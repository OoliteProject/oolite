/*

OOMusicController.h

Singleton controller for music playback.


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

#import "OOCocoa.h"

@class OOMusic;


#define OOLITE_ITUNES_SUPPORT OOLITE_MAC_OS_X


typedef enum
{
	kOOMusicOff,
	kOOMusicOn,
	kOOMusicITunes,
	
#if OOLITE_ITUNES_SUPPORT
	kOOMusicModeMax = kOOMusicITunes
#else
	kOOMusicModeMax = kOOMusicOn
#endif
} OOMusicMode;


@interface OOMusicController: NSObject
{
@private
	OOMusicMode				_mode;
	NSString				*_missionMusic;
	OOMusic					*_current;
	uint8_t					_special;
}

+ (OOMusicController *) sharedController;

- (void) playMusicNamed:(NSString *)name loop:(BOOL)loop;

- (void) playThemeMusic;
- (void) playDockingMusic;
- (void) playDockedMusic;

- (void) setMissionMusic:(NSString *)missionMusicName;
- (void) playMissionMusic;

- (void) justStop;
- (void) stop;
- (void) stopMusicNamed:(NSString *)name;	// Stop only if name == playingMusic
- (void) stopThemeMusic;
- (void) stopDockingMusic;
- (void) stopMissionMusic;

- (void) toggleDockingMusic;	// Start docking music if none playing, stop docking music if currently playing docking music.

- (NSString *) playingMusic;
- (BOOL) isPlaying;

- (OOMusicMode) mode;
- (void) setMode:(OOMusicMode)mode;


@end
