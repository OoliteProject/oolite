# macOS specific: Apple Foundation (not GNUstep) with the SDL front end.
add_project_arguments(
    '-DOOLITE_SDL_MAC=1',
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
