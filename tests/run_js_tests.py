"""
Runs the JavaScript tests in tests/js against a running game.

The game starts docked from the standard scenario, and moves through these
phases, running the tests in tests/js/<phase> in each:

- docked: docked at Lave, as the scenario starts;
- flight: launched, in flight near the station;
- arrived: after flying for a while, a hyperspace jump to the neighbouring
  system with the most stable government;
- redocked: docked there with dockPlayer();
- galactic: launched again, and after a galactic jump.

tests/oxp/oolite-test-recorder.oxp records the world-script events that
each phase change causes, so that tests can check them; tests can also keep
state in $state from one phase to the next. Each test file is sent to the game's debug
console (see oolite_harness.py) as the body of a function, preceded by
tests/js/prelude.js, which defines test(), assert() and friends. The run
fails if any test fails, if the console or the log reports a JavaScript
exception or error, or if the JavaScript runtime leaks objects at shutdown.

Usage: run_js_tests.py --path <oolite.app or binary> [--test_output DIR] [--filter TEXT]
"""

import argparse
import glob
import os
import re
import sys

from oolite_harness import HarnessError, OoliteGame

HERE = os.path.dirname(os.path.abspath(__file__))
JS_DIR = os.path.join(HERE, "js")
SAVE = os.path.join(os.path.dirname(HERE), "Resources", "Scenarios", "oolite-standard.oolite-save")
PHASES = ["docked", "flight", "arrived", "redocked", "galactic"]
RECORDER = 'worldScripts["oolite-test-recorder"]'
TIME_ACCELERATION = 16  # The most the game allows.

# Puts the player far from the main station, clear of anything that would block a jump.
MOVE_CLEAR = (
    "(function () { var st = system.mainStation;"
    " player.ship.position = st.position.add(st.position.subtract(system.mainPlanet.position).direction().multiply(300000));"
    " return true; })()"
)


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


def check_script_cache(log_path):
    """
    The compat test OXP turns on the compiled-script cache's log messages.
    Reports how the cache was used, and fails if a cached script could not be
    read back (which would mean cached bytecode no longer matches the engine).
    """
    try:
        with open(log_path, encoding="utf-8", errors="replace") as f:
            log = f.read()
    except OSError:
        return []
    counts = {kind: log.count(f"[script.javaScript.cache.{kind}]") for kind in ("load", "store", "stale", "readFailed")}
    print("[*] Compiled-script cache: " + ", ".join(f"{n} {kind}" for kind, n in counts.items()))
    if counts["readFailed"]:
        return [f"{counts['readFailed']} compiled script(s) could not be read back from the cache"]
    return []


def require(console, expression, what):
    if not console.evaluate(expression):
        raise HarnessError(f"Could not {what}.")


def enter_phase(console, phase):
    """Moves the game into a phase; the recorder files the events this causes under the phase."""
    if phase == "docked":
        # The game only answers once the saved game has loaded.
        console.wait_for("player.ship.docked && player.ship.dockedStation.isMainStation", timeout=180)
        # Launches, countdowns and jumps take game time: run it as fast as the game allows (16x).
        # Loading a game resets this, so it is set once the save has loaded; deployment builds ignore it.
        print(f"[*] Time acceleration: {console.evaluate(f'timeAccelerationFactor = {TIME_ACCELERATION}, timeAccelerationFactor')}x")
    console.evaluate(f"{RECORDER}.$begin({phase!r}), true")
    if phase == "docked":
        pass
    elif phase == "flight":
        # The hyperspace destination can only be chosen while docked: the most stable neighbouring system.
        console.evaluate(
            "(function () { var to = system.info.systemsInRange(7).sort(function (a, b)"
            " { return (b.government - a.government) || (a.systemID - b.systemID); })[0];"
            " player.ship.targetSystem = to.systemID; return to.systemID; })()"
        )
        require(console, "player.ship.launch(), true", "launch")
        console.wait_for('player.ship.status === "STATUS_IN_FLIGHT"', timeout=120)
    elif phase == "arrived":
        # Fly for a while first, so that AIs, timers and frame callbacks run: 10 seconds of game time, and
        # enough frames for the frame callback tests where frames are slow (4 fps on CI, where 10 seconds
        # at 16x is only a few frames). The count is kept on the console's this, which lasts between commands.
        start = console.evaluate("clock.seconds")
        console.evaluate(
            "(function () { var s = this; s.$flightFrames = 0;"
            " s.$flightCallback = addFrameCallback(function () { s.$flightFrames++; }); return true; }).call(this)"
        )
        console.wait_for(f"clock.seconds >= {start + 10} && this.$flightFrames >= 30", timeout=60, interval=0.1)
        console.evaluate("removeFrameCallback(this.$flightCallback), true")
        require(console, MOVE_CLEAR, "move clear of the station")
        require(console, "player.ship.beginHyperspaceCountdown(5)", "start the hyperspace countdown")
        console.wait_for(
            'system.ID === player.ship.targetSystem && player.ship.status === "STATUS_IN_FLIGHT"', timeout=180
        )
    elif phase == "redocked":
        console.evaluate("system.mainStation.dockPlayer(), true")
        # player.ship.docked is true a frame before shipDockedWithStation is sent.
        console.wait_for(f'{RECORDER}.$names().indexOf("shipDockedWithStation") !== -1', timeout=60)
    elif phase == "galactic":
        require(console, 'player.ship.awardEquipment("EQ_GAL_DRIVE")', "award a galactic hyperdrive")
        require(console, "player.ship.launch(), true", "launch")
        console.wait_for('player.ship.status === "STATUS_IN_FLIGHT"', timeout=120)
        require(console, MOVE_CLEAR, "move clear of the station")
        require(console, "player.ship.beginGalacticHyperspaceCountdown(5)", "start the galactic countdown")
        console.wait_for('galaxyNumber === 1 && player.ship.status === "STATUS_IN_FLIGHT"', timeout=180)


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

    # Only the test OXPs (the event recorder): the tests rely on the standard game.
    empty = os.path.join(test_output, "ManagedAddOns")
    os.makedirs(empty, exist_ok=True)
    game = OoliteGame(
        args.path,
        test_output,
        load=SAVE,
        extra_args=["-nosound"],
        extra_env={"OO_ADDITIONALADDONSDIRS": os.path.join(HERE, "oxp"), "OO_MANAGEDADDONSDIR": empty},
    )
    passed = failed = 0
    problems = []
    try:
        console = game.start()
        last = max((i for i, phase in enumerate(PHASES) if files[phase]), default=-1)
        for phase in PHASES[: last + 1]:  # Phases without tests still move the game on.
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

    # Test files declare log lines they cause on purpose with "// expect-log: <regular expression>".
    allowed = [m.group(1).strip() for phase in PHASES for path in files[phase]
               for m in re.finditer(r"^// expect-log:(.*)$", read(path), re.MULTILINE)]
    if game.proc is not None and game.proc.returncode not in (0, None):
        problems.append(f"Oolite exited with status {game.proc.returncode}")
    problems += game.check_log(require_leak_check=not args.no_leak_check, allowed=allowed)
    problems += check_script_cache(game.log_path)
    unexpected = [e for e in (game.console.exceptions if game.console else [])
                  if not any(re.search(a, e) for a in allowed)]
    if unexpected:
        problems.append(f"the console reported {len(unexpected)} exception(s)")
    for problem in problems:
        print(f"[!] {problem}")
    print(f"[*] {passed} passed, {failed} failed")
    return 0 if failed == 0 and not problems and passed > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
