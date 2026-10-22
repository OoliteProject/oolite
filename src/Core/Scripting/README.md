# JavaScript engine

Oolite's JavaScript layer uses [QuickJS-ng](https://github.com/quickjs-ng/quickjs)
v0.17.0. Up to 1.92 it used SpiderMonkey 1.8.5; the port is issue #580, and
this file describes how existing OXP scripts are kept working.

## Building

QuickJS-ng is built from source as a Meson subproject
(`subprojects/quickjs-ng.wrap`), with Oolite's patch from
`subprojects/packagefiles/quickjs-ng/` applied. The bundled copy is always
used, even if a system `quickjs-ng` is installed (`force_fallback_for` in the
top-level `meson.build`), because an unpatched build changes behaviour OXPs rely
on. The flatpak manifest provides the same source and patch, since
flatpak-builder has no network access; update both when changing the version.

Game code uses the engine-neutral names `OOJSVal`, `OOJSPropID`,
`OOJSFreeValue()` etc. from the SpiderMonkey to QuickJS transition.

## Not yet done

- Stack dumps with local variables: QuickJS has no frame inspection API.
  Stack dumps (`dumpStackForErrors` and friends) list the call stack with
  function names, files and lines, but not `this` or local variables.

## Conventions

The comment at the top of `OOJavaScriptEngine.h` is the reference. In short:

- QuickJS values are reference counted. `JSValueConst` parameters are
  borrowed; every `JSValue` you are given is owned and must be freed or handed
  on. `-oo_jsValueInContext:`, `OOJSValueFromNativeObject()` and `OOJSSTR()`
  return owned values.
- Natives are `static JSValue F(OOJS_NATIVE_ARGS)` and fail with
  `return OOJSNativeFailure(context);`, which keeps SpiderMonkey's behaviour
  of silently stopping the script when no error was reported.
- Property callbacks switch on `magic` (the old tinyid).
- `JS_ValueToInt32()` becomes `OOJSValueToInt32()` (it rounds and rejects NaN,
  unlike QuickJS's `JS_ToInt32()`).
- There is one runtime per process; `-reset` replaces the context. Anything
  holding a `JSValue` releases it on `kOOJavaScriptEngineWillResetNotification`.

Behaviour that needed emulating, all in the engine core:

- **Scope chain.** SpiderMonkey put each script's object at the head of its
  scope chain, so bare names resolve to script properties. Scripts are wrapped
  in `with(this){(function(){ ... }).call(this)}` (`OOJSWrapScriptSource()`);
  strict mode and line numbers are unaffected. Top-level `var`s are local to the
  script rather than global. One consequence: in a ship, AI, equipment or
  other per-entity script, SpiderMonkey's global top-level `var`s were shared
  by every instance of the script, whereas now each instance has its own
  (`tests/js/flight/50-compat-setup.js` checks both).
- **Own properties.** SpiderMonkey reported a prototype's accessor properties
  as own properties of instances, so `JSON.stringify(vector)` and
  `Object.keys(ship)` see them (`OOJSClasses.m`).
- **`toSource()` / `uneval()`** are provided by
  `Resources/Scripts/oolite-quickjs-compat.js`.
- **`const`.** In SpiderMonkey 1.8.5, `const` was function-scoped and usable
  before its declaration, and a few OXPs rely on that. Before compiling, every
  script's `const` keywords are replaced with `var` (same length, so positions
  are unchanged) by `__ooliteRewriteLegacyConst()` in the compatibility script;
  only the read-only check is lost. The rewriter was checked against acorn's
  tokenizer on 488 OXP scripts: it changed exactly the `const` keywords.
- **Properties on primitives.** SpiderMonkey 1.8.5 silently ignored
  `"str".foo = 1` even in strict code (Route Planner relies on this); QuickJS
  throws. QuickJS-ng is patched to match
  (`subprojects/packagefiles/quickjs-ng/`), and a warning
  (`script.javaScript.init.unpatchedEngine`) is logged if Oolite is somehow
  linked against an unpatched QuickJS-ng. An upstream option to replace the
  patch has been requested (quickjs-ng/quickjs#1837).
- **Profiling.** In debug builds `OOJS_PROFILE` is on, as with SpiderMonkey:
  natives bracketed by `OOJS_NATIVE_ENTER`/`OOJS_PROFILE_ENTER` are timed, and
  the debug console's `profile()`, `getProfile()` and `trace()` work. As in
  SpiderMonkey builds without `MOZ_TRACE_JSCALLS` (the usual case), only
  natives are profiled; other time is reported as JavaScript time.
- The time limiter uses QuickJS's interrupt handler; error locations come from
  the exception's stack.

## Opting out of the emulation

A script whose directive prologue includes `"use oolite modern"` runs without
the scope chain and `const` emulation above. It is compiled as a plain
function called with the script object as `this`. `tools/oxp-upgrade` rewrites
OXP scripts so that they don't need the emulation, and adds the directive; its
README explains what changes and why. Marked scripts are logged under
`script.javaScript.load.modern` (off by default). The other compatibility
measures (own properties, `toSource()`/`uneval()` and the primitive property
patch) apply to every script.

The emulation is intended to stay until OXPs have had time to upgrade; the
proposed timeline is in the tool's README.

## Compiled-script cache

As with SpiderMonkey's XDR cache, compiled scripts are kept in the data cache
(OOCacheManager), keyed by path, in a separate cache named "compiled QuickJS
scripts". Entries hold `JS_WriteObject()` bytecode, plus a hash of the exact
text that was compiled (after the `const` rewrite and wrapping), the QuickJS
version and a format number (`kCompiledScriptFormat` in `OOJSScript.m`). An
entry is only used if all three match, so editing a script recompiles it even
when the data cache is otherwise up to date. As before, the whole data cache is
cleared when the Oolite version or the search paths change.

Because `JS_EvalFunction()` runs compiled code with the global object as
`this`, the wrapped script is compiled as a function expression and then called
with the script object as `this`. The prefix is on the first line, so line
numbers don't change. Cache activity is logged under `script.javaScript.cache`
(off by default).

## Testing

- `tools/js-parity`: runs the game with a probe OXP that flies through the
  main game states, and compares what scripts see with SpiderMonkey baselines
  recorded before SpiderMonkey was removed. See `tools/js-parity/README.md`.
  Accepted differences are listed in `tools/js-parity/expected-differences.txt`.
- `poc/`: a standalone harness for the engine core, Vector3D, Quaternion and
  script wrapping (`-Dquickjs_poc=true`, which `./mk.sh` sets for `dev` and
  `debug` builds; `./mk.sh test` runs it). It has its own cut-down engine core
  and script loader, so the compatibility behaviour of the real ones is
  tested in the game instead (`tests/js`, with the scripts in `tests/oxp`).
- Debug builds log `script.javaScript.reset.liveObjects` after every
  context teardown; anything other than zero is a reference counting bug.

## Known behaviour differences from SpiderMonkey 1.8.5

- Debug console (`src/Core/Debug/OOJSConsole.m`): `pedanticMode` is
  remembered but has no effect, `dumpNamedRoots()` is gone, `dumpHeap()`
  writes QuickJS's memory usage summary, and console error reports have no
  "Error" or "strict mode" variants (QuickJS reports every error as an
  exception).

- Assigning to a read-only property in strict code throws `TypeError: no setter
  for property` (SpiderMonkey quoted the expression).
- `for..in` lists integer-like keys first, in ascending order, as the current
  ECMAScript specification requires.
- `Function.prototype.toString()`/`toSource()` return the original source text,
  not SpiderMonkey's decompiled text.
- `oolite.jsVersion` is still 185, but `oolite.jsVersionString` names
  QuickJS-ng.
- Exception log message classes are named after the error type
  (`script.javaScript.exception.ReferenceError`) rather than SpiderMonkey's
  error numbers.
- `SoundFromJSValue()` now resumes the script time limiter on every path; the
  SpiderMonkey version left it paused in one case, so a script could run
  without a time limit after it.
- Property reads on stale Station and Dock references stop the script silently
  (as in SpiderMonkey, where this was an unintended consequence of the code),
  whereas stale Ship references return `undefined`.
