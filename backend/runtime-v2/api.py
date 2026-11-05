"""Versioned public API, reached only through the unprivileged gateway."""
import hashlib
import hmac
import json
import os
import queue
import re
import secrets
import threading
import time
from http import HTTPStatus
from manager import APP_ID, Failure, Manager, encode, sha, validate_bundle

CAPABILITIES = {
    "apiVersion": 2, "sdkVersion": 2, "origin": "https://htmlapp.hostish.site",
    "apiBaseURLTemplate": "https://htmlapp.hostish.site/v2/apps/{appID}/api",
    "enrollmentPath": "/v2/enrollment", "deploymentPath": "/v2/deployments", "operationsPath": "/v2/operations/{operationID}",
    "managementPath": "/v2/manage/apps/{appID}", "schemaPath": "/v2/apps/{appID}/schema",
    "devicesPath": "/v2/apps/{appID}/devices", "documentationPath": "/v2/docs",
    "runtimeHeader": "Authorization: Bearer <publicKey>", "sessionHeader": "X-HTMLApp-Session",
    "runtime": "Python 3.12 standard library + cryptography 50.0.2 + htmlapp_sdk v2",
    "features": ["custom-python-routes", "sqlite-transactions", "resource-sessions", "revocation",
                 "cursor-events", "interval-jobs", "approved-https", "scoped-push", "revision-checks", "rollback"],
    "eventTransport": "cursor-polling", "workspaceLimitBytes": 1998848,
    "memoryMiB": 256, "cpuLimit": 0.35, "requestLimitBytes": 131072,
    "maxActiveDeployments": 6, "maxPerEnrollmentSecret": 3,
    "encryption": "Applications may store ciphertext. Client-side E2EE requires a compatible client implementation.",
}


class Operations:
    def __init__(self, manager):
        self.manager = manager
        self.lock = threading.Lock()
        self.work = queue.Queue(maxsize=8)
        with manager.db() as db:
            db.execute("""CREATE TABLE IF NOT EXISTS operations (
                id TEXT PRIMARY KEY, owner TEXT, idempotency TEXT, request_hash TEXT,
                state TEXT, result BLOB, created INTEGER, UNIQUE(owner,idempotency))""")
            db.execute("UPDATE operations SET state='failed',result=? WHERE state IN ('queued','running')",
                       (encode({"error": "Manager restarted. Retry with a new operation key and the same clientID/baseRevision."}),))
        threading.Thread(target=self.run, daemon=True).start()

    def submit(self, token, key, action, app_id, body):
        if not isinstance(key, str) or not re.fullmatch(r"[A-Za-z0-9_-]{8,80}", key):
            raise Failure(400, "Provide a stable Idempotency-Key header.")
        if action == "create":
            if not self.manager.accepts_enrollment(token):
                raise Failure(403, "VPS enrollment authorization required.")
            validate_bundle({"source": body.get("source"), "manifest": body.get("manifest")})
        else:
            self.manager.require_manager(app_id, token, deleted=action == "delete")
            if action == "deploy":
                validate_bundle({"source": body.get("source"), "manifest": body.get("manifest")})
        request_hash = hashlib.sha256(encode([action, app_id, body])).hexdigest()
        owner = sha(token)
        with self.lock, self.manager.db() as db:
            prior = db.execute("SELECT * FROM operations WHERE owner=? AND idempotency=?", (owner, key)).fetchone()
            if prior:
                if prior["request_hash"] != request_hash:
                    raise Failure(409, "Idempotency key was already used with a different request.")
                return self.summary(prior)
            if self.work.full():
                raise Failure(429, "Deployment queue is full. Retry shortly.")
            db.execute("DELETE FROM operations WHERE created<? AND state IN ('failed','succeeded')", (int(time.time()) - 86400,))
            daily = db.execute("SELECT count(*) FROM operations WHERE owner=? AND created>?", (owner, int(time.time()) - 86400)).fetchone()[0]
            if daily >= 50:
                raise Failure(429, "Daily operation limit reached for this credential.")
            if db.execute("SELECT count(*) FROM operations").fetchone()[0] >= 200:
                raise Failure(429, "Daily deployment operation limit reached.")
            operation = secrets.token_hex(16)
            db.execute("INSERT INTO operations VALUES(?,?,?,?,?,?,?)",
                       (operation, owner, key, request_hash, "queued", None, int(time.time())))
        self.work.put_nowait((operation, action, app_id, token, body))
        return {"operationID": operation, "state": "queued", "statusURL": "/v2/operations/" + operation}

    @staticmethod
    def summary(row):
        result = {"operationID": row["id"], "state": row["state"], "statusURL": "/v2/operations/" + row["id"]}
        if row["result"]:
            result["result"] = json.loads(row["result"])
        return result

    def get(self, token, operation):
        with self.manager.db() as db:
            row = db.execute("SELECT * FROM operations WHERE id=? AND owner=?", (operation, sha(token))).fetchone()
        if not row:
            raise Failure(404, "Operation not found.")
        return self.summary(row)

    def run(self):
        while True:
            operation, action, app_id, token, body = self.work.get()
            try:
                with self.manager.db() as db:
                    db.execute("UPDATE operations SET state='running' WHERE id=?", (operation,))
                if action == "create":
                    result = self.manager.create(token, body)
                elif action == "deploy":
                    result = self.manager.deploy(app_id, token, body)
                elif action == "restart":
                    result = self.manager.restart(app_id, token, body)
                elif action == "rollback":
                    result = self.manager.rollback(app_id, token, body)
                else:
                    result = self.manager.delete(app_id, token)
                state = "succeeded"
            except Failure as error:
                state, result = "failed", {"error": error.message, "status": error.status}
            except Exception as error:
                import traceback
                frames = traceback.extract_tb(error.__traceback__)
                location = ", ".join(f"{os.path.basename(f.filename)} line {f.lineno}" for f in frames[-4:])
                detail = re.sub(r"[A-Za-z0-9_-]{20,}", "[redacted]", str(error)[:500])
                message = f"{type(error).__name__} at {location}. {detail}"
                state, result = "failed", {"error": message, "status": 503}
            with self.manager.db() as db:
                db.execute("UPDATE operations SET state=?,result=? WHERE id=?", (state, encode(result), operation))
            self.work.task_done()


class API:
    def __init__(self, manager, documentation=""):
        self.manager = manager
        self.operations = Operations(manager)
        self.documentation = documentation

    def dispatch(self, method, path, query, token, session, idem, body):
        if method == "GET" and path == "/v2/capabilities":
            return 200, {**CAPABILITIES, "pushConfigured": self.manager.push is not None}
        if method == "GET" and path == "/v2/enrollment":
            enrollment = self.manager.accepts_enrollment(token)
            if not enrollment:
                raise Failure(403, "Invalid or revoked enrollment secret.")
            with self.manager.db() as db:
                active = db.execute("SELECT count(*) FROM apps WHERE tenant=? AND deleted=0", (sha(token),)).fetchone()[0]
            return 200, {"paired": True, "maxApps": enrollment["max_apps"], "activeApps": active}
        if method == "GET" and path == "/v2/docs":
            return 200, {"sdkVersion": 2, "instructions": self.documentation}
        if method == "POST" and path == "/v2/deployments":
            return 202, self.operations.submit(token, idem, "create", None, body)
        match = re.fullmatch(r"/v2/operations/([a-f0-9]{32})", path)
        if match and method == "GET":
            return 200, self.operations.get(token, match[1])
        match = re.fullmatch(r"/v2/manage/apps/([A-Z2-7]{12})(?:/(deploy|rollback|restart|source|logs))?", path)
        if match:
            app_id, action = match.groups()
            row = self.manager.require_manager(app_id, token, deleted=method == "DELETE")
            if method == "GET" and action is None:
                return 200, self.manager.details(app_id)
            if method == "GET" and action == "source":
                return 200, self.manager.bundle(row)
            if method == "GET" and action == "logs":
                # Generated logs can contain personal data or deliberately print
                # secrets. Detailed logs are administrator-only on the VPS.
                return 200, {"state": row["state"], "revision": row["revision"],
                             "message": "Detailed application output is available only to the VPS administrator."}
            if method == "DELETE" and action is None:
                return 202, self.operations.submit(token, idem, "delete", app_id, {})
            if method == "POST" and action in ("deploy", "rollback", "restart"):
                return 202, self.operations.submit(token, idem, action, app_id, body)
        match = re.fullmatch(r"/v2/apps/([A-Z2-7]{12})/(schema|devices|api(?:/.*)?)", path)
        if match:
            app_id, action = match.groups()
            if action == "schema" and method == "GET":
                row = self.manager.row(app_id)
                if not hmac.compare_digest(token, self.manager.keys(app_id)["publicKey"]):
                    raise Failure(403, "App access key required.")
                return 200, self.manager.bundle(row)["manifest"]
            if action == "devices" and method in ("PUT", "DELETE"):
                return 200, self.manager.device(app_id, token, body, delete=method == "DELETE")
            if action.startswith("api/"):
                suffix = action[3:] + ("?" + query if query else "")
                return self.manager.proxy(app_id, method, suffix, token, session, body if method != "GET" else None)
        raise Failure(404, "Route not found.")

    def __call__(self, environ, start_response):
        try:
            length = int(environ.get("CONTENT_LENGTH") or 0)
            maximum = 160000 if environ.get("PATH_INFO", "").startswith(("/v2/deployments", "/v2/manage/")) else 131072
            if length < 0 or length > maximum or environ.get("HTTP_TRANSFER_ENCODING"):
                raise Failure(413, "Request too large or unsupported transfer encoding.")
            raw = environ["wsgi.input"].read(length)
            body = json.loads(raw) if raw else {}
            if not isinstance(body, dict):
                raise Failure(400, "Expected a JSON object.")
            authorization = environ.get("HTTP_AUTHORIZATION", "")
            token = authorization[7:] if authorization.startswith("Bearer ") else ""
            status, payload = self.dispatch(environ["REQUEST_METHOD"], environ["PATH_INFO"],
                environ.get("QUERY_STRING", ""), token, environ.get("HTTP_X_HTMLAPP_SESSION", ""),
                environ.get("HTTP_IDEMPOTENCY_KEY", ""), body)
            data = encode(payload)
        except Failure as error:
            status, data = error.status, encode({"error": error.message})
        except (ValueError, TypeError, KeyError, RecursionError):
            status, data = 400, encode({"error": "Invalid request."})
        except Exception:
            status, data = 503, encode({"error": "Runtime service unavailable."})
        start_response(f"{status} {HTTPStatus(status).phrase}", [("Content-Type", "application/json"),
            ("Content-Length", str(len(data))), ("Cache-Control", "no-store"), ("X-Content-Type-Options", "nosniff")])
        return [data]
