"""
Shared support for driving Oolite in automated tests.

Oolite builds with debug support connect to a debug console on TCP port 8563
at startup. The harness acts as that console: it launches the game, accepts
the connection, sends JavaScript to be evaluated and reads the results back.
It also checks the game's log for script errors and for the result of the
JavaScript runtime's shutdown leak check.

See https://github.com/OoliteProject/oolite-debug-console for the protocol.
"""

import itertools
import json
import os
import plistlib
import queue
import re
import select
import socket
import struct
import subprocess
import sys
import threading
import time

# --- PROTOCOL CONSTANTS ---
# See src/Core/Debug/OODebugTCPConsoleProtocol.h
REQUEST_CONNECTION = "Request Connection"
APPROVE_CONNECTION = "Approve Connection"
PERFORM_COMMAND = "Perform Command"
CONSOLE_OUTPUT = "Console Output"
CLOSE_CONNECTION = "Close Connection"
PING = "Ping"
PONG = "Pong"
PACKET_TYPE_KEY = "packet type"
MESSAGE_KEY = "message"
COLOR_KEY = "color key"
CONSOLE_IDENTITY_KEY = "console identity"
OOLITE_VERSION_KEY = "Oolite version"

IS_WINDOWS = sys.platform == "win32" or (os.name == "nt")
PORT = 8563
HOST = "127.0.0.1"

# Log lines that fail a test. Script errors are logged under
# script.javaScript.exception.* and script.javaScript.error.*.
LOG_FAILURE_PATTERNS = [
    re.compile(r"\[script\.javaScript\.(exception|error)[^\]]*\]"),
    re.compile(r"\[script\.javaScript\.shutDown\.leak\]"),
    re.compile(r"\[script\.javaScript\.timeLimit\]"),
]
LOG_WARNING_PATTERN = re.compile(r"\[script\.javaScript\.warning[^\]]*\]")
CONTINUATION_PATTERN = re.compile(r"\]: {2,}")
LEAK_CHECK_PASSED = "JavaScript runtime shut down with no leaked objects."


def scaled(seconds):
    """
    Scales a timeout by $OOLITE_TEST_TIMEOUT_SCALE, for slow machines (for
    example an emulated CPU, where the game runs many times slower).
    """
    try:
        return seconds * float(os.environ.get("OOLITE_TEST_TIMEOUT_SCALE", "1"))
    except ValueError:
        return seconds


class HarnessError(Exception):
    pass


class JSException(HarnessError):
    """The game reported a JavaScript exception while evaluating a command."""


def send_plist_packet(sock, packet):
    """Sends a packet: a 32-bit big-endian length, then an XML property list."""
    data = plistlib.dumps(packet, fmt=plistlib.FMT_XML)
    sock.sendall(struct.pack(">I", len(data)) + data)


def receive_plist_packet(sock):
    """Reads one packet; returns None when the connection closes."""

    def read_exactly(count):
        data = b""
        while len(data) < count:
            chunk = sock.recv(count - len(data))
            if not chunk:
                return None
            data += chunk
        return data

    header = read_exactly(4)
    if header is None:
        return None
    data = read_exactly(struct.unpack(">I", header)[0])
    if data is None:
        return None
    return plistlib.loads(data)


def game_environment(test_output):
    """Environment for headless software rendering, with logs and snapshots in test_output."""
    env = os.environ.copy()
    # SDL's offscreen driver has no OpenGL on macOS, so a real window is used there
    if not IS_WINDOWS and sys.platform != "darwin":
        env["SDL_VIDEODRIVER"] = "offscreen"
    env["LIBGL_ALWAYS_SOFTWARE"] = "1"
    env["GALLIUM_DRIVER"] = "llvmpipe"
    env["SDL_AUDIODRIVER"] = "dummy"
    env["ALSOFT_DRIVERS"] = "null"
    env["OO_SNAPSHOTSDIR"] = test_output
    env["OO_LOGSDIR"] = test_output
    return env


def resolve_binary(path):
    """Returns (directory, binary name) for an Oolite directory or binary path."""
    target = os.path.abspath(path)
    bundle_binary = os.path.join(target, "Contents", "MacOS", "oolite")
    if os.path.isfile(bundle_binary):  # macOS app bundle
        return os.path.dirname(bundle_binary), "oolite"
    if os.path.isfile(target):
        return os.path.dirname(target), os.path.basename(target)
    return target, "oolite.exe" if IS_WINDOWS else "oolite"


class OoliteConsole:
    """A debug console server that one Oolite process connects to."""

    def __init__(self):
        self._server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._server.bind((HOST, PORT))
        self._server.listen(1)
        self._server.setblocking(False)
        self._conn = None
        self._send_lock = threading.Lock()
        self._packets = queue.Queue()
        self._tags = itertools.count(1)
        self.oolite_version = None
        # Every exception and warning the game sent, for the caller to report.
        self.exceptions = []
        self.warnings = []
        self.log_lines = []
        self.closed = threading.Event()

    def accept(self, timeout, proc=None):
        """Waits for the game to connect and completes the handshake."""
        deadline = time.time() + scaled(timeout)
        while time.time() < deadline:
            if proc is not None and proc.poll() is not None:
                raise HarnessError(f"Oolite exited with status {proc.returncode} before connecting.")
            readable, _, _ = select.select([self._server], [], [], 1)
            if readable:
                self._conn, addr = self._server.accept()
                self._conn.setblocking(True)
                print(f"[+] Oolite connected from {addr}")
                break
        if self._conn is None:
            raise HarnessError("Oolite failed to connect to the debug console.")

        pkt = receive_plist_packet(self._conn)
        if not pkt or pkt.get(PACKET_TYPE_KEY) != REQUEST_CONNECTION:
            raise HarnessError("Handshake failed: expected 'Request Connection'.")
        self.oolite_version = pkt.get(OOLITE_VERSION_KEY)
        print(f"[+] Handshake started. Oolite version: {self.oolite_version}")
        self._send({PACKET_TYPE_KEY: APPROVE_CONNECTION, CONSOLE_IDENTITY_KEY: "OoliteAutomationTester"})
        print("[*] Connection approved.")

        threading.Thread(target=self._read_packets, daemon=True).start()

    def _send(self, packet):
        with self._send_lock:
            send_plist_packet(self._conn, packet)

    def _read_packets(self):
        try:
            while True:
                pkt = receive_plist_packet(self._conn)
                if pkt is None:
                    break
                kind = pkt.get(PACKET_TYPE_KEY)
                if kind == PING:
                    reply = {PACKET_TYPE_KEY: PONG}
                    if MESSAGE_KEY in pkt:
                        reply[MESSAGE_KEY] = pkt[MESSAGE_KEY]
                    self._send(reply)
                elif kind == CLOSE_CONNECTION:
                    break
                elif kind == CONSOLE_OUTPUT:
                    color = pkt.get(COLOR_KEY)
                    message = pkt.get(MESSAGE_KEY, "")
                    if color == "exception":
                        self.exceptions.append(message)
                        print(f"[!] Console exception: {message}")
                    elif color == "warning":
                        self.warnings.append(message)
                        print(f"[?] Console warning: {message}")
                    elif color == "log":
                        self.log_lines.append(message)
                    self._packets.put(pkt)
        except OSError:
            pass
        finally:
            self.closed.set()

    def perform(self, command):
        """Sends JavaScript to be evaluated, without waiting for a result."""
        self._send({PACKET_TYPE_KEY: PERFORM_COMMAND, MESSAGE_KEY: command})

    def evaluate(self, expression, timeout=30):
        """
        Evaluates a JavaScript expression in the console script and returns
        its value, converted through JSON. Raises JSException if the game
        reports an exception first.
        """
        tag = f"__oolite_harness_{next(self._tags)}:"
        command = (
            f"{json.dumps(tag)} + JSON.stringify((function () {{ return ({expression}\n); }}).call(this))"
        )
        exceptions_before = len(self.exceptions)
        self.perform(command)
        deadline = time.time() + scaled(timeout)
        while True:
            remaining = deadline - time.time()
            if remaining <= 0:
                raise HarnessError(f"Timed out evaluating: {expression}")
            if self.closed.is_set() and self._packets.empty():
                raise HarnessError(f"Connection closed while evaluating: {expression}")
            try:
                pkt = self._packets.get(timeout=min(remaining, 0.5))
            except queue.Empty:
                continue
            color = pkt.get(COLOR_KEY)
            message = pkt.get(MESSAGE_KEY, "")
            if color == "command-result" and message.startswith(tag):
                value = message[len(tag):]
                return None if value == "undefined" else json.loads(value)
            if color == "exception" and len(self.exceptions) > exceptions_before:
                raise JSException(message)

    def wait_for(self, expression, timeout, interval=0.5):
        """
        Evaluates expression repeatedly until it is truthy; returns its value.
        The game does not answer while it is busy (loading a game, say), so a
        slow answer only counts against the overall timeout.
        """
        deadline = time.time() + scaled(timeout)
        while True:
            try:
                value = self.evaluate(expression, timeout=max(1, min(30, deadline - time.time())))
            except JSException:
                raise
            except HarnessError:
                if self.closed.is_set():
                    raise
                value = None
            if value:
                return value
            if time.time() > deadline:
                raise HarnessError(f"Timed out waiting for: {expression}")
            time.sleep(interval)

    def close(self):
        if self._conn:
            try:
                self._conn.close()
            except OSError:
                pass
        self._server.close()


class OoliteGame:
    """An Oolite process connected to an OoliteConsole."""

    def __init__(self, path, test_output, load=None, extra_args=(), extra_env=None):
        self.directory, self.binary = resolve_binary(path)
        self.test_output = os.path.abspath(test_output)
        self.log_path = os.path.join(self.test_output, "Latest.log")
        self.args = ["--no-splash"]
        if load:
            self.args += ["-load", os.path.abspath(load)]
        self.args += list(extra_args)
        self.extra_env = dict(extra_env or {})
        self.proc = None
        self.console = None

    def start(self, connect_timeout=60):
        self.console = OoliteConsole()
        print(f"[*] Console server listening on {PORT}")
        cmd = [os.path.join(self.directory, self.binary)] + self.args
        print(f"[*] Executing: {' '.join(cmd)}")
        self.proc = subprocess.Popen(
            cmd,
            cwd=self.directory,
            env={**game_environment(self.test_output), **self.extra_env},
            stdout=sys.stdout,
            stderr=sys.stderr,
        )
        try:
            self.console.accept(connect_timeout, self.proc)
        except HarnessError:
            if sys.platform == "darwin" and self.proc.poll() is None:
                # Show where a hung process is stuck
                subprocess.run(["sample", str(self.proc.pid), "3"], stdout=sys.stdout, stderr=sys.stderr)
            raise
        return self.console

    def wait_for_log(self, text, timeout):
        """Waits until text appears in the game's log; returns False if the game exits or time runs out."""
        deadline = time.time() + scaled(timeout)
        while time.time() < deadline:
            try:
                with open(self.log_path, encoding="utf-8", errors="replace") as f:
                    if text in f.read():
                        return True
            except OSError:
                pass
            if self.proc.poll() is not None:
                return False
            time.sleep(1)
        return False

    def quit(self, timeout=30):
        """
        Asks the game to quit through quitGame(), which takes effect after the
        console command returns so that the shutdown leak check runs, and
        waits for the process to exit.
        """
        print("[*] Requesting quit...")
        self.console.perform("quitGame();")
        try:
            self.proc.wait(timeout=scaled(timeout))
        except subprocess.TimeoutExpired:
            raise HarnessError("Oolite ignored the quit command.")
        print(f"[*] Oolite exited with status {self.proc.returncode}")

    def stop(self):
        if self.console:
            self.console.close()
        if self.proc and self.proc.poll() is None:
            self.proc.kill()
            self.proc.wait()

    def check_log(self, require_leak_check=True):
        """Returns a list of problems found in the game's log."""
        return check_log(self.log_path, require_leak_check)


def check_log(log_path, require_leak_check=True):
    problems = []
    try:
        with open(log_path, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError as e:
        return [f"Could not read the log {log_path}: {e}"]

    leak_check_passed = False
    previous_failed = False
    for number, line in enumerate(lines, 1):
        if any(p.search(line) for p in LOG_FAILURE_PATTERNS):
            # A message's further lines repeat its class, indented after the "]: ".
            if previous_failed and CONTINUATION_PATTERN.search(line):
                problems[-1] += "\n" + line
            else:
                problems.append(f"Latest.log line {number}: {line}")
            previous_failed = True
            continue
        previous_failed = False
        if LOG_WARNING_PATTERN.search(line):
            print(f"[?] Script warning in Latest.log line {number}: {line}")
        if LEAK_CHECK_PASSED in line:
            leak_check_passed = True

    if require_leak_check and not leak_check_passed:
        problems.append("The JavaScript runtime's shutdown leak check did not run or did not pass.")
    return problems


def output_log(log_path):
    if os.path.isfile(log_path):
        print("--- Latest.log ---")
        with open(log_path, encoding="utf-8", errors="replace") as f:
            print(f.read())
        print("------------------------------")
