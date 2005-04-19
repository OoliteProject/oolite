/*

Provides utility routines for Vectors, rotation matrices, and conversion to OpenGL transformation matrices
 
 *
 *  Oolite
 *
 *  Created by Giles Williams on Sat Apr 03 2004.
 *  Copyright (c) 2004 for aegidian.org. All rights reserved.
 *

Copyright (c) 2004, Giles C Williams
All rights reserved.

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

¥	to copy, distribute, display, and perform the work
¥	to make derivative works

Under the following conditions:

¥	Attribution. You must give the original author credit.

¥	Noncommercial. You may not use this work for commercial purposes.

¥	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

#include <stdlib.h>
#include <math.h>
#ifndef GNUSTEP
#include <ppc_intrinsics.h>
#endif

#include "vector.h"
#include "legacy_random.h"

#define PI	3.1415926535897932384626433832795

static Matrix start_matrix =
{
	{1.0, 0.0, 0.0},
	{0.0, 1.0, 0.0},
	{0.0, 0.0, 1.0}
};

//
// Multiply first matrix by second matrix.
// Put result into first matrix.
//
void mult_matrix (struct vector *first, struct vector *second)
{
	int i;
	Matrix rv;

	for (i = 0; i < 3; i++)
	{

		rv[i].x =	(first[0].x * second[i].x) +
				 	(first[1].x * second[i].y) +
					(first[2].x * second[i].z);

		rv[i].y =	(first[0].y * second[i].x) +
					(first[1].y * second[i].y) +
					(first[2].y * second[i].z);

		rv[i].z =	(first[0].z * second[i].x) +
					(first[1].z * second[i].y) +
					(first[2].z * second[i].z);
	}

	for (i = 0; i < 3; i++)
		first[i] = rv[i];
}

//
// Multiply vector by matrix.
//
void mult_vector (struct vector *vec, struct vector *mat)
{
	GLfloat x;
	GLfloat y;
	GLfloat z;

	x = (vec->x * mat[0].x) +
		(vec->y * mat[0].y) +
		(vec->z * mat[0].z);

	y = (vec->x * mat[1].x) +
		(vec->y * mat[1].y) +
		(vec->z * mat[1].z);

	z = (vec->x * mat[2].x) +
		(vec->y * mat[2].y) +
		(vec->z * mat[2].z);

	vec->x = x;
	vec->y = y;
	vec->z = z;
}

//
// Multiply vector by gl_matrix.
//
void mult_vector_gl_matrix (struct vector *vec, GLfloat *glmat)
{
	GLfloat x;
	GLfloat y;
	GLfloat z;
	GLfloat w = 1.0;

	x = (vec->x * glmat[0]) +
		(vec->y * glmat[4]) +
		(vec->z * glmat[8]) +
		(1.0 * glmat[12]);

	y = (vec->x * glmat[1]) +
		(vec->y * glmat[5]) +
		(vec->z * glmat[9]) +
		(1.0 * glmat[13]);

	z = (vec->x * glmat[2]) +
		(vec->y * glmat[6]) +
		(vec->z * glmat[10]) +
		(1.0 * glmat[13]);
	
	w = (vec->x * glmat[3]) +
		(vec->y * glmat[7]) +
		(vec->z * glmat[11]) +
		(1.0 * glmat[15]);
	
	vec->x = x/w;
	vec->y = y/w;
	vec->z = z/w;
}

// returns the square of the magnitude of the vector
//
double magnitude2 (Vector vec)
{
	return vec.x * vec.x + vec.y * vec.y + vec.z * vec.z;
}

// returns the square of the distance between two points
//
double distance2 (Vector v1, Vector v2)
{
	return (v1.x - v2.x) * (v1.x - v2.x) + (v1.y - v2.y) * (v1.y - v2.y) + (v1.z - v2.z) * (v1.z - v2.z);
}

// Calculate the dot product of two vectors sharing a common point.
// Returns the cosine of the angle between the two vectors.
//
GLfloat dot_product (Vector first, Vector second)
{
	return (first.x * second.x) + (first.y * second.y) + (first.z * second.z);	
}


Vector cross_product (Vector first, Vector second)
{
	Vector result;
	GLfloat	det, mag2;
	result.x = (first.y * second.z) - (first.z * second.y);
	result.y = (first.z * second.x) - (first.x * second.z);
	result.z = (first.x * second.y) - (first.y * second.x);
	mag2 = sqrt(result.x * result.x + result.y * result.y + result.z * result.z);
	if (mag2 > 0.0)
	{
		det = 1.0 / sqrt(result.x * result.x + result.y * result.y + result.z * result.z);
		result.x *= det;	result.y *= det;	result.z *= det;
		return result;
	}
	else
	{
		result.x = result.y = result.z = 0.0;
		return result;
	}
}


Vector normal_to_surface (Vector v1, Vector v2, Vector v3)
{
	Vector d0, d1;
	d0.x = v2.x - v1.x;	d0.y = v2.y - v1.y;	d0.z = v2.z - v1.z;	
	d1.x = v3.x - v2.x;	d1.y = v3.y - v2.y;	d1.z = v3.z - v2.z;	
	return cross_product(d0,d1);	
}

// make a vector
//
struct vector make_vector (GLfloat vx, GLfloat vy, GLfloat vz)
{
	Vector result;
	result.x = vx;
	result.y = vy;
	result.z = vz;
	return result;
}
	

// Convert a vector into a vector of unit (1) length.
//
//Vector unit_vector (struct vector *vec)
//{
//	GLfloat lx,ly,lz;
//	float len,isqrt,temp1,temp2;
//	Vector res;
//
//	lx = vec->x;
//	ly = vec->y;
//	lz = vec->z;
//
//	len = lx * lx + ly * ly + lz * lz;
//	
//	// Fast estimate
//	isqrt = __frsqrte (len);
//	
//	// Newton-Rhapson
//	temp1 = len - 0.5f;
//	temp2 = isqrt * isqrt;
//	temp1 *= isqrt;
//	isqrt *= (float)(3.0/2.0);
//	len = isqrt + temp1 * temp2;
//
//	res.x = lx * len;
//	res.y = ly * len;
//	res.z = lz * len;
//
//	return res;
//}
Vector unit_vector (struct vector *vec)
{
	GLfloat lx,ly,lz;
	GLfloat det;
	Vector res;

	lx = vec->x;
	ly = vec->y;
	lz = vec->z;

	det = 1.0 / sqrt (lx * lx + ly * ly + lz * lz);

	res.x = lx * det;
	res.y = ly * det;
	res.z = lz * det;

	return res;
}

// set the unit matrix
//
void set_matrix_identity (struct vector *mat)
{
	int i;

	for (i = 0; i < 3; i++)
            mat[i] = start_matrix[i];
}


// orthonormalisation
//
void tidy_matrix (struct vector *mat)
{
	mat[2] = unit_vector (&mat[2]);

	if ((mat[2].x > -1) && (mat[2].x < 1))
	{
		if ((mat[2].y > -1) && (mat[2].y < 1))
		{
			mat[1].z = -(mat[2].x * mat[1].x + mat[2].y * mat[1].y) / mat[2].z;
		}
		else
		{
			mat[1].y = -(mat[2].x * mat[1].x + mat[2].z * mat[1].z) / mat[2].y;
		}
	}
	else
	{
		mat[1].x = -(mat[2].y * mat[1].y + mat[2].z * mat[1].z) / mat[2].x;
	}
	
	mat[1] = unit_vector (&mat[1]);
	
	mat[0].x = mat[1].y * mat[2].z - mat[1].z * mat[2].y;
	mat[0].y = mat[1].z * mat[2].x - mat[1].x * mat[2].z;
	mat[0].z = mat[1].x * mat[2].y - mat[1].y * mat[2].x;
}


// produce a GL_matrix from a rotation matrix
//
void	matrix_into_gl_matrix(struct vector *mat, GLfloat *glmat)
{
    glmat[0] = mat[0].x;	glmat[4] = mat[0].y;	glmat[8] = mat[0].z;	glmat[3] = 0.0;
    glmat[1] = mat[1].x;	glmat[5] = mat[1].y;	glmat[9] = mat[1].z;	glmat[7] = 0.0;
    glmat[2] = mat[2].x;	glmat[6] = mat[2].y;	glmat[10] = mat[2].z;	glmat[11] = 0.0;
    glmat[12] = 0.0;		glmat[13] = 0.0;		glmat[14] = 0.0;		glmat[15] = 1.0;
}

// turn forward, up and right vectors into a gl matrix
//
void	vectors_into_gl_matrix(Vector vf, Vector vr, Vector vu, GLfloat *glmat)
{
    glmat[0] = vr.x;		glmat[4] = vu.x;	glmat[8] = vf.x;	glmat[3] = 0.0;
    glmat[1] = vr.y;		glmat[5] = vu.y;	glmat[9] = vf.y;	glmat[7] = 0.0;
    glmat[2] = vr.z;		glmat[6] = vu.z;	glmat[10] = vf.z;	glmat[11] = 0.0;
    glmat[12] = 0.0;		glmat[13] = 0.0;	glmat[14] = 0.0;	glmat[15] = 1.0;
}

void	gl_matrix_into_matrix(GLfloat *glmat, struct vector *mat)
{
    mat[0].x = glmat[0];	mat[0].y = glmat[4];	mat[0].z = glmat[8];
	mat[1].x = glmat[1];	mat[1].y = glmat[5];	mat[1].z = glmat[9];
	mat[2].x = glmat[2];	mat[2].y = glmat[6];	mat[2].z = glmat[10];
}

void	bounding_box_add_vector(struct boundingBox *box, Vector vec)
{
	if (vec.x < box->min_x)  box->min_x = vec.x;
	if (vec.x > box->max_x)  box->max_x = vec.x;
	if (vec.y < box->min_y)  box->min_y = vec.y;
	if (vec.y > box->max_y)  box->max_y = vec.y;
	if (vec.z < box->min_z)  box->min_z = vec.z;
	if (vec.z > box->max_z)  box->max_z = vec.z;
}

void	bounding_box_add_xyz(struct boundingBox *box, GLfloat x, GLfloat y, GLfloat z)
{
	if (x < box->min_x)  box->min_x = x;
	if (x > box->max_x)  box->max_x = x;
	if (y < box->min_y)  box->min_y = y;
	if (y > box->max_y)  box->max_y = y;
	if (z < box->min_z)  box->min_z = z;
	if (z > box->max_z)  box->max_z = z;
}

void	bounding_box_reset(struct boundingBox *box)
{
	box->min_x = 0.0;
	box->max_x = 0.0;
	box->min_y = 0.0;
	box->max_y = 0.0;
	box->min_z = 0.0;
	box->max_z = 0.0;
}

void	bounding_box_reset_to_vector(struct boundingBox *box, Vector vec)
{
	box->min_x = vec.x;
	box->max_x = vec.x;
	box->min_y = vec.y;
	box->max_y = vec.y;
	box->min_z = vec.z;
	box->max_z = vec.z;
}

/*

        QUATERNION MATH ROUTINES
        

*/

// product of two quaternions
//
Quaternion	quaternion_multiply(Quaternion q1, Quaternion q2)
{
    Quaternion	result;
    result.w = q1.w * q2.w - q2.x * q1.x - q1.y * q2.y - q1.z * q2.z;
    result.x = q1.w * q2.x + q1.x * q2.w + q1.y * q2.z - q1.z * q2.y;
    result.y = q1.w * q2.y + q1.y * q2.w + q1.z * q2.x - q1.x * q2.z;
    result.z = q1.w * q2.z + q1.z * q2.w + q1.x * q2.y - q1.y * q2.x;
    return result;
}
// set identity
//
void	quaternion_set_identity(struct quaternion *quat)
{
    quat->w = 1.0;
    quat->x = 0.0;
    quat->y = 0.0;
    quat->z = 0.0;
}
// set random
//
void	quaternion_set_random(struct quaternion *quat)
{
    quat->w = (ranrot_rand() & 1023) - 512.0;  // -512 to +512;
    quat->x = (ranrot_rand() & 1023) - 512.0;  // -512 to +512
    quat->y = (ranrot_rand() & 1023) - 512.0;  // -512 to +512
    quat->z = (ranrot_rand() & 1023) - 512.0;  // -512 to +512
	quaternion_normalise(quat);
}
// set angle a about axis v
//
void	quaternion_set_rotate_about_axis(struct quaternion *quat, Vector axis, GLfloat angle)
{
    GLfloat a = angle * 0.5;
    GLfloat scale = sin(a);
    
    quat->w = cos(a);
    quat->x = axis.x * scale;
    quat->y = axis.y * scale;
    quat->z = axis.z * scale;
}
// dot product of two vectors
//
GLfloat	quaternion_dot_product(Quaternion q1, Quaternion q2)
{
    return	(q1.w*q2.w + q1.x*q2.x + q1.y*q2.y + q1.z*q2.z);
}
// produce a GL_matrix from a quaternion
//
void	quaternion_into_gl_matrix(Quaternion quat, GLfloat *glmat)
{
    GLfloat	w, wz, wy, wx;
    GLfloat	x, xz, xy, xx;
    GLfloat	y, yz, yy;
    GLfloat	z, zz;
    
    w = quat.w;
    z = quat.z;
    y = quat.y;
    x = quat.x;
    
    xx = 2.0 * x; yy = 2.0 * y; zz = 2.0 * z;
    wx = w * xx; wy = w * yy; wz = w * zz;
    xx = x * xx; xy = x * yy; xz = x * zz;
    yy = y * yy; yz = y * zz;
    zz = z * zz;

    glmat[0]	= 1.0 - yy- zz;	glmat[4]	= xy + wz;			glmat[8]	= xz - wy;			glmat[12] = 0.0;
    glmat[1]	= xy - wz;		glmat[5]	= 1.0 - xx - zz;	glmat[9]	= yz + wx;			glmat[13] = 0.0;
    glmat[2]	= xz + wy;		glmat[6]	= yz - wx;			glmat[10]	= 1.0 - xx - yy;	glmat[14] = 0.0;
    glmat[3]	= 0.0;			glmat[7]	= 0.0;				glmat[11]	= 0.0;				glmat[15] = 1.0;

}
// produce a right vector from a quaternion
//
Vector	vector_right_from_quaternion(Quaternion quat)
{
    GLfloat	w, wz, wy, wx;
    GLfloat	x, xz, xy, xx;
    GLfloat	y, yz, yy;
    GLfloat	z, zz;
    Vector res;
	
    w = quat.w;
    z = quat.z;
    y = quat.y;
    x = quat.x;
    
    xx = 2.0 * x; yy = 2.0 * y; zz = 2.0 * z;
    wx = w * xx; wy = w * yy; wz = w * zz;
    xx = x * xx; xy = x * yy; xz = x * zz;
    yy = y * yy; yz = y * zz;
    zz = z * zz;

    res.x	= 1.0 - yy - zz;	res.y	= xy - wz;			res.z	= xz + wy;
	
	return unit_vector(&res);
}
// produce an up vector from a quaternion
//
Vector	vector_up_from_quaternion(Quaternion quat)
{
    GLfloat	w, wz, wy, wx;
    GLfloat	x, xz, xy, xx;
    GLfloat	y, yz, yy;
    GLfloat	z, zz;
    Vector res;
	
    w = quat.w;
    z = quat.z;
    y = quat.y;
    x = quat.x;
    
    xx = 2.0 * x; yy = 2.0 * y; zz = 2.0 * z;
    wx = w * xx; wy = w * yy; wz = w * zz;
    xx = x * xx; xy = x * yy; xz = x * zz;
    yy = y * yy; yz = y * zz;
    zz = z * zz;

    res.x	= xy + wz;	res.y	= 1.0 - xx - zz;			res.z	= yz - wx;
	
	return unit_vector(&res);
}
// produce a forward vector from a quaternion
//
Vector	vector_forward_from_quaternion(Quaternion quat)
{
    GLfloat	w, wz, wy, wx;
    GLfloat	x, xz, xy, xx;
    GLfloat	y, yz, yy;
    GLfloat	z, zz;
    Vector res;
	
    w = quat.w;
    z = quat.z;
    y = quat.y;
    x = quat.x;
    
    xx = 2.0 * x; yy = 2.0 * y; zz = 2.0 * z;
    wx = w * xx; wy = w * yy; wz = w * zz;
    xx = x * xx; xy = x * yy; xz = x * zz;
    yy = y * yy; yz = y * zz;
    zz = z * zz;

    res.x	= xz - wy;	res.y	= yz + wx;			res.z	= 1.0 - xx - yy;
	
	return unit_vector(&res);
}

// produce a quaternion representing an angle between two vectors
//
Quaternion	quaternion_rotation_between(Vector v0, Vector v1)	// vectors both normalised
{
	Quaternion q;
	quaternion_set_identity(&q);
	Vector xp = cross_product( v0, v1);
	double d = dot_product( v0, v1);
//	double s = sqrt((1.0 + d) * 2.0);
//	q.x = xp.x / s;
//	q.y = xp.y / s;
//	q.z = xp.z / s;
//	q.w = s / 2.0;
	if (d > 0.999)
		return q;
	quaternion_rotate_about_axis( &q, xp, acos(d));
	return q;
}

// rotate about fixed axes
//
void	quaternion_rotate_about_x(struct quaternion *quat, GLfloat angle)
{
    Quaternion result;
    GLfloat a = angle * 0.5;
    GLfloat w = cos(a);
    GLfloat scale = sin(a);

    result.w = quat->w * w - quat->x * scale;
    result.x = quat->w * scale + quat->x * w;
    result.y = quat->y * w + quat->z * scale;
    result.z = quat->z * w - quat->y * scale;
    
    quat->w = result.w;
    quat->x = result.x;
    quat->y = result.y;
    quat->z = result.z;
}
void	quaternion_rotate_about_y(struct quaternion *quat, GLfloat angle)
{
    Quaternion result;
    GLfloat a = angle * 0.5;
    GLfloat w = cos(a);
    GLfloat scale = sin(a);

    result.w = quat->w * w - quat->y * scale;
    result.x = quat->x * w - quat->z * scale;
    result.y = quat->w * scale + quat->y * w;
    result.z = quat->z * w + quat->x * scale;
    
    quat->w = result.w;
    quat->x = result.x;
    quat->y = result.y;
    quat->z = result.z;
}
void	quaternion_rotate_about_z(struct quaternion *quat, GLfloat angle)
{
    Quaternion result;
    GLfloat a = angle * 0.5;
    GLfloat w = cos(a);
    GLfloat scale = sin(a);
    
    result.w = quat->w * w - quat->z * scale;
    result.x = quat->x * w + quat->y * scale;
    result.y = quat->y * w - quat->x * scale;
    result.z = quat->w * scale + quat->z * w;
    
    quat->w = result.w;
    quat->x = result.x;
    quat->y = result.y;
    quat->z = result.z;
}
void	quaternion_rotate_about_axis(struct quaternion *quat, Vector axis, GLfloat angle)
{
    Quaternion q2, result;
    GLfloat a = angle * 0.5;
    GLfloat w = cos(a);
    GLfloat scale = sin(a);
    
	//printf("Axis %.1f, %.1f, %.1f : ", axis.x, axis.y, axis.z);
	
    q2.w = w;
    q2.x = axis.x * scale;
    q2.y = axis.y * scale;
    q2.z = axis.z * scale;

	//printf("Quat input %.1f, %.1f, %.1f, %.1f : ", quat->w, quat->x, quat->y, quat->z); // input is OKAY
	
	//printf("Quat multiplier %.1f, %.1f, %.1f, %.1f : ", q2.w, q2.x, q2.y, q2.z);
	    
    result.w = quat->w * q2.w - q2.x * quat->x - quat->y * q2.y - quat->z * q2.z;
    result.x = quat->w * q2.x + quat->x * q2.w + quat->y * q2.z - quat->z * q2.y;
    result.y = quat->w * q2.y + quat->y * q2.w + quat->z * q2.x - quat->x * q2.z;
    result.z = quat->w * q2.z + quat->z * q2.w + quat->x * q2.y - quat->y * q2.x;
	
	//printf("Quat result %.1f, %.1f, %.1f, %.1f\n", result.w, result.x, result.y, result.z);
	
    quat->w = result.w;
    quat->x = result.x;
    quat->y = result.y;
    quat->z = result.z;
}
//
// normalise
//
void	quaternion_normalise(struct quaternion *quat)
{
    GLfloat	w = quat->w;
    GLfloat	x = quat->x;
    GLfloat	y = quat->y;
    GLfloat	z = quat->z;
    GLfloat	lv = 1.0 / sqrt(w*w + x*x + y*y + z*z);
    
    quat->w = lv * w;
    quat->x = lv * x;
    quat->y = lv * y;
    quat->z = lv * z;
}
