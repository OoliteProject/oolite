# SMOKE SCENARIO (ADR-0020). This does NOT prove "the target registers an
# attacker" (Ship.AIPrimaryAggressor / Ship.AIFoundTarget) — the step library
# has no step that reads AI/threat-tracking state. That assertion is
# deferred to oo-kbqw. This scenario only proves the setup (spawn the named
# roles, set their AIs per ADR-0019) runs for the stated ticks without
# crashing, and that a spawned role survives.

Feature: Ship-to-ship combat

  Scenario: A pirate attacks a trader; the setup runs cleanly
    Given a universe seeded with 20260918
    When I spawn 1 ship with role "trader"
    And I spawn 1 ship with role "pirate" within 10 km
    And the simulation runs for at most 900 ticks
    Then a ship with role "trader" survives
    And no ERROR appears in the log
