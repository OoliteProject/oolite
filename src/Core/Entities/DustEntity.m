/*

DustEntity.m

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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

#import "DustEntity.h"

#import "OOMaths.h"
#import "Universe.h"
#import "MyOpenGLView.h"
#import "OOGraphicsResetManager.h"
#import "OODebugFlags.h"

#import "PlayerEntity.h"


#define FAR_PLANE		(DUST_SCALE * 0.50f)
#define NEAR_PLANE		(DUST_SCALE * 0.25f)


// Declare protocol conformance
@interface DustEntity (OOGraphicsResetClient) <OOGraphicsResetClient>
@end


@implementation DustEntity

- (id) init
{
	int vi;
	
	ranrot_srand([[NSDate date] timeIntervalSince1970]);	// seed randomiser by time
	
	self = [super init];
	
	for (vi = 0; vi < DUST_N_PARTICLES; vi++)
	{
		vertices[vi].x = (ranrot_rand() % DUST_SCALE) - DUST_SCALE / 2;
		vertices[vi].y = (ranrot_rand() % DUST_SCALE) - DUST_SCALE / 2;
		vertices[vi].z = (ranrot_rand() % DUST_SCALE) - DUST_SCALE / 2;
	}
	
	dust_color = [[OOColor colorWithCalibratedRed:0.5 green:1.0 blue:1.0 alpha:1.0] retain];
	displayListName = 0;
	[self setStatus:STATUS_ACTIVE];
	
	[[OOGraphicsResetManager sharedManager] registerClient:self];
	
	return self;
}


- (void) dealloc
{
	DESTROY(dust_color);
	[[OOGraphicsResetManager sharedManager] unregisterClient:self];
	OOGL(glDeleteLists(displayListName, 1));
	
#if OO_SHADERS
	DESTROY(shader);
#endif
	
	[super dealloc];
}


- (void) setDustColor:(OOColor *) color
{
	if (dust_color) [dust_color release];
	dust_color = [color retain];
	[dust_color getGLRed:&color_fv[0] green:&color_fv[1] blue:&color_fv[2] alpha:&color_fv[3]];
}


- (OOColor *) dustColor
{
	return dust_color;
}


- (BOOL) canCollide
{
	return NO;
}


- (void) update:(OOTimeDelta) delta_t
{
	PlayerEntity* player = [PlayerEntity sharedPlayer];
	assert(player != nil);
	
	zero_distance = 0.0;
			
	Vector offset = [player position];
	GLfloat  half_scale = DUST_SCALE * 0.50;
	int vi;
	for (vi = 0; vi < DUST_N_PARTICLES; vi++)
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
	}
}


#if OO_SHADERS
- (OOShaderProgram *) shader
{
	if (shader == nil)
	{
		NSString *prefix = [NSString stringWithFormat:
						   @"#define OODUST_SCALE_MAX    (float(%g))\n"
							"#define OODUST_SCALE_FACTOR (float(%g))\n",
							FAR_PLANE / NEAR_PLANE,
							1.0f / (FAR_PLANE - NEAR_PLANE)];
		
		shader = [[OOShaderProgram shaderProgramWithVertexShaderName:@"oolite-dust.vertex"
												  fragmentShaderName:@"oolite-dust.fragment"
															  prefix:prefix
												   attributeBindings:nil] retain];
	}
	
	return shader;
}
#endif


- (void) drawEntity:(BOOL) immediate :(BOOL) translucent
{
	if ([UNIVERSE breakPatternHide] || !translucent)  return;	// DON'T DRAW
	
	PlayerEntity* player = [PlayerEntity sharedPlayer];
	assert(player != nil);
	
#ifndef NDEBUG
	if (gDebugFlags & DEBUG_NO_DUST)  return;
#endif

	GLfloat	*fogcolor = [UNIVERSE skyClearColor];
	float	idealDustSize = [[UNIVERSE gameView] viewSize].width / 1200.0f;
	
	float dustPointSize = ceilf(idealDustSize);
	if (dustPointSize < 1.0f)  dustPointSize = 1.0f;
	
	float idealLineSize = idealDustSize * 0.5f;
	float dustLineSize = ceilf(idealLineSize);
	if (dustLineSize < 1.0f) dustLineSize = 1.0f;
	
	BOOL	warp_stars = [player atHyperspeed];
	Vector  warp_vector = vector_multiply_scalar([player velocity], 1.0f / HYPERSPEED_FACTOR);
	GLenum	dustMode;
	float	dustIntensity;
#if OO_SHADERS
	BOOL	useShader = [UNIVERSE shaderEffectsLevel] > SHADERS_OFF;
#endif
	
	if (!warp_stars)
	{
		// Draw points.
		OOGL(glEnable(GL_POINT_SMOOTH));
		OOGL(glPointSize(dustPointSize));
		dustMode = GL_POINTS;
		dustIntensity = OOClamp_0_1_f(idealDustSize / dustPointSize);
	}
	else
	{
		// Draw lines.
		OOGL(glEnable(GL_LINE_SMOOTH));
		OOGL(glLineWidth(dustLineSize));
		dustMode = GL_LINES;
		dustIntensity = OOClamp_0_1_f(idealLineSize / dustLineSize);
	}
	
	float	*color = NULL;
	if (player->isSunlit)  color = color_fv;
	else  color = UNIVERSE->stars_ambient;
	
#if OO_SHADERS
	if (useShader)
	{
		[[self shader] apply];
		OOGL(glEnable(GL_BLEND));
		OOGL(glColor4f(color[0], color[1], color[2], dustIntensity));
	}
	else
#endif
	{
		OOGL(glEnable(GL_FOG));
		OOGL(glFogi(GL_FOG_MODE, GL_LINEAR));
		OOGL(glFogfv(GL_FOG_COLOR, fogcolor));
		OOGL(glHint(GL_FOG_HINT, GL_NICEST));
		OOGL(glFogf(GL_FOG_START, NEAR_PLANE));
		OOGL(glFogf(GL_FOG_END, FAR_PLANE));
		OOGL(glColor4f(color[0] * dustIntensity, color[1] * dustIntensity, color[2] * dustIntensity, 1.0));
	}
	
	OOGL(glDisable(GL_TEXTURE_2D));
	
	OOGLBEGIN(dustMode);
	
	unsigned vi;
	for (vi = 0; vi < DUST_N_PARTICLES; vi++)
	{
		GLVertexOOVector(vertices[vi]);
		if (warp_stars)  GLVertexOOVector(vector_subtract(vertices[vi], warp_vector));
	}
	OOGLEND();
	
	// reapply normal conditions
#if OO_SHADERS
	if (useShader)
	{
		[OOShaderProgram applyNone];
	}
	else
#endif
	{
		OOGL(glDisable(GL_FOG));
	}
	
	CheckOpenGLErrors(@"DustEntity after drawing %@", self);
}


- (void)resetGraphicsState
{
	if (displayListName != 0)
	{
		OOGL(glDeleteLists(displayListName, 1));
		displayListName = 0;
	}
	
#if OO_SHADERS
	DESTROY(shader);
#endif
}


#ifndef NDEBUG
- (NSString *) descriptionForObjDump
{
	// Don't include range and visibility flag as they're irrelevant.
	return [self descriptionForObjDumpBasic];
}
#endif

@end
