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
OOINLINE double OOClamp_0_1_d(double value) INLINE_CONST_FUNC;
OOINLINE float OOClamp_0_max_f(float value, float max) INLINE_CONST_FUNC;
OOINLINE double OOClamp_0_max_d(double value, double max) INLINE_CONST_FUNC;

/* Linear interpolation. */
OOINLINE float OOLerp(float v0, float v1, float fraction) INLINE_CONST_FUNC;


/* Round integer up to nearest power of 2. NOTE: these return 0 if the high bit of value is set. */
OOINLINE INLINE_CONST_FUNC uint32_t OORoundUpToPowerOf2_32(uint32_t value)
{
	return 0x80000000U >> (__builtin_clz(value - 1) - 1);
}


OOINLINE INLINE_CONST_FUNC uint64_t OORoundUpToPowerOf2_64(uint64_t value)
{
	return 0x8000000000000000ULL >> (__builtin_clzll(value - 1) - 1);
}


#if __OBJC__
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


OOINLINE float OOLerp(float v0, float v1, float fraction)
{
	// Linear interpolation - equivalent to v0 * (1.0f - fraction) + v1 * fraction.
	return v0 + fraction * (v1 - v0);
}


#endif	/* INCLUDED_OOMATHS_h */
