#!/usr/bin/env python3
"""A small authenticated WebDAV server for M2 tests.

It is deliberately limited to what OpenFuse needs: PROPFIND Depth 0/1,
GET/HEAD with single-range support, OPTIONS, Basic auth and request logging.
The media tree is built from the generated OpenFuse fixture, so playback and
seek tests do not need a real OpenList account.

    python3 Tools/webdav_fixture.py --setup
    python3 Tools/webdav_fixture.py --port 8099

Server root: build/webdav-root (mounted at /dav/)
Credentials: test / test (override with --user/--password)
Log: build/webdav.log (JSON lines)
"""
from __future__ import annotations

import argparse
import base64
import datetime
import json
import os
import re
import shutil
import socketserver
import sys
import threading
import time
import urllib.parse
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from xml.sax.saxutils import escape

FIXTURE = os.path.abspath("Fixtures/generated/openfuse-fixture.mkv")
SUBS = [
    "openfuse-fixture.zh-Hans.ass",
    "openfuse-fixture.zh-Hant.ass",
    "openfuse-fixture.ass",
]
ROOT = os.path.abspath("build/webdav-root")
LOG_PATH = os.path.abspath("build/webdav.log")
PREFIX = "/dav"
AUTH_USER = "test"
AUTH_PASSWORD = "test"
THROTTLE_KBPS = 0
LOG_LOCK = threading.Lock()


def link_or_copy(source: str, destination: str) -> None:
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    if os.path.exists(destination):
        return
    try:
        os.link(source, destination)
    except OSError:
        shutil.copy2(source, destination)


def setup_tree() -> None:
    if not os.path.exists(FIXTURE):
        raise SystemExit(f"missing fixture: {FIXTURE}; run Scripts/make_fixtures.sh")
    movie_dir = os.path.join(ROOT, "Movies", "OpenFuse Fixture (2026)")
    link_or_copy(FIXTURE, os.path.join(movie_dir, "OpenFuse Fixture.mkv"))
    subtitle_targets = {
        "openfuse-fixture.zh-Hans.ass": "OpenFuse Fixture.zh-Hans.ass",
        "openfuse-fixture.zh-Hant.ass": "OpenFuse Fixture.zh-Hant.ass",
        "openfuse-fixture.ass": "OpenFuse Fixture.ass",
    }
    for source_name, target_name in subtitle_targets.items():
        link_or_copy(os.path.join("Fixtures/generated", source_name), os.path.join(movie_dir, target_name))
    episode_dir = os.path.join(ROOT, "Shows", "示例剧", "Season 01")
    link_or_copy(FIXTURE, os.path.join(episode_dir, "示例剧.S01E01.mkv"))
    link_or_copy(
        os.path.join("Fixtures/generated", "openfuse-fixture.zh-Hans.ass"),
        os.path.join(episode_dir, "示例剧.S01E01.zh-Hans.ass"),
    )
    odd_dir = os.path.join(ROOT, "Movies", "100% 测试")
    os.makedirs(odd_dir, exist_ok=True)
    with open(os.path.join(odd_dir, "说明.txt"), "w", encoding="utf-8") as handle:
        handle.write("Unicode 与百分号路径测试\n")
    print(f"fixture tree ready: {ROOT}")


class FixtureServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True

    def server_bind(self) -> None:
        # HTTPServer.server_bind performs a reverse DNS lookup which can block
        # for tens of seconds on machines with a proxy/VPN. The fixture only
        # needs a numeric host.
        socketserver.TCPServer.server_bind(self)
        host, port = self.server_address[:2]
        self.server_name = str(host)
        self.server_port = int(port)


class Handler(BaseHTTPRequestHandler):
    server_version = "OpenFuseWebDAVFixture/1.0"
    protocol_version = "HTTP/1.1"

    def log_message(self, format: str, *args) -> None:  # noqa: A003
        pass

    def _record(self, status: int, extra: dict | None = None) -> None:
        entry = {
            "time": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "method": self.command,
            "path": urllib.parse.unquote(self.path),
            "range": self.headers.get("Range"),
            "depth": self.headers.get("Depth"),
            "status": status,
            "user_agent": self.headers.get("User-Agent", ""),
        }
        if extra:
            entry.update(extra)
        with LOG_LOCK:
            with open(LOG_PATH, "a", encoding="utf-8") as handle:
                handle.write(json.dumps(entry, ensure_ascii=False) + "\n")

    def _authorized(self) -> bool:
        header = self.headers.get("Authorization", "")
        if not header.startswith("Basic "):
            return False
        try:
            decoded = base64.b64decode(header[6:]).decode("utf-8")
        except Exception:
            return False
        return decoded == f"{AUTH_USER}:{AUTH_PASSWORD}"

    def _require_auth(self) -> bool:
        if self._authorized():
            return True
        self.send_response(HTTPStatus.UNAUTHORIZED)
        self.send_header("WWW-Authenticate", 'Basic realm="OpenFuse"')
        self.send_header("Content-Length", "0")
        self.end_headers()
        self._record(401)
        return False

    def _resolve(self) -> tuple[str | None, str | None]:
        parsed = urllib.parse.urlsplit(self.path)
        path = urllib.parse.unquote(parsed.path)
        if not path.startswith(PREFIX):
            return None, None
        relative = path[len(PREFIX):].strip("/")
        candidate = os.path.abspath(os.path.join(ROOT, relative))
        if candidate != ROOT and not candidate.startswith(ROOT + os.sep):
            return None, None
        return candidate, relative

    def _href(self, relative: str, is_dir: bool) -> str:
        path = f"{PREFIX}/{relative}".rstrip("/") or PREFIX
        encoded = urllib.parse.quote(path, safe="/")
        if is_dir and not encoded.endswith("/"):
            encoded += "/"
        return encoded

    def _prop(self, relative: str, full: str) -> str:
        stat = os.stat(full)
        is_dir = os.path.isdir(full)
        display = os.path.basename(full) or "dav"
        modified = datetime.datetime.fromtimestamp(stat.st_mtime, tz=datetime.timezone.utc)
        http_date = modified.strftime("%a, %d %b %Y %H:%M:%S GMT")
        content_type = "httpd/unix-directory" if is_dir else guess_type(full)
        size = 0 if is_dir else stat.st_size
        etag = f'"{int(stat.st_mtime)}-{size}"'
        resource_type = "<d:collection/>" if is_dir else ""
        return f"""<d:response>
  <d:href>{self._href(relative, is_dir)}</d:href>
  <d:propstat>
    <d:prop>
      <d:displayname>{escape(display)}</d:displayname>
      <d:resourcetype>{resource_type}</d:resourcetype>
      <d:getcontentlength>{size}</d:getcontentlength>
      <d:getcontenttype>{content_type}</d:getcontenttype>
      <d:getlastmodified>{http_date}</d:getlastmodified>
      <d:getetag>{escape(etag)}</d:getetag>
    </d:prop>
    <d:status>HTTP/1.1 200 OK</d:status>
  </d:propstat>
</d:response>"""

    def do_OPTIONS(self) -> None:  # noqa: N802
        if not self._require_auth():
            return
        self.send_response(HTTPStatus.OK)
        self.send_header("DAV", "1, 2")
        self.send_header("Allow", "OPTIONS, PROPFIND, GET, HEAD")
        self.send_header("Content-Length", "0")
        self.end_headers()
        self._record(200)

    def do_PROPFIND(self) -> None:  # noqa: N802
        if not self._require_auth():
            return
        full, relative = self._resolve()
        if full is None or not os.path.exists(full):
            self.send_error(HTTPStatus.NOT_FOUND)
            self._record(404)
            return
        depth = self.headers.get("Depth", "1")
        responses = [self._prop(relative, full)]
        if depth != "0" and os.path.isdir(full):
            for name in sorted(os.listdir(full)):
                child_full = os.path.join(full, name)
                child_relative = os.path.join(relative, name).replace(os.sep, "/")
                responses.append(self._prop(child_relative, child_full))
        body = (
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<d:multistatus xmlns:d="DAV:">\n' + "\n".join(responses) + "\n</d:multistatus>\n"
        ).encode("utf-8")
        self.send_response(207)
        self.send_header("Content-Type", 'application/xml; charset="utf-8"')
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        self._record(207, {"items": len(responses)})

    def do_HEAD(self) -> None:  # noqa: N802
        self._serve(head_only=True)

    def do_GET(self) -> None:  # noqa: N802
        self._serve(head_only=False)

    def _serve(self, head_only: bool) -> None:
        if not self._require_auth():
            return
        full, relative = self._resolve()
        if full is None:
            self.send_error(HTTPStatus.BAD_REQUEST)
            self._record(400)
            return
        if not os.path.exists(full):
            self.send_error(HTTPStatus.NOT_FOUND)
            self._record(404)
            return
        if os.path.isdir(full):
            self.send_error(HTTPStatus.METHOD_NOT_ALLOWED)
            self._record(405)
            return
        size = os.path.getsize(full)
        stat = os.stat(full)
        range_header = self.headers.get("Range")
        start, end = 0, size - 1
        status = 200
        if range_header:
            match = re.match(r"bytes=(\d*)-(\d*)$", range_header.strip())
            if not match:
                self._range_not_satisfiable(size)
                return
            start_text, end_text = match.groups()
            if start_text:
                start = int(start_text)
                end = int(end_text) if end_text else size - 1
            else:
                length = int(end_text)
                start = max(0, size - length)
                end = size - 1
            if start >= size or start > end:
                self._range_not_satisfiable(size)
                return
            end = min(end, size - 1)
            status = 206
        length = end - start + 1
        content_type = guess_type(full)
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(length))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Last-Modified", datetime.datetime.fromtimestamp(stat.st_mtime, tz=datetime.timezone.utc)
                         .strftime("%a, %d %b %Y %H:%M:%S GMT"))
        self.send_header("ETag", f'"{int(stat.st_mtime)}-{size}"')
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        if head_only:
            self._record(status, {"bytes": 0, "size": size})
            return
        sent = 0
        with open(full, "rb") as handle:
            handle.seek(start)
            remaining = length
            try:
                while remaining > 0:
                    chunk = handle.read(min(256 * 1024, remaining))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    sent += len(chunk)
                    remaining -= len(chunk)
                    if THROTTLE_KBPS > 0:
                        time.sleep(len(chunk) / (THROTTLE_KBPS * 1024))
            except (BrokenPipeError, ConnectionResetError):
                self._record(status, {"bytes": sent, "size": size, "start": start, "end": end, "aborted": True})
                return
        self._record(status, {"bytes": sent, "size": size, "start": start, "end": end})

    def _range_not_satisfiable(self, size: int) -> None:
        self.send_response(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
        self.send_header("Content-Range", f"bytes */{size}")
        self.send_header("Content-Length", "0")
        self.end_headers()
        self._record(416, {"size": size})


def guess_type(path: str) -> str:
    ext = os.path.splitext(path)[1].lower()
    return {
        ".mkv": "video/x-matroska",
        ".mp4": "video/mp4",
        ".ass": "text/x-ssa",
        ".srt": "application/x-subrip",
        ".txt": "text/plain; charset=utf-8",
    }.get(ext, "application/octet-stream")


def main() -> None:
    global ROOT, LOG_PATH, PREFIX, AUTH_USER, AUTH_PASSWORD, THROTTLE_KBPS
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=ROOT)
    parser.add_argument("--port", type=int, default=8099)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--prefix", default=PREFIX)
    parser.add_argument("--user", default=AUTH_USER)
    parser.add_argument("--password", default=AUTH_PASSWORD)
    parser.add_argument("--log", default=LOG_PATH)
    parser.add_argument("--setup", action="store_true")
    parser.add_argument("--throttle-kbps", type=int, default=0)
    args = parser.parse_args()
    ROOT = os.path.abspath(args.root)
    LOG_PATH = os.path.abspath(args.log)
    PREFIX = "/" + args.prefix.strip("/")
    AUTH_USER = args.user
    AUTH_PASSWORD = args.password
    THROTTLE_KBPS = args.throttle_kbps
    os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
    if args.setup or not os.path.isdir(ROOT):
        setup_tree()
    server = FixtureServer((args.host, args.port), Handler)
    print(f"webdav fixture listening on http://{args.host}:{args.port}{PREFIX}/ (user {AUTH_USER})", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
