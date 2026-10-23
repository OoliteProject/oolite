#!/usr/bin/env python3
"""
Usage: oxp_corpus.py <oolite.app or binary> [options]

Runs the parity probe (run_probe.py) with the OXPs in oxp-corpus.txt
installed, and compares the script problems that the OXPs cause (JavaScript
exceptions, errors and warnings, and scripts stopped by the time limiter)
with those recorded in oxp-corpus-known.txt. The probe's own lines are left
to the baseline comparison in ./mk.sh test.

Fails if an OXP causes an exception, error or warning that is not in the
known list, or if the probe does not finish cleanly. A script newly stopped
by the time limiter is reported as a warning only, since it depends on the
speed of the machine. Known problems that no longer occur are listed, so that
the list can be updated with --update.

The OXPs are downloaded into a cache directory (fetch_oxps.py). An OXP that
cannot be downloaded, or whose file has changed, is skipped with a warning;
if none is available, nothing is checked and the run says so.
"""

import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(SRC, "tests"))

import fetch_oxps  # noqa: E402

LIST = os.path.join(HERE, "oxp-corpus.txt")
KNOWN = os.path.join(HERE, "oxp-corpus-known.txt")

PROBLEM = re.compile(r"^\[script\.javaScript\.(exception|error|warning|timeLimit)[^\]]*\]: (.*)$")
# A problem's first line names it; the indented lines after it give the file and line.
HEADER = re.compile(r"^(\*\*\*\*\*|-----) JavaScript |^\S")
ADDRESS = re.compile(r"0x[0-9a-fA-F]+")
DECIMAL = re.compile(r"-?\d+\.\d+(e[-+]?\d+)?")


def github(command, message):
    if os.environ.get("GITHUB_ACTIONS") == "true":
        print(f"::{command} title=OXP corpus::{message}")


def summary(text):
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write(text + "\n")


def problems(probe_output):
    """Returns {problem: kind} for the problems in a probe output that are not the probe's own."""
    found = {}
    current = None
    kind = None

    def finish():
        if current is not None and "oojs_probe" not in current:
            found.setdefault(current, kind)

    with open(probe_output, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = PROBLEM.match(line.rstrip("\n"))
            if not m:
                continue
            text = m.group(2)
            if HEADER.match(text):
                finish()
                kind = m.group(1)
                current = text.strip()
            elif current is not None:
                current += " | " + text.strip()
    finish()
    # Addresses and positions differ from run to run.
    return {DECIMAL.sub("<n>", ADDRESS.sub("0x<addr>", p)): k for p, k in found.items()}


def read_known(path):
    if not os.path.isfile(path):
        return set()
    with open(path, encoding="utf-8") as f:
        return {line.rstrip("\n") for line in f if line.strip() and not line.startswith("#")}


def write_known(path, found):
    with open(path, "w", encoding="utf-8") as f:
        f.write("# Script problems that the OXPs in oxp-corpus.txt cause with the parity probe\n"
                "# (macOS arm64). Regenerate with: oxp_corpus.py <oolite.app> --update\n")
        for line in sorted(found):
            f.write(line + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("app", help="oolite.app directory (or bundle) or the oolite binary")
    parser.add_argument("--cache", default=os.path.join(SRC, "build", "oxp-corpus-cache"),
                        help="directory for the downloaded OXPs (default build/oxp-corpus-cache)")
    parser.add_argument("--output", default=os.path.join(SRC, "build", "oxp-corpus-output"),
                        help="directory for the probe's output and the game's log")
    parser.add_argument("--known", default=KNOWN, help="the list of known problems (default oxp-corpus-known.txt)")
    parser.add_argument("--update", action="store_true",
                        help="add the problems found to the known list instead of checking (with all OXPs available)")
    args = parser.parse_args()

    total = sum(1 for _ in fetch_oxps.entries(LIST))
    available, _ = fetch_oxps.fetch(args.cache, LIST, lenient=True)
    print(f"[*] {available} of {total} corpus OXPs available")
    if available == 0:
        message = f"0 of {total} corpus OXPs could be downloaded, so nothing was checked."
        print(f"[!] {message}")
        github("warning", message)
        summary(f"## OXP corpus\n\n{message}")
        return 0
    if args.update and available < total:
        print(f"[!] Only {available} of {total} OXPs are available; not updating {args.known}.")
        return 1
    if os.environ.get("GITHUB_OUTPUT") and available == total:
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as out:
            out.write("oxp-corpus-complete=true\n")

    os.makedirs(args.output, exist_ok=True)
    probe_output = os.path.join(args.output, "probe.txt")
    status = subprocess.call([sys.executable, "-u", os.path.join(HERE, "run_probe.py"), args.app, probe_output,
                              "--extra-addons", args.cache, "--check-leaks"])
    if status != 0 or not os.path.isfile(probe_output):
        print("[!] The parity probe did not finish cleanly with the corpus OXPs installed.")
        summary(f"## OXP corpus\n\nThe parity probe did not finish cleanly ({available} of {total} OXPs installed).")
        return 1

    found = problems(probe_output)
    if args.update:
        write_known(args.known, read_known(args.known) | set(found))
        print(f"[*] Recorded {len(found)} problem(s) in {args.known}")
        return 0

    known = read_known(args.known)
    new = sorted(p for p in found if p not in known)
    failures = [p for p in new if found[p] != "timeLimit"]
    slow = [p for p in new if found[p] == "timeLimit"]
    gone = sorted(known - set(found))
    for p in failures:
        print(f"[!] New: {p}")
        github("error", p)
    for p in slow:
        print(f"[?] New time-limit stop (may depend on the machine): {p}")
        github("warning", f"Time limit: {p}")
    for p in gone:
        print(f"[*] No longer seen: {p}")

    lines = [f"## OXP corpus\n\n{available} of {total} OXPs installed; {len(found)} problem(s), "
             f"{len(failures)} new, {len(slow)} new time-limit stop(s), {len(gone)} known but not seen."]
    if available < total:
        lines.append("\nSome OXPs could not be downloaded, so problems they cause were not checked.")
    for title, items in (("New", failures), ("New time-limit stops", slow), ("Known but not seen", gone)):
        if items:
            lines.append(f"\n### {title}\n\n" + "\n".join(f"- `{p}`" for p in items))
    summary("\n".join(lines))
    print(f"[*] {len(found)} problem(s): {len(failures)} new, {len(slow)} new time-limit stop(s), "
          f"{len(gone)} known but not seen")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
