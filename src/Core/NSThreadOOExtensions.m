/*

NSThreadOOExtensions.m

 
Copyright (C) 2007-2013 Jens Ayton

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

#import "NSThreadOOExtensions.h"
#import "OOCocoa.h"
#include <pthread.h>


#define OO_HAVE_PTHREAD_SETNAME_NP	OOLITE_MAC_OS_X_10_6


@implementation NSThread (OOExtensions)

+ (void) ooSetCurrentThreadName:(NSString *)name
{
	// We may be called with no pool in place.
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	[[NSThread currentThread] setName:name];
	
#if OO_HAVE_PTHREAD_SETNAME_NP
	/*	Under Mac OS X 10.6, the name set by pthread_setname_np() is used in
		crash reports, but, annoyingly, -[NSThread setName:] does not call it.
	*/
	pthread_setname_np([name UTF8String]);
#endif
	
	[pool release];
}

@end
