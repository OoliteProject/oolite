/*

OOMatrix.h

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
	#error Do not include OOMatrix.h directly; include OOMaths.h.
#else


typedef GLfloat	gl_matrix[16];

/* NOTE: this definition makes Matrix a pointer type. */
//typedef Vector Matrix[3];
typedef struct
{
	Vector				m[3];
} Matrix;


extern const Matrix		kIdentityMatrix;		// {1, 0, 0}, {0, 1, 0}, {0, 0, 1}
extern const Matrix		kZeroMatrix;			// {0, 0, 0}, {0, 0, 0}, {0, 0, 0}


/* Set matrix to identity matrix */
OOINLINE void set_matrix_identity(Matrix *outMatrix) ALWAYS_INLINE_FUNC NONNULL_FUNC DEPRECATED_FUNC;

/* Copy one matrix to another */
OOINLINE void matrix_copy(Matrix *outMatrix, const Matrix value) ALWAYS_INLINE_FUNC NONNULL_FUNC DEPRECATED_FUNC;
OOINLINE void OOCopyGLMatrix(gl_matrix dst, const gl_matrix src) ALWAYS_INLINE_FUNC NONNULL_FUNC;

/* Mutiply two matrices, storing the result in a. */
void mult_matrix(Matrix *outA, const Matrix b) NONNULL_FUNC;

/* Muliply a vector by a matrix, storing the result in v. */
void mult_vector(Vector *outV, const Matrix m) NONNULL_FUNC;

/* Convert between Matrix and OpenGL matrix */
void matrix_into_gl_matrix(const Matrix m, gl_matrix outGLMatrix) NONNULL_FUNC;
void gl_matrix_into_matrix(const gl_matrix glmat, Matrix *outMatrix) NONNULL_FUNC;


/* Multiply vector by OpenGL matrix */
void mult_vector_gl_matrix(Vector *outVector, const gl_matrix glmat) NONNULL_FUNC;

/* Build an OpenGL matrix from vectors */
void vectors_into_gl_matrix(Vector forward, Vector right, Vector up, gl_matrix outGLMatrix) NONNULL_FUNC;



/*** Only inline definitions beyond this point ***/
OOINLINE void matrix_copy(Matrix *matrix, const Matrix value)
{
	*matrix = value;
}


OOINLINE void OOCopyGLMatrix(gl_matrix dst, const gl_matrix src)
{
	memcpy(dst, src, sizeof dst);
}


OOINLINE void set_matrix_identity(Matrix *matrix)
{
	*matrix = kIdentityMatrix;
}


#endif	/* INCLUDED_OOMATHS_h */
