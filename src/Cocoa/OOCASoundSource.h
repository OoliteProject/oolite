/*

OOCASoundSource.h

A sound source.
Each playing sound is associated with a sound source, either explicitly or by
creating one on the fly. Each sound source can play one sound at a time, and
has a number of attributes related to positional audio (which is currently
unimplemented).

OOCASound - Core Audio sound implementation for Oolite.
Copyright (C) 2005-2006  Jens Ayton

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
#import "vector.h"
#import "OOCASoundReferencePoint.h"

@class OOSound, OOCASoundChannel;


@interface OOSoundSource: NSObject
{
	OOSound						*sound;
	OOCASoundChannel			*channel;
	BOOL						loop;
	uint8_t						repeatCount,
								remainingCount;
}

+ (id)sourceWithSound:(OOSound *)inSound;
- (id)initWithSound:(OOSound *)inSound;
- (id)init;

// These options should be set before playing. Effect of setting them while playing is undefined.
- (OOSound *)sound;
- (void)setSound:(OOSound *)inSound;
- (BOOL)loop;
- (void)setLoop:(BOOL)inLoop;
- (uint8_t)repeatCount;
- (void)setRepeatCount:(uint8_t)inCount;

- (BOOL)isPlaying;
- (void)play;
- (void)playOrRepeat;
- (void)stop;

// Conveniences:
- (void)playSound:(OOSound *)inSound;
- (void)playSound:(OOSound *)inSound repeatCount:(uint8_t)inCount;
- (void)playOrRepeatSound:(OOSound *)inSound;

// Positional audio attributes are ignored in this implementation
- (void)setPositional:(BOOL)inPositional;
- (void)setPosition:(Vector)inPosition;
- (void)setVelocity:(Vector)inVelocity;
- (void)setOrientation:(Vector)inOrientation;
- (void)setConeAngle:(float)inAngle;
- (void)setGainInsideCone:(float)inInside outsideCone:(float)inOutside;
- (void)positionRelativeTo:(OOSoundReferencePoint *)inPoint;

@end
