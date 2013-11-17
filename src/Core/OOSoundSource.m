/*

OOSoundSource.m
 

Copyright (C) 2006-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOSoundInternal.h"
#import "OOLogging.h"
#import "OOMaths.h"

static NSMutableSet *sPlayingSoundSources;


@implementation OOSoundSource

+ (instancetype) sourceWithSound:(OOSound *)inSound
{
	return [[[self alloc] initWithSound:inSound] autorelease];
}


- (id) init
{
	self = [super init];
	if (!self) return nil;
	
	_positional = NO;
	_position = kZeroVector;
	_gain = 1.0;
	return self;
}


- (id) initWithSound:(OOSound *)inSound
{
	self = [self init];
	if (!self) return nil;
	
	[self setSound:inSound];
	
	return self;
}


- (void) dealloc
{
	[self stop];
	[_sound autorelease];
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	if ([self isPlaying])
	{
		return [NSString stringWithFormat:@"sound=%@, loop=%s, repeatCount=%u, playing on channel %@", _sound, [self loop] ? "YES" : "NO", [self repeatCount], _channel];
	}
	else
	{
		return [NSString stringWithFormat:@"sound=%@, loop=%s, repeatCount=%u, not playing", _sound, [self loop] ? "YES" : "NO", [self repeatCount]];
	}
}


- (OOSound *) sound
{
	return _sound;
}


- (void) setSound:(OOSound *)sound
{
	if (_sound != sound)
	{
		[self stop];
		[_sound autorelease];
		_sound = [sound retain];
	}
}


- (BOOL) loop
{
	return _loop;
}


- (void) setLoop:(BOOL)loop
{
	_loop = !!loop;
}


- (uint8_t) repeatCount
{
	return _repeatCount ? _repeatCount : 1;
}


- (void) setRepeatCount:(uint8_t)count
{
	_repeatCount = count;
}


- (BOOL) isPlaying
{
	return _channel != nil;
}


- (void)play
{
	if ([self sound] == nil) return;
	
	OOSoundAcquireLock();
	
	if (_channel)  [self stop];
	
	_channel = [[OOSoundMixer sharedMixer] popChannel];
	if (nil != _channel)
	{
		_remainingCount = [self repeatCount];
		[_channel setDelegate:self];
		[_channel setPosition:_position];
		[_channel setGain:_gain];
		[_channel playSound:[self sound] looped:[self loop]];
		[self retain];
	}
	
	if (EXPECT_NOT(sPlayingSoundSources == nil))
	{
		sPlayingSoundSources = [[NSMutableSet alloc] init];
	}
	[sPlayingSoundSources addObject:self];
	
	OOSoundReleaseLock();
}


- (void) playOrRepeat
{
	if (![self isPlaying])  [self play];
	else ++_remainingCount;
}


- (void)stop
{
	OOSoundAcquireLock();
	
	if (nil != _channel)
	{
		[_channel setDelegate:[self class]];
		[_channel stop];
		_channel = nil;
		
		[sPlayingSoundSources removeObject:self];
		[self release];
	}
	
	OOSoundReleaseLock();
}


+ (void) stopAll
{
	/*	We're not allowed to mutate sPlayingSoundSources during iteration. The
		normal solution would be to copy the set, but since we know it will
		end up empty we may as well use the original set and let a new one be
		set up lazily.
	*/
	NSMutableSet *playing = sPlayingSoundSources;
	sPlayingSoundSources = nil;
	
	[playing makeObjectsPerformSelector:@selector(stop)];
	[playing release];
}


- (void) playSound:(OOSound *)sound
{
	[self playSound:sound repeatCount:_repeatCount];
}


- (void) playSound:(OOSound *)sound repeatCount:(uint8_t)count
{
	[self stop];
	[self setSound:sound];
	[self setRepeatCount:count];
	[self play];
}


- (void) playOrRepeatSound:(OOSound *)sound
{
	if (_sound != sound) [self playSound:sound];
	else [self playOrRepeat];
}


- (void) setPositional:(BOOL)inPositional
{
	if (inPositional)
	{
		_positional = YES;
	}
	else
	{
		/* OpenAL doesn't easily do non-positional sounds beyond the
		 * stereo/mono distinction, but setting the position to the
		 * zero vector is probably close enough */
		_positional = NO;
		[self setPosition:kZeroVector];
	}
}


- (BOOL) positional
{
	return _positional;
}


- (void) setPosition:(Vector)inPosition
{
	_position = inPosition;
	if (inPosition.x != 0.0 || inPosition.y != 0.0 || inPosition.z != 0.0)
	{
		_positional = YES;
	}
	if (_channel)
	{
		[_channel setPosition:_position]; 
	}
}


- (Vector) position
{
	return _position;
}


- (void) setGain:(float)gain
{
	_gain = gain;
	if (_channel)
	{
		[_channel setGain:_gain];
	}
}


- (float) gain
{
	return _gain;
}


/* Following not yet implemented */
- (void) setVelocity:(Vector)inVelocity
{
	
}


- (void) setOrientation:(Vector)inOrientation
{
	
}


- (void) setConeAngle:(float)inAngle
{
	
}


- (void) setGainInsideCone:(float)inInside outsideCone:(float)inOutside
{
	
}


- (void) positionRelativeTo:(OOSoundReferencePoint *)inPoint
{
	
}


// OOSoundChannelDelegate
- (void)channel:(OOSoundChannel *)channel didFinishPlayingSound:(OOSound *)sound
{
	assert(_channel == channel);
	
	OOSoundAcquireLock();
	
	if (--_remainingCount)
	{
		[_channel playSound:[self sound] looped:NO];
	}
	else
	{
		[_channel setDelegate:nil];
		[[OOSoundMixer sharedMixer] pushChannel:_channel];
		_channel = nil;
		[self release];
	}
	OOSoundReleaseLock();
}


+ (void)channel:(OOSoundChannel *)inChannel didFinishPlayingSound:(OOSound *)inSound
{
	// This delegate is used for a stopped source
	[[OOSoundMixer sharedMixer] pushChannel:inChannel];
}

@end
