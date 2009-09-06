/*

OOSDLSound.m

OOSDLSound - SDL_mixer sound implementation for Oolite.
Copyright (C) 2006-2008 Jens Ayton


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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2006-2008 Jens Ayton

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

#import "OOSDLSoundInternal.h"
#import "OOLogging.h"
#import "OOCollectionExtractors.h"
#import "OOMaths.h"


#define KEY_VOLUME_CONTROL @"volume_control"


static BOOL	sIsSetUp = NO;
static BOOL sIsSoundOK = NO;
static int	sEffectiveMasterVolume = MIX_MAX_VOLUME;


@implementation OOSound

+ (BOOL) setUp
{
	if (!sIsSetUp)
	{
		sIsSetUp = YES;
		
		if (Mix_OpenAudio(44100, AUDIO_S16LSB, 2, 2048) < 0)
		{
			OOLog(@"sdl.init.audio.failed", @"Mix_OpenAudio: %s\n", Mix_GetError());
			return NO;
		}
		
		Mix_AllocateChannels(kMixerGeneralChannels);
		sIsSoundOK = YES;
		
		float volume = [[NSUserDefaults standardUserDefaults] oo_floatForKey:KEY_VOLUME_CONTROL defaultValue:1.0];
		[self setMasterVolume:volume];
		
		[OOSoundMixer sharedMixer];
	}
	
	return sIsSoundOK;
}


+ (void) setMasterVolume:(float) fraction
{
	if (!sIsSetUp && ![self setUp])
		return;
	
	fraction = OOClamp_0_1_f(fraction);
	int volume = (float)MIX_MAX_VOLUME * fraction;
	
	if (volume != sEffectiveMasterVolume)
	{
		// -1 = all channels
		Mix_Volume(-1, volume);
		Mix_VolumeMusic(volume);
		
		sEffectiveMasterVolume = volume;
		[[NSUserDefaults standardUserDefaults] setFloat:[self masterVolume] forKey:KEY_VOLUME_CONTROL];
	}
}


+ (float) masterVolume
{
	if (!sIsSetUp && ![self setUp] )
		return 0;
	
	return (float)sEffectiveMasterVolume / (float)MIX_MAX_VOLUME;
}


- (id) init
{
	if (!sIsSetUp)  [OOSound setUp];
	return [super init];
}


- (id) initWithContentsOfFile:(NSString *)path
{
	[self release];
	if (!sIsSetUp && ![OOSound setUp])  return nil;
	
	return [[OOSDLConcreteSound alloc] initWithContentsOfFile:path];
}


- (NSString *)name
{
	OOLogGenericSubclassResponsibility();
	return @"";
}


+ (void) update
{
	OOSoundMixer * mixer = [OOSoundMixer sharedMixer];
	if( sIsSoundOK && mixer)
		[mixer update];
}

+ (BOOL) isSoundOK
{
  return sIsSoundOK;
}

@end
