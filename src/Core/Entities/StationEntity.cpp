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

#include "StationEntity.h"
#include "DockEntity.h"
#include "OOJSStation.h"
#include "EntityOOJavaScriptExtensions.h"
#include "ShipEntityAI.h"
#include "OOStringParsing.h"

#include "Universe.h"
#include "GameController.h"
#include "HeadUpDisplay.h"
#include "OOConstToString.h"

#include "PlayerEntityLegacyScriptEngine.h"
#include "OOLegacyScriptWhitelist.h"
#include "OOPlanetEntity.h"
#include "OOShipGroup.h"
#include "OOQuiriumCascadeEntity.h"

#include "AI.h"
#include "OOCharacter.h"

#include "OOJSScript.h"
#include "OODebugGLDrawing.h"
#include "OODebugFlags.h"
#include "OODebugStandards.h"
#include "OOPListGameTypes.h"
#include "OOObjCPList.h"
#include "oofnd/Log.hpp"
#include "oofnd/String.hpp"


// -oo_stringForKey:'s value without the Foundation type (proposed ADR-0043): a string as is, a
// number's -stringValue, anything else (or nothing) nullopt, as it gave nil.
namespace
{

std::optional<std::string> OptionalStringValue(const oo::PList *value)
{
	if (value == nullptr)  return std::nullopt;
	if (const std::string *string = value->getIf<std::string>())  return *string;
	if (value->isNumber())  return oo::plist_get::numberStringValue(*value);
	return std::nullopt;
}

}	// namespace


oo::PList cxx_OOMakeDockingInstructions(StationEntity *station, HPVector coords, float speed, float range, const std::optional<std::string> &ai_message, const std::optional<std::string> &comms_message, BOOL match_rotation, int docking_stage)
{
	oo::PList::Dict acc;
	// destination as OOPropertyListFromHPVector built it (doubles); speed and range as -oo_setFloat:
	// stored them (+numberWithDouble:); docking_stage as -oo_setInteger: (signed)
	acc["destination"] = oo::PList(oo::PList::Dict{ { "x", oo::PList(coords.x) }, { "y", oo::PList(coords.y) }, { "z", oo::PList(coords.z) } });
	acc["speed"] = oo::PList(static_cast<double>(speed));
	acc["range"] = oo::PList(static_cast<double>(range));
	acc["station"] = oo::EntityWeakNode(station);	// weakly, as its object's weak reference was (bead oo-w9pi2)
	acc["match_rotation"] = oo::PList(static_cast<bool>(match_rotation));
	acc["docking_stage"] = oo::PList::signedInteger(docking_stage);
	if (ai_message)
	{
		acc["ai_message"] = oo::PList(*ai_message);
	}
	if (comms_message)
	{
		acc["comms_message"] = oo::PList(*comms_message);
	}
	return oo::PList(std::move(acc));
}


// Slice 4 of docs/phases/3-slices/StationEntity.md (bead oo-tqem7): NPC launchers. Several are sent
// by name (ADR-0055 item 5), which the root's facade answers for a station's part (beads oo-9ht.175,
// oo-9ht.144).


// Exposed to AI
oo::PList StationEntity::launchIndependentShip(const std::string &role)	// called by name (ADR-0055 item 5): the ship launched, as an Object node (null: none)
{
	ShipEntity *self = this;
	if (!hasLaunchDock())
	{
		OO_LOG("station.launchShip.impossible", "Cancelled launch for a ship with role {}, as the {} has no launch docks.",
			  role, getDisplayName().value_or("(null)"));
		return oo::PList();
	}

	std::string		shipRole = role;
	BOOL			trader = shipRole == "trader";
	BOOL			sunskimmer = (shipRole == "sunskim-trader");
	::ShipEntity		*ship = nil;

	if((trader && (randf() < 0.1)) || sunskimmer)
	{
		ship = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole("sunskim-trader") : (::ShipEntity *)nil);
		sunskimmer = true;
		trader = true;
		shipRole = "trader"; // make sure also sunskimmers get trader role.
	}
	else
	{
		ship = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole(shipRole) : (::ShipEntity *)nil);
	}

	if (!fitsInDock(ship))
	{
		if (ship != nullptr)  oo::ReleaseEntity(ship);
		return oo::PList();
	}
	
	if (ship)
	{
		if (!(ship != nullptr ? ship->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>()).has_value())
		{
			if (ship != nullptr)  ship->setSingleCrewWithRole(shipRole);
		}
		if (ship != nullptr)  ship->setPrimaryRole(shipRole);

		if(trader || ship->scanClass == CLASS_NOT_SET)  { if (ship != nullptr)  ship->setScanClass(CLASS_NEUTRAL); } // keep defined scanclasses for non-traders.
		
		if (trader)
		{
			if (ship != nullptr)  ship->setBounty(0, kOOLegalStatusReasonSetup);
			if (ship != nullptr)  ship->setCargoFlag(CARGO_FLAG_FULL_PLENTIFUL);
			if (sunskimmer) 
			{
				if (ship != nullptr)  ship->setFuel((Ranrot()&31));
				if (UNIVERSE != nullptr)  UNIVERSE->makeSunSkimmer(ship, YES);
			}
			else
			{
// JSAI: not needed - oolite-traderAI.js handles exiting if full fuel and plentiful cargo
//				[ship switchAITo:@"exitingTraderAI.plist"];
				if((ship != nullptr ? ship->getFuel() : OOFuelQuantity{}) == 0) { if (ship != nullptr)  ship->setFuel(70); }
//				if ([ship hasRole:"sunskim-trader"]) [UNIVERSE makeSunSkimmer:ship andSetAI:NO];
			}
		}
		
		addShipToLaunchQueue(ship, NO);

		::OOShipGroup *escortGroup = (ship != nullptr ? ship->escortGroup() : (OOShipGroup *)nullptr);
		if ((ship != nullptr ? ship->group() : (OOShipGroup *)nullptr) == nil) { if (ship != nullptr)  ship->setGroup(escortGroup); }
		// Eric: Escorts are defined both as _group and as _escortGroup because friendly attacks are only handled within _group.
		if (escortGroup != nullptr)  escortGroup->setLeader(ship);
				
		// add escorts to the trader
		unsigned escorts = (ship != nullptr ? ship->pendingEscortCount() : uint8_t{});
		if(escorts > 0)
		{
			if (ship != nullptr)  ship->setOwner(self); // makes escorts get added to station launch queue
			if (ship != nullptr)  ship->setUpEscorts();
			if (ship != nullptr)  ship->setOwner(ship);
		}
		
		if (ship != nullptr)  ship->setPendingEscortCount(0);
		if (ship != nullptr)  oo::ToShip(oo::AutoreleaseEntity(ship));
	}
	return oo::EntityObjectNode(ship);
}


// Exposed to AI
oo::PList StationEntity::launchPolice()	// called by name (ADR-0055 item 5)
{
	std::vector<oo::EntityHold>	result;	// the police ships' objects, held (bead oo-9ht.39.19)
	if (!hasLaunchDock())
	{
		OO_LOG("station.launchShip.impossible", "Cancelled launch for a police ship, as the {} has no launch docks.",
			  getDisplayName().value_or("(null)"));
		return oo::EntityNodesFrom(result);
	}

	OOUniversalID	police_target = (primaryTarget() != nullptr ? primaryTarget()->getUniversalID() : OOUniversalID{});
	unsigned		i;
	OOTechLevelID	techlevel = getEquivalentTechLevel();
	if (techlevel == NSNotFound)  techlevel = 6;

	result.reserve(4);

	for (i = 0; (i < 4)&&(defenders_launched < max_police) ; i++)
	{
		::ShipEntity  *police_ship = nil;
		if ((UNIVERSE != nullptr ? UNIVERSE->entityForUniversalID(police_target) : nullptr) == nullptr)
		{
			noteLostTarget();
			return oo::EntityNodesFrom(std::vector<oo::EntityHold>());
		}
		/* this is more likely to give interceptors than the
		 * equivalent populator function: save them for defense
		 * ships */
		if ((Ranrot() & 3) + 9 < techlevel)
		{
			police_ship = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole("interceptor") : (::ShipEntity *)nil);   // retain count = 1
		}
		else
		{
			police_ship = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole("police") : (::ShipEntity *)nil);   // retain count = 1
		}
		
		if (police_ship && fitsInDock(police_ship))
		{
			if (!(police_ship != nullptr ? police_ship->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>()).has_value())
			{
				if (police_ship != nullptr)  police_ship->setSingleCrewWithRole("police");
			}
			
			if (police_ship != nullptr)  police_ship->setGroup(stationGroup());	// who's your Daddy
			if (police_ship != nullptr)  police_ship->setPrimaryRole("police");
			if (police_ship != nullptr)  police_ship->addTarget((UNIVERSE != nullptr ? UNIVERSE->entityForUniversalID(police_target) : nullptr));
			if ((police_ship != nullptr ? police_ship->getScanClass() : OOScanClass{}) == CLASS_NOT_SET)
				if (police_ship != nullptr)  police_ship->setScanClass(CLASS_POLICE);
			if (police_ship != nullptr)  police_ship->setBounty(0, kOOLegalStatusReasonSetup);
			if ((police_ship != nullptr ? police_ship->heatInsulation() : 0.0f) < heatInsulation())
				if (police_ship != nullptr)  police_ship->setHeatInsulation(heatInsulation());
			if (police_ship != nullptr)  police_ship->switchAITo("oolite-defenseShipAI.js");
			addShipToLaunchQueue(police_ship, YES);
			defenders_launched++;
			result.push_back(oo::EntityHold(police_ship));
		}
		if (police_ship != nullptr)  oo::ToShip(oo::AutoreleaseEntity(police_ship));
	}
	abortAllDockings();
	return oo::EntityNodesFrom(result);
}


// Exposed to AI
::ShipEntity *StationEntity::launchDefenseShip()
{
	ShipEntity *self = this;
	if (!hasLaunchDock())
	{
		OO_LOG("station.launchShip.impossible", "Cancelled launch for a defense ship, as the {} has no launch docks.",
			  getDisplayName().value_or("(null)"));
		return nil;
	}

	OOUniversalID	defense_target = (primaryTarget() != nullptr ? primaryTarget()->getUniversalID() : OOUniversalID{});
	::ShipEntity	*defense_ship = nil;
	std::string	default_defense_ship_role;
	const std::string	defense_ship_ai = "oolite-defenseShipAI.js";
	
	OOTechLevelID	techlevel;
	
	techlevel = getEquivalentTechLevel();
	if (techlevel == NSNotFound)  techlevel = 6;
	if ((Ranrot() & 7) + 6 <= techlevel)
		default_defense_ship_role	= "interceptor";
	else
		default_defense_ship_role	= "police";

	if (scanClass == CLASS_ROCK)
		default_defense_ship_role	= "hermit-ship";
	
	if (defenders_launched >= max_defense_ships)   // shuttles are to rockhermits what police ships are to stations
		return nil;
	
	if ((UNIVERSE != nullptr ? UNIVERSE->entityForUniversalID(defense_target) : nullptr) == nullptr)
	{
		noteLostTarget();
		return nil;
	}
	
	const std::optional<std::string> defense_ship_key = OptionalStringValue(shipinfoDictionary.find("defense_ship"));	// -oo_stringForKey:
	if (defense_ship_key)
	{
		defense_ship = (UNIVERSE != nullptr ? UNIVERSE->newShipWithName(*defense_ship_key) : (::ShipEntity *)nil);
	}
	// The retry below was a pointer comparison of the role with the default role string: it ran
	// exactly when shipdata supplied defense_ship_role (-oo_stringForKey:defaultValue: returned the
	// default object itself otherwise).
	bool shipdataSuppliedRole = false;
	if (!defense_ship)
	{
		const std::optional<std::string> defense_ship_role = OptionalStringValue(shipinfoDictionary.find("defense_ship_role"));
		shipdataSuppliedRole = defense_ship_role.has_value();
		defense_ship = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole(defense_ship_role.value_or(default_defense_ship_role)) : (::ShipEntity *)nil);
	}

	if (!defense_ship && shipdataSuppliedRole)
		defense_ship = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole(default_defense_ship_role) : (::ShipEntity *)nil);

	if (!defense_ship || !fitsInDock(defense_ship))
	{
		if (defense_ship != nullptr)  oo::ReleaseEntity(defense_ship);
		return nil;
	}
	
	if ((defense_ship != nullptr ? defense_ship->isPolice() : false) || (defense_ship != nullptr ? defense_ship->hasPrimaryRole("hermit-ship") : false))
	{
		if (defense_ship != nullptr)  defense_ship->switchAITo(defense_ship_ai);
	}
	
	if (defense_ship != nullptr)  defense_ship->setPrimaryRole("defense_ship");
	
	defenders_launched++;
	
	if (!(defense_ship != nullptr ? defense_ship->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>()).has_value())
	{
		if ((defense_ship != nullptr ? defense_ship->isPolice() : false))
		{
			if (defense_ship != nullptr)  defense_ship->setSingleCrewWithRole("police");
		}
		else
		{
			if (defense_ship != nullptr)  defense_ship->setSingleCrewWithRole("hunter");
		}
	}
				
	if (defense_ship != nullptr)  defense_ship->setOwner(self);
	if (group() == nil)
	{
		setGroup(stationGroup());	
	}
	if (defense_ship != nullptr)  defense_ship->setGroup(stationGroup());	// who's your Daddy
	
	if (defense_ship != nullptr)  defense_ship->addTarget((UNIVERSE != nullptr ? UNIVERSE->entityForUniversalID(defense_target) : nullptr));

	if ((scanClass != CLASS_ROCK)&&(scanClass != CLASS_STATION))
	{
		if (defense_ship != nullptr)  defense_ship->setScanClass(scanClass);	// same as self
	}
	else if ((defense_ship != nullptr ? defense_ship->getScanClass() : OOScanClass{}) == CLASS_NOT_SET)
	{
		if (defense_ship != nullptr)  defense_ship->setScanClass(CLASS_NEUTRAL);
	}

	if ((defense_ship != nullptr ? defense_ship->heatInsulation() : 0.0f) < heatInsulation())
	{
		if (defense_ship != nullptr)  defense_ship->setHeatInsulation(heatInsulation());
	}

	addShipToLaunchQueue(defense_ship, YES);
	if (defense_ship != nullptr)  oo::ToShip(oo::AutoreleaseEntity(defense_ship));
	abortAllDockings();
	
	return defense_ship;
}


// Exposed to AI
::ShipEntity *StationEntity::launchScavenger()
{
	ShipEntity *self = this;
	if (!hasLaunchDock())
	{
		OO_LOG("station.launchShip.impossible", "Cancelled launch for a scavenger ship, as the {} has no launch docks.",
			  getDisplayName().value_or("(null)"));
		return nil;
	}

	::ShipEntity  *scavenger_ship;
	
	unsigned scavs = (UNIVERSE != nullptr ? UNIVERSE->countShipsWithPrimaryRole("scavenger", SCANNER_MAX_RANGE, self) : 0u) + countOfShipsInLaunchQueueWithPrimaryRole("scavenger");
	
	if (scavs >= max_scavengers)  return nil;
	if (scavengers_launched >= max_scavengers)  return nil;
			
	scavenger_ship = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole("scavenger") : (::ShipEntity *)nil);   // retain count = 1
	
	if (!fitsInDock(scavenger_ship))
	{
		if (scavenger_ship != nullptr)  oo::ReleaseEntity(scavenger_ship);
		return nil;
	}
	
	if (scavenger_ship)
	{
		if (!(scavenger_ship != nullptr ? scavenger_ship->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>()).has_value())
		{
			if (scavenger_ship != nullptr)  scavenger_ship->setSingleCrewWithRole("miner");
		}
				
		scavengers_launched++;
		if (scavenger_ship != nullptr)  scavenger_ship->setScanClass(CLASS_NEUTRAL);
		if ((scavenger_ship != nullptr ? scavenger_ship->heatInsulation() : 0.0f) < heatInsulation())
			if (scavenger_ship != nullptr)  scavenger_ship->setHeatInsulation(heatInsulation());
		if (scavenger_ship != nullptr)  scavenger_ship->setGroup(stationGroup());	// who's your Daddy -- FIXME: should we have a separate group for non-escort auxiliaires?
		if (scavenger_ship != nullptr)  scavenger_ship->switchAITo("oolite-scavengerAI.js");
		addShipToLaunchQueue(scavenger_ship, NO);
		if (scavenger_ship != nullptr)  oo::ToShip(oo::AutoreleaseEntity(scavenger_ship));
	}
	return scavenger_ship;
}


// Exposed to AI
::ShipEntity *StationEntity::launchMiner()
{
	ShipEntity *self = this;
	if (!hasLaunchDock())
	{
		OO_LOG("station.launchShip.impossible", "Cancelled launch for a miner ship, as the {} has no launch docks.",
			  getDisplayName().value_or("(null)"));
		return nil;
	}

	::ShipEntity  *miner_ship;
	
	int		n_miners = (UNIVERSE != nullptr ? UNIVERSE->countShipsWithPrimaryRole("miner", SCANNER_MAX_RANGE, self) : 0u) + countOfShipsInLaunchQueueWithPrimaryRole("miner");
	
	if (n_miners >= 1)	// just the one
		return nil;
	
	// count miners as scavengers...
	if (scavengers_launched >= max_scavengers)  return nil;
	
	miner_ship = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole("miner") : (::ShipEntity *)nil);   // retain count = 1

	if (!fitsInDock(miner_ship))
	{
		if (miner_ship != nullptr)  oo::ReleaseEntity(miner_ship);
		return nil;
	}
	
	if (miner_ship)
	{
		if (!(miner_ship != nullptr ? miner_ship->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>()).has_value())
		{
			if (miner_ship != nullptr)  miner_ship->setSingleCrewWithRole("miner");
		}
				
		scavengers_launched++;
		if (miner_ship != nullptr)  miner_ship->setScanClass(CLASS_NEUTRAL);
		if ((miner_ship != nullptr ? miner_ship->heatInsulation() : 0.0f) < heatInsulation())
			if (miner_ship != nullptr)  miner_ship->setHeatInsulation(heatInsulation());
		if (miner_ship != nullptr)  miner_ship->setGroup(stationGroup());	// who's your Daddy -- FIXME: should we have a separate group for non-escort auxiliaires?
		if (miner_ship != nullptr)  miner_ship->switchAITo("oolite-scavengerAI.js");
		addShipToLaunchQueue(miner_ship, NO);
		if (miner_ship != nullptr)  oo::ToShip(oo::AutoreleaseEntity(miner_ship));
	}
	return miner_ship;
}

/**Lazygun** added the following method. A complete rip-off of launchDefenseShip. 
 */
// Exposed to AI
::ShipEntity *StationEntity::launchPirateShip()
{
	ShipEntity *self = this;
	if (!hasLaunchDock())
	{
		OO_LOG("station.launchShip.impossible", "Cancelled launch for a pirate ship, as the {} has no launch docks.",
			  getDisplayName().value_or("(null)"));
		return nil;
	}
	//Pirate ships are launched from the same pool as defence ships.
	OOUniversalID	defense_target = (primaryTarget() != nullptr ? primaryTarget()->getUniversalID() : OOUniversalID{});
	::ShipEntity		*pirate_ship = nil;
	
	if (defenders_launched >= max_defense_ships)  return nil;   // shuttles are to rockhermits what police ships are to stations
	
	if ((UNIVERSE != nullptr ? UNIVERSE->entityForUniversalID(defense_target) : nullptr) == nullptr)
	{
		noteLostTarget();
		return nil;
	}
	
	// Yep! The standard hermit defence ships, even if they're the aggressor.
	pirate_ship = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole("pirate") : (::ShipEntity *)nil);   // retain count = 1
	// Nope, use standard pirates in a generic method.
	
	if (!fitsInDock(pirate_ship))
	{
		if (pirate_ship != nullptr)  oo::ReleaseEntity(pirate_ship);
		return nil;
	}
		
	if (pirate_ship)
	{
		if (!(pirate_ship != nullptr ? pirate_ship->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>()).has_value())
		{
			if (pirate_ship != nullptr)  pirate_ship->setSingleCrewWithRole("pirate");
		}
				
		defenders_launched++;
		
		// set the owner of the ship to the station so that it can check back for docking later
		if (pirate_ship != nullptr)  pirate_ship->setOwner(self);
		if (pirate_ship != nullptr)  pirate_ship->setGroup(stationGroup());	// who's your Daddy
		if (pirate_ship != nullptr)  pirate_ship->setPrimaryRole("defense_ship");
		if (pirate_ship != nullptr)  pirate_ship->addTarget((UNIVERSE != nullptr ? UNIVERSE->entityForUniversalID(defense_target) : nullptr));
		if (pirate_ship != nullptr)  pirate_ship->setScanClass(CLASS_NEUTRAL);
		if ((pirate_ship != nullptr ? pirate_ship->heatInsulation() : 0.0f) < heatInsulation())
			if (pirate_ship != nullptr)  pirate_ship->setHeatInsulation(heatInsulation());
		//**Lazygun** added 30 Nov 04 to put a bounty on those pirates' heads.
		if (pirate_ship != nullptr)  pirate_ship->setBounty(10 + floor(randf() * 20), kOOLegalStatusReasonSetup);	// modified for variety

		addShipToLaunchQueue(pirate_ship, NO);
		if (pirate_ship != nullptr)  oo::ToShip(oo::AutoreleaseEntity(pirate_ship));
		abortAllDockings();
	}
	return pirate_ship;
}


// Exposed to AI
::ShipEntity *StationEntity::launchShuttle()
{
	if (!hasLaunchDock())
	{
		OO_LOG("station.launchShip.impossible", "Cancelled launch for a shuttle ship, as the {} has no launch docks.",
			  getDisplayName().value_or("(null)"));
		return nil;
	}
	::ShipEntity  *shuttle_ship;
		
	shuttle_ship = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole("shuttle") : (::ShipEntity *)nil);   // retain count = 1
	
	if (!fitsInDock(shuttle_ship))
	{
		if (shuttle_ship != nullptr)  oo::ReleaseEntity(shuttle_ship);
		return nil;
	}
	
	if (shuttle_ship)
	{
		if (!(shuttle_ship != nullptr ? shuttle_ship->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>()).has_value())
		{
			if (shuttle_ship != nullptr)  shuttle_ship->setSingleCrewWithRole("trader");
		}
		
		docked_shuttles--;
		if (shuttle_ship != nullptr)  shuttle_ship->setScanClass(CLASS_NEUTRAL);
		if (shuttle_ship != nullptr)  shuttle_ship->setCargoFlag(CARGO_FLAG_FULL_SCARCE);
		if (shuttle_ship != nullptr)  shuttle_ship->switchAITo("oolite-shuttleAI.js");
		addShipToLaunchQueue(shuttle_ship, NO);
		
		if (shuttle_ship != nullptr)  oo::ToShip(oo::AutoreleaseEntity(shuttle_ship));
	}
	return shuttle_ship;
}


// Exposed to AI
::ShipEntity *StationEntity::launchEscort()
{
	if (!hasLaunchDock())
	{
		OO_LOG("station.launchShip.impossible", "Cancelled launch for an escort ship, as the {} has no launch docks.",
			  getDisplayName().value_or("(null)"));
		return nil;
	}
	::ShipEntity  *escort_ship;
		
	escort_ship = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole("escort") : (::ShipEntity *)nil);   // retain count = 1
	
	if (escort_ship && fitsInDock(escort_ship))
	{
		if (!(escort_ship != nullptr ? escort_ship->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>()).has_value())
		{
			if (escort_ship != nullptr)  escort_ship->setSingleCrewWithRole("hunter");
		}
				
		if (escort_ship != nullptr)  escort_ship->setScanClass(CLASS_NEUTRAL);
		if (escort_ship != nullptr)  escort_ship->setCargoFlag(CARGO_FLAG_FULL_PLENTIFUL);
		if (escort_ship != nullptr)  escort_ship->switchAITo("oolite-escortAI.js");
		addShipToLaunchQueue(escort_ship, NO);
		
	}
	if (escort_ship != nullptr)  oo::ReleaseEntity(escort_ship);
	return escort_ship;
}


// Exposed to AI
::ShipEntity *StationEntity::launchPatrol()
{
	if (!hasLaunchDock())
	{
		OO_LOG("station.launchShip.impossible", "Cancelled launch for a patrol ship, as the {} has no launch docks.",
			  getDisplayName().value_or("(null)"));
		return nil;
	}
	if (defenders_launched < max_police)
	{
		::ShipEntity		*patrol_ship = nil;
		OOTechLevelID	techlevel;
		
		techlevel = getEquivalentTechLevel();
		if (techlevel == NSNotFound)
			techlevel = 6;
			
		if ((Ranrot() & 7) + 6 <= techlevel)
			patrol_ship = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole("interceptor") : (::ShipEntity *)nil);   // retain count = 1
		else
			patrol_ship = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole("police") : (::ShipEntity *)nil);   // retain count = 1

		if (!fitsInDock(patrol_ship))
		{
			if (patrol_ship != nullptr)  oo::ReleaseEntity(patrol_ship);
			return nil;
		}
		
		if (patrol_ship)
		{
			if (!(patrol_ship != nullptr ? patrol_ship->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>()).has_value())
			{
				if (patrol_ship != nullptr)  patrol_ship->setSingleCrewWithRole("police");
			}
			
			defenders_launched++;
			if (patrol_ship != nullptr)  patrol_ship->switchLightsOff();
			if ((patrol_ship != nullptr ? patrol_ship->getScanClass() : OOScanClass{}) == CLASS_NOT_SET)
				if (patrol_ship != nullptr)  patrol_ship->setScanClass(CLASS_POLICE);
			if ((patrol_ship != nullptr ? patrol_ship->heatInsulation() : 0.0f) < heatInsulation())
				if (patrol_ship != nullptr)  patrol_ship->setHeatInsulation(heatInsulation());
			if (patrol_ship != nullptr)  patrol_ship->setPrimaryRole("police-station-patrol");
			if (patrol_ship != nullptr)  patrol_ship->setBounty(0, kOOLegalStatusReasonSetup);
			if (patrol_ship != nullptr)  patrol_ship->setGroup(stationGroup());	// who's your Daddy
			if (patrol_ship != nullptr)  patrol_ship->switchAITo("oolite-policeAI.js");
			addShipToLaunchQueue(patrol_ship, NO);
			acceptPatrolReportFrom(patrol_ship);
			if (patrol_ship != nullptr)  oo::ToShip(oo::AutoreleaseEntity(patrol_ship));
			return patrol_ship;
		}
	}
	return nil;
}


// Exposed to AI
void StationEntity::launchShipWithRole(const std::string &role)	// called by name (ADR-0055 item 5)
{
	if (!hasLaunchDock())
	{
		OO_LOG("station.launchShip.impossible", "Cancelled launch for a ship with role {}, as the {} has no launch docks.",
			  role, getDisplayName().value_or("(null)"));
		return;
	}
	const std::string &shipRole = role;
	::ShipEntity  *ship = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole(shipRole) : (::ShipEntity *)nil);   // retain count = 1
	if (ship && fitsInDock(ship))
	{
		if (!(ship != nullptr ? ship->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>()).has_value())
		{
			if (ship != nullptr)  ship->setSingleCrewWithRole(shipRole);
		}
		if (ship->scanClass == CLASS_NOT_SET) { if (ship != nullptr)  ship->setScanClass(CLASS_NEUTRAL); }
		if (ship != nullptr)  ship->setPrimaryRole(shipRole);
		if (ship != nullptr)  ship->setGroup(stationGroup());	// who's your Daddy
		addShipToLaunchQueue(ship, NO);
	}
	if (ship != nullptr)  oo::ReleaseEntity(ship);
}



// Slice 1 of docs/phases/3-slices/StationEntity.md (bead oo-64ako): class shell, market and
// shipyard, flags and accessors. The facade's initialiser and -dealloc are members since bead
// oo-9ht.175 deleted the facade (ADR-0056 amendment oo-9ht.175).


::ShipEntity *StationEntity::newStationObject(const std::string &key, const oo::PList &dict)
{
	::ShipEntity *object = oo::ToShip(oo::NewShipObject(oo::makeRef<StationEntity>(), key, dict));	// [super cxx_initWithKey:key definition:dict]
	if (object != nil)  static_cast<StationEntity *>(object)->initStationDefaults();
	return object;
}


void StationEntity::initStationDefaults()
{
	OOJS_PROFILE_ENTER

	isStation = YES;
	_shipsOnHold.removeAll();	// a new, empty set
	hasBreakPattern = YES;

	OOJS_PROFILE_EXIT_VOID
}


void StationEntity::willDealloc()
{
	_shipsOnHold.removeAll();
	localMarket = nullptr;
//	DESTROY(localPassengers);
//	DESTROY(localContracts);
}


/* Override ShipEntity: stations of CLASS_ROCK or CLASS_CARGO are not automatically unpiloted. */
bool StationEntity::isUnpiloted()
{
	return isExplicitlyUnpiloted() || getIsHulk();
}


void StationEntity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)
{
	::OOJSStationGetJSClass(outClass, outPrototype);
}


bool StationEntity::isVisibleToScripts()
{
	return ::ShipEntityJSIsVisibleToScripts();
}


std::optional<std::string> StationEntity::jsClassName()
{
	return ::OOJSStationJSClassName();
}


OOTechLevelID StationEntity::getEquivalentTechLevel()
{
	if (equivalentTechLevel == NSNotFound)
	{
		return (UNIVERSE != nullptr ? UNIVERSE->currentSystemData() : oo::PList()).get<int>(std::string(KEY_TECHLEVEL));
	}
	else
	{
		return equivalentTechLevel;
	}
}


void StationEntity::setEquivalentTechLevel(OOTechLevelID value)
{
	equivalentTechLevel = value;
}


Vector StationEntity::virtualPortDimensions()
{
	return port_dimensions;
}


::DockEntity *StationEntity::playerReservedDock()
{
	return player_reserved_dock;
}


HPVector StationEntity::beaconPosition()
{
	double buoy_distance = 10000.0;				// distance from station entrance
	Vector v_f = vector_forward_from_quaternion(getOrientation());
	HPVector result = HPvector_add(getPosition(), vectorToHPVector(vector_multiply_scalar(v_f, buoy_distance)));
	
	return result;
}


float StationEntity::getEquipmentPriceFactor()
{
	return equipmentPriceFactor;
}


OOCargoQuantity StationEntity::getMarketCapacity()
{
	return marketCapacity;
}


oo::PList StationEntity::getMarketDefinition()
{
	return marketDefinition;
}


std::optional<std::string> StationEntity::getMarketScriptName()
{
	return marketScriptName;
}


bool StationEntity::getMarketMonitored()
{
	if (this == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr))
	{
		return YES;
	}
	return marketMonitored;
}


bool StationEntity::getMarketBroadcast()
{
	if (this == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr))
	{
		return YES;
	}
	return marketBroadcast;
}


OOCreditsQuantity StationEntity::legalStatusOfManifest(::OOCommodityMarket *manifest, bool isExport)
{
	OOCreditsQuantity penalty, status = 0;
	::OOCommodityMarket *market = getLocalMarket();
	for (const std::string &good : market->goods())
	{
		if (isExport)
		{
			penalty = market->exportLegalityForGood(good);
		}
		else
		{
			penalty = market->importLegalityForGood(good);
		}
		status += penalty * manifest->quantityForGood(good);
	}
	return status;
}


::OOCommodityMarket *StationEntity::getLocalMarket()
{
	if (this == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr))
	{
		// main stations use the system market
		// just return a reference
		return (UNIVERSE != nullptr ? UNIVERSE->getCommodityMarket() : nullptr);
	}
	if (!localMarket)
	{
		initialiseLocalMarket();
	}
	return localMarket.get();
}


void StationEntity::setLocalMarket(const oo::PList &some_market)
{
	OOCommodityMarket *market = getLocalMarket();	// null: nothing set, as a message to nil
	if (market != nullptr)  market->loadStationAmounts(some_market);
}


oo::PList StationEntity::localMarketForScripting()
{
	OOCommodityMarket *market = getLocalMarket();	// null: null, as a message to nil
	return (market != nullptr) ? market->dictionaryForScripting() : oo::PList();
}


void StationEntity::setPrice(OOCreditsQuantity price, const std::string &commodity)
{
	OOCommodityMarket *market = getLocalMarket();	// null: nothing set, as a message to nil
	if (market != nullptr)  market->setPrice(price, commodity);
}


void StationEntity::setQuantity(OOCargoQuantity quantity, const std::string &commodity)
{
	OOCommodityMarket *market = getLocalMarket();	// null: nothing set, as a message to nil
	if (market != nullptr)  market->setQuantity(quantity, commodity);
}


std::vector<oo::PList> *StationEntity::getLocalShipyard()
{
	return localShipyard ? &*localShipyard : nullptr;
}


void StationEntity::setLocalShipyard(const std::vector<oo::PList> &some_market)
{
	localShipyard = some_market;
}


std::map<std::string, oo::Ref<::OOJSInterfaceDefinition>, std::less<>> *StationEntity::getLocalInterfaces()
{
	return &localInterfaces;
}


void StationEntity::setInterfaceDefinition(::OOJSInterfaceDefinition *definition, const std::string &key)
{
	if (definition == nullptr)
	{
		localInterfaces.erase(key);
	}
	else
	{
		localInterfaces[key] = oo::Ref<::OOJSInterfaceDefinition>(definition);
	}
}


::OOCommodityMarket *StationEntity::initialiseLocalMarket()
{
	localMarket = ((UNIVERSE != nullptr ? UNIVERSE->getCommodities() : nullptr) != nullptr ? UNIVERSE->getCommodities()->generateMarketForStation(this) : oo::Ref<OOCommodityMarket>());
	return localMarket.get();
}


void StationEntity::setPlanet(::OOPlanetEntity *planet_entity)
{
	if (planet_entity)
		planet = (planet_entity != nullptr ? planet_entity->getUniversalID() : OOUniversalID{});
	else
		planet = NO_TARGET;
}


::OOPlanetEntity *StationEntity::getPlanet()
{
	// The planet is C++ since bead oo-9ht.129: null for any other entity (and for none, as nil).
	return dynamic_cast<::OOPlanetEntity *>((UNIVERSE != nullptr ? UNIVERSE->entityForUniversalID(planet) : nullptr));
}


unsigned StationEntity::countOfDockedContractors()
{
	return max_scavengers > scavengers_launched ? max_scavengers - scavengers_launched : 0;
}


unsigned StationEntity::countOfDockedPolice()
{
	return max_police > defenders_launched ? max_police - defenders_launched : 0;
}


unsigned StationEntity::countOfDockedDefenders()
{
	return max_defense_ships > defenders_launched ? max_defense_ships - defenders_launched : 0;
}


std::vector<oo::EntityHold> StationEntity::dockSubEntities()
{
	std::vector<oo::EntityHold> result;
	for (const auto &subRef : getSubEntities())
	{
		Entity *sub = subRef.get();
		if (sub == nullptr || !sub->isDock())  continue;	// -isDock
		result.push_back(subRef);	// a dock, held
	}
	return result;
}


bool StationEntity::setUpShipFromDictionary(const oo::PList &dict)
{
	OOJS_PROFILE_ENTER
	
		isShip = YES;
	isStation = YES;
	alertLevel = STATION_ALERT_LEVEL_GREEN;
	
	port_radius = dict.get<oo::NonNegative<double>>("port_radius", 500.0);
	
	// port_dimensions is deprecated
	port_dimensions = make_vector(69, 69, 250);
	const std::optional<std::string> portDimensionsStr = OptionalStringValue(dict.find("port_dimensions"));	// -oo_stringForKey:
	if (portDimensionsStr)
	{
		cxx_OOStandardsDeprecated("The port_dimensions key is deprecated");
		if (!OOEnforceStandards())
		{
			const std::vector<std::string> tokens = oo::str::split(*portDimensionsStr, "x");
			if (tokens.size() == 3)
			{
				// -floatValue
				port_dimensions = make_vector((float)oo::str::doubleValue(tokens[0]),
											  (float)oo::str::doubleValue(tokens[1]),
											  (float)oo::str::doubleValue(tokens[2]));
			}
		}
	}
	
	if (!ShipEntity::setUpShipFromDictionary(dict))  return NO;
	
	equivalentTechLevel = dict.get<NSUInteger>("equivalent_tech_level", NSNotFound);
	max_scavengers = dict.get<unsigned int>("max_scavengers", 3);
	max_defense_ships = dict.get<unsigned int>("max_defense_ships", 3);
	max_police = dict.get<unsigned int>("max_police", STATION_MAX_POLICE);
	equipmentPriceFactor = dict.get<oo::NonNegative<float>>("equipment_price_factor", 1.0);
	equipmentPriceFactor = fmax(equipmentPriceFactor, 0.5f);
	hasNPCTraffic = (unsigned char)OOFuzzyBooleanFromPList(dict.find("has_npc_traffic"), (maxFlightSpeed == 0)); // carriers default to NO
	hasPatrolShips = OOFuzzyBooleanFromPList(dict.find("has_patrol_ships"), NO);
	suppress_arrival_reports = (unsigned char)dict.get<bool>("suppress_arrival_reports", NO);
	setAllegiance(OptionalStringValue(dict.find("allegiance")));

	marketCapacity = dict.get<unsigned int>("market_capacity", MAIN_SYSTEM_MARKET_LIMIT);
	const oo::PList *marketDefinitionValue = dict.get<oo::PList::Array>("market_definition");
	marketDefinition = (marketDefinitionValue != nullptr) ? *marketDefinitionValue : oo::PList();	// oo_arrayForKey:
	marketScriptName = OptionalStringValue(dict.find("market_script"));
	marketMonitored = (unsigned char)dict.get<bool>("market_monitored", NO);
	marketBroadcast = (unsigned char)dict.get<bool>("market_broadcast", YES);

	// Non main stations may have requiresDockingClearance set to yes as a result of the code below,
	// but this variable should be irrelevant for them, as they do not make use of it anyway.
	requiresDockingClearance = (unsigned char)dict.get<bool>("requires_docking_clearance", (UNIVERSE != nullptr ? UNIVERSE->dockingClearanceProtocolActive() : false));
	
	allowsFastDocking = (unsigned char)dict.get<bool>("allows_fast_docking", NO);
	
	allowsAutoDocking = (unsigned char)dict.get<bool>("allows_auto_docking", YES);
	
	allowsSaving = (UNIVERSE != nullptr ? UNIVERSE->deterministicPopulation() : false);

	interstellarUndockingAllowed = (unsigned char)dict.get<bool>("interstellar_undocking", NO);
	
	double unitime = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0);

	if (getHasNPCTraffic())  // removed the 'isRotatingStation' restriction.
	{
		docked_shuttles = ranrot_rand() & 3;   // 0..3;
		shuttle_launch_interval = 15.0 * 60.0;  // every 15 minutes
		last_shuttle_launch_time = unitime - (ranrot_rand() & 63) * shuttle_launch_interval / 60.0;
			
		docked_traders = 3 + (ranrot_rand() & 7);   // 1..3;
		trader_launch_interval = 3600.0 / docked_traders;  // every few minutes
		last_trader_launch_time = unitime + 60.0 - trader_launch_interval; // in one minute's time
	}
	else
	{
		docked_shuttles = 0;
		docked_traders = 0;   // 1..3;
	}
	
	patrol_launch_interval = 300.0;	// 5 minutes
	last_patrol_report_time = unitime - patrol_launch_interval;
	
	if (!getCrew().has_value())
	{
		setSingleCrewWithRole("police");
	}
	
	if (group() == nil)
	{
		setGroup(stationGroup());
	}
	return YES;
	
	OOJS_PROFILE_EXIT
}


// used to set up a virtual dock if necessary
bool StationEntity::setUpSubEntities()
{
	ShipEntity *self = this;
	if (!ShipEntity::setUpSubEntities())
	{
		return NO;
	}


#ifndef NDEBUG
	for (const auto &subRef : getSubEntities())
	{
		Entity *sub = subRef.get();
		if (!oo::EntityIsShip(sub))  continue;
		::ShipEntity *subEntity = oo::ToShip(sub);
		if ((subEntity != nullptr ? subEntity->getIsStation() : false))
		{
			OO_LOG("setup.ship.badType.subentities", "Subentity {} ({}) of station {} is itself a StationEntity. This is an internal error - please report it. ", oo::EntityDescription(subEntity), (subEntity != nullptr ? subEntity->shipDataKey() : std::optional<std::string>()).value_or("(null)"), getDisplayName().value_or("(null)"));
		}
	}
#endif

	// and now check for docks
	if (!dockSubEntities().empty())
	{
		return YES;
	}

	cxx_OOStandardsDeprecated(oo::str::format("No docks set up for %s", oo::EntityDescription(self).c_str()));
	OO_LOG("ship.setup.docks", "No docks set up for {}, making virtual dock", oo::EntityDescription(self));

	// no real docks, make a virtual one
	// position and orientation as OOPropertyListFromVector / OOPropertyListFromQuaternion built them (floats)
	Vector dockPosition = make_vector(0,0,port_radius);
	oo::PList::Dict virtualDockDict;
	virtualDockDict["type"] = oo::PList("standard");
	virtualDockDict["subentity_key"] = oo::PList("oolite-dock-virtual");
	virtualDockDict["position"] = oo::PList(oo::PList::Dict{ { "x", oo::PList::singleReal(dockPosition.x) }, { "y", oo::PList::singleReal(dockPosition.y) }, { "z", oo::PList::singleReal(dockPosition.z) } });
	virtualDockDict["orientation"] = oo::PList(oo::PList::Dict{ { "w", oo::PList::singleReal(kIdentityQuaternion.w) }, { "x", oo::PList::singleReal(kIdentityQuaternion.x) }, { "y", oo::PList::singleReal(kIdentityQuaternion.y) }, { "z", oo::PList::singleReal(kIdentityQuaternion.z) } });
	virtualDockDict["is_dock"] = oo::PList(true);
	virtualDockDict["dock_label"] = oo::PList("the docking bay");
	virtualDockDict["allow_docking"] = oo::PList(true);
	virtualDockDict["disallowed_docking_collides"] = oo::PList(false);
	virtualDockDict["allow_launching"] = oo::PList(true);
	virtualDockDict["_is_virtual_dock"] = oo::PList(true);

	if (!setUpOneStandardSubentity(oo::PList(std::move(virtualDockDict)), NO))
	{
		return NO;
	}
	return YES;
}


bool StationEntity::getInterstellarUndockingAllowed()
{
	return interstellarUndockingAllowed;
}


bool StationEntity::getHasNPCTraffic()
{
	return hasNPCTraffic;
}


void StationEntity::setHasNPCTraffic(bool flag)
{
	hasNPCTraffic = flag != NO;
}


bool StationEntity::getRequiresDockingClearance()
{
	return requiresDockingClearance;
}


void StationEntity::setRequiresDockingClearance(bool newValue)
{
	requiresDockingClearance = !!newValue;	// Ensure yes or no
}


bool StationEntity::getAllowsFastDocking()
{
	return allowsFastDocking;
}


void StationEntity::setAllowsFastDocking(bool newValue)
{
	allowsFastDocking = !!newValue;	// Ensure yes or no
}


bool StationEntity::getAllowsAutoDocking()
{
	return allowsAutoDocking;
}


void StationEntity::setAllowsAutoDocking(bool newValue)
{
	allowsAutoDocking = !!newValue; // Ensure yes or no
}


bool StationEntity::getAllowsSaving()
{
	// fixed stations only, not carriers!
	return allowsSaving && (getMaxFlightSpeed() == 0);
}


bool StationEntity::isRotatingStation()
{
	if (shipinfoDictionary.get<bool>("rotating", false))  return YES;
	// legacy. -rangeOfString: of the roles string; absent, a message to nil gave a zeroed range, which is not NSNotFound.
	const oo::PList *roles = shipinfoDictionary.find("roles");
	if (roles == nullptr)  return YES;
	const std::string *rolesString = roles->getIf<std::string>();
	return rolesString != nullptr && rolesString->find("rotating-station") != std::string::npos;
}


std::optional<std::string> StationEntity::marketOverrideName()
{
	// 2010.06.14 - Micha - we can't default to the primary role as otherwise the logic
	//				generating the market in [Universe commodityDataForEconomy:] doesn't
	//				work properly with the various overrides.  The primary role will get
	//				used if either there is no market override, or the market wasn't
	//				defined.
	return OptionalStringValue(shipinfoDictionary.find("market"));
}


bool StationEntity::hasShipyard()
{
	if ((UNIVERSE != nullptr ? UNIVERSE->station() : nullptr) == this)
		return YES;
	const oo::PList	*determinantValue = shipinfoDictionary.find("has_shipyard");

	if (determinantValue == nullptr)
		determinantValue = shipinfoDictionary.find("hasShipyard");
	
	// NOTE: non-standard capitalization is documented and entrenched.
	if (determinantValue != nullptr && !determinantValue->isNull())
	{
		if (determinantValue->isArray())
		{
			return (PLAYER != nullptr ? PLAYER->scriptTestConditions(OOSanitizeLegacyScriptConditions(*determinantValue, std::nullopt)) : false);
		}
		else
		{
			return OOFuzzyBooleanFromPList(determinantValue, 0.0f);
		}
	}
	else
	{
		return NO;
	}
}


void StationEntity::generateShipyard()
{
	generateShipyard(getEquivalentTechLevel());
}


void StationEntity::generateShipyard(OOTechLevelID stationTechLevel)
{
	unsigned		i;

	if (getLocalShipyard() == nullptr)
	{
		const oo::PList forSale = (UNIVERSE != nullptr ? UNIVERSE->shipsForSaleForSystem((UNIVERSE != nullptr ? UNIVERSE->currentSystemID() : 0), stationTechLevel, (PLAYER != nullptr ? PLAYER->clockTime() : 0.0)) : oo::PList());
		const oo::PList::Array *entries = forSale.getIf<oo::PList::Array>();
		setLocalShipyard(entries != nullptr ? *entries : oo::PList::Array());	// nil gave an empty shipyard
	}

	std::vector<oo::PList> *shipyard = getLocalShipyard();
	const oo::PList::Dict *shipyardRecord = (PLAYER != nullptr ? PLAYER->shipyardRecord() : (oo::PList::Dict *)nullptr);
		
	// remove ships that the player has already bought
	for (i = 0; i < shipyard->size(); i++)
	{
		const std::optional<std::string> shipID = OptionalStringValue((*shipyard)[i].find("id"));	// SHIPYARD_KEY_ID
		if (shipID && shipyardRecord != nullptr && shipyardRecord->contains(*shipID))
		{
			shipyard->erase(shipyard->begin() + i--);
		}
	}
}


bool StationEntity::suppressArrivalReports()
{
	return suppress_arrival_reports;
}


void StationEntity::setSuppressArrivalReports(bool newValue)
{
	suppress_arrival_reports = !!newValue;	// ensure YES or NO
}


bool StationEntity::getHasBreakPattern()
{
	return hasBreakPattern;
}


void StationEntity::setHasBreakPattern(bool newValue)
{
	hasBreakPattern = !!newValue;
}


std::optional<std::string> StationEntity::descriptionComponents() const
{
	return oo::str::format("\"%s\" %s", name.value_or("(null)").c_str(), ShipEntity::descriptionComponents().value_or("(null)").c_str());
}


void StationEntity::dumpSelfState()
{
	std::vector<std::string>	flags;
	std::string					flagsString;
	std::string					alertString = "*** ERROR: UNKNOWN ALERT LEVEL ***";
	
	ShipEntity::dumpSelfState();
	
	switch (alertLevel)
	{
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
	
	#define ADD_FLAG_IF_SET(x)		if (x) { flags.push_back(#x); }
	ADD_FLAG_IF_SET(no_docking_while_launching);
	if (isRotatingStation()) { flags.push_back("rotatingStation"); }
	if (!dockingCorridorIsEmpty()) { flags.push_back("dockingCorridorIsBusy"); }
	for (const std::string &flag : flags)
	{
		if (!flagsString.empty())  flagsString += ", ";	// -componentsJoinedByString:
		flagsString += flag;
	}
	if (flags.empty())  flagsString = "none";
	OO_LOG("dumpState.stationEntity", "Flags: {}", flagsString);
	
	// approach and hold lists.
	
	// Ships on hold list, only used with moving stations (= carriers)
	if(_shipsOnHold.count() > 0)
	{
		OO_LOG("dumpState.stationEntity", "{} Ships on hold (unsorted):", _shipsOnHold.count());
		
		oo::log::indent();
		unsigned		i = 1;
		for (const oo::Ref<Entity> &shipRef : _shipsOnHold.allObjects())
		{
			::ShipEntity *ship = oo::ToShip(shipRef.get());
			OO_LOG("dumpState.stationEntity", "Nr {}: {} at distance {:g} with role: {}", i++, (ship != nullptr ? ship->getDisplayName() : std::optional<std::string>()).value_or("(null)"), HPdistance(getPosition(), (ship != nullptr ? ship->getPosition() : HPVector{})), (ship != nullptr ? ship->getPrimaryRole() : std::optional<std::string>()).value_or("(null)"));
		}
		oo::log::outdent();
	}
}



// Slice 2 of docs/phases/3-slices/StationEntity.md (bead oo-9j462): docking traffic control and the
// launch queue.


void StationEntity::sanityCheckShipsOnApproach()
{

	unsigned soa = 0;
	for (const oo::EntityHold &dock : dockSubEntities())
	{
		::DockEntity *sub = oo::ToDock(dock.get());
		soa += (sub != nullptr ? sub->pruneAndCountShipsOnApproach() : 0);
	}

	if (soa == 0)
	{
		// if all docks have no ships on approach
		if (shipAI != nullptr)  shipAI->message("DOCKING_COMPLETE");
		doScriptEvent(OOJSID("stationDockingQueuesAreEmpty"));	
	}
}


// only used by player - everything else ends up in a Dock's launch queue
void StationEntity::launchShip(::ShipEntity *ship)
{
	
	// try to find an unused dock first
	for (const oo::EntityHold &dock : dockSubEntities())
	{
		::DockEntity *sub = oo::ToDock(dock.get());
		if ((sub != nullptr ? sub->allowsLaunching() : false) && (sub != nullptr ? sub->countOfShipsInLaunchQueue() : 0) == 0) 
		{
			if (sub != nullptr)  sub->launchShip(ship);
			return;
		}
	}
	// otherwise any launchable dock will do
	for (const oo::EntityHold &dock : dockSubEntities())
	{
		::DockEntity *sub = oo::ToDock(dock.get());
		if ((sub != nullptr ? sub->allowsLaunching() : false)) 
		{
			if (sub != nullptr)  sub->launchShip(ship);
			return;
		}
	}

	// ship has no launch docks specified; just use the last one
	// (the enumerator loop this replaced left its variable nil when it ran out, so this never fires)
	::DockEntity *sub = nil;
	if (sub != nil)
	{
		if (sub != nullptr)  sub->launchShip(ship);
		return;
	}
	// guaranteed to always be a dock as virtual dock will suffice
}


// Exposed to AI
void StationEntity::abortAllDockings()
{
	for (const oo::EntityHold &dock : dockSubEntities())
	{
		::DockEntity *sub = oo::ToDock(dock.get());
		if (sub != nullptr)  sub->abortAllDockings();
	}
	
	// -makeObjectsPerformSelector:withObject: of the live ships on hold, in order
	for (const oo::Ref<Entity> &holdRef : _shipsOnHold.allObjects())  { if (oo::ToShip(holdRef.get()) != nullptr)  oo::ToShip(holdRef.get())->sendAIMessage("DOCKING_ABORTED"); }
	for (const oo::Ref<Entity> &holdRef : _shipsOnHold.allObjects())
	{
		::ShipEntity *hold = oo::ToShip(holdRef.get());
		if (hold != nullptr)  hold->doScriptEvent(OOJSID("stationWithdrewDockingClearance"));
	}

	::PlayerEntity *player = PLAYER;

	if ((player != nullptr ? player->getTargetDockStation() : (::StationEntity *)nullptr) == this && (player != nullptr ? player->getDockingClearanceStatus() : OODockingClearanceStatus{}) >= DOCKING_CLEARANCE_STATUS_REQUESTED)
	{
		// then docking clearance is requested but hasn't been cancelled
		// yet by a DockEntity
		sendExpandedMessage("[station-docking-clearance-abort-cancelled]", player);
		if (player != nullptr)  player->setDockingClearanceStatus(DOCKING_CLEARANCE_STATUS_NONE);
		if (player != nullptr)  player->doScriptEvent(OOJSID("stationWithdrewDockingClearance"));
	}

	_shipsOnHold.removeAll();
	
	if (shipAI != nullptr)  shipAI->message("DOCKING_COMPLETE");
	doScriptEvent(OOJSID("stationDockingQueuesAreEmpty"));

}


void StationEntity::autoDockShipsOnHold()
{
	for (const oo::Ref<Entity> &shipRef : _shipsOnHold.allObjects())
	{
		::ShipEntity *ship = oo::ToShip(shipRef.get());
		pullInShipIfPermitted(ship);
	}
	
	_shipsOnHold.removeAll();
}


void StationEntity::autoDockShipsOnApproach()
{
	for (const oo::EntityHold &dock : dockSubEntities())
	{
		::DockEntity *sub = oo::ToDock(dock.get());
		if (sub != nullptr)  sub->autoDockShipsOnApproach();
	}

	autoDockShipsOnHold();
	
	if (shipAI != nullptr)  shipAI->message("DOCKING_COMPLETE");
	doScriptEvent(OOJSID("stationDockingQueuesAreEmpty"));

}


Vector StationEntity::portUpVectorForShip(::ShipEntity *ship)
{
	for (const oo::EntityHold &dock : dockSubEntities())
	{
		::DockEntity *sub = oo::ToDock(dock.get());
		if ((sub != nullptr ? sub->shipIsInDockingQueue(ship) : false))
		{
			return (sub != nullptr ? sub->portUpVectorForShipsBoundingBox((ship != nullptr ? ship->getTotalBoundingBox() : BoundingBox{})) : Vector{});
		}
	}
	return kZeroVector;
}


// this method does initial traffic control, before passing the ship
// to an appropriate dock for docking coordinates and instructions.
// used for NPCs, and the player when they use the docking computer
oo::PList StationEntity::dockingInstructionsForShip(::ShipEntity *ship)
{
	if (ship == nil)  return oo::PList();

	doScriptEvent(OOJSID("stationReceivedDockingRequest"), ship);

	if ((ship != nullptr ? ship->getIsPlayer() : false))
	{
		player_reserved_dock = nil; // clear any dock reservation for manual docking
	}

	if ((ship != nullptr ? ship->getIsPlayer() : false) && (ship != nullptr ? ship->legalStatus() : int{}) > 50)	// note: non-player fugitives dock as normal
	{
		// refuse docking to the fugitive player
		return cxx_OOMakeDockingInstructions(this, (ship != nullptr ? ship->getPosition() : HPVector{}), 0, 100, "DOCKING_REFUSED", "[station-docking-refused-to-fugitive]", NO, -1);
	}
	
	if	(magnitude2(velocity) > 1.0 ||
			 fabs(flightPitch) > 0.01 ||
			 fabs(flightYaw) > 0.01)
	{
		// no docking while station is moving, pitching or yawing
		return holdPositionInstructionForShip(ship);
	}
	::PlayerEntity *player = PLAYER;
	BOOL player_is_ahead = (!(ship != nullptr ? ship->getIsPlayer() : false) && (player != nullptr ? player->getDockingClearanceStatus() : OODockingClearanceStatus{}) == DOCKING_CLEARANCE_STATUS_REQUESTED && (this == (player != nullptr ? player->getTargetDockStation() : (::StationEntity *)nullptr)));

	::DockEntity		*chosenDock = nil;
	std::optional<std::string>	docking;	// nullopt: no dock asked yet (was nil)
	NSUInteger		queue = 100;
	
	BOOL alldockstoosmall = YES;
	for (const oo::EntityHold &dock : dockSubEntities())
	{
		::DockEntity *sub = oo::ToDock(dock.get());
		if ((sub != nullptr ? sub->shipIsInDockingQueue(ship) : false)) 
		{
			// if already claimed a docking queue, use that one
			chosenDock = sub;
			alldockstoosmall = NO;
			break;
		}
		if (player_is_ahead) {
			// can't allocate a new queue while player is manually docking
			continue;
		}
		if (sub != player_reserved_dock || (ship != nullptr ? ship->getIsPlayer() : false))
		{
			docking = (sub != nullptr ? sub->canAcceptShipForDocking(ship) : std::optional<std::string>());
			if (docking == "DOCK_CLOSED")
			{
				ooscript::Context context = OOJSAcquireContext();
				ooscript::Value		rval = ooscript::undefinedValue();
				ooscript::Value		args[] = { OOJSValueFromCxxObject(context, sub),
													 OOJSValueFromCxxObject(context, ship) };
				bool tempreject = NO;

				BOOL OK = (getScript() != nullptr ? getScript()->callMethod(OOJSID("willOpenDockingPortFor"), context, args, 2, &rval) : false);
				if (OK)  OK = ooscript::valueToBoolean(context, rval, &tempreject);
				if (!OK)  tempreject = NO; // default to permreject
				if (tempreject)
				{
					docking = "TRY_AGAIN_LATER";
				}
				else
				{
					docking = "TOO_BIG_TO_DOCK";
				}

				OOJSRelinquishContext(context);
			}

			if (docking == "DOCKING_POSSIBLE" && (sub != nullptr ? sub->countOfShipsInDockingQueue() : 0) < queue) {
				// try to select the dock with the fewest ships already enqueued
				chosenDock = sub;
				queue = (sub != nullptr ? sub->countOfShipsInDockingQueue() : 0);
				alldockstoosmall = NO;
			}
			else if (!(docking == "TOO_BIG_TO_DOCK"))
			{
				alldockstoosmall = NO;
			}
		}
		else
		{
			alldockstoosmall = NO;
		}
	}	
	if (chosenDock == nil)
	{
		if (player_is_ahead || (docking == "TOO_BIG_TO_DOCK" && !alldockstoosmall) || !docking)
		{
			// either player is manually docking and we can't allocate new docks,
			// or the last dock was too small, and there may be an acceptable one
			// not tested yet or returning TRY_AGAIN_LATER
			docking = "TRY_AGAIN_LATER";
		}
		// no docks accept this ship (or the player is blocking them)
		return cxx_OOMakeDockingInstructions(this, (ship != nullptr ? ship->getPosition() : HPVector{}), 200, 100, docking, std::nullopt, NO, -1);
	}


	// rolling is okay for some
	if	(fabs(flightRoll) > 0.01 && (chosenDock != nullptr ? chosenDock->isOffCentre() : false))
	{
		return holdPositionInstructionForShip(ship);
	}
	
	// we made it through holding!
	_shipsOnHold.remove(ship);
	
	if (shipAI != nullptr)  shipAI->reactToMessage("DOCKING_REQUESTED", "requestDockingCoordinates");	// react to the request	
	doScriptEvent(OOJSID("stationAcceptedDockingRequest"), ship);

	return (chosenDock != nullptr ? chosenDock->dockingInstructionsForShip(ship) : oo::PList());
}


oo::PList StationEntity::holdPositionInstructionForShip(::ShipEntity *ship)
{
	if (!_shipsOnHold.contains(ship))
	{
		sendExpandedMessage("[station-acknowledges-hold-position]", ship);
		_shipsOnHold.add(ship);
	}
	
	return cxx_OOMakeDockingInstructions(this, (ship != nullptr ? ship->getPosition() : HPVector{}), 0, 100, "HOLD_POSITION", std::nullopt, NO, -1);
}


void StationEntity::abortDockingForShip(::ShipEntity *ship)
{
	if (ship != nullptr)  ship->sendAIMessage("DOCKING_ABORTED");
	if (ship != nullptr)  ship->doScriptEvent(OOJSID("stationWithdrewDockingClearance"));
	
	_shipsOnHold.remove(ship);
	
	for (const oo::EntityHold &dock : dockSubEntities())
	{
		::DockEntity *sub = oo::ToDock(dock.get());
		if (sub != nullptr)  sub->abortDockingForShip(ship);
	}
	
	if ((ship != nullptr ? ship->getIsPlayer() : false))
	{
		player_reserved_dock = nil;
	}

	sanityCheckShipsOnApproach();
}


//////////////////////////////////////////////// from superclass


bool StationEntity::shipIsInDockingCorridor(::ShipEntity *ship)
{
	if (!(ship != nullptr ? ship->getIsShip() : false))  return NO;
	if ((ship != nullptr ? ship->getIsPlayer() : false) && (ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_DEAD)  return NO;

	for (const oo::EntityHold &dock : dockSubEntities())
	{
		::DockEntity *sub = oo::ToDock(dock.get());
		if ((sub != nullptr ? sub->shipIsInDockingCorridor(ship) : false))
		{
			return YES;
		}
	}
	return NO;
}


void StationEntity::pullInShipIfPermitted(::ShipEntity *ship)
{
	if (ship != nullptr)  ship->enterDock(this); // dock performs permitted checks
}


bool StationEntity::dockingCorridorIsEmpty()
{
	if (!UNIVERSE)
		return NO;

	for (const oo::EntityHold &dock : dockSubEntities())
	{
		::DockEntity *sub = oo::ToDock(dock.get());
		if ((sub != nullptr ? sub->dockingCorridorIsEmpty() : false))
		{
			return YES; // if any are
		}
	}
	return NO;
}


void StationEntity::clearDockingCorridor()
{
	if (!UNIVERSE)
		return;

	for (const oo::EntityHold &dock : dockSubEntities())
	{
		::DockEntity *sub = oo::ToDock(dock.get());
		if (sub != nullptr)  sub->clearDockingCorridor();
	}		

	return;
}


void StationEntity::update(OOTimeDelta delta_t)
{
	BOOL isRockHermit = (scanClass == CLASS_ROCK);
	BOOL isMainStation = (this == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr));
	
	double unitime = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0);
	
	if (!isMainStation && localMarket == nil)
	{
		initialiseLocalMarket();
	}

	ShipEntity::update(delta_t);	// [super update:delta_t]

	::PlayerEntity *player = PLAYER;

	BOOL isDockingStation = (this == (player != nullptr ? player->getTargetDockStation() : (::StationEntity *)nullptr));
	if (isDockingStation && (player != nullptr ? player->status() : OOEntityStatus{}) == STATUS_IN_FLIGHT)
	{
		if ((player != nullptr ? player->getDockingClearanceStatus() : OODockingClearanceStatus{}) >= DOCKING_CLEARANCE_STATUS_GRANTED)
		{
			if (last_launch_time-30 < unitime && (player != nullptr ? player->getDockingClearanceStatus() : OODockingClearanceStatus{}) != DOCKING_CLEARANCE_STATUS_TIMING_OUT)
			{
				sendExpandedMessage("[station-docking-clearance-about-to-expire]", player);
				if (player != nullptr)  player->setDockingClearanceStatus(DOCKING_CLEARANCE_STATUS_TIMING_OUT);
			}
			else if (last_launch_time < unitime)
			{
				sendExpandedMessage("[station-docking-clearance-expired]", player);
				if (player != nullptr)  player->setDockingClearanceStatus(DOCKING_CLEARANCE_STATUS_NONE);	// Docking clearance for player has expired.
				if (player != nullptr)  player->doScriptEvent(OOJSID("playerDockingClearanceExpired"));
				if (currentlyInDockingQueues() == 0) 
				{
					if (getAI() != nullptr)  getAI()->message("DOCKING_COMPLETE");
					doScriptEvent(OOJSID("stationDockingQueuesAreEmpty"));
				}
				player_reserved_dock = nil;
			}
		}

		else if ((player != nullptr ? player->getDockingClearanceStatus() : OODockingClearanceStatus{}) == DOCKING_CLEARANCE_STATUS_NOT_REQUIRED)
		{
			if (last_launch_time < unitime)
			{
				if (player != nullptr)  player->setDockingClearanceStatus(DOCKING_CLEARANCE_STATUS_NONE);
				if (currentlyInDockingQueues() == 0) 
				{
					if (getAI() != nullptr)  getAI()->message("DOCKING_COMPLETE");
					doScriptEvent(OOJSID("stationDockingQueuesAreEmpty"));
				}
			}
		}

		else if ((player != nullptr ? player->getDockingClearanceStatus() : OODockingClearanceStatus{}) == DOCKING_CLEARANCE_STATUS_REQUESTED &&
				hasClearDock())
		{
			::DockEntity *dock = selectDockForDocking();
			last_launch_time = unitime + DOCKING_CLEARANCE_WINDOW;
			if (hasMultipleDocks()) 
			{
				const std::string grantedFormat = OO_DESC("station-docking-clearance-granted-in-@-until-@");	// the format first, as Clang evaluates the arguments: a description that is an array draws (ADR-0063 item 5)
				sendExpandedMessage(oo::str::formatRuntime(grantedFormat, { (dock != nullptr ? dock->getDisplayName() : std::optional<std::string>()).value_or("(null)"), cxx_ClockToString((player != nullptr ? player->clockTime() : 0.0) + DOCKING_CLEARANCE_WINDOW, NO) }), player);
			}
			else
			{
				const std::string grantedFormat = OO_DESC("station-docking-clearance-granted-until-@");	// the format first, as Clang evaluates the arguments: a description that is an array draws (ADR-0063 item 5)
				sendExpandedMessage(oo::str::formatRuntime(grantedFormat, { cxx_ClockToString((player != nullptr ? player->clockTime() : 0.0) + DOCKING_CLEARANCE_WINDOW, NO) }), player);
			}
			player_reserved_dock = dock;
			if (player != nullptr)  player->setDockingClearanceStatus(DOCKING_CLEARANCE_STATUS_GRANTED);
			if (player != nullptr)  player->doScriptEvent(OOJSID("playerDockingClearanceGranted"));

		}
	}
	
	
	if (approach_spacing > 0.0)
	{
		approach_spacing -= delta_t * 10.0;	// reduce by 10 m/s
		if (approach_spacing < 0.0)   approach_spacing = 0.0;
	}

	/* JSAI: JS-based AIs handle their own traffic either alone or 
	 * in conjunction with the system repopulator */
	if (!hasNewAI())
	{
		// begin launch of shuttles, traders, patrols
		if ((docked_shuttles > 0)&&(!isRockHermit))
		{
			if (unitime > last_shuttle_launch_time + shuttle_launch_interval)
			{
				if ((getHasNPCTraffic())&&(aegis_status != AEGIS_NONE))
				{
					launchShuttle();
				}
				last_shuttle_launch_time = unitime;
			}
		}

		if ((docked_traders > 0)&&(!isRockHermit))
		{
			if (unitime > last_trader_launch_time + trader_launch_interval)
			{
				if (getHasNPCTraffic())
				{
					launchIndependentShip("trader");
					docked_traders--;
				}
				last_trader_launch_time = unitime;
			}
		}
	
		// testing patrols
		if (unitime > (last_patrol_report_time + patrol_launch_interval))
		{
			if (!((isMainStation && getHasNPCTraffic()) || hasPatrolShips) || launchPatrol() != nil)
				last_patrol_report_time = unitime;
		}

	}
}


void StationEntity::clear()
{
	for (const oo::EntityHold &dock : dockSubEntities())
	{
		::DockEntity *sub = oo::ToDock(dock.get());
		if (sub != nullptr)  sub->clear();
	}
	
	_shipsOnHold.removeAll();
}


bool StationEntity::hasMultipleDocks()
{
	return dockSubEntities().size() > 1;
}


// is there a dock free for the player to dock manually?
// not used for NPCs
bool StationEntity::hasClearDock()
{
	for (const oo::EntityHold &dock : dockSubEntities())
	{
		::DockEntity *sub = oo::ToDock(dock.get());
		if ((sub != nullptr ? sub->allowsDocking() : false) && (sub != nullptr ? sub->countOfShipsInLaunchQueue() : 0) == 0 && (sub != nullptr ? sub->countOfShipsInDockingQueue() : 0) == 0)
		{
			if ((sub != nullptr ? sub->canAcceptShipForDocking(PLAYER) : std::optional<std::string>()) == "DOCKING_POSSIBLE")
			{
				return YES;
			}
		}
	}
	return NO;
}


bool StationEntity::hasEligibleDock()
{
	for (const oo::EntityHold &dock : dockSubEntities())
	{
		::DockEntity *sub = oo::ToDock(dock.get());
		// TRY_AGAIN_LATER in this context means "ships launching now"
		if ((sub != nullptr ? sub->allowsDocking() : false) && ((sub != nullptr ? sub->canAcceptShipForDocking(PLAYER) : std::optional<std::string>()) == "DOCKING_POSSIBLE" || (sub != nullptr ? sub->canAcceptShipForDocking(PLAYER) : std::optional<std::string>()) == "TRY_AGAIN_LATER"))
		{
			return YES;
		}
	}
	return NO;
}


// is there any dock which may launch ships?
bool StationEntity::hasLaunchDock()
{
	for (const oo::EntityHold &dock : dockSubEntities())
	{
		::DockEntity *sub = oo::ToDock(dock.get());
		if ((sub != nullptr ? sub->allowsLaunching() : false))
		{
			return YES;
		}
	}
	return NO;
}


// only used to pick a dock for the player
::DockEntity * StationEntity::selectDockForDocking()
{
	for (const oo::EntityHold &dock : dockSubEntities())
	{
		::DockEntity *sub = oo::ToDock(dock.get());
		if ((sub != nullptr ? sub->allowsDocking() : false) && (sub != nullptr ? sub->countOfShipsInLaunchQueue() : 0) == 0 && (sub != nullptr ? sub->countOfShipsInDockingQueue() : 0) == 0)
		{
			return sub;
		}
	}
	return nil;
}


void StationEntity::addShipToLaunchQueue(::ShipEntity *ship, bool priority)
{
	unsigned			threshold = 0;

	// quickest launch if we assign ships to those bays with no incoming ships
	// and spread the ships evenly around those bays
	// much easier if the station has at least one launch-only dock
	while (threshold < 16)
	{
		for (const oo::EntityHold &dock : dockSubEntities())
		{
			::DockEntity *sub = oo::ToDock(dock.get());
			if (sub != player_reserved_dock)
			{
				if ((sub != nullptr ? sub->countOfShipsInDockingQueue() : 0) == 0)
				{
					if ((sub != nullptr ? sub->allowsLaunching() : false) && (sub != nullptr ? sub->countOfShipsInLaunchQueue() : 0) <= threshold)
					{
						if ((sub != nullptr ? sub->allowsLaunchingOf(ship) : false))
						{
							if (sub != nullptr)  sub->addShipToLaunchQueue(ship, priority);
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
	while (threshold < 16)
	{
		for (const oo::EntityHold &dock : dockSubEntities())
		{
			::DockEntity *sub = oo::ToDock(dock.get());
			/* so this time as long as it allows launching only check
			 * the docking queue size so long as enumerator order is
			 * deterministic, this will assign every launch this
			 * update to the same dock (edge case where new docking
			 * ship appears in the middle, probably not a problem) */
			if ((sub != nullptr ? sub->allowsLaunching() : false) && (sub != nullptr ? sub->countOfShipsInDockingQueue() : 0) <= threshold)
			{
				if ((sub != nullptr ? sub->allowsLaunchingOf(ship) : false))
				{
					if (sub != nullptr)  sub->addShipToLaunchQueue(ship, priority);
					return;
				}
			}

		}
		threshold++;
	}
	
	OO_LOG("station.launchShip.failed", "Cancelled launch for a {} with role {}, as the {} has too many ships in its launch queue(s) or no suitable launch docks.",
			  (ship != nullptr ? ship->getDisplayName() : std::optional<std::string>()).value_or("(null)"), (ship != nullptr ? ship->getPrimaryRole() : std::optional<std::string>()).value_or("(null)"), getDisplayName().value_or("(null)"));
}


unsigned StationEntity::countOfShipsInLaunchQueueWithPrimaryRole(const std::string &role)
{
	unsigned result = 0;
	for (const oo::EntityHold &dock : dockSubEntities())
	{
		::DockEntity *sub = oo::ToDock(dock.get());
		result += (sub != nullptr ? sub->countOfShipsInLaunchQueueWithPrimaryRole(role) : 0);
	}
	return result;
}


bool StationEntity::fitsInDock(::ShipEntity *ship)
{
   return fitsInDock(ship, YES);
}


bool StationEntity::fitsInDock(::ShipEntity *ship, bool logNoFit)
{
	ShipEntity *self = this;
	if (!(ship != nullptr ? ship->getIsShip() : false))  return NO;
	
	for (const oo::EntityHold &dock : dockSubEntities())
	{
		::DockEntity *sub = oo::ToDock(dock.get());
		if ((sub != nullptr ? sub->allowsLaunchingOf(ship) : false))
		{
			return YES;
		}
	}

	if (logNoFit) OO_LOG("station.launchShip.failed", "Cancelled launch for a {} with role {}, as it is too large for the docking port of the {}.",
			  (ship != nullptr ? ship->getDisplayName() : std::optional<std::string>()).value_or("(null)"), (ship != nullptr ? ship->getPrimaryRole() : std::optional<std::string>()).value_or("(null)"), oo::EntityDescription(self));
	return NO;
}


void StationEntity::noteDockedShip(::ShipEntity *ship)
{
	if (ship == nil)  return;	
	
	::PlayerEntity *player = PLAYER;
	// set last launch time to avoid clashes with outgoing ships
	if ((player != nullptr ? player->getDockingClearanceStatus() : OODockingClearanceStatus{}) != DOCKING_CLEARANCE_STATUS_GRANTED)
	{
		// avoid interfering with docking clearance on another bay
		last_launch_time = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0);
	}
	addShipToStationCount(ship);
	
	for (const oo::EntityHold &dock : dockSubEntities())
	{
		::DockEntity *sub = oo::ToDock(dock.get());
		if (sub != nullptr)  sub->noteDockingForShip(ship);
	}
	sanityCheckShipsOnApproach();
	
	doScriptEvent(OOJSID("otherShipDocked"), ship);
	
	BOOL isDockingStation = (this == (player != nullptr ? player->getTargetDockStation() : (::StationEntity *)nullptr));
	if (isDockingStation && (player != nullptr ? player->status() : OOEntityStatus{}) == STATUS_IN_FLIGHT &&
			(player != nullptr ? player->getDockingClearanceStatus() : OODockingClearanceStatus{}) == DOCKING_CLEARANCE_STATUS_REQUESTED)
	{
		if (!hasClearDock())
		{
			// then say why
			if (currentlyInDockingQueues())
			{
				sendExpandedMessage(oo::str::formatRuntime(OO_DESC("station-docking-clearance-holding-d-ships-approaching"), { currentlyInDockingQueues()+1 }), player);
			}
			else if(currentlyInLaunchingQueues())
			{
				sendExpandedMessage(oo::str::formatRuntime(OO_DESC("station-docking-clearance-holding-d-ships-departing"), { currentlyInLaunchingQueues()+1 }), player);
			}
		} 
	}


	if ((ship != nullptr ? ship->getIsPlayer() : false))
	{
		player_reserved_dock = nil;
	}
}


void StationEntity::addShipToStationCount(::ShipEntity *ship)
{
 	if ((ship != nullptr ? ship->isShuttle() : false))  docked_shuttles++;
	else if ((ship != nullptr ? ship->isTrader() : false) && !(ship != nullptr ? ship->getIsPlayer() : false))  docked_traders++;
	else if (((ship != nullptr ? ship->isPolice() : false) && !(ship != nullptr ? ship->isEscort() : false)) || (ship != nullptr ? ship->hasPrimaryRole("defense_ship") : false))
	{
		if (0 < defenders_launched)  defenders_launched--;
	}
	else if ((ship != nullptr ? ship->hasPrimaryRole("scavenger") : false) || (ship != nullptr ? ship->hasPrimaryRole("miner") : false))	// treat miners and scavengers alike!
	{
		if (0 < scavengers_launched)  scavengers_launched--;
	}
}




// Slice 3 of docs/phases/3-slices/StationEntity.md (bead oo-hjzwk): docking clearance, damage,
// allegiance and alert level.


bool StationEntity::collideWithShip(::ShipEntity *other)
{
	/*
		There used to be a [self abortAllDockings] here. Removed as there
		doesn't appear to be a good reason for it and it interferes with
		docking clearance.
		-- Micha 2010-06-10
	       Reformatted, Ahruman 2012-08-26
	*/
	return ShipEntity::collideWithShip(other);	// [super collideWithShip:other]
}


bool StationEntity::hasHostileTarget()
{
	return ShipEntity::hasHostileTarget() || (primaryTarget() != nil && ((alertLevel == STATION_ALERT_LEVEL_YELLOW) || (alertLevel == STATION_ALERT_LEVEL_RED)));
}


void StationEntity::takeEnergyDamage(double amount, Entity *entPart, Entity *otherPart, const std::string &weaponIdentifier)
{
	ShipEntity *self = this;
	Entity *other = otherPart;
	// stations must ignore friendly fire, otherwise the defenders' AI gets stuck.
	BOOL			isFriend = NO;
	::OOShipGroup		*group = this->group();
	
	if (oo::EntityIsShip(other) && group != nil)
	{
		::OOShipGroup *otherGroup = (oo::ToShip(other) != nullptr ? oo::ToShip(other)->group() : (OOShipGroup *)nullptr);
		isFriend = otherGroup == group || (otherGroup != nullptr ? otherGroup->leader() : (::ShipEntity *)nil) == self;
	}
	
	// If this is the system's main station...
	if (this == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr) && !isFriend)
	{
		//...get angry
		BOOL isEnergyMine = OOEntityIsCascadeWeapon(entPart);

		// JSAIs might ignore friendly fire from conventional weapons
		if (hasNewAI() || isEnergyMine)
		{
			unsigned b=isEnergyMine ? 96 : 64;
			if ((oo::ToShip(other) != nullptr ? oo::ToShip(other)->getBounty() : 0) >= b)	//already a hardened criminal?
			{
				b *= 1.5; //bigger bounty!
			}
			if (oo::ToShip(other) != nullptr)  oo::ToShip(other)->markAsOffender(b, kOOLegalStatusReasonAttackedMainStation);
			setPrimaryAggressor(other);
			setFoundTarget(other);
			launchPolice();
		}

		if (isEnergyMine) //don't blow up!
		{
			increaseAlertLevel();
			respondToAttackFrom(entPart, other);
			return;
		}
	}
	// Stop damage if main station & close to death!
	if (!isFriend && (this != (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr) || amount < energy) )
	{
		// Handle damage like a ship.
		ShipEntity::takeEnergyDamage(amount, entPart, otherPart, weaponIdentifier);	// [super takeEnergyDamage:...]
	}
}


void StationEntity::adjustVelocity(Vector xVel)
{
	if (this != (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr))  ShipEntity::adjustVelocity(xVel); //dont get moved
}


void StationEntity::takeScrapeDamage(double amount, Entity *ent)
{
	// Stop damage if main station
	if (this != (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr))  ShipEntity::takeScrapeDamage(amount, ent);
}


void StationEntity::takeHeatDamage(double amount)
{
	// Stop damage if main station
	if (this != (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr))  ShipEntity::takeHeatDamage(amount);
}


std::optional<std::string> StationEntity::getAllegiance()
{
	return allegiance;
}


void StationEntity::setAllegiance(const std::optional<std::string> &newAllegiance)
{
	allegiance = newAllegiance;
}


OOStationAlertLevel StationEntity::getAlertLevel()
{
	return alertLevel;
}


void StationEntity::setAlertLevel(OOStationAlertLevel level, bool signallingScript)
{
	ShipEntity *self = this;
	if (level < STATION_ALERT_LEVEL_GREEN)  level = STATION_ALERT_LEVEL_GREEN;
	if (level > STATION_ALERT_LEVEL_RED)  level = STATION_ALERT_LEVEL_RED;
	
	if (alertLevel != level)
	{
		OOStationAlertLevel oldLevel = alertLevel;
		alertLevel = level;
		if (signallingScript)
		{
			ShipScriptEventNoCx(self, "alertConditionChanged", ooscript::int32Value(level), ooscript::int32Value(oldLevel));
		}
		switch (level)
		{
			case STATION_ALERT_LEVEL_GREEN:
				if (shipAI != nullptr)  shipAI->reactToMessage("GREEN_ALERT", std::nullopt);
				break;
				
			case STATION_ALERT_LEVEL_YELLOW:
				if (shipAI != nullptr)  shipAI->reactToMessage("YELLOW_ALERT", std::nullopt);
				break;
				
			case STATION_ALERT_LEVEL_RED:
				if (shipAI != nullptr)  shipAI->reactToMessage("RED_ALERT", std::nullopt);
				break;
		}
	}
}


//////////////////////////////////////////////// extra AI routines


// Exposed to AI
void StationEntity::increaseAlertLevel()
{
	setAlertLevel((OOStationAlertLevel)(getAlertLevel() + 1), YES);
}


// Exposed to AI
void StationEntity::decreaseAlertLevel()
{
	setAlertLevel((OOStationAlertLevel)(getAlertLevel() - 1), YES);
}


// Exposed to AI
void StationEntity::becomeExplosion()
{
	if (this == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr))  return;
	
	// launch docked ships if possible
	::PlayerEntity* player = PLAYER;
	if ((player)&&((player != nullptr ? player->status() : OOEntityStatus{}) == STATUS_DOCKED || (player != nullptr ? player->status() : OOEntityStatus{}) == STATUS_DOCKING)&&((player != nullptr ? player->dockedStation() : (::StationEntity *)nullptr) == this))
	{
		// undock the player!
		if (player != nullptr)  player->leaveDock(this);
		if (UNIVERSE != nullptr)  UNIVERSE->setViewDirection(VIEW_FORWARD);
		if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setMouseInteractionModeForFlight();
		if (player != nullptr)  player->warnAboutHostiles();	// sound a klaxon
	}
	
	if (scanClass == CLASS_ROCK)	// ie we're a rock hermit or similar
	{
		// set the role so that we break up into rocks!
		setPrimaryRole("asteroid");
		being_mined = YES;
	}
	
	// finally bite the bullet
	ShipEntity::becomeExplosion();	// [super becomeExplosion]
}


// Exposed to AI
void StationEntity::becomeEnergyBlast()
{
	if (this == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr))  return;
	ShipEntity::becomeEnergyBlast();	// [super becomeEnergyBlast]
}


void StationEntity::becomeLargeExplosion(double factor)
{
	if (this == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr))  return;
	ShipEntity::becomeLargeExplosion(factor);	// [super becomeLargeExplosion:factor]
}


void StationEntity::acceptPatrolReportFrom(::ShipEntity * /* patrol_ship */)
{
	last_patrol_report_time = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0);
}


// used by player - "other" should always be a reference to the player
// there are some checks in the function from possibly when this wasn't true?
std::optional<std::string> StationEntity::acceptDockingClearanceRequestFrom(::ShipEntity *other)
{
	std::optional<std::string>	result;	// nullopt: no answer yet (was nil)
	double		timeNow = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0);
	::PlayerEntity	*player = PLAYER;
	
	doScriptEvent(OOJSID("stationReceivedDockingRequest"), other);


	if (UNIVERSE != nullptr)  UNIVERSE->clearPreviousMessage();

	sanityCheckShipsOnApproach();

	// Docking clearance not required - clear it just in case it's been
	// set for another nearby station.
	if (!getRequiresDockingClearance())
	{
		// TODO: We're potentially cancelling docking at another station, so
		//       ensure we clear the timer to allow NPC traffic.  If we
		//       don't, normal traffic will resume once the timer runs out.
		// No clearance is needed, but don't send friendly messages to hostile ships!
		if (!(((other != nullptr ? other->getIsPlayer() : false) && (other != nullptr ? other->hasHostileTarget() : false)) || (this == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr) && (other != nullptr ? other->getBounty() : 0) > 50)))
		{
			sendExpandedMessage("[station-docking-clearance-not-required]", other);
		}
		if ((other != nullptr ? other->getIsPlayer() : false))
		{
			if (player != nullptr)  player->setDockingClearanceStatus(DOCKING_CLEARANCE_STATUS_NOT_REQUIRED);
		}
		if (shipAI != nullptr)  shipAI->reactToMessage("DOCKING_REQUESTED", std::nullopt);	// react to the request	
		doScriptEvent(OOJSID("stationAcceptedDockingRequest"), other);

		last_launch_time = timeNow + DOCKING_CLEARANCE_WINDOW;
		result = "DOCKING_CLEARANCE_NOT_REQUIRED";
	}

	// Docking clearance already granted for this station - check for
	// time-out or cancellation (but only for the Player).
	if( !result && (other != nullptr ? other->getIsPlayer() : false) && this == (player != nullptr ? player->getTargetDockStation() : (::StationEntity *)nullptr))
	{
		switch( (player != nullptr ? player->getDockingClearanceStatus() : OODockingClearanceStatus{}) )
		{
			case DOCKING_CLEARANCE_STATUS_TIMING_OUT:
				if (!no_docking_while_launching)
				{
					last_launch_time = timeNow + DOCKING_CLEARANCE_WINDOW;
					const std::string extendedFormat = OO_DESC("station-docking-clearance-extended-until-@");	// the format first, as Clang evaluates the arguments: a description that is an array draws (ADR-0063 item 5)
					sendExpandedMessage(oo::str::formatRuntime(extendedFormat, { cxx_ClockToString((player != nullptr ? player->clockTime() : 0.0) + DOCKING_CLEARANCE_WINDOW, NO) }), other);
					if (player != nullptr)  player->setDockingClearanceStatus(DOCKING_CLEARANCE_STATUS_GRANTED);
					result = "DOCKING_CLEARANCE_EXTENDED";
					break;
				}
				// else, continue with canceling.
			case DOCKING_CLEARANCE_STATUS_REQUESTED:
			case DOCKING_CLEARANCE_STATUS_GRANTED:
				last_launch_time = timeNow;
				sendExpandedMessage("[station-docking-clearance-cancelled]", other);
				if (player != nullptr)  player->setDockingClearanceStatus(DOCKING_CLEARANCE_STATUS_NONE);
				result = "DOCKING_CLEARANCE_CANCELLED";
				player_reserved_dock = nil;
				if (currentlyInDockingQueues() == 0)
				{
					if (shipAI != nullptr)  shipAI->message("DOCKING_COMPLETE");
					doScriptEvent(OOJSID("stationDockingQueuesAreEmpty"));
				}
				break;
			case DOCKING_CLEARANCE_STATUS_NONE:
			case DOCKING_CLEARANCE_STATUS_NOT_REQUIRED:
				break;
		}
	}

	// First we must set the status to REQUESTED to avoid problems when 
	// switching docking targets - even if we later set it back to NONE.
	if (!result && (other != nullptr ? other->getIsPlayer() : false) && this != (player != nullptr ? player->getTargetDockStation() : (::StationEntity *)nullptr))
	{
		player_reserved_dock = nil; // and clear any previously reserved dock
		if (player != nullptr)  player->setDockingClearanceStatus(DOCKING_CLEARANCE_STATUS_REQUESTED);
	}

	// Deny docking for fugitives at the main station
	// TODO: Should this be another key in shipdata.plist and/or should this
	//  apply to all stations?
	if (!result && this == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr) && (other != nullptr ? other->getBounty() : 0) > 50)	// do not grant docking clearance to fugitives
	{
		sendExpandedMessage("[station-docking-clearance-H-clearance-refused]", other);
		if ((other != nullptr ? other->getIsPlayer() : false))
			if (player != nullptr)  player->setDockingClearanceStatus(DOCKING_CLEARANCE_STATUS_NONE);
		result = "DOCKING_CLEARANCE_DENIED_SHIP_FUGITIVE";
	}
	
	if (!result && (other != nullptr ? other->hasHostileTarget() : false)) // do not grant docking clearance to hostile ships.
	{
		sendExpandedMessage("[station-docking-clearance-denied]", other);
		if ((other != nullptr ? other->getIsPlayer() : false))
			if (player != nullptr)  player->setDockingClearanceStatus(DOCKING_CLEARANCE_STATUS_NONE);
		result = "DOCKING_CLEARANCE_DENIED_SHIP_HOSTILE";
	}

	if (!hasEligibleDock()) // make sure at least one dock could plausibly accept the player
	{
		if ((other != nullptr ? other->getIsPlayer() : false))
		{
			if (player != nullptr)  player->setDockingClearanceStatus(DOCKING_CLEARANCE_STATUS_NONE);
		}
		sendExpandedMessage("[station-docking-clearance-denied-no-docks]", other);

		result = "DOCKING_CLEARANCE_DENIED_NO_DOCKS";
	}
	else if (!hasClearDock()) // skip check if at least one dock clear
	{
		// Put ship in queue if we've got incoming or outgoing traffic or
		// if the player is waiting for manual clearance and we are not
		// the player
		if (!result && ((currentlyInDockingQueues() && last_launch_time < timeNow) || (!(other != nullptr ? other->getIsPlayer() : false) && (player != nullptr ? player->getDockingClearanceStatus() : OODockingClearanceStatus{}) == DOCKING_CLEARANCE_STATUS_REQUESTED)))
		{
			sendExpandedMessage(oo::str::formatRuntime(OO_DESC("station-docking-clearance-acknowledged-d-ships-approaching"), { currentlyInDockingQueues()+1 }), other);
			// No need to set status to REQUESTED as we've already done that earlier.
			result = "DOCKING_CLEARANCE_DENIED_TRAFFIC_INBOUND";
		}

		if (!result && currentlyInLaunchingQueues())
		{
			sendExpandedMessage(oo::str::formatRuntime(OO_DESC("station-docking-clearance-acknowledged-d-ships-departing"), { currentlyInLaunchingQueues()+1 }), other);
			// No need to set status to REQUESTED as we've already done that earlier.
			result = "DOCKING_CLEARANCE_DENIED_TRAFFIC_OUTBOUND";
		}
		if (!result)
		{
			// if this happens, the station has no docks which allow
			// docking, so deny clearance
			if ((other != nullptr ? other->getIsPlayer() : false))
			{
				if (player != nullptr)  player->setDockingClearanceStatus(DOCKING_CLEARANCE_STATUS_NONE);
			}
			result = "DOCKING_CLEARANCE_DENIED_NO_DOCKS";
			// but can check to see if we'll open some for later.
			BOOL openLater = NO;
			for (const oo::EntityHold &dock : dockSubEntities())
			{
				::DockEntity *sub = oo::ToDock(dock.get());
				std::string docking = (sub != nullptr ? sub->canAcceptShipForDocking(other) : std::optional<std::string>()).value_or("");
				if (docking == "DOCK_CLOSED")
				{
					ooscript::Context context = OOJSAcquireContext();
					ooscript::Value		rval = ooscript::undefinedValue();
					ooscript::Value		args[] = { OOJSValueFromCxxObject(context, sub),
														 OOJSValueFromCxxObject(context, other) };
					bool tempreject = NO;

					BOOL OK = (getScript() != nullptr ? getScript()->callMethod(OOJSID("willOpenDockingPortFor"), context, args, 2, &rval) : false);
					if (OK)  OK = ooscript::valueToBoolean(context, rval, &tempreject);
					if (!OK)  tempreject = NO; // default to permreject
					if (tempreject)
					{
						openLater = YES;
					}
					OOJSRelinquishContext(context);			
				}
				if (openLater) break;
			}

			if (openLater)
			{
				sendExpandedMessage("[station-docking-clearance-denied-no-docks-yet]", other);
			} 
			else
			{
				sendExpandedMessage("[station-docking-clearance-denied-no-docks]", other);
			}

		}
	}

	// Ship has passed all checks - grant docking!
	if (!result)
	{
		last_launch_time = timeNow + DOCKING_CLEARANCE_WINDOW;
		if ((other != nullptr ? other->getIsPlayer() : false)) 
		{
			if (player != nullptr)  player->setDockingClearanceStatus(DOCKING_CLEARANCE_STATUS_GRANTED);
			player_reserved_dock = selectDockForDocking();
		}

		if (hasMultipleDocks() && (other != nullptr ? other->getIsPlayer() : false))
		{
			const std::string grantedFormat = OO_DESC("station-docking-clearance-granted-in-@-until-@");	// the format first, as Clang evaluates the arguments: a description that is an array draws (ADR-0063 item 5)
			sendExpandedMessage(oo::str::formatRuntime(grantedFormat, { (player_reserved_dock != nullptr ? player_reserved_dock->getDisplayName() : std::optional<std::string>()).value_or("(null)"), cxx_ClockToString((player != nullptr ? player->clockTime() : 0.0) + DOCKING_CLEARANCE_WINDOW, NO) }), other);
		}
		else
		{
			const std::string grantedFormat = OO_DESC("station-docking-clearance-granted-until-@");	// the format first, as Clang evaluates the arguments: a description that is an array draws (ADR-0063 item 5)
			sendExpandedMessage(oo::str::formatRuntime(grantedFormat, { cxx_ClockToString((player != nullptr ? player->clockTime() : 0.0) + DOCKING_CLEARANCE_WINDOW, NO) }), other);
		}

		result = "DOCKING_CLEARANCE_GRANTED";
		if (shipAI != nullptr)  shipAI->reactToMessage("DOCKING_REQUESTED", std::nullopt);	// react to the request	
		doScriptEvent(OOJSID("stationAcceptedDockingRequest"), other);
	}
	return result;
}


unsigned StationEntity::currentlyInDockingQueues()
{
	unsigned soa = 0;
	for (const oo::EntityHold &dock : dockSubEntities())
	{
		::DockEntity *sub = oo::ToDock(dock.get());
		soa += (sub != nullptr ? sub->countOfShipsInDockingQueue() : 0);
	}
	soa += _shipsOnHold.count();
	return soa;
}


unsigned StationEntity::currentlyInLaunchingQueues()
{
	unsigned soa = 0;
	for (const oo::EntityHold &dock : dockSubEntities())
	{
		::DockEntity *sub = oo::ToDock(dock.get());
		soa += (sub != nullptr ? sub->countOfShipsInLaunchQueue() : 0);
	}
	return soa;
}


