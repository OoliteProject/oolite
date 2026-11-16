cc = meson.get_compiler('c')
ccid = cc.get_id()
use_quickjs = get_option('js_engine') == 'quickjs'

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

if use_quickjs
    quickjs_dep = dependency(
        'quickjs-ng',
        version: '>=0.17.0',
        # No LTO for QuickJS: with clang on Windows (MSYS2), the static library's
        # LTO objects are archived without a symbol index, so linking fails.
        # Warning level 2 (QuickJS defaults to 3) leaves out -Wpedantic, which
        # clang uses to flag QuickJS's "return f();" in void functions.
        default_options: ['default_library=static', 'libc=false', 'b_lto=false', 'warning_level=2'],
    )
    oolite_dependencies += quickjs_dep
    add_project_arguments('-DOOJS_QUICKJS=1', language: c_family)
    # Oolite's QuickJS-ng patch 0004 adds the function call hook the profiler
    # uses to time JavaScript functions. A system QuickJS-ng, or a subproject
    # checkout made before the patch was added, lacks it.
    # (Compiler checks can't use a subproject's dependency, so read its header.)
    if quickjs_dep.type_name() == 'internal'
        quickjs_has_call_hook = import('fs').read(
            meson.project_source_root() / 'subprojects' / 'quickjs-ng' / 'quickjs.h',
        ).contains('JS_SetFunctionCallHook')
    else
        quickjs_has_call_hook = cc.has_header_symbol('quickjs.h', 'JS_SetFunctionCallHook', dependencies: quickjs_dep)
    endif
    if quickjs_has_call_hook
        add_project_arguments('-DOOJS_QUICKJS_CALL_HOOK=1', language: c_family)
    elif quickjs_dep.type_name() == 'internal'
        warning('subprojects/quickjs-ng predates Oolite\'s function call hook patch, so the profiler will time natives only. Run "meson subprojects update --reset quickjs-ng" and rebuild.')
    else
        warning('This QuickJS-ng lacks Oolite\'s function call hook patch, so the profiler will time natives only.')
    endif
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
