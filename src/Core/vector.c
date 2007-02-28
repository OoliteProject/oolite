/*

vector.c

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

#include <stdlib.h>
#include <stdio.h>
#include <math.h>

#include "vector.h"
#include "legacy_random.h"

#define PI	3.1415926535897932384626433832795

//static Vector	zero_vector = { 0.0f, 0.0f, 0.0f };

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
// Multiply vector by scalar
//
void	scale_vector (struct vector *vec, GLfloat factor)
{
	vec->x *= factor;
	vec->y *= factor;
	vec->z *= factor;
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

//	NOTE IMPORTANT
//	this cross product routine returns the UNIT vector cross product
//
Vector cross_product (Vector first, Vector second)
{
	Vector result;
	GLfloat	det, mag2;
	result.x = (first.y * second.z) - (first.z * second.y);
	result.y = (first.z * second.x) - (first.x * second.z);
	result.z = (first.x * second.y) - (first.y * second.x);
	mag2 = result.x * result.x + result.y * result.y + result.z * result.z;
	if (mag2 > 0.0)
	{
#ifndef WIN32
		det = FastInvSqrt(mag2);
#else
		det = 1.0 / sqrt (mag2);
#endif
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


float FastInvSqrt(float x)
{
	float xhalf = 0.5f * x;
	int i = *(int*)&x;
	i = 0x5f3759df - (i>>1);
	x = *(float*)&i;
	x = x * (1.5f - xhalf * x * x);
	return x;
}

// Convert a vector into a vector of unit (1) length.
//
Vector unit_vector (struct vector *vec)
{
	GLfloat lx,ly,lz;
	GLfloat det;
	Vector res;

	lx = vec->x;
	ly = vec->y;
	lz = vec->z;

	if (lx || ly || lz)
#ifndef WIN32
		det = FastInvSqrt(lx * lx + ly * ly + lz * lz);
#else
		det = 1.0 / sqrt (lx * lx + ly * ly + lz * lz);
#endif
	else
	{
		det = 1.0;
		printf("***** ERROR - attempt to normalise vector ( %.5f, %.5f, %.5f)\n", lx, ly, lz);
		//	catches div-by-zero problem
	}

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
	if (vec.x < box->min.x)  box->min.x = vec.x;
	if (vec.x > box->max.x)  box->max.x = vec.x;
	if (vec.y < box->min.y)  box->min.y = vec.y;
	if (vec.y > box->max.y)  box->max.y = vec.y;
	if (vec.z < box->min.z)  box->min.z = vec.z;
	if (vec.z > box->max.z)  box->max.z = vec.z;
}

void	bounding_box_add_xyz(struct boundingBox *box, GLfloat x, GLfloat y, GLfloat z)
{
	if (x < box->min.x)  box->min.x = x;
	if (x > box->max.x)  box->max.x = x;
	if (y < box->min.y)  box->min.y = y;
	if (y > box->max.y)  box->max.y = y;
	if (z < box->min.z)  box->min.z = z;
	if (z > box->max.z)  box->max.z = z;
}

void	bounding_box_reset(struct boundingBox *box)
{
	box->min.x = 0.0;
	box->max.x = 0.0;
	box->min.y = 0.0;
	box->max.y = 0.0;
	box->min.z = 0.0;
	box->max.z = 0.0;
}

void	bounding_box_reset_to_vector(struct boundingBox *box, Vector vec)
{
	box->min.x = vec.x;
	box->max.x = vec.x;
	box->min.y = vec.y;
	box->max.y = vec.y;
	box->min.z = vec.z;
	box->max.z = vec.z;
}

GLfloat	bounding_box_max_radius(BoundingBox bb)
{
	GLfloat x = (bb.max.x > -bb.min.x)? bb.max.x: -bb.min.x;
	GLfloat y = (bb.max.y > -bb.min.y)? bb.max.y: -bb.min.y;
	GLfloat z = (bb.max.z > -bb.min.z)? bb.max.z: -bb.min.z;
	GLfloat xy = (x > y)? x: y;
	return	(xy > z)? xy: z;
}

/*

        QUATERNION MATH ROUTINES
        

*/

// product of two quaternions
//
Quaternion	quaternion_multiply(Quaternion q1, Quaternion q2)
{
    Quaternion	result;
    result.w = q1.w * q2.w - q1.x * q2.x - q1.y * q2.y - q1.z * q2.z;
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
    
	Quaternion q = quat;
	quaternion_normalise(&q);
	
	w = q.w;
	z = q.z;
	y = q.y;
	x = q.x;
    
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

	if (res.x||res.y||res.z)
		return unit_vector(&res);
	else
		return make_vector( 1, 0, 0);
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
	
	if (res.x||res.y||res.z)
		return unit_vector(&res);
	else
		return make_vector( 0, 1, 0);
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

	if (res.x||res.y||res.z)
		return unit_vector(&res);
	else
		return make_vector( 0, 0, 1);
}

// produce a quaternion representing an angle between two vectors
//
Quaternion	quaternion_rotation_between(Vector v0, Vector v1)	// vectors both normalised
{
	Quaternion q;
	quaternion_set_identity(&q);
	GLfloat s = (GLfloat)sqrt((1.0 + v0.x * v1.x + v0.y * v1.y + v0.z * v1.z) * 2.0);
	if (s)
	{
		q.x = (v0.y * v1.z - v0.z * v1.y) / s;
		q.y = (v0.z * v1.x - v0.x * v1.z) / s;
		q.z = (v0.x * v1.y - v0.y * v1.x) / s;
		q.w = s * 0.5;
	}
	else
	{
		printf("ERROR * minarc s == zero ! *\n");
	}
	return q;
}

// produce a quaternion representing an angle between two vectors with a maximum arc
//
Quaternion	quaternion_limited_rotation_between(Vector v0, Vector v1, float maxArc)	// vectors both normalised
{
	Quaternion q;
	quaternion_set_identity(&q);
	GLfloat min_s = 2.0 * cos( 0.5 * maxArc);
	GLfloat s = (GLfloat)sqrt((1.0 + v0.x * v1.x + v0.y * v1.y + v0.z * v1.z) * 2.0);
	if (s)
	{
		if (s < min_s)	// larger angle => smaller cos
		{
			GLfloat a = maxArc * 0.5;
			GLfloat w = cos(a);
			GLfloat scale = sin(a);
			printf("DEBUG using maxArc %.5f \tw %.5f \tscale %.5f\n", maxArc, w, scale);
			q.x = (v0.y * v1.z - v0.z * v1.y) * scale;
			q.y = (v0.z * v1.x - v0.x * v1.z) * scale;
			q.z = (v0.x * v1.y - v0.y * v1.x) * scale;
			q.w = w;
		}
		else
		{
			q.x = (v0.y * v1.z - v0.z * v1.y) / s;
			q.y = (v0.z * v1.x - v0.x * v1.z) / s;
			q.z = (v0.x * v1.y - v0.y * v1.x) / s;
			q.w = s * 0.5;
		}
	}
	else
	{
		printf("ERROR * minarc s == zero ! *\n");
	}
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
#ifndef WIN32
    GLfloat	lv = FastInvSqrt(w*w + x*x + y*y + z*z);
#else
    GLfloat	lv = 1.0 / sqrt(w*w + x*x + y*y + z*z);
#endif
    quat->w = lv * w;
    quat->x = lv * x;
    quat->y = lv * y;
    quat->z = lv * z;
}

//
// calculate a unit normal vector for a triangle_4v storing it in v[3]
//
Vector	calculateNormalForTriangle(struct triangle_4v *tri)
{
	Vector v01 = vector_between(tri->v[0], tri->v[1]);
	Vector v12 = vector_between(tri->v[1], tri->v[2]);
	tri->v[3] = cross_product( v01, v12);
	return tri->v[3];
}
//
// make triangle
//
Triangle	make_triangle(Vector v0, Vector v1, Vector v2)
{
	Triangle result;
	result.v[0] = v0;
	result.v[1] = v1;
	result.v[2] = v2;
	calculateNormalForTriangle(&result);
	return result;
}

//
//	resolve vector in arbitrary ijk vectors
//
Vector		resolveVectorInIJK(Vector v0, Triangle ijk)
{
	Vector result;
	result.x = dot_product( v0, ijk.v[0]);
	result.y = dot_product( v0, ijk.v[1]);
	result.z = dot_product( v0, ijk.v[2]);
	return result;
}

// routines concerning octree voxels

int checkFace(Vector p, GLfloat rd)
{
	int faces = 0;
	if (p.x >  rd) faces |= CUBE_FACE_RIGHT;	// right
	if (p.x < -rd) faces |= CUBE_FACE_LEFT;		// left
	if (p.y >  rd) faces |= CUBE_FACE_TOP;		// above
	if (p.y < -rd) faces |= CUBE_FACE_BOTTOM;	// below
	if (p.z >  rd) faces |= CUBE_FACE_FRONT;	// ahead
	if (p.z < -rd) faces |= CUBE_FACE_BACK;		// behind
	return faces ;
}

int checkBevel(Vector p, GLfloat rd)
{
	GLfloat r2 = rd * 2;
	int bevels = 0;
	if ( p.x + p.y > r2) bevels |= 0x001;
	if ( p.x - p.y > r2) bevels |= 0x002;
	if (-p.x + p.y > r2) bevels |= 0x004;
	if (-p.x - p.y > r2) bevels |= 0x008;
	if ( p.x + p.z > r2) bevels |= 0x010;
	if ( p.x - p.z > r2) bevels |= 0x020;
	if (-p.x + p.z > r2) bevels |= 0x040;
	if (-p.x - p.z > r2) bevels |= 0x080;
	if ( p.y + p.z > r2) bevels |= 0x100;
	if ( p.y - p.z > r2) bevels |= 0x200;
	if (-p.y + p.z > r2) bevels |= 0x400;
	if (-p.y - p.z > r2) bevels |= 0x800;
	return bevels;
}

int checkCorner(Vector p, GLfloat rd)
{
	GLfloat r3 = rd * 3;
	int corners = 0;
	if (( p.x + p.y + p.z) > r3) corners |= 0x01;
	if (( p.x + p.y - p.z) > r3) corners |= 0x02;
	if (( p.x - p.y + p.z) > r3) corners |= 0x04;
	if (( p.x - p.y - p.z) > r3) corners |= 0x08;
	if ((-p.x + p.y + p.z) > r3) corners |= 0x10;
	if ((-p.x + p.y - p.z) > r3) corners |= 0x20;
	if ((-p.x - p.y + p.z) > r3) corners |= 0x40;
	if ((-p.x - p.y - p.z) > r3) corners |= 0x80;
	return corners;
}

Vector lineIntersectionWithFace(Vector p1, Vector p2, long mask, GLfloat rd)
{
	if (CUBE_FACE_RIGHT & mask)
		return make_vector( rd,
							p1.y + (p2.y - p1.y) * (rd - p1.x) / (p2.x - p1.x),
							p1.z + (p2.z - p1.z) * (rd - p1.x) / (p2.x - p1.x));
	
	if (CUBE_FACE_LEFT & mask)
		return make_vector( -rd,
							p1.y + (p2.y - p1.y) * (-rd - p1.x) / (p2.x - p1.x),
							p1.z + (p2.z - p1.z) * (-rd - p1.x) / (p2.x - p1.x));
	
	if (CUBE_FACE_TOP & mask)
		return make_vector( p1.x + (p2.x - p1.x) * (rd - p1.y) / (p2.y - p1.y),
							rd,
							p1.z + (p2.z - p1.z) * (rd - p1.y) / (p2.y - p1.y));
	
	if (CUBE_FACE_BOTTOM & mask)
		return make_vector( p1.x + (p2.x - p1.x) * (-rd - p1.y) / (p2.y - p1.y),
							-rd,
							p1.z + (p2.z - p1.z) * (-rd - p1.y) / (p2.y - p1.y));
	
	if (CUBE_FACE_FRONT & mask)
		return make_vector( p1.x + (p2.x - p1.x) * (rd - p1.z) / (p2.z - p1.z),
							p1.y + (p2.y - p1.y) * (rd - p1.z) / (p2.z - p1.z),
							rd);
	
	if (CUBE_FACE_BACK & mask)
		return make_vector( p1.x + (p2.x - p1.x) * (-rd - p1.z) / (p2.z - p1.z),
							p1.y + (p2.y - p1.y) * (-rd - p1.z) / (p2.z - p1.z),
							-rd);
	return p1;
}

int checkPoint(Vector p1, Vector p2, GLfloat alpha, long mask, GLfloat rd)
{
	Vector pp;
	pp.x = p1.x + alpha * (p2.x - p1.x);
	pp.y = p1.y + alpha * (p2.y - p1.y);
	pp.z = p1.z + alpha * (p2.z - p1.z);
	return (checkFace( pp, rd) & mask);
}

int checkLine(Vector p1, Vector p2, int mask, GLfloat rd)
{
	int result = 0;
	if ((CUBE_FACE_RIGHT & mask) && (p1.x > p2.x) && (checkPoint( p1, p2, (rd-p1.x)/(p2.x-p1.x), 0x3f - CUBE_FACE_RIGHT, rd) == 0))		// right
		result |= CUBE_FACE_RIGHT;
	if ((CUBE_FACE_LEFT & mask) && (p1.x < p2.x) && (checkPoint( p1, p2, (-rd-p1.x)/(p2.x-p1.x), 0x3f - CUBE_FACE_LEFT, rd) == 0))		// left
		result |= CUBE_FACE_LEFT;
	if ((CUBE_FACE_TOP & mask) && (p1.y > p2.y) && (checkPoint( p1, p2, (rd-p1.y)/(p2.y-p1.y), 0x3f - CUBE_FACE_TOP, rd) == 0))			// above
		result |= CUBE_FACE_TOP;
	if ((CUBE_FACE_BOTTOM & mask) && (p1.y < p2.y) && (checkPoint( p1, p2, (-rd-p1.y)/(p2.y-p1.y), 0x3f - CUBE_FACE_BOTTOM, rd) == 0))	// below
		result |= CUBE_FACE_BOTTOM;
	if ((CUBE_FACE_FRONT & mask) && (p1.z > p2.z) && (checkPoint( p1, p2, (rd-p1.z)/(p2.z-p1.z), 0x3f - CUBE_FACE_FRONT, rd) == 0))		// ahead
		result |= CUBE_FACE_FRONT;
	if ((CUBE_FACE_BACK & mask) && (p1.z < p2.z) && (checkPoint( p1, p2, (-rd-p1.z)/(p2.z-p1.z), 0x3f - CUBE_FACE_BACK, rd) == 0))		// behind
		result |= CUBE_FACE_BACK;
	return result;
}

// line v0 to v1 is compared with a cube centered on the origin (corners at -rd,-rd,-rd to rd,rd,rd).                    
// returns -1 if the line intersects the cube. 
int lineCubeIntersection(Vector v0, Vector v1, GLfloat rd)
{
	int	v0_test, v1_test;

	//	compare both vertexes with all six face-planes 
	//
	if ((v0_test = checkFace( v0, rd)) == 0)
		return -1;	// v0 is inside the cube
	if ((v1_test = checkFace( v1, rd)) == 0)
		return -1;	// v1 is inside the cube
	
	// check they're not both outside one face-plane
	//
	if ((v0_test & v1_test) != 0)
		return 0;	// both v0 and v1 are outside the same face of the cube

	//	Now do the same test for the 12 edge planes 
	//
	v0_test |= checkBevel( v0, rd) << 8; 
	v1_test |= checkBevel( v1, rd) << 8; 
	if ((v0_test & v1_test) != 0)
		return 0; // v0 and v1 outside of the same bevel  

	//	Now do the same test for the 8 corner planes
	//
	v0_test |= checkCorner( v0, rd) << 24; 
	v1_test |= checkCorner( v1, rd) << 24; 
	if ((v0_test & v1_test) != 0)
		return 0; // v0 and v1 outside of same corner   

	// see if the v0-->v1 line intersects the cube.
	//
	return checkLine( v0, v1, v0_test | v1_test, rd);
}
