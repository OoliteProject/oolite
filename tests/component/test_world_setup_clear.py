"""Offline proof for bug oo-hmnbb: the world setup's clear-then-count survives ambient arrivals.

"a universe seeded with N" empties the system and then counts ``system.allShips``. A live
universe keeps adding ships between those two console commands - measured: cargo pods from a ship
removed mid-way through ``Ship.dumpCargo(n)``, whose n-1 deferred ``-dumpCargo`` calls outlive
the ship (21 of 120 single-shot clears failed while such a stream was running, 0 of 120 with the
repeated clear); station launches; the ~20 s repopulation. So the step repeats the clear until
one clear-then-count sees only the player, and still fails when the system never empties.

No game is launched here: a scripted console stands in for the debug console, so this runs in
well under a second and takes no desktop lock.
"""

import pytest

from steps import world_steps


class ScriptedConsole:
    """Answers the clear with a removal count and ``system.allShips.length`` from a script."""

    def __init__(self, counts):
        self.counts = list(counts)
        self.clears = 0

    def evaluate_int(self, js):
        if js == world_steps.CLEAR_NON_PLAYER_SHIPS_JS:
            self.clears += 1
            return 10 if self.clears == 1 else 1
        assert js == "system.allShips.length", f"unexpected JS {js!r}"
        return self.counts.pop(0)


@pytest.fixture(autouse=True)
def no_sleep(monkeypatch):
    monkeypatch.setattr(world_steps.time, "sleep", lambda _seconds: None)


def test_a_ship_arriving_between_clear_and_count_is_cleared_on_the_next_pass():
    console = ScriptedConsole([2, 1])
    removed, remaining = world_steps._clear_to_player(console)
    assert remaining == 1
    assert removed == 11
    assert console.clears == 2


def test_an_empty_system_takes_exactly_one_pass():
    console = ScriptedConsole([1])
    assert world_steps._clear_to_player(console) == (10, 1)
    assert console.clears == 1


def test_a_system_that_never_empties_still_reports_the_survivors():
    console = ScriptedConsole([3] * world_steps.CLEAR_ATTEMPTS)
    removed, remaining = world_steps._clear_to_player(console)
    assert remaining == 3, "the setup assertion must still see a system that cannot be emptied"
    assert console.clears == world_steps.CLEAR_ATTEMPTS
