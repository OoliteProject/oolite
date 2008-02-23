/*

ParticleEntity.h

Entity subclass implementing a variety of special effects.

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

#import "OOSelfDrawingEntity.h"

#import "Universe.h"
#import "OOMaths.h"

#define PARTICLE_LASER_DURATION		0.20
#define PARTICLE_LASER_LENGTH		10000.0
#define PARTICLE_LASER_RANGE_LIMIT	1000000000.0

#define LASER_FLASH_SIZE			(1.0 + 2.0 * randf())

@class OOTexture;


@interface ParticleEntity: OOSelfDrawingEntity
{
	OOTexture		*texture;
	
	OOColor			*color;
	GLfloat			color_fv[4];
	
	GLfloat			alpha;
	OOTimeDelta		time_counter;
	
	OOTimeDelta		duration;
	OOTimeDelta		activation_time;
	double			growth_rate;
	
	GLfloat			ring_inner_radius, ring_outer_radius;
	
	int				particle_type;
	
	GLfloat			alpha_for_vertex[MAX_VERTICES_PER_ENTITY];
		
    NSSize			size;

	Vector			exhaustScale;
	GLfloat			exhaustBaseColors[34 * 4], verts[34 * 3];
}

- (id) initLaserFromShip:(ShipEntity *) ship view:(int) view offset:(Vector)offset;
- (id) initExhaustFromShip:(ShipEntity *) ship details:(NSString *) details;
- (id) initECMMineFromShip:(ShipEntity *) ship;
- (id) initEnergyMineFromShip:(ShipEntity *) ship;
- (id) initHyperringFromShip:(ShipEntity *) ship;
- (id) initFragburstSize:(GLfloat) fragSize fromPosition:(Vector) fragPos;
- (id) initBurst2Size:(GLfloat) burstSize fromPosition:(Vector) fragPos;
- (id) initFlashSize:(GLfloat) burstSize fromPosition:(Vector) fragPos;
- (id) initFlashSize:(GLfloat) flashSize fromPosition:(Vector) fragPos color:(OOColor*) flashColor;
- (id) initBillboard:(NSSize) billSize withTexture:(NSString*) textureFile;
- (id) initFlasherWithSize:(float)size frequency:(float)frequency phase:(float)phase;
- (id) initPlasmaShotAt:(Vector)position velocity:(Vector)velocity energy:(float)energy duration:(OOTimeDelta)duration color:(OOColor *)color;
- (id) initSparkAt:(Vector)position velocity:(Vector)velocity duration:(OOTimeDelta)duration size:(float)size color:(OOColor *)color;

- (void) setColor:(OOColor *) a_color;

- (void) setDuration:(double) dur;
- (void) setSize:(NSSize) siz;
- (NSSize) size;


@end


@interface Entity (OOParticleExtensions)

- (BOOL)isParticle;
- (BOOL)isFlasher;
- (BOOL)isExhaust;

@end
