/*

OORegExpMatcher.h

Regular expression utility built on top of JavaScript regexp objects in lieu
of Objective-C regexp support. Not thread-safe.

If we had a performance-critical need for regexps, I'd want a real library,
but this will do for light usage.


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

#import "OOFoundation.h"
#include "oofnd/StdLib.hpp"
#import "oofnd/objc/OOObject.h"

@class OOJSFunction, OOJSValue;

// Same values as SpiderMonkey's JSREG_FOLD and JSREG_MULTILINE.
enum {
    kOORegExpCaseInsensitive = 0x01,
    kOORegExpMultiLine = 0x04
};

@interface OORegExpMatcher : OOObject {
@private
    OOJSFunction* _tester;
    std::optional<std::string> _cachedRegExpString; // UTF-8; nullopt: nothing cached (proposed ADR-0043)
    OOJSValue* _cachedRegExpObject;
    NSUInteger _cachedFlags;
}

+ (instancetype)regExpMatcher;

// Strings are UTF-8 (Foundation sweep, proposed ADR-0043). The Objective-C string category
// -oo_matchesRegularExpression: was [[OORegExpMatcher regExpMatcher] string:self matchesExpression:regExp];
// its callers now send that message themselves.
- (BOOL)string:(const std::string&)string matchesExpression:(const std::string&)regExp;
- (BOOL)string:(const std::string&)string matchesExpression:(const std::string&)regExp flags:(NSUInteger)flags;

@end
