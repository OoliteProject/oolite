#!/usr/bin/env python3
"""Find vertices that would be emitted into the wrong kind of batch.

Usage: audit_immediate.py [<source dir>]   (default: src)

Mixing the two APIs fails silently: a raw glVertex inside an
OOImmediateBegin/End batch is dropped (no glBegin is active), and an
OOImmediateVertex inside a raw glBegin/glEnd batch asserts in debug builds
and is lost in release builds. Batches often span functions (a helper emits
vertices, its caller opens the batch), so this works per function:

- an "emitter" is a function that emits vertices without opening a batch;
- each batch is checked for calls to emitters of the other API.

Function bodies are found with a brace-matching scan of top-level C
functions and Objective-C methods, which is enough for Oolite's style.
Prints every mismatch and exits 1 if there are any.
"""
import os
import re
import sys

RAW_VERTEX = re.compile(r"\bglVertex[234][fdis]v?\s*\(")
# GLVertexOOVector/GLVertexOOHPVector are macros around OOImmediateVertex3f.
OO_VERTEX = re.compile(r"\b(?:OOImmediateVertex\w*|GLVertexOO(?:HP)?Vector)\s*\(")
RAW_BEGIN = re.compile(r"\b(?:glBegin|OOGLBEGIN)\s*\(")
RAW_END = re.compile(r"\b(?:glEnd|OOGLEND)\s*\(")
OO_BEGIN = re.compile(r"\bOOImmediateBegin\s*\(")
OO_END = re.compile(r"\bOOImmediateEnd\s*\(")
C_FUNC = re.compile(r"^(?:static\s+|OOINLINE\s+|inline\s+)*[A-Za-z_][\w\s\*]*?\b([A-Za-z_]\w*)\s*\([^;]*$")
OBJC_METHOD = re.compile(r"^[-+]\s*\([^)]*\)\s*([A-Za-z_]\w*)")
CALL = re.compile(r"\b([A-Za-z_]\w*)\s*\(")
MESSAGE = re.compile(r"\[\s*[^\]\s]+\s+([A-Za-z_]\w*)")
COMMENT = re.compile(r"//.*?$|/\*.*?\*/", re.S | re.M)
STRING = re.compile(r'@?"(?:\\.|[^"\\])*"')


def functions(path):
    """Yield (name, first line, body text) for each function or method."""
    text = open(path, encoding="utf-8", errors="replace").read()
    text = COMMENT.sub(lambda m: re.sub(r"[^\n]", " ", m.group(0)), text)
    text = STRING.sub('""', text)
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        m = OBJC_METHOD.match(line) or (C_FUNC.match(line) if line[:1].isalpha() else None)
        if not m:
            i += 1
            continue
        name, start = m.group(1), i
        # Find the opening brace (possibly a few lines down), then match.
        j, depth, opened = i, 0, False
        body = []
        while j < len(lines):
            for ch in lines[j]:
                if ch == "{":
                    depth += 1
                    opened = True
                elif ch == "}":
                    depth -= 1
            body.append(lines[j])
            if lines[j].rstrip().endswith(";") and not opened:
                break  # a declaration, not a definition
            if opened and depth == 0:
                break
            j += 1
        if opened:
            yield name, start + 1, "\n".join(body)
        i = j + 1


def batches(body, begin, end):
    """Yield the text between each begin and its end."""
    pos = 0
    while True:
        b = begin.search(body, pos)
        if not b:
            return
        e = end.search(body, b.end())
        if not e:
            yield body[b.end():]
            return
        yield body[b.end():e.start()]
        pos = e.end()


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "src"
    funcs = []
    for dirpath, _, files in os.walk(root):
        for f in files:
            if f.endswith((".m", ".c", ".h")):
                path = os.path.join(dirpath, f)
                funcs.extend((path, *fn) for fn in functions(path))

    raw_emitters, oo_emitters = {}, {}
    for path, name, line, body in funcs:
        if RAW_VERTEX.search(body) and not RAW_BEGIN.search(body):
            raw_emitters[name] = f"{path}:{line}"
        if OO_VERTEX.search(body) and not OO_BEGIN.search(body):
            oo_emitters[name] = f"{path}:{line}"

    problems = []
    for path, name, line, body in funcs:
        for batch in batches(body, OO_BEGIN, OO_END):
            if RAW_VERTEX.search(batch):
                problems.append(f"{path}:{line} {name}: raw glVertex inside an OOImmediate batch")
            for callee in set(CALL.findall(batch)) | set(MESSAGE.findall(batch)):
                if callee in raw_emitters and callee != name:
                    problems.append(f"{path}:{line} {name}: OOImmediate batch calls raw emitter {callee} ({raw_emitters[callee]})")
        for batch in batches(body, RAW_BEGIN, RAW_END):
            if OO_VERTEX.search(batch):
                problems.append(f"{path}:{line} {name}: OOImmediateVertex inside a raw glBegin batch")
            for callee in set(CALL.findall(batch)) | set(MESSAGE.findall(batch)):
                if callee in oo_emitters and callee != name:
                    problems.append(f"{path}:{line} {name}: raw glBegin batch calls OOImmediate emitter {callee} ({oo_emitters[callee]})")

    print(f"{len(funcs)} functions scanned; emitters without their own batch: "
          f"{len(raw_emitters)} raw GL, {len(oo_emitters)} OOImmediate")
    for name, where in sorted(oo_emitters.items()):
        print(f"  OOImmediate emitter: {name} ({where})")
    for p in sorted(set(problems)):
        print(p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
