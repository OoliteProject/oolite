//	
//	OOCASoundSource.m
//	CoreAudio sound implementation for Oolite
//	
/*

Copyright © 2005 Jens Ayton
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

#import "OOCASoundInternal.h"


@implementation OOSoundSource

#pragma mark NSObject

- (void)dealloc
{
	if (nil != channel) [self stop];
	[sound release];
	
	[super dealloc];
}


- (id)init
{
	return [super init];
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
	if (nil == channel) [self play];
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
	if (channel) [self stop];
	[self setSound:inSound];
	[self play];
}


- (void)playSound:(OOSound *)inSound repeatCount:(uint8_t)inCount
{
	if (channel) [self stop];
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
