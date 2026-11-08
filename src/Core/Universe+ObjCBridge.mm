/*

Universe+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendment oo-riqmz): the Objective-C Universe facade (see
Universe+ObjCBridge.h). Its initialiser and -dealloc are here because they need the Objective-C
object as self; their bodies are cxx::Universe's initWithGameView() and dealloc(), in Universe.mm.
Every other method is a forwarder to a cxx::Universe member, in the category of its slice. The
class's primary @implementation is here too (bead oo-pas, as oo-k8a did for ShipEntity): empty but
for the Mac speech arms, which stay Objective-C (Mac-only, not adapted in Phase 3). The delayed
message holder the deferred call retains is here as well. Deleted with Universe+ObjCBridge.h.

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

#import "GameController.h"
#import "Universe.h"
#include "oofnd/objc/OOException.h"

extern Universe* gSharedUniverse;

@implementation Universe

// speech routines (the Mac arms; the others are slice 24's forwarders)
#if OOLITE_MAC_OS_X

- (void)cxx_startSpeakingString:(const std::string&)text
{
    [_cxxUniverse->speechSynthesizer startSpeakingString:oo::NSStringFrom(oo::str::format("[[volm %.3f]]%s", 0.3333333f * OOSound::masterVolume(), text.c_str()))];
}

- (void)stopSpeaking
{
    if ([_cxxUniverse->speechSynthesizer respondsToSelector:@selector(stopSpeakingAtBoundary:)]) {
        [_cxxUniverse->speechSynthesizer stopSpeakingAtBoundary:NSSpeechWordBoundary];
    } else {
        [_cxxUniverse->speechSynthesizer stopSpeaking];
    }
}

- (BOOL)isSpeaking
{
    return [_cxxUniverse->speechSynthesizer isSpeaking];
}

#endif

@end

@implementation OOUniverseDelayedMessage
@end

@implementation Universe (OOObjCBridge)

- (id)initWithGameView:(MyOpenGLView*)inGameView
{
    /*	The part first: a universe refused below is released at once, and its -dealloc runs the
            whole body as it did when the ivars were the object's.
    */
    if (_cxxUniverse == nullptr)
        _cxxUniverse = oo::makeRef<cxx::Universe>(self);

    if (gSharedUniverse != nil) {
        [self release];
        [OOException raise:OOInternalInconsistencyException format:"%s: expected only one Universe to exist at a time.", __PRETTY_FUNCTION__];
    }

    OO_DEBUG_PROGRESS("Universe initWithGameView:");

    self = [super init];
    if (self == nil)
        return nil;

    _cxxUniverse->initWithGameView(inGameView);
    return self;
}

- (void)dealloc
{
    // A universe released before -initWithGameView: made its part has nothing to tear down (oo-s6ic6).
    if (_cxxUniverse != nullptr)
        _cxxUniverse->dealloc();
    _cxxUniverse = nullptr;

    [super dealloc];
}

@end

@implementation Universe (OOSlice2)

- (BOOL)bloom
{
    return _cxxUniverse->bloom();
}
- (void)setBloom:(BOOL)newBloom
{
    _cxxUniverse->setBloom(newBloom);
}
- (int)currentPostFX
{
    return _cxxUniverse->currentPostFX();
}
- (void)setCurrentPostFX:(int)newCurrentPostFX
{
    _cxxUniverse->setCurrentPostFX(newCurrentPostFX);
}
- (void)terminatePostFX:(int)postFX
{
    _cxxUniverse->terminatePostFX(postFX);
}
- (int)nextColorblindMode:(int)index
{
    return _cxxUniverse->nextColorblindMode(index);
}
- (int)prevColorblindMode:(int)index
{
    return _cxxUniverse->prevColorblindMode(index);
}
- (int)colorblindMode
{
    return _cxxUniverse->colorblindMode();
}
- (void)initTargetFramebufferWithViewSize:(NSSize)viewSize
{
    _cxxUniverse->initTargetFramebufferWithViewSize(viewSize);
}
- (void)deleteOpenGLObjects
{
    _cxxUniverse->deleteOpenGLObjects();
}
- (void)resizeTargetFramebufferWithViewSize:(NSSize)viewSize
{
    _cxxUniverse->resizeTargetFramebufferWithViewSize(viewSize);
}
- (void)drawTargetTextureIntoDefaultFramebuffer
{
    _cxxUniverse->drawTargetTextureIntoDefaultFramebuffer();
}
- (NSUInteger)sessionID
{
    return _cxxUniverse->sessionID();
}
- (BOOL)doingStartUp
{
    return _cxxUniverse->doingStartUp();
}
- (BOOL)doProcedurallyTexturedPlanets
{
    return _cxxUniverse->getDoProcedurallyTexturedPlanets();
}
- (void)setDoProcedurallyTexturedPlanets:(BOOL)value
{
    _cxxUniverse->setDoProcedurallyTexturedPlanets(value);
}
- (std::optional<std::string>)cxx_useAddOns
{
    return _cxxUniverse->getUseAddOns();
}
- (BOOL)cxx_setUseAddOns:(const std::string&)newUse fromSaveGame:(BOOL)saveGame
{
    return _cxxUniverse->setUseAddOns(newUse, saveGame);
}
- (BOOL)cxx_setUseAddOns:(const std::string&)newUse fromSaveGame:(BOOL)saveGame forceReinit:(BOOL)force
{
    return _cxxUniverse->setUseAddOns(newUse, saveGame, force);
}
- (NSUInteger)entityCount
{
    return _cxxUniverse->entityCount();
}
#ifdef OO_DEBUG_MONITOR_ENABLED
- (void)debugDumpEntities
{
    _cxxUniverse->debugDumpEntities();
}
- (std::vector<oo::ObjCRef<::Entity*>>)cxx_entityList
{
    return _cxxUniverse->entityList();
}
#endif

@end

@implementation Universe (OOSlice3)

- (void)pauseGame
{
    _cxxUniverse->pauseGame();
}
- (void)quitGame
{
    _cxxUniverse->quitGame();
}
- (void)carryPlayerOn:(StationEntity*)carrier inWormhole:(WormholeEntity*)wormhole
{
    _cxxUniverse->carryPlayerOn(carrier, wormhole);
}
- (void)setUpUniverseFromStation
{
    _cxxUniverse->setUpUniverseFromStation();
}
- (void)setUpUniverseFromWitchspace
{
    _cxxUniverse->setUpUniverseFromWitchspace();
}
- (void)setUpUniverseFromMisjump
{
    _cxxUniverse->setUpUniverseFromMisjump();
}
- (void)setUpWitchspace
{
    _cxxUniverse->setUpWitchspace();
}
- (void)setUpWitchspaceBetweenSystem:(OOSystemID)s1 andSystem:(OOSystemID)s2
{
    _cxxUniverse->setUpWitchspaceBetweenSystem(s1, s2);
}
- (OOPlanetEntity*)setUpPlanet
{
    return _cxxUniverse->setUpPlanet();
}

@end

@implementation Universe (OOSlice4)

- (void)setUpSpace
{
    _cxxUniverse->setUpSpace();
}
- (void)populateNormalSpace
{
    _cxxUniverse->populateNormalSpace();
}
- (void)clearSystemPopulator
{
    _cxxUniverse->clearSystemPopulator();
}
- (oo::PList)cxx_getPopulatorSettings
{
    return _cxxUniverse->getPopulatorSettings();
}
- (void)cxx_setPopulatorSetting:(const std::string&)key to:(const oo::PList&)setting
{
    _cxxUniverse->setPopulatorSetting(key, setting);
}
- (BOOL)deterministicPopulation
{
    return _cxxUniverse->deterministicPopulation();
}
- (void)populateSystemFromDictionariesWithSun:(OOSunEntity*)sun andPlanet:(OOPlanetEntity*)planet
{
    _cxxUniverse->populateSystemFromDictionariesWithSun(sun, planet);
}

@end

@implementation Universe (OOSlice5)

- (HPVector)cxx_locationByCode:(const std::string&)code withSun:(OOSunEntity*)sun andPlanet:(OOPlanetEntity*)planet
{
    return _cxxUniverse->locationByCode(code, sun, planet);
}
- (void)setAmbientLightLevel:(float)newValue
{
    _cxxUniverse->setAmbientLightLevel(newValue);
}
- (float)ambientLightLevel
{
    return _cxxUniverse->getAmbientLightLevel();
}
- (void)setLighting
{
    _cxxUniverse->setLighting();
}
- (void)forceLightSwitch
{
    _cxxUniverse->forceLightSwitch();
}
- (void)setMainLightPosition:(Vector)sunPos
{
    _cxxUniverse->setMainLightPosition(sunPos);
}
- (ShipEntity*)addShipWithRole:(const std::string&)desc launchPos:(HPVector)launchPos rfactor:(GLfloat)rfactor
{
    return _cxxUniverse->addShipWithRole(desc, launchPos, rfactor);
}
- (void)cxx_addShipWithRole:(const std::string&)desc nearRouteOneAt:(double)route_fraction
{
    _cxxUniverse->addShipWithRole(desc, route_fraction);
}
- (HPVector)cxx_coordinatesForPosition:(HPVector)pos withCoordinateSystem:(const std::string&)system returningScalar:(GLfloat*)my_scalar
{
    return _cxxUniverse->coordinatesForPosition(pos, system, my_scalar);
}
- (std::optional<std::string>)cxx_expressPosition:(HPVector)pos inCoordinateSystem:(const std::string&)system
{
    return _cxxUniverse->expressPosition(pos, system);
}

@end

@implementation Universe (OOSlice6)

- (HPVector)cxx_legacyPositionFrom:(HPVector)pos asCoordinateSystem:(const std::string&)system
{
    return _cxxUniverse->legacyPositionFrom(pos, system);
}
- (HPVector)cxx_coordinatesFromCoordinateSystemString:(const std::string&)system_x_y_z
{
    return _cxxUniverse->coordinatesFromCoordinateSystemString(system_x_y_z);
}
- (BOOL)cxx_addShipWithRole:(const std::string&)desc nearPosition:(HPVector)pos withCoordinateSystem:(const std::string&)system
{
    return _cxxUniverse->addShipWithRole(desc, pos, system);
}
- (BOOL)cxx_addShips:(int)howMany withRole:(const std::string&)desc atPosition:(HPVector)pos withCoordinateSystem:(const std::string&)system
{
    return _cxxUniverse->addShipsAtPosition(howMany, desc, pos, system);
}
- (BOOL)cxx_addShips:(int)howMany withRole:(const std::string&)desc nearPosition:(HPVector)pos withCoordinateSystem:(const std::string&)system
{
    return _cxxUniverse->addShipsNearPosition(howMany, desc, pos, system);
}
- (BOOL)cxx_addShips:(int)howMany withRole:(const std::string&)desc nearPosition:(HPVector)pos withCoordinateSystem:(const std::string&)system withinRadius:(GLfloat)radius
{
    return _cxxUniverse->addShipsNearPosition(howMany, desc, pos, system, radius);
}
- (BOOL)cxx_addShips:(int)howMany withRole:(const std::string&)desc intoBoundingBox:(BoundingBox)bbox
{
    return _cxxUniverse->addShips(howMany, desc, bbox);
}
- (BOOL)cxx_spawnShip:(const std::string&)shipdesc
{
    return _cxxUniverse->spawnShip(shipdesc);
}
- (void)cxx_witchspaceShipWithPrimaryRole:(const std::string&)role
{
    _cxxUniverse->witchspaceShipWithPrimaryRole(role);
}
- (ShipEntity*)cxx_spawnShipWithRole:(const std::string&)desc near:(Entity*)entity
{
    return _cxxUniverse->spawnShipWithRole(desc, entity);
}
- (Entity*)cxx_addVisualEffectAt:(HPVector)pos withKey:(const std::string&)key
{
    return _cxxUniverse->addVisualEffectAt(pos, key);
}

@end

@implementation Universe (OOSlice7)

- (ShipEntity*)addShipAt:(HPVector)pos withRole:(const std::string&)role withinRadius:(GLfloat)radius
{
    return _cxxUniverse->addShipAt(pos, role, radius);
}
- (std::vector<oo::ObjCRef<::Entity*>>)cxx_addShipsAt:(HPVector)pos withRole:(const std::string&)role quantity:(unsigned)count withinRadius:(GLfloat)radius asGroup:(BOOL)isGroup
{
    return _cxxUniverse->addShipsAt(pos, role, count, radius, isGroup);
}
- (std::vector<oo::ObjCRef<::Entity*>>)cxx_addShipsToRoute:(const std::string&)route withRole:(const std::string&)role quantity:(unsigned)count routeFraction:(double)routeFraction asGroup:(BOOL)isGroup
{
    return _cxxUniverse->addShipsToRoute(route, role, count, routeFraction, isGroup);
}
- (BOOL)cxx_roleIsPirateVictim:(const std::string&)role
{
    return _cxxUniverse->roleIsPirateVictim(role);
}
- (BOOL)cxx_role:(const std::string&)role isInCategory:(const std::string&)category
{
    return _cxxUniverse->role(role, category);
}
- (void)forceWitchspaceEntries
{
    _cxxUniverse->forceWitchspaceEntries();
}
- (void)addWitchspaceJumpEffectForShip:(ShipEntity*)ship
{
    _cxxUniverse->addWitchspaceJumpEffectForShip(ship);
}
- (GLfloat)safeWitchspaceExitDistance
{
    return _cxxUniverse->safeWitchspaceExitDistance();
}
- (void)setUpBreakPattern:(HPVector)pos orientation:(Quaternion)q forDocking:(BOOL)forDocking
{
    _cxxUniverse->setUpBreakPattern(pos, q, forDocking);
}
- (BOOL)witchspaceBreakPattern
{
    return _cxxUniverse->witchspaceBreakPattern();
}
- (void)setWitchspaceBreakPattern:(BOOL)newValue
{
    _cxxUniverse->setWitchspaceBreakPattern(newValue);
}
- (BOOL)dockingClearanceProtocolActive
{
    return _cxxUniverse->dockingClearanceProtocolActive();
}
- (void)setDockingClearanceProtocolActive:(BOOL)newValue
{
    _cxxUniverse->setDockingClearanceProtocolActive(newValue);
}
- (void)handleGameOver
{
    _cxxUniverse->handleGameOver();
}

@end

@implementation Universe (OOSlice8)

- (void)setupIntroFirstGo:(BOOL)justCobra
{
    _cxxUniverse->setupIntroFirstGo(justCobra);
}
- (oo::PList)demoShipData
{
    return _cxxUniverse->demoShipData();
}
- (void)setLibraryTextForDemoShip
{
    _cxxUniverse->setLibraryTextForDemoShip();
}
- (void)selectIntro2Previous
{
    _cxxUniverse->selectIntro2Previous();
}
- (void)selectIntro2PreviousCategory
{
    _cxxUniverse->selectIntro2PreviousCategory();
}
- (void)selectIntro2NextCategory
{
    _cxxUniverse->selectIntro2NextCategory();
}
- (void)selectIntro2Next
{
    _cxxUniverse->selectIntro2Next();
}
- (StationEntity*)station
{
    return _cxxUniverse->station();
}
- (StationEntity*)cxx_stationWithRole:(const std::string&)role andPosition:(HPVector)position
{
    return _cxxUniverse->stationWithRole(role, position);
}
- (StationEntity*)stationFriendlyTo:(ShipEntity*)ship
{
    return _cxxUniverse->stationFriendlyTo(ship);
}
- (OOPlanetEntity*)planet
{
    return _cxxUniverse->planet();
}
- (OOSunEntity*)sun
{
    return _cxxUniverse->sun();
}
- (std::vector<oo::ObjCRef<::Entity*>>)cxx_planets
{
    return _cxxUniverse->planets();
}
- (std::vector<oo::ObjCRef<::Entity*>>)cxx_stations
{
    return _cxxUniverse->stations();
}

@end

@implementation Universe (OOSlice9)

- (std::vector<oo::ObjCRef<::Entity*>>)cxx_wormholes
{
    return _cxxUniverse->wormholes();
}
- (void)unMagicMainStation
{
    _cxxUniverse->unMagicMainStation();
}
- (void)resetBeacons
{
    _cxxUniverse->resetBeacons();
}
- (Entity<OOBeaconEntity>*)firstBeacon
{
    return (Entity<OOBeaconEntity>*)_cxxUniverse->firstBeacon();
}
- (void)setFirstBeacon:(Entity<OOBeaconEntity>*)beacon
{
    _cxxUniverse->setFirstBeacon(beacon);
}
- (Entity<OOBeaconEntity>*)lastBeacon
{
    return (Entity<OOBeaconEntity>*)_cxxUniverse->lastBeacon();
}
- (void)setLastBeacon:(Entity<OOBeaconEntity>*)beacon
{
    _cxxUniverse->setLastBeacon(beacon);
}
- (void)setNextBeacon:(Entity<OOBeaconEntity>*)beaconShip
{
    _cxxUniverse->setNextBeacon(beaconShip);
}
- (void)clearBeacon:(Entity<OOBeaconEntity>*)beaconShip
{
    _cxxUniverse->clearBeacon(beaconShip);
}
- (std::map<std::string, oo::ObjCRef<::Entity*>, std::less<>>)cxx_currentWaypoints
{
    return _cxxUniverse->currentWaypoints();
}
- (void)cxx_defineWaypoint:(const oo::PList&)definition forKey:(const std::string&)key
{
    _cxxUniverse->defineWaypoint(definition, key);
}
- (GLfloat*)skyClearColor
{
    return _cxxUniverse->getSkyClearColor();
}
- (void)setSkyColorRed:(GLfloat)red green:(GLfloat)green blue:(GLfloat)blue alpha:(GLfloat)alpha
{
    _cxxUniverse->setSkyColorRed(red, green, blue, alpha);
}
- (BOOL)breakPatternOver
{
    return _cxxUniverse->breakPatternOver();
}
- (BOOL)breakPatternHide
{
    return _cxxUniverse->breakPatternHide();
}
- (BOOL)canInstantiateShip:(const std::string&)shipKey
{
    return _cxxUniverse->canInstantiateShip(shipKey);
}
- (std::optional<std::string>)cxx_randomShipKeyForRoleRespectingConditions:(const std::string&)role
{
    return _cxxUniverse->randomShipKeyForRoleRespectingConditions(role);
}
- (ShipEntity*)cxx_newShipWithRole:(const std::string&)role
{
    return _cxxUniverse->newShipWithRole(role);
}
- (Entity*)cxx_newVisualEffectWithName:(const std::string&)effectKey
{
    return _cxxUniverse->newVisualEffectWithName(effectKey);
}
- (ShipEntity*)cxx_newSubentityWithName:(const std::string&)shipKey andScaleFactor:(float)scale
{
    return _cxxUniverse->newSubentityWithName(shipKey, scale);
}
- (ShipEntity*)cxx_newShipWithName:(const std::string&)shipKey usePlayerProxy:(BOOL)usePlayerProxy
{
    return _cxxUniverse->newShipWithName(shipKey, usePlayerProxy);
}
- (ShipEntity*)cxx_newShipWithName:(const std::string&)shipKey usePlayerProxy:(BOOL)usePlayerProxy isSubentity:(BOOL)isSubentity
{
    return _cxxUniverse->newShipWithName(shipKey, usePlayerProxy, isSubentity);
}
- (ShipEntity*)cxx_newShipWithName:(const std::string&)shipKey usePlayerProxy:(BOOL)usePlayerProxy isSubentity:(BOOL)isSubentity andScaleFactor:(float)scale
{
    return _cxxUniverse->newShipWithName(shipKey, usePlayerProxy, isSubentity, scale);
}
- (ShipEntity*)cxx_newDockWithName:(const std::string&)shipDataKey andScaleFactor:(float)scale
{
    return _cxxUniverse->newDockWithName(shipDataKey, scale);
}
- (ShipEntity*)cxx_newShipWithName:(const std::string&)shipKey
{
    return _cxxUniverse->newShipWithName(shipKey);
}
- (BOOL)cxx_isStationShipDictionary:(const oo::PList&)dict
{
    return _cxxUniverse->isStationShipDictionary(dict);
}
- (std::optional<std::string>)defaultAIForRole:(const std::string&)role
{
    return _cxxUniverse->defaultAIForRole(role);
}
- (OOCargoQuantity)cxx_maxCargoForShip:(const std::string&)desc
{
    return _cxxUniverse->maxCargoForShip(desc);
}

@end

@implementation Universe (OOSlice10)

- (OOCreditsQuantity)cxx_getEquipmentPriceForKey:(const std::string&)eq_key
{
    return _cxxUniverse->getEquipmentPriceForKey(eq_key);
}
- (OOCommodities*)commodities
{
    return _cxxUniverse->getCommodities();
}
- (ShipEntity*)reifyCargoPod:(ShipEntity*)cargoObj
{
    return _cxxUniverse->reifyCargoPod(cargoObj);
}
- (ShipEntity*)cargoPodFromTemplate:(ShipEntity*)cargoObj
{
    return _cxxUniverse->cargoPodFromTemplate(cargoObj);
}
- (std::vector<oo::ObjCRef<::Entity*>>)cxx_getContainersOfGoods:(OOCargoQuantity)how_many scarce:(BOOL)scarce legal:(BOOL)legal
{
    return _cxxUniverse->getContainersOfGoods(how_many, scarce, legal);
}
- (std::vector<oo::ObjCRef<::Entity*>>)cxx_getContainersOfCommodity:(const std::string&)commodity_name /* unnamed second part */ :(OOCargoQuantity)how_much
{
    return _cxxUniverse->getContainersOfCommodity(commodity_name, how_much);
}
- (void)fillCargopodWithRandomCargo:(ShipEntity*)cargopod
{
    _cxxUniverse->fillCargopodWithRandomCargo(cargopod);
}
- (std::string)getRandomCommodity
{
    return _cxxUniverse->getRandomCommodity();
}
- (OOCargoQuantity)cxx_getRandomAmountOfCommodity:(const std::string&)co_type
{
    return _cxxUniverse->getRandomAmountOfCommodity(co_type);
}
- (oo::PList)commodityDataForType:(const std::string&)type
{
    return _cxxUniverse->commodityDataForType(type);
}
- (std::optional<std::string>)cxx_displayNameForCommodity:(const std::string&)co_type
{
    return _cxxUniverse->displayNameForCommodity(co_type);
}
- (std::optional<std::string>)cxx_describeCommodity:(const std::string&)co_type amount:(OOCargoQuantity)co_amount
{
    return _cxxUniverse->describeCommodity(co_type, co_amount);
}
- (void)setGameView:(MyOpenGLView*)view
{
    _cxxUniverse->setGameView(view);
}
- (MyOpenGLView*)gameView
{
    return _cxxUniverse->getGameView();
}
- (GameController*)gameController
{
    return _cxxUniverse->gameController();
}
- (oo::PList)cxx_gameSettings
{
    return _cxxUniverse->gameSettings();
}
- (void)useGUILightSource:(BOOL)GUILight
{
    _cxxUniverse->useGUILightSource(GUILight);
}
- (void)lightForEntity:(BOOL)isLit
{
    _cxxUniverse->lightForEntity(isLit);
}
- (void)getActiveViewMatrix:(OOMatrix*)outMatrix forwardVector:(Vector*)outForward upVector:(Vector*)outUp
{
    _cxxUniverse->getActiveViewMatrix(outMatrix, outForward, outUp);
}
- (OOMatrix)activeViewMatrix
{
    return _cxxUniverse->activeViewMatrix();
}

@end

@implementation Universe (OOSlice11)

- (void)defineFrustum
{
    _cxxUniverse->defineFrustum();
}
- (BOOL)viewFrustumIntersectsSphereAt:(Vector)position withRadius:(GLfloat)radius
{
    return _cxxUniverse->viewFrustumIntersectsSphereAt(position, radius);
}

@end

@implementation Universe (OOSlice12)

- (void)drawUniverse
{
    _cxxUniverse->drawUniverse();
}
- (void)prepareToRenderIntoDefaultFramebuffer
{
    _cxxUniverse->prepareToRenderIntoDefaultFramebuffer();
}
- (int)framesDoneThisUpdate
{
    return _cxxUniverse->getFramesDoneThisUpdate();
}
- (void)resetFramesDoneThisUpdate
{
    _cxxUniverse->resetFramesDoneThisUpdate();
}
- (OOMatrix)viewMatrix
{
    return _cxxUniverse->getViewMatrix();
}

@end

@implementation Universe (OOSlice13)

- (void)drawMessage
{
    _cxxUniverse->drawMessage();
}
- (void)drawWatermarkString:(const std::string&)watermarkString
{
    _cxxUniverse->drawWatermarkString(watermarkString);
}
- (id)entityForUniversalID:(OOUniversalID)u_id
{
    return _cxxUniverse->entityForUniversalID(u_id);
}
- (BOOL)addEntity:(Entity*)entity
{
    return _cxxUniverse->addEntity(entity);
}
- (BOOL)removeEntity:(Entity*)entity
{
    return _cxxUniverse->removeEntity(entity);
}
- (void)ensureEntityReallyRemoved:(Entity*)entity
{
    _cxxUniverse->ensureEntityReallyRemoved(entity);
}
- (void)removeAllEntitiesExceptPlayer
{
    _cxxUniverse->removeAllEntitiesExceptPlayer();
}
- (void)removeDemoShips
{
    _cxxUniverse->removeDemoShips();
}

@end

@implementation Universe (OOSlice14)

- (ShipEntity*)cxx_makeDemoShipWithRole:(const std::string&)role spinning:(BOOL)spinning
{
    return _cxxUniverse->makeDemoShipWithRole(role, spinning);
}
- (BOOL)isVectorClearFromEntity:(Entity*)e1 toDistance:(double)dist fromPoint:(HPVector)p2
{
    return _cxxUniverse->isVectorClearFromEntity(e1, dist, p2);
}
- (Entity*)hazardOnRouteFromEntity:(Entity*)e1 toDistance:(double)dist fromPoint:(HPVector)p2
{
    return _cxxUniverse->hazardOnRouteFromEntity(e1, dist, p2);
}
- (HPVector)getSafeVectorFromEntity:(Entity*)e1 toDistance:(double)dist fromPoint:(HPVector)p2
{
    return _cxxUniverse->getSafeVectorFromEntity(e1, dist, p2);
}
- (ShipEntity*)cxx_addWreckageFrom:(ShipEntity*)ship withRole:(const std::string&)wreckRole at:(HPVector)rpos scale:(GLfloat)scale lifetime:(GLfloat)lifetime
{
    return _cxxUniverse->addWreckageFrom(ship, wreckRole, rpos, scale, lifetime);
}
- (void)addLaserHitEffectsAt:(HPVector)pos against:(ShipEntity*)target damage:(float)damage color:(OOColor*)color
{
    _cxxUniverse->addLaserHitEffectsAt(pos, target, damage, color);
}
- (ShipEntity*)firstShipHitByLaserFromShip:(ShipEntity*)srcEntity inDirection:(OOWeaponFacing)direction offset:(Vector)offset gettingRangeFound:(GLfloat*)range_ptr
{
    return _cxxUniverse->firstShipHitByLaserFromShip(srcEntity, direction, offset, range_ptr);
}

@end

@implementation Universe (OOSlice15)

- (Entity*)firstEntityTargetedByPlayer
{
    return _cxxUniverse->firstEntityTargetedByPlayer();
}
- (Entity*)firstEntityTargetedByPlayerPrecisely
{
    return _cxxUniverse->firstEntityTargetedByPlayerPrecisely();
}
- (std::vector<oo::ObjCRef<::Entity*>>)cxx_entitiesWithinRange:(double)range ofEntity:(Entity*)entity
{
    return _cxxUniverse->entitiesWithinRange(range, entity);
}
- (unsigned)cxx_countShipsWithRole:(const std::string&)role inRange:(double)range ofEntity:(Entity*)entity
{
    return _cxxUniverse->countShipsWithRole(role, range, entity);
}
- (unsigned)cxx_countShipsWithRole:(const std::string&)role
{
    return _cxxUniverse->countShipsWithRole(role);
}
- (unsigned)cxx_countShipsWithPrimaryRole:(const std::string&)role inRange:(double)range ofEntity:(Entity*)entity
{
    return _cxxUniverse->countShipsWithPrimaryRole(role, range, entity);
}
- (unsigned)countShipsWithScanClass:(OOScanClass)scanClass inRange:(double)range ofEntity:(Entity*)entity
{
    return _cxxUniverse->countShipsWithScanClass(scanClass, range, entity);
}
- (unsigned)cxx_countShipsWithPrimaryRole:(const std::string&)role
{
    return _cxxUniverse->countShipsWithPrimaryRole(role);
}
- (unsigned)countEntitiesMatchingPredicate:(EntityFilterPredicate)predicate parameter:(void*)parameter inRange:(double)range ofEntity:(Entity*)e1
{
    return _cxxUniverse->countEntitiesMatchingPredicate(predicate, parameter, range, e1);
}
- (unsigned)countShipsMatchingPredicate:(EntityFilterPredicate)predicate parameter:(void*)parameter inRange:(double)range ofEntity:(Entity*)entity
{
    return _cxxUniverse->countShipsMatchingPredicate(predicate, parameter, range, entity);
}
- (std::vector<oo::ObjCRef<::Entity*>>)cxx_findEntitiesMatchingPredicate:(EntityFilterPredicate)predicate parameter:(void*)parameter inRange:(double)range ofEntity:(Entity*)e1
{
    return _cxxUniverse->findEntitiesMatchingPredicate(predicate, parameter, range, e1);
}
- (id)findOneEntityMatchingPredicate:(EntityFilterPredicate)predicate parameter:(void*)parameter
{
    return _cxxUniverse->findOneEntityMatchingPredicate(predicate, parameter);
}
- (std::vector<oo::ObjCRef<::Entity*>>)cxx_findShipsMatchingPredicate:(EntityFilterPredicate)predicate parameter:(void*)parameter inRange:(double)range ofEntity:(Entity*)entity
{
    return _cxxUniverse->findShipsMatchingPredicate(predicate, parameter, range, entity);
}
- (std::vector<oo::ObjCRef<::Entity*>>)cxx_findVisualEffectsMatchingPredicate:(EntityFilterPredicate)predicate parameter:(void*)parameter inRange:(double)range ofEntity:(Entity*)entity
{
    return _cxxUniverse->findVisualEffectsMatchingPredicate(predicate, parameter, range, entity);
}
- (id)nearestEntityMatchingPredicate:(EntityFilterPredicate)predicate parameter:(void*)parameter relativeToEntity:(Entity*)entity
{
    return _cxxUniverse->nearestEntityMatchingPredicate(predicate, parameter, entity);
}
- (id)nearestShipMatchingPredicate:(EntityFilterPredicate)predicate parameter:(void*)parameter relativeToEntity:(Entity*)entity
{
    return _cxxUniverse->nearestShipMatchingPredicate(predicate, parameter, entity);
}
- (OOTimeAbsolute)getTime
{
    return _cxxUniverse->getTime();
}
- (OOTimeDelta)getTimeDelta
{
    return _cxxUniverse->getTimeDelta();
}
- (void)findCollisionsAndShadows
{
    _cxxUniverse->findCollisionsAndShadows();
}
- (std::string)collisionDescription
{
    return _cxxUniverse->collisionDescription();
}
- (void)dumpCollisions
{
    _cxxUniverse->dumpCollisions();
}
- (OOViewID)viewDirection
{
    return _cxxUniverse->getViewDirection();
}

@end

@implementation Universe (OOSlice16)

- (void)setViewDirection:(OOViewID)vd
{
    _cxxUniverse->setViewDirection(vd);
}
- (void)enterGUIViewModeWithMouseInteraction:(BOOL)mouseInteraction
{
    _cxxUniverse->enterGUIViewModeWithMouseInteraction(mouseInteraction);
}
- (std::optional<std::string>)soundNameForCustomSoundKey:(const std::string&)soundKey
{
    return _cxxUniverse->soundNameForCustomSoundKey(soundKey);
}
- (oo::PList)cxx_screenTextureDescriptorForKey:(const std::string&)key
{
    return _cxxUniverse->screenTextureDescriptorForKey(key);
}
- (void)cxx_setScreenTextureDescriptorForKey:(const std::string&)key descriptor:(const oo::PList&)desc
{
    _cxxUniverse->setScreenTextureDescriptorForKey(key, desc);
}
- (void)clearPreviousMessage
{
    _cxxUniverse->clearPreviousMessage();
}
- (void)setMessageGuiBackgroundColor:(OOColor*)some_color
{
    _cxxUniverse->setMessageGuiBackgroundColor(some_color);
}
- (void)cxx_displayMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count
{
    _cxxUniverse->displayMessage(text, count);
}
- (void)cxx_displayCountdownMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count
{
    _cxxUniverse->displayCountdownMessage(text, count);
}
- (void)cxx_addDelayedMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count afterDelay:(double)delay
{
    _cxxUniverse->addDelayedMessage(text, count, delay);
}
- (void)addDelayedMessage:(OOUniverseDelayedMessage*)holder
{
    _cxxUniverse->addDelayedMessage(holder);
}
- (void)cxx_addMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count
{
    _cxxUniverse->addMessage(text, count);
}
- (void)speakWithSubstitutions:(const std::optional<std::string>&)text
{
    _cxxUniverse->speakWithSubstitutions(text);
}
- (void)cxx_addMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count forceDisplay:(BOOL)forceDisplay
{
    _cxxUniverse->addMessage(text, count, forceDisplay);
}
- (void)cxx_addCommsMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count
{
    _cxxUniverse->addCommsMessage(text, count);
}
- (void)cxx_addCommsMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count andShowComms:(BOOL)showComms logOnly:(BOOL)logOnly
{
    _cxxUniverse->addCommsMessage(text, count, showComms, logOnly);
}
- (void)showCommsLog:(OOTimeDelta)how_long
{
    _cxxUniverse->showCommsLog(how_long);
}
- (void)showGUIMessage:(const std::optional<std::string>&)text withScroll:(BOOL)scroll andColor:(OOColor*)selectedColor overDuration:(OOTimeDelta)how_long
{
    _cxxUniverse->showGUIMessage(text, scroll, selectedColor, how_long);
}
- (void)repopulateSystem
{
    _cxxUniverse->repopulateSystem();
}

@end

@implementation Universe (OOSlice17)

- (double)timeAccelerationFactor
{
    return _cxxUniverse->getTimeAccelerationFactor();
}
- (void)setTimeAccelerationFactor:(double)newTimeAccelerationFactor
{
    _cxxUniverse->setTimeAccelerationFactor(newTimeAccelerationFactor);
}
- (void)update:(OOTimeDelta)inDeltaT
{
    _cxxUniverse->update(inDeltaT);
}
- (BOOL)ECMVisualFXEnabled
{
    return _cxxUniverse->getECMVisualFXEnabled();
}
- (void)setECMVisualFXEnabled:(BOOL)isEnabled
{
    _cxxUniverse->setECMVisualFXEnabled(isEnabled);
}

@end

@implementation Universe (OOSlice18)

- (void)filterSortedLists
{
    _cxxUniverse->filterSortedLists();
}
- (void)setGalaxyTo:(OOGalaxyID)g
{
    _cxxUniverse->setGalaxyTo(g);
}

@end

@implementation Universe (OOSlice19)

- (void)setGalaxyTo:(OOGalaxyID)g andReinit:(BOOL)forced
{
    _cxxUniverse->setGalaxyTo(g, forced);
}
- (void)setSystemTo:(OOSystemID)s
{
    _cxxUniverse->setSystemTo(s);
}
- (OOSystemID)currentSystemID
{
    return _cxxUniverse->currentSystemID();
}
- (const oo::PList*)cxx_descriptions
{
    return _cxxUniverse->descriptions();
}
- (unsigned)cxx_descriptionsGeneration
{
    return _cxxUniverse->descriptionsGeneration();
}
- (void)verifyDescriptions
{
    _cxxUniverse->verifyDescriptions();
}
- (void)loadDescriptions
{
    _cxxUniverse->loadDescriptions();
}
- (oo::PList)cxx_explosionSetting:(const std::string&)explosion
{
    return _cxxUniverse->explosionSetting(explosion);
}
- (oo::PList)cxx_scenarios
{
    return _cxxUniverse->scenarios();
}
- (void)loadScenarios
{
    _cxxUniverse->loadScenarios();
}
- (oo::PList)cxx_characters
{
    return _cxxUniverse->getCharacters();
}
- (oo::PList)cxx_missiontext
{
    return _cxxUniverse->getMissiontext();
}
- (std::optional<std::string>)cxx_descriptionForKey:(const std::string&)key
{
    return _cxxUniverse->descriptionForKey(key);
}
- (std::optional<std::string>)cxx_descriptionForArrayKey:(const std::string&)key index:(unsigned)index
{
    return _cxxUniverse->descriptionForArrayKey(key, index);
}
- (BOOL)descriptionBooleanForKey:(const std::string&)key
{
    return _cxxUniverse->descriptionBooleanForKey(key);
}
- (OOSystemDescriptionManager*)systemManager
{
    return _cxxUniverse->getSystemManager();
}
- (std::optional<std::string>)cxx_keyForPlanetOverridesForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g
{
    return _cxxUniverse->keyForPlanetOverridesForSystem(s, g);
}
- (std::optional<std::string>)keyForInterstellarOverridesForSystems:(OOSystemID)s1 s2:(OOSystemID)s2 inGalaxy:(OOGalaxyID)g
{
    return _cxxUniverse->keyForInterstellarOverridesForSystems(s1, s2, g);
}
- (oo::PList)cxx_generateSystemData:(OOSystemID)s
{
    return _cxxUniverse->generateSystemData(s);
}
- (oo::PList)cxx_generateSystemData:(OOSystemID)s useCache:(BOOL)useCache
{
    return _cxxUniverse->generateSystemData(s, useCache);
}
- (oo::PList)cxx_currentSystemData
{
    return _cxxUniverse->currentSystemData();
}
- (BOOL)inInterstellarSpace
{
    return _cxxUniverse->inInterstellarSpace();
}
- (void)cxx_setSystemDataKey:(const std::string&)key value:(const oo::PList&)value fromManifest:(const std::optional<std::string>&)manifest
{
    _cxxUniverse->setSystemDataKey(key, value, manifest);
}
- (void)cxx_setSystemDataForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum key:(const std::string&)key value:(const oo::PList&)value fromManifest:(const std::optional<std::string>&)manifest forLayer:(OOSystemLayer)layer
{
    _cxxUniverse->setSystemDataForGalaxy(gnum, pnum, key, value, manifest, layer);
}
- (oo::PList)generateSystemDataForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum
{
    return _cxxUniverse->generateSystemDataForGalaxy(gnum, pnum);
}
- (std::vector<std::string>)cxx_systemDataKeysForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum
{
    return _cxxUniverse->systemDataKeysForGalaxy(gnum, pnum);
}
- (oo::PList)cxx_systemDataForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum key:(const std::string&)key
{
    return _cxxUniverse->systemDataForGalaxy(gnum, pnum, key);
}
- (std::optional<std::string>)cxx_getSystemName:(OOSystemID)sys
{
    return _cxxUniverse->getSystemName(sys);
}
- (std::optional<std::string>)cxx_getSystemName:(OOSystemID)sys forGalaxy:(OOGalaxyID)gnum
{
    return _cxxUniverse->getSystemName(sys, gnum);
}
- (OOGovernmentID)getSystemGovernment:(OOSystemID)sys
{
    return _cxxUniverse->getSystemGovernment(sys);
}
- (std::optional<std::string>)cxx_getSystemInhabitants:(OOSystemID)sys
{
    return _cxxUniverse->getSystemInhabitants(sys);
}
- (std::optional<std::string>)cxx_getSystemInhabitants:(OOSystemID)sys plural:(BOOL)plural
{
    return _cxxUniverse->getSystemInhabitants(sys, plural);
}
- (NSPoint)coordinatesForSystem:(OOSystemID)s
{
    return _cxxUniverse->coordinatesForSystem(s);
}
- (OOSystemID)cxx_findSystemFromName:(const std::string&)sysName
{
    return _cxxUniverse->findSystemFromName(sysName);
}
- (OOSystemID)findSystemAtCoords:(NSPoint)coords withGalaxy:(OOGalaxyID)g
{
    return _cxxUniverse->findSystemAtCoords(coords, g);
}

@end

@implementation Universe (OOSlice20)

- (oo::PList)cxx_nearbyDestinationsWithinRange:(double)range
{
    return _cxxUniverse->nearbyDestinationsWithinRange(range);
}
- (OOSystemID)findNeighbouringSystemToCoords:(NSPoint)coords withGalaxy:(OOGalaxyID)g
{
    return _cxxUniverse->findNeighbouringSystemToCoords(coords, g);
}
- (OOSystemID)findConnectedSystemAtCoords:(NSPoint)coords withGalaxy:(OOGalaxyID)g
{
    return _cxxUniverse->findConnectedSystemAtCoords(coords, g);
}
- (OOSystemID)findSystemNumberAtCoords:(NSPoint)coords withGalaxy:(OOGalaxyID)g includingHidden:(BOOL)hidden
{
    return _cxxUniverse->findSystemNumberAtCoords(coords, g, hidden);
}
- (NSPoint)cxx_findSystemCoordinatesWithPrefix:(const std::string&)p_fix
{
    return _cxxUniverse->findSystemCoordinatesWithPrefix(p_fix);
}
- (NSPoint)cxx_findSystemCoordinatesWithPrefix:(const std::string&)p_fix exactMatch:(BOOL)exactMatch
{
    return _cxxUniverse->findSystemCoordinatesWithPrefix(p_fix, exactMatch);
}
- (BOOL*)systemsFound
{
    return _cxxUniverse->systemsFound();
}
- (std::optional<std::string>)cxx_systemNameIndex:(OOSystemID)index
{
    return _cxxUniverse->systemNameIndex(index);
}
- (oo::PList)cxx_routeFromSystem:(OOSystemID)start toSystem:(OOSystemID)goal optimizedBy:(OORouteType)optimizeBy
{
    return _cxxUniverse->routeFromSystem(start, goal, optimizeBy);
}
- (std::vector<OOSystemID>)neighboursToSystem:(OOSystemID)s
{
    return _cxxUniverse->neighboursToSystem(s);
}
- (void)preloadPlanetTexturesForSystem:(OOSystemID)s
{
    _cxxUniverse->preloadPlanetTexturesForSystem(s);
}
- (oo::PList)cxx_globalSettings
{
    return _cxxUniverse->getGlobalSettings();
}
- (oo::PList)cxx_equipmentData
{
    return _cxxUniverse->getEquipmentData();
}
- (oo::PList)cxx_equipmentDataOutfitting
{
    return _cxxUniverse->getEquipmentDataOutfitting();
}
- (OOCommodityMarket*)commodityMarket
{
    return _cxxUniverse->getCommodityMarket();
}
- (std::optional<std::string>)timeDescription:(double)interval
{
    return _cxxUniverse->timeDescription(interval);
}

@end

@implementation Universe (OOSlice21)

- (std::optional<std::string>)cxx_shortTimeDescription:(double)interval
{
    return _cxxUniverse->shortTimeDescription(interval);
}
- (void)makeSunSkimmer:(ShipEntity*)ship andSetAI:(BOOL)setAI
{
    _cxxUniverse->makeSunSkimmer(ship, setAI);
}
- (Random_Seed)marketSeed
{
    return _cxxUniverse->marketSeed();
}
- (void)cxx_loadStationMarkets:(const oo::PList&)marketData
{
    _cxxUniverse->loadStationMarkets(marketData);
}
- (oo::PList)cxx_getStationMarkets
{
    return _cxxUniverse->getStationMarkets();
}

@end

@implementation Universe (OOSlice22)

- (oo::PList)cxx_shipsForSaleForSystem:(OOSystemID)s withTL:(OOTechLevelID)specialTL atTime:(OOTimeAbsolute)current_time
{
    return _cxxUniverse->shipsForSaleForSystem(s, specialTL, current_time);
}

@end

@implementation Universe (OOSlice23)

- (OOCreditsQuantity)cxx_tradeInValueForCommanderDictionary:(const oo::PList&)dict
{
    return _cxxUniverse->tradeInValueForCommanderDictionary(dict);
}
- (std::optional<std::string>)brochureDescriptionWithDictionary:(const oo::PList&)dict standardEquipment:(const std::vector<std::string>&)extras optionalEquipment:(const std::vector<std::string>&)options
{
    return _cxxUniverse->brochureDescriptionWithDictionary(dict, extras, options);
}
- (HPVector)getWitchspaceExitPosition
{
    return _cxxUniverse->getWitchspaceExitPosition();
}
- (Quaternion)getWitchspaceExitRotation
{
    return _cxxUniverse->getWitchspaceExitRotation();
}
- (HPVector)getSunSkimStartPositionForShip:(ShipEntity*)ship
{
    return _cxxUniverse->getSunSkimStartPositionForShip(ship);
}
- (HPVector)getSunSkimEndPositionForShip:(ShipEntity*)ship
{
    return _cxxUniverse->getSunSkimEndPositionForShip(ship);
}
- (std::vector<oo::ObjCRef<Entity<OOBeaconEntity>*>>)cxx_listBeaconsWithCode:(const std::string&)code
{
    return _cxxUniverse->listBeaconsWithCode(code);
}
- (void)cxx_allShipsDoScriptEvent:(OOJSPropID)event andReactToAIMessage:(const std::optional<std::string>&)message
{
    _cxxUniverse->allShipsDoScriptEvent(event, message);
}
- (GuiDisplayGen*)gui
{
    return _cxxUniverse->getGui();
}
- (GuiDisplayGen*)commLogGUI
{
    return _cxxUniverse->commLogGUI();
}
- (GuiDisplayGen*)messageGUI
{
    return _cxxUniverse->messageGUI();
}
- (void)clearGUIs
{
    _cxxUniverse->clearGUIs();
}
- (void)resetCommsLogColor
{
    _cxxUniverse->resetCommsLogColor();
}
- (void)setDisplayText:(BOOL)value
{
    _cxxUniverse->setDisplayText(value);
}
- (BOOL)displayGUI
{
    return _cxxUniverse->getDisplayGUI();
}
- (void)setDisplayFPS:(BOOL)value
{
    _cxxUniverse->setDisplayFPS(value);
}
- (BOOL)displayFPS
{
    return _cxxUniverse->getDisplayFPS();
}
- (void)setAutoSave:(BOOL)value
{
    _cxxUniverse->setAutoSave(value);
}
- (BOOL)autoSave
{
    return _cxxUniverse->getAutoSave();
}
- (void)setAutoSaveNow:(BOOL)value
{
    _cxxUniverse->setAutoSaveNow(value);
}

@end

@implementation Universe (OOSlice24)

#if !OOLITE_MAC_OS_X
- (void)cxx_startSpeakingString:(const std::string&)text
{
    _cxxUniverse->startSpeakingString(text);
}
- (void)stopSpeaking
{
    _cxxUniverse->stopSpeaking();
}
- (BOOL)isSpeaking
{
    return _cxxUniverse->isSpeaking();
}
#endif
#if OOLITE_ESPEAK
- (std::optional<std::string>)cxx_voiceName:(unsigned int)index
{
    return _cxxUniverse->voiceName(index);
}
- (unsigned int)cxx_voiceNumber:(const std::string&)name
{
    return _cxxUniverse->voiceNumber(name);
}
- (unsigned int)nextVoice:(unsigned int)index
{
    return _cxxUniverse->nextVoice(index);
}
- (unsigned int)prevVoice:(unsigned int)index
{
    return _cxxUniverse->prevVoice(index);
}
- (unsigned int)setVoice:(unsigned int)index withGenderM:(BOOL)isMale
{
    return _cxxUniverse->setVoice(index, isMale);
}
#endif
- (BOOL)autoSaveNow
{
    return _cxxUniverse->getAutoSaveNow();
}
- (void)setWireframeGraphics:(BOOL)value
{
    _cxxUniverse->setWireframeGraphics(value);
}
- (BOOL)wireframeGraphics
{
    return _cxxUniverse->getWireframeGraphics();
}
- (BOOL)reducedDetail
{
    return _cxxUniverse->reducedDetail();
}
- (void)setDetailLevelDirectly:(OOGraphicsDetail)value
{
    _cxxUniverse->setDetailLevelDirectly(value);
}
- (void)setDetailLevel:(OOGraphicsDetail)value
{
    _cxxUniverse->setDetailLevel(value);
}
- (OOGraphicsDetail)detailLevel
{
    return _cxxUniverse->getDetailLevel();
}
- (BOOL)useShaders
{
    return _cxxUniverse->useShaders();
}
- (void)handleOoliteException:(OOException*)exception
{
    _cxxUniverse->handleOoliteException(exception);
}
- (GLfloat)airResistanceFactor
{
    return _cxxUniverse->getAirResistanceFactor();
}
- (void)setAirResistanceFactor:(GLfloat)newFactor
{
    _cxxUniverse->setAirResistanceFactor(newFactor);
}
- (BOOL)pauseMessageVisible
{
    return _cxxUniverse->pauseMessageVisible();
}
- (void)setPauseMessageVisible:(BOOL)value
{
    _cxxUniverse->setPauseMessageVisible(value);
}
- (BOOL)permanentMessageLog
{
    return _cxxUniverse->permanentMessageLog();
}
- (void)setPermanentMessageLog:(BOOL)value
{
    _cxxUniverse->setPermanentMessageLog(value);
}
- (BOOL)autoMessageLogBg
{
    return _cxxUniverse->autoMessageLogBg();
}
- (void)setAutoMessageLogBg:(BOOL)value
{
    _cxxUniverse->setAutoMessageLogBg(value);
}
- (BOOL)permanentCommLog
{
    return _cxxUniverse->permanentCommLog();
}
- (void)setPermanentCommLog:(BOOL)value
{
    _cxxUniverse->setPermanentCommLog(value);
}
- (void)setAutoCommLog:(BOOL)value
{
    _cxxUniverse->setAutoCommLog(value);
}
- (BOOL)blockJSPlayerShipProps
{
    return _cxxUniverse->blockJSPlayerShipProps();
}
- (void)setBlockJSPlayerShipProps:(BOOL)value
{
    _cxxUniverse->setBlockJSPlayerShipProps(value);
}
- (void)setUpSettings
{
    _cxxUniverse->setUpSettings();
}
- (void)setUpCargoPods
{
    _cxxUniverse->setUpCargoPods();
}
- (void)verifyEntitySessionIDs
{
    _cxxUniverse->verifyEntitySessionIDs();
}

@end

@implementation Universe (OOSlice25)

- (BOOL)reinitAndShowDemo:(BOOL)showDemo
{
    return _cxxUniverse->reinitAndShowDemo(showDemo);
}
- (void)setUpInitialUniverse
{
    _cxxUniverse->setUpInitialUniverse();
}
- (float)randomDistanceWithinScanner
{
    return _cxxUniverse->randomDistanceWithinScanner();
}
- (Vector)randomPlaceWithinScannerFrom:(Vector)pos alongRoute:(Vector)route withOffset:(double)offset
{
    return _cxxUniverse->randomPlaceWithinScannerFrom(pos, route, offset);
}
- (HPVector)fractionalPositionFrom:(HPVector)point0 to:(HPVector)point1 withFraction:(double)routeFraction
{
    return _cxxUniverse->fractionalPositionFrom(point0, point1, routeFraction);
}
- (BOOL)doRemoveEntity:(Entity*)entity
{
    return _cxxUniverse->doRemoveEntity(entity);
}
- (void)preloadSounds
{
    _cxxUniverse->preloadSounds();
}
- (void)populateSpaceFromActiveWormholes
{
    _cxxUniverse->populateSpaceFromActiveWormholes();
}
- (std::optional<std::string>)chooseStringForKey:(const std::string&)key inDictionary:(const oo::PList&)dictionary
{
    return _cxxUniverse->chooseStringForKey(key, dictionary);
}
#if OO_LOCALIZATION_TOOLS && DEBUG_GRAPHVIZ
- (void)dumpDebugGraphViz
{
    _cxxUniverse->dumpDebugGraphViz();
}
- (void)dumpSystemDescriptionGraphViz
{
    _cxxUniverse->dumpSystemDescriptionGraphViz();
}
#endif

@end

@implementation Universe (OOSlice26)

#if OO_LOCALIZATION_TOOLS
- (void)addNumericRefsInString:(const std::string&)string toGraphViz:(std::string&)graphViz fromNode:(const std::string&)fromNode nodeCount:(NSUInteger)nodeCount
{
    _cxxUniverse->addNumericRefsInString(string, graphViz, fromNode, nodeCount);
}
- (void)runLocalizationTools
{
    _cxxUniverse->runLocalizationTools();
}
#endif
- (void)prunePreloadingPlanetMaterials
{
    _cxxUniverse->prunePreloadingPlanetMaterials();
}
- (void)loadConditionScripts
{
    _cxxUniverse->loadConditionScripts();
}
- (void)addConditionScripts:(const std::vector<std::string>&)scripts
{
    _cxxUniverse->addConditionScripts(scripts);
}
- (OOScript*)cxx_getConditionScript:(const std::string&)scriptname
{
    return _cxxUniverse->getConditionScript(scriptname);
}

@end

// The look-ups' messages to UNIVERSE (Universe+ObjCBridge.h).
std::optional<std::string> OOUniverseDescriptionForKey(const std::string& key) { return UNIVERSE != nil ? [UNIVERSE cxx_descriptionForKey:key] : std::nullopt; } // nil: a C++ result from a nil receiver is garbage
const oo::PList* OOUniverseDescriptions() { return [UNIVERSE cxx_descriptions]; }
std::optional<std::string> OOUniverseSoundNameForCustomSoundKey(const std::string& key) { return UNIVERSE != nil ? [UNIVERSE soundNameForCustomSoundKey:key] : std::nullopt; }
