"""HTMLApp Python SDK v2. Application code runs only inside its sandbox."""
import base64
import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import threading
import time
import urllib.request
import urllib.error
from contextlib import contextmanager


class Error(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message


def encode(value):
    return json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":")).encode()


class Store:
    def __init__(self, path=None):
        self.path = path or os.environ.get("HTMLAPP_DATABASE", "/data/app.sqlite3")
        with self.transaction() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY,value BLOB NOT NULL);
                CREATE TABLE IF NOT EXISTS resources (id TEXT PRIMARY KEY,salt BLOB,verifier BLOB);
                CREATE TABLE IF NOT EXISTS members (resource TEXT,subject TEXT,active INTEGER DEFAULT 1,
                    PRIMARY KEY(resource,subject));
                CREATE TABLE IF NOT EXISTS sessions (hash TEXT PRIMARY KEY,resource TEXT,subject TEXT,expires INTEGER);
                CREATE TABLE IF NOT EXISTS attempts (resource TEXT PRIMARY KEY,window INTEGER,count INTEGER);
                CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY AUTOINCREMENT,resource TEXT,payload BLOB);
            """)

    @contextmanager
    def transaction(self):
        db = sqlite3.connect(self.path, timeout=3, isolation_level=None)
        db.row_factory = sqlite3.Row
        try:
            db.execute("PRAGMA journal_mode=DELETE")
            db.execute("PRAGMA foreign_keys=ON")
            db.execute("BEGIN IMMEDIATE")
            yield db
            db.commit()
        except BaseException:
            db.rollback()
            raise
        finally:
            db.close()

    def get(self, key, default=None):
        with self.transaction() as db:
            row = db.execute("SELECT value FROM kv WHERE key=?", (key,)).fetchone()
            return json.loads(row[0]) if row else default

    def put(self, key, value):
        data = encode(value)
        if len(data) > 131072 or not isinstance(key, str) or len(key) > 160:
            raise Error(413, "Item exceeds its size limit.")
        with self.transaction() as db:
            db.execute("INSERT OR REPLACE INTO kv VALUES(?,?)", (key, data))

    def delete(self, key):
        with self.transaction() as db:
            db.execute("DELETE FROM kv WHERE key=?", (key,))

    def publish(self, resource, value):
        data = encode(value)
        if len(data) > 16384:
            raise Error(413, "Event too large.")
        with self.transaction() as db:
            cursor = db.execute("INSERT INTO events(resource,payload) VALUES(?,?)", (resource, data))
            return cursor.lastrowid

    def events(self, resource, after=0, limit=100):
        with self.transaction() as db:
            rows = db.execute("SELECT id,payload FROM events WHERE resource=? AND id>? ORDER BY id LIMIT ?",
                              (resource, int(after), min(max(int(limit), 1), 100))).fetchall()
            return [{"id": row[0], "data": json.loads(row[1])} for row in rows]


class Auth:
    """Resource access codes, bounded guessing, revocable sessions. Not encryption."""
    def __init__(self, store):
        self.store = store

    @staticmethod
    def verifier(code, salt):
        return hashlib.scrypt(code.encode(), salt=salt, n=16384, r=8, p=1, dklen=32)

    def create(self, code):
        if not isinstance(code, str) or not 4 <= len(code) <= 128:
            raise Error(400, "Use an access code of 4 to 128 characters.")
        resource, salt = secrets.token_urlsafe(18), secrets.token_bytes(16)
        verifier = self.verifier(code, salt)
        with self.store.transaction() as db:
            db.execute("INSERT INTO resources VALUES(?,?,?)", (resource, salt, verifier))
        return {"resource": resource, **self.join(resource, code)}

    def join(self, resource, code):
        if not isinstance(code, str) or len(code) > 128:
            raise Error(400, "Invalid access code.")
        now = int(time.time())
        # Commit counters before the expensive check, including failed guesses.
        with self.store.transaction() as db:
            row = db.execute("SELECT * FROM resources WHERE id=?", (resource,)).fetchone()
            attempt = db.execute("SELECT * FROM attempts WHERE resource=?", (resource,)).fetchone()
            count = attempt["count"] if attempt and attempt["window"] == now // 300 else 0
            if count >= 5:
                raise Error(429, "Too many attempts for this resource. Try in five minutes.")
            # Unknown IDs cannot cause unlimited counter rows.
            if row:
                db.execute("INSERT OR REPLACE INTO attempts VALUES(?,?,?)", (resource, now // 300, count + 1))
        if not row or not hmac.compare_digest(self.verifier(code, row["salt"]), row["verifier"]):
            raise Error(403, "Access code or resource is incorrect.")
        subject, token = secrets.token_urlsafe(18), secrets.token_urlsafe(32)
        with self.store.transaction() as db:
            db.execute("DELETE FROM attempts WHERE resource=?", (resource,))
            db.execute("DELETE FROM sessions WHERE expires<?", (now,))
            db.execute("INSERT INTO members(resource,subject) VALUES(?,?)", (resource, subject))
            db.execute("INSERT INTO sessions VALUES(?,?,?,?)",
                       (hashlib.sha256(token.encode()).hexdigest(), resource, subject, now + 86400))
        return {"session": token, "subject": subject, "expiresAt": now + 86400}

    def require(self, token, resource=None):
        with self.store.transaction() as db:
            row = db.execute("""SELECT s.resource,s.subject,s.expires FROM sessions s JOIN members m
                ON m.resource=s.resource AND m.subject=s.subject
                WHERE s.hash=? AND s.expires>? AND m.active=1""",
                (hashlib.sha256(token.encode()).hexdigest(), int(time.time()))).fetchone()
        if not row or (resource is not None and resource != row["resource"]):
            raise Error(401, "Session expired, revoked, or invalid for this resource.")
        return dict(row)

    def is_member(self, resource, subject):
        with self.store.transaction() as db:
            row = db.execute("SELECT active FROM members WHERE resource=? AND subject=?", (resource, subject)).fetchone()
            return bool(row and row[0])

    def revoke(self, resource, subject):
        with self.store.transaction() as db:
            db.execute("UPDATE members SET active=0 WHERE resource=? AND subject=?", (resource, subject))
            db.execute("DELETE FROM sessions WHERE resource=? AND subject=?", (resource, subject))


class Request:
    def __init__(self, method, path, headers, body, query):
        self.method, self.path, self.headers, self.json, self.query = method, path, headers, body, query
        self.session = headers.get("X-HTMLApp-Session", "")
        self.identity = None
        self.params = {}


class App:
    def __init__(self, database=None):
        self.store = Store(database)
        self.auth = Auth(self.store)
        self.routes = []
        self.schedulers = []

    def route(self, method, path, access="session"):
        if method not in ("GET", "POST", "PUT", "PATCH", "DELETE") or access not in ("public", "app", "session"):
            raise ValueError("Invalid route method or access policy")
        if not re.fullmatch(r"/(?:[A-Za-z0-9_-]+|\{[A-Za-z_][A-Za-z0-9_]*\})(?:/(?:[A-Za-z0-9_-]+|\{[A-Za-z_][A-Za-z0-9_]*\}))*", path):
            raise ValueError("Routes must use safe segments, e.g. /items/{id}")
        def register(function):
            pattern = re.sub(r"\\\{([A-Za-z_][A-Za-z0-9_]*)\\\}", r"(?P<\1>[^/]+)", re.escape(path))
            self.routes.append((method, path, access, re.compile("^" + pattern + "$"), function))
            return function
        return register

    def schema(self):
        return [{"method": m, "path": p, "access": a} for m, p, a, _, _ in self.routes]

    def handle(self, request):
        for method, _, access, pattern, function in self.routes:
            match = pattern.fullmatch(request.path)
            if method == request.method and match:
                if access == "session":
                    request.identity = self.auth.require(request.session)
                request.params = match.groupdict()
                return function(request)
        raise Error(404, "Route not found.")

    def every(self, seconds):
        if not 30 <= seconds <= 86400:
            raise ValueError("Scheduled intervals must be between 30 seconds and a day")
        def register(function):
            self.schedulers.append((seconds, function))
            return function
        return register

    def start_schedulers(self):
        for interval, function in self.schedulers:
            def run(interval=interval, function=function):
                while True:
                    time.sleep(interval)
                    try:
                        function()
                    except Exception:
                        pass  # A failed job is retried at the next interval.
            threading.Thread(target=run, daemon=True).start()

    def fetch(self, domain, path, method="GET", json=None, headers=None):
        body = {"domain": domain, "path": path, "method": method, "headers": headers or {}}
        if json is not None:
            body["json"] = json
        return self._broker("/fetch", body)

    def _broker(self, path, body):
        request = urllib.request.Request(os.environ["HTMLAPP_BROKER_URL"] + path,
            data=encode(body), method="POST",
            headers={"Authorization": "Bearer " + os.environ["HTMLAPP_BROKER_TOKEN"], "Content-Type": "application/json"})
        try:
            with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(request, timeout=15) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            try:
                payload = json.loads(error.read(4096))
                message = payload.get("error", "Platform request failed.")
            except ValueError:
                message = "Platform request failed."
            raise Error(error.code, message) from None
        except urllib.error.URLError:
            raise Error(503, "Platform broker is temporarily unavailable.") from None

    def notify(self, resource, title="New activity", body="Open the app to view it."):
        return self._broker("/notify", {"resource": resource, "title": title, "body": body})
