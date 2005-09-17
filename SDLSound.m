//
// SDLSound.h: Audio interface for oolite to the SDL library.
// Implements a similar interface to NSSound.
//
// David Taylor, 2005-05-04
//

#import "SDLSound.h"
#include "oolite-linux.h"
static int mixChan=0;

@implementation OOSound

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
	if (sample)
	{
      mixChan++;
      if(mixChan >= MAX_CHANNELS)
      {
         mixChan=0;
      }
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
