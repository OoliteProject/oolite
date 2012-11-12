/*

OOJSEngineNativeWrappers.h
(Included by OOJavaScriptEngine.h)

Exception safety and profiling macros.

Every JavaScript native callback that could concievably cause an
Objective-C exception should begin with OOJS_NATIVE_ENTER() and end with
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
Copyright (C) 2007-2012 David Taylor and Jens Ayton.

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


#ifndef OOJS_PROFILE
#define OOJS_PROFILE (!defined(NDEBUG))
#endif

#if OOJS_PROFILE


#define OOJS_PROFILE_ENTER_NAMED(NAME) \
	{ \
		OOJS_DECLARE_PROFILE_STACK_FRAME(oojsProfilerStackFrame) \
		@try { \
			OOJSProfileEnter(&oojsProfilerStackFrame, NAME);

#define OOJS_PROFILE_ENTER \
	OOJS_PROFILE_ENTER_NAMED(__FUNCTION__)

#define OOJS_PROFILE_EXIT_VAL(rval) \
		} @finally { \
			OOJSProfileExit(&oojsProfilerStackFrame); \
		} \
		OOJSUnreachable(__FUNCTION__, __FILE__, __LINE__); \
		return rval; \
	}
#define OOJS_PROFILE_EXIT_VOID return; OOJS_PROFILE_EXIT_VAL()

#define OOJS_PROFILE_ENTER_FOR_NATIVE OOJS_PROFILE_ENTER

#else

#define OOJS_PROFILE_ENTER			{
#define OOJS_PROFILE_EXIT_VAL(rval)	} OOJSUnreachable(__FUNCTION__, __FILE__, __LINE__); return (rval);
#define OOJS_PROFILE_EXIT_VOID		} return;
#define OOJS_PROFILE_ENTER_FOR_NATIVE @try {

#endif	// OOJS_PROFILE

#define OOJS_NATIVE_ENTER(cx) \
	{ \
		JSContext *oojsNativeContext = (cx); \
		OOJS_PROFILE_ENTER_FOR_NATIVE

#define OOJS_NATIVE_EXIT \
		} @catch(id exception) { \
			OOJSReportWrappedException(oojsNativeContext, exception); \
			return NO; \
		OOJS_PROFILE_EXIT_VAL(NO) \
	}


void OOJSReportWrappedException(JSContext *context, id exception);


#ifndef NDEBUG
void OOJSUnreachable(const char *function, const char *file, unsigned line)  NO_RETURN_FUNC;
#else
#define OOJSUnreachable(function, file, line) OO_UNREACHABLE()
#endif


#define OOJS_PROFILE_EXIT		OOJS_PROFILE_EXIT_VAL(0)
#define OOJS_PROFILE_EXIT_JSVAL	OOJS_PROFILE_EXIT_VAL(JSVAL_VOID)


/*
	OOJS_BEGIN_FULL_NATIVE() and OOJS_END_FULL_NATIVE
	These macros are used to bracket sections of native Oolite code within JS
	callbacks which may take a long time. Thet do two things: pause the
	time limiter, and (in JS_THREADSAFE builds) suspend the current JS context
	request.
	
	These macros must be used in balanced pairs. They introduce a scope.
	
	JSAPI functions may not be used, directly or indirectily, between these
	macros unless explicitly opening a request first.
*/
#if JS_THREADSAFE
#define OOJS_BEGIN_FULL_NATIVE(context) \
	{ \
		OOJSPauseTimeLimiter(); \
		JSContext *oojsRequestContext = (context); \
		jsrefcount oojsRequestRefCount = JS_SuspendRequest(oojsRequestContext); \
		@try \
		{

#define OOJS_END_FULL_NATIVE \
		} \
		@finally \
		{ \
			JS_ResumeRequest(oojsRequestContext, oojsRequestRefCount); \
			OOJSResumeTimeLimiter(); \
		} \
	}
#else
#define OOJS_BEGIN_FULL_NATIVE(context) \
	{ \
		(void)(context); \
		OOJSPauseTimeLimiter(); \
		@try \
		{

#define OOJS_END_FULL_NATIVE \
		} \
		@finally \
		{ \
			OOJSResumeTimeLimiter(); \
		} \
	}
#endif



#if OOJS_PROFILE

#import "OOProfilingStopwatch.h"

/*
	Profiler implementation details. This should be internal to
	OOJSTimeManagement.m, but needs to be declared on the stack by the macros
	above when profiling is enabled.
*/

typedef struct OOJSProfileStackFrame OOJSProfileStackFrame;
struct OOJSProfileStackFrame
{
	OOJSProfileStackFrame	*back;			// Stack link
	const void				*key;			// Key to look up profile entries. May be any pointer; currently const char * for native frames and JSFunction * for JS frames.
	const char				*function;		// Name of function, for native frames.
	OOHighResTimeValue		startTime;		// Time frame was entered.
	OOTimeDelta				subTime;		// Time spent in subroutine calls.
	OOTimeDelta				*total;			// Pointer to accumulator for this type of frame.
	void (*cleanup)(OOJSProfileStackFrame *);	// Cleanup function if needed (used for JS frames).
};



#define OOJS_DECLARE_PROFILE_STACK_FRAME(name) OOJSProfileStackFrame name;
void OOJSProfileEnter(OOJSProfileStackFrame *frame, const char *function);
void OOJSProfileExit(OOJSProfileStackFrame *frame);

#else

#define OOJS_DECLARE_PROFILE_STACK_FRAME(name)
#define OOJSProfileEnter(frame, function) do {} while (0)
#define OOJSProfileExit(frame) do {} while (0)

#endif
