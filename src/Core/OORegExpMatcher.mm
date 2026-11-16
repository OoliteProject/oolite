/*

OORegExpMatcher.mm


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

#import "OORegExpMatcher.h"
#import "OOFoundationBridge.h"
#import "OOJSFunction.h"
#import "OOJavaScriptEngine.h"

#include "oofnd/Thread.hpp"

// Pseudo-singleton: a single instance exists at a given time, but can be released.
static OORegExpMatcher* sActiveInstance;

@implementation OORegExpMatcher

+ (instancetype)regExpMatcher
{
    NSAssert(oo::thread::isMainThread(), @"OORegExpMatcher may only be used on the main thread.");

    if (sActiveInstance == nil) {
        sActiveInstance = [[[self alloc] init] autorelease];
    }

    return sActiveInstance;
}

- (id)init
{
    if ((self = [super init])) {
        const char* argumentNames[2] = { "string", "regexp" };
        unsigned codeLine = __LINE__ + 1; // NB: should remain line before code.
        const char* code = "return regexp.test(string);";

        [OOJavaScriptEngine sharedEngine]; // Summon the beast from the Pit.

        JSContext* context = OOJSAcquireContext();
        _tester = [[OOJSFunction alloc] initWithName:std::string("matchesRegExp")
                                               scope:JS_UNDEFINED
                                                code:std::string(code)
                                       argumentCount:2
                                       argumentNames:argumentNames
                                            fileName:oo::str::lastPathComponent(__FILE__)
                                          lineNumber:codeLine
                                             context:context];

        OOJSRelinquishContext(context);

        if (_tester == nil)
            DESTROY(self);
    }

    return self;
}

- (void)dealloc
{
    if (sActiveInstance == self)
        sActiveInstance = nil;

    DESTROY(_tester);
    DESTROY(_cachedRegExpObject);

    [super dealloc];
}

- (BOOL)string:(const std::string&)string matchesExpression:(const std::string&)regExp
{
    return [self string:string matchesExpression:regExp flags:0];
}

- (BOOL)string:(const std::string&)string matchesExpression:(const std::string&)regExp flags:(NSUInteger)flags
{
    NSAssert(oo::thread::isMainThread(), @"OORegExpMatcher may only be used on the main thread.");

    const std::u16string regExpUnits = oo::utf8ToUtf16(regExp);
    size_t expLength = regExpUnits.size();
    if (EXPECT_NOT(expLength == 0))
        return NO;

    JSContext* context = OOJSAcquireContext();

    // Create new RegExp object if necessary.
    if (flags != _cachedFlags || _cachedRegExpString != regExp) {
        _cachedRegExpString.reset();
        DESTROY(_cachedRegExpObject);

        // QuickJS has no API to create a RegExp directly, so call the RegExp constructor.
        _cachedRegExpString = regExp;
        std::string flagString;
        if (flags & kOORegExpCaseInsensitive)
            flagString += "i";
        if (flags & kOORegExpMultiLine)
            flagString += "m";
        JSValue global = JS_GetGlobalObject(context);
        JSValue constructor = JS_GetPropertyStr(context, global, "RegExp");
        JSValue args[2] = { JS_NewStringLen(context, regExp.data(), regExp.size()), JS_NewStringLen(context, flagString.data(), flagString.size()) };
        JSValue regExpObj = JS_CallConstructor(context, constructor, 2, args);
        if (JS_IsException(regExpObj)) {
            OOJSReportPendingException(context);
            regExpObj = JS_NULL;
        }
        _cachedRegExpObject = [[OOJSValue alloc] initWithJSValue:regExpObj inContext:context];
        _cachedFlags = flags;

        JS_FreeValue(context, regExpObj);
        JS_FreeValue(context, args[0]);
        JS_FreeValue(context, args[1]);
        JS_FreeValue(context, constructor);
        JS_FreeValue(context, global);
    }

    BOOL result = [_tester evaluatePredicateWithContext:context
                                                  scope:nil
                                              arguments:oo::ObjCRefsFrom<id>(oo::NSArrayFromObjects(std::vector<id> { oo::NSStringFrom(string), _cachedRegExpObject }))];

    OOJSRelinquishContext(context);

    return result;
}

@end
