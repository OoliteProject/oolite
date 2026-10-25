project(
    'oolite',
    ['c', 'cpp'],	# the Objective-C languages went with libobjc2 (bead oo-dbz.5): every game unit is C++
    meson_version: '>= 1.4.0',
    version: run_command(
        'bash',
        files('ShellScripts/common/get_version.sh'),
        meson.project_build_root(),
        check: true,
    ).stdout().strip(),
    default_options: [
        # PINNED -O FOR GOLDEN BUILDS (decision 11, see tests/golden/GOLDEN_STORAGE.md).
        # A golden blessed at one optimisation level is not comparable to a run at another:
        # -O changes vectorisation width, reassociation opportunities and inlining, all of
        # which move the low-order bits of float results. This is the level the stored
        # goldens under goldens/<platform>/ were produced at, and
        # tests/golden/check_build_flags.py asserts the configured build really uses it.
        'optimization=2',
    ],
)

host_os = host_machine.system()
c_family = ['c', 'cpp']

version_string = meson.project_version()
cat_cmd = find_program('cat', required: true)
version_file = meson.project_build_root() / '.meson_version'
cat_result = run_command(cat_cmd, version_file, check: true)
version_vars = {}
file_contents = cat_result.stdout().strip()

foreach line : file_contents.split('\n')
    parts = line.split('=')
    key = parts[0].strip()
    value = parts[1].strip('"\' ')
    version_vars += { key : value }
endforeach
add_project_arguments(
    '-DOO_VERSION_FULL="@0@"'.format(version_string),
    '-DOO_BUILD_DATE="@0@"'.format(version_vars.get('app_date')),
    '-DOO_BUILDER="@0@"'.format(version_vars.get('builder')),
    language: c_family,
)

is_debug = (get_option('optimization') == '0' or get_option('debug'))
if is_debug
    add_project_arguments(
        '-O0',
        '-DDEBUG',
        '-DOO_DEBUG',
        '-DOO_CHECK_GL_HEAVY=1',
        language: c_family,
    )
endif

# FLOATING-POINT CONTRACTION IS OFF FOR EVERY BUILD (decision 11).
#
# clang's default is -ffp-contract=on, which lets it fuse `a*b + c` into a single FMA
# instruction. FMA rounds ONCE instead of twice, so the fused and unfused forms give
# genuinely different doubles - measured on this toolchain (clang 22.1.8, ucrt64) with
# a=0.1, b=0.3, c=-0.03 read from argv so nothing is constant-folded:
#   -ffp-contract=off   0 vfmadd in the asm, result 0
#   -ffp-contract=fast  2 vfmadd in the asm, result 1.665334536937734749e-18
# Whether the fusion happens is a function of the target's instruction set and of what the
# optimiser felt like doing, i.e. of the machine and the compiler version - exactly the
# variation a cross-platform golden must not inherit.
#
# This pin is the FIRST line of defence; float quantisation in the dump (dump_state.js
# QUANT_DECIMALS) is the second. They are coupled on purpose: the pin removes the large,
# structural discrepancies that no sane quantisation could absorb, so the quantisation only
# has to absorb ordinary last-bit noise. See tests/golden/GOLDEN_STORAGE.md.
#
# It is applied UNCONDITIONALLY, not only for golden builds: a flag that is only on in one
# configuration is a flag whose absence nobody notices.
#
# GLOBAL, not project, arguments (bead oo-5pr): QuickJS-ng is a meson subproject linked into the
# game binary, its number code produces floats that land in the dumps, and project arguments do
# not reach a subproject (nor does a subproject() c_args default option).
add_global_arguments('-ffp-contract=off', language: c_family)

# (A message to an undeclared method was an error, -Werror=objc-method-access, proposed ADR-0050,
# bead oo-tk0w, while the game sent Objective-C messages. No unit is Objective-C since bead oo-dbz.5:
# a call to an undeclared C++ member is a compile error by itself.)

if get_option('no_shaders')
    add_project_arguments('-DNO_SHADERS=1', language: c_family)
endif

if get_option('deployment_release')
    add_project_arguments(
        '-DNDEBUG',
        '-DOO_CHECK_GL_HEAVY=0',
        '-DOO_OXP_VERIFIER_ENABLED=0',
        '-DOO_LOCALIZATION_TOOLS=0',
        '-DDEBUG_GRAPHVIZ=0',
        '-DOO_FOV_INFLIGHT_CONTROL_ENABLED=0',
        language: c_family,
    )
else
    if get_option('oo_check_gl_heavy')
        add_project_arguments('-DOO_CHECK_GL_HEAVY=1', language: c_family)
    endif
    if get_option('oo_exclude_debug_support')
        add_project_arguments('-DNDEBUG', language: c_family)
    endif
    if get_option('oo_oxp_verifier_enabled')
        add_project_arguments('-DOO_OXP_VERIFIER_ENABLED=1', language: c_family)
    endif
    if get_option('oo_localization_tools')
        add_project_arguments('-DOO_LOCALIZATION_TOOLS=1', language: c_family)
    endif
    if get_option('debug_graphviz')
        add_project_arguments('-DDEBUG_GRAPHVIZ=1', language: c_family)
    endif
    if get_option('oo_fov_inflight_control_enabled')
        add_project_arguments(
            '-DOO_FOV_INFLIGHT_CONTROL_ENABLED=1',
            language: c_family,
        )
    endif
endif

if get_option('dev_release')
    add_project_arguments(
        '-DDEV_RELEASE',
        language: c_family,
    )
endif

gnustep_folder = ''  # Not needed for Windows
# dependencies, compiler/linker flags and build
subdir('src')

# Unit tests that need no game build (meson test --suite oofnd).
subdir('tests/unit/oofnd')

# Unit tests of converted game classes, linked from the game's own objects (meson test --suite core).
subdir('tests/unit/core')
