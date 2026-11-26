"""G3 - exit the game by closing the window (SDL_EVENT_QUIT).

The same claim as G1 - "the game shuts down cleanly on a user's exit request" - reached down the
OTHER path into ``-exitAppWithContext:``. G1 goes through the start-screen menu; G3 goes through
the window manager, which is the path a user takes when they click the title-bar X and the only
path that covers ``MyOpenGLView+Input.m:660-664``:

    case SDL_EVENT_QUIT:
        SDL_DestroyWindow(window);
        [gameController exitAppWithContext:@"SDL_QUIT event received"];

Deliberately SHORT. Everything G1 built - the desktop lock, the readiness gate, DPI awareness,
the process-table survivor check, the G9 hygiene assert - is in conftest.py and is reused here
verbatim; this file adds the one thing that is different, which is how the exit is asked for.
The grid/DPI/foreground guards live with G1 (test_g1_exit_via_mouse.py) and are not repeated.

    python3 -m pytest upstream/oolite/tests/gui/test_g3_exit_via_window_close.py -x -q

Needs the desktop: a real window, unlocked and logged in (ADR-0017). It takes tools/gui-lock for
the duration, via the ``game`` fixture - this file launches nothing of its own.
"""

import time

import pytest

from conftest import (
    WM_CLOSE,
    assert_clean_exit,
    assert_no_surviving_game_processes,
)

# The story's budget. The close is delivered to a message queue the game pumps every frame, so a
# window that has not gone by now has not received it or has not acted on it. Measured on this
# build: PostMessageW(WM_CLOSE) -> exit status 0 in about 2s.
EXIT_TIMEOUT_SECONDS = 10


def test_g3_exit_via_window_close(game):
    """Close the window from outside the process; assert it really exits, cleanly.

    ONE action, unlike G1's select-then-confirm: closing a window is not a menu selection and
    has nothing to confirm. What is asserted is identical, because the DoD is about the SHUTDOWN,
    not about the gesture: the process is gone within the budget with status 0, no oolite.exe
    survived, and the G9 hygiene evidence (no dump, a clean Latest.log, a defaults file written
    by THIS run and still parseable) holds.
    """
    assert game.proc.poll() is None, "the game exited before the test could close anything"
    # The window must still be the live foreground one, or the hwnd we are about to post to is
    # not the window a user would have clicked the X on. assert_focused() self-heals (oo-0p8f).
    game.assert_focused()

    # 1. Close it, the way the window manager does. game.close_window() posts WM_CLOSE to the
    #    game's own hwnd from this process; SDL turns it into SDL_EVENT_QUIT. Its docstring
    #    carries the full justification for choosing that boundary over a synthetic SDL event.
    hwnd = game.close_window()

    # 2. It exits within the budget, with status 0. This is the whole claim: a close that leaves
    #    the game running, or that takes it down with a non-zero status, is not a clean exit.
    try:
        returncode = game.proc.wait(timeout=EXIT_TIMEOUT_SECONDS)
    except Exception:
        pytest.fail(
            f"the game was still running {EXIT_TIMEOUT_SECONDS}s after WM_CLOSE was posted to "
            f"hwnd {hwnd}; the SDL_EVENT_QUIT path (MyOpenGLView+Input.m:660-664) did not take "
            "the game down"
        )
    assert returncode == 0, f"the game exited with {returncode}, not 0"

    # 3. No orphaned process. Asked of the OS process table, not of proc.poll(): wait() above
    #    already reaped and stored that returncode, so re-reading it is true by construction.
    #    Scoped to the tree we launched so a concurrent sibling's oolite.exe is not our leak.
    assert_no_surviving_game_processes(game.proc.pid)

    # 4. G9 hygiene. assert_clean_exit(game) - the fixture, not a directory: the "written by this
    #    run" evidence is the launch-time mark start() recorded, and a spelling that omitted it
    #    would be a check that cannot fail (oo-5rsa).
    assert_clean_exit(game)


@pytest.mark.offline
def test_the_close_message_is_the_one_a_title_bar_x_delivers():
    """WM_CLOSE must be 0x0010, and the test must be posting THAT.

    Cheap, and it is the one constant in this file that cannot be checked by the game: a typo
    here would post some other message, the game would keep running, and the failure would look
    like "the SDL_EVENT_QUIT path is broken" rather than "the test asked for the wrong thing".
    """
    assert WM_CLOSE == 0x0010, "WM_CLOSE is 0x0010 in winuser.h"


@pytest.mark.offline
def test_the_close_is_posted_rather_than_synthesised_inside_the_game():
    """G3 must drive the real message queue, not fake an SDL event or call the exit directly.

    This is the guard that stops G3 decaying into a test of a function. A future edit that
    replaced the posted WM_CLOSE with ``SDL_PushEvent``, an injected ``exitAppWithContext``, or
    a plain ``proc.terminate()`` would leave every assertion in this file passing while the
    SDL_EVENT_QUIT case in MyOpenGLView+Input.m could be deleted outright without anything
    going red. Checked by reading this file's own source, so it cannot drift from it.
    """
    import ast
    import os

    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "test_g3_exit_via_window_close.py"), "r", encoding="utf-8") as h:
        source = h.read()
    tree = ast.parse(source)
    body = [
        node
        for node in tree.body
        if isinstance(node, ast.FunctionDef) and node.name == "test_g3_exit_via_window_close"
    ]
    assert body, "the G3 test function has been renamed; this guard must be renamed with it"
    called = {
        node.func.attr
        for node in ast.walk(body[0])
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
    }
    assert "close_window" in called, (
        "G3 no longer closes the window through game.close_window(); the test would no longer "
        "exercise the SDL_EVENT_QUIT path"
    )
    for forbidden in ("terminate", "kill", "send_signal"):
        assert forbidden not in called, (
            f"G3 calls {forbidden}(); killing the process proves the OS can kill a process, not "
            "that closing the window exits the game cleanly"
        )
