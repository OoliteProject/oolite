# SMOKE SCENARIO (ADR-0020, descoping oo-on18): this does NOT prove "group and
# formation behaviour (OOShipGroup), which no other tier touches" - it only proves the
# setup for this story runs the stated ticks without crashing, and that a spawned escort
# is still alive afterwards. The real assertion (escorts closing distance on their mother,
# via Ship.escortGroup/Ship.escorts) is deferred to oo-bdl0, which needs a step library
# capability (per-ship identity / numeric sampling, cf. oo-kbqw) that does not exist yet.
Feature: Escorts converge on their mother

  Scenario: A mother ship and her escorts fly without error
    Given a universe seeded with 20260910
    When I spawn 1 ship with role "trader"
    And I spawn 2 ships with role "escort" within 5 km
    And the simulation runs for at most 900 ticks
    Then a ship with role "escort" survives
    And no ERROR appears in the log
