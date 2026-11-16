# SMOKE TEST.
#
# This scenario does NOT prove "the FLEE branch, the most commonly broken AI transition"
# (story S6) and does NOT prove that range increases while a
# damaged ship flees. The step library (oolite-dev/tests/component/steps/world_steps.py)
# has no step that samples a numeric range/distance more than once for comparison and no step
# that reads an AI behavioural-state transition, so neither half of the story's title can be
# asserted with the existing step catalogue. Adding either is a new interface and
# out of scope here.
#
# What this DOES prove: the scenario's world setup (load, launch, spawn the named roles, set
# their AIs) runs for the stated tick budget without the game logging an ERROR, and
# a ship with a role this scenario spawned is still alive afterwards. The real assertion -
# FLEE-state transition and increasing range - is deferred.

Feature: A damaged ship flees and range increases (smoke test)

  Scenario: Setup runs cleanly and a spawned ship survives the scenario duration
    Given a universe seeded with 20260918
    When I spawn 1 ship with role "police"
    And I spawn 1 ship with role "pirate" within 10 km
    And the simulation runs for at most 900 ticks
    Then a ship with role "police" survives
    And no ERROR appears in the log
