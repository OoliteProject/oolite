Feature: The tutorial can be played start to finish from the keyboard

  Scenario: Every lesson is reachable and the basic controls respond
    Given the tutorial is loaded
    When I press "enter"
    Then the player is in flight
    And the tutorial is at lesson 0 step 2

    # Lesson 0 ends on "next"; lesson 1 is the HUD tour, all "next".
    When I advance through lesson 0
    And I advance through lesson 1
    Then the tutorial is at lesson 2 step 0

    # Lesson 2 will not start until the ship is stationary.
    When I bring the ship to a stop
    And I advance the tutorial to lesson 2 step 10
    Then the view is "VIEW_FORWARD"

    # 2-10 teaches the four view keys; 2-11 the external view.
    When I press "2"
    Then the view is "VIEW_AFT"
    When I press "3"
    Then the view is "VIEW_PORT"
    When I press "4"
    Then the view is "VIEW_STARBOARD"
    When I press "1"
    Then the view is "VIEW_FORWARD"
    When I advance the tutorial
    Then the tutorial is at lesson 2 step 11
    When I press "v"
    Then the view is "VIEW_CUSTOM"
    When I press "1"
    Then the view is "VIEW_FORWARD"
    When I advance through lesson 2

    # Lessons 3-7 are flying challenges; the tutorial's own skip control leaves each one.
    Then the tutorial is at lesson 3 step 0
    When I skip to the next lesson
    And I skip to the next lesson
    And I skip to the next lesson
    And I skip to the next lesson
    And I skip to the next lesson
    Then the tutorial is at lesson 8 step 0

    # Lesson 8 is the status screens. Each opens from flight, and a view key closes it again.
    When I press "f5"
    Then the screen is "GUI_SCREEN_STATUS"
    When I press "f6"
    Then the screen is "GUI_SCREEN_SHORT_RANGE_CHART"
    When I press "f7"
    Then the screen is "GUI_SCREEN_SYSTEM_DATA"
    When I press "f8"
    Then the screen is "GUI_SCREEN_MARKET"
    When I press "1"
    Then the screen is "GUI_SCREEN_MAIN"
    And the view is "VIEW_FORWARD"
    When I press "2"
    Then the view is "VIEW_AFT"
    When I press "1"
    Then the view is "VIEW_FORWARD"
    When I advance through lesson 8

    # Lesson 9 is navigation across the system; skipping it ends the tutorial.
    Then the tutorial is at lesson 9 step 0
    When I skip to the next lesson
    Then the tutorial end screen is shown
    And no ERROR appears in the log
