/*

ParticleEntity.h
Created by Giles Williams on 2004-04-03.

Entity subclass implementing a variety of special effects.

For Oolite
Copyright (C) 2004  Giles C Williams

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

#import <Foundation/Foundation.h>
#import "Entity.h"

#import "Universe.h"
#import "vector.h"

#define PARTICLE_TEST				1
#define PARTICLE_SHOT_GREEN_PLASMA	100
#define PARTICLE_SHOT_YELLOW_PLASMA	101
#define PARTICLE_SPARK				102
#define PARTICLE_SHOT_PLASMA		110
#define PARTICLE_LASER_BEAM_RED		150
#define PARTICLE_LASER_BEAM			160
#define PARTICLE_SHOT_EXPIRED		200
#define PARTICLE_EXPLOSION			201
#define PARTICLE_FLASH				230
#define PARTICLE_FIREBALL			240
#define PARTICLE_FRAGBURST			250
#define PARTICLE_BURST2				270
#define PARTICLE_EXHAUST			300
#define PARTICLE_EXHAUST2			301
#define PARTICLE_ECM_MINE			400
#define PARTICLE_ENERGY_MINE		500
#define PARTICLE_FLASHER			600
#define PARTICLE_BILLBOARD			700
#define PARTICLE_HYPERRING			800
#define PARTICLE_MARKER			666

#define PARTICLE_LASER_DURATION		0.20
#define PARTICLE_LASER_LENGTH		10000.0
#define PARTICLE_LASER_RANGE_LIMIT	1000000000.0

#define LASER_FLASH_SIZE			1.0 + 2.0 * randf()

@class Entity;

@interface ParticleEntity : Entity {

    NSString*	textureNameString;
    GLuint		texName;
	
	OOColor*	color;
	GLfloat		color_fv[4];
	
	double		alpha;
	double		time_counter;
	
	double		duration;
	double		activation_time;
	double		growth_rate;
		
	double		ring_inner_radius, ring_outer_radius;
		
	int			particle_type;
	
	double		alpha_for_vertex[MAX_VERTICES_PER_ENTITY];
		
    NSSize	size;

	Vector exhaustScale;
	GLfloat exhaustBaseColors[34 * 4], verts[34 * 3];
}

- (id) initLaserFromShip:(ShipEntity *) ship view:(int) view;
- (id) initLaserFromShip:(ShipEntity *) ship view:(int) view offset:(Vector)offset;
- (id) initLaserFromSubentity:(ShipEntity *) subent view:(int) view;
- (id) initExhaustFromShip:(ShipEntity *) ship offsetVector:(Vector) offset scaleVector:(Vector) scale;
- (id) initExhaustFromShip:(ShipEntity *) ship details:(NSString *) details;
- (id) initECMMineFromShip:(ShipEntity *) ship;
- (id) initEnergyMineFromShip:(ShipEntity *) ship;
- (id) initHyperringFromShip:(ShipEntity *) ship;
- (id) initFragburstFromPosition:(Vector) fragPos;
- (id) initFragburstSize:(GLfloat) fragSize FromPosition:(Vector) fragPos;
- (id) initBurst2FromPosition:(Vector) fragPos;
- (id) initBurst2Size:(GLfloat) burstSize FromPosition:(Vector) fragPos;
- (id) initFlashSize:(GLfloat) burstSize FromPosition:(Vector) fragPos;
- (id) initFlashSize:(GLfloat) flashSize FromPosition:(Vector) fragPos Color:(OOColor*) flashColor;
- (id) initBillboard:(NSSize) billSize withTexture:(NSString*) textureFile;

- (void) updateExplosion:(double) delta_t;
- (void) updateFlasher:(double) delta_t;
- (void) updateECMMine:(double) delta_t;
- (void) updateEnergyMine:(double) delta_t;
- (void) updateShot:(double) delta_t;
- (void) updateSpark:(double) delta_t;
- (void) updateLaser:(double) delta_t;
- (void) updateHyperring:(double) delta_t;
- (void) updateFragburst:(double) delta_t;
- (void) updateBurst2:(double) delta_t;
- (void) updateExhaust2:(double) delta_t;
- (void) updateFlash:(double) delta_t;

- (void) setTexture:(NSString *) filename;
- (void) setColor:(OOColor *) a_color;

- (void) setParticleType:(int) p_type;
- (int) particleType;

- (void) setDuration:(double) dur;
- (void) setSize:(NSSize) siz;
- (NSSize) size;

- (void) initialiseTexture: (NSString *) name;

- (void) drawParticle;
- (void) drawLaser;
- (void) drawExhaust2;
- (void) drawHyperring;
- (void) drawEnergyMine;
- (void) drawFragburst;
- (void) drawBurst2;
- (void) drawBillboard;
//- (void) drawFlash;

void drawQuadForView(Universe* universe, GLfloat x, GLfloat y, GLfloat z, GLfloat xx, GLfloat yy);

@end
