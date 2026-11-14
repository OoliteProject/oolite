"""G11 - the INHERITED dirty baseline: a parked software-GL DLL this run did not park.

    python3 -m pytest upstream/oolite/tests/gui/test_g11_inherited_parked_baseline.py -x -q

THE INCIDENT THIS FILE REPRODUCES (oo-992b)
-------------------------------------------
On Sep 16 a GUI run died between ``_park_software_gl`` and ``_restore_software_gl`` and left
the shared build in this exact state:

    libgallium_wgl.dll.gui-tier-parked   23778874 bytes   mtime 2026-09-16 21:55
    opengl32.dll.gui-tier-parked           132747 bytes   mtime 2026-09-16 21:06
    real opengl32.dll: ABSENT              real libgallium_wgl.dll: ABSENT

It stayed that way for a full day, across dozens of runs by five agents, and every one of those
runs was GREEN. The component tier's offscreen rendering was broken on disk the whole time.

WHY EVERY RUN PASSED. ``assert_no_parked_runtime_files`` is scoped to THIS run's own bookkeeping
(``_parked_ever`` / ``_restore_failures``) and that scoping is CORRECT - oo-e75 measured a naive
directory scan at teardown failing twice on a concurrent sibling's legitimate in-flight parking.
But a check of "did I put back what I moved" is spotless when the answer is "I moved nothing,
because it was already moved". The guard proves a run is clean; it is structurally incapable of
seeing a baseline that was dirty before the run began. That is not a bug in that guard, it is a
missing SECOND guard, and this file is the test for it.

Every test here is ``offline``: the guard is pure filesystem bookkeeping on a temporary
directory, so it gates in a clean checkout with no build and no desktop.
"""

import atexit
import os
import time

import pytest

import conftest
from conftest import (
    GameWindow,
    assert_no_inherited_parked_runtime_files,
    assert_no_parked_runtime_files,
)

SUFFIX = GameWindow._PARKED_SUFFIX


def _app_with_dlls(tmp_path, name="oolite.app"):
    """A stand-in app dir holding both software-GL DLLs at their REAL names."""
    app = tmp_path / name
    app.mkdir()
    for dll in GameWindow.SOFTWARE_GL_DLLS:
        (app / dll).write_bytes(b"MZ" + dll.encode())
    return app


@pytest.mark.offline
def test_guard_fires_on_an_inherited_parked_dll_and_names_it_with_its_mtime(tmp_path):
    """THE INCIDENT, replayed: a parked twin with NO live DLL, parked by nobody in this process.

    This is the Sep 16 state reconstructed byte-for-role: the real name absent, the parked name
    present, and a process that has parked nothing of its own walking into it.
    """
    app = _app_with_dlls(tmp_path)
    stranded = GameWindow.SOFTWARE_GL_DLLS[0]
    live = app / stranded
    parked = app / (stranded + SUFFIX)
    # Strand it exactly as a killed run does: rename, then die. No delete - the parked file IS
    # the real DLL under another name.
    os.replace(str(live), str(parked))
    old = time.time() - 24 * 3600
    os.utime(str(parked), (old, old))
    assert not live.is_file(), "precondition: the real DLL must be ABSENT, as it was on Sep 16"
    assert parked.is_file(), "precondition: the parked twin must be present"

    with pytest.raises(AssertionError) as caught:
        assert_no_inherited_parked_runtime_files(
            str(app), GameWindow.SOFTWARE_GL_DLLS, SUFFIX
        )

    message = str(caught.value)
    assert stranded in message, "the failure must NAME the stranded DLL"
    assert "INHERITED" in message, "the failure must say this baseline was inherited, not caused"
    # The mtime is the evidence identifying WHICH run died; a message without it cannot be
    # investigated.
    stamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(old))
    assert stamp in message, f"the failure must carry the parked file's mtime {stamp}"
    assert str(app) in message, "the failure must name the shared build it found dirty"


@pytest.mark.offline
def test_the_guard_heals_the_build_before_it_fails(tmp_path):
    """It renames the DLL back FIRST and fails SECOND. Both halves matter.

    Failing without repairing leaves five agents broken until a human reads the message.
    Repairing without failing is a silent fix nobody investigates. So: after the guard raises,
    the real DLL must be on disk at its real name with its real contents.
    """
    app = _app_with_dlls(tmp_path)
    stranded = GameWindow.SOFTWARE_GL_DLLS[1]
    payload = (app / stranded).read_bytes()
    os.replace(str(app / stranded), str(app / (stranded + SUFFIX)))

    with pytest.raises(AssertionError) as caught:
        assert_no_inherited_parked_runtime_files(
            str(app), GameWindow.SOFTWARE_GL_DLLS, SUFFIX
        )
    assert "RECOVERED" in str(caught.value)

    assert (app / stranded).is_file(), "the guard must rename the DLL back, not merely report it"
    assert (app / stranded).read_bytes() == payload, "the restored file must be the SAME bytes"
    assert not (app / (stranded + SUFFIX)).is_file(), "the parked twin must be gone, by RENAME"


@pytest.mark.offline
def test_the_guard_never_deletes_when_both_names_are_present(tmp_path):
    """A parked twin beside a live DLL is 23MB of real driver. It must survive the guard.

    Renaming here would destroy the live file; deleting would destroy the parked one. The only
    safe action is to report and keep both.
    """
    app = _app_with_dlls(tmp_path)
    dll = GameWindow.SOFTWARE_GL_DLLS[0]
    parked = app / (dll + SUFFIX)
    parked.write_bytes(b"MZ-parked-twin-real-driver")

    with pytest.raises(AssertionError) as caught:
        assert_no_inherited_parked_runtime_files(
            str(app), GameWindow.SOFTWARE_GL_DLLS, SUFFIX
        )
    assert "COULD NOT recover" in str(caught.value)
    assert "do NOT delete" in str(caught.value)
    assert parked.is_file(), "the parked twin must NOT be deleted"
    assert parked.read_bytes() == b"MZ-parked-twin-real-driver", "its bytes must be untouched"
    assert (app / dll).is_file(), "the live DLL must NOT be clobbered"


@pytest.mark.offline
def test_the_guard_passes_once_the_planted_file_is_removed(tmp_path):
    """The other half of the proof: on a CLEAN baseline it returns quietly.

    A guard that fires on everything is as useless as one that fires on nothing.
    """
    app = _app_with_dlls(tmp_path)
    dll = GameWindow.SOFTWARE_GL_DLLS[0]
    planted = app / (dll + SUFFIX)
    planted.write_bytes(b"MZ")
    with pytest.raises(AssertionError):
        assert_no_inherited_parked_runtime_files(
            str(app), GameWindow.SOFTWARE_GL_DLLS, SUFFIX
        )

    os.remove(str(planted))
    # REQUIRE THE SUBJECT FIRST: both real DLLs present by name. "no parked files" is trivially
    # true of an empty directory, so the clean case must assert the DLLs are THERE.
    for name in GameWindow.SOFTWARE_GL_DLLS:
        assert (app / name).is_file(), f"{name} must be present for this to be a clean baseline"
    assert (
        assert_no_inherited_parked_runtime_files(str(app), GameWindow.SOFTWARE_GL_DLLS, SUFFIX)
        == []
    )


@pytest.mark.offline
def test_park_calls_the_inherited_guard_so_a_dirty_baseline_aborts_the_run(tmp_path):
    """Wired in, not merely written: _park_software_gl must refuse a dirty build.

    A guard nothing calls is documentation. The park step is the right place because it is the
    first thing that touches these files, and aborting there means the run never launches a game
    against a build whose software GL is missing.
    """
    app = _app_with_dlls(tmp_path)
    stranded = GameWindow.SOFTWARE_GL_DLLS[0]
    os.replace(str(app / stranded), str(app / (stranded + SUFFIX)))

    window = GameWindow(str(app), str(tmp_path / "out"))
    with pytest.raises(AssertionError) as caught:
        window._park_software_gl()
    assert stranded in str(caught.value)
    assert "INHERITED" in str(caught.value)
    # And it aborted BEFORE parking anything of its own: the second DLL is untouched.
    survivor = GameWindow.SOFTWARE_GL_DLLS[1]
    assert (app / survivor).is_file(), "the guard must abort BEFORE this run parks its own DLLs"
    assert not (app / (survivor + SUFFIX)).is_file()


@pytest.mark.offline
def test_a_clean_park_restore_round_trip_still_works(tmp_path):
    """The guard must not break the normal path: park, restore, both DLLs back, run clean."""
    app = _app_with_dlls(tmp_path)
    window = GameWindow(str(app), str(tmp_path / "out"))
    window._park_software_gl()
    assert window.inherited_recovered == [], "a clean baseline inherits nothing"
    assert sorted(os.path.basename(p) for p in window._parked_ever) == sorted(
        GameWindow.SOFTWARE_GL_DLLS
    ), "the real parking step must still move both DLLs aside"
    for dll in GameWindow.SOFTWARE_GL_DLLS:
        assert (app / (dll + SUFFIX)).is_file(), f"{dll} should be parked during the run"

    window._restore_software_gl()
    for dll in GameWindow.SOFTWARE_GL_DLLS:
        assert (app / dll).is_file(), f"{dll} must be restored"
        assert not (app / (dll + SUFFIX)).is_file()
    assert_no_parked_runtime_files(window)


# --- crash safety -------------------------------------------------------------------------------
#
# The failure modes are specific and all three were seen in one session: a subagent timeout at
# 3600s, a taskkill, and an orchestrator stop. A ``finally`` in a fixture does NOT run when the
# interpreter is killed outright, so crash safety cannot rest on it. Two layers answer that:
#
#   1. atexit - covers the shutdowns that DO unwind the interpreter.
#   2. the setup guard above - covers the ones that do not, because it needs no cooperation at
#      all from the process that died. That is the layer that actually fixes this bug.


@pytest.mark.offline
def test_atexit_restore_is_idempotent_after_a_normal_restore(tmp_path):
    """The atexit hook must be a no-op once the ordinary teardown has already restored.

    Otherwise a second rename at interpreter shutdown could clobber a concurrent sibling's
    freshly-parked state - turning a safety net into the very bug it guards against.

    THIS TEST WAS REWRITTEN (oo-992b review) BECAUSE ITS FIRST VERSION WAS VACUOUS. That
    version simulated the sibling by ALSO writing a placeholder at the live name
    (``b"MZ-a-sibling-put-something-here"``). A placeholder OCCUPIES the live name, so the
    hook's "parked exists AND live free" condition was false and the hook returned without
    doing anything - the test exercised the one branch that is already safe and never reached
    the unsafe one. It was green while the race it is named after was wide open.

    A REAL park is a RENAME, so the sibling's real end state is: parked twin PRESENT, live
    name FREE. That is byte-for-byte the state the old condition treated as "safe to rename
    back", which is why the condition could never exclude this race: it is satisfied BY the
    race. Reproduced cross-process by the reviewer - A parks, A restores, A releases the
    gui-lock, B acquires it and legitimately parks, A's interpreter exits and A's hook renames
    B's park back - after which B's own restore records both DLLs as failures and B's game is
    mid-flight on a build whose software GL it had deliberately parked.
    """
    app = _app_with_dlls(tmp_path)
    window = GameWindow(str(app), str(tmp_path / "out"))
    dll = GameWindow.SOFTWARE_GL_DLLS[0]
    live = str(app / dll)
    parked = app / (dll + SUFFIX)

    window._park_software_gl()
    window._restore_software_gl()
    payload = (app / dll).read_bytes()

    # THE SIBLING'S REAL END STATE, and nothing else: a rename, with NO placeholder written at
    # the live name. Asserted as preconditions so this test can never silently regress into the
    # vacuous shape again.
    os.replace(live, str(parked))
    assert parked.is_file(), "precondition: a sibling's legitimate park leaves the parked twin"
    assert not (app / dll).is_file(), (
        "precondition: and leaves the live name FREE - that is what parking MEANS, and writing "
        "a placeholder here is what made the previous version of this test vacuous"
    )

    # Our interpreter now exits; the hook registered at OUR park time fires LATE.
    window._restore_one_at_exit(live)

    assert parked.is_file(), (
        "the late atexit hook CLOBBERED a concurrent sibling's freshly-parked DLL. Once our own "
        "teardown has restored, the hook must be DISARMED - being conditional on 'parked exists "
        "and live free' is no protection, because a legitimate park reproduces that state "
        "exactly (oo-992b)"
    )
    assert not (app / dll).is_file(), (
        "the late hook renamed the sibling's parked DLL back to its live name mid-run, silently "
        "switching the sibling's rendering path during its own run"
    )
    assert parked.read_bytes() == payload, "and the sibling's parked bytes must be untouched"

    # Firing again must stay a no-op: disarmed is disarmed, not "once per extra call".
    window._restore_one_at_exit(live)
    assert parked.is_file() and not (app / dll).is_file(), (
        "a second late firing must also be inert"
    )


@pytest.mark.offline
def test_atexit_restore_still_repairs_when_the_normal_teardown_never_ran(tmp_path):
    """The companion to the test above: disarming must not neuter the crash path.

    Disarming the hook after a normal restore would be trivial to "pass" by making the hook do
    nothing at all. So this pins the case the hook exists for: a run that parks and then unwinds
    the interpreter WITHOUT reaching its teardown must still get its DLL renamed back.
    """
    app = _app_with_dlls(tmp_path)
    window = GameWindow(str(app), str(tmp_path / "out"))
    dll = GameWindow.SOFTWARE_GL_DLLS[0]
    live = str(app / dll)
    payload = (app / dll).read_bytes()

    window._park_software_gl()
    assert not (app / dll).is_file(), "parked, so the live name is free"
    assert (app / (dll + SUFFIX)).is_file()

    # No _restore_software_gl() at all - this run is dying. atexit is all that is left.
    window._restore_one_at_exit(live)

    assert (app / dll).is_file(), "the atexit hook must still rename back on the crash path"
    assert (app / dll).read_bytes() == payload, "and restore the same bytes"
    assert not (app / (dll + SUFFIX)).is_file(), "by RENAME, leaving no parked twin"

    # Tidy the second DLL so the temp dir ends clean.
    window._restore_software_gl()


@pytest.mark.offline
def test_a_normal_restore_unregisters_its_atexit_hooks(tmp_path):
    """Hooks must not accumulate across a long pytest session.

    The hook was registered at EVERY park and never unregistered, so a session that parks once
    per test walked out of pytest with one live hook per park - every one of them a candidate to
    fire late against whatever the build looked like by then. A normal restore must hand its
    registrations back.
    """
    app = _app_with_dlls(tmp_path)
    window = GameWindow(str(app), str(tmp_path / "out"))
    unregistered = []
    real = conftest.atexit.unregister

    def spy(func):
        unregistered.append(func)
        return real(func)

    conftest.atexit.unregister = spy
    try:
        before = atexit._ncallbacks()
        window._park_software_gl()
        assert atexit._ncallbacks() == before + len(GameWindow.SOFTWARE_GL_DLLS), (
            "park should register one hook per DLL it moves aside"
        )
        window._restore_software_gl()
        assert atexit._ncallbacks() == before, (
            "a normal restore must leave NO atexit hooks of its own behind; they accumulated "
            "one per park across the whole session (oo-992b)"
        )
    finally:
        conftest.atexit.unregister = real

    assert window._restore_one_at_exit in unregistered, (
        "the restore must unregister its own hook, by identity of the bound method"
    )


@pytest.mark.offline
def test_atexit_hook_is_registered_by_the_park_step(tmp_path):
    """Registered at PARK time, one per DLL - not at teardown, which a kill never reaches."""
    app = _app_with_dlls(tmp_path)
    window = GameWindow(str(app), str(tmp_path / "out"))
    registered = []
    real = conftest.atexit.register

    def spy(func, *args, **kwargs):
        registered.append((func, args))
        return real(func, *args, **kwargs)

    conftest.atexit.register = spy
    try:
        window._park_software_gl()
    finally:
        conftest.atexit.register = real
        window._restore_software_gl()

    hooks = [args[0] for func, args in registered if func == window._restore_one_at_exit]
    assert sorted(os.path.basename(p) for p in hooks) == sorted(
        GameWindow.SOFTWARE_GL_DLLS
    ), "park must register an atexit unpark for EVERY DLL it moves aside"


# --- durable incident evidence ------------------------------------------------------------------
#
# heal-then-fail is the right ordering, but it costs reproducibility: run 1 repairs and fails, and
# a CI retry then finds a clean baseline and goes green. Without a durable record, a retry erases
# the incident - including the parked mtime that says WHICH run died.


@pytest.mark.offline
def test_the_guard_appends_a_durable_breadcrumb_naming_the_path_and_mtime(tmp_path):
    """The evidence must outlive the process that found it.

    ``window.inherited_recovered`` is populated, but it is in-memory and dies with the run. A
    file in the build directory is what a human or a CI artifact collector can still read after
    the retry has gone green.
    """
    app = _app_with_dlls(tmp_path)
    stranded = GameWindow.SOFTWARE_GL_DLLS[0]
    parked = app / (stranded + SUFFIX)
    os.replace(str(app / stranded), str(parked))
    old = time.time() - 36 * 3600
    os.utime(str(parked), (old, old))
    stamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(old))

    crumb = app / conftest.INHERITED_PARKED_BREADCRUMB
    assert not crumb.exists(), "precondition: no breadcrumb before the incident"

    with pytest.raises(AssertionError) as caught:
        assert_no_inherited_parked_runtime_files(str(app), GameWindow.SOFTWARE_GL_DLLS, SUFFIX)

    assert crumb.is_file(), (
        "the guard healed the build and failed, so the incident is now UNREPRODUCIBLE; without "
        "a durable breadcrumb a CI retry erases it entirely (oo-992b)"
    )
    text = crumb.read_text(encoding="utf-8")
    assert stranded in text, "the breadcrumb must name the stranded DLL"
    assert stamp in text, f"and carry the parked mtime {stamp} that identifies WHICH run died"
    assert "RECOVERED" in text, "and say what was done about it"
    assert str(os.getpid()) in text, "and name the pid that found it"
    # And the failure text must point at it, or nobody will know to look.
    assert conftest.INHERITED_PARKED_BREADCRUMB in str(caught.value)


@pytest.mark.offline
def test_a_ci_retry_cannot_erase_the_breadcrumb(tmp_path):
    """THE POINT OF THE BREADCRUMB: run 1 fails, run 2 passes, the evidence survives run 2.

    This is the heal-then-fail trade-off made safe. Run 2 is genuinely green - the build really
    is repaired - so nothing about it should be changed; what must not happen is run 2 erasing
    the only record that run 1 found a broken build.
    """
    app = _app_with_dlls(tmp_path)
    stranded = GameWindow.SOFTWARE_GL_DLLS[0]
    os.replace(str(app / stranded), str(app / (stranded + SUFFIX)))
    crumb = app / conftest.INHERITED_PARKED_BREADCRUMB

    # --- run 1: heals and fails.
    with pytest.raises(AssertionError):
        assert_no_inherited_parked_runtime_files(str(app), GameWindow.SOFTWARE_GL_DLLS, SUFFIX)
    after_run_1 = crumb.read_text(encoding="utf-8")
    assert after_run_1.count("\n") == 1, "one stranded DLL, one line"

    # --- run 2, the CI retry: the baseline is clean now, so it PASSES.
    assert (
        assert_no_inherited_parked_runtime_files(str(app), GameWindow.SOFTWARE_GL_DLLS, SUFFIX)
        == []
    ), "the retry passes, which is exactly why the evidence must be durable"
    assert crumb.read_text(encoding="utf-8") == after_run_1, (
        "a green retry must not truncate or rewrite the incident record"
    )

    # --- a SECOND, genuinely new incident appends rather than replacing the first.
    other = GameWindow.SOFTWARE_GL_DLLS[1]
    os.replace(str(app / other), str(app / (other + SUFFIX)))
    with pytest.raises(AssertionError):
        assert_no_inherited_parked_runtime_files(str(app), GameWindow.SOFTWARE_GL_DLLS, SUFFIX)
    final = crumb.read_text(encoding="utf-8")
    assert final.startswith(after_run_1), "the first incident's line must still be there, intact"
    assert final.count("\n") == 2, "and the second incident must have been APPENDED"
    assert other in final.split("\n")[1]


@pytest.mark.offline
def test_a_clean_baseline_writes_no_breadcrumb(tmp_path):
    """No incident, no file. A breadcrumb that appears on every run is noise, not evidence."""
    app = _app_with_dlls(tmp_path)
    for name in GameWindow.SOFTWARE_GL_DLLS:
        assert (app / name).is_file(), f"{name} must be present for this to be a clean baseline"
    assert (
        assert_no_inherited_parked_runtime_files(str(app), GameWindow.SOFTWARE_GL_DLLS, SUFFIX)
        == []
    )
    assert not (app / conftest.INHERITED_PARKED_BREADCRUMB).exists()


@pytest.mark.offline
def test_an_unwritable_breadcrumb_does_not_mask_the_incident(tmp_path):
    """Evidence must never become control flow.

    The breadcrumb is written on the way to a deliberate AssertionError. If the build directory
    is read-only or full, the loud failure about the STRANDED DLL must still be what comes out -
    not a confusing error about a log file.
    """
    app = _app_with_dlls(tmp_path)
    stranded = GameWindow.SOFTWARE_GL_DLLS[0]
    os.replace(str(app / stranded), str(app / (stranded + SUFFIX)))

    real_open = conftest.open if hasattr(conftest, "open") else open

    def exploding_open(*args, **kwargs):
        if args and str(args[0]).endswith(conftest.INHERITED_PARKED_BREADCRUMB):
            raise OSError(13, "Permission denied")
        return real_open(*args, **kwargs)

    conftest.open = exploding_open
    try:
        with pytest.raises(AssertionError) as caught:
            assert_no_inherited_parked_runtime_files(
                str(app), GameWindow.SOFTWARE_GL_DLLS, SUFFIX
            )
    finally:
        del conftest.open

    assert stranded in str(caught.value), "the real incident must still be reported"
    assert "INHERITED" in str(caught.value)
    assert (app / stranded).is_file(), "and the build must still have been healed"


@pytest.mark.offline
def test_a_killed_process_leaves_a_baseline_the_next_run_repairs(tmp_path):
    """END TO END, the property that actually closes oo-992b.

    Run A parks and is killed dead - no teardown, no atexit, nothing. Run B starts against the
    same shared build. Run B must NOT proceed silently: it must repair the build and fail loudly.
    This is the sequence that went unnoticed for a day.
    """
    app = _app_with_dlls(tmp_path)
    payloads = {d: (app / d).read_bytes() for d in GameWindow.SOFTWARE_GL_DLLS}

    # --- run A: parks, then dies. Its GameWindow object is simply dropped.
    run_a = GameWindow(str(app), str(tmp_path / "out-a"))
    run_a._park_software_gl()
    del run_a  # no kill(), no finally, no atexit: killed processes run none of them
    for dll in GameWindow.SOFTWARE_GL_DLLS:
        assert not (app / dll).is_file(), "the build is now broken, as it was on Sep 16"

    # --- the old guard's blind spot, demonstrated: run B's own bookkeeping is spotless.
    # (This is exactly why a full day of runs went green.)
    innocent = GameWindow(str(app), str(tmp_path / "out-b"))
    assert_no_parked_runtime_files(innocent)  # passes - and the build is broken

    # --- run B: the new guard sees what run B's bookkeeping cannot.
    run_b = GameWindow(str(app), str(tmp_path / "out-b"))
    with pytest.raises(AssertionError) as caught:
        run_b._park_software_gl()
    for dll in GameWindow.SOFTWARE_GL_DLLS:
        assert dll in str(caught.value), f"the failure must name {dll}"
        assert (app / dll).is_file(), f"{dll} must be back at its REAL name"
        assert (app / dll).read_bytes() == payloads[dll], "and must be the same bytes"
