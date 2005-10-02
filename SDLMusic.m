//
// SDLMsuic.h: An encapsulation of SDL_mixer music functions for oolite.
//
// David Taylor, 2005-05-04
//

#include "SDLMusic.h"

/*
 * This is used by instances of OOMusic to check if they are currently playing
 * or not.
 *
 * Because SDL_mixer only plays one piece of music at a time (which is
 * reasonable), the SDL implementation of OOMusic works on the basis that
 * only one instance of it is "current" at any given time.
 *
 * If an instance is not the current instance, the only method that will
 * work is play. Calling play on an instance that is not the current
 * instance will make it the current instance, stopping any music that is
 * already playing.
 */
OOMusic* current;

/*
 * This function is called by SDL_mixer whenever a piece of music finishes
 * playing.
 *
 * This resets the pointer the currently playing OOMusic object to signify
 * that no music is playing.
 */
void musicFinished()
{
	current = 0;
}

@implementation OOMusic

/*
 * Initialise an OOMusic instance from the given file.
 *
 * The OOMusic instance is deallocated and nil is returned if the contents
 * of the file cannot be loaded by SDL_mixer.
 */
- (id) initWithContentsOfFile:(NSString*) filepath
{
	[super init];

	music = Mix_LoadMUS([filepath cString]);
	if (!music)
	{
		NSLog(@"Mix_LoadMUS(\"%@\"): %s\n", filepath, Mix_GetError());
		[super dealloc];
		return nil;
	}

	return self;
}

/*
 * Deallocate resources used by this instance of OOMusic.
 */
- (void) dealloc
{
	if (current == self)
		Mix_HaltMusic();

	if (music)
		Mix_FreeMusic(music);

	[super dealloc];
}

- (void) pause
{
    // Only pause the music if this instance is the one being played.
    if (current == self)
    { 
	    Mix_PauseMusic();
       paused=YES;
    }
}

- (BOOL) isPaused
{
   return paused;
}

/*
 * Returns YES is this instance of OOMusic is currently playing.
 */
- (BOOL) isPlaying
{
    // If the "current OOMusic instance" pointer points to self, then this
    // instance is playing.
	if (current == self)
		return YES;

	return NO;
}

/*
 * Play the music represented by this OOMusic instance. This will replace any
 * music currently playing.
 *
 * If this instance is already playing, there is no effect.
 *
 * Returns YES for success, or NO if there was a problem playing the music.
 */
- (BOOL) play
{
	int rc;
   paused=NO;

    // Self is already playing, so do nothing.
	if (current == self)
	    return YES;

    // Another instance is playing so stop it.
	if (current != 0)
	    [current stop];

    // There is a potential race condition here because the
    // SDL_mixer "music stopped" callback sets current to NULL, and this
    // method sets current to self.
    //
    // If the callback is executed from a thread created by SDL_mixer then
    // that might not happen before the thread executing this code has
    // already made self current.
    //
    // One way of avoiding this is to wait for current to be equal to
    // NULL. When that happens we know the callback has been called.
    while (current != 0)
        ;

	rc = Mix_PlayMusic(music, 1);
	if (rc < 0)
	{
		NSLog(@"Mix_PlayMusic error: %s", Mix_GetError());
		return NO;
	}

    // This is done on every call to play simply because there didn't seem to
    // be another way to do it without having either a class init method or
    // doing it outside this class altogether. Both of those solutions seems
    // messy and this should not have a big performance hit.
	Mix_HookMusicFinished(musicFinished);
	current = self;

	return YES;
}

/*
 * Stop playing this piece of music.
 *
 * Returns YES if this music was being played, or NO if this music was not
 * being played.
 */
- (void) stop
{
    // Only stop the music if this instance is the one being played.
	if (current == self)
	{
		Mix_HaltMusic();
		// Flag that there is no tune currently playing
		current = 0;
	}
}

- (void) resume
{
    // Only resume playing the music if this instance is the one being played.
    if (current == self)
    {
	    Mix_ResumeMusic();
       paused=NO;
    }
}

/*
 * Go back to the beginning of the music.
 */
- (void) goToBeginning
{
    // Only rewind the music if this instance is the one being played.
	if (current == self)
	    Mix_RewindMusic();
}

@end
