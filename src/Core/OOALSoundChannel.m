/*

OOALSoundChannel.m

OOALSound - OpenAL sound implementation for Oolite.
Copyright (C) 2006-2013 Jens Ayton

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

#import "OOALSoundChannel.h"
#import "OOALSound.h"
#import "OOLogging.h"

@interface OOSoundChannel (Private)

- (void) hasStopped;

@end


@implementation OOSoundChannel

- (id) init
{
	if ((self = [super init]))
	{
		ALuint error;
		OOAL(alGenSources(1,&_source));
		if ((error = alGetError()) != AL_NO_ERROR)
		{
			OOLog(kOOLogSoundInitError,@"Could not create OpenAL source");
			[self release];
			self = nil;
		}
	}
	return self;
}


- (void) update
{
	// Check if we've reached the end of a sound.
	if (_sound != nil)
	{
		ALint check;
		OOAL(alGetSourcei(_source,AL_SOURCE_STATE,&check));
		if (check == AL_STOPPED)
		{
			[self hasStopped];
		}
	}
}


- (void) setDelegate:(id)delegate
{
	_delegate = delegate;
}


- (OOSoundChannel *) next
{
	return _next;
}


- (void) setNext:(OOSoundChannel *)next
{
	_next = next;
}


- (BOOL) playSound:(OOSound *)sound looped:(BOOL)loop
{
	if (sound == nil)  return NO;
	
	if (_sound != nil)  [self stop];

	// get sound data
	ALuint buffer = [sound soundBuffer];
	// bind sound data to buffer
	OOAL(alSourcei(_source, AL_BUFFER, buffer));
	ALuint error;
	if ((error = alGetError()) != AL_NO_ERROR)
	{
		return NO;
	}
	OOAL(alSourcePlay(_source));
	if ((error = alGetError()) != AL_NO_ERROR)
	{
		return NO;
	}
	_sound = [sound retain];
	return YES;
}


- (void) stop
{
	if (_sound != nil)
	{
		OOAL(alSourceStop(_source));
		[self hasStopped];
	}
}


- (void) hasStopped
{
	OOSound *sound = _sound;
	_sound = nil;
	
	if (nil != _delegate && [_delegate respondsToSelector:@selector(channel:didFinishPlayingSound:)])
	{
		[_delegate channel:self didFinishPlayingSound:sound];
	}
	[sound release];
}


- (OOSound *)sound
{
	return _sound;
}

@end
