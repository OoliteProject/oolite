"""Binds the T1 tutorial walkthrough to the keyboard steps and the shared step library.

The keyboard steps press real keys (keyboard.py), which is implemented for Windows only - the
platform this tier runs natively on (ADR-0017).
"""

import sys

import pytest
from pytest_bdd import scenarios

from steps.tutorial_steps import *  # noqa: F401,F403  (step definitions register on import)
from steps.world_steps import *  # noqa: F401,F403

pytestmark = pytest.mark.skipif(sys.platform != "win32", reason="real key presses are Windows only")

scenarios("features/t1_tutorial_walkthrough.feature")
