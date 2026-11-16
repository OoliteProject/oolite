/*

StationEntity+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-60fwo and oo-64ako): the Objective-C StationEntity,
the facade over the C++ cxx::StationEntity (StationEntity.h) while the class converts slice by
slice (docs/phases/3-slices/StationEntity.md). Its interface is the one StationEntity.h declared
before slice 1, copied exactly, but for the selectors slice 1 moved to cxx::StationEntity, which
are declared by the category StationEntity (OOSlice1) below and forward to the C++ part. Its
methods of slices 2-4 keep their Objective-C bodies in StationEntity.mm until their slice moves
them. It has one ivar, _cxxStation: the root's _cxxEntity, typed, borrowed (the root owns the
part), set by the initialiser; unconverted code reads the station's members through it by their
old names (_cxxStation->alertLevel). Its initialiser makes the station's adapter over
cxx::StationEntity (oo::ObjCShipEntity<cxx::StationEntity>, ShipEntity+ObjCAdapter.h).
Imported as the last line of StationEntity.h; do not import it directly. Deleted by its deletion
bead once every slice and the callers are C++.

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

#ifndef STATIONENTITY_OBJCBRIDGE_H
#define STATIONENTITY_OBJCBRIDGE_H

@interface StationEntity : ShipEntity {
@public
    cxx::StationEntity* _cxxStation; // _cxxEntity, typed; borrowed, set by the initialiser
}

- (oo::PList)launchIndependentShip:(const std::string&)role; // called by name (ADR-0055 item 5): the ship launched, as an Object node (null: none)

////////////////////////////////////////////////////////////// AI methods...

- (oo::PList)launchPolice; // called by name (ADR-0055 item 5): the ships launched, as Object nodes
- (ShipEntity*)launchDefenseShip;
- (ShipEntity*)launchScavenger;
- (ShipEntity*)launchMiner;
/**Lazygun** added the following line*/
- (ShipEntity*)launchPirateShip;
- (ShipEntity*)launchShuttle;
- (ShipEntity*)launchEscort;
- (ShipEntity*)launchPatrol;

- (void)launchShipWithRole:(const std::string&)role; // called by name (ADR-0055 item 5)

@end

// Slice 1 of docs/phases/3-slices/StationEntity.md (bead oo-64ako): class shell, market and
// shipyard, flags and accessors. Forwarders to cxx::StationEntity, in StationEntity+ObjCBridge.mm.
@interface StationEntity (OOSlice1)

- (OOCargoQuantity)marketCapacity;
- (oo::PList)cxx_marketDefinition; // null: none
- (std::optional<std::string>)cxx_marketScriptName;
- (BOOL)marketMonitored;
- (BOOL)marketBroadcast;
- (OOCreditsQuantity)legalStatusOfManifest:(OOCommodityMarket*)manifest export:(BOOL)isExport;
- (OOCommodityMarket*)localMarket;
- (void)cxx_setLocalMarket:(const oo::PList&)market; // [[key, quantity, price], ...] (OOCommodityMarket -cxx_loadStationAmounts:)
- (oo::PList)cxx_localMarketForScripting;
- (void)cxx_setPrice:(OOCreditsQuantity)price forCommodity:(const std::string&)commodity;
- (void)cxx_setQuantity:(OOCargoQuantity)quantity forCommodity:(const std::string&)commodity;
// The live shipyard, which callers edit in place (proposed ADR-0043 item 22): nullptr on a nil
// receiver or before -generateShipyard.
- (std::vector<oo::PList>*)cxx_localShipyard;
- (void)cxx_setLocalShipyard:(const std::vector<oo::PList>&)shipyard;
- (void)generateShipyard;
- (void)generateShipyard:(OOTechLevelID)stationTechLevel;
- (std::map<std::string, oo::ObjCRef<OOJSInterfaceDefinition*>, std::less<>>*)cxx_localInterfaces; // the live map; nullptr on nil
- (void)cxx_setInterfaceDefinition:(OOJSInterfaceDefinition*)definition forKey:(const std::string&)key; // nil removes
- (OOCommodityMarket*)initialiseLocalMarket;
- (OOTechLevelID)equivalentTechLevel;
- (void)setEquivalentTechLevel:(OOTechLevelID)value;
- (std::vector<oo::ObjCRef<DockEntity*>>)cxx_dockSubEntities; // the -isDock subentities, in subentity order (a snapshot)
- (Vector)virtualPortDimensions;
- (DockEntity*)playerReservedDock;
- (HPVector)beaconPosition;
- (float)equipmentPriceFactor;
- (void)setPlanet:(OOPlanetEntity*)planet;
- (OOPlanetEntity*)planet;
- (unsigned)countOfDockedContractors;
- (unsigned)countOfDockedPolice;
- (unsigned)countOfDockedDefenders;
- (BOOL)interstellarUndockingAllowed;
- (BOOL)hasNPCTraffic;
- (void)setHasNPCTraffic:(BOOL)flag;
- (BOOL)requiresDockingClearance;
- (void)setRequiresDockingClearance:(BOOL)newValue;
- (BOOL)allowsFastDocking;
- (void)setAllowsFastDocking:(BOOL)newValue;
- (BOOL)allowsAutoDocking;
- (void)setAllowsAutoDocking:(BOOL)newValue;
- (BOOL)allowsSaving;
// no setting this after station creation
- (std::optional<std::string>)marketOverrideName; // nullopt: no "market" key
- (BOOL)isRotatingStation;
- (BOOL)hasShipyard;
- (BOOL)suppressArrivalReports;
- (void)setSuppressArrivalReports:(BOOL)newValue;
- (BOOL)hasBreakPattern;
- (void)setHasBreakPattern:(BOOL)newValue;

@end

// The category StationEntity (OOAIPrivate) of ShipEntityAI.mm, slice 1 of
// docs/phases/3-slices/ShipEntityAI.md (bead oo-iebuz): a member of cxx::StationEntity defined in that
// file, forwarded by the category of the same name in StationEntity+ObjCBridge.mm.
@interface StationEntity (OOAIPrivate)

- (void)acceptDistressMessageFrom:(ShipEntity*)other;

@end

// Slice 2 of docs/phases/3-slices/StationEntity.md (bead oo-9j462): docking traffic control and the launch queue. Members of
// cxx::StationEntity, forwarded by the category of the same name in StationEntity+ObjCBridge.mm.
@interface StationEntity (OOSlice2)

- (void)sanityCheckShipsOnApproach;
- (void)launchShip:(ShipEntity*)ship;
- (void)abortAllDockings;
- (void)autoDockShipsOnHold;
- (void)autoDockShipsOnApproach;
- (Vector)portUpVectorForShip:(ShipEntity*)ship;
- (oo::PList)dockingInstructionsForShip:(ShipEntity*)ship; // null: none (bead oo-3rb.262)
- (oo::PList)holdPositionInstructionForShip:(ShipEntity*)ship;
- (void)abortDockingForShip:(ShipEntity*)ship;
- (BOOL)shipIsInDockingCorridor:(ShipEntity*)ship;
- (void)pullInShipIfPermitted:(ShipEntity*)ship;
- (BOOL)dockingCorridorIsEmpty;
- (void)clearDockingCorridor;
- (void)clear;
- (BOOL)hasMultipleDocks;
- (BOOL)hasClearDock;
- (BOOL)hasEligibleDock;
- (BOOL)hasLaunchDock;
- (DockEntity*)selectDockForDocking;
- (void)addShipToLaunchQueue:(ShipEntity*)ship withPriority:(BOOL)priority;
- (unsigned)countOfShipsInLaunchQueueWithPrimaryRole:(const std::string&)role;
- (BOOL)fitsInDock:(ShipEntity*)ship;
- (BOOL)fitsInDock:(ShipEntity*)ship andLogNoFit:(BOOL)logNoFit;
- (void)noteDockedShip:(ShipEntity*)ship;
- (void)addShipToStationCount:(ShipEntity*)ship;

@end

// The send of StationEntity.mm's C function cxx_OOMakeDockingInstructions() to the station it
// reaches as an Objective-C object (amendment oo-9ht.139 item 3); deleted with this header.
OOWeakReference* StationEntityWeakReference(StationEntity* station); // [[station weakRetain] autorelease]

// Slice 3 of docs/phases/3-slices/StationEntity.md (bead oo-hjzwk): docking clearance, damage, allegiance and alert level. Members of
// cxx::StationEntity, forwarded by the category of the same name in StationEntity+ObjCBridge.mm.
@interface StationEntity (OOSlice3)

- (std::optional<std::string>)cxx_allegiance; // nullopt: none
- (void)cxx_setAllegiance:(const std::optional<std::string>&)newAllegiance;
- (OOStationAlertLevel)alertLevel;
- (void)setAlertLevel:(OOStationAlertLevel)level signallingScript:(BOOL)signallingScript;
- (void)increaseAlertLevel;
- (void)decreaseAlertLevel;
- (void)acceptPatrolReportFrom:(ShipEntity*)patrol_ship;
- (std::optional<std::string>)cxx_acceptDockingClearanceRequestFrom:(ShipEntity*)other;
- (unsigned)currentlyInDockingQueues;
- (unsigned)currentlyInLaunchingQueues;

@end

namespace oo {

// The root's crossings, typed (amendment oo-up4b item 3).
inline cxx::StationEntity* ToCxx(::StationEntity* entity)
{
    return static_cast<cxx::StationEntity*>(ToCxx(static_cast<::Entity*>(entity)));
}

inline ::StationEntity* ToObjC(cxx::StationEntity* entity)
{
    return (::StationEntity*)ToObjC(static_cast<cxx::Entity*>(entity));
}

} // namespace oo

#endif // STATIONENTITY_OBJCBRIDGE_H
