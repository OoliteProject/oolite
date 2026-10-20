#!/usr/bin/env python3
"""Move GL immediate-mode calls to the renderer layer's OOImmediate API.

Usage: migrate_immediate.py <file> [<first line>-<last line> ...]

Rewrites glBegin/glEnd (and OOGLBEGIN/OOGLEND), glVertex, glColor,
glTexCoord2f and glNormal3f calls in the given line ranges (the whole file by
default), and adds the OOImmediateMode.h import. Primitive modes must be GL_*
constants; anything else is reported and left alone. Prints a summary and
the lines it couldn't convert.
"""
import re
import sys

MODES = {
    "GL_POINTS": "kOOPrimitivePoints",
    "GL_LINES": "kOOPrimitiveLines",
    "GL_LINE_STRIP": "kOOPrimitiveLineStrip",
    "GL_LINE_LOOP": "kOOPrimitiveLineLoop",
    "GL_TRIANGLES": "kOOPrimitiveTriangles",
    "GL_TRIANGLE_STRIP": "kOOPrimitiveTriangleStrip",
    "GL_TRIANGLE_FAN": "kOOPrimitiveTriangleFan",
    "GL_QUADS": "kOOPrimitiveQuads",
    "GL_QUAD_STRIP": "kOOPrimitiveQuadStrip",
    "GL_POLYGON": "kOOPrimitivePolygon",
}

FUNCTIONS = {
    "glVertex2f": "OOImmediateVertex2f",
    "glVertex3f": "OOImmediateVertex3f",
    "glVertex3fv": "OOImmediateVertex3fv",
    # Integer arguments convert to float implicitly.
    "glVertex2i": "OOImmediateVertex2f",
    "glVertex3i": "OOImmediateVertex3f",
    "glColor3f": "OOImmediateColor3f",
    "glColor4f": "OOImmediateColor4f",
    "glColor4fv": "OOImmediateColor4fv",
    "glTexCoord2f": "OOImmediateTexCoord2f",
    "glNormal3f": "OOImmediateNormal3f",
}

# Calls wrapped in OOGL(...): OOGL(glColor4f(a, b, c, d)); -> OOImmediateColor4f(a, b, c, d);
OOGL_WRAPPED = re.compile(r"OOGL\((gl(?:Vertex[23][fi]v?|Color[34]fv?|TexCoord2f|Normal3f))\((.*)\)\);")
BEGIN = re.compile(r"\b(?:OOGLBEGIN|glBegin)\(\s*(\w+)\s*\)")
END = re.compile(r"\b(?:OOGLEND|glEnd)\(\s*\)")
CALL = re.compile(r"\b(" + "|".join(sorted(FUNCTIONS, key=len, reverse=True)) + r")\(")
LEFTOVER = re.compile(r"\b(glBegin|glEnd|OOGLBEGIN|OOGLEND|glVertex\w+|glColor\w+|glTexCoord\w+|glNormal\w+)\b")


def in_ranges(n, ranges):
    return not ranges or any(a <= n <= b for a, b in ranges)


def top_level_imports(lines):
    """Indices of #import lines outside any #if block, so an insertion after
    them isn't compiled out in some configurations."""
    depth, found = 0, []
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("#if"):
            depth += 1
        elif stripped.startswith("#endif"):
            depth -= 1
        elif stripped.startswith("#import ") and depth == 0:
            found.append(i)
    return found


def main():
    path = sys.argv[1]
    ranges = [tuple(int(x) for x in r.split("-")) for r in sys.argv[2:]]
    lines = open(path, encoding="utf-8").read().split("\n")
    changed, problems = 0, []
    for i, line in enumerate(lines):
        n = i + 1
        if not in_ranges(n, ranges) or line.lstrip().startswith("//"):
            continue
        new = OOGL_WRAPPED.sub(lambda m: f"{FUNCTIONS[m.group(1)]}({m.group(2)});", line)
        new = BEGIN.sub(lambda m: f"OOImmediateBegin({MODES[m.group(1)]})" if m.group(1) in MODES else m.group(0), new)
        new = END.sub("OOImmediateEnd()", new)
        new = CALL.sub(lambda m: FUNCTIONS[m.group(1)] + "(", new)
        if new != line:
            lines[i] = new
            changed += 1
        if LEFTOVER.search(lines[i]):
            problems.append(f"{path}:{n}: {lines[i].strip()}")

    text = "\n".join(lines)
    if changed and '#import "OOImmediateMode.h"' not in text:
        imports = top_level_imports(lines)
        if imports:
            lines.insert(imports[-1] + 1, '#import "OOImmediateMode.h"')
            text = "\n".join(lines)
    open(path, "w", encoding="utf-8").write(text)
    print(f"{path}: {changed} lines changed, {len(problems)} left for review")
    for p in problems:
        print("  " + p)


if __name__ == "__main__":
    main()
