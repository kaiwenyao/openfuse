#!/usr/bin/env python3
"""Minimal Jellyfin server fixture for macOS browser/detail acceptance.

Serves three library views, Fargo S1 episodes, an Inception movie with two
versions, images, people, ratings and media-stream metadata. The stream endpoint
serves a small locally generated video with Range support.
"""
import argparse
import json
import os
import re
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

ROOT = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(ROOT, "..", "build", "jellyfin-fixture")
IMG = os.path.join(WORK, "img")
VIDEO = os.path.join(WORK, "video.mp4")
TOKEN = "demo-token"
USER_ID = "user-demo"
SERVER_ID = "server-demo"

def ensure_assets(video_source):
    os.makedirs(IMG, exist_ok=True)
    if not os.path.exists(VIDEO):
        subprocess.run([
            "ffmpeg", "-v", "error", "-y", "-i", video_source, "-t", "20",
            "-vf", "scale=640:360", "-c:v", "libx264", "-preset", "ultrafast",
            "-c:a", "aac", "-b:a", "96k", VIDEO,
        ], check=False)
    specs = {
        "lib-tv": ("640x360", "0x27405f", "电视剧库"),
        "lib-movies": ("640x360", "0x5b3324", "电影库"),
        "lib-folder": ("640x360", "0x3f4a3a", "文件夹"),
        "fargo": ("300x450", "0x1d2f45", "FARGO"),
        "fargo-s1": ("300x450", "0x26384f", "S1"),
        "fargo-s2": ("300x450", "0x30465f", "S2"),
        "inception": ("300x450", "0x143b4a", "INCEPTION"),
        "fargo-s1e1": ("640x360", "0x4a4f60", "E1"),
        "fargo-s1e2": ("640x360", "0x5a4038", "E2"),
        "fargo-s1e3": ("640x360", "0x3f5a48", "E3"),
        "fargo-s1e4": ("640x360", "0x5a4f2e", "E4"),
        "fargo-s1e5": ("640x360", "0x3a3f55", "E5"),
        "fargo-bd": ("1280x720", "0x20394f", "FARGO"),
        "inception-bd": ("1280x720", "0x143b4a", "INCEPTION"),
        "p1": ("200x200", "0x5b4a3a", "MARTIN"),
        "p2": ("200x200", "0x3a4a5b", "BILLY"),
        "p3": ("200x200", "0x4a5b3a", "ADAM"),
        "trickplay": ("640x180", "0x2a3a5a", "TRICK"),
    }
    for name, (size, color, label) in specs.items():
        path = os.path.join(IMG, name + ".png")
        if os.path.exists(path):
            continue
        font = "/System/Library/Fonts/Supplemental/Arial.ttf"
        draw = f"drawtext=fontfile={font}:text='{label}':fontcolor=white:fontsize=42:x=(w-text_w)/2:y=(h-text_h)/2"
        subprocess.run([
            "ffmpeg", "-v", "error", "-y", "-f", "lavfi",
            "-i", f"color=c={color}:s={size}:d=1", "-vf", draw,
            "-frames:v", "1", path,
        ], check=False)
        if not os.path.exists(path):
            subprocess.run([
                "ffmpeg", "-v", "error", "-y", "-f", "lavfi",
                "-i", f"color=c={color}:s={size}:d=1", "-frames:v", "1", path,
            ], check=False)

def image_for(item_id, kind="Primary"):
    if kind == "Backdrop":
        if item_id.startswith("fargo"):
            return "fargo-bd.png"
        if item_id.startswith("inception"):
            return "inception-bd.png"
        if item_id.startswith("lib-"):
            return item_id + ".png"
        return "fargo-bd.png"
    if item_id in ("lib-tv", "lib-movies", "lib-folder"):
        return item_id + ".png"
    if item_id.startswith("p"):
        return item_id + ".png"
    return item_id + ".png"

VIEWS = [
    {"Id": "lib-tv", "Name": "百度网盘电视剧", "Type": "CollectionFolder",
     "CollectionType": "tvshows", "ImageTags": {"Primary": "lib-tv"},
     "BackdropImageTags": ["lib-tv"]},
    {"Id": "lib-movies", "Name": "百度网盘电影", "Type": "CollectionFolder",
     "CollectionType": "movies", "ImageTags": {"Primary": "lib-movies"},
     "BackdropImageTags": ["lib-movies"]},
    {"Id": "lib-folder", "Name": "文件夹", "Type": "UserView",
     "ImageTags": {"Primary": "lib-folder"}, "BackdropImageTags": ["lib-folder"]},
]

PEOPLE = [
    {"Id": "p1", "Name": "Martin Freeman", "Role": "Lester Nygaard", "Type": "Actor", "PrimaryImageTag": "p1"},
    {"Id": "p2", "Name": "Billy Bob Thornton", "Role": "Lorne Malvo", "Type": "Actor", "PrimaryImageTag": "p2"},
    {"Id": "p3", "Name": "Adam Bernstein", "Type": "Director", "PrimaryImageTag": "p3"},
]

def episode(number, title, overview, progress=0.0):
    duration = 55 * 60 * 10_000_000
    return {
        "Id": f"fargo-s1e{number}", "Name": title, "Type": "Episode",
        "SeriesId": "fargo", "SeriesName": "冰血暴", "SeasonId": "fargo-s1",
        "IndexNumber": number, "ParentIndexNumber": 1,
        "RunTimeTicks": duration, "Overview": overview,
        "ImageTags": {"Primary": f"fargo-s1e{number}"},
        "UserData": {"PlaybackPositionTicks": int(duration * progress), "Played": False, "PlayCount": 0},
        "CommunityRating": 8.0 + number / 10.0,
    }

EPISODES = [
    episode(1, "鳄鱼的困境", "莱斯特在医院遇见了一个神秘的陌生人。", 0.2),
    episode(2, "公鸡王子", "莱斯特与马尔沃的相遇改变了小镇。"),
    episode(3, "泥泞之路", "警长开始调查一连串离奇事件。"),
    episode(4, "承受指责", "过去的事情开始找上门来。"),
    episode(5, "六不收", "小镇的暴力继续升级。"),
]

DETAILS = {
    "lib-tv": VIEWS[0], "lib-movies": VIEWS[1], "lib-folder": VIEWS[2],
    "fargo": {
        "Id": "fargo", "Name": "冰血暴", "Type": "Series",
        "Overview": "小镇保险推销员莱斯特遇见了神秘杀手马尔沃，一场关于谎言与暴力的故事就此展开。",
        "ProductionYear": 2014, "PremiereDate": "2014-04-15T00:00:00.0000000Z",
        "CommunityRating": 8.6, "CriticRating": 93, "OfficialRating": "TV-MA",
        "Genres": ["犯罪", "剧情"], "ProviderIds": {"Imdb": "tt2802850"},
        "ImageTags": {"Primary": "fargo"}, "BackdropImageTags": ["fargo-bd"],
        "People": PEOPLE,
    },
    "fargo-s1": {"Id": "fargo-s1", "Name": "第 1 季", "Type": "Season", "SeriesId": "fargo",
                 "SeriesName": "冰血暴", "IndexNumber": 1, "ImageTags": {"Primary": "fargo-s1"}},
    "fargo-s2": {"Id": "fargo-s2", "Name": "第 2 季", "Type": "Season", "SeriesId": "fargo",
                 "SeriesName": "冰血暴", "IndexNumber": 2, "ImageTags": {"Primary": "fargo-s2"}},
    "missing-art": {
        "Id": "missing-art", "Name": "无图样片", "Type": "Movie",
        "Overview": "这个条目没有海报、横幅、评分或演职员，用来验证缺图回退。",
        "ProductionYear": 2024,
    },
    "inception": {
        "Id": "inception", "Name": "盗梦空间", "Type": "Movie",
        "Overview": "一名窃贼潜入他人梦境窃取秘密，却被要求完成一次反向的植入。",
        "ProductionYear": 2010, "PremiereDate": "2010-07-16T00:00:00.0000000Z",
        "CommunityRating": 8.8, "CriticRating": 87, "OfficialRating": "PG-13",
        "Genres": ["科幻", "动作"], "ProviderIds": {"Imdb": "tt1375666"},
        "ImageTags": {"Primary": "inception"}, "BackdropImageTags": ["inception-bd"],
        "People": PEOPLE,
        "Trickplay": {"src-inception-1080": {"Width": 320, "Height": 180, "TileWidth": 2,
                                              "TileHeight": 1, "Interval": 5000, "ThumbnailCount": 2}},
    },
}
for ep in EPISODES:
    DETAILS[ep["Id"]] = ep

def media_source(media_id, name, size, total_bitrate, video_bitrate, width, height, fps, container="mkv"):
    return {
        "Id": media_id, "Name": name, "Container": container,
        "Size": size, "Bitrate": total_bitrate,
        "SupportsDirectPlay": True, "SupportsDirectStream": True,
        "DirectStreamUrl": f"/videos/{media_id}/stream?Static=true&MediaSourceId={media_id}",
        "MediaStreams": [
            {"Type": "Video", "Index": 0, "Codec": "hevc", "Profile": "Main 10",
             "Width": width, "Height": height, "BitDepth": 10,
             "VideoRange": "HDR", "VideoRangeType": "HDR10",
             "FrameRate": fps, "BitRate": video_bitrate, "IsDefault": True},
            {"Type": "Audio", "Index": 1, "Codec": "aac", "Channels": 6,
             "ChannelLayout": "5.1", "Language": "jpn", "IsDefault": True,
             "BitRate": 192000},
            {"Type": "Subtitle", "Index": 2, "Codec": "ass", "Language": "zh",
             "IsDefault": True, "IsExternal": False},
        ],
    }

PLAYBACK = {}
for ep in EPISODES:
    eid = ep["Id"]
    PLAYBACK[eid] = {"MediaSources": [
        media_source("src-" + eid, "1080p HEVC", 957_900_000, 1_700_000, 1_500_000, 1920, 1080, 24000 / 1001)
    ]}
PLAYBACK["missing-art"] = {"MediaSources": [
    media_source("src-missing-art", "720p", 300_000_000, 900_000, 800_000, 1280, 720, 25)
]}
PLAYBACK["inception"] = {"MediaSources": [
    media_source("src-inception-1080", "1080p BluRay", 1_200_000_000, 2_500_000, 2_200_000, 1920, 1080, 24000 / 1001),
    media_source("src-inception-2160", "2160p HDR", 4_500_000_000, 12_000_000, 11_000_000, 3840, 2160, 24),
]}

def items_for(parent):
    if parent == "lib-tv":
        return [DETAILS["fargo"]]
    if parent == "lib-movies":
        return [DETAILS["inception"], DETAILS["missing-art"]]
    if parent == "lib-folder":
        return []
    if parent == "fargo":
        return [DETAILS["fargo-s1"], DETAILS["fargo-s2"]]
    if parent == "fargo-s1":
        return EPISODES
    if parent == "fargo-s2":
        return []
    return []

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def json(self, payload, status=200):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def image(self, name):
        path = os.path.join(IMG, name)
        if not os.path.exists(path):
            self.send_error(404); return
        data = open(path, "rb").read()
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers(); self.wfile.write(data)

    def stream(self):
        if not os.path.exists(VIDEO):
            self.send_error(404); return
        size = os.path.getsize(VIDEO)
        range_header = self.headers.get("Range")
        start, end = 0, size - 1
        status = 200
        if range_header:
            match = re.match(r"bytes=(\d+)-(\d*)", range_header)
            if match:
                start = int(match.group(1))
                end = int(match.group(2)) if match.group(2) else size - 1
                status = 206
        length = max(0, end - start + 1)
        self.send_response(status)
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(length))
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        with open(VIDEO, "rb") as handle:
            handle.seek(start)
            remaining = length
            while remaining > 0:
                chunk = handle.read(min(64 * 1024, remaining))
                if not chunk: break
                self.wfile.write(chunk)
                remaining -= len(chunk)

    def do_HEAD(self):
        if self.path.startswith("/videos/"):
            size = os.path.getsize(VIDEO) if os.path.exists(VIDEO) else 0
            self.send_response(200)
            self.send_header("Content-Type", "video/mp4")
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Length", str(size))
            self.end_headers()
        else:
            self.send_error(404)

    def do_POST(self):
        parsed = urlparse(self.path)
        length = int(self.headers.get("Content-Length", "0"))
        if length:
            self.rfile.read(length)
        if parsed.path.endswith("/Users/AuthenticateByName"):
            self.json({
                "User": {"Id": USER_ID, "Name": "demo", "ServerId": SERVER_ID},
                "AccessToken": TOKEN, "ServerId": SERVER_ID,
            }); return
        match = re.match(r"/Items/([^/]+)/PlaybackInfo", parsed.path)
        if match and match.group(1) in PLAYBACK:
            payload = dict(PLAYBACK[match.group(1)])
            payload["PlaySessionId"] = "session-" + match.group(1)
            self.json(payload); return
        self.json({}, 404)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        if path == "/omdb" or path.startswith("/omdb/"):
            key = (parse_qs(parsed.query).get("i") or [""])[0]
            ratings = {
                "tt2802850": {"Title": "Fargo", "imdbRating": "9.0", "Metascore": "85",
                              "Ratings": [{"Source": "Internet Movie Database", "Value": "9.0/10"},
                                          {"Source": "Rotten Tomatoes", "Value": "95%"},
                                          {"Source": "Metacritic", "Value": "85/100"}]},
                "tt1375666": {"Title": "Inception", "imdbRating": "8.8", "Metascore": "74",
                              "Ratings": [{"Source": "Internet Movie Database", "Value": "8.8/10"},
                                          {"Source": "Rotten Tomatoes", "Value": "87%"},
                                          {"Source": "Metacritic", "Value": "74/100"}]},
            }
            if key in ratings:
                self.json(ratings[key])
            else:
                self.json({"Response": "False"}, 404)
            return
        if path.startswith("/videos/"):
            self.stream(); return
        trick_match = re.match(r"/Items/([^/]+)/Trickplay/(\d+)/(\d+)\.jpg", path)
        if trick_match:
            self.image("trickplay.png"); return
        image_match = re.match(r"/Items/([^/]+)/Images/(Primary|Backdrop)(?:/(\d+))?", path)
        if image_match:
            self.image(image_for(image_match.group(1), image_match.group(2))); return
        if path.endswith("/Users/" + USER_ID + "/Views") or path.endswith("/Users/user-demo/Views"):
            self.json({"Items": VIEWS, "TotalRecordCount": len(VIEWS)}); return
        items_match = re.match(r"/Users/[^/]+/Items/?$", path)
        if items_match:
            parent = (parse_qs(parsed.query).get("ParentId") or [""])[0]
            items = items_for(parent)
            self.json({"Items": items, "TotalRecordCount": len(items)}); return
        item_match = re.match(r"/Users/[^/]+/Items/([^/]+)$", path)
        if item_match:
            item = DETAILS.get(item_match.group(1))
            if item:
                self.json(item)
            else:
                self.json({}, 404)
            return
        if path.endswith("/System/Info/Public"):
            self.json({"ServerName": "Fixture", "Id": SERVER_ID}); return
        self.json({}, 404)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--video", default=os.path.join(ROOT, "..", "Fixtures", "generated", "openfuse-fixture.mkv"))
    args = parser.parse_args()
    ensure_assets(os.path.abspath(args.video))
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(server.server_address[1], flush=True)
    server.serve_forever()
