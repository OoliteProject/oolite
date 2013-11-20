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
#import "OOMaths.h"

@interface OOSoundChannel (Private)

- (BOOL) enqueueBuffer:(OOSound *)sound;
- (void) hasStopped;
- (void) getNextSoundBuffer;

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
			OOLog(kOOLogSoundInitError, @"Could not create OpenAL source");
			[self release];
			self = nil;
		}
		// sources are all relative to listener, defaulting to zero vector
		OOAL(alSourcei(_source, AL_SOURCE_RELATIVE, AL_TRUE));
		OOAL(alSource3f(_source, AL_POSITION, 0.0f, 0.0f, 0.0f));
	}
	return self;
}


- (void) dealloc
{
	[self hasStopped]; // make sure buffers are dequeued and deleted
	OOAL(alDeleteSources(1, &_source));
	[super dealloc];
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
		else if ([_sound soundIncomplete]) // streaming and not finished loading
		{
			OOLog(@"sound.buffer", @"Incomplete, trying next for %@", [_sound name]);
			[self getNextSoundBuffer];
		}
		else if (_loop)
		{
			OOLog(@"sound.buffer", @"Looping, trying restart for %@", [_sound name]);
			// sound is complete, but needs to be looped, so start it again
			[_sound rewind];
			[self getNextSoundBuffer];
		}
	}
}


- (void) getNextSoundBuffer
{
	if (!_bigSound)
	{
		// we've only loaded one buffer so far
		_bigSound = YES;
		_lastBuffer = _buffer;
		[self enqueueBuffer:_sound];
	}
	else
	{
		// _lastBuffer has something in it, so only queue up
		// another one if we've finished with that
		ALint processed = 0;
		OOAL(alGetSourcei(_source, AL_BUFFERS_PROCESSED, &processed));
		if (processed > 0) // slot free
		{
			// dequeue and delete lastBuffer
			ALuint buffer;
			OOAL(alSourceUnqueueBuffers(_source, 1, &buffer));
			assert(buffer == _lastBuffer);
			OOAL(alDeleteBuffers(1,&_lastBuffer));
			// shuffle along, and grab the next bit
			_lastBuffer = _buffer;
			[self enqueueBuffer:_sound];
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


- (void) setPosition:(Vector) vector
{
	OOAL(alSource3f(_source, AL_POSITION, vector.x, vector.y, vector.z));
}


- (void) setGain:(float) gain
{
	OOAL(alSourcef(_source, AL_GAIN, gain));
}


- (BOOL) playSound:(OOSound *)sound looped:(BOOL)loop
{
	if (sound == nil)  return NO;
	
	if (_sound != nil)  [self stop];

	_loop = loop;
	_bigSound = NO;
	[sound rewind];
	if ([self enqueueBuffer:sound])
	{
		_sound = [sound retain];
		return YES;
	}
	else
	{
		return NO;
	}
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
	OOAL(alDeleteBuffers(1,&_buffer));
	if (_bigSound)
	{
		// then we have two buffers to cleanup
		OOAL(alDeleteBuffers(1,&_lastBuffer));
	}
	_bigSound = NO;
	ALint queued;
	OOAL(alGetSourcei(_source, AL_BUFFERS_QUEUED, &queued));
    
	while (queued--)
	{
		ALuint buffer;
		OOAL(alSourceUnqueueBuffers(_source, 1, &buffer));
	}

	OOSound *sound = _sound;
	_sound = nil;
	
	if (nil != _delegate && [_delegate respondsToSelector:@selector(channel:didFinishPlayingSound:)])
	{
		[_delegate channel:self didFinishPlayingSound:sound];
	}
	[sound release];
}


- (BOOL) enqueueBuffer:(OOSound *)sound
{
	// get sound data
	_buffer = [sound soundBuffer];
	// bind sound data to buffer
	OOAL(alSourceQueueBuffers(_source, 1, &_buffer));
	ALuint error;
	if ((error = alGetError()) != AL_NO_ERROR)
	{
		OOLog(@"ov.debug",@"Error %d queueing buffers",error);
		return NO;
	}
	ALint playing = 0;
	OOAL(alGetSourcei(_source,AL_SOURCE_STATE,&playing));
	if (playing != AL_PLAYING)
	{
		OOAL(alSourcePlay(_source));
		if ((error = alGetError()) != AL_NO_ERROR)
		{
			OOLog(@"ov.debug",@"Error %d playing source",error);
			return NO;
		}
	}
	return YES;
}



- (OOSound *)sound
{
	return _sound;
}

@end
