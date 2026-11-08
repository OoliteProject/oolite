# icosmesh generates src/Core/OOPlanetData.{cpp,h}. It is built for its test
# (meson test --suite tools), which regenerates both files and compares them with the checked-in
# ones. To regenerate after changing the generator:
#   build/meson_<type>/tools/icosmesh/icosmesh src/Core
# then run clang-format on the two files.
icosmesh = executable('icosmesh', 'icosmesh.cpp',
    native: true, install: false, override_options: ['cpp_std=c++20', 'warning_level=2'])

test('planet_data_generated', find_program('python3'),
    args: [files('../../tests/check_planet_data.py'), icosmesh.full_path(), meson.project_source_root()],
    depends: icosmesh, suite: 'tools')
