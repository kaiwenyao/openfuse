#!/usr/bin/env python3
"""Minimal Plex Media Server JSON fixture for OpenFuse M5."""
from __future__ import annotations

import argparse
import datetime
import json
import os
import re
import socketserver
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.abspath("build/jellyfin-fixture")
FIXTURE = os.path.abspath("Fixtures/generated/openfuse-fixture.mkv")
LOG_PATH = os.path.abspath("build/plex.log")
TOKEN = "plex-test-token"
MOVIE_ID = "101"
SHOW_ID = "201"
SEASON_ID = "301"
EPISODE_IDS = ["401", "402"]


def section(key, kind, title):
    return {"key": key, "type": kind, "title": title}


def media(part_id):
    return [{
        "videoResolution": "1080",
        "container": "mkv",
        "Part": [{
            "key": f"/library/parts/{part_id}/file.mkv",
            "file": f"/media/{part_id}/file.mkv",
            "size": os.path.getsize(FIXTURE) if os.path.exists(FIXTURE) else 0,
        }],
    }]


def movie():
    return {
        "ratingKey": MOVIE_ID,
        "type": "movie",
        "title": "OpenFuse Plex Movie (2026)",
        "year": 2026,
        "summary": "Plex 夹具电影：HEVC Main 10、E-AC-3 5.1 与双语 ASS。",
        "thumb": f"/library/metadata/{MOVIE_ID}/thumb/1",
        "addedAt": 1767225600,
        "Media": media("101"),
    }


def show():
    return {
        "ratingKey": SHOW_ID,
        "type": "show",
        "title": "Plex 示例剧",
        "year": 2026,
        "summary": "Plex 夹具剧集，用于季/集、海报与续播。",
        "thumb": f"/library/metadata/{SHOW_ID}/thumb/1",
        "addedAt": 1767312000,
    }


def season():
    return {
        "ratingKey": SEASON_ID,
        "type": "season",
        "title": "第 1 季",
        "index": 1,
        "thumb": f"/library/metadata/{SEASON_ID}/thumb/1",
    }


def episodes():
    result = []
    for index, episode_id in enumerate(EPISODE_IDS, 1):
        result.append({
            "ratingKey": episode_id,
            "type": "episode",
            "title": f"Plex 第 {index} 集",
            "summary": f"Plex 夹具第 {index} 集，验证集序、播放与进度。",
            "parentIndex": 1,
            "index": index,
            "addedAt": 1767312000 + index,
            "thumb": f"/library/metadata/{episode_id}/thumb/1",
            "Media": media(episode_id),
        })
    return result


SECTIONS = [
    section("1", "movie", "Plex 电影"),
    section("2", "show", "Plex 电视剧"),
]


def container(payload):
    return json.dumps({"MediaContainer": payload}, ensure_ascii=False).encode("utf-8")


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
        entry = {
            "time": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "path": self.path,
            "status": status,
        }
        if extra:
            entry.update(extra)
        with open(LOG_PATH, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(entry, ensure_ascii=False) + "\n")

    def _authorized(self):
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
        token = self.headers.get("X-Plex-Token") or (query.get("X-Plex-Token") or [None])[0]
        return token == TOKEN

    def _json(self, payload, status=200):
        body = container(payload)
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)
        self._record(status)

    def _poster(self, item_id):
        names = {"101": "movie.jpg", "201": "series.jpg", "301": "season.jpg", "401": "episode.jpg", "402": "episode2.jpg"}
        path = os.path.join(ROOT, names.get(item_id, "movie.jpg"))
        if not os.path.exists(path):
            self.send_error(404)
            return
        with open(path, "rb") as handle:
            data = handle.read()
        self.send_response(200)
        self.send_header("Content-Type", "image/jpeg")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)
        self._record(200)

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        parsed = urllib.parse.urlsplit(self.path)
        path = parsed.path
        if not self._authorized():
            self.send_response(401)
            self.send_header("Content-Length", "0")
            self.end_headers()
            self._record(401)
            return
        if path == "/library/sections":
            self._json({"Directory": SECTIONS, "size": len(SECTIONS)})
            return
        if path == "/library/sections/1/all":
            self._json({"Metadata": [movie()], "size": 1})
            return
        if path == "/library/sections/2/all":
            self._json({"Metadata": [show()], "size": 1})
            return
        if path == f"/library/metadata/{SHOW_ID}/children":
            self._json({"Metadata": [season()], "size": 1})
            return
        if path == f"/library/metadata/{SEASON_ID}/children":
            entries = episodes()
            self._json({"Metadata": entries, "size": len(entries)})
            return
        match = re.match(r"^/library/metadata/(\d+)/thumb", path)
        if match:
            self._poster(match.group(1))
            return
        match = re.match(r"^/library/parts/(\d+)/file\.mkv$", path)
        if match:
            self._stream()
            return
        self.send_response(404)
        self.send_header("Content-Length", "0")
        self.end_headers()
        self._record(404)

    def _stream(self):
        if not os.path.exists(FIXTURE):
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        size = os.path.getsize(FIXTURE)
        range_header = self.headers.get("Range")
        start, end, status = 0, size - 1, 200
        if range_header:
            match = re.match(r"bytes=(\d*)-(\d*)$", range_header.strip())
            if not match:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{size}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            start_text, end_text = match.groups()
            if start_text:
                start = int(start_text)
                end = int(end_text) if end_text else size - 1
            else:
                start = max(0, size - int(end_text))
                end = size - 1
            end = min(end, size - 1)
            if start >= size or start > end:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{size}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            status = 206
        length = end - start + 1
        self.send_response(status)
        self.send_header("Content-Type", "video/x-matroska")
        self.send_header("Content-Length", str(length))
        self.send_header("Accept-Ranges", "bytes")
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        if self.command == "HEAD":
            self._record(status, {"bytes": 0, "size": size, "token": TOKEN})
            return
        sent = 0
        with open(FIXTURE, "rb") as handle:
            handle.seek(start)
            while sent < length:
                chunk = handle.read(min(65536, length - sent))
                if not chunk:
                    break
                self.wfile.write(chunk)
                sent += len(chunk)
        self._record(status, {"bytes": sent, "size": size, "start": start})


def main():
    global ROOT, LOG_PATH, TOKEN
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=32400)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--token", default=TOKEN)
    parser.add_argument("--log", default=LOG_PATH)
    args = parser.parse_args()
    LOG_PATH = os.path.abspath(args.log)
    TOKEN = args.token
    os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
    server = Server((args.host, args.port), Handler)
    print(f"plex fixture listening on http://{args.host}:{args.port} (token {TOKEN})", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
