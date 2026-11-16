/*

PlayerEntity+ObjCBridge.mm

TRANSITIONAL: the Objective-C PlayerEntity facade (see PlayerEntity+ObjCBridge.h). The shared
player, its initialisers and -dealloc are here, in a category while the class's @implementation is
still PlayerEntity.mm, because they need the Objective-C object as self, as is the override of the
ship's -initShipPart that makes the player's part; the other methods are still in PlayerEntity.mm
and its category files until their slices move them. Deleted with PlayerEntity+ObjCBridge.h.

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

#import "HeadUpDisplay.h"
#import "MyOpenGLView.h"
#import "OOTrumble.h"
#import "OOWeakReference.h"
#import "PlayerEntity.h"
#import "PlayerEntityControls.h"
#import "PlayerEntitySound.h"
#import "PlayerEntityStickProfile.h"
#import "ShipEntity+ObjCAdapter.h"
#include "oofnd/objc/OOAssert.h"

PlayerEntity* gOOPlayer = nil;

// The ship's initialiser for the player's -init (moved with it from PlayerEntity.mm).
@interface ShipEntity (Hax)

- (id)initBypassForPlayer;

@end

@implementation PlayerEntity (OOObjCBridge)

+ (PlayerEntity*)sharedPlayer
{
    if (EXPECT_NOT(gOOPlayer == nil)) {
        gOOPlayer = [[PlayerEntity alloc] init];
    }
    return gOOPlayer;
}

/////////////////////////////////////////////////////////

/*	Nasty initialization mechanism:
        PlayerEntity is alloced and inited on demand by +sharedPlayer. This
        initialization doesn't actually set anything up -- apart from the
        assertion, it's like doing a bare alloc. -deferredInit does the work
        that -init "should" be doing. It assumes that -[ShipEntity cxx_initWithKey:
        definition:] will not return an object other than self.
        This is necessary because we need a pointer to the PlayerEntity early in
        startup, when ship data hasn't been loaded yet. In particular, we need
        a pointer to the player to set up the JavaScript environment, we need the
        JavaScript environment to set up OpenGL, and we need OpenGL set up to load
        ships.
*/
- (id)init
{
    OOAssert(gOOPlayer == nil, "Expected only one PlayerEntity to exist at a time.");
    return [super initBypassForPlayer];
}

/*	What [super init] did in ShipEntity's initialisers, with the player's adapter: a player's C++
        part is a cxx::PlayerEntity, with the ship's adapter lines.
        -deferredInit's second ship initialiser keeps the part that is there.
*/
- (id)initShipPart
{
    // -init sent again to an initialised ship keeps its C++ part (the root's -initWithCxxEntity:).
    if (_cxxEntity != nullptr)
        return [self initWithCxxEntity:_cxxEntity.get()];
    return [self initWithCxxEntity:oo::makeRef<oo::ObjCShipEntity<cxx::PlayerEntity>>(self).get()];
}

// The root's designated initialiser, which also sets the typed alias of the part it stores, beside
// the ship's.
- (id)initWithCxxEntity:(cxx::Entity*)entity
{
    self = [super initWithCxxEntity:entity];
    if (EXPECT_NOT(self == nil))
        return nil;

    _cxxPlayer = dynamic_cast<cxx::PlayerEntity*>(_cxxEntity.get());
    OOCParameterAssert(_cxxPlayer != nullptr);
    return self;
}

- (void)deferredInit
{
    OOAssert(gOOPlayer == self, "Expected only one PlayerEntity to exist at a time.");
    OOAssert([super cxx_initWithKey:std::string(PLAYER_SHIP_DESC) definition:oo::PList(oo::PList::Dict { })] == self, "PlayerEntity requires -[ShipEntity cxx_initWithKey:definition:] to return unmodified self.");

    _cxxPlayer->maxFieldOfView = MAX_FOV;
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
    _cxxPlayer->fov_delta = 2.0; // multiply by 2 each second
#endif

    _cxxPlayer->compassMode = COMPASS_MODE_BASIC;

    _cxxPlayer->afterburnerSoundLooping = NO;

    _cxxEntity->isPlayer = YES;

    [self setStatus:STATUS_START_GAME];

    int i;
    for (i = 0; i < PLAYER_MAX_MISSILES; i++) {
        _cxxPlayer->missile_entity[i] = nil;
    }
    [self setUpAndConfirmOK:NO];

    _cxxPlayer->save_path.reset();

    _cxxPlayer->scoopsActive = NO;

    _cxxPlayer->target_memory_index = 0;

    _cxxPlayer->dockingReport.clear();
    [_cxxPlayer->hud cxx_resetGuis:oo::PList(oo::PList::Dict { { "message_gui", oo::PList(oo::PList::Dict()) },
                                       { "comm_log_gui", oo::PList(oo::PList::Dict()) } })];

    [self initControls];
}

- (void)dealloc
{
    /*	Released before its initialiser ran (alloc, then release): there is no C++ part, as in the
            ship's and the root's -dealloc.
    */
    if (_cxxPlayer == nullptr) {
        [super dealloc];
        return;
    }

    DESTROY(_cxxPlayer->compassTarget);
    DESTROY(_cxxPlayer->hud);

    _cxxPlayer->worldScripts.clear();
    _cxxPlayer->worldScriptsRequiringTickle.reset();
    _cxxPlayer->commodityScripts.clear();
    _cxxPlayer->mission_variables = oo::PList();

    _cxxPlayer->localVariables.clear();

    DESTROY(_cxxPlayer->shipCommodityData);

    _cxxPlayer->save_path.reset();
    _cxxPlayer->scenarioKey.reset();

    [self destroySound];

    DESTROY(_cxxPlayer->wormhole);

    int i;
    for (i = 0; i < PLAYER_MAX_MISSILES; i++)
        DESTROY(_cxxPlayer->missile_entity[i]);
    for (i = 0; i < PLAYER_MAX_TRUMBLES; i++)
        DESTROY(_cxxPlayer->trumble[i]);

    [super dealloc];
}

@end
