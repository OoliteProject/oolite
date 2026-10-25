"""Regression test for bug oo-37zzy: pausing a console-driven game must not starve the console.

On Windows a pause puts the game in efficiency mode (GameController -setEcoQoS:), which was
IDLE_PRIORITY_CLASS plus EcoQoS throttling. An idle-class process runs only when no other thread
wants a CPU, so on a loaded machine a paused game drew a frame in 15-60 s and answered no console
command in between - the golden harness pauses before it touches the world, and its scenarios
timed out. The game now stays at normal priority while a debug console is connected.

The priority class is read directly, so this fails on the old behaviour however idle the machine
is, instead of only under load. Windows only: the efficiency mode is Windows only.
"""

import ctypes
import sys

import pytest

IDLE_PRIORITY_CLASS = 0x40
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
SCENARIO_SAVE = "Resources/Scenarios/oolite-standard.oolite-save"

pytestmark = pytest.mark.skipif(sys.platform != "win32", reason="efficiency mode is Windows only")


def _priority_class(pid):
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.OpenProcess.restype = ctypes.c_void_p
    handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    assert handle, f"cannot open the game process {pid}: error {ctypes.get_last_error()}"
    try:
        value = kernel32.GetPriorityClass(ctypes.c_void_p(handle))
        assert value, f"GetPriorityClass failed: error {ctypes.get_last_error()}"
        return value
    finally:
        kernel32.CloseHandle(ctypes.c_void_p(handle))


def test_a_paused_game_with_a_console_keeps_normal_priority(world):
    console = world.start(seed=1, load_save=SCENARIO_SAVE)
    assert console.evaluate("pauseGame()").strip().lower() == "true"
    assert _priority_class(console._proc.pid) != IDLE_PRIORITY_CLASS, (
        "the paused game went to IDLE_PRIORITY_CLASS with a debug console connected (oo-37zzy)"
    )
    assert console.evaluate("1 + 1", timeout=60).strip() == "2"
