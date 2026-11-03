# Linux specific
add_project_arguments('-ggdb3', '-DLINUX', language: c_family)
oolite_link_args += ['-ggdb3']

oolite_dependencies += [
    dependency('gl'),
    dependency('glu'),
    dependency('x11'),
]

fs = import('fs')
project_root = meson.project_source_root()
shared_roots = [
    fs.expanduser('~') / '.local',
    '/usr/local',
    '/usr',
    '/app'
]

# =====================================================================
# LIBOBJC2 BLOCK (Scan & Resolve). The Objective-C runtime is all that is left of the GNUstep
# stack: the Foundation library left the build with oo-qps.18 (ADR-0055).
# =====================================================================
gs_search_roots = [project_root / 'build/gnustep'] + shared_roots
found_gs_dir = ''
found_gs_inc = ''

foreach root : gs_search_roots
    if found_gs_dir == ''
        foreach sub_dir : ['lib', 'lib64']
            current_dir = root / sub_dir
            if fs.is_file(current_dir / 'libobjc.so') or fs.is_file(current_dir / 'libobjc.a')
                gnustep_folder = root
                found_gs_dir = current_dir
                found_gs_inc = root / 'include'
                break
            endif
        endforeach
    endif
endforeach

if found_gs_dir != ''
    objc_lib = cc.find_library('objc', dirs: [found_gs_dir], required: true)
else
    error('Required dependency "libobjc2" was not found in SEARCH_ROOTS.')
endif

inc_dir = include_directories(found_gs_inc, is_system: true)
oolite_dependencies += declare_dependency(
    dependencies: [objc_lib],
    include_directories: inc_dir,
)
