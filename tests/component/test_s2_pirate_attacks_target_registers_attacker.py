"""Binds the S2 feature file to the shared step library.

S2 is a smoke scenario (ADR-0020): see the comment at the top of the feature file for what it
does not prove. Each scenario gets its own module-level binding so pytest-bdd collects it as a
test; the steps themselves live in steps/world_steps.py and are reused by S2-S8.
"""

from pytest_bdd import scenarios

from steps.world_steps import *  # noqa: F401,F403  (step definitions register on import)

scenarios("features/s2_pirate_attacks_target_registers_attacker.feature")
