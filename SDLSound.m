//
// SDLSound.h: Audio interface for oolite to the SDL library.
// Implements a similar interface to NSSound.
//
// David Taylor, 2005-05-04
//

#import "SDLSound.h"
#include "oolite-linux.h"
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

- (id) initWithContentsOfFile:(NSString*)filepath byReference:(BOOL)ref
{
	[super init];
   if(!isSetUp) [OOSound setUp];

	//NSLog(@"loading sample: %s", [filepath cString]);
	sample = Mix_LoadWAV([filepath cString]);
	if (!sample) {
		NSLog(@"Mix_LoadWAV: %s\n", Mix_GetError());
		sample = 0;
	}
	
	return self;
}

- (void) dealloc
{
	if (sample)
		Mix_FreeChunk(sample);

	[super dealloc];
}

+ (void) channelDone:(int) channel
{
	NSLog(@"channel done: %d", channel);
}

@end
