/*	test_log.cpp
	oo::log (oofnd/Log.hpp, bead oo-qpb) against the Objective-C OOLogging.mm it replaces.

	The expectation below is the complete output of a throwaway probe (not committed) that linked
	the ORIGINAL src/Core/OOLogging.mm against gnustep-base 1.31.1, with ResourceManager, the
	output handler and the log header stubbed so that every line OOLogging handed to the output
	handler was printed ("OUT|<line>|"), alongside its answers to OOLogWillDisplayMessagesInClass
	("Q|<class>|<0/1>"). This test performs the same calls, in the same order, through oo::log and
	prints the same way; the two transcripts must be identical. The same probe, relinked against
	the new OOLogging.mm (the Objective-C shell over oo::log), printed the same transcript.

	Only the time stamp is not replayed through the clock: the probe pinned +[NSDate date], so
	those lines are composed here with the time text the probe printed, and timeStamp() is tested
	on its own (local time, milliseconds truncated, as GNUstep's %F).
*/

#define true						1
#define false						0
#include "oofnd/Log.hpp"
#include <type_traits>
static_assert(std::is_same_v<decltype(true), int>, "Log.hpp must restore OOCocoa.h's true macro");
#undef true
#undef false

#include "oo_test.hpp"

#include <chrono>
#include <cstdio>
#include <ctime>
#include <string>
#include <utility>
#include <vector>

namespace {

using oo::log::RawSetting;
using Entries = std::vector<std::pair<std::string, RawSetting>>;

std::string gTranscript;

void Capture(std::string_view line)
{
	gTranscript += "OUT|";
	gTranscript += line;
	gTranscript += "|\n";
}

oo::log::Logger& L() { return oo::log::logger(); }

// logcontrol.plist as the probe built it, in the order the NSDictionary enumerated it.
const Entries& Control()
{
	static const Entries entries = {
		{"a.e", RawSetting::string("On")}, {"a.b.c", RawSetting::string("inherit")}, {"numf", RawSetting::boolean(true)},
		{"z.on", RawSetting::string("$metaOn")}, {"a.g", RawSetting::string("inherited")}, {"t", RawSetting::string("true")},
		{"m", RawSetting::string("$meta1")}, {"num0", RawSetting::boolean(false)}, {"bad1", RawSetting::string("maybe")},
		{"_default", RawSetting::string("no")}, {"a.b", RawSetting::string("no")}, {"bad3", RawSetting::string("")},
		{"a", RawSetting::string("yes")}, {"x.y", RawSetting::string("$meta1")}, {"$metaOn", RawSetting::string("on")},
		{"$meta2", RawSetting::string("off")}, {"a.f", RawSetting::string("FALSE")}, {"a.b.d", RawSetting::string("YES")},
		{"bad2", RawSetting::other("(1, x)")}, {"num1", RawSetting::boolean(true)}, {"u", RawSetting::string("$undefined")},
		{"space", RawSetting::string(" yes")}, {"$meta1", RawSetting::string("$meta2")},
	};
	return entries;
}

const Entries& BuiltIn()
{
	static const Entries entries = {{"general.error", RawSetting::string("yes")}, {"dataCache", RawSetting::string("no")}};
	return entries;
}

Entries gControl;

// OOLoggingReloadSettings() with the given show-* switches, as the probe's Flags() did.
void Flags(bool function, bool fileLine, bool cls, bool time)
{
	oo::log::Options o;
	o.showFunction = function;
	o.showFileAndLine = fileLine;
	o.showClass = cls;
	o.showTime = time;
	L().setOptions(o);
	L().replaceSettings(BuiltIn(), false);
	L().replaceSettings(gControl, true);
	char buf[96];
	std::snprintf(buf, sizeof buf, "FLAGS function=%d fileline=%d class=%d time=%d\n", function, fileLine, cls, time);
	gTranscript += buf;
}

void Query(const char* cls)
{
	gTranscript += std::string("Q|") + cls + "|" + (oo::log::willDisplay(cls) ? "1" : "0") + "\n";
}

void Log(const char* cls, const char* function, const char* file, unsigned long line, const std::string& message)
{
	L().write(cls, function, file, line, message);
}

// A time-stamped line as the probe's pinned clock produced it.
void Timed(const char* time, const char* function, unsigned long line, const char* message)
{
	Capture(oo::log::composeLine(L().options(), "a", function, "../../src/Core/Entities/ShipEntity.mm", line, message,
		oo::log::indentLevel(), time));
}

const char* const kExpected = R"LOG(OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "maybe" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "(1, x)" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value " yes" (expected yes, no, inherit or $metaclass).|
Q|a|1
Q|a.b|0
Q|a.b.c|0
Q|a.b.c.d|0
Q|a.b.d|1
Q|a.e|1
Q|a.f|0
Q|a.g|1
Q|a.z|1
Q|num1|1
Q|num0|0
Q|numf|1
Q|m|0
Q|m.sub|0
OUT|OOLogging internal - ResolveMetaClassReference: Reference to undefined metaclass $undefined, falling back to _default.|
Q|u|0
Q|bad1|0
Q|bad2|0
Q|x.y|0
Q|x|0
Q|unknown|0
Q||0
Q|a.|1
Q|.a|0
Q|a..b|1
Q|A|0
Q|t|1
Q|z.on|1
Q|z.on.x|1
Q|bad3|0
Q|space|0
Q|general.error|0
Q|dataCache|0
Q|$meta1|0
Q|$metaOn|1
Q|a.b|1
Q|a.b.c|1
Q|a.b.d|1
Q|new.cls.x|0
Q|new|0
PARENT|a.b|(nil)|a|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "maybe" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "(1, x)" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value " yes" (expected yes, no, inherit or $metaclass).|
FLAGS function=0 fileline=0 class=0 time=0
OUT|msg 7 s|
OUT|no file|
OUT|null function|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "maybe" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "(1, x)" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value " yes" (expected yes, no, inherit or $metaclass).|
FLAGS function=0 fileline=0 class=1 time=0
OUT|[a]: msg 7 s|
OUT|[a]: no file|
OUT|[a]: null function|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "maybe" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "(1, x)" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value " yes" (expected yes, no, inherit or $metaclass).|
FLAGS function=0 fileline=1 class=0 time=0
OUT|ShipEntity.mm:4242: msg 7 s|
OUT|no file|
OUT|ShipEntity.mm:2: null function|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "maybe" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "(1, x)" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value " yes" (expected yes, no, inherit or $metaclass).|
FLAGS function=0 fileline=1 class=1 time=0
OUT|[a] ShipEntity.mm:4242: msg 7 s|
OUT|[a] no file|
OUT|[a] ShipEntity.mm:2: null function|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "maybe" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "(1, x)" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value " yes" (expected yes, no, inherit or $metaclass).|
FLAGS function=1 fileline=0 class=0 time=0
OUT|-[ShipEntity update:]: msg 7 s|
OUT|Func: no file|
OUT|(null): null function|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "maybe" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "(1, x)" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value " yes" (expected yes, no, inherit or $metaclass).|
FLAGS function=1 fileline=0 class=1 time=0
OUT|[a] -[ShipEntity update:]: msg 7 s|
OUT|[a] Func: no file|
OUT|[a] (null): null function|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "maybe" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "(1, x)" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value " yes" (expected yes, no, inherit or $metaclass).|
FLAGS function=1 fileline=1 class=0 time=0
OUT|-[ShipEntity update:] (ShipEntity.mm:4242): msg 7 s|
OUT|Func: no file|
OUT|(null) (ShipEntity.mm:2): null function|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "maybe" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "(1, x)" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value " yes" (expected yes, no, inherit or $metaclass).|
FLAGS function=1 fileline=1 class=1 time=0
OUT|[a] -[ShipEntity update:] (ShipEntity.mm:4242): msg 7 s|
OUT|[a] Func: no file|
OUT|[a] (null) (ShipEntity.mm:2): null function|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "maybe" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "(1, x)" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value " yes" (expected yes, no, inherit or $metaclass).|
FLAGS function=0 fileline=0 class=1 time=0
OUT|[a]: indent 0|
OUT|  [a]: indent 1|
OUT|    [a]: indent 2|
OUT|                                                              [a]: indent 31|
OUT|                                                                [a]: indent 32|
OUT|                                                                [a]: indent 33|
OUT|                                                                [a]: indent 34|
OUT|[a]: after outdent|
OUT|                                                                [a]: after pop|
OUT|OOLogging internal - OOLogPopIndent: OOLogPopIndent(): state stack underflow.|
OUT|      [a]: three|
OUT|  [a]: one|
OUT|[a]: zero|
OUT|[a]: multi
line|
OUT|[a]: ***** ERROR: err 1|
OUT|[a]: ----- WARNING: warn 2|
OUT|[a.f]: not short-circuited: printed anyway|
OUT|

========== [Marker 1] ==========|
OUT|

========== [Marker 2] ==========|
ABBREV|Foo.mm|Foo.mm|y.mm|b|unspecified file
OUT|temporary no class|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "maybe" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "(1, x)" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value " yes" (expected yes, no, inherit or $metaclass).|
FLAGS function=0 fileline=0 class=1 time=1
TIME 1000000000.000000
OUT|21:46:40.000 [a]: timed|
TIME 1000000000.000400
OUT|21:46:40.000 [a]: timed|
TIME 1000000000.000500
OUT|21:46:40.000 [a]: timed|
TIME 1000000000.999400
OUT|21:46:40.999 [a]: timed|
TIME 1000000000.999500
OUT|21:46:40.999 [a]: timed|
TIME 1000000000.999900
OUT|21:46:40.999 [a]: timed|
TIME 1000000000.123456
OUT|21:46:40.123 [a]: timed|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "maybe" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value "(1, x)" (expected yes, no, inherit or $metaclass).|
OUT|OOLogging internal - LoadExplicitSettingsFromDictionary: Bad setting value " yes" (expected yes, no, inherit or $metaclass).|
FLAGS function=1 fileline=1 class=1 time=1
OUT|21:46:40.500 [a] -[X y] (ShipEntity.mm:9): everything|
OUT|OOLogging internal - LoadExplicitSettings: _default may not be set to a metaclass, ignoring.|
FLAGS function=0 fileline=0 class=1 time=0
Q|q|1
Q|anything|1
OUT|OOLogging internal - LoadExplicitSettings: _override may not be set to a metaclass, ignoring.|
FLAGS function=0 fileline=0 class=1 time=0
Q|q|1
Q|anything|1
FLAGS function=0 fileline=0 class=1 time=0
Q|q|0
)LOG";

} // namespace

OO_TEST(timeStampIsLocalTimeWithTruncatedMilliseconds)
{
	using namespace std::chrono;
	const system_clock::time_point base = system_clock::from_time_t(1000000000);
	std::tm tm{};
	const std::time_t t = 1000000000;
#ifdef _WIN32
	localtime_s(&tm, &t);
#else
	localtime_r(&t, &tm);
#endif
	char hms[16];
	std::strftime(hms, sizeof hms, "%H:%M:%S", &tm);
	OO_CHECK_EQ(oo::log::timeStamp(base), std::string(hms) + ".000");
	OO_CHECK_EQ(oo::log::timeStamp(base + microseconds(999999)), std::string(hms) + ".999");
	OO_CHECK_EQ(oo::log::timeStamp(base + microseconds(123456)), std::string(hms) + ".123");
	OO_CHECK_EQ(oo::log::timeStamp(base + microseconds(500)), std::string(hms) + ".000");
}

OO_TEST(formatFrontEndAndSettingsEdges)
{
	std::vector<std::string> lines;
	static std::vector<std::string>* sLines = nullptr;
	sLines = &lines;
	L().setSink([](std::string_view line) { sLines->emplace_back(line); });
	L().setInitialized(true);
	oo::log::Options o;
	o.showClass = true;
	L().setOptions(o);
	L().replaceSettings({{"x", RawSetting::string("on")}, {"$loop1", RawSetting::string("$loop2")}, {"$loop2", RawSetting::string("$loop1")},
							{"loop", RawSetting::string("$loop1")}, {"_default", RawSetting::string("off")}, {"_override", RawSetting::string("inherit")}},
		true);
	// This runs first: no _override is in effect yet (once set, it stays until set again).
	OO_CHECK(oo::log::willDisplay("x.y"));
	OO_CHECK(!oo::log::willDisplay("loop"));			// a metaclass cycle falls back to _default
	OO_LOG("x", "n = {}, s = {}, f = {:.2f}", 42, "str", 2.5);
	OO_LOG("hidden", "not {}", "shown");
	OO_LOG_WARN("x", "careful: {}", 1);
	oo::log::indentIf("x");
	OO_LOG("x.deep", "{}", "indented");
	oo::log::outdentIf("x");
	OO_CHECK(lines.size() == 3);
	if (lines.size() == 3)
	{
		OO_CHECK_EQ(lines[0], std::string("[x]: n = 42, s = str, f = 2.50"));
		OO_CHECK_EQ(lines[1], std::string("[x]: ----- WARNING: careful: 1"));
		OO_CHECK_EQ(lines[2], std::string("  [x.deep]: indented"));
	}
	OO_CHECK_EQ(oo::log::indentLevel(), 0u);

	L().setInitialized(false);
	OO_CHECK(!oo::log::willDisplay("x"));
	OO_CHECK(!lines.empty() && lines.back() == "OOLogging internal - Inited: ***** ERROR: OOLoggingInit() has not been called.");
	L().setInitialized(true);
	L().setSink(nullptr);
}

OO_TEST(transcriptMatchesTheOriginalOOLogging)
{
	L().setSink(Capture);
	L().setInitialized(true);
	gControl = Control();

	// OOLoggingInit(): the show-* defaults the probe registered, then LoadExplicitSettings().
	oo::log::Options o;
	o.showClass = true;
	L().setOptions(o);
	L().replaceSettings(BuiltIn(), false);
	L().replaceSettings(gControl, true);

	for (const char* q : {"a", "a.b", "a.b.c", "a.b.c.d", "a.b.d", "a.e", "a.f", "a.g", "a.z", "num1", "num0", "numf", "m", "m.sub",
			 "u", "bad1", "bad2", "x.y", "x", "unknown", "", "a.", ".a", "a..b", "A", "t", "z.on", "z.on.x", "bad3", "space",
			 "general.error", "dataCache", "$meta1", "$metaOn"})
	{
		Query(q);
	}
	L().setDisplay("a.b", true);
	Query("a.b");
	Query("a.b.c");
	Query("a.b.d");
	L().setDisplay("a.b", true);
	L().setDisplay("new.cls", false);
	Query("new.cls.x");
	Query("new");
	gTranscript += "PARENT|" + oo::log::parentClass("a.b.c").value_or("?") + "|" + oo::log::parentClass("a").value_or("(nil)") + "|"
		+ oo::log::parentClass("a.").value_or("?") + "|" + oo::log::parentClass(".a").value_or("?") + "\n";

	// Formatting.
	const char* file = "../../src/Core/Entities/ShipEntity.mm";
	for (int fn = 0; fn < 2; fn++)
		for (int fl = 0; fl < 2; fl++)
			for (int cl = 0; cl < 2; cl++)
			{
				Flags(fn, fl, cl, false);
				Log("a", "-[ShipEntity update:]", file, 4242, "msg 7 s");
				Log("a", "Func", nullptr, 1, "no file");
				Log("a", nullptr, file, 2, "null function");
			}
	Flags(false, false, true, false);
	for (int i = 0; i < 35; i++)
	{
		if (i <= 2 || i >= 31) Log("a", "f", file, 1, "indent " + std::to_string(i));
		oo::log::indent();
	}
	oo::log::pushIndent();
	for (int i = 0; i < 40; i++) oo::log::outdent();
	Log("a", "f", file, 1, "after outdent");
	oo::log::popIndent();
	Log("a", "f", file, 1, "after pop");
	oo::log::popIndent();
	for (int i = 0; i < 40; i++) oo::log::outdent();
	oo::log::pushIndent();
	oo::log::indent();
	oo::log::pushIndent();
	oo::log::indent();
	oo::log::indent();
	Log("a", "f", file, 1, "three");
	oo::log::popIndent();
	Log("a", "f", file, 1, "one");
	oo::log::popIndent();
	Log("a", "f", file, 1, "zero");
	Log("a", "f", file, 1, "multi\nline");
	oo::log::messageWithPrefix("a", "f", file, 1, oo::log::kErrorPrefix, "err {}", 1);
	oo::log::messageWithPrefix("a", "f", file, 1, oo::log::kWarningPrefix, "warn {}", 2);
	oo::log::messageWithPrefix("a.b.x.off", "f", file, 1, oo::log::kErrorPrefix, "hidden");
	Log("a.f", "f", file, 1, "not short-circuited: printed anyway");
	L().insertMarker();
	L().insertMarker();
	gTranscript += "ABBREV|" + oo::log::abbreviatedFileName("../../src/Core/Foo.mm") + "|" + oo::log::abbreviatedFileName("Foo.mm") + "|"
		+ oo::log::abbreviatedFileName("C:\\x\\y.mm") + "|" + oo::log::abbreviatedFileName("/a/b/") + "|"
		+ oo::log::abbreviatedFileName(nullptr) + "\n";
	L().setShowClassTemporarily(false);
	Log("a", "f", file, 1, "temporary no class");

	// The time prefix, with the probe's pinned times.
	Flags(false, false, true, true);
	static const std::pair<const char*, const char*> times[] = {{"1000000000.000000", "21:46:40.000"},
		{"1000000000.000400", "21:46:40.000"}, {"1000000000.000500", "21:46:40.000"}, {"1000000000.999400", "21:46:40.999"},
		{"1000000000.999500", "21:46:40.999"}, {"1000000000.999900", "21:46:40.999"}, {"1000000000.123456", "21:46:40.123"}};
	for (const auto& [t, text] : times)
	{
		gTranscript += std::string("TIME ") + t + "\n";
		Timed(text, "f", 1, "timed");
	}
	Flags(true, true, true, true);
	Timed("21:46:40.500", "-[X y]", 9, "everything");

	// Second configuration: _default and _override, which keep their values until set again.
	gControl = {{"_default", RawSetting::string("$nope")}, {"_override", RawSetting::string("yes")}, {"q", RawSetting::string("no")}};
	Flags(false, false, true, false);
	Query("q");
	Query("anything");
	gControl = {{"_override", RawSetting::string("$meta")}, {"_default", RawSetting::boolean(false)}, {"$meta", RawSetting::string("on")}};
	Flags(false, false, true, false);
	Query("q");
	Query("anything");
	gControl = {{"_override", RawSetting::boolean(false)}};
	Flags(false, false, true, false);
	Query("q");

	OO_CHECK_EQ(gTranscript, std::string(kExpected));
	if (gTranscript != kExpected)
	{
		std::printf("--- transcript ---\n%s--- end ---\n", gTranscript.c_str());
	}
}

OO_TEST_MAIN()
