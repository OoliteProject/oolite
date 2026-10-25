/*
 
 ShipEntityAI.mm
 
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

#include "ShipEntityAI.h"
#include "OOMaths.h"
#include "Universe.h"
#include "AI.h"

#include "StationEntity.h"
#include "OOSunEntity.h"
#include "OOPlanetEntity.h"
#include "WormholeEntity.h"
#include "PlayerEntity.h"
#include "PlayerEntityLegacyScriptEngine.h"
#include "OOJavaScriptEngine.h"
#include "OOJSFunction.h"
#include "OOJSScript.h"
#include "EntityOOJavaScriptExtensions.h"	// OOJSEntityJSValue (bead oo-9ht.39.16)
#include "OOShipGroup.h"

#include "OOStringExpander.h"
#include "OOStringParsing.h"
#include "OOEntityFilterPredicate.h"
#include "OOConstToString.h"
#include "OOConstToJSString.h"
#include "ResourceManager.h"
#include "GameController.h"
#include "OOCallByName.h"	// oo::ScheduleEntityCall

#include "ooscript/JSEngine.hpp"
#include "oofnd/Log.hpp"
#include "OOPListGameTypes.h"
#include "oofnd/String.hpp"
#include "oofnd/Log.hpp"
#include "OOObjCPList.h"


namespace
{

// Whitespace without newlines: whiteSpaceAndNewline without U+000A-U+000D, U+0085, U+2028, U+2029
// (matches GNUstep's whitespaceCharacterSet table).
bool IsWhitespace(char16_t c)
{
	return oo::str::isWhitespaceOrNewline(c) && !((c >= 0x000A && c <= 0x000D) || c == 0x0085 || c == 0x2028 || c == 0x2029);
}


// A debug context "<description> suffix" in debug builds, nil (nullopt) otherwise.
std::optional<std::string> DebugContext(Entity *entity, const char *suffix)	// the entity's object's short description (bead oo-9ht.39.16)
{
#ifndef NDEBUG
	return oo::str::format("%s %s", oo::EntityShortDescription(entity).c_str(), suffix);
#else
	(void)entity;
	(void)suffix;
	return std::nullopt;
#endif
}


// [[s componentsSeparatedByString:@":"] objectAtIndex:1] -intValue, for a "rand:N" coordinate.
int RandArgument(const std::string &token)
{
	const std::vector<std::string> parts = oo::str::split(token, ":");
	return parts.size() > 1 ? oo::str::intValue(parts[1]) : 0;
}

}	// namespace

/*
	Retargeted onto the ooscript façade (JSEngine.hpp) the way OOJSVector.mm does it (bead
	oo-sdz, the sweep exemplar): this file's one remaining direct engine call, the pending-
	exception report at the end of -scanForNearestShipMatchingPredicate:, becomes the façade's
	own reportPendingException entry point. SpiderMonkey still does the work underneath; only
	the call target changes.
*/
namespace ooscript { }
using ooscript::Context;

// Byte-identical façade <-> jsapi view, local to this call site (see OOJSVector.mm).


// Slice 1 of docs/phases/3-slices/ShipEntityAI.md (bead oo-iebuz): AI category, OOAIPrivate (ship
// and station) and the station stubs. Members of ShipEntity defined in the category's file
// (ADR-0056 amendment oo-o89 item 4); called directly since bead oo-9ht.144 deleted the facade
// (amendment oo-9ht.144).

void ShipEntity::setAITo(const std::string &aiString)	// called by name (ADR-0055 item 5)
{
	std::string ai = aiString;
	// don't try to load real AIs if the game hasn't started yet
	if (!(PLAYER != nullptr ? PLAYER->scriptsLoaded() : false))
	{
		ai = "oolite-nullAI.js";
	}
	if (oo::str::hasSuffix(ai, ".plist"))
	{
		if (getAI() != nullptr)  getAI()->setStateMachine(ai, "oolite-nullAI.js");
		setAIScript("oolite-nullAI.js");
	}
	else if (oo::str::hasSuffix(ai, ".js"))
	{
		if (getAI() != nullptr)  getAI()->setStateMachine("nullAI.plist", ai);
		setAIScript(ai);
	}
	else
	{
		const std::optional<std::string> path = ResourceManager::pathForFileNamed(ai + ".js", std::string("AIs"));
		if (!path) // no js, use plist
		{
			setAITo(ai + ".plist");
		}
		else
		{
			setAITo(ai + ".js");
		}
	}
}


void ShipEntity::setAIScript(const std::string &aiString)
{
	const oo::PList properties(oo::PList::Dict{ { "ship", oo::EntityObjectNode(this) } });
	
	OOScriptAutorelease(std::move(aiScript));	// [aiScript autorelease]
	aiScript = OOScript::jsAIScriptFromFileNamed(aiString, properties);
	if (aiScript == nullptr)
	{
		OO_LOG("ai.load.failed.unknownAI", "Unable to load JS AI {} for ship {} ({} for role {})", aiString, oo::EntityDescription(this), shipDataKey().value_or("(null)"), getPrimaryRole().value_or("(null)"));
		aiScript = OOScript::jsAIScriptFromFileNamed("oolite-nullAI.js", properties);
	}
	else
	{
		aiScriptWakeTime = 0;
		haveStartedJSAI = NO;
	}
}


void ShipEntity::switchAITo(const std::string &aiString)	// called by name (ADR-0055 item 5)
{
	setAITo(aiString);
	if (getAI() != nullptr)  getAI()->clearStack();
}


void ShipEntity::scanForHostiles()
{
	/*-- Locates all the ships in range targeting the receiver and chooses the nearest --*/
	_foundTarget = nullptr;
	
	checkScanner();
	unsigned i;
	GLfloat found_d2 = scannerRange * scannerRange;
	for (i = 0; i < n_scanned_ships ; i++)
	{
		::ShipEntity *thing = scanned_ships[i];
		GLfloat d2 = distance2_scanned_ships[i];
		if ((d2 < found_d2) 
			&& ((thing != nullptr ? thing->isThargoid() : false) || (((thing != nullptr ? thing->primaryTarget() : (Entity *)nullptr) == this) && (thing != nullptr ? thing->hasHostileTarget() : false)) || (thing != nullptr ? thing->isDefenseTarget(this) : false))
			&& !(thing != nullptr ? thing->isCloaked() : false))
		{
			setFoundTarget(thing);
			found_d2 = d2;
		}
	}
	
	checkFoundTarget();
}


void ShipEntity::groupAttackTarget()
{
	::ShipEntity			*target = nil, *ship = nil;

	target = oo::ToShip(primaryTarget());
	
	if (target == nil) return;
	
	if (group() == nil)		// ship is alone!
	{
		setFoundTarget(target);
		if (shipAI != nullptr)  shipAI->reactToMessage("GROUP_ATTACK_TARGET", "groupAttackTarget");
		doScriptEvent(OOJSID("helpRequestReceived"), this, target);
		return;
	}
	
	for (const oo::EntityHold &member : (group() != nullptr ? group()->memberArray() : std::vector<oo::EntityHold>()))
	{
		ship = oo::ToShip(member.get());
		if (ship != nullptr)  ship->setFoundTarget(target);
		if (ship != nullptr)  ship->reactToAIMessage("GROUP_ATTACK_TARGET", "groupAttackTarget");
		if (ship != nullptr)  ship->doScriptEvent(OOJSID("helpRequestReceived"), this, target);

		if ((ship != nullptr ? ship->escortGroup() : (OOShipGroup *)nullptr) != (ship != nullptr ? ship->group() : (OOShipGroup *)nullptr) && ((ship != nullptr ? ship->escortGroup() : (OOShipGroup *)nullptr) != nullptr ? (ship != nullptr ? ship->escortGroup() : (OOShipGroup *)nullptr)->count() : 0) > 1) // Ship has a seperate escort group.
		{
			for (const oo::EntityHold &escortRef : ((ship != nullptr ? ship->escortGroup() : (OOShipGroup *)nullptr) != nullptr ? (ship != nullptr ? ship->escortGroup() : (OOShipGroup *)nullptr)->memberArrayExcludingLeader() : std::vector<oo::EntityHold>()))
			{
				::ShipEntity		*escort = oo::ToShip(escortRef.get());
				if (escort != nullptr)  escort->setFoundTarget(target);
				if (escort != nullptr)  escort->reactToAIMessage("GROUP_ATTACK_TARGET", "groupAttackTarget");
				if (escort != nullptr)  escort->doScriptEvent(OOJSID("helpRequestReceived"), this, target);
			}
		}
	}
}


void ShipEntity::performAttack()
{
	if (behaviour != BEHAVIOUR_EVASIVE_ACTION)
	{
		behaviour = BEHAVIOUR_ATTACK_TARGET;
		desired_range = 1250 * randf() + 750; // 750 til 2000
		frustration = 0.0;	
	}
}


void ShipEntity::performCollect()
{
	behaviour = BEHAVIOUR_COLLECT_TARGET;
	frustration = 0.0;
}


void ShipEntity::performEscort()
{
	if(behaviour != BEHAVIOUR_FORMATION_FORM_UP) 
	{
		behaviour = BEHAVIOUR_FORMATION_FORM_UP;
		frustration = 0.0; // behavior changed, reset frustration.
	}
}


void ShipEntity::performFaceDestination()
{
	behaviour = BEHAVIOUR_FACE_DESTINATION;
	frustration = 0.0;
}


void ShipEntity::performFlee()
{
	if (behaviour != BEHAVIOUR_FLEE_EVASIVE_ACTION)
	{
		behaviour = BEHAVIOUR_FLEE_TARGET;
		setEvasiveJink(400.0);
		frustration = 0.0;
		if (accuracy > COMBAT_AI_ISNT_AWFUL)
		{
			// alert! they've got us in their sights! react!!
			if (approachAspectToPrimaryTarget() > 0.9995)
			{
				behaviour = randf() < 0.15 ? BEHAVIOUR_EVASIVE_ACTION : BEHAVIOUR_FLEE_EVASIVE_ACTION;
			}
		}
	}
}


void ShipEntity::performFlyToRangeFromDestination()
{
	behaviour = BEHAVIOUR_FLY_RANGE_FROM_DESTINATION;
	frustration = 0.0;
}


void ShipEntity::performHold()
{
	desired_speed = 0.0;
	behaviour = BEHAVIOUR_TRACK_TARGET;
	frustration = 0.0;
}


void ShipEntity::performIdle()
{
	behaviour = BEHAVIOUR_IDLE;
	frustration = 0.0;
}


void ShipEntity::performIntercept()
{
	behaviour = BEHAVIOUR_INTERCEPT_TARGET;
	frustration = 0.0;
}


void ShipEntity::performLandOnPlanet()
{
	::OOPlanetEntity	*nearest = findNearestPlanet();
	if (isNearPlanetSurface)
	{
		_destination = (nearest != nullptr ? nearest->getPosition() : HPVector{});
		behaviour = BEHAVIOUR_LAND_ON_PLANET;
		planetForLanding = (nearest != nullptr ? nearest->getUniversalID() : OOUniversalID{});
	}
	else
	{
		behaviour = BEHAVIOUR_IDLE;
		if (shipAI != nullptr)  shipAI->message("NO_PLANET_NEARBY");
	}
	
	frustration = 0.0;
}


void ShipEntity::performMining()
{
	Entity *target = primaryTarget();
	// mining is not seen as hostile behaviour, so ensure it is only used against rocks.
	if (target &&  (target != nullptr ? target->getScanClass() : OOScanClass{}) == CLASS_ROCK)
	{
		behaviour = BEHAVIOUR_ATTACK_MINING_TARGET;
		frustration = 0.0;
	}
	else
	{	
		noteLostTargetAndGoIdle();
	}
}


void ShipEntity::performScriptedAI()
{
	behaviour = BEHAVIOUR_SCRIPTED_AI;
	frustration = 0.0;
}


void ShipEntity::performScriptedAttackAI()
{
	behaviour = BEHAVIOUR_SCRIPTED_ATTACK_AI;
	frustration = 0.0;
}


void ShipEntity::performBuoyTumble()
{
	stick_roll = 0.10;
	stick_pitch = 0.15;
	behaviour = BEHAVIOUR_TUMBLE;
	frustration = 0.0;
}


void ShipEntity::performStop()
{
	behaviour = BEHAVIOUR_STOP_STILL;
	desired_speed = 0.0;
	frustration = 0.0;
}


void ShipEntity::performTumble()
{
	stick_roll = max_flight_roll*2.0*(randf() - 0.5);
	stick_pitch = max_flight_pitch*2.0*(randf() - 0.5);
	behaviour = BEHAVIOUR_TUMBLE;
	frustration = 0.0;
}


bool ShipEntity::performHyperSpaceToSpecificSystem(OOSystemID systemID)
{
	return performHyperSpaceExitReplace(NO, systemID);
}


void ShipEntity::requestDockingCoordinates()
{
	/*-	requests coordinates from the target station
	 if the target station can't be found
	 then use the nearest it can find (which may be a rock hermit) -*/
	
	::StationEntity	*station =  nil;
	Entity			*targStation = nullptr;
	double		distanceToStation2 = 0.0;
	
	targStation = targetStation();
	if (targStation != nullptr && targStation->getIsStation())
	{
		station = oo::ToStation(targStation);
	}
	else
	{
		station = oo::ToStation((UNIVERSE != nullptr ? UNIVERSE->nearestShipMatchingPredicate(IsStationPredicate, nullptr, this) : nullptr));
	}
	
	distanceToStation2 = HPdistance2((station != nullptr ? station->getPosition() : HPVector{}), getPosition());
	
	// Player check for being inside the aegis already exists in PlayerEntityControls. We just
	// check here that distance to station is less than 2.5 times scanner range to avoid problems with
	// NPC ships getting stuck with a dockingAI while just outside the aegis - Nikos 20090630, as proposed by Eric
	// On very busy systems (> 50 docking ships) docking ships can be sent to a hold position outside the range, 
	// so also test for presence of dockingInstructions. - Eric 20091130
	if (station != nil && (distanceToStation2 < SCANNER_MAX_RANGE2 * 6.25 || !dockingInstructions.isNull()))
	{
		// remember the instructions (the station's weak reference is kept as an Object node)
		dockingInstructions = (station != nullptr ? station->dockingInstructionsForShip(this) : oo::PList());
		if (!dockingInstructions.isNull())
		{
			recallDockingInstructions();
			
			// the strings the instructions hold (StationEntity -dockingInstructionsForShip:), sent as before (absent: nothing)
			const oo::PList *aiMessage = dockingInstructions.find("ai_message");
			if (aiMessage != nullptr && aiMessage->isString())  { if (shipAI != nullptr)  shipAI->message(*aiMessage->getIf<std::string>()); }
			const oo::PList *commsMessage = dockingInstructions.find("comms_message");
			if (commsMessage != nullptr && commsMessage->isString())  { if (station != nullptr)  station->sendExpandedMessage(*commsMessage->getIf<std::string>(), this); }
		}
	}
	else
	{
		dockingInstructions = oo::PList();
	}
	
	if (dockingInstructions.isNull())
	{
		if (shipAI != nullptr)  shipAI->message("NO_STATION_FOUND");
	}
}


void ShipEntity::recallDockingInstructions()
{
	if (!dockingInstructions.isNull())
	{
		const oo::PList *destination = dockingInstructions.find("destination");
		_destination = OOHPVectorFromPList(destination, kZeroHPVector);
		desired_speed = fmin(dockingInstructions.get<float>("speed"), maxFlightSpeed);
		desired_range = dockingInstructions.get<float>("range");
		if (const oo::PList *stationRef = dockingInstructions.find("station"))
		{
			::StationEntity *targetStation = oo::ToStation(oo::EntityInWeakNode(*stationRef));
			if (targetStation != nil)
			{
				addTarget(targetStation);
				setTargetStation(targetStation);
			}
			else 
			{
				removeTarget(primaryTarget());
			}
		}
		docking_match_rotation = dockingInstructions.get<bool>("match_rotation");
	}
}


void ShipEntity::scanForNearestIncomingMissile()
{
	OOScanClass missileClass = CLASS_MISSILE;
	BinaryOperationPredicateParameter param =
	{
		HasScanClassPredicate, &missileClass,	// the predicate reads an OOScanClass
		IsHostileAgainstTargetPredicate, this
	};
	scanForNearestShipWithPredicate(ANDPredicate, &param);
}


void ShipEntity::enterPlayerWormhole()
{
	enterWormhole((PLAYER != nullptr ? PLAYER->getWormhole() : (WormholeEntity *)nullptr), NO);
}


void ShipEntity::enterTargetWormhole()
{
	WormholeEntity *whole = nullptr;	// C++ since bead oo-9ht.112
	Entity		*targEnt = primaryTarget();	// any entity: a wormhole is the one sought (the ship's object was typed ShipEntity until bead oo-9ht.144)
	double found_d2 = scannerRange * scannerRange;
	
	if (targEnt && (HPdistance2(position, targEnt->getPosition()) < found_d2))
	{
		if (targEnt->getIsWormhole())
			whole = static_cast<WormholeEntity *>(targEnt);
		else if (targEnt->getIsPlayer())
			whole = (PLAYER != nullptr ? PLAYER->getWormhole() : (WormholeEntity *)nullptr);
	}

	if (!whole)
	{
		// locate nearest wormhole
		int				ent_count =		UNIVERSE->n_entities;
		Entity**		uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
		std::vector<oo::Ref<Entity>>	wormholes(ent_count);	// kept for the loop, as the objects were retained (bead oo-9ht.39.16)
		int i;
		int wh_count = 0;
		for (i = 0; i < ent_count; i++)
			if (uni_entities[i]->isWormhole)
				wormholes[wh_count++] = oo::Ref<Entity>(uni_entities[i]);
		//
		//double found_d2 = scannerRange * scannerRange;
		for (i = 0; i < wh_count ; i++)
		{
			Entity *wh = wormholes[i].get();
			double d2 = HPdistance2(position, wh->position);
			if (d2 < found_d2)
			{
				whole = static_cast<WormholeEntity *>(wh);
				found_d2 = d2;
			}
			wormholes[i] = nullptr;
		}
	}
	
	enterWormhole(whole, NO);
}


// FIXME: resolve this stuff.
void ShipEntity::wormholeEscorts()
{
	::ShipEntity			*ship = nil;
	Entity			*whole = nullptr;	// the wormhole (bead oo-9ht.39.16)
	
	whole = primaryTarget();
	if (!(whole != nullptr && whole->getIsWormhole()))  return;
	
	const std::optional<std::string> context = DebugContext(this, "wormholeEscorts");
	
	for (const auto &shipRef : escorts())
	{
		ship = oo::ToShip(shipRef.get());
		if (ship != nullptr)  ship->addTarget(whole);
		if (ship != nullptr)  ship->reactToAIMessage("ENTER WORMHOLE", context);
		if (ship != nullptr)  ship->doScriptEvent(OOJSID("wormholeSuggested"), whole);
	}
	
	// We now have no escorts..

	_escortGroup = nullptr;

}


void ShipEntity::wormholeEntireGroup()
{
	wormholeGroup();
	wormholeEscorts();
}


bool ShipEntity::suggestEscortTo(::ShipEntity *mother)
{
	if (mother)
	{
#ifndef NDEBUG
		if (reportAIMessages)
		{
			OO_LOG("ai.suggestEscort", "DEBUG: {} suggests escorting {}", oo::EntityDescription(this), oo::EntityDescription(mother));
		}
#endif
		
		if ((mother != nullptr ? mother->acceptAsEscort(this) : false))
		{
			// copy legal status across
			if (((mother != nullptr ? mother->legalStatus() : int{}) > 0)&&(bounty <= 0))
			{
				int extra = 1 | (ranrot_rand() & 15);
//				[mother setBounty: [mother legalStatus] + extra withReason:kOOLegalStatusReasonAssistingOffender];
				markAsOffender(extra, kOOLegalStatusReasonAssistingOffender);
				//				bounty += extra;	// obviously we're dodgier than we thought!
			}
			
			setOwner(mother);
			setGroup((mother != nullptr ? mother->escortGroup() : (OOShipGroup *)nullptr));
			if (shipAI != nullptr)  shipAI->message("ESCORTING");
			return YES;
		}
		
#ifndef NDEBUG
		if (reportAIMessages)
		{
			OO_LOG("ai.suggestEscort.refused", "DEBUG: {} refused by {}", oo::EntityDescription(this), oo::EntityDescription(mother));
		}
#endif
		
	}
	setOwner(this);
	if (shipAI != nullptr)  shipAI->message("NOT_ESCORTING");
	doScriptEvent(OOJSID("escortRejected"), mother);
	return NO;
}


void ShipEntity::broadcastDistressMessage()
{
	/*-- Locates all the stations, bounty hunters and police ships in range and tells them that you are under attack --*/
	broadcastDistressMessageWithDumping(YES);
}


void ShipEntity::broadcastDistressMessageWithDumping(bool dumpCargo)
{
	checkScannerIgnoringUnpowered();
	_foundTarget = nullptr;
	
	::ShipEntity	*aggressor_ship = oo::ToShip(primaryAggressor());
	if (aggressor_ship == nil)  return;
	
	// don't send too many distress messages at once, space them out semi-randomly
	if (messageTime > 2.0 * randf())  return;
	
	BOOL		is_buoy = (scanClass == CLASS_BUOY);
	const char	*distress_message = is_buoy ? "[buoy-distress-call]" : "[distress-call]";
	
	unsigned i;
	for (i = 0; i < n_scanned_ships; i++)
	{
		::ShipEntity*	ship = scanned_ships[i];

    // dump cargo if energy is low
		if (dumpCargo && !is_buoy && primaryAggressor() == ship && energy < 0.375 * maxEnergy)
		{
			ejectCargo();
			performFlee();
		}
		
		// tell it! (only plist AIs send comms here; JS AIs are
		// expected to handle their own)
		if (ship->isPlayer && !hasNewAI())
		{
			if (ship != nullptr)  ship->doScriptEvent(OOJSID("distressMessageReceived"), aggressor_ship, this);

			if (!is_buoy && primaryAggressor() == ship && energy < 0.375 * maxEnergy)
			{
				sendExpandedMessage("[beg-for-mercy]", ship);
			}
			else if (getBounty() == 0)
			{
				// only send distress message to player if plausibly sending
				// one more generally
				sendExpandedMessage(distress_message, ship);
			}
			
			// reset the thanked_ship_id
			_thankedShip = nullptr;
		}
		else if (getBounty() == 0 && (ship != nullptr ? ship->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>()).has_value()) // Only clean ships can have their distress calls accepted
		{
			if (ship != nullptr)  ship->doScriptEvent(OOJSID("distressMessageReceived"), aggressor_ship, this);
			
			// we only can send distressMessages to ships that are known to have a "ACCEPT_DISTRESS_CALL" reaction
			// in their AI, or they might react wrong on the added found_target.

			// ship must have a plist AI for this next bit. JS AIs
			// should already have done something sensible on
			// distressMessageReceived
			if (!hasNewAI())
			{
				// FIXME: this test only works with core AIs
				if (ship->isStation || (ship != nullptr ? ship->hasPrimaryRole("police") : false) || (ship != nullptr ? ship->hasPrimaryRole("hunter") : false))
				{
					if (ship != nullptr)  ship->acceptDistressMessageFrom(this);
				}
			}
		}
	}
}


void ShipEntity::checkFoundTarget()
{
	if (foundTarget() != nil) 
	{
		if (shipAI != nullptr)  shipAI->message("TARGET_FOUND");
	}
	else
	{
		if (shipAI != nullptr)  shipAI->message("NOTHING_FOUND");
	}
}


bool ShipEntity::performHyperSpaceExitReplace(bool replace)
{
	return performHyperSpaceExitReplace(replace, -1);
}


bool ShipEntity::performHyperSpaceExitReplace(bool replace, OOSystemID systemID)
{
	if(!hasHyperspaceMotor())
	{
		if (shipAI != nullptr)  shipAI->reactToMessage("WITCHSPACE UNAVAILABLE", "performHyperSpaceExit");
		return NO;
	}
	if(status() == STATUS_ENTERING_WITCHSPACE)
	{
// already in a wormhole
		return NO;
	}
	
	OOSystemID		targetSystem;
	NSUInteger		i = 0;
	
	// get a list of destinations within range
	const oo::PList sDests = (UNIVERSE != nullptr ? UNIVERSE->nearbyDestinationsWithinRange(0.1f * fuel) : oo::PList());
	NSUInteger n_dests = sDests.count();
	
	// if none available report to the AI and exit
	if (n_dests == 0)
	{
		if (shipAI != nullptr)  shipAI->reactToMessage("WITCHSPACE UNAVAILABLE", "performHyperSpaceExit");
		
		// If no systems exist near us, the AI is switched to a different state, so we do not need
		// the nearby destinations array anymore.
		return NO;
	}
	
	// check if we're clear of nearby masses
	::ShipEntity *blocker = oo::ToShip((UNIVERSE != nullptr ? UNIVERSE->entityForUniversalID(checkShipsInVicinityForWitchJumpExit()) : nullptr));
	if (blocker)
	{
		setFoundTarget(blocker);
		if (shipAI != nullptr)  shipAI->reactToMessage("WITCHSPACE BLOCKED", "performHyperSpaceExit");
		doScriptEvent(OOJSID("shipWitchspaceBlocked"), blocker);

		return NO;
	}
	
	if (systemID == -1)
	{
		// select one at random
		if (n_dests > 1)
		{
			i = ranrot_rand() % n_dests;
		}
		
		
		targetSystem = sDests.at(i)->get<int>("sysID");
	}
	else
	{
		targetSystem = systemID;
		
		for (i = 0; i < n_dests; i++)
		{
			if (systemID == sDests.at(i)->get<int>("sysID")) break;
		}
		
		if (i == n_dests)	// no match found
		{
			return NO;
		}
	}
	float dist = sDests.at(i)->get<float>("distance");
	if (dist > maxHyperspaceDistance() || dist > fuel/10.0f) 
	{
		OO_LOG_WARN("script.debug", "DEBUG: {} Jumping {:f} which is further than allowed.  I have {} fuel", oo::EntityDescription(this), dist, fuel);
	}
	fuel -= 10 * dist;
	
	// create wormhole
	// +alloc/-initWormholeTo:fromShip:/-autorelease: a new C++ wormhole and its autoreleased
	// Objective-C object (bead oo-9ht.112).
	oo::Ref<WormholeEntity> whRef = oo::makeRef<WormholeEntity>();
	Entity *wholeObject = oo::MadeEntity(whRef);	// the wormhole, given its object (bead oo-9ht.39.26)
	whRef->initWormholeTo(targetSystem, this);
	WormholeEntity  *whole = whRef.get();
	if (UNIVERSE != nullptr)  UNIVERSE->addEntity(wholeObject);
	
	enterWormhole(whole, replace);
	
	// we've no need for the destinations array anymore.
	return YES;
}


void ShipEntity::scanForNearestShipWithPredicate(EntityFilterPredicate predicate, void *parameter)
{
	// Locates all the ships in range for which predicate returns YES, and chooses the nearest.
	unsigned		i;
	::ShipEntity		*candidate;
	float			d2, found_d2 = scannerRange * scannerRange;
	
	_foundTarget = nullptr;
	checkScanner();
	
	if (predicate == NULL)  return;
	
	for (i = 0; i < n_scanned_ships ; i++)
	{
		candidate = scanned_ships[i];
		d2 = distance2_scanned_ships[i];
		if ((d2 < found_d2) && (candidate->scanClass != CLASS_CARGO) && ((candidate != nullptr ? candidate->status() : OOEntityStatus{}) != STATUS_DOCKED) 
					&& predicate(candidate, parameter) && !(candidate != nullptr ? candidate->isCloaked() : false))
		{
			setFoundTarget(candidate);
			found_d2 = d2;
		}
	}
	
	checkFoundTarget();
}


void ShipEntity::scanForNearestShipWithNegatedPredicate(EntityFilterPredicate predicate, void *parameter)
{
	ChainedEntityPredicateParameter param = { predicate, parameter };
	scanForNearestShipWithPredicate(NOTPredicate, &param);
}


void ShipEntity::acceptDistressMessageFrom(::ShipEntity *other)
{
	setFoundTarget((other != nullptr ? other->primaryTarget() : (Entity *)nullptr));
	if (isPolice())
	{
		if (oo::ToShip(foundTarget()) != nullptr)  oo::ToShip(foundTarget())->markAsOffender(8, kOOLegalStatusReasonDistressCall);  // you have been warned!!
	}
	
	if (shipAI != nullptr)  shipAI->reactToMessage("ACCEPT_DISTRESS_CALL", DebugContext(other, "broadcastDistressMessage"));
	
}




// The category ShipEntity (OOAIStationStubs): AI methods for stations, which have no effect on
// normal ships (StationEntity's own answer them for a station). They were generated by the
// STATION_STUB_* macros; as members they are written out.
namespace {

void LogNotAStation(ShipEntity *ship, const char *method)
{
	OO_LOG("ai.invalid.notAStation", "Attempt to use station AI method \"{}\" on non-station {}.", method, oo::EntityDescription(ship));
}

}	// namespace



void ShipEntity::increaseAlertLevel()	{ LogNotAStation(this, "increaseAlertLevel"); }
void ShipEntity::decreaseAlertLevel()	{ LogNotAStation(this, "decreaseAlertLevel"); }

oo::PList ShipEntity::launchPolice()	// called by name (ADR-0055 item 5): StationEntity's returns the ships launched
{
	LogNotAStation(this, "launchPolice");
	return oo::PList();
}

void ShipEntity::launchDefenseShip()	{ LogNotAStation(this, "launchDefenseShip"); }
void ShipEntity::launchScavenger()	{ LogNotAStation(this, "launchScavenger"); }
void ShipEntity::launchMiner()	{ LogNotAStation(this, "launchMiner"); }
void ShipEntity::launchPirateShip()	{ LogNotAStation(this, "launchPirateShip"); }
void ShipEntity::launchShuttle()	{ LogNotAStation(this, "launchShuttle"); }
void ShipEntity::launchTrader()	{ LogNotAStation(this, "launchTrader"); }
void ShipEntity::launchEscort()	{ LogNotAStation(this, "launchEscort"); }

bool ShipEntity::launchPatrol()
{
	LogNotAStation(this, "launchPatrol");
	return NO;
}

void ShipEntity::launchShipWithRole(const std::string & /* param */)	{ LogNotAStation(this, "launchShipWithRole:"); }	// called by name (ADR-0055 item 5)
void ShipEntity::abortAllDockings()	{ LogNotAStation(this, "abortAllDockings"); }



// The station's unit of the category StationEntity (OOAIPrivate), overriding the ship's.
void StationEntity::acceptDistressMessageFrom(::ShipEntity *other)
{
	if (this != (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr))  return;

	const oo::WeakRef<Entity> old_target = _primaryTarget;
	_primaryTarget = oo::WeakRef<Entity>(other != nullptr ? other->primaryTarget() : (Entity *)nullptr);
	if (oo::ToShip((other != nullptr ? other->primaryTarget() : (Entity *)nullptr)) != nullptr)  oo::ToShip((other != nullptr ? other->primaryTarget() : (Entity *)nullptr))->markAsOffender(8, kOOLegalStatusReasonDistressCall);	// mark their card
	launchDefenseShip();
	_primaryTarget = old_target;

}


// Slice 2 of docs/phases/3-slices/ShipEntityAI.md (bead oo-xurzn): PureAI part 1: state, speed,
// scans for prey and loot, planets, legal status. Members of ShipEntity defined in the category's
// file (ADR-0056 amendment oo-o89 item 4); called directly since bead oo-9ht.144 deleted the facade
// (amendment oo-9ht.144).

void ShipEntity::setStateTo(const std::string &state)	// called by name (ADR-0055 item 5)
{
	if (getAI() != nullptr)  getAI()->setState(state);
}


void ShipEntity::pauseAI(const std::string &intervalString)	// called by name (ADR-0055 item 5)
{
	if (shipAI != nullptr)  shipAI->setNextThinkTime((UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) + oo::str::doubleValue(intervalString));
}


void ShipEntity::randomPauseAI(const std::string &intervalString)	// called by name (ADR-0055 item 5)
{
	const std::vector<std::string>	tokens = oo::str::tokens(intervalString);
	double start, end;
	
	if (tokens.size() != 2)
	{
		OO_LOG("ai.syntax.randomPauseAI", "***** ERROR: cannot read min and max value for randomPauseAI:, needs 2 values: '{}'.", intervalString);
		return;
	}
	
	start = oo::str::doubleValue(tokens[0]);	// -oo_doubleAtIndex:
	end   = oo::str::doubleValue(tokens[1]);
	
	if (shipAI != nullptr)  shipAI->setNextThinkTime((UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) + (start + (end - start)*randf()));
}


void ShipEntity::dropMessages(const std::string &messageString)	// called by name (ADR-0055 item 5)
{
	for (const std::string &message : oo::str::split(messageString, ","))
	{
		if (shipAI != nullptr)  shipAI->dropMessage(oo::str::trimTrailing(oo::str::trimLeading(message, IsWhitespace), IsWhitespace));
	}
}


void ShipEntity::debugDumpPendingMessages()
{
	if (shipAI != nullptr)  shipAI->debugDumpPendingMessages();
}


void ShipEntity::setDestinationToCurrentLocation()
{
	// randomly add a .5m variance
	_destination = HPvector_add(position, OOHPVectorRandomSpatial(0.5));
}


void ShipEntity::setDestinationToJinkPosition()
{
	Vector front = vector_multiply_scalar(forwardVector(), flightSpeed / max_flight_pitch * 2);
	_destination = HPvector_add(position, vectorToHPVector(vector_add(front, OOVectorRandomSpatial(100))));
	pitching_over = YES; // don't complete roll first, but immediately start with pitching. 
}


void ShipEntity::setDesiredRangeTo(const std::string &rangeString)	// called by name (ADR-0055 item 5)
{
	desired_range = oo::str::doubleValue(rangeString);
}


void ShipEntity::setDesiredRangeForWaypoint()
{
	desired_range = fmax(maxFlightSpeed / max_flight_pitch / 6, 50.0); // some ships need a longer range to reach a waypoint.
}


void ShipEntity::setSpeedTo(const std::string &speedString)	// called by name (ADR-0055 item 5)
{
	desired_speed = oo::str::doubleValue(speedString);
}


void ShipEntity::setSpeedFactorTo(const std::string &speedString)	// called by name (ADR-0055 item 5)
{
	desired_speed = maxFlightSpeed * oo::str::doubleValue(speedString);
}


void ShipEntity::setSpeedToCruiseSpeed()
{
	desired_speed = cruiseSpeed;
}


void ShipEntity::setThrustFactorTo(const std::string &thrustFactorString)	// called by name (ADR-0055 item 5)
{
	thrust = OOClamp_0_1_f(oo::str::doubleValue(thrustFactorString)) * max_thrust;
}


void ShipEntity::setTargetToPrimaryAggressor()
{
	Entity *primeAggressor = primaryAggressor();
	if (!primeAggressor)
		return;
	if (primaryTarget() == primeAggressor)
		return;
	
	// a more considered approach here:
	// if we're already busy attacking a target we don't necessarily want to break off
	//
	if (hasHostileTarget() && randf() < 0.75)	// if I'm attacking, ignore 75% of new aggressor's attacks
	{
				// but add them as a secondary target anyway
		addDefenseTarget(primeAggressor);
		return;
	}
	// react only if the primary aggressor is not a friendly ship, else ignore it
	if (oo::EntityIsShip(primeAggressor) && !(oo::ToShip(primeAggressor) != nullptr ? oo::ToShip(primeAggressor)->isFriendlyTo(this) : false))
	{
		// inform our old target of our new target
		//
		Entity *primeTarget = primaryTarget();
		if ((primeTarget)&&(primeTarget->isShip))
		{
			::ShipEntity *currentShip = oo::ToShip(primaryTarget());
			if (currentShip != nullptr && currentShip->getAI() != nullptr)  currentShip->getAI()->message(oo::str::format("%s %d %d", std::string(AIMS_AGGRESSOR_SWITCHED_TARGET).c_str(), universalID, (primaryAggressor() != nullptr ? primaryAggressor()->getUniversalID() : OOUniversalID{})));
			if (currentShip != nullptr)  currentShip->doScriptEvent(OOJSID("shipAttackerDistracted"), primaryAggressor());
		}
		
		// okay, so let's now target the aggressor
		addTarget(primaryAggressor());
	}
}


void ShipEntity::addPrimaryAggressorAsDefenseTarget()
{
	Entity *primeAggressor = primaryAggressor();
	if (!primeAggressor)
		return;
	if (isDefenseTarget(primeAggressor))
		return;
	
	if (oo::EntityIsShip(primeAggressor) && !(oo::ToShip(primeAggressor) != nullptr ? oo::ToShip(primeAggressor)->isFriendlyTo(this) : false))
	{
		addDefenseTarget(primeAggressor);
	}
}


void ShipEntity::scanForNearestMerchantman()
{
	float				d2, found_d2;
	unsigned			i;
	::ShipEntity			*ship = nil;
	
	//-- Locates the nearest merchantman in range.
	checkScannerIgnoringUnpowered();
	
	found_d2 = scannerRange * scannerRange;
	_foundTarget = nullptr;
	
	for (i = 0; i < n_scanned_ships ; i++)
	{
		ship = scanned_ships[i];
		if ((ship != nullptr ? ship->isPirateVictim() : false) && ((ship != nullptr ? ship->status() : OOEntityStatus{}) != STATUS_DEAD) && ((ship != nullptr ? ship->status() : OOEntityStatus{}) != STATUS_DOCKED) && !(ship != nullptr ? ship->isCloaked() : false))
		{
			d2 = distance2_scanned_ships[i];
			if (PIRATES_PREFER_PLAYER && (d2 < desired_range * desired_range) && ship->isPlayer && isPirate())
			{
				d2 = 0.0;
			}
			else d2 = distance2_scanned_ships[i];
			if (d2 < found_d2)
			{
				found_d2 = d2;
				setFoundTarget(ship);
			}
		}
	}
	checkFoundTarget();
}


void ShipEntity::scanForRandomMerchantman()
{
	unsigned			n_found, i;
	
	//-- Locates one of the merchantman in range.
	checkScannerIgnoringUnpowered();
	std::vector<::ShipEntity *>	ids_found(n_scanned_ships);
	
	n_found = 0;
	_foundTarget = nullptr;
	for (i = 0; i < n_scanned_ships ; i++)
	{
		::ShipEntity *ship = scanned_ships[i];
		if (((ship != nullptr ? ship->status() : OOEntityStatus{}) != STATUS_DEAD) && ((ship != nullptr ? ship->status() : OOEntityStatus{}) != STATUS_DOCKED) && (ship != nullptr ? ship->isPirateVictim() : false) && !(ship != nullptr ? ship->isCloaked() : false))
			ids_found[n_found++] = ship;
	}
	if (n_found == 0)
	{
		if (shipAI != nullptr)  shipAI->message("NOTHING_FOUND");
	}
	else
	{
		i = ranrot_rand() % n_found;	// pick a number from 0 -> (n_found - 1)
		setFoundTarget(ids_found[i]);
		if (shipAI != nullptr)  shipAI->message("TARGET_FOUND");
	}
}


void ShipEntity::scanForLoot()
{
	/*-- Locates the nearest debris in range --*/
	if (!isStation)
	{
		if (!hasCargoScoop())
		{
			if (shipAI != nullptr)  shipAI->message("NOTHING_FOUND");		//can't collect loot if you have no scoop!
			return;
		}
		if (cargoCount() >= maxAvailableCargoSpace())
		{
			if (max_cargo)  { if (shipAI != nullptr)  shipAI->message("HOLD_FULL"); }	//can't collect loot if holds are full!
			if (shipAI != nullptr)  shipAI->message("NOTHING_FOUND");		//can't collect loot if holds are full!
			return;
		}
	}
	else
	{
		if (magnitude2(getVelocity()))
		{
			if (shipAI != nullptr)  shipAI->message("NOTHING_FOUND");		//can't collect loot if you're a moving station
			return;
		}
	}
	
	checkScanner();
	
	double found_d2 = scannerRange * scannerRange;
	_foundTarget = nullptr;
	unsigned i;
	for (i = 0; i < n_scanned_ships; i++)
	{
		::ShipEntity *other = oo::ToShip(scanned_ships[i]);
		if ((other != nullptr ? other->getScanClass() : OOScanClass{}) == CLASS_CARGO && (other == nullptr || other->cargoType() != CARGO_NOT_CARGO) && (other != nullptr ? other->status() : OOEntityStatus{}) != STATUS_BEING_SCOOPED)
		{
			if ((!isPolice()) || ((other != nullptr ? other->commodityType() : std::optional<std::string>()) == "slaves")) // police only rescue lifepods and slaves
			{
				GLfloat d2 = distance2_scanned_ships[i];
				if (d2 < found_d2)
				{
					found_d2 = d2;
					setFoundTarget(other);
				}
			}
		}
	}
	checkFoundTarget();
}


void ShipEntity::scanForRandomLoot()
{
	/*-- Locates the all debris in range and chooses a piece at random from the first sixteen found --*/
	if (!getIsStation() && !hasCargoScoop())
	{
		if (shipAI != nullptr)  shipAI->message("NOTHING_FOUND");		//can't collect loot if you have no scoop!
		return;
	}
	//
	checkScanner();
	//
	::ShipEntity* thing_uids_found[16];
	unsigned things_found = 0;
	_foundTarget = nullptr;
	unsigned i;
	for (i = 0; (i < n_scanned_ships)&&(things_found < 16) ; i++)
	{
		::ShipEntity *other = scanned_ships[i];
		if ((other != nullptr ? other->getScanClass() : OOScanClass{}) == CLASS_CARGO && (other == nullptr || other->cargoType() != CARGO_NOT_CARGO) && (other != nullptr ? other->status() : OOEntityStatus{}) != STATUS_BEING_SCOOPED)
		{
			thing_uids_found[things_found++] = other;
		}
	}
	
	if (things_found != 0)
	{
		setFoundTarget(thing_uids_found[ranrot_rand() % things_found]);
		if (shipAI != nullptr)  shipAI->message("TARGET_FOUND");
	}
	else
		{ if (shipAI != nullptr)  shipAI->message("NOTHING_FOUND"); }
}


void ShipEntity::setTargetToFoundTarget()
{
	if (foundTarget() != nil)
	{
		addTarget(foundTarget());
	}
	else
	{
		if (shipAI != nullptr)  shipAI->message("TARGET_LOST"); // to prevent the ship going for a wrong, previous target. Should not be a reactToMessage.
	}
}


void ShipEntity::addFoundTargetAsDefenseTarget()
{
	Entity *fTarget = foundTarget();
	if (fTarget != nil)
	{
		if (oo::EntityIsShip(fTarget) && !(oo::ToShip(fTarget) != nullptr ? oo::ToShip(fTarget)->isFriendlyTo(this) : false))
		{
			addDefenseTarget(fTarget);
		}
	}
}


void ShipEntity::checkForFullHold()
{
	if (!max_cargo)
	{
		if (shipAI != nullptr)  shipAI->message("NO_CARGO_BAY");
	}
	else if (cargoCount() >= maxAvailableCargoSpace())
	{
		if (shipAI != nullptr)  shipAI->message("HOLD_FULL");
	}
	else
	{
		if (shipAI != nullptr)  shipAI->message("HOLD_NOT_FULL");
	}
}


void ShipEntity::getWitchspaceEntryCoordinates()
{
	/*- calculates coordinates from the nearest station it can find, or just fly 10s forward -*/
	if (!UNIVERSE)
	{
		Vector  vr = vector_multiply_scalar(v_forward, maxFlightSpeed * 10.0);  // 10 second flying away
		coordinates = HPvector_add(position, vectorToHPVector(vr));
		return;
	}
	//
	// find the nearest station...
	//
	// we don't use "checkScanner" because we must rely on finding a present station.
	//
	::StationEntity	*station =  nil;
	station = oo::ToStation((UNIVERSE != nullptr ? UNIVERSE->nearestShipMatchingPredicate(IsStationPredicate, nullptr, this) : nullptr));
	
	if (station && HPdistance2((station != nullptr ? station->getPosition() : HPVector{}), position) < SCANNER_MAX_RANGE2) // there is a station in range.
	{
		Vector  vr = vector_multiply_scalar((station != nullptr ? station->rightVector() : Vector{}), 10000);  // 10km from station
		coordinates = HPvector_add((station != nullptr ? station->getPosition() : HPVector{}), vectorToHPVector(vr));
	}
	else
	{
		Vector  vr = vector_multiply_scalar(v_forward, maxFlightSpeed * 10.0);  // 10 second flying away
		coordinates = HPvector_add(position, vectorToHPVector(vr));
	}
}


void ShipEntity::setDestinationFromCoordinates()
{
	_destination = coordinates;
}


void ShipEntity::setCoordinatesFromPosition()
{
	coordinates = position;
}


void ShipEntity::fightOrFleeMissile()
{
	// find an incoming missile...
	//
	::ShipEntity			*missile =  nil;
	unsigned			i;
	::ShipEntity			*escort = nil;
	::ShipEntity			*target = nil;
	
	checkScannerIgnoringUnpowered();
	for (i = 0; (i < n_scanned_ships)&&(missile == nil); i++)
	{
		::ShipEntity *thing = scanned_ships[i];
		if (thing->scanClass == CLASS_MISSILE)
		{
			target = oo::ToShip((thing != nullptr ? thing->primaryTarget() : (Entity *)nullptr));
			
			if (target == this)
			{
				missile = thing;
			}
			else
			{
				for (const auto &escortRef : escorts())
				{
					escort = oo::ToShip(escortRef.get());
					if (target == escort)
					{
						missile = thing;
					}
				}
			}
		}
	}
	
	if (missile == nil)  return;
	
	addTarget(missile);
	addDefenseTarget(missile);
	
	// Notify own ship script that we are being attacked.	
	::ShipEntity *hunter = oo::ToShip((missile != nullptr ? missile->owner() : nullptr));
	doScriptEvent(OOJSID("shipBeingAttacked"), hunter);
	if (hunter != nullptr)  hunter->doScriptEvent(OOJSID("shipAttackedOther"), this);
	
	if (isPolice())
	{
		// Notify other police in group of attacker.
		// Note: prior to 1.73 this was done only if we had ECM.
		::ShipEntity		*police = nil;
		
		for (const oo::EntityHold &member : (group() != nullptr ? group()->memberArray() : std::vector<oo::EntityHold>()))
		{
			police = oo::ToShip(member.get());
			if (police != nullptr)  police->setFoundTarget(hunter);
			if (police != nullptr)  police->setPrimaryAggressor(hunter);
		}
	}
	
	// if I'm a copper and you're not, then mark the other as an offender!
	if (isPolice() && !(hunter != nullptr ? hunter->isPolice() : false))  { if (hunter != nullptr)  hunter->markAsOffender(64, kOOLegalStatusReasonAttackedPolice); }

	if (hasECM())
	{
		// use the ECM and battle on
		
		setPrimaryAggressor(hunter);	// lets get them now for that!
		setFoundTarget(hunter);
		
		fireECM();
		return;
	}
	
	// RUN AWAY !!
	desired_range = 10000;
	performFlee();
	if (shipAI != nullptr)  shipAI->message("FLEEING");
}


void ShipEntity::setCourseToPlanet()
{
	/*- selects the nearest planet it can find -*/
	::OOPlanetEntity	*the_planet =  findNearestPlanetExcludingMoons();
	if (the_planet)
	{
		double variation = (aegis_status == AEGIS_NONE ? 0.5 : 0.2); // more random deviation when far from planet.
		HPVector p_pos = the_planet->position;	// the planet is C++ since bead oo-9ht.129
		double p_cr = the_planet->collision_radius;		// the surface
		HPVector p1 = HPvector_between(p_pos, position);
		p1 = HPvector_normal(p1);			// vector towards ship
		p1.x += variation * (randf() - variation);
		p1.y += variation * (randf() - variation);
		p1.z += variation * (randf() - variation);
		p1 = HPvector_normal(p1); 
		_destination = HPvector_add(p_pos, HPvector_multiply_scalar(p1, p_cr));	// on surface
		desired_range = collision_radius + 100.0;	// +100m from the destination
	}
	else
	{
		if (shipAI != nullptr)  shipAI->message("NO_PLANET_FOUND");
	}
}


void ShipEntity::setTakeOffFromPlanet()
{
	/*- selects the nearest planet it can find -*/
	::OOPlanetEntity	*the_planet =  findNearestPlanet();
	if (the_planet)
	{
		_destination = HPvector_add((the_planet != nullptr ? the_planet->getPosition() : HPVector{}), HPvector_multiply_scalar(
																			   HPvector_normal(HPvector_subtract((the_planet != nullptr ? the_planet->getPosition() : HPVector{}),position)),-10000.0-the_planet->collision_radius));// 10km straight up
		desired_range = 50.0;
	}
	else
	{
		OO_LOG("ai.setTakeOffFromPlanet.noPlanet", "{}", "***** Error. Planet not found during take off!");
	}
}


void ShipEntity::landOnPlanet()
{
	// Selects the nearest planet it can find.
	landOnPlanet(findNearestPlanet());
}


void ShipEntity::checkTargetLegalStatus()
{
	::ShipEntity  *other_ship = oo::ToShip(primaryTarget());
	if (!other_ship)
	{
		if (shipAI != nullptr)  shipAI->message("NO_TARGET");
		return;
	}
	else
	{
		int ls = (other_ship != nullptr ? other_ship->legalStatus() : int{});
		if (ls > 50)
		{
			if (shipAI != nullptr)  shipAI->message("TARGET_FUGITIVE");
			return;
		}
		if (ls > 20)
		{
			if (shipAI != nullptr)  shipAI->message("TARGET_OFFENDER");
			return;
		}
		if (ls > 0)
		{
			if (shipAI != nullptr)  shipAI->message("TARGET_MINOR_OFFENDER");
			return;
		}
		if (shipAI != nullptr)  shipAI->message("TARGET_CLEAN");
	}
}


void ShipEntity::checkOwnLegalStatus()
{
	if (scanClass == CLASS_THARGOID)
	{
		if (shipAI != nullptr)  shipAI->message("SELF_THARGOID");
		return;
	}
	int ls = legalStatus();
	if (ls > 50)
	{
		if (shipAI != nullptr)  shipAI->message("SELF_FUGITIVE");
		return;
	}
	if (ls > 20)
	{
		if (shipAI != nullptr)  shipAI->message("SELF_OFFENDER");
		return;
	}
	if (ls > 0)
	{
		if (shipAI != nullptr)  shipAI->message("SELF_MINOR_OFFENDER");
		return;
	}
	if (shipAI != nullptr)  shipAI->message("SELF_CLEAN");
}


void ShipEntity::exitAIWithMessage(const std::string &message)	// called by name (ADR-0055 item 5)
{
	if (shipAI != nullptr)  shipAI->exitStateMachineWithMessage(message.empty() ? std::string("RESTARTED") : message);
}


void ShipEntity::setDestinationToTarget()
{
	Entity *the_target = primaryTarget();
	if (the_target)
		_destination = the_target->position;
}


void ShipEntity::setDestinationWithinTarget()
{
	Entity *the_target = primaryTarget();
	if (the_target)
	{
		HPVector pos = the_target->position;
		Quaternion q;	quaternion_set_random(&q);
		Vector v = vector_forward_from_quaternion(q);
		GLfloat d = (randf() - randf()) * the_target->collision_radius;  // NOLINT(misc-redundant-expression): two independent randf() draws, pre-existing; behaviour unchanged by this retarget.
		_destination = make_HPvector(pos.x + d * v.x, pos.y + d * v.y, pos.z + d * v.z);
	}
}


void ShipEntity::checkCourseToDestination()
{
	Entity *hazard = (UNIVERSE != nullptr ? UNIVERSE->hazardOnRouteFromEntity(this, desired_range, _destination) : nullptr);	// the C++ entities (bead oo-9ht.39.8.6); asked what its object answered (bead oo-9ht.39.16)
	
	if (hazard == nullptr || (oo::EntityIsShip(hazard) && HPdistance(position, hazard->getPosition()) > scannerRange) || (oo::EntityIsPlanet(hazard) && aegis_status == AEGIS_NONE)) 
		{ if (shipAI != nullptr)  shipAI->message("COURSE_OK"); } // Avoid going into a waypoint.plist for far away objects, it cripples the main AI a bit in its funtionality.
	else
	{
		if (oo::EntityIsShip(hazard) && (weapon_damage * 24.0 > hazard->getEnergy()))
		{
			if (shipAI != nullptr)  shipAI->reactToMessage("HAZARD_CAN_BE_DESTROYED", "checkCourseToDestination");
		}
		
		_destination = (UNIVERSE != nullptr ? UNIVERSE->getSafeVectorFromEntity(this, desired_range, _destination) : HPVector{});	// the C++ ship (bead oo-9ht.39.8.6)
		if (shipAI != nullptr)  shipAI->message("WAYPOINT_SET");
	}
}




// Slice 3 of docs/phases/3-slices/ShipEntityAI.md (bead oo-wc9o3): PureAI part 2: checks, comms,
// Thargoids, escorts, patrols, target marking. Members of ShipEntity defined in the category's file
// (ADR-0056 amendment oo-o89 item 4); called directly since bead oo-9ht.144 deleted the facade
// (amendment oo-9ht.144).

void ShipEntity::checkAegis()
{
	switch (aegis_status)
	{
		case AEGIS_CLOSE_TO_MAIN_PLANET: 
			if (shipAI != nullptr)  shipAI->message("AEGIS_CLOSE_TO_MAIN_PLANET");
			// It's been a few years since 1.71 - it should be safe enough to comment out the line below for 1.77/1.78 -- Kaks 20120917
			//[shipAI message:@"AEGIS_CLOSE_TO_PLANET"];	     // fires only for main planets, kept for compatibility with pre-1.72 AI plists.
			return;
		case AEGIS_CLOSE_TO_ANY_PLANET:
		{
			Entity *nearest = findNearestStellarBody();	// the C++ entity (bead oo-al52f)
			
			if(nearest != nullptr && nearest->isSun())
			{
				if (shipAI != nullptr)  shipAI->message("CLOSE_TO_SUN");
			}
			else
			{
				if (shipAI != nullptr)  shipAI->message("CLOSE_TO_PLANET");
				if (OOStellarBodyPlanetType(nearest) == STELLAR_TYPE_MOON)
				{
					if (shipAI != nullptr)  shipAI->message("CLOSE_TO_MOON");
				}
				else
				{
					if (shipAI != nullptr)  shipAI->message("CLOSE_TO_SECONDARY_PLANET");
				}
			}
			return;
		}
		case AEGIS_IN_DOCKING_RANGE:
			if (shipAI != nullptr)  shipAI->message("AEGIS_IN_DOCKING_RANGE");
			return;
		case AEGIS_NONE:
			if (shipAI != nullptr)  shipAI->message("AEGIS_NONE");
			return;
	}
	
	OO_LOG("unclassified", "Aegis status for {} has taken on invalid value {}. This is an internal error, please report it.", oo::EntityDescription(this), static_cast<int>(aegis_status));
	aegis_status = AEGIS_NONE;
	if (shipAI != nullptr)  shipAI->message("AEGIS_NONE");
}


void ShipEntity::checkEnergy()
{
	if (energy == maxEnergy)
	{
		if (shipAI != nullptr)  shipAI->message("ENERGY_FULL");
		return;
	}
	if (energy >= maxEnergy * 0.75)
	{
		if (shipAI != nullptr)  shipAI->message("ENERGY_HIGH");
		return;
	}
	if (energy <= maxEnergy * 0.25)
	{
		if (shipAI != nullptr)  shipAI->message("ENERGY_LOW");
		return;
	}
	if (shipAI != nullptr)  shipAI->message("ENERGY_MEDIUM");
}


void ShipEntity::checkHeatInsulation()
{
	float minInsulation = 1000 / getMaxFlightSpeed() + 1;
	
	if (heatInsulation() < minInsulation)
	{
		if (shipAI != nullptr)  shipAI->message("INSULATION_POOR");
		return;
	}
	if (shipAI != nullptr)  shipAI->message("INSULATION_OK");
}


void ShipEntity::findNewDefenseTarget()
{
	checkScanner();
	unsigned i;
	for (i = 0; i < n_scanned_ships ; i++)
	{
		::ShipEntity *ship = scanned_ships[i];
		if (!(ship != nullptr ? ship->isCloaked() : false) && (((ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) == this && (ship != nullptr ? ship->hasHostileTarget() : false)) || (ship != nullptr ? ship->isMine() : false) || ((ship != nullptr ? ship->isThargoid() : false) != isThargoid())))
		{
			if (!isDefenseTarget(ship))
			{
				addDefenseTarget(ship);
				return;
			}
		}
	}
}


void ShipEntity::scanForOffenders()
{
	/*-- Locates all the ships in range and compares their legal status or bounty against ranrot_rand() & 255 - chooses the worst offender --*/
	float gov_factor =	0.4 * (UNIVERSE != nullptr ? UNIVERSE->currentSystemData() : oo::PList()).get<int>(std::string(KEY_GOVERNMENT)); // 0 .. 7 (0 anarchic .. 7 most stable) --> [0.0, 0.4, 0.8, 1.2, 1.6, 2.0, 2.4, 2.8]
	//
	if ((UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr) == nil)
		gov_factor = 1.0;
	//
	_foundTarget = nullptr;
	
	// find the worst offender on the scanner
	//
	checkScanner();
	unsigned i;
	float	worst_legal_factor = 0;
	GLfloat found_d2 = scannerRange * scannerRange;
	::OOShipGroup *group = this->group();
	for (i = 0; i < n_scanned_ships ; i++)
	{
		::ShipEntity *ship = scanned_ships[i];
		if ((ship->scanClass != CLASS_CARGO)&&((ship != nullptr ? ship->status() : OOEntityStatus{}) != STATUS_DEAD)&&((ship != nullptr ? ship->status() : OOEntityStatus{}) != STATUS_DOCKED)&& !(ship != nullptr ? ship->isCloaked() : false))
		{
			GLfloat	d2 = distance2_scanned_ships[i];
			float	legal_factor = (ship != nullptr ? ship->legalStatus() : int{}) * gov_factor;
			int random_factor = ranrot_rand() & 255;   // 25% chance of spotting a fugitive in 15s
			if ((d2 < found_d2)&&(random_factor < legal_factor)&&(legal_factor > worst_legal_factor))
			{
				if (group == nil || group != (ship != nullptr ? ship->group() : (OOShipGroup *)nullptr))  // fellows with bounty can't be offenders
				{
					setFoundTarget(ship);
					worst_legal_factor = legal_factor;
				}
			}
		}
	}
	
	checkFoundTarget();
}


void ShipEntity::setCourseToWitchpoint()
{
	if (UNIVERSE)
	{
		_destination = (UNIVERSE != nullptr ? UNIVERSE->getWitchspaceExitPosition() : HPVector{});
		desired_range = 10000.0;   // 10km away
	}
}


void ShipEntity::setDestinationToWitchpoint()
{
	_destination = (UNIVERSE != nullptr ? UNIVERSE->getWitchspaceExitPosition() : HPVector{});
}


void ShipEntity::setDestinationToStationBeacon()
{
	if ((UNIVERSE != nullptr && UNIVERSE->station() != nullptr))
	{
		_destination = ((UNIVERSE != nullptr ? UNIVERSE->station() : nullptr) != nullptr ? UNIVERSE->station()->beaconPosition() : HPVector{});
	}
}


void ShipEntity::performHyperSpaceExit()
{
	performHyperSpaceExitReplace(YES);
}


void ShipEntity::performHyperSpaceExitWithoutReplacing()
{
	performHyperSpaceExitReplace(NO);
}


void ShipEntity::disengageAutopilot()
{
	OO_LOG_ERR("ai.invalid.notPlayer", "Error in {}:{}, AI method endAutoPilot is only applicable to the player.", (shipAI != nullptr ? shipAI->name() : std::optional<std::string>()).value_or("(null)"), (shipAI != nullptr ? shipAI->state() : std::optional<std::string>()).value_or("(null)"));
}


void ShipEntity::wormholeGroup()
{
	::ShipEntity			*ship = nil;
	Entity			*whole = nullptr;	// the wormhole (bead oo-9ht.39.16)
	
	whole = primaryTarget();
	if (!(whole != nullptr && whole->getIsWormhole()))  return;
	
	for (const oo::EntityHold &member : (group() != nullptr ? group()->memberArray() : std::vector<oo::EntityHold>()))
	{
		ship = oo::ToShip(member.get());
		if (ship != nullptr)  ship->addTarget(whole);
		if (ship != nullptr)  ship->reactToAIMessage("ENTER WORMHOLE", "wormholeGroup");
		if (ship != nullptr)  ship->doScriptEvent(OOJSID("wormholeSuggested"), whole);
	}
}


void ShipEntity::commsMessage(const std::string &valueString)	// called by name (ADR-0055 item 5)
{
	commsMessage(valueString, NO);
}


void ShipEntity::commsMessageByUnpiloted(const std::string &valueString)	// called by name (ADR-0055 item 5)
{
	commsMessage(valueString, YES);
}


void ShipEntity::ejectCargo()
{
	OOCargoQuantity i, cargo_to_go = 0.1 * maxAvailableCargoSpace();
	while (cargo_to_go > 15)
	{
		cargo_to_go = ranrot_rand() % cargo_to_go;
	}
	dumpCargo();
	for (i = 1; i < cargo_to_go; i++)
	{
		// drop 3 canisters per 2 seconds (a deferred call on the C++ ship since bead oo-9ht.39.7.3; by name on its object before)
		oo::ScheduleEntityCall(this, [](Entity *entity) { if (ShipEntity *ship = dynamic_cast<ShipEntity *>(entity))  ship->dumpCargo(); }, 0.75 * i);
	}
}


void ShipEntity::scanForThargoid()
{
	return scanForNearestShipWithPrimaryRole("thargoid");
}


void ShipEntity::scanForNonThargoid()
{
	/*-- Locates all the non thargoid ships in range and chooses the nearest --*/
	_foundTarget = nullptr;
	
	checkScanner();
	unsigned i;
	GLfloat	found_d2 = scannerRange * scannerRange;
	for (i = 0; i < n_scanned_ships ; i++)
	{
		::ShipEntity *thing = scanned_ships[i];
		GLfloat d2 = distance2_scanned_ships[i];
		if (((thing != nullptr ? thing->getScanClass() : OOScanClass{}) != CLASS_CARGO) && ((thing != nullptr ? thing->status() : OOEntityStatus{}) != STATUS_DOCKED) && !(thing != nullptr ? thing->isThargoid() : false) && !(thing != nullptr ? thing->isCloaked() : false) && (d2 < found_d2))
		{
			setFoundTarget(thing);
			if ((thing != nullptr ? thing->getIsPlayer() : false)) d2 = 0.0;   // prefer the player
			found_d2 = d2;
		}
	}

	checkFoundTarget();
}


void ShipEntity::thargonCheckMother()
{
	::ShipEntity   *mother = oo::ToShip(owner());
	if (mother == nil && group())  mother = (group() != nullptr ? group()->leader() : (::ShipEntity *)nil);
	
	double	maxRange2 = scannerRange * scannerRange;
	
	if (mother && mother != this && HPdistance2(mother->position, position) < maxRange2)
	{
		if (shipAI != nullptr)  shipAI->message("TARGET_FOUND"); // no need for scanning, we still have our mother.
	}
	else
	{
		// we lost the old mother, search for a new one
		scanForNearestShipHavingRole("thargoid-mothership"); // the scan will send further AI messages.
		if (foundTarget() != nil)
		{
			mother = oo::ToShip(foundTarget());
			setOwner(mother);
			if ((mother != nullptr ? mother->group() : (OOShipGroup *)nullptr) != (mother != nullptr ? mother->escortGroup() : (OOShipGroup *)nullptr)) // avoid adding thargon to an escort group.
			{
				setGroup((mother != nullptr ? mother->group() : (OOShipGroup *)nullptr));
			}
		};
	}
}


void ShipEntity::becomeUncontrolledThargon()
{
	int			ent_count =		UNIVERSE->n_entities;
	Entity**	uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
	int i;
	for (i = 0; i < ent_count; i++) if (uni_entities[i]->isShip)
	{
		::ShipEntity *other = oo::ToShip(uni_entities[i]);
		if ((other != nullptr ? other->primaryTarget() : (Entity *)nullptr) == this)
		{
			if (other != nullptr)  other->removeTarget(this);
		}
		if ((other != nullptr ? other->isDefenseTarget(this) : false))
		{
			if (other != nullptr)  other->removeDefenseTarget(this);
		}
	}
	// now we're just a bunch of alien artefacts!
	scanClass = CLASS_CARGO;
	reportAIMessages = NO;
	setAITo("dumbAI.plist");
	_primaryTarget = nullptr;
	setSpeed(0.0);
	setGroup(nullptr);
}


void ShipEntity::checkDistanceTravelled()
{
	if (distanceTravelled > desired_range)
		{ if (shipAI != nullptr)  shipAI->message("GONE_BEYOND_RANGE"); }
}


void ShipEntity::fightOrFleeHostiles()
{
	addDefenseTarget(foundTarget());
	
	if (hasEscorts())
	{
		Entity *leTarget = lastEscortTarget();
		if (leTarget != nil)
		{
			setFoundTarget(leTarget);
			if (shipAI != nullptr)  shipAI->message("FLEEING");
			return;
		}
		
		setPrimaryAggressor(foundTarget());
		addTarget(foundTarget());
		deployEscorts();
		if (shipAI != nullptr)  shipAI->message("DEPLOYING_ESCORTS");
		if (shipAI != nullptr)  shipAI->message("FLEEING");
		return;
	}
	
	// consider launching a missile
	if (missiles > 2)   // keep a reserve
	{
		if (randf() < 0.50)
		{
			setPrimaryAggressor(foundTarget());
			addTarget(foundTarget());
			fireMissile();
			if (shipAI != nullptr)  shipAI->message("FLEEING");
			return;
		}
	}
	
	// consider fighting
	if (energy > maxEnergy * 0.80)
	{
		setPrimaryAggressor(foundTarget());
		//[self performAttack];
		if (shipAI != nullptr)  shipAI->message("FIGHTING");
		return;
	}
	
	if (shipAI != nullptr)  shipAI->message("FLEEING");
}


void ShipEntity::suggestEscort()
{
	::ShipEntity   *mother = oo::ToShip(primaryTarget());
	suggestEscortTo(mother);
}


void ShipEntity::escortCheckMother()
{
	::ShipEntity   *mother = oo::ToShip(owner());
	
	if ((mother != nullptr ? mother->acceptAsEscort(this) : false))
	{
		setOwner(mother);
		setGroup((mother != nullptr ? mother->escortGroup() : (OOShipGroup *)nullptr));
		if (shipAI != nullptr)  shipAI->message("ESCORTING");
	}
	else
	{
		setOwner(this);
		if (group() == (mother != nullptr ? mother->escortGroup() : (OOShipGroup *)nullptr))  setGroup(nullptr);
		if (shipAI != nullptr)  shipAI->message("NOT_ESCORTING");
	}
}


void ShipEntity::checkGroupOddsVersusTarget()
{
	NSUInteger ownGroupCount = (group() != nullptr ? group()->count() : 0) + (ranrot_rand() & 3);			// add a random fudge factor
	::ShipEntity *target = oo::ToShip(primaryTarget());
	::OOShipGroup *targetGroup = (target != nullptr ? target->group() : (OOShipGroup *)nullptr);
	NSUInteger targetGroupCount = (targetGroup != nullptr ? targetGroup->count() : 0) + (ranrot_rand() & 3);	// add a random fudge factor
	
	if (ownGroupCount == targetGroupCount)
	{
		if (shipAI != nullptr)  shipAI->message("ODDS_LEVEL");
	}
	else if (ownGroupCount > targetGroupCount)
	{
		if (shipAI != nullptr)  shipAI->message("ODDS_GOOD");
	}
	else
	{
		if (shipAI != nullptr)  shipAI->message("ODDS_BAD");
	}
}


void ShipEntity::scanForFormationLeader()
{
	//-- Locates the nearest suitable formation leader in range --//
	_foundTarget = nullptr;
	checkScannerIgnoringUnpowered();
	unsigned i;
	GLfloat	found_d2 = scannerRange * scannerRange;
	for (i = 0; i < n_scanned_ships; i++)
	{
		::ShipEntity *ship = scanned_ships[i];
		if ((ship != this) && (!ship->isPlayer) && (ship->scanClass == scanClass) && (ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) != this && !(ship != nullptr ? ship->isCloaked() : false))	// look for alike
		{
			GLfloat d2 = distance2_scanned_ships[i];
			if ((d2 < found_d2) && (ship != nullptr ? ship->canAcceptEscort(this) : false))
			{
				found_d2 = d2;
				setFoundTarget(ship);
			}
		}
	}
	
	if (foundTarget() != nil)  { if (shipAI != nullptr)  shipAI->message("TARGET_FOUND"); }
	else
	{
		if (shipAI != nullptr)  shipAI->message("NOTHING_FOUND");
		if (hasPrimaryRole("wingman"))
		{
			// become free-lance police :)
			setAITo("route1patrolAI.plist");	// use this to avoid referencing a released AI
			setPrimaryRole("police"); // other wingman can now select this ship as leader.
		}
	}
	
}


void ShipEntity::messageMother(const std::string &msgString)	// called by name (ADR-0055 item 5)
{
	::ShipEntity *mother = oo::ToShip(owner());
	if (mother != nil && mother != this)
	{
		if (mother != nullptr)  mother->reactToAIMessage(msgString, DebugContext(this, "messageMother"));
	}
}


void ShipEntity::messageSelf(const std::string &msgString)	// called by name (ADR-0055 item 5)
{
	sendAIMessage(msgString);
}


void ShipEntity::setPlanetPatrolCoordinates()
{
	// check we've arrived near the last given coordinates
	HPVector r_pos = HPvector_subtract(position, coordinates);
	if (HPmagnitude2(r_pos) < 1000000 || patrol_counter == 0)
	{
		Entity *the_sun = (UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr);
		::ShipEntity *the_station = (group() != nullptr ? group()->leader() : (::ShipEntity *)nil);
		if(!the_station || !(the_station != nullptr ? the_station->getIsStation() : false)) the_station = oo::ToShip((UNIVERSE != nullptr ? UNIVERSE->station() : nullptr));
		if ((!the_sun)||(!the_station))
			return;
		HPVector sun_pos = the_sun->position;
		HPVector stn_pos = the_station->position;
		HPVector sun_dir = HPvector_subtract(sun_pos,stn_pos);
		Vector vSun = make_vector(0, 0, 1);
		if (sun_dir.x||sun_dir.y||sun_dir.z)
			vSun = HPVectorToVector(HPvector_normal(sun_dir));
		Vector v0 = (the_station != nullptr ? the_station->forwardVector() : Vector{});
		Vector v1 = cross_product(v0, vSun);
		Vector v2 = cross_product(v0, v1);
		switch (patrol_counter)
		{
			case 0:		// first go to 5km ahead of the station
				coordinates = make_HPvector(stn_pos.x + 5000 * v0.x, stn_pos.y + 5000 * v0.y, stn_pos.z + 5000 * v0.z);
				desired_range = 250.0;
				break;
			case 1:		// go to 25km N of the station
				coordinates = make_HPvector(stn_pos.x + 25000 * v1.x, stn_pos.y + 25000 * v1.y, stn_pos.z + 25000 * v1.z);
				desired_range = 250.0;
				break;
			case 2:		// go to 25km E of the station
				coordinates = make_HPvector(stn_pos.x + 25000 * v2.x, stn_pos.y + 25000 * v2.y, stn_pos.z + 25000 * v2.z);
				desired_range = 250.0;
				break;
			case 3:		// go to 25km S of the station
				coordinates = make_HPvector(stn_pos.x - 25000 * v1.x, stn_pos.y - 25000 * v1.y, stn_pos.z - 25000 * v1.z);
				desired_range = 250.0;
				break;
			case 4:		// go to 25km W of the station
				coordinates = make_HPvector(stn_pos.x - 25000 * v2.x, stn_pos.y - 25000 * v2.y, stn_pos.z - 25000 * v2.z);
				desired_range = 250.0;
				break;
			default:	// We should never come here
				coordinates = make_HPvector(stn_pos.x + 5000 * v0.x, stn_pos.y + 5000 * v0.y, stn_pos.z + 5000 * v0.z);
				desired_range = 250.0;
				break;
		}
		patrol_counter++;
		if (patrol_counter > 4)
		{
			if (randf() < .25)
			{
				// consider docking
				setTargetStation(the_station);
				setAITo("dockingAI.plist");
				return;
			}
			else
			{
				// go around again
				patrol_counter = 1;
			}
		}
	}
	if (shipAI != nullptr)  shipAI->message("APPROACH_COORDINATES");
}


void ShipEntity::setSunSkimStartCoordinates()
{
	if ((UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr) == nil)
	{
		if (shipAI != nullptr)  shipAI->message("NO_SUN_FOUND");
		return;
	}
	
	HPVector v0 = (UNIVERSE != nullptr ? UNIVERSE->getSunSkimStartPositionForShip(this) : HPVector{});
	
	if (!HPvector_equal(v0, kZeroHPVector))
	{
		coordinates = v0;
		if (shipAI != nullptr)  shipAI->message("APPROACH_COORDINATES");
	}
	else
	{
		if (shipAI != nullptr)  shipAI->message("WAIT_FOR_SUN");
	}
}


void ShipEntity::setSunSkimEndCoordinates()
{
	if ((UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr) == nil)
	{
		if (shipAI != nullptr)  shipAI->message("NO_SUN_FOUND");
		return;
	}
	
	coordinates = (UNIVERSE != nullptr ? UNIVERSE->getSunSkimEndPositionForShip(this) : HPVector{});
	if (shipAI != nullptr)  shipAI->message("APPROACH_COORDINATES");
}


void ShipEntity::setSunSkimExitCoordinates()
{
	Entity *the_sun = (UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr);
	if (the_sun == nil)  return;
	HPVector v1 = (UNIVERSE != nullptr ? UNIVERSE->getSunSkimEndPositionForShip(this) : HPVector{});
	HPVector vs = the_sun->position;
	HPVector vout = HPvector_subtract(v1,vs);
	if (vout.x||vout.y||vout.z)
		vout = HPvector_normal(vout);
	else
		vout.z = 1.0;
	v1.x += 10000 * vout.x;	v1.y += 10000 * vout.y;	v1.z += 10000 * vout.z;
	coordinates = v1;
	if (shipAI != nullptr)  shipAI->message("APPROACH_COORDINATES");
}


void ShipEntity::patrolReportIn()
{
	// Set a report time in the patrolled station to delay a new launch.
	::ShipEntity *the_station = (group() != nullptr ? group()->leader() : (::ShipEntity *)nil);
	if(!the_station || !(the_station != nullptr ? the_station->getIsStation() : false)) the_station = oo::ToShip((UNIVERSE != nullptr ? UNIVERSE->station() : nullptr));
	if (oo::ToStation(the_station) != nullptr)  oo::ToStation(the_station)->acceptPatrolReportFrom(this);
}


void ShipEntity::checkForMotherStation()
{
	::ShipEntity *motherStation = (group() != nullptr ? group()->leader() : (::ShipEntity *)nil);
	if ((!motherStation) || (!(motherStation->isStation)))
	{
		if (shipAI != nullptr)  shipAI->message("NOTHING_FOUND");
		return;
	}
	double found_d2 = scannerRange * scannerRange;
	HPVector v0 = motherStation->position;
	if (HPdistance2(v0,position) > found_d2)
	{
		if (shipAI != nullptr)  shipAI->message("NOTHING_FOUND");
		return;
	}
	if (shipAI != nullptr)  shipAI->message("STATION_FOUND");		
}


void ShipEntity::sendTargetCommsMessage(const std::string &message)	// called by name (ADR-0055 item 5)
{
	::ShipEntity *ship = oo::ToShip(primaryTarget());
	if ((ship == nil) || ((ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_DEAD) || ((ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_DOCKED))
	{
		noteLostTarget();
		return;
	}
	sendExpandedMessage(message, oo::ToShip(primaryTarget()));
}


void ShipEntity::markTargetForFines()
{
	::ShipEntity *ship = oo::ToShip(primaryTarget());
	if ((ship == nil) || ((ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_DEAD) || ((ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_DOCKED))
	{
		noteLostTarget();
		return;
	}
	if ((ship != nullptr ? ship->markForFines() : false))  { if (shipAI != nullptr)  shipAI->message("TARGET_MARKED"); }
}


void ShipEntity::markTargetForOffence(const std::string &valueString)	// called by name (ADR-0055 item 5)
{
	if ((isStation)||(scanClass == CLASS_POLICE))
	{
		::ShipEntity *ship = oo::ToShip(primaryTarget());
		if ((ship == nil) || ((ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_DEAD) || ((ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_DOCKED))
		{
			noteLostTarget();
			return;
		}
		const std::string finalValue = cxx_OOExpand(valueString).value_or(std::string());	// expand values
		if (ship != nullptr)  ship->markAsOffender(oo::str::intValue(finalValue), kOOLegalStatusReasonSeenByPolice);
	}
}


void ShipEntity::storeTarget()
{
	Entity *target = primaryTarget();
	
	if (target)
	{
		setRememberedShip(target);
	}
	else
	{
		_rememberedShip = nullptr;
	}
	
}




// Slice 4 of docs/phases/3-slices/ShipEntityAI.md (bead oo-lqyhf): PureAI part 3: stored targets,
// nearest-ship scans, stations, script actions, beacons. Members of ShipEntity defined in the
// category's file (ADR-0056 amendment oo-o89 item 4); called directly since bead oo-9ht.144 deleted
// the facade (amendment oo-9ht.144).

void ShipEntity::recallStoredTarget()
{
	::ShipEntity	*oldTarget = oo::ToShip(rememberedShip());
	BOOL	found = NO;
	
	if (oldTarget && !(oldTarget != nullptr ? oldTarget->isCloaked() : false))
	{
		GLfloat range2 = HPdistance2((oldTarget != nullptr ? oldTarget->getPosition() : HPVector{}), position);
		if (range2 <= scannerRange * scannerRange && range2 <= SCANNER_MAX_RANGE2)
		{
			found = YES;
		}
	}
	
	if (found)
	{
		setFoundTarget(oldTarget);
		if (shipAI != nullptr)  shipAI->message("TARGET_FOUND");
	}
	else
	{
		if (oldTarget == nil) _rememberedShip = nullptr; // ship no longer exists
		if (shipAI != nullptr)  shipAI->message("NOTHING_FOUND");
	}
	
}


void ShipEntity::scanForRocks()
{
	/*-- Locates the all boulders and asteroids in range and selects nearest --*/
	
	// find boulders then asteroids within range
	//
	_foundTarget = nullptr;
	checkScanner();
	unsigned i;
	GLfloat found_d2 = scannerRange * scannerRange;
	for (i = 0; i < n_scanned_ships; i++)
	{
		::ShipEntity *thing = scanned_ships[i];
		if ((thing != nullptr ? thing->isBoulder() : false))
		{
			GLfloat d2 = distance2_scanned_ships[i];
			if (d2 < found_d2)
			{
				setFoundTarget(thing);
				found_d2 = d2;
			}
		}
	}
	if (foundTarget() == nil)
	{
		for (i = 0; i < n_scanned_ships; i++)
		{
			::ShipEntity *thing = scanned_ships[i];
			if ((thing != nullptr ? thing->hasRole("asteroid") : false))
			{
				GLfloat d2 = distance2_scanned_ships[i];
				if (d2 < found_d2)
				{
					setFoundTarget(thing);
					found_d2 = d2;
				}
			}
		}
	}
	
	checkFoundTarget();
}


void ShipEntity::setDestinationToDockingAbort()
{
	Entity *the_target = targetStation();
	if (!the_target) {
		/* Probably the player trying to dock with docking computer
		 * from out of scanner range */
		the_target = (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr);
	}
	double bo_distance = 8000; //	8km back off
	HPVector v0 = position;
	HPVector d0 = (the_target) ? the_target->position : kZeroHPVector;
	v0.x += (randf() - 0.5)*collision_radius;	v0.y += (randf() - 0.5)*collision_radius;	v0.z += (randf() - 0.5)*collision_radius;
	v0.x -= d0.x;	v0.y -= d0.y;	v0.z -= d0.z;
	v0 = HPvector_normal_or_fallback(v0, make_HPvector(0, 0, -1));
	
	v0.x *= bo_distance;	v0.y *= bo_distance;	v0.z *= bo_distance;
	v0.x += d0.x;	v0.y += d0.y;	v0.z += d0.z;
	coordinates = v0;
	_destination = v0;
}


void ShipEntity::requestNewTarget()
{
	::ShipEntity *mother = (group() != nullptr ? group()->leader() : (::ShipEntity *)nil);
	if (mother == nil)
	{
		if (shipAI != nullptr)  shipAI->message("MOTHER_LOST");
		return;
	}
	
	/*-- Locates all the ships in range targeting the mother ship and chooses the nearest/biggest --*/
	_foundTarget = nullptr;
	checkScanner();
	unsigned i;
	GLfloat found_d2 = scannerRange * scannerRange;
	GLfloat max_e = 0;
	for (i = 0; i < n_scanned_ships ; i++)
	{
		::ShipEntity *thing = scanned_ships[i];
		GLfloat d2 = distance2_scanned_ships[i];
		GLfloat e1 = (thing != nullptr ? thing->getEnergy() : 0.0f);
		if ((d2 < found_d2) && !(thing != nullptr ? thing->isCloaked() : false) && (((thing != nullptr ? thing->isThargoid() : false) && !(mother != nullptr ? mother->isThargoid() : false)) || (((thing != nullptr ? thing->primaryTarget() : (Entity *)nullptr) == mother) && (thing != nullptr ? thing->hasHostileTarget() : false))))
		{
			if (e1 > max_e)
			{
				setFoundTarget(thing);
				max_e = e1;
			}
		}
	}
	
	checkFoundTarget();
}


void ShipEntity::rollD(const std::string &die_number)	// called by name (ADR-0055 item 5)
{
	int die_sides = oo::str::intValue(die_number);
	if (die_sides > 0)
	{
		int die_roll = 1 + (ranrot_rand() % die_sides);
		if (shipAI != nullptr)  shipAI->reactToMessage(oo::str::format("ROLL_%d", die_roll), "rollD:");
	}
	else
	{
		OO_LOG("ai.rollD.invalidValue", "***** ERROR: invalid value supplied to rollD: '{}'.", die_number);
	}
}


void ShipEntity::scanForNearestShipWithPrimaryRole(const std::string &scanRole)	// called by name (ADR-0055 item 5)
{
	scanForNearestShipWithPredicate(HasPrimaryRolePredicate, const_cast<std::string *>(&scanRole));	// the predicate reads a std::string
}


void ShipEntity::scanForNearestShipHavingRole(const std::string &scanRole)	// called by name (ADR-0055 item 5)
{
	scanForNearestShipWithPredicate(HasRolePredicate, const_cast<std::string *>(&scanRole));	// the predicate reads a std::string
}


void ShipEntity::scanForNearestShipWithAnyPrimaryRole(const std::string &scanRoles)	// called by name (ADR-0055 item 5)
{
	std::vector<std::string> roles = oo::str::tokens(scanRoles);	// the predicate reads the role strings
	scanForNearestShipWithPredicate(HasPrimaryRoleInSetPredicate, &roles);
}


void ShipEntity::scanForNearestShipHavingAnyRole(const std::string &scanRoles)	// called by name (ADR-0055 item 5)
{
	std::vector<std::string> roles = oo::str::tokens(scanRoles);	// the predicate reads the role strings
	scanForNearestShipWithPredicate(HasRoleInSetPredicate, &roles);
}


void ShipEntity::scanForNearestShipWithScanClass(const std::string &scanScanClass)	// called by name (ADR-0055 item 5)
{
	OOScanClass wantedClass = cxx_OOScanClassFromString(scanScanClass);	// the predicate reads an OOScanClass
	scanForNearestShipWithPredicate(HasScanClassPredicate, &wantedClass);
}


void ShipEntity::scanForNearestShipWithoutPrimaryRole(const std::string &scanRole)	// called by name (ADR-0055 item 5)
{
	scanForNearestShipWithNegatedPredicate(HasPrimaryRolePredicate, const_cast<std::string *>(&scanRole));	// the predicate reads a std::string
}


void ShipEntity::scanForNearestShipNotHavingRole(const std::string &scanRole)	// called by name (ADR-0055 item 5)
{
	scanForNearestShipWithNegatedPredicate(HasRolePredicate, const_cast<std::string *>(&scanRole));	// the predicate reads a std::string
}


void ShipEntity::scanForNearestShipWithoutAnyPrimaryRole(const std::string &scanRoles)	// called by name (ADR-0055 item 5)
{
	std::vector<std::string> roles = oo::str::tokens(scanRoles);	// the predicate reads the role strings
	scanForNearestShipWithNegatedPredicate(HasPrimaryRoleInSetPredicate, &roles);
}


void ShipEntity::scanForNearestShipNotHavingAnyRole(const std::string &scanRoles)	// called by name (ADR-0055 item 5)
{
	std::vector<std::string> roles = oo::str::tokens(scanRoles);	// the predicate reads the role strings
	scanForNearestShipWithNegatedPredicate(HasRoleInSetPredicate, &roles);
}


void ShipEntity::scanForNearestShipWithoutScanClass(const std::string &scanScanClass)	// called by name (ADR-0055 item 5)
{
	OOScanClass wantedClass = cxx_OOScanClassFromString(scanScanClass);	// the predicate reads an OOScanClass
	scanForNearestShipWithNegatedPredicate(HasScanClassPredicate, &wantedClass);
}


void ShipEntity::scanForNearestShipMatchingPredicate(const std::string &predicateExpression)	// called by name (ADR-0055 item 5)
{
	/*	Takes a boolean-valued JS expression where "ship" is the ship being
	 evaluated and "this" is our ship's ship script. the expression is
	 turned into a JS function of the form:
	 
	 function _oo_AIScanPredicate(ship)
	 {
	 return $expression;
	 }
	 
	 Examples of expressions:
	 ship.isWeapon
	 this.someComplicatedPredicate(ship)
	 function (ship) { ...do something complicated... } ()
	 */
	
	// Created on first use and never destroyed, as the dictionary it replaces (it holds JS functions).
	static std::map<std::string, oo::Ref<OOJSFunction>, std::less<>> *scriptCache = nullptr;
	std::string					key;
	oo::Ref<OOJSFunction>		function;
	ooscript::Context context = NULL;
	
	context = OOJSAcquireContext();
	
	const std::string &expression = predicateExpression;
	
	const std::optional<std::string> aiName = (getAI() != nullptr ? getAI()->name() : std::optional<std::string>());
#ifndef NDEBUG
	/*	In debug/test release builds, scripts are cached per AI in order to be
	 able to report errors correctly. For end-user releases, we only cache
	 one copy of each predicate, potentially leading to error messages for
	 the wrong AI.
	 */
	key = aiName.value_or("(null)") + "\n" + expression;
#else
	key = expression;
#endif
	
	// Look for cached function
	if (scriptCache != nullptr)
	{
		const auto cached = scriptCache->find(key);
		if (cached != scriptCache->end())  function = cached->second;
	}
	if (function == nullptr)
	{
		const char					*argNames[] = { "ship" };
		
		// Stuff expression in a function.
		const std::string predicateCode = "return " + expression + ";";
		function = OOJSFunction::initWithName(std::string("_oo_AIScanPredicate"),
											  NULL,
											  predicateCode,
											  1,
											  argNames,
											  aiName,
											  0,
											  context);
		
		// Cache function.
		if (function != nullptr)
		{
			if (scriptCache == nullptr)  scriptCache = new std::map<std::string, oo::Ref<OOJSFunction>, std::less<>>();
			(*scriptCache)[key] = function;
		}
	}
	
	if (function != nullptr)
	{
		ooscript::Object jsThis = nullptr;	// the ship's JS object, as OOJSObjectFromNativeObject() made of its object (bead oo-9ht.39.16)
		if (!ooscript::valueToObject(context, OOJSEntityJSValue(this, context), &jsThis))  jsThis = nullptr;
		JSFunctionPredicateParameter param =
		{
			.context = context,
			.function = function->functionValue(),
			.jsThis = jsThis,
			.errorFlag = NO
		};
		scanForNearestShipWithPredicate(JSFunctionPredicate, &param);
	}
	else
	{
		// Report error (once per occurrence)
		static std::set<std::string>	errorCache;
		
		if (!errorCache.contains(key))
		{
			OO_LOG("ai.scanForNearestShipMatchingPredicate.compile.failed", "Could not compile JavaScript predicate \"{}\" for AI {}.", predicateExpression, (getAI() != nullptr ? getAI()->name() : std::optional<std::string>()).value_or("(null)"));
			errorCache.insert(key);
		}
		
		// Select nothing
		_foundTarget = nullptr;
		if (getAI() != nullptr)  getAI()->message("NOTHING_FOUND");
	}
	
	ooscript::reportPendingException((context));
	OOJSRelinquishContext(context);
}


void ShipEntity::setCoordinates(const std::string &system_x_y_z)	// called by name (ADR-0055 item 5)
{
	const std::vector<std::string>	tokens = oo::str::tokens(system_x_y_z);
	
	if (tokens.size() != 4)
	{
		OO_LOG("ai.syntax.setCoordinates", "***** ERROR: cannot setCoordinates: '{}'.", system_x_y_z);
		return;
	}
	
	const std::string &systemString = tokens[0];
	std::string xString = tokens[1];
	if (oo::str::hasPrefix(xString, "rand:"))
		xString = oo::str::format("%.3f", bellf(RandArgument(xString)));
	std::string yString = tokens[2];
	if (oo::str::hasPrefix(yString, "rand:"))
		yString = oo::str::format("%.3f", bellf(RandArgument(yString)));
	std::string zString = tokens[3];
	if (oo::str::hasPrefix(zString, "rand:"))
		zString = oo::str::format("%.3f", bellf(RandArgument(zString)));
	
	// -floatValue
	HPVector posn = make_HPvector((float)oo::str::doubleValue(xString), (float)oo::str::doubleValue(yString), (float)oo::str::doubleValue(zString));
	GLfloat	scalar = 1.0;
	
	coordinates = (UNIVERSE != nullptr ? UNIVERSE->coordinatesForPosition(posn, systemString, &scalar) : HPVector{});
	
	if (shipAI != nullptr)  shipAI->message("APPROACH_COORDINATES");
}


void ShipEntity::checkForNormalSpace()
{
	if ((UNIVERSE != nullptr && UNIVERSE->sun() != nullptr) && (UNIVERSE != nullptr && UNIVERSE->planet() != nullptr))
		{ if (shipAI != nullptr)  shipAI->message("NORMAL_SPACE"); }
	else
		{ if (shipAI != nullptr)  shipAI->message("INTERSTELLAR_SPACE"); }
}


void ShipEntity::setTargetToRandomStation()
{
	/*- selects the nearest station it can find -*/
	int				ent_count = UNIVERSE->n_entities;
	Entity			**uni_entities = UNIVERSE->sortedEntities;	// grab the public sorted list
	std::vector<oo::Ref<Entity>>	my_entities(ent_count);	// kept for the search, as the objects were retained (bead oo-9ht.39.16)
	::StationEntity	*station = nil, *my_station = nil;
	double			maxRange2 = desired_range * desired_range;
	int				i;
	int				station_count = 0;
	
	for (i = 0; i < ent_count; i++)
	{
		// find stations within range but exclude carriers.
		if (uni_entities[i]->isStation)
		{
			my_station = oo::ToStation(uni_entities[i]);
			if ((my_station != nullptr ? my_station->getMaxFlightSpeed() : 0.0f) == 0 && (my_station != nullptr ? my_station->getHasNPCTraffic() : false) && HPdistance2(position, (my_station != nullptr ? my_station->getPosition() : HPVector{})) < maxRange2)
			{
				my_entities[station_count++] = oo::Ref<Entity>(uni_entities[i]);		//	retained
			}
		}
	}
	
	if (station_count != 0)
	{
		// select a random station
		station = oo::ToStation(my_entities[ranrot_rand() % station_count].get());
		// if more than one candidate do not select main station
		if (station == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr) && station_count > 1)
		{
			while (station == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr))
			{
				station = oo::ToStation(my_entities[ranrot_rand() % station_count].get());
			}
		}
	}
	
	for (i = 0; i < station_count; i++)
		my_entities[i] = nullptr;		//	released
	//
	if (station)
	{
		addTarget(station);
		setTargetStation(station);
		if (shipAI != nullptr)  shipAI->message("STATION_FOUND");
	}
	else
	{
		if (shipAI != nullptr)  shipAI->message("NO_STATION_IN_RANGE");
	}
}


void ShipEntity::setTargetToLastStation()
{
	Entity *station = targetStation();
	
	if (station != nil && (station != nullptr && station->getIsStation()))
	{
		addTarget(station);
	}
	else
	{
		if (shipAI != nullptr)  shipAI->message("NO_STATION_FOUND");
		setTargetStation(nullptr);
	}
	
}


void ShipEntity::addFuel(const std::string &fuel_number)	// called by name (ADR-0055 item 5)
{
	setFuel(getFuel() + oo::str::intValue(fuel_number) * 10);
}


void ShipEntity::scriptActionOnTarget(const std::string &action)	// called by name (ADR-0055 item 5)
{
	::PlayerEntity	*player = PLAYER;
	::ShipEntity		*targEnt = oo::ToShip(primaryTarget());
	::ShipEntity		*oldTarget = nil;
	
#ifndef NDEBUG
	static BOOL		deprecationWarning = NO;
	
	if (!deprecationWarning)
	{
		deprecationWarning = YES;
		OO_LOG("script.deprecated.scriptActionOnTarget", "----- WARNING in AI {}: the AI method scriptActionOnTarget: is deprecated and should not be used. It is slow and has unpredictable side effects. The recommended alternative is to use sendScriptMessage: to call a function in a ship's JavaScript ship script instead. scriptActionOnTarget: should not be used at all from scripts. An alternative is safeScriptActionOnTarget:, which is similar to scriptActionOnTarget: but has less side effects.", ::AI::currentlyRunningAIDescription().value_or("(null)"));
	}
	else
	{
		OO_LOG("script.deprecated.scriptActionOnTarget.repeat", "----- WARNING in AI {}: the AI method scriptActionOnTarget: is deprecated and should not be used.", ::AI::currentlyRunningAIDescription().value_or("(null)"));
	}
#endif
	
	if ((targEnt != nullptr ? targEnt->getIsShip() : false))
	{
		oldTarget = (player != nullptr ? player->scriptTarget() : (::ShipEntity *)nullptr);
		if (player != nullptr)  player->setScriptTarget(oo::ToShip(targEnt));
		if (player != nullptr)  player->runUnsanitizedScriptActions(oo::PList(oo::PList::Array{ oo::PList(action) }), YES, oo::str::format("<AI \"%s\" state %s - scriptActionOnTarget:>", (getAI() != nullptr ? getAI()->name() : std::optional<std::string>()).value_or("(null)").c_str(), (getAI() != nullptr ? getAI()->state() : std::optional<std::string>()).value_or("(null)").c_str()), targEnt);
		if (player != nullptr)  player->checkScript();	// react immediately to any changes this makes
		if (player != nullptr)  player->setScriptTarget(oldTarget);
	}
}


void ShipEntity::safeScriptActionOnTarget(const std::string &action)	// called by name (ADR-0055 item 5)
{
	::PlayerEntity	*player = PLAYER;
	::ShipEntity		*targEnt = oo::ToShip(primaryTarget());
	::ShipEntity		*oldTarget = nil;
	
	if ((targEnt != nullptr ? targEnt->getIsShip() : false))
	{
		oldTarget = (player != nullptr ? player->scriptTarget() : (::ShipEntity *)nullptr);
		if (player != nullptr)  player->setScriptTarget(oo::ToShip(targEnt));
		if (player != nullptr)  player->runUnsanitizedScriptActions(oo::PList(oo::PList::Array{ oo::PList(action) }), YES, oo::str::format("<AI \"%s\" state %s - safeScriptActionOnTarget:>", (getAI() != nullptr ? getAI()->name() : std::optional<std::string>()).value_or("(null)").c_str(), (getAI() != nullptr ? getAI()->state() : std::optional<std::string>()).value_or("(null)").c_str()), targEnt);
		if (player != nullptr)  player->setScriptTarget(oldTarget);
	}
}


// Send own ship script a message.
void ShipEntity::sendScriptMessage(const std::string &message)	// called by name (ADR-0055 item 5)
{
	const std::vector<std::string> components = oo::str::tokens(message);
	
	if (components.size() == 1)
	{
		doScriptEvent(cxx_OOJSIDFromString(message));
	}
	else if (!components.empty())	// (an empty message raised at -objectAtIndex:0)
	{
		const std::string &function = components[0];
		oo::PList::Array arguments;	// one argument: an array of the other components
		for (auto component = components.begin() + 1; component != components.end(); ++component)  arguments.emplace_back(*component);
		doScriptEvent(cxx_OOJSIDFromString(function), { oo::PList(std::move(arguments)) });
	}
}


void ShipEntity::ai_throwSparks()
{
	setThrowSparks(YES);
}


void ShipEntity::explodeSelf()
{
	getDestroyedBy(nullptr, kOODamageTypeEnergy);
}


void ShipEntity::ai_debugMessage(const std::string &message)	// called by name (ADR-0055 item 5)
{
	std::string desc = oo::str::format("%s %d", getName().value_or("(null)").c_str(), getUniversalID());
	if (getIsPlayer())  desc = "player autopilot";
	OO_LOG("ai.takeAction.debugMessage", "DEBUG: AI MESSAGE from {}: {}", desc, message);
}


// racing code TODO
void ShipEntity::targetFirstBeaconWithCode(const std::string &code)	// called by name (ADR-0055 item 5)
{
	const std::vector<oo::EntityHold> all_beacons = (UNIVERSE != nullptr ? UNIVERSE->listBeaconsWithCode(code) : std::vector<oo::EntityHold>());	// held C++ entities (bead oo-9ht.39.26)
	if (!all_beacons.empty())
	{
		addTarget(all_beacons[0].get());
		if (shipAI != nullptr)  shipAI->message("TARGET_FOUND");
	}
	else
		{ if (shipAI != nullptr)  shipAI->message("NOTHING_FOUND"); }
}


void ShipEntity::targetNextBeaconWithCode(const std::string &code)	// called by name (ADR-0055 item 5)
{
	const std::vector<oo::EntityHold> all_beacons = (UNIVERSE != nullptr ? UNIVERSE->listBeaconsWithCode(code) : std::vector<oo::EntityHold>());	// held C++ entities (bead oo-9ht.39.26)
	::ShipEntity		*current_beacon = oo::ToShip(primaryTarget());
	
	if ((!current_beacon)||(!(current_beacon != nullptr ? current_beacon->isBeacon() : false)))
	{
		if (shipAI != nullptr)  shipAI->message("NO_CURRENT_BEACON");
		if (shipAI != nullptr)  shipAI->message("NOTHING_FOUND");
		return;
	}
	
	// find the current beacon in the list..
	// -indexOfObject: (identity for entities)
	const auto found = std::find_if(all_beacons.begin(), all_beacons.end(), [current_beacon](const oo::EntityHold &beacon) { return beacon.get() == current_beacon; });
	NSUInteger i = found != all_beacons.end() ? (NSUInteger)(found - all_beacons.begin()) : NSNotFound;
	
	if (i == NSNotFound)
	{
		if (shipAI != nullptr)  shipAI->message("NOTHING_FOUND");
		return;
	}
	
	i++;	// next index
	
	if (i < all_beacons.size())
	{
		// locate current target in list
		addTarget(all_beacons[i].get());
		if (shipAI != nullptr)  shipAI->message("TARGET_FOUND");
	}
	else
	{
		if (shipAI != nullptr)  shipAI->message("LAST_BEACON");
		if (shipAI != nullptr)  shipAI->message("NOTHING_FOUND");
	}
}


void ShipEntity::setRacepointsFromTarget()
{
	// two point - one at z - cr one at z + cr
	::ShipEntity *ship = oo::ToShip(primaryTarget());
	if (ship == nil)
	{
		if (shipAI != nullptr)  shipAI->message("NOTHING_FOUND");
		return;
	}
	Vector k = ship->v_forward;
	GLfloat c = ship->collision_radius;
	HPVector o = ship->position;
	navpoints[0] = make_HPvector(o.x - c * k.x, o.y - c * k.y, o.z - c * k.z);
	navpoints[1] = make_HPvector(o.x + c * k.x, o.y + c * k.y, o.z + c * k.z);
	navpoints[2] = make_HPvector(o.x + 2.0 * c * k.x, o.y + 2.0 * c * k.y, o.z + 2.0 * c * k.z);
	number_of_navpoints = 2;
	next_navpoint_index = 0;
	_destination = navpoints[0];
	if (shipAI != nullptr)  shipAI->message("RACEPOINTS_SET");
}


void ShipEntity::performFlyRacepoints()
{
	next_navpoint_index = 0;
	desired_range = collision_radius;
	behaviour = BEHAVIOUR_FLY_THRU_NAVPOINTS;
}


