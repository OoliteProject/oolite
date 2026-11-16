# oofnd — the Foundation replacement (Phase 2, docs/architecture.md §3.4).
#
# Header-first C++20: every component so far is header-only, so oofnd is an include path and
# nothing more. Consumers write #include "oofnd/Expected.hpp" and depend on oofnd_dep. When a
# component needs a .cpp, add it here as a static library and fold it into oofnd_dep, e.g.
#
#     oofnd_lib = static_library('oofnd', files('PList.cpp'),
#                                include_directories: oofnd_inc,
#                                override_options: oofnd_override_options)
#     oofnd_dep = declare_dependency(include_directories: oofnd_inc, link_with: oofnd_lib)
#
# The unit tests are tests/unit/oofnd (meson test --suite oofnd); tools/check-oofnd.sh is the
# build-dir-free acceptance that compiles the same files directly.

oofnd_inc = include_directories('..')
# werror under Clang only (ADR-0063 item 4, decided 2026-10-21): GCC's flow-sensitive diagnostics
# fire inside libstdc++ inlines on correct test code (test_plist.cpp, test_ref.cpp). Under GCC the
# warnings still print; nothing is suppressed.
oofnd_override_options = ['cpp_std=c++20', 'warning_level=2',
    'werror=' + (meson.get_compiler('cpp').get_id() == 'gcc' ? 'false' : 'true')]
# ICU: oo::str::localizedCompare (String.hpp) collates with it, as GNUstep's -localizedCompare:
# does (bead oo-r4d6). GNUstep-base already links the same ICU, so the game gains no new DLL.
# icu-uc is named too: String.hpp calls it directly (uloc_getDefault, unorm2_*), and icu-i18n.pc
# lists it only under Requires.private, so a shared link on Linux does not get -licuuc from i18n.
oofnd_icu_dep = [dependency('icu-uc', required: true), dependency('icu-i18n', required: true)]
oofnd_dep = declare_dependency(include_directories: oofnd_inc, dependencies: oofnd_icu_dep)

# What is left of the Objective-C floor (bead oo-3rb.1, proposed ADR-0029): oofnd/objc's C++ support,
# OORaiseException (Exception.cpp) and OOCAssert's failure path. Its OOObject root class and
# OOConstantString went with bead oo-4aq6a.8; libobjc2 itself and -fno-constant-cfstrings with bead
# oo-dbz.5 (no unit is Objective-C). Test consumers: tests/unit/oofnd/test_objc_assert.cpp.
oofnd_objc_dep = declare_dependency(
    include_directories: oofnd_inc,
    sources: files('Exception.cpp', 'objc/OOAssert.cpp'),
)
