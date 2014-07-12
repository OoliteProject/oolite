/*

OOSunEntity.m

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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

#import "OOSunEntity.h"
#import "OOOpenGLExtensionManager.h"
#import "OOMacroOpenGL.h"

#import "Universe.h"
#import "AI.h"
#import "MyOpenGLView.h"
#import "ShipEntityAI.h"
#import "OOColor.h"
#import "OOCharacter.h"
#import "OOStringParsing.h"
#import "PlayerEntity.h"
#import "OOCollectionExtractors.h"
#import "OODebugFlags.h"
#import "OOStringExpander.h"

@interface OOSunEntity (Private)

- (void) calculateGLArrays:(GLfloat)inner_radius width:(GLfloat)width zDistance:(GLfloat)z_distance;
- (void) drawOpaqueParts;
- (void) drawTranslucentParts;

@end


@implementation OOSunEntity

#ifndef NDEBUG
- (id) init
{
	assert(0);
	return nil;
}
#endif


- (BOOL) setSunColor:(OOColor*)sun_color
{
	if (sun_color == nil) return NO;
	
	OO_ENTER_OPENGL();
	
	float		hue, sat, bri, alf;
	OOColor		*color = nil;
	
	[sun_color getHue:&hue saturation:&sat brightness:&bri alpha:&alf];
	hue /= 360;
	
/*
	// FIXME: do away with hue_drift altogether?
	// The following two lines are functionally identical to 1.73:
	randf();randf();	// avoid ranrot dirft!
	float hue_drift = 0.0f;
*/
	
	// anything more than a minimal hue drift will wipe out the original colour.
	float hue_drift = 0.038f * fabs(randf() - randf());
	
	// set the lighting color for the sun
	GLfloat		r,g,b,a;
	[sun_color getRed:&r green:&g blue:&b alpha:&a];
	
	GLfloat		sun_ambient[] = { 0.0, 0.0, 0.0, 1.0};	// real ambient light inside gl_LightModel.ambient
	sun_diffuse[0] = 0.5 * (1.0 + r);	// paler
	sun_diffuse[1] = 0.5 * (1.0 + g);	// paler
	sun_diffuse[2] = 0.5 * (1.0 + b);	// paler
	sun_diffuse[3] = 1.0;
	sun_specular[0] = r;
	sun_specular[1] = g;
	sun_specular[2] = b;
	sun_specular[3] = 1.0;
	
	OOGL(glLightfv(GL_LIGHT1, GL_AMBIENT, sun_ambient));
	OOGL(glLightfv(GL_LIGHT1, GL_DIFFUSE, sun_diffuse));
	OOGL(glLightfv(GL_LIGHT1, GL_SPECULAR, sun_specular));
	
	// main disc less saturation more brightness
	color = [OOColor colorWithHue:hue saturation:sat * 0.333f brightness:1.0f alpha:1.0f];
	[color getRed:&discColor[0] green:&discColor[1] blue:&discColor[2] alpha:&discColor[3]];
	
	/*	Two inner corona layers with low alpha and saturation are additively
		blended with main corona. This produces something vaguely like a bloom
		effect.
	*/
	hue += hue_drift * 3;
	// saturation = 1 would shift white to red
	color = [OOColor colorWithHue:hue saturation:OOClamp_0_1_f(sat*1.0f) brightness:bri * 0.75f alpha:0.45f];
	[color getRed:&outerCoronaColor[0] green:&outerCoronaColor[1] blue:&outerCoronaColor[2] alpha:&outerCoronaColor[3]];
	
	return YES;
}


- (id) initSunWithColor:(OOColor *)sun_color andDictionary:(NSDictionary *) dict
{
	int			i;
	
	self = [super init];
	
	collision_radius = 100000.0; //  100km across
	
	scanClass = CLASS_NO_DRAW;
	
	[self setSunColor:sun_color];

	[self setName:OOExpand([dict oo_stringForKey:KEY_SUNNAME defaultValue:@"[oolite-default-star-name]"])];


		
	corona_blending=OOClamp_0_1_f([dict oo_floatForKey:@"corona_hues" defaultValue:1.0f]);
	corona_speed_factor=[dict oo_floatForKey:@"corona_shimmer" defaultValue:-1.0];
	if(corona_speed_factor<0)
	{
		// from .22222 to 2
		corona_speed_factor = 1.0 / (0.5 + 2.0 * (randf() + randf()));
	}
	else
	{
		//on average:  0 = .25 , 1 = 2.25  -  the same sun should give the same random component
		corona_speed_factor=OOClamp_0_1_f(corona_speed_factor) * 2.0 + randf() * randf();
	}
	corona_stage = 0.0;
	for (i = 0; i < SUN_CORONA_SAMPLES; i++)
		rvalue[i] = randf();
	
	// set up the radius properties
	[self changeSunProperty:@"sun_radius" withDictionary:dict];
	
	unsigned k = 0;
	for (unsigned i=0 ; i < 360 ; i++)
	{
		unsigned j = (i+1)%360;
// disc
		sunTriangles[k++] = 0;
		sunTriangles[k++] = 1+i;
		sunTriangles[k++] = 1+j;
	}
	for (unsigned i=0 ; i < 360 ; i++)
	{
		unsigned j = (i+1)%360;
// ring 1
		sunTriangles[k++] = 1+i;
		sunTriangles[k++] = 1+j;
		sunTriangles[k++] = 361+i;
		sunTriangles[k++] = 1+j;
		sunTriangles[k++] = 361+i;
		sunTriangles[k++] = 361+j;
// ring 2
		sunTriangles[k++] = 361+i;
		sunTriangles[k++] = 361+j;
		sunTriangles[k++] = 721+i;
		sunTriangles[k++] = 361+j;
		sunTriangles[k++] = 721+i;
		sunTriangles[k++] = 721+j;
// ring 3
		sunTriangles[k++] = 721+i;
		sunTriangles[k++] = 721+j;
		sunTriangles[k++] = 1081+i;
		sunTriangles[k++] = 721+j;
		sunTriangles[k++] = 1081+i;
		sunTriangles[k++] = 1081+j;
// ring 4
		sunTriangles[k++] = 1081+i;
		sunTriangles[k++] = 1081+j;
		sunTriangles[k++] = 1441+i;
		sunTriangles[k++] = 1081+j;
		sunTriangles[k++] = 1441+i;
		sunTriangles[k++] = 1441+j;
	}

	return self;
}


- (void) dealloc
{
	DESTROY(_name);
	[super dealloc];
}


- (NSString*) descriptionComponents
{
	NSString *result = [NSString stringWithFormat:@"ID: %u position: %@ radius: %.3fkm", [self universalID], HPVectorDescription([self position]), 0.001 * [self radius]];
	if ([self goneNova])
	{
		result = [result stringByAppendingString:@" (gone nova)"];
	}
	else if ([self willGoNova])
	{
		result = [result stringByAppendingString:@" (will go nova)"];
	}
	
	return result;
}


- (BOOL) canCollide
{
	return YES;
}


#ifndef NDEBUG
- (BOOL) checkCloseCollisionWith:(Entity *)other
{
	if (gDebugFlags & DEBUG_COLLISIONS)
	{
		OOLog(@"sun.collide", @"SUN Collision!");
	}
	
	return [super checkCloseCollisionWith:other];
}
#endif


- (void) update:(OOTimeDelta) delta_t
{
	[super update:delta_t];
	
	PlayerEntity	*player = PLAYER;
	assert(player != nil);
	rotMatrix = OOMatrixForBillboard(position, [player viewpointPosition]);
	
	if (throw_sparks && _novaExpansionRate > 0)	// going NOVA!
	{
		if (_novaCountdown >= 0.0)	// countdown
		{
			_novaCountdown -= delta_t;
			if (corona_speed_factor < 5.0)
			{
				corona_speed_factor += 0.75 * delta_t;
			}
		}
		else
		{
			if (_novaExpansionTimer <= 60.0)	// expand for a minute
			{
				double sky_bri = 1.0 - 1.5 * _novaExpansionTimer;
				if (sky_bri < 0)
				{
					[UNIVERSE setSkyColorRed:0.0f		// back to black
									   green:0.0f
										blue:0.0f
									   alpha:0.0f];
				}
				else
				{
					[UNIVERSE setSkyColorRed:sky_bri	// whiteout
									   green:sky_bri
										blue:sky_bri
									   alpha:1.0f];
				}
				if (sky_bri == 1.0)
				{	
					// This sun has now gone nova!
					[UNIVERSE setSystemDataKey:@"sun_gone_nova" value:[NSNumber numberWithBool:YES]];
					OOLog(@"sun.nova.start", @"DEBUG: NOVA original radius %.1f", collision_radius);
				}
				discColor[0] = 1.0;	discColor[1] = 1.0;	discColor[2] = 1.0;
				_novaExpansionTimer += delta_t;
				NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithFloat:collision_radius + delta_t * _novaExpansionRate], @"sun_radius", [NSNumber numberWithFloat:0.3], @"corona_flare", [NSNumber numberWithFloat:0.05], @"corona_hues", nil];
				[self changeSunProperty:@"sun_radius" withDictionary:dict];
			}
			else
			{
				OOLog(@"sun.nova.end", @"DEBUG: NOVA final radius %.1f", collision_radius);
				
				// reset at the new size
				_novaCountdown = 0.0;
				_novaExpansionTimer = 0.0;
				_novaExpansionRate = 0.0f;
				
				throw_sparks = YES;	// keep throw_sparks at YES to indicate the higher temperature
			}
		}
	}
	
	// update corona
	if (![UNIVERSE reducedDetail])
	{
		corona_stage += corona_speed_factor * delta_t;
		while (corona_stage > 1.0)
		{
			int i;
			corona_stage -= 1.0;
			for (i = 0; i < 360; i++)
			{
				rvalue[i] = rvalue[360 + i];
				rvalue[360 + i] = randf();
			}
		}
	}

}



- (void) drawImmediate:(bool)immediate translucent:(bool)translucent
{
	if (![UNIVERSE breakPatternHide])
	{
		if (translucent)
		{
			// nothing...
		}
		else
		{
			[self drawOpaqueParts];
			/* Despite the side effects, we have to draw the translucent
			 * parts on the opaque pass. Planets, at long range, aren't
			 * depth-buffered. So if the translucent parts are drawn on the
			 * translucent pass, they appear in front of planets they are
			 * actually behind. Telabe in G3 is a good one to test with if
			 * you have any clever ideas.
			 *
			 * - CIM 8/7/2013 */
			[self drawTranslucentParts];
		}
	}
}


- (void) drawOpaqueParts
{
	float sqrt_zero_distance = sqrt(cam_zero_distance);

	OO_ENTER_OPENGL();
	
	OOSetOpenGLState(OPENGL_STATE_ADDITIVE_BLENDING);

	if ([UNIVERSE reducedDetail])
	{	
		int subdivideLevel = 2;		// 4 is probably the maximum!
		float drawFactor = [[UNIVERSE gameView] viewSize].width / 100.0;
		float drawRatio2 = drawFactor * collision_radius / sqrt_zero_distance; // equivalent to size on screen in pixels
	
		if (cam_zero_distance > 0.0)
		{
			subdivideLevel = 2 + floor(drawRatio2);
			if (subdivideLevel > 4)
				subdivideLevel = 4;
		}
	
	/*
	 
	The depth test gets disabled in parts of this and instead
	we rely on the painters algorithm instead.
	 
	The depth buffer isn't granular enough to cope with huge objects at vast
	distances.
	 
	*/
		BOOL ignoreDepthBuffer = cam_zero_distance > collision_radius * collision_radius * 25;
	
		int steps = 2 * (MAX_SUBDIVIDE - subdivideLevel);

		// Close enough not to draw flat?
		if (ignoreDepthBuffer)  OOGL(glDisable(GL_DEPTH_TEST));
		
		OOGL(glColor3fv(discColor));
		// FIXME: use vertex arrays
		OOGL(glDisable(GL_BLEND));
		OOGLBEGIN(GL_TRIANGLE_FAN);
		GLDrawBallBillboard(collision_radius, steps, sqrt_zero_distance);
		OOGLEND();
		OOGL(glEnable(GL_BLEND));

		if (ignoreDepthBuffer)  OOGL(glEnable(GL_DEPTH_TEST)); 
	
	}
	else
	{
		[self calculateGLArrays:collision_radius
											width:cor16k
									zDistance:sqrt_zero_distance];
		OOGL(glDisable(GL_BLEND));
		OOGL(glVertexPointer(3, GL_FLOAT, 0, sunVertices));
		
		OOGL(glEnableClientState(GL_COLOR_ARRAY));
		OOGL(glColorPointer(4, GL_FLOAT, 0, sunColors));
		
		OOGL(glDrawElements(GL_TRIANGLES, 3*360, GL_UNSIGNED_INT, sunTriangles));

		OOGL(glDisableClientState(GL_COLOR_ARRAY));
		OOGL(glEnable(GL_BLEND));

		
	}
	
	OOVerifyOpenGLState();
	OOCheckOpenGLErrors(@"SunEntity after drawing %@", self);
}


- (void) drawTranslucentParts
{
	if ([UNIVERSE reducedDetail]) 
	{
		return;
	}
	
	OO_ENTER_OPENGL();
	
	OOSetOpenGLState(OPENGL_STATE_ADDITIVE_BLENDING);

	OOGL(glVertexPointer(3, GL_FLOAT, 0, sunVertices));

	OOGL(glEnableClientState(GL_COLOR_ARRAY));
	OOGL(glColorPointer(4, GL_FLOAT, 0, sunColors));
	OOGL(glDrawElements(GL_TRIANGLES, 24*360, GL_UNSIGNED_INT, sunTriangles+(3*360)));

	OOGL(glDisableClientState(GL_COLOR_ARRAY));


}

- (void) calculateGLArrays:(GLfloat)inner_radius width:(GLfloat)width zDistance:(GLfloat)z_distance
{
//	if (EXPECT_NOT(inner_radius >= z_distance))  return;	// inside the sphere
	
	GLfloat activity[8] = {0.84, 0.74, 0.64, 0.54, 
												 0.3 , 0.4 , 0.7 , 0.8};
	
	GLfloat				si, ci;
	GLfloat				rv0, rv1, rv2, c0, c1, c2;
	GLfloat				pt0, pt1; 
	
	unsigned short		i, j, k;
	GLfloat				theta = 0.0f, delta;
	delta = M_PI / 180.0f;	// Convert step from degrees to radians
	pt0=(1.0 - corona_stage) * corona_blending;
	pt1=corona_stage * corona_blending;

	sunVertices[0] = 0.0;
	sunVertices[1] = 0.0;
	sunVertices[2] = 0.0;
	k = 3;
	for (j = 0 ; j <= 4 ; j++)
	{
		GLfloat r = inner_radius;
		switch (j) {
		case 4:
			r += width;
			break;
		case 3:
			r += width/1.5;
			break;
		case 2:
			r += width/3.0;
			break;
		case 1:
			r += width/15.0;
			break;
		}
		theta = 0.0;
		for (i = 0 ; i < 360 ; i++)
		{
			GLfloat rm = 1.0;
			if (j >= 1 && j < 4)
			{
				rm = 1.0 + ((0.04/j)*(pt0 * (rvalue[i]+rvalue[i+1]+rvalue[i+2]) + pt1 * (rvalue[i+360]+rvalue[i+361]+rvalue[i+362])))/3;
			}
			GLfloat z = r * r * rm * rm / z_distance;
			si = sin(theta);
			ci = cos(theta);
			theta += delta;
			sunVertices[k++] = si * r * rm;
			sunVertices[k++] = ci * r * rm;
			sunVertices[k++] = -z;
		}
	}

	GLfloat blackColor[4] = {0.0,0.0,0.0,0.0};
	GLfloat *color = blackColor;
	GLfloat alpha = 0.0;

	k=0;
	sunColors[k++] = discColor[0];
	sunColors[k++] = discColor[1];
	sunColors[k++] = discColor[2];
	sunColors[k++] = discColor[3];
	for (j = 0 ; j <= 4 ; j++)
	{
		switch (j) {
		case 4:
			color = blackColor;
			alpha = 0.0;
			break;
		case 3:
			color = outerCoronaColor;
			alpha = 0.1;
			break;
		case 2:
			color = outerCoronaColor;
			alpha = 0.6;
			break;
		case 1:
			color = discColor;
			alpha = 0.95;
			break;
		case 0:
			color = discColor;
			alpha = 1.0;
			break;
		}
		for (i = 0 ; i < 360 ; i++)
		{
			if (j == 0) 
			{
				sunColors[k++] = color[0];
				sunColors[k++] = color[1];
				sunColors[k++] = color[2];
				sunColors[k++] = 1.0;
			}
			else
			{
				rv0 = pt0 * rvalue[i] + pt1 * rvalue[i + 360];
				rv1 = pt0 * rvalue[i + 1] + pt1 * rvalue[i + 361];
				rv2 = pt0 * rvalue[i + 2] + pt1 * rvalue[i + 362];
				c0 = color[0] * (activity[j-1] + rv0*activity[j+3]);
				c1 = color[1] * (activity[j-1] + rv1*activity[j+3]);
				c2 = color[2] * (activity[j-1] + rv2*activity[j+3]);
				if (c1 > c2 && c1 > c0)
				{
					c1 = fmaxf(c0,c2);
				}

				sunColors[k++] = c0;
				sunColors[k++] = c1;
				sunColors[k++] = c2;
				sunColors[k++] = alpha;
			}	
		}
	}
}


- (void) drawDirectVisionSunGlare
{
#if SUN_DIRECT_VISION_GLARE
	OO_ENTER_OPENGL();
	
	OOSetOpenGLState(OPENGL_STATE_OVERLAY);
	
	GLfloat sunGlareAngularSize = atan([self radius]/HPdistance([PLAYER viewpointPosition], [self position])) * SUN_GLARE_MULT_FACTOR + (SUN_GLARE_ADD_FACTOR);

	GLfloat	directVisionSunGlare = [PLAYER lookingAtSunWithThresholdAngleCos:cos(sunGlareAngularSize)];
	if (directVisionSunGlare)
	{
		NSSize	siz =	[[UNIVERSE gui]	size];
		GLfloat z = [[UNIVERSE gameView] display_z];
		GLfloat atmosphericReductionFactor =  1.0f - [PLAYER insideAtmosphereFraction];
		// 182: square of ratio of radius to sun-witchpoint distance
		// in default Lave
		GLfloat distanceReductionFactor = OOClamp_0_1_f(([self radius] * [self radius] * 182.0) / HPdistance2([PLAYER position], [self position]));
		GLfloat	sunGlareFilterMultiplierLocal = [PLAYER sunGlareFilter];
		GLfloat directVisionSunGlareColor[4] = {discColor[0], discColor[1], discColor[2], directVisionSunGlare *
													atmosphericReductionFactor * distanceReductionFactor * 
													(1.0f - sunGlareFilterMultiplierLocal) * 0.85f};
													
		OOGL(glColor4fv(directVisionSunGlareColor));
		
		OOGLBEGIN(GL_QUADS);
		glVertex3f(siz.width, siz.height, z);
		glVertex3f(siz.width, -siz.height, z);
		glVertex3f(-siz.width, -siz.height, z);
		glVertex3f(-siz.width, siz.height, z);
		OOGLEND();
	}
#endif
}


- (void) drawStarGlare
{
	OO_ENTER_OPENGL();

	OOSetOpenGLState(OPENGL_STATE_OVERLAY);
	
	float sqrt_zero_distance = sqrt(cam_zero_distance);
	double alt = sqrt_zero_distance - collision_radius;
	if (EXPECT_NOT(alt < 0))
	{
		return;
	}
	double corona = cor16k/SUN_GLARE_CORONA_FACTOR;
	if (corona > alt)
	{
		double alpha = 1-(alt/corona);
		GLfloat glareColor[4] = {discColor[0], discColor[1], discColor[2], alpha};
		NSSize		siz =	[[UNIVERSE gui]	size];
		GLfloat z = [[UNIVERSE gameView] display_z];
		OOGL(glColor4fv(glareColor));

		OOGLBEGIN(GL_QUADS);
		glVertex3f(siz.width, siz.height, z);
		glVertex3f(siz.width, -siz.height, z);
		glVertex3f(-siz.width, -siz.height, z);
		glVertex3f(-siz.width, siz.height, z);
		OOGLEND();

	}
}



- (BOOL) changeSunProperty:(NSString *)key withDictionary:(NSDictionary*) dict
{
	id	object = [dict objectForKey:key];
	static GLfloat oldRadius = 0.0;
	if ([key isEqualToString:@"sun_radius"])
	{
		oldRadius =	[object doubleValue];	// clamp corona_flare in case planetinfo.plist / savegame contains the wrong value
		[self setRadius: oldRadius + (0.66*MAX_CORONAFLARE * OOClamp_0_1_f([dict oo_floatForKey:@"corona_flare" defaultValue:0.0f]))];
		collision_radius = oldRadius;								
	}
	else if ([key isEqualToString:KEY_SUNNAME])
	{
		[self setName:[dict oo_stringForKey:KEY_SUNNAME]];
	}
	else if ([key isEqualToString:@"corona_flare"])
	{
		double rad = collision_radius;
		[self setRadius: rad + (0.66*MAX_CORONAFLARE * OOClamp_0_1_f([object floatValue]))];
		collision_radius = rad;
	}
	else if ([key isEqualToString:@"corona_shimmer"])
	{
		corona_speed_factor=OOClamp_0_1_f([object floatValue]) * 2.0 + randf() * randf();
	}
	else if ([key isEqualToString:@"corona_hues"])
	{
		corona_blending=OOClamp_0_1_f([object floatValue]);
	}
	else if ([key isEqualToString:@"sun_gone_nova"])
	{

		if ([dict oo_boolForKey:key])
		{
			[self setGoingNova:YES inTime:0];
		}
		else
		{
			[self setGoingNova:NO inTime:0];
			// oldRadius is always the radius we had before going nova...
			[self setRadius: oldRadius + (0.66*MAX_CORONAFLARE * OOClamp_0_1_f([dict oo_floatForKey:@"corona_flare" defaultValue:0.0f]))];
			collision_radius = oldRadius;

		}
	}
	else
	{
		OOLogWARN(@"script.warning", @"Change to property '%@' not applied, will apply only after leaving this system.",key);
		return NO;
	}
	return YES;
}


- (OOStellarBodyType) planetType
{
	return STELLAR_TYPE_SUN;
}


- (void) getDiffuseComponents:(GLfloat[4])components
{
	NSParameterAssert(components != NULL);
	memcpy(components, sun_diffuse, sizeof sun_diffuse);
}


- (void) getSpecularComponents:(GLfloat[4])components
{
	NSParameterAssert(components != NULL);
	memcpy(components, sun_specular, sizeof sun_specular);
}


- (double) radius
{
	return collision_radius;
}


- (void) setRadius:(GLfloat) rad
{
	collision_radius = rad;
	
	cor16k =	rad * rad * 16 / 10000000;
	lim16k =	cor16k	* cor16k* NO_DRAW_DISTANCE_FACTOR*NO_DRAW_DISTANCE_FACTOR;
}


- (void) setPosition:(HPVector) posn
{
	[super setPosition: posn];
	[UNIVERSE setMainLightPosition: HPVectorToVector(posn)];
}


- (BOOL) willGoNova
{
	return throw_sparks;
}


- (BOOL) goneNova
{
	return throw_sparks && _novaCountdown <= 0;
}


- (void) setGoingNova:(BOOL) yesno inTime:(double)interval
{
	throw_sparks = yesno;
	if (throw_sparks)
	{
		_novaCountdown = fmax(interval, 0.0);
		OOLog(@"script.debug.setSunNovaIn", @"NOVA activated! time until Nova : %.1f s", _novaCountdown);
	}
	
	_novaExpansionTimer = 0;
	_novaExpansionRate = 10000;
}


- (BOOL) isSun
{
	return YES;
}


- (BOOL) isVisible
{
	return YES;
}


- (NSString *) name
{
	return _name;
}


- (void) setName:(NSString *)name
{
	[_name release];
	_name = [name retain];
}


@end
