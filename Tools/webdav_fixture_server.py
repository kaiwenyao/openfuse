#!/usr/bin/env python3
"""Small local WebDAV server for OpenFuse acceptance.

Serves one directory tree with PROPFIND (depth 0/1), GET/HEAD with byte ranges
and Basic auth. Deliberately mirrors what OpenList's WebDAV endpoint does for
the operations OpenFuse uses: list a directory, stat a file, range-read media,
and fetch sidecar subtitles.
"""
import argparse
import base64
import datetime
import html
import os
import posixpath
import re
import sys
import urllib.parse
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MIME = {
    ".mkv": "video/x-matroska",
    ".mp4": "video/mp4",
    ".m4v": "video/mp4",
    ".mov": "video/quicktime",
    ".ass": "text/x-ssa",
    ".srt": "application/x-subrip",
    ".vtt": "text/vtt",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
    ".nfo": "text/xml",
}

NS = 'xmlns:d="DAV:"'


def http_date(timestamp):
    return datetime.datetime.fromtimestamp(timestamp, datetime.timezone.utc).strftime(
        "%a, %d %b %Y %H:%M:%S GMT"
    )


def href_for(path):
    return urllib.parse.quote(path, safe="/")


class Handler(BaseHTTPRequestHandler):
    server_version = "OpenFuseWebDAVFixture/1.0"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    # --- helpers ---------------------------------------------------------
    def authorized(self):
        if not self.server.password:
            return True
        header = self.headers.get("Authorization", "")
        if not header.startswith("Basic "):
            return False
        try:
            decoded = base64.b64decode(header[6:]).decode("utf-8")
        except Exception:
            return False
        return decoded == f"{self.server.username}:{self.server.password}"

    def require_auth(self):
        if self.authorized():
            return True
        self.send_response(HTTPStatus.UNAUTHORIZED)
        self.send_header("WWW-Authenticate", 'Basic realm="OpenFuse"')
        self.send_header("Content-Length", "0")
        self.end_headers()
        return False

    def resolve(self):
        raw = urllib.parse.urlsplit(self.path).path
        decoded = urllib.parse.unquote(raw)
        normalized = posixpath.normpath("/" + decoded.lstrip("/"))
        full = os.path.realpath(os.path.join(self.server.root, normalized.lstrip("/")))
        root = os.path.realpath(self.server.root)
        if full != root and not full.startswith(root + os.sep):
            return None, None
        return normalized, full

    def file_mtime(self, full):
        try:
            return os.path.getmtime(full)
        except OSError:
            return 0

    def entry_xml(self, url_path, full, is_collection):
        display = os.path.basename(full.rstrip("/")) or "/"
        content_type = "httpd/unix-directory" if is_collection else MIME.get(
            os.path.splitext(full)[1].lower(), "application/octet-stream"
        )
        size = 0 if is_collection else os.path.getsize(full)
        etag = f'"{int(self.file_mtime(full))}-{size}"'
        resource = "<d:resourcetype><d:collection/></d:resourcetype>" if is_collection else "<d:resourcetype/>"
        return (
            "<d:response>"
            f"<d:href>{html.escape(href_for(url_path))}</d:href>"
            "<d:propstat><d:prop>"
            f"<d:displayname>{html.escape(display)}</d:displayname>"
            f"{resource}"
            f"<d:getcontenttype>{content_type}</d:getcontenttype>"
            f"<d:getcontentlength>{size}</d:getcontentlength>"
            f"<d:getlastmodified>{http_date(self.file_mtime(full))}</d:getlastmodified>"
            f"<d:getetag>{html.escape(etag)}</d:getetag>"
            "</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>"
            "</d:response>"
        )

    # --- methods ---------------------------------------------------------
    def read_body(self):
        try:
            length = int(self.headers.get("Content-Length", "0") or "0")
        except ValueError:
            length = 0
        if length > 0:
            self.rfile.read(min(length, 1 << 20))

    def do_OPTIONS(self):
        if not self.require_auth():
            return
        self.send_response(HTTPStatus.OK)
        self.send_header("DAV", "1")
        self.send_header("Allow", "OPTIONS, GET, HEAD, PROPFIND")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_PROPFIND(self):
        if not self.require_auth():
            return
        self.read_body()
        url_path, full = self.resolve()
        if full is None:
            self.send_error(HTTPStatus.BAD_REQUEST)
            return
        if not os.path.exists(full):
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        depth = self.headers.get("Depth", "1")
        collection = os.path.isdir(full)
        entries = [self.entry_xml(url_path, full, collection)]
        if collection and depth != "0":
            try:
                names = sorted(os.listdir(full))
            except OSError:
                names = []
            for name in names:
                child_full = os.path.join(full, name)
                child_path = url_path.rstrip("/") + "/" + name
                entries.append(self.entry_xml(child_path, child_full, os.path.isdir(child_full)))
        body = (
            '<?xml version="1.0" encoding="utf-8"?>'
            f"<d:multistatus {NS}>{''.join(entries)}</d:multistatus>"
        ).encode("utf-8")
        self.send_response(207)
        self.send_header("Content-Type", "application/xml; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_HEAD(self):
        self.serve_file(head_only=True)

    def do_GET(self):
        self.serve_file(head_only=False)

    def serve_file(self, head_only):
        if not self.require_auth():
            return
        _, full = self.resolve()
        if full is None:
            self.send_error(HTTPStatus.BAD_REQUEST)
            return
        if not os.path.isfile(full):
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        size = os.path.getsize(full)
        start, end = 0, size - 1
        status = HTTPStatus.OK
        range_header = self.headers.get("Range")
        if range_header:
            match = re.match(r"bytes=(\d*)-(\d*)$", range_header.strip())
            if not match:
                self.send_error(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
                return
            first, last = match.groups()
            if first:
                start = int(first)
                if last:
                    end = min(int(last), size - 1)
            elif last:
                length = int(last)
                start = max(0, size - length)
            if start >= size or start > end:
                self.send_response(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
                self.send_header("Content-Range", f"bytes */{size}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            status = HTTPStatus.PARTIAL_CONTENT
        length = end - start + 1
        self.send_response(status)
        self.send_header("Content-Type", MIME.get(os.path.splitext(full)[1].lower(), "application/octet-stream"))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(length))
        if status == HTTPStatus.PARTIAL_CONTENT:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Last-Modified", http_date(self.file_mtime(full)))
        self.end_headers()
        if head_only:
            return
        with open(full, "rb") as handle:
            handle.seek(start)
            remaining = length
            while remaining > 0:
                chunk = handle.read(min(256 * 1024, remaining))
                if not chunk:
                    break
                try:
                    self.wfile.write(chunk)
                except (BrokenPipeError, ConnectionResetError):
                    return
                remaining -= len(chunk)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--port", type=int, default=8088)
    parser.add_argument("--user", default="openfuse")
    parser.add_argument("--password", default="openfuse")
    args = parser.parse_args()
    httpd = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    httpd.root = os.path.realpath(args.root)
    httpd.username = args.user
    httpd.password = args.password
    print(f"webdav on http://127.0.0.1:{args.port}/ root={httpd.root} user={args.user}", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
