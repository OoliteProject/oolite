"""G5 - screen round-trips: Ship Library, Game Options, Expansion Manager.

docs/phases/0-gui-tier.md G5: "Enter and leave each of: Ship Library (row 24, exit with ``Space``),
Game Options (row 25, exit via its ``Back`` row), Expansion Manager (row 26). Assert the start
screen is reachable again each time." The bug class is a screen that crashes on entry, and the
secondary claim is the per-screen back semantics, which are deliberately inconsistent and are
exactly the kind of thing a rewrite silently breaks.

Written the way test_g3_exit_via_window_close.py is written: SHORT, and reusing conftest.py
wholesale. The desktop lock, the readiness gate, DPI awareness, the pinned window, the row ->
screen-point maths, the process-table survivor check and the G9 hygiene assert are all G1's and
are not repeated here. This file adds the two things that are new: a per-screen OBSERVABLE, and
the navigation that round-trips each screen.

WHY THE OBSERVABLE IS ``guiScreen`` AND NOT THE LOG
--------------------------------------------------
The central risk for G5 is that "we navigated to a screen" quietly decays into "we pressed a key
and nothing crashed". A test built that way passes with every one of the three screen transitions
broken, because the only thing it ever checks is that the process is still alive.

G1 and G3 can read their evidence out of ``Latest.log`` because shutdown is a LOGGED event
(``exit.context`` is enabled by default in Resources/Config/logcontrol.plist:156). Entering a GUI
screen is not. Measured on this build, with the private staged app and every log class forced on:
confirming row 24, pressing Space, and confirming row 25 added ZERO attributable lines to
Latest.log - the only per-transition traces at default settings are ``universe.profile.*`` frame
noise and, for the ship library alone, an incidental ``plist.information`` line for
shiplibrary.plist which is neither enabled by default nor produced by the other two screens. There
is no honest log string for Game Options or the Expansion Manager, so a log-based G5 could only
ever have been a proxy.

So this file asks the GAME what screen it is on, over the debug console, exactly as the component
tier does (tests/component/console.py) - ``guiScreen`` is
``PlayerEntityLegacyScriptEngine.m:920`` -> ``OOStringFromGUIScreenID(gui_screen)``, i.e. a direct
read of the very instance variable each screen's setter assigns.

UNIQUENESS OF EACH SCREEN'S OBSERVABLE (the tree-wide grep)
-----------------------------------------------------------
``gui_screen`` is assigned the three values this file asserts on in EXACTLY ONE PLACE EACH in the
whole source tree - verified by grep, and pinned by
``test_each_screens_observable_is_assigned_in_exactly_one_place`` so it cannot rot:

* ``GUI_SCREEN_SHIPLIBRARY``  - PlayerEntity.m:10070, in ``-setGuiToIntroFirstGo:``
* ``GUI_SCREEN_GAMEOPTIONS``  - PlayerEntity.m:8855, in ``-setGuiToGameOptionsScreen``
* ``GUI_SCREEN_OXZMANAGER``   - PlayerEntity.m:10098, in ``-setGuiToOXZManager``

Reading ``GUI_SCREEN_OXZMANAGER`` back from the live game therefore proves that line 10098 ran in
THIS process, which is the same class of evidence the reviewer accepted for SDL_EVENT_QUIT's
context string in G3 - and it is attributable to that screen and to no other.

EXPANSION MANAGER AND THE NETWORK
---------------------------------
Opening the screen is in scope; expansion CONTENT is not, and this file never reads, downloads or
installs any. ``-setGuiToOXZManager`` (PlayerEntity.m:10094-10107) builds the screen from
``OOOXZManager``'s already-constructed state and fetches NOTHING: with no manifest cache the
manager sits in ``OXZ_STATE_NODATA`` and merely OFFERS a "download list" row
(OOOXZManager.m:1180-1190). Only activating that row would touch the network, and this test never
selects it - it confirms row 27, ``_EXIT`` (OOOXZManager.m:114, :1407), which calls
``cancelUpdate`` and returns to the start screen. So G5 is hermetic: it passes with the machine
offline, and no network state can change its result.

    python3 -m pytest upstream/oolite/tests/gui/test_g5_screen_round_trips.py -x -q

Needs the desktop: a real window, unlocked and logged in (ADR-0017). It takes tools/gui-lock for
the duration, via the ``game`` fixture - this file launches nothing of its own.

HELPERS LIVE HERE, NOT IN conftest.py, ON PURPOSE. G4 is being written concurrently against the
same tier; a shared helper added to conftest.py by both beads is a guaranteed merge conflict, and
nothing below is needed by any other test.
"""

import ast
import os
import plistlib
import re
import select
import socket
import struct
import sys
import tempfile
import time

import pytest

from conftest import (
    assert_clean_exit,
    assert_no_surviving_game_processes,
)

HERE = os.path.dirname(os.path.abspath(__file__))
OOLITE_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC_DIR = os.path.join(OOLITE_ROOT, "src")
TESTS_DIR = os.path.abspath(os.path.join(HERE, ".."))
if TESTS_DIR not in sys.path:
    sys.path.insert(0, TESTS_DIR)

# Sources are named by STEM: the migration renames .m -> .mm -> .cpp (source_paths.py, oo-7j3t).
from source_paths import iter_source_files  # noqa: E402

# --- the start screen's rows (PlayerEntity.m:9913-9955, ``initialRow = 22``) --------------------
SHIP_LIBRARY_ROW = 24
GAME_OPTIONS_ROW = 25
EXPANSION_MANAGER_ROW = 26
EXIT_GAME_ROW = 27

# The Game Options ``Back`` row. GUI_ROW(GAME,BACK) expands through a chain of #ifs
# (PlayerEntity.h:52, :178-210) whose value depends on OOLITE_SPEECH_SYNTH / OO_RESOLUTION_OPTION /
# NEW_PLANETS, so it is not a constant this file may compute. MEASURED against this build by
# confirming each addressable row from the bottom up and reading guiScreen back: rows 21-26 left
# guiScreen at GUI_SCREEN_GAMEOPTIONS, row 20 returned it to GUI_SCREEN_INTRO1. The test does NOT
# trust this number blindly - a wrong row simply fails the return assertion, by name.
GAME_OPTIONS_BACK_ROW = 20

# OOOXZManager.m:114 - ``OXZ_GUI_ROW_EXIT = 27``, the manager's own "exit" row. Its handler
# (:1407-1420) calls -cancelUpdate and [PLAYER setGuiToIntroFirstGo:YES]. Nothing here downloads.
EXPANSION_MANAGER_EXIT_ROW = 27

# The screen the tier starts on and returns to. PlayerEntity.m:10070 - ``setGuiToIntroFirstGo:YES``
# leaves gui_screen at GUI_SCREEN_INTRO1.
START_SCREEN = "GUI_SCREEN_INTRO1"

# Space is a KEY-DOWN-then-KEY-UP the game must sample inside one frame of pollDemoControls
# (PlayerEntityControls.m:5031-5035 tests ``[gameView isDown:' ']``). pyautogui.press() holds the
# key for ~0 seconds and was measured MISSING the sample entirely: guiScreen stayed at
# GUI_SCREEN_SHIPLIBRARY. A 0.15s hold is sampled reliably and is what this file uses.
KEY_HOLD_SECONDS = 0.15

# How long the game is given to act on a confirmed row or a key press. The transition happens in
# the frame after the input is sampled; this is generous so a busy machine is not a flake.
TRANSITION_TIMEOUT_SECONDS = 15

# The story's budget for ` Exit Game `, the same one G1 and G3 use.
EXIT_TIMEOUT_SECONDS = 10


# --- the debug-console peek --------------------------------------------------------------------
#
# Protocol constants, spelled the same way tests/component/console.py spells them.
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
    the game starts - hence the fixture below is instantiated ahead of ``game``. The port is
    private to this session and is handed to the game by writing debugConfig.plist into a
    throwaway resource root, which is what tests/launch_snapshot.py::_console_config_dir already
    does; a fixed 8563 would collide with a component-tier run on this shared machine.
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
        """A resource root whose only content is debugConfig.plist naming OUR port."""
        root = tempfile.mkdtemp(prefix=f"oolite-g5-console-{self.port}-")
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
                # On Windows an accepted socket INHERITS the listener's non-blocking mode, so
                # _recv_exactly's recv() raises WinError 10035 instead of waiting for the rest
                # of a packet. Every read below is already deadline-guarded by select(), so the
                # accepted connection is put back into blocking mode explicitly.
                self._conn.setblocking(True)
                self._handshake()
                return self
        raise ScreenWitnessError(
            f"the game never dialled the debug console on 127.0.0.1:{self.port} within "
            f"{timeout}s. G5 reads the screen out of the running game rather than guessing from "
            "the log, so without this connection the test cannot prove ARRIVAL at any screen and "
            "must not pass. Check that the debug support resource bundle shipped with the "
            "build is present in its add-on directory."
        )

    def _handshake(self):
        packet = self._recv()
        if packet is None or packet.get(PACKET_TYPE_KEY) != REQUEST_CONNECTION:
            raise ScreenWitnessError(f"unexpected first console packet: {packet!r}")
        self._send({PACKET_TYPE_KEY: APPROVE_CONNECTION, CONSOLE_IDENTITY_KEY: "oolite G5"})

    def gui_screen(self, timeout=15):
        """The game's own ``guiScreen``, as a ``GUI_SCREEN_*`` string.

        PlayerEntityLegacyScriptEngine.m:920 answers this property with
        ``OOStringFromGUIScreenID(gui_screen)``, so the value is a direct read of the instance
        variable each screen's setter assigns - not a redraw, not a texture, not a guess.
        """
        # The console echoes the command text back before the answer, so a marker that appears
        # literally in the command matches the echo. Split in the source, joined at runtime -
        # the same trick console.py::evaluate uses and for the same reason.
        head = f"@@g5-{os.getpid()}-{self.port}"
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
            time.sleep(0.5)
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
    ``os.environ`` - that is how this file adds a resource root without adding a launcher.
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


# --- the round trips ---------------------------------------------------------------------------
#
# ``(name, screen, enter, leave)``. ``enter``/``leave`` take the GameWindow.
def _confirm(row):
    return lambda game: game.confirm_row(row)


def _hold_key(key):
    def press(game):
        import pyautogui

        game.assert_focused()
        pyautogui.keyDown(key)
        time.sleep(KEY_HOLD_SECONDS)
        pyautogui.keyUp(key)

    return press


ROUND_TRIPS = (
    (
        "Ship Library",
        "GUI_SCREEN_SHIPLIBRARY",
        _confirm(SHIP_LIBRARY_ROW),
        _hold_key("space"),  # PlayerEntityControls.m:5031-5035
    ),
    (
        "Game Options",
        "GUI_SCREEN_GAMEOPTIONS",
        _confirm(GAME_OPTIONS_ROW),
        _confirm(GAME_OPTIONS_BACK_ROW),  # PlayerEntityControls.m:3888-3892
    ),
    (
        "Expansion Manager",
        "GUI_SCREEN_OXZMANAGER",
        _confirm(EXPANSION_MANAGER_ROW),
        _confirm(EXPANSION_MANAGER_EXIT_ROW),  # OOOXZManager.m:1407-1420
    ),
)


def test_g5_screen_round_trips(screen_witness, game):
    """Enter and leave each of the three screens, proving BOTH halves for each one.

    For every screen this asserts, in order:

    1. the game is on the START screen before the trip (re-verified each time, so a trip that
       silently left the game somewhere else fails at the NEXT screen rather than passing);
    2. after the entry gesture, ``guiScreen`` is that screen's OWN identifier - the observable
       assigned in exactly one place in the tree (see this module's docstring);
    3. after the leave gesture, ``guiScreen`` is the start screen again.

    Every failure NAMES the screen and says which half of the round trip failed, because "G5
    failed" is useless when three screens are in play.
    """
    witness = screen_witness.accept()

    for name, screen, enter, leave in ROUND_TRIPS:
        seen = witness.await_screen(START_SCREEN)
        assert seen == START_SCREEN, (
            f"before the {name} round trip the game was on {seen}, not {START_SCREEN}. The "
            "previous round trip did not return to the start screen, so this trip would be "
            "measured from the wrong place."
        )

        enter(game)
        seen = witness.await_screen(screen)
        assert seen == screen, (
            f"ARRIVAL FAILED for {name}: after the entry gesture the game reports guiScreen "
            f"{seen}, not {screen}. {screen} is assigned in exactly one place in the source "
            "tree, so this is a direct statement that the screen's setter never ran - the "
            "screen was not entered."
        )

        leave(game)
        seen = witness.await_screen(START_SCREEN)
        assert seen == START_SCREEN, (
            f"RETURN FAILED for {name}: after the leave gesture the game reports guiScreen "
            f"{seen}, not {START_SCREEN}. The game entered {name} and did not come back, so "
            "that screen's back semantics are broken and the start screen is no longer "
            "reachable."
        )

    # The game is usable after all three trips: it still answers the menu. Exiting through
    # ` Exit Game ` is the proof - a game left in a wedged GUI state cannot take this path.
    seen = witness.await_screen(START_SCREEN)
    assert seen == START_SCREEN, f"after all three round trips the game is on {seen}"
    game.select_row(EXIT_GAME_ROW)
    game.confirm_row(EXIT_GAME_ROW)
    try:
        returncode = game.proc.wait(timeout=EXIT_TIMEOUT_SECONDS)
    except Exception:
        pytest.fail(
            f"the game was still running {EXIT_TIMEOUT_SECONDS}s after ` Exit Game ` was "
            "confirmed; the three round trips left the GUI unusable"
        )
    assert returncode == 0, f"the game exited with {returncode}, not 0"

    # Asked of the OS process table, not of proc.poll() - wait() above already stored that code.
    assert_no_surviving_game_processes(game.proc.pid)
    # G9 hygiene, with the launch-time defaults mark the fixture recorded (oo-5rsa).
    assert_clean_exit(game)


# --- offline guards ----------------------------------------------------------------------------


@pytest.mark.offline
def test_each_screens_observable_is_assigned_in_exactly_one_place():
    """Each ``GUI_SCREEN_*`` this test asserts on must be assigned in EXACTLY ONE place.

    This is the uniqueness proof the whole file rests on. If some future edit assigned
    ``gui_screen = GUI_SCREEN_GAMEOPTIONS`` from a second site, then reading that value back
    would no longer prove that ``-setGuiToGameOptionsScreen`` ran, and G5's arrival assertion
    would have quietly become a weaker claim than its message says it is. Measured on this tree:
    one assignment each, all three in PlayerEntity.m.
    """
    assert os.path.isdir(SRC_DIR), f"no source tree at {SRC_DIR}"
    sources = list(iter_source_files(SRC_DIR))
    assert sources, f"no Objective-C sources under {SRC_DIR}"

    for screen in ("GUI_SCREEN_SHIPLIBRARY", "GUI_SCREEN_GAMEOPTIONS", "GUI_SCREEN_OXZMANAGER"):
        pattern = re.compile(r"gui_screen\s*=\s*[^=;]*\b" + screen + r"\b")
        hits = []
        for path in sources:
            with open(path, "r", encoding="utf-8", errors="replace") as handle:
                for number, line in enumerate(handle, 1):
                    if pattern.search(line):
                        hits.append(f"{os.path.relpath(path, OOLITE_ROOT)}:{number}")
        assert len(hits) == 1, (
            f"{screen} is assigned to gui_screen in {len(hits)} places, not 1: {hits}. G5 reads "
            "this value back out of the live game and claims it proves that screen's setter ran; "
            "with more than one assignment site that claim is no longer true and the arrival "
            "assertion must be re-justified."
        )


@pytest.mark.offline
def test_g5_asserts_arrival_and_return_for_all_three_screens():
    """The real test must assert on all three screen identifiers AND on the start screen.

    The guard that this file cannot decay into "we pressed keys and nothing crashed". It reads
    THIS FILE'S OWN AST - not its text - because a text grep is satisfied by a docstring, which
    is exactly how a sibling bead's guard stayed green after both of its real assertions were
    deleted. Every name below is required to appear in executable code inside the test function.
    """
    with open(os.path.join(HERE, "test_g5_screen_round_trips.py"), "r", encoding="utf-8") as h:
        tree = ast.parse(h.read())

    functions = {
        node.name: node for node in tree.body if isinstance(node, ast.FunctionDef)
    }
    assert "test_g5_screen_round_trips" in functions, (
        "the G5 test function has been renamed; this guard must be renamed with it"
    )

    # The ROUND_TRIPS table is executable module-level code, so its strings count - but the
    # DOCSTRINGS do not, and that is the whole point. Strip every docstring before looking.
    def literals(*nodes):
        found = set()
        for node in nodes:
            for child in ast.walk(node):
                if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef,
                                      ast.Module)):
                    body = child.body
                    if (body and isinstance(body[0], ast.Expr)
                            and isinstance(body[0].value, ast.Constant)
                            and isinstance(body[0].value.value, str)):
                        body[0].value.value = ""
                if isinstance(child, ast.Constant) and isinstance(child.value, str):
                    found.add(child.value)
        return found

    table = [
        node for node in tree.body
        if isinstance(node, ast.Assign)
        and any(isinstance(t, ast.Name) and t.id == "ROUND_TRIPS" for t in node.targets)
    ]
    assert table, "the ROUND_TRIPS table is gone; G5 no longer drives three screens"

    present = literals(functions["test_g5_screen_round_trips"], *table)
    for required in (
        "GUI_SCREEN_SHIPLIBRARY",
        "GUI_SCREEN_GAMEOPTIONS",
        "GUI_SCREEN_OXZMANAGER",
    ):
        assert required in present, (
            f"G5 no longer names {required} in executable code. The round trip for that screen "
            "has been dropped, or its arrival is being 'proved' by something other than the "
            "screen's own identifier."
        )
    assert "GUI_SCREEN_INTRO1" in present or "START_SCREEN" in {
        node.id
        for node in ast.walk(functions["test_g5_screen_round_trips"])
        if isinstance(node, ast.Name)
    }, (
        "G5 no longer checks the START screen, so it can no longer prove the RETURN half of any "
        "round trip - only that some screen was entered"
    )

    called = {
        node.func.attr
        for node in ast.walk(functions["test_g5_screen_round_trips"])
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
    }
    assert "await_screen" in called, (
        "G5 no longer reads guiScreen out of the running game; whatever it asserts now cannot "
        "distinguish 'arrived at the screen' from 'the process is still alive'"
    )
    for forbidden in ("terminate", "kill", "send_signal"):
        assert forbidden not in called, (
            f"G5 calls {forbidden}(); killing the process proves nothing about screen navigation"
        )


@pytest.mark.offline
def test_g5_never_touches_expansion_content():
    """G5 opens the Expansion Manager SCREEN and must never read or download expansion content.

    The repository rule is absolute (ADR/story prohibitions), and the manager is the one screen
    from which a careless keystroke could break it. The rows this file confirms are checked by
    AST: only the start-screen rows, the Game Options Back row, and the manager's own ``_EXIT``
    row (OOOXZManager.m:114) may appear. ``OXZ_GUI_ROW_INSTALL``/``_UPDATE`` and friends are not
    reachable from the row numbers below, and nothing here opens a file under an .oxp/.oxz.
    """
    with open(os.path.join(HERE, "test_g5_screen_round_trips.py"), "r", encoding="utf-8") as h:
        source = h.read()
    tree = ast.parse(source)

    allowed = {
        "SHIP_LIBRARY_ROW",
        "GAME_OPTIONS_ROW",
        "EXPANSION_MANAGER_ROW",
        "GAME_OPTIONS_BACK_ROW",
        "EXPANSION_MANAGER_EXIT_ROW",
        "EXIT_GAME_ROW",
    }
    used = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in (
            "_confirm",
        ):
            for arg in node.args:
                assert isinstance(arg, ast.Name), (
                    f"G5 confirms a literal row {ast.dump(arg)}; rows must be named constants so "
                    "this guard can check which screens they belong to"
                )
                used.add(arg.id)
    assert used, "G5 no longer confirms any row"
    assert used <= allowed, (
        f"G5 confirms unexpected row constant(s) {sorted(used - allowed)}. Inside the Expansion "
        "Manager only the _EXIT row is permitted: any other row can start a download or an "
        "install, which would read expansion content and break the repository rule."
    )

    # No EXECUTABLE string in this file may name an expansion file or an add-on directory.
    # Two exclusions, both narrow and both necessary:
    #   * docstrings are blanked first - this guard's prose necessarily names the extensions it
    #     forbids, and a plain text scan would fail on that, or worse, be satisfied by prose;
    #   * this guard's OWN body is skipped, since it must spell the forbidden patterns to check
    #     for them. Everything that actually drives the game is still covered.
    # ``OO_ADDITIONALADDONSDIRS`` is exempt by exact name: it is the variable that adds this
    # session's throwaway debugConfig.plist ROOT (see screen_witness), which contains nothing
    # but that plist and no expansion of any kind.
    ADDONS_ENV = "OO_ADDITIONALADDONSDIRS"
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Module)):
            body = node.body
            if (body and isinstance(body[0], ast.Expr)
                    and isinstance(body[0].value, ast.Constant)
                    and isinstance(body[0].value.value, str)):
                body[0].value.value = ""
    scanned = [
        node for node in tree.body
        if not (isinstance(node, ast.FunctionDef)
                and node.name == "test_g5_never_touches_expansion_content")
    ]
    assert len(scanned) == len(tree.body) - 1, (
        "this guard could not find itself to exclude; it has been renamed"
    )
    executable_strings = [
        child.value
        for node in scanned
        for child in ast.walk(node)
        if isinstance(child, ast.Constant) and isinstance(child.value, str)
    ]
    for text in executable_strings:
        if text == ADDONS_ENV:
            continue
        lowered = text.lower()
        for forbidden in (".oxz", ".oxp", "addons"):
            assert forbidden not in lowered, (
                f"G5 has an executable string {text!r} naming {forbidden!r}: this tier must "
                "never read expansion content"
            )
