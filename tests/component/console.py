"""Debug-console client: framing, handshake, and running JS inside a live Oolite.

Transport only. The golden harness (item 0.4) is expected to share this file, so nothing here
knows anything about the component tier, Gherkin, or pytest - keep assertions and scenario
vocabulary in steps/world_steps.py.

The protocol is the one tests/launch_snapshot.py speaks: a 4-byte big-endian length followed by an
XML property list. See src/Core/Debug/OODebugTCPConsoleProtocol.h for the packet types.

NO DESKTOP LOCK here, deliberately (bug oo-ccy9). Every tool that launches the game on the
interactive desktop must take tools/gui-lock - but this file is the shared TRANSPORT, not a tier,
and it has two callers with opposite needs: the component tier spawns it once per scenario (and
holds the lock for its whole session, in its conftest), while the golden harness spawns it N times
CONCURRENTLY on purpose. An exclusive mutex in here would serialise or outright deadlock the
harness. The lock therefore belongs to whoever decides how many games run at once, which is the
caller. tools/check-desktop-lock.sh records this exemption and enforces it.
"""

import os
import plistlib
import select
import socket
import struct
import subprocess
import sys
import time

REQUEST_CONNECTION = "Request Connection"
APPROVE_CONNECTION = "Approve Connection"
PERFORM_COMMAND = "Perform Command"
CONSOLE_OUTPUT = "Console Output"
PING = "Ping"
PONG = "Pong"

PACKET_TYPE_KEY = "packet type"
MESSAGE_KEY = "message"
CONSOLE_IDENTITY_KEY = "console identity"
OOLITE_VERSION_KEY = "Oolite version"

IS_WINDOWS = sys.platform == "win32" or os.name == "nt"


class ConsoleError(RuntimeError):
    """The game could not be driven: it never connected, never answered, or died."""


class DebugConsole:
    """One Oolite process and the console connection to it.

    The port is a constructor argument rather than a module constant because each scenario runs
    its own game process and they must not collide (item 0.4 requires the same).
    """

    def __init__(self, app_dir, port, seed=None, output_dir=None, host="127.0.0.1",
                 load_save=None):
        self.app_dir = os.path.abspath(app_dir)
        self.port = int(port)
        self.seed = seed
        # Without a save the game sits on the main-menu demo: there is a docked player and a
        # station, but the simulation is not running, so spawned ships never leave AIState GLOBAL
        # and never acquire a target. -load starts a real game (src/SDL/main.m:167). There is no
        # JS route out of the intro screen - that is keyboard work and belongs to the GUI tier.
        self.load_save = load_save
        self.output_dir = os.path.abspath(output_dir) if output_dir else None
        self.host = host
        self._server = None
        self._conn = None
        self._proc = None

    # --- lifecycle ---------------------------------------------------------------------------

    def start(self, ready_timeout=180):
        """Launch the game, accept its connection, and wait until it services the console.

        Waiting is not optional and must not be a fixed sleep. The game connects to the console
        early in startup but cannot answer until its run loop is dispatching packets; on a slow
        machine that is many seconds later. Ping is echoed back as Pong with the same message, so
        readiness is observable rather than guessed at. (tests/launch_snapshot.py had a fixed
        sleep here and took its snapshot before the first frame was ever drawn.)
        """
        self._listen()
        self._spawn()
        self._accept(timeout=60)
        self._handshake()
        self._await_ready(ready_timeout)
        return self

    def _listen(self):
        self._server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._server.bind((self.host, self.port))
        self._server.listen(1)
        self._server.setblocking(False)

    def _env(self):
        env = os.environ.copy()
        # Headless and silent, exactly as tests/launch_snapshot.py runs the game. The offscreen
        # video driver is deliberately not set on Windows: MSYS2's mesa ships no EGL, so SDL's
        # offscreen driver cannot create a context there and the game exits during init.
        if not IS_WINDOWS:
            env["SDL_VIDEODRIVER"] = "offscreen"
        env["LIBGL_ALWAYS_SOFTWARE"] = "1"
        env["GALLIUM_DRIVER"] = "llvmpipe"
        env["SDL_AUDIODRIVER"] = "dummy"
        env["ALSOFT_DRIVERS"] = "null"
        if self.seed is not None:
            # Combat draws on RANROT heavily, so an unpinned seed makes "the pirate dies within
            # 900 ticks" genuinely flaky rather than merely slow.
            env["OO_RANDOM_SEED"] = str(self.seed)
        if self.output_dir:
            env["OO_SNAPSHOTSDIR"] = self.output_dir
            env["OO_LOGSDIR"] = self.output_dir
        return env

    def _spawn(self):
        binary = "oolite.exe" if IS_WINDOWS else "oolite"
        path = os.path.join(self.app_dir, binary)
        if not os.path.isfile(path):
            raise ConsoleError(f"no Oolite binary at {path}; build it first")
        argv = [path, "--no-splash"]
        if self.load_save:
            argv += ["-load", self.load_save]
        self._proc = subprocess.Popen(
            argv,
            cwd=self.app_dir,
            env=self._env(),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    def _accept(self, timeout):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self._proc.poll() is not None:
                raise ConsoleError(
                    f"Oolite exited with {self._proc.returncode} before connecting to the console"
                )
            readable, _, _ = select.select([self._server], [], [], 1)
            if readable:
                self._conn, _ = self._server.accept()
                self._conn.setblocking(True)
                return
        raise ConsoleError(f"Oolite did not connect to the console within {timeout}s")

    def _handshake(self):
        pkt = self._recv()
        if not pkt or pkt.get(PACKET_TYPE_KEY) != REQUEST_CONNECTION:
            raise ConsoleError(f"expected {REQUEST_CONNECTION!r}, got {pkt!r}")
        self.oolite_version = pkt.get(OOLITE_VERSION_KEY)
        self._send({PACKET_TYPE_KEY: APPROVE_CONNECTION,
                    CONSOLE_IDENTITY_KEY: "OoliteComponentTests"})

    def _await_ready(self, timeout):
        token = f"ready-{os.getpid()}-{self.port}"
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self._proc.poll() is not None:
                raise ConsoleError(
                    f"Oolite exited with {self._proc.returncode} while starting up"
                )
            self._send({PACKET_TYPE_KEY: PING, MESSAGE_KEY: token})
            readable, _, _ = select.select([self._conn], [], [], 2)
            if not readable:
                continue
            pkt = self._recv()
            if pkt is None:
                raise ConsoleError("console connection closed during startup")
            if pkt.get(PACKET_TYPE_KEY) == PONG and pkt.get(MESSAGE_KEY) == token:
                return
            # Console output and configuration notes arrive here too; they are not an answer.
        raise ConsoleError(f"Oolite did not answer a Ping within {timeout}s")

    def close(self):
        """Quit the game if it is still up, then tear the sockets down. Safe to call twice."""
        try:
            if self._conn is not None and self._proc is not None and self._proc.poll() is None:
                try:
                    self.perform("quit();")
                except Exception:
                    pass
        finally:
            for sock in (self._conn, self._server):
                try:
                    if sock is not None:
                        sock.close()
                except Exception:
                    pass
            self._conn = None
            self._server = None
            if self._proc is not None:
                try:
                    self._proc.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    self._proc.kill()
                    self._proc.wait(timeout=10)

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
        return False

    # --- commands ----------------------------------------------------------------------------

    def perform(self, js):
        """Fire a JS string into the game without waiting for output."""
        self._send({PACKET_TYPE_KEY: PERFORM_COMMAND, MESSAGE_KEY: js})

    def evaluate(self, js, timeout=15):
        """Run a JS expression and return its result as a string.

        The console replies to a command with Console Output packets, so the value has to be sent
        back deliberately: the expression is wrapped so its result is printed with a unique marker
        this call then waits for. Without the marker a stray log line from the game would be
        mistaken for the answer.
        """
        # The console echoes the command back as Console Output before it sends any result, so a
        # marker that appears literally in the command text matches the echo and the answer is
        # read out of the wrong packet. Splitting the marker in the source fixes that: the echo
        # contains the pieces, only the real output contains them joined.
        head = f"@@{os.getpid()}-{self.port}"
        tail = f"{int(time.time() * 1000) % 1000000}@@"
        marker = head + tail
        wrapped = (
            "(function(){ try { return String(%s); } "
            "catch (e) { return 'ERROR: ' + e; } })()" % js
        )
        # debugConsole.consoleMessage(colorCode, message) - OOJSConsole.m:195. It is a method on
        # the debugConsole global (OODebugMonitor.m:761), not a bare function, and it takes a
        # colour key first; the bare consoleMessage() global belongs to player and shows an
        # in-game message instead of reaching us. This route ends in appendJSConsoleLine, which
        # the TCP client forwards as a Console Output packet.
        self.perform(
            'debugConsole.consoleMessage("command-result", '
            f'"{head}" + "{tail}" + {wrapped} + "{head}" + "{tail}");'
        )

        deadline = time.time() + timeout
        while time.time() < deadline:
            if self._proc is not None and self._proc.poll() is not None:
                raise ConsoleError(f"Oolite exited with {self._proc.returncode} mid-command")
            readable, _, _ = select.select([self._conn], [], [], 1)
            if not readable:
                continue
            pkt = self._recv()
            if pkt is None:
                raise ConsoleError("console connection closed mid-command")
            if pkt.get(PACKET_TYPE_KEY) != CONSOLE_OUTPUT:
                continue
            text = str(pkt.get(MESSAGE_KEY, ""))
            if text.count(marker) >= 2:
                value = text.split(marker)[1]
                if value.startswith("ERROR: "):
                    raise ConsoleError(f"JS error evaluating {js!r}: {value[7:]}")
                return value
        raise ConsoleError(f"no answer to {js!r} within {timeout}s")

    def evaluate_int(self, js, timeout=15):
        value = self.evaluate(js, timeout=timeout).strip()
        try:
            return int(float(value))
        except ValueError as exc:
            raise ConsoleError(f"expected a number from {js!r}, got {value!r}") from exc

    # --- framing -----------------------------------------------------------------------------

    def _send(self, packet):
        data = plistlib.dumps(packet, fmt=plistlib.FMT_XML)
        self._conn.sendall(struct.pack(">I", len(data)) + data)

    def _recv(self):
        header = self._recv_exactly(4)
        if header is None:
            return None
        length = struct.unpack(">I", header)[0]
        body = self._recv_exactly(length)
        if body is None:
            return None
        return plistlib.loads(body)

    def _recv_exactly(self, count):
        buf = b""
        while len(buf) < count:
            chunk = self._conn.recv(count - len(buf))
            if not chunk:
                return None
            buf += chunk
        return buf
