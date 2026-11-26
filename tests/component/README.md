# Component test tier

Gherkin scenarios driven over the debug-console TCP channel, asserting named, tolerant invariants
about simulated gameplay. The seam and exemplar is
[S1](features/s1_police_kills_pirate.feature).

```bash
python3 -m pytest oolite-dev/tests/component/ -x -q
```

It needs a built game. By default it uses `oolite-dev/build/meson_test/oolite.app`; override
with `--oolite-app <path>` or `OO_APP_DIR`. Each scenario launches its own game process on its own
free port, so scenarios do not collide and the suite can run in parallel.

| Variable | Default | What it does |
|---|---:|---|
| `OO_COMPONENT_TIMEOUT` | `300` | Hard per-scenario timeout in seconds; the game is killed and the scenario fails. |
| `OO_APP_DIR` | the test build | Which `oolite.app` to drive. |

## The step catalogue

**This table is the interface.** A new `.feature` file that uses only these steps is fleet work and
scores 7/7 against S1. Needing a step that is not here is a *new interface*: sizing check 5 fails,
so stop and report it rather than adding one inside a conversion story.

| Step | Kind | Notes |
|---|---|---|
| `a universe seeded with <n>` | Given | Launches the game with `OO_RANDOM_SEED=<n>`. Must be first: RANROT is seeded once in `GameController -init`, so the seed cannot change afterwards. |
| `I spawn <n> ship(s) with role "<role>"` | When | `system.addShips`; fails if fewer than `<n>` were added. |
| `I spawn <n> ship(s) with role "<role>" within <km> km` | When | Same, positioned within `<km>` of the first existing ship (or the origin if the system is empty). |
| `the simulation runs for at most <n> ticks` | When | Polls and returns early once every non-`police` spawned role is gone. A tick is one `AI_THINK_INTERVAL` (0.125 s, `src/Core/AI.h:31`), so 900 ticks ≈ 120 AI decisions. |
| `the simulation runs for <n> ticks` | When | Runs the whole budget with no early exit, for scenarios asserting that nothing happened. |
| `no ship with role "<role>" remains` | Then | `system.countShipsWithRole(role) == 0`. |
| `a ship with role "<role>" survives` | Then | `system.countShipsWithRole(role) > 0`. |
| `<n> ships with role "<role>" remain` | Then | Exact count. |
| `no ERROR appears in the log` | Then | Quits the game and greps `Latest.log`. The canary for NaN blowups and scan-class confusion (S7). |

## Writing a scenario that will not flake

Assert **"within N ticks"**, never "at tick N". Assert **"no pirate remains"**, never an exact
position. A scenario that needs an exact float does not belong in this tier.

**The spawn steps pin the cast.** `I spawn <n> ship(s) with role "<role>"` does not ask `addShips`
for the role: for `police`, `pirate`, `trader` and `escort` it asks for a literal core ship key
(`[viper]`, `[sidewinder]`, `[boa]`, `[sidewinder-escort]`, `ROLE_SHIP_KEY` in
`steps/world_steps.py`), then sets `primaryRole` back to the role. A role spawn is a RANROT draw
between hulls, and the role path also draws a pirate's starting bounty (20-70) across policeAI's
`fineThreshold()` gate, so the same seed gave a different, sometimes non-engageable cast each run.
A spawned pirate's bounty is set to `PIRATE_BOUNTY` (100)
for the same reason. A role with no pinned key falls back to the plain role draw. The step text is
unchanged; add a key here, not a new step, when a new role needs to be deterministic.
Pinning removes the draw, not the fight: a scenario that asserts who survives a long dogfight (S6)
can still lose it, because a real-time fight on a software renderer is not seed-deterministic.

## What this tier deliberately cannot see

- **`energy` is not exposed to JS** (only `energyRechargeRate`, `OOJSShip.m:371`). Assert death and
  survival through `countShipsWithRole` and `isValid`, not health. Do not add a native property.
- **Killer attribution.** `shipDied` / `shipKilledOther` fire, but capturing them needs a script
  object on a ship and therefore a test-only script resource. With exactly two ships spawned, "no
  pirate remains and a police ship survives" already proves the AI engaged, the weapon fired,
  damage landed and the target died.

Asserting only on what is already observable is what keeps this a small seam rather than a
native-API project.

## Keyboard steps (T1, the tutorial walkthrough)

Everything above drives the game through JS. `features/t1_tutorial_walkthrough.feature` is about
**player input**, and there is no JS for "the player pressed 2", so these steps press real keys
into the game's window (`keyboard.py`) and read the effect back over the console. It loads the
tutorial's own save, walks lessons 0-9 to the end screen, and checks on the way that `1`-`4` and
`v` change `player.ship.viewDirection`, that `s` stops the ship, that F5-F8 open their screens
and a view key closes them, and that the tutorial's `n` (next) and `b`+`n` (skip lesson)
controls work. The flying challenges (lessons 3-7, 9) are left with that skip.

| Step | Kind | Notes |
|---|---|---|
| `the tutorial is loaded` | Given | `-load`s `Resources/Scenarios/oolite-tutorial.oolite-save` and waits for the welcome mission screen. |
| `I press "<key>"` | When | One real key press. Keys are named in `keyboard.py` `VK_CODES`; add one there. |
| `I advance the tutorial` | When | Holds `n` until `$tutorialStage`/`$tutorialSubstage` move; fails if they do not. |
| `I advance the tutorial to lesson <n> step <m>` | When | Repeats the above until exactly there. |
| `I advance through lesson <n>` | When | Repeats it until lesson `<n>+1` step 0. |
| `I skip to the next lesson` | When | `b` then `n`; fails unless the lesson number goes up by one. |
| `I bring the ship to a stop` | When | Holds `s` until `player.ship.speed` <= 0.1 (lesson 2 will not start otherwise). |
| `the tutorial is at lesson <n> step <m>` | Then | The tutorial script's own counters. |
| `the view is "<VIEW_X>"` | Then | `player.ship.viewDirection`. |
| `the screen is "<GUI_SCREEN_X>"` | Then | `guiScreen`. |
| `the player is in flight` | Then | Not docked and on `GUI_SCREEN_MAIN`; a view key pressed during the launch tunnel is lost. |
| `the tutorial end screen is shown` | Then | `guiScreen` is the mission screen **and** `mission.screenID` is `oolite-tutorial-end` (screenID alone goes stale). |

Why the presses are what they are:

- **`SendInput` by scancode, into the foreground window**, the GUI tier's recipe restated in
  `keyboard.py`: the SDL3 build dispatches by scancode, and synthetic input goes to whichever
  window is focused. The tier runs alone on the desktop, which is what lets it take the
  foreground. **Windows only**, like `test_paused_console_priority.py`.
- **Longer than the GUI tier's 0.15 s.** This tier renders on llvmpipe, which draws 6-9 frames a
  second in the tutorial's flight scenes; the game samples keys once per frame, so a 0.15 s tap
  was lost. Taps are 0.4 s down and 0.4 s up (`OO_COMPONENT_KEY_HOLD` /
  `OO_COMPONENT_KEY_RELEASE`). "Next" is **held until the tutorial moves**, because even 0.4 s
  was lost once under lesson 2's asteroid field. Holding cannot double-advance: the game latches
  `activate_equipment_pressed`.
- **No silent pass.** Every press meant to move the tutorial is checked to have moved it.
  `test_tutorial_steps_offline.py` proves that against a scripted tutorial with no game.

The walkthrough takes about 2.5 minutes, inside the default `OO_COMPONENT_TIMEOUT`.

## Files

| File | Role |
|---|---|
| `console.py` | Debug-console client: framing, handshake, `perform`/`evaluate`, parameterised port. **Transport only** — keep component-tier vocabulary out. |
| `conftest.py` | `world` fixture: one game per scenario, free port, hard timeout with forced kill. |
| `steps/world_steps.py` | The step library above. |
| `steps/tutorial_steps.py` | The keyboard steps (T1). |
| `keyboard.py` | Real key presses into the game window (`SendInput`), Windows only. Transport-level, like `console.py`: no Gherkin. |
| `features/*.feature` | The scenarios. Data, not interface. |
| `test_*.py` | One binding module per feature so pytest-bdd collects it. |

## Why readiness is waited for, not slept through

`console.py` pings until the game answers Pong before it sends anything else. The game connects to
the console early in startup but cannot answer until its run loop is dispatching packets, which on
a software renderer is many seconds later. `tests/launch_snapshot.py` originally slept a fixed five
seconds here and, on a slow machine, sent its command before the first frame had ever been drawn —
producing a black screenshot that looked like a rendering fault rather than a race. Do not
reintroduce a fixed sleep.
