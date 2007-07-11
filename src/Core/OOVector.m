/*

OOVector.m

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


const Vector			kZeroVector = { 0.0f, 0.0f, 0.0f };
const Vector			kBasisXVector = { 1.0f, 0.0f, 0.0f };
const Vector			kBasisYVector = { 0.0f, 1.0f, 0.0f };
const Vector			kBasisZVector = { 0.0f, 0.0f, 1.0f };
const BoundingBox		kZeroBoundingBox = {{ 0.0f, 0.0f, 0.0f }, { 0.0f, 0.0f, 0.0f }};


static NSString * const kOOLogMathsNormalizeZero = @"maths.vector.normalizeZero";


void ReportNormalizeZeroVector(void)
{
	OOLog(kOOLogMathsNormalizeZero, @"***** Attempt to normalize zero vector.");
}


NSString *VectorDescription(Vector vector)
{
	return [NSString stringWithFormat:@"(%g, %g, %g)", vector.x, vector.y, vector.z];
}
