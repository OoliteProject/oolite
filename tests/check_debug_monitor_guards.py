#!/usr/bin/env python3
"""Debug-monitor code is guarded by OO_DEBUG_MONITOR_ENABLED, never by NDEBUG.

Upstream #756 ("Debug monitor enabled in release build") builds the debug monitor into the
deployment flavour, which also defines NDEBUG, and so moved every guard on debug-monitor code
from !NDEBUG to OO_DEBUG_MONITOR_ENABLED. A guard left on NDEBUG compiles that code out of the
shipped game while the monitor that uses it stays in, and no build flavour reports it: the test
flavours define neither NDEBUG nor (usually) leave the monitor out. This check fails on

  - a conditional that pairs OO_SHADERS with NDEBUG: #756's form for the shader-uniform binding
    code the monitor inspects is `#if OO_SHADERS || defined(OO_DEBUG_MONITOR_ENABLED)`;
  - a line naming something upstream declares only under OO_DEBUG_MONITOR_ENABLED (MONITOR_NAMES)
    inside a block whose condition tests NDEBUG and not OO_DEBUG_MONITOR_ENABLED.

Plain NDEBUG asserts and sanity checks, which upstream still guards with NDEBUG, are untouched.

    python3 tests/check_debug_monitor_guards.py [--root DIR]

Scope: src/Core, src/SDL and src/oofnd, less vendored code, with comments and literals blanked.
Prints one 'path:line: reason' per hit; exit 1 if any, 0 if none.
"""

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCAN_DIRS = ("src/Core", "src/SDL", "src/oofnd")
SUFFIXES = (".h", ".hpp", ".cpp")
VENDORED = (
    "src/Core/MiniZip",
    "src/SDL/EXRSnapshotSupport",
    "src/SDL/stb_image_write.h",
    "src/Core/OOPlanetData.cpp",
)


def strip_comments_and_literals(text):
    """Blank comments, string literals and character literals, keeping every newline.

    A comment becomes one space; "..." becomes "" and '...' becomes ''. Raw strings R"x(...)x" and
    C++14 digit separators (1'000) are understood, so neither confuses the scan.
    """
    out = []
    i = 0
    n = len(text)

    def skip_newlines(chunk):
        out.append("\n" * chunk.count("\n"))

    while i < n:
        c = text[i]
        two = text[i : i + 2]
        if two == "//":
            j = i
            while j < n and text[j] != "\n":
                if text[j] == "\\" and j + 1 < n and text[j + 1] in "\r\n":
                    j += 2  # a backslash-newline continues a line comment
                    if text[j - 1] == "\r" and j < n and text[j] == "\n":
                        j += 1
                    continue
                j += 1
            out.append(" ")
            skip_newlines(text[i:j])
            i = j
        elif two == "/*":
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(" ")
            skip_newlines(text[i:j])
            i = j
        elif c == '"':
            # Raw string: the quote is preceded by R (optionally with an encoding prefix).
            m = re.match(r'"([^()\\\s"]{0,16})\(', text[i:])
            if m and i > 0 and text[i - 1] == "R":
                close = ")" + m.group(1) + '"'
                j = text.find(close, i + m.end())
                j = n if j < 0 else j + len(close)
                out.append('""')
                skip_newlines(text[i:j])
                i = j
                continue
            j = i + 1
            while j < n and text[j] != '"':
                if text[j] == "\\":
                    j += 1
                elif text[j] == "\n":
                    break  # an unterminated literal ends with its line
                j += 1
            j = min(j + 1, n)
            out.append('""')
            skip_newlines(text[i:j])
            i = j
        elif c == "'":
            k = i - 1
            while k >= 0 and (text[k].isalnum() or text[k] in "_'"):
                k -= 1
            if k < i - 1 and text[k + 1].isdigit():
                out.append(c)  # a digit separator, not a character literal
                i += 1
                continue
            j = i + 1
            while j < n and text[j] != "'":
                if text[j] == "\\":
                    j += 1
                elif text[j] == "\n":
                    break
                j += 1
            j = min(j + 1, n)
            out.append("''")
            skip_newlines(text[i:j])
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def logical_lines(stripped_text):
    """Yield (first_line_number, text) for each logical line (backslash continuations joined)."""
    lines = stripped_text.split("\n")
    i = 0
    while i < len(lines):
        start = i
        joined = lines[i]
        while joined.rstrip().endswith("\\") and i + 1 < len(lines):
            i += 1
            joined = joined.rstrip()[:-1] + " " + lines[i]
        yield start + 1, joined
        i += 1


def source_files(root):
    """[(relative path, stripped text)] for every file in scope."""
    found = []
    for top in SCAN_DIRS:
        for directory, dirs, files in os.walk(os.path.join(root, top)):
            dirs.sort()
            for name in sorted(files):
                if not name.endswith(SUFFIXES):
                    continue
                rel = os.path.relpath(os.path.join(directory, name), root).replace(os.sep, "/")
                if any(rel == v or rel.startswith(v + "/") for v in VENDORED):
                    continue
                with open(os.path.join(root, rel), "rb") as handle:
                    raw = handle.read().decode("utf-8", errors="replace")
                raw = raw.replace("\r\n", "\n").replace("\r", "\n")
                found.append((rel, strip_comments_and_literals(raw)))
    return found

# Names upstream (7437f22a5) declares or defines only under OO_DEBUG_MONITOR_ENABLED.
MONITOR_NAMES = (
    "OOSetShaderEntityHooks",  # OOShaderUniformMethodType.h, #756's OO_SHADERS || monitor guard
    "OODebugMonitor",
    "gDebugFlags",
    "dumpSelfState",
    "descriptionForObjDump",
    "gLiveEntityCount",
    "gTotalEntityMemory",
    "n_key_dump_target_state",
    "n_key_dump_entity_list",
    r"n_key_debug_\w+",
)
MONITOR = re.compile(r"\b(" + "|".join(MONITOR_NAMES) + r")\b")
NDEBUG = re.compile(r"\bNDEBUG\b")
SHADERS = re.compile(r"\bOO_SHADERS\b")
MONITOR_MACRO = re.compile(r"\bOO_DEBUG_MONITOR_ENABLED\b")
DIRECTIVE = re.compile(r"^\s*#\s*(if|ifdef|ifndef|elif|else|endif)\b(.*)$")


def hits_in(stripped):
    """[(line, reason)] for one file's comment-stripped text."""
    hits = []
    stack = []  # the condition text of each enclosing conditional's current branch
    for number, line in logical_lines(stripped):
        m = DIRECTIVE.match(line)
        if m:
            kind, rest = m.group(1), m.group(2)
            if kind in ("if", "ifdef", "ifndef", "elif"):
                if SHADERS.search(rest) and NDEBUG.search(rest):
                    hits.append((number, "OO_SHADERS paired with NDEBUG, not OO_DEBUG_MONITOR_ENABLED"))
            if kind in ("if", "ifdef", "ifndef"):
                stack.append(rest)
            elif kind == "elif" and stack:
                stack[-1] = stack[-1] + " " + rest
            elif kind == "endif" and stack:
                stack.pop()
            continue
        if not MONITOR.search(line):
            continue
        guards = [c for c in stack if NDEBUG.search(c) and not MONITOR_MACRO.search(c)]
        if guards and not any(MONITOR_MACRO.search(c) for c in stack):
            name = MONITOR.search(line).group(1)
            hits.append((number, "%s under an NDEBUG guard, not OO_DEBUG_MONITOR_ENABLED" % name))
    return hits


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--root", help="oolite-dev tree to check (default: this script's)")
    args = parser.parse_args(argv)
    root = os.path.abspath(args.root) if args.root else ROOT
    found = 0
    for rel, stripped in source_files(root):
        for number, reason in hits_in(stripped):
            print("%s:%d: %s" % (rel, number, reason))
            found += 1
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
