/*	test_OOJSEngineTimeManagement.mm
	Unit tests for the script profiler (src/Core/Scripting/OOJSEngineTimeManagement.h/.mm).

	The file holds the debug-build profiler, whose results are OOTimeProfile and OOTimeProfileEntry
	objects. (The time limiter is the engine's, in OOJavaScriptEngine.mm, as #768 has it, on
	QuickJS-ng's interrupt handler; its cases are in test_OOJSTimeLimiter.mm.) The test links the
	game's own objects for the file and the stopwatch (OOProfilingStopwatch.mm). What the rest of
	the engine would provide is defined below as the smallest stand-in that does the same thing:
	the time limiter the profiler reads, pauses and extends, and the property-list converter
	(recording what it is given). The tests pin the profiler's entries (names, hit counts, the frame kind), the
	profile's and entries' descriptions and property lists and the comparisons.
	Run: tests/run.sh unit
*/

#include "OOJSEngineTimeManagement.h"
#include "OODescription.h"
#include "oofnd/PList.hpp"

#include "oo_test.hpp"

#include <chrono>
#include <string>
#include <thread>
#include <vector>


// MARK: What the rest of the engine provides ------------------------------------------------------

namespace {
std::vector<oo::PList> sConverted;		// what OOJSValueFromPList was given
} // namespace


JSValue OOJSValueFromPList(JSContext *context, const oo::PList &plist)
{
	sConverted.push_back(plist);
	return JS_NewInt32(context, static_cast<std::int32_t>(sConverted.size()));
}


#if OOJS_PROFILE
// The engine's time limiter, which the profiler reads, pauses and extends: a limiter that is never
// started.
OOTimeDelta OOJSGetTimeLimiterLimit(void)  { return 0.0; }
void OOJSPauseTimeLimiter(void)  {}
void OOJSResumeTimeLimiter(void)  {}
void OOJSExcludeTimeFromLimiter(OOTimeDelta)  {}
#endif


// MARK: Helpers -----------------------------------------------------------------------------------

#if OOJS_PROFILE
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
#endif


// MARK: Tests -------------------------------------------------------------------------------------

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

		std::shared_ptr<OOTimeProfile> profileRef = OOJSEndProfiling();
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
		OO_CHECK_EQ(outerEntry->compareBySelfTime(outerEntry), OOComparisonResult::kSame);
		OO_CHECK_EQ(oo::ToUnderlying(outerEntry->compareByTotalTime(innerEntry)), -oo::ToUnderlying(outerEntry->compareByTotalTimeReverse(innerEntry)));
		OO_CHECK_EQ(oo::ToUnderlying(innerEntry->compareBySelfTime(outerEntry)), -oo::ToUnderlying(innerEntry->compareBySelfTimeReverse(outerEntry)));
		if (outerEntry->totalTimeSum() > innerEntry->totalTimeSum())  OO_CHECK_EQ(outerEntry->compareByTotalTimeReverse(innerEntry), OOComparisonResult::kAscending);

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
				// Each entry's own property list, as #768 builds "profiles".
				for (const oo::PList &entry : *profiles->getIf<oo::PList::Array>())  OO_CHECK(entry.isDict() && (entry.count() == 9 || entry.count() == 0));
			}
		}
	}
}
#endif


OO_TEST_MAIN()
