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

bash_prog = find_program('bash')
prog_dir = meson.global_build_root() / appname + '.app'
stamp_file = '.oolite_bundle.stamp'
post_build_args = [
    meson.current_build_dir() / appname,
    prog_dir,
    host_os,
    get_option('debug') ? 'yes' : 'no',
    get_option('deployment_release') ? 'yes' : 'no',
    get_option('espeak') ? 'yes' : 'no',
    get_option('strip_bin') ? 'yes' : 'no',
    version_string,
    version_vars.get('ver_quad'),
    version_vars.get('ver_githash'),
    version_vars.get('buildtime'),
    gnustep_folder,
    stamp_file,
]
post_build_script = files('../ShellScripts/common/post_build.sh')
generate_manifest_script = files('../ShellScripts/common/generate_manifest_fn.sh')
oolite_app_bundle = custom_target('post_build',
                                  input: oolite_bin,
                                  output: stamp_file,
                                  command: [
                                      bash_prog,
                                      post_build_script,
                                      post_build_args,
                                  ],
                                  depend_files: [generate_manifest_script],
                                  build_by_default: true,
                                  install: false,
)
install_args = [
    prog_dir / appname,
    get_option('bindir'),
    get_option('datadir'),
    host_os,
    get_option('deployment_release') ? 'yes' : 'no',
]
install_script = files('../ShellScripts/common/install.sh')
meson.add_install_script(bash_prog, install_script, install_args)
