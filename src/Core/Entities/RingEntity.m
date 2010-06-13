/*

RingEntity.m

Oolite
Copyright (C) 2004-2010 Giles C Williams and contributors

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
#import "OOMacroOpenGL.h"


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

- (id) initWithModelFile:(NSString *) ringModelFileName
{
	self = [super init];

	[self setModelName:ringModelFileName];
	
	// initialise the vertex arrays
	//
	OOColor *col1 = [OOColor colorWithCalibratedRed:1.0 green:0.0 blue:0.0 alpha:0.5];
	OOColor *col2 = [OOColor colorWithCalibratedRed:0.0 green:0.0 blue:1.0 alpha:0.25];
	[self setColors:col1 and:col2];
	
	lifetime = 50.0;
	[self setStatus:STATUS_EFFECT];
	
	velocity.x = 0.0;
	velocity.y = 0.0;
	velocity.z = 1.0;
	
	isRing = YES;
	isImmuneToBreakPatternHide = YES;
	
	return self;
}


- (void) setColors:(OOColor *) color1 and:(OOColor *) color2
{
	GLfloat amb_diff1[] = {[color1 redComponent], [color1 greenComponent], [color1 blueComponent], [color1 alphaComponent]};
	GLfloat amb_diff2[] = {[color2 redComponent], [color2 greenComponent], [color2 blueComponent], [color2 alphaComponent]};
	int i;
	int ti = 0;
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
}


- (void) update:(OOTimeDelta) delta_t
{
	[super update:delta_t];
	
	double movement = RING_SPEED * delta_t;
	position = vector_subtract(position, vector_multiply_scalar(velocity, movement)); // swap out for setting a velocity vector
	lifetime -= movement;
	if (lifetime < 0.0)
	{
		[UNIVERSE removeEntity:self];
	}
}


- (void) drawEntity:(BOOL)immediate :(BOOL)translucent
{
	OO_ENTER_OPENGL();
	
	OOGL(glPushAttrib(GL_ENABLE_BIT));
	
	OOGL(glShadeModel(GL_SMOOTH));
	OOGL(glDisable(GL_LIGHTING));	
	
	if (translucent || immediate)
	{
		if (basefile)
		{
			if (immediate)
			{
				OOGL(glEnableClientState(GL_VERTEX_ARRAY));
				OOGL(glVertexPointer( 3, GL_FLOAT, 0, ringentity.vertex_array));
				// 3 coords per vertex
				// of type GL_FLOAT
				// 0 stride (tightly packed)
				// pointer to first vertex

				OOGL(glEnableClientState(GL_COLOR_ARRAY));
				OOGL(glColorPointer( 4, GL_FLOAT, 0, ringentity.color_array));
				// 4 values per vertex color
				// of type GL_FLOAT
				// 0 stride (tightly packed)
				// pointer to quadruplet

				OOGL(glDisableClientState(GL_NORMAL_ARRAY));
				OOGL(glDisableClientState(GL_TEXTURE_COORD_ARRAY));
				OOGL(glDisableClientState(GL_EDGE_FLAG_ARRAY));

				OOGL(glDrawElements(GL_TRIANGLES, 3 * 64, GL_UNSIGNED_INT, ringentity.triangle_index_array));
				
				OOGL(glDisableClientState(GL_VERTEX_ARRAY));
				OOGL(glDisableClientState(GL_COLOR_ARRAY));
			}
			else
			{
				if (displayListName != 0)
				{
					OOGL(glCallList(displayListName));
				}
				else
				{
					[self generateDisplayList];
				}
			}
		}
	}
	
	OOGL(glPopAttrib());
	CheckOpenGLErrors(@"RingEntity after drawing %@", self);
}


- (BOOL) canCollide
{
	return NO;
}

@end
