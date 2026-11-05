"""Unprivileged compatibility gateway. v1 continues to use its existing database."""
import http.client
import json
import socket
from gateway import create_app as legacy_app


class LocalConnection(http.client.HTTPConnection):
    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(15)
        self.sock.connect("/run/htmlapp-runtime/control.sock")


def create_app():
    legacy = legacy_app()
    def application(environ, start_response):
        if not environ.get("PATH_INFO", "").startswith("/v2/"):
            return legacy(environ, start_response)
        connection = LocalConnection("localhost", timeout=15)
        try:
            length = int(environ.get("CONTENT_LENGTH") or 0)
            transfer = environ.get("HTTP_TRANSFER_ENCODING", "").lower().strip()
            if transfer:
                if transfer != "chunked" or not environ.get("wsgi.input_terminated") or environ.get("CONTENT_LENGTH"):
                    raise ValueError("Unsupported request framing")
                payload = environ["wsgi.input"].read(160001)
            else:
                if length < 0 or length > 160000:
                    raise ValueError("Request too large")
                payload = environ["wsgi.input"].read(length)
                if len(payload) != length:
                    raise ValueError("Incomplete request")
            if len(payload) > 160000:
                raise ValueError("Request too large")
            path = environ["PATH_INFO"]
            if environ.get("QUERY_STRING"):
                path += "?" + environ["QUERY_STRING"]
            headers = {"Content-Type": "application/json"}
            for source, target in (("HTTP_AUTHORIZATION", "Authorization"), ("HTTP_X_HTMLAPP_SESSION", "X-HTMLApp-Session"),
                                   ("HTTP_IDEMPOTENCY_KEY", "Idempotency-Key")):
                if source in environ:
                    headers[target] = environ[source]
            connection.request(environ["REQUEST_METHOD"], path, body=payload, headers=headers)
            response = connection.getresponse()
            data = response.read(200001)
            if len(data) > 200000:
                raise ValueError("Response too large")
            status = str(response.status) + " " + response.reason
        except Exception:
            status, data = "503 Service Unavailable", b'{"error":"Runtime service unavailable. Existing v1 apps remain available."}'
        finally:
            connection.close()
        start_response(status, [("Content-Type", "application/json"), ("Content-Length", str(len(data))),
                                ("Cache-Control", "no-store"), ("X-Content-Type-Options", "nosniff")])
        return [data]
    return application
