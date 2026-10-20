/*

OOJSEngineTimeManagement.h

Functionality related to time limiting and profiling of JavaScript code.


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

#import "OOJavaScriptEngine.h"

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

        With QuickJS, the limiter functions (OOJSStartTimeLimiterWithTimeLimit(),
        OOJSStartTimeLimiter(), OOJSStopTimeLimiter(), OOJSPauseTimeLimiter(),
        OOJSResumeTimeLimiter(), kOOJSLongTimeLimit and, in debug builds,
        OOJSResetTimeLimiter(), OOJSGetTimeLimiterLimit() and
        OOJSSetTimeLimiterLimit()) are declared in OOJavaScriptEngine.h and
        implemented in OOJavaScriptEngine.m. QuickJS polls an interrupt handler
        while running JS code, so no watchdog thread or operation callback is
        needed.

        Not ported: the debug-build variants that record the file and line of
        the last start/stop (OOJSStartTimeLimiterWithTimeLimit_() and
        OOJSStopTimeLimiter_()), which were only used to diagnose unbalanced
        calls.
*/

/*	Profiling

        The SpiderMonkey build's profiler (OOJSBeginProfiling(),
        OOJSEndProfiling(), OOJSIsProfiling(), OOTimeProfile and
        OOTimeProfileEntry, used by the debug console's profile(), getProfile()
        and trace()) depended on SpiderMonkey's function call hook and on
        per-native OOJS_PROFILE_ENTER/EXIT bookkeeping. QuickJS has no function
        call hook, and OOJS_PROFILE_ENTER/EXIT are plain blocks, so profiling is
        not available: OOJS_PROFILE is 0 and the profiling API is not declared.
*/
#ifndef OOJS_PROFILE
#define OOJS_PROFILE 0
#endif

@class OOJavaScriptEngine;

/*	Formerly installed the watchdog thread and operation callback. The QuickJS
        interrupt handler is installed by -[OOJavaScriptEngine init], so this
        does nothing; it is kept for source compatibility.
*/
void OOJSTimeManagementInit(OOJavaScriptEngine* engine, JSRuntime* runtime);
