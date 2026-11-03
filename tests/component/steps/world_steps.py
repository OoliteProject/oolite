"""The step library. S2-S8 reuse these; adding a NEW step is a new interface, so it is a seam,
not fleet work - stop and file a bead (ADR-0018 section 5).

Every step drives the game through JS that already exists. Nothing here adds a native property:
assertions are built from countShipsWithRole, system.allShips and the entity/ship properties listed
in docs/phases/0-component-tier.md.
"""

import time

from pytest_bdd import given, when, then, parsers

# Ship AI thinks every 0.125 s (AI_THINK_INTERVAL, src/Core/AI.h:31). A "tick" in the scenario
# vocabulary is one of those decision intervals, which is what makes "within 900 ticks" mean
# roughly 120 AI decisions rather than 900 frames.
TICK_SECONDS = 0.125

# How often the run step asks the game for a count. Each round trip costs a console command, so
# polling far faster than the AI thinks buys nothing.
POLL_SECONDS = 0.5

# A save has to be loaded to get a running simulation; this one ships with the game.
SCENARIO_SAVE = "Resources/Scenarios/oolite-standard.oolite-save"

# Launching out of the station takes a few seconds of real time on a software renderer.
LAUNCH_TIMEOUT_SECONDS = 60

# system.addShips gives every ship nullAI.plist - an inert ship that never thinks, never acquires
# a target and never fires. Measured: two ships, 900 ticks, AIState GLOBAL throughout and full
# energy on both. A scenario about combat therefore has to install the role's real AI, which is
# what the system populator would have done. Names from ai_type in Resources/Config/shipdata.plist.
ROLE_AI = {
    "police": "oolite-policeAI.js",
    "pirate": "oolite-pirateAI.js",
    "trader": "oolite-traderAI.js",
    "shuttle": "oolite-shuttleAI.js",
}

# oo-sjvz DETERMINISM FIX (S1/S5/S6 flakiness, docs/fleet/LEARNINGS.md oo-qwk5/oo-rkm):
# system.addShips(role, ...) draws the ship TYPE at random (Universe.mm:4002 -newShipWithRole: ->
# :3951 -randomShipKeyForRoleRespectingConditions: -> OOShipRegistry.mm:304
# [[self probabilitySetForRole:role] randomObject]), so spawning "police" or "pirate" by role
# hands a component scenario a different ship class - with a different max_energy, weapon
# loadout and starting bounty - on every run, even at a pinned seed. Measured by oo-qwk5: ~24% of
# role-spawned pirates were not even legally attackable by police, because their random starting
# bounty fell below policeAI's fineThreshold() gate (oolite-priorityai.js:845,
# `50 - government*6`). That is what made S1/S5/S6 a coin flip unrelated to the code under test.
# Pinning fixes the draw, not combat: S6 asserts the police ship survives up to 900 ticks of a
# real-time 1-v-1 dogfight, which it sometimes loses whatever the hulls (oo-9aq4).
#
# The fix pins the SHIP KEY that addShips is actually asked for, using the literal "[shipKey]"
# form that OOShipRegistry.mm:1253 registers at probability 1.0 for every ship (no draw),
# entirely INSIDE the existing spawn steps' implementation - no .feature file changes and no new
# step text, since a step's WORDING is what every scenario's vocabulary and guardrails' test-unit
# classifier key off. Choosing which key backs a role is a fact about this test harness, not a
# new observation surface (ADR-0018 section 4/5): no new native property, no new step.
# Every key is core game data (Resources/Config/shipdata.plist) and carries the role it backs,
# so a pinned ship is one the role draw could itself have produced.
ROLE_SHIP_KEY = {
    "police": "[viper]",              # oolite_template_viper: roles = "police",
                                       # scan_class = CLASS_POLICE (the only "police" hull).
    "pirate": "[sidewinder]",         # oolite_template_sidewinder: roles include "pirate(0.75)".
                                       # Combat AI comes from ROLE_AI, so the hull is the only
                                       # thing pinned here.
    "trader": "[boa]",                # oolite_template_boa: roles = "trader"; S5's mother ship.
    "escort": "[sidewinder-escort]",  # roles = "escort escort-medium(0.5)"; S5's escorts.
}

# A ship spawned with role "pirate" needs a bounty precondition to be a legal police target:
# policeAI's fugitive/offender conditions require s.bounty > 50 and s.bounty > fineThreshold()
# (oolite-priorityai.js:2192-2219, 841-847). addShips("pirate") drew that bounty at random
# (Universe.mm:4029, `20 + randf() * 50`, i.e. 20-70, straddling the threshold); a literal
# "[shipKey]" spawn never reaches that line at all, because it compares the SELECTOR against
# "pirate", not the role assigned afterwards. Writing ship.bounty explicitly - already
# OOJS_PROP_READWRITE_CB, OOJSShip.mm:353, setter case :1392 - turns the engagement precondition
# into a fact of the scenario, comfortably above the worst-case threshold (government 0:
# fineThreshold() == 50).
PIRATE_BOUNTY = 100

# Where an unpositioned spawn goes. Left to itself addShips scatters ships anywhere in the system
# - measured 415 km apart - so nothing ever meets anything. Scenarios spawn around one locus.
SPAWN_RADIUS_M = 5000


def _js_string(value):
    """Quote a Python string for embedding in a JS source fragment."""
    return '"%s"' % str(value).replace("\\", "\\\\").replace('"', '\\"')


# --- Given ---------------------------------------------------------------------------------


@given(parsers.parse("a universe seeded with {seed:d}"))
def universe_seeded_with(world, seed):
    """Launch the game with OO_RANDOM_SEED pinned, into an empty but running system.

    Two things have to be true at once, and neither is free.

    The simulation must actually be running. Left at the main menu the game shows a demo scene:
    there is a docked player and a station, but no AI runs, so spawned ships sit in AIState
    GLOBAL with no target for ever. Measured: 90 s, zero movement, zero targets. A save has to be
    loaded to get a live universe, and there is no JS route out of the intro screen - that is
    keyboard work and belongs to the GUI tier.

    The system must also be empty, and a loaded save is anything but: the standard scenario opens
    with roughly 80 entities including 32 pirates and 5 police. "No ship with role pirate
    remains" is unreachable in that, and would be measuring the ambient population rather than
    the scenario. So the system is cleared down to the player before anything is spawned.

    RANROT is seeded once in GameController -init, which is why the seed belongs to this step and
    cannot be changed later.
    """
    world.start(seed, load_save=SCENARIO_SAVE)

    # A loaded save starts docked, and while docked the game is sitting on station screens rather
    # than flying the system - NPC AI does not tick, which is why every ship reports AIState
    # GLOBAL with no target no matter how long you wait. Launching puts the universe in flight.
    world.console.perform("player.ship.launch();")
    deadline = time.time() + LAUNCH_TIMEOUT_SECONDS
    while time.time() < deadline:
        time.sleep(1)
        if world.console.evaluate("player.ship.docked").strip().lower() == "false":
            break
    else:
        raise AssertionError(
            f"player never launched within {LAUNCH_TIMEOUT_SECONDS}s; the system would not be "
            "simulated and no scenario below it can mean anything"
        )
    # Let the launch settle so the player is clear of the station before the system is emptied.
    time.sleep(2)

    removed = world.console.evaluate_int(
        "(function(){"
        " var ships = system.allShips, n = 0;"
        " for (var i = 0; i < ships.length; i++) {"
        "   if (!ships[i].isPlayer) { ships[i].remove(); n++; }"
        " }"
        " return n; })()"
    )
    remaining = world.console.evaluate_int("system.allShips.length")
    if remaining > 1:
        raise AssertionError(
            f"cleared {removed} ships but {remaining} remain; the scenario would be measuring "
            "the ambient population rather than what it spawned"
        )


# --- When ----------------------------------------------------------------------------------


@when(parsers.parse('I spawn {count:d} ship with role "{role}"'))
@when(parsers.parse('I spawn {count:d} ships with role "{role}"'))
def spawn_ships(world, count, role):
    _spawn(world, count, role, "player.ship.position", SPAWN_RADIUS_M)


@when(parsers.parse('I spawn {count:d} ship with role "{role}" within {km:d} km'))
@when(parsers.parse('I spawn {count:d} ships with role "{role}" within {km:d} km'))
def spawn_ships_near(world, count, role, km):
    """Spawn near the existing action rather than anywhere in the system.

    The optional position/radius arguments of addShips take metres. The first ship already
    spawned is the only thing in an otherwise empty system worth measuring from, so use it when
    there is one and fall back to the origin when there is not.
    """
    _spawn(world, count, role, "__ooLocus", km * 1000)


def _spawn(world, count, role, at_js, radius_m):
    """Spawn ships around a locus and give them the AI their role would normally fly with.

    addShips(role_or_key, count [, position, radius]) returns the Array of ships it added
    (OOJSSystem.mm, SystemAddShips), so its length is the honest answer to "did I get what I asked for".

    ROLE_SHIP_KEY pins the SELECTOR passed to addShips to a literal "[shipKey]" for every role
    this step library knows about, removing OOShipRegistry's random draw between ship types (see
    the oo-sjvz determinism-fix comment above ROLE_SHIP_KEY). addShips still assigns the KEY
    itself as primaryRole (Universe.mm:4017 `[ship setPrimaryRole:role]`, called with the literal
    selector), so every spawned ship's primaryRole is forced back to the scenario's ROLE
    afterwards - otherwise every existing Then step and AI precondition that compares
    primaryRole against the scenario's role name (e.g. "police", "pirate") would silently stop
    matching. A role this library has no pinned key for (there are none among S1-S8 today) falls
    back to the plain role string, i.e. the original random-draw behaviour, so this cannot make
    an as-yet-unpinned scenario worse.

    The first spawn of a scenario also fixes __ooLocus, the point later "within N km" spawns
    measure from. debugConsole is a writable JS global (OODebugMonitor.m:761), which is the
    documented place to keep scratch state between commands.
    """
    ai = ROLE_AI.get(role)
    selector = ROLE_SHIP_KEY.get(role, role)
    js = (
        "(function(){"
        " var at = %s;"
        " var added = system.addShips(%s, %d, at, %d);"
        " if (!added) return 0;"
        " if (typeof debugConsole.__ooLocus === 'undefined' && added.length > 0)"
        "   debugConsole.__ooLocus = added[0].position;"
        " for (var i = 0; i < added.length; i++) {"
        "   added[i].primaryRole = %s;"
        "   %s"
        " }"
        " return added.length; })()"
        % (
            "debugConsole.__ooLocus" if at_js == "__ooLocus" else at_js,
            _js_string(selector),
            count,
            radius_m,
            _js_string(role),
            (("added[i].bounty = %d;" % PIRATE_BOUNTY) if role == "pirate" else "")
            + ((" added[i].setAI(%s);" % _js_string(ai)) if ai else ""),
        )
    )
    added = world.console.evaluate_int(js)
    if added != count:
        raise AssertionError(f"asked for {count} {role!r}, addShips returned {added}")
    world.spawned[role] = world.spawned.get(role, 0) + count


@when(parsers.parse("the simulation runs for at most {ticks:d} ticks"))
def run_simulation(world, ticks):
    """Let the game run, stopping early once the scenario's quarry is gone.

    Polling for an early exit is what keeps the suite fast; the budget is a ceiling, not a wait.
    Reaching the ceiling is not a failure here - the Then steps decide that - but the step must
    never block past it.
    """
    budget = ticks * TICK_SECONDS
    deadline = time.time() + budget
    watched = [r for r in world.spawned if r != "police"]
    while time.time() < deadline:
        time.sleep(POLL_SECONDS)
        if not watched:
            continue
        if all(count_with_role(world, role) == 0 for role in watched):
            return


@when(parsers.parse("the simulation runs for {ticks:d} ticks"))
def run_simulation_fully(world, ticks):
    """Run the whole budget without an early exit, for scenarios asserting nothing happened."""
    time.sleep(ticks * TICK_SECONDS)


# --- Then ----------------------------------------------------------------------------------


def count_with_role(world, role):
    return world.console.evaluate_int(
        "system.countShipsWithRole(%s)" % _js_string(role)
    )


@then(parsers.parse('within {ticks:d} ticks a ship with role "{hunter}" '
                   'engages a ship with role "{quarry}"'))
def engages_within(world, ticks, hunter, quarry):
    """Poll until a hunter has the quarry as a hostile target, or the budget runs out.

    Engagement rather than a kill, and measured rather than assumed - see ADR-0019. A GalCop
    Viper has 180 max energy against a stock pirate's 706, so it cannot win: observed over 320 s
    the police dropped to 130/180 and regenerated while the pirate never fell below 682/706. They
    simply circle. Engagement, by contrast, is quick and unambiguous: target acquired and
    hasHostileTarget set within ~17 s (about 136 ticks) of the spawn, against this budget of 900.

    Returning as soon as it is true is what keeps the scenario ~20 s instead of the full 112 s.
    """
    js = (
        "(function(){ var r = 0;"
        " system.allShips.forEach(function(s){"
        "   if (s.primaryRole == %s && s.hasHostileTarget"
        "       && s.target && s.target.primaryRole == %s) r = 1;"
        " });"
        " return r; })()" % (_js_string(hunter), _js_string(quarry))
    )
    deadline = time.time() + ticks * TICK_SECONDS
    while time.time() < deadline:
        # A generous per-command timeout: the game is flying a dogfight on a software renderer
        # and two cores, so a console round trip is not always prompt.
        if world.console.evaluate_int(js, timeout=45) == 1:
            return
        time.sleep(POLL_SECONDS)
    raise AssertionError(
        f"no ship with role {hunter!r} took a ship with role {quarry!r} as a hostile target "
        f"within {ticks} ticks"
    )


@then(parsers.parse('no ship with role "{role}" remains'))
def no_ship_with_role_remains(world, role):
    remaining = count_with_role(world, role)
    assert remaining == 0, f"{remaining} ship(s) with role {role!r} still alive"


@then(parsers.parse('a ship with role "{role}" survives'))
def ship_with_role_survives(world, role):
    remaining = count_with_role(world, role)
    assert remaining > 0, f"no ship with role {role!r} survived"


@then(parsers.parse('{count:d} ships with role "{role}" remain'))
def n_ships_with_role_remain(world, count, role):
    remaining = count_with_role(world, role)
    assert remaining == count, (
        f"expected {count} ship(s) with role {role!r}, found {remaining}"
    )


@then(parsers.parse("no ERROR appears in the log"))
def no_error_in_log(world):
    """The canary for NaN blowups and scan-class confusion (S7).

    Read after the game has quit, so the log is complete and closed.
    """
    import os

    world.close()
    log = os.path.join(world.output_dir, "Latest.log")
    if not os.path.isfile(log):
        raise AssertionError(f"no log written at {log}")
    with open(log, "r", encoding="utf-8", errors="replace") as handle:
        offenders = [line.rstrip() for line in handle if "ERROR" in line]
    assert not offenders, "ERROR lines in Latest.log:\n" + "\n".join(offenders[:20])
