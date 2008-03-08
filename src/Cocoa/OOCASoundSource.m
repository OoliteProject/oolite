/*

OOCASoundSource.m

OOCASound - Core Audio sound implementation for Oolite.
Copyright (C) 2005-2006 Jens Ayton

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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2005-2008 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOCASoundInternal.h"


@implementation OOSoundSource

#pragma mark NSObject

- (void)dealloc
{
	[self stop];
	[sound autorelease];
	
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
	loop = !!inLoop;
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
	[self playSound:inSound repeatCount:repeatCount];
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
