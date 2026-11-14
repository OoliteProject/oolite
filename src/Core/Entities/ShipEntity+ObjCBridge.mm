/*

ShipEntity+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8 and oo-60fwo): the Objective-C ShipEntity
facade (see ShipEntity+ObjCBridge.h). Its initialisers and -dealloc are here, in a category while
the class's @implementation is still ShipEntity.mm, because they need the Objective-C object as
self (amendment oo-bj8 items 6 and 7), and so are the two SubEntityRelationship categories (item
12); the other methods are still in ShipEntity.mm until their slices move them. Deleted with
ShipEntity+ObjCBridge.h.

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

#import "AI.h"
#import "OOColor.h"
#import "OODescription.h"
#import "OOJSEngineTimeManagement.h"
#import "OOJSScript.h"
#import "OORoleSet.h"
#import "OOShipGroup.h"
#import "OOWeakSet.h"
#import "Octree.h"
#import "ShipEntity.h"
#import "ShipEntityAI.h"
#import "ShipEntityScriptMethods.h"
#include "oofnd/Log.hpp"
#include "oofnd/objc/OOAssert.h"

#include <cmath>

@interface ShipEntity (OOObjCBridgePrivate)

- (id)initShipPart;

@end

@implementation ShipEntity (OOObjCBridge)

- (id)init
{
    /*	-init used to set up a bunch of defaults that were different from
            those in -reinit and -setUpShipFromDictionary:. However, it seems that
            no ships are ever used which are not -setUpShipFromDictionary: (which
            is as it should be), so these different defaults were meaningless.
    */
    return [self cxx_initWithKey:std::string { } definition:oo::PList()];
}

- (id)initBypassForPlayer
{
    return [self initShipPart]; // [super init]
}

- (id)cxx_initWithKey:(const std::string&)key definition:(const oo::PList&)dict
{
    OOJS_PROFILE_ENTER

    self = [self initShipPart]; // [super init]
    if (self == nil)
        return nil;

    _cxxShip->initWithKey(key);

    if (![self setUpShipFromDictionary:dict]) {
        [self release];
        self = nil;
    }

    // Problem observed in testing -- Ahruman
    if (self != nil && !isfinite(_cxxShip->maxFlightSpeed)) {
        OO_LOG("ship.sanityCheck.failed", "Ship {} {} infinite top speed, clamped to 300.", oo::DescriptionOf(self), "generated with");
        _cxxShip->maxFlightSpeed = 300;
    }
    return self;

    OOJS_PROFILE_EXIT
}

/*	What [super init] did in the two initialisers, with the ship's adapter: an Objective-C ship, of
        this class or a subclass, has a C++ part over cxx::ShipEntity (amendment oo-bj8 item 5), as
        OOEntityWithDrawable's -init makes one over its class.
*/
- (id)initShipPart
{
    // -init sent again to an initialised ship keeps its C++ part (the root's -initWithCxxEntity:).
    if (_cxxEntity != nullptr)
        return [self initWithCxxEntity:_cxxEntity.get()];
    return [self initWithCxxEntity:oo::makeRef<oo::ObjCEntity<cxx::ShipEntity>>(self).get()];
}

// The root's designated initialiser, which also sets the typed alias of the part it stores.
- (id)initWithCxxEntity:(cxx::Entity*)entity
{
    self = [super initWithCxxEntity:entity];
    if (EXPECT_NOT(self == nil))
        return nil;

    _cxxShip = dynamic_cast<cxx::ShipEntity*>(_cxxEntity.get());
    OOCParameterAssert(_cxxShip != nullptr);
    return self;
}

- (void)dealloc
{
    /*	Released before its initialiser ran (a failing initialiser's [self release]; return nil;):
            there is no C++ part, as in the root's -dealloc (oo-s6ic6).
    */
    if (_cxxShip == nullptr) {
        [super dealloc];
        return;
    }

    /*	NOTE: we guarantee that entityDestroyed is sent immediately after the
            JS ship becomes invalid (as a result of dropping the weakref), i.e.
            with no intervening script activity.
            It has to be after the invalidation so that scripts can't directly or
            indirectly cause the ship to become strong-referenced. (Actually, we
            could handle that situation by breaking out of dealloc, but that's a
            nasty abuse of framework semantics and would require special-casing in
            subclasses.)
            -- Ahruman 2011-02-27
    */
    [weakSelf weakRefDrop];
    weakSelf = nil;
    [self doScriptEvent:OOJSID("entityDestroyed")];

    [self setTrackCloseContacts:NO]; // deallocs tracking dictionary
    [[self parentEntity] subEntityReallyDied:self]; // Will do nothing if we're not really a subentity
    [self clearSubEntities];

    DESTROY(_cxxShip->shipAI);
    DESTROY(_cxxShip->roleSet);
    DESTROY(_cxxShip->laser_color);
    DESTROY(_cxxShip->default_laser_color);
    DESTROY(_cxxShip->exhaust_emissive_color);
    DESTROY(_cxxShip->scanner_display_color1);
    DESTROY(_cxxShip->scanner_display_color2);
    DESTROY(_cxxShip->scanner_display_color_hostile1);
    DESTROY(_cxxShip->scanner_display_color_hostile2);
    DESTROY(_cxxShip->script);
    DESTROY(_cxxShip->aiScript);
    DESTROY(_cxxShip->octree);
    DESTROY(_cxxShip->_defenseTargets);
    DESTROY(_cxxShip->_collisionExceptions);

    [self setSubEntityTakingDamage:nil];
    [self removeAllEquipment];

    [_cxxShip->_group removeShip:self];
    DESTROY(_cxxShip->_group);
    [_cxxShip->_escortGroup removeShip:self];
    DESTROY(_cxxShip->_escortGroup);

    DESTROY(_cxxShip->_lastAegisLock);

    DESTROY(_cxxShip->_beaconDrawable);

    [super dealloc];
}

@end

@implementation Entity (SubEntityRelationship)

- (BOOL)isShipWithSubEntityShip:(Entity*)other
{
    return NO;
}

- (void)drawSubEntityImmediate:(bool)immediate translucent:(bool)translucent
{
    // Do nothing.
}

@end

@implementation ShipEntity (SubEntityRelationship)

- (BOOL)isShipWithSubEntityShip:(Entity*)other
{
    return oo::ToCxx(self)->isShipWithSubEntityShip(other);
}

@end
