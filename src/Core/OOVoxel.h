/*

OOVoxel.h

Mathematical framework for Oolite.

Primitive functions used for octree intersection tests.

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
	#error Do not include OOVoxel.h directly; include OOMaths.h.
#else


#define CUBE_FACE_RIGHT		0x01
#define CUBE_FACE_LEFT		0x02
#define CUBE_FACE_TOP		0x04
#define CUBE_FACE_BOTTOM	0x08
#define CUBE_FACE_FRONT		0x10
#define CUBE_FACE_BACK		0x20


Vector lineIntersectionWithFace(Vector p1, Vector p2, long mask, GLfloat rd) CONST_FUNC;
int lineCubeIntersection(Vector v0, Vector v1, GLfloat rd) CONST_FUNC;


#endif
