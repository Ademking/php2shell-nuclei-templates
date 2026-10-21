#!/usr/bin/env python3
"""Tiny HTTP server that returns a configurable X-Powered-By header.

GET /set?v=8.3.36  -> changes the advertised version
GET /              -> 200 with X-Powered-By: PHP/<version>
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

STATE = {"version": "8.3.30"}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/set":
            STATE["version"] = parse_qs(parsed.query).get("v", [""])[0]
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(STATE["version"].encode())
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        if STATE["version"]:
            self.send_header("X-Powered-By", f"PHP/{STATE['version']}")
        self.end_headers()
        self.wfile.write(b"<html><body>ok</body></html>")

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 18084), Handler).serve_forever()
