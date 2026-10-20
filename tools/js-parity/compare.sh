#!/bin/bash
# Usage: compare.sh <expected> <actual>
# Diffs two probe outputs, ignoring the lines listed in noise.txt.
HERE="$(dirname "$0")"
# Lines listed in noise.txt and expected-differences.txt are dropped; Oolite build version strings are normalised.
filter() {
    grep -v -F -f <(grep -v '^#' "$HERE/noise.txt" | sed 's/$/ =/'; grep -v '^#' "$HERE/noise.txt" | sed 's/$/ ->/') "$1" |
        grep -v -F -f <(grep -v '^#' "$HERE/expected-differences.txt" | grep -v '^$') |
        sed -E 's/version:"[^"]*"/version:"<version>"/g'
}
diff -u <(filter "$1") <(filter "$2") && echo "probe outputs match"
