/*

OOVector.h

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
	#error Do not include OOVector.h directly; include OOMaths.h.
#else


#ifndef OOMATHS_EXTERNAL_VECTOR_TYPES

typedef struct Vector
{
	OOScalar x;
	OOScalar y;
	OOScalar z;
} Vector;


typedef struct Vector2D
{
	OOScalar x;
	OOScalar y;
} Vector2D;

#endif


extern const Vector		kZeroVector,		/* 0, 0, 0 */
						kBasisXVector,		/* 1, 0, 0 */
						kBasisYVector,		/* 0, 1, 0 */
						kBasisZVector;		/* 0, 0, 1 */


extern const Vector2D	kZeroVector2D,		/* 0, 0 */
						kBasisXVector2D,	/* 1, 0 */
						kBasisYVector2D;	/* 0, 1 */


/* Construct vector */
OOINLINE Vector make_vector(OOScalar vx, OOScalar vy, OOScalar vz) INLINE_CONST_FUNC;
OOINLINE Vector2D MakeVector2D(OOScalar vx, OOScalar vy) INLINE_CONST_FUNC;

#if !OOMATHS_STANDALONE
/* Generate random vectors. */
Vector OORandomUnitVector(void);
Vector OOVectorRandomSpatial(OOScalar maxLength);	// Random vector uniformly distributed in radius-maxLength sphere. (Longer vectors are more common.)
Vector OOVectorRandomRadial(OOScalar maxLength);		// Random vector with uniform distribution of direction and radius in radius-maxLength sphere. (Causes clustering at centre.)
#endif

/* Multiply vector by scalar (in place) */
OOINLINE void scale_vector(Vector *outVector, OOScalar factor) ALWAYS_INLINE_FUNC NONNULL_FUNC;

/* Multiply vector by scalar */
OOINLINE Vector vector_multiply_scalar(Vector v, OOScalar s) INLINE_CONST_FUNC;

/* Addition and subtraction of vectors */
OOINLINE Vector vector_add(Vector a, Vector b) INLINE_CONST_FUNC;
OOINLINE Vector vector_subtract(Vector a, Vector b) INLINE_CONST_FUNC;
#define vector_between(a, b) vector_subtract(b, a)
OOINLINE Vector vector_flip(Vector v) INLINE_CONST_FUNC;

/* Vector linear interpolation */
OOINLINE Vector OOVectorInterpolate(Vector a, Vector b, OOScalar where) INLINE_CONST_FUNC;
OOINLINE Vector OOVectorTowards(Vector a, Vector b, OOScalar where) INLINE_CONST_FUNC;

/* Comparison of vectors */
OOINLINE bool vector_equal(Vector a, Vector b) INLINE_CONST_FUNC;

/* Square of magnitude of vector */
OOINLINE OOScalar magnitude2(Vector vec) INLINE_CONST_FUNC;

/* Magnitude of vector */
OOINLINE OOScalar magnitude(Vector vec) INLINE_CONST_FUNC;

/* Normalize vector */
OOINLINE Vector vector_normal(Vector vec) INLINE_CONST_FUNC;

/* Normalize vector, returning fallback if zero vector. */
OOINLINE Vector vector_normal_or_fallback(Vector vec, Vector fallback) INLINE_CONST_FUNC;
OOINLINE Vector vector_normal_or_xbasis(Vector vec) INLINE_CONST_FUNC;
OOINLINE Vector vector_normal_or_ybasis(Vector vec) INLINE_CONST_FUNC;
OOINLINE Vector vector_normal_or_zbasis(Vector vec) INLINE_CONST_FUNC;

/* Square of distance between vectors */
OOINLINE OOScalar distance2(Vector v1, Vector v2) INLINE_CONST_FUNC;

/* Distance between vectors */
OOINLINE OOScalar distance(Vector v1, Vector v2) INLINE_CONST_FUNC;

/* Dot product */
OOINLINE OOScalar dot_product (Vector first, Vector second) INLINE_CONST_FUNC;

/* NORMALIZED cross product */
OOINLINE Vector cross_product(Vector first, Vector second) INLINE_CONST_FUNC;

/* General cross product */
OOINLINE Vector true_cross_product(Vector first, Vector second) CONST_FUNC;

/* Triple product */
OOINLINE OOScalar triple_product(Vector first, Vector second, Vector third) INLINE_CONST_FUNC;

/* Given three points on a surface, returns the normal to the surface. */
OOINLINE Vector normal_to_surface(Vector v1, Vector v2, Vector v3) CONST_FUNC;

#if __OBJC__
NSString *VectorDescription(Vector vector);	// @"(x, y, z)"
#endif

#if OOMATHS_OPENGL_INTEGRATION
/*	OpenGL conveniences. Need to be macros to work with OOMacroOpenGL. */
#define GLVertexOOVector(v) do { Vector v_ = v; glVertex3f(v_.x, v_.y, v_.z); } while (0)
#define GLTranslateOOVector(v) do { Vector v_ = v; OOGL(glTranslatef(v_.x, v_.y, v_.z)); } while (0)
#endif


/*** Only inline definitions beyond this point ***/

OOINLINE Vector make_vector (OOScalar vx, OOScalar vy, OOScalar vz)
{
	Vector result;
	result.x = vx;
	result.y = vy;
	result.z = vz;
	return result;
}


OOINLINE Vector2D MakeVector2D(OOScalar vx, OOScalar vy)
{
	Vector2D result;
	result.x = vx;
	result.y = vy;
	return result;
}


OOINLINE void scale_vector(Vector *vec, OOScalar factor)
{
	vec->x *= factor;
	vec->y *= factor;
	vec->z *= factor;
}


OOINLINE Vector vector_multiply_scalar(Vector v, OOScalar s)
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


OOINLINE Vector OOVectorInterpolate(Vector a, Vector b, OOScalar where)
{
	return make_vector(OOLerp(a.x, b.x, where),
					   OOLerp(a.y, b.y, where),
					   OOLerp(a.z, b.z, where));
}


OOINLINE Vector OOVectorTowards(Vector a, Vector b, OOScalar where)
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


OOINLINE bool vector_equal(Vector a, Vector b)
{
	return a.x == b.x && a.y == b.y && a.z == b.z;
}


OOINLINE OOScalar magnitude2(Vector vec)
{
	return vec.x * vec.x + vec.y * vec.y + vec.z * vec.z;
}


OOINLINE OOScalar magnitude(Vector vec)
{
	return sqrt(magnitude2(vec));
}


OOINLINE Vector vector_normal_or_fallback(Vector vec, Vector fallback)
{
	OOScalar mag2 = magnitude2(vec);
	if (EXPECT_NOT(mag2 == 0.0f))  return fallback;
	return vector_multiply_scalar(vec, 1.0f / sqrt(mag2));
}


OOINLINE Vector vector_normal_or_xbasis(Vector vec)
{
	return vector_normal_or_fallback(vec, kBasisXVector);
}


OOINLINE Vector vector_normal_or_ybasis(Vector vec)
{
	return vector_normal_or_fallback(vec, kBasisYVector);
}


OOINLINE Vector vector_normal_or_zbasis(Vector vec)
{
	return vector_normal_or_fallback(vec, kBasisZVector);
}


OOINLINE Vector vector_normal(Vector vec)
{
	return vector_normal_or_fallback(vec, kZeroVector);
}


OOINLINE OOScalar distance2(Vector v1, Vector v2)
{
	return magnitude2(vector_subtract(v1, v2));
}


OOINLINE OOScalar distance(Vector v1, Vector v2)
{
	return magnitude(vector_subtract(v1, v2));
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


OOINLINE OOScalar dot_product (Vector a, Vector b)
{
	return (a.x * b.x) + (a.y * b.y) + (a.z * b.z);	
}


OOINLINE OOScalar triple_product(Vector first, Vector second, Vector third)
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


#endif	/* INCLUDED_OOMATHS_h */
