#!/bin/bash
# Usage: run_probe.sh <oolite.app dir> <output file>
#
# Runs the game headless (Xvfb) from the standard scenario with the
# oojs_probe OXP installed, and writes the probe's log lines, with timestamps
# stripped, to the output file. Compare outputs from two builds with
# compare.sh. Needs xvfb-run and a software OpenGL (Mesa llvmpipe).
#
# Under qemu-user emulation (e.g. an amd64 container on an arm64 host),
# SpiderMonkey 1.8.5 builds need QEMU_RESERVED_VA=0x7fffffffffff: its value
# representation assumes pointers fit in 47 bits.

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$HERE/../.." && pwd)"
APP="$(cd "$1" && pwd)"
OUT="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"

rm -rf "$APP/GameData/AddOns/oojs_probe.oxp" "$APP/GameData/.logs"
mkdir -p "$APP/GameData/AddOns"
cp -r "$HERE/oojs_probe.oxp" "$APP/GameData/AddOns/"

cd "$(dirname "$OUT")"
timeout 240 xvfb-run -a -s "-screen 0 1280x720x24" "$APP/run_oolite.sh" -nosound -nosplash \
    -load "$SRC/Resources/Scenarios/oolite-standard.oolite-save" > "$OUT.stdout" 2>&1
echo "exit=$?" > "$OUT.status"

LOG="$APP/GameData/.logs/Latest.log"
cp "$LOG" "$OUT.full.log" 2>/dev/null
grep -E "\[oojs\.probe\]|\[script\.javaScript\.(exception|error|warning)" "$LOG" | sed -E 's/^[0-9:.]+ //' > "$OUT"
