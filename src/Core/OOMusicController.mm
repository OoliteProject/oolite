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

#import "OOMusicController.h"
#import "OOSound.h"
#import "ResourceManager.h"
#include "oofnd/Defaults.hpp"
#include "oofnd/Log.hpp"

static id sSingleton = nil;

@interface OOMusicController (Private)

- (void)playiTunesPlaylist:(const char*)playlistName;
- (void)pauseiTunes;

@end

// Values for _special
enum {
    kSpecialNone,
    kSpecialTheme,
    kSpecialDocking,
    kSpecialDocked,
    kSpecialMission
};

@implementation OOMusicController

+ (OOMusicController*)sharedController
{
    if (sSingleton == nil) {
        sSingleton = [[self alloc] init];
    }

    return sSingleton;
}

- (id)init
{
    self = [super init];
    if (self != nil) {
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

    return self;
}

- (void)playMusicNamed:(const std::string&)name loop:(BOOL)loop
{
    [self playMusicNamed:name loop:loop gain:OO_DEFAULT_SOUNDSOURCE_GAIN];
}

- (void)playMusicNamed:(const std::string&)name loop:(BOOL)loop gain:(float)gain
{
    if ([self isPlaying] && name == [self playingMusic])
        return;

    if (_mode == kOOMusicOn || (_mode == kOOMusicITunes && name == "OoliteTheme.ogg")) {
        OOMusic* music = [ResourceManager cxx_ooMusicNamed:name inFolder:"Music"];
        if (music != nil) {
            [_current stop];

            [music setMusicGain:OOClamp_0_1_f(gain)];
            [music playLooped:loop];

            [_current release];
            _current = [music retain];
        }
    }
}

- (void)playThemeMusic
{
    _special = kSpecialTheme;
    [self playMusicNamed:"OoliteTheme.ogg" loop:YES];
}

- (void)playDockingMusic
{
    _special = kSpecialDocking;

    if (_mode == kOOMusicITunes) {
        [self playiTunesPlaylist:"Oolite-Docking"];
    } else {
        [self playMusicNamed:"BlueDanube.ogg" loop:YES];
    }
}

- (void)playDockedMusic
{
    _special = kSpecialDocked;

    if (_mode == kOOMusicITunes) {
        [self playiTunesPlaylist:"Oolite-Docked"];
    } else {
        [self playMusicNamed:"OoliteDocked.ogg" loop:NO];
    }
}

- (void)cxx_setMissionMusic:(const std::optional<std::string>&)missionMusicName
{
    _missionMusic = missionMusicName;
}

- (void)playMissionMusic
{
    if (_missionMusic.has_value()) {
        _special = kSpecialMission;
        [self playMusicNamed:*_missionMusic loop:NO];
    }
}

// Stop without switching iTunes to in-flight music.
- (void)justStop
{
    [_current stop];
    [_current release];
    _current = nil;
    _special = kSpecialNone;
}

- (void)stop
{
    [self justStop];

    if (_mode == kOOMusicITunes) {
        [self playiTunesPlaylist:"Oolite-Inflight"];
    }
}

- (void)stopMusicNamed:(const std::string&)name
{
    if (name == [self playingMusic])
        [self stop];
}

- (void)stopThemeMusic
{
    if (_special == kSpecialTheme) {
        [self justStop];
        [self playDockedMusic];
    }
}

- (void)stopDockingMusic
{
    if (_special == kSpecialDocking)
        [self stop];
}

- (void)stopMissionMusic
{
    if (_special == kSpecialMission)
        [self stop];
}

- (void)toggleDockingMusic
{
    if (_mode != kOOMusicOn)
        return;

    if (![self isPlaying])
        [self playDockingMusic];
    else if (_special == kSpecialDocking)
        [self stop];
}

- (OOSoundSource*)soundSource
{
    return [_current musicSoundSource];
}

- (std::optional<std::string>)playingMusic
{
    return [_current cxx_name];
}

- (BOOL)isPlaying
{
    return [_current isPlaying];
}

- (OOMusicMode)mode
{
    return _mode;
}

- (void)setMode:(OOMusicMode)mode
{
    if (mode <= kOOMusicModeMax && _mode != mode) {
        if (_mode == kOOMusicITunes)
            [self pauseiTunes];
        _mode = mode;

        if (_mode == kOOMusicOff)
            [self stop];
        else
            switch (_special) {
            case kSpecialNone:
                [self stop];
                break;

            case kSpecialTheme:
                [self playThemeMusic];
                break;

            case kSpecialDocked:
                [self playDockedMusic];
                break;

            case kSpecialDocking:
                [self playDockingMusic];
                break;

            case kSpecialMission:
                [self playMissionMusic];
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

@end

@implementation OOMusicController (Singleton)

/*	Canonical singleton boilerplate.
        See Cocoa Fundamentals Guide: Creating a Singleton Instance.
        See also +sharedController above.

        NOTE: assumes single-threaded access.
*/

+ (id)allocWithZone:(OOZone*)inZone
{
    if (sSingleton == nil) {
        sSingleton = [super allocWithZone:inZone];
        return sSingleton;
    }
    return nil;
}

- (id)copyWithZone:(OOZone*)inZone
{
    return self;
}

- (id)retain
{
    return self;
}

- (NSUInteger)retainCount
{
    return UINT_MAX;
}

- (void)release
{
}

- (id)autorelease
{
    return self;
}

@end

@implementation OOMusicController (Private)

#if OOLITE_MAC_OS_X
- (void)playiTunesPlaylist:(const char*)playlistNameUTF8
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

- (void)pauseiTunes
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
- (void)playiTunesPlaylist:(const char*)playlistName
{
}
- (void)pauseiTunes
{
}
#endif

@end
