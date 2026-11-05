"""Privileged, local-only lifecycle manager. Never imports generated Python."""
import base64
import hashlib
import hmac
import http.client
import ipaddress
import json
import os
import re
import secrets
import shutil
import sqlite3
import ssl
import stat
import string
import subprocess
import threading
import time
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(os.environ.get("HTMLAPP_RUNTIME_ROOT", "/var/lib/htmlapp-runtime/workspaces"))
STATE = Path(os.environ.get("HTMLAPP_RUNTIME_STATE", "/var/lib/htmlapp-runtime"))
ORIGIN = "https://htmlapp.hostish.site"
IMAGE = "htmlapp-python:v2"
RUNTIME = "htmlapp-runsc"
MAX_APPS = 6
MAX_TENANT_APPS = 3
APP_ID = re.compile(r"^[A-Z2-7]{12}$")
REVISION = re.compile(r"^[a-f0-9]{24}$")
ROUTE = re.compile(r"^/(?:[A-Za-z0-9_-]+|\{[A-Za-z_][A-Za-z0-9_]*\})(?:/(?:[A-Za-z0-9_-]+|\{[A-Za-z_][A-Za-z0-9_]*\}))*$")
MAX_REQUEST = 160000


class Failure(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message


def encode(value):
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode()


def sha(value):
    return hashlib.sha256(value.encode()).hexdigest()


def matches(key, expected):
    return bool(expected) and hmac.compare_digest(sha(key), expected)


def command(*args, timeout=30, check=True):
    result = subprocess.run(list(args), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=timeout, env={"PATH": "/usr/sbin:/usr/bin:/sbin:/bin"})
    if result.returncode:
        if check:
            # Do not expose source, credentials, container environment, or host paths.
            detail = re.sub(r"[A-Za-z0-9_-]{20,}", "[redacted]", result.stderr[:2000]).strip()
            label = " ".join(args[:2])
            raise Failure(503, f"{label} failed with exit {result.returncode}. {detail}")
        return ""
    return result.stdout.strip()


def fields(body, required, optional=()):
    if not isinstance(body, dict) or set(required) - body.keys() or body.keys() - set(required) - set(optional):
        raise Failure(400, "Unexpected or missing fields.")


def validate_bundle(body):
    fields(body, {"source", "manifest"})
    source, manifest = body["source"], body["manifest"]
    if not isinstance(source, str) or not 1 <= len(source.encode()) <= 100000:
        raise Failure(400, "source must be a Python file of at most 100000 bytes.")
    fields(manifest, {"sdkVersion", "schemaVersion", "routes", "checks"}, {"migrations", "outboundDomains"})
    if manifest["sdkVersion"] != 2 or type(manifest["schemaVersion"]) is not int or not 1 <= manifest["schemaVersion"] <= 10000:
        raise Failure(400, "Unsupported SDK or schema version.")
    routes = manifest["routes"]
    if not isinstance(routes, list) or not 1 <= len(routes) <= 40:
        raise Failure(400, "Declare 1 to 40 routes.")
    seen = set()
    for route in routes:
        fields(route, {"method", "path", "access"})
        if (route["method"] not in ("GET", "POST", "PUT", "PATCH", "DELETE") or
                not isinstance(route["path"], str) or not ROUTE.fullmatch(route["path"]) or
                route["path"].startswith("/_platform") or route["access"] not in ("public", "app", "session")):
            raise Failure(400, "Invalid route contract.")
        pair = (route["method"], route["path"])
        if pair in seen:
            raise Failure(400, "Duplicate route.")
        seen.add(pair)
    checks = manifest["checks"]
    if not isinstance(checks, list) or not 1 <= len(checks) <= 8:
        raise Failure(400, "Declare 1 to 8 read-only health checks.")
    for check in checks:
        fields(check, {"path", "expect"})
        if (not isinstance(check["path"], str) or not safe_path(check["path"]) or
                type(check["expect"]) is not int or check["expect"] not in (200, 401, 403, 404)):
            raise Failure(400, "Invalid read-only check.")
    migrations = manifest.get("migrations", [])
    if not isinstance(migrations, list) or len(migrations) > 20 or any(not isinstance(s, str) or len(s) > 16000 for s in migrations):
        raise Failure(400, "Invalid SQLite migrations.")
    domains = manifest.get("outboundDomains", [])
    if not isinstance(domains, list) or len(domains) > 8:
        raise Failure(400, "Declare at most eight outbound HTTPS domains.")
    for domain in domains:
        if not isinstance(domain, str) or not re.fullmatch(r"(?=.{4,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}", domain):
            raise Failure(400, "Use exact lowercase DNS domains for outbound HTTPS.")
    if len(encode(manifest)) > 32000:
        raise Failure(413, "Manifest too large.")
    return source, manifest


def safe_path(path):
    if not isinstance(path, str) or len(path) > 2048 or not path.startswith("/") or path.startswith("//"):
        return False
    # Avoid double decoding and route confusion between Hostish, gateway and worker.
    if any(ord(c) < 32 for c in path) or "#" in path:
        return False
    parsed = urlsplit(path)
    if "%" in parsed.path or "\\" in parsed.path:
        return False
    return not any(part in (".", "..", "") for part in parsed.path.split("/")[1:])


def copy_data(source, target):
    """Copy stopped app data without following links into the host filesystem."""
    target.mkdir(mode=0o700)
    for current, directories, files in os.walk(source, followlinks=False):
        relative = Path(current).relative_to(source)
        for name in directories:
            entry = Path(current) / name
            if not stat.S_ISDIR(entry.lstat().st_mode):
                raise Failure(400, "App data contains an unsupported filesystem object.")
            (target / relative / name).mkdir(mode=0o700)
        for name in files:
            entry = Path(current) / name
            fd = os.open(entry, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
            try:
                info = os.fstat(fd)
                if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
                    raise Failure(400, "App data contains an unsupported filesystem object.")
                with os.fdopen(os.dup(fd), "rb") as incoming, (target / relative / name).open("xb") as outgoing:
                    shutil.copyfileobj(incoming, outgoing, 65536)
            finally:
                os.close(fd)


class Manager:
    def __init__(self, engine=None, state=STATE, root=ROOT, owner=None, provision=None, push=None):
        self.state, self.root = Path(state), Path(root)
        self.state.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.owner = owner or os.environ["HTMLAPP_OWNER_KEY"]
        self.provision = provision or os.environ.get("HTMLAPP_PROVISION_KEY", "")
        self.push = push
        self.lock = threading.RLock()
        self.engine = engine or Engine(self)
        self.brokers = {}
        self.rate = {}
        with self.db() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS enrollments (hash TEXT PRIMARY KEY,label TEXT,active INTEGER,max_apps INTEGER);
                CREATE TABLE IF NOT EXISTS apps (
                    project INTEGER PRIMARY KEY AUTOINCREMENT,id TEXT UNIQUE,tenant TEXT,client TEXT,
                    name TEXT,revision INTEGER DEFAULT 0,current TEXT,previous TEXT,pending TEXT,
                    state TEXT DEFAULT 'new',deleted INTEGER DEFAULT 0,
                    broker TEXT,key_generation INTEGER NOT NULL DEFAULT 0, UNIQUE(tenant,client));
                CREATE TABLE IF NOT EXISTS devices (
                    app TEXT,resource TEXT,subject TEXT,device TEXT,
                    PRIMARY KEY(app,resource,subject,device));
                CREATE TABLE IF NOT EXISTS pushes (app TEXT,resource TEXT,minute INTEGER,count INTEGER,
                    PRIMARY KEY(app,resource));
                CREATE TABLE IF NOT EXISTS push_jobs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, app TEXT,resource TEXT,subject TEXT,device TEXT,
                    title TEXT,body TEXT,attempts INTEGER DEFAULT 0,next_try INTEGER,created INTEGER);
            """)

            if self.provision:
                db.execute("INSERT OR IGNORE INTO enrollments VALUES(?,?,1,?)", (sha(self.provision), "Initial device secret", MAX_TENANT_APPS))

    def accepts_enrollment(self, token):
        with self.db() as db:
            row = db.execute("SELECT * FROM enrollments WHERE hash=? AND active=1", (sha(token),)).fetchone()
        return dict(row) if row else None

    @contextmanager
    def db(self):
        db = sqlite3.connect(self.state / "runtime.sqlite3", timeout=10)
        db.row_factory = sqlite3.Row
        try:
            yield db
            db.commit()
        except BaseException:
            db.rollback()
            raise
        finally:
            db.close()

    def keys(self, app_id):
        with self.db() as db:
            row = db.execute("SELECT key_generation FROM apps WHERE id=?", (app_id,)).fetchone()
        generation = row[0] if row else 0
        def derive(scope, length):
            raw = hmac.digest(self.owner.encode(), ("htmlapp.v2:" + app_id + ":" + str(generation) + ":" + scope).encode(), "sha256")[:length]
            return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()
        return {"managementKey": derive("management", 15), "publicKey": derive("runtime", 24)}

    def row(self, app_id, include_deleted=False):
        if not APP_ID.fullmatch(app_id):
            raise Failure(404, "Backend not found.")
        with self.db() as db:
            row = db.execute("SELECT * FROM apps WHERE id=?", (app_id,)).fetchone()
        if not row or (row["deleted"] and not include_deleted):
            raise Failure(404, "Backend not found.")
        return dict(row)

    def require_manager(self, app_id, token, deleted=False):
        row = self.row(app_id, deleted)
        if not hmac.compare_digest(token, self.keys(app_id)["managementKey"]):
            raise Failure(403, "Backend management authorization required.")
        return row

    def throttle(self, identity, limit):
        now = int(time.time()) // 60
        key = (identity, now)
        with self.lock:
            if len(self.rate) > 2048:
                self.rate = {k: v for k, v in self.rate.items() if k[1] == now}
            count = self.rate.get(key, 0)
            if count >= limit:
                raise Failure(429, "Request limit reached. Retry next minute.")
            self.rate[key] = count + 1

    def create(self, token, body):
        enrollment = self.accepts_enrollment(token)
        if not enrollment:
            raise Failure(403, "A valid VPS enrollment secret is required.")
        fields(body, {"clientID", "name", "source", "manifest"})
        if not isinstance(body["clientID"], str) or not re.fullmatch(r"[A-Za-z0-9_-]{8,80}", body["clientID"]):
            raise Failure(400, "Use a stable clientID for safe retries.")
        if not isinstance(body["name"], str) or not 1 <= len(body["name"]) <= 80:
            raise Failure(400, "Invalid app name.")
        validate_bundle({"source": body["source"], "manifest": body["manifest"]})
        tenant = sha(token)
        with self.lock, self.db() as db:
            prior = db.execute("SELECT * FROM apps WHERE tenant=? AND client=?", (tenant, body["clientID"])).fetchone()
            if prior:
                if prior["deleted"]:
                    raise Failure(410, "This deployment was deleted.")
                app_id = prior["id"]
            else:
                live = db.execute("SELECT count(*) FROM apps WHERE deleted=0").fetchone()[0]
                tenant_live = db.execute("SELECT count(*) FROM apps WHERE tenant=? AND deleted=0", (tenant,)).fetchone()[0]
                if live >= MAX_APPS or tenant_live >= enrollment["max_apps"]:
                    raise Failure(409, "Deployment capacity reached.")
                if db.execute("SELECT count(*) FROM apps").fetchone()[0] >= 4096:
                    raise Failure(409, "Deployment ID capacity reached. Administrator maintenance required.")
                app_id = "".join(secrets.choice(string.ascii_uppercase + "234567") for _ in range(12))
                db.execute("INSERT INTO apps(id,tenant,client,name,broker) VALUES(?,?,?,?,?)",
                           (app_id, tenant, body["clientID"], body["name"], secrets.token_urlsafe(32)))
        row = self.row(app_id)
        if row["revision"] == 0:
            self.deploy(app_id, self.keys(app_id)["managementKey"], {"baseRevision": 0, "source": body["source"], "manifest": body["manifest"]})
        return {**self.details(app_id), **self.keys(app_id)}

    def directory(self, row, revision=None):
        revision = revision or row["current"]
        if not revision or not REVISION.fullmatch(revision):
            raise Failure(503, "No active revision.")
        return self.root / row["id"] / revision

    def details(self, app_id):
        row = self.row(app_id)
        return {"appID": app_id, "name": row["name"], "revision": row["revision"], "state": row["state"],
                "apiBaseURL": ORIGIN + "/v2/apps/" + app_id + "/api",
                "schemaURL": ORIGIN + "/v2/apps/" + app_id + "/schema",
                "workspaceLimitBytes": 1998848, "pushConfigured": self.push is not None}

    def bundle(self, row):
        directory = self.directory(row)
        return {"source": (directory / "server.py").read_text(), "manifest": json.loads((directory / "manifest.json").read_text())}

    def deploy(self, app_id, token, body):
        fields(body, {"baseRevision", "source", "manifest"})
        source, manifest = validate_bundle({"source": body["source"], "manifest": body["manifest"]})
        with self.lock:
            row = self.require_manager(app_id, token)
            if type(body["baseRevision"]) is not int or row["revision"] != body["baseRevision"]:
                raise Failure(409, "Revision changed. Refresh before editing.")
            old = self.bundle(row) if row["current"] else None
            if old and manifest["schemaVersion"] < old["manifest"]["schemaVersion"]:
                raise Failure(409, "Schema downgrade requires an explicit compatible migration.")
            candidate = secrets.token_hex(12)
            with self.db() as db:
                db.execute("UPDATE apps SET state='deploying',pending=? WHERE id=?", (candidate, app_id))
            try:
                self.engine.stop(row)
                self.engine.stage(row, candidate, source, manifest)
                self.engine.start(row, candidate)
                self.engine.check(row, candidate, manifest)
                with self.db() as db:
                    db.execute("UPDATE apps SET current=?,previous=?,pending=NULL,revision=revision+1,state='running' WHERE id=?",
                               (candidate, row["current"], app_id))
            except BaseException as error:
                self.engine.remove(row, candidate)
                with self.db() as db:
                    db.execute("UPDATE apps SET pending=NULL,state=? WHERE id=?", ("running" if row["current"] else "failed", app_id))
                if row["current"]:
                    try:
                        self.engine.start(row, row["current"])
                        self.engine.check(row, row["current"], old["manifest"])
                    except Exception:
                        with self.db() as db:
                            db.execute("UPDATE apps SET state='failed' WHERE id=?", (app_id,))
                if isinstance(error, OSError) and error.errno in (28, 122):
                    raise Failure(507, "Workspace quota exhausted. Free space before deploying.") from None
                raise
            # Keep previous source, but only the current data remains live.
            try:
                self.engine.cleanup(self.row(app_id))
            except (Failure, OSError):
                pass  # The committed app remains usable; recovery retries cleanup.
            return self.details(app_id)

    def rollback(self, app_id, token, body):
        fields(body, {"baseRevision"})
        with self.lock:
            row = self.require_manager(app_id, token)
            if not row["previous"]:
                raise Failure(409, "No previous source revision is available.")
            previous = self.bundle({**row, "current": row["previous"]})
            current = self.bundle(row)
            if previous["manifest"]["schemaVersion"] != current["manifest"]["schemaVersion"]:
                raise Failure(409, "Schema changed. Generate a forward repair instead of losing data.")
            # Old code with current data, never an old data snapshot.
            previous["manifest"]["migrations"] = []
            return self.deploy(app_id, token, {"baseRevision": body["baseRevision"], **previous})

    def restart(self, app_id, token, body):
        fields(body, {"baseRevision"})
        with self.lock:
            row = self.require_manager(app_id, token)
            if type(body["baseRevision"]) is not int or body["baseRevision"] != row["revision"] or not row["current"]:
                raise Failure(409, "Refresh the current revision before restarting.")
            self.engine.stop(row)
            try:
                self.engine.start(row, row["current"])
                self.engine.check(row, row["current"], self.bundle(row)["manifest"])
            except Exception:
                with self.db() as db:
                    db.execute("UPDATE apps SET state='failed' WHERE id=?", (app_id,))
                raise
            with self.db() as db:
                db.execute("UPDATE apps SET state='running' WHERE id=?", (app_id,))
            return self.details(app_id)

    def delete(self, app_id, token):
        with self.lock:
            row = self.require_manager(app_id, token, deleted=True)
            with self.db() as db:
                db.execute("UPDATE apps SET deleted=1,state='deleted' WHERE id=?", (app_id,))
                db.execute("DELETE FROM devices WHERE app=?", (app_id,))
                db.execute("DELETE FROM push_jobs WHERE app=?", (app_id,))
            self.engine.destroy(row)
            return {"deleted": True}

    def proxy(self, app_id, method, path, token, session, body):
        if not safe_path(path) or urlsplit(path).path.startswith("/_platform"):
            raise Failure(400, "Invalid API path.")
        row = self.row(app_id)
        if row["state"] != "running":
            raise Failure(503, "Backend is starting, updating, or unavailable.")
        self.throttle("runtime:" + app_id, 120)
        route = None
        for entry in self.bundle(row)["manifest"]["routes"]:
            pattern = re.sub(r"\\\{[A-Za-z_][A-Za-z0-9_]*\\\}", "[^/]+", re.escape(entry["path"]))
            if entry["method"] == method and re.fullmatch(pattern, urlsplit(path).path):
                route = entry
                break
        if not route:
            raise Failure(404, "Route not declared by this app.")
        if route["access"] != "public" and not hmac.compare_digest(token, self.keys(app_id)["publicKey"]):
            raise Failure(403, "App access key required.")
        return self.engine.request(row, row["current"], method, path, body, session=session)

    def device(self, app_id, token, body, delete=False):
        fields(body, {"session", "deviceToken"})
        row = self.row(app_id)
        if not hmac.compare_digest(token, self.keys(app_id)["publicKey"]):
            raise Failure(403, "App access key required.")
        if not isinstance(body["deviceToken"], str) or len(body["deviceToken"]) % 2 or not re.fullmatch(r"[a-fA-F0-9]{64,256}", body["deviceToken"]):
            raise Failure(400, "Invalid APNs token.")
        status, identity = self.engine.request(row, row["current"], "POST", "/_platform/session", {"session": body["session"]}, internal=True)
        if status != 200:
            raise Failure(401, "A current resource session is required.")
        with self.db() as db:
            if not delete:
                db.execute("DELETE FROM devices WHERE app=? AND resource=? AND device=?",
                           (app_id, identity["resource"], body["deviceToken"]))
            count = db.execute("SELECT count(*) FROM devices WHERE app=?", (app_id,)).fetchone()[0]
            if not delete and count >= 100:
                raise Failure(409, "Device subscription limit reached.")
            values = (app_id, identity["resource"], identity["subject"], body["deviceToken"])
            if delete:
                db.execute("DELETE FROM devices WHERE app=? AND resource=? AND subject=? AND device=?", values)
                db.execute("DELETE FROM push_jobs WHERE app=? AND resource=? AND subject=? AND device=?", values)
            else:
                db.execute("INSERT OR IGNORE INTO devices VALUES(?,?,?,?)", values)
        return {"subscribed": not delete, "pushConfigured": self.push is not None}

    def fetch(self, app_id, body):
        fields(body, {"domain", "path", "method"}, {"json", "headers"})
        row = self.row(app_id)
        if row["state"] != "running":
            raise Failure(409, "Backend validation is in progress. External effects are disabled.")
        domain = body["domain"]
        if domain not in self.bundle(row)["manifest"].get("outboundDomains", []):
            raise Failure(403, "Outbound domain is not declared by this app.")
        if body["method"] not in ("GET", "POST", "PUT", "PATCH", "DELETE") or not safe_path(body["path"]):
            raise Failure(400, "Invalid outbound request.")
        headers = body.get("headers", {})
        if not isinstance(headers, dict) or any(k not in ("Accept", "Content-Type", "Authorization") or
                not isinstance(v, str) or len(v) > 2048 or any(ord(c) < 32 for c in v) for k, v in headers.items()):
            raise Failure(400, "Unsupported outbound headers.")
        self.throttle("fetch:" + app_id, 30)
        # Resolve once, validate every answer, and connect to that exact IP.
        # DNS rebinding and redirects cannot redirect a request into the LAN.
        addresses = command("getent", "ahostsv4", domain, timeout=3).splitlines()
        addresses = sorted({line.split()[0] for line in addresses if line.split()})
        if not addresses or any(not ipaddress.ip_address(address).is_global for address in addresses):
            raise Failure(403, "Outbound endpoints must resolve exclusively to public IP addresses.")
        connection = http.client.HTTPSConnection(domain, 443, timeout=3)
        import socket
        raw = socket.create_connection((addresses[0], 443), timeout=3)
        sockets = [raw]
        def expire():
            try:
                sockets[0].shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        deadline = threading.Timer(7, expire)
        deadline.daemon = True
        deadline.start()
        try:
            connection.sock = ssl.create_default_context().wrap_socket(raw, server_hostname=domain)
            sockets[0] = connection.sock
            payload = encode(body["json"]) if "json" in body else None
            if payload and len(payload) > 16384:
                raise Failure(413, "Outbound body too large.")
            if payload is not None:
                headers.setdefault("Content-Type", "application/json")
            connection.request(body["method"], body["path"], body=payload, headers=headers)
            response = connection.getresponse()
            data = response.read(65537)
            if len(data) > 65536:
                raise Failure(413, "Outbound response too large.")
            if 300 <= response.status < 400:
                raise Failure(502, "Outbound redirects are disabled. Use the final approved domain.")
            try:
                value = json.loads(data)
            except ValueError:
                value = data.decode("utf-8", errors="replace")
            return {"status": response.status, "data": value}
        finally:
            deadline.cancel()
            connection.close()
            raw.close()

    def notify(self, app_id, body):
        fields(body, {"resource", "title", "body"})
        if any(not isinstance(body[k], str) for k in body) or len(body["title"]) > 80 or len(body["body"].encode()) > 1000:
            raise Failure(400, "Invalid notification.")
        if self.push is None:
            raise Failure(503, "APNs is not configured on the VPS.")
        row = self.row(app_id)
        if row["state"] != "running":
            raise Failure(409, "Backend validation is in progress. External effects are disabled.")
        with self.lock, self.db() as db:
            minute = int(time.time()) // 60
            prior = db.execute("SELECT minute,count FROM pushes WHERE app=? AND resource=?", (app_id, body["resource"])).fetchone()
            count = prior[1] if prior and prior[0] == minute else 0
            if count >= 6:
                raise Failure(429, "Resource notification limit reached.")
            self.throttle("push:" + app_id, 30)
            db.execute("INSERT OR REPLACE INTO pushes VALUES(?,?,?,?)", (app_id, body["resource"], minute, count + 1))
            devices = db.execute("SELECT * FROM devices WHERE app=? AND resource=?", (app_id, body["resource"])).fetchall()
        with self.lock, self.db() as db:
            pending = db.execute("SELECT count(*) FROM push_jobs WHERE app=?", (app_id,)).fetchone()[0]
            if pending + len(devices) > 100:
                raise Failure(429, "Notification queue is full. Retry later.")
            now = int(time.time())
            for device in devices:
                db.execute("INSERT INTO push_jobs(app,resource,subject,device,title,body,next_try,created) VALUES(?,?,?,?,?,?,?,?)",
                    (app_id, body["resource"], device["subject"], device["device"], body["title"], body["body"], now, now))
        return {"queued": len(devices)}

    def deliver_notifications(self):
        while True:
            time.sleep(1)
            with self.db() as db:
                job = db.execute("SELECT * FROM push_jobs WHERE next_try<=? ORDER BY id LIMIT 1", (int(time.time()),)).fetchone()
            if not job:
                continue
            retry = False
            try:
                with self.db() as db:
                    subscribed = db.execute("SELECT 1 FROM devices WHERE app=? AND resource=? AND subject=? AND device=?",
                                            (job["app"], job["resource"], job["subject"], job["device"])).fetchone()
                if not subscribed:
                    with self.db() as db:
                        db.execute("DELETE FROM push_jobs WHERE id=?", (job["id"],))
                    continue
                row = self.row(job["app"])
                if row["state"] != "running":
                    raise Failure(503, "Backend is updating or unavailable.")
                status, member = self.engine.request(row, row["current"], "POST", "/_platform/member",
                    {"resource": job["resource"], "subject": job["subject"]}, internal=True)
                if status != 200:
                    raise Failure(503, "Could not confirm current membership.")
                if member.get("active") and self.push:
                    self.push(job["device"], {"aps": {"alert": {"title": job["title"], "body": job["body"]}, "sound": "default"},
                        "htmlapp_backend_id": job["app"], "htmlapp_resource_id": job["resource"],
                        "htmlapp_notification_id": str(job["id"])})
            except Exception as error:
                status = getattr(error, "status", 503)
                retry = status != 404 and status != 410 and job["attempts"] < 3 and int(time.time()) - job["created"] < 3600
                if status == 410:
                    with self.db() as db:
                        db.execute("DELETE FROM devices WHERE app=? AND device=?", (job["app"], job["device"]))
            with self.db() as db:
                if retry:
                    db.execute("UPDATE push_jobs SET attempts=attempts+1,next_try=? WHERE id=?",
                               (int(time.time()) + 10 * (3 ** job["attempts"]), job["id"]))
                else:
                    db.execute("DELETE FROM push_jobs WHERE id=?", (job["id"],))

    def recover(self):
        with self.lock, self.db() as db:
            rows = [dict(r) for r in db.execute("SELECT * FROM apps")]
        for row in rows:
            try:
                if row["deleted"]:
                    self.engine.destroy(row)
                    continue
                if row["pending"]:
                    self.engine.remove(row, row["pending"])
                if row["current"]:
                    self.engine.start(row, row["current"])
                    self.engine.check(row, row["current"], self.bundle(row)["manifest"])
                    self.engine.cleanup(row)
                with self.db() as db:
                    db.execute("UPDATE apps SET pending=NULL,state=? WHERE id=?", ("running" if row["current"] else "failed", row["id"]))
            except Exception:
                with self.db() as db:
                    db.execute("UPDATE apps SET state='failed' WHERE id=?", (row["id"],))


    def monitor(self):
        failures = {}
        while True:
            time.sleep(20)
            with self.db() as db:
                rows = [dict(row) for row in db.execute("SELECT * FROM apps WHERE deleted=0 AND state='running'")]
            for row in rows:
                try:
                    status, result = self.engine.request(row, row["current"], "GET", "/_platform/health", internal=True)
                    if status == 200 and result.get("ready"):
                        failures.pop(row["id"], None)
                        continue
                except Exception:
                    pass
                failures[row["id"]] = failures.get(row["id"], 0) + 1
                if failures[row["id"]] >= 3:
                    with self.db() as db:
                        db.execute("UPDATE apps SET state='failed' WHERE id=? AND current=? AND state='running'",
                                   (row["id"], row["current"]))


class Engine:
    def __init__(self, manager):
        self.manager = manager

    @staticmethod
    def name(row, revision):
        return "htmlapp-v2-" + row["id"].lower() + "-" + revision

    @staticmethod
    def network(row):
        return "htmlapp-v2-" + row["id"].lower()

    def network_info(self, row):
        result = command("docker", "network", "inspect", self.network(row), check=False)
        if not result:
            command("docker", "network", "create", "--internal", "--label", "htmlapp.runtime=v2",
                    "--opt", "com.docker.network.bridge.name=ha" + row["id"].lower(), self.network(row))
            result = command("docker", "network", "inspect", self.network(row))
        info = json.loads(result)[0]
        if not info["Internal"] or info.get("EnableIPv6"):
            raise Failure(503, "Runtime network policy mismatch.")
        gateway = info["IPAM"]["Config"][0]["Gateway"]
        interface = "ha" + row["id"].lower()
        # Restrict access to host services and all forwarded traffic. No shared
        # Docker socket, host networking, published ports or arbitrary mounts.
        rules = [
            ("INPUT", "-i", interface, "-d", gateway, "-p", "tcp", "--dport", "45808", "-j", "ACCEPT"),
            ("INPUT", "-i", interface, "-m", "conntrack", "--ctstate", "ESTABLISHED,RELATED", "-j", "ACCEPT"),
            ("INPUT", "-i", interface, "-j", "DROP"),
            ("DOCKER-USER", "-i", interface, "-j", "DROP"),
        ]
        # Insert in reverse order so the broker and return-traffic exceptions
        # precede the drop rule, even on reconfiguration after Docker restarts.
        for rule in reversed(rules):
            if subprocess.run(["iptables", "-C", *rule], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
                command("iptables", "-I", rule[0], "1", *rule[1:])
        for chain in ("INPUT", "FORWARD"):
            rule = (chain, "-i", interface, "-j", "DROP")
            if subprocess.run(["ip6tables", "-C", *rule], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
                command("ip6tables", "-I", chain, "1", *rule[1:])
        if row["id"] not in self.manager.brokers:
            server = BrokerServer((gateway, 45808), self.manager, row["id"])
            threading.Thread(target=server.serve_forever, daemon=True).start()
            self.manager.brokers[row["id"]] = server
        return gateway

    def stage(self, row, revision, source, manifest):
        base = self.manager.root / row["id"]
        base.mkdir(mode=0o755, exist_ok=True)
        base.chmod(0o755)
        command("xfs_quota", "-x", "-c", f"project -s -p {base} {row['project']}", str(self.manager.root))
        command("xfs_quota", "-x", "-c", f"limit -p bsoft=1952k bhard=1952k isoft=256 ihard=256 {row['project']}", str(self.manager.root))
        target = base / revision
        target.mkdir(mode=0o755)
        target.chmod(0o755)
        (target / "server.py").write_text(source)
        (target / "manifest.json").write_bytes(encode(manifest))
        data = target / "data"
        if row["current"]:
            copy_data(self.manager.directory(row) / "data", data)
        else:
            data.mkdir(mode=0o700)
        # Temporary files are charged to the same project quota as app data.
        (data / "tmp").mkdir(mode=0o700, exist_ok=True)
        uid = 200000 + row["project"]
        for current, directories, files in os.walk(data):
            os.chown(current, uid, uid)
            for name in files:
                os.chown(Path(current) / name, uid, uid, follow_symlinks=False)
        for file in (target / "server.py", target / "manifest.json"):
            file.chmod(0o444)

    def start(self, row, revision):
        gateway = self.network_info(row)
        name = self.name(row, revision)
        existing = command("docker", "inspect", name, check=False)
        if existing:
            info = json.loads(existing)[0]
            if info["State"]["Running"]:
                return
            command("docker", "rm", "-f", name)
        target = self.manager.directory(row, revision)
        image = (self.manager.state / "image-id").read_text().strip()
        if not re.fullmatch(r"sha256:[a-f0-9]{64}", image):
            raise Failure(503, "Pinned runtime image is invalid.")
        uid = str(200000 + row["project"])
        command("docker", "run", "-d", "--name", name, "--runtime", RUNTIME,
                "--label", "htmlapp.runtime=v2", "--restart", "on-failure:5", "--network", self.network(row),
                "--read-only", "--cap-drop", "ALL", "--security-opt", "no-new-privileges=true",
                "--user", uid + ":" + uid, "--memory", "256m", "--memory-swap", "256m", "--cpus", "0.35",
                "--pids-limit", "96", "--ulimit", "nofile=128:128", "--shm-size", "64k",
                "--log-driver", "local", "--log-opt", "max-size=64k", "--log-opt", "max-file=1", "--log-opt", "compress=false",
                "--mount", f"type=bind,source={target},target=/code,readonly",
                "--mount", f"type=bind,source={target / 'data'},target=/data",
                "--mount", f"type=bind,source={target / 'data' / 'tmp'},target=/tmp",
                "--env", "HTMLAPP_BROKER_URL=http://" + gateway + ":45808",
                "--env", "HTMLAPP_BROKER_TOKEN=" + row["broker"], "--env", "HTMLAPP_ID=" + row["id"],
                image, timeout=40)

    def stop(self, row):
        if row["current"]:
            name = self.name(row, row["current"])
            existing = command("docker", "inspect", name, check=False)
            if existing:
                command("docker", "stop", "--time", "5", name)
                if json.loads(command("docker", "inspect", name))[0]["State"]["Running"]:
                    raise Failure(503, "Could not quiesce the old backend. Update aborted.")

    def request(self, row, revision, method, path, body=None, session="", internal=False):
        name = self.name(row, revision)
        value = command("docker", "inspect", "--format", "{{json .NetworkSettings.Networks}}", name)
        networks = json.loads(value) or {}
        address = networks.get(self.network(row), {}).get("IPAddress", "")
        try:
            private = ipaddress.ip_address(address).is_private
        except ValueError:
            raise Failure(503, "Container has no address yet or has exited.") from None
        if not private:
            raise Failure(503, "Runtime network address mismatch.")
        connection = http.client.HTTPConnection(address, 8080, timeout=12)
        headers = {"Content-Type": "application/json", "X-HTMLApp-Session": session}
        if internal:
            headers["Authorization"] = "Bearer " + row["broker"]
        try:
            connection.request(method, path, body=encode(body) if body is not None else None, headers=headers)
            response = connection.getresponse()
            data = response.read(131073)
            if len(data) > 131072:
                raise Failure(502, "Backend response exceeds the gateway limit.")
            return response.status, json.loads(data)
        except (OSError, ValueError, http.client.HTTPException):
            raise Failure(503, "Backend is unavailable or returned invalid JSON.") from None
        finally:
            connection.close()

    def check(self, row, revision, manifest):
        ready = False
        for attempt in range(30):
            try:
                status, payload = self.request(row, revision, "GET", "/_platform/health", internal=True)
                if status == 200 and payload.get("ready"):
                    ready = True
                    break
            except Failure:
                pass
            time.sleep(0.3)
        if not ready:
            raise Failure(422, "Backend failed to start. " + self.diagnostic(row, revision))
        for check in manifest["checks"]:
            status, _ = self.request(row, revision, "GET", check["path"])
            if status != check["expect"]:
                raise Failure(422, f"GET {check['path']} returned HTTP {status}, expected {check['expect']}. Previous release retained.")

    def diagnostic(self, row, revision):
        name = self.name(row, revision)
        state = command("docker", "inspect", "--format", "{{json .State}}", name, check=False)
        summary = ""
        if state:
            value = json.loads(state)
            summary = f"Container status {value.get('Status')}, exit {value.get('ExitCode')}, OOM {value.get('OOMKilled')}. "
            if value.get("Error"):
                detail = re.sub(r"[A-Za-z0-9_-]{20,}", "[redacted]", str(value["Error"])[:1000])
                summary += detail + " "
        result = subprocess.run(["docker", "logs", "--tail", "30", name], capture_output=True, text=True, timeout=10)
        logs = result.stdout + "\n" + result.stderr
        allowed = {"SyntaxError", "IndentationError", "ImportError", "ModuleNotFoundError", "RuntimeError", "OperationalError", "ProgrammingError", "ValueError", "NameError", "TypeError", "AttributeError", "KeyError", "ApplicationError"}
        for line in reversed(logs.splitlines()):
            if line.startswith("HTMLAPP_STARTUP "):
                try:
                    value = json.loads(line[16:])
                    if value.get("kind") in allowed and type(value.get("line")) is int and 0 <= value["line"] <= 100000:
                        return summary + f"{value['kind']} at server.py line {value['line']}."
                except (ValueError, TypeError):
                    pass
        missing = re.search(r"ModuleNotFoundError: No module named '([A-Za-z0-9_.]+)'", logs)
        if missing:
            return summary + "Missing Python module " + missing[1] + "."
        return summary + "Verify the SDK import, app object and route manifest."

    def remove(self, row, revision):
        if not revision or not REVISION.fullmatch(revision):
            return
        name = self.name(row, revision)
        if command("docker", "inspect", name, check=False):
            command("docker", "rm", "-f", name)
        path = self.manager.directory(row, revision)
        if path.exists():
            shutil.rmtree(path)

    def cleanup(self, row):
        base = self.manager.root / row["id"]
        if not base.exists():
            return
        for entry in base.iterdir():
            if not REVISION.fullmatch(entry.name):
                continue
            if entry.name == row["current"]:
                continue
            command("docker", "rm", "-f", self.name(row, entry.name), check=False)
            if entry.name == row["previous"]:
                if (entry / "data").exists():
                    shutil.rmtree(entry / "data")
            else:
                shutil.rmtree(entry)

    def destroy(self, row):
        base = self.manager.root / row["id"]
        if base.exists():
            for entry in base.iterdir():
                if REVISION.fullmatch(entry.name):
                    self.remove(row, entry.name)
            base.rmdir()
        server = self.manager.brokers.pop(row["id"], None)
        if server:
            server.shutdown()
            server.server_close()
        command("docker", "network", "rm", self.network(row), check=False)


class BrokerServer(ThreadingHTTPServer):
    daemon_threads = True
    def __init__(self, address, manager, app_id):
        self.manager, self.app_id = manager, app_id
        self.slots = threading.BoundedSemaphore(4)
        super().__init__(address, BrokerHandler)

    def process_request(self, request, address):
        if not self.slots.acquire(blocking=False):
            request.close()
            return
        request.settimeout(5)
        try:
            super().process_request(request, address)
        except BaseException:
            self.slots.release()
            raise

    def process_request_thread(self, request, address):
        try:
            super().process_request_thread(request, address)
        finally:
            self.slots.release()


class BrokerHandler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        status, payload = 200, {}
        try:
            manager = self.server.manager
            row = manager.row(self.server.app_id)
            if not hmac.compare_digest(self.headers.get("Authorization", ""), "Bearer " + row["broker"]):
                raise Failure(403, "Broker authorization required.")
            size = int(self.headers.get("Content-Length", "0"))
            if not 0 < size <= 20000 or self.headers.get("Transfer-Encoding"):
                raise Failure(413, "Invalid broker request size.")
            body = json.loads(self.rfile.read(size))
            if self.path == "/notify":
                payload = manager.notify(row["id"], body)
            elif self.path == "/fetch":
                payload = manager.fetch(row["id"], body)
            else:
                raise Failure(404, "Broker route not found.")
        except Failure as error:
            status, payload = error.status, {"error": error.message}
        except Exception:
            status, payload = 503, {"error": "Broker unavailable."}
        data = encode(payload)
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
