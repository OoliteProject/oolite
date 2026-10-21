"""
Smoke test: starts Oolite, optionally from a saved game, and checks that it
renders and shuts down cleanly.

With --load, the game starts docked from that save; the test then launches
the player into space and takes the snapshot there, which runs the world
scripts, the populator and the ship AIs. In every case the test fails if the
log shows a JavaScript exception or error, a script that ran too long, or a
JavaScript runtime that did not pass its shutdown leak check.
"""

import argparse
import os
import sys
import time

from oolite_harness import HarnessError, OoliteGame, scaled

MIN_FILE_SIZE_KB = 100  # Threshold for a valid render


def check_snapshot(test_output):
    snaps = [f for f in os.listdir(test_output) if f.endswith(".png")]
    if not snaps:
        print("[!] Failure: no snapshot was found.")
        return False
    snap_path = os.path.join(test_output, snaps[0])
    file_size_kb = os.path.getsize(snap_path) // 1024
    print(f"[*] Captured {snap_path} ({file_size_kb} KB)")
    if file_size_kb < MIN_FILE_SIZE_KB:
        print(f"[!] Failure: snapshot is too small ({file_size_kb} KB). Likely a black frame.")
        return False
    print("[+] Snapshot passed quality check.")
    return True


def run_test(path, test_output, load):
    game = OoliteGame(path, test_output, load=load)
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

        print("[*] Requesting snapshot...")
        console.evaluate("takeSnapShot()")
        # The snapshot is written on the next frame.
        time.sleep(scaled(2))
        game.quit()
    except HarnessError as e:
        print(f"[!] Failure: {e}")
        return False
    finally:
        game.stop()

    success = check_snapshot(test_output)

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
    args = parser.parse_args()

    success = False
    try:
        success = run_test(args.path, os.path.abspath(args.test_output), args.load)
    except Exception as e:
        print(f"[!] Critical Error: {e!r}")
    if success:
        print("[+] Success")
    sys.exit(0 if success else 1)
