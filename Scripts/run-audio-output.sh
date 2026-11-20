#!/bin/bash
# M6e: record actual CoreAudio output and prove device routing.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/OpenFuse.app/Contents/MacOS/OpenFuse"
OUT="$PWD/build/audio-output"
rm -rf "$OUT"; mkdir -p "$OUT/support"
DEVICE=$(mpv --audio-device=help 2>/dev/null | awk -F"'" '/\(iFlyrecAudioDevice\)/ {print $2; exit}')
if [[ -z "$DEVICE" ]]; then
  DEVICE=$(mpv --audio-device=help 2>/dev/null | awk -F"'" '/\(BlackHole/ {print $2; exit}')
fi
if [[ -z "$DEVICE" ]]; then
  echo "no virtual audio output device" >&2
  exit 2
fi
rm -rf "$OUT/support"; mkdir -p "$OUT/support"
Scripts/build-app.sh >/dev/null
swift test >/dev/null
pkill -f "OpenFuse.app/Contents/MacOS/OpenFuse" 2>/dev/null || true
(/opt/homebrew/bin/ffmpeg -hide_banner -loglevel error -y -f avfoundation -i ":0" -t 14 -ac 2 -ar 48000 "$OUT/virtual.wav" >"$OUT/virtual-rec.log" 2>&1) &
RECPID=$!
sleep 1
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_AUDIO_DEVICE="$DEVICE" \
  "$APP" --open Fixtures/generated/openfuse-fixture.mkv --report "$OUT/virtual-play.json" \
  --quit-after 12 >"$OUT/virtual-play.log" 2>&1 || true
wait "$RECPID"
pkill -f "OpenFuse.app/Contents/MacOS/OpenFuse" 2>/dev/null || true
(/opt/homebrew/bin/ffmpeg -hide_banner -loglevel error -y -f avfoundation -i ":0" -t 10 -ac 2 -ar 48000 "$OUT/speaker.wav" >"$OUT/speaker-rec.log" 2>&1) &
RECPID=$!
sleep 1
OPENFUSE_SUPPORT_DIR="$OUT/support" OPENFUSE_AUDIO_DEVICE="coreaudio/BuiltInSpeakerDevice" \
  "$APP" --open Fixtures/generated/openfuse-fixture.mkv --quit-after 9 >"$OUT/speaker-play.log" 2>&1 || true
wait "$RECPID"
mean() {
  /opt/homebrew/bin/ffmpeg -hide_banner -nostats -i "$1" -af volumedetect -f null - 2>&1 \
    | sed -n 's/.*mean_volume: \([-0-9.]*\) dB.*/\1/p' | head -1
}
VIRTUAL_MEAN=$(mean "$OUT/virtual.wav")
SPEAKER_MEAN=$(mean "$OUT/speaker.wav")
/opt/homebrew/bin/ffmpeg -hide_banner -loglevel error -y -i "$OUT/virtual.wav" \
  -lavfi "showwavespic=s=1200x300:colors=red" "$OUT/wave.png"
VIRTUAL_MEAN="$VIRTUAL_MEAN" SPEAKER_MEAN="$SPEAKER_MEAN" python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
virtual = float(os.environ["VIRTUAL_MEAN"])
speaker = float(os.environ["SPEAKER_MEAN"])
errors = []
play = json.load(open(os.path.join(out, "virtual-play.json")))
tracks = play.get("audio", [])
if not tracks or tracks[0].get("channels") != 6 or tracks[0].get("codec") != "eac3":
    errors.append(f"source audio {tracks}")
if virtual < -40:
    errors.append(f"virtual mean {virtual} dB too quiet")
if speaker > -80:
    errors.append(f"speaker-control mean {speaker} dB not silent")
if not os.path.exists(os.path.join(out, "wave.png")):
    errors.append("waveform missing")
if errors:
    print("FAIL")
    for error in errors: print(" -", error)
    sys.exit(1)
print(f"PASS: actual output {virtual:.1f} dB, speaker control {speaker:.1f} dB")
PY
