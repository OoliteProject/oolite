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

Scope and comment handling are idiom_check.py's (src/Core, src/SDL, src/oofnd; comments and
literals blanked). Prints one 'path:line: reason' per hit; exit 1 if any, 0 if none.
"""

import argparse
import os
import re
import sys

import idiom_check

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
    for number, line in idiom_check.logical_lines(stripped):
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
    if args.root:
        idiom_check.ROOT = os.path.abspath(args.root)
    found = 0
    for rel, _, stripped in idiom_check.source_files():
        for number, reason in hits_in(stripped):
            print("%s:%d: %s" % (rel, number, reason))
            found += 1
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
