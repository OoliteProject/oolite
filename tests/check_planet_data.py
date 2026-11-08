#!/usr/bin/env python3
"""src/Core/OOPlanetData.{cpp,h} are exactly what tools/icosmesh generates.

Runs the icosmesh generator into a temporary directory and compares its output with the
checked-in files, ignoring whitespace (the checked-in files are clang-formatted; the generator
writes its own layout). Any other difference — a vertex, an index, a texture coordinate, a count —
fails.

    python3 tests/check_planet_data.py <icosmesh executable> <source root>

Exit 1 on a difference, with the first differing position; 0 when both files match.
"""

import os
import re
import subprocess
import sys
import tempfile


def squeeze(text):
    return re.sub(r"\s+", "", text)


def main():
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    generator, root = os.path.abspath(sys.argv[1]), sys.argv[2]
    failed = False
    with tempfile.TemporaryDirectory() as out:
        subprocess.run([generator, out], check=True)
        for name in ("OOPlanetData.h", "OOPlanetData.cpp"):
            with open(os.path.join(out, name), encoding="utf-8") as f:
                generated = squeeze(f.read())
            with open(os.path.join(root, "src", "Core", name), encoding="utf-8") as f:
                checked_in = squeeze(f.read())
            if generated == checked_in:
                print(f"{name}: matches")
                continue
            failed = True
            at = next((i for i, (a, b) in enumerate(zip(generated, checked_in)) if a != b),
                      min(len(generated), len(checked_in)))
            print(f"{name}: differs at character {at} (whitespace removed):\n"
                  f"  generated:  ...{generated[max(0, at - 40):at + 40]}...\n"
                  f"  checked in: ...{checked_in[max(0, at - 40):at + 40]}...")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
