/*

OOJSEngineTimeManagement.h

Functionality related to time limiting and profiling of JavaScript code.

C++20 since bead oo-cn4o (proposed ADR-0056; amendment oo-ppc for the scripting files): the
profile classes are OOTimeProfile and OOTimeProfileEntry (no Objective-C facades since bead
oo-9ht.63). The watchdog is a function of this file; it was a category of the engine
that nothing else sent.


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


#pragma once

#include "OOJavaScriptEngine.h"
#include "oofnd/StdLib.hpp"
#include "oofnd/Ref.hpp"

#include <optional>
#include <string>
#include <vector>


/*	Time Limiter
	
	The time limiter stops scripts from running an arbitrarily long time.
	
	The time limiter must be started before calling into JavaScript code.
	Calls to OOJSStartTimeLimiter() and OOJSStopTimeLimiter() must be balanced,
	and may be nested.
	OOJSStartTimeLimiterWithTimeLimit() is like OOJSStartTimeLimiter(), but
	specifies a custom time limit. This limit is only used if the limiter is
	actually stopped.
	
	The time limiter can be paused and resumed for native operations that are
	known to be slow. OOJSPauseTimeLimiter() and OOJSResumeTimeLimiter() must
	be balanced and can be nested, but the nest count may be negative - it is
	valid to call OOJSResumeTimeLimiter() followed by OOJSPauseTimeLimiter().
*/
#define OOJSStartTimeLimiter()  OOJSStartTimeLimiterWithTimeLimit(0.0)

#ifndef NDEBUG
#define OOJSStartTimeLimiterWithTimeLimit(limit)  OOJSStartTimeLimiterWithTimeLimit_(limit, OOLOG_FILE_NAME, __LINE__)
#define OOJSStopTimeLimiter()  OOJSStopTimeLimiter_(OOLOG_FILE_NAME, __LINE__)

#ifdef __cplusplus
extern "C" {
#endif

void OOJSStartTimeLimiterWithTimeLimit_(OOTimeDelta limit, const char *file, unsigned line);
void OOJSStopTimeLimiter_(const char *file, unsigned line);

#ifdef __cplusplus
}
#endif

#else
void OOJSStartTimeLimiterWithTimeLimit(OOTimeDelta limit);
void OOJSStopTimeLimiter(void);
#endif


#define kOOJSLongTimeLimit (5.0)


#if OOJS_PROFILE
#include "OOProfilingStopwatch.h"

/*
	Profiling support.
	
	OOJSBeginProfiling(trace), OOJSEndProfiling(), OOJSIsProfiling()
	Start, stop, and query profiling mode. It is a hard error to start
	profiling while already profiling.
	
	If trace is set, all profileable functions will be logged. The actual
	profile will be of little use in this case because of logging overhead.
	
	OOJSCopyTimeLimiterNominalStartTime()
	Copy the nominal start time for the time limiter. This is the actual time
	with any time extensions (paused periods) added in.
	
	OOJSResetTimeLimiter()
	Set the time limiter start time to now.
	
	OOJSGetTimeLimiterLimit()
	OOJSSetTimeLimiterLimit()
	Manipulate the timeout.
*/


class OOTimeProfile;


oo::Ref<OOTimeProfile> OOJSEndProfiling(void);

#ifdef __cplusplus
extern "C" {
#endif

void OOJSBeginProfiling(bool trace);
bool OOJSIsProfiling(void);

OOHighResTimeValue OOJSCopyTimeLimiterNominalStartTime(void);

void OOJSResetTimeLimiter(void);
OOTimeDelta OOJSGetTimeLimiterLimit(void);
void OOJSSetTimeLimiterLimit(OOTimeDelta limit);

#ifdef __cplusplus
}
#endif


/*
	NOTE: the profiler declarations that need to be visible to functions that
	are profiled are found in OOJSEngineNativeWrappers.h.
*/


class OOTimeProfileEntry;


class OOTimeProfile : public oo::RefCounted
{
public:
	std::optional<std::string> description();

	double totalTime();
	double javaScriptTime();
	double nativeTime();
	double extensionTime();
	double nonExtensionTime();
	double profilerOverhead();

	std::vector<oo::Ref<OOTimeProfileEntry>> profileEntries();	// sorted by self time, longest first

	ooscript::Value oo_jsValueInContext(ooscript::Context context);

	// Set by OOJSEndProfiling() (the old private category).
	void setTotalTime(double value);
	void setNativeTime(double value);
#ifdef MOZ_TRACE_JSCALLS
	void setJavaScriptTime(double value);
#endif
	void setProfilerOverhead(double value);
	void setExtensionTime(double value);
	void setProfileEntries(const std::vector<oo::Ref<OOTimeProfileEntry>> &value);

private:
	oo::PList propertyListRepresentation();

	double						_totalTime = {};
	double						_nativeTime = {};
	double						_extensionTime = {};
#ifdef MOZ_TRACE_JSCALLS
	double						_javaScriptTime = {};
#endif

	double						_profilerOverhead = {};

	std::vector<oo::Ref<OOTimeProfileEntry>>	_profileEntries;
};


class OOTimeProfileEntry : public oo::RefCounted
{
public:
	// The profiler's (the old private category): only while profiling.
	explicit OOTimeProfileEntry(const char *name);
#ifdef MOZ_TRACE_JSCALLS
	OOTimeProfileEntry(ooscript::Function function, ooscript::Context context);
#endif

	void addSampleWithTotalTime(OOTimeDelta totalTime, OOTimeDelta selfTime);

	std::optional<std::string> description();

	std::optional<std::string> function();	// nullopt: none (bead oo-3rb.291.3)
	NSUInteger hitCount();
	double totalTimeSum();
	double selfTimeSum();
	double totalTimeAverage();
	double selfTimeAverage();
	double totalTimeMax();
	double selfTimeMax();
	bool isJavaScriptFrame();

	OOComparisonResult compareByTotalTime(OOTimeProfileEntry *other);
	OOComparisonResult compareByTotalTimeReverse(OOTimeProfileEntry *other);
	OOComparisonResult compareBySelfTime(OOTimeProfileEntry *other);
	OOComparisonResult compareBySelfTimeReverse(OOTimeProfileEntry *other);

	ooscript::Value oo_jsValueInContext(ooscript::Context context);
	oo::PList propertyListRepresentation();

private:
	std::optional<std::string>	_function;	// nullopt when created without a name
	unsigned long				_hitCount = {};
	double						_totalTimeSum = {};
	double						_selfTimeSum = {};
	double						_totalTimeMax = {};
	double						_selfTimeMax = {};
#ifdef MOZ_TRACE_JSCALLS
	ooscript::Function _jsFunction = {};
#endif
};

#endif


class OOJavaScriptEngine;

#ifdef __cplusplus
extern "C" {
#endif

void OOJSTimeManagementInit(OOJavaScriptEngine *engine, ooscript::Runtime runtime);

#ifdef __cplusplus
}
#endif

