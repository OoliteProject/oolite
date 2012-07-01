/*

OOSunEntity.m

Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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

#define kOOLogUnconvertedNSLog @"unclassified.SunEntity"


@interface OOSunEntity (Private)

- (void) drawActiveCoronaWithInnerRadius:(float)inner_radius
								   width:(float)width
									step:(float)step
							   zDistance:(float)z_distance
								   color:(GLfloat[4])color
									  rv:(int)rv;

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
	
	OOCGFloat	hue, sat, bri, alf;
	OOColor		*color;
	
	[sun_color getHue:&hue saturation:&sat brightness:&bri alpha:&alf];
	hue /= 360;
	
/*
	// FIXME: do away with hue_drift altogether?
	// The following two lines are functionally identical to 1.73:
	randf();randf();	// avoid ranrot dirft!
	float hue_drift = 0.0f;
*/

	// anything more than a minimal hue drift will wipe out the original colour.
	float hue_drift = 0.038f * fabsf(randf() - randf());
	
	// set the lighting color for the sun
	GLfloat		r,g,b,a;
	[sun_color getGLRed:&r green:&g blue:&b alpha:&a];

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
	color = [OOColor colorWithCalibratedHue: hue saturation: sat * 0.333 brightness: 1.0 alpha: alf];
	discColor[0] = [color redComponent];
	discColor[1] = [color greenComponent];
	discColor[2] = [color blueComponent];
	discColor[3] = 1.0f;
	
	// nearest corona much more saturation
	hue += hue_drift;
	if (hue > 1.0)	hue -= 1.0;
	color = [OOColor colorWithCalibratedHue:hue saturation: sat * 0.625 brightness:(bri + 2.0)/3.0 alpha:alf];
	innerCoronaColor[0] = [color redComponent];
	innerCoronaColor[1] = [color greenComponent];
	innerCoronaColor[2] = [color blueComponent];
	innerCoronaColor[3] = 0.75f;
	
	// next corona slightly more saturation
	hue += hue_drift;
	if (hue > 1.0)	hue -= 1.0;
	color = [OOColor colorWithCalibratedHue:hue saturation:sat brightness:bri alpha:alf];
	middleCoronaColor[0] = [color redComponent];
	middleCoronaColor[1] = [color greenComponent];
	middleCoronaColor[2] = [color blueComponent];
	middleCoronaColor[3] = 0.625f;
	
	// last corona, highest saturation, less bright
	hue += hue_drift;
	if (hue > 1.0)	hue -= 1.0;
	// saturation = 1 would shift white to red
	color = [OOColor colorWithCalibratedHue:hue saturation:OOClamp_0_1_f(sat*1.3f) brightness:bri * 0.75 alpha:alf*0.6];
	outerCoronaColor[0] = [color redComponent];
	outerCoronaColor[1] = [color greenComponent];
	outerCoronaColor[2] = [color blueComponent];
	outerCoronaColor[3] = 0.45f;

	return YES;
}


- (id) initSunWithColor:(OOColor *)sun_color andDictionary:(NSDictionary *) dict
{
	int			i;
	
	self = [super init];
	
	collision_radius = 100000.0; //  100km across
	
	scanClass = CLASS_NO_DRAW;
	
	[self setSunColor:sun_color];
	
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
	
	return self;
}


- (void) dealloc
{
	[super dealloc];
}


- (NSString*) descriptionComponents
{
	NSString *result = [NSString stringWithFormat:@"ID: %u position: %@ radius: %.3fkm", [self universalID], VectorDescription([self position]), 0.001 * [self radius]];
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
	rotMatrix = OOMatrixForBillboard(position, [player position]);
	
	if (throw_sparks && velocity.z > 0)	// going NOVA!
	{
		if (velocity.x >= 0.0)	// countdown
		{
			velocity.x -= delta_t;
			if (corona_speed_factor < 5.0)
			{
				corona_speed_factor += 0.75 * delta_t;
			}
		}
		else
		{
			if (velocity.y <= 60.0)	// expand for a minute
			{
				double sky_bri = 1.0 - 1.5 * velocity.y;
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
				velocity.y += delta_t;
				[self setRadius: collision_radius + delta_t * velocity.z];
			}
			else
			{
				OOLog(@"sun.nova.end", @"DEBUG: NOVA final radius %.1f", collision_radius);
				// reset at the new size
				velocity = kZeroVector;
				throw_sparks = YES;	// keep throw_sparks at YES to indicate the higher temperature
			}
		}
	}
	
	// update corona
	if (![UNIVERSE reducedDetail])
	{
		corona_stage += corona_speed_factor * delta_t;
		if (corona_stage > 1.0)
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



// TODO: some translucent stuff is drawn in the opaque pass, which is Naughty.
- (void) drawEntity:(BOOL) immediate :(BOOL) translucent
{
	if (![UNIVERSE breakPatternHide] && !translucent)  [self drawUnconditionally];
}


- (void) drawUnconditionally
{
	int subdivideLevel = 2;		// 4 is probably the maximum!
	
	float sqrt_zero_distance = sqrtf(cam_zero_distance);
	float drawFactor = [[UNIVERSE gameView] viewSize].width / 100.0;
	float drawRatio2 = drawFactor * collision_radius / sqrt_zero_distance; // equivalent to size on screen in pixels
	
	if (cam_zero_distance > 0.0)
	{
		subdivideLevel = 2 + floor(drawRatio2);
		if (subdivideLevel > 4)
			subdivideLevel = 4;
	}
	OO_ENTER_OPENGL();
	
	OOGL(glPushAttrib(GL_ENABLE_BIT));
	OOGL(glDisable(GL_CULL_FACE));
	
	/*
	 
	The depth test gets disabled in parts of this and instead
	we rely on the painters algorithm instead.
	 
	The depth buffer isn't granular enough to cope with huge objects at vast
	distances.
	 
	*/
	BOOL ignoreDepthBuffer = cam_zero_distance > collision_radius * collision_radius * 25;
	
	int steps = 2 * (MAX_SUBDIVIDE - subdivideLevel);
	
	// far enough away to draw flat ?
	if (ignoreDepthBuffer)
	{
		OOGL(glDisable(GL_DEPTH_TEST));
	}
	
	OOGL(glDisable(GL_TEXTURE_2D));
	OOGL(glDisable(GL_LIGHTING));
	OOGL(glColor3fv(discColor));
	
	// FIXME: use vertex arrays
	OOGLBEGIN(GL_TRIANGLE_FAN);
		GLDrawBallBillboard(collision_radius, steps, sqrt_zero_distance);
	OOGLEND();
	
	if (![UNIVERSE reducedDetail])
	{
		OOGL(glDisable(GL_DEPTH_TEST));
		if (cam_zero_distance < lim4k)
		{
			[self drawActiveCoronaWithInnerRadius:collision_radius
											width:cor4k
											 step:steps
										zDistance:sqrt_zero_distance
											color:innerCoronaColor
											   rv:6];
		}
		if (cam_zero_distance < lim8k)
		{
			[self drawActiveCoronaWithInnerRadius:collision_radius
											width:cor8k
											 step:steps
										zDistance:sqrt_zero_distance
											color:middleCoronaColor
											   rv:3];
		}
		if (cam_zero_distance < lim16k)
		{
			[self drawActiveCoronaWithInnerRadius:collision_radius
											width:cor16k
											 step:steps
										zDistance:sqrt_zero_distance
											color:outerCoronaColor
											   rv:0];
		}
	}
	
	OOGL(glPopAttrib());
	CheckOpenGLErrors(@"SunEntity after drawing %@", self);
}


- (void) drawActiveCoronaWithInnerRadius:(float)inner_radius
								   width:(float)width
									step:(float)step
							   zDistance:(float)z_distance
								   color:(GLfloat[4])color
									  rv:(int)rv
{
	if (EXPECT_NOT(inner_radius >= z_distance))  return;	// inside the sphere
	
	GLfloat outer_radius = inner_radius + width;
	
	NSRange activity = { 0.34, 1.0 };
	
	GLfloat				si, ci;
	GLfloat				s0, c0, s1, c1;
	
	GLfloat				r = inner_radius;
	GLfloat				c = outer_radius;
	GLfloat				z = z_distance;
	GLfloat				x = sqrtf(z * z - r * r);
	
	GLfloat				r1 = r * x / z;
	GLfloat				z1 = r * r / z;
	
	GLfloat				r0 = c * x / z;
	GLfloat				z0 = c * r / z;
	
	GLfloat				rv0, rv1, rv2;
	GLfloat				pt0, pt1;
	
	unsigned short		i;
	GLfloat				theta = 0.0f, delta;
	
	delta = step * M_PI / 180.0f;	// Convert step from degrees to radians
	pt0=(1.0 - corona_stage) * corona_blending;
	pt1=corona_stage * corona_blending;
	
	OO_ENTER_OPENGL();
	
	OOGL(glShadeModel(GL_SMOOTH));
	OOGLBEGIN(GL_TRIANGLE_STRIP);
		for (i = 0; i < 360; i += step)
		{
			si = sinf(theta);
			ci = cosf(theta);
			theta += delta;
			
			rv0 = pt0 * rvalue[i + rv] + pt1 * rvalue[i + rv + 360];
			rv1 = pt0 * rvalue[i + rv + 1] + pt1 * rvalue[i + rv + 361];
			rv2 = pt0 * rvalue[i + rv + 2] + pt1 * rvalue[i + rv + 362];

			s1 = r1 * si;
			c1 = r1 * ci;
			glColor4f(color[0] * (activity.location + rv0*activity.length), color[1] * (activity.location + rv1*activity.length), color[2] * (activity.location + rv2*activity.length), color[3]);
			glVertex3f(s1, c1, -z1);

			s0 = r0 * si;
			c0 = r0 * ci;
			glColor4f(color[0], color[1], color[2], 0);
			glVertex3f(s0, c0, -z0);
		}
	
		rv0 = pt0 * rvalue[rv] + pt1 * rvalue[360 + rv];
		rv1 = pt0 * rvalue[1 + rv] + pt1 * rvalue[361 + rv];
		rv2 = pt0 * rvalue[2 + rv] + pt1 * rvalue[362 + rv];
		
		glColor4f(color[0] * (activity.location + rv0*activity.length), color[1] * (activity.location + rv1*activity.length), color[2] * (activity.location + rv2*activity.length), color[3]);
		glVertex3f(0.0, r1, -z1);	//repeat the zero value to close
		glColor4f(color[0], color[1], color[2], 0);
		glVertex3f(0.0, r0, -z0);	//repeat the zero value to close
	OOGLEND();
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


- (void) setRadius:(double) rad
{
	collision_radius = rad;
	cor4k =		rad * 4 / 100;				lim4k =		cor4k	* cor4k	* NO_DRAW_DISTANCE_FACTOR*NO_DRAW_DISTANCE_FACTOR;
	cor8k =		rad * 8 / 100;				lim8k =		cor8k	* cor8k	* NO_DRAW_DISTANCE_FACTOR*NO_DRAW_DISTANCE_FACTOR;
	cor16k =	rad * rad * 16/ 10000000;	lim16k =	cor16k	* cor16k* NO_DRAW_DISTANCE_FACTOR*NO_DRAW_DISTANCE_FACTOR;
}


- (void) setPosition:(Vector) posn
{
	[super setPosition: posn];
	[UNIVERSE setMainLightPosition: posn];
}


- (BOOL) willGoNova
{
	return throw_sparks;
}


- (BOOL) goneNova
{
	return throw_sparks && velocity.x <= 0;
}


- (void) setGoingNova:(BOOL) yesno inTime:(double)interval
{
	throw_sparks = yesno;
	if (throw_sparks)
	{
		velocity.x = fmax(interval, 0.0);
		OOLog(@"script.debug.setSunNovaIn", @"NOVA activated! time until Nova : %.1f s", velocity.x);
	}
	
	velocity.y = 0;
	velocity.z = 10000;
}


- (BOOL) isSun
{
	return YES;
}


- (BOOL) isVisible
{
	return YES;
}

@end
