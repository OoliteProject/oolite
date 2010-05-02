/*

OOCASoundInternal.h

Declarations used within OOCASound. This file should not be used by client
code.


OOCASound - Core Audio sound implementation for Oolite.
Copyright (C) 2005-2008 Jens Ayton

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
#import "OOErrorDescription.h"
#import "OOLogging.h"


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


#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_4
#import </usr/include/libkern/OSAtomic.h>

static inline void OOSoundAtomicAdd(int32_t delta, int32_t *value)
{
	OSAtomicAdd32(delta, value);
}
#else
static inline void OOSoundAtomicAdd(int32_t delta, int32_t *value)
{
	OTAtomicAdd32(delta, (SInt32 *)value);
}
#endif


// Wrappers for AU APIs changed in Leopard SDK
#if OOLITE_LEOPARD

static inline OSStatus OOAUGraphAddNode(AUGraph inGraph, const ComponentDescription *inDescription, AUNode *outNode)
{
	return AUGraphAddNode(inGraph, inDescription, outNode);
}


static inline OSStatus OOAUGraphNodeInfo(AUGraph inGraph, AUNode inNode, ComponentDescription *outDescription, AudioUnit *outAudioUnit)	
{
	return AUGraphNodeInfo(inGraph, inNode, outDescription, outAudioUnit);
}

#else

static inline OSStatus OOAUGraphAddNode(AUGraph inGraph, const ComponentDescription *inDescription, AUNode *outNode)
{
	return AUGraphNewNode(inGraph, inDescription, 0, NULL, outNode);
}


static inline OSStatus OOAUGraphNodeInfo(AUGraph inGraph, AUNode inNode, ComponentDescription *outDescription, AudioUnit *outAudioUnit)	
{
	return AUGraphGetNodeInfo(inGraph, inNode, outDescription, NULL, NULL, outAudioUnit);
}

#endif


#ifndef NDEBUG
void OOCASoundVerifyBuffers(AudioBufferList *buffers, OOUInteger numFrames, OOSound *sound);
#else
#define OOCASoundVerifyBuffers(buffers, numFrames, sound)  do {} while (0)
#endif



/*	The Vorbis floating-point decoder gives us out-of-range values for certain
	built-in sounds. To compensate, we reduce overall volume slightly to avoid
	clipping. (The worst observed value is -1.341681f in bigbang.ogg.)
*/
#define kOOAudioSlop 1.341682f
