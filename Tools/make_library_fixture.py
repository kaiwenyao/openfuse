#!/usr/bin/env python3
"""Build a small local library tree for M3 scan/grouping tests."""
from __future__ import annotations

import os
import shutil

ROOT = os.path.abspath("build/library-fixture")
FIXTURE = os.path.abspath("Fixtures/generated/openfuse-fixture.mkv")
SUBS = "Fixtures/generated"
POSTER_DIR = os.path.abspath("build/jellyfin-fixture")


def link_or_copy(source: str, destination: str) -> None:
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    if os.path.exists(destination):
        return
    try:
        os.link(source, destination)
    except OSError:
        shutil.copy2(source, destination)


def main() -> None:
    if not os.path.exists(FIXTURE):
        raise SystemExit("missing fixture; run Scripts/make_fixtures.sh")
    movie = os.path.join(ROOT, "Movies", "OpenFuse Fixture (2026)")
    link_or_copy(FIXTURE, os.path.join(movie, "OpenFuse Fixture (2026).mkv"))
    for source, target in [
        ("openfuse-fixture.zh-Hans.ass", "OpenFuse Fixture (2026).zh-Hans.ass"),
        ("openfuse-fixture.zh-Hant.ass", "OpenFuse Fixture (2026).zh-Hant.ass"),
    ]:
        link_or_copy(os.path.join(SUBS, source), os.path.join(movie, target))
    link_or_copy(os.path.join(POSTER_DIR, "movie.jpg"), os.path.join(movie, "poster.jpg"))

    show = os.path.join(ROOT, "Shows", "示例剧")
    season = os.path.join(show, "Season 01")
    for number in (1, 2):
        episode = os.path.join(season, f"示例剧.S01E0{number}.mkv")
        link_or_copy(FIXTURE, episode)
        link_or_copy(
            os.path.join(SUBS, "openfuse-fixture.zh-Hans.ass"),
            os.path.join(season, f"示例剧.S01E0{number}.zh-Hans.ass"),
        )
    link_or_copy(os.path.join(POSTER_DIR, "series.jpg"), os.path.join(show, "poster.jpg"))

    show2 = os.path.join(ROOT, "Shows", "另一部剧")
    season2 = os.path.join(show2, "Season 01")
    link_or_copy(FIXTURE, os.path.join(season2, "另一部剧.S01E01.mkv"))
    link_or_copy(os.path.join(POSTER_DIR, "season.jpg"), os.path.join(show2, "poster.jpg"))
    nfo = """<?xml version="1.0" encoding="UTF-8"?>
<tvshow>
  <title>另一部剧 · 本地 NFO</title>
  <year>2025</year>
  <plot>来自 tvshow.nfo 的本地简介，优先于 TMDB。</plot>
  <poster>poster.jpg</poster>
</tvshow>
"""
    with open(os.path.join(show2, "tvshow.nfo"), "w", encoding="utf-8") as handle:
        handle.write(nfo)

    print(f"library fixture ready: {ROOT}")


if __name__ == "__main__":
    main()
