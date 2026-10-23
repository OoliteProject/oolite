"""
Smoke test: starts Oolite, optionally from a saved game, and checks that it
renders and shuts down cleanly.

With --load, the game starts docked from that save; the test then launches
the player into space and takes a snapshot there, which runs the world
scripts, the populator and the ship AIs. It fires a missile at an asteroid
and checks that one fewer missile remains, then docks with the docking
computer and takes a second snapshot. With --addons, the OXPs in that
directory are loaded too (run_test_fn.sh uses those listed in test-oxps.txt). In every case the test fails if the
log shows a JavaScript exception or error, a script that ran too long, or a
JavaScript runtime that did not pass its shutdown leak check.
"""

import argparse
import os
import struct
import sys
import time

from oolite_harness import HarnessError, JSException, OoliteGame, scaled

# Threshold for a valid render at the default window size (1280x720); scaled by a snapshot's pixel count.
MIN_FILE_SIZE_KB = 100
DEFAULT_PIXELS = 1280 * 720


def png_pixels(path):
    """Returns a PNG's width times height, from its IHDR chunk, or None if it is not a PNG."""
    with open(path, "rb") as f:
        header = f.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    width, height = struct.unpack(">II", header[16:24])
    return width * height


def check_snapshots(test_output, expected):
    snaps = sorted(f for f in os.listdir(test_output) if f.endswith(".png"))
    if len(snaps) < expected:
        print(f"[!] Failure: expected {expected} snapshot(s), found {len(snaps)}.")
        return False
    success = True
    for snap in snaps:
        snap_path = os.path.join(test_output, snap)
        file_size_kb = os.path.getsize(snap_path) // 1024
        pixels = png_pixels(snap_path) or DEFAULT_PIXELS
        minimum = MIN_FILE_SIZE_KB * pixels / DEFAULT_PIXELS
        print(f"[*] Captured {snap_path} ({file_size_kb} KB)")
        if file_size_kb < minimum:
            print(f"[!] Failure: snapshot is too small ({file_size_kb} KB, expected at least {minimum:.0f}). "
                  "Likely a black frame.")
            success = False
    if success:
        print("[+] Snapshots passed quality check.")
    return success


def take_snapshot(console):
    print("[*] Requesting snapshot...")
    console.evaluate("takeSnapShot()")
    # The snapshot is written on the next frame.
    time.sleep(scaled(2))


def fire_missile(console):
    """Fires a missile at an asteroid spawned ahead (a legal target), and checks one fewer remains."""
    before = console.evaluate("player.ship.missiles.length")
    console.evaluate(
        "(function () { var ps = player.ship;"
        " var rock = system.addShips('asteroid', 1, ps.position.add(ps.vectorForward.multiply(6000)), 0)[0];"
        " ps.target = rock; return ps.target === rock; })()"
    )
    print(f"[*] Firing a missile ({before} loaded)...")
    missile = console.evaluate("String(player.ship.fireMissile())")
    after = console.evaluate("player.ship.missiles.length")
    print(f"[*] Fired {missile}; {after} missiles left")
    if missile == "null" or after != before - 1:
        raise HarnessError(f"Firing a missile failed: {before} missiles before, {after} after.")


def dock(console):
    """Docks at the main station with the docking computer (the autopilot), with game time sped up."""
    acceleration = os.environ.get("OOLITE_TEST_DOCKING_ACCELERATION", "16")
    acceleration = console.evaluate(f"timeAccelerationFactor = {float(acceleration)}, timeAccelerationFactor")
    print(f"[*] Docking with the docking computer (time acceleration {acceleration}x)...")
    if not console.evaluate("player.ship.engageAutopilotToStation(system.mainStation)"):
        raise HarnessError("The docking computer could not be engaged.")
    start = time.time()
    deadline = start + scaled(600)
    reported = None
    while True:
        try:
            state = console.evaluate(
                "[player.ship.docked, player.ship.status, Math.round(player.ship.position.distanceTo(system.mainStation))]"
            )
        except JSException:
            raise
        except HarnessError:
            state = None  # Busy; try again.
        if state and state[0]:
            break
        if time.time() > deadline:
            raise HarnessError(f"Not docked after {scaled(600):.0f} seconds (status, distance: {state and state[1:]}).")
        if state and (reported is None or time.time() - reported >= 30):
            print(f"[*]   {state[1]}, {state[2]} m from the station")
            reported = time.time()
        time.sleep(1)
    console.evaluate("timeAccelerationFactor = 1")
    print(f"[*] Docked after {time.time() - start:.0f} seconds.")


def run_test(path, test_output, load, addons=None):
    # Only the given OXPs are loaded, not any installed for normal play.
    managed = os.path.join(test_output, "ManagedAddOns")
    os.makedirs(managed, exist_ok=True)
    if addons:
        addons = os.path.abspath(addons)
    else:
        addons = os.path.join(test_output, "AddOns")
        os.makedirs(addons, exist_ok=True)
    oxps = sorted(f for f in os.listdir(addons) if f.endswith((".oxz", ".oxp")))
    print(f"[*] OXPs: {', '.join(oxps) if oxps else 'none'}")
    game = OoliteGame(
        path,
        test_output,
        load=load,
        extra_env={"OO_ADDITIONALADDONSDIRS": addons, "OO_MANAGEDADDONSDIR": managed},
    )
    try:
        console = game.start()

        if load:
            print("[*] Waiting for the saved game to load...")
            console.wait_for("player.ship.docked && player.ship.dockedStation.isMainStation", timeout=180)
            print("[*] Launching...")
            console.evaluate("player.ship.launch(), true")
            console.wait_for('player.ship.status === "STATUS_IN_FLIGHT"', timeout=120)
            # Let a few frames of flight run.
            time.sleep(scaled(5))
        else:
            # Allow time for engine state transition
            time.sleep(5)

        take_snapshot(console)

        if load:
            fire_missile(console)
            dock(console)
            take_snapshot(console)
        game.quit()
    except HarnessError as e:
        print(f"[!] Failure: {e}")
        return False
    finally:
        game.stop()

    success = check_snapshots(test_output, 2 if load else 1)

    problems = game.check_log()
    for problem in problems:
        print(f"[!] Failure: {problem}")
    if game.console.exceptions:
        print(f"[!] Failure: the console reported {len(game.console.exceptions)} exception(s).")
        success = False
    return success and not problems


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Oolite Automation Tester")
    parser.add_argument("--path", default="./", help="Path to the Oolite directory or binary (default: ./)")
    parser.add_argument("--test_output", default="./test_output", help="Path to test output (default: ./test_output)")
    parser.add_argument("--load", help="Saved game to start from (for example Resources/Scenarios/oolite-standard.oolite-save)")
    parser.add_argument("--addons", help="Directory of OXPs/OXZs to load (see fetch_oxps.py)")
    args = parser.parse_args()

    success = False
    try:
        success = run_test(args.path, os.path.abspath(args.test_output), args.load, args.addons)
    except Exception as e:
        print(f"[!] Critical Error: {e!r}")
    if success:
        print("[+] Success")
    sys.exit(0 if success else 1)
