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


enum
{
	kFreeListMax				= 16
};


static uint32_t					sFreeListCount = 0;
static OOSoundSource			*sFreeList = nil;


@implementation OOSoundSource

+ (id)alloc
{
	OOSoundSource				*result = nil;
	
	[gOOCASoundSyncLock lock];
	if (nil != sFreeList)
	{
		result = sFreeList;
		sFreeList = (OOSoundSource *)result->_channel;
		result->_channel = nil;
	}
	[gOOCASoundSyncLock unlock];
	
	if (nil == result)
	{
		result = [super alloc];
	}
	
	return result;
}


- (void)dealloc
{
	if (nil != _channel) [self stop];
	
	if (sFreeListCount < kFreeListMax)
	{
		// It’s OK to do locking after test since the count doesn’t need to be precise.
		[gOOCASoundSyncLock lock];
		_channel = (OOCASoundChannel *)sFreeList;
		sFreeList = self;
		_loop = NO;
		[gOOCASoundSyncLock unlock];
		return;
	}
	[super dealloc];
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


- (void)setLoop:(BOOL)inLoop
{
	_loop = inLoop;
}


- (void)playSound:(OOSound *)inSound
{
	[self playSound:inSound repeatCount:1];
}


- (void)playSound:(OOSound *)inSound repeatCount:(uint8_t)inCount
{
	if (nil == inSound || 0 == inCount) return;
	
	[gOOCASoundSyncLock lock];
	
	if (nil != _channel)
	{
		[self stop];
	}
	
	_channel = [[OOCASoundMixer mixer] popChannel];
	if (nil != _channel)
	{
		_playCount = inCount;
		_playing = YES;
		[_channel setDelegate:self];
		[_channel playSound:inSound looped:_loop];
		[self retain];
	}
	[gOOCASoundSyncLock unlock];
}


- (void)playOrRepeatSound:(OOSound *)inSound
{
	if (nil == inSound) return;
	
	[gOOCASoundSyncLock lock];
	if ([_channel sound] == inSound)
	{
		++_playCount;
	}
	else
	{
		[self playSound:inSound repeatCount:1];
	}
	[gOOCASoundSyncLock unlock];
}


- (void)stop
{
	[gOOCASoundSyncLock lock];
	if (nil != _channel)
	{
		[_channel setDelegate:[self class]];
		[_channel stop];
		_channel = nil;
		[self release];
		_playCount = 0;
	}
	
	_playing = NO;
	[gOOCASoundSyncLock unlock];
}


- (BOOL)isPlaying
{
	return _playing;
}


- (void)channel:(OOCASoundChannel *)inChannel didFinishPlayingSound:(OOSound *)inSound
{
	assert(_channel == inChannel);
	
	[gOOCASoundSyncLock lock];
//	if (_loop && _playing) ++_playCount;	// Moved responsibility for looping into sounds
	
	if (--_playCount)
	{
		[_channel playSound:inSound looped:_loop];
	}
	else
	{
		[_channel setDelegate:nil];
		[[OOCASoundMixer mixer] pushChannel:_channel];
		_channel = nil;
		_playing = NO;
		[self release];
	}
	[gOOCASoundSyncLock unlock];
}


+ (void)channel:(OOCASoundChannel *)inChannel didFinishPlayingSound:(OOSound *)inSound
{
	[[OOCASoundMixer mixer] pushChannel:inChannel];
}


@end
