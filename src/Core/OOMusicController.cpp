/*

OOMusicController.m

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

#include "OOMusicController.h"

#include "OOSound.h"
#include "ResourceManager.h"
#include "oofnd/Defaults.hpp"
#include "oofnd/Log.hpp"

namespace {

OOMusicController* sSingleton = nullptr;

}  // namespace

// Values for _special

constexpr int kSpecialNone = 0;
constexpr int kSpecialTheme = kSpecialNone + 1;
constexpr int kSpecialDocking = kSpecialTheme + 1;
constexpr int kSpecialDocked = kSpecialDocking + 1;
constexpr int kSpecialMission = kSpecialDocked + 1;

OOMusicController* OOMusicController::sharedController() {
  if (sSingleton == nullptr) {
    sSingleton = (*new std::shared_ptr<OOMusicController>(
                      oo::makeShared<OOMusicController>()))
                     .get();
  }

  return sSingleton;
}

// The body of -init after [super init], which could not fail.
OOMusicController::OOMusicController() {
  {
    const std::optional<std::string> modeString =
        oo::Defaults::standard().stringForKey("music mode");
    if (modeString == "off")
      _mode = OOMusicMode::kOff;
    else if (modeString == "iTunes")
      _mode = OOMusicMode::kITunes;
    else
      _mode = OOMusicMode::kOn;

    // Handle unlikely case of taking prefs from iTunes-enabled system to other.
    if (_mode > kOOMusicModeMax) _mode = kOOMusicModeMax;

    _missionMusic = "OoliteTheme.ogg";
  }
}

void OOMusicController::playMusicNamed(const std::string& name, bool loop) {
  playMusicNamed(name, loop, OO_DEFAULT_SOUNDSOURCE_GAIN);
}

void OOMusicController::playMusicNamed(const std::string& name, bool loop,
                                       float gain) {
  if (isPlaying() && name == playingMusic()) return;

  if (_mode == OOMusicMode::kOn ||
      (_mode == OOMusicMode::kITunes && name == "OoliteTheme.ogg")) {
    oo::Ref<OOMusic> music =
        ResourceManager::ooMusicNamed(name, std::string("Music"));
    if (music) {
      if (_current) _current->stop();

      music->setMusicGain(OOClamp_0_1_f(gain));
      music->playLooped(loop);

      _current = std::move(music);
    }
  }
}

void OOMusicController::playThemeMusic() {
  _special = kSpecialTheme;
  playMusicNamed("OoliteTheme.ogg", true);
}

void OOMusicController::playDockingMusic() {
  _special = kSpecialDocking;

  if (_mode == OOMusicMode::kITunes) {
    playiTunesPlaylist("Oolite-Docking");
  } else {
    playMusicNamed("BlueDanube.ogg", true);
  }
}

void OOMusicController::playDockedMusic() {
  _special = kSpecialDocked;

  if (_mode == OOMusicMode::kITunes) {
    playiTunesPlaylist("Oolite-Docked");
  } else {
    playMusicNamed("OoliteDocked.ogg", false);
  }
}

void OOMusicController::setMissionMusic(
    const std::optional<std::string>& missionMusicName) {
  _missionMusic = missionMusicName;
}

void OOMusicController::playMissionMusic() {
  if (_missionMusic.has_value()) {
    _special = kSpecialMission;
    playMusicNamed(*_missionMusic, false);
  }
}

// Stop without switching iTunes to in-flight music.
void OOMusicController::justStop() {
  if (_current) _current->stop();
  _current = nullptr;
  _special = kSpecialNone;
}

void OOMusicController::stop() {
  justStop();

  if (_mode == OOMusicMode::kITunes) {
    playiTunesPlaylist("Oolite-Inflight");
  }
}

void OOMusicController::stopMusicNamed(const std::string& name) {
  if (name == playingMusic()) stop();
}

void OOMusicController::stopThemeMusic() {
  if (_special == kSpecialTheme) {
    justStop();
    playDockedMusic();
  }
}

void OOMusicController::stopDockingMusic() {
  if (_special == kSpecialDocking) stop();
}

void OOMusicController::stopMissionMusic() {
  if (_special == kSpecialMission) stop();
}

void OOMusicController::toggleDockingMusic() {
  if (_mode != OOMusicMode::kOn) return;

  if (!isPlaying())
    playDockingMusic();
  else if (_special == kSpecialDocking)
    stop();
}

::OOSoundSource* OOMusicController::soundSource() {
  return _current ? _current->musicSoundSource() : nullptr;
}

std::optional<std::string> OOMusicController::playingMusic() {
  return _current ? _current->name() : std::nullopt;
}

bool OOMusicController::isPlaying() {
  return _current && _current->isPlaying();
}

OOMusicMode OOMusicController::mode() { return _mode; }

void OOMusicController::setMode(OOMusicMode mode) {
  if (mode <= kOOMusicModeMax && _mode != mode) {
    if (_mode == OOMusicMode::kITunes) pauseiTunes();
    _mode = mode;

    if (_mode == OOMusicMode::kOff)
      stop();
    else
      switch (_special) {
        case kSpecialNone:
          stop();
          break;

        case kSpecialTheme:
          playThemeMusic();
          break;

        case kSpecialDocked:
          playDockedMusic();
          break;

        case kSpecialDocking:
          playDockingMusic();
          break;

        case kSpecialMission:
          playMissionMusic();
          break;
      }

    std::optional<std::string> modeString;
    switch (_mode) {
      case OOMusicMode::kOff:
        modeString = "off";
        break;
      case OOMusicMode::kOn:
        modeString = "on";
        break;
      case OOMusicMode::kITunes:
        modeString = "iTunes";
        break;
    }
    oo::Defaults::standard().setObject(
        "music mode", modeString ? oo::PList(*modeString) : oo::PList());
  }
}

// The singleton category (+allocWithZone:, -retain and the rest) is not
// translated: the controller has no other creator and is never released.

// The iTunes integration. Upstream's Cocoa build drove iTunes with AppleScript;
// no other build has it, so these do nothing.
void OOMusicController::playiTunesPlaylist(std::string_view /*playlistName*/) {}
void OOMusicController::pauseiTunes() {}
