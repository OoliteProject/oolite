/*

OOMusicController+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, the Audio module: amendment oo-2en): the Objective-C
OOMusicController facade (see OOMusicController+ObjCBridge.h). Every method forwards to its C++
member. Deleted with OOMusicController+ObjCBridge.h.


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

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOMusicController (OOObjCBridgePrivate)

- (id)initWithCxxController:(cxx::OOMusicController*)controller;

@end

@implementation OOMusicController

// Inside the @implementation for the private ivar.
OOMusicController* oo::ToObjC(cxx::OOMusicController* controller)
{
    return Peers().peerFor(controller, [controller] { return [[OOMusicController alloc] initWithCxxController:controller]; });
}

cxx::OOMusicController* oo::ToCxx(OOMusicController* controller)
{
    if (controller == nil)
        return nullptr;
    return controller->_cxxController.get();
}

- (id)initWithCxxController:(cxx::OOMusicController*)controller
{
    self = [super init];
    if (self != nil)
        _cxxController = oo::Ref<cxx::OOMusicController>(controller);
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxController.get());
    [super dealloc];
}

// One facade for the life of the process, retained once and kept (amendment oo-r7m0 item 5).
+ (OOMusicController*)sharedController
{
    static OOMusicController* facade = nil;
    if (facade == nil)
        facade = [oo::ToObjC(cxx::OOMusicController::sharedController()) retain];
    return facade;
}

- (void)playMusicNamed:(const std::string&)name loop:(BOOL)loop
{
    _cxxController->playMusicNamed(name, loop);
}
- (void)playMusicNamed:(const std::string&)name loop:(BOOL)loop gain:(float)gain
{
    _cxxController->playMusicNamed(name, loop, gain);
}

- (void)playThemeMusic
{
    _cxxController->playThemeMusic();
}
- (void)playDockingMusic
{
    _cxxController->playDockingMusic();
}
- (void)playDockedMusic
{
    _cxxController->playDockedMusic();
}

- (void)cxx_setMissionMusic:(const std::optional<std::string>&)missionMusicName
{
    _cxxController->setMissionMusic(missionMusicName);
}
- (void)playMissionMusic
{
    _cxxController->playMissionMusic();
}

- (void)justStop
{
    _cxxController->justStop();
}
- (void)stop
{
    _cxxController->stop();
}
- (void)stopMusicNamed:(const std::string&)name
{
    _cxxController->stopMusicNamed(name);
}
- (void)stopThemeMusic
{
    _cxxController->stopThemeMusic();
}
- (void)stopDockingMusic
{
    _cxxController->stopDockingMusic();
}
- (void)stopMissionMusic
{
    _cxxController->stopMissionMusic();
}

- (void)toggleDockingMusic
{
    _cxxController->toggleDockingMusic();
}

- (OOSoundSource*)soundSource
{
    return _cxxController->soundSource();
}

- (std::optional<std::string>)playingMusic
{
    return _cxxController->playingMusic();
}
- (BOOL)isPlaying
{
    return _cxxController->isPlaying();
}

- (OOMusicMode)mode
{
    return _cxxController->mode();
}
- (void)setMode:(OOMusicMode)mode
{
    _cxxController->setMode(mode);
}

@end
