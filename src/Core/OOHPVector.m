/*

OOHPVector.m

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


const HPVector			kZeroHPVector = { 0.0, 0.0, 0.0 };
const HPVector			kBasisXHPVector = { 1.0, 0.0, 0.0 };
const HPVector			kBasisYHPVector = { 0.0, 1.0, 0.0 };
const HPVector			kBasisZHPVector = { 0.0, 0.0, 1.0 };

const HPVector2D			kZeroHPVector2D = { 0.0, 0.0 };
const HPVector2D			kBasisXHPVector2D = { 1.0, 0.0 };
const HPVector2D			kBasisYHPVector2D = { 0.0, 1.0 };


#if __OBJC__
NSString *HPVectorDescription(HPVector vector)
{
	return [NSString stringWithFormat:@"(%g, %g, %g)", vector.x, vector.y, vector.z];
}

NSArray *ArrayFromHPVector(HPVector vec)
{
	return [NSArray arrayWithObjects:[NSNumber numberWithDouble:vec.x],
					[NSNumber numberWithDouble:vec.y],
					[NSNumber numberWithDouble:vec.z],
					nil];
}

#endif


#if !OOMATHS_STANDALONE
/*	This generates random vectors distrubuted evenly over the surface of the
	unit sphere. It does this the simple way, by generating vectors in the
	half-unit cube and rejecting those outside the half-unit sphere (and the
	zero vector), then normalizing the result. (Half-unit measures are used
	to avoid unnecessary multiplications of randf() values.)
	
	In principle, using three normally-distributed co-ordinates (and again
	normalizing the result) would provide the right result without looping, but
	I don't trust bellf() so I'll go with the simple approach for now.
*/
HPVector OORandomUnitHPVector(void)
{
	HPVector				v;
	OOHPScalar				m;
	
	do
	{
		v = make_HPvector(randf() - 0.5f, randf() - 0.5f, randf() - 0.5f);
		m = HPmagnitude2(v);
	}
	while (m > 0.25 || m == 0.0);	// We're confining to a sphere of radius 0.5 using the sqared magnitude; 0.5 squared is 0.25.
	
	return HPvector_normal(v);
}


HPVector OOHPVectorRandomSpatial(OOHPScalar maxLength)
{
	HPVector				v;
	OOHPScalar				m;
	
	do
	{
		v = make_HPvector(randf() - 0.5f, randf() - 0.5f, randf() - 0.5f);
		m = HPmagnitude2(v);
	}
	while (m > 0.25);	// We're confining to a sphere of radius 0.5 using the sqared magnitude; 0.5 squared is 0.25.
	
	return HPvector_multiply_scalar(v, maxLength * 2.0);	// 2.0 is to compensate for the 0.5-radius sphere.
}


HPVector OOHPVectorRandomRadial(OOHPScalar maxLength)
{
	return HPvector_multiply_scalar(OORandomUnitHPVector(), randf() * maxLength);
}


HPVector OOHPRandomPositionInBoundingBox(BoundingBox bb)
{
	HPVector result;
	result.x = (OOHPScalar)(bb.min.x + randf() * (bb.max.x - bb.min.x));
	result.y = (OOHPScalar)(bb.min.y + randf() * (bb.max.y - bb.min.y));
	result.z = (OOHPScalar)(bb.min.z + randf() * (bb.max.z - bb.min.z));
	return result;
}

HPVector OORandomPositionInCylinder(HPVector centre1, OOHPScalar exclusion1, HPVector centre2, OOHPScalar exclusion2, OOHPScalar radius)
{
	OOHPScalar exc12 = exclusion1*exclusion1;
	OOHPScalar exc22 = exclusion2*exclusion2;
	if (HPdistance(centre1,centre2) < (exclusion1+exclusion2)*1.2)
	{
		OOLog(@"position.cylinder.error",@"Trying to generate cylinder position in range %f long with exclusions %f and %f",HPdistance(centre1,centre2),exclusion1,exclusion2);
	}
	HPVector result;
	do
	{
		result = HPvector_add(OOHPVectorInterpolate(centre1,centre2,randf()),OOHPVectorRandomSpatial(radius));
	}
	while(HPdistance2(result,centre1)<exc12 || HPdistance2(result,centre2)<exc22);
	return result;
}

HPVector OORandomPositionInShell(HPVector centre, OOHPScalar inner, OOHPScalar outer)
{
	HPVector result;
	OOHPScalar inner2 = inner*inner;
	do
	{
		result = HPvector_add(centre,OOHPVectorRandomSpatial(outer));
	} while(HPdistance2(result,centre)<inner2);
	return result;
}

HPVector OOProjectHPVectorToPlane(HPVector point, HPVector plane, HPVector normal)
{
	return HPvector_subtract(point,HPvector_multiply_scalar(normal,HPdot_product(HPvector_subtract(point, plane), normal)));
}

#endif
