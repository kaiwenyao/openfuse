#!/usr/bin/env python3
"""Minimal WebDAV server for browser/navigation acceptance tests.

Serves a read-only tree with PROPFIND (Depth 0/1) and ranged GET. The Mac
WebDAV browser only needs those two verbs, so this keeps the acceptance script
free of Docker and of any third-party package.

    python3 Scripts/webdav_fixture.py --root DIR --port 8099
"""

from __future__ import annotations

import argparse
import email.utils
import http.server
import mimetypes
import os
import posixpath
import socketserver
import time
import sys
import urllib.parse
from xml.sax.saxutils import escape

BASE_PATH = "/dav"


def http_date(timestamp: float) -> str:
    return email.utils.formatdate(timestamp, usegmt=True)


def href_for(relpath: str, is_dir: bool) -> str:
    quoted = urllib.parse.quote(relpath, safe="/")
    href = f"{BASE_PATH}/{quoted}".replace("//", "/")
    if is_dir and not href.endswith("/"):
        href += "/"
    return href


def propfind_entry(root: str, relpath: str) -> str:
    full = os.path.join(root, relpath) if relpath else root
    is_dir = os.path.isdir(full)
    name = os.path.basename(relpath) or "dav"
    try:
        stat = os.stat(full)
        modified = http_date(stat.st_mtime)
        size = 0 if is_dir else stat.st_size
        mtime = int(stat.st_mtime)
    except OSError:
        modified = http_date(datetime.datetime.now().timestamp())
        size = 0
        mtime = 0
    resource = "<D:resourcetype><D:collection/></D:resourcetype>" if is_dir else "<D:resourcetype/>"
    content_type = "" if is_dir else mimetypes.guess_type(full)[0] or "application/octet-stream"
    return (
        "<D:response>"
        f"<D:href>{escape(href_for(relpath, is_dir))}</D:href>"
        "<D:propstat><D:prop>"
        f"<D:displayname>{escape(name)}</D:displayname>"
        f"{resource}"
        f"<D:getcontentlength>{size}</D:getcontentlength>"
        f"<D:getcontenttype>{escape(content_type)}</D:getcontenttype>"
        f"<D:getlastmodified>{modified}</D:getlastmodified>"
        f"<D:getetag>\"{size}-{mtime}\"</D:getetag>"
        "</D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat>"
        "</D:response>"
    )


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "OpenFuseWebDAVFixture/1.0"
    root = "."
    rate_bytes = 0
    first_byte_delay = 0.0
    stall_after_bytes = 0
    stall_seconds = 0.0

    def log_message(self, fmt, *args):  # noqa: N802 - stdlib signature
        sys.stderr.write("[webdav] " + fmt % args + "\n")

    # -- helpers ---------------------------------------------------------
    def relpath(self) -> str:
        parsed = urllib.parse.urlparse(self.path)
        path = urllib.parse.unquote(parsed.path)
        if not path.startswith(BASE_PATH):
            return ""
        rel = path[len(BASE_PATH):].lstrip("/")
        return posixpath.normpath(rel) if rel else ""

    def fullpath(self, rel: str) -> str:
        return os.path.join(self.root, rel) if rel else self.root

    def send_body(self, status: int, body: bytes, content_type: str, extra: dict | None = None):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Accept-Ranges", "bytes")
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    # -- verbs -----------------------------------------------------------
    def do_PROPFIND(self):  # noqa: N802
        rel = self.relpath()
        full = self.fullpath(rel)
        if not os.path.exists(full):
            self.send_body(404, b"not found", "text/plain")
            return
        responses = [propfind_entry(self.root, rel)]
        if self.headers.get("Depth", "1") != "0" and os.path.isdir(full):
            for name in sorted(os.listdir(full)):
                child = name if not rel else f"{rel}/{name}"
                responses.append(propfind_entry(self.root, child))
        body = (
            '<?xml version="1.0" encoding="utf-8"?>'
            '<D:multistatus xmlns:D="DAV:">' + "".join(responses) + "</D:multistatus>"
        ).encode("utf-8")
        self.send_body(207, body, "application/xml; charset=utf-8")

    def do_HEAD(self):  # noqa: N802
        self.do_GET()

    def do_GET(self):  # noqa: N802
        if self.first_byte_delay > 0:
            time.sleep(self.first_byte_delay)
        rel = self.relpath()
        full = self.fullpath(rel)
        if not os.path.isfile(full):
            self.send_body(404, b"not found", "text/plain")
            return
        size = os.path.getsize(full)
        content_type = mimetypes.guess_type(full)[0] or "application/octet-stream"
        range_header = self.headers.get("Range")
        start, end = 0, size - 1
        status = 200
        extra = {}
        if range_header and range_header.startswith("bytes="):
            spec = range_header[len("bytes="):].split(",")[0]
            first, _, last = spec.partition("-")
            try:
                if first:
                    start = int(first)
                    end = int(last) if last else size - 1
                elif last:
                    start = max(0, size - int(last))
                status = 206
                end = min(end, size - 1)
                extra["Content-Range"] = f"bytes {start}-{end}/{size}"
            except ValueError:
                start, end, status = 0, size - 1, 200
                extra = {}
        length = max(0, end - start + 1)
        if self.command == "HEAD" or self.rate_bytes <= 0:
            with open(full, "rb") as handle:
                handle.seek(start)
                body = handle.read(length)
            if status == 206:
                self.send_response(206)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Content-Range", extra["Content-Range"])
                self.send_header("Accept-Ranges", "bytes")
                self.end_headers()
                self.wfile.write(body)
            else:
                self.send_body(200, body, content_type)
            return

        # Throttled streaming: lets the acceptance run exercise the buffering
        # HUD and the cached-span highlight on a local server.
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(length))
        self.send_header("Accept-Ranges", "bytes")
        if status == 206:
            self.send_header("Content-Range", extra["Content-Range"])
        self.end_headers()
        chunk = 32 * 1024
        sent = 0
        stalled = False
        with open(full, "rb") as handle:
            handle.seek(start)
            while sent < length:
                data = handle.read(min(chunk, length - sent))
                if not data:
                    break
                try:
                    self.wfile.write(data)
                    self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError):
                    return
                sent += len(data)
                time.sleep(len(data) / self.rate_bytes)
                if (not stalled and self.stall_after_bytes > 0
                        and sent >= self.stall_after_bytes and self.stall_seconds > 0):
                    stalled = True
                    time.sleep(self.stall_seconds)

    def do_OPTIONS(self):  # noqa: N802
        self.send_response(200)
        self.send_header("DAV", "1,2")
        self.send_header("Allow", "OPTIONS, GET, HEAD, PROPFIND")
        self.send_header("Content-Length", "0")
        self.end_headers()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--port", type=int, default=8099)
    parser.add_argument("--rate-bytes", type=int, default=0,
                        help="throttle GET bodies to this many bytes per second (0 = unlimited)")
    parser.add_argument("--first-byte-delay", type=float, default=0.0,
                        help="sleep this many seconds before answering GET (simulates a slow origin)")
    parser.add_argument("--stall-after-bytes", type=int, default=0,
                        help="pause this connection after sending N bytes (simulates a network stall)")
    parser.add_argument("--stall-seconds", type=float, default=0.0,
                        help="length of that pause")
    args = parser.parse_args()

    Handler.root = os.path.abspath(args.root)
    Handler.rate_bytes = max(0, args.rate_bytes)
    Handler.first_byte_delay = max(0.0, args.first_byte_delay)
    Handler.stall_after_bytes = max(0, args.stall_after_bytes)
    Handler.stall_seconds = max(0.0, args.stall_seconds)
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    # Threaded: while a throttled GET streams the body, mpv opens a second
    # connection for the tail/seek-head; a single-threaded server would deadlock
    # the demuxer.
    with socketserver.ThreadingTCPServer(("127.0.0.1", args.port), Handler) as httpd:
        httpd.daemon_threads = True
        print(f"webdav fixture on http://127.0.0.1:{args.port}{BASE_PATH}/ -> {Handler.root}", flush=True)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
