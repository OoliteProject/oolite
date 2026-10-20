#!/usr/bin/env python3
"""Move glLight/glLightModel/glMaterial calls to the renderer layer's OOFixedFunction API.

Usage: migrate_fixed_function.py <file> [<first line>-<last line> ...]

Converts single-line OOGL(...)-wrapped or bare calls with constant enums:
  glLightfv(GL_LIGHTn, GL_AMBIENT|GL_DIFFUSE|GL_SPECULAR, v) -> OORendererSetLightColor
  glLightfv(GL_LIGHTn, GL_POSITION, v)                      -> OOGLSetLightPosition (current modelview)
  glLightModelfv(GL_LIGHT_MODEL_AMBIENT, v)                 -> OORendererSetLightModelAmbient
  glMaterialfv(face, GL_<colour>, v)                        -> OORendererSetMaterialColor
  glMateriali/glMaterialf(face, GL_SHININESS, v)            -> OORendererSetMaterialShininess
Face may be GL_FRONT, GL_BACK, GL_FRONT_AND_BACK or a macro that is
#defined to one of them in the same file. Lists calls it can't convert.
"""
import re
import sys

LIGHT_COLORS = {"GL_AMBIENT": "kOOLightAmbient", "GL_DIFFUSE": "kOOLightDiffuse", "GL_SPECULAR": "kOOLightSpecular"}
MATERIAL_COLORS = {"GL_AMBIENT": "kOOMaterialAmbient", "GL_DIFFUSE": "kOOMaterialDiffuse", "GL_SPECULAR": "kOOMaterialSpecular",
                   "GL_EMISSION": "kOOMaterialEmission", "GL_AMBIENT_AND_DIFFUSE": "kOOMaterialAmbientAndDiffuse"}
FACES = {"GL_FRONT": "kOOMaterialFront", "GL_BACK": "kOOMaterialBack", "GL_FRONT_AND_BACK": "kOOMaterialFrontAndBack"}

WRAPPED = r"(?:OOGL\(\s*)?{call}(?:\s*\))?;"
LIGHT = re.compile(WRAPPED.format(call=r"glLightfv\(\s*GL_LIGHT(\d)\s*,\s*(GL_\w+)\s*,\s*([^;]+?)\s*\)"))
MODEL = re.compile(WRAPPED.format(call=r"glLightModelfv\(\s*GL_LIGHT_MODEL_AMBIENT\s*,\s*([^;]+?)\s*\)"))
MATERIAL = re.compile(WRAPPED.format(call=r"glMaterialfv\(\s*(\w+)\s*,\s*(GL_\w+)\s*,\s*([^;]+?)\s*\)"))
SHININESS = re.compile(WRAPPED.format(call=r"glMaterial[if]\(\s*(\w+)\s*,\s*GL_SHININESS\s*,\s*([^;]+?)\s*\)"))
LEFTOVER = re.compile(r"\bgl(?:Light|LightModel|Material)\w*\(")
HEADERS = ['#import "OOFixedFunction.h"', '#import "OOOpenGLMatrixManager.h"']


def main():
    path = sys.argv[1]
    ranges = [tuple(int(x) for x in r.split("-")) for r in sys.argv[2:]]
    text = open(path, encoding="utf-8").read()
    faces = dict(FACES)
    for name, value in re.findall(r"#define\s+(\w+)\s+(GL_FRONT_AND_BACK|GL_FRONT|GL_BACK)\b", text):
        faces[name] = FACES[value]
    lines = text.split("\n")
    changed, problems = 0, []

    def light(m):
        n, param, v = m.groups()
        if param == "GL_POSITION":
            return f"OOGLSetLightPosition({n}, {v});"
        if param in LIGHT_COLORS:
            return f"OORendererSetLightColor({n}, {LIGHT_COLORS[param]}, {v});"
        return m.group(0)

    def material(m):
        face, param, v = m.groups()
        if face in faces and param in MATERIAL_COLORS:
            return f"OORendererSetMaterialColor({faces[face]}, {MATERIAL_COLORS[param]}, {v});"
        return m.group(0)

    def shininess(m):
        face, v = m.groups()
        return f"OORendererSetMaterialShininess({faces[face]}, {v});" if face in faces else m.group(0)

    for i, line in enumerate(lines):
        n = i + 1
        if (ranges and not any(a <= n <= b for a, b in ranges)) or line.lstrip().startswith("//"):
            continue
        new = LIGHT.sub(light, line)
        new = MODEL.sub(lambda m: f"OORendererSetLightModelAmbient({m.group(1)});", new)
        new = MATERIAL.sub(material, new)
        new = SHININESS.sub(shininess, new)
        if new != line:
            lines[i] = new
            changed += 1
        if LEFTOVER.search(lines[i]) and "glGet" not in lines[i]:
            problems.append(f"{path}:{n}: {lines[i].strip()}")

    if changed:
        imports = [i for i, l in enumerate(lines) if l.startswith("#import ")]
        for header in HEADERS:
            if header not in lines and imports:
                lines.insert(imports[-1] + 1, header)
    open(path, "w", encoding="utf-8").write("\n".join(lines))
    print(f"{path}: {changed} lines changed, {len(problems)} left for review")
    for p in problems:
        print("  " + p)


if __name__ == "__main__":
    main()
