# QuickJS-ng proof of concept (issue #580).
#
# Builds a standalone test harness, oojs-quickjs-poc, from the engine's
# Vector3D and Quaternion bindings and class registry, and a minimal engine
# core and script loader. From the repository root:
#   meson setup build/quickjs-poc --native-file clang.ini -Dquickjs_poc=true -Ddebug=true -Doptimization=0
#   meson compile -C build/quickjs-poc oojs-quickjs-poc
#   meson test -C build/quickjs-poc quickjs-poc --print-errorlogs
# or run the harness directly to see each check:
#   build/quickjs-poc/src/Core/Scripting/poc/oojs-quickjs-poc src/Core/Scripting/poc/tests
#
# The harness has its own minimal engine core and script loader (in this
# directory), since the full ones depend on the rest of the game. It uses the
# game's QuickJS-ng (src/meson/meson.build) and oofnd, compiled as the game is.

poc_sources = files(
    '../OOJSClasses.cpp',
    '../OOJSEngineNativeWrappers.cpp',
    '../OOJSQuaternion.cpp',
    '../OOJSVector.cpp',
    'OOJSScript.cpp',
    'OOJavaScriptEnginePoc.cpp',
    'OOLogStub.cpp',
    'main.cpp',
    '../../OOHPVector.cpp',
    '../../OOQuaternion.cpp',
    '../../OOVector.cpp',
    '../../legacy_random.c',
)

# The game's QuickJS-ng, as src/meson/meson.build declared it (the cached dependency).
poc_quickjs_dep = dependency('quickjs-ng', version: '>=0.17.0')

poc_args = ['-DOOJS_POC_HARNESS=1']

# The harness's own OOJSScript.h must be found before the game's in
# src/Core/Scripting.
poc_bin = executable(
    'oojs-quickjs-poc',
    poc_sources,
    include_directories: [include_directories('.'), oolite_includes],
    c_args: poc_args,
    cpp_args: poc_args,
    dependencies: [poc_quickjs_dep, oofnd_dep, oofnd_objc_dep],
    override_options: oolite_override_options,
    install: false,
)

test(
    'quickjs-poc',
    poc_bin,
    args: [meson.current_source_dir() / 'tests'],
    timeout: 120,
)
