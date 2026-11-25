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
# `sample` overlap the switch loop. Reports before and after the loop carry
# playback position, avsync, dropped-frame counters and render percentiles.
#
# Each invocation writes summary.tsv and summary.md to its own run directory
# under build/cmdtab-timing. Screen animation
# frames are not recorded: reading presented frames needs a ScreenCaptureKit
# capture path that this script does not have, so the switch animation stays a
# manual acceptance item.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
FIXTURE="$PWD/Fixtures/generated/openfuse-fixture.mkv"
ROUNDS="${ROUNDS:-2}"
SWITCHES="${SWITCHES:-12}"
FULLSCREEN="${FULLSCREEN:-0}"
if [[ ! "$ROUNDS" =~ ^[1-9][0-9]*$ || ! "$SWITCHES" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: ROUNDS and SWITCHES must be positive integers" >&2
  exit 1
fi
QUIT_AFTER="${QUIT_AFTER:-$((10 + 3 * SWITCHES))}"
if [[ ! "$QUIT_AFTER" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: QUIT_AFTER must be a positive integer" >&2
  exit 1
fi

if [[ ! -f "$FIXTURE" ]]; then
  echo "error: missing fixture $FIXTURE (run Scripts/make_fixtures.sh)" >&2
  exit 1
fi

mkdir -p "$PWD/build/cmdtab-timing"
OUT="$(mktemp -d "$PWD/build/cmdtab-timing/run.XXXXXXXX")"
echo "runs: $OUT"
expected_runs=()
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

send_cmd_tab() {
  osascript -e 'tell application "System Events" to key code 48 using command down' >/dev/null
}

switched_away() {
  local front
  front="$(frontmost_pid)"
  [[ "$front" -gt 0 && "$front" != "$1" ]]
}

cmd_tab_out() {
  local pid="$1"
  if send_cmd_tab; then
    sleep 0.5
    if switched_away "$pid"; then
      echo cmdTab
      return
    fi
  fi
  if [[ "$(frontmost_pid)" == "$pid" ]] && osascript -e 'tell application "Finder" to activate' >/dev/null; then
    sleep 0.4
    if switched_away "$pid"; then
      echo finder
      return
    fi
  fi
  echo failed
}

measure_switch() {
  local pid="$1" dir="$2"
  local cmd_tab=0 finder=0 failed=0 missed_return=0 sample_failed=0 early_report=0
  activate_app "$pid" || true
  sample "$pid" 8 2 -file "$dir/sample.txt" >"$dir/sample.log" 2>&1 &
  local sampler=$!
  for _ in $(seq 1 "$SWITCHES"); do
    if [[ "$(frontmost_pid)" != "$pid" ]]; then
      failed=$((failed + 1))
    else
      case "$(cmd_tab_out "$pid" 2>>"$dir/switches.log")" in
        cmdTab) cmd_tab=$((cmd_tab + 1)) ;;
        finder) finder=$((finder + 1)) ;;
        *) failed=$((failed + 1)) ;;
      esac
    fi
    # NSRunningApplication activation does not switch to a fullscreen app's
    # Space in some cases. Try switching back and verify the resulting PID.
    if [[ "$(frontmost_pid)" != "$pid" ]] && ! activate_app "$pid"; then
      send_cmd_tab 2>>"$dir/switches.log" || true
      sleep 0.6
    fi
    if [[ "$(frontmost_pid)" != "$pid" ]]; then
      missed_return=$((missed_return + 1))
    fi
    sleep 0.2
  done
  if [[ -e "$dir/report-after.json" ]]; then early_report=1; fi
  if ! wait "$sampler"; then sample_failed=1; fi
  printf '%d\t%d\t%d\t%d\t%d\t%d\n' "$cmd_tab" "$finder" "$failed" "$missed_return" "$sample_failed" "$early_report" >"$dir/switches.tsv"
}

run_once() {
  local variant="$1" offset="$2" block="$3" mode="$4" index="$5"
  local suffix=""
  local args=()
  local capture_after=3
  local quit_after="$QUIT_AFTER"
  if [[ "$mode" == "pause" ]]; then args+=(--freeze-at 0.5); fi
  if [[ "$FULLSCREEN" == "1" ]]; then
    args+=(--fullscreen)
    suffix="-fs"
    capture_after=5
    quit_after=$((QUIT_AFTER + 6))
  fi
  local name="$variant-$mode$suffix-$index"
  local dir="$OUT/$name"
  expected_runs+=("$name")
  mkdir -p "$dir/support"

  local env_args=(
    OPENFUSE_SUPPORT_DIR="$dir/support"
    OPENFUSE_CREDENTIAL_MODE=session
    OPENFUSE_DEBUG_TIMING=1
    OPENFUSE_RENDER_TIMING=1
    OPENFUSE_RENDER_TIMING_INTERVAL=2
    OPENFUSE_AO_PCM="$dir/fixture.wav"
    OPENFUSE_VIDEO_SYNC=audio
    OPENFUSE_VIDEO_TIMING_OFFSET="$offset"
    OPENFUSE_BLOCK_FOR_TARGET_TIME="$block"
  )

  env "${env_args[@]}" "$APP" --open "$FIXTURE" ${args[@]+"${args[@]}"} \
    --capture "$dir/frame.png" \
    --report "$dir/report-before.json" --capture-after "$capture_after" \
    --report-on-quit "$dir/report-after.json" --quit-after "$quit_after" \
    >"$dir/stdout.log" 2>"$dir/timing.log" &
  local pid=$!
  sleep 1
  activate_app "$pid" || true

  for _ in $(seq 1 40); do
    if [[ -s "$dir/report-before.json" ]] || ! kill -0 "$pid" 2>/dev/null; then break; fi
    sleep 0.25
  done
  if [[ -s "$dir/report-before.json" ]]; then
    measure_switch "$pid" "$dir"
  else
    echo "FAIL $name: missing pre-switch report" >&2
  fi
  if kill -0 "$pid" 2>/dev/null; then
    "$OUT/focus" terminate "$pid" || true
  fi
  if ! wait "$pid"; then
    echo "OpenFuse exited unsuccessfully" >"$dir/process-error.txt"
  fi
}

for variant in ${VARIANTS:-A B C}; do
  case "$variant" in
    A) offset="0.05"; block="1" ;;
    B) offset="0"; block="1" ;;
    C) offset="0.05"; block="0" ;;
    *) echo "error: unknown variant $variant" >&2; exit 1 ;;
  esac
  for mode in play pause; do
    for index in $(seq 1 "$ROUNDS"); do
      run_once "$variant" "$offset" "$block" "$mode" "$index"
    done
  done
done

python3 - "$OUT" "$SWITCHES" "$FULLSCREEN" "${expected_runs[@]}" <<'PY'
import json
import math
import os
import re
import statistics
import sys

out, requested_switches, fullscreen, *expected_runs = sys.argv[1:]
requested_switches = int(requested_switches)
rows = []
failures = []
window_re = re.compile(r"\[timing\] render-window ([0-9.]+)s (.*)")
stage_re = re.compile(r"(\w+) n=(\d+) p50=(-?[0-9.]+) p95=(-?[0-9.]+) p99=(-?[0-9.]+) max=(-?[0-9.]+)(?: (?:overBudget|over)=(\d+))?")

for name in expected_runs:
    directory = os.path.join(out, name)
    required_files = ("report-before.json", "report-after.json", "switches.tsv", "sample.txt", "timing.log")
    missing = [file for file in required_files if not os.path.isfile(os.path.join(directory, file))
               or os.path.getsize(os.path.join(directory, file)) == 0]
    if missing:
        failures.append(f"{name}: missing or empty {', '.join(missing)}")
        continue
    if os.path.exists(os.path.join(directory, "process-error.txt")):
        failures.append(f"{name}: OpenFuse exited unsuccessfully")
    with open(os.path.join(directory, "switches.tsv")) as handle:
        cmd_tab, finder, failed, missed_return, sample_failed, early_report = map(int, handle.read().split())
    if cmd_tab != requested_switches or finder or failed or missed_return:
        failures.append(f"{name}: Cmd+Tab {cmd_tab}/{requested_switches}, Finder {finder}, "
                        f"failed {failed}, missed returns {missed_return}")
    if sample_failed:
        failures.append(f"{name}: sample failed (see sample.log)")
    if early_report:
        failures.append(f"{name}: post-switch report was written before the switch loop ended")

    with open(os.path.join(directory, "report-before.json")) as handle:
        before = json.load(handle)
    with open(os.path.join(directory, "report-after.json")) as handle:
        after = json.load(handle)
    variant, mode, *_ = name.split("-")
    expected_offset, expected_block = {"A": ("0.05", True), "B": ("0", True), "C": ("0.05", False)}[variant]
    for phase, report in (("before", before), ("after", after)):
        if report.get("paused") is not (mode == "pause") or report.get("hasRenderContext") is not True:
            failures.append(f"{name}: unexpected playback state in {phase} report")
        if report.get("videoSync") != "audio" or report.get("videoTimingOffset") != expected_offset or report.get("blockForTargetTime") is not expected_block:
            failures.append(f"{name}: unexpected timing options in {phase} report")
        if not isinstance(report.get("frameDropCount"), int):
            failures.append(f"{name}: missing dropped-frame count in {phase} report")
        if mode == "play" and not math.isfinite(float(report.get("avsync", "nan"))):
            failures.append(f"{name}: missing A/V sync in {phase} report")
    if before.get("isFullScreen") is not (fullscreen == "1"):
        failures.append(f"{name}: unexpected fullscreen state before switching")
    position_before = before["position"]
    position_after = after["position"]
    position_delta = position_after - position_before
    if (mode == "play" and position_delta <= 0) or (mode == "pause" and abs(position_delta) > 0.01):
        failures.append(f"{name}: unexpected playback position change ({position_delta:.3f}s)")
    drop_before = before.get("frameDropCount")
    drop_after = after.get("frameDropCount")
    drop_delta = drop_after - drop_before if isinstance(drop_before, int) and isinstance(drop_after, int) else None

    timing_path = os.path.join(directory, "timing.log")
    windows = []
    final = {}
    stalls = []
    with open(timing_path, errors="replace") as handle:
        for line in handle:
            match = window_re.search(line)
            if match:
                windows.append(dict((m.group(1), m.groups()[1:]) for m in stage_re.finditer(match.group(2))))
            if "render-final" in line:
                final = dict((m.group(1), m.groups()[1:]) for m in stage_re.finditer(line))
            stall = re.search(r"MAIN-STALL (\d+)ms", line)
            if stall:
                stalls.append(int(stall[1]))
    if "draw" not in final or "render" not in final:
        failures.append(f"{name}: missing final render timing")
    sample_path = os.path.join(directory, "sample.txt")
    # Keep the stacks for manual inspection. Symbol hits in the full report
    # include other threads and are not main-thread sample counts.
    with open(sample_path, errors="replace") as handle:
        if "Call graph:" not in handle.read():
            failures.append(f"{name}: sample.txt has no call graph")
    stages = (after.get("renderTiming") or {}).get("stages") or {}

    def window_p50(stage, key):
        values = []
        for window in windows:
            if stage in window:
                values.append(float(window[stage][{ "p50": 1, "p95": 2, "p99": 3, "max": 4 }.get(key, 1)]))
        return statistics.median(values) if values else 0.0

    rows.append({
        "run": name,
        "variant": variant,
        "mode": mode,
        "offset": after.get("videoTimingOffset"),
        "block": after.get("blockForTargetTime"),
        "paused": after.get("paused"),
        "positionBefore": round(position_before, 3),
        "positionAfter": round(position_after, 3),
        "positionDelta": round(position_delta, 3),
        "avsyncBefore": before.get("avsync"),
        "avsyncAfter": after.get("avsync"),
        "videoSync": after.get("videoSync"),
        "frameDropBefore": drop_before,
        "frameDropAfter": drop_after,
        "frameDropDelta": drop_delta,
        "mistimed": after.get("mistimedFrameCount"),
        "delayed": after.get("voDelayedFrameCount"),
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
        "cmdTabSwitches": cmd_tab,
        "finderFallbacks": finder,
        "failedSwitches": failed,
        "missedReturns": missed_return,
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
    for failure in failures:
        print(f"FAIL {failure}", file=sys.stderr)
    sys.exit("no complete runs collected")

fields = list(rows[0].keys())
with open(os.path.join(out, "summary.tsv"), "w") as handle:
    handle.write("\t".join(fields) + "\n")
    for row in rows:
        handle.write("\t".join(str(row[f]) for f in fields) + "\n")

columns = ["run", "offset", "block", "positionBefore", "positionAfter", "avsyncBefore", "avsyncAfter",
           "frameDropBefore", "frameDropAfter", "frameDropDelta", "cmdTabSwitches", "finderFallbacks",
           "failedSwitches", "missedReturns", "finalDrawP95", "finalRenderP95", "finalSwapP95", "maxStall"]
with open(os.path.join(out, "summary.md"), "w") as handle:
    handle.write("| " + " | ".join(columns) + " |\n")
    handle.write("|" + "|".join(["---"] * len(columns)) + "|\n")
    for row in rows:
        handle.write("| " + " | ".join(str(row[c]) for c in columns) + " |\n")

print(open(os.path.join(out, "summary.md")).read())
for failure in failures:
    print(f"FAIL {failure}", file=sys.stderr)
if failures:
    sys.exit(1)
PY

echo "runs: $OUT"
