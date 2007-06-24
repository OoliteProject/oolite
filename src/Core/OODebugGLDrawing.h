/*

OODebugDrawing.h

A set of functions for drawing debug stuff like bounding boxes. These are
drawn in wireframe without Z buffer reads or writes.


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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2007 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOMaths.h"
#import "OOColor.h"


#ifndef OODEBUGLDRAWING_DISABLE

OOINLINE void OODebugDrawBoundingBox(BoundingBox box);
OOINLINE void OODebugDrawBoundingBoxBetween(Vector min, Vector max);
OOINLINE void OODebugDrawColoredBoundingBox(BoundingBox box, OOColor *color);
void OODebugDrawColoredBoundingBoxBetween(Vector min, Vector max, OOColor *color);

// Normals are drawn as cyan lines
OOINLINE void OODebugDrawNormal(Vector position, Vector normal, GLfloat scale);
OOINLINE void OODebugDrawNormalAtOrigin(Vector normal, GLfloat scale);

// Other vectors are drawn as magenta lines by default
OOINLINE void OODebugDrawVector(Vector position, Vector v);
OOINLINE void OODebugDrawColoredVector(Vector position, Vector v, OOColor *color);
OOINLINE void OODebugDrawVectorAtOrigin(Vector v);
OOINLINE void OODebugDrawColoredVectorAtOrigin(Vector v, OOColor *color);

// Lines are drawn white by default
OOINLINE void OODebugDrawLine(Vector start, Vector end);
void OODebugDrawColoredLine(Vector start, Vector end, OOColor *color);

// Bases are drawn as one red, one green and one blue vector, representing x, y and z axes in the current coordinate frame.
void OODebugDrawBasis(Vector position, GLfloat scale);
OOINLINE void OODebugDrawBasisAtOrigin(GLfloat scale);


/*** Only inline definitions beyond this point ***/

OOINLINE void OODebugDrawBoundingBoxBetween(Vector min, Vector max)
{
	OODebugDrawColoredBoundingBoxBetween(min, max, [OOColor blueColor]);
}


OOINLINE void OODebugDrawBoundingBox(BoundingBox box)
{
	OODebugDrawBoundingBoxBetween(box.min, box.max);
}


OOINLINE void OODebugDrawColoredBoundingBox(BoundingBox box, OOColor *color)
{
	OODebugDrawColoredBoundingBoxBetween(box.min, box.max, color);
}


OOINLINE void OODebugDrawNormal(Vector position, Vector normal, GLfloat scale)
{
	OODebugDrawColoredVector(position, vector_add(position, vector_multiply_scalar(normal, scale)), [OOColor cyanColor]);
}


OOINLINE void OODebugDrawNormalAtOrigin(Vector normal, GLfloat scale)
{
	OODebugDrawNormal(kZeroVector, normal, scale);
}


OOINLINE void OODebugDrawColoredVector(Vector position, Vector v, OOColor *color)
{
	OODebugDrawColoredLine(position, vector_add(position, v), color);
}


OOINLINE void OODebugDrawVector(Vector position, Vector v)
{
	OODebugDrawColoredVector(position, v, [OOColor magentaColor]);
}


OOINLINE void OODebugDrawVectorAtOrigin(Vector v)
{
	OODebugDrawVector(kZeroVector, v);
}


OOINLINE void OODebugDrawColoredVectorAtOrigin(Vector v, OOColor *color)
{
	OODebugDrawColoredVector(kZeroVector, v, color);	
}


OOINLINE void OODebugDrawLine(Vector start, Vector end)
{
	OODebugDrawColoredLine(start, end, [OOColor whiteColor]);
}


OOINLINE void OODebugDrawBasisAtOrigin(GLfloat scale)
{
	OODebugDrawBasis(kZeroVector, scale);
}

#else	// OODEBUGLDRAWING_DISABLE

#define OODRAW_NOOP		do {} while (0)

#define OODebugDrawBoundingBox(box)						OODRAW_NOOP
#define OODebugDrawBoundingBoxBetween(min, max)			OODRAW_NOOP
#define OODebugDrawNormal(position, normal, scale)		OODRAW_NOOP
#define OODebugDrawNormalAtOrigin(normal, scale)		OODRAW_NOOP
#define OODebugDrawVector(position, v)					OODRAW_NOOP
#define OODebugDrawColoredVector(position, v, color)	OODRAW_NOOP
#define OODebugDrawVectorAtOrigin(v)					OODRAW_NOOP
#define OODebugDrawColoredVectorAtOrigin(v, color)		OODRAW_NOOP
#define OODebugDrawBasis(position, scale)				OODRAW_NOOP
#define OODebugDrawBasisAtOrigin(scale)					OODRAW_NOOP

#endif	// OODEBUGLDRAWING_DISABLE
