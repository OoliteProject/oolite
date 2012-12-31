/*

OOQuaternion.h

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
	#error Do not include OOQuaternion.h directly; include OOMaths.h.
#else


typedef struct Quaternion
{
	OOScalar w;
	OOScalar x;
	OOScalar y;
	OOScalar z;
} Quaternion;


extern const Quaternion	kIdentityQuaternion;	// 1, 0, 0, 0
extern const Quaternion	kZeroQuaternion;		// 0, 0, 0, 0


/* Construct quaternion */
OOINLINE Quaternion make_quaternion(OOScalar qw, OOScalar qx, OOScalar qy, OOScalar qz) INLINE_CONST_FUNC;

/* Comparison of quaternions */
OOINLINE bool quaternion_equal(Quaternion a, Quaternion b) INLINE_CONST_FUNC;

/* Multiply quaternions */
Quaternion quaternion_multiply(Quaternion q1, Quaternion q2) CONST_FUNC;

/* Negation, or additive inverse -- negate all components */
OOINLINE Quaternion quaternion_negate(Quaternion q) INLINE_CONST_FUNC;

/* Conjugate, or spacial inverse -- negate x, y, z components */
OOINLINE Quaternion quaternion_conjugate(Quaternion q) INLINE_CONST_FUNC;

#if !OOMATHS_STANDALONE
/* Set quaternion to random unit quaternion */
void quaternion_set_random(Quaternion *quat) NONNULL_FUNC;
OOINLINE Quaternion OORandomQuaternion(void) ALWAYS_INLINE_FUNC;
#endif

/* Build quaternion representing a rotation around a given axis */
OOINLINE void quaternion_set_rotate_about_axis(Quaternion *quat, Vector axis, OOScalar angle) NONNULL_FUNC;

/* Inner product of two quaternions */
OOINLINE OOScalar quaternion_dot_product(Quaternion q1, Quaternion q2) CONST_FUNC;

/* Create basis vectors from a quaternion. */
Vector vector_forward_from_quaternion(Quaternion quat) CONST_FUNC;
Vector vector_up_from_quaternion(Quaternion quat) CONST_FUNC;
Vector vector_right_from_quaternion(Quaternion quat) CONST_FUNC;

void basis_vectors_from_quaternion(Quaternion quat, Vector *outRight, Vector *outUp, Vector *outForward);

/* produce a quaternion representing an angle between two vectors. Assumes the vectors are normalized. */
Quaternion quaternion_rotation_between(Vector v0, Vector v1) CONST_FUNC;

/* produce a quaternion representing an angle between two vectors with a maximum arc */
Quaternion quaternion_limited_rotation_between(Vector v0, Vector v1, float maxArc) CONST_FUNC;

/* Rotate a quaternion about a fixed axis. */
void quaternion_rotate_about_x(Quaternion *quat, OOScalar angle) NONNULL_FUNC;
void quaternion_rotate_about_y(Quaternion *quat, OOScalar angle) NONNULL_FUNC;
void quaternion_rotate_about_z(Quaternion *quat, OOScalar angle) NONNULL_FUNC;
void quaternion_rotate_about_axis(Quaternion *quat, Vector axis, OOScalar angle) NONNULL_FUNC;

/* Normalize quaternion */
OOINLINE void quaternion_normalize(Quaternion *quat) NONNULL_FUNC ALWAYS_INLINE_FUNC;

#if __OBJC__
NSString *QuaternionDescription(Quaternion quaternion);	// @"(w + xi + yj + zk)"
#endif


Vector quaternion_rotate_vector(Quaternion q, Vector vector) CONST_FUNC;



/*** Only inline definitions beyond this point ***/

OOINLINE Quaternion make_quaternion(OOScalar qw, OOScalar qx, OOScalar qy, OOScalar qz)
{
	Quaternion result;
	result.w = qw;
	result.x = qx;
	result.y = qy;
	result.z = qz;
	return result;
}


OOINLINE bool quaternion_equal(Quaternion a, Quaternion b)
{
	return a.w == b.w && a.x == b.x && a.y == b.y && a.z == b.z;
}


OOINLINE Quaternion quaternion_negate(Quaternion q)
{
	return make_quaternion(-q.w, -q.x, -q.y, -q.z);
}


OOINLINE Quaternion quaternion_conjugate(Quaternion q)
{
	return make_quaternion(q.w, -q.x, -q.y, -q.z);
}


OOINLINE void quaternion_set_rotate_about_axis(Quaternion *quat, Vector axis, OOScalar angle)
{
	OOScalar a = angle * 0.5f;
	OOScalar scale = sin(a);
	
	quat->w = cos(a);
	quat->x = axis.x * scale;
	quat->y = axis.y * scale;
	quat->z = axis.z * scale;
}


OOINLINE OOScalar quaternion_dot_product(Quaternion q1, Quaternion q2)
{
	return q1.w*q2.w + q1.x*q2.x + q1.y*q2.y + q1.z*q2.z;
}


OOINLINE void quaternion_normalize(Quaternion *quat)
{
	OOScalar	w = quat->w;
	OOScalar	x = quat->x;
	OOScalar	y = quat->y;
	OOScalar	z = quat->z;
	
	OOScalar	lv = 1.0f / sqrt(w*w + x*x + y*y + z*z);
	
	quat->w = lv * w;
	quat->x = lv * x;
	quat->y = lv * y;
	quat->z = lv * z;
}


#if !OOMATHS_STANDALONE
OOINLINE Quaternion OORandomQuaternion(void)
{
	Quaternion q;
	quaternion_set_random(&q);
	return q;
}
#endif

#endif	/* INCLUDED_OOMATHS_h */
