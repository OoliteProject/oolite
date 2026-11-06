/*

OOJSEngineNativeWrappers.h (QuickJS-ng)

Exception safety and profiling macros.

Every JavaScript native callback that could concievably throw
should begin with OOJS_NATIVE_ENTER() and end with
OOJS_NATIVE_EXIT. Callbacks which have been carefully audited for potential
exceptions, and support functions called from JavaScript native callbacks,
may start with OOJS_PROFILE_ENTER and end with OOJS_PROFILE_EXIT to be
included in profiling reports.

Functions using either of these pairs _must_ return before
OOJS_NATIVE_EXIT/OOJS_PROFILE_EXIT, or they will crash.

For functions with a non-scalar return type, OOJS_PROFILE_EXIT should be
replaced with OOJS_PROFILE_EXIT_VAL(returnValue). The returnValue is never
used (and should be a constant expression), but is required to placate the
compiler.

For values with void return, use OOJS_PROFILE_EXIT_VOID. It is not
necessary to insert a return statement before OOJS_PROFILE_EXIT_VOID.


JavaScript support for Oolite
Copyright (C) 2007-2013 David Taylor and Jens Ayton.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#pragma once

/*	Plain includes: this header is reached from C++ binding translation units
        through OOJSEngineCore.h. OOFoundation.h gave it OOLITE_DEBUG and the
        function attributes.
*/
#include <quickjs.h>

#include "OOFunctionAttributes.h"

#ifndef OOLITE_DEBUG
// As OOFoundation.h defines it (an identical redefinition there is harmless).
#ifdef NDEBUG
#define OOLITE_DEBUG 0
#else
#define OOLITE_DEBUG 1
#endif
#endif

/*	Profiling of native functions (the debug console's profile(), getProfile()
        and trace()), as in SpiderMonkey builds without MOZ_TRACE_JSCALLS: time
        is attributed to natives bracketed by OOJS_NATIVE_ENTER/EXIT or
        OOJS_PROFILE_ENTER/EXIT, and everything else counts as JavaScript time.
*/
#define OOJS_PROFILE (OOLITE_DEBUG && !OOJS_POC_HARNESS)

/*	OOJS_NATIVE_ENTER()/OOJS_NATIVE_EXIT bracket natives that call into
        code which may throw; the exception is converted into a JS
        error. OOJS_PROFILE_ENTER/EXIT bracket natives that cannot throw. When
        OOJS_PROFILE is set, both also record the time spent in the native for
        the profiler.
*/
#if OOJS_PROFILE

#include "OOProfilingStopwatch.h"

/*
        Profiler implementation details. This should be internal to
        OOJSEngineTimeManagement.m, but needs to be declared on the stack by the
        macros below when profiling is enabled.
*/
typedef struct OOJSProfileStackFrame OOJSProfileStackFrame;
struct OOJSProfileStackFrame {
    OOJSProfileStackFrame* back; // Stack link
    const void* key; // Key to look up profile entries: the function name.
    const char* function; // Name of function.
    OOHighResTimeValue startTime; // Time frame was entered.
    OOTimeDelta subTime; // Time spent in subroutine calls.
    OOTimeDelta* total; // Pointer to accumulator for this type of frame.
};

void OOJSProfileEnter(OOJSProfileStackFrame* frame, const char* function);
void OOJSProfileExit(OOJSProfileStackFrame* frame);

/*
        The pairs below are a C++ try, a catch (...) and scope guards, so a
   binding file that uses them contains no exception syntax of its own:
          * OOJS_NATIVE_EXIT catches whatever the body throws and hands it to
            OOJSReportCurrentException() (OOJSEngineNativeWrappers.mm), which
   reports the game's exception (oo::Exception). It also reports a C++
   exception ("Native exception: <what()>").
          * The native then returns
            JS_EXCEPTION.
          * The profiler frame is exited, and the time limiter is resumed, when the scope ends, by return or by exception.
*/

// The scope OOJS_PROFILE_ENTER opens: enters the frame, and exits it however the scope ends.
class OOJSProfileScope {
public:
    explicit OOJSProfileScope(const char* function) { OOJSProfileEnter(&_frame, function); }
    ~OOJSProfileScope() { OOJSProfileExit(&_frame); }
    OOJSProfileScope(const OOJSProfileScope&) = delete;
    OOJSProfileScope& operator=(const OOJSProfileScope&) = delete;

private:
    OOJSProfileStackFrame _frame = { };
};

#define OOJS_PROFILE_ENTER_NAMED(NAME)           \
    {                                            \
        OOJSProfileScope oojsProfileScope(NAME); \
        {

#define OOJS_PROFILE_EXIT \
    }                     \
    }

#define OOJS_NATIVE_ENTER(cx)                            \
    {                                                    \
        JSContext* oojsNativeContext = (cx);             \
        OOJSProfileScope oojsProfileScope(__FUNCTION__); \
        try {

#define OOJS_NATIVE_EXIT                               \
    }                                                  \
    catch (...)                                        \
    {                                                  \
        OOJSReportCurrentException(oojsNativeContext); \
        return JS_EXCEPTION;                           \
    }                                                  \
    }

#else

#define OOJS_PROFILE_ENTER_NAMED(NAME) {
#define OOJS_PROFILE_EXIT }

#define OOJS_NATIVE_ENTER(cx)                \
    {                                        \
        JSContext* oojsNativeContext = (cx); \
        try {

#define OOJS_NATIVE_EXIT                               \
    }                                                  \
    catch (...)                                        \
    {                                                  \
        OOJSReportCurrentException(oojsNativeContext); \
        return JS_EXCEPTION;                           \
    }                                                  \
    }

#endif // OOJS_PROFILE

/*	OOJSReportCurrentException()
        Call only inside a catch handler. Reports the exception being handled as a JS error unless
        one is already pending: the game's oo::Exception as "Native exception: <reason>" (what
        OOJSReportWrappedException() did), another C++ one as "Native exception: <what()>"
        (std::exception) or "Unidentified native exception".
*/
void OOJSReportCurrentException(JSContext* context);

#define OOJS_PROFILE_ENTER OOJS_PROFILE_ENTER_NAMED(__FUNCTION__)
#define OOJS_PROFILE_EXIT_VOID OOJS_PROFILE_EXIT

#define OOJS_BEGIN_FULL_NATIVE(context)                   \
    {                                                     \
        OOJSFullNativeScope oojsFullNativeScope(context); \
        {

#define OOJS_END_FULL_NATIVE \
    }                        \
    }

// The scope OOJS_BEGIN_FULL_NATIVE opens: a try and a finally, in the same order.
void OOJSPauseTimeLimiter(void);
void OOJSResumeTimeLimiter(void);

class OOJSFullNativeScope {
public:
    explicit OOJSFullNativeScope(JSContext* /*context*/) { OOJSPauseTimeLimiter(); }
    ~OOJSFullNativeScope() { OOJSResumeTimeLimiter(); }
    OOJSFullNativeScope(const OOJSFullNativeScope&) = delete;
    OOJSFullNativeScope& operator=(const OOJSFullNativeScope&) = delete;
};
