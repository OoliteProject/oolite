oolite_sources = []
oolite_includes = []
oolite_override_options = []
oolite_link_args = []
oolite_dependencies = [
    dependency('sdl3'),
    dependency('libpng'),
    dependency('openal'),
    dependency('vorbisfile'),
    dependency('vorbis'),
    dependency('nspr'),
    dependency('zlib'),
]

if get_option('espeak')
    oolite_dependencies += [dependency('espeak-ng')]
    add_project_arguments('-DHAVE_LIBESPEAK=1', language: c_family)
endif

# Enter child subdirectories
subdir('meson')
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
