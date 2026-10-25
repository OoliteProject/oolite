/*

OOFastArithmetic.h

Mathematical framework for Oolite.

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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


#ifndef INCLUDED_OOMATHS_h
	#error Do not include OOFastArithmetic.h directly; include OOMaths.h.
#else


/* Clamp to range. */
OOINLINE float OOClamp_0_1_f(float value) INLINE_CONST_FUNC;
OOINLINE float OOClamp_n1_1_f(float value) INLINE_CONST_FUNC;
OOINLINE double OOClamp_0_1_d(double value) INLINE_CONST_FUNC;
OOINLINE float OOClamp_0_max_f(float value, float max) INLINE_CONST_FUNC;
OOINLINE double OOClamp_0_max_d(double value, double max) INLINE_CONST_FUNC;

/* Linear interpolation. */
OOINLINE float OOLerp(float v0, float v1, float fraction) INLINE_CONST_FUNC;
OOINLINE double OOLerpd(double v0, double v1, double fraction) INLINE_CONST_FUNC;


/* Round integer up to nearest power of 2.
   The expression has no defined value for 1 (__builtin_clz(0)) nor for 0 and values above the
   high bit (a shift by -1). Those inputs return what the optimised x86-64 build has always
   returned for them, so debug and release agree (bead oo-lglaq): 2 for 1, and 1 for 0 and for
   values above the high bit (not 0, as an older note here said). */
OOINLINE INLINE_CONST_FUNC uint32_t OORoundUpToPowerOf2_32(uint32_t value)
{
	if (value == 1)  return 2;
	int zeros = __builtin_clz(value - 1);
	return (zeros == 0) ? 1 : 0x80000000U >> (zeros - 1);
}


OOINLINE INLINE_CONST_FUNC uint64_t OORoundUpToPowerOf2_64(uint64_t value)
{
	if (value == 1)  return 2;
	int zeros = __builtin_clzll(value - 1);
	return (zeros == 0) ? 1 : 0x8000000000000000ULL >> (zeros - 1);
}


#if defined(__cplusplus) && !defined(OO_PLAIN_CPP_UNIT)	// was __OBJC__: a game unit (an Objective-C++ unit until bead oo-dbz), not a plain C++ one
#if OOLITE_64_BIT
OOINLINE INLINE_CONST_FUNC NSUInteger OORoundUpToPowerOf2_NS(NSUInteger value)
{
	return OORoundUpToPowerOf2_64(value);
}
#else
OOINLINE INLINE_CONST_FUNC NSUInteger OORoundUpToPowerOf2_NS(NSUInteger value)
{
	return OORoundUpToPowerOf2_32(value);
}
#endif
#endif


OOINLINE float OOClamp_0_1_f(float value)
{
	return fmax(0.0f, fmin(value, 1.0f));
}

OOINLINE float OOClamp_n1_1_f(float value)
{
	return fmax(-1.0f, fmin(value, 1.0f));
}

OOINLINE double OOClamp_0_1_d(double value)
{
	return fmax(0.0f, fmin(value, 1.0f));
}

OOINLINE float OOClamp_0_max_f(float value, float max)
{
	return fmax(0.0f, fmin(value, max));
}

OOINLINE double OOClamp_0_max_d(double value, double max)
{
	return fmax(0.0, fmin(value, max));
}

// Moved verbatim from the collection extractors oo-snzn retired.
OOINLINE long long OOClampInteger(long long value, long long minValue, long long maxValue) ALWAYS_INLINE_FUNC;
OOINLINE long long OOClampInteger(long long value, long long minValue, long long maxValue)
{
	return (minValue < value) ? ((value < maxValue) ? value : maxValue) : minValue;
}


OOINLINE float OOLerp(float v0, float v1, float fraction)
{
	// Linear interpolation - equivalent to v0 * (1.0f - fraction) + v1 * fraction.
	return v0 + fraction * (v1 - v0);
}

OOINLINE double OOLerpd(double v0, double v1, double fraction)
{
	// Linear interpolation - equivalent to v0 * (1.0 - fraction) + v1 * fraction.
	return v0 + fraction * (v1 - v0);
}



#endif	/* INCLUDED_OOMATHS_h */
