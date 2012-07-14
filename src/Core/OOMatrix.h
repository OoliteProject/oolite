/*

OOMatrix.h

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
	#error Do not include OOMatrix.h directly; include OOMaths.h.
#else

typedef struct OOMatrix
{
	OOScalar				m[4][4];
} OOMatrix;


extern const OOMatrix	kIdentityMatrix;		/* {1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1} */
extern const OOMatrix	kZeroMatrix;			/* {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0} */


/* Matrix construction and standard primitive matrices */
OOINLINE OOMatrix OOMatrixConstruct(OOScalar aa, OOScalar ab, OOScalar ac, OOScalar ad,
									OOScalar ba, OOScalar bb, OOScalar bc, OOScalar bd,
									OOScalar ca, OOScalar cb, OOScalar cc, OOScalar cd,
									OOScalar da, OOScalar db, OOScalar dc, OOScalar dd) INLINE_CONST_FUNC;

OOINLINE OOMatrix OOMatrixFromOrientationAndPosition(Quaternion orientation, Vector position) INLINE_CONST_FUNC;

OOINLINE OOMatrix OOMatrixFromBasisVectorsAndPosition(Vector i, Vector j, Vector k, Vector position) INLINE_CONST_FUNC;
OOINLINE OOMatrix OOMatrixFromBasisVectors(Vector i, Vector j, Vector k) INLINE_CONST_FUNC;

OOINLINE OOMatrix OOMatrixForScale(OOScalar sx, OOScalar sy, OOScalar sz) INLINE_CONST_FUNC;
OOINLINE OOMatrix OOMatrixForScaleUniform(OOScalar s) INLINE_CONST_FUNC;

OOINLINE OOMatrix OOMatrixForRotationX(OOScalar angle) INLINE_CONST_FUNC;
OOINLINE OOMatrix OOMatrixForRotationY(OOScalar angle) INLINE_CONST_FUNC;
OOINLINE OOMatrix OOMatrixForRotationZ(OOScalar angle) INLINE_CONST_FUNC;
OOMatrix OOMatrixForRotation(Vector axis, OOScalar angle) CONST_FUNC;
OOMatrix OOMatrixForQuaternionRotation(Quaternion orientation);

OOINLINE OOMatrix OOMatrixForTranslation(Vector v) INLINE_CONST_FUNC;
OOINLINE OOMatrix OOMatrixForTranslationComponents(OOScalar dx, OOScalar dy, OOScalar dz) INLINE_CONST_FUNC;

OOMatrix OOMatrixForBillboard(Vector bbPos, Vector eyePos) CONST_FUNC;


/* Matrix transformations */
OOINLINE OOMatrix OOMatrixTranslate(OOMatrix m, Vector offset) INLINE_CONST_FUNC;
OOINLINE OOMatrix OOMatrixTranslateComponents(OOMatrix m, OOScalar dx, OOScalar dy, OOScalar dz) INLINE_CONST_FUNC;

OOINLINE OOMatrix OOMatrixScale(OOMatrix m, OOScalar sx, OOScalar sy, OOScalar sz) INLINE_CONST_FUNC;
OOINLINE OOMatrix OOMatrixScaleUniform(OOMatrix m, OOScalar s) INLINE_CONST_FUNC;

OOINLINE OOMatrix OOMatrixRotateX(OOMatrix m, OOScalar angle) INLINE_CONST_FUNC;
OOINLINE OOMatrix OOMatrixRotateY(OOMatrix m, OOScalar angle) INLINE_CONST_FUNC;
OOINLINE OOMatrix OOMatrixRotateZ(OOMatrix m, OOScalar angle) INLINE_CONST_FUNC;
OOINLINE OOMatrix OOMatrixRotate(OOMatrix m, Vector axis, OOScalar angle) INLINE_CONST_FUNC;
OOINLINE OOMatrix OOMatrixRotateQuaternion(OOMatrix m, Quaternion quat) INLINE_CONST_FUNC;


bool OOMatrixEqual(OOMatrix a, OOMatrix b) CONST_FUNC;
OOINLINE bool OOMatrixIsIdentity(OOMatrix m) INLINE_CONST_FUNC;


/* Matrix multiplication */
OOMatrix OOMatrixMultiply(OOMatrix a, OOMatrix b) CONST_FUNC;
Vector OOVectorMultiplyMatrix(Vector v, OOMatrix m) CONST_FUNC;


/* Extraction */
OOINLINE void OOMatrixGetBasisVectors(OOMatrix m, Vector *outRight, Vector *outUp, Vector *outForward) NONNULL_FUNC ALWAYS_INLINE_FUNC;


/* Orthogonalizion - avoidance of distortions due to numerical inaccuracy. */
OOMatrix OOMatrixOrthogonalize(OOMatrix m) CONST_FUNC;


#if OOMATHS_OPENGL_INTEGRATION
/*	OpenGL conveniences. Need to be macros to work with OOMacroOpenGL. */
#define OOMatrixValuesForOpenGL(M) (&(M).m[0][0])
#define GLMultOOMatrix(M) do { OOMatrix m_ = M; OOGL(glMultMatrixf(OOMatrixValuesForOpenGL(m_))); } while (0)
#define GLLoadOOMatrix(M) do { OOMatrix m_ = M; OOGL(glLoadMatrixf(OOMatrixValuesForOpenGL(m_))); } while (0)
#define GLMultTransposeOOMatrix(M) do { OOMatrix m_ = M; OOGL(glMultTransposeMatrixf(OOMatrixValuesForOpenGL(m_))); } while (0)
#define GLLoadTransposeOOMatrix(M) do { OOMatrix m_ = M; OOGL(glLoadTransposeMatrixf(OOMatrixValuesForOpenGL(m_))); } while (0)
#define GLUniformMatrix(location, M) do { OOGL(glUniformMatrix4fvARB(location, 1, NO, OOMatrixValuesForOpenGL(M))); } while (0)

OOINLINE OOMatrix OOMatrixLoadGLMatrix(unsigned long /* GLenum */ matrixID) ALWAYS_INLINE_FUNC;
#endif


#if __OBJC__
NSString *OOMatrixDescription(OOMatrix matrix);		// @"{{#, #, #, #}, {#, #, #, #}, {#, #, #, #}, {#, #, #, #}}"
#endif



/*** Only inline definitions beyond this point ***/

OOINLINE OOMatrix OOMatrixConstruct(OOScalar aa, OOScalar ab, OOScalar ac, OOScalar ad,
									OOScalar ba, OOScalar bb, OOScalar bc, OOScalar bd,
									OOScalar ca, OOScalar cb, OOScalar cc, OOScalar cd,
									OOScalar da, OOScalar db, OOScalar dc, OOScalar dd)
{
	OOMatrix r =
	{{
		{ aa, ab, ac, ad },
		{ ba, bb, bc, bd },
		{ ca, cb, cc, cd },
		{ da, db, dc, dd }
	}};
	return r;
}

OOINLINE OOMatrix OOMatrixFromOrientationAndPosition(Quaternion orientation, Vector position)
{
	OOMatrix m = OOMatrixForQuaternionRotation(orientation);
	return OOMatrixTranslate(m, position);
}


OOINLINE OOMatrix OOMatrixFromBasisVectorsAndPosition(Vector i, Vector j, Vector k, Vector p)
{
	return OOMatrixConstruct
	(
		i.x,	i.y,	i.z,	0.0f,
		j.x,	j.y,	j.z,	0.0f,
		k.x,	k.y,	k.z,	0.0f,
		p.x,	p.y,	p.z,	1.0f
	);
}


OOINLINE OOMatrix OOMatrixFromBasisVectors(Vector i, Vector j, Vector k)
{
	return OOMatrixFromBasisVectorsAndPosition(i, j, k, kZeroVector);
}


/* Standard primitive transformation matrices: */
OOMatrix OOMatrixForRotationX(OOScalar angle)
{
	OOScalar			s, c;
	
	s = sin(angle);
	c = cos(angle);
	
	return OOMatrixConstruct
	(
		1,  0,  0,  0,
		0,  c,  s,  0,
		0, -s,  c,  0,
		0,  0,  0,  1
	);
}


OOMatrix OOMatrixForRotationY(OOScalar angle)
{
	OOScalar			s, c;
	
	s = sin(angle);
	c = cos(angle);
	
	return OOMatrixConstruct
	(
		c,  0, -s,  0,
		0,  1,  0,  0,
		s,  0,  c,  0,
		0,  0,  0,  1
	);
}


OOMatrix OOMatrixForRotationZ(OOScalar angle)
{
	OOScalar			s, c;
	
	s = sin(angle);
	c = cos(angle);
	
	return OOMatrixConstruct
	(
	    c,  s,  0,  0,
	   -s,  c,  0,  0,
	    0,  0,  1,  0,
	    0,  0,  0,  1
	);
}
OOINLINE OOMatrix OOMatrixForTranslationComponents(OOScalar dx, OOScalar dy, OOScalar dz)
{
	return OOMatrixConstruct
	(
	    1,  0,  0,  0,
	    0,  1,  0,  0,
	    0,  0,  1,  0,
	   dx, dy, dz,  1
	);
}


OOINLINE OOMatrix OOMatrixForTranslation(Vector v)
{
	return OOMatrixForTranslationComponents(v.x, v.y, v.z);
}


OOINLINE OOMatrix OOMatrixTranslateComponents(OOMatrix m, OOScalar dx, OOScalar dy, OOScalar dz)
{
	m.m[3][0] += dx;
	m.m[3][1] += dy;
	m.m[3][2] += dz;
	return m;
}


OOINLINE OOMatrix OOMatrixTranslate(OOMatrix m, Vector offset)
{
	return OOMatrixTranslateComponents(m, offset.x, offset.y, offset.z);
}


OOINLINE OOMatrix OOMatrixForScale(OOScalar sx, OOScalar sy, OOScalar sz)
{
	return OOMatrixConstruct
	(
	   sx,  0,  0,  0,
	    0, sy,  0,  0,
	    0,  0, sz,  0,
	    0,  0,  0,  1
	);
}


OOINLINE OOMatrix OOMatrixForScaleUniform(OOScalar s)
{
	return OOMatrixForScale(s, s, s);
}


OOINLINE OOMatrix OOMatrixScale(OOMatrix m, OOScalar sx, OOScalar sy, OOScalar sz)
{
	return OOMatrixMultiply(m, OOMatrixForScale(sx, sy, sz));
}


OOINLINE OOMatrix OOMatrixScaleUniform(OOMatrix m, OOScalar s)
{
	return OOMatrixScale(m, s, s, s);
}


OOINLINE OOMatrix OOMatrixRotateX(OOMatrix m, OOScalar angle)
{
	return OOMatrixMultiply(m, OOMatrixForRotationX(angle));
}


OOINLINE OOMatrix OOMatrixRotateY(OOMatrix m, OOScalar angle)
{
	return OOMatrixMultiply(m, OOMatrixForRotationY(angle));
}


OOINLINE OOMatrix OOMatrixRotateZ(OOMatrix m, OOScalar angle)
{
	return OOMatrixMultiply(m, OOMatrixForRotationZ(angle));
}


OOINLINE OOMatrix OOMatrixRotate(OOMatrix m, Vector axis, OOScalar angle)
{
	return OOMatrixMultiply(m, OOMatrixForRotation(axis, angle));
}


OOINLINE OOMatrix OOMatrixRotateQuaternion(OOMatrix m, Quaternion quat)
{
	return OOMatrixMultiply(m, OOMatrixForQuaternionRotation(quat));
}


OOINLINE bool OOMatrixIsIdentity(OOMatrix m)
{
	return OOMatrixEqual(m, kIdentityMatrix);
}


OOINLINE void OOMatrixGetBasisVectors(OOMatrix m, Vector *outRight, Vector *outUp, Vector *outForward)
{
	assert(outRight != NULL && outUp != NULL && outForward != NULL);
	
	*outRight	= make_vector(m.m[0][0], m.m[1][0], m.m[2][0]);
	*outUp		= make_vector(m.m[0][1], m.m[1][1], m.m[2][1]);
	*outForward	= make_vector(m.m[0][2], m.m[1][2], m.m[2][2]);
}


#if OOMATHS_OPENGL_INTEGRATION
OOINLINE OOMatrix OOMatrixLoadGLMatrix(unsigned long /* GLenum */ matrixID)
{
	OOMatrix m;
	glGetFloatv(matrixID, OOMatrixValuesForOpenGL(m));
	return m;
}
#endif

#endif	/* INCLUDED_OOMATHS_h */
