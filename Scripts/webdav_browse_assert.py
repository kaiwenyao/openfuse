#!/usr/bin/env python3
"""Asserts the WebDAV browser listed one canonical deep path.

Reads the fixture server log produced by Scripts/run-webdav-browser.sh and
rejects the duplicated paths the old `pathStack.append(entry.path)` navigation
sent while a listing was still loading.
"""

from __future__ import annotations

import sys

DEEP = "/dav/Shows/Season%201/"


def main(path: str) -> int:
    log = open(path, errors="replace").read()
    errors = []
    if DEEP not in log:
        errors.append(f"browser never requested {DEEP}")
    if "/dav/Shows/Shows" in log or f"{DEEP}Shows" in log:
        errors.append("server saw a duplicated path built by the old append bug")
    if log.count(DEEP) > 4:
        errors.append(f"{DEEP} requested {log.count(DEEP)} times; the listing should be requested once")
    if errors:
        print("FAIL: " + "; ".join(errors))
        return 1
    print(f"PASS: WebDAV deep path browsed with a single canonical listing request ({DEEP})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1]))
