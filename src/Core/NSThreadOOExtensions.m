/*

NSThreadOOExtensions.h

Utility methods for NSThread.

 
Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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

Copyright (C) 2007 Jens Ayton

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


#ifndef OO_HAVE_PTHREAD_SETNAME_NP
#define OO_HAVE_PTHREAD_SETNAME_NP 0
#endif


#if !OO_HAVE_PTHREAD_SETNAME_NP && OOLITE_MAC_OS_X
#undef OO_HAVE_PTHREAD_SETNAME_NP
#define OO_HAVE_PTHREAD_SETNAME_NP 1
#define PTHREAD_SETNAME_DYNAMIC 1
#endif


#if !OO_HAVE_PTHREAD_SETNAME_NP
#define pthread_setname_np(name) do {} while (0)
#endif


#if PTHREAD_SETNAME_DYNAMIC
static int InitialSetNameFunc(const char *name);
static int (*PThreadSetNameNPFunc)(const char *name) = InitialSetNameFunc;
#define pthread_setname_np(name) do { if (PThreadSetNameNPFunc != NULL)  PThreadSetNameNPFunc(name); } while (0)
#endif



@interface NSThread (LeopardAdditions)
- (void) setName:(NSString *)name;
@end

@interface NSLock (LeopardAdditions)
- (void) setName:(NSString *)name;
@end

@interface NSRecursiveLock (LeopardAdditions)
- (void) setName:(NSString *)name;
@end

@interface NSConditionLock (LeopardAdditions)
- (void) setName:(NSString *)name;
@end


@implementation NSThread (OOExtensions)

+ (void) ooSetCurrentThreadName:(NSString *)name
{
	NSThread			*thread = nil;
	
	thread = [NSThread currentThread];
	if ([thread respondsToSelector:@selector(setName:)])
	{
		[thread setName:name];
	}
	/*	Under Mac OS X 10.6, the name set by pthread_setname_np() is used in
		crash reports, but, annoyingly, -[NSThread setName:] does not call it.
	*/
	pthread_setname_np([name UTF8String]);
}

@end


@implementation NSLock (OOExtensions)

- (void) ooSetName:(NSString *)name
{
	if ([self respondsToSelector:@selector(setName:)])
	{
		[self setName:name];
	}
}

@end


@implementation NSRecursiveLock (OOExtensions)

- (void) ooSetName:(NSString *)name
{
	if ([self respondsToSelector:@selector(setName:)])
	{
		[self setName:name];
	}
}

@end


@implementation NSConditionLock (OOExtensions)

- (void) ooSetName:(NSString *)name
{
	if ([self respondsToSelector:@selector(setName:)])
	{
		[self setName:name];
	}
}

@end


#if PTHREAD_SETNAME_DYNAMIC

#import <dlfcn.h>

// Attempt to load pthread_setname_np() (available in Mac OS X 10.6 or later)
static int InitialSetNameFunc(const char *name)
{
	@synchronized ([NSThread class])	// Thread functions should be thread safe.
	{
		if (PThreadSetNameNPFunc == InitialSetNameFunc)	// Only look up once.
		{
			PThreadSetNameNPFunc = dlsym(RTLD_DEFAULT, "pthread_setname_np");
		}
	}
	
	if (PThreadSetNameNPFunc != NULL)
	{
		return PThreadSetNameNPFunc(name);
	}
	else
	{
		return 0;
	}
}

#endif
