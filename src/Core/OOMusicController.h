/*

OOMusicController.h

Singleton controller for music playback.

A singleton.

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

#pragma once

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "OOALMusic.h"
#include "OOFoundation.h"
#include "OOSoundSource.h"
#include "oofnd/Ref.hpp"
#include "oofnd/objc/OOObject.h"

typedef enum {
  kOOMusicOff,
  kOOMusicOn,
  kOOMusicITunes,

  kOOMusicModeMax = kOOMusicOn
} OOMusicMode;

class OOMusicController : public oo::RefCounted {
 public:
  /*	The one controller (was +sharedController),
     made on first use and never released; borrowed.
  */
  static OOMusicController* sharedController();

  OOMusicController();  // was -init

  void playMusicNamed(const std::string& name, bool loop);
  void playMusicNamed(const std::string& name, bool loop, float gain);

  void playThemeMusic();
  void playDockingMusic();
  void playDockedMusic();

  void setMissionMusic(
      const std::optional<std::string>&
          missionMusicName);  // was -cxx_setMissionMusic:; nullopt: none
  void playMissionMusic();

  void justStop();
  void stop();
  void stopMusicNamed(
      const std::string& name);  // Stop only if name == playingMusic
  void stopThemeMusic();
  void stopDockingMusic();
  void stopMissionMusic();

  void
  toggleDockingMusic();  // Start docking music if none playing, stop docking
                         // music if currently playing docking music.

  ::OOSoundSource* soundSource();

  std::optional<std::string> playingMusic();  // nullopt: nothing playing
  bool isPlaying();

  OOMusicMode mode();
  void setMode(OOMusicMode mode);

 private:
  // The private category (the iTunes integration, Mac only).
  void playiTunesPlaylist(const char* playlistName);
  void pauseiTunes();

  OOMusicMode _mode = {};
  std::optional<std::string> _missionMusic;
  oo::Ref<OOMusic> _current;
  uint8_t _special = {};
};
