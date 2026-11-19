#!/bin/bash
# Build the deterministic OpenFuse playback fixture.
#
#   Fixtures/generated/openfuse-fixture.mkv
#     video: HEVC Main 10, 1920x1080, 24.000 fps, 60 s, BT.709
#     audio: E-AC-3 5.1 448 kb/s, discrete channel announcements
#     subs : embedded ASS (chi) + external zh-Hans / zh-Hant / untagged ASS
#
# Everything is generated from source in this repository. No commercial media,
# no third-party fonts. Usage:
#
#   Scripts/make_fixtures.sh            # full 60 s fixture
#   Scripts/make_fixtures.sh --quick    # 8 s smoke fixture
set -euo pipefail

cd "$(dirname "$0")/.."

QUICK=0
if [[ "${1:-}" == "--quick" ]]; then QUICK=1; fi
SECONDS_LEN=60
if [[ $QUICK -eq 1 ]]; then SECONDS_LEN=8; fi

OUT="Fixtures/generated"
BUILD="build"
mkdir -p "$OUT" "$BUILD"

FONT_URL="https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/SubsetOTF/SC/NotoSansSC-Regular.otf"
FONT_LICENSE_URL="https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/LICENSE"
if [[ ! -f "$OUT/NotoSansSC-Regular.otf" ]]; then
  echo "==> fetching OFL test font"
  curl -fsSL "$FONT_URL" -o "$OUT/NotoSansSC-Regular.otf"
  curl -fsSL "$FONT_LICENSE_URL" -o "$OUT/NotoSansSC-LICENSE.txt" || true
fi

echo "==> toolchain"
swiftc -O Tools/gen_frames.swift -o "$BUILD/gen_frames"
ffmpeg -hide_banner -version | head -1 > "$OUT/ffmpeg-version.txt"
sw_vers >> "$OUT/ffmpeg-version.txt"

echo "==> subtitles"
python3 Tools/gen_subtitles.py

echo "==> video ($SECONDS_LEN s HEVC Main 10)"
"$BUILD/gen_frames" "$SECONDS_LEN" 24 1920 1080 2>"$OUT/gen_frames.log" \
  | ffmpeg -hide_banner -loglevel warning -y \
      -f rawvideo -pix_fmt bgra -s 1920x1080 -r 24 -i - \
      -c:v libx265 -pix_fmt yuv420p10le -preset medium -crf 20 -profile:v main10 \
      -x265-params "log-level=error:keyint=48:min-keyint=24:scenecut=0:repeat-headers=1" \
      -color_primaries bt709 -color_trc bt709 -colorspace bt709 \
      -metadata title="OpenFuse playback fixture" \
      "$OUT/video.mkv"

echo "==> audio (6-channel callouts)"
python3 Tools/gen_audio.py --seconds "$SECONDS_LEN" --out "$OUT/audio.wav"

ffmpeg -hide_banner -loglevel warning -y -i "$OUT/audio.wav" \
  -af "channelmap=channel_layout=5.1" \
  -c:a eac3 -b:a 448k \
  "$OUT/audio.eac3"

echo "==> mux"
FONT_ATTACH=()
if [[ -f "$OUT/NotoSansSC-Regular.otf" ]]; then
  FONT_ATTACH=(-attach "$OUT/NotoSansSC-Regular.otf"
               -metadata:s:t:0 mimetype=font/otf
               -metadata:s:t:0 filename=OpenFuseSansSC.otf)
fi

ffmpeg -hide_banner -loglevel warning -y \
  -i "$OUT/video.mkv" -i "$OUT/audio.eac3" -i "$OUT/openfuse-fixture.zh-Hans.ass" \
  -map 0:v:0 -map 1:a:0 -map 2:s:0 \
  -c:v copy -c:a copy -c:s ass \
  -metadata:s:a:0 language=chi \
  -metadata:s:a:0 title="E-AC-3 5.1 测试音轨" \
  -disposition:a:0 default \
  -metadata:s:s:0 language=chi \
  -metadata:s:s:0 title="中文（简体） · 中日双语" \
  -disposition:s:0 0 \
  "${FONT_ATTACH[@]}" \
  "$OUT/openfuse-fixture.mkv"

echo "==> probe"
{
  echo "# OpenFuse fixture probe"
  echo "# generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ffprobe -hide_banner -v error -show_streams -show_format -of json "$OUT/openfuse-fixture.mkv"
} > "$OUT/probe.json"
ffprobe -hide_banner -v error -show_entries \
  stream=index,codec_name,profile,width,height,r_frame_rate,channels,channel_layout,bit_rate:stream_tags=language,title \
  -of default=noprint_wrappers=0 "$OUT/openfuse-fixture.mkv"

echo "==> channel map validation"
python3 Tools/analyze_audio.py "$OUT/openfuse-fixture.mkv" \
  --out "$OUT/audio-channel-map.json" > "$OUT/audio-channel-map.log" || {
    echo "error: channel map validation failed, see $OUT/audio-channel-map.log" >&2
    exit 1
  }
python3 - "$OUT" <<'PY'
import json, os, subprocess, sys
out = sys.argv[1]
probe = json.loads(subprocess.check_output([
    "ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json",
    os.path.join(out, "openfuse-fixture.mkv"),
]))
streams = probe["streams"]
video = next(s for s in streams if s["codec_type"] == "video")
audio = next(s for s in streams if s["codec_type"] == "audio")
subs = [s for s in streams if s["codec_type"] == "subtitle"]
duration = float(probe["format"]["duration"])
assert video["codec_name"] == "hevc" and video["profile"] == "Main 10", video
assert video["pix_fmt"] == "yuv420p10le", video
assert audio["codec_name"] == "eac3" and audio["channels"] == 6, audio
assert audio["channel_layout"].startswith("5.1"), audio
assert subs and subs[0]["codec_name"] == "ass", subs
assert abs(duration - 60.0) < 0.2, duration
channel_map = json.load(open(os.path.join(out, "audio-channel-map.json")))
assert channel_map["tone_tests"] >= 24 and not channel_map["failures"], channel_map["failures"]
print(f"ok: HEVC Main 10 {video['width']}x{video['height']}, "
      f"E-AC-3 {audio['channels']}ch {audio['channel_layout']}, "
      f"ASS tracks={len(subs)}, duration={duration:.3f}s, "
      f"channel tests={channel_map['tone_tests']}")
PY

echo "==> hashes"
shasum -a 256 "$OUT/openfuse-fixture.mkv" "$OUT/audio.wav" "$OUT/video.mkv" \
  | tee "$OUT/SHA256SUMS.txt"

echo "fixture ready: $OUT/openfuse-fixture.mkv"
