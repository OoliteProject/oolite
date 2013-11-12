/*

OOOpenALController.m


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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

#import "OOOpenALController.h"
#import "OOLogging.h"
#import "OOALSoundMixer.h"

static id sSingleton = nil;

@implementation OOOpenALController

+ (OOOpenALController *) sharedController
{
	if (sSingleton == nil)
	{
		sSingleton = [[self alloc] init];
	}
	
	return sSingleton;
}


- (id) init
{
	self = [super init];
	if (self != nil)
	{
		ALuint error;
		device = alcOpenDevice(NULL); // default device
		if (!device)
		{
			OOLog(kOOLogSoundInitError,@"Failed to open default sound device");
			return nil;
		}
		context = alcCreateContext(device,NULL); // default context
		if (!alcMakeContextCurrent(context))
		{
			OOLog(kOOLogSoundInitError,@"Failed to create default sound context");
			return nil;
		}
		if ((error = alGetError()) != AL_NO_ERROR)
		{
			OOLog(kOOLogSoundInitError,@"Error %d creating sound context",error);
		}
		OOAL(alDistanceModel(AL_NONE)); 
	}
	return self;
}


- (void) setMasterVolume:(ALfloat) fraction
{
	OOAL(alListenerf(AL_GAIN,fraction));
}

- (ALfloat) masterVolume
{
	ALfloat fraction = 0.0;
	OOAL(alGetListenerf(AL_GAIN,&fraction));
	return fraction;
}

// only to be called at app shutdown
// is there a better way to handle this?
- (void) shutdown
{
	[[OOSoundMixer sharedMixer] shutdown];
	OOAL(alcMakeContextCurrent(NULL));
	OOAL(alcDestroyContext(context));
	OOAL(alcCloseDevice(device));
}

@end
