/*

OORegExpMatcher.h

Regular expression utility built on top of JavaScript regexp objects in lieu
of Objective-C regexp support. Not thread-safe.

If we had a performance-critical need for regexps, I'd want a real library,
but this will do for light usage.


Copyright (C) 2010-2012 Jens Ayton

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

#import "OOCocoa.h"
#include <jsapi.h>

@class OOJSFunction, OOJSValue;


enum
{
	kOORegExpCaseInsensitive	= JSREG_FOLD,
	kOORegExpMultiLine			= JSREG_MULTILINE
};


@interface OORegExpMatcher: NSObject
{
@private
	OOJSFunction			*_tester;
	NSString				*_cachedRegExpString;
	OOJSValue				*_cachedRegExpObject;
	OOUInteger				_cachedFlags;
}

+ (instancetype) regExpMatcher;

- (BOOL) string:(NSString *)string matchesExpression:(NSString *)regExp;
- (BOOL) string:(NSString *)string matchesExpression:(NSString *)regExp flags:(OOUInteger)flags;

@end


@interface NSString (OORegExpMatcher)

- (BOOL) oo_matchesRegularExpression:(NSString *)regExp;

@end
