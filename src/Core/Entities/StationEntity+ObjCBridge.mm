/*

StationEntity+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendments oo-60fwo and oo-64ako): the Objective-C StationEntity
facade (see StationEntity+ObjCBridge.h). The class's primary @implementation is here, empty:
every method has moved into cxx::StationEntity (slices 1-4 of docs/phases/3-slices/StationEntity.md,
the last bead oo-tqem7) and the facade's methods are its categories below, which forward each
selector to the C++ part. Its initialisers and -dealloc are a category because they need the
Objective-C object as self (amendment oo-bj8 items 6 and 7). Deleted with
StationEntity+ObjCBridge.h.

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

#import "OOCommodityMarket.h"
#import "OOJSEngineTimeManagement.h"
#import "OOWeakSet.h"
#import "ShipEntity+ObjCAdapter.h"
#import "StationEntity.h"
#include "oofnd/objc/OOAssert.h"

@implementation StationEntity
@end

@implementation StationEntity (OOObjCBridge)

- (id)cxx_initWithKey:(const std::string&)key definition:(const oo::PList&)dict
{
    OOJS_PROFILE_ENTER

    self = [super cxx_initWithKey:key definition:dict];
    if (self != nil) {
        _cxxStation->isStation = YES;
        _cxxStation->_shipsOnHold = [[OOWeakSet alloc] init];
        _cxxStation->hasBreakPattern = YES;
    }
    return self;

    OOJS_PROFILE_EXIT
}

/*	What [super init] did in ShipEntity's initialisers, with the station's adapter: a station's C++
        part is a cxx::StationEntity (amendment oo-64ako), with the ship's adapter lines.
*/
- (id)initShipPart
{
    // -init sent again to an initialised ship keeps its C++ part (the root's -initWithCxxEntity:).
    if (_cxxEntity != nullptr)
        return [self initWithCxxEntity:_cxxEntity.get()];
    return [self initWithCxxEntity:oo::makeRef<oo::ObjCShipEntity<cxx::StationEntity>>(self).get()];
}

// The root's designated initialiser, which also sets the typed alias of the part it stores.
- (id)initWithCxxEntity:(cxx::Entity*)entity
{
    self = [super initWithCxxEntity:entity];
    if (EXPECT_NOT(self == nil))
        return nil;

    _cxxStation = dynamic_cast<cxx::StationEntity*>(_cxxEntity.get());
    OOCParameterAssert(_cxxStation != nullptr);
    return self;
}

- (void)dealloc
{
    /*	Released before its initialiser ran (a failing initialiser's [self release]; return nil;):
            there is no C++ part, as in ShipEntity's -dealloc (oo-s6ic6).
    */
    if (_cxxStation != nullptr) {
        DESTROY(_cxxStation->_shipsOnHold);
        DESTROY(_cxxStation->localMarket);
        //	DESTROY(localPassengers);
        //	DESTROY(localContracts);
    }

    [super dealloc];
}

@end

OOWeakReference* StationEntityWeakReference(StationEntity* station) { return [[station weakRetain] autorelease]; }

// Slice 1 of docs/phases/3-slices/StationEntity.md (bead oo-64ako).
@implementation StationEntity (OOSlice1)

- (BOOL)isUnpiloted
{
    return _cxxStation->cxx::StationEntity::isUnpiloted();
}
- (OOTechLevelID)equivalentTechLevel
{
    return _cxxStation->getEquivalentTechLevel();
}
- (void)setEquivalentTechLevel:(OOTechLevelID)value
{
    _cxxStation->setEquivalentTechLevel(value);
}
- (Vector)virtualPortDimensions
{
    return _cxxStation->virtualPortDimensions();
}
- (DockEntity*)playerReservedDock
{
    return _cxxStation->playerReservedDock();
}
- (HPVector)beaconPosition
{
    return _cxxStation->beaconPosition();
}
- (float)equipmentPriceFactor
{
    return _cxxStation->getEquipmentPriceFactor();
}
- (OOCargoQuantity)marketCapacity
{
    return _cxxStation->getMarketCapacity();
}
- (oo::PList)cxx_marketDefinition
{
    return _cxxStation->getMarketDefinition();
}
- (std::optional<std::string>)cxx_marketScriptName
{
    return _cxxStation->getMarketScriptName();
}
- (BOOL)marketMonitored
{
    return _cxxStation->getMarketMonitored();
}
- (BOOL)marketBroadcast
{
    return _cxxStation->getMarketBroadcast();
}
- (OOCreditsQuantity)legalStatusOfManifest:(OOCommodityMarket*)manifest export:(BOOL)isExport
{
    return _cxxStation->legalStatusOfManifest(manifest, isExport);
}
- (OOCommodityMarket*)localMarket
{
    return _cxxStation->getLocalMarket();
}
- (void)cxx_setLocalMarket:(const oo::PList&)market
{
    _cxxStation->setLocalMarket(market);
}
- (oo::PList)cxx_localMarketForScripting
{
    return _cxxStation->localMarketForScripting();
}
- (void)cxx_setPrice:(OOCreditsQuantity)price forCommodity:(const std::string&)commodity
{
    _cxxStation->setPrice(price, commodity);
}
- (void)cxx_setQuantity:(OOCargoQuantity)quantity forCommodity:(const std::string&)commodity
{
    _cxxStation->setQuantity(quantity, commodity);
}
- (std::vector<oo::PList>*)cxx_localShipyard
{
    return _cxxStation->getLocalShipyard();
}
- (void)cxx_setLocalShipyard:(const std::vector<oo::PList>&)shipyard
{
    _cxxStation->setLocalShipyard(shipyard);
}
- (std::map<std::string, oo::ObjCRef<OOJSInterfaceDefinition*>, std::less<>>*)cxx_localInterfaces
{
    return _cxxStation->getLocalInterfaces();
}
- (void)cxx_setInterfaceDefinition:(OOJSInterfaceDefinition*)definition forKey:(const std::string&)key
{
    _cxxStation->setInterfaceDefinition(definition, key);
}
- (OOCommodityMarket*)initialiseLocalMarket
{
    return _cxxStation->initialiseLocalMarket();
}
- (void)setPlanet:(OOPlanetEntity*)planet_entity
{
    _cxxStation->setPlanet(planet_entity);
}
- (OOPlanetEntity*)planet
{
    return _cxxStation->getPlanet();
}
- (unsigned)countOfDockedContractors
{
    return _cxxStation->countOfDockedContractors();
}
- (unsigned)countOfDockedPolice
{
    return _cxxStation->countOfDockedPolice();
}
- (unsigned)countOfDockedDefenders
{
    return _cxxStation->countOfDockedDefenders();
}
- (std::vector<oo::ObjCRef<DockEntity*>>)cxx_dockSubEntities
{
    return _cxxStation->dockSubEntities();
}
- (BOOL)setUpShipFromDictionary:(const oo::PList&)dict
{
    return _cxxStation->cxx::StationEntity::setUpShipFromDictionary(dict);
}
- (BOOL)setUpSubEntities
{
    return _cxxStation->cxx::StationEntity::setUpSubEntities();
}
- (BOOL)interstellarUndockingAllowed
{
    return _cxxStation->getInterstellarUndockingAllowed();
}
- (BOOL)hasNPCTraffic
{
    return _cxxStation->getHasNPCTraffic();
}
- (void)setHasNPCTraffic:(BOOL)flag
{
    _cxxStation->setHasNPCTraffic(flag);
}
- (BOOL)requiresDockingClearance
{
    return _cxxStation->getRequiresDockingClearance();
}
- (void)setRequiresDockingClearance:(BOOL)newValue
{
    _cxxStation->setRequiresDockingClearance(newValue);
}
- (BOOL)allowsFastDocking
{
    return _cxxStation->getAllowsFastDocking();
}
- (void)setAllowsFastDocking:(BOOL)newValue
{
    _cxxStation->setAllowsFastDocking(newValue);
}
- (BOOL)allowsAutoDocking
{
    return _cxxStation->getAllowsAutoDocking();
}
- (void)setAllowsAutoDocking:(BOOL)newValue
{
    _cxxStation->setAllowsAutoDocking(newValue);
}
- (BOOL)allowsSaving
{
    return _cxxStation->getAllowsSaving();
}
- (BOOL)isRotatingStation
{
    return _cxxStation->isRotatingStation();
}
- (std::optional<std::string>)marketOverrideName
{
    return _cxxStation->marketOverrideName();
}
- (BOOL)hasShipyard
{
    return _cxxStation->hasShipyard();
}
- (void)generateShipyard
{
    _cxxStation->generateShipyard();
}
- (void)generateShipyard:(OOTechLevelID)stationTechLevel
{
    _cxxStation->generateShipyard(stationTechLevel);
}
- (BOOL)suppressArrivalReports
{
    return _cxxStation->suppressArrivalReports();
}
- (void)setSuppressArrivalReports:(BOOL)newValue
{
    _cxxStation->setSuppressArrivalReports(newValue);
}
- (BOOL)hasBreakPattern
{
    return _cxxStation->getHasBreakPattern();
}
- (void)setHasBreakPattern:(BOOL)newValue
{
    _cxxStation->setHasBreakPattern(newValue);
}
- (std::optional<std::string>)cxx_descriptionComponents
{
    return _cxxStation->cxx::StationEntity::descriptionComponents();
}
- (void)dumpSelfState
{
    _cxxStation->cxx::StationEntity::dumpSelfState();
}

@end

// ShipEntityAI.mm slice 1 (bead oo-iebuz): the category StationEntity (OOAIPrivate).
@implementation StationEntity (OOAIPrivate)

- (void)acceptDistressMessageFrom:(ShipEntity*)other
{
    _cxxStation->cxx::StationEntity::acceptDistressMessageFrom(other);
}

@end

// Slice 2 of docs/phases/3-slices/StationEntity.md (bead oo-9j462).
@implementation StationEntity (OOSlice2)

- (void)sanityCheckShipsOnApproach
{
    _cxxStation->sanityCheckShipsOnApproach();
}
- (void)launchShip:(ShipEntity*)ship
{
    _cxxStation->launchShip(ship);
}
- (void)abortAllDockings
{
    _cxxStation->abortAllDockings();
}
- (void)autoDockShipsOnHold
{
    _cxxStation->autoDockShipsOnHold();
}
- (void)autoDockShipsOnApproach
{
    _cxxStation->autoDockShipsOnApproach();
}
- (Vector)portUpVectorForShip:(ShipEntity*)ship
{
    return _cxxStation->portUpVectorForShip(ship);
}
- (oo::PList)dockingInstructionsForShip:(ShipEntity*)ship
{
    return _cxxStation->dockingInstructionsForShip(ship);
}
- (oo::PList)holdPositionInstructionForShip:(ShipEntity*)ship
{
    return _cxxStation->holdPositionInstructionForShip(ship);
}
- (void)abortDockingForShip:(ShipEntity*)ship
{
    _cxxStation->abortDockingForShip(ship);
}
- (BOOL)shipIsInDockingCorridor:(ShipEntity*)ship
{
    return _cxxStation->shipIsInDockingCorridor(ship);
}
- (void)pullInShipIfPermitted:(ShipEntity*)ship
{
    _cxxStation->pullInShipIfPermitted(ship);
}
- (BOOL)dockingCorridorIsEmpty
{
    return _cxxStation->dockingCorridorIsEmpty();
}
- (void)clearDockingCorridor
{
    _cxxStation->clearDockingCorridor();
}
- (void)update:(OOTimeDelta)delta_t
{
    _cxxStation->cxx::StationEntity::update(delta_t);
}
- (void)clear
{
    _cxxStation->clear();
}
- (BOOL)hasMultipleDocks
{
    return _cxxStation->hasMultipleDocks();
}
- (BOOL)hasClearDock
{
    return _cxxStation->hasClearDock();
}
- (BOOL)hasEligibleDock
{
    return _cxxStation->hasEligibleDock();
}
- (BOOL)hasLaunchDock
{
    return _cxxStation->hasLaunchDock();
}
- (DockEntity*)selectDockForDocking
{
    return _cxxStation->selectDockForDocking();
}
- (void)addShipToLaunchQueue:(ShipEntity*)ship withPriority:(BOOL)priority
{
    _cxxStation->addShipToLaunchQueue(ship, priority);
}
- (unsigned)countOfShipsInLaunchQueueWithPrimaryRole:(const std::string&)role
{
    return _cxxStation->countOfShipsInLaunchQueueWithPrimaryRole(role);
}
- (BOOL)fitsInDock:(ShipEntity*)ship
{
    return _cxxStation->fitsInDock(ship);
}
- (BOOL)fitsInDock:(ShipEntity*)ship andLogNoFit:(BOOL)logNoFit
{
    return _cxxStation->fitsInDock(ship, logNoFit);
}
- (void)noteDockedShip:(ShipEntity*)ship
{
    _cxxStation->noteDockedShip(ship);
}
- (void)addShipToStationCount:(ShipEntity*)ship
{
    _cxxStation->addShipToStationCount(ship);
}

@end

// Slice 3 of docs/phases/3-slices/StationEntity.md (bead oo-hjzwk).
@implementation StationEntity (OOSlice3)

- (BOOL)collideWithShip:(ShipEntity*)other
{
    return _cxxStation->cxx::StationEntity::collideWithShip(other);
}
- (BOOL)hasHostileTarget
{
    return _cxxStation->cxx::StationEntity::hasHostileTarget();
}
- (void)takeEnergyDamage:(double)amount from:(Entity*)ent becauseOf:(Entity*)other weaponIdentifier:(const std::string&)weaponIdentifier
{
    _cxxStation->cxx::StationEntity::takeEnergyDamage(amount, oo::ToCxx(ent), oo::ToCxx(other), weaponIdentifier);
}
- (void)adjustVelocity:(Vector)xVel
{
    _cxxStation->cxx::StationEntity::adjustVelocity(xVel);
}
- (void)takeScrapeDamage:(double)amount from:(Entity*)ent
{
    _cxxStation->cxx::StationEntity::takeScrapeDamage(amount, ent);
}
- (void)takeHeatDamage:(double)amount
{
    _cxxStation->cxx::StationEntity::takeHeatDamage(amount);
}
- (std::optional<std::string>)cxx_allegiance
{
    return _cxxStation->getAllegiance();
}
- (void)cxx_setAllegiance:(const std::optional<std::string>&)newAllegiance
{
    _cxxStation->setAllegiance(newAllegiance);
}
- (OOStationAlertLevel)alertLevel
{
    return _cxxStation->getAlertLevel();
}
- (void)setAlertLevel:(OOStationAlertLevel)level signallingScript:(BOOL)signallingScript
{
    _cxxStation->setAlertLevel(level, signallingScript);
}
- (void)increaseAlertLevel
{
    _cxxStation->increaseAlertLevel();
}
- (void)decreaseAlertLevel
{
    _cxxStation->decreaseAlertLevel();
}
- (void)becomeExplosion
{
    _cxxStation->cxx::StationEntity::becomeExplosion();
}
- (void)becomeEnergyBlast
{
    _cxxStation->cxx::StationEntity::becomeEnergyBlast();
}
- (void)becomeLargeExplosion:(double)factor
{
    _cxxStation->cxx::StationEntity::becomeLargeExplosion(factor);
}
- (void)acceptPatrolReportFrom:(ShipEntity*)patrol_ship
{
    _cxxStation->acceptPatrolReportFrom(patrol_ship);
}
- (std::optional<std::string>)cxx_acceptDockingClearanceRequestFrom:(ShipEntity*)other
{
    return _cxxStation->acceptDockingClearanceRequestFrom(other);
}
- (unsigned)currentlyInDockingQueues
{
    return _cxxStation->currentlyInDockingQueues();
}
- (unsigned)currentlyInLaunchingQueues
{
    return _cxxStation->currentlyInLaunchingQueues();
}

@end

// Slice 4 of docs/phases/3-slices/StationEntity.md (bead oo-tqem7).
@implementation StationEntity (OOSlice4)

- (oo::PList)launchIndependentShip:(const std::string&)role
{
    return _cxxStation->launchIndependentShip(role);
}
- (oo::PList)launchPolice
{
    return _cxxStation->launchPolice();
}
- (ShipEntity*)launchDefenseShip
{
    return _cxxStation->launchDefenseShip();
}
- (ShipEntity*)launchScavenger
{
    return _cxxStation->launchScavenger();
}
- (ShipEntity*)launchMiner
{
    return _cxxStation->launchMiner();
}
- (ShipEntity*)launchPirateShip
{
    return _cxxStation->launchPirateShip();
}
- (ShipEntity*)launchShuttle
{
    return _cxxStation->launchShuttle();
}
- (ShipEntity*)launchEscort
{
    return _cxxStation->launchEscort();
}
- (ShipEntity*)launchPatrol
{
    return _cxxStation->launchPatrol();
}
- (void)launchShipWithRole:(const std::string&)role
{
    _cxxStation->launchShipWithRole(role);
}

@end
