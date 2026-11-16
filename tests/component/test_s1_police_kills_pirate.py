"""Binds the S1 feature file to the shared step library.

Each scenario gets its own module-level binding so pytest-bdd collects it as a test; the steps
themselves live in steps/world_steps.py and are reused by S2-S8.
"""

from pytest_bdd import scenarios

from steps.world_steps import *  # noqa: F401,F403  (step definitions register on import)

scenarios("features/s1_police_kills_pirate.feature")
