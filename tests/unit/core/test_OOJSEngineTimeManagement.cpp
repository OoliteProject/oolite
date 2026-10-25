/*	test_OOJSEngineTimeManagement.mm
	Unit tests for the script time limiter and profiler (src/Core/Scripting/OOJSEngineTimeManagement.h/.mm):
	bead oo-cn4o, a Phase 3 conversion in the house style of the OOColor exemplar (proposed ADR-0056;
	amendment oo-ppc for the scripting files).

	The file holds the time limiter (start/stop, pause/resume), the watchdog thread that stops a
	script which runs too long, and the debug-build profiler, whose results are OOTimeProfile and
	OOTimeProfileEntry objects. The test runs them against the game's own façade backend
	(ooscript/JSEngine_quickjs.cpp) and links the game's own objects for the file and the stopwatch
	(OOProfilingStopwatch.mm). What the rest of the engine would provide is defined below as the
	smallest stand-in that does the same thing: the engine object the watchdog keeps, the running
	script (named in the "terminated" log line), the stack dump, and the property-list converter
	(recording what it is given). The file's own header imports the engine's, which the test
	defines classes of, so the test declares what it calls itself (amendment oo-z1s4 item 4). The
	expectations were written against the Objective-C file and run on it first; they pin the
	limiter's limit through nesting, an extra stop, pause and resume; the profiler's entries (names,
	hit counts, the frame kind), the profile's and entries' descriptions and property lists and the
	comparisons; and the watchdog stopping an endless script.
	Run: bash tools/check-core-tests.sh
*/

#include "oofnd/objc/OOObject.h"
#include "OOTypes.h"
#include "OODescription.h"
#include "ooscript/JSEngine.hpp"
#include "OOJSEngineNativeWrappers.h"
#include "oofnd/Log.hpp"
#include "oofnd/PList.hpp"
#include "OOObjCPList.h"

#include "oo_test.hpp"
#include "test_OOJSEngineTimeManagement.hpp"

#include <chrono>
#include <cstring>
#include <string>
#include <thread>
#include <vector>


// MARK: The file's API, as its header declares it ----------------------------------------------

class OOJavaScriptEngine;

// OOTimeProfile and OOTimeProfileEntry, as OOJSEngineTimeManagement.h declares them (test_OOJSEngineTimeManagement.hpp).

#ifndef NDEBUG
extern "C" void OOJSStartTimeLimiterWithTimeLimit_(OOTimeDelta limit, const char *file, unsigned line);
extern "C" void OOJSStopTimeLimiter_(const char *file, unsigned line);
#define StartLimiter(limit)  OOJSStartTimeLimiterWithTimeLimit_(limit, __FILE__, __LINE__)
#define StopLimiter()  OOJSStopTimeLimiter_(__FILE__, __LINE__)
#else
void OOJSStartTimeLimiterWithTimeLimit(OOTimeDelta limit);
void OOJSStopTimeLimiter(void);
#define StartLimiter(limit)  OOJSStartTimeLimiterWithTimeLimit(limit)
#define StopLimiter()  OOJSStopTimeLimiter()
#endif

extern "C" void OOJSBeginProfiling(bool trace);
oo::Ref<OOTimeProfile> OOJSEndProfiling(void);
extern "C" bool OOJSIsProfiling(void);
extern "C" void OOJSResetTimeLimiter(void);
extern "C" OOTimeDelta OOJSGetTimeLimiterLimit(void);
extern "C" void OOJSSetTimeLimiterLimit(OOTimeDelta limit);
extern "C" void OOJSTimeManagementInit(OOJavaScriptEngine *engine, ooscript::Runtime runtime);


// MARK: What the rest of the engine provides ------------------------------------------------------

namespace {
std::vector<oo::PList> sConverted;		// what OOJSValueFromPList was given
int sStackDumps = 0;
std::vector<std::string> sLogLines;
} // namespace


ooscript::Value OOJSValueFromPList(ooscript::Context, const oo::PList &plist)
{
	sConverted.push_back(plist);
	return ooscript::int32Value(static_cast<std::int32_t>(sConverted.size()));
}


std::optional<std::string> cxx_OOStringFromJSString(ooscript::Context context, ooscript::String string)
{
	if (string == nullptr)  return std::nullopt;
	std::size_t length = 0;
	const ooscript::Char16 *chars = ooscript::getStringCharsAndLength(context, string, &length);
	std::string result;
	for (std::size_t i = 0; i < length; i++)  result += static_cast<char>(chars[i]);
	return result;
}


#ifndef NDEBUG
extern "C" void OOJSDumpStack(ooscript::Context)
{
	sStackDumps++;
}
#endif


// The engine owns the runtime; the watchdog reads it from the engine's ivar, as in the game.
// The engine (a C++ class since bead oo-wdqw1 deleted its facade): reference counted, as the
// watchdog holds it; the engine owns the runtime, which the watchdog is handed with it.
class OOJavaScriptEngine : public oo::RefCounted
{
public:
	explicit OOJavaScriptEngine(ooscript::Runtime runtime) : _runtime(runtime) {}

	ooscript::Runtime _runtime;
};


#include "OOScript.h"


// OOJSScript (OOJSScript.h), which the code under test calls. Since bead oo-9ht.133 deleted the
// OOScript root's facade (a script's object since bead oo-9ht.137) a script is the C++ object, so
// the stand-in is a C++ subclass of OOScript declaring the members that code calls.
class OOJSScript : public OOScript
{
public:
	static OOJSScript *currentlyRunningScript();
	std::optional<std::string> name() override  { return std::string("test script"); }
};

// OOScript's virtual members (OOScript.mm reaches the whole game), for the test's scripts' vtable.
std::optional<std::string> OOScript::descriptionComponents()	{ return std::nullopt; }
std::optional<std::string> OOScript::name()					{ return std::nullopt; }
std::optional<std::string> OOScript::scriptDescription()		{ return std::nullopt; }
std::optional<std::string> OOScript::version()				{ return std::nullopt; }
bool OOScript::requiresTickle()								{ return false; }
void OOScript::runWithTarget(Entity *)						{}
bool OOScript::callMethod(ooscript::PropertyId, ooscript::Context, ooscript::Value *, int, ooscript::Value *)	{ return false; }
std::string OOScript::className() const						{ return "OOScript"; }
std::string OOScript::description() const						{ return "<OOScript>"; }
ooscript::Value OOScript::jsValueInContext(ooscript::Context)	{ return ooscript::undefinedValue(); }
void OOScript::clearJSSelf(ooscript::Object)					{}

OOJSScript *OOJSScript::currentlyRunningScript()  { static OOJSScript *script = oo::makeRef<OOJSScript>().leakRef(); return script; }


// MARK: Helpers -----------------------------------------------------------------------------------

namespace {

void SleepMs(int ms)
{
	std::this_thread::sleep_for(std::chrono::milliseconds(ms));
}


OOTimeProfileEntry *EntryNamed(OOTimeProfile *profile, const std::string &name)
{
	for (const auto &entry : profile->profileEntries())
	{
		if (entry->function().value_or("<none>") == name)  return entry.get();
	}
	return nullptr;
}


const oo::PList *Key(const oo::PList &dict, const char *key)
{
	return dict.get<oo::PList>(key);
}

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

OO_TEST(limiter)
{
	OO_CHECK_EQ(OOJSGetTimeLimiterLimit(), 0.0);
	StartLimiter(0.0);	// the default limit
	const double defaultLimit = OOJSGetTimeLimiterLimit();
	OO_CHECK(defaultLimit == 0.2 || defaultLimit == 1.0);	// debug-limiter builds keep a short leash
	StartLimiter(5.0);	// nested: the outermost limit stays
	OO_CHECK_EQ(OOJSGetTimeLimiterLimit(), defaultLimit);
	StopLimiter();
	OO_CHECK_EQ(OOJSGetTimeLimiterLimit(), defaultLimit);
	StopLimiter();
	OO_CHECK_EQ(OOJSGetTimeLimiterLimit(), 0.0);

	// A stop too many is logged and ignored: the next start is outermost again.
	StopLimiter();
	StartLimiter(3.0);
	OO_CHECK_EQ(OOJSGetTimeLimiterLimit(), 3.0);
	OOJSSetTimeLimiterLimit(4.5);
	OO_CHECK_EQ(OOJSGetTimeLimiterLimit(), 4.5);
	StopLimiter();
	OO_CHECK_EQ(OOJSGetTimeLimiterLimit(), 0.0);
}


OO_TEST(pauseAndResume)
{
	StartLimiter(10.0);
	OOJSPauseTimeLimiter();
	OOJSPauseTimeLimiter();	// nested: only the outermost pause counts
	SleepMs(60);
	OOJSResumeTimeLimiter();
	OO_CHECK_EQ(OOJSGetTimeLimiterLimit(), 10.0);
	OOJSResumeTimeLimiter();
	const double extended = OOJSGetTimeLimiterLimit();
	OO_CHECK(extended > 10.04 && extended < 11.0);	// the paused time is added to the limit
	StopLimiter();
}


#if OOJS_PROFILE
OO_TEST(profiling)
{
	{
		OO_CHECK(!OOJSIsProfiling());
		OOJSBeginProfiling(false);
		OO_CHECK(OOJSIsProfiling());

		OOJSProfileStackFrame outer, inner, again, nameless;
		OOJSProfileEnter(&outer, "outer");
		SleepMs(20);
		OOJSProfileEnter(&inner, "inner");
		SleepMs(20);
		OOJSProfileExit(&inner);
		OOJSProfileExit(&outer);
		OOJSProfileEnter(&again, "inner");
		OOJSProfileExit(&again);
		OOJSProfileEnter(&nameless, NULL);
		OOJSProfileExit(&nameless);

		oo::Ref<OOTimeProfile> profileRef = OOJSEndProfiling();
		OOTimeProfile *profile = profileRef.get();
		OO_CHECK(!OOJSIsProfiling());
		OO_CHECK(profile != nullptr);
		OO_CHECK_EQ(profile->profileEntries().size(), 3u);

		OOTimeProfileEntry *outerEntry = EntryNamed(profile, "outer");
		OOTimeProfileEntry *innerEntry = EntryNamed(profile, "inner");
		OO_CHECK(outerEntry != nullptr && innerEntry != nullptr);
		OO_CHECK_EQ(outerEntry->hitCount(), 1u);
		OO_CHECK_EQ(innerEntry->hitCount(), 2u);
		OO_CHECK(!innerEntry->isJavaScriptFrame());
		OO_CHECK(outerEntry->totalTimeSum() >= innerEntry->totalTimeSum());	// outer contains inner's first call
		OO_CHECK(outerEntry->totalTimeSum() >= outerEntry->selfTimeSum());
		OO_CHECK_EQ(innerEntry->totalTimeAverage(), innerEntry->totalTimeSum() / 2);
		OO_CHECK_EQ(innerEntry->selfTimeMax(), innerEntry->totalTimeMax());	// nothing below it
		OO_CHECK(profile->totalTime() >= outerEntry->totalTimeSum());
		OO_CHECK_EQ(profile->nonExtensionTime(), profile->totalTime() - profile->extensionTime());
		OO_CHECK_EQ(profile->javaScriptTime(), profile->totalTime() - profile->nativeTime());
		OO_CHECK(profile->nativeTime() >= outerEntry->selfTimeSum() + innerEntry->selfTimeSum());

		// Comparisons: "reverse" is longest first.
		OO_CHECK_EQ(outerEntry->compareBySelfTime(outerEntry), OOOrderedSame);
		OO_CHECK_EQ(outerEntry->compareByTotalTime(innerEntry), -outerEntry->compareByTotalTimeReverse(innerEntry));
		OO_CHECK_EQ(innerEntry->compareBySelfTime(outerEntry), -innerEntry->compareBySelfTimeReverse(outerEntry));
		if (outerEntry->totalTimeSum() > innerEntry->totalTimeSum())  OO_CHECK_EQ(outerEntry->compareByTotalTimeReverse(innerEntry), OOOrderedAscending);

		// The descriptions.
		const std::string profileText = profile->description().value_or("");
		OO_CHECK(profileText.find("Total time: ") != std::string::npos);
		OO_CHECK(profileText.find("NAME  T  COUNT    TOTAL     SELF  TOTAL%   SELF%  SELFMAX") != std::string::npos);
		OO_CHECK(profileText.find("inner  N      2 ") != std::string::npos);
		OO_CHECK(profileText.find("outer  N      1 ") != std::string::npos);
		OO_CHECK(profileText.find("(null)  N      1 ") != std::string::npos);
		const std::string innerText = innerEntry->description().value_or("");
		OO_CHECK(innerText.find("inner: 2 times, total ") != std::string::npos);
		const std::string outerText = outerEntry->description().value_or("");
		OO_CHECK(outerText.find("outer: 1 time, ") != std::string::npos);
		OO_CHECK(outerText.find("(self ") != std::string::npos);

		// The property lists, as JS gets them.
		sConverted.clear();
		innerEntry->oo_jsValueInContext(NULL);
		OO_CHECK_EQ(sConverted.size(), 1u);
		if (sConverted.size() == 1)
		{
			const oo::PList &plist = sConverted[0];
			OO_CHECK(plist.isDict() && plist.count() == 9);
			OO_CHECK(Key(plist, "name") != nullptr && *Key(plist, "name")->getIf<std::string>() == "inner");
			OO_CHECK(Key(plist, "hitCount") != nullptr && Key(plist, "hitCount")->doubleValue() == 2);
			OO_CHECK(Key(plist, "isJavaScriptFrame") != nullptr && Key(plist, "isJavaScriptFrame")->type() == oo::PList::Type::Bool && !Key(plist, "isJavaScriptFrame")->boolValue());
		}
		sConverted.clear();
		EntryNamed(profile, "<none>")->oo_jsValueInContext(NULL);
		OO_CHECK(sConverted.size() == 1 && sConverted[0].isDict() && sConverted[0].count() == 0);	// a nameless entry

		sConverted.clear();
		profile->oo_jsValueInContext(NULL);
		OO_CHECK_EQ(sConverted.size(), 1u);
		if (sConverted.size() == 1)
		{
			const oo::PList &plist = sConverted[0];
			OO_CHECK(plist.isDict() && plist.count() == 7);
			for (const char *key : { "totalTime", "javaScriptTime", "nativeTime", "extensionTime", "nonExtensionTime", "profilerOverhead" })  OO_CHECK(Key(plist, key) != nullptr && Key(plist, key)->type() == oo::PList::Type::Real);
			const oo::PList *profiles = Key(plist, "profiles");
			OO_CHECK(profiles != nullptr && profiles->isArray() && profiles->count() == 3);
			if (profiles != nullptr && profiles->isArray())
			{
				for (const oo::PList &entry : *profiles->getIf<oo::PList::Array>())  OO_CHECK(entry.isDict() && (entry.count() == 9 || entry.count() == 0));
			}
		}

	}
}
#endif


OO_TEST(watchdog)
{
	// The watchdog stops a script that runs past its limit.
	ooscript::Runtime runtime = ooscript::newRuntime(8u * 1024u * 1024u);
	OOJSTimeManagementInit(oo::makeRef<OOJavaScriptEngine>(runtime).get(), runtime);	// the watchdog keeps its own reference
	ooscript::Context context = ooscript::newContext(runtime, 8192);	// the context callback sets the operation callback
	ooscript::beginRequest(context);
	ooscript::Object global = ooscript::getGlobalObject(context);
	ooscript::initStandardClasses(context, global);
	oo::log::logger().setSink([](std::string_view line) { sLogLines.emplace_back(line); });
	oo::log::logger().setInitialized(true);

	StartLimiter(0.05);
	OOJSResetTimeLimiter();
	sStackDumps = 0;
	const char *endless = "for (;;) {}";
	ooscript::Value result = ooscript::undefinedValue();
	const auto start = std::chrono::steady_clock::now();
	const bool completed = ooscript::evaluateScript(context, global, endless, static_cast<unsigned>(std::strlen(endless)), "endless.js", 1, &result);
	const double seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
	ooscript::clearPendingException(context);
	StopLimiter();
	OOJSResetTimeLimiter();
	oo::log::logger().setSink(nullptr);

	OO_CHECK(!completed);
	OO_CHECK(seconds < 10.0);
	bool logged = false;
	for (const std::string &line : sLogLines)  if (line.find("Script \"test script\" ran for ") != std::string::npos && line.find(" seconds and has been terminated.") != std::string::npos)  logged = true;
	OO_CHECK(logged);
#ifndef NDEBUG
	OO_CHECK_EQ(sStackDumps, 1);
#endif

	// After a reset, scripts run again.
	const char *quick = "1 + 1";
	StartLimiter(0.0);
	OO_CHECK(ooscript::evaluateScript(context, global, quick, static_cast<unsigned>(std::strlen(quick)), "quick.js", 1, &result));
	StopLimiter();
	ooscript::endRequest(context);
}


OO_TEST_MAIN()
