/*

OOSunEntity.h

Entity subclass representing a sun.

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


#import "OOPlanetEntity.h"

#import "Entity.h"
#import "legacy_random.h"
#import "OOColor.h"


#define SUN_CORONA_SAMPLES		729			// Samples at half-degree intervals, with a bit of overlap.
#define MAX_CORONAFLARE			600000.0	// nova flare


@class ShipEntity;


@interface OOSunEntity: Entity <OOStellarBody>
{
@private
	GLfloat					sun_diffuse[4];
	GLfloat					sun_specular[4];
	
	GLfloat					discColor[4];
	GLfloat					innerCoronaColor[4];
	GLfloat					middleCoronaColor[4];
	GLfloat					outerCoronaColor[4];
	
	GLfloat					cor4k, lim4k;
	GLfloat					cor8k, lim8k;
	GLfloat					cor16k, lim16k;
	
	double					corona_speed_factor;		// multiply delta_t by this before adding it to corona_stage
	double					corona_stage;				// 0.0 -> 1.0
	GLfloat					rvalue[SUN_CORONA_SAMPLES];	// stores random values for adjusting colors in the corona
	float					corona_blending;
	
	OOTimeDelta				_novaCountdown;
	OOTimeDelta				_novaExpansionTimer;
	float					_novaExpansionRate;
}

- (id) initSunWithColor:(OOColor*)sun_color andDictionary:(NSDictionary*) dict;
- (BOOL) setSunColor:(OOColor*)sun_color;
- (BOOL) changeSunProperty:(NSString *)key withDictionary:(NSDictionary*) dict;

- (OOStellarBodyType) planetType;

- (void) getDiffuseComponents:(GLfloat[4])components;
- (void) getSpecularComponents:(GLfloat[4])components;

- (GLfloat) radius;	// metres
- (void) setRadius:(GLfloat) rad;

- (BOOL) willGoNova;
- (BOOL) goneNova;
- (void) setGoingNova:(BOOL) yesno inTime:(double)interval;

- (void) drawUnconditionally;

@end
