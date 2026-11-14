#!/usr/bin/env python3
"""Named, comment-aware idiom checks over the game's own C++ sources.

A sweep that replaces an old idiom (NULL, (void) parameter lists, MIN/MAX macros, C casts, ...)
needs a way to prove the idiom is gone that a grep cannot give: a grep also hits comments and
string literals, and it cannot tell a real hit from the word in a doc comment. Each check here is a
regular expression run over the file text with comments and string literals removed, and the
sweep's acceptance line is "this check reports nothing".

    python3 tests/idiom_check.py <check> [--paths P ...] [--exclude E ...] [--count]
    python3 tests/idiom_check.py --list | --self-test | --all <check> [<check> ...]

Scope: src/Core, src/SDL and src/oofnd (.h .hpp .cpp), found relative to the oolite-dev root
whatever the current directory is, minus the vendored MiniZip, EXRSnapshotSupport and
stb_image_write.h and the generated OOPlanetData.cpp. --paths and --exclude take files or
directories (relative to oolite-dev); a prefix matches the path itself or anything below it.

Output is one 'path:line: text' per hit. The exit status is 1 if any hit is in scope, 0 if none,
2 for a usage error such as an unknown check. --count prints only the number of hits.

Comments (// and /* */), string literals ("..." becomes "") and character literals ('...' becomes
'') are blanked with every newline kept, so reported line numbers are the file's. A RAW check runs
on the text as written, for the idioms that live in strings (an include path, a format specifier).
The regexes are approximations; where one proves wrong on a real file, fix the regex here and say
so in the commit.

Standard library only.
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

PLATFORM_MACROS = (
    r"OOLITE_WINDOWS|OOLITE_LINUX|OOLITE_MAC_OS_X|_WIN32|_WIN64|WIN32|__APPLE__|__linux__"
    r"|OOLITE_SDL|__MINGW32__"
)


class Check:
    """One named check: a regex over (stripped or raw) text, or a SPECIAL function."""

    def __init__(self, name, description, pattern=None, raw=False, special=None):
        self.name = name
        self.description = description
        self.raw = raw
        self.special = special
        self.regex = re.compile(pattern, re.M) if pattern else None


# --- the check table ---------------------------------------------------------------------------

CHECKS = [
    Check("nullptr", "NULL in code", r"\bNULL\b"),
    Check("void-params", "(void) parameter lists", r"\w\s*\(void\)"),
    Check(
        "typedef-using",
        "typedef aliases other than enum/struct/union",
        r"\btypedef\b(?!\s+(enum|struct|union)\b)",
    ),
    Check("inline-macro", "the OOINLINE macro (uses and definition)", r"\bOOINLINE\b"),
    Check(
        "expect",
        "EXPECT/EXPECT_NOT branch hints (uses and definitions)",
        r"\bEXPECT(_NOT)?\s*\(",
    ),
    Check("minmaxabs", "MIN/MAX/ABS macros (uses and definitions)", r"\b(MIN|MAX|ABS)\s*\("),
    Check(
        "pi",
        "hand-defined M_PI family and PI",
        r"\bM_(PI|PI_2|PI_4|1_PI|2_PI|E|SQRT2)\b|\bPI\b",
    ),
    Check(
        "clamp",
        "OOClamp*/OOLerp* helpers (uses and definitions)",
        r"\bOO(Clamp\w*|Lerp\w*)\s*\(",
    ),
    Check(
        "c-headers",
        "C headers instead of <cxxx>",
        r"#\s*include\s*<(stdlib|stdint|stdio|string|math|limits|assert|stdarg|stdbool|tgmath"
        r"|errno|locale|ctype)\.h>",
    ),
    Check("mac-blocks", "the OOLITE_MAC_OS_X macro (blocks and definition)", r"OOLITE_MAC_OS_X"),
    Check(
        "dead-code-leftovers",
        "SpiderMonkey and Objective-C leftovers",
        r"MOZ_TRACE_JSCALLS|@interface|@implementation|@selector|@optional|^\s*#\s*import\b"
        r"|\bIBOutlet\b|\bIBAction\b|\bOOLITE_OPTIONAL\b|\bOO_RETURNS_RETAINED\b"
        r"|\bOO_NS_CONSUMED\b|\bCFSTR\b|\bOOALSTR\b",
    ),
    Check("extern-const", "extern const declarations", r"\bextern\s+const\b"),
    Check(
        "define-const",
        "object-like #define constants (numeric, string, bool, alias) whose name is never used "
        "in a #if/#ifdef/#ifndef/#elif/defined()",
        special="define-const",
    ),
    Check("unscoped-enum", "enum without class (includes typedef enum)", r"\benum\b(?!\s+(class|struct)\b)"),
    Check("ns-integer", "NSInteger/NSUInteger (uses and typedefs)", r"\bNS(U?Integer)\b"),
    Check(
        "ns-geometry",
        "NSPoint/NSSize/NSRect and helpers",
        r"\bNS(Point|Size|Rect|MakePoint|MakeSize|MakeRect|EqualPoints|EqualSizes|EqualRects)\b",
    ),
    Check("ns-range", "NSRange/NSMakeRange/NSNotFound", r"\bNS(Range|MakeRange|NotFound)\b"),
    Check("cxx-prefix", "cxx_ migration prefix on identifiers", r"\bcxx_\w+"),
    Check(
        "stdlib-hpp",
        "includes of the StdLib.hpp umbrella (raw text, so include strings count)",
        r"StdLib\.hpp",
        raw=True,
    ),
    Check(
        "str-format",
        "printf-style oo::str::format / formatRuntime",
        r"\bstr::format\s*\(|\bformatRuntime\s*\(",
    ),
    Check("percent-at", "%@ format specifiers (raw text)", r"%@", raw=True),
    Check(
        "ref-legacy",
        "Objective-C style Ref ownership calls",
        r"\b(autorelease|leakRef|adopt|AutoreleaseScope)\b",
    ),
    Check("malloc", "C heap calls", r"\b(malloc|calloc|realloc|free)\s*\("),
    Check("raw-new", "raw new/delete", r"(=\s*|\(|return\s+)new\s+\w|\bdelete(\[\])?\s+\w"),
    Check(
        "c-array",
        "C array declarations (approximate)",
        r"\b(?!return\b|else\b|case\b|delete\b|goto\b|new\b)[A-Za-z_][\w:<>,]*\s+[A-Za-z_]\w*"
        r"\s*\[[^\]\n]*\]\s*(=|;|,)",
    ),
    Check("c-string", "const char* and char[] C strings", r"\bconst\s+char\s*\*|\bchar\s+\w+\s*\["),
    Check(
        "c-cast",
        "C-style casts (approximate)",
        r"\(\s*(int|unsigned|float|double|long|size_t|NSUInteger|NSInteger|GLfloat|GLint|GLuint"
        r"|uint\d+_t|int\d+_t|char|short|OOScalar|\w+\s*\*)\s*\)\s*[\w(&*\-]",
    ),
    Check("out-param", "out-parameters named outFoo", r"[&*]\s*out[A-Z]\w*\s*[,)=]"),
    Check("fopen", "fopen/fclose", r"\bf(open|close)\s*\("),
    Check("rand", "rand()/srand()", r"\bs?rand\s*\("),
    Check("lock-pair", "manual mutex lock()/unlock() calls", r"\b(lock|unlock)\s*\(\s*\)\s*;"),
    Check(
        "stopwatch-platform",
        "platform clocks",
        r"mach_absolute_time|timeGetTime|gettimeofday|QueryPerformance",
    ),
    Check(
        "platform-if-in-body",
        "platform #if/#ifdef/#ifndef/#elif (" + PLATFORM_MACROS.replace("|", ", ") + ") at brace "
        "depth > 0 (depth counted over non-directive lines)",
        special="platform-if-in-body",
    ),
    Check(
        "feature-ifdef",
        "OO_* feature switches tested with ifdef/defined() instead of by value",
        r"#\s*ifn?def\s+OO_\w+|defined\s*\(\s*OO_\w+\s*\)|#\s*if\s+defined\s+OO_\w+",
    ),
    Check("endian-macro", "endian macros", r"OOLITE_(BIG|LITTLE)_ENDIAN|__(BIG|LITTLE)_ENDIAN__"),
    Check("extern-c", 'extern "C" blocks (raw text)', r'extern\s+"C"', raw=True),
    Check(
        "oo-expected",
        "oo::Expected polyfill uses (raw text)",
        r"oo::Expected|Expected\.hpp",
        raw=True,
    ),
    Check("stmt-expr", "GNU statement expressions", r"\(\s*\{"),
    Check(
        "reserved-has",
        "redefinitions of reserved __has_* names",
        r"#\s*define\s+__has_(feature|attribute|extension)\b",
    ),
    Check("expander-map", "OOStringExpander preprocessor MAP machinery", r"OOEXPAND_MAP"),
]
BY_NAME = {c.name: c for c in CHECKS}


# --- comment and literal stripping ------------------------------------------------------------


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


# --- scanning ---------------------------------------------------------------------------------


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def regex_hits(check, raw_text, stripped_text):
    """[(line, ...)] for a regex check; one per line."""
    text = raw_text if check.raw else stripped_text
    lines = sorted({line_of(text, m.start()) for m in check.regex.finditer(text)})
    return lines


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


CONDITIONAL = re.compile(r"^\s*#\s*(if|ifdef|ifndef|elif)\b(.*)$")
DEFINED = re.compile(r"\bdefined\b\s*\(?\s*([A-Za-z_]\w*)")
IDENT = re.compile(r"[A-Za-z_]\w*")
OBJECT_DEFINE = re.compile(r"^\s*#\s*define\s+([A-Za-z_]\w*)(?!\()(?:\s+(.*))?$")
CONSTANT_VALUE = re.compile(r'^(?:"|\d|-|\(|[A-Za-z_]\w*\s*$)')


def tested_names(stripped_texts):
    """Every identifier that appears on a conditional line or inside defined(...)."""
    names = set()
    for text in stripped_texts:
        for _, line in logical_lines(text):
            m = CONDITIONAL.match(line)
            if m:
                names.update(IDENT.findall(m.group(2)))
        names.update(DEFINED.findall(text))
    return names


def define_const_hits(stripped, tested):
    """Lines of object-like constant #defines whose NAME is not in ``tested``."""
    lines = []
    for number, line in logical_lines(stripped):
        m = OBJECT_DEFINE.match(line)
        if not m or m.group(1) in tested:
            continue
        value = (m.group(2) or "").strip()
        if value and CONSTANT_VALUE.match(value):
            lines.append(number)
    return lines


def platform_if_hits(stripped):
    """Lines of platform conditionals at brace depth > 0 (depth over non-directive lines)."""
    platform = re.compile(r"\b(" + PLATFORM_MACROS + r")\b")
    depth = 0
    lines = []
    in_directive = False
    for number, raw_line in enumerate(stripped.split("\n"), 1):
        directive = in_directive or raw_line.lstrip().startswith("#")
        in_directive = directive and raw_line.rstrip().endswith("\\")
        if directive:
            m = CONDITIONAL.match(raw_line)
            if m and depth > 0 and platform.search(raw_line):
                lines.append(number)
            continue
        depth += raw_line.count("{") - raw_line.count("}")
    return lines


def in_scope(rel, paths, excludes):
    def under(prefix):
        prefix = prefix.rstrip("/")
        return rel == prefix or rel.startswith(prefix + "/")

    if paths and not any(under(p) for p in paths):
        return False
    return not any(under(e) for e in excludes)


def normalise(path):
    """A user-supplied path as a forward-slash path relative to the oolite-dev root."""
    absolute = path if os.path.isabs(path) else os.path.join(ROOT, path)
    return os.path.relpath(os.path.normpath(absolute), ROOT).replace(os.sep, "/")


def source_files():
    """[(relative path, raw text, stripped text)] for every file in scope of the tool."""
    found = []
    for top in SCAN_DIRS:
        for directory, dirs, files in os.walk(os.path.join(ROOT, top)):
            dirs.sort()
            for name in sorted(files):
                if not name.endswith(SUFFIXES):
                    continue
                rel = os.path.relpath(os.path.join(directory, name), ROOT).replace(os.sep, "/")
                if any(rel == v or rel.startswith(v + "/") for v in VENDORED):
                    continue
                with open(os.path.join(ROOT, rel), "rb") as handle:
                    raw = handle.read().decode("utf-8", errors="replace")
                raw = raw.replace("\r\n", "\n").replace("\r", "\n")
                found.append((rel, raw, strip_comments_and_literals(raw)))
    return found


def run_check(check, files, paths, excludes):
    """[(rel, line, text)] hits of ``check`` in the files that are in scope."""
    tested = None
    if check.special == "define-const":
        tested = tested_names([stripped for _, _, stripped in files])
    hits = []
    for rel, raw, stripped in files:
        if not in_scope(rel, paths, excludes):
            continue
        if check.special == "define-const":
            lines = define_const_hits(stripped, tested)
        elif check.special == "platform-if-in-body":
            lines = platform_if_hits(stripped)
        else:
            lines = regex_hits(check, raw, stripped)
        raw_lines = raw.split("\n")
        for number in lines:
            hits.append((rel, number, raw_lines[number - 1].strip()))
    return hits


# --- self-test --------------------------------------------------------------------------------

# One sample per regex check that the check must report, so a mistyped pattern fails here and not
# silently in a sweep.
POSITIVE_SAMPLES = {
    "nullptr": "Foo* p = NULL;\n",
    "void-params": "int main(void) { }\n",
    "typedef-using": "typedef unsigned int Index;\n",
    "inline-macro": "OOINLINE int f(void);\n",
    "expect": "if (EXPECT_NOT(x)) {}\n",
    "minmaxabs": "int a = MAX(1, 2);\n",
    "pi": "double r = M_PI * 2;\n",
    "clamp": "x = OOClamp_0_1_f(x);\n",
    "c-headers": "#include <stdlib.h>\n",
    "mac-blocks": "#if OOLITE_MAC_OS_X\n#endif\n",
    "dead-code-leftovers": "@interface Foo\n",
    "extern-const": "extern const int kFoo;\n",
    "unscoped-enum": "enum Mode { A, B };\n",
    "ns-integer": "NSUInteger count;\n",
    "ns-geometry": "NSRect r;\n",
    "ns-range": "NSRange r;\n",
    "cxx-prefix": "void cxx_doThing();\n",
    "stdlib-hpp": '#include "oofnd/StdLib.hpp"\n',
    "str-format": "auto s = oo::str::format(\"%d\", 1);\n",
    "percent-at": 'log("%@", x);\n',
    "ref-legacy": "x.autorelease();\n",
    "malloc": "void* p = malloc(4);\n",
    "raw-new": "Foo* p = new Foo;\n",
    "c-array": "int values[4] = {};\n",
    "c-string": "const char* name = \"x\";\n",
    "c-cast": "int i = (int)f;\n",
    "out-param": "void f(int* outCount);\n",
    "fopen": "FILE* f = fopen(p, \"r\");\n",
    "rand": "int r = rand();\n",
    "lock-pair": "mutex.lock();\n",
    "stopwatch-platform": "t = gettimeofday(&tv, 0);\n",
    "feature-ifdef": "#ifdef OO_DEBUG\n#endif\n",
    "endian-macro": "#if OOLITE_BIG_ENDIAN\n#endif\n",
    "extern-c": 'extern "C" {\n}\n',
    "oo-expected": "oo::Expected<int, int> e;\n",
    "stmt-expr": "int x = ({ int y = 1; y; });\n",
    "reserved-has": "#define __has_feature(x) 0\n",
    "expander-map": "OOEXPAND_MAP(f, a)\n",
}


def self_test():
    failures = []

    def expect(condition, message):
        if not condition:
            failures.append(message)

    def hit_lines(name, text):
        check = BY_NAME[name]
        stripped = strip_comments_and_literals(text)
        if check.special == "define-const":
            return define_const_hits(stripped, tested_names([stripped]))
        if check.special == "platform-if-in-body":
            return platform_if_hits(stripped)
        return regex_hits(check, text, stripped)

    # Every table entry is covered, and each regex check reports its sample.
    for check in CHECKS:
        if check.regex is not None:
            expect(check.name in POSITIVE_SAMPLES, "no sample for check %s" % check.name)
    for name, sample in POSITIVE_SAMPLES.items():
        expect(name in BY_NAME, "sample for unknown check %s" % name)
        expect(hit_lines(name, sample) == [1] or hit_lines(name, sample), "%s misses its sample" % name)

    # Comments and string literals are not code; a RAW check sees strings.
    expect(hit_lines("nullptr", "int a = NULL;\n") == [1], "a NULL in code must be a hit")
    expect(hit_lines("nullptr", "// NULL here\n") == [], "a NULL in a // comment is not a hit")
    expect(hit_lines("nullptr", "/* NULL\n here */\n") == [], "a NULL in a block comment is not a hit")
    expect(hit_lines("nullptr", 'const std::string s = "NULL";\n') == [], "a NULL in a string is not a hit")
    expect(hit_lines("nullptr", "char c = 'N'; int a = NULL;\n") == [1], "a char literal must not hide code")
    expect(hit_lines("nullptr", "char q = '\"'; int a = NULL;\n") == [1], "a '\"' must not start a string")
    expect(hit_lines("nullptr", 'auto s = "a // b"; int a = NULL;\n') == [1], "// inside a string is not a comment")
    expect(hit_lines("nullptr", "int n = 1'000; int a = NULL;\n") == [1], "a digit separator is not a char literal")
    expect(hit_lines("nullptr", 'auto s = R"x(NULL " // )x"; int a = NULL;\n') == [1], "a raw string is one literal")
    expect(hit_lines("nullptr", "// one \\\n NULL continues the comment\n") == [], "a comment continues over backslash-newline")
    expect(hit_lines("nullptr", "/* a\n b\n c */ int a = NULL;\n") == [3], "line numbers survive a block comment")
    expect(hit_lines("stdlib-hpp", '#include "oofnd/StdLib.hpp"\n') == [1], "a RAW check must see an include string")
    expect(hit_lines("stdlib-hpp", "// StdLib.hpp\n") == [1], "a RAW check sees the text as written")
    expect(hit_lines("percent-at", 'x("%@");\n') == [1], "percent-at is raw")
    expect(hit_lines("void-params", "void f(void);\n") == [1], "(void) is a hit")
    expect(hit_lines("void-params", "void f(void*);\n") == [], "(void*) is not a (void) list")
    expect(hit_lines("typedef-using", "typedef struct Foo Foo;\n") == [], "typedef struct is allowed")
    expect(hit_lines("unscoped-enum", "enum class E { A };\n") == [], "enum class is allowed")

    # define-const: a constant whose name no #if tests is a hit; one that is tested is not.
    sample = (
        "#define KEPT 1\n"
        "#define DROPPED 2\n"
        '#define NAME "text"\n'
        "#define ALIAS other\n"
        "#define FLAG (1 << 3)\n"
        "#define FUNC(x) (x)\n"
        "#define EMPTY\n"
        "#define BODY do_something(1)\n"
        "#if KEPT\n#endif\n"
        "#if defined(FLAG)\n#endif\n"
    )
    expect(hit_lines("define-const", sample) == [2, 3, 4], "define-const finds untested constants only: %r"
           % hit_lines("define-const", sample))
    expect(define_const_hits(strip_comments_and_literals("#define A 1\n"), {"A"}) == [],
           "define-const ignores a tested name")
    expect(hit_lines("define-const", "// #define A 1\n") == [], "define-const ignores a commented define")

    # platform-if-in-body: a top-level #if is fine, one inside a function is flagged.
    top_level = "#if OOLITE_WINDOWS\nint a;\n#endif\n"
    in_body = "void f() {\n#if OOLITE_WINDOWS\n  g();\n#endif\n}\n#if _WIN32\n#endif\n"
    expect(hit_lines("platform-if-in-body", top_level) == [], "a top-level platform #if is not a hit")
    expect(hit_lines("platform-if-in-body", in_body) == [2], "a platform #if inside a function is a hit: %r"
           % hit_lines("platform-if-in-body", in_body))
    expect(hit_lines("platform-if-in-body", "void f() {\n#if FOO\n#endif\n}\n") == [],
           "a non-platform #if in a body is not a hit")
    expect(hit_lines("platform-if-in-body", "#define M { \\\n  x }\nvoid f() {\n}\n#if OOLITE_LINUX\n#endif\n") == [],
           "braces in a macro body do not count as depth")

    # Scope filters.
    expect(in_scope("src/oofnd/Expected.hpp", ["src/oofnd"], []), "a directory prefix matches below it")
    expect(in_scope("src/oofnd/Expected.hpp", ["src/oofnd/Expected.hpp"], []), "a file prefix matches itself")
    expect(not in_scope("src/oofnd2/x.hpp", ["src/oofnd"], []), "a prefix stops at a path boundary")
    expect(not in_scope("src/oofnd/a.hpp", [], ["src/oofnd"]), "--exclude removes a directory")

    for failure in failures:
        print("FAIL: " + failure)
    if failures:
        return 1
    print("self-test: %d checks, all categories pass" % len(CHECKS))
    return 0


# --- command line -----------------------------------------------------------------------------


def main(argv):
    parser = argparse.ArgumentParser(
        description="Named, comment-aware idiom checks over src/Core, src/SDL and src/oofnd.",
        epilog="Exit status: 1 if any hit is in scope, 0 if none, 2 for a usage error.",
    )
    parser.add_argument("check", nargs="?", help="the check to run (see --list)")
    parser.add_argument("--paths", nargs="+", default=[], metavar="P", help="only files under these")
    parser.add_argument("--exclude", nargs="+", default=[], metavar="E", help="skip files under these")
    parser.add_argument("--count", action="store_true", help="print only the number of hits")
    parser.add_argument("--list", action="store_true", help="list the checks and what they find")
    parser.add_argument("--self-test", action="store_true", help="prove the checks work on samples")
    parser.add_argument("--all", nargs="+", metavar="CHECK", help="run several checks")
    args = parser.parse_args(argv)

    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    if args.list:
        for check in CHECKS:
            print("%-22s %s" % (check.name, check.description))
        return 0
    if args.self_test:
        return self_test()

    names = args.all if args.all else ([args.check] if args.check else [])
    if not names:
        parser.print_usage(sys.stderr)
        return 2
    unknown = [n for n in names if n not in BY_NAME]
    if unknown:
        print("idiom_check: unknown check %s (see --list)" % ", ".join(unknown), file=sys.stderr)
        return 2

    paths = [normalise(p) for p in args.paths]
    excludes = [normalise(e) for e in args.exclude]
    files = source_files()
    total = 0
    for name in names:
        hits = run_check(BY_NAME[name], files, paths, excludes)
        total += len(hits)
        if args.count:
            print(len(hits) if len(names) == 1 else "%s: %d" % (name, len(hits)))
        else:
            for rel, number, text in hits:
                print("%s:%d: %s" % (rel, number, text) if len(names) == 1
                      else "%s: %s:%d: %s" % (name, rel, number, text))
    return 1 if total else 0


if __name__ == "__main__":
    try:
        status = main(sys.argv[1:])
        sys.stdout.flush()
    except OSError:
        # The reader of a pipe (| head) went away; leave quietly rather than at shutdown.
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        status = 1
    sys.exit(status)
