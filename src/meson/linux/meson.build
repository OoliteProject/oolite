# Linux specific
add_project_arguments('-ggdb3', '-DLINUX', '-DXP_UNIX', language: c_family)
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

# (The LIBOBJC2 block, which found libobjc.so/libobjc.a under build/gnustep or the shared roots for
# the Objective-C runtime, went with the last Objective-C unit, bead oo-dbz.5.)

# The JavaScript engine is the vendored QuickJS-ng subproject (bead oo-7wx).
