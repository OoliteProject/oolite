/*

Universe+FoundationBridge.mm

TRANSITIONAL: see Universe+FoundationBridge.h. Each method and function forwards to its cxx_
counterpart and converts the result exactly as the old one produced it (nil for nil).

*/

#import "OOFoundationBridge.h"
#import "Universe.h" // declares the bridge at its end

@implementation Universe (OOFoundationBridge)

// Chunk 1 (oo-3rb.220).

/*	The old method handed out the live dictionary, and callers only read it (OOStringExpander per
        key, OOConstToString, the verifier...). It is read far too often to convert per call, so one
        immutable copy is kept and rebuilt only when the descriptions are replaced; the one it replaces
        is autoreleased, as -loadDescriptions autoreleased the old dictionary.
*/
- (NSDictionary*)descriptions
{
    static NSDictionary* sDescriptions = nil;
    static unsigned sGeneration = 0;

    const oo::PList* descriptions = [self cxx_descriptions];
    if (sDescriptions == nil || sGeneration != [self cxx_descriptionsGeneration]) {
        [sDescriptions autorelease];
        sDescriptions = [oo::ObjectFromPList(*descriptions) retain];
        sGeneration = [self cxx_descriptionsGeneration];
    }
    return sDescriptions;
}

// A fresh immutable copy per call (cold paths).
- (NSDictionary*)characters
{
    return oo::ObjectFromPList([self cxx_characters]);
}

- (NSDictionary*)missiontext
{
    return oo::ObjectFromPList([self cxx_missiontext]);
}

- (NSArray*)scenarios
{
    return oo::ObjectFromPList([self cxx_scenarios]);
}

// A nil name found no setting, as "" does.
- (NSDictionary*)explosionSetting:(NSString*)explosion
{
    return oo::ObjectFromPList([self cxx_explosionSetting:oo::StdString(explosion)]);
}

- (NSString*)descriptionForKey:(NSString*)key
{
    return oo::NSStringOrNil([self cxx_descriptionForKey:oo::StdString(key)]);
}

- (NSString*)descriptionForArrayKey:(NSString*)key index:(unsigned)index
{
    return oo::NSStringOrNil([self cxx_descriptionForArrayKey:oo::StdString(key) index:index]);
}

// Chunk 2 (oo-3rb.221). Dictionaries are fresh immutable copies per call (the old ones came from
// the system description manager, which also built them per call).

- (NSString*)keyForPlanetOverridesForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g
{
    return oo::NSStringOrNil([self cxx_keyForPlanetOverridesForSystem:s inGalaxy:g]);
}

- (NSDictionary*)generateSystemData:(OOSystemID)s
{
    return oo::ObjectFromPList([self cxx_generateSystemData:s]);
}

- (NSDictionary*)generateSystemData:(OOSystemID)s useCache:(BOOL)useCache
{
    return oo::ObjectFromPList([self cxx_generateSystemData:s useCache:useCache]);
}

- (NSDictionary*)currentSystemData
{
    return oo::ObjectFromPList([self cxx_currentSystemData]);
}

// A nil key compared equal to nothing, as "" does; a nil manifest stays nullopt.
- (void)setSystemDataKey:(NSString*)key value:(NSObject*)object fromManifest:(NSString*)manifest
{
    [self cxx_setSystemDataKey:oo::StdString(key) value:object fromManifest:oo::OptionalString(manifest)];
}

- (void)setSystemDataForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum key:(NSString*)key value:(id)object fromManifest:(NSString*)manifest forLayer:(OOSystemLayer)layer
{
    [self cxx_setSystemDataForGalaxy:gnum planet:pnum key:oo::StdString(key) value:object fromManifest:oo::OptionalString(manifest) forLayer:layer];
}

- (id)systemDataForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum key:(NSString*)key
{
    return [self cxx_systemDataForGalaxy:gnum planet:pnum key:oo::StdString(key)];
}

- (NSArray*)systemDataKeysForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum
{
    return oo::NSArrayFromStrings([self cxx_systemDataKeysForGalaxy:gnum planet:pnum]);
}

- (NSString*)getSystemName:(OOSystemID)sys
{
    return oo::NSStringOrNil([self cxx_getSystemName:sys]);
}

- (NSString*)getSystemName:(OOSystemID)sys forGalaxy:(OOGalaxyID)gnum
{
    return oo::NSStringOrNil([self cxx_getSystemName:sys forGalaxy:gnum]);
}

- (NSString*)getSystemInhabitants:(OOSystemID)sys
{
    return oo::NSStringOrNil([self cxx_getSystemInhabitants:sys]);
}

- (NSString*)getSystemInhabitants:(OOSystemID)sys plural:(BOOL)plural
{
    return oo::NSStringOrNil([self cxx_getSystemInhabitants:sys plural:plural]);
}

- (OOSystemID)findSystemFromName:(NSString*)sysName
{
    if (sysName == nil)
        return -1; // no match found!
    return [self cxx_findSystemFromName:oo::StdString(sysName)];
}

- (NSString*)systemNameIndex:(OOSystemID)index
{
    return oo::NSStringOrNil([self cxx_systemNameIndex:index]);
}

// Chunk 3 (oo-3rb.222).

// A fresh mutable array per call, as the old method built one.
- (NSMutableArray*)nearbyDestinationsWithinRange:(double)range
{
    return [[oo::ObjectFromPList([self cxx_nearbyDestinationsWithinRange:range]) mutableCopy] autorelease];
}

- (NSPoint)findSystemCoordinatesWithPrefix:(NSString*)p_fix
{
    return [self findSystemCoordinatesWithPrefix:p_fix exactMatch:NO];
}

// A nil prefix matched no system (while every flag was still cleared); "" would match them all.
- (NSPoint)findSystemCoordinatesWithPrefix:(NSString*)p_fix exactMatch:(BOOL)exactMatch
{
    if (p_fix == nil) {
        for (int i = 0; i < 256; i++)
            system_found[i] = NO;
        return NSMakePoint(-1.0, -1.0);
    }
    return [self cxx_findSystemCoordinatesWithPrefix:oo::StdString(p_fix) exactMatch:exactMatch];
}

- (NSDictionary*)routeFromSystem:(OOSystemID)start toSystem:(OOSystemID)goal optimizedBy:(OORouteType)optimizeBy
{
    return oo::ObjectFromPList([self cxx_routeFromSystem:start toSystem:goal optimizedBy:optimizeBy]);
}

- (NSString*)shortTimeDescription:(OOTimeDelta)interval
{
    return oo::NSStringOrNil([self cxx_shortTimeDescription:interval]);
}

// Chunk 4 (oo-3rb.223). A nil key or role found no ship (as "" finds none); the old methods
// returned nil there too.

- (NSString*)randomShipKeyForRoleRespectingConditions:(NSString*)role
{
    return oo::NSStringOrNil([self cxx_randomShipKeyForRoleRespectingConditions:oo::StdString(role)]);
}

- (ShipEntity*)newShipWithRole:(NSString*)role
{
    return [self cxx_newShipWithRole:oo::StdString(role)];
}

- (ShipEntity*)newShipWithName:(NSString*)shipKey
{
    return [self cxx_newShipWithName:oo::StdString(shipKey)];
}

- (ShipEntity*)newSubentityWithName:(NSString*)shipKey andScaleFactor:(float)scale
{
    return [self cxx_newSubentityWithName:oo::StdString(shipKey) andScaleFactor:scale];
}

- (OOVisualEffectEntity*)newVisualEffectWithName:(NSString*)effectKey
{
    return [self cxx_newVisualEffectWithName:oo::StdString(effectKey)];
}

- (DockEntity*)newDockWithName:(NSString*)shipKey andScaleFactor:(float)scale
{
    return [self cxx_newDockWithName:oo::StdString(shipKey) andScaleFactor:scale];
}

- (ShipEntity*)newShipWithName:(NSString*)shipKey usePlayerProxy:(BOOL)usePlayerProxy
{
    return [self cxx_newShipWithName:oo::StdString(shipKey) usePlayerProxy:usePlayerProxy];
}

- (ShipEntity*)newShipWithName:(NSString*)shipKey usePlayerProxy:(BOOL)usePlayerProxy isSubentity:(BOOL)isSubentity
{
    return [self cxx_newShipWithName:oo::StdString(shipKey) usePlayerProxy:usePlayerProxy isSubentity:isSubentity];
}

- (ShipEntity*)newShipWithName:(NSString*)shipKey usePlayerProxy:(BOOL)usePlayerProxy isSubentity:(BOOL)isSubentity andScaleFactor:(float)scale
{
    return [self cxx_newShipWithName:oo::StdString(shipKey) usePlayerProxy:usePlayerProxy isSubentity:isSubentity andScaleFactor:scale];
}

- (Class)shipClassForShipDictionary:(NSDictionary*)dict
{
    return [self cxx_shipClassForShipDictionary:oo::PListFrom(dict)];
}

- (ShipEntity*)addWreckageFrom:(ShipEntity*)ship withRole:(NSString*)wreckRole at:(HPVector)rpos scale:(GLfloat)scale lifetime:(GLfloat)lifetime
{
    return [self cxx_addWreckageFrom:ship withRole:oo::StdString(wreckRole) at:rpos scale:scale lifetime:lifetime];
}

// Chunk 5 (oo-3rb.224). A nil role or coordinate-system code found no ship / no system, as an
// empty one does (an empty code has the wrong length, as a nil one had).

- (void)addShipWithRole:(NSString*)desc nearRouteOneAt:(double)route_fraction
{
    [self cxx_addShipWithRole:oo::StdString(desc) nearRouteOneAt:route_fraction];
}

- (HPVector)coordinatesForPosition:(HPVector)pos withCoordinateSystem:(NSString*)system returningScalar:(GLfloat*)my_scalar
{
    return [self cxx_coordinatesForPosition:pos withCoordinateSystem:oo::StdString(system) returningScalar:my_scalar];
}

// A nil code printed "(null)" before the (zero) coordinates.
- (NSString*)expressPosition:(HPVector)pos inCoordinateSystem:(NSString*)system
{
    if (system == nil)
        return oo::NSStringFrom(oo::str::format("(null) %.2f %.2f %.2f", 0.0, 0.0, 0.0));
    return oo::NSStringOrNil([self cxx_expressPosition:pos inCoordinateSystem:oo::StdString(system)]);
}

- (HPVector)legacyPositionFrom:(HPVector)pos asCoordinateSystem:(NSString*)system
{
    return [self cxx_legacyPositionFrom:pos asCoordinateSystem:oo::StdString(system)];
}

- (HPVector)coordinatesFromCoordinateSystemString:(NSString*)system_x_y_z
{
    return [self cxx_coordinatesFromCoordinateSystemString:oo::StdString(system_x_y_z)];
}

- (BOOL)addShipWithRole:(NSString*)desc nearPosition:(HPVector)pos withCoordinateSystem:(NSString*)system
{
    return [self cxx_addShipWithRole:oo::StdString(desc) nearPosition:pos withCoordinateSystem:oo::StdString(system)];
}

- (BOOL)addShips:(int)howMany withRole:(NSString*)desc atPosition:(HPVector)pos withCoordinateSystem:(NSString*)system
{
    return [self cxx_addShips:howMany withRole:oo::StdString(desc) atPosition:pos withCoordinateSystem:oo::StdString(system)];
}

- (BOOL)addShips:(int)howMany withRole:(NSString*)desc nearPosition:(HPVector)pos withCoordinateSystem:(NSString*)system
{
    return [self cxx_addShips:howMany withRole:oo::StdString(desc) nearPosition:pos withCoordinateSystem:oo::StdString(system)];
}

- (BOOL)addShips:(int)howMany withRole:(NSString*)desc nearPosition:(HPVector)pos withCoordinateSystem:(NSString*)system withinRadius:(GLfloat)radius
{
    return [self cxx_addShips:howMany withRole:oo::StdString(desc) nearPosition:pos withCoordinateSystem:oo::StdString(system) withinRadius:radius];
}

- (BOOL)addShips:(int)howMany withRole:(NSString*)desc intoBoundingBox:(BoundingBox)bbox
{
    return [self cxx_addShips:howMany withRole:oo::StdString(desc) intoBoundingBox:bbox];
}

- (void)witchspaceShipWithPrimaryRole:(NSString*)role
{
    [self cxx_witchspaceShipWithPrimaryRole:oo::StdString(role)];
}

- (ShipEntity*)spawnShipWithRole:(NSString*)desc near:(Entity*)entity
{
    return [self cxx_spawnShipWithRole:oo::StdString(desc) near:entity];
}

- (OOVisualEffectEntity*)addVisualEffectAt:(HPVector)pos withKey:(NSString*)key
{
    return [self cxx_addVisualEffectAt:pos withKey:oo::StdString(key)];
}

// nil where no ship was added, as before; an immutable array.
- (NSArray*)addShipsAt:(HPVector)pos withRole:(NSString*)role quantity:(unsigned)count withinRadius:(GLfloat)radius asGroup:(BOOL)isGroup
{
    const std::vector<oo::ObjCRef<ShipEntity*>> ships = [self cxx_addShipsAt:pos withRole:oo::StdString(role) quantity:count withinRadius:radius asGroup:isGroup];
    return ships.empty() ? nil : oo::NSArrayFromObjects(ships);
}

- (NSArray*)addShipsToRoute:(NSString*)route withRole:(NSString*)role quantity:(unsigned)count routeFraction:(double)routeFraction asGroup:(BOOL)isGroup
{
    const std::vector<oo::ObjCRef<ShipEntity*>> ships = [self cxx_addShipsToRoute:oo::StdString(route) withRole:oo::StdString(role) quantity:count routeFraction:routeFraction asGroup:isGroup];
    return ships.empty() ? nil : oo::NSArrayFromObjects(ships);
}

- (BOOL)roleIsPirateVictim:(NSString*)role
{
    if (role == nil)
        return NO;
    return [self cxx_roleIsPirateVictim:oo::StdString(role)];
}

// A nil role or category matched nothing, as before.
- (BOOL)role:(NSString*)role isInCategory:(NSString*)category
{
    if (role == nil || category == nil)
        return NO;
    return [self cxx_role:oo::StdString(role) isInCategory:oo::StdString(category)];
}

- (OOJSScript*)getConditionScript:(NSString*)scriptname
{
    if (scriptname == nil)
        return nil;
    return [self cxx_getConditionScript:oo::StdString(scriptname)];
}

// Chunk 6 (oo-3rb.225).

- (NSDictionary*)getPopulatorSettings
{
    return oo::ObjectFromPList([self cxx_getPopulatorSettings]);
}

// A nil setting removes (a null PList); the populator definition object in a block is kept as an
// Object node and handed back as itself.
- (void)setPopulatorSetting:(NSString*)key to:(NSDictionary*)setting
{
    [self cxx_setPopulatorSetting:oo::StdString(key) to:oo::PListFrom(setting)];
}

- (HPVector)locationByCode:(NSString*)code withSun:(OOSunEntity*)sun andPlanet:(OOPlanetEntity*)planet
{
    return [self cxx_locationByCode:oo::StdString(code) withSun:sun andPlanet:planet];
}

// Chunk 7 (oo-3rb.226). A nil commodity or key found nothing, as the old methods did.

- (OOCargoQuantity)maxCargoForShip:(NSString*)desc
{
    return [self cxx_maxCargoForShip:oo::StdString(desc)];
}

- (OOCreditsQuantity)getEquipmentPriceForKey:(NSString*)eq_key
{
    if (eq_key == nil)
        return 0;
    return [self cxx_getEquipmentPriceForKey:oo::StdString(eq_key)];
}

- (NSArray*)getContainersOfGoods:(OOCargoQuantity)how_many scarce:(BOOL)scarce legal:(BOOL)legal
{
    return oo::NSArrayFromObjects([self cxx_getContainersOfGoods:how_many scarce:scarce legal:legal]);
}

- (NSArray*)getContainersOfCommodity:(OOCommodityType)commodity_name how_much:(OOCargoQuantity)how_many
{
    return oo::NSArrayFromObjects([self cxx_getContainersOfCommodity:oo::StdString(commodity_name) how_much:how_many]);
}

- (OOCargoQuantity)getRandomAmountOfCommodity:(OOCommodityType)co_type
{
    if (co_type == nil)
        return 0;
    return [self cxx_getRandomAmountOfCommodity:oo::StdString(co_type)];
}

- (NSString*)displayNameForCommodity:(OOCommodityType)co_type
{
    return oo::NSStringOrNil([self cxx_displayNameForCommodity:oo::StdString(co_type)]);
}

- (NSString*)describeCommodity:(OOCommodityType)co_type amount:(OOCargoQuantity)co_amount
{
    return oo::NSStringOrNil([self cxx_describeCommodity:oo::StdString(co_type) amount:co_amount]);
}

- (NSArray*)equipmentData
{
    return oo::ObjectFromPList([self cxx_equipmentData]);
}

- (NSArray*)equipmentDataOutfitting
{
    return oo::ObjectFromPList([self cxx_equipmentDataOutfitting]);
}

- (void)loadStationMarkets:(NSArray*)marketData
{
    [self cxx_loadStationMarkets:oo::PListFrom(marketData)];
}

// An array of dictionaries, as the old method built it (not mutable: the savegame writer only reads it).
- (NSArray*)getStationMarkets
{
    return oo::ObjectFromPList([self cxx_getStationMarkets]);
}

// Chunk 8 (oo-3rb.227).

// The offers as the old method returned them: an array of dictionaries (their callers only read them).
- (NSArray*)shipsForSaleForSystem:(OOSystemID)s withTL:(OOTechLevelID)specialTL atTime:(OOTimeAbsolute)current_time
{
    return oo::ObjectFromPList([self cxx_shipsForSaleForSystem:s withTL:specialTL atTime:current_time]);
}

- (OOCreditsQuantity)tradeInValueForCommanderDictionary:(NSDictionary*)cmdr_dict
{
    return [self cxx_tradeInValueForCommanderDictionary:oo::PListFrom(cmdr_dict)];
}

// Chunk 9 (oo-3rb.228). A nil role counted nothing and a nil role found no station, as before.

#ifndef NDEBUG
- (NSArray*)entityList
{
    return oo::NSArrayFromObjects([self cxx_entityList]);
}
#endif

- (NSArray*)planets
{
    return oo::NSArrayFromObjects([self cxx_planets]);
}

- (NSArray*)stations
{
    return oo::NSArrayFromObjects([self cxx_stations]);
}

- (NSArray*)wormholes
{
    return oo::NSArrayFromObjects([self cxx_wormholes]);
}

- (StationEntity*)stationWithRole:(NSString*)role andPosition:(HPVector)position
{
    if (role == nil)
        return nil;
    return [self cxx_stationWithRole:oo::StdString(role) andPosition:position];
}

- (NSDictionary*)currentWaypoints
{
    NSMutableDictionary* result = [NSMutableDictionary dictionary];
    for (const auto& [key, waypoint] : [self cxx_currentWaypoints]) {
        if (waypoint.get() != nil)
            [result setObject:waypoint.get() forKey:oo::NSStringFrom(key)];
    }
    return [[result copy] autorelease];
}

- (void)defineWaypoint:(NSDictionary*)definition forKey:(NSString*)key
{
    [self cxx_defineWaypoint:(definition != nil) ? oo::PListFrom(definition) : oo::PList() forKey:oo::StdString(key)];
}

- (NSArray*)entitiesWithinRange:(double)range ofEntity:(Entity*)entity
{
    if (entity == nil)
        return nil;
    return oo::NSArrayFromObjects([self cxx_entitiesWithinRange:range ofEntity:entity]);
}

- (unsigned)countShipsWithRole:(NSString*)role inRange:(double)range ofEntity:(Entity*)entity
{
    if (role == nil)
        return 0;
    return [self cxx_countShipsWithRole:oo::StdString(role) inRange:range ofEntity:entity];
}

- (unsigned)countShipsWithRole:(NSString*)role
{
    return [self countShipsWithRole:role inRange:-1 ofEntity:nil];
}

- (unsigned)countShipsWithPrimaryRole:(NSString*)role inRange:(double)range ofEntity:(Entity*)entity
{
    if (role == nil)
        return 0;
    return [self cxx_countShipsWithPrimaryRole:oo::StdString(role) inRange:range ofEntity:entity];
}

- (unsigned)countShipsWithPrimaryRole:(NSString*)role
{
    return [self countShipsWithPrimaryRole:role inRange:-1 ofEntity:nil];
}

- (NSMutableArray*)findEntitiesMatchingPredicate:(EntityFilterPredicate)predicate
                                       parameter:(void*)parameter
                                         inRange:(double)range
                                        ofEntity:(Entity*)entity
{
    return [[oo::NSArrayFromObjects([self cxx_findEntitiesMatchingPredicate:predicate parameter:parameter inRange:range ofEntity:entity]) mutableCopy] autorelease];
}

- (NSMutableArray*)findShipsMatchingPredicate:(EntityFilterPredicate)predicate
                                    parameter:(void*)parameter
                                      inRange:(double)range
                                     ofEntity:(Entity*)entity
{
    return [[oo::NSArrayFromObjects([self cxx_findShipsMatchingPredicate:predicate parameter:parameter inRange:range ofEntity:entity]) mutableCopy] autorelease];
}

- (NSMutableArray*)findVisualEffectsMatchingPredicate:(EntityFilterPredicate)predicate
                                            parameter:(void*)parameter
                                              inRange:(double)range
                                             ofEntity:(Entity*)entity
{
    return [[oo::NSArrayFromObjects([self cxx_findVisualEffectsMatchingPredicate:predicate parameter:parameter inRange:range ofEntity:entity]) mutableCopy] autorelease];
}

- (NSArray*)listBeaconsWithCode:(NSString*)code
{
    return oo::NSArrayFromObjects([self cxx_listBeaconsWithCode:oo::StdString(code)]);
}

- (void)allShipsDoScriptEvent:(OOJSPropID)event andReactToAIMessage:(NSString*)message
{
    [self cxx_allShipsDoScriptEvent:event andReactToAIMessage:oo::OptionalString(message)];
}

// Chunk 10 (oo-3rb.229). A nil text is std::nullopt (see Universe.h); a nil key finds nothing.

- (NSDictionary*)screenTextureDescriptorForKey:(NSString*)key
{
    return oo::ObjectFromPList([self cxx_screenTextureDescriptorForKey:oo::StdString(key)]);
}

- (void)setScreenTextureDescriptorForKey:(NSString*)key descriptor:(NSDictionary*)desc
{
    [self cxx_setScreenTextureDescriptorForKey:oo::StdString(key) descriptor:(desc != nil) ? oo::PListFrom(desc) : oo::PList()];
}

- (void)displayMessage:(NSString*)text forCount:(OOTimeDelta)count
{
    [self cxx_displayMessage:oo::OptionalString(text) forCount:count];
}

- (void)displayCountdownMessage:(NSString*)text forCount:(OOTimeDelta)count
{
    [self cxx_displayCountdownMessage:oo::OptionalString(text) forCount:count];
}

- (void)addDelayedMessage:(NSString*)text forCount:(OOTimeDelta)count afterDelay:(OOTimeDelta)delay
{
    [self cxx_addDelayedMessage:oo::OptionalString(text) forCount:count afterDelay:delay];
}

- (void)addMessage:(NSString*)text forCount:(OOTimeDelta)count
{
    [self cxx_addMessage:oo::OptionalString(text) forCount:count];
}

- (void)addMessage:(NSString*)text forCount:(OOTimeDelta)count forceDisplay:(BOOL)forceDisplay
{
    [self cxx_addMessage:oo::OptionalString(text) forCount:count forceDisplay:forceDisplay];
}

- (void)addCommsMessage:(NSString*)text forCount:(OOTimeDelta)count
{
    [self cxx_addCommsMessage:oo::OptionalString(text) forCount:count];
}

- (void)addCommsMessage:(NSString*)text forCount:(OOTimeDelta)count andShowComms:(BOOL)showComms logOnly:(BOOL)logOnly
{
    [self cxx_addCommsMessage:oo::OptionalString(text) forCount:count andShowComms:showComms logOnly:logOnly];
}

// A nil text said nothing (espeak: no UTF-8 data).
- (void)startSpeakingString:(NSString*)text
{
    if (text != nil)
        [self cxx_startSpeakingString:oo::StdString(text)];
}

#if OOLITE_ESPEAK
- (NSString*)voiceName:(unsigned int)index
{
    return oo::NSStringOrNil([self cxx_voiceName:index]);
}

- (unsigned int)voiceNumber:(NSString*)name
{
    if (name == nil)
        return UINT_MAX;
    return [self cxx_voiceNumber:oo::StdString(name)];
}
#endif

// Chunk 11 (oo-3rb.230). A nil role asked for the role "" (no ship), after clearing the display, as before.
- (ShipEntity*)makeDemoShipWithRole:(NSString*)role spinning:(BOOL)spinning
{
    return [self cxx_makeDemoShipWithRole:oo::StdString(role) spinning:spinning];
}

// Chunk 12 (oo-3rb.231). The scenario restriction is never nil (its callers pass the save's
// value or one of the SCENARIO_OXP_DEFINITION_* strings).

- (NSString*)useAddOns
{
    return oo::NSStringOrNil([self cxx_useAddOns]);
}

- (BOOL)setUseAddOns:(NSString*)newUse fromSaveGame:(BOOL)saveGame
{
    return [self cxx_setUseAddOns:oo::StdString(newUse) fromSaveGame:saveGame];
}

- (BOOL)setUseAddOns:(NSString*)newUse fromSaveGame:(BOOL)saveGame forceReinit:(BOOL)force
{
    return [self cxx_setUseAddOns:oo::StdString(newUse) fromSaveGame:saveGame forceReinit:force];
}

- (NSDictionary*)gameSettings
{
    return oo::ObjectFromPList([self cxx_gameSettings]);
}

- (NSDictionary*)globalSettings
{
    return oo::ObjectFromPList([self cxx_globalSettings]);
}

@end

// Chunk 10 (oo-3rb.229): the custom sound categories. A nil key found no sound.
@implementation OOSound (OOCustomSoundsFoundationBridge)

+ (id)soundWithCustomSoundKey:(NSString*)key
{
    return [self cxx_soundWithCustomSoundKey:oo::StdString(key)];
}

@end

@implementation OOSoundSource (OOCustomSoundsFoundationBridge)

- (void)playCustomSoundWithKey:(NSString*)key
{
    [self cxx_playCustomSoundWithKey:oo::StdString(key)];
}

@end

// Chunk 1 (oo-3rb.220). DESC() passes string literals: the key is never nil.
NSString* OOLookUpDescriptionPRIV(NSString* key)
{
    return oo::NSStringFrom(cxx_OOLookUpDescriptionPRIV(oo::StdString(key)));
}

NSString* OOLookUpPluralDescriptionPRIV(NSString* key, NSInteger count)
{
    return oo::NSStringFrom(cxx_OOLookUpPluralDescriptionPRIV(oo::StdString(key), count));
}
