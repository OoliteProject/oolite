"""Offline guard: the SDL double-click is timed by its events, not by the poll that read them.

Bugs oo-3rb.333 (G5) and oo-3rb.336 (G8), and the same miss seen in G1: every row this tier
activates is activated by a double-click (``GameWindow.confirm_row``), and the game decides
"double" in ``-pollControls`` (MyOpenGLView+Input) by comparing the time of this left-button
release with the last one against MOUSE_DOUBLE_CLICK_INTERVAL (0.40 s).

It used to take that time from ``timeNow``, sampled ONCE when the poll starts. The two releases
of a synthetic double-click are 50 ms apart and are nearly always read by two consecutive polls,
so the interval the game measured was really the length of the frame between them. Measured with
a diagnostic build (SDL event timestamps logged next to the computed interval): a poll that
stalled for 0.86 s turned a 62 ms double-click into "0.899 s apart" - two single clicks - so the
confirm activated nothing and the test saw the start screen where it expected the next screen.
Frame hitches of 0.4-0.6 s after screen changes are routine in this tier, which is why the flake
followed load rather than any one test.

SDL stamps every event with ``SDL_GetTicksNS()`` when it is queued (on Windows, from the input
message's own time), so the release's ``timestamp`` is when the user actually let go. These
tests pin that the interval is computed from it, and that the "last click" it is compared with
starts on the same clock. They read source text because no offline harness can stall a poll
between two synthetic releases; the live proof is the GUI tier itself (tests/nightly/checks.txt).
"""

import os
import re
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
TESTS_DIR = os.path.abspath(os.path.join(HERE, ".."))
if TESTS_DIR not in sys.path:
    sys.path.insert(0, TESTS_DIR)

from source_paths import resolve_source  # noqa: E402


def _read(*parts):
    with open(resolve_source(*parts), "r", encoding="utf-8", errors="replace") as handle:
        return handle.read()


def _button_up_case():
    """The body of ``case SDL_EVENT_MOUSE_BUTTON_UP:`` in -pollControls, up to its ``break;``."""
    source = _read("SDL", "MyOpenGLView+Input")
    cases = [m.start() for m in re.finditer(r"case\s+SDL_EVENT_MOUSE_BUTTON_UP\s*:", source)]
    assert len(cases) == 1, f"expected one SDL_EVENT_MOUSE_BUTTON_UP case, found {len(cases)}"
    end = source.index("break;", cases[0])
    return source[cases[0]:end]


def _code(text):
    """``text`` without // and /* */ comments, so prose cannot satisfy a check."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


@pytest.mark.offline
def test_the_click_interval_is_taken_from_the_release_event_timestamp():
    body = _code(_button_up_case())
    assignment = re.search(r"timeBetweenClicks\s*=\s*([^;]+);", body)
    assert assignment, "the button-up case no longer computes timeBetweenClicks"
    rhs = assignment.group(1)
    assert "timeNow" not in rhs, (
        "timeBetweenClicks is computed from timeNow again - the poll's start time. Two releases "
        "read by two polls are then timed by the frame between the polls, and one slow frame "
        "turns a real double-click into two single clicks (oo-3rb.333/oo-3rb.336)"
    )
    stamped = {m.group(1) for m in re.finditer(r"(\w+)\s*=\s*[^;]*mbtn_event->timestamp", body)}
    uses_timestamp = "mbtn_event->timestamp" in rhs or any(
        re.search(r"\b%s\b" % name, rhs) for name in stamped
    )
    assert uses_timestamp, (
        f"timeBetweenClicks = {rhs.strip()} is not derived from the release event's own "
        "timestamp (mbtn_event->timestamp)"
    )


@pytest.mark.offline
def test_the_last_click_starts_on_the_clock_sdl_stamps_events_with():
    """A first click compared with a time on another clock could read as a double-click."""
    init = _code(_read("SDL", "MyOpenGLView"))
    sites = re.findall(r"timeIntervalAtLastClick\s*=\s*([^;]+);", init)
    assert len(sites) == 1, f"expected one initialisation of timeIntervalAtLastClick, found {sites}"
    assert "SDL_GetTicksNS" in sites[0], (
        f"timeIntervalAtLastClick starts at {sites[0].strip()}, not on SDL_GetTicksNS(), the "
        "clock SDL stamps events with"
    )
