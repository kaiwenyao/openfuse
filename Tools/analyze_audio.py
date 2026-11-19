#!/usr/bin/env python3
"""Verify that the fixture's E-AC-3 track really carries discrete channels.

Decodes the first audio stream to 48 kHz float PCM and measures RMS energy in
the tone window of each channel announcement. Fails if the dominant channel is
not the announced one or if leakage exceeds -20 dB.
"""
from __future__ import annotations

import argparse
import array
import json
import math
import os
import subprocess
import sys

RATE = 48000
LAYOUT = ["FL", "FR", "FC", "LFE", "BL", "BR"]
FIRST_CYCLE = 4.5
STEP = 1.2
TONE_LENGTH = 0.55


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("media")
    parser.add_argument("--out", default="")
    parser.add_argument("--layout", default="Fixtures/generated/audio-layout.json")
    args = parser.parse_args()

    with open(args.layout, encoding="utf-8") as handle:
        layout = json.load(handle)
    first_cycle = layout["first_cycle"]
    step = layout["step"]
    cycle_length = layout["cycle"]
    tone_length = layout["tone_length"]

    raw = subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", args.media,
         "-map", "0:a:0", "-ac", "6", "-ar", str(RATE), "-f", "f32le", "-"],
        check=True, capture_output=True,
    ).stdout
    samples = array.array("f")
    samples.frombytes(raw)
    if sys.byteorder != "little":
        samples.byteswap()
    total_frames = len(samples) // 6
    duration = total_frames / RATE

    def goertzel(start: int, end: int, channel: int, frequency: float) -> float:
        count = end - start
        if count <= 0:
            return 0.0
        omega = 2.0 * math.pi * frequency / RATE
        coefficient = 2.0 * math.cos(omega)
        s1 = 0.0
        s2 = 0.0
        for frame in range(start, end):
            s0 = samples[frame * 6 + channel] + coefficient * s1 - s2
            s2 = s1
            s1 = s0
        power = s1 * s1 + s2 * s2 - coefficient * s1 * s2
        return math.sqrt(max(power, 0.0)) / count

    results = []
    failures = []
    cycle = 0
    start = first_cycle
    while start + 6 * step + tone_length < duration:
        for channel in range(6):
            at = start + channel * step
            begin = int((at + 0.08) * RATE)
            end = int((at + 0.08 + 0.40) * RATE)
            frequency = layout["frequencies"][channel]
            energies = [goertzel(begin, min(end, total_frames), ch, frequency) for ch in range(6)]
            dominant = max(range(6), key=lambda index: energies[index])
            peak = energies[dominant] or 1e-9
            leakage = max(value for index, value in enumerate(energies) if index != dominant) / peak
            leakage_db = 20 * math.log10(max(leakage, 1e-9))
            ok = dominant == channel and leakage_db < -30
            results.append({
                "cycle": cycle,
                "expected": LAYOUT[channel],
                "dominant": LAYOUT[dominant],
                "tone_magnitude": [round(value, 5) for value in energies],
                "leakage_db": round(leakage_db, 1),
                "ok": ok,
            })
            if not ok:
                failures.append(results[-1])
        cycle += 1
        start += cycle_length

    report = {
        "media": args.media,
        "duration": round(duration, 3),
        "tone_tests": len(results),
        "failures": failures,
        "results": results,
    }
    text = json.dumps(report, indent=2, ensure_ascii=False)
    print(text)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as handle:
            handle.write(text)
    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
