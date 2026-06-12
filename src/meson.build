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

subdir('meson')
subdir('Core')
subdir('SDL')

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

install_env_args = [
    'PROGPATH=' + meson.current_build_dir() / 'oolite',
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
post_build_script = find_program('../ShellScripts/common/post_build.sh')
oolite_app_bundle = custom_target('post_build',
                                  input: oolite_bin,
                                  output: '.oolite_bundle.stamp',
                                  command: [
                                      'env',
                                      install_env_args,
                                      post_build_script.full_path(),
                                      '&&', 'touch', '@OUTPUT@'
                                  ],
                                  build_by_default: true,
                                  install: false,
)
