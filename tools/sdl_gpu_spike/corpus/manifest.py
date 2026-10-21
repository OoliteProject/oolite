#!/usr/bin/env python3
"""Build an oogpu-check manifest from the fetched OXP configs.

Every (vertex_shader, fragment_shader) pair referenced from a shaders/materials
dictionary in any Config/*.plist becomes one program. Shader names resolve
first inside the same OXP's Shaders/ directory, then in Oolite's bundled
Resources/Shaders, then in any other OXP (standing in for dependencies).

Usage: manifest.py <corpus dir> <oolite checkout> <ship prefix file> <out.tsv>
"""
import glob, json, os, re, subprocess, sys

HERE = os.path.abspath(sys.argv[1])
OOLITE = sys.argv[2]
PREFIX = sys.argv[3]  # ship macro prefix file
OUT = sys.argv[4]


def load_plist(path):
    try:
        out = subprocess.run(["plutil", "-convert", "json", "-o", "-", path], capture_output=True, timeout=30)
        if out.returncode == 0:
            return json.loads(out.stdout)
    except Exception:  # noqa: BLE001
        pass
    return None


def walk(node, found):
    if isinstance(node, dict):
        if "vertex_shader" in node or "fragment_shader" in node:
            found.add((node.get("vertex_shader"), node.get("fragment_shader")))
        for v in node.values():
            walk(v, found)
    elif isinstance(node, list):
        for v in node:
            walk(v, found)


def regex_pairs(text):
    # Fallback for plists plutil rejects: pair shader names within one {...}.
    found = set()
    for block in re.findall(r"\{[^{}]*(?:vertex_shader|fragment_shader)[^{}]*\}", text, re.S):
        vs = re.search(r'vertex_shader\s*=\s*"?([^";\s]+)', block)
        fs = re.search(r'fragment_shader\s*=\s*"?([^";\s]+)', block)
        found.add((vs.group(1) if vs else None, fs.group(1) if fs else None))
    return found


# Shaders by lower-case name, per OXP and across all OXPs (for shaders that
# come from a dependency, as with a real AddOns folder).
LOCAL, GLOBAL = {}, {}
for path in glob.glob(os.path.join(HERE, "oxz", "*", "**", "*"), recursive=True):
    parts = path.replace("\\", "/").split("/")
    if os.path.isfile(path) and parts[-2].lower() == "shaders":
        oxp = os.path.join(HERE, "oxz", os.path.relpath(path, os.path.join(HERE, "oxz")).split(os.sep)[0])
        LOCAL.setdefault(oxp, {})[parts[-1].lower()] = path
        GLOBAL.setdefault(parts[-1].lower(), path)


def resolve(oxp, name):
    if not name:
        return "-"
    key = name.lower()
    if key in LOCAL.get(oxp, {}):
        return LOCAL[oxp][key]
    bundled = os.path.join(OOLITE, "Resources", "Shaders", name)
    if os.path.exists(bundled):
        return bundled
    return GLOBAL.get(key)


lines, unresolved, parse_fail = [], 0, 0
for oxp in sorted(glob.glob(os.path.join(HERE, "oxz", "*"))):
    pairs = set()
    for plist in glob.glob(os.path.join(oxp, "**", "*.plist"), recursive=True):
        if "/config/" not in plist.lower().replace("\\", "/"):
            continue
        data = load_plist(plist)
        if data is not None:
            walk(data, pairs)
        else:
            text = open(plist, encoding="utf-8", errors="replace").read()
            if "_shader" in text:
                parse_fail += 1
                pairs |= regex_pairs(text)
    for vs, fs in sorted(pairs, key=lambda p: (p[0] or "", p[1] or "")):
        vp, fp = resolve(oxp, vs), resolve(oxp, fs)
        if vp is None or fp is None:
            unresolved += 1
            continue
        label = f"{os.path.basename(oxp)}:{vs or '-'}+{fs or '-'}"
        lines.append(f"{label}\t{vp}\t{fp}\t{PREFIX}")

open(OUT, "w").write("\n".join(lines) + "\n")
print(f"{len(lines)} programs, {unresolved} pairs with missing files, {parse_fail} plists parsed by regex", file=sys.stderr)
