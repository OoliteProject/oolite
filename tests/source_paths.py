"""Find a game source file by its STEM, whatever language it is currently written in.

Tests that pin engine source text (a log format string, a switch case, a single assignment) used
to open files by their literal name, ``PlayerEntity.m``. The migration renames those files as it
goes - every ``.m`` became ``.mm`` in one step (bead oo-x7o) and Phase 3 renames them again to
``.cpp`` - and each rename turned a source-text guard into a collection error or, worse, into a
tree walk that silently found nothing. This module is the one place that knows which suffixes an
implementation file may carry, so the next rename is a change here and not in every test.

Stdlib only; imported by the GUI tier (upstream/oolite/tests/gui) and the golden tier
(tests/golden), both of which put this directory on ``pythonpath`` in their pytest.ini.

It never guesses. ``resolve_source`` returns the ONE existing file with that stem; none, or more
than one (a half-finished rename leaving both ``X.m`` and ``X.mm``), is an error that names every
candidate, because a guard reading the wrong copy would pin stale text and stay green.
"""

import os

# Suffixes an implementation file may carry, in migration order. A header keeps its own name.
IMPLEMENTATION_SUFFIXES = (".m", ".mm", ".cpp", ".c")
HEADER_SUFFIXES = (".h", ".hpp")
# Everything a tree-wide source scan must read. A scan that filters on a literal (".m", ".h")
# reads only the headers once the .m files are gone, and "exactly one site" becomes "zero".
SOURCE_SUFFIXES = IMPLEMENTATION_SUFFIXES + HEADER_SUFFIXES

OOLITE_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(OOLITE_ROOT, "src")


def source_stem(path):
    """``path`` with any implementation suffix removed and ``/`` separators.

    ``Core/Entities/PlayerEntityControls.mm`` and ``Core\\Entities\\PlayerEntityControls.m``
    both give ``Core/Entities/PlayerEntityControls``, so a site found by a tree walk can be
    compared with a site named in a test without either side knowing the current suffix.
    Headers keep their suffix: ``X.h`` and ``X.mm`` are different files.
    """
    path = path.replace("\\", "/")
    root, ext = os.path.splitext(path)
    return root if ext in IMPLEMENTATION_SUFFIXES else path


def resolve_source(*parts):
    """The existing implementation file for a stem under ``src/``.

    ``resolve_source("Core", "Entities", "PlayerEntity")`` - a trailing implementation suffix on
    the last part (``"PlayerEntity.m"``) is accepted and ignored, so a call site can keep the
    name it was written against. An absolute first part is used as-is instead of ``src/``.
    """
    stem = source_stem(os.path.join(SRC_DIR, *parts))
    candidates = [stem + suffix for suffix in IMPLEMENTATION_SUFFIXES]
    found = [path for path in candidates if os.path.isfile(path)]
    if not found:
        raise FileNotFoundError(
            "no implementation file for stem %s; tried %s" % (stem, ", ".join(candidates)))
    if len(found) > 1:
        raise LookupError(
            "more than one implementation file for stem %s: %s. A rename left both behind; a "
            "source-text guard cannot tell which one the build compiles" % (stem, ", ".join(found)))
    return os.path.normpath(found[0])


def iter_source_files(root=SRC_DIR, suffixes=SOURCE_SUFFIXES):
    """Every file under ``root`` whose name ends in one of ``suffixes``, in a stable order."""
    for directory, dirs, files in os.walk(root):
        dirs.sort()
        for name in sorted(files):
            if name.endswith(suffixes):
                yield os.path.join(directory, name)
