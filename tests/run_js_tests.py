"""
Runs the JavaScript tests in tests/js against a running game.

The game starts docked from the standard scenario. The tests in
tests/js/docked run first; the player is then launched, and the tests in
tests/js/flight run in space. Each test file is sent to the game's debug
console (see oolite_harness.py) as the body of a function, preceded by
tests/js/prelude.js, which defines test(), assert() and friends. The run
fails if any test fails, if the console or the log reports a JavaScript
exception or error, or if the JavaScript runtime leaks objects at shutdown.

Usage: run_js_tests.py --path <oolite.app or binary> [--test_output DIR] [--filter TEXT]
"""

import argparse
import glob
import os
import sys

from oolite_harness import HarnessError, OoliteGame

HERE = os.path.dirname(os.path.abspath(__file__))
JS_DIR = os.path.join(HERE, "js")
SAVE = os.path.join(os.path.dirname(HERE), "Resources", "Scenarios", "oolite-standard.oolite-save")
PHASES = ["docked", "flight"]


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def run_file(console, prelude, path):
    """Runs one test file; returns a list of (name, error or None)."""
    source = read(path)
    # One function per file, so files cannot interfere with each other's variables.
    command = f"(function () {{\n{prelude}\n{source}\nreturn $results;\n}}).call(this)"
    try:
        results = console.evaluate(command, timeout=60)
    except HarnessError as e:
        return [(os.path.basename(path), f"the file did not run: {e}")]
    if not isinstance(results, list):
        return [(os.path.basename(path), f"the file returned {results!r} instead of test results")]
    return [(name, error) for name, error in results]


def enter_phase(console, phase):
    if phase == "docked":
        console.wait_for("player.ship.docked && player.ship.dockedStation.isMainStation", timeout=180)
    elif phase == "flight":
        console.evaluate("player.ship.launch(), true")
        console.wait_for('player.ship.status === "STATUS_IN_FLIGHT"', timeout=120)


def main():
    parser = argparse.ArgumentParser(description="Run the JavaScript tests in tests/js")
    parser.add_argument("--path", required=True, help="oolite.app directory (or bundle) or the oolite binary")
    parser.add_argument("--test_output", default="./test_output_js", help="directory for the game's log")
    parser.add_argument("--filter", help="only run test files whose path contains this text")
    parser.add_argument("--no-leak-check", action="store_true",
                        help="do not require the JavaScript leak check (for builds without it, such as SpiderMonkey ones)")
    args = parser.parse_args()

    test_output = os.path.abspath(args.test_output)
    os.makedirs(test_output, exist_ok=True)
    for old in glob.glob(os.path.join(test_output, "*.log")):
        os.remove(old)

    prelude = read(os.path.join(JS_DIR, "prelude.js"))
    files = {
        phase: sorted(
            p for p in glob.glob(os.path.join(JS_DIR, phase, "*.js")) if not args.filter or args.filter in p
        )
        for phase in PHASES
    }

    empty = os.path.join(test_output, "AddOns")  # No OXPs: the tests rely on the standard game.
    os.makedirs(empty, exist_ok=True)
    game = OoliteGame(
        args.path,
        test_output,
        load=SAVE,
        extra_args=["-nosound"],
        extra_env={"OO_ADDITIONALADDONSDIRS": empty, "OO_MANAGEDADDONSDIR": empty},
    )
    passed = failed = 0
    problems = []
    try:
        console = game.start()
        for phase in PHASES:
            if not files[phase]:
                continue
            print(f"[*] Phase: {phase}")
            enter_phase(console, phase)
            for path in files[phase]:
                rel = os.path.relpath(path, JS_DIR)
                for name, error in run_file(console, prelude, path):
                    if error is None:
                        passed += 1
                        print(f"[+]   PASS {rel}: {name}")
                    else:
                        failed += 1
                        print(f"[!]   FAIL {rel}: {name}\n        " + error.replace("\n", "\n        "))
        game.quit()
    except HarnessError as e:
        problems.append(str(e))
    finally:
        game.stop()

    problems += game.check_log(require_leak_check=not args.no_leak_check)
    if game.console and game.console.exceptions:
        problems.append(f"the console reported {len(game.console.exceptions)} exception(s)")
    for problem in problems:
        print(f"[!] {problem}")
    print(f"[*] {passed} passed, {failed} failed")
    return 0 if failed == 0 and not problems and passed > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
