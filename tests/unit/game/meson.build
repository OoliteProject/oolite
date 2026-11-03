# Game-side unit tests: meson test -C build/meson_<type> --suite game-unit
#
# Objective-C++ tests of game sources that still sit on gnustep-base (transitional shims), built
# with the game's own flags and libraries. Each lists the game sources it compiles in.
# tools/check-game-unit.sh builds and runs this suite.

game_unit_tests = {
    'test_defaults_bridge': files(
        '../../../src/Core/NSUserDefaults+OODefaultsBridge.mm',
        # Former NSNumber (OOExtensions) TU retired; boolean identity is inlined in oo::PListFrom.
    ),
}

foreach t, sources : game_unit_tests
    exe = executable(
        'game_' + t,
        t + '.mm',
        sources,
        include_directories: [oolite_includes, include_directories('../oofnd')],
        dependencies: oolite_dependencies,
        override_options: oolite_override_options,
        install: false,
    )
    test(t, exe, suite: 'game-unit', timeout: 60)
endforeach
