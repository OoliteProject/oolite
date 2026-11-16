# oofnd unit tests: meson test -C build/meson_<type> --suite oofnd
#
# One executable per test_*.cpp, plain C++20 on the in-tree oo_test.hpp harness. Add a new test
# file's name here as well: tools/check-oofnd.sh fails when a test_*.cpp is missing from this list.

oofnd_tests = [
    'test_expected',
    'test_ref',
    'test_weakset',
    'test_data',
    'test_filesystem',
    'test_resourcepaths',
    'test_cocoa_macros',
    'test_notification',
    'test_date',
    'test_stdlib',
    'test_process',
    'test_thread',
    'test_defaults',
    'test_foundation_types',
    'test_string',
    'test_string_compare',
    'test_encoding',
    'test_log',
]

foreach t : oofnd_tests
    exe = executable(
        'oofnd_' + t,
        t + '.cpp',
        dependencies: oofnd_dep,
        override_options: oofnd_override_options,
        install: false,
    )
    test(t, exe, suite: 'oofnd', timeout: 60)
endforeach

# The PList component (value type, old-style and XML parsers, writers) is also its own suite:
# meson test -C build/meson_<type> --suite oofnd-plist
oofnd_plist_tests = [
    'test_plist',
    'test_plist_oldstyle_strings',
    'test_plist_oldstyle_structures',
    'test_plist_writers',
    'test_plist_xml',
    'test_plist_get',
]

foreach t : oofnd_plist_tests
    exe = executable(
        'oofnd_' + t,
        t + '.cpp',
        dependencies: oofnd_dep,
        override_options: oofnd_override_options,
        install: false,
    )
    test(t, exe, suite: ['oofnd', 'oofnd-plist'], timeout: 60)
endforeach

# Objective-C++ tests of the Foundation-free floor (oofnd/objc, proposed ADR-0029). They link
# libobjc2 and nothing from gnustep-base; tools/check-oofnd-objc.sh proves that on the import
# table. -fuse-ld=lld comes from the native file (clang.ini): GNU ld cannot link the gnustep-2 ABI.
oofnd_objc_tests = [
    'test_objc_floor',
    'test_objc_runtime',
    'test_objc_exception',
    'test_objc_ref',
]

foreach t : oofnd_objc_tests
    exe = executable(
        'oofnd_' + t,
        t + '.mm',
        dependencies: oofnd_objc_dep,
        objcpp_args: oofnd_objc_args,
        override_options: oofnd_override_options + ['objcpp_std=c++20'],
        install: false,
    )
    test(t, exe, suite: 'oofnd', timeout: 60)
endforeach
