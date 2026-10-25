/*	test_scanner.cpp
	oo::str::CharacterSet and oo::str::Scanner (oofnd/Scanner.hpp, bead oo-3rb.12) against
	GNUstep base 1.31.1.

	Every expectation was captured from gnustep-base 1.31.1 on this toolchain by throwaway
	Objective-C probes (not committed):
	  - the sets probe swept -characterIsMember: over the BMP for the five named sets and printed
	    one line per set, "<name>" then " XXXX-YYYY" per run of members, the line this test
	    rebuilds;
	  - the scanner probe read the script lines ScriptCorpus generates (a scanner over a string of
	    UTF-16 units, then operations on it) and printed per line exactly what ScriptRunner::run
	    returns here, calling the real NSScanner, NSScannerOOExtensions and the NSString set methods;
	    30,000 scripts, 0 differences; the digest below is FNV-1a over GNUstep's lines.
	To find a differing line after a failure, rebuild the probe, feed it the scripts and diff.
*/

// The header must survive OOCocoa.h's true/false macros and hand them back (proposed ADR-0028).
#define true						1
#define false						0
#include "oofnd/Scanner.hpp"
#include <type_traits>
static_assert(std::is_same_v<decltype(true), int>, "Scanner.hpp must restore OOCocoa.h's true macro");
#undef true
#undef false

#include "oo_test.hpp"

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <iterator>
#include <memory>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

using oo::str::CharacterSet;
using oo::str::Scanner;

std::uint64_t fnv(std::uint64_t h, const std::string& line)
{
	for (unsigned char c : line) h = (h ^ c) * 1099511628211ULL;
	return (h ^ '\n') * 1099511628211ULL;
}

// The scripts: generator (the probe read exactly these lines) and interpreter over oo::str.
struct ScriptCorpus
{
	std::uint64_t s;
	explicit ScriptCorpus(std::uint64_t seed) : s(seed) {}
	std::uint32_t next()
	{
		s ^= s << 13;
		s ^= s >> 7;
		s ^= s << 17;
		return static_cast<std::uint32_t>(s >> 32);
	}
	static void hex(std::string& out, char16_t c)
	{
		char buf[5];
		std::snprintf(buf, sizeof buf, "%04X", unsigned(c));
		out += buf;
	}
	// Scanned text: digits, number punctuation, every kind of skippable space, ASCII and
	// non-ASCII letters (including the Kelvin sign and long s, which fold to ASCII in Unicode),
	// a combining acute, non-ASCII digits and a surrogate pair.
	std::string text()
	{
		static constexpr char16_t kPool[] = {u'0', u'1', u'5', u'9', u'.', u'.', u'e', u'E', u'+', u'-', u' ', u' ',
			u'\t', u'\n', 0x00A0, 0x2028, 0x0085, u'a', u'b', u'A', u'B', u'x', u'(', u')', u'i', u'n', u'f',
			0x0301, 0x212A, 0x017F, 0x00E9, 0x00C9, 0x0661, 0xFF11, 0xD83D, 0x0130, u'k', u's', u'I'};
		std::string out;
		if (next() % 3 == 0)
		{
			// Numbers: long mantissas, exponents, signs, overflow.
			static constexpr char16_t kDigits[] = {u'0', u'1', u'2', u'4', u'6', u'7', u'9', u'9', u'0', u'.', u'e',
				u'-', u'+', u' '};
			for (std::uint32_t n = next() % 32; n > 0; --n) hex(out, kDigits[next() % std::size(kDigits)]);
			return out;
		}
		for (std::uint32_t n = next() % 13; n > 0; --n)
		{
			const char16_t c = kPool[next() % std::size(kPool)];
			hex(out, c);
			if (c == 0xD83D) hex(out, 0xDE00);
		}
		return out;
	}
	std::string target()
	{
		static constexpr char16_t kPool[] = {u'a', u'B', u'(', u')', u'1', u'.', u'e', u' ', u'k', u'S', u'x', u'i'};
		std::string out;
		for (std::uint32_t n = 1 + next() % 3; n > 0; --n) hex(out, kPool[next() % std::size(kPool)]);
		return out;
	}
	std::string set()
	{
		static constexpr const char* kNamed[] = {"w", "W", "n", "d", "a"};
		std::string out = next() % 4 == 0 ? "!" : "";
		if (next() % 3 == 0)
		{
			static constexpr char16_t kPool[] = {u'a', u'1', u' ', u'.', u'(', 0x00E9, 0x0301, 0xD83D, 0xDE00, u'e'};
			out += 'x';
			for (std::uint32_t n = next() % 4; n > 0; --n) hex(out, kPool[next() % std::size(kPool)]);
		}
		else
		{
			out += kNamed[next() % 5];
		}
		return out;
	}
	// One scanner and 1-8 operations on it.
	std::vector<std::string> script()
	{
		std::vector<std::string> lines;
		const std::string t = text();
		lines.push_back("S " + t);
		const std::size_t length = t.size() / 4;
		for (std::uint32_t n = 1 + next() % 8; n > 0; --n)
		{
			switch (next() % 17)
			{
				case 13: lines.push_back("T " + set()); break;
				case 14: lines.push_back("R " + set()); break;
				case 15: lines.push_back("B " + set()); break;
				case 16: lines.push_back("X " + set()); break;
				case 0: lines.push_back("I"); break;
				case 1: lines.push_back("F"); break;
				case 2: lines.push_back("D"); break;
				case 3: lines.push_back("E"); break;
				case 4: lines.push_back("s " + target()); break;
				case 5: lines.push_back("u " + target()); break;
				case 6: lines.push_back("c " + set()); break;
				case 7: lines.push_back("C " + set()); break;
				case 8: lines.push_back("o " + set()); break;
				case 9: lines.push_back("O " + set()); break;
				case 10: lines.push_back("L " + std::to_string(next() % (length + 1))); break;
				case 11: lines.push_back("P"); break;
				default:
				{
					std::string m = "M ";
					hex(m, static_cast<char16_t>(next() % 4 == 0 ? next() : (next() % 0x100)));
					lines.push_back(m + " " + set());
				}
			}
		}
		return lines;
	}
};

// Runs script lines against oo::str and returns the probe's output lines.
struct ScriptRunner
{
	std::unique_ptr<oo::str::Scanner> sc;
	std::string whole;

	static std::u16string units(std::string_view hex)
	{
		std::u16string u;
		for (std::size_t i = 0; i + 4 <= hex.size(); i += 4)
		{
			u += static_cast<char16_t>(std::stoul(std::string(hex.substr(i, 4)), nullptr, 16));
		}
		return u;
	}
	static std::string utf8(std::string_view hex) { return oo::utf16ToUtf8(units(hex)); }
	static oo::str::CharacterSet set(std::string_view p)
	{
		switch (p[0])
		{
			case 'w': return oo::str::CharacterSet::whitespace();
			case 'W': return oo::str::CharacterSet::whitespaceAndNewline();
			case 'n': return oo::str::CharacterSet::newline();
			case 'd': return oo::str::CharacterSet::decimalDigit();
			case 'a': return oo::str::CharacterSet::alphanumeric();
			case 'x': return oo::str::CharacterSet::fromCharacters(utf8(p.substr(1)));
			default: return set(p.substr(1)).inverted();
		}
	}
	static std::string value(bool ok, const std::string& v)
	{
		if (!ok) return " nil";
		std::string out = " [";
		for (char16_t c : oo::utf8ToUtf16(v)) ScriptCorpus::hex(out, c);
		return out + "]";
	}
	std::string run(const std::string& line)
	{
		const std::string_view arg = line.size() > 2 ? std::string_view(line).substr(2) : std::string_view();
		char buf[64];
		switch (line[0])
		{
			case 'S':
				whole = utf8(arg);
				sc = std::make_unique<oo::str::Scanner>(whole);
				return "S";
			case 'I':
			{
				int v = 12345;
				const bool r = sc->scanInt(&v);
				return "I " + std::to_string(r) + " " + std::to_string(v) + " " + std::to_string(sc->scanLocation());
			}
			case 'F':
			{
				float v = 7.0f;
				const bool r = sc->scanFloat(&v);
				std::uint32_t b;
				std::memcpy(&b, &v, 4);
				std::snprintf(buf, sizeof buf, "%08x", unsigned(b));
				return "F " + std::to_string(r) + " " + buf + " " + std::to_string(sc->scanLocation());
			}
			case 'D':
			{
				double v = 7.0;
				const bool r = sc->scanDouble(&v);
				std::uint64_t b;
				std::memcpy(&b, &v, 8);
				std::snprintf(buf, sizeof buf, "%08x%08x", unsigned(b >> 32), unsigned(b & 0xFFFFFFFFu));
				return "D " + std::to_string(r) + " " + buf + " " + std::to_string(sc->scanLocation());
			}
			case 'E': return "E " + std::to_string(sc->isAtEnd()) + " " + std::to_string(sc->scanLocation());
			case 'P': return "P " + std::to_string(sc->scanLocation());
			case 's':
			case 'u':
			{
				std::string v;
				const bool r = line[0] == 's' ? sc->scanString(utf8(arg), &v) : sc->scanUpToString(utf8(arg), &v);
				return std::string(1, line[0]) + " " + std::to_string(r) + value(r, v) + " " + std::to_string(sc->scanLocation());
			}
			case 'c':
			case 'C':
			case 'o':
			case 'O':
			{
				std::string v;
				const oo::str::CharacterSet cs = set(arg);
				bool r = false;
				if (line[0] == 'c') r = sc->scanCharactersFromSet(cs, &v);
				else if (line[0] == 'C') r = sc->scanUpToCharactersFromSet(cs, &v);
				else if (line[0] == 'o') r = sc->scanCharactersFromSetNoSkip(cs, &v);
				else r = sc->scanUpToCharactersFromSetNoSkip(cs, &v);
				return std::string(1, line[0]) + " " + std::to_string(r) + value(r, v) + " " + std::to_string(sc->scanLocation());
			}
			case 'L':
				sc->setScanLocation(std::stoul(std::string(arg)));
				return "L " + std::to_string(sc->scanLocation());
			case 'T': return "T" + value(true, oo::str::trim(whole, set(arg)));
			case 'R':
			case 'B':
			{
				const std::size_t at = line[0] == 'R' ? oo::str::findFirstOf(whole, set(arg)) : oo::str::findLastOf(whole, set(arg));
				return std::string(1, line[0]) + (at == std::string_view::npos ? " -1 0" : " " + std::to_string(at) + " 1");
			}
			case 'X':
			{
				const std::vector<std::string> parts = oo::str::splitByCharacters(whole, set(arg));
				std::string out = "X " + std::to_string(parts.size());
				for (const std::string& p : parts) out += value(true, p);
				return out;
			}
			case 'M':
				return "M " + std::to_string(set(arg.substr(5)).contains(units(arg.substr(0, 4))[0]));
		}
		return "?";
	}
};

} // namespace

OO_TEST(namedSetsMatchGNUstepOverTheBMP)
{
	const std::pair<const char*, CharacterSet> sets[] = {
		{"whitespace", CharacterSet::whitespace()},
		{"whitespaceAndNewline", CharacterSet::whitespaceAndNewline()},
		{"newline", CharacterSet::newline()},
		{"decimalDigit", CharacterSet::decimalDigit()},
		{"alphanumeric", CharacterSet::alphanumeric()},
	};
	std::uint64_t h = 14695981039346656037ULL;
	for (const auto& [name, set] : sets)
	{
		std::string line = name;
		char buf[16];
		for (unsigned c = 0; c < 0x10000;)
		{
			if (!set.contains(char16_t(c)))
			{
				++c;
				continue;
			}
			const unsigned start = c;
			while (c < 0x10000 && set.contains(char16_t(c))) ++c;
			std::snprintf(buf, sizeof buf, " %04X-%04X", start, c - 1);
			line += buf;
		}
		h = fnv(h, line);
	}
	OO_CHECK_EQ(h, 0xd85a935268da8294ULL);

	OO_CHECK(CharacterSet::whitespace().contains(u'\t'));
	OO_CHECK(!CharacterSet::whitespace().contains(u'\n'));
	OO_CHECK(CharacterSet::whitespace().contains(char16_t(0x2028)));
	OO_CHECK(!CharacterSet::newline().contains(char16_t(0x2028)));
	OO_CHECK(CharacterSet::decimalDigit().contains(char16_t(0x0661)));
	OO_CHECK(!CharacterSet::decimalDigit().contains(char16_t(0x00B2)));
	OO_CHECK(CharacterSet::alphanumeric().contains(char16_t(0x00B2)));
	bool same = true;
	for (unsigned c = 0; c < 0x10000; ++c)
	{
		same = same && CharacterSet::whitespaceAndNewline().contains(char16_t(c)) == oo::str::isWhitespaceOrNewline(char16_t(c));
	}
	OO_CHECK(same);
}

OO_TEST(customAndInvertedSets)
{
	const CharacterSet set = CharacterSet::fromCharacters("a(\xC3\xA9");
	OO_CHECK(set.contains(u'a') && set.contains(u'(') && set.contains(char16_t(0xE9)));
	OO_CHECK(!set.contains(u'A'));
	OO_CHECK(set.inverted().contains(u'A') && !set.inverted().contains(u'a'));
	OO_CHECK(set.inverted().inverted().contains(u'a'));
	// A surrogate pair is one supplementary member; neither unit alone is.
	const CharacterSet pair = CharacterSet::fromCharacters("\xF0\x9F\x98\x80");
	OO_CHECK(!pair.contains(char16_t(0xD83D)) && !pair.contains(char16_t(0xDE00)));
}

OO_TEST(numbersAsNSScannerReadsThem)
{
	Scanner s(" 1.5e");
	float f = 0;
	OO_CHECK(s.scanFloat(&f));
	OO_CHECK_EQ(f, 1.5f);
	OO_CHECK_EQ(s.scanLocation(), 4u);	// the dangling 'e' is not consumed
	OO_CHECK(!s.isAtEnd());

	Scanner colour("255 128 0");	// OOColor +colorFromString:
	float rgb[4] = {0, 0, 0, 7};
	OO_CHECK(colour.scanFloat(&rgb[0]) && colour.scanFloat(&rgb[1]) && colour.scanFloat(&rgb[2]));
	OO_CHECK(!colour.scanFloat(&rgb[3]));
	OO_CHECK_EQ(rgb[0], 255.0f);
	OO_CHECK_EQ(rgb[3], 7.0f);	// untouched on failure
	OO_CHECK_EQ(colour.scanLocation(), 9u);

	int i = 12345;
	Scanner big("4294967295"), small("-2147483648"), neg(" -12");
	OO_CHECK(big.scanInt(&i));
	OO_CHECK_EQ(i, 2147483647);
	OO_CHECK(small.scanInt(&i));
	OO_CHECK_EQ(i, -2147483647 - 1);
	OO_CHECK(neg.scanInt(&i));
	OO_CHECK_EQ(i, -12);
	OO_CHECK(neg.isAtEnd());

	Scanner none("x");
	OO_CHECK(!none.scanInt(&i) && !none.scanDouble(nullptr));
	OO_CHECK_EQ(none.scanLocation(), 0u);
}

OO_TEST(stringsAsOORoleSetScansThem)
{
	// "role(0.5)": scanUpToString "(" then scanString "(" then scanFloat.
	Scanner s("role(0.5)");
	std::string role, paren;
	float p = 1.0f;
	OO_CHECK(s.scanUpToString("(", &role));
	OO_CHECK_EQ(role, std::string("role"));
	OO_CHECK(s.scanString("(", &paren));
	OO_CHECK(s.scanFloat(&p));
	OO_CHECK_EQ(p, 0.5f);

	// A token starting with "(": nothing before it, so scanUpToString fails and leaves <role>.
	Scanner t("(5)");
	std::string untouched = "keep";
	OO_CHECK(!t.scanUpToString("(", &untouched));
	OO_CHECK_EQ(untouched, std::string("keep"));
	OO_CHECK(t.scanString("("));
	OO_CHECK(t.scanFloat(&p));
	OO_CHECK_EQ(p, 5.0f);

	// Case-insensitive by default; the text is returned as written.
	Scanner c("ABc");
	std::string got;
	OO_CHECK(c.scanString("ab", &got));
	OO_CHECK_EQ(got, std::string("AB"));
	// U+212A KELVIN SIGN matches 'k', but only as the first unit of the target.
	Scanner k("x\xE2\x84\xAA" "a");
	OO_CHECK(k.scanUpToString("k", &got));
	OO_CHECK_EQ(got, std::string("x"));
	Scanner k2("x\xE2\x84\xAA" "a");
	OO_CHECK(k2.scanUpToString("xk", &got));
	OO_CHECK_EQ(k2.scanLocation(), 3u);	// not found: everything scanned
	// A match that a combining unit follows is not a match.
	Scanner m("ae\xCC\x81" "e");
	OO_CHECK(m.scanUpToString("e", &got));
	OO_CHECK_EQ(m.scanLocation(), 3u);
}

OO_TEST(failureLocationsFollowNSScanner)
{
	// Nothing but skippable characters: scanString / scanUpToString / scanUpToCharactersFromSet
	// leave the location past them; scanCharactersFromSet and the number scans restore it.
	Scanner a("  ");
	OO_CHECK(!a.scanCharactersFromSet(CharacterSet::alphanumeric()));
	OO_CHECK_EQ(a.scanLocation(), 0u);
	OO_CHECK(!a.scanInt(nullptr));
	OO_CHECK_EQ(a.scanLocation(), 0u);
	OO_CHECK(!a.scanUpToCharactersFromSet(CharacterSet::alphanumeric()));
	OO_CHECK_EQ(a.scanLocation(), 2u);
	Scanner b(" ");
	OO_CHECK(!b.scanString(" "));
	OO_CHECK_EQ(b.scanLocation(), 1u);
	// A target longer than what is left also leaves the location past the skipped characters;
	// a mismatch restores it.
	Scanner c("\tab");
	OO_CHECK(!c.scanString("abc"));
	OO_CHECK_EQ(c.scanLocation(), 1u);
	c.setScanLocation(0);
	OO_CHECK(!c.scanString("x"));
	OO_CHECK_EQ(c.scanLocation(), 0u);
}

OO_TEST(ooliteNoSkipScansAsNSScannerOOExtensions)
{
	// ShipEntity's cargo: scanInt, then skip whitespace (no newlines), then the rest.
	Scanner s("3 \talloys");
	int n = 0;
	OO_CHECK(s.scanInt(&n));
	OO_CHECK_EQ(n, 3);
	OO_CHECK(s.scanCharactersFromSetNoSkip(CharacterSet::whitespace()));
	OO_CHECK_EQ(s.remainder(), std::string("alloys"));
	// No skipping: a leading tab is a run of its own; an empty run fails but keeps the location.
	Scanner t("\tA ");
	std::string run;
	OO_CHECK(!t.scanUpToCharactersFromSetNoSkip(CharacterSet::whitespace(), &run));
	OO_CHECK(t.scanCharactersFromSetNoSkip(CharacterSet::whitespace(), &run));
	OO_CHECK_EQ(run, std::string("\t"));
	OO_CHECK(t.scanUpToCharactersFromSetNoSkip(CharacterSet::whitespace(), &run));
	OO_CHECK_EQ(run, std::string("A"));
	OO_CHECK_EQ(t.scanLocation(), 2u);
}

OO_TEST(trimFindAndSplitBySet)
{
	OO_CHECK_EQ(oo::str::trim(" A\tB ", CharacterSet::whitespace()), std::string("A\tB"));
	OO_CHECK_EQ(oo::str::trim(" \x1F" "A\x1F ", CharacterSet::fromCharacters(" \x1F")), std::string("A"));	// GuiDisplayGen
	OO_CHECK_EQ(oo::str::trim("_ A\n_", CharacterSet::fromCharacters("_ \n")), std::string("A"));
	OO_CHECK_EQ(oo::str::findFirstOf(" A\tB ", CharacterSet::whitespace().inverted()), 1u);
	OO_CHECK_EQ(oo::str::findLastOf(" A\tB ", CharacterSet::whitespace().inverted()), 3u);
	// OODefaultShaderSynthesizer: a mode made only of r, g, b, a has no member of the inverse.
	OO_CHECK_EQ(oo::str::findFirstOf("rgbx", CharacterSet::fromCharacters("rgba").inverted()), 3u);
	OO_CHECK_EQ(oo::str::findFirstOf("rgba", CharacterSet::fromCharacters("rgba").inverted()), std::string_view::npos);
	const std::vector<std::string> parts = oo::str::splitByCharacters(" A\tB ", CharacterSet::whitespace());
	OO_CHECK_EQ(parts.size(), 4u);
	OO_CHECK(parts[0].empty() && parts[1] == "A" && parts[2] == "B" && parts[3].empty());
}

// Captured from GNUstep base (bead oo-3rb.67): -rangeOfCharacterFromSet:options:NSLiteralSearch
// range: with the old-style plist writer's escape set, and -longCharacterIsMember: of a unit.
OO_TEST(rangedSearchAndLongMembership)
{
	const CharacterSet escapes = CharacterSet::fromCharacters("\"\r\n\\");
	OO_CHECK_EQ(oo::str::findFirstOf("x\ny\rz\\w\"", escapes, 0), 1u);
	OO_CHECK_EQ(oo::str::findFirstOf("x\ny\rz\\w\"", escapes, 2), 3u);
	OO_CHECK_EQ(oo::str::findFirstOf("x\ny\rz\\w\"", escapes, 6), 7u);
	OO_CHECK_EQ(oo::str::findFirstOf("x\ny\rz\\w\"", escapes, 8), std::string_view::npos);
	OO_CHECK_EQ(oo::str::findFirstOf("e\xCC\x81\"", escapes, 1), 2u);	// after a combining mark
	OO_CHECK_EQ(oo::str::findFirstOf("\xF0\x9F\x98\x80\"a\\", escapes, 1), 2u);	// after a surrogate pair
	OO_CHECK_EQ(oo::str::findFirstOf("abc", escapes, 3), std::string_view::npos);
	OO_CHECK(CharacterSet::decimalDigit().contains(u'7'));
	OO_CHECK(CharacterSet::decimalDigit().contains(u'٣'));	// ARABIC-INDIC DIGIT THREE
	OO_CHECK(!CharacterSet::decimalDigit().contains(u'A'));
}


OO_TEST(scriptCorpusMatchesGNUstep)
{
	ScriptCorpus corpus(0x12);
	ScriptRunner runner;
	std::uint64_t h = 14695981039346656037ULL;
	for (int i = 0; i < 30000; ++i)
	{
		for (const std::string& line : corpus.script()) h = fnv(h, runner.run(line));
	}
	OO_CHECK_EQ(h, 0xbcc81a26e7aadb21ULL);
}

OO_TEST_MAIN()
