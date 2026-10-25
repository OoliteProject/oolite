/*

ShipEntity.m


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the impllied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#include "ShipEntity.h"
#include "ShipEntityAI.h"
#include "ShipEntityScriptMethods.h"
#include "EntityOOJavaScriptExtensions.h"

#include "OOMaths.h"
#include "Universe.h"
#include "OOShaderMaterial.h"
#include "OOOpenGLExtensionManager.h"

#include "ResourceManager.h"
#include "OOStringExpander.h"
#include "OOStringParsing.h"
#include "OOConstToString.h"
#include "OOConstToJSString.h"
#include "oofnd/Scanner.hpp"
#include "OORoleSet.h"
#include "OOShipGroup.h"
#include "GameController.h"
#include "MyOpenGLView.h"
#include "OOSystemDescriptionManager.h"
#include "OOCharacter.h"
#include "AI.h"

#include "OOMesh.h"
#include "OOPlanetDrawable.h"

#include "Octree.h"
#include "OOColor.h"
#include "OOPolygonSprite.h"

#include "OOParticleSystem.h"
#include "StationEntity.h"
#include "DockEntity.h"
#include "OOSunEntity.h"
#include "OOPlanetEntity.h"
#include "OOStellarBody.h"
#include "PlayerEntity.h"
#include "WormholeEntity.h"
#include "OOFlasherEntity.h"
#include "OOExhaustPlumeEntity.h"
#include "OOSparkEntity.h"
#include "OOECMBlastEntity.h"
#include "OOPlasmaShotEntity.h"
#include "OOFlashEffectEntity.h"
#include "OOExplosionCloudEntity.h"
#include "ProxyPlayerEntity.h"
#include "OOLaserShotEntity.h"
#include "OOQuiriumCascadeEntity.h"
#include "OORingEffectEntity.h"

#include "PlayerEntityLegacyScriptEngine.h"
#include "PlayerEntitySound.h"
#include "GuiDisplayGen.h"
#include "HeadUpDisplay.h"
#include "OOEntityFilterPredicate.h"
#include "OOShipRegistry.h"
#include "OOEquipmentType.h"

#include "OODebugGLDrawing.h"
#include "OODebugFlags.h"
#include "OODebugStandards.h"

#include "OOJSScript.h"
#include "OOJSVector.h"
#include "OOJSEngineTimeManagement.h"
#include "OOPListGameTypes.h"
#include "oofnd/objc/OOAssert.h"
#include "oofnd/objc/OOException.h"	// oo::Finally, oo::CurrentOOException (beads oo-rskgl, oo-rskgl.1)
#include <string_view>
#include "OOObjCPList.h"
#include "oofnd/String.hpp"

#define USEMASC 1


#ifndef NDEBUG
#endif

#if MASS_DEPENDENT_FUEL_PRICES
static GLfloat calcFuelChargeRate (GLfloat myMass)
{
#define kMassCharge 0.65				// the closer to 1 this number is, the more the fuel price changes from ship to ship.
#define kBaseCharge (1.0 - kMassCharge)	// proportion of price that doesn't change with ship's mass.

	GLfloat baseMass = (PLAYER != nullptr ? PLAYER->baseMass() : 0.0f);	// [PLAYER baseMass] (ShipEntityPlayerBaseMass() until bead oo-9ht.144)
	// if anything is wrong, use 1 (the default  charge rate).
	if (myMass <= 0.0 || baseMass <=0.0) return 1.0;
	
	GLfloat result = (kMassCharge * myMass / baseMass) + kBaseCharge;
	
	// round the result to the second decimal digit.
	result = roundf(result * 100.0f) / 100.0f;
	
	// Make sure that the rate is clamped to between three times and a third of the standard charge rate.
	if (result > 3.0f) result = 3.0f;
	else if (result < 0.33f) result = 0.33f;
	
	return result;
	
#undef kMassCharge
#undef kBaseCharge
}
#endif


namespace {

// Equipment keys as the array -hasEquipmentItem: / -hasAllEquipment: take (was an NSSet of them).
oo::PList KeysPList(const std::vector<std::string> &keys)
{
	oo::PList::Array result;
	result.reserve(keys.size());
	for (const std::string &key : keys)  result.emplace_back(key);
	return oo::PList(std::move(result));
}


// An equipment key as -hasEquipmentItem: takes it: a null PList for nullopt (was nil).
oo::PList OptionalKeyPList(const std::optional<std::string> &key)
{
	return key.has_value() ? oo::PList(*key) : oo::PList();
}


/*	Readers for a subentity / ship configuration held as an oo::PList (the Foundation sweep,
	proposed ADR-0043): what oo::PListView(dict)'s array / string / get<HPVector> /
	get<Quaternion> answered. A string is nil (nullopt) when the key is absent or holds neither a
	string nor a number; vectors and quaternions go through OOPListGameTypes' readers, with their
	defaults for a missing key.
*/
const oo::PList *ArrayForKey(const oo::PList &dict, std::string_view key)
{
	const oo::PList *value = dict.find(key);
	return (value != nullptr && value->isArray()) ? value : nullptr;
}


std::optional<std::string> StringForKey(const oo::PList &dict, std::string_view key)
{
	const oo::PList *value = dict.find(key);
	if (value == nullptr || !(value->isString() || value->isNumber()))  return std::nullopt;
	return oo::PListGet<std::string>::from(value, std::string());
}


HPVector HPVectorForKey(const oo::PList &dict, std::string_view key)
{
	const oo::PList *value = dict.find(key);
	return OOHPVectorFromPList(value, kZeroHPVector);
}


Quaternion QuaternionForKey(const oo::PList &dict, std::string_view key)
{
	const oo::PList *value = dict.find(key);
	return OOQuaternionFromPList(value, kIdentityQuaternion);
}


// get<Vector>(key, kZeroVector) / at<Vector>(i, kZeroVector): nullptr is a missing value.
Vector VectorFromPList(const oo::PList *value)
{
	return OOVectorFromPList(value, kZeroVector);
}


// Was the private -repeatString:times:.
std::string RepeatString(std::string_view str, NSUInteger times)
{
	std::string result;
	result.reserve(str.size() * times);
	
	for (NSUInteger i = 0; i < times; i++)
	{
	    result += str;
	}
	
	return result;
}


/*	cxx_OOExpandKey(key, <argument>): the expansion of a description key with the one-entry argument
	dictionary the macro builds from the variable's name (OOShipLibraryDescriptions.mm's pattern).
	A nil argument (which the macro could not have put in a dictionary) is left out.
*/
std::optional<std::string> ExpandKeyWithArgument(const char *key, const char *argumentName, const std::optional<std::string> &argument)
{
	oo::PList::Dict arguments;
	if (argument.has_value())  arguments[argumentName] = *argument;
	return cxx_OOExpandDescriptionString(OOStringExpanderDefaultRandomSeed(), key,
		oo::PList(std::move(arguments)), oo::PList(), std::nullopt, kOOExpandKey);
}


// [key intValue] for a close-contact key (the "%d" text of a universal ID).
int IntValueOfKey(std::string_view key)
{
	int value = 0;
	if (std::from_chars(key.data(), key.data() + key.size(), value).ec != std::errc())  return 0;	// -intValue gave 0
	return value;
}


// cxx_OOExpand(text): the text expanded with no arguments; nothing expanded is "".
std::string ExpandedText(const std::string &text)
{
	return cxx_OOExpand(text).value_or(std::string());
}


// get<oo::FuzzyBoolean>(key, fallback): YES with the probability the value gives, through
// OOFuzzyBooleanFromPList, which also draws the random number.
BOOL FuzzyBooleanForKey(const oo::PList &dict, std::string_view key, float fallback = 0.0f)
{
	const oo::PList *value = dict.find(key);
	return OOFuzzyBooleanFromPList(value, fallback);
}


// get<Vector>(key, fallback).
Vector VectorForKey(const oo::PList &dict, std::string_view key, Vector fallback)
{
	const oo::PList *value = dict.find(key);
	return OOVectorFromPList(value, fallback);
}


// get<PList::Dict>: the dictionary, or null (nil).
oo::PList DictionaryForKey(const oo::PList &dict, std::string_view key)
{
	const oo::PList *value = dict.get<oo::PList::Dict>(key);
	return value != nullptr ? *value : oo::PList();
}


// -objectForKey: as plist data (a null PList when absent), for +cxx_colorWithDescription: & co.
oo::PList ValueForKey(const oo::PList &dict, std::string_view key)
{
	const oo::PList *value = dict.find(key);
	return value != nullptr ? *value : oo::PList();
}


// The strings in an array value, as a set of names (a string set's -containsObject: of a string
// never matched anything else); empty when the value is absent or not an array.
std::set<std::string> NamesInArrayForKey(const oo::PList &dict, std::string_view key)
{
	std::set<std::string> names;
	const oo::PList *value = ArrayForKey(dict, key);
	if (value == nullptr)  return names;
	for (const oo::PList &entry : *value->getIf<oo::PList::Array>())
	{
		if (const std::string *name = entry.getIf<std::string>())  names.insert(*name);
	}
	return names;
}

}	// namespace


static ShipEntity *doOctreesCollide(ShipEntity *prime, ShipEntity *other);


namespace {

/*	One batch of a for-in over a group's -objectEnumerator, now a plain OOShipGroupCursor: GNUstep's
	-[NSEnumerator countByEnumeratingWithState:objects:count:] asked -nextObject up to 16 times
	(clang's buffer) before the loop body ran, so dead members were compacted, and the group cleaned
	up, a batch ahead of the body, also when the body returned early. 0 at the end.
*/
NSUInteger ShipGroupCursorBatch(OOShipGroupCursor &cursor, ShipEntity **batch)
{
	NSUInteger count = 0;
	while (count < 16)
	{
		ShipEntity *member = cursor.next();
		if (member == nil)  break;
		batch[count++] = member;
	}
	return count;
}

}	// namespace



/*	A ship made in C++ (oo::NewShipObject, beads oo-9ht.183, oo-9ht.144): the object holding ship,
	the root's facade (OOEntityWithDrawable's until bead oo-9ht.40) (the root's -initWithCxxEntity: stores the part once, so the root's
	-init body runs once, as [super init] did), then the set-up from the definition. The failing
	set-up released the object, as the initialiser did.
*/
ShipEntity *oo::NewShipObject(const Ref<ShipEntity> &ship, const std::string &key, const oo::PList &dict)
{
	if (ship == nullptr)  return nullptr;
	MadeEntityRetained(ship);	// +1, as +alloc gave (its object's, until bead oo-dpyk8)
	if (!ship->initShipSetUp(key, dict))
	{
		ReleaseEntity(ship.get());
		return nullptr;
	}
	return ship.get();
}


// The deleted facade's -initShipSetUpWithKey:definition: (bead oo-9ht.183), unchanged but for self.
bool ShipEntity::initShipSetUp(const std::string &key, const oo::PList &dict)
{
	OOJS_PROFILE_ENTER

	initWithKey(key);

	if (!setUpShipFromDictionary(dict))  return false;

	// Problem observed in testing -- Ahruman
	if (!isfinite(maxFlightSpeed))
	{
		OO_LOG("ship.sanityCheck.failed", "Ship {} {} infinite top speed, clamped to 300.", oo::EntityDescription(this), "generated with");
		maxFlightSpeed = 300;
	}
	return true;

	OOJS_PROFILE_EXIT
}


// The deleted facade's -dealloc body after the subclasses' parts and the weak reference's drop,
// which the root's -dealloc (Entity::willDispose() since bead oo-dpyk8) runs first (bead oo-9ht.144).
void ShipEntity::shipWillDealloc()
{
	/*	NOTE: we guarantee that entityDestroyed is sent immediately after the
		JS ship becomes invalid (as a result of dropping the weakref), i.e.
		with no intervening script activity.
		It has to be after the invalidation so that scripts can't directly or
		indirectly cause the ship to become strong-referenced. (Actually, we
		could handle that situation by breaking out of dealloc, but that's a
		nasty abuse of framework semantics and would require special-casing in
		subclasses.)
		-- Ahruman 2011-02-27
	*/
	ShipScriptEventNoCx(this, "entityDestroyed");

	setTrackCloseContacts(NO);	// deallocs tracking dictionary
	if (ShipEntity *parent = oo::ToShip(parentEntity()))  parent->subEntityReallyDied(this);	// Will do nothing if we're not really a subentity
	clearSubEntities();

	shipAI = nullptr;	// DESTROY
	roleSet = nullptr;
	laser_color = nullptr;
	default_laser_color = nullptr;
	exhaust_emissive_color = nullptr;
	scanner_display_color1 = nullptr;
	scanner_display_color2 = nullptr;
	scanner_display_color_hostile1 = nullptr;
	scanner_display_color_hostile2 = nullptr;
	script = nullptr;
	aiScript = nullptr;
	octree = nullptr;
	_defenseTargets.removeAll();
	_collisionExceptions.removeAll();

	setSubEntityTakingDamage(nullptr);
	removeAllEquipment();

	if (_group != nullptr)  _group->removeShip(this);
	_group = nullptr;
	if (_escortGroup != nullptr)  _escortGroup->removeShip(this);
	_escortGroup = nullptr;

	_lastAegisLock = nullptr;

	_beaconDrawable = nullptr;
}


/*	-cxx_initWithKey:definition:'s body between [super init] and the set-up from the dictionary
	(initShipSetUp() runs both: amendment oo-60fwo).
*/
void ShipEntity::initWithKey(const std::string &key)
{
	_shipKey = key;

	isShip = YES;
	entity_personality = Ranrot() & ENTITY_PERSONALITY_MAX;
	setStatus(STATUS_IN_FLIGHT);
	
	zero_distance = SCANNER_MAX_RANGE2 * 2.0;
	weapon_recharge_rate = 6.0;
	shot_time = INITIAL_SHOT_TIME;
	ship_temperature = SHIP_MIN_CABIN_TEMP;
	weapon_temp				= 0.0f;
	currentWeaponFacing		= WEAPON_FACING_FORWARD;
	forward_weapon_temp		= 0.0f;
	aft_weapon_temp			= 0.0f;
	port_weapon_temp		= 0.0f;
	starboard_weapon_temp	= 0.0f;

	_nextAegisCheck = -0.1f;
	aiScriptWakeTime = 0;
}




static constexpr std::string_view kBoulderRole = "boulder";


static GLfloat cargo_color[4] =		{ 0.9, 0.9, 0.9, 1.0};	// gray
static GLfloat hostile_color[4] =	{ 1.0, 0.25, 0.0, 1.0};	// red/orange
static GLfloat neutral_color[4] =	{ 1.0, 1.0, 0.0, 1.0};	// yellow
static GLfloat friendly_color[4] =	{ 0.0, 1.0, 0.0, 1.0};	// green
static GLfloat missile_color[4] =	{ 0.0, 1.0, 1.0, 1.0};	// cyan
static GLfloat police_color1[4] =	{ 0.5, 0.0, 1.0, 1.0};	// purpley-blue
static GLfloat police_color2[4] =	{ 1.0, 0.0, 0.5, 1.0};	// purpley-red
static GLfloat jammed_color[4] =	{ 0.0, 0.0, 0.0, 0.0};	// clear black
static GLfloat mascem_color1[4] =	{ 0.3, 0.3, 0.3, 1.0};	// dark gray
static GLfloat mascem_color2[4] =	{ 0.4, 0.1, 0.4, 1.0};	// purple
static GLfloat scripted_color[4] = 	{ 0.0, 0.0, 0.0, 0.0};	// to be defined by script


static BOOL IsBehaviourHostile(OOBehaviour behaviour)
{
	switch (behaviour)
	{
		case BEHAVIOUR_ATTACK_TARGET:
		case BEHAVIOUR_ATTACK_FLY_TO_TARGET:
		case BEHAVIOUR_ATTACK_FLY_FROM_TARGET:
		case BEHAVIOUR_RUNNING_DEFENSE:
		case BEHAVIOUR_FLEE_TARGET:
		case BEHAVIOUR_ATTACK_BREAK_OFF_TARGET:
		case BEHAVIOUR_ATTACK_SLOW_DOGFIGHT:
		case BEHAVIOUR_EVASIVE_ACTION:
		case BEHAVIOUR_FLEE_EVASIVE_ACTION:
		case BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX:
	//	case BEHAVIOUR_ATTACK_MINING_TARGET:
		case BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE:
		case BEHAVIOUR_ATTACK_BROADSIDE:
		case BEHAVIOUR_ATTACK_BROADSIDE_LEFT:
		case BEHAVIOUR_ATTACK_BROADSIDE_RIGHT:
 	  case BEHAVIOUR_CLOSE_TO_BROADSIDE_RANGE:
		case BEHAVIOUR_CLOSE_WITH_TARGET:
 	  case BEHAVIOUR_ATTACK_SNIPER:
		case BEHAVIOUR_SCRIPTED_ATTACK_AI:
			return YES;
			
		default:
			return NO;
	}
	
	return 100 < behaviour && behaviour < 120;
}


// The stellar bodies are C++ entities (bead oo-al52f): -position and -radius were the members.
namespace {
float SurfaceDistanceSqaredV(HPVector reference, Entity *stellar)
{
	float centerDistance = HPmagnitude2(HPvector_subtract(stellar->getPosition(), reference));
	float r = OOStellarBodyRadius(stellar);	// [stellar radius] (ShipEntityStellarBodyRadius() until bead oo-9ht.144)
	/*	1.35: empirical value used to help determine proximity when non-nested
			planets are close to each other
		*/
	return centerDistance - 1.35 * r * r;
}


float SurfaceDistanceSqared(Entity *reference, Entity *stellar)
{
	return SurfaceDistanceSqaredV(reference->getPosition(), stellar);
}


OOComparisonResult ComparePlanetsBySurfaceDistance(Entity *e1, Entity *e2, void* context)	// the C++ planets (bead oo-al52f)
{
	HPVector p = static_cast<ShipEntity *>(context)->getPosition();	// the ship (its object until bead oo-9ht.144)
	
	float p1 = SurfaceDistanceSqaredV(p, e1);
	float p2 = SurfaceDistanceSqaredV(p, e2);
	
	if (p1 < p2) return OOOrderedAscending;
	if (p1 > p2) return OOOrderedDescending;
	
	return OOOrderedSame;
}
}	// namespace


Vector cxx_positionOffsetForShipInRotationToAlignment(ShipEntity* ship, Quaternion q, const std::string &align)
{
	// indexed in UTF-16 units, as -characterAtIndex: was
	const std::u16string padAlign = oo::utf8ToUtf16(oo::str::format("%s---", align.c_str()));
	Vector i = vector_right_from_quaternion(q);
	Vector j = vector_up_from_quaternion(q);
	Vector k = vector_forward_from_quaternion(q);
	BoundingBox arbb = ship->findBoundingBoxRelativeToPosition(kZeroHPVector, i, j, k);
	Vector result = kZeroVector;
	switch (padAlign[0])
	{
		case (uint16_t)'c':
		case (uint16_t)'C':
			result.x = 0.5 * (arbb.min.x + arbb.max.x);
			break;
		case (uint16_t)'M':
			result.x = arbb.max.x;
			break;
		case (uint16_t)'m':
			result.x = arbb.min.x;
			break;
	}
	switch (padAlign[1])
	{
		case (uint16_t)'c':
		case (uint16_t)'C':
			result.y = 0.5 * (arbb.min.y + arbb.max.y);
			break;
		case (uint16_t)'M':
			result.y = arbb.max.y;
			break;
		case (uint16_t)'m':
			result.y = arbb.min.y;
			break;
	}
	switch (padAlign[2])
	{
		case (uint16_t)'c':
		case (uint16_t)'C':
			result.z = 0.5 * (arbb.min.z + arbb.max.z);
			break;
		case (uint16_t)'M':
			result.z = arbb.max.z;
			break;
		case (uint16_t)'m':
			result.z = arbb.min.z;
			break;
	}
	return result;
}


/*	Slice 33 (bead oo-tz2ra): -broadcastHitByLaserFrom:'s search for the authorities, without
	messages. Its parameter is the victim's C++ part with the two answers the predicate messaged for,
	read once before the search (both are plain reads); the entities' C++ parts answer the rest
	(getScanClass() is virtual, so an Objective-C subclass's -scanClass still runs).
*/
namespace {

struct AuthorityPredicateParameter
{
	ShipEntity		*victim;
	Entity		*mainStation;			// [UNIVERSE station], the C++ station (bead oo-al52f)
	bool				victimWithinAegis;		// [victim withinStationAegis]
};


BOOL AuthorityPredicate(Entity *entity, void *parameter)
{
	const AuthorityPredicateParameter	*param = (const AuthorityPredicateParameter *)parameter;
	Entity							*entityPart = entity;
	
	// Select main station, if victim is in aegis
	if (entity == param->mainStation && param->victimWithinAegis)
	{
		return YES;
	}
	
	// Select police units in typical scanner range
	if (entityPart->getScanClass() == CLASS_POLICE &&
		HPdistance2(param->victim->getPosition(), entityPart->getPosition()) < SCANNER_MAX_RANGE2)
	{
		return YES;
	}
	
	// Reject others
	return NO;
}

}	// namespace	(AuthorityPredicate joined it when its signature changed, bead oo-9ht.39.23: misc-use-anonymous-namespace)



// The category ShipEntity (SubEntityRelationship); Entity's, which answers NO, is the facade's.
bool ShipEntity::isShipWithSubEntityShip(Entity *other)
{
	assert (getIsShip());
	
	if (!oo::EntityIsShip(other))  return NO;
	if (!oo::EntityIsSubEntity(other))  return NO;
	if (oo::LiveOwner(other) != this)  return NO;
	
#ifndef NDEBUG
	// Sanity check; this should always be true.
	if (!hasSubEntity(other))
	{
		OO_LOG_ERR("ship.subentity.sanityCheck.failed", "{} thinks it's a subentity of {}, but the supposed parent does not agree. {}", oo::EntityShortDescription(other), oo::EntityShortDescription(this), "This is an internal error, please report it.");
		if (other != nullptr)  other->setOwner(nullptr);
		return NO;
	}
#endif
	
	return YES;
}



// Slice 2 of docs/phases/3-slices/ShipEntity.md (bead oo-cvbe3): set-up from the ship dictionary
// (cxx_setUpFromDictionary:). Members of the C++ ship, called directly, since bead oo-9ht.144
// deleted the facade (ADR-0056 amendment oo-9ht.144).

bool ShipEntity::setUpFromDictionary(const oo::PList &inShipDict)
{
	OOJS_PROFILE_ENTER

	// Settings shared by players & NPCs.
	//
	// In order for default values to work and float values to not be junk,
	// replace nil with empty dictionary. -- Ahruman 2008-04-28
	shipinfoDictionary = inShipDict;
	if (shipinfoDictionary.isNull())  shipinfoDictionary = oo::PList(oo::PList::Dict{});
	const oo::PList &shipDict = shipinfoDictionary;	// Ensure no mutation.

	// set these flags explicitly.
	haveExecutedSpawnAction = NO;
	haveStartedJSAI = NO;
	scripted_misjump		= NO;
	_scriptedMisjumpRange		= 0.5;
	being_fined = NO;
	isNearPlanetSurface = NO;
	suppressAegisMessages = NO;
	isMissile = NO;
	suppressExplosion = NO;
	_lightsActive = YES;
	

	// set things from dictionary from here out - default values might require adjustment -- Kaks 20091130
	_scaleFactor = shipDict.get<float>("model_scale_factor", 1.0f);


	float defaultSpeed = isStation ? 0.0f : 160.0f;
	maxFlightSpeed = shipDict.get<float>("max_flight_speed", defaultSpeed);
	max_flight_roll = shipDict.get<float>("max_flight_roll", 2.0f);
	max_flight_pitch = shipDict.get<float>("max_flight_pitch", 1.0f);
	max_flight_yaw = shipDict.get<float>("max_flight_yaw", max_flight_pitch);	// Note by default yaw == pitch
	cruiseSpeed = maxFlightSpeed*0.8f;
	
	max_thrust = shipDict.get<float>("thrust", 15.0f);
	thrust = max_thrust;

	afterburner_rate = shipDict.get<float>("injector_burn_rate", AFTERBURNER_BURNRATE);
	afterburner_speed_factor = shipDict.get<float>("injector_speed_factor", 7.0f);
	if (afterburner_speed_factor < 1.0)
	{
		OO_LOG("ship.setup.injectorSpeed", "injector_speed_factor cannot be lower than 1.0 for {}", oo::EntityDescription(this));
		afterburner_speed_factor = 1.0;
	}
#if OO_VARIABLE_TORUS_SPEED
	else if (afterburner_speed_factor > MIN_HYPERSPEED_FACTOR)
	{
		OO_LOG("ship.setup.injectorSpeed", "injector_speed_factor cannot be higher than minimum torus speed factor ({:f}) for {}.", MIN_HYPERSPEED_FACTOR, oo::EntityDescription(this));
		afterburner_speed_factor = MIN_HYPERSPEED_FACTOR;
	}
#else
	else if (afterburner_speed_factor > HYPERSPEED_FACTOR)
	{
		OO_LOG("ship.setup.injectorSpeed", "injector_speed_factor cannot be higher than torus speed factor ({:f}) for {}.", HYPERSPEED_FACTOR, oo::EntityDescription(this));
		afterburner_speed_factor = HYPERSPEED_FACTOR;
	}
#endif

	maxEnergy = shipDict.get<float>("max_energy", 200.0f);
	energy_recharge_rate = shipDict.get<float>("energy_recharge_rate", 1.0f);
	
	_showDamage = shipDict.get<bool>("show_damage", (energy_recharge_rate > 0));
	// Each new ship should start in seemingly good operating condition, unless specifically told not to - this does not affect the ship's energy levels
	setThrowSparks(shipDict.get<bool>("throw_sparks", NO));
	
	weapon_facings = shipDict.get<int>("weapon_facings", VALID_WEAPON_FACINGS) & VALID_WEAPON_FACINGS;
	if (weapon_facings & WEAPON_FACING_FORWARD)
		forward_weapon_type = cxx_OOWeaponTypeFromString(shipDict.get<std::string>("forward_weapon_type", "EQ_WEAPON_NONE"));
	if (weapon_facings & WEAPON_FACING_AFT)
		aft_weapon_type = cxx_OOWeaponTypeFromString(shipDict.get<std::string>("aft_weapon_type", "EQ_WEAPON_NONE"));
	if (weapon_facings & WEAPON_FACING_PORT)
		port_weapon_type = cxx_OOWeaponTypeFromString(shipDict.get<std::string>("port_weapon_type", "EQ_WEAPON_NONE"));
	if (weapon_facings & WEAPON_FACING_STARBOARD)
		starboard_weapon_type = cxx_OOWeaponTypeFromString(shipDict.get<std::string>("starboard_weapon_type", "EQ_WEAPON_NONE"));

	cloaking_device_active = NO;
	military_jammer_active = NO;
	cloakPassive = shipDict.get<bool>("cloak_passive", YES); // Nikos - switched passive cloak default to YES 20120523
	cloakAutomatic = shipDict.get<bool>("cloak_automatic", YES);

	missiles = shipDict.get<int>("missiles", 0);
	/* TODO: The following initializes the missile list to be blank, which prevents a crash caused by hasOneEquipmentItem trying to access a missile list
	         previously initialized but then released.  See issue #204.  We need to investigate further the cause of the missile list being released.
 			- kanthoney 10/03/2017
		Update 20170818: The issue seems to have been resolved properly using the fix below and the problem was apparently an access of the
		missile_list array elements before their initialization and while we were checking whether equipment can be added or not. There is
		probably not much more that can be done here, unless someone would like to have a go at refactoring the entire ship initialization
		code. In any case, the crash is no more and the applied solution is both simple and logical - Nikos
	*/
	unsigned i;
	for (i = 0; i < missiles; i++)
	{
		missile_list[i] = nil;
	}
	max_missiles = shipDict.get<int>("max_missiles", missiles);
	if (max_missiles > SHIPENTITY_MAX_MISSILES) max_missiles = SHIPENTITY_MAX_MISSILES;
	if (missiles > max_missiles) missiles = max_missiles;
	missile_load_time = fmax(0.0, shipDict.get<double>("missile_load_time", 0.0)); // no negative load times
	missile_launch_time = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) + missile_load_time;
	
	// upgrades:
	equipment_weight = 0; 
	if (FuzzyBooleanForKey(shipDict, "has_ecm"))  addEquipmentItem("EQ_ECM", "npc");
	if (FuzzyBooleanForKey(shipDict, "has_scoop"))  addEquipmentItem("EQ_FUEL_SCOOPS", "npc");
	if (FuzzyBooleanForKey(shipDict, "has_escape_pod"))  addEquipmentItem("EQ_ESCAPE_POD", "npc");
	if (FuzzyBooleanForKey(shipDict, "has_cloaking_device"))  addEquipmentItem("EQ_CLOAKING_DEVICE", "npc");
	if (shipDict.get<float>("has_energy_bomb") > 0)
	{
		/*	NOTE: has_energy_bomb actually refers to QC mines.
			
			max_missiles for NPCs is a newish addition, and ships have
			traditionally not needed to reserve a slot for a Q-mine added this
			way. If has_energy_bomb is possible, and max_missiles is not
			explicit, we add an extra missile slot to compensate.
			-- Ahruman 2011-03-25
		*/
		if (FuzzyBooleanForKey(shipDict, "has_energy_bomb"))
		{
			if (max_missiles == missiles && max_missiles < SHIPENTITY_MAX_MISSILES && shipDict.find("max_missiles") == nullptr)
			{
				max_missiles++;
			}
			addEquipmentItem("EQ_QC_MINE", "npc");
		}
	}

	if (FuzzyBooleanForKey(shipDict, "has_fuel_injection"))  addEquipmentItem("EQ_FUEL_INJECTION", "npc");

#if USEMASC
	if (FuzzyBooleanForKey(shipDict, "has_military_jammer"))  addEquipmentItem("EQ_MILITARY_JAMMER", "npc");
	if (FuzzyBooleanForKey(shipDict, "has_military_scanner_filter"))  addEquipmentItem("EQ_MILITARY_SCANNER_FILTER", "npc");
#endif
	
	
	// can it be 'mined' for alloys?
	canFragment = (unsigned char)FuzzyBooleanForKey(shipDict, "fragment_chance", 0.9);
	isWreckage = NO;

	// can subentities be destroyed separately?
	isFrangible = shipDict.get<bool>("frangible", YES);
	
	max_cargo = shipDict.get<unsigned int>("max_cargo");
	extra_cargo = shipDict.get<unsigned int>("extra_cargo", 15);
	
	hyperspaceMotorSpinTime = shipDict.get<float>("hyperspace_motor_spin_time", DEFAULT_HYPERSPACE_SPIN_TIME);
	if(!shipDict.get<bool>("hyperspace_motor", YES)) hyperspaceMotorSpinTime = -1;
	
	name = shipDict.get<std::string>("name", "?");

	shipUniqueName = shipDict.get<std::string>("ship_name", "");

	shipClassName = shipDict.get<std::string>("ship_class_name", *name);

	displayName = StringForKey(shipDict, "display_name");

	// Load the model (must be before subentities)
	const std::optional<std::string> modelName = StringForKey(shipDict, "model");
	if (modelName.has_value())
	{
		const oo::Ref<::OOMesh> mesh = ::OOMesh::meshWithName(*modelName,
						   oo::str::format("%s-%.3f", _shipKey.value_or("(null)").c_str(), _scaleFactor),	// %@ printed nil as (null)
						   DictionaryForKey(shipDict, "materials"),
						   DictionaryForKey(shipDict, "shaders"),
						   shipDict.get<bool>("smooth", false),
						   OODefaultShipShaderMacros(),
						   this,	// the C++ ship (bead oo-9ht.39.6)
						   _scaleFactor,
						   true);

		if (mesh == nullptr)  return NO;
		setMesh(mesh.get());
	}
	
	float density = shipDict.get<float>("density", 1.0f);
	if (octree)  mass = (GLfloat)(density * 20.0f * octree->volume());
	
	default_laser_color = OOColor::brightColorWithDescription(ValueForKey(shipDict, "laser_color"));
	
	if (default_laser_color == nil) 
	{
		setLaserColor(OOColor::redColor().get());
	}
	else
	{
		setLaserColor(default_laser_color.get());
	}
	// exhaust emissive color
	OORGBAComponents defaultExhaustEmissiveColorComponents; // pale blue is exhaust default color
	defaultExhaustEmissiveColorComponents.r = 0.7f;
	defaultExhaustEmissiveColorComponents.g = 0.9f;
	defaultExhaustEmissiveColorComponents.b = 1.0f;
	defaultExhaustEmissiveColorComponents.a = 0.9f;
	oo::Ref<OOColor>	color = OOColor::brightColorWithDescription(ValueForKey(shipDict, "exhaust_emissive_color"));
	if (color == nil)  color = OOColor::colorWithRGBAComponents(defaultExhaustEmissiveColorComponents);
	setExhaustEmissiveColor(color.get());
	
	clearSubEntities();
	setUpSubEntities();

// correctly initialise weaponRange, etc. (must be after subentity setup)
	if (isWeaponNone(forward_weapon_type))
	{
		OOWeaponType 			weapon_type = nil;
		BOOL hasTurrets = NO;
		for (const auto &sub : shipSubEntities())
		{
			if (!isWeaponNone(weapon_type))  break;
			::ShipEntity *se = oo::ToShip(sub.get());
			weapon_type = se->forward_weapon_type;
			if (se->behaviour == BEHAVIOUR_TRACK_AS_TURRET)
			{
				hasTurrets = YES;
			}
		}
		if (isWeaponNone(weapon_type) && hasTurrets)
		{ /* safety for ships only equipped with turrets
		     note: this was hard-coded to 10000.0, although turrets have a notably 
		     shorter range. We are using a multiplier of 1.667 in order to not change
		     something that already works, but probably it would be best to use
		     TURRET_SHOT_RANGE * COMBAT_WEAPON_RANGE_FACTOR here
		  */
			weaponRange = TURRET_SHOT_RANGE * 1.667;
		}
		else
		{
			setWeaponDataFromType(weapon_type);
		}
	}
	else
	{
		setWeaponDataFromType(forward_weapon_type);
	}
	
	// rotating subentities
	subentityRotationalVelocity = kIdentityQuaternion;
	if (shipDict.find("rotational_velocity") != nullptr)
	{
		subentityRotationalVelocity = QuaternionForKey(shipDict, "rotational_velocity");
	}

	// set weapon offsets
	const oo::PList &weaponMounts = shipDict;
	const std::string weaponMountMode = weaponMounts.get<std::string>("weapon_mount_mode", "single");
	_multiplyWeapons = weaponMountMode == "multiply";
	forwardWeaponOffset = weaponOffsetsFrom(weaponMounts, "weapon_position_forward", weaponMountMode);
	aftWeaponOffset = weaponOffsetsFrom(weaponMounts, "weapon_position_aft", weaponMountMode);
	portWeaponOffset = weaponOffsetsFrom(weaponMounts, "weapon_position_port", weaponMountMode);
	starboardWeaponOffset = weaponOffsetsFrom(weaponMounts, "weapon_position_starboard", weaponMountMode);

	
	tractor_position = vector_multiply_scalar(VectorFromPList(shipDict.find("scoop_position")),_scaleFactor);
	

	// sun glare filter - default is high filter, both for HDR and SDR
	setSunGlareFilter(shipDict.get<float>("sun_glare_filter", 0.97f));
	
	// Get scriptInfo dictionary, containing arbitrary stuff scripts might be interested in.
	scriptInfo = DictionaryForKey(shipDict, "script_info");	// null when absent

	const oo::PList *explosion = ArrayForKey(shipDict, "explosion_type");
	explosionType = explosion != nullptr ? *explosion : oo::PList();	// null when absent

	isDemoShip = NO;
	
	return YES;
	
	OOJS_PROFILE_EXIT
}




// Slice 3 of docs/phases/3-slices/ShipEntity.md (bead oo-mvzmb): setUpShipFromDictionary:,
// subentity serialisation and set-up. Members of the C++ ship, called directly, since bead
// oo-9ht.144 deleted the facade (ADR-0056 amendment oo-9ht.144).

bool ShipEntity::setUpShipFromDictionary(const oo::PList &shipDict)
{
	OOJS_PROFILE_ENTER

	if (!setUpFromDictionary(shipDict)) return NO;

	// NPC-only settings.
	//
	orientation = kIdentityQuaternion;
	rotMatrix	= kIdentityMatrix;
	v_forward	= kBasisZVector;
	v_up		= kBasisYVector;
	v_right		= kBasisXVector;
	reference	= v_forward;  // reference vector for (* turrets *)
	
	isShip = YES;

	// scan class settings. 'scanClass' is in common usage, but we could also have a more standard 'scan_class' key with higher precedence. Kaks 20090810 
	// let's see if scan_class is set... 
	scanClass = cxx_OOScanClassFromString(shipDict.get<std::string>("scan_class", "CLASS_NOT_SET"));
	
	// if not, try 'scanClass'. NOTE: non-standard capitalization is documented and entrenched.
	if (scanClass == CLASS_NOT_SET)
	{
		scanClass = cxx_OOScanClassFromString(shipDict.get<std::string>("scanClass", "CLASS_NOT_SET"));
	}

	scan_description = StringForKey(shipDict, "scan_description");

	// FIXME: give NPCs shields instead.
	
	if (FuzzyBooleanForKey(shipDict, "has_shield_booster"))  addEquipmentItem("EQ_SHIELD_BOOSTER", "npc");
	if (FuzzyBooleanForKey(shipDict, "has_shield_enhancer"))  addEquipmentItem("EQ_SHIELD_ENHANCER", "npc");
	
	// Start with full energy banks.
	energy = maxEnergy;
	weapon_temp				= 0.0f;
	forward_weapon_temp		= 0.0f;
	aft_weapon_temp			= 0.0f;
	port_weapon_temp		= 0.0f;
	starboard_weapon_temp	= 0.0f;
	
	// setWeaponDataFromType inside setUpFromDictionary should set weapon_damage from the front laser.
	// no weapon_damage? It's a missile: set weapon_damage from shipdata!
	if (weapon_damage == 0.0) 
	{
		weapon_damage_override = weapon_damage = shipDict.get<float>("weapon_energy", 0); // any damage value for missiles/bombs
	}
	else
	{
		weapon_damage_override = 0;
	}

	scannerRange = shipDict.get<float>("scanner_range", (float)SCANNER_MAX_RANGE);
	
	fuel = shipDict.get<unsigned short>("fuel");	// Does it make sense that this defaults to 0? Should it not be 70? -- Ahruman
	
	fuel_accumulator = 1.0;
	
	setBounty(shipDict.get<unsigned int>("bounty", 0), kOOLegalStatusReasonSetup);
	
	OOAIAutorelease(std::move(shipAI));	// [shipAI autorelease]
	shipAI = oo::makeRef<::AI>();
	shipAI->setOwner(this);
	setAITo(shipDict.get<std::string>("ai_type", "nullAI.plist"));
	
	likely_cargo = shipDict.get<unsigned int>("likely_cargo");
	noRocks = (unsigned char)FuzzyBooleanForKey(shipDict, "no_boulders");
	
	commodity_amount = 0;
	commodity_type = std::nullopt;
	std::optional<std::string> cargoString = StringForKey(shipDict, "cargo_carried");
	if (cargoString.has_value())
	{
		if (*cargoString == "SCARCE_GOODS")
		{
			cargo_flag = CARGO_FLAG_FULL_SCARCE;
		}
		else if (*cargoString == "PLENTIFUL_GOODS")
		{
			cargo_flag = CARGO_FLAG_FULL_PLENTIFUL;
		}
		else
		{
			cargo_flag = CARGO_FLAG_FULL_UNIFORM;

			std::optional<std::string>	c_commodity;
			int				c_amount = 1;
			oo::str::Scanner	scanner(*cargoString);
			OOCommodities	*commodities = (UNIVERSE != nullptr ? UNIVERSE->getCommodities() : nullptr);	// null: no good is defined, as a message to nil
			if (scanner.scanInt(&c_amount))
			{
				scanner.scanCharactersFromSetNoSkip(oo::str::CharacterSet::whitespace());	// skip whitespace
				c_commodity = scanner.remainder();
				if (commodities != nullptr && commodities->goodDefined(c_commodity.value_or("")))
				{
					setCommodityForPod(c_commodity, c_amount);
				}
				else
				{
					c_commodity = (commodities != nullptr) ? commodities->goodNamed(c_commodity.value_or("")) : std::nullopt;
					if (commodities != nullptr && commodities->goodDefined(c_commodity.value_or("")))
					{
						setCommodityForPod(c_commodity, c_amount);
					}
				}
			}
			else
			{
				c_amount = 1;
				c_commodity = StringForKey(shipDict, "cargo_carried");
				if (commodities != nullptr && commodities->goodDefined(c_commodity.value_or("")))
				{
					setCommodityForPod(c_commodity, c_amount);
				}
				else
				{
					c_commodity = (commodities != nullptr) ? commodities->goodNamed(c_commodity.value_or("")) : std::nullopt;
					if (commodities != nullptr && commodities->goodDefined(c_commodity.value_or("")))
					{
						setCommodityForPod(c_commodity, c_amount);
					}
				}
			}
		}
	}

	cargoString = StringForKey(shipDict, "cargo_type");
	if (cargoString.has_value())
	{
		cargo.clear();

		setUpCargoType(*cargoString);
	}
	else if (scanClass != CLASS_CARGO)
	{
		cargo.clear();
		// if not CLASS_CARGO, and no cargo type set, default to CARGO_NOT_CARGO
		cargo_type = CARGO_NOT_CARGO;
	}
	
	hasScoopMessage = shipDict.get<bool>("has_scoop_message", YES);

	
	roleSet = nullptr;
	if (const oo::Ref<::OORoleSet> roles = ::OORoleSet::roleSetWithString(shipDict.get<std::string>("roles")))  roleSet = roles->roleSetWithRemovedRole("player");
	primaryRole.reset();

	setOwner(this);
	setHulk(shipDict.get<bool>("is_hulk"));
	
	// these are the colors used for the "lollipop" of the ship. Any of the two (or both, for flash effect) can be defined. nil means use default from shipData.
	setScannerDisplayColor1(nullptr);
	setScannerDisplayColor2(nullptr);
	// and the same for the "hostile" colours
	setScannerDisplayColorHostile1(nullptr);
	setScannerDisplayColorHostile2(nullptr);


	// Populate the missiles here. Must come after scanClass.
	_missileRole = StringForKey(shipDict, "missile_role");
	unsigned	i, j;
	for (i = 0, j = 0; i < missiles; i++)
	{
		missile_list[i] = selectMissile();
		// could loop forever (if missile_role is badly defined, selectMissile might return nil in some cases) . Try 3 times, and if no luck, skip
		if (missile_list[i] == nil && j < 3)
		{
			j++;
			i--;
		}
		else
		{
			j = 0;
			if (missile_list[i] == nil)
			{
				missiles--;
			}
		}
	}

	// accuracy. Must come after scanClass, because we are using scanClass to determine if this is a missile.

// missiles: range 0 to +10
// ships: range -5 to +10, but randomly only -5 <= accuracy < +5
// enables "better" AIs at +5 and above
// police and military always have positive accuracy

	accuracy = shipDict.get<float>("accuracy", -100.0f);	// Out-of-range default
	if (accuracy < -5.0f || accuracy > 10.0f)
	{
		accuracy = (randf() * 10.0)-5.0;

		if (accuracy < 0.0f && (scanClass == CLASS_MILITARY || scanClass == CLASS_POLICE))
		{ // police and military pilots have a better average skill. 
			accuracy = -accuracy;
		}
	}
	if (scanClass == CLASS_MISSILE)
	{ // missile accuracy range is 0 to 10
		accuracy = OOClamp_0_max_f(accuracy, 10.0f);
	}
	setAccuracy(accuracy); // set derived variables
	_missed_shots = 0;

	//  escorts
	_maxEscortCount = MIN(shipDict.get<unsigned char>("escorts", 0), (uint8_t)MAX_ESCORTS);
	_pendingEscortCount = _maxEscortCount;
	if (_pendingEscortCount == 0 && ArrayForKey(shipDict, "escort_roles") != nullptr)
	{
		// mostly ignored by setUpMixedEscorts, but needs to be high
		// enough that it doesn't end up at zero (e.g. by governmental
		// reductions in [Universe addShipAt]
		_pendingEscortCount = MAX_ESCORTS;
	}

	
	// beacons
	setBeaconCode(StringForKey(shipDict, "beacon"));
	std::optional<std::string> label = StringForKey(shipDict, "beacon_label");
	if (!label.has_value())  label = StringForKey(shipDict, "beacon");	// the fallback
	setBeaconLabel(label);

	
	// contact tracking entities
	setTrackCloseContacts(shipDict.get<bool>("track_contacts", NO));
	
	// ship skin insulation factor (1.0 is normal)
	setHeatInsulation(shipDict.get<float>("heat_insulation", hasHeatShield() ? 2.0 : 1.0));
	
	// unpiloted (like missiles asteroids etc.)
	_explicitlyUnpiloted = (unsigned char)FuzzyBooleanForKey(shipDict, "unpiloted");
	if (_explicitlyUnpiloted)
	{
		setCrew(std::nullopt);
	}
	else 
	{
		// crew and passengers
		// the one entry of UNIVERSE's characters (a nil key found nothing)
		const std::optional<std::string> pilotKey = StringForKey(shipDict, "pilot");
		oo::PList cdict;
		if (pilotKey.has_value())
		{
			const oo::PList characters = (UNIVERSE != nullptr ? UNIVERSE->getCharacters() : oo::PList());
			if (const oo::PList *entry = characters.find(*pilotKey))  cdict = *entry;
		}
		if (!cdict.isNull())
		{
			oo::Ref<OOCharacter>	pilot = OOCharacter::characterWithDictionary(cdict);
			setCrew(std::vector<oo::Ref<OOCharacter>>{ pilot });
		}
	}
	
	setShipScript(StringForKey(shipDict, "script"));

	home_system = (UNIVERSE != nullptr ? UNIVERSE->currentSystemID() : 0);
	destination_system = (UNIVERSE != nullptr ? UNIVERSE->currentSystemID() : 0);

	reactionTime = shipDict.get<float>("reaction_time", COMBAT_AI_STANDARD_REACTION_TIME);
	
	return YES;
	
	OOJS_PROFILE_EXIT
}


void ShipEntity::setSubIdx(NSUInteger value)
{
	_subIdx = value;
}


NSUInteger ShipEntity::subIdx()
{
	return _subIdx;
}


NSUInteger ShipEntity::maxShipSubEntities()
{
	return _maxShipSubIdx;
}


std::optional<std::string> ShipEntity::serializeShipSubEntities()
{
	std::string			result;
	NSUInteger			diff, i = 0;
	
	for (const auto &sub : shipSubEntities())
	{
		::ShipEntity *se = oo::ToShip(sub.get());
		diff = (se != nullptr ? se->subIdx() : 0) - i;
		i += diff + 1;
		result += RepeatString("0", diff);
		result += "1";
	}
	// add trailing zeroes
	result += RepeatString("0", maxShipSubEntities() - i);
	return result;
}


void ShipEntity::deserializeShipSubEntitiesFrom(const std::string &string)
{
	const std::vector<oo::EntityHold> subEnts = shipSubEntities();
	const std::u16string	units = oo::utf8ToUtf16(string);	// indexed in UTF-16 units, as -substringWithRange: was
	NSInteger			i,idx, start = (NSInteger)subEnts.size() - 1;
	NSInteger			strMaxIdx = (NSInteger)units.size() - 1;
		
	::ShipEntity			*se = nil;
	
	for (i = start; i >= 0; i--)
	{
		se = oo::ToShip(subEnts[(std::size_t)i].get());
		idx = (se != nullptr ? se->subIdx() : 0); // should be identical to i, but better safe than sorry...
		if (idx <= strMaxIdx && units[(std::size_t)idx] == u'0')
		{
			if (se != nullptr)  se->setSuppressExplosion(NO);
			if (se != nullptr)  se->setEnergy(1);
			if (se != nullptr)  se->takeEnergyDamage(500000000.0, nullptr, nullptr, std::string());
		}
	}
}


bool ShipEntity::setUpSubEntities()
{
	OOJS_PROFILE_ENTER
	
	unsigned int	i;
	const oo::PList	shipDict = shipInfoDictionary();
	const oo::PList	*plumes = ArrayForKey(shipDict, "exhaust");

	_profileRadius = collision_radius;
	_maxShipSubIdx = 0;

	for (i = 0; plumes != nullptr && i < plumes->count(); i++)
	{
		// at<std::string>: a string, or a number's text, else "" (no tokens), as the string reader gave.
		const std::vector<std::string> definition = oo::str::tokens(plumes->at<std::string>(i));
		// C++ since bead oo-9ht.110: the plume's object is the root façade; nil for no tokens.
		addSubEntity(oo::MadeEntity(OOExhaustPlumeEntity::exhaustForShip(this, definition, _scaleFactor)));	// its object made as before (null for none)
	}

	const oo::PList	*subs = ArrayForKey(shipDict, "subentities");

	totalBoundingBox = boundingBox;

	for (i = 0; subs != nullptr && i < subs->count(); i++)
	{
		const oo::PList *subentDict = subs->at(i);
		setUpOneSubentity((subentDict != nullptr && subentDict->isDict()) ? *subentDict : oo::PList());
	}
	
	no_draw_distance = _profileRadius * _profileRadius * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR * 2.0;
	
	return YES;
	
	OOJS_PROFILE_EXIT
}


GLfloat ShipEntity::frustumRadius()
{
	OOScalar exhaust_length = 0;
	for (const auto &exhaust : exhausts())
	{
		Entity *exEnt = exhaust.get();
		const double exRadius = exEnt != nullptr ? exEnt->findCollisionRadius() : 0;	// a message to nil answered 0
		if (exRadius > exhaust_length)
		{
			exhaust_length = exRadius;
		}
	}
	return _profileRadius + exhaust_length;
}


bool ShipEntity::setUpOneSubentity(const oo::PList &subentDict)
{
	OOJS_PROFILE_ENTER

	const std::optional<std::string> type = StringForKey(subentDict, "type");
	if (type == "flasher")
	{
		return setUpOneFlasher(subentDict);
	}
	else
	{
		return setUpOneStandardSubentity(subentDict, type == "ball_turret");
	}

	OOJS_PROFILE_EXIT
}


bool ShipEntity::setUpOneFlasher(const oo::PList &subentDict)
{
	// C++ since bead oo-9ht.107: the flasher's object is the nearest façade left.
	const oo::Ref<OOFlasherEntity> flasher = OOFlasherEntity::flasherWithDictionary(subentDict);
	Entity *flasherPart = oo::MadeEntity(flasher);	// its object made as before
	if (flasherPart != nullptr)  flasherPart->setPosition(HPvector_multiply_scalar(HPVectorForKey(subentDict, "position"),_scaleFactor));
	flasher->rescaleBy(_scaleFactor);
	addSubEntity(flasherPart);
	return YES;
}




// Slice 4 of docs/phases/3-slices/ShipEntity.md (bead oo-ln2m1): standard subentities and cargo
// pods; descriptions, mesh, vectors, misjump, subentity lists, AI scripts. Members of the C++ ship,
// called directly, since bead oo-9ht.144 deleted the facade (ADR-0056 amendment oo-9ht.144).

bool ShipEntity::setUpOneStandardSubentity(const oo::PList &subentDict, bool asTurret)
{
	::ShipEntity			*subentity = nil;
	HPVector				subPosition;
	Quaternion			subOrientation;

	const std::optional<std::string> subentKey = StringForKey(subentDict, "subentity_key");
	if (!subentKey.has_value()) {
		OO_LOG("setup.ship.badEntry.subentities", "Failed to set up entity - no subentKey in {}", oo::DescriptionOf(subentDict));
		return NO;
	}

	if (!asTurret && getIsStation() && subentDict.get<bool>("is_dock"))
	{
		subentity = (UNIVERSE != nullptr ? UNIVERSE->newDockWithName(*subentKey, _scaleFactor) : (::ShipEntity *)nil);
	}
	else
	{
		subentity = (UNIVERSE != nullptr ? UNIVERSE->newSubentityWithName(*subentKey, _scaleFactor) : (::ShipEntity *)nil);
	}
	if (subentity == nil) {
		OO_LOG("setup.ship.badEntry.subentities", "Failed to set up entity {}", *subentKey);
		return NO;
	}

	subPosition = HPvector_multiply_scalar(HPVectorForKey(subentDict, "position"),_scaleFactor);
	subOrientation = QuaternionForKey(subentDict, "orientation");
	
	if (subentity != nullptr)  subentity->setPosition(subPosition);
	if (subentity != nullptr)  subentity->setOrientation(subOrientation);
	if (subentity != nullptr)  subentity->setReference(vector_forward_from_quaternion(subOrientation));
	// subentities inherit parent personality
	if (subentity != nullptr)  subentity->setEntityPersonalityInt(entityPersonalityInt());

	if (asTurret)
	{
		if (subentity != nullptr)  subentity->setBehaviour(BEHAVIOUR_TRACK_AS_TURRET);
		if (subentity != nullptr)  subentity->setWeaponRechargeRate(subentDict.get<float>("fire_rate", TURRET_SHOT_FREQUENCY));
		if (subentity != nullptr)  subentity->setWeaponEnergy(subentDict.get<float>("weapon_energy", TURRET_TYPICAL_ENERGY));
		if (subentity != nullptr)  subentity->setWeaponRange(subentDict.get<float>("weapon_range", TURRET_SHOT_RANGE));
		if (subentity != nullptr)  subentity->setStatus(STATUS_ACTIVE);
	}
	else
	{
		if (subentity != nullptr)  subentity->setStatus(STATUS_INACTIVE);
	}
	
	const oo::PList *scriptInfoOverride = subentDict.find("script_info");
	if (subentity != nullptr)  subentity->overrideScriptInfo((scriptInfoOverride != nullptr && scriptInfoOverride->isDict()) ? *scriptInfoOverride : oo::PList());
	
	addSubEntity(subentity);
	if (subentity != nullptr)  subentity->setSubIdx(_maxShipSubIdx);
	_maxShipSubIdx++;
	
	// update subentities
	BoundingBox sebb = (subentity != nullptr ? subentity->findSubentityBoundingBox() : BoundingBox{});
	bounding_box_add_vector(&totalBoundingBox, sebb.max);
	bounding_box_add_vector(&totalBoundingBox, sebb.min);

	if (!asTurret && getIsStation() && subentDict.get<bool>("is_dock"))
	{
		BOOL allow_docking = subentDict.get<bool>("allow_docking", true);
		BOOL ddc = subentDict.get<bool>("disallowed_docking_collides", false);
		BOOL allow_launching = subentDict.get<bool>("allow_launching", true);
		// do not include this key in OOShipRegistry; should never be set by shipdata
		BOOL virtual_dock = subentDict.get<bool>("_is_virtual_dock", false);
		if (virtual_dock)
		{
			if (oo::ToDock(subentity) != nullptr)  oo::ToDock(subentity)->setVirtual();
		}
		
		if (oo::ToDock(subentity) != nullptr)  oo::ToDock(subentity)->setDimensionsAndCorridor(allow_docking, ddc, allow_launching);
		if (subentity != nullptr)  subentity->setDisplayName(subentDict.get<std::string>("dock_label", "the docking bay"));
	}

	if (subentity != nullptr)  oo::ReleaseEntity(subentity);
	
	return YES;
}


bool ShipEntity::isTemplateCargoPod()
{
	return getPrimaryRole() == "oolite-template-cargopod";
}


void ShipEntity::setUpCargoType(const std::string &cargoString)
{
	cargo_type = cxx_StringToCargoType(cargoString);
	
	switch (cargo_type)
	{
		case CARGO_SLAVES:
			commodity_amount = 1;
			commodity_type = "slaves";
			cargo_type = CARGO_RANDOM; // not realy random, but it tells that cargo is selected.
			break;
			
		case CARGO_ALLOY:
			commodity_amount = 1;
			commodity_type = "alloys";
			cargo_type = CARGO_RANDOM;
			break;
			
		case CARGO_MINERALS:
			commodity_amount = 1;
			commodity_type = "minerals";
			cargo_type = CARGO_RANDOM;
			break;
			
		case CARGO_THARGOID:
			commodity_amount = 1;
			commodity_type = "alien_items";
			cargo_type = CARGO_RANDOM;
			break;
			
		case CARGO_SCRIPTED_ITEM:
			commodity_amount = 1; // value > 0 is needed to be recognised as cargo by scripts;
			commodity_type = std::nullopt; // will be defined elsewhere when needed.
			break;
			
		case CARGO_RANDOM:
			// Could already be set by the cargo_carried key. If not, ensure at least one.
			if (commodity_amount == 0) commodity_amount = 1;
			break;

		default:
			break;
	}
}


void ShipEntity::removeScript()
{
	OOScriptAutorelease(std::move(script));	// [script autorelease]
	script = nullptr;
}


void ShipEntity::clearSubEntities()
{
	// Ensure backlinks are broken (last to first, as -makeObjectsPerformSelector:withObject: went)
	for (auto sub = subEntities.rbegin(); sub != subEntities.rend(); ++sub)  if (sub->get() != nullptr)  sub->get()->setOwner(nullptr);
	subEntities.clear();
	
	// reset size & mass!
	collision_radius = findCollisionRadius();
	_profileRadius = collision_radius;
	float density = shipinfoDictionary.get<float>("density", 1.0f);
	if (octree)  mass = (GLfloat)(density * 20.0f * octree->volume());
}


Quaternion ShipEntity::subEntityRotationalVelocity()
{
	return subentityRotationalVelocity;
}


void ShipEntity::setSubEntityRotationalVelocity(Quaternion rv)
{
	subentityRotationalVelocity = rv;
}


std::optional<std::string> ShipEntity::shortDescriptionComponents()
{
	return oo::str::format("\"%s\"", getName().value_or("(null)").c_str());
}


GLfloat ShipEntity::getSunGlareFilter()
{
	return sunGlareFilter;
}


void ShipEntity::setSunGlareFilter(GLfloat newValue)
{
	sunGlareFilter = OOClamp_0_1_f(newValue);
}


GLfloat ShipEntity::getAccuracy()
{
	return accuracy;
}


void ShipEntity::setAccuracy(GLfloat new_accuracy)
{
	if (new_accuracy < 0.0f && scanClass == CLASS_MISSILE)
	{
		new_accuracy = 0.0;
	}
	else if (new_accuracy < -5.0f)
	{
		new_accuracy = -5.0;
	}
	else if (new_accuracy > 10.0f)
	{
		new_accuracy = 10.0;
	}
	accuracy = new_accuracy;
	pitch_tolerance = 0.01 * (85.0f + accuracy);
// especially against small targets, less good pilots will waste some shots
	aim_tolerance = 240.0 - (18.0f * accuracy);

	if (accuracy >= COMBAT_AI_ISNT_AWFUL && missile_load_time < 0.1)
	{
		missile_load_time = 2.0; // smart enough not to waste all missiles on 1 ECM!
	}
}


::OOMesh *ShipEntity::mesh()
{
	return static_cast<::OOMesh *>(getDrawable());	// a ship's drawable is its mesh
}


void ShipEntity::setMesh(::OOMesh *mesh)
{
	if (mesh != this->mesh())
	{
		setDrawable(mesh);
		octree = mesh ? mesh->getOctree() : oo::Ref<Octree>();
	}
}


BoundingBox ShipEntity::getTotalBoundingBox()
{
	return totalBoundingBox;
}


Vector ShipEntity::forwardVector()
{
	return v_forward;
}


Vector ShipEntity::upVector()
{
	return v_up;
}


Vector ShipEntity::rightVector()
{
	return v_right;
}


bool ShipEntity::scriptedMisjump()
{
	return scripted_misjump;
}


void ShipEntity::setScriptedMisjump(bool newValue)
{
	scripted_misjump = !!newValue;
}


GLfloat ShipEntity::scriptedMisjumpRange()
{
	return _scriptedMisjumpRange;
}


void ShipEntity::setScriptedMisjumpRange(GLfloat newValue)
{
	_scriptedMisjumpRange = newValue;
}


std::vector<oo::EntityHold> ShipEntity::getSubEntities()
{
	return subEntities;
}


NSUInteger ShipEntity::subEntityCount()
{
	return subEntities.size();
}


bool ShipEntity::hasSubEntity(Entity *sub)
{
	// Identity: a subentity's -isEqual: is NSObject's.
	return sub != nullptr && std::find(subEntities.begin(), subEntities.end(), sub) != subEntities.end();	// the list holds no null
}


std::vector<oo::EntityHold> ShipEntity::subEntityEnumerator()
{
	return subEntities;
}


std::vector<oo::EntityHold> ShipEntity::shipSubEntities()
{
	std::vector<oo::EntityHold> result;
	for (const auto &sub : subEntities)
	{
		if (oo::EntityIsShip(sub.get()))  result.push_back(sub);
	}
	return result;
}


std::vector<oo::EntityHold> ShipEntity::flasherEnumerator()
{
	std::vector<oo::EntityHold> flashers;
	for (const auto &sub : subEntities)
	{
		if (dynamic_cast<OOFlasherEntity *>(sub.get()) != nullptr)  flashers.push_back(sub);
	}
	return flashers;
}


std::vector<oo::EntityHold> ShipEntity::exhausts()
{
	std::vector<oo::EntityHold> result;
	for (const auto &sub : subEntities)
	{
		if (dynamic_cast<OOExhaustPlumeEntity *>(sub.get()) != nullptr)  result.push_back(sub);
	}
	return result;
}


::ShipEntity *ShipEntity::subEntityTakingDamage()
{
	::ShipEntity *result = oo::ToShip(oo::LiveEntity(_subEntityTakingDamage));
	
#ifndef NDEBUG
	// Sanity check - there have been problems here, see fireLaserShotInDirection:
	// -parentEntity will take care of reporting insanity.
	if ((result != nullptr ? result->parentEntity() : (Entity *)nullptr) != this)  result = nil;
#endif
	
	// Clear the weakref if the subentity is dead.
	if (result == nil)  setSubEntityTakingDamage(nullptr);
	
	return result;
}


void ShipEntity::setSubEntityTakingDamage(::ShipEntity *sub)
{
#ifndef NDEBUG
	// Sanity checks: sub must be a ship subentity of self, or nil.
	if (sub != nil)
	{
		if (!hasSubEntity(sub))
		{
			OO_LOG("ship.subentity.sanityCheck.failed.details", "Attempt to set subentity taking damage of {} to {}, which is not a subentity.", oo::EntityShortDescription(this), oo::EntityDescription(sub));
			sub = nil;
		}
		else if (!(sub != nullptr ? sub->getIsShip() : false))
		{
			OO_LOG("ship.subentity.sanityCheck.failed", "Attempt to set subentity taking damage of {} to {}, which is not a ship.", oo::EntityShortDescription(this), oo::EntityDescription(sub));
			sub = nil;
		}
	}
#endif
	
	_subEntityTakingDamage = oo::WeakRef<Entity>(sub);
}


::OOScript *ShipEntity::shipScript()
{
	return script.get();
}


::OOScript *ShipEntity::shipAIScript()
{
	return aiScript.get();
}


OOTimeAbsolute ShipEntity::shipAIScriptWakeTime()
{
	return aiScriptWakeTime;
}


void ShipEntity::setAIScriptWakeTime(OOTimeAbsolute t)
{
	aiScriptWakeTime = t;
}


std::optional<std::string> ShipEntity::descriptionComponents() const
{
	ShipEntity *self = const_cast<ShipEntity *>(this);	// the getters it called are not const
	if (!self->getIsSubEntity())
	{
		// [super cxx_descriptionComponents]: the entity's own components.
		return oo::str::format("\"%s\" %s", self->getName().value_or("(null)").c_str(), OOEntityWithDrawable::descriptionComponents().value_or("(null)").c_str());
	}
	else
	{
		// ID, scanClass and status are of no interest for subentities.
		const char *subtype = nullptr;
		if (self->getBehaviour() == BEHAVIOUR_TRACK_AS_TURRET)  subtype = "(turret)";
		else  subtype = "(subentity)";

		return oo::str::format("\"%s\" position: %s %s", self->getName().value_or("(null)").c_str(), cxx_HPVectorDescription(self->getPosition()).c_str(), subtype);
	}
}




// Slice 5 of docs/phases/3-slices/ShipEntity.md (bead oo-ddnn8): bounding boxes, octree hit tests,
// universe add / remove, beacons, boulders, escort set-up. Members of the C++ ship, called
// directly, since bead oo-9ht.144 deleted the facade (ADR-0056 amendment oo-9ht.144).

BoundingBox ShipEntity::findBoundingBoxRelativeToPosition(HPVector opv, Vector _i, Vector _j, Vector _k)
{
	// HPVect: check that this conversion doesn't lose needed precision
	::OOMesh *mesh = this->mesh();
	if (mesh == nullptr)  return BoundingBox{};	// a message to nil answered zero
	return mesh->findBoundingBoxRelativeToPosition(HPVectorToVector(opv), _i, _j, _k, HPVectorToVector(position), v_right, v_up, v_forward);
}


Octree *ShipEntity::getOctree()
{
	return octree.get();
}


float ShipEntity::volume()
{
	return octree ? octree->volume() : 0.0f;
}


GLfloat ShipEntity::doesHitLine(HPVector v0, HPVector v1)
{
	Vector u0 = HPVectorToVector(HPvector_between(position, v0));	// relative to origin of model / octree
	Vector u1 = HPVectorToVector(HPvector_between(position, v1));
	Vector w0 = make_vector(dot_product(u0, v_right), dot_product(u0, v_up), dot_product(u0, v_forward));	// in ijk vectors
	Vector w1 = make_vector(dot_product(u1, v_right), dot_product(u1, v_up), dot_product(u1, v_forward));
	return octree ? octree->isHitByLine(w0, w1) : 0.0f;
}


GLfloat ShipEntity::doesHitLine(HPVector v0, HPVector v1, ::ShipEntity **hitEntity)
{
	if (hitEntity)
		hitEntity[0] = (::ShipEntity*)nil;
	Vector u0 = HPVectorToVector(HPvector_between(position, v0));	// relative to origin of model / octree
	Vector u1 = HPVectorToVector(HPvector_between(position, v1));
	Vector w0 = make_vector(dot_product(u0, v_right), dot_product(u0, v_up), dot_product(u0, v_forward));	// in ijk vectors
	Vector w1 = make_vector(dot_product(u1, v_right), dot_product(u1, v_up), dot_product(u1, v_forward));
	GLfloat hit_distance = octree ? octree->isHitByLine(w0, w1) : 0.0f;
	if (hit_distance)
	{
		if (hitEntity)
			hitEntity[0] = this;
	}
	
	for (const auto &sub : shipSubEntities())
	{
		::ShipEntity *se = oo::ToShip(sub.get());
		if (se == nullptr)  continue;	// (shipSubEntities() answers ships)
		HPVector p0 = (se != nullptr ? se->absolutePositionForSubentity() : HPVector{});
		Triangle ijk = (se != nullptr ? se->absoluteIJKForSubentity() : Triangle{});
		u0 = HPVectorToVector(HPvector_between(p0, v0));
		u1 = HPVectorToVector(HPvector_between(p0, v1));
		w0 = resolveVectorInIJK(u0, ijk);
		w1 = resolveVectorInIJK(u1, ijk);
		
		GLfloat hitSub = (se->octree ? se->octree->isHitByLine(w0, w1) : 0.0f);
		if (hitSub && (hit_distance == 0 || hit_distance > hitSub))
		{	
			hit_distance = hitSub;
			if (hitEntity)
			{
				*hitEntity = se;
			}
		}
	}
	
	return hit_distance;
}


GLfloat ShipEntity::doesHitLine(HPVector v0, HPVector v1, HPVector o, Vector i, Vector j, Vector k)
{
	Vector u0 = HPVectorToVector(HPvector_between(o, v0));	// relative to origin of model / octree
	Vector u1 = HPVectorToVector(HPvector_between(o, v1));
	Vector w0 = make_vector(dot_product(u0, i), dot_product(u0, j), dot_product(u0, k));	// in ijk vectors
	Vector w1 = make_vector(dot_product(u1, j), dot_product(u1, j), dot_product(u1, k));
	return octree ? octree->isHitByLine(w0, w1) : 0.0f;
}


void ShipEntity::wasAddedToUniverse()
{
	OOEntityWithDrawable::wasAddedToUniverse();	// [super wasAddedToUniverse]
	
	// if we have a universal id then we can proceed to set up any
	// stuff that happens when we get added to the UNIVERSE
	if (universalID != NO_TARGET)
	{
		// set up escorts
		if ((status() == STATUS_IN_FLIGHT || status() == STATUS_LAUNCHING) && _pendingEscortCount != 0)	// just popped into existence
		{
			setUpEscorts();
		}
		else
		{
			/*	Earlier there was a silly log message here because I thought
				this would never happen, but wasn't entirely sure. Turns out
				it did!
				-- Ahruman 2009-09-13
			*/
			_pendingEscortCount = 0;
		}
	}

	//	Tell subentities, too (last to first, as -makeObjectsPerformSelector: went)
	const std::vector<oo::EntityHold> subs = subEntities;
	for (auto sub = subs.rbegin(); sub != subs.rend(); ++sub)  { if (sub->get() != nullptr)  sub->get()->wasAddedToUniverse(); }
	
	resetExhaustPlumes();
}


void ShipEntity::wasRemovedFromUniverse()
{
	// last to first, as -makeObjectsPerformSelector: went
	const std::vector<oo::EntityHold> subs = subEntities;
	for (auto sub = subs.rbegin(); sub != subs.rend(); ++sub)  { if (sub->get() != nullptr)  sub->get()->wasRemovedFromUniverse(); }
}


HPVector ShipEntity::absoluteTractorPosition()
{
	return HPvector_add(position, vectorToHPVector(quaternion_rotate_vector(normalOrientation(), tractor_position)));
}


std::optional<std::string> ShipEntity::beaconCode()
{
	return _beaconCode;
}


// bcode: optional string; empty is treated as none. The Foundation version compared the new string with the
// old by pointer, so any new string (every string this class hands out is new) replaced it.
void ShipEntity::setBeaconCode(const std::optional<std::string> &bcode)
{
	std::optional<std::string> code = bcode;
	if (code.has_value() && code->empty())  code.reset();

	if (code.has_value() || _beaconCode.has_value())
	{
		_beaconCode = code;

		_beaconDrawable = nullptr;
	}
	// if not blanking code and label is currently blank, default label to code
	if (code.has_value() && (!_beaconLabel.has_value() || _beaconLabel->empty()))
	{
		setBeaconLabel(code);
	}

}


std::optional<std::string> ShipEntity::beaconLabel()
{
	return _beaconLabel;
}


void ShipEntity::setBeaconLabel(const std::optional<std::string> &blabel)
{
	std::optional<std::string> label = blabel;
	if (label.has_value() && label->empty())  label.reset();

	if (label.has_value() || _beaconLabel.has_value())
	{
		_beaconLabel = label.has_value() ? cxx_OOExpand(*label) : std::nullopt;
	}
}


bool ShipEntity::isVisible()
{
	return cam_zero_distance <= no_draw_distance;
}


bool ShipEntity::isBeacon()
{
	return beaconCode().has_value();
}


OOHUDBeaconIcon *ShipEntity::beaconDrawable()
{
	if (_beaconDrawable == nullptr)
	{
		const std::u16string	beaconCode = oo::utf8ToUtf16(_beaconCode.value_or(std::string()));
		NSUInteger	length = beaconCode.size();	// -length: UTF-16 units

		if (length > 1)
		{
			const oo::PList *iconEntry = UNIVERSE->descriptions()->find(*_beaconCode);
			const oo::PList iconData = (iconEntry != nullptr) ? *iconEntry : oo::PList();
			if (iconData.isArray())  _beaconDrawable = OOPolygonSprite::initWithDataArray(iconData, 0.5, *_beaconCode);	// null where it answered nil
		}

		if (_beaconDrawable == nullptr)
		{
			if (length > 0)  _beaconDrawable = oo::makeRef<OOHUDBeaconCodeIcon>(oo::utf16ToUtf8(beaconCode.substr(0, 1)));	// -substringToIndex:1
			else  _beaconDrawable = oo::makeRef<OOHUDBeaconCodeIcon>(std::string());
		}
}
	
	return _beaconDrawable.get();
}


// The beacons' C++ entities since bead oo-9ht.39.23: null when the object is gone, as the object was nil.
Entity *ShipEntity::prevBeacon()
{
	return oo::LiveEntity(_prevBeacon);
}


Entity *ShipEntity::nextBeacon()
{
	return oo::LiveEntity(_nextBeacon);
}


// Through the virtual nextBeacon() (a test's player answers it) (bead oo-9ht.39.8.10): the JS bindings compare
// the C++ entity, which nextBeacon() answers since bead oo-9ht.39.23.
Entity *ShipEntity::nextBeaconEntity()
{
	return nextBeacon();
}


void ShipEntity::setPrevBeacon(Entity *beaconShip)
{
	if (beaconShip != prevBeacon())
	{
		_prevBeacon = oo::WeakRef<Entity>(beaconShip);
	}
}


void ShipEntity::setNextBeacon(Entity *beaconShip)
{
	if (beaconShip != nextBeacon())
	{
		_nextBeacon = oo::WeakRef<Entity>(beaconShip);
	}
}


void ShipEntity::setIsBoulder(bool flag)
{
	if (flag)  addRole(std::string(kBoulderRole));
	else  removeRole(std::string(kBoulderRole));
}


bool ShipEntity::isBoulder()
{
	return roleSet != nullptr && roleSet->hasRole(std::string(kBoulderRole));
}


bool ShipEntity::isMinable()
{
	if (hasRole("asteroid") || isBoulder())
	{
		if (!noRocks)
		{
			return YES;
		}
	}
	return NO;
}


bool ShipEntity::countsAsKill()
{
	return shipinfoDictionary.get<bool>("counts_as_kill", true);
}


void ShipEntity::setUpEscorts()
{
	// Ensure that we do not try to create escorts if we are an escort ship ourselves.
	// This could lead to circular reference memory overflows (e.g. "boa-mk2" trying to create 4 "boa-mk2"
	// escorts or the case of two ships specifying eachother as escorts) - Nikos 20090510
	if (isEscort())
	{
		OO_LOG_WARN("ship.setUp.escortShipCircularReference", 
				"Ship {} requested escorts, when it is an escort ship itself. Avoiding possible circular reference overflow by ignoring escort setup.", oo::EntityDescription(this));
		return;
	}

	const oo::PList		&info = shipinfoDictionary;
	if (info.find("escort_roles") != nullptr)
	{
		setUpMixedEscorts();
		return;
	}

	std::string						defaultRole = "escort";
	std::string						escortRole;
	std::optional<std::string>		escortShipKey;
	
	if (_pendingEscortCount == 0)  return;
	
	if (_maxEscortCount < _pendingEscortCount)
	{
		if (hasPrimaryRole("police") || hasPrimaryRole("hunter"))
		{
			_maxEscortCount = MAX_ESCORTS; // police and hunters get up to MAX_ESCORTS, overriding the 'escorts' key.
			updateEscortFormation();
		}
		else
		{
			_pendingEscortCount = _maxEscortCount;	// other ships can only get what's defined inside their 'escorts' key.
		}
	}
	
	if (isPolice())  defaultRole = "wingman";

	const std::optional<std::string> escortRoleSetting = StringForKey(info, "escort_role");
	escortRole = escortRoleSetting.has_value() ? *escortRoleSetting : info.get<std::string>("escort-role", defaultRole);
	if (escortRole != defaultRole)
	{
		if (!oo::ToShip(oo::AutoreleaseEntity((UNIVERSE != nullptr ? UNIVERSE->newShipWithRole(escortRole) : (::ShipEntity *)nil))))
		{
			escortRole = defaultRole;
		}
	}

	escortShipKey = StringForKey(info, "escort_ship");
	if (!escortShipKey.has_value())
		escortShipKey = StringForKey(info, "escort-ship");

	if (escortShipKey.has_value())
	{
		if (!oo::ToShip(oo::AutoreleaseEntity((UNIVERSE != nullptr ? UNIVERSE->newShipWithName(*escortShipKey) : (::ShipEntity *)nil))))
		{
			escortShipKey = std::nullopt;
		}
		else
		{
			escortRole = oo::str::format("[%s]", escortShipKey->c_str());
		}
	}

	::OOShipGroup *escortGroup = this->escortGroup();
	if (group() == nil)
	{
		setGroup(escortGroup); // should probably become a copy of the escortGroup post NMSR.
	}
	if (escortGroup != nullptr)  escortGroup->setLeader(this);
	
	refreshEscortPositions();
	
	uint8_t currentEscortCount = (escortGroup != nullptr ? escortGroup->count() : 0) - 1;	// always at least 0.
	
	while (_pendingEscortCount > 0 && (isThargoid() || currentEscortCount < _maxEscortCount))
	{
		 // The following line adds escort 1 in position 1, etc... up to MAX_ESCORTS.
		HPVector ex_pos = coordinatesForEscortPosition(currentEscortCount);
		
		::ShipEntity *escorter = nil;
		
		escorter = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole(escortRole) : (::ShipEntity *)nil);	// retained

		if (escorter == nil)  break;
		setUpOneEscort(escorter, escortGroup, escortRole, ex_pos, currentEscortCount);

		if (escorter != nullptr)  oo::ReleaseEntity(escorter);

		_pendingEscortCount--;
		currentEscortCount = (escortGroup != nullptr ? escortGroup->count() : 0) - 1;
	}
	// done assigning escorts
	_pendingEscortCount = 0;
}


void ShipEntity::setUpMixedEscorts()
{
	const oo::PList &info = shipinfoDictionary;
	const oo::PList *escortRoles = ArrayForKey(info, "escort_roles");
	if (escortRoles == nullptr)
	{
		OO_LOG_WARN("eship.setUp.escortShipRoles",
				  "Ship {} has bad escort_roles definition.", oo::EntityDescription(this));
		return;
	}
	OOGovernmentID		government;

	const oo::PList systeminfo = (UNIVERSE != nullptr ? UNIVERSE->currentSystemData() : oo::PList());
 	government = systeminfo.get<unsigned char>(std::string(KEY_GOVERNMENT));

	::OOShipGroup *escortGroup = this->escortGroup();
	if (group() == nil)
	{
		setGroup(escortGroup); // should probably become a copy of the escortGroup post NMSR.
	}
	if (escortGroup != nullptr)  escortGroup->setLeader(this);
	_maxEscortCount = MAX_ESCORTS;
	refreshEscortPositions();
	
	uint8_t currentEscortCount = (escortGroup != nullptr ? escortGroup->count() : 0) - 1;	// always at least 0
	
	_maxEscortCount = 0;
	int8_t i = 0;
	for (const oo::PList &escortDefinition : *escortRoles->getIf<oo::PList::Array>())
	{
		if (currentEscortCount >= MAX_ESCORTS)
		{
			break;
		}
		// int rather than uint because, at least for min, there is a
		// use to giving a negative value
		int8_t min = escortDefinition.get<int>("min", 0);
		int8_t max = escortDefinition.get<int>("max", 2);
		const std::string escortRole = escortDefinition.get<std::string>("role", "escort");
		int8_t desired = max;
		if (min < desired)
		{
			for (i = min ; i < max ; i++)
			{
				if (Ranrot()%11 < static_cast<unsigned>(government)+2)	// unsigned, as the comparison converted it (GCC -Wsign-compare; bead oo-1q4)
				{
					desired--;
				}
			}
		}
		for (i = 0; i < desired; i++)
		{
			if (currentEscortCount >= MAX_ESCORTS)
			{
				break;
			}
			if (!escortRole.empty())
			{
				HPVector ex_pos = coordinatesForEscortPosition(currentEscortCount);
				::ShipEntity *escorter = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole(escortRole) : (::ShipEntity *)nil);	// retained
				if (escorter == nil)
				{
					break;
				}
				setUpOneEscort(escorter, escortGroup, escortRole, ex_pos, currentEscortCount);
				if (escorter != nullptr)  oo::ReleaseEntity(escorter);
			}
			currentEscortCount++;
			_maxEscortCount++;
		}
	}
	// done assigning escorts
	_pendingEscortCount = 0;
}




// Slice 6 of docs/phases/3-slices/ShipEntity.md (bead oo-5z5wd): escort creation, ship data key,
// weapon offsets, octree collision checks, subentity geometry, escape-pod launch. Members of the
// C++ ship, called directly, since bead oo-9ht.144 deleted the facade (ADR-0056 amendment
// oo-9ht.144).
/*	Slice 6 (bead oo-5z5wd): the octree collision check, without messages: the ships' C++ parts
	answer their positions, frames and -canCollide (a virtual member, so PlayerEntity's override
	still runs), and the octrees' C++ objects test the hit.
*/
::ShipEntity *doOctreesCollide(::ShipEntity *prime, ::ShipEntity *other)
{
	// octree check
	Octree		*prime_octree = prime->octree.get();
	Octree		*other_octree = other->octree.get();
	
	HPVector		prime_position = prime->absolutePositionForSubentity();
	Triangle	prime_ijk = prime->absoluteIJKForSubentity();
	HPVector		other_position = other->absolutePositionForSubentity();
	Triangle	other_ijk = other->absoluteIJKForSubentity();

	Vector		relative_position_of_other = resolveVectorInIJK(HPVectorToVector(HPvector_between(prime_position, other_position)), prime_ijk);
	Triangle	relative_ijk_of_other;
	relative_ijk_of_other.v[0] = resolveVectorInIJK(other_ijk.v[0], prime_ijk);
	relative_ijk_of_other.v[1] = resolveVectorInIJK(other_ijk.v[1], prime_ijk);
	relative_ijk_of_other.v[2] = resolveVectorInIJK(other_ijk.v[2], prime_ijk);
	
	// check hull octree against other hull octree
	// [nil isHitByOctree:...] answered NO.
	if (prime_octree != nullptr && prime_octree->isHitByOctree(other_octree,
						 relative_position_of_other,
							 relative_ijk_of_other))
	{
		return other;
	}
	
	// check prime subentities against the other's hull
	const std::vector<oo::EntityHold> &prime_subs = prime->subEntities;
	if (!prime_subs.empty())
	{
		NSUInteger i, n_subs = prime_subs.size();
		for (i = 0; i < n_subs; i++)
		{
			Entity* se = prime_subs[i].get();
			if (se->getIsShip() && se->canCollide() && doOctreesCollide(oo::ToShip(se), other))
				return other;
		}
	}

	// check prime hull against the other's subentities
	const std::vector<oo::EntityHold> &other_subs = other->subEntities;
	if (!other_subs.empty())
	{
		NSUInteger i, n_subs = other_subs.size();
		for (i = 0; i < n_subs; i++)
		{
			Entity* se = other_subs[i].get();
			if (se->getIsShip() && se->canCollide() && doOctreesCollide(prime, oo::ToShip(se)))
				return oo::ToShip(se);
		}
	}
	
	// check prime subenties against the other's subentities
	if ((!prime_subs.empty())&&(!other_subs.empty()))
	{
		NSUInteger i, n_osubs = other_subs.size();
		for (i = 0; i < n_osubs; i++)
		{
			Entity* oe = other_subs[i].get();
			if (oe->getIsShip() && oe->canCollide())
			{
				NSUInteger j, n_psubs = prime_subs.size();
				for (j = 0; j <  n_psubs; j++)
				{
					Entity* pe = prime_subs[j].get();
					if (pe->getIsShip() && pe->canCollide() && doOctreesCollide(oo::ToShip(pe), oo::ToShip(oe)))
						return oo::ToShip(oe);
				}
			}
		}
	}

	// fall through => no collision
	return nil;
}



void ShipEntity::setUpOneEscort(::ShipEntity *escorter, ::OOShipGroup *escortGroup, const std::string &/*escortRole*/, HPVector ex_pos, uint8_t currentEscortCount)
{
	std::string		autoAI;
	std::string		pilotRole;
	::AI				*escortAI = nil;
	std::string		defaultRole = "escort";

	if (isPolice())
	{
		defaultRole = "wingman";
		pilotRole = "police"; // police are always insured.
	}
	else
	{
		pilotRole = bounty ? "pirate" : "hunter"; // hunters have insurancies, pirates not.
	}
	
	double dd = escorter->collision_radius;
		
	if (EXPECT(currentEscortCount < (uint8_t)MAX_ESCORTS))
	{
		// spread them around a little randomly
		ex_pos.x += dd * 6.0 * (randf() - 0.5);
		ex_pos.y += dd * 6.0 * (randf() - 0.5);
		ex_pos.z += dd * 6.0 * (randf() - 0.5);
	}
	else
	{
		// Thargoid armada(!) Add more distance between the 'escorts'.
		ex_pos.x += dd * 12.0 * (randf() - 0.5);
		ex_pos.y += dd * 12.0 * (randf() - 0.5);
		ex_pos.z += dd * 12.0 * (randf() - 0.5);
	}
		
	if (escorter != nullptr)  escorter->setPosition(ex_pos);	// minimise lollipop flash
		
	if (!(escorter != nullptr ? escorter->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>()).has_value())
	{
		if (escorter != nullptr)  escorter->setSingleCrewWithRole(pilotRole);
	}

	if (escorter != nullptr)  escorter->setPrimaryRole(defaultRole);	//for mothership
	// in case this hasn't yet been set, make sure escorts get a real scan class
	// shouldn't happen very often, but is possible
	if (scanClass == CLASS_NOT_SET)
	{
		scanClass = CLASS_NEUTRAL;
	}
	if (escorter != nullptr)  escorter->setScanClass(scanClass);		// you are the same as I
		
	if (getBounty() == 0)  { if (escorter != nullptr)  escorter->setBounty(0, kOOLegalStatusReasonSetup); }	// Avoid dirty escorts for clean mothers
		
	// find the right autoAI.
	const oo::PList autoAIMap = ResourceManager::dictionaryFromFilesNamed("autoAImap.plist", "Config", YES);
	const std::optional<std::string> mappedAI = StringForKey(autoAIMap, defaultRole);
	if (mappedAI.has_value())  autoAI = *mappedAI;
	else // no 'wingman' defined in autoAImap?
	{
		autoAI = autoAIMap.get<std::string>("escort", "nullAI.plist");
	}

	escortAI = (escorter != nullptr ? escorter->getAI() : (::AI *)nullptr);

	// Let the populator decide which AI to use, unless we have a working alternative AI & we specify auto_ai = NO !
	// (Both callers always passed a role, so the old nil test of escortRole was always true.)
	if ( FuzzyBooleanForKey((escorter != nullptr ? escorter->shipInfoDictionary() : oo::PList()), "auto_ai", YES)
		 || ((escortAI != nullptr ? escortAI->name() : std::optional<std::string>()).value_or(std::string()) == "nullAI.plist" && autoAI != "nullAI.plist") )
	{
		if (escorter != nullptr)  escorter->switchAITo(autoAI);
	}

	if (escorter != nullptr)  escorter->setGroup(escortGroup);
	if (escorter != nullptr)  escorter->setOwner(this);	// mark self as group leader

	
	if (status() == STATUS_DOCKED)
	{
		// A station's object is a ship's since bead oo-9ht.175, and a dock's since bead
		// oo-9ht.180: their C++ parts answer (no other owner answered the selector).
		if (::StationEntity *station = oo::ToStation(owner()))  station->addShipToLaunchQueue(escorter, NO);
		else if (::DockEntity *dock = oo::ToDock(owner()))  dock->addShipToLaunchQueue(escorter, NO);
	}
	else
	{
		if (UNIVERSE != nullptr)  UNIVERSE->addEntity(escorter); 	// STATUS_IN_FLIGHT, AI state GLOBAL
		if (escortAI != nullptr)  escortAI->setState("FLYING_ESCORT");	// Begin escort flight. (If the AI doesn't define FLYING_ESCORT, this has no effect.)
		if (escorter != nullptr)  escorter->doScriptEvent(OOJSID("spawnedAsEscort"), this);
	}
	
	if((escorter != nullptr ? escorter->heatInsulation() : 0.0f) < heatInsulation()) { if (escorter != nullptr)  escorter->setHeatInsulation(heatInsulation()); } // give escorts same protection as mother.
	if(((escorter != nullptr ? escorter->getMaxFlightSpeed() : 0.0f) < cruiseSpeed) && ((escorter != nullptr ? escorter->getMaxFlightSpeed() : 0.0f) > cruiseSpeed * 0.3)) 
		cruiseSpeed = (escorter != nullptr ? escorter->getMaxFlightSpeed() : 0.0f) * 0.99;  // adapt patrolSpeed to the slowest escort but ignore the very slow ones.
		
		
	if (bounty)
	{
		int extra = 1 | (ranrot_rand() & 15);
		// if mothership is offender, make sure escorter is too.
		if (escorter != nullptr)  escorter->markAsOffender(extra, kOOLegalStatusReasonSetup);
	}
	else
	{
		// otherwise force the escort to be clean
		if (escorter != nullptr)  escorter->setBounty(0, kOOLegalStatusReasonSetup);
	}
	
}


std::optional<std::string> ShipEntity::shipDataKey()
{
	return _shipKey;
}


std::optional<std::string> ShipEntity::shipDataKeyAutoRole()
{
	return oo::str::format("[%s]", shipDataKey().value_or("(null)").c_str());	// %@ printed nil as (null)
}


void ShipEntity::setShipDataKey(const std::optional<std::string> &key)
{
	_shipKey = key;
}


oo::PList ShipEntity::shipInfoDictionary()
{
	return shipinfoDictionary;
}


std::vector<Vector> ShipEntity::weaponOffsetsFrom(const oo::PList &dict, const std::string &key, const std::string &mode)
{
	Vector offset;
	if (mode == "single")
	{
		offset = vector_multiply_scalar(VectorFromPList(dict.find(key)),_scaleFactor);
		return { offset };
	}
	else
	{
		const oo::PList *offsets = ArrayForKey(dict, key);
		if (offsets == nullptr) {
			offset = kZeroVector;
			return { offset };
		}
		std::vector<Vector> output;
		output.reserve(offsets->count());
		NSUInteger i;
		for (i=0;i<offsets->count();i++) {
			offset = vector_multiply_scalar(VectorFromPList(offsets->at(i)),_scaleFactor);
			output.push_back(offset);
		}
		return output;
	}
}


std::vector<Vector> ShipEntity::getAftWeaponOffset()
{
	return aftWeaponOffset;
}


std::vector<Vector> ShipEntity::getForwardWeaponOffset()
{
	return forwardWeaponOffset;
}


std::vector<Vector> ShipEntity::getPortWeaponOffset()
{
	return portWeaponOffset;
}


std::vector<Vector> ShipEntity::getStarboardWeaponOffset()
{
	return starboardWeaponOffset;
}


bool ShipEntity::getIsFrangible()
{
	return isFrangible;
}


bool ShipEntity::suppressFlightNotifications()
{
	return suppressAegisMessages;
}


OOScanClass ShipEntity::getScanClass()
{
	if (cloaking_device_active)  return CLASS_NO_DRAW;
	return scanClass;
}


//////////////////////////////////////////////

bool ShipEntity::canCollide()
{
	int status = this->status();
	if (status == STATUS_COCKPIT_DISPLAY || status == STATUS_DEAD || status == STATUS_BEING_SCOOPED)
	{	
		return NO;
	}

	if (isWreckage)
	{
		// wreckage won't collide
		return NO;
	}
	
	if (isMissile && shotTime() < 0.25) // not yet fused
	{
		return NO;
	}
	
	return YES;
}


BoundingBox ShipEntity::findSubentityBoundingBox()
{
	::OOMesh *mesh = this->mesh();
	if (mesh == nullptr)  return BoundingBox{};	// a message to nil answered zero
	return mesh->findSubentityBoundingBoxWithPosition(HPVectorToVector(position), rotMatrix);
}


Triangle ShipEntity::absoluteIJKForSubentity()
{
	Triangle	result = {{ kBasisXVector, kBasisYVector, kBasisZVector }};
	Entity		*last = nullptr;
	Entity		*father = this;	// the C++ entities, which the objects forwarded to (bead oo-9ht.39.16)
	OOMatrix	r_mat;
	
	// NO_TARGET is 0, so the old `father != (Entity *)NO_TARGET` test only repeated the null check.
	while ((father)&&(father != last))
	{
		r_mat = father->drawRotationMatrix();
		result.v[0] = OOVectorMultiplyMatrix(result.v[0], r_mat);
		result.v[1] = OOVectorMultiplyMatrix(result.v[1], r_mat);
		result.v[2] = OOVectorMultiplyMatrix(result.v[2], r_mat);
		
		last = father;
		if (!oo::EntityIsSubEntity(last)) break;
		father = oo::LiveOwner(father);
	}
	return result;
}


void ShipEntity::addSubentityToCollisionRadius(Entity *subent)
{
	if (!subent)  return;
	
	double distance = HPmagnitude(subent->getPosition()) + subent->findCollisionRadius();
	if ((oo::ToShip(subent) != nullptr))	// Solid subentity
	{
		if (distance > collision_radius)
		{
			collision_radius = distance;
		}
		
		mass += subent->getMass();
	}
	if (distance > _profileRadius)
	{
		_profileRadius = distance;
	}
}


::ShipEntity *ShipEntity::launchPodWithCrew(const std::vector<oo::Ref<OOCharacter>> &podCrew)
{
	::ShipEntity *pod = nil;

	const oo::PList &info = shipinfoDictionary;
	pod = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole(StringForKey(info, "escape_pod_role").value_or("")) : (::ShipEntity *)nil);	// or nil
	if (!pod)
	{
		//	_role not defined? it might have _model defined;
		pod = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole(info.get<std::string>("escape_pod_model", "escape-capsule")) : (::ShipEntity *)nil);
		if (!pod)
		{
			pod = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole("escape-capsule") : (::ShipEntity *)nil);
			OO_LOG("shipEntity.noEscapePod", "Ship {} has no correct escape_pod_role defined. Now using default capsule.", oo::EntityDescription(this));
		}
	}
	
	if (pod)
	{
		if (pod != nullptr)  pod->setOwner(this);
		if (pod != nullptr)  pod->setTemperature(randomEjectaTemperatureWithMaxFactor(0.9));
		if (pod != nullptr)  pod->setCommodity("slaves", 1);
		if (pod != nullptr)  pod->setCrew(podCrew);
		if (pod != nullptr)  pod->switchAITo("oolite-shuttleAI.js");
		dumpItem(pod);	// CLASS_CARGO, STATUS_IN_FLIGHT, AI state GLOBAL
		if (pod != nullptr)  oo::ReleaseEntity(pod); //release
	}
	
	return pod;
}


bool ShipEntity::validForAddToUniverse()
{
	if (shipinfoDictionary.isNull())
	{
		OO_LOG("shipEntity.notDict", "Ship {} was not set up from dictionary.", oo::EntityDescription(this));
		return NO;
	}
	return OOEntityWithDrawable::validForAddToUniverse();	// [super validForAddToUniverse]
}


bool ShipEntity::checkCloseCollisionWith(Entity *otherPart)
{
	if (oo::WithObject(otherPart) == nullptr)  return NO;	// (no object: nil)
	if (std::find_if(collidingEntities.begin(), collidingEntities.end(), [otherPart](const oo::EntityHold &e) { return e.get() == otherPart; }) != collidingEntities.end())  return NO;	// we know about this already! (-containsObject:, identity for entities)
	
	::ShipEntity *otherShip = nil;
	if (oo::EntityIsShip(otherPart))  otherShip = oo::ToShip(otherPart);
	
	if (canScoop(otherShip))  return YES;	// quick test - could this improve scooping for small ships? I think so!
	
	if (otherShip != nil && trackCloseContacts)
	{
		// in update we check if close contacts have gone out of touch range (origin within our collision_radius)
		// here we check if something has come within that range
		HPVector			otherPos = (otherShip != nullptr ? otherShip->getPosition() : HPVector{});
		OOUniversalID	otherID = (otherShip != nullptr ? otherShip->getUniversalID() : OOUniversalID{});
		const std::string	other_key = oo::str::format("%d", otherID);

		if (!closeContactsInfo.contains(other_key) &&
			HPdistance2(position, otherPos) < collision_radius * collision_radius)
		{
			// calculate position with respect to our own position and orientation
			Vector	dpos = HPVectorToVector(HPvector_between(position, otherPos));
			Vector  rpos = make_vector(dot_product(dpos, v_right), dot_product(dpos, v_up), dot_product(dpos, v_forward));
			closeContactsInfo[other_key] = oo::str::format("%f %f %f", rpos.x, rpos.y, rpos.z);
			
			// send AI a message about the touch
			const oo::WeakRef<Entity>	temp = _primaryTarget;
			_primaryTarget = oo::WeakRef<Entity>(otherShip);
			doScriptEvent(OOJSID("shipCloseContact"), otherShip, "CLOSE CONTACT");
			_primaryTarget = temp;
		}
	}
	
	/* This does not appear to save a significant amount of time in
	 * most situations. No significant change in frame rate with a
	 * 350-segment planetary ring at 1400 collision candidates, even
	 * on old hardware. There are perhaps situations in which it could
	 * be a significant optimisation, but those are likely to also be
	 * the situations where the effect of adding hundreds of extra
	 * false-positive collisions leaves the player returning to a
	 * mess... So, commented out: CIM 21 Jan 2014
	if (zero_distance > CLOSE_COLLISION_CHECK_MAX_RANGE2)	// don't work too hard on entities that are far from the player
	return YES; 
	*/
	
	if (otherShip != nil)
	{
		// check hull octree versus other hull octree
		collider = doOctreesCollide(this, otherShip);	// the C++ part (bead oo-9ht.39.4)
		return (collider != nil);
	}
	
	// default at this stage is to say YES they've collided!
	collider = otherPart;
	return YES;
}




// Slice 7 of docs/phases/3-slices/ShipEntity.md (bead oo-k2q1f): update:. Members of the C++ ship,
// called directly, since bead oo-9ht.144 deleted the facade (ADR-0056 amendment oo-9ht.144).

void ShipEntity::update(OOTimeDelta delta_t)
{
	if (shipinfoDictionary.isNull())
	{
		OO_LOG("shipEntity.notDict", "Ship {} was not set up from dictionary.", oo::EntityDescription(this));
		if (UNIVERSE != nullptr)  UNIVERSE->removeEntity(this);
		return;
	}
	
	if (!isfinite(maxFlightSpeed))
	{
		OO_LOG("ship.sanityCheck.failed", "Ship {} {} infinite top speed, clamped to 300.", oo::EntityDescription(this), "had");
		maxFlightSpeed = 300;
	}

	bool isSubEnt = getIsSubEntity();

	if (isDemoShip)
	{
		if (demoRate > 0)
		{
			OOScalar cos1 = cos(M_PI * ((UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) - demoStartTime) * demoRate / 11);
			OOScalar sin1 = sin(M_PI * ((UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) - demoStartTime) * demoRate / 11);
			OOScalar cos2 = cos(-M_PI * ((UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) - demoStartTime) * demoRate / 15);
			OOScalar sin2 = sin(-M_PI * ((UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) - demoStartTime) * demoRate / 15);
			Quaternion q1 = make_quaternion(cos1, sin1*sqrt(3)/2, sin1/2, 0);
			Quaternion q2 = make_quaternion(cos2, -sin2*sqrt(4)/sqrt(5), 0, sin2*sqrt(1)/sqrt(5));
			setOrientation(quaternion_multiply(q2, quaternion_multiply(q1, demoStartOrientation)));
		}

		OOEntityWithDrawable::update(delta_t);	// [super update:delta_t]
		if (subEntityCount() > 0)
		{
			// only copy the subent array if there are subentities
			const std::vector<oo::EntityHold> subs = subEntities;	// a snapshot, as -subEntities copied
			for (const auto &sub : subs)
			{
				::ShipEntity *se = oo::ToShip(sub.get());
				if (se != nullptr)  se->update(delta_t);
				if ((se != nullptr ? se->getIsShip() : false))
				{
					BoundingBox sebb = (se != nullptr ? se->findSubentityBoundingBox() : BoundingBox{});
					bounding_box_add_vector(&totalBoundingBox, sebb.max);
					bounding_box_add_vector(&totalBoundingBox, sebb.min);
				}
			}
		}
		return;
	}


	if (!isSubEnt)
	{
		if (scanClass == CLASS_NOT_SET)
		{
			scanClass = CLASS_NEUTRAL;
			OO_LOG("ship.sanityCheck.failed", "Ship {} {} with scanClass CLASS_NOT_SET; forced to CLASS_NEUTRAL.", oo::EntityDescription(this), getPrimaryRole().value_or("(null)"));
		}

		updateTrackingCurve();

		//
		// deal with collisions
		//
		manageCollisions();

    // subentity collisions managed via parent entity
	
		//
		// reset any inadvertant legal mishaps
		//
		if (scanClass == CLASS_POLICE)
		{
			if (bounty > 0)
			{
				setBounty(0, kOOLegalStatusReasonPoliceAreClean);
			}
			::ShipEntity* target = oo::ToShip(primaryTarget());
			if ((target)&&((target != nullptr ? target->getScanClass() : OOScanClass{}) == CLASS_POLICE))
			{
				noteLostTarget();
			}
		}
		
		if (trackCloseContacts)
		{
			// in checkCloseCollisionWith: we check if some thing has come within touch range (origin within our collision_radius)
			// here we check if it has gone outside that range
			// create a temp copy to iterate over, since we may want to
			// change the original. ORDER: byte order of the ID text (was the dictionary's hash order).
			const std::map<std::string, std::string, std::less<>> closeContactsTemp = closeContactsInfo;
			for (const auto &[other_key, other_position] : closeContactsTemp)
			{
				::ShipEntity* other = oo::ToShip((UNIVERSE != nullptr ? UNIVERSE->entityForUniversalID(IntValueOfKey(other_key)) : nullptr));
				if ((other != nil) && (other->isShip))
				{
					if (HPdistance2(position, other->position) > collision_radius * collision_radius)	// moved beyond our sphere!
					{
						// calculate position with respect to our own position and orientation
						Vector	dpos = HPVectorToVector(HPvector_between(position, other->position));
						Vector  pos1 = make_vector(dot_product(dpos, v_right), dot_product(dpos, v_up), dot_product(dpos, v_forward));
						Vector	pos0 = {0, 0, 0};
						const auto contact = closeContactsInfo.find(other_key);
						cxx_ScanVectorFromString(contact != closeContactsInfo.end() ? std::optional<std::string>(contact->second) : std::nullopt, &pos0);
						// send AI messages about the contact
						const oo::WeakRef<Entity> temp = _primaryTarget;
						_primaryTarget = oo::WeakRef<Entity>(other);
						if ((pos0.x < 0.0)&&(pos1.x > 0.0))
						{
							doScriptEvent(OOJSID("shipTraversePositiveX"), other, "POSITIVE X TRAVERSE");
						}
						if ((pos0.x > 0.0)&&(pos1.x < 0.0))
						{
							doScriptEvent(OOJSID("shipTraverseNegativeX"), other, "NEGATIVE X TRAVERSE");
						}
						if ((pos0.y < 0.0)&&(pos1.y > 0.0))
						{
							doScriptEvent(OOJSID("shipTraversePositiveY"), other, "POSITIVE Y TRAVERSE");
						}
						if ((pos0.y > 0.0)&&(pos1.y < 0.0))
						{
							doScriptEvent(OOJSID("shipTraverseNegativeY"), other, "NEGATIVE Y TRAVERSE");
						}
						if ((pos0.z < 0.0)&&(pos1.z > 0.0))
						{
							doScriptEvent(OOJSID("shipTraversePositiveZ"), other, "POSITIVE Z TRAVERSE");
						}
						if ((pos0.z > 0.0)&&(pos1.z < 0.0))
						{
							doScriptEvent(OOJSID("shipTraverseNegativeZ"), other, "NEGATIVE Z TRAVERSE");
						}
						_primaryTarget = temp;
						closeContactsInfo.erase(other_key);
					}
				}
				else
				{
					closeContactsInfo.erase(other_key);
				}
			}
		} // end if trackCloseContacts

	} // end if !isSubEntity


#ifndef NDEBUG
	// DEBUGGING
	if (reportAIMessages && (debugLastBehaviour != behaviour))
	{
		OO_LOG("entity.behaviour.changed", "{} behaviour is now {}", oo::EntityDescription(this), cxx_OOStringFromBehaviour(behaviour));
		debugLastBehaviour = behaviour;
	}
#endif
	
	// cool all weapons.
	weapon_temp = fmaxf(weapon_temp - (float)(WEAPON_COOLING_FACTOR * delta_t), 0.0f);
	forward_weapon_temp = fmaxf(forward_weapon_temp - (float)(WEAPON_COOLING_FACTOR * delta_t), 0.0f);
	aft_weapon_temp = fmaxf(aft_weapon_temp - (float)(WEAPON_COOLING_FACTOR * delta_t), 0.0f);
	port_weapon_temp = fmaxf(port_weapon_temp - (float)(WEAPON_COOLING_FACTOR * delta_t), 0.0f);
	starboard_weapon_temp = fmaxf(starboard_weapon_temp - (float)(WEAPON_COOLING_FACTOR * delta_t), 0.0f);
	
	// update time between shots
	shot_time += delta_t;

	// handle radio message effects
	if (messageTime > 0.0)
	{
		messageTime -= delta_t;
		if (messageTime < 0.0)  messageTime = 0.0;
	}
	
	// temperature factors
	if(!isSubEnt)
	{
		double external_temp = 0.0;
		::OOSunEntity *sun = (UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr);
		if (sun != nil)
		{
			// set the ambient temperature here
			double  sun_zd = HPdistance2(position, (sun != nullptr ? sun->getPosition() : HPVector{}));	// square of distance
			double  sun_cr = sun->collision_radius;
			double	alt1 = sun_cr * sun_cr / sun_zd;
			external_temp = SUN_TEMPERATURE * alt1;
			if ((sun != nullptr ? sun->goneNova() : false))  external_temp *= 100;

			if (hasFuelScoop() && alt1 > 0.75 && getFuel() < fuelCapacity())
			{
				fuel_accumulator += (float)(delta_t * flightSpeed * 0.010 / fuelChargeRate());
			// are we fast enough to collect any fuel?
				while (fuel_accumulator > 1.0f)
				{
					setFuel(getFuel() + 1);
					fuel_accumulator -= 1.0f;
					doScriptEvent(OOJSID("shipScoopedFuel"));
				}
			}
		}

		// work on the ship temperature
		//
		float heatThreshold = heatInsulation() * 100.0f;
		if (external_temp > heatThreshold &&  external_temp > ship_temperature)
			ship_temperature += (external_temp - ship_temperature) * delta_t * SHIP_INSULATION_FACTOR / heatInsulation();
		else
		{
			if (ship_temperature > SHIP_MIN_CABIN_TEMP)
			{
				ship_temperature += (external_temp - heatThreshold - ship_temperature) * delta_t * SHIP_COOLING_FACTOR / heatInsulation();
				if (ship_temperature < SHIP_MIN_CABIN_TEMP) ship_temperature = SHIP_MIN_CABIN_TEMP;
			}
		}
	}
	else //subents
	{
		ship_temperature = (oo::ToShip(owner()) != nullptr ? oo::ToShip(owner())->temperature() : 0.0f);
	}

	if (ship_temperature > SHIP_MAX_CABIN_TEMP)
		takeHeatDamage(delta_t * ship_temperature);

	// are we burning due to low energy
	if ((energy < maxEnergy * 0.20)&&_showDamage)	// prevents asteroid etc. from burning
		throw_sparks = YES;
	
	// burning effects
	if (throw_sparks)
	{
		next_spark_time -= delta_t;
		if (next_spark_time < 0.0)
		{
			throwSparks();
			throw_sparks = NO;	// until triggered again
		}
	}
	
	if (!isSubEnt)
	{

		// cloaking device
		if (hasCloakingDevice())
		{
			if (cloaking_device_active)
			{
				energy -= delta_t * CLOAKING_DEVICE_ENERGY_RATE;
				if (energy < CLOAKING_DEVICE_MIN_ENERGY)
				{  
					deactivateCloakingDevice();
					if (energy < 0) energy = 0;
				}
			}
		}

		// military_jammer
		if (hasMilitaryJammer())
		{
			if (military_jammer_active)
			{
				energy -= delta_t * MILITARY_JAMMER_ENERGY_RATE;
				if (energy < MILITARY_JAMMER_MIN_ENERGY)
				{
					military_jammer_active = NO;
					if (energy < 0) energy = 0;
				}
			}
			else
			{
				if (energy > 1.5 * MILITARY_JAMMER_MIN_ENERGY)
					military_jammer_active = YES;
			}
		}

	// check outside factors
		/* aegis checks are expensive, so only do them once every km or so of flight
		 * unlikely to be important otherwise. (every 100m if already close to
		 * planet, to watch for surface)

		 * if have non-zero inertial velocity, need to check every frame,
		 * as distanceTravelled does not include this component - CIM */
		if (_nextAegisCheck < distanceTravelled || !vector_equal(OOEntityWithDrawable::getVelocity(),kZeroVector))
		{
			aegis_status = checkForAegis();   // is a station or something nearby??
			if (aegis_status == AEGIS_NONE)
			{
				// in open space: check every km
				_nextAegisCheck = distanceTravelled + 1000.0;
			}
			else
			{
				// near planets: check every 100m
				_nextAegisCheck = distanceTravelled + 100.0;
			}
		}
	} // end if !isSubEntity

	// scripting
	if (!haveExecutedSpawnAction)
	{
		// When crashing into a boulder, STATUS_LAUNCHING is sometimes skipped on scooping the resulting splinters.
		OOEntityStatus status = this->status();
		if (script != nullptr && (status == STATUS_IN_FLIGHT ||
							  status == STATUS_LAUNCHING ||
							  status == STATUS_BEING_SCOOPED ||
							  (status == STATUS_ACTIVE && this == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr))
							  ))
		{
			if (PLAYER != nullptr)  PLAYER->setScriptTarget(this);
			doScriptEvent(OOJSID("shipSpawned"));
			if (this->status() != STATUS_DEAD)  { if (PLAYER != nullptr)  PLAYER->doScriptEvent(OOJSID("shipSpawned"), this); }
		}
		haveExecutedSpawnAction = YES;
	}
	/* No point in starting the AI if still launching */
	if (!haveStartedJSAI && status() != STATUS_LAUNCHING)
	{
		haveStartedJSAI = YES;
		doScriptEvent(OOJSID("aiStarted"));
	}

	// behaviours according to status and behaviour
	//
	if (status() == STATUS_LAUNCHING)
	{
		if ((UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) > launch_time + launch_delay)		// move for while before thinking
		{
			::StationEntity *stationLaunchedFrom = oo::ToStation((UNIVERSE != nullptr ? UNIVERSE->nearestEntityMatchingPredicate(IsStationPredicate, NULL, this) : nullptr));
			setStatus(STATUS_IN_FLIGHT);
			// awaken JS-based AIs
			haveStartedJSAI = YES;
			doScriptEvent(OOJSID("aiStarted"));
			doScriptEvent(OOJSID("shipLaunchedFromStation"), stationLaunchedFrom);
			if (shipAI != nullptr)  shipAI->reactToMessage("LAUNCHED OKAY", "launched");
		}
		else
		{
			// ignore behaviour just keep moving...
			flightYaw = 0.0;
			applyAttitudeChanges(delta_t);
			applyThrust(delta_t);
			if (energy < maxEnergy)
			{
				energy += energy_recharge_rate * delta_t;
				if (energy > maxEnergy)
				{
					energy = maxEnergy;
					doScriptEvent(OOJSID("shipEnergyBecameFull"));
					if (shipAI != nullptr)  shipAI->message("ENERGY_FULL");
				}
			}
			
			if (subEntityCount() > 0)
			{
				// only copy the subent array if there are subentities
				const std::vector<oo::EntityHold> subs = subEntities;	// a snapshot, as -subEntities copied
				for (const auto &sub : subs)
				{
					::ShipEntity *se = oo::ToShip(sub.get());
					if (se != nullptr)  se->update(delta_t);
				}
			}
			// super update
			OOEntityWithDrawable::update(delta_t);	// [super update:delta_t]

			return;
		}
	}
	//
	// double check scooped behaviour
	//
	if (status() == STATUS_BEING_SCOOPED)
	{
		//if we are being tractored, but we have no owner, then we have a problem
		if (behaviour != BEHAVIOUR_TRACTORED  || owner() == nil || oo::LiveOwner(this) == this)	// NO_TARGET is 0: `[self owner] == (id)NO_TARGET` only repeated the nil test
		{
			// escaped tractor beam
			setStatus(STATUS_IN_FLIGHT);	// should correct 'uncollidable objects' bug
			behaviour = BEHAVIOUR_IDLE;
			frustration = 0.0;
			setOwner(this);
			if (shipAI != nullptr)  shipAI->exitStateMachineWithMessage(std::nullopt);  // Escapepods and others should continue their old AI here.
		}
	}
	
	if (status() == STATUS_COCKPIT_DISPLAY)
	{
		flightYaw = 0.0;
		applyAttitudeChanges(delta_t);
		GLfloat range2 = 0.1 * HPdistance2(position, _destination) / (collision_radius * collision_radius);
		if ((range2 > 1.0)||(velocity.z > 0.0))	range2 = 1.0;
		position = HPvector_add(position, vectorToHPVector(vector_multiply_scalar(velocity, range2 * delta_t)));
	}
	else
	{
		processBehaviour(delta_t);

		// manage energy
		if (energy < maxEnergy)
		{
			energy += energy_recharge_rate * delta_t;
			if (energy > maxEnergy)
			{
				energy = maxEnergy;
				doScriptEvent(OOJSID("shipEnergyBecameFull"));
				if (shipAI != nullptr)  shipAI->message("ENERGY_FULL");
			}
		}
		
		if (!isSubEnt)
		{
		// update destination position for escorts
			refreshEscortPositions();
			if (hasEscorts())
			{
				unsigned	i = 0;
				// Note: works on escortArray rather than escortEnumerator because escorts may be mutated.
				for (const auto &escort : escortArray())
				{
					if (oo::ToShip(escort.get()) != nullptr)  oo::ToShip(escort.get())->setEscortDestination(coordinatesForEscortPosition(i++));
				}
			
				::ShipEntity *leader = (escortGroup() != nullptr ? escortGroup()->leader() : (::ShipEntity *)nil);
				if (leader != nil && ((leader != nullptr ? leader->getScanClass() : OOScanClass{}) != getScanClass())) {
					OO_LOG("ship.sanityCheck.failed", "Ship {} escorting {} with wrong scanclass!", oo::EntityDescription(this), oo::EntityDescription(leader));
					if (escortGroup() != nullptr)  escortGroup()->removeShip(this);
					setEscortGroup(nullptr);
				}
			}
		}
	}
	
	// rotational velocity
	if (!quaternion_equal(subentityRotationalVelocity, kIdentityQuaternion) &&
		!quaternion_equal(subentityRotationalVelocity, kZeroQuaternion))
	{
		Quaternion qf = subentityRotationalVelocity;
		qf.w *= (1.0 - delta_t);
		qf.x *= delta_t;
		qf.y *= delta_t;
		qf.z *= delta_t;
		setOrientation(quaternion_multiply(qf, orientation));
	}
	
	//	reset totalBoundingBox
	totalBoundingBox = boundingBox;
	
	// super update
	OOEntityWithDrawable::update(delta_t);	// [super update:delta_t]

	// update subentities

	if (subEntityCount() > 0)
	{
		// only copy the subent array if there are subentities
		const std::vector<oo::EntityHold> subs = subEntities;	// a snapshot, as -subEntities copied
		for (const auto &sub : subs)
		{
			::ShipEntity *se = oo::ToShip(sub.get());
			if (se != nullptr)  se->update(delta_t);
			if ((se != nullptr ? se->getIsShip() : false))
			{
				BoundingBox sebb = (se != nullptr ? se->findSubentityBoundingBox() : BoundingBox{});
				bounding_box_add_vector(&totalBoundingBox, sebb.max);
				bounding_box_add_vector(&totalBoundingBox, sebb.min);
			}
		}
	}
	
	if (aiScriptWakeTime > 0 && (PLAYER != nullptr ? PLAYER->clockTimeAdjusted() : 0.0) > aiScriptWakeTime)
	{
		aiScriptWakeTime = 0;
		doScriptEvent(OOJSID("aiAwoken"));
	}
}




// Slice 8 of docs/phases/3-slices/ShipEntity.md (bead oo-vxdsc): behaviour dispatch, attack
// response, equipment queries. Members of the C++ ship, called directly, since bead oo-9ht.144
// deleted the facade (ADR-0056 amendment oo-9ht.144).

void ShipEntity::processBehaviour(OOTimeDelta delta_t)
{
	BOOL applyThrust = YES;
	switch (behaviour)
	{
	case BEHAVIOUR_TUMBLE :
		behaviour_tumble(delta_t);
		break;

	case BEHAVIOUR_STOP_STILL :
	case BEHAVIOUR_STATION_KEEPING :
		behaviour_stop_still(delta_t);
		break;

	case BEHAVIOUR_IDLE :
		if (getIsSubEntity())
		{
			applyThrust = NO;
		}
		behaviour_idle(delta_t);
		break;

	case BEHAVIOUR_TRACTORED :
		behaviour_tractored(delta_t);
		break;

	case BEHAVIOUR_TRACK_TARGET :
		behaviour_track_target(delta_t);
		break;

	case BEHAVIOUR_INTERCEPT_TARGET :
	case BEHAVIOUR_COLLECT_TARGET :
		behaviour_intercept_target(delta_t);
		break;

	case BEHAVIOUR_ATTACK_TARGET :
		behaviour_attack_target(delta_t);
		break;

	case BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX :
	case BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE :
		behaviour_fly_to_target_six(delta_t);
		break;

	case BEHAVIOUR_ATTACK_MINING_TARGET :
		behaviour_attack_mining_target(delta_t);
		break;

	case BEHAVIOUR_ATTACK_FLY_TO_TARGET :
		behaviour_attack_fly_to_target(delta_t);
		break;

	case BEHAVIOUR_ATTACK_FLY_FROM_TARGET :
		behaviour_attack_fly_from_target(delta_t);
		break;

	case BEHAVIOUR_ATTACK_BREAK_OFF_TARGET :
		behaviour_attack_break_off_target(delta_t);
		break;

	case BEHAVIOUR_ATTACK_SLOW_DOGFIGHT :
		behaviour_attack_slow_dogfight(delta_t);
		break;

	case BEHAVIOUR_RUNNING_DEFENSE :
		behaviour_running_defense(delta_t);
		break;

	case BEHAVIOUR_ATTACK_BROADSIDE :
		behaviour_attack_broadside(delta_t);
		break;

	case BEHAVIOUR_ATTACK_BROADSIDE_LEFT :
		behaviour_attack_broadside_left(delta_t);
		break;

	case BEHAVIOUR_ATTACK_BROADSIDE_RIGHT :
		behaviour_attack_broadside_right(delta_t);
		break;

	case BEHAVIOUR_CLOSE_TO_BROADSIDE_RANGE :
		behaviour_close_to_broadside_range(delta_t);
		break;

	case BEHAVIOUR_CLOSE_WITH_TARGET :
		behaviour_close_with_target(delta_t);
		break;

	case BEHAVIOUR_ATTACK_SNIPER :
		behaviour_attack_sniper(delta_t);
		break;

	case BEHAVIOUR_EVASIVE_ACTION :
	case BEHAVIOUR_FLEE_EVASIVE_ACTION :
		behaviour_evasive_action(delta_t);
		break;

	case BEHAVIOUR_FLEE_TARGET :
		behaviour_flee_target(delta_t);
		break;

	case BEHAVIOUR_FLY_RANGE_FROM_DESTINATION :
		behaviour_fly_range_from_destination(delta_t);
		break;

	case BEHAVIOUR_FACE_DESTINATION :
		behaviour_face_destination(delta_t);
		break;

	case BEHAVIOUR_LAND_ON_PLANET :
		behaviour_land_on_planet(delta_t);
		break;
				
	case BEHAVIOUR_FORMATION_FORM_UP :
		behaviour_formation_form_up(delta_t);
		break;

	case BEHAVIOUR_FLY_TO_DESTINATION :
		behaviour_fly_to_destination(delta_t);
		break;

	case BEHAVIOUR_FLY_FROM_DESTINATION :
	case BEHAVIOUR_FORMATION_BREAK :
		behaviour_fly_from_destination(delta_t);
		break;

	case BEHAVIOUR_AVOID_COLLISION :
		behaviour_avoid_collision(delta_t);
		break;

	case BEHAVIOUR_TRACK_AS_TURRET :
		applyThrust = NO;
		behaviour_track_as_turret(delta_t);
		break;

	case BEHAVIOUR_FLY_THRU_NAVPOINTS :
		behaviour_fly_thru_navpoints(delta_t);
		break;

	case BEHAVIOUR_SCRIPTED_AI:
	case BEHAVIOUR_SCRIPTED_ATTACK_AI:
		behaviour_scripted_ai(delta_t);
		break;

	case BEHAVIOUR_ENERGY_BOMB_COUNTDOWN:
		applyThrust = NO;
		// Do nothing
		break;
	}

	// generally the checks above should be turning this *off* for subents
	if (applyThrust)
	{
		applyAttitudeChanges(delta_t);
		this->applyThrust(delta_t);
	}
}


// called when behaviour is unable to improve position
void ShipEntity::noteFrustration(const std::string &context)
{
	if (shipAI != nullptr)  shipAI->reactToMessage("FRUSTRATED", context);
	doScriptEvent(OOJSID("shipAIFrustrated"), { oo::PList(context) });
}


void ShipEntity::respondToAttackFrom(Entity *from, Entity *other)
{
	Entity				*source = nullptr;
	
	if ((oo::ToShip(other) != nullptr))
	{
		source = other;

		// JSAIs handle friendly fire themselves
		if (!hasNewAI())
		{
		
			::ShipEntity *hunter = oo::ToShip(other);
			//if we are in the same group, then we have to be careful about how we handle things
			if (isPolice() && (hunter != nullptr ? hunter->isPolice() : false)) 
			{
				//police never get into a fight with each other
				return;
			}
		
			::OOShipGroup *group = this->group();
		
			if (group != nil && group == (hunter != nullptr ? hunter->group() : (OOShipGroup *)nullptr)) 
			{
				//we are in the same group, do we forgive you?
				//criminals are less likely to forgive
				if (randf() < (0.8 - static_cast<OOCreditsQuantity>(bounty/100)))	// whole hundreds, as before
				{
					//it was an honest mistake, lets get on with it
					return;
				}
			
				::ShipEntity *groupLeader = (group != nullptr ? group->leader() : (::ShipEntity *)nil);
				if (hunter == groupLeader)
				{
					//oops we were attacked by our leader, desert him
					if (group != nullptr)  group->removeShip(this);
				}
				else 
				{
					//evict them from our group
					if (group != nullptr)  group->removeShip(hunter);
				
					if (groupLeader != nullptr)  groupLeader->setFoundTarget(other);
					if (groupLeader != nullptr)  groupLeader->setPrimaryAggressor(hunter);
					if (groupLeader != nullptr)  groupLeader->respondToAttackFrom(from, other);
				}
			}
		}
	}
	else
	{
		source = from;
	}	
	
	doScriptEvent(OOJSID("shipBeingAttacked"), source, "ATTACKED");
	if (oo::EntityIsShip(source)) { if (oo::ToShip(source) != nullptr)  oo::ToShip(source)->doScriptEvent(OOJSID("shipAttackedOther"), this); }
}


// Equipment

bool ShipEntity::hasOneEquipmentItem(const std::string &itemKey, bool includeWeapons, bool loading)
{
	if (hasOneEquipmentItemIncludingMissiles(itemKey, includeWeapons, loading))  return YES;

	if (loading)
	{
		const std::string damaged = itemKey + "_DAMAGED";
		if (std::ranges::find(_equipment, damaged) != _equipment.end())  return YES;
	}

	if (includeWeapons)
	{
		// Check for primary weapon
		OOWeaponType weaponType = cxx_OOWeaponTypeFromEquipmentIdentifierStrict(itemKey);
		if (!isWeaponNone(weaponType))
		{
			if (hasPrimaryWeapon(weaponType))  return YES;
		}
	}
	
	return NO;
}


bool ShipEntity::hasOneEquipmentItemIncludingMissiles(const std::string &itemKey, bool includeMissiles, bool loading)
{
	if (std::ranges::find(_equipment, itemKey) != _equipment.end())  return YES;

	if (loading)
	{
		const std::string damaged = itemKey + "_DAMAGED";
		if (std::ranges::find(_equipment, damaged) != _equipment.end())  return YES;
	}

	if (includeMissiles && missiles > 0)
	{
		unsigned i;
		const std::string key = (itemKey == "thargon") ? std::string("EQ_THARGON") : itemKey;
		for (i = 0; i < missiles; i++)
		{
			if (missile_list[i] != nil && (missile_list[i] != nullptr ? missile_list[i]->identifier() : std::optional<std::string>()).value_or("") == key)  return YES;
		}
	}
	
	return NO;
}


bool ShipEntity::hasPrimaryWeapon(OOWeaponType weaponType)
{
	// -isEqualToString: of the identifiers: a nil weapon (nullopt) matches nothing.
	const std::optional<std::string> weaponIdentifier = (weaponType != nullptr ? weaponType->identifier() : std::optional<std::string>());
	if (weaponIdentifier.has_value() &&
		((forward_weapon_type != nullptr ? forward_weapon_type->identifier() : std::optional<std::string>()) == weaponIdentifier ||
		 (aft_weapon_type != nullptr ? aft_weapon_type->identifier() : std::optional<std::string>()) == weaponIdentifier ||
		 (port_weapon_type != nullptr ? port_weapon_type->identifier() : std::optional<std::string>()) == weaponIdentifier ||
		 (starboard_weapon_type != nullptr ? starboard_weapon_type->identifier() : std::optional<std::string>()) == weaponIdentifier))
	{
		return YES;
	}

	for (const auto &subEntity : shipSubEntities())
	{
		if ((oo::ToShip(subEntity.get()) != nullptr ? oo::ToShip(subEntity.get())->hasPrimaryWeapon(weaponType) : false))  return YES;
	}
	
	return NO;
}


NSUInteger ShipEntity::countEquipmentItem(const std::string &eqkey)
{
	return (NSUInteger)std::ranges::count(_equipment, eqkey);
}


bool ShipEntity::hasEquipmentItem(const oo::PList &equipmentKeys, bool includeWeapons, bool loading)
{
	// this method is also used internally to find out if an equipped item is undamaged.
	if (const std::string *key = equipmentKeys.getIf<std::string>())
	{
		return hasOneEquipmentItem(*key, includeWeapons, loading);
	}
	else
	{
		OOCParameterAssert(equipmentKeys.isArray());

		// Any match: order-insensitive. Only string keys can match an equipment key.
		if (const oo::PList::Array *keys = equipmentKeys.getIf<oo::PList::Array>())
		{
			for (const oo::PList &element : *keys)
			{
				const std::string *elementKey = element.getIf<std::string>();
				if (elementKey != nullptr && hasOneEquipmentItem(*elementKey, includeWeapons, loading))  return YES;
			}
		}
	}

	return NO;
}


bool ShipEntity::hasEquipmentItem(const oo::PList &equipmentKeys)
{
	return hasEquipmentItem(equipmentKeys, NO, NO);
}


/* allows OXP equipment to provide core functions (or indeed OXP
 * functions, potentially) */
bool ShipEntity::hasEquipmentItemProviding(const std::string &equipmentType)
{
	for (const std::string &key : _equipment) {
		if (key == equipmentType)
		{
			// equipment always provides itself
			return YES;
		}
		else
		{
			::OOEquipmentType *et = OOEquipmentType::equipmentTypeWithIdentifier(key).get();
			if (et != nil && (et != nullptr ? et->provides(equipmentType) : false))
			{
				return YES;
			}
		}
	}
	return NO;
}


std::optional<std::string> ShipEntity::equipmentItemProviding(const std::string &equipmentType)
{
	for (const std::string &key : _equipment) {
		if (key == equipmentType)
		{
			// equipment always provides itself
			return key;
		}
		else
		{
			::OOEquipmentType *et = OOEquipmentType::equipmentTypeWithIdentifier(key).get();
			if (et != nil && (et != nullptr ? et->provides(equipmentType) : false))
			{
				return key;
			}
		}
	}
	return std::nullopt;
}


bool ShipEntity::hasAllEquipment(const oo::PList &equipmentKeys, bool includeWeapons, bool loading)
{
	if (_equipment.empty())  return NO;

	// Make sure it's an array, using a single-element list if it's a string.
	std::vector<std::string> keys;
	if (const std::string *key = equipmentKeys.getIf<std::string>())  keys.push_back(*key);
	else if (const oo::PList::Array *elements = equipmentKeys.getIf<oo::PList::Array>())
	{
		for (const oo::PList &element : *elements)
		{
			const std::string *elementKey = element.getIf<std::string>();
			// A key that is not a string is never held: the whole test fails, as it did.
			if (elementKey == nullptr)  return NO;
			keys.push_back(*elementKey);
		}
	}
	else  return NO;

	// All must match: order-insensitive.
	for (const std::string &key : keys)
	{
		if (!hasOneEquipmentItem(key, includeWeapons, loading))  return NO;
	}

	return YES;
}


bool ShipEntity::hasAllEquipment(const oo::PList &equipmentKeys)
{
	return hasAllEquipment(equipmentKeys, NO, NO);
}


bool ShipEntity::hasHyperspaceMotor()
{
	return hyperspaceMotorSpinTime >= 0;
}


float ShipEntity::hyperspaceSpinTime()
{
	return hyperspaceMotorSpinTime;
}


void ShipEntity::setHyperspaceSpinTime(float newValue)
{
	hyperspaceMotorSpinTime = newValue;
}




// Slice 9 of docs/phases/3-slices/ShipEntity.md (bead oo-ke13m): equipment validity and adding,
// weapon mounts, scripting lists. Members of the C++ ship, called directly, since bead oo-9ht.144
// deleted the facade (ADR-0056 amendment oo-9ht.144).

bool ShipEntity::canAddEquipment(const std::string &equipmentKeyIn, const std::string &context)
{
	std::string equipmentKey = equipmentKeyIn;
	if (oo::str::hasSuffix(equipmentKey, "_DAMAGED"))
	{
		equipmentKey.resize(equipmentKey.size() - std::string_view("_DAMAGED").size());
	}

	const std::string lcEquipmentKey = oo::str::lowercase(equipmentKey);
	if (oo::str::hasSuffix(equipmentKey, "MISSILE")||oo::str::hasSuffix(equipmentKey, "MINE")||(isThargoid() && (oo::str::hasPrefix(lcEquipmentKey, "thargon") || oo::str::hasSuffix(lcEquipmentKey, "thargon"))))
	{
		if (missiles >= max_missiles) return NO;
	}

	::OOEquipmentType *eqType = OOEquipmentType::equipmentTypeWithIdentifier(equipmentKey).get();

	// -hasEquipmentItem: with one string key.
	if (!(eqType != nullptr ? eqType->canCarryMultiple() : false) && hasOneEquipmentItem(equipmentKey, NO, NO))  return NO;
	if (!equipmentValidToAdd(equipmentKey, context))  return NO;

	return YES;
}


OOWeaponFacingSet ShipEntity::weaponFacings()
{
	return weapon_facings;
}


OOWeaponType ShipEntity::weaponTypeIDForFacing(OOWeaponFacing facing, bool strict)
{
	OOWeaponType weaponType = nil;

	if (facing & weapon_facings)
	{
		switch (facing)
		{
			case WEAPON_FACING_FORWARD:
				weaponType = forward_weapon_type;
				// if no forward weapon, and not carrying out a strict check, see if subentities have forward weapons, return the first one found.
				if (isWeaponNone(weaponType) && !strict)
				{
					for (const auto &subEntity : shipSubEntities())
					{
						if (!isWeaponNone(weaponType))  break;
						if (ShipEntity *subShip = oo::ToShip(subEntity.get()))  weaponType = subShip->forward_weapon_type;
					}
				}
				break;
				
			case WEAPON_FACING_AFT:
				weaponType = aft_weapon_type;
				break;
				
			case WEAPON_FACING_PORT:
				weaponType = port_weapon_type;
				break;
				
			case WEAPON_FACING_STARBOARD:
				weaponType = starboard_weapon_type;
				break;
				
			case WEAPON_FACING_NONE:
				break;
		}
	}
	return weaponType;
}


::OOEquipmentType *ShipEntity::weaponTypeForFacing(OOWeaponFacing facing, bool strict)
{
//	OOWeaponType weaponType = [self weaponTypeIDForFacing:facing strict:strict];
//	return [OOEquipmentType equipmentTypeWithIdentifier:OOEquipmentIdentifierFromWeaponType(weaponType)];
	return weaponTypeIDForFacing(facing, strict);
}


std::vector<oo::Ref<::OOEquipmentType>> ShipEntity::missilesList()
{
	// if missile_list is empty, avoid exception and return an empty array instead
	std::vector<oo::Ref<::OOEquipmentType>> list;
	if (missile_list[0] != nil)
	{
		list.reserve(missiles);
		for (unsigned i = 0; i < missiles; i++)  list.emplace_back(missile_list[i]);
	}
	return list;
}


oo::PList ShipEntity::passengerListForScripting()
{
	return oo::PList(oo::PList::Array{});	// an empty array
}


oo::PList ShipEntity::parcelListForScripting()
{
	return oo::PList(oo::PList::Array{});	// an empty array
}


oo::PList ShipEntity::contractListForScripting()
{
	return oo::PList(oo::PList::Array{});	// an empty array
}


::OOEquipmentType *ShipEntity::generateMissileEquipmentTypeFrom(const std::string &role)
{
	/* 	The generated missile equipment type provides for backward compatibility with pre-1.74 OXPs  missile_roles
		and follows this template:
		
		//NPC equipment, incompatible with player ship. Not buyable because of its TL.
		(
			100, 100000, "Missile",
			"EQ_X_MISSILE",
			"Unidentified missile type.",
			{
				is_external_store = true;
			}
		)
	*/
	const oo::PList itemInfo(oo::PList::Array{ "100", "100000", "Missile", role, "Unidentified missile type.",
							oo::PList(oo::PList::Dict{ { "is_external_store", oo::PList("true") } }) });

	OOEquipmentType::addEquipmentWithInfo(itemInfo);
	return OOEquipmentType::equipmentTypeWithIdentifier(role).get();
}


std::vector<oo::Ref<::OOEquipmentType>> ShipEntity::equipmentListForScripting()
{
	std::vector<oo::Ref<::OOEquipmentType>>	quip;
	::OOEquipmentType		*eqType = nil;
	BOOL				isDamaged;

	for (const auto &eqTypeRef : OOEquipmentType::allEquipmentTypes())
	{
		eqType = eqTypeRef.get();
		const std::string identifier = (eqType != nullptr ? eqType->identifier() : std::optional<std::string>()).value_or("");
		// Equipment list,  consistent with the rest of the API - Kaks
		if ((eqType != nullptr ? eqType->canCarryMultiple() : false))
		{
			const std::string damagedIdentifier = identifier + "_DAMAGED";
			NSUInteger i, count = 0;
			count += countEquipmentItem(identifier);
			count += countEquipmentItem(damagedIdentifier);
			for (i=0;i<count;i++)
			{
				quip.emplace_back(eqType);
			}
		}
		else
		{
			// -hasEquipmentItem: with one string key.
			isDamaged = hasOneEquipmentItem(identifier + "_DAMAGED", NO, NO);
			if (hasOneEquipmentItem(identifier, NO, NO) || isDamaged)
			{
				quip.emplace_back(eqType);
			}
		}
	}

	// Passengers - not supported yet for NPCs, but it's here for genericity.
	if (passengerCapacity() > 0)
	{
		eqType = OOEquipmentType::equipmentTypeWithIdentifier("EQ_PASSENGER_BERTH").get();
		//[quip addObject:[self eqDictionaryWithType:eqType isDamaged:NO]];
		quip.emplace_back(eqType);
	}

	return quip;
}


bool ShipEntity::equipmentValidToAdd(const std::string &equipmentKey, const std::string &context)
{
	return equipmentValidToAdd(equipmentKey, NO, context);
}


bool ShipEntity::equipmentValidToAdd(const std::string &fullEquipmentKey, bool loading, const std::string &context)
{
	::OOEquipmentType			*eqType = nil;
	BOOL					validationForDamagedEquipment = NO;

	std::string equipmentKey = fullEquipmentKey;
	if (oo::str::hasSuffix(equipmentKey, "_DAMAGED"))
	{
		equipmentKey.resize(equipmentKey.size() - std::string_view("_DAMAGED").size());
	}

	eqType = OOEquipmentType::equipmentTypeWithIdentifier(equipmentKey).get();
	if (eqType == nil)  return NO;
	
	// need to know if we are trying to add a Repair version of the equipment. In some cases
	// (e.g. available cargo space required), it makes sense to deny installation of equipment
	// if the condition is not satisfied, but it doesn't make sense to deny repair when the
	// equipment is already installed. For now, we are checking only the cargo space condition,
	// but other conditions might need to be revised too. - Nikos, 20151115
	if (hasEquipmentItem(OptionalKeyPList((eqType != nullptr ? eqType->damagedIdentifier() : std::optional<std::string>()))))
	{
		validationForDamagedEquipment = YES;
	}
	
	// not all conditions make sence checking while loading a game with already purchaged equipment.
	// while loading, we mainly need to catch changes when the installed oxps set has changed since saving. 
	if ((eqType != nullptr ? eqType->requiresEmptyPylon() : false) && missileCount() >= missileCapacity() && !loading)  return NO;
	if ((eqType != nullptr ? eqType->requiresMountedPylon() : false) && missileCount() == 0 && !loading)  return NO;
	if (availableCargoSpace() < (eqType != nullptr ? eqType->requiredCargoSpace() : 0) && !validationForDamagedEquipment && !loading)  return NO;
	const std::optional<std::vector<std::string>> requiresEquipment = (eqType != nullptr ? eqType->requiresEquipment() : std::optional<std::vector<std::string>>());
	const std::optional<std::vector<std::string>> requiresAnyEquipment = (eqType != nullptr ? eqType->requiresAnyEquipment() : std::optional<std::vector<std::string>>());
	const std::optional<std::vector<std::string>> incompatibleEquipment = (eqType != nullptr ? eqType->incompatibleEquipment() : std::optional<std::vector<std::string>>());
	if (requiresEquipment.has_value() && !hasAllEquipment(KeysPList(*requiresEquipment), YES, loading))  return NO;
	if (requiresAnyEquipment.has_value() && !hasEquipmentItem(KeysPList(*requiresAnyEquipment), YES, loading))  return NO;
	if (incompatibleEquipment.has_value() && hasEquipmentItem(KeysPList(*incompatibleEquipment), YES, loading))  return NO;
	if ((eqType != nullptr ? eqType->requiresCleanLegalRecord() : false) && legalStatus() != 0 && !loading)  return NO;
	if ((eqType != nullptr ? eqType->requiresNonCleanLegalRecord() : false) && legalStatus() == 0 && !loading)  return NO;
	if ((eqType != nullptr ? eqType->requiresFreePassengerBerth() : false) && passengerCount() >= passengerCapacity())  return NO;
	if ((eqType != nullptr ? eqType->requiresFullFuel() : false) && getFuel() < fuelCapacity() && !loading)  return NO;
	if ((eqType != nullptr ? eqType->requiresNonFullFuel() : false) && getFuel() >= fuelCapacity() && !loading)  return NO;

	if (!loading)
	{
		const std::optional<std::string> condition_script = (eqType != nullptr ? eqType->conditionScript() : std::optional<std::string>());
		if (condition_script.has_value())
		{
			::OOScript *condScript = (UNIVERSE != nullptr ? UNIVERSE->getConditionScript(*condition_script) : nullptr);
			if (condScript != nil) // should always be non-nil, but just in case
			{
				ooscript::Context JScontext = OOJSAcquireContext();
				BOOL OK;
				bool allow_addition = false;
				ooscript::Value result;
				ooscript::Value args[] = { OOJSValueFromPList(JScontext, oo::PList(equipmentKey)) , OOJSValueFromCxxObject(JScontext, this) , OOJSValueFromPList(JScontext, oo::PList(context))};
				
				OK = (condScript != nullptr ? condScript->callMethod(OOJSID("allowAwardEquipment"), JScontext, args, sizeof args / sizeof *args, &result) : false);

				if (OK) OK = ooscript::valueToBoolean(JScontext, result, &allow_addition);
				
				OOJSRelinquishContext(JScontext);

				if (OK && !allow_addition)
				{
					/* if the script exists, the function exists, the function
					 * returns a bool, and that bool is false, block
					 * addition. Otherwise allow it as default */
					return NO;
				}
			}
		}
	}

	if (getIsPlayer())
	{
		if (!(eqType != nullptr ? eqType->isAvailableToPlayer() : false))  return NO;
		if (!(eqType != nullptr ? eqType->isAvailableToAll() : false))  
		{
			// find options that agree with this ship. Only player ships have these options.
			// (Membership only: the string elements of the two arrays.)
			::OOShipRegistry		*registry = OOShipRegistry::sharedRegistry();
			const oo::PList		shipyardInfo = registry->shipyardInfoForKey(shipDataKey().value_or(""));
			std::set<std::string>	options;
			const oo::PList		*standardEquipment = shipyardInfo.find(std::string(KEY_STANDARD_EQUIPMENT));
			for (const oo::PList *list : { ArrayForKey(shipyardInfo, std::string(KEY_OPTIONAL_EQUIPMENT)),
										   standardEquipment != nullptr ? ArrayForKey(*standardEquipment, std::string(KEY_EQUIPMENT_EXTRAS)) : nullptr })
			{
				for (std::size_t i = 0; list != nullptr && i < list->count(); i++)
				{
					if (const std::string *option = list->at(i)->getIf<std::string>())  options.insert(*option);
				}
			}
			if (!options.contains(equipmentKey))  return NO;
		}
	}
	else
	{
		if (!(eqType != nullptr ? eqType->isAvailableToNPCs() : false))  return NO;
	}
	
	return YES;
}


bool ShipEntity::setWeaponMount(OOWeaponFacing facing, const std::string &eqKey)
{
	// sets WEAPON_NONE if not recognised
	if (weapon_facings & facing) 
	{
		OOWeaponType chosen_weapon = cxx_OOWeaponTypeFromEquipmentIdentifierStrict(eqKey);
		switch (facing)
		{
			case WEAPON_FACING_FORWARD:
				forward_weapon_type = chosen_weapon;
				break;
				
			case WEAPON_FACING_AFT:
				aft_weapon_type = chosen_weapon;
				break;
				
			case WEAPON_FACING_PORT:
				port_weapon_type = chosen_weapon;
				break;
				
			case WEAPON_FACING_STARBOARD:
				starboard_weapon_type = chosen_weapon;
				break;
				
			case WEAPON_FACING_NONE:
				break;
		}

		return YES;
	}
	else
	{
		return NO;
	}
}


bool ShipEntity::addEquipmentItem(const std::string &equipmentKey, const std::string &context)
{
	return addEquipmentItem(equipmentKey, YES, context);
}


bool ShipEntity::addEquipmentItem(const std::string &equipmentKeyIn, bool validateAddition, const std::string &context)
{
	::OOEquipmentType			*eqType = nil;
	std::string				equipmentKey = equipmentKeyIn;
	const std::string		lcEquipmentKey = oo::str::lowercase(equipmentKey);
	BOOL					isEqThargon = oo::str::hasSuffix(lcEquipmentKey, "thargon") || oo::str::hasPrefix(lcEquipmentKey, "thargon");
	BOOL					isRepairedEquipment = NO;

	if(lcEquipmentKey == "thargon")
	{
		equipmentKey = "EQ_THARGON";
	}

	// canAddEquipment always checks if the undamaged version is equipped.
	if (validateAddition == YES && !canAddEquipment(equipmentKey, context))  return NO;

	if (oo::str::hasSuffix(equipmentKey, "_DAMAGED"))
	{
		eqType = OOEquipmentType::equipmentTypeWithIdentifier(equipmentKey.substr(0, equipmentKey.size() - std::string_view("_DAMAGED").size())).get();
	}
	else
	{
		eqType = OOEquipmentType::equipmentTypeWithIdentifier(equipmentKey).get();
		// in case we have the damaged version!
		if (!(eqType != nullptr ? eqType->canCarryMultiple() : false))
		{
			const std::string damagedKey = equipmentKey + "_DAMAGED";
			if (std::ranges::find(_equipment, damagedKey) != _equipment.end())
			{
				std::erase(_equipment, damagedKey);	// -removeObject: removed every occurrence
				isRepairedEquipment = YES;
			}
		}
	}
	
	// does this equipment actually exist?
	if (eqType == nil)  return NO;
	
	// special cases
	if ((eqType != nullptr ? eqType->isMissileOrMine() : false) || (isThargoid() && isEqThargon))
	{
		if (missiles >= max_missiles) return NO;
		
		missile_list[missiles] = eqType;
		missiles++;
		return YES;
	}
	
	// don't add any thargons to non-thargoid ships.
	if(isEqThargon) return NO;
	
	// we can theoretically add a damaged weapon, but not a working one.
	if(oo::str::hasPrefix(equipmentKey, "EQ_WEAPON") && !oo::str::hasSuffix(equipmentKey, "_DAMAGED"))
	{
		return NO;
	}
	// end special cases

	if (equipmentKey != "EQ_PASSENGER_BERTH" && !isRepairedEquipment)
	{
		// Add to equipment_weight with all other equipment.
		equipment_weight += (eqType != nullptr ? eqType->requiredCargoSpace() : 0);
		if (equipment_weight > max_cargo)
		{
			// should not even happen with old save games. Reject equipment now.
			equipment_weight -= (eqType != nullptr ? eqType->requiredCargoSpace() : 0);
			return NO;
		}
	}
	
	
	if (!isPlayer)
	{
		if (equipmentKey == "EQ_CARGO_BAY")
		{
			max_cargo += extra_cargo;
		}
		else if(equipmentKey == "EQ_SHIELD_BOOSTER")
		{
			maxEnergy += 256.0f;
		}
		if(equipmentKey == "EQ_SHIELD_ENHANCER")
		{
			maxEnergy += 256.0f;
			energy_recharge_rate *= 1.5;
		}
	}
	// add the equipment
	_equipment.push_back(equipmentKey);
	doScriptEvent(OOJSID("equipmentAdded"), { oo::PList(equipmentKey) });
	return YES;
}


std::vector<std::string> ShipEntity::equipmentKeys()
{
	return _equipment;
}


NSUInteger ShipEntity::equipmentCount()
{
	return _equipment.size();
}




// Slice 10 of docs/phases/3-slices/ShipEntity.md (bead oo-wvcs2): equipment removal, missile
// selection, capacities and has-equipment predicates, shields. Members of the C++ ship, called
// directly, since bead oo-9ht.144 deleted the facade (ADR-0056 amendment oo-9ht.144).

void ShipEntity::removeEquipmentItem(const std::string &equipmentKey)
{
	// "" (a former nil) matches no equipment key.
	std::string			equipmentTypeCheckKey = equipmentKey;
	const std::string	lcEquipmentKey = oo::str::lowercase(equipmentKey);
	// determine the equipment type and make sure it works also in the case of damaged equipment
	if (oo::str::hasSuffix(equipmentKey, "_DAMAGED"))
	{
		equipmentTypeCheckKey.resize(equipmentKey.size() - std::string_view("_DAMAGED").size());
	}
	::OOEquipmentType *eqType = OOEquipmentType::equipmentTypeWithIdentifier(equipmentTypeCheckKey).get();
	if (eqType == nil)  return;

	if ((eqType != nullptr ? eqType->isMissileOrMine() : false) || (isThargoid() && (oo::str::hasSuffix(lcEquipmentKey, "thargon") || oo::str::hasPrefix(lcEquipmentKey, "thargon"))))
	{
		removeExternalStore(eqType);
	}
	else
	{
		if (std::ranges::find(_equipment, equipmentKey) != _equipment.end())
		{
			if (equipmentKey != "EQ_PASSENGER_BERTH")
			{
				equipment_weight -= (eqType != nullptr ? eqType->requiredCargoSpace() : 0); // all other cases;
			}
						
			if (equipmentKey == "EQ_CLOAKING_DEVICE")
			{
				if (isCloaked())  setCloaked(NO);
			}

			if (!isPlayer)
			{
				if(equipmentKey == "EQ_SHIELD_BOOSTER")
				{
					maxEnergy -= 256.0f;
					if (maxEnergy < energy) energy = maxEnergy;
				}
				else if(equipmentKey == "EQ_SHIELD_ENHANCER")
				{
					maxEnergy -= 256.0f;
					energy_recharge_rate /= 1.5;
					if (maxEnergy < energy) energy = maxEnergy;
				}
				else if (equipmentKey == "EQ_CARGO_BAY")
				{
					max_cargo -= extra_cargo;
				}
			}
		}

		if (!oo::str::hasSuffix(equipmentKey, "_DAMAGED") && !(eqType != nullptr ? eqType->canCarryMultiple() : false))
		{
			const std::string damagedKey = equipmentKey + "_DAMAGED";
			const auto damaged = std::ranges::find(_equipment, damagedKey);
			if (damaged != _equipment.end())
			{
				// remove damaged counterpart (the first occurrence, as -indexOfObject: found it)
				_equipment.erase(damaged);
				equipment_weight -= (eqType != nullptr ? eqType->requiredCargoSpace() : 0);
			}
		}
		const auto equipped = std::ranges::find(_equipment, equipmentKey);
		if (equipped != _equipment.end())
		{
			_equipment.erase(equipped);
		}
		// this event must come after the item is actually removed
		doScriptEvent(OOJSID("equipmentRemoved"), { oo::PList(equipmentKey) });
		
		// if all docking computers are damaged while active
		if (getIsPlayer() && status() == STATUS_AUTOPILOT_ENGAGED && !hasDockingComputer())
		{
			static_cast<PlayerEntity *>(this)->disengageAutopilot();
		}


		if (_equipment.empty())  removeAllEquipment();
	}
}


bool ShipEntity::removeExternalStore(::OOEquipmentType *eqType)
{
	// nil (a nil type) matches nothing, as -isEqualTo:nil did.
	const std::optional<std::string>	identifier = (eqType != nullptr ? eqType->identifier() : std::optional<std::string>());
	unsigned	i;

	for (i = 0; i < missiles; i++)
	{
		if (identifier.has_value() && (missile_list[i] != nullptr ? missile_list[i]->identifier() : std::optional<std::string>()) == identifier)
		{
			// now 'delete' [i] by compacting the array
			while ( ++i < missiles ) missile_list[i - 1] = missile_list[i];
			
			missiles--;
			return YES;
		}
	}
	return NO;
}


::OOEquipmentType *ShipEntity::verifiedMissileTypeFromRole(const std::string &requestedRole)
{
	std::string			role = requestedRole;
	std::optional<std::string> eqRole;
	std::optional<std::string> shipKey;
	::ShipEntity			*missile = nil;
	::OOEquipmentType		*missileType = nil;
	BOOL				isRandomMissile = role == "missile";

	if (isRandomMissile)
	{
		while (!shipKey.has_value())
		{
			shipKey = (UNIVERSE != nullptr ? UNIVERSE->randomShipKeyForRoleRespectingConditions(role) : std::optional<std::string>());
			if (!shipKey.has_value())
			{
				OO_LOG_WARN("ship.setUp.missiles", "{} \"{}\" used in ship \"{}\" needs a valid {}.plist entry.{}", "random missile", shipKey.value_or("(null)"), getName().value_or("(null)"), "shipdata",  "Trying another missile.");
			}
		}
	}
	else
	{
		shipKey = (UNIVERSE != nullptr ? UNIVERSE->randomShipKeyForRoleRespectingConditions(role) : std::optional<std::string>());
		if (!shipKey.has_value())
		{
			OO_LOG_WARN("ship.setUp.missiles", "{} \"{}\" used in ship \"{}\" needs a valid {}.plist entry.{}", "missile_role", role, getName().value_or("(null)"), "shipdata", " Using defaults instead.");
			return nil;
		}
	}

	eqRole = OOEquipmentType::getMissileRegistryRoleForShip(*shipKey);	// eqRole != role for generic missiles.

	if (!eqRole.has_value())
	{
		missile = (UNIVERSE != nullptr ? UNIVERSE->newShipWithName(*shipKey) : (::ShipEntity *)nil);
		if (!missile)
		{
			if (isRandomMissile)
				OO_LOG_WARN("ship.setUp.missiles", "{} \"{}\" used in ship \"{}\" needs a valid {}.plist entry.{}", "random missile", *shipKey, getName().value_or("(null)"), "shipdata",  "Trying another missile.");
			else
				OO_LOG_WARN("ship.setUp.missiles", "{} \"{}\" used in ship \"{}\" needs a valid {}.plist entry.{}", "missile_role", role, getName().value_or("(null)"), "shipdata", " Using defaults instead.");

			OOEquipmentType::setMissileRegistryRole("", *shipKey);	// no valid role for this shipKey
			if (isRandomMissile) return verifiedMissileTypeFromRole(role);
			else return nil;
		}

		if(isRandomMissile)
		{
			const oo::Ref<::OORoleSet> missileRoles = missile->getRoleSet();
			for (const std::string &value : (missileRoles != nullptr) ? missileRoles->roles() : std::vector<std::string>())
			{
				role = value;
				missileType = OOEquipmentType::equipmentTypeWithIdentifier(role).get();
				// ensure that we have a missile or mine
				if ((missileType != nullptr ? missileType->isMissileOrMine() : false)) break;
			}

			if (!(missileType != nullptr ? missileType->isMissileOrMine() : false))
			{
				role = *shipKey;	// unique identifier to use in lieu of a valid equipment type if none are defined inside the generic missile roleset.
			}
		}

		missileType = OOEquipmentType::equipmentTypeWithIdentifier(role).get();

		if (!missileType)
		{
			OO_LOG_WARN("ship.setUp.missiles", "{} \"{}\" used in ship \"{}\" needs a valid {}.plist entry.{}", (isRandomMissile ? "random missile" : "missile_role"), role, getName().value_or("(null)"), "equipment", " Enabling compatibility mode.");
			missileType = generateMissileEquipmentTypeFrom(role);
		}

		OOEquipmentType::setMissileRegistryRole(role, *shipKey);
		if (missile != nullptr)  oo::ReleaseEntity(missile);
	}
	else
	{
		if (eqRole->empty())
		{
			// wrong ship definition, already written to the log in a previous call.
			if (isRandomMissile) return verifiedMissileTypeFromRole(role);	// try and find a valid missile with role 'missile'.
			return nil;
		}
		missileType = OOEquipmentType::equipmentTypeWithIdentifier(*eqRole).get();
	}

	return missileType;
}


::OOEquipmentType *ShipEntity::selectMissile()
{
	::OOEquipmentType		*missileType = nil;
	std::string			role;
	double				chance = randf();
	BOOL				thargoidMissile = NO;

	if (isThargoid())
	{
		if (_missileRole.has_value()) missileType = verifiedMissileTypeFromRole(*_missileRole);
		if (missileType == nil) {
			_missileRole = "EQ_THARGON";	// no valid missile_role defined, use thargoid fallback from now on.
			missileType = verifiedMissileTypeFromRole(*_missileRole);
		}
	}
	else
	{
		// All other ships: random role 10% of the cases when auto weapons is set, if a missile_role is defined.
		// Without auto weapons, never random.
		float randomSelectionChance = chance;
		if(!hasAutoWeapons())  randomSelectionChance = 0.0f;
		if (randomSelectionChance < 0.9f && _missileRole.has_value())
		{
			missileType = verifiedMissileTypeFromRole(*_missileRole);
		}

		if (missileType == nil)	// the random 10% , or no valid missile_role defined
		{
			if (chance < 0.9f && _missileRole.has_value())	// no valid missile_role defined?
			{
				_missileRole = std::nullopt;	// use generic ship fallback from now on.
			}

			// assign random missiles 20% of the time without missile_role (or 10% with valid missile_role)
			if (chance > 0.8f) role = "missile";
			// otherwise use the standard role
			else role = "EQ_MISSILE";

			missileType = verifiedMissileTypeFromRole(role);
		}
	}

	if (missileType == nil) OO_LOG_ERR("ship.setUp.missiles", "could not resolve missile / mine type for ship \"{}\". Original missile role:\"{}\".", getName().value_or("(null)"), _missileRole.value_or("(null)"));

	role = oo::str::lowercase((missileType != nullptr ? missileType->identifier() : std::optional<std::string>()).value_or(""));
	thargoidMissile = isThargoid() && (oo::str::hasSuffix(role, "thargon") || oo::str::hasPrefix(role, "thargon"));

	if (thargoidMissile || (!thargoidMissile && (missileType != nullptr ? missileType->isMissileOrMine() : false)))
	{
		return missileType;
	}
	else
	{
		OO_LOG_WARN("ship.setUp.missiles", "missile_role \"{}\" is not a valid missile / mine type for ship \"{}\".{}", (missileType != nullptr ? missileType->identifier() : std::optional<std::string>()).value_or("(null)"), getName().value_or("(null)"), " No missile selected.");
		return nil;
	}
}


void ShipEntity::removeAllEquipment()
{
	_equipment.clear();
}


OOCreditsQuantity ShipEntity::removeMissiles()
{
	missiles = 0;
	return 0;
}


NSUInteger ShipEntity::parcelCount()
{
	return 0;
}


NSUInteger ShipEntity::passengerCount()
{
	return 0;
}


NSUInteger ShipEntity::passengerCapacity()
{
	return 0;
}


NSUInteger ShipEntity::missileCount()
{
	return missiles;
}


NSUInteger ShipEntity::missileCapacity()
{
	return max_missiles;
}


NSUInteger ShipEntity::extraCargo()
{
	return extra_cargo;
}


/* This is used for e.g. displaying the HUD icon */
bool ShipEntity::hasScoop()
{
	return hasEquipmentItemProviding("EQ_FUEL_SCOOPS") || hasEquipmentItemProviding("EQ_CARGO_SCOOPS");
}


bool ShipEntity::hasFuelScoop()
{
	return hasEquipmentItemProviding("EQ_FUEL_SCOOPS");
}


/* No such core equipment item, but EQ_FUEL_SCOOPS provides it */
bool ShipEntity::hasCargoScoop()
{
	return hasEquipmentItemProviding("EQ_CARGO_SCOOPS");
}


bool ShipEntity::hasECM()
{
	return hasEquipmentItemProviding("EQ_ECM");
}


bool ShipEntity::hasCloakingDevice()
{
	/* TODO: Checks above stop this being 'providing'. */
	return hasEquipmentItem(oo::PList("EQ_CLOAKING_DEVICE"));
}


bool ShipEntity::hasMilitaryScannerFilter()
{
#if USEMASC
	return hasEquipmentItemProviding("EQ_MILITARY_SCANNER_FILTER");
#else
	return NO;
#endif
}


bool ShipEntity::hasMilitaryJammer()
{
#if USEMASC
	return hasEquipmentItemProviding("EQ_MILITARY_JAMMER");
#else
	return NO;
#endif
}


bool ShipEntity::hasExpandedCargoBay()
{
	/* Not 'providing' - controlled through scripts */
	return hasEquipmentItem(oo::PList("EQ_CARGO_BAY"));
}


bool ShipEntity::hasShieldBooster()
{
	/* Not 'providing' - controlled through scripts */
	return hasEquipmentItem(oo::PList("EQ_SHIELD_BOOSTER"));
}


bool ShipEntity::hasMilitaryShieldEnhancer()
{
	/* Not 'providing' - controlled through scripts */
	return hasEquipmentItem(oo::PList("EQ_NAVAL_SHIELD_BOOSTER"));
}


bool ShipEntity::hasHeatShield()
{
	return hasEquipmentItemProviding("EQ_HEAT_SHIELD");
}


bool ShipEntity::hasFuelInjection()
{
	return hasEquipmentItemProviding("EQ_FUEL_INJECTION");
}


bool ShipEntity::hasCascadeMine()
{
	/* TODO: this could be providing since theoretically OXP
	 * deployable mines could also do cascade effects, but there are
	 * probably better ways to manage OXP pylon AI */
	return hasEquipmentItem(oo::PList("EQ_QC_MINE"), YES, NO);
}


bool ShipEntity::hasEscapePod()
{
	return hasEquipmentItemProviding("EQ_ESCAPE_POD");
}


bool ShipEntity::hasDockingComputer()
{
	return hasEquipmentItemProviding("EQ_DOCK_COMP");
}


bool ShipEntity::hasGalacticHyperdrive()
{
	return hasEquipmentItemProviding("EQ_GAL_DRIVE");
}


float ShipEntity::shieldBoostFactor()
{
	float boostFactor = 1.0f;
	if (hasShieldBooster())  boostFactor += 1.0f;
	if (hasMilitaryShieldEnhancer())  boostFactor += 1.0f;
	
	return boostFactor;
}


/* These next three are never called as of 12/12/2014, as NPCs don't
 * have shields and PlayerEntity overrides these. */
float ShipEntity::maxForwardShieldLevel()
{
	return BASELINE_SHIELD_LEVEL * shieldBoostFactor();
}


float ShipEntity::maxAftShieldLevel()
{
	return BASELINE_SHIELD_LEVEL * shieldBoostFactor();
}


float ShipEntity::shieldRechargeRate()
{
	return hasMilitaryShieldEnhancer() ? 3.0f : 2.0f;
}


double ShipEntity::maxHyperspaceDistance()
{
	return MAX_JUMP_RANGE;
}




// Slice 11 of docs/phases/3-slices/ShipEntity.md (bead oo-eh955): thrust and afterburner;
// behaviours: idle, tumble, tractored, track, intercept, break off, dogfight, evasive. Members of
// the C++ ship, called directly, since bead oo-9ht.144 deleted the facade (ADR-0056 amendment
// oo-9ht.144).

float ShipEntity::afterburnerFactor()
{
	return afterburner_speed_factor;
}


float ShipEntity::afterburnerRate()
{
	return afterburner_rate;
}


void ShipEntity::setAfterburnerFactor(GLfloat newValue)
{
	afterburner_speed_factor = newValue;
}


void ShipEntity::setAfterburnerRate(GLfloat newValue)
{
	afterburner_rate = newValue;
}


float ShipEntity::maxThrust()
{
	return max_thrust;
}


void ShipEntity::setMaxThrust(GLfloat newValue)
{
	max_thrust = newValue;
}


float ShipEntity::getThrust()
{
	return thrust;
}


////////////////
//            //
// behaviours //
//            //
void ShipEntity::behaviour_stop_still(double delta_t)
{
	stick_roll = 0.0;
	stick_pitch = 0.0;
	stick_yaw = 0.0;
	applySticks(delta_t);

	
}


void ShipEntity::behaviour_idle(double delta_t)
{
	stick_yaw = 0.0;
	if ((!isStation)&&(scanClass != CLASS_BUOY))
	{
		stick_roll = 0.0;
	}
	else
	{
		stick_roll = flightRoll;
	}
	if (scanClass != CLASS_BUOY)
	{
		stick_pitch = 0.0;
	}
	else
	{
		stick_pitch = flightPitch;
	}
	applySticks(delta_t);
	
	
}


void ShipEntity::behaviour_tumble(double delta_t)
{
	applySticks(delta_t);
	
	
}


void ShipEntity::behaviour_tractored(double delta_t)
{
	desired_range = collision_radius * 2.0;
	::ShipEntity* hauler = oo::ToShip(owner());
	if ((hauler)&&((hauler != nullptr ? hauler->getIsShip() : false)))
	{
		_destination = (hauler != nullptr ? hauler->absoluteTractorPosition() : HPVector{});
		double  distance = rangeToDestination();
		if (distance < desired_range)
		{
			performTumble();
			setStatus(STATUS_IN_FLIGHT);
			if (hauler != nullptr)  hauler->scoopUp(this);
			return;
		}
		GLfloat tf = TRACTOR_FORCE / mass;
		// adjust for difference in velocity (spring rule)
		Vector dv = vector_between(getVelocity(), (hauler != nullptr ? hauler->getVelocity() : Vector{}));
		GLfloat moment = delta_t * 0.25 * tf;
		velocity.x += moment * dv.x;
		velocity.y += moment * dv.y;
		velocity.z += moment * dv.z;
		// acceleration = force / mass
		// force proportional to distance (spring rule)
		HPVector dp = HPvector_between(position, _destination);
		moment = delta_t * 0.5 * tf;
		velocity.x += moment * dp.x;
		velocity.y += moment * dp.y;
		velocity.z += moment * dp.z;
		// force inversely proportional to distance
		GLfloat d2 = HPmagnitude2(dp);
		moment = (d2 > 0.0)? delta_t * 5.0 * tf / d2 : 0.0;
		if (d2 > 0.0)
		{
			velocity.x += moment * dp.x;
			velocity.y += moment * dp.y;
			velocity.z += moment * dp.z;
		}
		//
		if (status() == STATUS_BEING_SCOOPED)
		{
			BOOL lost_contact = (distance > hauler->collision_radius + collision_radius + 250.0f);	// 250m range for tractor beam
			if ((hauler != nullptr ? hauler->getIsPlayer() : false))
			{
				switch (static_cast<PlayerEntity *>(hauler)->dialFuelScoopStatus())
				{
					case SCOOP_STATUS_NOT_INSTALLED:
					case SCOOP_STATUS_FULL_HOLD:
						lost_contact = YES;	// don't draw
						break;
						
					case SCOOP_STATUS_OKAY:
					case SCOOP_STATUS_ACTIVE:
						break;
				}
			}
			
			if (lost_contact)	// 250m range for tractor beam
			{
				// escaped tractor beam
				setStatus(STATUS_IN_FLIGHT);
				behaviour = BEHAVIOUR_IDLE;
				setThrust(maxThrust()); // restore old thrust.
				frustration = 0.0;
				setOwner(this);
				if (shipAI != nullptr)  shipAI->exitStateMachineWithMessage(std::nullopt);	// exit nullAI.plist
				return;
			}
			else if ((hauler != nullptr ? hauler->getIsPlayer() : false))
			{
				static_cast<PlayerEntity *>(hauler)->setScoopsActive();
			}
		}
	}

// being tractored; sticks ignored - CIM
	flightYaw = 0.0;
	
	desired_speed = 0.0;
	thrust = 25.0;	// used to damp velocity (must be less than hauler thrust)
	
	thrust = 0.0;	// must reset thrust now
}


void ShipEntity::behaviour_track_target(double delta_t)
{
	if (primaryTarget() == nil)
	{
		noteLostTargetAndGoIdle();
		return;
	}
	trackPrimaryTarget(delta_t, NO); // applies sticks
	if (hasProximityAlertIgnoringTarget(YES))
	{
		avoidCollision();
	}
	
}


void ShipEntity::behaviour_intercept_target(double delta_t)
{
	double  range = rangeToPrimaryTarget();
	if (behaviour == BEHAVIOUR_INTERCEPT_TARGET)
	{
		desired_speed = maxFlightSpeed;
		if (range < desired_range)
		{
			if (shipAI != nullptr)  shipAI->reactToMessage("DESIRED_RANGE_ACHIEVED", "BEHAVIOUR_INTERCEPT_TARGET");
			doScriptEvent(OOJSID("shipAchievedDesiredRange"));

		}
		desired_speed = maxFlightSpeed * trackPrimaryTarget(delta_t, NO);
	}
	else
	{
		// = BEHAVIOUR_COLLECT_TARGET
		::ShipEntity*	target = oo::ToShip(primaryTarget());
// if somehow ended up in this state but target is not cargo, stop
// trying to scoop it
		if (!target || (target != nullptr ? target->getScanClass() : OOScanClass{}) != CLASS_CARGO || (target != nullptr && target->cargoType() == CARGO_NOT_CARGO))
		{
			noteLostTargetAndGoIdle();
			return;
		}
		double target_speed = (target != nullptr ? target->speed() : 0.0);
		double eta = range / (flightSpeed - target_speed);
		double last_success_factor = success_factor;
		double last_distance = last_success_factor;
		double  distance = rangeToDestination();
		success_factor = distance;
		//
		double slowdownTime = 96.0 / (thrust*SHIP_THRUST_FACTOR);	// more thrust implies better slowing
		double minTurnSpeedFactor = 0.005 * max_flight_pitch * max_flight_roll;	// faster turning implies higher speeds

		if ((eta < slowdownTime)&&(flightSpeed > maxFlightSpeed * minTurnSpeedFactor))
			desired_speed = flightSpeed * 0.75;   // cut speed by 50% to a minimum minTurnSpeedFactor of speed
		else
			desired_speed = maxFlightSpeed;

		if (desired_speed < target_speed)
		{
			desired_speed += target_speed;
			if (target_speed > maxFlightSpeed)
			{
				noteLostTargetAndGoIdle();
				return;
			}
		}
		if (desired_speed > maxFlightSpeed)
		{ // never use injectors for scooping
			desired_speed = maxFlightSpeed;
		}

		_destination = target->position;
		desired_range = 0.5 * target->collision_radius;
		trackDestination( delta_t ,  NO);

		//
		if (distance < last_distance)	// improvement
		{
			frustration -= delta_t;
			if (frustration < 0.0)
				frustration = 0.0;
		}
		else
		{
			frustration += delta_t * 0.9;
			if (frustration > 10.0)	// 10s of frustration
			{
				noteFrustration("BEHAVIOUR_INTERCEPT_TARGET");
				frustration -= 5.0;	//repeat after another five seconds' frustration
			}
		}
	}
	if (hasProximityAlertIgnoringTarget(YES))
	{
		avoidCollision();
	}
	
	
}


void ShipEntity::behaviour_attack_break_off_target(double delta_t)
{
	if (!canStillTrackPrimaryTarget())
	{
		noteLostTargetAndGoIdle();
		return;
	}
	BOOL	canBurn = hasFuelInjection() && (fuel > MIN_FUEL);
	float	max_available_speed = maxFlightSpeed;
	double  range = rangeToPrimaryTarget();
	if (canBurn) max_available_speed *= afterburnerFactor();

	desired_speed = max_available_speed;

	Entity *target = primaryTarget();

	if (desired_speed > maxFlightSpeed)
	{
		double target_speed = (target != nullptr ? target->speed() : 0.0);
		if (desired_speed > target_speed * 3.0)
		{
			desired_speed = maxFlightSpeed; // don't overuse the injectors
		}
	}

	if (cloakAutomatic) activateCloakingDevice();
	if (hasProximityAlertIgnoringTarget(NO))
	{
		avoidCollision();
		return;
	}

	frustration += delta_t;
	if (frustration > 15.0 && accuracy >= COMBAT_AI_DOGFIGHTER && !canBurn)
	{
		desired_speed = maxFlightSpeed / 2.0;
	}
	double aspect = approachAspectToPrimaryTarget();
	if (range > 3000.0 || (oo::EntityIsShip(target) && (oo::ToShip(target) != nullptr ? oo::ToShip(target)->primaryTarget() : (Entity *)nullptr) != this) || frustration - floor(frustration) > fmin(1.6/max_flight_roll,aspect))
	{
		trackPrimaryTarget(delta_t, YES);
	}
	else
	{
// less useful at long range if not under direct fire
		evasiveAction(delta_t);
	}

	if (range > COMBAT_OUT_RANGE_FACTOR * weaponRange)
	{
		behaviour = BEHAVIOUR_ATTACK_TARGET;
	}
	else if (aspect < -0.75 && accuracy >= COMBAT_AI_DOGFIGHTER)
	{
		behaviour = BEHAVIOUR_ATTACK_SLOW_DOGFIGHT;
	}
	else if (frustration > 10.0 && approachAspectToPrimaryTarget() < 0.85 && forward_weapon_temp < COMBAT_AI_WEAPON_TEMP_READY)
	{
		frustration = 0.0;
		if (accuracy >= COMBAT_AI_DOGFIGHTER)
		{
			behaviour = BEHAVIOUR_ATTACK_SLOW_DOGFIGHT;
		}
		else
		{
			behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET;
		}
	}

	flightYaw = 0.0;
}


void ShipEntity::behaviour_attack_slow_dogfight(double delta_t)
{
	if (!canStillTrackPrimaryTarget())
	{
		noteLostTargetAndGoIdle();
		return;
	}
	if (hasProximityAlertIgnoringTarget(YES))
	{
		avoidCollision();
		return;
	} 
	double  range = rangeToPrimaryTarget();
	::ShipEntity*	target = oo::ToShip(primaryTarget());
	double aspect = approachAspectToPrimaryTarget();
	if (range < 2.5*(collision_radius+target->collision_radius) && proximityAlert() == target && aspect > 0) {
		desired_speed = maxFlightSpeed;
		avoidCollision();
		return;
	}
	if (aspect < -0.5 && range > COMBAT_IN_RANGE_FACTOR * weaponRange * 2.0)
	{
		behaviour = BEHAVIOUR_ATTACK_TARGET;
	}
	else if (aspect < -0.5)
	{
// mostly behind target - try to stay there and keep up
		desired_speed = fmin(maxFlightSpeed * 0.5,(target != nullptr ? target->speed() : 0.0)*0.5);		
	}
	else if (aspect < 0.3)
	{
// to side of target - slow right down
		desired_speed = maxFlightSpeed * 0.1;
	}
	else
	{
// coming to front of target - accelerate for a quick getaway
		desired_speed = maxFlightSpeed * fmin(aspect*2.5,1.0);
	}
	if (aspect > 0.85)
	{
		behaviour = BEHAVIOUR_ATTACK_BREAK_OFF_TARGET;
	}
	if (aspect > 0.0)
	{
		frustration += delta_t;
	}
	else
	{
		frustration -= delta_t;
	}
	if (frustration > 10.0)
	{
		desired_speed /= 2.0;
	}
	else if (frustration < 0.0)
		frustration = 0.0;
	
	trackPrimaryTarget(delta_t, NO);
	
	if (missiles) considerFiringMissile(delta_t);

	if (cloakAutomatic) activateCloakingDevice();

}


void ShipEntity::behaviour_evasive_action(double delta_t)
{
	BOOL	canBurn = hasFuelInjection() && (fuel > MIN_FUEL);
	float	max_available_speed = maxFlightSpeed;
//	double  range = [self rangeToPrimaryTarget];
	if (canBurn) max_available_speed *= afterburnerFactor();
	desired_speed = max_available_speed;
	if (desired_speed > maxFlightSpeed)
	{
		::ShipEntity*	target = oo::ToShip(primaryTarget());
		double target_speed = (target != nullptr ? target->speed() : 0.0);
		if (desired_speed > target_speed)
		{
			desired_speed = maxFlightSpeed; // don't overuse the injectors
		}
	}
	
	if (cloakAutomatic) activateCloakingDevice();
	if (proximityAlert() != nullptr)
	{
		avoidCollision();
		return;
	}

	evasiveAction(delta_t);

	frustration += delta_t;
	
	if (frustration > 0.5)
	{
		if (behaviour == BEHAVIOUR_FLEE_EVASIVE_ACTION)
		{
			setEvasiveJink(400.0);
			behaviour = BEHAVIOUR_FLEE_TARGET;
		}
		else
		{
			behaviour = BEHAVIOUR_ATTACK_TARGET;
		}
	}

	flightYaw = 0.0;

	// probably only useful for Thargoids, except for the occasional opportunist
	fireMainWeapon(rangeToPrimaryTarget());
	
}




// Slice 12 of docs/phases/3-slices/ShipEntity.md (bead oo-0akes): behaviours: attack target,
// broadside, close with target. Members of the C++ ship, called directly, since bead oo-9ht.144
// deleted the facade (ADR-0056 amendment oo-9ht.144).

void ShipEntity::behaviour_attack_target(double /*delta_t*/)
{
	double  range = rangeToPrimaryTarget();
	
	if (cloakAutomatic) activateCloakingDevice();

/* Start of behaviour selection:
 * Anything beyond the basics should require accuracy >= COMBAT_AI_ISNT_AWFUL
 * Anything fancy should require accuracy >= COMBAT_AI_IS_SMART
 * If precise aim is required, behaviour should have accuracy >= COMBAT_AI_TRACKS_CLOSER
 * - CIM
 */

	OOWeaponType forward_weapon_real_type = forward_weapon_type;
	GLfloat forward_weapon_real_temp = forward_weapon_temp;

// if forward weapon is actually on a subent
	if (isWeaponNone(forward_weapon_real_type))
	{
		BOOL hasTurrets = NO;
		for (const auto &sub : shipSubEntities())
		{
			if (!isWeaponNone(forward_weapon_real_type))  break;
			::ShipEntity *se = oo::ToShip(sub.get());
			forward_weapon_real_type = se->forward_weapon_type;
			forward_weapon_real_temp = se->forward_weapon_temp;
			if (se->behaviour == BEHAVIOUR_TRACK_AS_TURRET)
			{
				hasTurrets = YES;
			}
		}
		if (isWeaponNone(forward_weapon_real_type) && hasTurrets)
		{ // safety for ships only equipped with turrets
			forward_weapon_real_type = cxx_OOWeaponTypeFromEquipmentIdentifierSloppy("EQ_WEAPON_PULSE_LASER");
			forward_weapon_real_temp = COMBAT_AI_WEAPON_TEMP_USABLE * 0.9;
		}
	}

	if ((forward_weapon_real_type != nullptr ? forward_weapon_real_type->isTurretLaser() : false)) 
	{
		behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE;
	} 
	else 
	{
		BOOL in_good_range = aim_tolerance*range < COMBAT_AI_CONFIDENCE_FACTOR;

		BOOL aft_weapon_ready = !isWeaponNone(aft_weapon_type) && (aft_weapon_temp < COMBAT_AI_WEAPON_TEMP_READY) && in_good_range;
		BOOL forward_weapon_ready = !isWeaponNone(forward_weapon_real_type) && (forward_weapon_real_temp < COMBAT_AI_WEAPON_TEMP_READY); // does not require in_good_range
		BOOL port_weapon_ready = !isWeaponNone(port_weapon_type) && (port_weapon_temp < COMBAT_AI_WEAPON_TEMP_READY) && in_good_range;
		BOOL starboard_weapon_ready = !isWeaponNone(starboard_weapon_type) && (starboard_weapon_temp < COMBAT_AI_WEAPON_TEMP_READY) && in_good_range;
// if no weapons cool enough to be good choices, be less picky
		BOOL weapons_heating = NO;
		if (!forward_weapon_ready && !aft_weapon_ready && !port_weapon_ready && !starboard_weapon_ready)
		{
			weapons_heating = YES;
			aft_weapon_ready = !isWeaponNone(aft_weapon_type) && (aft_weapon_temp < COMBAT_AI_WEAPON_TEMP_USABLE) && in_good_range;
			forward_weapon_ready = !isWeaponNone(forward_weapon_real_type) && (forward_weapon_real_temp < COMBAT_AI_WEAPON_TEMP_USABLE); // does not require in_good_range
			port_weapon_ready = !isWeaponNone(port_weapon_type) && (port_weapon_temp < COMBAT_AI_WEAPON_TEMP_USABLE) && in_good_range;
		starboard_weapon_ready = !isWeaponNone(starboard_weapon_type) && (starboard_weapon_temp < COMBAT_AI_WEAPON_TEMP_USABLE) && in_good_range;
		}

		Entity *target = primaryTarget();
		double aspect = approachAspectToPrimaryTarget();

		if (!forward_weapon_ready && !aft_weapon_ready && !port_weapon_ready && !starboard_weapon_ready)
		{ // no usable weapons! Either not fitted or overheated
			
			// if unarmed
			if (isWeaponNone(forward_weapon_real_type) && 
				isWeaponNone(aft_weapon_type) && 
				isWeaponNone(port_weapon_type) && 
				isWeaponNone(starboard_weapon_type))
			{
				behaviour = BEHAVIOUR_ATTACK_FLY_FROM_TARGET;
			}
			else if (aspect > 0)
			{
				if (in_good_range)
				{
					if (accuracy >= COMBAT_AI_IS_SMART && randf() < 0.75)
					{
						behaviour = BEHAVIOUR_EVASIVE_ACTION;
					}
					else 
					{
						behaviour = BEHAVIOUR_ATTACK_FLY_FROM_TARGET;
					}
				}
				else 
				{
					// ready to get more accurate shots later
					behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET;
				}
			} 
			else
			{
				// if target is running away, stay on target
				// unless too close for safety
				if (range < COMBAT_IN_RANGE_FACTOR * weaponRange) {
					behaviour = BEHAVIOUR_ATTACK_FLY_FROM_TARGET;
				} else {
					behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET;
				}
			}
		}
// if our current target isn't targeting us, and we have some idea of how to fight, and our weapons are running hot, and we're fairly nearby
		else if (weapons_heating && accuracy >= COMBAT_AI_ISNT_AWFUL && oo::EntityIsShip(target) && (oo::ToShip(target) != nullptr ? oo::ToShip(target)->primaryTarget() : (Entity *)nullptr) != this && range < COMBAT_OUT_RANGE_FACTOR * weaponRange) 
		{
// then back off a bit for weapons to cool so we get a good attack run later, rather than weaving closer
			float relativeSpeed = magnitude(vector_subtract(getVelocity(), (target != nullptr ? target->getVelocity() : kZeroVector)));
			setEvasiveJink((range + COMBAT_JINK_OFFSET - relativeSpeed / max_flight_pitch));
			behaviour = BEHAVIOUR_ATTACK_FLY_FROM_TARGET;
		}
		else 
		{
			BOOL nearby = range < COMBAT_IN_RANGE_FACTOR * getWeaponRangeFromType(forward_weapon_type);
			BOOL midrange = range < COMBAT_OUT_RANGE_FACTOR * getWeaponRangeFromType(aft_weapon_type);


			if (nearby && aft_weapon_ready)
			{
				jink = kZeroVector; // almost all behaviours
				behaviour = BEHAVIOUR_RUNNING_DEFENSE;
			}
			else if (nearby && (port_weapon_ready || starboard_weapon_ready))
			{
				jink = kZeroVector; // almost all behaviours
				behaviour = BEHAVIOUR_ATTACK_BROADSIDE;
			}
			else if (nearby)
			{
				if (!pitching_over) // don't change jink in the middle of a sharp turn.
				{
					/*
						For most AIs, is behaviour_attack_target called as starting behaviour on every hit.
						Target can both fly towards or away from ourselves here. Both situations
						need a different jink.z for optimal collision avoidance at high speed approach and low speed dogfighting.
						The COMBAT_JINK_OFFSET intentionally over-compensates the range for collision radii to send ships towards
						the target at low speeds.
					*/
					float relativeSpeed = magnitude(vector_subtract(getVelocity(), (target != nullptr ? target->getVelocity() : kZeroVector)));
					setEvasiveJink((range + COMBAT_JINK_OFFSET - relativeSpeed / max_flight_pitch));
				}
				// good pilots use behaviour_attack_break_off_target instead
				if (accuracy >= COMBAT_AI_FLEES_BETTER)
				{
					behaviour = BEHAVIOUR_ATTACK_BREAK_OFF_TARGET;
				}
				else
				{
					behaviour = BEHAVIOUR_ATTACK_FLY_FROM_TARGET;
				}
			}
			else if (forward_weapon_ready)
			{
				jink = kZeroVector; // almost all behaviours

				// TODO: good pilots use behaviour_attack_sniper sometimes
				if (getWeaponRangeFromType(forward_weapon_real_type) > 12500 && range > 12500)
				{
					behaviour = BEHAVIOUR_ATTACK_SNIPER;
				}
// generally not good tactics the next two
				else if (accuracy < COMBAT_AI_ISNT_AWFUL && aspect < 0)
				{
					behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX;
				}
				else if (accuracy < COMBAT_AI_ISNT_AWFUL)
				{
					behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE;
				}
				else
				{
					behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET;
				}
			}
			else if (port_weapon_ready || starboard_weapon_ready)
			{
				jink = kZeroVector; // almost all behaviours
				behaviour = BEHAVIOUR_ATTACK_BROADSIDE;
			}
			else if (aft_weapon_ready && midrange)
			{
				jink = kZeroVector; // almost all behaviours
				behaviour = BEHAVIOUR_RUNNING_DEFENSE;
			} 
			else
			{
				jink = kZeroVector; // almost all behaviours
				behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET;
			}
		}
	}

	frustration = 0.0;	// behaviour changed, so reset frustration
	
}


void ShipEntity::behaviour_attack_broadside(double /*delta_t*/)
{
	BOOL	canBurn = hasFuelInjection() && (fuel > MIN_FUEL);
	float	max_available_speed = maxFlightSpeed;
	double  range = rangeToPrimaryTarget();
	if (canBurn) max_available_speed *= afterburnerFactor();
	
	if (cloakAutomatic) activateCloakingDevice();

	if (!canStillTrackPrimaryTarget())
	{
		noteLostTargetAndGoIdle();
		return;
	}
	
	desired_speed = max_available_speed;
	if (range < COMBAT_BROADSIDE_IN_RANGE_FACTOR * weaponRange)
	{
		behaviour = BEHAVIOUR_ATTACK_TARGET;
	}
	else
	{
		if (port_weapon_temp < starboard_weapon_temp)
		{
			if (isWeaponNone(port_weapon_type))
			{
				behaviour = BEHAVIOUR_ATTACK_BROADSIDE_RIGHT;
				setWeaponDataFromType(starboard_weapon_type);
			}
			else
			{
				behaviour = BEHAVIOUR_ATTACK_BROADSIDE_LEFT;
				setWeaponDataFromType(port_weapon_type);
			}
		}
		else
		{
			if (isWeaponNone(starboard_weapon_type))
			{
				behaviour = BEHAVIOUR_ATTACK_BROADSIDE_RIGHT;
				setWeaponDataFromType(starboard_weapon_type);
			}
			else
			{
				behaviour = BEHAVIOUR_ATTACK_BROADSIDE_LEFT;
				setWeaponDataFromType(port_weapon_type);
			}
		}
		jink = kZeroVector;
		if (weapon_damage == 0.0)
		{ // safety in case side lasers no longer exist
			behaviour = BEHAVIOUR_ATTACK_TARGET;
		}
		else if (range > 0.9 * weaponRange)
		{
			behaviour = BEHAVIOUR_CLOSE_TO_BROADSIDE_RANGE;
		}
	}

	frustration = 0.0;	// behaviour changed, so reset frustration

	
}


void ShipEntity::behaviour_attack_broadside_left(double delta_t)
{
	behaviour_attack_broadside_target(delta_t, YES);
}


void ShipEntity::behaviour_attack_broadside_right(double delta_t)
{
	behaviour_attack_broadside_target(delta_t, NO);
}


void ShipEntity::behaviour_attack_broadside_target(double delta_t, bool leftside)
{
	BOOL	canBurn = hasFuelInjection() && (fuel > MIN_FUEL);
	float	max_available_speed = maxFlightSpeed;
	double  range = rangeToPrimaryTarget();
	if (canBurn) max_available_speed *= afterburnerFactor();
	if (primaryTarget() == nil)
	{
		noteLostTargetAndGoIdle();
		return;
	}
	GLfloat currentWeaponRange = getWeaponRangeFromType(leftside?port_weapon_type:starboard_weapon_type);
	if (range > COMBAT_BROADSIDE_RANGE_FACTOR * currentWeaponRange)
	{
		behaviour = BEHAVIOUR_CLOSE_TO_BROADSIDE_RANGE;
		return;
	}

// can get closer on broadsides since there's less risk of a collision
	if ((range < COMBAT_BROADSIDE_IN_RANGE_FACTOR * currentWeaponRange)||(proximityAlert() != nullptr))
	{
		if (!hasProximityAlertIgnoringTarget(YES))
		{
			behaviour = BEHAVIOUR_ATTACK_TARGET;
		}
		else
		{
			avoidCollision();
			return;
		}
	}
	else
	{
		if (!canStillTrackPrimaryTarget())
		{
			noteLostTargetAndGoIdle();
			return;
		}
	}
	// control speed
	//
	BOOL isUsingAfterburner = canBurn && (flightSpeed > maxFlightSpeed);
	double slow_down_range = currentWeaponRange * COMBAT_WEAPON_RANGE_FACTOR * ((isUsingAfterburner)? 3.0 * afterburnerFactor() : 1.0);
//	double target_speed = [target speed];
	if (range <= slow_down_range)
		desired_speed = fmin(0.8 * maxFlightSpeed, fmax((2.0-frustration)*maxFlightSpeed, 0.1 * maxFlightSpeed));   // within the weapon's range slow down to aim
	else
		desired_speed = max_available_speed; // use afterburner to approach

	double last_success_factor = success_factor;
	success_factor = trackSideTarget(delta_t, leftside);	// do the actual piloting
	if (weapon_temp > COMBAT_AI_WEAPON_TEMP_USABLE)
	{ // will probably have more luck with the other laser or picking a different attack method
		if (leftside)
		{
			if (!isWeaponNone(starboard_weapon_type))
			{
				behaviour = BEHAVIOUR_ATTACK_BROADSIDE_RIGHT;
			}
			else
			{
				behaviour = BEHAVIOUR_ATTACK_TARGET;
			}
		}
		else
		{
			if (!isWeaponNone(port_weapon_type))
			{
				behaviour = BEHAVIOUR_ATTACK_BROADSIDE_LEFT;
			}
			else 
			{
				behaviour = BEHAVIOUR_ATTACK_TARGET;
			}
		}
	}

/* FIXME: again, basically all of this next bit common with standard attack  */
	if ((success_factor > 0.999)||(success_factor > last_success_factor))
	{
		frustration -= delta_t;
		if (frustration < 0.0)
			frustration = 0.0;
	}
	else
	{
		frustration += delta_t;
		if (frustration > 3.0)	// 3s of frustration
		{
			
			noteFrustration("BEHAVIOUR_ATTACK_BROADSIDE");
			setEvasiveJink(1000.0);
			behaviour = BEHAVIOUR_ATTACK_FLY_FROM_TARGET;
			frustration = 0.0;
			desired_speed = maxFlightSpeed;
		}
	}

	if (missiles) considerFiringMissile(delta_t);

	if (cloakAutomatic) activateCloakingDevice();
	if (leftside)
	{
		firePortWeapon(range);
	}
	else 
	{
		fireStarboardWeapon(range);
	}
	
	
	if (weapon_temp > COMBAT_AI_WEAPON_TEMP_USABLE)
	{
		behaviour = BEHAVIOUR_ATTACK_TARGET;
	}
}


void ShipEntity::behaviour_close_to_broadside_range(double delta_t)
{
	double  range = rangeToPrimaryTarget();
	if (proximityAlert() != nullptr)
	{
		if (proximityAlert() == primaryTarget())
		{
			behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET; // this behaviour will handle proximity_alert.
			behaviour_attack_fly_from_target(delta_t); // do it now.
		}
		else
		{
			avoidCollision();
		}
		return;
	}
	if (!canStillTrackPrimaryTarget())
	{
		noteLostTargetAndGoIdle();
		return;
	}

	behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE;
	behaviour_fly_to_target_six(delta_t);
	if (!isWeaponNone(port_weapon_type))
	{
		setWeaponDataFromType(port_weapon_type);
	}
	else
	{
		setWeaponDataFromType(starboard_weapon_type);
	}
	if (range <= COMBAT_BROADSIDE_RANGE_FACTOR * weaponRange)
	{
		behaviour = BEHAVIOUR_ATTACK_BROADSIDE;
	}
	else
	{
		behaviour = BEHAVIOUR_CLOSE_TO_BROADSIDE_RANGE;
	}
}


void ShipEntity::behaviour_close_with_target(double delta_t)
{
	double  range = rangeToPrimaryTarget();
	if (proximityAlert() != nullptr)
	{
		if (proximityAlert() == primaryTarget())
		{
			behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET; // this behaviour will handle proximity_alert.
			behaviour_attack_fly_from_target(delta_t); // do it now.
		}
		else
		{
			avoidCollision();
		}
		return;
	}
	if (!canStillTrackPrimaryTarget())
	{
		noteLostTargetAndGoIdle();
		return;
	}
	behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE;
	double saved_frustration = frustration;
	behaviour_fly_to_target_six(delta_t);
	frustration = saved_frustration; // ignore fly-to-12 frustration
	frustration += delta_t;
	if (range <= COMBAT_IN_RANGE_FACTOR * weaponRange || frustration > 5.0)
	{
		behaviour = BEHAVIOUR_ATTACK_TARGET;
	}
	else
	{
		behaviour = BEHAVIOUR_CLOSE_WITH_TARGET;
	}


}




// Slice 13 of docs/phases/3-slices/ShipEntity.md (bead oo-xmajv): behaviours: sniper, fly to target
// six, mining target, attack fly to target. Members of the C++ ship, called directly, since bead
// oo-9ht.144 deleted the facade (ADR-0056 amendment oo-9ht.144).

void ShipEntity::behaviour_attack_sniper(double delta_t)
{

	if (!canStillTrackPrimaryTarget())
	{
		noteLostTargetAndGoIdle();
		return;
	}
	Entity *rawTarget = primaryTarget();
	if (!oo::EntityIsShip(rawTarget))
	{
		// can't attack a wormhole
		noteLostTargetAndGoIdle();
		return;
	}
	::ShipEntity *target = oo::ToShip(rawTarget);

	double  range = rangeToPrimaryTarget();
	float	max_available_speed = maxFlightSpeed;

	if (range < 15000)
	{
		behaviour = BEHAVIOUR_ATTACK_TARGET;
	}
	else 
	{
		if (range > weaponRange || range > scannerRange * 0.8)
		{
			BOOL	canBurn = hasFuelInjection() && (fuel > MIN_FUEL);
			if (canBurn && (target != nullptr ? target->getWeaponRange() : 0.0f) > weaponRange && range > weaponRange)
			{
				// if outside maximum weapon range, but inside target weapon range
				// close to fight ASAP!
				max_available_speed *= afterburnerFactor();
			}
			desired_speed = max_available_speed;
		}
		else
		{
			desired_speed = max_available_speed / 10.0f;
		}

		double last_success_factor = success_factor;
		success_factor = trackPrimaryTarget(delta_t, NO);
		
		if ((success_factor > 0.999)||(success_factor > last_success_factor))
		{
			frustration -= delta_t;
			if (frustration < 0.0)
				frustration = 0.0;
		}
		else
		{
			frustration += delta_t;
			if (frustration > 3.0)	// 3s of frustration
			{
				noteFrustration("BEHAVIOUR_ATTACK_SNIPER");
				setEvasiveJink(1000.0);
				behaviour = BEHAVIOUR_ATTACK_TARGET;
				frustration = 0.0;
				desired_speed = maxFlightSpeed;
			}
		}

	}

	if (missiles) considerFiringMissile(delta_t);

	if (cloakAutomatic) activateCloakingDevice();
	fireMainWeapon(range);

	if (weapon_temp > COMBAT_AI_WEAPON_TEMP_USABLE && accuracy >= COMBAT_AI_ISNT_AWFUL)
	{
		behaviour = BEHAVIOUR_ATTACK_TARGET;
	}

}


void ShipEntity::behaviour_fly_to_target_six(double delta_t)
{

	BOOL	canBurn = hasFuelInjection() && (fuel > MIN_FUEL);
	float	max_available_speed = maxFlightSpeed;
	double  range = rangeToPrimaryTarget();
	if (canBurn) max_available_speed *= afterburnerFactor();
	
	// deal with collisions and lost targets
	if (proximityAlert() != nullptr)
	{
		if (proximityAlert() == primaryTarget())
		{
			behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET; // this behaviour will handle proximity_alert.
			behaviour_attack_fly_from_target(delta_t); // do it now.
		}
		else
		{
			avoidCollision();
		}
		return;
	}
	if (!canStillTrackPrimaryTarget())
	{
		noteLostTargetAndGoIdle();
		return;
	}

	// control speed
	BOOL isUsingAfterburner = canBurn && (flightSpeed > maxFlightSpeed);
	BOOL closeQuickly = (canBurn && range > weaponRange);
	double	slow_down_range = weaponRange * COMBAT_WEAPON_RANGE_FACTOR * ((isUsingAfterburner)? 3.0 * afterburnerFactor() : 1.0);
	if (closeQuickly)
	{
		slow_down_range = weaponRange * COMBAT_OUT_RANGE_FACTOR;
	}
	double	back_off_range = weaponRange * COMBAT_OUT_RANGE_FACTOR * ((isUsingAfterburner)? 3.0 * afterburnerFactor() : 1.0);
	Entity *rawTarget = primaryTarget();
	if (!oo::EntityIsShip(rawTarget))
	{
		noteLostTargetAndGoIdle();
		return;
	}
	::ShipEntity*	target = oo::ToShip(rawTarget);
	double target_speed = (target != nullptr ? target->speed() : 0.0);
	double last_success_factor = success_factor;
	double distance = rangeToDestination();
	success_factor = distance;
		
	if (range < slow_down_range && (behaviour == BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX))
	{
		if (range < back_off_range)
		{
			desired_speed = fmax(0.9 * target_speed, 0.4 * maxFlightSpeed);
		} 
		else
		{
			desired_speed = fmax(target_speed * 1.2, maxFlightSpeed);
		}
		
		// avoid head-on collision
		if ((range < 0.5 * distance)&&(behaviour == BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX))
			behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE;
	}
	else
	{
		if (range < back_off_range)
		{
			desired_speed = fmax(0.9 * target_speed, 0.8 * maxFlightSpeed);
		} 
		else 
		{
			desired_speed = max_available_speed; // use afterburner to approach
		}
	}


	// if within 0.75km of the target's six or twelve, or if target almost at standstill for 62.5% of non-thargoid ships (!),
	// then vector in attack. 
	if (distance < 750.0 || (target_speed < 0.2 && !isThargoid() && (getUniversalID() & 14) > 4))
 	{
		behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET;
		frustration = 0.0;
		desired_speed = fmax(target_speed, 0.4 * maxFlightSpeed);   // within the weapon's range don't use afterburner
	}

	// target-six
	if (behaviour == BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX)
	{
		// head for a point weapon-range * 0.5 to the six of the target
		//
		_destination = (target != nullptr ? target->distance_six(0.5 * weaponRange) : HPVector{});
	}
	// target-twelve
	if (behaviour == BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE)
	{
		if ((forward_weapon_type != nullptr ? forward_weapon_type->isTurretLaser() : false))
		{
			// head for a point near the target, avoiding common Galcop weapon mount locations
			// TODO: this should account for weapon ranges
			GLfloat offset = 1000.0;
			GLfloat spacing = 2000.0;
			if (accuracy > 0.0) 
			{
				offset = accuracy * 750.0;
				spacing = 2000.0 + (accuracy * 500.0);
			}
			if (entity_personality & 1)
			{ // half at random
				offset = -offset;
			}
			_destination = (target != nullptr ? target->distance_twelve(spacing, offset) : HPVector{});
		}
		else 
		{
			// head for a point 1.25km above the target
			_destination = (target != nullptr ? target->distance_twelve(1250, 0) : HPVector{});
		}
	}

	pitching_over = NO; // in case it's set from elsewhere
	double confidenceFactor = trackDestination(delta_t, NO);
	
	if(success_factor > last_success_factor || confidenceFactor < 0.85) frustration += delta_t;
	else if(frustration > 0.0) frustration -= delta_t * 0.75;

	double aspect = approachAspectToPrimaryTarget();
	if(!(forward_weapon_type != nullptr ? forward_weapon_type->isTurretLaser() : false) && (frustration > 10 || aspect > 0.75))
	{
		behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET;
	}

	// use weaponry
	if (missiles) considerFiringMissile(delta_t);

	if (cloakAutomatic) activateCloakingDevice();
	fireMainWeapon(range);
	
	
	if (weapon_temp > COMBAT_AI_WEAPON_TEMP_USABLE)
	{
		behaviour = BEHAVIOUR_ATTACK_TARGET;
	}
}


void ShipEntity::behaviour_attack_mining_target(double delta_t)
{

	double  range = rangeToPrimaryTarget();
	if (!canStillTrackPrimaryTarget())
	{
		noteLostTargetAndGoIdle();
		desired_speed = maxFlightSpeed * 0.375;
		return;
	}
	else if ((range < 650) || (proximityAlert() != nullptr))
	{
		if (proximityAlert() == nullptr)	// NO_TARGET is 0: `== (Entity *)NO_TARGET` was the nil test
		{
			desired_speed = range * maxFlightSpeed / (650.0 * 16.0);
		}
		else
		{
			avoidCollision();
		}
	}
	else
	{
		//we have a target, its within scanner range, and outside 650
		desired_speed = maxFlightSpeed * 0.875;
	}

	trackPrimaryTarget(delta_t, NO);

	/* Don't open fire until within 3km - it doesn't take many mining
	 * laser shots to destroy an asteroid, but some of these mining
	 * ships are way too slow to effectively chase down the debris:
	 * wait until reasonably close before trying to split it. */
	if (range < 3000)
	{
		fireMainWeapon(range);
	}
	
	
}


void ShipEntity::behaviour_attack_fly_to_target(double delta_t)
{

	BOOL	canBurn = hasFuelInjection() && (fuel > MIN_FUEL);
	float	max_available_speed = maxFlightSpeed;
	double  range = rangeToPrimaryTarget();
	if (canBurn) max_available_speed *= afterburnerFactor();
	if (primaryTarget() == nil)
	{
		noteLostTargetAndGoIdle();
		return;
	}
	Entity *rawTarget = primaryTarget();
	if (!oo::EntityIsShip(rawTarget))
	{
		// can't attack a wormhole
		noteLostTargetAndGoIdle();
		return;
	}

	::ShipEntity *target = oo::ToShip(rawTarget);
	if ((range < COMBAT_IN_RANGE_FACTOR * weaponRange)||(proximityAlert() != nullptr))
	{
		if (!hasProximityAlertIgnoringTarget(YES))
		{
			behaviour = BEHAVIOUR_ATTACK_TARGET;
		}
		else
		{
			avoidCollision();
			return;
		}
	}
	else
	{
		if (!canStillTrackPrimaryTarget())
		{
			noteLostTargetAndGoIdle();
			return;
		}
	}

	// control speed
	//
	BOOL isUsingAfterburner = canBurn && (flightSpeed > maxFlightSpeed);
	BOOL closeQuickly = (canBurn && (target != nullptr ? target->getWeaponRange() : 0.0f) > weaponRange && range > weaponRange);
	double slow_down_range = weaponRange * COMBAT_WEAPON_RANGE_FACTOR * ((isUsingAfterburner)? 3.0 * afterburnerFactor() : 1.0);
	if (closeQuickly)
	{
		slow_down_range = weaponRange * COMBAT_OUT_RANGE_FACTOR;
	}
	double	back_off_range = 10000 * COMBAT_OUT_RANGE_FACTOR * ((isUsingAfterburner)? 3.0 * afterburnerFactor() : 1.0);
	double target_speed = (target != nullptr ? target->speed() : 0.0);
	double aspect = approachAspectToPrimaryTarget();

	if (range <= slow_down_range)
	{
		if (range < back_off_range)
		{
			if (accuracy < COMBAT_AI_IS_SMART || ((target != nullptr ? target->primaryTarget() : (Entity *)nullptr) == this && aspect > 0.8) || aim_tolerance*range > COMBAT_AI_CONFIDENCE_FACTOR)
			{
				if (accuracy >= COMBAT_AI_FLEES_BETTER && aspect > 0.8)
				{
					desired_speed = fmax(target_speed * 1.25, 0.8 * maxFlightSpeed);
					// stay at high speed if might be taking return fire
				}
				else
				{
					desired_speed = fmax(target_speed * 1.05, 0.25 * maxFlightSpeed);   // within the weapon's range match speed

				}
			}
			else
			{ // smart, and not being shot at right now - slow down to attack
				desired_speed = fmax(0.1 * target_speed, 0.1 * maxFlightSpeed);
			}
		}
		else
		{
			if (accuracy < COMBAT_AI_IS_SMART || ((target != nullptr ? target->getIsShip() : false) && (oo::ToShip(target) != nullptr ? oo::ToShip(target)->primaryTarget() : (Entity *)nullptr) == this) || range > weaponRange / 2.0)
			{
				desired_speed = fmax(target_speed * 1.5, maxFlightSpeed);
			}
			else
			{ // smart, and not being shot at right now - slow down to attack
				if (aspect > -0.25)
				{
					desired_speed = fmax(0.5 * target_speed, 0.5 * maxFlightSpeed);
				}
				else
				{
					desired_speed = fmax(1.25 * target_speed, 0.5 * maxFlightSpeed);
				}
			}
		}
	}
	else
	{
		if (closeQuickly)
		{
			desired_speed = max_available_speed; // use afterburner to approach
		}
		else
		{
			desired_speed = fmax(maxFlightSpeed,fmin(3.0 * target_speed, max_available_speed)); // possibly use afterburner to approach
		}
	}


	double last_success_factor = success_factor;
	success_factor = trackPrimaryTarget(delta_t, NO);	// do the actual piloting

	if ((success_factor > 0.999)||(success_factor > last_success_factor))
	{
		frustration -= delta_t;
		if (frustration < 0.0)
			frustration = 0.0;
	}
	else
	{
		frustration += delta_t;
		if (frustration > 3.0)	// 3s of frustration
		{
			noteFrustration("BEHAVIOUR_ATTACK_FLY_TO_TARGET");
			setEvasiveJink(1000.0);
			behaviour = BEHAVIOUR_ATTACK_TARGET;
			frustration = 0.0;
			desired_speed = maxFlightSpeed;
		}
	}

	if (missiles) considerFiringMissile(delta_t);

	if (cloakAutomatic) activateCloakingDevice();
	fireMainWeapon(range);
	
	
	if (weapon_temp > COMBAT_AI_WEAPON_TEMP_USABLE && accuracy >= COMBAT_AI_ISNT_AWFUL && aim_tolerance * range < COMBAT_AI_CONFIDENCE_FACTOR)
	{
		// don't do this if the target is fleeing and the front laser is
		// the only weapon, or if we're too far away to use non-front
		// lasers effectively
		if (aspect < 0 || 
			!isWeaponNone(aft_weapon_type) ||
			!isWeaponNone(port_weapon_type) ||
			!isWeaponNone(starboard_weapon_type))
		{
			frustration = 0.0;
			behaviour = BEHAVIOUR_ATTACK_TARGET;
		}
	}
	else if (accuracy >= COMBAT_AI_FLEES_BETTER_2) 
	{
		// if we're right in their gunsights, dodge!
		// need to dodge sooner if in aft sights
		if ((target != nullptr ? target->getBehaviour() : OOBehaviour{}) != BEHAVIOUR_FLEE_TARGET && (target != nullptr ? target->getBehaviour() : OOBehaviour{}) != BEHAVIOUR_FLEE_EVASIVE_ACTION)
		{
			if ((aspect > 0.99999 && !isWeaponNone((target != nullptr ? target->weaponTypeForFacing(WEAPON_FACING_FORWARD, NO) : (OOEquipmentType *)nullptr))) || (aspect < -0.999 && !isWeaponNone((target != nullptr ? target->weaponTypeForFacing(WEAPON_FACING_AFT, NO) : (OOEquipmentType *)nullptr))))
			{
				frustration = 0.0;
				behaviour = BEHAVIOUR_EVASIVE_ACTION;
			}
		}
	}
}




// Slice 14 of docs/phases/3-slices/ShipEntity.md (bead oo-v9sa5): behaviours: fly from target,
// running defence, flee, range from destination, face destination, land on planet, formation.
// Members of the C++ ship, called directly, since bead oo-9ht.144 deleted the facade (ADR-0056
// amendment oo-9ht.144).

void ShipEntity::behaviour_attack_fly_from_target(double delta_t)
{

	double  range = rangeToPrimaryTarget();
	double last_success_factor = success_factor;
	success_factor = range;
	
	if (primaryTarget() == nil)
	{
		noteLostTargetAndGoIdle();
		return;
	}
	if (last_success_factor > success_factor) // our target is closing in.
	{
		frustration += delta_t;
	}
	else
	{ // not getting away fast enough?
		frustration += delta_t / 4.0 ;
	}

	if (frustration > 10.0)
	{
		if (randf() < 0.3) {
			desired_speed = maxFlightSpeed * ((hasFuelInjection() && (fuel > MIN_FUEL)) ? afterburnerFactor() : 1);
		}
		else if (range > COMBAT_IN_RANGE_FACTOR * weaponRange && randf() < 0.3)
		{
			behaviour = BEHAVIOUR_ATTACK_TARGET;
		}
		GLfloat z = jink.z;
		if (randf() < 0.3)
		{
			z /= 2; // move the z-offset closer to the target to let him fly away from the target.
			desired_speed = flightSpeed * 2; // increase speed a bit.
		}
		setEvasiveJink(z);

		frustration /= 2.0;
	}
	if (desired_speed > maxFlightSpeed)
	{
		::ShipEntity*	target = oo::ToShip(primaryTarget());
		double target_speed = (target != nullptr ? target->speed() : 0.0);
		if (desired_speed > target_speed * 2.0)
		{
			desired_speed = maxFlightSpeed; // don't overuse the injectors
		}
	}
	else if (desired_speed < maxFlightSpeed * 0.5)
	{
		desired_speed = maxFlightSpeed;
	}

	if (range > COMBAT_OUT_RANGE_FACTOR * weaponRange + 15.0 * jink.x || 
			flightSpeed > (scannerRange - range) * max_flight_pitch / 6.28)
	{
		jink = kZeroVector;
		behaviour = BEHAVIOUR_ATTACK_TARGET;
		frustration = 0.0;
	}
	trackPrimaryTarget(delta_t, YES);

	if (missiles) considerFiringMissile(delta_t);

	if (cloakAutomatic) activateCloakingDevice();
	if (hasProximityAlertIgnoringTarget(YES))
		avoidCollision();

	if (accuracy >= COMBAT_AI_FLEES_BETTER_2) 
	{
		double aspect = approachAspectToPrimaryTarget();
		// if we're right in their gunsights, dodge!
		// need to dodge sooner if in aft sights
		if (aspect > 0.99999 || aspect < -0.999) 
		{
			frustration = 0.0;
			behaviour = BEHAVIOUR_EVASIVE_ACTION;
		}
	}
	
}


void ShipEntity::behaviour_running_defense(double delta_t)
{

	if (!canStillTrackPrimaryTarget())
	{
		noteLostTargetAndGoIdle();
		return;
	}

	double  range = rangeToPrimaryTarget();
	desired_speed = maxFlightSpeed; // not injectors
	jink = kZeroVector;
	if (range > weaponRange || range > 0.8 * scannerRange || range == 0)
	{
		behaviour = BEHAVIOUR_CLOSE_WITH_TARGET;
		if ((forward_weapon_type != nullptr ? forward_weapon_type->isTurretLaser() : false)) 
		{
				behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE;
		} 
		frustration = 0.0;
	}
	trackPrimaryTarget(delta_t, YES);
	if ((forward_weapon_type != nullptr ? forward_weapon_type->isTurretLaser() : false)) 
	{
		// most Thargoids will only have the forward weapon
		fireMainWeapon(range);
	}
	else 
	{
		fireAftWeapon(range);
	}
	if (cloakAutomatic) activateCloakingDevice();
	if (hasProximityAlertIgnoringTarget(YES))
		avoidCollision();

	if (behaviour != BEHAVIOUR_CLOSE_WITH_TARGET && weapon_temp > COMBAT_AI_WEAPON_TEMP_USABLE)
	{
		behaviour = BEHAVIOUR_ATTACK_TARGET;
	}

	// remember to look where you're going?
	if (accuracy >= COMBAT_AI_ISNT_AWFUL && hasProximityAlertIgnoringTarget(YES))
	{
		avoidCollision();
	}


}


void ShipEntity::behaviour_flee_target(double delta_t)
{

	BOOL	canBurn = hasFuelInjection() && (fuel > MIN_FUEL);
	float	max_available_speed = maxFlightSpeed;
	double  range = rangeToPrimaryTarget();
	if (primaryTarget() == nil)
	{
		noteLostTargetAndGoIdle();
		return;
	}
	if (canBurn) max_available_speed *= afterburnerFactor();
	
	double last_range = success_factor;
	success_factor = range;

	if (range > desired_range || range == 0)
		{ if (shipAI != nullptr)  shipAI->message("REACHED_SAFETY"); }
	else
		desired_speed = max_available_speed;

	if (range > last_range)	// improvement
	{
		frustration -= 0.25 * delta_t;
		if (frustration < 0.0)
			frustration = 0.0;
	}
	else
	{
		frustration += delta_t;
		if (frustration > 15.0)	// 15s of frustration
		{
			noteFrustration("BEHAVIOUR_FLEE_TARGET");
			frustration = 0.0;
		}
	}

	trackPrimaryTarget(delta_t, YES);

	Entity *target = primaryTarget();

	if (missiles && oo::EntityIsShip(target) && (oo::ToShip(target) != nullptr ? oo::ToShip(target)->primaryTarget() : (Entity *)nullptr) == this)
	{
		considerFiringMissile(delta_t);
	}

	if ((hasCascadeMine()) && (range < 10000.0) && canBurn)
	{
		float	qbomb_chance = 0.01 * delta_t;
		if (randf() < qbomb_chance)
		{
			launchCascadeMine();
		}
	}

// thargoids won't normally be fleeing, but if they do, they can still shoot
	if ((forward_weapon_type != nullptr ? forward_weapon_type->isTurretLaser() : false))
	{
		fireMainWeapon(range);
	}

	if (cloakAutomatic) activateCloakingDevice();

	// remember to look where you're going?
	if (accuracy >= COMBAT_AI_ISNT_AWFUL && hasProximityAlertIgnoringTarget(YES))
	{
		avoidCollision();
	}

}


void ShipEntity::behaviour_fly_range_from_destination(double /*delta_t*/)
{

	double distance = rangeToDestination();
	if (distance < desired_range)
	{
		behaviour = BEHAVIOUR_FLY_FROM_DESTINATION;
		if (desired_speed < maxFlightSpeed) 
		{
			desired_speed = maxFlightSpeed;  // Not all AI define speed when flying away. Start with max speed to stay compatible with such AI's, but allow faster flight if it's (e.g.) used to flee from coordinates rather than entity
		}
	}
	else
	{
		behaviour = BEHAVIOUR_FLY_TO_DESTINATION;
	}
	if (hasProximityAlertIgnoringTarget(YES))
	{
		avoidCollision();
	}
	frustration = 0.0;

	
}


void ShipEntity::behaviour_face_destination(double delta_t)
{

	double max_cos = MAX_COS;
	double distance = rangeToDestination();
	double old_pitch = flightPitch;
	desired_speed = 0.0;
	if (desired_range > 1.0 && distance > desired_range)
	{
		max_cos = sqrt(1 - 0.90 * desired_range*desired_range/(distance * distance));   // Head for a point within 95% of desired_range (must match the value in trackDestination)
	}
	double confidenceFactor = trackDestination(delta_t, NO);
	if (confidenceFactor >= max_cos && flightPitch == 0.0)
	{
		// desired facing achieved and movement stabilised.
		if (shipAI != nullptr)  shipAI->message("FACING_DESTINATION");
		doScriptEvent(OOJSID("shipNowFacingDestination"));
		frustration = 0.0;
		if(docking_match_rotation)  // IDLE stops rotating while docking
		{
			behaviour = BEHAVIOUR_FLY_TO_DESTINATION;
		}
		else
		{
			behaviour = BEHAVIOUR_IDLE;
		}
	}

	if(flightSpeed == 0) frustration += delta_t;
	if (frustration > 15.0 / max_flight_pitch)	// allow more time for slow ships.
	{
		frustration = 0.0;
		noteFrustration("BEHAVIOUR_FACE_DESTINATION");
		if(flightPitch == old_pitch) flightPitch = 0.5 * max_flight_pitch; // hack to get out of frustration.
	}	
	
	/* 2009-7-18 Eric: the condition check below is intended to eliminate the flippering between two positions for fast turning ships
	   during low FPS conditions. This flippering is particular frustrating on slow computers during docking. But with my current computer I can't
	   induce those low FPS conditions so I can't properly test if it helps.
	   I did try with the TAF time acceleration that also generated larger frame jumps and than it seemed to help.
	*/
	if(flightSpeed == 0 && frustration > 5 && confidenceFactor > 0.5 && ((flightPitch > 0 && old_pitch < 0) || (flightPitch < 0 && old_pitch > 0)))
	{
		flightPitch += 0.5 * old_pitch; // damping with last pitch value.
	}
	
	if (hasProximityAlertIgnoringTarget(YES))
	{
		avoidCollision();
	}
	
	
}


void ShipEntity::behaviour_land_on_planet(double delta_t)
{

	double max_cos = MAX_COS2; // trackDestination returns the squared confidence in reverse mode.
	desired_speed = 0.0;
	
	::OOPlanetEntity* planet = dynamic_cast<::OOPlanetEntity *>((UNIVERSE != nullptr ? UNIVERSE->entityForUniversalID(planetForLanding) : nullptr));	// null for any other entity, whose -isPlanet was NO (C++ since bead oo-9ht.129)
	
	if (!(planet != nullptr ? planet->isPlanet() : false)) 
	{
		behaviour = BEHAVIOUR_IDLE;
		aiScriptWakeTime = 1; // reconsider JSAI
		if (shipAI != nullptr)  shipAI->message("NO_PLANET_NEARBY");
		return;
	}
		  
	if (HPdistance(position, (planet != nullptr ? planet->getPosition() : HPVector{})) + collisionRadius() < (planet != nullptr ? planet->radius() : 0.0))
	{
		// we have landed. (completely disappeared inside planet)
		landOnPlanet(planet);
		return;
	}

	double confidenceFactor = trackDestination(delta_t, YES); // turn away from destination
	
	if (confidenceFactor >= max_cos && flightSpeed == 0.0)
	{
		// We are now turned away from planet. Start landing by flying backward.
		thrust = 0.0; // stop forward acceleration.
		if (magnitude2(velocity) < MAX_LANDING_SPEED2)
		{
			adjustVelocity(vector_multiply_scalar(forwardVector(), -max_thrust * delta_t));
		}
	}
	
	
	if (hasProximityAlertIgnoringTarget(YES))
	{
		avoidCollision();
	}
	
	
}


void ShipEntity::behaviour_formation_form_up(double delta_t)
{

	// destination for each escort is set in update() from owner.
	::ShipEntity* leadShip = oo::ToShip(owner());
	double distance = rangeToDestination();
	double eta = (distance - desired_range) / flightSpeed;
	if(eta < 0) eta = 0;
	if ((eta < 5.0)&&(leadShip)&&(leadShip->isShip))
		desired_speed = (leadShip != nullptr ? leadShip->getFlightSpeed() : 0.0f) * (1 + eta * 0.05);
	else
		desired_speed = maxFlightSpeed;

	double last_distance = success_factor;
	success_factor = distance;

	// do the actual piloting!!
	trackDestination(delta_t,  NO);

	eta = eta / 0.51;	// 2% safety margin assuming an average of half current speed
	GLfloat slowdownTime = (thrust > 0.0)? flightSpeed / (thrust) : 4.0;
	GLfloat minTurnSpeedFactor = 0.05 * max_flight_pitch * max_flight_roll;	// faster turning implies higher speeds

	if ((eta < slowdownTime)&&(flightSpeed > maxFlightSpeed * minTurnSpeedFactor))
		desired_speed = flightSpeed * 0.50;   // cut speed by 50% to a minimum minTurnSpeedFactor of speed
		
	if (distance < last_distance)	// improvement
	{
		frustration -= 0.25 * delta_t;
		if (frustration < 0.0)
			frustration = 0.0;
	}
	else
	{
		frustration += delta_t;
		if (frustration > 15.0)
		{
			if (!leadShip) noteFrustration("BEHAVIOUR_FORMATION_FORM_UP"); // escorts never reach their destination when following leader.
			else if (distance > 0.5 * scannerRange && !pitching_over) 
			{
				pitching_over = YES; // Force the ship in a 180 degree turn. Do it here to allow escorts to break out formation for some seconds.
			}
			frustration = 0;
		}
	}
	if (hasProximityAlertIgnoringTarget(YES))
	{
		avoidCollision();
	}
	
	
}




// Slice 15 of docs/phases/3-slices/ShipEntity.md (bead oo-x4qqv): behaviours: fly to / from
// destination, avoid collision, turret, navpoints, scripted AI; reaction time. Members of the C++
// ship, called directly, since bead oo-9ht.144 deleted the facade (ADR-0056 amendment oo-9ht.144).

void ShipEntity::behaviour_fly_to_destination(double delta_t)
{

	double distance = rangeToDestination();
	// double desiredRange = (dockingInstructions != nil) ? 1.2 * desired_range : desired_range; // stop a bit earlyer when docking.
	if (distance < desired_range) // + collision_radius)
	{
		// desired range achieved
		if (shipAI != nullptr)  shipAI->message("DESIRED_RANGE_ACHIEVED");
		doScriptEvent(OOJSID("shipAchievedDesiredRange"));

		if(!docking_match_rotation) // IDLE stops rotating while docking
		{
			behaviour = BEHAVIOUR_IDLE;
			desired_speed = 0.0;
		}
		frustration = 0.0;
	}
	else
	{
		double last_distance = success_factor;
		success_factor = distance;

		// do the actual piloting!!
		double confidenceFactor = trackDestination(delta_t,  NO);
		if(confidenceFactor < 0.2) confidenceFactor = 0.2;  // don't allow small or negative values.
		
		/*	2009-07-19 Eric: Estimated Time of Arrival (eta) should also take the "angle to target" into account (confidenceFactor = cos(angle to target))
			and should not fuss about that last meter and use "distance + 1" instead of just "distance".
			trackDestination already did pitch regulation, use confidence here only for cutting down to high speeds.
			This should prevent ships crawling to their destination when they try to pull up close to their destination.
			
			To prevent ships circling around their target without reaching destination I added a limitation based on turnrate,
			speed and distance to target. Formula based on satelite orbit:
					orbitspeed = turnrate (rad/sec) * radius (m)   or   flightSpeed = max_flight_pitch * 2 Pi * distance
			Speed must be significant lower when not flying in direction of target (low confidenceFactor) or it can never approach its destination 
			and the ships runs the risk flying in circles around the target. (exclude active escorts)
		*/
		GLfloat eta = ((distance + 1) - desired_range) / (0.51 * flightSpeed * confidenceFactor);	// 2% safety margin assuming an average of half current speed
		GLfloat slowdownTime = (thrust > 0.0)? flightSpeed / (thrust) : 4.0;
		GLfloat minTurnSpeedFactor = 0.05 * max_flight_pitch * max_flight_roll;	// faster turning implies higher speeds
		if (!dockingInstructions.isNull())
		{
			minTurnSpeedFactor /= 10.0;
			if (minTurnSpeedFactor * maxFlightSpeed > 20.0)
			{
				minTurnSpeedFactor /= 10.0;
			}
		}


		if (((eta < slowdownTime)&&(flightSpeed > maxFlightSpeed * minTurnSpeedFactor)) || (flightSpeed > max_flight_pitch * 5 * confidenceFactor * distance))
		{
			desired_speed = flightSpeed * 0.50;   // cut speed by 50% to a minimum minTurnSpeedFactor of speed
		}

		/* Flight correction block to prevent one possible form of
		 * crashes in late docking process */
		if (docking_match_rotation && confidenceFactor >= MAX_COS && !dockingInstructions.isNull() && dockingInstructions.get<int>("docking_stage") >= 7)
		{
			// then at this point should be rotating to match the station
			::StationEntity* station_for_docking = oo::ToStation(targetStation());

			if ((station_for_docking)&&(station_for_docking->isStation))
			{
				float rollMatch = dot_product((station_for_docking != nullptr ? station_for_docking->portUpVectorForShip(this) : Vector{}),upVector());
				if (rollMatch < MAX_COS && rollMatch > -MAX_COS)
				{
					// not matching rotating - stop until corrected
					desired_speed = 0.1;
				}
				else if (desired_speed <= 0.2)
				{
					// had previously paused, so return to normal speed
					desired_speed = dockingInstructions.get<float>("speed");
				}
			}
		}


		if (distance < last_distance)	// improvement
		{
			frustration -= 0.25 * delta_t;
			if (frustration < 0.0)
				frustration = 0.0;
		}
		else
		{
			frustration += delta_t;
			if ((frustration > slowdownTime * 10.0 && slowdownTime > 0)||(frustration > 15.0))	// 10x slowdownTime or 15s of frustration
			{
				noteFrustration("BEHAVIOUR_FLY_TO_DESTINATION");
				frustration -= slowdownTime * 5.0;	//repeat after another five units of frustration
			}
		}
	}
	if (hasProximityAlertIgnoringTarget(YES))
	{
		avoidCollision();
	}
	
	
}


void ShipEntity::behaviour_fly_from_destination(double delta_t)
{

	double distance = rangeToDestination();
	if (distance > desired_range)
	{
		// desired range achieved
		if (shipAI != nullptr)  shipAI->message("DESIRED_RANGE_ACHIEVED");
		doScriptEvent(OOJSID("shipAchievedDesiredRange"));

		behaviour = BEHAVIOUR_IDLE;
		frustration = 0.0;
		desired_speed = 0.0;
	}

	trackDestination(delta_t, YES);
	if (hasProximityAlertIgnoringTarget(YES))
	{
		avoidCollision();
	}
	
	
}


void ShipEntity::behaviour_avoid_collision(double delta_t)
{

	double distance = rangeToDestination();
	if (distance > desired_range)
	{
		resumePostProximityAlert();
	}
	else
	{
		::ShipEntity* prox_ship = oo::ToShip(proximityAlert());
		if (prox_ship)
		{
			desired_range = prox_ship->collision_radius * PROXIMITY_AVOID_DISTANCE_FACTOR;
			_destination = prox_ship->position;
		}
		double dq = trackDestination(delta_t, YES); // returns 0 when heading towards prox_ship
		// Heading towards target with desired_speed > 0, avoids collisions better than setting desired_speed to zero.
		// (tested with boa class cruiser on collisioncourse with buoy)
		desired_speed = maxFlightSpeed * (0.5 * dq + 0.5);
	}

	
}


void ShipEntity::behaviour_track_as_turret(double delta_t)
{

	double aim = -2.0;
	::ShipEntity *turret_owner = oo::ToShip(owner());
	::ShipEntity *turret_target = oo::ToShip((turret_owner != nullptr ? turret_owner->primaryTarget() : (Entity *)nullptr));
	if (turret_owner && turret_target && (turret_owner != nullptr ? turret_owner->hasHostileTarget() : false))
	{
		aim = ballTrackLeadingTarget(delta_t, turret_target);
		if (aim > -1.0) // potential target
		{
			HPVector p = HPvector_subtract((turret_target != nullptr ? turret_target->getPosition() : HPVector{}), (turret_owner != nullptr ? turret_owner->getPosition() : HPVector{}));
			double cr = (turret_owner != nullptr ? turret_owner->collisionRadius() : 0.0f);
			
			if (aim > .95)
			{
				fireTurretCannon(HPmagnitude(p) - cr);
			}
			return;
		}
	}
	
	// can't fire on primary target; track secondary targets instead
	for (const auto &targetRef : (turret_owner != nullptr ? turret_owner->defenseTargets() : std::vector<oo::EntityHold>()))
	{
		Entity *target = targetRef.get();	// the snapshot keeps its object (bead oo-9ht.39.16)
		// defense targets cannot be tracked while cloaked
		if (target->getScanClass() == CLASS_NO_DRAW || (oo::ToShip(target) != nullptr ? oo::ToShip(target)->isCloaked() : false) || target->getEnergy() <= 0.0)
		{
			if (turret_owner != nullptr)  turret_owner->removeDefenseTarget(target);
		}
		else 
		{
			double range = (turret_owner != nullptr ? turret_owner->rangeToSecondaryTarget(target) : 0.0);
			if (range < weaponRange)
			{
				aim = ballTrackLeadingTarget(delta_t, target);
				if (aim > -1.0)
				{ // tracking...
					HPVector p = HPvector_subtract(target->getPosition(), (turret_owner != nullptr ? turret_owner->getPosition() : HPVector{}));
					double cr = (turret_owner != nullptr ? turret_owner->collisionRadius() : 0.0f);
		
					if (aim > .95)
					{ // fire!
						fireTurretCannon(HPmagnitude(p) - cr);
					}
					return;
				}
				// else that target is out of range, try the next priority defense target
			}
			else if (range > scannerRange)
			{
				if (turret_owner != nullptr)  turret_owner->removeDefenseTarget(target);
			}
		}
	}

	// turrets now don't return to neutral facing if no suitable target
	// better for shooting at targets that are on edge of fire arc
}


void ShipEntity::behaviour_fly_thru_navpoints(double delta_t)
{

	int navpoint_plus_index = (next_navpoint_index + 1) % number_of_navpoints;
	HPVector d1 = navpoints[next_navpoint_index];		// head for this one
	HPVector d2 = navpoints[navpoint_plus_index];	// but be facing this one
	
	HPVector rel = HPvector_between(d1, position);	// vector from d1 to position 
	HPVector ref = HPvector_between(d2, d1);		// vector from d2 to d1
	ref = HPvector_normal(ref);
	
	HPVector xp = make_HPvector(ref.y * rel.z - ref.z * rel.y, ref.z * rel.x - ref.x * rel.z, ref.x * rel.y - ref.y * rel.x);	
	
	GLfloat v0 = 0.0;
	
	GLfloat	r0 = HPdot_product(rel, ref);	// proportion of rel in direction ref
	
	// if r0 is negative then we're the wrong side of things
	
	GLfloat	r1 = HPmagnitude(xp);	// distance of position from line
	
	BOOL in_cone = (r0 > 0.5 * r1);
	
	if (!in_cone)	// are we in the approach cone ?
		r1 = 25.0 * flightSpeed;	// aim a few km out!
	else
		r1 *= 2.0;
	
	GLfloat dist2 = HPmagnitude2(rel);
	
	if (dist2 < desired_range * desired_range)
	{
		// desired range achieved
		doScriptEvent(OOJSID("shipReachedNavPoint"), "NAVPOINT_REACHED");
		if (navpoint_plus_index == 0)
		{
			doScriptEvent(OOJSID("shipReachedEndPoint"), "ENDPOINT_REACHED");
			behaviour = BEHAVIOUR_IDLE;
		}
		next_navpoint_index = navpoint_plus_index;	// loop as required
	}
	else
	{
		double last_success_factor = success_factor;
		double last_dist2 = last_success_factor;
		success_factor = dist2;

		// set destination spline point from r1 and ref
		_destination = make_HPvector(d1.x + r1 * ref.x, d1.y + r1 * ref.y, d1.z + r1 * ref.z);

		// do the actual piloting!!
		//
		// aim to within 1m
		GLfloat temp = desired_range;
		if (in_cone)
			desired_range = 1.0;
		else
			desired_range = 100.0;
		v0 = trackDestination(delta_t,  NO);
		desired_range = temp;
		
		if (dist2 < last_dist2)	// improvement
		{
			frustration -= 0.25 * delta_t;
			if (frustration < 0.0)
				frustration = 0.0;
		}
		else
		{
			frustration += delta_t;
			if (frustration > 15.0)	// 15s of frustration
			{
				noteFrustration("BEHAVIOUR_FLY_THRU_NAVPOINTS");
				frustration -= 15.0;	//repeat after another 15s of frustration
			}
		}
	}
	

	GLfloat temp = desired_speed;
	desired_speed *= v0 * v0;
	
	desired_speed = temp;
}


void ShipEntity::behaviour_scripted_ai(double delta_t)
{

	ooscript::Context context = OOJSAcquireContext();
	ooscript::Value		rval = ooscript::undefinedValue();
	ooscript::Value		deltaJS = ooscript::undefinedValue();
	oo::PList result;
	
	BOOL OK = ooscript::newNumberValue(context, delta_t, &deltaJS);
	if (OK)
	{
		OK = (getScript() != nullptr ? getScript()->callMethod(OOJSID("scriptedAI"), context, &deltaJS, 1, &rval) : false);
	}
	
	if (!OK)
	{
		OO_LOG("ai.error", "Could not call scriptedAI in ship script of {}, reverting to idle", oo::EntityDescription(this));
		behaviour = BEHAVIOUR_IDLE;
		OOJSRelinquishContext(context);
		return;
	}

	if (!ooscript::isObjectOrNull(rval))
	{
		OO_LOG("ai.error", "Invalid return value of scriptedAI in ship script of {}, reverting to idle", oo::EntityDescription(this));
		behaviour = BEHAVIOUR_IDLE;
		OOJSRelinquishContext(context);
		return;
	}

	result = cxx_OOJSPListFromJSObject(context, ooscript::toObject(rval));
	OOJSRelinquishContext(context);

	// roll or roll factor
	if (result.find("stickRollFactor") != nullptr)
	{
		stick_roll = result.get<float>("stickRollFactor") * max_flight_roll;
	} 
	else 
	{
		stick_roll = result.get<float>("stickRoll");
	}
	if (stick_roll > max_flight_roll) 
	{
		stick_roll = max_flight_roll;
	}
	else if (stick_roll < -max_flight_roll)
	{
		stick_roll = -max_flight_roll;
	}

	// pitch or pitch factor
	if (result.find("stickPitchFactor") != nullptr)
	{
		stick_pitch = result.get<float>("stickPitchFactor") * max_flight_pitch;
	} 
	else 
	{
		stick_pitch = result.get<float>("stickPitch");
	}
	if (stick_pitch > max_flight_pitch) 
	{
		stick_pitch = max_flight_pitch;
	}
	else if (stick_pitch < -max_flight_pitch)
	{
		stick_pitch = -max_flight_pitch;
	}

	// yaw or yaw factor
	if (result.find("stickYawFactor") != nullptr)
	{
		stick_yaw = result.get<float>("stickYawFactor") * max_flight_yaw;
	} 
	else 
	{
		stick_yaw = result.get<float>("stickYaw");
	}
	if (stick_yaw > max_flight_yaw) 
	{
		stick_yaw = max_flight_yaw;
	}
	else if (stick_yaw < -max_flight_yaw)
	{
		stick_yaw = -max_flight_yaw;
	}	

	// apply sticks to current flight profile
	applySticks(delta_t);

	// desired speed
	if (result.find("desiredSpeedFactor") != nullptr)
	{
		desired_speed = result.get<float>("desiredSpeedFactor") * maxFlightSpeed;
	}
	else
	{
		desired_speed = result.get<float>("desiredSpeed");
	}

	if (desired_speed < 0.0)
	{
		desired_speed = 0.0;
	}
	// overspeed and injector use is handled by applyThrust

	if (behaviour == BEHAVIOUR_SCRIPTED_ATTACK_AI)
	{
		const std::string chosen_weapon = result.get<std::string>("chosenWeapon", "FORWARD");
		double  range = rangeToPrimaryTarget();

		if (chosen_weapon == "FORWARD")
		{
			fireMainWeapon(range);
		}
		else if (chosen_weapon == "AFT")
		{
			fireAftWeapon(range);
		}
		else if (chosen_weapon == "PORT")
		{
			firePortWeapon(range);
		}
		else if (chosen_weapon == "STARBOARD")
		{
			fireStarboardWeapon(range);
		}
	}
}


float ShipEntity::getReactionTime()
{
	return reactionTime;
}


void ShipEntity::setReactionTime(float newReactionTime)
{
	reactionTime = newReactionTime;
}


HPVector ShipEntity::calculateTargetPosition()
{

	Entity *target = primaryTarget();
	if (target == nil)
	{
		return kZeroHPVector;
	}
	if (reactionTime <= 0.0)
	{
		return (target != nullptr ? target->getPosition() : kZeroHPVector);
	}
	double t = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) - trackingCurveTimes[1];
	return HPvector_add(HPvector_add(trackingCurveCoeffs[0], HPvector_multiply_scalar(trackingCurveCoeffs[1],t)), HPvector_multiply_scalar(trackingCurveCoeffs[2],t*t));
}




// Slice 16 of docs/phases/3-slices/ShipEntity.md (bead oo-d96oe): tracking curve, drawing, scanner
// colours, cloaking, subentities and owner, thrust. Members of the C++ ship, called directly, since
// bead oo-9ht.144 deleted the facade (ADR-0056 amendment oo-9ht.144).

void ShipEntity::startTrackingCurve()
{

	Entity *target = primaryTarget();
	if (target == nil)
	{
		return;
	}
	OOTimeAbsolute now = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0);
	trackingCurvePositions[0] = (target != nullptr ? target->getPosition() : kZeroHPVector);
	trackingCurvePositions[1] = (target != nullptr ? target->getPosition() : kZeroHPVector);
	trackingCurvePositions[2] = (target != nullptr ? target->getPosition() : kZeroHPVector);
	trackingCurvePositions[3] = (target != nullptr ? target->getPosition() : kZeroHPVector);
	trackingCurveTimes[0] = now;
	trackingCurveTimes[1] = now - reactionTime/3.0;
	trackingCurveTimes[2] = now - reactionTime*2.0/3.0;
	trackingCurveTimes[3] = now - reactionTime;
	calculateTrackingCurve();
	return;
}


void ShipEntity::updateTrackingCurve()
{

	Entity *target = primaryTarget();
	OOTimeAbsolute now = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0);
	if (target == nil || reactionTime <= 0.0 || trackingCurveTimes[0] + reactionTime/3.0 > now) return;
	trackingCurvePositions[3] = trackingCurvePositions[2];
	trackingCurvePositions[2] = trackingCurvePositions[1];
	trackingCurvePositions[1] = trackingCurvePositions[0];
	if (EXPECT_NOT(oo::EntityIsShip(target) && (oo::ToShip(target) != nullptr ? oo::ToShip(target)->isCloaked() : false)))
	{
		// if target is cloaked, introduce some more inaccuracy
		// 0.02 seems to be enough to give them slight difficulty on
		// a straight-line target and real trouble on anything better
		trackingCurvePositions[0] = HPvector_add((target != nullptr ? target->getPosition() : kZeroHPVector),OOHPVectorRandomSpatial((oo::ToShip(target) != nullptr ? oo::ToShip(target)->getFlightSpeed() : 0.0f)*reactionTime*0.02));
	}
	else
	{
		trackingCurvePositions[0] = (target != nullptr ? target->getPosition() : kZeroHPVector);
	}
	trackingCurveTimes[3] = trackingCurveTimes[2];
	trackingCurveTimes[2] = trackingCurveTimes[1];
	trackingCurveTimes[1] = trackingCurveTimes[0];
	trackingCurveTimes[0] = now;
	calculateTrackingCurve();
	return;
}


void ShipEntity::calculateTrackingCurve()
{
	if (reactionTime <= 0.0)
	{
		trackingCurveCoeffs[0] = trackingCurvePositions[0];
		trackingCurveCoeffs[1] = kZeroHPVector;
		trackingCurveCoeffs[2] = kZeroHPVector;
		return;
	}
	double	t1 = trackingCurveTimes[2] - trackingCurveTimes[1],
		t2 = trackingCurveTimes[3] - trackingCurveTimes[1];
	trackingCurveCoeffs[0] = trackingCurvePositions[1];
	trackingCurveCoeffs[1] = HPvector_add(HPvector_add(
		HPvector_multiply_scalar(trackingCurvePositions[1], -(t1+t2)/(t1*t2)),
		HPvector_multiply_scalar(trackingCurvePositions[2], -t2/(t1*(t1-t2)))),
		HPvector_multiply_scalar(trackingCurvePositions[3], t1/(t2*(t1-t2))));
	trackingCurveCoeffs[2] = HPvector_add(HPvector_add(
		HPvector_multiply_scalar(trackingCurvePositions[1], 1/(t1*t2)),
		HPvector_multiply_scalar(trackingCurvePositions[2], 1/(t1*(t1-t2)))),
		HPvector_multiply_scalar(trackingCurvePositions[3], -1/(t2*(t1-t2))));
	return;
}


void ShipEntity::drawImmediate(bool immediate, bool translucent)
{

	if ((no_draw_distance < cam_zero_distance) ||	// Done redundantly to skip subentities
		(cloaking_device_active && randf() > 0.10))
	{
		// Don't draw.
		return;
	}
	
	// Draw self.
	OOEntityWithDrawable::drawImmediate(immediate, translucent);
	
#ifndef NDEBUG
	// Draw bounding boxes if we have to before going for the subentities.
	// TODO: the translucent flag here makes very little sense. Something's wrong with the matrices.
	if (translucent)  drawDebugStuff();
	else if (gDebugFlags & DEBUG_BOUNDING_BOXES && !getIsSubEntity())
	{
		OODebugDrawBoundingBox(getBoundingBox());
		OODebugDrawColoredBoundingBox(totalBoundingBox, OOColor::purpleColor().get());
	}
#endif
	
	// Draw subentities.
	if (!immediate)	// TODO: is this relevant any longer?
	{
		// save time by not copying the subentity array if it's empty - CIM
		if (subEntityCount() > 0) 
		{ 
			const std::vector<oo::EntityHold> subs = subEntities;	// a snapshot, as -subEntities copied
			for (const auto &sub : subs)
			{
				Entity *subEntity = sub.get();
				OOCAssert((subEntity != nullptr ? subEntity->owner() : nullptr) == oo::WithObject(this), "Subentity ownership broke - %s should be owned by %s but is owned by %s.", oo::EntityDescription(subEntity).c_str(), oo::EntityDescription(this).c_str(), oo::EntityDescription(subEntity != nullptr ? subEntity->owner() : nullptr).c_str());
				if (cxx::OOSubEntityInterface *cxxSub = dynamic_cast<cxx::OOSubEntityInterface *>(subEntity))  cxxSub->drawSubEntityImmediate(immediate, translucent);
				// (else: nothing - the root's category drew only a ship's or an effect's part, which adopt the interface; bead oo-dpyk8)
			}
		}
	}
}


#ifndef NDEBUG
void ShipEntity::drawDebugStuff()
{

	// HPVect: imprecise here - needs camera relative
	if (0 && reportAIMessages)
	{
		OODebugDrawPoint(HPVectorToVector(_destination), OOColor::blueColor().get());
		OODebugDrawColoredLine(HPVectorToVector(getPosition()), HPVectorToVector(_destination), OOColor::colorWithWhite(0.15, 1.0).get());
		
		Entity *pTarget = primaryTarget();
		if (pTarget != nil)
		{
			OODebugDrawPoint(HPVectorToVector((pTarget != nullptr ? pTarget->getPosition() : kZeroHPVector)), OOColor::redColor().get());
			OODebugDrawColoredLine(HPVectorToVector(getPosition()), HPVectorToVector((pTarget != nullptr ? pTarget->getPosition() : kZeroHPVector)), OOColor::colorWithRed(0.2, 0.0, 0.0, 1.0).get());
		}
		
		Entity *sTarget = targetStation();
		if (sTarget != pTarget && (sTarget != nullptr && sTarget->getIsStation()))
		{
			OODebugDrawPoint(HPVectorToVector((sTarget != nullptr ? sTarget->getPosition() : kZeroHPVector)), OOColor::cyanColor().get());
		}
		
		Entity *fTarget = foundTarget();
		if (fTarget != nil && fTarget != pTarget && fTarget != sTarget)
		{
			OODebugDrawPoint(HPVectorToVector((fTarget != nullptr ? fTarget->getPosition() : kZeroHPVector)), OOColor::magentaColor().get());
		}
	}
}
#endif


void ShipEntity::drawSubEntityImmediate(bool immediate, bool translucent)
{

	OOVerifyOpenGLState();
	
	if (cam_zero_distance > no_draw_distance) // this test provides an opportunity to do simple LoD culling
	{
		return; // TOO FAR AWAY
	}
	OOGLPushModelView();
	
	// HPVect: need to make camera-relative
	OOGLTranslateModelView(HPVectorToVector(position));
	OOGLMultModelView(rotMatrix);
	drawImmediate(immediate, translucent);
	
#ifndef NDEBUG
	if (gDebugFlags & DEBUG_BOUNDING_BOXES)
	{
		OODebugDrawBoundingBox(getBoundingBox());
	}
#endif
	
	OOGLPopModelView();
	
	OOVerifyOpenGLState();	
}


GLfloat *ShipEntity::scannerDisplayColorForShip(::ShipEntity *otherShip, bool isHostile, bool flash, ::OOColor *scannerDisplayColor1, ::OOColor *scannerDisplayColor2, ::OOColor *scannerDisplayColorH1, ::OOColor *scannerDisplayColorH2)
{

	if (isHostile)
	{
		/* if there are any scripted scanner hostile display colours
		 * for the ship, use them - otherwise fall through to the
		 * normal scripted colours, then the scan class colours */
		if (scannerDisplayColorH1 || scannerDisplayColorH2)
		{
			if (scannerDisplayColorH1 && !scannerDisplayColorH2)
			{
				scannerDisplayColorH1->getRed(&scripted_color[0], &scripted_color[1], &scripted_color[2], &scripted_color[3]);
			}
		
			if (!scannerDisplayColorH1 && scannerDisplayColorH2)
			{
				scannerDisplayColorH2->getRed(&scripted_color[0], &scripted_color[1], &scripted_color[2], &scripted_color[3]);
			}
		
			if (scannerDisplayColorH1 && scannerDisplayColorH2)
			{
				if (flash)
					scannerDisplayColorH1->getRed(&scripted_color[0], &scripted_color[1], &scripted_color[2], &scripted_color[3]);
				else
					scannerDisplayColorH2->getRed(&scripted_color[0], &scripted_color[1], &scripted_color[2], &scripted_color[3]);
			}
		
			return scripted_color;
		}
	}

	// if there are any scripted scanner display colors for the ship, use them
	if (scannerDisplayColor1 || scannerDisplayColor2)
	{
		if (scannerDisplayColor1 && !scannerDisplayColor2)
		{
			scannerDisplayColor1->getRed(&scripted_color[0], &scripted_color[1], &scripted_color[2], &scripted_color[3]);
		}
		
		if (!scannerDisplayColor1 && scannerDisplayColor2)
		{
			scannerDisplayColor2->getRed(&scripted_color[0], &scripted_color[1], &scripted_color[2], &scripted_color[3]);
		}
		
		if (scannerDisplayColor1 && scannerDisplayColor2)
		{
			if (flash)
				scannerDisplayColor1->getRed(&scripted_color[0], &scripted_color[1], &scripted_color[2], &scripted_color[3]);
			else
				scannerDisplayColor2->getRed(&scripted_color[0], &scripted_color[1], &scripted_color[2], &scripted_color[3]);
		}
		
		return scripted_color;
	}

	// no scripted scanner display colors defined, proceed as per standard
	if (isJammingScanning())
	{
		if (!(otherShip != nullptr ? otherShip->hasMilitaryScannerFilter() : false))
			return jammed_color;
		else
		{
			if (flash)
				return mascem_color1;
			else
			{
				if (isHostile)
					return hostile_color;
				else
					return mascem_color2;
			}
		}
	}

	switch (scanClass)
	{
		case CLASS_ROCK :
		case CLASS_CARGO :
			return cargo_color;
		case CLASS_THARGOID :
			if (flash)
				return hostile_color;
			else
				return friendly_color;
		case CLASS_MISSILE :
			return missile_color;
		case CLASS_STATION :
			return friendly_color;
		case CLASS_BUOY :
			if (flash)
				return friendly_color;
			else
				return neutral_color;
		case CLASS_POLICE :
		case CLASS_MILITARY :
			if ((isHostile)&&(flash))
				return police_color2;
			else
				return police_color1;
		case CLASS_MINE :
			if (flash)
				return neutral_color;
			else
				return hostile_color;
		default :
			if (isHostile)
				return hostile_color;
	}
	return neutral_color;
}


void ShipEntity::setScannerDisplayColor1(::OOColor *color)
{
	if (color == nullptr)  scanner_display_color1 = OOColor::colorWithDescription(ValueForKey(shipinfoDictionary, "scanner_display_color1"));
	else  scanner_display_color1 = oo::Ref<OOColor>(color);
}


void ShipEntity::setScannerDisplayColor2(::OOColor *color)
{
	if (color == nullptr)  scanner_display_color2 = OOColor::colorWithDescription(ValueForKey(shipinfoDictionary, "scanner_display_color2"));
	else  scanner_display_color2 = oo::Ref<OOColor>(color);
}


::OOColor *ShipEntity::scannerDisplayColor1()
{
	return scanner_display_color1.get();
}


::OOColor *ShipEntity::scannerDisplayColor2()
{
	return scanner_display_color2.get();
}


void ShipEntity::setScannerDisplayColorHostile1(::OOColor *color)
{
	if (color == nullptr)  scanner_display_color_hostile1 = OOColor::colorWithDescription(ValueForKey(shipinfoDictionary, "scanner_hostile_display_color1"));
	else  scanner_display_color_hostile1 = oo::Ref<OOColor>(color);
}


void ShipEntity::setScannerDisplayColorHostile2(::OOColor *color)
{
	if (color == nullptr)  scanner_display_color_hostile2 = OOColor::colorWithDescription(ValueForKey(shipinfoDictionary, "scanner_hostile_display_color2"));
	else  scanner_display_color_hostile2 = oo::Ref<OOColor>(color);
}


::OOColor *ShipEntity::scannerDisplayColorHostile1()
{
	return scanner_display_color_hostile1.get();
}


::OOColor *ShipEntity::scannerDisplayColorHostile2()
{
	return scanner_display_color_hostile2.get();
}


bool ShipEntity::isCloaked()
{
	return cloaking_device_active;
}


bool ShipEntity::getCloakPassive()
{
	return cloakPassive;
}


void ShipEntity::setCloaked(bool cloak)
{

	if (cloak)  activateCloakingDevice();
	else  deactivateCloakingDevice();
}


bool ShipEntity::hasAutoCloak()
{
	return cloakAutomatic;
}


void ShipEntity::setAutoCloak(bool automatic)
{
	cloakAutomatic = !!automatic;
}


bool ShipEntity::isJammingScanning()
{

	return (hasMilitaryJammer() && military_jammer_active);
}


void ShipEntity::addSubEntity(Entity *sub)
{

	if (sub == nil)  return;
	
	sub->isSubEntity = YES;
	// Order matters - need consistent state in setOwner:. -- Ahruman 2008-04-20
	subEntities.emplace_back(sub);
	sub->setOwner(this);	// [subObject setOwner:self]
	
	addSubentityToCollisionRadius(sub);
}


void ShipEntity::setOwner(Entity *who_owns_entity)
{

	OOEntityWithDrawable::setOwner(who_owns_entity);
	
	/*	Reset shader binding target so that bind-to-super works.
		This is necessary since we don't know about the owner in
		setUpShipFromDictionary:, when the mesh is initially set up.
		-- Ahruman 2008-04-19
	*/
	if (isSubEntity)
	{
		if (OODrawable *drawable = getDrawable())  drawable->setBindingTarget(this);	// the C++ entity (bead oo-9ht.39.6)
	}
}


void ShipEntity::applyThrust(double delta_t)
{

	GLfloat dt_thrust = SHIP_THRUST_FACTOR * thrust * delta_t;
	BOOL	canBurn = hasFuelInjection() && (fuel > MIN_FUEL);
	BOOL	isUsingAfterburner = (canBurn && (flightSpeed > maxFlightSpeed) && (desired_speed >= flightSpeed));
	float	max_available_speed = maxFlightSpeed;
	if (canBurn) max_available_speed *= afterburnerFactor();
	
	if (thrust)
	{
		// If we have Newtonian (non-thrust) velocity, brake it.
		GLfloat velmag = magnitude(velocity);
		if (velmag)
		{
			GLfloat vscale = fmaxf((velmag - dt_thrust) / velmag, 0.0f);
			scale_vector(&velocity, vscale);
		}
	}

	if (behaviour == BEHAVIOUR_TUMBLE)  return;

	// check for speed
	if (desired_speed > max_available_speed)
		desired_speed = max_available_speed;

	if (flightSpeed > desired_speed)
	{
		decrease_flight_speed(dt_thrust);
		if (flightSpeed < desired_speed)   flightSpeed = desired_speed;
	}
	if (flightSpeed < desired_speed)
	{
		increase_flight_speed(dt_thrust);
		if (flightSpeed > desired_speed)   flightSpeed = desired_speed;
	}
	moveForward(delta_t*flightSpeed);

	// burn fuel at the appropriate rate
	if (isUsingAfterburner) // no fuelconsumption on slowdown
	{
		fuel_accumulator -= delta_t * afterburner_rate;
		while (fuel_accumulator < 0.0)
		{
			fuel--;
			fuel_accumulator += 1.0;
		}
	}
}


void ShipEntity::orientationChanged()
{
	OOEntityWithDrawable::orientationChanged();
	
	v_forward   = vector_forward_from_quaternion(orientation);
	v_up		= vector_up_from_quaternion(orientation);
	v_right		= vector_right_from_quaternion(orientation);
}




// Slice 17 of docs/phases/3-slices/ShipEntity.md (bead oo-6hofy): attitude, collision avoidance,
// messages, groups and escort accessors, proximity alert, names and descriptions. Members of the
// C++ ship, called directly, since bead oo-9ht.144 deleted the facade (ADR-0056 amendment
// oo-9ht.144).

void ShipEntity::applyRoll(GLfloat roll1, GLfloat climb1)
{

	Quaternion q1 = kIdentityQuaternion;

	if (!roll1 && !climb1 && !hasRotated)  return;

	if (roll1)  quaternion_rotate_about_z(&q1, -roll1);
	if (climb1)  quaternion_rotate_about_x(&q1, -climb1);

	orientation = quaternion_multiply(q1, orientation);
	orientationChanged();
}


void ShipEntity::applyRoll(GLfloat roll1, GLfloat climb1, GLfloat yaw1)
{

	if ((roll1 == 0.0)&&(climb1 == 0.0)&&(yaw1 == 0.0)&&(!hasRotated))
		return;

	Quaternion q1 = kIdentityQuaternion;

	if (roll1)
		quaternion_rotate_about_z(&q1, -roll1);
	if (climb1)
		quaternion_rotate_about_x(&q1, -climb1);
	if (yaw1)
		quaternion_rotate_about_y(&q1, -yaw1);

	orientation = quaternion_multiply(q1, orientation);
	orientationChanged();
}


void ShipEntity::applyAttitudeChanges(double delta_t)
{

	applyRoll(flightRoll*delta_t, flightPitch*delta_t, flightYaw*delta_t);
}


void ShipEntity::avoidCollision()
{

	if (scanClass == CLASS_MISSILE)
		return;						// missiles are SUPPOSED to collide!
	
	::ShipEntity* prox_ship = oo::ToShip(proximityAlert());

	if (prox_ship)
	{
		oo::PList::Dict condition;
		condition["behaviour"] = oo::PList((long)behaviour);	// as oo_setInteger: stored it
		if (primaryTarget() != nil)
		{
			// must use the weak ref here to prevent potential over-retention
			condition["primaryTarget"] = oo::EntityWeakNode(primaryTarget());	// weakly, as its object's weak reference was (bead oo-w9pi2)
		}
		condition["desired_range"] = oo::PList::singleReal(desired_range);	// floats, as oo_setFloat: stored them
		condition["desired_speed"] = oo::PList::singleReal(desired_speed);
		condition["destination"] = OOPListFromHPVector(_destination);	// as oo_setHPVector: stored it
		previousCondition = oo::PList(std::move(condition));
		
		_destination = (prox_ship != nullptr ? prox_ship->getPosition() : HPVector{});
		_destination = OOHPVectorInterpolate(position, (prox_ship != nullptr ? prox_ship->getPosition() : HPVector{}), 0.5);		// point between us and them
		
		desired_range = prox_ship->collision_radius * PROXIMITY_AVOID_DISTANCE_FACTOR;
		
		behaviour = BEHAVIOUR_AVOID_COLLISION;
		pitching_over = YES;
	}
}


void ShipEntity::resumePostProximityAlert()
{

	if (previousCondition.isNull())  return;

	behaviour =		(OOBehaviour)previousCondition.get<int>("behaviour");
	const oo::PList *previousTarget = previousCondition.find("primaryTarget");
	_primaryTarget =	oo::WeakRef<Entity>(previousTarget != nullptr ? oo::EntityInWeakNode(*previousTarget) : nullptr);	// the node holds the target weakly (bead oo-w9pi2)
	startTrackingCurve();
	desired_range =	previousCondition.get<float>("desired_range");
	desired_speed =	previousCondition.get<float>("desired_speed");
	_destination =	HPVectorForKey(previousCondition, "destination");

	previousCondition = oo::PList();
	frustration = 0.0;
	
	_proximityAlert = nullptr;
	
	//[shipAI message:@"RESTART_DOCKING"];	// if docking, start over, other AIs will ignore this message
}


double ShipEntity::getMessageTime()
{
	return messageTime;
}


void ShipEntity::setMessageTime(double value)
{
	messageTime = value;
}


::OOShipGroup *ShipEntity::group()
{
	return _group.get();
}


void ShipEntity::setGroup(::OOShipGroup *group)
{

	if (group != _group)
	{
		if (_escortGroup != _group && _group != nullptr) 
		{
			if (this == _group->leader())  _group->setLeader(nil);
			_group->removeShip(this);
		}
		if (group != nullptr)  group->addShip(this);
		_group = oo::Ref<::OOShipGroup>(group);
		
		if (group != nullptr)  { if (group->leader() != nullptr)  group->leader()->updateEscortFormation(); }
	}
}


::OOShipGroup *ShipEntity::escortGroup()
{

	if (_escortGroup == nullptr)
	{
		_escortGroup = ::OOShipGroup::groupWithName(std::string("escort group"));
		if (_escortGroup != nullptr)  _escortGroup->setLeader(this);
	}
	
	return _escortGroup.get();
}


void ShipEntity::setEscortGroup(::OOShipGroup *group)
{

	if (group != _escortGroup)
	{
		_escortGroup = oo::Ref<::OOShipGroup>(group);
		if (group != nullptr)  group->setLeader(this);	// A ship is always leader of its own escort group.
		updateEscortFormation();
	}
}


#ifndef NDEBUG
::OOShipGroup *ShipEntity::rawEscortGroup()
{
	return _escortGroup.get();
}
#endif


::OOShipGroup *ShipEntity::stationGroup()
{

	if (_group == nullptr)
	{
		_group = ::OOShipGroup::groupWithName(std::string("station group"));
		if (_group != nullptr)  _group->setLeader(this);
	}
	
	return _group.get();
}


bool ShipEntity::hasEscorts()
{
	if (_escortGroup == nullptr)  return NO;
	return _escortGroup->count() > 1;	// If only one member, it's self.
}


std::vector<oo::EntityHold> ShipEntity::escorts()
{

	std::vector<oo::EntityHold> escorts;
	if (_escortGroup == nullptr)  return escorts;
	// The group's members at this moment, in its order, without self (as -ooExcludingObject: skipped it).
	for (const oo::EntityHold &memberRef : _escortGroup->memberArray())
	{
		::ShipEntity *member = oo::ToShip(memberRef.get());
		if (member == this)  continue;
		escorts.emplace_back(member);
	}
	return escorts;
}


std::vector<oo::EntityHold> ShipEntity::escortArray()
{

	return escorts();
}


uint8_t ShipEntity::escortCount()
{
	if (_escortGroup == nullptr)  return 0;
	return _escortGroup->count() - 1;
}


uint8_t ShipEntity::pendingEscortCount()
{
	return _pendingEscortCount;
}


void ShipEntity::setPendingEscortCount(uint8_t count)
{
	_pendingEscortCount = MIN(count, _maxEscortCount);
}


uint8_t ShipEntity::maxEscortCount()
{
	return _maxEscortCount;
}


void ShipEntity::setMaxEscortCount(uint8_t newCount)
{
	_maxEscortCount = newCount;
}


NSUInteger ShipEntity::turretCount()
{

	NSUInteger count = 0;
	for (const auto &se : shipSubEntities())
	{
		if ((oo::ToShip(se.get()) != nullptr ? oo::ToShip(se.get())->isTurret() : false))
		{
			count ++; 
		}
	}
	return count;
}


// The C++ entity (bead oo-9ht.39.23.2): null, and forgotten, when its object is gone, as before.
Entity *ShipEntity::proximityAlert()
{
	Entity *prox = oo::LiveEntity(_proximityAlert);
	if (prox == nullptr)
	{
		_proximityAlert = nullptr;
		return nullptr;
	}
	return prox;
}


void ShipEntity::setProximityAlert(::ShipEntity *other)
{

	if (!other)
	{
		_proximityAlert = nullptr;
		return;
	}

	if ((other != nullptr ? other->getMass() : 0.0f) < 2000) // we are not alerted by small objects. (a cargopod has a mass of about 1000)
		return;
	

	if (isStation) // stations don't worry about colliding with things
		return; 

	/* Ignore station collision warnings if launching or docking */
	if ((other->isStation) && (status() == STATUS_LAUNCHING || 
							   !dockingInstructions.isNull()))
	{
		return; 
	}	

	if (!crew) // Ships without pilot (cargo, rocks, missiles, buoys etc) will not get alarmed. (escape-pods have pilots)
		return;
	
	// check vectors
	Vector vdiff = HPVectorToVector(HPvector_between(position, other->position));
	GLfloat d_forward = dot_product(vdiff, v_forward);
	GLfloat d_up = dot_product(vdiff, v_up);
	GLfloat d_right = dot_product(vdiff, v_right);
	if ((d_forward > 0.0)&&(flightSpeed > 0.0))	// it's ahead of us and we're moving forward
		d_forward *= 0.25 * maxFlightSpeed / flightSpeed;	// extend the collision zone forward up to 400%
	double d2 = d_forward * d_forward + d_up * d_up + d_right * d_right;
	double cr2 = collision_radius * 2.0 + other->collision_radius;	cr2 *= cr2;	// check with twice the combined radius

	if (d2 > cr2) // we're okay
	return;

	if (behaviour == BEHAVIOUR_AVOID_COLLISION)	//	already avoiding something
	{
		::ShipEntity* prox = oo::ToShip(proximityAlert());
		if ((prox)&&(prox != other))
		{
			// check which subtends the greatest angle
			GLfloat sa_prox = prox->collision_radius * prox->collision_radius / HPdistance2(position, prox->position);
			GLfloat sa_other = other->collision_radius *  other->collision_radius / HPdistance2(position, other->position);
			if (sa_prox < sa_other)  return;
		}
	}
	_proximityAlert = oo::WeakRef<Entity>(other);
}


std::optional<std::string> ShipEntity::getName()
{
	return name;
}


std::optional<std::string> ShipEntity::getShipUniqueName()
{
	return shipUniqueName;
}


std::optional<std::string> ShipEntity::getShipClassName()
{
	return shipClassName;
}


std::optional<std::string> ShipEntity::getDisplayName()
{
	if (!displayName.has_value() || displayName->empty())
	{
		if (!shipUniqueName.has_value() || shipUniqueName->empty())
		{
			if (!shipClassName.has_value())
			{
				return name;
			}
			else
			{
				return shipClassName;	// engaged here
			}
		}
		else
		{
			// %@ printed nil as (null)
			if (!shipClassName.has_value())
			{
				return oo::str::format("%s: %s", name.value_or("(null)").c_str(), shipUniqueName->c_str());
			}
			else
			{
				return oo::str::format("%s: %s", shipClassName->c_str(), shipUniqueName->c_str());
			}
		}
	}
	return displayName;	// engaged here
}


// needed so that scan_description = scan_description doesn't have odd effects
std::optional<std::string> ShipEntity::scanDescriptionForScripting()
{
	return scan_description;
}


std::optional<std::string> ShipEntity::scanDescription()
{

	if (scan_description.has_value())
	{
		return scan_description;
	}
	else
	{
		std::optional<std::string> desc;
		switch (getScanClass())
		{
		case CLASS_NEUTRAL:
			{
				int legal = legalStatus();
				int legal_i = 0;
				if (legal > 0)
				{
					legal_i =  (legal <= 50) ? 1 : 2;
				}
				// the entry if it is a string (or a number's -stringValue), else nil
				const oo::PList *legalStatusEntry = UNIVERSE->descriptions()->find("legal_status");
				const oo::PList legalStatus = (legalStatusEntry != nullptr) ? *legalStatusEntry : oo::PList();
				const oo::PList *entry = legalStatus.at(legal_i);
				if (entry != nullptr && (entry->isString() || entry->isNumber()))  desc = legalStatus.at<std::string>(legal_i);
			}
			break;

		case CLASS_THARGOID:
			desc = OO_DESC("legal-desc-alien");
			break;

		case CLASS_POLICE:
			desc = OO_DESC("legal-desc-system-vessel");
			break;

		case CLASS_MILITARY:
			desc = OO_DESC("legal-desc-military-vessel");
			break;

		default:
			break;
		}
		return desc;
	}
}


void ShipEntity::setName(const std::optional<std::string> &inName)
{
	name = inName;
}


void ShipEntity::setShipUniqueName(const std::optional<std::string> &inName)
{
	shipUniqueName = inName;
}


void ShipEntity::setShipClassName(const std::optional<std::string> &inName)
{
	shipClassName = inName;
}


void ShipEntity::setDisplayName(const std::optional<std::string> &inName)
{
	displayName = inName;
}


void ShipEntity::setScanDescription(const std::optional<std::string> &inName)
{
	scan_description = inName;
}




// Slice 18 of docs/phases/3-slices/ShipEntity.md (bead oo-vho1o): roles, ship-type predicates,
// hostility, weapon data, scanner range, aegis transition, nearest planet. Members of the C++ ship,
// called directly, since bead oo-9ht.144 deleted the facade (ADR-0056 amendment oo-9ht.144).

std::optional<std::string> ShipEntity::identFromShip(::ShipEntity *otherShip)
{

	if (isJammingScanning() && !(otherShip != nullptr ? otherShip->hasMilitaryScannerFilter() : false))
	{
		return OO_DESC("unknown-target");
	}
	return getDisplayName();
}


bool ShipEntity::hasRole(const std::string &role)
{

	if (roleSet != nullptr && roleSet->hasRole(role))  return YES;
	return role == primaryRole || role == shipDataKeyAutoRole();
}


oo::Ref<::OORoleSet> ShipEntity::getRoleSet()
{

	// A null set answers null, as the messages to a nil set did.
	if (roleSet == nullptr)  roleSet = ::OORoleSet::roleSetWithString(primaryRole.value_or(std::string()));
	if (roleSet == nullptr)  return nullptr;
	const oo::Ref<::OORoleSet> withPrimary = roleSet->roleSetWithAddedRoleIfNotSet(primaryRole.value_or(std::string()), 1.0);
	if (withPrimary == nullptr)  return nullptr;
	return withPrimary->roleSetWithAddedRoleIfNotSet(*shipDataKeyAutoRole(), 1.0);
}


void ShipEntity::addRole(const std::string &role)
{

	addRole(role, 0.0f);
}


void ShipEntity::addRole(const std::string &role, float probability)
{

	if (!hasRole(role))
	{
		oo::Ref<::OORoleSet> newRoles;
		if (roleSet != nullptr)  newRoles = roleSet->roleSetWithAddedRole(role, probability);
		else  newRoles = ::OORoleSet::roleSetWithRole(role, probability);
		if (newRoles != nullptr)
		{
			roleSet = newRoles;
		}
	}
}


void ShipEntity::removeRole(const std::string &role)
{

	if (hasRole(role))
	{
		const oo::Ref<::OORoleSet> newRoles = (roleSet != nullptr) ? roleSet->roleSetWithRemovedRole(role) : nullptr;
		if (newRoles != nullptr)
		{
			roleSet = newRoles;
		}
	}
}


std::optional<std::string> ShipEntity::getPrimaryRole()
{

	if (!primaryRole.has_value())
	{
		primaryRole = (roleSet != nullptr) ? roleSet->anyRole() : std::nullopt;
		if (!primaryRole.has_value())  primaryRole = "trader";
		OO_LOG("ship.noPrimaryRole", "{} had no primary role, randomly selected \"{}\".", getName().value_or("(null)"), primaryRole.value_or("(null)"));
	}

	return primaryRole;
}


// Exposed to AI.
void ShipEntity::setPrimaryRole(const std::string &role)
{
	primaryRole = role;
}


bool ShipEntity::hasPrimaryRole(const std::string &role)
{

	return getPrimaryRole() == role;
}


bool ShipEntity::isPolice()
{

	//bounty hunters have a police role, but are not police, so we must test by scan class, not by role
	return getScanClass() == CLASS_POLICE;
}


bool ShipEntity::isThargoid()
{

	return getScanClass() == CLASS_THARGOID;
}


bool ShipEntity::isTrader()
{

	return (UNIVERSE != nullptr ? UNIVERSE->role(getPrimaryRole().value_or(""), "oolite-trader") : false);
}


bool ShipEntity::isPirate()
{

	return (UNIVERSE != nullptr ? UNIVERSE->role(getPrimaryRole().value_or(""), "oolite-pirate") : false);
}


bool ShipEntity::getIsMissile()
{

	return (getPrimaryRole().value_or("").ends_with("MISSILE") || hasPrimaryRole("missile"));
}


bool ShipEntity::isMine()
{

	return getPrimaryRole().value_or("").ends_with("MINE");
}


bool ShipEntity::isWeapon()
{

	return getIsMissile() || isMine();
}


bool ShipEntity::isEscort()
{

	return (UNIVERSE != nullptr ? UNIVERSE->role(getPrimaryRole().value_or(""), "oolite-escort") : false);
}


bool ShipEntity::isShuttle()
{

	return (UNIVERSE != nullptr ? UNIVERSE->role(getPrimaryRole().value_or(""), "oolite-shuttle") : false);
}


bool ShipEntity::isTurret()
{
	return behaviour == BEHAVIOUR_TRACK_AS_TURRET;
}


bool ShipEntity::isPirateVictim()
{

	return (UNIVERSE != nullptr ? UNIVERSE->roleIsPirateVictim(getPrimaryRole().value_or("")) : false);
}


bool ShipEntity::isExplicitlyUnpiloted()
{
	return _explicitlyUnpiloted;
}


void ShipEntity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)
{
	::ShipEntityJSGetJSClass(outClass, outPrototype);
}


std::optional<std::string> ShipEntity::jsClassName()
{
	return ::ShipEntityJSClassName();
}


// A ship made in C++ (the player, the proxy) is visible to scripts, as its deleted facade was: the
// Objective-C PlayerEntity and ProxyPlayerEntity inherited ShipEntity's answer (bead oo-ak1km).
bool ShipEntity::isVisibleToScripts()
{
	return ::ShipEntityJSIsVisibleToScripts();
}


bool ShipEntity::isUnpiloted()
{

	return isExplicitlyUnpiloted() || getIsHulk() || getScanClass() == CLASS_ROCK || getScanClass() == CLASS_CARGO;
}


// Exposed to shaders.
bool ShipEntity::hasHostileTarget()
{

	Entity *t = primaryTarget();
	if (t == nil || !oo::EntityIsShip(t))
	{
		return NO;
	}
	if (getIsMissile())
	{
		return YES;	// missiles are always fired against a hostile target
	}
	if ((behaviour == BEHAVIOUR_AVOID_COLLISION)&&(!previousCondition.isNull()))
	{
		int old_behaviour = previousCondition.get<int>("behaviour");
		return IsBehaviourHostile((OOBehaviour)old_behaviour);
	}
	return IsBehaviourHostile(behaviour);
}


bool ShipEntity::isHostileTo(Entity *entity)
{

	return (hasHostileTarget() && primaryTarget() == entity);
}


GLfloat ShipEntity::getWeaponRange()
{
	return weaponRange;
}


void ShipEntity::setWeaponRange(GLfloat value)
{
	weaponRange = value;
}


void ShipEntity::setWeaponDataFromType(OOWeaponType weapon_type)
{

	weaponRange = getWeaponRangeFromType(weapon_type);
	weapon_energy_use = (weapon_type != nullptr ? weapon_type->weaponEnergyUse() : 0.0f);
	weapon_recharge_rate = (weapon_type != nullptr ? weapon_type->weaponRechargeRate() : 0.0f);
	weapon_shot_temperature = (weapon_type != nullptr ? weapon_type->weaponShotTemperature() : 0.0f);
	weapon_damage = (weapon_type != nullptr ? weapon_type->weaponDamage() : 0.0f);

	if (default_laser_color == nil)
	{
		oo::Ref<OOColor>	wcol = (weapon_type != nullptr ? weapon_type->weaponColor() : oo::Ref<OOColor>());
		if (wcol != nil)
		{
			setLaserColor(wcol.get());
		}
	}

}


float ShipEntity::energyRechargeRate()
{
	return energy_recharge_rate;
}


void ShipEntity::setEnergyRechargeRate(GLfloat newValue)
{
	energy_recharge_rate = newValue;
}


float ShipEntity::weaponRechargeRate()
{
	return weapon_recharge_rate;
}


void ShipEntity::setWeaponRechargeRate(float value)
{
	weapon_recharge_rate = value;
}


void ShipEntity::setWeaponEnergy(float value)
{
	weapon_damage = value;
}


OOWeaponFacing ShipEntity::getCurrentWeaponFacing()
{
	return currentWeaponFacing;
}


GLfloat ShipEntity::getScannerRange()
{
	return scannerRange;
}


void ShipEntity::setScannerRange(GLfloat value)
{
	scannerRange = value;
}


Vector ShipEntity::getReference()
{
	return reference;
}


void ShipEntity::setReference(Vector v)
{
	reference = v;
}


bool ShipEntity::getReportAIMessages()
{
	return reportAIMessages;
}


void ShipEntity::setReportAIMessages(bool yn)
{
	reportAIMessages = yn;
}


void ShipEntity::transitionToAegisNone()
{

	if (!suppressAegisMessages && aegis_status != AEGIS_NONE)
	{
		Entity *lastAegisLock = this->lastAegisLock();	// the C++ entity (bead oo-al52f)
		if (lastAegisLock != nullptr)
		{
			doScriptEvent(OOJSID("shipExitedPlanetaryVicinity"), lastAegisLock);
			
			if (lastAegisLock == (UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr))
			{
				if (shipAI != nullptr)  shipAI->message("AWAY_FROM_SUN");
			}
			else
			{
				if (shipAI != nullptr)  shipAI->message("AWAY_FROM_PLANET");
			}
		}

		if (aegis_status != AEGIS_CLOSE_TO_ANY_PLANET)
		{
			if (shipAI != nullptr)  shipAI->message("AEGIS_NONE");
		}
	}
	aegis_status = AEGIS_NONE;
}


::OOPlanetEntity *ShipEntity::findNearestPlanet()
{

	/*
		Performance note: this method is called every frame by every ship, and
		has a significant profiler presence.
		-- Ahruman 2012-09-13
	*/
	::OOPlanetEntity *planet = nil, *bestPlanet = nil;
	float bestRange = INFINITY;
	HPVector myPosition = getPosition();
	
	// valgrind complains about this line here. Might be compiler/GNUstep bug? 
	// should we go back to a traditional enumerator? - CIM
	// similar complaints about the other foreach() in this file
	for (const auto &planetRef : (UNIVERSE != nullptr ? UNIVERSE->planets() : std::vector<oo::EntityHold>()))
	{
		planet = static_cast<::OOPlanetEntity *>(planetRef.get());	// the list holds only planets (C++ since bead oo-9ht.129)
		// Ignore miniature planets.
		if ((planet != nullptr ? planet->planetType() : OOStellarBodyType{}) == STELLAR_TYPE_MINIATURE)  continue;
		
		float range = SurfaceDistanceSqaredV(myPosition, planetRef.get());
		if (range < bestRange)
		{
			bestPlanet = planet;
			bestRange = range;
		}
	}
	
	return bestPlanet;
}


Entity *ShipEntity::findNearestStellarBody()
{

	Entity *match = findNearestPlanet();	// the C++ planet and sun (bead oo-al52f)
	Entity *sun = (UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr);
	
	if (sun != nullptr)
	{
		if (match == nullptr ||
			SurfaceDistanceSqared(this, sun) < SurfaceDistanceSqared(this, match))
		{
			match = sun;
		}
	}
	
	return match;
}


::OOPlanetEntity *ShipEntity::findNearestPlanetExcludingMoons()
{

	::OOPlanetEntity		*result = nil;
	std::vector<oo::EntityHold>	planets;	// the planets, held (beads oo-9ht.39.26, oo-al52f)

	for (const auto &planet : (UNIVERSE != nullptr ? UNIVERSE->planets() : std::vector<oo::EntityHold>()))
	{
		if(OOStellarBodyPlanetType(planet.get()) == STELLAR_TYPE_NORMAL_PLANET)
					planets.push_back(planet);
	}

	if (planets.empty())  return nil;

	// ComparePlanetsBySurfaceDistance's order; the nearest comes first.
	std::stable_sort(planets.begin(), planets.end(), [this](const oo::EntityHold &a, const oo::EntityHold &b)
	{
		return ComparePlanetsBySurfaceDistance(a.get(), b.get(), this) == OOOrderedAscending;
	});
	result = static_cast<::OOPlanetEntity *>(planets[0].get());

	return result;
}




// Slice 19 of docs/phases/3-slices/ShipEntity.md (bead oo-umyg2): aegis, home and destination
// systems, status, crew, AI and ship script, fuel. Members of the C++ ship, called directly, since
// bead oo-9ht.144 deleted the facade (ADR-0056 amendment oo-9ht.144).

OOAegisStatus ShipEntity::checkForAegis()
{
	Entity			*nearest = findNearestStellarBody();	// the C++ entity (bead oo-al52f)
	BOOL					sunGoneNova = ((UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr) != nullptr ? UNIVERSE->sun()->goneNova() : false);
	
	if (nearest == nullptr)
	{
		if (aegis_status != AEGIS_NONE)
		{
			// Planet disappeared!
			transitionToAegisNone();
		}
		return AEGIS_NONE;
	}
	// check planet
	float			cr = OOStellarBodyRadius(nearest);
	float			cr2 = cr * cr;
	OOAegisStatus	result = AEGIS_NONE;
	float			d2 = HPmagnitude2(HPvector_subtract(nearest->getPosition(), getPosition()));
	// not scannerRange: aegis shouldn't depend on that
	float 		sd2 = SCANNER_MAX_RANGE2 * 10.0f;

	// check if nearing a surface
	unsigned wasNearPlanetSurface = isNearPlanetSurface;	// isNearPlanetSurface is a bit flag, not an actual BOOL
	isNearPlanetSurface = (d2 - cr2) < (250000.0f + 1000.0f * cr); //less than 500m from the surface: (a+b)*(a+b) = a*a+b*b +2*a*b


	if (EXPECT_NOT((wasNearPlanetSurface != isNearPlanetSurface) && !suppressAegisMessages))
	{
		if (isNearPlanetSurface)
		{
			doScriptEvent(OOJSID("shipApproachingPlanetSurface"), nearest);
			if (shipAI != nullptr)  shipAI->reactToMessage("APPROACHING_SURFACE", "flight update");
		}
		else
		{
			doScriptEvent(OOJSID("shipLeavingPlanetSurface"), nearest);
			if (shipAI != nullptr)  shipAI->reactToMessage("LEAVING_SURFACE", "flight update");
		}
	}
	
	// being close to the station takes precedence over planets
	::StationEntity	*the_station = (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr);
	if (the_station)
	{
		sd2 = HPmagnitude2(HPvector_subtract((the_station != nullptr ? the_station->getPosition() : HPVector{}), getPosition()));
	}
	// again, notional scanner range is intentional
	if (sd2 < SCANNER_MAX_RANGE2 * 4.0f) // double scanner range
	{
		result = AEGIS_IN_DOCKING_RANGE;
	}
	else if (EXPECT_NOT(isNearPlanetSurface || d2 < cr2 * 9.0f)) // to 3x radius of any planet/moon - or 500m of tiny ones,
	{
		result = AEGIS_CLOSE_TO_ANY_PLANET;
		if (EXPECT(nearest == (UNIVERSE != nullptr ? UNIVERSE->planet() : nullptr)))
		{
			result = AEGIS_CLOSE_TO_MAIN_PLANET;
		}
	}
	// need to do this check separately from above case to avoid oddity where
	// main planet and small moon are at just the wrong distance. - CIM
	if (result != AEGIS_CLOSE_TO_MAIN_PLANET && result != AEGIS_IN_DOCKING_RANGE && !sunGoneNova)
	{
		// are we also close to the main planet?
		::OOPlanetEntity *mainPlanet = (UNIVERSE != nullptr ? UNIVERSE->planet() : nullptr);
		d2 = HPmagnitude2(HPvector_subtract((mainPlanet != nullptr ? mainPlanet->getPosition() : HPVector{}), getPosition()));
		cr2 = (mainPlanet != nullptr ? mainPlanet->radius() : 0.0);
		cr2 *= cr2;	
		if (d2 < cr2 * 9.0f)
		{
			nearest = mainPlanet;	// the C++ planet (bead oo-al52f)
			result = AEGIS_CLOSE_TO_MAIN_PLANET;
		}
	}


	/*	Rewrote aegis stuff and tested it against redux.oxp that adds multiple planets and moons.
		Made sure AI scripts can differentiate between MAIN and NON-MAIN planets so they can decide
		if they can dock at the systemStation or just any station.
		Added sun detection so route2Patrol can turn before they heat up in the sun.
		-- Eric 2009-07-11
		
		More rewriting of the aegis stuff, it's now a bit faster and works properly when moving
		from one secondary planet/moon vicinity to another one.  -- Kaks 20120917
	*/
	if (EXPECT(!suppressAegisMessages))
	{
		// script/AI messages on change in status
		if (EXPECT_NOT(aegis_status == AEGIS_IN_DOCKING_RANGE && result != aegis_status))
		{
			doScriptEvent(OOJSID("shipExitedStationAegis"), the_station);
			if (shipAI != nullptr)  shipAI->message("AEGIS_LEAVING_DOCKING_RANGE");
		}
		
		if (EXPECT_NOT(result == AEGIS_IN_DOCKING_RANGE && aegis_status != result))
		{
			doScriptEvent(OOJSID("shipEnteredStationAegis"), the_station);
			if (shipAI != nullptr)  shipAI->message("AEGIS_IN_DOCKING_RANGE");
			
			if(lastAegisLock() == nullptr && !sunGoneNova) // With small main planets the station aegis can come before planet aegis
			{
				doScriptEvent(OOJSID("shipEnteredPlanetaryVicinity"), (UNIVERSE != nullptr ? UNIVERSE->planet() : nullptr));	// the planet is C++ since bead oo-9ht.129
				setLastAegisLock((UNIVERSE != nullptr ? UNIVERSE->planet() : nullptr));
			}
		}
		else if (EXPECT_NOT(result == AEGIS_NONE && aegis_status != result))
		{
			if(lastAegisLock() == nullptr && !sunGoneNova)
			{
				setLastAegisLock((UNIVERSE != nullptr ? UNIVERSE->planet() : nullptr));  // in case of a first launch from a near-planet station.
			}
			transitionToAegisNone();
		}
		// approaching..
		else if (EXPECT_NOT((result == AEGIS_CLOSE_TO_ANY_PLANET || result == AEGIS_CLOSE_TO_MAIN_PLANET) && lastAegisLock() != nearest))
		{
			if(aegis_status != AEGIS_NONE && lastAegisLock() != nullptr)	// we were close to another stellar body
			{
				doScriptEvent(OOJSID("shipExitedPlanetaryVicinity"), lastAegisLock());
				if (shipAI != nullptr)  shipAI->message("AWAY_FROM_PLANET");	// fires for suns, planets and moons.
			}
			doScriptEvent(OOJSID("shipEnteredPlanetaryVicinity"), nearest);
			setLastAegisLock(nearest);
			
			if (EXPECT_NOT(nearest != nullptr && nearest->isSun()))	// [nil isSun] was NO
			{
				if (shipAI != nullptr)  shipAI->message("CLOSE_TO_SUN");
			}
			else
			{
				if (shipAI != nullptr)  shipAI->message("CLOSE_TO_PLANET");
				
				if (EXPECT(result == AEGIS_CLOSE_TO_MAIN_PLANET))
				{
					// It's been years since 1.71 - it should be safe enough to comment out the line below for 1.77/1.78 -- Kaks 20120917
					//[shipAI message:@"AEGIS_CLOSE_TO_PLANET"];	    // fires only for main planets, kept for compatibility with pre-1.72 AI plists.
					if (shipAI != nullptr)  shipAI->message("AEGIS_CLOSE_TO_MAIN_PLANET");  // fires only for main planet.
				}
				else if (EXPECT_NOT(OOStellarBodyPlanetType(nearest) == STELLAR_TYPE_MOON))
				{
					if (shipAI != nullptr)  shipAI->message("CLOSE_TO_MOON");
				}
				else
				{
					if (shipAI != nullptr)  shipAI->message("CLOSE_TO_SECONDARY_PLANET");
				}
			}
		}
		

	}
	if (result == AEGIS_NONE)
	{
		setLastAegisLock(nullptr);
	}

	aegis_status = result;	// put this here
	return result;
}


void ShipEntity::forceAegisCheck()
{
	_nextAegisCheck = -1.0f;
}


bool ShipEntity::withinStationAegis()
{
	return aegis_status == AEGIS_IN_DOCKING_RANGE;
}


// A planet or sun, the C++ entity (bead oo-9ht.39.23.3): null, and forgotten, when its object is gone, as before.
Entity *ShipEntity::lastAegisLock()
{
	Entity *stellar = oo::LiveEntity(_lastAegisLock);
	if (stellar == nullptr)
	{
		_lastAegisLock = nullptr;
		return nullptr;
	}
	
	return stellar;
}


void ShipEntity::setLastAegisLock(Entity *lastAegisLock)
{
	_lastAegisLock = oo::WeakRef<Entity>(lastAegisLock);
}


OOSystemID ShipEntity::homeSystem()
{
	return home_system;
}


OOSystemID ShipEntity::destinationSystem()
{
	return destination_system;
}


void ShipEntity::setHomeSystem(OOSystemID s)
{
	home_system = s;
}


void ShipEntity::setDestinationSystem(OOSystemID s)
{
	destination_system = s;
}


void ShipEntity::setStatus(OOEntityStatus stat)
{
	if (status() == stat) return;
	OOEntityWithDrawable::setStatus(stat);	// [super setStatus:stat]
	if (stat == STATUS_LAUNCHING)
	{
		launch_time = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0);
	}
}


void ShipEntity::setLaunchDelay(double delay)
{
	launch_delay = delay;
}


std::optional<std::vector<oo::Ref<OOCharacter>>> ShipEntity::getCrew()
{
	return crew;
}


void ShipEntity::setCrew(const std::optional<std::vector<oo::Ref<OOCharacter>>> &crewArray)
{
	if (isExplicitlyUnpiloted())
	{
		//unpiloted ships cannot have crew
		// but may have crew before isExplicitlyUnpiloted set, so force *that* to clear too
		crew = std::nullopt;
		return;
	}
	//do not set to hulk here when crew is nil (or 0).  Some things like missiles have no crew.
	crew = crewArray;
}


void ShipEntity::setSingleCrewWithRole(const std::string &crewRole)
{
	if (!isUnpiloted())
	{
		oo::Ref<OOCharacter> crewMember = OOCharacter::randomCharacterWithRole(crewRole, homeSystem());
		setCrew(std::vector<oo::Ref<OOCharacter>>{ crewMember });
	}
}


std::vector<oo::PList> ShipEntity::crewForScripting()
{
	std::vector<oo::PList> result;
	if (!crew.has_value())
	{
		return result;
	}
	result.reserve(crew->size());
	for (const auto &crewMember : *crew)
	{
		result.push_back(crewMember->infoForScripting());
	}
	return result;
}


void ShipEntity::setStateMachine(const std::string &smName)
{
	setAITo(smName);
}


void ShipEntity::setAI(::AI *ai)
{
	oo::Ref<::AI> newAI(ai);	// [ai retain]
	if (shipAI)
	{
		shipAI->clearAllData();
		OOAIAutorelease(std::move(shipAI));	// [shipAI autorelease]
	}
	shipAI = std::move(newAI);
}


::AI *ShipEntity::getAI()
{
	return shipAI.get();
}


bool ShipEntity::hasAutoAI()
{
	return 	FuzzyBooleanForKey(shipinfoDictionary, "auto_ai", YES);
}


bool ShipEntity::hasNewAI()
{
	return (getAI() != nullptr ? getAI()->name() : std::optional<std::string>()) == "nullAI.plist";	// (no AI never matched)
}


bool ShipEntity::hasAutoWeapons()
{
	return 	FuzzyBooleanForKey(shipinfoDictionary, "auto_weapons", NO);
}


void ShipEntity::setShipScript(const std::optional<std::string> &script_name)
{
	oo::PList::Dict			properties;
	const oo::PList			*actions = nullptr;

	properties["ship"] = oo::EntityObjectNode(this);

	OOScriptAutorelease(std::move(script));	// [script autorelease]
	script = OOScript::jsScriptFromFileNamed(script_name.value_or(std::string()), oo::PList(properties));	// nil as "", as the Foundation form sent it

	if (script == nullptr)
	{
		actions = ArrayForKey(shipinfoDictionary, "launch_actions");
		if (actions)
		{
			cxx_OOStandardsDeprecated(oo::str::format("The launch_actions ship key is deprecated on %s.", getDisplayName().value_or("(null)").c_str()));
			if (!OOEnforceStandards())
			{
				properties["legacy_launchActions"] = *actions;
			}
		}

		actions = ArrayForKey(shipinfoDictionary, "script_actions");
		if (actions)
		{
			cxx_OOStandardsDeprecated(oo::str::format("The script_actions ship key is deprecated on %s.", getDisplayName().value_or("(null)").c_str()));
			if (!OOEnforceStandards())
			{
				properties["legacy_scriptActions"] = *actions;
			}
		}

		actions = ArrayForKey(shipinfoDictionary, "death_actions");
		if (actions)
		{
			cxx_OOStandardsDeprecated(oo::str::format("The death_actions ship key is deprecated on %s.", getDisplayName().value_or("(null)").c_str()));
			if (!OOEnforceStandards())
			{
				properties["legacy_deathActions"] = *actions;
			}
		}

		actions = ArrayForKey(shipinfoDictionary, "setup_actions");
		if (actions)
		{
			cxx_OOStandardsDeprecated(oo::str::format("The setup_actions ship key is deprecated on %s.", getDisplayName().value_or("(null)").c_str()));
			if (!OOEnforceStandards())
			{
				properties["legacy_setupActions"] = *actions;
			}
		}

		script = OOScript::jsScriptFromFileNamed("oolite-default-ship-script.js", oo::PList(std::move(properties)));
	}
}


double ShipEntity::getFrustration()
{
	return frustration;
}


OOFuelQuantity ShipEntity::getFuel()
{
	return fuel;
}


void ShipEntity::setFuel(OOFuelQuantity amount)
{
	if (amount > fuelCapacity())  amount = fuelCapacity();
	
	fuel = amount;
}


OOFuelQuantity ShipEntity::fuelCapacity()
{
	// FIXME: shipdata.plist can allow greater fuel quantities (without extending hyperspace range). Need some consistency here.
	return PLAYER_MAX_FUEL;
}


GLfloat ShipEntity::fuelChargeRate()
{
	GLfloat		rate = 1.0; // Standard (& strict play) charge rate.
	
#if MASS_DEPENDENT_FUEL_PRICES
	
	if (EXPECT(PLAYER != nil && mass> 0 && mass != (PLAYER != nullptr ? PLAYER->baseMass() : 0.0f)))
	{
		rate = calcFuelChargeRate(mass);
	}

	OO_LOG("fuelPrices", "\"{}\" fuel charge rate: {:.2f} (mass ratio: {:.2f}/{:.2f})", shipDataKey().value_or("(null)"), rate, mass, (PLAYER != nullptr ? PLAYER->baseMass() : 0.0f));
#endif
	
	return rate;
}




// Slice 20 of docs/phases/3-slices/ShipEntity.md (bead oo-66inv): sticks, bounty and legal status,
// commodities and cargo, speed. Members of the C++ ship, called directly, since bead oo-9ht.144
// deleted the facade (ADR-0056 amendment oo-9ht.144).

void ShipEntity::applySticks(double delta_t)
{
	
	double  rate1 = 2.0 * delta_t; //roll 
	double  rate2 = 4.0 * delta_t; //pitch
	double  rate3 = 4.0 * delta_t; //yaw

	if (((stick_roll > 0.0)&&(flightRoll < 0.0))||((stick_roll < 0.0)&&(flightRoll > 0.0)))
		rate1 *= 4.0;	// much faster correction
	if (((stick_pitch > 0.0)&&(flightPitch < 0.0))||((stick_pitch < 0.0)&&(flightPitch > 0.0)))
		rate2 *= 4.0;	// much faster correction
	if (((stick_yaw > 0.0)&&(flightYaw < 0.0))||((stick_yaw < 0.0)&&(flightYaw > 0.0)))
		rate3 *= 4.0;	// much faster correction

	if (accuracy >= COMBAT_AI_TRACKS_CLOSER) 
	{
		if (stick_roll == 0.0)
			rate1 *= 2.0;	// faster correction
		if (stick_pitch == 0.0)
			rate2 *= 2.0;	// faster correction
		if (stick_yaw == 0.0)
			rate3 *= 2.0;	// faster correction
	}

	// apply stick movement limits
	if (flightRoll < stick_roll - rate1)
	{
		flightRoll = flightRoll + rate1;
	}
	else if (flightRoll > stick_roll + rate1)
	{
		flightRoll = flightRoll - rate1;
	}
	else
	{
		flightRoll = stick_roll;
	}

	if (flightPitch < stick_pitch - rate2)
	{
		flightPitch = flightPitch + rate2;
	}
	else if (flightPitch > stick_pitch + rate2)
	{
		flightPitch = flightPitch - rate2;
	}
	else
	{
		flightPitch = stick_pitch;
	}

	if (flightYaw < stick_yaw - rate3)
	{
		flightYaw = flightYaw + rate3;
	}
	else if (flightYaw > stick_yaw + rate3)
	{
		flightYaw = flightYaw - rate3;
	}
	else
	{
		flightYaw = stick_yaw;
	}

}


void ShipEntity::setRoll(double amount)
{
	flightRoll = amount * M_PI / 2.0;
}


void ShipEntity::setRawRoll(double amount)
{
	flightRoll = amount;
}


void ShipEntity::setPitch(double amount)
{
	flightPitch = amount * M_PI / 2.0;
}


void ShipEntity::setYaw(double amount)
{
	flightYaw = amount * M_PI / 2.0;
}


void ShipEntity::setThrust(double amount)
{
	thrust = amount;
}


void ShipEntity::setThrustForDemo(float factor)
{
	flightSpeed = factor * maxFlightSpeed;
}


void ShipEntity::setBounty(OOCreditsQuantity amount)
{
	setBounty(amount, kOOLegalStatusReasonUnknown);
}


void ShipEntity::setBounty(OOCreditsQuantity amount, OOLegalStatusReason reason)
{
	if (getIsSubEntity()) 
	{
		if (oo::ToShip(parentEntity()) != nullptr)  oo::ToShip(parentEntity())->setBounty(amount, reason);
	}
	else 
	{
		if ((scanClass == CLASS_THARGOID || scanClass == CLASS_STATION) && reason != kOOLegalStatusReasonSetup && reason != kOOLegalStatusReasonByScript)
		{
			return; // no standard bounties for Thargoids / Stations
		}
		if (scanClass == CLASS_POLICE && amount != 0)
		{
			return; // police never have bounties
		}
		setBounty(amount, cxx_OOStringFromLegalStatusReason(reason));
	}
}


void ShipEntity::setBounty(OOCreditsQuantity amount, const std::string &reason)
{
	if (getIsSubEntity()) 
	{
		if (oo::ToShip(parentEntity()) != nullptr)  oo::ToShip(parentEntity())->setBounty(amount, reason);
	}
	else 
	{
		ooscript::Context context = OOJSAcquireContext();
	
		ooscript::Value amountVal = ooscript::undefinedValue();
		ooscript::newNumberValue(context, (int)amount-(int)bounty, &amountVal);

		bounty = amount; // can't set the new bounty until the size of the change is known

		ooscript::Value reasonVal = OOJSValueFromPList(context, oo::PList(reason));
		
		ShipScriptEvent(context, this, "shipBountyChanged", amountVal, reasonVal);
		
		OOJSRelinquishContext(context);

	}
}


OOCreditsQuantity ShipEntity::getBounty()
{
	if (getIsSubEntity()) 
	{
		return (oo::ToShip(parentEntity()) != nullptr ? oo::ToShip(parentEntity())->getBounty() : 0);
	}
	else 
	{		
		return bounty;
	}
}


int ShipEntity::legalStatus()
{
	if (scanClass == CLASS_THARGOID)
		return 5 * collision_radius;
	if (scanClass == CLASS_ROCK)
		return 0;
	return (int)getBounty();
}


void ShipEntity::setCommodity(const std::string &co_type, OOCargoQuantity co_amount)
{
	/* scoopUp can pass a reference to self.commodity_type (the old code copied it first);
	 * assigning a std::string from itself is safe. */
	commodity_type = co_type;
	commodity_amount = co_amount;
}


void ShipEntity::setCommodityForPod(const std::optional<std::string> &co_type, OOCargoQuantity co_amount)
{
	// can be nil for pods
	if (!co_type.has_value())
	{
		commodity_type = std::nullopt;
		commodity_amount = 0;
		return;
	}
	// pod content should never be greater than 1 ton or this will give cargo counting problems elsewhere in the code.
	// so do first a mass check for cargo added by script/plist.
	OOCommodityMarket *market = (UNIVERSE != nullptr ? UNIVERSE->getCommodityMarket() : nullptr);	// null: tons, as a message to nil
	OOMassUnit	unit = (market != nullptr) ? market->massUnitForGood(*co_type) : UNITS_TONS;
	if (unit == UNITS_TONS && co_amount > 1) co_amount = 1;
	else if (unit == UNITS_KILOGRAMS && co_amount > 1000) co_amount = 1000;
	else if (unit == UNITS_GRAMS && co_amount > 1000000) co_amount = 1000000;
	setCommodity(*co_type, co_amount);
}


std::optional<std::string> ShipEntity::commodityType()
{
	return commodity_type;
}


OOCargoQuantity ShipEntity::commodityAmount()
{
	return commodity_amount;
}


OOCargoQuantity ShipEntity::maxAvailableCargoSpace()
{
	return max_cargo - equipment_weight;
}


void ShipEntity::setMaxAvailableCargoSpace(OOCargoQuantity newValue)
{
	max_cargo = newValue + equipment_weight;
}


OOCargoQuantity ShipEntity::availableCargoSpace()
{
	// OOCargoQuantity is unsigned, we need to check for underflows.
	if (EXPECT_NOT(cargoQuantityOnBoard() + equipment_weight >= max_cargo)) return 0;
	return maxAvailableCargoSpace() - cargoQuantityOnBoard();
}


OOCargoQuantity ShipEntity::cargoQuantityOnBoard()
{
	NSUInteger result = cargoCount();
	OOCAssert(result < UINT32_MAX, "Cargo quantity out of bounds.");
	return (OOCargoQuantity)result;
}


OOCargoType ShipEntity::cargoType()
{
	return cargo_type;
}


/* Note: this array probably contains some template cargo pods. Do not
 * pass it to Javascript without reifying them first. The live container: callers edit it in place
 * (ADR-0043 Amendment 3 item 22); nullptr for a nil receiver. */
std::vector<oo::EntityHold> *ShipEntity::getCargo()
{
	return &cargo;
}


NSUInteger ShipEntity::cargoCount()
{
	return cargo.size();
}


oo::PList ShipEntity::cargoListForScripting()
{
	oo::PList::Array	list;

	OOCommodityMarket *market = (UNIVERSE != nullptr ? UNIVERSE->getCommodityMarket() : nullptr);	// null: no goods, as a message to nil
	const std::vector<std::string> goods = (market != nullptr) ? market->goods() : std::vector<std::string>();
	NSUInteger			i, commodityCount = goods.size();
	std::vector<OOCargoQuantity> quantityInHold(commodityCount, 0);

	for (i = 0; i < cargo.size(); i++)
	{
		::ShipEntity *container = oo::ToShip(cargo[i].get());
		const std::optional<std::string> good = (container != nullptr ? container->commodityType() : std::optional<std::string>());
		const auto j = good.has_value() ? std::ranges::find(goods, *good) : goods.end();
		// A pod whose commodity is not a good (or has none) indexed past the array before; it is skipped.
		if (j != goods.end())  quantityInHold[(std::size_t)(j - goods.begin())] += (container != nullptr ? container->commodityAmount() : 0);
	}

	for (i = 0; i < commodityCount; i++)
	{
		if (quantityInHold[i] > 0)
		{
			oo::PList::Dict	commodity;
			const std::string &good = goods[i];
			// commodity, quantity - keep consistency between .manifest and .contracts
			commodity["commodity"] = good;
			commodity["quantity"] = oo::PList(quantityInHold[i]);	// an unsigned integer
			const std::optional<std::string> goodName = market->nameForGood(good);	// (a good: the market is not null)
			if (goodName.has_value())  commodity["displayName"] = *goodName;
			commodity["unit"] = cxx_DisplayStringForMassUnitForCommodity(good).value_or("");
			list.emplace_back(std::move(commodity));
		}
	}

	return oo::PList(std::move(list));
}


void ShipEntity::setCargo(const std::vector<oo::EntityHold> &some_cargo)
{
	cargo = some_cargo;
}


bool ShipEntity::addCargo(const std::vector<oo::EntityHold> &some_cargo)
{
	if (cargo.size() + some_cargo.size() > maxAvailableCargoSpace())
	{
		return NO;
	}
	else
	{
		cargo.insert(cargo.end(), some_cargo.begin(), some_cargo.end());
		return YES;
	}
}


bool ShipEntity::removeCargo(const std::string &commodity, OOCargoQuantity amount)
{
	OOCargoQuantity found = 0;
	for (const auto &pod : cargo)
	{
		if ((oo::ToShip(pod.get()) != nullptr ? oo::ToShip(pod.get())->commodityType() : std::optional<std::string>()) == commodity)
		{
			found++;
		}
	}
	if (found < amount)
	{
		// don't remove any if there aren't enough to remove the full amount
		return NO;
	}
	
	NSUInteger i = cargo.size() - 1;
	// iterate downwards to be safe removing during iteration
	while (amount > 0)
	{
		if ((oo::ToShip(cargo[i].get()) != nullptr ? oo::ToShip(cargo[i].get())->commodityType() : std::optional<std::string>()) == commodity)
		{
			amount--;
			cargo.erase(cargo.begin() + i);
		}
		// check above means array index can't underflow here
		i--;
	}

	return YES;
}


bool ShipEntity::showScoopMessage()
{
	return hasScoopMessage;
}


OOCargoFlag ShipEntity::cargoFlag()
{
	return cargo_flag;
}


void ShipEntity::setCargoFlag(OOCargoFlag flag)
{
	if (cargo_flag != flag)
	{
		cargo_flag = flag;
		std::vector<oo::EntityHold> newCargo;	// the universe's pods (bead oo-9ht.39.26)
		unsigned num = 0;
		if (likely_cargo > 0)
		{
			num = likely_cargo * (0.5+randf());
			if (num > maxAvailableCargoSpace())
			{
				num = maxAvailableCargoSpace();
			}
		}
		else
		{
			num = maxAvailableCargoSpace();
		}
		if (num > 200)
		{
			num = 200; 
			/* no core NPC ship carries this much when generated (the
			 * Anaconda could, but doesn't): let's not waste time generating
			 * thousands of pods - even if they are semi-virtual - for some
			 * massive OXP ship */
		}
		if (num > 0)
		{
			switch (cargo_flag)
			{
			case CARGO_FLAG_FULL_UNIFORM:
				{
					const oo::PList &info = shipinfoDictionary;
					newCargo = (UNIVERSE != nullptr ? UNIVERSE->getContainersOfCommodity(StringForKey(info, "cargo_carried").value_or(""), num) : std::vector<oo::EntityHold>());
				}
				break;
			case CARGO_FLAG_FULL_PLENTIFUL:
				newCargo = (UNIVERSE != nullptr ? UNIVERSE->getContainersOfGoods(num, NO, YES) : std::vector<oo::EntityHold>());
				break;
			case CARGO_FLAG_FULL_SCARCE:
				newCargo = (UNIVERSE != nullptr ? UNIVERSE->getContainersOfGoods(num, YES, YES) : std::vector<oo::EntityHold>());
				break;
			case CARGO_FLAG_FULL_MEDICAL:
				newCargo = (UNIVERSE != nullptr ? UNIVERSE->getContainersOfCommodity("Narcotics", num) : std::vector<oo::EntityHold>());
				break;
			case CARGO_FLAG_FULL_CONTRABAND:
				newCargo = (UNIVERSE != nullptr ? UNIVERSE->getContainersOfGoods(num, YES, NO) : std::vector<oo::EntityHold>());
				break;
			case CARGO_FLAG_PIRATE:
				newCargo = (UNIVERSE != nullptr ? UNIVERSE->getContainersOfGoods((Ranrot() % (1+num/2)), YES, NO) : std::vector<oo::EntityHold>());
				break;
			case CARGO_FLAG_FULL_PASSENGERS:
				// TODO: allow passengers to survive
			case CARGO_FLAG_NONE:
			default:
				break;
			}
		}
		setCargo(newCargo);
	}
}


void ShipEntity::setSpeed(double amount)
{
	flightSpeed = amount;
}


void ShipEntity::setDesiredSpeed(double amount)
{
	desired_speed = amount;
}


double ShipEntity::desiredSpeed()
{
	return desired_speed;
}




// Slice 21 of docs/phases/3-slices/ShipEntity.md (bead oo-cicod): flight controls and limits,
// temperature, dealing damage, hulks, damage notes. Members of the C++ ship, called directly, since
// bead oo-9ht.144 deleted the facade (ADR-0056 amendment oo-9ht.144).

double ShipEntity::desiredRange()
{
	return desired_range;
}


void ShipEntity::setDesiredRange(double amount)
{
	desired_range = amount;
}


double ShipEntity::getCruiseSpeed()
{
	return cruiseSpeed;
}


void ShipEntity::increase_flight_speed(double delta)
{
	double factor = 1.0;
	if (desired_speed > maxFlightSpeed && hasFuelInjection() && fuel > MIN_FUEL) factor = afterburnerFactor();

	if (flightSpeed < maxFlightSpeed * factor)
		flightSpeed += delta * factor;
	else
		flightSpeed = maxFlightSpeed * factor;
}


void ShipEntity::decrease_flight_speed(double delta)
{
	double factor = 1.0;
	if (flightSpeed > maxFlightSpeed) 
	{
		factor = MIN_HYPERSPEED_FACTOR;
	}

	if (flightSpeed > factor * delta)
	{
		flightSpeed -= factor * delta;
	}
	else
	{
		flightSpeed = 0;
	}
}


void ShipEntity::increase_flight_roll(double delta)
{
	flightRoll += delta;
	if (flightRoll > max_flight_roll)
		flightRoll = max_flight_roll;
	else if (flightRoll < -max_flight_roll)
		flightRoll = -max_flight_roll;
}


void ShipEntity::decrease_flight_roll(double delta)
{
	flightRoll -= delta;
	if (flightRoll > max_flight_roll)
		flightRoll = max_flight_roll;
	else if (flightRoll < -max_flight_roll)
		flightRoll = -max_flight_roll;
}


void ShipEntity::increase_flight_pitch(double delta)
{
	flightPitch += delta;
	if (flightPitch > max_flight_pitch)
		flightPitch = max_flight_pitch;
	else if (flightPitch < -max_flight_pitch)
		flightPitch = -max_flight_pitch;
}


void ShipEntity::decrease_flight_pitch(double delta)
{
	flightPitch -= delta;
	if (flightPitch > max_flight_pitch)
		flightPitch = max_flight_pitch;
	else if (flightPitch < -max_flight_pitch)
		flightPitch = -max_flight_pitch;
}


void ShipEntity::increase_flight_yaw(double delta)
{
	flightYaw += delta;
	if (flightYaw > max_flight_yaw)
		flightYaw = max_flight_yaw;
	else if (flightYaw < -max_flight_yaw)
		flightYaw = -max_flight_yaw;
}


void ShipEntity::decrease_flight_yaw(double delta)
{
	flightYaw -= delta;
	if (flightYaw > max_flight_yaw)
		flightYaw = max_flight_yaw;
	else if (flightYaw < -max_flight_yaw)
		flightYaw = -max_flight_yaw;
}


GLfloat ShipEntity::getFlightRoll()
{
	return flightRoll;
}


GLfloat ShipEntity::getFlightPitch()
{
	return flightPitch;
}


GLfloat ShipEntity::getFlightYaw()
{
	return flightYaw;
}


GLfloat ShipEntity::getFlightSpeed()
{
	return flightSpeed;
}


GLfloat ShipEntity::maxFlightPitch()
{
	return max_flight_pitch;
}


GLfloat ShipEntity::getMaxFlightSpeed()
{
	return maxFlightSpeed;
}


GLfloat ShipEntity::maxFlightRoll()
{
	return max_flight_roll;
}


GLfloat ShipEntity::maxFlightYaw()
{
	return max_flight_yaw;
}


void ShipEntity::setMaxFlightPitch(GLfloat newValue)
{
	max_flight_pitch = newValue;
}


void ShipEntity::setMaxFlightSpeed(GLfloat newValue)
{
	maxFlightSpeed = newValue;
}


void ShipEntity::setMaxFlightRoll(GLfloat newValue)
{
	max_flight_roll = newValue;
}


void ShipEntity::setMaxFlightYaw(GLfloat newValue)
{
	max_flight_yaw = newValue;
}


GLfloat ShipEntity::speedFactor()
{
	if (maxFlightSpeed <= 0.0)  return 0.0;
	return flightSpeed / maxFlightSpeed;
}


GLfloat ShipEntity::temperature()
{
	return ship_temperature;
}


void ShipEntity::setTemperature(GLfloat value)
{
	ship_temperature = value;
}


float ShipEntity::randomEjectaTemperature()
{
	return randomEjectaTemperatureWithMaxFactor(0.99f);
}


float ShipEntity::randomEjectaTemperatureWithMaxFactor(float factor)
{
	const float kRange = 0.02f;
	factor -= kRange;
	
	float parentTemp = temperature();
	float adjusted = parentTemp * (bellf(5) * (kRange * 2.0f) - kRange + factor);
	if (adjusted > SHIP_MAX_CABIN_TEMP)
	{
		adjusted = SHIP_MAX_CABIN_TEMP;
	}
	
	// Interpolate so that result == parentTemp when parentTemp is SHIP_MIN_CABIN_TEMP
	float interp = OOClamp_0_1_f((parentTemp - SHIP_MIN_CABIN_TEMP) / (SHIP_MAX_CABIN_TEMP - SHIP_MIN_CABIN_TEMP));
	
	return OOLerp(SHIP_MIN_CABIN_TEMP, adjusted, interp);
}


GLfloat ShipEntity::heatInsulation()
{
	return _heatInsulation;
}


void ShipEntity::setHeatInsulation(GLfloat value)
{
	_heatInsulation = value;
}


int ShipEntity::damage()
{
	return (int)(100 - (100 * energy / maxEnergy));
}


void ShipEntity::dealEnergyDamage(GLfloat baseDamage, GLfloat range, GLfloat velocityBias)
{
	// this is limited to the player's scanner range
	GLfloat maxRange = fmin(range * sqrt(baseDamage), SCANNER_MAX_RANGE);
	
	OO_LOG("missile.damage.calc", "Range: {:f} | Damage: {:f} | MaxRange: {:f}", range, baseDamage, maxRange);

	const std::vector<oo::EntityHold> targets = (UNIVERSE != nullptr ? UNIVERSE->entitiesWithinRange(maxRange, this) : std::vector<oo::EntityHold>());
	if (targets.size() > 0)
	{
		unsigned i;
		for (i = 0; i < targets.size(); i++)
		{
			Entity *e2 = targets[i].get();	// the snapshot keeps its object (beads oo-9ht.39.16, oo-9ht.39.26)
			Vector p2 = vectorTo(e2);
			double ecr = e2->collisionRadius();
			double d = (magnitude(p2) - ecr) / range;
			// base damage within defined range, inverse-square falloff outside
			double localDamage = baseDamage;
			OO_LOG("missile.damage.calc", "Base damage: {:f}", baseDamage);
			if (velocityBias > 0)
			{
				Vector v2 = vector_subtract(getVelocity(), e2->getVelocity());
				double vSign = dot_product(vector_normal(getVelocity()), vector_normal(p2));
				// vSign should always be positive for the missile's actual target
        // but might be negative for other nearby ships which are
        // actually moving further away from the missile
//				double vMag = vSign > 0.0 ? magnitude(v2) : -magnitude(v2);
				double vMag = vSign * magnitude(v2);
				if (vMag > 1000.0) {
					vMag = 1000.0; 
// cap effective closing speed to 1.0LM or injector-collisions can still do
// ridiculous damage
				}

				localDamage += vMag * velocityBias;
				OO_LOG("missile.damage.calc", "Velocity magnitude + sign: {:f} , {:f}", magnitude(v2), vSign);
				OO_LOG("missile.damage.calc", "Velocity magnitude factor: {:f}", vMag);
				OO_LOG("missile.damage.calc", "Velocity corrected damage: {:f}", localDamage);
			}
			double damage = (d > 1) ? localDamage / (d * d) : localDamage;
			OO_LOG("missile.damage.calc", "{:f} at range {:f} (d={:f})", damage, magnitude(p2)-ecr, d);
			if (damage > 0.0)
			{
				if (owner())
				{
					e2->takeEnergyDamage(damage, this, oo::LiveOwner(this), getPrimaryRole().value_or(std::string()));
				} 
				else
				{
					e2->takeEnergyDamage(damage, this, this, getPrimaryRole().value_or(std::string()));
				}
			}
		}
	}
	
	/* the actual damage can't go more than S_M_R, so cap the range
	 * for exploding purposes so that the visual appearance isn't
	 * larger than that */
	if (range > SCANNER_MAX_RANGE / 4.0)
	{
		range = SCANNER_MAX_RANGE / 4.0;
	}
	// and a visual sign of the explosion
	// "fireball" explosion effect
	if (UNIVERSE != nullptr)  UNIVERSE->addEntity(oo::MadeEntity(OOExplosionCloudEntity::explosionCloudFromEntity(this, range*3.0, (UNIVERSE != nullptr ? UNIVERSE->explosionSetting("oolite-default-ship-explosion") : oo::PList()))));

}


// dealEnergyDamage preferred
// Exposed to AI
void ShipEntity::dealEnergyDamageWithinDesiredRange()
{
	cxx_OOStandardsDeprecated(oo::str::format("dealEnergyDamageWithinDesiredRange is deprecated for %s", oo::EntityDescription(this).c_str()));
	// not over scannerRange
	const std::vector<oo::EntityHold> targets = (UNIVERSE != nullptr ? UNIVERSE->entitiesWithinRange((desired_range < SCANNER_MAX_RANGE ? desired_range : SCANNER_MAX_RANGE), this) : std::vector<oo::EntityHold>());
	if (targets.size() > 0)
	{
		unsigned i;
		for (i = 0; i < targets.size(); i++)
		{
			Entity *e2 = targets[i].get();	// the snapshot keeps its object (beads oo-9ht.39.16, oo-9ht.39.26)
			Vector p2 = vectorTo(e2);
			double ecr = e2->collisionRadius();
			double d = (magnitude(p2) - ecr) * 2.6; // 2.6 is a correction constant to stay in limits of the old code.
			double damage = (d > 0) ? weapon_damage * desired_range / (d * d) : weapon_damage;
			e2->takeEnergyDamage(damage, this, oo::LiveOwner(this), getPrimaryRole().value_or(std::string()));
		}
	}
}


void ShipEntity::dealMomentumWithinDesiredRange(double amount)
{
	const std::vector<oo::EntityHold> targets = (UNIVERSE != nullptr ? UNIVERSE->entitiesWithinRange(desired_range, this) : std::vector<oo::EntityHold>());
	if (targets.size() > 0)
	{
		unsigned i;
		for (i = 0; i < targets.size(); i++)
		{
			::ShipEntity *e2 = oo::ToShip(targets[i].get());
			if ((e2 != nullptr ? e2->getIsShip() : false) && (e2 != nullptr ? e2->isInSpace() : false))
			{
				Vector p2 = vectorTo(e2);
				double ecr = (e2 != nullptr ? e2->collisionRadius() : 0.0f);
				double d2 = magnitude2(p2) - ecr * ecr;
				// limit momentum transfer to relatively sensible levels
				if (d2 < 0.1)
				{
					d2 = 0.1;
				}
				double moment = amount*desired_range/d2;
				if (e2 != nullptr)  e2->addImpactMoment(vector_normal(p2), moment);
			}
		}
	}
}


bool ShipEntity::getIsHulk()
{
	return isHulk;
}


void ShipEntity::setHulk(bool isNowHulk)
{
	if (!getIsSubEntity()) 
	{
		isHulk = isNowHulk;
	}
}


void ShipEntity::noteTakingDamage(double amount, Entity *entity, OOShipDamageType type)
{
	if (amount < 0 || (amount == 0 && (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr ? UNIVERSE->gameController()->isGamePaused() : false)))  return;
	
	ooscript::Context context = OOJSAcquireContext();
	
	ooscript::Value amountVal = ooscript::undefinedValue();
	ooscript::newNumberValue(context, amount, &amountVal);
	ooscript::Value entityVal = OOJSEntityJSValue(entity, context);
	ooscript::Value typeVal = OOJSValueFromShipDamageType(context, type);
	
	ShipScriptEvent(context, this, "shipTakingDamage", amountVal, entityVal, typeVal);
	OOJSRelinquishContext(context);
	
	if (oo::EntityIsShip(entity)) {
//		ShipEntity* attacker = (ShipEntity *)entity;
		if (hasHostileTarget() && accuracy >= COMBAT_AI_IS_SMART && (randf()*10.0 < accuracy || desired_speed < 0.5 * maxFlightSpeed) && behaviour != BEHAVIOUR_EVASIVE_ACTION && behaviour != BEHAVIOUR_FLEE_EVASIVE_ACTION && behaviour != BEHAVIOUR_SCRIPTED_ATTACK_AI)
		{
			if (behaviour == BEHAVIOUR_FLEE_TARGET)
			{
// jink should be sufficient to avoid being hit most of the time
// if not, this will make a sharp turn and then select a new jink position
				behaviour = BEHAVIOUR_FLEE_EVASIVE_ACTION;
			}
			else
			{
				behaviour = BEHAVIOUR_EVASIVE_ACTION;
			}
			frustration = 0.0;
		}
	}

}


void ShipEntity::noteKilledBy(Entity *whom, OOShipDamageType type)
{
	if (status() == STATUS_DEAD)  return;
	
	if (PLAYER != nullptr)  PLAYER->setScriptTarget(this);
	
	ooscript::Context context = OOJSAcquireContext();
	
	ooscript::Value whomVal = OOJSEntityJSValue(whom, context);
	ooscript::Value typeVal = OOJSValueFromShipDamageType(context, type);
	OOEntityStatus originalStatus = status();
	setStatus(STATUS_DEAD);
	
	ShipScriptEvent(context, this, "shipDied", whomVal, typeVal);
	if (oo::EntityIsShip(whom))
	{
		ooscript::Value selfVal = OOJSValueFromCxxObject(context, this);
		ShipScriptEvent(context, oo::ToShip(whom), "shipKilledOther", selfVal, typeVal);
	}
	
	setStatus(originalStatus);
	OOJSRelinquishContext(context);
}




// Slice 22 of docs/phases/3-slices/ShipEntity.md (bead oo-z1utw): destruction, rescaling, cargo
// debris, explosions, energy blast. Members of the C++ ship, called directly, since bead oo-9ht.144
// deleted the facade (ADR-0056 amendment oo-9ht.144).

void ShipEntity::getDestroyedBy(Entity *whom, OOShipDamageType type)
{
	noteKilledBy(whom, type);
	abortDocking();
	becomeExplosion();
}


void ShipEntity::rescaleBy(GLfloat factor)
{
	rescaleBy(factor, YES);
}


void ShipEntity::rescaleBy(GLfloat factor, bool writeToCache)
{
	_scaleFactor *= factor;
	oo::Ref<::OOMesh> mesh;

	const oo::PList &shipDict = shipinfoDictionary;
	const std::optional<std::string> modelName = StringForKey(shipDict, "model");
	if (modelName.has_value())
	{
		mesh = ::OOMesh::meshWithName(*modelName,
						   oo::str::format("%s-%.3f", _shipKey.value_or("(null)").c_str(), _scaleFactor),	// %@ printed nil as (null)
						   DictionaryForKey(shipDict, "materials"),
						   DictionaryForKey(shipDict, "shaders"),
						   shipDict.get<bool>("smooth", false),
						   OODefaultShipShaderMacros(),
						   this,	// the C++ ship (bead oo-9ht.39.6)
						   factor,
						   writeToCache);

		if (mesh == nullptr)  return;
		setMesh(mesh.get());
	}

	// rescale subentities
	const std::vector<oo::EntityHold> subs = subEntities;	// a snapshot, as -subEntities copied
	for (const auto &sub : subs)
	{
		Entity	*se = sub.get();
		if (se == nullptr)  continue;	// every message went to nil
		se->setPosition(HPvector_multiply_scalar(se->getPosition(), factor));
		if (cxx::OOSubEntityInterface *cxxSub = dynamic_cast<cxx::OOSubEntityInterface *>(se))  cxxSub->rescaleBy(factor, writeToCache);
		// (else: none - every ship sub-entity adopts the interface; bead oo-dpyk8)
	}
	
	// rescale mass
	mass *= factor * factor * factor;
}


void ShipEntity::releaseCargoPodsDebris()
{
	HPVector xposition = position;
	NSUInteger i;
	Vector v;
	Quaternion q;
	int speed_low = 200;

	std::vector<oo::EntityHold> jetsam;  // this will contain the stuff to get thrown out
	unsigned cargo_chance = 70;
	jetsam = cargo;   // what the ship is carrying
	cargo.clear();   // dispense with it!
	unsigned limit = 15;
	//  Throw out cargo
	NSUInteger n_jetsam = jetsam.size();
					
	for (i = 0; i < n_jetsam; i++)
	{
		if (Ranrot() % 100 < cargo_chance)  //  chance of any given piece of cargo surviving decompression
		{
			// a higher chance of getting at least a couple of bits of cargo out
			if (cargo_chance > 10)
			{
				if (EXPECT_NOT(getIsPlayer()))
				{
					cargo_chance -= 20;
				}
				else
				{
					cargo_chance -= 30;
				}
			}
			limit--;
			::ShipEntity* cargoObj = oo::ToShip(jetsam[i].get());
			::ShipEntity* container = (UNIVERSE != nullptr ? UNIVERSE->reifyCargoPod(cargoObj) : (::ShipEntity *)nil);
			/* TODO: this debris position/velocity setting code is
			 * duplicated - sometimes not very cleanly - all over the
			 * place. Unify to a single function - CIM */
			HPVector  rpos = xposition;
			Vector	rrand = OORandomPositionInBoundingBox(boundingBox);
			rpos.x += rrand.x;	rpos.y += rrand.y;	rpos.z += rrand.z;
			rpos.x += (ranrot_rand() % 7) - 3;
			rpos.y += (ranrot_rand() % 7) - 3;
			rpos.z += (ranrot_rand() % 7) - 3;
			if (container != nullptr)  container->setPosition(rpos);
			v.x = 0.1 *((ranrot_rand() % speed_low) - speed_low / 2);
			v.y = 0.1 *((ranrot_rand() % speed_low) - speed_low / 2);
			v.z = 0.1 *((ranrot_rand() % speed_low) - speed_low / 2);
			if (container != nullptr)  container->setVelocity(vector_add(v,getVelocity()));
			quaternion_set_random(&q);
			if (container != nullptr)  container->setOrientation(q);
							
			if (container != nullptr)  container->setTemperature(randomEjectaTemperature());
			if (container != nullptr)  container->setScanClass(CLASS_CARGO);
			if (UNIVERSE != nullptr)  UNIVERSE->addEntity(container);	// STATUS_IN_FLIGHT, AI state GLOBAL

			::AI *containerAI = (container != nullptr ? container->getAI() : (::AI *)nullptr);
			if ((containerAI != nullptr ? containerAI->hasSuspendedStateMachines() : false)) // check if new or recycled cargo.
			{
				if (containerAI != nullptr)  containerAI->exitStateMachineWithMessage(std::nullopt);
				if (container != nullptr)  container->setThrust((container != nullptr ? container->maxThrust() : 0.0f)); // restore old value. Was set to zero on previous scooping.
				if (container != nullptr)  container->setOwner(container);
			}
		}
		if (limit <= 0)
		{
			break; // even really big ships won't have too much cargo survive an explosion
		}
	}

}


void ShipEntity::setIsWreckage(bool isw)
{
	isWreckage = isw;
}


bool ShipEntity::showDamage()
{
	return _showDamage;
}


void ShipEntity::becomeExplosion()
{
	
	// check if we're destroying a subentity
	::ShipEntity *parent = oo::ToShip(parentEntity());
	if (parent != nil)
	{
		::ShipEntity *this_ship = oo::ToShip(oo::RetainEntity(this));
		HPVector this_pos = absolutePositionForSubentity();
		
		// remove this ship from its parent's subentity list
		if (parent != nullptr)  parent->subEntityDied(this);
		if (UNIVERSE != nullptr)  UNIVERSE->addEntity(this_ship);
		if (this_ship != nullptr)  this_ship->setPosition(this_pos);
		if (this_ship != nullptr)  oo::ReleaseEntity(this_ship);
		if ((parent != nullptr ? parent->getIsPlayer() : false))
		{
			// make the parent ship less reliable.
			static_cast<PlayerEntity *>(parent)->adjustTradeInFactorBy(-PLAYER_SHIP_SUBENTITY_TRADE_IN_VALUE);
		}
	}
	
	HPVector xposition = position;
	NSUInteger i;
	Vector v;
	Quaternion q;
	int speed_low = 200;
	GLfloat n_alloys = sqrtf(sqrtf(mass / 6000.0f));
	NSUInteger numAlloys = 0;
	BOOL canReleaseSubWreckage = isWreckage && ((UNIVERSE != nullptr ? UNIVERSE->getDetailLevel() : OOGraphicsDetail{}) >= DETAIL_LEVEL_EXTRAS);

	if (status() == STATUS_DEAD)
	{
		if (UNIVERSE != nullptr)  UNIVERSE->removeEntity(this);
		return;
	}
	setStatus(STATUS_DEAD);
	
	const oo::Finally removeDead([this]	// was @finally
	{
		if (this != PLAYER)
		{
			if (UNIVERSE != nullptr)  UNIVERSE->removeEntity(this);
		}
	});
	{
		if (isThargoid() && roleSet != nullptr && roleSet->hasRole("thargoid-mothership"))  broadcastThargoidDestroyed();
		
		if (!suppressExplosion && (isVisible() || HPdistance2(getPosition(), (PLAYER != nullptr ? PLAYER->getPosition() : HPVector{})) < SCANNER_MAX_RANGE2))
		{
			if (!isWreckage && mass > 500000.0f && randf() < 0.25f) // big!
			{
				// draw an expanding ring
				oo::Ref<OORingEffectEntity> ring = OORingEffectEntity::ringFromEntity(this);
				if (ring != nullptr)  ring->setVelocity(vector_multiply_scalar(getVelocity(), 0.25f));
				if (UNIVERSE != nullptr)  UNIVERSE->addEntity(oo::MadeEntity(ring));
			}
			
			BOOL add_debris = (UNIVERSE->n_entities < 0.95 * static_cast<double>(UNIVERSE_MAX_ENTITIES)) &&
									  ((UNIVERSE != nullptr ? UNIVERSE->getTimeDelta() : 0.0) < 0.125);	  // FPS > 8
			
			
			// There are several parts to explosions, show only the main
			// explosion effect if UNIVERSE is almost full.
			
			if (add_debris)
			{
				if ((UNIVERSE != nullptr ? UNIVERSE->reducedDetail() : false))
				{
					// Quick explosion effects for reduced detail mode
					
					// 1. fast sparks
					if (UNIVERSE != nullptr)  UNIVERSE->addEntity(oo::MadeEntity(OOSmallFragmentBurstEntity::fragmentBurstFromEntity(this)));
					// 2. slow clouds
					if (UNIVERSE != nullptr)  UNIVERSE->addEntity(oo::MadeEntity(OOBigFragmentBurstEntity::fragmentBurstFromEntity(this)));
					// 3. flash
					if (UNIVERSE != nullptr)  UNIVERSE->addEntity(oo::MadeEntity(::OOFlashEffectEntity::explosionFlashFromEntity(this)));
					/* This mode used to be the default for
					 * cargo/munitions but this now must be explicitly
					 * specified. */
				}
				else
				{
					if (explosionType.isNull())
					{
						if (UNIVERSE != nullptr)  UNIVERSE->addEntity(oo::MadeEntity(OOExplosionCloudEntity::explosionCloudFromEntity(this, (UNIVERSE != nullptr ? UNIVERSE->explosionSetting("oolite-default-ship-explosion") : oo::PList()))));
						// 3. flash
						if (UNIVERSE != nullptr)  UNIVERSE->addEntity(oo::MadeEntity(::OOFlashEffectEntity::explosionFlashFromEntity(this)));
					}
					for (NSUInteger i=0;i<explosionType.count();i++)
					{
						// The string reader at index i: a string, or a number's text, else none.
						const oo::PList *entry = explosionType.at(i);
						if (entry != nullptr && (entry->isString() || entry->isNumber()))
						{
							const std::string explosionKey = oo::PListGet<std::string>::from(entry, std::string());
							// three special-case builtins
							if (explosionKey == "oolite-builtin-flash")
							{
								if (UNIVERSE != nullptr)  UNIVERSE->addEntity(oo::MadeEntity(::OOFlashEffectEntity::explosionFlashFromEntity(this)));
							}
							else if (explosionKey == "oolite-builtin-slowcloud")
							{
								if (UNIVERSE != nullptr)  UNIVERSE->addEntity(oo::MadeEntity(OOBigFragmentBurstEntity::fragmentBurstFromEntity(this)));
							}
							else if (explosionKey == "oolite-builtin-fastspark")
							{
								if (UNIVERSE != nullptr)  UNIVERSE->addEntity(oo::MadeEntity(OOSmallFragmentBurstEntity::fragmentBurstFromEntity(this)));
							}
							else
							{
								if (UNIVERSE != nullptr)  UNIVERSE->addEntity(oo::MadeEntity(OOExplosionCloudEntity::explosionCloudFromEntity(this, (UNIVERSE != nullptr ? UNIVERSE->explosionSetting(explosionKey) : oo::PList()))));
							}
						}
					}
					// "fireball" explosion effect

				}
			}
			 
			// If UNIVERSE is nearing limit for entities don't add to it!
			if (add_debris)
			{
				// we need to throw out cargo at this point.
				releaseCargoPodsDebris();
				
				//  Throw out rocks and alloys to be scooped up
				if (hasRole("asteroid") || isBoulder())
				{
					if (!noRocks && (being_mined || randf() < 0.20))
					{
						std::string defaultRole = "boulder";
						float defaultSpeed = 50.0;
						if (isBoulder())
						{
							defaultRole = "splinter";
							defaultSpeed = 20.0;
							if (likely_cargo == 0)
							{
								likely_cargo = 4; // compatibility with older boulders
							}
						}
						else if (oo::EntityIsPlayer(primaryAggressor()))
						{
							if (PLAYER != nullptr)  PLAYER->addRoleForMining();
						}
						NSUInteger n_rocks = 2 + (Ranrot() % (likely_cargo + 1));
						
						const std::string debrisRole = shipInfoDictionary().get<std::string>("debris_role", defaultRole);
						for (i = 0; i < n_rocks; i++)
						{
							::ShipEntity* rock = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole(debrisRole) : (::ShipEntity *)nil);   // retain count = 1
							if (rock)
							{
								float  r_speed = (rock != nullptr ? rock->getMaxFlightSpeed() : 0.0f) > 0 ? 2.0 * (rock != nullptr ? rock->getMaxFlightSpeed() : 0.0f) : defaultSpeed;
								float cr = (collision_radius < rock->collision_radius) ? collision_radius : 2 * rock->collision_radius;
								v.x = ((randf() * r_speed) - r_speed / 2);
								v.y = ((randf() * r_speed) - r_speed / 2);
								v.z = ((randf() * r_speed) - r_speed / 2);
								if (rock != nullptr)  rock->setVelocity(vector_add(v,getVelocity()));
								HPVector rpos = HPvector_add(xposition,vectorToHPVector(vector_multiply_scalar(vector_normal(v),cr)));
								if (rock != nullptr)  rock->setPosition(rpos);

								quaternion_set_random(&q);
								if (rock != nullptr)  rock->setOrientation(q);
								
								if (rock != nullptr)  rock->setTemperature(randomEjectaTemperature());
								if (isBoulder())
								{
									if (rock != nullptr)  rock->setScanClass(CLASS_CARGO);
									if (rock != nullptr)  rock->setBounty(0, kOOLegalStatusReasonSetup);
									// only make the rock have minerals if something isn't already defined for the rock
									if (!StringForKey((rock != nullptr ? rock->shipInfoDictionary() : oo::PList()), "cargo_carried").has_value())
										if (rock != nullptr)  rock->setCommodity("minerals", 1);
								}
								else
								{
									if (rock != nullptr)  rock->setScanClass(CLASS_ROCK);
									if (rock != nullptr)  rock->setIsBoulder(YES);
								}
								if (UNIVERSE != nullptr)  UNIVERSE->addEntity(rock);	// STATUS_IN_FLIGHT, AI state GLOBAL
								if (rock != nullptr)  oo::ReleaseEntity(rock);
							}
						}
					}
					return;
				}

				// throw out burning chunks of wreckage
				//
				if ((n_alloys && canFragment) || canReleaseSubWreckage)
				{
					NSUInteger n_wreckage = 0;
					
					if (UNIVERSE->n_entities < 0.50 * static_cast<double>(UNIVERSE_MAX_ENTITIES))
					{
						// Create wreckage only when UNIVERSE is less than half full.
						// (condition set in r906 - was < 0.75 before) --Kaks 2011.10.17
						NSUInteger maxWrecks = 3;
						if (n_alloys == 0)
						{
							// must be sub-wreckage here
							n_wreckage = (mass > 600.0 && randf() < 0.2)?2:0;
						}
						else
						{
							n_wreckage = (n_alloys < maxWrecks)? floorf(randf()*(n_alloys+2)) : maxWrecks;
						}
					}
					
					for (i = 0; i < n_wreckage; i++)
					{
						Vector r1 = (octree ? octree->randomPoint() : kZeroVector);
						Vector dir = quaternion_rotate_vector(normalOrientation(), r1);
						HPVector rpos = HPvector_add(vectorToHPVector(dir), xposition);
						GLfloat lifetime = 750.0 * randf() + 250.0 * i + 100.0;
						::ShipEntity *wreck = (UNIVERSE != nullptr ? UNIVERSE->addWreckageFrom(this, "wreckage", rpos, 1.0, lifetime/2) : nullptr);

						if (wreck != nullptr)  wreck->setVelocity(vector_add((wreck != nullptr ? wreck->getVelocity() : Vector{}),vector_multiply_scalar(vector_normal(dir),randf()*(wreck != nullptr ? wreck->collisionRadius() : 0.0f))));

					}
					n_alloys = randf() * n_alloys;
				}
			} 

			if (!canFragment)
			{
				n_alloys = 0.0;
			}
			// If UNIVERSE is almost full, don't create more than 1 piece of scrap metal.
			else if (!add_debris)
			{
				n_alloys = (n_alloys > 1.0) ? 1.0 : 0.0;
			}

			// now convert to uint
			numAlloys = floorf(n_alloys);

			// Throw out scrap metal
			//
			for (i = 0; i < numAlloys; i++)
			{
				::ShipEntity* plate = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole("alloy") : (::ShipEntity *)nil);   // retain count = 1
				if (plate)
				{
					HPVector  rpos = xposition;
					Vector	rrand = OORandomPositionInBoundingBox(boundingBox);
					rpos.x += rrand.x;	rpos.y += rrand.y;	rpos.z += rrand.z;
					rpos.x += (ranrot_rand() % 7) - 3;
					rpos.y += (ranrot_rand() % 7) - 3;
					rpos.z += (ranrot_rand() % 7) - 3;
					if (plate != nullptr)  plate->setPosition(rpos);
					v.x = 0.1 *((ranrot_rand() % speed_low) - speed_low / 2);
					v.y = 0.1 *((ranrot_rand() % speed_low) - speed_low / 2);
					v.z = 0.1 *((ranrot_rand() % speed_low) - speed_low / 2);
					if (plate != nullptr)  plate->setVelocity(vector_add(v,getVelocity()));
					quaternion_set_random(&q);
					if (plate != nullptr)  plate->setOrientation(q);
					
					if (plate != nullptr)  plate->setTemperature(randomEjectaTemperature());
					if (plate != nullptr)  plate->setScanClass(CLASS_CARGO);
					if (plate != nullptr)  plate->setCommodity("alloys", 1);
					if (UNIVERSE != nullptr)  UNIVERSE->addEntity(plate);	// STATUS_IN_FLIGHT, AI state GLOBAL
					
					if (plate != nullptr)  oo::ReleaseEntity(plate);
				}
			}
		}
		
		// Explode subentities.
		for (const auto &sub : shipSubEntities())
		{
			::ShipEntity *se = oo::ToShip(sub.get());
			if (se != nullptr)  se->setSuppressExplosion(suppressExplosion);
			if (se != nullptr)  se->becomeExplosion();
		}
		clearSubEntities();

		// momentum from explosions
		if (!suppressExplosion)
		{
			desired_range = collision_radius * 2.5f;
			dealMomentumWithinDesiredRange(0.125f * mass);
		}
		
		if (this != PLAYER)	// was if !isPlayer - but I think this may cause ghosts (Who's "I"? -- Ahruman)
		{
			if (isPlayer)
			{
	#ifndef NDEBUG
				OO_LOG("becomeExplosion.suspectedGhost.confirm", "{}", "Ship spotted with isPlayer set when not actually the player.");
	#endif
				isPlayer = NO;
			}
		}
	}
}


// Exposed to AI
void ShipEntity::becomeEnergyBlast()
{
	if (UNIVERSE != nullptr)  UNIVERSE->addEntity(oo::MadeEntity(OOQuiriumCascadeEntity::quiriumCascadeFromShip(this)));
	broadcastEnergyBlastImminent();
	noteKilledBy(nullptr, kOODamageTypeCascadeWeapon);
	if (UNIVERSE != nullptr)  UNIVERSE->removeEntity(this);
}


// Exposed to AI
void ShipEntity::broadcastEnergyBlastImminent()
{
	// anyone further away than typical scanner range probably doesn't need to hear
	const std::vector<oo::EntityHold> targets = (UNIVERSE != nullptr ? UNIVERSE->entitiesWithinRange(SCANNER_MAX_RANGE, this) : std::vector<oo::EntityHold>());
	if (targets.size() > 0)
	{
		unsigned i;
		for (i = 0; i < targets.size(); i++)
		{
			Entity *e2 = targets[i].get();	// the snapshot keeps its object (beads oo-9ht.39.16, oo-9ht.39.26)
			if (oo::EntityIsShip(e2))
			{
				::ShipEntity *se = oo::ToShip(e2);
				if (se != nullptr)  se->setFoundTarget(this);
				if (se != nullptr)  se->reactToAIMessage("CASCADE_WEAPON_DETECTED", "nearby Q-mine");
				if (se != nullptr)  se->doScriptEvent(OOJSID("cascadeWeaponDetected"), this);
			}
		}
	}
}


void ShipEntity::removeExhaust(OOExhaustPlumeEntity *exhaust)
{
	std::erase(subEntities, static_cast<Entity *>(exhaust));
	if (exhaust != nullptr)  exhaust->setOwner(nullptr);	// [exhaustObject setOwner:nil]
}




// Slice 23 of docs/phases/3-slices/ShipEntity.md (bead oo-xmrgd): subentity death, alignment
// offsets, large explosion, laser heat, personality, scanner, remembered ships. Members of the C++
// ship, called directly, since bead oo-9ht.144 deleted the facade (ADR-0056 amendment oo-9ht.144).

void ShipEntity::removeFlasher(OOFlasherEntity *flasher)
{
	std::erase(subEntities, static_cast<Entity *>(flasher));
	if (flasher != nullptr)  flasher->setOwner(nullptr);	// [flasherObject setOwner:nil]
}


void ShipEntity::subEntityDied(::ShipEntity *sub)
{
	if (subEntityTakingDamage() == sub)  setSubEntityTakingDamage(nullptr);
	
	if (sub != nullptr)  sub->setOwner(nullptr);
	// TODO? Recalculating collision radius should increase collision testing efficiency,
	// but for most ship models the difference would be marginal. -- Kaks 20110429
	mass -= (sub != nullptr ? sub->getMass() : 0.0f); // missing subents affect fuel charge rate, etc..
	std::erase(subEntities, static_cast<Entity *>(sub));
}


void ShipEntity::subEntityReallyDied(::ShipEntity *sub)
{
	if (subEntityTakingDamage() == sub)  setSubEntityTakingDamage(nullptr);
	
	if (hasSubEntity(sub))
	{
		OO_LOG_ERR("shipEntity.bug.subEntityRetainUnderflow", "Subentity of {} died while still in subentity list! This is bad. Leaking subentity list to avoid crash. {}", oo::EntityDescription(this), "This is an internal error, please report it.");
		
		// Leak subentity list: one more retain each, so that emptying the list keeps them all alive,
		// as dropping the array pointer did.
		for (const auto &leaked : subEntities)  oo::RetainEntity(leaked.get());
		subEntities.clear();
	}
}


Vector ShipEntity::positionOffsetForAlignment(const std::string &align)
{
	// indexed in UTF-16 units, as -characterAtIndex: was
	const std::u16string padAlign = oo::utf8ToUtf16(oo::str::format("%s---", align.c_str()));
	Vector result = kZeroVector;
	switch (padAlign[0])
	{
		case (uint16_t)'c':
		case (uint16_t)'C':
			result.x = 0.5 * (boundingBox.min.x + boundingBox.max.x);
			break;
		case (uint16_t)'M':
			result.x = boundingBox.max.x;
			break;
		case (uint16_t)'m':
			result.x = boundingBox.min.x;
			break;
	}
	switch (padAlign[1])
	{
		case (uint16_t)'c':
		case (uint16_t)'C':
			result.y = 0.5 * (boundingBox.min.y + boundingBox.max.y);
			break;
		case (uint16_t)'M':
			result.y = boundingBox.max.y;
			break;
		case (uint16_t)'m':
			result.y = boundingBox.min.y;
			break;
	}
	switch (padAlign[2])
	{
		case (uint16_t)'c':
		case (uint16_t)'C':
			result.z = 0.5 * (boundingBox.min.z + boundingBox.max.z);
			break;
		case (uint16_t)'M':
			result.z = boundingBox.max.z;
			break;
		case (uint16_t)'m':
			result.z = boundingBox.min.z;
			break;
	}
	return result;
}


void ShipEntity::becomeLargeExplosion(double factor)
{
	
	if (status() == STATUS_DEAD)  return;
	setStatus(STATUS_DEAD);
	
	const oo::Finally removeDead([this]	// was @finally
	{
		if (!isPlayer)  { if (UNIVERSE != nullptr)  UNIVERSE->removeEntity(this); }
	});
	{
		// two parts to the explosion:
		// 1. fast sparks
		float how_many = factor;
		while (how_many > 0.5f)
		{
			if (UNIVERSE != nullptr)  UNIVERSE->addEntity(oo::MadeEntity(OOSmallFragmentBurstEntity::fragmentBurstFromEntity(this)));
			how_many -= 1.0f;
		}
		// 2. slow clouds
		how_many = factor;
		while (how_many > 0.5f)
		{
			if (UNIVERSE != nullptr)  UNIVERSE->addEntity(oo::MadeEntity(OOBigFragmentBurstEntity::fragmentBurstFromEntity(this)));
			how_many -= 1.0f;
		}

		releaseCargoPodsDebris();
		
		for (const auto &sub : shipSubEntities())
		{
			::ShipEntity *se = oo::ToShip(sub.get());
			if (se != nullptr)  se->setSuppressExplosion(suppressExplosion);
			if (se != nullptr)  se->becomeExplosion();
		}
		clearSubEntities();
		
	}
}


void ShipEntity::collectBountyFor(::ShipEntity *other)
{
	if ((other != nullptr ? other->isPolice() : false))   // oops, we shot a copper!
	{
		markAsOffender(64, kOOLegalStatusReasonAttackedPolice);
	}
}


OOComparisonResult ShipEntity::compareBeaconCodeWith(Entity *other)
{
	return (OOComparisonResult)oo::str::caseInsensitiveCompare(beaconCode().value_or(""), oo::BeaconCode(other).value_or(""));	// the other's -beaconCode (bead oo-al52f)
}


// for shaders, equivalent to 1.76's NPC laserHeatLevel
GLfloat ShipEntity::weaponRecoveryTime()
{
	float result = (weapon_recharge_rate - shotTime()) / weapon_recharge_rate;
	return OOClamp_0_1_f(result);
}


GLfloat ShipEntity::laserHeatLevel()
{
	GLfloat result = weapon_temp / NPC_MAX_WEAPON_TEMP;
	return OOClamp_0_1_f(result);
}


GLfloat ShipEntity::laserHeatLevelAft()
{
	GLfloat result = aft_weapon_temp / NPC_MAX_WEAPON_TEMP;
	return OOClamp_0_1_f(result);
}


GLfloat ShipEntity::laserHeatLevelForward()
{
	GLfloat result = forward_weapon_temp / NPC_MAX_WEAPON_TEMP;
	if (isWeaponNone(forward_weapon_type)) 
	{ // must check subents
		OOWeaponType forward_weapon_real_type = nil;
		for (const auto &sub : shipSubEntities())
		{
			if (!isWeaponNone(forward_weapon_real_type))  break;
			::ShipEntity *se = oo::ToShip(sub.get());
			if (!isWeaponNone(se->forward_weapon_type))
			{
				forward_weapon_real_type = se->forward_weapon_type;
				result = se->forward_weapon_temp / NPC_MAX_WEAPON_TEMP;
			}
		}
	}
	return OOClamp_0_1_f(result);
}


GLfloat ShipEntity::laserHeatLevelPort()
{
	GLfloat result = port_weapon_temp / NPC_MAX_WEAPON_TEMP;
	return OOClamp_0_1_f(result);
}


GLfloat ShipEntity::laserHeatLevelStarboard()
{
	GLfloat result = starboard_weapon_temp / NPC_MAX_WEAPON_TEMP;
	return OOClamp_0_1_f(result);
}


GLfloat ShipEntity::hullHeatLevel()
{
	GLfloat result = (GLfloat)ship_temperature / (GLfloat)SHIP_MAX_CABIN_TEMP;
	return OOClamp_0_1_f(result);
}


GLfloat ShipEntity::entityPersonality()
{
	return entity_personality / (float)ENTITY_PERSONALITY_MAX;
}


GLint ShipEntity::entityPersonalityInt()
{
	return entity_personality;
}


uint32_t ShipEntity::randomSeedForShaders()
{
	return entity_personality * 0x00010001;
}


void ShipEntity::setEntityPersonalityInt(uint16_t value)
{
	if (value <= ENTITY_PERSONALITY_MAX)
	{
		entity_personality = value;
		if (::OOMesh *mesh = this->mesh())  mesh->rebindMaterials();
	}
}


void ShipEntity::setSuppressExplosion(bool suppress)
{
	suppressExplosion = !!suppress;
}


void ShipEntity::resetExhaustPlumes()
{
	for (const auto &exEnt : exhausts())
	{
		if (OOExhaustPlumeEntity *exhaust = dynamic_cast<OOExhaustPlumeEntity *>(exEnt.get()))  exhaust->resetPlume();
	}
}


/*-----------------------------------------

	AI piloting methods

-----------------------------------------*/


void ShipEntity::checkScanner()
{
	Entity* scan;	// the C++ part (bead oo-9ht.39.4)
	n_scanned_ships = 0;
	//
	scan = z_previous;	while ((scan)&&(scan->isShip == NO))	scan = scan->z_previous;	// skip non-ships
	GLfloat scannerRange2 = scannerRange * scannerRange;
	while ((scan)&&(scan->position.z > position.z - scannerRange)&&(n_scanned_ships < MAX_SCAN_NUMBER))
	{
		// can't scan cloaked ships
		if (scan->isShip && !(oo::ToShip(scan) != nullptr ? oo::ToShip(scan)->isCloaked() : false) && isValidTarget(scan))
		{
			distance2_scanned_ships[n_scanned_ships] = HPdistance2(position, scan->position);
			if (distance2_scanned_ships[n_scanned_ships] < scannerRange2)
				scanned_ships[n_scanned_ships++] = oo::ToShip(scan);
		}
		scan = scan->z_previous;	while ((scan)&&(scan->isShip == NO))	scan = scan->z_previous;
	}
	//
	scan = z_next;	while ((scan)&&(scan->isShip == NO))	scan = scan->z_next;	// skip non-ships
	while ((scan)&&(scan->position.z < position.z + scannerRange)&&(n_scanned_ships < MAX_SCAN_NUMBER))
	{
		if (scan->isShip && !(oo::ToShip(scan) != nullptr ? oo::ToShip(scan)->isCloaked() : false) && isValidTarget(scan))
		{
			distance2_scanned_ships[n_scanned_ships] = HPdistance2(position, scan->position);
			if (distance2_scanned_ships[n_scanned_ships] < scannerRange2)
				scanned_ships[n_scanned_ships++] = oo::ToShip(scan);
		}
		scan = scan->z_next;	while ((scan)&&(scan->isShip == NO))	scan = scan->z_next;	// skip non-ships
	}
	//
	scanned_ships[n_scanned_ships] = nil;	// terminate array
}


void ShipEntity::checkScannerIgnoringUnpowered()
{
	Entity* scan;	// the C++ part (bead oo-9ht.39.4)
	n_scanned_ships = 0;
	//
	GLfloat scannerRange2 = scannerRange * scannerRange;
	scan = z_previous;	
	while ((scan)&&((scan->isShip == NO)||(scan->scanClass==CLASS_ROCK)||(scan->scanClass==CLASS_CARGO)))	
	{
		scan = scan->z_previous;	// skip non-ships
	}
	while ((scan)&&(scan->position.z > position.z - scannerRange)&&(n_scanned_ships < MAX_SCAN_NUMBER))
	{
		if (scan->isShip && !(oo::ToShip(scan) != nullptr ? oo::ToShip(scan)->isCloaked() : false))
		{
			distance2_scanned_ships[n_scanned_ships] = HPdistance2(position, scan->position);
			if (distance2_scanned_ships[n_scanned_ships] < scannerRange2)
				scanned_ships[n_scanned_ships++] = oo::ToShip(scan);
		}
		scan = scan->z_previous;
		while ((scan)&&((scan->isShip == NO)||(scan->scanClass==CLASS_ROCK)||(scan->scanClass==CLASS_CARGO)))	
		{
			scan = scan->z_previous;	// skip non-ships
		}
	}
	//
	scan = z_next;	
	while ((scan)&&((scan->isShip == NO)||(scan->scanClass==CLASS_ROCK)||(scan->scanClass==CLASS_CARGO)))	
	{
		scan = scan->z_next;	// skip non-ships
	}

	while ((scan)&&(scan->position.z < position.z + scannerRange)&&(n_scanned_ships < MAX_SCAN_NUMBER))
	{
		if (scan->isShip && !(oo::ToShip(scan) != nullptr ? oo::ToShip(scan)->isCloaked() : false))
		{
			distance2_scanned_ships[n_scanned_ships] = HPdistance2(position, scan->position);
			if (distance2_scanned_ships[n_scanned_ships] < scannerRange2)
				scanned_ships[n_scanned_ships++] = oo::ToShip(scan);
		}
		scan = scan->z_next;
		while ((scan)&&((scan->isShip == NO)||(scan->scanClass==CLASS_ROCK)||(scan->scanClass==CLASS_CARGO)))	
		{
			scan = scan->z_next;	// skip non-ships
		}
	}
	//
	scanned_ships[n_scanned_ships] = nil;	// terminate array
}


::ShipEntity **ShipEntity::scannedShips()
{
	scanned_ships[n_scanned_ships] = nil;	// terminate array
	return scanned_ships;
}


int ShipEntity::numberOfScannedShips()
{
	return n_scanned_ships;
}


// The C++ entity (bead oo-9ht.39.23): null, and forgotten, when its object is gone or it is no valid target, as before.
Entity *ShipEntity::foundTarget()
{
	Entity *result = oo::LiveEntity(_foundTarget);
	if (result == nullptr || !isValidTarget(result))
	{
		_foundTarget = nullptr;
		return nullptr;
	}
	return result;
}


void ShipEntity::setFoundTarget(Entity *targetEntity)
{
	_foundTarget = oo::WeakRef<Entity>(targetEntity);
}


// The C++ entity (bead oo-9ht.39.23): null, and forgotten, when its object is gone or it is no valid target, as before.
Entity *ShipEntity::primaryAggressor()
{
	Entity *result = oo::LiveEntity(_primaryAggressor);
	if (result == nullptr || !isValidTarget(result))
	{
		_primaryAggressor = nullptr;
		return nullptr;
	}
	return result;
}


void ShipEntity::setPrimaryAggressor(Entity *targetEntity)
{
	_primaryAggressor = oo::WeakRef<Entity>(targetEntity);
}


// The C++ entity (bead oo-9ht.39.23.1): null when its object is gone or it is no valid target, as before.
Entity *ShipEntity::lastEscortTarget()
{
	Entity *result = oo::LiveEntity(_lastEscortTarget);
	if (result == nullptr || !isValidTarget(result))
	{
		_lastEscortTarget = nullptr;
		return nullptr;
	}
	return result;
}


void ShipEntity::setLastEscortTarget(Entity *targetEntity)
{
	_lastEscortTarget = oo::WeakRef<Entity>(targetEntity);
}




// Slice 24 of docs/phases/3-slices/ShipEntity.md (bead oo-zd80m): target memory and validity,
// behaviour and destination accessors, distances, leading the target. Members of the C++ ship,
// called directly, since bead oo-9ht.144 deleted the facade (ADR-0056 amendment oo-9ht.144).

// The C++ entity (bead oo-9ht.39.23.1): null when its object is gone or it is no valid target, as before.
Entity *ShipEntity::thankedShip()
{
	Entity *result = oo::LiveEntity(_thankedShip);
	if (result == nullptr || !isValidTarget(result))
	{
		_thankedShip = nullptr;
		return nullptr;
	}
	return result;
}


void ShipEntity::setThankedShip(Entity *targetEntity)
{
	_thankedShip = oo::WeakRef<Entity>(targetEntity);
}


// The C++ entity (bead oo-9ht.39.23.1): null when its object is gone or it is no valid target, as before.
Entity *ShipEntity::rememberedShip()
{
	Entity *result = oo::LiveEntity(_rememberedShip);
	if (result == nullptr || !isValidTarget(result))
	{
		_rememberedShip = nullptr;
		return nullptr;
	}
	return result;
}


void ShipEntity::setRememberedShip(Entity *targetEntity)
{
	_rememberedShip = oo::WeakRef<Entity>(targetEntity);
}


// The C++ entity (bead oo-9ht.39.23.4): null, and forgotten, when its object is gone or it is no valid target, as before.
Entity *ShipEntity::targetStation()
{
	Entity *result = oo::LiveEntity(_targetStation);
	if (result == nullptr || !isValidTarget(result))
	{
		_targetStation = nullptr;
		return nullptr;
	}
	return result;
}


void ShipEntity::setTargetStation(Entity *targetEntity)
{
	_targetStation = oo::WeakRef<Entity>(targetEntity);
}


/* Now we use weakrefs rather than universal ID this function checks
 * for targets which may have a valid reference but are not currently
 * targetable. */
// The C++ entity since bead oo-9ht.39.23 (the object's -isShip, -status, -isWormhole and -scanClass read these).
bool ShipEntity::isValidTarget(Entity *target)
{
	if (target == nullptr) 
	{
		return NO;
	}
	if (target->getIsShip())
	{
		OOEntityStatus tstatus = target->status();
		if (tstatus == STATUS_ENTERING_WITCHSPACE || tstatus == STATUS_IN_HOLD || tstatus == STATUS_DOCKED || tstatus == STATUS_DEAD)
        // 2013-01-13, Eric: added STATUS_DEAD because I keep seeing ships locked on dead ships in attack mode.
		{
			return NO;
		}
		return YES;
	}
	if (target->getIsWormhole() && target->getScanClass() != CLASS_NO_DRAW)
	{
		return YES;
	}
	return NO;
}


void ShipEntity::addTarget(Entity *targetEntity)
{
	if (targetEntity == this)  return;
	if (targetEntity != nullptr) 
	{
		_primaryTarget = nullptr;
		_primaryTarget = oo::WeakRef<Entity>(targetEntity);
		startTrackingCurve();
	}
	
	for (const auto &sub : shipSubEntities())  { if (oo::ToShip(sub.get()) != nullptr)  oo::ToShip(sub.get())->addTarget(targetEntity); }
	if (!getIsSubEntity())  doScriptEvent(OOJSID("shipTargetAcquired"), targetEntity);
}


void ShipEntity::removeTarget(Entity *targetEntity)
{
	if(targetEntity != nullptr) noteLostTarget();
	else _primaryTarget = nullptr;
	// targetEntity == nil is currently only true for mounted player missiles. 
	// we don't want to send lostTarget messages while the missile is mounted.
	
	for (const auto &sub : shipSubEntities())  { if (oo::ToShip(sub.get()) != nullptr)  oo::ToShip(sub.get())->removeTarget(targetEntity); }
}


/* Checks if the primary target is still trackable.
 * 
 * 1.80 behaviour: still exists, is in scanner range, is not cloaked
 *
 * 1.81 (planned) behaviour:
 * - track cloaked ships once primary targeted (but no missiles, and can't keep as a mere defense target, and probably some other penalties)
 * - track ships at 120% scanner range *if* they are also primary aggressor
 *
 * But first, just switch over to this method on 1.80 behaviour and check
 * that things still work.
 */
bool ShipEntity::canStillTrackPrimaryTarget()
{
	Entity *target = primaryTargetWithoutValidityCheck();
	if (target == nullptr)
	{
		return NO;
	}
	if (!isValidTarget(target))
	{
		return NO;
	}
	double range2 = HPmagnitude2(HPvector_subtract(target->getPosition(), position));
	if (range2 > scannerRange * scannerRange * 1.5625) 
	{
		// 1.5625 = 1.25*1.25
		return NO;
	}
	// 1.81: can retain cloaked ships as a *primary* target now
/*	if ([target isShip] && [(ShipEntity*)target isCloaked])
	{
		return NO;
		} */
	return YES;
}


// The C++ entity (bead oo-9ht.39.23; its object before): null, and forgotten, when its object is gone or it is
// no valid target, as before.
Entity *ShipEntity::primaryTarget()
{
	Entity *result = oo::LiveEntity(_primaryTarget);
	if ((result == nil && _primaryTarget != oo::WeakRef<Entity>())
			|| !isValidTarget(result))
	{
		_primaryTarget = nullptr;
		return nullptr;
	}
	else if (EXPECT_NOT(result == this))
	{
		/*	Added in response to a crash report showing recursion in
			[PlayerEntity hasHostileTarget].
			-- Ahruman 2009-12-17
		*/
		_primaryTarget = nullptr;
	}
	return result;
}


// used when we need to check the target - perhaps for a potential
// noteTargetLost - without invalidating the target first
Entity *ShipEntity::primaryTargetWithoutValidityCheck()
{
	Entity *result = oo::LiveEntity(_primaryTarget);
	if (EXPECT_NOT(result == this))
	{
		// just in case
		_primaryTarget = nullptr;
		return nullptr;
	}
	return result;
}


bool ShipEntity::isFriendlyTo(::ShipEntity *otherShip)
{
	BOOL isFriendly = NO;
	::OOShipGroup	*myGroup = group();
	::OOShipGroup	*otherGroup = (otherShip != nullptr ? otherShip->group() : (OOShipGroup *)nullptr);
	
	if ((otherShip == this) ||
		(isPolice() && (otherShip != nullptr ? otherShip->isPolice() : false)) ||
		(isThargoid() && (otherShip != nullptr ? otherShip->isThargoid() : false)) ||
		(myGroup != nil && otherGroup != nil && (myGroup == otherGroup || (otherGroup != nullptr ? otherGroup->leader() : (::ShipEntity *)nil) == this)) ||
		(getScanClass() == CLASS_MILITARY && (otherShip != nullptr ? otherShip->getScanClass() : OOScanClass{}) == CLASS_MILITARY))
	{
		isFriendly = YES;
	}
	
	return isFriendly;
}


::ShipEntity *ShipEntity::shipHitByLaser()
{
	return oo::ToShip(oo::LiveEntity(_shipHitByLaser));
}


void ShipEntity::setShipHitByLaser(::ShipEntity *ship)
{
	if (ship != shipHitByLaser())
	{
		_shipHitByLaser = oo::WeakRef<Entity>(ship);
	}
}


void ShipEntity::noteLostTarget()
{
	Entity *target = nullptr;
	if (primaryTarget() != nil)
	{
		::ShipEntity* ship = oo::ToShip(primaryTarget());
		if (isDefenseTarget(ship)) 
		{
			removeDefenseTarget(ship);
		}
		// for compatibility with 1.76 behaviour of this function, only pass
		// the target as a function parameter if the target is still a potential
		// valid target (e.g. not scooped, docked, hyperspaced, etc.)
		target = (ship && ship->isShip && isValidTarget(ship)) ? ship : nullptr;
		if (primaryAggressor() == ship) 
		{
			_primaryAggressor = nullptr;
		}
		_primaryTarget = nullptr;
	}
	// always do target lost
	doScriptEvent(OOJSID("shipTargetLost"), target);
	if (target == nullptr) { if (shipAI != nullptr)  shipAI->message("TARGET_LOST"); }	// stale target? no major urgency.
	else { if (shipAI != nullptr)  shipAI->reactToMessage("TARGET_LOST", "flight updates"); }	// execute immediately otherwise.
}


void ShipEntity::noteLostTargetAndGoIdle()
{
	behaviour = BEHAVIOUR_IDLE;
	frustration = 0.0;
	noteLostTarget();
}


void ShipEntity::noteTargetDestroyed(::ShipEntity *target)
{
	collectBountyFor(oo::ToShip(target));
	if (primaryTarget() == target)
	{
		removeTarget(target);
		doScriptEvent(OOJSID("shipTargetDestroyed"), target);
		if (shipAI != nullptr)  shipAI->message("TARGET_DESTROYED");
	}
	if (isDefenseTarget(target)) 
	{
		removeDefenseTarget(target);
		if (shipAI != nullptr)  shipAI->message("DEFENSE_TARGET_DESTROYED");
		doScriptEvent(OOJSID("defenseTargetDestroyed"), target);
	}
}


OOBehaviour ShipEntity::getBehaviour()
{
	return behaviour;
}


void ShipEntity::setBehaviour(OOBehaviour cond)
{
	if (cond != behaviour)
	{
		frustration = 0.0;	// change is a GOOD thing
		behaviour = cond;
	}
}


HPVector ShipEntity::destination()
{
	return _destination;
}


HPVector ShipEntity::getCoordinates()
{
	return coordinates;
}


void ShipEntity::setCoordinate(HPVector coord)
{
	coordinates = coord;
}


HPVector ShipEntity::distance_six(GLfloat dist)
{
	HPVector six = position;
	six.x -= dist * v_forward.x;	six.y -= dist * v_forward.y;	six.z -= dist * v_forward.z;
	return six;
}


HPVector ShipEntity::distance_twelve(GLfloat dist, GLfloat offset)
{
	HPVector twelve = position;
	twelve.x += dist * v_up.x;	twelve.y += dist * v_up.y;	twelve.z += dist * v_up.z;
	twelve.x += offset * v_right.x;	twelve.y += offset * v_right.y;	twelve.z += offset * v_right.z;
	return twelve;
}


void ShipEntity::trackOntoTarget(double /* delta_t */, GLfloat dp)
{
	Vector vector_to_target;
	Quaternion q_minarc;
	//
	Entity *target = primaryTarget();
	//
	if (!target)
		return;

	vector_to_target = vectorTo(target);
	//
	GLfloat range2 =		magnitude2(vector_to_target);
	GLfloat	targetRadius =	0.75 * target->collision_radius;
	GLfloat	max_cos =		sqrt(1 - targetRadius*targetRadius/range2);
	
	if (dp > max_cos)
		return;	// ON TARGET!
	
	if (vector_to_target.x||vector_to_target.y||vector_to_target.z)
		vector_to_target = vector_normal(vector_to_target);
	else
		vector_to_target.z = 1.0;
	
	q_minarc = quaternion_rotation_between(v_forward, vector_to_target);
	
	orientation = quaternion_multiply(q_minarc, orientation);
	orientationChanged();
	
	flightRoll = 0.0;
	flightPitch = 0.0;
	flightYaw = 0.0;
	stick_roll = 0.0;
	stick_pitch = 0.0;
	stick_yaw = 0.0;
}


double ShipEntity::ballTrackLeadingTarget(double delta_t, Entity *target)
{
	if (!target)
	{
		return -2.0; // no target
	}

	Vector		vector_to_target;
	Vector		axis_to_track_by;
	Vector		my_aim = vector_forward_from_quaternion(orientation);
	Vector		my_ref = reference;
	double		aim_cos, ref_cos;
	Vector		leading = target->getVelocity();

	// need to get vector to target in terms of this entities coordinate system
	HPVector my_position = absolutePositionForSubentity();
	vector_to_target = HPVectorToVector(HPvector_subtract(target->getPosition(), my_position));
	// this is in absolute coordinates, so now rotate it

	Entity		*last = nullptr;
	Entity		*father = oo::LiveEntity(oo::WeakRef<Entity>(parentEntity()));	// null once its object has gone, as the object read +0 was nil (bead oo-xn1j1)

	Quaternion  q = kIdentityQuaternion;
	while ((father)&&(father != last) && (father != nullptr))	// (Entity *)NO_TARGET
	{
		/* Fix orientation */
		Quaternion fo = father->normalOrientation();
		fo.w = -fo.w;
		/* The below code works for player turrets where the
		 * orientation is different, but not for NPC turrets. Taking
		 * the normal orientation with -w works: there is probably a
		 * neater way which someone who understands quaternions can
		 * find, but this works well enough for 1.82 - CIM */
		q = quaternion_multiply(q,quaternion_conjugate(fo));
		last = father;
		if (!oo::EntityIsSubEntity(last)) break;
		father = oo::LiveOwner(father);	// [father owner]
	}
	q = quaternion_conjugate(q);
	// q now contains the rotation to the turret's reference system

	vector_to_target = quaternion_rotate_vector(q,vector_to_target);

	leading = quaternion_rotate_vector(q,leading);
	// rotate the vector to target and its velocity
	
	if (magnitude(vector_to_target) > weaponRange * 1.01)
	{
		return -2.0; // out of range
	}

	float lead = magnitude(vector_to_target) / TURRET_SHOT_SPEED;
		
	vector_to_target = vector_add(vector_to_target, vector_multiply_scalar(leading, lead));
	vector_to_target = vector_normal_or_fallback(vector_to_target, kBasisZVector);
		
	// do the tracking!
	aim_cos = dot_product(vector_to_target, my_aim);
	ref_cos = dot_product(vector_to_target, my_ref);

	
	if (ref_cos > TURRET_MINIMUM_COS)  // target is forward of self
	{
		axis_to_track_by = cross_product(vector_to_target, my_aim);
	}
	else
	{
		return -2.0; // target is out of fire arc
	}
	
	quaternion_rotate_about_axis(&orientation, axis_to_track_by, thrust * delta_t);
	orientationChanged();
	
	setStatus(STATUS_ACTIVE);
	
	return aim_cos;
}




// Slice 25 of docs/phases/3-slices/ShipEntity.md (bead oo-k6wuw): evasive jink, primary and side
// target tracking. Members of the C++ ship, called directly, since bead oo-9ht.144 deleted the
// facade (ADR-0056 amendment oo-9ht.144).

void ShipEntity::setEvasiveJink(GLfloat z)
{
	if (accuracy < COMBAT_AI_ISNT_AWFUL)
	{
		jink = kZeroVector;
	}
	else 
	{
		jink.x = (ranrot_rand() % 256) - 128.0;
		jink.y = (ranrot_rand() % 256) - 128.0;
		jink.z = z;
		
		// make sure we don't accidentally have near-zero jink
		if (jink.x < 0.0) 
		{
			jink.x -= 128.0;
		}
		else
		{
			jink.x += 128.0;
		}
		if (jink.y < 0) 
		{
			jink.y -= 128.0;
		}
		else
		{
			jink.y += 128.0;
		}
	}
}


void ShipEntity::evasiveAction(double delta_t)
{
	stick_roll = flightRoll;	//desired roll and pitch
	stick_pitch = flightPitch;

	::ShipEntity* target = oo::ToShip(primaryTarget());
	if (!target)   // leave now!
	{
		noteLostTargetAndGoIdle();	// NOTE: was AI message: rather than reactToMessage:
		return;
	}

	double agreement = dot_product(v_right,target->v_right);
	if (agreement > -0.3 && agreement < 0.3)
	{
		stick_roll = 0.0;
	}
	else
	{
		if (stick_roll >= 0.0) {
			stick_roll = max_flight_roll;
		} else {
			stick_roll = -max_flight_roll;
		}
	}
	if (stick_pitch >= 0.0) {
		stick_pitch = max_flight_pitch;
	} else {
		stick_pitch = -max_flight_pitch;
	}
	
  applySticks(delta_t);
}


double ShipEntity::trackPrimaryTarget(double delta_t, bool retreat)
{
	Entity *target = primaryTarget();

	if (!target)   // leave now!
	{
		noteLostTargetAndGoIdle();	// NOTE: was AI message: rather than reactToMessage:
		return 0.0;
	}

	if (!canStillTrackPrimaryTarget())
	{
		noteLostTargetAndGoIdle();	// NOTE: was AI message: rather than reactToMessage:
		return 0.0;
	}

	/* 1.81 change: do the above check first: if a missile can't be
	 * fired outside scanner range it should self-destruct if the
	 * target gets far enough away (it's going to miss anyway) -
	 * CIM */
	if (scanClass == CLASS_MISSILE)
		return missileTrackPrimaryTarget(delta_t);

	GLfloat  d_forward, d_up, d_right;
	
	Vector  relPos = HPVectorToVector(HPvector_subtract(calculateTargetPosition(), position));
	
	double	range2 = HPmagnitude2(HPvector_subtract((target != nullptr ? target->getPosition() : kZeroHPVector), position));

	//jink if retreating
	if (retreat) // calculate jink position when flying away from target.
	{
		Vector vx, vy, vz;
		if (target->isShip)
		{
			::ShipEntity* targetShip = oo::ToShip(target);
			vx = targetShip->v_right;
			vy = targetShip->v_up;
			vz = targetShip->v_forward;
		}
		else
		{
			Quaternion q = target->orientation;
			vx = vector_right_from_quaternion(q);
			vy = vector_up_from_quaternion(q);
			vz = vector_forward_from_quaternion(q);
		}
		
		BOOL avoidCollision = NO;
		if (range2 < collision_radius * target->collision_radius * 100.0) // Check direction within 10 * collision radius.
		{
			Vector targetDirection = kBasisZVector;
			if (!vector_equal(relPos, kZeroVector))  targetDirection = vector_normal(relPos);
			avoidCollision  =  (dot_product(targetDirection, v_forward) > -0.1); // is flying toward target or only slightly outward.
		}
		
		GLfloat dist_adjust_factor = 1.0;
		if (accuracy >= COMBAT_AI_FLEES_BETTER)
		{
			double	range = magnitude(relPos);
			if (range > 2000.0)
			{
				dist_adjust_factor = range / 2000.0;
				if (accuracy >= COMBAT_AI_FLEES_BETTER_2)
				{
					dist_adjust_factor *= 3;
				}
			}
			if (jink.x == 0.0 && behaviour != BEHAVIOUR_RUNNING_DEFENSE)
			{ // test for zero jink and correct
				setEvasiveJink(400.0);
			}
		}

		if (!avoidCollision)  // it is safe to jink
		{
			relPos.x += (jink.x * vx.x + jink.y * vy.x + jink.z * vz.x) * dist_adjust_factor;
			relPos.y += (jink.x * vx.y + jink.y * vy.y + jink.z * vz.y) * dist_adjust_factor;
			relPos.z += (jink.x * vx.z + jink.y * vy.z + jink.z * vz.z);
		}

	}

	if (!vector_equal(relPos, kZeroVector))  relPos = vector_normal(relPos);
	else  relPos.z = 1.0;

	double	max_cos = currentAimTolerance();

	stick_roll = 0.0;	//desired roll and pitch
	stick_pitch = 0.0;

	double reverse = (retreat)? -1.0: 1.0;

	double min_d = 0.004; // ~= 40m at 10km
	int max_factor = 8;
	double r_max_factor = 0.125;
	if (!retreat)
	{	
		if (accuracy >= COMBAT_AI_TRACKS_CLOSER)
		{ 
			// much greater precision in combat
			if (max_flight_pitch > 1.0)
			{
				max_factor = floor(max_flight_pitch/0.125);
				r_max_factor = 1.0/max_factor;
			}
			min_d = 0.0004; // 10 times more precision ~= 4m at 10km
			max_factor *= 3;
			r_max_factor /= 3.0;
		}
		else if (accuracy >= COMBAT_AI_ISNT_AWFUL)
		{
			// slowly improve precision to target, but only if missing
			min_d -= 0.0001 * missedShots();
			if (min_d < 0.001)
			{
				min_d = 0.001;
				max_factor *= 2;
				r_max_factor /= 2.0;
			}
		}
	}

	d_right		=   dot_product(relPos, v_right);
	d_up		=   dot_product(relPos, v_up);
	d_forward   =   dot_product(relPos, v_forward);	// == cos of angle between v_forward and vector to target

	if (d_forward * reverse > max_cos)	// on_target!
	{
		return d_forward;
	}

	// begin rule-of-thumb manoeuvres
	stick_pitch = 0.0;
	stick_roll = 0.0;


	if ((reverse * d_forward < -0.5) && !pitching_over) // we're going the wrong way!
		pitching_over = YES;

	if (pitching_over)
	{
		if (reverse * d_up > 0) // pitch up
			stick_pitch = -max_flight_pitch;
		else
			stick_pitch = max_flight_pitch;
		pitching_over = (reverse * d_forward < 0.707);
	}

	// check if we are flying toward the destination..
	if ((d_forward < max_cos)||(retreat))	// not on course so we must adjust controls..
	{
		if (d_forward < -max_cos)  // hack to avoid just flying away from the destination
		{
			d_up = min_d * 2.0;
		}

		if (d_up > min_d)
		{
			int factor = sqrt(fabs(d_right) / fabs(min_d));
			if (factor > max_factor)
				factor = max_factor;
			if (d_right > min_d)
				stick_roll = - max_flight_roll * r_max_factor * factor; // note#
			if (d_right < -min_d)
				stick_roll = + max_flight_roll * r_max_factor * factor; // note#
		}
		if (d_up < -min_d)
		{
			int factor = sqrt(fabs(d_right) / fabs(min_d));
			if (factor > max_factor)
				factor = max_factor;
			if (d_right > min_d)
				stick_roll = + max_flight_roll * r_max_factor * factor; // note#
			if (d_right < -min_d)
				stick_roll = - max_flight_roll * r_max_factor * factor; // note#
		}

		if (stick_roll == 0.0)
		{
			int factor = sqrt(fabs(d_up) / fabs(min_d));
			if (factor > max_factor)
				factor = max_factor;
			if (d_up > min_d)
				stick_pitch = - max_flight_pitch * reverse * r_max_factor * factor;
			if (d_up < -min_d)
				stick_pitch = + max_flight_pitch * reverse * r_max_factor * factor;
		}

		if (accuracy >= COMBAT_AI_ISNT_AWFUL)
		{
			// don't overshoot target (helps accuracy at low frame rates)
			if (fabs(d_right) < fabs(stick_roll) * delta_t) 
			{
				stick_roll = fabs(d_right) / delta_t * (stick_roll<0 ? -1 : 1);
			}
			if (fabs(d_up) < fabs(stick_pitch) * delta_t) 
			{
				stick_pitch = fabs(d_up) / delta_t * (stick_pitch<0 ? -0.9 : 0.9);
			}
		}

	}
	/*	#  note
		Eric 9-9-2010: Removed the "reverse" variable from the stick_roll calculation. This was mathematical wrong and
		made the ship roll in the wrong direction, preventing the ship to fly away in a straight line from the target.
		This means all the places were a jink was set, this jink never worked correctly. The main reason a ship still
		managed to turn at close range was probably by the fail-safe mechanisme with the "pitching_over" variable.
		The jink was programmed to do nothing within 500 meters of the ship and just fly away in direct line from the target
		in that range. Because of the bug the ships always rolled to the wrong side needed to fly away in direct line
		resulting in making it a difficult target.
		After fixing the bug, the ship realy flew away in direct line during the first 500 meters, making it a easy target
		for the player. All jink settings are retested and changed to give a turning behaviour that felt like the old
		situation, but now more deliberately set.
	 */

	// end rule-of-thumb manoeuvres
	stick_yaw = 0.0;
	
	applySticks(delta_t);

	if (retreat)
		d_forward *= d_forward;	// make positive AND decrease granularity

	if (d_forward < 0.0)
		return 0.0;

	if ((!flightRoll)&&(!flightPitch))	// no correction
		return 1.0;

	return d_forward;
}


double ShipEntity::trackSideTarget(double delta_t, bool leftside)
{
	Entity *target = primaryTarget();

	if (!target)   // leave now!
	{
		noteLostTargetAndGoIdle();	// NOTE: was AI message: rather than reactToMessage:
		return 0.0;
	}

	if (!canStillTrackPrimaryTarget())
	{
		noteLostTargetAndGoIdle();	// NOTE: was AI message: rather than reactToMessage:
		return 0.0;
	}


	if (scanClass == CLASS_MISSILE) // never?
		return missileTrackPrimaryTarget(delta_t);

	GLfloat  d_forward, d_up, d_right;
	
	Vector  relPos = HPVectorToVector(HPvector_subtract(calculateTargetPosition(), position));


	if (!vector_equal(relPos, kZeroVector))  relPos = vector_normal(relPos);
	else  relPos.z = 1.0;

// worse shots with side lasers than fore/aft, in general

	double	max_cos = currentAimTolerance();

	stick_roll = 0.0;	//desired roll and pitch
	stick_pitch = 0.0;
	stick_yaw = 0.0;

	double reverse = (leftside)? -1.0: 1.0;

	double min_d = 0.004;
	if (accuracy >= COMBAT_AI_TRACKS_CLOSER) 
	{
		min_d = 0.002;
	}
	int max_factor = 8;
	double r_max_factor = 0.125;

	d_right		=   dot_product(relPos, v_right);
	d_up		=   dot_product(relPos, v_up);
	d_forward   =   dot_product(relPos, v_forward);	// == cos of angle between v_forward and vector to target

	if (d_right * reverse > max_cos)	// on_target!
	{
		return d_right * reverse;
	}

	// begin rule-of-thumb manoeuvres
	stick_pitch = 0.0;
	stick_roll = 0.0;
	stick_yaw = 0.0;

	// check if we are flying toward the destination..
	if ((d_right * reverse < max_cos))	// not on course so we must adjust controls..
	{
		if (d_right < -max_cos)  // hack to avoid just pointing away from the destination
		{
			d_forward = min_d * 2.0;
		}

		if (d_forward > min_d)
		{
			int factor = sqrt(fabs(d_up) / fabs(min_d));
			if (factor > max_factor)
				factor = max_factor;
			if (d_up > min_d)
				stick_pitch = + max_flight_pitch * r_max_factor * factor; // note#
			if (d_up < -min_d)
				stick_pitch = - max_flight_pitch * r_max_factor * factor; // note#
		}
		if (d_forward < -min_d)
		{
			int factor = sqrt(fabs(d_up) / fabs(min_d));
			if (factor > max_factor)
				factor = max_factor;
			if (d_up > min_d)
				stick_pitch = + max_flight_pitch * r_max_factor * factor; // note#
			if (d_up < -min_d)
				stick_pitch = - max_flight_pitch * r_max_factor * factor; // note#
		}

		if (fabs(stick_pitch) == 0.0 || fabs(d_forward) > 0.5)
		{
			stick_pitch = 0.0;
			int factor = sqrt(fabs(d_forward) / fabs(min_d));
			if (factor > max_factor)
				factor = max_factor;
			if (d_forward > min_d)
				stick_yaw = - max_flight_yaw * reverse * r_max_factor * factor;
			if (d_forward < -min_d)
			{
				if (factor < max_factor/2.0) // compensate for forward thrust
					factor *= 2.0;
				stick_yaw = + max_flight_yaw * reverse * r_max_factor * factor;
			}
		}
	}


	// end rule-of-thumb manoeuvres

	applySticks(delta_t);

	if ((!flightPitch)&&(!flightYaw))	// no correction
		return 1.0;

	return d_right * reverse;
}




// Slice 26 of docs/phases/3-slices/ShipEntity.md (bead oo-v92af): missile and destination tracking,
// collision exceptions, defence targets, ranges. Members of the C++ ship, called directly, since
// bead oo-9ht.144 deleted the facade (ADR-0056 amendment oo-9ht.144).

double ShipEntity::missileTrackPrimaryTarget(double delta_t)
{
	Vector  relPos;
	GLfloat  d_forward, d_up, d_right;
	::ShipEntity  *target = oo::ToShip(primaryTarget());
	BOOL	inPursuit = YES;

	if (!target || !(target != nullptr ? target->getIsShip() : false))   // leave now!
		return 0.0;

	double  damping = 0.5 * delta_t;

	stick_roll = 0.0;	//desired roll and pitch
	stick_pitch = 0.0;
	stick_yaw = 0.0;

	relPos = vectorTo(target);
	
	// Adjust missile course by taking into account target's velocity and missile
	// accuracy. Modification on original code contributed by Cmdr James.

	float missileSpeed = (float)speed();

	// Avoid getting ourselves in a divide by zero situation by setting a missileSpeed
	// low threshold. Arbitrarily chosen 0.01, since it seems to work quite well.
	// Missile accuracy is already clamped within the 0.0 to 10.0 range at initialization,
	// but doing these calculations every frame when accuracy equals 0.0 just wastes cycles.
	if (missileSpeed > 0.01f && accuracy > 0.0f)
	{
		inPursuit = (dot_product((target != nullptr ? target->forwardVector() : Vector{}), v_forward) > 0.0f);
		if (inPursuit)
		{
			Vector leading = (target != nullptr ? target->getVelocity() : Vector{}); 
			float lead = magnitude(relPos) / missileSpeed; 
			
			// Adjust where we are going to take into account target's velocity.
			// Use accuracy value to determine how well missile will track target.
			relPos.x += (lead * leading.x * (accuracy / 10.0f)); 
			relPos.y += (lead * leading.y * (accuracy / 10.0f)); 
			relPos.z += (lead * leading.z * (accuracy / 10.0f));
		}
	}

	if (!vector_equal(relPos, kZeroVector))  relPos = vector_normal(relPos);
	else  relPos.z = 1.0;

	d_right		=   dot_product(relPos, v_right);		// = cosine of angle between angle to target and v_right
	d_up		=   dot_product(relPos, v_up);		// = cosine of angle between angle to target and v_up
	d_forward   =   dot_product(relPos, v_forward);	// = cosine of angle between angle to target and v_forward

	// begin rule-of-thumb manoeuvres

	stick_roll = 0.0;

	if (pitching_over)
		pitching_over = (stick_pitch != 0.0);

	if ((d_forward < -pitch_tolerance) && (!pitching_over))
	{
		pitching_over = YES;
		if (d_up >= 0)
			stick_pitch = -max_flight_pitch;
		if (d_up < 0)
			stick_pitch = max_flight_pitch;
	}

	if (pitching_over)
	{
		pitching_over = (d_forward < 0.5);
	}
	else
	{
		stick_pitch = -max_flight_pitch * d_up;
		stick_roll = -max_flight_roll * d_right;
	}

	// end rule-of-thumb manoeuvres

	// apply damping
	if (flightRoll < 0)
		flightRoll += (flightRoll < -damping) ? damping : -flightRoll;
	if (flightRoll > 0)
		flightRoll -= (flightRoll > damping) ? damping : flightRoll;
	if (flightPitch < 0)
		flightPitch += (flightPitch < -damping) ? damping : -flightPitch;
	if (flightPitch > 0)
		flightPitch -= (flightPitch > damping) ? damping : flightPitch;

	
	applySticks(delta_t);

	//
	//  return target confidence 0.0 .. 1.0
	//
	if (d_forward < 0.0)
		return 0.0;
	return d_forward;
}


double ShipEntity::trackDestination(double delta_t, bool retreat)
{
	Vector  relPos;
	GLfloat  d_forward, d_up, d_right;

	BOOL	we_are_docking = !dockingInstructions.isNull();

	stick_roll = 0.0;	//desired roll and pitch
	stick_pitch = 0.0;
	stick_yaw = 0.0;

	double reverse = 1.0;
	double reversePlayer = 1.0;

	double min_d = 0.004;
	double max_cos = MAX_COS;  // should match default value of max_cos in behaviour_fly_to_destination!
	double precision = we_are_docking ? 0.25 : 0.9025; // lower values force a direction closer to the target. (resp. 50% and 95% within range)

	if (retreat)
		reverse = -reverse;

	if (isPlayer)
	{
		reverse = -reverse;
		reversePlayer = -1;
	}

	relPos = HPVectorToVector(HPvector_subtract(_destination, position));
	double range2 = magnitude2(relPos);
	double desired_range2 = desired_range*desired_range;
	
	/*	2009-7-18 Eric: We need to aim well inide the desired_range sphere round the target and not at the surface of the sphere. 
		Because of the framerate most ships normally overshoot the target and they end up flying clearly on a path
		through the sphere. Those ships give no problems, but ships with a very low turnrate will aim close to the surface and will than
		have large trouble with reaching their destination. When those ships enter the slowdown range, they have almost no speed vector
		in the direction of the target. I now used 95% of desired_range to aim at, but a smaller value might even be better. 
	*/
	if (range2 > desired_range2) 
	{
		max_cos = sqrt(1 - precision * desired_range2/range2);  // Head for a point within 95% of desired_range.
		if (max_cos >= 0.99999)
		{
			max_cos = 0.99999;
		}
	}

	if (!vector_equal(relPos, kZeroVector))  relPos = vector_normal(relPos);
	else  relPos.z = 1.0;

	d_right		=   dot_product(relPos, v_right);
	d_up		=   dot_product(relPos, v_up);
	d_forward   =   dot_product(relPos, v_forward);	// == cos of angle between v_forward and vector to target

	// begin rule-of-thumb manoeuvres
	stick_pitch = 0.0;
	stick_roll = 0.0;
	
	// pitching_over is currently only set in behaviour_formation_form_up, for escorts and in avoidCollision.
	// This allows for immediate pitch corrections instead of first waiting untill roll has completed.
	if (pitching_over)
	{
		if (reverse * d_up > 0) // pitch up
			stick_pitch = -max_flight_pitch;
		else
			stick_pitch = max_flight_pitch;
		pitching_over = (reverse * d_forward < 0.707);
	}

	// check if we are flying toward (or away from) the destination..
	if ((d_forward < max_cos)||(retreat))	// not on course so we must adjust controls..
	{

		if (d_forward <= -max_cos || (retreat && d_forward >= max_cos))  // hack to avoid just flying away from the destination
		{
			d_up = min_d * 2.0;
		} 

		if (d_up > min_d)
		{
			int factor = sqrt(fabs(d_right) / fabs(min_d));
			if (factor > 8)
				factor = 8;
			if (d_right > min_d)
				stick_roll = - max_flight_roll * reversePlayer * 0.125 * factor;  // only reverse sign for the player;
			if (d_right < -min_d)
				stick_roll = + max_flight_roll * reversePlayer * 0.125 * factor;
			if (fabs(d_right) < fabs(stick_roll) * delta_t) 
				stick_roll = fabs(d_right) / delta_t * (stick_roll<0 ? -1 : 1); // don't overshoot heading
		}

		if (d_up < -min_d)
		{
			int factor = sqrt(fabs(d_right) / fabs(min_d));
			if (factor > 8)
				factor = 8;
			if (d_right > min_d)
				stick_roll = + max_flight_roll * reversePlayer * 0.125 * factor;  // only reverse sign for the player;
			if (d_right < -min_d)
				stick_roll = - max_flight_roll * reversePlayer * 0.125 * factor;
			if (fabs(d_right) < fabs(stick_roll) * delta_t) 
				stick_roll = fabs(d_right) / delta_t * (stick_roll<0 ? -1 : 1); // don't overshoot heading
		}

		if (stick_roll == 0.0)
		{
			int factor = sqrt(fabs(d_up) / fabs(min_d));
			if (factor > 8)
				factor = 8;
			if (d_up > min_d)
				stick_pitch = - max_flight_pitch * reverse * 0.125 * factor;  //pitch_pitch * reverse;
			if (d_up < -min_d)
				stick_pitch = + max_flight_pitch * reverse * 0.125 * factor;
			if (fabs(d_up) < fabs(stick_pitch) * delta_t) 
				stick_pitch = fabs(d_up) / delta_t * (stick_pitch<0 ? -1 : 1); // don't overshoot heading
		}

		if (stick_pitch == 0.0)
		{
			// not sufficiently on course yet, but min_d is too high
			// turn anyway slightly to adjust
			stick_pitch = 0.01;
		}
	}

	if (we_are_docking && docking_match_rotation && (d_forward > max_cos))
	{
		/* we are docking and need to consider the rotation/orientation of the docking port */
		::StationEntity* station_for_docking = oo::ToStation(targetStation());

		if ((station_for_docking)&&(station_for_docking->isStation))
		{
			stick_roll = rollToMatchUp((station_for_docking != nullptr ? station_for_docking->portUpVectorForShip(this) : Vector{}), (station_for_docking != nullptr ? station_for_docking->getFlightRoll() : 0.0f));
		}
	}

	// end rule-of-thumb manoeuvres

	applySticks(delta_t);

	if (retreat)
		d_forward *= d_forward;	// make positive AND decrease granularity

	if (d_forward < 0.0)
		return 0.0;

	if ((!flightRoll)&&(!flightPitch))	// no correction
		return 1.0;

	return d_forward;
}


GLfloat ShipEntity::rollToMatchUp(Vector up_vec, GLfloat match_roll)
{
	GLfloat cosTheta = dot_product(up_vec, v_up);	// == cos of angle between up vectors
	GLfloat sinTheta = dot_product(up_vec, v_right);

	if (!isPlayer)
	{
		match_roll = -match_roll;	// make necessary corrections for a different viewpoint
		sinTheta = -sinTheta;
	}

	if (cosTheta < 0.0f)
	{
		cosTheta = -cosTheta;
		sinTheta = -sinTheta;
	}

	if (sinTheta > 0.0f)
	{
		// increase roll rate
		return cosTheta * cosTheta * match_roll + sinTheta * sinTheta * max_flight_roll;
	}
	else
	{
		// decrease roll rate
		return cosTheta * cosTheta * match_roll - sinTheta * sinTheta * max_flight_roll;
	}
}


GLfloat ShipEntity::rangeToDestination()
{
	return HPdistance(position, _destination);
}


std::vector<oo::EntityHold> ShipEntity::collisionExceptions()
{
	// The live ones, in the weak set's order (empty when there are none).
	std::vector<oo::EntityHold> result;
	for (const oo::Ref<Entity> &exception : _collisionExceptions.allObjects())  result.emplace_back(exception.get());
	return result;
}


void ShipEntity::addCollisionException(::ShipEntity *ship)
{
	_collisionExceptions.add(ship);	// (was allocated lazily, as an OOWeakSet of the ships' objects)
}


void ShipEntity::removeCollisionException(::ShipEntity *ship)
{
	_collisionExceptions.remove(ship);
}


bool ShipEntity::collisionExceptedFor(::ShipEntity *ship)
{
	return _collisionExceptions.contains(ship);
}


NSUInteger ShipEntity::defenseTargetCount()
{
	return _defenseTargets.count();
}


std::vector<oo::EntityHold> ShipEntity::allDefenseTargets()
{
	std::vector<oo::EntityHold> result;
	for (const oo::Ref<Entity> &target : _defenseTargets.allObjects())  result.emplace_back(target.get());
	return result;
}


std::vector<oo::EntityHold> ShipEntity::defenseTargets()
{
	// What the weak set's enumerator gave: the live targets, in its order.
	std::vector<oo::EntityHold> targets;
	for (const oo::Ref<Entity> &target : _defenseTargets.allObjects())  targets.emplace_back(target.get());
	return targets;
}


// The C++ entity since bead oo-9ht.39.23; the weak set holds it since bead oo-9ht.22.3.
bool ShipEntity::addDefenseTarget(Entity *target)
{
	if (defenseTargetCount() >= MAX_TARGETS)
	{
		return NO;
	}
	// primary target can be a wormhole, defense targets shouldn't be
	if (target == nullptr || isDefenseTarget(target) || !target->getIsShip())
	{
		return NO;
	}
	_defenseTargets.add(target);	// (was allocated lazily, as an OOWeakSet of the targets' objects)
	return YES;
}


void ShipEntity::validateDefenseTargets()
{
	// iterate a copy as we'll be modifying original during enumeration
	for (const auto &targetRef : allDefenseTargets())
	{
		Entity *target = targetRef.get();
		if ((target != nullptr ? target->status() : OOEntityStatus{}) == STATUS_DEAD)
		{
			removeDefenseTarget(target);
		}
	}
}


bool ShipEntity::isDefenseTarget(Entity *target)
{
	return _defenseTargets.contains(target);
}


// exposed to AI (as alias of clearDefenseTargets)
void ShipEntity::removeAllDefenseTargets()
{
	_defenseTargets.removeAll();
}


void ShipEntity::removeDefenseTarget(Entity *target)
{
	_defenseTargets.remove(target);
}


double ShipEntity::rangeToPrimaryTarget()
{
	return rangeToSecondaryTarget(primaryTarget());
}


double ShipEntity::rangeToSecondaryTarget(Entity *target)
{
	double dist;
	Vector delta;
	if (target == nullptr)   // leave now!
		return 0.0;
	delta = HPVectorToVector(HPvector_subtract(target->position, position));
	dist = magnitude(delta);
	dist -= target->collision_radius;
	dist -= collision_radius;
	return dist;
}


double ShipEntity::approachAspectToPrimaryTarget()
{
	Vector delta;
	Entity *target = primaryTarget();
	if (target == nil || !oo::EntityIsShip(target))   // leave now!
	{
		return 0.0;
	}
	::ShipEntity  *ship_target = oo::ToShip(target);

	delta = HPVectorToVector(HPvector_subtract(position, target->position));
	
	return dot_product(vector_normal(delta), ship_target->v_forward);
}


bool ShipEntity::hasProximityAlertIgnoringTarget(bool ignore_target)
{
	if ((proximityAlert() != nullptr)&&(!ignore_target || (proximityAlert() != primaryTarget())))
	{
		return YES;
	}
	return NO;
}




// Slice 27 of docs/phases/3-slices/ShipEntity.md (bead oo-pnfyp): aim tolerance, sun glare, main
// weapons and turret fire, laser colours. Members of the C++ ship, called directly, since bead
// oo-9ht.144 deleted the facade (ADR-0056 amendment oo-9ht.144).

// lower is better. Defines angular size of circle in which ship
// thinks is on target
GLfloat ShipEntity::currentAimTolerance()
{
	GLfloat basic_aim = aim_tolerance;
	GLfloat best_cos = 0.99999; // ~45m in 10km (track won't go better than 40)
	if (accuracy >= COMBAT_AI_ISNT_AWFUL)
	{ 
		// better general targeting
		best_cos = 0.999999; // ~14m in 10km (track won't go better than 10)
		// if missing, aim better!
		basic_aim /= 1.0 + ((GLfloat)missedShots() / 4.0);
	}
	if (accuracy >= COMBAT_AI_TRACKS_CLOSER)
	{ 
		// deadly shots
		best_cos = 0.9999999; // ~4m in 10km (track won't go better than 4)
		// and start with extremely good aim circle
		basic_aim /= 5.0;
	}
	if (currentWeaponFacing == WEAPON_FACING_AFT && accuracy < COMBAT_AI_ISNT_AWFUL)
	{ // bad shots with aft lasers
		basic_aim *= 1.3;
	}
	else if (currentWeaponFacing == WEAPON_FACING_PORT || currentWeaponFacing == WEAPON_FACING_STARBOARD)
	{ // everyone a bit worse with side lasers
		if (accuracy < COMBAT_AI_ISNT_AWFUL) 
		{ // especially these
			basic_aim *= 1.3 + randf();
		}
		else
		{
			basic_aim *= 1.3;
		}
	}
	// only apply glare if ship is not shadowed
	if (isSunlit) {
		::OOSunEntity *sun = (UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr);
		if (sun)
		{
			GLfloat sunGlareAngularSize = atan((sun != nullptr ? sun->radius() : 0.0)/HPdistance(getPosition(), (sun != nullptr ? sun->getPosition() : HPVector{}))) * SUN_GLARE_MULT_FACTOR + (SUN_GLARE_ADD_FACTOR);
			GLfloat glareLevel = lookingAtSunWithThresholdAngleCos(cos(sunGlareAngularSize)) * (1.0f - getSunGlareFilter());
			if (glareLevel > 0.1f)
			{
				// looking towards sun can seriously mess up aim (glareLevel 0..1)
				basic_aim *= (1.0 + glareLevel*3.0);
//				OO_LOG("aim.debug", "Sun glare affecting aim: {:f} for {}", glareLevel, oo::DescriptionOf(self));
				if (glareLevel > 0.5f)
				{
					// strong glare makes precise targeting impossible
					best_cos = 0.99999;
				}
			}
		}
	}


	GLfloat max_cos = sqrt(1-(basic_aim * basic_aim / 100000000.0));

	if (max_cos < best_cos)
	{
		return max_cos;
	}
	return best_cos;
}


// much simpler than player version
GLfloat ShipEntity::lookingAtSunWithThresholdAngleCos(GLfloat thresholdAngleCos)
{
	::OOSunEntity	*sun = (UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr);
	GLfloat measuredCos = 999.0f, measuredCosAbs;
	GLfloat sunBrightness = 0.0f;
	Vector relativePosition, unitRelativePosition;
	
	if (EXPECT_NOT(!sun))  return 0.0f;
	
	relativePosition = HPVectorToVector(HPvector_subtract(getPosition(), (sun != nullptr ? sun->getPosition() : HPVector{})));
	unitRelativePosition = vector_normal_or_zbasis(relativePosition);
	switch (currentWeaponFacing)
	{
		case WEAPON_FACING_FORWARD:
			measuredCos = -dot_product(unitRelativePosition, v_forward);
			break;
		case WEAPON_FACING_AFT:
			measuredCos = +dot_product(unitRelativePosition, v_forward);
			break;
		case WEAPON_FACING_PORT:
			measuredCos = +dot_product(unitRelativePosition, v_right);
			break;
		case WEAPON_FACING_STARBOARD:
			measuredCos = -dot_product(unitRelativePosition, v_right);
			break;
		default:
			break;
	}
	measuredCosAbs = fabs(measuredCos);
	if (thresholdAngleCos <= measuredCosAbs && measuredCosAbs <= 1.0f)	// angle from viewpoint to sun <= desired threshold
	{
		sunBrightness =  (measuredCos - thresholdAngleCos) / (1.0f - thresholdAngleCos);
		if (sunBrightness < 0.0f)  sunBrightness = 0.0f;
	}
	return sunBrightness * sunBrightness * sunBrightness;
}


bool ShipEntity::onTarget(OOWeaponFacing direction, OOWeaponType weapon_type)
{
	// initialize dq to a value that would normally return NO; dq is handled inside the defaultless switch(direction) statement
	// and should alaways be recalculated anyway. Initialization here needed to silence compiler warning - Nikos 20120526
	GLfloat dq = -1.0f;
	GLfloat d2, radius, astq;
	Vector rel_pos, urp;
	if ((weapon_type != nullptr ? weapon_type->isTurretLaser() : false))
	{
		return YES;
	}
	
	Entity *target = primaryTarget();
	if (target == nil)  return NO;
	if (oo::EntityStatus(target) == STATUS_DEAD)  return NO;
	
	if (isSunlit && (target->isSunlit == NO) && (randf() < 0.75))
	{
		return NO;	// 3/4 of the time you can't see from a lit place into a darker place
	}
	radius = target->collision_radius;
	rel_pos = HPVectorToVector(HPvector_subtract(calculateTargetPosition(), position));
	d2 = magnitude2(rel_pos);
	urp = vector_normal_or_zbasis(rel_pos);
	
	switch (direction)
	{
		case WEAPON_FACING_FORWARD:
			dq = +dot_product(urp, v_forward);		// cosine of angle between v_forward and unit relative position
			break;
			
		case WEAPON_FACING_AFT:
			dq = -dot_product(urp, v_forward);		// cosine of angle between v_forward and unit relative position
			break;
			
		case WEAPON_FACING_PORT:
			dq = -dot_product(urp, v_right);		// cosine of angle between v_right and unit relative position
			break;
			
		case WEAPON_FACING_STARBOARD:
			dq = +dot_product(urp, v_right);		// cosine of angle between v_right and unit relative position
			break;
			
		case WEAPON_FACING_NONE:
			break;
	}

	if (dq < 0.0)  return NO;
	
	GLfloat aim = currentAimTolerance();
	if (dq > aim*aim) return YES;

	// cosine of 1/3 of half angle subtended by target (mostly they'll
	// fire sooner anyway due to currentAimTolerance, but this should
	// almost always be a solid hit)
	astq = sqrt(1.0 - radius * radius / (d2 * 9));	

	return (fabs(dq) >= astq);
}


bool ShipEntity::fireWeapon(OOWeaponType weapon_type, OOWeaponFacing direction, double range)
{
	weapon_temp = 0.0;
	switch (direction)
	{
		case WEAPON_FACING_FORWARD:
			weapon_temp = forward_weapon_temp;
			break;
			
		case WEAPON_FACING_AFT:
			weapon_temp = aft_weapon_temp;
			break;
			
		case WEAPON_FACING_PORT:
			weapon_temp = port_weapon_temp;
			break;
			
		case WEAPON_FACING_STARBOARD:
			weapon_temp = starboard_weapon_temp;
			break;
			
		case WEAPON_FACING_NONE:
			break;
	}
	if (weapon_temp / NPC_MAX_WEAPON_TEMP >= WEAPON_COOLING_CUTOUT) return NO;

	NSUInteger multiplier = 1;
	if (_multiplyWeapons)
	{
		// multiple fitted
		multiplier = laserPortOffset(direction).size();
	}

	if (energy <= weapon_energy_use * multiplier) return NO;
	if (shotTime() < weapon_recharge_rate)  return NO;
	if (!(weapon_type != nullptr ? weapon_type->isTurretLaser() : false))
	{ // thargoid laser may just pick secondary target in this case
		if (range > randf() * weaponRange * (accuracy+7.5))  return NO;
		if (range > weaponRange)  return NO;
	}
	if (!onTarget(direction, weapon_type))  return NO;
	
	BOOL fired = NO;
	if (!isWeaponNone(weapon_type))
	{
		if ((weapon_type != nullptr ? weapon_type->isTurretLaser() : false))
		{
			fireDirectLaserShot(range);
			fired = YES;
		}
		else
		{
			fireLaserShotInDirection(direction, (weapon_type != nullptr ? weapon_type->identifier() : std::optional<std::string>()).value_or(""));
			fired = YES;
		}
	}

	if (fired)
	{
		energy -= weapon_energy_use * multiplier;
		switch (direction)
		{
			case WEAPON_FACING_FORWARD:
				forward_weapon_temp += weapon_shot_temperature * multiplier;
				break;
				
			case WEAPON_FACING_AFT:
				aft_weapon_temp += weapon_shot_temperature * multiplier;
				break;
				
			case WEAPON_FACING_PORT:
				port_weapon_temp += weapon_shot_temperature * multiplier;
				break;
				
			case WEAPON_FACING_STARBOARD:
				starboard_weapon_temp += weapon_shot_temperature * multiplier;
				break;
				
			case WEAPON_FACING_NONE:
				break;
		}
	}
	
	if (direction == WEAPON_FACING_FORWARD)
	{
		//can we fire lasers from our subentities?
		for (const auto &se : shipSubEntities())
		{
			if ((oo::ToShip(se.get()) != nullptr ? oo::ToShip(se.get())->fireSubentityLaserShot(range) : false))
			{
				fired = YES;
			}
		}
	}
	
	if (fired && cloaking_device_active && cloakPassive)
	{
		deactivateCloakingDevice();
	}
	
	return fired;
}


bool ShipEntity::fireMainWeapon(double range)
{
	// set the values from forward_weapon_type.
	// OXPs can override the default front laser energy damage.
	currentWeaponFacing = WEAPON_FACING_FORWARD;
	setWeaponDataFromType(forward_weapon_type);

//  weapon damage override no longer effective
//	weapon_damage = weapon_damage_override;
	
	BOOL result = fireWeapon(forward_weapon_type, WEAPON_FACING_FORWARD, range);
	if (isWeaponNone(forward_weapon_type))
	{
		// need to check subentities to avoid AI oddities
		// will already have fired them by now, though
		OOWeaponType 			weapon_type = nil;
		BOOL hasTurrets = NO;
		for (const auto &sub : shipSubEntities())
		{
			if (!isWeaponNone(weapon_type))  break;
			::ShipEntity *se = oo::ToShip(sub.get());
			weapon_type = se->forward_weapon_type;
			weapon_temp = se->forward_weapon_temp;
			if (se->behaviour == BEHAVIOUR_TRACK_AS_TURRET)
			{
				hasTurrets = YES;
			}
		}
		if (isWeaponNone(weapon_type) && hasTurrets)
		{ /* no forward weapon but has turrets, so set up range calculations accordingly
		     note: this was hard-coded to 10000.0, although turrets have a notably 
		     shorter range. We are using a multiplier of 1.667 in order to not change
		     something that already works, but probably it would be best to use
		     TURRET_SHOT_RANGE * COMBAT_WEAPON_RANGE_FACTOR here
		  */
			 weaponRange = TURRET_SHOT_RANGE * 1.667;
		}
		else
		{
			setWeaponDataFromType(weapon_type);
		}
	}
	return result;
}


bool ShipEntity::fireAftWeapon(double range)
{
	// set the values from aft_weapon_type.
	currentWeaponFacing = WEAPON_FACING_AFT;
	setWeaponDataFromType(aft_weapon_type);
	
	return fireWeapon(aft_weapon_type, WEAPON_FACING_AFT, range);
}


bool ShipEntity::firePortWeapon(double range)
{
	// set the values from port_weapon_type.
	currentWeaponFacing = WEAPON_FACING_PORT;
	setWeaponDataFromType(port_weapon_type);
	
	return fireWeapon(port_weapon_type, WEAPON_FACING_PORT, range);
}


bool ShipEntity::fireStarboardWeapon(double range)
{
	// set the values from starboard_weapon_type.
	currentWeaponFacing = WEAPON_FACING_STARBOARD;
	setWeaponDataFromType(starboard_weapon_type);
	
	return fireWeapon(starboard_weapon_type, WEAPON_FACING_STARBOARD, range);
}


OOTimeDelta ShipEntity::shotTime()
{
	return shot_time;
}


void ShipEntity::resetShotTime()
{
	shot_time = 0.0;
}


bool ShipEntity::fireTurretCannon(double range)
{
	if (shotTime() < weapon_recharge_rate)
		return NO;
	if (range > weaponRange * 1.01) // 1% more than max range - open up just slightly early
		return NO;
	::ShipEntity *root = oo::ToShip(rootShipEntity());
	if ((root != nullptr ? root->getIsPlayer() : false) && !(PLAYER != nullptr ? PLAYER->weaponsOnline() : false))
		return NO;

	if ((root != nullptr ? root->isCloaked() : false) && (root != nullptr ? root->getCloakPassive() : false))
	{
		// can't fire turrets while cloaked
		return NO;
	}

	Vector		vel;	
	HPVector		origin = getPosition();

	Entity		*last = nullptr;
	Entity		*father = oo::LiveEntity(oo::WeakRef<Entity>(parentEntity()));	// null once its object has gone, as the object read +0 was nil (bead oo-xn1j1)
	OOMatrix	r_mat;

	vel = vector_forward_from_quaternion(orientation);		// Facing
	// adjust velocity and position vectors to absolute coordinates
	while ((father)&&(father != last) && (father != nullptr))	// (Entity *)NO_TARGET
	{
		r_mat = father->drawRotationMatrix();
		origin = HPvector_add(OOHPVectorMultiplyMatrix(origin, r_mat), father->getPosition());
		vel = OOVectorMultiplyMatrix(vel, r_mat);
		last = father;
		if (!oo::EntityIsSubEntity(last)) break;
		father = oo::LiveOwner(father);	// [father owner]
	}
	
	origin = HPvector_add(origin, vectorToHPVector(vector_multiply_scalar(vel, collision_radius + 0.5)));	// Start just outside collision sphere
	vel = vector_multiply_scalar(vel, TURRET_SHOT_SPEED);	// Shot velocity
	
	Entity *shot = oo::MadeEntity(OOPlasmaShotEntity::shotWithPosition(origin,
																			vel,
																			weapon_damage,
																			weaponRange/TURRET_SHOT_SPEED,
																			laser_color.get()));
	
	if (UNIVERSE != nullptr)  UNIVERSE->addEntity(shot);
	shot->setOwner(rootShipEntity());	// has to be done AFTER adding shot to the UNIVERSE
	
	resetShotTime();
	return YES;
}


void ShipEntity::setLaserColor(::OOColor *color)
{
	if (color)
	{
		laser_color = oo::Ref<OOColor>(color);
	}
}


void ShipEntity::setExhaustEmissiveColor(::OOColor *color)
{
	if (color)
	{
		exhaust_emissive_color = oo::Ref<OOColor>(color);
	}
}


::OOColor *ShipEntity::laserColor()
{
	return laser_color.get();
}


::OOColor *ShipEntity::exhaustEmissiveColor()
{
	return exhaust_emissive_color.get();
}




// Slice 28 of docs/phases/3-slices/ShipEntity.md (bead oo-40ocf): laser shots, missed shots,
// sparks, missile launch decision. Members of the C++ ship, called directly, since bead oo-9ht.144
// deleted the facade (ADR-0056 amendment oo-9ht.144).

bool ShipEntity::fireSubentityLaserShot(double range)
{
	setShipHitByLaser(nullptr);
	
	if (isWeaponNone(forward_weapon_type))  return NO;
	setWeaponDataFromType(forward_weapon_type);
	
	::ShipEntity *parent = oo::ToShip(owner());
	OOCAssert((parent != nullptr ? parent->isShipWithSubEntityShip(this) : false), "-fireSubentityLaserShot: called on ship which is not a subentity.");

	// subentity lasers still draw power from the main entity
	if ((parent != nullptr ? parent->getEnergy() : 0.0f) <= weapon_energy_use) return NO;
	if (shotTime() < weapon_recharge_rate)  return NO;
	if (forward_weapon_temp > WEAPON_COOLING_CUTOUT * NPC_MAX_WEAPON_TEMP)  return NO;
	if (range > weaponRange)  return NO;

	forward_weapon_temp += weapon_shot_temperature;
	if (parent != nullptr)  parent->setEnergy(((parent != nullptr ? parent->getEnergy() : 0.0f) - weapon_energy_use));

	GLfloat hitAtRange = weaponRange;
	OOWeaponFacing direction = WEAPON_FACING_FORWARD;
	::ShipEntity *victim = (UNIVERSE != nullptr ? UNIVERSE->firstShipHitByLaserFromShip(this, direction, kZeroVector, &hitAtRange) : (::ShipEntity *)nil);
	setShipHitByLaser(victim);
	
	const oo::Ref<OOLaserShotEntity> shot = OOLaserShotEntity::laserFromShip(this, direction, kZeroVector);
	Entity *shotObjC = oo::MadeEntity(shot);	// the shot, given its object (bead oo-9ht.39.26)
	shot->setColor(laser_color.get());
	shot->setScanClass(CLASS_NO_DRAW);
	
	if (victim != nil)
	{
		adjustMissedShots(-1);
		
		if (getIsPlayer())
		{
			if (PLAYER != nullptr)  PLAYER->addRoleForAggression(victim);
		}

		::ShipEntity *subent = (victim != nullptr ? victim->subEntityTakingDamage() : (::ShipEntity *)nil);
		if (subent != nil && (victim != nullptr ? victim->getIsFrangible() : false))
		{
			// do 1% bleed-through damage...
			if (victim != nullptr)  victim->takeEnergyDamage(0.01 * weapon_damage, this, parent, (weaponTypeForFacing(WEAPON_FACING_FORWARD, YES) != nullptr ? weaponTypeForFacing(WEAPON_FACING_FORWARD, YES)->identifier() : std::optional<std::string>()).value_or(std::string()));
			victim = subent;
		}
		
		if (hitAtRange < weaponRange)
		{
			if (victim != nullptr)  victim->takeEnergyDamage(weapon_damage, this, parent, (weaponTypeForFacing(WEAPON_FACING_FORWARD, YES) != nullptr ? weaponTypeForFacing(WEAPON_FACING_FORWARD, YES)->identifier() : std::optional<std::string>()).value_or(std::string()));  // a very palpable hit
			
			shot->setRange(hitAtRange);
			Vector vd = vector_forward_from_quaternion(shot->getOrientation());
			HPVector flash_pos = HPvector_add(shot->getPosition(), vectorToHPVector(vector_multiply_scalar(vd, hitAtRange)));
			if (UNIVERSE != nullptr)  UNIVERSE->addLaserHitEffectsAt(flash_pos, victim, weapon_damage, laser_color.get());
		}
	}
	else
	{
		adjustMissedShots(+1);

		// see ATTACKER_MISSED section of main entity laser routine
		if (!(parent != nullptr ? parent->isCloaked() : false))
		{
			victim = oo::ToShip((parent != nullptr ? parent->primaryTarget() : (Entity *)nullptr));
			
			Vector shotDirection = vector_forward_from_quaternion(shot->getOrientation());
			Vector victimDirection = vector_normal(HPVectorToVector(HPvector_subtract((victim != nullptr ? victim->getPosition() : HPVector{}), (parent != nullptr ? parent->getPosition() : HPVector{}))));
			if (dot_product(shotDirection, victimDirection) > 0.995)	// Within 84.26 degrees
			{
				if (getIsPlayer())
				{
					if (PLAYER != nullptr)  PLAYER->addRoleForAggression(victim);
				}
				if (victim != nullptr)  victim->setPrimaryAggressor(parent);
				if (victim != nullptr)  victim->setFoundTarget(parent);
				if (victim != nullptr)  victim->reactToAIMessage("ATTACKER_MISSED", "attacker narrowly misses");
				if (victim != nullptr)  victim->doScriptEvent(OOJSID("shipBeingAttackedUnsuccessfully"), parent);

			}
		}
	}
	
	if (UNIVERSE != nullptr)  UNIVERSE->addEntity(shotObjC);
	resetShotTime();
	
	return YES;
}


bool ShipEntity::fireDirectLaserShot(double range)
{
	Entity *my_target = primaryTarget();
	if (my_target == nil)  return fireDirectLaserDefensiveShot();
	if (range > randf() * weaponRange * (accuracy+5.5))  return fireDirectLaserDefensiveShot();
	if (range > weaponRange)  return fireDirectLaserDefensiveShot();
	return fireDirectLaserShotAt(my_target);
}


bool ShipEntity::fireDirectLaserDefensiveShot()
{
	for (const auto &targetRef : defenseTargets())
	{
		Entity *target = targetRef.get();	// the snapshot keeps its object (bead oo-9ht.39.16)
		// can't fire defensively at cloaked ships
		if (target->getScanClass() == CLASS_NO_DRAW || (oo::ToShip(target) != nullptr ? oo::ToShip(target)->isCloaked() : false) || target->getEnergy() <= 0.0)
		{
			removeDefenseTarget(target);
		}
		else 
		{
			double range = rangeToSecondaryTarget(target);
			if (range < weaponRange)
			{
				return fireDirectLaserShotAt(target);
			}
			else if (range > scannerRange)
			{
				removeDefenseTarget(target);
			}
		}
	}
	return NO;
}


bool ShipEntity::fireDirectLaserShotAt(Entity *my_target)
{
	GLfloat			hit_at_range;
	double			range_limit2 = weaponRange*weaponRange;
	Vector			r_pos;
	
	r_pos = vector_normal_or_zbasis(vectorTo(my_target));

	Quaternion		q_laser = quaternion_rotation_between(r_pos, kBasisZVector);

	GLfloat acc_factor = (10.0 - accuracy) * 0.001;

	q_laser.x += acc_factor * (randf() - 0.5);	// randomise aim a little (+/- 0.005 at accuracy 0, never miss at accuracy 10)
	q_laser.y += acc_factor * (randf() - 0.5);
	q_laser.z += acc_factor * (randf() - 0.5);
	quaternion_normalize(&q_laser);

	Quaternion q_save = orientation;	// save rotation
	orientation = q_laser;			// face in direction of laser
	// weapon offset for thargoid lasers is always zero
	::ShipEntity *victim = (UNIVERSE != nullptr ? UNIVERSE->firstShipHitByLaserFromShip(this, WEAPON_FACING_FORWARD, kZeroVector, &hit_at_range) : (::ShipEntity *)nil);
	setShipHitByLaser(victim);
	orientation = q_save;			// restore rotation

	Vector  vel = vector_multiply_scalar(v_forward, flightSpeed);
	
	// do special effects laser line
	const oo::Ref<OOLaserShotEntity> shot = OOLaserShotEntity::laserFromShip(this, WEAPON_FACING_FORWARD, kZeroVector);
	Entity *shotObjC = oo::MadeEntity(shot);	// the shot, given its object (bead oo-9ht.39.26)
	shot->setColor(laser_color.get());
	shot->setScanClass(CLASS_NO_DRAW);
	shot->setPosition(position);
	shot->setOrientation(q_laser);
	shot->setVelocity(vel);
	
	if (victim != nil)
	{
		::ShipEntity *subent = (victim != nullptr ? victim->subEntityTakingDamage() : (::ShipEntity *)nil);
		if (subent != nil && (victim != nullptr ? victim->getIsFrangible() : false))
		{
			// do 1% bleed-through damage...
			if (victim != nullptr)  victim->takeEnergyDamage(0.01 * weapon_damage, this, this, (weaponTypeForFacing(WEAPON_FACING_FORWARD, YES) != nullptr ? weaponTypeForFacing(WEAPON_FACING_FORWARD, YES)->identifier() : std::optional<std::string>()).value_or(std::string()));
			victim = subent;
		}

		if (hit_at_range * hit_at_range < range_limit2)
		{
			if (victim != nullptr)  victim->takeEnergyDamage(weapon_damage, this, this, (weaponTypeForFacing(WEAPON_FACING_FORWARD, YES) != nullptr ? weaponTypeForFacing(WEAPON_FACING_FORWARD, YES)->identifier() : std::optional<std::string>()).value_or(std::string()));	// a very palpable hit

			shot->setRange(hit_at_range);
			Vector vd = vector_forward_from_quaternion(shot->getOrientation());
			HPVector flash_pos = HPvector_add(shot->getPosition(), vectorToHPVector(vector_multiply_scalar(vd, hit_at_range)));
			if (UNIVERSE != nullptr)  UNIVERSE->addLaserHitEffectsAt(flash_pos, victim, weapon_damage, laser_color.get());
		}
	}
	
	if (UNIVERSE != nullptr)  UNIVERSE->addEntity(shotObjC);
	
	resetShotTime();
	
	return YES;
}


std::vector<Vector> ShipEntity::laserPortOffset(OOWeaponFacing direction)
{
	std::vector<Vector> laserPortOffset;
	switch (direction)
	{
		case WEAPON_FACING_FORWARD:
		case WEAPON_FACING_NONE:
			laserPortOffset = forwardWeaponOffset;
			break;
			
		case WEAPON_FACING_AFT:
			laserPortOffset = aftWeaponOffset;
			break;
			
		case WEAPON_FACING_PORT:
			laserPortOffset = portWeaponOffset;
			break;
			
		case WEAPON_FACING_STARBOARD:
			laserPortOffset = starboardWeaponOffset;
			break;
	}
	return laserPortOffset;
}


bool ShipEntity::fireLaserShotInDirection(OOWeaponFacing direction, const std::string &weaponIdentifier)
{
	double			range_limit2 = weaponRange * weaponRange;
	GLfloat			hit_at_range;
	NSUInteger		i, barrels;
	Vector			vel = vector_multiply_scalar(v_forward, flightSpeed);
	const std::vector<Vector> laserPortOffsets = laserPortOffset(direction);
	oo::Ref<OOLaserShotEntity> shot;

	barrels = laserPortOffsets.size();
	std::vector<oo::Ref<OOLaserShotEntity>> shotEntities;
	shotEntities.reserve(barrels);

	
	GLfloat			effective_damage = weapon_damage;
	if (barrels > 1 && !_multiplyWeapons)
	{
		// then divide the shot power between the shots
		effective_damage /= (GLfloat)barrels;
	}
	
	for (i=0;i<barrels;i++)
	{
		Vector 			laserPortOffset = laserPortOffsets[i];
	
		last_shot_time = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0);

		::ShipEntity *victim = (UNIVERSE != nullptr ? UNIVERSE->firstShipHitByLaserFromShip(this, direction, laserPortOffset, &hit_at_range) : (::ShipEntity *)nil);
		setShipHitByLaser(victim);
	
		shot = OOLaserShotEntity::laserFromShip(this, direction, laserPortOffset);
		Entity *shotObjC = oo::MadeEntity(shot);	// the shot, given its object (bead oo-9ht.39.26)
		if (getIsPlayer())
		{
			shotEntities.emplace_back(shot);
		}
	
		shot->setColor(laser_color.get());
		shot->setScanClass(CLASS_NO_DRAW);
		shot->setVelocity(vel);
	
		if (victim != nil)
		{
			adjustMissedShots(-1);
			if (getIsPlayer())
			{
				if (PLAYER != nullptr)  PLAYER->addRoleForAggression(victim);
			}
		
			/*	CRASH in [victim->sub_entities containsObject:subent] here (1.69, OS X/x86).
				Analysis: Crash is in _freedHandler called from CFEqual, indicating either a dead
				object in victim->sub_entities or dead victim->subentity_taking_damage. I suspect
				the latter. Probable solution: dying subentities must cause parent to clean up
				properly. This was probably obscured by the entity recycling scheme in the past.
				Fix: made subentity_taking_damage a weak reference accessed via a method.
				-- Ahruman 20070706, 20080304
			*/
			::ShipEntity *subent = (victim != nullptr ? victim->subEntityTakingDamage() : (::ShipEntity *)nil);
			if (subent != nil && (victim != nullptr ? victim->getIsFrangible() : false))
			{
				// do 1% bleed-through damage...
				if (victim != nullptr)  victim->takeEnergyDamage(0.01 * effective_damage, this, this, weaponIdentifier);
				victim = subent;
			}
		
			if (hit_at_range * hit_at_range < range_limit2)
			{
				if (victim != nullptr)  victim->takeEnergyDamage(effective_damage, this, this, weaponIdentifier);	// a very palpable hit

				shot->setRange(hit_at_range);
				Vector vd = vector_forward_from_quaternion(shot->getOrientation());
				HPVector flash_pos = HPvector_add(shot->getPosition(), vectorToHPVector(vector_multiply_scalar(vd, hit_at_range)));
				if (UNIVERSE != nullptr)  UNIVERSE->addLaserHitEffectsAt(flash_pos, victim, effective_damage, laser_color.get());
			}
		}
		else
		{
			adjustMissedShots(+1);

			// shot missed
			if (!isCloaked())
			{
				victim = oo::ToShip(primaryTarget());
				if ((victim != nullptr ? victim->getIsShip() : false)) // it might not be - fixes crash bug
				{

					/* player currently gets a bit of an advantage here if
					 * they ambush without having their target actually
					 * targeted. Though in those circumstances they
					 * shouldn't be missing their first shot anyway. */
					if (dot_product(vector_forward_from_quaternion(shot->getOrientation()),vector_normal(vectorTo(victim))) > 0.995)
					{
						/* plausibly aimed at target. Allows reaction
						 * before attacker actually hits. But we need to
						 * be able to distinguish in AI from ATTACKED so
						 * that ships in combat aren't bothered by
						 * amateurs. So should only respond to
						 * ATTACKER_MISSED if not already fighting */
						if (getIsPlayer())
						{
							if (PLAYER != nullptr)  PLAYER->addRoleForAggression(victim);
						}
						if (victim != nullptr)  victim->setPrimaryAggressor(this);
						if (victim != nullptr)  victim->setFoundTarget(this);
						if (victim != nullptr)  victim->reactToAIMessage("ATTACKER_MISSED", "attacker narrowly misses");
						if (victim != nullptr)  victim->doScriptEvent(OOJSID("shipBeingAttackedUnsuccessfully"), this);
					}
				}
			}
		}
	
		if (UNIVERSE != nullptr)  UNIVERSE->addEntity(shotObjC);

	}
	
	if (getIsPlayer())
	{
		static_cast<PlayerEntity *>(this)->setLastShot(shotEntities);
	}
	
	resetShotTime();

	return YES;
}


void ShipEntity::adjustMissedShots(int delta)
{
	if (getIsSubEntity())
	{
		if (oo::ToShip(owner()) != nullptr)  oo::ToShip(owner())->adjustMissedShots(delta);
	}
	else
	{
		_missed_shots += delta;
		if (_missed_shots < 0)
		{
			_missed_shots = 0;
		}
	}
}


int ShipEntity::missedShots()
{
	if (getIsSubEntity())
	{
		return (oo::ToShip(owner()) != nullptr ? oo::ToShip(owner())->missedShots() : int{});
	}
	else
	{
		return _missed_shots;
	}
}


void ShipEntity::throwSparks()
{
	Vector offset =
	{
		randf() * (boundingBox.max.x - boundingBox.min.x) + boundingBox.min.x,
		randf() * (boundingBox.max.y - boundingBox.min.y) + boundingBox.min.y,
		randf() * boundingBox.max.z + boundingBox.min.z	// rear section only
	};
	HPVector origin = HPvector_add(position, vectorToHPVector(quaternion_rotate_vector(normalOrientation(), offset)));

	float	w = boundingBox.max.x - boundingBox.min.x;
	float	h = boundingBox.max.y - boundingBox.min.y;
	float	m = (w < h) ? 0.25 * w: 0.25 * h;
	
	float	sz = m * (1 + randf() + randf());	// half minimum dimension on average
	
	Vector vel = vector_multiply_scalar(HPVectorToVector(HPvector_subtract(origin, position)), 2.0);
	
	oo::Ref<OOColor>	color = OOColor::colorWithHue(0.08 + 0.17 * randf(), 1.0, 1.0, 1.0);
	
	Entity *spark = oo::MadeEntity(OOSparkEntity::sparkWithPosition(origin,
																		 vel,
																		 2.0 + 3.0 * randf(),
																		 sz,
																		 color.get()));
	
	spark->setOwner(this);
	if (UNIVERSE != nullptr)  UNIVERSE->addEntity(spark);

	next_spark_time = randf();
}


void ShipEntity::considerFiringMissile(double delta_t)
{
	int missile_chance = 0;
	int rhs = 3.2 / delta_t;
	if (rhs) missile_chance = 1 + (ranrot_rand() % rhs);

	double hurt_factor = 16 * pow(energy/maxEnergy, 4.0);
	if (missiles > missile_chance * hurt_factor)
	{
		fireMissile();
	}
}


Vector ShipEntity::missileLaunchPosition()
{
	Vector start;
	// default launching position
	start.x = 0.0f;						// in the middle
	start.y = boundingBox.min.y - 4.0f;	// 4m below bounding box
	start.z = boundingBox.max.z + 1.0f;	// 1m ahead of bounding box
	
	// custom launching position
	start = VectorForKey(shipinfoDictionary, "missile_launch_position", start);
	if (EXPECT_NOT(_scaleFactor != 1.0))
	{
		start = vector_multiply_scalar(start,_scaleFactor);
	}
	
	if (start.x == 0.0f && start.y == 0.0f && start.z <= 0.0f) // The kZeroVector as start is illegal also.
	{
		OO_LOG("ship.missileLaunch.invalidPosition", "***** ERROR: The missile_launch_position defines a position {} behind the {}. In future versions such missiles may explode on launch because they have to travel through the ship.", VectorDescription(start), oo::EntityDescription(this));
		start.x = 0.0f;
		start.y = boundingBox.min.y - 4.0f;
		start.z = boundingBox.max.z + 1.0f;
	}
	return start;
}


::ShipEntity *ShipEntity::fireMissile()
{
	return fireMissileWithIdentifier(std::nullopt, primaryTarget());
}




// Slice 29 of docs/phases/3-slices/ShipEntity.md (bead oo-g900k): missile firing, ECM, cloak,
// cascade mine, escape capsule, cargo dumping. Members of the C++ ship, called directly, since bead
// oo-9ht.144 deleted the facade (ADR-0056 amendment oo-9ht.144).

::ShipEntity *ShipEntity::fireMissileWithIdentifier(const std::optional<std::string> &requestedIdentifier, Entity *target)
{
	std::optional<std::string>	identifier = requestedIdentifier;
	// both players and NPCs!
	//
	::ShipEntity		*missile = nil;
	::ShipEntity		*target_ship = nil;
	
	Vector			vel;
	Vector			start, v_eject;
	
	if ((UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) < missile_launch_time) return nil;

	start = missileLaunchPosition();
	
	double  throw_speed = 250.0f;
	
	if	((missiles <= 0)||(target == nullptr)||(target->getScanClass() == CLASS_NO_DRAW))	// no missile lock!
		return nil;
	
	if (target->getIsShip())
	{
		target_ship = oo::ToShip(target);
		if ((target_ship != nullptr ? target_ship->isCloaked() : false))
		{
			return nil;
		}
		// missile fire requires being in scanner range
		if (HPmagnitude2(HPvector_subtract((target_ship != nullptr ? target_ship->getPosition() : HPVector{}), position)) > scannerRange * scannerRange)
		{
			return nil;
		}
		if (!hasMilitaryScannerFilter() && (target_ship != nullptr ? target_ship->isJammingScanning() : false)) 
		{
			return nil;
		}
	}
	
	unsigned i;
	if (!identifier.has_value())
	{
		// use a random missile from the list
		i = floor(randf()*(double)missiles);
		identifier = (missile_list[i] != nullptr ? missile_list[i]->identifier() : std::optional<std::string>());
		missile = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole(identifier.value_or("")) : (::ShipEntity *)nil);
		if (EXPECT_NOT(missile == nil))	// invalid missile role.
		{
			// remove that invalid missile role from the missiles list.
			while ( ++i < missiles ) missile_list[i - 1] = missile_list[i];
			missiles--;
		}
	}
	else
		missile = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole(*identifier) : (::ShipEntity *)nil);
	
	if (EXPECT_NOT(missile == nil))	return nil;
	
	// By definition, the player will always have the specified missile.
	// What if the NPC didn't actually have the specified missile to begin with?
	if (!isPlayer && !removeExternalStore((identifier.has_value() ? OOEquipmentType::equipmentTypeWithIdentifier(*identifier).get() : nil)))
	{
		if (missile != nullptr)  oo::ReleaseEntity(missile);
		return nil;
	}
	
	double mcr = missile->collision_radius;
	v_eject = vector_normal(start);
	vel = kZeroVector;	// starting velocity
	
	// check if start is within bounding box...
	while (	(start.x > boundingBox.min.x - mcr)&&(start.x < boundingBox.max.x + mcr)&&
			(start.y > boundingBox.min.y - mcr)&&(start.y < boundingBox.max.y + mcr)&&
			(start.z > boundingBox.min.z - mcr)&&(start.z < boundingBox.max.z + mcr) )
	{
		start = vector_add(start, vector_multiply_scalar(v_eject, mcr));
	}
	
	vel = vector_add(vel, vector_multiply_scalar(v_forward, flightSpeed + throw_speed));
	
	Quaternion q1 = normalOrientation();
	HPVector origin = HPvector_add(position, vectorToHPVector(quaternion_rotate_vector(q1, start)));
	
	if (isPlayer) { if (missile != nullptr)  missile->setScanClass(CLASS_MISSILE); }
	
// special cases
	
	//We don't want real missiles in a group. Missiles could become escorts when the group is also used as escortGroup.
	if ((missile != nullptr ? missile->getScanClass() : OOScanClass{}) == CLASS_THARGOID) 
	{
		if(group() == nullptr) setGroup(OOShipGroup::groupWithName("thargoid group").get());	// the ship keeps it (the autoreleased facade lived to the end of the pass)
		
		::ShipEntity	*thisGroupLeader = (_group != nullptr ? _group->leader() : (::ShipEntity *)nil);
		
		if ((thisGroupLeader != nullptr ? thisGroupLeader->escortGroup() : (OOShipGroup *)nullptr) != _group) // avoid adding tharons to escort groups
		{
			if (missile != nullptr)  missile->setGroup(group());
		}
	}
	
	// is this a submunition?
	if (!isMissileFlagSet())  { if (missile != nullptr)  missile->setOwner(this); }
	else  { if (missile != nullptr)  missile->setOwner(oo::LiveOwner(this)); }

// end special cases

	if (missile != nullptr)  missile->setPosition(origin);
	if (missile != nullptr)  missile->addTarget(target);	
	if (missile != nullptr)  missile->setOrientation(q1);
	if (missile != nullptr)  missile->setIsMissileFlag(YES);
	if (missile != nullptr)  missile->setVelocity(vel);
	if (missile != nullptr)  missile->setSpeed(150.0f);
	if (missile != nullptr)  missile->setDistanceTravelled(0.0f);
	if (missile != nullptr)  missile->resetShotTime();
	missile_launch_time = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) + missile_load_time; // set minimum launchtime for the next missile.
	
	if (UNIVERSE != nullptr)  UNIVERSE->addEntity(missile);	// STATUS_IN_FLIGHT, AI state GLOBAL
	if (missile != nullptr)  oo::ReleaseEntity(missile); //release
	
	// missile lives on after UNIVERSE addEntity
	if ((missile != nullptr ? missile->getIsMissile() : false) && oo::EntityIsShip(target))
	{
		doScriptEvent(OOJSID("shipFiredMissile"), missile, target_ship);
		if (target_ship != nullptr)  target_ship->setPrimaryAggressor(this);
		if (target_ship != nullptr)  target_ship->doScriptEvent(OOJSID("shipAttackedWithMissile"), missile, this);
		if (target_ship != nullptr)  target_ship->reactToAIMessage("INCOMING_MISSILE", "someone's shooting at me!");
		if (cloaking_device_active && cloakPassive)
		{
			// parity between player &NPCs, only deactivate cloak for missiles
			deactivateCloakingDevice();
		}
	}
	else
	{
		doScriptEvent(OOJSID("shipReleasedEquipment"), missile);
	}
	
	return missile;
}


bool ShipEntity::isMissileFlagSet()
{
	return isMissile; // were we created using fireMissile? (for tracking submunitions and preventing collisions at launch)
}


void ShipEntity::setIsMissileFlag(bool newValue)
{
	isMissile = !!newValue; // set the isMissile flag, used for tracking submunitions and preventing collisions at launch.
}


OOTimeDelta ShipEntity::missileLoadTime()
{
	return missile_load_time;
}


void ShipEntity::setMissileLoadTime(OOTimeDelta newMissileLoadTime)
{
	missile_load_time = fmax(0.0, newMissileLoadTime);
}


// reactions to ECM that are not dependent on current AI state here
void ShipEntity::noticeECM()
{
	if (accuracy >= COMBAT_AI_ISNT_AWFUL && missiles > 0 && ((missile_list[0] != nullptr ? missile_list[0]->identifier() : std::optional<std::string>()) == "EQ_MISSILE"))
	{
// if we're being ECMd, and our missiles appear to be standard, and we
// have some combat sense, wait a bit before firing the next one!
		missile_launch_time = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) + fmax(2.0,missile_load_time); // set minimum launchtime for the next missile.
	}
}


// Exposed to AI
bool ShipEntity::fireECM()
{
	if (!hasECM())  return NO;
	
	if (UNIVERSE != nullptr)  UNIVERSE->addEntity(oo::MadeEntity(OOECMBlastEntity::initFromShip(this)));
	return YES;
}


bool ShipEntity::activateCloakingDevice()
{
	if (!hasCloakingDevice() || cloaking_device_active)  return cloaking_device_active; // no changes.
	
	if (!cloaking_device_active)  cloaking_device_active = (energy > CLOAKING_DEVICE_START_ENERGY * maxEnergy);
	if (cloaking_device_active)  doScriptEvent(OOJSID("shipCloakActivated"));
	return cloaking_device_active;
}


void ShipEntity::deactivateCloakingDevice()
{
	if (hasCloakingDevice() && cloaking_device_active)
	{
		cloaking_device_active = NO;
		doScriptEvent(OOJSID("shipCloakDeactivated"));
	}
}


bool ShipEntity::launchCascadeMine()
{
	if (!hasCascadeMine())  return NO;
	setSpeed(maxFlightSpeed + 300);
	::ShipEntity*	bomb = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole("energy-bomb") : (::ShipEntity *)nil);
	if (bomb == nil)  return NO;
	
	removeEquipmentItem("EQ_QC_MINE");
	
	double  start = collision_radius + bomb->collision_radius;
	Quaternion  random_direction;
	Vector  vel;
	HPVector  rpos;
	double random_roll =	randf() - 0.5;  //  -0.5 to +0.5
	double random_pitch = 	randf() - 0.5;  //  -0.5 to +0.5
	quaternion_set_random(&random_direction);
	
	rpos = HPvector_subtract(getPosition(), vectorToHPVector(vector_multiply_scalar(v_forward, start)));
	
	double  eject_speed = -800.0;
	vel = vector_multiply_scalar(v_forward, getFlightSpeed() + eject_speed);
	eject_speed *= 0.5 * (randf() - 0.5);   //  -0.25x .. +0.25x
	vel = vector_add(vel, vector_multiply_scalar(v_up, eject_speed));
	eject_speed *= 0.5 * (randf() - 0.5);   //  -0.0625x .. +0.0625x
	vel = vector_add(vel, vector_multiply_scalar(v_right, eject_speed));
	
	if (bomb != nullptr)  bomb->setPosition(rpos);
	if (bomb != nullptr)  bomb->setOrientation(random_direction);
	if (bomb != nullptr)  bomb->setRoll(random_roll);
	if (bomb != nullptr)  bomb->setPitch(random_pitch);
	if (bomb != nullptr)  bomb->setVelocity(vel);
	if (bomb != nullptr)  bomb->setScanClass(CLASS_MINE);
	if (bomb != nullptr)  bomb->setEnergy(5.0);	// 5 second countdown
	if (bomb != nullptr)  bomb->setBehaviour(BEHAVIOUR_ENERGY_BOMB_COUNTDOWN);
	if (bomb != nullptr)  bomb->setOwner(this);
	if (UNIVERSE != nullptr)  UNIVERSE->addEntity(bomb);	// STATUS_IN_FLIGHT, AI state GLOBAL
	if (bomb != nullptr)  oo::ReleaseEntity(bomb);
	
	if (cloaking_device_active && cloakPassive)
	{
		deactivateCloakingDevice();
	}
	
	if (this != PLAYER)	// get the heck out of here
	{
		addTarget(bomb);
		setBehaviour(BEHAVIOUR_FLEE_TARGET);
		frustration = 0.0;
	}
	return YES;
}


::ShipEntity *ShipEntity::launchEscapeCapsule()
{
	::ShipEntity		*result = nil;
	::ShipEntity			*mainPod = nil;
	unsigned			n_pods, i;
	std::optional<std::vector<oo::EntityHold>>	passengers;	// only with more than one pod, as before
	
	/*
		CHANGE: both player & NPCs can now launch escape pods in interstellar
		space. -- Kaks 20101113
	*/
	
	// check number of pods aboard -- require at least one.
	n_pods = shipinfoDictionary.get<unsigned int>("has_escape_pod");
	if (n_pods > 65) n_pods = 65; // maximum of 64 passengers.
	if (n_pods > 1) passengers.emplace().reserve(n_pods-1);

	if (crew)	// transfer crew
	{
		// make sure crew inherit any legalStatus
		for (i = 0; i < crew->size(); i++)
		{
			::OOCharacter *ch = (*crew)[i].get();
			ch->setLegalStatus(legalStatus() | ch->legalStatus());
		}
		mainPod = launchPodWithCrew(*crew);
		if (mainPod)
		{
			result = mainPod;
			setCrew(std::nullopt);
			setHulk(YES); // we are without crew now.
		}
	}
	
	// launch other pods (passengers)
	for (i = 1; i < n_pods; i++)
	{
		::ShipEntity	*passenger = nil;
		passenger = launchPodWithCrew(std::vector<oo::Ref<OOCharacter>>{ oo::Ref<OOCharacter>(OOCharacter::randomCharacterWithRole("passenger", gen_rnd_number())) });
		if (passengers.has_value())  passengers->emplace_back(passenger);
	}

	// the passengers' pods as an array, or null (nil) with a single pod
	if (mainPod) doScriptEvent(OOJSID("shipLaunchedEscapePod"), { oo::EntityObjectNode(mainPod), passengers.has_value() ? oo::EntityNodesFrom(*passengers) : oo::PList() });
	
	return result;
}


// This is a documented AI method; do not change semantics. (Note: AIs don't have access to the return value,
// and no caller read it: PlayerEntity reads the commodity from -cxx_dumpCargoItem: itself.)
void ShipEntity::dumpCargo()
{
	dumpCargoItem(std::nullopt);
}


::ShipEntity *ShipEntity::dumpCargoItem(const std::optional<std::string> &preferred)
{
	::ShipEntity				*jetto = nil;
	NSUInteger				 i = 0;
	
	if ((cargo.size() > 0)&&((UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) - cargo_dump_time > 0.5))  // space them 0.5s or 10m apart
	{
		if (!preferred.has_value())
		{
			jetto = oo::ToShip(oo::AutoreleaseEntity(oo::RetainEntity(cargo[0].get())));
		}
		else
		{
			BOOL found = NO;
			for (i=0;i<cargo.size();i++)
			{
				if ((oo::ToShip(cargo[i].get()) != nullptr ? oo::ToShip(cargo[i].get())->commodityType() : std::optional<std::string>()) == preferred)
				{
					jetto = oo::ToShip(oo::AutoreleaseEntity(oo::RetainEntity(cargo[i].get())));
					found = YES;
					break;
				}
			}
			if (found == NO)
			{
				// dump anything
				jetto = oo::ToShip(oo::AutoreleaseEntity(oo::RetainEntity(cargo[0].get())));
				i = 0;
			}
		}
		if (jetto != nil)
		{
			dumpItem(jetto);	// CLASS_CARGO, STATUS_IN_FLIGHT, AI state GLOBAL
			cargo.erase(cargo.begin() + i);
			broadcastAIMessage("CARGO_DUMPED"); // goes only to 16 nearby ships in range, but that should be enough.
			unsigned i;
			// only send script event to powered entities
			checkScannerIgnoringUnpowered();
			for (i = 0; i < n_scanned_ships ; i++)
			{
				::ShipEntity* other = scanned_ships[i];
				if (other != nullptr)  other->doScriptEvent(OOJSID("cargoDumpedNearby"), jetto, this);
				
			}
		}
	}
	
	return jetto;
}


OOCargoType ShipEntity::dumpItem(::ShipEntity *cargoObj)
{
	if (!cargoObj)
		return (OOCargoType)0;

	::ShipEntity* jetto = (UNIVERSE != nullptr ? UNIVERSE->reifyCargoPod(cargoObj) : (::ShipEntity *)nil);

	int		result = (jetto != nullptr ? static_cast<int>(jetto->cargoType()) : 0);
	::AI		*jettoAI = nil;
	Vector	start;
	
	// players get to see their old ship sailing forth, while NPCs run away more efficiently!
	// cargo is ejected at higher speed from any ship
	double  eject_speed = EXPECT_NOT((jetto != nullptr ? jetto->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>()).has_value() && (jetto != nullptr ? jetto->getIsPlayer() : false)) ? 20.0 : 100.0;
	double  eject_reaction = -eject_speed * (jetto != nullptr ? jetto->getMass() : 0.0f) / getMass();
	double	jcr = jetto->collision_radius;
	
	Quaternion  jetto_orientation = kIdentityQuaternion;
	Vector  vel, v_eject, v_eject_normal;
	HPVector  rpos = absolutePositionForSubentity();
	double jetto_roll =	0;
	double jetto_pitch = 0;
	
	// default launching position
	start.x = 0.0;						// in the middle
	start.y = 0.0;						//
	start.z = boundingBox.min.z - jcr;	// 1m behind of bounding box
	
	// custom launching position
	start = VectorForKey(shipinfoDictionary, "aft_eject_position", start);
	
	v_eject = vector_normal(start);
	
	// check if start is within bounding box...
	while (	(start.x > boundingBox.min.x - jcr)&&(start.x < boundingBox.max.x + jcr)&&
			(start.y > boundingBox.min.y - jcr)&&(start.y < boundingBox.max.y + jcr)&&
			(start.z > boundingBox.min.z - jcr)&&(start.z < boundingBox.max.z + jcr))
	{
		start = vector_add(start, vector_multiply_scalar(v_eject, jcr));
	}
	
	v_eject = quaternion_rotate_vector(normalOrientation(), start);
	rpos = HPvector_add(rpos, vectorToHPVector(v_eject));
	v_eject = vector_normal(v_eject);
	v_eject_normal = v_eject;
	
	v_eject.x += (randf() - randf())/eject_speed;
	v_eject.y += (randf() - randf())/eject_speed;
	v_eject.z += (randf() - randf())/eject_speed;
	
	vel = vector_add(vector_multiply_scalar(v_forward, flightSpeed), vector_multiply_scalar(v_eject, eject_speed));
	velocity = vector_add(velocity, vector_multiply_scalar(v_eject, eject_reaction));
	
	if (jetto != nullptr)  jetto->setPosition(rpos);
	if ((jetto != nullptr ? jetto->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>()).has_value()) // jetto has a crew, so assume it is an escape pod.
	{
		// orient the pod away from the ship to avoid colliding with it.
		jetto_orientation = quaternion_rotation_between(v_eject_normal, kBasisZVector);
	}
	else
	{
		// It is true cargo, let it tumble.
		jetto_roll =	((ranrot_rand() % 1024) - 512.0)/1024.0;  //  -0.5 to +0.5
		jetto_pitch =   ((ranrot_rand() % 1024) - 512.0)/1024.0;  //  -0.5 to +0.5
		quaternion_set_random(&jetto_orientation);
	}
	
	if (jetto != nullptr)  jetto->setOrientation(jetto_orientation);
	if (jetto != nullptr)  jetto->setRoll(jetto_roll);
	if (jetto != nullptr)  jetto->setPitch(jetto_pitch);
	if (jetto != nullptr)  jetto->setVelocity(vel);
	if (jetto != nullptr)  jetto->setScanClass(CLASS_CARGO);
	if (jetto != nullptr)  jetto->setTemperature(randomEjectaTemperature());
	if (UNIVERSE != nullptr)  UNIVERSE->addEntity(jetto);	// STATUS_IN_FLIGHT, AI state GLOBAL
	
	jettoAI = (jetto != nullptr ? jetto->getAI() : (::AI *)nullptr);
	if ((jettoAI != nullptr ? jettoAI->hasSuspendedStateMachines() : false)) // check if this was previous scooped cargo.
	{
		if (jetto != nullptr)  jetto->setThrust((jetto != nullptr ? jetto->maxThrust() : 0.0f)); // restore old thrust.
		if (jetto != nullptr)  jetto->setOwner(jetto);
		if (jettoAI != nullptr)  jettoAI->exitStateMachineWithMessage(std::nullopt); // exit nullAI.
	}
	if (jetto != nullptr)  jetto->doScriptEvent(OOJSID("shipWasDumped"), this);
	doScriptEvent(OOJSID("shipDumpedCargo"), jetto);
	
	cargo_dump_time = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0);
	return (OOCargoType)result;
}




// Slice 30 of docs/phases/3-slices/ShipEntity.md (bead oo-ogoct): collisions, velocity, tractoring
// and scooping. Members of the C++ ship, called directly, since bead oo-9ht.144 deleted the facade
// (ADR-0056 amendment oo-9ht.144).

void ShipEntity::manageCollisions()
{
	// deal with collisions
	//
	Entity*		ent;
	::ShipEntity* other_ship;
	
	while (!collidingEntities.empty())
	{
		// EMMSTRAN: investigate if doing this backwards would be more efficient. (Not entirely obvious, the vector is kinda funky.) -- Ahruman 2011-02-12
		ent = oo::AutoreleaseEntity(oo::RetainEntity(collidingEntities.front().get()));	// [[... retain] autorelease]
		collidingEntities.erase(collidingEntities.begin());
		if (ent)
		{
			if (oo::EntityIsShip(ent))
			{
				other_ship = oo::ToShip(ent);
				collideWithShip(other_ship);
			}
			else if (ent->isStellarObject())
			{
				getDestroyedBy(ent, ent->isSun() ? kOODamageTypeHitASun : kOODamageTypeHitAPlanet);
				if (this == PLAYER)  oo::RetainEntity(this);
			}
			else if (ent->getIsWormhole())
			{
				// the C++ wormhole (C++ since bead oo-9ht.112; a C-style cast of its object until bead oo-9ht.144)
				if( getIsPlayer() ) enterWormhole(static_cast<::WormholeEntity *>(ent));
				else enterWormhole(static_cast<::WormholeEntity *>(ent), NO);
			}
		}
	}
}


bool ShipEntity::collideWithShip(::ShipEntity *other)
{
	HPVector  hploc;
	Vector loc;
	double  dam1, dam2;
	
	if (!other)
		return NO;
	
	::ShipEntity* otherParent = oo::ToShip((other != nullptr ? other->parentEntity() : (Entity *)nullptr));
	BOOL otherIsStation = other == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr);
	// calculate line of centers using centres
	hploc = HPvector_normal_or_zbasis(HPvector_subtract((other != nullptr ? other->absolutePositionForSubentity() : HPVector{}), position));
	loc = HPVectorToVector(hploc);

	
	if (canScoop(other))
	{
		scoopIn(other);
		return NO;
	}
	if ((other != nullptr ? other->canScoop(this) : false))
	{
		if (other != nullptr)  other->scoopIn(this);
		return NO;
	}
	if (universalID == NO_TARGET)
		return NO;
	if (other->universalID == NO_TARGET)
		return NO;

	// find velocity along line of centers
	//
	// momentum = mass x velocity
	// ke = mass x velocity x velocity
	//
	GLfloat m1 = mass;			// mass of self
	GLfloat m2 = (other != nullptr ? other->getMass() : 0.0f);	// mass of other

	// starting velocities:
	Vector	v, vel1b =	getVelocity();
	
	if (otherParent != nil)
	{
		// Subentity
		/*	TODO: if the subentity is rotating (subentityRotationalVelocity is
			not 1 0 0 0) we should calculate the tangential velocity from the
			other's position relative to our absolute position and add that in.
		*/
		v = (otherParent != nullptr ? otherParent->getVelocity() : Vector{});
	}
	else
	{
		v = (other != nullptr ? other->getVelocity() : Vector{});
	}

	v = vector_subtract(vel1b, v);
	
	GLfloat	v2b = dot_product(v, loc);			// velocity of other along loc before collision
	
	GLfloat v1a = sqrt(v2b * v2b * m2 / m1);	// velocity of self along loc after elastic collision
	if (v2b < 0.0f)	v1a = -v1a;					// in same direction as v2b
	
	// are they moving apart at over 1m/s already?
	if (v2b < 0.0f)
	{
		if (v2b < -1.0f)  return NO;
		else
		{
			position = HPvector_subtract(position, hploc);	// adjust self position
			v = kZeroVector;	// go for the 1m/s solution
		}
	}

	// convert change in velocity into damage energy (KE)
	dam1 = m2 * v2b * v2b / 50000000;
	dam2 = m1 * v2b * v2b / 50000000;
	
	// calculate adjustments to velocity after collision
	Vector vel1a = vector_multiply_scalar(loc, -v1a);
	Vector vel2a = vector_multiply_scalar(loc, v2b);

	if (magnitude2(v) <= 0.1)	// virtually no relative velocity - we must provide at least 1m/s to avoid conjoined objects
	{
		vel1a = vector_multiply_scalar(loc, -1);
		vel2a = loc;
	}

	// apply change in velocity
	if (otherParent != nil)
	{
		if (otherParent != nullptr)  otherParent->adjustVelocity(vel2a);	// move the otherParent not the subentity
	}
	else
	{
		if (other != nullptr)  other->adjustVelocity(vel2a);
	}
	
	adjustVelocity(vel1a);
	
	BOOL selfDestroyed = (dam1 > energy);
	BOOL otherDestroyed = (dam2 > (other != nullptr ? other->getEnergy() : 0.0f)) && !otherIsStation;
	
	if (dam1 > 0.05)
	{
		takeScrapeDamage(dam1, other);
		if (selfDestroyed)	// inelastic! - take xplosion velocity damage instead
		{
			vel2a = vector_multiply_scalar(vel2a, -1);
			if (other != nullptr)  other->adjustVelocity(vel2a);
		}
	}
	
	if (dam2 > 0.05)
	{
		if (otherParent != nil && !(otherParent != nullptr ? otherParent->getIsFrangible() : false))
		{
			if (otherParent != nullptr)  otherParent->takeScrapeDamage(dam2, this);
		}
		else
		{
			if (other != nullptr)  other->takeScrapeDamage(dam2, this);
		}
		
		if (otherDestroyed)	// inelastic! - take explosion velocity damage instead
		{
			vel1a = vector_multiply_scalar(vel1a, -1);
			adjustVelocity(vel1a);
		}
	}
	
	if (!selfDestroyed && !otherDestroyed)
	{
		float t = 10.0 * (UNIVERSE != nullptr ? UNIVERSE->getTimeDelta() : 0.0);	// 10 ticks
		
		HPVector pos1a = HPvector_add(getPosition(), vectorToHPVector(vector_multiply_scalar(loc, t * v1a)));
		setPosition(pos1a);
		
		if (!otherIsStation)
		{
			HPVector pos2a = HPvector_add((other != nullptr ? other->getPosition() : HPVector{}), vectorToHPVector(vector_multiply_scalar(loc, t * v2b)));
			if (other != nullptr)  other->setPosition(pos2a);
		}
	}
	
	// remove self from other's collision list
	if (std::vector<oo::EntityHold> *colliding = (other != nullptr ? other->getCollidingEntities() : (std::vector<oo::EntityHold> *)nullptr))  std::erase_if(*colliding, [this](const oo::EntityHold &e) { return e.get() == this; });	// -removeObject:
	
	doScriptEvent(OOJSID("shipCollided"), other, "COLLISION");
	if (other != nullptr)  other->doScriptEvent(OOJSID("shipCollided"), this, "COLLISION");
	
	return YES;
}


Vector ShipEntity::thrustVector()
{
	return vector_multiply_scalar(v_forward, flightSpeed);
}


Vector ShipEntity::getVelocity()
{
	return vector_add(OOEntityWithDrawable::getVelocity(), thrustVector());	// [super velocity]
}


void ShipEntity::setTotalVelocity(Vector vel)
{
	setVelocity(vector_subtract(vel, thrustVector()));
}


void ShipEntity::adjustVelocity(Vector xVel)
{
	velocity = vector_add(velocity, xVel);
}


void ShipEntity::addImpactMoment(Vector moment, GLfloat howmuch)
{
	velocity = vector_add(velocity, vector_multiply_scalar(moment, howmuch / mass));
}


bool ShipEntity::canScoop(::ShipEntity *other)
{
	if (other == nil)							return NO;
	if (!hasCargoScoop())						return NO;
	if (cargo.size() >= maxAvailableCargoSpace())	return NO;
	if (scanClass == CLASS_CARGO)				return NO;  // we have no power so we can't scoop
	if ((other != nullptr ? other->getScanClass() : OOScanClass{}) != CLASS_CARGO)		return NO;
	if (other != nullptr && other->cargoType() == CARGO_NOT_CARGO)	return NO;
	
	if ((other != nullptr ? other->getIsStation() : false))						return NO;

	HPVector  loc = HPvector_between(position, (other != nullptr ? other->getPosition() : HPVector{}));
	
	if (dot_product(v_forward, HPVectorToVector(loc)) < 0.0f)		return NO;  // Must be in front of us
	if (getIsPlayer() && dot_product(v_up, HPVectorToVector(loc)) > 0.0f)  return NO;  // player has to scoop on underside, give more flexibility to NPCs
	
	return YES;
}


void ShipEntity::getTractoredBy(::ShipEntity *other)
{
	if(status() == STATUS_BEING_SCOOPED) return; // both cargo and ship call this. Act only once.
	desired_speed = 0.0;
	setAITo("nullAI.plist");	// prevent AI from changing status or behaviour.
	behaviour = BEHAVIOUR_TRACTORED;
	setStatus(STATUS_BEING_SCOOPED);
	addTarget(other);
	setOwner(other);
	// should we make this an all rather than first 16? - CIM
	// made it ignore other cargopods and similar at least. - CIM 28/7/2013
	checkScannerIgnoringUnpowered(); 
	unsigned i;
	::ShipEntity *scooper;
	for (i = 0; i < n_scanned_ships ; i++)
	{
		scooper = oo::ToShip(scanned_ships[i]);
		// 'Dibs!' - Stops other ships from trying to scoop/shoot this cargo.
		if (other != scooper && this == (scooper != nullptr ? scooper->primaryTarget() : (Entity *)nullptr))
		{
			if (scooper != nullptr)  scooper->noteLostTarget();
		}
	}
}


void ShipEntity::scoopIn(::ShipEntity *other)
{
	if (other != nullptr)  other->getTractoredBy(this);
}


void ShipEntity::suppressTargetLost()
{
	
}


void ShipEntity::scoopUp(::ShipEntity *other)
{
	scoopUpProcess(other, YES, YES);
}


void ShipEntity::scoopUpProcess(::ShipEntity *other, bool procEvents, bool procMessages)
{
	if (other == nil)  return;
	
	std::optional<std::string>	co_type;
	OOCargoQuantity	co_amount;
	
	// don't even think of trying to scoop if the cargo hold is already full
	if (max_cargo && cargo.size() >= maxAvailableCargoSpace())
	{
		if (other != nullptr)  other->setStatus(STATUS_IN_FLIGHT);
		return;
	}
	
	switch (other != nullptr ? static_cast<int>(other->cargoType()) : 0)	// (a message to nil answered 0)
	{
		case CARGO_RANDOM:
			co_type = (other != nullptr ? other->commodityType() : std::optional<std::string>());
			co_amount = (other != nullptr ? other->commodityAmount() : 0);
			break;
		
		case CARGO_SCRIPTED_ITEM:
			{
				//scripting
				::PlayerEntity *player = PLAYER;
				if (player != nullptr)  player->setScriptTarget(this);
				if (procEvents)
				{
					if (other != nullptr)  other->doScriptEvent(OOJSID("shipWasScooped"), this);
				}
				
				if ((other != nullptr ? other->commodityType() : std::optional<std::string>()).has_value())
				{
					co_type = (other != nullptr ? other->commodityType() : std::optional<std::string>());
					co_amount = (other != nullptr ? other->commodityAmount() : 0);
					// don't show scoop message now, will happen later.
				}
				else
				{
					if (isPlayer && (other != nullptr ? other->showScoopMessage() : false) && procMessages)
					{
						if (UNIVERSE != nullptr)  UNIVERSE->clearPreviousMessage();
						const std::optional<std::string> shipName = (other != nullptr ? other->getDisplayName() : std::optional<std::string>());
						if (UNIVERSE != nullptr)  UNIVERSE->addMessage(ExpandKeyWithArgument("scripted-item-scooped", "shipName", shipName), 4);
					}
					if (other != nullptr)  other->setCommodityForPod(std::nullopt, 0);
					co_amount = 0;
					co_type = std::nullopt;
				}
			}
			break;

		default :
			co_amount = 0;
			co_type = std::nullopt;
			break;
	}
	
	/*	Bug: docking failed due to OORangeException while looking for element
		NSNotFound of cargo mainfest in -[PlayerEntity unloadCargoPods].
		Analysis: bad cargo pods being generated due to
		-[Universe commodityForName:] looking in wrong place for names.
		Fix 1: fix -[Universe commodityForName:].
		Fix 2: catch NSNotFound here and substitute random cargo type.
		-- Ahruman 20070714
	*/
	if (!co_type.has_value() && co_amount > 0)
	{
		co_type = std::optional<std::string>((UNIVERSE != nullptr ? UNIVERSE->getRandomCommodity() : std::string()));
		co_amount = co_type.has_value() ? (UNIVERSE != nullptr ? UNIVERSE->getRandomAmountOfCommodity(*co_type) : 0) : 0;
	}

	if (co_amount > 0)
	{
		if (co_type.has_value())  { if (other != nullptr)  other->setCommodity(*co_type, co_amount); }   // belt and braces setting this! (nil changed nothing)
		cargo_flag = CARGO_FLAG_CANISTERS;
		
		if (isPlayer)
		{
			const std::optional<std::vector<oo::Ref<OOCharacter>>> otherCrew = (other != nullptr ? other->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>());
			if (otherCrew.has_value())
			{
				if ((other != nullptr ? other->showScoopMessage() : false) && procMessages)
				{
					if (UNIVERSE != nullptr)  UNIVERSE->clearPreviousMessage();
					unsigned i;
					for (i = 0; i < otherCrew->size(); i++)
					{
						::OOCharacter *rescuee = (*otherCrew)[i].get();
						const std::optional<std::string> characterName = rescuee->name();
						if (rescuee->legalStatus())
						{
							if (UNIVERSE != nullptr)  UNIVERSE->addMessage(ExpandKeyWithArgument("scoop-captured-character", "characterName", characterName), 4.5);
						}
						else if (rescuee->insuranceCredits())
						{
							if (UNIVERSE != nullptr)  UNIVERSE->addMessage(ExpandKeyWithArgument("scoop-rescued-character", "characterName", characterName), 4.5);
						}
						else
						{
							if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("scoop-got-slave"), 4.5);
						}
					}
				}
				if (procEvents) 
				{
					static_cast<PlayerEntity *>(this)->playEscapePodScooped();
				}
			}
			else
			{
				if ((other != nullptr ? other->showScoopMessage() : false) && procMessages)
				{
					if (UNIVERSE != nullptr)  UNIVERSE->clearPreviousMessage();
					if (UNIVERSE != nullptr)  UNIVERSE->addMessage((UNIVERSE != nullptr ? UNIVERSE->describeCommodity(co_type.value_or(""), co_amount) : std::optional<std::string>()), 4.5);
				}
			}
		}
		cargo.insert(cargo.begin(), oo::EntityHold(other));	// places most recently scooped object at eject position
		if (other != nullptr)  other->setStatus(STATUS_IN_HOLD);
		if (other != nullptr)  other->performTumble();
		if (shipAI != nullptr)  shipAI->message("CARGO_SCOOPED");
		if (max_cargo && cargo.size() >= maxAvailableCargoSpace())  { if (shipAI != nullptr)  shipAI->message("HOLD_FULL"); }
	}
	if (procEvents)
	{
		doScriptEvent(OOJSID("shipScoopedOther"), other); // always fire, even without commodity.
	}

	// if shipScoopedOther does something strange to the object, we must
	// then remove it from the hold, or it will be over-retained
	if ((other != nullptr ? other->status() : OOEntityStatus{}) != STATUS_IN_HOLD) 
	{
		if (other != nullptr && (std::find(cargo.begin(), cargo.end(), other) != cargo.end()))	// the list holds no null
		{
			std::erase(cargo, other);
		}
	}

	if (std::vector<oo::EntityHold> *colliding = (other != nullptr ? other->getCollidingEntities() : (std::vector<oo::EntityHold> *)nullptr))  std::erase_if(*colliding, [this](const oo::EntityHold &e) { return e.get() == this; });	// -removeObject:, so it can't be scooped twice!
	// make sure other ships trying to scoop it lose it
	// probably already happened, but some may have acquired it
	// after the scooping started, and they might get stuck in a scooping
	// attempt as a result
	checkScannerIgnoringUnpowered();
	unsigned i;
	::ShipEntity *scooper;
	for (i = 0; i < n_scanned_ships ; i++)
	{
		scooper = oo::ToShip(scanned_ships[i]);
		if (this != scooper && other == (scooper != nullptr ? scooper->primaryTargetWithoutValidityCheck() : (Entity *)nullptr))
		{
			if (scooper != nullptr)  scooper->noteLostTarget();
		}
	}

	suppressTargetLost();
	if (UNIVERSE != nullptr)  UNIVERSE->removeEntity(other);
}




// Slice 31 of docs/phases/3-slices/ShipEntity.md (bead oo-gx86h): cascades, energy / scrape / heat
// damage, abandoning ship, docks, wormholes, witchspace. Members of the C++ ship, called directly,
// since bead oo-9ht.144 deleted the facade (ADR-0056 amendment oo-9ht.144).

bool ShipEntity::cascadeIfAppropriateWithDamageAmount(double amount, Entity * /* owner */)
{
	BOOL cascade = NO;
	switch (getScanClass())
	{
		case CLASS_WORMHOLE:
		case CLASS_ROCK:
		case CLASS_CARGO:
		case CLASS_VISUAL_EFFECT:
		case CLASS_BUOY:
			// does not normally cascade
			if ((fuel > MIN_FUEL) || isStation) 
			{
				//we have fuel onboard so we can still go pop, or we are a station which can
			}
			else break;
			
		case CLASS_STATION:
		case CLASS_MINE:
		case CLASS_PLAYER:
		case CLASS_POLICE:
		case CLASS_MILITARY:
		case CLASS_THARGOID:
		case CLASS_MISSILE:
		case CLASS_NOT_SET:
		case CLASS_NO_DRAW:
		case CLASS_NEUTRAL:
		case CLASS_TARGET:
			// ...start a chain reaction, if we're dying and have a non-trivial amount of energy.
			if (energy < amount && energy > 10 && countsAsKill())
			{
				cascade = YES;	// confirm we're cascading, then try to add our cascade to UNIVERSE.
				if (UNIVERSE != nullptr)  UNIVERSE->addEntity(oo::MadeEntity(OOQuiriumCascadeEntity::quiriumCascadeFromShip(this)));
			}
			break;
			//no default thanks, we want the compiler to tell us if we missed a case.
	}
	return cascade;
}


void ShipEntity::takeEnergyDamage(double amount, Entity *entPart, Entity *otherPart, const std::string & /* weaponIdentifier */)
{
	if (status() == STATUS_DEAD)  return;
	if (amount <= 0.0)  return;
	
	BOOL energyMine = OOEntityIsCascadeWeapon(entPart);
	BOOL cascade = NO;
	if (energyMine)
	{
		cascade = cascadeIfAppropriateWithDamageAmount(amount, oo::LiveOwner(entPart));	// [ent owner]'s C++ entity
	}
	
	energy -= amount;
	/* Heat increase from energy impacts will never directly cause
	 * overheating - too easy for missile hits to cause an uncredited
	 * death by overheating - CIM */
	if (ship_temperature < SHIP_MAX_CABIN_TEMP)
	{
		ship_temperature += amount * (mass > 400000 ? 200000 / mass : 0.5) / heatInsulation();	// SHIP_ENERGY_DAMAGE_TO_HEAT_FACTOR, which named the facade's C++ entity
		if (ship_temperature > SHIP_MAX_CABIN_TEMP)
		{
			ship_temperature = SHIP_MAX_CABIN_TEMP;
		}
	}


	being_mined = NO;
	::ShipEntity *hunter = nil;
	
	hunter = oo::ToShip(otherPart != nullptr ? otherPart->rootShipEntity() : nullptr);
	if (hunter == nil && oo::EntityIsShip(otherPart)) hunter = oo::ToShip(otherPart);
	
	// must check for this before potentially deleting 'other' for cloaking
	if ((otherPart)&&(oo::EntityIsShip(otherPart)))
	{
		being_mined = ((oo::ToShip(otherPart) != nullptr ? oo::ToShip(otherPart)->isMining() : false) != NO);
	}

	if (hunter !=nil && oo::LiveOwner(this) != hunter) // our owner could be the same entity as the one responsible for our taking damage in the case of submunitions
	{
		if ((hunter != nullptr ? hunter->isCloaked() : false))
		{
			doScriptEvent(OOJSID("shipBeingAttackedByCloaked"), "ATTACKED_BY_CLOAKED");
			
			// lose it!
			otherPart = nullptr;
			hunter = nil;
		}
	}
	else
	{
		hunter = nil;
	}
	
	// if the other entity is a ship note it as an aggressor
	if (hunter != nil)
	{
		BOOL iAmTheLaw = isPolice();
		BOOL uAreTheLaw = (hunter != nullptr ? hunter->isPolice() : false);
		
		_lastEscortTarget = nullptr;	// we're being attacked, escorts can scramble!
		
		setPrimaryAggressor(hunter);
		setFoundTarget(hunter);

		// firing on an innocent ship is an offence
		broadcastHitByLaserFrom(hunter);

		// tell ourselves we've been attacked
		if (energy > 0)
		{
			respondToAttackFrom(entPart, hunter);
		}

		::OOShipGroup *group = this->group();
		// JSAIs manage group notifications themselves
		if (!hasNewAI())
		{
			// additionally, tell our group we've been attacked
			if (group != nil && group != (hunter != nullptr ? hunter->group() : (OOShipGroup *)nullptr) && !(iAmTheLaw || uAreTheLaw))
			{
				if (isTrader() || isEscort())
				{
					::ShipEntity *groupLeader = (group != nullptr ? group->leader() : (::ShipEntity *)nil);
					if (groupLeader != this)
					{
						if (groupLeader != nullptr)  groupLeader->setFoundTarget(hunter);
						if (groupLeader != nullptr)  groupLeader->setPrimaryAggressor(hunter);
						if (groupLeader != nullptr)  groupLeader->respondToAttackFrom(entPart, hunter);
						//unsetting group leader for carriers can break stuff
					}
				}
				if (isPirate())
				{
					for (const oo::EntityHold &otherPirateRef : (group != nullptr ? group->memberArray() : std::vector<oo::EntityHold>()))
					{
						::ShipEntity *otherPirate = oo::ToShip(otherPirateRef.get());
						if (otherPirate != this && randf() < 0.5)	// 50% chance they'll help
						{
							if (otherPirate != nullptr)  otherPirate->setFoundTarget(hunter);
							if (otherPirate != nullptr)  otherPirate->setPrimaryAggressor(hunter);
							if (otherPirate != nullptr)  otherPirate->respondToAttackFrom(entPart, hunter);
						}
					}
				}
				else if (iAmTheLaw)
				{
					for (const oo::EntityHold &otherPoliceRef : (group != nullptr ? group->memberArray() : std::vector<oo::EntityHold>()))
					{
						::ShipEntity *otherPolice = oo::ToShip(otherPoliceRef.get());
						if (otherPolice != this)
						{
							if (otherPolice != nullptr)  otherPolice->setFoundTarget(hunter);
							if (otherPolice != nullptr)  otherPolice->setPrimaryAggressor(hunter);
							if (otherPolice != nullptr)  otherPolice->respondToAttackFrom(entPart, hunter);
						}
					}
				}
			}
		}

		// if I'm a copper and you're not, then mark the other as an offender!
		if (iAmTheLaw && !uAreTheLaw)
		{
			// JSAI's can choose not to do this for friendly fire purposes
			if (!hasNewAI()) 
			{
				if (hunter != nullptr)  hunter->markAsOffender(64, kOOLegalStatusReasonAttackedPolice);
			}
		}

		if ((group != nil && (hunter != nullptr ? hunter->group() : (OOShipGroup *)nullptr) == group) || (iAmTheLaw && uAreTheLaw))
		{
			// avoid shooting each other
			if ((hunter != nullptr ? hunter->getBehaviour() : OOBehaviour{}) == BEHAVIOUR_ATTACK_FLY_TO_TARGET)	// avoid me please!
			{
				if (hunter != nullptr)  hunter->setBehaviour(BEHAVIOUR_ATTACK_FLY_FROM_TARGET);
				if (hunter != nullptr)  hunter->setDesiredSpeed((hunter != nullptr ? hunter->getMaxFlightSpeed() : 0.0f));
			}
		}

	}
	
	OOShipDamageType damageType = kOODamageTypeEnergy;
	if (suppressExplosion)  damageType = kOODamageTypeRemoved;
	else if (energyMine)  damageType = kOODamageTypeCascadeWeapon;
	
	if (!suppressExplosion)
	{
		noteTakingDamage(amount, otherPart, damageType);
		if (cascade) energy = 0.0; // explicit set energy to zero in case an oxp raised the energy in previous line.
	}

	// die if I'm out of energy
	if (energy <= 0.0)
	{
		// backup check just in case scripts have reduced energy
		if (this != (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr)) 
		{
			if (hunter != nil)  { if (hunter != nullptr)  hunter->noteTargetDestroyed(this); }
			getDestroyedBy(otherPart, damageType);
		}
	}
	else
	{
		// warn if I'm low on energy
		if (energy < maxEnergy * 0.25)
		{
			doScriptEvent(OOJSID("shipEnergyIsLow"), "ENERGY_LOW");
		}
		if ((energy < maxEnergy *0.125 || (energy < 64 && energy < amount*2)) && hasEscapePod() && (ranrot_rand() & 3) == 0)  // 25% chance he gets to an escape pod
		{
			abandonShip();
		}
	}
}


bool ShipEntity::abandonShip()
{
	BOOL OK = NO;
	if (getIsPlayer() && static_cast<PlayerEntity *>(this)->isDocked())
	{
		OO_LOG("ShipEntity.abandonShip.failed", "{}", "Player cannot abandon ship while docked.");
		return OK;
	}
	
	if (!hasEscapePod())
	{
		OO_LOG("ShipEntity.abandonShip.failed", "Ship abandonment was requested for {}, but this ship does not carry escape pod(s).", oo::EntityDescription(this));
		return OK;
	}
		
	if (EXPECT(launchEscapeCapsule() != nil))	// oo::ToShip(NO_TARGET)	// -launchEscapeCapsule takes care of everything for the player
	{
		if (!getIsPlayer())
		{
			OK = YES;
			// if multiple items providing escape pod, remove all of them (NPC process)
			while (hasEquipmentItemProviding("EQ_ESCAPE_POD"))
			{
				removeEquipmentItem(equipmentItemProviding("EQ_ESCAPE_POD").value_or(std::string()));
			}
			setAITo("nullAI.plist");
			behaviour = BEHAVIOUR_IDLE;
			frustration = 0.0;
			setScanClass(CLASS_CARGO);			// we're unmanned now!
			thrust = thrust * 0.5;
			if (thrust > 5) thrust = 5; // 5 is the thrust of an escape-capsule
			desired_speed = 0.0;
			if (group()) setGroup(nullptr); // remove self from group.
			if (!getIsSubEntity() && owner()) setOwner(nullptr); //unset owner, but not if we are a subent
			if (hasEscorts())
			{
				::OOShipGroup			*escortGroup = this->escortGroup();
				// Note: works on escortArray rather than escortEnumerator because escorts may be mutated.
				for (const auto &escortRef : escortArray())
				{
					::ShipEntity *escort = oo::ToShip(escortRef.get());
					// act individually now!
					if ((escort != nullptr ? escort->group() : (OOShipGroup *)nullptr) == escortGroup)  { if (escort != nullptr)  escort->setGroup(nullptr); }
					if (oo::LiveOwner(escort) == this)  { if (escort != nullptr)  escort->setOwner(escort); }
				}
				
				// We now have no escorts.
				_escortGroup = nullptr;
			}
		}
	}
	else if (EXPECT(getIsSubEntity()))
	{
		// may still have launched passenger pods even if no crew
		// if multiple items providing escape pod, remove all of them (NPC process)
		while (hasEquipmentItemProviding("EQ_ESCAPE_POD"))
		{
			removeEquipmentItem(equipmentItemProviding("EQ_ESCAPE_POD").value_or(std::string()));
		}

	}
	else
	{
		// this shouldn't happen any more!
		OO_LOG("ShipEntity.abandonShip.notPossible", "Ship {} cannot be abandoned at this time.", oo::EntityDescription(this));
	}
	return OK;
}


void ShipEntity::takeScrapeDamage(double amount, Entity *ent)
{
	if (status() == STATUS_DEAD)  return;

	if (status() == STATUS_LAUNCHING|| oo::EntityStatus(ent) == STATUS_LAUNCHING)
	{
		// no collisions during launches please
		return;
	}
	
	energy -= amount;
	noteTakingDamage(amount, ent, kOODamageTypeScrape);
	
	// oops we hit too hard!!!
	if (energy <= 0.0)
	{
		float frag_chance = (ent != nullptr ? ent->getMass() : 0.0f)*10/getMass();
		/* impacts from heavier entities produce fragments
		 * impacts from lighter entities might do but not always
		 * asteroid-asteroid impacts likely to fragment
		 * ship-asteroid impacts might, or might just vaporise it
		 * projectile weapons just get the default chance
		 */
		if (randf() < frag_chance)
		{
			being_mined = YES;  // same as using a mining laser
		}
		if (oo::EntityIsShip(ent))
		{
			if (oo::ToShip(ent) != nullptr)  oo::ToShip(ent)->noteTargetDestroyed(this);
		}
		getDestroyedBy(ent, kOODamageTypeScrape);
	}
	else
	{
		// warn if I'm low on energy
		if (energy < maxEnergy * 0.25)
		{
			doScriptEvent(OOJSID("shipEnergyIsLow"), "ENERGY_LOW");
		}
	}
}


void ShipEntity::takeHeatDamage(double amount)
{
	if (status() == STATUS_DEAD)  return;

	if (getIsSubEntity())
	{
		::ShipEntity* owner = oo::ToShip(this->owner());
		if (!(owner != nullptr ? owner->getIsFrangible() : false)) 
		{
			return;
		}
	}
	
	energy -= amount;
	throw_sparks = YES;
	
	noteTakingDamage(amount, nullptr, kOODamageTypeHeat);
	
	// oops we're burning up!
	if (energy <= 0.0)
	{
		getDestroyedBy(nullptr, kOODamageTypeHeat);
	}
	else
	{
		// warn if I'm low on energy
		if (energy < maxEnergy * 0.25)
		{
			doScriptEvent(OOJSID("shipEnergyIsLow"), "ENERGY_LOW");
		}
	}
}


void ShipEntity::enterDock(::StationEntity *station)
{
	// throw these away now we're docked...
	dockingInstructions = oo::PList();
	
	doScriptEvent(OOJSID("shipWillDockWithStation"), station);
	doScriptEvent(OOJSID("shipDockedWithStation"), station);
	if (shipAI != nullptr)  shipAI->message("DOCKED");
	if (station != nullptr)  station->noteDockedShip(this);
	if (UNIVERSE != nullptr)  UNIVERSE->removeEntity(this);
}


void ShipEntity::leaveDock(::StationEntity *station)
{
	// This code is never used. Currently npc ships are only launched from the stations launch queue.
	if (station == nil)  return;
	
	if (station != nullptr)  station->launchShip(this);

}


void ShipEntity::enterWormhole(::WormholeEntity *w_hole)
{
	enterWormhole(w_hole, YES);
}


void ShipEntity::enterWormhole(::WormholeEntity *w_hole, bool /* replacing */)
{
	if (w_hole == nil)  return;
	if (status() == STATUS_ENTERING_WITCHSPACE)
	{
		return; // has already entered a different wormhole
	}
	// Replacement ships now handled by system repopulator

	// MKW 2011.02.27 - Moved here from ShipEntityAI so escorts reliably follow
	//                  mother in all wormhole cases, not just when the ship
	//                  creates the wormhole.
	addTarget(w_hole);	// its Objective-C object (C++ since bead oo-9ht.112)
	setFoundTarget(w_hole);
	if (shipAI != nullptr)  shipAI->reactToMessage("WITCHSPACE OKAY", "performHyperSpaceExit");	// must be a reaction, the ship is about to disappear
	
	// CIM 2012.07.22 above only covers those cases where ship expected to leave
	if (escortArray().size() > 1)
	{
		// so wormhole escorts anyway if it leaves unexpectedly.
		wormholeEscorts();
	}

	if (scriptedMisjump())
	{
		setScriptedMisjump(NO);
		if (w_hole != nullptr)  w_hole->setMisjumpWithRange(scriptedMisjumpRange());
		setScriptedMisjumpRange(0.5);
	}
	if (w_hole != nullptr)  w_hole->suckInShip(this);	// removes ship from universe
}


void ShipEntity::enterWitchspace()
{
	if (UNIVERSE != nullptr)  UNIVERSE->addWitchspaceJumpEffectForShip(this);
	if (shipAI != nullptr)  shipAI->message("ENTERED_WITCHSPACE");
	
	if (!((UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr) != nullptr ? UNIVERSE->sun()->willGoNova() : false))
	{
		// if the sun's not going nova, add a new ship like this one leaving.
		if (UNIVERSE != nullptr)  UNIVERSE->witchspaceShipWithPrimaryRole(getPrimaryRole().value_or(""));
	}
	
	if (UNIVERSE != nullptr)  UNIVERSE->removeEntity(this);
}


void ShipEntity::leaveWitchspace()
{
	Quaternion	q1;
	quaternion_set_random(&q1);
	Vector		v1 = vector_forward_from_quaternion(q1);
	double		d1 = 0.0;
	
	GLfloat min_d1 = (UNIVERSE != nullptr ? UNIVERSE->safeWitchspaceExitDistance() : 0.0f);

	while (fabs(d1) < min_d1)
	{
		// not scannerRange - has no effect on witchspace exit
		d1 = SCANNER_MAX_RANGE * (randf() - randf());
	}
	
	HPVector exitposition = (UNIVERSE != nullptr ? UNIVERSE->getWitchspaceExitPosition() : HPVector{});
	exitposition.x += v1.x * d1; // randomise exit position
	exitposition.y += v1.y * d1;
	exitposition.z += v1.z * d1;
	setPosition(exitposition);
	witchspaceLeavingEffects();
}




// Slice 32 of docs/phases/3-slices/ShipEntity.md (bead oo-5e0ny): witchspace effects, offences,
// lights, escort formation and deployment, nearest stations. Members of the C++ ship, called
// directly, since bead oo-9ht.144 deleted the facade (ADR-0056 amendment oo-9ht.144).

bool ShipEntity::witchspaceLeavingEffects()
{
	// all ships exiting witchspace will share the same orientation.
	orientation = (UNIVERSE != nullptr ? UNIVERSE->getWitchspaceExitRotation() : Quaternion{});
	flightRoll = 0.0;
	stick_roll = 0.0;
	flightPitch = 0.0;
	stick_pitch = 0.0;
	flightYaw = 0.0;
	stick_yaw = 0.0;
	flightSpeed = 50.0; // constant speed same for all ships
// was a quarter of max speed, so the Anaconda speeds up and most
// others slow down - CIM
// will be overridden if left witchspace via a genuine wormhole
	velocity = kZeroVector;
	if (!(UNIVERSE != nullptr ? UNIVERSE->addEntity(this) : false))	// AI and status get initialised here
	{
		return NO;
	}
	setStatus(STATUS_EXITING_WITCHSPACE);
	if (shipAI != nullptr)  shipAI->message("EXITED_WITCHSPACE");
	
	if (UNIVERSE != nullptr)  UNIVERSE->addWitchspaceJumpEffectForShip(this);
	setStatus(STATUS_IN_FLIGHT);
	return YES;
}


void ShipEntity::markAsOffender(int offence_value)
{
	markAsOffender(offence_value, kOOLegalStatusReasonUnknown);
}


void ShipEntity::markAsOffender(int offence_value, OOLegalStatusReason reason)
{
	if (!isPolice() && !isCloaked() && this != (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr))
	{
		if (getIsSubEntity()) 
		{
			if (oo::ToShip(parentEntity()) != nullptr)  oo::ToShip(parentEntity())->markAsOffender(offence_value, reason);
		}
		else
		{
			if ((scanClass == CLASS_THARGOID || scanClass == CLASS_STATION) && reason != kOOLegalStatusReasonSetup && reason != kOOLegalStatusReasonByScript)
			{
				return; // no non-scripted bounties for thargoids and stations
			}

			ooscript::Context context = OOJSAcquireContext();
	
			ooscript::Value amountVal = ooscript::undefinedValue();
			ooscript::newNumberValue(context, (bounty | offence_value)-bounty, &amountVal);

			bounty |= offence_value; // can't set the new bounty until the size of the change is known

			ooscript::Value reasonVal = OOJSValueFromLegalStatusReason(context, reason);
		
			ShipScriptEvent(context, this, "shipBountyChanged", amountVal, reasonVal);
		
			OOJSRelinquishContext(context);
		
		}
	}
}


// Exposed to AI
void ShipEntity::switchLightsOn()
{
	_lightsActive = YES;

	const std::vector<oo::EntityHold> subs = subEntities;
	for (const auto &se : subs)
	{
		if (OOFlasherEntity *flasher = dynamic_cast<OOFlasherEntity *>(se.get()))  flasher->setActive(YES);
	}
	for (const auto &sub : shipSubEntities())
	{
		if (oo::ToShip(sub.get()) != nullptr)  oo::ToShip(sub.get())->switchLightsOn();
	}
}


// Exposed to AI
void ShipEntity::switchLightsOff()
{
	_lightsActive = NO;

	const std::vector<oo::EntityHold> subs = subEntities;
	for (const auto &se : subs)
	{
		if (OOFlasherEntity *flasher = dynamic_cast<OOFlasherEntity *>(se.get()))  flasher->setActive(NO);
	}
	for (const auto &sub : shipSubEntities())
	{
		if (oo::ToShip(sub.get()) != nullptr)  oo::ToShip(sub.get())->switchLightsOff();
	}
}


bool ShipEntity::lightsActive()
{
	return _lightsActive;
}


void ShipEntity::setDestination(HPVector dest)
{
	_destination = dest;
	frustration = 0.0;	// new destination => no frustration!
}


void ShipEntity::setEscortDestination(HPVector dest)
{
	_destination = dest; // don't reset frustration for escorts.
}


bool ShipEntity::canAcceptEscort(::ShipEntity *potentialEscort)
{
	if (!dockingInstructions.isNull()) // we are busy with docking.
	{
		return NO;
	}
	if (scanClass != (potentialEscort != nullptr ? potentialEscort->getScanClass() : OOScanClass{})) // this makes sure that wingman can only select police, thargons only thargoids.
	{
		return NO;
	}
	if (getBounty() == 0 && (potentialEscort != nullptr ? potentialEscort->getBounty() : 0) != 0) // clean mothers can only accept clean escorts
	{
		return NO;
	}
	if (!isEscort()) // self is NOT wingman or escort or thargon
	{
		return (potentialEscort != nullptr ? potentialEscort->isEscort() : false); // is wingman or escort or thargon
	}
	return NO;
}


bool ShipEntity::acceptAsEscort(::ShipEntity *other_ship)
{
	// can't pair with self
	if (this == other_ship)  return NO;
	
	// no longer in flight, probably entered wormhole without telling escorts.
	if (status() != STATUS_IN_FLIGHT)  return NO;
	
	//increased stack depth at which it can accept escorts to avoid rejections at this stage.
	//doesn't seem to have any adverse effect for now. - Kaks.
	if ((shipAI != nullptr ? shipAI->stackDepth() : NSUInteger{}) > 3)
	{
		OO_LOG("ship.escort.reject", "{} rejecting escort {} because AI stack depth is {}.", oo::EntityDescription(this), oo::EntityDescription(other_ship), (shipAI != nullptr ? shipAI->stackDepth() : NSUInteger{}));
		return NO;
	}
	
	if (canAcceptEscort(other_ship))
	{
		::OOShipGroup *escortGroup = this->escortGroup();
		
		if ((escortGroup != nullptr ? escortGroup->containsShip(other_ship) : false))  return YES;
		
		// check total number acceptable
		// the system's patrols don't have escorts set inside their dictionary, but accept max escorts.
		if (_maxEscortCount == 0 && (hasPrimaryRole("police") || hasPrimaryRole("hunter") || hasRole("thargoid-mothership"))) 
		{
			_maxEscortCount = MAX_ESCORTS;
		}
		
		NSUInteger maxEscorts = _maxEscortCount; 	// never bigger than MAX_ESCORTS.
		NSUInteger escortCount = (escortGroup != nullptr ? escortGroup->count() : 0) - 1;	// always 0 or higher.
		
		if (escortCount < maxEscorts)
		{
			if (other_ship != nullptr)  other_ship->setGroup(escortGroup);
			if (group() == nil)
			{
				setGroup(escortGroup);
			}
			else if (group() != escortGroup)  { if (group() != nullptr)  group()->addShip(other_ship); }
			
			if (((other_ship != nullptr ? other_ship->getMaxFlightSpeed() : 0.0f) < cruiseSpeed) && ((other_ship != nullptr ? other_ship->getMaxFlightSpeed() : 0.0f) > cruiseSpeed * 0.3))
			{
				cruiseSpeed = (other_ship != nullptr ? other_ship->getMaxFlightSpeed() : 0.0f) * 0.99;
			}
			
			OO_LOG("ship.escort.accept", "{} accepting escort {}.", oo::EntityDescription(this), oo::EntityDescription(other_ship));
			
			doScriptEvent(OOJSID("shipAcceptedEscort"), other_ship);
			if (other_ship != nullptr)  other_ship->doScriptEvent(OOJSID("escortAccepted"), this);
			if (shipAI != nullptr)  shipAI->message("ACCEPTED_ESCORT");
			return YES;
		}
		else
		{
			OO_LOG("ship.escort.reject", "{} already got max escorts({}). Escort rejected: {}.", oo::EntityDescription(this), escortCount, oo::EntityDescription(other_ship));
		}
	}
	else
	{
		OO_LOG("ship.escort.reject", "{} failed canAcceptEscort for escort {}.", oo::EntityDescription(this), oo::EntityDescription(other_ship));
	}

	
	return NO;
}


// Exposed to AI
void ShipEntity::updateEscortFormation()
{
	_escortPositionsValid = NO;
}


/*
	NOTE: it's tempting to call refreshEscortPositions from coordinatesForEscortPosition:
	as needed, but that would cause unnecessary extra work if the formation
	callback itself calls updateEscortFormation.
*/
void ShipEntity::refreshEscortPositions()
{
	if (!_escortPositionsValid)
	{
		ooscript::Context context = OOJSAcquireContext();
		ooscript::Value				result;
		ooscript::Value				args[] = { ooscript::int32Value(0), ooscript::int32Value(_maxEscortCount) };
		BOOL				OK;
		
		// Reset validity first so updateEscortFormation can be called from the update callback.
		_escortPositionsValid = YES;
		
		uint8_t i;
		for (i = 0; i < _maxEscortCount; i++)
		{
			args[0] = ooscript::int32Value(i);
			OK = (script != nullptr ? script->callMethod(OOJSID("coordinatesForEscortPosition"), context, args, sizeof args / sizeof *args, &result) : false);
			
			if (OK)  OK = JSValueToVector(context, result, &_escortPositions[i]);
			
			if (!OK)  _escortPositions[i] = kZeroVector;
		}
		
		OOJSRelinquishContext(context);
	}
}


HPVector ShipEntity::coordinatesForEscortPosition(unsigned idx)
{
	/*
		This function causes problems with Thargoids: their missiles (aka Thargons) are automatically
		added to the escorts group, and when a mother ship dies all thargons will attach themselves
		as escorts to the surviving battleships. This can lead to huge escort groups.
		TODO: better handling of Thargoid groups:
			- put thargons (& all other thargon missiles) in their own non-escort group perhaps?
	*/
	
	// The _escortPositions array is always MAX_ESCORTS long.
	// Kludge: return the same last escort position if we have escorts above MAX_ESCORTS...
	idx = MIN(idx, (unsigned)(MAX_ESCORTS - 1));
	
	return HPvector_add(position, vectorToHPVector(quaternion_rotate_vector(normalOrientation(), _escortPositions[idx])));
}


// Exposed to AI
void ShipEntity::deployEscorts()
{
	::ShipEntity		*target = nil;
	std::vector<oo::EntityHold>	idleEscorts;	// in escort order (was a mutable set: hash order)
	unsigned		deployCount;
	
	if (primaryTarget() == nil || _escortGroup == nil)  return;
	
	::OOShipGroup *escortGroup = this->escortGroup();
	NSUInteger escortCount = (escortGroup != nullptr ? escortGroup->count() : 0) - 1;  // escorts minus leader.
	if (escortCount == 0)  return;
	
	if (group() == nil)  setGroup(escortGroup);
	
	if (primaryTarget() == lastEscortTarget())
	{
		// already deployed escorts onto this target!
		return;
	}
	
	setLastEscortTarget(primaryTarget());
	
	// Find idle escorts
	for (const auto &escortRef : escorts())
	{
		::ShipEntity *escort = oo::ToShip(escortRef.get());
		if ((escort != nullptr && escort->getAI() != nullptr ? escort->getAI()->name() : std::optional<std::string>()).value_or(std::string()) != "interceptAI.plist" && !(escort != nullptr ? escort->hasNewAI() : false))
		{
			idleEscorts.push_back(escortRef);
		}
		else if ((escort != nullptr ? escort->hasNewAI() : false))
		{
			// JS-based escorts get a help request
			if (escort != nullptr)  escort->doScriptEvent(OOJSID("helpRequestReceived"), this, primaryTarget());
		}
	}
	
	escortCount = idleEscorts.size();
	if (escortCount == 0)  return;

	deployCount = ranrot_rand() % escortCount + 1;

	// Deploy deployCount idle escorts.
	target = oo::ToShip(primaryTarget());
	for (const auto &escortRef : idleEscorts)
	{
		::ShipEntity *escort = oo::ToShip(escortRef.get());
		if (escort != nullptr)  escort->addTarget(target);
		if (escort != nullptr)  escort->setAITo("interceptAI.plist");
		if (escort != nullptr)  escort->doScriptEvent(OOJSID("escortAttack"), target);
		
		if (--deployCount == 0)  break;
	}
	
	updateEscortFormation();
}


// Exposed to AI
void ShipEntity::dockEscorts()
{
	if (!hasEscorts())  return;
	
	::OOShipGroup			*escortGroup = this->escortGroup();
	::ShipEntity			*target = oo::ToShip(primaryTarget());
	unsigned			i = 0;
	// Note: works on escortArray rather than escortEnumerator because escorts may be mutated.
	for (const auto &escortRef : escortArray())
	{
		::ShipEntity	*escort = oo::ToShip(escortRef.get());
		float		delay = i++ * 3.0 + 1.5;		// send them off at three second intervals
		::AI			*ai = (escort != nullptr ? escort->getAI() : (::AI *)nullptr);
		
		// act individually now!
		if ((escort != nullptr ? escort->group() : (OOShipGroup *)nullptr) == escortGroup)  { if (escort != nullptr)  escort->setGroup(nullptr); }
		if (oo::LiveOwner(escort) == this)  { if (escort != nullptr)  escort->setOwner(escort); }
		if(target && (target != nullptr ? target->getIsStation() : false)) { if (escort != nullptr)  escort->setTargetStation(target); }
		// JSAI: handles own delay
		if (!(escort != nullptr ? escort->hasNewAI() : false))
		{
			if (escort != nullptr)  escort->setAITo("dockingAI.plist");
			if (ai != nullptr)  ai->setState("ABORT", delay + 0.25);
		}
		if (escort != nullptr)  escort->doScriptEvent(OOJSID("escortDock"), { oo::PList::singleReal(delay) });
	}
	
	// We now have no escorts.
	_escortGroup = nullptr;
}


void ShipEntity::setTargetToNearestStationIncludingHostiles(bool includeHostiles)
{
	// check if the groupID (parent ship) points to a station...
	Entity		*mother = (group() != nullptr ? group()->leader() : (::ShipEntity *)nil);
	if (mother != nullptr && mother->getIsStation())
	{
		addTarget(mother);
		setTargetStation(mother);
		return;	// head for mother!
	}

	/*- selects the nearest station it can find -*/
	if (!UNIVERSE)
		return;
	int			ent_count = UNIVERSE->n_entities;
	Entity		**uni_entities = UNIVERSE->sortedEntities;	// grab the public sorted list
	std::vector<Entity*> my_entities(ent_count);
	int i;
	int station_count = 0;
	for (i = 0; i < ent_count; i++)
		if (uni_entities[i]->isStation)
			my_entities[station_count++] = oo::RetainEntity(uni_entities[i]);		//	retained
	//
	::StationEntity *thing = nil, *station = nil;
	double range2, nearest2 = SCANNER_MAX_RANGE2 * 1000000.0; // 1000x typical scanner range (25600 km), squared.
	for (i = 0; i < station_count; i++)
	{
		thing = oo::ToStation(my_entities[i]);
		range2 = HPdistance2(position, thing->position);
		if (range2 < nearest2 && (includeHostiles || !(thing != nullptr ? thing->isHostileTo(this) : false)))
		{
			station = thing;
			nearest2 = range2;
		}
	}
	for (i = 0; i < station_count; i++)
		oo::ReleaseEntity(my_entities[i]);		//	released
	//
	if (station)
	{
		addTarget(station);
		setTargetStation(station);
	}
	else
	{
		if (shipAI != nullptr)  shipAI->message("NO_STATION_FOUND");
	}
}


// Exposed to AI
void ShipEntity::setTargetToNearestFriendlyStation()
{
	setTargetToNearestStationIncludingHostiles(NO);
}


// Exposed to AI
void ShipEntity::setTargetToNearestStation()
{
	setTargetToNearestStationIncludingHostiles(YES);
}


// Exposed to AI
void ShipEntity::setTargetToSystemStation()
{
	::StationEntity* system_station = (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr);
	
	if (!system_station)
	{
		if (shipAI != nullptr)  shipAI->message("NOTHING_FOUND");
		if (shipAI != nullptr)  shipAI->message("NO_STATION_FOUND");
		_primaryTarget = nullptr;
		setTargetStation(nullptr);
		return;
	}
	
	if (!system_station->isStation)
	{
		if (shipAI != nullptr)  shipAI->message("NOTHING_FOUND");
		if (shipAI != nullptr)  shipAI->message("NO_STATION_FOUND");
		_primaryTarget = nullptr;
		setTargetStation(nullptr);
		return;
	}
	
	addTarget(system_station);
	setTargetStation(system_station);
	return;
}




// Slice 33 of docs/phases/3-slices/ShipEntity.md (bead oo-tz2ra): landing, docking abort,
// broadcasts and comms, fines, AI messages, spawning, close contacts, salvage. Members of the C++
// ship, called directly, since bead oo-9ht.144 deleted the facade (ADR-0056 amendment oo-9ht.144).

void ShipEntity::landOnPlanet(::OOPlanetEntity *planet)
{
	if (planet && isShuttle())
	{
		if (planet != nullptr)  planet->welcomeShuttle(this);
	}
	doScriptEvent(OOJSID("shipLandedOnPlanet"), planet, "LANDED_ON_PLANET");
	
#ifndef NDEBUG
	if (getReportAIMessages())
	{
		OO_LOG("planet.collide.shuttleLanded", "DEBUG: {} landed on planet {}", oo::EntityDescription(this), oo::EntityDescription(planet));
	}
#endif
	
	if (UNIVERSE != nullptr)  UNIVERSE->removeEntity(this);
}


// Exposed to AI
void ShipEntity::abortDocking()
{
	// -makeObjectsPerformSelector:withObject: of the stations, in order
	for (const oo::EntityHold &station : (UNIVERSE != nullptr ? UNIVERSE->findEntitiesMatchingPredicate(IsStationPredicate, nullptr, -1, nullptr) : std::vector<oo::EntityHold>()))
	{
		if (oo::ToStation(station.get()) != nullptr)  oo::ToStation(station.get())->abortDockingForShip(this);
	}
}


oo::PList ShipEntity::getDockingInstructions()
{
	return dockingInstructions;
}


void ShipEntity::broadcastThargoidDestroyed()
{
	std::string role = "tharglet";
	// -makeObjectsPerformSelector:withObject: of the ships, in order
	for (const oo::EntityHold &ship : (UNIVERSE != nullptr ? UNIVERSE->findShipsMatchingPredicate(HasRolePredicate, &role, SCANNER_MAX_RANGE, this) : std::vector<oo::EntityHold>()))
	{
		if (oo::ToShip(ship.get()) != nullptr)  oo::ToShip(ship.get())->sendAIMessage("THARGOID_DESTROYED");
	}
}


void ShipEntity::broadcastHitByLaserFrom(::ShipEntity *aggressor_ship)
{
	/*-- If you're clean, locates all police and stations in range and tells them OFFENCE_COMMITTED --*/
	if (!UNIVERSE)  return;
	if (getBounty())  return;
	if (!aggressor_ship)  return;
	
	if (	(scanClass == CLASS_NEUTRAL)||
			(scanClass == CLASS_STATION)||
			(scanClass == CLASS_BUOY)||
			(scanClass == CLASS_POLICE)||
			(scanClass == CLASS_MILITARY)||
			(scanClass == CLASS_PLAYER))	// only for active ships...
	{
		AuthorityPredicateParameter param = { this, (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr), (bool)withinStationAegis() };
		const std::vector<oo::EntityHold> authorities = (UNIVERSE != nullptr ? UNIVERSE->findShipsMatchingPredicate(AuthorityPredicate, &param, -1, nullptr) : std::vector<oo::EntityHold>());
		for (const auto &authority : authorities)
		{
			::ShipEntity *auth = oo::ToShip(authority.get());
			if (auth != nullptr)  auth->setFoundTarget(aggressor_ship);
			if (auth != nullptr)  auth->doScriptEvent(OOJSID("offenceCommittedNearby"), aggressor_ship, this);
			if (auth != nullptr)  auth->reactToAIMessage("OFFENCE_COMMITTED", "combat update");
		}
	}
}


void ShipEntity::sendMessage(const std::string &message_text, ::ShipEntity *other_ship, bool unpilotedOverride)
{
	if (!other_ship) return;
	if (!crew && !unpilotedOverride) return;

	double d2 = HPdistance2(position, (other_ship != nullptr ? other_ship->getPosition() : HPVector{}));
	if (d2 > scannerRange * scannerRange)
		return;					// out of comms range

	const std::string expandedMessage = ExpandedText(message_text); // consistent with broadcast message.

	if (other_ship->isPlayer)
	{
		setCommsMessageColor();
		static_cast<PlayerEntity *>(other_ship)->receiveCommsMessage(expandedMessage, this);
		messageTime = 6.0;
		if (UNIVERSE != nullptr)  UNIVERSE->resetCommsLogColor();
	}
	else
		if (other_ship != nullptr)  other_ship->receiveCommsMessage(expandedMessage, this);
}


void ShipEntity::sendExpandedMessage(const std::string &message_text, ::ShipEntity *other_ship)
{
	if (!other_ship || !crew)
		return;	// nobody to receive or send the signal
	if ((lastRadioMessage) && (messageTime > 0.0) && message_text == *lastRadioMessage)
		return;	// don't send the same message too often
	lastRadioMessage = message_text;

	double d2 = HPdistance2(position, (other_ship != nullptr ? other_ship->getPosition() : HPVector{}));
	if (d2 > scannerRange * scannerRange)
	{
		// out of comms range
		return;
	}
	
	Random_Seed very_random_seed;
	very_random_seed.a = rand() & 255;
	very_random_seed.b = rand() & 255;
	very_random_seed.c = rand() & 255;
	very_random_seed.d = rand() & 255;
	very_random_seed.e = rand() & 255;
	very_random_seed.f = rand() & 255;
	seed_RNG_only_for_planet_description(very_random_seed);
	
	// The specials dictionary as +dictionaryWithObjectsAndKeys: built it: it ended at the first nil.
	oo::PList::Dict specials;
	const std::optional<std::string> selfName = getDisplayName();
	if (selfName.has_value())
	{
		specials["[self:name]"] = *selfName;
		const std::optional<std::string> targetName = (other_ship != nullptr ? other_ship->identFromShip(this) : std::optional<std::string>());
		if (targetName.has_value())  specials["[target:name]"] = *targetName;
	}
	const std::optional<std::string> expandedMessage = cxx_OOExpandDescriptionString(OOStringExpanderDefaultRandomSeed(), message_text, oo::PList(std::move(specials)), oo::PList(), std::nullopt, kOOExpandNoOptions);

	if (expandedMessage.has_value())  sendMessage(*expandedMessage, other_ship, NO);	// nil was not sent
}


void ShipEntity::broadcastAIMessage(const std::string &ai_message)
{
	const std::string expandedMessage = ExpandedText(ai_message);

	checkScanner();
	unsigned i;
	for (i = 0; i < n_scanned_ships ; i++)
	{
		::ShipEntity* ship = scanned_ships[i];
		if (ship != nullptr && ship->getAI() != nullptr)  ship->getAI()->message(expandedMessage);
	}
}


void ShipEntity::broadcastMessage(const std::string &message_text, bool unpilotedOverride)
{
	const std::string expandedMessage = ExpandedText(message_text); // consistent with broadcast message.


	if (!crew && !unpilotedOverride)
		return;	// nobody to send the signal and no override for unpiloted craft is set

	checkScanner();
	unsigned i;
	for (i = 0; i < n_scanned_ships ; i++)
	{
		::ShipEntity* ship = scanned_ships[i];
		if (!(ship != nullptr ? ship->getIsPlayer() : false)) { if (ship != nullptr)  ship->receiveCommsMessage(expandedMessage, this); }
	}
	
	::PlayerEntity *player = PLAYER; // make sure that the player always receives a message when in range
	// SCANNER_MAX_RANGE2 because it's the player's scanner range
	// which is important
	if (HPdistance2(position, (player != nullptr ? player->getPosition() : HPVector{})) < SCANNER_MAX_RANGE2)
	{
		setCommsMessageColor();
		if (player != nullptr)  player->receiveCommsMessage(expandedMessage, this);
		messageTime = 6.0;
		if (UNIVERSE != nullptr)  UNIVERSE->resetCommsLogColor();
	}
}


void ShipEntity::setCommsMessageColor()
{
	float hue = 0.0625f * (universalID & 15);
	UNIVERSE->commLogGUI()->setTextColor(OOColor::colorWithHue(hue, 0.375f, 1.0f, 1.0f).get());
	if (scanClass == CLASS_THARGOID)
		UNIVERSE->commLogGUI()->setTextColor(OOColor::greenColor().get());
	if (scanClass == CLASS_POLICE)
		UNIVERSE->commLogGUI()->setTextColor(OOColor::cyanColor().get());
}


void ShipEntity::receiveCommsMessage(const std::string &message_text, ::ShipEntity *other)
{
	// Too complex for AI scripts to handle, JS event only.
	doScriptEvent(OOJSID("commsMessageReceived"), { oo::PList(message_text), oo::EntityObjectNode(other) });
}


void ShipEntity::commsMessage(const std::string &valueString, bool unpilotedOverride)
{
	Random_Seed very_random_seed;
	very_random_seed.a = rand() & 255;
	very_random_seed.b = rand() & 255;
	very_random_seed.c = rand() & 255;
	very_random_seed.d = rand() & 255;
	very_random_seed.e = rand() & 255;
	very_random_seed.f = rand() & 255;
	seed_RNG_only_for_planet_description(very_random_seed);
	
	broadcastMessage(valueString, unpilotedOverride);
}


bool ShipEntity::markedForFines()
{
	return being_fined;
}


bool ShipEntity::markForFines()
{
	if (being_fined)
		return NO;	// can't mark twice
	being_fined = (legalStatus() > 0);
	return being_fined;
}


bool ShipEntity::isMining()
{
	return ((behaviour == BEHAVIOUR_ATTACK_MINING_TARGET)&&((forward_weapon_type != nullptr ? forward_weapon_type->isMiningLaser() : false)));
}


void ShipEntity::interpretAIMessage(const std::string &ms)
{
	if (oo::str::hasPrefix(ms, std::string(AIMS_AGGRESSOR_SWITCHED_TARGET)))
	{
		// if I'm under attack send a thank-you message to the rescuer
		//
		const std::vector<std::string> tokens = oo::str::tokens(ms);
		if (tokens.size() < 3)  return;	// (-objectAtIndex: raised on a short message; never sent)
		int switcher_id = oo::str::intValue(tokens[1]); // Attacker that switched targets.
		Entity *switcher = (UNIVERSE != nullptr ? UNIVERSE->entityForUniversalID(switcher_id) : nullptr);	// the C++ entity (bead oo-9ht.39.26)
		int rescuer_id = oo::str::intValue(tokens[2]); // New primary target of attacker.
		Entity *rescuer = (UNIVERSE != nullptr ? UNIVERSE->entityForUniversalID(rescuer_id) : nullptr);
		if ((switcher == primaryAggressor())&&(switcher == primaryTarget())&&(switcher)&&(rescuer)&&(rescuer->isShip)&&(thankedShip() != rescuer)&&(scanClass != CLASS_THARGOID))
		{
			::ShipEntity* rescueShip = oo::ToShip(rescuer);
//			ShipEntity* switchingShip = (ShipEntity*)switcher;
			if (scanClass == CLASS_POLICE)
			{
				sendExpandedMessage("[police-thanks-for-assist]", rescueShip);
				if (rescueShip != nullptr)  rescueShip->setBounty((rescueShip != nullptr ? rescueShip->getBounty() : 0) * 0.80, kOOLegalStatusReasonAssistingPolice);	// lower bounty by 20%
			}
			else
			{
				sendExpandedMessage("[thanks-for-assist]", rescueShip);
			}
			setThankedShip(rescuer);
		}
	}
}


BoundingBox ShipEntity::findBoundingBoxRelativeTo(Entity *other, Vector _i, Vector _j, Vector _k)
{
	HPVector  opv = other ? other->position : position;
	return findBoundingBoxRelativeToPosition(opv, _i, _j, _k);
}


// Exposed to AI and legacy scripts.
void ShipEntity::spawn(const std::string &roles_number)
{
	const std::vector<std::string> tokens = oo::str::tokens(roles_number);
	NSUInteger	number;

	if (tokens.size() != 2)
	{
		OO_LOG("script.debug.syntax.addShips", "***** Could not spawn: \"{}\" (must be two tokens, role and number)", roles_number);
		return;
	}

	const std::string &roleString = tokens[0];
	const std::string &numberString = tokens[1];

	number = oo::str::intValue(numberString);

	spawnShipsWithRole(roleString, number);
}


int ShipEntity::checkShipsInVicinityForWitchJumpExit()
{
	// checks if there are any large masses close by
	// since we want to place the space station at least 10km away
	// the formula we'll use is K x m / d2 < 1.0
	// (m = mass, d2 = distance squared)
	// coriolis station is mass 455,223,200
	// 10km is 10,000m,
	// 10km squared is 100,000,000
	// therefore K is 0.22 (approx)

	int result = NO_TARGET;

	GLfloat k = 0.1;

	int			ent_count =		UNIVERSE->n_entities;
	Entity**	uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
	std::vector<::ShipEntity*> my_entities(ent_count);
	int i;

	int ship_count = 0;
	for (i = 0; i < ent_count; i++)
		if ((uni_entities[i]->isShip)&&(uni_entities[i] != this))
			my_entities[ship_count++] = oo::ToShip(oo::RetainEntity(uni_entities[i]));		//	retained
	//
	for (i = 0; (i < ship_count)&&(result == NO_TARGET) ; i++)
	{
		::ShipEntity* ship = my_entities[i];
		HPVector delta = HPvector_between(position, ship->position);
		GLfloat d2 = HPmagnitude2(delta);
		if (!(ship != nullptr ? ship->getIsPlayer() : false) || !(PLAYER != nullptr ? PLAYER->isDocked() : false))
		{ // player doesn't block if docked
			if ((k * (ship != nullptr ? ship->getMass() : 0.0f) > d2)&&(d2 < SCANNER_MAX_RANGE2))	// if you go off (typical) scanner from a blocker - it ceases to block
				result = (ship != nullptr ? ship->getUniversalID() : OOUniversalID{});
		}
	}
	for (i = 0; i < ship_count; i++)
		if (my_entities[i] != nullptr)  oo::ReleaseEntity(my_entities[i]);	//		released

	return result;
}


bool ShipEntity::getTrackCloseContacts()
{
	return trackCloseContacts;
}


void ShipEntity::setTrackCloseContacts(bool value)
{
	if (value == (BOOL)trackCloseContacts)  return;
	
	trackCloseContacts = value;
	// A fresh (empty) record either way; it is only read while tracking.
	closeContactsInfo.clear();
}


#if OO_SALVAGE_SUPPORT || !defined(NDEBUG)
// What oo::DescriptionOf printed for the deleted facade: "(null)" for none, else
// <OORoleSet 0x...>{roles} (OODescription.h).
namespace {
std::string RoleSetDescription(::OORoleSet *roleSet)
{
	if (roleSet == nullptr)  return "(null)";
	std::string result = oo::str::format("<OORoleSet %s>", oo::str::pointerDescription(roleSet).c_str());
	if (const std::optional<std::string> components = roleSet->descriptionComponents())  result += "{" + *components + "}";
	return result;
}
}	// namespace
#endif


#if OO_SALVAGE_SUPPORT
// Never used.

void ShipEntity::claimAsSalvage()
{
	// Create a bouy and beacon where the hulk is.
	// Get the main GalCop station to launch a pilot boat to deliver a pilot to the hulk.
	OO_LOG("claimAsSalvage.called", "claimAsSalvage called on {} {}", [this cxx_name].value_or("(null)"), RoleSetDescription(getRoleSet().get()));
	
	// Not an abandoned hulk, so don't allow the salvage
	if (![this isHulk])
	{
		OO_LOG("claimAsSalvage.failed.notHulk", "{}", "claimAsSalvage failed because not a hulk");
		return;
	}

	// Set target to main station, and return now if it can't be found
	[this setTargetToSystemStation];
	if ([this primaryTarget] == nil)
	{
		OO_LOG("claimAsSalvage.failed.noStation", "{}", "claimAsSalvage failed because did not find a station");
		return;
	}

	// Get the station to launch a pilot boat to bring a pilot out to the hulk (use a viper for now)
	::StationEntity *station = oo::ToStation([this primaryTarget]);
	OO_LOG("claimAsSalvage.requestingPilot", "{}", "claimAsSalvage asking station to launch a pilot boat");
	[station launchShipWithRole:"pilot"];
	[this setReportAIMessages:YES];
	OO_LOG("claimAsSalvage.success", "{}", "claimAsSalvage setting own state machine to capturedShipAI.plist");
	[this setAITo:"capturedShipAI.plist"];
}


void ShipEntity::sendCoordinatesToPilot()
{
	::Entity		*scan;
	::ShipEntity	*scanShip, *pilot;
	
	n_scanned_ships = 0;
	scan = z_previous;
	OO_LOG("ship.pilotage", "{}", "searching for pilot boat");
	while (scan &&(scan->isShip == NO))
	{
		scan = scan->z_previous;	// skip non-ships
	}

	pilot = nil;
	while (scan)
	{
		if (scan->isShip)
		{
			scanShip = oo::ToShip(scan);
			
			if ([this hasRole:"pilot"] == YES)
			{
				if ([scanShip primaryTarget] == nil)
				{
					OO_LOG("ship.pilotage", "{}", "found pilot boat with no target, will use this one");
					pilot = scanShip;
					[pilot setPrimaryRole:"pilot"];
					break;
				}
			}
		}
		scan = scan->z_previous;
		while (scan && (scan->isShip == NO))
		{
			scan = scan->z_previous;
		}
	}

	if (pilot != nil)
	{
		OO_LOG("ship.pilotage", "{}", "becoming pilot target and setting AI");
		[pilot setReportAIMessages:YES];
		[pilot addTarget:this];
		[pilot setAITo:"pilotAI.plist"];
		[this cxx_reactToAIMessage:"FOUND_PILOT" context:"flight update"];
	}
}
#endif




// Slice 34 of docs/phases/3-slices/ShipEntity.md (bead oo-nkyn3): salvage pilot, debug dump, script
// info, demo ship, script events and AI reactions, alert condition, shader helpers. Members of the
// C++ ship, called directly, since bead oo-9ht.144 deleted the facade (ADR-0056 amendment
// oo-9ht.144).

#if OO_SALVAGE_SUPPORT
void ShipEntity::pilotArrived()
{
	[this setHulk:NO];
	[this cxx_reactToAIMessage:"PILOT_ARRIVED" context:"flight update"];
}
#endif


#ifndef NDEBUG
void ShipEntity::dumpSelfState()
{
	std::vector<std::string>	flags;
	std::string				flagsString;

	OOEntityWithDrawable::dumpSelfState();	// [super dumpSelfState]
	
	OO_LOG("dumpState.shipEntity", "Type: {}", shipDataKey().value_or("(null)"));
	OO_LOG("dumpState.shipEntity", "Name: {}", name.value_or("(null)"));
	OO_LOG("dumpState.shipEntity", "Display Name: {}", getDisplayName().value_or("(null)"));
	OO_LOG("dumpState.shipEntity", "Roles: {}", RoleSetDescription(getRoleSet().get()));
	OO_LOG("dumpState.shipEntity", "Primary role: {}", primaryRole.value_or("(null)"));
	OO_LOG("dumpState.shipEntity", "Script: {}", (script != nullptr) ? script->description() : std::string("(null)"));
	OO_LOG("dumpState.shipEntity", "Subentity count: {}", subEntityCount());
	OO_LOG("dumpState.shipEntity", "Behaviour: {}", cxx_OOStringFromBehaviour(behaviour));
	Entity *target = primaryTarget();
	OO_LOG("dumpState.shipEntity", "Target: {}", target != nullptr ? oo::EntityDescription(target) : std::string("<none>"));
	OO_LOG("dumpState.shipEntity", "Destination: {}", cxx_HPVectorDescription(_destination));
	OO_LOG("dumpState.shipEntity", "Other destination: {}", cxx_HPVectorDescription(coordinates));
	OO_LOG("dumpState.shipEntity", "Waypoint count: {}", number_of_navpoints);
	OO_LOG("dumpState.shipEntity", "Desired speed: {:g}", desired_speed);
	OO_LOG("dumpState.shipEntity", "Thrust: {:g}", thrust);
	if (escortCount() != 0)  OO_LOG("dumpState.shipEntity", "Escort count: {}", static_cast<unsigned>(escortCount()));
	OO_LOG("dumpState.shipEntity", "Fuel: {}", fuel);
	OO_LOG("dumpState.shipEntity", "Fuel accumulator: {:g}", fuel_accumulator);
	OO_LOG("dumpState.shipEntity", "Missile count: {}", missiles);
	
	if (shipAI != nil && oo::log::willDisplay("dumpState.shipEntity.ai"))
	{
		OO_LOG("dumpState.shipEntity.ai", "{}", "AI:");
		OOLogPushIndent();
		OOLogIndent();
		try
		{
			if (shipAI != nullptr)  shipAI->dumpState();
		}
		catch (...) { if (!oo::CurrentOOException())  throw; }	// was @catch (id exception) {}: the game's exceptions only (oo::Exception since oo-rskgl.1)
		OOLogPopIndent();
	}
	OO_LOG("dumpState.shipEntity", "Accuracy: {:g}", accuracy);
	OO_LOG("dumpState.shipEntity", "Jink position: {}", VectorDescription(jink));
	OO_LOG("dumpState.shipEntity", "Frustration: {:g}", frustration);
	OO_LOG("dumpState.shipEntity", "Success factor: {:g}", success_factor);
	OO_LOG("dumpState.shipEntity", "Shots fired: {}", static_cast<unsigned>(shot_counter));
	OO_LOG("dumpState.shipEntity", "Time since shot: {:g}", shotTime());
	OO_LOG("dumpState.shipEntity", "Spawn time: {:g} ({:g} seconds ago)", getSpawnTime(), timeElapsedSinceSpawn());
	if (isBeacon())
	{
		OO_LOG("dumpState.shipEntity", "Beacon code: {}", beaconCode().value_or("(null)"));
	}
	OO_LOG("dumpState.shipEntity", "Hull temperature: {:g}", ship_temperature);
	OO_LOG("dumpState.shipEntity", "Heat insulation: {:g}", heatInsulation());
	
	#define ADD_FLAG_IF_SET(x)		if (x) { flags.push_back(#x); }
	ADD_FLAG_IF_SET(military_jammer_active);
	ADD_FLAG_IF_SET(docking_match_rotation);
	ADD_FLAG_IF_SET(pitching_over);
	ADD_FLAG_IF_SET(reportAIMessages);
	ADD_FLAG_IF_SET(being_mined);
	ADD_FLAG_IF_SET(being_fined);
	ADD_FLAG_IF_SET(isHulk);
	ADD_FLAG_IF_SET(trackCloseContacts);
	ADD_FLAG_IF_SET(isNearPlanetSurface);
	ADD_FLAG_IF_SET(isFrangible);
	ADD_FLAG_IF_SET(cloaking_device_active);
	ADD_FLAG_IF_SET(canFragment);
	ADD_FLAG_IF_SET(proximityAlert() != nullptr);
	for (const std::string &flag : flags)
	{
		if (!flagsString.empty())  flagsString += ", ";
		flagsString += flag;
	}
	if (flags.empty())  flagsString = "none";
	OO_LOG("dumpState.shipEntity", "Flags: {}", flagsString);
}
#endif


::OOScript *ShipEntity::getScript()
{
	return script.get();
}


oo::PList ShipEntity::getScriptInfo()
{
	return scriptInfo.isNull() ? oo::PList(oo::PList::Dict{}) : scriptInfo;	// empty rather than null
}


void ShipEntity::overrideScriptInfo(const oo::PList &override)
{
	if (scriptInfo.isNull())  scriptInfo = override;
	else if (!override.isNull())
	{
		// both are dictionaries: a copy with the override's entries added, replacing duplicates
		oo::PList::Dict newInfo = *scriptInfo.getIf<oo::PList::Dict>();
		for (const auto &[key, value] : *override.getIf<oo::PList::Dict>())  newInfo[key] = value;
		scriptInfo = oo::PList(std::move(newInfo));
	}
}


Entity *ShipEntity::entityForShaderProperties()
{
	return rootShipEntity();
}


void ShipEntity::setDemoShip(OOScalar rate)
{
	demoStartOrientation = orientation;
	demoRate = rate;
	isDemoShip = YES;
	setPitch(0.0f);
	setRoll(0.0f);
}


bool ShipEntity::getIsDemoShip()
{
	return isDemoShip;
}


void ShipEntity::setDemoStartTime(OOTimeAbsolute time)
{
	demoStartTime = time;
}


OOTimeAbsolute ShipEntity::getDemoStartTime()
{
	return demoStartTime;
}


// *** Script event dispatch.
void ShipEntity::doScriptEvent(ooscript::PropertyId message)
{
	ooscript::Context context = OOJSAcquireContext();
	doScriptEvent(message, context, NULL, 0);
	OOJSRelinquishContext(context);
}


// With entities (bead oo-9ht.39.16): each entity's JS value, what OOJSValueFromNativeObject()
// gave for its object (null for none). The id forms had no caller and are deleted (bead oo-4aq6a.6).
void ShipEntity::doScriptEvent(ooscript::PropertyId message, Entity *argument)
{
	ooscript::Context context = OOJSAcquireContext();
	
	ooscript::Value value = OOJSEntityJSValue(argument, context);
	doScriptEvent(message, context, &value, 1);
	
	OOJSRelinquishContext(context);
}


void ShipEntity::doScriptEvent(ooscript::PropertyId message, Entity *argument1, Entity *argument2)
{
	ooscript::Context context = OOJSAcquireContext();
	
	ooscript::Value argv[2] = { OOJSEntityJSValue(argument1, context), OOJSEntityJSValue(argument2, context) };
	doScriptEvent(message, context, argv, 2);
	
	OOJSRelinquishContext(context);
}


void ShipEntity::doScriptEvent(ooscript::PropertyId message, const std::vector<oo::PList> &arguments)
{
	ooscript::Context context = OOJSAcquireContext();
	unsigned					i, argc;
	ooscript::Value					*argv = NULL;

	// Convert arguments to JS values and make them temporarily un-garbage-collectable.
	argc = (unsigned)arguments.size();
	if (argc != 0)
	{
		argv = (decltype(argv))malloc(sizeof *argv * argc);
		if (argv != NULL)
		{
			for (i = 0; i != argc; ++i)
			{
				argv[i] = OOJSValueFromPList(context, arguments[i]);
				OOJSAddGCValueRoot(context, &argv[i], "event parameter");
			}
		}
		else  argc = 0;
	}
	
	doScriptEvent(message, context, argv, argc);
	
	// Re-garbage-collectibalize the arguments and free the array.
	if (argv != NULL)
	{
		for (i = 0; i != argc; ++i)
		{
			ooscript::removeValueRoot(context, &argv[i]);
		}
		free(argv);
	}
	
	OOJSRelinquishContext(context);
}


void ShipEntity::doScriptEvent(ooscript::PropertyId message, ooscript::Value *argv, unsigned argc)
{
	ooscript::Context context = OOJSAcquireContext();
	doScriptEvent(message, context, argv, argc);
	OOJSRelinquishContext(context);
}


void ShipEntity::doScriptEvent(ooscript::PropertyId message, ooscript::Context context, ooscript::Value *argv, unsigned argc)
{
	// This method is a bottleneck so that PlayerEntity can override at one point.
	if (script != nullptr)  script->callMethod(message, context, argv, argc, NULL);
	if (aiScript != nullptr)  aiScript->callMethod(message, context, argv, argc, NULL);
}


void ShipEntity::reactToAIMessage(const std::string &message, const std::optional<std::string> &debugContext)
{
	if (shipAI != nullptr)  shipAI->reactToMessage(message, debugContext);
}


void ShipEntity::sendAIMessage(const std::string &message)
{
	if (shipAI != nullptr)  shipAI->message(message);
}


void ShipEntity::doScriptEvent(ooscript::PropertyId scriptEvent, const std::string &aiMessage)
{
	doScriptEvent(scriptEvent);
	reactToAIMessage(aiMessage, std::nullopt);
}


void ShipEntity::doScriptEvent(ooscript::PropertyId scriptEvent, Entity *argument, const std::string &aiMessage)
{
	doScriptEvent(scriptEvent, argument);
	reactToAIMessage(aiMessage, std::nullopt);
}


// exposed for shaders; fake alert level
// since NPCs don't have torus drive, they're never at condition green
OOAlertCondition ShipEntity::alertCondition()
{
	if (status() == STATUS_DOCKED) 
	{
		return ALERT_CONDITION_DOCKED;
	}
	if (hasHostileTarget() || energy < maxEnergy / 4)
	{
		return ALERT_CONDITION_RED;
	}
	return ALERT_CONDITION_YELLOW;
}


OOAlertCondition ShipEntity::realAlertCondition()
{
	if (status() == STATUS_DOCKED) 
	{
		return ALERT_CONDITION_DOCKED;
	}
	if (hasHostileTarget())
	{
		return ALERT_CONDITION_RED;
	}
	else
	{
		::ShipEntity *ship = nil;
		double scanrange2 = scannerRange * scannerRange;
		for (const auto &defenseTarget : defenseTargets())
		{
			ship = oo::ToShip(defenseTarget.get());
			if ((ship != nullptr ? ship->hasHostileTarget() : false) || ((ship != nullptr ? ship->getIsPlayer() : false) && (PLAYER != nullptr ? PLAYER->weaponsOnline() : false)))
			{
				if (HPdistance2((ship != nullptr ? ship->getPosition() : HPVector{}),position) < scanrange2)
				{
					return ALERT_CONDITION_RED;
				}
			}
		}
		// also need to check primary target separately
		if (hasHostileTarget())
		{
			Entity *ptarget = primaryTargetWithoutValidityCheck();
			if (ptarget != nil && oo::EntityIsShip(ptarget))
			{
				ship = oo::ToShip(ptarget);
				if ((ship != nullptr ? ship->hasHostileTarget() : false) || ((ship != nullptr ? ship->getIsPlayer() : false) && (PLAYER != nullptr ? PLAYER->weaponsOnline() : false)))
				{
					if (HPdistance2((ship != nullptr ? ship->getPosition() : HPVector{}),position) < scanrange2 * 1.5625)
					{
						return ALERT_CONDITION_RED;
					}
				}
			}
		}
		if (_group)
		{
			OOShipGroupCursor cursor(_group.get());
			::ShipEntity *batch[16];
			for (NSUInteger count = ShipGroupCursorBatch(cursor, batch); count != 0; count = ShipGroupCursorBatch(cursor, batch))
			{
				for (NSUInteger i = 0; i < count; i++)
				{
					ship = batch[i];
					if ((ship != nullptr ? ship->hasHostileTarget() : false) || ((ship != nullptr ? ship->getIsPlayer() : false) && (PLAYER != nullptr ? PLAYER->weaponsOnline() : false)))
					{
						if (HPdistance2((ship != nullptr ? ship->getPosition() : HPVector{}),position) < scanrange2)
						{
							return ALERT_CONDITION_RED;
						}
					}
				}
			}
		}
		if (_escortGroup && _group != _escortGroup)
		{
			OOShipGroupCursor cursor(_escortGroup.get());
			::ShipEntity *batch[16];
			for (NSUInteger count = ShipGroupCursorBatch(cursor, batch); count != 0; count = ShipGroupCursorBatch(cursor, batch))
			{
				for (NSUInteger i = 0; i < count; i++)
				{
					ship = batch[i];
					if ((ship != nullptr ? ship->hasHostileTarget() : false) || ((ship != nullptr ? ship->getIsPlayer() : false) && (PLAYER != nullptr ? PLAYER->weaponsOnline() : false)))
					{
						if (HPdistance2((ship != nullptr ? ship->getPosition() : HPVector{}),position) < scanrange2)
						{
							return ALERT_CONDITION_RED;
						}
					}
				}
			}
		}
	}
	return ALERT_CONDITION_YELLOW;
}


// Exposed to AI and scripts.
void ShipEntity::doNothing()
{
	
}


#ifndef NDEBUG
std::optional<std::string> ShipEntity::descriptionForObjDump()
{
	// DescriptionOf(nil) was "(null)"; preserve that for a disengaged super result.
	std::string desc = oo::str::format("%s mass %g", OOEntityWithDrawable::descriptionForObjDump().value_or("(null)").c_str(), getMass());
	if (!getIsPlayer())
	{
		desc = oo::str::format("%s AI: %s", desc.c_str(), (getAI() != nullptr ? getAI()->shortDescriptionComponents() : std::optional<std::string>()).value_or("(null)").c_str());
	}
	return desc;
}
#endif




/*	Slice 34 (bead oo-nkyn3): the shader and weapon-range helpers, without messages. The resource
	manager and the equipment types answer through their C++ classes; the binding target's class is
	asked of the runtime, and its kind of entity of the entity's C++ part (getIsShip(),
	getIsVisualEffect(): the facade's -isShip and -isVisualEffect answer the same).
*/
oo::PList OODefaultShipShaderMacros(void)
{
	// "ship-prefix-macros" of the material defaults, read once; an empty dictionary if it is not one.
	static const oo::PList macros = []
	{
		const oo::PList materialDefaults = ResourceManager::materialDefaults();
		const oo::PList *prefixMacros = materialDefaults.get<oo::PList::Dict>("ship-prefix-macros");
		return prefixMacros != nullptr ? *prefixMacros : oo::PList(oo::PList::Dict{});
	}();

	return macros;
}


// is this the right place for this function now? - CIM
// The target is the C++ entity since bead oo-9ht.39.6; every entity's object was a kind of Entity.
BOOL OOUniformBindingPermitted(const std::string &propertyName, Entity *bindingTarget)
{
	// the whitelists, read once (membership only)
	static const oo::PList					wlDict = ResourceManager::whitelistDictionary();
	static const std::set<std::string>		entityWhitelist = NamesInArrayForKey(wlDict, "shader_entity_binding_methods");
	static const std::set<std::string>		shipWhitelist = NamesInArrayForKey(wlDict, "shader_ship_binding_methods");
	static const std::set<std::string>		playerShipWhitelist = NamesInArrayForKey(wlDict, "shader_player_ship_binding_methods");
	static const std::set<std::string>		visualEffectWhitelist = NamesInArrayForKey(wlDict, "shader_visual_effect_binding_methods");

	if (bindingTarget != nullptr)
	{
		Entity *entity = bindingTarget;
		if (entityWhitelist.contains(propertyName))  return YES;
		if (entity->getIsShip())
		{
			if (shipWhitelist.contains(propertyName))  return YES;
		}
		// -isPlayerLikeShip answered YES for these two only (ProxyPlayerEntity.mm); their objects are a
		// ship's since beads oo-9ht.177 and oo-9ht.183, so it is asked of the C++ part.
		if (dynamic_cast<PlayerEntity *>(entity) != nullptr || dynamic_cast<ProxyPlayerEntity *>(entity) != nullptr)
		{
			if (playerShipWhitelist.contains(propertyName))  return YES;
		}
		if (entity->getIsVisualEffect())
		{
			if (visualEffectWhitelist.contains(propertyName))  return YES;
		}
	}
	
	return NO;
}


GLfloat getWeaponRangeFromType(OOWeaponType weapon_type)
{
	// [nil weaponRange] answered 0.
	return weapon_type != nullptr ? weapon_type->weaponRange() : 0.0f;
}


BOOL isWeaponNone(OOWeaponType weapon)
{
	return weapon == nullptr || (weapon->identifier() == "EQ_WEAPON_NONE");
}
