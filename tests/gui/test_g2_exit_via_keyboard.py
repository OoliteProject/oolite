"""G2 - exit the game from the start screen with the KEYBOARD: ``Down`` x5, then ``Enter``.

docs/phases/0-gui-tier.md G2: "Launch -> ``Down``x5 -> ``Enter``", covering "the keyboard path
independently of mouse - a separate SDL3 code path from G1".

Written the way test_g1_exit_via_mouse.py is written and kept SHORT the way
test_g3_exit_via_window_close.py is: the desktop lock, the readiness gate, DPI awareness, the
pinned window, the process-table survivor check and the G9 hygiene asserts are all conftest.py's
and are reused verbatim. This file launches nothing of its own. What it adds is the keyboard
navigation and the evidence that the keyboard is what did it.

THE EXIT CONTEXT CONVERGES WITH G1's. SAID PLAINLY.
---------------------------------------------------
G3's technique is to assert on an observable UNIQUELY attributable to the path under test - the
``@"SDL_QUIT event received"`` context string, unique among the tree's ``-exitAppWithContext:``
call sites. G2 has no such luck AT THE EXIT, and pretending otherwise would be the exact
dishonesty this tier exists to prevent:

    PlayerEntityControls.m:4979-4982
        else if (([gameView isDown:gvMouseDoubleClick] || [self checkKeyPress:n_key_gui_select])
                 && [gui selectedRow] == 6+row_zero)
        {
            [[UNIVERSE gameController] exitAppWithContext:@"Exit Game selected on start screen"];
        }

ONE expression, an ``||`` of the double-click and the select key, reaching ONE
``exitAppWithContext:``. G1 (mouse) and G2 (keyboard) therefore produce a byte-identical
``[exit.context]`` line. That string IS unique in the tree - verified by
``test_the_start_screen_exit_context_is_unique_in_the_tree`` - so asserting it proves the
START-SCREEN ` Exit Game ` ROW ran rather than one of the other exit sites, and it is asserted
here for that reason. It proves NOTHING about keyboard versus mouse, and this file does not
claim it does.

THE KEYBOARD-ONLY OBSERVABLE: WHERE THE SELECTION ENDED UP
-----------------------------------------------------------
The discriminator is upstream of the exit, in HOW THE SELECTION MOVED. This test never moves the
pointer and never presses a mouse button, so the only thing that can move the selection is the
arrow key: ``-[GuiDisplayGen setNextRow:]`` (GuiDisplayGen.m:517) is the game's ONLY relative
selection move, it has exactly TWO call sites in the whole tree (PlayerEntityControls.m:729 and
:749), both inside ``-handleGUIUpDownArrowKeys`` and both gated on ``checkKeyPress:`` of an arrow
key, while that same method's mouse branches (:765-:787) jump ABSOLUTELY to
``UNIVERSE->cursor_row``. All of that is pinned by a tree-wide grep in
``test_a_single_row_step_is_reachable_only_from_the_arrow_keys``.

HOW THE SELECTION IS OBSERVED, AND WHY NOT THE OBVIOUS WAY. ``-reportSelectedRow:``
(GuiDisplayGen.m:572) fires a ``guiSelectedRowChanged`` world-script event, and reading that over
the debug console was the first design. IT DOES NOT WORK, and the measurement is recorded here so
nobody spends the afternoon again: with the handler installed on ``console.script`` and
``typeof`` confirming it was a function, a MOUSE-CONFIRMED row change that demonstrably happened
(``guiScreen`` went to GUI_SCREEN_SHIPLIBRARY) produced an EMPTY trace. A hook that stays empty
through a change that certainly occurred is a dead instrument, and a test built on it would have
been a check that cannot fail.

What IS used is the instrument G5 relies on and which answered correctly throughout:
``guiScreen``. It works as a ROW PROBE because every start-screen row activates a DIFFERENT
screen (PlayerEntityControls.m:4945 ``int row_zero = 21``, :4950-4982):

    row 22 (1+row_zero) -> setGuiToScenarioScreen      => GUI_SCREEN_NEWGAME
    row 24 (3+row_zero) -> setGuiToIntroFirstGo:NO     => GUI_SCREEN_SHIPLIBRARY
    row 25 (4+row_zero) -> setGuiToGameOptionsScreen   => GUI_SCREEN_GAMEOPTIONS
    row 26 (5+row_zero) -> setGuiToOXZManager          => GUI_SCREEN_OXZMANAGER
    row 27 (6+row_zero) -> exitAppWithContext:@"Exit Game selected on start screen"

So "Down x N, then Enter, and the game arrives on the screen row (first+N) leads to" proves the
arrow keys walked exactly N rows. The test uses this TWICE: once as a CALIBRATION that ends on a
screen and is therefore recoverable (Down x2 -> Enter -> GUI_SCREEN_SHIPLIBRARY, proving a single
Down advances exactly one row), and once for real (Down x5 -> Enter -> the process exits). The
calibration is what makes the real press count meaningful rather than assumed: if a Down advanced
zero rows the calibration lands on GUI_SCREEN_NEWGAME, and if it auto-repeated it lands on
GUI_SCREEN_GAMEOPTIONS - both named, both fatal.

WHY THE KEYS ARE SENT WITH SendInput AND NOT pyautogui
-------------------------------------------------------
``game.press_key`` (conftest) sends a SCANCODE with ``KEYEVENTF_EXTENDEDKEY``. pyautogui's
Windows backend calls ``keybd_event(vk, 0, 0, 0)`` - no scancode, no extended bit - and Oolite's
SDL3 build dispatches BY SCANCODE, where the arrow cluster shares scancodes with the numeric
keypad. MEASURED: pyautogui ``down`` x2 then Enter landed on GUI_SCREEN_NEWGAME (zero advances);
the same gesture through ``press_key`` landed on GUI_SCREEN_SHIPLIBRARY (exactly two). Space and
Enter arrive either way, which is why G5's Space navigation never hit this.

ROW ADDRESSING
---------------
The start screen's rows are written down at the top of the file (``FIRST_SELECTABLE_ROW``,
``EXIT_GAME_ROW``, ``SHIP_LIBRARY_ROW`` and the exit context string), because the GUI is not
changed during the migration. The number of Down presses is the difference between the first
selectable row and the target row.

    python3 -m pytest oolite-dev/tests/gui/test_g2_exit_via_keyboard.py -x -q

Needs the desktop: a real window, unlocked and logged in (ADR-0017). It takes tools/gui-lock for
the duration, via the ``game`` fixture.
"""

import ast
import os
import plistlib
import re
import select
import socket
import struct
import tempfile
import time

import pytest

from conftest import (
    KEY_HOLD_SECONDS,
    assert_clean_exit,
    assert_no_surviving_game_processes,
    assert_shutdown_path_completed,
)

HERE = os.path.dirname(os.path.abspath(__file__))

# The start screen, the only screen this test navigates from. G5 pins that this identifier is
# assigned in exactly one place in the tree.
START_SCREEN = "GUI_SCREEN_INTRO1"
# Where a confirmed row 24 (3+row_zero, ``setGuiToIntroFirstGo:NO``) lands. The calibration's
# expected destination, and the only one that means "each Down advanced exactly one row".
CALIBRATION_SCREEN = "GUI_SCREEN_SHIPLIBRARY"
# Where a confirmed row 22 lands - i.e. what the calibration sees if the Downs did NOTHING and
# Enter fired on the row the menu starts on. Named so that failure reports its own cause.
NO_ADVANCE_SCREEN = "GUI_SCREEN_NEWGAME"
# ...and row 25, i.e. what an auto-repeating Down produces.
OVER_ADVANCE_SCREEN = "GUI_SCREEN_GAMEOPTIONS"

# How long the game is given to act on a confirmed row.
TRANSITION_TIMEOUT_SECONDS = 15
# The story's budget for the exit, the same one G1, G3 and G5 use.
EXIT_TIMEOUT_SECONDS = 10


# --- the start screen's rows ---------------------------------------------------------------------
#
# The GUI is not changed during the migration, so the menu is written down here instead of being
# read out of the game's source (PlayerEntity -setupStartScreenGui and PlayerEntityControls
# -pollDemoControls). The start screen has six selectable rows, 22 to 27, and selection begins on
# the first of them.
FIRST_SELECTABLE_ROW = 22
# ` Exit Game ` and the context string the game logs when it is confirmed.
EXIT_GAME_ROW = 27
EXPECTED_EXIT_CONTEXT = "Exit Game selected on start screen"
# The row whose confirmation lands on the ship library (``setGuiToIntroFirstGo:NO``).
SHIP_LIBRARY_ROW = 24
# Selection starts on the first selectable row, so reaching ` Exit Game ` costs exactly this many
# single-row steps: the story's "Down x5".
DOWN_PRESSES = EXIT_GAME_ROW - FIRST_SELECTABLE_ROW
# And the calibration's.
CALIBRATION_PRESSES = SHIP_LIBRARY_ROW - FIRST_SELECTABLE_ROW


# --- the screen witness (G5's instrument) -------------------------------------------------------
#
# Protocol constants, spelled as tests/component/console.py and G5 spell them.
PACKET_TYPE_KEY = "packet type"
MESSAGE_KEY = "message"
REQUEST_CONNECTION = "Request Connection"
APPROVE_CONNECTION = "Approve Connection"
PERFORM_COMMAND = "Perform Command"
CONSOLE_OUTPUT = "Console Output"
CONSOLE_IDENTITY_KEY = "console identity"


class ScreenWitnessError(AssertionError):
    """The console could not tell us what screen the game is on."""


class ScreenWitness:
    """Reads ``guiScreen`` out of the running game over the debug console.

    It is the GAME that dials US (OODebugSupport.m:67-80), so the socket must be listening BEFORE
    the game starts - hence the fixture below is built ahead of ``game``. The port is private to
    this session and handed over by writing debugConfig.plist into a throwaway resource root, the
    way tests/launch_snapshot.py and G5 both do; a fixed 8563 would collide with a component-tier
    run on this shared machine.
    """

    def __init__(self):
        self._server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._server.bind(("127.0.0.1", 0))
        self.port = self._server.getsockname()[1]
        self._server.listen(1)
        self._server.setblocking(False)
        self._conn = None
        self.config_root = self._write_config_root()

    def _write_config_root(self):
        root = tempfile.mkdtemp(prefix=f"oolite-g2-console-{self.port}-")
        config = os.path.join(root, "Config")
        os.makedirs(config, exist_ok=True)
        with open(os.path.join(config, "debugConfig.plist"), "wb") as handle:
            plistlib.dump(
                {"console-host": "127.0.0.1", "console-port": self.port},
                handle,
                fmt=plistlib.FMT_XML,
            )
        return root

    def accept(self, timeout=60):
        deadline = time.time() + timeout
        while time.time() < deadline:
            readable, _, _ = select.select([self._server], [], [], 1)
            if readable:
                self._conn, _ = self._server.accept()
                # An accepted socket INHERITS the listener's non-blocking mode on Windows, so
                # _recv_exactly would raise WinError 10035 instead of waiting for the rest of a
                # packet (oo-8yp). Every read is deadline-guarded by select(), so blocking is safe.
                self._conn.setblocking(True)
                self._handshake()
                return self
        raise ScreenWitnessError(
            f"the game never dialled the debug console on 127.0.0.1:{self.port} within "
            f"{timeout}s. G2 proves the ARROW KEYS moved the selection by reading the game's own "
            "guiScreen after a confirmed row, so without this connection it cannot tell a "
            "keyboard walk from a press that did nothing and must not pass. Check that "
            "Basic-debug.oxp is present in the build's AddOns directory."
        )

    def _handshake(self):
        packet = self._recv()
        if packet is None or packet.get(PACKET_TYPE_KEY) != REQUEST_CONNECTION:
            raise ScreenWitnessError(f"unexpected first console packet: {packet!r}")
        self._send({PACKET_TYPE_KEY: APPROVE_CONNECTION, CONSOLE_IDENTITY_KEY: "oolite G2"})

    def gui_screen(self, timeout=15):
        """The game's own ``guiScreen``, as a ``GUI_SCREEN_*`` string.

        PlayerEntityLegacyScriptEngine.m:920 answers this property with
        ``OOStringFromGUIScreenID(gui_screen)``, so the value is a direct read of the instance
        variable each screen's setter assigns - not a redraw, not a texture, not a guess.
        """
        # The console echoes the command text back before the answer, so a marker that appeared
        # literally in the command would match its own echo. Split in the source, joined at
        # runtime - the same trick console.py::evaluate and G5 use, for the same reason.
        head = f"@@g2-{os.getpid()}-{self.port}"
        tail = f"{int(time.time() * 1000) % 1000000}@@"
        marker = head + tail
        self._send({
            PACKET_TYPE_KEY: PERFORM_COMMAND,
            MESSAGE_KEY: (
                'debugConsole.consoleMessage("command-result", '
                f'"{head}" + "{tail}" + String(guiScreen) + "{head}" + "{tail}");'
            ),
        })
        deadline = time.time() + timeout
        while time.time() < deadline:
            readable, _, _ = select.select([self._conn], [], [], 1)
            if not readable:
                continue
            packet = self._recv()
            if packet is None:
                raise ScreenWitnessError("the console connection closed mid-query")
            if packet.get(PACKET_TYPE_KEY) != CONSOLE_OUTPUT:
                continue
            text = str(packet.get(MESSAGE_KEY, ""))
            if text.count(marker) >= 2:
                return text.split(marker)[1]
        raise ScreenWitnessError(f"no answer to guiScreen within {timeout}s")

    def await_screen(self, expected, timeout=TRANSITION_TIMEOUT_SECONDS):
        """Poll until ``guiScreen`` is ``expected``; return the last value seen either way."""
        deadline = time.time() + timeout
        seen = self.gui_screen()
        while seen != expected and time.time() < deadline:
            time.sleep(0.4)
            seen = self.gui_screen()
        return seen

    def close(self):
        import shutil

        for sock in (self._conn, self._server):
            try:
                if sock is not None:
                    sock.close()
            except OSError:
                pass
        shutil.rmtree(self.config_root, ignore_errors=True)

    # --- framing ------------------------------------------------------------------------------

    def _send(self, packet):
        data = plistlib.dumps(packet, fmt=plistlib.FMT_XML)
        self._conn.sendall(struct.pack(">I", len(data)) + data)

    def _recv_exactly(self, count):
        buffer = b""
        while len(buffer) < count:
            chunk = self._conn.recv(count - len(buffer))
            if not chunk:
                return None
            buffer += chunk
        return buffer

    def _recv(self):
        header = self._recv_exactly(4)
        if header is None:
            return None
        body = self._recv_exactly(struct.unpack(">I", header)[0])
        return plistlib.loads(body) if body else None


@pytest.fixture
def screen_witness():
    """Listen for the game's console connection, and tell the game where to dial.

    Named FIRST in the test's signature so pytest builds it BEFORE ``game``: the game dials out
    during startup, so a socket that starts listening afterwards is never connected to. The
    environment variable is set here rather than in a launcher because ``GameWindow._env`` copies
    ``os.environ``, which is how this file adds a resource root without adding a launcher.
    """
    witness = ScreenWitness()
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


def walk_down(game, presses):
    """Press ``Down`` ``presses`` times, discretely. Returns the rows aimed at, for messages."""
    for _ in range(presses):
        game.press_key("down")
    return list(range(FIRST_SELECTABLE_ROW + 1, FIRST_SELECTABLE_ROW + presses + 1))


# --- the test -----------------------------------------------------------------------------------


def test_g2_exit_via_keyboard(screen_witness, game):
    """Calibrate the arrow key, then walk to ` Exit Game ` and press Enter.

    The pointer is never moved and no button is ever pressed: every input is a key.

    1. CALIBRATION. From the start screen, ``Down`` x CALIBRATION_PRESSES then ``Enter`` must
       arrive at the Ship Library. That screen is reachable ONLY from the row that many steps
       down, so arriving there is evidence each Down advanced exactly one row - and the two ways
       it can go wrong are named and reported separately: landing on the scenario screen is the
       no-advance case, landing on Game Options is the over-advance case. Each reports what was
       OBSERVED and lists candidate causes rather than naming one. ``Space`` returns to the start
       screen, which also re-selects the first row (``setupStartScreenGui`` does
       ``setSelectedRow:initialRow``), so the real walk starts from a known position.
    2. THE WALK. ``Down`` x DOWN_PRESSES, still on the start screen afterwards, because
       navigating is not activating.
    3. ``Enter`` exits within the budget, with status 0.
    4. Nothing of ours survives, the G9 hygiene evidence holds, and the shutdown trace names the
       START-SCREEN exit context (shared with G1's mouse path by construction - see this module's
       docstring - so it is proof of WHICH ROW ran, not of which device ran it).
    """
    witness = screen_witness.accept()
    assert game.proc.poll() is None, "the game exited before the test could press anything"
    # Synthetic key input is delivered to the FOCUSED window, so this is the precondition for
    # every press below. assert_focused() self-heals a transiently stolen foreground (oo-0p8f).
    game.assert_focused()

    screen = witness.gui_screen()
    assert screen == START_SCREEN, (
        f"the game is on {screen}, not {START_SCREEN}, so the rows derived from "
        "-setupStartScreenGui do not describe what is on the screen and pressing Down would "
        "navigate an unknown menu"
    )

    # 1. CALIBRATION: prove one Down == one row, using a screen we can come back from.
    walk_down(game, CALIBRATION_PRESSES)
    game.press_key("enter")
    seen = witness.await_screen(CALIBRATION_SCREEN)
    if seen == NO_ADVANCE_SCREEN:
        pytest.fail(
            f"CALIBRATION FAILED: after {CALIBRATION_PRESSES} Down press(es) and Enter the game "
            f"is on {seen}, which is what row {FIRST_SELECTABLE_ROW} activates - the row the "
            "menu STARTS on. OBSERVED: the Enter arrived and the selection did not move. The "
            "cause is NOT determined by this test; the candidates, in the order they are worth "
            "checking, are: (a) the Down presses never reached the game at all; (b) they reached "
            "it without KEYEVENTF_EXTENDEDKEY, which a build that dispatches by scancode could "
            "receive as numeric-keypad keys rather than arrows (see GameWindow.press_key); "
            f"(c) the hold ({KEY_HOLD_SECONDS}s) was too short for the per-frame poll to "
            "sample the key down, or long enough to outlive KEY_REPEAT_INTERVAL and be "
            "swallowed as a repeat; (d) the start menu was renumbered, so the derived rows no "
            "longer describe it."
        )
    if seen == OVER_ADVANCE_SCREEN:
        pytest.fail(
            f"CALIBRATION FAILED: after {CALIBRATION_PRESSES} Down press(es) and Enter the game "
            f"is on {seen}, one row PAST {CALIBRATION_SCREEN}. OBSERVED: the selection moved one "
            "row too far. The cause is NOT determined by this test; the candidates are: (a) one "
            "press auto-repeated - -handleGUIUpDownArrowKeys (PlayerEntityControls.m:725-742) "
            f"advances again once a held key outlives KEY_REPEAT_INTERVAL, and the hold is "
            f"{KEY_HOLD_SECONDS}s; (b) the release gap was too short, so a press was counted as a "
            "repeat of the previous one; (c) the start menu was renumbered, so the derived rows "
            "no longer describe it - which looks identical from here."
        )
    assert seen == CALIBRATION_SCREEN, (
        f"CALIBRATION FAILED: after {CALIBRATION_PRESSES} Down press(es) and Enter the game is "
        f"on {seen}, not {CALIBRATION_SCREEN} (row {SHIP_LIBRARY_ROW}). Until one Down is known "
        "to be one row, the five presses below prove nothing about where the selection ended up."
    )

    # Back to the start screen. Space is the Ship Library's own exit (PlayerEntityControls.m:
    # 5031-5035) and -setGuiToIntroFirstGo:YES rebuilds the menu with the first row selected.
    game.press_key("space")
    seen = witness.await_screen(START_SCREEN)
    assert seen == START_SCREEN, (
        f"Space did not return the game from {CALIBRATION_SCREEN} to {START_SCREEN} (it is on "
        f"{seen}), so the real walk below would start from an unknown selection"
    )

    # 2. THE WALK: to ` Exit Game `. DOWN_PRESSES is the row difference, not a typed count.
    walk_down(game, DOWN_PRESSES)
    assert game.proc.poll() is None, (
        f"the game exited during navigation, before Enter was pressed. {DOWN_PRESSES} Down "
        "presses are supposed to move the selection and nothing else."
    )
    screen = witness.gui_screen()
    assert screen == START_SCREEN, (
        f"navigating left the game on {screen}; Down is supposed to move the selection within "
        f"{START_SCREEN}, not change screen"
    )

    # 3. Enter. The start-screen dispatcher activates the selected row on
    #    ``[self checkKeyPress:n_key_gui_select]``, which is what Enter is bound to.
    game.press_key("enter")
    try:
        returncode = game.proc.wait(timeout=EXIT_TIMEOUT_SECONDS)
    except Exception:
        pytest.fail(
            f"the game was still running {EXIT_TIMEOUT_SECONDS}s after Enter was pressed with "
            f"row {EXIT_GAME_ROW} (` Exit Game `) expected to be selected - {DOWN_PRESSES} Down "
            f"presses below a calibrated start. OBSERVED: the process did not exit within the "
            f"budget, and it was still on {START_SCREEN} immediately before Enter. The cause is "
            "NOT determined by this test; the candidates are: (a) the Enter never reached the "
            "game; (b) the selection was not on ` Exit Game ` despite the calibration, e.g. one "
            "of the Down presses was dropped or repeated; (c) the shutdown started but took "
            f"longer than {EXIT_TIMEOUT_SECONDS}s, which the Latest.log in the run directory "
            "would show."
        )
    assert returncode == 0, f"the game exited with {returncode}, not 0"

    # 4. No orphaned process. Asked of the OS process table, not of proc.poll(): wait() above has
    #    already reaped and stored that returncode, so re-reading it is true by construction
    #    (oo-5rsa). Scoped to the tree we launched so a concurrent sibling's oolite.exe is not
    #    mistaken for our leak.
    assert_no_surviving_game_processes(game.proc.pid)

    # 5. G9 hygiene: no dump, no ERROR, a defaults file THIS run wrote and which re-parses. The
    #    fixture is passed rather than a directory so the launch-time mark travels with it.
    assert_clean_exit(game)

    # 6. The shutdown ran to its last line, and it ran for the START-SCREEN ` Exit Game ` row
    #    rather than for any of the other exit sites in the tree.
    assert_shutdown_path_completed(game, expected_context=EXPECTED_EXIT_CONTEXT)


# --- offline guards on the harness ----------------------------------------------------------------


@pytest.mark.offline
def test_the_arrow_keys_are_sent_with_the_extended_scancode_flag():
    """The mechanism G2 depends on, pinned where a future edit would notice.

    WHY THE FLAG IS SENT, stated as rationale and not as a measurement: press_key delivers arrows
    by SCANCODE, and the arrow cluster shares its scancodes with the numeric keypad - the extended
    bit is the only thing in the INPUT structure that distinguishes them. This file therefore sets
    it, and pins that it is still set. What is NOT claimed here is that dropping the flag has been
    observed to break this build: the arrow delivery was reworked several times during authoring
    and the only mechanism measured end-to-end is the one below. The risk being guarded is that a
    future edit drops the flag, every assertion in this file stays intact, and the resulting
    failure reads as a game bug rather than as a harness regression.
    """
    import conftest

    assert conftest.KEYEVENTF_SCANCODE == 0x0008
    assert conftest.KEYEVENTF_EXTENDEDKEY == 0x0001
    assert conftest.VK_CODES["down"] == 0x28, "VK_DOWN is 0x28 in winuser.h"
    assert conftest.VK_CODES["down"] in conftest.EXTENDED_VK_CODES, (
        "VK_DOWN is not in EXTENDED_VK_CODES, so press_key would send its scancode without "
        "KEYEVENTF_EXTENDEDKEY - the one bit that tells an arrow apart from numpad-2 for a "
        "consumer that dispatches by scancode"
    )
    for arrow in ("up", "down", "left", "right"):
        assert conftest.VK_CODES[arrow] in conftest.EXTENDED_VK_CODES, (
            f"the {arrow} arrow is not declared extended"
        )
    # Enter and Space are NOT extended, and must not be sent as though they were.
    for plain in ("enter", "space"):
        assert conftest.VK_CODES[plain] not in conftest.EXTENDED_VK_CODES
    # The declaration the call depends on (test_win32_declarations.py enforces the rest).
    assert "user32.SendInput" in conftest.WIN32_SIGNATURES
    assert conftest.WIN32_SIGNATURES["user32.SendInput"][1][1] == "LPINPUT", (
        "SendInput's second parameter must be declared as a pointer to the real INPUT structure"
    )


@pytest.mark.offline
def test_g2_presses_keys_and_never_touches_the_mouse():
    """THE ANTI-DECAY GUARD: G2 must remain a KEYBOARD test.

    Read from this file's own AST, not its text, so a docstring or a comment cannot hold it green
    (the sibling-bead defect G5 documents). A future edit that reached ` Exit Game ` with
    ``select_row``/``confirm_row`` - or that killed the process instead of pressing Enter - would
    leave every assertion in the launching test passing while the keyboard path could be deleted
    outright without anything going red.
    """
    with open(os.path.join(HERE, "test_g2_exit_via_keyboard.py"), "r", encoding="utf-8") as h:
        tree = ast.parse(h.read())
    functions = {node.name: node for node in tree.body if isinstance(node, ast.FunctionDef)}
    assert "test_g2_exit_via_keyboard" in functions, (
        "the G2 test function has been renamed; this guard must be renamed with it"
    )
    reachable = [functions["test_g2_exit_via_keyboard"]]
    assert "walk_down" in functions, "walk_down is gone; G2's key presses are not where they were"
    reachable.append(functions["walk_down"])

    attribute_calls, name_calls = set(), set()
    for func in reachable:
        for node in ast.walk(func):
            if not isinstance(node, ast.Call):
                continue
            if isinstance(node.func, ast.Attribute):
                attribute_calls.add(node.func.attr)
            elif isinstance(node.func, ast.Name):
                name_calls.add(node.func.id)

    assert "press_key" in attribute_calls, (
        "G2 no longer presses keys with game.press_key(); it is supposed to exercise the "
        "keyboard path, which is the only thing it covers that G1 does not"
    )
    for forbidden in ("select_row", "confirm_row", "click", "doubleClick", "moveTo", "mouseDown"):
        assert forbidden not in attribute_calls, (
            f"G2 calls {forbidden}(); that is G1's mouse path, and a G2 that uses it proves "
            "nothing about the keyboard"
        )
    for forbidden in ("terminate", "kill", "send_signal", "close_window"):
        assert forbidden not in attribute_calls, (
            f"G2 calls {forbidden}(); killing or closing the game proves the OS can end a "
            "process, not that Enter on ` Exit Game ` exits it cleanly"
        )
    # And the post-exit hygiene the tier requires of every launching test (G9's meta-guard) must
    # be present as real calls.
    for helper in ("assert_no_surviving_game_processes", "assert_clean_exit"):
        assert helper in name_calls, f"G2 never calls {helper}()"
