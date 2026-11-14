/*	test_encoding.cpp
	oo::str encodings (oofnd/Encoding.hpp, bead oo-dps): OOEncodingConverter's lossy conversion to
	the five Windows code pages, against GNUstep base 1.31.1 (libiconv with transliteration).

	Captured with throwaway probes (not committed): every BMP unit between 'a' and 'z', a sample of
	the supplementary planes that covers every transliterated range, and 5,000 corpus strings, in
	all five code pages. The test recomputes the same FNV-1a digest from oo::str::encodeLossy.
*/

#define true						1
#define false						0
#include "oofnd/Encoding.hpp"
#include <type_traits>
static_assert(std::is_same_v<decltype(true), int>, "Encoding.hpp must restore OOCocoa.h's true macro");
#undef true
#undef false

#include "oo_test.hpp"

#include <cstdint>
#include <initializer_list>
#include <string>
#include <utility>
#include <vector>

namespace {

using oo::str::Encoding;

constexpr Encoding kPages[5] = {Encoding::windowsCP1250, Encoding::windowsCP1251, Encoding::windowsCP1252,
	Encoding::windowsCP1253, Encoding::windowsCP1254};

std::string U(std::initializer_list<char16_t> units)
{
	return oo::utf16ToUtf8(std::u16string(units));
}

std::string bytes(const std::optional<oo::Data>& d)
{
	return d ? std::string(reinterpret_cast<const char*>(d->bytes()), d->length()) : std::string("<nil>");
}

struct Fnv
{
	std::uint64_t h = 14695981039346656037ULL;
	void add(unsigned char c) { h = (h ^ c) * 1099511628211ULL; }
	void add(const std::optional<oo::Data>& d)
	{
		if (!d)
		{
			add(0xFE);
			return;
		}
		for (std::size_t i = 0; i < d->length(); i++) add(d->bytes()[i]);
		add(0xFF);
	}
};

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
			if (i == 0 && c == 0xFEFF) c = 0x62;
			r += c;
		}
		return r;
	}
};

} // namespace

OO_TEST(namesAreOOEncodingConvertersFixedList)
{
	OO_CHECK(oo::str::encodingFromName("windows-latin-1") == Encoding::windowsCP1252);
	OO_CHECK(oo::str::encodingFromName("windows-latin-2") == Encoding::windowsCP1250);
	OO_CHECK(oo::str::encodingFromName("windows-cyrillic") == Encoding::windowsCP1251);
	OO_CHECK(oo::str::encodingFromName("windows-greek") == Encoding::windowsCP1253);
	OO_CHECK(oo::str::encodingFromName("windows-turkish") == Encoding::windowsCP1254);
	OO_CHECK(!oo::str::encodingFromName("Windows-Latin-1"));
	OO_CHECK(!oo::str::encodingFromName("utf-8"));
	OO_CHECK(!oo::str::encodingFromName(""));
	for (Encoding e : kPages) OO_CHECK(oo::str::encodingFromName(oo::str::encodingName(e)) == e);
	OO_CHECK_EQ(static_cast<unsigned>(Encoding::windowsCP1252), 12u);   // NSWindowsCP1252StringEncoding
	OO_CHECK_EQ(static_cast<unsigned>(Encoding::windowsCP1250), 15u);
}

OO_TEST(everyBMPUnitMatchesGNUstep)
{
	static const std::uint64_t expected[5] = {0x3D2DB7BB5756F8F8ULL, 0x368DBA04E77D116EULL, 0x914F7CAAF2360067ULL,
		0x296E0E3075B725B2ULL, 0x59C2422E4D489637ULL};
	for (int p = 0; p < 5; p++)
	{
		Fnv f;
		for (unsigned c = 0; c < 0x10000; c++) f.add(oo::str::encodeLossy(U({0x61, static_cast<char16_t>(c), 0x7A}), kPages[p]));
		OO_CHECK_EQ(f.h, expected[p]);
	}
}

OO_TEST(supplementaryCharactersMatchGNUstep)
{
	// Every 61st code point, and all of the two blocks that transliterate (mathematical
	// alphanumerics, enclosed and pictographic symbols).
	static const std::uint64_t expected[5] = {0x059B3B65B4A4F1ECULL, 0x059B3B65B4A4F1ECULL, 0x059B3B65B4A4F1ECULL,
		0x69F8B8772C895044ULL, 0x9FC8C5FDCE82C740ULL};
	for (int p = 0; p < 5; p++)
	{
		Fnv f;
		for (char32_t c = 0x10000; c < 0x110000; c++)
		{
			if (!(c % 61 == 0 || (c >= 0x1D400 && c < 0x1D800) || (c >= 0x1F100 && c < 0x1FB00))) continue;
			const char32_t v = c - 0x10000;
			f.add(oo::str::encodeLossy(U({0x61, static_cast<char16_t>(0xD800 + (v >> 10)), static_cast<char16_t>(0xDC00 + (v & 0x3FF)), 0x7A}), kPages[p]));
		}
		OO_CHECK_EQ(f.h, expected[p]);
	}
}

OO_TEST(corpusStringsMatchGNUstep)
{
	static const std::uint64_t expected[5] = {0xCFE95B259D13739FULL, 0xDB13546AE370D724ULL, 0x5093A2A6AED14ED9ULL,
		0x0FE99386A855E214ULL, 0x33519E8F6EF0DB11ULL};
	static const char16_t extra[] = {0x301, 0x308, 0x327, 0x2019, 0x201C, 0x20AC, 0x20A2, 0x2318, 0x2605, 0x266F, 0x200A, 0x152,
		0x160, 0x416, 0x3A9, 0x11F, 0x131, 0x2122, 0xFB01, 0x2026};
	// The probe ran the encodings in the order 1252, 1250, 1251, 1253, 1254, one corpus each.
	static const int order[5] = {2, 0, 1, 3, 4};
	for (int k = 0; k < 5; k++)
	{
		const int p = order[k];
		Corpus corpus(4242);
		Fnv f;
		for (int i = 0; i < 5000; i++)
		{
			std::u16string s = corpus.string(10);
			for (char16_t& ch : s)
				if (corpus.next() % 2) ch = extra[corpus.next() % (sizeof extra / sizeof *extra)];
			f.add(oo::str::encodeLossy(oo::utf16ToUtf8(s), kPages[p]));
		}
		OO_CHECK_EQ(f.h, expected[p]);
	}
}

OO_TEST(readableCases)
{
	using oo::str::encodeLossy;
	OO_CHECK_EQ(bytes(encodeLossy("plain ASCII", Encoding::windowsCP1252)), std::string("plain ASCII"));
	OO_CHECK_EQ(bytes(encodeLossy("", Encoding::windowsCP1252)), std::string(""));
	OO_CHECK_EQ(bytes(encodeLossy(U({0xE9, 0x20AC}), Encoding::windowsCP1252)), std::string("\xE9\x80"));
	OO_CHECK_EQ(bytes(encodeLossy(U({0x416}), Encoding::windowsCP1251)), std::string("\xC6"));
	OO_CHECK_EQ(bytes(encodeLossy(U({0x106}), Encoding::windowsCP1250)), std::string("\xC6"));        // native
	OO_CHECK_EQ(bytes(encodeLossy(U({0x106}), Encoding::windowsCP1252)), std::string("\xB4" "C"));    // acute + C
	OO_CHECK_EQ(bytes(encodeLossy(U({0x106}), Encoding::windowsCP1251)), std::string("'C"));          // no acute there
	OO_CHECK_EQ(bytes(encodeLossy(U({0x2047}), Encoding::windowsCP1252)), std::string("??"));         // a transliteration
	OO_CHECK_EQ(bytes(encodeLossy(U({0x4E2D}), Encoding::windowsCP1252)), std::string("?"));          // none
	OO_CHECK_EQ(bytes(encodeLossy(U({0xD83D, 0xDE00}), Encoding::windowsCP1252)), std::string(":-D"));
	OO_CHECK_EQ(bytes(encodeLossy(U({0xD83C, 0xDF00}), Encoding::windowsCP1252)), std::string("??"));  // per unit
	OO_CHECK_EQ(bytes(encodeLossy(U({0x61, 0xDC00, 0x7A}), Encoding::windowsCP1252)), std::string("a?z"));
	OO_CHECK_EQ(bytes(encodeLossy(U({0x61, 0xD83D, 0x7A}), Encoding::windowsCP1252)), std::string("a?z"));
	OO_CHECK(!encodeLossy(U({0x61, 0xD83D}), Encoding::windowsCP1252));                              // nil
	OO_CHECK_EQ(bytes(encodeLossy(U({0xD835, 0xDC00}), Encoding::windowsCP1252)), std::string("A"));  // MATHEMATICAL BOLD A
}

OO_TEST(convertForFontAppliesTheShippedSubstitutions)
{
	// Resources/Config/oolite-font.plist's substitutions (key order irrelevant: none overlap).
	const std::vector<std::pair<std::string, std::string>> subs = {
		{U({0x20A2}), U({0x20AC})}, {U({0x2318}), "(Command)"}, {U({0x2325}), "(Option)"}, {U({0x2303}), "(Control)"},
		{U({0x2605}), "\b"}, {U({0x272F}), "\b"}, {U({0x2606}), "\030"}, {U({0x266D}), "b"}, {U({0x266E}), "="},
		{U({0x266F}), "#"}, {U({0x200A}), "\037"},
	};
	OO_CHECK_EQ(bytes(oo::str::convertForFont(U({0x20A2, 0x31, 0x30, 0x30}), Encoding::windowsCP1252, subs)), std::string("\x80" "100"));
	OO_CHECK_EQ(bytes(oo::str::convertForFont(U({0x2605, 0x20, 0x2606}), Encoding::windowsCP1252, subs)), std::string("\b \030"));
	OO_CHECK_EQ(bytes(oo::str::convertForFont(U({0x2318, 0x51}), Encoding::windowsCP1252, subs)), std::string("(Command)Q"));
	OO_CHECK_EQ(bytes(oo::str::convertForFont(U({0x43, 0x266F, 0x200A, 0x78}), Encoding::windowsCP1252, subs)), std::string("C#\037x"));
	OO_CHECK_EQ(bytes(oo::str::convertForFont(U({0x2605, 0x301}), Encoding::windowsCP1252, subs)), std::string("??"));
}

OO_TEST_MAIN()
