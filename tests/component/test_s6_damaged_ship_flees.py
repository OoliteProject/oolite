"""Binds the S6 feature file to the shared step library.

S6 is a smoke scenario (ADR-0020): it proves the scenario's setup runs for the stated tick
budget without error and that a spawned ship survives. It does not prove the FLEE AI
transition or that range increases, which is deferred to oo-kbqw.
"""

from pytest_bdd import scenarios

from steps.world_steps import *  # noqa: F401,F403  (step definitions register on import)

scenarios("features/s6_damaged_ship_flees.feature")
