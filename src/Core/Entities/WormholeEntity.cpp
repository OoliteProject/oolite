/*

WormholeEntity.m

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

#include "WormholeEntity.h"
#include "OOJSWormhole.h"

#include "ShipEntity.h"
#include "StationEntity.h"
#include "OOSunEntity.h"
#include "OOPlanetEntity.h"
#include "PlayerEntity.h"
#include "ShipEntityLoadRestore.h"

#include "Universe.h"
#include "AI.h"
#include "OORoleSet.h"
#include "OOShipRegistry.h"
#include "OOShipGroup.h"
#include "OOStringParsing.h"
#include "OOSystemDescriptionManager.h"
#include "OOLogging.h"
#include "OOPListGameTypes.h"
#include "oofnd/Log.hpp"
#include "OOObjCPList.h"
#include "oofnd/String.hpp"

#define OO_WORMHOLE_COLOR_BOOST	25.0
#define OO_WORMHOLE_COLOR_FVEC4	{ 0.067, 0.067, 1.0, 0.25 }

// Static local functions
static void DrawWormholeCorona(GLfloat inner_radius, GLfloat outer_radius, int step, GLfloat z_distance, GLfloat *col4v1);


namespace {

// [[UNIVERSE systemManager] getCoordinatesForSystem:inGalaxy:]: the manager is converted (a message
// to a missing manager answered zeros).
NSPoint SystemCoordinates(OOSystemID system, OOGalaxyID galaxy)
{
	OOSystemDescriptionManager *manager = (UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr);
	return manager != nullptr ? manager->getCoordinatesForSystem(system, galaxy) : NSMakePoint(0, 0);
}

}	// namespace


void WormholeEntity::init()
{
	// [super init] could not fail: the constructor ran Entity's -init body.
	{
		witch_mass = 0.0;
		shipsInTransit.reserve(4);
		collision_radius = 0.0;
		setStatus(STATUS_EFFECT);
		scanClass = CLASS_WORMHOLE;
		isWormhole = YES;
		scan_info = WH_SCANINFO_NONE;
		scan_time = 0;
		hasExitPosition = NO;
		containsPlayer = NO;
		exit_speed = 50.0;
	}
}


//
// Public Wormhole Implementation
//

void WormholeEntity::initWithDict(const oo::PList &dict)
{
	assert(!dict.isNull());

	init();
	// [self init] could not fail.
	{
		{
			oo::AutoreleaseScope pool;	// was @autoreleasepool (oo-31u.8)
			// wormholes from pre-1.80 savegames using "origin_seed" and "dest_seed"
			// currently get defaults set; will probably disappear unnoticed
			origin = dict.get<int>("origin_id", 0);
			destination = dict.get<int>("dest_id", 255);

			originCoords = SystemCoordinates(origin, (PLAYER != nullptr ? PLAYER->galaxyNumber() : OOGalaxyID{}));
			destinationCoords = SystemCoordinates(destination, (PLAYER != nullptr ? PLAYER->galaxyNumber() : OOGalaxyID{}));

			// We only ever init from dictionary if we're loaded by the player, so
			// by definition we have been scanned
			scan_info = WH_SCANINFO_SCANNED;

			// Remember, times are stored as Ship Clock - but anything
			// saving/restoring wormholes from dictionaries should know this!
			expiry_time = dict.get<double>("expiry_time");
			arrival_time = dict.get<double>("arrival_time");
			// just in case an old save game has one with crossed times
			if (expiry_time > arrival_time)
			{
				expiry_time = arrival_time - 1.0; 
			}

			// Since this is new for 1.75.1, we must give it a default values as we could be loading an old savegame
			estimated_arrival_time = dict.get<double>("estimated_arrival_time", arrival_time);
			const oo::PList *positionNode = dict.find("position");
			position = OOHPVectorFromPList(positionNode, kZeroHPVector);// what PListView's get<HPVector> called
			_misjump = dict.get<bool>("misjump", NO);
		
		
			// Setup shipsInTransit
			const oo::PList *shipDictsArray = dict.get<oo::PList::Array>("ships");
			shipsInTransit.clear();
			OOShipSaveContext restoreContext;
		
			for (std::size_t i = 0; shipDictsArray != nullptr && i < shipDictsArray->count(); i++)
			{
				const oo::PList &currShipDict = *shipDictsArray->at(i);
				const oo::PList *shipInfo = currShipDict.get<oo::PList::Dict>("ship_info");
				if (shipInfo != nullptr)
				{
					::ShipEntity *ship = ShipEntity::shipRestoredFromDictionary(*shipInfo, YES, &restoreContext);
					if (ship != nil)
					{
						// time_delta as stored; it was only ever read with -oo_doubleForKey: (0 when absent)
						shipsInTransit.push_back(OOWormholeTransit{ oo::EntityHold(ship), currShipDict.get<double>("time_delta"), std::nullopt });
					}
					else
					{
						const oo::PList *shipKey = shipInfo->find("ship_key");
						OO_LOG("wormhole.load.warning", "Wormhole ship \"{}\" failed to initialize - missing OXP or old-style saved wormhole data.", (shipKey != nullptr && (shipKey->isString() || shipKey->isNumber())) ? shipInfo->get<std::string>("ship_key") : std::string("(null)"));
					}
				}
			}
		}
	}
}

void WormholeEntity::initWormholeTo(OOSystemID s, ::ShipEntity *ship)
{
	assert(ship != nil);

	init();
	// [self init] could not fail.
	{
		double		now = (PLAYER != nullptr ? PLAYER->clockTimeAdjusted() : 0.0);
		double		distance;
		::OOSunEntity	*sun = (UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr);
		
		_misjump = NO;
		origin = (UNIVERSE != nullptr ? UNIVERSE->currentSystemID() : 0);
		destination = s;
		originCoords = (PLAYER != nullptr ? PLAYER->getGalaxy_coordinates() : NSPoint{});
		destinationCoords = SystemCoordinates(destination, (PLAYER != nullptr ? PLAYER->galaxyNumber() : OOGalaxyID{}));
		distance = distanceBetweenPlanetPositions(originCoords.x, originCoords.y, destinationCoords.x, destinationCoords.y);
		distance = fmax(distance, 0.1);
		witch_mass = 200000.0; // MKW 2010.11.21 - originally the ship's mass was added twice - once here and once in suckInShip.  Instead, we give each wormhole a minimum mass.
		if ((ship != nullptr ? ship->getIsPlayer() : false))
			witch_mass += (ship != nullptr ? ship->getMass() : 0.0f); // The player ship never gets sucked in, so add its mass here.

		if (sun && ((sun != nullptr ? sun->willGoNova() : false) || (sun != nullptr ? sun->goneNova() : false)) && (ship != nullptr ? ship->getMass() : 0.0f) > 240000) 
			shrink_factor = (ship != nullptr ? ship->getMass() : 0.0f) / 240000; // don't allow longstanding wormholes in nova systems. (60 sec * WORMHOLE_SHRINK_RATE = 240 000)
		else
			shrink_factor = 1;
			
		collision_radius = 0.5 * M_PI * pow(witch_mass, 1.0/3.0);
		expiry_time = now + (witch_mass / WORMHOLE_SHRINK_RATE / shrink_factor);
		travel_time = (distance * distance * 3600); // Taken from PlayerEntity.h
		arrival_time = now + travel_time;
		estimated_arrival_time = arrival_time;

		/* There are a number of bugs where the arrival time is < than the
		 * expiry time (i.e. both ends open at once).
		 * Rather than try to flatten all of them, having been unsuccessful twice
		 * it seems easier to declare as a matter of wormhole physics that it 
		 * _can't_ be open at both ends at once. - CIM: 13/12/12 */
		if (expiry_time > arrival_time)
		{
			expiry_time = arrival_time - 1.0; 
		}
		position = (ship != nullptr ? ship->getPosition() : HPVector{});
		zero_distance = HPdistance2((PLAYER != nullptr ? PLAYER->getPosition() : HPVector{}), position);
	}
}


void WormholeEntity::setMisjump()
{
	// Test for misjump first - it's entirely possibly that the wormhole
	// has already been marked for misjumping when another ship enters it.
	if (!_misjump)
	{
		double distance = distanceBetweenPlanetPositions(originCoords.x, originCoords.y, destinationCoords.x, destinationCoords.y);
		double time_adjust = distance * distance * (3600 - 2700); // NB: Time adjustment is calculated using original distance. Formula matches the one in [PlayerEntity witchJumpTo]
		arrival_time -= time_adjust;
		travel_time -= time_adjust;
		destinationCoords.x = (originCoords.x + destinationCoords.x) / 2;
		destinationCoords.y = (originCoords.y + destinationCoords.y) / 2;
		_misjump = YES;
	}
}


void WormholeEntity::setMisjumpWithRange(GLfloat range)
{
	if (range <= 0.0 || range >= 1.0)
	{
		range = 0.5; // for safety, though nothing should be setting this
	}
	_misjumpRange = range;
	// Test for misjump first - it's entirely possibly that the wormhole
	// has already been marked for misjumping when another ship enters it.
	if (!_misjump)
	{
		double distance = distanceBetweenPlanetPositions(originCoords.x, originCoords.y, destinationCoords.x, destinationCoords.y);
		double time_adjust = (distance * (1-_misjumpRange))*(distance * (1-_misjumpRange))*3600.0;
		// time adjustment ensures that misjumps not faster than normal jumps
		// formulae for time and distance by mwerle at http://developer.berlios.de/pm/task.php?func=detailtask&project_task_id=4703&group_id=3577&group_project_id=1753
		arrival_time -= time_adjust;
		travel_time -= time_adjust;
	
		destinationCoords.x = (originCoords.x * (1-_misjumpRange)) + (destinationCoords.x * _misjumpRange);
		destinationCoords.y = (originCoords.y * (1-_misjumpRange)) + (destinationCoords.y * _misjumpRange);
		_misjump = YES;
	}
}


bool WormholeEntity::withMisjump()
{
	return _misjump;
}


GLfloat WormholeEntity::misjumpRange()
{
	return _misjumpRange;
}


bool WormholeEntity::suckInShip(::ShipEntity *ship)
{
	if (!ship || (ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_ENTERING_WITCHSPACE)
	{
		return NO;
	}
	if (origin != (UNIVERSE != nullptr ? UNIVERSE->currentSystemID() : 0))
	{
		// if we're no longer in the origin system, can't suck in
		return NO;
	}
	if ((PLAYER != nullptr ? PLAYER->getGalaxy_coordinates() : NSPoint{}).x != originCoords.x || (PLAYER != nullptr ? PLAYER->getGalaxy_coordinates() : NSPoint{}).y != originCoords.y)
	{
		// if we're no longer at the origin coordinates, can't suck in (handles interstellar space case)
		return NO;
	}
	double now = (PLAYER != nullptr ? PLAYER->clockTimeAdjusted() : 0.0);

/* CIM: removed test. Not valid for wormholes which last longer than their travel time. Most likely for short distances e.g. zero-distance doubles. equal_seeds test above should cover it, with expiry_time test for safety.  */
/*	if (now > arrival_time)
		return NO;	// far end of the wormhole! */
	if( now > expiry_time )
		return NO;
	// MKW 2010.11.18 - calculate time it takes for ship to reach wormhole
	// This is for AI ships which get told to enter the wormhole even though they
	// may still be some distance from it when the player exits the system
	float d = HPdistance(position, (ship != nullptr ? ship->getPosition() : HPVector{}));
	d -= (ship != nullptr ? ship->collisionRadius() : 0.0f) + collisionRadius();
	if (d > 0.0f)
	{
		float afterburnerFactor = (ship != nullptr ? ship->hasFuelInjection() : false) && (ship != nullptr ? ship->getFuel() : OOFuelQuantity{}) > MIN_FUEL ? (ship != nullptr ? ship->afterburnerFactor() : 0.0f) : 1.0;
		float shipSpeed = (ship != nullptr ? ship->getMaxFlightSpeed() : 0.0f) * afterburnerFactor;
		// MKW 2011.02.27 - calculate speed based on group leader, if any, to
		// try and prevent escorts from entering the wormhole before their mother.
		::ShipEntity *leader = ((ship != nullptr ? ship->group() : (OOShipGroup *)nullptr) != nullptr ? (ship != nullptr ? ship->group() : (OOShipGroup *)nullptr)->leader() : (::ShipEntity *)nil);
		if (leader && (leader != ship))
		{
			afterburnerFactor = (leader != nullptr ? leader->hasFuelInjection() : false) && (leader != nullptr ? leader->getFuel() : OOFuelQuantity{}) > MIN_FUEL ? (leader != nullptr ? leader->afterburnerFactor() : 0.0f) : 1.0;
			float leaderShipSpeed = (leader != nullptr ? leader->getMaxFlightSpeed() : 0.0f) * afterburnerFactor;
			if (leaderShipSpeed < shipSpeed ) shipSpeed = leaderShipSpeed;
		}
		if (shipSpeed <= 0.0f ) shipSpeed = 0.1f;
		now += d / shipSpeed;
		if( now > expiry_time ) 
		{
			return NO;
		}
	}
	
	shipsInTransit.push_back(OOWormholeTransit{ oo::EntityHold(ship),
						now + travel_time - arrival_time,
						(ship != nullptr ? ship->beaconCode() : std::optional<std::string>()) });	// in case a beacon code has been set, nullopt otherwise
	witch_mass += (ship != nullptr ? ship->getMass() : 0.0f);
	expiry_time = now + (witch_mass / WORMHOLE_SHRINK_RATE / shrink_factor);
	// and, again, cap to be earlier than arrival time
	if (expiry_time > arrival_time)
	{
		expiry_time = arrival_time - 1.0; 
	}

	collision_radius = 0.5 * M_PI * pow(witch_mass, 1.0/3.0);
	
	if (UNIVERSE != nullptr)  UNIVERSE->addWitchspaceJumpEffectForShip(ship);
	
	// Should probably pass the wormhole, but they have no JS representation
	if (ship != nullptr)  ship->setStatus(STATUS_ENTERING_WITCHSPACE);
	if (ship != nullptr)  ship->doScriptEvent(OOJSID("shipWillEnterWormhole"));
	if (ship != nullptr && ship->getAI() != nullptr)  ship->getAI()->message("ENTERED_WITCHSPACE");

	if (UNIVERSE != nullptr)  UNIVERSE->removeEntity(ship);
	if (ship != nullptr && ship->getAI() != nullptr)  ship->getAI()->clearStack();	// get rid of any preserved states

	if ((ship != nullptr ? ship->getIsStation() : false))
	{
		if ((PLAYER != nullptr ? PLAYER->dockedStation() : (StationEntity *)nullptr) == oo::ToStation(ship))
		{
			// the carrier has jumped while the player is docked
			if (ship != nullptr)  oo::ToShip(oo::RetainEntity(ship));
			if (UNIVERSE != nullptr)  UNIVERSE->carryPlayerOn(oo::ToStation(ship), this);
			if (ship != nullptr)  oo::ReleaseEntity(ship);
		}
	}		

	return YES;
}


void WormholeEntity::disgorgeShips()
{
	double now = (PLAYER != nullptr ? PLAYER->clockTimeAdjusted() : 0.0);
	std::vector<OOWormholeTransit> shipsStillInTransit;
	shipsStillInTransit.reserve(shipsInTransit.size());
	BOOL hasShiftedExitPosition = NO;
	BOOL useExitXYScatter = NO;
	
	const std::vector<OOWormholeTransit> transits = shipsInTransit;	// (the array was enumerated as it stood)
	for (const OOWormholeTransit &shipInfo : transits)
	{
		::ShipEntity *ship = oo::ToShip(shipInfo.ship.get());
		const std::optional<std::string> &shipBeacon = shipInfo.beacon;
		double	ship_arrival_time = arrival_time + shipInfo.time;
		double	time_passed = now - ship_arrival_time;
		
		if ((ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_DEAD) continue; // skip dead ships.
		
		if (ship_arrival_time > now)
		{
			shipsStillInTransit.push_back(shipInfo);
		}
		else
		{
			// Only calculate exit position once so that all ships arrive from the same point
			if (!hasExitPosition)
			{
				position = (UNIVERSE != nullptr ? UNIVERSE->getWitchspaceExitPosition() : HPVector{});	// no need to reset PRNG.
				GLfloat min_d1 = (UNIVERSE != nullptr ? UNIVERSE->safeWitchspaceExitDistance() : 0.0f);
				Quaternion	q1;
				quaternion_set_random(&q1);
				double		d1 = SCANNER_MAX_RANGE*((ranrot_rand() % 256)/256.0 - 0.5);
				Vector		v1 = vector_forward_from_quaternion(q1);
				if (dot_product(v1,kBasisZVector) < -0.99)
				{
					// a bit more safe distance if right behind the buoy
					min_d1 *= 3.0;
				}

				if (fabs(d1) < min_d1)	// no closer than 750m to edge of buoy
				{
					d1 += ((d1 > 0.0)? min_d1: -min_d1);
				}
				position.x += v1.x * d1; // randomise exit position
				position.y += v1.y * d1;
				position.z += v1.z * d1;
			}
			
			if (hasExitPosition && (!containsPlayer || useExitXYScatter))
			{
				HPVector shippos;
				Vector exit_vector_x = vector_right_from_quaternion((UNIVERSE != nullptr ? UNIVERSE->getWitchspaceExitRotation() : Quaternion{}));			
				Vector exit_vector_y = vector_up_from_quaternion((UNIVERSE != nullptr ? UNIVERSE->getWitchspaceExitRotation() : Quaternion{}));
// entry wormhole has a radius of around 100m (or perhaps more)
// so randomise exit positions slightly too for second and subsequent ships
// helps avoid collisions when two ships enter wormhole at same time
				double offset_x = randf()*150.0-75.0;
				double offset_y = randf()*150.0-75.0;
				shippos.x = position.x + (offset_x*exit_vector_x.x)+(offset_y*exit_vector_y.x);
				shippos.y = position.y + (offset_x*exit_vector_x.y)+(offset_y*exit_vector_y.y);
				shippos.z = position.z + (offset_x*exit_vector_x.z)+(offset_y*exit_vector_y.z);
				if (ship != nullptr)  ship->setPosition(shippos);
			}
			else
			{
				// this is the first ship out of the wormhole
				setExitSpeed((ship != nullptr ? ship->getMaxFlightSpeed() : 0.0f)*WORMHOLE_LEADER_SPEED_FACTOR);
				if (containsPlayer)
				{ // reset the player's speed to the new speed
					if (PLAYER != nullptr)  PLAYER->setSpeed(exit_speed);
				}
				useExitXYScatter = YES;
				if (ship != nullptr)  ship->setPosition(position);
			}

			if (shipBeacon)
			{
				if (ship != nullptr)  ship->setBeaconCode(shipBeacon);
			}
			
			// Don't reduce bounty on misjump. Fixes #17992
			// - MKW 2011.03.10	
			if (!_misjump)  { if (ship != nullptr)  ship->setBounty((ship != nullptr ? ship->getBounty() : 0)/2, kOOLegalStatusReasonNewSystem); }	// adjust legal status for new system
			
			// now the cargo is defined in advance, this is unnecessary
/*			if ([ship cargoFlag] == CARGO_FLAG_FULL_PLENTIFUL)
			{
				[ship setCargoFlag: CARGO_FLAG_FULL_SCARCE];
				}*/
			
			if (time_passed < 2.0)
			{
				if (ship != nullptr)  ship->witchspaceLeavingEffects(); // adds the ship to the universe with effects.
			}
			else
			{
				// arrived 2 seconds or more before the player. Rings have faded out.
				if (ship != nullptr)  ship->setOrientation((UNIVERSE != nullptr ? UNIVERSE->getWitchspaceExitRotation() : Quaternion{}));
				if (ship != nullptr)  ship->setPitch(0.0);
				if (ship != nullptr)  ship->setRoll(0.0);
				if (ship != nullptr)  ship->setVelocity(kZeroVector);
				if (UNIVERSE != nullptr)  UNIVERSE->addEntity(ship);	// AI and status get initialised here
			}
			if (ship != nullptr)  ship->setSpeed(exitSpeed()); // all ships from this wormhole have same velocity

			// awaken JS-based AIs
			if (ship != nullptr)  ship->doScriptEvent(OOJSID("aiStarted"));

			// Wormholes now have a JS representation, so we could provide it
			// but is it worth it for the exit wormhole?
			if (ship != nullptr)  ship->doScriptEvent(OOJSID("shipExitedWormhole"), "EXITED WITCHSPACE");
		
			// update the ships's position
			if (!hasExitPosition)
			{
				hasExitPosition = YES;
				hasShiftedExitPosition = YES; // exitPosition is shifted towards the lead ship update position.
				if (ship != nullptr)  ship->update(time_passed); // do this only for one ship or the next ships might appear at very different locations.
				position = (ship != nullptr ? ship->getPosition() : HPVector{}); // e.g. when the player docks first before following, time_passed is already > 10 minutes.
			}
			else if (time_passed > 1) // Only update the ship position if it was some time ago, otherwise we're in 'real time'.
			{
				if (hasShiftedExitPosition)
				{
					// only update the time delay to the lead ship. Sign is not correct but updating gives a small spacial distribution.
					if (ship != nullptr)  ship->update((ship_arrival_time - arrival_time));
				}
				else
				{
					// Exit position was externally set, e.g. by player ship following through this wormhole.
					// Use the real time difference.
					if (ship != nullptr)  ship->update(time_passed);
				}
			}
		}
	}
	shipsInTransit = std::move(shipsStillInTransit);

	if (containsPlayer)
	{
		// ships exiting the wormhole after now are following the player
		// so appear behind them
		position = HPvector_add((PLAYER != nullptr ? PLAYER->getPosition() : HPVector{}), vectorToHPVector(vector_multiply_scalar((PLAYER != nullptr ? PLAYER->forwardVector() : Vector{}), -500.0f)));
		containsPlayer = NO;
	}
// else, the wormhole doesn't now (or never) contained the player, so
// no need to move it
}


void WormholeEntity::setContainsPlayer(bool val)
{
	containsPlayer = val;
}


void WormholeEntity::setExitPosition(HPVector pos)
{
	setPosition(pos);
	hasExitPosition = YES;
}

OOSystemID WormholeEntity::getOrigin()
{
	return origin;
}

OOSystemID WormholeEntity::getDestination()
{
	return destination;
}

NSPoint WormholeEntity::originCoordinates()
{
	return originCoords;
}

NSPoint WormholeEntity::destinationCoordinates()
{
	return destinationCoords;
}

double WormholeEntity::exitSpeed()
{
	return exit_speed;
}


void WormholeEntity::setExitSpeed(double speed)
{
	exit_speed = speed;
}


double WormholeEntity::expiryTime()
{
	return expiry_time;
}

double WormholeEntity::arrivalTime()
{
	return arrival_time;
}

double WormholeEntity::estimatedArrivalTime()
{
	return estimated_arrival_time;
}

double WormholeEntity::travelTime()
{
	return travel_time;
}

double WormholeEntity::scanTime()
{
	return scan_time;
}

bool WormholeEntity::isScanned()
{
	return scan_info > WH_SCANINFO_NONE;
}

void WormholeEntity::setScannedAt(double p_scanTime)
{
	if( scan_info == WH_SCANINFO_NONE )
	{
		scan_time = p_scanTime;
		scan_info = WH_SCANINFO_SCANNED;
	}
	// else we previously scanned this wormhole
}

WORMHOLE_SCANINFO WormholeEntity::scanInfo()
{
	return scan_info;
}

void WormholeEntity::setScanInfo(WORMHOLE_SCANINFO p_scanInfo)
{
	scan_info = p_scanInfo;
}

oo::PList WormholeEntity::getShipsInTransit()
{
	oo::PList::Array result;
	result.reserve(shipsInTransit.size());
	for (const OOWormholeTransit &transit : shipsInTransit)
	{
		oo::PList::Dict entry{
			{ "ship", oo::EntityObjectNode(transit.ship.get()) },
			{ "time", oo::PList(transit.time) } };
		if (transit.beacon)  entry["shipBeacon"] = oo::PList(*transit.beacon);
		result.push_back(oo::PList(std::move(entry)));
	}
	return oo::PList(std::move(result));
}

std::optional<std::string> WormholeEntity::descriptionComponents() const
{
	double now = (PLAYER != nullptr ? PLAYER->clockTime() : 0.0);
	return oo::str::format("destination: %s ttl: %.2fs arrival: %s",
		_misjump ? "Interstellar Space" : (UNIVERSE != nullptr ? UNIVERSE->getSystemName(destination) : std::optional<std::string>()).value_or("(null)").c_str(),
		expiry_time - now,
		cxx_ClockToString(arrival_time, false).c_str());
}


std::optional<std::string> WormholeEntity::identFromShip(::ShipEntity *ship)
{
	if ((ship != nullptr ? ship->hasEquipmentItem(oo::PList("EQ_WORMHOLE_SCANNER")) : false))
	{
		if (scanInfo() >= WH_SCANINFO_DESTINATION)
		{
			return oo::str::formatRuntime(OO_DESC("wormhole-to-@"), { (UNIVERSE != nullptr ? UNIVERSE->getSystemName(destination) : std::optional<std::string>()).value_or("(null)") });
		}
		else
		{
			return OO_DESC("wormhole-desc");
		}
	}
	else
	{
		OO_LOG_ERR(cxx_kOOLogInconsistentState, "{}", "Wormhole identified when ship has no EQ_WORMHOLE_SCANNER.");
		/*
			This was previously an assertion, but a player reported hitting it.
			http://aegidian.org/bb/viewtopic.php?p=128110#p128110
			-- Ahruman 2011-01-27
		*/
		return std::nullopt;
	}

}


bool WormholeEntity::canCollide()
{
	/* Correct test for far end of wormhole */
	if (origin != (UNIVERSE != nullptr ? UNIVERSE->currentSystemID() : 0))
	{
		// if we're no longer in the origin system, can't suck in
		return NO;
	}
	if ((PLAYER != nullptr ? PLAYER->getGalaxy_coordinates() : NSPoint{}).x != originCoords.x || (PLAYER != nullptr ? PLAYER->getGalaxy_coordinates() : NSPoint{}).y != originCoords.y)
	{
		// if we're no longer at the origin coordinates, can't suck in (handles interstellar space case)
		return NO;
	}

	return (witch_mass > 0.0);
}


// The other entity's -isEffect, as the particle system asks it (bead oo-9ht.39.20): [nil isEffect] answered NO.
bool WormholeEntity::checkCloseCollisionWith(Entity *otherEntity)
{
	return otherEntity == nullptr || !otherEntity->isEffect();
}


void WormholeEntity::update(OOTimeDelta delta_t)
{
	Entity::update(delta_t);
	
	::PlayerEntity	*player = PLAYER;
	assert(player != nil);
	rotMatrix = OOMatrixForBillboard(position, (player != nullptr ? player->viewpointPosition() : HPVector{}));
	double now = (player != nullptr ? player->clockTimeAdjusted() : 0.0);
	
	if (witch_mass > 0.0)
	{

		witch_mass -= WORMHOLE_SHRINK_RATE * delta_t * shrink_factor;
		witch_mass = fmax(witch_mass, 0.0);
		collision_radius = 0.5 * M_PI * pow(witch_mass, 1.0/3.0);
		no_draw_distance = collision_radius * collision_radius * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR;
	}

	scanClass = (witch_mass > 0.0)? CLASS_WORMHOLE : CLASS_NO_DRAW;
	
	if (now > expiry_time)
	{
		scanClass = CLASS_NO_DRAW; // witch_mass not certain to be limiting factor on extremely short jumps, so make sure now

		// If we're a saved wormhole waiting to disgorge more ships, it's safe
		// to remove self from UNIVERSE, but we need the current position!
		if (UNIVERSE != nullptr)  UNIVERSE->removeEntity(this);
	}
}


void WormholeEntity::drawImmediate(bool /*immediate*/, bool translucent)
{
	if ((UNIVERSE != nullptr ? UNIVERSE->breakPatternHide() : false))
		return;		// DON'T DRAW DURING BREAK PATTERN
	
	if (cam_zero_distance > no_draw_distance)
		return;	// TOO FAR AWAY TO SEE
		
	if (witch_mass <= 0.0)
		return;
	
	if (collision_radius <= 0.0)
		return;
	
	if (getScanClass() == CLASS_NO_DRAW)
		return;
	
	if (translucent)
	{
		// for now, a simple copy of the energy bomb draw routine
		float srzd = sqrt(cam_zero_distance);
		
		GLfloat	color_fv[4] = OO_WORMHOLE_COLOR_FVEC4;
		
		OOSetOpenGLState(OPENGL_STATE_TRANSLUCENT_PASS);
		OOGL(glDisable(GL_CULL_FACE));
		OOGL(glEnable(GL_BLEND));
		
		OOGL(glColor4fv(color_fv));
		OOGLBEGIN(GL_TRIANGLE_FAN);
			GLDrawBallBillboard(0.45 * collision_radius, 4, srzd);
		OOGLEND();
				
		color_fv[3] = fmin(color_fv[3] * 2.0, 1.0);
		DrawWormholeCorona(0.45 * collision_radius, collision_radius, 4, srzd, color_fv);
					
		OOGL(glEnable(GL_CULL_FACE));
		OOGL(glDisable(GL_BLEND));
	}
	
	OOVerifyOpenGLState();
	cxx_OOCheckOpenGLErrors([&]() -> std::string { return "WormholeEntity after drawing " + oo::EntityDescription(this); });
}




static void DrawWormholeCorona(GLfloat inner_radius, GLfloat outer_radius, int step, GLfloat z_distance, GLfloat *col4v1)
{
	if (outer_radius >= z_distance) // inside the sphere
		return;
	int i;

	const GLfloat activityMin = 0.34f;
	const GLfloat activityLength = 1.0f;

	GLfloat				s0, c0, s1, c1;
	
	GLfloat				r0, r1;
	GLfloat				rv0, rv1, q;
	
	GLfloat				theta, delta, halfStep;
	
	r0 = outer_radius * z_distance / sqrt(z_distance * z_distance - outer_radius * outer_radius); 
	r1 = inner_radius * z_distance / sqrt(z_distance * z_distance - inner_radius * inner_radius); 
	
	delta = step * M_PI / 180.0f;
	halfStep = 0.5f * delta;
	theta = 0.0f;
		
	OOGLBEGIN(GL_TRIANGLE_STRIP);
		for (i = 0; i < 360; i += step )
		{
			rv0 = randf();
			rv1 = randf();
			
			q = activityMin + rv0 * activityLength;
			
			s0 = r0 * sin(theta);
			c0 = r0 * cos(theta);
			glColor4f(col4v1[0] * q, col4v1[1] * q, col4v1[2] * q, col4v1[3] * rv0);
			glVertex3f(s0, c0, 0.0);

			s1 = r1 * sin(theta - halfStep) * 0.5 * (1.0 + rv1);
			c1 = r1 * cos(theta - halfStep) * 0.5 * (1.0 + rv1);
			glColor4f(col4v1[0] * OO_WORMHOLE_COLOR_BOOST, col4v1[1] * OO_WORMHOLE_COLOR_BOOST, col4v1[2] * OO_WORMHOLE_COLOR_BOOST, col4v1[3] * rv0);
			glVertex3f(s1, c1, 0.0);
			
			theta += delta;
		}
		// repeat last values to close
		rv0 = randf();
		rv1 = randf();
			
		q = activityMin + rv0 * activityLength;
		
		s0 = 0.0f;	// r0 * sin(0);
		c0 = r0;	// r0 * cos(0);
		glColor4f(col4v1[0] * q, col4v1[1] * q, col4v1[2] * q, col4v1[3] * rv0);
		glVertex3f(s0, c0, 0.0);

		s1 = r1 * sin(halfStep) * 0.5 * (1.0 + rv1);
		c1 = r1 * cos(halfStep) * 0.5 * (1.0 + rv1);
		glColor4f(col4v1[0] * OO_WORMHOLE_COLOR_BOOST, col4v1[1] * OO_WORMHOLE_COLOR_BOOST, col4v1[2] * OO_WORMHOLE_COLOR_BOOST, col4v1[3] * rv0);
		glVertex3f(s1, c1, 0.0);
	OOGLEND();
}


oo::PList WormholeEntity::getDict()
{
	oo::PList::Dict myDict;

	// -oo_setInteger: stored a signed integer, -oo_setFloat: a double, -oo_setBool: a boolean
	myDict["origin_id"] = oo::PList::signedInteger(origin);
	myDict["dest_id"] = oo::PList::signedInteger(destination);
	myDict["origin_coords"] = oo::PList(cxx_StringFromPoint(originCoords));
	myDict["dest_coords"] = oo::PList(cxx_StringFromPoint(destinationCoords));
	// Anything converting a wormhole to a dictionary should already have 
	// modified its time to shipClock time
	myDict["expiry_time"] = oo::PList(expiry_time);
	myDict["arrival_time"] = oo::PList(arrival_time);
	myDict["estimated_arrival_time"] = oo::PList(estimated_arrival_time);
	myDict["position"] = OOPListFromHPVector(position);	// -oo_setHPVector:
	myDict["misjump"] = oo::PList(static_cast<bool>(_misjump));
	
	oo::PList::Array shipArray;
	shipArray.reserve(shipsInTransit.size());
	OOShipSaveContext context;
	for (const OOWormholeTransit &transit : shipsInTransit)
	{
		// +dictionaryWithObjectsAndKeys: stopped at a nil ship_info
		oo::PList::Dict shipDict{ { "time_delta", oo::PList(transit.time) } };
		oo::PList shipInfo = (oo::ToShip(transit.ship.get()) != nullptr ? oo::ToShip(transit.ship.get())->savedShipDictionaryWithContext(&context) : oo::PList());
		if (!shipInfo.isNull())  shipDict["ship_info"] = std::move(shipInfo);
		shipArray.push_back(oo::PList(std::move(shipDict)));
	}
	myDict["ships"] = oo::PList(std::move(shipArray));

	return oo::PList(std::move(myDict));
}

const char *WormholeEntity::scanInfoString()
{
	switch(scan_info)
	{
		case WH_SCANINFO_NONE: return "WH_SCANINFO_NONE";
		case WH_SCANINFO_SCANNED: return "WH_SCANINFO_SCANNED";
		case WH_SCANINFO_COLLAPSE_TIME: return "WH_SCANINFO_COLLAPSE_TIME";
		case WH_SCANINFO_ARRIVAL_TIME: return "WH_SCANINFO_ARRIVAL_TIME";
		case WH_SCANINFO_DESTINATION: return "WH_SCANINFO_DESTINATION";
		case WH_SCANINFO_SHIP: return "WH_SCANINFO_SHIP";
	}
	return "WH_SCANINFO_UNDEFINED"; // should never get here
}

void WormholeEntity::dumpSelfState()
{
	Entity::dumpSelfState();
	OO_LOG("dumpState.wormholeEntity", "Origin                 : {}", (UNIVERSE != nullptr ? UNIVERSE->getSystemName(origin) : std::optional<std::string>()).value_or("(null)"));
	OO_LOG("dumpState.wormholeEntity", "Destination            : {}", (UNIVERSE != nullptr ? UNIVERSE->getSystemName(destination) : std::optional<std::string>()).value_or("(null)"));
	OO_LOG("dumpState.wormholeEntity", "Expiry Time            : {}", cxx_ClockToString(expiry_time, false));
	OO_LOG("dumpState.wormholeEntity", "Arrival Time           : {}", cxx_ClockToString(arrival_time, false));
	OO_LOG("dumpState.wormholeEntity", "Projected Arrival Time : {}", cxx_ClockToString(estimated_arrival_time, false));
	OO_LOG("dumpState.wormholeEntity", "Scanned Time           : {}", cxx_ClockToString(scan_time, false));
	OO_LOG("dumpState.wormholeEntity", "Scanned State          : {}", scanInfoString());

	OO_LOG("dumpState.wormholeEntity", "Mass                   : {:.2f}", witch_mass);
	OO_LOG("dumpState.wormholeEntity", "Ships                  : {}", shipsInTransit.size());
	unsigned i;
	for (i = 0; i < shipsInTransit.size(); ++i)
	{
		::ShipEntity* ship = oo::ToShip(shipsInTransit[i].ship.get());
		double	ship_arrival_time = arrival_time + shipsInTransit[i].time;
		OO_LOG("dumpState.wormholeEntity.ships", "Ship {}: {}  mass {:.2f}  arrival time {}", i+1, oo::EntityDescription(ship), (ship != nullptr ? ship->getMass() : 0.0f), cxx_ClockToString(ship_arrival_time, false));
	}
}


// The binding's bodies (OOJSWormhole.mm), which the facade forwarded to until bead oo-9ht.112.
void WormholeEntity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)
{
	::OOJSWormholeGetJSClass(outClass, outPrototype);
}


std::optional<std::string> WormholeEntity::jsClassName()
{
	return ::OOJSWormholeJSClassName();
}


bool WormholeEntity::isVisibleToScripts()
{
	return ::OOJSWormholeIsVisibleToScripts();
}


oo::PList WormholeEntityShipsInTransit(Entity *entity)
{
	WormholeEntity *wormhole = dynamic_cast<WormholeEntity *>(entity);	// the C++ entity (bead oo-w9pi2; was its object)
	return (wormhole != nullptr) ? wormhole->getShipsInTransit() : oo::PList();
}
