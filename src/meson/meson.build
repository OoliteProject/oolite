cc = meson.get_compiler('c')
ccid = cc.get_id()

if (host_os == 'windows' or host_os == 'cygwin')
    subdir('windows')
elif host_os == 'darwin'
    subdir('darwin')
else
    subdir('linux')
endif

if ccid == 'gcc'
    oolite_override_options += 'c_std=gnu99'
endif

if get_option('b_lto')
    if ccid == 'clang'
        add_project_arguments('-flto=thin', language: c_family)
        oolite_link_args += ['-flto=thin']
        if host_os != 'darwin'
            oolite_link_args += ['-Wl,--thinlto-cache-dir=thinlto_cache']
        endif
    else
        add_project_arguments('-flto=auto', language: c_family)
        oolite_link_args += ['-flto=auto']
    endif
endif

if host_os != 'darwin'
    add_project_arguments(
        '-DGNUSTEP_BASE_LIBRARY=1',
        language: c_family,
    )
endif
add_project_arguments(
    '-fexceptions',
    '-fobjc-exceptions',
    language: 'objc',
)

if host_os == 'darwin'
    # Apple Foundation and the Apple Objective-C runtime (manual retain/release).
    add_project_arguments('-fblocks', language: 'objc')
elif ccid == 'clang'
    add_project_arguments(
        '-DGNUSTEP_RUNTIME=1',
        '-D_NONFRAGILE_ABI=1',
        '-fobjc-runtime=gnustep-2.2',
        '-fblocks',
        language: 'objc',
    )
else
    add_project_arguments(
        '-DGNU_RUNTIME=1',
        '-fconstant-string-class=NSConstantString',
        language: 'objc',
    )
endif
