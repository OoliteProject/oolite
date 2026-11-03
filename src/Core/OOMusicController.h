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

#import "OOFoundation.h"
#import "OOSoundSource.h"
#import "oofnd/objc/OOObject.h"

#include "oofnd/StdLib.hpp"

@class OOMusic;

#define OOLITE_ITUNES_SUPPORT OOLITE_MAC_COCOA_UI

typedef enum {
    kOOMusicOff,
    kOOMusicOn,
    kOOMusicITunes,

#if OOLITE_ITUNES_SUPPORT
    kOOMusicModeMax = kOOMusicITunes
#else
    kOOMusicModeMax = kOOMusicOn
#endif
} OOMusicMode;

@interface OOMusicController : OOObject {
@private
    OOMusicMode _mode;
    std::optional<std::string> _missionMusic;
    OOMusic* _current;
    uint8_t _special;
}

+ (OOMusicController*)sharedController;

- (void)playMusicNamed:(const std::string&)name loop:(BOOL)loop;
- (void)playMusicNamed:(const std::string&)name loop:(BOOL)loop gain:(float)gain;

- (void)playThemeMusic;
- (void)playDockingMusic;
- (void)playDockedMusic;

- (void)cxx_setMissionMusic:(const std::optional<std::string>&)missionMusicName; // nullopt: none (was the shared selector -setMissionMusic:, bead oo-qps.53)
- (void)playMissionMusic;

- (void)justStop;
- (void)stop;
- (void)stopMusicNamed:(const std::string&)name; // Stop only if name == playingMusic
- (void)stopThemeMusic;
- (void)stopDockingMusic;
- (void)stopMissionMusic;

- (void)toggleDockingMusic; // Start docking music if none playing, stop docking music if currently playing docking music.

- (OOSoundSource*)soundSource;

- (std::optional<std::string>)playingMusic; // nullopt: nothing playing
- (BOOL)isPlaying;

- (OOMusicMode)mode;
- (void)setMode:(OOMusicMode)mode;

@end
