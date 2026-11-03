"""G6 - window lifecycle: resize, minimise/restore, fullscreen.

docs/phases/0-gui-tier.md G6: "Resize, minimise/restore, fullscreen toggle. GL context survival."

Written the way test_g3_exit_via_window_close.py is written: SHORT where it can be, and reusing
conftest.py wholesale. The desktop lock, the readiness gate, DPI awareness, the pinned window,
the survivor check and the G9 hygiene asserts are G1's and are not repeated here. What this file
adds is the three lifecycle gestures and - the part that makes it a test rather than a sequence
of API calls - a pair of INDEPENDENT witnesses for each one.

WHY AN API CALL RETURNING SUCCESS PROVES NOTHING
------------------------------------------------
``SetWindowPos`` returning TRUE says the request was accepted, not that the window is that size;
``ShowWindow(SW_MINIMIZE)`` does not even return success (its BOOL is the PREVIOUS visibility);
and a synthetic F12 that the game never sampled returns exactly what one it did sample returns.
So every gesture below is judged by TWO observables that the gesture did not produce:

* THE OPERATING SYSTEM'S ANSWER - ``GetClientRect``/``GetWindowRect`` for geometry,
  ``IsIconic`` and ``GetWindowPlacement().showCmd`` for the minimised state, and the monitor's
  own ``rcMonitor`` (``MonitorFromWindow`` + ``GetMonitorInfoW``) for what "covers the screen"
  means on THIS machine.
* THE GAME'S OWN ANSWER - read out of the running process over the debug console, exactly as G5
  reads ``guiScreen``. ``oolite.gameSettings.gameWindow`` is Universe.m:4538-4542:
  ``[gameView backingViewSize].width/.height`` and
  ``[[self gameController] inFullScreenMode]``.

An OS rectangle alone would prove Windows moved a window; it would NOT prove the game reacted.
A game-side property alone would prove an instance variable changed; it would not prove anything
happened on screen. Both, for each gesture, is the claim.

WHAT MAKES THE GAME-SIDE OBSERVABLE ATTRIBUTABLE (and the guards that pin it)
----------------------------------------------------------------------------
``backingViewSize`` is ``bounds.size`` (MyOpenGLView.m:679-682), and ``bounds.size`` is assigned
in EXACTLY ONE place in the whole source tree - MyOpenGLView.m:514, the first line of
``-updateGLSize:``. ``-updateGLSize:`` is called from exactly two places: the resize handler at
MyOpenGLView+Input.m:679 and ``-initialiseGLWithSize:`` at MyOpenGLView.m:615. So reading the
size we asked for back out of the live game proves ``-updateGLSize:`` ran in THIS process with
THAT size - i.e. the game recomputed ``display_z``, ``x_offset``/``y_offset`` and its
``glViewport``. That is the same class of evidence G3 accepted for SDL_EVENT_QUIT's context
string and G5 accepted for ``guiScreen``, and
``test_the_games_view_size_has_exactly_one_assignment_in_the_tree`` fails if it ever stops being
unique.

The route from the OS resize to that assignment is equally singular:
``resize_pending = true`` occurs once in the tree (MyOpenGLView+Input.m:635) and it is inside the
``SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED`` case, so the game only reaches ``-updateGLSize:`` at all
by having been TOLD by the window system that its pixel size changed.

Fullscreen is the same shape. ``inFullScreenMode`` answers ``fullScreen``
(MyOpenGLView.m:715-718), and after start-up the only thing that assigns ``fullScreen`` is
``-setFullScreenMode:`` (MyOpenGLView.m:723); the only caller of ``-toggleScreenMode`` in the
tree is the ``SDLK_F12`` case at MyOpenGLView+Input.m:471. The gesture is therefore a real F12
through ``SendInput`` - the tier's own scancode path, which G2 measured as the only way this
SDL3 build actually receives a key - and not a JS call, which would prove a function works
rather than that the key does. The log carries the second witness: ``-initialiseGLWithSize:``
logs "Requested a new surface of W x H, fullscreen." (MyOpenGLView.m:591-592), and the word
``fullscreen`` in that line cannot be produced by any windowed path.

RELATIONSHIPS, NOT MAGIC PIXELS
-------------------------------
Nothing here asserts a size this test did not itself cause. The resize target is chosen by this
file; the assertion is that the client rect IS that, that the game reports THAT, and that both
differ from what they were before. "Fullscreen covers the screen" is measured against the
monitor the window is on. "Restore put it back" is measured against the rectangle recorded
immediately before the minimise AND against ``rcNormalPosition``, which Windows itself
remembers. A test that asserted 1024x768 because this machine happens to use it would be a
flake on any other display.

THE SHARED DESKTOP AND THE SHARED BUILD
---------------------------------------
Five agents share this machine. Two consequences, both handled rather than hoped about:

* EVERY measurement re-checks that the hwnd it is about to read belongs to the pid this test
  launched (``assert_window_is_ours``). conftest._pin_window parks EVERY instance at (0,0) at
  960x720, so a sibling's window is pixel-identical to ours and would satisfy any assertion
  that did not check ownership.
* The game WRITES the window size it ends up with into its preferences (``-saveWindowSize:``,
  MyOpenGLView.m:1309-1315, reached from the resize handler at MyOpenGLView+Input.m:683), and
  ``-setFullScreenMode:`` writes the ``fullscreen`` key. Against the shared build that would
  mutate ``<build>/oolite.app/GNUstep/Defaults/oolite.plist`` for every other tier on the
  machine. So this file overrides ``app_dir`` with a PRIVATE staged app, exactly as
  test_g7_first_run_creates_defaults.py does and with the same audited helpers
  (tests/launch_snapshot.py ``stage_app``/``unstage_app``): junctions for the read-only
  directories, real copies for the three the game writes. The shared prefs file is never
  touched, and ``test_the_staged_app_is_private_and_the_shared_build_is_read_only`` pins it.

Finally, the window is put back the way the tier hands it over - pinned at (0,0) at
PINNED_CLIENT_SIZE - before the game is asked to exit, so nothing this test moved outlives it.

    python3 -m pytest upstream/oolite/tests/gui/test_g6_window_lifecycle.py -x -q

Needs the desktop: a real window, unlocked and logged in (ADR-0017). It takes tools/gui-lock for
the duration, via the ``game`` fixture - this file launches nothing of its own.
"""

import ast
import ctypes
import os
import re
import sys
import time

import pytest

import conftest
from conftest import (
    MONITORINFO,
    PINNED_CLIENT_SIZE,
    USER32,
    WINDOWPLACEMENT,
    assert_clean_exit,
    assert_no_surviving_game_processes,
    assert_shutdown_path_completed,
)

HERE = os.path.dirname(os.path.abspath(__file__))
TESTS_DIR = os.path.abspath(os.path.join(HERE, ".."))
OOLITE_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC_DIR = os.path.join(OOLITE_ROOT, "src")
if TESTS_DIR not in sys.path:
    sys.path.insert(0, TESTS_DIR)

# The staging helpers, imported rather than re-written - the same ones G7 uses. unstage_app in
# particular removes junctions AS LINKS, so a teardown cannot recurse into the real build.
from launch_snapshot import stage_app, unstage_app  # noqa: E402

# The console witness, imported from G5 rather than reimplemented: the framing, the handshake,
# the private-port debugConfig.plist and the echo-proof marker are all already audited there.
from test_g5_screen_round_trips import (  # noqa: E402
    START_SCREEN,
    ScreenWitness,
    ScreenWitnessError,
)

if conftest.IS_WINDOWS:
    from ctypes import wintypes

# --- what this test causes ----------------------------------------------------------------------
#
# CHOSEN HERE, not observed: every geometry assertion below is "the window is what THIS FILE
# asked for", never "the window is some size that happens to be true on this display". Both
# differ from conftest.PINNED_CLIENT_SIZE and from the pinned (0,0) origin so that a gesture that
# did nothing leaves the window at a measurably different place and size.
RESIZE_CLIENT_SIZE = (800, 600)
RESIZE_ORIGIN = (40, 30)

# winuser.h. SW_SHOWMINIMIZED/SW_SHOWNORMAL are what GetWindowPlacement reports in showCmd; the
# SW_* values passed to ShowWindow are the command codes.
SW_SHOWNORMAL = 1
SW_SHOWMINIMIZED = 2
SW_MINIMIZE = 6
SW_RESTORE = 9
SWP_NOZORDER = 0x0004
MONITOR_DEFAULTTONEAREST = 0x00000002

# How long the OS and the game are given to act. A window state change is asynchronous: ShowWindow
# posts, the game's message pump services it, and the resize handler acts on the NEXT frame.
STATE_TIMEOUT_SECONDS = 15
# The game's own clock must advance by this much after the restore for the run loop to count as
# drawing again (OOJSClock.m - UNIVERSE's time only moves while frames are stepped).
FRAMES_AFTER_RESTORE_SECONDS = 0.5
# Same exit budget as G1/G3.
EXIT_TIMEOUT_SECONDS = 10
# MyOpenGLView+Input.m:663 - the context this file's exit gesture hands -exitAppWithContext:.
EXPECTED_EXIT_CONTEXT = "SDL_QUIT event received"


# --- the OS's answers ----------------------------------------------------------------------------


def window_rect(hwnd):
    """``(left, top, right, bottom)`` of the whole window frame, in screen pixels."""
    rect = wintypes.RECT()
    if not USER32.GetWindowRect(hwnd, ctypes.byref(rect)):
        raise conftest._win32_error("GetWindowRect")
    return (rect.left, rect.top, rect.right, rect.bottom)


def client_size(hwnd):
    """``(width, height)`` of the client area - the pixels the game actually renders into."""
    rect = wintypes.RECT()
    if not USER32.GetClientRect(hwnd, ctypes.byref(rect)):
        raise conftest._win32_error("GetClientRect")
    return (rect.right - rect.left, rect.bottom - rect.top)


def window_placement(hwnd):
    """The full WINDOWPLACEMENT. ``showCmd`` is the OS's own name for the window's state."""
    placement = WINDOWPLACEMENT()
    placement.length = ctypes.sizeof(WINDOWPLACEMENT)
    if not USER32.GetWindowPlacement(hwnd, ctypes.byref(placement)):
        raise conftest._win32_error("GetWindowPlacement")
    return placement


def is_iconic(hwnd):
    """The ONLY authority on "minimised".

    A minimised window's GetWindowRect answers an off-screen parking rectangle, so a rect
    comparison cannot tell a minimise from a move - and the parking coordinates are not
    documented, so asserting them would be asserting an implementation detail of the shell.
    """
    return bool(USER32.IsIconic(hwnd))


def monitor_rect(hwnd):
    """``(left, top, right, bottom)`` of the monitor this window is on.

    THIS is what "fullscreen covers the screen" is measured against - the display the window
    actually sits on, read at the moment of the assertion, so the test says nothing about any
    particular resolution.
    """
    handle = USER32.MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST)
    if not handle:
        raise conftest._win32_error("MonitorFromWindow")
    info = MONITORINFO()
    info.cbSize = ctypes.sizeof(MONITORINFO)
    if not USER32.GetMonitorInfoW(handle, ctypes.byref(info)):
        raise conftest._win32_error("GetMonitorInfoW")
    return (
        info.rcMonitor.left,
        info.rcMonitor.top,
        info.rcMonitor.right,
        info.rcMonitor.bottom,
    )


def owning_pid(hwnd):
    pid = wintypes.DWORD()
    USER32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    return pid.value


def assert_window_is_ours(game, where):
    """The hwnd about to be measured belongs to the process THIS test launched.

    Not decoration. conftest._pin_window parks EVERY Oolite instance at (0,0) at 960x720, and
    five agents share this desktop, so a sibling's window is pixel-for-pixel identical to ours.
    Without this check, "the window is 800x600 at (40,30)" could in principle be satisfied by
    somebody else's window - and, worse, a stale hwnd from a dead instance would still answer
    GetWindowRect with its last rectangle. Re-checked at every phase rather than once, because
    what it guards against can appear mid-test.
    """
    pid = owning_pid(game.hwnd)
    assert pid == game.proc.pid, (
        f"[{where}] hwnd {game.hwnd} belongs to pid {pid}, not to the game this test launched "
        f"(pid {game.proc.pid}). Every Oolite instance on this desktop is pinned to the same "
        "position and size by conftest._pin_window, so a sibling agent's window would satisfy "
        "these geometry assertions; nothing below may be measured against it."
    )


def wait_for(predicate, timeout=STATE_TIMEOUT_SECONDS, interval=0.25):
    """Poll ``predicate`` until it is true or the budget runs out. Returns its last value."""
    deadline = time.time() + timeout
    value = predicate()
    while not value and time.time() < deadline:
        time.sleep(interval)
        value = predicate()
    return value


def set_client_rect(hwnd, origin, size):
    """Move and resize so the CLIENT area is exactly ``size`` at exactly ``origin``.

    The chrome delta is COMPUTED from this very window's current frame and client rectangles
    rather than assumed, because border and caption metrics are a property of the desktop theme.
    SetWindowPos takes the OUTER size, so asking for the client size directly is the whole point
    of the arithmetic - and the assertion afterwards is on the CLIENT rect, i.e. on the thing
    this function claims to control.
    """
    outer = window_rect(hwnd)
    inner = client_size(hwnd)
    chrome_w = (outer[2] - outer[0]) - inner[0]
    chrome_h = (outer[3] - outer[1]) - inner[1]
    if not USER32.SetWindowPos(
        hwnd,
        None,
        origin[0],
        origin[1],
        size[0] + chrome_w,
        size[1] + chrome_h,
        SWP_NOZORDER,
    ):
        raise conftest._win32_error("SetWindowPos")
    return chrome_w, chrome_h


# --- the game's own answers ----------------------------------------------------------------------


class WindowWitness(ScreenWitness):
    """G5's console witness, taught one extra question: evaluate arbitrary JS.

    Subclassed rather than copied so the framing, the handshake and the private-port
    debugConfig.plist stay in ONE place. The marker trick is G5's and is kept for the same
    reason: the console echoes the command text back before the answer, so a marker that
    appeared literally in the command would match the echo.
    """

    def evaluate(self, expression, timeout=15):
        head = f"@@g6-{os.getpid()}-{self.port}"
        tail = f"{int(time.time() * 1000) % 1000000}@@"
        marker = head + tail
        self._send({
            conftest_packet_type(): "Perform Command",
            "message": (
                'debugConsole.consoleMessage("command-result", '
                f'"{head}" + "{tail}" + String({expression}) + "{head}" + "{tail}");'
            ),
        })
        deadline = time.time() + timeout
        import select

        while time.time() < deadline:
            readable, _, _ = select.select([self._conn], [], [], 1)
            if not readable:
                continue
            packet = self._recv()
            if packet is None:
                raise ScreenWitnessError("the console connection closed mid-query")
            if packet.get("packet type") != "Console Output":
                continue
            text = str(packet.get("message", ""))
            if text.count(marker) >= 2:
                return text.split(marker)[1]
        raise ScreenWitnessError(f"no answer to {expression!r} within {timeout}s")

    # --- the three questions this file asks -------------------------------------------------

    def game_window_size(self):
        """``(width, height)`` as the GAME sees its own drawable - Universe.m:4539-4540.

        That is ``[gameView backingViewSize]``, i.e. ``bounds.size``, which is assigned in
        exactly one place in the tree (MyOpenGLView.m:514, inside ``-updateGLSize:``).
        """
        raw = self.evaluate("oolite.gameSettings.gameWindow.width + 'x' "
                            "+ oolite.gameSettings.gameWindow.height")
        width, _, height = raw.strip().partition("x")
        return int(float(width)), int(float(height))

    def game_is_fullscreen(self):
        """``[[UNIVERSE gameController] inFullScreenMode]`` - Universe.m:4541.

        MEASURED, not assumed: this property comes back over the console as ``0``/``1``, not
        as ``false``/``true``. It is an ObjC BOOL boxed with ``+numberWithBool:``, and
        ``String()`` of the resulting JS value is the number. The first spelling of this method
        compared against ``"true"`` and therefore answered False for a genuinely fullscreen
        game - the fullscreen phase failed while the game's own log said "Requested a new
        surface of 5120 x 1392, fullscreen." So every accepted spelling is listed explicitly
        and anything else RAISES rather than being read as False: a silent False here is a test
        that can never see a successful toggle however well the game behaves.
        """
        raw = self.evaluate("oolite.gameSettings.gameWindow.fullScreen").strip().lower()
        if raw in ("1", "true"):
            return True
        if raw in ("0", "false"):
            return False
        raise ScreenWitnessError(
            f"oolite.gameSettings.gameWindow.fullScreen answered {raw!r}, which is neither a "
            "boolean nor 0/1. Treating an unrecognised answer as False would make the "
            "fullscreen assertion unable to pass however well the game behaved."
        )

    def game_clock(self):
        """UNIVERSE's own clock, which only advances while the run loop steps frames."""
        return float(self.evaluate("clock.absoluteSeconds").strip())

    def assert_on_start_screen(self, where):
        """The game is on GUI_SCREEN_INTRO1 - the runtime half of the F12 attribution.

        -toggleScreenMode has two callers (see the offline guard): the SDLK_F12 case, and the
        Game Options screen's ``Display Style`` row (PlayerEntityControls.m:3871), which is
        gated on ``guiSelectedRow == GUI_ROW(GAME,DISPLAYSTYLE)`` and can therefore only run on
        GUI_SCREEN_GAMEOPTIONS. Establishing the screen immediately before the key press is what
        rules that route out, so "the game went fullscreen" is attributable to the key.
        """
        seen = self.gui_screen()
        assert seen == START_SCREEN, (
            f"[{where}] the game is on {seen}, not {START_SCREEN}. The fullscreen gesture is a "
            "real F12, and the ONLY other route to -toggleScreenMode is the Game Options "
            "screen's Display Style row (PlayerEntityControls.m:3871) - so the toggle is only "
            "attributable to the key while the game is demonstrably not on that screen."
        )
        return seen

    def wait_for_game_window_size(self, expected, timeout=STATE_TIMEOUT_SECONDS):
        seen = self.game_window_size()
        deadline = time.time() + timeout
        while seen != expected and time.time() < deadline:
            time.sleep(0.5)
            seen = self.game_window_size()
        return seen

    def wait_for_game_fullscreen(self, expected, timeout=STATE_TIMEOUT_SECONDS):
        seen = self.game_is_fullscreen()
        deadline = time.time() + timeout
        while seen != expected and time.time() < deadline:
            time.sleep(0.5)
            seen = self.game_is_fullscreen()
        return seen


def conftest_packet_type():
    """The console protocol's packet-type key, spelled once."""
    return "packet type"


# --- fixtures ------------------------------------------------------------------------------------


@pytest.fixture(scope="session")
def app_dir(pytestconfig, tmp_path_factory):
    """OVERRIDES conftest.app_dir so the game writes its window preferences SOMEWHERE PRIVATE.

    This is not isolation for its own sake. The resize under test makes the game call
    ``-saveWindowSize:`` (MyOpenGLView+Input.m:683 -> MyOpenGLView.m:1309-1315), which writes
    ``window_width``/``window_height`` into NSUserDefaults, and ``-setFullScreenMode:``
    (MyOpenGLView.m:721-729) writes and synchronizes the ``fullscreen`` key. main.m:119 derives
    GNUSTEP_USERS_ROOT from the directory holding the executable, so against the shared build
    those writes land in ``<build>/oolite.app/GNUstep/Defaults/oolite.plist`` - the file every
    other tier and every concurrent agent on this machine reads.

    Same mechanism and the same audited helpers as G7: a staged app whose read-only directories
    are junctions into the real build and whose three written directories are real copies.
    """
    real = pytestconfig.getoption("--oolite-app") or conftest._default_app_dir()
    if not os.path.isdir(real):
        pytest.fail(
            f"no Oolite build at {real}. Build it first (tools/build-windows.sh test) "
            "or pass --oolite-app."
        )
    staged = str(tmp_path_factory.mktemp("g6-window-lifecycle") / "oolite.app")
    stage_app(real, staged)
    try:
        yield staged
    finally:
        # unstage_app, NEVER rmtree: the staged app is full of junctions INTO THE REAL BUILD.
        unstage_app(staged)


@pytest.fixture
def window_witness():
    """Listen for the game's console connection before the game exists. G5's arrangement.

    Named FIRST in the test's signature so pytest builds it BEFORE ``game``: the game dials out
    during start-up (OODebugSupport.m:67-80), so a socket that starts listening afterwards is
    never connected to.
    """
    witness = WindowWitness()
    previous = os.environ.get("OO_ADDITIONALADDONSDIRS")
    roots = [witness.config_root.replace("\\", "/")]
    if previous:
        roots.append(previous)
    os.environ["OO_ADDITIONALADDONSDIRS"] = ",".join(roots)
    try:
        yield witness
    finally:
        if previous is None:
            os.environ.pop("OO_ADDITIONALADDONSDIRS", None)
        else:
            os.environ["OO_ADDITIONALADDONSDIRS"] = previous
        witness.close()


# --- the test ------------------------------------------------------------------------------------


def test_g6_window_lifecycle(window_witness, game):
    """Resize, minimise, restore, fullscreen and back - each proved by the OS AND by the game.

    One launch, five phases, in the order the DoD names them. Each phase asserts a relationship
    this test CAUSED, and each of the seven properties below carries its own message so a red
    run says which one failed:

        RESIZE (OS)        the client rect is exactly what was asked for, at the asked-for origin
        RESIZE (GAME)      the game's own backingViewSize is that size, and it CHANGED
        MINIMISE           IsIconic is true and showCmd is SW_SHOWMINIMIZED
        RESTORE            IsIconic is false, showCmd is SW_SHOWNORMAL, and the frame rect is
                           byte-for-byte the pre-minimise one
        GL SURVIVAL        after the restore the game is still stepping frames and still reports
                           the resized drawable
        FULLSCREEN         the game reports fullscreen, logs a fullscreen surface, and the frame
                           covers the monitor it is on
        WINDOWED RETURN    F12 again puts it back to the size THIS TEST chose, which the game
                           had saved
    """
    witness = window_witness.accept()
    assert game.proc.poll() is None, "the game exited before the test could touch its window"

    log_path = os.path.join(game.output_dir, "Latest.log")
    with open(log_path, "r", encoding="utf-8", errors="replace") as handle:
        log_before_fullscreen_anchor = len(handle.read())

    # --- phase 0: the two witnesses agree BEFORE anything is changed ---------------------------
    #
    # Not an assertion about the pinned size (a magic number this test did not choose); an
    # assertion that the game's idea of its drawable MATCHES the OS's idea of its client area.
    # Without this, a later "the game says 800x600" could be true of a witness that reports the
    # client rect by some other route, and the resize would prove nothing.
    assert_window_is_ours(game, "baseline")
    baseline_client = client_size(game.hwnd)
    baseline_game = witness.wait_for_game_window_size(baseline_client)
    assert baseline_game == baseline_client, (
        f"BASELINE: before any gesture the game reports its drawable as {baseline_game} while "
        f"Windows reports a client area of {baseline_client} for hwnd {game.hwnd}. The two "
        "witnesses must already agree, or nothing measured after a resize distinguishes 'the "
        "game reacted' from 'the game reports something else entirely'."
    )
    assert not witness.game_is_fullscreen(), (
        "BASELINE: the game reports fullscreen before the test toggled anything; the tier "
        "launches with -windowed (conftest.LAUNCH_ARGS) so the fullscreen phase would be "
        "measuring a transition that had already happened"
    )

    # --- phase 1: RESIZE (and move) -------------------------------------------------------------
    set_client_rect(game.hwnd, RESIZE_ORIGIN, RESIZE_CLIENT_SIZE)
    wait_for(lambda: client_size(game.hwnd) == RESIZE_CLIENT_SIZE)
    assert_window_is_ours(game, "resize")

    observed_client = client_size(game.hwnd)
    assert observed_client == RESIZE_CLIENT_SIZE, (
        f"RESIZE (OS) FAILED: this test asked for a client area of {RESIZE_CLIENT_SIZE} and "
        f"Windows reports {observed_client} for hwnd {game.hwnd} after "
        f"{STATE_TIMEOUT_SECONDS}s. SetWindowPos was given the outer size computed from this "
        "window's own chrome, so the request cannot have been for the wrong number; the window "
        "is not the size it was told to be."
    )
    observed_frame = window_rect(game.hwnd)
    assert (observed_frame[0], observed_frame[1]) == RESIZE_ORIGIN, (
        f"RESIZE (OS) FAILED: the window frame's top-left is {observed_frame[:2]}, not the "
        f"{RESIZE_ORIGIN} this test moved it to. The move and the resize are one SetWindowPos, "
        "so a window at the old origin did not act on it."
    )

    resized_game = witness.wait_for_game_window_size(RESIZE_CLIENT_SIZE)
    assert resized_game == RESIZE_CLIENT_SIZE, (
        f"RESIZE (GAME) FAILED: Windows resized the window to {observed_client}, but the game "
        f"still reports its own drawable as {resized_game}. oolite.gameSettings.gameWindow is "
        "[gameView backingViewSize] (Universe.m:4539-4540), i.e. bounds.size, which is assigned "
        "in exactly ONE place in the tree - MyOpenGLView.m:514, inside -updateGLSize:. So this "
        "is a direct statement that -updateGLSize: never ran with the new size: the game never "
        "acted on SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED (MyOpenGLView+Input.m:633-636, :673-686), "
        "its glViewport and display_z are stale, and it is now rendering for a window that no "
        "longer exists. The OS rectangle alone would have passed."
    )
    assert resized_game != baseline_game, (
        f"RESIZE (GAME) FAILED: the game reports {resized_game}, which is what it reported "
        f"BEFORE the resize ({baseline_game}). The resize target must differ from the pinned "
        "size or this phase asserts nothing; check RESIZE_CLIENT_SIZE against "
        f"conftest.PINNED_CLIENT_SIZE ({PINNED_CLIENT_SIZE})."
    )

    # --- phase 2: MINIMISE ----------------------------------------------------------------------
    pre_minimise_frame = window_rect(game.hwnd)
    USER32.ShowWindow(game.hwnd, SW_MINIMIZE)
    wait_for(lambda: is_iconic(game.hwnd))
    assert_window_is_ours(game, "minimise")

    assert is_iconic(game.hwnd), (
        f"MINIMISE FAILED: {STATE_TIMEOUT_SECONDS}s after ShowWindow(SW_MINIMIZE), IsIconic is "
        f"false for hwnd {game.hwnd}. ShowWindow's BOOL return is the window's PREVIOUS "
        "visibility and not a success code, so the call 'succeeding' says nothing; IsIconic is "
        "the only authority, and it says the window was never minimised."
    )
    minimised_placement = window_placement(game.hwnd)
    assert minimised_placement.showCmd == SW_SHOWMINIMIZED, (
        f"MINIMISE FAILED: the window is iconic but GetWindowPlacement reports showCmd "
        f"{minimised_placement.showCmd}, not SW_SHOWMINIMIZED ({SW_SHOWMINIMIZED}). The shell "
        "and the window manager disagree about the window's state, which is not a state a real "
        "minimise can leave behind."
    )

    # --- phase 3: RESTORE -------------------------------------------------------------------------
    #
    # The strongest available witness for "back where it was" is Windows' own memory of the
    # restored rectangle, which GetWindowPlacement keeps in rcNormalPosition WHILE the window is
    # minimised. It is read here, before the restore, so the comparison afterwards is against the
    # OS's record and not only against a number this test wrote down.
    remembered = minimised_placement.rcNormalPosition
    USER32.ShowWindow(game.hwnd, SW_RESTORE)
    wait_for(lambda: not is_iconic(game.hwnd))
    assert_window_is_ours(game, "restore")

    assert not is_iconic(game.hwnd), (
        f"RESTORE FAILED: {STATE_TIMEOUT_SECONDS}s after ShowWindow(SW_RESTORE) the window is "
        f"still iconic (hwnd {game.hwnd}). The game is running with no visible window, which "
        "every other assertion in this tier would happily pass."
    )
    restored_placement = window_placement(game.hwnd)
    assert restored_placement.showCmd == SW_SHOWNORMAL, (
        f"RESTORE FAILED: showCmd is {restored_placement.showCmd}, not SW_SHOWNORMAL "
        f"({SW_SHOWNORMAL}); the window came back in some other state than the one it was in "
        "before the minimise."
    )
    restored_frame = window_rect(game.hwnd)
    assert restored_frame == pre_minimise_frame, (
        f"RESTORE FAILED: the window came back at {restored_frame} but was at "
        f"{pre_minimise_frame} immediately before the minimise. A restore that relocates or "
        "resizes the window has not restored it - and Windows' own record of where it should "
        f"go (rcNormalPosition) said "
        f"{(remembered.left, remembered.top, remembered.right, remembered.bottom)}."
    )
    assert (remembered.left, remembered.top, remembered.right, remembered.bottom) == (
        pre_minimise_frame
    ), (
        "RESTORE FAILED: while minimised, Windows' remembered restore rectangle was "
        f"{(remembered.left, remembered.top, remembered.right, remembered.bottom)}, not the "
        f"{pre_minimise_frame} the window occupied before the minimise. The window would come "
        "back somewhere else the moment anything else restored it."
    )

    # GL CONTEXT SURVIVAL, which is the reason G6 exists at all (docs/phases/0-gui-tier.md).
    # Two separate claims: the game is still STEPPING FRAMES (UNIVERSE's clock only advances
    # inside the run loop, OOJSClock.m) and it still knows how big its drawable is. A game whose
    # context died on the minimise typically survives as a process, which is exactly why
    # "proc.poll() is None" is not the check here.
    clock_before = witness.game_clock()
    deadline = time.time() + STATE_TIMEOUT_SECONDS
    clock_after = clock_before
    while clock_after - clock_before < FRAMES_AFTER_RESTORE_SECONDS and time.time() < deadline:
        time.sleep(0.25)
        clock_after = witness.game_clock()
    assert clock_after - clock_before >= FRAMES_AFTER_RESTORE_SECONDS, (
        f"GL SURVIVAL FAILED: after the restore the game's own clock advanced only "
        f"{clock_after - clock_before:.3f}s in {STATE_TIMEOUT_SECONDS}s of wall time "
        f"(clock.absoluteSeconds {clock_before} -> {clock_after}). UNIVERSE's clock only moves "
        "while the run loop steps frames, so the game has stopped rendering - the process is "
        "alive and answering the console, which is precisely the state a 'is it still running' "
        "check would call a pass."
    )
    survived_size = witness.wait_for_game_window_size(RESIZE_CLIENT_SIZE)
    assert survived_size == RESIZE_CLIENT_SIZE, (
        f"GL SURVIVAL FAILED: after the minimise/restore round trip the game reports its "
        f"drawable as {survived_size}, not the {RESIZE_CLIENT_SIZE} it reported before being "
        "minimised. The window came back at its old rectangle (asserted above), so the game and "
        "the window now disagree about the viewport."
    )

    # --- phase 4: FULLSCREEN, through the game's own F12 ------------------------------------------
    #
    # The GESTURE is a real key: MyOpenGLView+Input.m:469-473 is the only caller of
    # -toggleScreenMode in the tree, and it is the SDLK_F12 case. Driving it with SendInput's
    # scancode path (conftest.GameWindow.press_key) is what G2 measured as the only way this SDL3
    # build actually receives a key press.
    game.assert_focused()
    witness.assert_on_start_screen("before the fullscreen F12")
    game.press_key("f12")
    fullscreen_seen = witness.wait_for_game_fullscreen(True)
    assert fullscreen_seen, (
        "FULLSCREEN (GAME) FAILED: after F12 the game still reports "
        "oolite.gameSettings.gameWindow.fullScreen == false. That property is "
        "[[UNIVERSE gameController] inFullScreenMode] (Universe.m:4541) -> "
        "[gameView inFullScreenMode] -> the fullScreen ivar, and after start-up the only thing "
        "that assigns it is -setFullScreenMode: (MyOpenGLView.m:721-729), whose only runtime "
        "caller is -toggleScreenMode at the SDLK_F12 case (MyOpenGLView+Input.m:471). So the "
        "key never reached the game, or the toggle did not run."
    )

    # The second, independent witness for the same transition: the game LOGS the surface it
    # creates, and -initialiseGLWithSize: spells the mode in that line (MyOpenGLView.m:591-592).
    # No windowed path can write the word 'fullscreen' there. Only the text written AFTER this
    # phase began is searched, so a line from an earlier run or an earlier phase cannot vouch.
    fullscreen_line = wait_for(
        lambda: _find_surface_line(log_path, log_before_fullscreen_anchor, "fullscreen")
    )
    assert fullscreen_line, (
        "FULLSCREEN (GAME) FAILED: no 'Requested a new surface of W x H, fullscreen.' line was "
        f"written to {log_path} after offset {log_before_fullscreen_anchor} (where this phase "
        "started). -toggleScreenMode calls -initialiseGLWithSize: (MyOpenGLView.m:732-741), "
        "which logs that line at :591-592 with the mode spelled out, so its absence means the "
        "GL surface was never re-created - the flag flipped without the window following it."
    )

    assert_window_is_ours(game, "fullscreen")
    screen = monitor_rect(game.hwnd)
    fullscreen_frame = wait_for(lambda: _covers(window_rect(game.hwnd), screen) and
                                window_rect(game.hwnd)) or window_rect(game.hwnd)
    assert _covers(fullscreen_frame, screen), (
        f"FULLSCREEN (OS) FAILED: the game reports fullscreen but its window frame is "
        f"{fullscreen_frame}, which does not cover the monitor it is on ({screen}). Measured "
        "against THIS window's own monitor (MonitorFromWindow/GetMonitorInfoW), not against any "
        "assumed resolution. The game's flag is true and its surface was re-created, so a "
        "game-side check alone would have passed while the user still saw a small window."
    )

    # --- phase 5: BACK TO WINDOWED ----------------------------------------------------------------
    #
    # The size it must come back to is the one THIS TEST caused: -toggleScreenMode's windowed
    # branch calls -initialiseGLWithSize:currentWindowSize (MyOpenGLView.m:739), and
    # currentWindowSize was set by -saveWindowSize: when the game handled phase 1's resize
    # (MyOpenGLView+Input.m:683 -> MyOpenGLView.m:1314). So this assertion is a relationship
    # between two gestures of this test's own making, not a magic number.
    game.assert_focused()
    witness.assert_on_start_screen("before the windowed-return F12")
    game.press_key("f12")
    windowed_seen = witness.wait_for_game_fullscreen(False)
    assert not windowed_seen, (
        "WINDOWED RETURN FAILED: a second F12 left the game reporting fullScreen == true. "
        "-toggleScreenMode inverts the flag on every call, so the game is stuck fullscreen and "
        "a user could not get their desktop back."
    )
    assert_window_is_ours(game, "windowed return")
    back_client = wait_for(
        lambda: client_size(game.hwnd) == RESIZE_CLIENT_SIZE and client_size(game.hwnd)
    ) or client_size(game.hwnd)
    assert back_client == RESIZE_CLIENT_SIZE, (
        f"WINDOWED RETURN FAILED: leaving fullscreen left a client area of {back_client}, not "
        f"the {RESIZE_CLIENT_SIZE} this test resized the window to in phase 1. The windowed "
        "branch of -toggleScreenMode restores currentWindowSize (MyOpenGLView.m:739), which "
        "-saveWindowSize: set from the resize the game observed (MyOpenGLView+Input.m:683), so "
        "this is the game failing to remember the size it told us it had."
    )
    back_game = witness.wait_for_game_window_size(RESIZE_CLIENT_SIZE)
    assert back_game == RESIZE_CLIENT_SIZE, (
        f"WINDOWED RETURN FAILED: the window is {back_client} again but the game reports its "
        f"drawable as {back_game}; the two witnesses disagree after the fullscreen round trip."
    )

    # --- put the desktop back the way the tier hands it over ---------------------------------
    #
    # This test MOVED and RESIZED a window on a desktop five agents share. conftest._pin_window
    # is what every other test in this tier expects to find, so the window is put back to it
    # before the game is asked to exit - and the restore is CHECKED, because an unchecked
    # restore is the same class of claim this whole file exists to refuse.
    set_client_rect(game.hwnd, (0, 0), PINNED_CLIENT_SIZE)
    wait_for(lambda: client_size(game.hwnd) == PINNED_CLIENT_SIZE)
    assert client_size(game.hwnd) == PINNED_CLIENT_SIZE, (
        f"the window could not be put back to the tier's pinned size {PINNED_CLIENT_SIZE}; it "
        f"is {client_size(game.hwnd)}. It is killed with the process a moment later, so this is "
        "housekeeping rather than a lifecycle claim - but an uncheckable restore is not a "
        "restore."
    )

    # --- exit, and the tier's shared post-exit contract -------------------------------------
    launched_pid = game.proc.pid
    hwnd = game.close_window()
    try:
        returncode = game.proc.wait(timeout=EXIT_TIMEOUT_SECONDS)
    except Exception:
        pytest.fail(
            f"the game was still running {EXIT_TIMEOUT_SECONDS}s after WM_CLOSE was posted to "
            f"hwnd {hwnd} at the end of the lifecycle test"
        )
    assert returncode == 0, f"the game exited with {returncode}, not 0"
    assert_no_surviving_game_processes(launched_pid)
    assert_clean_exit(game)
    assert_shutdown_path_completed(game, EXPECTED_EXIT_CONTEXT)


def _covers(frame, screen):
    """Does ``frame`` cover every pixel of ``screen``? Both are (left, top, right, bottom)."""
    return (
        frame[0] <= screen[0]
        and frame[1] <= screen[1]
        and frame[2] >= screen[2]
        and frame[3] >= screen[3]
    )


def _find_surface_line(log_path, offset, mode):
    """The first 'Requested a new surface of W x H, <mode>.' line written after ``offset``.

    Reading from a byte offset recorded before the phase is what attributes the line to THIS
    gesture: the windowed surface line from start-up is in the same file, and a presence-only
    search would find it and call a fullscreen toggle proven.
    """
    try:
        with open(log_path, "r", encoding="utf-8", errors="replace") as handle:
            handle.seek(offset)
            text = handle.read()
    except OSError:
        return None
    match = re.search(r"Requested a new surface of (\d+) x (\d+), " + re.escape(mode), text)
    return match.group(0) if match else None


# --- offline guards: the observables are what this file claims they are --------------------------


def _tree_sources():
    for root, _dirs, files in os.walk(SRC_DIR):
        for name in sorted(files):
            if name.endswith((".m", ".h")):
                path = os.path.join(root, name)
                with open(path, "r", encoding="utf-8", errors="replace") as handle:
                    yield path, handle.read()


@pytest.mark.offline
def test_the_games_view_size_has_exactly_one_assignment_in_the_tree():
    """``bounds.size`` is assigned in exactly one place, so reading it back is attributable.

    This is G6's equivalent of G3's "SDL_EVENT_QUIT occurs once tree-wide" and G5's "each
    GUI_SCREEN_* is assigned in exactly one place". ``backingViewSize`` answers ``bounds.size``
    (MyOpenGLView.m:679-682); if some other code path could set it, the resized value coming
    back from the live game would no longer prove that -updateGLSize: ran.
    """
    sites = []
    for path, source in _tree_sources():
        for number, line in enumerate(source.splitlines(), 1):
            if re.search(r"\bbounds\.size\s*=(?!=)", line):
                sites.append(f"{os.path.relpath(path, SRC_DIR)}:{number}")
    assert len(sites) == 1, (
        "bounds.size - which is what [gameView backingViewSize] returns, and therefore what "
        "oolite.gameSettings.gameWindow reports - is assigned in "
        f"{len(sites)} places: {sites}. G6 reads that value back to prove -updateGLSize: ran "
        "with the size the OS gave the window; with more than one assignment the value is no "
        "longer attributable to the resize and this test's central witness is a proxy."
    )
    assert "SDL/MyOpenGLView.m" in sites[0].replace("\\", "/"), (
        f"the single assignment moved to {sites[0]}; check it is still inside -updateGLSize:"
    )


@pytest.mark.offline
def test_the_resize_reaches_the_game_only_through_the_window_system():
    """``resize_pending`` is set in exactly one place, and it is the SDL resize event's case.

    This is the route the RESIZE (GAME) assertion depends on: the game learns its new pixel size
    by being told, by the window system, that the size changed. If anything else could set the
    flag, a game-side size matching ours would no longer prove the OS resize was observed.
    """
    setters = []
    handler_case = []
    for path, source in _tree_sources():
        lines = source.splitlines()
        for number, line in enumerate(lines, 1):
            if re.search(r"\bresize_pending\s*=\s*true\b", line):
                setters.append((f"{os.path.relpath(path, SRC_DIR)}:{number}", lines, number))
    assert len(setters) == 1, (
        f"resize_pending is set true in {len(setters)} places: "
        f"{[site for site, _, _ in setters]}. G6 relies on the game reaching -updateGLSize: "
        "only via SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED."
    )
    site, lines, number = setters[0]
    preceding = "\n".join(lines[max(0, number - 6) : number])
    assert "SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED" in preceding, (
        f"the single resize_pending assignment at {site} is no longer inside the "
        "SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED case; the preceding lines are:\n" + preceding
    )
    handler_case.append(site)

    # And the flag is CONSUMED by a call to -updateGLSize:, which is the assignment above.
    consumers = [
        f"{os.path.relpath(path, SRC_DIR)}"
        for path, source in _tree_sources()
        if "updateGLSize" in source and "resize_pending" in source
    ]
    assert consumers, (
        "no file both tests resize_pending and calls -updateGLSize:; the chain from the window "
        "system's resize event to bounds.size is broken and this test's witness is stale"
    )


@pytest.mark.offline
def test_the_fullscreen_toggle_has_exactly_two_routes_and_g6_takes_only_the_key():
    """``-toggleScreenMode`` has exactly TWO callers, and the other one needs a screen G6 avoids.

    This guard was written expecting ONE caller and a real run of it falsified that, which is
    why it is spelled this way: the tree also reaches the toggle from
    PlayerEntityControls.m:3871, the Game Options screen's ``Display Style`` row. Both routes are
    named here, and BOTH halves of the attribution are asserted:

    * the key route is the ``SDLK_F12`` case (MyOpenGLView+Input.m:471), which is the gesture
      this file performs; and
    * the menu route is guarded by ``guiSelectedRow == GUI_ROW(GAME,DISPLAYSTYLE)`` and a select
      key press, so it can only run while the game is on GUI_SCREEN_GAMEOPTIONS.

    The launching test never leaves GUI_SCREEN_INTRO1 - it asserts that it is on the start
    screen immediately before each F12 (see ``test_the_launching_test_proves_it_is_on_the_start_
    screen_before_f12``), so the menu route is unreachable at the moment of the gesture and the
    fullscreen transition is attributable to the key. A THIRD caller would break that argument,
    and this test goes red if one appears.
    """
    callers = []
    for path, source in _tree_sources():
        for number, line in enumerate(source.splitlines(), 1):
            if re.search(r"\btoggleScreenMode\s*\]", line):
                callers.append((f"{os.path.relpath(path, SRC_DIR)}:{number}", line.strip()))
    assert callers, "nothing calls -toggleScreenMode any more; F12 would toggle nothing"
    assert len(callers) == 2, (
        f"-toggleScreenMode is called from {len(callers)} places: {callers}. G6 presses F12 and "
        "attributes the fullscreen transition to it, having proved the only OTHER route (the "
        "Game Options Display Style row) needs a screen this test never visits. A new caller "
        "must be shown to be unreachable from the start screen before this expectation is "
        "raised."
    )
    by_file = {site.split(":")[0].replace("\\", "/"): site for site, _ in callers}

    key_site = by_file.get("SDL/MyOpenGLView+Input.m")
    assert key_site, f"no -toggleScreenMode call in SDL/MyOpenGLView+Input.m; callers: {callers}"
    assert "SDLK_F12" in _source_window(key_site, before=4), (
        f"the key route to -toggleScreenMode ({key_site}) is no longer in the SDLK_F12 case; "
        "the lines before it are:\n" + _source_window(key_site, before=4)
    )

    menu_site = by_file.get("Core/Entities/PlayerEntityControls.m")
    assert menu_site, f"no -toggleScreenMode call in PlayerEntityControls.m; callers: {callers}"
    guard = _source_window(menu_site, before=3)
    assert "GUI_ROW(GAME,DISPLAYSTYLE)" in guard, (
        f"the menu route to -toggleScreenMode ({menu_site}) is no longer gated on the Game "
        "Options Display Style row, so it may now be reachable from the start screen and G6's "
        "F12 would no longer be the only possible cause of a fullscreen transition. The lines "
        "before it are:\n" + guard
    )


def _source_window(site, before):
    """The ``before`` source lines immediately preceding ``site`` (a ``path:line`` string)."""
    path, _, number = site.rpartition(":")
    with open(os.path.join(SRC_DIR, path), "r", encoding="utf-8", errors="replace") as handle:
        lines = handle.read().splitlines()
    return "\n".join(lines[max(0, int(number) - 1 - before) : int(number)])


@pytest.mark.offline
def test_the_launching_test_proves_it_is_on_the_start_screen_before_f12():
    """The runtime half of the F12 attribution, pinned by AST.

    The menu route to -toggleScreenMode is only reachable from GUI_SCREEN_GAMEOPTIONS, so the
    launching test must ESTABLISH that the game is on the start screen at the moment it presses
    F12 - otherwise "the game went fullscreen after F12" could in principle be the other route.
    Read off ast.Call nodes rather than by grep: a docstring naming gui_screen must not satisfy
    this (the substring-guard defect a sibling bead shipped).
    """
    with open(os.path.join(HERE, os.path.basename(__file__)), "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read())
    func = next(
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.FunctionDef) and node.name == "test_g6_window_lifecycle"
    )
    called = [
        node
        for node in ast.walk(func)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "assert_on_start_screen"
    ]
    presses = [
        node
        for node in ast.walk(func)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "press_key"
    ]
    assert presses, "the launching test no longer presses a key; F12 is the fullscreen gesture"
    assert len(called) >= len(presses), (
        f"the launching test presses a key {len(presses)} time(s) but calls "
        f"assert_on_start_screen() only {len(called)} time(s). Every F12 must be preceded by "
        "proof that the game is on GUI_SCREEN_INTRO1, or the Game Options Display Style row "
        "(PlayerEntityControls.m:3871) is an alternative explanation for the toggle."
    )


@pytest.mark.offline
def test_the_fullscreen_flag_is_only_assigned_by_the_toggle_at_runtime():
    """After start-up, ``fullScreen`` is assigned only by ``-setFullScreenMode:``.

    ``oolite.gameSettings.gameWindow.fullScreen`` is that ivar (Universe.m:4541 ->
    GameController+SDLFullScreen.m:92-95 -> MyOpenGLView.m:715-718). The other assignments are
    the ``-init`` default and the two command-line/-defaults reads, none of which can run while
    the game is on the start screen - so the value flipping mid-run is attributable to the
    toggle.
    """
    assignments = []
    for path, source in _tree_sources():
        for number, line in enumerate(source.splitlines(), 1):
            if re.search(r"\bfullScreen\s*=(?!=)", line) and "==" not in line:
                assignments.append((f"{os.path.relpath(path, SRC_DIR)}:{number}", line.strip()))
    assert assignments, "nothing assigns fullScreen; the observable does not exist"
    runtime = [
        site
        for site, line in assignments
        if "fullScreen = fsm" in line
    ]
    assert len(runtime) == 1, (
        f"expected exactly one setter-style assignment of fullScreen (-setFullScreenMode:), "
        f"found {runtime} among {[site for site, _ in assignments]}"
    )
    startup_only = [
        line
        for site, line in assignments
        if site not in runtime
    ]
    for line in startup_only:
        assert (
            "NO;" in line
            or "userDefaults" in line
            or "cmdline_arguments" in line
        ), (
            f"an assignment to fullScreen that is neither the setter nor a start-up read: "
            f"{line!r}. G6 attributes a mid-run change of this flag to the F12 toggle."
        )


@pytest.mark.offline
def test_the_fullscreen_flag_parse_accepts_the_form_the_game_really_sends():
    """The 0/1 spelling must be accepted, and an unrecognised answer must RAISE, not be False.

    This guard exists because the bug it covers actually happened on a real run:
    ``oolite.gameSettings.gameWindow.fullScreen`` is an ObjC BOOL boxed with
    ``+numberWithBool:``, so it arrives as ``0``/``1``, and a parse comparing against ``"true"``
    answered False for a game whose own log said "Requested a new surface of 5120 x 1392,
    fullscreen." A parse that reads anything unexpected as False makes the whole fullscreen
    phase unpassable, so the failure mode is pinned here rather than left to a live run to
    rediscover.
    """
    class _Canned(WindowWitness):
        def __init__(self, answer):
            self._answer = answer  # no socket: only the parse is under test

        def evaluate(self, expression, timeout=15):
            return self._answer

    assert _Canned("1").game_is_fullscreen() is True, "the game's real spelling must parse"
    assert _Canned("0").game_is_fullscreen() is False
    assert _Canned("true").game_is_fullscreen() is True, "a boolean spelling must still work"
    assert _Canned("false").game_is_fullscreen() is False
    assert _Canned(" 1 \n").game_is_fullscreen() is True, "whitespace must not defeat it"
    with pytest.raises(ScreenWitnessError) as caught:
        _Canned("undefined").game_is_fullscreen()
    assert "neither a boolean nor 0/1" in str(caught.value), (
        "an unrecognised answer must be reported, not silently read as 'not fullscreen' - that "
        "is exactly the shape that made the fullscreen assertion unpassable"
    )


@pytest.mark.offline
def test_the_surface_log_line_spells_the_mode():
    """The log witness must be a string the game really writes, with the mode in it.

    A typo here would make the fullscreen phase fail every healthy run and read as "fullscreen
    is broken" rather than "the test is looking for the wrong string".
    """
    view = os.path.join(SRC_DIR, "SDL", "MyOpenGLView.m")
    assert os.path.isfile(view), f"no MyOpenGLView.m at {view}"
    with open(view, "r", encoding="utf-8", errors="replace") as handle:
        source = handle.read()
    assert "Requested a new surface of %d x %d, %@." in source, (
        "the surface log line has been reworded; both this file's fullscreen witness and "
        "conftest.assert_splash_screen_is_off match on it"
    )
    assert '@"fullscreen" : @"windowed"' in source.replace("? ", "").replace(" :", " :"), (
        "the mode in the surface line is no longer spelled 'fullscreen'/'windowed'; the "
        "fullscreen witness would match nothing"
    )
    # And the windowed spelling must NOT be a substring of the fullscreen one, or a windowed
    # line would satisfy the fullscreen search.
    assert "windowed" not in "fullscreen", "the two mode words must be distinguishable"


@pytest.mark.offline
def test_a_windowed_surface_line_does_not_satisfy_the_fullscreen_search(tmp_path):
    """The log search is anchored AND mode-specific: neither alone would do.

    Two separate traps, both reachable: the start-up windowed line is in the same file (so a
    presence-only search finds it), and it sits BEFORE the offset this phase records (so an
    unanchored search would find a fullscreen line from an earlier phase too).
    """
    log = tmp_path / "Latest.log"
    log.write_text(
        "Opening log for Oolite version 1.93 at 2026-09-17 11:31:33 -0400.\n"
        "11:31:34.100 [display.initGL]: Requested a new surface of 960 x 720, windowed.\n",
        encoding="utf-8",
    )
    anchor = len(log.read_text(encoding="utf-8"))
    assert _find_surface_line(str(log), 0, "windowed"), "the windowed line must be findable at 0"
    assert _find_surface_line(str(log), 0, "fullscreen") is None, (
        "a windowed surface line satisfied the fullscreen search"
    )
    assert _find_surface_line(str(log), anchor, "windowed") is None, (
        "a line written BEFORE the anchor was found after it; the offset is not being used"
    )

    with open(str(log), "a", encoding="utf-8") as handle:
        handle.write(
            "11:31:52.900 [display.initGL]: Requested a new surface of 2560 x 1440, fullscreen.\n"
        )
    found = _find_surface_line(str(log), anchor, "fullscreen")
    assert found and "fullscreen" in found, (
        "the fullscreen line written after the anchor must be found"
    )


@pytest.mark.offline
def test_covers_is_a_real_containment_test():
    """The fullscreen geometry predicate, exercised directly on both sides of every edge.

    ``_covers`` is the whole of the FULLSCREEN (OS) claim, so a version that answered True for
    everything (or compared the wrong edges) would silently make that assertion unfalsifiable.
    """
    screen = (0, 0, 1920, 1080)
    assert _covers((0, 0, 1920, 1080), screen), "an exactly-covering frame must pass"
    assert _covers((-8, -8, 1928, 1088), screen), "an over-covering frame must pass"
    assert not _covers((1, 0, 1920, 1080), screen), "one pixel short on the left must fail"
    assert not _covers((0, 1, 1920, 1080), screen), "one pixel short on the top must fail"
    assert not _covers((0, 0, 1919, 1080), screen), "one pixel short on the right must fail"
    assert not _covers((0, 0, 1920, 1079), screen), "one pixel short on the bottom must fail"
    # A window pinned the way the tier pins it must not pass for a real monitor.
    assert not _covers((0, 0, PINNED_CLIENT_SIZE[0], PINNED_CLIENT_SIZE[1]), screen), (
        "the tier's pinned window would satisfy the fullscreen check"
    )
    # A monitor that is not at the origin (a second display) is handled too.
    right_hand = (1920, 0, 3840, 1080)
    assert _covers((1920, 0, 3840, 1080), right_hand)
    assert not _covers((0, 0, 1920, 1080), right_hand), (
        "a frame covering the PRIMARY monitor must not pass for a window on the second one"
    )


@pytest.mark.offline
def test_the_geometry_assertions_are_not_magic_numbers():
    """No size this test asserts may be one it did not itself set.

    Read off the AST rather than by eye: the launching test must compare against
    RESIZE_CLIENT_SIZE / RESIZE_ORIGIN / PINNED_CLIENT_SIZE and against values it measured, and
    must not contain a bare (width, height)-looking literal. A hard-coded 1024x768 would pass on
    the machine it was written on and flake on every other display.
    """
    with open(os.path.join(HERE, os.path.basename(__file__)), "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read())
    func = next(
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.FunctionDef) and node.name == "test_g6_window_lifecycle"
    )
    plausible_pixels = [
        node.value
        for node in ast.walk(func)
        if isinstance(node, ast.Constant) and isinstance(node.value, int) and node.value > 64
    ]
    assert not plausible_pixels, (
        "the launching test contains integer literal(s) large enough to be a pixel dimension: "
        f"{plausible_pixels}. Every geometry assertion must name RESIZE_CLIENT_SIZE, "
        "RESIZE_ORIGIN, PINNED_CLIENT_SIZE or a value read from the OS, so that it asserts a "
        "relationship this test caused rather than a resolution this machine happens to use."
    )
    assert RESIZE_CLIENT_SIZE != PINNED_CLIENT_SIZE, (
        "the resize target equals the size conftest._pin_window already applied, so the resize "
        "phase would assert something that was true before it ran"
    )
    assert RESIZE_ORIGIN != (0, 0), (
        "the move target is the origin the tier already pins the window to; the move would "
        "assert nothing"
    )


@pytest.mark.offline
def test_the_test_measures_its_own_window_at_every_phase():
    """``assert_window_is_ours`` must be CALLED, as a real call, in the launching test.

    Five agents share this desktop and conftest._pin_window parks every instance at (0,0) at the
    same size, so a sibling's window is indistinguishable by geometry alone. AST, never a
    substring: a docstring naming the helper must not hold this guard green (the defect a
    sibling bead shipped).
    """
    with open(os.path.join(HERE, os.path.basename(__file__)), "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read())
    func = next(
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.FunctionDef) and node.name == "test_g6_window_lifecycle"
    )
    calls = [
        node
        for node in ast.walk(func)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Name)
        and node.func.id == "assert_window_is_ours"
    ]
    assert len(calls) >= 5, (
        f"the launching test calls assert_window_is_ours() {len(calls)} times; every phase that "
        "measures geometry must re-check the window belongs to the pid this test launched, "
        "because a sibling agent's pinned window satisfies the same measurements"
    )
    # And the check itself must compare pids, not merely exist.
    guard = next(
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.FunctionDef) and node.name == "assert_window_is_ours"
    )
    compared = {
        ast.unparse(node) for node in ast.walk(guard) if isinstance(node, ast.Compare)
    }
    assert any("proc.pid" in text for text in compared), (
        f"assert_window_is_ours does not compare against game.proc.pid: {compared}"
    )


@pytest.mark.offline
def test_the_staged_app_is_private_and_the_shared_build_is_read_only():
    """The app_dir override must stage a private app and must never write the shared build.

    The resize makes the game write window_width/window_height, and the fullscreen toggle writes
    and synchronizes the ``fullscreen`` key. Against the shared build those land in the prefs
    file every other tier on this machine reads. AST: the fixture must call stage_app and
    unstage_app, and must not call rmtree (the staged tree is full of junctions INTO the real
    build, so a recursive delete would take the build with it).
    """
    with open(os.path.join(HERE, os.path.basename(__file__)), "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read())
    fixture = next(
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.FunctionDef) and node.name == "app_dir"
    )
    names = {
        node.func.id
        for node in ast.walk(fixture)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
    }
    attrs = {
        node.func.attr
        for node in ast.walk(fixture)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
    }
    assert "stage_app" in names, (
        "the app_dir override does not stage a private app; the game would write its window "
        "size and fullscreen flag into the SHARED build's prefs file"
    )
    assert "unstage_app" in names, (
        "the app_dir override does not call unstage_app; the staged tree's junctions must be "
        "removed as links"
    )
    assert "rmtree" not in names and "rmtree" not in attrs, (
        "the app_dir override calls rmtree on a tree full of junctions into the real build"
    )


@pytest.mark.offline
def test_g6_does_not_pretend_to_run_the_game_without_a_desktop():
    """The launching test must NOT be marked offline, and must take the game fixture.

    An ``offline`` G6 would be collected by the tier's clean-checkout command, pass with no game,
    and report that the window lifecycle had been verified on a machine with no build. It must
    also carry no skip marker of its own: OO_GUI_REQUIRE=1 turns the fixture's legitimate
    platform skip into a failure (conftest.require_gui_platform), and a decorator here would sit
    outside that mechanism (oo-7by1).
    """
    with open(os.path.join(HERE, os.path.basename(__file__)), "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read())
    func = next(
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.FunctionDef) and node.name == "test_g6_window_lifecycle"
    )
    assert "game" in [a.arg for a in func.args.args], "the launching test must take the fixture"
    for decorator in func.decorator_list:
        text = ast.unparse(decorator)
        assert "offline" not in text, (
            f"the launching test is marked offline; it would pass with no build. {text}"
        )
        assert "skip" not in text, (
            f"the launching test carries its own skip marker (oo-7by1). {text}"
        )
    calls = {
        node.func.attr
        for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
    }
    assert "importorskip" not in calls, (
        "no importorskip in this tier: a hard dependency must fail, not skip (oo-7by1)"
    )
