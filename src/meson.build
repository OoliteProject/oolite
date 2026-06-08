oolite_deps = [
    dependency('sdl3'),
    dependency('libpng'),
    dependency('openal'),
    dependency('vorbisfile'),
    dependency('vorbis'),
    dependency('nspr'),
    dependency('zlib'),
]

if get_option('espeak')
    oolite_deps += [dependency('espeak-ng')]
    add_project_arguments('-DHAVE_LIBESPEAK=1', language: c_family)
endif

gnustep_folder = ''  # Not needed for Windows
my_sources = []
my_includes = []

if is_windows
    add_project_arguments(
        '-DWIN32',
        '-DXP_WIN',
        '-DWINVER=0x0A00',
        language: c_family,
    )
    extra_link_args += ['-mwindows']

    if cc.get_id() == 'clang' and get_option('pdb')
        add_project_arguments('-g', '-gcodeview', language: c_family)
        extra_link_args += ['-Wl,-pdb=']
    endif

    win_js_suffix = (get_option('optimization') == '0' or get_option('debug')) ? 'dbg' : ''
    dep_libs = [
        'glu32',
        'opengl32',
        'dwmapi',
        'winmm',
        'ws2_32',
        'objc',
        'gnustep-base',
        'js' + win_js_suffix,
    ]
    foreach lib : dep_libs
        oolite_deps += [cc.find_library(lib, required: true)]
    endforeach
    if (cc.get_id() == 'gcc')
        add_project_arguments('-DSTATIC_JS_API', language: c_family)
    endif

else
    add_project_arguments('-ggdb3', '-DLINUX', '-DXP_UNIX', language: c_family)
    extra_link_args += ['-ggdb3']

    oolite_deps += [
        dependency('gl'),
        dependency('glu'),
        dependency('x11'),
    ]

    fs = import('fs')
    project_root = meson.project_source_root()
    home_local = join_paths(fs.expanduser('~'), '.local')

    candidate_roots = [
        {'abs': project_root, 'rel': '..'},
        {'abs': home_local, 'rel': home_local},
        {'abs': '/usr/local', 'rel': '/usr/local'},
        {'abs': '/app', 'rel': '/app'},
    ]
    js_name = is_debug ? 'jsdbg_static' : 'js_static'
    js_lib = disabler()
    gs_lib = disabler()
    objc_lib = disabler()
    js_inc = ''
    gs_inc = ''
    foreach root : candidate_roots
        if not js_lib.found()
            js_sub = (root['abs'] == project_root) ? 'build/mozilla_js' : ''
            js_folder = root['abs'] / js_sub
            lib_check = cc.find_library(
                js_name,
                dirs: [js_folder / 'lib', js_folder / 'lib64'],
                required: false,
            )
            if lib_check.found()
                js_lib = lib_check
                js_inc = root['rel'] / js_sub / 'include'
            endif
        endif

        if not gs_lib.found()
            gs_sub = (root['abs'] == project_root) ? 'build/gnustep' : ''
            gnustep_folder = root['abs'] / gs_sub
            test_dirs = [gnustep_folder / 'lib', gnustep_folder / 'lib64']
            lib_check = cc.find_library(
                'gnustep-base',
                dirs: test_dirs,
                required: false,
            )
            if lib_check.found()
                gs_lib = lib_check
                objc_lib = cc.find_library(
                    'objc',
                    dirs: test_dirs,
                    required: true,
                )
                gs_inc = root['rel'] / gs_sub / 'include'
            endif
        endif

        if js_lib.found() and gs_lib.found()
            break
        endif
    endforeach

    if not js_lib.found()
        error('Required dependency "@0@" was not found.'.format(js_name))
    endif
    if not gs_lib.found()
        error('Required dependency "gnustep-base" was not found.')
    endif

    inc_dir = include_directories([js_inc, gs_inc], is_system: true)
    oolite_deps += declare_dependency(
        dependencies: [js_lib, gs_lib, objc_lib],
        include_directories: inc_dir,
    )
endif

# Enter child subdirectories
subdir('Core')
subdir('SDL')

oolite_bin = executable(
    'oolite',
    my_sources,
    include_directories: my_includes,
    dependencies: oolite_deps,
    win_subsystem: 'windows',
    link_args: extra_link_args,
    build_rpath: '$ORIGIN',
    install_rpath: '$ORIGIN',
    install: true,
)
