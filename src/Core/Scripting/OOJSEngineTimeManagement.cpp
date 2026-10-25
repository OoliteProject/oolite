/*

OOJSEngineTimeManagement.h


Copyright (C) 2010-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#include "OOJSEngineTimeManagement.h"
#include "OOJavaScriptEngine.h"
#include "OOProfilingStopwatch.h"
#include "OOJSScript.h"
#include "OOLoggingExtended.h"
#include "oofnd/Log.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/Thread.hpp"
#include "oofnd/objc/OOAssert.h"

#if OOLITE_LINUX
// Workaround for clang/glibc incompatibility.
#ifdef __block
#undef __block
#endif
#define __block __glibc_block
#endif
#include <unistd.h>
#include "OOObjCPList.h"
#include "oofnd/String.hpp"

#if OOLITE_LINUX
#undef __block
#endif


#if OO_DEBUG
#define OOJS_DEBUG_LIMITER	1
#else
#define OOJS_DEBUG_LIMITER	0
#endif


static unsigned sLimiterStartDepth;
static int sLimiterPauseDepth;
static OOHighResTimeValue sLimiterStart;
static OOHighResTimeValue sLimiterPauseStart;
static double sLimiterTimeLimit;


#if OOJS_DEBUG_LIMITER
#define OOJS_TIME_LIMIT		(0.2)	// seconds
#else
#define OOJS_TIME_LIMIT		(1)	// seconds
#endif

namespace {
static bool sStop;
} // namespace

#ifndef NDEBUG
static const char *sLastStartedFile;
static unsigned sLastStartedLine;
static const char *sLastStoppedFile;
static unsigned sLastStoppedLine;
#endif


#if OOJS_PROFILE && defined(MOZ_TRACE_JSCALLS)
static void FunctionCallback(ooscript::Function function, ooscript::Script script, ooscript::Context context, int entering);
#endif


#ifndef NDEBUG
void OOJSStartTimeLimiterWithTimeLimit_(OOTimeDelta limit, const char *file, unsigned line)
#else
void OOJSStartTimeLimiterWithTimeLimit(OOTimeDelta limit)
#endif
{
#if OOJS_DEBUG_LIMITER
	OO_LOG("script.javaScript.timeLimit.debug", "Limiter starting: {} => {}", sLimiterStartDepth, sLimiterStartDepth+1);
#endif
	if (sLimiterStartDepth++ == 0)
	{
		if (limit <= 0.0)  limit = OOJS_TIME_LIMIT;
		sLimiterTimeLimit = limit;
		sLimiterPauseDepth = 0;
		
		OODisposeHighResTime(sLimiterStart);
		sLimiterStart = OOGetHighResTime();
	}
	
#ifndef NDEBUG
	sLastStartedFile = file;
	sLastStartedLine = line;
#endif
}


#ifndef NDEBUG
void OOJSStopTimeLimiter_(const char *file, unsigned line)
#else
void OOJSStopTimeLimiter(void)
#endif
{
#ifndef NDEBUG
	if (sLimiterStartDepth == 0)
	{
		OO_LOG("bug.javaScript.limiterDepth", "Attempt to stop JavaScript time limiter while it is already fully stopped. This is an internal bug, please report it. (Last start: {}:{}, last valid stop: {}:{}, this stop attempt: {}:{}.)", oo::log::abbreviatedFileName(sLastStartedFile), sLastStartedLine, oo::log::abbreviatedFileName(sLastStoppedFile), sLastStoppedLine, oo::log::abbreviatedFileName(file), line);
		return;
	}
	
	sLastStoppedFile = file;
	sLastStoppedLine = line;

#if OOJS_DEBUG_LIMITER
	OO_LOG("script.javaScript.timeLimit.debug", "Limiter ending: {} <= {}", sLimiterStartDepth-1, sLimiterStartDepth);
#endif

#endif
	
	if (--sLimiterStartDepth == 0)  sLimiterTimeLimit = 0.0;
}


void OOJSPauseTimeLimiter(void)
{
	if (sLimiterPauseDepth++ == 0)
	{
		OODisposeHighResTime(sLimiterPauseStart);
		sLimiterPauseStart = OOGetHighResTime();
	}
}


void OOJSResumeTimeLimiter(void)
{
	if (--sLimiterPauseDepth == 0)
		
	{
		OOHighResTimeValue now = OOGetHighResTime();
		OOTimeDelta elapsed = OOHighResTimeDeltaInSeconds(sLimiterPauseStart, now);
		OODisposeHighResTime(now);
		
		sLimiterTimeLimit += elapsed;
	}
}


#ifndef NDEBUG
OOHighResTimeValue OOJSCopyTimeLimiterNominalStartTime(void)
{
	return sLimiterStart;
}


void OOJSResetTimeLimiter(void)
{
	OODisposeHighResTime(sLimiterStart);
	sLimiterStart = OOGetHighResTime();
	
	sStop = false;
}


OOTimeDelta OOJSGetTimeLimiterLimit(void)
{
	return sLimiterTimeLimit;
}


void OOJSSetTimeLimiterLimit(OOTimeDelta limit)
{
	sLimiterTimeLimit = limit;
}
#endif


/*	The watchdog, which was a category of the engine that only OOJSTimeManagementInit() sent. It
	reads the runtime the engine made (its _runtime, set once in -init) from its argument.
*/
namespace {
void WatchdogTimerThread(ooscript::Runtime runtime)
{
	for (;;)
	{
#if OOLITE_WINDOWS
		Sleep(OOJS_TIME_LIMIT * 1000);
#else
		usleep(OOJS_TIME_LIMIT * 1000000);
#endif
		
		if (EXPECT(sLimiterStartDepth == 0 || sLimiterPauseDepth > 0))  continue;	// Most of the time, a script isn't running.
		
		// Note: if you add logging here, you need a manual autorelease pool.
		
		OOHighResTimeValue now = OOGetHighResTime();
		OOTimeDelta elapsed = OOHighResTimeDeltaInSeconds(sLimiterStart, now);
		OODisposeHighResTime(now);
		
		if (EXPECT_NOT(elapsed > sLimiterTimeLimit))
		{
			sStop = true;
			ooscript::triggerAllOperationCallbacks(runtime);
		}
	}
}
} // namespace


static bool OperationCallback(ooscript::Context context)
{
	if (!sStop)  return true;
	
    ooscript::clearPendingException(context);
	
	OOHighResTimeValue now = OOGetHighResTime();
	OOTimeDelta elapsed = OOHighResTimeDeltaInSeconds(sLimiterStart, now);
	OODisposeHighResTime(now);
	
	if (elapsed <= sLimiterTimeLimit)  return true;
	
	OOJSScript *runningScript = OOJSScript::currentlyRunningScript();
	OO_LOG_ERR("script.javaScript.timeLimit", "Script \"{}\" ran for {:g} seconds and has been terminated.", ((runningScript != nullptr) ? runningScript->name() : std::nullopt).value_or("(null)"), elapsed);
#ifndef NDEBUG
	OOJSDumpStack(context);
#endif
	
	// FIXME: we really should put something in the JS log here, but since that's implemented in JS there are complications.
	
	return false;
}


static bool ContextCallback(ooscript::Context context, ooscript::ContextOp contextOp)
{
	if (contextOp == ooscript::ContextOp::New)
	{
		ooscript::setOperationCallback(context, OperationCallback);
		
#if OOJS_PROFILE && defined(MOZ_TRACE_JSCALLS)
		ooscript::setFunctionCallback(context, FunctionCallback);
#endif
	}
	return true;
}


void OOJSTimeManagementInit(OOJavaScriptEngine *engine, ooscript::Runtime runtime)
{
	// The watchdog holds the engine for its (endless) life, as a detached selector thread did.
	if (engine != nullptr)  engine->retain();
	oo::thread::detach([engine, runtime]()
	{
		{
			oo::AutoreleaseScope pool;	// was @autoreleasepool (oo-31u.8)
			WatchdogTimerThread(runtime);
		}
		if (engine != nullptr)  engine->release();
	});
	
	ooscript::setContextCallback(runtime, ContextCallback);
}


#if OOJS_PROFILE
	
// Profiling is enabled, but MOZ_TRACE_JSCALLS is disabled, so only native functions are profiled.
// MOZ_TRACE_JSCALLS was a SpiderMonkey build option; the QuickJS-ng engine has no such hook, so it
// is never defined and this is how every profiling build profiles. It was a #warning, printed by
// every such build with nothing to act on (bead oo-99txa).

namespace {
static bool						sProfiling = false;
static bool						sTracing = false;
} // namespace
static OOJSProfileStackFrame	*sProfileStack = NULL;
// Profile key (native name or JS function, by pointer) -> entry, retained. Was a map table with
// non-owned pointer keys and retained object values (bead oo-3rb.20).
namespace {
static std::unordered_map<const void *, oo::Ref<OOTimeProfileEntry>>	*sProfileInfo;

static OOTimeProfileEntry *ProfileEntryForKey(const void *key)
{
	auto found = sProfileInfo->find(key);
	return (found != sProfileInfo->end()) ? found->second.get() : nullptr;
}
} // namespace
static double					sProfilerOverhead;
static double					sProfilerTotalNativeTime;
static double					sProfilerTotalJavaScriptTime;
static double					sProfilerEntryTimeLimit;
static OOHighResTimeValue		sProfilerStartTime;


void OOJSBeginProfiling(bool trace)
{
	assert(sProfiling == false);
	sProfiling = true;
	sTracing = trace;
	sProfileInfo = new std::unordered_map<const void *, oo::Ref<OOTimeProfileEntry>>;
	sProfileInfo->reserve(100);
	sProfilerOverhead = 0.0;
	sProfilerTotalNativeTime = 0.0;
	sProfilerTotalJavaScriptTime = 0.0;
	sProfilerEntryTimeLimit = OOJSGetTimeLimiterLimit();
	
	// This should be last for precision.
	sProfilerStartTime = OOGetHighResTime();
	
	if (trace)
	{
		OO_LOG("script.javaScript.trace", "{}", ">>>> Beginning trace.");
		oo::log::indent();
	}
}


oo::Ref<OOTimeProfile> OOJSEndProfiling(void)
{
	// This should be at the top for precision.
	OOHighResTimeValue now = OOGetHighResTime();
	// Time limiter should be as close to outermost as practical.
	OOJSPauseTimeLimiter();
	
	assert(sProfiling && sProfileStack == NULL);
	
	sProfiling = false;

	oo::Ref<OOTimeProfile> result = oo::makeRef<OOTimeProfile>();
	
	result->setTotalTime(OOHighResTimeDeltaInSeconds(sProfilerStartTime, now));
	result->setNativeTime(sProfilerTotalNativeTime);
#ifdef MOZ_TRACE_JSCALLS
	result->setJavaScriptTime(sProfilerTotalJavaScriptTime);
#endif
	result->setProfilerOverhead(sProfilerOverhead);
	
	double currentTimeLimit = OOJSGetTimeLimiterLimit(); 
	result->setExtensionTime(currentTimeLimit - sProfilerEntryTimeLimit);
	
	std::vector<oo::Ref<OOTimeProfileEntry>> entries;
	entries.reserve(sProfileInfo->size());
	for (const auto &keyAndEntry : *sProfileInfo)  entries.emplace_back(keyAndEntry.second);
	std::stable_sort(entries.begin(), entries.end(), [](const auto &a, const auto &b) { return a->compareBySelfTimeReverse(b.get()) == OOOrderedAscending; });
	result->setProfileEntries(entries);
	
	if (sTracing)
	{
		oo::log::outdent();
		OO_LOG("script.javaScript.trace", "{}", "<<<< End of trace.");
		sTracing = false;
	}
	
	// Clean up (the table held the entries' references).
	delete sProfileInfo;
	sProfileInfo = NULL;
	OODisposeHighResTime(sProfilerStartTime);
	
	OODisposeHighResTime(now);
	
	OOJSResumeTimeLimiter();
	return result;
}


bool OOJSIsProfiling(void)
{
	return sProfiling;
}

void OOJSBeginTracing(void);
void OOJSEndTracing(void);
bool OOJSIsTracing(void);


namespace {
static void UpdateProfileForFrame(OOHighResTimeValue now, OOJSProfileStackFrame *frame);
} // namespace


#ifdef MOZ_TRACE_JSCALLS
static void CleanUpJSFrame(OOJSProfileStackFrame *frame)
{
	free(frame);
}


static void TraceEnterJSFunction(ooscript::Context context, ooscript::Function function, OOTimeProfileEntry *profileEntry)
{
	std::string			name = oo::str::format("%s(", profileEntry->function().value_or("(null)").c_str());
	bool				isNative = ooscript::getFunctionNative(context, function) != NULL;
	std::string			frameTag;
	std::string			logMsgClass;
	
	if (!isNative)
	{
		// Get stack frame and find arguments.
		ooscript::StackFrame	frame = NULL;
		bool				first = true;
		ooscript::Value				thisVal;
		ooscript::Object scope;
		ooscript::VariableList	properties = { 0, NULL, NULL };
		unsigned			i;
		
		// Temporarily disable profiling as we'll call out to profiled functions to get value descriptions.
		sProfiling = false;
		
		if (ooscript::frameIterator(context, &frame) != NULL)
		{
			if (ooscript::frameIsConstructor(context, frame))
			{
				name.insert(0, "new ");
			}
			
			if (ooscript::frameThis(context, frame, &thisVal))
			{
				name += oo::str::format("this: %s", (cxx_OOJSDescribeValue(context, thisVal, true)).c_str());
				first = false;
			}
			
			scope = ooscript::frameScopeChain(context, frame);
			if (scope != NULL && ooscript::getScopeVariables(context, scope, &properties))
			{
				for (i = 0; i < properties.length; i++)
				{
					ooscript::Variable *prop = &properties.vars[i];
					if (prop->flags & static_cast<unsigned>(ooscript::VariableFlag::Argument))
					{
						if (!first)  name += ", ";
						else  first = false;
						
						ooscript::Value propName = ooscript::undefinedValue();
						ooscript::idToValue(context, prop->id, &propName);
						name += oo::str::format("%s: %s", (cxx_OOStringFromJSValueEvenIfNull(context, propName)).value_or("(null)").c_str(), (cxx_OOJSDescribeValue(context, prop->value, true)).c_str());
					}
				}
			}
		}
		
		sProfiling = true;
		
		frameTag = "JS";	// JavaScript
		logMsgClass = "script.javaScript.trace.JS";
	}
	else
	{
		frameTag = "NW";	// Native Wrapper
		logMsgClass = "script.javaScript.trace.NW";
	}
	
	name += ")";
	OO_LOG(logMsgClass, ">> {} [{}]", name, frameTag);
	oo::log::indent();
}


static void FunctionCallback(ooscript::Function function, ooscript::Script script, ooscript::Context context, int entering)
{
	if (EXPECT(!sProfiling))  return;
	if (EXPECT_NOT(function == NULL))  return;
	
	// Ignore native functions. Ours get their own entries anyway, SpiderMonkey's are elided.
	if (!sTracing && ooscript::getFunctionNative(context, function) != NULL)  return;
	
	OOHighResTimeValue start = OOGetHighResTime();
	
	{
		if (entering > 0)
		{
			// Create profile entry up front so we can shove the JS function in it.
			OOTimeProfileEntry *entry = ProfileEntryForKey(function);
			if (entry == nullptr)
			{
				const oo::Ref<OOTimeProfileEntry> made = oo::makeRef<OOTimeProfileEntry>(function, context);
				(*sProfileInfo)[function] = made;	// the table's reference
				entry = made.get();
			}
			
			if (EXPECT_NOT(sTracing))
			{
				// We use EXPECT_NOT here because profiles are time-critical and traces are not.
				TraceEnterJSFunction(context, function, entry);
			}
			
			// Make a stack frame on the heap.
			OOJSProfileStackFrame *frame = (OOJSProfileStackFrame *)malloc(sizeof(OOJSProfileStackFrame));
			assert(frame != NULL);
			
			*frame = (OOJSProfileStackFrame)
			{
				.back = sProfileStack,
				.key = function,
				.startTime = start,
				.subTime = 0.0,
				.total = &sProfilerTotalJavaScriptTime,
				.cleanup = CleanUpJSFrame
			};
			
			sProfileStack = frame;
		}
		else
		{
			// Exiting.
			assert(sProfileStack != NULL && sProfileStack->cleanup == CleanUpJSFrame);
			
			UpdateProfileForFrame(start, sProfileStack);
		}
	}
	
	OOHighResTimeValue end = OOGetHighResTime();
	double currentOverhead = OOHighResTimeDeltaInSeconds(start, end);
	sProfilerOverhead += currentOverhead;
	OODisposeHighResTime(start);
	OODisposeHighResTime(end);
}
#endif


void OOJSProfileEnter(OOJSProfileStackFrame *frame, const char *function)
{
	if (EXPECT(!sProfiling))  return;
	if (EXPECT_NOT(sTracing))
	{
		// We use EXPECT_NOT here because profiles are time-critical and traces are not.
		OO_LOG("script.javaScript.trace.ON", ">> {} [ON]", function);
		oo::log::indent();
	}
	
	*frame = (OOJSProfileStackFrame)
	{
		.back = sProfileStack,
		.key = function,
		.function = function,
		.startTime = OOGetHighResTime(),
		.subTime = 0,
		.total = &sProfilerTotalNativeTime,
		.cleanup = NULL
	};
	sProfileStack = frame;
}


void OOJSProfileExit(OOJSProfileStackFrame *frame)
{
	if (EXPECT(!sProfiling))  return;
	
	OOHighResTimeValue	now = OOGetHighResTime();
	{
		bool				done = false;
		
		/*
			It's possible there could be JavaScript frames on top of this frame if
			a JS native returned false. Or possibly not. The semantics of
			the engine's function callback aren't specified in detail.
			-- Ahruman 2011-01-16
		*/
		for (;;)
		{
			assert(sProfileStack != NULL);
			
			done = (sProfileStack == frame);
			UpdateProfileForFrame(now, sProfileStack);
			if (EXPECT(done))  break;
		}
	}
	
	OODisposeHighResTime(frame->startTime);
	
	OOHighResTimeValue end = OOGetHighResTime();
	double currentOverhead = OOHighResTimeDeltaInSeconds(now, end);
	sProfilerOverhead += currentOverhead;
	
	/*	Equivalent of pausing/resuming time limiter, except that it guarantees
		excluded time will match profiler overhead if there are no other
		pauses happening.
	*/
	if (sLimiterPauseDepth == 0)  sLimiterTimeLimit += currentOverhead;
	
	OODisposeHighResTime(now);
	OODisposeHighResTime(end);
}


namespace {
static void UpdateProfileForFrame(OOHighResTimeValue now, OOJSProfileStackFrame *frame)
{
	sProfileStack = frame->back;
	
	OOTimeProfileEntry *entry = ProfileEntryForKey(frame->key);
	if (entry == nullptr)
	{
		const oo::Ref<OOTimeProfileEntry> made = oo::makeRef<OOTimeProfileEntry>(frame->function);
		(*sProfileInfo)[frame->key] = made;	// the table's reference
		entry = made.get();
	}
	
	OOTimeDelta time = OOHighResTimeDeltaInSeconds(frame->startTime, now);
	OOTimeDelta selfTime = time - frame->subTime;
	entry->addSampleWithTotalTime(time, selfTime);
	
	*(frame->total) += selfTime;
	if (sProfileStack != NULL)  sProfileStack->subTime += time;
	
	if (frame->cleanup != NULL)  frame->cleanup(frame);
	
	if (EXPECT_NOT(sTracing))  oo::log::outdent();
}
} // namespace


std::optional<std::string> OOTimeProfile::description()
{
	double totalTime = this->totalTime();
	
	std::string result = oo::str::format(
							  "Total time: %g ms\n"
							   "JavaScript: %g ms, native: %g ms\n"
							   "Counted towards limit: %g ms, excluded: %g ms\n"
							   "Profiler overhead: %g ms",
							   totalTime * 1000.0,
							   javaScriptTime() * 1000.0, nativeTime() * 1000.0,
							   nonExtensionTime() * 1000.0, extensionTime() * 1000.0,
							   profilerOverhead() * 1000.0);
	
	const std::vector<oo::Ref<OOTimeProfileEntry>> &profileEntries = _profileEntries;
	NSUInteger i, count = profileEntries.size();
	if (count != 0)
	{
		result += "\n                                                        NAME  T  COUNT    TOTAL     SELF  TOTAL%   SELF%  SELFMAX";
		for (i = 0; i < count; i++)
		{
		//	[result appendFormat:@"\n    %@", [_profileEntries objectAtIndex:i]];
			
			OOTimeProfileEntry *entry = profileEntries[i].get();
			
			double totalPc = entry->totalTimeSum() * 100.0 / totalTime;
			double selfPc = entry->selfTimeSum() * 100.0 / totalTime;
			
			result += oo::str::format("\n%60s  %c%7lu %8.2f %8.2f   %5.1f   %5.1f %8.2f",
			 entry->function().value_or("(null)").c_str(),
			 entry->isJavaScriptFrame() ? 'J' : 'N',
			 (unsigned long)entry->hitCount(), entry->totalTimeSum() * 1000.0, entry->selfTimeSum() * 1000.0, totalPc, selfPc, entry->selfTimeMax() * 1000.0);
		}
	}
	
	return result;
}


double OOTimeProfile::totalTime()
{
	return _totalTime;
}


void OOTimeProfile::setTotalTime(double value)
{
	_totalTime = value;
}


double OOTimeProfile::javaScriptTime()
{
#ifdef MOZ_TRACE_JSCALLS
	return _javaScriptTime;
#else
	return _totalTime - _nativeTime;
#endif
}


#ifdef MOZ_TRACE_JSCALLS
void OOTimeProfile::setJavaScriptTime(double value)
{
	_javaScriptTime = value;
}
#endif


double OOTimeProfile::nativeTime()
{
	return _nativeTime;
}


void OOTimeProfile::setNativeTime(double value)
{
	_nativeTime = value;
}


double OOTimeProfile::extensionTime()
{
	return _extensionTime;
}


void OOTimeProfile::setExtensionTime(double value)
{
	_extensionTime = value;
}


double OOTimeProfile::nonExtensionTime()
{
	return _totalTime - _extensionTime;
}


double OOTimeProfile::profilerOverhead()
{
	return _profilerOverhead;
}


void OOTimeProfile::setProfilerOverhead(double value)
{
	_profilerOverhead = value;
}


std::vector<oo::Ref<OOTimeProfileEntry>> OOTimeProfile::profileEntries()
{
	return _profileEntries;
}


void OOTimeProfile::setProfileEntries(const std::vector<oo::Ref<OOTimeProfileEntry>> &value)
{
	_profileEntries = value;
}


ooscript::Value OOTimeProfile::oo_jsValueInContext(ooscript::Context context)
{
	return OOJSValueFromPList(context, propertyListRepresentation());
}


oo::PList OOTimeProfile::propertyListRepresentation()
{
	// "profiles" holds each entry's own property list, which is what converting the entry to JavaScript gave.
	oo::PList::Array profiles;
	profiles.reserve(_profileEntries.size());
	for (const auto &entry : _profileEntries)  profiles.push_back(entry->propertyListRepresentation());
	
	oo::PList::Dict result;
	result.emplace("profiles", oo::PList(std::move(profiles)));
	result.emplace("totalTime", oo::PList(totalTime()));
	result.emplace("javaScriptTime", oo::PList(javaScriptTime()));
	result.emplace("nativeTime", oo::PList(nativeTime()));
	result.emplace("extensionTime", oo::PList(extensionTime()));
	result.emplace("nonExtensionTime", oo::PList(nonExtensionTime()));
	result.emplace("profilerOverhead", oo::PList(profilerOverhead()));
	return oo::PList(std::move(result));
}


OOTimeProfileEntry::OOTimeProfileEntry(const char *name)
{
	OOCAssert(sProfiling, "Can't create profile entries while not profiling.");
	
	{
		if (name != NULL)
		{
			_function = std::string(name);
		}
	}
}


#if MOZ_TRACE_JSCALLS
OOTimeProfileEntry::OOTimeProfileEntry(ooscript::Function function, ooscript::Context context)
	: OOTimeProfileEntry(nullptr)
{
	{
		// Temporarily disable profiling so we don't profile the profiler while it's profiling the profilee.
		sProfiling = false;
		_jsFunction = function;
		
		std::string funcName;
		ooscript::String jsName = ooscript::getFunctionId(_jsFunction);
		if (jsName != NULL)  funcName = cxx_OOStringFromJSString(context, jsName).value_or(std::string());
		else  funcName = "<anonymous>";
		
		// If it's a non-native function, get its source location.
		std::optional<std::string> location;
		if (ooscript::getFunctionNative(context, function) == NULL)
		{
			ooscript::StackFrame frame = NULL;
			if (ooscript::frameIterator(context, &frame) != NULL)
			{
				location = OOJSDescribeLocation(context, frame);
			}
		}
		
		if (location.has_value())
		{
			_function = oo::str::format("(%s) %s", location->c_str(), funcName.c_str());
		}
		else  _function = funcName;
		
		sProfiling = true;
	}
}
#endif


void OOTimeProfileEntry::addSampleWithTotalTime(OOTimeDelta totalTime, OOTimeDelta selfTime)
{
	_hitCount++;
	_totalTimeSum += totalTime;
	_selfTimeSum += selfTime;
	_totalTimeMax = fmax(_totalTimeMax, totalTime);
	_selfTimeMax = fmax(_selfTimeMax, selfTime);
}


std::optional<std::string> OOTimeProfileEntry::description()
{
	const char *function = _function.has_value() ? _function->c_str() : "(null)";	// as %@ printed nil
	if (_hitCount == 0)  return oo::str::format("%s: --", function);
	
	// Convert everything to milliseconds.
	float totalTimeSum = _totalTimeSum * 1000.0;
	float selfTimeSum = _selfTimeSum * 1000.0;
	float totalTimeMax = _totalTimeMax * 1000.0;
	float selfTimeMax = _selfTimeMax * 1000.0;
	
	if (totalTimeSum == selfTimeSum && totalTimeMax == selfTimeMax)
	{
		if (_hitCount == 1)
		{
			return oo::str::format("%s: 1 time, %g ms", function, totalTimeSum);
		}
		else
		{
			return oo::str::format("%s: %lu times, total %g ms, avg %g ms, max %g ms", function, _hitCount, totalTimeSum, totalTimeSum / _hitCount, totalTimeMax);
		}
	}
	else
	{
		if (_hitCount == 1)
		{
			return oo::str::format("%s: 1 time, %g ms (self %g ms)", function, totalTimeSum, selfTimeSum);
		}
		else
		{
			return oo::str::format("%s: %lu times, total %g ms (self %g ms), avg %g ms (self %g ms), max %g ms, max self %g ms", function, _hitCount, totalTimeSum, selfTimeSum, totalTimeSum / _hitCount, selfTimeSum / _hitCount, totalTimeMax, selfTimeMax);
		}
	}
}


std::optional<std::string> OOTimeProfileEntry::function()
{
	return _function;
}


NSUInteger OOTimeProfileEntry::hitCount()
{
	return _hitCount;
}


double OOTimeProfileEntry::totalTimeSum()
{
	return _totalTimeSum;
}


double OOTimeProfileEntry::selfTimeSum()
{
	return _selfTimeSum;
}


double OOTimeProfileEntry::totalTimeAverage()
{
	return _hitCount ? (_totalTimeSum / _hitCount) : 0.0;
}


double OOTimeProfileEntry::selfTimeAverage()
{
	return _hitCount ? (_selfTimeSum / _hitCount) : 0.0;
}


double OOTimeProfileEntry::totalTimeMax()
{
	return _totalTimeMax;
}


double OOTimeProfileEntry::selfTimeMax()
{
	return _selfTimeMax;
}


bool OOTimeProfileEntry::isJavaScriptFrame()
{
#if MOZ_TRACE_JSCALLS
	return _jsFunction != NULL;
#else
	return false;
#endif
}


OOComparisonResult OOTimeProfileEntry::compareByTotalTime(OOTimeProfileEntry *other)
{
	return (OOComparisonResult)-compareByTotalTimeReverse(other);
}


OOComparisonResult OOTimeProfileEntry::compareByTotalTimeReverse(OOTimeProfileEntry *other)
{
	double selfTotal = totalTimeSum();
	double otherTotal = (other != nullptr) ? other->totalTimeSum() : 0.0;	// (a message to nil gave 0)
	
	if (selfTotal < otherTotal)  return OOOrderedDescending;
	if (selfTotal > otherTotal)  return OOOrderedAscending;
	return OOOrderedSame;
}


OOComparisonResult OOTimeProfileEntry::compareBySelfTime(OOTimeProfileEntry *other)
{
	return (OOComparisonResult)-compareBySelfTimeReverse(other);
}


OOComparisonResult OOTimeProfileEntry::compareBySelfTimeReverse(OOTimeProfileEntry *other)
{
	double selfTotal = selfTimeSum();
	double otherTotal = (other != nullptr) ? other->selfTimeSum() : 0.0;	// (a message to nil gave 0)
	
	if (selfTotal < otherTotal)  return OOOrderedDescending;
	if (selfTotal > otherTotal)  return OOOrderedAscending;
	return OOOrderedSame;
}


ooscript::Value OOTimeProfileEntry::oo_jsValueInContext(ooscript::Context context)
{
	return OOJSValueFromPList(context, propertyListRepresentation());
}


oo::PList OOTimeProfileEntry::propertyListRepresentation()
{
	oo::PList::Dict result;
	// A nameless entry gave an empty dictionary: its nil name ended the object/key list.
	if (_function.has_value())
	{
		result.emplace("name", oo::PList(*_function));
		result.emplace("hitCount", oo::PList::unsignedInteger(hitCount()));
		result.emplace("totalTimeSum", oo::PList(totalTimeSum()));
		result.emplace("selfTimeSum", oo::PList(selfTimeSum()));
		result.emplace("totalTimeAverage", oo::PList(totalTimeAverage()));
		result.emplace("selfTimeAverage", oo::PList(selfTimeAverage()));
		result.emplace("totalTimeMax", oo::PList(totalTimeMax()));
		result.emplace("selfTimeMax", oo::PList(selfTimeMax()));
		result.emplace("isJavaScriptFrame", oo::PList(static_cast<bool>(isJavaScriptFrame())));
	}
	return oo::PList(std::move(result));
}

#endif
