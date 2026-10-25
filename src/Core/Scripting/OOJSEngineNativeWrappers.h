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

#ifndef INCLUDED_OOJSENGINENATIVEWRAPPERS_h
#define INCLUDED_OOJSENGINENATIVEWRAPPERS_h

/*	Plain includes (bead oo-9ht.72): this header is reached from C++ binding translation units
	through OOJSEngineCore.h. OOCocoa.h gave it OOLITE_DEBUG and the function attributes.
*/
#include "OOFunctionAttributes.h"
#include "ooscript/JSEngine.hpp"

#ifndef OOLITE_DEBUG
// As OOCocoa.h defines it (an identical redefinition there is harmless).
#ifdef NDEBUG
#define OOLITE_DEBUG 0
#else
#define OOLITE_DEBUG 1
#endif
#endif


#ifdef __cplusplus
#ifndef OOJS_EXTERN_C
#define OOJS_EXTERN_C extern "C"
#endif
#else
#ifndef OOJS_EXTERN_C
#define OOJS_EXTERN_C
#endif
#endif


#define OOJS_PROFILE OOLITE_DEBUG

/*
	C++ since bead oo-ppc (the Phase 3 scripting-bindings pattern; proposed ADR-0056 amendment
	oo-ppc). The pairs below were Objective-C try, catch (id) and finally blocks. They are now a
	C++ try, a catch (...) and scope guards, so a binding file that uses them contains no
	Objective-C exception syntax. What each one does is unchanged:
	  * OOJS_NATIVE_EXIT catches whatever the body throws and hands it to
	    OOJSReportCurrentException() (OOJSEngineNativeWrappers.mm), which reports the game's
	    exception exactly as OOJSReportWrappedException() did (that function went with bead
	    oo-rskgl.1, when the exception became the C++ oo::Exception). It also reports a C++ exception
	    ("Native exception: <what()>"), which the Objective-C catch (id) could not catch: that
	    path ended in std::terminate (ADR-0029 measurement 10).
	  * The profiler frame is exited, and the time limiter and request are resumed, when the
	    scope ends, by return or by exception, as the finally blocks did.
*/

#if OOJS_PROFILE

#define OOJS_PROFILE_ENTER_NAMED(NAME) \
	{ \
		OOJSProfileScope oojsProfileScope(NAME); \
		{

#define OOJS_PROFILE_ENTER \
	OOJS_PROFILE_ENTER_NAMED(__FUNCTION__)

#define OOJS_PROFILE_EXIT_VAL(rval) \
		} \
		OOJSUnreachable(__FUNCTION__, __FILE__, __LINE__); \
		return rval; \
	}
#define OOJS_PROFILE_EXIT_VOID return; OOJS_PROFILE_EXIT_VAL()

#define OOJS_PROFILE_ENTER_FOR_NATIVE \
	{ \
		OOJSProfileScope oojsProfileScope(__FUNCTION__); \
		try {

#else

#define OOJS_PROFILE_ENTER			{
#define OOJS_PROFILE_EXIT_VAL(rval)	} OOJSUnreachable(__FUNCTION__, __FILE__, __LINE__); return (rval);
#define OOJS_PROFILE_EXIT_VOID		} return;
#define OOJS_PROFILE_ENTER_FOR_NATIVE try {

#endif	// OOJS_PROFILE

#define OOJS_NATIVE_ENTER(cx) \
	{ \
		ooscript::Context oojsNativeContext = (cx); \
		OOJS_PROFILE_ENTER_FOR_NATIVE

#define OOJS_NATIVE_EXIT \
		} catch (...) { \
			OOJSReportCurrentException(oojsNativeContext); \
			return false; \
		OOJS_PROFILE_EXIT_VAL(false) \
	}


/*	OOJSReportCurrentException()
	Call only inside a catch handler. Reports the exception being handled as a JS error unless
	one is already pending: the game's oo::Exception as "Native exception: <reason>" (what
	OOJSReportWrappedException() did), another C++ one as "Native exception: <what()>"
	(std::exception) or "Unidentified native exception".
*/
void OOJSReportCurrentException(ooscript::Context context);


#ifndef NDEBUG
OOJS_EXTERN_C void OOJSUnreachable(const char *function, const char *file, unsigned line)  NO_RETURN_FUNC;
#else
#define OOJSUnreachable(function, file, line) OO_UNREACHABLE()
#endif


#define OOJS_PROFILE_EXIT		OOJS_PROFILE_EXIT_VAL(0)
#define OOJS_PROFILE_EXIT_JSVAL	OOJS_PROFILE_EXIT_VAL(ooscript::undefinedValue())


/*
	OOJS_BEGIN_FULL_NATIVE() and OOJS_END_FULL_NATIVE
	These macros are used to bracket sections of native Oolite code within JS
	callbacks which may take a long time. Thet do two things: pause the
	time limiter, and (in thread-safe engine builds) suspend the current JS context
	request.
	
	These macros must be used in balanced pairs. They introduce a scope.
	
	Script engine functions may not be used, directly or indirectily, between these
	macros unless explicitly opening a request first.
*/
#define OOJS_BEGIN_FULL_NATIVE(context) \
	{ \
		OOJSFullNativeScope oojsFullNativeScope(context); \
		{

#define OOJS_END_FULL_NATIVE \
		} \
	}


// The scope OOJS_BEGIN_FULL_NATIVE opens: what its Objective-C try and finally did, in the same order.
OOJS_EXTERN_C void OOJSPauseTimeLimiter(void);
OOJS_EXTERN_C void OOJSResumeTimeLimiter(void);

class OOJSFullNativeScope
{
public:
	explicit OOJSFullNativeScope(ooscript::Context context)
	{
		OOJSPauseTimeLimiter();
		_context = context;
		_refCount = ooscript::suspendRequest(_context);
	}
	~OOJSFullNativeScope()
	{
		ooscript::resumeRequest(_context, _refCount);
		OOJSResumeTimeLimiter();
	}
	OOJSFullNativeScope(const OOJSFullNativeScope &) = delete;
	OOJSFullNativeScope &operator=(const OOJSFullNativeScope &) = delete;

private:
	ooscript::Context	_context = {};
	unsigned			_refCount = {};
};



#if OOJS_PROFILE

#include "OOProfilingStopwatch.h"

/*
	Profiler implementation details. This should be internal to
	OOJSTimeManagement.m, but needs to be declared on the stack by the macros
	above when profiling is enabled.
*/

typedef struct OOJSProfileStackFrame OOJSProfileStackFrame;
struct OOJSProfileStackFrame
{
	OOJSProfileStackFrame	*back;			// Stack link
	const void				*key;			// Key to look up profile entries. May be any pointer; currently const char * for native frames and ooscript::Function  for JS frames.
	const char				*function;		// Name of function, for native frames.
	OOHighResTimeValue		startTime;		// Time frame was entered.
	OOTimeDelta				subTime;		// Time spent in subroutine calls.
	OOTimeDelta				*total;			// Pointer to accumulator for this type of frame.
	void (*cleanup)(OOJSProfileStackFrame *);	// Cleanup function if needed (used for JS frames).
};



#define OOJS_DECLARE_PROFILE_STACK_FRAME(name) OOJSProfileStackFrame name;
OOJS_EXTERN_C void OOJSProfileEnter(OOJSProfileStackFrame *frame, const char *function);
OOJS_EXTERN_C void OOJSProfileExit(OOJSProfileStackFrame *frame);

// The scope OOJS_PROFILE_ENTER opens: enters the frame, and exits it however the scope ends.
class OOJSProfileScope
{
public:
	explicit OOJSProfileScope(const char *function)  { OOJSProfileEnter(&_frame, function); }
	~OOJSProfileScope()  { OOJSProfileExit(&_frame); }
	OOJSProfileScope(const OOJSProfileScope &) = delete;
	OOJSProfileScope &operator=(const OOJSProfileScope &) = delete;

private:
	OOJSProfileStackFrame	_frame = {};
};

#else

#define OOJS_DECLARE_PROFILE_STACK_FRAME(name)
#define OOJSProfileEnter(frame, function) do {} while (0)
#define OOJSProfileExit(frame) do {} while (0)

#endif

#endif	// INCLUDED_OOJSENGINENATIVEWRAPPERS_h
