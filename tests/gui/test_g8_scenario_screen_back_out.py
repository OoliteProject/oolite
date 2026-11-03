"""G8 - the scenario screen, entered from start-screen row 22 and left again by its row 1.

docs/phases/0-gui-tier.md G8: "Launch -> confirm row 22 -> confirm row 1 (``Return to Menu``) ->
verify start screen -> exit". The bug class is a GUI state machine that goes one way: a screen you
can enter and cannot leave is a wedged game, and it is exactly what a rewrite of the screen
dispatchers breaks without breaking anything that compiles.

Written the way the two merged tests closest to it are written, and reusing both wholesale:

* **G2** (test_g2_exit_via_keyboard.py) for ROW DERIVATION. No row number in this file's
  navigation is typed. ``scenario_screen_row()`` reads ``int row_zero = N;`` and the
  ``[gui selectedRow] == K+row_zero`` branch that calls ``-setGuiToScenarioScreen:`` out of
  ``-pollDemoControls`` (PlayerEntityControls.m), the same way G2 reads its ` Exit Game ` row; and
  the derivations are asserted to AGREE with the literals in the story, so a renumbered menu fails
  LOUDLY instead of quietly confirming the wrong row.
* **G5** (test_g5_screen_round_trips.py) for the INSTRUMENT. The observable is the game's own
  ``guiScreen``, read over the debug console - PlayerEntityLegacyScriptEngine.m:920 answers that
  property with ``OOStringFromGUIScreenID(gui_screen)``, a direct read of the instance variable
  each screen's setter assigns. The ScreenWitness client below, its marked-reply protocol (the
  console ECHOES the command text first, so a marker spelled literally in the command matches its
  own echo - it is split in the source and joined at runtime, and the answer is the text between
  the SECOND and third occurrence, hence ``count >= 2``) and the per-frame key sampling are G5's,
  restated here for the same reason G2 restated them: a shared helper added to conftest.py by two
  concurrent GUI beads is a guaranteed merge conflict, and nothing below is needed by any other
  test.

WHAT "ROW 1" ACTUALLY IS ON THE SCENARIO SCREEN. DERIVED, NOT ASSUMED.
---------------------------------------------------------------------
The story says "confirm row 1 (``Return to Menu``)" and that is worth checking rather than
trusting, because the three screens G5 round-trips leave by three DIFFERENT mechanisms (a Space
key, a ``Back`` row, an ``_EXIT`` row). On this screen it IS a numbered, addressable row, and the
number is derived from the game's own source in ``scenario_exit_row()``:

    PlayerEntityLoadSave.m:207 -setGuiToScenarioScreen:
        OOGUIRow start_row = GUI_ROW_SCENARIOS_START;                     (PlayerEntity.h:164, = 3)
        [gui setArray:... DESC(@"oolite-scenario-exit") ... forRow:start_row - 2];
        [gui setKey:@"exit" forRow:start_row - 2];                        => row 1
        [gui setSelectableRange:NSMakeRange(start_row - 2, ...)];         => row 1 is selectable
        [gui setSelectedRow:start_row];                                   => but NOT preselected

    PlayerEntityLoadSave.m:314 -startScenario
        if ([key isEqualToString:@"exit"]) return NO;                     // "return to main menu"

    PlayerEntityControls.m:5064 case GUI_SCREEN_NEWGAME:
        if ([self checkKeyPress:n_key_gui_select] || [gameView isDown:gvMouseDoubleClick])
            if (![self startScenario]) { [UNIVERSE removeDemoShips]; [self setGuiToIntroFirstGo:YES]; }

So confirming row 1 makes ``-startScenario`` answer NO for the ``exit`` key, and the dispatcher's
NO branch is the ONLY thing on that screen that calls ``-setGuiToIntroFirstGo:YES``. Every link in
that chain is pinned by an offline guard below, and ``DESC(@"oolite-scenario-exit")`` is checked
against descriptions.plist to be the story's "Return to Menu" - so the row this test confirms is
the row the story names, and not merely row number 1.

Note what row 1 is NOT: it is not preselected. ``-setGuiToScenarioScreen:`` leaves the selection on
``start_row`` (3), the first scenario, so a bare Enter on arrival would START a scenario - i.e.
load a save game - rather than back out. This test therefore SELECTS row 1 before confirming it,
and never confirms any ``Scenario:N`` row.

THE ARRIVAL OBSERVABLE HAS TWO ASSIGNMENT SITES, AND THAT IS STATED RATHER THAN GLOSSED
---------------------------------------------------------------------------------------
G5 could say each of its three screens' identifiers was assigned in exactly ONE place in the tree.
``GUI_SCREEN_NEWGAME`` is not like that - it is assigned TWICE, and pretending otherwise would be
the dishonesty this tier exists to prevent:

    PlayerEntityLoadSave.m:262  -setGuiToScenarioScreen:      the screen setter, what G8 wants
    PlayerEntityLoadSave.m:803  -loadPlayerFromFile:asNew:    ``if (asNew) gui_screen = GUI_SCREEN_NEWGAME;``

The second is still a sound witness for this test, for a reason that is CHECKED and not asserted
in prose: that assignment is immediately followed, in the same straight line of code, by
``[self setGuiToStatusScreen]`` (PlayerEntity.m:7924, ``gui_screen = GUI_SCREEN_STATUS``), so the
value cannot be OBSERVED from outside that method - by the time the run loop polls again,
guiScreen is GUI_SCREEN_STATUS. The only way to reach :803 at all is ``-startScenario`` selecting
a ``Scenario:N`` row, which this test never does. Both halves of that argument are pinned by
``test_the_arrival_observable_has_exactly_two_assignment_sites_and_only_one_is_observable``; if a
future edit gave the load path a lingering GUI_SCREEN_NEWGAME, that guard goes red and this
file's arrival claim is re-justified deliberately rather than silently weakened.

``GUI_SCREEN_INTRO1`` - the return observable - is assigned in exactly one place
(PlayerEntity.m:10070, ``-setGuiToIntroFirstGo:``), which is checked the same way.

ARRIVAL AND RETURN ARE SEPARATE PROPERTIES, WITH SEPARATE MESSAGES
------------------------------------------------------------------
The test asserts them as two assertions with two distinct, non-overlapping messages
(``ARRIVAL FAILED``/``RETURN FAILED``), because a single "the round trip worked" assertion cannot
say which half broke - and because one assertion wearing two names is the defect this fleet keeps
finding. They fail independently: breaking the entry gesture reddens ARRIVAL and never reaches
RETURN; breaking only the back-out gesture leaves ARRIVAL green and reddens RETURN. That
independence is what makes each one load-bearing, and it is required structurally by
``test_g8_asserts_arrival_and_return_as_separate_properties`` below, which reads this file's own
AST rather than its text.

This file reads no expansion content: nothing here opens an .oxp or .oxz, and the only rows it
ever confirms are the start screen's scenario row, the scenario screen's ``exit`` row and the
start screen's ` Exit Game ` row.

    python3 -m pytest upstream/oolite/tests/gui/test_g8_scenario_screen_back_out.py -x -q

Needs the desktop: a real window, unlocked and logged in (ADR-0017). It takes tools/gui-lock for
the duration, via the ``game`` fixture - this file launches nothing of its own.
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
    assert_clean_exit,
    assert_no_surviving_game_processes,
    assert_shutdown_path_completed,
)

HERE = os.path.dirname(os.path.abspath(__file__))
OOLITE_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC_DIR = os.path.join(OOLITE_ROOT, "src")
PLAYER_ENTITY = os.path.join(SRC_DIR, "Core", "Entities", "PlayerEntity.m")
PLAYER_ENTITY_H = os.path.join(SRC_DIR, "Core", "Entities", "PlayerEntity.h")
PLAYER_CONTROLS = os.path.join(SRC_DIR, "Core", "Entities", "PlayerEntityControls.m")
PLAYER_LOADSAVE = os.path.join(SRC_DIR, "Core", "Entities", "PlayerEntityLoadSave.m")
DESCRIPTIONS = os.path.join(OOLITE_ROOT, "Resources", "Config", "descriptions.plist")

# The screen the tier starts on and must come back to (PlayerEntity.m:10070).
START_SCREEN = "GUI_SCREEN_INTRO1"
# The screen -setGuiToScenarioScreen: assigns (PlayerEntityLoadSave.m:262).
SCENARIO_SCREEN = "GUI_SCREEN_NEWGAME"
# Where a mis-aimed confirm on the scenario screen would land instead: -startScenario answering
# YES loads a save game, and the load path ends at -setGuiToStatusScreen. Named so that a failure
# of the RETURN assertion can report the difference between "it did not come back" and "it started
# a scenario", which are completely different bugs.
SCENARIO_STARTED_SCREEN = "GUI_SCREEN_STATUS"

# The DESC key -setGuiToScenarioScreen: puts on the back-out row, and the text the story calls it
# by. Checked against descriptions.plist rather than trusted.
SCENARIO_EXIT_DESC_KEY = "oolite-scenario-exit"
SCENARIO_EXIT_LABEL = "Return to Menu"
# The GUI key -setGuiToScenarioScreen: sets on that row, and the one -startScenario tests for.
SCENARIO_EXIT_GUI_KEY = "exit"

# How long the game is given to act on a confirmed row. The transition happens in the frame after
# the input is sampled; generous so a busy machine is not a flake. G5's value.
TRANSITION_TIMEOUT_SECONDS = 15
# The story's budget for ` Exit Game `, the same one G1, G2, G3 and G5 use.
EXIT_TIMEOUT_SECONDS = 10

# The two failure messages, as constants, because they are a CONTRACT: the arrival assertion and
# the return assertion must be distinguishable in a log, and the AST guard below requires both to
# be present in executable code. If one mutation ever produced both, one of them is not working.
ARRIVAL_FAILURE_PREFIX = "ARRIVAL FAILED"
RETURN_FAILURE_PREFIX = "RETURN FAILED"


# --- the rows, derived from the game's own definitions ------------------------------------------


def _read(path):
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        return handle.read()


def _method_body(source, signature):
    """The text of one Objective-C method, from its signature to its closing brace."""
    start = source.find(signature)
    assert start >= 0, f"{signature!r} is no longer in the source; G8's derivation is broken"
    end = source.find("\n}\n", start)
    assert end > start, f"could not find the end of {signature!r}"
    return source[start:end]


def _start_screen_row_zero(body):
    match = re.search(r"int\s+row_zero\s*=\s*(\d+)\s*;", body)
    assert match, (
        "the start-screen dispatcher no longer declares `int row_zero = N;`, so G8 cannot derive "
        "which row opens the scenario screen and must not guess one"
    )
    return int(match.group(1))


def scenario_screen_row():
    """The start-screen row whose dispatch calls ``-setGuiToScenarioScreen:``.

    G2's technique, aimed at a different branch. ``-pollDemoControls``'s ``case GUI_SCREEN_INTRO1:``
    declares a bare ``int row_zero = N;`` and dispatches each menu row as
    ``[gui selectedRow] == K+row_zero``; the branch that calls ``-setGuiToScenarioScreen:`` is the
    one this test wants, and ``K + row_zero`` is its row. Nothing is hardcoded, so a menu that
    gains or loses an entry above the scenario row fails loudly instead of opening Game Options.
    """
    body = _method_body(_read(PLAYER_CONTROLS), "- (void) pollDemoControls:(double)delta_t")
    row_zero = _start_screen_row_zero(body)
    branch = re.search(
        r"\[gui selectedRow\]\s*==\s*(\d+)\s*\+\s*row_zero\s*\)\s*\{(?:[^{}]*?)"
        r"\[self setGuiToScenarioScreen:",
        body,
        re.S,
    )
    assert branch, (
        "no `[gui selectedRow] == K+row_zero` branch on the start screen calls "
        "-setGuiToScenarioScreen: any more; G8 has no scenario row to aim at"
    )
    return row_zero + int(branch.group(1))


def exit_row_dispatch():
    """``(exit_row, context)`` for ` Exit Game `, exactly as G2 derives them.

    G8 leaves through the same row G1/G2/G5 do, and asserting the context string the source
    actually contains is what makes the final shutdown evidence attributable to THIS row rather
    than to one of the tree's other -exitAppWithContext: call sites.
    """
    body = _method_body(_read(PLAYER_CONTROLS), "- (void) pollDemoControls:(double)delta_t")
    row_zero = _start_screen_row_zero(body)
    branch = re.search(
        r"\[gui selectedRow\]\s*==\s*(\d+)\s*\+\s*row_zero\s*\)\s*\{\s*"
        r"\[\[UNIVERSE gameController\] exitAppWithContext:@\"([^\"]+)\"\]",
        body,
    )
    assert branch, (
        "no `[gui selectedRow] == K+row_zero` branch on the start screen calls "
        "-exitAppWithContext: any more; G8 has no ` Exit Game ` row to leave by"
    )
    return row_zero + int(branch.group(1)), branch.group(2)


def scenarios_start_row():
    """``GUI_ROW_SCENARIOS_START`` out of the game's own enum (PlayerEntity.h)."""
    match = re.search(
        r"GUI_ROW_SCENARIOS_START\s*=\s*(\d+)\s*,", _read(PLAYER_ENTITY_H)
    )
    assert match, (
        "PlayerEntity.h no longer defines GUI_ROW_SCENARIOS_START as a literal, so G8 cannot "
        "derive which row the scenario screen's back-out sits on"
    )
    return int(match.group(1))


def scenario_exit_row():
    """The scenario screen's OWN back-out row - ``Return to Menu`` - derived from its builder.

    ``-setGuiToScenarioScreen:`` lays that row out relative to ``start_row``:

        [gui setArray:... DESC(@"oolite-scenario-exit") ... forRow:start_row - 2];
        [gui setKey:@"exit" forRow:start_row - 2];

    Both the label row and the KEY row are read, and they must be the SAME offset - the key is
    what ``-startScenario`` tests, and the label is what the operator sees, so a screen where they
    disagree would mean this test confirms a row whose visible text is not the one the story
    names. The offset is subtracted from ``GUI_ROW_SCENARIOS_START`` rather than written as 1.
    """
    body = _method_body(_read(PLAYER_LOADSAVE), "- (void) setGuiToScenarioScreen:(int)page")
    start_row_name = re.search(
        r"OOGUIRow\s+start_row\s*=\s*(GUI_ROW_SCENARIOS_START)\s*;", body
    )
    assert start_row_name, (
        "-setGuiToScenarioScreen: no longer builds its rows from GUI_ROW_SCENARIOS_START; G8's "
        "back-out row derivation no longer describes the screen"
    )
    label = re.search(
        r'DESC\(@"' + re.escape(SCENARIO_EXIT_DESC_KEY) + r'"\).*?forRow:start_row\s*-\s*(\d+)\]',
        body,
        re.S,
    )
    assert label, (
        f"-setGuiToScenarioScreen: no longer lays out a DESC(@\"{SCENARIO_EXIT_DESC_KEY}\") row "
        "at a start_row-relative offset, so G8 cannot find the ` Return to Menu ` row"
    )
    key = re.search(
        r'setKey:@"' + re.escape(SCENARIO_EXIT_GUI_KEY) + r'"\s+forRow:start_row\s*-\s*(\d+)\]',
        body,
    )
    assert key, (
        f"-setGuiToScenarioScreen: no longer sets the @\"{SCENARIO_EXIT_GUI_KEY}\" key on a "
        "start_row-relative row; -startScenario dispatches on that key, so without it confirming "
        "the row would do something other than backing out"
    )
    assert label.group(1) == key.group(1), (
        f"the ` {SCENARIO_EXIT_LABEL} ` LABEL is on row start_row-{label.group(1)} but the "
        f"@\"{SCENARIO_EXIT_GUI_KEY}\" KEY is on row start_row-{key.group(1)}. G8 would confirm a "
        "row whose visible text is not the one it acts on."
    )
    return scenarios_start_row() - int(key.group(1))


SCENARIO_ROW = scenario_screen_row()
SCENARIO_EXIT_ROW = scenario_exit_row()
EXIT_GAME_ROW, EXPECTED_EXIT_CONTEXT = exit_row_dispatch()


# --- the screen witness (G5's instrument) -------------------------------------------------------
#
# Protocol constants, spelled as tests/component/console.py, G2 and G5 spell them.
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
    way tests/launch_snapshot.py, G2 and G5 all do; a fixed 8563 would collide with a
    component-tier run on this shared machine.
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
        root = tempfile.mkdtemp(prefix=f"oolite-g8-console-{self.port}-")
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
            f"{timeout}s. G8 proves ARRIVAL at the scenario screen and RETURN to the start "
            "screen by reading the game's own guiScreen, so without this connection it cannot "
            "tell a round trip from a pair of keystrokes that did nothing, and must not pass. "
            "Check that the debug support resource bundle shipped with the build is present in "
            "its add-on directory."
        )

    def _handshake(self):
        packet = self._recv()
        if packet is None or packet.get(PACKET_TYPE_KEY) != REQUEST_CONNECTION:
            raise ScreenWitnessError(f"unexpected first console packet: {packet!r}")
        self._send({PACKET_TYPE_KEY: APPROVE_CONNECTION, CONSOLE_IDENTITY_KEY: "oolite G8"})

    def gui_screen(self, timeout=15):
        """The game's own ``guiScreen``, as a ``GUI_SCREEN_*`` string.

        PlayerEntityLegacyScriptEngine.m:920 answers this property with
        ``OOStringFromGUIScreenID(gui_screen)``, so the value is a direct read of the instance
        variable each screen's setter assigns - not a redraw, not a texture, not a guess.
        """
        # The console echoes the command text back before the answer, so a marker that appeared
        # literally in the command would match its own echo. Split in the source, joined at
        # runtime - the same trick console.py::evaluate, G2 and G5 use, for the same reason.
        head = f"@@g8-{os.getpid()}-{self.port}"
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


# --- the test -----------------------------------------------------------------------------------


def test_g8_scenario_screen_back_out(screen_witness, game):
    """Enter the scenario screen from row 22, leave it by row 1, and exit.

    Four claims, in order, each with its own message:

    1. PRECONDITION - the game is on the start screen, so the derived rows describe what is on
       the screen and confirming one is not navigating an unknown menu.
    2. ARRIVAL - after confirming the scenario row, ``guiScreen`` is the scenario screen's own
       identifier. Read from the game, not from a screenshot and not from the absence of a crash.
    3. RETURN - after selecting and confirming the scenario screen's ``Return to Menu`` row,
       ``guiScreen`` is the START screen again. This is a SEPARATE property from arrival with a
       SEPARATE message: a game that enters and cannot leave passes claim 2 and fails this one,
       which is the whole bug class G8 exists for.
    4. STILL USABLE - the start screen still answers its menu: ` Exit Game ` takes the game down
       with status 0, no survivor in the process table, clean G9 hygiene, and a shutdown trace
       naming the start-screen exit context.
    """
    witness = screen_witness.accept()
    assert game.proc.poll() is None, "the game exited before the test could confirm a row"
    game.assert_focused()

    # 1. PRECONDITION.
    seen = witness.await_screen(START_SCREEN)
    assert seen == START_SCREEN, (
        f"the game is on {seen}, not {START_SCREEN}, so the rows derived from the start-screen "
        f"dispatcher do not describe what is on the screen and confirming row {SCENARIO_ROW} "
        "would activate an unknown menu entry"
    )

    # 2. ARRIVAL. Confirm the scenario row and ask the game what screen it is on.
    game.confirm_row(SCENARIO_ROW)
    arrived = witness.await_screen(SCENARIO_SCREEN)
    assert arrived == SCENARIO_SCREEN, (
        f"{ARRIVAL_FAILURE_PREFIX}: after confirming start-screen row {SCENARIO_ROW} the game "
        f"reports guiScreen {arrived}, not {SCENARIO_SCREEN}. That row's dispatch branch is the "
        "only start-screen path to -setGuiToScenarioScreen:, so this is a direct statement that "
        "the scenario screen's setter never ran - the screen was not entered, and the back-out "
        "below would be measured from the wrong place."
    )

    # 3. RETURN. Row 1 is NOT preselected (-setGuiToScenarioScreen: leaves the selection on the
    #    first SCENARIO row), so it is selected first and only then confirmed. Confirming the
    #    preselected row would start a scenario instead of backing out.
    game.select_row(SCENARIO_EXIT_ROW)
    game.confirm_row(SCENARIO_EXIT_ROW)
    returned = witness.await_screen(START_SCREEN)
    assert returned == START_SCREEN, (
        f"{RETURN_FAILURE_PREFIX}: after confirming the scenario screen's row "
        f"{SCENARIO_EXIT_ROW} (` {SCENARIO_EXIT_LABEL} `, GUI key "
        f"\"{SCENARIO_EXIT_GUI_KEY}\") the game reports guiScreen {returned}, not "
        f"{START_SCREEN}. The game entered the scenario screen and did not come back, so that "
        "screen's back-out is broken and the start screen is no longer reachable."
        + (
            f" It is on {SCENARIO_STARTED_SCREEN}, which means -startScenario answered YES and "
            "LOADED a scenario rather than backing out - the confirm landed on a Scenario row, "
            "not on the exit row."
            if returned == SCENARIO_STARTED_SCREEN
            else ""
        )
    )

    # 4. STILL USABLE. A game left in a wedged GUI state cannot take this path.
    game.select_row(EXIT_GAME_ROW)
    game.confirm_row(EXIT_GAME_ROW)
    try:
        returncode = game.proc.wait(timeout=EXIT_TIMEOUT_SECONDS)
    except Exception:
        pytest.fail(
            f"the game was still running {EXIT_TIMEOUT_SECONDS}s after ` Exit Game ` (row "
            f"{EXIT_GAME_ROW}) was confirmed; the scenario round trip left the GUI unusable"
        )
    assert returncode == 0, f"the game exited with {returncode}, not 0"

    # Asked of the OS process table, not of proc.poll() - wait() above already stored that code.
    assert_no_surviving_game_processes(game.proc.pid)
    # G9 hygiene, with the launch-time defaults mark the fixture recorded (oo-5rsa).
    assert_clean_exit(game)
    # And the shutdown ran to its last line, for the START-SCREEN ` Exit Game ` row.
    assert_shutdown_path_completed(game, expected_context=EXPECTED_EXIT_CONTEXT)


# --- offline guards: the claims this file rests on -----------------------------------------------


def _objc_sources():
    sources = []
    for root, _dirs, files in os.walk(SRC_DIR):
        for name in files:
            if name.endswith((".m", ".mm", ".c", ".h")):
                sources.append(os.path.join(root, name))
    assert sources, f"no Objective-C sources under {SRC_DIR}"
    return sources


def _assignment_sites(screen):
    """``[path:line, ...]`` for every ``gui_screen = ... SCREEN`` in the tree."""
    pattern = re.compile(r"gui_screen\s*=\s*[^=;]*\b" + re.escape(screen) + r"\b")
    hits = []
    for path in _objc_sources():
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            for number, line in enumerate(handle, 1):
                if pattern.search(line):
                    hits.append(f"{os.path.relpath(path, OOLITE_ROOT)}:{number}")
    return hits


@pytest.mark.offline
def test_the_return_observable_is_assigned_in_exactly_one_place():
    """``GUI_SCREEN_INTRO1`` must have ONE assignment site, or RETURN proves less than it says.

    The return assertion reads this value back out of the live game and claims it proves
    ``-setGuiToIntroFirstGo:`` ran. A second assignment site would make that a weaker claim than
    the message says it is. Measured on this tree: one, PlayerEntity.m:10070.
    """
    hits = _assignment_sites(START_SCREEN)
    assert len(hits) == 1, (
        f"{START_SCREEN} is assigned to gui_screen in {len(hits)} places, not 1: {hits}. G8's "
        "RETURN assertion reads this value back out of the live game and claims it proves the "
        "start screen's setter ran; with more than one site that claim must be re-justified."
    )


@pytest.mark.offline
def test_the_arrival_observable_has_exactly_two_assignment_sites_and_only_one_is_observable():
    """``GUI_SCREEN_NEWGAME`` is assigned TWICE, and the second one cannot be observed.

    STATED PLAINLY rather than glossed, because G5 could honestly say "exactly one" and G8
    cannot. The two sites are ``-setGuiToScenarioScreen:`` (the setter G8 wants) and
    ``-loadPlayerFromFile:asNew:``'s ``if (asNew)`` branch. The second is harmless here because
    the very next statements in that method call ``-setGuiToStatusScreen``, which overwrites
    gui_screen before the run loop can poll again - so an OBSERVED GUI_SCREEN_NEWGAME can only
    have come from the screen setter.

    Both halves are checked. If a future edit let the load path leave GUI_SCREEN_NEWGAME standing,
    this goes red and G8's arrival claim is re-justified deliberately instead of silently decaying.
    """
    hits = _assignment_sites(SCENARIO_SCREEN)
    assert len(hits) == 2, (
        f"{SCENARIO_SCREEN} is assigned to gui_screen in {len(hits)} places, not the 2 this "
        f"file's docstring accounts for: {hits}. G8's ARRIVAL assertion reads this value back "
        "out of the live game; every assignment site must be shown unobservable or unreachable."
    )

    setter = _method_body(_read(PLAYER_LOADSAVE), "- (void) setGuiToScenarioScreen:(int)page")
    assert re.search(r"gui_screen\s*=\s*" + SCENARIO_SCREEN, setter), (
        "-setGuiToScenarioScreen: no longer assigns gui_screen = " + SCENARIO_SCREEN
    )

    loader = _method_body(
        _read(PLAYER_LOADSAVE), "- (BOOL) loadPlayerFromFile:(NSString *)fileToOpen asNew:"
    )
    assign = re.search(r"gui_screen\s*=\s*" + SCENARIO_SCREEN, loader)
    assert assign, (
        "the second assignment site is no longer inside -loadPlayerFromFile:asNew:; the argument "
        "that it cannot be observed was made about THAT method and must be remade"
    )
    tail = loader[assign.end():]
    status_call = tail.find("[self setGuiToStatusScreen]")
    assert status_call >= 0, (
        "-loadPlayerFromFile:asNew: assigns gui_screen = " + SCENARIO_SCREEN + " and no longer "
        "calls -setGuiToStatusScreen afterwards. That value would now SURVIVE into the run loop, "
        "so reading it back would no longer prove -setGuiToScenarioScreen: ran, and G8's ARRIVAL "
        "assertion would be satisfied by a loaded save game."
    )
    # Nothing between them may poll input or return: the overwrite must be unconditional.
    between = tail[:status_call]
    assert "return" not in between, (
        f"there is now a `return` between the GUI_SCREEN_NEWGAME assignment and "
        f"-setGuiToStatusScreen in -loadPlayerFromFile:asNew:: {between!r}. The overwrite is no "
        "longer unconditional, so the load path can leave that value observable."
    )
    # And -setGuiToStatusScreen really is what overwrites it.
    assert re.search(
        r"gui_screen\s*=\s*GUI_SCREEN_STATUS",
        _method_body(_read(PLAYER_ENTITY), "- (void) setGuiToStatusScreen"),
    ), "-setGuiToStatusScreen no longer assigns gui_screen, so it cannot overwrite the load path's"


@pytest.mark.offline
def test_the_scenario_row_and_the_back_out_row_are_derived_and_agree_with_the_story():
    """The two derived rows must equal the numbers docs/phases/0-gui-tier.md's G8 row names.

    NOT because the literals are the source of truth - the game's source is, and that is what the
    functions above read - but because a silent divergence is the failure this guards. If the
    start menu gains an entry, or the scenario screen's layout moves, the derivation follows it
    and this assertion goes RED: the story and the test then get updated together, deliberately,
    rather than the test quietly confirming a different row and reporting a pass.
    """
    assert scenario_screen_row() == SCENARIO_ROW
    assert scenario_exit_row() == SCENARIO_EXIT_ROW
    assert SCENARIO_ROW == 22, (
        f"the derivation now puts the scenario screen on start-screen row {SCENARIO_ROW}, not "
        "the 22 in docs/phases/0-gui-tier.md's G8 row. That is not necessarily a bug - the start "
        "menu may have gained or lost an entry - but the story and this test must be updated "
        "together rather than the test silently confirming a different row."
    )
    assert SCENARIO_EXIT_ROW == 1, (
        f"the derivation now puts the scenario screen's ` {SCENARIO_EXIT_LABEL} ` on row "
        f"{SCENARIO_EXIT_ROW}, not the 1 in docs/phases/0-gui-tier.md's G8 row. Same rule: "
        "update the story and this test together."
    )
    # The back-out row must be distinct from every scenario row, or "confirm it" is ambiguous.
    assert SCENARIO_EXIT_ROW < scenarios_start_row(), (
        f"the back-out row {SCENARIO_EXIT_ROW} is not above the first scenario row "
        f"{scenarios_start_row()}; confirming it could start a scenario"
    )
    # ...and addressable by the tier's row -> point helper in the pinned window.
    import conftest

    left, top = 0, 0
    width, height = conftest.PINNED_CLIENT_SIZE
    for row in (SCENARIO_ROW, SCENARIO_EXIT_ROW, EXIT_GAME_ROW):
        conftest.row_to_point(row, (left, top, width, height))


@pytest.mark.offline
def test_the_back_out_row_is_the_row_the_story_names():
    """``DESC(@"oolite-scenario-exit")`` must really read ` Return to Menu `.

    The story says "row 1 (``Return to Menu``)". Row 1 is derived above from the game's source;
    this is the other half - that the row so derived is the one an operator would call by that
    name. Read out of descriptions.plist rather than assumed.
    """
    assert os.path.isfile(DESCRIPTIONS), f"no descriptions.plist at {DESCRIPTIONS}"
    text = _read(DESCRIPTIONS)
    match = re.search(
        r'"' + re.escape(SCENARIO_EXIT_DESC_KEY) + r'"\s*=\s*"([^"]*)"\s*;', text
    )
    assert match, (
        f"descriptions.plist no longer defines {SCENARIO_EXIT_DESC_KEY!r}; the row G8 confirms "
        "would then have no visible label and the story's name for it could not be checked"
    )
    assert match.group(1) == SCENARIO_EXIT_LABEL, (
        f"{SCENARIO_EXIT_DESC_KEY!r} now reads {match.group(1)!r}, not {SCENARIO_EXIT_LABEL!r}. "
        "docs/phases/0-gui-tier.md's G8 row names that text; the story and this test must be "
        "updated together."
    )


@pytest.mark.offline
def test_the_back_out_chain_is_the_only_way_off_the_scenario_screen_by_that_row():
    """Confirming the ``exit`` key must be what returns the game to the start screen.

    Three links, each read from the game's own source:

    1. ``-startScenario`` answers NO for the ``exit`` key - and for that key alone among the ones
       the back-out row could carry;
    2. the ``GUI_SCREEN_NEWGAME`` dispatcher calls ``-startScenario`` on the select key or a
       double-click, and calls ``-setGuiToIntroFirstGo:YES`` exactly when it answers NO;
    3. that is the only ``-setGuiToIntroFirstGo:`` call in the scenario screen's case.

    Without this, "confirm row 1 and the game came back" would be a coincidence this file has no
    account of.
    """
    start_scenario = _method_body(_read(PLAYER_LOADSAVE), "- (BOOL) startScenario")
    exit_branch = re.search(
        r'if\s*\(\s*\[key isEqualToString:@"'
        + re.escape(SCENARIO_EXIT_GUI_KEY)
        + r'"\]\s*\)\s*\{(.*?)\}',
        start_scenario,
        re.S,
    )
    assert exit_branch, (
        f"-startScenario no longer has an `if ([key isEqualToString:@\"{SCENARIO_EXIT_GUI_KEY}\"])"
        "` branch, so confirming the back-out row no longer means 'do not start a scenario'"
    )
    assert re.search(r"return\s+NO\s*;", exit_branch.group(1)), (
        f"-startScenario's {SCENARIO_EXIT_GUI_KEY!r} branch no longer returns NO: "
        f"{exit_branch.group(1)!r}. The dispatcher backs out only on NO, so this row would now "
        "do something else entirely."
    )

    controls = _read(PLAYER_CONTROLS)
    case_start = controls.find("case " + SCENARIO_SCREEN + ":")
    assert case_start >= 0, (
        f"-pollGuiScreenControls has no `case {SCENARIO_SCREEN}:` any more; the scenario screen "
        "no longer has a dispatcher and G8's back-out has nothing to drive"
    )
    case_end = controls.find("\n\t\tcase ", case_start + 1)
    assert case_end > case_start, "could not find the end of the scenario screen's case block"
    case_body = controls[case_start:case_end]
    back_out = re.search(
        r"if\s*\(\s*!\s*\[self startScenario\]\s*\)\s*\{(.*?)\}", case_body, re.S
    )
    assert back_out, (
        f"the {SCENARIO_SCREEN} dispatcher no longer has an `if (![self startScenario])` branch, "
        "so a NO from the exit row no longer returns the game to the start screen"
    )
    assert "setGuiToIntroFirstGo:YES" in back_out.group(1), (
        "the `if (![self startScenario])` branch no longer calls -setGuiToIntroFirstGo:YES: "
        f"{back_out.group(1)!r}. That call is what assigns {START_SCREEN}, which is G8's RETURN "
        "observable."
    )
    assert case_body.count("setGuiToIntroFirstGo") == 1, (
        f"the {SCENARIO_SCREEN} dispatcher now calls -setGuiToIntroFirstGo: from "
        f"{case_body.count('setGuiToIntroFirstGo')} places, so returning to the start screen no "
        "longer identifies the back-out row as the cause"
    )
    assert "gvMouseDoubleClick" in case_body and "n_key_gui_select" in case_body, (
        "the scenario screen's dispatcher no longer activates the selected row on a double-click "
        "or the select key, so game.confirm_row() would not reach -startScenario at all"
    )
    # And the screen does NOT preselect the back-out row: this is why the test selects it first.
    setter = _method_body(_read(PLAYER_LOADSAVE), "- (void) setGuiToScenarioScreen:(int)page")
    assert re.search(r"setSelectedRow:start_row\s*\]", setter), (
        "-setGuiToScenarioScreen: no longer leaves the selection on start_row. G8 selects the "
        "back-out row explicitly BECAUSE it is not preselected; if that changed, the reason for "
        "the extra select_row call has changed too and should be re-read."
    )


@pytest.mark.offline
def test_g8_asserts_arrival_and_return_as_separate_properties():
    """THE ANTI-DECAY GUARD: two assertions, two messages, and the game asked both times.

    Read from this file's own AST, never its text: a docstring or a comment containing
    "ARRIVAL FAILED" is not an assertion, and a sibling bead's substring guard was held green by
    exactly that. Every requirement below is checked against real ``ast.Assert``/``ast.Call``
    nodes inside the launching test.

    What it enforces:

    * the launching test contains an assert comparing against ``SCENARIO_SCREEN`` whose message
      carries the arrival prefix, and a DIFFERENT assert comparing against ``START_SCREEN`` whose
      message carries the return prefix;
    * the two messages do not overlap, so a log line identifies which half failed;
    * both are fed by ``await_screen``, i.e. by the game's own guiScreen, not by liveness;
    * the test never terminates or kills the process - that would prove the OS can end a process,
      not that the scenario screen can be left;
    * the shared post-exit helpers the tier requires of every launching test are real calls.
    """
    with open(os.path.join(HERE, os.path.basename(__file__)), "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read())
    functions = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
    assert "test_g8_scenario_screen_back_out" in functions, (
        "the G8 test function has been renamed; this guard must be renamed with it"
    )
    func = functions["test_g8_scenario_screen_back_out"]

    # The two prefixes are module constants referenced BY NAME inside the f-string messages, so
    # the message text as written is a mixture of literals and Name loads. Both are resolved
    # here - a Name load of ARRIVAL_FAILURE_PREFIX is every bit as executable as the literal,
    # and neither can be produced by a docstring or a comment.
    prefix_constants = {
        "ARRIVAL_FAILURE_PREFIX": ARRIVAL_FAILURE_PREFIX,
        "RETURN_FAILURE_PREFIX": RETURN_FAILURE_PREFIX,
    }

    def message_text(node):
        """Every string reachable from an assert's message: constants and named prefixes."""
        if node.msg is None:
            return ""
        parts = []
        for child in ast.walk(node.msg):
            if isinstance(child, ast.Constant) and isinstance(child.value, str):
                parts.append(child.value)
            elif isinstance(child, ast.Name) and child.id in prefix_constants:
                parts.append(prefix_constants[child.id])
        return "".join(parts)

    def compared_names(node):
        return {
            child.id
            for child in ast.walk(node.test)
            if isinstance(child, ast.Name)
        }

    asserts = [n for n in ast.walk(func) if isinstance(n, ast.Assert)]
    arrival = [
        n for n in asserts
        if ARRIVAL_FAILURE_PREFIX in message_text(n) and "SCENARIO_SCREEN" in compared_names(n)
    ]
    returns = [
        n for n in asserts
        if RETURN_FAILURE_PREFIX in message_text(n) and "START_SCREEN" in compared_names(n)
    ]
    assert len(arrival) == 1, (
        f"G8 has {len(arrival)} assertion(s) comparing against SCENARIO_SCREEN with an "
        f"{ARRIVAL_FAILURE_PREFIX!r} message, not exactly 1. The ARRIVAL half of the round trip "
        "is no longer a property this test states."
    )
    assert len(returns) == 1, (
        f"G8 has {len(returns)} assertion(s) comparing against START_SCREEN with a "
        f"{RETURN_FAILURE_PREFIX!r} message, not exactly 1. The RETURN half - the whole bug class "
        "G8 exists for, a screen you can enter and cannot leave - is no longer stated."
    )
    assert arrival[0] is not returns[0], (
        "arrival and return are the SAME assertion; one assertion cannot fail two ways, so one "
        "of the two properties is not being checked"
    )
    assert ARRIVAL_FAILURE_PREFIX not in message_text(returns[0]), (
        "the RETURN failure message also contains the ARRIVAL prefix; the two must be "
        "distinguishable in a log"
    )
    assert RETURN_FAILURE_PREFIX not in message_text(arrival[0]), (
        "the ARRIVAL failure message also contains the RETURN prefix; the two must be "
        "distinguishable in a log"
    )
    # The arrival assert must come first: a return checked before arrival would pass trivially
    # on a game that never left the start screen.
    assert arrival[0].lineno < returns[0].lineno, (
        "the RETURN assertion is written before the ARRIVAL assertion, so it would be satisfied "
        "by a game that never entered the scenario screen at all"
    )

    attribute_calls = {
        n.func.attr for n in ast.walk(func)
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
    }
    name_calls = {
        n.func.id for n in ast.walk(func)
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
    }
    assert "await_screen" in attribute_calls, (
        "G8 no longer reads guiScreen out of the running game; whatever it asserts now cannot "
        "distinguish 'entered and left the scenario screen' from 'the process is still alive'"
    )
    assert "confirm_row" in attribute_calls, "G8 no longer confirms any row"
    for forbidden in ("terminate", "kill", "send_signal", "close_window"):
        assert forbidden not in attribute_calls, (
            f"G8 calls {forbidden}(); ending the process proves nothing about whether the "
            "scenario screen can be entered and left"
        )
    for helper in ("assert_no_surviving_game_processes", "assert_clean_exit"):
        assert helper in name_calls, f"G8 never calls {helper}()"

    # Every row this file drives must be a NAMED derived constant - no literal may creep into the
    # navigation, which is what makes the derivation load-bearing rather than decorative.
    allowed_rows = {"SCENARIO_ROW", "SCENARIO_EXIT_ROW", "EXIT_GAME_ROW"}
    for node in ast.walk(func):
        if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)):
            continue
        if node.func.attr not in ("confirm_row", "select_row", "point_for_row"):
            continue
        for arg in node.args:
            assert isinstance(arg, ast.Name), (
                f"G8 drives a row with a non-constant expression {ast.dump(arg)}; rows must be "
                "named constants derived from the game's source, never literals"
            )
            assert arg.id in allowed_rows, (
                f"G8 drives row constant {arg.id!r}, which is not one of {sorted(allowed_rows)}. "
                "On the scenario screen only the exit row may be confirmed: any Scenario row "
                "would LOAD a save game."
            )


@pytest.mark.offline
def test_the_rows_are_derived_from_the_game_source_and_not_written_down():
    """The module constants must be CALLS to the derivation functions, not literals.

    Checked on this file's AST so that "derived from the game's own source" is a structural
    property rather than a claim in a docstring. This is the assertion that would catch someone
    replacing ``SCENARIO_ROW = scenario_screen_row()`` with ``SCENARIO_ROW = 22`` after a
    derivation started failing.
    """
    with open(os.path.join(HERE, os.path.basename(__file__)), "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read())
    assigned = {}
    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        target = node.targets[0]
        names = target.elts if isinstance(target, ast.Tuple) else [target]
        for index, name in enumerate(names):
            if isinstance(name, ast.Name):
                assigned[name.id] = (node.value, index, len(names))
    for constant, function in (
        ("SCENARIO_ROW", "scenario_screen_row"),
        ("SCENARIO_EXIT_ROW", "scenario_exit_row"),
        ("EXIT_GAME_ROW", "exit_row_dispatch"),
        ("EXPECTED_EXIT_CONTEXT", "exit_row_dispatch"),
    ):
        assert constant in assigned, f"{constant} is no longer assigned at module level"
        value, _index, _count = assigned[constant]
        assert isinstance(value, ast.Call) and isinstance(value.func, ast.Name), (
            f"{constant} is no longer the result of a call; a hardcoded row is exactly what this "
            "bead forbids, because a renumbered menu would then confirm the wrong row silently"
        )
        assert value.func.id == function, (
            f"{constant} is derived by {value.func.id}(), not {function}()"
        )
    # And the derivations must still be reading the game, not a cached copy.
    source = _read(os.path.join(HERE, os.path.basename(__file__)))
    for needed in (
        "pollDemoControls",
        "row_zero",
        "setGuiToScenarioScreen",
        "GUI_ROW_SCENARIOS_START",
        "startScenario",
    ):
        assert needed in source, f"the derivation no longer reads the game source for {needed!r}"


@pytest.mark.offline
def test_g8_never_reads_expansion_content():
    """G8 must never open, name or download expansion content.

    The repository rule is absolute. Checked on EXECUTABLE strings only - docstrings are blanked
    first, since this guard's prose has to name the extensions it forbids - and this guard's own
    body is excluded for the same reason. ``OO_ADDITIONALADDONSDIRS`` is exempt by exact name: it
    is what adds this session's throwaway debugConfig.plist root, which contains that plist and
    nothing else.
    """
    tree = ast.parse(_read(os.path.join(HERE, os.path.basename(__file__))))
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
                and node.name == "test_g8_never_reads_expansion_content")
    ]
    assert len(scanned) == len(tree.body) - 1, (
        "this guard could not find itself to exclude; it has been renamed"
    )
    addons_env = "OO_ADDITIONALADDONSDIRS"
    for node in scanned:
        for child in ast.walk(node):
            if not (isinstance(child, ast.Constant) and isinstance(child.value, str)):
                continue
            if child.value == addons_env:
                continue
            lowered = child.value.lower()
            for forbidden in (".oxz", ".oxp", "addons"):
                assert forbidden not in lowered, (
                    f"G8 has an executable string {child.value!r} naming {forbidden!r}: this "
                    "tier must never read expansion content"
                )
