#!/usr/bin/env python3
"""
Usage: run_probe.py <oolite.app or binary> <output file> [options]

Runs the game from the standard scenario with the oojs_probe OXP installed
and writes the probe's log lines, with timestamps stripped, to the output
file. Compare outputs from two builds, or with a stored baseline, with
compare.sh.

The game is driven through the debug console (tests/oolite_harness.py), so
this works on Linux, macOS and Windows without Xvfb or xdotool; the build
must include debug support (any build type except deployment). Under Linux
it uses SDL's offscreen video driver with software OpenGL.

When the probe has finished it logs "ready for external quit"; the runner
then quits the game through the console, which with QuickJS also runs the
JavaScript runtime's shutdown leak check (see --check-leaks).
"""

import argparse
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(SRC, "tests"))

from oolite_harness import HarnessError, OoliteGame  # noqa: E402

READY = "ready for external quit"
PROBE_LINE = re.compile(r"\[oojs\.probe(\.quit)?\]|\[script\.javaScript\.(exception|error|warning)")
TIMESTAMP = re.compile(r"^[0-9:.]+ ")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("app", help="oolite.app directory (or bundle) or the oolite binary")
    parser.add_argument("output", help="file to write the probe's lines to")
    parser.add_argument("--extra-addons", help="directory whose .oxz/.oxp contents are installed with the probe")
    parser.add_argument("--timeout", type=int, default=int(os.environ.get("PROBE_TIMEOUT", "600")),
                        help="seconds to wait for the probe to finish (default 600, or $PROBE_TIMEOUT)")
    parser.add_argument("--check-leaks", action="store_true",
                        help="fail unless the JavaScript runtime shut down with no leaked objects (QuickJS builds)")
    args = parser.parse_args()

    output = os.path.abspath(args.output)
    work = output + ".run"
    shutil.rmtree(work, ignore_errors=True)
    addons = os.path.join(work, "AddOns")
    managed = os.path.join(work, "ManagedAddOns")
    logs = os.path.join(work, "logs")
    for path in (addons, managed, logs):
        os.makedirs(path)

    # Start from an AddOns folder containing only the probe (and any extra OXPs).
    shutil.copytree(os.path.join(HERE, "oojs_probe.oxp"), os.path.join(addons, "oojs_probe.oxp"))
    extra = args.extra_addons or os.environ.get("PROBE_EXTRA_ADDONS")
    if extra:
        # OXPs must be directly in AddOns; Oolite does not search subfolders.
        for name in os.listdir(extra):
            source = os.path.join(extra, name)
            if os.path.isdir(source):
                shutil.copytree(source, os.path.join(addons, name))
            else:
                shutil.copy(source, addons)

    game = OoliteGame(
        args.app,
        logs,
        load=os.path.join(SRC, "Resources", "Scenarios", "oolite-standard.oolite-save"),
        extra_args=["-nosound"],
        extra_env={"OO_ADDITIONALADDONSDIRS": addons, "OO_MANAGEDADDONSDIR": managed},
    )
    finished = False
    status = 1
    try:
        game.start()
        finished = game.wait_for_log(READY, args.timeout)
        if finished:
            game.quit()
            status = 0
        else:
            print(f"[!] The probe did not finish within {args.timeout} seconds.")
    except HarnessError as e:
        print(f"[!] {e}")
    finally:
        game.stop()

    with open(output + ".status", "w") as f:
        f.write(f"exit={status if game.proc is None or game.proc.returncode is None else game.proc.returncode}\n")
    if os.path.isfile(game.log_path):
        shutil.copy(game.log_path, output + ".full.log")
        with open(game.log_path, encoding="utf-8", errors="replace") as f:
            # Paths into this run's folder differ between runs.
            lines = [TIMESTAMP.sub("", line).replace(addons, "<AddOns>") for line in f if PROBE_LINE.search(line)]
        with open(output, "w", encoding="utf-8") as f:
            f.writelines(lines)
        print(f"[*] Wrote {len(lines)} probe lines to {output}")

    if args.check_leaks and finished:
        problems = [p for p in game.check_log() if "leak" in p]
        for problem in problems:
            print(f"[!] {problem}")
        if problems:
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main())
