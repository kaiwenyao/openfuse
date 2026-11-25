#!/bin/bash
# A/B timing for the macOS "Cmd+Tab away from a playing video stutters" bug.
#
#   Scripts/run-cmdtab-timing.sh
#
# Builds build/OpenFuse.app, then plays the local fixture with the three
# render-timing variants while real Cmd+Tab switches run:
#
#   A  OPENFUSE_VIDEO_TIMING_OFFSET=0.05        (pre-fix: mpv's default)
#   B  OPENFUSE_VIDEO_TIMING_OFFSET=0           (candidate fix)
#   C  OPENFUSE_VIDEO_TIMING_OFFSET=0.05
#      OPENFUSE_BLOCK_FOR_TARGET_TIME=0         (diagnostic alternative)
#
# The play and pause groups are separate processes, as in the investigation.
# Render-timing windows (OPENFUSE_RENDER_TIMING_INTERVAL=2) and a main-thread
# `sample` during the switch loop measure the same frames; the report JSON
# carries avsync, dropped-frame counters and the per-stage percentiles.
#
# It writes build/cmdtab-timing/summary.tsv and summary.md. Screen animation
# frames are not recorded: reading presented frames needs a ScreenCaptureKit
# capture path that this script does not have, so the switch animation stays a
# manual acceptance item.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
FIXTURE="$PWD/Fixtures/generated/openfuse-fixture.mkv"
OUT="$PWD/build/cmdtab-timing"
ROUNDS="${ROUNDS:-2}"
SWITCHES="${SWITCHES:-12}"
QUIT_AFTER="${QUIT_AFTER:-18}"
SUMMARY="$OUT/summary.tsv"

if [[ ! -f "$FIXTURE" ]]; then
  echo "error: missing fixture $FIXTURE (run Scripts/make_fixtures.sh)" >&2
  exit 1
fi

mkdir -p "$OUT"
: >"$SUMMARY"
Scripts/build-app.sh >/dev/null
# Focus helper: NSRunningApplication activation does not need the Accessibility
# grant and cannot launch a second /Applications/OpenFuse.app instance.
swiftc -O Tools/window_focus.swift -o "$OUT/focus" 2>/dev/null || {
  echo "error: failed to build Tools/window_focus.swift" >&2
  exit 1
}

frontmost_pid() {
  "$OUT/focus" frontmost 2>/dev/null || echo -1
}

activate_app() {
  local pid="$1"
  # The first activation right after launch can race WindowServer registering
  # the new process, so retry briefly before reporting a miss.
  for _ in $(seq 1 3); do
    if "$OUT/focus" activate "$pid" >/dev/null 2>&1 && [[ "$(frontmost_pid)" == "$pid" ]]; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

cmd_tab_out() {
  local pid="$1"
  # Real user gesture; the Finder activation fallback is the repeatable
  # system-activated switch the investigation used as a control.
  osascript -e 'tell application "System Events" to key code 48 using command down' >/dev/null 2>&1 || true
  sleep 0.5
  if [[ "$(frontmost_pid)" == "$pid" ]]; then
    osascript -e 'tell application "Finder" to activate' >/dev/null 2>&1 || true
    sleep 0.4
  fi
}

measure_switch() {
  local pid="$1"
  local switched=0
  activate_app "$pid" || true
  sample "$pid" 8 2 -file "$2" >/dev/null 2>&1 &
  local sampler=$!
  for _ in $(seq 1 "$SWITCHES"); do
    if [[ "$(frontmost_pid)" == "$pid" ]]; then
      cmd_tab_out "$pid"
      if [[ "$(frontmost_pid)" != "$pid" ]]; then switched=$((switched + 1)); fi
    fi
    # NSRunningApplication activation does not switch to a fullscreen app's
    # Space, so fall back to the reverse Cmd+Tab the user would press. The app
    # was the most recent one, so a single press returns to it.
    if ! activate_app "$pid" >/dev/null 2>&1; then
      osascript -e 'tell application "System Events" to key code 48 using command down' >/dev/null 2>&1 || true
      sleep 0.6
    fi
    sleep 0.2
  done
  wait "$sampler" 2>/dev/null || true
  printf '%d\n' "$switched" >"$3"
}

run_once() {
  local variant="$1" offset="$2" block="$3" mode="$4" index="$5"
  local suffix=""
  local args=()
  local capture_after=3
  local quit_after="$QUIT_AFTER"
  if [[ "$mode" == "pause" ]]; then args+=(--freeze-at 0.5); fi
  if [[ "${FULLSCREEN:-0}" == "1" ]]; then
    args+=(--fullscreen)
    suffix="-fs"
    capture_after=5
    quit_after=$((QUIT_AFTER + 6))
  fi
  local dir="$OUT/$variant-$mode$suffix-$index"
  rm -rf "$dir"
  mkdir -p "$dir"

  local env_args=(
    OPENFUSE_SUPPORT_DIR="$dir/support"
    OPENFUSE_CREDENTIAL_MODE=session
    OPENFUSE_DEBUG_TIMING=1
    OPENFUSE_RENDER_TIMING=1
    OPENFUSE_RENDER_TIMING_INTERVAL=2
    OPENFUSE_AO_PCM="$dir/fixture.wav"
    OPENFUSE_VIDEO_TIMING_OFFSET="$offset"
  )
  if [[ "$block" == "0" ]]; then env_args+=(OPENFUSE_BLOCK_FOR_TARGET_TIME=0); fi
  mkdir -p "$dir/support"

  env "${env_args[@]}" "$APP" --open "$FIXTURE" ${args[@]+"${args[@]}"} \
    --capture "$dir/frame.png" \
    --report "$dir/report.json" --capture-after "$capture_after" --quit-after "$quit_after" \
    >"$dir/stdout.log" 2>"$dir/timing.log" &
  local pid=$!
  sleep 1
  activate_app "$pid" || true

  for _ in $(seq 1 40); do
    if [[ -s "$dir/report.json" ]]; then break; fi
    sleep 0.25
  done
  if [[ -s "$dir/report.json" ]]; then
    measure_switch "$pid" "$dir/sample.txt" "$dir/switches.txt"
  else
    echo "FAIL $variant $mode #$index: no report" | tee -a "$SUMMARY"
  fi
  wait "$pid" || true
}

for variant in ${VARIANTS:-A B C}; do
  case "$variant" in
    A) offset="0.05"; block="1" ;;
    B) offset="0"; block="1" ;;
    C) offset="0.05"; block="0" ;;
  esac
  for mode in play pause; do
    for index in $(seq 1 "$ROUNDS"); do
      run_once "$variant" "$offset" "$block" "$mode" "$index"
    done
  done
done

python3 - "$OUT" <<'PY'
import json
import os
import re
import statistics
import sys

out = sys.argv[1]
rows = []
window_re = re.compile(r"\[timing\] render-window ([0-9.]+)s (.*)")
stage_re = re.compile(r"(\w+) n=(\d+) p50=(-?[0-9.]+) p95=(-?[0-9.]+) p99=(-?[0-9.]+) max=(-?[0-9.]+)(?: (?:overBudget|over)=(\d+))?")

for name in sorted(os.listdir(out)):
    directory = os.path.join(out, name)
    report_path = os.path.join(directory, "report.json")
    if not os.path.isdir(directory) or not os.path.exists(report_path):
        continue
    with open(report_path) as handle:
        report = json.load(handle)
    timing_path = os.path.join(directory, "timing.log")
    windows = []
    final = {}
    if os.path.exists(timing_path):
        with open(timing_path, errors="replace") as handle:
            for line in handle:
                match = window_re.search(line)
                if match:
                    windows.append(dict((m.group(1), m.groups()[1:]) for m in stage_re.finditer(match.group(2))))
                if "render-final" in line:
                    final = dict((m.group(1), m.groups()[1:]) for m in stage_re.finditer(line))
    sample_path = os.path.join(directory, "sample.txt")
    sample_counts = {"draw": 0, "mpv": 0, "wait": 0, "flush": 0, "lines": 0}
    if os.path.exists(sample_path):
        with open(sample_path, errors="replace") as handle:
            text = handle.read()
        sample_counts = {
            "draw": text.count("MPVGLView.draw"),
            "mpv": text.count("mpv_render_context_render"),
            "wait": len(re.findall(r"__psynch_cvwait|_pthread_cond_wait", text)),
            "flush": text.count("CGLFlushDrawable") + text.count("flushBuffer"),
            "lines": len(text.splitlines()),
        }
    stalls = []
    if os.path.exists(timing_path):
        with open(timing_path, errors="replace") as handle:
            stalls = [int(m.group(1)) for m in re.finditer(r"MAIN-STALL (\d+)ms", handle.read())]
    stages = (report.get("renderTiming") or {}).get("stages") or {}

    def window_p50(stage, key):
        values = []
        for window in windows:
            if stage in window:
                values.append(float(window[stage][{ "p50": 1, "p95": 2, "p99": 3, "max": 4 }.get(key, 1)]))
        return statistics.median(values) if values else 0.0

    rows.append({
        "run": name,
        "variant": name.split("-")[0],
        "mode": name.split("-")[1],
        "offset": report.get("videoTimingOffset"),
        "block": report.get("blockForTargetTime"),
        "paused": report.get("paused"),
        "position": round(float(report.get("position") or 0), 2),
        "hasRenderContext": report.get("hasRenderContext"),
        "avsync": report.get("avsync"),
        "videoSync": report.get("videoSync"),
        "frameDrop": report.get("frameDropCount"),
        "mistimed": report.get("mistimedFrameCount"),
        "delayed": report.get("voDelayedFrameCount"),
        "drawSamples": ((stages.get("draw") or {}).get("count")),
        "drawP95Window": round(window_p50("draw", "p95"), 2),
        "drawP99Window": round(window_p50("draw", "p99"), 2),
        "renderP95Window": round(window_p50("render", "p95"), 2),
        "renderMaxWindow": round(window_p50("render", "max"), 2),
        "swapP95Window": round(window_p50("swap", "p95"), 2),
        "targetLeadP50Window": round(window_p50("targetLead", "p50"), 2),
        "renderOverBudget": (stages.get("render") or {}).get("overBudget"),
        "drawOverBudget": (stages.get("draw") or {}).get("overBudget"),
        "windows": len(windows),
        "realSwitches": open(os.path.join(directory, "switches.txt")).read().strip() if os.path.exists(os.path.join(directory, "switches.txt")) else "-",
        "sampleDraw": sample_counts["draw"],
        "sampleMpv": sample_counts["mpv"],
        "sampleWait": sample_counts["wait"],
        "sampleFlush": sample_counts["flush"],
        "finalDrawP95": round(float(final.get("draw", [0, 0, 0, 0, 0])[2]), 2) if "draw" in final else 0.0,
        "finalRenderP95": round(float(final.get("render", [0, 0, 0, 0, 0])[2]), 2) if "render" in final else 0.0,
        "finalRenderMax": round(float(final.get("render", [0, 0, 0, 0, 0])[4]), 2) if "render" in final else 0.0,
        "finalDrawMax": round(float(final.get("draw", [0, 0, 0, 0, 0])[4]), 2) if "draw" in final else 0.0,
        "finalSwapP95": round(float(final.get("swap", [0, 0, 0, 0, 0])[2]), 2) if "swap" in final else 0.0,
        "finalDrawOver": int(final.get("draw", [0, 0, 0, 0, 0])[5]) if "draw" in final else 0,
        "finalRenderOver": int(final.get("render", [0, 0, 0, 0, 0])[5]) if "render" in final else 0,
        "mainStalls": len(stalls),
        "maxStall": max(stalls) if stalls else 0,
    })

if not rows:
    print("no runs collected", file=sys.stderr)
    sys.exit(1)

fields = list(rows[0].keys())
with open(os.path.join(out, "summary.tsv"), "w") as handle:
    handle.write("\t".join(fields) + "\n")
    for row in rows:
        handle.write("\t".join(str(row[f]) for f in fields) + "\n")

columns = ["run", "offset", "block", "avsync", "drawSamples", "drawP95Window", "renderP95Window",
           "renderMaxWindow", "swapP95Window", "targetLeadP50Window", "renderOverBudget",
           "frameDrop", "mistimed", "delayed", "finalDrawP95", "finalRenderP95", "finalRenderMax",
           "finalSwapP95", "finalDrawOver", "finalRenderOver", "realSwitches", "mainStalls", "maxStall"]
with open(os.path.join(out, "summary.md"), "w") as handle:
    handle.write("| " + " | ".join(columns) + " |\n")
    handle.write("|" + "|".join(["---"] * len(columns)) + "|\n")
    for row in rows:
        handle.write("| " + " | ".join(str(row[c]) for c in columns) + " |\n")

print(open(os.path.join(out, "summary.md")).read())
PY

echo "runs: $OUT"
