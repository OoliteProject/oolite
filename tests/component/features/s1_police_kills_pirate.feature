Feature: Ship-to-ship combat

  Scenario: A police viper engages a lone pirate
    Given a universe seeded with 20260910
    When I spawn 1 ship with role "police"
    And I spawn 1 ship with role "pirate" within 10 km
    Then within 900 ticks a ship with role "police" engages a ship with role "pirate"
    And a ship with role "police" survives
