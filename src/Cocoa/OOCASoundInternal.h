/*

OOCASoundInternal.h

Declarations used within OOCASound. This file should not be used by client
code.


OOCASound - Core Audio sound implementation for Oolite.
Copyright (C) 2005-2012 Jens Ayton

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
#import "OOCASoundChannel.h"
#import "OOCABufferedSound.h"
#import "OOCAStreamingSound.h"
#import <CoreAudio/CoreAudio.h>
#import <AudioToolbox/AudioToolbox.h>
#import <OSAtomic.h>
#import "OOErrorDescription.h"
#import "OOLogging.h"
#import "OOMaths.h"


@interface OOSound (Internal)

- (OSStatus)renderWithFlags:(AudioUnitRenderActionFlags *)ioFlags frames:(UInt32)inNumFrames context:(OOCASoundRenderContext *)ioContext data:(AudioBufferList *)ioData;

// Called by -play and -stop only if in appropriate state
- (BOOL)prepareToPlayWithContext:(OOCASoundRenderContext *)outContext looped:(BOOL)inLoop;
- (void)finishStoppingWithContext:(OOCASoundRenderContext)inContext;

- (BOOL)getAudioStreamBasicDescription:(AudioStreamBasicDescription *)outFormat;

- (void)incrementPlayingCount;
- (void)decrementPlayingCount;

- (BOOL) isPlaying;

@end


@interface OOSoundMixer (Internal)

- (BOOL)connectChannel:(OOSoundChannel *)inChannel;
- (OSStatus)disconnectChannel:(OOSoundChannel *)inChannel;

@end


extern BOOL				gOOSoundSetUp, gOOSoundBroken;

extern NSString * const kOOLogDeprecatedMethodOOCASound;
extern NSString * const kOOLogSoundInitError;

#define kOOLogUnconvertedNSLog @"unclassified.OOCASound"


#ifndef NDEBUG
void OOCASoundVerifyBuffers(AudioBufferList *buffers, NSUInteger numFrames, OOSound *sound);
#else
#define OOCASoundVerifyBuffers(buffers, numFrames, sound)  do {} while (0)
#endif



/*	The Vorbis floating-point decoder gives us out-of-range values for certain
	built-in sounds. To compensate, we reduce overall volume slightly to avoid
	clipping. (The worst observed value is -1.341681f in bigbang.ogg.)
*/
#define kOOAudioSlop 1.341682f
