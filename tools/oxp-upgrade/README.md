# oxp-upgrade

Upgrades OXP scripts so that Oolite runs them without its emulation of
SpiderMonkey 1.8.5 scoping. Upgraded OXPs still work in Oolite 1.92 and
earlier.

## Why

Up to 1.92, Oolite used SpiderMonkey 1.8.5. It had two behaviours that
current JavaScript engines don't have, and many OXPs rely on them:

- **The script object was on the scope chain.** A script could refer to its
  own properties by bare name: `$count++` meant `this.$count++`, and
  `ship.name` in a ship script meant `this.ship.name`.
- **`const` worked like `var`.** It was function-scoped and could be used
  before its declaration.

Oolite now uses QuickJS-ng, and emulates both for every script. It wraps each
script in `with (this) { ... }` and replaces `const` with `var` before
compiling. This keeps every existing OXP working, but it has costs:

- **Speed.** `with` slows down every global and script property lookup.
  In a QuickJS micro-benchmark, a loop reading `player`, `system` and `Math`
  ran 1.8 times faster without it. Reading a script property as `this.$k`
  ran 2.3 times faster than the bare `$k`.
- **Language features.** Scripts can't have real block-scoped `const`.
- **Maintenance.** Oolite has to keep the emulation.

A script that starts with the directive `"use oolite modern";` tells Oolite it
doesn't need the emulation. Oolite then runs it as standard JavaScript: no
`with`, and no `const` rewrite. Older versions of Oolite ignore the directive.
This tool makes the changes a script needs and adds the directive.

## Usage

Needs [Node.js](https://nodejs.org/) 18 or later.

```
cd tools/oxp-upgrade
npm ci
node oxp-upgrade.js path/to/MyOXP.oxz
```

Each argument can be an `.oxz` file, an `.oxp` folder or a single `.js` file.
The upgraded copy is written next to the original, as `MyOXP.upgraded.oxz`.
Nothing is changed in place unless you ask.

| Option | |
|---|---|
| `--check` | Report only; write nothing. |
| `--in-place` | Overwrite the originals. |
| `--out=DIR` | Write upgraded copies to `DIR`. |
| `--world` | Treat single `.js` files as world scripts (see below). |
| `--json` | Print the report as JSON. |
| `--quiet` | Only list scripts that weren't upgraded. |

Running the tool on an already upgraded OXP changes nothing.

After upgrading an OXP, test it, then raise its version number in
`manifest.plist` before publishing it. The tool doesn't change the manifest.

## What it changes

All changes are made on existing lines, so line numbers in error messages stay
the same. Comments, formatting, byte order marks and line endings are kept.

- **`const` becomes `var`.** This is exactly what Oolite does for unmarked
  scripts, so the script behaves the same. If you no longer need to support
  Oolite 1.92, you can change them back to `const` or `let` where block
  scoping is what you want.
- **Bare references to script properties get `this.`.** A bare name counts
  as a script property reference when it is assigned or read as `this.name`
  somewhere in the script, or is one of the properties Oolite sets on scripts,
  such as `ship` and `equipmentKey`.

  ```js
  this.shipDied = function () { $count++; log(ship.name); };
  // becomes
  this.shipDied = function () { this.$count++; log(this.ship.name); };
  ```

- **Inside nested functions** (callbacks to `filter`, `forEach` and so on),
  `this` isn't the script. There the tool adds `var $script = this;` at the
  start of the enclosing method and uses `$script.name`:

  ```js
  this.startUp = function () {
      return list.filter(function (s) { return s.bounty > $limit; });
  };
  // becomes
  this.startUp = function () { var $script = this;
      return list.filter(function (s) { return s.bounty > $script.$limit; });
  };
  ```

- **The directive `"use oolite modern";`** is added after `"use strict";`, or
  at the start of the script if it has no directives.

The tool only uses `this.name` where `this` is the script: in top-level code,
in methods defined as `this.name = function`, and in functions run with
`.call(this)`. A method stops counting as one where it is passed around as a
value, for example `addFrameCallback(this.$frame)`, because it is then called
with a different `this`. Passing it to `new Timer(this, ...)`,
`mission.runScreen()` or `system.filteredEntities(this, ...)`, or using
`.bind(this)`, is fine: Oolite calls those with the script as `this`. The tool
also checks the other scripts in the OXP for uses such as
`worldScripts.myScript.$method`.

### World scripts and per-entity scripts

World scripts (`Config/script.js` and the scripts listed in
`Config/world-scripts.plist`) have one instance. Ship, AI, equipment, character
and effect scripts have one instance per ship or item. In those scripts the
tool can't add a single top-level `var $script = this;`, because SpiderMonkey
1.8.5 shares top-level variables between the instances. So if such a script
refers to its properties from a function that isn't a method, the tool leaves
the script unchanged and says where. Change those references by hand, for
example by passing the script in as a parameter. When you upgrade a single
`.js` file, the tool assumes it is a per-entity script unless you give
`--world`.

## Scripts it leaves alone

A script is left unchanged, with the reasons listed, if it:

- uses `with`, `eval()` or `Function()`;
- creates script properties with computed names (`this[key] = ...`),
  `Object.assign(this, ...)` or `Object.defineProperties(this, ...)`, so its
  properties can't all be found;
- uses a script property in a shorthand property (`{ $a }`) or a
  destructuring pattern;
- is a per-entity script that refers to its properties from a function that
  isn't a method (see above);
- doesn't parse.

Unmarked scripts keep working as they always have.

## Things to check by hand

The report also lists:

- **Names that are neither globals nor properties of the script.** Most are
  undeclared variables, which behave the same either way. But if another
  script sets the property on this script (`worldScripts.mine.$x = 1`) and
  this script reads it as a bare `$x`, change it to `this.$x`.
- **`toSource()` and `uneval()`.** These are SpiderMonkey extensions. They
  still work in Oolite, but `JSON.stringify()` is the standard alternative.

The tool can't detect scripts that add properties to primitive values, such as
`"text".flag = true`. SpiderMonkey 1.8.5 ignored this, even in strict mode,
and Oolite's QuickJS-ng is patched to do the same for all scripts. If your
script does this, fix it by hand. It does nothing anyway.

## Results on the add-on catalogue

On the 189 OXZs in the catalogue (467 scripts), the tool upgraded 457 scripts:

- **Marker only.** 410 of them needed nothing else.
- **`const`.** 19 had `const` declarations.
- **Rewrites.** 33 scripts had bare script property references, 153 in all, and
  only one needed an alias.
- **Left unchanged.** Ten scripts:
  - 5 use `eval()`
  - 2 use computed script property names
  - 3 don't parse in any engine

Nineteen of these OXZs, upgraded, were run in Oolite with QuickJS-ng and with
SpiderMonkey 1.8.5. They gave the same errors and warnings as the originals on
both engines.

## Proposed timeline

Following the discussion on the QuickJS-ng pull request, the proposal is:

1. **Now:** unmarked scripts keep working unchanged. OXP authors can upgrade
   with this tool when it suits them.
2. **A release or two later:** Oolite logs a deprecation warning for unmarked
   scripts.
3. **Later still:** the emulation is removed, and unmarked scripts run as
   standard JavaScript.

## Tests

```
npm test
```
