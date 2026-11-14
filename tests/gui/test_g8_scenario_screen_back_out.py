"""G8 - the scenario screen, entered from start-screen row 22 and left again by its row 1.

G8: "Launch -> confirm row 22 -> confirm row 1 (``Return to Menu``) ->
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
  concurrent GUI tests is a guaranteed merge conflict, and nothing below is needed by any other
  test.

WHAT "ROW 1" ACTUALLY IS ON THE SCENARIO SCREEN. DERIVED, NOT ASSUMED.
---------------------------------------------------------------------
The story says "confirm row 1 (``Return to Menu``)" and that is worth checking rather than
trusting, because the three screens G5 round-trips leave by three DIFFERENT mechanisms (a Space
key, a ``Back`` row, an ``_EXIT`` row). On this screen it IS a numbered, addressable row, and the
number is fixed by how the game lays the screen out (``SCENARIO_EXIT_ROW`` below):

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

    python3 -m pytest oolite-dev/tests/gui/test_g8_scenario_screen_back_out.py -x -q

Needs the desktop: a real window, unlocked and logged in, left alone while it runs.
The game is launched through the ``game`` fixture; this file launches nothing of its own.
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

# The screen the tier starts on and must come back to (PlayerEntity.m:10070).
START_SCREEN = "GUI_SCREEN_INTRO1"
# The screen -setGuiToScenarioScreen: assigns (PlayerEntityLoadSave.m:262).
SCENARIO_SCREEN = "GUI_SCREEN_NEWGAME"
# Where a mis-aimed confirm on the scenario screen would land instead: -startScenario answering
# YES loads a save game, and the load path ends at -setGuiToStatusScreen. Named so that a failure
# of the RETURN assertion can report the difference between "it did not come back" and "it started
# a scenario", which are completely different bugs.
SCENARIO_STARTED_SCREEN = "GUI_SCREEN_STATUS"

# The text the story calls the scenario screen's back-out row.
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


# --- the rows -------------------------------------------------------------------------------------


def _read(path):
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        return handle.read()


# The start-screen and scenario-screen rows are written down rather than read out of the game's
# source, because the GUI is not changed during the migration.
# The start-screen row that opens the scenario screen (PlayerEntityControls -pollDemoControls).
SCENARIO_ROW = 22
# The scenario screen's ` Return to Menu ` row: GUI_ROW_SCENARIOS_START (3) minus the 2 rows
# -setGuiToScenarioScreen: lays it out above that.
SCENARIO_EXIT_ROW = 1
# ` Exit Game ` on the start screen, and the context the game logs when it is confirmed.
EXIT_GAME_ROW = 27
EXPECTED_EXIT_CONTEXT = "Exit Game selected on start screen"


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
                # packet. Every read is deadline-guarded by select(), so blocking is safe.
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

    1. PRECONDITION - the game is on the start screen, so the rows describe what is on
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
        f"the game is on {seen}, not {START_SCREEN}, so the rows of the start-screen "
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
    # G9 hygiene, with the launch-time defaults mark the fixture recorded.
    assert_clean_exit(game)
    # And the shutdown ran to its last line, for the START-SCREEN ` Exit Game ` row.
    assert_shutdown_path_completed(game, expected_context=EXPECTED_EXIT_CONTEXT)


# --- offline guards: the claims this file rests on -----------------------------------------------


@pytest.mark.offline
def test_g8_asserts_arrival_and_return_as_separate_properties():
    """THE ANTI-DECAY GUARD: two assertions, two messages, and the game asked both times.

    Read from this file's own AST, never its text: a docstring or a comment containing
    "ARRIVAL FAILED" is not an assertion, and a sibling test's substring guard was held green by
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

    # Every row this file drives must be a NAMED constant - no literal may creep into the
    # navigation.
    allowed_rows = {"SCENARIO_ROW", "SCENARIO_EXIT_ROW", "EXIT_GAME_ROW"}
    for node in ast.walk(func):
        if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)):
            continue
        if node.func.attr not in ("confirm_row", "select_row", "point_for_row"):
            continue
        for arg in node.args:
            assert isinstance(arg, ast.Name), (
                f"G8 drives a row with a non-constant expression {ast.dump(arg)}; rows must be "
                "named constants, never literals"
            )
            assert arg.id in allowed_rows, (
                f"G8 drives row constant {arg.id!r}, which is not one of {sorted(allowed_rows)}. "
                "On the scenario screen only the exit row may be confirmed: any Scenario row "
                "would LOAD a save game."
            )


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
