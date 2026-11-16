"""Binds the S5 feature file to the shared step library.

SMOKE SCENARIO (ADR-0020): asserts only that the setup runs cleanly and a spawned escort
survives. See the top-of-file comment in the feature for the deferred full assertion
(oo-bdl0).
"""

from pytest_bdd import scenarios

from steps.world_steps import *  # noqa: F401,F403  (step definitions register on import)

scenarios("features/s5_escorts_converge_on_their_mother.feature")
