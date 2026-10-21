# Renderer layer for the move to SDL_GPU (issue #579).

oolite_sources += files(
    'OOFixedFunction.c',
    'OOGLStateCompat.m',
    'OOImmediateMode.c',
    'OORenderPass.c',
    'OORenderState.c',
    'OORenderStateMachine.c',
    'OORendererLog.m',
    'OORendererTexture.m',
    'OOTextureUpload.c',
    'OOVertexArray.c',
)

if get_option('renderer') == 'sdl_gpu'
    # SDL_GPU, with Oolite's and OXPs' GLSL translated by glslang and SPIRV-Cross.
    oolite_sources += files('OOGLSLTranslator.c', 'OORendererSDLGPU.c')
    add_project_arguments('-DOO_RENDERER_SDL_GPU=1', language: ['c', 'objc'])

    cc = meson.get_compiler('c')
    brew_lib = ['/opt/homebrew/lib', '/usr/local/lib', '/usr/lib', '/usr/lib64']
    # Homebrew's glslang ships no pkg-config file; look for the libraries directly.
    glslang = dependency('glslang', required: false)
    if glslang.found()
        # Debian's static glslang also needs the SPIRV-Tools optimiser.
        glslang = declare_dependency(dependencies: [glslang, cc.find_library('glslang-default-resource-limits'),
            cc.find_library('SPIRV-Tools-opt', required: false), dependency('SPIRV-Tools-shared', 'SPIRV-Tools', required: false)])
    else
        glslang_include = run_command('sh', '-c',
            'for d in /opt/homebrew/include /usr/local/include /usr/include /ucrt64/include /mingw64/include; do [ -d $d/glslang ] && echo $d && break; done',
            check: true).stdout().strip()
        glslang = declare_dependency(
            dependencies: [cc.find_library('glslang', dirs: brew_lib), cc.find_library('glslang-default-resource-limits', dirs: brew_lib)],
            include_directories: include_directories(glslang_include, is_system: true))
    endif
    # Prefer the shared SPIRV-Cross C library (Debian, Ubuntu); the static one
    # (Homebrew) needs its backend libraries listed by hand.
    spirv_cross = dependency('spirv-cross-c-shared', required: false)
    if not spirv_cross.found()
        spirv_cross_libs = [dependency('spirv-cross-c')]
        foreach lib : ['msl', 'hlsl', 'cpp', 'glsl', 'reflect', 'util', 'core']
            spirv_cross_libs += cc.find_library('spirv-cross-' + lib, dirs: brew_lib, static: true)
        endforeach
        spirv_cross = declare_dependency(dependencies: spirv_cross_libs)
    endif
    # Both are C++ libraries behind C interfaces.
    oolite_dependencies += [glslang, spirv_cross, cc.find_library('stdc++', required: false)]
else
    oolite_sources += files('OORendererGL.c')
endif

oolite_includes += include_directories('.')
