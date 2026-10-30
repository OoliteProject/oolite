# Windows specific

add_project_arguments(
    '-DWIN32',
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
    'objc',
    'gnustep-base',
]
foreach lib : dep_libs
    oolite_dependencies += [cc.find_library(lib, required: true)]
endforeach
if (ccid == 'gcc')
    add_project_arguments('-D_WIN32_WINNT=0x0A00', language: c_family)
endif
