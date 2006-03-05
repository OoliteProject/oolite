/*

	Oolite

	Geometry.h
	
	Created by Giles Williams on 30/01/2006.


Copyright (c) 2005, Giles C Williams
All rights reserved.

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Noncommercial. You may not use this work for commercial purposes.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

#import "OOCocoa.h"

#import "vector.h"

@class ShipEntity, Octree;

@interface Geometry : NSObject
{
	// a geometry essentially consists of a whole bunch of Triangles.
	int			n_triangles;			// how many triangles in the geometry
	int			max_triangles;			// how many triangles are allowed in the geometry before expansion
	Triangle*	triangles;				// pointer to an array of triangles which we'll grow as necessary...
	BOOL		isConvex;				// set at initialisation to NO
}

- (id) initWithCapacity:(int) amount;

- (BOOL) isConvex;
- (void) setConvex:(BOOL) value;

- (void) addTriangle:(Triangle) tri;

- (BOOL) testHasGeometry;
- (BOOL) testIsConvex;
- (BOOL) testCornersWithinGeometry:(GLfloat) corner;
- (GLfloat) findMaxDimensionFromOrigin;

- (Octree*) findOctreeToDepth: (int) depth;
- (NSObject*) octreeWithinRadius:(GLfloat) octreeRadius toDepth: (int) depth;

- (void) translate:(Vector) offset;
- (void) scale:(GLfloat) scalar;

- (void) x_axisSplitBetween:(Geometry*) g_plus :(Geometry*) g_minus :(GLfloat) x;
- (void) y_axisSplitBetween:(Geometry*) g_plus :(Geometry*) g_minus :(GLfloat) y;
- (void) z_axisSplitBetween:(Geometry*) g_plus :(Geometry*) g_minus :(GLfloat) z;

@end
