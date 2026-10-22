# JavaScript parity probe

The probe OXP (`oojs_probe.oxp`) logs a deterministic record of what scripts
can see and do, so that the output of one build can be diffed against another.
It was written to check the QuickJS-ng port against SpiderMonkey 1.8.5, and
now also guards against regressions.

Starting docked at Lave from the standard scenario, the probe:

1. lists every property of the player ship, the station, a spawned ship, the
   system and the player, and checks object behaviour (own properties, JSON,
   `toSource()`, stale entities, legacy `const`, and so on);
2. launches and flies for a few seconds, then exercises vector and quaternion
   maths, system and route information, and ship methods on a spawned ship;
3. jumps to the neighbouring system with the most stable government;
4. docks (`dockPlayer()`), then uses the market, cargo manifest, equipment,
   contracts, mission text and a mission screen;
5. launches from the mission screen and makes a galactic jump;
6. sweeps every script method (`$sweepNames`, from the method tables in
   `src/Core/Scripting`): each is called with a wrong `this`, on a removed
   ship (for Entity and Ship methods), and with bad arguments (none,
   `undefined`, `null`, a string, -1, NaN, an object, an array) on a
   throwaway object, and one line per method records what each call did.
   Methods that act on the player, the system or the mission without
   checking `this`, and calls that would derail the run, are skipped
   (`$sweepSkip`); entity descriptions, numbers and addresses in messages
   are normalised so that the lines are stable between runs.

From step 2 on it also records the world-script events that its own actions
cause, with their arguments. When it has finished it logs
`ready for external quit`.

## Running it

```bash
tools/js-parity/run_probe.py <oolite.app or binary> <output file> [--check-leaks]
tools/js-parity/compare.sh <expected> <actual>
```

`run_probe.py` drives the game through the debug console (see
`tests/oolite_harness.py`), so the build must include debug support (any
build type except deployment). It works on Linux (SDL offscreen video with
Mesa's software OpenGL; no X server needed), macOS and Windows. AddOns are
isolated through `OO_ADDITIONALADDONSDIRS` and `OO_MANAGEDADDONSDIR`, so
OXPs you have installed are not loaded. `--extra-addons DIR` (or
`PROBE_EXTRA_ADDONS`) installs further OXPs alongside the probe, to compare
their errors and warnings between builds. `--check-leaks` fails the run
unless the JavaScript runtime shut down with no leaked objects.

The console port is fixed (8563), so only one game can be driven at a time on
a machine. On slow machines set `OOLITE_TEST_TIMEOUT_SCALE` (for example
`10` under CPU emulation).

## Checking OXPs

`oxp_corpus.py <oolite.app or binary>` runs the probe with the 19 OXPs in
`oxp-corpus.txt` installed (popular, script-heavy OXPs and the libraries
they need, pinned by SHA-256), and compares the script problems they cause
(exceptions, errors, warnings and time-limit stops; the probe's own lines
are left out) with `oxp-corpus-known.txt`. A new exception, error or warning
fails the run; a new time-limit stop is only a warning, since it depends on
the machine's speed. Known problems that no longer occur are listed. After an
intended change, or a change to the list, regenerate the known problems with
`--update` (which needs every OXP to be available).

The OXPs are downloaded into `build/oxp-corpus-cache`. One that cannot be
downloaded, or whose file has changed (OXPs on the wiki are sometimes
replaced in place), is skipped with a warning; if none can be downloaded,
nothing is checked and the run says so rather than failing.

`.github/workflows/oxp_corpus.yaml` runs it nightly on macOS arm64 (where the
known list was recorded), on demand, and on pushes that change these files.
Scheduled and on-demand runs only happen once the workflow is on the
repository's default branch.

## Files

- `baseline-spidermonkey.txt` (Linux amd64, from upstream master before the
  port, 7d440905) and `baseline-spidermonkey-macos.txt` (macOS arm64, from a
  SpiderMonkey build of the `quickjs-poc` branch): the probe's output from
  SpiderMonkey 1.8.5. Once SpiderMonkey builds are gone these cannot be
  regenerated, and new probe checks can only be compared with QuickJS output.
- `baseline-quickjs.txt` (Linux amd64) and `baseline-quickjs-macos.txt`
  (macOS arm64): the current QuickJS output, for regression testing.
  Regenerate them when a change to the probe or to the game is intended to
  change the output, and explain the difference in the commit.
- `noise.txt`: lines that differ between two runs of the same build (random
  equipment, traffic, prices); `compare.sh` ignores them.
- `oxp-corpus.txt` and `oxp-corpus-known.txt`: the OXPs `oxp_corpus.py`
  installs, and the problems they are known to cause.
- `expected-differences.txt`: accepted differences between SpiderMonkey and
  QuickJS, each with its reason. `compare.sh` ignores lines containing them
  only when one of the files it compares has `spidermonkey` in its name, so
  QuickJS-to-QuickJS comparisons still check those lines.

Linux and macOS outputs differ slightly (float formatting in one ship's
collision radius, the station's shipyard and the build version string), so
compare each platform with its own baseline.

The sweep found two crashes in SpiderMonkey debug builds that QuickJS does
not have, and which the probe therefore avoids: `Ship.setCrew()` with bad
arguments (a segmentation fault), and most Station methods called with a
wrong `this` (an assertion). `tests/js` checks `setCrew()` under QuickJS, and
the Station sweep runs only under QuickJS.
