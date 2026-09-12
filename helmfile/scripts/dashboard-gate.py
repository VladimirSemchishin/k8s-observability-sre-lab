#!/usr/bin/env python3
import base64
import hashlib
import hmac
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

USER = os.environ.get("GATE_USER", "admin")
PASS = os.environ.get("GATE_PASS", "admin")
SECRET = os.environ["GATE_SECRET"].encode()
COOKIE = "kd-auth"
PATH = "/ui/kubernetes-dashboard"

def sign():
    return hmac.new(SECRET, USER.encode(), hashlib.sha256).hexdigest()

def ok_cookie(header):
    if not header:
        return False
    for part in header.split(";"):
        part = part.strip()
        if part.startswith(COOKIE + "="):
            val = part.split("=", 1)[1]
            return hmac.compare_digest(val, sign())
    return False

def ok_basic(header):
    if not header or not header.startswith("Basic "):
        return False
    try:
        raw = base64.b64decode(header.split(" ", 1)[1]).decode()
    except Exception:
        return False
    if ":" not in raw:
        return False
    u, p = raw.split(":", 1)
    return u == USER and p == PASS

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def do_GET(self):
        self.auth()

    def do_HEAD(self):
        self.auth()

    def do_POST(self):
        self.auth()

    def do_PUT(self):
        self.auth()

    def do_DELETE(self):
        self.auth()

    def do_OPTIONS(self):
        self.auth()

    def auth(self):
        if self.path.split("?", 1)[0] == "/healthz":
            self.send_response(200)
            self.end_headers()
            return
        if ok_cookie(self.headers.get("Cookie")):
            self.send_response(200)
            self.end_headers()
            return
        if ok_basic(self.headers.get("Authorization")):
            self.send_response(200)
            self.send_header(
                "Set-Cookie",
                "%s=%s; Path=%s; HttpOnly; Secure; SameSite=Lax; Max-Age=86400"
                % (COOKIE, sign(), PATH),
            )
            self.end_headers()
            return
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="kubernetes-dashboard"')
        self.end_headers()

if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
