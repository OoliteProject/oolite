"""The tier's own guard against reporting a pass for a run that never happened.

These tests are `offline`: no desktop, no built game, no pyautogui. They exist because the
failure they cover is invisible by construction — when the GUI tier skips, every command in the
DoD path still exits 0, and the only way to notice is to assert on the skip machinery itself.

Bug oo-7by1: `pytest.importorskip("pyautogui")` inside the `game` fixture meant the G1 DoD
command exited 0 green on three separate configurations where G1 never executed (non-Windows;
Windows without pyautogui; and any machine at all, since nothing installed requirements.txt).
"""

import ast
import os
import subprocess
import sys
import time

import pytest

import conftest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
RUNNER = os.path.join(REPO_ROOT, "tools", "gui-tier.sh")


@pytest.mark.offline
def test_no_importorskip_anywhere_in_the_tier():
    """A hard dependency must fail, not skip.

    importorskip turns a broken environment into a green run. If this assertion ever needs
    relaxing, the thing being imported is by definition not a hard dependency of this tier.
    """
    for name in sorted(os.listdir(HERE)):
        if not name.endswith(".py"):
            continue
        with open(os.path.join(HERE, name), "r", encoding="utf-8") as handle:
            tree = ast.parse(handle.read(), filename=name)
        called = {
            node.func.attr if isinstance(node.func, ast.Attribute) else getattr(node.func, "id", "")
            for node in ast.walk(tree)
            if isinstance(node, ast.Call)
        }
        assert "importorskip" not in called, (
            f"{name} calls pytest.importorskip; a missing hard dependency in this tier must "
            "fail with the install command, not skip to a silent pass (oo-7by1)"
        )


@pytest.mark.offline
def test_missing_pyautogui_fails_rather_than_skips(monkeypatch):
    """With pyautogui unimportable, the dependency gate raises Failed, not Skipped."""
    # A None entry in sys.modules is exactly how CPython reports "this import fails".
    monkeypatch.setitem(sys.modules, "pyautogui", None)

    with pytest.raises(BaseException) as caught:
        conftest.require_gui_dependencies()

    assert not isinstance(caught.value, pytest.skip.Exception), (
        "a missing pyautogui skipped instead of failing"
    )
    assert isinstance(caught.value, pytest.fail.Exception), (
        f"expected a hard failure, got {type(caught.value).__name__}"
    )
    message = str(caught.value)
    assert "pip install -r" in message, "the failure must name the exact install command"
    assert "requirements.txt" in message


@pytest.mark.offline
def test_requirements_names_the_tier_dependencies():
    with open(os.path.join(HERE, "requirements.txt"), "r", encoding="utf-8") as handle:
        names = {line.split("=")[0].split(">")[0].strip().lower() for line in handle if line.strip()}
    assert "pyautogui" in names
    assert "pytest" in names


@pytest.mark.offline
def test_a_runner_installs_the_requirements():
    """requirements.txt must be installed by something the DoD path actually runs.

    Vendoring the dependency, or documenting the install in prose nobody executes, both leave
    the missing-pyautogui case as the expected case.
    """
    assert os.path.isfile(RUNNER), "tools/gui-tier.sh is the tier's runner and must exist"
    with open(RUNNER, "r", encoding="utf-8") as handle:
        script = handle.read()
    assert "requirements.txt" in script
    assert "pip install" in script
    assert "OO_GUI_REQUIRE=1" in script, (
        "the runner must disarm the not-applicable-platform skip, or it can still exit 0 green "
        "on a machine that never ran G1"
    )
    if os.name != "nt":
        bash = ["bash", "-n", RUNNER]
        assert subprocess.run(bash, capture_output=True).returncode == 0, "runner is not valid bash"


@pytest.mark.offline
def test_wrong_platform_skip_is_a_failure_when_the_run_demanded_g1(monkeypatch):
    """OO_GUI_REQUIRE=1 (what the runner exports) removes the last vacuous-pass path."""
    gate = conftest.require_gui_platform
    monkeypatch.setattr(conftest, "IS_WINDOWS", False)

    monkeypatch.setattr(conftest, "GUI_REQUIRED", False)
    with pytest.raises(pytest.skip.Exception) as skipped:
        gate()
    assert "ADR-0017" in str(skipped.value), "the one legitimate skip must say why"

    monkeypatch.setattr(conftest, "GUI_REQUIRED", True)
    with pytest.raises(BaseException) as caught:
        gate()
    assert isinstance(caught.value, pytest.fail.Exception), (
        "with OO_GUI_REQUIRE set, the wrong platform must fail, not skip"
    )


@pytest.mark.offline
def test_oo_gui_require_is_honoured_by_the_fixture_source():
    """The env var has to reach the non-Windows branch, not merely exist."""
    with open(os.path.join(HERE, "conftest.py"), "r", encoding="utf-8") as handle:
        source = handle.read()
    assert "OO_GUI_REQUIRE" in source
    gate = source.split("def require_gui_platform(", 1)[1].split("\ndef ", 1)[0]
    assert "GUI_REQUIRED" in gate, "the precondition gate must consult OO_GUI_REQUIRE"
    runtime = source.split("def gui_runtime(", 1)[1].split("\n@pytest.fixture", 1)[0]
    assert "require_gui_platform()" in runtime
    assert "require_gui_dependencies()" in runtime
    # And the gate must be wired into the fixture the real test actually uses, first, so the
    # platform skip is reachable without a built game.
    game_sig = source.split("def game(", 1)[1].split(")", 1)[0]
    assert game_sig.split(",")[0].strip() == "gui_runtime"


# --- bug oo-5rsa: the three post-exit hygiene checks must be able to FAIL ----------------------
#
# assert_clean_exit promised "no core dump, no ERROR in Latest.log, and a defaults file that still
# parses", and the story (docs/stories/G1-exit-via-mouse.md:13,46) additionally requires "no
# orphaned process". Three of those were missing or true by construction:
#
#   * the defaults re-parse was never implemented at all;
#   * `if os.path.isfile(log):` meant an ABSENT Latest.log silently passed the log check, even
#     though _await_startup_complete had already proved that file existed in the same run;
#   * `assert game.proc.poll() == 0` only re-read a returncode wait() had already reaped, so it
#     could not return anything else.
#
# A check that cannot fail is not a check. Each test below CONSTRUCTS the failure and asserts the
# check notices it, so none of the three can silently revert to a tautology.


def _healthy_output_dir(tmp_path):
    out = tmp_path / "out"
    out.mkdir(exist_ok=True)
    (out / "Latest.log").write_text(
        "[log.header] Opening log\n"
        "[display.initGL] Requested a new surface of 960 x 720, windowed\n"
        "[searchPaths.dumpAll] Resource paths\n"
        "[shipData.load.begin] Loading ship data\n"
        "[startup.complete] Startup complete\n"
        "[exit.context] Exiting: exit game.\n",
        encoding="utf-8",
    )
    return str(out)


def _healthy_app_dir(tmp_path, plist_text=None):
    """An app dir holding a defaults file in the dialect gnustep-base really writes.

    The shape of upstream/oolite/build/meson_test/oolite.app/GNUstep/Defaults/oolite.plist as
    written by a real run on this machine: OpenStep ("old-style"), not XML.
    """
    app = tmp_path / "oolite.app"
    defaults = app / "GNUstep" / "Defaults"
    defaults.mkdir(parents=True, exist_ok=True)
    (defaults / "oolite.plist").write_text(
        plist_text
        if plist_text is not None
        else (
            '{\n'
            '    "debug-settings-override" = {\n'
            '    };\n'
            '    "volume_control" = "0.5";\n'
            '    window_height = 720;\n'
            '    window_width = 960;\n'
            '}\n'
        ),
        encoding="utf-8",
    )
    return str(app)


def _plist_in(app_dir):
    return os.path.join(app_dir, "GNUstep", "Defaults", "oolite.plist")


def _launched_at(app_dir):
    """The mark GameWindow.start() would have recorded, taken now (= 'before this run')."""
    return conftest.defaults_write_mark(app_dir)


def _rewritten_now(app_dir, text=None):
    """Mark the app dir as it was at launch, then write the plist AS THIS RUN WOULD.

    Returns the launch mark. The rewrite is forced to a strictly later mtime rather than
    trusting the clock: filesystem timestamp granularity (FAT/some network mounts) is coarse
    enough that two writes inside the same test can share an mtime, and a flaky helper would
    make the real assertion look flaky instead of the code.
    """
    mark = _launched_at(app_dir)
    plist = _plist_in(app_dir)
    before = mark.get(plist)
    if text is not None:
        with open(plist, "w", encoding="utf-8") as handle:
            handle.write(text)
    else:
        with open(plist, "a", encoding="utf-8") as handle:
            handle.write("")
    if before is not None:
        newer = before[0] + 1_000_000_000  # one second later, in ns
        os.utime(plist, ns=(newer, newer))
    return mark


def _clean_exit(out, app, mark):
    return conftest.assert_clean_exit(out, app, mark)


@pytest.mark.offline
def test_the_real_defaults_dialect_parses(tmp_path):
    """The healthy case must PASS - a check that rejects a good file is no use either.

    gnustep-base emits OpenStep, so a check built on plistlib alone would fail every real file.
    """
    app = _healthy_app_dir(tmp_path)
    mark = _rewritten_now(app)
    path, contents = conftest.assert_defaults_file_reparses(app, mark)
    assert contents["window_width"] == "960"
    assert contents["debug-settings-override"] == {}
    assert path.endswith(os.path.join("GNUstep", "Defaults", "oolite.plist"))


@pytest.mark.offline
def test_assert_clean_exit_accepts_a_healthy_run(tmp_path):
    app = _healthy_app_dir(tmp_path)
    _clean_exit(_healthy_output_dir(tmp_path), app, _rewritten_now(app))


@pytest.mark.offline
def test_a_defaults_file_absent_at_launch_counts_as_written(tmp_path):
    """The first ever run on a clean tree: no file at launch, a file afterwards.

    Existence is a stronger witness than any timestamp here, and this case must still pass or
    the check would fail every fresh checkout.
    """
    app = str(tmp_path / "oolite.app")
    os.makedirs(os.path.join(app, "GNUstep", "Defaults"), exist_ok=True)
    mark = _launched_at(app)                      # nothing on disk yet
    assert mark[_plist_in(app)] is None
    _healthy_app_dir(tmp_path)                    # ... and now the run writes it
    _clean_exit(_healthy_output_dir(tmp_path), app, mark)


@pytest.mark.offline
def test_a_missing_defaults_file_fails(tmp_path):
    """FAILURE 1a: the defaults file is not written at all."""
    out = _healthy_output_dir(tmp_path)
    app = _healthy_app_dir(tmp_path)
    mark = _launched_at(app)
    os.remove(_plist_in(app))
    with pytest.raises(AssertionError) as caught:
        _clean_exit(out, app, mark)
    assert "defaults" in str(caught.value).lower()


@pytest.mark.offline
@pytest.mark.parametrize(
    "corruption",
    [
        '{\n    "volume_control" = "0.5";\n',      # truncated: no closing brace
        '{\n    "volume_control" = "0.5\n}\n',      # unterminated string
        '{\n    "volume_control" "0.5";\n}\n',      # missing =
        '',                                        # zero bytes
        '{} trailing garbage here',                # trailing junk
        '{\n    "k" = ;\n}\n',                     # missing value
    ],
)
def test_a_corrupt_defaults_file_fails(tmp_path, corruption):
    """FAILURE 1b: the defaults file exists but the final write did not complete."""
    out = _healthy_output_dir(tmp_path)
    app = _healthy_app_dir(tmp_path)
    mark = _rewritten_now(app, corruption)
    with pytest.raises(AssertionError) as caught:
        _clean_exit(out, app, mark)
    message = str(caught.value).lower()
    assert "defaults" in message or "empty" in message, f"{corruption!r} passed silently"


@pytest.mark.offline
def test_an_absent_log_fails_rather_than_skipping(tmp_path):
    """FAILURE 2: Latest.log is gone. This used to SILENTLY PASS.

    `if os.path.isfile(log):` made the log check evaporate whenever the file it reads was
    absent - and the ERROR scan is the one check with a real chance of catching a bad
    shutdown. _await_startup_complete already read startup.complete out of this exact file in
    this exact run, so its absence is a broken run, not a reason to check nothing.
    """
    out = _healthy_output_dir(tmp_path)
    app = _healthy_app_dir(tmp_path)
    mark = _rewritten_now(app)
    os.remove(os.path.join(out, "Latest.log"))
    with pytest.raises(AssertionError) as caught:
        _clean_exit(out, app, mark)
    assert "Latest.log" in str(caught.value)


@pytest.mark.offline
def test_an_error_in_the_log_still_fails(tmp_path):
    """The check that the absent-log skip was hiding must itself still work."""
    out = _healthy_output_dir(tmp_path)
    app = _healthy_app_dir(tmp_path)
    mark = _rewritten_now(app)
    with open(os.path.join(out, "Latest.log"), "a", encoding="utf-8") as handle:
        handle.write("[shipData.load.error] ERROR: ship data did not load\n")
    with pytest.raises(AssertionError) as caught:
        _clean_exit(out, app, mark)
    assert "errors in Latest.log" in str(caught.value)


@pytest.mark.offline
def test_a_crash_dump_still_fails(tmp_path):
    out = _healthy_output_dir(tmp_path)
    app = _healthy_app_dir(tmp_path)
    mark = _rewritten_now(app)
    with open(os.path.join(out, "oolite.dmp"), "wb") as handle:
        handle.write(b"\x00")
    with pytest.raises(AssertionError) as caught:
        _clean_exit(out, app, mark)
    assert "crash dump" in str(caught.value)


@pytest.mark.offline
def test_the_no_survivor_check_is_not_a_tautology(monkeypatch):
    """FAILURE 3: a live process in the launched tree must fail the check.

    The old `assert game.proc.poll() == 0` re-read a returncode wait() had already stored, so
    it was true by construction. The OS process table is the only witness that can say no.
    Here the table is stubbed to pin down the SCOPING rule exactly; the real table reader is
    exercised against a live process by the two tests below.
    """
    live = [
        (1000, 4, "explorer.exe"),
        (1001, 1000, "oolite.exe"),     # our root
        (1002, 1001, "oolite.exe"),     # a child of ours - also a survivor
        (2001, 1000, "oolite.exe"),     # a CONCURRENT SIBLING run - must NOT be blamed on us
    ]
    monkeypatch.setattr(conftest, "_process_table", lambda: live)
    survivors = conftest.surviving_game_processes(1001)
    assert survivors == [(1001, "oolite.exe"), (1002, "oolite.exe")], survivors
    assert 2001 not in [pid for pid, _ in survivors], (
        "a concurrent sibling GUI run's process was mistaken for our leak"
    )
    with pytest.raises(AssertionError) as caught:
        conftest.assert_no_surviving_game_processes(1001, timeout=0.0)
    assert "orphaned game process" in str(caught.value)

    # And with our own tree gone, the sibling alone must NOT fail the check.
    monkeypatch.setattr(
        conftest, "_process_table", lambda: [(1000, 4, "explorer.exe"), (2001, 1000, "oolite.exe")]
    )
    conftest.assert_no_surviving_game_processes(1001, timeout=0.0)


@pytest.mark.offline
def test_the_process_table_sees_this_very_process():
    """The real table reader works on this platform: it must find our own pid."""
    rows = conftest._process_table()
    mine = [row for row in rows if row[0] == os.getpid()]
    assert mine, "the process table reader did not find this python process"
    _, parent, name = mine[0]
    assert name, "implausible empty image name for our own pid"
    assert parent > 0


@pytest.mark.offline
def test_a_real_live_child_is_seen_as_a_survivor(monkeypatch):
    """End-to-end on the REAL OS table: a live child is found, and once dead it is not.

    Uses this python's own image name rather than oolite.exe (which cannot be launched from an
    offline test), so the tree walk and the liveness reading are exercised for real.
    """
    child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])
    try:
        monkeypatch.setattr(
            conftest, "GAME_PROCESS_NAMES", (os.path.basename(sys.executable).lower(),)
        )
        survivors = conftest.surviving_game_processes(child.pid)
        assert child.pid in [pid for pid, _ in survivors], (
            f"a live child (pid {child.pid}) was not reported as a survivor: {survivors}"
        )
        with pytest.raises(AssertionError):
            conftest.assert_no_surviving_game_processes(child.pid, timeout=0.0)
        child.kill()
        child.wait(timeout=30)
        conftest.assert_no_surviving_game_processes(child.pid, timeout=10.0)
    finally:
        if child.poll() is None:
            child.kill()
            child.wait(timeout=30)


@pytest.mark.offline
def test_g1_asserts_on_the_process_table_not_on_returncode():
    """The tautology must not come back: no `proc.poll()`/`returncode` comparison after wait().

    AST, not grep: the comment explaining why the old assertion was a tautology contains the
    very text a grep would look for.
    """
    path = os.path.join(HERE, "test_g1_exit_via_mouse.py")
    with open(path, "r", encoding="utf-8") as handle:
        source = handle.read()
    tree = ast.parse(source)
    func = next(
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.FunctionDef) and node.name == "test_g1_exit_via_mouse"
    )
    wait_line = min(
        node.lineno
        for node in ast.walk(func)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "wait"
    )
    for node in ast.walk(func):
        if not isinstance(node, ast.Assert) or node.lineno <= wait_line:
            continue
        offenders = [
            sub
            for sub in ast.walk(node.test)
            if (isinstance(sub, ast.Attribute) and sub.attr in ("poll", "returncode"))
            or (
                isinstance(sub, ast.Call)
                and isinstance(sub.func, ast.Attribute)
                and sub.func.attr == "poll"
            )
        ]
        assert not offenders, (
            "line %d re-reads the Popen handle's own returncode, which wait() already reaped; "
            "that comparison cannot fail. Enumerate the surviving processes instead (oo-5rsa)"
            % node.lineno
        )
    calls = {
        node.func.id
        for node in ast.walk(func)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
    }
    assert "assert_no_surviving_game_processes" in calls
    assert "assert_clean_exit" in calls
    assert "oolite.exe" in conftest.GAME_PROCESS_NAMES


# --- oo-5rsa attempt 2: "exists and parses" is not "was written by THIS run" ------------------
#
# The first fix asserted only that a defaults file EXISTS and PARSES. app_dir is the PERSISTENT
# build tree (upstream/oolite/build/meson_test/oolite.app), so a plist left behind by any earlier
# run satisfied that forever: the game could write nothing at all - or not start - and the check
# still passed. That is the same "cannot fail" defect class this bead exists to remove, so the
# check now compares against a mark taken at LAUNCH, and the tests below construct exactly the
# stale-file case a reviewer used to falsify the first attempt.


@pytest.mark.offline
def test_a_stale_defaults_file_fails_even_though_it_parses(tmp_path):
    """THE GATE: a perfectly valid plist that THIS RUN did not write must FAIL.

    Reproduces the reviewer's falsification of attempt 1 verbatim: write a healthy plist, back
    its mtime up 30 days, then run the post-exit check. Attempt 1 returned successfully with
    the run having written nothing; anything but an AssertionError here means the "written"
    half of docs/stories/G1-exit-via-mouse.md:52 has gone unfalsifiable again.
    """
    out = _healthy_output_dir(tmp_path)
    app = _healthy_app_dir(tmp_path)
    plist = _plist_in(app)

    thirty_days_ago = time.time() - 30 * 24 * 60 * 60
    os.utime(plist, (thirty_days_ago, thirty_days_ago))

    # The mark is taken AFTER the backdating, exactly as GameWindow.start() would see the tree
    # at launch. The run then writes nothing at all.
    mark = _launched_at(app)

    # Sanity: the stale file is genuinely valid, so only the launch mark can reject it.
    assert conftest.parse_defaults_file(plist)["window_width"] == "960"

    with pytest.raises(AssertionError) as caught:
        _clean_exit(out, app, mark)
    message = str(caught.value)
    assert "THIS RUN did not write it" in message, message
    assert "oo-5rsa" in message


@pytest.mark.offline
def test_the_same_stale_file_passes_once_this_run_rewrites_it(tmp_path):
    """The other half of the gate: the check rejects staleness, not the file.

    Without this, "always fail" would satisfy the test above just as well as a real check.
    """
    out = _healthy_output_dir(tmp_path)
    app = _healthy_app_dir(tmp_path)
    plist = _plist_in(app)
    thirty_days_ago = time.time() - 30 * 24 * 60 * 60
    os.utime(plist, (thirty_days_ago, thirty_days_ago))

    mark = _launched_at(app)
    with pytest.raises(AssertionError):
        _clean_exit(out, app, mark)

    # ... and now the run synchronizes its defaults, byte-for-byte identical content.
    with open(plist, "r", encoding="utf-8") as handle:
        same_bytes = handle.read()
    with open(plist, "w", encoding="utf-8") as handle:
        handle.write(same_bytes)
    now = time.time_ns()
    os.utime(plist, ns=(now, now))
    _clean_exit(out, app, mark)


@pytest.mark.offline
def test_an_equal_mtime_is_not_accepted_as_a_write(tmp_path):
    """A file whose mtime merely EQUALS the launch mark has not been rewritten.

    Strictly-newer, not newer-or-equal: on a coarse-granularity filesystem "equal" is the
    signature of a file nobody touched, and accepting it would reopen the hole for exactly the
    fast runs where it matters.
    """
    out = _healthy_output_dir(tmp_path)
    app = _healthy_app_dir(tmp_path)
    plist = _plist_in(app)
    mark = _launched_at(app)
    os.utime(plist, ns=(mark[plist][0], mark[plist][0]))
    with pytest.raises(AssertionError) as caught:
        _clean_exit(out, app, mark)
    assert "THIS RUN did not write it" in str(caught.value)


@pytest.mark.offline
def test_the_defaults_check_refuses_to_run_without_a_launch_mark(tmp_path):
    """Dropping the mark must be an ERROR, not a quiet reversion to "a file exists".

    The failure mode being guarded is a future edit that removes the argument "because it is
    optional": the unmarked call has to be impossible to write, not merely discouraged.
    """
    app = _healthy_app_dir(tmp_path)
    with pytest.raises(AssertionError) as caught:
        conftest.assert_defaults_file_reparses(app, None)
    assert "defaults_write_mark" in str(caught.value)

    # And the one-argument assert_clean_exit(output_dir) that a sibling branch may still be
    # carrying must fail loudly with instructions rather than skip the defaults check.
    out = _healthy_output_dir(tmp_path)
    with pytest.raises(AssertionError) as caught:
        conftest.assert_clean_exit(out)
    assert "assert_clean_exit(game)" in str(caught.value)
    with pytest.raises(AssertionError) as caught:
        conftest.assert_clean_exit(out, app)
    assert "launch-time defaults mark" in str(caught.value)


@pytest.mark.offline
def test_a_file_outside_the_launch_mark_is_not_credited_to_this_run(tmp_path):
    """A candidate path that was never marked cannot be evidence of a write.

    Unattributable evidence is precisely what the first attempt rested on, so it is refused
    rather than accepted-with-a-shrug.
    """
    out = _healthy_output_dir(tmp_path)
    app = _healthy_app_dir(tmp_path)
    with pytest.raises(AssertionError) as caught:
        _clean_exit(out, app, {})       # a mark that knows about no paths at all
    assert "not marked at launch" in str(caught.value)


@pytest.mark.offline
def test_the_launch_mark_is_taken_before_the_process_starts():
    """The mark must be recorded in GameWindow.start() BEFORE Popen, or it proves nothing.

    A mark taken after launch could already include the game's own write, which would make the
    comparison vacuous again. AST, so a comment cannot satisfy it.
    """
    with open(os.path.join(HERE, "conftest.py"), "r", encoding="utf-8") as handle:
        source = handle.read()
    tree = ast.parse(source)
    start = next(
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.FunctionDef) and node.name == "start"
    )
    mark_lines = [
        node.lineno
        for node in ast.walk(start)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Name)
        and node.func.id == "defaults_write_mark"
    ]
    assert mark_lines, (
        "GameWindow.start() never calls defaults_write_mark; without a launch-time mark the "
        "G9 defaults check cannot distinguish this run's write from an earlier run's leftover "
        "(oo-5rsa)"
    )
    popen_lines = [
        node.lineno
        for node in ast.walk(start)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "Popen"
    ]
    assert popen_lines, "GameWindow.start() no longer launches anything"
    assert min(mark_lines) < min(popen_lines), (
        "the defaults mark is taken at line %d, AFTER the game is launched at line %d; it "
        "could then already contain the game's own write and the comparison would be vacuous "
        "(oo-5rsa)" % (min(mark_lines), min(popen_lines))
    )


@pytest.mark.offline
def test_g1_passes_the_launch_mark_through_to_the_hygiene_check():
    """G1 must call assert_clean_exit in a form that carries the mark.

    `assert_clean_exit(game.output_dir, game.app_dir)` - the attempt-1 spelling - omits it and
    would land back on the unfalsifiable check, so the call site is pinned by AST.
    """
    path = os.path.join(HERE, "test_g1_exit_via_mouse.py")
    with open(path, "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read())
    call = next(
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Name)
        and node.func.id == "assert_clean_exit"
    )
    if len(call.args) == 1:
        assert isinstance(call.args[0], ast.Name) and call.args[0].id == "game", (
            "a single-argument assert_clean_exit must be passed the game fixture itself, "
            "which carries the launch mark (oo-5rsa)"
        )
    else:
        assert len(call.args) == 3, (
            "assert_clean_exit needs the output dir, the app dir AND the launch-time defaults "
            "mark; a two-argument call cannot tell this run's write from a leftover (oo-5rsa)"
        )


# --- the Win32 process-table calls are covered by test_win32_declarations.py ------------------
#
# surviving_game_processes reaches kernel32 (CreateToolhelp32Snapshot/Process32First/
# Process32Next/CloseHandle). Their declarations are asserted there, beside the rest of the
# oo-x2uy guards, because those tests are the ones permitted to name ctypes.windll.


@pytest.mark.offline
def test_assert_clean_exit_runs_every_check_unconditionally():
    """No `if` may guard a check inside assert_clean_exit, and all three must be present.

    A skip is a silent pass; a check wrapped in "only if the evidence happens to be there" is
    the same thing spelled differently.
    """
    with open(os.path.join(HERE, "conftest.py"), "r", encoding="utf-8") as handle:
        source = handle.read()
    tree = ast.parse(source)
    func = next(
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.FunctionDef) and node.name == "assert_clean_exit"
    )
    assert not [n for n in ast.walk(func) if isinstance(n, (ast.If, ast.IfExp))], (
        "assert_clean_exit must run every check unconditionally; an absent Latest.log must "
        "FAIL, not skip the log check (oo-5rsa)"
    )
    body = ast.get_source_segment(source, func) or ""
    assert "assert_defaults_file_reparses" in body, (
        "the promised defaults re-parse must actually be performed (oo-5rsa)"
    )
    assert "crash dump" in body
    assert "Latest.log" in body


# --- bug oo-3opg: a click must be aimed a frame BEFORE the button goes down -------------------
#
# The defect these pin is not a timeout and not a screen: it is that Oolite reads the clicked
# row out of UNIVERSE->cursor_row, which is written only while RENDERING (Universe.m:5343 is the
# sole assignment in the tree), so a move and a click delivered inside one pollControls activate
# the row the pointer was on BEFORE the move. In-tier that lost race turned G5's Expansion
# Manager leave gesture into a confirm of the row that OPENED the screen - row 26, which on the
# manager is OXZ_GUI_ROW_UPDATE - and the game stayed on GUI_SCREEN_OXZMANAGER.
#
# These are structural (AST) rather than textual: a comment describing the settle would satisfy
# a grep, and the prose above would satisfy it twice over.


def _conftest_tree():
    with open(os.path.join(HERE, "conftest.py"), "r", encoding="utf-8") as handle:
        source = handle.read()
    return source, ast.parse(source)


def _method(tree, class_name, method_name):
    cls = next(
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.ClassDef) and node.name == class_name
    )
    return next(
        node
        for node in ast.walk(cls)
        if isinstance(node, ast.FunctionDef) and node.name == method_name
    )


@pytest.mark.offline
@pytest.mark.parametrize("method_name", ["select_row", "confirm_row"])
def test_every_clicking_helper_aims_before_it_clicks(method_name):
    """The pointer must be placed by aim_at_row, never moved-and-clicked in one breath.

    Asserted as ORDER on the AST, not as the presence of a name: the aim call must appear
    before any pyautogui click/doubleClick/mouseDown in the method body, and the method must
    not compute its own point with point_for_row and click that, which is exactly the shape
    that raced.
    """
    _, tree = _conftest_tree()
    func = _method(tree, "GameWindow", method_name)

    clicks = [
        node.lineno
        for node in ast.walk(func)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr in ("click", "doubleClick", "mouseDown", "mouseUp")
    ]
    assert clicks, f"{method_name} no longer clicks anything"

    aims = [
        node.lineno
        for node in ast.walk(func)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "aim_at_row"
    ]
    assert aims, (
        f"{method_name} does not call aim_at_row, so nothing guarantees the game has rendered a "
        "frame with the pointer on the target row. The click will activate UNIVERSE->cursor_row "
        "from the PREVIOUS frame - the row the pointer was on before - which is bug oo-3opg."
    )
    assert min(aims) < min(clicks), (
        f"{method_name} clicks at line {min(clicks)} before aiming at line {min(aims)}"
    )
    assert not [
        node
        for node in ast.walk(func)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "point_for_row"
    ], (
        f"{method_name} computes its own click point with point_for_row instead of going "
        "through aim_at_row; that is the un-settled path this bug was filed for"
    )


@pytest.mark.offline
def test_aim_at_row_waits_after_moving():
    """aim_at_row must sleep for CURSOR_SETTLE_SECONDS *after* the move, or it settles nothing.

    A move with a duration argument is not a settle: pyautogui returns as soon as the pointer
    arrives, and the frame that reads the new position has not been drawn yet.
    """
    _, tree = _conftest_tree()
    func = _method(tree, "GameWindow", "aim_at_row")

    moves = [
        node.lineno
        for node in ast.walk(func)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "moveTo"
    ]
    assert moves, "aim_at_row no longer moves the pointer"

    sleeps = [
        node
        for node in ast.walk(func)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "sleep"
        and any(
            isinstance(arg, ast.Name) and arg.id == "CURSOR_SETTLE_SECONDS"
            for arg in node.args
        )
    ]
    assert sleeps, (
        "aim_at_row does not sleep for CURSOR_SETTLE_SECONDS; without a wait the game has not "
        "rendered a frame with the pointer here and cursor_row is still the previous row"
    )
    assert max(node.lineno for node in sleeps) > min(moves), (
        "aim_at_row waits BEFORE it moves, which settles the position it is leaving"
    )


@pytest.mark.offline
def test_the_cursor_settle_budget_covers_a_loaded_frame():
    """The settle must be worth more than one nominal frame, and stay a real wait.

    0.3s was the value in place while G5's Expansion Manager round trip failed roughly one
    in-tier run in three and never in isolation, so a loaded frame on this machine is not
    reliably inside 0.3s. The floor is set above that measured-insufficient value rather than
    at a frame time, and a settle of zero must be impossible.
    """
    assert conftest.CURSOR_SETTLE_SECONDS > 0.3, (
        f"CURSOR_SETTLE_SECONDS is {conftest.CURSOR_SETTLE_SECONDS}s. 0.3s was MEASURED "
        "insufficient (bug oo-3opg: ~1 full-tier run in 3 lost the Expansion Manager return), "
        "so a budget at or below it reinstates the race."
    )
    # It is also the tier's cost: two settles per confirmed row, and G5 confirms six.
    assert conftest.CURSOR_SETTLE_SECONDS <= 5.0, (
        "the settle has grown into a timeout; if a frame really takes this long the tier has a "
        "different problem and hiding it behind a longer wait is not the fix"
    )
