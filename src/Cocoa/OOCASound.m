//	
//	OOCASound.m
//	CoreAudio sound implementation for Oolite
//	
/*

Copyright © 2005-2006 Jens Ayton
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

/*	OOSound is a class cluster. A single OOSound object exists, which represents a sound that has
	been alloced but not inited. The designated initialiser returns a concrete subclass, either
	OOCABufferedSound or OOCAStreamingSound, depending on the size of the sound data.
*/

#import "OOCASoundInternal.h"
#import "OOCASoundDecoder.h"
#import <CoreAudio/CoreAudio.h>
#import <AudioToolbox/AudioToolbox.h>

#define KEY_VOLUME_CONTROL @"volume_control"


enum
{
	kMaxDecodeSize			= 1 << 19		// 512 kB
};


static float				sNominalVolume = 1.0f;
BOOL						gOOSoundSetUp = NO;
BOOL						gOOSoundBroken = NO;
NSLock						*gOOCASoundSyncLock = NULL;	// Used to ensure thread-safety of play and stop, specifically because stop may be called from the CoreAudio thread.

static OOSound				*sSingletonOOSound = NULL;


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
	if (!gOOSoundSetUp)
	{
		gOOCASoundSyncLock = [[NSRecursiveLock alloc] init];
		if (nil == gOOCASoundSyncLock)
		{
			NSLog(@"Failed to set up sound (lock allocation failed). No sound will be played.");
			gOOSoundBroken = YES;
		}
		if (!gOOSoundBroken)
		{
			if (![OOCASoundChannel setUp])
			gOOSoundBroken = YES;
		}
		
		gOOSoundSetUp = YES;
		
		if ([[NSUserDefaults standardUserDefaults] objectForKey:KEY_VOLUME_CONTROL])
			sNominalVolume = [[NSUserDefaults standardUserDefaults] floatForKey:KEY_VOLUME_CONTROL];
		else
			sNominalVolume = 0.75;	// default setting at 75% system volume
		[[OOCASoundMixer mixer] setMasterVolume:sNominalVolume];
	}
}


+ (void) tearDown
{
	if (gOOSoundSetUp)
	{
		[gOOCASoundSyncLock release];
		gOOCASoundSyncLock = nil;
		[OOCASoundMixer destroy];
	}
	[OOCASoundChannel tearDown];
	gOOSoundSetUp = NO;
	gOOSoundBroken = NO;
	
	[sSingletonOOSound release];
}


+ (void) update
{
	[[OOCASoundMixer mixer] update];
}


+ (void) setMasterVolume:(float)fraction
{
	if (fraction != sNominalVolume)
	{
		[[OOCASoundMixer mixer] setMasterVolume:fraction];
		
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
	
	if ([decoder sizeAsBuffer] <= kMaxDecodeSize)
	{
		self = [[OOCABufferedSound alloc] initWithDecoder:decoder];
	}
	else
	{
		self = [[OOCAStreamingSound alloc] initWithDecoder:decoder];
	}
	
	if (nil != self)
	{
		NSLog(@"Loaded sound %@", self);
	}
	else
	{
		NSLog(@"Failed to load sound \"%@\"", inPath);
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
	NSLog(@"%s shouldn't be called - subclass responsibility.", __PRETTY_FUNCTION__);
	return unimpErr;
}


- (void)incrementPlayingCount
{
	++_playingCount;
}


- (void)decrementPlayingCount
{
	assert(0 != _playingCount);
	--_playingCount;
}


- (BOOL) isPlaying
{
	return 0 != _playingCount;
}


- (uint32_t)playingCount
{
	return _playingCount;
}


- (BOOL) isPaused
{
	return NO;
}


- (BOOL) play
{
	return NO;
}


- (BOOL)stop
{
	return YES;
}


- (BOOL)pause
{
	return NO;
}


- (BOOL)resume
{
	return NO;
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
