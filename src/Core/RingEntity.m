//
//  RingEntity.m
/*
 *
 *  Oolite
 *
 *  Created by Giles Williams on Sat Apr 03 2004.
 *  Copyright (c) 2004 for aegidian.org. All rights reserved.
 *

Copyright (c) 2004, Giles C Williams
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

#import "RingEntity.h"
#import "entities.h"

#import "Universe.h"

@implementation RingEntity

// the vertex array data...
typedef struct
{
	Vector	vertex_array[64];
	GLfloat	color_array[4*64];
	GLuint	triangle_index_array[3*64];
}	Ringdata;

Ringdata	ringentity;

- (void) setLifetime:(double) amount
{
	lifetime = amount;
}

- (id) init
{    
	self = [super init];

	[self setModel:@"ring.dat"];
	
	// initialise the vertex arrays
	//
	int i;
	int ti = 0;
	GLfloat amb_diff1[] = { 1.0, 0.0, 0.0, 0.5};
	GLfloat amb_diff2[] = { 0.0, 0.0, 1.0, 0.25};
	for (i = 0; i < 64; i++)
	{
		ringentity.vertex_array[i] = vertices[i];
		ringentity.triangle_index_array[ti++] = faces[i].vertex[0];
		ringentity.triangle_index_array[ti++] = faces[i].vertex[1];
		ringentity.triangle_index_array[ti++] = faces[i].vertex[2];
		if (vertices[i].z < -20.0)
		{
			ringentity.color_array[i*4+0] = amb_diff1[0];
			ringentity.color_array[i*4+1] = amb_diff1[1];
			ringentity.color_array[i*4+2] = amb_diff1[2];
			ringentity.color_array[i*4+3] = amb_diff1[3];
		}
		else
		{
			ringentity.color_array[i*4+0] = amb_diff2[0];
			ringentity.color_array[i*4+1] = amb_diff2[1];
			ringentity.color_array[i*4+2] = amb_diff2[2];
			ringentity.color_array[i*4+3] = amb_diff2[3];
		}
	}
	//
	usingVAR = [self OGL_InitVAR];
	//
	if (usingVAR)
		[self OGL_AssignVARMemory:sizeof(Ringdata) :(void *)&ringentity :0];
	//
	////
	
	lifetime = 50.0;
	status = STATUS_EFFECT;
	
	velocity.x = 0.0;
	velocity.y = 0.0;
	velocity.z = 1.0;
	//
	isRing = YES;
	//
    return self;
}

- (void) update:(double) delta_t
{	
	if (usingVAR)
		[self OGL_UpdateVAR];
	
	[super update:delta_t];
			
    {
		double movement = RING_SPEED * delta_t;
		position.x -= movement * velocity.x; // swap out for setting a velocity vector
		position.y -= movement * velocity.y; // swap out for setting a velocity vector
		position.z -= movement * velocity.z; // swap out for setting a velocity vector
		lifetime -= movement;
		if (lifetime < 0.0)
		{
			//NSLog(@"removing ring %@ movement %.3f delta_t %.3f",self,movement,delta_t);
			[universe removeEntity:self];
		}
    }
}

- (void) drawEntity:(BOOL) immediate :(BOOL) translucent
{
	glShadeModel(GL_SMOOTH);
	glDisable(GL_LIGHTING);	
					
    //
	if ((translucent)||(immediate))
	{
		if (basefile)
		{
			//NSLog(@"Drawing ring : %@ n_faces %d, n_vertices %d", basefile, n_faces, n_vertices);
			if (immediate)
			{
#ifdef GNUSTEP
        // TODO: replace APPLE function call
#else           
				if (usingVAR)
					glBindVertexArrayAPPLE(gVertexArrayRangeObjects[0]);
#endif            
				
				glEnableClientState(GL_VERTEX_ARRAY);
				glVertexPointer( 3, GL_FLOAT, 0, ringentity.vertex_array);
				// 3 coords per vertex
				// of type GL_FLOAT
				// 0 stride (tightly packed)
				// pointer to first vertex

				glEnableClientState(GL_COLOR_ARRAY);
				glColorPointer( 4, GL_FLOAT, 0, ringentity.color_array);
				// 4 values per vertex color
				// of type GL_FLOAT
				// 0 stride (tightly packed)
				// pointer to quadruplet

				glDisableClientState(GL_NORMAL_ARRAY);
				glDisableClientState(GL_INDEX_ARRAY);
				glDisableClientState(GL_TEXTURE_COORD_ARRAY);
				glDisableClientState(GL_EDGE_FLAG_ARRAY);

				glDrawElements( GL_TRIANGLES, 3 * 64, GL_UNSIGNED_INT, ringentity.triangle_index_array);
			}
			else
			{
				if (displayListName != 0)
					glCallList(displayListName);
				else
					[self generateDisplayList];
			}
		}
	}
	glEnable(GL_LIGHTING);
	checkGLErrors([NSString stringWithFormat:@"RingEntity after drawing %@", self]);
}

- (BOOL) canCollide
{
	return NO;
}

@end
