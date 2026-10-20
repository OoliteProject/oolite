#!/usr/bin/env python3
"""Run Oolite through a list of debug console commands and collect snapshots.

Usage: game-snapshot.py <oolite binary> <output dir> <command>...

Each command is JavaScript sent to the game's debug console, or "sleep:<s>".
The game runs with -novsync (a locked macOS screen otherwise blocks GL
buffer swaps), no sound, and OO_FREEZE_DEMO_SHIPS=1, so in debug builds the
title screen ship holds still and the whole title screen is reproducible:
two runs differ by at most 1/255. Snapshots and Latest.log go to the output
directory. Example, for the title screen:

    game-snapshot.py build/meson_dev/oolite.app/Contents/MacOS/oolite out \
        sleep:5 "takeSnapShot();" sleep:2 "quit();"
"""
import os, select, socket, subprocess, sys, time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tests"))
import launch_snapshot as ls  # noqa: E402

binary, outdir = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
commands = sys.argv[3:]
os.makedirs(outdir, exist_ok=True)

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind((ls.HOST, ls.PORT))
server.listen(1)

env = os.environ.copy()
env.update({"SDL_AUDIODRIVER": "dummy", "ALSOFT_DRIVERS": "null", "OO_SNAPSHOTSDIR": outdir, "OO_LOGSDIR": outdir,
            "OO_FREEZE_DEMO_SHIPS": "1"})
proc = subprocess.Popen([binary, "--no-splash", "-novsync"], cwd=os.path.dirname(binary), env=env,
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
    sys.exit(1)
pkt = ls.receive_plist_packet(conn)
ls.send_plist_packet(conn, {ls.PACKET_TYPE_KEY: ls.APPROVE_CONNECTION, ls.CONSOLE_IDENTITY_KEY: "game-snapshot"})
print("connected:", pkt.get(ls.OOLITE_VERSION_KEY) if pkt else None)
conn.setblocking(False)
for cmd in commands:
    if cmd.startswith("sleep:"):
        time.sleep(float(cmd[6:]))
        continue
    ls.send_plist_packet(conn, {ls.PACKET_TYPE_KEY: ls.PERFORM_COMMAND, ls.MESSAGE_KEY: cmd})
    time.sleep(0.5)
try:
    proc.wait(timeout=20)
except subprocess.TimeoutExpired:
    proc.kill()
print("snapshots:", sorted(f for f in os.listdir(outdir) if f.endswith(".png")))
