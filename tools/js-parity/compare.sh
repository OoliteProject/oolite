#!/bin/bash
# Usage: compare.sh <expected> <actual>
# Diffs two probe outputs, ignoring the lines listed in noise.txt.
HERE="$(dirname "$0")"
filter() {
    grep -v -F -f <(grep -v '^#' "$HERE/noise.txt" | sed 's/$/ =/'; grep -v '^#' "$HERE/noise.txt" | sed 's/$/ ->/') "$1"
}
diff -u <(filter "$1") <(filter "$2") && echo "probe outputs match"
