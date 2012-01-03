/*

SDLMusic.h

SDLSound - SDL sound implementation for Oolite.
Copyright (C) 2005-2012 David Taylor

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

#import <Foundation/Foundation.h>
#include <SDL.h>
#include <SDL_mixer.h>


@interface OOMusic : NSObject
{
    // The SDL_mixer music structure encapsulated by an instance of OOMusic.
	Mix_Music		*music;
	BOOL			paused;
	NSString		*name;
}

// Initialise the OOMusic instance from the contents of "filepath"
- (id) initWithContentsOfFile:(NSString*) filepath;

// Pause the music if this instance is currently playing
- (void) pause;
- (BOOL) isPaused;

// Returns YES if this instance is playing, otherwise NO.
- (BOOL) isPlaying;

// Start playing this instance of OOMusic, stopping any other instance
// currently playing.
- (void) playLooped:(BOOL)loop;

// Stop the music if this instance is currently playing.
- (void) stop;

// Resume the music if this instance was paused. Has no effect if a different
// instance was paused.
- (void) resume;

// Rewind the music if this instance is the current instance.
- (void) goToBeginning;

- (NSString *) name;

@end
