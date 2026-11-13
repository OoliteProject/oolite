# QuickJS-ng proof of concept (issue #580).
#
# Builds a standalone test harness, oojs-quickjs-poc, from the ported engine
# core, Vector3D and Quaternion bindings and a minimal script loader. The game
# itself still uses SpiderMonkey. Linux only for now; needs the same GNUstep
# install as the game. From the repository root:
#   meson setup build/quickjs-poc --native-file clang.ini -Dquickjs_poc=true -Ddebug=true -Doptimization=0
#   meson compile -C build/quickjs-poc oojs-quickjs-poc
#   meson test -C build/quickjs-poc quickjs-poc --print-errorlogs
# or run the harness directly to see each check:
#   build/quickjs-poc/src/Core/Scripting/QuickJS/poc/oojs-quickjs-poc src/Core/Scripting/QuickJS/poc/tests
#
# The harness has its own minimal engine core and script loader (in this
# directory), since the full ones depend on the rest of the game.

quickjs_dep = dependency(
    'quickjs-ng',
    version: '>=0.17.0',
    default_options: ['default_library=static', 'libc=false'],
)

if host_os == 'windows' or host_os == 'cygwin'
    error('The QuickJS proof-of-concept harness currently supports Linux only.')
endif

poc_gnustep_dep = declare_dependency(
    dependencies: [gs_lib, objc_lib, dependency('gl')],
    include_directories: include_directories(found_gs_inc, is_system: true),
)

poc_sources = files(
    '../OOJSClasses.m',
    '../OOJSQuaternion.m',
    '../OOJSVector.m',
    'OOJSScript.m',
    'OOJavaScriptEnginePoc.m',
    'OOLogStub.m',
    'main.m',
    '../../../OOHPVector.m',
    '../../../OOQuaternion.m',
    '../../../OOVector.m',
    '../../../legacy_random.c',
)

# The ported headers in this directory must be found before the SpiderMonkey
# ones in src/Core/Scripting, so that directory is deliberately not included.
poc_bin = executable(
    'oojs-quickjs-poc',
    poc_sources,
    include_directories: include_directories('.', '..', '../../..', '../../../Tables', '../../../../SDL'),
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
