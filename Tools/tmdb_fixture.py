#!/usr/bin/env python3
"""Minimal TMDB v3 search fixture for M3b metadata tests."""
from __future__ import annotations

import argparse
import datetime
import json
import os
import socketserver
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.abspath("build/tmdb-fixture")
LOG_PATH = os.path.abspath("build/tmdb.log")
API_KEY = "test-key"
POSTERS = os.path.abspath("build/jellyfin-fixture")

MOVIES = [
    {
        "id": 1001,
        "title": "OpenFuse Fixture: TMDB Cut",
        "overview": "TMDB fixture overview for the OpenFuse library test.",
        "poster_path": "/poster-movie.jpg",
        "release_date": "2026-01-15",
    }
]
TV = [
    {
        "id": 2001,
        "name": "示例剧：TMDB 版",
        "overview": "TMDB fixture overview for the series test.",
        "poster_path": "/poster-series.jpg",
        "first_air_date": "2026-02-01",
    }
]


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

    def _record(self, status, extra=None):
        parsed = urllib.parse.urlsplit(self.path)
        query = urllib.parse.parse_qs(parsed.query)
        query.pop("api_key", None)
        safe_query = urllib.parse.urlencode(query, doseq=True)
        entry = {
            "time": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "path": parsed.path + (("?" + safe_query) if safe_query else ""),
            "status": status,
        }
        if extra:
            entry.update(extra)
        with open(LOG_PATH, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(entry, ensure_ascii=False) + "\n")

    def _json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        self._record(status)

    def _image(self, name):
        mapping = {"poster-movie.jpg": "movie.jpg", "poster-series.jpg": "series.jpg"}
        name = mapping.get(name, name)
        path = os.path.join(POSTERS, name)
        if not os.path.exists(path):
            self.send_error(404)
            return
        with open(path, "rb") as handle:
            data = handle.read()
        self.send_response(200)
        self.send_header("Content-Type", "image/jpeg")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        self._record(200)

    def do_GET(self):
        parsed = urllib.parse.urlsplit(self.path)
        query = urllib.parse.parse_qs(parsed.query)
        if parsed.path.startswith("/poster-"):
            self._image(os.path.basename(parsed.path))
            return
        if query.get("api_key", [""])[0] != API_KEY:
            self._json({"status_message": "Invalid API key"}, 401)
            return
        term = (query.get("query") or [""])[0].lower()
        if parsed.path == "/3/search/movie":
            results = [m for m in MOVIES if term and term in m["title"].lower()]
            self._json({"page": 1, "results": results, "total_results": len(results)})
            return
        if parsed.path == "/3/search/tv":
            results = [t for t in TV if term and term in t["name"].lower()]
            self._json({"page": 1, "results": results, "total_results": len(results)})
            return
        self._json({"status_message": "Not found"}, 404)


def main():
    global ROOT, LOG_PATH, API_KEY
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8110)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--log", default=LOG_PATH)
    parser.add_argument("--key", default=API_KEY)
    parser.add_argument("--setup", action="store_true")
    args = parser.parse_args()
    ROOT = os.path.abspath("build/tmdb-fixture")
    LOG_PATH = os.path.abspath(args.log)
    API_KEY = args.key
    os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
    os.makedirs(ROOT, exist_ok=True)
    server = Server((args.host, args.port), Handler)
    print(f"tmdb fixture listening on http://{args.host}:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
