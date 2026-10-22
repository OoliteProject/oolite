# Tests

`./mk.sh test <build type>` (any build type except `deployment`, which has no
debug console) runs these stages against `build/meson_<build type>/oolite.app`,
or against `$OOLITE_TEST_APP` if that is set:

0. **Engine unit tests** (`meson test quickjs-poc`): in builds configured with
   `-Dquickjs_poc=true` (`./mk.sh` does that for `dev` and `debug` builds, on
   Linux and macOS), a standalone harness checks the Vector3D and Quaternion
   bindings, script wrapping, error reporting, the time limiter and the leak
   check, without starting the game. See `src/Core/Scripting/poc/meson.build`.
1. **Smoke test** (`launch_snapshot.py`): loads the standard starting game with
   the OXPs listed in `test-oxps.txt`, launches into space and takes a
   snapshot, fires a missile at an asteroid and checks that one fewer missile
   remains, docks with the docking computer and takes a second snapshot.
2. **JavaScript tests** (`run_js_tests.py`, tests in `js/`): runs assertion
   tests inside the game as it moves through five phases (see below), with
   only the test OXPs in `oxp/` installed: an event recorder, and scripts
   written for SpiderMonkey (and one with `"use oolite modern"`) whose
   behaviour the compat tests check. It also reports how the compiled-script
   cache was used, and fails if a cached script could not be read back.
3. **Parity probe** (`tools/js-parity`): flies through hyperspace, docking and
   a galactic jump, and compares what scripts see with the stored output for
   this platform (Linux x86-64 and macOS arm64; elsewhere it only checks for
   exceptions). See `tools/js-parity/README.md`.

Not part of `./mk.sh test`, because it is slower and depends on downloads:
`tools/js-parity/oxp_corpus.py` runs the probe with 19 popular OXPs and fails
on script problems they cause that are not already known. CI runs it nightly
(see `tools/js-parity/README.md`).

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

The JavaScript tests run in five phases, each in its own directory under
`js/`; `run_js_tests.py` moves the game from one to the next:

| Phase | State |
|---|---|
| `docked` | Docked at Lave, as the standard scenario starts. |
| `flight` | Launched; in flight near the station. |
| `arrived` | After 10 seconds of flight, a hyperspace jump to the neighbouring system with the most stable government. |
| `redocked` | Docked there with `dockPlayer()`. |
| `galactic` | Launched again, and after a galactic jump. |

`oxp/oolite-test-recorder.oxp` records every world-script event, filed under
the phase that the runner was moving to when it happened. Tests can check
them with `phaseEvents()`, `eventNames()`, `eventArgs(name)` and
`assertEventOrder([names])`. `$state` persists from one test file and phase
to the next, so a test can start something (a timer, a frame callback) in
one phase and check what it did in the next.

Each test file runs as the body of one function, in the debug console's
script, after `js/prelude.js`:

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
`fail`. A test that causes a log message on purpose (a time-limit kill, say)
declares it with a line `// expect-log: <regular expression>` in its file.
Tests run synchronously within a frame, so they cannot wait for
events; put a test in the phase whose state it needs (or check in a later
phase), and undo any changes that later tests could see. Run a subset with `--filter`, for example
`python3 tests/run_js_tests.py --path build/meson_dev/oolite.app --filter galaxy`.

## Test OXPs

`fetch_oxps.py` downloads the OXZs listed in `test-oxps.txt` into
`build/test-oxz-cache` (or `$OOLITE_TEST_OXZ_CACHE`), checking their
SHA-256. CI caches that directory once all of them have been downloaded. A
download that fails is skipped with a warning (in CI, a warning on the run),
since the files are hosted on the Oolite wiki, which is sometimes down; a
checksum mismatch fails the test. When a CI test step fails, the test output
(logs, snapshots and probe output) is uploaded as an artifact. To change the list, take the
download URL from the add-ons catalogue
(https://addons.oolite.space/api/1.0/overview) and record the file's
`shasum -a 256`.
