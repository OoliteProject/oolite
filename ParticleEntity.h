//
//  ParticleEntity.h
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

#import <Foundation/Foundation.h>
#import "Entity.h"

#import "Universe.h"
#import "vector.h"

#define PARTICLE_TEST				1
#define PARTICLE_SHOT_EXPIRED		200
#define PARTICLE_EXPLOSION			201
#define PARTICLE_FRAGBURST			250
#define PARTICLE_BURST2				270
#define PARTICLE_SHOT_GREEN_PLASMA	100
#define PARTICLE_SHOT_YELLOW_PLASMA	101
#define PARTICLE_SPARK				102
#define PARTICLE_SHOT_PLASMA		110
#define PARTICLE_LASER_BEAM_RED		150
#define PARTICLE_LASER_BEAM			160
#define PARTICLE_EXHAUST			300
#define PARTICLE_ECM_MINE			400
#define PARTICLE_ENERGY_MINE		500
#define PARTICLE_FLASHER			600
#define PARTICLE_HYPERRING			800
#define PARTICLE_MARKER			666

#define PARTICLE_LASER_DURATION		0.20
#define PARTICLE_LASER_LENGTH		10000.0
#define PARTICLE_LASER_RANGE_LIMIT	1000000000.0

@class Entity;

@interface ParticleEntity : Entity {

    NSString*	textureNameString;
    GLuint		texName;
	
	NSColor*	color;
	GLfloat		color_fv[4];
	
	double		alpha;
	double		time_counter;
	
	double		duration;
	double		activation_time;
		
	double		ring_inner_radius, ring_outer_radius;
		
	int			particle_type;
	
	double		alpha_for_vertex[MAX_VERTICES_PER_ENTITY];
		
    NSSize	size;
}

- (id) initLaserFromShip:(ShipEntity *) ship view:(int) view;
- (id) initExhaustFromShip:(ShipEntity *) ship offsetVector:(Vector) offset scaleVector:(Vector) scale;
- (id) initExhaustFromShip:(ShipEntity *) ship details:(NSString *) details;
- (id) initECMMineFromShip:(ShipEntity *) ship;
- (id) initEnergyMineFromShip:(ShipEntity *) ship;
- (id) initHyperringFromShip:(ShipEntity *) ship;
- (id) initFragburstFromPosition:(Vector) fragPos;
- (id) initBurst2FromPosition:(Vector) fragPos;

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

- (void) setTexture:(NSString *) filename;
- (void) setColor:(NSColor *) a_color;

- (void) setParticleType:(int) p_type;
- (int) particleType;

- (void) setDuration:(double) dur;
- (void) setSize:(NSSize) siz;
- (NSSize) size;

- (void) initialiseTexture: (NSString *) name;

- (void) drawParticle;
- (void) drawLaser;
- (void) drawExhaust:(BOOL) immediate;
- (void) drawHyperring;
- (void) drawEnergyMine;
- (void) drawFragburst;
- (void) drawBurst2;

@end
