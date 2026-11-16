/*

OOMusicController+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, the Audio module: amendment oo-2en): the Objective-C
OOMusicController, a facade over the C++ cxx::OOMusicController (OOMusicController.h), for the
player, the universe and the JS Sound and Mission classes. Its interface is the one
OOMusicController.h declared before the conversion, copied exactly. +sharedController answers one
facade for the life of the process (amendment oo-r7m0 item 5). Imported as the last line of
OOMusicController.h; do not import it directly. Never add to this file; converted code does not
message the facade. Deleted by its deletion bead once every caller is C++.


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

#ifndef OOMUSICCONTROLLER_OBJCBRIDGE_H
#define OOMUSICCONTROLLER_OBJCBRIDGE_H

@interface OOMusicController : OOObject {
@private
    oo::Ref<cxx::OOMusicController> _cxxController;
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

namespace oo {

// The controller's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOMusicController* ToObjC(cxx::OOMusicController* controller);

// The C++ controller behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOMusicController* ToCxx(OOMusicController* controller);

} // namespace oo

#endif // OOMUSICCONTROLLER_OBJCBRIDGE_H
