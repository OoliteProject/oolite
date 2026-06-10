oolite_dependencies = [
    dependency('sdl3'),
    dependency('libpng'),
    dependency('openal'),
    dependency('vorbisfile'),
    dependency('vorbis'),
    dependency('nspr'),
    dependency('zlib'),
]
# gnustep including its flags, mozilla js
subdir('meson')

if get_option('espeak')
    oolite_dependencies += [dependency('espeak-ng')]
    add_project_arguments('-DHAVE_LIBESPEAK=1', language: c_family)
endif

oolite_override_options = []
oolite_link_args = []

oolite_sources = []
oolite_includes = []

if is_windows
    add_project_arguments(
        '-DWIN32',
        '-DXP_WIN',
        '-DWINVER=0x0A00',
        language: c_family,
    )
    oolite_link_args += ['-mwindows']

    if cc.get_id() == 'clang' and get_option('pdb')
        add_project_arguments('-g', '-gcodeview', language: c_family)
        oolite_link_args += ['-Wl,-pdb=']
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
        oolite_dependencies += [cc.find_library(lib, required: true)]
    endforeach
    if (cc.get_id() == 'gcc')
        add_project_arguments('-DSTATIC_JS_API', language: c_family)
    endif

else
    add_project_arguments('-ggdb3', '-DLINUX', '-DXP_UNIX', language: c_family)
    oolite_link_args += ['-ggdb3']

    oolite_dependencies += [
        dependency('gl'),
        dependency('glu'),
        dependency('x11'),
    ]

endif

# Enter child subdirectories
subdir('Core')
subdir('SDL')

if cc.get_id() == 'gcc'
    oolite_override_options += 'c_std=gnu99'
endif

if get_option('b_lto')
    if cc.get_id() == 'clang'
        add_project_arguments('-flto=thin', language: c_family)
        oolite_link_args += [
            '-flto=thin',
            '-Wl,--thinlto-cache-dir=thinlto_cache',
        ]
    else
        add_project_arguments('-flto=auto', language: c_family)
        oolite_link_args += ['-flto=auto']
    endif
endif

oolite_bin = executable(
    'oolite',
    oolite_sources,
    include_directories: oolite_includes,
    dependencies: oolite_dependencies,
    override_options: oolite_override_options,
    link_args: oolite_link_args,
    win_subsystem: 'windows',
    build_rpath: '$ORIGIN',
    install_rpath: '$ORIGIN',
    install: true,
)
