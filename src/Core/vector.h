#ifndef _VECTOR_H
#define _VECTOR_H
/*

Provides utility routines for Vectors, Quaternions, rotation matrices, and conversion to OpenGL transformation matrices
 
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

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Noncommercial. You may not use this work for commercial purposes.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

#import "OOOpenGL.h"


#define OCTANT_LEFT_BOTTOM_BACK		0
#define OCTANT_LEFT_BOTTOM_FRONT	1
#define OCTANT_LEFT_TOP_BACK		2
#define OCTANT_LEFT_TOP_FRONT		3
#define OCTANT_RIGHT_BOTTOM_BACK	4
#define OCTANT_RIGHT_BOTTOM_FRONT	5
#define OCTANT_RIGHT_TOP_BACK		6
#define OCTANT_RIGHT_TOP_FRONT		7

#define CUBE_FACE_RIGHT		0x01
#define CUBE_FACE_LEFT		0x02
#define CUBE_FACE_TOP		0x04
#define CUBE_FACE_BOTTOM	0x08
#define CUBE_FACE_FRONT		0x10
#define CUBE_FACE_BACK		0x20

struct vector
{
	GLfloat x;
	GLfloat y;
	GLfloat z;
};

struct boundingBox
{
	struct vector min;
	struct vector max;
};

struct triangle_3v
{
	struct vector v[3];
};

struct triangle_4v
{
	struct vector v[4];	// v0 v1 v2 and vnormal
};

typedef struct vector Matrix[3];

typedef struct vector Vector;

typedef struct boundingBox BoundingBox;

typedef struct triangle_4v Triangle;

typedef GLfloat	gl_matrix[16];

struct quaternion
{
	GLfloat w;
	GLfloat x;
	GLfloat y;
	GLfloat z;
};

typedef struct quaternion Quaternion;

void	mult_matrix (struct vector *first, struct vector *second);
void	mult_vector (struct vector *vec, struct vector *mat);

//
// Multiply vector by scalar
//
void	scale_vector (struct vector *vec, GLfloat factor);

//
// Multiply vector by gl_matrix.
//
void mult_vector_gl_matrix (struct vector *vec, GLfloat *glmat);

Vector cross_product (Vector first, Vector second);
Vector normal_to_surface (Vector v1, Vector v2, Vector v3);

struct vector unit_vector (struct vector *vec);
void	set_matrix_identity (struct vector *mat);

void	matrix_into_gl_matrix(struct vector *mat, GLfloat *glmat);
void	vectors_into_gl_matrix(Vector vf, Vector vr, Vector vu, GLfloat *glmat);
void	gl_matrix_into_matrix(GLfloat *glmat, struct vector *mat);

void	bounding_box_add_vector(struct boundingBox *box, Vector vec);
void	bounding_box_add_xyz(struct boundingBox *box, GLfloat x, GLfloat y, GLfloat z);
void	bounding_box_reset(struct boundingBox *box);
void	bounding_box_reset_to_vector(struct boundingBox *box, Vector vec);
GLfloat	bounding_box_max_radius(BoundingBox bb);

// product of two quaternions
//
Quaternion	quaternion_multiply(Quaternion q1, Quaternion q2);
// set identity
//
void	quaternion_set_identity(struct quaternion *quat);
// set 0 0 0 1
//
void	quaternion_set_random(struct quaternion *quat);
// set r r r 1 with |Q| = 1.0
//
void	quaternion_set_rotate_about_axis(struct quaternion *quat, Vector axis, GLfloat angle);
// dot product of two vectors
//
GLfloat	quaternion_dot_product(Quaternion q1, Quaternion q2);

// produce a GL_matrix from a quaternion
//
void	quaternion_into_gl_matrix(Quaternion quat, GLfloat *glmat);

// produce a right vector from a quaternion
//
Vector	vector_right_from_quaternion(Quaternion quat);

// produce an up vector from a quaternion
//
Vector	vector_up_from_quaternion(Quaternion quat);

// produce a forward vector from a quaternion
//
Vector	vector_forward_from_quaternion(Quaternion quat);

// produce a quaternion representing an angle between two vectors
//
Quaternion	quaternion_rotation_between(Vector v0, Vector v1);

// produce a quaternion representing an angle between two vectors with a maximum arc
//
Quaternion	quaternion_limited_rotation_between(Vector v0, Vector v1, float maxArc);	// vectors both normalised

//
// rotate about fixed axes
//
void	quaternion_rotate_about_x(struct quaternion *quat, GLfloat angle);
void	quaternion_rotate_about_y(struct quaternion *quat, GLfloat angle);
void	quaternion_rotate_about_z(struct quaternion *quat, GLfloat angle);
void	quaternion_rotate_about_axis(struct quaternion *quat, Vector axis, GLfloat angle);
//
// normalise
//
void	quaternion_normalise(struct quaternion *quat);

Vector		calculateNormalForTriangle(struct triangle_4v * tri);
Triangle	make_triangle(Vector v0, Vector v1, Vector v2);
Vector		resolveVectorInIJK(Vector v0, Triangle ijk);

Vector lineIntersectionWithFace(Vector p1, Vector p2, long mask, GLfloat rd);
int lineCubeIntersection(Vector v0, Vector v1, GLfloat rd);


#ifndef GCC_ATTR
	#ifdef __GNUC__
		#define GCC_ATTR(x)	__attribute__(x)
	#else
		#define GCC_ATTR(x)
	#endif
#endif


// returns the square of the magnitude of the vector
//
static inline GLfloat magnitude2 (Vector vec) GCC_ATTR((always_inline, pure));
static inline GLfloat magnitude2 (Vector vec)
{
	return vec.x * vec.x + vec.y * vec.y + vec.z * vec.z;
}

// returns the square of the distance between two points
//
static inline GLfloat distance2 (Vector v1, Vector v2) GCC_ATTR((always_inline, pure));
static inline GLfloat distance2 (Vector v1, Vector v2)
{
	return (v1.x - v2.x) * (v1.x - v2.x) + (v1.y - v2.y) * (v1.y - v2.y) + (v1.z - v2.z) * (v1.z - v2.z);
}

// Calculate the dot product of two vectors sharing a common point.
// Returns the cosine of the angle between the two vectors.
//
static inline GLfloat dot_product (Vector first, Vector second) GCC_ATTR((always_inline, pure));
static inline GLfloat dot_product (Vector first, Vector second)
{
	return (first.x * second.x) + (first.y * second.y) + (first.z * second.z);	
}

// make a vector
//
static inline struct vector make_vector (GLfloat vx, GLfloat vy, GLfloat vz) GCC_ATTR((always_inline, pure));
static inline struct vector make_vector (GLfloat vx, GLfloat vy, GLfloat vz)
{
	Vector result;
	result.x = vx;
	result.y = vy;
	result.z = vz;
	return result;
}

// vector from a to b
//
static inline Vector vector_between (Vector a, Vector b) GCC_ATTR((always_inline, pure));
static inline Vector vector_between (Vector a, Vector b)
{
	return make_vector( b.x - a.x, b.y - a.y, b.z - a.z);
}

#endif

