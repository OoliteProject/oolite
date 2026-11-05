"""Launch Oolite headless, drive it over the debug console, and capture one screenshot.

Everything that used to be a module constant is now an argument or an environment variable, so N
copies of ``run_test`` can run at once: each picks its own console port and its own artifact
directory, and nothing is shared between them except the binary. --load hands a saved commander
to the game's -load argument so a run can start docked instead of on the main-menu demo.

Three things here are not obvious and are the reason the file looks the way it does:

* The PORT is not something this script can simply choose. It is the GAME that dials out to the
  console, and it reads the port from `console-port` in debugConfig.plist (OODebugSupport.m:80,
  default kOOTCPConsolePort = 8563 in OODebugTCPConsoleProtocol.h:46). So a port is made real by
  writing a plist the game will merge, not by listening somewhere else. See _console_config_dir.

* Readiness is measured on the GAME's clock, never on this script's. See wait_until_rendering.

* The PREFS ROOT is per-run, by STAGING A PRIVATE oolite.app - not by a lock and not by an
  environment variable (bug oo-pzc1). ``src/SDL/main.m:119`` does

      SDL_setenv_unsafe("GNUSTEP_USERS_ROOT", currentWorkingDir, YES)

  where ``currentWorkingDir`` is the directory holding the EXECUTABLE (QueryFullProcessImageName,
  main.m:91-95) and the trailing ``YES`` is SDL's *overwrite* flag. So the game OVERWRITES whatever
  the parent exported: handing each child its own ``GNUSTEP_USERS_ROOT`` in the environment - the
  first fix anyone reaches for - is inert on Windows, and N instances sharing one oolite.app still
  race on one ``GNUstep/Defaults/oolite.plist`` (written by ``-exitAppWithContext:``,
  GameController.m:905-906, as a whole-file read-modify-write, so the last writer wins and the
  other runs' preferences are silently lost).

  The only thing the game reads is WHERE ITS OWN BINARY LIVES, so isolation has to be a private
  directory holding the binary. That is exactly what ``tests/golden/golden_run.py`` does (bug
  oo-16s) and why it is the desktop-lock exemption: junctions for read-only directories, hard
  links for files, real copies for the three directories the game WRITES. A lock was the wrong
  answer here for the same reason it is wrong there - ``run_test`` is the N-concurrent half, and
  an exclusive mutex inside it would serialise or deadlock the fan-out. The staging code is
  duplicated rather than imported because this subtree is also pushed to the fork on its own,
  where ``tests/golden/`` does not exist (same reason ``_desktop_lock_helper`` locates tools/ at
  runtime).

  ``--check-isolation`` and ``--prefs-race`` prove both halves offline, with no built game.

* PATHS FROM THE COMMAND LINE CROSS A BOUNDARY (bug oo-vyey). The repository's shell is MSYS2
  bash, so the documented way to run this - ``--load "$SAVE"`` with ``$SAVE`` a natural
  ``/c/Users/...`` path - hands an MSYS path to a NATIVE Windows python. ``os.path.abspath`` then
  resolves it against the current DRIVE (``/c/Users/x`` becomes ``C:/c/Users/x``, a real directory
  on this machine, which is how the mistake survives), and the same string would go on to the
  native game binary's ``-load``. Every path that arrives as an argument is therefore converted at
  the boundary with ``cygpath -m``, exactly as ``tests/golden/run.sh:124`` and ``tools/gui-lock``
  do. ``--check-msys-paths`` proves both directions offline.
"""

import argparse
import os
import plistlib
import select
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time

# --- PROTOCOL CONSTANTS ---
# See https://github.com/OoliteProject/oolite-debug-console/blob/master/ooliteConsoleServer/_protocol.py
# Using the exact string definitions required by the Oolite Debug Protocol
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

# --- CONFIGURATION ---
IS_WINDOWS = sys.platform == "win32" or (os.name == "nt")


# --- THE MSYS PATH BOUNDARY (bug oo-vyey) ------------------------------------------------------
#
# This script is a NATIVE Windows python invoked from MSYS2 bash, and the two disagree about what
# a path is. `/c/Users/jon/save.oolite-save` is what the shell means; os.path.abspath resolves it
# against the CURRENT DRIVE and yields `C:/c/Users/jon/save.oolite-save`, which on this machine is
# a real directory (C:\c exists), so the mistake does not announce itself - it silently reads the
# wrong tree, or hands the wrong string to the game's -load. cygpath is the only thing that knows
# the mapping (it reads /etc/fstab and the MSYS root), so it is what does the conversion, exactly
# as tests/golden/run.sh:124 and tools/gui-lock:35 already do.
#
# Applied ONCE, at the argument boundary, never deeper: a path already in native form is left
# alone (cygpath -m is idempotent on `C:/...`), and off Windows there is no boundary to cross.
_CYGPATH = shutil.which("cygpath") if IS_WINDOWS else None


def looks_like_msys_path(text):
    """True for a POSIX-rooted path string on Windows - the form a native binary misreads.

    Drive-letter paths (`C:/x`, `C:\\x`) and UNC paths are already native. A bare `/c/...` or
    `/tmp/...` is not, and is what the repository's own shell produces.
    """
    if not text or not IS_WINDOWS:
        return False
    if text[0] not in "/\\":
        return False
    return not text.startswith("\\\\") and not text.startswith("//")


def native_path(text):
    """Convert an MSYS path to the native `C:/...` form the game and the OS understand.

    Returns ``text`` unchanged when there is nothing to convert or no cygpath to convert with -
    a missing cygpath means this is not an MSYS shell, and the caller's path is already native.
    """
    if not looks_like_msys_path(text) or not _CYGPATH:
        return text
    try:
        out = subprocess.run(
            [_CYGPATH, "-m", "--", text],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return text
    return out or text

DEFAULT_PORT = 8563  # kOOTCPConsolePort
DEFAULT_HOST = "127.0.0.1"
DEFAULT_OUTPUT = "./test_output"
MIN_FILE_SIZE_KB = 100  # Threshold for a valid render
# The macOS CI runner renders with Apple's software renderer and can take
# 20 seconds or more after startup before the game services the console
READY_TIMEOUT = 90
READY_TOKEN = "oolite-test-ready"

# How much of the game's own clock must pass, after it starts answering, before a frame is worth
# capturing. This is a duration in GAME-CLOCK SECONDS, not a count of frames: it is compared
# against a clock.absoluteSeconds delta in wait_until_rendering. Game time only advances while the
# run loop steps, so waiting on it implies frames were drawn and cannot be exhausted by a slow
# startup - but the quantity itself is seconds, and the flag that sets it is --settle-game-seconds.
DEFAULT_SETTLE_GAME_SECONDS = 2.0


def send_plist_packet(sock, packet):
    """
    Implements the framing protocol from
    https://github.com/OoliteProject/oolite-debug-console/blob/master/ooliteConsoleServer/PropertyListPacketProtocol.py:
    1. Encodes the dictionary as an XML Property List.
    2. Calculates a 32-bit big-endian integer for the length.
    3. Prepends this 4-byte header to the data.
    """
    try:
        # Matches writePlistToString logic for Python 3
        data = plistlib.dumps(packet, fmt=plistlib.FMT_XML)
        length = len(data)

        # Header is 4 bytes, network-endian (Big-Endian)
        header = struct.pack(">I", length)

        sock.sendall(header + data)
        return True
    except Exception as e:
        print(f"[!] Failed to encode/send packet: {e}")
        return False


def receive_plist_packet(sock):
    """
    Implements the receiving state machine from:
    https://github.com/OoliteProject/oolite-debug-console/blob/master/ooliteConsoleServer/OoliteDebugConsoleProtocol.py
    1. Reads the 4-byte header to determine expected length.
    2. Reads the specific number of bytes for the XML payload.
    """
    try:
        header = sock.recv(4)
        if len(header) < 4:
            return None

        length = struct.unpack(">I", header)[0]
        data = b""
        while len(data) < length:
            chunk = sock.recv(length - len(data))
            if not chunk:
                break
            data += chunk

        return plistlib.loads(data)
    except Exception as e:
        print(f"[!] Error receiving packet: {e}")
        return None


def wait_until_ready(sock, timeout):
    """
    Sends a harmless command and waits for its result. The game only reads
    console commands from its main loop, so a reply means it is running.
    """
    send_plist_packet(
        sock, {PACKET_TYPE_KEY: PERFORM_COMMAND, MESSAGE_KEY: f"'{READY_TOKEN}'"}
    )
    deadline = time.time() + timeout
    while time.time() < deadline:
        readable, _, _ = select.select([sock], [], [], 1)
        if not readable:
            continue
        pkt = receive_plist_packet(sock)
        if pkt is None:
            return False
        if (
            pkt.get(PACKET_TYPE_KEY) == "Console Output"
            and pkt.get("color key") == "command-result"
            and pkt.get(MESSAGE_KEY) == READY_TOKEN
        ):
            return True
    return False


def sample_process(proc):
    """Shows where a hung process is stuck (macOS only)."""
    if sys.platform == "darwin" and proc.poll() is None:
        subprocess.run(["sample", str(proc.pid), "3"], stdout=sys.stdout, stderr=sys.stderr)


def run_test(bin_name, test_output):
    # Setup TCP Server
    server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_sock.bind((host, port))
    server_sock.listen(1)
    server_sock.setblocking(False)

    print(f"[*] Console server listening on {host}:{port}")

    config_dir = _console_config_dir(host, port)

    # THE PREFS ROOT (bug oo-pzc1). Stage a private oolite.app and run the binary from THERE, so
    # main.m:119 derives this run's GNUSTEP_USERS_ROOT from a directory nobody else is using. Not
    # an env var - the game overwrites it (SDL_setenv_unsafe ..., YES) - and not a lock, which
    # would serialise the N-concurrent fan-out this function exists to support.
    staged_root = tempfile.mkdtemp(prefix=f"oolite-run-{port}-{os.getpid()}-")
    if _bundle_contents(app_dir):
        staged_app = os.path.join(staged_root, "oolite.app", "Contents", BUNDLE_BINARY_DIR)
    else:
        staged_app = os.path.join(staged_root, "app")
    stage_app(app_dir, staged_app)
    print(f"[*] Private prefs root: {staged_app}")

    # Environment configuration for pure headless software offscreen rendering
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

    # Prepended rather than replaced: a caller may already be pointing the game at add-ons.
    existing = env.get("OO_ADDITIONALADDONSDIRS")
    env["OO_ADDITIONALADDONSDIRS"] = f"{config_dir},{existing}" if existing else config_dir

    cmd = [os.path.join(staged_app, bin_name), "--no-splash"]
    if load_save:
        # src/SDL/main.m:167 - the argument after -load is taken as the commander to load, and it
        # must end in .oolite-save for the game to accept it.
        #
        # Converted HERE too, not only in __main__ (bug oo-vyey): this is the boundary where the
        # string stops being python's and becomes a NATIVE Windows process's argv, and run_test is
        # a library function that callers - tests/golden, the component tier - invoke directly
        # with whatever their own MSYS shell handed them. native_path is a no-op on an
        # already-native path, so the CLI's conversion is not undone by a second one.
        cmd += ["-load", native_path(load_save)]

    print(f"[*] Executing: {' '.join(cmd)}")
    proc = subprocess.Popen(
        cmd,
        cwd=staged_app,
        env=env,
        stdout=sys.stdout,
        stderr=sys.stderr,
    )

    conn = None
    try:
        # 1. Wait for Oolite to initiate connection
        timeout = time.time() + 60
        while time.time() < timeout:
            if proc.poll() is not None:
                print(f"[!] Failure: Oolite exited with {proc.returncode} before connecting.")
                return False
            readable, _, _ = select.select([server_sock], [], [], 1)
            if readable:
                conn, addr = server_sock.accept()
                conn.setblocking(True)
                print(f"[+] Oolite connected from {addr}")
                break

        if not conn:
            print("[!] Failure: Oolite failed to connect.")
            sample_process(proc)
            return False

        # 2. THE HANDSHAKE
        pkt = receive_plist_packet(conn)

        if pkt and pkt.get(PACKET_TYPE_KEY) == REQUEST_CONNECTION:
            print(
                f"[+] Handshake started. Oolite version: {pkt.get(OOLITE_VERSION_KEY)}"
            )

            # Respond with 'Approve Connection' and identity
            approval = {
                PACKET_TYPE_KEY: APPROVE_CONNECTION,
                CONSOLE_IDENTITY_KEY: "OoliteAutomationTester",
            }
            send_plist_packet(conn, approval)
            print("[*] Connection Approved.")
        else:
            print("[!] Handshake failed: Expected 'Request Connection'.")
            return False

        # Wait until the game's main loop is servicing the console
        ready_start = time.time()
        if not wait_until_ready(conn, READY_TIMEOUT):
            print(f"[!] Failure: Oolite did not answer the console within {READY_TIMEOUT}s.")
            sample_process(proc)
            return False
        print(f"[*] Oolite ready after {time.time() - ready_start:.1f}s.", flush=True)

        # Allow time for the title screen to render
        time.sleep(5)

        # 3. THE COMMAND. Snapshot and quit are separate, and the file is waited for: sending
        # both at once means the game may quit on the same frame it snapshots.
        print("[*] Requesting snapshot...")
        before = set(f for f in os.listdir(test_output) if f.endswith(".png"))
        perform(conn, "takeSnapShot();")

        snap_path = None
        deadline = time.time() + 30
        while time.time() < deadline:
            new = [f for f in os.listdir(test_output) if f.endswith(".png") and f not in before]
            if new:
                snap_path = os.path.join(test_output, sorted(new)[0])
                # The PNG is written by the game; wait for its size to stop changing.
                size = -1
                while size != os.path.getsize(snap_path):
                    size = os.path.getsize(snap_path)
                    time.sleep(0.3)
                break
            time.sleep(0.3)

        print("[*] Requesting quit...")
        perform(conn, "quit();")

        # 4. WAIT FOR PROCESS EXIT
        print("[*] Waiting for process to exit...")
        try:
            proc.wait(timeout=30)
        except subprocess.TimeoutExpired:
            print("[!] Error: Oolite ignored the shutdown command.")
            sample_process(proc)
            return False

        # 5. VERIFY OUTPUT
        if snap_path is None:
            print("[!] Error: Oolite exited but no snapshot was found.")
            return False

        file_size_kb = os.path.getsize(snap_path) // 1024
        print(f"[*] Captured {snap_path} ({file_size_kb} KB)")

        if file_size_kb < MIN_FILE_SIZE_KB:
            print(
                f"[!] Failure: Snapshot is too small ({file_size_kb} KB). Likely a black frame."
            )
            return False

        print("[+] Success: Snapshot passed quality check.")
        return True

    finally:
        if conn:
            conn.close()
        server_sock.close()
        if proc.poll() is None:
            proc.kill()
        shutil.rmtree(config_dir, ignore_errors=True)
        if keep_staged:
            print(f"[*] Keeping staged app at {staged_app}")
        else:
            # unstage_app, never rmtree: the staged app is full of junctions INTO THE REAL BUILD.
            unstage_app(staged_app)
            for leftover in (os.path.join(staged_root, "oolite.app"), staged_root):
                try:
                    os.rmdir(leftover)
                except OSError:
                    pass


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description="Oolite Automation Tester")
    parser.add_argument(
        "--path",
        default=os.environ.get("OO_APP_DIR", "./"),
        help="Path to the Oolite directory or binary (default: $OO_APP_DIR, else ./)",
    )
    parser.add_argument(
        "--output",
        "--test_output",
        dest="output",
        default=os.environ.get("OO_TEST_OUTPUT", DEFAULT_OUTPUT),
        help="Artifact directory for the snapshot and Latest.log; one per instance "
        f"(default: $OO_TEST_OUTPUT, else {DEFAULT_OUTPUT})",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("OO_CONSOLE_PORT", DEFAULT_PORT)),
        help=f"Debug-console port this instance uses (default: $OO_CONSOLE_PORT, else {DEFAULT_PORT})",
    )
    parser.add_argument(
        "--host",
        default=os.environ.get("OO_CONSOLE_HOST", DEFAULT_HOST),
        help=f"Address to listen on (default: $OO_CONSOLE_HOST, else {DEFAULT_HOST})",
    )
    parser.add_argument(
        "--load",
        metavar="FILE.oolite-save",
        default=os.environ.get("OO_LOAD_SAVE") or None,
        help="Saved commander to hand to the game's -load argument, so the run starts docked",
    )
    parser.add_argument(
        "--settle-game-seconds",
        type=float,
        default=None,
        metavar="SECONDS",
        help="Seconds of the GAME's clock that must pass before snapshotting "
        f"(default: $OO_SNAPSHOT_SETTLE, else {DEFAULT_SETTLE_GAME_SECONDS})",
    )
    # Deprecated alias. The old name lied about its unit - it never took a frame count - but it is
    # a published flag, so it keeps working and warns rather than breaking callers silently.
    parser.add_argument(
        "--settle-frames",
        type=float,
        default=None,
        dest="settle_frames_deprecated",
        metavar="SECONDS",
        help="DEPRECATED alias for --settle-game-seconds (never took frames; takes game-clock "
        "seconds). Warns and will be removed.",
    )
    parser.add_argument(
        "--ready-timeout",
        type=float,
        default=float(os.environ.get("OO_READY_TIMEOUT", "120")),
        help="Seconds to wait for the game to start answering the console (default: 120)",
    )
    parser.add_argument(
        "--keep-staged",
        action="store_true",
        help="keep this run's private staged oolite.app instead of removing it",
    )
    args = parser.parse_args(argv)

    # Resolve the settle duration: explicit new flag wins, then the deprecated alias (with a
    # warning), then $OO_SNAPSHOT_SETTLE, then the built-in default. Both flags carry the SAME
    # unit - game-clock seconds - so the alias needs no conversion, only a warning.
    if args.settle_frames_deprecated is not None:
        print(
            "[!] --settle-frames is deprecated and misnamed: it takes game-clock SECONDS, not "
            "frames. Use --settle-game-seconds.",
            file=sys.stderr,
        )
        if args.settle_game_seconds is None:
            args.settle_game_seconds = args.settle_frames_deprecated
    if args.settle_game_seconds is None:
        args.settle_game_seconds = float(
            os.environ.get("OO_SNAPSHOT_SETTLE", DEFAULT_SETTLE_GAME_SECONDS)
        )
    return args


if __name__ == "__main__":
    args = parse_args()

    # Determine binary name and original path
    bin_name = "oolite.exe" if IS_WINDOWS else "oolite"
    original_cwd = os.getcwd()
    # native_path FIRST, then abspath: abspath on an MSYS path silently invents a real-looking
    # C:/c/... that exists on this machine (bug oo-vyey). The same reasoning applies to --path and
    # --output, which also arrive from the MSYS shell and also end up in the native game's world
    # (the app dir becomes the staging source and the cwd; the output dir becomes OO_SNAPSHOTSDIR
    # and OO_LOGSDIR, read by the game itself).
    target_dir = os.path.abspath(native_path(args.path))

    # If the user pointed to a file, get the containing directory
    if os.path.isfile(target_dir):
        bin_name = os.path.basename(target_dir)
        target_dir = os.path.dirname(target_dir)

    # Resolved before the chdir below, so relative paths mean what the caller meant.
    test_output = os.path.abspath(native_path(args.output))
    os.makedirs(test_output, exist_ok=True)
    load_save = os.path.abspath(native_path(args.load)) if args.load else None
    if load_save and not os.path.isfile(load_save):
        print(f"[!] Failure: no save file at {load_save}")
        if looks_like_msys_path(args.load) and not _CYGPATH:
            print("[!] --load looks like an MSYS path and no cygpath was found to convert it; "
                  "pass a native C:/... path instead.")
        sys.exit(1)

    success = False
    try:
        print(f"[*] Moving to {target_dir}")
        os.chdir(target_dir)

        # Run the test from within the Oolite directory
        success = run_test(
            bin_name,
            test_output,
            args.port,
            args.host,
            load_save,
            args.settle_game_seconds,
            args.ready_timeout,
            app_dir=target_dir,
            keep_staged=args.keep_staged,
        )

    except Exception as e:
        print(f"[!] Critical Error: {e}")
    finally:
        # ALWAYS return to the original path
        os.chdir(original_cwd)
        print(f"[*] Returned to {original_cwd}")

    sys.exit(0 if success else 1)
