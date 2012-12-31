/*

OOTrumble.h

Implements cute, fuzzy trumbles.

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

#import <Foundation/Foundation.h>
#import "OOOpenGL.h"


@class PlayerEntity, AI, OOSound, OOTexture;

#define TRUMBLE_MAX_ROTATION				15.0
#define TRUMBLE_MAX_ROTATIONAL_VELOCITY		5.0

#define TRUMBLE_GROWTH_RATE					0.01

enum trumble_animation
{
	TRUMBLE_ANIM_NONE = 0,
	TRUMBLE_ANIM_IDLE,
	TRUMBLE_ANIM_BLINK,
	TRUMBLE_ANIM_SNARL,
	TRUMBLE_ANIM_PROOT,
	TRUMBLE_ANIM_SHUDDER,
	TRUMBLE_ANIM_STONED,
	TRUMBLE_ANIM_SPAWN,
	TRUMBLE_ANIM_SLEEP,
	TRUMBLE_ANIM_DIE
};

enum trumble_eyes
{
	TRUMBLE_EYES_NONE = 0,
	TRUMBLE_EYES_OPEN,
	TRUMBLE_EYES_SHUT,
	TRUMBLE_EYES_WIDE
};

enum trumble_mouth
{
	TRUMBLE_MOUTH_NONE = 0,
	TRUMBLE_MOUTH_POUT,
	TRUMBLE_MOUTH_GROWL,
	TRUMBLE_MOUTH_SNARL,
	TRUMBLE_MOUTH_NORMAL
};

float	trumbleAppetiteAccumulator;

@interface OOTrumble : NSObject
{
@private
	PlayerEntity			*player;	// owning entity (not retained)
	//
	unichar					digram[2];	// seed for pseudo-randomly setting up Trumble (pair of characters)
	//
	GLfloat					colorBase[4];	// color of Trumble
	GLfloat					colorPoint1[4];	// color of Trumble (variation 1)
	GLfloat					colorPoint2[4];	// color of Trumble	(variation 2)
	GLfloat					colorEyes[4];	// color of Trumble (eye color)
	GLfloat					*pointColor[6];	// pointscheme
	//
	GLfloat					hunger;		// behaviour modifier 0.0 (satiated) to 1.0 (starving)
	GLfloat					discomfort;	// behaviour modifier 0.0 (very happy) to 1.0 (extremely uncomfortable)
	//
	GLfloat					size;			// 0.0 -> max_size
	GLfloat					max_size;		// 0.90 -> 1.25
	GLfloat					growth_rate;	// diff to size per sec.
	//
	GLfloat					rotation;	// CW rotation in radians (starts at 0.0)
	GLfloat					rotational_velocity;	// +r (radians/sec)
	//
	NSPoint					position;	// x, y onscreen relative to center of screen
	NSPoint					movement;	// +x, +y (screen units / sec)
	//
	NSPoint					eye_position;	// current position of eyes relative to their starting position
	NSPoint					mouth_position;	// current position of eyes relative to their starting position
	//
	double					animationTime;	// set to 0.0 at start of current animation
	double					animationDuration;	// set to 0.0 at start of current animation
	//
	enum trumble_animation	animation;		// current animation sequence
	enum trumble_animation	nextAnimation;	// next animation sequence
	//
	int						animationStage;	// sub-sequence within animation
	//
	enum trumble_mouth		mouthFrame;	// which mouth position - determines what part of the texture to display
	enum trumble_eyes		eyeFrame;	// which eye position - determines what part of the texture to display
	//
	OOTexture				*texture;
	//
	GLfloat					saved_float1, saved_float2;
	//
	BOOL					readyToSpawn;
}

- (id) initForPlayer:(PlayerEntity*) p1;
- (id) initForPlayer:(PlayerEntity*) p1 digram:(NSString*) digramString;

- (void) setupForPlayer:(PlayerEntity*) p1 digram:(NSString*) digramString;

- (void) spawnFrom:(OOTrumble*) parentTrumble;

- (void) calcGrowthRate;

- (unichar *)	digram;
- (NSPoint)		position;
- (NSPoint)		movement;
- (GLfloat)		rotation;
- (GLfloat)		size;
- (GLfloat)		hunger;
- (GLfloat)		discomfort;

// AI methods here
- (void) actionIdle;
- (void) actionBlink;
- (void) actionSnarl;
- (void) actionProot;
- (void) actionShudder;
- (void) actionStoned;
- (void) actionPop;
- (void) actionSleep;
- (void) actionSpawn;

- (void) randomizeMotionX;
- (void) randomizeMotionY;

- (void) drawTrumble:(double) z;
- (void) updateTrumble:(double) delta_t;

- (void) updateIdle:(double) delta_t;
- (void) updateBlink:(double) delta_t;
- (void) updateSnarl:(double) delta_t;
- (void) updateProot:(double) delta_t;
- (void) updateShudder:(double) delta_t;
- (void) updateStoned:(double) delta_t;
- (void) updatePop:(double) delta_t;
- (void) updateSleep:(double) delta_t;
- (void) updateSpawn:(double) delta_t;

- (NSDictionary*) dictionary;
- (void) setFromDictionary:(NSDictionary*) dict;

@end
