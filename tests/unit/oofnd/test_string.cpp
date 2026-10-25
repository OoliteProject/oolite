/*	test_string.cpp
	oo::str (oofnd/String.hpp, bead oo-dps) against GNUstep base 1.31.1.

	Every expectation here was captured from gnustep-base 1.31.1 on this toolchain (throwaway
	probes, not committed): readable rows for the cases worth reading, and, for the exhaustive
	sweeps, an FNV-1a digest of GNUstep's output that the test recomputes from oo::str. The
	corpora are generated here by the same xorshift generator the probes used, so the digest of
	oo::str's output equals the digest of GNUstep's output exactly when every line matches.
	Each probe was an Objective-C++ program linked against gnustep-base that built the same inputs
	and printed, per input, exactly the line this test hashes (units() is its line format); to find
	which line differs after a failure, rebuild that program and diff its lines against these.
*/

// The header must survive OOCocoa.h's true/false macros and hand them back (proposed ADR-0028).
#define true						1
#define false						0
#include "oofnd/String.hpp"
#include <type_traits>
static_assert(std::is_same_v<decltype(true), int>, "String.hpp must restore OOCocoa.h's true macro");
#undef true
#undef false

#include "oo_test.hpp"

#include <cstdint>
#include <initializer_list>
#include <limits>
#include <string>
#include <vector>

namespace {

using namespace oo::str;

// A UTF-8 string from UTF-16 code units (keeps this file ASCII).
std::string U(std::initializer_list<char16_t> units)
{
	return oo::utf16ToUtf8(std::u16string(units));
}

struct Fnv
{
	std::uint64_t h = 14695981039346656037ULL;
	void add(const std::string& s)
	{
		for (unsigned char c : s) h = (h ^ c) * 1099511628211ULL;
	}
	void add(unsigned char c) { h = (h ^ c) * 1099511628211ULL; }
};

// The probes' corpus: strings of up to maxLen units drawn from a pool of ASCII, whitespace of
// every kind GNUstep knows, separators, cased and uncased letters and lone surrogates.
struct Corpus
{
	std::uint64_t s;
	explicit Corpus(std::uint64_t seed) : s(seed) {}
	std::uint32_t next()
	{
		s ^= s << 13;
		s ^= s >> 7;
		s ^= s << 17;
		return static_cast<std::uint32_t>(s >> 32);
	}
	std::u16string string(unsigned maxLen)
	{
		static const char16_t pool[] = {0x61, 0x5A, 0x6D, 0x30, 0x39, 0x20, 0x09, 0x0A, 0x0D, 0x0B, 0x0C, 0x85, 0xA0, 0x1680,
			0x2000, 0x200B, 0x2028, 0x3000, 0xFEFF, 0x2E, 0x2F, 0x5C, 0x2D, 0x5F, 0x27, 0xE9, 0xC9, 0xDF, 0x130, 0x131, 0x3A3,
			0x3C2, 0x3C3, 0x401, 0x451, 0x1E9E, 0x212A, 0xFB00, 0xD83D, 0xDE00, 0x10D0, 0xFF21, 0x2160, 0x24B6, 0x78, 0x51};
		const unsigned n = next() % (maxLen + 1);
		std::u16string r;
		for (unsigned i = 0; i < n; i++)
		{
			char16_t c = pool[next() % (sizeof pool / sizeof *pool)];
			if (i == 0 && c == 0xFEFF) c = 0x62;	// NSString creation drops a leading BOM
			r += c;
		}
		return r;
	}
};

// The probes' line format: each UTF-16 unit as "%04X ".
std::string units(const std::string& s)
{
	static const char* hex = "0123456789ABCDEF";
	std::string out;
	for (char16_t c : oo::utf8ToUtf16(s))
	{
		out += hex[(c >> 12) & 15];
		out += hex[(c >> 8) & 15];
		out += hex[(c >> 4) & 15];
		out += hex[c & 15];
		out += ' ';
	}
	return out;
}

} // namespace

// --- character tables ----------------------------------------------------------------------------

OO_TEST(caseTablesMatchGNUstepOverTheBMP)
{
	// -uppercaseString / -lowercaseString of every unit, upper then lower, little-endian.
	Fnv f;
	for (unsigned c = 0; c < 0x10000; c++)
	{
		if (c >= 0xD800 && c < 0xE000) continue;
		const char16_t u = toUpper(static_cast<char16_t>(c)), l = toLower(static_cast<char16_t>(c));
		f.add(static_cast<unsigned char>(u & 0xFF));
		f.add(static_cast<unsigned char>(u >> 8));
		f.add(static_cast<unsigned char>(l & 0xFF));
		f.add(static_cast<unsigned char>(l >> 8));
	}
	OO_CHECK_EQ(f.h, 0x314D997D349929D1ULL);

	OO_CHECK_EQ(toUpper(u'a'), u'A');
	OO_CHECK_EQ(toUpper(0xDF), char16_t(0xDF));      // sharp s has no one-unit capital here
	OO_CHECK_EQ(toUpper(0x131), char16_t(0x49));     // dotless i -> I
	OO_CHECK_EQ(toLower(0x130), char16_t(0x69));     // I with dot -> i
	OO_CHECK_EQ(toUpper(0x3C2), char16_t(0x3A3));    // final sigma -> SIGMA
	OO_CHECK_EQ(toLower(0x212A), char16_t(0x6B));    // KELVIN SIGN -> k
	OO_CHECK_EQ(toUpper(0x2C30), char16_t(0x2C30));  // Glagolitic: newer than GNUstep's tables
	OO_CHECK(isWhitespaceOrNewline(0x85) && isWhitespaceOrNewline(0x3000) && !isWhitespaceOrNewline(0xFEFF));
}

// --- the string corpus: case, capitalisation, trimming, path extensions ------------------------------

OO_TEST(stringCorpusMatchesGNUstep)
{
	// 20,000 strings x {itself, -capitalizedString, -uppercaseString, -lowercaseString, leading
	// trim, trailing trim, -pathExtension}, one probe line each.
	Corpus c(12345);
	Fnv f;
	for (int i = 0; i < 20000; i++)
	{
		const std::string s = oo::utf16ToUtf8(c.string(12));
		f.add("in " + units(s) + "|\n");
		f.add("cap " + units(capitalized(s)) + "|\n");
		f.add("up " + units(uppercase(s)) + "|\n");
		f.add("lo " + units(lowercase(s)) + "|\n");
		f.add("tl " + units(trimLeadingWhitespaceAndNewlines(s)) + "|\n");
		f.add("tt " + units(trimTrailingWhitespaceAndNewlines(s)) + "|\n");
		f.add("ext " + units(pathExtension(s)) + "|\n");
	}
	OO_CHECK_EQ(f.h, 0x078ADF6EE40A0057ULL);
}

OO_TEST(capitalizationAndTrimming)
{
	OO_CHECK_EQ(capitalized("hello wORLD"), std::string("Hello World"));
	OO_CHECK_EQ(capitalized("o'neil mc-donald"), std::string("O'neil Mc-donald"));
	OO_CHECK_EQ(capitalized("  two\tspaces\nx"), std::string("  Two\tSpaces\nX"));
	OO_CHECK_EQ(capitalized(U({0x61, 0xA0, 0x62})), U({0x41, 0xA0, 0x42}));    // NBSP breaks words
	OO_CHECK_EQ(capitalized("3rd"), std::string("3rd"));
	OO_CHECK_EQ(capitalized(""), std::string(""));
	OO_CHECK_EQ(trimLeadingWhitespaceAndNewlines(" \t\n x y "), std::string("x y "));
	OO_CHECK_EQ(trimTrailingWhitespaceAndNewlines(" x y \r\n"), std::string(" x y"));
	OO_CHECK_EQ(trimLeadingWhitespaceAndNewlines(U({0x3000, 0x2028, 0x41})), std::string("A"));
	OO_CHECK_EQ(trimTrailingWhitespaceAndNewlines(" \n\t "), std::string(""));
	OO_CHECK_EQ(trimWhitespaceAndNewlines("  both  "), std::string("both"));
	OO_CHECK_EQ(trimLeading("xxaxx", [](char16_t c) { return c == u'x'; }), std::string("axx"));
	OO_CHECK_EQ(trimTrailing("xxaxx", [](char16_t c) { return c == u'x'; }), std::string("xxa"));
}

OO_TEST(pathExtensionMatchesGNUstep)
{
	struct Row
	{
		const char* path;
		const char* ext;
	};
	static const Row rows[] = {
		{"", ""}, {".", ""}, {"..", ""}, {"a", ""}, {"a.", ""}, {".a", ""}, {"a.b", "b"}, {"a.b.c", "c"},
		{"a..b", "b"}, {"a.b/", "b"}, {"a.b//", "b"}, {"a.b\\", "b"}, {"/a.b", "b"}, {"/.a", ""}, {"/", ""},
		{"//", ""}, {"x/.b", ""}, {"x/a.b", "b"}, {"x.y/z", ""}, {"x.y/", "y"}, {"C:", ""}, {"C:.b", ""},
		{"C:a.b", "b"}, {"C:/", ""}, {"C:/.b", ""}, {"C:\\a.b", "b"}, {"C:\\", ""}, {"\\\\srv\\share\\a.b", "b"},
		{"//srv/share/a.b", "b"}, {"//srv/share", ""}, {"//srv/share/", ""}, {"//srv/sh.are", "are"},
		{"\\\\srv\\sh.are", "are"}, {"~", ""}, {"~/a.b", "b"}, {"~a.b", ""}, {"a/b.c/d", ""}, {"a.b\\c", ""},
		{"a b.c d", "c d"}, {"a.B", "B"}, {"a.OXP", "OXP"}, {"x/y.tar.gz", "gz"}, {"a.b/.", ""}, {"a.b/..", ""},
		{"/..", ""}, {"./a", ""}, {"../a.b", "b"}, {"C:x", ""}, {"c:.", ""}, {"1:a.b", "b"}, {"ab:c.d", "d"},
		{"a:/b.c", "c"}, {"\\a.b", "b"}, {"\\\\a.b", "b"}, {"//a.b", "b"}, {"///a.b", "b"}, {"//a/b.c", "c"},
		{"a/", ""}, {"a.b.", ""}, {"a.b..", ""}, {" .b", "b"}, {"a. b", " b"},
	};
	for (const Row& r : rows) OO_CHECK_EQ(pathExtension(r.path), std::string(r.ext));

	// A dot that a combining unit follows is part of that composed sequence, not a separator.
	OO_CHECK_EQ(pathExtension(U({0x61, 0x2E, 0x62, 0x2E, 0x301, 0x63})), U({0x62, 0x2E, 0x301, 0x63}));
	OO_CHECK_EQ(pathExtension(U({0x61, 0x2F, 0x2E, 0x301, 0x62})), std::string(""));
	OO_CHECK_EQ(pathExtension(U({0x61, 0x2E, 0xD83D, 0xDE00})), U({0xD83D, 0xDE00}));
	OO_CHECK_EQ(pathExtension(U({0x61, 0x2E, 0x62, 0x2E, 0xDE00})), U({0x62, 0x2E, 0xDE00}));
	OO_CHECK_EQ(pathExtension(U({0x61, 0x2E, 0x2B0, 0x62})), std::string(""));  // a modifier letter extends too

	OO_CHECK(pathHasExtension("Shaders/foo.VS", "vs"));
	OO_CHECK(pathHasExtension("a.oxp/", "OXP"));
	OO_CHECK(!pathHasExtension("a.oxp.zip", "oxp"));
	OO_CHECK(!pathHasExtension(U({0x61, 0x2E, 0x212A}), "k"));   // Kelvin sign is not 'k' here
	OO_CHECK(!pathHasExtension(U({0x61, 0x2E, 0x130}), "i"));
	const std::vector<std::string> exts = {"vertex", "vs", "vsh"};
	OO_CHECK(pathHasExtensionIn("x/y.Vsh", exts));
	OO_CHECK(!pathHasExtensionIn("x/y.fs", exts));
}

OO_TEST(caseInsensitiveEqualityAgainstASCII)
{
	OO_CHECK(equalsIgnoringCaseAscii("PLIST", "plist"));
	OO_CHECK(equalsIgnoringCaseAscii("", ""));
	OO_CHECK(!equalsIgnoringCaseAscii("plists", "plist"));
	OO_CHECK(!equalsIgnoringCaseAscii("_", "A"));
	OO_CHECK(!equalsIgnoringCaseAscii(U({0xFF21}), "a"));      // fullwidth A
	OO_CHECK(!equalsIgnoringCaseAscii(U({0x17F}), "s"));       // long s
	OO_CHECK(!equalsIgnoringCaseAscii(U({0x61, 0x301}), "a")); // a + combining acute
	OO_CHECK(equalsIgnoringCaseAscii(U({0xE9}), U({0xE9})));
}

// --- tokens, oo_hash, versions ---------------------------------------------------------------------

OO_TEST(tokensAndHashCorpusMatchGNUstep)
{
	// ScanTokensFromString() and -oo_hash over hand-picked strings and 3,000 corpus strings.
	std::vector<std::string> inputs = {"", "  a  b ", "x\ty\nz", "one", " lead", "trail ", "\n\n",
		U({0x61, 0xA0, 0x62, 0x3000, 0x63}), "1.0 2.5 -3"};
	Corpus c(2024);
	for (int i = 0; i < 3000; i++) inputs.push_back(oo::utf16ToUtf8(c.string(12)));
	Fnv f;
	for (const std::string& s : inputs)
	{
		std::string line = "tok " + units(s) + ":";
		for (const std::string& t : tokens(s)) line += " " + units(t) + ";";
		f.add(line + "\n");
		f.add("hash " + units(s) + ": " + std::to_string(ooHash(s)) + "\n");
	}
	OO_CHECK_EQ(f.h, 0x33B776F86797BE7DULL);

	OO_CHECK(tokens("  alpha\tbeta\n gamma ") == (std::vector<std::string>{"alpha", "beta", "gamma"}));
	OO_CHECK(tokens(" \n ").empty());
	OO_CHECK_EQ(ooHash(""), 5381u);
	OO_CHECK_EQ(ooHash("a"), ((5381u << 5) + 5381u) ^ 0x61u);
}

OO_TEST(versionsMatchGNUstep)
{
	struct Row
	{
		const char* text;
		std::vector<unsigned> components;
	};
	static const std::vector<Row> rows = {
		{"1.2.3", {1, 2, 3}}, {"1.77.1", {1, 77, 1}}, {"1.2.3-beta 4", {1, 2, 3}}, {" 1.2", {0}},
		{"1..2", {1, 0, 2}}, {"a.b", {0, 0}}, {"-1.2", {0}}, {"1.-2", {1, 0}}, {"2147483648.1", {2147483647, 1}},
		{"99999999999.1", {2147483647, 1}}, {"1.2 3.4", {1, 2}}, {"", {0}}, {"1.2-3.4", {1, 2}}, {".5", {0, 5}},
		{"5.", {5, 0}}, {"1.2.3.4.5.6", {1, 2, 3, 4, 5, 6}}, {"+3.4", {3, 4}}, {"0x10.2", {0, 2}}, {" 12 .3", {0}},
		{"1e5.2", {1, 2}}, {"007.08", {7, 8}}, {"1.90", {1, 90}}, {"1.9", {1, 9}}, {"1.2.3.0", {1, 2, 3, 0}},
		{"4294967295.1", {2147483647, 1}}, {"-5", {0}}, {"1.2.3 (build 7)", {1, 2, 3}},
	};
	for (const Row& r : rows) OO_CHECK(versionComponents(r.text) == r.components);

	// CompareVersions() over every ordered pair of the rows, as NSComparisonResult bytes.
	Fnv f;
	for (const Row& a : rows)
		for (const Row& b : rows) f.add(static_cast<unsigned char>(compareVersions(versionComponents(a.text), versionComponents(b.text))));
	OO_CHECK_EQ(f.h, 0x988203404BD1F39FULL);
	OO_CHECK(compareVersions(versionComponents("1.7"), versionComponents("1.60")) < 0);
	OO_CHECK_EQ(compareVersions(versionComponents("1.2.3.0"), versionComponents("1.2.3")), 0);
}

// --- replacing, splitting, building --------------------------------------------------------------

OO_TEST(replaceOccurrencesMatchesGNUstep)
{
	OO_CHECK_EQ(replaceOccurrences(U({0x61, 0x2605, 0x62}), U({0x2605}), "\b"), std::string("a\bb"));
	OO_CHECK_EQ(replaceOccurrences(U({0x2605, 0x2605}), U({0x2605}), "xy"), std::string("xyxy"));
	OO_CHECK_EQ(replaceOccurrences(U({0x2605, 0x301}), U({0x2605}), "X"), U({0x2605, 0x301}));
	OO_CHECK_EQ(replaceOccurrences(U({0x78, 0x301, 0x2605}), U({0x2605}), "X"), U({0x78, 0x301, 0x58}));
	OO_CHECK_EQ(replaceOccurrences("aab", "ab", "Z"), std::string("aZ"));
	OO_CHECK_EQ(replaceOccurrences("abab", "ab", "Z"), std::string("ZZ"));
	OO_CHECK_EQ(replaceOccurrences("aaa", "aa", "Z"), std::string("Za"));
	OO_CHECK_EQ(replaceOccurrences(U({0x65, 0x301}), U({0xE9}), "Z"), U({0x65, 0x301}));  // no canonical equivalence
	OO_CHECK_EQ(replaceOccurrences(U({0x65, 0x301}), "e", "Z"), U({0x65, 0x301}));
	OO_CHECK_EQ(replaceOccurrences(U({0x41, 0x2605}), U({0x61, 0x2605}), "Z"), U({0x41, 0x2605}));
	OO_CHECK_EQ(replaceOccurrences(U({0xFB01}), "fi", "Z"), U({0xFB01}));
	OO_CHECK_EQ(replaceOccurrences(U({0x2605, 0xD83D}), U({0x2605}), "X"), U({0x58, 0xD83D}));
	OO_CHECK_EQ(replaceOccurrences(U({0x2605, 0xDE00}), U({0x2605}), "X"), U({0x2605, 0xDE00}));
	OO_CHECK_EQ(replaceOccurrences(U({0x20A2, 0x20, 0x35}), U({0x20A2}), U({0x20AC})), U({0x20AC, 0x20, 0x35}));

	// 3,000 corpus haystacks salted with the font's substitution keys, one- and two-unit targets.
	static const char16_t keys[] = {0x20A2, 0x2318, 0x2605, 0x266F, 0x200A, 0x61, 0x2E, 0x62};
	Corpus c(99);
	Fnv f;
	for (int i = 0; i < 3000; i++)
	{
		std::u16string hay = c.string(10);
		for (char16_t& ch : hay)
			if (c.next() % 3 == 0) ch = keys[c.next() % 8];
		std::u16string key(1, keys[c.next() % 8]);
		if (c.next() % 4 == 0) key += keys[c.next() % 8];
		const std::string h = oo::utf16ToUtf8(hay), k = oo::utf16ToUtf8(key);
		f.add("C " + units(h) + ": " + units(k) + ": " + units(replaceOccurrences(h, k, "<>")) + "\n");
	}
	OO_CHECK_EQ(f.h, 0xEDBF1D989502E79FULL);
}

OO_TEST(literalSearchPrefixAndSuffixMatchGNUstep)
{
	// NSLiteralSearch replacement, -hasPrefix: and -hasSuffix: over 4,000 corpus haystacks salted
	// with a combining acute, so literal and composed matching would differ.
	static const char16_t keys[] = {0x2605, 0x61, 0x2E, 0x62, 0x301, 0x25};
	Corpus c(515);
	Fnv f;
	for (int i = 0; i < 4000; i++)
	{
		std::u16string hay = c.string(8);
		for (char16_t& ch : hay)
			if (c.next() % 2 == 0) ch = keys[c.next() % 6];
		std::u16string key(1, keys[c.next() % 4]);
		if (c.next() % 3 == 0) key += keys[c.next() % 6];
		const std::string h = oo::utf16ToUtf8(hay), k = oo::utf16ToUtf8(key);
		f.add("L " + units(h) + ": " + units(k) + ": " + units(replaceOccurrences(h, k, "<>", Search::literal)) + ": "
			+ (hasPrefix(h, k) ? "1" : "0") + " " + (hasSuffix(h, k) ? "1" : "0") + "\n");
	}
	OO_CHECK_EQ(f.h, 0xD8CC5CDB623FF7ECULL);

	OO_CHECK_EQ(replaceOccurrences(U({0x2605, 0x301}), U({0x2605}), "X", Search::literal), U({0x58, 0x301}));
	OO_CHECK(hasPrefix(U({0x62, 0x301}), "b"));                  // literal: ends inside the sequence
	OO_CHECK(hasPrefix(U({0xD83D, 0xDE00}), U({0xD83D})));      // ...or inside a surrogate pair
	OO_CHECK(!hasPrefix("abc", "") && !hasSuffix("abc", "") && !hasPrefix("", ""));
	OO_CHECK(hasPrefix("mission_x", "mission_") && hasSuffix("abc_string", "_string") && !hasSuffix("c", "abc"));
}

OO_TEST(splitLinesTabsAndUnits)
{
	OO_CHECK(split("a.b..c", ".") == (std::vector<std::string>{"a", "b", "", "c"}));
	OO_CHECK(split("", ".") == (std::vector<std::string>{""}));
	OO_CHECK(split(".", ".") == (std::vector<std::string>{"", ""}));
	OO_CHECK(split("a::b", "::") == (std::vector<std::string>{"a", "b"}));

	OO_CHECK_EQ(tabString(0), std::string(""));
	OO_CHECK_EQ(tabString(12), std::string(12, '\t'));
	std::string m = "x";
	appendLine(m, "y");
	appendLine(m, "");
	OO_CHECK_EQ(m, std::string("xy\n\n"));
	std::string d = U({0x61, 0xD83D, 0xDE00, 0x62});
	deleteUnitAt(d, 1);                               // one UTF-16 unit, as NSMutableString does
	OO_CHECK_EQ(d, U({0x61, 0xDE00, 0x62}));
	deleteUnitAt(d, 9);
	OO_CHECK_EQ(length(d), 3u);
	OO_CHECK_EQ(length(U({0xD83D, 0xDE00})), 2u);

	const oo::Data bom = utf16Data("A", true), plain = utf16Data(U({0x20AC}), false);
	OO_CHECK_EQ(bom.length(), 4u);
	OO_CHECK(bom.bytes()[0] == 0xFF && bom.bytes()[1] == 0xFE && bom.bytes()[2] == 0x41 && bom.bytes()[3] == 0);
	OO_CHECK(plain.length() == 2 && plain.bytes()[0] == 0xAC && plain.bytes()[1] == 0x20);

	OO_CHECK_EQ(intValue(" -12abc"), -12);
	OO_CHECK_EQ(longLongValue("99999999999999999999"), 9223372036854775807LL);
	OO_CHECK_EQ(doubleValue(" 2.5e1x"), 25.0);
}

// --- formatting -------------------------------------------------------------------------------------

OO_TEST(formatMatchesGNUstepForTheGamesConversions)
{
	// -[NSString stringWithFormat:] results, captured.
	OO_CHECK_EQ(format("%f", 0.1), std::string("0.100000"));
	OO_CHECK_EQ(format("%f", -0.0), std::string("-0.000000"));
	OO_CHECK_EQ(format("%.1f", 0.05), std::string("0.1"));
	OO_CHECK_EQ(format("%.1f", 0.25), std::string("0.2"));
	OO_CHECK_EQ(format("%.2f", 2.675), std::string("2.67"));
	OO_CHECK_EQ(format("%.0f %.0f %.0f", 0.5, 1.5, 2.5), std::string("0 2 2"));
	OO_CHECK_EQ(format("%.3f", 1234567.891), std::string("1234567.891"));
	OO_CHECK_EQ(format("%g %g %g", 0.1, 1e-5, 123456789.0), std::string("0.1 1e-05 1.23457e+08"));
	OO_CHECK_EQ(format("%.3g", 1234567.891), std::string("1.23e+06"));
	OO_CHECK_EQ(format("%.10g", 2.0 / 3.0), std::string("0.6666666667"));
	OO_CHECK_EQ(format("%e", 1e-300), std::string("1.000000e-300"));
	OO_CHECK_EQ(format("%.3e", 6.02214076e23), std::string("6.022e+23"));
	OO_CHECK_EQ(format("%E", 1.602e-19), std::string("1.602000E-19"));
	OO_CHECK_EQ(format("%g %f %g", std::numeric_limits<double>::infinity(), -std::numeric_limits<double>::infinity(),
		std::numeric_limits<double>::quiet_NaN()), std::string("inf -inf nan"));
	OO_CHECK_EQ(format("%10.3f|%-10.3f|", 3.14159, 3.14159), std::string("     3.142|3.142     |"));
	OO_CHECK_EQ(format("%+.2f % f %010.3f", 7.0, 42.0, -3.5), std::string("+7.00  42.000000 -00003.500"));
	OO_CHECK_EQ(format("%#g %.1f %5.1f", 1.0, 1e15, 99.95), std::string("1.00000 1000000000000000.0 100.0"));
	OO_CHECK_EQ(format("%.17g %.15g %a", 0.1, 0.1, 1.0), std::string("0.10000000000000001 0.1 0x1p+0"));
	OO_CHECK_EQ(format("%d|%5d|%-5d|%05d|%+d|% d", -42, 42, 42, 42, 7, 7), std::string("-42|   42|42   |00042|+7| 7"));
	OO_CHECK_EQ(format("%x %X %#x %o %u %3.2d", 255, 255, 255, 8, -1, 5), std::string("ff FF 0xff 10 4294967295  05"));
	OO_CHECK_EQ(format("%i %d %c", 2147483647, -2147483647 - 1, 65), std::string("2147483647 -2147483648 A"));
	OO_CHECK_EQ(format("%lld %lld", 9223372036854775807LL, -9223372036854775807LL - 1),
		std::string("9223372036854775807 -9223372036854775808"));
	OO_CHECK_EQ(format("%llu %llx", 18446744073709551615ULL, 3735928559ULL), std::string("18446744073709551615 deadbeef"));
	OO_CHECK_EQ(format("%s|%5s|%-5s|%.2s", "abc", "ab", "ab", "abcdef"), std::string("abc|   ab|ab   |ab"));
	OO_CHECK_EQ(format("%%%s a%%b", "x"), std::string("%x a%b"));
	const std::string big(300, 'q');
	OO_CHECK_EQ(format("<%s>", big.c_str()), "<" + big + ">");
}

OO_TEST_MAIN()
