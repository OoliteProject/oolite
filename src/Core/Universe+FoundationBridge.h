/*

Universe+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; made by bead oo-3rb.220, chunk 1 of the
Universe sweep oo-3rb.79, and extended only by its later chunks oo-3rb.221-.231). Universe's
Foundation-typed API as it was before its sweep, with the same selector and function names and
types, forwarding to the cxx_ API in Universe.h. It exists so that Universe's callers (some 70
files, most through the UNIVERSE macro and DESC()) compile unchanged; each caller moves to the cxx_
API in its own sweep bead. When `git grep` finds no caller of anything declared here, the bridge
bead deletes this file, Universe+FoundationBridge.mm, its line in Core/meson.build and the #import
at the end of Universe.h (DESC() / DESC_PLURAL() then expand to the cxx_ lookups). Never add to it
outside the Universe chunks; never call it from migrated code. oo-qps (the removal of
gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2004-2013 Giles C Williams and contributors (Universe.h)

*/

// Imported only from the end of Universe.h (which declares everything used here); never import it
// directly, and never import Universe.h from it (a cycle).
#ifndef UNIVERSE_FOUNDATIONBRIDGE_H
#define UNIVERSE_FOUNDATIONBRIDGE_H

@interface Universe (OOFoundationBridge)

// Chunk 1 (oo-3rb.220): descriptions, characters, mission text, scenarios, explosion settings.
- (NSDictionary*)descriptions; // -> -cxx_descriptions (one immutable copy per -cxx_descriptionsGeneration)
- (NSDictionary*)characters; // -> -cxx_characters
- (NSDictionary*)missiontext; // -> -cxx_missiontext
- (NSArray*)scenarios; // -> -cxx_scenarios
- (NSDictionary*)explosionSetting:(NSString*)explosion; // -> -cxx_explosionSetting:

- (NSString*)descriptionForKey:(NSString*)key; // -> -cxx_descriptionForKey:
- (NSString*)descriptionForArrayKey:(NSString*)key index:(unsigned)index; // -> -cxx_descriptionForArrayKey:index:

// Chunk 2 (oo-3rb.221): system data, system names and override keys.
- (NSString*)keyForPlanetOverridesForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g; // -> -cxx_keyForPlanetOverridesForSystem:inGalaxy:
- (NSDictionary*)generateSystemData:(OOSystemID)s; // -> -cxx_generateSystemData:
- (NSDictionary*)generateSystemData:(OOSystemID)s useCache:(BOOL)useCache; // -> -cxx_generateSystemData:useCache:
- (NSDictionary*)currentSystemData; // -> -cxx_currentSystemData
- (void)setSystemDataKey:(NSString*)key value:(NSObject*)object fromManifest:(NSString*)manifest; // -> -cxx_setSystemDataKey:value:fromManifest:
- (void)setSystemDataForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum key:(NSString*)key value:(id)object fromManifest:(NSString*)manifest forLayer:(OOSystemLayer)layer; // -> -cxx_setSystemDataForGalaxy:...
- (id)systemDataForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum key:(NSString*)key; // -> -cxx_systemDataForGalaxy:planet:key:
- (NSArray*)systemDataKeysForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum; // -> -cxx_systemDataKeysForGalaxy:planet:
- (NSString*)getSystemName:(OOSystemID)sys; // -> -cxx_getSystemName:
- (NSString*)getSystemName:(OOSystemID)sys forGalaxy:(OOGalaxyID)gnum; // -> -cxx_getSystemName:forGalaxy:
- (NSString*)getSystemInhabitants:(OOSystemID)sys; // -> -cxx_getSystemInhabitants:
- (NSString*)getSystemInhabitants:(OOSystemID)sys plural:(BOOL)plural; // -> -cxx_getSystemInhabitants:plural:
- (OOSystemID)findSystemFromName:(NSString*)sysName; // -> -cxx_findSystemFromName:
- (NSString*)systemNameIndex:(OOSystemID)index; // -> -cxx_systemNameIndex:

// Chunk 3 (oo-3rb.222): routes, chart searches and travel-time text.
- (NSMutableArray*)nearbyDestinationsWithinRange:(double)range; // -> -cxx_nearbyDestinationsWithinRange:
- (NSPoint)findSystemCoordinatesWithPrefix:(NSString*)p_fix; // -> -cxx_findSystemCoordinatesWithPrefix:
- (NSPoint)findSystemCoordinatesWithPrefix:(NSString*)p_fix exactMatch:(BOOL)exactMatch; // -> -cxx_findSystemCoordinatesWithPrefix:exactMatch:
- (NSDictionary*)routeFromSystem:(OOSystemID)start toSystem:(OOSystemID)goal optimizedBy:(OORouteType)optimizeBy; // -> -cxx_routeFromSystem:toSystem:optimizedBy:
- (NSString*)shortTimeDescription:(OOTimeDelta)interval; // -> -cxx_shortTimeDescription:

// Chunk 4 (oo-3rb.223): ship, effect and dock creation.
- (NSString*)randomShipKeyForRoleRespectingConditions:(NSString*)role; // -> -cxx_randomShipKeyForRoleRespectingConditions:
- (ShipEntity*)newShipWithRole:(NSString*)role OO_RETURNS_RETAINED; // -> -cxx_newShipWithRole:
- (ShipEntity*)newShipWithName:(NSString*)shipKey OO_RETURNS_RETAINED; // -> -cxx_newShipWithName:
- (ShipEntity*)newSubentityWithName:(NSString*)shipKey andScaleFactor:(float)scale OO_RETURNS_RETAINED; // -> -cxx_newSubentityWithName:andScaleFactor:
- (OOVisualEffectEntity*)newVisualEffectWithName:(NSString*)effectKey OO_RETURNS_RETAINED; // -> -cxx_newVisualEffectWithName:
- (DockEntity*)newDockWithName:(NSString*)shipKey andScaleFactor:(float)scale OO_RETURNS_RETAINED; // -> -cxx_newDockWithName:andScaleFactor:
- (ShipEntity*)newShipWithName:(NSString*)shipKey usePlayerProxy:(BOOL)usePlayerProxy OO_RETURNS_RETAINED; // -> -cxx_newShipWithName:usePlayerProxy:
- (ShipEntity*)newShipWithName:(NSString*)shipKey usePlayerProxy:(BOOL)usePlayerProxy isSubentity:(BOOL)isSubentity OO_RETURNS_RETAINED; // -> -cxx_newShipWithName:usePlayerProxy:isSubentity:
- (ShipEntity*)newShipWithName:(NSString*)shipKey usePlayerProxy:(BOOL)usePlayerProxy isSubentity:(BOOL)isSubentity andScaleFactor:(float)scale OO_RETURNS_RETAINED; // -> -cxx_newShipWithName:usePlayerProxy:isSubentity:andScaleFactor:
- (Class)shipClassForShipDictionary:(NSDictionary*)dict; // -> -cxx_shipClassForShipDictionary:
- (ShipEntity*)addWreckageFrom:(ShipEntity*)ship withRole:(NSString*)wreckRole at:(HPVector)rpos scale:(GLfloat)scale lifetime:(GLfloat)lifetime; // -> -cxx_addWreckageFrom:withRole:at:scale:lifetime:

// Chunk 5 (oo-3rb.224): adding and spawning ships, coordinate systems, roles, condition scripts.
- (void)addShipWithRole:(NSString*)desc nearRouteOneAt:(double)route_fraction; // -> -cxx_addShipWithRole:nearRouteOneAt:
- (HPVector)coordinatesForPosition:(HPVector)pos withCoordinateSystem:(NSString*)system returningScalar:(GLfloat*)my_scalar; // -> -cxx_coordinatesForPosition:...
- (NSString*)expressPosition:(HPVector)pos inCoordinateSystem:(NSString*)system; // -> -cxx_expressPosition:inCoordinateSystem:
- (HPVector)legacyPositionFrom:(HPVector)pos asCoordinateSystem:(NSString*)system; // -> -cxx_legacyPositionFrom:asCoordinateSystem:
- (HPVector)coordinatesFromCoordinateSystemString:(NSString*)system_x_y_z; // -> -cxx_coordinatesFromCoordinateSystemString:
- (BOOL)addShipWithRole:(NSString*)desc nearPosition:(HPVector)pos withCoordinateSystem:(NSString*)system; // -> -cxx_addShipWithRole:nearPosition:withCoordinateSystem:
- (BOOL)addShips:(int)howMany withRole:(NSString*)desc atPosition:(HPVector)pos withCoordinateSystem:(NSString*)system; // -> -cxx_addShips:...
- (BOOL)addShips:(int)howMany withRole:(NSString*)desc nearPosition:(HPVector)pos withCoordinateSystem:(NSString*)system; // -> -cxx_addShips:...
- (BOOL)addShips:(int)howMany withRole:(NSString*)desc nearPosition:(HPVector)pos withCoordinateSystem:(NSString*)system withinRadius:(GLfloat)radius; // -> -cxx_addShips:...
- (BOOL)addShips:(int)howMany withRole:(NSString*)desc intoBoundingBox:(BoundingBox)bbox; // -> -cxx_addShips:withRole:intoBoundingBox:
- (void)witchspaceShipWithPrimaryRole:(NSString*)role; // -> -cxx_witchspaceShipWithPrimaryRole:
- (ShipEntity*)spawnShipWithRole:(NSString*)desc near:(Entity*)entity; // -> -cxx_spawnShipWithRole:near:
- (OOVisualEffectEntity*)addVisualEffectAt:(HPVector)pos withKey:(NSString*)key; // -> -cxx_addVisualEffectAt:withKey:
- (NSArray*)addShipsAt:(HPVector)pos withRole:(NSString*)role quantity:(unsigned)count withinRadius:(GLfloat)radius asGroup:(BOOL)isGroup; // -> -cxx_addShipsAt:...
- (NSArray*)addShipsToRoute:(NSString*)route withRole:(NSString*)role quantity:(unsigned)count routeFraction:(double)routeFraction asGroup:(BOOL)isGroup; // -> -cxx_addShipsToRoute:...
- (BOOL)roleIsPirateVictim:(NSString*)role; // -> -cxx_roleIsPirateVictim:
- (BOOL)role:(NSString*)role isInCategory:(NSString*)category; // -> -cxx_role:isInCategory:
- (OOJSScript*)getConditionScript:(NSString*)scriptname; // -> -cxx_getConditionScript:

// Chunk 6 (oo-3rb.225): system population.
- (NSDictionary*)getPopulatorSettings; // -> -cxx_getPopulatorSettings (a fresh immutable snapshot per call; the old one was live, and callers only read it)
- (void)setPopulatorSetting:(NSString*)key to:(NSDictionary*)setting; // -> -cxx_setPopulatorSetting:to:
- (HPVector)locationByCode:(NSString*)code withSun:(OOSunEntity*)sun andPlanet:(OOPlanetEntity*)planet; // -> -cxx_locationByCode:withSun:andPlanet:

// Chunk 7 (oo-3rb.226): commodities, cargo pods, equipment data, station markets.
- (OOCargoQuantity)maxCargoForShip:(NSString*)desc; // -> -cxx_maxCargoForShip:
- (OOCreditsQuantity)getEquipmentPriceForKey:(NSString*)eq_key; // -> -cxx_getEquipmentPriceForKey:
- (NSArray*)getContainersOfGoods:(OOCargoQuantity)how_many scarce:(BOOL)scarce legal:(BOOL)legal; // -> -cxx_getContainersOfGoods:scarce:legal:
- (NSArray*)getContainersOfCommodity:(OOCommodityType)commodity_name how_much:(OOCargoQuantity)how_many; // -> -cxx_getContainersOfCommodity:how_much:
- (OOCargoQuantity)getRandomAmountOfCommodity:(OOCommodityType)co_type; // -> -cxx_getRandomAmountOfCommodity:
- (NSString*)displayNameForCommodity:(OOCommodityType)co_type; // -> -cxx_displayNameForCommodity:
- (NSString*)describeCommodity:(OOCommodityType)co_type amount:(OOCargoQuantity)co_amount; // -> -cxx_describeCommodity:amount:
- (NSArray*)equipmentData; // -> -cxx_equipmentData (a fresh immutable copy per call; OOEquipmentType reads it at load)
- (NSArray*)equipmentDataOutfitting; // -> -cxx_equipmentDataOutfitting
- (void)loadStationMarkets:(NSArray*)marketData; // -> -cxx_loadStationMarkets:
- (NSArray*)getStationMarkets; // -> -cxx_getStationMarkets

// Chunk 8 (oo-3rb.227): shipyard offers, trade-in value.
- (NSArray*)shipsForSaleForSystem:(OOSystemID)s withTL:(OOTechLevelID)specialTL atTime:(OOTimeAbsolute)current_time; // -> -cxx_shipsForSaleForSystem:withTL:atTime:
- (OOCreditsQuantity)tradeInValueForCommanderDictionary:(NSDictionary*)cmdr_dict; // -> -cxx_tradeInValueForCommanderDictionary:

// Chunk 9 (oo-3rb.228): entity lists, stations, planets, wormholes, waypoints, predicate searches.
// The lists are snapshots (the old -planets / -wormholes / -currentWaypoints were the live
// collections; their callers only read them).
#ifdef OO_DEBUG_MONITOR_ENABLED
- (NSArray*)entityList; // -> -cxx_entityList
#endif
- (NSArray*)planets; // Note: does not include sun.	// -> -cxx_planets
- (NSArray*)stations; // includes main station	// -> -cxx_stations
- (NSArray*)wormholes; // -> -cxx_wormholes
- (StationEntity*)stationWithRole:(NSString*)role andPosition:(HPVector)position; // -> -cxx_stationWithRole:andPosition:
- (NSDictionary*)currentWaypoints; // -> -cxx_currentWaypoints
- (void)defineWaypoint:(NSDictionary*)definition forKey:(NSString*)key; // -> -cxx_defineWaypoint:forKey:
- (NSArray*)entitiesWithinRange:(double)range ofEntity:(Entity*)entity; // -> -cxx_entitiesWithinRange:ofEntity:
- (unsigned)countShipsWithRole:(NSString*)role inRange:(double)range ofEntity:(Entity*)entity; // -> -cxx_countShipsWithRole:inRange:ofEntity:
- (unsigned)countShipsWithRole:(NSString*)role; // -> -cxx_countShipsWithRole:
- (unsigned)countShipsWithPrimaryRole:(NSString*)role inRange:(double)range ofEntity:(Entity*)entity; // -> -cxx_countShipsWithPrimaryRole:inRange:ofEntity:
- (unsigned)countShipsWithPrimaryRole:(NSString*)role; // -> -cxx_countShipsWithPrimaryRole:
// -> -cxx_findEntitiesMatchingPredicate:... / -cxx_findShipsMatchingPredicate:... /
// -cxx_findVisualEffectsMatchingPredicate:... (each call a fresh mutable array, as before)
- (NSMutableArray*)findEntitiesMatchingPredicate:(EntityFilterPredicate)predicate
                                       parameter:(void*)parameter
                                         inRange:(double)range
                                        ofEntity:(Entity*)entity;
- (NSMutableArray*)findShipsMatchingPredicate:(EntityFilterPredicate)predicate
                                    parameter:(void*)parameter
                                      inRange:(double)range
                                     ofEntity:(Entity*)entity;
- (NSMutableArray*)findVisualEffectsMatchingPredicate:(EntityFilterPredicate)predicate
                                            parameter:(void*)parameter
                                              inRange:(double)range
                                             ofEntity:(Entity*)entity;
- (NSArray*)listBeaconsWithCode:(NSString*)code; // -> -cxx_listBeaconsWithCode:
- (void)allShipsDoScriptEvent:(OOJSPropID)event andReactToAIMessage:(NSString*)message; // -> -cxx_allShipsDoScriptEvent:andReactToAIMessage:

// Chunk 10 (oo-3rb.229): messages, speech, custom sounds, screen backgrounds.
- (NSDictionary*)screenTextureDescriptorForKey:(NSString*)key; // -> -cxx_screenTextureDescriptorForKey:
- (void)setScreenTextureDescriptorForKey:(NSString*)key descriptor:(NSDictionary*)desc; // -> -cxx_setScreenTextureDescriptorForKey:descriptor:
- (void)displayMessage:(NSString*)text forCount:(OOTimeDelta)count; // -> -cxx_displayMessage:forCount:
- (void)displayCountdownMessage:(NSString*)text forCount:(OOTimeDelta)count; // -> -cxx_displayCountdownMessage:forCount:
- (void)addDelayedMessage:(NSString*)text forCount:(OOTimeDelta)count afterDelay:(OOTimeDelta)delay; // -> -cxx_addDelayedMessage:forCount:afterDelay:
- (void)addMessage:(NSString*)text forCount:(OOTimeDelta)count; // -> -cxx_addMessage:forCount:
- (void)addMessage:(NSString*)text forCount:(OOTimeDelta)count forceDisplay:(BOOL)forceDisplay; // -> -cxx_addMessage:forCount:forceDisplay:
- (void)addCommsMessage:(NSString*)text forCount:(OOTimeDelta)count; // -> -cxx_addCommsMessage:forCount:
- (void)addCommsMessage:(NSString*)text forCount:(OOTimeDelta)count andShowComms:(BOOL)showComms logOnly:(BOOL)logOnly; // -> -cxx_addCommsMessage:forCount:andShowComms:logOnly:
- (void)startSpeakingString:(NSString*)text; // -> -cxx_startSpeakingString:
#if OOLITE_ESPEAK
- (NSString*)voiceName:(unsigned int)index; // -> -cxx_voiceName:
- (unsigned int)voiceNumber:(NSString*)name; // -> -cxx_voiceNumber:
#endif

// Chunk 11 (oo-3rb.230): demo ships.
- (ShipEntity*)makeDemoShipWithRole:(NSString*)role spinning:(BOOL)spinning; // -> -cxx_makeDemoShipWithRole:spinning:

// Chunk 12 (oo-3rb.231): add-ons, settings.
- (NSString*)useAddOns; // -> -cxx_useAddOns
- (BOOL)setUseAddOns:(NSString*)newUse fromSaveGame:(BOOL)saveGame; // -> -cxx_setUseAddOns:fromSaveGame:
- (BOOL)setUseAddOns:(NSString*)newUse fromSaveGame:(BOOL)saveGame forceReinit:(BOOL)force; // -> -cxx_setUseAddOns:fromSaveGame:forceReinit:
- (NSDictionary*)gameSettings; // -> -cxx_gameSettings
- (NSDictionary*)globalSettings; // -> -cxx_globalSettings (a fresh immutable copy per call; its callers only read it)

@end

// Chunk 10 (oo-3rb.229): the custom sound categories.
@interface OOSound (OOCustomSoundsFoundationBridge)
+ (id)soundWithCustomSoundKey:(NSString*)key; // -> +cxx_soundWithCustomSoundKey:
@end

@interface OOSoundSource (OOCustomSoundsFoundationBridge)
- (void)playCustomSoundWithKey:(NSString*)key; // -> -cxx_playCustomSoundWithKey:
@end

// Chunk 1 (oo-3rb.220): the lookups behind DESC() / DESC_PLURAL().
#ifdef __cplusplus
extern "C" {
#endif
NSString* OOLookUpDescriptionPRIV(NSString* key); // -> cxx_OOLookUpDescriptionPRIV
#ifdef __cplusplus
}
#endif
NSString* OOLookUpPluralDescriptionPRIV(NSString* key, NSInteger count); // -> cxx_OOLookUpPluralDescriptionPRIV

// Chunk 12 (oo-3rb.231): OOConstToString's display strings, declared in Universe.h before
// (defined in OOConstToString.mm; -> cxx_OODisplayStringFromGovernmentID / EconomyID).
#ifdef __cplusplus
extern "C" {
#endif
NSString* OODisplayStringFromGovernmentID(OOGovernmentID government);
NSString* OODisplayStringFromEconomyID(OOEconomyID economy);
#ifdef __cplusplus
}
#endif

#endif // UNIVERSE_FOUNDATIONBRIDGE_H
