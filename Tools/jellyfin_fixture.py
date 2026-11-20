#!/usr/bin/env python3
"""Minimal Jellyfin 10.x-compatible fixture for OpenFuse M2b.

Implements the endpoints OpenFuse uses: AuthenticateByName, Views, Items,
PlaybackInfo, stream with Range, Primary images and the three Sessions/Playing
progress calls. Media is the OpenFuse fixture; metadata is synthetic.

    python3 Tools/jellyfin_fixture.py --setup
    python3 Tools/jellyfin_fixture.py --port 8096

Credentials: test / test
Token: jf-test-token
Log: build/jellyfin.log (JSON lines, includes progress bodies)
"""
from __future__ import annotations

import argparse
import base64
import datetime
import hashlib
import json
import os
import re
import shutil
import socketserver
import subprocess
import threading
import urllib.parse
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

FIXTURE = os.path.abspath("Fixtures/generated/openfuse-fixture.mkv")
ROOT = os.path.abspath("build/jellyfin-fixture")
LOG_PATH = os.path.abspath("build/jellyfin.log")
USER_ID = "user-1"
TOKEN = "jf-test-token"
USERNAME = "test"
PASSWORD = "test"
THROTTLE_KBPS = 0
LOG_LOCK = threading.Lock()
POSITIONS: dict[str, int] = {}

RUN_TIME_TICKS = 600_000_000
MOBILE_SAMPLE = False
MOBILE_MP4 = os.path.abspath("Fixtures/mobile/openfuse-mobile.mp4")
HLS_DIR = os.path.abspath("build/hls-fixture")


def setup_posters() -> None:
    if not os.path.exists(FIXTURE):
        raise SystemExit(f"missing fixture: {FIXTURE}")
    os.makedirs(ROOT, exist_ok=True)
    for name, seconds in [
        ("movie", 5.5),
        ("movie-alt", 25.5),
        ("series", 35.5),
        ("season", 45.5),
        ("episode", 15.5),
        ("episode2", 44.5),
    ]:
        path = os.path.join(ROOT, f"{name}.jpg")
        if os.path.exists(path):
            continue
        subprocess.run(
            [
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                "-ss", str(seconds), "-i", FIXTURE, "-frames:v", "1",
                "-vf", "scale=400:600:force_original_aspect_ratio=increase,crop=400:600",
                path,
            ],
            check=True,
        )
    print(f"poster fixtures ready: {ROOT}")


def item(
    id: str,
    name: str,
    type: str,
    parent: str | None = None,
    series_id: str | None = None,
    series_name: str | None = None,
    season_id: str | None = None,
    index: int | None = None,
    parent_index: int | None = None,
    year: int | None = None,
    overview: str | None = None,
    image_tag: str | None = None,
    run_time: int | None = None,
    collection_type: str | None = None,
) -> dict:
    created = {"movie-1": "2026-01-10T00:00:00Z", "series-1": "2026-02-10T00:00:00Z"}.get(
        id, "2026-02-11T00:00:00Z"
    )
    result = {
        "Id": id,
        "Name": name,
        "Type": type,
        "DateCreated": created,
        "ImageTags": {"Primary": image_tag or id},
        "UserData": {
            "PlaybackPositionTicks": POSITIONS.get(id, 0),
            "Played": False,
            "PlayCount": 0,
        },
    }
    if parent: result["ParentId"] = parent
    if series_id: result["SeriesId"] = series_id
    if series_name: result["SeriesName"] = series_name
    if season_id: result["SeasonId"] = season_id
    if index is not None: result["IndexNumber"] = index
    if parent_index is not None: result["ParentIndexNumber"] = parent_index
    if year is not None: result["ProductionYear"] = year
    if overview: result["Overview"] = overview
    if run_time is not None: result["RunTimeTicks"] = run_time
    if collection_type: result["CollectionType"] = collection_type
    return result


def views() -> list[dict]:
    return [
        item("lib-movies", "电影", "CollectionFolder", image_tag="movie", collection_type="movies"),
        item("lib-tv", "电视剧", "CollectionFolder", image_tag="series", collection_type="tvshows"),
    ]


def children(parent: str | None) -> list[dict]:
    if parent is None:
        return views()
    if parent == "lib-movies":
        movies = [
            item(
                "movie-1", "OpenFuse Fixture (2026)", "Movie", parent=parent, year=2026,
                overview="OpenFuse 自制的 HEVC Main 10、E-AC-3 5.1 与中日双语 ASS 测试片。",
                image_tag="movie", run_time=RUN_TIME_TICKS,
            )
        ]
        if MOBILE_SAMPLE:
            movies.append(
                item(
                    "movie-mobile", "OpenFuse Mobile Sample (2026)", "Movie", parent=parent, year=2026,
                    overview="H.264/AAC 20 秒样片，用于移动端 AVPlayer 远程播放测试。",
                    image_tag="movie", run_time=20 * 10_000_000,
                )
            )
        return movies
    if parent == "lib-tv":
        return [
            item(
                "series-1", "示例剧", "Series", parent=parent,
                overview="用于验证季/集层级、字幕与续播的测试剧。",
                image_tag="series",
            )
        ]
    if parent == "series-1":
        return [
            item("season-1", "第 1 季", "Season", parent=parent, series_id="series-1",
                 series_name="示例剧", index=1, image_tag="season"),
        ]
    if parent == "season-1":
        return [
            item("ep-1", "第 1 集", "Episode", parent=parent, series_id="series-1",
                 series_name="示例剧", season_id="season-1", index=1, parent_index=1,
                 image_tag="episode", run_time=RUN_TIME_TICKS,
                 overview="第一集：验证服务器片名、封面、音轨、字幕与进度回写。"),
            item("ep-2", "第 2 集", "Episode", parent=parent, series_id="series-1",
                 series_name="示例剧", season_id="season-1", index=2, parent_index=1,
                 image_tag="episode2", run_time=RUN_TIME_TICKS,
                 overview="第二集：用于下一集与续播。"),
        ]
    return []


def descendants(parent: str | None) -> list[dict]:
    result: list[dict] = []

    def walk(node: str | None) -> None:
        for entry in children(node):
            result.append(entry)
            walk(entry["Id"])

    walk(parent)
    return result


def all_items() -> dict[str, dict]:
    result = {v["Id"]: v for v in views()}
    for parent in ["lib-movies", "lib-tv", "series-1", "season-1"]:
        for entry in children(parent):
            result[entry["Id"]] = entry
    return result


def media_streams() -> list[dict]:
    return [
        {"Type": "Video", "Index": 0, "Codec": "hevc", "Profile": "Main 10", "Width": 1920, "Height": 1080,
         "VideoRange": "HDR", "VideoRangeType": "HDR10",
         "DisplayTitle": "1080p HEVC Main 10 HDR10", "IsDefault": True},
        {"Type": "Audio", "Index": 1, "Codec": "eac3", "Language": "chi", "Channels": 6,
         "DisplayTitle": "服务器音轨 · E-AC-3 5.1", "IsDefault": True},
        {"Type": "Subtitle", "Index": 2, "Codec": "ass", "Language": "chi",
         "DisplayTitle": "服务器字幕 · 中日双语", "IsExternal": False, "IsDefault": True},
        {"Type": "Subtitle", "Index": 3, "Codec": "srt", "Language": "zho",
         "DisplayTitle": "外挂简体中文", "IsExternal": True, "IsDefault": False,
         "DeliveryUrl": "/Videos/movie-1/subtitles/zh-Hans.srt"},
    ]


def playback_info(item_id: str) -> dict:
    if item_id == "movie-mobile":
        return {
            "PlaySessionId": "play-" + os.urandom(4).hex(),
            "MediaSources": [
                {
                    "Id": "ms-mobile",
                    "Name": "Mobile H.264 720p",
                    "Container": "mp4",
                    "RunTimeTicks": 20 * 10_000_000,
                    "SupportsDirectPlay": True,
                    "SupportsDirectStream": True,
                    "DirectStreamUrl": "/Videos/movie-mobile/stream?Static=true&MediaSourceId=ms-mobile",
                    "MediaStreams": [
                        {"Type": "Video", "Index": 0, "Codec": "h264", "Profile": "High", "Width": 1280, "Height": 720,
                         "DisplayTitle": "720p H.264", "IsDefault": True},
                        {"Type": "Audio", "Index": 1, "Codec": "aac", "Language": "und", "Channels": 2,
                         "DisplayTitle": "AAC 立体声", "IsDefault": True},
                        {"Type": "Subtitle", "Index": 2, "Codec": "srt", "Language": "zho",
                         "DisplayTitle": "外挂简体中文", "IsExternal": True, "IsDefault": False,
                         "DeliveryUrl": "/Videos/movie-mobile/subtitles/zh-Hans.srt"},
                    ],
                }
            ],
        }
    if item_id.startswith("ep-"):
        sources = [
            {
                "Id": "ms-" + item_id + "-1080",
                "Name": "1080p HEVC 5.1",
                "Container": "mkv",
                "RunTimeTicks": RUN_TIME_TICKS,
                "SupportsDirectPlay": True,
                "SupportsDirectStream": True,
                "DirectStreamUrl": f"/Videos/{item_id}/stream?Static=true&MediaSourceId=ms-{item_id}-1080",
                "MediaStreams": media_streams(),
            }
        ]
    else:
        sources = [
            {
                "Id": "ms-movie-1080",
                "Name": "1080p HEVC 5.1",
                "Container": "mkv",
                "RunTimeTicks": RUN_TIME_TICKS,
                "SupportsDirectPlay": True,
                "SupportsDirectStream": True,
                "DirectStreamUrl": "/Videos/movie-1/stream?Static=true&MediaSourceId=ms-movie-1080",
                "MediaStreams": media_streams(),
            },
            {
                "Id": "ms-movie-compact",
                "Name": "720p 压缩版",
                "Container": "mkv",
                "RunTimeTicks": RUN_TIME_TICKS,
                "SupportsDirectPlay": True,
                "SupportsDirectStream": True,
                "DirectStreamUrl": "/Videos/movie-1/stream?Static=true&MediaSourceId=ms-movie-compact",
                "MediaStreams": media_streams(),
            },
        ]
    return {"PlaySessionId": "play-" + os.urandom(4).hex(), "MediaSources": sources}


class FixtureServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True

    def server_bind(self) -> None:
        socketserver.TCPServer.server_bind(self)
        host, port = self.server_address[:2]
        self.server_name = str(host)
        self.server_port = int(port)


class Handler(BaseHTTPRequestHandler):
    server_version = "OpenFuseJellyfinFixture/1.0"
    protocol_version = "HTTP/1.1"

    def log_message(self, format: str, *args) -> None:
        pass

    def _record(self, status: int, extra: dict | None = None) -> None:
        entry = {
            "time": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "method": self.command,
            "path": self.path,
            "status": status,
        }
        if extra:
            entry.update(extra)
        with LOG_LOCK:
            with open(LOG_PATH, "a", encoding="utf-8") as handle:
                handle.write(json.dumps(entry, ensure_ascii=False) + "\n")

    def _token(self) -> str | None:
        header = self.headers.get("X-Emby-Token")
        if header:
            return header
        authorization = self.headers.get("Authorization", "")
        match = re.search(r'Token="([^"]+)"', authorization)
        if match:
            return match.group(1)
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
        return (query.get("api_key") or [None])[0]

    def _authorized(self) -> bool:
        return self._token() == TOKEN

    def _require_auth(self) -> bool:
        if self._authorized():
            return True
        self.send_response(HTTPStatus.UNAUTHORIZED)
        self.send_header("Content-Length", "0")
        self.end_headers()
        self._record(401)
        return False

    def _json(self, data: dict | list, status: int = 200) -> None:
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        self._record(status)

    def _empty(self, status: int = 204) -> None:
        self.send_response(status)
        self.send_header("Content-Length", "0")
        self.end_headers()
        self._record(status)

    def do_GET(self) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        path = urllib.parse.unquote(parsed.path)
        if path == "/System/Info/Public":
            self._json({"ServerName": "OpenFuse Fixture", "Version": "10.10.0", "Id": "fixture-server"})
            return
        if path.startswith("/Videos/movie-1/hls/") or path.startswith("/Videos/movie-mobile/hls/"):
            self._serve_hls_segment(os.path.basename(path))
            return
        if not self._require_auth():
            return
        if path.endswith("/master.m3u8") and path.startswith("/Videos/"):
            self._serve_hls_playlist()
            return
        if path.startswith("/Items/") and path.endswith("/Images/Primary"):
            item_id = path.split("/")[2]
            self._serve_image(item_id)
            return
        if path in ("/Videos/movie-mobile/subtitles/zh-Hans.srt", "/Videos/movie-1/subtitles/zh-Hans.srt"):
            subtitle = os.path.abspath("Fixtures/mobile/openfuse-mobile.zh-Hans.srt")
            if not os.path.exists(subtitle):
                self._empty(404)
                return
            with open(subtitle, "rb") as handle:
                data = handle.read()
            self.send_response(200)
            self.send_header("Content-Type", "application/x-subrip; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            self._record(200, {"subtitle": "zh-Hans"})
            return
        if path.startswith("/Videos/") and path.endswith("/stream"):
            item_id = path.split("/")[2]
            self._serve_stream(item_id)
            return
        if path.startswith("/Users/"):
            parts = [p for p in path.split("/") if p]
            # /Users/{id}/Views or /Users/{id}/Items[/{itemId}]
            if len(parts) >= 3 and parts[2] == "Views":
                self._json({"Items": views(), "TotalRecordCount": len(views())})
                return
            if len(parts) >= 3 and parts[2] == "Items":
                if len(parts) == 4:
                    item_id = parts[3]
                    entry = all_items().get(item_id)
                    if entry:
                        self._json(entry)
                    else:
                        self._empty(404)
                    return
                query = urllib.parse.parse_qs(parsed.query)
                parent = (query.get("ParentId") or [None])[0]
                recursive = (query.get("Recursive") or ["false"])[0].lower() == "true"
                entries = descendants(parent) if recursive else children(parent)
                self._json({"Items": entries, "TotalRecordCount": len(entries)})
                return
        self._empty(404)

    def do_POST(self) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        path = urllib.parse.unquote(parsed.path)
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length) if length else b"{}"
        if path == "/Users/AuthenticateByName":
            try:
                payload = json.loads(body)
            except Exception:
                payload = {}
            if payload.get("Username") == USERNAME and payload.get("Pw") == PASSWORD:
                self._json({
                    "User": {"Id": USER_ID, "Name": USERNAME, "Type": "User"},
                    "AccessToken": TOKEN,
                    "ServerId": "fixture-server",
                })
            else:
                self._empty(401)
            return
        if not self._require_auth():
            return
        if path.startswith("/Items/") and path.endswith("/PlaybackInfo"):
            item_id = path.split("/")[2]
            self._json(playback_info(item_id))
            return
        if path in ("/Sessions/Playing", "/Sessions/Playing/Progress", "/Sessions/Playing/Stopped"):
            try:
                payload = json.loads(body)
            except Exception:
                payload = {}
            item_id = payload.get("ItemId")
            position = int(payload.get("PositionTicks") or 0)
            if item_id and path != "/Sessions/Playing/Stopped":
                POSITIONS[item_id] = position
            if item_id and path == "/Sessions/Playing/Stopped":
                POSITIONS[item_id] = position
            self._record(204, {"event": path.rsplit("/", 1)[-1], "body": payload})
            self.send_response(204)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        self._empty(404)

    def _serve_image(self, item_id: str) -> None:
        mapping = {
            "movie-1": "movie.jpg",
            "movie-mobile": "movie.jpg",
            "series-1": "series.jpg",
            "season-1": "season.jpg",
            "ep-1": "episode.jpg",
            "ep-2": "episode2.jpg",
            "lib-movies": "movie-alt.jpg",
            "lib-tv": "series.jpg",
        }
        filename = mapping.get(item_id, "movie.jpg")
        full = os.path.join(ROOT, filename)
        if not os.path.exists(full):
            self._empty(404)
            return
        with open(full, "rb") as handle:
            data = handle.read()
        self.send_response(200)
        self.send_header("Content-Type", "image/jpeg")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        self._record(200)

    def do_HEAD(self) -> None:
        self.do_GET()

    def _serve_hls_playlist(self) -> None:
        playlist = os.path.join(HLS_DIR, "index.m3u8")
        if not os.path.exists(playlist):
            self._empty(404)
            return
        with open(playlist, "r", encoding="utf-8") as handle:
            lines = handle.read().splitlines()
        rewritten = []
        for line in lines:
            if line.startswith("#") or not line.strip():
                rewritten.append(line)
            else:
                rewritten.append("hls/" + os.path.basename(line))
        body = "\n".join(rewritten).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/vnd.apple.mpegurl")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)
        self._record(200, {"hls": "playlist"})

    def _serve_hls_segment(self, name: str) -> None:
        path = os.path.join(HLS_DIR, name)
        if not os.path.exists(path):
            self._empty(404)
            return
        with open(path, "rb") as handle:
            data = handle.read()
        self.send_response(200)
        self.send_header("Content-Type", "video/mp2t")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)
        self._record(200, {"hls": name, "bytes": len(data)})

    def _serve_stream(self, item_id: str) -> None:
        path = MOBILE_MP4 if item_id == "movie-mobile" else FIXTURE
        if not os.path.exists(path):
            self._empty(404)
            return
        size = os.path.getsize(path)
        range_header = self.headers.get("Range")
        start, end = 0, size - 1
        status = 200
        if range_header:
            match = re.match(r"bytes=(\d*)-(\d*)$", range_header.strip())
            if not match:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{size}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                self._record(416)
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
                self._record(416)
                return
            status = 206
        length = end - start + 1
        self.send_response(status)
        self.send_header("Content-Type", "video/mp4" if item_id == "movie-mobile" else "video/x-matroska")
        self.send_header("Content-Length", str(length))
        self.send_header("Accept-Ranges", "bytes")
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        if self.command == "HEAD":
            self._record(status, {"bytes": 0, "size": size, "start": start})
            return
        sent = 0
        with open(path, "rb") as handle:
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
                        import time
                        time.sleep(len(chunk) / (THROTTLE_KBPS * 1024))
            except (BrokenPipeError, ConnectionResetError):
                self._record(status, {"bytes": sent, "size": size, "start": start, "aborted": True})
                return
        self._record(status, {"bytes": sent, "size": size, "start": start})


def main() -> None:
    global ROOT, LOG_PATH, TOKEN, USERNAME, PASSWORD, THROTTLE_KBPS
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8096)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--root", default=ROOT)
    parser.add_argument("--log", default=LOG_PATH)
    parser.add_argument("--token", default=TOKEN)
    parser.add_argument("--user", default=USERNAME)
    parser.add_argument("--password", default=PASSWORD)
    parser.add_argument("--setup", action="store_true")
    parser.add_argument("--throttle-kbps", type=int, default=0)
    parser.add_argument("--mobile-sample", action="store_true")
    args = parser.parse_args()
    ROOT = os.path.abspath(args.root)
    LOG_PATH = os.path.abspath(args.log)
    TOKEN = args.token
    USERNAME = args.user
    PASSWORD = args.password
    THROTTLE_KBPS = args.throttle_kbps
    MOBILE_SAMPLE = args.mobile_sample
    if args.setup or not os.path.isdir(ROOT):
        setup_posters()
    os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
    server = FixtureServer((args.host, args.port), Handler)
    print(f"jellyfin fixture listening on http://{args.host}:{args.port} (user {USERNAME})", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
