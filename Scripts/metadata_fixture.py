#!/usr/bin/env python3
"""Local TMDB/OMDb fixture for metadata acceptance. Serves only public IDs and
fixed sample data; no WebDAV paths or credentials are accepted."""
import argparse
import json
import os
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

ROOT = os.path.dirname(os.path.abspath(__file__))
IMG_DIR = os.path.join(ROOT, "..", "build", "metadata-fixture", "img")

def ensure_images():
    os.makedirs(IMG_DIR, exist_ok=True)
    specs = {
        "poster-got.png": "0x23395d", "poster-aot.png": "0x5a2a1a",
        "poster-inception.png": "0x1b3b4b",
        "still-got-1.png": "0x2f4f6f", "still-got-2.png": "0x405070",
        "still-got-10.png": "0x503060", "still-aot-13.png": "0x704020",
    }
    for name, color in specs.items():
        path = os.path.join(IMG_DIR, name)
        if os.path.exists(path):
            continue
        subprocess.run([
            "ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
            f"color=c={color}:s=320x180:d=1", "-frames:v", "1", path,
        ], check=False)

def episodes(show, season, items):
    return {
        "episodes": [
            {
                "season_number": season, "episode_number": number,
                "name": title, "overview": overview,
                "still_path": f"/{still}", "runtime": 60,
                "air_date": "2011-04-17", "vote_average": rating,
            }
            for number, title, overview, still, rating in items
        ]
    }

DATA = {
    "tv": {
        1399: {
            "id": 1399, "name": "Game of Thrones", "overview": "七大王国的贵族家族为铁王座展开争斗。",
            "first_air_date": "2011-04-17", "poster_path": "/poster-got.png",
            "backdrop_path": "/still-got-1.png", "vote_average": 8.4, "vote_count": 22000,
            "external_ids": {"imdb_id": "tt0944947"},
            "seasons": [{"season_number": 1, "name": "第 1 季", "episode_count": 10, "poster_path": "/poster-got.png"}],
        },
        1429: {
            "id": 1429, "name": "进击的巨人", "overview": "人类与巨人的生存之战。",
            "first_air_date": "2013-04-07", "poster_path": "/poster-aot.png",
            "backdrop_path": "/still-aot-13.png", "vote_average": 8.7, "vote_count": 12000,
            "external_ids": {"imdb_id": "tt2560140"},
            "seasons": [{"season_number": 3, "name": "第 3 季", "episode_count": 22, "poster_path": "/poster-aot.png"}],
        },
    },
    "movie": {
        27205: {
            "id": 27205, "title": "盗梦空间", "overview": "一名窃贼潜入他人梦境窃取秘密。",
            "release_date": "2010-07-16", "poster_path": "/poster-inception.png",
            "backdrop_path": "/still-got-1.png", "vote_average": 8.4, "vote_count": 35000,
            "external_ids": {"imdb_id": "tt1375666"}, "seasons": [],
        },
    },
    "seasons": {
        (1399, 1): episodes("got", 1, [
            (1, "Winter Is Coming", "奈德·史塔克面临来自南方的邀请。", "still-got-1.png", 8.0),
            (2, "The Kingsroad", "奈德带着女儿们南下，琼恩前往长城。", "still-got-2.png", 8.2),
            (10, "Fire and Blood", "龙妈在火中重生，新的时代开始。", "still-got-10.png", 9.0),
        ]),
        (1429, 3): episodes("aot", 3, [
            (13, "地下室", "调查兵团终于抵达地下室。", "still-aot-13.png", 8.9),
        ]),
    },
    "omdb": {
        "tt0944947": {"Title": "Game of Thrones", "imdbRating": "9.2", "Metascore": "86",
                      "Ratings": [{"Source": "Internet Movie Database", "Value": "9.2/10"},
                                  {"Source": "Rotten Tomatoes", "Value": "89%"},
                                  {"Source": "Metacritic", "Value": "86/100"}]},
        "tt2560140": {"Title": "Attack on Titan", "imdbRating": "9.0", "Metascore": "81",
                      "Ratings": [{"Source": "Internet Movie Database", "Value": "9.0/10"},
                                  {"Source": "Rotten Tomatoes", "Value": "95%"},
                                  {"Source": "Metacritic", "Value": "81/100"}]},
        "tt1375666": {"Title": "Inception", "imdbRating": "8.8", "Metascore": "74",
                      "Ratings": [{"Source": "Internet Movie Database", "Value": "8.8/10"},
                                  {"Source": "Rotten Tomatoes", "Value": "87%"},
                                  {"Source": "Metacritic", "Value": "74/100"}]},
    },
}

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send_json(self, payload, status=200):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        path = parsed.path
        if path.startswith("/img/"):
            file = os.path.join(IMG_DIR, os.path.basename(path))
            if not os.path.exists(file):
                self.send_error(404); return
            data = open(file, "rb").read()
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers(); self.wfile.write(data); return
        if path == "/omdb" or path.startswith("/omdb/"):
            key = (query.get("i") or [""])[0]
            if key in DATA["omdb"]:
                self.send_json(DATA["omdb"][key])
            else:
                self.send_json({"Response": "False", "Error": "not found"}, 404)
            return
        if path.endswith("/search/tv"):
            q = (query.get("query") or [""])[0].lower()
            results = []
            for ident, show in DATA["tv"].items():
                if q in show["name"].lower() or "thrones" in q and ident == 1399 or "巨人" in q and ident == 1429:
                    results.append({"id": ident, "name": show["name"],
                                    "first_air_date": show["first_air_date"],
                                    "overview": show["overview"], "poster_path": show["poster_path"]})
            self.send_json({"results": results}); return
        if path.endswith("/search/movie"):
            q = (query.get("query") or [""])[0].lower()
            results = []
            for ident, movie in DATA["movie"].items():
                if q in movie["title"].lower() or "inception" in q:
                    results.append({"id": ident, "title": movie["title"],
                                    "release_date": movie["release_date"],
                                    "overview": movie["overview"], "poster_path": movie["poster_path"]})
            self.send_json({"results": results}); return
        parts = [p for p in path.split("/") if p]
        if len(parts) >= 3 and parts[-2] == "season":
            try:
                tv_id = int(parts[-3]); season = int(parts[-1])
                payload = DATA["seasons"].get((tv_id, season))
            except ValueError:
                payload = None
            if payload:
                self.send_json(payload)
            else:
                self.send_json({"episodes": []})
            return
        if len(parts) >= 2 and parts[-2] in ("tv", "movie"):
            try:
                ident = int(parts[-1]); kind = parts[-2]
                payload = DATA[kind].get(ident)
            except ValueError:
                payload = None
            if payload:
                self.send_json(payload)
            else:
                self.send_json({}, 404)
            return
        self.send_json({}, 404)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=0)
    args = parser.parse_args()
    ensure_images()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(server.server_address[1], flush=True)
    server.serve_forever()
