cc = meson.get_compiler('c')
ccid = cc.get_id()

if (host_os == 'windows' or host_os == 'cygwin')
    subdir('windows')
else
    subdir('linux')
endif

if ccid == 'gcc'
    oolite_override_options += 'c_std=gnu99'
endif

if get_option('b_lto')
    if ccid == 'clang'
        add_project_arguments('-flto=thin', language: c_family)
        oolite_link_args += [
            '-flto=thin',
            '-Wl,--thinlto-cache-dir=thinlto_cache',
        ]
    else
        add_project_arguments('-flto=auto', language: c_family)
        oolite_link_args += ['-flto=auto']
    endif
endif

add_project_arguments(
    '-DGNUSTEP_BASE_LIBRARY=1',
    language: c_family,
)
# The Objective-C and Objective-C++ arguments (the libobjc2 runtime ABI, Objective-C exceptions,
# blocks) went with the languages, bead oo-dbz.5: every game unit is C++, which has exceptions by
# default.
