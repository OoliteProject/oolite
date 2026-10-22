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
5. launches from the mission screen and makes a galactic jump.

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
- `expected-differences.txt`: accepted differences between SpiderMonkey and
  QuickJS; `compare.sh` ignores them too.

Linux and macOS outputs differ slightly (float formatting in one ship's
collision radius, the station's shipyard and the build version string), so
compare each platform with its own baseline.
