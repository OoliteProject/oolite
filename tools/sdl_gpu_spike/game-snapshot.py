#!/usr/bin/env python3
"""Run Oolite through a list of debug console commands and collect snapshots.

Usage: game-snapshot.py <oolite binary> <output dir> <command>...

Each command is JavaScript sent to the game's debug console, "sleep:<s>", or
"key:<SDL key name>" to press and release a key (debug builds), or
"script:<file>" to send a JavaScript file. With --scenario as the first
command, the RenderTest OXP in scenarios/ is loaded; it drives the game
through a fixed list of screens and quits (see its Config/script.js), so
no further commands are needed. With --gallery <OXZ dir> instead, the
OXPGallery OXP in gallery/ and the OXZs in that directory (fetched by
gallery/fetch-gallery.py) are loaded; it launches, snapshots a list of OXP
ships one by one and quits.
The game runs with -novsync (a locked macOS screen otherwise blocks GL
buffer swaps), no sound, and OO_FREEZE_DEMO_SHIPS=1, so in debug builds the
title screen ship holds still and the whole title screen is reproducible:
two runs differ by at most 1/255. The GUI cursor follows the mouse, so on
macOS the pointer is first moved to the top left corner of the main display.
Snapshots and Latest.log go to the output
directory. Example, for the title screen:

    game-snapshot.py build/meson_dev/oolite.app/Contents/MacOS/oolite out \
        sleep:5 "takeSnapShot();" sleep:2 "quit();"

The window is always 1280 x 720 points, whatever size the player last
left it at, so snapshots stay comparable. On macOS the player's saved
window size is put back afterwards, in case the game saved ours over it.
Set OO_SNAPSHOT_ARGS to pass extra launch arguments, such as settings that
Foundation reads as defaults for this run only: "-detailLevel 3
-anti-aliasing YES".
"""
import ctypes, os, select, socket, subprocess, sys, time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tests"))
import launch_snapshot as ls  # noqa: E402

binary, outdir = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
commands = sys.argv[3:]
scenario = bool(commands) and commands[0] == "--scenario"
gallery = None
if len(commands) >= 2 and commands[0] == "--gallery":
    gallery = os.path.abspath(commands[1])
    commands = ["--scenario"] + commands[2:]
    scenario = True
if scenario:
    # The title screens are static; world scripts take over once the game starts.
    commands = ["sleep:5", "takeSnapShot();", "sleep:1", "key:Return", "sleep:2", "takeSnapShot();", "sleep:1", "key:Return"] + commands[1:]
os.makedirs(outdir, exist_ok=True)

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind((ls.HOST, ls.PORT))
server.listen(1)

if sys.platform == "darwin":
    class CGPoint(ctypes.Structure):
        _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double)]
    cg = ctypes.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
    cg.CGWarpMouseCursorPosition.argtypes = [CGPoint]
    cg.CGWarpMouseCursorPosition(CGPoint(0, 0))

env = os.environ.copy()
env.update({"SDL_AUDIODRIVER": "dummy", "ALSOFT_DRIVERS": "null", "OO_SNAPSHOTSDIR": outdir, "OO_LOGSDIR": outdir,
            "OO_FREEZE_DEMO_SHIPS": "1", "OO_DETERMINISTIC_TEST": "1"})
here = os.path.dirname(os.path.abspath(__file__))
if gallery:
    env["OO_ADDITIONALADDONSDIRS"] = os.path.join(here, "gallery") + "," + gallery
elif scenario:
    env["OO_ADDITIONALADDONSDIRS"] = os.path.join(here, "scenarios")
# OO_SNAPSHOT_ARGS adds launch arguments. Foundation reads "-key value" pairs
# as defaults for this run only, e.g. "-detailLevel 3 -anti-aliasing YES".
extra = os.environ.get("OO_SNAPSHOT_ARGS", "").split()
window = ["-window_width", "1280", "-window_height", "720"]


def saved_window_size():
    if sys.platform != "darwin":
        return None
    values = []
    for key in ("window_width", "window_height"):
        result = subprocess.run(["defaults", "read", "oolite", key], capture_output=True, text=True)
        values.append(result.stdout.strip() if result.returncode == 0 else None)
    return values


def restore_window_size(values):
    if values is None or saved_window_size() == values:
        return
    for key, value in zip(("window_width", "window_height"), values):
        if value is None:
            subprocess.run(["defaults", "delete", "oolite", key], capture_output=True)
        else:
            subprocess.run(["defaults", "write", "oolite", key, "-int", value], capture_output=True)


player_window = saved_window_size()
proc = subprocess.Popen([binary, "--no-splash", "-novsync"] + window + extra, cwd=os.path.dirname(binary), env=env,
                        stdout=open(os.path.join(outdir, "stdout.txt"), "w"), stderr=subprocess.STDOUT)
conn = None
deadline = time.time() + 30
while time.time() < deadline and conn is None:
    if select.select([server], [], [], 1)[0]:
        conn, _ = server.accept()
if conn is None:
    print("no connection")
    subprocess.run(["sample", str(proc.pid), "2"], stdout=subprocess.DEVNULL)
    proc.kill()
    restore_window_size(player_window)
    sys.exit(1)
pkt = ls.receive_plist_packet(conn)
ls.send_plist_packet(conn, {ls.PACKET_TYPE_KEY: ls.APPROVE_CONNECTION, ls.CONSOLE_IDENTITY_KEY: "game-snapshot"})
print("connected:", pkt.get(ls.OOLITE_VERSION_KEY) if pkt else None)
conn.setblocking(False)
for cmd in commands:
    if cmd.startswith("sleep:"):
        time.sleep(float(cmd[6:]))
        continue
    if cmd.startswith("script:"):
        cmd = open(cmd[7:], encoding="utf-8").read()
    if cmd.startswith("key:"):
        name = cmd[4:].replace("'", "\\'")
        ls.send_plist_packet(conn, {ls.PACKET_TYPE_KEY: ls.PERFORM_COMMAND, ls.MESSAGE_KEY: f"console.simulateKey('{name}', true)"})
        time.sleep(0.3)
        ls.send_plist_packet(conn, {ls.PACKET_TYPE_KEY: ls.PERFORM_COMMAND, ls.MESSAGE_KEY: f"console.simulateKey('{name}', false)"})
        time.sleep(0.5)
        continue
    ls.send_plist_packet(conn, {ls.PACKET_TYPE_KEY: ls.PERFORM_COMMAND, ls.MESSAGE_KEY: cmd})
    time.sleep(0.5)
try:
    proc.wait(timeout=120 if scenario else 20)
except subprocess.TimeoutExpired:
    proc.kill()
restore_window_size(player_window)
print("snapshots:", sorted(f for f in os.listdir(outdir) if f.endswith(".png")))
