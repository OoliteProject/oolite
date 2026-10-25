# SMOKE SCENARIO (ADR-0020, docs/decisions/0020-component-scenarios-are-smoke-tests-for-now.md).
# The full story - "the second weapon path; missiles are simulated projectiles, lasers are
# hitscan" and damageType/kill attribution - needs a step the library does not have yet
# (tracked by oo-kbqw). This scenario only proves the setup (load, launch, spawn the named
# roles, set their AIs per ADR-0019) runs for the stated ticks without crashing. It does NOT
# prove a kill happened, that a missile specifically was fired, or who fired it.
Feature: Ship-to-ship combat
  Scenario: A missile-armed ship kills by missile (smoke)
    Given a universe seeded with 20260918
    When I spawn 1 ship with role "pirate"
    And I spawn 1 ship with role "trader" within 10 km
    And the simulation runs for at most 900 ticks
    Then a ship with role "pirate" survives
    And no ERROR appears in the log
