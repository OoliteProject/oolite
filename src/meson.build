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

    dep_libs = ['gnustep-base', 'glu32', 'opengl32', 'dwmapi', 'winmm']
    foreach lib : dep_libs
        oolite_deps += [cc.find_library(lib)]
    endforeach

    win_js_suffix = (get_option('optimization') == '0' or get_option('debug')) ? 'dbg' : ''
    if (cc.get_id() == 'gcc')
        add_project_arguments('-DSTATIC_JS_API', language: c_family)
    endif
    oolite_deps += [cc.find_library('js' + win_js_suffix)]

else
    add_project_arguments('-ggdb3', '-DLINUX', '-DXP_UNIX', language: c_family)
    extra_link_args += ['-ggdb3']

    oolite_deps += [
        dependency('gl'),
        dependency('glu'),
        dependency('x11'),
    ]

    gnustep_folder = ''
    fs = import('fs')
    home_local = join_paths(fs.expanduser('~'), '.local')
    libraries_to_find = [
        {
            'name': (get_option('optimization') == '0' or get_option('debug')) ? 'jsdbg_static' : 'js_static',
            'build_subfolder': 'mozilla_js',
        },
        {
            'name': 'gnustep-base',
            'build_subfolder': 'gnustep',
        },
    ]
    foreach item : libraries_to_find
        found_dep = false
        foreach root : [
            'build/' + item['build_subfolder'],
            home_local,
            '/usr/local',
            '/app',
        ]
            actual_root = root.substring(0, 1) == '/' ? root : join_paths(
                meson.current_source_dir(),
                root,
            )
            search_subdirs = ['lib', 'lib64']
            foreach libdir : search_subdirs
                test_path = join_paths(actual_root, libdir)
                lib_check = cc.find_library(
                    item['name'],
                    dirs: test_path,
                    required: false,
                )

                if lib_check.found() and not found_dep
                    include_target = join_paths(actual_root, 'include')
                    linked_objects = [lib_check]
                    if item['build_subfolder'] == 'gnustep'
                        gnustep_folder = actual_root
                        linked_objects += [
                            cc.find_library(
                                'objc',
                                dirs: test_path,
                                required: true,
                            ),
                        ]
                    endif

                    oolite_deps += [
                        declare_dependency(
                            dependencies: linked_objects,
                            include_directories: include_directories(
                                include_target,
                            ),
                        ),
                    ]
                    found_dep = true
                endif
            endforeach
        endforeach
    endforeach
endif

# Enter child subdirectories
subdir('Core')
subdir('SDL')

oolite_bin = executable(
    'oolite',
    my_sources,
    include_directories: my_includes,
    dependencies: oolite_deps,
    link_args: extra_link_args,
    build_rpath: '$ORIGIN',
    install_rpath: '$ORIGIN',
    install: true,
)
