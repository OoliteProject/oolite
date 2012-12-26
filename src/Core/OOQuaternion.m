/*

OOQuaternion.m

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


#include "OOMaths.h"


const Quaternion		kIdentityQuaternion = { 1.0f, 0.0f, 0.0f, 0.0f };
const Quaternion		kZeroQuaternion = { 0.0f, 0.0f, 0.0f, 0.0f };


Quaternion quaternion_multiply(Quaternion q1, Quaternion q2)
{
	Quaternion	result;
	result.w = q1.w * q2.w - q1.x * q2.x - q1.y * q2.y - q1.z * q2.z;
	result.x = q1.w * q2.x + q1.x * q2.w + q1.y * q2.z - q1.z * q2.y;
	result.y = q1.w * q2.y + q1.y * q2.w + q1.z * q2.x - q1.x * q2.z;
	result.z = q1.w * q2.z + q1.z * q2.w + q1.x * q2.y - q1.y * q2.x;
	return result;
}


#if !OOMATHS_STANDALONE
// NOTE: this is broken - its distribution is weighted towards corners of the hypercube. Probably doesn't matter, though.
void quaternion_set_random(Quaternion *quat)
{
	quat->w = (OOScalar)(Ranrot() % 1024) - 511.5f;  // -511.5 to +511.5
	quat->x = (OOScalar)(Ranrot() % 1024) - 511.5f;  // -511.5 to +511.5
	quat->y = (OOScalar)(Ranrot() % 1024) - 511.5f;  // -511.5 to +511.5
	quat->z = (OOScalar)(Ranrot() % 1024) - 511.5f;  // -511.5 to +511.5
	quaternion_normalize(quat);
}
#endif


Vector vector_forward_from_quaternion(Quaternion quat)
{
	OOScalar	w, wy, wx;
	OOScalar	x, xz, xx;
	OOScalar	y, yz, yy;
	OOScalar	z, zz;
	Vector res;
	
	w = quat.w;
	z = quat.z;
	y = quat.y;
	x = quat.x;
	
	xx = 2.0f * x; yy = 2.0f * y; zz = 2.0f * z;
	wx = w * xx; wy = w * yy;
	xx = x * xx; xz = x * zz;
	yy = y * yy; yz = y * zz;
	
	res.x = xz - wy;
	res.y = yz + wx;
	res.z = 1.0f - xx - yy;
	
	if (res.x||res.y||res.z)  return vector_normal(res);
	else  return make_vector(0.0f, 0.0f, 1.0f);
}


Vector vector_up_from_quaternion(Quaternion quat)
{
	OOScalar	w, wz, wx;
	OOScalar	x, xy, xx;
	OOScalar	y, yz, yy;
	OOScalar	z, zz;
	Vector res;
	
	w = quat.w;
	z = quat.z;
	y = quat.y;
	x = quat.x;
	
	xx = 2.0f * x; yy = 2.0f * y; zz = 2.0f * z;
	wx = w * xx; wz = w * zz;
	xx = x * xx; xy = x * yy;
	yz = y * zz;
	zz = z * zz;
	
	res.x = xy + wz;
	res.y = 1.0f - xx - zz;
	res.z = yz - wx;
	
	if (res.x||res.y||res.z)  return vector_normal(res);
	else  return make_vector(0.0f, 1.0f, 0.0f);
}


Vector vector_right_from_quaternion(Quaternion quat)
{
	OOScalar	w, wz, wy;
	OOScalar	x, xz, xy;
	OOScalar	y, yy;
	OOScalar	z, zz;
	Vector res;
	
	w = quat.w;
	z = quat.z;
	y = quat.y;
	x = quat.x;
	
	yy = 2.0f * y; zz = 2.0f * z;
	wy = w * yy; wz = w * zz;
	xy = x * yy; xz = x * zz;
	yy = y * yy;
	zz = z * zz;
	
	res.x = 1.0f - yy - zz;
	res.y = xy - wz;
	res.z = xz + wy;
	
	if (res.x||res.y||res.z)  return vector_normal(res);
	else  return make_vector(1.0f, 0.0f, 0.0f);
}


void basis_vectors_from_quaternion(Quaternion quat, Vector *outRight, Vector *outUp, Vector *outForward)
{
	OOScalar	w, wz, wy, wx;
	OOScalar	x, xz, xy, xx;
	OOScalar	y, yz, yy;
	OOScalar	z, zz;
	
	w = quat.w;
	z = quat.z;
	y = quat.y;
	x = quat.x;
	
	xx = 2.0f * x; yy = 2.0f * y; zz = 2.0f * z;
	wx = w * xx; wy = w * yy; wz = w * zz;
	xx = x * xx; xy = x * yy; xz = x * zz;
	yy = y * yy; yz = y * zz;
	zz = z * zz;
	
	if (outRight != NULL)
	{
		outRight->x = 1.0f - yy - zz;
		outRight->y = xy - wz;
		outRight->z = xz + wy;

		if (outRight->x || outRight->y || outRight->z)  *outRight = vector_normal(*outRight);
		else  *outRight = make_vector(1.0f, 0.0f, 0.0f);
	}
	
	if (outUp != NULL)
	{
		outUp->x = xy + wz;
		outUp->y = 1.0f - xx - zz;
		outUp->z = yz - wx;
		
		if (outUp->x || outUp->y || outUp->z)  *outUp = vector_normal(*outUp);
		else  *outUp = make_vector(0.0f, 1.0f, 0.0f);
	}
	
	if (outForward != NULL)
	{
		outForward->x = xz - wy;
		outForward->y = yz + wx;
		outForward->z = 1.0f - xx - yy;
		
		if (outForward->x || outForward->y || outForward->z)  *outForward = vector_normal(*outForward);
		else  *outForward = make_vector(0.0f, 0.0f, 1.0f);
	}
}


Quaternion quaternion_rotation_between(Vector v0, Vector v1)
{
	Quaternion q;
	OOScalar s = sqrt((1.0f + v0.x * v1.x + v0.y * v1.y + v0.z * v1.z) * 2.0f);
	if (EXPECT(s > 0.0f))
	{
		OOScalar is = 1.0f / s;
		q.x = (v0.y * v1.z - v0.z * v1.y) * is;
		q.y = (v0.z * v1.x - v0.x * v1.z) * is;
		q.z = (v0.x * v1.y - v0.y * v1.x) * is;
		q.w = s * 0.5f;
	}
	else
	{
		// Is this actually a problem?
		if (vector_equal(v1, kBasisZVector) || vector_equal(v0, kBasisZVector))
		{
			q = make_quaternion(0, 1, 0, 0);
		}
		else
		{
			q = kIdentityQuaternion;
		}
		// We arrive here for antiparallel vectors. Rotation axis is then undefined, but not rotating is
		// wrong. Probably the calling function should exclude this situation. For current
		// in-game use of this function we return (0,1,0,0), but generally that is also wrong.
	}
	return q;
}


Quaternion quaternion_limited_rotation_between(Vector v0, Vector v1, float maxArc)	// vectors both normalised
{
	Quaternion q;
	OOScalar min_s = 2.0f * cos(0.5f * maxArc);
	OOScalar s = sqrt((1.0f + v0.x * v1.x + v0.y * v1.y + v0.z * v1.z) * 2.0f);
	// for some antiparallel vectors, s returns a NaN instead of 0. Testing s > 0 catches both.
	if (EXPECT(s > 0.0f))
	{
		if (s < min_s)	// larger angle => smaller cos
		{
			OOScalar a = maxArc * 0.5f;
			OOScalar w = cos(a);
			OOScalar scale = sin(a);
			q.x = (v0.y * v1.z - v0.z * v1.y) * scale;
			q.y = (v0.z * v1.x - v0.x * v1.z) * scale;
			q.z = (v0.x * v1.y - v0.y * v1.x) * scale;
			q.w = w;
		}
		else
		{
			OOScalar is = 1.0f / s;
			q.x = (v0.y * v1.z - v0.z * v1.y) * is;
			q.y = (v0.z * v1.x - v0.x * v1.z) * is;
			q.z = (v0.x * v1.y - v0.y * v1.x) * is;
			q.w = s * 0.5f;
		}
	}
	else
	{
		// Is this actually a problem?
		q = kIdentityQuaternion;
	}
	return q;
}


void quaternion_rotate_about_x(Quaternion *quat, OOScalar angle)
{
	Quaternion result;
	OOScalar a = angle * 0.5f;
	OOScalar w = cos(a);
	OOScalar scale = sin(a);
	
	result.w = quat->w * w - quat->x * scale;
	result.x = quat->w * scale + quat->x * w;
	result.y = quat->y * w + quat->z * scale;
	result.z = quat->z * w - quat->y * scale;
	
	quat->w = result.w;
	quat->x = result.x;
	quat->y = result.y;
	quat->z = result.z;
}


void quaternion_rotate_about_y(Quaternion *quat, OOScalar angle)
{
	Quaternion result;
	OOScalar a = angle * 0.5f;
	OOScalar w = cos(a);
	OOScalar scale = sin(a);
	
	result.w = quat->w * w - quat->y * scale;
	result.x = quat->x * w - quat->z * scale;
	result.y = quat->w * scale + quat->y * w;
	result.z = quat->z * w + quat->x * scale;
	
	quat->w = result.w;
	quat->x = result.x;
	quat->y = result.y;
	quat->z = result.z;
}


void quaternion_rotate_about_z(Quaternion *quat, OOScalar angle)
{
	Quaternion result;
	OOScalar a = angle * 0.5f;
	OOScalar w = cos(a);
	OOScalar scale = sin(a);
	
	result.w = quat->w * w - quat->z * scale;
	result.x = quat->x * w + quat->y * scale;
	result.y = quat->y * w - quat->x * scale;
	result.z = quat->w * scale + quat->z * w;
	
	quat->w = result.w;
	quat->x = result.x;
	quat->y = result.y;
	quat->z = result.z;
}


void quaternion_rotate_about_axis(Quaternion *quat, Vector axis, OOScalar angle)
{
	Quaternion q2 /*, result */;
	OOScalar a = angle * 0.5f;
	OOScalar w = cos(a);
	OOScalar scale = sin(a);
	
	q2.w = w;
	q2.x = axis.x * scale;
	q2.y = axis.y * scale;
	q2.z = axis.z * scale;
	
	*quat = quaternion_multiply(*quat, q2);
}


#if __OBJC__
NSString *QuaternionDescription(Quaternion quaternion)
{
	float			x, y, z;
	char			xs, ys, zs;
	
	x = fabs(quaternion.x);
	y = fabs(quaternion.y);
	z = fabs(quaternion.z);
	
	xs = (quaternion.x >= 0.0f) ? '+' : '-';
	ys = (quaternion.y >= 0.0f) ? '+' : '-';
	zs = (quaternion.z >= 0.0f) ? '+' : '-';
	
	return [NSString stringWithFormat:@"(%g %c %gi %c %gj %c %gk)", quaternion.w, xs, x, ys, y, zs, z];
}
#endif


Vector quaternion_rotate_vector(Quaternion q, Vector v)
{
	Quaternion				qv;
	
	qv.w = 0.0f - q.x * v.x - q.y * v.y - q.z * v.z;
	qv.x = -q.w * v.x + q.y * v.z - q.z * v.y;
	qv.y = -q.w * v.y + q.z * v.x - q.x * v.z;
	qv.z = -q.w * v.z + q.x * v.y - q.y * v.x;
	
	v.x = qv.w * -q.x + qv.x * -q.w + qv.y * -q.z - qv.z * -q.y;
	v.y = qv.w * -q.y + qv.y * -q.w + qv.z * -q.x - qv.x * -q.z;
	v.z = qv.w * -q.z + qv.z * -q.w + qv.x * -q.y - qv.y * -q.x;
	
	return v;
}
