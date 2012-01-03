/*

NSNumberOOExtensions.m


Copyright (C) 2009-2012 Jens Ayton

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

#import "NSNumberOOExtensions.h"
#import "OOFunctionAttributes.h"


@implementation NSNumber (OOExtensions)

- (BOOL) oo_isFloatingPointNumber
{
#if __COREFOUNDATION_CFNUMBER__
	return CFNumberIsFloatType((CFNumberRef)self);
#else
	/*	This happily assumes the compiler will inline strcmp() where one
		argument is a single-character constant string. Verified under
		apple-gcc 4.0 (even with -O0).
	*/
	const char *type = [self objCType];
	return (strcmp(type, @encode(double)) == 0 || strcmp(type, @encode(float)) == 0);
#endif
}


- (BOOL) oo_isBoolean
{
	/*	There's no explicit way to test this. However, on Mac OS X boolean
		NSNumbers are required to be constant objects because they're toll-
		free bridged with kCFBooleanTrue and kCFBooleanFalse, so comparison to
		those values has to work.
		
		In GNUstep, constant objects are also used, because they're not about
		to miss such an obvious optimization.
	*/
	
#if __COREFOUNDATION_CFNUMBER__
	return self == (NSNumber *)kCFBooleanTrue || self == (NSNumber *)kCFBooleanFalse;
#else
	static NSNumber *sTrue = nil, *sFalse;
	if (EXPECT_NOT(sTrue == nil))
	{
		sTrue = [[NSNumber numberWithBool:YES] retain];
		sFalse = [[NSNumber numberWithBool:NO] retain];
	}
	return self == sTrue || self == sFalse;
#endif
}

@end
