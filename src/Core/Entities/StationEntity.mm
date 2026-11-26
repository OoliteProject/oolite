/*

        StationEntity.m

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

#import "StationEntity.h"
#import "DockEntity.h"
#import "OOStringParsing.h"
#import "ShipEntityAI.h"

#import "GameController.h"
#import "HeadUpDisplay.h"
#import "OOConstToString.h"
#import "Universe.h"

#import "OOLegacyScriptWhitelist.h"
#import "OOPlanetEntity.h"
#import "OOQuiriumCascadeEntity.h"
#import "OOShipGroup.h"
#import "PlayerEntityLegacyScriptEngine.h"

#import "AI.h"
#import "OOCharacter.h"

#import "OODebugFlags.h"
#import "OODebugGLDrawing.h"
#import "OODebugStandards.h"
#import "OOJSScript.h"
#import "OOObjCPList.h"
#import "OOPListGameTypes.h"
#import "OOWeakSet.h"
#include "oofnd/Log.hpp"
#include "oofnd/String.hpp"

// -oo_stringForKey:'s value without the Foundation type (proposed ADR-0043): a string as is, a
// number's -stringValue, anything else (or nothing) nullopt, as it gave nil.
namespace {

std::optional<std::string> OptionalStringValue(const oo::PList* value)
{
    if (value == nullptr)
        return std::nullopt;
    if (const std::string* string = value->getIf<std::string>())
        return *string;
    if (value->isNumber())
        return oo::plist_get::numberStringValue(*value);
    return std::nullopt;
}

} // namespace

@interface StationEntity (OOPrivate)

- (void)pullInShipIfPermitted:(ShipEntity*)ship;
- (void)addShipToStationCount:(ShipEntity*)ship;

- (void)addShipToLaunchQueue:(ShipEntity*)ship withPriority:(BOOL)priority;
- (unsigned)countOfShipsInLaunchQueueWithPrimaryRole:(const std::string&)role;

- (oo::PList)holdPositionInstructionForShip:(ShipEntity*)ship;

@end

@implementation StationEntity

/* Override ShipEntity: stations of CLASS_ROCK or CLASS_CARGO are not automatically unpiloted. */
- (BOOL)isUnpiloted
{
    return [self isExplicitlyUnpiloted] || [self isHulk];
}

- (OOTechLevelID)equivalentTechLevel
{
    if (equivalentTechLevel == NSNotFound) {
        return [UNIVERSE cxx_currentSystemData].get<int>(std::string(KEY_TECHLEVEL));
    } else {
        return equivalentTechLevel;
    }
}

- (void)setEquivalentTechLevel:(OOTechLevelID)value
{
    equivalentTechLevel = value;
}

- (Vector)virtualPortDimensions
{
    return port_dimensions;
}

- (DockEntity*)playerReservedDock
{
    return player_reserved_dock;
}

- (HPVector)beaconPosition
{
    double buoy_distance = 10000.0; // distance from station entrance
    Vector v_f = vector_forward_from_quaternion([self orientation]);
    HPVector result = HPvector_add([self position], vectorToHPVector(vector_multiply_scalar(v_f, buoy_distance)));

    return result;
}

- (float)equipmentPriceFactor
{
    return equipmentPriceFactor;
}

- (OOCargoQuantity)marketCapacity
{
    return marketCapacity;
}

- (oo::PList)cxx_marketDefinition
{
    return marketDefinition;
}

- (std::optional<std::string>)cxx_marketScriptName
{
    return marketScriptName;
}

- (BOOL)marketMonitored
{
    if (self == [UNIVERSE station]) {
        return YES;
    }
    return marketMonitored;
}

- (BOOL)marketBroadcast
{
    if (self == [UNIVERSE station]) {
        return YES;
    }
    return marketBroadcast;
}

- (OOCreditsQuantity)legalStatusOfManifest:(OOCommodityMarket*)manifest export:(BOOL)isExport
{
    OOCreditsQuantity penalty, status = 0;
    OOCommodityMarket* market = [self localMarket];
    for (const std::string& good : [market goods]) {
        if (isExport) {
            penalty = [market cxx_exportLegalityForGood:good];
        } else {
            penalty = [market cxx_importLegalityForGood:good];
        }
        status += penalty * [manifest cxx_quantityForGood:good];
    }
    return status;
}

- (OOCommodityMarket*)localMarket
{
    if (self == [UNIVERSE station]) {
        // main stations use the system market
        // just return a reference
        return [UNIVERSE commodityMarket];
    }
    if (!localMarket) {
        [self initialiseLocalMarket];
    }
    return localMarket;
}

- (void)cxx_setLocalMarket:(const oo::PList&)some_market
{
    [[self localMarket] cxx_loadStationAmounts:some_market];
}

- (oo::PList)cxx_localMarketForScripting
{
    return [[self localMarket] dictionaryForScripting];
}

- (void)cxx_setPrice:(OOCreditsQuantity)price forCommodity:(const std::string&)commodity
{
    [[self localMarket] cxx_setPrice:price forGood:commodity];
}

- (void)cxx_setQuantity:(OOCargoQuantity)quantity forCommodity:(const std::string&)commodity
{
    [[self localMarket] cxx_setQuantity:quantity forGood:commodity];
}

- (std::vector<oo::PList>*)cxx_localShipyard
{
    return localShipyard ? &*localShipyard : nullptr;
}

- (void)cxx_setLocalShipyard:(const std::vector<oo::PList>&)some_market
{
    localShipyard = some_market;
}

- (std::map<std::string, oo::ObjCRef<OOJSInterfaceDefinition*>, std::less<>>*)cxx_localInterfaces
{
    return &localInterfaces;
}

- (void)cxx_setInterfaceDefinition:(OOJSInterfaceDefinition*)definition forKey:(const std::string&)key
{
    if (definition == nil) {
        localInterfaces.erase(key);
    } else {
        localInterfaces[key] = oo::ObjCRef<OOJSInterfaceDefinition*>(definition);
    }
}

- (OOCommodityMarket*)initialiseLocalMarket
{
    DESTROY(localMarket);
    localMarket = [[[UNIVERSE commodities] generateMarketForStation:self] retain];
    return localMarket;
}

- (void)setPlanet:(OOPlanetEntity*)planet_entity
{
    if (planet_entity)
        planet = [planet_entity universalID];
    else
        planet = NO_TARGET;
}

- (OOPlanetEntity*)planet
{
    return [UNIVERSE entityForUniversalID:planet];
}

- (unsigned)countOfDockedContractors
{
    return max_scavengers > scavengers_launched ? max_scavengers - scavengers_launched : 0;
}

- (unsigned)countOfDockedPolice
{
    return max_police > defenders_launched ? max_police - defenders_launched : 0;
}

- (unsigned)countOfDockedDefenders
{
    return max_defense_ships > defenders_launched ? max_defense_ships - defenders_launched : 0;
}

- (std::vector<oo::ObjCRef<DockEntity*>>)cxx_dockSubEntities
{
    std::vector<oo::ObjCRef<DockEntity*>> result;
    for (const auto& subRef : [self subEntities]) {
        Entity* sub = subRef.get();
        if (![sub isDock])
            continue;
        result.push_back(oo::ObjCRef<DockEntity*>((DockEntity*)sub));
    }
    return result;
}

- (void)sanityCheckShipsOnApproach
{

    unsigned soa = 0;
    for (const oo::ObjCRef<DockEntity*>& dock : [self cxx_dockSubEntities]) {
        DockEntity* sub = dock.get();
        soa += [sub pruneAndCountShipsOnApproach];
    }

    if (soa == 0) {
        // if all docks have no ships on approach
        [shipAI message:"DOCKING_COMPLETE"];
        [self doScriptEvent:OOJSID("stationDockingQueuesAreEmpty")];
    }
}

// only used by player - everything else ends up in a Dock's launch queue
- (void)launchShip:(ShipEntity*)ship
{

    // try to find an unused dock first
    for (const oo::ObjCRef<DockEntity*>& dock : [self cxx_dockSubEntities]) {
        DockEntity* sub = dock.get();
        if ([sub allowsLaunching] && [sub countOfShipsInLaunchQueue] == 0) {
            [sub launchShip:ship];
            return;
        }
    }
    // otherwise any launchable dock will do
    for (const oo::ObjCRef<DockEntity*>& dock : [self cxx_dockSubEntities]) {
        DockEntity* sub = dock.get();
        if ([sub allowsLaunching]) {
            [sub launchShip:ship];
            return;
        }
    }

    // ship has no launch docks specified; just use the last one
    // (the enumerator loop this replaced left its variable nil when it ran out, so this never fires)
    DockEntity* sub = nil;
    if (sub != nil) {
        [sub launchShip:ship];
        return;
    }
    // guaranteed to always be a dock as virtual dock will suffice
}

// Exposed to AI
- (void)abortAllDockings
{
    for (const oo::ObjCRef<DockEntity*>& dock : [self cxx_dockSubEntities]) {
        DockEntity* sub = dock.get();
        [sub abortAllDockings];
    }

    // -makeObjectsPerformSelector:withObject: of the live ships on hold, in order
    for (const oo::ObjCRef<id>& holdRef : [_shipsOnHold cxx_objectEnumerator])
        [static_cast<ShipEntity*>(holdRef.get()) sendAIMessage:"DOCKING_ABORTED"];
    for (const oo::ObjCRef<id>& holdRef : [_shipsOnHold cxx_objectEnumerator]) {
        ShipEntity* hold = static_cast<ShipEntity*>(holdRef.get());
        [hold doScriptEvent:OOJSID("stationWithdrewDockingClearance")];
    }

    PlayerEntity* player = PLAYER;

    if ([player getTargetDockStation] == self && [player getDockingClearanceStatus] >= DOCKING_CLEARANCE_STATUS_REQUESTED) {
        // then docking clearance is requested but hasn't been cancelled
        // yet by a DockEntity
        [self cxx_sendExpandedMessage:"[station-docking-clearance-abort-cancelled]" toShip:player];
        [player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
        [player doScriptEvent:OOJSID("stationWithdrewDockingClearance")];
    }

    [_shipsOnHold removeAllObjects];

    [shipAI message:"DOCKING_COMPLETE"];
    [self doScriptEvent:OOJSID("stationDockingQueuesAreEmpty")];
}

- (void)autoDockShipsOnHold
{
    for (const oo::ObjCRef<id>& shipRef : [_shipsOnHold cxx_objectEnumerator]) {
        ShipEntity* ship = static_cast<ShipEntity*>(shipRef.get());
        [self pullInShipIfPermitted:ship];
    }

    [_shipsOnHold removeAllObjects];
}

- (void)autoDockShipsOnApproach
{
    for (const oo::ObjCRef<DockEntity*>& dock : [self cxx_dockSubEntities]) {
        DockEntity* sub = dock.get();
        [sub autoDockShipsOnApproach];
    }

    [self autoDockShipsOnHold];

    [shipAI message:"DOCKING_COMPLETE"];
    [self doScriptEvent:OOJSID("stationDockingQueuesAreEmpty")];
}

- (Vector)portUpVectorForShip:(ShipEntity*)ship
{
    for (const oo::ObjCRef<DockEntity*>& dock : [self cxx_dockSubEntities]) {
        DockEntity* sub = dock.get();
        if ([sub shipIsInDockingQueue:ship]) {
            return [sub portUpVectorForShipsBoundingBox:[ship totalBoundingBox]];
        }
    }
    return kZeroVector;
}

oo::PList cxx_OOMakeDockingInstructions(StationEntity* station, HPVector coords, float speed, float range, const std::optional<std::string>& ai_message, const std::optional<std::string>& comms_message, BOOL match_rotation, int docking_stage)
{
    oo::PList::Dict acc;
    // destination as OOPropertyListFromHPVector built it (doubles); speed and range as -oo_setFloat:
    // stored them (+numberWithDouble:); docking_stage as -oo_setInteger: (signed)
    acc["destination"] = oo::PList(oo::PList::Dict { { "x", oo::PList(coords.x) }, { "y", oo::PList(coords.y) }, { "z", oo::PList(coords.z) } });
    acc["speed"] = oo::PList(static_cast<double>(speed));
    acc["range"] = oo::PList(static_cast<double>(range));
    acc["station"] = oo::PListObject([[station weakRetain] autorelease]);
    acc["match_rotation"] = oo::PList(static_cast<bool>(match_rotation));
    acc["docking_stage"] = oo::PList::signedInteger(docking_stage);
    if (ai_message) {
        acc["ai_message"] = oo::PList(*ai_message);
    }
    if (comms_message) {
        acc["comms_message"] = oo::PList(*comms_message);
    }
    return oo::PList(std::move(acc));
}

// this method does initial traffic control, before passing the ship
// to an appropriate dock for docking coordinates and instructions.
// used for NPCs, and the player when they use the docking computer
- (oo::PList)dockingInstructionsForShip:(ShipEntity*)ship
{
    if (ship == nil)
        return oo::PList();

    [self doScriptEvent:OOJSID("stationReceivedDockingRequest") withArgument:ship];

    if ([ship isPlayer]) {
        player_reserved_dock = nil; // clear any dock reservation for manual docking
    }

    if ([ship isPlayer] && [ship legalStatus] > 50) // note: non-player fugitives dock as normal
    {
        // refuse docking to the fugitive player
        return cxx_OOMakeDockingInstructions(self, [ship position], 0, 100, "DOCKING_REFUSED", "[station-docking-refused-to-fugitive]", NO, -1);
    }

    if (magnitude2(velocity) > 1.0 || fabs(flightPitch) > 0.01 || fabs(flightYaw) > 0.01) {
        // no docking while station is moving, pitching or yawing
        return [self holdPositionInstructionForShip:ship];
    }
    PlayerEntity* player = PLAYER;
    BOOL player_is_ahead = (![ship isPlayer] && [player getDockingClearanceStatus] == DOCKING_CLEARANCE_STATUS_REQUESTED && (self == [player getTargetDockStation]));

    DockEntity* chosenDock = nil;
    std::optional<std::string> docking; // nullopt: no dock asked yet (was nil)
    NSUInteger queue = 100;

    BOOL alldockstoosmall = YES;
    for (const oo::ObjCRef<DockEntity*>& dock : [self cxx_dockSubEntities]) {
        DockEntity* sub = dock.get();
        if ([sub shipIsInDockingQueue:ship]) {
            // if already claimed a docking queue, use that one
            chosenDock = sub;
            alldockstoosmall = NO;
            break;
        }
        if (player_is_ahead) {
            // can't allocate a new queue while player is manually docking
            continue;
        }
        if (sub != player_reserved_dock || [ship isPlayer]) {
            docking = [sub canAcceptShipForDocking:ship];
            if (docking == "DOCK_CLOSED") {
                JSContext* context = OOJSAcquireContext();
                OOJSVal rval = OOJSUndefinedValue();
                OOJSVal args[] = { OOJSValueFromNativeObject(context, sub),
                    OOJSValueFromNativeObject(context, ship) };
                BOOL tempreject = NO;

                BOOL OK = [[self script] callMethod:OOJSID("willOpenDockingPortFor") inContext:context withArguments:args count:2 result:&rval];
                if (OK)
                    tempreject = OOJSValueToBOOL(context, rval);
                if (!OK)
                    tempreject = NO; // default to permreject
                if (tempreject) {
                    docking = "TRY_AGAIN_LATER";
                } else {
                    docking = "TOO_BIG_TO_DOCK";
                }

                OOJSFreeValue(context, rval);
                OOJSFreeValue(context, args[0]);
                OOJSFreeValue(context, args[1]);
                OOJSRelinquishContext(context);
            }

            if (docking == "DOCKING_POSSIBLE" && [sub countOfShipsInDockingQueue] < queue) {
                // try to select the dock with the fewest ships already enqueued
                chosenDock = sub;
                queue = [sub countOfShipsInDockingQueue];
                alldockstoosmall = NO;
            } else if (!(docking == "TOO_BIG_TO_DOCK")) {
                alldockstoosmall = NO;
            }
        } else {
            alldockstoosmall = NO;
        }
    }
    if (chosenDock == nil) {
        if (player_is_ahead || (docking == "TOO_BIG_TO_DOCK" && !alldockstoosmall) || !docking) {
            // either player is manually docking and we can't allocate new docks,
            // or the last dock was too small, and there may be an acceptable one
            // not tested yet or returning TRY_AGAIN_LATER
            docking = "TRY_AGAIN_LATER";
        }
        // no docks accept this ship (or the player is blocking them)
        return cxx_OOMakeDockingInstructions(self, [ship position], 200, 100, docking, std::nullopt, NO, -1);
    }

    // rolling is okay for some
    if (fabs(flightRoll) > 0.01 && [chosenDock isOffCentre]) {
        return [self holdPositionInstructionForShip:ship];
    }

    // we made it through holding!
    [_shipsOnHold removeObject:ship];

    [shipAI cxx_reactToMessage:"DOCKING_REQUESTED" context:"requestDockingCoordinates"]; // react to the request
    [self doScriptEvent:OOJSID("stationAcceptedDockingRequest") withArgument:ship];

    return [chosenDock dockingInstructionsForShip:ship];
}

- (oo::PList)holdPositionInstructionForShip:(ShipEntity*)ship
{
    if (![_shipsOnHold containsObject:ship]) {
        [self cxx_sendExpandedMessage:"[station-acknowledges-hold-position]" toShip:ship];
        [_shipsOnHold addObject:ship];
    }

    return cxx_OOMakeDockingInstructions(self, [ship position], 0, 100, "HOLD_POSITION", std::nullopt, NO, -1);
}

- (void)abortDockingForShip:(ShipEntity*)ship
{
    [ship sendAIMessage:"DOCKING_ABORTED"];
    [ship doScriptEvent:OOJSID("stationWithdrewDockingClearance")];

    [_shipsOnHold removeObject:ship];

    for (const oo::ObjCRef<DockEntity*>& dock : [self cxx_dockSubEntities]) {
        DockEntity* sub = dock.get();
        [sub abortDockingForShip:ship];
    }

    if ([ship isPlayer]) {
        player_reserved_dock = nil;
    }

    [self sanityCheckShipsOnApproach];
}

//////////////////////////////////////////////// from superclass

- (id)cxx_initWithKey:(const std::string&)key definition:(const oo::PList&)dict
{
    OOJS_PROFILE_ENTER

    self = [super cxx_initWithKey:key definition:dict];
    if (self != nil) {
        isStation = YES;
        _shipsOnHold = [[OOWeakSet alloc] init];
        hasBreakPattern = YES;
    }
    return self;

    OOJS_PROFILE_EXIT
}

- (void)dealloc
{
    DESTROY(_shipsOnHold);
    DESTROY(localMarket);
    //	DESTROY(localPassengers);
    //	DESTROY(localContracts);

    [super dealloc];
}

- (BOOL)setUpShipFromDictionary:(const oo::PList&)dict
{
    OOJS_PROFILE_ENTER

    isShip = YES;
    isStation = YES;
    alertLevel = STATION_ALERT_LEVEL_GREEN;

    port_radius = dict.get<oo::NonNegative<double>>("port_radius", 500.0);

    // port_dimensions is deprecated
    port_dimensions = make_vector(69, 69, 250);
    const std::optional<std::string> portDimensionsStr = OptionalStringValue(dict.find("port_dimensions")); // -oo_stringForKey:
    if (portDimensionsStr) {
        cxx_OOStandardsDeprecated("The port_dimensions key is deprecated");
        if (!OOEnforceStandards()) {
            const std::vector<std::string> tokens = oo::str::split(*portDimensionsStr, "x");
            if (tokens.size() == 3) {
                // -floatValue
                port_dimensions = make_vector((float)oo::str::doubleValue(tokens[0]),
                    (float)oo::str::doubleValue(tokens[1]),
                    (float)oo::str::doubleValue(tokens[2]));
            }
        }
    }

    if (![super setUpShipFromDictionary:dict])
        return NO;

    equivalentTechLevel = dict.get<NSUInteger>("equivalent_tech_level", NSNotFound);
    max_scavengers = dict.get<unsigned int>("max_scavengers", 3);
    max_defense_ships = dict.get<unsigned int>("max_defense_ships", 3);
    max_police = dict.get<unsigned int>("max_police", STATION_MAX_POLICE);
    equipmentPriceFactor = dict.get<oo::NonNegative<float>>("equipment_price_factor", 1.0);
    equipmentPriceFactor = fmax(equipmentPriceFactor, 0.5f);
    hasNPCTraffic = (unsigned char)OOFuzzyBooleanFromPList(dict.find("has_npc_traffic"), (maxFlightSpeed == 0)); // carriers default to NO
    hasPatrolShips = OOFuzzyBooleanFromPList(dict.find("has_patrol_ships"), NO);
    suppress_arrival_reports = (unsigned char)dict.get<bool>("suppress_arrival_reports", NO);
    [self cxx_setAllegiance:OptionalStringValue(dict.find("allegiance"))];

    marketCapacity = dict.get<unsigned int>("market_capacity", MAIN_SYSTEM_MARKET_LIMIT);
    const oo::PList* marketDefinitionValue = dict.get<oo::PList::Array>("market_definition");
    marketDefinition = (marketDefinitionValue != nullptr) ? *marketDefinitionValue : oo::PList(); // oo_arrayForKey:
    marketScriptName = OptionalStringValue(dict.find("market_script"));
    marketMonitored = (unsigned char)dict.get<bool>("market_monitored", NO);
    marketBroadcast = (unsigned char)dict.get<bool>("market_broadcast", YES);

    // Non main stations may have requiresDockingClearance set to yes as a result of the code below,
    // but this variable should be irrelevant for them, as they do not make use of it anyway.
    requiresDockingClearance = (unsigned char)dict.get<bool>("requires_docking_clearance", [UNIVERSE dockingClearanceProtocolActive]);

    allowsFastDocking = (unsigned char)dict.get<bool>("allows_fast_docking", NO);

    allowsAutoDocking = (unsigned char)dict.get<bool>("allows_auto_docking", YES);

    allowsSaving = [UNIVERSE deterministicPopulation];

    interstellarUndockingAllowed = (unsigned char)dict.get<bool>("interstellar_undocking", NO);

    double unitime = [UNIVERSE getTime];

    if ([self hasNPCTraffic]) // removed the 'isRotatingStation' restriction.
    {
        docked_shuttles = ranrot_rand() & 3; // 0..3;
        shuttle_launch_interval = 15.0 * 60.0; // every 15 minutes
        last_shuttle_launch_time = unitime - (ranrot_rand() & 63) * shuttle_launch_interval / 60.0;

        docked_traders = 3 + (ranrot_rand() & 7); // 1..3;
        trader_launch_interval = 3600.0 / docked_traders; // every few minutes
        last_trader_launch_time = unitime + 60.0 - trader_launch_interval; // in one minute's time
    } else {
        docked_shuttles = 0;
        docked_traders = 0; // 1..3;
    }

    patrol_launch_interval = 300.0; // 5 minutes
    last_patrol_report_time = unitime - patrol_launch_interval;

    if (![self cxx_crew].has_value()) {
        [self cxx_setSingleCrewWithRole:"police"];
    }

    if ([self group] == nil) {
        [self setGroup:[self stationGroup]];
    }
    return YES;

    OOJS_PROFILE_EXIT
}

// used to set up a virtual dock if necessary
- (BOOL)setUpSubEntities
{
    if (![super setUpSubEntities]) {
        return NO;
    }

#ifndef NDEBUG
    for (const auto& subRef : [self subEntities]) {
        Entity* sub = subRef.get();
        if (![sub isShip])
            continue;
        ShipEntity* subEntity = (ShipEntity*)sub;
        if ([subEntity isStation]) {
            OO_LOG("setup.ship.badType.subentities", "Subentity {} ({}) of station {} is itself a StationEntity. This is an internal error - please report it. ", oo::DescriptionOf(subEntity), [subEntity cxx_shipDataKey].value_or("(null)"), [self displayName].value_or("(null)"));
        }
    }
#endif

    // and now check for docks
    if (![self cxx_dockSubEntities].empty()) {
        return YES;
    }

    cxx_OOStandardsDeprecated(oo::str::format("No docks set up for %s", oo::DescriptionOf(self).c_str()));
    OO_LOG("ship.setup.docks", "No docks set up for {}, making virtual dock", oo::DescriptionOf(self));

    // no real docks, make a virtual one
    // position and orientation as OOPropertyListFromVector / OOPropertyListFromQuaternion built them (floats)
    Vector dockPosition = make_vector(0, 0, port_radius);
    oo::PList::Dict virtualDockDict;
    virtualDockDict["type"] = oo::PList("standard");
    virtualDockDict["subentity_key"] = oo::PList("oolite-dock-virtual");
    virtualDockDict["position"] = oo::PList(oo::PList::Dict { { "x", oo::PList::singleReal(dockPosition.x) }, { "y", oo::PList::singleReal(dockPosition.y) }, { "z", oo::PList::singleReal(dockPosition.z) } });
    virtualDockDict["orientation"] = oo::PList(oo::PList::Dict { { "w", oo::PList::singleReal(kIdentityQuaternion.w) }, { "x", oo::PList::singleReal(kIdentityQuaternion.x) }, { "y", oo::PList::singleReal(kIdentityQuaternion.y) }, { "z", oo::PList::singleReal(kIdentityQuaternion.z) } });
    virtualDockDict["is_dock"] = oo::PList(true);
    virtualDockDict["dock_label"] = oo::PList("the docking bay");
    virtualDockDict["allow_docking"] = oo::PList(true);
    virtualDockDict["disallowed_docking_collides"] = oo::PList(false);
    virtualDockDict["allow_launching"] = oo::PList(true);
    virtualDockDict["_is_virtual_dock"] = oo::PList(true);

    if (![self cxx_setUpOneStandardSubentity:oo::PList(std::move(virtualDockDict)) asTurret:NO]) {
        return NO;
    }
    return YES;
}

- (BOOL)shipIsInDockingCorridor:(ShipEntity*)ship
{
    if (![ship isShip])
        return NO;
    if ([ship isPlayer] && [ship status] == STATUS_DEAD)
        return NO;

    for (const oo::ObjCRef<DockEntity*>& dock : [self cxx_dockSubEntities]) {
        DockEntity* sub = dock.get();
        if ([sub shipIsInDockingCorridor:ship]) {
            return YES;
        }
    }
    return NO;
}

- (void)pullInShipIfPermitted:(ShipEntity*)ship
{
    [ship enterDock:self]; // dock performs permitted checks
}

- (BOOL)dockingCorridorIsEmpty
{
    if (!UNIVERSE)
        return NO;

    for (const oo::ObjCRef<DockEntity*>& dock : [self cxx_dockSubEntities]) {
        DockEntity* sub = dock.get();
        if ([sub dockingCorridorIsEmpty]) {
            return YES; // if any are
        }
    }
    return NO;
}

- (void)clearDockingCorridor
{
    if (!UNIVERSE)
        return;

    for (const oo::ObjCRef<DockEntity*>& dock : [self cxx_dockSubEntities]) {
        DockEntity* sub = dock.get();
        [sub clearDockingCorridor];
    }

    return;
}

- (void)update:(OOTimeDelta)delta_t
{
    BOOL isRockHermit = (scanClass == CLASS_ROCK);
    BOOL isMainStation = (self == [UNIVERSE station]);

    double unitime = [UNIVERSE getTime];

    if (!isMainStation && localMarket == nil) {
        [self initialiseLocalMarket];
    }

    [super update:delta_t];

    PlayerEntity* player = PLAYER;

    BOOL isDockingStation = (self == [player getTargetDockStation]);
    if (isDockingStation && [player status] == STATUS_IN_FLIGHT) {
        if ([player getDockingClearanceStatus] >= DOCKING_CLEARANCE_STATUS_GRANTED) {
            if (last_launch_time - 30 < unitime && [player getDockingClearanceStatus] != DOCKING_CLEARANCE_STATUS_TIMING_OUT) {
                [self cxx_sendExpandedMessage:"[station-docking-clearance-about-to-expire]" toShip:player];
                [player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_TIMING_OUT];
            } else if (last_launch_time < unitime) {
                [self cxx_sendExpandedMessage:"[station-docking-clearance-expired]" toShip:player];
                [player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE]; // Docking clearance for player has expired.
                [player doScriptEvent:OOJSID("playerDockingClearanceExpired")];
                if ([self currentlyInDockingQueues] == 0) {
                    [[self getAI] message:"DOCKING_COMPLETE"];
                    [self doScriptEvent:OOJSID("stationDockingQueuesAreEmpty")];
                }
                player_reserved_dock = nil;
            }
        }

        else if ([player getDockingClearanceStatus] == DOCKING_CLEARANCE_STATUS_NOT_REQUIRED) {
            if (last_launch_time < unitime) {
                [player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
                if ([self currentlyInDockingQueues] == 0) {
                    [[self getAI] message:"DOCKING_COMPLETE"];
                    [self doScriptEvent:OOJSID("stationDockingQueuesAreEmpty")];
                }
            }
        }

        else if ([player getDockingClearanceStatus] == DOCKING_CLEARANCE_STATUS_REQUESTED &&
            [self hasClearDock]) {
            DockEntity* dock = [self selectDockForDocking];
            last_launch_time = unitime + DOCKING_CLEARANCE_WINDOW;
            if ([self hasMultipleDocks]) {
                [self cxx_sendExpandedMessage:oo::str::formatRuntime(OO_DESC("station-docking-clearance-granted-in-@-until-@"),
                                                  { [dock displayName].value_or("(null)"),
                                                      cxx_ClockToString([player clockTime] + DOCKING_CLEARANCE_WINDOW, NO) })
                                       toShip:player];
            } else {
                [self cxx_sendExpandedMessage:oo::str::formatRuntime(OO_DESC("station-docking-clearance-granted-until-@"),
                                                  { cxx_ClockToString([player clockTime] + DOCKING_CLEARANCE_WINDOW, NO) })
                                       toShip:player];
            }
            player_reserved_dock = dock;
            [player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_GRANTED];
            [player doScriptEvent:OOJSID("playerDockingClearanceGranted")];
        }
    }

    if (approach_spacing > 0.0) {
        approach_spacing -= delta_t * 10.0; // reduce by 10 m/s
        if (approach_spacing < 0.0)
            approach_spacing = 0.0;
    }

    /* JSAI: JS-based AIs handle their own traffic either alone or
     * in conjunction with the system repopulator */
    if (![self hasNewAI]) {
        // begin launch of shuttles, traders, patrols
        if ((docked_shuttles > 0) && (!isRockHermit)) {
            if (unitime > last_shuttle_launch_time + shuttle_launch_interval) {
                if (([self hasNPCTraffic]) && (aegis_status != AEGIS_NONE)) {
                    [self launchShuttle];
                }
                last_shuttle_launch_time = unitime;
            }
        }

        if ((docked_traders > 0) && (!isRockHermit)) {
            if (unitime > last_trader_launch_time + trader_launch_interval) {
                if ([self hasNPCTraffic]) {
                    [self launchIndependentShip:"trader"];
                    docked_traders--;
                }
                last_trader_launch_time = unitime;
            }
        }

        // testing patrols
        if (unitime > (last_patrol_report_time + patrol_launch_interval)) {
            if (!((isMainStation && [self hasNPCTraffic]) || hasPatrolShips) || [self launchPatrol] != nil)
                last_patrol_report_time = unitime;
        }
    }
}

- (void)clear
{
    for (const oo::ObjCRef<DockEntity*>& dock : [self cxx_dockSubEntities]) {
        DockEntity* sub = dock.get();
        [sub clear];
    }

    [_shipsOnHold removeAllObjects];
}

- (BOOL)hasMultipleDocks
{
    return [self cxx_dockSubEntities].size() > 1;
}

// is there a dock free for the player to dock manually?
// not used for NPCs
- (BOOL)hasClearDock
{
    for (const oo::ObjCRef<DockEntity*>& dock : [self cxx_dockSubEntities]) {
        DockEntity* sub = dock.get();
        if ([sub allowsDocking] && [sub countOfShipsInLaunchQueue] == 0 && [sub countOfShipsInDockingQueue] == 0) {
            if ([sub canAcceptShipForDocking:PLAYER] == "DOCKING_POSSIBLE") {
                return YES;
            }
        }
    }
    return NO;
}

- (BOOL)hasEligibleDock
{
    for (const oo::ObjCRef<DockEntity*>& dock : [self cxx_dockSubEntities]) {
        DockEntity* sub = dock.get();
        // TRY_AGAIN_LATER in this context means "ships launching now"
        if ([sub allowsDocking] && ([sub canAcceptShipForDocking:PLAYER] == "DOCKING_POSSIBLE" || [sub canAcceptShipForDocking:PLAYER] == "TRY_AGAIN_LATER")) {
            return YES;
        }
    }
    return NO;
}

// is there any dock which may launch ships?
- (BOOL)hasLaunchDock
{
    for (const oo::ObjCRef<DockEntity*>& dock : [self cxx_dockSubEntities]) {
        DockEntity* sub = dock.get();
        if ([sub allowsLaunching]) {
            return YES;
        }
    }
    return NO;
}

// only used to pick a dock for the player
- (DockEntity*)selectDockForDocking
{
    for (const oo::ObjCRef<DockEntity*>& dock : [self cxx_dockSubEntities]) {
        DockEntity* sub = dock.get();
        if ([sub allowsDocking] && [sub countOfShipsInLaunchQueue] == 0 && [sub countOfShipsInDockingQueue] == 0) {
            return sub;
        }
    }
    return nil;
}

- (void)addShipToLaunchQueue:(ShipEntity*)ship withPriority:(BOOL)priority
{
    unsigned threshold = 0;

    // quickest launch if we assign ships to those bays with no incoming ships
    // and spread the ships evenly around those bays
    // much easier if the station has at least one launch-only dock
    while (threshold < 16) {
        for (const oo::ObjCRef<DockEntity*>& dock : [self cxx_dockSubEntities]) {
            DockEntity* sub = dock.get();
            if (sub != player_reserved_dock) {
                if ([sub countOfShipsInDockingQueue] == 0) {
                    if ([sub allowsLaunching] && [sub countOfShipsInLaunchQueue] <= threshold) {
                        if ([sub allowsLaunchingOf:ship]) {
                            [sub addShipToLaunchQueue:ship withPriority:priority];
                            return;
                        }
                    }
                }
            }
        }
        threshold++;
    }
    // if we get this far, all docks have at least some incoming traffic.
    // usually most efficient (since launching is far faster than docking)
    // to assign all ships to the *same* dock with the smallest incoming queue
    // rather than to try spreading them out across several queues
    // also stops escorts being launched before their mothership
    threshold = 0;
    while (threshold < 16) {
        for (const oo::ObjCRef<DockEntity*>& dock : [self cxx_dockSubEntities]) {
            DockEntity* sub = dock.get();
            /* so this time as long as it allows launching only check
             * the docking queue size so long as enumerator order is
             * deterministic, this will assign every launch this
             * update to the same dock (edge case where new docking
             * ship appears in the middle, probably not a problem) */
            if ([sub allowsLaunching] && [sub countOfShipsInDockingQueue] <= threshold) {
                if ([sub allowsLaunchingOf:ship]) {
                    [sub addShipToLaunchQueue:ship withPriority:priority];
                    return;
                }
            }
        }
        threshold++;
    }

    OO_LOG("station.launchShip.failed", "Cancelled launch for a {} with role {}, as the {} has too many ships in its launch queue(s) or no suitable launch docks.",
        [ship displayName].value_or("(null)"), [ship cxx_primaryRole].value_or("(null)"), [self displayName].value_or("(null)"));
}

- (unsigned)countOfShipsInLaunchQueueWithPrimaryRole:(const std::string&)role
{
    unsigned result = 0;
    for (const oo::ObjCRef<DockEntity*>& dock : [self cxx_dockSubEntities]) {
        DockEntity* sub = dock.get();
        result += [sub countOfShipsInLaunchQueueWithPrimaryRole:role];
    }
    return result;
}

- (BOOL)fitsInDock:(ShipEntity*)ship
{
    return [self fitsInDock:ship andLogNoFit:YES];
}

- (BOOL)fitsInDock:(ShipEntity*)ship andLogNoFit:(BOOL)logNoFit
{
    if (![ship isShip])
        return NO;

    for (const oo::ObjCRef<DockEntity*>& dock : [self cxx_dockSubEntities]) {
        DockEntity* sub = dock.get();
        if ([sub allowsLaunchingOf:ship]) {
            return YES;
        }
    }

    if (logNoFit)
        OO_LOG("station.launchShip.failed", "Cancelled launch for a {} with role {}, as it is too large for the docking port of the {}.",
            [ship displayName].value_or("(null)"), [ship cxx_primaryRole].value_or("(null)"), oo::DescriptionOf(self));
    return NO;
}

- (void)noteDockedShip:(ShipEntity*)ship
{
    if (ship == nil)
        return;

    PlayerEntity* player = PLAYER;
    // set last launch time to avoid clashes with outgoing ships
    if ([player getDockingClearanceStatus] != DOCKING_CLEARANCE_STATUS_GRANTED) {
        // avoid interfering with docking clearance on another bay
        last_launch_time = [UNIVERSE getTime];
    }
    [self addShipToStationCount:ship];

    for (const oo::ObjCRef<DockEntity*>& dock : [self cxx_dockSubEntities]) {
        DockEntity* sub = dock.get();
        [sub noteDockingForShip:ship];
    }
    [self sanityCheckShipsOnApproach];

    [self doScriptEvent:OOJSID("otherShipDocked") withArgument:ship];

    BOOL isDockingStation = (self == [player getTargetDockStation]);
    if (isDockingStation && [player status] == STATUS_IN_FLIGHT &&
        [player getDockingClearanceStatus] == DOCKING_CLEARANCE_STATUS_REQUESTED) {
        if (![self hasClearDock]) {
            // then say why
            if ([self currentlyInDockingQueues]) {
                [self cxx_sendExpandedMessage:oo::str::formatRuntime(OO_DESC("station-docking-clearance-holding-d-ships-approaching"),
                                                  { [self currentlyInDockingQueues] + 1 })
                                       toShip:player];
            } else if ([self currentlyInLaunchingQueues]) {
                [self cxx_sendExpandedMessage:oo::str::formatRuntime(OO_DESC("station-docking-clearance-holding-d-ships-departing"),
                                                  { [self currentlyInLaunchingQueues] + 1 })
                                       toShip:player];
            }
        }
    }

    if ([ship isPlayer]) {
        player_reserved_dock = nil;
    }
}

- (void)addShipToStationCount:(ShipEntity*)ship
{
    if ([ship isShuttle])
        docked_shuttles++;
    else if ([ship isTrader] && ![ship isPlayer])
        docked_traders++;
    else if (([ship isPolice] && ![ship isEscort]) || [ship cxx_hasPrimaryRole:"defense_ship"]) {
        if (0 < defenders_launched)
            defenders_launched--;
    } else if ([ship cxx_hasPrimaryRole:"scavenger"] || [ship cxx_hasPrimaryRole:"miner"]) // treat miners and scavengers alike!
    {
        if (0 < scavengers_launched)
            scavengers_launched--;
    }
}

- (BOOL)interstellarUndockingAllowed
{
    return interstellarUndockingAllowed;
}

- (BOOL)hasNPCTraffic
{
    return hasNPCTraffic;
}

- (void)setHasNPCTraffic:(BOOL)flag
{
    hasNPCTraffic = flag != NO;
}

- (BOOL)collideWithShip:(ShipEntity*)other
{
    /*
            There used to be a [self abortAllDockings] here. Removed as there
            doesn't appear to be a good reason for it and it interferes with
            docking clearance.
            -- Micha 2010-06-10
           Reformatted, Ahruman 2012-08-26
    */
    return [super collideWithShip:other];
}

- (BOOL)hasHostileTarget
{
    return [super hasHostileTarget] || ([self primaryTarget] != nil && ((alertLevel == STATION_ALERT_LEVEL_YELLOW) || (alertLevel == STATION_ALERT_LEVEL_RED)));
}

- (void)takeEnergyDamage:(double)amount from:(Entity*)ent becauseOf:(Entity*)other weaponIdentifier:(const std::string&)weaponIdentifier
{
    // stations must ignore friendly fire, otherwise the defenders' AI gets stuck.
    BOOL isFriend = NO;
    OOShipGroup* group = [self group];

    if ([other isShip] && group != nil) {
        OOShipGroup* otherGroup = [(ShipEntity*)other group];
        isFriend = otherGroup == group || [otherGroup leader] == self;
    }

    // If this is the system's main station...
    if (self == [UNIVERSE station] && !isFriend) {
        //...get angry
        BOOL isEnergyMine = [ent isCascadeWeapon];

        // JSAIs might ignore friendly fire from conventional weapons
        if ([self hasNewAI] || isEnergyMine) {
            unsigned b = isEnergyMine ? 96 : 64;
            if ([(ShipEntity*)other bounty] >= b) // already a hardened criminal?
            {
                b *= 1.5; // bigger bounty!
            }
            [(ShipEntity*)other markAsOffender:b withReason:kOOLegalStatusReasonAttackedMainStation];
            [self setPrimaryAggressor:other];
            [self setFoundTarget:other];
            [self launchPolice];
        }

        if (isEnergyMine) // don't blow up!
        {
            [self increaseAlertLevel];
            [self respondToAttackFrom:ent becauseOf:other];
            return;
        }
    }
    // Stop damage if main station & close to death!
    if (!isFriend && (self != [UNIVERSE station] || amount < energy)) {
        // Handle damage like a ship.
        [super takeEnergyDamage:amount from:ent becauseOf:other weaponIdentifier:weaponIdentifier];
    }
}

- (void)adjustVelocity:(Vector)xVel
{
    if (self != [UNIVERSE station])
        [super adjustVelocity:xVel]; // dont get moved
}

- (void)takeScrapeDamage:(double)amount from:(Entity*)ent
{
    // Stop damage if main station
    if (self != [UNIVERSE station])
        [super takeScrapeDamage:amount from:ent];
}

- (void)takeHeatDamage:(double)amount
{
    // Stop damage if main station
    if (self != [UNIVERSE station])
        [super takeHeatDamage:amount];
}

- (std::optional<std::string>)cxx_allegiance
{
    return allegiance;
}

- (void)cxx_setAllegiance:(const std::optional<std::string>&)newAllegiance
{
    allegiance = newAllegiance;
}

- (OOStationAlertLevel)alertLevel
{
    return alertLevel;
}

- (void)setAlertLevel:(OOStationAlertLevel)level signallingScript:(BOOL)signallingScript
{
    if (level < STATION_ALERT_LEVEL_GREEN)
        level = STATION_ALERT_LEVEL_GREEN;
    if (level > STATION_ALERT_LEVEL_RED)
        level = STATION_ALERT_LEVEL_RED;

    if (alertLevel != level) {
        OOStationAlertLevel oldLevel = alertLevel;
        alertLevel = level;
        if (signallingScript) {
            [self cxx_doScriptEvent:OOJSID("alertConditionChanged") withPListArguments:{ oo::PList((int)level), oo::PList((int)oldLevel) }];
        }
        switch (level) {
        case STATION_ALERT_LEVEL_GREEN:
            [shipAI cxx_reactToMessage:"GREEN_ALERT" context:std::nullopt];
            break;

        case STATION_ALERT_LEVEL_YELLOW:
            [shipAI cxx_reactToMessage:"YELLOW_ALERT" context:std::nullopt];
            break;

        case STATION_ALERT_LEVEL_RED:
            [shipAI cxx_reactToMessage:"RED_ALERT" context:std::nullopt];
            break;
        }
    }
}

// Exposed to AI
- (oo::PList)launchIndependentShip:(const std::string&)role // called by name (ADR-0055 item 5): the ship launched, as an Object node (null: none)
{
    if (![self hasLaunchDock]) {
        OO_LOG("station.launchShip.impossible", "Cancelled launch for a ship with role {}, as the {} has no launch docks.",
            role, [self displayName].value_or("(null)"));
        return oo::PList();
    }

    std::string shipRole = role;
    BOOL trader = shipRole == "trader";
    BOOL sunskimmer = (shipRole == "sunskim-trader");
    ShipEntity* ship = nil;

    if ((trader && (randf() < 0.1)) || sunskimmer) {
        ship = [UNIVERSE cxx_newShipWithRole:"sunskim-trader"];
        sunskimmer = true;
        trader = true;
        shipRole = "trader"; // make sure also sunskimmers get trader role.
    } else {
        ship = [UNIVERSE cxx_newShipWithRole:shipRole];
    }

    if (![self fitsInDock:ship]) {
        [ship release];
        return oo::PList();
    }

    if (ship) {
        if (![ship cxx_crew].has_value()) {
            [ship cxx_setSingleCrewWithRole:shipRole];
        }
        [ship setPrimaryRole:shipRole];

        if (trader || ship->scanClass == CLASS_NOT_SET)
            [ship setScanClass:CLASS_NEUTRAL]; // keep defined scanclasses for non-traders.

        if (trader) {
            [ship setBounty:0 withReason:kOOLegalStatusReasonSetup];
            [ship setCargoFlag:CARGO_FLAG_FULL_PLENTIFUL];
            if (sunskimmer) {
                [ship setFuel:(Ranrot() & 31)];
                [UNIVERSE makeSunSkimmer:ship andSetAI:YES];
            } else {
                // JSAI: not needed - oolite-traderAI.js handles exiting if full fuel and plentiful cargo
                //				[ship switchAITo:@"exitingTraderAI.plist"];
                if ([ship fuel] == 0)
                    [ship setFuel:70];
                //				if ([ship hasRole:"sunskim-trader"]) [UNIVERSE makeSunSkimmer:ship andSetAI:NO];
            }
        }

        [self addShipToLaunchQueue:ship withPriority:NO];

        OOShipGroup* escortGroup = [ship escortGroup];
        if ([ship group] == nil)
            [ship setGroup:escortGroup];
        // Eric: Escorts are defined both as _group and as _escortGroup because friendly attacks are only handled within _group.
        [escortGroup setLeader:ship];

        // add escorts to the trader
        unsigned escorts = [ship pendingEscortCount];
        if (escorts > 0) {
            [ship setOwner:self]; // makes escorts get added to station launch queue
            [ship setUpEscorts];
            [ship setOwner:ship];
        }

        [ship setPendingEscortCount:0];
        [ship autorelease];
    }
    return oo::PListObject(ship);
}

//////////////////////////////////////////////// extra AI routines

// Exposed to AI
- (void)increaseAlertLevel
{
    [self setAlertLevel:(OOStationAlertLevel)([self alertLevel] + 1) signallingScript:YES];
}

// Exposed to AI
- (void)decreaseAlertLevel
{
    [self setAlertLevel:(OOStationAlertLevel)([self alertLevel] - 1) signallingScript:YES];
}

// Exposed to AI
- (oo::PList)launchPolice // called by name (ADR-0055 item 5)
{
    std::vector<oo::ObjCRef<ShipEntity*>> result;
    if (![self hasLaunchDock]) {
        OO_LOG("station.launchShip.impossible", "Cancelled launch for a police ship, as the {} has no launch docks.",
            [self displayName].value_or("(null)"));
        return oo::PListFromObjects(result);
    }

    OOUniversalID police_target = [[self primaryTarget] universalID];
    unsigned i;
    OOTechLevelID techlevel = [self equivalentTechLevel];
    if (techlevel == NSNotFound)
        techlevel = 6;

    result.reserve(4);

    for (i = 0; (i < 4) && (defenders_launched < max_police); i++) {
        ShipEntity* police_ship = nil;
        if (![UNIVERSE entityForUniversalID:police_target]) {
            [self noteLostTarget];
            return oo::PListFromObjects(std::vector<oo::ObjCRef<ShipEntity*>>());
        }
        /* this is more likely to give interceptors than the
         * equivalent populator function: save them for defense
         * ships */
        if ((Ranrot() & 3) + 9 < techlevel) {
            police_ship = [UNIVERSE cxx_newShipWithRole:"interceptor"]; // retain count = 1
        } else {
            police_ship = [UNIVERSE cxx_newShipWithRole:"police"]; // retain count = 1
        }

        if (police_ship && [self fitsInDock:police_ship]) {
            if (![police_ship cxx_crew].has_value()) {
                [police_ship cxx_setSingleCrewWithRole:"police"];
            }

            [police_ship setGroup:[self stationGroup]]; // who's your Daddy
            [police_ship setPrimaryRole:"police"];
            [police_ship addTarget:[UNIVERSE entityForUniversalID:police_target]];
            if ([police_ship scanClass] == CLASS_NOT_SET)
                [police_ship setScanClass:CLASS_POLICE];
            [police_ship setBounty:0 withReason:kOOLegalStatusReasonSetup];
            if ([police_ship heatInsulation] < [self heatInsulation])
                [police_ship setHeatInsulation:[self heatInsulation]];
            [police_ship switchAITo:"oolite-defenseShipAI.js"];
            [self addShipToLaunchQueue:police_ship withPriority:YES];
            defenders_launched++;
            result.push_back(oo::ObjCRef<ShipEntity*>(police_ship));
        }
        [police_ship autorelease];
    }
    [self abortAllDockings];
    return oo::PListFromObjects(result);
}

// Exposed to AI
- (ShipEntity*)launchDefenseShip
{
    if (![self hasLaunchDock]) {
        OO_LOG("station.launchShip.impossible", "Cancelled launch for a defense ship, as the {} has no launch docks.",
            [self displayName].value_or("(null)"));
        return nil;
    }

    OOUniversalID defense_target = [[self primaryTarget] universalID];
    ShipEntity* defense_ship = nil;
    std::string default_defense_ship_role;
    const std::string defense_ship_ai = "oolite-defenseShipAI.js";

    OOTechLevelID techlevel;

    techlevel = [self equivalentTechLevel];
    if (techlevel == NSNotFound)
        techlevel = 6;
    if ((Ranrot() & 7) + 6 <= techlevel)
        default_defense_ship_role = "interceptor";
    else
        default_defense_ship_role = "police";

    if (scanClass == CLASS_ROCK)
        default_defense_ship_role = "hermit-ship";

    if (defenders_launched >= max_defense_ships) // shuttles are to rockhermits what police ships are to stations
        return nil;

    if (![UNIVERSE entityForUniversalID:defense_target]) {
        [self noteLostTarget];
        return nil;
    }

    const std::optional<std::string> defense_ship_key = OptionalStringValue(shipinfoDictionary.find("defense_ship")); // -oo_stringForKey:
    if (defense_ship_key) {
        defense_ship = [UNIVERSE cxx_newShipWithName:*defense_ship_key];
    }
    // The retry below was a pointer comparison of the role with the default role string: it ran
    // exactly when shipdata supplied defense_ship_role (-oo_stringForKey:defaultValue: returned the
    // default object itself otherwise).
    bool shipdataSuppliedRole = false;
    if (!defense_ship) {
        const std::optional<std::string> defense_ship_role = OptionalStringValue(shipinfoDictionary.find("defense_ship_role"));
        shipdataSuppliedRole = defense_ship_role.has_value();
        defense_ship = [UNIVERSE cxx_newShipWithRole:defense_ship_role.value_or(default_defense_ship_role)];
    }

    if (!defense_ship && shipdataSuppliedRole)
        defense_ship = [UNIVERSE cxx_newShipWithRole:default_defense_ship_role];

    if (!defense_ship || ![self fitsInDock:defense_ship]) {
        [defense_ship release];
        return nil;
    }

    if ([defense_ship isPolice] || [defense_ship cxx_hasPrimaryRole:"hermit-ship"]) {
        [defense_ship switchAITo:defense_ship_ai];
    }

    [defense_ship setPrimaryRole:"defense_ship"];

    defenders_launched++;

    if (![defense_ship cxx_crew].has_value()) {
        if ([defense_ship isPolice]) {
            [defense_ship cxx_setSingleCrewWithRole:"police"];
        } else {
            [defense_ship cxx_setSingleCrewWithRole:"hunter"];
        }
    }

    [defense_ship setOwner:self];
    if ([self group] == nil) {
        [self setGroup:[self stationGroup]];
    }
    [defense_ship setGroup:[self stationGroup]]; // who's your Daddy

    [defense_ship addTarget:[UNIVERSE entityForUniversalID:defense_target]];

    if ((scanClass != CLASS_ROCK) && (scanClass != CLASS_STATION)) {
        [defense_ship setScanClass:scanClass]; // same as self
    } else if ([defense_ship scanClass] == CLASS_NOT_SET) {
        [defense_ship setScanClass:CLASS_NEUTRAL];
    }

    if ([defense_ship heatInsulation] < [self heatInsulation]) {
        [defense_ship setHeatInsulation:[self heatInsulation]];
    }

    [self addShipToLaunchQueue:defense_ship withPriority:YES];
    [defense_ship autorelease];
    [self abortAllDockings];

    return defense_ship;
}

// Exposed to AI
- (ShipEntity*)launchScavenger
{
    if (![self hasLaunchDock]) {
        OO_LOG("station.launchShip.impossible", "Cancelled launch for a scavenger ship, as the {} has no launch docks.",
            [self displayName].value_or("(null)"));
        return nil;
    }

    ShipEntity* scavenger_ship;

    unsigned scavs = [UNIVERSE cxx_countShipsWithPrimaryRole:"scavenger" inRange:SCANNER_MAX_RANGE ofEntity:self] + [self countOfShipsInLaunchQueueWithPrimaryRole:"scavenger"];

    if (scavs >= max_scavengers)
        return nil;
    if (scavengers_launched >= max_scavengers)
        return nil;

    scavenger_ship = [UNIVERSE cxx_newShipWithRole:"scavenger"]; // retain count = 1

    if (![self fitsInDock:scavenger_ship]) {
        [scavenger_ship release];
        return nil;
    }

    if (scavenger_ship) {
        if (![scavenger_ship cxx_crew].has_value()) {
            [scavenger_ship cxx_setSingleCrewWithRole:"miner"];
        }

        scavengers_launched++;
        [scavenger_ship setScanClass:CLASS_NEUTRAL];
        if ([scavenger_ship heatInsulation] < [self heatInsulation])
            [scavenger_ship setHeatInsulation:[self heatInsulation]];
        [scavenger_ship setGroup:[self stationGroup]]; // who's your Daddy -- FIXME: should we have a separate group for non-escort auxiliaires?
        [scavenger_ship switchAITo:"oolite-scavengerAI.js"];
        [self addShipToLaunchQueue:scavenger_ship withPriority:NO];
        [scavenger_ship autorelease];
    }
    return scavenger_ship;
}

// Exposed to AI
- (ShipEntity*)launchMiner
{
    if (![self hasLaunchDock]) {
        OO_LOG("station.launchShip.impossible", "Cancelled launch for a miner ship, as the {} has no launch docks.",
            [self displayName].value_or("(null)"));
        return nil;
    }

    ShipEntity* miner_ship;

    int n_miners = [UNIVERSE cxx_countShipsWithPrimaryRole:"miner" inRange:SCANNER_MAX_RANGE ofEntity:self] + [self countOfShipsInLaunchQueueWithPrimaryRole:"miner"];

    if (n_miners >= 1) // just the one
        return nil;

    // count miners as scavengers...
    if (scavengers_launched >= max_scavengers)
        return nil;

    miner_ship = [UNIVERSE cxx_newShipWithRole:"miner"]; // retain count = 1

    if (![self fitsInDock:miner_ship]) {
        [miner_ship release];
        return nil;
    }

    if (miner_ship) {
        if (![miner_ship cxx_crew].has_value()) {
            [miner_ship cxx_setSingleCrewWithRole:"miner"];
        }

        scavengers_launched++;
        [miner_ship setScanClass:CLASS_NEUTRAL];
        if ([miner_ship heatInsulation] < [self heatInsulation])
            [miner_ship setHeatInsulation:[self heatInsulation]];
        [miner_ship setGroup:[self stationGroup]]; // who's your Daddy -- FIXME: should we have a separate group for non-escort auxiliaires?
        [miner_ship switchAITo:"oolite-scavengerAI.js"];
        [self addShipToLaunchQueue:miner_ship withPriority:NO];
        [miner_ship autorelease];
    }
    return miner_ship;
}

/**Lazygun** added the following method. A complete rip-off of launchDefenseShip.
 */
// Exposed to AI
- (ShipEntity*)launchPirateShip
{
    if (![self hasLaunchDock]) {
        OO_LOG("station.launchShip.impossible", "Cancelled launch for a pirate ship, as the {} has no launch docks.",
            [self displayName].value_or("(null)"));
        return nil;
    }
    // Pirate ships are launched from the same pool as defence ships.
    OOUniversalID defense_target = [[self primaryTarget] universalID];
    ShipEntity* pirate_ship = nil;

    if (defenders_launched >= max_defense_ships)
        return nil; // shuttles are to rockhermits what police ships are to stations

    if (![UNIVERSE entityForUniversalID:defense_target]) {
        [self noteLostTarget];
        return nil;
    }

    // Yep! The standard hermit defence ships, even if they're the aggressor.
    pirate_ship = [UNIVERSE cxx_newShipWithRole:"pirate"]; // retain count = 1
    // Nope, use standard pirates in a generic method.

    if (![self fitsInDock:pirate_ship]) {
        [pirate_ship release];
        return nil;
    }

    if (pirate_ship) {
        if (![pirate_ship cxx_crew].has_value()) {
            [pirate_ship cxx_setSingleCrewWithRole:"pirate"];
        }

        defenders_launched++;

        // set the owner of the ship to the station so that it can check back for docking later
        [pirate_ship setOwner:self];
        [pirate_ship setGroup:[self stationGroup]]; // who's your Daddy
        [pirate_ship setPrimaryRole:"defense_ship"];
        [pirate_ship addTarget:[UNIVERSE entityForUniversalID:defense_target]];
        [pirate_ship setScanClass:CLASS_NEUTRAL];
        if ([pirate_ship heatInsulation] < [self heatInsulation])
            [pirate_ship setHeatInsulation:[self heatInsulation]];
        //**Lazygun** added 30 Nov 04 to put a bounty on those pirates' heads.
        [pirate_ship setBounty:10 + floor(randf() * 20) withReason:kOOLegalStatusReasonSetup]; // modified for variety

        [self addShipToLaunchQueue:pirate_ship withPriority:NO];
        [pirate_ship autorelease];
        [self abortAllDockings];
    }
    return pirate_ship;
}

// Exposed to AI
- (ShipEntity*)launchShuttle
{
    if (![self hasLaunchDock]) {
        OO_LOG("station.launchShip.impossible", "Cancelled launch for a shuttle ship, as the {} has no launch docks.",
            [self displayName].value_or("(null)"));
        return nil;
    }
    ShipEntity* shuttle_ship;

    shuttle_ship = [UNIVERSE cxx_newShipWithRole:"shuttle"]; // retain count = 1

    if (![self fitsInDock:shuttle_ship]) {
        [shuttle_ship release];
        return nil;
    }

    if (shuttle_ship) {
        if (![shuttle_ship cxx_crew].has_value()) {
            [shuttle_ship cxx_setSingleCrewWithRole:"trader"];
        }

        docked_shuttles--;
        [shuttle_ship setScanClass:CLASS_NEUTRAL];
        [shuttle_ship setCargoFlag:CARGO_FLAG_FULL_SCARCE];
        [shuttle_ship switchAITo:"oolite-shuttleAI.js"];
        [self addShipToLaunchQueue:shuttle_ship withPriority:NO];

        [shuttle_ship autorelease];
    }
    return shuttle_ship;
}

// Exposed to AI
- (ShipEntity*)launchEscort
{
    if (![self hasLaunchDock]) {
        OO_LOG("station.launchShip.impossible", "Cancelled launch for an escort ship, as the {} has no launch docks.",
            [self displayName].value_or("(null)"));
        return nil;
    }
    ShipEntity* escort_ship;

    escort_ship = [UNIVERSE cxx_newShipWithRole:"escort"]; // retain count = 1

    if (escort_ship && [self fitsInDock:escort_ship]) {
        if (![escort_ship cxx_crew].has_value()) {
            [escort_ship cxx_setSingleCrewWithRole:"hunter"];
        }

        [escort_ship setScanClass:CLASS_NEUTRAL];
        [escort_ship setCargoFlag:CARGO_FLAG_FULL_PLENTIFUL];
        [escort_ship switchAITo:"oolite-escortAI.js"];
        [self addShipToLaunchQueue:escort_ship withPriority:NO];
    }
    [escort_ship release];
    return escort_ship;
}

// Exposed to AI
- (ShipEntity*)launchPatrol
{
    if (![self hasLaunchDock]) {
        OO_LOG("station.launchShip.impossible", "Cancelled launch for a patrol ship, as the {} has no launch docks.",
            [self displayName].value_or("(null)"));
        return nil;
    }
    if (defenders_launched < max_police) {
        ShipEntity* patrol_ship = nil;
        OOTechLevelID techlevel;

        techlevel = [self equivalentTechLevel];
        if (techlevel == NSNotFound)
            techlevel = 6;

        if ((Ranrot() & 7) + 6 <= techlevel)
            patrol_ship = [UNIVERSE cxx_newShipWithRole:"interceptor"]; // retain count = 1
        else
            patrol_ship = [UNIVERSE cxx_newShipWithRole:"police"]; // retain count = 1

        if (![self fitsInDock:patrol_ship]) {
            [patrol_ship release];
            return nil;
        }

        if (patrol_ship) {
            if (![patrol_ship cxx_crew].has_value()) {
                [patrol_ship cxx_setSingleCrewWithRole:"police"];
            }

            defenders_launched++;
            [patrol_ship switchLightsOff];
            if ([patrol_ship scanClass] == CLASS_NOT_SET)
                [patrol_ship setScanClass:CLASS_POLICE];
            if ([patrol_ship heatInsulation] < [self heatInsulation])
                [patrol_ship setHeatInsulation:[self heatInsulation]];
            [patrol_ship setPrimaryRole:"police-station-patrol"];
            [patrol_ship setBounty:0 withReason:kOOLegalStatusReasonSetup];
            [patrol_ship setGroup:[self stationGroup]]; // who's your Daddy
            [patrol_ship switchAITo:"oolite-policeAI.js"];
            [self addShipToLaunchQueue:patrol_ship withPriority:NO];
            [self acceptPatrolReportFrom:patrol_ship];
            [patrol_ship autorelease];
            return patrol_ship;
        }
    }
    return nil;
}

// Exposed to AI
- (void)launchShipWithRole:(const std::string&)role // called by name (ADR-0055 item 5)
{
    if (![self hasLaunchDock]) {
        OO_LOG("station.launchShip.impossible", "Cancelled launch for a ship with role {}, as the {} has no launch docks.",
            role, [self displayName].value_or("(null)"));
        return;
    }
    const std::string& shipRole = role;
    ShipEntity* ship = [UNIVERSE cxx_newShipWithRole:shipRole]; // retain count = 1
    if (ship && [self fitsInDock:ship]) {
        if (![ship cxx_crew].has_value()) {
            [ship cxx_setSingleCrewWithRole:shipRole];
        }
        if (ship->scanClass == CLASS_NOT_SET)
            [ship setScanClass:CLASS_NEUTRAL];
        [ship setPrimaryRole:shipRole];
        [ship setGroup:[self stationGroup]]; // who's your Daddy
        [self addShipToLaunchQueue:ship withPriority:NO];
    }
    [ship release];
}

// Exposed to AI
- (void)becomeExplosion
{
    if (self == [UNIVERSE station])
        return;

    // launch docked ships if possible
    PlayerEntity* player = PLAYER;
    if ((player) && ([player status] == STATUS_DOCKED || [player status] == STATUS_DOCKING) && ([player dockedStation] == self)) {
        // undock the player!
        [player leaveDock:self];
        [UNIVERSE setViewDirection:VIEW_FORWARD];
        [[UNIVERSE gameController] setMouseInteractionModeForFlight];
        [player warnAboutHostiles]; // sound a klaxon
    }

    if (scanClass == CLASS_ROCK) // ie we're a rock hermit or similar
    {
        // set the role so that we break up into rocks!
        [self setPrimaryRole:"asteroid"];
        being_mined = YES;
    }

    // finally bite the bullet
    [super becomeExplosion];
}

// Exposed to AI
- (void)becomeEnergyBlast
{
    if (self == [UNIVERSE station])
        return;
    [super becomeEnergyBlast];
}

- (void)becomeLargeExplosion:(double)factor
{
    if (self == [UNIVERSE station])
        return;
    [super becomeLargeExplosion:factor];
}

- (void)acceptPatrolReportFrom:(ShipEntity*)patrol_ship
{
    last_patrol_report_time = [UNIVERSE getTime];
}

// used by player - "other" should always be a reference to the player
// there are some checks in the function from possibly when this wasn't true?
- (std::optional<std::string>)cxx_acceptDockingClearanceRequestFrom:(ShipEntity*)other
{
    std::optional<std::string> result; // nullopt: no answer yet (was nil)
    double timeNow = [UNIVERSE getTime];
    PlayerEntity* player = PLAYER;

    [self doScriptEvent:OOJSID("stationReceivedDockingRequest") withArgument:other];

    [UNIVERSE clearPreviousMessage];

    [self sanityCheckShipsOnApproach];

    // Docking clearance not required - clear it just in case it's been
    // set for another nearby station.
    if (![self requiresDockingClearance]) {
        // TODO: We're potentially cancelling docking at another station, so
        //       ensure we clear the timer to allow NPC traffic.  If we
        //       don't, normal traffic will resume once the timer runs out.
        // No clearance is needed, but don't send friendly messages to hostile ships!
        if (!(([other isPlayer] && [other hasHostileTarget]) || (self == [UNIVERSE station] && [other bounty] > 50))) {
            [self cxx_sendExpandedMessage:"[station-docking-clearance-not-required]" toShip:other];
        }
        if ([other isPlayer]) {
            [player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NOT_REQUIRED];
        }
        [shipAI cxx_reactToMessage:"DOCKING_REQUESTED" context:std::nullopt]; // react to the request
        [self doScriptEvent:OOJSID("stationAcceptedDockingRequest") withArgument:other];

        last_launch_time = timeNow + DOCKING_CLEARANCE_WINDOW;
        result = "DOCKING_CLEARANCE_NOT_REQUIRED";
    }

    // Docking clearance already granted for this station - check for
    // time-out or cancellation (but only for the Player).
    if (!result && [other isPlayer] && self == [player getTargetDockStation]) {
        switch ([player getDockingClearanceStatus]) {
        case DOCKING_CLEARANCE_STATUS_TIMING_OUT:
            if (!no_docking_while_launching) {
                last_launch_time = timeNow + DOCKING_CLEARANCE_WINDOW;
                [self cxx_sendExpandedMessage:oo::str::formatRuntime(OO_DESC("station-docking-clearance-extended-until-@"),
                                                  { cxx_ClockToString([player clockTime] + DOCKING_CLEARANCE_WINDOW, NO) })
                                       toShip:other];
                [player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_GRANTED];
                result = "DOCKING_CLEARANCE_EXTENDED";
                break;
            }
            // else, continue with canceling.
        case DOCKING_CLEARANCE_STATUS_REQUESTED:
        case DOCKING_CLEARANCE_STATUS_GRANTED:
            last_launch_time = timeNow;
            [self cxx_sendExpandedMessage:"[station-docking-clearance-cancelled]" toShip:other];
            [player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
            result = "DOCKING_CLEARANCE_CANCELLED";
            player_reserved_dock = nil;
            if ([self currentlyInDockingQueues] == 0) {
                [shipAI message:"DOCKING_COMPLETE"];
                [self doScriptEvent:OOJSID("stationDockingQueuesAreEmpty")];
            }
            break;
        case DOCKING_CLEARANCE_STATUS_NONE:
        case DOCKING_CLEARANCE_STATUS_NOT_REQUIRED:
            break;
        }
    }

    // First we must set the status to REQUESTED to avoid problems when
    // switching docking targets - even if we later set it back to NONE.
    if (!result && [other isPlayer] && self != [player getTargetDockStation]) {
        player_reserved_dock = nil; // and clear any previously reserved dock
        [player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_REQUESTED];
    }

    // Deny docking for fugitives at the main station
    // TODO: Should this be another key in shipdata.plist and/or should this
    //  apply to all stations?
    if (!result && self == [UNIVERSE station] && [other bounty] > 50) // do not grant docking clearance to fugitives
    {
        [self cxx_sendExpandedMessage:"[station-docking-clearance-H-clearance-refused]" toShip:other];
        if ([other isPlayer])
            [player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
        result = "DOCKING_CLEARANCE_DENIED_SHIP_FUGITIVE";
    }

    if (!result && [other hasHostileTarget]) // do not grant docking clearance to hostile ships.
    {
        [self cxx_sendExpandedMessage:"[station-docking-clearance-denied]" toShip:other];
        if ([other isPlayer])
            [player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
        result = "DOCKING_CLEARANCE_DENIED_SHIP_HOSTILE";
    }

    if (![self hasEligibleDock]) // make sure at least one dock could plausibly accept the player
    {
        if ([other isPlayer]) {
            [player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
        }
        [self cxx_sendExpandedMessage:"[station-docking-clearance-denied-no-docks]" toShip:other];

        result = "DOCKING_CLEARANCE_DENIED_NO_DOCKS";
    } else if (![self hasClearDock]) // skip check if at least one dock clear
    {
        // Put ship in queue if we've got incoming or outgoing traffic or
        // if the player is waiting for manual clearance and we are not
        // the player
        if (!result && (([self currentlyInDockingQueues] && last_launch_time < timeNow) || (![other isPlayer] && [player getDockingClearanceStatus] == DOCKING_CLEARANCE_STATUS_REQUESTED))) {
            [self cxx_sendExpandedMessage:oo::str::formatRuntime(OO_DESC("station-docking-clearance-acknowledged-d-ships-approaching"),
                                              { [self currentlyInDockingQueues] + 1 })
                                   toShip:other];
            // No need to set status to REQUESTED as we've already done that earlier.
            result = "DOCKING_CLEARANCE_DENIED_TRAFFIC_INBOUND";
        }

        if (!result && [self currentlyInLaunchingQueues]) {
            [self cxx_sendExpandedMessage:oo::str::formatRuntime(OO_DESC("station-docking-clearance-acknowledged-d-ships-departing"),
                                              { [self currentlyInLaunchingQueues] + 1 })
                                   toShip:other];
            // No need to set status to REQUESTED as we've already done that earlier.
            result = "DOCKING_CLEARANCE_DENIED_TRAFFIC_OUTBOUND";
        }
        if (!result) {
            // if this happens, the station has no docks which allow
            // docking, so deny clearance
            if ([other isPlayer]) {
                [player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
            }
            result = "DOCKING_CLEARANCE_DENIED_NO_DOCKS";
            // but can check to see if we'll open some for later.
            BOOL openLater = NO;
            for (const oo::ObjCRef<DockEntity*>& dock : [self cxx_dockSubEntities]) {
                DockEntity* sub = dock.get();
                std::string docking = [sub canAcceptShipForDocking:other].value_or("");
                if (docking == "DOCK_CLOSED") {
                    JSContext* context = OOJSAcquireContext();
                    OOJSVal rval = OOJSUndefinedValue();
                    OOJSVal args[] = { OOJSValueFromNativeObject(context, sub),
                        OOJSValueFromNativeObject(context, other) };
                    BOOL tempreject = NO;

                    BOOL OK = [[self script] callMethod:OOJSID("willOpenDockingPortFor") inContext:context withArguments:args count:2 result:&rval];
                    if (OK)
                        tempreject = OOJSValueToBOOL(context, rval);
                    if (!OK)
                        tempreject = NO; // default to permreject
                    if (tempreject) {
                        openLater = YES;
                    }

                    OOJSFreeValue(context, rval);
                    OOJSFreeValue(context, args[0]);
                    OOJSFreeValue(context, args[1]);
                    OOJSRelinquishContext(context);
                }
                if (openLater)
                    break;
            }

            if (openLater) {
                [self cxx_sendExpandedMessage:"[station-docking-clearance-denied-no-docks-yet]" toShip:other];
            } else {
                [self cxx_sendExpandedMessage:"[station-docking-clearance-denied-no-docks]" toShip:other];
            }
        }
    }

    // Ship has passed all checks - grant docking!
    if (!result) {
        last_launch_time = timeNow + DOCKING_CLEARANCE_WINDOW;
        if ([other isPlayer]) {
            [player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_GRANTED];
            player_reserved_dock = [self selectDockForDocking];
        }

        if ([self hasMultipleDocks] && [other isPlayer]) {
            [self cxx_sendExpandedMessage:oo::str::formatRuntime(OO_DESC("station-docking-clearance-granted-in-@-until-@"),
                                              { [player_reserved_dock displayName].value_or("(null)"),
                                                  cxx_ClockToString([player clockTime] + DOCKING_CLEARANCE_WINDOW, NO) })
                                   toShip:other];
        } else {
            [self cxx_sendExpandedMessage:oo::str::formatRuntime(OO_DESC("station-docking-clearance-granted-until-@"),
                                              { cxx_ClockToString([player clockTime] + DOCKING_CLEARANCE_WINDOW, NO) })
                                   toShip:other];
        }

        result = "DOCKING_CLEARANCE_GRANTED";
        [shipAI cxx_reactToMessage:"DOCKING_REQUESTED" context:std::nullopt]; // react to the request
        [self doScriptEvent:OOJSID("stationAcceptedDockingRequest") withArgument:other];
    }
    return result;
}

- (unsigned)currentlyInDockingQueues
{
    unsigned soa = 0;
    for (const oo::ObjCRef<DockEntity*>& dock : [self cxx_dockSubEntities]) {
        DockEntity* sub = dock.get();
        soa += [sub countOfShipsInDockingQueue];
    }
    soa += [_shipsOnHold count];
    return soa;
}

- (unsigned)currentlyInLaunchingQueues
{
    unsigned soa = 0;
    for (const oo::ObjCRef<DockEntity*>& dock : [self cxx_dockSubEntities]) {
        DockEntity* sub = dock.get();
        soa += [sub countOfShipsInLaunchQueue];
    }
    return soa;
}

- (BOOL)requiresDockingClearance
{
    return requiresDockingClearance;
}

- (void)setRequiresDockingClearance:(BOOL)newValue
{
    requiresDockingClearance = !!newValue; // Ensure yes or no
}

- (BOOL)allowsFastDocking
{
    return allowsFastDocking;
}

- (void)setAllowsFastDocking:(BOOL)newValue
{
    allowsFastDocking = !!newValue; // Ensure yes or no
}

- (BOOL)allowsAutoDocking
{
    return allowsAutoDocking;
}

- (void)setAllowsAutoDocking:(BOOL)newValue
{
    allowsAutoDocking = !!newValue; // Ensure yes or no
}

- (BOOL)allowsSaving
{
    // fixed stations only, not carriers!
    return allowsSaving && ([self maxFlightSpeed] == 0);
}

- (BOOL)isRotatingStation
{
    if (shipinfoDictionary.get<bool>("rotating", false))
        return YES;
    // legacy. -rangeOfString: of the roles string; absent, a message to nil gave a zeroed range, which is not NSNotFound.
    const oo::PList* roles = shipinfoDictionary.find("roles");
    if (roles == nullptr)
        return YES;
    const std::string* rolesString = roles->getIf<std::string>();
    return rolesString != nullptr && rolesString->find("rotating-station") != std::string::npos;
}

- (std::optional<std::string>)marketOverrideName
{
    // 2010.06.14 - Micha - we can't default to the primary role as otherwise the logic
    //				generating the market in [Universe commodityDataForEconomy:] doesn't
    //				work properly with the various overrides.  The primary role will get
    //				used if either there is no market override, or the market wasn't
    //				defined.
    return OptionalStringValue(shipinfoDictionary.find("market"));
}

- (BOOL)hasShipyard
{
    if ([UNIVERSE station] == self)
        return YES;
    const oo::PList* determinantValue = shipinfoDictionary.find("has_shipyard");

    if (determinantValue == nullptr)
        determinantValue = shipinfoDictionary.find("hasShipyard");

    // NOTE: non-standard capitalization is documented and entrenched.
    if (determinantValue != nullptr && !determinantValue->isNull()) {
        if (determinantValue->isArray()) {
            return [PLAYER cxx_scriptTestConditions:OOSanitizeLegacyScriptConditions(*determinantValue, std::nullopt)];
        } else {
            return OOFuzzyBooleanFromPList(determinantValue, 0.0f);
        }
    } else {
        return NO;
    }
}

- (void)generateShipyard
{
    [self generateShipyard:[self equivalentTechLevel]];
}

- (void)generateShipyard:(OOTechLevelID)stationTechLevel
{
    unsigned i;

    if ([self cxx_localShipyard] == nullptr) {
        const oo::PList forSale = [UNIVERSE cxx_shipsForSaleForSystem:[UNIVERSE currentSystemID] withTL:stationTechLevel atTime:[PLAYER clockTime]];
        const oo::PList::Array* entries = forSale.getIf<oo::PList::Array>();
        [self cxx_setLocalShipyard:entries != nullptr ? *entries : oo::PList::Array()]; // nil gave an empty shipyard
    }

    std::vector<oo::PList>* shipyard = [self cxx_localShipyard];
    const oo::PList::Dict* shipyardRecord = [PLAYER cxx_shipyardRecord];

    // remove ships that the player has already bought
    for (i = 0; i < shipyard->size(); i++) {
        const std::optional<std::string> shipID = OptionalStringValue((*shipyard)[i].find("id")); // SHIPYARD_KEY_ID
        if (shipID && shipyardRecord != nullptr && shipyardRecord->contains(*shipID)) {
            shipyard->erase(shipyard->begin() + i--);
        }
    }
}

- (BOOL)suppressArrivalReports
{
    return suppress_arrival_reports;
}

- (void)setSuppressArrivalReports:(BOOL)newValue
{
    suppress_arrival_reports = !!newValue; // ensure YES or NO
}

- (BOOL)hasBreakPattern
{
    return hasBreakPattern;
}

- (void)setHasBreakPattern:(BOOL)newValue
{
    hasBreakPattern = !!newValue;
}

- (std::optional<std::string>)cxx_descriptionComponents
{
    return oo::str::format("\"%s\" %s", name.value_or("(null)").c_str(), [super cxx_descriptionComponents].value_or("(null)").c_str());
}

- (void)dumpSelfState
{
    std::vector<std::string> flags;
    std::string flagsString;
    std::string alertString = "*** ERROR: UNKNOWN ALERT LEVEL ***";

    [super dumpSelfState];

    switch (alertLevel) {
    case STATION_ALERT_LEVEL_GREEN:
        alertString = "green";
        break;

    case STATION_ALERT_LEVEL_YELLOW:
        alertString = "yellow";
        break;

    case STATION_ALERT_LEVEL_RED:
        alertString = "red";
        break;
    }

    OO_LOG("dumpState.stationEntity", "Alert level: {}", alertString);
    OO_LOG("dumpState.stationEntity", "Max police: {}", static_cast<unsigned>(max_police));
    OO_LOG("dumpState.stationEntity", "Max defense ships: {}", static_cast<unsigned>(max_defense_ships));
    OO_LOG("dumpState.stationEntity", "Defenders launched: {}", static_cast<unsigned>(defenders_launched));
    OO_LOG("dumpState.stationEntity", "Max scavengers: {}", static_cast<unsigned>(max_scavengers));
    OO_LOG("dumpState.stationEntity", "Scavengers launched: {}", static_cast<unsigned>(scavengers_launched));
    OO_LOG("dumpState.stationEntity", "Docked shuttles: {}", static_cast<unsigned>(docked_shuttles));
    OO_LOG("dumpState.stationEntity", "Docked traders: {}", static_cast<unsigned>(docked_traders));
    OO_LOG("dumpState.stationEntity", "Equivalent tech level: {}", equivalentTechLevel);
    OO_LOG("dumpState.stationEntity", "Equipment price factor: {:g}", equipmentPriceFactor);

#define ADD_FLAG_IF_SET(x)   \
    if (x) {                 \
        flags.push_back(#x); \
    }
    ADD_FLAG_IF_SET(no_docking_while_launching);
    if ([self isRotatingStation]) {
        flags.push_back("rotatingStation");
    }
    if (![self dockingCorridorIsEmpty]) {
        flags.push_back("dockingCorridorIsBusy");
    }
    for (const std::string& flag : flags) {
        if (!flagsString.empty())
            flagsString += ", "; // -componentsJoinedByString:
        flagsString += flag;
    }
    if (flags.empty())
        flagsString = "none";
    OO_LOG("dumpState.stationEntity", "Flags: {}", flagsString);

    // approach and hold lists.

    // Ships on hold list, only used with moving stations (= carriers)
    if ([_shipsOnHold count] > 0) {
        OO_LOG("dumpState.stationEntity", "{} Ships on hold (unsorted):", [_shipsOnHold count]);

        oo::log::indent();
        unsigned i = 1;
        for (const oo::ObjCRef<id>& shipRef : [_shipsOnHold cxx_objectEnumerator]) {
            ShipEntity* ship = static_cast<ShipEntity*>(shipRef.get());
            OO_LOG("dumpState.stationEntity", "Nr {}: {} at distance {:g} with role: {}", i++, [ship displayName].value_or("(null)"), HPdistance([self position], [ship position]), [ship cxx_primaryRole].value_or("(null)"));
        }
        oo::log::outdent();
    }
}

@end
