/*

OOMatrix.m

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


#import "OOMaths.h"


const Matrix			kIdentityMatrix =
						{
							{ 1.0f, 0.0f, 0.0f },
							{ 0.0f, 1.0f, 0.0f },
							{ 0.0f, 0.0f, 1.0f }
						};
const Matrix			kZeroMatrix =
						{
							{ 0.0f, 0.0f, 0.0f },
							{ 0.0f, 0.0f, 0.0f },
							{ 0.0f, 0.0f, 0.0f }
						};


void mult_matrix(Matrix a, const Matrix b)
{
	int i;
	Matrix rv;

	for (i = 0; i < 3; i++)
	{

		rv[i].x =	(a[0].x * b[i].x) +
				 	(a[1].x * b[i].y) +
					(a[2].x * b[i].z);

		rv[i].y =	(a[0].y * b[i].x) +
					(a[1].y * b[i].y) +
					(a[2].y * b[i].z);

		rv[i].z =	(a[0].z * b[i].x) +
					(a[1].z * b[i].y) +
					(a[2].z * b[i].z);
	}
	
	a[0] = rv[0];
	a[1] = rv[1];
	a[2] = rv[2];
}


void mult_vector(Vector *v, const Matrix m)
{
	GLfloat x;
	GLfloat y;
	GLfloat z;

	x = (v->x * m[0].x) +
		(v->y * m[0].y) +
		(v->z * m[0].z);

	y = (v->x * m[1].x) +
		(v->y * m[1].y) +
		(v->z * m[1].z);

	z = (v->x * m[2].x) +
		(v->y * m[2].y) +
		(v->z * m[2].z);

	v->x = x;
	v->y = y;
	v->z = z;
}


void matrix_into_gl_matrix(const Matrix mat, gl_matrix glmat)
{
    glmat[0] = mat[0].x;	glmat[4] = mat[0].y;	glmat[8] = mat[0].z;	glmat[3] = 0.0f;
    glmat[1] = mat[1].x;	glmat[5] = mat[1].y;	glmat[9] = mat[1].z;	glmat[7] = 0.0f;
    glmat[2] = mat[2].x;	glmat[6] = mat[2].y;	glmat[10] = mat[2].z;	glmat[11] = 0.0f;
    glmat[12] = 0.0f;		glmat[13] = 0.0f;		glmat[14] = 0.0f;		glmat[15] = 1.0f;
}


void gl_matrix_into_matrix(const gl_matrix glmat, Matrix mat)
{
    mat[0].x = glmat[0];	mat[0].y = glmat[4];	mat[0].z = glmat[8];
	mat[1].x = glmat[1];	mat[1].y = glmat[5];	mat[1].z = glmat[9];
	mat[2].x = glmat[2];	mat[2].y = glmat[6];	mat[2].z = glmat[10];
}


// Multiply vector by gl_matrix.
void mult_vector_gl_matrix (Vector *vec, const gl_matrix glmat)
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


void vectors_into_gl_matrix(Vector forward, Vector right, Vector up, gl_matrix glmat)
{
    glmat[0] = right.x;	glmat[4] = up.x;	glmat[8] = forward.x;	glmat[3] = 0.0;
    glmat[1] = right.y;	glmat[5] = up.y;	glmat[9] = forward.y;	glmat[7] = 0.0;
    glmat[2] = right.z;	glmat[6] = up.z;	glmat[10] = forward.z;	glmat[11] = 0.0;
    glmat[12] = 0.0;	glmat[13] = 0.0;	glmat[14] = 0.0;		glmat[15] = 1.0;
}
