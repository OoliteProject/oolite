"""Binds the S4 feature file to the shared step library.

S4 is a smoke scenario (ADR-0020): it proves the setup runs without crashing, not the
missile-kill behaviour named in the story. See the comment at the top of the feature file.
"""

from pytest_bdd import scenarios

from steps.world_steps import *  # noqa: F401,F403  (step definitions register on import)

scenarios("features/s4_missile_armed_ship_kills_by_missile.feature")
