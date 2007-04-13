/*

RingEntity.m

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

#import "RingEntity.h"

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

	[self setModelName:@"ring.dat"];
	
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
			[UNIVERSE removeEntity:self];
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
			if (immediate)
			{
#if GL_APPLE_vertex_array_object
				if (usingVAR)  glBindVertexArrayAPPLE(gVertexArrayRangeObjects[0]);
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
	CheckOpenGLErrors([NSString stringWithFormat:@"RingEntity after drawing %@", self]);
}

- (BOOL) canCollide
{
	return NO;
}

@end
