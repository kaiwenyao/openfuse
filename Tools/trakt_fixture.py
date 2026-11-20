#!/usr/bin/env python3
"""Minimal Trakt API fixture for OpenFuse M4q scrobble tests."""
from __future__ import annotations

import argparse
import datetime
import json
import os
import socketserver
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG_PATH = os.path.abspath("build/trakt.log")
TOKEN = "trakt-test-token"
LOCK = threading.Lock()


def log(entry):
    with LOCK:
        with open(LOG_PATH, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(entry, ensure_ascii=False) + "\n")


class Server(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True

    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        host, port = self.server_address[:2]
        self.server_name = str(host)
        self.server_port = int(port)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format, *args):
        pass

    def _json(self, payload, status=200):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)
        log({"time": datetime.datetime.now(datetime.timezone.utc).isoformat(),
             "path": self.path, "method": self.command, "status": status})

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(length) or b"{}")

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        parsed = urllib.parse.urlsplit(self.path)
        if parsed.path.startswith("/search/show"):
            query = (urllib.parse.parse_qs(parsed.query).get("query") or [""])[0]
            self._json([{
                "type": "show",
                "score": 1000,
                "show": {
                    "title": query or "OpenFuse Show",
                    "year": 2026,
                    "ids": {"trakt": 2001, "slug": "openfuse-show", "imdb": "tt0002001", "tmdb": 2001},
                },
            }])
            return
        if parsed.path.startswith("/search/movie"):
            query = (urllib.parse.parse_qs(parsed.query).get("query") or [""])[0]
            self._json([{
                "type": "movie",
                "score": 1000,
                "movie": {
                    "title": query or "OpenFuse Fixture",
                    "year": 2026,
                    "ids": {"trakt": 1001, "slug": "openfuse-fixture", "imdb": "tt0000001", "tmdb": 1001},
                },
            }])
            return
        self._json({"error": "not found"}, 404)

    def do_POST(self):
        path = urllib.parse.urlsplit(self.path).path
        body = self._body()
        if path == "/oauth/device/code":
            self._json({
                "device_code": "device-test-code",
                "user_code": "ABCD1234",
                "verification_url": "https://trakt.tv/activate",
                "expires_in": 600,
                "interval": 1,
            })
            return
        if path == "/oauth/device/token":
            self._json({"access_token": TOKEN, "refresh_token": "refresh-test", "expires_in": 7776000})
            return
        if path in ("/scrobble/start", "/scrobble/pause", "/scrobble/stop"):
            log({"time": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                 "path": path, "method": "POST", "status": 201, "body": body})
            self._json({"action": path.split("/")[-1], "progress": body.get("progress", 0)}, 201)
            return
        self._json({"error": "not found"}, 404)


def main():
    global LOG_PATH, TOKEN
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8123)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--log", default=LOG_PATH)
    parser.add_argument("--token", default=TOKEN)
    args = parser.parse_args()
    LOG_PATH = os.path.abspath(args.log)
    TOKEN = args.token
    os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
    server = Server((args.host, args.port), Handler)
    print(f"trakt fixture listening on http://{args.host}:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
