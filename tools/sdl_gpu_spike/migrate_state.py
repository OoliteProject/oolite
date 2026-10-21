#!/usr/bin/env python3
"""Move OpenGL state calls to the OOGL* wrappers in OOGLStateCompat.h.

Usage: migrate_state.py <file>...

Renames glEnable, glDisable, glBlendFunc, glDepthMask, glDepthFunc,
glCullFace, glFrontFace, glShadeModel, glPolygonMode, glScissor,
glActiveTexture(ARB), glBindTexture, glDeleteTextures, glTexEnv*, glUseProgramObjectARB,
glPushAttrib and glPopAttrib calls, drops a now-redundant OOGL(...) around
them, and adds the OOGLStateCompat.h import outside any #if block.
"""
import re
import sys

RENAMES = {
    "glEnable": "OOGLEnable",
    "glDisable": "OOGLDisable",
    "glBlendFunc": "OOGLBlendFunc",
    "glDepthMask": "OOGLDepthMask",
    "glDepthFunc": "OOGLDepthFunc",
    "glCullFace": "OOGLCullFace",
    "glFrontFace": "OOGLFrontFace",
    "glShadeModel": "OOGLShadeModel",
    "glPolygonMode": "OOGLPolygonMode",
    "glScissor": "OOGLScissor",
    "glActiveTextureARB": "OOGLActiveTexture",
    "glActiveTexture": "OOGLActiveTexture",
    "glBindTexture": "OOGLBindTexture",
    "glDeleteTextures": "OOGLDeleteTextures",
    "glTexEnvi": "OOGLTexEnvi",
    "glTexEnvf": "OOGLTexEnvf",
    "glTexEnvfv": "OOGLTexEnvfv",
    "glUseProgramObjectARB": "OOGLUseProgramObject",
    "glPushAttrib": "OOGLPushAttrib",
    "glPopAttrib": "OOGLPopAttrib",
}
CALL = re.compile(r"\b(" + "|".join(sorted(RENAMES, key=len, reverse=True)) + r")\s*\(")
UNWRAP = re.compile(r"OOGL\(\s*(OOGL(?:" + "|".join(sorted({v[4:] for v in RENAMES.values()}, key=len, reverse=True)) + r")\(.*\))\s*\);")
HEADER = '#import "OOGLStateCompat.h"'


def top_level_imports(lines):
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


def migrate(path):
    lines = open(path, encoding="utf-8").read().split("\n")
    changed = 0
    for i, line in enumerate(lines):
        stripped = line.lstrip()
        if stripped.startswith("//") or stripped.startswith("#define"):
            continue
        new = CALL.sub(lambda m: RENAMES[m.group(1)] + "(", line)
        new = UNWRAP.sub(r"\1;", new)
        if new != line:
            lines[i] = new
            changed += 1
    if changed and HEADER not in lines:
        imports = top_level_imports(lines)
        if imports:
            lines.insert(imports[-1] + 1, HEADER)
    open(path, "w", encoding="utf-8").write("\n".join(lines))
    return changed


if __name__ == "__main__":
    for path in sys.argv[1:]:
        n = migrate(path)
        if n:
            print(f"{path}: {n} lines changed")
