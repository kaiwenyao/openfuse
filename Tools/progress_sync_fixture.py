#!/usr/bin/env python3
"""LAN progress sync fixture: GET/POST /progress, merge by mediaPath."""
from __future__ import annotations
import argparse, datetime, json, os, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOCK = threading.Lock()
RECORDS: dict[str, dict] = {}
LOG = os.path.abspath("build/progress-sync.log")
TOKEN: str | None = None


def log(entry):
    with LOCK:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(entry, ensure_ascii=False) + "\n")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def send_json(self, payload, status=200):
        body = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def authorized(self):
        if not TOKEN:
            return True
        return self.headers.get("Authorization") == f"Bearer {TOKEN}"

    def do_GET(self):
        if self.path.split("?")[0] != "/progress":
            self.send_json({"error": "not found"}, 404); return
        if not self.authorized():
            self.send_json({"error": "unauthorized"}, 401); return
        with LOCK:
            rows = list(RECORDS.values())
        log({"method": "GET", "count": len(rows)})
        self.send_json(rows)

    def do_POST(self):
        if self.path.split("?")[0] != "/progress":
            self.send_json({"error": "not found"}, 404); return
        if not self.authorized():
            self.send_json({"error": "unauthorized"}, 401); return
        length = int(self.headers.get("Content-Length") or 0)
        rows = json.loads(self.rfile.read(length) or b"[]")
        with LOCK:
            for row in rows:
                key = row.get("mediaPath", "")
                old = RECORDS.get(key)
                if old is None or row.get("lastPlayedAt", "") >= old.get("lastPlayedAt", ""):
                    RECORDS[key] = row
            count = len(RECORDS)
        log({"method": "POST", "received": len(rows), "stored": count})
        self.send_json({"code": 200, "count": count})


def main():
    global LOG, TOKEN
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8130)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--log", default=LOG)
    parser.add_argument("--token", default="")
    args = parser.parse_args()
    LOG = os.path.abspath(args.log)
    TOKEN = args.token or None
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"progress sync on http://{args.host}:{args.port}/progress", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
