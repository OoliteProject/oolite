# QuickJS-ng proof of concept (issue #580).
#
# Builds a standalone test harness, oojs-quickjs-poc, from the ported engine
# core, Vector3D and Quaternion bindings and a minimal script loader, on Linux
# (with the same GNUstep install as the game) or macOS. From the repository root:
#   meson setup build/quickjs-poc --native-file clang.ini -Dquickjs_poc=true -Ddebug=true -Doptimization=0
#   meson compile -C build/quickjs-poc oojs-quickjs-poc
#   meson test -C build/quickjs-poc quickjs-poc --print-errorlogs
# or run the harness directly to see each check:
#   build/quickjs-poc/src/Core/Scripting/poc/oojs-quickjs-poc src/Core/Scripting/poc/tests
#
# The harness has its own minimal engine core and script loader (in this
# directory), since the full ones depend on the rest of the game.

quickjs_dep = dependency(
    'quickjs-ng',
    version: '>=0.17.0',
    default_options: ['default_library=static', 'libc=false'],
)

if host_os == 'windows' or host_os == 'cygwin'
    warning('The QuickJS proof-of-concept harness supports Linux and macOS only; not building it.')
    subdir_done()
endif

if host_os == 'darwin'
    # The OpenGL headers come by way of SDL's.
    poc_gnustep_dep = [
        dependency('appleframeworks', modules: ['Foundation', 'OpenGL']),
        dependency('sdl3').partial_dependency(compile_args: true, includes: true),
    ]
else
    poc_gnustep_dep = declare_dependency(
        dependencies: [gs_lib, objc_lib, dependency('gl')],
        include_directories: include_directories(found_gs_inc, is_system: true),
    )
endif

poc_sources = files(
    '../OOJSClasses.m',
    '../OOJSQuaternion.m',
    '../OOJSVector.m',
    'OOJSScript.m',
    'OOJavaScriptEnginePoc.m',
    'OOLogStub.m',
    'main.m',
    '../../OOHPVector.m',
    '../../OOQuaternion.m',
    '../../OOVector.m',
    '../../legacy_random.c',
)

# The harness's own OOJSScript.h must be found before the game's in
# src/Core/Scripting.
poc_bin = executable(
    'oojs-quickjs-poc',
    poc_sources,
    include_directories: include_directories('.', '..', '../..', '../../Tables', '../../../SDL'),
    objc_args: ['-DOOJS_POC_HARNESS=1'],
    dependencies: [quickjs_dep, poc_gnustep_dep],
    override_options: oolite_override_options,
    install: false,
)

test(
    'quickjs-poc',
    poc_bin,
    args: [meson.current_source_dir() / 'tests'],
    timeout: 120,
)
