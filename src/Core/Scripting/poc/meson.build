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
    '../OOJSClasses.mm',
    '../OOJSEngineNativeWrappers.mm',
    '../OOJSQuaternion.mm',
    '../OOJSVector.mm',
    'OOJSScript.mm',
    'OOJavaScriptEnginePoc.mm',
    'OOLogStub.mm',
    'main.mm',
    '../../OOHPVector.mm',
    '../../OOQuaternion.cpp',
    '../../OOVector.mm',
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
    objc_args: poc_args + oofnd_objc_args,
    objcpp_args: poc_args + oofnd_objc_args,
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
