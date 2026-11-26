"""Offline proof that the T1 keyboard steps cannot pass vacuously.

The walkthrough's worth rests on one property: a key press that does nothing FAILS the step. If
"I advance through lesson 1" were satisfied by pressing keys into a window that ignored them, the
whole feature file would read green with the keyboard broken. So the steps are driven here
against a scripted tutorial and a fake keyboard, and made to fail.

No game is launched: this runs in well under a second and takes no desktop lock.
"""

import pytest

from steps import tutorial_steps


class ScriptedTutorial:
    """Answers PROGRESS_JS from a tutorial whose "n" and "b" do what the script says.

    ``accepts`` is whether an "n" moves anything at all; ``lesson_lengths`` is
    $tutorialStages. Mode "b" arms the skip, as oolite-tutorial-equipment.js does.
    """

    def __init__(self, stage=0, substage=0, lesson_lengths=(3, 25, 12), accepts=True):
        self.stage, self.substage = stage, substage
        self.lengths = lesson_lengths
        self.accepts = accepts
        self.skip_armed = False
        self.presses = []

    # --- the console ----------------------------------------------------------------------

    def evaluate(self, js, timeout=None):
        assert js == tutorial_steps.PROGRESS_JS, f"unexpected JS {js!r}"
        return f"{self.stage} {self.substage}"

    # --- the keyboard ---------------------------------------------------------------------

    def press(self, key, hold=None, release=None):
        self.presses.append(key)
        if key == "b":
            self.skip_armed = True
        elif key == "n":
            self._next()

    def hold_until(self, key, condition, timeout):
        self.press(key)
        return condition()

    def _next(self):
        if not self.accepts:
            return
        if self.skip_armed:
            self.skip_armed = False
            self.stage, self.substage = self.stage + 1, 0
            return
        self.substage += 1
        if self.substage >= self.lengths[self.stage]:
            self.stage, self.substage = self.stage + 1, 0


class FakeWorld:
    def __init__(self, tutorial):
        self.console = tutorial
        self.keyboard = tutorial


@pytest.fixture(autouse=True)
def no_sleep(monkeypatch):
    monkeypatch.setattr(tutorial_steps.time, "sleep", lambda _seconds: None)
    monkeypatch.setattr(tutorial_steps, "EFFECT_TIMEOUT_SECONDS", 0)


def test_a_press_the_tutorial_ignores_fails_the_step():
    world = FakeWorld(ScriptedTutorial(stage=1, substage=1, accepts=False))
    with pytest.raises(AssertionError, match="left the tutorial at lesson 1 step 1"):
        tutorial_steps.advance_tutorial(world)


def test_advancing_through_a_lesson_presses_once_per_remaining_step():
    tutorial = ScriptedTutorial(stage=1, substage=0)
    tutorial_steps.advance_through_lesson(FakeWorld(tutorial), 1)
    assert (tutorial.stage, tutorial.substage) == (2, 0)
    assert tutorial.presses == ["n"] * 25


def test_advancing_through_a_lesson_that_stalls_fails():
    tutorial = ScriptedTutorial(stage=1, substage=0, accepts=False)
    with pytest.raises(AssertionError):
        tutorial_steps.advance_through_lesson(FakeWorld(tutorial), 1)


def test_advancing_to_a_step_already_passed_fails():
    world = FakeWorld(ScriptedTutorial(stage=2, substage=5))
    with pytest.raises(AssertionError, match="advanced past lesson 2 step 3"):
        tutorial_steps.advance_tutorial_to(world, 2, 3)


def test_skip_moves_to_the_next_lesson():
    tutorial = ScriptedTutorial(stage=1, substage=4)
    tutorial_steps.skip_lesson(FakeWorld(tutorial))
    assert (tutorial.stage, tutorial.substage) == (2, 0)
    assert tutorial.presses == ["b", "n"]


def test_a_skip_whose_mode_key_was_lost_fails():
    """A dropped "b" turns the "n" into next-item; that must not pass as a skip."""
    tutorial = ScriptedTutorial(stage=1, substage=4)
    original = tutorial.press
    tutorial.press = lambda key, **kw: None if key == "b" else original(key, **kw)
    with pytest.raises(AssertionError, match="should skip from lesson 1 to lesson 2"):
        tutorial_steps.skip_lesson(FakeWorld(tutorial))
