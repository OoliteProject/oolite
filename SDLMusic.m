//
// SDLMsuic.h: An encapsulation of SDL_mixer music functions for oolite.
//
// David Taylor, 2005-05-04
//

#include "SDLMusic.h"

OOMusic* current;

void musicFinished()
{
	current = 0;
}

@implementation OOMusic

- (id) initWithContentsOfFile:(NSString*) filepath
{
	[super init];

	filename = [NSString stringWithString: filepath];

	music = Mix_LoadMUS([filepath cString]);
	if (!music)
	{
		NSLog(@"Mix_LoadMUS(\"%@\"): %s\n", filepath, Mix_GetError());
		[super dealloc];
		return nil;
	}

	return self;
}

- (void) dealloc
{
	if (current == self)
		Mix_HaltMusic();

	if (music)
		Mix_FreeMusic(music);

	[super dealloc];
}

- (BOOL) pause
{
	return YES;
}

- (BOOL) isPlaying
{
	if (current == self)
		return YES;

	return NO;
}

- (BOOL) play
{
	int rc;
	rc = Mix_PlayMusic(music, 1);
	if (rc < 0)
	{
		NSLog(@"Mix_PlayMusic error: %s", Mix_GetError());
		return NO;
	}

	Mix_HookMusicFinished(musicFinished);
	current = self;

	return YES;
}

- (BOOL) stop
{
	if (current == self)
	{
		Mix_HaltMusic();
		current = 0;
		return YES;
	}

	return NO;
}

- (BOOL) resume
{
	return YES;
}

- (void) goToBeginning
{
	Mix_RewindMusic();
}

@end
