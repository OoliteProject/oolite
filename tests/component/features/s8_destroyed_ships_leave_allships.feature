# SMOKE SCENARIO (ADR-0020, docs/decisions/0020-component-scenarios-are-smoke-tests-for-now.md).
# This does NOT prove the title's full claim (that a destroyed ship leaves system.allShips).
# Proving entity lifetime needs a per-ship identity handle so the assertion can name the ship
# this scenario spawned rather than a role the populator also writes to - that capability is
# deferred to the seam bead oo-kbqw. It also does not prove the pirate is killed: whether the
# eight police engage at all depends on a spawn-time bounty draw (docs/stories/S8-measurements.md
# via tools/oo-qwk5-probe.py), so asserting the pirate is destroyed is a coin flip and is not
# asserted here. This scenario proves only that the setup (1 pirate + 8 police, per ADR-0019)
# runs and completes the stated tick budget without an ERROR in Latest.log, and that a role that
# is never the target of anything in this scenario - the police - still exists afterwards.
Feature: Entity lifetime

  Scenario: Setup with a pirate and police runs cleanly for 900 ticks
    Given a universe seeded with 20260910
    When I spawn 1 ship with role "pirate"
    And I spawn 8 ships with role "police" within 10 km
    And the simulation runs for 900 ticks
    Then a ship with role "police" survives
    And no ERROR appears in the log
