/*

OOVoxel.m

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


#import "OOMaths.h"


// routines concerning octree voxels

int checkFace(Vector p, GLfloat rd)
{
	int faces = 0;
	if (p.x >  rd) faces |= CUBE_FACE_RIGHT;	// right
	if (p.x < -rd) faces |= CUBE_FACE_LEFT;		// left
	if (p.y >  rd) faces |= CUBE_FACE_TOP;		// above
	if (p.y < -rd) faces |= CUBE_FACE_BOTTOM;	// below
	if (p.z >  rd) faces |= CUBE_FACE_FRONT;	// ahead
	if (p.z < -rd) faces |= CUBE_FACE_BACK;		// behind
	return faces ;
}

int checkBevel(Vector p, GLfloat rd)
{
	GLfloat r2 = rd * 2;
	int bevels = 0;
	if ( p.x + p.y > r2) bevels |= 0x001;
	if ( p.x - p.y > r2) bevels |= 0x002;
	if (-p.x + p.y > r2) bevels |= 0x004;
	if (-p.x - p.y > r2) bevels |= 0x008;
	if ( p.x + p.z > r2) bevels |= 0x010;
	if ( p.x - p.z > r2) bevels |= 0x020;
	if (-p.x + p.z > r2) bevels |= 0x040;
	if (-p.x - p.z > r2) bevels |= 0x080;
	if ( p.y + p.z > r2) bevels |= 0x100;
	if ( p.y - p.z > r2) bevels |= 0x200;
	if (-p.y + p.z > r2) bevels |= 0x400;
	if (-p.y - p.z > r2) bevels |= 0x800;
	return bevels;
}

int checkCorner(Vector p, GLfloat rd)
{
	GLfloat r3 = rd * 3;
	int corners = 0;
	if (( p.x + p.y + p.z) > r3) corners |= 0x01;
	if (( p.x + p.y - p.z) > r3) corners |= 0x02;
	if (( p.x - p.y + p.z) > r3) corners |= 0x04;
	if (( p.x - p.y - p.z) > r3) corners |= 0x08;
	if ((-p.x + p.y + p.z) > r3) corners |= 0x10;
	if ((-p.x + p.y - p.z) > r3) corners |= 0x20;
	if ((-p.x - p.y + p.z) > r3) corners |= 0x40;
	if ((-p.x - p.y - p.z) > r3) corners |= 0x80;
	return corners;
}

Vector lineIntersectionWithFace(Vector p1, Vector p2, long mask, GLfloat rd)
{
	if (CUBE_FACE_RIGHT & mask)
		return make_vector( rd,
							p1.y + (p2.y - p1.y) * (rd - p1.x) / (p2.x - p1.x),
							p1.z + (p2.z - p1.z) * (rd - p1.x) / (p2.x - p1.x));
	
	if (CUBE_FACE_LEFT & mask)
		return make_vector( -rd,
							p1.y + (p2.y - p1.y) * (-rd - p1.x) / (p2.x - p1.x),
							p1.z + (p2.z - p1.z) * (-rd - p1.x) / (p2.x - p1.x));
	
	if (CUBE_FACE_TOP & mask)
		return make_vector( p1.x + (p2.x - p1.x) * (rd - p1.y) / (p2.y - p1.y),
							rd,
							p1.z + (p2.z - p1.z) * (rd - p1.y) / (p2.y - p1.y));
	
	if (CUBE_FACE_BOTTOM & mask)
		return make_vector( p1.x + (p2.x - p1.x) * (-rd - p1.y) / (p2.y - p1.y),
							-rd,
							p1.z + (p2.z - p1.z) * (-rd - p1.y) / (p2.y - p1.y));
	
	if (CUBE_FACE_FRONT & mask)
		return make_vector( p1.x + (p2.x - p1.x) * (rd - p1.z) / (p2.z - p1.z),
							p1.y + (p2.y - p1.y) * (rd - p1.z) / (p2.z - p1.z),
							rd);
	
	if (CUBE_FACE_BACK & mask)
		return make_vector( p1.x + (p2.x - p1.x) * (-rd - p1.z) / (p2.z - p1.z),
							p1.y + (p2.y - p1.y) * (-rd - p1.z) / (p2.z - p1.z),
							-rd);
	return p1;
}

int checkPoint(Vector p1, Vector p2, GLfloat alpha, long mask, GLfloat rd)
{
	Vector pp;
	pp.x = p1.x + alpha * (p2.x - p1.x);
	pp.y = p1.y + alpha * (p2.y - p1.y);
	pp.z = p1.z + alpha * (p2.z - p1.z);
	return (checkFace( pp, rd) & mask);
}

int checkLine(Vector p1, Vector p2, int mask, GLfloat rd)
{
	int result = 0;
	if ((CUBE_FACE_RIGHT & mask) && (p1.x > p2.x) && (checkPoint( p1, p2, (rd-p1.x)/(p2.x-p1.x), 0x3f - CUBE_FACE_RIGHT, rd) == 0))		// right
		result |= CUBE_FACE_RIGHT;
	if ((CUBE_FACE_LEFT & mask) && (p1.x < p2.x) && (checkPoint( p1, p2, (-rd-p1.x)/(p2.x-p1.x), 0x3f - CUBE_FACE_LEFT, rd) == 0))		// left
		result |= CUBE_FACE_LEFT;
	if ((CUBE_FACE_TOP & mask) && (p1.y > p2.y) && (checkPoint( p1, p2, (rd-p1.y)/(p2.y-p1.y), 0x3f - CUBE_FACE_TOP, rd) == 0))			// above
		result |= CUBE_FACE_TOP;
	if ((CUBE_FACE_BOTTOM & mask) && (p1.y < p2.y) && (checkPoint( p1, p2, (-rd-p1.y)/(p2.y-p1.y), 0x3f - CUBE_FACE_BOTTOM, rd) == 0))	// below
		result |= CUBE_FACE_BOTTOM;
	if ((CUBE_FACE_FRONT & mask) && (p1.z > p2.z) && (checkPoint( p1, p2, (rd-p1.z)/(p2.z-p1.z), 0x3f - CUBE_FACE_FRONT, rd) == 0))		// ahead
		result |= CUBE_FACE_FRONT;
	if ((CUBE_FACE_BACK & mask) && (p1.z < p2.z) && (checkPoint( p1, p2, (-rd-p1.z)/(p2.z-p1.z), 0x3f - CUBE_FACE_BACK, rd) == 0))		// behind
		result |= CUBE_FACE_BACK;
	return result;
}

// line v0 to v1 is compared with a cube centered on the origin (corners at -rd,-rd,-rd to rd,rd,rd).
// returns -1 if the line intersects the cube. 
int lineCubeIntersection(Vector v0, Vector v1, GLfloat rd)
{
	int	v0_test, v1_test;

	//	compare both vertexes with all six face-planes 
	//
	if ((v0_test = checkFace( v0, rd)) == 0)
		return -1;	// v0 is inside the cube
	if ((v1_test = checkFace( v1, rd)) == 0)
		return -1;	// v1 is inside the cube
	
	// check they're not both outside one face-plane
	//
	if ((v0_test & v1_test) != 0)
		return 0;	// both v0 and v1 are outside the same face of the cube

	//	Now do the same test for the 12 edge planes 
	//
	v0_test |= checkBevel( v0, rd) << 8; 
	v1_test |= checkBevel( v1, rd) << 8; 
	if ((v0_test & v1_test) != 0)
		return 0; // v0 and v1 outside of the same bevel  

	//	Now do the same test for the 8 corner planes
	//
	v0_test |= checkCorner( v0, rd) << 24; 
	v1_test |= checkCorner( v1, rd) << 24; 
	if ((v0_test & v1_test) != 0)
		return 0; // v0 and v1 outside of same corner   

	// see if the v0-->v1 line intersects the cube.
	//
	return checkLine( v0, v1, v0_test | v1_test, rd);
}
