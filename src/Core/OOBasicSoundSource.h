/*

OOBasicSoundSource.h

Transitional implementation of OOSoundSource which relies on
conceptually-legacy OOSound methods.

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

#import <Foundation/Foundation.h>
#import "OOMaths.h"
#import "OOBasicSoundReferencePoint.h"

@class OOSound;


@interface OOSoundSource: NSObject
{
	OOSound						*_sound;
	BOOL						_loop;
	uint8_t						_playCount;
}

// Positional audio attributes are ignored in this implementation
- (void)setPositional:(BOOL)inPositional;
- (void)setPosition:(Vector)inPosition;
- (void)setVelocity:(Vector)inVelocity;
- (void)setOrientation:(Vector)inOrientation;
- (void)setConeAngle:(float)inAngle;
- (void)setGainInsideCone:(float)inInside outsideCone:(float)inOutside;
- (void)positionRelativeTo:(OOSoundReferencePoint *)inPoint;

- (void)setLoop:(BOOL)inLoop;

- (void)playSound:(OOSound *)inSound;
// repeatCount lets a sound be played a fixed number of times. If looping is on, it will play the specified number of times after looping is switched off.
- (void)playSound:(OOSound *)inSound repeatCount:(uint8_t)inCount;
// -playOrRepeatSound will increment the repeat count if the sound is already playing.
- (void)playOrRepeatSound:(OOSound *)inSound;
- (void)stop;
- (BOOL)isPlaying;

// Called by OOSound +update.
+ (void)update;

@end
