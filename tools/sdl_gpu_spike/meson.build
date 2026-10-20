# Standalone build for the SDL_GPU phase 0 spike. Not part of the game build.
#   meson setup build/sdl_gpu_spike tools/sdl_gpu_spike && meson compile -C build/sdl_gpu_spike

project('oolite-sdl-gpu-spike', 'c', 'cpp', default_options: ['c_std=c11', 'warning_level=2'])

sdl3 = dependency('sdl3')
spirv_tools = dependency('SPIRV-Tools-shared')
# glslang ships no pkg-config file; look for the libraries directly.
cc = meson.get_compiler('c')
brew_lib = ['/opt/homebrew/lib', '/usr/local/lib']
glslang = declare_dependency(
    dependencies: [cc.find_library('glslang', dirs: brew_lib), cc.find_library('glslang-default-resource-limits', dirs: brew_lib)],
    include_directories: include_directories(run_command('sh', '-c', 'for d in /opt/homebrew/include /usr/local/include /usr/include; do [ -d $d/glslang ] && echo $d && break; done', check: true).stdout().strip()))

# The static spirv-cross-c pkg-config file leaves out the backends it needs.
spirv_cross_libs = [dependency('spirv-cross-c')]
foreach lib : ['msl', 'hlsl', 'cpp', 'glsl', 'reflect', 'util', 'core']
    spirv_cross_libs += cc.find_library('spirv-cross-' + lib, dirs: brew_lib, static: true)
endforeach
spirv_cross = declare_dependency(dependencies: spirv_cross_libs)

translator = static_library('ooglsltranslator', 'OOGLSLTranslator.c',
    dependencies: [glslang, spirv_cross])
translator_dep = declare_dependency(link_with: translator, dependencies: [glslang, spirv_cross],
    include_directories: include_directories('.'))

common = static_library('oogpuspike', 'OOGPUSpikeCommon.c', dependencies: [translator_dep, sdl3])
common_dep = declare_dependency(link_with: common, dependencies: [translator_dep, sdl3])

executable('oogpu-check', 'oogpu-check.c', dependencies: [common_dep, spirv_tools], link_language: 'cpp')

# The OpenGL reference renderer needs a compatibility (2.1) context.
if host_machine.system() == 'darwin'
    gl = dependency('appleframeworks', modules: ['OpenGL'])
else
    gl = dependency('gl')
endif
executable('oogpu-render', 'oogpu-render.c', dependencies: [common_dep, gl, cc.find_library('m', required: false)],
    link_language: 'cpp')
