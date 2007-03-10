/*

OOCASound.m

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

#define KEY_VOLUME_CONTROL			@"volume_control"
#define KEY_MAX_BUFFERED_SOUND		@"max_buffered_sound"


NSString * const kOOLogDeprecatedMethodOOCASound	= @"general.error.deprecatedMethod.oocasound";
NSString * const kOOLogSoundInitError				= @"sound.initialization.error";
static NSString * const kOOLogSoundLoadingSuccess	= @"sound.load.success";
static NSString * const kOOLogSoundLoadingError		= @"sound.load.error";


static float				sNominalVolume = 1.0f;
BOOL						gOOSoundSetUp = NO;
BOOL						gOOSoundBroken = NO;
NSLock						*gOOCASoundSyncLock = NULL;	// Used to ensure thread-safety of play and stop, specifically because stop may be called from the CoreAudio thread.

static OOSound				*sSingletonOOSound = NULL;
static size_t				sMaxBufferedSoundSize = 1 << 20;	// 1 MB


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
		if (nil == gOOCASoundSyncLock)
		{
			OOLog(kOOLogSoundInitError, @"Failed to set up sound (lock allocation failed). No sound will be played.");
			gOOSoundBroken = YES;
		}
		if (!gOOSoundBroken)
		{
			if (![OOCASoundChannel setUp])
			gOOSoundBroken = YES;
		}
		
		gOOSoundSetUp = YES;	// Must be before [OOCASoundMixer mixer] below.
		
		prefs = [NSUserDefaults standardUserDefaults];
		
		if ([prefs objectForKey:KEY_VOLUME_CONTROL])  sNominalVolume = [prefs floatForKey:KEY_VOLUME_CONTROL];
		else  sNominalVolume = 0.75;	// default setting at 75% system volume
		[[OOCASoundMixer mixer] setMasterVolume:sNominalVolume];
		
		if ([prefs objectForKey:KEY_MAX_BUFFERED_SOUND])
		{
			int maxSize = [prefs integerForKey:KEY_MAX_BUFFERED_SOUND];
			if (0 <= maxSize) sMaxBufferedSoundSize = maxSize;
		}
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
	
	if ([decoder sizeAsBuffer] <= sMaxBufferedSoundSize)
	{
		self = [[OOCABufferedSound alloc] initWithDecoder:decoder];
	}
	else
	{
		self = [[OOCAStreamingSound alloc] initWithDecoder:decoder];
	}
	
	if (nil != self)
	{
		OOLog(kOOLogSoundLoadingSuccess, @"Loaded sound %@", self);
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
