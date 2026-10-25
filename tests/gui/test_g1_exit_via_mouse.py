"""G1 - exit the game via mouse on the start screen.

The calibration exemplar for the GUI tier (docs/stories/G1-exit-via-mouse.md,
docs/phases/0-gui-tier.md). It is the baseline smoke test: the window opens, synthetic mouse
input reaches the game, and the menu shutdown path works. Everything else in this tier
(G2-G9) reuses conftest.py's ``game`` fixture and ``row_to_point`` and cites this file.

    python3 -m pytest upstream/oolite/tests/gui/test_g1_exit_via_mouse.py -x -q

Needs the desktop: a real window, unlocked and logged in (ADR-0017). It takes tools/gui-lock
for the duration.
"""

import time

import pytest

from conftest import (
    DESKTOP_UNUSABLE_MARKER,
    DOUBLE_CLICK_INTERVAL_SECONDS,
    DPI_PER_MONITOR_AWARE,
    IS_WINDOWS,
    MAIN_GUI_PIXEL_HEIGHT,
    MAIN_GUI_ROW_HEIGHT,
    assert_clean_exit,
    assert_dpi_awareness_matches_game,
    assert_no_surviving_game_processes,
    point_to_row,
    row_to_point,
)

# src/SDL/MyOpenGLView.h:59 - two left clicks further apart than this are two single clicks to
# the game and never set gvMouseDoubleClick, so ` Exit Game ` is selected but never activated.
MOUSE_DOUBLE_CLICK_INTERVAL = 0.40

# PlayerEntity.m:9900-9960 - start-screen rows 22-27 are selectable and 27 is ` Exit Game `.
EXIT_GAME_ROW = 27
FIRST_SELECTABLE_ROW = 22

# The story's budget: a confirmed ` Exit Game ` that has not exited by now has not worked.
EXIT_TIMEOUT_SECONDS = 10


@pytest.mark.offline
@pytest.mark.parametrize("row", range(1, 28))
def test_row_to_point_is_its_own_inverse(row):
    """The grid maths, checked without a game.

    row_to_point aims at the centre of a row's band, so feeding its answer back through the
    chain the game itself walks (SDL motion -> virtualJoystickPosition -> cursor_row) must
    return the row we asked for. This is what makes "click row 27" a claim rather than a hope,
    and it is the part of the helper G2-G9 inherit unchanged.
    """
    for client_rect in ((0, 0, 960, 720), (37, 91, 1280, 720), (0, 0, 800, 600)):
        point = row_to_point(row, client_rect)
        assert point_to_row(point[0], point[1], client_rect) == row, (
            f"row {row} at {client_rect} round-tripped through {point}"
        )


@pytest.mark.offline
def test_unreachable_rows_are_refused_not_clamped():
    """Rows past the cursor's clamp must raise, never quietly resolve to a neighbour.

    GuiDisplayGen.m:1453-1456 clamps the cursor to the virtual half-height, so a point computed
    for row 29 selects row 28 instead. Returning that point would make a test click the wrong
    menu entry and still pass.
    """
    rect = (0, 0, 960, 720)
    for row in (29, 30, 40):
        with pytest.raises(ValueError):
            row_to_point(row, rect)
    # And the row this test actually needs is well inside.
    assert row_to_point(EXIT_GAME_ROW, rect)


@pytest.mark.offline
def test_row_points_are_distinct_and_ordered():
    """Adjacent rows must land on distinct points, increasing down the screen.

    A window small enough to collapse two rows onto the same pixel would make every menu test
    in this tier silently select the wrong thing, so the pinned size is checked, not assumed.
    """
    rect = (0, 0, 960, 720)
    ys = [row_to_point(row, rect)[1] for row in range(FIRST_SELECTABLE_ROW, EXIT_GAME_ROW + 1)]
    assert ys == sorted(ys)
    assert len(set(ys)) == len(ys)
    # One GUI row is MAIN_GUI_ROW_HEIGHT of 480 virtual pixels; at this window it must be worth
    # more than a couple of real ones.
    step = ys[1] - ys[0]
    assert step >= 2, f"rows are {step}px apart - the window is too small to click reliably"
    expected = MAIN_GUI_ROW_HEIGHT * 720 / MAIN_GUI_PIXEL_HEIGHT
    assert abs(step - expected) <= 1, f"row pitch {step}px, expected about {expected}px"


def test_g1_exit_via_mouse(game):
    """Launch, click ` Exit Game ` to select it, double-click to confirm, assert a clean exit.

    Two actions, not one. A single left click only calls setSelectedRow: on the row under the
    cursor (PlayerEntityControls.m:765-780); activation is Enter or a double-click. A test that
    single-clicks ` Exit Game ` and waits sits on the start screen until it times out.
    """
    assert game.proc.poll() is None, "the game exited before the test could click anything"
    # The window must own the foreground or the clicks below go to whatever does; the bug this
    # test was rewritten for was exactly that, mistaken for a coordinate error.
    game.assert_focused()

    # 1. Select. The click must not activate anything: the game is still running afterwards.
    x, y = game.select_row(EXIT_GAME_ROW)
    assert point_to_row(x, y, game.client_rect()) == EXIT_GAME_ROW
    time.sleep(0.5)
    assert game.proc.poll() is None, (
        "a single click activated a row; selection and activation are supposed to be distinct "
        "(PlayerEntityControls.m:765-780)"
    )

    # 2. Confirm.
    game.confirm_row(EXIT_GAME_ROW)

    # 3. Exits within the budget, with status 0.
    try:
        returncode = game.proc.wait(timeout=EXIT_TIMEOUT_SECONDS)
    except Exception:
        pytest.fail(
            f"the game was still running {EXIT_TIMEOUT_SECONDS}s after ` Exit Game ` was "
            f"confirmed at {(x, y)}"
        )
    assert returncode == 0, f"the game exited with {returncode}, not 0"

    # 4. No orphaned process. NOT `game.proc.poll() == 0` - wait() above already reaped and
    #    stored that returncode, so re-reading it is true by construction and checks nothing.
    #    Ask the OS process table instead, scoped to the tree we launched so a concurrent
    #    sibling GUI run's oolite.exe cannot be mistaken for our leak.
    assert_no_surviving_game_processes(game.proc.pid)

    # 5. G9 hygiene: no crash dump, no ERROR in the log, and a defaults file THIS RUN wrote and
    #    which re-parses. Passing the fixture itself rather than a directory is deliberate: the
    #    "written by this run" evidence is the launch-time mark GameWindow.start() recorded, and
    #    a call that could be spelled without it would be a check that cannot fail (oo-5rsa).
    assert_clean_exit(game)


# --- regression guards for the two defects behind this bug bead ---------------------------------
#
# Both were invisible on the implementer's desktop and fatal on the reviewer's, and neither needs
# a game to check, so both are marked offline and gate in a clean checkout too.


@pytest.mark.offline
@pytest.mark.skipif(not IS_WINDOWS, reason="DPI awareness is a Windows concept")
def test_test_process_is_dpi_aware_like_the_game():
    """The test process must measure pixels the way Oolite does - PER_MONITOR, not merely 'aware'.

    Oolite's manifest declares PerMonitorV2 (src/SDL/OOResourcesWin/oolite.exe.manifest:34-35).
    A DPI-unaware python.exe is handed virtualised logical pixels by GetClientRect,
    ClientToScreen and SendInput alike, so on any display above 100% scaling every point
    row_to_point computes is wrong by the scale factor and the confirm click misses ` Exit Game `
    while the maths still looks perfect. conftest declares awareness at import; this asserts it
    took, because the failure it prevents is otherwise indistinguishable from a coordinate bug.
    """
    assert_dpi_awareness_matches_game()


@pytest.mark.offline
@pytest.mark.skipif(not IS_WINDOWS, reason="DPI awareness is a Windows concept")
def test_system_dpi_awareness_is_not_accepted_as_matching_the_game():
    """SYSTEM awareness (1) must FAIL the check, not pass it.

    The assert this replaces was `awareness != 0`, which accepts PROCESS_SYSTEM_DPI_AWARE. A
    system-aware process is told the PRIMARY monitor's DPI for the whole desktop, so on any
    monitor whose scaling differs it still receives virtualised coordinates - exactly the
    game/test mismatch the function is named for, and exactly the reachable case (an awareness
    already set to SYSTEM by an earlier caller, so the PerMonitorV2 request is refused). A check
    that passes in the very scenario it exists to catch is not a check.
    """
    import conftest

    for insufficient in (conftest.DPI_UNAWARE, conftest.DPI_SYSTEM_AWARE):
        original = conftest._process_dpi_awareness
        conftest._process_dpi_awareness = lambda value=insufficient: value
        try:
            with pytest.raises(AssertionError) as caught:
                conftest.assert_dpi_awareness_matches_game()
        finally:
            conftest._process_dpi_awareness = original
        assert "PerMonitorV2" in str(caught.value)

    # And the real process must genuinely be PER_MONITOR, not just not-unaware.
    assert conftest._process_dpi_awareness() == DPI_PER_MONITOR_AWARE


@pytest.mark.offline
@pytest.mark.skipif(not IS_WINDOWS, reason="the DPI declaration is a Windows call")
def test_the_dpi_declaration_checks_its_own_return():
    """A refused SetProcessDpiAwarenessContext must be recorded with a MEANINGFUL error.

    The call's return was once thrown away entirely, so a refusal was invisible. Recording it is
    not enough on its own: ``ctypes.get_last_error()`` reads ctypes' private last-error slot,
    which is populated ONLY for functions reached through a
    ``ctypes.WinDLL(..., use_last_error=True)`` handle. Read after a call made on the shared
    ``ctypes.windll`` cache it is a constant 0, so "was REFUSED (error 0)" is what the operator
    would be told on exactly the path this guard exists for. Measured: after a genuinely refused
    second call, SetProcessDpiAwarenessContext -> False with ``ctypes.get_last_error()`` == 0 via
    windll but 5 (ERROR_ACCESS_DENIED) via an own handle.

    So this asserts the recorded error is REAL, by making a refusal happen and reading it.
    """
    import ctypes

    import conftest

    assert conftest._become_per_monitor_dpi_aware.requested is not None, (
        "the DPI declaration's outcome is not recorded, so a silent refusal is possible"
    )
    assert conftest.USER32 is not None
    # The tier's own handle, opened with use_last_error=True. That flag is the ONLY reason
    # ctypes.get_last_error() below returns anything but 0; ctypes.windll's cached library
    # does not carry it. Asserted off the flag on the handle's function-pointer class rather
    # than by identity against windll, so this file does not itself touch the banned handle
    # (test_win32_declarations.py bans it).
    FUNCFLAG_USE_LASTERROR = 0x10
    assert conftest.USER32._FuncPtr._flags_ & FUNCFLAG_USE_LASTERROR, (
        "the DPI calls must go through a WinDLL(..., use_last_error=True) handle, or "
        "get_last_error() is always 0 and a refusal reports nothing"
    )
    if not hasattr(conftest.USER32, "SetProcessDpiAwarenessContext"):
        pytest.skip("this Windows predates SetProcessDpiAwarenessContext")

    declared = conftest.USER32.SetProcessDpiAwarenessContext
    assert declared.argtypes == [ctypes.c_void_p], (
        "without argtypes the context is truncated to 32 bits and the call fails on win64"
    )

    # The refusal path, for real: awareness is already PerMonitorV2 (conftest set it at import),
    # and a second attempt to set it is refused with ERROR_ACCESS_DENIED. The error that gets
    # recorded must be that code, not zero.
    ctypes.set_last_error(0)
    refused = bool(declared(conftest.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2))
    error = ctypes.get_last_error()
    assert not refused, (
        "a second SetProcessDpiAwarenessContext was accepted; this test needs the refusal path"
    )
    assert error != 0, (
        "the refusal recorded error 0, which tells the operator nothing. That is what happens "
        "when get_last_error() is read after a call made through ctypes.windll instead of a "
        "WinDLL(..., use_last_error=True) handle."
    )
    assert error == 5, f"expected ERROR_ACCESS_DENIED (5) on a refused redeclaration, got {error}"

    # And the message the operator actually sees names that code rather than a constant zero.
    original = conftest._become_per_monitor_dpi_aware.error
    conftest._become_per_monitor_dpi_aware.error = error
    conftest._become_per_monitor_dpi_aware.requested = False
    real_awareness = conftest._process_dpi_awareness
    conftest._process_dpi_awareness = lambda: conftest.DPI_UNAWARE
    try:
        with pytest.raises(AssertionError) as caught:
            conftest.assert_dpi_awareness_matches_game()
    finally:
        conftest._process_dpi_awareness = real_awareness
        conftest._become_per_monitor_dpi_aware.error = original
        conftest._become_per_monitor_dpi_aware.requested = True
    assert "error 5" in str(caught.value), (
        "the assertion message must carry the real Win32 error code from the refusal"
    )


@pytest.mark.offline
def test_a_failed_start_kills_the_game_rather_than_leaking_it():
    """start() must not leave a live oolite.exe behind when it fails part-way through.

    This is BELT AND BRACES, and the docstring says so rather than claiming a cause it cannot
    demonstrate. The mechanism once asserted here - "the fixture's teardown only runs once
    ``yield window.start()`` has been reached, so a failure inside start() leaks the process" -
    is FALSE and was disproven by measurement: when start() raises, the exception propagates out
    through the ``yield`` expression inside the fixture generator and the ``finally:
    window.kill()`` in the ``game`` fixture runs during the unwind. Instrumented on both the
    pre-fix and post-fix trees by forcing a failure inside focus(): pre-fix, kill WAS called
    (kill_calls=1) and the launched pid was dead at session end; post-fix, kill_calls=2.

    The guard stays because killing twice costs nothing and a surviving oolite.exe costs the
    machine: _pin_window parks every instance at exactly (0,0) at the same client size, so any
    other instance covers the next run's rows pixel for pixel. What makes THAT condition loud is
    assert_click_point_is_ours, not this.
    """
    import conftest

    killed = []

    class ExplodingWindow(conftest.GameWindow):
        def __init__(self):
            super().__init__(".", ".")
            self.proc = object()  # stands in for the live Popen a failed start() leaves behind

        def _park_software_gl(self):
            pass

        def _await_startup_complete(self, timeout):
            pytest.fail("simulated: the game never finished loading")

        def kill(self):
            killed.append(True)

    window = ExplodingWindow()
    # Only the Popen and the steps after it matter here, so call the guarded region directly by
    # running start() with the binary check and the Popen stubbed out.
    original_popen = conftest.subprocess.Popen
    conftest.subprocess.Popen = lambda *a, **k: window.proc
    original_isfile = conftest.os.path.isfile
    conftest.os.path.isfile = lambda path: True
    original_assert = conftest.assert_dpi_awareness_matches_game
    conftest.assert_dpi_awareness_matches_game = lambda: None
    try:
        with pytest.raises(BaseException):
            window.start()
    finally:
        conftest.subprocess.Popen = original_popen
        conftest.os.path.isfile = original_isfile
        conftest.assert_dpi_awareness_matches_game = original_assert

    assert killed, (
        "start() failed without killing the process it had already launched; every failing run "
        "would leak a live oolite.exe that occludes the next run's click point"
    )


@pytest.mark.offline
def test_an_occluded_click_point_is_detected_even_though_focus_is_correct():
    """THE THIRD FAILURE MODE: owning the foreground does not mean owning the pixels.

    A synthetic click made with mouse_event (what pyautogui uses) is delivered BY POSITION to the
    topmost window at that point, exactly like a physical click - NOT to the foreground window.
    So a window above the game at the click point swallows the click while GetForegroundWindow()
    still answers with the game's hwnd and assert_focused() still passes. That is precisely the
    reviewer's report: focus() succeeded, assert_focused() passed, and the double-click still did
    not activate the row.

    Measured on this machine with a leaked oolite.exe present: foreground == our hwnd while
    WindowFromPoint(488,727) returned the ORPHAN's hwnd. assert_click_point_is_ours is the check
    that turns that silent miss into a named failure.
    """
    import conftest

    window = conftest.GameWindow.__new__(conftest.GameWindow)
    window.hwnd = 111111

    user32 = conftest.USER32
    real_from_point = user32.WindowFromPoint
    real_ancestor = user32.GetAncestor
    try:
        # Same window under the point: allowed.
        user32.WindowFromPoint = lambda point: 111111
        user32.GetAncestor = lambda hwnd, flag: 111111
        window.assert_click_point_is_ours(488, 727)

        # A DIFFERENT window under the point, while we still hold the foreground: fail loudly.
        user32.WindowFromPoint = lambda point: 222222
        user32.GetAncestor = lambda hwnd, flag: 222222
        with pytest.raises(BaseException) as caught:
            window.assert_click_point_is_ours(488, 727)
    finally:
        user32.WindowFromPoint = real_from_point
        user32.GetAncestor = real_ancestor

    message = str(caught.value)
    assert "OCCLUDED" in message, "the occlusion failure must name its own cause"
    assert "222222" in message, "the failure must name the window that would eat the click"


@pytest.mark.offline
@pytest.mark.skipif(not IS_WINDOWS, reason="the foreground is a Windows concept")
def test_assert_focused_retakes_the_foreground_rather_than_only_sampling_it():
    """A transiently stolen foreground must be RETAKEN, not turned into a hard failure.

    This is the structural cause of the DoD's non-repeatability. Measured on an otherwise idle
    machine with no oolite.exe present at start: 35 consecutive runs of the DoD command gave 34
    passes and ONE failure, at test_g1_exit_via_mouse.py:105, "the Oolite window lost the
    foreground before a click". ``select_row`` has always been self-healing because it calls
    ``focus()`` first; the bare ``assert_focused()`` calls did not, so anything that owned the
    foreground for an instant - a notification, an installer, or a sibling tool launching the
    game without taking tools/gui-lock - hard-failed the run.

    It is not a softening: when the foreground genuinely cannot be taken, focus() still spends
    its whole FOCUS_TIMEOUT_SECONDS budget and then hard-fails, which is asserted below too.
    """
    import conftest

    window = conftest.GameWindow.__new__(conftest.GameWindow)
    window.hwnd = 111111

    user32 = conftest.USER32
    real_foreground = user32.GetForegroundWindow
    try:
        # 1. Already focused: no focus() call needed at all.
        user32.GetForegroundWindow = lambda: 111111
        window.focus = lambda: pytest.fail("focus() must not be called when already focused")
        window.assert_focused()

        # 2. Foreground lost, and focus() gets it back: the assert must PASS, where the bare
        #    sample it replaces would have failed the whole run.
        stolen = [True]

        def recovering_focus():
            stolen[0] = False

        user32.GetForegroundWindow = lambda: 999999 if stolen[0] else 111111
        window.focus = recovering_focus
        window.assert_focused()
        assert not stolen[0], "assert_focused must actually attempt to retake the foreground"

        # 3. Foreground genuinely untakeable: still a hard failure, not a pass.
        user32.GetForegroundWindow = lambda: 999999
        window.focus = lambda: None
        with pytest.raises(AssertionError) as caught:
            window.assert_focused()
        assert "999999" in str(caught.value), "the failure must name the window that took it"
    finally:
        user32.GetForegroundWindow = real_foreground


@pytest.mark.offline
def test_an_unusable_desktop_is_reported_distinguishably_from_a_broken_g1():
    """An elevated foreground owner must be reported as a PRECONDITION, not as a click failure.

    AttachThreadInput cannot cross the UIPI/integrity boundary, so while an elevated window owns
    the foreground no retry can ever succeed and the tier is wedged. Measured: an elevated Task
    Manager (integrity 0x3000 against our 0x2000) refused AttachThreadInput with
    ERROR_ACCESS_DENIED on 11 consecutive runs. The gate must still FAIL - a silent pass is what
    bead oo-7by1 removed - but it must say which of the two things went wrong, because
    "your desktop is unusable" and "G1 is broken" call for opposite responses.
    """
    import conftest

    original = conftest.describe_untakeable_foreground
    conftest.describe_untakeable_foreground = lambda: (
        "hwnd 461400 (class 'TaskManagerWindow', title 'Task Manager', pid 22884) owns the "
        "foreground and refuses AttachThreadInput with ERROR_ACCESS_DENIED"
    )
    try:
        with pytest.raises(BaseException) as caught:
            conftest.assert_desktop_can_run_gui_tests()
    finally:
        conftest.describe_untakeable_foreground = original

    message = str(caught.value)
    assert not isinstance(caught.value, pytest.skip.Exception), (
        "an unusable desktop must not SKIP; that is the silent pass oo-7by1 removed"
    )
    assert DESKTOP_UNUSABLE_MARKER in message, (
        "the failure must carry the precondition marker so it is machine-distinguishable from a "
        "G1 failure"
    )
    assert "TaskManagerWindow" in message, "the failure must name the offending window"

    # And a takeable foreground must not fail at all.
    conftest.describe_untakeable_foreground = lambda: None
    try:
        conftest.assert_desktop_can_run_gui_tests()
    finally:
        conftest.describe_untakeable_foreground = original


@pytest.mark.offline
def test_the_runner_checks_the_desktop_precondition_up_front():
    """tools/gui-tier.sh must refuse an unusable desktop before it launches a game."""
    import os

    here = os.path.dirname(os.path.abspath(__file__))
    runner = os.path.join(here, "..", "..", "..", "..", "tools", "gui-tier.sh")
    with open(runner, "r", encoding="utf-8") as handle:
        script = handle.read()
    assert "describe_untakeable_foreground" in script, (
        "the runner must check for an un-takeable foreground before starting the tier"
    )
    assert "DESKTOP_UNUSABLE_MARKER" in script


@pytest.mark.offline
def test_double_click_interval_activates_rather_than_selecting_twice():
    """The confirm click's inter-click gap must be inside the game's double-click window.

    MyOpenGLView+Input.m:285-293 sets gvMouseDoubleClick only when the gap between two
    SDL_EVENT_MOUSE_BUTTON_UPs is under MOUSE_DOUBLE_CLICK_INTERVAL (0.40s,
    MyOpenGLView.h:59). Left at a library default, a slower pair is two single clicks: the row is
    selected, never activated, and the game runs on until the test times out - the exact symptom
    this bead was filed for. Pinning the interval is only a fix while it stays under the game's.
    """
    assert DOUBLE_CLICK_INTERVAL_SECONDS < MOUSE_DOUBLE_CLICK_INTERVAL, (
        f"confirm_row clicks {DOUBLE_CLICK_INTERVAL_SECONDS}s apart, but the game only counts a "
        f"double-click under {MOUSE_DOUBLE_CLICK_INTERVAL}s (MyOpenGLView.h:59)"
    )
    # And with margin: the interval is the *requested* gap, and a loaded machine adds to it.
    assert DOUBLE_CLICK_INTERVAL_SECONDS <= MOUSE_DOUBLE_CLICK_INTERVAL / 4.0, (
        "the double-click interval has no headroom for scheduling jitter"
    )

