#!/usr/bin/env python3
"""Make OpenFuse.app self-contained: copy libmpv + non-system dylibs into
Contents/Frameworks, rewrite install names to @rpath, ad-hoc sign.

Resolves both absolute Homebrew paths and @rpath/@loader_path dependencies.
"""
from __future__ import annotations

import glob
import os
import re
import shutil
import subprocess
import sys

DEP_RE = re.compile(r"^\s+(/\S+|@\S+)\s+\(")
SYSTEM_PREFIXES = ("/System/", "/usr/lib/", "/usr/local/lib/")


def deps(path: str) -> list[str]:
    out = subprocess.check_output(["otool", "-L", path], text=True)
    result = []
    for line in out.splitlines()[1:]:
        match = DEP_RE.match(line)
        if match:
            result.append(match.group(1))
    return result


def resolve(dep: str, current: str, frameworks: str) -> str | None:
    if dep.startswith("@rpath/"):
        name = dep[len("@rpath/"):]
        candidates = [f"/opt/homebrew/lib/{name}", os.path.join(frameworks, name)]
        candidates += glob.glob(f"/opt/homebrew/opt/*/lib/{name}")
        candidates += glob.glob(f"/opt/homebrew/Cellar/*/*/lib/{name}")
        candidates.append(os.path.join(os.path.dirname(current), name))
    elif dep.startswith("@loader_path/"):
        candidates = [os.path.normpath(os.path.join(os.path.dirname(current), dep[len("@loader_path/"):]))]
    elif dep.startswith("@executable_path/"):
        executable = os.path.join(os.path.dirname(frameworks), "MacOS")
        candidates = [os.path.normpath(os.path.join(executable, dep[len("@executable_path/"):]))]
    elif dep.startswith("/"):
        candidates = [dep]
    else:
        return None
    for candidate in candidates:
        if os.path.exists(candidate):
            return os.path.realpath(candidate)
    return None


def main() -> int:
    binary, frameworks = sys.argv[1], sys.argv[2]
    os.makedirs(frameworks, exist_ok=True)
    copied: dict[str, str] = {}
    queue = [binary]
    seen: set[str] = set()

    while queue:
        current = queue.pop(0)
        if current in seen:
            continue
        seen.add(current)
        try:
            entries = deps(current)
        except subprocess.CalledProcessError:
            continue
        for dep in entries:
            if dep.startswith("/") and dep.startswith(SYSTEM_PREFIXES):
                continue
            real = resolve(dep, current, frameworks)
            if not real:
                continue
            name = os.path.basename(real)
            target = os.path.join(frameworks, name)
            if not os.path.exists(target):
                shutil.copy2(real, target)
                os.chmod(target, 0o755)
            copied[dep] = "@rpath/" + name
            copied[real] = "@rpath/" + name
            if real not in seen:
                queue.append(real)

    # Rewrite each bundled dylib and the executable.
    for file in [os.path.join(frameworks, name) for name in sorted(os.listdir(frameworks))] + [binary]:
        if not file.endswith(".dylib") and file != binary:
            continue
        if file != binary:
            subprocess.run(["install_name_tool", "-id", "@rpath/" + os.path.basename(file), file], check=True)
        for dep in deps(file):
            replacement = copied.get(dep)
            if replacement is None and dep.startswith("@rpath/"):
                base = dep[len("@rpath/"):]
                if os.path.exists(os.path.join(frameworks, base)):
                    replacement = "@rpath/" + base
            if replacement and replacement != dep:
                subprocess.run(["install_name_tool", "-change", dep, replacement, file], check=True)
        rpaths = subprocess.check_output(["otool", "-l", file], text=True)
        if "@executable_path/../Frameworks" not in rpaths:
            subprocess.run(
                ["install_name_tool", "-add_rpath", "@executable_path/../Frameworks", file],
                check=True,
            )
        subprocess.run(
            ["codesign", "--force", "--sign", "-", "--timestamp=none", file],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

    # Remove stale Homebrew rpaths from the executable.
    rpaths = subprocess.check_output(["otool", "-l", binary], text=True)
    for match in re.finditer(r"path (/opt/homebrew/\S+) \(offset", rpaths):
        try:
            subprocess.run(["install_name_tool", "-delete_rpath", match.group(1), binary], check=True)
        except subprocess.CalledProcessError:
            pass
    subprocess.run(
        ["codesign", "--force", "--sign", "-", "--timestamp=none", binary],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    print(f"bundled {len(os.listdir(frameworks))} dylibs into Frameworks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
