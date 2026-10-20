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

#import "OOJSEngineTimeManagement.h"

/*	The SpiderMonkey version of this file implemented the time limiter
        (with a watchdog thread that triggered SpiderMonkey's operation
        callback) and the JavaScript profiler.

        With QuickJS, the time limiter is implemented in OOJavaScriptEngine.m on
        top of QuickJS's interrupt handler, which QuickJS polls while running
        JavaScript, so neither the watchdog thread nor the operation callback is
        needed. The profiler is not ported (see OOJSEngineTimeManagement.h).
*/

void OOJSTimeManagementInit(OOJavaScriptEngine* engine, JSRuntime* runtime)
{
    // The interrupt handler is installed by -[OOJavaScriptEngine init].
}
