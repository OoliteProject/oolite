# icosmesh generates src/Core/OOPlanetData.{cpp,h}. To regenerate after changing the generator:
#   build/meson_<type>/tools/icosmesh/icosmesh src/Core
# then run clang-format on the two files.
#
# The vertex set merges vertices by their exact bits, so the arithmetic must round the same
# everywhere. -ffp-contract=off stops the compiler fusing a*b+c into one FMA instruction, as clang
# does by default on arm64 (macOS); fused, the rounding differs and 20 vertices fail to merge.
icosmesh = executable('icosmesh', 'icosmesh.cpp',
    native: true, install: false, override_options: ['cpp_std=c++23', 'warning_level=2'],
    cpp_args: ['-ffp-contract=off'])
