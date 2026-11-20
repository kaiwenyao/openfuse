#!/bin/bash
# M5z: E-AC-3 5.1 decode verified via mpv PCM output (not speaker listening).
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/audio-pcm"
rm -rf "$OUT"; mkdir -p "$OUT"
Scripts/build-app.sh >/dev/null
swift test >/dev/null
WAV="$OUT/audio.wav"
OPENFUSE_SUPPORT_DIR="$OUT/support" \
OPENFUSE_AO_PCM="$WAV" \
  "$APP" --open Fixtures/generated/openfuse-fixture.mkv --freeze-at 16 \
  --report "$OUT/play.json" --capture-after 17 --quit-after 19 \
  >"$OUT/app.log" 2>&1 || true
sleep 0.5
ffprobe -v error -show_entries stream=codec_name,channels,channel_layout,sample_rate,duration \
  -of json "$WAV" >"$OUT/probe.json"
ffmpeg -hide_banner -i "$WAV" -af "astats=metadata=1:reset=0" -f null - 2>"$OUT/astats.txt" || true
STEREO="$OUT/stereo.wav"
OPENFUSE_SUPPORT_DIR="$OUT/support-stereo" \
OPENFUSE_AO_PCM="$STEREO" OPENFUSE_AO_CHANNELS=stereo \
  "$APP" --open Fixtures/generated/openfuse-fixture.mkv --freeze-at 16 \
  --report "$OUT/stereo.json" --capture-after 17 --quit-after 19 \
  >"$OUT/stereo.log" 2>&1 || true
sleep 0.5
ffprobe -v error -show_entries stream=codec_name,channels,channel_layout,sample_rate,duration \
  -of json "$STEREO" >"$OUT/stereo-probe.json"
ffmpeg -hide_banner -i "$STEREO" -af "astats=metadata=1:reset=0" -f null - 2>"$OUT/stereo-astats.txt" || true
python3 - "$OUT" <<'PY'
import json, os, re, sys
out = sys.argv[1]
errors = []
probe = json.load(open(os.path.join(out, "probe.json")))
stream = probe.get("streams", [{}])[0]
if stream.get("channels") != 6:
    errors.append(f"channels {stream.get('channels')}")
if not str(stream.get("channel_layout", "")).startswith("5.1"):
    errors.append(f"layout {stream.get('channel_layout')}")
if stream.get("sample_rate") != "48000":
    errors.append(f"rate {stream.get('sample_rate')}")
if float(stream.get("duration", 0)) < 15:
    errors.append(f"duration {stream.get('duration')}")
levels = re.findall(r"Channel: (\d+).*?RMS level dB: ([-\d.inf]+)", open(os.path.join(out, "astats.txt")).read(), re.S)
if len(levels) < 6:
    errors.append(f"channels analyzed {len(levels)}")
for channel, level in levels[:6]:
    if level in ("-inf", "-117.9"):
        errors.append(f"channel {channel} silent: {level}")
stereo = json.load(open(os.path.join(out, "stereo-probe.json"))).get("streams", [{}])[0]
if stereo.get("channels") != 2:
    errors.append(f"stereo channels {stereo.get('channels')}")
if not str(stereo.get("channel_layout", "")).startswith("stereo"):
    errors.append(f"stereo layout {stereo.get('channel_layout')}")
stereo_levels = re.findall(r"Channel: (\d+).*?RMS level dB: ([-\d.inf]+)", open(os.path.join(out, "stereo-astats.txt")).read(), re.S)
if len(stereo_levels) < 2 or any(level in ("-inf", "-117.9") for _, level in stereo_levels[:2]):
    errors.append(f"stereo levels {stereo_levels}")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print("PASS: E-AC-3 5.1 PCM six channels + stereo downmix both non-silent")
PY
