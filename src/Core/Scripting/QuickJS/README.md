# QuickJS-ng scripting engine

This directory is a port of Oolite's JavaScript layer (`src/Core/Scripting`)
from SpiderMonkey 1.8.5 to [QuickJS-ng](https://github.com/quickjs-ng/quickjs)
v0.17.0. See issue #580.

## Building

```
meson setup build/qjs --native-file clang.ini -Djs_engine=quickjs
meson compile -C build/qjs
```

`js_engine` defaults to `spidermonkey`, which builds exactly as before. With
`quickjs`, the files here replace the SpiderMonkey files of the same name in
the parent directory (this directory comes first on the include path), and
QuickJS-ng is built from source as a meson subproject
(`subprojects/quickjs-ng.wrap`) unless a system `quickjs-ng` is found. No
SpiderMonkey headers or libraries are needed.

Files that don't use a JavaScript engine API (`OOScript.m`, `OOPListScript.m`,
`OOScriptTimer.m`, `OOLegacyScriptWhitelist.m`) are shared by both engines.
Game code outside `src/Core/Scripting` builds with either engine, using the
engine-neutral names `OOJSVal`, `OOJSPropID`, `OOJSFreeValue()` etc. and
`#if OOJS_QUICKJS` for engine-specific declarations.

## Status

The game builds, boots, loads saved games, launches and flies with QuickJS.
The parity probe (below) gives the same results as SpiderMonkey apart from
the differences listed below, and in debug builds no JavaScript objects are
left alive when the engine resets or shuts down.

Not yet done:

- JavaScript profiling (`OOJS_PROFILE`) and stack dumps with local variables:
  QuickJS has no function-call hooks or frame inspection API.
- The compiled-script cache: SpiderMonkey's XDR bytecode cache is not used.
  QuickJS bytecode (`JS_WriteObject()`) could be cached the same way, under a
  different cache name.
- Windows builds are untested. Linux (amd64) and macOS (arm64, the
  `macos-arm64-port` branch) build and pass the parity probe.

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
  script rather than global.
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
  (`script.javaScript.init.unpatchedEngine`) is logged if Oolite is linked
  against an unpatched system QuickJS-ng. An upstream option to replace the
  patch has been requested (quickjs-ng/quickjs#1837).
- The time limiter uses QuickJS's interrupt handler; error locations come from
  the exception's stack.

## Testing

- `tools/js-parity`: runs the game headless (Xvfb) with a probe OXP and
  compares what scripts see with a SpiderMonkey baseline. See `run_probe.sh`.
  Accepted differences are listed in `tools/js-parity/expected-differences.txt`.
- `poc/`: a standalone harness for the engine core, Vector3D, Quaternion and
  script wrapping (`-Dquickjs_poc=true`).
- Debug QuickJS builds log `script.javaScript.reset.liveObjects` after every
  context teardown; anything other than zero is a reference counting bug.

## Known behaviour differences

- Debug console (`src/Core/Debug/QuickJS/OOJSConsole.m`): `pedanticMode` is
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
