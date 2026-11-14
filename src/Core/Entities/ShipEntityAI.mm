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

#import "ShipEntityAI.h"

#include <vector>
#import "AI.h"
#import "OOMaths.h"
#import "Universe.h"

#import "OOJSFunction.h"
#import "OOJSScript.h"
#import "OOJavaScriptEngine.h"
#import "OOPlanetEntity.h"
#import "OOShipGroup.h"
#import "OOSunEntity.h"
#import "PlayerEntity.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "StationEntity.h"
#import "WormholeEntity.h"

#import "GameController.h"
#import "OOConstToJSString.h"
#import "OOConstToString.h"
#import "OOEntityFilterPredicate.h"
#import "OOStringExpander.h"
#import "OOStringParsing.h"
#import "ResourceManager.h"

#import "OOObjCPList.h"
#import "OOPListGameTypes.h"
#include "oofnd/Log.hpp"
#include "oofnd/String.hpp"

namespace {

// Whitespace without newlines: whiteSpaceAndNewline without U+000A-U+000D, U+0085, U+2028, U+2029
// (matches GNUstep's whitespaceCharacterSet table).
bool IsWhitespace(char16_t c)
{
    return oo::str::isWhitespaceOrNewline(c) && !((c >= 0x000A && c <= 0x000D) || c == 0x0085 || c == 0x2028 || c == 0x2029);
}

// A debug context "<description> suffix" in debug builds, nil (nullopt) otherwise.
std::optional<std::string> DebugContext(id entity, const char* suffix)
{
#ifndef NDEBUG
    return oo::str::format("%s %s", oo::ShortDescriptionOf(entity).c_str(), suffix);
#else
    (void)entity;
    (void)suffix;
    return std::nullopt;
#endif
}

// [[s componentsSeparatedByString:@":"] objectAtIndex:1] -intValue, for a "rand:N" coordinate.
int RandArgument(const std::string& token)
{
    const std::vector<std::string> parts = oo::str::split(token, ":");
    return parts.size() > 1 ? oo::str::intValue(parts[1]) : 0;
}

} // namespace

// Slice 1 of docs/phases/3-slices/ShipEntityAI.md (bead oo-iebuz): AI category, OOAIPrivate (ship
// and station) and the station stubs. Members of cxx::ShipEntity defined in the category's file
// (ADR-0056 amendment oo-o89 item 4); the facade forwards each selector (ShipEntity+ObjCBridge.mm);
// sends to self stay sends, so an Objective-C subclass's override still runs (amendment oo-mvzmb).
namespace cxx {

void ShipEntity::setAITo(const std::string& aiString) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    std::string ai = aiString;
    // don't try to load real AIs if the game hasn't started yet
    if (![PLAYER scriptsLoaded]) {
        ai = "oolite-nullAI.js";
    }
    if (oo::str::hasSuffix(ai, ".plist")) {
        [[self getAI] cxx_setStateMachine:ai withJSScript:"oolite-nullAI.js"];
        [self setAIScript:"oolite-nullAI.js"];
    } else if (oo::str::hasSuffix(ai, ".js")) {
        [[self getAI] cxx_setStateMachine:"nullAI.plist" withJSScript:ai];
        [self setAIScript:ai];
    } else {
        const std::optional<std::string> path = [::ResourceManager cxx_pathForFileNamed:ai + ".js" inFolder:std::string("AIs")];
        if (!path) // no js, use plist
        {
            [self setAITo:ai + ".plist"];
        } else {
            [self setAITo:ai + ".js"];
        }
    }
}

void ShipEntity::setAIScript(const std::string& aiString)
{
    ::ShipEntity* self = oo::ToObjC(this);
    const oo::PList properties(oo::PList::Dict { { "ship", oo::PListObject(self) } });

    [aiScript autorelease];
    aiScript = [::OOScript cxx_jsAIScriptFromFileNamed:aiString properties:properties];
    if (aiScript == nil) {
        OO_LOG("ai.load.failed.unknownAI", "Unable to load JS AI {} for ship {} ({} for role {})", aiString, oo::DescriptionOf(self), [self cxx_shipDataKey].value_or("(null)"), [self cxx_primaryRole].value_or("(null)"));
        aiScript = [::OOScript cxx_jsAIScriptFromFileNamed:"oolite-nullAI.js" properties:properties];
    } else {
        aiScriptWakeTime = 0;
        haveStartedJSAI = NO;
    }
    [aiScript retain];
}

void ShipEntity::switchAITo(const std::string& aiString) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    [self setAITo:aiString];
    [[self getAI] clearStack];
}

void ShipEntity::scanForHostiles()
{
    ::ShipEntity* self = oo::ToObjC(this);
    /*-- Locates all the ships in range targeting the receiver and chooses the nearest --*/
    DESTROY(_foundTarget);

    [self checkScanner];
    unsigned i;
    GLfloat found_d2 = scannerRange * scannerRange;
    for (i = 0; i < n_scanned_ships; i++) {
        ::ShipEntity* thing = scanned_ships[i];
        GLfloat d2 = distance2_scanned_ships[i];
        if ((d2 < found_d2)
            && ([thing isThargoid] || (([thing primaryTarget] == self) && [thing hasHostileTarget]) || [thing isDefenseTarget:self])
            && ![thing isCloaked]) {
            [self setFoundTarget:thing];
            found_d2 = d2;
        }
    }

    [self checkFoundTarget];
}

void ShipEntity::groupAttackTarget()
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::ShipEntity *target = nil, *ship = nil;

    target = [self primaryTarget];

    if (target == nil)
        return;

    if ([self group] == nil) // ship is alone!
    {
        [self setFoundTarget:target];
        [shipAI cxx_reactToMessage:"GROUP_ATTACK_TARGET" context:"groupAttackTarget"];
        [self doScriptEvent:OOJSID("helpRequestReceived") withArgument:self andArgument:target];
        return;
    }

    for (const oo::ObjCRef<::ShipEntity*>& member : [[self group] cxx_memberArray]) {
        ship = member.get();
        [ship setFoundTarget:target];
        [ship cxx_reactToAIMessage:"GROUP_ATTACK_TARGET" context:"groupAttackTarget"];
        [ship doScriptEvent:OOJSID("helpRequestReceived") withArgument:self andArgument:target];

        if ([ship escortGroup] != [ship group] && [[ship escortGroup] count] > 1) // Ship has a seperate escort group.
        {
            for (const oo::ObjCRef<::ShipEntity*>& escortRef : [[ship escortGroup] cxx_memberArrayExcludingLeader]) {
                ::ShipEntity* escort = escortRef.get();
                [escort setFoundTarget:target];
                [escort cxx_reactToAIMessage:"GROUP_ATTACK_TARGET" context:"groupAttackTarget"];
                [escort doScriptEvent:OOJSID("helpRequestReceived") withArgument:self andArgument:target];
            }
        }
    }
}

void ShipEntity::performAttack()
{
    if (behaviour != BEHAVIOUR_EVASIVE_ACTION) {
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
    if (behaviour != BEHAVIOUR_FORMATION_FORM_UP) {
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
    ::ShipEntity* self = oo::ToObjC(this);
    if (behaviour != BEHAVIOUR_FLEE_EVASIVE_ACTION) {
        behaviour = BEHAVIOUR_FLEE_TARGET;
        [self setEvasiveJink:400.0];
        frustration = 0.0;
        if (accuracy > COMBAT_AI_ISNT_AWFUL) {
            // alert! they've got us in their sights! react!!
            if ([self approachAspectToPrimaryTarget] > 0.9995) {
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
    ::ShipEntity* self = oo::ToObjC(this);
    ::OOPlanetEntity* nearest = [self findNearestPlanet];
    if (isNearPlanetSurface) {
        _destination = [nearest position];
        behaviour = BEHAVIOUR_LAND_ON_PLANET;
        planetForLanding = [nearest universalID];
    } else {
        behaviour = BEHAVIOUR_IDLE;
        [shipAI message:"NO_PLANET_NEARBY"];
    }

    frustration = 0.0;
}

void ShipEntity::performMining()
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::Entity* target = [self primaryTarget];
    // mining is not seen as hostile behaviour, so ensure it is only used against rocks.
    if (target && [target scanClass] == CLASS_ROCK) {
        behaviour = BEHAVIOUR_ATTACK_MINING_TARGET;
        frustration = 0.0;
    } else {
        [self noteLostTargetAndGoIdle];
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
    stick_roll = max_flight_roll * 2.0 * (randf() - 0.5);
    stick_pitch = max_flight_pitch * 2.0 * (randf() - 0.5);
    behaviour = BEHAVIOUR_TUMBLE;
    frustration = 0.0;
}

bool ShipEntity::performHyperSpaceToSpecificSystem(OOSystemID systemID)
{
    ::ShipEntity* self = oo::ToObjC(this);
    return [self performHyperSpaceExitReplace:NO toSystem:systemID];
}

void ShipEntity::requestDockingCoordinates()
{
    ::ShipEntity* self = oo::ToObjC(this);
    /*-	requests coordinates from the target station
     if the target station can't be found
     then use the nearest it can find (which may be a rock hermit) -*/

    ::StationEntity* station = nil;
    ::Entity* targStation = nil;
    double distanceToStation2 = 0.0;

    targStation = [self targetStation];
    if ([targStation isStation]) {
        station = (::StationEntity*)targStation;
    } else {
        station = [UNIVERSE nearestShipMatchingPredicate:IsStationPredicate
                                               parameter:nil
                                        relativeToEntity:self];
    }

    distanceToStation2 = HPdistance2([station position], [self position]);

    // Player check for being inside the aegis already exists in PlayerEntityControls. We just
    // check here that distance to station is less than 2.5 times scanner range to avoid problems with
    // NPC ships getting stuck with a dockingAI while just outside the aegis - Nikos 20090630, as proposed by Eric
    // On very busy systems (> 50 docking ships) docking ships can be sent to a hold position outside the range,
    // so also test for presence of dockingInstructions. - Eric 20091130
    if (station != nil && (distanceToStation2 < SCANNER_MAX_RANGE2 * 6.25 || !dockingInstructions.isNull())) {
        // remember the instructions (the station's weak reference is kept as an Object node)
        dockingInstructions = [station dockingInstructionsForShip:self];
        if (!dockingInstructions.isNull()) {
            [self recallDockingInstructions];

            // the strings the instructions hold (StationEntity -dockingInstructionsForShip:), sent as before (absent: nothing)
            const oo::PList* aiMessage = dockingInstructions.find("ai_message");
            if (aiMessage != nullptr && aiMessage->isString())
                [shipAI message:*aiMessage->getIf<std::string>()];
            const oo::PList* commsMessage = dockingInstructions.find("comms_message");
            if (commsMessage != nullptr && commsMessage->isString())
                [station cxx_sendExpandedMessage:*commsMessage->getIf<std::string>() toShip:self];
        }
    } else {
        dockingInstructions = oo::PList();
    }

    if (dockingInstructions.isNull()) {
        [shipAI message:"NO_STATION_FOUND"];
    }
}

void ShipEntity::recallDockingInstructions()
{
    ::ShipEntity* self = oo::ToObjC(this);
    if (!dockingInstructions.isNull()) {
        const oo::PList* destination = dockingInstructions.find("destination");
        _destination = OOHPVectorFromPList(destination, kZeroHPVector);
        desired_speed = fmin(dockingInstructions.get<float>("speed"), maxFlightSpeed);
        desired_range = dockingInstructions.get<float>("range");
        if (const oo::PList* stationRef = dockingInstructions.find("station")) {
            ::StationEntity* targetStation = [oo::ObjectIn(*stationRef) weakRefUnderlyingObject];
            if (targetStation != nil) {
                [self addTarget:targetStation];
                [self setTargetStation:targetStation];
            } else {
                [self removeTarget:[self primaryTarget]];
            }
        }
        docking_match_rotation = dockingInstructions.get<bool>("match_rotation");
    }
}

void ShipEntity::scanForNearestIncomingMissile()
{
    ::ShipEntity* self = oo::ToObjC(this);
    OOScanClass missileClass = CLASS_MISSILE;
    BinaryOperationPredicateParameter param = {
        HasScanClassPredicate, &missileClass, // the predicate reads an OOScanClass
        IsHostileAgainstTargetPredicate, self
    };
    [self scanForNearestShipWithPredicate:ANDPredicate parameter:&param];
}

void ShipEntity::enterPlayerWormhole()
{
    ::ShipEntity* self = oo::ToObjC(this);
    [self enterWormhole:[PLAYER wormhole] replacing:NO];
}

void ShipEntity::enterTargetWormhole()
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::WormholeEntity* whole = nil;
    ::ShipEntity* targEnt = [self primaryTarget];
    double found_d2 = scannerRange * scannerRange;

    if (targEnt && (HPdistance2(position, [targEnt position]) < found_d2)) {
        if ([targEnt isWormhole])
            whole = (::WormholeEntity*)targEnt;
        else if ([targEnt isPlayer])
            whole = [PLAYER wormhole];
    }

    if (!whole) {
        // locate nearest wormhole
        int ent_count = UNIVERSE->_cxxUniverse->n_entities;
        ::Entity** uni_entities = UNIVERSE->_cxxUniverse->sortedEntities; // grab the public sorted list
        std::vector<::WormholeEntity*> wormholes(ent_count);
        int i;
        int wh_count = 0;
        for (i = 0; i < ent_count; i++)
            if (uni_entities[i]->_cxxEntity->isWormhole)
                wormholes[wh_count++] = [(::WormholeEntity*)uni_entities[i] retain];
        //
        // double found_d2 = scannerRange * scannerRange;
        for (i = 0; i < wh_count; i++) {
            ::WormholeEntity* wh = wormholes[i];
            double d2 = HPdistance2(position, wh->_cxxEntity->position);
            if (d2 < found_d2) {
                whole = wh;
                found_d2 = d2;
            }
            [wh release];
        }
    }

    [self enterWormhole:whole replacing:NO];
}

// FIXME: resolve this stuff.
void ShipEntity::wormholeEscorts()
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::ShipEntity* ship = nil;
    ::WormholeEntity* whole = nil;

    whole = [self primaryTarget];
    if (![whole isWormhole])
        return;

    const std::optional<std::string> context = DebugContext(self, "wormholeEscorts");

    for (const auto& shipRef : [self cxx_escorts]) {
        ship = shipRef.get();
        [ship addTarget:whole];
        [ship cxx_reactToAIMessage:"ENTER WORMHOLE" context:context];
        [ship doScriptEvent:OOJSID("wormholeSuggested") withArgument:whole];
    }

    // We now have no escorts..

    [_escortGroup release];
    _escortGroup = nil;
}

void ShipEntity::wormholeEntireGroup()
{
    ::ShipEntity* self = oo::ToObjC(this);
    [self wormholeGroup];
    [self wormholeEscorts];
}

bool ShipEntity::suggestEscortTo(::ShipEntity* mother)
{
    ::ShipEntity* self = oo::ToObjC(this);
    if (mother) {
#ifdef OO_DEBUG_MONITOR_ENABLED
        if (reportAIMessages) {
            OO_LOG("ai.suggestEscort", "DEBUG: {} suggests escorting {}", oo::DescriptionOf(self), oo::DescriptionOf(mother));
        }
#endif

        if ([mother acceptAsEscort:self]) {
            // copy legal status across
            if (([mother legalStatus] > 0) && (bounty <= 0)) {
                int extra = 1 | (ranrot_rand() & 15);
                //				[mother setBounty: [mother legalStatus] + extra withReason:kOOLegalStatusReasonAssistingOffender];
                [self markAsOffender:extra withReason:kOOLegalStatusReasonAssistingOffender];
                //				bounty += extra;	// obviously we're dodgier than we thought!
            }

            [self setOwner:mother];
            [self setGroup:[mother escortGroup]];
            [shipAI message:"ESCORTING"];
            return YES;
        }

#ifdef OO_DEBUG_MONITOR_ENABLED
        if (reportAIMessages) {
            OO_LOG("ai.suggestEscort.refused", "DEBUG: {} refused by {}", oo::DescriptionOf(self), oo::DescriptionOf(mother));
        }
#endif
    }
    [self setOwner:self];
    [shipAI message:"NOT_ESCORTING"];
    [self doScriptEvent:OOJSID("escortRejected") withArgument:mother];
    return NO;
}

void ShipEntity::broadcastDistressMessage()
{
    ::ShipEntity* self = oo::ToObjC(this);
    /*-- Locates all the stations, bounty hunters and police ships in range and tells them that you are under attack --*/
    [self broadcastDistressMessageWithDumping:YES];
}

void ShipEntity::broadcastDistressMessageWithDumping(bool dumpCargo)
{
    ::ShipEntity* self = oo::ToObjC(this);
    [self checkScannerIgnoringUnpowered];
    DESTROY(_foundTarget);

    ::ShipEntity* aggressor_ship = (::ShipEntity*)[self primaryAggressor];
    if (aggressor_ship == nil)
        return;

    // don't send too many distress messages at once, space them out semi-randomly
    if (messageTime > 2.0 * randf())
        return;

    BOOL is_buoy = (scanClass == CLASS_BUOY);
    const char* distress_message = is_buoy ? "[buoy-distress-call]" : "[distress-call]";

    unsigned i;
    for (i = 0; i < n_scanned_ships; i++) {
        ::ShipEntity* ship = scanned_ships[i];

        // dump cargo if energy is low
        if (dumpCargo && !is_buoy && [self primaryAggressor] == ship && energy < 0.375 * maxEnergy) {
            [self ejectCargo];
            [self performFlee];
        }

        // tell it! (only plist AIs send comms here; JS AIs are
        // expected to handle their own)
        if (ship->_cxxEntity->isPlayer && ![self hasNewAI]) {
            [ship doScriptEvent:OOJSID("distressMessageReceived") withArgument:aggressor_ship andArgument:self];

            if (!is_buoy && [self primaryAggressor] == ship && energy < 0.375 * maxEnergy) {
                [self cxx_sendExpandedMessage:"[beg-for-mercy]" toShip:ship];
            } else if ([self bounty] == 0) {
                // only send distress message to player if plausibly sending
                // one more generally
                [self cxx_sendExpandedMessage:distress_message toShip:ship];
            }

            // reset the thanked_ship_id
            DESTROY(_thankedShip);
        } else if ([self bounty] == 0 && [ship cxx_crew].has_value()) // Only clean ships can have their distress calls accepted
        {
            [ship doScriptEvent:OOJSID("distressMessageReceived") withArgument:aggressor_ship andArgument:self];

            // we only can send distressMessages to ships that are known to have a "ACCEPT_DISTRESS_CALL" reaction
            // in their AI, or they might react wrong on the added found_target.

            // ship must have a plist AI for this next bit. JS AIs
            // should already have done something sensible on
            // distressMessageReceived
            if (![self hasNewAI]) {
                // FIXME: this test only works with core AIs
                if (ship->_cxxEntity->isStation || [ship cxx_hasPrimaryRole:"police"] || [ship cxx_hasPrimaryRole:"hunter"]) {
                    [ship acceptDistressMessageFrom:self];
                }
            }
        }
    }
}

void ShipEntity::checkFoundTarget()
{
    ::ShipEntity* self = oo::ToObjC(this);
    if ([self foundTarget] != nil) {
        [shipAI message:"TARGET_FOUND"];
    } else {
        [shipAI message:"NOTHING_FOUND"];
    }
}

bool ShipEntity::performHyperSpaceExitReplace(bool replace)
{
    ::ShipEntity* self = oo::ToObjC(this);
    return [self performHyperSpaceExitReplace:replace toSystem:-1];
}

bool ShipEntity::performHyperSpaceExitReplace(bool replace, OOSystemID systemID)
{
    ::ShipEntity* self = oo::ToObjC(this);
    if (![self hasHyperspaceMotor]) {
        [shipAI cxx_reactToMessage:"WITCHSPACE UNAVAILABLE" context:"performHyperSpaceExit"];
        return NO;
    }
    if ([self status] == STATUS_ENTERING_WITCHSPACE) {
        // already in a wormhole
        return NO;
    }

    OOSystemID targetSystem;
    NSUInteger i = 0;

    // get a list of destinations within range
    const oo::PList sDests = [UNIVERSE cxx_nearbyDestinationsWithinRange:0.1f * fuel];
    NSUInteger n_dests = sDests.count();

    // if none available report to the AI and exit
    if (n_dests == 0) {
        [shipAI cxx_reactToMessage:"WITCHSPACE UNAVAILABLE" context:"performHyperSpaceExit"];

        // If no systems exist near us, the AI is switched to a different state, so we do not need
        // the nearby destinations array anymore.
        return NO;
    }

    // check if we're clear of nearby masses
    ::ShipEntity* blocker = [UNIVERSE entityForUniversalID:[self checkShipsInVicinityForWitchJumpExit]];
    if (blocker) {
        [self setFoundTarget:blocker];
        [shipAI cxx_reactToMessage:"WITCHSPACE BLOCKED" context:"performHyperSpaceExit"];
        [self doScriptEvent:OOJSID("shipWitchspaceBlocked") withArgument:blocker];

        return NO;
    }

    if (systemID == -1) {
        // select one at random
        if (n_dests > 1) {
            i = ranrot_rand() % n_dests;
        }

        targetSystem = sDests.at(i)->get<int>("sysID");
    } else {
        targetSystem = systemID;

        for (i = 0; i < n_dests; i++) {
            if (systemID == sDests.at(i)->get<int>("sysID"))
                break;
        }

        if (i == n_dests) // no match found
        {
            return NO;
        }
    }
    float dist = sDests.at(i)->get<float>("distance");
    if (dist > [self maxHyperspaceDistance] || dist > fuel / 10.0f) {
        OO_LOG_WARN("script.debug", "DEBUG: {} Jumping {:f} which is further than allowed.  I have {} fuel", oo::DescriptionOf(self), dist, fuel);
    }
    fuel -= 10 * dist;

    // create wormhole
    ::WormholeEntity* whole = [[[::WormholeEntity alloc] initWormholeTo:targetSystem fromShip:self] autorelease];
    [UNIVERSE addEntity:whole];

    [self enterWormhole:whole replacing:replace];

    // we've no need for the destinations array anymore.
    return YES;
}

void ShipEntity::scanForNearestShipWithPredicate(EntityFilterPredicate predicate, void* parameter)
{
    ::ShipEntity* self = oo::ToObjC(this);
    // Locates all the ships in range for which predicate returns YES, and chooses the nearest.
    unsigned i;
    ::ShipEntity* candidate;
    float d2, found_d2 = scannerRange * scannerRange;

    DESTROY(_foundTarget);
    [self checkScanner];

    if (predicate == NULL)
        return;

    for (i = 0; i < n_scanned_ships; i++) {
        candidate = scanned_ships[i];
        d2 = distance2_scanned_ships[i];
        if ((d2 < found_d2) && (candidate->_cxxEntity->scanClass != CLASS_CARGO) && ([candidate status] != STATUS_DOCKED)
            && predicate(candidate, parameter) && ![candidate isCloaked]) {
            [self setFoundTarget:candidate];
            found_d2 = d2;
        }
    }

    [self checkFoundTarget];
}

void ShipEntity::scanForNearestShipWithNegatedPredicate(EntityFilterPredicate predicate, void* parameter)
{
    ::ShipEntity* self = oo::ToObjC(this);
    ChainedEntityPredicateParameter param = { predicate, parameter };
    [self scanForNearestShipWithPredicate:NOTPredicate parameter:&param];
}

void ShipEntity::acceptDistressMessageFrom(::ShipEntity* other)
{
    ::ShipEntity* self = oo::ToObjC(this);
    [self setFoundTarget:[other primaryTarget]];
    if ([self isPolice]) {
        [(::ShipEntity*)[self foundTarget] markAsOffender:8 withReason:kOOLegalStatusReasonDistressCall]; // you have been warned!!
    }

    [shipAI cxx_reactToMessage:"ACCEPT_DISTRESS_CALL" context:DebugContext(other, "broadcastDistressMessage")];
}

} // namespace cxx

// The category ShipEntity (OOAIStationStubs): AI methods for stations, which have no effect on
// normal ships (StationEntity's own answer them for a station). They were generated by the
// STATION_STUB_* macros; as members they are written out.
namespace {

void LogNotAStation(cxx::ShipEntity* ship, const char* method)
{
    OO_LOG("ai.invalid.notAStation", "Attempt to use station AI method \"{}\" on non-station {}.", method, oo::DescriptionOf(oo::ToObjC(ship)));
}

} // namespace

namespace cxx {

void ShipEntity::increaseAlertLevel() { LogNotAStation(this, "increaseAlertLevel"); }
void ShipEntity::decreaseAlertLevel() { LogNotAStation(this, "decreaseAlertLevel"); }

oo::PList ShipEntity::launchPolice() // called by name (ADR-0055 item 5): StationEntity's returns the ships launched
{
    LogNotAStation(this, "launchPolice");
    return oo::PList();
}

void ShipEntity::launchDefenseShip() { LogNotAStation(this, "launchDefenseShip"); }
void ShipEntity::launchScavenger() { LogNotAStation(this, "launchScavenger"); }
void ShipEntity::launchMiner() { LogNotAStation(this, "launchMiner"); }
void ShipEntity::launchPirateShip() { LogNotAStation(this, "launchPirateShip"); }
void ShipEntity::launchShuttle() { LogNotAStation(this, "launchShuttle"); }
void ShipEntity::launchTrader() { LogNotAStation(this, "launchTrader"); }
void ShipEntity::launchEscort() { LogNotAStation(this, "launchEscort"); }

bool ShipEntity::launchPatrol()
{
    LogNotAStation(this, "launchPatrol");
    return NO;
}

void ShipEntity::launchShipWithRole(const std::string& /* param */) { LogNotAStation(this, "launchShipWithRole:"); } // called by name (ADR-0055 item 5)
void ShipEntity::abortAllDockings() { LogNotAStation(this, "abortAllDockings"); }

// The station's unit of the category StationEntity (OOAIPrivate), overriding the ship's.
void StationEntity::acceptDistressMessageFrom(::ShipEntity* other)
{
    ::StationEntity* self = oo::ToObjC(this);
    if (self != [UNIVERSE station])
        return;

    ::OOWeakReference* old_target = _primaryTarget;
    _primaryTarget = [[[other primaryTarget] weakRetain] autorelease];
    [(::ShipEntity*)[other primaryTarget] markAsOffender:8 withReason:kOOLegalStatusReasonDistressCall]; // mark their card
    [self launchDefenseShip];
    _primaryTarget = old_target;
}

} // namespace cxx

// Slice 2 of docs/phases/3-slices/ShipEntityAI.md (bead oo-xurzn): PureAI part 1: state, speed,
// scans for prey and loot, planets, legal status. Members of cxx::ShipEntity defined in the
// category's file (ADR-0056 amendment oo-o89 item 4); the facade forwards each selector
// (ShipEntity+ObjCBridge.mm); sends to self stay sends, so an Objective-C subclass's override still
// runs (amendment oo-mvzmb).
namespace cxx {

void ShipEntity::setStateTo(const std::string& state) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    [[self getAI] cxx_setState:state];
}

void ShipEntity::pauseAI(const std::string& intervalString) // called by name (ADR-0055 item 5)
{
    [shipAI setNextThinkTime:[UNIVERSE getTime] + oo::str::doubleValue(intervalString)];
}

void ShipEntity::randomPauseAI(const std::string& intervalString) // called by name (ADR-0055 item 5)
{
    const std::vector<std::string> tokens = oo::str::tokens(intervalString);
    double start, end;

    if (tokens.size() != 2) {
        OO_LOG("ai.syntax.randomPauseAI", "***** ERROR: cannot read min and max value for randomPauseAI:, needs 2 values: '{}'.", intervalString);
        return;
    }

    start = oo::str::doubleValue(tokens[0]); // -oo_doubleAtIndex:
    end = oo::str::doubleValue(tokens[1]);

    [shipAI setNextThinkTime:[UNIVERSE getTime] + (start + (end - start) * randf())];
}

void ShipEntity::dropMessages(const std::string& messageString) // called by name (ADR-0055 item 5)
{
    for (const std::string& message : oo::str::split(messageString, ",")) {
        [shipAI cxx_dropMessage:oo::str::trimTrailing(oo::str::trimLeading(message, IsWhitespace), IsWhitespace)];
    }
}

void ShipEntity::debugDumpPendingMessages()
{
    [shipAI debugDumpPendingMessages];
}

void ShipEntity::setDestinationToCurrentLocation()
{
    // randomly add a .5m variance
    _destination = HPvector_add(position, OOHPVectorRandomSpatial(0.5));
}

void ShipEntity::setDestinationToJinkPosition()
{
    ::ShipEntity* self = oo::ToObjC(this);
    Vector front = vector_multiply_scalar([self forwardVector], flightSpeed / max_flight_pitch * 2);
    _destination = HPvector_add(position, vectorToHPVector(vector_add(front, OOVectorRandomSpatial(100))));
    pitching_over = YES; // don't complete roll first, but immediately start with pitching.
}

void ShipEntity::setDesiredRangeTo(const std::string& rangeString) // called by name (ADR-0055 item 5)
{
    desired_range = oo::str::doubleValue(rangeString);
}

void ShipEntity::setDesiredRangeForWaypoint()
{
    desired_range = fmax(maxFlightSpeed / max_flight_pitch / 6, 50.0); // some ships need a longer range to reach a waypoint.
}

void ShipEntity::setSpeedTo(const std::string& speedString) // called by name (ADR-0055 item 5)
{
    desired_speed = oo::str::doubleValue(speedString);
}

void ShipEntity::setSpeedFactorTo(const std::string& speedString) // called by name (ADR-0055 item 5)
{
    desired_speed = maxFlightSpeed * oo::str::doubleValue(speedString);
}

void ShipEntity::setSpeedToCruiseSpeed()
{
    desired_speed = cruiseSpeed;
}

void ShipEntity::setThrustFactorTo(const std::string& thrustFactorString) // called by name (ADR-0055 item 5)
{
    thrust = OOClamp_0_1_f(oo::str::doubleValue(thrustFactorString)) * max_thrust;
}

void ShipEntity::setTargetToPrimaryAggressor()
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::Entity* primeAggressor = [self primaryAggressor];
    if (!primeAggressor)
        return;
    if ([self primaryTarget] == primeAggressor)
        return;

    // a more considered approach here:
    // if we're already busy attacking a target we don't necessarily want to break off
    //
    if ([self hasHostileTarget] && randf() < 0.75) // if I'm attacking, ignore 75% of new aggressor's attacks
    {
        // but add them as a secondary target anyway
        [self addDefenseTarget:(::ShipEntity*)primeAggressor];
        return;
    }
    // react only if the primary aggressor is not a friendly ship, else ignore it
    if ([primeAggressor isShip] && ![(::ShipEntity*)primeAggressor isFriendlyTo:self]) {
        // inform our old target of our new target
        //
        ::Entity* primeTarget = [self primaryTarget];
        if ((primeTarget) && (primeTarget->_cxxEntity->isShip)) {
            ::ShipEntity* currentShip = [self primaryTarget];
            [[currentShip getAI] message:oo::str::format("%s %d %d", std::string(AIMS_AGGRESSOR_SWITCHED_TARGET).c_str(), universalID, [[self primaryAggressor] universalID])];
            [currentShip doScriptEvent:OOJSID("shipAttackerDistracted") withArgument:[self primaryAggressor]];
        }

        // okay, so let's now target the aggressor
        [self addTarget:[self primaryAggressor]];
    }
}

void ShipEntity::addPrimaryAggressorAsDefenseTarget()
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::Entity* primeAggressor = [self primaryAggressor];
    if (!primeAggressor)
        return;
    if ([self isDefenseTarget:primeAggressor])
        return;

    if ([primeAggressor isShip] && ![(::ShipEntity*)primeAggressor isFriendlyTo:self]) {
        [self addDefenseTarget:primeAggressor];
    }
}

void ShipEntity::scanForNearestMerchantman()
{
    ::ShipEntity* self = oo::ToObjC(this);
    float d2, found_d2;
    unsigned i;
    ::ShipEntity* ship = nil;

    //-- Locates the nearest merchantman in range.
    [self checkScannerIgnoringUnpowered];

    found_d2 = scannerRange * scannerRange;
    DESTROY(_foundTarget);

    for (i = 0; i < n_scanned_ships; i++) {
        ship = scanned_ships[i];
        if ([ship isPirateVictim] && ([ship status] != STATUS_DEAD) && ([ship status] != STATUS_DOCKED) && ![ship isCloaked]) {
            d2 = distance2_scanned_ships[i];
            if (PIRATES_PREFER_PLAYER && (d2 < desired_range * desired_range) && ship->_cxxEntity->isPlayer && [self isPirate]) {
                d2 = 0.0;
            } else
                d2 = distance2_scanned_ships[i];
            if (d2 < found_d2) {
                found_d2 = d2;
                [self setFoundTarget:ship];
            }
        }
    }
    [self checkFoundTarget];
}

void ShipEntity::scanForRandomMerchantman()
{
    ::ShipEntity* self = oo::ToObjC(this);
    unsigned n_found, i;

    //-- Locates one of the merchantman in range.
    [self checkScannerIgnoringUnpowered];
    std::vector<::ShipEntity*> ids_found(n_scanned_ships);

    n_found = 0;
    DESTROY(_foundTarget);
    for (i = 0; i < n_scanned_ships; i++) {
        ::ShipEntity* ship = scanned_ships[i];
        if (([ship status] != STATUS_DEAD) && ([ship status] != STATUS_DOCKED) && [ship isPirateVictim] && ![ship isCloaked])
            ids_found[n_found++] = ship;
    }
    if (n_found == 0) {
        [shipAI message:"NOTHING_FOUND"];
    } else {
        i = ranrot_rand() % n_found; // pick a number from 0 -> (n_found - 1)
        [self setFoundTarget:ids_found[i]];
        [shipAI message:"TARGET_FOUND"];
    }
}

void ShipEntity::scanForLoot()
{
    ::ShipEntity* self = oo::ToObjC(this);
    /*-- Locates the nearest debris in range --*/
    if (!isStation) {
        if (![self hasCargoScoop]) {
            [shipAI message:"NOTHING_FOUND"]; // can't collect loot if you have no scoop!
            return;
        }
        if ([self cxx_cargoCount] >= [self maxAvailableCargoSpace]) {
            if (max_cargo)
                [shipAI message:"HOLD_FULL"]; // can't collect loot if holds are full!
            [shipAI message:"NOTHING_FOUND"]; // can't collect loot if holds are full!
            return;
        }
    } else {
        if (magnitude2([self velocity])) {
            [shipAI message:"NOTHING_FOUND"]; // can't collect loot if you're a moving station
            return;
        }
    }

    [self checkScanner];

    double found_d2 = scannerRange * scannerRange;
    DESTROY(_foundTarget);
    unsigned i;
    for (i = 0; i < n_scanned_ships; i++) {
        ::ShipEntity* other = (::ShipEntity*)scanned_ships[i];
        if ([other scanClass] == CLASS_CARGO && [other cargoType] != CARGO_NOT_CARGO && [other status] != STATUS_BEING_SCOOPED) {
            if ((![self isPolice]) || ([other cxx_commodityType] == "slaves")) // police only rescue lifepods and slaves
            {
                GLfloat d2 = distance2_scanned_ships[i];
                if (d2 < found_d2) {
                    found_d2 = d2;
                    [self setFoundTarget:other];
                }
            }
        }
    }
    [self checkFoundTarget];
}

void ShipEntity::scanForRandomLoot()
{
    ::ShipEntity* self = oo::ToObjC(this);
    /*-- Locates the all debris in range and chooses a piece at random from the first sixteen found --*/
    if (![self isStation] && ![self hasCargoScoop]) {
        [shipAI message:"NOTHING_FOUND"]; // can't collect loot if you have no scoop!
        return;
    }
    //
    [self checkScanner];
    //
    ::ShipEntity* thing_uids_found[16];
    unsigned things_found = 0;
    DESTROY(_foundTarget);
    unsigned i;
    for (i = 0; (i < n_scanned_ships) && (things_found < 16); i++) {
        ::ShipEntity* other = scanned_ships[i];
        if ([other scanClass] == CLASS_CARGO && [other cargoType] != CARGO_NOT_CARGO && [other status] != STATUS_BEING_SCOOPED) {
            thing_uids_found[things_found++] = other;
        }
    }

    if (things_found != 0) {
        [self setFoundTarget:thing_uids_found[ranrot_rand() % things_found]];
        [shipAI message:"TARGET_FOUND"];
    } else
        [shipAI message:"NOTHING_FOUND"];
}

void ShipEntity::setTargetToFoundTarget()
{
    ::ShipEntity* self = oo::ToObjC(this);
    if ([self foundTarget] != nil) {
        [self addTarget:[self foundTarget]];
    } else {
        [shipAI message:"TARGET_LOST"]; // to prevent the ship going for a wrong, previous target. Should not be a reactToMessage.
    }
}

void ShipEntity::addFoundTargetAsDefenseTarget()
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::Entity* fTarget = [self foundTarget];
    if (fTarget != nil) {
        if ([fTarget isShip] && ![(::ShipEntity*)fTarget isFriendlyTo:self]) {
            [self addDefenseTarget:fTarget];
        }
    }
}

void ShipEntity::checkForFullHold()
{
    ::ShipEntity* self = oo::ToObjC(this);
    if (!max_cargo) {
        [shipAI message:"NO_CARGO_BAY"];
    } else if ([self cxx_cargoCount] >= [self maxAvailableCargoSpace]) {
        [shipAI message:"HOLD_FULL"];
    } else {
        [shipAI message:"HOLD_NOT_FULL"];
    }
}

void ShipEntity::getWitchspaceEntryCoordinates()
{
    ::ShipEntity* self = oo::ToObjC(this);
    /*- calculates coordinates from the nearest station it can find, or just fly 10s forward -*/
    if (!UNIVERSE) {
        Vector vr = vector_multiply_scalar(v_forward, maxFlightSpeed * 10.0); // 10 second flying away
        coordinates = HPvector_add(position, vectorToHPVector(vr));
        return;
    }
    //
    // find the nearest station...
    //
    // we don't use "checkScanner" because we must rely on finding a present station.
    //
    ::StationEntity* station = nil;
    station = [UNIVERSE nearestShipMatchingPredicate:IsStationPredicate
                                           parameter:nil
                                    relativeToEntity:self];

    if (station && HPdistance2([station position], position) < SCANNER_MAX_RANGE2) // there is a station in range.
    {
        Vector vr = vector_multiply_scalar([station rightVector], 10000); // 10km from station
        coordinates = HPvector_add([station position], vectorToHPVector(vr));
    } else {
        Vector vr = vector_multiply_scalar(v_forward, maxFlightSpeed * 10.0); // 10 second flying away
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
    ::ShipEntity* self = oo::ToObjC(this);
    // find an incoming missile...
    //
    ::ShipEntity* missile = nil;
    unsigned i;
    ::ShipEntity* escort = nil;
    ::ShipEntity* target = nil;

    [self checkScannerIgnoringUnpowered];
    for (i = 0; (i < n_scanned_ships) && (missile == nil); i++) {
        ::ShipEntity* thing = scanned_ships[i];
        if (thing->_cxxEntity->scanClass == CLASS_MISSILE) {
            target = [thing primaryTarget];

            if (target == self) {
                missile = thing;
            } else {
                for (const auto& escortRef : [self cxx_escorts]) {
                    escort = escortRef.get();
                    if (target == escort) {
                        missile = thing;
                    }
                }
            }
        }
    }

    if (missile == nil)
        return;

    [self addTarget:missile];
    [self addDefenseTarget:missile];

    // Notify own ship script that we are being attacked.
    ::ShipEntity* hunter = [missile owner];
    [self doScriptEvent:OOJSID("shipBeingAttacked") withArgument:hunter];
    [hunter doScriptEvent:OOJSID("shipAttackedOther") withArgument:self];

    if ([self isPolice]) {
        // Notify other police in group of attacker.
        // Note: prior to 1.73 this was done only if we had ECM.
        ::ShipEntity* police = nil;

        for (const oo::ObjCRef<::ShipEntity*>& member : [[self group] cxx_memberArray]) {
            police = member.get();
            [police setFoundTarget:hunter];
            [police setPrimaryAggressor:hunter];
        }
    }

    // if I'm a copper and you're not, then mark the other as an offender!
    if ([self isPolice] && ![hunter isPolice])
        [hunter markAsOffender:64 withReason:kOOLegalStatusReasonAttackedPolice];

    if ([self hasECM]) {
        // use the ECM and battle on

        [self setPrimaryAggressor:hunter]; // lets get them now for that!
        [self setFoundTarget:hunter];

        [self fireECM];
        return;
    }

    // RUN AWAY !!
    desired_range = 10000;
    [self performFlee];
    [shipAI message:"FLEEING"];
}

void ShipEntity::setCourseToPlanet()
{
    ::ShipEntity* self = oo::ToObjC(this);
    /*- selects the nearest planet it can find -*/
    ::OOPlanetEntity* the_planet = [self findNearestPlanetExcludingMoons];
    if (the_planet) {
        double variation = (aegis_status == AEGIS_NONE ? 0.5 : 0.2); // more random deviation when far from planet.
        HPVector p_pos = the_planet->_cxxEntity->position;
        double p_cr = the_planet->_cxxEntity->collision_radius; // the surface
        HPVector p1 = HPvector_between(p_pos, position);
        p1 = HPvector_normal(p1); // vector towards ship
        p1.x += variation * (randf() - variation);
        p1.y += variation * (randf() - variation);
        p1.z += variation * (randf() - variation);
        p1 = HPvector_normal(p1);
        _destination = HPvector_add(p_pos, HPvector_multiply_scalar(p1, p_cr)); // on surface
        desired_range = collision_radius + 100.0; // +100m from the destination
    } else {
        [shipAI message:"NO_PLANET_FOUND"];
    }
}

void ShipEntity::setTakeOffFromPlanet()
{
    ::ShipEntity* self = oo::ToObjC(this);
    /*- selects the nearest planet it can find -*/
    ::OOPlanetEntity* the_planet = [self findNearestPlanet];
    if (the_planet) {
        _destination = HPvector_add([the_planet position], HPvector_multiply_scalar(HPvector_normal(HPvector_subtract([the_planet position], position)), -10000.0 - the_planet->_cxxEntity->collision_radius)); // 10km straight up
        desired_range = 50.0;
    } else {
        OO_LOG("ai.setTakeOffFromPlanet.noPlanet", "{}", "***** Error. Planet not found during take off!");
    }
}

void ShipEntity::landOnPlanet()
{
    ::ShipEntity* self = oo::ToObjC(this);
    // Selects the nearest planet it can find.
    [self landOnPlanet:[self findNearestPlanet]];
}

void ShipEntity::checkTargetLegalStatus()
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::ShipEntity* other_ship = [self primaryTarget];
    if (!other_ship) {
        [shipAI message:"NO_TARGET"];
        return;
    } else {
        int ls = [other_ship legalStatus];
        if (ls > 50) {
            [shipAI message:"TARGET_FUGITIVE"];
            return;
        }
        if (ls > 20) {
            [shipAI message:"TARGET_OFFENDER"];
            return;
        }
        if (ls > 0) {
            [shipAI message:"TARGET_MINOR_OFFENDER"];
            return;
        }
        [shipAI message:"TARGET_CLEAN"];
    }
}

void ShipEntity::checkOwnLegalStatus()
{
    ::ShipEntity* self = oo::ToObjC(this);
    if (scanClass == CLASS_THARGOID) {
        [shipAI message:"SELF_THARGOID"];
        return;
    }
    int ls = [self legalStatus];
    if (ls > 50) {
        [shipAI message:"SELF_FUGITIVE"];
        return;
    }
    if (ls > 20) {
        [shipAI message:"SELF_OFFENDER"];
        return;
    }
    if (ls > 0) {
        [shipAI message:"SELF_MINOR_OFFENDER"];
        return;
    }
    [shipAI message:"SELF_CLEAN"];
}

void ShipEntity::exitAIWithMessage(const std::string& message) // called by name (ADR-0055 item 5)
{
    [shipAI cxx_exitStateMachineWithMessage:message.empty() ? std::string("RESTARTED") : message];
}

void ShipEntity::setDestinationToTarget()
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::Entity* the_target = [self primaryTarget];
    if (the_target)
        _destination = the_target->_cxxEntity->position;
}

void ShipEntity::setDestinationWithinTarget()
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::Entity* the_target = [self primaryTarget];
    if (the_target) {
        HPVector pos = the_target->_cxxEntity->position;
        Quaternion q;
        quaternion_set_random(&q);
        Vector v = vector_forward_from_quaternion(q);
        GLfloat d = (randf() - randf()) * the_target->_cxxEntity->collision_radius; // NOLINT(misc-redundant-expression): two independent randf() draws, pre-existing; behaviour unchanged by this retarget.
        _destination = make_HPvector(pos.x + d * v.x, pos.y + d * v.y, pos.z + d * v.z);
    }
}

void ShipEntity::checkCourseToDestination()
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::Entity* hazard = [UNIVERSE hazardOnRouteFromEntity:self toDistance:desired_range fromPoint:_destination];

    if (hazard == nil || ([hazard isShip] && HPdistance(position, [hazard position]) > scannerRange) || ([hazard isPlanet] && aegis_status == AEGIS_NONE))
        [shipAI message:"COURSE_OK"]; // Avoid going into a waypoint.plist for far away objects, it cripples the main AI a bit in its funtionality.
    else {
        if ([hazard isShip] && (weapon_damage * 24.0 > [hazard energy])) {
            [shipAI cxx_reactToMessage:"HAZARD_CAN_BE_DESTROYED" context:"checkCourseToDestination"];
        }

        _destination = [UNIVERSE getSafeVectorFromEntity:self toDistance:desired_range fromPoint:_destination];
        [shipAI message:"WAYPOINT_SET"];
    }
}

} // namespace cxx

// Slice 3 of docs/phases/3-slices/ShipEntityAI.md (bead oo-wc9o3): PureAI part 2: checks, comms,
// Thargoids, escorts, patrols, target marking. Members of cxx::ShipEntity defined in the category's
// file (ADR-0056 amendment oo-o89 item 4); the facade forwards each selector
// (ShipEntity+ObjCBridge.mm); sends to self stay sends, so an Objective-C subclass's override still
// runs (amendment oo-mvzmb).
namespace cxx {

void ShipEntity::checkAegis()
{
    ::ShipEntity* self = oo::ToObjC(this);
    switch (aegis_status) {
    case AEGIS_CLOSE_TO_MAIN_PLANET:
        [shipAI message:"AEGIS_CLOSE_TO_MAIN_PLANET"];
        // It's been a few years since 1.71 - it should be safe enough to comment out the line below for 1.77/1.78 -- Kaks 20120917
        //[shipAI message:@"AEGIS_CLOSE_TO_PLANET"];	     // fires only for main planets, kept for compatibility with pre-1.72 AI plists.
        return;
    case AEGIS_CLOSE_TO_ANY_PLANET: {
        ::Entity<OOStellarBody>* nearest = [self findNearestStellarBody];

        if ([nearest isSun]) {
            [shipAI message:"CLOSE_TO_SUN"];
        } else {
            [shipAI message:"CLOSE_TO_PLANET"];
            if ([nearest planetType] == STELLAR_TYPE_MOON) {
                [shipAI message:"CLOSE_TO_MOON"];
            } else {
                [shipAI message:"CLOSE_TO_SECONDARY_PLANET"];
            }
        }
        return;
    }
    case AEGIS_IN_DOCKING_RANGE:
        [shipAI message:"AEGIS_IN_DOCKING_RANGE"];
        return;
    case AEGIS_NONE:
        [shipAI message:"AEGIS_NONE"];
        return;
    }

    OO_LOG("unclassified", "Aegis status for {} has taken on invalid value {}. This is an internal error, please report it.", oo::DescriptionOf(self), static_cast<int>(aegis_status));
    aegis_status = AEGIS_NONE;
    [shipAI message:"AEGIS_NONE"];
}

void ShipEntity::checkEnergy()
{
    if (energy == maxEnergy) {
        [shipAI message:"ENERGY_FULL"];
        return;
    }
    if (energy >= maxEnergy * 0.75) {
        [shipAI message:"ENERGY_HIGH"];
        return;
    }
    if (energy <= maxEnergy * 0.25) {
        [shipAI message:"ENERGY_LOW"];
        return;
    }
    [shipAI message:"ENERGY_MEDIUM"];
}

void ShipEntity::checkHeatInsulation()
{
    ::ShipEntity* self = oo::ToObjC(this);
    float minInsulation = 1000 / [self maxFlightSpeed] + 1;

    if ([self heatInsulation] < minInsulation) {
        [shipAI message:"INSULATION_POOR"];
        return;
    }
    [shipAI message:"INSULATION_OK"];
}

void ShipEntity::findNewDefenseTarget()
{
    ::ShipEntity* self = oo::ToObjC(this);
    [self checkScanner];
    unsigned i;
    for (i = 0; i < n_scanned_ships; i++) {
        ::ShipEntity* ship = scanned_ships[i];
        if (![ship isCloaked] && (([ship primaryTarget] == self && [ship hasHostileTarget]) || [ship isMine] || ([ship isThargoid] != [self isThargoid]))) {
            if (![self isDefenseTarget:ship]) {
                [self addDefenseTarget:ship];
                return;
            }
        }
    }
}

void ShipEntity::scanForOffenders()
{
    ::ShipEntity* self = oo::ToObjC(this);
    /*-- Locates all the ships in range and compares their legal status or bounty against ranrot_rand() & 255 - chooses the worst offender --*/
    float gov_factor = 0.4 * [UNIVERSE cxx_currentSystemData].get<int>(std::string(KEY_GOVERNMENT)); // 0 .. 7 (0 anarchic .. 7 most stable) --> [0.0, 0.4, 0.8, 1.2, 1.6, 2.0, 2.4, 2.8]
    //
    if ([UNIVERSE sun] == nil)
        gov_factor = 1.0;
    //
    DESTROY(_foundTarget);

    // find the worst offender on the scanner
    //
    [self checkScanner];
    unsigned i;
    float worst_legal_factor = 0;
    GLfloat found_d2 = scannerRange * scannerRange;
    ::OOShipGroup* group = [self group];
    for (i = 0; i < n_scanned_ships; i++) {
        ::ShipEntity* ship = scanned_ships[i];
        if ((ship->_cxxEntity->scanClass != CLASS_CARGO) && ([ship status] != STATUS_DEAD) && ([ship status] != STATUS_DOCKED) && ![ship isCloaked]) {
            GLfloat d2 = distance2_scanned_ships[i];
            float legal_factor = [ship legalStatus] * gov_factor;
            int random_factor = ranrot_rand() & 255; // 25% chance of spotting a fugitive in 15s
            if ((d2 < found_d2) && (random_factor < legal_factor) && (legal_factor > worst_legal_factor)) {
                if (group == nil || group != [ship group]) // fellows with bounty can't be offenders
                {
                    [self setFoundTarget:ship];
                    worst_legal_factor = legal_factor;
                }
            }
        }
    }

    [self checkFoundTarget];
}

void ShipEntity::setCourseToWitchpoint()
{
    if (UNIVERSE) {
        _destination = [UNIVERSE getWitchspaceExitPosition];
        desired_range = 10000.0; // 10km away
    }
}

void ShipEntity::setDestinationToWitchpoint()
{
    _destination = [UNIVERSE getWitchspaceExitPosition];
}

void ShipEntity::setDestinationToStationBeacon()
{
    if ([UNIVERSE station]) {
        _destination = [[UNIVERSE station] beaconPosition];
    }
}

void ShipEntity::performHyperSpaceExit()
{
    ::ShipEntity* self = oo::ToObjC(this);
    [self performHyperSpaceExitReplace:YES];
}

void ShipEntity::performHyperSpaceExitWithoutReplacing()
{
    ::ShipEntity* self = oo::ToObjC(this);
    [self performHyperSpaceExitReplace:NO];
}

void ShipEntity::disengageAutopilot()
{
    OO_LOG_ERR("ai.invalid.notPlayer", "Error in {}:{}, AI method endAutoPilot is only applicable to the player.", [shipAI cxx_name].value_or("(null)"), [shipAI cxx_state].value_or("(null)"));
}

void ShipEntity::wormholeGroup()
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::ShipEntity* ship = nil;
    ::WormholeEntity* whole = nil;

    whole = [self primaryTarget];
    if (![whole isWormhole])
        return;

    for (const oo::ObjCRef<::ShipEntity*>& member : [[self group] cxx_memberArray]) {
        ship = member.get();
        [ship addTarget:whole];
        [ship cxx_reactToAIMessage:"ENTER WORMHOLE" context:"wormholeGroup"];
        [ship doScriptEvent:OOJSID("wormholeSuggested") withArgument:whole];
    }
}

void ShipEntity::commsMessage(const std::string& valueString) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    [self cxx_commsMessage:valueString withUnpilotedOverride:NO];
}

void ShipEntity::commsMessageByUnpiloted(const std::string& valueString) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    [self cxx_commsMessage:valueString withUnpilotedOverride:YES];
}

void ShipEntity::ejectCargo()
{
    ::ShipEntity* self = oo::ToObjC(this);
    OOCargoQuantity i, cargo_to_go = 0.1 * [self maxAvailableCargoSpace];
    while (cargo_to_go > 15) {
        cargo_to_go = ranrot_rand() % cargo_to_go;
    }
    [self dumpCargo];
    for (i = 1; i < cargo_to_go; i++) {
        OOScheduleDeferredCall(self, @selector(dumpCargo), nil, 0.75 * i); // drop 3 canisters per 2 seconds
    }
}

void ShipEntity::scanForThargoid()
{
    ::ShipEntity* self = oo::ToObjC(this);
    return [self scanForNearestShipWithPrimaryRole:"thargoid"];
}

void ShipEntity::scanForNonThargoid()
{
    ::ShipEntity* self = oo::ToObjC(this);
    /*-- Locates all the non thargoid ships in range and chooses the nearest --*/
    DESTROY(_foundTarget);

    [self checkScanner];
    unsigned i;
    GLfloat found_d2 = scannerRange * scannerRange;
    for (i = 0; i < n_scanned_ships; i++) {
        ::ShipEntity* thing = scanned_ships[i];
        GLfloat d2 = distance2_scanned_ships[i];
        if (([thing scanClass] != CLASS_CARGO) && ([thing status] != STATUS_DOCKED) && ![thing isThargoid] && ![thing isCloaked] && (d2 < found_d2)) {
            [self setFoundTarget:thing];
            if ([thing isPlayer])
                d2 = 0.0; // prefer the player
            found_d2 = d2;
        }
    }

    [self checkFoundTarget];
}

void ShipEntity::thargonCheckMother()
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::ShipEntity* mother = [self owner];
    if (mother == nil && [self group])
        mother = [[self group] leader];

    double maxRange2 = scannerRange * scannerRange;

    if (mother && mother != self && HPdistance2(mother->_cxxEntity->position, position) < maxRange2) {
        [shipAI message:"TARGET_FOUND"]; // no need for scanning, we still have our mother.
    } else {
        // we lost the old mother, search for a new one
        [self scanForNearestShipHavingRole:"thargoid-mothership"]; // the scan will send further AI messages.
        if ([self foundTarget] != nil) {
            mother = (::ShipEntity*)[self foundTarget];
            [self setOwner:mother];
            if ([mother group] != [mother escortGroup]) // avoid adding thargon to an escort group.
            {
                [self setGroup:[mother group]];
            }
        };
    }
}

void ShipEntity::becomeUncontrolledThargon()
{
    ::ShipEntity* self = oo::ToObjC(this);
    int ent_count = UNIVERSE->_cxxUniverse->n_entities;
    ::Entity** uni_entities = UNIVERSE->_cxxUniverse->sortedEntities; // grab the public sorted list
    int i;
    for (i = 0; i < ent_count; i++)
        if (uni_entities[i]->_cxxEntity->isShip) {
            ::ShipEntity* other = (::ShipEntity*)uni_entities[i];
            if ([other primaryTarget] == self) {
                [other removeTarget:self];
            }
            if ([other isDefenseTarget:self]) {
                [other removeDefenseTarget:self];
            }
        }
    // now we're just a bunch of alien artefacts!
    scanClass = CLASS_CARGO;
    reportAIMessages = NO;
    [self setAITo:"dumbAI.plist"];
    DESTROY(_primaryTarget);
    [self setSpeed:0.0];
    [self setGroup:nil];
}

void ShipEntity::checkDistanceTravelled()
{
    if (distanceTravelled > desired_range)
        [shipAI message:"GONE_BEYOND_RANGE"];
}

void ShipEntity::fightOrFleeHostiles()
{
    ::ShipEntity* self = oo::ToObjC(this);
    [self addDefenseTarget:[self foundTarget]];

    if ([self hasEscorts]) {
        ::Entity* leTarget = [self lastEscortTarget];
        if (leTarget != nil) {
            [self setFoundTarget:leTarget];
            [shipAI message:"FLEEING"];
            return;
        }

        [self setPrimaryAggressor:[self foundTarget]];
        [self addTarget:[self foundTarget]];
        [self deployEscorts];
        [shipAI message:"DEPLOYING_ESCORTS"];
        [shipAI message:"FLEEING"];
        return;
    }

    // consider launching a missile
    if (missiles > 2) // keep a reserve
    {
        if (randf() < 0.50) {
            [self setPrimaryAggressor:[self foundTarget]];
            [self addTarget:[self foundTarget]];
            [self fireMissile];
            [shipAI message:"FLEEING"];
            return;
        }
    }

    // consider fighting
    if (energy > maxEnergy * 0.80) {
        [self setPrimaryAggressor:[self foundTarget]];
        //[self performAttack];
        [shipAI message:"FIGHTING"];
        return;
    }

    [shipAI message:"FLEEING"];
}

void ShipEntity::suggestEscort()
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::ShipEntity* mother = [self primaryTarget];
    [self suggestEscortTo:mother];
}

void ShipEntity::escortCheckMother()
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::ShipEntity* mother = [self owner];

    if ([mother acceptAsEscort:self]) {
        [self setOwner:mother];
        [self setGroup:[mother escortGroup]];
        [shipAI message:"ESCORTING"];
    } else {
        [self setOwner:self];
        if ([self group] == [mother escortGroup])
            [self setGroup:nil];
        [shipAI message:"NOT_ESCORTING"];
    }
}

void ShipEntity::checkGroupOddsVersusTarget()
{
    ::ShipEntity* self = oo::ToObjC(this);
    NSUInteger ownGroupCount = [[self group] count] + (ranrot_rand() & 3); // add a random fudge factor
    NSUInteger targetGroupCount = [[[self primaryTarget] group] count] + (ranrot_rand() & 3); // add a random fudge factor

    if (ownGroupCount == targetGroupCount) {
        [shipAI message:"ODDS_LEVEL"];
    } else if (ownGroupCount > targetGroupCount) {
        [shipAI message:"ODDS_GOOD"];
    } else {
        [shipAI message:"ODDS_BAD"];
    }
}

void ShipEntity::scanForFormationLeader()
{
    ::ShipEntity* self = oo::ToObjC(this);
    //-- Locates the nearest suitable formation leader in range --//
    DESTROY(_foundTarget);
    [self checkScannerIgnoringUnpowered];
    unsigned i;
    GLfloat found_d2 = scannerRange * scannerRange;
    for (i = 0; i < n_scanned_ships; i++) {
        ::ShipEntity* ship = scanned_ships[i];
        if ((ship != self) && (!ship->_cxxEntity->isPlayer) && (ship->_cxxEntity->scanClass == scanClass) && [ship primaryTarget] != self && ![ship isCloaked]) // look for alike
        {
            GLfloat d2 = distance2_scanned_ships[i];
            if ((d2 < found_d2) && [ship canAcceptEscort:self]) {
                found_d2 = d2;
                [self setFoundTarget:ship];
            }
        }
    }

    if ([self foundTarget] != nil)
        [shipAI message:"TARGET_FOUND"];
    else {
        [shipAI message:"NOTHING_FOUND"];
        if ([self cxx_hasPrimaryRole:"wingman"]) {
            // become free-lance police :)
            [self setAITo:"route1patrolAI.plist"]; // use this to avoid referencing a released AI
            [self setPrimaryRole:"police"]; // other wingman can now select this ship as leader.
        }
    }
}

void ShipEntity::messageMother(const std::string& msgString) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::ShipEntity* mother = [self owner];
    if (mother != nil && mother != self) {
        [mother cxx_reactToAIMessage:msgString context:DebugContext(self, "messageMother")];
    }
}

void ShipEntity::messageSelf(const std::string& msgString) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    [self sendAIMessage:msgString];
}

void ShipEntity::setPlanetPatrolCoordinates()
{
    ::ShipEntity* self = oo::ToObjC(this);
    // check we've arrived near the last given coordinates
    HPVector r_pos = HPvector_subtract(position, coordinates);
    if (HPmagnitude2(r_pos) < 1000000 || patrol_counter == 0) {
        ::Entity* the_sun = [UNIVERSE sun];
        ::ShipEntity* the_station = [[self group] leader];
        if (!the_station || ![the_station isStation])
            the_station = [UNIVERSE station];
        if ((!the_sun) || (!the_station))
            return;
        HPVector sun_pos = the_sun->_cxxEntity->position;
        HPVector stn_pos = the_station->_cxxEntity->position;
        HPVector sun_dir = HPvector_subtract(sun_pos, stn_pos);
        Vector vSun = make_vector(0, 0, 1);
        if (sun_dir.x || sun_dir.y || sun_dir.z)
            vSun = HPVectorToVector(HPvector_normal(sun_dir));
        Vector v0 = [the_station forwardVector];
        Vector v1 = cross_product(v0, vSun);
        Vector v2 = cross_product(v0, v1);
        switch (patrol_counter) {
        case 0: // first go to 5km ahead of the station
            coordinates = make_HPvector(stn_pos.x + 5000 * v0.x, stn_pos.y + 5000 * v0.y, stn_pos.z + 5000 * v0.z);
            desired_range = 250.0;
            break;
        case 1: // go to 25km N of the station
            coordinates = make_HPvector(stn_pos.x + 25000 * v1.x, stn_pos.y + 25000 * v1.y, stn_pos.z + 25000 * v1.z);
            desired_range = 250.0;
            break;
        case 2: // go to 25km E of the station
            coordinates = make_HPvector(stn_pos.x + 25000 * v2.x, stn_pos.y + 25000 * v2.y, stn_pos.z + 25000 * v2.z);
            desired_range = 250.0;
            break;
        case 3: // go to 25km S of the station
            coordinates = make_HPvector(stn_pos.x - 25000 * v1.x, stn_pos.y - 25000 * v1.y, stn_pos.z - 25000 * v1.z);
            desired_range = 250.0;
            break;
        case 4: // go to 25km W of the station
            coordinates = make_HPvector(stn_pos.x - 25000 * v2.x, stn_pos.y - 25000 * v2.y, stn_pos.z - 25000 * v2.z);
            desired_range = 250.0;
            break;
        default: // We should never come here
            coordinates = make_HPvector(stn_pos.x + 5000 * v0.x, stn_pos.y + 5000 * v0.y, stn_pos.z + 5000 * v0.z);
            desired_range = 250.0;
            break;
        }
        patrol_counter++;
        if (patrol_counter > 4) {
            if (randf() < .25) {
                // consider docking
                [self setTargetStation:the_station];
                [self setAITo:"dockingAI.plist"];
                return;
            } else {
                // go around again
                patrol_counter = 1;
            }
        }
    }
    [shipAI message:"APPROACH_COORDINATES"];
}

void ShipEntity::setSunSkimStartCoordinates()
{
    ::ShipEntity* self = oo::ToObjC(this);
    if ([UNIVERSE sun] == nil) {
        [shipAI message:"NO_SUN_FOUND"];
        return;
    }

    HPVector v0 = [UNIVERSE getSunSkimStartPositionForShip:self];

    if (!HPvector_equal(v0, kZeroHPVector)) {
        coordinates = v0;
        [shipAI message:"APPROACH_COORDINATES"];
    } else {
        [shipAI message:"WAIT_FOR_SUN"];
    }
}

void ShipEntity::setSunSkimEndCoordinates()
{
    ::ShipEntity* self = oo::ToObjC(this);
    if ([UNIVERSE sun] == nil) {
        [shipAI message:"NO_SUN_FOUND"];
        return;
    }

    coordinates = [UNIVERSE getSunSkimEndPositionForShip:self];
    [shipAI message:"APPROACH_COORDINATES"];
}

void ShipEntity::setSunSkimExitCoordinates()
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::Entity* the_sun = [UNIVERSE sun];
    if (the_sun == nil)
        return;
    HPVector v1 = [UNIVERSE getSunSkimEndPositionForShip:self];
    HPVector vs = the_sun->_cxxEntity->position;
    HPVector vout = HPvector_subtract(v1, vs);
    if (vout.x || vout.y || vout.z)
        vout = HPvector_normal(vout);
    else
        vout.z = 1.0;
    v1.x += 10000 * vout.x;
    v1.y += 10000 * vout.y;
    v1.z += 10000 * vout.z;
    coordinates = v1;
    [shipAI message:"APPROACH_COORDINATES"];
}

void ShipEntity::patrolReportIn()
{
    ::ShipEntity* self = oo::ToObjC(this);
    // Set a report time in the patrolled station to delay a new launch.
    ::ShipEntity* the_station = [[self group] leader];
    if (!the_station || ![the_station isStation])
        the_station = [UNIVERSE station];
    [(::StationEntity*)the_station acceptPatrolReportFrom:self];
}

void ShipEntity::checkForMotherStation()
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::ShipEntity* motherStation = [[self group] leader];
    if ((!motherStation) || (!(motherStation->_cxxEntity->isStation))) {
        [shipAI message:"NOTHING_FOUND"];
        return;
    }
    double found_d2 = scannerRange * scannerRange;
    HPVector v0 = motherStation->_cxxEntity->position;
    if (HPdistance2(v0, position) > found_d2) {
        [shipAI message:"NOTHING_FOUND"];
        return;
    }
    [shipAI message:"STATION_FOUND"];
}

void ShipEntity::sendTargetCommsMessage(const std::string& message) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::ShipEntity* ship = [self primaryTarget];
    if ((ship == nil) || ([ship status] == STATUS_DEAD) || ([ship status] == STATUS_DOCKED)) {
        [self noteLostTarget];
        return;
    }
    [self cxx_sendExpandedMessage:message toShip:[self primaryTarget]];
}

void ShipEntity::markTargetForFines()
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::ShipEntity* ship = [self primaryTarget];
    if ((ship == nil) || ([ship status] == STATUS_DEAD) || ([ship status] == STATUS_DOCKED)) {
        [self noteLostTarget];
        return;
    }
    if ([ship markForFines])
        [shipAI message:"TARGET_MARKED"];
}

void ShipEntity::markTargetForOffence(const std::string& valueString) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    if ((isStation) || (scanClass == CLASS_POLICE)) {
        ::ShipEntity* ship = [self primaryTarget];
        if ((ship == nil) || ([ship status] == STATUS_DEAD) || ([ship status] == STATUS_DOCKED)) {
            [self noteLostTarget];
            return;
        }
        const std::string finalValue = cxx_OOExpand(valueString).value_or(std::string()); // expand values
        [ship markAsOffender:oo::str::intValue(finalValue) withReason:kOOLegalStatusReasonSeenByPolice];
    }
}

void ShipEntity::storeTarget()
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::Entity* target = [self primaryTarget];

    if (target) {
        [self setRememberedShip:target];
    } else {
        DESTROY(_rememberedShip);
    }
}

} // namespace cxx

// Slice 4 of docs/phases/3-slices/ShipEntityAI.md (bead oo-lqyhf): PureAI part 3: stored targets,
// nearest-ship scans, stations, script actions, beacons. Members of cxx::ShipEntity defined in the
// category's file (ADR-0056 amendment oo-o89 item 4); the facade forwards each selector
// (ShipEntity+ObjCBridge.mm); sends to self stay sends, so an Objective-C subclass's override still
// runs (amendment oo-mvzmb).
namespace cxx {

void ShipEntity::recallStoredTarget()
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::ShipEntity* oldTarget = (::ShipEntity*)[self rememberedShip];
    BOOL found = NO;

    if (oldTarget && ![oldTarget isCloaked]) {
        GLfloat range2 = HPdistance2([oldTarget position], position);
        if (range2 <= scannerRange * scannerRange && range2 <= SCANNER_MAX_RANGE2) {
            found = YES;
        }
    }

    if (found) {
        [self setFoundTarget:oldTarget];
        [shipAI message:"TARGET_FOUND"];
    } else {
        if (oldTarget == nil)
            DESTROY(_rememberedShip); // ship no longer exists
        [shipAI message:"NOTHING_FOUND"];
    }
}

void ShipEntity::scanForRocks()
{
    ::ShipEntity* self = oo::ToObjC(this);
    /*-- Locates the all boulders and asteroids in range and selects nearest --*/

    // find boulders then asteroids within range
    //
    DESTROY(_foundTarget);
    [self checkScanner];
    unsigned i;
    GLfloat found_d2 = scannerRange * scannerRange;
    for (i = 0; i < n_scanned_ships; i++) {
        ::ShipEntity* thing = scanned_ships[i];
        if ([thing isBoulder]) {
            GLfloat d2 = distance2_scanned_ships[i];
            if (d2 < found_d2) {
                [self setFoundTarget:thing];
                found_d2 = d2;
            }
        }
    }
    if ([self foundTarget] == nil) {
        for (i = 0; i < n_scanned_ships; i++) {
            ::ShipEntity* thing = scanned_ships[i];
            if ([thing hasRole:"asteroid"]) {
                GLfloat d2 = distance2_scanned_ships[i];
                if (d2 < found_d2) {
                    [self setFoundTarget:thing];
                    found_d2 = d2;
                }
            }
        }
    }

    [self checkFoundTarget];
}

void ShipEntity::setDestinationToDockingAbort()
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::Entity* the_target = [self targetStation];
    if (!the_target) {
        /* Probably the player trying to dock with docking computer
         * from out of scanner range */
        the_target = [UNIVERSE station];
    }
    double bo_distance = 8000; //	8km back off
    HPVector v0 = position;
    HPVector d0 = (the_target) ? the_target->_cxxEntity->position : kZeroHPVector;
    v0.x += (randf() - 0.5) * collision_radius;
    v0.y += (randf() - 0.5) * collision_radius;
    v0.z += (randf() - 0.5) * collision_radius;
    v0.x -= d0.x;
    v0.y -= d0.y;
    v0.z -= d0.z;
    v0 = HPvector_normal_or_fallback(v0, make_HPvector(0, 0, -1));

    v0.x *= bo_distance;
    v0.y *= bo_distance;
    v0.z *= bo_distance;
    v0.x += d0.x;
    v0.y += d0.y;
    v0.z += d0.z;
    coordinates = v0;
    _destination = v0;
}

void ShipEntity::requestNewTarget()
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::ShipEntity* mother = [[self group] leader];
    if (mother == nil) {
        [shipAI message:"MOTHER_LOST"];
        return;
    }

    /*-- Locates all the ships in range targeting the mother ship and chooses the nearest/biggest --*/
    DESTROY(_foundTarget);
    [self checkScanner];
    unsigned i;
    GLfloat found_d2 = scannerRange * scannerRange;
    GLfloat max_e = 0;
    for (i = 0; i < n_scanned_ships; i++) {
        ::ShipEntity* thing = scanned_ships[i];
        GLfloat d2 = distance2_scanned_ships[i];
        GLfloat e1 = [thing energy];
        if ((d2 < found_d2) && ![thing isCloaked] && (([thing isThargoid] && ![mother isThargoid]) || (([thing primaryTarget] == mother) && [thing hasHostileTarget]))) {
            if (e1 > max_e) {
                [self setFoundTarget:thing];
                max_e = e1;
            }
        }
    }

    [self checkFoundTarget];
}

void ShipEntity::rollD(const std::string& die_number) // called by name (ADR-0055 item 5)
{
    int die_sides = oo::str::intValue(die_number);
    if (die_sides > 0) {
        int die_roll = 1 + (ranrot_rand() % die_sides);
        [shipAI cxx_reactToMessage:oo::str::format("ROLL_%d", die_roll) context:"rollD:"];
    } else {
        OO_LOG("ai.rollD.invalidValue", "***** ERROR: invalid value supplied to rollD: '{}'.", die_number);
    }
}

void ShipEntity::scanForNearestShipWithPrimaryRole(const std::string& scanRole) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    [self scanForNearestShipWithPredicate:HasPrimaryRolePredicate parameter:const_cast<std::string*>(&scanRole)]; // the predicate reads a std::string
}

void ShipEntity::scanForNearestShipHavingRole(const std::string& scanRole) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    [self scanForNearestShipWithPredicate:HasRolePredicate parameter:const_cast<std::string*>(&scanRole)]; // the predicate reads a std::string
}

void ShipEntity::scanForNearestShipWithAnyPrimaryRole(const std::string& scanRoles) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    std::vector<std::string> roles = oo::str::tokens(scanRoles); // the predicate reads the role strings
    [self scanForNearestShipWithPredicate:HasPrimaryRoleInSetPredicate parameter:&roles];
}

void ShipEntity::scanForNearestShipHavingAnyRole(const std::string& scanRoles) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    std::vector<std::string> roles = oo::str::tokens(scanRoles); // the predicate reads the role strings
    [self scanForNearestShipWithPredicate:HasRoleInSetPredicate parameter:&roles];
}

void ShipEntity::scanForNearestShipWithScanClass(const std::string& scanScanClass) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    OOScanClass wantedClass = cxx_OOScanClassFromString(scanScanClass); // the predicate reads an OOScanClass
    [self scanForNearestShipWithPredicate:HasScanClassPredicate parameter:&wantedClass];
}

void ShipEntity::scanForNearestShipWithoutPrimaryRole(const std::string& scanRole) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    [self scanForNearestShipWithNegatedPredicate:HasPrimaryRolePredicate parameter:const_cast<std::string*>(&scanRole)]; // the predicate reads a std::string
}

void ShipEntity::scanForNearestShipNotHavingRole(const std::string& scanRole) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    [self scanForNearestShipWithNegatedPredicate:HasRolePredicate parameter:const_cast<std::string*>(&scanRole)]; // the predicate reads a std::string
}

void ShipEntity::scanForNearestShipWithoutAnyPrimaryRole(const std::string& scanRoles) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    std::vector<std::string> roles = oo::str::tokens(scanRoles); // the predicate reads the role strings
    [self scanForNearestShipWithNegatedPredicate:HasPrimaryRoleInSetPredicate parameter:&roles];
}

void ShipEntity::scanForNearestShipNotHavingAnyRole(const std::string& scanRoles) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    std::vector<std::string> roles = oo::str::tokens(scanRoles); // the predicate reads the role strings
    [self scanForNearestShipWithNegatedPredicate:HasRoleInSetPredicate parameter:&roles];
}

void ShipEntity::scanForNearestShipWithoutScanClass(const std::string& scanScanClass) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    OOScanClass wantedClass = cxx_OOScanClassFromString(scanScanClass); // the predicate reads an OOScanClass
    [self scanForNearestShipWithNegatedPredicate:HasScanClassPredicate parameter:&wantedClass];
}

void ShipEntity::scanForNearestShipMatchingPredicate(const std::string& predicateExpression) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
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
    static std::map<std::string, oo::Ref<OOJSFunction>, std::less<>>* scriptCache = nullptr;
    std::string key;
    oo::Ref<OOJSFunction> function;
    JSContext* context = NULL;

    context = OOJSAcquireContext();

    const std::string& expression = predicateExpression;

    const std::optional<std::string> aiName = [[self getAI] cxx_name];
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
    if (scriptCache != nullptr) {
        const auto cached = scriptCache->find(key);
        if (cached != scriptCache->end())
            function = cached->second;
    }
    if (function == nullptr) {
        const char* argNames[] = { "ship" };

        // Stuff expression in a function.
        const std::string predicateCode = "return " + expression + ";";
        function = OOJSFunction::initWithName(std::string("_oo_AIScanPredicate"),
            JS_UNDEFINED,
            predicateCode,
            1,
            argNames,
            aiName,
            0,
            context);

        // Cache function.
        if (function != nullptr) {
            if (scriptCache == nullptr)
                scriptCache = new std::map<std::string, oo::Ref<OOJSFunction>, std::less<>>();
            (*scriptCache)[key] = function;
        }
    }

    if (function != nullptr) {
        JSValue jsThis = OOJSObjectFromNativeObject(context, self); // Owned.
        JSFunctionPredicateParameter param = {
            .context = context,
            .function = function->function(), // Borrowed.
            .jsThis = jsThis
        };
        [self scanForNearestShipWithPredicate:JSFunctionPredicate parameter:&param];
        JS_FreeValue(context, jsThis);
    } else {
        // Report error (once per occurrence)
        static std::set<std::string> errorCache;

        if (!errorCache.contains(key)) {
            OO_LOG("ai.scanForNearestShipMatchingPredicate.compile.failed", "Could not compile JavaScript predicate \"{}\" for AI {}.", predicateExpression, [[self getAI] cxx_name].value_or("(null)"));
            errorCache.insert(key);
        }

        // Select nothing
        DESTROY(_foundTarget);
        [[self getAI] message:"NOTHING_FOUND"];
    }

    OOJSReportPendingException(context);
    OOJSRelinquishContext(context);
}

void ShipEntity::setCoordinates(const std::string& system_x_y_z) // called by name (ADR-0055 item 5)
{
    const std::vector<std::string> tokens = oo::str::tokens(system_x_y_z);

    if (tokens.size() != 4) {
        OO_LOG("ai.syntax.setCoordinates", "***** ERROR: cannot setCoordinates: '{}'.", system_x_y_z);
        return;
    }

    const std::string& systemString = tokens[0];
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
    GLfloat scalar = 1.0;

    coordinates = [UNIVERSE cxx_coordinatesForPosition:posn withCoordinateSystem:systemString returningScalar:&scalar];

    [shipAI message:"APPROACH_COORDINATES"];
}

void ShipEntity::checkForNormalSpace()
{
    if ([UNIVERSE sun] && [UNIVERSE planet])
        [shipAI message:"NORMAL_SPACE"];
    else
        [shipAI message:"INTERSTELLAR_SPACE"];
}

void ShipEntity::setTargetToRandomStation()
{
    ::ShipEntity* self = oo::ToObjC(this);
    /*- selects the nearest station it can find -*/
    int ent_count = UNIVERSE->_cxxUniverse->n_entities;
    ::Entity** uni_entities = UNIVERSE->_cxxUniverse->sortedEntities; // grab the public sorted list
    std::vector<::Entity*> my_entities(ent_count);
    ::StationEntity *station = nil, *my_station = nil;
    double maxRange2 = desired_range * desired_range;
    int i;
    int station_count = 0;

    for (i = 0; i < ent_count; i++) {
        // find stations within range but exclude carriers.
        if (uni_entities[i]->_cxxEntity->isStation) {
            my_station = (::StationEntity*)uni_entities[i];
            if ([my_station maxFlightSpeed] == 0 && [my_station hasNPCTraffic] && HPdistance2(position, [my_station position]) < maxRange2) {
                my_entities[station_count++] = [uni_entities[i] retain]; //	retained
            }
        }
    }

    if (station_count != 0) {
        // select a random station
        station = (::StationEntity*)my_entities[ranrot_rand() % station_count];
        // if more than one candidate do not select main station
        if (station == [UNIVERSE station] && station_count > 1) {
            while (station == [UNIVERSE station]) {
                station = (::StationEntity*)my_entities[ranrot_rand() % station_count];
            }
        }
    }

    for (i = 0; i < station_count; i++)
        [my_entities[i] release]; //	released
    //
    if (station) {
        [self addTarget:station];
        [self setTargetStation:station];
        [shipAI message:"STATION_FOUND"];
    } else {
        [shipAI message:"NO_STATION_IN_RANGE"];
    }
}

void ShipEntity::setTargetToLastStation()
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::Entity* station = [self targetStation];

    if (station != nil && [station isStation]) {
        [self addTarget:station];
    } else {
        [shipAI message:"NO_STATION_FOUND"];
        [self setTargetStation:nil];
    }
}

void ShipEntity::addFuel(const std::string& fuel_number) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    [self setFuel:[self fuel] + oo::str::intValue(fuel_number) * 10];
}

void ShipEntity::scriptActionOnTarget(const std::string& action) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::PlayerEntity* player = PLAYER;
    ::ShipEntity* targEnt = [self primaryTarget];
    ::ShipEntity* oldTarget = nil;

#ifndef NDEBUG
    static BOOL deprecationWarning = NO;

    if (!deprecationWarning) {
        deprecationWarning = YES;
        OO_LOG("script.deprecated.scriptActionOnTarget", "----- WARNING in AI {}: the AI method scriptActionOnTarget: is deprecated and should not be used. It is slow and has unpredictable side effects. The recommended alternative is to use sendScriptMessage: to call a function in a ship's JavaScript ship script instead. scriptActionOnTarget: should not be used at all from scripts. An alternative is safeScriptActionOnTarget:, which is similar to scriptActionOnTarget: but has less side effects.", [::AI cxx_currentlyRunningAIDescription].value_or("(null)"));
    } else {
        OO_LOG("script.deprecated.scriptActionOnTarget.repeat", "----- WARNING in AI {}: the AI method scriptActionOnTarget: is deprecated and should not be used.", [::AI cxx_currentlyRunningAIDescription].value_or("(null)"));
    }
#endif

    if ([targEnt isShip]) {
        oldTarget = [player scriptTarget];
        [player setScriptTarget:(::ShipEntity*)targEnt];
        [player cxx_runUnsanitizedScriptActions:oo::PList(oo::PList::Array { oo::PList(action) })
                              allowingAIMethods:YES
                                withContextName:oo::str::format("<AI \"%s\" state %s - scriptActionOnTarget:>", [[self getAI] cxx_name].value_or("(null)").c_str(), [[self getAI] cxx_state].value_or("(null)").c_str())
                                      forTarget:targEnt];
        [player checkScript]; // react immediately to any changes this makes
        [player setScriptTarget:oldTarget];
    }
}

void ShipEntity::safeScriptActionOnTarget(const std::string& action) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    ::PlayerEntity* player = PLAYER;
    ::ShipEntity* targEnt = [self primaryTarget];
    ::ShipEntity* oldTarget = nil;

    if ([targEnt isShip]) {
        oldTarget = [player scriptTarget];
        [player setScriptTarget:(::ShipEntity*)targEnt];
        [player cxx_runUnsanitizedScriptActions:oo::PList(oo::PList::Array { oo::PList(action) })
                              allowingAIMethods:YES
                                withContextName:oo::str::format("<AI \"%s\" state %s - safeScriptActionOnTarget:>", [[self getAI] cxx_name].value_or("(null)").c_str(), [[self getAI] cxx_state].value_or("(null)").c_str())
                                      forTarget:targEnt];
        [player setScriptTarget:oldTarget];
    }
}

// Send own ship script a message.
void ShipEntity::sendScriptMessage(const std::string& message) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    const std::vector<std::string> components = oo::str::tokens(message);

    if (components.size() == 1) {
        [self doScriptEvent:cxx_OOJSIDFromString(message)];
    } else if (!components.empty()) // (an empty message raised at -objectAtIndex:0)
    {
        const std::string& function = components[0];
        oo::PList::Array arguments; // one argument: an array of the other components
        for (auto component = components.begin() + 1; component != components.end(); ++component)
            arguments.emplace_back(*component);
        [self cxx_doScriptEvent:cxx_OOJSIDFromString(function) withPListArguments: { oo::PList(std::move(arguments)) }];
    }
}

void ShipEntity::ai_throwSparks()
{
    ::ShipEntity* self = oo::ToObjC(this);
    [self setThrowSparks:YES];
}

void ShipEntity::explodeSelf()
{
    ::ShipEntity* self = oo::ToObjC(this);
    [self getDestroyedBy:nil damageType:kOODamageTypeEnergy];
}

void ShipEntity::ai_debugMessage(const std::string& message) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    std::string desc = oo::str::format("%s %d", [self cxx_name].value_or("(null)").c_str(), [self universalID]);
    if ([self isPlayer])
        desc = "player autopilot";
    OO_LOG("ai.takeAction.debugMessage", "DEBUG: AI MESSAGE from {}: {}", desc, message);
}

// racing code TODO
void ShipEntity::targetFirstBeaconWithCode(const std::string& code) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    const std::vector<oo::ObjCRef<::Entity<OOBeaconEntity>*>> all_beacons = [UNIVERSE cxx_listBeaconsWithCode:code];
    if (!all_beacons.empty()) {
        [self addTarget:(::ShipEntity*)all_beacons[0].get()];
        [shipAI message:"TARGET_FOUND"];
    } else
        [shipAI message:"NOTHING_FOUND"];
}

void ShipEntity::targetNextBeaconWithCode(const std::string& code) // called by name (ADR-0055 item 5)
{
    ::ShipEntity* self = oo::ToObjC(this);
    const std::vector<oo::ObjCRef<::Entity<OOBeaconEntity>*>> all_beacons = [UNIVERSE cxx_listBeaconsWithCode:code];
    ::ShipEntity* current_beacon = [self primaryTarget];

    if ((!current_beacon) || (![current_beacon isBeacon])) {
        [shipAI message:"NO_CURRENT_BEACON"];
        [shipAI message:"NOTHING_FOUND"];
        return;
    }

    // find the current beacon in the list..
    // -indexOfObject: (identity for entities)
    const auto found = std::find_if(all_beacons.begin(), all_beacons.end(), [current_beacon](const oo::ObjCRef<::Entity*>& beacon) { return beacon.get() == current_beacon; });
    NSUInteger i = found != all_beacons.end() ? (NSUInteger)(found - all_beacons.begin()) : NSNotFound;

    if (i == NSNotFound) {
        [shipAI message:"NOTHING_FOUND"];
        return;
    }

    i++; // next index

    if (i < all_beacons.size()) {
        // locate current target in list
        [self addTarget:(::ShipEntity*)all_beacons[i].get()];
        [shipAI message:"TARGET_FOUND"];
    } else {
        [shipAI message:"LAST_BEACON"];
        [shipAI message:"NOTHING_FOUND"];
    }
}

void ShipEntity::setRacepointsFromTarget()
{
    ::ShipEntity* self = oo::ToObjC(this);
    // two point - one at z - cr one at z + cr
    ::ShipEntity* ship = [self primaryTarget];
    if (ship == nil) {
        [shipAI message:"NOTHING_FOUND"];
        return;
    }
    Vector k = ship->_cxxShip->v_forward;
    GLfloat c = ship->_cxxEntity->collision_radius;
    HPVector o = ship->_cxxEntity->position;
    navpoints[0] = make_HPvector(o.x - c * k.x, o.y - c * k.y, o.z - c * k.z);
    navpoints[1] = make_HPvector(o.x + c * k.x, o.y + c * k.y, o.z + c * k.z);
    navpoints[2] = make_HPvector(o.x + 2.0 * c * k.x, o.y + 2.0 * c * k.y, o.z + 2.0 * c * k.z);
    number_of_navpoints = 2;
    next_navpoint_index = 0;
    _destination = navpoints[0];
    [shipAI message:"RACEPOINTS_SET"];
}

void ShipEntity::performFlyRacepoints()
{
    next_navpoint_index = 0;
    desired_range = collision_radius;
    behaviour = BEHAVIOUR_FLY_THRU_NAVPOINTS;
}

} // namespace cxx
