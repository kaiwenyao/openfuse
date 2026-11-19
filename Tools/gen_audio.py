#!/usr/bin/env python3
"""Build the 6-channel E-AC-3 test track.

Every 12 seconds the clip walks the 5.1 layout in order (FL, FR, FC, LFE, BL,
BR): a pitched tone first, then a spoken channel announcement on the same
channel. A short 1 kHz beep sits on the centre channel at every whole second,
aligned with the white flash in the video, so A/V sync can be measured.

Voices alternate Chinese / Japanese so that a listener can also confirm that
the centre channel carries dialogue and that downmixing keeps it audible.

Usage: python3 Tools/gen_audio.py --seconds 60 --out Fixtures/generated/audio.wav
"""
from __future__ import annotations

import argparse
import array
import hashlib
import math
import os
import shutil
import subprocess
import sys
import wave

RATE = 48000
CHANNELS = 6
CHANNEL_NAMES_ZH = ["左前", "右前", "中置", "低频效果", "左环绕", "右环绕"]
CHANNEL_NAMES_JA = ["左前", "右前", "センター", "サブウーファー", "左サラウンド", "右サラウンド"]
FREQS = [440.0, 554.0, 659.0, 41.0, 740.0, 880.0]
CYCLE = 11.4
FIRST_CYCLE = 4.5
STEP = 1.9
TONE_LENGTH = 0.55
VOICE_OFFSET = 0.62


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def synth_voice(text: str, voice: str, cache_dir: str) -> tuple[array.array, int]:
    key = hashlib.sha1((voice + "|" + text).encode()).hexdigest()[:16]
    raw_path = os.path.join(cache_dir, key + ".f32")
    if not os.path.exists(raw_path):
        aiff = os.path.join(cache_dir, key + ".aiff")
        run(["say", "-v", voice, "-r", "175", "-o", aiff, text])
        run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", aiff,
             "-f", "f32le", "-ac", "1", "-ar", str(RATE), raw_path])
    data = array.array("f")
    with open(raw_path, "rb") as handle:
        data.frombytes(handle.read())
    if sys.byteorder != "little":
        data.byteswap()
    # Light fade in/out to avoid clicks.
    fade = int(0.01 * RATE)
    for index in range(min(fade, len(data))):
        gain = index / fade
        data[index] *= gain
        data[-1 - index] *= gain
    return data, len(data)


def add(buffer: array.array, offset_seconds: float, samples: array.array, gain: float) -> None:
    start = int(offset_seconds * RATE)
    for index, value in enumerate(samples):
        position = start + index
        if position >= len(buffer):
            break
        buffer[position] += value * gain


def synthesize(seconds: float, cache_dir: str) -> list[array.array]:
    total = int(seconds * RATE)
    channels = [array.array("f", bytes(4 * total)) for _ in range(CHANNELS)]

    def tone(freq: float, length: float, amplitude: float = 0.30) -> array.array:
        count = int(length * RATE)
        result = array.array("f", bytes(4 * count))
        fade = int(0.008 * RATE)
        for index in range(count):
            envelope = 1.0
            if index < fade:
                envelope = index / fade
            elif index > count - fade:
                envelope = max(0.0, (count - index) / fade)
            result[index] = amplitude * envelope * math.sin(2 * math.pi * freq * index / RATE)
        return result

    # Intro on the centre channel.
    intro_zh, zh_len = synth_voice("OpenFuse 五点一声道测试", "Tingting", cache_dir)
    add(channels[2], 0.25, intro_zh, 0.85)
    intro_ja, ja_len = synth_voice("五点一チャンネルテスト", "Kyoko", cache_dir)
    add(channels[2], 0.25 + zh_len / RATE + 0.15, intro_ja, 0.8)

    # Whole-second sync beeps on the centre channel.
    beep = tone(1000.0, 0.06, amplitude=0.16)
    for second in range(0, int(seconds) + 1):
        add(channels[2], float(second), beep, 0.5)

    cycle_index = 0
    start = FIRST_CYCLE
    while start + 6 * STEP + 1.6 < seconds:
        for channel in range(CHANNELS):
            at = start + channel * STEP
            add(channels[channel], at, tone(FREQS[channel], TONE_LENGTH), 0.55)
            if cycle_index % 3 == 0:
                voice = "Tingting"
                text = f"{CHANNEL_NAMES_ZH[channel]}声道"
                gain = 0.85
            elif cycle_index % 3 == 1:
                voice = "Kyoko"
                text = f"{CHANNEL_NAMES_JA[channel]}チャンネル"
                gain = 0.8
            else:
                voice = "Tingting"
                text = f"{CHANNEL_NAMES_ZH[channel]}，{CHANNEL_NAMES_JA[channel]}"
                gain = 0.8
            samples, _ = synth_voice(text, voice, cache_dir)
            add(channels[channel], at + VOICE_OFFSET, samples, gain)
        cycle_index += 1
        start += CYCLE

    return channels


def write_wav(path: str, channels: list[array.array], seconds: float) -> None:
    total = int(seconds * RATE)
    interleaved = array.array("h", bytes(2 * total * CHANNELS))
    peak = 0.0
    for channel in channels:
        for value in channel:
            peak = max(peak, abs(value))
    limit = 0.98
    scale = 1.0
    if peak > limit:
        scale = limit / peak
    for index in range(total):
        for channel in range(CHANNELS):
            value = channels[channel][index] * scale
            value = max(-1.0, min(1.0, value))
            interleaved[index * CHANNELS + channel] = int(value * 32767)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(CHANNELS)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(interleaved.tobytes())
    print(f"wrote {path}: {seconds:.1f}s {CHANNELS}ch peak={peak:.3f} scale={scale:.3f}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seconds", type=float, default=60.0)
    parser.add_argument("--out", default="Fixtures/generated/audio.wav")
    parser.add_argument("--cache", default="Fixtures/generated/tts")
    args = parser.parse_args()
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    os.makedirs(args.cache, exist_ok=True)
    if shutil.which("say") is None:
        raise SystemExit("macOS `say` is required for channel announcements")
    channels = synthesize(args.seconds, args.cache)
    write_wav(args.out, channels, args.seconds)

    layout = {
        "sample_rate": RATE,
        "channels": CHANNEL_NAMES_ZH,
        "channel_layout": "5.1",
        "first_cycle": FIRST_CYCLE,
        "cycle": CYCLE,
        "step": STEP,
        "tone_length": TONE_LENGTH,
        "voice_offset": VOICE_OFFSET,
        "frequencies": FREQS,
    }
    import json
    layout_path = os.path.join(os.path.dirname(os.path.abspath(args.out)), "audio-layout.json")
    with open(layout_path, "w", encoding="utf-8") as handle:
        json.dump(layout, handle, indent=2, ensure_ascii=False)
    print("wrote", layout_path)


if __name__ == "__main__":
    main()
