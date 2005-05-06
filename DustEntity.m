//
//  DustEntity.m
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

#import "DustEntity.h"
#import "entities.h"

#import "vector.h"
#import "Universe.h"
#import "MyOpenGLView.h"

@implementation DustEntity

- (id) init
{
    int vi;

    ranrot_srand([[NSDate date] timeIntervalSince1970]);	// seed randomiser by time
    
    self = [super init];
    //
    quaternion_set_identity(&q_rotation);
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
    //
    position.x = 0.0;
    position.y = 0.0;
    position.z = 0.0;
    //
    n_vertices = DUST_N_PARTICLES;
    n_faces = 0;
	//
	for (vi = 0; vi < n_vertices; vi++)
	{
		vertices[vi].x = (ranrot_rand() % DUST_SCALE) - DUST_SCALE / 2;
		vertices[vi].y = (ranrot_rand() % DUST_SCALE) - DUST_SCALE / 2;
		vertices[vi].z = (ranrot_rand() % DUST_SCALE) - DUST_SCALE / 2;
	}
	//NSLog(@"DustEntity vertices set");
	//
	dust_color = [[NSColor colorWithCalibratedRed:0.5 green:1.0 blue:1.0 alpha:1.0] retain];
    //
    displayListName = 0;
    //
    status = STATUS_TEST;
    //
    return self;
}

- (void) dealloc
{
	if (dust_color) [dust_color release];
	[super dealloc];
}

- (void) setDustColor:(NSColor *) color
{
	if (dust_color) [dust_color release];
	dust_color = [color retain];
}

- (NSColor *) dust_color
{
	return dust_color;
}

- (BOOL) canCollide
{
	return NO;
}

- (void) update:(double) delta_t
{
	// do nowt!
	zero_distance = 0.0;
}

- (void) drawEntity:(BOOL) immediate :(BOOL) translucent
{
    // roll out vertex in turn
    //
    int ct;
	int vi;
	Vector  offset;
    GLfloat *fogcolor = [universe sky_clear_color];
	int  dust_size = floor([(MyOpenGLView *)[universe gameView] viewSize].width / 480.0);
	if (dust_size < 1.0)
		dust_size = 1.0;
	int  line_size = dust_size / 2;
	if (line_size < 1.0)
		line_size = 1.0;
	double  half_scale = DUST_SCALE * 0.50;
	double  quarter_scale = DUST_SCALE * 0.25;
	BOOL	warp_stars = [(PlayerEntity *)[universe entityZero] atHyperspeed];
	Vector  warp_vector = [(PlayerEntity *)[universe entityZero] velocityVector];
	
	if ([universe breakPatternHide])   return; // DON'T DRAW

	if (translucent)
	{
		Entity* player = [universe entityZero];
		glEnable(GL_FOG);
		glFogi(GL_FOG_MODE, GL_LINEAR);
		glFogfv(GL_FOG_COLOR, fogcolor);
		glHint(GL_FOG_HINT, GL_NICEST);
		glFogf(GL_FOG_START, quarter_scale);
		glFogf(GL_FOG_END, half_scale);
		//
		// disapply lighting
		glDisable(GL_LIGHTING);
		
		glEnable(GL_SMOOTH);
		
		glColor4f([dust_color redComponent], [dust_color greenComponent], [dust_color blueComponent], [dust_color alphaComponent]);
		
		ct = 0;
		
		glPushMatrix();
		
		offset = (player)? player->position: position;
		
		if (!warp_stars)
		{
			glEnable(GL_POINT_SMOOTH);
			glPointSize(dust_size);
			glBegin(GL_POINTS);
		}
		else
		{
			//glEnable(GL_LINE_SMOOTH);
			glLineWidth(line_size);
			glBegin(GL_LINES);
		}
		for (vi = 0; vi < n_vertices; vi++)
		{
			
			while (vertices[vi].x - offset.x < -half_scale)
				vertices[vi].x += DUST_SCALE;
			while (vertices[vi].x - offset.x > half_scale)
				vertices[vi].x -= DUST_SCALE;
			
			while (vertices[vi].y - offset.y < -half_scale)
				vertices[vi].y += DUST_SCALE;
			while (vertices[vi].y - offset.y > half_scale)
				vertices[vi].y -= DUST_SCALE;
			
			while (vertices[vi].z - offset.z < -half_scale)
				vertices[vi].z += DUST_SCALE;
			while (vertices[vi].z - offset.z > half_scale)
				vertices[vi].z -= DUST_SCALE;
						
			glVertex3f(vertices[vi].x, vertices[vi].y, vertices[vi].z);
			if (warp_stars)
				glVertex3f(vertices[vi].x-warp_vector.x/HYPERSPEED_FACTOR, vertices[vi].y-warp_vector.y/HYPERSPEED_FACTOR, vertices[vi].z-warp_vector.z/HYPERSPEED_FACTOR);
		}
		glEnd();
		
		glPopMatrix();
				
		// reapply lighting etc.
		glEnable(GL_LIGHTING);
		glDisable(GL_FOG);
	}
}

@end
