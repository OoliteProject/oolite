"""Launch Oolite headless, drive it over the debug console, and capture one screenshot.

Everything is an argument or an environment variable, so N copies of ``run_test`` can run at
once: each picks its own console port and its own artifact directory, and nothing is shared
between them except the binary. --load hands a saved commander to the game's -load argument so a
run can start docked instead of on the main-menu demo.

Three things here are not obvious:

* The PORT is not something this script can simply choose. It is the GAME that dials out to the
  console, and it reads the port from `console-port` in debugConfig.plist (OODebugSupport.m:80,
  default kOOTCPConsolePort = 8563 in OODebugTCPConsoleProtocol.h:46). So a port is made real by
  writing a plist the game will merge, not by listening somewhere else. See _console_config_dir.

* Readiness is measured on the GAME's clock, never on this script's. See wait_until_rendering.

* The PREFS ROOT is per-run, by staging a private oolite.app. ``src/SDL/main.m:119`` does

      SDL_setenv_unsafe("GNUSTEP_USERS_ROOT", currentWorkingDir, YES)

  where ``currentWorkingDir`` is the directory holding the EXECUTABLE and the trailing ``YES`` is
  SDL's *overwrite* flag. So the game overwrites whatever the parent exported: giving each child
  its own ``GNUSTEP_USERS_ROOT`` in the environment does nothing on Windows, and instances that
  share one oolite.app race on one ``GNUstep/Defaults/oolite.plist`` (written by
  ``-exitAppWithContext:`` as a whole-file read-modify-write, so the last writer wins and the
  other runs' preferences are lost).

  The only thing the game reads is where its own binary lives, so isolation needs a private
  directory holding the binary. ``stage_app`` builds one: junctions or symlinks for read-only
  directories, hard links for files, and real copies for the three directories the game writes.
  A lock would be the wrong tool, because it would serialise the N concurrent runs.

* PATHS FROM THE COMMAND LINE CROSS A BOUNDARY on Windows. Under MSYS2 bash, ``--load "$SAVE"``
  with ``$SAVE`` a natural ``/c/Users/...`` path hands an MSYS path to a NATIVE Windows python.
  ``os.path.abspath`` then resolves it against the current drive (``/c/Users/x`` becomes
  ``C:/c/Users/x``), and the same string would go on to the native game binary's ``-load``. Every
  path that arrives as an argument is therefore converted at the boundary with ``cygpath -m``.
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


# --- THE MSYS PATH BOUNDARY ---------------------------------------------------------------------
#
# This script may be a NATIVE Windows python invoked from MSYS2 bash, and the two disagree about
# what a path is. `/c/Users/jon/save.oolite-save` is what the shell means; os.path.abspath resolves
# it against the CURRENT DRIVE and yields `C:/c/Users/jon/save.oolite-save`, which can be a real
# directory, so the mistake does not announce itself - it silently reads the wrong tree, or hands
# the wrong string to the game's -load. cygpath is the only thing that knows the mapping (it reads
# /etc/fstab and the MSYS root), so it does the conversion.
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


# --- per-run prefs isolation --------------------------------------------------------------------
#
# Real copies rather than links: these are the directories the GAME WRITES, and sharing them is
# the collision. GNUstep/ holds Defaults/oolite.plist (the raced file), Logs/ holds Latest.log,
# oolite-saves/ holds commanders.
PRIVATE_SUBDIRS = ("GNUstep", "Logs", "oolite-saves")


def _link_dir(source, target):
    """Junction (Windows) or symlink: a read-only directory shared with the real build."""
    if IS_WINDOWS:
        import _winapi

        _winapi.CreateJunction(source, target)
    else:
        os.symlink(source, target)


# On macOS the binary lives in oolite.app/Contents/MacOS and finds its dylibs and resources through
# paths relative to itself (@loader_path/../Frameworks, ../Resources). A staged copy of MacOS alone
# would lose them, so the other entries of Contents are linked in beside it. Logs is left out: the
# game's logs are redirected to the test output directory.
BUNDLE_BINARY_DIR = "MacOS"
BUNDLE_SKIPPED_SIBLINGS = ("Logs",)


def _bundle_contents(app_dir):
    """The Contents directory when app_dir is an app bundle's MacOS directory, else None."""
    if os.path.basename(app_dir) != BUNDLE_BINARY_DIR:
        return None
    contents = os.path.dirname(app_dir)
    if os.path.basename(contents) != "Contents":
        return None
    return contents


def _bundle_siblings(contents):
    return [name for name in sorted(os.listdir(contents))
            if name != BUNDLE_BINARY_DIR and name not in BUNDLE_SKIPPED_SIBLINGS]


def _link_bundle_siblings(app_dir, staged):
    """Make a staged MacOS directory look like part of a bundle; a no-op for any other layout."""
    contents = _bundle_contents(app_dir)
    if contents is None or os.path.basename(staged) != BUNDLE_BINARY_DIR:
        return
    staged_contents = os.path.dirname(staged)
    for name in _bundle_siblings(contents):
        target = os.path.join(staged_contents, name)
        if not os.path.lexists(target):
            os.symlink(os.path.join(contents, name), target)


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
            elif name == "MacOS":
                # A bundle's executable must sit in a real Contents/MacOS: the game finds its
                # Resources from the real path of the binary, so a linked directory would resolve
                # back into the shared build.
                shutil.copytree(source, target, dirs_exist_ok=True, copy_function=_link_file)
            else:
                _link_dir(source, target)
        else:
            try:
                os.link(source, target)
            except OSError:
                shutil.copy2(source, target)
    for name in PRIVATE_SUBDIRS:
        os.makedirs(os.path.join(staged, name), exist_ok=True)
    _link_bundle_siblings(app_dir, staged)
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
    _unlink_bundle_siblings(staged)


def _unlink_bundle_siblings(staged):
    """Remove the links _link_bundle_siblings made beside a staged MacOS directory."""
    if os.path.basename(staged) != BUNDLE_BINARY_DIR:
        return
    staged_contents = os.path.dirname(staged)
    if not os.path.isdir(staged_contents):
        return
    for name in os.listdir(staged_contents):
        path = os.path.join(staged_contents, name)
        if os.path.islink(path):
            os.unlink(path)
    try:
        os.rmdir(staged_contents)
    except OSError:
        pass


def _is_reparse_point(path):
    """A junction is not an os.path.islink on stock CPython < 3.8 and is not always one now."""
    try:
        return bool(os.lstat(path).st_file_attributes & 0x400)  # FILE_ATTRIBUTE_REPARSE_POINT
    except (OSError, AttributeError):
        return False


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

    # THE PREFS ROOT. Stage a private oolite.app and run the binary from THERE, so main.m:119
    # derives this run's GNUSTEP_USERS_ROOT from a directory nobody else is using. Not an env var -
    # the game overwrites it (SDL_setenv_unsafe ..., YES) - and not a lock, which would serialise
    # the concurrent runs this function is meant to support.
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
        # Converted HERE too, not only in __main__: this is where the string stops being python's
        # and becomes a NATIVE Windows process's argv, and run_test is a library function that
        # other callers invoke directly with whatever their own MSYS shell handed them.
        # native_path is a no-op on an already-native path, so converting twice is harmless.
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
            if sys.platform == "darwin" and proc.poll() is None:
                # Show where a hung process is stuck
                subprocess.run(["sample", str(proc.pid), "3"], stdout=sys.stdout, stderr=sys.stderr)
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
    # C:/c/... that may exist on this machine. The same reasoning applies to --path and
    # --output, which also arrive from the MSYS shell and also end up in the native game's world
    # (the app dir becomes the staging source and the cwd; the output dir becomes OO_SNAPSHOTSDIR
    # and OO_LOGSDIR, read by the game itself).
    target_dir = os.path.abspath(native_path(args.path))

    # If the user pointed to a file, get the containing directory
    if os.path.isfile(target_dir):
        bin_name = os.path.basename(target_dir)
        target_dir = os.path.dirname(target_dir)
        if os.path.basename(target_dir) == "MacOS" and (
                os.path.basename(os.path.dirname(target_dir)) == "Contents"):
            # An app bundle: stage the whole Contents, and run MacOS/oolite from it.
            bin_name = os.path.join("MacOS", bin_name)
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

        # This is the smoke test, and it launches ONE game - which on Windows means one real
        # window on the interactive desktop, because SDL_VIDEODRIVER=offscreen is deliberately
        # not set there. Two games on the desktop at once steal each other's foreground, so run
        # it alone (tests/run.sh smoke).
        #
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
