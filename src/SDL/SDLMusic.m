/*

SDLSound.h

SDLSound - SDL sound implementation for Oolite.
Copyright (C) 2005-2013 David Taylor

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

#include "SDLMusic.h"
#import "OOLogging.h"
#include "OOSDLSound.h"

#define kOOLogUnconvertedNSLog @"unclassified.SDLMusic"

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
	current = nil;
}


@interface OOMusic (Private)

- (BOOL) playWithCount:(int)count;

@end


@implementation OOMusic

/*
 * Initialise an OOMusic instance from the given file.
 *
 * The OOMusic instance is deallocated and nil is returned if the contents
 * of the file cannot be loaded by SDL_mixer.
 */
- (id) initWithContentsOfFile:(NSString*) filepath
{
	if( ![OOSound isSoundOK] ) return nil;

	[super init];

	music = Mix_LoadMUS([filepath UTF8String]);
	if (!music)
	{
		NSLog(@"Mix_LoadMUS(\"%@\"): %s\n", filepath, Mix_GetError());
		[super dealloc];
		return nil;
	}
	
	name = [[filepath lastPathComponent] copy];

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
	
	[name autorelease];

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

- (BOOL) playWithCount:(int)count
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

	rc = Mix_PlayMusic(music, count);
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
 * Play the music represented by this OOMusic instance. This will replace any
 * music currently playing.
 *
 * If this instance is already playing, there is no effect.
 *
 * Returns YES for success, or NO if there was a problem playing the music.
 */
- (void) playLooped:(BOOL)loop
{
	[self playWithCount:loop ? -1 : 1];
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


- (NSString *) name
{
	return name;
}

@end
