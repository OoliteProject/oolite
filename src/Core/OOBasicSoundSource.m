/*

OOBasicSoundSource.m

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
