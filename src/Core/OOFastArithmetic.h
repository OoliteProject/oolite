/*

OOFastArithmetic.h

Mathematical framework for Oolite.

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


#ifndef INCLUDED_OOMATHS_h
	#error Do not include OOFastArithmetic.h directly; include OOMaths.h.
#else


#ifdef WIN32
	#define FASTINVSQRT_ENABLED	0	/* Doesn't work on Windows (why?) */
#else
	#define FASTINVSQRT_ENABLED	0	/* Disabled due to precision problems. */
#endif


/* Round integer up to nearest power of 2. */
OOINLINE uint32_t OORoundUpToPowerOf2(uint32_t x) INLINE_CONST_FUNC;

/* Clamp to range. */
OOINLINE float OOClamp_0_1_f(float value) INLINE_CONST_FUNC;
OOINLINE double OOClamp_0_1_d(double value) INLINE_CONST_FUNC;
OOINLINE float OOClamp_0_max_f(float value, float max) INLINE_CONST_FUNC;
OOINLINE double OOClamp_0_max_d(double value, double max) INLINE_CONST_FUNC;

/* Linear interpolation. */
OOINLINE float OOLerp(float v0, float v1, float fraction) INLINE_CONST_FUNC;


#ifdef __GNUC__
	OOINLINE uint32_t OORoundUpToPowerOf2(uint32_t value)
	{
		return 0x80000000 >> (__builtin_clz(value - 1) - 1);
	}
#else
	OOINLINE uint32_t OORoundUpToPowerOf2(uint32_t value)
	{
		value -= 1;
		value |= (value >> 1);
		value |= (value >> 2);
		value |= (value >> 4);
		value |= (value >> 8);
		value |= (value >> 16);
		return value + 1;
	}
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
