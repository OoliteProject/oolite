# Building Oolite for macOS (Apple Silicon)

This guide describes the native macOS ARM64 port of Oolite: how to configure, build,
run and debug it on Apple Silicon Macs. It reflects what the `macos-port` branch was
developed and verified with: macOS 26.5 (Tahoe), Xcode 26.6 (Apple clang 21), an M1 Max.

Supported configuration:

- Apple Silicon (ARM64) Mac
- macOS 26 (Tahoe) or newer — the generated app bundle declares
  `LSMinimumSystemVersion 26.0`
- Xcode 26.x with the macOS 26 SDK

Intel (x86_64) Macs are not covered by this port; an x86_64 build is a documented
near-term follow-up.

## Prerequisites

1. Xcode 26.x (Mac App Store or developer.apple.com), including the macOS 26 SDK.
   Confirm with `xcode-select -p` that it is the selected developer directory.
2. Homebrew (<https://brew.sh>) and the build dependencies:

```bash
brew install meson ninja pkg-config libpng openal-soft libvorbis nspr zlib sdl3 espeak-ng
```

Versions the port was verified against: meson 1.12, ninja 1.13, SDL3 3.4, OpenAL Soft
1.25, libpng 1.6, libvorbis 1.3, nspr 4.40, zlib 1.3, espeak-ng 1.52 (`libogg` and
`pcaudiolib` arrive as transitive dependencies).

`espeak-ng` is required, not optional: the speech-synthesis build option defaults to on,
and Oolite links espeak-ng for its spoken messages.

## JavaScript engine artifact

Oolite embeds Mozilla JavaScript 1.8.5 (js185). The macOS build consumes a prebuilt
static arm64 artifact produced by the mozillajs-macos project, mirroring the
[mozillajs-linux](https://github.com/OoliteProject/mozillajs-linux) dependency pattern:
oolite never vendors JavaScript patches, and building oolite itself never needs Python.

- Source pin: `OoliteProject/spidermonkey-ff4` commit
  `c463e95ea5d1d780301e7f3792783771381125f0`, patched for darwin/arm64.
- Stage the artifact into the gitignored `build/mozilla_js/` directory so it contains:

```text
build/mozilla_js/
    include/jsapi.h     (plus the rest of the dist/include/js headers)
    lib/libjs_static.a
```

Note the library name: artifact tarballs ship `lib/js_static.a`, while the build scan
requires `lib/libjs_static.a` — rename at stage time.

`python2` is needed only if you rebuild the js185 artifact yourself (js185's configure
hard-requires Python 2.7); building oolite needs no Python at all.

The meson scan's failure message references `ShellScripts/Darwin/install_mozilla_js.sh`,
a fetch script provided by the CI task of this port series; manual staging as above is
the currently documented path.

## Configure and build

### The pkg_config_path trap — read before your first build

Meson resolves Homebrew libraries through its sticky `pkg_config_path` build option, not
the ambient `PKG_CONFIG_PATH` environment variable; on meson 1.x the environment variable
alone is ignored. On a fresh setup without the option, dependency resolution silently
falls back to Apple's deprecated `/System/Library/Frameworks/OpenAL` (and the system
zlib), because openal-soft is keg-only and its `.pc` file is not on pkg-config's default
search path. The build succeeds and the game runs — the mistake is only visible in
`otool -L`.

Pass the option on the **first** setup. It is then sticky in the build directory, so
later rebuilds need nothing:

```bash
export PKG_CONFIG_PATH="$(brew --prefix)/lib/pkgconfig:$(brew --prefix openal-soft)/lib/pkgconfig:$(brew --prefix nspr)/lib/pkgconfig:$(brew --prefix zlib)/lib/pkgconfig:$(brew --prefix sdl3)/lib/pkgconfig"
./mk.sh build dev --setup-flags="-Dpkg_config_path=$PKG_CONFIG_PATH"
```

If a build directory was already configured without the option, a plain reconfigure does
not re-resolve dependencies (meson caches them) — clear the cache or start over:

```bash
meson setup --clearcache --reconfigure build/meson_dev -Dpkg_config_path="$PKG_CONFIG_PATH"
# or: ./mk.sh clean dev, then set up again with the flag
```

Two ways to verify: `./mk.sh build dev` prints `pkg_config_path` under "User defined
options", and the linked binary must reference Homebrew's OpenAL Soft (bundled as
`@rpath/libopenal.1.dylib`), never `/System/Library/Frameworks/OpenAL`.

### Building

```bash
./mk.sh build dev
```

This runs meson setup and compile (the `clang-darwin.ini` native file is selected
automatically on macOS) and then assembles `build/meson_dev/oolite.app`:

- full `Info.plist` (bundle identifier `org.oolite.oolite`, version derived from git,
  `LSMinimumSystemVersion 26.0`) and the Oolite icon
- every Homebrew dylib copied into `Contents/Frameworks` with `@rpath` install names;
  all Homebrew rpaths are stripped from the binary, leaving a single
  `@executable_path/../Frameworks` — the bundle loads nothing from `/opt/homebrew` at
  runtime
- `espeak-ng-data` copied into `Contents/Resources`
- ad-hoc code signature: each bundled dylib, the main binary, then the sealed bundle,
  verified with `codesign --verify --deep --strict` as an in-build gate (ad-hoc signing
  is an arm64 requirement; see [Distribution and signing](#distribution-and-signing))

The other build flavors work as described in the main README (`deployment`, `test`,
`dev`, `debug`). The `debug` flavor compiles with `-O0 -DOO_DEBUG` and adds the TCP
debug console and the `callObjC` bridge (see
[Debug flavor and the TCP console](#debug-flavor-and-the-tcp-console)).

One deviation from the other platforms: `./mk.sh test dev` (the automated snapshot
harness) does not currently work on macOS — it drives the game through SDL's `offscreen`
video driver, which cannot create an OpenGL context there. Run the app directly instead.

## Running the game

From the command line:

```bash
build/meson_dev/oolite.app/Contents/MacOS/oolite
```

or through LaunchServices (also how a Finder double-click launches it):

```bash
open -n build/meson_dev/oolite.app
```

The game log is written to `~/Library/Logs/Oolite/Latest.log`. Expansion packs (OXPs)
load from the `AddOns` directory next to the bundle (`build/meson_dev/AddOns/`); the
build installs `Basic-debug.oxp` there for the dev and debug flavors. Speech synthesis
runs through espeak-ng; enable "Spoken messages" in the in-game Game Options to use it.

## Debug flavor and the TCP console

```bash
./mk.sh build debug
```

Debug builds support Oolite's TCP debug console. The game is the TCP client: at startup
it connects to a console listening on `127.0.0.1:8563` (the `console-port` default in
`DebugOXP/Debug.oxp/Config/debugConfig.plist`). With no console listening, boot
continues normally after a `[debugTCP.connect.failed]` log line.

Once connected, the console provides JavaScript evaluation (including the debug-only
`callObjC` bridge) and commands such as `takeSnapShot()`, and stays functional while the
game is paused. The plist-framed protocol is defined by the debug OXP;
`tests/launch_snapshot.py` shows a working client pattern to build against.

## Renderer: what to expect

Apple Silicon exposes either a legacy OpenGL 2.1 context or a core 4.1 context — never
both — while Oolite's renderer wants 3.3 features with legacy semantics. The macOS port
therefore runs a legacy-GL compatibility mode: the 3.3 gate is bypassed when framebuffer
objects are available, and the postFX chain runs GLSL-120 variants of the shared shaders
(upstream shader files are untouched off-darwin). Verified behavior:

- Output is Linux-equivalent SDR: ACES tone mapping, bloom via multiple render targets,
  colorblind modes, and all postFX effects. True HDR/EDR output remains Windows-only
  upstream.
- MSAA is off on darwin (Apple's multisample framebuffer extension is a documented
  quality follow-up).
- Two degradation fallbacks are armed but did not fire on tested hardware: float16
  render targets fall back to RGBA8 (bloom goes visually inert), and the MRT probe
  falls back to single-target rendering with bloom off. Both log through
  `[rendering.legacy.fallback]` when active.

## JavaScript engine deviations

Two intentional deviations from upstream js185, both documented in the mozillajs-macos
project:

1. JIT off — interpreter-only. No arm64 JIT backend exists in this 2011-era fork.
   Script behavior is identical; JS-heavy OXPs run slower than on x86_64 JIT builds.
2. pcre regexes. On arm64, RegExp uses the pcre engine instead of YARR/JIT. A small set
   of jstests edge-case deltas (listed in the mozillajs-macos README) comes with that
   choice; gameplay-relevant differences are not known.

## Known limitations

- FrameGuard corruption under sustained eval+GC (about 160+ cycles): upstream-inherited
  — it reproduces with the macos/arm64 patches reverted — and tracked as a known issue
  in the mozillajs-macos project. Short-eval workloads are unaffected.
- The native `Debug.bundle` plug-in is not built by the meson port; the TCP console
  works without it (one non-fatal `[debugSupport.load.failed]` log line).
- `./mk.sh test dev` does not work on macOS (see
  [Configure and build](#configure-and-build)).

## Continuous integration

The `build-macos` CI job builds the dev flavor on a GitHub `macos-26` runner for every
push and uploads the unsigned `oolite.app` as a workflow artifact. Unsigned artifacts
are for testing only; they trigger Gatekeeper on other machines.

## Distribution and signing

Every local build is ad-hoc signed, which is enough to run it on the machine that built
it, including double-click launches. Distributing the bundle to other machines requires
real signing, which is a release-process step rather than a build step:

- a Developer ID Application identity to sign the bundle with the hardened runtime,
  replacing the ad-hoc signature
- notarization (`notarytool submit --wait` on a zipped archive, then `stapler staple`)
  — without it, Gatekeeper blocks the app on machines that did not build it
