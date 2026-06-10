project(
    'oolite',
    ['c', 'cpp', 'objc'],
    meson_version: '>= 1.4.0',
    version: run_command(
        'bash',
        files('ShellScripts/common/get_version.sh'),
        check: true,
    ).stdout().strip(),
    default_options: [
        'prefix=' + meson.current_build_dir() / 'oolite.app',
        'bindir=',
        'datadir=',
        'optimization=2',
    ],
)

# ------------------------------------------------------------------------------
# Compiler Setup & Baseline Arguments
# ------------------------------------------------------------------------------
cc = meson.get_compiler('c')
host_os = host_machine.system()
is_windows = (host_os == 'windows' or host_os == 'cygwin')

c_family = ['c', 'cpp', 'objc']

version_string = meson.project_version()
add_project_arguments(
    '-DOO_VERSION_FULL="@0@"'.format(version_string),
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

if get_option('no_shaders')
    add_project_arguments('-DNO_SHADERS=1', language: c_family)
endif

if get_option('deployment_release_configuration')
    add_project_arguments(
        '-DNDEBUG',
        '-DOO_CHECK_GL_HEAVY=0',
        '-DOO_OXP_VERIFIER_ENABLED=0',
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

if get_option('snapshot_build')
    add_project_arguments(
        '-DSNAPSHOT_BUILD',
        '-DOOLITE_SNAPSHOT_VERSION="@0@"'.format(version_string),
        language: c_family,
    )
endif

if get_option('oo_javascript_trace')
    add_project_arguments('-DMOZ_TRACE_JSCALLS=1', language: c_family)
endif

gnustep_folder = ''  # Not needed for Windows
# dependencies, compiler/linker flags and build
subdir('src')

install_env_args = [
    'PROGPATH=' + join_paths(
        meson.global_build_root() / 'oolite.app',
        get_option('bindir'),
        'oolite',
    ),
    'HOST_OS=' + host_os,
    'DEBUG=' + (get_option('debug') ? 'yes' : 'no'),
    'DEPLOYMENT_RELEASE_CONFIGURATION=' + (
        get_option('deployment_release_configuration') ? 'yes' : 'no'
    ),
    'ESPEAK=' + (get_option('espeak') ? 'yes' : 'no'),
    'STRIP_BIN=' + (get_option('strip_bin') ? 'yes' : 'no'),
    'VER_FULL=' + version_string,
    'GNUSTEP_FOLDER=' + gnustep_folder,
]
post_build_script = find_program('ShellScripts/common/post_build.sh')
meson.add_install_script('env', install_env_args, post_build_script.full_path())
