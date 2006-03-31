//
//  SkyEntity.m
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

#define SKY_SCALE	2000.0

#import "Entity.h"
#import "SkyEntity.h"

#import "vector.h"
#import "Universe.h"
#import "TextureStore.h"
#import "MyOpenGLView.h"
#import "OOColor.h"

@implementation SkyEntity

- (id) init
{    
    self = [super init];
    //
    quaternion_set_identity(&q_rotation);
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
    //
    position.x = 0.0;
    position.y = 0.0;
    position.z = 0.0;
    //
    n_vertices = 0;
    n_faces = 0;
	delta = 0.0;
    //
    displayListName = 0;
    //
    status = STATUS_EFFECT;
	sky_type = SKY_BILLBOARDS;
	//
	float h1 = (ranrot_rand() % 1024)/1024.0;
	float h2 = h1 + 1.0 / (1.0 + (ranrot_rand() % 5));
	while (h2 > 1.0)
		h2 -= 1.0;
	OOColor *col1 = [OOColor colorWithCalibratedHue:h1 saturation:(ranrot_rand() % 1024)/1024.0 brightness:0.5 +(ranrot_rand() % 1024)/2048.0 alpha:1.0];
	OOColor *col2 = [OOColor colorWithCalibratedHue:h2 saturation:0.5 +(ranrot_rand() % 1024)/2048.0 brightness:0.5 +(ranrot_rand() % 1024)/2048.0 alpha:1.0];
	//
	sky_color = [[col2 blendedColorWithFraction:0.5 ofColor:col1] retain];
	//
	// init stars
	//
	[self set_up_billboards:col1 :col2];
	//
	
	//
	usingVAR = [self OGL_InitVAR];
	//
	if (usingVAR)
	{
		[self OGL_AssignVARMemory:sizeof(SkyStarsData) :(void *)&starsData :0];
		[self OGL_AssignVARMemory:sizeof(SkyBlobsData) :(void *)&blobsData :1];
	}
	//
	isSky = YES;
	//
    return self;
}

- (id) initWithColors:(OOColor *) col1:(OOColor *) col2
{    
    self = [super init];
	//
	n_stars = SKY_N_STARS;
	n_blobs = SKY_N_BLOBS;
    //
    quaternion_set_identity(&q_rotation);
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
    //
    position.x = 0.0;
    position.y = 0.0;
    position.z = 0.0;
    //
    n_vertices = 0;
    n_faces = 0;
	delta = 0.0;
    //
    displayListName = 0;
    //
    status = STATUS_EFFECT;
	sky_type = SKY_BILLBOARDS;
	//
	sky_color = [[col2 blendedColorWithFraction:0.5 ofColor:col1] retain];
	//
	// init stars
	//
	blob_cluster_chance = SKY_BLOB_CLUSTER_CHANCE;
	blob_alpha = SKY_BLOB_ALPHA;
	blob_scale = SKY_BLOB_SCALE;
	blob_scale_prime = 0.005 / blob_scale;
	//
	[self set_up_billboards:col1 :col2];
	//

	//
	usingVAR = [self OGL_InitVAR];
	//
	if (usingVAR)
	{
		[self OGL_AssignVARMemory:sizeof(SkyStarsData) :(void *)&starsData :0];
		[self OGL_AssignVARMemory:sizeof(SkyBlobsData) :(void *)&blobsData :1];
	}
	//
	isSky = YES;
	//
    return self;
}

- (id) initWithColors:(OOColor *) col1:(OOColor *) col2 andSystemInfo:(NSDictionary *) systeminfo
{    
	OOColor* color1 = col1;
	OOColor* color2 = col2;
	
	self = [super init];
	//
	n_stars = SKY_N_STARS;
	n_blobs = SKY_N_BLOBS;
    //
    quaternion_set_identity(&q_rotation);
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
    //
    position.x = 0.0;
    position.y = 0.0;
    position.z = 0.0;
    //
    n_vertices = 0;
    n_faces = 0;
	delta = 0.0;
    //
    displayListName = 0;
    //
    status = STATUS_EFFECT;
	sky_type = SKY_BILLBOARDS;
	//
	blob_cluster_chance = SKY_BLOB_CLUSTER_CHANCE;
	blob_alpha = SKY_BLOB_ALPHA;
	blob_scale = SKY_BLOB_SCALE;
	blob_scale_prime = 0.005 / blob_scale;
	//
	
	//// possible systeminfo overrides
	//
	if ([systeminfo objectForKey:@"sky_rgb_colors"])
	{
		NSString*   value = (NSString *)[systeminfo objectForKey:@"sky_rgb_colors"];
		NSArray*	tokens = [Entity scanTokensFromString:value];
		if ([tokens count] == 6)
		{
			float r1 = [(NSString *)[tokens objectAtIndex:0] floatValue];
			float g1 = [(NSString *)[tokens objectAtIndex:1] floatValue];
			float b1 = [(NSString *)[tokens objectAtIndex:2] floatValue];
			float r2 = [(NSString *)[tokens objectAtIndex:3] floatValue];
			float g2 = [(NSString *)[tokens objectAtIndex:4] floatValue];
			float b2 = [(NSString *)[tokens objectAtIndex:5] floatValue];
		color1 = [OOColor colorWithCalibratedRed:r1 green:g1 blue:b1 alpha:1.0];
		color2 = [OOColor colorWithCalibratedRed:r2 green:g2 blue:b2 alpha:1.0];
		}
	}
	if ([systeminfo objectForKey:@"sky_blur_cluster_chance"])
	{
		NSNumber*   value = (NSNumber *)[systeminfo objectForKey:@"sky_blur_cluster_chance"];
		blob_cluster_chance = [value doubleValue];
	}
	if ([systeminfo objectForKey:@"sky_blur_alpha"])
	{
		NSNumber*   value = (NSNumber *)[systeminfo objectForKey:@"sky_blur_alpha"];
		blob_alpha = [value doubleValue];
	}
	if ([systeminfo objectForKey:@"sky_blur_scale"])
	{
		NSNumber*   value = (NSNumber *)[systeminfo objectForKey:@"sky_blur_scale"];
		blob_scale = [value doubleValue];
	}
	//
	if ([systeminfo objectForKey:@"sky_n_stars"])
	{
		NSNumber*   value = (NSNumber *)[systeminfo objectForKey:@"sky_n_stars"];
		n_stars = [value doubleValue];
		if (n_stars < 0)
			n_stars = 0;
		if (n_stars > SKY_MAX_STARS)
			n_stars = SKY_MAX_STARS;
	}
	else
	{
		n_stars = SKY_MAX_STARS * 0.5 * randf() * randf();	// around 0.125
	}
	//
	if ([systeminfo objectForKey:@"sky_n_blurs"])
	{
		NSNumber*   value = (NSNumber *)[systeminfo objectForKey:@"sky_n_blurs"];
		n_blobs = [value doubleValue];
		if (n_blobs < 0)
			n_blobs = 0;
		if (n_blobs > SKY_MAX_BLOBS)
			n_blobs = SKY_MAX_BLOBS;
	}
	else
	{
		n_blobs = SKY_MAX_BLOBS * 0.4 * randf() * randf();	// around 0.10
	}
	//
	////
	
	sky_color = [[color2 blendedColorWithFraction:0.5 ofColor:color1] retain];
	//
	// init stars
	//
	[self set_up_billboards:color1 :color2];
	
	//
	usingVAR = [self OGL_InitVAR];
	//
	if (usingVAR)
	{
		[self OGL_AssignVARMemory:sizeof(SkyStarsData) :(void *)&starsData :0];
		[self OGL_AssignVARMemory:sizeof(SkyBlobsData) :(void *)&blobsData :1];
	}
	//
	isSky = YES;
	//
    return self;
}

- (id) initAsWitchspace
{
    self = [super init];
    //
	n_stars = SKY_N_STARS;
	n_blobs = SKY_N_BLOBS;
	//
    quaternion_set_identity(&q_rotation);
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
    //
    position.x = 0.0;
    position.y = 0.0;
    position.z = 0.0;
    //
    n_vertices = 0;
    n_faces = 0;
	delta = 0.0;
    //
    displayListName = 0;
    //
    status = STATUS_EFFECT;
	sky_type = SKY_BILLBOARDS;
    //
	OOColor *col1 = [OOColor colorWithCalibratedRed:0.0 green:1.0 blue:0.5 alpha:1.0];
	OOColor *col2 = [OOColor colorWithCalibratedRed:0.0 green:1.0 blue:0.0 alpha:1.0];
	//
	sky_color = [[col2 blendedColorWithFraction:0.5 ofColor:col1] retain];
	//
	// init stars
	//
	blob_cluster_chance = SKY_BLOB_CLUSTER_CHANCE;
	blob_alpha = SKY_BLOB_ALPHA;
	blob_scale = SKY_BLOB_SCALE;
	blob_scale_prime = 0.005 / blob_scale;
	//
	[self set_up_billboards:col1 :col2];
	//

	//
	usingVAR = [self OGL_InitVAR];
	//
	if (usingVAR)
	{
		[self OGL_AssignVARMemory:sizeof(SkyStarsData) :(void *)&starsData :0];
		[self OGL_AssignVARMemory:sizeof(SkyBlobsData) :(void *)&blobsData :1];
	}
	//
	isSky = YES;
	//
    return self;
}

- (void) set_up_billboards:(OOColor *) col1:(OOColor *) col2
{
	// stars
	Vector  star_vector[n_stars];
	GLfloat star_color[n_stars][4];
	Vector  star_quad[4][n_stars];
	
	// blobs
	Vector  blob_vector[n_blobs];
	GLfloat blob_color[n_blobs][4];
	Vector  blob_quad[4][n_blobs];

	int i;
	//
	// init stars
	//
	for (i = 0; i < n_stars; i++)
	{
		OOColor *col3 = [col1 blendedColorWithFraction:(ranrot_rand() % 1024)/1024.0 ofColor:col2];
		star_color[i][0] = [col3 redComponent];
		star_color[i][1] = [col3 greenComponent];
		star_color[i][2] = [col3 blueComponent];
		star_color[i][3] = 1.0;
		Quaternion q;
		quaternion_set_random(&q);
		Vector vi = vector_right_from_quaternion(q);
		Vector vj = vector_up_from_quaternion(q);
		Vector vk = vector_forward_from_quaternion(q);
		star_vector[i] = vk;
		star_vector[i].x *= BILLBOARD_DEPTH;
		star_vector[i].y *= BILLBOARD_DEPTH;
		star_vector[i].z *= BILLBOARD_DEPTH;
		double p_size = (1 + (ranrot_rand() % 6)) * BILLBOARD_DEPTH / 500.0;
		star_quad[0][i] = star_vector[i];
		star_quad[1][i].x = star_quad[0][i].x + p_size * vj.x;
		star_quad[1][i].y = star_quad[0][i].y + p_size * vj.y;
		star_quad[1][i].z = star_quad[0][i].z + p_size * vj.z;
		star_quad[2][i].x = star_quad[1][i].x + p_size * vi.x;
		star_quad[2][i].y = star_quad[1][i].y + p_size * vi.y;
		star_quad[2][i].z = star_quad[1][i].z + p_size * vi.z;
		star_quad[3][i].x = star_quad[0][i].x + p_size * vi.x;
		star_quad[3][i].y = star_quad[0][i].y + p_size * vi.y;
		star_quad[3][i].z = star_quad[0][i].z + p_size * vi.z;
		
		int j;
		for (j = 0; j < 4; j++)
		{
			star_quad[j][i].x -= 0.5 * p_size * (vi.x + vj.x);
			star_quad[j][i].y -= 0.5 * p_size * (vi.y + vj.y);
			star_quad[j][i].z -= 0.5 * p_size * (vi.z + vj.z);
		}

		//**  SET UP VERTEX ARRAY DATA **//
				
		// set up texture and vertex arrays
		starsData.texture_uv_array[ 4*i*2 + 0] = 0;	starsData.texture_uv_array[ 4*i*2 + 1] = 0;
		starsData.vertex_array[ 4*i*3 + 0] = star_quad[0][i].x;	starsData.vertex_array[ 4*i*3 + 1] = star_quad[0][i].y;	starsData.vertex_array[ 4*i*3 + 2] = star_quad[0][i].z;
		starsData.texture_uv_array[ 4*i*2 + 2] = 1;	starsData.texture_uv_array[ 4*i*2 + 3] = 0;
		starsData.vertex_array[ 4*i*3 + 3] = star_quad[1][i].x;	starsData.vertex_array[ 4*i*3 + 4] = star_quad[1][i].y;	starsData.vertex_array[ 4*i*3 + 5] = star_quad[1][i].z;
		starsData.texture_uv_array[ 4*i*2 + 4] = 1;	starsData.texture_uv_array[ 4*i*2 + 5] = 1;
		starsData.vertex_array[ 4*i*3 + 6] = star_quad[2][i].x;	starsData.vertex_array[ 4*i*3 + 7] = star_quad[2][i].y;	starsData.vertex_array[ 4*i*3 + 8] = star_quad[2][i].z;
		starsData.texture_uv_array[ 4*i*2 + 6] = 0;	starsData.texture_uv_array[ 4*i*2 + 7] = 1;
		starsData.vertex_array[ 4*i*3 + 9] = star_quad[3][i].x;	starsData.vertex_array[ 4*i*3 + 10] = star_quad[3][i].y;	starsData.vertex_array[ 4*i*3 + 11] = star_quad[3][i].z;
		
		// set up color array
		for (j = 0; j < 4; j++)
		{
			starsData.color_array[ 4*i*4 + j*4 + 0] = star_color[i][0];
			starsData.color_array[ 4*i*4 + j*4 + 1] = star_color[i][1];
			starsData.color_array[ 4*i*4 + j*4 + 2] = star_color[i][2];
			starsData.color_array[ 4*i*4 + j*4 + 3] = star_color[i][3];
		}

	}
	star_textureName = 0;
	//
	//
	// init blobs
	//
	for (i = 0; i < n_blobs; i++)
	{
		OOColor *col3 = [col1 blendedColorWithFraction:(ranrot_rand() % 1024)/1024.0 ofColor:col2];
		float hu, sa, br, al;
		[col3 getHue:&hu saturation:&sa brightness:&br alpha:&al];
		sa = 0.5 * sa + 0.5;	// move saturation up a notch!
		//br = 0.5 * br + 0.5;	// move brightness up a notch!
		col3 = [OOColor colorWithCalibratedHue:hu saturation:sa brightness:br alpha:al];
		Quaternion q;
		quaternion_set_random(&q);
		while ((i < n_blobs)&&(randf() < blob_cluster_chance))
		{
			Vector vi = vector_right_from_quaternion(q);
			Vector vj = vector_up_from_quaternion(q);
			Vector vk = vector_forward_from_quaternion(q);
			blob_color[i][0] = [col3 redComponent];
			blob_color[i][1] = [col3 greenComponent];
			blob_color[i][2] = [col3 blueComponent];
			blob_color[i][3] = blob_alpha;
			blob_vector[i] = vk;
			blob_vector[i].x *= BILLBOARD_DEPTH;
			blob_vector[i].y *= BILLBOARD_DEPTH;
			blob_vector[i].z *= BILLBOARD_DEPTH;
			int r1 = 1 + (ranrot_rand() & 15);
			double p_size = blob_scale * r1 * BILLBOARD_DEPTH / 500.0;
			blob_color[i][3] *= 0.5 + (float)r1 / 32.0;	// make smaller blobs dimmer
			blob_quad[0][i] = blob_vector[i];
			
			// rotate vi and vj a random amount
			double r = randf() * PI * 2.0;
			quaternion_rotate_about_axis(&q, vk, r);
			vi = vector_right_from_quaternion(q);
			vj = vector_up_from_quaternion(q);
			//
			
			blob_quad[1][i].x = blob_quad[0][i].x + p_size * vj.x;
			blob_quad[1][i].y = blob_quad[0][i].y + p_size * vj.y;
			blob_quad[1][i].z = blob_quad[0][i].z + p_size * vj.z;
			blob_quad[2][i].x = blob_quad[1][i].x + p_size * vi.x;
			blob_quad[2][i].y = blob_quad[1][i].y + p_size * vi.y;
			blob_quad[2][i].z = blob_quad[1][i].z + p_size * vi.z;
			blob_quad[3][i].x = blob_quad[0][i].x + p_size * vi.x;
			blob_quad[3][i].y = blob_quad[0][i].y + p_size * vi.y;
			blob_quad[3][i].z = blob_quad[0][i].z + p_size * vi.z;
			
			int j;
			for (j = 0; j < 4; j++)
			{
				blob_quad[j][i].x -= 0.5 * p_size * (vi.x + vj.x);
				blob_quad[j][i].y -= 0.5 * p_size * (vi.y + vj.y);
				blob_quad[j][i].z -= 0.5 * p_size * (vi.z + vj.z);
			}
			
			//**  SET UP VERTEX ARRAY DATA **//
			
			// set up texture and vertex arrays
			blobsData.texture_uv_array[ 4*i*2 + 0] = 0;	blobsData.texture_uv_array[ 4*i*2 + 1] = 0;
			blobsData.vertex_array[ 4*i*3 + 0] = blob_quad[0][i].x;	blobsData.vertex_array[ 4*i*3 + 1] = blob_quad[0][i].y;	blobsData.vertex_array[ 4*i*3 + 2] = blob_quad[0][i].z;
			blobsData.texture_uv_array[ 4*i*2 + 2] = 1;	blobsData.texture_uv_array[ 4*i*2 + 3] = 0;
			blobsData.vertex_array[ 4*i*3 + 3] = blob_quad[1][i].x;	blobsData.vertex_array[ 4*i*3 + 4] = blob_quad[1][i].y;	blobsData.vertex_array[ 4*i*3 + 5] = blob_quad[1][i].z;
			blobsData.texture_uv_array[ 4*i*2 + 4] = 1;	blobsData.texture_uv_array[ 4*i*2 + 5] = 1;
			blobsData.vertex_array[ 4*i*3 + 6] = blob_quad[2][i].x;	blobsData.vertex_array[ 4*i*3 + 7] = blob_quad[2][i].y;	blobsData.vertex_array[ 4*i*3 + 8] = blob_quad[2][i].z;
			blobsData.texture_uv_array[ 4*i*2 + 6] = 0;	blobsData.texture_uv_array[ 4*i*2 + 7] = 1;
			blobsData.vertex_array[ 4*i*3 + 9] = blob_quad[3][i].x;	blobsData.vertex_array[ 4*i*3 + 10] = blob_quad[3][i].y;	blobsData.vertex_array[ 4*i*3 + 11] = blob_quad[3][i].z;
			
			// set up color array
			for (j = 0; j < 4; j++)
			{
				blobsData.color_array[ 4*i*4 + j*4 + 0] = blob_color[i][0];
				blobsData.color_array[ 4*i*4 + j*4 + 1] = blob_color[i][1];
				blobsData.color_array[ 4*i*4 + j*4 + 2] = blob_color[i][2];
				blobsData.color_array[ 4*i*4 + j*4 + 3] = blob_color[i][3];
			}

			p_size *= 500/BILLBOARD_DEPTH;	// back to normal scale
			
			// shuffle it around a bit in a random walk
			q.x += p_size * blob_scale_prime * (randf() - 0.5);
			q.y += p_size * blob_scale_prime * (randf() - 0.5);
			q.z += p_size * blob_scale_prime * (randf() - 0.5);
			q.w += p_size * blob_scale_prime * (randf() - 0.5);
			quaternion_normalise(&q);
			i++;


		}
	}
	blob_textureName = 0;
	//
}

- (void) dealloc
{
	if (sky_color)  [sky_color release];
	[super dealloc];
}

- (OOColor *) sky_color
{
	return sky_color;
}

- (void) update:(double) delta_t
{
	if (usingVAR)
		[self OGL_UpdateVAR];
	Entity* player = [universe entityZero];
	zero_distance = MAX_CLEAR_DEPTH * MAX_CLEAR_DEPTH;
	position = (player)? player->position : position;
}

- (BOOL) canCollide
{
	return NO;
}

- (void) drawEntity:(BOOL) immediate :(BOOL) translucent
{    
	if ([universe breakPatternHide])   return; // DON'T DRAW

    //
    if (!translucent)
	{
		// disapply lighting
		glDisable(GL_LIGHTING);
		glDisable(GL_DEPTH_TEST);	// don't read the depth buffer
		glDepthMask(GL_FALSE);		// don't write to depth buffer
		glDisable(GL_CULL_FACE);	// face culling
		//
		glShadeModel(GL_SMOOTH);	// smoothing for color values...
										
		if (immediate)
		{
			switch (sky_type)
			{
				case SKY_POINTS :
					NSLog(@"ERROR: SkyEntity SKY_POINTS deprecated");
					break;
					
				case SKY_BILLBOARDS :
					
					if ((star_textureName == 0)&&(universe))
						star_textureName = [[universe textureStore] getTextureNameFor:@"star64.png"];
					if ((blob_textureName == 0)&&(universe))
						blob_textureName = [[universe textureStore] getTextureNameFor:@"galaxy256.png"];
					//
					glEnable(GL_TEXTURE_2D);
					glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
					//
					// stars
#ifdef GNUSTEP
               // TODO: find replacement for APPLE function
#else               
					if (usingVAR)
						glBindVertexArrayAPPLE(gVertexArrayRangeObjects[0]);
#endif               
					
//					if (usingVAR)
//						NSLog(@"DEBUG using accelerated memory technique to draw %@ (%@)", self, basefile);
//					
					glBindTexture(GL_TEXTURE_2D, star_textureName);
					
					glEnableClientState(GL_VERTEX_ARRAY);
					glVertexPointer( 3, GL_FLOAT, 0, starsData.vertex_array);
					// 3 coords per vertex
					// of type GL_FLOAT
					// 0 stride (tightly packed)
					// pointer to first vertex
					
					glEnableClientState(GL_TEXTURE_COORD_ARRAY);
					glTexCoordPointer( 2, GL_INT, 0, starsData.texture_uv_array);
					// 2 coords per vertex
					// of type GL_INT
					// 0 stride (tightly packed)
					// pointer to first coordinate pair
					
					glEnableClientState(GL_COLOR_ARRAY);
					glColorPointer( 4, GL_FLOAT, 0, starsData.color_array);
					// 4 values per vertex color
					// of type GL_FLOAT
					// 0 stride (tightly packed)
					// pointer to quadruplet
					
					glDisableClientState(GL_INDEX_ARRAY);
					glDisableClientState(GL_NORMAL_ARRAY);
					glDisableClientState(GL_EDGE_FLAG_ARRAY);
					
					glDrawArrays( GL_QUADS, 0, 4 * n_stars);
					
					//
					// blobs
					if (![universe reducedDetail])
					{
						glBindTexture(GL_TEXTURE_2D, blob_textureName);
#ifdef GNUSTEP
                  // TODO: Find replacement for APPLE fncall
#else
						if (usingVAR)
							glBindVertexArrayAPPLE(gVertexArrayRangeObjects[1]);
#endif                  
						
						glEnableClientState(GL_VERTEX_ARRAY);
						glVertexPointer( 3, GL_FLOAT, 0, blobsData.vertex_array);
						// 3 coords per vertex
						// of type GL_FLOAT
						// 0 stride (tightly packed)
						// pointer to first vertex
						
						glEnableClientState(GL_TEXTURE_COORD_ARRAY);
						glTexCoordPointer( 2, GL_INT, 0, blobsData.texture_uv_array);
						// 2 coords per vertex
						// of type GL_INT
						// 0 stride (tightly packed)
						// pointer to first coordinate pair
						
						glEnableClientState(GL_COLOR_ARRAY);
						glColorPointer( 4, GL_FLOAT, 0, blobsData.color_array);
						// 4 values per vertex color
						// of type GL_FLOAT
						// 0 stride (tightly packed)
						// pointer to quadruplet
						
						glDisableClientState(GL_INDEX_ARRAY);
						glDisableClientState(GL_NORMAL_ARRAY);
						glDisableClientState(GL_EDGE_FLAG_ARRAY);
						
						glDrawArrays( GL_QUADS, 0, 4 * n_blobs);

					}
					glDisable(GL_TEXTURE_2D);
					break;
			}
		}
		else
		{
			if (displayListName != 0)
				glCallList(displayListName);
			else
			{
				[self initialiseTextures];
				[self generateDisplayList];
				//
			}
		}
		
		// reapply lighting &c
		glEnable(GL_CULL_FACE);			// face culling
		glEnable(GL_LIGHTING);
		glEnable(GL_DEPTH_TEST);	// read the depth buffer
		glDepthMask(GL_TRUE);	// restore write to depth buffer
	}
	checkGLErrors([NSString stringWithFormat:@"SkyEntity after drawing %@", self]);
}





@end
