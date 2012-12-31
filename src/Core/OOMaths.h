/*

OOMaths.h

Mathematical framework for Oolite.

Provides utility routines for Vectors, Quaternions, rotation matrices, and
conversion to OpenGL transformation matrices.

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
#define INCLUDED_OOMATHS_h

#ifdef __cplusplus
extern "C" {
#endif
	
#ifndef OOMATHS_STANDALONE
#define OOMATHS_STANDALONE 0
#endif

#ifndef OOMATHS_OPENGL_INTEGRATION
#define OOMATHS_OPENGL_INTEGRATION !OOMATHS_STANDALONE
#endif

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#endif

#include "OOFunctionAttributes.h"
#include <tgmath.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdint.h>
#include <limits.h>
#include <assert.h>

#if OOMATHS_OPENGL_INTEGRATION
#include "OOOpenGL.h"
#endif


#if OOMATHS_OPENGL_INTEGRATION
typedef GLfloat OOScalar;
#else
typedef float OOScalar;
#endif


#ifndef M_PI
	#define	M_PI		3.14159265358979323846	/* pi */
#endif
#ifndef M_PI_2
	#define	M_PI_2		1.57079632679489661923	/* pi/2 */
#endif
#ifndef M_PI_4
	#define	M_PI_4		0.78539816339744830962	/* pi/4 */
#endif
#ifndef M_1_PI
	#define	M_1_PI		0.31830988618379067154	/* 1/pi */
#endif
#ifndef M_2_PI
	#define	M_2_PI		0.63661977236758134308	/* 2/pi */
#endif
#ifndef M_2_SQRTPI
	#define	M_2_SQRTPI	1.12837916709551257390	/* 2/sqrt(pi) */
#endif
#ifndef M_SQRT2
	#define	M_SQRT2		1.41421356237309504880	/* sqrt(2) */
#endif
#ifndef M_SQRT1_2
	#define	M_SQRT1_2	0.70710678118654752440	/* 1/sqrt(2) */
#endif


#if defined(__GNUC__) && !defined(__STRICT_ANSI__)
	#ifndef MIN
		#define MIN(A,B)	({ __typeof__(A) __a = (A); __typeof__(B) __b = (B); __a < __b ? __a : __b; })
	#endif
	#if !defined(MAX)
		#define MAX(A,B)	({ __typeof__(A) __a = (A); __typeof__(B) __b = (B); __a < __b ? __b : __a; })
	#endif
	#if !defined(ABS)
		#define ABS(A)		({ __typeof__(A) __a = (A); __a < 0 ? -__a : __a; })
	#endif
#else
	/* These definitions are unsafe in that the "winning" expression is evaluated twice. */
	#if !defined(MIN)
		#define MIN(A,B)	((A) < (B) ? (A) : (B))
	#endif
	#if !defined(MAX)
		#define MAX(A,B)	((A) > (B) ? (A) : (B))
	#endif
	#if !defined(ABS)
		#define ABS(A)		((A) < 0 ? (-(A)) : (A))
	#endif
#endif


#include "OOFastArithmetic.h"
#include "OOVector.h"
#include "OOQuaternion.h"
#include "OOMatrix.h"

#if !OOMATHS_STANDALONE
#include "OOVoxel.h"
#include "OOTriangle.h"
#include "OOBoundingBox.h"

#include "legacy_random.h"
#endif


#ifdef __cplusplus
}
#endif

#endif	/* INCLUDED_OOMATHS_h */
