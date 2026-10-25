# Windows specific

add_project_arguments(
    '-DWIN32',
    '-DXP_WIN',
    '-DWINVER=0x0A00',
    language: c_family,
)
oolite_link_args += ['-mwindows']

if ccid == 'clang' and get_option('pdb')
    add_project_arguments('-g', '-gcodeview', language: c_family)
    oolite_link_args += ['-Wl,-pdb=']
endif

dep_libs = [
    'glu32',
    'opengl32',
    'dwmapi',
    'winmm',
    'ws2_32',
    'winhttp',      # oofnd/Http.hpp, the OXZ manager's downloads (proposed ADR-0044)
    # libobjc2 went with the last Objective-C unit (bead oo-dbz.5)
]
foreach lib : dep_libs
    oolite_dependencies += [cc.find_library(lib, required: true)]
endforeach
if (ccid == 'gcc')
    add_project_arguments(
        '-DSTATIC_JS_API',
        '-D_WIN32_WINNT=0x0A00',
        language: c_family
    )
endif
