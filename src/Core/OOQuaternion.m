/*

OOQuaternion.m

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
#import "OOLogging.h"


const Quaternion		kIdentityQuaternion = { 1.0f, 0.0f, 0.0f, 0.0f };


static NSString * const kOOLogMathsZeroRotation = @"maths.quaternion.zeroRotation";
static NSString * const kOOLogMathsQuatLimitedRotationDebug = @"maths.quaternion.limitedRotation.debug";


Quaternion quaternion_multiply(Quaternion q1, Quaternion q2)
{
    Quaternion	result;
    result.w = q1.w * q2.w - q1.x * q2.x - q1.y * q2.y - q1.z * q2.z;
    result.x = q1.w * q2.x + q1.x * q2.w + q1.y * q2.z - q1.z * q2.y;
    result.y = q1.w * q2.y + q1.y * q2.w + q1.z * q2.x - q1.x * q2.z;
    result.z = q1.w * q2.z + q1.z * q2.w + q1.x * q2.y - q1.y * q2.x;
    return result;
}


// NOTE: this is broken - its distribution is weighted towards corners of the hypercube. Probably doesn't matter, though.
void quaternion_set_random(Quaternion *quat)
{
    quat->w = (GLfloat)(ranrot_rand() % 1024) - 511.5f;  // -511.5 to +511.5
    quat->x = (GLfloat)(ranrot_rand() % 1024) - 511.5f;  // -511.5 to +511.5
    quat->y = (GLfloat)(ranrot_rand() % 1024) - 511.5f;  // -511.5 to +511.5
    quat->z = (GLfloat)(ranrot_rand() % 1024) - 511.5f;  // -511.5 to +511.5
	quaternion_normalize(quat);
}


void quaternion_into_gl_matrix(Quaternion quat, GLfloat *glmat)
{
	GLfloat	w, wz, wy, wx;
	GLfloat	x, xz, xy, xx;
	GLfloat	y, yz, yy;
	GLfloat	z, zz;
    
	Quaternion q = quat;
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

	glmat[ 0] = 1.0f - yy - zz;	glmat[ 4] = xy + wz;		glmat[ 8] = xz - wy;		glmat[12] = 0.0f;
	glmat[ 1] = xy - wz;		glmat[ 5] = 1.0f - xx - zz;	glmat[ 9] = yz + wx;		glmat[13] = 0.0f;
	glmat[ 2] = xz + wy;		glmat[ 6] = yz - wx;		glmat[10] = 1.0f - xx - yy;	glmat[14] = 0.0f;
	glmat[ 3] = 0.0f;			glmat[ 7] = 0.0f;			glmat[11] = 0.0f;			glmat[15] = 1.0f;
}


Vector vector_forward_from_quaternion(Quaternion quat)
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
    
    xx = 2.0f * x; yy = 2.0f * y; zz = 2.0f * z;
    wx = w * xx; wy = w * yy; wz = w * zz;
    xx = x * xx; xy = x * yy; xz = x * zz;
    yy = y * yy; yz = y * zz;
    zz = z * zz;

    res.x = xz - wy;
	res.y = yz + wx;
	res.z = 1.0f - xx - yy;

	if (res.x||res.y||res.z)  return unit_vector(&res);
	else  return make_vector(0.0f, 0.0f, 1.0f);
}


Vector vector_up_from_quaternion(Quaternion quat)
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
    
    xx = 2.0f * x; yy = 2.0f * y; zz = 2.0f * z;
    wx = w * xx; wy = w * yy; wz = w * zz;
    xx = x * xx; xy = x * yy; xz = x * zz;
    yy = y * yy; yz = y * zz;
    zz = z * zz;

    res.x = xy + wz;
	res.y = 1.0f - xx - zz;
	res.z = yz - wx;
	
	if (res.x||res.y||res.z)  return unit_vector(&res);
	else  return make_vector(0.0f, 1.0f, 0.0f);
}


Vector vector_right_from_quaternion(Quaternion quat)
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
    
    xx = 2.0f * x; yy = 2.0f * y; zz = 2.0f * z;
    wx = w * xx; wy = w * yy; wz = w * zz;
    xx = x * xx; xy = x * yy; xz = x * zz;
    yy = y * yy; yz = y * zz;
    zz = z * zz;

    res.x = 1.0f - yy - zz;
	res.y = xy - wz;
	res.z = xz + wy;

	if (res.x||res.y||res.z)  return unit_vector(&res);
	else  return make_vector(1.0f, 0.0f, 0.0f);
}


Quaternion quaternion_rotation_between(Vector v0, Vector v1)
{
	Quaternion q;
	GLfloat s = sqrtf((1.0f + v0.x * v1.x + v0.y * v1.y + v0.z * v1.z) * 2.0f);
	if (EXPECT(s))
	{
		GLfloat is = 1.0f / s;
		q.x = (v0.y * v1.z - v0.z * v1.y) * is;
		q.y = (v0.z * v1.x - v0.x * v1.z) * is;
		q.z = (v0.x * v1.y - v0.y * v1.x) * is;
		q.w = s * 0.5f;
	}
	else
	{
		// Is this actually a problem?
		q = kIdentityQuaternion;
	//	OOLog(kOOLogMathsZeroRotation, @"***** minarc s == zero!");
	}
	return q;
}


Quaternion quaternion_limited_rotation_between(Vector v0, Vector v1, float maxArc)	// vectors both normalised
{
	Quaternion q;
	GLfloat min_s = 2.0f * cosf(0.5f * maxArc);
	GLfloat s = sqrtf((1.0f + v0.x * v1.x + v0.y * v1.y + v0.z * v1.z) * 2.0f);
	if (EXPECT(s))
	{
		if (s < min_s)	// larger angle => smaller cos
		{
			GLfloat a = maxArc * 0.5f;
			GLfloat w = cosf(a);
			GLfloat scale = sinf(a);
			OOLog(kOOLogMathsQuatLimitedRotationDebug, @"DEBUG using maxArc %.5f \tw %.5f \tscale %.5f", maxArc, w, scale);
			q.x = (v0.y * v1.z - v0.z * v1.y) * scale;
			q.y = (v0.z * v1.x - v0.x * v1.z) * scale;
			q.z = (v0.x * v1.y - v0.y * v1.x) * scale;
			q.w = w;
		}
		else
		{
			GLfloat is = 1.0f / s;
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
	//	OOLog(kOOLogMathsZeroRotation, @"***** minarc s == zero!");
	}
	return q;
}


void quaternion_rotate_about_x(Quaternion *quat, GLfloat angle)
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


void quaternion_rotate_about_y(Quaternion *quat, GLfloat angle)
{
    Quaternion result;
    GLfloat a = angle * 0.5f;
    GLfloat w = cosf(a);
    GLfloat scale = sinf(a);

    result.w = quat->w * w - quat->y * scale;
    result.x = quat->x * w - quat->z * scale;
    result.y = quat->w * scale + quat->y * w;
    result.z = quat->z * w + quat->x * scale;
    
    quat->w = result.w;
    quat->x = result.x;
    quat->y = result.y;
    quat->z = result.z;
}


void quaternion_rotate_about_z(Quaternion *quat, GLfloat angle)
{
    Quaternion result;
    GLfloat a = angle * 0.5f;
    GLfloat w = cosf(a);
    GLfloat scale = sinf(a);
    
    result.w = quat->w * w - quat->z * scale;
    result.x = quat->x * w + quat->y * scale;
    result.y = quat->y * w - quat->x * scale;
    result.z = quat->w * scale + quat->z * w;
    
    quat->w = result.w;
    quat->x = result.x;
    quat->y = result.y;
    quat->z = result.z;
}


void quaternion_rotate_about_axis(Quaternion *quat, Vector axis, GLfloat angle)
{
    Quaternion q2, result;
    GLfloat a = angle * 0.5f;
    GLfloat w = cosf(a);
    GLfloat scale = sinf(a);
	
    q2.w = w;
    q2.x = axis.x * scale;
    q2.y = axis.y * scale;
    q2.z = axis.z * scale;
	    
    result.w = quat->w * q2.w - q2.x * quat->x - quat->y * q2.y - quat->z * q2.z;
    result.x = quat->w * q2.x + quat->x * q2.w + quat->y * q2.z - quat->z * q2.y;
    result.y = quat->w * q2.y + quat->y * q2.w + quat->z * q2.x - quat->x * q2.z;
    result.z = quat->w * q2.z + quat->z * q2.w + quat->x * q2.y - quat->y * q2.x;
	
    quat->w = result.w;
    quat->x = result.x;
    quat->y = result.y;
    quat->z = result.z;
}


NSString *QuaternionDescription(Quaternion quaternion)
{
	return [NSString stringWithFormat:@"(%g + %gi + %gj + %gk)", quaternion.w, quaternion.x, quaternion.y, quaternion.z];
}
