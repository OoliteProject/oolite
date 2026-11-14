/*

OOTrumble+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-862e): the Objective-C OOTrumble facade over
cxx::OOTrumble. Every method forwards to its C++ member; an argument that was OOTrumble * goes
through oo::ToCxx. The initialisers make the C++ object and register the facade as its peer
(ADR-0056 amendment oo-8kx7). Deleted with OOTrumble+ObjCBridge.h.

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

#import "OOTrumble.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOTrumble (OOObjCBridgePrivate)

- (id)initWithCxxTrumble:(cxx::OOTrumble*)trumble;
- (id)initWithNewCxxTrumble:(const oo::Ref<cxx::OOTrumble>&)trumble;

@end

@implementation OOTrumble

// Inside the @implementation for the private ivar.
OOTrumble* oo::ToObjC(cxx::OOTrumble* trumble)
{
    return Peers().peerFor(trumble, [trumble] { return [[OOTrumble alloc] initWithCxxTrumble:trumble]; });
}

cxx::OOTrumble* oo::ToCxx(OOTrumble* trumble)
{
    if (trumble == nil)
        return nullptr;
    return trumble->_cxxTrumble.get();
}

- (id)initWithCxxTrumble:(cxx::OOTrumble*)trumble
{
    self = [super init];
    if (self != nil)
        _cxxTrumble = oo::Ref<cxx::OOTrumble>(trumble);
    return self;
}

// An initialiser's C++ trumble, made before the facade: the facade is its peer.
- (id)initWithNewCxxTrumble:(const oo::Ref<cxx::OOTrumble>&)trumble
{
    self = [self initWithCxxTrumble:trumble.get()];
    if (self != nil) {
        @autoreleasepool {
            Peers().peerFor(trumble.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

- (id)init
{
    return [self initWithNewCxxTrumble:oo::makeRef<cxx::OOTrumble>()];
}

- (id)initForPlayer:(PlayerEntity*)p1
{
    return [self initWithNewCxxTrumble:oo::makeRef<cxx::OOTrumble>(p1)];
}

- (id)initForPlayer:(PlayerEntity*)p1 digram:(const std::string&)digramString
{
    return [self initWithNewCxxTrumble:oo::makeRef<cxx::OOTrumble>(p1, digramString)];
}

- (void)dealloc
{
    Peers().forget(_cxxTrumble.get());
    [super dealloc];
}

- (void)setupForPlayer:(PlayerEntity*)p1 digram:(const std::string&)digramString
{
    _cxxTrumble->setupForPlayer(p1, digramString);
}

- (void)spawnFrom:(OOTrumble*)parentTrumble
{
    _cxxTrumble->spawnFrom(oo::ToCxx(parentTrumble));
}

- (void)calcGrowthRate
{
    _cxxTrumble->calcGrowthRate();
}

- (uint16_t*)digram
{
    return _cxxTrumble->getDigram();
}
- (NSPoint)position
{
    return _cxxTrumble->getPosition();
}
- (NSPoint)movement
{
    return _cxxTrumble->getMovement();
}
- (GLfloat)rotation
{
    return _cxxTrumble->getRotation();
}
- (GLfloat)size
{
    return _cxxTrumble->getSize();
}
- (GLfloat)hunger
{
    return _cxxTrumble->getHunger();
}
- (GLfloat)discomfort
{
    return _cxxTrumble->getDiscomfort();
}

- (void)actionIdle
{
    _cxxTrumble->actionIdle();
}
- (void)actionBlink
{
    _cxxTrumble->actionBlink();
}
- (void)actionSnarl
{
    _cxxTrumble->actionSnarl();
}
- (void)actionProot
{
    _cxxTrumble->actionProot();
}
- (void)actionShudder
{
    _cxxTrumble->actionShudder();
}
- (void)actionStoned
{
    _cxxTrumble->actionStoned();
}
- (void)actionPop
{
    _cxxTrumble->actionPop();
}
- (void)actionSleep
{
    _cxxTrumble->actionSleep();
}
- (void)actionSpawn
{
    _cxxTrumble->actionSpawn();
}

- (void)randomizeMotionX
{
    _cxxTrumble->randomizeMotionX();
}
- (void)randomizeMotionY
{
    _cxxTrumble->randomizeMotionY();
}

- (void)drawTrumble:(double)z
{
    _cxxTrumble->drawTrumble(z);
}
- (void)updateTrumble:(double)delta_t
{
    _cxxTrumble->updateTrumble(delta_t);
}

- (void)updateIdle:(double)delta_t
{
    _cxxTrumble->updateIdle(delta_t);
}
- (void)updateBlink:(double)delta_t
{
    _cxxTrumble->updateBlink(delta_t);
}
- (void)updateSnarl:(double)delta_t
{
    _cxxTrumble->updateSnarl(delta_t);
}
- (void)updateProot:(double)delta_t
{
    _cxxTrumble->updateProot(delta_t);
}
- (void)updateShudder:(double)delta_t
{
    _cxxTrumble->updateShudder(delta_t);
}
- (void)updateStoned:(double)delta_t
{
    _cxxTrumble->updateStoned(delta_t);
}
- (void)updatePop:(double)delta_t
{
    _cxxTrumble->updatePop(delta_t);
}
- (void)updateSleep:(double)delta_t
{
    _cxxTrumble->updateSleep(delta_t);
}
- (void)updateSpawn:(double)delta_t
{
    _cxxTrumble->updateSpawn(delta_t);
}

- (oo::PList)dictionary
{
    return _cxxTrumble->dictionary();
}
- (void)setFromDictionary:(const oo::PList&)dict
{
    _cxxTrumble->setFromDictionary(dict);
}

@end
