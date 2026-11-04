project(
    'oolite',
    ['c', 'cpp'],
    meson_version: '>= 1.4.0',
    version: run_command(
        'bash',
        files('ShellScripts/common/get_version.sh'),
        meson.project_build_root(),
        check: true,
    ).stdout().strip(),
    default_options: [
        'optimization=2',
        # Always use the bundled, patched QuickJS-ng (see subprojects/quickjs-ng.wrap):
        # an unpatched system build breaks OXPs that rely on SpiderMonkey behaviour.
        'force_fallback_for=quickjs-ng',
    ],
)

host_os = host_machine.system()
c_family = ['c', 'cpp']

version_string = meson.project_version()
cat_cmd = find_program('cat', required: true)
version_file = meson.project_build_root() / '.meson_version'
cat_result = run_command(cat_cmd, version_file, check: true)
version_vars = {}
file_contents = cat_result.stdout().strip()

foreach line : file_contents.split('\n')
    parts = line.split('=')
    key = parts[0].strip()
    value = parts[1].strip('"\' ')
    version_vars += { key : value }
endforeach
add_project_arguments(
    '-DOO_VERSION_FULL="@0@"'.format(version_string),
    '-DOO_BUILD_DATE="@0@"'.format(version_vars.get('app_date')),
    '-DOO_BUILDER="@0@"'.format(version_vars.get('builder')),
    language: c_family,
)

is_debug = (get_option('optimization') == '0' or get_option('debug'))
if is_debug
    add_project_arguments(
        '-O0',
        '-DDEBUG',
        '-DOO_DEBUG',
        '-DOO_CHECK_GL_HEAVY=1',
        language: c_family,
    )
endif

# (A message to an undeclared method was an error, -Werror=objc-method-access, proposed ADR-0050,
# bead oo-tk0w, while the game sent Objective-C messages. No unit is Objective-C since bead oo-dbz.5:
# a call to an undeclared C++ member is a compile error by itself.)

if get_option('no_shaders')
    add_project_arguments('-DNO_SHADERS=1', language: c_family)
endif

if get_option('deployment_release')
    add_project_arguments(
        '-DNDEBUG',
        '-DOO_CHECK_GL_HEAVY=0',
        '-DOO_DEBUG_MONITOR_ENABLED=1',
        '-DOO_OXP_VERIFIER_ENABLED=1',
        '-DOO_LOCALIZATION_TOOLS=0',
        '-DDEBUG_GRAPHVIZ=0',
        '-DOO_FOV_INFLIGHT_CONTROL_ENABLED=0',
        language: c_family,
    )
else
    if get_option('oo_check_gl_heavy')
        add_project_arguments('-DOO_CHECK_GL_HEAVY=1', language: c_family)
    endif
    if get_option('oo_exclude_debug_support')
        add_project_arguments('-DNDEBUG', language: c_family)
    endif
    if get_option('oo_debug_monitor_enabled')
        add_project_arguments('-DOO_DEBUG_MONITOR_ENABLED=1', language: c_family)
    endif
    if get_option('oo_oxp_verifier_enabled')
        add_project_arguments('-DOO_OXP_VERIFIER_ENABLED=1', language: c_family)
    endif
    if get_option('oo_localization_tools')
        add_project_arguments('-DOO_LOCALIZATION_TOOLS=1', language: c_family)
    endif
    if get_option('debug_graphviz')
        add_project_arguments('-DDEBUG_GRAPHVIZ=1', language: c_family)
    endif
    if get_option('oo_fov_inflight_control_enabled')
        add_project_arguments(
            '-DOO_FOV_INFLIGHT_CONTROL_ENABLED=1',
            language: c_family,
        )
    endif
endif

if get_option('dev_release')
    add_project_arguments(
        '-DDEV_RELEASE',
        language: c_family,
    )
endif

gnustep_folder = ''  # Not needed for Windows
# dependencies, compiler/linker flags and build
subdir('src')

if get_option('quickjs_poc')
    subdir('src/Core/Scripting/poc')
endif

# The unit tests are built by every flavour but deployment: they test the live assertion and
# debug paths, which a deployment build (NDEBUG) compiles out, and upstream's CI builds
# `./mk.sh build deployment` (since #756), which builds every default target.
# They are Windows-only for now: they were written and verified on the native Windows toolchain
# and use its headers and LLP64 types (<process.h>, _putenv_s, <winsock2.h>, long == 32 bits),
# so the Linux CI flavours build the game without them.
#
# deployment_unit_tests builds the oofnd suite under the deployment macros as well, in a separate
# non-LTO build directory (meson setup with -Ddeployment_unit_tests=true): OOCAssert compiled out
# under NDEBUG, and with it PlayerEntity's -deferredInit ship set-up, passes every test-flavour
# suite and breaks the shipped game.
if host_machine.system() == 'windows'
    # Tests load the toolchain's libstdc++/libwinpthread, which must win over older copies earlier
    # on PATH (Git for Windows ships mingw64 ones; a missing symbol surfaces as exit 0xc0000139).
    toolchain_bin = import('fs').parent(find_program(meson.get_compiler('cpp').cmd_array()[0]).full_path())
    test_env = environment()
    test_env.prepend('PATH', toolchain_bin)
    add_test_setup('default', env: test_env, is_default: true)
endif

if (not get_option('deployment_release') or get_option('deployment_unit_tests')) and host_machine.system() == 'windows'
    # Unit tests that need no game build (meson test --suite oofnd).
    subdir('tests/unit/oofnd')
endif

if not get_option('deployment_release') and host_machine.system() == 'windows'
    # Unit tests of converted game classes, linked from the game's own objects (meson test --suite core).
    subdir('tests/unit/core')
endif

# Every game and test header compiles on its own, so include order never matters and clang-format
# may sort includes freely (meson test --suite headers). Windows-only like the unit tests above,
# whose headers it also checks; it needs the finished build's dependency log, which meson test has.
if not get_option('deployment_release') and host_machine.system() == 'windows'
    test('headers_standalone', find_program('python3'),
        args: [files('tests/check_headers_standalone.py'), meson.project_build_root()],
        suite: 'headers', timeout: 900, is_parallel: false)
endif
