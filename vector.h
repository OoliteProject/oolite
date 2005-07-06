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
#ifndef VECTOR_H
#define VECTOR_H

#ifdef LINUX
#include "oolite-linux.h"
#else
#import <OpenGL/gl.h>
#endif

struct vector
{
	GLfloat x;
	GLfloat y;
	GLfloat z;
};

struct boundingBox
{
	GLfloat min_x, max_x;
	GLfloat min_y, max_y;
	GLfloat min_z, max_z;
};

typedef struct vector Matrix[3];

typedef struct vector Vector;

typedef struct boundingBox BoundingBox;

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
// Multiply vector by gl_matrix.
//
void mult_vector_gl_matrix (struct vector *vec, GLfloat *glmat);

inline GLfloat magnitude2 (Vector vec);
inline GLfloat distance2 (Vector v1, Vector v2);
inline GLfloat dot_product (Vector first, Vector second);
Vector cross_product (Vector first, Vector second);
Vector normal_to_surface (Vector v1, Vector v2, Vector v3);

inline struct vector make_vector (GLfloat vx, GLfloat vy, GLfloat vz);
struct vector unit_vector (struct vector *vec);
void	set_matrix_identity (struct vector *mat);

void	matrix_into_gl_matrix(struct vector *mat, GLfloat *glmat);
void	vectors_into_gl_matrix(Vector vf, Vector vr, Vector vu, GLfloat *glmat);
void	gl_matrix_into_matrix(GLfloat *glmat, struct vector *mat);

void	bounding_box_add_vector(struct boundingBox *box, Vector vec);
void	bounding_box_add_xyz(struct boundingBox *box, GLfloat x, GLfloat y, GLfloat z);
void	bounding_box_reset(struct boundingBox *box);
void	bounding_box_reset_to_vector(struct boundingBox *box, Vector vec);

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

#endif

