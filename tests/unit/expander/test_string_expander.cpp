/*	test_string_expander.cpp
	Differential regression test for src/Core/OOStringExpander.mm (bead oo-3rb.61).

	The engine of cxx_OOExpandDescriptionString() moved from Foundation strings onto UTF-16 units and oo::str.
	Before that, this program was built against the ORIGINAL OOStringExpander.mm (gnustep-base
	1.31.1) with the stubs in this directory standing in for Universe, PlayerEntity,
	ResourceManager, the JavaScript engine and the credit formatter, and it recorded one line per
	expansion: the result's UTF-16 units, the two random generators' next values (so the engine
	must consume them identically) and everything the expander logged. The digests below are
	FNV-1a over those lines; the converted engine reproduces them exactly.

	Corpora:
	  - every key of the shipped Resources/Config/descriptions.plist, 16 planet seeds, 5 option
	    sets (plain; good RNG; good RNG with \n conversion; JavaScript warnings; %I disallowed),
	    with overrides and legacy locals, plus the system description of each seed;
	  - 20,000 generated strings (ExpressionCorpus) mixing [keys], [digits], operator chains
	    with and without parameters, every %-escape, \n, \x7F, byte-order marks, combining marks
	    and lone surrogates, under the same 5 option sets.
	Two things are normalised because they are not the engine's: the character of GNUstep's
	"%lc" in the unknown-escape warning (it printed the argument's garbage high byte, which varied
	from run to run) keeps only its low byte, and an exception is recorded by name only (its
	reason quotes a source line number and a C++ signature).

	C++ since bead oo-6e1.2 (std-2026-10-19 item 1): the harness was Objective-C++ on gnustep-base
	(Foundation string and dictionary records, the Objective-C PlayerEntity stub answering by selector, the
	expander's Foundation test surface). It now drives cxx_OOExpandDescriptionString and
	cxx_OOGenerateSystemDescription directly with the same inputs, reads the plists with oofnd's
	parser (the game's), and builds every recorded line from the same UTF-16 units, so the
	recorded digests are unchanged.

	Built and run by tools/check-string-expander.sh (it copies OOStringExpander.mm next to these
	stubs so that its quote-includes find them). Run with --print to see the lines.
*/

#include "Universe.h"
#include "PlayerEntity.h"
#include "ResourceManager.h"
#include "OOJavaScriptEngine.h"
#include "OOStringParsing.h"
#include "OOStringExpander.h"
#include "legacy_random.h"
#include "oofnd/Exception.hpp"
#include "oofnd/FileSystem.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/PListParsing.hpp"
#include "oofnd/String.hpp"
#include <algorithm>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <format>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace {

using Units = std::u16string;

std::vector<Units> sLog;
oo::PList sDescriptions;
oo::PList sWhitelist;

Units U(std::string_view utf8)  { return oo::utf8ToUtf16(utf8); }

/*	A string gnustep-base 1.31.1's -stringByAppendingString: and -stringByReplacingCharactersInRange:
	answered (the Objective-C harness built its keys and masked its messages with them): the units,
	except that a leading U+FEFF was taken as a byte-order mark and dropped, and a leading U+FFFE was
	dropped and every other unit byte-swapped (measured on main a357f5933: "￾" + "num" gave
	U+6E00 U+7500 U+6D00, "﻿﻿" + "num" gave U+FEFF "num"). -appendString:,
	-stringWithFormat: and -initWithBytes:length:encoding: kept every unit.
*/
Units GSDerived(Units units)
{
	if (!units.empty() && units.front() == 0xFEFF)
	{
		units.erase(0, 1);
	}
	else if (!units.empty() && units.front() == 0xFFFE)
	{
		units.erase(0, 1);
		for (char16_t &c : units)  c = static_cast<char16_t>((c << 8) | (c >> 8));
	}
	return units;
}

// --- logging and JavaScript warnings ------------------------------------------------------

Units MaskPercentLc(Units message)
{
	static const Units kPrefix = u"Unknown escape code in string: %";
	const std::size_t at = message.find(kPrefix);
	if (at == Units::npos || at + kPrefix.size() >= message.size())  return message;
	message[at + kPrefix.size()] = static_cast<char16_t>(message[at + kPrefix.size()] & 0xFF);
	return GSDerived(message);
}

// The expander logs through oo::log since bead oo-3rb.315: its finished lines ("[class] function:
// message") reach this sink (installed in main()). A failed assertion (OOCAssert) logs here too, in
// class "gnustep"; the Foundation assertion's log line went to stderr and was never recorded (and the line quotes the
// temporary copy's path), so it is left out, as it was.
void HarnessLogSink(std::string_view line)
{
	if (line.starts_with("[gnustep] "))
	{
		std::fprintf(stderr, "%.*s\n", static_cast<int>(line.size()), line.data());
		return;
	}
	sLog.push_back(MaskPercentLc(U(line)));
}

}	// namespace

void OOLogIndent(void) {}
void OOLogOutdent(void) {}
void OOLogPushIndent(void) {}
void OOLogPopIndent(void) {}

ooscript::Context OOJSAcquireContext(void) { return ooscript::Context{nullptr}; }
void OOJSRelinquishContext(ooscript::Context context) { (void)context; }
// The C++ form (printf format) the expander calls since bead oo-vp0y.10.
void cxx_OOJSReportWarningWithArguments(ooscript::Context context, const char *format, va_list args)
{
	(void)context;
	sLog.push_back(u"JS warning: " + MaskPercentLc(U(oo::str::vformat(format, args))));
}

std::string OOHarnessCredits(OOCreditsQuantity tenths, bool decimal)
{
	return decimal ? std::format("{}.{} Cr", static_cast<unsigned long long>(tenths / 10), static_cast<unsigned long long>(tenths % 10))
				   : std::format("{} Cr", static_cast<unsigned long long>(tenths / 10));
}

// --- lookups -------------------------------------------------------------------------------

Random_Seed OOHarnessSystemManager::getRandomSeedForCurrentSystem() { Random_Seed s = {1, 2, 3, 4, 5, 6}; return s; }

const oo::PList *Universe::descriptions()
{
	static const oo::PList *descriptions = new oo::PList(sDescriptions);
	return descriptions;
}
std::optional<std::string> Universe::getSystemName(OOSystemID sys)  { return std::format("Sys{}", static_cast<int>(sys)); }
std::optional<std::string> Universe::getSystemName(OOSystemID sys, OOGalaxyID gal)  { return std::format("G{}Sys{}", static_cast<int>(gal), static_cast<int>(sys)); }
OOHarnessSystemManager *Universe::getSystemManager()  { static OOHarnessSystemManager manager; return &manager; }
static Universe *sUniverse;
Universe *OOGetUniverse(void) { return sUniverse; }

// The player's by-name queries are recorded (PlayerEntity.h).
void OOHarnessRecordQuery(const std::string &name)
{
	sLog.push_back(U(std::format("query {}", name)));
}

static OOHarnessPlayer *sPlayer;
OOHarnessPlayer *OOHarnessGetPlayer(void) { return sPlayer; }

oo::PList ResourceManager::whitelistDictionary() { return sWhitelist; }	// C++ since bead oo-9ht.150

// --- recording -----------------------------------------------------------------------------

namespace {

uint64_t sHash;
bool sPrint;
unsigned sLines;

void HashLine(const Units &line)
{
	for (char16_t c : line)
	{
		sHash = (sHash ^ (c & 0xFF)) * 1099511628211ULL;
		sHash = (sHash ^ (c >> 8)) * 1099511628211ULL;
	}
	sHash = (sHash ^ '\n') * 1099511628211ULL;
	sLines++;
	if (sPrint)  std::printf("%s\n", oo::utf16ToUtf8(line).c_str());
}

Units Quoted(const std::optional<Units> &s)
{
	if (!s.has_value())  return u"nil";
	Units out = u"\"";
	for (char16_t c : *s)
	{
		if (c >= 0x20 && c < 0x7F && c != '\\' && c != '"')  out.push_back(c);
		else  out += U(std::format("\\u{:04X}", static_cast<unsigned>(c)));
	}
	out += u"\"";
	return out;
}

std::optional<Units> UnitsOf(const std::optional<std::string> &s)
{
	if (!s.has_value())  return std::nullopt;
	return U(*s);
}

void Record(const Units &label, const std::optional<Units> &result)
{
	unsigned r1 = Ranrot();
	int r2 = gen_rnd_number();
	HashLine(label + u" => " + Quoted(result) + U(std::format(" | rng {} {}", r1, r2)));
	for (const Units &line : sLog)  HashLine(u"    log " + Quoted(line));
	sLog.clear();
}

// The overrides and legacy locals every expansion gets: @12.5 was a double number object, @3 an int one.
const oo::PList &Overrides()
{
	static const oo::PList overrides(oo::PList::Dict{
		{ "self:name", oo::PList(std::string("Bob")) },
		{ "num", oo::PList(12.5) },
		{ "big", oo::PList(std::string("123456789012.25")) },
		{ "pr", oo::PList(std::string("%R")) },
		{ "arr", oo::PList(oo::PList::Array{ oo::PList(std::string("x")) }) },
		{ "neg", oo::PList(std::string("-3.75")) },
	});
	return overrides;
}

const oo::PList &Locals()
{
	static const oo::PList locals(oo::PList::Dict{
		{ "local_x", oo::PList::signedInteger(3) },
		{ "local_s", oo::PList(std::string("loc%H")) },
	});
	return locals;
}

std::optional<Units> Expand(Random_Seed seed, const Units &string, const std::optional<std::string> &systemName, OOExpandOptions options)
{
	try
	{
		return UnitsOf(cxx_OOExpandDescriptionString(seed, oo::utf16ToUtf8(string), Overrides(), Locals(), systemName, options));
	}
	catch (const oo::Exception &e)	// was @catch (OOException *e) (bead oo-rskgl.1)
	{
		sLog.push_back(u"EXCEPTION " + U(e.name()));
	}
	return std::nullopt;
}

const OOExpandOptions kOptionSets[] =
{
	kOOExpandNoOptions, kOOExpandGoodRNG, kOOExpandBackslashN | kOOExpandGoodRNG, kOOExpandForJavaScript, kOOExpandDisallowPercentI
};
enum { kOptionCount = sizeof kOptionSets / sizeof *kOptionSets };

// --- the generated expressions -------------------------------------------------------------

struct ExpressionCorpus
{
	uint64_t s;
	const std::vector<Units> *keys;
	uint32_t next()
	{
		s ^= s << 13;
		s ^= s >> 7;
		s ^= s << 17;
		return (uint32_t)(s >> 32);
	}
	const Units &pick(const std::vector<Units> &a) { return a[next() % a.size()]; }
	Units key()
	{
		static const std::vector<Units> special = { u"commander_name", u"commander_shipdisplayname", u"credits_number", u"_oo_legacy_credits_number",
			u"self:name", u"num", u"big", u"pr", u"neg", u"arr", u"local_x", u"local_s", u"mission_foo", u"mission_x_nil",
			u"oolite_key_x", u"oolite_key_", u"dockedStationName_string", u"foo_string", u"bar_number", u"baz_bool",
			u"unknownkey", u"system_description" };
		static const std::vector<Units> boms = { u"﻿", u"￾", u"﻿﻿" };
		Units k;
		switch (next() % 5)
		{
			case 0: case 1: k = pick(*keys); break;
			case 2: case 3: k = pick(special); break;
			default: k = U(std::format("{}", next() % 41));
		}
		if (next() % 10 == 0)  k = GSDerived(pick(boms) + k);	// [bom stringByAppendingString:k]
		return k;
	}
	Units expression()
	{
		static const std::vector<Units> ops = { u"cr", u"dcr", u"icr", u"idcr", u"precision", u"multiply", u"add", u"bogus", u"", u"ćr" };
		static const std::vector<Units> params = { u"1", u"-3", u"0", u"2.5", u"abc", u"12", u"1e3", u"", u" 7", u"3́", u"-1", u"20", u"1e400" };
		Units s = u"[" + key();
		static const unsigned kOpCounts[] = {0, 0, 1, 1, 2, 3};
		for (unsigned n = kOpCounts[next() % 6]; n > 0; n--)
		{
			s += u"|" + pick(ops);
			if (next() % 5 < 3)  s += u":" + pick(params);
			if (next() % 20 == 0)  s += u"́";
		}
		if (next() % 20 == 0)  s += u"|́|cr";
		s += u"]";
		return s;
	}
	Units string()
	{
		static const std::vector<Units> literals = { u"a", u"Hello ", u"x", u"  ", u"\n", u"\\n", u"\\", u"\x7F", u"﻿", u"￾", u"́",
			u"é", u"é", u"|", u":", u"%", u"%%", u"%[", u"%]", u"%H", u"%I", u"%N", u"%R", u"%Ŕ",
			u"%J007", u"%J256", u"%J07", u"%G123001", u"%G123009", u"%G12300", u"%@", u"%d", u"%.", u"%q", u"[",
			u"]", u"[]", u"[5]", u"[0]", u"[999]", u"[22]", u"9", u"0", u"Ā", Units(1, static_cast<char16_t>(0xD800)),
			u"﻿﻿z" };
		Units s;
		for (unsigned n = 1 + next() % 8; n > 0; n--)
		{
			if (next() % 20 < 9)  s += expression();
			else  s += pick(literals);
		}
		return s;
	}
};

/*	+dictionaryWithContentsOfFile: of gnustep-base 1.31.1, through which the recorded
	digests read both plists: it read an old-style file with no byte-order mark as ISO-8859-1 (each
	byte one UTF-16 unit; descriptions.plist's UTF-8 "\xE2\x80\x99" became U+00E2 U+0080 U+0099,
	measured on main a357f5933 with the Objective-C harness's --print), then parsed the text. The
	bytes are widened the same way here and the text parsed with oofnd's parser. (The game reads
	the file as UTF-8 since oo-qps; the digests pin the expander, not the file reader.)
*/
oo::PList DictionaryWithContentsOfFile(const char *path)
{
	const auto data = oo::fs::readFile(oo::fs::pathFromUTF8(path));
	if (!data)  return oo::PList();
	Units latin1;
	for (char byte : data->stringView())  latin1.push_back(static_cast<char16_t>(static_cast<unsigned char>(byte)));
	auto plist = oo::parsePropertyListData(oo::utf16ToUtf8(latin1));
	if (!plist || !plist->isDict())  return oo::PList();
	return std::move(*plist);
}

}	// namespace

int main(int argc, char **argv)
{
	if (argc < 3)
	{
		std::fprintf(stderr, "usage: %s descriptions.plist whitelist.plist [--print]\n", argv[0]);
		return 2;
	}
	sPrint = argc > 3 && std::strcmp(argv[3], "--print") == 0;
	// oo::log as the old stubs behaved: every class shows, "[class] function: message".
	oo::log::logger().setSink(&HarnessLogSink);
	oo::log::logger().setInitialized(true);
	oo::log::logger().setOptions(oo::log::Options{ .showFunction = true, .showFileAndLine = false, .showClass = true, .showTime = false });
	sUniverse = new Universe();
	sPlayer = new OOHarnessPlayer();
	sDescriptions = DictionaryWithContentsOfFile(argv[1]);
	sWhitelist = DictionaryWithContentsOfFile(argv[2]);
	if (sDescriptions.isNull() || sWhitelist.isNull())
	{
		std::fprintf(stderr, "test_string_expander: cannot read %s or %s\n", argv[1], argv[2]);
		return 2;
	}
	// [[sDescriptions allKeys] sortedArrayUsingSelector:@selector(compare:)]: by UTF-16 unit.
	std::vector<Units> keys;
	for (const auto &entry : *sDescriptions.getIf<oo::PList::Dict>())  keys.push_back(U(entry.first));
	std::sort(keys.begin(), keys.end());

	// Every descriptions.plist key.
	sHash = 14695981039346656037ULL;
	for (unsigned s = 0; s < 16; s++)
	{
		Random_Seed seed = { (uint8_t)(0x4A + 17 * s), (uint8_t)(0x5A + 3 * s), (uint8_t)(0x48 ^ s), (uint8_t)(0x02 + s), (uint8_t)(0x53 + 29 * s), (uint8_t)(0xB7 - 11 * s) };
		for (const Units &key : keys)
		{
			for (unsigned o = 0; o < kOptionCount; o++)
			{
				ranrot_srand(1000 + s * 7 + o);
				seed_for_planet_description(seed);
				std::optional<Units> r = Expand(seed, key, (o & 1) ? std::optional<std::string>("Zaonce") : std::nullopt, kOptionSets[o] | kOOExpandKey);
				Record(U(std::format("seed {} key ", s)) + key + U(std::format(" opt {}", o)), r);
			}
		}
		ranrot_srand(77 + s);
		Record(u"system description", UnitsOf(cxx_OOGenerateSystemDescription(seed, std::string("Riedquat"))));
	}
	const uint64_t keysHash = sHash;
	const unsigned keysLines = sLines;

	// Generated expressions.
	sHash = 14695981039346656037ULL;
	sLines = 0;
	ExpressionCorpus corpus = { 0x61, &keys };
	for (unsigned n = 0; n < 20000; n++)
	{
		Units input = corpus.string();
		Random_Seed seed = { (uint8_t)n, (uint8_t)(n >> 8), 3, 4, 5, (uint8_t)(n * 7) };
		for (unsigned o = 0; o < kOptionCount; o++)
		{
			ranrot_srand(n * 5 + o);
			seed_for_planet_description(seed);
			std::optional<Units> r = Expand(seed, input, (o & 1) ? std::optional<std::string>("Zaonce") : std::nullopt, kOptionSets[o]);
			Record(U(std::format("string {} opt {}", n, o)), r);
		}
	}
	const uint64_t stringsHash = sHash;

	// Regression (bead oo-3rb.69): a replacement of "\x7F" eats the character after it. At the end
	// of the (sub-)string there is none; the upstream engine then asserted in AppendCharacters
	// (start > end) and raised out of OOExpandDescriptionString. It now eats nothing there.
	int regressionFailures = 0;
	{
		Random_Seed seed = { 1, 2, 3, 4, 5, 6 };
		const oo::PList del(oo::PList::Dict{ { "del", oo::PList(std::string("\x7F")) } });
		const Units cases[][2] =
		{
			{ u"a[del]", u"a" },		// at the end: eats nothing (asserted before)
			{ u"ab[del]", u"ab" },		// at the end: eats nothing (asserted before)
			{ u"a[del]bc", u"ac" },		// in the middle: eats "b", as always
			{ u"[del]x", u"" },			// the whole string, as always
		};
		for (const auto &c : cases)
		{
			std::optional<Units> r;
			try
			{
				r = UnitsOf(cxx_OOExpandDescriptionString(seed, oo::utf16ToUtf8(c[0]), del, oo::PList(), std::nullopt, kOOExpandNoOptions));
			}
			catch (const oo::Exception &e)	// was @catch (OOException *e) (bead oo-rskgl.1)
			{
				std::fprintf(stderr, "test_string_expander: %s raised %s\n", oo::utf16ToUtf8(Quoted(c[0])).c_str(), e.name());
				regressionFailures++;
				continue;
			}
			if (!r.has_value() || *r != c[1])
			{
				std::fprintf(stderr, "test_string_expander: %s gave %s, expected %s\n", oo::utf16ToUtf8(Quoted(c[0])).c_str(), oo::utf16ToUtf8(Quoted(r)).c_str(), oo::utf16ToUtf8(Quoted(c[1])).c_str());
				regressionFailures++;
			}
		}
		sLog.clear();
	}

	// Captured from the original OOStringExpander.mm (see the banner). Re-captured with Jon's
	// approval, 2026-09-29 (bead oo-qqz6; were 0xdaec14b5265fca36 / 0x07a1e83ff98956eb): every
	// expansion result and RNG draw is unchanged; only log text differs - 7845 lines name a
	// non-string value by its contents instead of its class (oo-qps.50), and 22 JS warnings end at
	// an embedded NUL, as the C string the JS engine receives always did (oo-kpxgo).
	// kStringsDigest re-captured with Jon's approval, 2026-09-29 (bead oo-3rb.69; was
	// 0xdc8ef7032bfb6797): the \x7F fix changes exactly the 12 records that raised before.
	const uint64_t kKeysDigest = 0x6349f869900cf779ULL, kStringsDigest = 0xef7448c0016ba2edULL;
	int failures = regressionFailures;
	if (keysHash != kKeysDigest)
	{
		std::fprintf(stderr, "test_string_expander: descriptions.plist keys digest 0x%016llx, expected 0x%016llx (%u lines)\n", (unsigned long long)keysHash, (unsigned long long)kKeysDigest, keysLines);
		failures++;
	}
	if (stringsHash != kStringsDigest)
	{
		std::fprintf(stderr, "test_string_expander: generated strings digest 0x%016llx, expected 0x%016llx (%u lines)\n", (unsigned long long)stringsHash, (unsigned long long)kStringsDigest, sLines);
		failures++;
	}
	if (failures == 0)  std::fprintf(stderr, "test_string_expander: OK (%u + %u lines)\n", keysLines, sLines);
	return failures == 0 ? 0 : 1;
}
