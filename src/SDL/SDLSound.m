/*

SDLSound.m

SDLSound - SDL sound implementation for Oolite.
Copyright (C) 2005 David Taylor

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

#import "SDLSound.h"
#import "OOBasicSoundSource.h"

#define kOOLogUnconvertedNSLog @"unclassified.SDLSound"


static int mixChan=0;
static float masterVol=1.0;
static BOOL isSetUp=NO;

@implementation OOSound

// DJS: Volume controls compatible with OS X's fmod controls
// The GUI sets and expects a float volume with the range
// 0.0 to 1.0. SDL_Mixer expects an int value of 0 to MIX_MAX_VOLUME (128).
+ (void) setUp
{
   NSUserDefaults *dfl=[NSUserDefaults standardUserDefaults];
   if([dfl objectForKey: KEY_VOLUME_CONTROL])
   {
      [OOSound setMasterVolume: [dfl floatForKey: KEY_VOLUME_CONTROL]];
   }
   else
   {
      [OOSound setMasterVolume: 1.0];
   }
   isSetUp=YES;
}

+ (float) masterVolume
{
   if(!isSetUp) [OOSound setUp];
   return masterVol;  
}

+ (void) setMasterVolume: (float)vol
{
   masterVol=vol;
   if(masterVol < 0.0)
      masterVol=0;
   if(masterVol > 1.0)
      masterVol=1.0;
   int mixVol=(float)MIX_MAX_VOLUME * masterVol;

   // -1 = all channels
   Mix_Volume(-1, mixVol);
   Mix_VolumeMusic(mixVol);

   // save it
   [[NSUserDefaults standardUserDefaults]
         setFloat: masterVol forKey: KEY_VOLUME_CONTROL];
}

- (BOOL) pause
{
	if (sample && currentChannel > -1)
		Mix_Pause(currentChannel);

	return YES;
}

- (BOOL) isPlaying
{
	int i;
	if (sample && currentChannel > -1)
		i = Mix_Playing(currentChannel);

	if (i == 1)
		return YES;

	return NO;
}

- (BOOL) play
{
   if(!isSetUp) [OOSound setUp];
   int chansScanned=1;
	if (sample)
	{
      [self stop];

      // avoid treading on channels that are already playing
      do
      {
         mixChan++;
         if(mixChan >= MAX_CHANNELS)
         {
            mixChan=0;
         }
         if(chansScanned++ > MAX_CHANNELS)
         {
            NSLog(@"Out of channels!");
            break;
         }
      } while(Mix_Playing(mixChan));
		currentChannel = Mix_PlayChannel(mixChan, sample, 0);
		if (currentChannel < 0)
			NSLog(@"Mix_PlayChannel: %s\n", Mix_GetError());
			return NO;
	}

	return YES;
}

- (BOOL) stop
{
	if (sample && currentChannel > -1)
	{
		Mix_HaltChannel(currentChannel);
		currentChannel = -1;
	}

	return YES;
}

- (BOOL) resume
{
	if (sample && currentChannel > -1)
		Mix_Resume(currentChannel);

	return YES;
}

- (id) initWithContentsOfFile:(NSString*)filepath
{
	[super init];
   if(!isSetUp) [OOSound setUp];

	sample = Mix_LoadWAV([filepath cString]);
	if (!sample) {
		NSLog(@"Mix_LoadWAV: %s\n", Mix_GetError());
		sample = 0;
	}
	
	name = [[filepath lastPathComponent] copy];
	
	return self;
}

- (void) dealloc
{
	if (sample)
		Mix_FreeChunk(sample);
	[name autorelease];

	[super dealloc];
}

+ (void) channelDone:(int) channel
{
	NSLog(@"channel done: %d", channel);
}


+ (void)update
{
	[OOSoundSource update];
}


- (NSString *) name
{
	return name;
}

@end
