/*

OOMusicController.h

Singleton controller for music playback.

C++20 since bead oo-lfkq (proposed ADR-0056, the Audio module: amendment oo-2en; a singleton:
amendment oo-r7m0). Its Objective-C facade was deleted by bead oo-9ht.90, and the class left
namespace cxx.


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

#ifndef OOMUSICCONTROLLER_H
#define OOMUSICCONTROLLER_H

#include "OOCocoa.h"
#include "oofnd/objc/OOObject.h"
#include "OOSoundSource.h"

#include "oofnd/StdLib.hpp"
#include "oofnd/Ref.hpp"

#include "OOALMusic.h"


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


class OOMusicController : public oo::RefCounted
{
public:
	/*	Was +sharedController (amendment oo-r7m0 item 1): the one controller, made on first use and
		never released; borrowed.
	*/
	static OOMusicController *sharedController();

	OOMusicController();	// was -init

	void playMusicNamed(const std::string &name, bool loop);
	void playMusicNamed(const std::string &name, bool loop, float gain);

	void playThemeMusic();
	void playDockingMusic();
	void playDockedMusic();

	void setMissionMusic(const std::optional<std::string> &missionMusicName);	// was -cxx_setMissionMusic:; nullopt: none
	void playMissionMusic();

	void justStop();
	void stop();
	void stopMusicNamed(const std::string &name);	// Stop only if name == playingMusic
	void stopThemeMusic();
	void stopDockingMusic();
	void stopMissionMusic();

	void toggleDockingMusic();	// Start docking music if none playing, stop docking music if currently playing docking music.

	::OOSoundSource *soundSource();	// C++ since bead oo-9ht.88

	std::optional<std::string> playingMusic();	// nullopt: nothing playing
	bool isPlaying();

	OOMusicMode mode();
	void setMode(OOMusicMode mode);

private:
	// The private category (the iTunes integration, Mac only).
	void playiTunesPlaylist(const char *playlistName);
	void pauseiTunes();

	OOMusicMode				_mode = {};
	std::optional<std::string>	_missionMusic;
	oo::Ref<OOMusic>		_current;
	uint8_t					_special = {};
};



#endif	// OOMUSICCONTROLLER_H
