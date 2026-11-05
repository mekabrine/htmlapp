"""Fixed entrypoint for generated code. Never runs on the VPS host."""
import hmac
import json
import os
import runpy
import sqlite3
import sys
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit
from htmlapp_sdk import App, Error, Request, encode

def load_application():
    code_directory = os.environ.get("HTMLAPP_CODE_DIRECTORY", "/code")
    manifest = json.load(open(code_directory + "/manifest.json"))
    database = os.environ.get("HTMLAPP_DATABASE", "/data/app.sqlite3")
    with sqlite3.connect(database) as migration:
        migration.execute("CREATE TABLE IF NOT EXISTS _htmlapp_schema (singleton INTEGER PRIMARY KEY CHECK(singleton=1),version INTEGER)")
        row = migration.execute("SELECT version FROM _htmlapp_schema WHERE singleton=1").fetchone()
        version = row[0] if row else 0
        target = manifest["schemaVersion"]
        if version > target:
            raise RuntimeError("Schema downgrade is not supported")
        if version < target:
            migration.execute("BEGIN IMMEDIATE")
            def authorize(action, *_):
                if action in (sqlite3.SQLITE_TRANSACTION, sqlite3.SQLITE_ATTACH, sqlite3.SQLITE_DETACH, sqlite3.SQLITE_PRAGMA):
                    return sqlite3.SQLITE_DENY
                return sqlite3.SQLITE_OK
            migration.set_authorizer(authorize)
            try:
                for statement in manifest.get("migrations", []):
                    migration.execute(statement)
            finally:
                migration.set_authorizer(None)
            migration.execute("INSERT OR REPLACE INTO _htmlapp_schema VALUES(1,?)", (target,))

    migration.close()
    app = runpy.run_path(code_directory + "/server.py").get("app")
    if not isinstance(app, App):
        raise RuntimeError("server.py must expose app = htmlapp_sdk.App()")
    if sorted(app.schema(), key=str) != sorted(manifest["routes"], key=str):
        raise RuntimeError("Python routes do not match manifest.routes")

    return app


try:
    app = load_application()
except Exception as error:
    allowed = {"SyntaxError", "IndentationError", "ImportError", "ModuleNotFoundError", "RuntimeError", "OperationalError", "ProgrammingError", "ValueError", "NameError", "TypeError", "AttributeError", "KeyError"}
    kind = type(error).__name__
    frames = [frame for frame in traceback.extract_tb(error.__traceback__) if frame.filename.endswith("/server.py")]
    line = getattr(error, "lineno", None) or (frames[-1].lineno if frames else 0)
    print("HTMLAPP_STARTUP " + json.dumps({"kind": kind if kind in allowed else "ApplicationError", "line": int(line)}), flush=True)
    sys.exit(1)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def process(self):
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if size < 0 or size > 131072 or self.headers.get("Transfer-Encoding"):
                raise Error(413, "Request too large or unsupported encoding.")
            raw = self.rfile.read(size)
            body = json.loads(raw) if raw else {}
            parsed = urlsplit(self.path)
            if parsed.path.startswith("/_platform/"):
                expected = "Bearer " + os.environ["HTMLAPP_BROKER_TOKEN"]
                if not hmac.compare_digest(self.headers.get("Authorization", ""), expected):
                    raise Error(403, "Platform authorization required.")
                if parsed.path == "/_platform/health":
                    result = {"ready": True, "routes": app.schema()}
                elif parsed.path == "/_platform/session":
                    result = app.auth.require(body.get("session", ""))
                elif parsed.path == "/_platform/member":
                    result = {"active": app.auth.is_member(body.get("resource"), body.get("subject"))}
                else:
                    raise Error(404, "Not found.")
            else:
                request = Request(self.command, parsed.path, self.headers, body, parse_qs(parsed.query))
                result = app.handle(request)
            self.reply(200, result)
        except Error as error:
            self.reply(error.status, {"error": error.message})
        except (ValueError, KeyError, TypeError):
            self.reply(400, {"error": "Invalid request fields."})
        except (sqlite3.Error, OSError):
            self.reply(507, {"error": "Storage unavailable or quota exhausted."})
        except Exception:
            self.reply(500, {"error": "Application error. Inspect the backend source and request contract."})

    def reply(self, status, value):
        data = encode(value)
        if len(data) > 131072:
            status, data = 413, b'{"error":"Response too large. Use pagination."}'
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = process


app.start_schedulers()
ThreadingHTTPServer(("0.0.0.0", int(os.environ.get("HTMLAPP_PORT", "8080"))), Handler).serve_forever()
