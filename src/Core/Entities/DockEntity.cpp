/*

DockEntity.m

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

#include "DockEntity.h"
#include "StationEntity.h"
#include "ShipEntityAI.h"
#include "OOStringParsing.h"
#include "OOStringExpander.h"

#include "Universe.h"
#include "HeadUpDisplay.h"

#include "PlayerEntityLegacyScriptEngine.h"
#include "OOLegacyScriptWhitelist.h"
#include "OOPlanetEntity.h"
#include "OOShipGroup.h"
#include "OOQuiriumCascadeEntity.h"

#include "AI.h"
#include "OOCharacter.h"

#include "OOJSScript.h"
#include "OOJSDock.h"
#include "EntityOOJavaScriptExtensions.h"
#include "OODebugGLDrawing.h"
#include "OODebugFlags.h"
#include "oofnd/Log.hpp"
#include "oofnd/PListWriting.hpp"
#include "oofnd/String.hpp"


namespace
{

// [shipsOnApproach allKeys]: a snapshot, since the loops over it change the map.
std::vector<unsigned short> ShipIDsIn(const std::map<unsigned short, std::vector<oo::PList>> &queue)
{
	std::vector<unsigned short> shipIDs;
	shipIDs.reserve(queue.size());
	for (const auto &[shipID, coordinatesStack] : queue)  shipIDs.push_back(shipID);
	return shipIDs;
}


// %@ of the approach queue or a coordinates stack in the error logs (ADR-0043 item 23): the
// old-style plist text, ship IDs as decimal keys; GNUstep's exact -description is not kept.
std::string DescriptionForLog(const oo::PList &plist)
{
	const auto data = oo::writeOldStylePList(plist);
	return data.has_value() ? std::string(data->stringView()) : std::string("(unwritable)");
}


// OOMakeDockingInstructions() with no comms message, as -dockingInstructionsForShip: returns it.
oo::PList DockingInstructions(StationEntity *station, HPVector coords, float speed, float range, const char *ai_message, BOOL match_rotation, int docking_stage)
{
	return cxx_OOMakeDockingInstructions(station, coords, speed, range, std::string(ai_message), std::nullopt, match_rotation, docking_stage);
}


// -oo_stringForKey:'s value: a string, a number's -stringValue, anything else nullopt.
std::optional<std::string> OptionalStringValue(const oo::PList *value)
{
	if (value == nullptr)  return std::nullopt;
	if (const std::string *string = value->getIf<std::string>())  return *string;
	if (value->isNumber())  return oo::plist_get::numberStringValue(*value);
	return std::nullopt;
}

}	// namespace



// Slice 1 of docs/phases/3-slices/DockEntity.md (bead oo-ao2d): class shell, flags, geometry and
// lifecycle. The facade's initialiser and -dealloc are members since bead oo-9ht.180 deleted the
// facade (ADR-0056 amendment oo-9ht.180).


::ShipEntity *DockEntity::newDockObject(const std::string &key, const oo::PList &dict)
{
	::ShipEntity *object = oo::ToShip(oo::NewShipObject(oo::makeRef<DockEntity>(), key, dict));	// [super cxx_initWithKey:key definition:dict]
	if (object != nil)  static_cast<DockEntity *>(object)->initDockDefaults();
	return object;
}


void DockEntity::initDockDefaults()
{
	OOJS_PROFILE_ENTER

	allow_docking = YES;
	disallowed_docking_collides = NO;
	allow_launching = YES;
	virtual_dock = NO;

	OOJS_PROFILE_EXIT_VOID
}


void DockEntity::willDealloc()
{
	clearIdLocks(nil);
}


bool DockEntity::allowsDocking()
{
	return allow_docking;
}


void DockEntity::setAllowsDocking(bool allowed)
{
	if (!allowed && allow_docking) 
	{
		abortAllDockings();
	}
	allow_docking = allowed;
}


bool DockEntity::disallowedDockingCollides()
{
	return disallowed_docking_collides;
}


bool DockEntity::allowsLaunching()
{
	return allow_launching;
}


void DockEntity::setAllowsLaunching(bool allowed)
{
	if (!allowed && allow_launching) 
	{
		abortAllLaunches();
	}
	allow_launching = allowed;
}


void DockEntity::setDisallowedDockingCollides(bool ddc)
{
	disallowed_docking_collides = ddc;
}


void DockEntity::setVirtual()
{
	virtual_dock = YES;
}


bool DockEntity::isOffCentre()
{
	if (fabs(position.x) + fabs(position.y) > 5.0)
	{
		return YES;
	}
	Vector dir = vector_forward_from_quaternion(orientation);
	if (fabs(dir.x) + fabs(dir.y) > 0.1)
	{
		return YES;
	}
	return NO;
}


Vector DockEntity::portUpVectorForShipsBoundingBox(BoundingBox bb)
{
	BOOL twist = ((port_dimensions.x < port_dimensions.y) ^ (bb.max.x - bb.min.x < bb.max.y - bb.min.y));

	if (!twist)
	{
		return vector_up_from_quaternion(quaternion_multiply(orientation, (parentEntity() != nullptr ? parentEntity()->getOrientation() : Quaternion{})));
	}
	else
	{
		return vector_right_from_quaternion(quaternion_multiply(orientation, (parentEntity() != nullptr ? parentEntity()->getOrientation() : Quaternion{})));
	}
}


NSUInteger DockEntity::countOfShipsInDockingQueue()
{
	return shipsOnApproach.size();
}


NSUInteger DockEntity::countOfShipsInLaunchQueue()
{
	return launchQueue.size();
}


void DockEntity::clear()
{
	launchQueue.clear();
	shipsOnApproach.clear();
}


void DockEntity::setDimensionsAndCorridor(bool docking, bool ddc, bool launching)
{
	::StationEntity *station = oo::ToStation(parentEntity());
	if (virtual_dock)
	{
		port_dimensions = (station != nullptr ? station->virtualPortDimensions() : Vector{});
	}
	else
	{
		BoundingBox bb = getBoundingBox();
		port_dimensions = make_vector(bb.max.x - bb.min.x, bb.max.y - bb.min.y, bb.max.z - bb.min.z);
	}

	HPVector vk = HPvector_forward_from_quaternion(orientation);
	
	BoundingBox stbb = (station != nullptr ? station->getBoundingBox() : BoundingBox{});
	HPVector start = position;
	while ((start.x > stbb.min.x)&&(start.x < stbb.max.x) &&
		   (start.y > stbb.min.y)&&(start.y < stbb.max.y) &&
		   (start.z > stbb.min.z)&&(start.z < stbb.max.z) )
	{
		start = HPvector_add(start, HPvector_multiply_scalar(vk, port_dimensions.z));
	}
	port_corridor = start.z - position.z;
	
	allow_docking = docking;
	disallowed_docking_collides = ddc;
	allow_launching = launching;
}



//////////////////////////////////////////////// from superclass

bool DockEntity::isDock()
{
	return YES;
}


// The binding's bodies (OOJSDock.mm), which a category on the façade forwarded to
// until bead oo-9ht.47.
void DockEntity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)
{
	::OOJSDockGetJSClass(outClass, outPrototype);
}


bool DockEntity::isVisibleToScripts()
{
	return ::ShipEntityJSIsVisibleToScripts();
}


std::optional<std::string> DockEntity::jsClassName()
{
	return ::OOJSDockJSClassName();
}


void DockEntity::clearIdLocks(::ShipEntity *ship)
{
	int i;
	for (i = 1; i < MAX_DOCKING_STAGES; i++)
	{
		if (ship == nullptr || ship == oo::LiveEntity(id_lock[i]))
		{
			id_lock[i] = nullptr;
		}
	}
}


void DockEntity::clearAllIdLocks()
{
	int i;
	for (i = 1; i < MAX_DOCKING_STAGES; i++)
	{
		id_lock[i] = nullptr;
	}
}


bool DockEntity::setUpShipFromDictionary(const oo::PList &dict)
{
	OOJS_PROFILE_ENTER
	
	isShip = YES;
	isStation = NO;
	
	if (!ShipEntity::setUpShipFromDictionary(dict))  return NO;
	
	return YES;
	
	OOJS_PROFILE_EXIT
}


void DockEntity::update(OOTimeDelta delta_t)
{
	ShipEntity::update(delta_t);	// [super update:delta_t]
	
	if ((!launchQueue.empty())&&(shipsOnApproach.empty())&&dockingCorridorIsEmpty())
	{
		const oo::EntityHold se = launchQueue.front();
		// check to make sure ship has not been destroyed in queue by script
		if (oo::EntityStatus(se.get()) == STATUS_DOCKED)
		{
			launchShip(oo::ToShip(se.get()));
		}
		if (!launchQueue.empty())  launchQueue.erase(launchQueue.begin());	// (-removeObjectAtIndex:0 of an emptied queue raised)
	}
	if ((launchQueue.empty()) && no_docking_while_launching)
	{
		no_docking_while_launching = NO;	// launching complete
	}
	
}


// avoid possibility of shooting the virtual dock damaging the station
void DockEntity::noteTakingDamage(double amount, Entity *entity, OOShipDamageType type)
{
	if (virtual_dock) // can't be damaged
	{
		return;
	}
	ShipEntity::noteTakingDamage(amount, entity, type);
}


void DockEntity::takeEnergyDamage(double amount, Entity *ent, Entity *other, const std::string &weaponIdentifier)
{
	if (virtual_dock) // can't be damaged
	{
		return;
	}
	ShipEntity::takeEnergyDamage(amount, ent, other, weaponIdentifier);
}


// virtual docks are invisible
void DockEntity::drawImmediate(bool immediate, bool translucent)
{
	if (virtual_dock) // not drawn
	{
		return;
	}
	ShipEntity::drawImmediate(immediate, translucent);
}


// Slice 2 of docs/phases/3-slices/DockEntity.md (bead oo-9ht.178): docking guidance, the approach
// queue and docking instructions. The facade forwards each selector (DockEntity (OOSlice2)).

NSUInteger DockEntity::pruneAndCountShipsOnApproach()
{
	// Remove dead entities.
	// Enumerate over a snapshot of the keys because we mutate the map.
	for (unsigned short idObj : ShipIDsIn(shipsOnApproach))
	{
		::ShipEntity *ship = oo::ToShip((UNIVERSE != nullptr ? UNIVERSE->entityForUniversalID(idObj) : nullptr));
		/* Remove ships from the approach queue if they are dead, or
		 * are more than 25.6km from the dock.
		 */
		if (ship == nil || HPmagnitude2(HPvector_subtract((ship != nullptr ? ship->getPosition() : HPVector{}),absolutePositionForSubentity())) > SCANNER_MAX_RANGE2)
		{
			shipsOnApproach.erase(idObj);
			if (ship != nil) {
				// notify ship if it's alive
				if (ship != nullptr)  ship->sendAIMessage("DOCKING_ABORTED");
				if (ship != nullptr)  ship->doScriptEvent(OOJSID("stationWithdrewDockingClearance"));
			}
		}
	}
	
	if (shipsOnApproach.empty())
	{
		if (last_launch_time < (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0))
		{
			last_launch_time = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0);
		}
	}
	
	return shipsOnApproach.size();
}


void DockEntity::abortAllDockings()
{
	double		playerExtraTime = 0;
	
	no_docking_while_launching = YES;
	
	for (unsigned short idObj : ShipIDsIn(shipsOnApproach))
	{
		::ShipEntity *ship = oo::ToShip((UNIVERSE != nullptr ? UNIVERSE->entityForUniversalID(idObj) : nullptr));
		if ((ship != nullptr ? ship->getIsShip() : false))
		{
			if (ship != nullptr)  ship->sendAIMessage("DOCKING_ABORTED");
			if (ship != nullptr)  ship->doScriptEvent(OOJSID("stationWithdrewDockingClearance"));
		}
	}
	shipsOnApproach.clear();
	
	::PlayerEntity *player = PLAYER;
	::StationEntity *station = oo::ToStation(parentEntity());
	BOOL isDockingStation = (station == (player != nullptr ? player->getTargetDockStation() : (::StationEntity *)nullptr)) && ((station != nullptr ? station->playerReservedDock() : (::DockEntity *)nullptr) == this);
	if (isDockingStation && (player != nullptr ? player->status() : OOEntityStatus{}) == STATUS_IN_FLIGHT &&
			(player != nullptr ? player->getDockingClearanceStatus() : OODockingClearanceStatus{}) >= DOCKING_CLEARANCE_STATUS_REQUESTED)
	{
		if (HPmagnitude2(HPvector_subtract((player != nullptr ? player->getPosition() : HPVector{}), absolutePositionForSubentity())) > 2250000) // within 1500m of the dock
		{
			if (station != nullptr)  station->sendExpandedMessage("[station-docking-clearance-abort-cancelled]", player);
			if (player != nullptr)  player->setDockingClearanceStatus(DOCKING_CLEARANCE_STATUS_NONE);
			if (player != nullptr)  player->doScriptEvent(OOJSID("stationWithdrewDockingClearance"));
		}
		else
		{
			playerExtraTime = 10; // when very close to the port, give the player a few seconds to react on the abort message.
			int seconds = round(playerExtraTime);
			const std::optional<std::string> message = cxx_OOExpandKey("station-docking-clearance-abort-cancelled-in-time", seconds);
			if (message.has_value())  { if (station != nullptr)  station->sendExpandedMessage(*message, player); }	// nil: nothing sent, as before
			if (player != nullptr)  player->setDockingClearanceStatus(DOCKING_CLEARANCE_STATUS_TIMING_OUT);
		}

	}
	
	// mark docking queue flight pattern as clear
	clearAllIdLocks();

	last_launch_time = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) + playerExtraTime;
}


void DockEntity::autoDockShipsInQueue(std::map<unsigned short, std::vector<oo::PList>> &queue)
{	
	for (unsigned short idObj : ShipIDsIn(queue))
	{
		::ShipEntity *ship = oo::ToShip((UNIVERSE != nullptr ? UNIVERSE->entityForUniversalID(idObj) : nullptr));
		if ((ship != nullptr ? ship->getIsShip() : false))
		{
			pullInShipIfPermitted(ship);
		}
	}
	
	queue.clear();
}


void DockEntity::autoDockShipsOnApproach()
{
	autoDockShipsInQueue(shipsOnApproach);
}


std::optional<std::string> DockEntity::canAcceptShipForDocking(::ShipEntity *ship)
{
	// First test permanent rejection reasons
	if (!allow_docking)
	{
		return "DOCK_CLOSED"; // could be temp or perm reject
	}
	BoundingBox bb = (ship != nullptr ? ship->getTotalBoundingBox() : BoundingBox{});
	if ((port_dimensions.x < (bb.max.x - bb.min.x) || port_dimensions.y < (bb.max.y - bb.min.y)) && 
		(port_dimensions.y < (bb.max.x - bb.min.x) || port_dimensions.x < (bb.max.y - bb.min.y)))
	{
		return "TOO_BIG_TO_DOCK";
	}

	// callback to allow more complex filtering on accept/reject
	ooscript::Context context = OOJSAcquireContext();
	ooscript::Value		rval = ooscript::undefinedValue();
	ooscript::Value		args[] = { OOJSValueFromCxxObject(context, ship) };
	bool accept = YES;
	
	BOOL OK = (getScript() != nullptr ? getScript()->callMethod(OOJSID("acceptDockingRequestFrom"), context, args, 1, &rval) : false);
	if (OK)  OK = ooscript::valueToBoolean(context, rval, &accept);
	if (!OK)  accept = YES; // default to permreject
	OOJSRelinquishContext(context);

	if (!accept)
	{
		return "TOO_BIG_TO_DOCK";
	}

	// Second test temporary rejection reasons
	if (no_docking_while_launching)
	{
		return "TRY_AGAIN_LATER";
	}
	// if there are pending launches, temporarily don't accept docking requests
	if (allow_launching && !launchQueue.empty())
	{
		return "TRY_AGAIN_LATER";
	}
	
	return "DOCKING_POSSIBLE";
}


oo::PList DockEntity::dockingInstructionsForShip(::ShipEntity *ship)
{
	ShipEntity *self = this;
	if (ship == nil)  return oo::PList();
	
	OOUniversalID	ship_id = (ship != nullptr ? ship->getUniversalID() : OOUniversalID{});
	const unsigned short	shipID = (unsigned short)ship_id;	// +numberWithUnsignedShort:
	::StationEntity *station = oo::ToStation(parentEntity());

	HPVector launchVector = HPvector_forward_from_quaternion(quaternion_multiply(orientation, (station != nullptr ? station->getOrientation() : Quaternion{})));
	HPVector temp = (fabs(launchVector.x) < 0.8)? make_HPvector(1,0,0) : make_HPvector(0,1,0);
	temp = HPcross_product(launchVector, temp);	// 90 deg to launchVector & temp
	HPVector vi = HPcross_product(launchVector, temp);
	HPVector vj = HPcross_product(launchVector, vi);
	HPVector vk = launchVector;
	
	// check if this is a new ship on approach
	//
	if (!shipsOnApproach.contains(shipID))
	{
		HPVector	delta = HPvector_subtract((ship != nullptr ? ship->getPosition() : HPVector{}), absolutePositionForSubentity());
		float	ship_distance = HPmagnitude(delta);

		if (ship_distance > SCANNER_MAX_RANGE)
		{
			// too far away - don't claim a docking slot by not putting on approachlist for now.
			return DockingInstructions(station, absolutePositionForSubentity(), (ship != nullptr ? ship->getMaxFlightSpeed() : 0.0f), 10000, "APPROACH", NO, -1);
		}

		addShipToShipsOnApproach(ship);
		
		if (ship_distance < 1000.0 + (station != nullptr ? station->collisionRadius() : 0.0f) + ship->collision_radius)	// too close - back off
			return DockingInstructions(station, absolutePositionForSubentity(), (ship != nullptr ? ship->getMaxFlightSpeed() : 0.0f), 5000, "BACK_OFF", NO, -1);
		
		float dot = HPdot_product(launchVector, delta);
		if (dot < 0) // approaching from the wrong side of the station - construct a vector to the side of the station.
		{
			HPVector approachVector = HPcross_product(HPvector_normal(delta), launchVector);
			approachVector = HPcross_product(launchVector, approachVector); // vector, 90 degr rotated from launchVector towards target.
			return DockingInstructions(station, OOHPVectorTowards(absolutePositionForSubentity(), approachVector, (station != nullptr ? station->collisionRadius() : 0.0f) + 5000) , (ship != nullptr ? ship->getMaxFlightSpeed() : 0.0f), 1000, "APPROACH", NO, -1);
		}
		
		if (ship_distance > 12500.0)
		{
			// long way off - approach more closely
			return DockingInstructions(station, absolutePositionForSubentity(), (ship != nullptr ? ship->getMaxFlightSpeed() : 0.0f), 10000, "APPROACH", NO, -1);
		}
	}
	
	if (!shipsOnApproach.contains(shipID))
	{
		// some error has occurred - log it, and send the try-again message
		oo::PList::Dict queue;
		for (const auto &[queuedID, queuedStack] : shipsOnApproach)  queue[oo::str::format("%u", (unsigned)queuedID)] = oo::PList(oo::PList::Array(queuedStack));
		OO_LOG_ERR("station.issueDockingInstructions.failed", "couldn't addShipToShipsOnApproach:{} in {}, retrying later -- shipsOnApproach:\n{}", oo::EntityDescription(ship), oo::EntityDescription(self), DescriptionForLog(oo::PList(std::move(queue))));
		
		return DockingInstructions(station, (ship != nullptr ? ship->getPosition() : HPVector{}), 200, 100, "TRY_AGAIN_LATER", NO, -1);
	}


	//	shipsOnApproach now has an entry for the ship.
	//
	std::vector<oo::PList> &coordinatesStack = shipsOnApproach[shipID];

	if (coordinatesStack.empty())
	{
		OO_LOG_ERR("station.issueDockingInstructions.failed", " -- coordinatesStack = {}", DescriptionForLog(oo::PList(oo::PList::Array(coordinatesStack))));
		
		return DockingInstructions(station, (ship != nullptr ? ship->getPosition() : HPVector{}), 0, 100, "HOLD_POSITION", NO, -1);
	}
	
	// get the docking information from the instructions	
	const oo::PList &nextCoords = coordinatesStack[0];
	int docking_stage = nextCoords.get<int>("docking_stage");
	float speedAdvised = nextCoords.get<float>("speed");
	float rangeAdvised = nextCoords.get<float>("range");
	
	// calculate world coordinates from relative coordinates
	HPVector rel_coords;
	rel_coords.x = nextCoords.get<double>("rx");
	rel_coords.y = nextCoords.get<double>("ry");
	rel_coords.z = nextCoords.get<double>("rz");
	HPVector coords = absolutePositionForSubentity();
	coords.x += rel_coords.x * vi.x + rel_coords.y * vj.x + rel_coords.z * vk.x;
	coords.y += rel_coords.x * vi.y + rel_coords.y * vj.y + rel_coords.z * vk.y;
	coords.z += rel_coords.x * vi.z + rel_coords.y * vj.z + rel_coords.z * vk.z;
	
	// check if the ship is at the control point
	double max_allowed_range = 2.0f * rangeAdvised + ship->collision_radius;	// maximum distance permitted from control point - twice advised range
	HPVector delta = HPvector_subtract(ship->position, coords);
	
	if (HPmagnitude2(delta) > max_allowed_range * max_allowed_range)	// too far from the coordinates - do not remove them from the stack!
	{
		if ((docking_stage == 1) &&(HPmagnitude2(delta) < 1000000.0))	// 1km*1km
			speedAdvised *= 0.5;	// half speed
		
		return DockingInstructions(station, coords, speedAdvised, rangeAdvised, "APPROACH_COORDINATES", NO, docking_stage);
	}
	
	// else, reached the current coordinates okay..

	// get the NEXT coordinates (a copy: the messages below may run code that changes the queue)
	if (coordinatesStack.size() < 2 || !coordinatesStack[1].isDict())
	{
		return oo::PList();
	}
	const oo::PList next = coordinatesStack[1];
	
	docking_stage = next.get<int>("docking_stage");
	speedAdvised = next.get<float>("speed");
	rangeAdvised = next.get<float>("range");
	BOOL match_rotation = next.get<bool>("match_rotation");
	const std::optional<std::string> comms_message = OptionalStringValue(next.find("comms_message"));
	
	if (comms_message)
	{
		if (station != nullptr)  station->sendExpandedMessage(*comms_message, ship);
	}
			
	// calculate world coordinates from relative coordinates
	rel_coords.x = next.get<double>("rx");
	rel_coords.y = next.get<double>("ry");
	rel_coords.z = next.get<double>("rz");
	coords = absolutePositionForSubentity();
	coords.x += rel_coords.x * vi.x + rel_coords.y * vj.x + rel_coords.z * vk.x;
	coords.y += rel_coords.x * vi.y + rel_coords.y * vj.y + rel_coords.z * vk.y;
	coords.z += rel_coords.x * vi.z + rel_coords.y * vj.z + rel_coords.z * vk.z;
	
	if(oo::LiveEntity(id_lock[docking_stage]) == nullptr &&
	   oo::LiveEntity(id_lock[docking_stage + 1]) == nullptr &&
	   oo::LiveEntity(id_lock[docking_stage + 2]) == nullptr)	// check three stages ahead
	{
		// approach is clear - move to next position
		//
		
		// clear any previously owned docking stages
		clearIdLocks(ship);
				
		if (docking_stage > 1)	// don't claim first docking stage
		{
			id_lock[docking_stage] = oo::WeakRef<Entity>(ship);	// otherwise - claim this docking stage
		}
		
		//remove the previous stage from the stack
		auto stack = shipsOnApproach.find(shipID);
		if (stack != shipsOnApproach.end() && !stack->second.empty())  stack->second.erase(stack->second.begin());
		
		return DockingInstructions(station, coords, speedAdvised, rangeAdvised, "APPROACH_COORDINATES", match_rotation, docking_stage);
	}
	
	// else, approach isn't clear - hold position..
	//
	if (ship != nullptr && ship->getAI() != nullptr)  ship->getAI()->message("HOLD_POSITION");
	
	if (next.find("hold_message_given") == nullptr)
	{
		// COMM-CHATTER
		if (UNIVERSE != nullptr)  UNIVERSE->clearPreviousMessage();
		sendExpandedMessage("[station-hold-position]", ship);
		auto stack = shipsOnApproach.find(shipID);
		if (stack != shipsOnApproach.end() && stack->second.size() > 1)
		{
			if (oo::PList::Dict *held = stack->second[1].getIf<oo::PList::Dict>())  (*held)["hold_message_given"] = oo::PList("YES");
		}
	}

	return DockingInstructions(station, ship->position, 0, 100, "HOLD_POSITION", NO, -1);
}


void DockEntity::addShipToShipsOnApproach(::ShipEntity *ship)
{		
	int			corridor_distance[] =	{	-1,	1,	3,	5,	7,	9,	11,	12,	12};
	int			corridor_offset[] =		{	0,	0,	0,	0,	0,	0,	1,	3,	12};
	/* Eric's improvements to the docking flight code seem to have
	 * made it safer to go quite a bit faster here. With the increased
	 * numbers of ships which might need to dock at the main station,
	 * faster docking will help avoid massive queues. Previous speed
	 * was mostly 48 - CIM: 27/8/2013*/
	int			corridor_speed[] =		{	96,	96,	128,	128,	96,	128,	128,	256,	512};	// how fast to approach the next point
	int			corridor_range[] =		{	24,	12,	6,	4,	4,	6,	15,	38,	96};	// how close you have to get to the target point
	int			corridor_rotate[] =		{	1,	1,	1,	1,	0,	0,	0,	0,	0};		// whether to match the station rotation
	int			corridor_count = 9;
	int			corridor_final_approach = 3;
	
	const unsigned short	shipID = (unsigned short)(ship != nullptr ? ship->getUniversalID() : OOUniversalID{});	// +numberWithUnsignedShort:
	::StationEntity *station = oo::ToStation(parentEntity());
	
	HPVector launchVector = HPvector_forward_from_quaternion(quaternion_multiply(orientation, (station != nullptr ? station->getOrientation() : Quaternion{})));
	HPVector temp = (fabs(launchVector.x) < 0.8)? make_HPvector(1,0,0) : make_HPvector(0,1,0);
	temp = HPcross_product(launchVector, temp);	// 90 deg to launchVector & temp
	HPVector rightVector = HPcross_product(launchVector, temp);
	HPVector upVector = HPcross_product(launchVector, rightVector);
	
	// will select a direction for offset based on the entity personality (was ship ID)
	int offset_id = (ship != nullptr ? ship->entityPersonalityInt() : GLint{}) & 0xf;	// 16  point compass
	double c = cos(offset_id * M_PI * ONE_EIGHTH);
	double s = sin(offset_id * M_PI * ONE_EIGHTH);
	
	// test if this points at the ship
	HPVector point1 = absolutePositionForSubentity();
	point1.x += launchVector.x * corridor_offset[corridor_count - 1];
	point1.y += launchVector.x * corridor_offset[corridor_count - 1];
	point1.z += launchVector.x * corridor_offset[corridor_count - 1];
	HPVector alt1 = point1;
	point1.x += c * upVector.x * corridor_offset[corridor_count - 1] + s * rightVector.x * corridor_offset[corridor_count - 1];
	point1.y += c * upVector.y * corridor_offset[corridor_count - 1] + s * rightVector.y * corridor_offset[corridor_count - 1];
	point1.z += c * upVector.z * corridor_offset[corridor_count - 1] + s * rightVector.z * corridor_offset[corridor_count - 1];
	alt1.x -= c * upVector.x * corridor_offset[corridor_count - 1] + s * rightVector.x * corridor_offset[corridor_count - 1];
	alt1.y -= c * upVector.y * corridor_offset[corridor_count - 1] + s * rightVector.y * corridor_offset[corridor_count - 1];
	alt1.z -= c * upVector.z * corridor_offset[corridor_count - 1] + s * rightVector.z * corridor_offset[corridor_count - 1];
	if (HPdistance2(alt1, ship->position) < HPdistance2(point1, ship->position))
	{
		s = -s;
		c = -c;	// turn 180 degrees
	}
	
	//
	std::vector<oo::PList> coordinatesStack;
	coordinatesStack.reserve(MAX_DOCKING_STAGES);
	float port_depth = port_dimensions.z;	// 250m deep standard port.
	
	int i;
	for (i = corridor_count - 1; i >= 0; i--)
	{
		oo::PList::Dict nextCoords;
		int offset = corridor_offset[i];
		float corridor_length = port_depth * corridor_distance[i];
		
		float rx = s * port_depth * offset;
		float ry = c * port_depth * offset;
		float rz = corridor_length;
		// if there are many ships on approach, randomise coordinates a bit
		if ((i == corridor_count - 1) && countOfShipsInDockingQueue())
		{
			/* This used to try to just space the ships further out
			 * along the 16 approach lanes - this had various problems
			 * with putting ship coordinates on top of each other
			 * and/or spacing them out all the way back to the
			 * witchpoint. Instead, use a few more bits of
			 * entityPersonalityInt to shuffle the holding coordinates
			 * a bit more. It still doesn't guarantee two ships won't
			 * want the same space, but it makes it considerably more
			 * unlikely - I dropped 100 docking ships into the aegis
			 * at once, and they all got allocated positions far
			 * enough from the others to avoid collisions or near
			 * misses - CIM: 27 May 2014 */

			int offset_id2 = ((ship != nullptr ? ship->entityPersonalityInt() : GLint{}) & 0xf0)>>4;	// 16  point compass
			int offset_id3 = ((ship != nullptr ? ship->entityPersonalityInt() : GLint{}) & 0xf00)>>8;	// 16  point step position
			float c2 = cos(offset_id2 * M_PI * ONE_EIGHTH);
			float s2 = sin(offset_id2 * M_PI * ONE_EIGHTH);
			float ssize = MAX(port_depth,1500.0);
			rx += c2 * ssize; 
			ry += s2 * ssize; 
			rz += ssize * ((float)offset_id3 / 4.0);

//			// docking.debug: Adjusted coordinates by c2/s2/ssize factors
		}
		
		// add the lenght inside the station to the corridor, except for the final position, inside the dock.
		// (Upstream added port_corridor to corridor_length here when corridor_distance[i] > 0,
		// after its last read: a dead store, dropped when slice 1 touched the line (bead oo-ao2d).)
		
		// -oo_setInteger: stored a signed integer, -oo_setFloat: a double
		nextCoords["docking_stage"]	= oo::PList::signedInteger(corridor_count - i);
		nextCoords["rx"]			= oo::PList(static_cast<double>(rx));
		nextCoords["ry"]			= oo::PList(static_cast<double>(ry));
		nextCoords["rz"]			= oo::PList(static_cast<double>(rz));
		nextCoords["speed"]			= oo::PList(static_cast<double>(corridor_speed[i]));
		nextCoords["range"]			= oo::PList(static_cast<double>(corridor_range[i]));
		
		if (corridor_rotate[i])
		{
			nextCoords["match_rotation"] = oo::PList("YES");
		}
		
		if (i == corridor_final_approach)
		{
			if (station == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr))
			{
				nextCoords["comms_message"] = oo::PList("[station-begin-final-aproach]");
			}
			else
			{
				nextCoords["comms_message"] = oo::PList("[docking-begin-final-aproach]");
			}
		}
		
		coordinatesStack.push_back(oo::PList(std::move(nextCoords)));
	}
	
	shipsOnApproach[shipID] = std::move(coordinatesStack);
	
	
	// COMM-CHATTER
	if (station == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr))
	{
		if (station != nullptr)  station->sendExpandedMessage("[station-welcome]", ship);
	}
	else
	{
		if (station != nullptr)  station->sendExpandedMessage("[docking-welcome]", ship);
	}
}


void DockEntity::noteDockingForShip(::ShipEntity *ship)
{
	// safe to do this for now, as it just clears the ship from the docking queue
	abortDockingForShip(ship);
	
	// avoid clashes with outgoing ships
	last_launch_time = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0);

}


void DockEntity::abortDockingForShip(::ShipEntity *ship)
{
	OOUniversalID	ship_id = (ship != nullptr ? ship->getUniversalID() : OOUniversalID{});
	const unsigned short	shipID = (unsigned short)ship_id;	// +numberWithUnsignedShort:
	
	shipsOnApproach.erase(shipID);
	
	if ((ship != nullptr ? ship->getIsPlayer() : false))
	{
		::PlayerEntity * player = PLAYER;
		if ((player != nullptr ? player->status() : OOEntityStatus{}) == STATUS_IN_FLIGHT &&
				(player != nullptr ? player->getDockingClearanceStatus() : OODockingClearanceStatus{}) >= DOCKING_CLEARANCE_STATUS_REQUESTED)
		{
			if (HPmagnitude2(HPvector_subtract((player != nullptr ? player->getPosition() : HPVector{}), absolutePositionForSubentity())) > 2250000) // within 1500m of the dock
			{
				if (oo::ToShip(parentEntity()) != nullptr)  oo::ToShip(parentEntity())->sendExpandedMessage("[station-docking-clearance-abort-cancelled]", player);
				if (player != nullptr)  player->setDockingClearanceStatus(DOCKING_CLEARANCE_STATUS_NONE);
			}
			else
			{
				int seconds = 10; // when very close to the port, give the player a few seconds to react on the abort message.
				const std::optional<std::string> message = cxx_OOExpandKey("station-docking-clearance-abort-cancelled-in-time", seconds);
				if (message.has_value())  { if (oo::ToShip(parentEntity()) != nullptr)  oo::ToShip(parentEntity())->sendExpandedMessage(*message, player); }	// nil: nothing sent, as before
				if (player != nullptr)  player->setDockingClearanceStatus(DOCKING_CLEARANCE_STATUS_TIMING_OUT);
			}
		}
	}

	// clear any previously owned docking stages
	clearIdLocks(ship);
}


bool DockEntity::shipIsInDockingQueue(::ShipEntity *ship)
{
	if (!(ship != nullptr ? ship->getIsShip() : false))  return NO;
	if ((ship != nullptr ? ship->getIsPlayer() : false) && (ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_DEAD)  return NO;
	
	OOUniversalID	ship_id = (ship != nullptr ? ship->getUniversalID() : OOUniversalID{});
	const unsigned short	shipID = (unsigned short)ship_id;	// +numberWithUnsignedShort:
	
	if (shipsOnApproach.contains(shipID))
	{
		return YES;
	}
	// player docking manually
	if ((ship != nullptr ? ship->getIsPlayer() : false) && (oo::ToStation(owner()) != nullptr ? oo::ToStation(owner())->playerReservedDock() : (::DockEntity *)nil) == this)
	{
		return YES;
	}
	return NO;
}


void DockEntity::pullInShipIfPermitted(::ShipEntity *ship)
{
	// allow_docking: docking permitted and expected
	// disallowed_docking_collides: unauthorised docking does not result in explosion
	if (allow_docking || !disallowed_docking_collides)
	{
		if (ship != nullptr)  ship->enterDock(oo::ToStation(parentEntity()));
	}
}

// Slice 3 of docs/phases/3-slices/DockEntity.md (bead oo-9ht.179): the docking corridor and
// launching. The facade forwards each selector (DockEntity (OOSlice3)).

void DockEntity::abortAllLaunches()
{
	no_docking_while_launching = NO;
	launchQueue.clear();
}


bool DockEntity::shipIsInDockingCorridor(::ShipEntity *ship)
{
	if (!(ship != nullptr ? ship->getIsShip() : false))  return NO;
	if ((ship != nullptr ? ship->getIsPlayer() : false) && (ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_DEAD)  return NO;

	BOOL allow_docking_thisship = allow_docking || !disallowed_docking_collides;
	// ships can physically dock here, and this routine is mainly for
	// collision detection, but will never be directed here by traffic
	// control, if allow_docking is false but d_d_c is also false
	
	::StationEntity *station = oo::ToStation(parentEntity());
	if ((station != nullptr ? station->status() : OOEntityStatus{}) == STATUS_DEAD)
	{
		return NO;
	}
	
	Quaternion q0 = quaternion_multiply(orientation, (station != nullptr ? station->getOrientation() : Quaternion{}));
	Vector vi = vector_right_from_quaternion(q0);
	Vector vj = vector_up_from_quaternion(q0);
	Vector vk = vector_forward_from_quaternion(q0);
	
	HPVector port_pos = absolutePositionForSubentity();
	
	BoundingBox shipbb = (ship != nullptr ? ship->getBoundingBox() : BoundingBox{});
	BoundingBox arbb = (ship != nullptr ? ship->findBoundingBoxRelativeToPosition(port_pos, vi, vj, vk) : BoundingBox{});
	
	// port dimensions..
	GLfloat ww = port_dimensions.x;
	GLfloat hh = port_dimensions.y;
	GLfloat dd = port_dimensions.z;

	BOOL rotatedPort = (ww >= hh) ? NO : YES;
	BOOL rotatedShip = ((shipbb.max.x - shipbb.min.x) >= (shipbb.max.y - shipbb.min.y)) ? NO : YES;
	BOOL rotationsMatch = (rotatedShip == rotatedPort);
	if (rotationsMatch)
	{
		// the ship and port are both bigger in x than y
		while (shipbb.max.x - shipbb.min.x > ww * 0.90) ww *= 1.25;
		while (shipbb.max.y - shipbb.min.y > hh * 0.90) hh *= 1.25;
	}
	else
	{
		// the ship and port have different x/y biggerness
		while (shipbb.max.y - shipbb.min.y > ww * 0.90) ww *= 1.25;
		while (shipbb.max.x - shipbb.min.x > hh * 0.90) hh *= 1.25;
	}
	
	ww *= 0.5;
	hh *= 0.5;

#ifndef NDEBUG
	if ((ship != nullptr ? ship->getIsPlayer() : false) && (gDebugFlags & DEBUG_DOCKING))
	{
		BOOL			inLane;
		float			range;
		unsigned		laneFlags = 0;
		
		if (arbb.max.x < ww)   laneFlags |= 1;
		if (arbb.min.x > -ww)  laneFlags |= 2;
		if (arbb.max.y < hh)   laneFlags |= 4;
		if (arbb.min.y > -hh)  laneFlags |= 8;
		inLane = laneFlags == 0xF;
		range = 0.90 * arbb.max.z + 0.10 * arbb.min.z;
		
		OO_LOG("docking.debug", "Normalised port dimensions are {:g} x {:g} x {:g}.  Player bounding box is at {}-{} -- {} ({:X}), range: {:g}",
			ww * 2.0, hh * 2.0, dd,
			VectorDescription(arbb.min), VectorDescription(arbb.max),
			inLane ? "in lane" : "out of lane", static_cast<unsigned>(laneFlags),
			range);
	}
#endif

	if ((arbb.max.x < ww * 3.0)&&(arbb.min.x > -ww * 3.0)&&(arbb.max.y < hh * 3.0)&&(arbb.min.y > -hh * 3.0))
	{
		if ((station != nullptr ? station->getRequiresDockingClearance() : false) && (ship != nullptr ? ship->getIsPlayer() : false) && (ship != nullptr ? ship->status() : OOEntityStatus{}) != STATUS_LAUNCHING && (ship != nullptr ? ship->status() : OOEntityStatus{}) != STATUS_AUTOPILOT_ENGAGED && (PLAYER != nullptr ? PLAYER->getDockingClearanceStatus() : OODockingClearanceStatus{}) < DOCKING_CLEARANCE_STATUS_GRANTED)
		{
			if ((0.90 * arbb.max.z + 0.10 * arbb.min.z < 3000) && (dot_product(vk,(ship != nullptr ? ship->forwardVector() : Vector{})) < -0.9))
			{
				// player is in docking corridor and facing dock
				// and within 3km
				if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("oolite-station-docking-requires-clearance"), 3);
			}
		}
	}
	
	if (arbb.max.z < -dd)
	{
		return NO;
	}
	
	if ((arbb.max.x < ww)&&(arbb.min.x > -ww)&&(arbb.max.y < hh)&&(arbb.min.y > -hh))
	{
		if ((ship != nullptr ? ship->status() : OOEntityStatus{}) != STATUS_LAUNCHING && !allow_docking_thisship)
		{ // launch-only dock: will collide!
			if (arbb.min.z < dd)
			{
				if (ship != nullptr)  ship->takeScrapeDamage(5 * (UNIVERSE != nullptr ? UNIVERSE->getTimeDelta() : 0.0)*(ship != nullptr ? ship->getFlightSpeed() : 0.0f), station);
				// and bounce
				HPVector rel = HPvector_subtract((ship != nullptr ? ship->getPosition() : HPVector{}),port_pos);
				rel = HPvector_multiply_scalar(HPvector_normal(rel),(ship != nullptr ? ship->getFlightSpeed() : 0.0f)*0.4);
				if (ship != nullptr)  ship->adjustVelocity(HPVectorToVector(rel));
			}

			if (arbb.max.z < 0.0)
			{ // give some warning before exploding...
				return NO;
			}
		}

		// in lane
		if (0.90 * arbb.max.z + 0.10 * arbb.min.z < 0.0)	// we're 90% in docking position!
		{
			pullInShipIfPermitted(ship);
		}
		return YES;
	}
	
	if ((ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_LAUNCHING)
	{
		return YES;
	}
	
	// if close enough (within 50%) correct and add damage
	//
	GLfloat safety = 1.0+(50.0/100.0);

	if ((arbb.min.x > -safety * ww)&&(arbb.max.x < safety * ww)&&(arbb.min.y > -safety * hh)&&(arbb.max.y < safety * hh))
	{
		if (arbb.min.z < 0.0)	// got our nose inside
		{

			if ((arbb.min.x < -ww && arbb.max.x > ww) || (arbb.min.y < -hh && arbb.max.y > hh))
			{
				/* No matter how much safety margin there is, if the
				 * ship is going off opposite edges of the dock at
				 * once, that's a fatal collision */
				return NO;
			}

			GLfloat correction_factor = -arbb.min.z / (arbb.max.z - arbb.min.z);	// proportion of ship inside
		
			// damage the ship according to velocity - don't send collision messages to AIs to avoid problems.
			if (ship != nullptr)  ship->takeScrapeDamage(5 * (UNIVERSE != nullptr ? UNIVERSE->getTimeDelta() : 0.0)*(ship != nullptr ? ship->getFlightSpeed() : 0.0f), station);
			if (station != nullptr)  station->doScriptEvent(OOJSID("shipCollided"), ship); // no COLLISION message to station AI, carriers would move away!
			if (ship != nullptr)  ship->doScriptEvent(OOJSID("shipCollided"), station); // no COLLISION message to ship AI, dockingAI.plist would abort.
			
			Vector delta;
			delta.x = 0.5f * (arbb.max.x + arbb.min.x) * correction_factor;
			delta.y = 0.5f * (arbb.max.y + arbb.min.y) * correction_factor;
			
			if (arbb.max.x < ww && arbb.min.x > -ww)
			{
				// x is okay - no need to correct
				delta.x = 0.0f;
			}
			if (arbb.max.y > hh && arbb.min.y > -hh)
			{
				// y is okay - no need to correct
				delta.y = 0.0f;
			}
				
			// adjust the ship back to the center of the port
			HPVector pos = (ship != nullptr ? ship->getPosition() : HPVector{});
			pos.x -= delta.y * vj.x + delta.x * vi.x;
			pos.y -= delta.y * vj.y + delta.x * vi.y;
			pos.z -= delta.y * vj.z + delta.x * vi.z;
			if (ship != nullptr)  ship->setPosition(pos);
		}
		
		// if far enough in - dock
		if (0.90f * arbb.max.z + 0.10f * arbb.min.z < 0.0f)
		{
			pullInShipIfPermitted(ship);
		}
		
		return YES;	// okay NOW we're in the docking corridor!
	}
	
	return NO;
}


void DockEntity::addShipToLaunchQueue(::ShipEntity *ship, bool priority)
{
	pruneAndCountShipsOnApproach();
	
	if (ship == nil)  return;
	
	if (ship != nullptr)  ship->setStatus(STATUS_DOCKED);
	if (priority)
	{
		launchQueue.insert(launchQueue.begin(), oo::EntityHold(ship));
	}
	else
	{
		launchQueue.push_back(oo::EntityHold(ship));
	}
}


void DockEntity::launchShip(::ShipEntity *ship)
{
	if (!(ship != nullptr ? ship->getIsShip() : false))  return;
	
	BoundingBox		bb = (ship != nullptr ? ship->getBoundingBox() : BoundingBox{});
	::StationEntity	*station = oo::ToStation(parentEntity());
	
	HPVector launchPos = absolutePositionForSubentity();
	Vector launchVel = (station != nullptr ? station->getVelocity() : Vector{});
	double launchSpeed = 0.5 * (ship != nullptr ? ship->getMaxFlightSpeed() : 0.0f);
	if ((station != nullptr ? station->getMaxFlightSpeed() : 0.0f) > 0 && (station != nullptr ? station->getFlightSpeed() : 0.0f) > 0) // is self a carrier in flight.
	{
		launchSpeed = 0.5 * (ship != nullptr ? ship->getMaxFlightSpeed() : 0.0f) * (1.0 + (station != nullptr ? station->getFlightSpeed() : 0.0f)/(station != nullptr ? station->getMaxFlightSpeed() : 0.0f));
	}
	Quaternion q1 = (station != nullptr ? station->getOrientation() : Quaternion{});
	q1 = quaternion_multiply(orientation, q1);
	Vector launchVector = vector_forward_from_quaternion(q1);
	
	// launch orientation
	if ((port_dimensions.x < port_dimensions.y) ^ (bb.max.x - bb.min.x < bb.max.y - bb.min.y))
	{
		quaternion_rotate_about_axis(&q1, launchVector, M_PI*0.5);  // to account for the slot being at 90 degrees to vertical
	}
	if (ship != nullptr)  ship->setNormalOrientation(q1);
	// launch position
	if (ship != nullptr)  ship->setPosition(launchPos);
	if((ship != nullptr ? ship->pendingEscortCount() : uint8_t{}) > 0) { if (ship != nullptr)  ship->setPendingEscortCount(0); } // Make sure no extra escorts are added after launch. (e.g. for miners etc.)
	if ((ship != nullptr ? ship->hasEscorts() : false)) no_docking_while_launching = YES;
	// launch speed
	launchVel = vector_add(launchVel, vector_multiply_scalar(launchVector, launchSpeed));
	launchSpeed = magnitude(launchVel);
	if (ship != nullptr)  ship->setSpeed(launchSpeed);
	if (ship != nullptr)  ship->setVelocity(launchVel);
	// launch roll/pitch
	if (ship != nullptr)  ship->setRoll((station != nullptr ? station->getFlightRoll() : 0.0f));
	if (ship != nullptr)  ship->setPitch(0.0);
	if (ship != nullptr)  ship->setYaw(0.0);
	if (UNIVERSE != nullptr)  UNIVERSE->addEntity(ship);
	if (ship != nullptr)  ship->setStatus(STATUS_LAUNCHING);
	if (ship != nullptr)  ship->setDesiredSpeed(launchSpeed); // must be set after initialising the AI to correct any speed set by AI
	last_launch_time = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0);
	double delay = (port_corridor + 2 * port_dimensions.z)/launchSpeed; // pause until 2 portlengths outside of the station.
	if (ship != nullptr)  ship->setLaunchDelay(delay);
	if (ship != nullptr && ship->getAI() != nullptr)  ship->getAI()->setNextThinkTime(last_launch_time + delay); // pause while launching
	
	if (ship != nullptr)  ship->resetExhaustPlumes();	// resets stuff for tracking/exhausts
	
	if (ship != nullptr)  ship->doScriptEvent(OOJSID("shipWillLaunchFromStation"), station);
	if (station != nullptr)  station->doScriptEvent(OOJSID("stationLaunchedShip"), ship, "STATION_LAUNCHED_SHIP");
}


NSUInteger DockEntity::countOfShipsInLaunchQueueWithPrimaryRole(const std::string &role)
{
	NSUInteger count = 0;
	for (const oo::EntityHold &ship : launchQueue)
	{
		if ((oo::ToShip(ship.get()) != nullptr ? oo::ToShip(ship.get())->hasPrimaryRole(role) : false))  count++;
	}
	return count;
}


bool DockEntity::allowsLaunchingOf(::ShipEntity *ship)
{
	if (!(ship != nullptr ? ship->getIsShip() : false))  return NO;
	
	BoundingBox bb = (ship != nullptr ? ship->getTotalBoundingBox() : BoundingBox{});
	if ((port_dimensions.x < (bb.max.x - bb.min.x) || port_dimensions.y < (bb.max.y - bb.min.y)) && 
		(port_dimensions.y < (bb.max.x - bb.min.x) || port_dimensions.x < (bb.max.y - bb.min.y)) && !(ship != nullptr ? ship->getIsPlayer() : false))
	{
		return NO;
	}

	// callback to allow more complex filtering on accept/reject
	ooscript::Context context = OOJSAcquireContext();
	ooscript::Value		rval = ooscript::undefinedValue();
	ooscript::Value		args[] = { OOJSValueFromCxxObject(context, ship) };
	bool accept = YES;
	
	BOOL OK = (getScript() != nullptr ? getScript()->callMethod(OOJSID("acceptLaunchingRequestFrom"), context, args, 1, &rval) : false);
	if (OK)  OK = ooscript::valueToBoolean(context, rval, &accept);
	if (!OK)  accept = YES; // default to permreject
	OOJSRelinquishContext(context);
	if (!accept)
	{
		return NO;
	}

	return YES;
}	


bool DockEntity::dockingCorridorIsEmpty()
{
	double unitime = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0);
	
	if (unitime < last_launch_time + STATION_DELAY_BETWEEN_LAUNCHES)
	{
		// leave sufficient pause between launches
		return NO;
	}
	

	::StationEntity	*station = oo::ToStation(parentEntity());
	if ((station != nullptr ? station->playerReservedDock() : (::DockEntity *)nullptr) == this)
	{
		// player probably will not appreciate a ship launch right now
		return NO;
	}

	// check against all ships
	BOOL			isEmpty = YES;
	int				ent_count =		UNIVERSE->n_entities;
	Entity			**uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
	std::vector<Entity *>	my_entities(ent_count);	// each one's object retained (bead oo-9ht.39.26)
	int i;
	int ship_count = 0;
	
	for (i = 0; i < ent_count; i++)
	{
		//on red alert, launch even if the player is trying block the corridor. Ignore cargopods or other small debris.
		if (oo::EntityIsShip(uni_entities[i]) && ((station == nullptr || station->getAlertLevel() < STATION_ALERT_LEVEL_RED) || !oo::EntityIsPlayer(uni_entities[i])) && uni_entities[i]->getMass() > 1000)
		{
			my_entities[ship_count++] = oo::RetainEntity(uni_entities[i]);		//	retained
		}
	}

	for (i = 0; (i < ship_count)&&(isEmpty); i++)
	{
		::ShipEntity*	ship = oo::ToShip(my_entities[i]);
		if (ship == nullptr)  continue;	// (every one is a ship: the list holds the ships)
		double		d2 = HPdistance2((station != nullptr ? station->getPosition() : HPVector{}), ship->getPosition());
		if ((ship != station) && (d2 < 25000000)&&(ship->status() != STATUS_DOCKED))	// within 5km
		{
			HPVector ppos = absolutePositionForSubentity();
			d2 = HPdistance2(ppos, ship->position);
			if (d2 < 4000000)	// within 2km of the port entrance
			{
				Quaternion q1 = (station != nullptr ? station->getOrientation() : Quaternion{});
				q1 = quaternion_multiply(orientation, q1);
				//
				HPVector v_out = HPvector_forward_from_quaternion(q1);
				HPVector r_pos = make_HPvector(ship->position.x - ppos.x, ship->position.y - ppos.y, ship->position.z - ppos.z);
				if (r_pos.x||r_pos.y||r_pos.z)
					r_pos = HPvector_normal(r_pos);
				else
					r_pos.z = 1.0;
				//
				double vdp = HPdot_product(v_out, r_pos); //== cos of the angle between r_pos and v_out
				//
				if (vdp > 0.86)
				{
					isEmpty = NO;
					last_launch_time = unitime - STATION_DELAY_BETWEEN_LAUNCHES + STATION_LAUNCH_RETRY_INTERVAL;
				}
			}
		}
	}
	
	for (i = 0; i < ship_count; i++)
	{
		oo::ReleaseEntity(my_entities[i]);		//released
	}

	return isEmpty;
}


void DockEntity::clearDockingCorridor()
{
	// check against all ships
	::StationEntity	*station = oo::ToStation(parentEntity());
	BOOL			isClear = YES;
	int				ent_count =			UNIVERSE->n_entities;
	Entity			**uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
	std::vector<Entity *>	my_entities(ent_count);	// each one's object retained (bead oo-9ht.39.26)
	int i;
	int ship_count = 0;
	
	for (i = 0; i < ent_count; i++)
	{
		if (uni_entities[i]->isShip)
		{
			my_entities[ship_count++] = oo::RetainEntity(uni_entities[i]);		//	retained
		}
	}

	for (i = 0; i < ship_count; i++)
	{
		::ShipEntity	*ship = oo::ToShip(my_entities[i]);
		if (ship == nullptr)  continue;	// (every one is a ship: the list holds the ships)
		double		d2 = HPdistance2((station != nullptr ? station->getPosition() : HPVector{}), ship->getPosition());
		if ((ship != station)&&(d2 < 25000000)&&(ship->status() != STATUS_DOCKED))	// within 5km
		{
			HPVector ppos = absolutePositionForSubentity();
			float time_out = -15.00;	// 15 secs
			do
			{
				isClear = YES;
				d2 = HPdistance2(ppos, ship->position);
				if (d2 < 4000000)	// within 2km of the port entrance
				{
					Quaternion q1 = (station != nullptr ? station->getOrientation() : Quaternion{});
					q1 = quaternion_multiply(orientation, q1);
					//
					Vector v_out = vector_forward_from_quaternion(q1);
					Vector r_pos = make_vector(ship->position.x - ppos.x, ship->position.y - ppos.y, ship->position.z - ppos.z);
					if (r_pos.x||r_pos.y||r_pos.z)
						r_pos = vector_normal(r_pos);
					else
						r_pos.z = 1.0;
					//
					float vdp = dot_product(v_out, r_pos); //== cos of the angle between r_pos and v_out
					//
					if (vdp > 0.86f)
					{
						isClear = NO;
						
						// okay it's in the way .. give it a wee nudge (0.25s)
						if (ship != nullptr)  ship->update(0.25);
						time_out += 0.25;
					}
					if (time_out > 0)
					{
						HPVector v1 = HPvector_forward_from_quaternion(orientation);
						HPVector spos = ship->position;
						spos.x += 3000.0 * v1.x;	spos.y += 3000.0 * v1.y;	spos.z += 3000.0 * v1.z; 
						if (ship != nullptr)  ship->setPosition(spos); // move 3km out of the way
					}
				}
			} while (!isClear);
		}
	}
	
	for (i = 0; i < ship_count; i++)
	{
		oo::ReleaseEntity(my_entities[i]);		//released
	}

}

