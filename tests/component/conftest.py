"""Fixtures for the component tier: one native game process per scenario, on its own port.

Every scenario gets a hard timeout with a forced kill, so a hung game fails the run instead of
wedging it.
"""

import os
import shutil
import threading

import pytest

from console import DebugConsole

# A scenario that has not finished by now is not going to. Generous because a single launch costs
# 5-10 s on a software renderer before any simulation starts.
SCENARIO_TIMEOUT_SECONDS = int(os.environ.get("OO_COMPONENT_TIMEOUT", "300"))


def pytest_addoption(parser):
    parser.addoption(
        "--oolite-app",
        action="store",
        default=os.environ.get("OO_APP_DIR", ""),
        help="Path to oolite.app (default: $OO_APP_DIR, else the test build in this checkout)",
    )


def _default_app_dir():
    here = os.path.dirname(os.path.abspath(__file__))
    oolite = os.path.abspath(os.path.join(here, "..", ".."))
    return os.path.join(oolite, "build", "meson_test", "oolite.app")


def _ensure_software_gl(app_dir):
    """Put Mesa's llvmpipe driver beside the binary, as tests/run_test_fn.sh does.

    Without it the game picks up whatever OpenGL the desktop offers and dies during init with
    "An uninitialized OpenGL extension function has been called, terminating" - the headless VM
    has no usable hardware GL.

    Two DLLs, not one. Mesa's opengl32.dll loads libgallium_wgl.dll at runtime, and when that is
    missing Windows raises a MODAL error dialog, which blocks an unattended run for ever instead
    of failing it. run_test_fn.sh copies only opengl32.dll and gets away with it purely because
    it runs inside an MSYS2 shell with $MINGW_PREFIX/bin on PATH.
    """
    prefix = os.environ.get("MINGW_PREFIX")
    if not prefix:
        return
    for dll in ("opengl32.dll", "libgallium_wgl.dll"):
        source = os.path.join(prefix, "bin", dll)
        target = os.path.join(app_dir, dll)
        if os.path.isfile(source) and not os.path.isfile(target):
            shutil.copy2(source, target)


@pytest.fixture(scope="session")
def app_dir(pytestconfig):
    path = pytestconfig.getoption("--oolite-app") or _default_app_dir()
    if not os.path.isdir(path):
        pytest.fail(
            f"no Oolite build at {path}. Build it first (tools/build-windows.sh test) "
            "or pass --oolite-app."
        )
    _ensure_software_gl(path)
    return path


@pytest.fixture
def console_port():
    """The port the game will connect out to.

    It is the GAME that dials the console, not the other way round, and it takes the port from
    console-port in debugConfig.plist - defaulting to 8563 (OODebugSupport.m:80,
    OODebugTCPConsoleProtocol.h:46). So a port the test picks freely is a port nothing connects
    to. console.py still takes the port as an argument, so a caller that runs several games at
    once can write that plist per process; until something does, scenarios share the default
    and must run sequentially, which pytest does anyway.
    """
    return int(os.environ.get("OO_CONSOLE_PORT", "8563"))


class World:
    """Scenario state shared between steps: the console, the seed, and what was spawned."""

    def __init__(self, app_dir, port, output_dir):
        self.app_dir = app_dir
        self.port = port
        self.output_dir = output_dir
        self.console = None
        self.seed = None
        self.spawned = {}

    def start(self, seed, load_save=None):
        self.seed = seed
        self.console = DebugConsole(
            self.app_dir, self.port, seed=seed, output_dir=self.output_dir,
            load_save=load_save
        )
        self.console.start()
        return self.console

    def close(self):
        if self.console is not None:
            self.console.close()
            self.console = None


@pytest.fixture
def world(app_dir, console_port, tmp_path, request):
    """One game per scenario, killed unconditionally at the end.

    On Windows ``SDL_VIDEODRIVER=offscreen`` is deliberately left unset (console.py::_env - MSYS2's
    Mesa ships no EGL and the offscreen driver cannot make a context), so every scenario opens a
    REAL window on the real desktop, which can take the foreground away from a running GUI test.
    Scenarios run sequentially on ONE console port (``console_port``), and nothing locks the
    desktop: do not run this tier alongside the GUI tier.

    The timeout is enforced by a watchdog thread rather than a signal: SIGALRM does not exist on
    Windows, and this tier runs natively on Windows.
    """
    w = World(app_dir, console_port, str(tmp_path))

    timed_out = threading.Event()

    def on_timeout():
        timed_out.set()
        w.close()

    watchdog = threading.Timer(SCENARIO_TIMEOUT_SECONDS, on_timeout)
    watchdog.daemon = True
    watchdog.start()
    try:
        yield w
    finally:
        watchdog.cancel()
        w.close()
        if timed_out.is_set():
            pytest.fail(
                f"scenario exceeded {SCENARIO_TIMEOUT_SECONDS}s and the game was killed"
            )
