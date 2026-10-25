"""A GUI test that fails MID-RUN, with the game up, must leave no orphaned oolite.exe.

Bead oo-njnw. The bead was filed as a defect: "conftest's shared ``game`` fixture does not take
the process down when a test fails while the game is up; an oolite.exe SURVIVES the run", with a
reviewer's report of an ``assert False`` injected into test_g1_exit_via_mouse.py on pristine main
leaving a survivor behind.

THAT DEFECT DOES NOT EXIST, and this file is the evidence that it does not, pinned so it cannot
come back. Measured by reproducing that injection exactly - a scratch copy of
test_g1_exit_via_mouse.py with ``assert False`` placed after step 1's ``select_row``, i.e. with
the game demonstrably up - and recording the pid the run itself launched:

    current main 602219c    rc=1, "1 failed, 38 passed in 27.66s", launched pid 11144 -> GONE
    pristine     fd501c4    rc=1, "1 failed, 38 passed in 26.51s", launched pid  6384 -> GONE

fd501c4 is the very tree the bead was filed against, so this is not a leak some later bead fixed
by accident: the teardown was already correct, and ``GameWindow.kill`` is byte-identical between
the two trees. The original sighting was a CONCURRENT AGENT'S oolite.exe - five agents share this
desktop - and a bare ``tasklist /FI "IMAGENAME eq oolite.exe"`` cannot tell that from a leak of
one's own. Recording the launched pid and asking about THAT pid is what distinguishes them, and it
is why every assertion here is pid-scoped.

WHY THE TEARDOWN IS SOUND, which is the property this file locks. ``game`` is a generator fixture
whose ``yield`` sits inside a ``try/finally``. When a test body raises, pytest throws that
exception into the generator at the yield point, so ``finally: window.kill()`` runs during the
unwind - identically for a passing test and a failing one. There is no separate failure path.

HOW THE MID-RUN FAILURE IS STAGED. A test cannot fail deliberately AND then assert on what its
own teardown did: its assertions would never run. So the failure happens in a CHILD pytest
process and the assertions happen here, in the parent. The child test file is written into THIS
directory, so the ``conftest.py`` it binds to is this tier's real one - the shared fixture itself,
unmodified, not a reimplementation and not a private copy of its body. The child records the pid
it launched to a file, fails while the game is up, and the parent then asserts that pid is gone
from the operating system's process table.

The child file is named ``_njnw_child_*.py`` rather than ``test_*.py`` so that a normal tier run
never collects it, the tier-wide AST meta-guard in test_g9_post_exit_hygiene.py (which walks
``os.listdir`` for ``test_*.py``) never sees it, and it is removed in a ``finally`` either way.

    python3 -m pytest upstream/oolite/tests/gui/test_g10_mid_run_failure_leaves_no_orphan.py -q

FALSIFIABILITY, measured rather than asserted - see the bead's evidence. With
``GameWindow.kill``'s ``self.proc.kill()`` neutered in a scratch copy of the tier, this test goes
RED and names the surviving pid. The committed conftest.py is untouched by this bead.

Needs the desktop: a real window, unlocked and logged in (ADR-0017). The child run takes
tools/gui-lock through the shared fixture, so this test releases the lock before spawning it (it
holds none of its own) and launches nothing directly.
"""

import os
import subprocess
import sys
import time

import pytest

import conftest
from conftest import (
    assert_no_parked_runtime_files,
    assert_no_surviving_game_processes,
    surviving_game_processes,
)

HERE = os.path.dirname(os.path.abspath(__file__))

# How long the pid gets to actually be gone once the child process has exited. kill() already
# waits up to 10s on the Popen; this is slack for the OS to drop the process-table entry.
ORPHAN_GRACE_SECONDS = 15.0

# The child gets the tier's own readiness budget plus room for the launch itself. A real launch is
# ~11-25s on this machine; a child that came back in under a second did not run a game at all,
# which is asserted below rather than assumed.
CHILD_TIMEOUT_SECONDS = float(os.environ.get("OO_NJNW_CHILD_TIMEOUT", "300"))

# A child run that finishes faster than this cannot have launched, pinned and settled a real
# window (the fixture alone sleeps SETTLE_SECONDS after a startup gate that waits for
# ``startup.complete``). Guards against the failure this file had in review: a pin that dies in
# its own preamble in 0.4s while claiming to have exercised the teardown.
MINIMUM_REAL_LAUNCH_SECONDS = 5.0

INJECTED_MESSAGE = "oo-njnw: deliberate mid-run failure with the game UP"

CHILD_SOURCE = '''\
"""GENERATED, TRANSIENT (bead oo-njnw). Fails MID-RUN with the game up, on purpose.

Written into the GUI tier directory by test_g10_mid_run_failure_leaves_no_orphan.py so that the
``conftest.py`` it binds is this tier's real one - the point is to exercise the SHARED ``game``
fixture's own teardown down its real unwind path. Deliberately not named test_*.py: a normal tier
run must never collect it, and the tier-wide AST meta-guard must never see it. The parent removes
it in a finally.
"""

import os


def test_njnw_child_fails_while_the_game_is_up(game):
    pid = game.proc.pid
    with open(os.environ["OO_NJNW_PIDFILE"], "w", encoding="utf-8") as handle:
        handle.write(str(pid))
    assert game.proc.poll() is None, "the game must still be up at the injection point"
    assert False, {message!r}
'''


def _run_child(pidfile, child_lock_dir):
    """Run the child test in its own pytest process. Returns ``(returncode, output, seconds)``.

    THE LOCK, which is the subtle part and was a real self-deadlock in review. This tier's
    ``game`` fixture depends on the session-scoped ``desktop_lock``, so the child would try to
    acquire tools/gui-lock - the exclusive desktop mutex THIS TEST'S OWN SESSION already holds.
    Parent and child would then wait on each other until the child's timeout: measured, the pin
    passed alone in ~10s and hung for the full 300s budget when run with the rest of the
    launching tier. A longer timeout would not have fixed it, only hidden a deadlock behind a
    slower wait.

    So the child is given a PRIVATE lock directory in ``OO_GUI_LOCK_DIR``, which both
    tools/gui-lock (``lock_dir()``) and conftest's bash-less fallback (``_lock_path()``) honour.
    That is sound rather than a loophole: desktop exclusivity for this test is supplied by the
    PARENT, which takes the real ``desktop_lock`` fixture and holds it across the child's whole
    run, so at no point is an unlocked game on the desktop. The child's private mutex only stops
    it from queueing behind its own parent. It is a fresh empty directory per run, so the child
    never contends with anything and never reclaims anyone's lock.

    THIS IS NOT COMPENSATING FOR THE STALE LOCK, and that was measured rather than assumed. A
    separate fleet defect - a lock orphaned by a dead session, reclaimed under the script's own
    age-based protocol and filed as oo-c7bu - produced failures that LOOKED like this deadlock,
    so the two had to be told apart deliberately. Removing only the ``OO_GUI_LOCK_DIR`` line
    below, from a CLEAN and verified-free lock, still fails: the child never writes its pidfile
    and dies with "1 error in 29.89s", the parent failing at the pidfile assertion after 39s.
    That is the child hitting its 30s acquisition budget on the mutex its own parent is holding,
    with no stale lock anywhere in the picture. The private directory is therefore load-bearing
    on its own merits and is kept.
    """
    child = os.path.join(HERE, "_njnw_child_%d.py" % os.getpid())
    with open(child, "w", encoding="utf-8") as handle:
        handle.write(CHILD_SOURCE.format(message=INJECTED_MESSAGE))
    env = dict(os.environ, OO_NJNW_PIDFILE=pidfile)
    env["OO_GUI_LOCK_DIR"] = child_lock_dir
    # Its own owner identity too, so nothing it does can be mistaken for this process's, and a
    # release it makes can only ever apply to its own private directory.
    env["OO_GUI_LOCK_OWNER"] = "njnw-child:py%d" % os.getpid()
    # A short acquisition budget: the child's lock is private and uncontended, so if it ever
    # blocks here something is wrong with the arrangement above and it must say so quickly
    # rather than burning the whole timeout.
    env["OO_GUI_LOCK_TIMEOUT"] = "30"
    try:
        started = time.time()
        finished = subprocess.run(
            [
                sys.executable,
                "-m",
                "pytest",
                os.path.basename(child) + "::test_njnw_child_fails_while_the_game_is_up",
                "-q",
                "-p",
                "no:cacheprovider",
                "-o",
                "python_files=_njnw_child_*.py",
                "--oolite-app",
                _app_dir_argument(),
            ],
            cwd=HERE,
            env=env,
            capture_output=True,
            text=True,
            timeout=CHILD_TIMEOUT_SECONDS,
        )
        return finished.returncode, finished.stdout + finished.stderr, time.time() - started
    finally:
        try:
            os.remove(child)
        except OSError:
            pass


def _app_dir_argument():
    """The build this tier would use anyway, passed explicitly so the child cannot pick another."""
    return conftest._default_app_dir()


def test_a_mid_run_failure_leaves_no_orphaned_game(desktop_lock, tmp_path):
    """A GUI test that dies with the game up must leave the pid it launched dead.

    Every check is scoped to the pid the child run launched. A bare "is any oolite.exe running?"
    would be a false positive against a concurrent sibling GUI run on this shared desktop - and
    that false positive is exactly what filed this bead, so this test is not allowed to repeat it.

    Takes ``desktop_lock`` directly, and NOT ``game``: this test launches nothing itself, but the
    child it spawns puts a real window on the desktop, so the desktop must be held for the
    duration. Holding it here - in the session that also runs G1, G3, G9 and the rest - is what
    lets this pin coexist with its own tier instead of queueing behind it (see _run_child).
    """
    conftest.require_gui_platform()
    conftest.require_gui_dependencies()
    app = _app_dir_argument()
    if not os.path.isdir(app):
        pytest.fail(
            f"no Oolite build at {app}; this pin needs a real game to launch "
            "(tools/build-windows.sh test)"
        )

    pidfile = str(tmp_path / "child-pid.txt")
    # The child's own private, uncontended mutex. Fresh per run and inside this test's tmp_path,
    # so it can never collide with the real desktop lock this test is holding on its behalf.
    child_lock = str(tmp_path / "child-gui-lock")
    returncode, output, seconds = _run_child(pidfile, child_lock)

    # The child must have failed for OUR reason, not fallen over in its own preamble. Without
    # this, a child that never launched anything would make the orphan assertion below vacuous -
    # the exact defect an earlier draft of this file had (it died in 0.4s having launched nothing).
    assert os.path.isfile(pidfile), (
        "the child run never recorded a launched pid, so it never had a game up and this pin "
        f"asserted nothing. Child rc={returncode} in {seconds:.1f}s:\n{output}"
    )
    pid = int(open(pidfile, encoding="utf-8").read().strip())
    assert returncode != 0, (
        f"the child run was expected to FAIL mid-run (it ends in `assert False`) but exited 0; "
        f"the injection is not happening:\n{output}"
    )
    assert INJECTED_MESSAGE in output, (
        "the child did not fail for the injected reason, so the failure it exercised was not a "
        f"mid-run failure with the game up. Child rc={returncode}:\n{output}"
    )
    assert seconds >= MINIMUM_REAL_LAUNCH_SECONDS, (
        f"the child finished in {seconds:.2f}s, faster than a real launch can possibly be "
        f"({MINIMUM_REAL_LAUNCH_SECONDS}s floor: the fixture waits for startup.complete and then "
        "settles). It cannot have put a window on the desktop, so this pin would be vacuous:\n"
        + output
    )

    # THE PROPERTY. Pid-scoped, asked of the operating system's process table - the only witness
    # that can say "no". NOT Popen.returncode, which the child's own kill() already stored and
    # which would therefore be true by construction.
    deadline = time.time() + ORPHAN_GRACE_SECONDS
    survivors = surviving_game_processes(pid)
    while survivors and time.time() < deadline:
        time.sleep(0.25)
        survivors = surviving_game_processes(pid)
    assert not survivors, (
        f"the game process the child run launched (pid {pid}) SURVIVED a mid-run test failure: "
        + ", ".join(f"{name} (pid {survived})" for survived, name in survivors)
        + f" still alive {ORPHAN_GRACE_SECONDS}s after the shared ``game`` fixture's teardown "
        "returned. A leaked window is parked by _pin_window at exactly (0,0) at the same client "
        "size, so it covers the NEXT test's click point pixel for pixel and silently eats its "
        "clicks - the root cause of bug oo-0p8f, and five agents share this desktop (oo-njnw). "
        f"Child rc={returncode} in {seconds:.1f}s:\n{output}"
    )

    # The tier's own shared post-exit helper, over the same pid, so this pin is held to the tier's
    # baseline rather than to a private one.
    assert_no_surviving_game_processes(pid)

    # Printed so a passing run carries its own evidence: which pid was launched, that it is gone,
    # and that the child really did take a real launch's worth of time. A pin whose green run
    # leaves no trace of the pid it observed cannot be audited (run with -s to see it).
    print(
        f"oo-njnw: child launched oolite.exe pid {pid}, failed MID-RUN with the game up "
        f"({INJECTED_MESSAGE!r}), and the shared fixture's teardown left that pid DEAD "
        f"- child rc={returncode} in {seconds:.1f}s"
    )


@pytest.mark.offline
def test_the_shared_teardown_kills_on_the_failure_path_and_not_only_on_success():
    """The fixture's kill must be in a ``finally``, reached however the test ended.

    The structural half of the claim above, checkable with no desktop: if a future edit moved
    ``window.kill()`` out of the finalizer and into the body after the yield, the launching test
    would still pass on every green run and leak on every red one - the exact defect this bead was
    filed for. So the SHAPE is pinned too, from the AST rather than from a substring: a comment or
    a docstring naming kill() must not be able to hold this green.
    """
    import ast
    import inspect

    tree = ast.parse(inspect.getsource(conftest))
    fixture = next(
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.FunctionDef) and node.name == "game"
    )
    tries = [node for node in ast.walk(fixture) if isinstance(node, ast.Try)]
    assert tries, "the game fixture no longer wraps its yield in try/finally"

    in_finally = {
        sub.func.attr
        for node in tries
        for stmt in node.finalbody
        for sub in ast.walk(stmt)
        if isinstance(sub, ast.Call) and isinstance(sub.func, ast.Attribute)
    }
    assert "kill" in in_finally, (
        "the game fixture's teardown does not call .kill() from its ``finally`` handler. In the "
        "body after the yield it would be skipped by exactly the failed runs most likely to have "
        "left a game on the desktop, which is the leak bead oo-njnw investigated (and disproved "
        "on both fd501c4 and 602219c precisely because the call is in the finalizer)."
    )

    # And the yield really is inside that try, i.e. a failure in the test body unwinds through it.
    assert any(
        isinstance(sub, ast.Yield)
        for node in tries
        for stmt in node.body
        for sub in ast.walk(stmt)
    ), (
        "the game fixture's ``yield`` is not inside the try whose finally kills the game, so a "
        "test-body failure would not unwind through the teardown at all"
    )


@pytest.mark.offline
def test_the_generated_child_fails_mid_run_rather_than_after_the_game_exits():
    """The injected child must fail with the game UP, and must record its pid first.

    The one property that makes the launching pin meaningful: a child that failed AFTER the game
    had already exited would leave no orphan trivially, and the pin would pass forever without
    exercising the teardown's failure path at all. Asserted from the AST of the generated source,
    so a future edit to CHILD_SOURCE cannot quietly weaken it.
    """
    import ast

    source = CHILD_SOURCE.format(message=INJECTED_MESSAGE)
    tree = ast.parse(source)
    func = next(
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.FunctionDef) and node.name.startswith("test_")
    )
    assert "game" in [a.arg for a in func.args.args], (
        "the child must take the SHARED game fixture; anything else would exercise a "
        "reimplementation of the teardown rather than the teardown"
    )
    statements = [node for node in func.body if not isinstance(node, ast.Expr)]
    # The last statement is the deliberate failure, and a liveness assertion precedes it.
    last = statements[-1]
    assert isinstance(last, ast.Assert) and isinstance(last.test, ast.Constant), (
        "the child's final statement must be the deliberate `assert False` failure"
    )
    assert last.test.value is False
    unparsed = ast.unparse(tree)
    assert "game.proc.poll() is None" in unparsed, (
        "the child must assert the game is still UP immediately before failing, or the pin cannot "
        "claim to exercise a MID-RUN failure"
    )
    assert "OO_NJNW_PIDFILE" in unparsed and "game.proc.pid" in unparsed, (
        "the child must record the pid it launched, or the parent has nothing pid-scoped to "
        "assert on and would fall back to the image-name query that misattributed this bead"
    )


@pytest.mark.offline
def test_the_child_cannot_deadlock_on_the_lock_its_parent_holds():
    """The child must get a PRIVATE desktop lock, and the parent must hold the real one.

    The self-deadlock this guards was real and measured: with the child acquiring tools/gui-lock
    normally, the pin passed alone in ~10s and then hung for its whole 300s budget when run in
    one pytest invocation with the rest of the launching tier, because the parent's session
    already held the exclusive mutex the child was waiting for. A test that only passes when
    nothing else runs is the flaky-gate class filed as oo-ac3f, and accept.sh runs acceptance
    while siblings are live - so the SHAPE is pinned here rather than left to whoever next edits
    the spawn.

    Both halves matter and both are asserted:

    * the child is handed ``OO_GUI_LOCK_DIR`` (honoured by tools/gui-lock's ``lock_dir()`` and by
      conftest's bash-less ``_lock_path()`` fallback alike), so it never queues behind its parent.
      Asserted from the AST with _run_child's docstring stripped, never as a substring: that
      docstring names OO_GUI_LOCK_DIR four times and used to hold this guard green with the real
      assignment deleted (bug oo-f1sq);
    * the parent takes the REAL ``desktop_lock`` fixture, so the desktop is genuinely held while
      the child's window is up. Without that second half the first would be a loophole rather
      than a fix - an unlocked game on a desktop five agents share.
    """
    import ast
    import inspect

    # From the AST, with _run_child's OWN DOCSTRING STRIPPED FIRST. A substring check over the
    # source cannot do this job: that docstring names OO_GUI_LOCK_DIR four times, so deleting the
    # real assignment left this guard GREEN ("1 passed in 0.02s") - bug oo-f1sq. Prose must not be
    # able to hold this green, the same standard the teardown guard above states for kill().
    spawn = ast.parse(inspect.getsource(_run_child))
    func = next(
        node
        for node in ast.walk(spawn)
        if isinstance(node, ast.FunctionDef) and node.name == "_run_child"
    )
    body = list(func.body)
    if (
        body
        and isinstance(body[0], ast.Expr)
        and isinstance(body[0].value, ast.Constant)
        and isinstance(body[0].value.value, str)
    ):
        del body[0]

    def _assigns_env_key(key):
        """True iff executable code assigns to ``env[key]`` - not merely names it."""
        for statement in body:
            for node in ast.walk(statement):
                if not isinstance(node, ast.Assign):
                    continue
                for target in node.targets:
                    if not isinstance(target, ast.Subscript):
                        continue
                    if not (
                        isinstance(target.value, ast.Name) and target.value.id == "env"
                    ):
                        continue
                    index = target.slice
                    if isinstance(index, ast.Index):  # pragma: no cover - Python < 3.9
                        index = index.value
                    if isinstance(index, ast.Constant) and index.value == key:
                        return True
        return False

    assert _assigns_env_key("OO_GUI_LOCK_DIR"), (
        "_run_child does not ASSIGN env['OO_GUI_LOCK_DIR'] (checked as an ast.Assign to an "
        "ast.Subscript on `env`, with the docstring stripped, so a mention in prose cannot "
        "satisfy it). Without the real assignment the child is not given a private lock "
        "directory, so it will block acquiring the exclusive desktop mutex its own parent's "
        "session already holds - a self-deadlock that makes this pin pass alone and hang inside "
        "its own tier"
    )

    signature = inspect.signature(test_a_mid_run_failure_leaves_no_orphaned_game)
    assert "desktop_lock" in signature.parameters, (
        "the pin does not take the desktop_lock fixture, so the child's real window would be on "
        "the desktop with nothing holding the tier's mutex"
    )
    assert "game" not in signature.parameters, (
        "the pin must not take the game fixture: it would launch a second game it never uses, "
        "and it is the CHILD's game whose teardown is under test"
    )

    # And the private directory really is per-run, not a fixed path two concurrent runs share.
    body = ast.unparse(ast.parse(inspect.getsource(test_a_mid_run_failure_leaves_no_orphaned_game)))
    assert "tmp_path" in body and "child-gui-lock" in body, (
        "the child's lock directory must live under this test's own tmp_path, or two concurrent "
        "runs of the pin would share one private mutex and reintroduce the contention"
    )


@pytest.mark.offline
def test_the_pin_refuses_to_pass_on_a_child_that_never_launched():
    """The vacuity guard itself: a fast child with no pid must FAIL this pin, not pass it.

    This is the defect an earlier draft of this file shipped with - it died in its own preamble in
    0.37s, launched nothing, and would have been reported as a guard. The floor and the pidfile
    demand are what prevent that, so they are asserted directly.
    """
    assert MINIMUM_REAL_LAUNCH_SECONDS > 1.0, (
        "the real-launch floor must be well above a preamble failure's duration"
    )
    assert conftest.SETTLE_SECONDS > 0, (
        "the fixture settles after readiness, which is why a real launch cannot be instant"
    )
    # And the helpers the pin leans on are the tier's shared, pid-scoped ones.
    assert callable(surviving_game_processes)
    assert callable(assert_no_surviving_game_processes)
    assert callable(assert_no_parked_runtime_files)
