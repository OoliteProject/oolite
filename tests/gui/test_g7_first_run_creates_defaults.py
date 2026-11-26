"""G7 - first run: no prefs directory exists, and the game creates its defaults.

docs/phases/0-gui-tier.md G7: "Delete the config/prefs directory -> launch -> verify defaults are
created -> exit cleanly". The bug class is "it works because I already have a config file", which
is exactly the bug a brand-new platform hits first.

WHERE THE PREFS ROOT COMES FROM, AND WHY IT IS NOT DELETED
----------------------------------------------------------
The DoD's literal "delete the prefs directory" is NOT available to this tier, and doing it anyway
would be a bug rather than a test. ``src/SDL/main.m:119`` is

    SDL_setenv_unsafe("GNUSTEP_USERS_ROOT", currentWorkingDir, YES)

where ``currentWorkingDir`` is the directory holding the EXECUTABLE and the trailing ``YES`` is
SDL's *overwrite* flag (bug oo-pzc1). So:

* the prefs root CANNOT be relocated with an environment variable - the game overwrites whatever
  the parent exported; and
* the prefs root of the shared build is ``<build>/oolite.app/GNUstep/``, which every other tier,
  every golden run and every concurrent agent on this machine reads and writes. Deleting it to
  manufacture a "first run" would corrupt their runs, and would still be racy.

The only lever the game gives us is WHERE ITS BINARY LIVES. So this file does what
``tests/launch_snapshot.py`` already does for exactly this reason (and with exactly that helper,
``stage_app``): it stages a PRIVATE oolite.app under pytest's ``tmp_path_factory`` - junctions for
the read-only directories, hard links for the files - and then removes the staged copy of
``GNUstep/`` only. That copy is this session's own, seconds old, and outside the build tree; the
real ``<build>/oolite.app/GNUstep/Defaults/oolite.plist`` is never touched, which
``test_the_pristine_root_never_touches_the_shared_build`` pins by AST and
``test_staging_a_pristine_root_leaves_the_source_tree_intact`` pins by measurement.

The launch itself is NOT reimplemented. This module overrides one fixture - ``app_dir`` - so the
tier's own ``game`` fixture launches from the pristine app instead of the shared one, and
everything else (the desktop lock, the readiness gate, DPI awareness, the survivor check, the G9
hygiene assert) is conftest.py's, unchanged.

WHY THE ASSERTION CAN FAIL
--------------------------
``GameWindow.start()`` records ``defaults_write_mark(app_dir)`` BEFORE Popen (oo-5rsa). On a
pristine root every candidate path is absent at launch, so the mark is ``None`` for the prefs
file and its later EXISTENCE - not a timestamp - is the proof of a write. That is the strongest
witness this check has, and it is the whole of G7's claim.

    python3 -m pytest upstream/oolite/tests/gui/test_g7_first_run_creates_defaults.py -x -q

Needs the desktop: a real window, unlocked and logged in (ADR-0017). It takes tools/gui-lock for
the duration, via the ``game`` fixture - this file launches nothing of its own.
"""

import ast
import os
import sys

import pytest

import conftest
from conftest import (
    DEFAULTS_RELATIVE_PATH,
    assert_clean_exit,
    assert_no_surviving_game_processes,
    defaults_write_mark,
    parse_defaults_file,
)

HERE = os.path.dirname(os.path.abspath(__file__))
TESTS_DIR = os.path.abspath(os.path.join(HERE, ".."))
if TESTS_DIR not in sys.path:
    sys.path.insert(0, TESTS_DIR)

# The staging helpers, imported rather than re-written: tests/launch_snapshot.py:316 is the
# audited implementation of "a private oolite.app whose GNUSTEP_USERS_ROOT is this run's alone",
# including unstage_app, which removes junctions AS LINKS so a teardown cannot recurse into - and
# delete - the real build it borrowed them from.
from launch_snapshot import stage_app, unstage_app  # noqa: E402

# PlayerEntity.m:9900-9960 - row 27 of the start screen is ` Exit Game `. G1 owns the grid maths
# and its guards; this file only needs the row.
EXIT_GAME_ROW = 27

# The story's budget, the same one G1 uses: a confirmed ` Exit Game ` that has not exited by now
# has not worked.
EXIT_TIMEOUT_SECONDS = 10


def make_pristine_app(real_app_dir, staged):
    """A private oolite.app with NO prefs directory at all. Returns its path.

    The pristine-ness is asserted, not assumed: a staged root that still had a ``GNUstep/`` in it
    would make the launch mark a timestamp comparison instead of an existence one, and G7 would
    quietly degrade into G9.
    """
    import shutil

    stage_app(real_app_dir, staged)
    prefs_root = os.path.join(staged, "GNUstep")
    # Belt and braces before a recursive delete: this must be OUR fresh copy, under the staged
    # directory, and not a junction into the shared build (stage_app copies GNUstep/ rather than
    # linking it precisely because it is a directory the game WRITES - launch_snapshot.py:303).
    assert os.path.abspath(prefs_root).startswith(os.path.abspath(staged) + os.sep), (
        f"refusing to delete {prefs_root}: it is not inside the staged app {staged}"
    )
    if os.path.isdir(prefs_root):
        assert not _is_link(prefs_root), (
            f"refusing to delete {prefs_root}: it is a link into another tree, and removing it "
            "recursively would delete the shared build's prefs"
        )
        shutil.rmtree(prefs_root)
    assert not os.path.exists(prefs_root), f"{prefs_root} survived; this is not a first run"
    return staged


def _is_link(path):
    """True for a symlink or an NTFS junction."""
    if os.path.islink(path):
        return True
    try:
        return bool(os.lstat(path).st_file_attributes & 0x400)  # FILE_ATTRIBUTE_REPARSE_POINT
    except (OSError, AttributeError):
        return False


@pytest.fixture(scope="session")
def app_dir(pytestconfig, tmp_path_factory):
    """OVERRIDES conftest.app_dir: the tier's ``game`` fixture launches from a PRISTINE app.

    Session-scoped and named identically on purpose - that is the entire mechanism by which this
    file reuses the launch/kill fixture rather than growing a launcher of its own. The real build
    is still resolved by conftest (``--oolite-app`` / ``$OO_APP_DIR`` / the checkout's build), and
    is only ever READ.
    """
    real = pytestconfig.getoption("--oolite-app") or conftest._default_app_dir()
    if not os.path.isdir(real):
        pytest.fail(
            f"no Oolite build at {real}. Build it first (tools/build-windows.sh test) "
            "or pass --oolite-app."
        )
    staged = str(tmp_path_factory.mktemp("g7-first-run") / "oolite.app")
    make_pristine_app(real, staged)
    try:
        yield staged
    finally:
        # unstage_app, NEVER rmtree: the staged app is full of junctions INTO THE REAL BUILD.
        unstage_app(staged)


def test_g7_first_run_creates_defaults(game):
    """No prefs directory at launch; a parseable defaults file afterwards; a clean exit.

    The three claims in the DoD's order. What makes the middle one falsifiable is that the prefs
    file did not exist when the process started - asserted here directly, and independently
    recorded by ``GameWindow.start()`` as ``game.defaults_launch_mark`` (oo-5rsa).
    """
    prefs_file = os.path.join(game.app_dir, DEFAULTS_RELATIVE_PATH)

    # 1. This really is a first run. The game is already up (the fixture waited for
    #    startup.complete), so a prefs file appearing only at EXIT is what we are watching for.
    assert game.defaults_launch_mark is not None, "start() recorded no launch mark"
    assert game.defaults_launch_mark.get(prefs_file, "missing") is None, (
        f"{prefs_file} was already present at launch (mark "
        f"{game.defaults_launch_mark.get(prefs_file)!r}); this is not a first run and the "
        "existence of the file afterwards would prove nothing"
    )
    assert game.proc.poll() is None, "the game exited before the test could ask it to"

    # 2. Exit cleanly, through the menu, the way G1 does: select ` Exit Game `, then confirm.
    #    GameController.m:905-906 synchronizes NSUserDefaults on the way out, so the orderly
    #    shutdown path is the one that has to create the prefs directory it never had.
    game.assert_focused()
    game.select_row(EXIT_GAME_ROW)
    game.confirm_row(EXIT_GAME_ROW)
    try:
        returncode = game.proc.wait(timeout=EXIT_TIMEOUT_SECONDS)
    except Exception:
        pytest.fail(
            f"the game was still running {EXIT_TIMEOUT_SECONDS}s after ` Exit Game ` was "
            f"confirmed on a first run from {game.app_dir}"
        )
    assert returncode == 0, f"the game exited with {returncode}, not 0"

    # 3. THE G7 CLAIM: the prefs directory and its defaults file were created from nothing.
    #    Named explicitly rather than left to assert_clean_exit's candidate search, because the
    #    failure this test exists to report is "the first run created no config at all" and the
    #    operator needs the path.
    assert os.path.isdir(os.path.dirname(prefs_file)), (
        f"the first run created no prefs directory: {os.path.dirname(prefs_file)} does not "
        f"exist. The game's GNUSTEP_USERS_ROOT is {game.app_dir} (main.m:119 derives it from "
        "the directory holding the executable), and it was empty of GNUstep/ at launch."
    )
    assert os.path.isfile(prefs_file), (
        f"the first run created no defaults file: {prefs_file} does not exist. It was absent at "
        "launch and GameController.m:905-906 -synchronize-s NSUserDefaults in "
        "-exitAppWithContext:, so a fresh install would start with no preferences at all."
    )
    contents = parse_defaults_file(prefs_file)
    assert isinstance(contents, dict) and contents, (
        f"{prefs_file} was created but parsed to {contents!r}; a first run must write real "
        "defaults, not an empty or malformed plist"
    )

    # 4. No orphaned process. The OS process table, not proc.poll() - wait() above already
    #    reaped that returncode, so re-reading it is true by construction (oo-5rsa).
    assert_no_surviving_game_processes(game.proc.pid)

    # 5. G9 hygiene, via the fixture so the launch mark travels with it.
    assert_clean_exit(game)


# --- guards: this test must stay a FIRST-RUN test, and must stay safe ---------------------------
#
# Offline, so they gate in a clean checkout with no build and no desktop.


@pytest.mark.offline
def test_a_pristine_root_marks_the_prefs_file_as_absent_at_launch(tmp_path):
    """The mark on a prefs-less app dir must be ``None``, which is what makes G7 falsifiable.

    If ``defaults_write_mark`` ever returned a tuple here (or omitted the path), step 1 of the
    test above would pass against a root that already had a plist in it and the "created" half of
    the DoD would go unfalsifiable - the oo-5rsa defect class, one level up.
    """
    app = str(tmp_path / "oolite.app")
    os.makedirs(app, exist_ok=True)
    prefs_file = os.path.join(app, DEFAULTS_RELATIVE_PATH)
    mark = defaults_write_mark(app)
    assert prefs_file in mark, "the prefs file must be marked even when it does not exist"
    assert mark[prefs_file] is None, (
        "a path absent at launch must be marked None; its later existence is then the proof of "
        "a write, which is stronger than any timestamp (oo-5rsa)"
    )

    # ... and once a file is there, the mark is NOT None, so the guard above can fail.
    os.makedirs(os.path.dirname(prefs_file), exist_ok=True)
    with open(prefs_file, "w", encoding="utf-8") as handle:
        handle.write("{ window_width = 960; }\n")
    assert defaults_write_mark(app)[prefs_file] is not None


@pytest.mark.offline
def test_staging_a_pristine_root_leaves_the_source_tree_intact(tmp_path):
    """MEASURED, not promised: staging + unstaging must not disturb the source app at all.

    Five agents share this machine and the shared build's
    ``GNUstep/Defaults/oolite.plist`` is live state for every one of them. This builds a
    miniature oolite.app, stages a pristine copy of it, deletes the copy's prefs, tears the copy
    down, and then asserts the ORIGINAL still has its prefs file with its original bytes.
    """
    source = tmp_path / "oolite.app"
    (source / "GNUstep" / "Defaults").mkdir(parents=True)
    plist = source / "GNUstep" / "Defaults" / "oolite.plist"
    plist.write_text('{ window_width = 960; }\n', encoding="utf-8")
    (source / "Resources").mkdir()
    (source / "Resources" / "big.dat").write_text("read-only payload", encoding="utf-8")
    (source / "oolite.exe").write_text("binary", encoding="utf-8")

    staged = str(tmp_path / "staged" / "oolite.app")
    make_pristine_app(str(source), staged)
    try:
        assert not os.path.exists(os.path.join(staged, "GNUstep")), "the staged root is not clean"
        assert os.path.isfile(os.path.join(staged, "oolite.exe")), (
            "the staged app must still hold the binary; it is the binary's directory that "
            "becomes GNUSTEP_USERS_ROOT (main.m:119)"
        )
    finally:
        unstage_app(staged)

    assert plist.is_file(), (
        "staging a pristine prefs root DELETED the source tree's defaults file - exactly the "
        "shared-state corruption this whole approach exists to avoid"
    )
    assert plist.read_text(encoding="utf-8") == '{ window_width = 960; }\n'
    assert (source / "Resources" / "big.dat").is_file(), (
        "unstage_app followed a junction into the source tree and deleted its contents"
    )


@pytest.mark.offline
def test_the_pristine_root_never_touches_the_shared_build():
    """No destructive call in this module may be aimed at anything but the staged copy.

    AST, so a comment cannot satisfy it. The rule: ``shutil.rmtree`` appears exactly once, inside
    ``make_pristine_app``, guarded by the containment and not-a-link assertions above it; and the
    fixture tears down with ``unstage_app``, never with ``rmtree`` (which would follow the
    junctions into the real build).
    """
    with open(os.path.join(HERE, os.path.basename(__file__)), "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read())

    def calls_in(name):
        func = next(
            node
            for node in ast.walk(tree)
            if isinstance(node, ast.FunctionDef) and node.name == name
        )
        return {
            node.func.attr if isinstance(node.func, ast.Attribute) else getattr(node.func, "id", "")
            for node in ast.walk(func)
            if isinstance(node, ast.Call)
        }

    for node in ast.walk(tree):
        if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)):
            continue
        assert node.func.attr not in ("remove", "unlink", "rmdir"), (
            f"line {node.lineno} removes a filesystem entry directly; the staged app is full of "
            "junctions into the shared build and must be torn down with unstage_app"
        )

    assert "rmtree" in calls_in("make_pristine_app"), (
        "make_pristine_app no longer removes the staged prefs root, so the root it hands to the "
        "game is not pristine and G7 is not testing a first run"
    )
    fixture = calls_in("app_dir")
    assert "unstage_app" in fixture, (
        "the pristine-app fixture must tear down with unstage_app; shutil.rmtree over a tree of "
        "junctions is how a harness deletes the build it was supposed to read"
    )
    assert "rmtree" not in fixture, "the fixture must not rmtree the staged app (junctions)"
    assert "stage_app" in fixture or "make_pristine_app" in fixture


@pytest.mark.offline
def test_g7_asserts_on_the_prefs_file_by_name_and_only_after_a_real_launch():
    """The test must name the file it expects, and must not fall back to "some plist somewhere".

    A G7 that only called ``assert_clean_exit(game)`` would pass on a machine where the shared
    build's plist happened to be fresh: assert_clean_exit searches every candidate root. The
    explicit ``os.path.isfile(prefs_file)`` on the STAGED root is what makes this a first-run
    test rather than a second G9, so it is pinned here.
    """
    with open(os.path.join(HERE, os.path.basename(__file__)), "r", encoding="utf-8") as handle:
        source = handle.read()
    tree = ast.parse(source)
    func = next(
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.FunctionDef) and node.name == "test_g7_first_run_creates_defaults"
    )
    body = ast.get_source_segment(source, func) or ""
    assert "prefs_file" in body and "isfile" in body, (
        "G7 must assert on the prefs file's own path; without it the test cannot tell a first "
        "run from any other run"
    )
    assert "DEFAULTS_RELATIVE_PATH" in body, (
        "the prefs path must be built from conftest.DEFAULTS_RELATIVE_PATH so it cannot drift "
        "from the path the rest of the tier checks"
    )
    # NOT a substring search. `body` is the function's raw source INCLUDING its docstring, and
    # the docstring names game.defaults_launch_mark: a text grep here stays green after both
    # real assertions are deleted, which is the oo-5rsa defect class one level up. Ask the AST
    # instead - the attribute must be REACHED BY AN ``assert`` STATEMENT, so prose cannot
    # satisfy it.
    mark_asserts = [
        node
        for node in ast.walk(func)
        if isinstance(node, ast.Assert)
        and any(
            isinstance(child, ast.Attribute) and child.attr == "defaults_launch_mark"
            for child in ast.walk(node)
        )
    ]
    assert len(mark_asserts) >= 2, (
        "G7 must assert the prefs file was ABSENT at launch, in two steps: that start() recorded "
        "a launch mark at all, and that the mark's entry for prefs_file is None. Found "
        f"{len(mark_asserts)} assert statement(s) referencing .defaults_launch_mark. Without both, "
        "'it exists afterwards' is satisfied by a leftover and the test cannot fail (oo-5rsa). "
        "Mentioning defaults_launch_mark in the docstring does NOT count."
    )
    calls = {
        node.func.id
        for node in ast.walk(func)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
    }
    assert "assert_no_surviving_game_processes" in calls
    assert "assert_clean_exit" in calls
    assert "parse_defaults_file" in calls, (
        "a created-but-corrupt defaults file is a failed first run, not a passing one"
    )
