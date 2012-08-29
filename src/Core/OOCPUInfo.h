/*

OOCPUInfo.h

Capabilities and features of CPUs.

Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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

*/

#import "OOCocoa.h"
#include <stdint.h>


void OOCPUInfoInit(void);


/*	Number of processors (whether they be individual or cores), used to select
	number of threads to use for things like texture loading.
*/
NSUInteger OOCPUCount(void);


/*	Set up OOLITE_BIG_ENDIAN and OOLITE_LITTLE_ENDIAN macros. Exactly one must
	be non-zero. If you're porting Oolite to a middle-endian platform, you'll
	need to work out what to do with endian-sensitive stuff -- currently, that
	means texture loading. (The data cache automatically rejects cached data
	of the wrong byte sex.)
*/
#if !defined(OOLITE_BIG_ENDIAN) && !defined(OOLITE_LITTLE_ENDIAN)

#if __BIG_ENDIAN__
#define OOLITE_BIG_ENDIAN		1
#endif

#if __LITTLE_ENDIAN__
#define OOLITE_LITTLE_ENDIAN	1
#endif


#if !defined(OOLITE_BIG_ENDIAN) && !defined(OOLITE_LITTLE_ENDIAN)
#if defined(__i386__) || defined(__amd64__) || defined(__x86_64__)
#define OOLITE_LITTLE_ENDIAN	1
#endif

#if defined(__sgi__) || defined(__mips__) 
#define OOLITE_BIG_ENDIAN       1 
#endif 

// Do not assume PPC == big endian, it can be either.

#endif	// inner none defined
#endif	// outer none defined


#ifndef OOLITE_BIG_ENDIAN
#define OOLITE_BIG_ENDIAN		0
#endif

#ifndef OOLITE_LITTLE_ENDIAN
#define OOLITE_LITTLE_ENDIAN	0
#endif


#if !OOLITE_BIG_ENDIAN && !OOLITE_LITTLE_ENDIAN
#error Neither OOLITE_BIG_ENDIAN nor OOLITE_LITTLE_ENDIAN is defined as nonzero!

#undef OOLITE_BIG_ENDIAN
#undef OOLITE_LITTLE_ENDIAN

// Cause errors where the macros are used
#define OOLITE_BIG_ENDIAN		"BUG"
#define OOLITE_LITTLE_ENDIAN	"BUG"
#endif


/*	Set up OOLITE_NATIVE_64_BIT. This is intended for 64-bit optimizations
	(see OOTextureScaling.m). It is not set for systems where 64-bitness may
	be determined at runtime (such as 32-bit OS X binaries), because I can't
	be bothered to do the set-up required to use switch to a 64-bit code path
	at runtime while being cross-platform.
	-- Ahruman
*/

#ifndef OOLITE_NATIVE_64_BIT

#ifdef _UINT64_T
#ifdef __ppc64__
#define OOLITE_NATIVE_64_BIT	1
#elif __amd64__
#define OOLITE_NATIVE_64_BIT	1
#elif __x86_64__
#define OOLITE_NATIVE_64_BIT	1
#endif
#endif	// _UINT64_T

#ifndef OOLITE_NATIVE_64_BIT
#define OOLITE_NATIVE_64_BIT	0
#endif

#endif	// defined(OOLITE_NATIVE_64_BIT)
