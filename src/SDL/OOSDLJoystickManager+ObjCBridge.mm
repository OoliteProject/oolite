/*

OOSDLJoystickManager+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056 and its amendment oo-o89): the Objective-C
OOSDLJoystickManager facade. See OOSDLJoystickManager+ObjCBridge.h.

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

#import "OOSDLJoystickManager.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@implementation OOSDLJoystickManager

// Inside the @implementation for the private ivar.
OOSDLJoystickManager* oo::ToObjC(cxx::OOSDLJoystickManager* manager)
{
    return Peers().peerFor(manager, [] { return (id)nil; });
}

cxx::OOSDLJoystickManager* oo::ToCxx(OOSDLJoystickManager* manager)
{
    if (manager == nil)
        return nullptr;
    return manager->_cxxManager.get();
}

- (id)init
{
    // The C++ constructor is the old -init's body, which ran before [super init].
    _cxxManager = oo::makeRef<cxx::OOSDLJoystickManager>();
    @autoreleasepool {
        Peers().peerFor(_cxxManager.get(), [self] { return [self retain]; });
    }
    return [super init];
}

- (void)dealloc
{
    Peers().forget(_cxxManager.get());
    [super dealloc];
}

- (NSInteger)getJoystickIndexFromId:(SDL_JoystickID)joystickId
{
    return _cxxManager->getJoystickIndexFromId(joystickId);
}

- (SDL_JoyAxisEvent)makeJoyAxisEvent:(SDL_JoyAxisEvent*)sdlevt
{
    return _cxxManager->makeJoyAxisEvent(sdlevt);
}

- (SDL_JoyButtonEvent)makeJoyButtonEvent:(SDL_JoyButtonEvent*)sdlevt
{
    return _cxxManager->makeJoyButtonEvent(sdlevt);
}

- (SDL_JoyHatEvent)makeJoyHatEvent:(SDL_JoyHatEvent*)sdlevt
{
    return _cxxManager->makeJoyHatEvent(sdlevt);
}

- (BOOL)handleSDLEvent:(SDL_Event*)evt
{
    return _cxxManager->handleSDLEvent(evt);
}

// Overrides

- (NSUInteger)joystickCount
{
    return _cxxManager->joystickCount();
}

- (std::optional<std::string>)nameOfJoystick:(NSUInteger)stickNumber
{
    return _cxxManager->nameOfJoystick(stickNumber);
}

- (int16_t)getAxisWithStick:(NSUInteger)stickNum axis:(NSUInteger)axisNum
{
    return _cxxManager->getAxisWithStick(stickNum, axisNum);
}

@end
