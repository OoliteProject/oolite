#!/usr/bin/env python3
"""Compare the scenes oogpu-backend-test-gl and oogpu-backend-test-gpu drew.

Usage: oogpu-backend-compare.py <gl dir> <gpu dir>

Two APIs needn't rasterise identically, so a scene passes when at most
0.5% of its pixels differ by more than 16/255 in any channel and the mean
difference is at most 1/255. Exits non-zero if any scene fails.
"""
import glob
import os
import struct
import sys

kTolerance = 16
kMaxFraction = 0.005
kMaxMean = 1.0


def load(path):
    data = open(path, "rb").read()
    offset = struct.unpack("<I", data[10:14])[0]
    width, height = struct.unpack("<ii", data[18:26])
    bpp = struct.unpack("<H", data[28:30])[0] // 8
    return width, abs(height), bpp, data[offset:]


def compare(a_path, b_path):
    wa, ha, ba, a = load(a_path)
    wb, hb, bb, b = load(b_path)
    if (wa, ha, ba) != (wb, hb, bb):
        return None
    over = 0
    total = 0
    for i in range(0, wa * ha * ba, ba):
        d = max(abs(a[i + c] - b[i + c]) for c in range(3))
        total += d
        if d > kTolerance:
            over += 1
    pixels = wa * ha
    return over / pixels, total / (pixels * 3)


def main():
    gl_dir, gpu_dir = sys.argv[1], sys.argv[2]
    failures = 0
    for gl_path in sorted(glob.glob(os.path.join(gl_dir, "*.bmp"))):
        name = os.path.basename(gl_path)[:-4]
        gpu_path = os.path.join(gpu_dir, name + ".bmp")
        result = compare(gl_path, gpu_path) if os.path.exists(gpu_path) else None
        if result is None:
            print(f"FAIL {name:8} missing or different size")
            failures += 1
            continue
        fraction, mean = result
        ok = fraction <= kMaxFraction and mean <= kMaxMean
        failures += not ok
        print(f"{'OK  ' if ok else 'FAIL'} {name:8} {fraction * 100:6.3f}% of pixels over {kTolerance}/255, mean {mean:.3f}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
