//	
//	OOBasicSoundSource.m
//	Transitional sound implementation for Oolite
//	
/*

Copyright © 2005, Jens Ayton
All rights reserved.

This work is licensed under the Creative Commons Attribution-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

#import "OOBasicSoundSource.h"
#import "OOSound.h"

@interface OOSoundSource (Private)

- (void)update;

@end


static NSMutableSet			*sUpdateSet = nil;


@implementation OOSoundSource


- (void)positionRelativeTo:(OOSoundReferencePoint *)inPoint
{
	
}


- (void)setPositional:(BOOL)inPositional
{
	
}


- (void)setPosition:(Vector)inPosition
{
	
}


- (void)setVelocity:(Vector)inVelocity
{
	
}


- (void)setOrientation:(Vector)inOrientation
{
	
}


- (void)setConeAngle:(float)inAngle
{
	
}


- (void)setGainInsideCone:(float)inInside outsideCone:(float)inOutside
{
	
}


- (void)setLoop:(BOOL)inLoop
{
	_loop = !!inLoop;
}


- (void)playSound:(OOSound *)inSound
{
	[self playSound:inSound repeatCount:1];
}


- (void)playSound:(OOSound *)inSound repeatCount:(uint8_t)inCount
{
	if (nil == inSound || 0 == inCount) return;
	
	[self stop];
	_sound = [inSound retain];
	[_sound play];
	
	_playCount = inCount;
	
	if (nil == sUpdateSet) sUpdateSet = [[NSMutableSet alloc] init];
	[sUpdateSet addObject:self];
}


- (void)playOrRepeatSound:(OOSound *)inSound
{
	if (nil == inSound) return;
	
	if (_sound == inSound)
	{
		++_playCount;
	}
	else
	{
		[self playSound:inSound repeatCount:1];
	}
}


- (void)stop
{
	if (nil != _sound)
	{
		[_sound stop];
		[_sound release];
		_sound = nil;
		[sUpdateSet removeObject:self];
		_playCount = 0;
	}
}


- (BOOL)isPlaying
{
	return [_sound isPlaying];
}


+ (void)update
{
	[sUpdateSet makeObjectsPerformSelector:@selector(update)];
}


- (void)update
{
	if (![_sound isPlaying])
	{
		if (_loop) ++_playCount;
		if (--_playCount)
		{
			[_sound play];
		}
		else
		{
			[self stop];
		}
	}
}


- (NSString *)description
{
	NSString				*repeatString;
	
	if (_loop) repeatString = @"loop";
	else if (_playCount <= 1) repeatString = @"none";
	else repeatString = [NSString stringWithFormat:@"%u", _playCount];
	
	return [NSString stringWithFormat:@"<%@ %p>{sound=%@, repeat=%@}", [self className], self, _sound, repeatString];
}

@end
