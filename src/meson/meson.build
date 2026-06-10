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
add_project_arguments(
    '-fexceptions',
    '-fobjc-exceptions',
    language: 'objc',
)

if ccid == 'clang'
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
