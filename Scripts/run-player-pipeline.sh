#!/bin/bash
# Playback pipeline acceptance: frame pacing, dropped frames and the
# control-bar fade-out over a 60 s MKV soak.
#
#   Scripts/run-player-pipeline.sh
#
# Notes
#  - The presentation surface is the proven NSOpenGLView from 0.4.x. The 0.5.0
#    Core Animation backend rendered every vsync (p50 ~8.4 ms) but broke
#    plain-text subtitle rendering and Core Animation's colour management tinted
#    the picture on XDR displays, so it was rolled back in 0.5.2.
#  - `[gl] draw <nanos>` lines (OPENFUSE_DEBUG_GL=1) give the frame cadence.
#  - `[timeline] <nanos> controls hidden` marks the control-bar fade; the UI
#    clock keeps that transition from stalling the video (it was ~100 ms in
#    0.4.0).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
FIXTURE="$PWD/Fixtures/generated/openfuse-fixture.mkv"
OUT="$PWD/build/player-pipeline"
DURATION=60

if [[ ! -f "$FIXTURE" ]]; then
  Scripts/make_fixtures.sh
fi
Scripts/build-app.sh >/dev/null
swift test >/dev/null

rm -rf "$OUT"
mkdir -p "$OUT/support" "$OUT/capture-support"

# 1) Soak without screenshots: a PNG readback costs ~100 ms and would pollute
#    the pacing measurement.
OPENFUSE_SUPPORT_DIR="$OUT/support" \
OPENFUSE_DEBUG_GL=1 \
OPENFUSE_DEBUG_TIMELINE=1 \
  "$APP" --open "$FIXTURE" \
  --report "$OUT/report.json" \
  --capture-after $((DURATION - 5)) \
  --quit-after "$DURATION" >"$OUT/app.log" 2>"$OUT/draw.log" || true

# 2) Evidence runs: the rendered frame and the control bar.
OPENFUSE_SUPPORT_DIR="$OUT/capture-support" OPENFUSE_FORCE_CONTROLS=1 \
  "$APP" --open "$FIXTURE" --capture "$OUT/frame.png" --capture-after 6 \
  --capture-ui "$OUT/player-ui.png" --ui-after 7 --quit-after 9 \
  >"$OUT/capture.log" 2>&1 || true

python3 - "$OUT" "$DURATION" <<'PY'
import json
import os
import re
import statistics
import sys

out = sys.argv[1]
duration = float(sys.argv[2])
errors = []

draws = []
hidden_at = None
for line in open(os.path.join(out, "draw.log"), errors="replace"):
    match = re.search(r"\[gl\] draw (\d+)", line)
    if match:
        draws.append(int(match.group(1)))
        continue
    match = re.search(r"\[timeline\] (\d+) controls hidden", line)
    if match:
        hidden_at = int(match.group(1))

if len(draws) < 800:
    errors.append(f"only {len(draws)} rendered frames captured")

start = draws[0]
times = [(t - start) / 1e9 for t in draws]
times = [t for t in times if t > 5.0]
gaps = [(b - a) * 1000 for a, b in zip(times, times[1:])]
gaps_sorted = sorted(gaps)
p50 = statistics.median(gaps)
p99 = gaps_sorted[int(len(gaps_sorted) * 0.99)]
worst = gaps_sorted[-1]
print(f"frame cadence: n={len(times)} span={times[-1]:.1f}s p50={p50:.1f}ms p99={p99:.1f}ms max={worst:.1f}ms")
if not 40.5 <= p50 <= 43.5:
    errors.append(f"median frame interval {p50:.1f} ms (expected ~41.7 ms for 24 fps)")
if p99 > 56:
    errors.append(f"p99 frame interval {p99:.1f} ms > 56 ms")
if worst > 80:
    errors.append(f"worst frame interval {worst:.1f} ms > 80 ms")

if hidden_at is None:
    errors.append("control bar never hid; the fade-out regression check did not run")
elif draws:
    before = [t for t in draws if t <= hidden_at]
    after = [t for t in draws if t > hidden_at]
    if before and after:
        fade_gap = (after[0] - before[-1]) / 1e6
        print(f"control-bar fade gap: {fade_gap:.1f} ms (was ~100 ms in 0.4.0)")
        if fade_gap > 70:
            errors.append(f"control-bar fade stalled the video for {fade_gap:.1f} ms")

report_path = os.path.join(out, "report.json")
if not os.path.exists(report_path):
    errors.append("playback report missing")
else:
    report = json.load(open(report_path))
    print("report:", {key: report.get(key) for key in (
        "position", "duration", "frameDropCount", "mistimedFrameCount",
        "decoderDropFrameCount", "estimatedVFFps", "displayFps", "videoSync",
        "hasRenderContext")})
    if report.get("hasRenderContext") is not True:
        errors.append("no mpv render context")
    if (report.get("frameDropCount") or 0) > 8:
        errors.append(f"frameDropCount={report.get('frameDropCount')}")
    if (report.get("decoderDropFrameCount") or 0) != 0:
        errors.append(f"decoderDropFrameCount={report.get('decoderDropFrameCount')}")
    fps = report.get("estimatedVFFps") or 0
    if abs(fps - 24.0) > 0.5:
        errors.append(f"estimated-vf-fps={fps} (expected ~24)")
    if (report.get("displayFps") or 0) < 30:
        errors.append(f"display-fps={report.get('displayFps')}; CVDisplayLink override not applied")
    if (report.get("position") or 0) < duration - 10:
        errors.append(f"playback only reached {report.get('position')} s")
    if report.get("videoSync") != "audio":
        errors.append(f"video-sync={report.get('videoSync')} (expected audio)")

for artifact in ("frame.png", "player-ui.png"):
    path = os.path.join(out, artifact)
    if not os.path.exists(path) or os.path.getsize(path) < 20_000:
        errors.append(f"missing evidence capture {artifact}")

if errors:
    print("FAIL: " + "; ".join(errors))
    sys.exit(1)
print("PASS: 60 s soak, no decoder drops, control-bar fade below 70 ms")
PY
