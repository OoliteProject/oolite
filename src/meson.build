# ------------------------------------------------------------------------------
# Dependencies and platform specific logic
# ------------------------------------------------------------------------------

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
    extra_objc_args += ['-DHAVE_LIBESPEAK=1']
endif

my_sources = []
my_includes = []

if is_windows
    extra_c_args += ['-DWIN32', '-DWINVER=0x0A00']
    extra_objc_args += ['-DWIN32', '-DXP_WIN', '-DWINVER=0x0A00']
    extra_link_args += ['-mwindows']

    if cc.get_id() == 'clang' and get_option('pdb')
        extra_c_args += ['-g', '-gcodeview']
        extra_objc_args += ['-g', '-gcodeview']
        extra_link_args += ['-Wl,-pdb=']
    endif

    oolite_deps += [dependency('gnustep-base')]
    dep_libs = ['glu32', 'opengl32', 'dwmapi', 'winmm']
    foreach lib : dep_libs
        oolite_deps += [cc.find_library(lib)]
    endforeach

    my_includes += [
        include_directories('deps/Windows-deps/x86_64/JS32ECMAv5/include'),
    ]
    win_js_suffix = (get_option('optimization') == '0' or get_option('debug')) ? 'ECMAv5dbg' : 'ECMAv5'
    js_lib_dir = meson.current_source_dir() + '/deps/Windows-deps/x86_64/JS32' + win_js_suffix + '/lib'
    if (get_option('optimization') == '0' or get_option('debug')) and (
        cc.get_id() == 'gcc'
    )
        extra_c_args += ['-DSTATIC_JS_API']
        extra_objc_args += ['-DSTATIC_JS_API']
    endif
    oolite_deps += [cc.find_library('js32' + win_js_suffix, dirs: js_lib_dir)]

else
    extra_c_args += ['-ggdb3']
    extra_objc_args += ['-ggdb3', '-DLINUX', '-DXP_UNIX']
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
                    gnustep_compile_flags = []
                    if item['build_subfolder'] == 'gnustep'
                        gnustep_folder = actual_root
                        gnustep_compile_flags = [
                            '-DGNUSTEP_RUNTIME=1',
                            '-D_NONFRAGILE_ABI=1',
                            '-DGNUSTEP_BASE_LIBRARY=1',
                            '-fobjc-runtime=gnustep-2.2',
                            '-fblocks',
                            '-fexceptions',
                            '-fobjc-exceptions',
                        ]
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
                            compile_args: gnustep_compile_flags,
                        ),
                    ]
                    found_dep = true
                endif
            endforeach
        endforeach
    endforeach
endif

# Enter child subdirectories
subdir('SDL')
subdir('Core')
subdir('Cocoa')

oolite_bin = executable(
    'oolite',
    my_sources,
    include_directories: my_includes,
    dependencies: oolite_deps,
    c_args: extra_c_args,
    objc_args: extra_objc_args,
    link_args: extra_link_args,
    build_rpath: '$ORIGIN',
    install_rpath: '$ORIGIN',
    install: true,
)
