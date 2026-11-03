"""Keyboard steps: the tutorial walkthrough (T1) and anything else about player input.

A new step family, and therefore a seam (ADR-0018 section 5): the rest of the tier drives the game
only through JS, and these steps PRESS KEYS (keyboard.py) and read the effect back over the
console. Every observable is JS that already exists - nothing here adds a native property:

* ``worldScripts["oolite-tutorial"].$tutorialStage`` / ``$tutorialSubstage`` - the tutorial's own
  progress counters (Resources/Scripts/oolite-tutorial.js ``_nextItem`` / ``_nextSection``).
* ``player.ship.viewDirection`` - VIEW_FORWARD, VIEW_AFT, VIEW_PORT, VIEW_STARBOARD, VIEW_CUSTOM.
* ``guiScreen`` and ``mission.screenID`` - the screen the game is showing, as G5/G8 read it.

The tutorial is driven along a path a player can take. Enter answers its opening mission screen;
``n`` (activate equipment) is the tutorial controls' "next"; ``b`` then ``n`` is their "skip this
lesson" (oolite-tutorial-equipment.js: mode 1 calls ``_nextSection``). The challenge lessons -
flight, lasers, missiles, combat, docking, navigation - need flying that a key script cannot
honestly do, and they are left by that skip, which is itself a control under test.

Every wait is a poll for a condition, never a fixed sleep, and every press that is supposed to
move the tutorial is checked to have moved it: a walkthrough that pressed keys into a window that
ignored them must fail, not reach the end of the feature file.
"""

import time

from pytest_bdd import given, when, then, parsers

from keyboard import GameKeyboard

TUTORIAL_SAVE = "Resources/Scenarios/oolite-tutorial.oolite-save"

# The tutorial draws nothing at random that this scenario asserts on; the seed only keeps the
# run's RANROT draws (asteroid placement in lesson 2) the same from run to run.
TUTORIAL_SEED = 20261027

# Loading the save and reaching the opening mission screen on a software renderer.
LOAD_TIMEOUT_SECONDS = 60
# How long one press has to show its effect. A press is sampled on the next frame, and a frame on
# llvmpipe with the tutorial's asteroid field up can take a good fraction of a second.
EFFECT_TIMEOUT_SECONDS = 10
POLL_SECONDS = 0.25
# Bringing the ship to a stop with "s" held: from full speed it takes a few seconds.
STOP_TIMEOUT_SECONDS = 30
# Bound on presses within one lesson. The largest lesson has 25 substages (oolite-tutorial.js
# $tutorialStages); a lesson that needs more than this is not advancing.
MAX_PRESSES_PER_LESSON = 40

TUTORIAL_JS = 'worldScripts["oolite-tutorial"]'
PROGRESS_JS = (
    "(function(){ var t = %s;"
    " return t.$tutorialStage + ' ' + t.$tutorialSubstage; })()" % TUTORIAL_JS
)


def _js_string(value):
    return '"%s"' % str(value).replace("\\", "\\\\").replace('"', '\\"')


def progress(world):
    """(stage, substage) of the tutorial, as the script itself counts them."""
    stage, substage = world.console.evaluate(PROGRESS_JS).split()
    return int(stage), int(substage)


def wait_for(read, wanted, timeout=EFFECT_TIMEOUT_SECONDS):
    """Poll ``read()`` until it returns ``wanted``; return the last value seen either way."""
    deadline = time.time() + timeout
    value = read()
    while value != wanted and time.time() < deadline:
        time.sleep(POLL_SECONDS)
        value = read()
    return value


def advance(world):
    """Press the tutorial's "next" once and require the tutorial to move.

    Returns the new (stage, substage). Raises when the press changed nothing: either the key
    never arrived, or the tutorial refused it (a gated step, ``$advanceByEquipment`` false).

    The key is HELD until the tutorial moves rather than tapped for a fixed time. With lesson 2's
    asteroid field up, llvmpipe draws only a few frames a second, and a fixed-length tap was
    still lost between two polls (T1, lesson 2 step 4). Holding cannot advance twice:
    activate_equipment_pressed (PlayerEntityControls.cpp) latches, so activated() fires once
    per press however long the key stays down.
    """
    before = progress(world)
    world.keyboard.hold_until("n", lambda: progress(world) != before, EFFECT_TIMEOUT_SECONDS)
    after = progress(world)
    if after == before:
        raise AssertionError(
            f"pressing 'n' (activate equipment) left the tutorial at lesson {before[0]} step "
            f"{before[1]}; the key was not delivered or the tutorial did not accept it"
        )
    return after


# --- Given ---------------------------------------------------------------------------------


@given("the tutorial is loaded")
def tutorial_is_loaded(world):
    """Launch the game straight into the tutorial scenario and wait for its first screen.

    ``-load`` of the scenario's own save (Resources/Config/scenarios.plist) is exactly what
    choosing "Tutorial" on the scenario screen does, minus the menu navigation that G8 already
    covers. The save sets missionVariables.oolite_tutorial, so the tutorial script activates and
    opens its welcome mission screen while the player is still docked.
    """
    world.start(TUTORIAL_SEED, load_save=TUTORIAL_SAVE)
    world.keyboard = GameKeyboard(world.console._proc.pid)
    screen = wait_for(lambda: world.console.evaluate("mission.screenID"),
                      "oolite-tutorial-0-0", timeout=LOAD_TIMEOUT_SECONDS)
    assert screen == "oolite-tutorial-0-0", (
        f"the tutorial's welcome screen never opened (mission.screenID is {screen!r}); "
        "the tutorial script did not start"
    )
    assert progress(world) == (0, 0)


# --- When ----------------------------------------------------------------------------------


@when(parsers.parse('I press "{key}"'))
def press_key(world, key):
    world.keyboard.press(key)


@when("I advance the tutorial")
def advance_tutorial(world):
    advance(world)


@when(parsers.parse("I advance the tutorial to lesson {stage:d} step {substage:d}"))
def advance_tutorial_to(world, stage, substage):
    """Press "next" until the tutorial is at exactly (stage, substage), every press checked."""
    wanted = (stage, substage)
    now = progress(world)
    for _ in range(MAX_PRESSES_PER_LESSON):
        if now == wanted:
            return
        if now > wanted:
            raise AssertionError(f"advanced past lesson {stage} step {substage} "
                                 f"to lesson {now[0]} step {now[1]}")
        now = advance(world)
    assert now == wanted, (f"lesson {stage} step {substage} not reached in "
                           f"{MAX_PRESSES_PER_LESSON} presses (at {now})")


@when(parsers.parse("I advance through lesson {stage:d}"))
def advance_through_lesson(world, stage):
    """Press "next" through every remaining step of a lesson until the next one begins."""
    now = progress(world)
    assert now[0] == stage, f"expected to be in lesson {stage}, tutorial is at {now}"
    for _ in range(MAX_PRESSES_PER_LESSON):
        now = advance(world)
        if now[0] != stage:
            break
    assert now == (stage + 1, 0), (
        f"finishing lesson {stage} should start lesson {stage + 1} at step 0, "
        f"tutorial is at lesson {now[0]} step {now[1]}"
    )


@when("I skip to the next lesson")
def skip_lesson(world):
    """The tutorial controls' own skip: "b" selects next-section mode, "n" acts on it."""
    before = progress(world)
    # "b" has no JS-visible effect (the controls' $mode lives on the equipment script, not in
    # worldScripts), so it is tapped; a lost "b" makes the "n" a plain next-item and the
    # assertion below names it. "n" is held until the tutorial moves, as in advance().
    world.keyboard.press("b")
    world.keyboard.hold_until("n", lambda: progress(world) != before, EFFECT_TIMEOUT_SECONDS)
    after = progress(world)
    assert after == (before[0] + 1, 0), (
        f"'b' then 'n' should skip from lesson {before[0]} to lesson {before[0] + 1} step 0, "
        f"tutorial is at lesson {after[0]} step {after[1]}"
    )


@when("I bring the ship to a stop")
def bring_ship_to_stop(world):
    """Hold "s" (decrease speed) until the ship reports itself stopped.

    Lesson 2 refuses to start until the ship is stationary (``__stage2sub1``: speed > 0.1 puts
    the step back), so this is a precondition the tutorial itself imposes - and a key under test.
    """
    def stopped():
        return float(world.console.evaluate("player.ship.speed")) <= 0.1

    assert world.keyboard.hold_until("s", stopped, STOP_TIMEOUT_SECONDS), (
        f"holding 's' did not stop the ship within {STOP_TIMEOUT_SECONDS}s "
        f"(speed {world.console.evaluate('player.ship.speed')})"
    )


# --- Then ----------------------------------------------------------------------------------


@then(parsers.parse("the tutorial is at lesson {stage:d} step {substage:d}"))
def tutorial_is_at(world, stage, substage):
    now = wait_for(lambda: progress(world), (stage, substage))
    assert now == (stage, substage), (
        f"expected lesson {stage} step {substage}, tutorial is at lesson {now[0]} step {now[1]}"
    )


@then(parsers.parse('the view is "{view}"'))
def view_is(world, view):
    now = wait_for(lambda: world.console.evaluate("player.ship.viewDirection"), view)
    assert now == view, f"expected view {view}, player.ship.viewDirection is {now}"


def _assert_screen(world, screen):
    now = wait_for(lambda: world.console.evaluate("guiScreen"), screen)
    assert now == screen, f"expected screen {screen}, guiScreen is {now}"


@then(parsers.parse('the screen is "{screen}"'))
def screen_is(world, screen):
    _assert_screen(world, screen)


@then("the player is in flight")
def player_in_flight(world):
    """Launched and clear of the launch tunnel: docked is false and the main view is up.

    Waiting for GUI_SCREEN_MAIN and the tutorial's post-launch step matters: view keys pressed
    while the launch is still playing are not acted on (measured: a "2" pressed then was lost).
    """
    docked = wait_for(lambda: world.console.evaluate("player.ship.docked"), "false")
    assert docked == "false", "the player never launched"
    _assert_screen(world, "GUI_SCREEN_MAIN")


@then("the tutorial end screen is shown")
def end_screen_is_shown(world):
    # mission.screenID keeps naming the last mission screen after it closes, so it only means
    # something together with guiScreen.
    _assert_screen(world, "GUI_SCREEN_MISSION")
    screen_id = wait_for(lambda: world.console.evaluate("mission.screenID"),
                         "oolite-tutorial-end")
    assert screen_id == "oolite-tutorial-end", (
        f"expected the tutorial's end screen, mission.screenID is {screen_id!r}"
    )
