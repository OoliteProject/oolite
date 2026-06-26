project(
    'oolite',
    ['c', 'cpp', 'objc'],
    meson_version: '>= 1.4.0',
    version: 'not used',
    default_options: [
        'optimization=2',
    ],
)

host_os = host_machine.system()
c_family = ['c', 'cpp', 'objc']

version_string = get_option('ver_full')  # use instead of meson project version!
add_project_arguments(
    '-DOO_VERSION_FULL="@0@"'.format(version_string),
    '-DOO_BUILD_DATE="@0@"'.format(get_option('build_date')),
    '-DOO_BUILDER="@0@"'.format(get_option('builder')),
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

if get_option('deployment_release')
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

if get_option('dev_release')
    add_project_arguments(
        '-DDEV_RELEASE',
        language: c_family,
    )
endif

if get_option('oo_javascript_trace')
    add_project_arguments('-DMOZ_TRACE_JSCALLS=1', language: c_family)
endif

gnustep_folder = ''  # Not needed for Windows
# dependencies, compiler/linker flags and build
subdir('src')
