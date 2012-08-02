/*

OOCASound.m


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


/*	OOSound is a class cluster. A single OOSound object exists, which
	represents a sound that has been alloced but not inited. The designated
	initialiser returns a concrete subclass, either OOCABufferedSound or
	OOCAStreamingSound, depending on the size of the sound data.
*/

#import "OOCASoundInternal.h"
#import "OOCASoundDecoder.h"
#import <CoreAudio/CoreAudio.h>
#import <AudioToolbox/AudioToolbox.h>
#import "NSThreadOOExtensions.h"
#import "OOCollectionExtractors.h"


#define KEY_VOLUME_CONTROL			@"volume_control"
#define KEY_MAX_BUFFERED_SOUND		@"max_buffered_sound"


NSString * const kOOLogDeprecatedMethodOOCASound	= @"general.error.deprecatedMethod.oocasound";
NSString * const kOOLogSoundInitError				= @"sound.initialization.error";
static NSString * const kOOLogSoundLoadingSuccess	= @"sound.load.success";
static NSString * const kOOLogSoundLoadingError		= @"sound.load.error";


static float				sNominalVolume = 1.0f;
BOOL						gOOSoundSetUp = NO;
BOOL						gOOSoundBroken = NO;
NSRecursiveLock				*gOOCASoundSyncLock = nil;	// Used to ensure thread-safety of play and stop, specifically because stop may be called from the CoreAudio thread.

static OOSound				*sSingletonOOSound = nil;
static size_t				sMaxBufferedSoundSize = 1 << 20;	// 1 MB


#ifndef NDEBUG
static struct
{
	BOOL hasData;
	float badVal;
	OOSound *badSound;
} sSoundError;

#import <Foundation/NSDebug.h>
#endif


@implementation OOSound

#pragma mark NSObject

+ (id)allocWithZone:(NSZone *)inZone
{
	if (self != [OOSound class]) return [super allocWithZone:inZone];
	
	if (nil == sSingletonOOSound)
	{
		sSingletonOOSound = [super allocWithZone:inZone];
	}
	
	return sSingletonOOSound;
}


- (id)init
{
	if ([self isMemberOfClass:[OOSound class]])
	{
		[self release];
		return nil;
	}
	else
	{
		return [super init];
	}
}


- (void)dealloc
{
	if (self == sSingletonOOSound) sSingletonOOSound = nil;
	
	[super dealloc];
}


- (NSString *)description
{
	if ([self isMemberOfClass:[OOSound class]])
	{
		return [NSString stringWithFormat:@"<%@ %p>(singleton placeholder)", [self className], self];
	}
	else
	{
		return [NSString stringWithFormat:@"<%@ %p>{\"%@\"}", [self className], self, [self name]];
	}
}


#pragma mark OOSound

+ (void) setUp
{
	NSUserDefaults				*prefs = nil;
	
	if (!gOOSoundSetUp)
	{
		gOOCASoundSyncLock = [[NSRecursiveLock alloc] init];
		[gOOCASoundSyncLock setName:@"OOCASound synchronization lock"];
		if (nil == gOOCASoundSyncLock)
		{
			OOLog(kOOLogSoundInitError, @"Failed to set up sound (lock allocation failed). No sound will be played.");
			gOOSoundBroken = YES;
		}
		if (!gOOSoundBroken)
		{
			if (![OOSoundChannel setUp])  gOOSoundBroken = YES;
		}
		
		gOOSoundSetUp = YES;	// Must be before [OOSoundMixer sharedMixer] below.
		
		prefs = [NSUserDefaults standardUserDefaults];
		
		if ([prefs objectForKey:KEY_VOLUME_CONTROL])  sNominalVolume = [prefs floatForKey:KEY_VOLUME_CONTROL];
		else  sNominalVolume = 0.75;	// default setting at 75% system volume
		[[OOSoundMixer sharedMixer] setMasterVolume:sNominalVolume];
		
		int maxSize = [prefs oo_intForKey:KEY_MAX_BUFFERED_SOUND defaultValue:sMaxBufferedSoundSize];
		if (0 <= maxSize) sMaxBufferedSoundSize = maxSize;
	}
}


+ (void) update
{
	[[OOSoundMixer sharedMixer] update];
	
#ifndef NDEBUG
	if (sSoundError.hasData)
	{
		float badVal = sSoundError.badVal;
		OOSound *badSound = sSoundError.badSound;
		sSoundError.hasData = NO;
		
		NSString *desc = nil;
		if (NSIsFreedObject(badSound))  desc = [NSString stringWithFormat:@"released sound %p", badSound];
		else  desc = [badSound description];
		
		OOLog(@"sound.renderingError", @"Sound rendering error detected for sound %@ (bad value: %f)", desc, badVal);
	}
#endif
}


+ (void) setMasterVolume:(float)fraction
{
	if (fraction != sNominalVolume)
	{
		[[OOSoundMixer sharedMixer] setMasterVolume:fraction];
		
		sNominalVolume = fraction;
		[[NSUserDefaults standardUserDefaults] setFloat:fraction forKey:KEY_VOLUME_CONTROL];
	}
}


+ (float) masterVolume
{
	return sNominalVolume;
}


/*	Designated initialiser for OOSound.
	Note: OOSound is a class cluster. This will always return a subclass of OOSound.
*/
- (id) initWithContentsOfFile:(NSString *)inPath
{
	OOCASoundDecoder		*decoder;
	
	if (!gOOSoundSetUp) [OOSound setUp];
	
	decoder = [[OOCASoundDecoder alloc] initWithPath:inPath];
	if (nil == decoder) return nil;
	
	if ([decoder sizeAsBuffer] <= sMaxBufferedSoundSize)
	{
		self = [[OOCABufferedSound alloc] initWithDecoder:decoder];
	}
	else
	{
		self = [[OOCAStreamingSound alloc] initWithDecoder:decoder];
	}
	[decoder release];
	
	if (nil != self)
	{
		#ifndef NDEBUG
			OOLog(kOOLogSoundLoadingSuccess, @"Loaded sound %@", self);
		#endif
	}
	else
	{
		OOLog(kOOLogSoundLoadingError, @"Failed to load sound \"%@\"", inPath);
	}
	
	return self;
}


- (id)initWithDecoder:(OOCASoundDecoder *)inDecoder
{
	[self release];
	return nil;
}


- (OSStatus)renderWithFlags:(AudioUnitRenderActionFlags *)ioFlags frames:(UInt32)inNumFrames context:(OOCASoundRenderContext *)ioContext data:(AudioBufferList *)ioData
{
	OOLog(@"general.error.subclassResponsibility.OOCASound-renderWithFlags", @"%s shouldn't be called - subclass responsibility.", __PRETTY_FUNCTION__);
	return unimpErr;
}


- (void)incrementPlayingCount
{
	++_playingCount;
}


- (void)decrementPlayingCount
{
	//assert(0 != _playingCount);
	if (EXPECT(_playingCount != 0))  --_playingCount;
	else  OOLog(@"sound.playUnderflow", @"Playing count for %@ dropped below 0!", self);
}


- (BOOL) isPlaying
{
	return 0 != _playingCount;
}


- (uint32_t)playingCount
{
	return _playingCount;
}


- (BOOL)prepareToPlayWithContext:(OOCASoundRenderContext *)outContext looped:(BOOL)inLoop
{
	return YES;
}


- (void)finishStoppingWithContext:(OOCASoundRenderContext)inContext
{
	
}


- (BOOL)doPlay
{
	return YES;
}


- (BOOL)doStop
{
	return YES;
}


- (NSString *)name
{
	return nil;
}


- (BOOL)getAudioStreamBasicDescription:(AudioStreamBasicDescription *)outFormat
{
	return NO;
}

@end


#ifndef NDEBUG
static BOOL VerifyOneBuffer(AudioBuffer *buffer, OOUInteger numFrames, float *badVal);


void OOCASoundVerifyBuffers(AudioBufferList *buffers, OOUInteger numFrames, OOSound *sound)
{
	BOOL allOK = YES;
	UInt32 i;
	float badVal = 0.0;
	
	for (i = 0; i < buffers->mNumberBuffers; i++)
	{
		if (!VerifyOneBuffer(&buffers->mBuffers[i], numFrames, &badVal))
		{
			allOK = NO;
		}
	}
	
	if (!allOK && !sSoundError.hasData)
	{
		sSoundError.badSound = sound;
		sSoundError.badVal = badVal;
		sSoundError.hasData = YES;	// Must be last!
	}
}


static BOOL VerifyOneBuffer(AudioBuffer *buffer, OOUInteger numFrames, float *badVal)
{
	if (buffer == NULL || buffer->mData == NULL || badVal == NULL)  return NO;
	
	*badVal = 0.0;
	
	if (numFrames * sizeof(float) > buffer->mDataByteSize)
	{
		memset(buffer->mData, 0, buffer->mDataByteSize);
		return NO;
	}
	
	// Assume data is float.
	float *floatBuffer = (float *)buffer->mData;
	OOUInteger i;
	BOOL OK = YES;
	BOOL worstAbnormal = NO;
	for (i = 0; i < numFrames; i++)
	{
		float val = floatBuffer[i];
		BOOL abnormal = isnan(val) || !isfinite(val);
		
		if (abnormal || (fabs(val) > kOOAudioSlop))
		{
			if (abnormal || (!abnormal && !worstAbnormal && fabs(*badVal < fabs(val))))
			{
				worstAbnormal = abnormal;
				*badVal = val;
			}
			
			OK = NO;
		}
	}
	
	if (OK == NO)
	{
		memset(buffer->mData, 0, buffer->mDataByteSize);
	}
	
	return OK;
}

#endif
