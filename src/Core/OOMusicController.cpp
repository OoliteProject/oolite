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

} // namespace

// Values for _special
enum {
    kSpecialNone,
    kSpecialTheme,
    kSpecialDocking,
    kSpecialDocked,
    kSpecialMission
};

OOMusicController* OOMusicController::sharedController()
{
    if (sSingleton == nullptr) {
        sSingleton = oo::makeRef<OOMusicController>().leakRef();
    }

    return sSingleton;
}

// The body of -init after [super init], which could not fail.
OOMusicController::OOMusicController()
{
    {
        const std::optional<std::string> modeString = oo::Defaults::standard().stringForKey("music mode");
        if (modeString == "off")
            _mode = kOOMusicOff;
        else if (modeString == "iTunes")
            _mode = kOOMusicITunes;
        else
            _mode = kOOMusicOn;

        // Handle unlikely case of taking prefs from iTunes-enabled system to other.
        if (_mode > kOOMusicModeMax)
            _mode = kOOMusicModeMax;

        _missionMusic = "OoliteTheme.ogg";
    }
}

void OOMusicController::playMusicNamed(const std::string& name, bool loop)
{
    playMusicNamed(name, loop, OO_DEFAULT_SOUNDSOURCE_GAIN);
}

void OOMusicController::playMusicNamed(const std::string& name, bool loop, float gain)
{
    if (isPlaying() && name == playingMusic())
        return;

    if (_mode == kOOMusicOn || (_mode == kOOMusicITunes && name == "OoliteTheme.ogg")) {
        oo::Ref<OOMusic> music = ResourceManager::ooMusicNamed(name, std::string("Music"));
        if (music) {
            if (_current)
                _current->stop();

            music->setMusicGain(OOClamp_0_1_f(gain));
            music->playLooped(loop);

            _current = std::move(music);
        }
    }
}

void OOMusicController::playThemeMusic()
{
    _special = kSpecialTheme;
    playMusicNamed("OoliteTheme.ogg", true);
}

void OOMusicController::playDockingMusic()
{
    _special = kSpecialDocking;

    if (_mode == kOOMusicITunes) {
        playiTunesPlaylist("Oolite-Docking");
    } else {
        playMusicNamed("BlueDanube.ogg", true);
    }
}

void OOMusicController::playDockedMusic()
{
    _special = kSpecialDocked;

    if (_mode == kOOMusicITunes) {
        playiTunesPlaylist("Oolite-Docked");
    } else {
        playMusicNamed("OoliteDocked.ogg", false);
    }
}

void OOMusicController::setMissionMusic(const std::optional<std::string>& missionMusicName)
{
    _missionMusic = missionMusicName;
}

void OOMusicController::playMissionMusic()
{
    if (_missionMusic.has_value()) {
        _special = kSpecialMission;
        playMusicNamed(*_missionMusic, false);
    }
}

// Stop without switching iTunes to in-flight music.
void OOMusicController::justStop()
{
    if (_current)
        _current->stop();
    _current = nullptr;
    _special = kSpecialNone;
}

void OOMusicController::stop()
{
    justStop();

    if (_mode == kOOMusicITunes) {
        playiTunesPlaylist("Oolite-Inflight");
    }
}

void OOMusicController::stopMusicNamed(const std::string& name)
{
    if (name == playingMusic())
        stop();
}

void OOMusicController::stopThemeMusic()
{
    if (_special == kSpecialTheme) {
        justStop();
        playDockedMusic();
    }
}

void OOMusicController::stopDockingMusic()
{
    if (_special == kSpecialDocking)
        stop();
}

void OOMusicController::stopMissionMusic()
{
    if (_special == kSpecialMission)
        stop();
}

void OOMusicController::toggleDockingMusic()
{
    if (_mode != kOOMusicOn)
        return;

    if (!isPlaying())
        playDockingMusic();
    else if (_special == kSpecialDocking)
        stop();
}

::OOSoundSource* OOMusicController::soundSource()
{
    return _current ? _current->musicSoundSource() : nil;
}

std::optional<std::string> OOMusicController::playingMusic()
{
    return _current ? _current->name() : std::nullopt;
}

bool OOMusicController::isPlaying()
{
    return _current && _current->isPlaying();
}

OOMusicMode OOMusicController::mode()
{
    return _mode;
}

void OOMusicController::setMode(OOMusicMode mode)
{
    if (mode <= kOOMusicModeMax && _mode != mode) {
        if (_mode == kOOMusicITunes)
            pauseiTunes();
        _mode = mode;

        if (_mode == kOOMusicOff)
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
        case kOOMusicOff:
            modeString = "off";
            break;
        case kOOMusicOn:
            modeString = "on";
            break;
        case kOOMusicITunes:
            modeString = "iTunes";
            break;
        }
        oo::Defaults::standard().setObject("music mode", modeString ? oo::PList(*modeString) : oo::PList());
    }
}

// The singleton category (+allocWithZone:, -retain and the rest) is not translated: the controller
// has no other creator and is never released (amendment oo-r7m0 item 1).

// The private category: the iTunes integration, compiled for the Mac only (amendment oo-bgmb item 2).
#if OOLITE_MAC_OS_X
void OOMusicController::playiTunesPlaylist(const char* playlistNameUTF8)
{
    NSString* playlistName = oo::NSStringFrom(playlistNameUTF8);
    NSString* ootunesScriptString =
        [NSString stringWithFormat:
                @"with timeout of 1 second\n"
                 "    tell application \"iTunes\"\n"
                 "        copy playlist \"%@\" to thePlaylist\n"
                 "        if thePlaylist exists then\n"
                 "            play some track of thePlaylist\n"
                 "        end if\n"
                 "    end tell\n"
                 "end timeout",
            playlistName];

    NSAppleScript* ootunesScript = [[[NSAppleScript alloc] initWithSource:ootunesScriptString] autorelease];
    NSDictionary* errDict = nil;

    [ootunesScript executeAndReturnError:&errDict];
    if (errDict)
        OO_LOG("sound.music.iTunesIntegration.failed", "ootunes returned :{}", oo::DescriptionOf(errDict));
}

void OOMusicController::pauseiTunes()
{
    NSString* ootunesScriptString = [NSString stringWithFormat:@"try\nignoring application responses\ntell application \"iTunes\" to pause\nend ignoring\nend try"];
    NSAppleScript* ootunesScript = [[NSAppleScript alloc] initWithSource:ootunesScriptString];
    NSDictionary* errDict = nil;
    [ootunesScript executeAndReturnError:&errDict];
    if (errDict)
        OO_LOG("sound.music.iTunesIntegration.failed", "ootunes returned :{}", oo::DescriptionOf(errDict));
    [ootunesScript release];
}
#else
void OOMusicController::playiTunesPlaylist(const char* /*playlistName*/) { }
void OOMusicController::pauseiTunes() { }
#endif
