/*

OOCPUInfo.h

Capabilities and features of CPUs.

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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


/*	Must be called once -- currently in [Universe init].
*/
void OOCPUInfoInit(void);


/*	Number of processors (whether they be individual or cores), used to select
	number of threads to use for things like texture loading.
	
	Currently always 1 on non-Mac systems!
*/
unsigned OOCPUCount(void);


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

#ifdef __ppc64__
#define OOLITE_NATIVE_64_BIT	1
#elif __amd64__
#define OOLITE_NATIVE_64_BIT	1
#elif __x86_64__
#define OOLITE_NATIVE_64_BIT	1
#endif

#ifndef OOLITE_NATIVE_64_BIT
#define OOLITE_NATIVE_64_BIT	0
#endif

#endif	// defined(OOLITE_NATIVE_64_BIT)


/*	Set up OOLITE_ALTIVEC -- availability flag for AltiVec/VMX.
	If AltiVec instructions are being used, OOAltivecAvailable() should be
	used to test for availability. If compiling for PPC systems with AltiVec
	only, predefine OOLITE_ALTIVEC_ALWAYS to 1. Availability check is
	OS-dependent, currently OS X only; see below.
	
	NOTE: in its current form, this requires __VEC__ to be defined as nonzero.
	This is done by gcc when -maltivec is used, which it won't be by default
	in GNUmakefile builds.
*/
#ifndef OOLITE_ALTIVEC

#if (defined(__ppc__) || defined(__ppc64__)) && __VEC__
#define OOLITE_ALTIVEC			1
#else
#define OOLITE_ALTIVEC			0
#endif

#endif


#if OOLITE_ALTIVEC
#ifndef __GNUC__
#warning OOLITE_ALTIVEC is set, but the compiler is not gcc. Altivec support is currenty written with the assumption of gcc and may not work on other compilers.
#endif

#if OOLITE_ALTIVEC_ALWAYS
#define OOAltiVecAvailable()	(1)
#else
#ifndef OOLITE_ALTIVEC_DYNAMIC
#define OOLITE_ALTIVEC_DYNAMIC	1
#endif
#endif

#if OOLITE_ALTIVEC_DYNAMIC && !OOLITE_MAC_OS_X
#warning OOLITE_ALTIVEC is set, but Oolite doesn't know how to detect AltiVec on this platform. Either implement OOAltivecAvailable() or predefine OOLITE_ALTIVEC_ALWAYS to 1 if you know it will always be available.
#undef OOLITE_ALTIVEC_DYNAMIC
#undef OOLITE_ALTIVEC
#define OOLITE_ALTIVEC			0
#endif

#if OOLITE_ALTIVEC_DYNAMIC
BOOL OOAltiVecAvailable(void);
#endif
#endif

// After all this, I haven't got around to implementing Altivec texture scaling. -- Ahruman
