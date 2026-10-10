# Darwin (macOS) specific — Apple Foundation + Apple ld. No GNUstep.
#
# Foundation is hard-selected: there is deliberately no 'foundation' build
# option (upstream doctrine — no speculative second-config surface). The
# GNUstep-on-macOS path survives only as the coexistence-probe contingency
# documented in the port notes, not as a build configuration; its code is
# preserved in this file's git history and in src/meson/linux/meson.build.

add_project_arguments('-DXP_UNIX', language: c_family)

# NOTE: -DLINUX is deliberately NOT set. OOFoundation.h maps "#ifdef LINUX"
# to OOLITE_LINUX=1, which would misdefine the platform on darwin.

oolite_dependencies += declare_dependency(link_args: [
    '-framework', 'OpenGL', '-framework', 'Cocoa', '-framework', 'CoreAudio',
    '-framework', 'AudioToolbox', '-framework', 'AudioUnit', '-framework',
    'IOKit', '-framework', 'Carbon', '-framework', 'Foundation',
    '-framework', 'CoreServices',
])
# Defensive: the ObjC runtime is not guaranteed transitive through Foundation.
oolite_dependencies += cc.find_library('objc', required: true)

# Apple Foundation path. House prefix is OOLITE_MACOS_, not OO_.
# - OOLITE_SDL must come from the command line: OOFoundation.h defines it only
#   under OOLITE_GNUSTEP, and its #ifndef fallback is 0 — without this define
#   the SDL backend silently compiles away.
# - GL_GLEXT_PROTOTYPES makes SDL3's vendored glext header supply the
#   GL 3.0-era prototypes/tokens that Apple's legacy gl.h omits; without it
#   OOOpenGLOnly.h fails to compile.
# - OOLITE_MAC_APPKIT is deliberately NOT defined here. It lives only in
#   OOFoundation.h as a compound macro (with #ifndef->0 fallback); defining it
#   on the command line too is a redefinition-warning storm.
# - OOLITE_NO_CGL_MACRO keeps OO_ENTER_OPENGL a no-op: the Meson tree's GL
#   call sites follow the portable pattern (plain GL functions), not the
#   Xcode backend's OO_ENTER_OPENGL discipline the CGL macros require, and
#   the CGL macro table is mutually exclusive with the GL 3.3 core renderer
#   (Apple's CGLMacro.h #errors if gl3.h was included first).
add_project_arguments(
    '-DOOLITE_MACOS_APPLE_FOUNDATION=1',
    '-DOOLITE_SDL=1',
    '-DGL_GLEXT_PROTOTYPES=1',
    '-DOOLITE_NO_CGL_MACRO=1',
    language: c_family,
)

# Apple-Foundation compatibility shims (src/Core/Compat/OOFoundationCompat.h,
# included by OOFoundation.h under OOLITE_MACOS_APPLE_FOUNDATION). Entries are
# strictly audit-driven; the header documents the rules.
oolite_includes += include_directories('../../../src/Core/Compat')
# Spelling note: meson rejects absolute paths into the source tree ("Tried to
# form an absolute path to a dir in the source tree"), so the path is relative
# to THIS subdir (src/meson/darwin/): three levels up is the project root.

fs = import('fs')
project_root = meson.project_source_root()

# =====================================================================
# MOZILLA JS BLOCK (Scan & Resolve)
# =====================================================================
# Pinned to the release artifact name on BOTH flavors: jsdbg_static is never
# packaged (the debug artifact ships the same js_static lib — darwin debug
# builds link the release lib).
js_name = 'js_static'
js_search_roots = [
    project_root / 'build/mozilla_js',
    fs.expanduser('~') / '.local',
    '/usr/local',
]
found_js_dir = ''
found_js_inc = ''

foreach root : js_search_roots
    if found_js_dir == ''
        foreach sub_dir : ['lib', 'lib64']
            current_dir = root / sub_dir
            if fs.is_file(current_dir / 'lib' + js_name + '.a')
                found_js_dir = current_dir
                found_js_inc = root / 'include'
                break
            endif
        endforeach
    endif
endforeach

if found_js_dir != ''
    js_lib = cc.find_library(js_name, dirs: [found_js_dir], static: true, required: true)
    # Meson rejects absolute include paths into the source tree ("Tried to
    # form an absolute path to a dir in the source tree"), and the primary
    # artifact root (build/mozilla_js) is in-tree. Spell that case relative to
    # THIS subdir (src/meson/darwin/); out-of-tree roots pass through as-is.
    if found_js_dir.startswith(project_root)
        js_inc = '../../../' + fs.relative_to(found_js_inc, project_root)
    else
        js_inc = found_js_inc
    endif
    oolite_includes += include_directories(js_inc, is_system: true)
    oolite_dependencies += declare_dependency(dependencies: [js_lib])
else
    error('Required dependency "@0@" was not found in SEARCH_ROOTS. Run ShellScripts/Darwin/install_mozilla_js.sh to fetch the prebuilt artifact.'.format(js_name))
endif
