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

* The DESKTOP LOCK is taken by the command-line entry point, NOT by ``run_test`` (bug oo-ccy9).
  Running this file as a script is the build's single smoke launch, and one real window on the
  interactive desktop must exclude the GUI tier's. But ``run_test`` is the reusable half that the
  N-concurrent claim above is about, and an exclusive mutex inside it would serialise - or
  deadlock - exactly the fan-out it exists to support. So the lock wraps the single-launch CLI
  and leaves the library function alone.

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


def perform(conn, js):
    """Fire a JS string into the game without waiting for anything back."""
    return send_plist_packet(conn, {PACKET_TYPE_KEY: PERFORM_COMMAND, MESSAGE_KEY: js})


def evaluate(conn, js, timeout=20):
    """Run a JS expression in the game and return its result as a string, or None on failure.

    The console answers a command with Console Output packets, so a value has to be sent back
    deliberately: the expression is wrapped and printed between a unique marker this call waits
    for. The marker is split in the source because the console echoes the command text back as
    Console Output before any result, and a marker appearing literally in the command would match
    that echo - the answer would then be read out of the wrong packet.
    """
    head = f"@@{os.getpid()}"
    tail = f"{int(time.time() * 1000) % 1000000}@@"
    marker = head + tail
    wrapped = (
        "(function(){ try { return String(%s); } catch (e) { return 'ERROR: ' + e; } })()" % js
    )
    # debugConsole.consoleMessage(colorCode, message) - OOJSConsole.m. It is a method on the
    # debugConsole global, not a bare function, and the colour key comes first. This route ends in
    # appendJSConsoleLine, which the TCP client forwards to us as a Console Output packet.
    if not perform(
        conn,
        'debugConsole.consoleMessage("command-result", '
        f'"{head}" + "{tail}" + {wrapped} + "{head}" + "{tail}");',
    ):
        return None

    deadline = time.time() + timeout
    while time.time() < deadline:
        readable, _, _ = select.select([conn], [], [], 1)
        if not readable:
            continue
        pkt = receive_plist_packet(conn)
        if pkt is None:
            print("[!] Console connection closed mid-command.")
            return None
        if pkt.get(PACKET_TYPE_KEY) != CONSOLE_OUTPUT:
            continue
        text = str(pkt.get(MESSAGE_KEY, ""))
        if text.count(marker) >= 2:
            return text.split(marker)[1]
    print(f"[!] No answer to {js!r} within {timeout}s.")
    return None


def wait_until_answering(conn, ready_timeout=120):
    """Block until Oolite is actually servicing the debug console.

    Sleeping a fixed number of seconds after sending the approval measures the wrong clock. The
    approval is answered by the game's run loop, and until loading finishes there is no run loop
    to answer it: on a slow machine the entire sleep elapses during startup, the approval and the
    snapshot command are then consumed in the same poll, and the snapshot is taken on the first
    frame the game ever services - before anything has been drawn. That produces a black frame and
    looks like a rendering fault rather than the race it is.

    Ping is echoed back as Pong with the same message (OODebugTCPConsoleProtocol.h), so readiness
    is directly observable instead of guessed at.
    """
    token = f"ready-{os.getpid()}-{time.time()}"
    started = time.time()
    deadline = started + ready_timeout

    while time.time() < deadline:
        if not send_plist_packet(conn, {PACKET_TYPE_KEY: PING, MESSAGE_KEY: token}):
            print("[!] Failure: could not send Ping.")
            return False
        # select rather than a socket timeout: receive_plist_packet reports every exception, and
        # a timeout per poll is normal here, not an error worth printing.
        readable, _, _ = select.select([conn], [], [], 2)
        if not readable:
            continue
        pkt = receive_plist_packet(conn)
        if pkt is None:
            print("[!] Failure: console connection closed while waiting for Oolite.")
            return False
        if pkt.get(PACKET_TYPE_KEY) == PONG and pkt.get(MESSAGE_KEY) == token:
            print(f"[+] Oolite is servicing the console after {time.time() - started:.1f}s")
            return True
        # Anything else (console output, configuration notes) is not an answer; keep waiting.

    print(f"[!] Failure: Oolite did not answer a Ping within {ready_timeout}s.")
    return False


def wait_until_rendering(conn, settle_game_seconds, timeout=120):
    """Wait until the game has actually drawn frames, counted on the game's own clock.

    Answering a Ping proves the run loop is alive; it does not prove anything has been drawn.
    clock.absoluteSeconds is UNIVERSE's time (OOJSClock.m), which only advances while the run loop
    steps, so requiring it to move forward is equivalent to requiring frames - and unlike a sleep
    on this script's clock it cannot be spent while the game is still loading.
    """
    first = evaluate(conn, "clock.absoluteSeconds")
    if first is None:
        return False
    try:
        start = float(first)
    except ValueError:
        print(f"[!] Failure: clock.absoluteSeconds returned {first!r}.")
        return False

    deadline = time.time() + timeout
    while time.time() < deadline:
        now = evaluate(conn, "clock.absoluteSeconds")
        if now is None:
            return False
        try:
            elapsed = float(now) - start
        except ValueError:
            print(f"[!] Failure: clock.absoluteSeconds returned {now!r}.")
            return False
        if elapsed >= settle_game_seconds:
            screen = evaluate(conn, "guiScreen") or "?"
            print(f"[+] {elapsed:.1f}s of game time drawn; guiScreen={screen}")
            return True
        time.sleep(0.5)

    print(f"[!] Failure: game time did not advance {settle_game_seconds}s within {timeout}s.")
    return False


def wait_until_docked(conn, timeout=60):
    """Confirm a --load run reached the docked screen rather than the main-menu demo."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        docked = evaluate(conn, "player.ship.docked")
        if docked is None:
            return False
        if docked.strip().lower() == "true":
            screen = evaluate(conn, "guiScreen") or "?"
            print(f"[+] Loaded save is docked; guiScreen={screen}")
            return True
        time.sleep(1)
    print(f"[!] Failure: the loaded save was not docked within {timeout}s.")
    return False


def _console_config_dir(host, port):
    """Create a throwaway resource root that tells the game which console port to dial.

    The game reads console-host/console-port out of debugConfig.plist, merged across every search
    path (OODebugSupport.m:67-80), so this is the only way to move it off 8563. A directory named
    in OO_ADDITIONALADDONSDIRS becomes a search root (OOOXZManager.m:286 -> ResourceManager
    userRootPaths), and a plain directory root needs no manifest.plist. The stock Debug OXP leaves
    both keys commented out, so whatever this writes wins the merge regardless of path order.

    Returned path must be removed by the caller.
    """
    root = tempfile.mkdtemp(prefix=f"oolite-console-{port}-")
    config = os.path.join(root, "Config")
    os.makedirs(config, exist_ok=True)
    with open(os.path.join(config, "debugConfig.plist"), "wb") as handle:
        plistlib.dump({"console-host": host, "console-port": port}, handle,
                      fmt=plistlib.FMT_XML)
    return root


# --- per-run prefs isolation (bug oo-pzc1) -----------------------------------------------------
#
# Real copies rather than links: these are the directories the GAME WRITES, and sharing them is
# the collision. Same list as tests/golden/golden_run.py:56 - GNUstep/ holds Defaults/oolite.plist
# (the raced file), Logs/ holds Latest.log, oolite-saves/ holds commanders.
PRIVATE_SUBDIRS = ("GNUstep", "Logs", "oolite-saves")


def _link_dir(source, target):
    """Junction (Windows) or symlink: a read-only directory shared with the real build."""
    if IS_WINDOWS:
        import _winapi

        _winapi.CreateJunction(source, target)
    else:
        os.symlink(source, target)


def stage_app(app_dir, staged):
    """Build a private copy of oolite.app whose GNUSTEP_USERS_ROOT is this run's alone.

    Cheap on purpose: the game only needs its BINARY to sit in a private directory, because that
    directory is what main.m:119 turns into GNUSTEP_USERS_ROOT. Read-only directories (Resources,
    the GL DLLs' folders) are junctions into the real build, files are hard links, and only the
    three directories the game writes are real copies.
    """
    os.makedirs(staged, exist_ok=True)
    for name in sorted(os.listdir(app_dir)):
        source = os.path.join(app_dir, name)
        target = os.path.join(staged, name)
        if os.path.exists(target) or os.path.islink(target):
            continue
        if os.path.isdir(source):
            if name in PRIVATE_SUBDIRS:
                shutil.copytree(source, target, dirs_exist_ok=True)
            else:
                _link_dir(source, target)
        else:
            try:
                os.link(source, target)
            except OSError:
                shutil.copy2(source, target)
    for name in PRIVATE_SUBDIRS:
        os.makedirs(os.path.join(staged, name), exist_ok=True)
    return staged


def unstage_app(staged):
    """Remove a staged app WITHOUT following its junctions into the real build.

    shutil.rmtree over a tree containing junctions is exactly how a harness deletes the build it
    was supposed to read, so links are removed as links and only real copies are recursed into.
    """
    if not os.path.isdir(staged):
        return
    for name in os.listdir(staged):
        path = os.path.join(staged, name)
        if os.path.islink(path) or (os.path.isdir(path) and _is_reparse_point(path)):
            try:
                os.rmdir(path)
            except OSError:
                try:
                    os.unlink(path)
                except OSError:
                    pass
        elif os.path.isdir(path):
            shutil.rmtree(path, ignore_errors=True)
        else:
            try:
                os.unlink(path)
            except OSError:
                pass
    try:
        os.rmdir(staged)
    except OSError:
        pass


def _is_reparse_point(path):
    """A junction is not an os.path.islink on stock CPython < 3.8 and is not always one now."""
    try:
        return bool(os.lstat(path).st_file_attributes & 0x400)  # FILE_ATTRIBUTE_REPARSE_POINT
    except (OSError, AttributeError):
        return False


def prefs_file(app_root):
    """The defaults file the game writes: GNUSTEP_USERS_ROOT/GNUstep/Defaults/oolite.plist.

    Learned on bead oo-5rsa: this is an OpenStep 'old-style' plist, NOT XML, so plistlib cannot
    parse a real one. Nothing here parses it; only its PATH and its owner matter.
    """
    return os.path.join(app_root, "GNUstep", "Defaults", "oolite.plist")


def run_test(bin_name, test_output, port, host, load_save, settle_game_seconds, ready_timeout,
             app_dir=None, keep_staged=False):
    """Launch one game and capture one snapshot. Safe to run N times concurrently.

    ``app_dir`` is the built oolite.app to run. The game is NOT launched from it: a private copy
    is staged under a per-run temporary directory and the binary is launched from there, so this
    run's GNUSTEP_USERS_ROOT - which the game derives from its own executable's location and which
    no environment variable can override - is nobody else's. Defaults to the current directory,
    which is what the CLI chdir'd into.
    """
    if app_dir is None:
        app_dir = os.getcwd()
    app_dir = os.path.abspath(app_dir)

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
    staged_app = os.path.join(staged_root, "app")
    stage_app(app_dir, staged_app)
    print(f"[*] Private prefs root: {staged_app}")

    # Environment configuration for pure headless software offscreen rendering
    env = os.environ.copy()
    if not IS_WINDOWS:
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

        # Wait for the game itself, not for the clock. See wait_until_answering.
        if not wait_until_answering(conn, ready_timeout=ready_timeout):
            return False
        if not wait_until_rendering(conn, settle_game_seconds):
            return False
        if load_save and not wait_until_docked(conn):
            return False

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
            try:
                os.rmdir(staged_root)
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
    parser.add_argument(
        "--check-isolation",
        action="store_true",
        help="offline: hold N staged prefs roots at once and assert they cannot collide",
    )
    parser.add_argument(
        "--launch-probe",
        action="store_true",
        help="offline: run N OVERLAPPING run_test calls against a fake binary and assert each "
             "launched from its own private prefs root",
    )
    parser.add_argument(
        "--prefs-race",
        action="store_true",
        help="offline: construct the shared-GNUSTEP_USERS_ROOT race and prove staging closes it",
    )
    parser.add_argument(
        "--check-msys-paths",
        action="store_true",
        help="offline: prove an MSYS --load path misses the file unconverted and reaches it "
             "converted, and that the binary's -load argv is native",
    )
    parser.add_argument(
        "--check-settle-units",
        action="store_true",
        help="offline: prove the settle value is game-clock seconds, not frames, and that "
             "--settle-frames is an exact alias",
    )
    parser.add_argument(
        "--instances",
        type=int,
        default=3,
        help="how many concurrent instances the offline checks simulate (default: 3)",
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


# --- offline self-checks (bug oo-pzc1) ---------------------------------------------------------
#
# Both need no built game and no desktop, so they still gate something real in the detached,
# build-less checkout accept.sh merges into (the tools/check-splash-off.py --self-test pattern).


def _fake_app(root):
    """A minimal stand-in for a built oolite.app: a binary, a read-only dir, the written dirs."""
    os.makedirs(os.path.join(root, "Resources"), exist_ok=True)
    with open(os.path.join(root, "Resources", "big.dat"), "w") as handle:
        handle.write("x" * 4096)
    binary = "oolite.exe" if IS_WINDOWS else "oolite"
    with open(os.path.join(root, binary), "w") as handle:
        handle.write("#!/bin/sh\nexit 0\n")
    for name in PRIVATE_SUBDIRS:
        os.makedirs(os.path.join(root, name), exist_ok=True)
    os.makedirs(os.path.dirname(prefs_file(root)), exist_ok=True)
    with open(prefs_file(root), "w") as handle:
        handle.write("{ shared = 1; }\n")
    return root


def _prefs_race(instances=3):
    """Construct the race, then show staging closes it. Prints every step; exit 0 only if closed.

    THE RACE, exactly as N instances of the OLD code had it: every instance's GNUSTEP_USERS_ROOT
    is the ONE shared app dir, so every instance writes the SAME Defaults/oolite.plist and the
    last writer wins. Each "instance" here writes its own id into the prefs file it owns, and the
    property asserted afterwards is that EVERY instance can still read back ITS OWN id.
    """
    base = tempfile.mkdtemp(prefix="oolite-prefs-race-")
    failures = []
    try:
        app = _fake_app(os.path.join(base, "oolite.app"))

        # --- BEFORE: the shared root. This is the defect; it MUST fail. ---------------------
        shared_roots = [app] * instances
        for i, root in enumerate(shared_roots):
            with open(prefs_file(root), "w") as handle:
                handle.write("{ instance = %d; }\n" % i)
        shared_survivors = 0
        for i, root in enumerate(shared_roots):
            with open(prefs_file(root)) as handle:
                if ("instance = %d;" % i) in handle.read():
                    shared_survivors += 1
        print("[race] shared GNUSTEP_USERS_ROOT: %d/%d instances kept their own prefs"
              % (shared_survivors, instances))
        if shared_survivors != 1:
            failures.append(
                "the race did not reproduce: expected exactly 1 surviving writer with one shared "
                "root, got %d. A check that cannot fail is not a check." % shared_survivors
            )

        # --- AFTER: one staged app per instance. This is the fix; it MUST hold. -------------
        staged_roots = []
        for i in range(instances):
            staged = os.path.join(base, "staged-%d" % i, "app")
            stage_app(app, staged)
            staged_roots.append(staged)
        if len(set(staged_roots)) != instances:
            failures.append("staged app dirs are not distinct: %r" % (staged_roots,))
        for i, root in enumerate(staged_roots):
            with open(prefs_file(root), "w") as handle:
                handle.write("{ instance = %d; }\n" % i)
        staged_survivors = 0
        for i, root in enumerate(staged_roots):
            with open(prefs_file(root)) as handle:
                if ("instance = %d;" % i) in handle.read():
                    staged_survivors += 1
        print("[race] staged GNUSTEP_USERS_ROOT: %d/%d instances kept their own prefs"
              % (staged_survivors, instances))
        if staged_survivors != instances:
            failures.append("staging did not isolate the prefs file: %d/%d survived"
                            % (staged_survivors, instances))

        # The shared build must be untouched by any of it, and the binary must really be there.
        with open(prefs_file(app)) as handle:
            if "instance = %d;" % (instances - 1) not in handle.read():
                failures.append("the source app's own prefs file was not the shared one")
        binary = "oolite.exe" if IS_WINDOWS else "oolite"
        for root in staged_roots:
            if not os.path.isfile(os.path.join(root, binary)):
                failures.append("staged app %s has no %s to launch" % (root, binary))
            if not os.path.isfile(os.path.join(root, "Resources", "big.dat")):
                failures.append("staged app %s cannot see the shared Resources" % root)

        # unstage must not follow the junctions into the build. Asserted BEFORE anything else
        # removes the source, so the conjunct can actually be false.
        for root in staged_roots:
            unstage_app(root)
        leaked = [r for r in staged_roots if os.path.isdir(r)]
        if leaked:
            failures.append("staged app dirs survived unstage_app: %r" % leaked)
        if not os.path.isfile(os.path.join(app, "Resources", "big.dat")):
            failures.append("unstage_app followed a junction and deleted the real build")
    finally:
        shutil.rmtree(base, ignore_errors=True)

    for line in failures:
        print("[!] %s" % line)
    if failures:
        print("prefs-race: FAIL")
        return 1
    print("prefs-race: PASS - the shared root loses %d/%d writers, staging loses none"
          % (instances - 1, instances))
    return 0


def _check_isolation(instances=3):
    """Assert that N SIMULTANEOUSLY HELD staged roots cannot collide, and that the source can.

    The plans are held at once on purpose: these are the roots N concurrent run_test calls own at
    the same moment, so a collision here is a collision two real runs have.
    """
    base = tempfile.mkdtemp(prefix="oolite-isolation-")
    failures = []
    roots = []
    try:
        app = _fake_app(os.path.join(base, "oolite.app"))
        for _ in range(instances):
            staged_root = tempfile.mkdtemp(prefix="oolite-run-", dir=base)
            staged = os.path.join(staged_root, "app")
            stage_app(app, staged)
            roots.append(staged)
        for key, values in (("staged app dir", roots),
                            ("prefs file", [prefs_file(r) for r in roots])):
            if len(set(values)) != instances:
                failures.append("two concurrent runs would collide on %s: %r" % (key, values))
        for root in roots:
            if os.path.normcase(os.path.abspath(root)) == os.path.normcase(os.path.abspath(app)):
                failures.append("a staged root IS the shared build: %s" % root)
        print("ok: %d isolated prefs roots" % len(roots) if not failures else "collision")
    finally:
        for root in roots:
            unstage_app(root)
        shutil.rmtree(base, ignore_errors=True)
    for line in failures:
        print("[!] %s" % line)
    return 1 if failures else 0


class _SpawnRecord:
    """Stands in for the game process: records WHERE it was launched from, then reports exit 0.

    The launch directory is the whole measurement. src/SDL/main.m:91-119 takes the directory of
    the RUNNING EXECUTABLE (QueryFullProcessImageName) and makes it GNUSTEP_USERS_ROOT, so the
    directory argv[0] resolves to IS this instance's prefs root - nothing the parent puts in the
    environment changes it. Resolving argv[0] against the cwd the spawn was given (or the process
    cwd when it was given none, which is how the pre-fix code launched "./oolite.exe") reproduces
    exactly what CreateProcess would do.
    """

    lock = None
    seen = None

    def __init__(self, cmd, cwd=None, **kwargs):
        argv0 = cmd[0] if isinstance(cmd, (list, tuple)) else str(cmd).split()[0]
        root = os.path.dirname(os.path.abspath(os.path.join(cwd or os.getcwd(), argv0)))
        # Recorded AT SPAWN TIME, because run_test removes the staged app on its way out and a
        # check made afterwards would be asking about a directory that no longer exists.
        usable = os.path.isdir(os.path.dirname(prefs_file(root)))
        with _SpawnRecord.lock:
            _SpawnRecord.seen.append((os.path.normcase(root), usable))
        self.returncode = 0

    def poll(self):
        return self.returncode

    def wait(self, timeout=None):
        return self.returncode

    def kill(self):
        pass


def _launch_probe(instances=3, stagger=0.4):
    """Run N run_test calls that OVERLAP and assert each launched from its OWN prefs root.

    Overlapping on purpose: a solo run has nothing to collide with, which is precisely why a solo
    run missed this class of defect before. Threads are staggered so the runs are genuinely
    simultaneous rather than merely consecutive, and every recorded root is compared.

    Against the pre-fix code all N roots are the ONE shared app directory and this returns 1.
    """
    import threading

    base = tempfile.mkdtemp(prefix="oolite-launch-probe-")
    previous_cwd = os.getcwd()
    real_popen = subprocess.Popen
    _SpawnRecord.lock = threading.Lock()
    _SpawnRecord.seen = []
    failures = []
    try:
        app = _fake_app(os.path.join(base, "oolite.app"))
        bin_name = "oolite.exe" if IS_WINDOWS else "oolite"
        # The pre-fix code spawned "./<binary>" with no cwd, i.e. relative to the PROCESS cwd,
        # which its CLI had chdir'd into the app dir. Both versions start from that same world.
        os.chdir(app)
        subprocess.Popen = _SpawnRecord

        results = {}

        def one(i):
            out = os.path.join(base, "out-%d" % i)
            os.makedirs(out, exist_ok=True)
            try:
                results[i] = run_test(bin_name, out, 8700 + i, "127.0.0.1", None, 0.1, 1,
                                      app_dir=app)
            except TypeError:
                # The pre-fix signature has no app_dir; call it as it was, so the probe measures
                # the OLD behaviour rather than erroring out before it measures anything.
                results[i] = run_test(bin_name, out, 8700 + i, "127.0.0.1", None, 0.1, 1)
            except Exception as exc:  # noqa: BLE001 - reported, never swallowed
                results[i] = "error: %s" % exc

        threads = []
        for i in range(instances):
            t = threading.Thread(target=one, args=(i,))
            t.start()
            threads.append(t)
            time.sleep(stagger)  # overlap on purpose
        for t in threads:
            t.join(timeout=180)

        recorded = list(_SpawnRecord.seen)
        roots = [r for r, _ in recorded]
        unusable = [r for r, usable in recorded if not usable]
        print("[probe] %d overlapping instances; run_test returned %r"
              % (instances, sorted(results.items(), key=lambda kv: kv[0])))
        for root in roots:
            print("[probe] launched from %s" % root)
        shared = os.path.normcase(os.path.abspath(app))
        if len(roots) != instances:
            failures.append("expected %d launches, recorded %d" % (instances, len(roots)))
        if len(set(roots)) != len(roots):
            failures.append(
                "CONCURRENT INSTANCES SHARE A GNUSTEP_USERS_ROOT: %d distinct launch directories "
                "for %d instances" % (len(set(roots)), len(roots)))
        if shared in set(roots):
            failures.append("an instance launched out of the SHARED build directory %s" % shared)
        # A distinct root that cannot hold a prefs file isolates nothing, so "distinct" alone is
        # not the property. Measured at spawn time (see _SpawnRecord).
        for root in unusable:
            failures.append("%s had no GNUstep/Defaults to write prefs into at launch" % root)
        # Asserted while the source build still exists, so it can actually be false.
        if not os.path.isfile(os.path.join(app, "Resources", "big.dat")):
            failures.append("the shared build lost Resources/big.dat during the run")
    finally:
        subprocess.Popen = real_popen
        os.chdir(previous_cwd)
        shutil.rmtree(base, ignore_errors=True)

    for line in failures:
        print("[!] %s" % line)
    if failures:
        print("launch-probe: FAIL")
        return 1
    print("launch-probe: PASS - %d overlapping instances, %d distinct private prefs roots, none "
          "the shared build" % (instances, len(set(roots))))
    return 0


class _ArgvRecord:
    """Stands in for the game process: records the argv it was spawned with, then reports exit 0.

    Exit 0 at poll() time is deliberate - run_test sees the child gone before it connects, prints
    so, and returns False in under a second, which is all the time this check needs. The argv is
    captured at spawn, which is the moment the string stops being python's and becomes a native
    Windows process's.
    """

    lock = None
    seen = None

    def __init__(self, cmd, cwd=None, **kwargs):
        with _ArgvRecord.lock:
            _ArgvRecord.seen.append(list(cmd))
        self.returncode = 0

    def poll(self):
        return self.returncode

    def wait(self, timeout=None):
        return self.returncode

    def kill(self):
        pass


def _spawn_recorder(real_popen, binary):
    """Intercept ONLY the game launch; every other spawn goes to the real Popen.

    Necessary because native_path itself shells out to cygpath: a blanket replacement of
    subprocess.Popen would swallow the very conversion under test (and cygpath's Popen is used as
    a context manager, which the recorder is not).
    """

    def spawn(cmd, *args, **kwargs):
        argv0 = cmd[0] if isinstance(cmd, (list, tuple)) else str(cmd)
        if os.path.basename(str(argv0)) == binary:
            return _ArgvRecord(cmd, *args, **kwargs)
        return real_popen(cmd, *args, **kwargs)

    return spawn


def _check_msys_paths():
    """Prove the MSYS boundary BOTH ways: the broken form is still broken, the fix resolves it.

    Three things are asserted, and the first is the one that makes this a check rather than a
    decoration: the DEFECT MUST REPRODUCE. os.path.abspath on an MSYS path has to yield something
    that is NOT the file, or there is no bug here and the rest proves nothing.

    Runs offline, with no built game and no desktop: the game process is replaced by _ArgvRecord,
    so what is measured is the argv a NATIVE binary would have received.
    """
    import threading

    if not IS_WINDOWS or not _CYGPATH:
        print("=" * 78)
        print("SKIPPED: --check-msys-paths needs a native Windows python with cygpath on PATH.")
        print("  IS_WINDOWS=%r cygpath=%r" % (IS_WINDOWS, _CYGPATH))
        print("  There is no MSYS/native boundary to cross here, so there is nothing to check.")
        print("=" * 78)
        return 0

    base = tempfile.mkdtemp(prefix="oolite-msys-path-")
    previous_cwd = os.getcwd()
    real_popen = subprocess.Popen
    _ArgvRecord.lock = threading.Lock()
    _ArgvRecord.seen = []
    failures = []
    try:
        save = os.path.join(base, "checklist.oolite-save")
        with open(save, "w") as handle:
            handle.write("<save/>\n")
        real = os.path.normcase(os.path.abspath(save))

        # The MSYS spelling of that exact file - what the repository's own bash hands to --load.
        msys = subprocess.run(
            [_CYGPATH, "-u", "--", save], capture_output=True, text=True, check=True
        ).stdout.strip()
        print("[msys] native : %s" % save)
        print("[msys] MSYS   : %s" % msys)
        if not msys.startswith("/"):
            failures.append("cygpath -u did not produce a POSIX path: %r" % msys)
        if not looks_like_msys_path(msys):
            failures.append("looks_like_msys_path rejected a real MSYS path: %r" % msys)

        # --- BEFORE: the pre-fix expression. It MUST NOT reach the file. ---------------------
        broken = os.path.abspath(msys)
        print("[msys] os.path.abspath(MSYS) -> %s  (isfile=%r)" % (broken, os.path.isfile(broken)))
        if os.path.normcase(broken) == real:
            failures.append(
                "the defect did not reproduce: os.path.abspath(%r) already resolved to the real "
                "file. A check that cannot fail is not a check." % msys
            )
        if os.path.isfile(broken):
            failures.append("os.path.abspath(%r) reached a FILE at %r - the scratch directory was "
                            "not where this check thought it was" % (msys, broken))

        # --- AFTER: the fix. It MUST reach exactly that file. --------------------------------
        fixed = os.path.abspath(native_path(msys))
        print("[msys] native_path(MSYS)     -> %s  (isfile=%r)" % (fixed, os.path.isfile(fixed)))
        if os.path.normcase(fixed) != real:
            failures.append("native_path(%r) resolved to %r, not the save at %r"
                            % (msys, fixed, real))
        if not os.path.isfile(fixed):
            failures.append("native_path(%r) does not name an existing file" % msys)

        # Idempotent: an already-native path must survive untouched, or a caller that converted
        # once would be mangled by converting twice (run_test converts again, on purpose).
        if native_path(save) != save:
            failures.append("native_path mangled an already-native path: %r -> %r"
                            % (save, native_path(save)))
        for already in ("C:/x/y.oolite-save", r"C:\x\y.oolite-save", "relative.oolite-save"):
            if native_path(already) != already:
                failures.append("native_path touched a non-MSYS path %r -> %r"
                                % (already, native_path(already)))

        # --- BEHAVIOURAL: what argv does the NATIVE binary actually get? ---------------------
        app = _fake_app(os.path.join(base, "oolite.app"))
        bin_name = "oolite.exe" if IS_WINDOWS else "oolite"
        out = os.path.join(base, "out")
        os.makedirs(out, exist_ok=True)
        os.chdir(app)
        subprocess.Popen = _spawn_recorder(real_popen, bin_name)
        try:
            run_test(bin_name, out, 8791, "127.0.0.1", msys, 0.1, 1, app_dir=app)
        finally:
            subprocess.Popen = real_popen
            os.chdir(previous_cwd)

        if len(_ArgvRecord.seen) != 1:
            failures.append("expected exactly one spawn, recorded %d" % len(_ArgvRecord.seen))
        for argv in _ArgvRecord.seen:
            print("[msys] spawned argv: %r" % (argv,))
            if "-load" not in argv:
                failures.append("run_test dropped -load from the argv: %r" % (argv,))
                continue
            handed = argv[argv.index("-load") + 1]
            if looks_like_msys_path(handed):
                failures.append(
                    "run_test handed an MSYS path to the native binary's -load: %r. This is the "
                    "bug: the game resolves it against the current drive and loads nothing."
                    % handed
                )
            if os.path.normcase(os.path.abspath(handed)) != real:
                failures.append("-load argument %r does not name the save at %r" % (handed, real))
            if not os.path.isfile(handed):
                failures.append("-load argument %r is not an existing file" % handed)
            # The staging from bug oo-pzc1 must still be intact: the binary launched must be the
            # PRIVATE staged copy, never the shared build.
            launched = os.path.dirname(os.path.abspath(argv[0]))
            if os.path.normcase(launched) == os.path.normcase(os.path.abspath(app)):
                failures.append("the run launched out of the SHARED build %s - per-run staging "
                                "(bug oo-pzc1) was undone" % app)
    finally:
        subprocess.Popen = real_popen
        os.chdir(previous_cwd)
        shutil.rmtree(base, ignore_errors=True)

    for line in failures:
        print("[!] %s" % line)
    if failures:
        print("msys-paths: FAIL")
        return 1
    print("msys-paths: PASS - abspath alone misses the file, native_path reaches it, and the "
          "binary's -load argv is native")
    return 0


def _settle_units_check():
    """Offline: prove the settle knob is GAME-CLOCK SECONDS, and that both spellings agree.

    A grep for the new flag name proves nothing about units. The observable is behavioural: ask
    for N and the wait must end when the GAME's clock has advanced N - regardless of how many
    polls (frames) that took and regardless of wall-clock time. So this drives the real
    wait_until_rendering against a stubbed clock:

      * a clock ticking 0.25 game-seconds per poll must satisfy N=1.0 after ~4 polls, not after
        1 poll (which is what a frame COUNT of 1.0 would mean);
      * a clock that is frozen - the run loop stalled - must be REFUSED, never satisfied. Without
        this case the check could not fail.
    """
    global evaluate
    real_evaluate = evaluate
    failures = []

    def run(step, want, timeout=6):
        polls = {"n": 0}

        def fake(conn, js, timeout=20):
            if js != "clock.absoluteSeconds":
                return "GUI_SCREEN_MAIN"
            value = polls["n"] * step
            polls["n"] += 1
            return repr(value)

        globals()["evaluate"] = fake
        try:
            return wait_until_rendering(None, want, timeout=timeout), polls["n"]
        finally:
            globals()["evaluate"] = real_evaluate

    # 1. Ticking clock: N is seconds of game time, so N=1.0 at 0.25/poll needs >= 5 reads
    #    (the baseline read plus four advancing ones). A frame count would have stopped at 2.
    ok, polls = run(0.25, 1.0)
    if not ok:
        failures.append("advancing game clock did not satisfy a 1.0 game-second settle")
    elif polls < 5:
        failures.append(
            "settle of 1.0 was satisfied after %d clock reads at 0.25s/read - that is a frame "
            "count, not seconds" % polls
        )

    # 2. Asking for MORE seconds must take strictly more polls. Units scale; a frame count of
    #    2.0 vs 1.0 at this tick rate would not.
    ok_two, polls_two = run(0.25, 2.0)
    if not ok_two or polls_two <= polls:
        failures.append(
            "settle 2.0 took %r reads vs %r for 1.0 - the value does not scale as a duration"
            % (polls_two, polls)
        )

    # 3. THE FAILURE CASE: a stalled run loop (game clock frozen) must be refused, not settled.
    frozen, _ = run(0.0, 1.0, timeout=2)
    if frozen:
        failures.append("frozen game clock was accepted as settled - the wait cannot fail")

    # 4. Both spellings resolve to the same field and the same unit; neither converts.
    new = parse_args(["--settle-game-seconds", "7.5"]).settle_game_seconds
    old = parse_args(["--settle-frames", "7.5"]).settle_game_seconds
    default = parse_args([]).settle_game_seconds
    if new != 7.5:
        failures.append("--settle-game-seconds 7.5 resolved to %r" % new)
    if old != 7.5:
        failures.append("--settle-frames 7.5 resolved to %r, not the same quantity" % old)
    if default != float(os.environ.get("OO_SNAPSHOT_SETTLE", DEFAULT_SETTLE_GAME_SECONDS)):
        failures.append("default settle resolved to %r" % default)

    for line in failures:
        print("[!] %s" % line)
    if failures:
        print("settle-units: FAIL")
        return 1
    print("settle-units: PASS - settle is game-clock seconds (1.0s took %d clock reads at "
          "0.25s/read), a frozen clock is refused, and --settle-frames is an exact alias" % polls)
    return 0


def _desktop_lock_helper():
    """tools/desktop_lock from the OUTER repository, or None when there is none.

    This file lives in a subtree that is also pushed to the fork on its own, where tools/ does
    not exist; there is no fleet to collide with there, so a missing helper is not an error. When
    the outer repository IS around us, its tools/gui-lock is the desktop mutex every launcher on
    this machine shares, and this launcher must take it (bug oo-ccy9).
    """
    here = os.path.dirname(os.path.abspath(__file__))
    while True:
        tools = os.path.join(here, "tools")
        if os.path.isfile(os.path.join(tools, "gui-lock")) and os.path.isfile(
            os.path.join(tools, "desktop_lock.py")
        ):
            if tools not in sys.path:
                sys.path.insert(0, tools)
            import desktop_lock  # noqa: F401  - located at runtime, on purpose

            return desktop_lock
        parent = os.path.dirname(here)
        if parent == here:
            print(
                "[!] no tools/desktop_lock.py above this checkout; "
                "launching WITHOUT the desktop mutex"
            )
            return None
        here = parent


if __name__ == "__main__":
    args = parse_args()

    # The offline checks come first: they need no build, no desktop and no chdir.
    if args.prefs_race:
        sys.exit(_prefs_race(max(2, args.instances)))
    if args.check_isolation:
        sys.exit(_check_isolation(max(2, args.instances)))
    if args.launch_probe:
        sys.exit(_launch_probe(max(2, args.instances)))
    if args.check_msys_paths:
        sys.exit(_check_msys_paths())
    if args.check_settle_units:
        sys.exit(_settle_units_check())

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

        # THE DESKTOP LOCK (bug oo-ccy9). This is the smoke test, and it launches ONE game -
        # which on Windows means one real window on the interactive desktop, because
        # SDL_VIDEODRIVER=offscreen is deliberately not set there. Two games on the desktop at
        # once steal each other's foreground, so it queues behind the GUI tier rather than
        # racing it.
        #
        # The lock lives in the OUTER repository (tools/gui-lock), not in this subtree, and this
        # file must keep working when the subtree is pushed to the fork on its own - so the
        # helper is located at runtime and a missing one is a warning, not a failure. It is also
        # taken around run_test only: acquiring before the chdir above would hold the desktop
        # while resolving paths, which is free but says the wrong thing about what the lock
        # protects.
        lock_helper = _desktop_lock_helper()
        if lock_helper is None:
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
        else:
            with lock_helper.desktop_lock("smoke", start=__file__, stream=sys.stdout):
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
