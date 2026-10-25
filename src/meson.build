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
    dependency('zlib'),
]

if get_option('espeak')
    oolite_dependencies += [dependency('espeak-ng')]
    add_project_arguments('-DHAVE_LIBESPEAK=1', language: c_family)
endif

# The JavaScript engine behind ooscript/JSEngine.hpp: the vendored QuickJS-ng, linked statically
# (Phase 1; SpiderMonkey 1.8.5 and NSPR were removed by bead oo-7wx).
# QuickJS-ng is part of the game binary, so it is held to the same golden flag policy as Oolite's own
# code (meson.build; tests/golden/check_build_flags.py): its dtoa/number code produces floats that
# land in the dumps. Its own project() defaults to buildtype=release (-O3). Passing only
# buildtype=debugoptimized from the parent is NOT enough on current meson: the subproject still
# emits an effective -O3 (measured 2026-09-27, oo-6ece; 10 TUs). Pass optimization=2 explicitly
# so the last -O on each QuickJS compile line is the pinned level. b_ndebug=true keeps release
# NDEBUG semantics. -ffp-contract=off reaches it through add_global_arguments in meson.build.
# Bead oo-bipqn: QuickJS-ng adds dependency('threads') (-pthread) to its link line, and every target
# that links it. The MinGW clang driver does not use -pthread when linking (cutils.h takes Win32
# threads under _WIN32), so each link printed "argument unused during compilation: '-pthread'".
# On Windows the threads dependency is the same compile flag without the unused link flag, so the
# objects and the links are unchanged and the driver has nothing to report.
if host_machine.system() == 'windows'
    meson.override_dependency('threads', declare_dependency(compile_args: ['-pthread']))
endif
quickjs_ng_proj = subproject(
    'quickjs-ng',
    default_options: [
        'default_library=static',
        'buildtype=debugoptimized',
        'optimization=2',
        'b_ndebug=true',
    ],
)
oolite_dependencies += [quickjs_ng_proj.get_variable('qjs_dep')]

subdir('meson')
subdir('oofnd')
# Game sources include oofnd headers, which are C++20 (ADR-0011): the game builds as gnu++20.
oolite_dependencies += [oofnd_dep]
# oofnd/objc's support (OORaiseException, OOCAssert's failure path). The game linked libobjc2 alone
# for its Objective-C floor (ADR-0029) from oo-qps.18 until bead oo-dbz.5: no unit is Objective-C.
oolite_dependencies += [oofnd_objc_dep]
oolite_override_options += ['cpp_std=gnu++20']
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
