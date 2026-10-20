#!/bin/bash
# Usage: run_probe.sh <oolite.app dir> <output file>
#
# Runs the game headless (Xvfb) from the standard scenario with the
# oojs_probe OXP installed, and writes the probe's log lines, with timestamps
# stripped, to the output file. Compare outputs from two builds with
# compare.sh. Needs xvfb-run, xdotool and a software OpenGL (Mesa llvmpipe).
#
# When the probe is done it asks to be quit from outside JavaScript; this
# script then presses Shift-Escape, so a debug QuickJS build's shutdown leak
# check runs with no script on the stack.
#
# Under qemu-user emulation (e.g. an amd64 container on an arm64 host),
# SpiderMonkey 1.8.5 builds need QEMU_RESERVED_VA=0x7fffffffffff: its value
# representation assumes pointers fit in 47 bits. PROBE_TIMEOUT (seconds,
# default 600) bounds the run; flight is slow under software rendering.

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$HERE/../.." && pwd)"
APP="$(cd "$1" && pwd)"
OUT="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
LOG="$APP/GameData/.logs/Latest.log"

rm -rf "$APP/GameData/AddOns/oojs_probe.oxp" "$APP/GameData/.logs"
mkdir -p "$APP/GameData/AddOns"
cp -r "$HERE/oojs_probe.oxp" "$APP/GameData/AddOns/"

cd "$(dirname "$OUT")"
export APP SRC LOG OUT
timeout "${PROBE_TIMEOUT:-600}" xvfb-run -a -s "-screen 0 1280x720x24" bash -c '
    "$APP/run_oolite.sh" -nosound -nosplash -load "$SRC/Resources/Scenarios/oolite-standard.oolite-save" > "$OUT.stdout" 2>&1 &
    game=$!
    until grep -q "ready for external quit" "$LOG" 2>/dev/null || ! kill -0 $game 2>/dev/null; do sleep 1; done
    if kill -0 $game 2>/dev/null; then
        window=$(xdotool search --sync --class oolite | head -1)
        xdotool windowfocus --sync "$window" key shift+Escape
    fi
    wait $game
'
echo "exit=$?" > "$OUT.status"

cp "$LOG" "$OUT.full.log" 2>/dev/null
grep -E "\[oojs\.probe(\.quit)?\]|\[script\.javaScript\.(exception|error|warning)" "$LOG" | sed -E 's/^[0-9:.]+ //' > "$OUT"
