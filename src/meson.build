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

appname = 'oolite'
oolite_bin = executable(
    appname,
    oolite_sources,
    include_directories: oolite_includes,
    dependencies: oolite_dependencies,
    override_options: oolite_override_options,
    link_args: oolite_link_args,
    win_subsystem: 'windows',
    build_rpath: '$ORIGIN',
    install_rpath: '$ORIGIN',
    install: false,
)

prog_dir = meson.global_build_root() / appname + '.app'
stamp_file = '.oolite_bundle.stamp'
install_env_args = [
    'ORIGPROGPATH=' + meson.current_build_dir() / appname,
    'PROGDIR=' + prog_dir,
    'HOST_OS=' + host_os,
    'DEBUG=' + (get_option('debug') ? 'yes' : 'no'),
    'DEPLOYMENT_RELEASE_CONFIGURATION=' + (
        get_option('deployment_release_configuration') ? 'yes' : 'no'
    ),
    'ESPEAK=' + (get_option('espeak') ? 'yes' : 'no'),
    'STRIP_BIN=' + (get_option('strip_bin') ? 'yes' : 'no'),
    'VER_FULL=' + version_string,
    'GNUSTEP_FOLDER=' + gnustep_folder,
    'STAMP_FILE=' + stamp_file,
]
post_build_script = find_program('../ShellScripts/common/post_build.sh')
oolite_app_bundle = custom_target('post_build',
                                  input: oolite_bin,
                                  output: stamp_file,
                                  depend_files: [post_build_script.full_path()],
                                  command: [
                                      'env',
                                      install_env_args,
                                      post_build_script.full_path(),
                                  ],
                                  build_by_default: true,
                                  install: false,
)
install_env_args = [
    'STAGEPROGPATH=' + prog_dir / appname,
    'BINDIR=' + get_option('bindir'),
    'DATADIR=' + get_option('datadir'),
    'HOST_OS=' + host_os,
    'DEPLOYMENT_RELEASE_CONFIGURATION=' + (
    get_option('deployment_release_configuration') ? 'yes' : 'no'),
]
install_script = find_program('../ShellScripts/common/install.sh')
meson.add_install_script('env', install_env_args, install_script.full_path())