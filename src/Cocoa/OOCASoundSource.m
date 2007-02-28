/*

OOCASoundSource.m

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

#import "OOCASoundInternal.h"


@implementation OOSoundSource

#pragma mark NSObject

- (id)init
{
	return [super init];
}


- (void)dealloc
{
	if (nil != channel) [self stop];
	[sound release];
	
	[super dealloc];
}


- (NSString *)description
{
	if ([self isPlaying])
	{
		return [NSString stringWithFormat:@"<%@ %p>{sound=%@, loop=%s, repeatCount=%u, playing on channel %@}", [self className], self, sound, [self loop] ? "YES" : "NO", [self repeatCount], channel];
	}
	else
	{
		return [NSString stringWithFormat:@"<%@ %p>{sound=%@, loop=%s, repeatCount=%u, not playing}", [self className], self, sound, [self loop] ? "YES" : "NO", [self repeatCount]];
	}
}


#pragma mark OOSoundSource

+ (id)sourceWithSound:(OOSound *)inSound
{
	return [[[self alloc] initWithSound:inSound] autorelease];
}


- (id)initWithSound:(OOSound *)inSound
{
	self = [self init];
	if (!self) return nil;
	
	[self setSound:inSound];
	
	return self;
}


- (OOSound *)sound
{
	return sound;
}


- (void)setSound:(OOSound *)inSound
{
	if (sound != inSound)
	{
		[sound autorelease];
		sound = [inSound retain];
	}
}


- (BOOL)loop
{
	return loop;
}


- (void)setLoop:(BOOL)inLoop
{
	loop = 0 != inLoop;
}


- (uint8_t)repeatCount
{
	return repeatCount ? repeatCount : 1;
}


- (void)setRepeatCount:(uint8_t)inCount
{
	repeatCount = inCount;
}


- (BOOL)isPlaying
{
	return (nil != channel);
}


- (void)play
{
	if (nil == sound) return;
	
	[gOOCASoundSyncLock lock];
	
	if (channel) [self stop];
	
	channel = [[OOCASoundMixer mixer] popChannel];
	if (nil != channel)
	{
		remainingCount = [self repeatCount];
		[channel setDelegate:self];
		[channel playSound:sound looped:loop];
		[self retain];
	}
	[gOOCASoundSyncLock unlock];
}


- (void)playOrRepeat
{
	if (![self isPlaying]) [self play];
	else ++remainingCount;
}


- (void)stop
{
	[gOOCASoundSyncLock lock];
	if (nil != channel)
	{
		[channel setDelegate:[self class]];
		[channel stop];
		channel = nil;
		[self release];
	}
	
	[gOOCASoundSyncLock unlock];
}


- (void)playSound:(OOSound *)inSound
{
	[self stop];
	[self setSound:inSound];
	[self play];
}


- (void)playSound:(OOSound *)inSound repeatCount:(uint8_t)inCount
{
	[self stop];
	[self setSound:inSound];
	[self setRepeatCount:inCount];
	[self play];
}


- (void)playOrRepeatSound:(OOSound *)inSound
{
	if (sound != inSound) [self playSound:inSound];
	else [self playOrRepeat];
}


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


#pragma mark (OOCASoundChannelDelegate)

- (void)channel:(OOCASoundChannel *)inChannel didFinishPlayingSound:(OOSound *)inSound
{
	assert(channel == inChannel);
	
	[gOOCASoundSyncLock lock];
	
	if (--remainingCount)
	{
		[channel playSound:sound looped:NO];
	}
	else
	{
		[channel setDelegate:nil];
		[[OOCASoundMixer mixer] pushChannel:channel];
		channel = nil;
		[self release];
	}
	[gOOCASoundSyncLock unlock];
}


+ (void)channel:(OOCASoundChannel *)inChannel didFinishPlayingSound:(OOSound *)inSound
{
	// This delegate is used for a stopped source
	[[OOCASoundMixer mixer] pushChannel:inChannel];
}

@end
