/*

OOQuaternion.h

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
	#error Do not include OOQuaternion.h directly; include OOMaths.h.
#else


typedef struct Quaternion
{
	GLfloat w;
	GLfloat x;
	GLfloat y;
	GLfloat z;
} Quaternion;


extern const Quaternion	kIdentityQuaternion;	// 1, 0, 0, 0


/* Construct quaternion */
OOINLINE Quaternion make_quaternion(GLfloat qw, GLfloat qx, GLfloat qy, GLfloat qz) INLINE_CONST_FUNC;

/* Comparison of quaternions */
OOINLINE GLboolean quaternion_equal(Quaternion a, Quaternion b) INLINE_CONST_FUNC;

/* Multiply quaternions */
Quaternion quaternion_multiply(Quaternion q1, Quaternion q2) CONST_FUNC;

/* Obsolete function equivalent to *quat = kIdentityQuaternion */
OOINLINE void quaternion_set_identity(Quaternion *quat) ALWAYS_INLINE_FUNC NONNULL_FUNC DEPRECATED_FUNC;

/* Set quaternion to random unit quaternion */
void quaternion_set_random(Quaternion *quat) NONNULL_FUNC;

/* Build quaternion representing a rotation around a given axis */
OOINLINE void quaternion_set_rotate_about_axis(Quaternion *quat, Vector axis, GLfloat angle) NONNULL_FUNC;

/* Inner product of two quaternions */
OOINLINE GLfloat quaternion_dot_product(Quaternion q1, Quaternion q2) CONST_FUNC;

/* Create a rotation matrix from a quaternion. */
void quaternion_into_gl_matrix(Quaternion quat, GLfloat *glmat) NONNULL_FUNC;

/* Create basis vectors from a quaternion. */
Vector vector_forward_from_quaternion(Quaternion quat) CONST_FUNC;
Vector vector_up_from_quaternion(Quaternion quat) CONST_FUNC;
Vector vector_right_from_quaternion(Quaternion quat) CONST_FUNC;

/* produce a quaternion representing an angle between two vectors. Assumes the vectors are normalized. */
Quaternion quaternion_rotation_between(Vector v0, Vector v1) CONST_FUNC;

/* produce a quaternion representing an angle between two vectors with a maximum arc */
Quaternion quaternion_limited_rotation_between(Vector v0, Vector v1, float maxArc) CONST_FUNC;

/* Rotate a quaternion about a fixed axis. */
void quaternion_rotate_about_x(Quaternion *quat, GLfloat angle) NONNULL_FUNC;
void quaternion_rotate_about_y(Quaternion *quat, GLfloat angle) NONNULL_FUNC;
void quaternion_rotate_about_z(Quaternion *quat, GLfloat angle) NONNULL_FUNC;
void quaternion_rotate_about_axis(Quaternion *quat, Vector axis, GLfloat angle) NONNULL_FUNC;

/* Normalize quaternion */
OOINLINE void quaternion_normalize(Quaternion *quat) NONNULL_FUNC ALWAYS_INLINE_FUNC;
OOINLINE void fast_quaternion_normalize(Quaternion *quat) NONNULL_FUNC ALWAYS_INLINE_FUNC;
OOINLINE void quaternion_normalise(Quaternion *quat) NONNULL_FUNC ALWAYS_INLINE_FUNC DEPRECATED_FUNC;

#ifdef __OBJC__
NSString *QuaternionDescription(Quaternion quaternion);	// @"(w + xi + yj + zk)"
#endif



/*** Only inline definitions beyond this point ***/

OOINLINE Quaternion make_quaternion(GLfloat qw, GLfloat qx, GLfloat qy, GLfloat qz)
{
	Quaternion result;
	result.w = qw;
	result.x = qx;
	result.y = qy;
	result.z = qz;
	return result;
}


OOINLINE GLboolean quaternion_equal(Quaternion a, Quaternion b)
{
	return a.w == b.w && a.x == b.x && a.y == b.y && a.z == b.z;
}


OOINLINE void quaternion_set_identity(Quaternion *quat)
{
	*quat = kIdentityQuaternion;
}


OOINLINE void quaternion_set_rotate_about_axis(Quaternion *quat, Vector axis, GLfloat angle)
{
    GLfloat a = angle * 0.5f;
    GLfloat scale = sinf(a);
    
    quat->w = cosf(a);
    quat->x = axis.x * scale;
    quat->y = axis.y * scale;
    quat->z = axis.z * scale;
}


OOINLINE GLfloat quaternion_dot_product(Quaternion q1, Quaternion q2)
{
    return q1.w*q2.w + q1.x*q2.x + q1.y*q2.y + q1.z*q2.z;
}


OOINLINE void quaternion_normalize(Quaternion *quat)
{
    GLfloat	w = quat->w;
    GLfloat	x = quat->x;
    GLfloat	y = quat->y;
    GLfloat	z = quat->z;
	
    GLfloat	lv = OOInvSqrtf(w*w + x*x + y*y + z*z);
	
    quat->w = lv * w;
    quat->x = lv * x;
    quat->y = lv * y;
    quat->z = lv * z;
}


OOINLINE void quaternion_normalise(Quaternion *quat)
{
	quaternion_normalize(quat);
}


OOINLINE void fast_quaternion_normalize(Quaternion *quat)
{
    GLfloat	w = quat->w;
    GLfloat	x = quat->x;
    GLfloat	y = quat->y;
    GLfloat	z = quat->z;
	
    GLfloat	lv = OOFastInvSqrtf(w*w + x*x + y*y + z*z);
	
    quat->w = lv * w;
    quat->x = lv * x;
    quat->y = lv * y;
    quat->z = lv * z;
}


#endif	/* INCLUDED_OOMATHS_h */
