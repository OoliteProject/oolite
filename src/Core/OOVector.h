/*

OOVector.h

Mathematical framework for Oolite.

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


#ifndef INCLUDED_OOMATHS_h
	#error Do not include OOVector.h directly; include OOMaths.h.
#else


typedef struct Vector
{
	GLfloat x;
	GLfloat y;
	GLfloat z;
} Vector;


extern const Vector		kZeroVector,		/* 0, 0, 0 */
						kBasisXVector,		/* 1, 0, 0 */
						kBasisYVector,		/* 0, 1, 0 */
						kBasisZVector;		/* 0, 0, 1 */


/* Construct vector */
OOINLINE Vector make_vector(GLfloat vx, GLfloat vy, GLfloat vz) INLINE_CONST_FUNC;

/* Multiply vector by scalar (in place) */
OOINLINE void scale_vector(Vector *outVector, GLfloat factor) ALWAYS_INLINE_FUNC NONNULL_FUNC;

/* Multiply vector by scalar */
OOINLINE Vector vector_multiply_scalar(Vector v, GLfloat s) INLINE_CONST_FUNC;

/* Addition and subtraction of vectors */
OOINLINE Vector vector_add(Vector a, Vector b) INLINE_CONST_FUNC;
OOINLINE Vector vector_subtract(Vector a, Vector b) INLINE_CONST_FUNC;
#define vector_between(a, b) vector_subtract(b, a)
OOINLINE Vector vector_flip(Vector v) INLINE_CONST_FUNC;

/* Vector linear interpolation */
OOINLINE Vector OOVectorInterpolate(Vector a, Vector b, GLfloat where) INLINE_CONST_FUNC;
OOINLINE Vector OOVectorTowards(Vector a, Vector b, GLfloat where) INLINE_CONST_FUNC;

/* Comparison of vectors */
OOINLINE GLboolean vector_equal(Vector a, Vector b) INLINE_CONST_FUNC;

/* Square of magnitude of vector */
OOINLINE GLfloat magnitude2(Vector vec) INLINE_CONST_FUNC;

/* Magnitude of vector */
OOINLINE GLfloat magnitude(Vector vec) INLINE_CONST_FUNC;
OOINLINE GLfloat fast_magnitude(Vector vec) INLINE_CONST_FUNC;

/* Normalize vector */
OOINLINE Vector vector_normal(Vector vec) INLINE_CONST_FUNC;
OOINLINE Vector fast_vector_normal(Vector vec) INLINE_CONST_FUNC;
OOINLINE Vector unit_vector(const Vector *vec) NONNULL_FUNC INLINE_CONST_FUNC;
/* Normalize vector, returning fallback if zero vector. */
OOINLINE Vector vector_normal_or_fallback(Vector vec, Vector fallback) INLINE_CONST_FUNC;
OOINLINE Vector fast_vector_normal_or_fallback(Vector vec, Vector fallback) INLINE_CONST_FUNC;

/* Square of distance between vectors */
OOINLINE GLfloat distance2(Vector v1, Vector v2) INLINE_CONST_FUNC;

/* Distance between vectors */
OOINLINE GLfloat distance(Vector v1, Vector v2) INLINE_CONST_FUNC;
OOINLINE GLfloat fast_distance(Vector v1, Vector v2) INLINE_CONST_FUNC;

/* Dot product */
OOINLINE GLfloat dot_product (Vector first, Vector second) INLINE_CONST_FUNC;

/* NORMALIZED cross product */
OOINLINE Vector cross_product(Vector first, Vector second) INLINE_CONST_FUNC;
OOINLINE Vector fast_cross_product(Vector first, Vector second) INLINE_CONST_FUNC;

/* General cross product */
OOINLINE Vector true_cross_product(Vector first, Vector second) CONST_FUNC;

/* Triple product */
OOINLINE GLfloat triple_product(Vector first, Vector second, Vector third) INLINE_CONST_FUNC;

/* Given three points on a surface, returns the normal to the surface. */
OOINLINE Vector normal_to_surface(Vector v1, Vector v2, Vector v3) CONST_FUNC;
OOINLINE Vector fast_normal_to_surface(Vector v1, Vector v2, Vector v3) CONST_FUNC;

#ifdef __OBJC__
NSString *VectorDescription(Vector vector);	// @"(x, y, z)"
#endif

/*	OpenGL conveniences. Need to be macros to work with OOMacroOpenGL. */
#define GLTranslateOOVector(v) do { Vector v_ = v; glTranslatef(v_.x, v_.y, v_.z); } while (0)



/* Internal */
void ReportNormalizeZeroVector(void);


/*** Only inline definitions beyond this point ***/

OOINLINE Vector make_vector (GLfloat vx, GLfloat vy, GLfloat vz)
{
	Vector result;
	result.x = vx;
	result.y = vy;
	result.z = vz;
	return result;
}


OOINLINE void scale_vector(Vector *vec, GLfloat factor)
{
	vec->x *= factor;
	vec->y *= factor;
	vec->z *= factor;
}


OOINLINE Vector vector_multiply_scalar(Vector v, GLfloat s)
{
	Vector r;
	r.x = v.x * s;
	r.y = v.y * s;
	r.z = v.z * s;
	return r;
}


OOINLINE Vector vector_add(Vector a, Vector b)
{
	Vector r;
	r.x = a.x + b.x;
	r.y = a.y + b.y;
	r.z = a.z + b.z;
	return r;
}


OOINLINE Vector OOVectorInterpolate(Vector a, Vector b, GLfloat where)
{
	GLfloat invWhere = 1.0f - where;
	return make_vector(a.x * invWhere + b.x * where,
					   a.y * invWhere + b.y * where,
					   a.z * invWhere + b.z * where);
}


OOINLINE Vector OOVectorTowards(Vector a, Vector b, GLfloat where)
{
	return make_vector(a.x + b.x * where,
					   a.y + b.y * where,
					   a.z + b.z * where);
}


OOINLINE Vector vector_subtract(Vector a, Vector b)
{
	Vector r;
	r.x = a.x - b.x;
	r.y = a.y - b.y;
	r.z = a.z - b.z;
	return r;
}


OOINLINE Vector vector_flip(Vector v)
{
	return vector_subtract(kZeroVector, v);
}


OOINLINE GLboolean vector_equal(Vector a, Vector b)
{
	return a.x == b.x && a.y == b.y && a.z == b.z;
}


OOINLINE GLfloat magnitude2(Vector vec)
{
	return vec.x * vec.x + vec.y * vec.y + vec.z * vec.z;
}


OOINLINE GLfloat magnitude(Vector vec)
{
	return sqrtf(magnitude2(vec));
}


OOINLINE GLfloat fast_magnitude(Vector vec)
{
	#if FASTINVSQRT_ENABLED || OO_PPC
		GLfloat mag2 = magnitude2(vec);
		return mag2 * OOFastInvSqrtf(mag2);	/* x = sqrt(x) * sqrt(x); x * 1/sqrt(x) = (sqrt(x) * sqrt(x))/sqrt(x) = sqrt(x). */
	#else
		return magnitude(vec);
	#endif
}


OOINLINE Vector vector_normal_or_fallback(Vector vec, Vector fallback)
{
	GLfloat mag2 = magnitude2(vec);
	if (EXPECT_NOT(mag2 == 0))  return fallback;
	return vector_multiply_scalar(vec, OOInvSqrtf(mag2));
}


OOINLINE Vector vector_normal(Vector vec)
{
	return vector_normal_or_fallback(vec, kZeroVector);
}


OOINLINE Vector fast_vector_normal_or_fallback(Vector vec, Vector fallback)
{
	GLfloat mag2 = magnitude2(vec);
	if (EXPECT_NOT(mag2 == 0))  return fallback;
	return vector_multiply_scalar(vec, OOFastInvSqrtf(mag2));
}


OOINLINE Vector fast_vector_normal(Vector vec)
{
	return fast_vector_normal_or_fallback(vec, kZeroVector);
}


OOINLINE Vector unit_vector(const Vector *vec)
{
	return vector_normal(*vec);
}


OOINLINE GLfloat distance2(Vector v1, Vector v2)
{
	return magnitude2(vector_subtract(v1, v2));
}


OOINLINE GLfloat distance(Vector v1, Vector v2)
{
	return magnitude(vector_subtract(v1, v2));
}


OOINLINE GLfloat fast_distance(Vector v1, Vector v2)
{
	return fast_magnitude(vector_subtract(v1, v2));
}


OOINLINE Vector true_cross_product(Vector first, Vector second)
{
	Vector result;
	result.x = (first.y * second.z) - (first.z * second.y);
	result.y = (first.z * second.x) - (first.x * second.z);
	result.z = (first.x * second.y) - (first.y * second.x);
	return result;
}


OOINLINE Vector cross_product(Vector first, Vector second)
{
	return vector_normal(true_cross_product(first, second));
}


OOINLINE Vector fast_cross_product(Vector first, Vector second)
{
	return fast_vector_normal(true_cross_product(first, second));
}


OOINLINE GLfloat dot_product (Vector a, Vector b)
{
	return (a.x * b.x) + (a.y * b.y) + (a.z * b.z);	
}


OOINLINE GLfloat triple_product(Vector first, Vector second, Vector third)
{
	return dot_product(first, true_cross_product(second, third));
}


OOINLINE Vector normal_to_surface(Vector v1, Vector v2, Vector v3)
{
	Vector d0, d1;
	d0 = vector_subtract(v2, v1);
	d1 = vector_subtract(v3, v2);
	return cross_product(d0, d1);
}


OOINLINE Vector fast_normal_to_surface(Vector v1, Vector v2, Vector v3)
{
	Vector d0, d1;
	d0 = vector_subtract(v2, v1);
	d1 = vector_subtract(v3, v2);
	return fast_cross_product(d0, d1);
}


#endif	/* INCLUDED_OOMATHS_h */
