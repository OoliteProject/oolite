/*

SDLSound.h

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

#import <Foundation/Foundation.h>
#include "SDL.h"
#include "SDL_mixer.h"

#define KEY_VOLUME_CONTROL @"volume_control"

#define MAX_CHANNELS 16


@interface OOSound : NSObject
{
	BOOL			isPlaying;
	Mix_Chunk		*sample;
	int				currentChannel;
	NSString		*name;
}

+ (void) channelDone:(int) channel;

// DJS: Volume controls compatible with OS X's fmod sound
+ (void) setUp;
+ (float) masterVolume;
+ (void) setMasterVolume: (float) fraction;

- (id) initWithContentsOfFile:(NSString*) filepath;
- (BOOL) pause;
- (BOOL) isPlaying;
- (BOOL) play;
- (BOOL) stop;
- (BOOL) resume;

- (NSString *) name;

+ (void)update;

@end
