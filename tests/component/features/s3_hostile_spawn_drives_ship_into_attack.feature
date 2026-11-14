# SMOKE SCENARIO (ADR-0020). This does NOT prove "a hostile spawn drives a
# ship into ATTACK via Ship.AIState, independent of whether combat resolves"
# — Ship.AIState never leaves GLOBAL in this tier (JS AIs install
# nullAI.plist, which has exactly one state) and the step library has no
# step that can distinguish ATTACK from FLEE. That assertion is deferred to
# seam oo-3cvh. This scenario only proves the setup (spawn the named roles,
# set their AIs per ADR-0019) runs for the stated ticks without crashing,
# and that a spawned role survives. "trader" is used as the surviving role,
# matching the sibling S2 scenario's already-validated, reliable choice.

Feature: Ship-to-ship combat

  Scenario: A hostile spawn drives a ship into ATTACK; the setup runs cleanly
    Given a universe seeded with 20260918
    When I spawn 1 ship with role "trader"
    And I spawn 1 ship with role "pirate" within 10 km
    And the simulation runs for at most 900 ticks
    Then a ship with role "trader" survives
    And no ERROR appears in the log
