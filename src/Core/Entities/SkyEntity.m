/*

SkyEntity.m

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


#import "SkyEntity.h"
#import "PlayerEntity.h"

#import "OOMaths.h"
#import "Universe.h"
#import "MyOpenGLView.h"
#import "OOColor.h"
#import "OOStringParsing.h"
#import "OOTexture.h"
#import "OOCollectionExtractors.h"
#import "OOGraphicsResetManager.h"


#define MULTI_TEXTURE_BLOBS		0		// Not fully implemented yet


static BOOL				sLoadedTextures = NO;
static OOTexture		*sStarTexture, *sBlobTexture;


@interface SkyEntity (OOPrivate) <OOGraphicsResetClient>

- (void)readColor1:(OOColor **)ioColor1 andColor2:(OOColor **)ioColor2 fromDictionary:(NSDictionary *)dictionary;

- (void)setUpStarsWithColor1:(OOColor *)color1 color2:(OOColor *)color2;
- (void)setUpBlobsWithColor1:(OOColor *)color1 color2:(OOColor *)color2;

- (void)generateDisplayList;

- (void)loadTextures;
- (void)ensureTexturesLoaded;

@end


@implementation SkyEntity

- (id) initWithColors:(OOColor *) col1:(OOColor *) col2 andSystemInfo:(NSDictionary *) systemInfo
{
    self = [super init];
	if (self == nil)  return nil;
	
	if (!sLoadedTextures)  [self loadTextures];
	
	// Load colours
	[self readColor1:&col1 andColor2:&col2 fromDictionary:systemInfo];
	sky_color = [[col2 blendedColorWithFraction:0.5 ofColor:col1] retain];
	
	// Load distribution values
	blob_cluster_chance = [systemInfo floatForKey:@"sky_blur_cluster_chance" defaultValue:SKY_BLOB_CLUSTER_CHANCE];
	blob_alpha = [systemInfo floatForKey:@"sky_blur_alpha" defaultValue:SKY_BLOB_ALPHA];
	blob_scale = [systemInfo floatForKey:@"sky_blur_scale" defaultValue:SKY_BLOB_SCALE];
	
	blob_scale_prime = 0.005 / blob_scale;
	
	// Load star count
	n_stars = [systemInfo floatForKey:@"sky_n_stars" defaultValue:-1];
	if (0 <= n_stars)
	{
		n_stars = MIN(SKY_MAX_STARS, n_stars);
	}
	else
	{
		n_stars = SKY_MAX_STARS * 0.5 * randf() * randf();
	}
	
	// ...and sky count. (Note: simplifying this would change the appearance of stars/blobs.)
	n_blobs = [systemInfo floatForKey:@"sky_n_blurs" defaultValue:-1];
	if (0 <= n_blobs)
	{
		n_blobs = MIN(SKY_MAX_BLOBS, n_stars);
	}
	else
	{
		n_blobs = SKY_MAX_BLOBS * 0.5 * randf() * randf();
	}
	
	// init stars and blobs
	[self setUpStarsWithColor1:col1 color2:col2];
	[self setUpBlobsWithColor1:col1 color2:col2];
	
    status = STATUS_EFFECT;
	isSky = YES;
	
	[[OOGraphicsResetManager sharedManager] registerClient:self];
	
    return self;
}


- (id) initAsWitchspace
{
	NSDictionary *info = [[UNIVERSE planetinfo] objectForKey:@"interstellar space!"];
	
	return [self initWithColors:nil :nil andSystemInfo:info];
}


- (void) dealloc
{
	[sky_color release];
	
	[[OOGraphicsResetManager sharedManager] unregisterClient:self];
	glDeleteLists(displayListName, 1);
	
	[super dealloc];
}


- (OOColor *) sky_color
{
	return sky_color;
}


- (void) update:(double) delta_t
{
	PlayerEntity *player = [PlayerEntity sharedPlayer];
	zero_distance = MAX_CLEAR_DEPTH * MAX_CLEAR_DEPTH;
	position = (player)? player->position : position;
}


- (BOOL) canCollide
{
	return NO;
}


- (void) drawEntity:(BOOL) immediate :(BOOL) translucent
{
	if ([UNIVERSE breakPatternHide])   return; // DON'T DRAW

    //
    if (!translucent)
	{
		// disapply lighting
		glDisable(GL_LIGHTING);
		glDisable(GL_DEPTH_TEST);	// don't read the depth buffer
		glDepthMask(GL_FALSE);		// don't write to depth buffer
		glDisable(GL_CULL_FACE);	// face culling
		
		if (immediate)
		{
			glEnable(GL_TEXTURE_2D);
			glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
			glBlendFunc(GL_ONE, GL_ONE);	// Pure additive blending, ignoring alpha
			
			[sStarTexture apply];

			glEnableClientState(GL_VERTEX_ARRAY);
			glVertexPointer(3, GL_FLOAT, 0, starsData.vertex_array);
			// 3 coords per vertex
			// of type GL_FLOAT
			// 0 stride (tightly packed)
			// pointer to first vertex

			glEnableClientState(GL_TEXTURE_COORD_ARRAY);
			glTexCoordPointer(2, GL_INT, 0, starsData.texture_uv_array);
			// 2 coords per vertex
			// of type GL_INT
			// 0 stride (tightly packed)
			// pointer to first coordinate pair

			glEnableClientState(GL_COLOR_ARRAY);
			glColorPointer(4, GL_FLOAT, 0, starsData.color_array);
			// 4 values per vertex color
			// of type GL_FLOAT
			// 0 stride (tightly packed)
			// pointer to quadruplet

			glDisableClientState(GL_INDEX_ARRAY);
			glDisableClientState(GL_NORMAL_ARRAY);
			glDisableClientState(GL_EDGE_FLAG_ARRAY);

			glDrawArrays(GL_QUADS, 0, 4 * n_stars);

			//
			// blobs
			if (![UNIVERSE reducedDetail])
			{
				[sBlobTexture apply];

				glEnableClientState(GL_VERTEX_ARRAY);
				glVertexPointer(3, GL_FLOAT, 0, blobsData.vertex_array);
				// 3 coords per vertex
				// of type GL_FLOAT
				// 0 stride (tightly packed)
				// pointer to first vertex

				glEnableClientState(GL_TEXTURE_COORD_ARRAY);
				glTexCoordPointer(2, GL_INT, 0, blobsData.texture_uv_array);
				// 2 coords per vertex
				// of type GL_INT
				// 0 stride (tightly packed)
				// pointer to first coordinate pair

				glEnableClientState(GL_COLOR_ARRAY);
				glColorPointer(4, GL_FLOAT, 0, blobsData.color_array);
				// 4 values per vertex color
				// of type GL_FLOAT
				// 0 stride (tightly packed)
				// pointer to quadruplet

				glDisableClientState(GL_INDEX_ARRAY);
				glDisableClientState(GL_NORMAL_ARRAY);
				glDisableClientState(GL_EDGE_FLAG_ARRAY);

				glDrawArrays(GL_QUADS, 0, 4 * n_blobs);

			}
			glDisable(GL_TEXTURE_2D);
			glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);	// Basic alpha blending
		}
		else
		{
			if (displayListName != 0)  glCallList(displayListName);
			else  [self generateDisplayList];
		}

		// reapply lighting &c
		glEnable(GL_CULL_FACE);			// face culling
		glEnable(GL_LIGHTING);
		glEnable(GL_DEPTH_TEST);		// read the depth buffer
		glDepthMask(GL_TRUE);			// restore write to depth buffer
	}
	CheckOpenGLErrors(@"SkyEntity after drawing %@", self);
}

@end


@implementation SkyEntity (OOPrivate)

- (void)readColor1:(OOColor **)ioColor1 andColor2:(OOColor **)ioColor2 fromDictionary:(NSDictionary *)dictionary
{
	NSString			*string = nil;
	NSArray				*tokens = nil;
	id					colorDesc = nil;
	OOColor				*color = nil;
	
	assert(ioColor1 != NULL && ioColor2 != NULL);
	
	string = [dictionary stringForKey:@"sky_rgb_colors"];
	if (string != nil)
	{
		tokens = ScanTokensFromString(string);
		
		if ([tokens count] == 6)
		{
			float r1 = [tokens floatAtIndex:0];
			float g1 = [tokens floatAtIndex:1];
			float b1 = [tokens floatAtIndex:2];
			float r2 = [tokens floatAtIndex:3];
			float g2 = [tokens floatAtIndex:4];
			float b2 = [tokens floatAtIndex:5];
			*ioColor1 = [OOColor colorWithCalibratedRed:r1 green:g1 blue:b1 alpha:1.0];
			*ioColor2 = [OOColor colorWithCalibratedRed:r2 green:g2 blue:b2 alpha:1.0];
		}
		else
		{
			OOLog(@"sky.fromDict", @"ERROR: could not interpret \"%@\" as two RGB colours (must be six numbers).", string);
		}
	}
	colorDesc = [dictionary objectForKey:@"sky_color_1"];
	if (colorDesc != nil)
	{
		color = [[OOColor colorWithDescription:colorDesc] premultipliedColor];
		if (color != nil)  *ioColor1 = color;
		else  OOLog(@"sky.fromDict", @"ERROR: could not interpret \"%@\" as a colour.", colorDesc);
	}
	colorDesc = [dictionary objectForKey:@"sky_color_2"];
	if (colorDesc != nil)
	{
		color = [[OOColor colorWithDescription:colorDesc] premultipliedColor];
		if (color != nil)  *ioColor2 = color;
		else  OOLog(@"sky.fromDict", @"ERROR: could not interpret \"%@\" as a colour.", colorDesc);
	}
}


- (void)setUpStarsWithColor1:(OOColor *)color1 color2:(OOColor *)color2
{
	Vector		star_vector[n_stars];
	GLfloat		star_color[n_stars][4];
	Vector		star_quad[4][n_stars];
	int			i;
	OOColor		*blendedColor = nil;
	Quaternion	q;
	Vector		vi, vj, vk;
	double		p_size;
	
	for (i = 0; i < n_stars; i++)
	{
		blendedColor = [color1 blendedColorWithFraction:(ranrot_rand() % 1024)/1024.0 ofColor:color2];
		star_color[i][0] = [blendedColor redComponent];
		star_color[i][1] = [blendedColor greenComponent];
		star_color[i][2] = [blendedColor blueComponent];
		star_color[i][3] = 1.0;
		
		quaternion_set_random(&q);
		vi = vector_right_from_quaternion(q);
		vj = vector_up_from_quaternion(q);
		vk = vector_forward_from_quaternion(q);
		
		star_vector[i] = vector_multiply_scalar(vk, BILLBOARD_DEPTH);
		
		p_size = (1 + (ranrot_rand() % 6)) * BILLBOARD_DEPTH / 500.0;
		
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
		starsData.texture_uv_array[4*i*2 + 0] = 0;	starsData.texture_uv_array[4*i*2 + 1] = 0;
		starsData.vertex_array[4*i*3 + 0] = star_quad[0][i].x;	starsData.vertex_array[4*i*3 + 1] = star_quad[0][i].y;	starsData.vertex_array[4*i*3 + 2] = star_quad[0][i].z;
		starsData.texture_uv_array[4*i*2 + 2] = 1;	starsData.texture_uv_array[4*i*2 + 3] = 0;
		starsData.vertex_array[4*i*3 + 3] = star_quad[1][i].x;	starsData.vertex_array[4*i*3 + 4] = star_quad[1][i].y;	starsData.vertex_array[4*i*3 + 5] = star_quad[1][i].z;
		starsData.texture_uv_array[4*i*2 + 4] = 1;	starsData.texture_uv_array[4*i*2 + 5] = 1;
		starsData.vertex_array[4*i*3 + 6] = star_quad[2][i].x;	starsData.vertex_array[4*i*3 + 7] = star_quad[2][i].y;	starsData.vertex_array[4*i*3 + 8] = star_quad[2][i].z;
		starsData.texture_uv_array[4*i*2 + 6] = 0;	starsData.texture_uv_array[4*i*2 + 7] = 1;
		starsData.vertex_array[4*i*3 + 9] = star_quad[3][i].x;	starsData.vertex_array[4*i*3 + 10] = star_quad[3][i].y;	starsData.vertex_array[4*i*3 + 11] = star_quad[3][i].z;

		// set up color array
		for (j = 0; j < 4; j++)
		{
			starsData.color_array[4*i*4 + j*4 + 0] = star_color[i][0];
			starsData.color_array[4*i*4 + j*4 + 1] = star_color[i][1];
			starsData.color_array[4*i*4 + j*4 + 2] = star_color[i][2];
			starsData.color_array[4*i*4 + j*4 + 3] = star_color[i][3];
		}

	}
}


- (void)setUpBlobsWithColor1:(OOColor *)color1 color2:(OOColor *)color2
{
	Vector		blob_vector[n_blobs];
	GLfloat		blob_color[n_blobs][4];
	Vector		blob_quad[4][n_blobs];
	int			i;
	OOColor		*blendedColor = nil;
	float		hu, sa, br, al;
	Quaternion	q;
	Vector		vi, vj, vk;
	int			r1;
	double		p_size, r;
	
	for (i = 0; i < n_blobs; i++)
	{
		// Choose a colour for this blob
		blendedColor = [color1 blendedColorWithFraction:(ranrot_rand() % 1024)/1024.0 ofColor:color2];
		[blendedColor getHue:&hu saturation:&sa brightness:&br alpha:&al];
		sa = 0.5 * sa + 0.5;	// move saturation up a notch!
		br *= blob_alpha;		// Premultiply alpha
		blendedColor = [OOColor colorWithCalibratedHue:hu saturation:sa brightness:br alpha:al];
		
		quaternion_set_random(&q);
		
		while ((i < n_blobs)&&(randf() < blob_cluster_chance))
		{
			vk = vector_forward_from_quaternion(q);
			
			blob_color[i][0] = [blendedColor redComponent];
			blob_color[i][1] = [blendedColor greenComponent];
			blob_color[i][2] = [blendedColor blueComponent];
			blob_color[i][3] = 1.0f;
			
			blob_vector[i] = vector_multiply_scalar(vk, BILLBOARD_DEPTH);
			
			r1 = 1 + (ranrot_rand() & 15);
			p_size = blob_scale * r1 * BILLBOARD_DEPTH / 500.0;
			blob_color[i][3] *= 0.5 + (float)r1 / 32.0;	// make smaller blobs dimmer
			blob_quad[0][i] = blob_vector[i];

			// rotate vi and vj a random amount
			r = randf() * M_PI * 2.0;
			quaternion_rotate_about_axis(&q, vk, r);
			vi = vector_right_from_quaternion(q);
			vj = vector_up_from_quaternion(q);

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
			blobsData.texture_uv_array[4*i*2 + 0] = 0;	blobsData.texture_uv_array[4*i*2 + 1] = 0;
			blobsData.vertex_array[4*i*3 + 0] = blob_quad[0][i].x;	blobsData.vertex_array[4*i*3 + 1] = blob_quad[0][i].y;	blobsData.vertex_array[4*i*3 + 2] = blob_quad[0][i].z;
			blobsData.texture_uv_array[4*i*2 + 2] = 1;	blobsData.texture_uv_array[4*i*2 + 3] = 0;
			blobsData.vertex_array[4*i*3 + 3] = blob_quad[1][i].x;	blobsData.vertex_array[4*i*3 + 4] = blob_quad[1][i].y;	blobsData.vertex_array[4*i*3 + 5] = blob_quad[1][i].z;
			blobsData.texture_uv_array[4*i*2 + 4] = 1;	blobsData.texture_uv_array[4*i*2 + 5] = 1;
			blobsData.vertex_array[4*i*3 + 6] = blob_quad[2][i].x;	blobsData.vertex_array[4*i*3 + 7] = blob_quad[2][i].y;	blobsData.vertex_array[4*i*3 + 8] = blob_quad[2][i].z;
			blobsData.texture_uv_array[4*i*2 + 6] = 0;	blobsData.texture_uv_array[4*i*2 + 7] = 1;
			blobsData.vertex_array[4*i*3 + 9] = blob_quad[3][i].x;	blobsData.vertex_array[4*i*3 + 10] = blob_quad[3][i].y;	blobsData.vertex_array[4*i*3 + 11] = blob_quad[3][i].z;

			// set up color array
			for (j = 0; j < 4; j++)
			{
				blobsData.color_array[4*i*4 + j*4 + 0] = blob_color[i][0];
				blobsData.color_array[4*i*4 + j*4 + 1] = blob_color[i][1];
				blobsData.color_array[4*i*4 + j*4 + 2] = blob_color[i][2];
				blobsData.color_array[4*i*4 + j*4 + 3] = blob_color[i][3];
			}

			p_size *= 500/BILLBOARD_DEPTH;	// back to normal scale

			// shuffle it around a bit in a random walk
			q.x += p_size * blob_scale_prime * (randf() - 0.5);
			q.y += p_size * blob_scale_prime * (randf() - 0.5);
			q.z += p_size * blob_scale_prime * (randf() - 0.5);
			q.w += p_size * blob_scale_prime * (randf() - 0.5);
			quaternion_normalize(&q);
			i++;
		}
	}
}


- (void)generateDisplayList
{
	[self ensureTexturesLoaded];
	
	displayListName = glGenLists(1);
	if (displayListName != 0)
	{
		glNewList(displayListName, GL_COMPILE);
		[self drawEntity:YES:NO];	//	immediate YES	translucent NO
		glEndList();
	}
}


- (void)loadTextures
{
	sStarTexture = [OOTexture textureWithName:@"star64.png"
									 inFolder:@"Textures"
									  options:kOOTextureDefaultOptions
								   anisotropy:0.0f
									  lodBias:-0.6f];
	sBlobTexture = [OOTexture textureWithName:@"galaxy256.png"
									 inFolder:@"Textures"
									  options:kOOTextureDefaultOptions
								   anisotropy:0.0f
									  lodBias:0.0f];
	
#if MULTI_TEXTURE_BLOBS
	unsigned				i;
	NSString				*name = nil;
	NSMutableArray			*blobTextures = nil;
	OOTexture				*tex;
	
	blobTextures = [[NSMutableArray alloc] init];
	i = 1;
	for (;;)
	{
		name = [NSString stringWithFormat:@"oolite-nebula-%u.png", i++];
		tex = [OOTexture textureWithName:name
								inFolder:@"Textures"
								 options:kOOTextureDefaultOptions | kOOTextureNoFNFMessage
							  anisotropy:0.0f
								 lodBias:0.0f];
		
		if (tex != nil)  [blobTextures addObject:tex];
		else  break;
	}
#endif
	
	sLoadedTextures = YES;
}


- (void)ensureTexturesLoaded
{
	[sStarTexture ensureFinishedLoading];
	[sBlobTexture ensureFinishedLoading];
	
#if MULTI_TEXTURE_BLOBS
	[sBlobTextures makeObjectsPerformSelector:@selector(ensureFinishedLoading)];
#endif
}


- (void)resetGraphicsState
{
	if (displayListName != 0)
	{
		glDeleteLists(displayListName, 1);
		displayListName = 0;
	}
}

@end
