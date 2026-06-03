project(
    'oolite',
    ['c', 'cpp', 'objc'],
    meson_version: '>= 1.4.0',
    version: run_command('bash', files('ShellScripts/common/get_version.sh'), check: true).stdout().strip(),
    default_options: [
        'prefix=' + meson.current_build_dir() / 'oolite.app',
        'bindir=',
        'datadir=',
        'optimization=2',
    ],
)

# ------------------------------------------------------------------------------
# Compiler Setup
# ------------------------------------------------------------------------------
cc = meson.get_compiler('c')
host_os = host_machine.system()
is_windows = (host_os == 'windows' or host_os == 'cygwin')

extra_c_args = []
extra_objc_args = []
extra_link_args = []

if cc.get_id() == 'clang'
    extra_c_args += ['-Qunused-arguments']
    extra_objc_args += ['-Qunused-arguments']
else
    add_project_arguments('-std=gnu99', language: ['c', 'objc'])
endif

version_string = meson.project_version()
extra_c_args += ['-DOO_VERSION_FULL="@0@"'.format(version_string)]
extra_objc_args += ['-DOO_VERSION_FULL="@0@"'.format(version_string)]

if get_option('optimization') == '0' or get_option('debug')
    extra_c_args += ['-O0', '-DDEBUG', '-DOO_DEBUG', '-DOO_CHECK_GL_HEAVY=1']
    extra_objc_args += ['-O0', '-DDEBUG', '-DOO_DEBUG', '-DOO_CHECK_GL_HEAVY=1']
endif

if get_option('no_shaders')
    extra_c_args += ['-DNO_SHADERS=1']
    extra_objc_args += ['-DNO_SHADERS=1']
endif

if get_option('deployment_release_configuration')
    deployment_flags = [
        '-DNDEBUG',
        '-DOO_CHECK_GL_HEAVY=0',
        '-DOO_OXP_VERIFIER_ENABLED=0',
        '-DOO_LOCALIZATION_TOOLS=0',
        '-DDEBUG_GRAPHVIZ=0',
        '-DOO_FOV_INFLIGHT_CONTROL_ENABLED=0',
    ]
    extra_c_args += deployment_flags
    extra_objc_args += deployment_flags
else
    if get_option('oo_check_gl_heavy')
        extra_c_args += ['-DOO_CHECK_GL_HEAVY=1']
        extra_objc_args += ['-DOO_CHECK_GL_HEAVY=1']
    endif
    if get_option('oo_exclude_debug_support')
        extra_c_args += ['-DNDEBUG']
        extra_objc_args += ['-DNDEBUG']
    endif
    if get_option('oo_oxp_verifier_enabled')
        extra_c_args += ['-DOO_OXP_VERIFIER_ENABLED=1']
        extra_objc_args += ['-DOO_OXP_VERIFIER_ENABLED=1']
    endif
    if get_option('oo_localization_tools')
        extra_c_args += ['-DOO_LOCALIZATION_TOOLS=1']
        extra_objc_args += ['-DOO_LOCALIZATION_TOOLS=1']
    endif
    if get_option('debug_graphviz')
        extra_c_args += ['-DDEBUG_GRAPHVIZ=1']
        extra_objc_args += ['-DDEBUG_GRAPHVIZ=1']
    endif
    if get_option('oo_fov_inflight_control_enabled')
        extra_c_args += ['-DOO_FOV_INFLIGHT_CONTROL_ENABLED=1']
        extra_objc_args += ['-DOO_FOV_INFLIGHT_CONTROL_ENABLED=1']
    endif
endif

if get_option('snapshot_build')
    extra_c_args += [
        '-DSNAPSHOT_BUILD',
        '-DOOLITE_SNAPSHOT_VERSION="@0@"'.format(version_string),
    ]
    extra_objc_args += [
        '-DSNAPSHOT_BUILD',
        '-DOOLITE_SNAPSHOT_VERSION="@0@"'.format(version_string),
    ]
endif

if get_option('oo_javascript_trace')
    extra_objc_args += ['-DMOZ_TRACE_JSCALLS=1']
endif

if get_option('b_lto')
    if cc.get_id() == 'clang'
        extra_c_args += ['-flto=thin']
        extra_objc_args += ['-flto=thin']
        extra_link_args += [
            '-flto=thin',
            '-Wl,--thinlto-cache-dir=thinlto_cache',
        ]
    else
        extra_c_args += ['-flto=auto']
        extra_objc_args += ['-flto=auto']
        extra_link_args += ['-flto=auto']
    endif
endif

subdir('src')

install_env_args = [
    'PROGPATH=' + join_paths(
        meson.global_build_root() / 'oolite.app',
        get_option('bindir'),
        'oolite',
    ),
    'HOST_OS=' + host_os,
    'DEBUG=' + (
        get_option('debug') ? 'yes' : 'no'
    ),
    'DEPLOYMENT_RELEASE_CONFIGURATION=' + (
        get_option('deployment_release_configuration') ? 'yes' : 'no'
    ),
    'ESPEAK=' + (
        get_option('espeak') ? 'yes' : 'no'
    ),
    'STRIP_BIN=' + (
        get_option('strip_bin') ? 'yes' : 'no'
    ),
    'VER_FULL=' + version_string,
    'GNUSTEP_FOLDER=' + gnustep_folder,
]
post_build_script = find_program('ShellScripts/common/post_build.sh')
meson.add_install_script('env', install_env_args, post_build_script.full_path())
