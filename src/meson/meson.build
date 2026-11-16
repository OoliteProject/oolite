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

# QuickJS-ng adds dependency('threads') (-pthread) to its link line, and every target
# that links it. The MinGW clang driver does not use -pthread when linking (cutils.h takes Win32
# threads under _WIN32), so each link printed "argument unused during compilation: '-pthread'".
# On Windows the threads dependency is the same compile flag without the unused link flag, so the
# objects and the links are unchanged and the driver has nothing to report.
if host_machine.system() == 'windows'
    meson.override_dependency('threads', declare_dependency(compile_args: ['-pthread']))
endif
oolite_dependencies += dependency(
    'quickjs-ng',
    version: '>=0.17.0',
    # A system header for the game: its macros' C-style casts are not the game's (-Wold-style-cast).
    include_type: 'system',
    # No LTO for QuickJS: with clang on Windows (MSYS2), the static library's
    # LTO objects are archived without a symbol index, so linking fails.
    # Warning level 2 (QuickJS defaults to 3) leaves out -Wpedantic, which
    # clang uses to flag QuickJS's "return f();" in void functions.
    # QuickJS-ng is part of the game binary, so it is held to the same flag policy as
    # Oolite's own code (meson.build): its dtoa/number code
    # produces floats that land in the dumps. Its own project() defaults to buildtype=release
    # (-O3), which the project-wide optimization=2 does not reach. Pass optimization=2 explicitly
    # so the last -O on each QuickJS compile line is the pinned level; b_ndebug=true keeps release
    # NDEBUG semantics.
    default_options: [
        'default_library=static',
        'libc=false',
        'b_lto=false',
        'warning_level=2',
        'buildtype=debugoptimized',
        'optimization=2',
        'b_ndebug=true',
    ],
)

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
