/*

Universe+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendment oo-riqmz): the Objective-C Universe, the facade over
the C++ cxx::Universe (Universe.h) while the class converts slice by slice
(docs/phases/3-slices/Universe.md). It is the game's universe object, gSharedUniverse, which about
150 files message through UNIVERSE. Its interface is the one Universe.h declared before slice 1,
copied exactly (same selectors, same types, same superclass); only -initWithGameView: moved, to the
category that implements it beside -dealloc in Universe+ObjCBridge.mm. Its methods keep their
Objective-C bodies in Universe.mm until their slice moves them to cxx::Universe and leaves a
forwarder here.

It has one ivar, _cxxUniverse: the C++ part, which it owns and makes in -initWithGameView:.
Unconverted code reads the universe's state through it by the old names: _cxxUniverse->entities in
the facade's methods, UNIVERSE->_cxxUniverse->n_entities from another class (amendments oo-bj8
item 2 and oo-60fwo item 1). When that code converts, deleting "_cxxUniverse->" gives its body
back verbatim.

        a caller that is                       holds / passes                       crosses with
        -------------------------------------  -----------------------------------  ------------------------
        still Objective-C                      Universe * (UNIVERSE)                (nothing)
        converted (C++)                        cxx::Universe *, borrowed            oo::ToObjC(universe)

Imported as the last line of Universe.h; do not import it directly. Never add to this file except
a forwarder. Deleted, with namespace cxx in Universe.h, by its deletion bead once every slice and
every caller is C++.

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

#ifndef UNIVERSE_OBJCBRIDGE_H
#define UNIVERSE_OBJCBRIDGE_H

@interface Universe : OOWeakRefObject {
@public
    oo::Ref<cxx::Universe> _cxxUniverse; // the universe's state; owned, made by -initWithGameView:
}

// find a valid station in interstellar space

///////////////////////////////////////

///////////////////////////////////////

// speech routines: the Mac arms, still the @implementation's (the others are slice 24's)
#if OOLITE_MAC_COCOA_UI
- (void)cxx_startSpeakingString:(const std::string&)text;
- (void)stopSpeaking;
- (BOOL)isSpeaking;
#endif
//
////

@end

// Implemented by the facade's category in Universe+ObjCBridge.mm with -dealloc: they need the
// Objective-C object as self (amendments oo-bj8 items 6 and 7, oo-60fwo item 6).
@interface Universe (OOObjCBridge)

- (id)initWithGameView:(MyOpenGLView*)gameView;

@end

// Slice 3 of docs/phases/3-slices/Universe.md: members of cxx::Universe, forwarded by the
// category of the same name in Universe+ObjCBridge.mm (the class's @implementation, still in
// Universe.mm, stays complete).
@interface Universe (OOSlice3)

- (void)pauseGame;
- (void)quitGame;
- (void)carryPlayerOn:(StationEntity*)carrier inWormhole:(WormholeEntity*)wormhole;
- (void)setUpUniverseFromStation;
- (void)setUpUniverseFromWitchspace;
- (void)setUpUniverseFromMisjump;
- (void)setUpWitchspace;
- (void)setUpWitchspaceBetweenSystem:(OOSystemID)s1 andSystem:(OOSystemID)s2;
- (OOPlanetEntity*)setUpPlanet;

@end

// Slice 4 of docs/phases/3-slices/Universe.md: members of cxx::Universe, forwarded by the
// category of the same name in Universe+ObjCBridge.mm (the class's @implementation, still in
// Universe.mm, stays complete).
@interface Universe (OOSlice4)

- (void)setUpSpace;
- (void)populateNormalSpace;
- (void)clearSystemPopulator;
- (oo::PList)cxx_getPopulatorSettings; // a copy
- (void)cxx_setPopulatorSetting:(const std::string&)key to:(const oo::PList&)setting; // a null setting removes
- (BOOL)deterministicPopulation;
- (void)populateSystemFromDictionariesWithSun:(OOSunEntity*)sun andPlanet:(OOPlanetEntity*)planet;

@end

// Slice 5 of docs/phases/3-slices/Universe.md: members of cxx::Universe, forwarded by the
// category of the same name in Universe+ObjCBridge.mm (the class's @implementation, still in
// Universe.mm, stays complete).
@interface Universe (OOSlice5)

- (HPVector)cxx_locationByCode:(const std::string&)code withSun:(OOSunEntity*)sun andPlanet:(OOPlanetEntity*)planet;
- (void)setAmbientLightLevel:(float)newValue;
- (float)ambientLightLevel;
- (void)setLighting;
- (void)forceLightSwitch;
- (void)setMainLightPosition:(Vector)sunPos;
- (ShipEntity*)addShipWithRole:(const std::string&)desc launchPos:(HPVector)launchPos rfactor:(GLfloat)rfactor;
- (void)cxx_addShipWithRole:(const std::string&)desc nearRouteOneAt:(double)route_fraction;
- (HPVector)cxx_coordinatesForPosition:(HPVector)pos withCoordinateSystem:(const std::string&)system returningScalar:(GLfloat*)my_scalar;
- (std::optional<std::string>)cxx_expressPosition:(HPVector)pos inCoordinateSystem:(const std::string&)system;

@end

// Slice 6 of docs/phases/3-slices/Universe.md: members of cxx::Universe, forwarded by the
// category of the same name in Universe+ObjCBridge.mm (the class's @implementation, still in
// Universe.mm, stays complete).
@interface Universe (OOSlice6)

- (HPVector)cxx_legacyPositionFrom:(HPVector)pos asCoordinateSystem:(const std::string&)system;
- (HPVector)cxx_coordinatesFromCoordinateSystemString:(const std::string&)system_x_y_z;
- (BOOL)cxx_addShipWithRole:(const std::string&)desc nearPosition:(HPVector)pos withCoordinateSystem:(const std::string&)system;
- (BOOL)cxx_addShips:(int)howMany withRole:(const std::string&)desc atPosition:(HPVector)pos withCoordinateSystem:(const std::string&)system;
- (BOOL)cxx_addShips:(int)howMany withRole:(const std::string&)desc nearPosition:(HPVector)pos withCoordinateSystem:(const std::string&)system;
- (BOOL)cxx_addShips:(int)howMany withRole:(const std::string&)desc nearPosition:(HPVector)pos withCoordinateSystem:(const std::string&)system withinRadius:(GLfloat)radius;
- (BOOL)cxx_addShips:(int)howMany withRole:(const std::string&)desc intoBoundingBox:(BoundingBox)bbox;
- (BOOL)cxx_spawnShip:(const std::string&)shipdesc; // the legacy spawnShip: action's ship key
- (void)cxx_witchspaceShipWithPrimaryRole:(const std::string&)role;
- (ShipEntity*)cxx_spawnShipWithRole:(const std::string&)desc near:(Entity*)entity;
- (OOVisualEffectEntity*)cxx_addVisualEffectAt:(HPVector)pos withKey:(const std::string&)key;

@end

// Slice 7 of docs/phases/3-slices/Universe.md: members of cxx::Universe, forwarded by the
// category of the same name in Universe+ObjCBridge.mm (the class's @implementation, still in
// Universe.mm, stays complete).
@interface Universe (OOSlice7)

- (ShipEntity*)addShipAt:(HPVector)pos withRole:(const std::string&)role withinRadius:(GLfloat)radius;
// Empty where the old methods returned nil (no ship added).
- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_addShipsAt:(HPVector)pos withRole:(const std::string&)role quantity:(unsigned)count withinRadius:(GLfloat)radius asGroup:(BOOL)isGroup;
- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_addShipsToRoute:(const std::string&)route withRole:(const std::string&)role quantity:(unsigned)count routeFraction:(double)routeFraction asGroup:(BOOL)isGroup;
- (BOOL)cxx_roleIsPirateVictim:(const std::string&)role;
- (BOOL)cxx_role:(const std::string&)role isInCategory:(const std::string&)category;
- (void)forceWitchspaceEntries;
- (void)addWitchspaceJumpEffectForShip:(ShipEntity*)ship;
- (GLfloat)safeWitchspaceExitDistance;
- (void)setUpBreakPattern:(HPVector)pos orientation:(Quaternion)q forDocking:(BOOL)forDocking;
- (BOOL)witchspaceBreakPattern;
- (void)setWitchspaceBreakPattern:(BOOL)newValue;
- (BOOL)dockingClearanceProtocolActive;
- (void)setDockingClearanceProtocolActive:(BOOL)newValue;
- (void)handleGameOver;

@end

// Slice 8 of docs/phases/3-slices/Universe.md: members of cxx::Universe, forwarded by the
// category of the same name in Universe+ObjCBridge.mm (the class's @implementation, still in
// Universe.mm, stays complete).
@interface Universe (OOSlice8)

- (void)setupIntroFirstGo:(BOOL)justCobra;
- (oo::PList)demoShipData; // null where there is no such entry
- (void)setLibraryTextForDemoShip;
- (void)selectIntro2Previous;
- (void)selectIntro2PreviousCategory;
- (void)selectIntro2NextCategory;
- (void)selectIntro2Next;
- (StationEntity*)station;
- (StationEntity*)cxx_stationWithRole:(const std::string&)role andPosition:(HPVector)position;
- (StationEntity*)stationFriendlyTo:(ShipEntity*)ship;
- (OOPlanetEntity*)planet;
- (OOSunEntity*)sun;
- (std::vector<oo::ObjCRef<OOPlanetEntity*>>)cxx_planets; // Note: does not include sun.
- (std::vector<oo::ObjCRef<StationEntity*>>)cxx_stations; // includes main station; in the order added

@end

// Slice 9 of docs/phases/3-slices/Universe.md: members of cxx::Universe, forwarded by the
// category of the same name in Universe+ObjCBridge.mm (the class's @implementation, still in
// Universe.mm, stays complete).
@interface Universe (OOSlice9)

- (std::vector<oo::ObjCRef<WormholeEntity*>>)cxx_wormholes;
// Turn main station into just another station, for blowUpStation.
- (void)unMagicMainStation;
- (void)resetBeacons;
- (Entity<OOBeaconEntity>*)firstBeacon;
- (void)setFirstBeacon:(Entity<OOBeaconEntity>*)beacon;
- (Entity<OOBeaconEntity>*)lastBeacon;
- (void)setLastBeacon:(Entity<OOBeaconEntity>*)beacon;
- (void)setNextBeacon:(Entity<OOBeaconEntity>*)beaconShip;
- (void)clearBeacon:(Entity<OOBeaconEntity>*)beaconShip;
- (std::map<std::string, oo::ObjCRef<OOWaypointEntity*>, std::less<>>)cxx_currentWaypoints;
- (void)cxx_defineWaypoint:(const oo::PList&)definition forKey:(const std::string&)key; // a null definition removes
- (GLfloat*)skyClearColor;
// Note: the alpha value is also air resistance!
- (void)setSkyColorRed:(GLfloat)red green:(GLfloat)green blue:(GLfloat)blue alpha:(GLfloat)alpha;
- (BOOL)breakPatternOver;
- (BOOL)breakPatternHide;
- (BOOL)canInstantiateShip:(const std::string&)shipKey;
- (std::optional<std::string>)cxx_randomShipKeyForRoleRespectingConditions:(const std::string&)role; // nullopt: none
- (ShipEntity*)cxx_newShipWithRole:(const std::string&)role OO_RETURNS_RETAINED; // Selects ship using role weights, applies auto_ai, respects conditions
- (OOVisualEffectEntity*)cxx_newVisualEffectWithName:(const std::string&)effectKey OO_RETURNS_RETAINED;
- (ShipEntity*)cxx_newSubentityWithName:(const std::string&)shipKey andScaleFactor:(float)scale OO_RETURNS_RETAINED; // Does not apply auto_ai or respect conditions
- (ShipEntity*)cxx_newShipWithName:(const std::string&)shipKey usePlayerProxy:(BOOL)usePlayerProxy OO_RETURNS_RETAINED; // If usePlayerProxy, non-carriers are instantiated as ProxyPlayerEntity.
- (ShipEntity*)cxx_newShipWithName:(const std::string&)shipKey usePlayerProxy:(BOOL)usePlayerProxy isSubentity:(BOOL)isSubentity OO_RETURNS_RETAINED;
- (ShipEntity*)cxx_newShipWithName:(const std::string&)shipKey usePlayerProxy:(BOOL)usePlayerProxy isSubentity:(BOOL)isSubentity andScaleFactor:(float)scale OO_RETURNS_RETAINED;
- (DockEntity*)cxx_newDockWithName:(const std::string&)shipKey andScaleFactor:(float)scale OO_RETURNS_RETAINED; // Does not apply auto_ai or respect conditions
- (ShipEntity*)cxx_newShipWithName:(const std::string&)shipKey OO_RETURNS_RETAINED; // Does not apply auto_ai or respect conditions
- (Class)cxx_shipClassForShipDictionary:(const oo::PList&)dict; // Nil for a null PList
- (std::optional<std::string>)defaultAIForRole:(const std::string&)role; // autoAImap.plist lookup
- (OOCargoQuantity)cxx_maxCargoForShip:(const std::string&)desc;

@end

// Slice 10 of docs/phases/3-slices/Universe.md: members of cxx::Universe, forwarded by the
// category of the same name in Universe+ObjCBridge.mm (the class's @implementation, still in
// Universe.mm, stays complete).
@interface Universe (OOSlice10)

- (OOCreditsQuantity)cxx_getEquipmentPriceForKey:(const std::string&)eq_key;
- (OOCommodities*)commodities;
- (ShipEntity*)reifyCargoPod:(ShipEntity*)cargoObj;
- (ShipEntity*)cargoPodFromTemplate:(ShipEntity*)cargoObj;
- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_getContainersOfGoods:(OOCargoQuantity)how_many scarce:(BOOL)scarce legal:(BOOL)legal;
- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_getContainersOfCommodity:(const std::string&)commodity_name how_much:(OOCargoQuantity)how_many;
- (void)fillCargopodWithRandomCargo:(ShipEntity*)cargopod;
- (std::string)getRandomCommodity; // a commodity key
- (OOCargoQuantity)cxx_getRandomAmountOfCommodity:(const std::string&)co_type;
- (oo::PList)commodityDataForType:(const std::string&)type; // null: no such good
- (std::optional<std::string>)cxx_displayNameForCommodity:(const std::string&)co_type;
- (std::optional<std::string>)cxx_describeCommodity:(const std::string&)co_type amount:(OOCargoQuantity)co_amount;
- (void)setGameView:(MyOpenGLView*)view;
- (MyOpenGLView*)gameView;
- (GameController*)gameController;
- (oo::PList)cxx_gameSettings;
- (void)useGUILightSource:(BOOL)GUILight;
- (void)lightForEntity:(BOOL)isLit;
- (void)getActiveViewMatrix:(OOMatrix*)outMatrix forwardVector:(Vector*)outForward upVector:(Vector*)outUp;
- (OOMatrix)activeViewMatrix;

@end

// Slice 11 of docs/phases/3-slices/Universe.md: members of cxx::Universe, forwarded by the
// category of the same name in Universe+ObjCBridge.mm (the class's @implementation, still in
// Universe.mm, stays complete).
@interface Universe (OOSlice11)

- (void)defineFrustum;
- (BOOL)viewFrustumIntersectsSphereAt:(Vector)position withRadius:(GLfloat)radius;

@end

// Slice 12 of docs/phases/3-slices/Universe.md: members of cxx::Universe, forwarded by the
// category of the same name in Universe+ObjCBridge.mm (the class's @implementation, still in
// Universe.mm, stays complete).
@interface Universe (OOSlice12)

- (void)drawUniverse;
- (void)prepareToRenderIntoDefaultFramebuffer;
- (int)framesDoneThisUpdate;
- (void)resetFramesDoneThisUpdate;
// Used to draw subentities. Should be getting this from camera.
- (OOMatrix)viewMatrix;

@end

// Slice 13 of docs/phases/3-slices/Universe.md: members of cxx::Universe, forwarded by the
// category of the same name in Universe+ObjCBridge.mm (the class's @implementation, still in
// Universe.mm, stays complete).
@interface Universe (OOSlice13)

- (void)drawMessage;
- (void)drawWatermarkString:(const std::string&)watermarkString;
- (id)entityForUniversalID:(OOUniversalID)u_id;
- (BOOL)addEntity:(Entity*)entity;
- (BOOL)removeEntity:(Entity*)entity;
- (void)ensureEntityReallyRemoved:(Entity*)entity;
- (void)removeAllEntitiesExceptPlayer;
- (void)removeDemoShips;

@end

// Slice 14 of docs/phases/3-slices/Universe.md (bead oo-7jhs5): members of cxx::Universe, forwarded by
// the category of the same name in Universe+ObjCBridge.mm (amendment oo-mvzmb item 1).
@interface Universe (OOSlice14)

- (ShipEntity*)cxx_makeDemoShipWithRole:(const std::string&)role spinning:(BOOL)spinning;
- (BOOL)isVectorClearFromEntity:(Entity*)e1 toDistance:(double)dist fromPoint:(HPVector)p2;
- (Entity*)hazardOnRouteFromEntity:(Entity*)e1 toDistance:(double)dist fromPoint:(HPVector)p2;
- (HPVector)getSafeVectorFromEntity:(Entity*)e1 toDistance:(double)dist fromPoint:(HPVector)p2;
- (ShipEntity*)cxx_addWreckageFrom:(ShipEntity*)ship withRole:(const std::string&)wreckRole at:(HPVector)rpos scale:(GLfloat)scale lifetime:(GLfloat)lifetime;
- (void)addLaserHitEffectsAt:(HPVector)pos against:(ShipEntity*)target damage:(float)damage color:(OOColor*)color;
- (ShipEntity*)firstShipHitByLaserFromShip:(ShipEntity*)srcEntity inDirection:(OOWeaponFacing)direction offset:(Vector)offset gettingRangeFound:(GLfloat*)range_ptr;

@end

// Slice 15 of docs/phases/3-slices/Universe.md (bead oo-dg9d1): members of cxx::Universe, forwarded by
// the category of the same name in Universe+ObjCBridge.mm (amendment oo-mvzmb item 1).
@interface Universe (OOSlice15)

- (Entity*)firstEntityTargetedByPlayer;
- (Entity*)firstEntityTargetedByPlayerPrecisely;
- (std::vector<oo::ObjCRef<Entity*>>)cxx_entitiesWithinRange:(double)range ofEntity:(Entity*)entity;
- (unsigned)cxx_countShipsWithRole:(const std::string&)role inRange:(double)range ofEntity:(Entity*)entity;
- (unsigned)cxx_countShipsWithRole:(const std::string&)role;
- (unsigned)cxx_countShipsWithPrimaryRole:(const std::string&)role inRange:(double)range ofEntity:(Entity*)entity;
- (unsigned)countShipsWithScanClass:(OOScanClass)scanClass inRange:(double)range ofEntity:(Entity*)entity;
- (unsigned)cxx_countShipsWithPrimaryRole:(const std::string&)role;
// General count/search methods. Pass range of -1 and entity of nil to search all of system.
- (unsigned)countEntitiesMatchingPredicate:(EntityFilterPredicate)predicate
                                 parameter:(void*)parameter
                                   inRange:(double)range
                                  ofEntity:(Entity*)entity;
- (unsigned)countShipsMatchingPredicate:(EntityFilterPredicate)predicate
                              parameter:(void*)parameter
                                inRange:(double)range
                               ofEntity:(Entity*)entity;
- (std::vector<oo::ObjCRef<Entity*>>)cxx_findEntitiesMatchingPredicate:(EntityFilterPredicate)predicate
                                                             parameter:(void*)parameter
                                                               inRange:(double)range
                                                              ofEntity:(Entity*)entity;
- (id)findOneEntityMatchingPredicate:(EntityFilterPredicate)predicate
                           parameter:(void*)parameter;
- (std::vector<oo::ObjCRef<Entity*>>)cxx_findShipsMatchingPredicate:(EntityFilterPredicate)predicate
                                                          parameter:(void*)parameter
                                                            inRange:(double)range
                                                           ofEntity:(Entity*)entity;
- (std::vector<oo::ObjCRef<Entity*>>)cxx_findVisualEffectsMatchingPredicate:(EntityFilterPredicate)predicate
                                                                  parameter:(void*)parameter
                                                                    inRange:(double)range
                                                                   ofEntity:(Entity*)entity;
- (id)nearestEntityMatchingPredicate:(EntityFilterPredicate)predicate
                           parameter:(void*)parameter
                    relativeToEntity:(Entity*)entity;
- (id)nearestShipMatchingPredicate:(EntityFilterPredicate)predicate
                         parameter:(void*)parameter
                  relativeToEntity:(Entity*)entity;
- (OOTimeAbsolute)getTime;
- (OOTimeDelta)getTimeDelta;
- (void)findCollisionsAndShadows;
- (std::string)collisionDescription; // flipped with its family (bead oo-3rb.277)
- (void)dumpCollisions;
- (OOViewID)viewDirection;

@end

// Slice 16 of docs/phases/3-slices/Universe.md (bead oo-focfo): members of cxx::Universe, forwarded by
// the category of the same name in Universe+ObjCBridge.mm (amendment oo-mvzmb item 1).
@interface Universe (OOSlice16)

- (void)setViewDirection:(OOViewID)vd;
- (void)enterGUIViewModeWithMouseInteraction:(BOOL)mouseInteraction; // Use instead of setViewDirection:VIEW_GUI_DISPLAY
- (std::optional<std::string>)soundNameForCustomSoundKey:(const std::string&)key; // nullopt: no sound
- (oo::PList)cxx_screenTextureDescriptorForKey:(const std::string&)key; // null: none
- (void)cxx_setScreenTextureDescriptorForKey:(const std::string&)key descriptor:(const oo::PList&)desc; // a null descriptor removes
// Message texts: nullopt where a nil text was passed (nothing is printed; it still counts as the message shown).
- (void)clearPreviousMessage;
- (void)setMessageGuiBackgroundColor:(OOColor*)some_color;
- (void)cxx_displayMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count;
- (void)cxx_displayCountdownMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count;
- (void)cxx_addDelayedMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count afterDelay:(OOTimeDelta)delay;
- (void)addDelayedMessage:(OOUniverseDelayedMessage*)holder; // the deferred call of -cxx_addDelayedMessage:forCount:afterDelay:
- (void)cxx_addMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count;
- (void)speakWithSubstitutions:(const std::optional<std::string>&)text;
- (void)cxx_addMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count forceDisplay:(BOOL)forceDisplay;
- (void)cxx_addCommsMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count;
- (void)cxx_addCommsMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count andShowComms:(BOOL)showComms logOnly:(BOOL)logOnly;
- (void)showCommsLog:(OOTimeDelta)how_long;
- (void)showGUIMessage:(const std::optional<std::string>&)text withScroll:(BOOL)scroll andColor:(OOColor*)selectedColor overDuration:(OOTimeDelta)how_long;
- (void)repopulateSystem;

@end

// Slice 17 of docs/phases/3-slices/Universe.md (bead oo-gr7a2): members of cxx::Universe, forwarded by
// the category of the same name in Universe+ObjCBridge.mm (amendment oo-mvzmb item 1).
@interface Universe (OOSlice17)

// Time Acelleration Factor. In deployment builds, this is always 1.0 and -setTimeAccelerationFactor: does nothing.
- (double)timeAccelerationFactor;
- (void)setTimeAccelerationFactor:(double)newTimeAccelerationFactor;
- (void)update:(OOTimeDelta)delta_t;
- (BOOL)ECMVisualFXEnabled;
- (void)setECMVisualFXEnabled:(BOOL)isEnabled;

@end

// Slice 18 of docs/phases/3-slices/Universe.md (bead oo-tail0): members of cxx::Universe, forwarded by
// the category of the same name in Universe+ObjCBridge.mm (amendment oo-mvzmb item 1).
@interface Universe (OOSlice18)

- (void)filterSortedLists;
- (void)setGalaxyTo:(OOGalaxyID)g;

@end

// Slice 19 of docs/phases/3-slices/Universe.md (bead oo-z3u03): members of cxx::Universe, forwarded by
// the category of the same name in Universe+ObjCBridge.mm (amendment oo-mvzmb item 1).
@interface Universe (OOSlice19)

- (void)setGalaxyTo:(OOGalaxyID)g andReinit:(BOOL)forced;
- (void)setSystemTo:(OOSystemID)s;
- (OOSystemID)currentSystemID;
// The live descriptions dictionary (the built-in descriptions.plist until the merged one is loaded);
// nullptr only for a nil receiver. The generation changes whenever it is replaced.
- (const oo::PList*)cxx_descriptions;
- (unsigned)cxx_descriptionsGeneration;
- (void)verifyDescriptions;
- (void)loadDescriptions;
- (oo::PList)cxx_explosionSetting:(const std::string&)explosion; // a null PList for none
- (oo::PList)cxx_scenarios;
- (void)loadScenarios;
- (oo::PList)cxx_characters;
- (oo::PList)cxx_missiontext;
- (std::optional<std::string>)cxx_descriptionForKey:(const std::string&)key; // String, or random item from array; nullopt for none
- (std::optional<std::string>)cxx_descriptionForArrayKey:(const std::string&)key index:(unsigned)index; // Indexed item from array; nullopt for none
- (BOOL)descriptionBooleanForKey:(const std::string&)key; // Boolean from descriptions.plist, for configuration.
- (OOSystemDescriptionManager*)systemManager;
- (std::optional<std::string>)cxx_keyForPlanetOverridesForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g;
- (std::optional<std::string>)keyForInterstellarOverridesForSystems:(OOSystemID)s1 s2:(OOSystemID)s2 inGalaxy:(OOGalaxyID)g;
- (oo::PList)cxx_generateSystemData:(OOSystemID)s;
- (oo::PList)cxx_generateSystemData:(OOSystemID)s useCache:(BOOL)useCache;
- (oo::PList)cxx_currentSystemData; // Same as generateSystemData:systemSeed unless in interstellar space.
- (BOOL)inInterstellarSpace;
// value: a script value (a null PList to remove); manifest nullopt where nil was passed.
- (void)cxx_setSystemDataKey:(const std::string&)key value:(const oo::PList&)value fromManifest:(const std::optional<std::string>&)manifest;
- (void)cxx_setSystemDataForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum key:(const std::string&)key value:(const oo::PList&)value fromManifest:(const std::optional<std::string>&)manifest forLayer:(OOSystemLayer)layer;
- (oo::PList)generateSystemDataForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum;
- (std::vector<std::string>)cxx_systemDataKeysForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum; // byte order of the key
- (oo::PList)cxx_systemDataForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum key:(const std::string&)key; // a script value (null: none)
- (std::optional<std::string>)cxx_getSystemName:(OOSystemID)sys;
- (std::optional<std::string>)cxx_getSystemName:(OOSystemID)sys forGalaxy:(OOGalaxyID)gnum;
- (OOGovernmentID)getSystemGovernment:(OOSystemID)sys;
- (std::optional<std::string>)cxx_getSystemInhabitants:(OOSystemID)sys;
- (std::optional<std::string>)cxx_getSystemInhabitants:(OOSystemID)sys plural:(BOOL)plural;
- (NSPoint)coordinatesForSystem:(OOSystemID)s;
- (OOSystemID)cxx_findSystemFromName:(const std::string&)sysName;
- (OOSystemID)findSystemAtCoords:(NSPoint)coords withGalaxy:(OOGalaxyID)gal;

@end

// Slice 20 of docs/phases/3-slices/Universe.md (bead oo-lftoq): members of cxx::Universe, forwarded by
// the category of the same name in Universe+ObjCBridge.mm (amendment oo-mvzmb item 1).
@interface Universe (OOSlice20)

/**
 * Finds systems within range.  If range is greater than 7.0LY then only look within 7.0LY.
 */
- (oo::PList)cxx_nearbyDestinationsWithinRange:(double)range; // an array of {distance, sysID, nova}
- (OOSystemID)findNeighbouringSystemToCoords:(NSPoint)coords withGalaxy:(OOGalaxyID)gal;
- (OOSystemID)findConnectedSystemAtCoords:(NSPoint)coords withGalaxy:(OOGalaxyID)gal;
// old alias for findSystemNumberAtCoords
- (OOSystemID)findSystemNumberAtCoords:(NSPoint)coords withGalaxy:(OOGalaxyID)gal includingHidden:(BOOL)hidden;
- (NSPoint)cxx_findSystemCoordinatesWithPrefix:(const std::string&)p_fix;
- (NSPoint)cxx_findSystemCoordinatesWithPrefix:(const std::string&)p_fix exactMatch:(BOOL)exactMatch;
- (BOOL*)systemsFound;
- (std::optional<std::string>)cxx_systemNameIndex:(OOSystemID)index;
- (oo::PList)cxx_routeFromSystem:(OOSystemID)start toSystem:(OOSystemID)goal optimizedBy:(OORouteType)optimizeBy; // {route, distance, time, jumps}; null for no route
- (std::vector<OOSystemID>)neighboursToSystem:(OOSystemID)system_number;
- (void)preloadPlanetTexturesForSystem:(OOSystemID)system;
- (oo::PList)cxx_globalSettings;
- (oo::PList)cxx_equipmentData;
- (oo::PList)cxx_equipmentDataOutfitting;
- (OOCommodityMarket*)commodityMarket;
- (std::optional<std::string>)timeDescription:(OOTimeDelta)interval;

@end

// Slice 21 of docs/phases/3-slices/Universe.md (bead oo-enek8): members of cxx::Universe, forwarded by
// the category of the same name in Universe+ObjCBridge.mm (amendment oo-mvzmb item 1).
@interface Universe (OOSlice21)

- (std::optional<std::string>)cxx_shortTimeDescription:(OOTimeDelta)interval;
- (void)makeSunSkimmer:(ShipEntity*)ship andSetAI:(BOOL)setAI;
- (Random_Seed)marketSeed;
- (void)cxx_loadStationMarkets:(const oo::PList&)marketData; // null: nothing to load
- (oo::PList)cxx_getStationMarkets; // [{market, position}, ...] as saved in the savegame

@end

// Slice 22 of docs/phases/3-slices/Universe.md (bead oo-05ow5): members of cxx::Universe, forwarded by
// the category of the same name in Universe+ObjCBridge.mm (amendment oo-mvzmb item 1).
@interface Universe (OOSlice22)

- (oo::PList)cxx_shipsForSaleForSystem:(OOSystemID)s withTL:(OOTechLevelID)specialTL atTime:(OOTimeAbsolute)current_time; // an array of offer dictionaries, by name and price

@end

// Slice 23 of docs/phases/3-slices/Universe.md (bead oo-ni1hw): members of cxx::Universe, forwarded by
// the category of the same name in Universe+ObjCBridge.mm (amendment oo-mvzmb item 1).
@interface Universe (OOSlice23)

/* Calculate base cost, before depreciation */
- (OOCreditsQuantity)cxx_tradeInValueForCommanderDictionary:(const oo::PList&)cmdr_dict;
- (std::optional<std::string>)brochureDescriptionWithDictionary:(const oo::PList&)dict standardEquipment:(const std::vector<std::string>&)extras optionalEquipment:(const std::vector<std::string>&)options;
- (HPVector)getWitchspaceExitPosition;
- (Quaternion)getWitchspaceExitRotation;
- (HPVector)getSunSkimStartPositionForShip:(ShipEntity*)ship;
- (HPVector)getSunSkimEndPositionForShip:(ShipEntity*)ship;
- (std::vector<oo::ObjCRef<Entity<OOBeaconEntity>*>>)cxx_listBeaconsWithCode:(const std::string&)code; // sorted by beacon code

- (void)cxx_allShipsDoScriptEvent:(OOJSPropID)event andReactToAIMessage:(const std::optional<std::string>&)message; // nullopt: no AI message

///////////////////////////////////////

- (void)clearGUIs;

- (GuiDisplayGen*)gui;
- (GuiDisplayGen*)commLogGUI;
- (GuiDisplayGen*)messageGUI;
- (void)clearGUIs;
- (void)resetCommsLogColor;
- (void)setDisplayText:(BOOL)value;
- (BOOL)displayGUI;
- (void)setDisplayFPS:(BOOL)value;
- (BOOL)displayFPS;
- (void)setAutoSave:(BOOL)value;
- (BOOL)autoSave;
// autosave
- (void)setAutoSaveNow:(BOOL)value;

@end

// Slice 24 of docs/phases/3-slices/Universe.md (bead oo-jxitg): members of cxx::Universe, forwarded by
// the category of the same name in Universe+ObjCBridge.mm (amendment oo-mvzmb item 1).
@interface Universe (OOSlice24)

#if !OOLITE_MAC_OS_X
- (void)cxx_startSpeakingString:(const std::string&)text;
- (void)stopSpeaking;
- (BOOL)isSpeaking;
#endif
#if OOLITE_ESPEAK
- (std::optional<std::string>)cxx_voiceName:(unsigned int)index;
- (unsigned int)cxx_voiceNumber:(const std::string&)name;
- (unsigned int)nextVoice:(unsigned int)index;
- (unsigned int)prevVoice:(unsigned int)index;
- (unsigned int)setVoice:(unsigned int)index withGenderM:(BOOL)isMale;
#endif
- (BOOL)autoSaveNow;
- (void)setWireframeGraphics:(BOOL)value;
- (BOOL)wireframeGraphics;
- (BOOL)reducedDetail;
- (void)setDetailLevelDirectly:(OOGraphicsDetail)value;
- (void)setDetailLevel:(OOGraphicsDetail)value;
- (OOGraphicsDetail)detailLevel;
- (BOOL)useShaders;
- (void)handleOoliteException:(OOException*)ooliteException;
- (GLfloat)airResistanceFactor;
- (void)setAirResistanceFactor:(GLfloat)newFactor;
// True if textual pause message (as opposed to overlay) is being shown.
- (BOOL)pauseMessageVisible;
- (void)setPauseMessageVisible:(BOOL)value;
- (BOOL)permanentMessageLog;
- (void)setPermanentMessageLog:(BOOL)value;
- (BOOL)autoMessageLogBg;
- (void)setAutoMessageLogBg:(BOOL)value;
- (BOOL)permanentCommLog;
- (void)setPermanentCommLog:(BOOL)value;
- (void)setAutoCommLog:(BOOL)value;
- (BOOL)blockJSPlayerShipProps;
- (void)setBlockJSPlayerShipProps:(BOOL)value;
- (void)setUpSettings;
- (void)setUpCargoPods;
- (void)verifyEntitySessionIDs;

@end

// Slice 25 of docs/phases/3-slices/Universe.md (bead oo-wmc72): members of cxx::Universe, forwarded by
// the category of the same name in Universe+ObjCBridge.mm (amendment oo-mvzmb item 1).
@interface Universe (OOSlice25)

- (BOOL)reinitAndShowDemo:(BOOL)showDemo;
- (void)setUpInitialUniverse;
- (float)randomDistanceWithinScanner;
- (Vector)randomPlaceWithinScannerFrom:(Vector)pos alongRoute:(Vector)route withOffset:(double)offset;
- (HPVector)fractionalPositionFrom:(HPVector)point0 to:(HPVector)point1 withFraction:(double)routeFraction;
- (BOOL)doRemoveEntity:(Entity*)entity;
- (void)preloadSounds;
- (void)populateSpaceFromActiveWormholes;
- (std::optional<std::string>)chooseStringForKey:(const std::string&)key inDictionary:(const oo::PList&)dictionary;
#if OO_LOCALIZATION_TOOLS && DEBUG_GRAPHVIZ
- (void)dumpDebugGraphViz;
- (void)dumpSystemDescriptionGraphViz;
#endif

@end

// Slice 2 of docs/phases/3-slices/Universe.md: members of cxx::Universe, forwarded by the
// category of the same name in Universe+ObjCBridge.mm (the class's @implementation, still in
// Universe.mm, stays complete).
@interface Universe (OOSlice2)

- (BOOL)bloom;
- (void)setBloom:(BOOL)newBloom;
- (int)currentPostFX;
- (void)setCurrentPostFX:(int)newCurrentPostFX;
- (void)terminatePostFX:(int)postFX;
- (int)nextColorblindMode:(int)index;
- (int)prevColorblindMode:(int)index;
- (int)colorblindMode;
- (void)initTargetFramebufferWithViewSize:(NSSize)viewSize;
- (void)deleteOpenGLObjects;
- (void)resizeTargetFramebufferWithViewSize:(NSSize)viewSize;
- (void)drawTargetTextureIntoDefaultFramebuffer;
// SessionID: a value that's incremented when the game is reset.
- (NSUInteger)sessionID;
- (BOOL)doingStartUp; // True during initial game startup (not reset).
- (BOOL)doProcedurallyTexturedPlanets;
- (void)setDoProcedurallyTexturedPlanets:(BOOL)value;
- (std::optional<std::string>)cxx_useAddOns;
- (BOOL)cxx_setUseAddOns:(const std::string&)newUse fromSaveGame:(BOOL)saveGame;
- (BOOL)cxx_setUseAddOns:(const std::string&)newUse fromSaveGame:(BOOL)saveGame forceReinit:(BOOL)force;
- (NSUInteger)entityCount;
#ifdef OO_DEBUG_MONITOR_ENABLED
- (void)debugDumpEntities;
- (std::vector<oo::ObjCRef<Entity*>>)cxx_entityList;
#endif

@end

// Slice 26 of docs/phases/3-slices/Universe.md (bead oo-32kcu): members of cxx::Universe, forwarded by
// the category of the same name in Universe+ObjCBridge.mm (amendment oo-mvzmb item 1).
@interface Universe (OOSlice26)

#if OO_LOCALIZATION_TOOLS
- (void)addNumericRefsInString:(const std::string&)string toGraphViz:(std::string&)graphViz fromNode:(const std::string&)fromNode nodeCount:(NSUInteger)nodeCount;
/**
 * \ingroup cli
 * Scans the command line for --complie-sysdesc, --export-sysdec, --xml and --penstep arguments.
 */
- (void)runLocalizationTools;
#endif
- (void)prunePreloadingPlanetMaterials;
- (void)loadConditionScripts;
- (void)addConditionScripts:(const std::vector<std::string>&)scripts;
- (OOJSScript*)cxx_getConditionScript:(const std::string&)scriptname;

@end

namespace oo {

// The C++ universe behind the Objective-C one, borrowed; null for nil and for a universe whose
// -initWithGameView: has not run.
inline cxx::Universe* ToCxx(::Universe* universe) { return universe != nil ? universe->_cxxUniverse.get() : nullptr; }

// The Objective-C universe that owns a C++ one, borrowed (it lives while its part does); nil for null.
inline ::Universe* ToObjC(cxx::Universe* universe) { return universe != nullptr ? universe->_objcOwner : nil; }

} // namespace oo

/*	The messages to UNIVERSE behind the description and custom-sound look-ups (slice 26): sends,
        not member calls, because many tests stand in for the universe with a class of their own
        (amendment oo-rmd7 item 3; ADR-0056 amendment oo-7jhs5). Defined in Universe+ObjCBridge.mm.
*/
std::optional<std::string> OOUniverseDescriptionForKey(const std::string& key); // [UNIVERSE cxx_descriptionForKey:key]
const oo::PList* OOUniverseDescriptions(); // [UNIVERSE cxx_descriptions]
std::optional<std::string> OOUniverseSoundNameForCustomSoundKey(const std::string& key); // [UNIVERSE soundNameForCustomSoundKey:key]

#endif // UNIVERSE_OBJCBRIDGE_H
