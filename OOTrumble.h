//
//  OOTrumble.h
//  Oolite
//
//  Created by Giles Williams on 18/07/2005.
//  Copyright 2005 __MyCompanyName__. All rights reserved.
//

#ifdef GNUSTEP
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "gnustep-oolite.h"
#else
#import <Cocoa/Cocoa.h>
#endif
#import <OpenGL/gl.h>

@class PlayerEntity, AI, OOSound;

enum trumble_animation
{
	TRUMBLE_ANIM_NONE = 0,
	TRUMBLE_ANIM_BLINK,
	TRUMBLE_ANIM_SNARL,
	TRUMBLE_ANIM_PROOT,
	TRUMBLE_ANIM_SHUDDER,
	TRUMBLE_ANIM_STONED,
	TRUMBLE_ANIM_SPAWN
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

@interface OOTrumble : NSObject
{
    PlayerEntity*	*player;	// owning entity (not retained)
	//
	BOOL			active;		// YES/NO
	//
	unichar			digram[2];	// seed for pseudo-randomly setting up Trumble (pair of characters)
	//
	GLfloat			colorBase[4];	// color of Trumble
	GLfloat			colorPoint1[4];	// color of Trumble (variation 1)
	GLfloat			colorPoint2[4];	// color of Trumble	(variation 2)
	GLfloat			colorEyes[4];	// color of Trumble (eye color)
	//
	GLfloat			hunger;		// behaviour modifier 0.0 (satiated) to 1.0 (starving)
	GLfloat			discomfort;	// behaviour modifier 0.0 (very happy) to 1.0 (extremely uncomfortable)
	//
	AI*				ai;			// AI to control animation (retained)
	//
	OOSound*		prootSound;	// FMOD Sample (retained)
	//
	NSPoint			position;	// x, y onscreen relative to center of screen
	GLfloat			rotation;	// CW rotation in radians (starts at 0.0)
	NSPoint			movement;	// +x, +y (screen units / sec)
	GLfloat			rotational_velocity;	// +r (radians/sec)
	GLfloat			size;			// 0.0 -> 1.0 (radians/sec)
	GLfloat			growth_rate;	// diff to size per sec.
	//
	NSTimeInterval referenceTime;	// set at start of current animation
	//
	enum trumble_animation	animation;	// current animation sequence
	//
	enum trumble_mouth		mouthFrame;	// which mouth position - determines what part of the texture to display
	enum trumble_eyes		eyeFrame;	// which eye position - determines what part of the texture to display
	//
	NSPoint			eye_position;	// current position of eyes relative to their starting position
	//
	NSPoint			mouth_position;	// current position of eyes relative to their starting position
	//
	GLuint			textureName;	// OpenGL texture reference
	//
}

// AI methods here
- (void) actionBlink;
- (void) actionSnarl;
- (void) actionProot;
- (void) actionShudder;
- (void) actionStoned;
- (void) actionPop;

@end
