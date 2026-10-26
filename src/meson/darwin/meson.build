# macOS specific: Apple Foundation (not GNUstep) with the SDL front end.
add_project_arguments(
    '-DOOLITE_SDL_MAC=1',
    '-DXP_UNIX',
    '-DXP_MACOSX',
    '-DGL_SILENCE_DEPRECATION',
    language: c_family,
)
add_project_arguments('-g', language: c_family)
oolite_link_args += [
    # Embed the Info plist so [[NSBundle mainBundle] infoDictionary] works for
    # an unbundled executable (GNUstep builds use NSBundle+Override instead).
    '-Wl,-sectcreate,__TEXT,__info_plist,' + meson.project_source_root() / 'Resources/Info-gnustep.plist',
]

oolite_dependencies += [
    dependency('appleframeworks', modules: ['Foundation', 'OpenGL']),
]

# =====================================================================
# MOZILLA JS (built by ShellScripts/macOS/build_mozilla_js.sh)
# =====================================================================
fs = import('fs')
js_name = is_debug ? 'jsdbg_static' : 'js_static'
js_root = meson.project_source_root() / 'build/mozilla_js'
if not fs.is_file(js_root / 'lib' / 'lib' + js_name + '.a')
    error('lib@0@.a not found in @1@. Run ShellScripts/macOS/build_mozilla_js.sh first.'.format(js_name, js_root / 'lib'))
endif
js_lib = cc.find_library(js_name, dirs: [js_root / 'lib'], static: true, required: true)

oolite_dependencies += declare_dependency(
    dependencies: [js_lib],
    include_directories: include_directories('../../../build/mozilla_js/include', is_system: true),
    link_args: ['-lc++'],
)
