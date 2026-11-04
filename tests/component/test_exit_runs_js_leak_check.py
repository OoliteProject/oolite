"""Regression test: quitting a debug build runs the JavaScript runtime's leak check.

Upstream #768 has GameController's exit path tear down the JavaScript runtime in a build without
NDEBUG, after the defaults are synchronized, so that a JSValue still alive at exit is reported.
A clean shutdown logs script.javaScript.shutDown (upstream #580), so this test can tell the check
ran. The engine is never released, so nothing else shuts it down: without the call in
GameController::exitAppWithContext the line is absent.

quitGame() is used because it quits once the calling script has returned (#580); a quit with a
script on the stack skips the check on purpose. The test build does not define NDEBUG, so the
check is compiled in.
"""

import os
import subprocess

import pytest

EXIT_TIMEOUT_SECONDS = 30
SHUTDOWN_CLASS = "[script.javaScript.shutDown]"
CLEAN_SHUTDOWN = "JavaScript runtime shut down with no leaked objects."


def test_quitting_logs_the_javascript_leak_check(world):
    console = world.start(seed=1)
    proc = console._proc
    console.perform("quitGame();")
    try:
        returncode = proc.wait(timeout=EXIT_TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired:
        pytest.fail(f"the game was still running {EXIT_TIMEOUT_SECONDS}s after quitGame()")
    assert returncode == 0, f"the game exited with {returncode}, not 0"

    log = os.path.join(world.output_dir, "Latest.log")
    assert os.path.isfile(log), f"no log written at {log}"
    with open(log, "r", encoding="utf-8", errors="replace") as handle:
        lines = [line.rstrip() for line in handle]

    shutdown = [line for line in lines if "[script.javaScript.shutDown" in line]
    assert shutdown, (
        "the exit path did not shut the JavaScript runtime down: no script.javaScript.shutDown "
        "line in Latest.log. Last lines:\n" + "\n".join(lines[-10:])
    )
    assert any(SHUTDOWN_CLASS in line and CLEAN_SHUTDOWN in line for line in shutdown), (
        "the JavaScript runtime did not shut down cleanly:\n" + "\n".join(shutdown)
    )
