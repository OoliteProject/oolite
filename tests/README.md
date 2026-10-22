# Tests

`./mk.sh test <build type>` (any build type except `deployment`, which has no
debug console) runs three stages against `build/meson_<build type>/oolite.app`,
or against `$OOLITE_TEST_APP` if that is set:

1. **Smoke test** (`launch_snapshot.py`): loads the standard starting game with
   the OXPs listed in `test-oxps.txt`, launches into space and takes a
   snapshot, fires a missile at an asteroid and checks that one fewer missile
   remains, docks with the docking computer and takes a second snapshot.
2. **JavaScript tests** (`run_js_tests.py`, tests in `js/`): runs assertion
   tests inside the game, first docked (`js/docked`) and then in flight
   (`js/flight`), with no OXPs installed.
3. **Parity probe** (`tools/js-parity`): flies through hyperspace, docking and
   a galactic jump, and compares what scripts see with the stored output for
   this platform (Linux x86-64 and macOS arm64; elsewhere it only checks for
   exceptions). See `tools/js-parity/README.md`.

Every stage fails if the game logs a JavaScript exception or error, kills a
script for running too long, or (in builds with debug support) shuts down
with leaked JavaScript objects.

## How it works

Builds with debug support connect to a debug console on TCP port 8563 at
startup. `oolite_harness.py` plays the console: it starts the game, accepts
the connection, sends JavaScript to be evaluated and reads the results. It
also isolates the game from OXPs installed for normal play (through
`OO_ADDITIONALADDONSDIRS` and `OO_MANAGEDADDONSDIR`), writes the log and
snapshots to the test output directory, and quits with `quitGame()`, which
takes effect once the calling script has returned so that the JavaScript
runtime's leak check runs.

Because the port is fixed, only one game can be tested at a time on a
machine. On slow machines (for example under CPU emulation) set
`OOLITE_TEST_TIMEOUT_SCALE` to multiply every timeout.

## Writing JavaScript tests

Each file in `js/docked` or `js/flight` runs as the body of one function, in
the debug console's script, after `js/prelude.js`:

```js
test("credits can be changed", function ()
{
	var before = player.credits;
	player.credits += 10;
	assertEqual(player.credits, before + 10);
	player.credits = before;
});
```

`prelude.js` provides `assert`, `assertEqual` (structural for arrays, objects,
vectors and quaternions), `assertClose`, `assertThrows`, `assertType` and
`fail`. Tests run synchronously within a frame, so they cannot wait for
events; put a test in the phase whose state it needs, and undo any changes
that later tests could see. Run a subset with `--filter`, for example
`python3 tests/run_js_tests.py --path build/meson_dev/oolite.app --filter galaxy`.

## Test OXPs

`fetch_oxps.py` downloads the OXZs listed in `test-oxps.txt` into
`build/test-oxz-cache` (or `$OOLITE_TEST_OXZ_CACHE`), checking their
SHA-256. CI caches that directory. A download that fails is skipped with a
warning, since the files are hosted on the Oolite wiki, which is sometimes
down; a checksum mismatch fails the test. To change the list, take the
download URL from the add-ons catalogue
(https://addons.oolite.space/api/1.0/overview) and record the file's
`shasum -a 256`.
