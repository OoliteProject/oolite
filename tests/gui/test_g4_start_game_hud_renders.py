"""G4 - start a game: confirm ` Start New Commander `, then ` Normal Start `, and the HUD renders.

docs/phases/0-gui-tier.md G4: "Launch -> confirm row 22 -> land on scenario screen -> confirm row 3
(`Normal Start`) -> wait for the cockpit -> assert the HUD renders -> exit". The end-to-end smoke
test: it is the only one in this tier that leaves the start screen at all, so it is the only one
that can catch "the menu works but the game never starts".

Written the way test_g3_exit_via_window_close.py is written - SHORT, and reusing everything
conftest.py already owns (the desktop lock, the readiness gate, DPI awareness, row->point, the
process-table survivor check, the G9 hygiene assert). This file launches nothing of its own.

HOW THE ROWS ARE ADDRESSED, AND WHY AN INDEX IS UNAVOIDABLE
-----------------------------------------------------------
The source offers NO symbolic name for either row this test presses, and that is a fact about the
game rather than a shortcut here:

* ``PlayerEntity.m:9912`` - the start screen is built with a bare ``int initialRow = 22;`` and six
  successive ``++row``. The rows carry keys (``Start:22`` ... ``Start:27``) but the KEYS ARE NEVER
  READ: ``PlayerEntityControls.m:4950-4982`` dispatches on ``[gui selectedRow] == N+row_zero`` with
  a second bare ``int row_zero = 21``. There is no enum, no #define, and no key lookup to name.
* ``PlayerEntity.h:164`` DOES name the scenario screen's first row -
  ``GUI_ROW_SCENARIOS_START = 3`` - and ``PlayerEntityLoadSave.m:214`` starts the scenario list
  there, so ` Normal Start ` (scenarios.plist entry 0) is addressed by THAT constant, mirrored
  here, rather than by the literal 3.

So one row is semantic and one cannot be. The brief's fallback is therefore what this file does for
BOTH presses: **assert which screen you are on before pressing**. ``assert_on_start_screen`` and
``assert_on_scenario_screen`` read the game's own rendered frame and check the row OCCUPANCY
PATTERN each screen's builder produces - the start screen fills rows 22-27 and leaves row 1 empty;
the scenario screen fills row 1 (` Return to Menu `, ``start_row - 2``) and leaves 22-27 empty. A
layout change that moved either menu therefore fails LOUDLY, by name, instead of silently
double-clicking whatever now sits at that index.

WHAT "THE HUD RENDERS" IS ASSERTED ON
-------------------------------------
Not "the process is alive", not "a window exists", and not a desktop screenshot: the observable is
the SCANNER GRID ELLIPSE in a frame THE GAME ITSELF read back out of its own framebuffer
(``MyOpenGLView.m:1194-1214`` ``glReadPixels`` -> PNG, into this run's private
``$OO_SNAPSHOTSDIR``, which conftest points at pytest's ``tmp_path``).

That ellipse is uniquely attributable to a rendered HUD, by a call chain each link of which has
exactly ONE call site in the tree (verified by grep over src/ and Resources/):

    Universe.m:5239   [theHUD renderHUD]          <- the only renderHUD: call site
    HeadUpDisplay.m:832  [self drawDials]         <- the only drawDials call site
    HeadUpDisplay.m:1235 drawScannerGrid(...)     <- the only drawScannerGrid call site,
                                                     inside -drawScanner:, which is reached only
                                                     through the "drawScanner:" selector in
                                                     Resources/Config/hud.plist:21

and ``Universe.m:5225-5232`` skips ``renderHUD`` outright for ``STATUS_START_GAME``, which is the
status the game sits in for the whole of the menu flow. So red pixels on that ellipse cannot be
produced by a game that never left the menu.

The ellipse's position is COMPUTED, not image-matched (docs/phases/0-gui-tier.md, "compute, don't
image-match"): hud.plist's ``x=0, y=68, y_origin=-1, width=288`` through the projection in
``MyOpenGLView.m:519-527``. And it is asserted DIFFERENTIALLY inside the one run - the identical
measurement is taken on the start screen and on the scenario screen first, where it must be empty -
so a stray red thing on the desktop, a leftover file, or a broken measurement fails the test rather
than passing it.

    python3 -m pytest upstream/oolite/tests/gui/test_g4_start_game_hud_renders.py -x -q

Needs the desktop: a real window, unlocked and logged in (ADR-0017). It takes tools/gui-lock for
the duration, via the ``game`` fixture - this file launches nothing of its own.
"""

import ast
import os
import time

import pytest

from conftest import (
    MAIN_GUI_PIXEL_HEIGHT,
    PINNED_CLIENT_SIZE,
    assert_clean_exit,
    assert_no_surviving_game_processes,
    row_to_point,
)

HERE = os.path.dirname(os.path.abspath(__file__))

# PlayerEntity.m:9912 `int initialRow = 22` - ` Start New Commander `, the first start-screen row.
# A literal because the source has no name for it (see the module docstring); every press of it is
# guarded by assert_on_start_screen.
START_NEW_COMMANDER_ROW = 22
# PlayerEntity.m:9912-9954 lay six rows out from initialRow; PlayerEntityControls.m:4982 dispatches
# ` Exit Game ` at 6+row_zero == 27.
EXIT_GAME_ROW = 27
# PlayerEntity.h:164 GUI_ROW_SCENARIOS_START = 3, where PlayerEntityLoadSave.m:214-247 starts the
# scenario list. scenarios.plist entry 0 is ` Normal Start `. THIS one is semantic.
GUI_ROW_SCENARIOS_START = 3
NORMAL_START_ROW = GUI_ROW_SCENARIOS_START
# PlayerEntityLoadSave.m:230 puts ` Return to Menu ` two rows above the list.
SCENARIO_EXIT_ROW = GUI_ROW_SCENARIOS_START - 2

# Resources/Config/hud.plist:19-28 - the scanner dial, in the game's virtual HUD coordinates.
SCANNER_X = 0.0
SCANNER_Y = 68.0
SCANNER_Y_ORIGIN = -1
SCANNER_WIDTH = 288.0
# MyOpenGLView.m:519-527: at exactly 4:3 the else-branch applies, so y_offset is 240 and the
# virtual-to-pixel scale is client_width/640.
VIRTUAL_VIEW_WIDTH = 640.0
Y_OFFSET = 240.0

# A pixel is "scanner red" at rgb_color (1.0, 0.0, 0.0): bright red, and not white text or a
# yellow menu row.
RED_MIN = 100
NON_RED_MAX = 70
# Half-extent of the probe box around a computed arc point. The ellipse is 2*lineWidth thick and
# the arc is nearly vertical there, so a few pixels of slack either way still lands on it without
# the box ever reaching another dial (the nearest, the forward shield bar, is 56 virtual units -
# 84 pixels - away).
PROBE_HALF = 7

# A pressed row whose screen never changes means the confirm did not take. Startup to a flyable
# cockpit is slower than G1/G3's exit: measured 6-14s on this build.
SCREEN_CHANGE_TIMEOUT_SECONDS = 30
EXIT_TIMEOUT_SECONDS = 10
# How long to hold the snapshot key. PlayerEntityControls.m:993-1006 latches on a HELD key seen by
# a poll, and a tap between two polls is simply never seen.
SNAPSHOT_HOLD_SECONDS = 0.5
SNAPSHOT_TIMEOUT_SECONDS = 30


# --- the game's own frame -----------------------------------------------------------------------


def capture_frame(game, timeout=SNAPSHOT_TIMEOUT_SECONDS):
    """Make the GAME read its own framebuffer back, and return the PNG's path.

    ``PlayerEntityControls.m:993-1006`` -> ``MyOpenGLView.m:1142-1214``: the snapshot key runs
    glReadPixels over the live framebuffer and writes a PNG into ``$OO_SNAPSHOTSDIR``, which
    conftest sets to this test's tmp_path. Nothing on the desktop can contribute to that image,
    which is exactly why it is used here instead of pyautogui.screenshot().
    """
    import pyautogui

    before = _frames(game)
    deadline = time.time() + timeout
    while time.time() < deadline:
        assert game.proc.poll() is None, "the game exited while a frame was being captured"
        game.assert_focused()
        pyautogui.keyDown("multiply")
        time.sleep(SNAPSHOT_HOLD_SECONDS)
        pyautogui.keyUp("multiply")
        time.sleep(1.0)
        new = sorted(set(_frames(game)) - set(before))
        if new:
            return os.path.join(game.output_dir, new[0])
    raise AssertionError(
        f"the game wrote no snapshot within {timeout}s of the snapshot key being held. Its "
        f"snapshot directory is {game.output_dir} (OO_SNAPSHOTSDIR, conftest.GameWindow._env); "
        "without a frame this test cannot tell a rendered HUD from a blank window"
    )


def _frames(game):
    return sorted(n for n in os.listdir(game.output_dir) if n.lower().endswith(".png"))


def _pixels(path):
    from PIL import Image

    with Image.open(path) as handle:
        image = handle.convert("RGB")
        return image.load(), image.size


def scanner_arc_points(client_size=PINNED_CLIENT_SIZE):
    """The two extreme points of the scanner ellipse, in client pixels. COMPUTED, never matched.

    hud.plist's dial is centred at (x, y + y_offset*y_origin) in virtual units with the origin at
    the view centre and +y up; MyOpenGLView.m:525-527 makes the scale client_width/640 and
    y_offset 240 for a 4:3 client. The ellipse's widest points are +/- width/2 from that centre.
    """
    width, height = client_size
    assert abs(width / height - 4.0 / 3.0) < 1e-9, (
        f"the pinned client size {client_size} is not 4:3, so MyOpenGLView.m:519-527 takes the "
        "OTHER projection branch and these coordinates would be wrong"
    )
    scale = width / VIRTUAL_VIEW_WIDTH
    centre_x = width / 2.0 + SCANNER_X * scale
    centre_y = height / 2.0 - (SCANNER_Y + Y_OFFSET * SCANNER_Y_ORIGIN) * scale
    half = SCANNER_WIDTH / 2.0 * scale
    return (centre_x - half, centre_y), (centre_x + half, centre_y)


def count_scanner_red(path):
    """Red pixels on BOTH extreme arcs of the scanner ellipse, as ``(left, right)``."""
    pixels, (width, height) = _pixels(path)
    counts = []
    for x, y in scanner_arc_points((width, height)):
        found = 0
        for py in range(int(y) - PROBE_HALF, int(y) + PROBE_HALF + 1):
            for px in range(int(x) - PROBE_HALF, int(x) + PROBE_HALF + 1):
                if not (0 <= px < width and 0 <= py < height):
                    continue
                r, g, b = pixels[px, py]
                if r >= RED_MIN and g <= NON_RED_MAX and b <= NON_RED_MAX:
                    found += 1
        counts.append(found)
    return tuple(counts)


# A row counts as "has text on it" above this many lit pixels. Measured on this build: the
# faintest real menu row (` Exit Game `) lights ~480 and the densest non-text artefact that can
# land on a row band - the GUI mouse crosshair, which stays wherever the last click left it -
# lights ~50. 200 is between them with room either side, and deliberately NOT 1: a threshold of
# "any lit pixel" would call the cursor a menu row and mis-identify the screen.
ROW_OCCUPIED_THRESHOLD = 200


def row_is_occupied(path, row, threshold=ROW_OCCUPIED_THRESHOLD):
    """Does GUI ``row`` have text drawn on it in this frame?

    The row's y comes from conftest.row_to_point - the SAME grid maths the clicks use, so a row
    this says is occupied is a row a click would land on.
    """
    pixels, (width, height) = _pixels(path)
    _, y = row_to_point(row, (0, 0, width, height))
    half = int(MAIN_GUI_PIXEL_HEIGHT / 480.0 * 6)
    lit = 0
    for py in range(max(0, y - half), min(height - 1, y + half) + 1):
        for px in range(width):
            r, g, b = pixels[px, py]
            if r + g + b > 120:
                lit += 1
    return lit >= threshold


# --- screen identity ----------------------------------------------------------------------------


def assert_on_start_screen(path):
    """The frame must be the start screen ``setupStartScreenGui`` builds, not some other menu.

    PlayerEntity.m:9894-9960 writes SIX consecutive rows from 22 and writes nothing above row 15,
    so rows 22-27 are all occupied and row 1 is empty. The scenario screen is the exact inverse.
    """
    empty = [row for row in range(START_NEW_COMMANDER_ROW, EXIT_GAME_ROW + 1)
             if not row_is_occupied(path, row)]
    assert not empty, (
        f"this is not the start screen: rows {empty} are blank, but setupStartScreenGui "
        f"(PlayerEntity.m:9894-9960) fills every row from {START_NEW_COMMANDER_ROW} to "
        f"{EXIT_GAME_ROW}. Confirming row {START_NEW_COMMANDER_ROW} here would double-click "
        f"whatever now occupies it. Frame: {path}"
    )
    assert not row_is_occupied(path, 1), (
        "this is not the start screen: row 1 has text on it, and setupStartScreenGui writes "
        f"nothing above row 15. This looks like the scenario screen, whose ` Return to Menu ` "
        f"sits on row {SCENARIO_EXIT_ROW}. Frame: {path}"
    )


def assert_on_scenario_screen(path):
    """The frame must be the scenario screen ``setGuiToScenarioScreen:`` builds.

    PlayerEntityLoadSave.m:207-247: ` Return to Menu ` at ``start_row - 2`` (row 1), the scenario
    list from ``GUI_ROW_SCENARIOS_START`` (row 3), and nothing anywhere near the start screen's
    rows 22-27.
    """
    assert row_is_occupied(path, SCENARIO_EXIT_ROW), (
        f"confirming ` Start New Commander ` did not reach the scenario screen: row "
        f"{SCENARIO_EXIT_ROW} is blank, but setGuiToScenarioScreen: "
        f"(PlayerEntityLoadSave.m:230) always writes ` Return to Menu ` there. Frame: {path}"
    )
    assert row_is_occupied(path, NORMAL_START_ROW), (
        f"the scenario list is empty: row {NORMAL_START_ROW} (GUI_ROW_SCENARIOS_START, "
        f"PlayerEntity.h:164) has no text, so there is no ` Normal Start ` to confirm. "
        f"Frame: {path}"
    )
    occupied = [row for row in range(START_NEW_COMMANDER_ROW, EXIT_GAME_ROW + 1)
                if row_is_occupied(path, row)]
    assert not occupied, (
        f"this still looks like the START screen: rows {occupied} have text on them, and the "
        f"scenario screen writes nothing below row {GUI_ROW_SCENARIOS_START + 14}. Frame: {path}"
    )


def _await_screen(game, check, what):
    """Capture frames until ``check`` accepts one, then return its path.

    The two confirms are asynchronous - the game acts on the double-click on its next poll and
    then loads - so a single frame taken immediately after the click would be a race. The LAST
    failure is re-raised, so the message names what never appeared rather than "timed out".
    """
    deadline = time.time() + SCREEN_CHANGE_TIMEOUT_SECONDS
    last = None
    while True:
        frame = capture_frame(game)
        try:
            check(frame)
            return frame
        except AssertionError as exc:
            last = exc
        if time.time() >= deadline:
            raise AssertionError(
                f"{what} did not appear within {SCREEN_CHANGE_TIMEOUT_SECONDS}s. {last}"
            )
        time.sleep(1.0)


# --- the test -----------------------------------------------------------------------------------


def test_g4_start_game_hud_renders(game):
    """Menu -> scenario screen -> a flying ship with a HUD on it -> a clean exit."""
    assert game.proc.poll() is None, "the game exited before the test could start anything"
    game.assert_focused()

    # 1. We are on the start screen, and the HUD is NOT drawn here. The second half is what makes
    #    step 4 falsifiable: the same measurement, the same window, before the game exists.
    start_frame = _await_screen(game, assert_on_start_screen, "the start screen")
    assert count_scanner_red(start_frame) == (0, 0), (
        f"the scanner ellipse is already on screen at the MENU ({start_frame}). "
        "Universe.m:5225-5232 skips renderHUD for STATUS_START_GAME, so either the probe boxes "
        "are mis-computed or something else is drawing red there - and in either case a red "
        "reading after the game starts would prove nothing"
    )

    # 2. ` Start New Commander `. PlayerEntityControls.m:4961-4965 - selectedRow == 1+row_zero
    #    goes to setGuiToScenarioScreen:0.
    game.select_row(START_NEW_COMMANDER_ROW)
    game.confirm_row(START_NEW_COMMANDER_ROW)

    # 3. The scenario screen, identified by ITS layout, and still no HUD.
    scenario_frame = _await_screen(game, assert_on_scenario_screen, "the scenario screen")
    assert count_scanner_red(scenario_frame) == (0, 0), (
        f"the scanner ellipse is on screen at the SCENARIO screen ({scenario_frame}), which is "
        "still STATUS_START_GAME and must not render a HUD"
    )

    # 4. ` Normal Start `, and THE G4 CLAIM: the HUD renders. Both extreme arcs, because one
    #    could conceivably be clipped or overdrawn while the other is not, and the claim is that
    #    the ELLIPSE is there.
    game.select_row(NORMAL_START_ROW)
    game.confirm_row(NORMAL_START_ROW)
    deadline = time.time() + SCREEN_CHANGE_TIMEOUT_SECONDS
    flight_frame = None
    seen = None
    while time.time() < deadline:
        flight_frame = capture_frame(game)
        seen = count_scanner_red(flight_frame)
        if seen[0] and seen[1]:
            break
        time.sleep(1.0)
    left, right = scanner_arc_points()
    # Re-measured INSIDE the assert, off the frame on disk: the claim is about that PNG, and the
    # AST guard below requires the call to be reached by an assert statement rather than by a
    # loop whose result a later edit could quietly stop checking.
    assert flight_frame is not None and all(count_scanner_red(flight_frame)), (
        f"THE HUD DID NOT RENDER. After confirming ` Normal Start ` (row {NORMAL_START_ROW}, "
        f"GUI_ROW_SCENARIOS_START) the game's own framebuffer readback {flight_frame} has "
        f"{seen} red pixels at the two extreme points of the scanner ellipse "
        f"({left} and {right}, computed from hud.plist:19-28 through MyOpenGLView.m:519-527); "
        "both must be non-zero. drawScannerGrid (HeadUpDisplay.m:1235) is reached only from "
        "-drawScanner: <- -drawDials (:832) <- -renderHUD <- Universe.m:5239, and "
        "Universe.m:5225-5232 skips all of it while the player is still STATUS_START_GAME - so "
        "an empty ellipse means the game never left the start-game state and no cockpit was "
        f"reached within {SCREEN_CHANGE_TIMEOUT_SECONDS}s."
    )

    # 5. Exit. Not through the menu - there is no menu any more - but the way a user closes a
    #    running game, which is the path G3 pins (SDL_EVENT_QUIT, MyOpenGLView+Input.m:660-664).
    hwnd = game.close_window()
    try:
        returncode = game.proc.wait(timeout=EXIT_TIMEOUT_SECONDS)
    except Exception:
        pytest.fail(
            f"the game was still running {EXIT_TIMEOUT_SECONDS}s after WM_CLOSE was posted to "
            f"hwnd {hwnd} with a game in progress"
        )
    assert returncode == 0, f"the game exited with {returncode}, not 0"

    # 6. No orphan, and G9 hygiene - asked of the OS process table and of the fixture, as G3 does.
    assert_no_surviving_game_processes(game.proc.pid)
    assert_clean_exit(game)


# --- guards: G4 must stay a HUD test, and must stay falsifiable ---------------------------------
#
# Offline, so they gate in a clean checkout with no build and no desktop.


@pytest.mark.offline
def test_the_scanner_probe_is_computed_from_the_hud_definition():
    """The probe points must match hud.plist and the projection, to the pixel.

    A transcription slip here would move the boxes onto empty space and G4 would report "the HUD
    did not render" forever, or - worse - onto a neighbouring red thing and report success for a
    HUD that never drew.
    """
    (lx, ly), (rx, ry) = scanner_arc_points((960, 720))
    assert (lx, ly) == (264.0, 618.0), f"left arc moved to {(lx, ly)}"
    assert (rx, ry) == (696.0, 618.0), f"right arc moved to {(rx, ry)}"
    assert ly == ry, "the two probes must sit on the same scan line"
    # Scaling the window scales the probe with it, rather than pinning a magic pixel.
    (hx, _), _ = scanner_arc_points((1280, 960))
    assert hx == 352.0, f"the probe does not scale with the client size: {hx}"
    with pytest.raises(AssertionError):
        scanner_arc_points((1280, 720))  # 16:9 takes the other projection branch


@pytest.mark.offline
def test_a_frame_with_no_scanner_scores_zero(tmp_path):
    """The red detector must actually be able to return zero, and to find the ellipse.

    Built here rather than committed as a fixture image: a golden PNG in the tree would be a
    second thing to keep in step with hud.plist.
    """
    from PIL import Image

    blank = tmp_path / "blank.png"
    Image.new("RGB", (960, 720), (0, 0, 0)).save(blank)
    assert count_scanner_red(str(blank)) == (0, 0)

    # Yellow menu text and white titles are NOT scanner red, even sitting on the probe.
    for colour in ((255, 255, 0), (255, 255, 255), (0, 200, 0)):
        decoy = Image.new("RGB", (960, 720), (0, 0, 0))
        for (x, y) in scanner_arc_points((960, 720)):
            for dy in range(-PROBE_HALF, PROBE_HALF + 1):
                for dx in range(-PROBE_HALF, PROBE_HALF + 1):
                    decoy.putpixel((int(x) + dx, int(y) + dy), colour)
        path = tmp_path / f"decoy{colour[0]}{colour[1]}{colour[2]}.png"
        decoy.save(path)
        assert count_scanner_red(str(path)) == (0, 0), f"{colour} was counted as scanner red"

    painted = Image.new("RGB", (960, 720), (0, 0, 0))
    for (x, y) in scanner_arc_points((960, 720)):
        for dy in range(-2, 3):
            painted.putpixel((int(x), int(y) + dy), (217, 0, 0))
    path = tmp_path / "painted.png"
    painted.save(path)
    assert count_scanner_red(str(path)) == (5, 5)


@pytest.mark.offline
def test_the_row_occupancy_threshold_separates_text_from_the_cursor(tmp_path):
    """A lit-pixel count must distinguish a menu row from the GUI mouse crosshair.

    This is a measured constant, not a taste: the crosshair is drawn wherever the last click left
    it and DOES land inside a row band (it put ~50 lit pixels on row 22 of a scenario-screen frame
    during development, which made the screen-identity check reject a correct screen). If the
    threshold ever drops near that, assert_on_scenario_screen starts failing on a healthy game.
    """
    from PIL import Image

    assert 60 < ROW_OCCUPIED_THRESHOLD < 400, (
        f"the row-occupancy threshold {ROW_OCCUPIED_THRESHOLD} is outside the measured gap "
        "between the GUI crosshair (~50 lit pixels in a row band) and the faintest real menu "
        "row (~480)"
    )
    blank = Image.new("RGB", (960, 720), (0, 0, 0))
    _, y = row_to_point(22, (0, 0, 960, 720))
    for dx in range(55):  # a crosshair-sized smudge, well under the threshold
        blank.putpixel((400 + dx, y), (120, 120, 255))
    sparse = tmp_path / "cursor.png"
    blank.save(sparse)
    assert not row_is_occupied(str(sparse), 22), "a cursor-sized smudge was read as a menu row"

    text = Image.new("RGB", (960, 720), (0, 0, 0))
    for dy in range(-5, 6):
        for dx in range(200):
            text.putpixel((380 + dx, y + dy), (255, 255, 0))
    dense = tmp_path / "text.png"
    text.save(dense)
    assert row_is_occupied(str(dense), 22), "a row full of text was not read as occupied"


@pytest.mark.offline
def test_g4_asserts_the_hud_and_both_screens_and_cannot_be_satisfied_by_liveness():
    """AST, not text: the docstring above names every symbol, so a grep would stay green.

    The defect class is oo-07s/oo-5rsa one level up - a guard a comment can satisfy. Each rule
    below therefore demands an ``assert`` STATEMENT that REACHES the named call.
    """
    with open(os.path.join(HERE, os.path.basename(__file__)), "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read())
    func = next(
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.FunctionDef) and node.name == "test_g4_start_game_hud_renders"
    )

    def asserts_calling(name):
        return [
            node
            for node in ast.walk(func)
            if isinstance(node, ast.Assert)
            and any(
                isinstance(child, ast.Call)
                and getattr(child.func, "id", getattr(child.func, "attr", None)) == name
                for child in ast.walk(node)
            )
        ]

    red = asserts_calling("count_scanner_red")
    assert len(red) >= 3, (
        "G4 must assert on count_scanner_red at least three times: zero on the start screen, "
        "zero on the scenario screen, and non-zero once the game is running. Found "
        f"{len(red)}. Without the two ZERO assertions the final one is not differential and a "
        "mis-computed probe that always reads red would pass."
    )
    calls = {
        getattr(node.func, "id", getattr(node.func, "attr", None))
        for node in ast.walk(func)
        if isinstance(node, ast.Call)
    }
    # The two screen checks are PASSED to _await_screen rather than called directly, so they are
    # Name loads, not Calls; both spellings count as "G4 still guards this press".
    named = calls | {
        node.id for node in ast.walk(func) if isinstance(node, ast.Name)
    }
    for required, why in (
        ("assert_on_start_screen", "the row 22 press must be guarded by the screen it is on"),
        ("assert_on_scenario_screen", "the row 3 press must be guarded by the screen it is on"),
    ):
        assert required in named, f"G4 no longer uses {required}(): {why}"
    for required, why in (
        ("select_row", "the rows must be reached by real mouse input"),
        ("confirm_row", "a selected row that is never confirmed starts no game"),
        ("assert_no_surviving_game_processes", "an orphaned oolite.exe is not a clean exit"),
        ("assert_clean_exit", "G9 hygiene is asserted after every test in this tier"),
    ):
        assert required in calls, f"G4 no longer calls {required}(): {why}"
    for forbidden in ("terminate", "kill", "send_signal"):
        assert forbidden not in calls, (
            f"G4 calls {forbidden}(); killing the process proves the OS can kill a process"
        )
    # The failure mode this whole file exists to avoid.
    liveness_only = [
        node
        for node in ast.walk(func)
        if isinstance(node, ast.Assert)
        and any(
            isinstance(child, ast.Attribute) and child.attr == "poll"
            for child in ast.walk(node)
        )
    ]
    assert len(liveness_only) <= 1, (
        "G4 leans on proc.poll() more than once. 'The process is alive' is not 'the HUD "
        "rendered'; the one permitted use is the precondition before any input is sent."
    )
