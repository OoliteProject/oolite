# SMOKE SCENARIO (ADR-0020, docs/decisions/0020-component-scenarios-are-smoke-tests-for-now.md).
# This does NOT prove the title's full claim (no accidental carnage, no NaN blowups, no
# scan-class confusion across 8 neutral ships over 900 ticks). It proves only that the
# scenario's setup runs and completes the stated tick budget without an ERROR in Latest.log,
# and that a ship with the spawned role still exists afterwards. The step library has no way
# to assert per-ship survival scoped to the ships this scenario spawned (an exact role-count
# assertion is flaky because the system populator adds ambient traffic during the run) — that
# capability is deferred to the seam bead oo-bdl0.
Feature: Neutral traffic is quiet

  Scenario: 8 neutral ships run for 900 ticks without incident
    Given a universe seeded with 20260910
    When I spawn 8 ships with role "shuttle"
    And the simulation runs for 900 ticks
    Then a ship with role "shuttle" survives
    And no ERROR appears in the log
