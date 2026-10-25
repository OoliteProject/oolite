# Component test tier

Gherkin scenarios driven over the debug-console TCP channel, asserting named, tolerant invariants
about simulated gameplay. Specified in [`docs/phases/0-component-tier.md`](../../../../docs/phases/0-component-tier.md),
decided in [ADR-0018](../../../../docs/decisions/0018-component-test-tier.md). The seam and
exemplar is [S1](../../../../docs/stories/S1-police-kills-pirate.md).

```bash
python3 -m pytest upstream/oolite/tests/component/ -x -q
```

It needs a built game. By default it uses `upstream/oolite/build/meson_test/oolite.app`; override
with `--oolite-app <path>` or `OO_APP_DIR`. Each scenario launches its own game process on its own
free port, so scenarios do not collide and the suite can run per bead.

| Variable | Default | What it does |
|---|---:|---|
| `OO_COMPONENT_TIMEOUT` | `300` | Hard per-scenario timeout in seconds; the game is killed and the scenario fails. |
| `OO_APP_DIR` | the test build | Which `oolite.app` to drive. |

## The step catalogue

**This table is the interface.** A new `.feature` file that uses only these steps is fleet work and
scores 7/7 against S1. Needing a step that is not here is a *new interface*: sizing check 5 fails,
so stop and file a bead rather than adding one inside a conversion story
([ADR-0018](../../../../docs/decisions/0018-component-test-tier.md) §5).

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
position. A scenario that needs an exact float is a golden, not a component test — it belongs in
item 0.4.

**The spawn steps pin the cast.** `I spawn <n> ship(s) with role "<role>"` does not ask `addShips`
for the role: for `police`, `pirate`, `trader` and `escort` it asks for a literal core ship key
(`[viper]`, `[sidewinder]`, `[boa]`, `[sidewinder-escort]`, `ROLE_SHIP_KEY` in
`steps/world_steps.py`), then sets `primaryRole` back to the role. A role spawn is a RANROT draw
between hulls, and the role path also draws a pirate's starting bounty (20-70) across policeAI's
`fineThreshold()` gate, so the same seed gave a different, sometimes non-engageable cast each run
(oo-sjvz; LEARNINGS oo-qwk5, oo-rkm). A spawned pirate's bounty is set to `PIRATE_BOUNTY` (100)
for the same reason. A role with no pinned key falls back to the plain role draw. The step text is
unchanged; add a key here, not a new step, when a new role needs to be deterministic.
Pinning removes the draw, not the fight: a scenario that asserts who survives a long dogfight (S6)
can still lose it, because a real-time fight on a software renderer is not seed-deterministic
(oo-9aq4).

## What this tier deliberately cannot see

- **`energy` is not exposed to JS** (only `energyRechargeRate`, `OOJSShip.m:371`). Assert death and
  survival through `countShipsWithRole` and `isValid`, not health. Do not add a native property.
- **Killer attribution.** `shipDied` / `shipKilledOther` fire, but capturing them needs a script
  object on a ship and therefore a test-only script resource. With exactly two ships spawned, "no
  pirate remains and a police ship survives" already proves the AI engaged, the weapon fired,
  damage landed and the target died.

Asserting only on what is already observable is what keeps this a small seam rather than a
native-API project.

## Files

| File | Role |
|---|---|
| `console.py` | Debug-console client: framing, handshake, `perform`/`evaluate`, parameterised port. **Transport only** — the golden harness (item 0.4) is expected to share it, so keep component-tier vocabulary out. |
| `conftest.py` | `world` fixture: one game per scenario, free port, hard timeout with forced kill. |
| `steps/world_steps.py` | The step library above. |
| `features/*.feature` | The scenarios. Data, not interface. |
| `test_*.py` | One binding module per feature so pytest-bdd collects it. |

## Why readiness is waited for, not slept through

`console.py` pings until the game answers Pong before it sends anything else. The game connects to
the console early in startup but cannot answer until its run loop is dispatching packets, which on
a software renderer is many seconds later. `tests/launch_snapshot.py` originally slept a fixed five
seconds here and, on a slow machine, sent its command before the first frame had ever been drawn —
producing a black screenshot that looked like a rendering fault rather than a race. Do not
reintroduce a fixed sleep.
