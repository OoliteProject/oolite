/*

OOALSoundChannel.h

A channel for audio playback.

This class is an implementation detail. Do not use it directly; use an
OOSoundSource to play an OOSound.

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

#import <Foundation/Foundation.h>
#import "OOOpenALController.h"
#import "OOMaths.h"

@class OOSound;


@interface OOSoundChannel: NSObject
{
	OOSoundChannel				*_next;
	id							_delegate;
	OOSound						*_sound;
	ALuint						_buffer;
	ALuint						_lastBuffer;
	BOOL						_bigSound;
	ALuint						_source;
	BOOL						_playing;
	BOOL						_loop;
}

- (void) update;

- (void) setDelegate:(id)delegate;

// Unretained pointer used to maintain simple stack
- (OOSoundChannel *) next;
- (void) setNext:(OOSoundChannel *)next;

// set sound position relative to listener
- (void) setPosition:(Vector) vector;
- (void) setGain:(float) gain;
- (BOOL) playSound:(OOSound *)sound looped:(BOOL)loop;
- (void)stop;

- (OOSound *)sound;

@end


@interface NSObject(OOSoundChannelDelegate)

- (void)channel:(OOSoundChannel *)inChannel didFinishPlayingSound:(OOSound *)inSound;

@end
