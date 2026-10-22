#!/bin/bash
# Usage: compare.sh <expected> <actual>
# Diffs two probe outputs.
HERE="$(dirname "$0")"
# Lines listed in noise.txt are dropped, and so are those in expected-differences.txt when either file is a
# SpiderMonkey baseline; Oolite build version strings are normalised.
EXPECTED="$HERE/expected-differences.txt"
case "$1$2" in
    *spidermonkey*) ;;
    *) EXPECTED=/dev/null ;;
esac
filter() {
    grep -v -F -f <(grep -v '^#' "$HERE/noise.txt" | sed 's/$/ =/'; grep -v '^#' "$HERE/noise.txt" | sed 's/$/ ->/') "$1" |
        grep -v -F -f <(grep -v '^#' "$EXPECTED" | grep -v '^$'; echo "$(printf '\001')") |
        sed -E 's/version:"[^"]*"/version:"<version>"/g'
}
diff -u <(filter "$1") <(filter "$2") && echo "probe outputs match"
