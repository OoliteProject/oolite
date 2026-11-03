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
oofnd_override_options = ['cpp_std=c++20', 'warning_level=2', 'werror=true']
oofnd_dep = declare_dependency(include_directories: oofnd_inc)

# The Foundation-free Objective-C floor (bead oo-3rb.1, proposed ADR-0029): the OOObject root
# class and the OOConstantString class behind @"..." literals, on libobjc2 alone. Linked into the game
# since oo-3rb.2 (src/meson.build) WITHOUT oofnd_objc_args: the game keeps gnustep-base's
# NSConstantString until the flip (oo-3rb.4). Test consumers
# (today only tests/unit/oofnd/test_objc_floor.mm) must compile with oofnd_objc_args.
oofnd_objc_args = ['-fno-constant-cfstrings', '-fconstant-string-class=OOConstantString']
oofnd_objc_dep = declare_dependency(
    include_directories: oofnd_inc,
    sources: files('objc/OOObject.mm', 'objc/OOConstantString.mm', 'objc/OOException.mm'),
    dependencies: cc.find_library('objc', required: true),
)
