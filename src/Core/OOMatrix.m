/*

OOMatrix.m

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


#include "OOMaths.h"


const OOMatrix	kIdentityMatrix = 
								{ .m = {
									{1.0f, 0.0f, 0.0f, 0.0f},
									{0.0f, 1.0f, 0.0f, 0.0f},
									{0.0f, 0.0f, 1.0f, 0.0f},
									{0.0f, 0.0f, 0.0f, 1.0f}
								}};
const OOMatrix	kZeroMatrix		= { .m = {
									{0.0f, 0.0f, 0.0f, 0.0f},
									{0.0f, 0.0f, 0.0f, 0.0f},
									{0.0f, 0.0f, 0.0f, 0.0f},
									{0.0f, 0.0f, 0.0f, 0.0f},
								}};


OOMatrix OOMatrixForRotation(Vector axis, OOScalar angle)
{
	axis = vector_normal(axis);
	
	OOScalar x = axis.x, y = axis.y, z = axis.z;
	OOScalar s = sin(angle), c = cos(angle);
	OOScalar t = 1.0f - c;
	
	// Lots of opportunity for common subexpression elimintation here, but I'll leave it to the compiler for now.
	return OOMatrixConstruct
	(
		t * x * x + c,		t * x * y + s * z,	t * x * z - s * y,	0.0f,
		t * x * y - s * z,	t * y * y + c,		t * y * z + s * x,	0.0f,
		t * x * y + s * y,	t * y * z - s * x,	t * z * z + c,		0.0f,
		0.0f,				0.0f,				0.0f,				1.0f
	);
}


OOMatrix OOMatrixForQuaternionRotation(Quaternion orientation)
{
	OOScalar	w, wz, wy, wx;
	OOScalar	x, xz, xy, xx;
	OOScalar	y, yz, yy;
	OOScalar	z, zz;
	
	Quaternion q = orientation;
	quaternion_normalize(&q);
	
	w = q.w;
	z = q.z;
	y = q.y;
	x = q.x;
	
	xx = 2.0f * x; yy = 2.0f * y; zz = 2.0f * z;
	wx = w * xx; wy = w * yy; wz = w * zz;
	xx = x * xx; xy = x * yy; xz = x * zz;
	yy = y * yy; yz = y * zz;
	zz = z * zz;
	
	return OOMatrixConstruct
	(
		1.0f - yy - zz,	xy - wz,		xz + wy,		0.0f,
		xy + wz,		1.0f - xx - zz,	yz - wx,		0.0f,
		xz - wy,		yz + wx,		1.0f - xx - yy,	0.0f,
		0.0f,			0.0f,			0.0f,			1.0f
	);
}


bool OOMatrixEqual(OOMatrix a, OOMatrix b)
{
	OOScalar *ma = &a.m[0][0];
	OOScalar *mb = &b.m[0][0];
	
	unsigned i;
	for (i = 0; i < 16; i++)
	{
		if (*ma++ != *mb++)  return false;
	}
	
	return true;
}


OOMatrix OOMatrixMultiply(OOMatrix a, OOMatrix b)
{
	unsigned			i = 0;
	OOMatrix			r;
	
	// This is amenable to significant optimization with Altivec, and presumably also SSE.
	for (i = 0; i != 4; ++i)
	{
		r.m[i][0] = a.m[i][0] * b.m[0][0] + a.m[i][1] * b.m[1][0] + a.m[i][2] * b.m[2][0] + a.m[i][3] * b.m[3][0];
		r.m[i][1] = a.m[i][0] * b.m[0][1] + a.m[i][1] * b.m[1][1] + a.m[i][2] * b.m[2][1] + a.m[i][3] * b.m[3][1];
		r.m[i][2] = a.m[i][0] * b.m[0][2] + a.m[i][1] * b.m[1][2] + a.m[i][2] * b.m[2][2] + a.m[i][3] * b.m[3][2];
		r.m[i][3] = a.m[i][0] * b.m[0][3] + a.m[i][1] * b.m[1][3] + a.m[i][2] * b.m[2][3] + a.m[i][3] * b.m[3][3];
	}
	
	return r;
}


Vector OOVectorMultiplyMatrix(Vector v, OOMatrix m)
{
	OOScalar x, y, z, w;
	
	x = m.m[0][0] * v.x + m.m[1][0] * v.y + m.m[2][0] * v.z + m.m[3][0];
	y = m.m[0][1] * v.x + m.m[1][1] * v.y + m.m[2][1] * v.z + m.m[3][1];
	z = m.m[0][2] * v.x + m.m[1][2] * v.y + m.m[2][2] * v.z + m.m[3][2];
	w = m.m[0][3] * v.x + m.m[1][3] * v.y + m.m[2][3] * v.z + m.m[3][3];
	
	w = 1.0f/w;
	return make_vector(x * w, y * w, z * w);
}


OOMatrix OOMatrixOrthogonalize(OOMatrix m)
{
	//	Simple orthogonalization: make everything orthogonal to everything else.
	
	Vector i;// = { m.m[0][0], m.m[1][0], m.m[2][0] };	// Overwritten without being used
	Vector j = { m.m[0][1], m.m[1][1], m.m[2][1] };
	Vector k = { m.m[0][2], m.m[1][2], m.m[2][2] };
	
	k = vector_normal(k);
	i = vector_normal(cross_product(j, k));
	j = cross_product(k, i);
	
	m.m[0][0] = i.x; m.m[1][0] = i.y; m.m[2][0] = i.z;
	m.m[0][1] = j.x; m.m[1][1] = j.y; m.m[2][1] = j.z;
	m.m[0][2] = k.x; m.m[1][2] = k.y; m.m[2][2] = k.z;
	
	return m;
}


#if __OBJC__
NSString *OOMatrixDescription(OOMatrix matrix)
{
	return [NSString stringWithFormat:@"{{%g, %g, %g, %g}, {%g, %g, %g, %g}, {%g, %g, %g, %g}, {%g, %g, %g, %g}}",
			matrix.m[0][0], matrix.m[0][1], matrix.m[0][2], matrix.m[0][3],
			matrix.m[1][0], matrix.m[1][1], matrix.m[1][2], matrix.m[1][3],
			matrix.m[2][0], matrix.m[2][1], matrix.m[2][2], matrix.m[2][3],
			matrix.m[3][0], matrix.m[3][1], matrix.m[3][2], matrix.m[3][3]];
}
#endif


OOMatrix OOMatrixForBillboard(Vector bbPos, Vector eyePos)
{
	Vector			v0, v1, v2, arbv;
	
	v0 = vector_subtract(bbPos, eyePos);
	v0 = vector_normal_or_fallback(v0, kBasisZVector);
	
	// arbitrary axis - not aligned with v0
	if (EXPECT_NOT(v0.x == 0.0 && v0.y == 0.0))  arbv = kBasisXVector;
	else  arbv = kBasisZVector;
	
	v1 = cross_product(v0, arbv); // 90 degrees to (v0 x arb1)
	v2 = cross_product(v0, v1);   // 90 degrees to (v0 x v1)
	
	return OOMatrixFromBasisVectors(v1, v2, v0);
}
