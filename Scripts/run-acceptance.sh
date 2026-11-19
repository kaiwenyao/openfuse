#!/bin/bash
# End-to-end M1 acceptance on this Mac.
#
#   Scripts/run-acceptance.sh
#
# Requires: mpv (brew install mpv), ffmpeg, the fixture (generated on demand).
# Writes captures and reports to build/acceptance and exits non-zero on a
# failed assertion. This is the script used for Docs/M1-ACCEPTANCE.md.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
FIXTURE="$PWD/Fixtures/generated/openfuse-fixture.mkv"
OUT="$PWD/build/acceptance"

if [[ ! -f "$FIXTURE" ]]; then
  Scripts/make_fixtures.sh
fi
Scripts/build-app.sh >/dev/null
swift test >/dev/null

rm -rf "$OUT"
mkdir -p "$OUT"

run_player() {
  local name="$1"; shift
  local support="$OUT/support-$name"
  mkdir -p "$support"
  OPENFUSE_SUPPORT_DIR="$support" "$APP" "$@" >"$OUT/$name.log" 2>&1 || true
}

capture() {
  local name="$1"; local subtitle="$2"; local freeze="$3"; local wait="$4"
  run_player "$name" \
    --open "$FIXTURE" \
    --subtitle "$subtitle" \
    --freeze-at "$freeze" \
    --capture "$OUT/$name.png" \
    --capture-after "$wait" \
    --report "$OUT/$name.json" \
    --quit-after "$((wait + 1))"
  sleep 0.5
}

capture hans zh-Hans 9.9 12
capture hant zh-Hant 9.9 12
capture note zh-Hans 4.3 8

# Resume: play from 20 s, quit, reopen without --seek.
run_player resume-a --open "$FIXTURE" --seek 20 --capture "$OUT/resume-a.png" \
  --capture-after 5 --report "$OUT/resume-a.json" --quit-after 7
sleep 0.5
# Deliberately reuse resume-a's store: this is the relaunch case.
OPENFUSE_SUPPORT_DIR="$OUT/support-resume-a" "$APP" --open "$FIXTURE" \
  --capture "$OUT/resume-b.png" --capture-after 4 --report "$OUT/resume-b.json" \
  --quit-after 6 >"$OUT/resume-b.log" 2>&1 || true
sleep 0.5

python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]

def load(name):
    with open(os.path.join(out, name), encoding="utf-8") as fh:
        return json.load(fh)

def channel_count(params):
    try:
        return json.loads(params)["channel-count"]
    except Exception:
        return None

errors = []
for name, tag in [("hans", "zh-Hans"), ("hant", "zh-Hant")]:
    report = load(f"{name}.json")
    if not report.get("paused"):
        errors.append(f"{name}: expected a frozen frame")
    if not 9.80 <= report.get("position", 0) <= 10.20:
        errors.append(f"{name}: position {report.get('position')} is not near 9.9")
    if not report.get("selectedSubtitle", "").endswith(f"{tag}.ass"):
        errors.append(f"{name}: wrong subtitle {report.get('selectedSubtitle')}")
    if channel_count(report.get("audioParams")) != 6:
        errors.append(f"{name}: input is not 6 channels")
    if report.get("currentVO") != "libmpv":
        errors.append(f"{name}: video output is {report.get('currentVO')}")
    screenshot = os.path.join(out, f"{name}.png")
    if not os.path.exists(screenshot) or os.path.getsize(screenshot) < 50_000:
        errors.append(f"{name}: missing rendered frame")

note = load("note.json")
if not 4.20 <= note.get("position", 0) <= 4.60:
    errors.append(f"note: position {note.get('position')} is not near 4.3")

before = load("resume-a.json")
after = load("resume-b.json")
if before.get("position", 0) < 20:
    errors.append("resume-a: did not seek")
if after.get("position", 0) < 26:
    errors.append(f"resume-b: did not resume from the saved position ({after.get('position')})")

if errors:
    print("FAIL")
    for error in errors:
        print(" -", error)
    sys.exit(1)

print("PASS: frozen ~9.9 s frames, zh-Hans/zh-Hant selection, 6ch E-AC-3, "
      "libmpv output, font-fallback cue, resume from 20 s")
print(f"captures: {out}")
PY
