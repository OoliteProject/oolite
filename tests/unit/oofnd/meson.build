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
    'test_localized_compare',
    'test_string_sweep',
    'test_string_path_extension',
    'test_string_format_runtime',
    'test_encoding',
    'test_scanner',
    'test_unicode_file',
    'test_unicode_file_decode',
    'test_log',
    'test_logfile',
    'test_tcp_stream_format',
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

# oofnd/Http.hpp links WinHTTP on Windows, and its test runs a loopback server on winsock
# (bead oo-3rb.13, proposed ADR-0044). tools/check-oofnd.sh reads the same libraries from the
# test's "// oofnd-link-windows:" line.
oofnd_http_link_args = host_machine.system() == 'windows' ? ['-lwinhttp', '-lws2_32'] : []
test('test_http',
    executable(
        'oofnd_test_http',
        'test_http.cpp',
        dependencies: oofnd_dep,
        link_args: oofnd_http_link_args,
        override_options: oofnd_override_options,
        install: false,
    ),
    suite: 'oofnd',
    timeout: 60,
)

# The PList component (value type, old-style and XML parsers, writers) is also its own suite:
# meson test -C build/meson_<type> --suite oofnd-plist
oofnd_plist_tests = [
    'test_plist',
    'test_plist_oldstyle_strings',
    'test_plist_oldstyle_structures',
    'test_plist_writers',
    'test_plist_xml',
    'test_plist_get',
    'test_plist_carrier',
    'test_plist_game_tuples',
    'test_plist_description',
    'test_plist_hdr_brightness_index',
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

# Tests of what is left of the Foundation-free floor (oofnd/objc, proposed ADR-0029). Objective-C++
# on libobjc2 until bead oo-dbz.5; C++ since, linking neither libobjc2 nor gnustep-base, which
# tools/check-oofnd-objc.sh proves on the import table.
# test_objc_exception retired with the Objective-C OOException class (bead oo-4aq6a.1, Jon approved 2026-10-19).
oofnd_objc_tests = [
    # test_objc_floor retired with its only subject, the OOObject root class, OOConstantString and OOObjCInstallFloor() (bead oo-4aq6a.8, std-2026-10-19)
    # test_objc_runtime retired with its only subject, oofnd/objc/OORuntime.h's libobjc2 class and selector lookups (bead oo-dbz.4, std-2026-10-19)
    'test_objc_assert',
    # test_objc_ref retired with its only subject, oofnd/objc/OOObjCRef.h's reference to an Objective-C object (bead oo-dbz.4, std-2026-10-19)
    # test_objc_call_by_name retired with its only subject, src/Core/OOCallByName.mm's call on an Objective-C object (bead oo-6e1.2, std-2026-10-19)
    # test_objc_description retired with OODescription.mm's OOObject (OODescription) (bead oo-8sql7, ADR-0049; Jon approved 2026-10-19)
    # test_objc_plist retired with its only subject, src/Core/OOObjCPList.h's Objective-C object node (bead oo-4aq6a.5, std-2026-10-19)
    # test_objc_peer retired with its only subject, oofnd/objc/OOObjCPeer.h (bead oo-4aq6a.9, std-2026-10-19)
]

foreach t : oofnd_objc_tests
    exe = executable(
        'oofnd_' + t,
        t + '.cpp',
        dependencies: oofnd_objc_dep,
        # (objcpp_args, the floor's -fno-constant-cfstrings, and objcpp_std=c++20 went with libobjc2, bead oo-dbz.5)
        override_options: oofnd_override_options,
        install: false,
    )
    test(t, exe, suite: 'oofnd', timeout: 60)
endforeach
