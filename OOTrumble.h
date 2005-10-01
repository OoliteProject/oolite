//
//  OOTrumble.h
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

#ifdef GNUSTEP
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "gnustep-oolite.h"
#include "oolite-linux.h"
#import "OOSound.h"
#else
#import <Cocoa/Cocoa.h>
#endif
#import <OpenGL/gl.h>

@class PlayerEntity, AI, OOSound;

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
    PlayerEntity*	player;	// owning entity (not retained)
	//
	unichar			digram[2];	// seed for pseudo-randomly setting up Trumble (pair of characters)
	//
	GLfloat			colorBase[4];	// color of Trumble
	GLfloat			colorPoint1[4];	// color of Trumble (variation 1)
	GLfloat			colorPoint2[4];	// color of Trumble	(variation 2)
	GLfloat			colorEyes[4];	// color of Trumble (eye color)
	GLfloat*		pointColor[6];	// pointscheme
	//
	GLfloat			hunger;		// behaviour modifier 0.0 (satiated) to 1.0 (starving)
	GLfloat			discomfort;	// behaviour modifier 0.0 (very happy) to 1.0 (extremely uncomfortable)
	//
	GLfloat			size;			// 0.0 -> max_size
	GLfloat			max_size;		// 0.90 -> 1.25
	GLfloat			growth_rate;	// diff to size per sec.
	//
	GLfloat			rotation;	// CW rotation in radians (starts at 0.0)
	GLfloat			rotational_velocity;	// +r (radians/sec)
	//
	NSPoint			position;	// x, y onscreen relative to center of screen
	NSPoint			movement;	// +x, +y (screen units / sec)
	//
	NSPoint			eye_position;	// current position of eyes relative to their starting position
	NSPoint			mouth_position;	// current position of eyes relative to their starting position
	//
	OOSound*		prootSound;	// FMOD Sample (retained)
	OOSound*		squealSound;	// FMOD Sample (retained)
	//
	double			animationTime;	// set to 0.0 at start of current animation
	double			animationDuration;	// set to 0.0 at start of current animation
	//
	enum trumble_animation	animation;		// current animation sequence
	enum trumble_animation	nextAnimation;	// next animation sequence
	//
	int animationStage;	// sub-sequence within animation
	//
	enum trumble_mouth		mouthFrame;	// which mouth position - determines what part of the texture to display
	enum trumble_eyes		eyeFrame;	// which eye position - determines what part of the texture to display
	//
	GLuint			textureName;	// OpenGL texture reference
	//
	GLfloat			saved_float1, saved_float2;
	//
	BOOL			readyToSpawn;
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
