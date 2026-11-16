"""Binds the S8 feature file to the shared step library.

Each scenario gets its own module-level binding so pytest-bdd collects it as a test; the steps
themselves live in steps/world_steps.py and are reused by S2-S8.

Descoped per ADR-0020 (docs/decisions/0020-component-scenarios-are-smoke-tests-for-now.md): this
is now a smoke scenario asserting only that the scenario's setup (1 pirate + 8 police, per
ADR-0019) runs cleanly for the stated 900-tick budget (no ERROR in Latest.log) and that a role
that is never the target of anything here - the police - still exists afterwards. It does not
assert the pirate is destroyed: whether the eight police engage at all depends on a spawn-time
bounty draw (``system.addShips("pirate", ...)`` gives each ship ``bounty = 20 + randf() * 50``,
``Universe.m:4026``, against ``policeAI``'s ``fineThreshold()`` of 32 in Lave), so in roughly a
quarter of runs no combat happens at all - see ``docs/stories/S8-measurements.md`` (measured with
``tools/oo-qwk5-probe.py``) for the full record of that investigation. Proving the full title
claim (a destroyed ship actually leaves ``system.allShips``, not just that its role count fell)
needs a per-ship identity handle so the assertion can name the ship this scenario spawned rather
than a role the populator also writes to - deferred to the seam bead oo-kbqw.
"""

from pytest_bdd import scenarios

from steps.world_steps import *  # noqa: F401,F403  (step definitions register on import)

scenarios("features/s8_destroyed_ships_leave_allships.feature")
