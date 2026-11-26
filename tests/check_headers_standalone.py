#!/usr/bin/env python3
"""Every game header compiles on its own: include order must not matter.

For each header under src/ and tests/ that the configured build actually uses (it appears in some object's
dependency file), compile a translation unit containing only `#include "<header>"`, with the exact
command of one source file that includes it. A header that relies on something its includer
happened to include first fails here, before a reformat that sorts includes exposes it.

Headers that may only be reached through an umbrella header (`#error Do not include X directly`)
are checked through that umbrella instead.

    python3 tests/check_headers_standalone.py [build/meson_debug] [-j N] [-v]

Needs a built (not just configured) build directory: ninja's dependency log says which headers
the build uses. Exit 0 when every header
compiles, 1 otherwise.
"""

import argparse
import concurrent.futures
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Headers that are deliberately not self-contained, each with the reason. Keep this short: a header
# belongs here only when its includer must supply something by design.
FRAGMENTS = {
    # Generated tables that OOEntityCalledByName.cpp pastes into the middle of itself, after the
    # declarations they use; tools/gen-entity-by-name-table.py checks them byte for byte.
    "src/Core/Entities/OOEntityCalledByNameTable.h": "generated table fragment",
    "src/Core/Entities/OOEntityObjectNamesTable.h": "generated table fragment",
    # Uses whichever Entity its includer declared: the game's (via OOJSEntity.h) or a unit test's
    # own stand-in class, which is why it cannot include Entity.h itself.
    "src/Core/Scripting/OOJSEntityHolder.h": "Entity supplied by the includer",
    # Each test declares its entity's oo::ToObjC() and friends, then includes this mid-file.
    "tests/unit/core/EntityHelpersStandIn.h": "test stand-in, parameterised by its includer",
}
UMBRELLA_RE = re.compile(r'#error Do not include \S+ directly; include (\S+?)\.?$', re.M)


def real(path, base):
    return os.path.normpath(os.path.join(base, path))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("build_dir", nargs="?", default=os.path.join(ROOT, "build", "meson_debug"))
    ap.add_argument("-j", type=int, default=os.cpu_count() or 4)
    ap.add_argument("-v", action="store_true", help="print each header as it passes")
    args = ap.parse_args()
    build = os.path.abspath(args.build_dir)
    with open(os.path.join(build, "compile_commands.json"), encoding="utf-8") as f:
        db = json.load(f)

    roots = tuple(os.path.normcase(os.path.join(ROOT, d)) + os.sep for d in ("src", "tests"))
    skip = {os.path.normcase(os.path.join(ROOT, f)) for f in FRAGMENTS}
    cxx = (".cpp", ".cc", ".cxx", ".mm")
    by_output = {}
    for entry in db:
        argv = shlex.split(entry["command"], posix=True)
        if "-o" in argv:
            by_output[os.path.normcase(os.path.normpath(argv[argv.index("-o") + 1]))] = (entry, argv)
    # ninja folds each object's .d file into its own log and deletes it; `ninja -t deps` reads it back.
    deps = subprocess.run(["ninja", "-C", build, "-t", "deps"], capture_output=True, text=True,
                          check=True).stdout
    # header (as spelled on disk) -> (entry, argv) of a source file that includes it, a C++ one
    # if there is one: a header C++ uses is checked as C++, a C-only header as C.
    owner = {}
    current = None
    for line in deps.splitlines():
        if line and not line[0].isspace():
            current = by_output.get(os.path.normcase(os.path.normpath(line.split(": #deps")[0])))
        elif current and line.strip():
            h = real(line.strip(), current[0]["directory"])
            if (os.path.normcase(h).startswith(roots) and h.endswith((".h", ".hpp"))
                    and os.path.normcase(h) not in skip):
                key = os.path.normcase(h)
                if key not in owner or (current[0]["file"].endswith(cxx)
                                        and not owner[key][1][0]["file"].endswith(cxx)):
                    owner[key] = (h, current)
    if not owner:
        sys.exit(f"no dependency information in {build}: build it first (ninja -C {build})")

    def check(key):
        header, (entry, argv) = owner[key]
        with open(header, encoding="utf-8", errors="replace") as f:
            m = UMBRELLA_RE.search(f.read())
        target = m.group(1) if m else os.path.basename(header)
        include_dir = os.path.dirname(header)
        fd, tu = tempfile.mkstemp(suffix=os.path.splitext(entry["file"])[1], dir=entry["directory"], prefix="hdrcheck_")
        with os.fdopen(fd, "w") as f:
            f.write(f'#include "{os.path.join(include_dir, target).replace(os.sep, "/")}"\n')
        cmd = []
        skip = 0
        for a in argv:
            if skip:
                skip -= 1
                continue
            if a in ("-o", "-MF", "-MQ", "-MT"):
                skip = 1
                continue
            if a in ("-c", "-MD", "-MMD") or a == entry["file"] or a.startswith("-fdiagnostics-color"):
                continue
            cmd.append(a)
        cmd += ["-fsyntax-only", tu]
        try:
            r = subprocess.run(cmd, cwd=entry["directory"], capture_output=True, text=True)
        finally:
            os.unlink(tu)
        return header, target if m else None, r.returncode, r.stderr

    failed = 0
    with concurrent.futures.ThreadPoolExecutor(args.j) as ex:
        for header, via, rc, err in sorted(ex.map(check, sorted(owner))):
            rel = os.path.relpath(header, ROOT).replace(os.sep, "/")
            label = f"{rel} (via {via})" if via else rel
            if rc:
                failed += 1
                first = [l for l in err.splitlines() if "error:" in l][:3]
                print(f"FAIL {label}")
                for l in first:
                    print(f"     {l.strip()}")
            elif args.v:
                print(f"ok   {label}")
    print(f"{len(owner) - failed}/{len(owner)} headers compile on their own")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
