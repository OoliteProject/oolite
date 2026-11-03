"""G9 - the post-exit hygiene every GUI test in this tier is held to.

docs/phases/0-gui-tier.md G9. Written the way test_g1_exit_via_mouse.py is written: the ``game``
fixture, no launcher of its own, the desktop lock inherited, and every guard that needs neither a
desktop nor a build marked ``offline`` so it gates in a clean checkout.

    python3 -m pytest upstream/oolite/tests/gui/test_g9_post_exit_hygiene.py -x -q

WHY THIS FILE IS BOTH A LAUNCHING TEST AND A META-TEST
------------------------------------------------------
Most of G9 already shipped, inside other beads, and a survey of what is actually asserted after
exit today says so:

  G1 (test_g1_exit_via_mouse.py)      exit status 0; assert_no_surviving_game_processes(pid);
                                      assert_clean_exit(game)
  G3 (test_g3_exit_via_window_close)  identical three, reached down the SDL_EVENT_QUIT path
  G7 (test_g7_first_run_creates_def)  the same three, plus the prefs file BY NAME and a direct
                                      parse_defaults_file on it (G7's own first-run claim)

So the three launching tests agree on the baseline, ``assert_clean_exit`` is already its single
home, and a fourth test calling the same three helpers would add a fourth run of the same
assertions and no coverage. The two properties genuinely NOT asserted anywhere are both about
the shutdown the log records, and both were MEASURED on this build rather than assumed:

  1. THAT THE SHUTDOWN FINISHED.  assert_clean_exit infers the shutdown from the defaults write,
     and GameController.m:906 synchronizes BEFORE :908 OOLoggingTerminate(), :909 SDL_Quit() and
     :910 the OpenAL shutdown. A process that synchronized and then died in any of those three
     leaves a moved plist mtime, no dump and no ERROR line, so assert_clean_exit passes it
     completely while the log was never closed. The footer is the only witness for that tail.
       HONEST LIMIT, because the first version of this docstring got it wrong and a real run
       falsified it: a game killed at the START SCREEN does NOT slip past assert_clean_exit. I
       drove exactly that - a break twin replacing close_window() with proc.kill() - and the
       defaults check caught it, "mtime unchanged since launch ... size 309 vs 309". What it
       says is "a leftover from an earlier run (oo-5rsa)", i.e. the right verdict for the wrong
       reason. So the coverage gap is specifically a death AFTER the synchronize, not any kill.
  2. WHY THE GAME EXITED.  -exitAppWithContext: is reached from NINE call sites in this tree
     (PlayerEntityControls.m:958/2658/4981, GameController.m:272/921, Universe.m:1048,
     MyOpenGLView+Input.m:479/663, MyOpenGLView.m:469). Every one synchronizes defaults, closes
     the log and exits 0, so every check in this tier passes on every one of them. G3's claim is
     that SDL_EVENT_QUIT (MyOpenGLView+Input.m:663) took the game down; today nothing in this
     tier can tell that from an exit via the error-handling path at :958. The exit.context line
     is the only runtime evidence of which one ran, and ``expected_context`` asserts on it.

A third property is not about the log at all: GameWindow._park_software_gl RENAMES opengl32.dll
and libgallium_wgl.dll inside the SHARED build tree five agents run against, and nothing asserted
the restore happened. It now runs from the ``game`` fixture's teardown, so it holds for every test
in this tier including future ones with no test having to remember it.

Hence both halves. The launching test proves the new assertions hold against a real exit - a
helper nobody has run against a real shutdown is a hope. The meta-test then locks the contract so
a future G4/G5 cannot quietly omit it: launching a game and never asking what it left behind is
the failure mode this bead exists to prevent, and no amount of coverage in THIS file prevents it
in the NEXT one.

REPORTED, NOT NORMALISED: G7 asserts the prefs file by name and parses it directly, where G1 and
G3 leave that to assert_clean_exit's candidate search. That is a real inconsistency and it is
deliberate on G7's side (its docstring says why: assert_clean_exit searches every candidate root,
so a fresh plist in the SHARED build would satisfy it while G7's private pristine app got
nothing). It is left exactly as it is; the meta-test below requires the shared baseline and does
not forbid a test from asserting more.

Needs the desktop for the launching test: a real window, unlocked and logged in (ADR-0017). It
takes tools/gui-lock for the duration via the ``game`` fixture and launches nothing of its own.
"""

import ast
import os

import pytest

from conftest import (
    SHUTDOWN_DEFAULTS_WITNESS,
    SHUTDOWN_EXIT_CONTEXT_WITNESS,
    SHUTDOWN_LOG_CLOSED_WITNESS,
    SHUTDOWN_WITNESSES,
    assert_clean_exit,
    assert_no_parked_runtime_files,
    assert_no_surviving_game_processes,
    assert_shutdown_path_completed,
)

HERE = os.path.dirname(os.path.abspath(__file__))

# Same budget as G1/G3: a close that has not taken the game down by now has not worked.
EXIT_TIMEOUT_SECONDS = 10

# MyOpenGLView+Input.m:663 - the exact string the SDL_EVENT_QUIT case hands
# -exitAppWithContext:. This is the gesture this test uses, so this is the context its log must
# name; any other of the nine exit paths means the close did nothing and something else took the
# game down.
EXPECTED_EXIT_CONTEXT = "SDL_QUIT event received"

# What every test in this tier that launches a game must ask of it afterwards. Deliberately the
# BASELINE the three existing launching tests already share, so this is a lock on an established
# contract rather than a new demand invented here.
REQUIRED_POST_EXIT_HELPERS = (
    "assert_no_surviving_game_processes",
    "assert_clean_exit",
)

# Asserted of the tier's own fixture instead of of each test: it is true of every test regardless
# of how the test ends, so requiring each one to call it would be the forgettable arrangement this
# file exists to remove.
FIXTURE_REQUIRED_HELPERS = ("assert_no_parked_runtime_files",)


# --- the launching half: the new assertions, against a real exit --------------------------------


def test_g9_post_exit_hygiene_holds_after_a_real_exit(game):
    """Exit for real, then run the whole shared hygiene set over what the run left behind.

    The exit gesture is the window close (G3's path) because G9's claim is about the STATE AFTER
    the exit, not about the gesture; reusing the cheapest real gesture keeps this file from
    re-testing G1's menu clicks. What is new here relative to G1/G3 is step 5: the log must carry
    -exitAppWithContext:'s trace THROUGH its final line, and must name the SDL_EVENT_QUIT context
    rather than any of the other eight exit paths.
    """
    assert game.proc.poll() is None, "the game exited before the test could ask it to"
    game.assert_focused()

    # 1. Ask it to exit, through the window manager.
    hwnd = game.close_window()

    # 2. It goes, within the budget, with status 0.
    try:
        returncode = game.proc.wait(timeout=EXIT_TIMEOUT_SECONDS)
    except Exception:
        pytest.fail(
            f"the game was still running {EXIT_TIMEOUT_SECONDS}s after WM_CLOSE was posted to "
            f"hwnd {hwnd}"
        )
    assert returncode == 0, f"the game exited with {returncode}, not 0"

    # 3. Nothing of ours survives in the OS process table. Not proc.poll(), which wait() above
    #    already reaped and which is therefore true by construction (oo-5rsa).
    assert_no_surviving_game_processes(game.proc.pid)

    # 4. The established baseline: no dump, no ERROR in the log, a defaults file THIS run wrote
    #    and which re-parses. Passed the fixture so the launch mark travels with it.
    assert_clean_exit(game)

    # 5. THE ASSERTIONS THIS BEAD ADDS. Step 4's evidence is the :906 defaults synchronize, which
    #    happens BEFORE OOLoggingTerminate/SDL_Quit/the OpenAL shutdown; the log footer is the
    #    only witness that the code after it ran. And the context must be THIS gesture's: all
    #    nine exit paths in the tree synchronize, close the log and exit 0, so without the
    #    context this test cannot tell its own close from an unrelated exit.
    context_line = assert_shutdown_path_completed(game, EXPECTED_EXIT_CONTEXT)
    assert EXPECTED_EXIT_CONTEXT in context_line

    # 6. NOT asserted here: anything about the shared build's software-GL DLLs. They are still
    #    parked at this point BY DESIGN - _restore_software_gl runs in kill(), which runs in the
    #    fixture's teardown, after this function returns. That property therefore belongs to the
    #    fixture and is asserted there (conftest.game), which is also what makes it hold for
    #    every test in this tier rather than only the ones that remember it.
    #
    #    AND NOT EVEN "this run parked something": that assertion was here and a real run turned
    #    it RED for a legitimate reason. A concurrent sibling GUI run already had the DLLs parked,
    #    so _park_software_gl found nothing to move and game._parked_ever was empty - which is
    #    correct behaviour by both runs. It is the same cross-run race that made the first
    #    spelling of assert_no_parked_runtime_files wrong, reintroduced one level up. The
    #    fixture's check is sound while vacuous in that case (nothing parked, nothing to restore)
    #    and the offline twins below cover the non-vacuous paths through the real park/restore
    #    pair, so nothing is lost by not demanding it here.


# --- the red proof: the gap the new helper closes is real ---------------------------------------
#
# Offline: these construct the evidence a killed run leaves and read it with the real helpers.


def _killed_run_output_dir(tmp_path):
    """A Latest.log as a game killed AT THE START SCREEN leaves it: startup, then nothing.

    Shaped from a real run of this tier - the log ends at the last line the game wrote before it
    was killed, with no exit.context, no synchronize line and no footer.
    """
    out = tmp_path / "killed"
    out.mkdir()
    (out / "Latest.log").write_text(
        "Opening log for Oolite version 1.93 at 2026-09-17 11:31:33 -0400.\n"
        "11:31:36.239 [rendering.opengl.shader.support]: Shaders are supported.\n"
        "11:31:36.330 [shipData.load.begin]: Loading ship data.\n"
        "11:31:38.530 [startup.complete]: ===== Loading complete in 2.67 seconds. =====\n",
        encoding="utf-8",
    )
    return str(out)


def _died_after_synchronize_output_dir(tmp_path):
    """THE GAP: the shutdown got as far as the defaults write and then died.

    GameController.m:906 synchronizes, :907 logs it, and only THEN come :908
    OOLoggingTerminate(), :909 SDL_Quit() and :910 the OpenAL shutdown. A process that dies in
    any of those three has written a fresh plist - which is the entire evidence
    assert_clean_exit's defaults check consumes - and has left no dump and no ERROR line. Every
    check in this tier passes on it. The missing footer is the only witness.
    """
    out = tmp_path / "half"
    out.mkdir()
    (out / "Latest.log").write_text(
        "Opening log for Oolite version 1.93 at 2026-09-17 11:31:33 -0400.\n"
        "11:31:38.530 [startup.complete]: ===== Loading complete in 2.67 seconds. =====\n"
        "11:31:45.382 [exit.context]: Exiting: SDL_QUIT event received.\n"
        "11:31:45.387 [gameController.exitApp]: .GNUstepDefaults synchronized.\n",
        encoding="utf-8",
    )
    return str(out)


def _clean_run_output_dir(tmp_path, context="SDL_QUIT event received"):
    """The same log with the three lines -exitAppWithContext: appends on its way out."""
    out = tmp_path / f"clean-{abs(hash(context)) % 10000}"
    out.mkdir()
    (out / "Latest.log").write_text(
        "Opening log for Oolite version 1.93 at 2026-09-17 11:31:33 -0400.\n"
        "11:31:38.530 [startup.complete]: ===== Loading complete in 2.67 seconds. =====\n"
        f"11:31:45.382 [exit.context]: Exiting: {context}.\n"
        "11:31:45.387 [gameController.exitApp]: .GNUstepDefaults synchronized.\n"
        "\nClosing log at 2026-09-17 11:31:45 -0400.\n",
        encoding="utf-8",
    )
    return str(out)


@pytest.mark.offline
def test_a_healthy_shutdown_log_passes(tmp_path):
    """The good case must pass; a check that rejects a real clean exit is no use either.

    The text is the tail of an actual run of this tier on this build, so this also pins the
    witnesses to the strings the game really writes rather than to strings this file invented.
    """
    line = assert_shutdown_path_completed(
        _clean_run_output_dir(tmp_path), EXPECTED_EXIT_CONTEXT
    )
    assert EXPECTED_EXIT_CONTEXT in line


@pytest.mark.offline
def test_a_killed_game_fails_the_shutdown_check_and_the_message_names_what_is_missing(tmp_path):
    """RED PROOF: no exit trace -> AssertionError naming every witness that never appeared."""
    with pytest.raises(AssertionError) as caught:
        assert_shutdown_path_completed(_killed_run_output_dir(tmp_path))
    message = str(caught.value)
    for witness in SHUTDOWN_WITNESSES:
        assert witness in message, (
            f"the failure must name the missing witness {witness!r} so the operator is told "
            "WHAT leaked rather than that something did"
        )


@pytest.mark.offline
def test_the_established_check_passes_a_shutdown_that_died_after_the_defaults_write(tmp_path):
    """THE JUSTIFICATION FOR GAP 1, as an executable claim rather than a docstring.

    One synthetic run that synchronized its defaults and then died before OOLoggingTerminate:
    assert_clean_exit PASSES it (no dump, no ERROR, and a plist written during the run - its
    entire evidence, produced at :906 before the code that never ran) while
    assert_shutdown_path_completed FAILS it on the absent footer.

    This replaces a WRONGER claim. The first version of this test asserted the same of a game
    killed at the START SCREEN, and a real break-twin run falsified it: that plist's mtime never
    moves, so assert_clean_exit does catch it (naming the wrong cause - "a leftover from an
    earlier run"). The gap is specifically a death AFTER the synchronize, and that is what this
    constructs. If a later edit ever made assert_clean_exit catch this too, this test goes red
    and G9's extra assertion can be retired deliberately rather than forgotten.
    """
    import conftest

    out = _died_after_synchronize_output_dir(tmp_path)
    app = tmp_path / "oolite.app"
    defaults = app / "GNUstep" / "Defaults"
    defaults.mkdir(parents=True)
    plist = defaults / "oolite.plist"
    plist.write_text('{\n    window_width = 960;\n}\n', encoding="utf-8")
    mark = conftest.defaults_write_mark(str(app))
    # The write the dying run DID make, at :906. Forced strictly later rather than trusted to
    # the clock: coarse filesystem timestamp granularity would make the assertion look flaky.
    plist.write_text('{\n    window_width = 960;\n    window_height = 720;\n}\n', encoding="utf-8")
    later = mark[str(plist)][0] + 1_000_000_000
    os.utime(str(plist), ns=(later, later))

    # The established check is fully satisfied by a shutdown that died partway through.
    conftest.assert_clean_exit(out, str(app), mark)
    # The new one is not, and it says which line is missing.
    with pytest.raises(AssertionError) as caught:
        assert_shutdown_path_completed(out)
    message = str(caught.value)
    assert SHUTDOWN_LOG_CLOSED_WITNESS in message
    assert SHUTDOWN_DEFAULTS_WITNESS not in message.split("never appeared")[0], (
        "the synchronize line IS present in this log, so it must not be reported missing"
    )


@pytest.mark.offline
def test_an_exit_down_a_different_path_fails_on_the_context(tmp_path):
    """THE JUSTIFICATION FOR GAP 2: a clean exit for the WRONG REASON must not pass.

    -exitAppWithContext: is reached from nine call sites, and every one of them synchronizes
    defaults, closes the log and exits 0. The log below is a perfectly clean shutdown - all
    three witnesses, in order - down PlayerEntityControls.m:958's error-handling path. Without
    the context assertion, a G3 whose WM_CLOSE did nothing while the game left that way is green
    with its central claim false.
    """
    out = _clean_run_output_dir(tmp_path, "Q or escape pressed in error handling mode")
    # It IS a complete, well-ordered shutdown: with no expectation it passes.
    assert_shutdown_path_completed(out)
    # But not the one the test asked for.
    with pytest.raises(AssertionError) as caught:
        assert_shutdown_path_completed(out, EXPECTED_EXIT_CONTEXT)
    message = str(caught.value)
    assert EXPECTED_EXIT_CONTEXT in message, "the failure must say what was expected"
    assert "error handling mode" in message, "and what actually happened"
    assert "nine call sites" in message


@pytest.mark.offline
def test_every_exit_context_in_the_tree_is_distinguished_from_the_expected_one():
    """No OTHER exit path's context may accidentally satisfy this test's expectation.

    Read out of the game's own source rather than listed here, so a tenth call site added later
    is covered. If someone adds a context string containing "SDL_QUIT event received" this goes
    red, which is correct: the expectation would no longer identify one path.
    """
    import re

    src = os.path.abspath(os.path.join(HERE, "..", "..", "src"))
    contexts = set()
    for root, _dirs, files in os.walk(src):
        for name in files:
            if not name.endswith((".m", ".h")):
                continue
            with open(os.path.join(root, name), "r", encoding="utf-8", errors="replace") as fh:
                contexts |= set(re.findall(r'exitAppWithContext:@"([^"]+)"', fh.read()))
    assert EXPECTED_EXIT_CONTEXT in contexts, (
        f"{EXPECTED_EXIT_CONTEXT!r} is not an exit context in the game's source any more; this "
        f"test would then never pass. Found: {sorted(contexts)}"
    )
    assert len(contexts) >= 5, (
        f"only {len(contexts)} exit contexts found ({sorted(contexts)}); the scan is not "
        "finding the call sites and this guard is not checking what it thinks it is"
    )
    others = [c for c in contexts if c != EXPECTED_EXIT_CONTEXT]
    clashes = [c for c in others if EXPECTED_EXIT_CONTEXT in c]
    assert not clashes, (
        f"these other exit contexts also contain {EXPECTED_EXIT_CONTEXT!r} and would satisfy "
        f"the expectation: {clashes}"
    )


@pytest.mark.offline
@pytest.mark.parametrize("dropped", SHUTDOWN_WITNESSES)
def test_each_witness_is_load_bearing_on_its_own(tmp_path, dropped):
    """Removing ANY ONE of the three lines must fail: a shutdown that stopped partway is not one.

    Without this, two of the three could be dropped from the helper and the remaining one would
    hold every case green - the check would be one assertion wearing three names.
    """
    out = _clean_run_output_dir(tmp_path)
    path = os.path.join(out, "Latest.log")
    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read()
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("".join(line for line in text.splitlines(True) if dropped not in line))
    with pytest.raises(AssertionError) as caught:
        assert_shutdown_path_completed(out)
    assert dropped in str(caught.value)


@pytest.mark.offline
def test_two_runs_concatenated_do_not_let_the_earlier_one_vouch_for_the_later(tmp_path):
    """An earlier clean shutdown followed by a kill must FAIL, not pass on the old evidence.

    All three witnesses are present in this file - a presence-only check passes it - but they are
    all BEFORE the second run's startup.complete, so the run that ended here never wrote them.
    This is the case the startup anchor exists for, and it is reachable: Latest.log is reopened
    per run, but an output directory whose log is appended to rather than replaced produces
    exactly this.
    """
    out = tmp_path / "both"
    out.mkdir()
    (out / "Latest.log").write_text(
        "11:31:38.530 [startup.complete]: ===== Loading complete in 2.67 seconds. =====\n"
        "11:31:45.382 [exit.context]: Exiting: SDL_QUIT event received.\n"
        "11:31:45.387 [gameController.exitApp]: .GNUstepDefaults synchronized.\n"
        "\nClosing log at 2026-09-17 11:31:45 -0400.\n"
        "Opening log for Oolite version 1.93 at 2026-09-17 11:40:00 -0400.\n"
        "11:40:03.530 [startup.complete]: ===== Loading complete in 2.71 seconds. =====\n",
        encoding="utf-8",
    )
    # Presence alone is satisfied - which is why presence alone is not the check.
    text = (out / "Latest.log").read_text(encoding="utf-8")
    assert all(w in text for w in SHUTDOWN_WITNESSES)
    with pytest.raises(AssertionError) as caught:
        assert_shutdown_path_completed(str(out))
    message = str(caught.value)
    assert "did not run to completion" in message
    for witness in SHUTDOWN_WITNESSES:
        assert witness in message, (
            "every witness belongs to the EARLIER run, so all three must be reported missing "
            f"from this one; {witness!r} was not named"
        )


@pytest.mark.offline
def test_a_scrambled_exit_trace_fails_on_order(tmp_path):
    """The ordering assertion itself, reached directly: the three lines in the wrong sequence.

    Written as a deliberate scramble rather than claimed to occur in the wild. GameController.m
    emits them at :893/:907/:908 in one straight line of code, so a log with the synchronize
    line before the exit context is evidence the trace was assembled by something other than
    that code path - and an assertion nothing can reach is not an assertion, so this reaches it.
    """
    out = tmp_path / "scrambled"
    out.mkdir()
    (out / "Latest.log").write_text(
        "11:31:38.530 [startup.complete]: ===== Loading complete in 2.67 seconds. =====\n"
        "11:31:45.387 [gameController.exitApp]: .GNUstepDefaults synchronized.\n"
        "\nClosing log at 2026-09-17 11:31:45 -0400.\n"
        "11:31:45.382 [exit.context]: Exiting: SDL_QUIT event received.\n",
        encoding="utf-8",
    )
    with pytest.raises(AssertionError) as caught:
        assert_shutdown_path_completed(str(out))
    assert "out of order" in str(caught.value)


@pytest.mark.offline
def test_an_absent_log_fails_rather_than_skipping(tmp_path):
    """No Latest.log is a FAILURE. A missing witness file is the silent pass oo-7by1 removed."""
    with pytest.raises(AssertionError) as caught:
        assert_shutdown_path_completed(str(tmp_path))
    assert "no Latest.log" in str(caught.value)


@pytest.mark.offline
def test_a_start_screen_kill_is_caught_by_the_existing_check_but_for_the_wrong_reason(tmp_path):
    """THE FALSIFIED HYPOTHESIS, kept as a regression test of what is actually true.

    This bead was started on the belief that a game killed at the start screen slips past
    assert_clean_exit. A break twin - close_window() replaced with proc.kill() in the launching
    test - DISPROVED it against the real build: the shared plist's mtime never moves, so the
    defaults check fails with "mtime unchanged since launch ... size 309 vs 309".

    So it is caught, and the reportable fact is that it is caught for the WRONG REASON: the
    message says "a leftover from an earlier run (oo-5rsa)" when what happened is that this run
    died. assert_shutdown_path_completed says the right thing about the same run. Both halves
    are asserted, so if either message changes the discrepancy is re-examined deliberately.
    """
    import conftest

    out = _killed_run_output_dir(tmp_path)
    app = tmp_path / "oolite.app"
    defaults = app / "GNUstep" / "Defaults"
    defaults.mkdir(parents=True)
    plist = defaults / "oolite.plist"
    plist.write_text('{\n    window_width = 960;\n}\n', encoding="utf-8")
    # No rewrite: a kill at the start screen never reaches GameController.m:906.
    mark = conftest.defaults_write_mark(str(app))

    with pytest.raises(AssertionError) as by_defaults:
        conftest.assert_clean_exit(out, str(app), mark)
    assert "THIS RUN did not write it" in str(by_defaults.value), (
        "a start-screen kill IS caught by the established check, via the unchanged plist mtime"
    )
    assert "leftover from an earlier run" in str(by_defaults.value), (
        "and it attributes it to a stale file rather than to a run that died - the diagnostic "
        "defect this bead reports rather than a coverage gap"
    )

    with pytest.raises(AssertionError) as by_trace:
        assert_shutdown_path_completed(out)
    assert SHUTDOWN_EXIT_CONTEXT_WITNESS in str(by_trace.value), (
        "the new check names the missing shutdown trace, which is what actually happened"
    )


# --- the parked-DLL half ------------------------------------------------------------------------


@pytest.mark.offline
def test_a_restore_that_never_happened_fails_and_names_the_file(tmp_path):
    """RED PROOF: a DLL this run parked and could not put back must be loud, and must name it.

    Driven through the REAL _park_software_gl/_restore_software_gl pair on a throwaway app dir,
    not by poking the bookkeeping lists: the claim is that the pair records its own failure, and
    setting ``_restore_failures`` by hand would assert only that a list I filled is non-empty.
    """
    import conftest

    app = tmp_path / "oolite.app"
    app.mkdir()
    for dll in conftest.GameWindow.SOFTWARE_GL_DLLS:
        (app / dll).write_bytes(b"MZ")

    window = conftest.GameWindow(str(app), str(tmp_path / "out"))
    window._park_software_gl()
    assert window._parked_ever, "the real parking step moved nothing; this dir is not set up"

    # The healthy round trip first: park then restore must leave the check clean.
    window._restore_software_gl()
    assert_no_parked_runtime_files(window)
    for dll in conftest.GameWindow.SOFTWARE_GL_DLLS:
        assert (app / dll).is_file(), f"{dll} was not restored"

    # Now the failure: park again, and have the parked file vanish before the restore - which is
    # what an interrupted run, or another process cleaning up, leaves behind.
    stranded = conftest.GameWindow.SOFTWARE_GL_DLLS[0]
    window._park_software_gl()
    os.remove(str(app / (stranded + conftest.GameWindow._PARKED_SUFFIX)))
    window._restore_software_gl()

    with pytest.raises(AssertionError) as caught:
        assert_no_parked_runtime_files(window)
    message = str(caught.value)
    assert stranded in message, "the failure must name the DLL that was stranded"
    assert "SHARED build" in message
    assert "could not be renamed back" in message


@pytest.mark.offline
def test_a_dll_this_run_parked_and_then_lost_fails_too(tmp_path):
    """The other direction: the restore claimed success but the file is gone from the build.

    A check that only looked at ``_restore_failures`` would report a clean machine for the worse
    of the two outcomes, because there is then not even a parked twin left to rename back.
    """
    import conftest

    app = tmp_path / "oolite.app"
    app.mkdir()
    for dll in conftest.GameWindow.SOFTWARE_GL_DLLS:
        (app / dll).write_bytes(b"MZ")
    window = conftest.GameWindow(str(app), str(tmp_path / "out"))
    window._park_software_gl()
    window._restore_software_gl()
    assert not window._restore_failures, "the restore itself reported a failure; wrong case"

    lost = conftest.GameWindow.SOFTWARE_GL_DLLS[0]
    os.remove(str(app / lost))
    with pytest.raises(AssertionError) as caught:
        assert_no_parked_runtime_files(window)
    assert lost in str(caught.value)
    assert "missing from the shared build" in str(caught.value)


@pytest.mark.offline
def test_the_check_is_not_a_directory_scan_of_the_shared_build(tmp_path):
    """A CONCURRENT SIBLING'S legitimate parking must NOT fail this run. Measured, not theorised.

    The first spelling of this helper listed the shared app dir for ``*.gui-tier-parked`` and it
    failed twice against another agent's in-flight GUI run, which correctly has those DLLs parked
    for the duration of its own game. Same defect class as a bare "is any oolite.exe running?",
    which surviving_game_processes rejects for exactly this reason. So: a parked file THIS run
    did not create must be invisible to the check.
    """
    import conftest

    app = tmp_path / "oolite.app"
    app.mkdir()
    for dll in conftest.GameWindow.SOFTWARE_GL_DLLS:
        (app / dll).write_bytes(b"MZ")
    window = conftest.GameWindow(str(app), str(tmp_path / "out"))
    window._park_software_gl()
    window._restore_software_gl()

    # A sibling's parking: a parked file in the same directory that this window never touched.
    sibling = app / ("some_other.dll" + conftest.GameWindow._PARKED_SUFFIX)
    sibling.write_bytes(b"MZ")
    assert_no_parked_runtime_files(window)  # must NOT raise

    # And the helper must refuse a path outright, so the directory-scan spelling cannot return.
    with pytest.raises(AssertionError) as caught:
        assert_no_parked_runtime_files(str(app))
    assert "takes the GameWindow, not a path" in str(caught.value)


# --- the meta half: no future GUI test can forget --------------------------------------------
#
# AST, never a substring. A sibling bead's `assert "name" in body` was held green by the
# function's own docstring after both real assertions had been deleted; every check below reads
# ast.Call nodes out of the parsed tree, and the break twin two tests down proves it.


def launching_tests(path):
    """``{test_name: ast.FunctionDef}`` for every test in ``path`` that takes the game fixture.

    "Takes the ``game`` fixture" is the exact definition of a test that puts a real Oolite
    process on the desktop, so it is also the exact set that owes the tier a post-exit check.
    """
    with open(path, "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read())
    found = {}
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        if not node.name.startswith("test_"):
            continue
        args = [a.arg for a in node.args.args] + [a.arg for a in node.args.kwonlyargs]
        if "game" in args:
            found[node.name] = node
    return found


def called_names(func):
    """Every plain function name called anywhere inside ``func``, from the AST.

    ast.Call/ast.Name only: a docstring, a comment or an error message that happens to contain a
    helper's name is not a call and must not be able to hold this guard green.
    """
    return {
        node.func.id
        for node in ast.walk(func)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
    }


def post_exit_omissions(path):
    """``[(test_name, missing_helper), ...]`` for one tier file. Empty means compliant."""
    omissions = []
    for name, func in sorted(launching_tests(path).items()):
        calls = called_names(func)
        for helper in REQUIRED_POST_EXIT_HELPERS:
            if helper not in calls:
                omissions.append((name, helper))
    return omissions


@pytest.mark.offline
def test_every_launching_test_in_the_tier_asserts_post_exit_hygiene():
    """THE META-ASSERTION: a test that starts a game must ask what it left behind.

    Applied to every test file in this directory, so it covers files that do not exist yet. The
    required set is the baseline G1, G3 and G7 already share, which makes this a lock on the
    established contract rather than a new demand: the failure it prevents is a future G4/G5
    launching the game, asserting its own claim, and never noticing the orphan or the crash dump.
    """
    scanned, omissions = [], []
    for name in sorted(os.listdir(HERE)):
        if not (name.startswith("test_") and name.endswith(".py")):
            continue
        path = os.path.join(HERE, name)
        found = launching_tests(path)
        if found:
            scanned.append(f"{name}:{','.join(sorted(found))}")
        omissions += [(name, test, helper) for test, helper in post_exit_omissions(path)]

    # Not vacuous: if the scan finds no launching test at all, the loop above proved nothing.
    assert len(scanned) >= 3, (
        "the scan found launching tests in fewer than 3 files (%s); G1, G3 and G9 all take the "
        "game fixture, so this guard is not looking at what it thinks it is" % (scanned,)
    )
    assert not omissions, "launching test(s) skip a shared post-exit check:\n" + "\n".join(
        f"  {name}::{test} never calls {helper}()" for name, test, helper in omissions
    )


@pytest.mark.offline
def test_the_meta_assertion_fails_when_a_test_omits_a_helper():
    """BREAK TWIN: the same scanner over a deliberately non-compliant file must report it.

    This is what makes the guard above a test. Two twins are written, differing only in the one
    call: the compliant one must come back clean and the broken one must name the exact test and
    the exact helper. Run against source held in this function rather than against a file on
    disk, so it cannot be silenced by anything in the repository.
    """
    import tempfile

    compliant = (
        "def test_g4_something(game):\n"
        "    game.close_window()\n"
        "    assert_no_surviving_game_processes(game.proc.pid)\n"
        "    assert_clean_exit(game)\n"
    )
    # The realistic omission: the helper's NAME still appears, in a docstring and a comment,
    # exactly the way a substring guard gets fooled (the sibling-bead defect this avoids).
    broken = (
        "def test_g4_something(game):\n"
        '    """Exits cleanly; hygiene is assert_clean_exit\'s job."""\n'
        "    game.close_window()\n"
        "    # assert_clean_exit(game) - covered by G9\n"
        "    assert_no_surviving_game_processes(game.proc.pid)\n"
    )
    with tempfile.TemporaryDirectory() as tmp:
        good = os.path.join(tmp, "test_g4_good.py")
        bad = os.path.join(tmp, "test_g4_bad.py")
        with open(good, "w", encoding="utf-8") as handle:
            handle.write(compliant)
        with open(bad, "w", encoding="utf-8") as handle:
            handle.write(broken)
        clean = post_exit_omissions(good)
        caught = post_exit_omissions(bad)

    assert clean == [], f"the scanner flagged a compliant test: {clean}"
    assert caught == [("test_g4_something", "assert_clean_exit")], (
        "the scanner must name the test and the omitted helper; a docstring and a commented-out "
        "call mentioning assert_clean_exit must NOT satisfy it. Got: %r" % (caught,)
    )


@pytest.mark.offline
def test_the_scanner_reads_calls_and_not_text():
    """The AST rule itself: a name in a string or a comment is not a call.

    Asserted directly, because it is the single property that distinguishes this guard from the
    substring guard that was held green by a docstring after its assertions were deleted.
    """
    source = (
        "def test_x(game):\n"
        '    """assert_clean_exit assert_no_surviving_game_processes"""\n'
        "    # assert_clean_exit(game)\n"
        "    message = 'assert_clean_exit'\n"
        "    assert message\n"
    )
    tree = ast.parse(source)
    func = next(n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef))
    assert called_names(func) == set(), (
        "a docstring, a comment and a string literal produced call names; the scanner is reading "
        "text rather than the tree"
    )


@pytest.mark.offline
def test_the_fixture_itself_asserts_the_build_was_put_back():
    """The tier's ``game`` fixture must call assert_no_parked_runtime_files in its teardown.

    This is the route by which the parked-DLL property reaches EVERY test without any test having
    to remember it, so the route is what has to be asserted. AST again: the call must be a real
    ast.Call inside the fixture, and it must be in the ``finally`` handler - in the body it would
    be skipped by exactly the failed runs most likely to have stranded a DLL.
    """
    with open(os.path.join(HERE, "conftest.py"), "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read())
    fixture = next(
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.FunctionDef) and node.name == "game"
    )
    finalizers = [node for node in ast.walk(fixture) if isinstance(node, ast.Try)]
    assert finalizers, "the game fixture no longer has a try/finally teardown"
    in_finally = set()
    for node in finalizers:
        for stmt in node.finalbody:
            in_finally |= {
                sub.func.id
                for sub in ast.walk(stmt)
                if isinstance(sub, ast.Call) and isinstance(sub.func, ast.Name)
            }
    for helper in FIXTURE_REQUIRED_HELPERS:
        assert helper in in_finally, (
            f"the game fixture's teardown does not call {helper}(); without it a run that "
            "stranded a software-GL DLL in the SHARED build goes green and the breakage lands "
            "on the component tier (oo-e75)"
        )
    assert "kill" in {
        sub.func.attr
        for node in finalizers
        for stmt in node.finalbody
        for sub in ast.walk(stmt)
        if isinstance(sub, ast.Call) and isinstance(sub.func, ast.Attribute)
    }, "the teardown must still kill the game; the hygiene assert does not replace it"


@pytest.mark.offline
def test_g9_does_not_pretend_to_run_the_game_without_a_desktop():
    """The launching test must NOT be marked offline, and must take the game fixture.

    An ``offline`` G9 would be collected by the tier's clean-checkout command, pass without a
    game, and report that post-exit hygiene had been verified on a machine with no build. It must
    also not carry a skip marker of its own: OO_GUI_REQUIRE=1 turns the fixture's legitimate
    platform skip into a failure (conftest.require_gui_platform), and a decorator here would sit
    outside that mechanism and skip regardless.
    """
    path = os.path.join(HERE, "test_g9_post_exit_hygiene.py")
    with open(path, "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read())
    func = next(
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.FunctionDef)
        and node.name == "test_g9_post_exit_hygiene_holds_after_a_real_exit"
    )
    assert "game" in [a.arg for a in func.args.args], "the launching test must take the fixture"
    for decorator in func.decorator_list:
        text = ast.unparse(decorator) if hasattr(ast, "unparse") else ""
        assert "offline" not in text, (
            "the launching test is marked offline; it would then be collected and PASS in a "
            f"checkout with no build. Decorator: {text}"
        )
        assert "skip" not in text, (
            "the launching test carries its own skip marker, which sits outside "
            "OO_GUI_REQUIRE's control and can hide a run that never happened (oo-7by1). "
            f"Decorator: {text}"
        )
    # No conditional-import skip anywhere in this file either (oo-7by1: a hard dependency must
    # fail, not skip). Asserted off the AST so this guard's own mention of the name in a string
    # cannot be what it finds.
    calls = {
        node.func.attr
        for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
    }
    assert "importorskip" not in calls, (
        "no importorskip in this tier: a hard dependency must fail, not skip (oo-7by1)"
    )


@pytest.mark.offline
def test_the_witnesses_are_the_strings_the_game_really_writes():
    """Each witness must be findable in the source that emits it, not merely plausible.

    A typo in any of the three would make assert_shutdown_path_completed fail every clean exit,
    and the failure would read as "the shutdown path is broken" rather than "the test is looking
    for the wrong string". Both source files are asserted to EXIST first, so a moved file is a
    failure rather than a check that quietly stops running.
    """
    src = os.path.abspath(os.path.join(HERE, "..", "..", "src", "Core"))
    controller = os.path.join(src, "GameController.m")
    handler = os.path.join(src, "OOLogOutputHandler.m")
    for path in (controller, handler):
        assert os.path.isfile(path), (
            f"no {os.path.basename(path)} at {path}; this guard cannot verify the witnesses "
            "against source that is not there, and silently passing would leave a typo in them "
            "undetectable"
        )

    with open(controller, "r", encoding="utf-8", errors="replace") as handle:
        source = handle.read()
    assert SHUTDOWN_DEFAULTS_WITNESS in source, (
        f"{SHUTDOWN_DEFAULTS_WITNESS!r} is not in GameController.m; the post-synchronize log "
        "line has been reworded and this witness now matches nothing"
    )
    assert 'OOLog(@"exit.context"' in source, (
        "GameController.m no longer logs the exit.context domain, so "
        f"{SHUTDOWN_EXIT_CONTEXT_WITNESS!r} can never appear in a log"
    )
    assert "OOLoggingTerminate" in source, (
        "-exitAppWithContext: no longer calls OOLoggingTerminate, so the log footer "
        f"{SHUTDOWN_LOG_CLOSED_WITNESS!r} is never written on the way out"
    )

    # The footer itself is written by the output handler's postamble, not by GameController.
    with open(handler, "r", encoding="utf-8", errors="replace") as handle:
        assert SHUTDOWN_LOG_CLOSED_WITNESS in handle.read(), (
            f"{SHUTDOWN_LOG_CLOSED_WITNESS!r} is not the postamble OOLogOutputHandler.m writes"
        )
