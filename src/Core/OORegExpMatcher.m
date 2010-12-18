/*

OORegExpMatcher.m


Copyright (C) 2010 Jens Ayton

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
#import "OOJSFunction.h"


// Pseudo-singleton: a single instance exists at a given time, but can be released.
static OORegExpMatcher *sActiveInstance;


@implementation OORegExpMatcher

+ (id) regExpMatcher
{
#if OOLITE_LEOPARD || OOLITE_GNUSTEP
	NSAssert([[NSThread currentThread] isMainThread], @"OORegExpMatcher may only be used on the main thread.");
#endif
	
	if (sActiveInstance == nil)
	{
		sActiveInstance = [[[self alloc] init] autorelease];
	}
	
	return sActiveInstance;
}


- (id) init
{
	if ((self = [super init]))
	{	
		const char *argumentNames[2] = { "string", "regexp" };
		unsigned codeLine = __LINE__ + 1;	// NB: should remain line before code.
		NSString *code = @"return regexp.test(string);";
		
		JSContext *context = [[OOJavaScriptEngine sharedEngine] acquireContext];
		_tester = [[OOJSFunction alloc] initWithName:@"matchesRegExp"
											   scope:NULL
												code:code
									   	argumentCount:2
									   argumentNames:argumentNames
											fileName:[@__FILE__ lastPathComponent]
										  lineNumber:codeLine
											 context:context];
		
		[[OOJavaScriptEngine sharedEngine] releaseContext:context];
		
		if (_tester == nil)  DESTROY(self);
	}
	
	return self;
}


- (void) dealloc
{
	if (sActiveInstance == self)  sActiveInstance = nil;
	
	DESTROY(_tester);
	DESTROY(_cachedRegExpString);
	DESTROY(_cachedRegExpObject);
	
	[super dealloc];
}


- (BOOL) string:(NSString *)string matchesExpression:(NSString *)regExp
{
	return [self string:string matchesExpression:regExp flags:0];
}


- (BOOL) string:(NSString *)string matchesExpression:(NSString *)regExp flags:(OOUInteger)flags
{
#if OOLITE_LEOPARD || OOLITE_GNUSTEP
	NSAssert([[NSThread currentThread] isMainThread], @"OORegExpMatcher may only be used on the main thread.");
#endif
	
	size_t expLength = [regExp length];
	if (EXPECT_NOT(expLength == 0))  return NO;
	
	JSContext *context = [[OOJavaScriptEngine sharedEngine] acquireContext];
	
	// Create new RegExp object if necessary.
	if (flags != _cachedFlags || ![regExp isEqualToString:_cachedRegExpString])
	{
		DESTROY(_cachedRegExpString);
		DESTROY(_cachedRegExpObject);
		
		unichar *buffer;
		buffer = malloc(expLength * sizeof *buffer);
		if (EXPECT_NOT(buffer == NULL))  return NO;
		[regExp getCharacters:buffer];
		
		JS_BeginRequest(context);
		_cachedRegExpString = [regExp retain];
#if OO_NEW_JS
		JSObject *regExpObj = JS_NewUCRegExpObjectNoStatics(context, buffer, expLength, flags);
#else
		JSObject *regExpObj = JS_NewUCRegExpObject(context, buffer, expLength, flags);
#endif
		_cachedRegExpObject = [[OOJSValue alloc] initWithJSObject:regExpObj inContext:context];
		_cachedFlags = flags;
		JS_EndRequest(context);
		
		free(buffer);
	}
	
	BOOL result = [_tester evaluatePredicateWithContext:context
												  scope:nil
											  arguments:[NSArray arrayWithObjects:string, _cachedRegExpObject, nil]];
	
	[[OOJavaScriptEngine sharedEngine] releaseContext:context];
	
	return result;
}

@end


@implementation NSString (OORegExpMatcher)

- (BOOL) oo_matchesRegularExpression:(NSString *)regExp
{
	return [[OORegExpMatcher regExpMatcher] string:self matchesExpression:regExp];
}

@end
