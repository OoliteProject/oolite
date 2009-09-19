/*

NSNumberOOExtensions.m


Oolite
Copyright (C) 2004-2009 Giles C Williams and contributors

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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2009 Jens Ayton

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
	return (strcmp(type, @encode(double)) == 0 || strcmp(type, @encode(float)) == 0 || strcmp(type, @encode(long double)) == 0);
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
		
		Cocotron, oddly enough, does miss the obvious optimization. If using
		this with Cocotron, the best workaround I can think of is to add a
		category to NSNumber_BOOL like we do with NSBoolNumber for GNUstep.
	*/
	
#if __COREFOUNDATION_CFNUMBER__
	return self == (NSNumber *)kCFBooleanTrue || self == (NSNumber *)kCFBooleanFalse;
#else
	static NSNumber *sTrue = nil, sFalse;
	if (EXPECT_NOT(sTrue == nil))
	{
		sTrue = [[NSNumber numberWithBool:YES] retain];
		sFalse = [[NSNumber numberWithBool:NO] retain];
	}
	return self == sTrue || self == sFalse;
#endif
}

@end


#ifdef GNUSTEP

/*	As an optimization, we override the implementation on NSBoolNumber to
	always return YES. In practical terms, we could always return NO in
	NSNumber's implementation, but I don't want to introduce a dependency on
	private classes staying the same. In fact, if this somehow turns out to
	be a hot spot, I'd rather introduce categories on the other commonly-used
	internal classes to return NO instead.
*/

@interface NSBoolNumber: NSNumber
// Ignoring ivars here; we're not accessing them or subclassing.
@end


@interface NSBoolNumber (OOExtensions)

- (BOOL) oo_isBoolean
{
	return YES;
}

@end

#endif
