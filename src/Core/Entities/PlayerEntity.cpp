/*

PlayerEntity.m

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

#include <assert.h>

#include "PlayerEntity.h"
#include "oofnd/Process.hpp"
#include "PlayerEntityLegacyScriptEngine.h"
#include "PlayerEntityContracts.h"
#include "PlayerEntityControls.h"
#include "PlayerEntitySound.h"
#include "PlayerEntityScriptMethods.h"

#include "StationEntity.h"
#include "OOSunEntity.h"
#include "OOPlanetEntity.h"
#include "WormholeEntity.h"
#include "ProxyPlayerEntity.h"
#include "OOQuiriumCascadeEntity.h"
#include "OOLaserShotEntity.h"
#include "OOMesh.h"

#include "OOMaths.h"
#include "GameController.h"
#include "ResourceManager.h"
#include "Universe.h"
#include "AI.h"
#include "ShipEntityAI.h"
#include "MyOpenGLView.h"
#include "OOTrumble.h"
#include "PlayerEntityLoadSave.h"
#include "OOSound.h"
#include "OOColor.h"
#include "Octree.h"
#include "OOCacheManager.h"
#include "OOOXZManager.h"
#include "OOStringExpander.h"
#include "OOStringParsing.h"
#include "OOPListParsing.h"
#include "OOConstToString.h"
#include "OOTexture.h"
#include "OORoleSet.h"
#include "HeadUpDisplay.h"
#include "OOOpenGLExtensionManager.h"
#include "OOMusicController.h"
#include "OOEntityFilterPredicate.h"
#include "OOShipRegistry.h"
#include "OOEquipmentType.h"
#include "OOFullScreenController.h"
#include "OODebugSupport.h"

#include "CollisionRegion.h"

#include "OOJSScript.h"
#include "OOJSVector.h"
#include "OOJSQuaternion.h"
#include "OOScriptTimer.h"
#include "OOJSEngineTimeManagement.h"
#include "OOJSInterfaceDefinition.h"
#include "OOJSGuiScreenKeyDefinition.h"
#include "OOConstToJSString.h"

#include "OOJoystickManager.h"
#include "PlayerEntityStickMapper.h"
#include "PlayerEntityStickProfile.h"
#include "PlayerEntityKeyMapper.h"
#include "OOSystemDescriptionManager.h"
#include "OOJSPlayerShip.h"
#include "oofnd/objc/OOException.h"
#include "oofnd/Defaults.hpp"
#include "oofnd/PListGet.hpp"
#include "oofnd/PListParsing.hpp"
#include "oofnd/FileSystem.hpp"
#include "oofnd/ResourcePaths.hpp"
#include "oofnd/Date.hpp"
#include "oofnd/objc/OOAssert.h"
#include "OOPListGameTypes.h"
#include <string_view>
#include "OOObjCPList.h"
#include "oofnd/String.hpp"


static constexpr std::string_view PLAYER_DEFAULT_NAME				= "Jameson";

enum
{
	// If comm log is kCommLogTrimThreshold or more lines long, it will be cut to kCommLogTrimSize.
	kCommLogTrimThreshold				= 15U,
	kCommLogTrimSize					= 10U
};


namespace
{

/*	What oo::PListView's string / vector / quaternion readers answered, for a
	configuration held as an oo::PList (the Foundation sweep, proposed ADR-0043): a string is
	nullopt when the key is absent or holds neither a string nor a number; vectors and quaternions
	go through OOCollectionExtractors' readers (unmigrated) with their defaults for a missing key.
	(Same readers as ShipEntity.mm's.)
*/
std::optional<std::string> StringForKey(const oo::PList &dict, std::string_view key)
{
	const oo::PList *value = dict.find(key);
	if (value == nullptr || !(value->isString() || value->isNumber()))  return std::nullopt;
	return oo::PListGet<std::string>::from(value, std::string());
}


// PointFromString() of a system's "coordinates" property: a string scans; nil (and a non-string
// value, which raised when read as a string) reads as the empty string, the zero point.
NSPoint PointFromCoordinates(const oo::PList &coordinates)
{
	const std::string *string = coordinates.getIf<std::string>();
	return cxx_PointFromString(string != nullptr ? *string : std::string());
}


Vector VectorForKey(const oo::PList &dict, std::string_view key, Vector fallback = kZeroVector)
{
	const oo::PList *value = dict.find(key);
	return OOVectorFromPList(value, fallback);
}


Quaternion QuaternionForKey(const oo::PList &dict, std::string_view key)
{
	const oo::PList *value = dict.find(key);
	return OOQuaternionFromPList(value, kIdentityQuaternion);
}


// -objectForKey: on a saved game: the value, or a null PList when absent.
const oo::PList &ValueForKey(const oo::PList &dict, std::string_view key)
{
	static const oo::PList none;
	const oo::PList *value = dict.find(key);
	return (value != nullptr) ? *value : none;
}


// -oo_stringAtIndex: (nullopt unless the element is a string or a number).
std::optional<std::string> StringAt(const oo::PList &array, std::size_t index)
{
	const oo::PList *value = array.at(index);
	if (value == nullptr || !(value->isString() || value->isNumber()))  return std::nullopt;
	return oo::PListGet<std::string>::from(value, std::string());
}


// ScanTokensFromString of a system's "coordinates" property (no tokens unless it is a string).
std::vector<std::string> CoordinateTokens(const oo::PList &coordinates)
{
	const std::string *text = coordinates.getIf<std::string>();
	return (text != nullptr) ? oo::str::tokens(*text) : std::vector<std::string>();
}


// -oo_unsignedCharAtIndex: on those tokens (0 when missing).
unsigned char CoordinateAt(const std::vector<std::string> &tokens, std::size_t index)
{
	if (index >= tokens.size())  return 0;
	const oo::PList token(tokens[index]);
	return oo::PListGet<unsigned char>::from(&token, 0);
}


// cxx_OOExpandKeyWithSeed(seed, key, ...) with its arguments as a Dict (ints as PList::signedInteger,
// NSUIntegers as PList::unsignedInteger, strings as std::string); no arguments passes the null PList,
// as the macro did; nothing expanded is "". Exemplar: OOShipLibraryDescriptions.mm ExpandCategoryKey.
std::string ExpandKeyWithSeed(Random_Seed seed, const std::string &key, const oo::PList::Dict &args)
{
	return cxx_OOExpandDescriptionString(seed, key, args.empty() ? oo::PList() : oo::PList(args),
		oo::PList(), std::nullopt, kOOExpandKey).value_or(std::string());
}


// A %@ argument for oo::str::formatRuntime: the text, or "(null)" for nil.
oo::str::FormatArg TextArg(const std::optional<std::string> &text)
{
	return text.has_value() ? oo::str::FormatArg(*text) : oo::str::FormatArg::null();
}


// -indexOfObject: on the goods list: NSNotFound when absent, or for nil.
NSUInteger IndexOfGood(const std::vector<std::string> &goods, const std::optional<std::string> &good)
{
	if (!good.has_value())  return NSNotFound;
	const auto found = std::find(goods.begin(), goods.end(), *good);
	return (found != goods.end()) ? static_cast<NSUInteger>(found - goods.begin()) : NSNotFound;
}


// The market sorters, as orderings (< 0, 0, > 0 for OOOrderedAscending, Same, Descending) over
// commodity keys; used with std::stable_sort, as -sortedArrayUsingFunction:context: is a stable
// sort in GNUstep (probed on gnustep-base: ties keep their order). They read the market's C++ part
// (slice 23, bead oo-wt5jv); a null market answers as a nil one did (no name, 0).
int marketSorterByName(const std::string &a, const std::string &b, OOCommodityMarket *market)
{
	// (-compare: on a nil name: goods always have names)
	const std::optional<std::string> nameA = (market != nullptr) ? market->nameForGood(a) : std::nullopt;
	const std::optional<std::string> nameB = (market != nullptr) ? market->nameForGood(b) : std::nullopt;
	return oo::str::compare(nameA.value_or(std::string()), nameB.value_or(std::string()));
}


int marketSorterByPrice(const std::string &a, const std::string &b, OOCommodityMarket *market)
{
	int result = (market != nullptr) ? (int)market->priceForGood(a) - (int)market->priceForGood(b) : 0;
	return (result < 0) ? -1 : ((result > 0) ? 1 : 0);
}


int marketSorterByQuantity(const std::string &a, const std::string &b, OOCommodityMarket *market)
{
	int result = (market != nullptr) ? (int)market->quantityForGood(a) - (int)market->quantityForGood(b) : 0;
	return (result < 0) ? -1 : ((result > 0) ? 1 : 0);
}


int marketSorterByMassUnit(const std::string &a, const std::string &b, OOCommodityMarket *market)
{
	int result = (market != nullptr) ? (int)market->massUnitForGood(a) - (int)market->massUnitForGood(b) : 0;
	return (result < 0) ? -1 : ((result > 0) ? 1 : 0);
}


// A custom_views value as the list of views (oo_arrayForKey: nil unless an array -> empty).
std::vector<oo::PList> CustomViewsFrom(const oo::PList &value)
{
	const oo::PList::Array *views = value.getIf<oo::PList::Array>();
	return (views != nullptr) ? *views : std::vector<oo::PList>();
}


// The docked station's interface for <key>, or nil (objectForKey: on a nil dictionary or key). Reads
// the station's C++ part (slice 21, bead oo-a602n); a null station has none.
OOJSInterfaceDefinition *InterfaceForKey(StationEntity *station, const std::optional<std::string> &key)
{
	if (station == nullptr || !key.has_value())  return nullptr;
	const auto it = station->localInterfaces.find(*key);
	return (it != station->localInterfaces.end()) ? it->second.get() : nullptr;
}


// A roleWeightFlags count (-oo_intForKey: with default 0).
int RoleFlagCount(const oo::PList::Dict &flags, const std::string &role)
{
	const auto it = flags.find(role);
	return (it != flags.end()) ? oo::PListGet<int>::from(&it->second, 0) : 0;
}


// The recently visited systems as saved: an array of signed integers (+numberWithInt:).
oo::PList SystemListPList(const std::vector<OOSystemID> &systems)
{
	oo::PList::Array result;
	result.reserve(systems.size());
	for (OOSystemID system : systems)  result.push_back(oo::PList::signedInteger(system));
	return oo::PList(std::move(result));
}


// A two-column GUI row as -arrayWithObjects:first, second, nil built it: it ends at the first nil.
std::vector<std::string> RowOf(const std::optional<std::string> &first, const std::optional<std::string> &second)
{
	std::vector<std::string> row;
	if (first.has_value())
	{
		row.push_back(*first);
		if (second.has_value())  row.push_back(*second);
	}
	return row;
}


// An equipment-list row: [text, availability, colour], ending at the first nil as arrayWithObjects: did.
oo::PList EquipmentRow(const std::optional<std::string> &text, bool available, OOColor *color)
{
	oo::PList::Array row;
	if (text.has_value())
	{
		row.push_back(oo::PList(*text));
		row.push_back(oo::PList(available));	// +numberWithBool:
		if (color != nullptr)  row.push_back(OOColorObjectNode(color));
	}
	return oo::PList(std::move(row));
}


// "More:<n>[:<key>]" row keys: field <index>, or nullopt past the end.
std::optional<std::string> RowKeyField(const std::string &key, size_t index)
{
	const std::vector<std::string> fields = oo::str::split(key, ":");
	if (index < fields.size())  return fields[index];
	return std::nullopt;
}

}	// namespace


static float const 		kDeadResetTime				= 30.0f;

static GLfloat		sBaseMass = 0.0;



namespace {

// An equipment key as -hasEquipmentItem: takes it: a null PList for nullopt (was nil).
oo::PList OptionalKeyPList(const std::optional<std::string> &key)
{
	return key.has_value() ? oo::PList(*key) : oo::PList();
}


// Info-gnustep.plist string (CFBundleVersion / CFBundleName as the Override category used to expose).
std::optional<std::string> OoliteInfoString(std::string_view key)
{
	const oo::fs::Path plistPath = oo::ResourcePaths::current().builtInResourcesDirectory() / "Info-gnustep.plist";
	oo::PList info;
	if (const oo::fs::Result<oo::Data> bytes = oo::fs::readFile(plistPath); bytes && !bytes->empty())
	{
		if (oo::Expected<oo::PList, oo::PListError> parsed = oo::parsePropertyList(bytes->stringView());
		    parsed && parsed->isDict())
			info = std::move(*parsed);
	}
	if (const oo::PList *v = info.find(key); v != nullptr && v->isString())
		return *v->getIf<std::string>();
	return std::nullopt;
}

}  // namespace


	


#ifndef NDEBUG
#define STAGE_TRACKING_BEGIN	{ \
									const char * volatile updateStage = "initialisation"; \
									try {
#define STAGE_TRACKING_END			} \
									catch (...) \
									{ \
										const auto exception = oo::CurrentOOException(); \
										if (!exception)  throw;	/* not an OOException: it goes on up, as before */ \
										OO_LOG(cxx_kOOLogException, "***** Exception during [{}] in {} : {} : {} *****", static_cast<const char *>(updateStage), static_cast<const char *>(__PRETTY_FUNCTION__), exception->name(), exception->reason()); \
										throw; \
									} \
								}
#define UPDATE_STAGE(x) do { updateStage = (x); } while (0)
#else
#define STAGE_TRACKING_BEGIN	{
#define STAGE_TRACKING_END		}
#define UPDATE_STAGE(x) do { (void) (x); } while (0);
#endif


#define VELOCITY_CLEANUP_MIN	2000.0f	// Minimum speed for "power braking".
#define VELOCITY_CLEANUP_FULL	5000.0f	// Speed at which full "power braking" factor is used.
#define VELOCITY_CLEANUP_RATE	0.001f	// Factor for full "power braking".





/////////////////////////////////////////////////////////////////////



///////////////////////////////////

namespace
{

// -prepareMarkedDestination:: appended the marker to the list for its "system" (the old
// +numberWithInt: key), creating the list on first use.
void PrepareMarkedDestination(std::map<int, std::vector<oo::PList>> &markers, oo::PList marker)
{
	const int system = marker.get<int>("system");
	markers[system].push_back(std::move(marker));
}

}	// namespace


	
namespace
{

std::string SliderString(NSInteger amountIn20ths)
{
	std::string filledSlider = std::string("|||||||||||||||||||||||||").substr(0, static_cast<std::size_t>(amountIn20ths));
	std::string emptySlider =  std::string(".........................").substr(0, static_cast<std::size_t>(20 - amountIn20ths));
	return filledSlider + emptySlider;
}

}	// namespace


namespace
{

std::optional<std::string> last_outfitting_key;	// nullopt = none (was nil)

}	// namespace


	





PlayerEntity		*gOOPlayer = nullptr;


/*	The player's life (ADR-0056 amendment oo-9ht.177): +sharedPlayer, -init, -deferredInit and the
	first part of -dealloc, which were the facade's (PlayerEntity+ObjCBridge.mm, deleted by bead
	oo-9ht.177). The player's Objective-C object is a ship's (OOEntityWithDrawable's facade since bead
	oo-9ht.144).

	Nasty initialization mechanism:
	PlayerEntity is made on demand by sharedPlayer(). This
	initialization doesn't actually set anything up -- apart from the
	assertion, it's like doing a bare alloc. deferredInit() does the work
	that -init "should" be doing. It assumes that -[ShipEntity cxx_initWithKey:
	definition:] will not return an object other than self.
	This is necessary because we need a pointer to the PlayerEntity early in
	startup, when ship data hasn't been loaded yet. In particular, we need
	a pointer to the player to set up the JavaScript environment, we need the
	JavaScript environment to set up OpenGL, and we need OpenGL set up to load
	ships.
*/
PlayerEntity::PlayerEntity() = default;
PlayerEntity::~PlayerEntity() = default;


PlayerEntity *PlayerEntity::sharedPlayer()
{
	if (EXPECT_NOT(gOOPlayer == nullptr))
	{
		// kept for the process, as +alloc's object was
		gOOPlayer = static_cast<PlayerEntity *>(newPlayerObject());
	}
	return gOOPlayer;
}


::ShipEntity *PlayerEntity::newPlayerObject()
{
	// -init: the ship's part only ([super initBypassForPlayer]), under the facade oo::NewEntityFacade
	// picks (the drawable's since bead oo-9ht.144); the player, its object retained (+1).
	OOCAssert(gOOPlayer == nullptr, "Expected only one PlayerEntity to exist at a time.");
	oo::Ref<PlayerEntity> player = oo::makeRef<PlayerEntity>();
	{
		oo::AutoreleaseScope pool;	// was @autoreleasepool (oo-31u.8)
		return oo::ToShip(oo::RetainEntity(oo::MadeEntity(player)));
	}
}


void PlayerEntity::deferredInit()
{
	OOCAssert(gOOPlayer == this, "Expected only one PlayerEntity to exist at a time.");
	// -[ShipEntity cxx_initWithKey:definition:] sent again: since bead oo-9ht.144 the root's -initWithCxxEntity:
	// (what the ship's -initShipPart sent an initialised ship), then the ship's set-up.
	OOCAssert(oo::EntityInitAgain(this) == this && initShipSetUp(std::string(PLAYER_SHIP_DESC), oo::PList(oo::PList::Dict{})), "PlayerEntity requires -[ShipEntity cxx_initWithKey:definition:] to return unmodified self.");

	maxFieldOfView = MAX_FOV;
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
	fov_delta = 2.0; // multiply by 2 each second
#endif

	compassMode = COMPASS_MODE_BASIC;

	afterburnerSoundLooping = NO;

	isPlayer = YES;

	setStatus(STATUS_START_GAME);

	int i;
	for (i = 0; i < PLAYER_MAX_MISSILES; i++)
	{
		missile_entity[i] = nullptr;
	}
	setUpAndConfirmOK(NO);

	save_path.reset();

	scoopsActive = NO;

	target_memory_index = 0;

	dockingReport.clear();
	if (hud != nullptr)  hud->resetGuis(oo::PList(oo::PList::Dict{ { "message_gui", oo::PList(oo::PList::Dict()) }, { "comm_log_gui", oo::PList(oo::PList::Dict()) } }));

	initControls();
}


// The player's part of -dealloc, which ran before the ship's: -[ShipEntity dealloc] calls it first.
void PlayerEntity::willDealloc()
{
	compassTarget = nullptr;
	hud = nullptr;

	worldScripts.clear();
	worldScriptsRequiringTickle.reset();
	commodityScripts.clear();
	mission_variables = oo::PList();

	localVariables.clear();

	shipCommodityData = nullptr;

	save_path.reset();
	scenarioKey.reset();

	destroySound();

	wormholeObject = nullptr;	// the wormhole's Objective-C object (beads oo-9ht.112, oo-5q11i)
	wormhole = nullptr;

	int i;
	for (i = 0; i < PLAYER_MAX_MISSILES; i++)  missile_entity[i] = nullptr;
	for (i = 0; i < PLAYER_MAX_TRUMBLES; i++)  trumble[i] = oo::Ref<OOTrumble>();
}


/*	Members named for an ivar the player keeps (alertCondition, legalStatus, suppressTargetLost):
	the facade answered these selectors with the getters, so the ship's virtual members do too.
*/
OOAlertCondition PlayerEntity::alertCondition()	{ return getAlertCondition(); }
int PlayerEntity::legalStatus()	{ return getLegalStatus(); }
void PlayerEntity::suppressTargetLost()	{ getSuppressTargetLost(); }

// The player's JS class name, which its facade's category PlayerEntity (OOJavaScriptExtensions) answered.
std::optional<std::string> PlayerEntity::jsClassName()	{ return OOJSPlayerShipJSClassName(); }


// Slice 2 of docs/phases/3-slices/PlayerEntity.md (bead oo-m4tfc): cargo pods, commodity data and credits, galaxy and chart coordinates, the current and previous system.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

void PlayerEntity::setName(const std::optional<std::string> &/*inName*/)
{
	// Block super method; player ship can't be renamed (-setName: forwards here).
}


GLfloat PlayerEntity::baseMass()
{
	if (sBaseMass <= 0.0)
	{
		// First call with initialised mass (in [UNIVERSE setUpInitialUniverse]) is always to the cobra 3, even when starting with a savegame.
		if (getMass() > 0.0)	// bootstrap the base mass.
		{
			OO_LOG("fuelPrices", "Setting Cobra3 base mass to: {:.2f} ", getMass());
			sBaseMass = getMass();
		}
		else 
		{
			// This happened on startup when [UNIVERSE setUpSpace] was called before player init, inside [UNIVERSE setUpInitialUniverse].
			OO_LOG("fuelPrices", "{}", "Player ship not initialised properly yet, using precalculated base mass.");
			return 185580.0;
		}
	}

	return sBaseMass;
}


void PlayerEntity::unloadAllCargoPodsForType(const std::string &type, ::OOCommodityMarket *manifest)
{
	NSInteger i, cargoCount = cargo.size();
	if (cargoCount == 0)  return;
	
	// step through the cargo pods adding in the quantities	
	for (i =  cargoCount - 1; i >= 0 ; i--)
	{
		::ShipEntity *cargoItem = oo::ToShip(cargo[i].get());
		const std::optional<std::string> commodityType = (cargoItem != nullptr ? cargoItem->commodityType() : std::optional<std::string>());
		if (!commodityType.has_value() || *commodityType == type)
		{
			if (commodityType.has_value())
			{
				// transfer
				manifest->addQuantity((cargoItem != nullptr ? cargoItem->commodityAmount() : 0), type);
			}
			else	// undefined
			{
				OO_LOG("player.badCargoPod", "Cargo pod {} has bad commodity type, rejecting.", oo::EntityDescription(cargoItem));
				continue;
			}
			cargo.erase(cargo.begin() + i);
		}
	}
}


void PlayerEntity::unloadCargoPodsForType(const std::string &type, OOCargoQuantity quantity)
{
	NSInteger			i, n_cargo = cargo.size();
	if (n_cargo == 0)  return;
	
	::ShipEntity			*cargoItem = nil;
	std::optional<std::string>	co_type;
	OOCargoQuantity		amount;
	OOCargoQuantity		cargoToGo = quantity;

	// step through the cargo pods removing pods or quantities	
	for (i =  n_cargo - 1; (i >= 0 && cargoToGo > 0) ; i--)
	{
		cargoItem = oo::ToShip(cargo[i].get());
		co_type = (cargoItem != nullptr ? cargoItem->commodityType() : std::optional<std::string>());
		if (!co_type.has_value() || *co_type == type)
		{
			if (co_type.has_value())
			{
				amount =  (cargoItem != nullptr ? cargoItem->commodityAmount() : 0);
				if (amount <= cargoToGo)
				{
					cargo.erase(cargo.begin() + i);
					cargoToGo -= amount;
				}
				else
				{
					// we only need to remove a part of the cargo to meet our target
					if (cargoItem != nullptr)  cargoItem->setCommodity(*co_type, (amount - cargoToGo));
					cargoToGo = 0;
					
				}
			}
			else	// undefined
			{
				OO_LOG("player.badCargoPod", "Cargo pod {} has bad commodity type (COMMODITY_UNDEFINED), rejecting.", oo::EntityDescription(cargoItem));
				continue;
			}
		}
	}
	
	// now check if we are ready. When not, proceed with quantities in the manifest.
	if (cargoToGo > 0)
	{
		if (shipCommodityData != nullptr)  shipCommodityData->removeQuantity(cargoToGo, type);
	}
}


void PlayerEntity::unloadCargoPods()
{
	OOCAssert(isDocked(), "Cannot unload cargo pods unless docked.");
	
	/* loads commodities from the cargo pods onto the ship's manifest */
	for (const std::string &good : (shipCommodityData != nullptr ? shipCommodityData->goods() : std::vector<std::string>()))
	{
		unloadAllCargoPodsForType(good, shipCommodityData.get());
	}
#ifndef NDEBUG
	if (cargo.size() > 0)
	{
		OO_LOG("player.unloadCargo", "Cargo remains in pods after unloading - {}", oo::DescriptionOf(oo::EntityNodesFrom(cargo)));
	}
#endif

	calculateCurrentCargo();	// work out the correct value for current_cargo
}


// TODO: better feedback on the log as to why failing to create player cargo pods causes a CTD?
void PlayerEntity::createCargoPodWithType(const std::string &type, OOCargoQuantity amount)
{
	::ShipEntity *container = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole("1t-cargopod") : (::ShipEntity *)nil);
	if (container)
	{
		if (container != nullptr)  container->setScanClass(CLASS_CARGO);
		if (container != nullptr)  container->setStatus(STATUS_IN_HOLD);
		if (container != nullptr)  container->setCommodity(type, amount);
		cargo.emplace_back(container);
		if (container != nullptr)  oo::ReleaseEntity(container);
	}
	else
	{
		OO_LOG_ERR("player.loadCargoPods.noContainer", "{}", "couldn't create a container in [PlayerEntity loadCargoPods]");
		// throw an exception here...
		OORaiseException(OOLITE_EXCEPTION_FATAL, "[PlayerEntity loadCargoPods] failed to create a container for cargo with role 'cargopod'");
	}
}


void PlayerEntity::loadCargoPodsForType(const std::string &type, ::OOCommodityMarket *manifest)
{
	// load commodities from the ships manifest into individual cargo pods
	unsigned j;
	
	OOCargoQuantity	quantity = manifest->quantityForGood(type);
	OOMassUnit		units =	manifest->massUnitForGood(type);
	
	if (quantity > 0)
	{
		if (units == UNITS_TONS)
		{
			// easy case
			for (j = 0; j < quantity; j++)
			{
				createCargoPodWithType(type, 1);		// or CTD if unsuccesful (!)
			}
			manifest->setQuantity(0, type);
		}
		else
		{
			OOCargoQuantity podsRequiredForQuantity, amountToLoadInCargopod, tmpQuantity;
			// reserve up to 1/2 ton of each commodity for the safe
			if (units == UNITS_KILOGRAMS) 
			{
				if (quantity <= MAX_KILOGRAMS_IN_SAFE)
				{
					tmpQuantity = quantity;
					 quantity = 0;
				}
				else
				{
					tmpQuantity = MAX_KILOGRAMS_IN_SAFE;
					quantity -= tmpQuantity;
				}
				amountToLoadInCargopod = KILOGRAMS_PER_POD;
			}
			else
			{
				if (quantity <= MAX_GRAMS_IN_SAFE) {
					tmpQuantity = quantity;
					quantity = 0;
				}
				else
				{
					tmpQuantity = MAX_GRAMS_IN_SAFE;
					quantity -= tmpQuantity;
				}
				amountToLoadInCargopod = GRAMS_PER_POD;
			}
			if (quantity > 0)
			{
				podsRequiredForQuantity = 1 + (quantity/amountToLoadInCargopod);
				// this check is needed so that initial quantities like 1499kg or 1499999g
				// do not result in generation of an empty cargopod
				if (quantity % amountToLoadInCargopod == 0)  podsRequiredForQuantity--;
				
				// put each ton or part-ton beyond that in a separate container
				for (j = 0; j < podsRequiredForQuantity; j++)
				{
					if (amountToLoadInCargopod > quantity)
					{
						// last pod gets the dregs. :)
						amountToLoadInCargopod = quantity;
					}
					createCargoPodWithType(type, amountToLoadInCargopod);	// or CTD if unsuccesful (!)
					quantity -= amountToLoadInCargopod;
				}
				// adjust manifest for this commodity
				manifest->setQuantity(tmpQuantity, type);
			}
		}
	}
}


void PlayerEntity::loadCargoPodsForType(const std::string &type, OOCargoQuantity quantity)
{
	OOMassUnit unit = (shipCommodityData != nullptr ? shipCommodityData->massUnitForGood(type) : UNITS_TONS);
	
	while (quantity)
	{
		if (unit != UNITS_TONS)
		{
			int amount_per_container = (unit == UNITS_KILOGRAMS)? KILOGRAMS_PER_POD : GRAMS_PER_POD;
			while (quantity > 0)
			{
				int smaller_quantity = 1 + ((quantity - 1) % amount_per_container);
				if (cargo.size() < maxAvailableCargoSpace())
				{
					::ShipEntity* container = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole("1t-cargopod") : (::ShipEntity *)nil);
					if (container)
					{
						// the cargopod ship is just being set up. If ejected,  will call UNIVERSE addEntity
						if (container != nullptr)  container->setStatus(STATUS_IN_HOLD);
						if (container != nullptr)  container->setScanClass(CLASS_CARGO);
						if (container != nullptr)  container->setCommodity(type, smaller_quantity);
						cargo.emplace_back(container);
						if (container != nullptr)  oo::ReleaseEntity(container);
					}
				}
				else
				{
					// try to squeeze any surplus, up to half a ton, in the manifest.
					int amount = (shipCommodityData != nullptr ? shipCommodityData->quantityForGood(type) : 0) + smaller_quantity;
					if (amount > MAX_GRAMS_IN_SAFE && unit == UNITS_GRAMS) amount = MAX_GRAMS_IN_SAFE;
					else if (amount > MAX_KILOGRAMS_IN_SAFE && unit == UNITS_KILOGRAMS) amount = MAX_KILOGRAMS_IN_SAFE;

					if (shipCommodityData != nullptr)  shipCommodityData->setQuantity(amount, type);
				}
				quantity -= smaller_quantity;
			}
		}
		else
		{
			// put each ton in a separate container
			while (quantity)
			{
				if (cargo.size() < maxAvailableCargoSpace())
				{
					::ShipEntity* container = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole("1t-cargopod") : (::ShipEntity *)nil);
					if (container)
					{
						// the cargopod ship is just being set up. If ejected, will call UNIVERSE addEntity
						if (container != nullptr)  container->setScanClass(CLASS_CARGO);
						if (container != nullptr)  container->setStatus(STATUS_IN_HOLD);
						if (container != nullptr)  container->setCommodity(type, 1);
						cargo.emplace_back(container);
						if (container != nullptr)  oo::ReleaseEntity(container);
					}
				}
				quantity--;
			}
		}
	}
}


void PlayerEntity::loadCargoPods()
{
	/* loads commodities from the ships manifest into individual cargo pods */
	for (const std::string &good : (shipCommodityData != nullptr ? shipCommodityData->goods() : std::vector<std::string>()))
	{
		loadCargoPodsForType(good, shipCommodityData.get());
	}
	calculateCurrentCargo();	// work out the correct value for current_cargo
	cargo_dump_time = 0;
}


::OOCommodityMarket *PlayerEntity::getShipCommodityData()
{
	return shipCommodityData.get();
}


OOCreditsQuantity PlayerEntity::deciCredits()
{
	return credits;
}


int PlayerEntity::random_factor()
{
	return market_rnd;
}


void PlayerEntity::setRandom_factor(int rf)
{
	market_rnd = rf;
}


OOGalaxyID PlayerEntity::galaxyNumber()
{
	return galaxy_number;
}


NSPoint PlayerEntity::getGalaxy_coordinates()
{
	return galaxy_coordinates;
}


void PlayerEntity::setGalaxyCoordinates(NSPoint newPosition)
{
	galaxy_coordinates.x = newPosition.x;
	galaxy_coordinates.y = newPosition.y;
}


NSPoint PlayerEntity::getCursor_coordinates()
{
	return cursor_coordinates;
}


NSPoint PlayerEntity::getChart_centre_coordinates()
{
	return chart_centre_coordinates;
}


OOScalar PlayerEntity::getChart_zoom()
{
	if(_missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_SHORT ||
		_missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_SHORT_ANA_QUICKEST ||
		_missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_SHORT_ANA_SHORTEST)
	{
		return 1.0;
	}
	else if(_missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG ||
			_missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_SHORTEST ||
			_missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_QUICKEST)
	{
		return CHART_MAX_ZOOM;
	}
	else if(_missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_CUSTOM ||
			_missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_QUICKEST ||
			_missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_SHORTEST)
	{
		return custom_chart_zoom;
	}
	return chart_zoom;
}


OOScalar PlayerEntity::getCustom_chart_zoom()
{
	return custom_chart_zoom;
}


void PlayerEntity::setCustomChartZoom(OOScalar zoom)
{
	custom_chart_zoom = zoom;
}


NSPoint PlayerEntity::getCustom_chart_centre_coordinates()
{
	return custom_chart_centre_coordinates;
}


void PlayerEntity::setCustomChartCentre(NSPoint coords)
{
	custom_chart_centre_coordinates.x = coords.x;
	custom_chart_centre_coordinates.y = coords.y;
}


NSPoint PlayerEntity::adjusted_chart_centre()
{
	NSPoint acc;		// adjusted chart centre
	double scroll_pos;	// cursor coordinate at which we'd want to scoll chart in the direction we're currently considering
	double ecc;		// chart centre coordinate we'd want if the cursor was on the edge of the galaxy in the current direction

	if(_missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_SHORT ||
		_missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_SHORT_ANA_QUICKEST || 
		_missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_SHORT_ANA_SHORTEST)
	{
		return galaxy_coordinates;
	}
	else if(_missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG ||
			_missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_QUICKEST ||
			_missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_SHORTEST)
	{
		return NSMakePoint(128.0, 128.0);
	}
	else if (_missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_CUSTOM ||
			_missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_QUICKEST ||
			_missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_SHORTEST)
	{
		return custom_chart_centre_coordinates;
	}
	// When fully zoomed in we want to centre chart on chart_centre_coordinates.  When zoomed out we want the chart centred on
	// (128.0, 128.0) so the galaxy fits the screen width.  For intermediate zoom we interpolate.
	acc.x = chart_centre_coordinates.x + (128.0 - chart_centre_coordinates.x) * (chart_zoom - 1.0) / (CHART_MAX_ZOOM - 1.0);
	acc.y = chart_centre_coordinates.y + (128.0 - chart_centre_coordinates.y) * (chart_zoom - 1.0) / (CHART_MAX_ZOOM - 1.0);

	// If the cursor is out of the centre non-scrolling part of the screen adjust the chart centre.  If the cursor is just at scroll_pos
	// we want to return the chart centre as it is, but if it's at the edge of the galaxy we want the centre positioned so the cursor is
	// at the edge of the screen
	if (chart_focus_coordinates.x - acc.x <= -CHART_SCROLL_AT_X*chart_zoom)
	{
		scroll_pos = acc.x - CHART_SCROLL_AT_X*chart_zoom;
		ecc = CHART_WIDTH_AT_MAX_ZOOM*chart_zoom / 2.0;
		if (scroll_pos <= 0)
		{
			acc.x = ecc;
		}
		else
		{
			acc.x = ((scroll_pos-chart_focus_coordinates.x)*ecc + chart_focus_coordinates.x*acc.x)/scroll_pos;
		}
	}
	else if (chart_focus_coordinates.x - acc.x >= CHART_SCROLL_AT_X*chart_zoom)
	{
		scroll_pos = acc.x + CHART_SCROLL_AT_X*chart_zoom;
		ecc = 256.0 - CHART_WIDTH_AT_MAX_ZOOM*chart_zoom / 2.0;
		if (scroll_pos >= 256.0)
		{
			acc.x = ecc;
		}
		else
		{
			acc.x = ((chart_focus_coordinates.x-scroll_pos)*ecc + (256.0 - chart_focus_coordinates.x)*acc.x)/(256.0 - scroll_pos);
		}
	}
	if (chart_focus_coordinates.y - acc.y <= -CHART_SCROLL_AT_Y*chart_zoom)
	{
		scroll_pos = acc.y - CHART_SCROLL_AT_Y*chart_zoom;
		ecc = CHART_HEIGHT_AT_MAX_ZOOM*chart_zoom / 2.0;
		if (scroll_pos <= 0)
		{
			acc.y = ecc;
		}
		else
		{
			acc.y = ((scroll_pos-chart_focus_coordinates.y)*ecc + chart_focus_coordinates.y*acc.y)/scroll_pos;
		}
	}
	else if (chart_focus_coordinates.y - acc.y >= CHART_SCROLL_AT_Y*chart_zoom)
	{
		scroll_pos = acc.y + CHART_SCROLL_AT_Y*chart_zoom;
		ecc = 256.0 - CHART_HEIGHT_AT_MAX_ZOOM*chart_zoom / 2.0;
		if (scroll_pos >= 256.0)
		{
			acc.y = ecc;
		}
		else
		{
			acc.y = ((chart_focus_coordinates.y-scroll_pos)*ecc + (256.0 - chart_focus_coordinates.y)*acc.y)/(256.0 - scroll_pos);
		}
	}
	return acc;
}


OORouteType PlayerEntity::ANAMode()
{
	return ANA_mode;
}


OOSystemID PlayerEntity::systemID()
{
	return system_id;
}


void PlayerEntity::setSystemID(OOSystemID sid)
{
	system_id = sid;
	galaxy_coordinates = PointFromCoordinates(((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getProperty("coordinates", sid, galaxy_number) : oo::PList()));
	chart_centre_coordinates = galaxy_coordinates;
	target_chart_centre = chart_centre_coordinates;
}


OOSystemID PlayerEntity::previousSystemID()
{
	return previous_system_id;
}


void PlayerEntity::setPreviousSystemID(OOSystemID sid)
{
	previous_system_id = sid;
}



// Slice 3 of docs/phases/3-slices/PlayerEntity.md (bead oo-7pa3t): target, next-hop and info systems, the wormhole, the commander data dictionary (save).
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

OOSystemID PlayerEntity::targetSystemID()
{
	return target_system_id;
}


void PlayerEntity::setTargetSystemID(OOSystemID sid)
{
	target_system_id = sid;
	cursor_coordinates = PointFromCoordinates(((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getProperty("coordinates", (UNIVERSE != nullptr ? UNIVERSE->keyForPlanetOverridesForSystem(sid, galaxy_number) : std::optional<std::string>()).value_or(std::string())) : oo::PList()));
}


// just return target system id if no valid next hop
OOSystemID PlayerEntity::nextHopTargetSystemID()
{
	// not available if no ANA
	if (!hasEquipmentItemProviding("EQ_ADVANCED_NAVIGATIONAL_ARRAY"))
	{
		return target_system_id;
	}
	// not available if ANA is turned off
	if (ANA_mode == OPTIMIZED_BY_NONE)
	{
		return target_system_id;
	}
	// easy case
	if (system_id == target_system_id)
	{
		return system_id; // no need to calculate
	}
	const oo::PList routeInfo = (UNIVERSE != nullptr ? UNIVERSE->routeFromSystem(system_id, target_system_id, ANA_mode) : oo::PList());
	// no route to destination
	if (routeInfo.isNull())
	{
		return target_system_id;
	}
	const oo::PList *route = routeInfo.get<oo::PList::Array>("route");
	return (route != nullptr) ? route->at<int>(1) : 0;
}


OOSystemID PlayerEntity::infoSystemID()
{
	return info_system_id;
}


void PlayerEntity::setInfoSystemID(OOSystemID sid, bool moveChart)
{
	if (sid != info_system_id)
	{
		OOSystemID old = info_system_id;
		info_system_id = sid;
		ooscript::Context context = OOJSAcquireContext();
		ShipScriptEvent(context, this, "infoSystemWillChange", ooscript::int32Value(info_system_id), ooscript::int32Value(old));
		if (gui_screen == GUI_SCREEN_LONG_RANGE_CHART || gui_screen == GUI_SCREEN_SHORT_RANGE_CHART)
		{
			if(moveChart)
			{
				target_chart_focus = ((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getCoordinatesForSystem(info_system_id, galaxy_number) : NSMakePoint(0, 0));
			}
		}
		else
		{
			if(gui_screen == GUI_SCREEN_SYSTEM_DATA)
			{
				setGuiToSystemDataScreenRefreshBackground(YES);
			}
			if(moveChart)
			{
				chart_centre_coordinates = ((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getCoordinatesForSystem(info_system_id, galaxy_number) : NSMakePoint(0, 0));
				target_chart_centre = chart_centre_coordinates;
				chart_focus_coordinates = chart_centre_coordinates;
				target_chart_focus = chart_focus_coordinates;
			}
		}
		ShipScriptEvent(context, this, "infoSystemChanged", ooscript::int32Value(info_system_id), ooscript::int32Value(old));
		OOJSRelinquishContext(context);
	}
}


void PlayerEntity::nextInfoSystem()
{
	if (ANA_mode == OPTIMIZED_BY_NONE)
	{
		setInfoSystemID(target_system_id, YES);
		return;
	}
	const oo::PList routeInfo = (UNIVERSE != nullptr ? UNIVERSE->routeFromSystem(system_id, target_system_id, ANA_mode) : oo::PList());
	const oo::PList *route = routeInfo.get<oo::PList::Array>("route");
	NSUInteger i;
	if (route == nullptr)
	{
		setInfoSystemID(target_system_id, YES);
		return;
	}
	for (i = 0; i < route->count(); i++)
	{
		if (route->at<int>(i) == info_system_id)
		{
			if (i + 1 < route->count())
			{
				setInfoSystemID(route->at<unsigned int>(i + 1), YES);
				return;
			}
			break;
		}
	}
	setInfoSystemID(target_system_id, YES);
	return;
}


void PlayerEntity::previousInfoSystem()
{
	if (ANA_mode == OPTIMIZED_BY_NONE)
	{
		setInfoSystemID(system_id, YES);
		return;
	}
	const oo::PList routeInfo = (UNIVERSE != nullptr ? UNIVERSE->routeFromSystem(system_id, target_system_id, ANA_mode) : oo::PList());
	const oo::PList *route = routeInfo.get<oo::PList::Array>("route");
	NSUInteger i;
	if (route == nullptr)
	{
		setInfoSystemID(system_id, YES);
		return;
	}
	for (i = 0; i < route->count(); i++)
	{
		if (route->at<int>(i) == info_system_id)
		{
			if (i > 0)
			{
				setInfoSystemID(route->at<unsigned int>(i - 1), YES);
				return;
			}
			break;
		}
	}
	setInfoSystemID(system_id, YES);
	return;
}


void PlayerEntity::homeInfoSystem()
{
	setInfoSystemID(system_id, YES);
	return;
}


void PlayerEntity::targetInfoSystem()
{
	setInfoSystemID(target_system_id, YES);
	return;
}


bool PlayerEntity::infoSystemOnRoute()
{
	const oo::PList routeInfo = (UNIVERSE != nullptr ? UNIVERSE->routeFromSystem(system_id, target_system_id, ANA_mode) : oo::PList());
	const oo::PList *route = routeInfo.get<oo::PList::Array>("route");
	NSUInteger i;
	if (route == nullptr)
	{
		return NO;
	}
	for (i = 0; i < route->count(); i++)
	{
		if (route->at<int>(i) == info_system_id)
		{
			return YES;
		}
	}
	return NO;
}


::WormholeEntity *PlayerEntity::getWormhole()
{
	return wormhole;
}


void PlayerEntity::setWormhole(::WormholeEntity *newWormhole)
{
	// The wormhole is C++ since bead oo-9ht.112: its Objective-C object (the root's facade, which
	// owns it) is what is retained. oo::ToObjC answers it autoreleased: the pool drains that here,
	// so the object's retain count is its holders' alone afterwards, as before.
	{
		oo::AutoreleaseScope pool;	// was @autoreleasepool (oo-31u.8)
		wormholeObject = oo::EntityHold(newWormhole);	// null for null
		wormhole = newWormhole;
	}
}


oo::PList PlayerEntity::commanderDataDictionary()
{
	int i;

	// Built as the old mutable dictionary was; each number keeps its kind (proposed ADR-0043
	// items 11 and 15): +numberWithInt: / oo_setInteger: (+numberWithLong:) signed,
	// +numberWithUnsigned*: / oo_setUnsignedInteger: unsigned, +numberWithFloat: a single real,
	// +numberWithDouble: and oo_setFloat: (+numberWithDouble:) a double, +numberWithBool: a bool.
	// A nil value (which -setObject:forKey: refused) is left out.
	oo::PList::Dict result;

	if (const std::optional<std::string> version = OoliteInfoString("CFBundleVersion"))  result["written_by_version"] = oo::PList(*version);

	const std::string gal_id = std::to_string(galaxy_number);	// "%u"
	const std::string sys_id = std::to_string(system_id);	// "%d"
	const std::string tgt_id = std::to_string(target_system_id);
	const std::string prv_id = std::to_string(previous_system_id);

	// Variable requiredCargoSpace not suitable for Oolite as it currently stands: it retroactively changes a savegame cargo space.
	//unsigned 	passenger_space = [[OOEquipmentType equipmentTypeWithIdentifier:@"EQ_PASSENGER_BERTH"] requiredCargoSpace];
	//if (passenger_space == 0) passenger_space = PASSENGER_BERTH_SPACE;

	result["galaxy_id"] = oo::PList(gal_id);
	result["system_id"] = oo::PList(sys_id);
	result["target_id"] = oo::PList(tgt_id);
	result["previous_system_id"] = oo::PList(prv_id);
	result["chart_zoom"] = oo::PList::singleReal(saved_chart_zoom);
	result["chart_ana_mode"] = oo::PList::signedInteger((int)ANA_mode);
	result["chart_colour_mode"] = oo::PList::signedInteger((int)longRangeChartMode);


	if (found_system_id >= 0)
	{
		result["found_system_id"] = oo::PList(std::to_string(found_system_id));
	}

	// Write the name of the current system. Useful for looking up saved game information and for overlapping systems.
	if (!(UNIVERSE != nullptr ? UNIVERSE->inInterstellarSpace() : false))
	{
		if (const std::optional<std::string> systemName = (UNIVERSE != nullptr ? UNIVERSE->getSystemName(currentSystemID()) : std::optional<std::string>()))  result["current_system_name"] = oo::PList(*systemName);
		const oo::PList systemData = (UNIVERSE != nullptr ? UNIVERSE->currentSystemData() : oo::PList());
		OOGovernmentID government = systemData.get<int>(std::string(KEY_GOVERNMENT));
		OOTechLevelID techlevel = systemData.get<int>(std::string(KEY_TECHLEVEL));
		OOEconomyID economy = systemData.get<int>(std::string(KEY_ECONOMY));
		result["current_system_government"] = oo::PList::unsignedInteger((unsigned short)government);
		result["current_system_techlevel"] = oo::PList::unsignedInteger((NSUInteger)techlevel);
		result["current_system_economy"] = oo::PList::unsignedInteger((unsigned short)economy);
	}

	if (const std::optional<std::string> value = commanderName())  result["player_name"] = oo::PList(*value);
	if (const std::optional<std::string> value = lastsaveName())  result["player_save_name"] = oo::PList(*value);
	if (const std::optional<std::string> value = getShipUniqueName())  result["ship_unique_name"] = oo::PList(*value);
	if (const std::optional<std::string> value = getShipClassName())  result["ship_class_name"] = oo::PList(*value);

	/*
		BUG: GNUstep truncates integer values to 32 bits when loading XML plists.
		Workaround: store credits as a double. 53 bits of precision ought to
		be good enough for anybody. Besides, we display credits with double
		precision anyway.
		-- Ahruman 2011-02-15
	*/
	result["credits"] = oo::PList((double)credits);	// oo_setFloat: was +numberWithDouble:
	result["fuel"] = oo::PList::unsignedInteger((unsigned long)fuel);

	result["galaxy_number"] = oo::PList::signedInteger((long)galaxy_number);

	result["weapons_online"] = oo::PList((bool)weaponsOnline());

	if (forward_weapon_type != nil)
	{
		if (const std::optional<std::string> identifier = (forward_weapon_type != nullptr ? forward_weapon_type->identifier() : std::optional<std::string>()))  result["forward_weapon"] = oo::PList(*identifier);
	}
	if (aft_weapon_type != nil)
	{
		if (const std::optional<std::string> identifier = (aft_weapon_type != nullptr ? aft_weapon_type->identifier() : std::optional<std::string>()))  result["aft_weapon"] = oo::PList(*identifier);
	}
	if (port_weapon_type != nil)
	{
		if (const std::optional<std::string> identifier = (port_weapon_type != nullptr ? port_weapon_type->identifier() : std::optional<std::string>()))  result["port_weapon"] = oo::PList(*identifier);
	}
	if (starboard_weapon_type != nil)
	{
		if (const std::optional<std::string> identifier = (starboard_weapon_type != nullptr ? starboard_weapon_type->identifier() : std::optional<std::string>()))  result["starboard_weapon"] = oo::PList(*identifier);
	}
	if (const std::optional<std::string> subentities = serializeShipSubEntities())  result["subentities_status"] = oo::PList(*subentities);
	if (hud != nil && hud->nonlinearScanner())
	{
		result["ship_scanner_zoom"] = oo::PList((double)hud->scannerZoom());	// oo_setFloat:
	}

	result["max_cargo"] = oo::PList::signedInteger((long)(max_cargo + PASSENGER_BERTH_SPACE * max_passengers));

	result["shipCommodityData"] = (shipCommodityData != nullptr ? shipCommodityData->savePlayerAmounts() : oo::PList());


	oo::PList::Array missileRoles;
	missileRoles.reserve(max_missiles);

	for (i = 0; i < (int)max_missiles; i++)
	{
		if (missile_entity[i])
		{
			missileRoles.push_back(oo::PList((oo::ToShip(missile_entity[i].get()) != nullptr ? oo::ToShip(missile_entity[i].get())->getPrimaryRole() : std::optional<std::string>()).value_or(std::string())));
		}
		else
		{
			missileRoles.push_back(oo::PList("NONE"));
		}
	}
	result["missile_roles"] = oo::PList(std::move(missileRoles));

	result["missiles"] = oo::PList::signedInteger((long)missiles);

	result["legal_status"] = oo::PList::signedInteger((long)legalStatusValue);
	result["market_rnd"] = oo::PList::signedInteger((long)market_rnd);
	result["ship_kills"] = oo::PList::signedInteger((long)ship_kills);

	// ship depreciation
	result["ship_trade_in_factor"] = oo::PList::signedInteger((long)ship_trade_in_factor);

	// mission variables
	if (!mission_variables.isNull())
	{
		result["mission_variables"] = mission_variables;
	}

	// communications log
	const std::vector<std::string> *log = getCommLog();
	if (log != nullptr)  result["comm_log"] = oo::PList(oo::PList::Array(log->begin(), log->end()));

	result["entity_personality"] = oo::PList::unsignedInteger((unsigned long)entity_personality);

	// extra equipment flags
	oo::PList::Dict equipment;
	for (const std::string &eqDesc : equipmentKeys())
	{
		equipment[eqDesc] = oo::PList::signedInteger((long)countEquipmentItem(eqDesc));
	}
	if (!equipment.empty())
	{
		result["extra_equipment"] = oo::PList(equipment);
	}
	if (primedEquipment < eqScripts.size()) result["primed_equipment"] = oo::PList(eqScripts[primedEquipment].first);

	if (const std::optional<std::string> value = fastEquipmentA())  result["primed_equipment_a"] = oo::PList(*value);
	if (const std::optional<std::string> value = fastEquipmentB())  result["primed_equipment_b"] = oo::PList(*value);

	// roles
	result["role_weights"] = oo::PList(oo::PList::Array(roleWeights.begin(), roleWeights.end()));

	// role information
	result["role_weight_flags"] = oo::PList(roleWeightFlags);

	// role information
	result["role_system_memory"] = SystemListPList(roleSystemList);

	// reputation
	// initialise parcel reputations in dictionary if not set (the saved dictionary was the live one,
	// so it is built after this backfill)
	const auto reputationValue = [&](const std::string &key) {
		const auto it = reputation.find(key);
		return it != reputation.end() ? oo::PListGet<int>::from(&it->second, 0) : 0;	// -oo_intForKey:
	};
	int pGood = reputationValue(std::string(PARCEL_GOOD_KEY));
	int pBad = reputationValue(std::string(PARCEL_BAD_KEY));
	int pUnknown = reputationValue(std::string(PARCEL_UNKNOWN_KEY));
	if (pGood+pBad+pUnknown != MAX_CONTRACT_REP)
	{
		reputation[std::string(PARCEL_GOOD_KEY)] = oo::PList::signedInteger(0);
		reputation[std::string(PARCEL_BAD_KEY)] = oo::PList::signedInteger(0);
		reputation[std::string(PARCEL_UNKNOWN_KEY)] = oo::PList::signedInteger(MAX_CONTRACT_REP);
	}
	result["reputation"] = oo::PList(reputation);

	// passengers
	result["max_passengers"] = oo::PList::signedInteger((long)max_passengers);
	result["passengers"] = oo::PList(passengers);
	result["passenger_record"] = oo::PList(passenger_record);

	// parcels
	result["parcels"] = oo::PList(parcels);
	result["parcel_record"] = oo::PList(parcel_record);

	//specialCargo
	if (specialCargo)  result["special_cargo"] = oo::PList(*specialCargo);

	// contracts
	result["contracts"] = oo::PList(contracts);
	result["contract_record"] = oo::PList(contract_record);

	result["mission_destinations"] = oo::PList(missionDestinations);

	//shipyard
	result["shipyard_record"] = oo::PList(shipyard_record);

	//ship's clock
	result["ship_clock"] = oo::PList((double)ship_clock);

	//speech
	result["speech_on"] = oo::PList::signedInteger((int)isSpeechOn);
#if OOLITE_ESPEAK
	if (const std::optional<std::string> voice = (UNIVERSE != nullptr ? UNIVERSE->voiceName(voice_no) : std::optional<std::string>()))  result["speech_voice"] = oo::PList(*voice);
	result["speech_gender"] = oo::PList((bool)voice_gender_m);
#endif

	// docking clearance
	result["docking_clearance_protocol"] = oo::PList((bool)(UNIVERSE != nullptr ? UNIVERSE->dockingClearanceProtocolActive() : false));

	//base ship description
	if (const std::optional<std::string> value = shipDataKey())  result["ship_desc"] = oo::PList(*value);
	if (const std::optional<std::string> value = StringForKey(shipInfoDictionary(), std::string(KEY_NAME)))  result["ship_name"] = oo::PList(*value);

	//custom view no.
	result["custom_view_index"] = oo::PList::unsignedInteger((unsigned long)_customViewIndex);

	// escape pod rescue time
	result["escape_pod_rescue_time"] = oo::PList((double)escapePodRescueTime());	// oo_setFloat:

	//local market for main station
	::StationEntity *mainStation = (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr);
	OOCommodityMarket *mainStationMarket = (mainStation != nullptr ? mainStation->getLocalMarket() : (OOCommodityMarket *)nullptr);
	if (mainStationMarket)  result["localMarket"] = mainStationMarket->saveStationAmounts();

	// Scenario restriction on OXZs
	if (const std::optional<std::string> value = (UNIVERSE != nullptr ? UNIVERSE->getUseAddOns() : std::optional<std::string>()))  result["scenario_restriction"] = oo::PList(*value);

	result["scripted_planetinfo_overrides"] = ((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->exportScriptedChanges() : oo::PList());

	// trumble information (unmigrated: OOTrumble's records)
	const oo::PList trumbles = trumbleValue();
	if (!trumbles.isNull())  result["trumbles"] = trumbles;

	// wormhole information
	oo::PList::Array wormholeDicts;
	wormholeDicts.reserve(scannedWormholes.size());
	for (const oo::EntityHold &wh : scannedWormholes)
	{
		wormholeDicts.push_back(static_cast<WormholeEntity *>(wh.get())->getDict());	// the list holds wormholes only
	}
	result["wormholes"] = oo::PList(std::move(wormholeDicts));

	// docked station
	::StationEntity *dockedStation = this->dockedStation();
	result["docked_station_role"] = oo::PList(dockedStation != nil ? (dockedStation != nullptr ? dockedStation->getPrimaryRole() : std::optional<std::string>()).value_or(std::string()) : std::string());
	if (dockedStation)
	{
		HPVector dpos = (dockedStation != nullptr ? dockedStation->getPosition() : HPVector{});
		{
			oo::PList::Array coords;
			for (double component : cxx_ArrayFromHPVector(dpos))  coords.push_back(oo::PList(component));
			result["docked_station_position"] = oo::PList(std::move(coords));
		}
	}
	else
	{
		result["docked_station_position"] = oo::PList(oo::PList::Array());
	}
	result["station_markets"] = (UNIVERSE != nullptr ? UNIVERSE->getStationMarkets() : oo::PList());

	// scenario information
	if (scenarioKey.has_value())
	{
		result["scenario"] = oo::PList(*scenarioKey);
	}

	// create checksum
	clear_checksum();
// TODO: should checksum checks be removed?
//	munge_checksum(galaxy_seed.a);	munge_checksum(galaxy_seed.b);	munge_checksum(galaxy_seed.c);
//	munge_checksum(galaxy_seed.d);	munge_checksum(galaxy_seed.e);	munge_checksum(galaxy_seed.f);
	munge_checksum(galaxy_coordinates.x);	munge_checksum(galaxy_coordinates.y);
	munge_checksum(credits);		munge_checksum(fuel);
	munge_checksum(max_cargo);		munge_checksum(missiles);
	munge_checksum(legalStatusValue);	munge_checksum(market_rnd);		munge_checksum(ship_kills);

	if (!mission_variables.isNull())
	{
		// the length of the dictionary's -description, as before (the same GNUstep text)
		munge_checksum(oo::str::length(oo::DescriptionOf(mission_variables)));
	}
	// the equipment dictionary always existed: the length of its -description, as above
	munge_checksum(oo::str::length(oo::DescriptionOf(oo::PList(equipment))));

	int final_checksum = munge_checksum(oo::str::length(shipDataKey().value_or(std::string())));

	//set checksum
	result["checksum"] = oo::PList::signedInteger((long)final_checksum);

	return oo::PList(std::move(result));
}



// Slice 4 of docs/phases/3-slices/PlayerEntity.md (bead oo-qvnwb): setting the commander data from a dictionary (load).
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

bool PlayerEntity::setCommanderDataFromDictionary(const oo::PList &dict)
{
	// multi-function displays
	// must be reset before ship setup
	multiFunctionDisplayText.clear();

	multiFunctionDisplaySettings.clear();

	customDialSettings.clear();

	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->resetTypedString();

	// Required keys
	if (!StringForKey(dict, "ship_desc").has_value())  return NO;
	// galaxy_seed is used is 1.80 or earlier
	if (!StringForKey(dict, "galaxy_seed").has_value() && !StringForKey(dict, "galaxy_id").has_value())  return NO;
	// galaxy_coordinates is used is 1.80 or earlier
	if (!StringForKey(dict, "galaxy_coordinates").has_value() && !StringForKey(dict, "system_id").has_value())  return NO;

	std::optional<std::string> scenarioRestrict = StringForKey(dict, "scenario_restriction");
	if (!scenarioRestrict.has_value())
	{
		// older save game - use the 'strict' key instead
		BOOL strict = dict.get<bool>("strict", NO);
		if (strict)
		{
			scenarioRestrict = std::string(SCENARIO_OXP_DEFINITION_NONE);
		}
		else
		{
			scenarioRestrict = std::string(SCENARIO_OXP_DEFINITION_ALL);
		}
	}

	if (!(UNIVERSE != nullptr ? UNIVERSE->setUseAddOns(*scenarioRestrict, YES) : false))
	{
		return NO;
	}


	//base ship description
	setShipDataKey(StringForKey(dict, "ship_desc"));

	const std::optional<std::string> shipDataKey = this->shipDataKey();
	const oo::PList shipDict = shipDataKey.has_value() ? OOShipRegistry::sharedRegistry()->shipInfoForKey(*shipDataKey) : oo::PList();
	if (shipDict.isNull())  return NO;
	if (!setUpShipFromDictionary(shipDict))  return NO;
	OO_LOG("fuelPrices", "Got \"{}\", fuel charge rate: {:.2f}", this->shipDataKey().value_or("(null)"), fuelChargeRate());

	// ship depreciation
	ship_trade_in_factor = dict.get<int>("ship_trade_in_factor", 95);

	// newer savegames use galaxy_id
	if (StringForKey(dict, "galaxy_id").has_value())
	{
		galaxy_number = dict.get<NSUInteger>("galaxy_id");
		if (galaxy_number >= OO_GALAXIES_AVAILABLE)
		{
			return NO;
		}
		if (UNIVERSE != nullptr)  UNIVERSE->setGalaxyTo(galaxy_number, YES);

		system_id = dict.get<int>("system_id");
		if (system_id < 0 || system_id >= OO_SYSTEMS_PER_GALAXY)
		{
			return NO;
		}

		if (UNIVERSE != nullptr)  UNIVERSE->setSystemTo(system_id);

		std::vector<std::string> coord_vals = CoordinateTokens(((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getProperty("coordinates", system_id, galaxy_number) : oo::PList()));
		galaxy_coordinates.x = CoordinateAt(coord_vals, 0);
		galaxy_coordinates.y = CoordinateAt(coord_vals, 1);
		chart_centre_coordinates = galaxy_coordinates;
		target_chart_centre = chart_centre_coordinates;
		cursor_coordinates = galaxy_coordinates;
		chart_zoom = dict.get<float>("chart_zoom", 1.0);
		target_chart_zoom = chart_zoom;
		saved_chart_zoom = chart_zoom;
		ANA_mode = (OORouteType)dict.get<int>("chart_ana_mode", OPTIMIZED_BY_NONE);
		longRangeChartMode = (OOLongRangeChartMode)dict.get<int>("chart_colour_mode", OOLRC_MODE_SUNCOLOR);
		if (longRangeChartMode == OOLRC_MODE_UNKNOWN) longRangeChartMode = OOLRC_MODE_SUNCOLOR;

		target_system_id = dict.get<int>("target_id", system_id);
		previous_system_id = dict.get<int>("previous_system_id", system_id);
		info_system_id = target_system_id;
		coord_vals = CoordinateTokens(((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getProperty("coordinates", target_system_id, galaxy_number) : oo::PList()));
		cursor_coordinates.x = CoordinateAt(coord_vals, 0);
		cursor_coordinates.y = CoordinateAt(coord_vals, 1);

		chart_focus_coordinates = chart_centre_coordinates;
		target_chart_focus = chart_focus_coordinates;

		found_system_id = dict.get<int>("found_system_id", -1);
	}
	else
		// compatibility for loading 1.80 savegames
	{
		galaxy_number = dict.get<NSUInteger>("galaxy_number");

		if (UNIVERSE != nullptr)  UNIVERSE->setGalaxyTo(galaxy_number, YES);

		std::vector<std::string> coord_vals = oo::str::tokens(StringForKey(dict, "galaxy_coordinates").value_or(std::string()));
		galaxy_coordinates.x = CoordinateAt(coord_vals, 0);
		galaxy_coordinates.y = CoordinateAt(coord_vals, 1);
		chart_centre_coordinates = galaxy_coordinates;
		target_chart_centre = chart_centre_coordinates;
		cursor_coordinates = galaxy_coordinates;
		chart_zoom = 1.0;
		target_chart_zoom = 1.0;
		saved_chart_zoom = 1.0;
		ANA_mode = OPTIMIZED_BY_NONE;

		const std::optional<std::string> keyStringValue = StringForKey(dict, "target_coordinates");

		if (keyStringValue.has_value())
		{
			coord_vals = oo::str::tokens(*keyStringValue);
			cursor_coordinates.x = CoordinateAt(coord_vals, 0);
			cursor_coordinates.y = CoordinateAt(coord_vals, 1);
		}
		chart_focus_coordinates = chart_centre_coordinates;
		target_chart_focus = chart_focus_coordinates;

		// calculate system ID, target ID
		if (dict.find("current_system_name") != nullptr)
		{
			const std::optional<std::string> systemName = StringForKey(dict, "current_system_name");
			system_id = systemName.has_value() ? (UNIVERSE != nullptr ? UNIVERSE->findSystemFromName(*systemName) : 0) : -1;	// (nil matched nothing)
			if (system_id == -1)  system_id = (UNIVERSE != nullptr ? UNIVERSE->findSystemNumberAtCoords(galaxy_coordinates, galaxy_number, YES) : 0);
		}
		else
		{
			// really old save games don't have system name saved
			// use coordinates instead - unreliable in zero-distance pairs.
			system_id = (UNIVERSE != nullptr ? UNIVERSE->findSystemNumberAtCoords(galaxy_coordinates, galaxy_number, YES) : 0);
		}
		// and current_system_name and target_system_name
		// were introduced at different times, too
		if (dict.find("target_system_name") != nullptr)
		{
			const std::optional<std::string> systemName = StringForKey(dict, "target_system_name");
			target_system_id = systemName.has_value() ? (UNIVERSE != nullptr ? UNIVERSE->findSystemFromName(*systemName) : 0) : -1;
			if (target_system_id == -1)  target_system_id = (UNIVERSE != nullptr ? UNIVERSE->findSystemNumberAtCoords(cursor_coordinates, galaxy_number, YES) : 0);
		}
		else
		{
			target_system_id = (UNIVERSE != nullptr ? UNIVERSE->findSystemNumberAtCoords(cursor_coordinates, galaxy_number, YES) : 0);
		}
		info_system_id = target_system_id;
		found_system_id = -1;
	}

	const std::string cname = StringForKey(dict, "player_name").value_or(std::string(PLAYER_DEFAULT_NAME));
	setCommanderName(cname);
	setLastsaveName(StringForKey(dict, "player_save_name").value_or(cname));

	setShipUniqueName(StringForKey(dict, "ship_unique_name").value_or(std::string()));
	std::optional<std::string> savedClassName = StringForKey(dict, "ship_class_name");
	if (!savedClassName.has_value())  savedClassName = StringForKey(shipDict, "name");
	setShipClassName(savedClassName);

	const oo::PList *savedAmounts = dict.get<oo::PList::Array>("shipCommodityData");
	if (shipCommodityData != nullptr)  shipCommodityData->loadPlayerAmounts((savedAmounts != nullptr) ? *savedAmounts : oo::PList());

	// extra equipment flags
	removeAllEquipment();
	const oo::PList *savedEquipment = dict.get<oo::PList::Dict>("extra_equipment");
	oo::PList::Dict equipment = (savedEquipment != nullptr) ? *savedEquipment->getIf<oo::PList::Dict>() : oo::PList::Dict();
	const oo::PList one = oo::PList::signedInteger(1);	// oo_setInteger:1 (+numberWithLong:)

	// Equipment flags	(deprecated in favour of equipment dictionary, keep for compatibility)
	if (dict.get<bool>("has_docking_computer"))		equipment["EQ_DOCK_COMP"] = one;
	if (dict.get<bool>("has_galactic_hyperdrive"))	equipment["EQ_GAL_DRIVE"] = one;
	if (dict.get<bool>("has_escape_pod"))				equipment["EQ_ESCAPE_POD"] = one;
	if (dict.get<bool>("has_ecm"))					equipment["EQ_ECM"] = one;
	if (dict.get<bool>("has_scoop"))					equipment["EQ_FUEL_SCOOPS"] = one;
	if (dict.get<bool>("has_energy_bomb"))			equipment["EQ_ENERGY_BOMB"] = one;
	if (dict.get<bool>("has_fuel_injection"))		equipment["EQ_FUEL_INJECTION"] = one;


	// Legacy energy unit type -> energy unit equipment item
	if (dict.get<bool>("has_energy_unit") && installedEnergyUnitType() == ENERGY_UNIT_NONE)
	{
		OOEnergyUnitType eType = (OOEnergyUnitType)dict.get<int>("energy_unit", ENERGY_UNIT_NORMAL);
		switch (eType)
		{
			// look for NEU first!
			case OLD_ENERGY_UNIT_NAVAL:
				equipment["EQ_NAVAL_ENERGY_UNIT"] = one;
				break;

			case OLD_ENERGY_UNIT_NORMAL:
				equipment["EQ_ENERGY_UNIT"] = one;
				break;

			default:
				break;
		}
	}

	custom_chart_zoom = 1.0;
	custom_chart_centre_coordinates = NSMakePoint(galaxy_coordinates.y, galaxy_coordinates.y);

	/*	Energy bombs are no longer supported without OXPs. As compensation,
		we'll award either a Q-mine or some cash. We can't determine what to
		award until we've handled missiles later on, though.
	*/
	BOOL energyBombCompensation = NO;
	const auto energyBomb = equipment.find("EQ_ENERGY_BOMB");
	if (energyBomb != equipment.end() && oo::PListGet<bool>::from(&energyBomb->second, false) && OOEquipmentType::equipmentTypeWithIdentifier("EQ_ENERGY_BOMB").get() == nil)
	{
		energyBombCompensation = YES;
		equipment.erase(energyBomb);
	}

	eqScripts.clear();
	addEquipmentFromCollection(oo::PList(equipment));
	primedEquipment = eqScriptIndexForKey(StringForKey(dict, "primed_equipment").value_or(""));	// if key not found primedEquipment is set to primed-none

	setFastEquipmentA(StringForKey(dict, "primed_equipment_a").value_or("EQ_CLOAKING_DEVICE"));
	setFastEquipmentB(StringForKey(dict, "primed_equipment_b").value_or("EQ_ENERGY_BOMB")); // even though there isn't one, for compatibility.

	if (hasEquipmentItemProviding("EQ_ADVANCED_COMPASS"))  compassMode = COMPASS_MODE_PLANET;
	else  compassMode = COMPASS_MODE_BASIC;
	compassTarget = nullptr;

	// speech
	isSpeechOn = (OOSpeechSettings)dict.get<int>("speech_on");
#if OOLITE_ESPEAK
	voice_gender_m = dict.get<bool>("speech_gender", YES);
	const std::optional<std::string> speechVoice = StringForKey(dict, "speech_voice");
	voice_no = (UNIVERSE != nullptr ? UNIVERSE->setVoice((speechVoice.has_value() ? (UNIVERSE != nullptr ? UNIVERSE->voiceNumber(*speechVoice) : 0u) : UINT_MAX), voice_gender_m) : 0u);	// (a nil voice was UINT_MAX)
#endif

	// reputation
	const oo::PList &savedReputation = ValueForKey(dict, "reputation");
	reputation = savedReputation.isDict() ? *savedReputation.getIf<oo::PList::Dict>() : oo::PList::Dict();	// -oo_dictionaryForKey:, empty if none
	normaliseReputation();

	// passengers and contracts

	max_passengers = dict.get<int>("max_passengers", 0);
	const oo::PList &savedPassengers = ValueForKey(dict, "passengers");
	passengers = savedPassengers.isArray() ? *savedPassengers.getIf<oo::PList::Array>() : oo::PList::Array();	// -oo_arrayForKey:, empty if none
	const oo::PList &savedPassengerRecord = ValueForKey(dict, "passenger_record");
	passenger_record = savedPassengerRecord.isDict() ? *savedPassengerRecord.getIf<oo::PList::Dict>() : oo::PList::Dict();
	/* Note: contracts from older savegames will have ints in the commodity.
	 * Need to fix this up */
	const oo::PList &savedContracts = ValueForKey(dict, "contracts");
	contracts = savedContracts.isArray() ? *savedContracts.getIf<oo::PList::Array>() : oo::PList::Array();	// -oo_arrayForKey:, empty if none

	// iterate downwards; lets us remove invalid ones as we go
	for (NSInteger i = (NSInteger)contracts.size() - 1; i >= 0; i--)
	{
		oo::PList contractInfo = contracts[i].isDict() ? contracts[i] : oo::PList(oo::PList::Dict());
		const oo::PList *cargoType = contractInfo.find(std::string(CARGO_KEY_TYPE));
		// if the trade good ID is an int
		if (cargoType != nullptr && cargoType->isNumber())
		{
			// look it up, and replace with a string
			NSUInteger legacy_type = contractInfo.get<NSUInteger>(std::string(CARGO_KEY_TYPE));
			(*contractInfo.getIf<oo::PList::Dict>())[std::string(CARGO_KEY_TYPE)] = oo::PList(OOCommodities::legacyCommodityType(legacy_type).value_or(""));
			contracts[i] = std::move(contractInfo);
		}
		else
		{
			// -oo_stringForKey: (nil when absent)
			const oo::PList *typeValue = contractInfo.find(std::string(CARGO_KEY_TYPE));
			const std::optional<std::string> new_type = (typeValue != nullptr && typeValue->isString()) ? std::optional<std::string>(*typeValue->getIf<std::string>()) : std::nullopt;
			// check that that the type still exists
			if (!((UNIVERSE != nullptr ? UNIVERSE->getCommodities() : nullptr) != nullptr ? UNIVERSE->getCommodities()->goodDefined(new_type.value_or("")) : false))
			{
				OO_LOG("setCommanderDataFromDictionary.warning.contract", "Cargo contract to deliver {} could not be loaded from the saved game, as the commodity is no longer defined", new_type.value_or("(null)"));
				contracts.erase(contracts.begin() + i);
			}
		}
	}

	const oo::PList savedContractRecord = ValueForKey(dict, "contract_record");
	contract_record = savedContractRecord.isDict() ? *savedContractRecord.getIf<oo::PList::Dict>() : oo::PList::Dict();
	const oo::PList savedParcels = ValueForKey(dict, "parcels");
	parcels = savedParcels.isArray() ? *savedParcels.getIf<oo::PList::Array>() : oo::PList::Array();	// -oo_arrayForKey:, empty if none
	const oo::PList savedParcelRecord = ValueForKey(dict, "parcel_record");
	parcel_record = savedParcelRecord.isDict() ? *savedParcelRecord.getIf<oo::PList::Dict>() : oo::PList::Dict();

	
	
	
	//specialCargo
	// a string (or a number, as text), else none: as -oo_stringForKey: read it
	const oo::PList savedSpecialCargo = ValueForKey(dict, "special_cargo");
	specialCargo = (savedSpecialCargo.isString() || savedSpecialCargo.isNumber()) ? std::optional<std::string>(oo::PListGet<std::string>::from(&savedSpecialCargo, std::string())) : std::nullopt;
	
	// mission destinations
	const oo::PList legacyDestinations = ValueForKey(dict, "missionDestinations");	// used only if an array

	const oo::PList newDestinations = ValueForKey(dict, "mission_destinations");	// used only if a dictionary
	initialiseMissionDestinations(newDestinations, legacyDestinations);
	
	// shipyard
	const oo::PList savedShipyardRecord = ValueForKey(dict, "shipyard_record");
	shipyard_record = savedShipyardRecord.isDict() ? *savedShipyardRecord.getIf<oo::PList::Dict>() : oo::PList::Dict();	// -oo_dictionaryForKey:, empty if none
	
	// Normalize cargo capacity
	unsigned	original_hold_size = (UNIVERSE != nullptr ? UNIVERSE->maxCargoForShip(this->shipDataKey().value_or("")) : 0);
	// Not Suitable For Oolite
	//unsigned 	passenger_space = [[OOEquipmentType equipmentTypeWithIdentifier:@"EQ_PASSENGER_BERTH"] requiredCargoSpace];
	//if (passenger_space == 0) passenger_space = PASSENGER_BERTH_SPACE;
	
	max_cargo = dict.get<unsigned int>("max_cargo", max_cargo);
	if (max_cargo > original_hold_size)  addEquipmentItem("EQ_CARGO_BAY", "loading");
	max_cargo = original_hold_size + (hasExpandedCargoBay() ? extra_cargo : 0);
	if (max_cargo < max_passengers * PASSENGER_BERTH_SPACE)
	{
		// Something went wrong. Possibly the save file was hacked to contain more passenger cabins than the available cargo space would allow - Nikos 20110731
		unsigned originalMaxPassengers = max_passengers;
		max_passengers = (unsigned)(max_cargo / PASSENGER_BERTH_SPACE);
		OO_LOG_WARN("setCommanderDataFromDictionary.inconsistency.max_passengers", "player ship {} had max_passengers set to a value requiring more cargo space than currently available ({}). Setting max_passengers to maximum possible value ({}).", getName().value_or("(null)"), static_cast<unsigned>(originalMaxPassengers), static_cast<unsigned>(max_passengers));
	}
	max_cargo -= max_passengers * PASSENGER_BERTH_SPACE;
	
	// Do we have extra passengers?
	if (passengers.size() > max_passengers)
	{
		OO_LOG_WARN("setCommanderDataFromDictionary.inconsistency.passengers", "player ship {} had more passengers ({}) than passenger berths ({}). Removing extra passengers.", getName().value_or("(null)"), passengers.size(), static_cast<unsigned>(max_passengers));
		for (NSInteger i = (NSInteger)passengers.size() - 1; i >= max_passengers; i--)
		{
			const oo::PList *passengerName = passengers[i].find(std::string(PASSENGER_KEY_NAME));
			if (passengerName != nullptr && (passengerName->isString() || passengerName->isNumber()))  passenger_record.erase(passengers[i].get<std::string>(std::string(PASSENGER_KEY_NAME)));	// -oo_stringForKey:
			passengers.erase(passengers.begin() + i);
		}
	}
	
	// too much cargo?	
	NSInteger excessCargo = (NSInteger)cargoQuantityOnBoard() - (NSInteger)maxAvailableCargoSpace();
	if (excessCargo > 0)
	{
		OO_LOG_WARN("setCommanderDataFromDictionary.inconsistency.cargo", "player ship {} had more cargo ({}) than it can hold ({}). Removing extra cargo.", getName().value_or("(null)"), cargoQuantityOnBoard(), static_cast<unsigned>(maxAvailableCargoSpace()));
		
		OOMassUnit			units;
		OOCargoQuantity		oldAmount, toRemove;
		
		OOCargoQuantity remainingExcess = (OOCargoQuantity)excessCargo;
		
		// manifest always contains entries for all 17 commodities, even if their quantity is 0.
		for (const std::string &type : (shipCommodityData != nullptr ? shipCommodityData->goods() : std::vector<std::string>()))
		{
			units =	(shipCommodityData != nullptr ? shipCommodityData->massUnitForGood(type) : UNITS_TONS);

			oldAmount = (shipCommodityData != nullptr ? shipCommodityData->quantityForGood(type) : 0);
			BOOL roundedTon = (units != UNITS_TONS) && ((units == UNITS_KILOGRAMS && oldAmount > MAX_KILOGRAMS_IN_SAFE) || (units == UNITS_GRAMS && oldAmount > MAX_GRAMS_IN_SAFE));
			if (roundedTon || (units == UNITS_TONS && oldAmount > 0))
			{
				// let's remove stuff
				OOCargoQuantity partAmount = oldAmount;
				toRemove = 0;
				while (remainingExcess > 0 && partAmount > 0)
				{
					if (EXPECT_NOT(roundedTon && ((units == UNITS_KILOGRAMS && partAmount > MAX_KILOGRAMS_IN_SAFE) || (units == UNITS_GRAMS && partAmount > MAX_GRAMS_IN_SAFE))))
					{
						toRemove += (units == UNITS_KILOGRAMS) ? (partAmount > (KILOGRAMS_PER_POD + MAX_KILOGRAMS_IN_SAFE) ? KILOGRAMS_PER_POD : partAmount - MAX_KILOGRAMS_IN_SAFE)
									: (partAmount > (GRAMS_PER_POD + MAX_GRAMS_IN_SAFE) ? GRAMS_PER_POD : partAmount - MAX_GRAMS_IN_SAFE);
						partAmount = oldAmount - toRemove;
						remainingExcess--;
					}
					else if (!roundedTon)
					{
						toRemove++;
						partAmount--;
						remainingExcess--;
					}
					else
					{
						partAmount = 0;
					}
				}
				if (shipCommodityData != nullptr)  shipCommodityData->removeQuantity(toRemove, type);
			}
		}
	}
	
	{ const oo::PList creditsValue = ValueForKey(dict, "credits"); credits = OODeciCreditsFromPList(&creditsValue); }
	
	fuel = dict.get<unsigned int>("fuel", fuel);
	galaxy_number = dict.get<int>("galaxy_number");
//
	const oo::PList shipyard_info = shipDataKey.has_value() ? OOShipRegistry::sharedRegistry()->shipyardInfoForKey(*shipDataKey) : oo::PList();
	OOWeaponFacingSet available_facings = shipyard_info.get<unsigned int>(std::string(KEY_WEAPON_FACINGS), weaponFacings());

	if (available_facings & WEAPON_FACING_FORWARD)
		forward_weapon_type = cxx_OOWeaponTypeFromEquipmentIdentifierLegacy(StringForKey(dict, "forward_weapon").value_or(""));
	else
		forward_weapon_type = cxx_OOWeaponTypeFromEquipmentIdentifierSloppy("EQ_WEAPON_NONE");

	if (available_facings & WEAPON_FACING_AFT)
		aft_weapon_type = cxx_OOWeaponTypeFromEquipmentIdentifierLegacy(StringForKey(dict, "aft_weapon").value_or(""));
	else
		aft_weapon_type = cxx_OOWeaponTypeFromEquipmentIdentifierSloppy("EQ_WEAPON_NONE");

	if (available_facings & WEAPON_FACING_PORT)
		port_weapon_type = cxx_OOWeaponTypeFromEquipmentIdentifierLegacy(StringForKey(dict, "port_weapon").value_or(""));
	else
		port_weapon_type = cxx_OOWeaponTypeFromEquipmentIdentifierSloppy("EQ_WEAPON_NONE");

	if (available_facings & WEAPON_FACING_STARBOARD)
		starboard_weapon_type = cxx_OOWeaponTypeFromEquipmentIdentifierLegacy(StringForKey(dict, "starboard_weapon").value_or(""));
	else
		starboard_weapon_type = cxx_OOWeaponTypeFromEquipmentIdentifierSloppy("EQ_WEAPON_NONE");

	setWeaponDataFromType(forward_weapon_type);

	if (hud != nil && hud->nonlinearScanner())
	{
		hud->setScannerZoom(dict.get<float>("ship_scanner_zoom", 1.0));
	}
	
	weapons_online = dict.get<bool>("weapons_online", YES);
	
	legalStatusValue = dict.get<int>("legal_status");
	market_rnd = dict.get<int>("market_rnd");
	ship_kills = dict.get<int>("ship_kills");
	
	ship_clock = dict.get<double>("ship_clock", PLAYER_SHIP_CLOCK_START);
	fps_check_time = ship_clock;
	
	escape_pod_rescue_time = dict.get<double>("escape_pod_rescue_time", 0.0);
	
	// role weights
	const oo::PList savedRoles = ValueForKey(dict, "role_weights");
	NSUInteger rc = maxPlayerRoles();
	roleWeights.clear();
	if (!savedRoles.isArray())
	{
		roleWeights.assign(rc, "player-unknown");
	}
	else
	{
		for (size_t roleIndex = 0; roleIndex < savedRoles.count(); roleIndex++)
		{
			// the roles are strings: anything else is dropped
			if (const std::string *role = savedRoles.at(roleIndex)->getIf<std::string>())  roleWeights.push_back(*role);
		}
		if (roleWeights.size() > rc)
		{
			roleWeights.resize(rc);
		}
	}

	const oo::PList savedFlags = ValueForKey(dict, "role_weight_flags");
	roleWeightFlags = savedFlags.isDict() ? *savedFlags.getIf<oo::PList::Dict>() : oo::PList::Dict();

	const oo::PList savedSystems = ValueForKey(dict, "role_system_memory");
	roleSystemList.clear();
	for (size_t systemIndex = 0; savedSystems.isArray() && systemIndex < savedSystems.count(); systemIndex++)
	{
		roleSystemList.push_back(savedSystems.at<int>(systemIndex));	// -intValue
	}


	// mission_variables
	mission_variables = ValueForKey(dict, "mission_variables");
	if (!mission_variables.isDict())  mission_variables = oo::PList(oo::PList::Dict{});	// absent or not a dictionary: empty
	
	// persistant UNIVERSE info
	const oo::PList *planetInfoOverrides = dict.get<oo::PList::Dict>("scripted_planetinfo_overrides");
	if (planetInfoOverrides != nullptr)
	{
		if ((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr)  UNIVERSE->getSystemManager()->importScriptedChanges(*planetInfoOverrides);	
	} 
	else
	{
		// no scripted overrides? What about 1.80-style local overrides?
		planetInfoOverrides = dict.get<oo::PList::Dict>("local_planetinfo_overrides");
		if (planetInfoOverrides != nullptr)
		{
			if ((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr)  UNIVERSE->getSystemManager()->importLegacyScriptedChanges(*planetInfoOverrides);
		}
	}
	
	// communications log
	commLog.clear();
	commLog.reserve(kCommLogTrimThreshold);

	const oo::PList savedCommLog = ValueForKey(dict, "comm_log");
	const std::size_t commCount = savedCommLog.isArray() ? savedCommLog.count() : 0;	// oo_arrayForKey:
	for (std::size_t i = 0; i < commCount; i++)
	{
		const std::string *savedMessage = savedCommLog.at(i)->getIf<std::string>();	// (a saved comm log holds strings)
		if (UNIVERSE != nullptr)  UNIVERSE->addCommsMessage((savedMessage != nullptr) ? std::optional<std::string>(*savedMessage) : std::nullopt, 0, NO, YES);
	}

	/*	entity_personality for scripts and shaders. If undefined, we fall back
		to old behaviour of using a random value each time game is loaded (set
		up in -setUp). Saving of entity_personality was added in 1.74.
		-- Ahruman 2009-09-13
	*/
	entity_personality = dict.get<unsigned short>("entity_personality", entity_personality);
	
	// set up missiles
	setActiveMissile(0);
	for (NSUInteger i = 0; i < PLAYER_MAX_MISSILES; i++)
	{
		missile_entity[i] = nullptr;
	}
	const oo::PList *missileRoles = dict.get<oo::PList::Array>("missile_roles");
	if (missileRoles != nullptr)
	{
		unsigned missileCount = 0;
		for (NSUInteger roleIndex = 0; roleIndex < missileRoles->count() && missileCount < max_missiles; roleIndex++)
		{
			const std::optional<std::string> missile_desc = StringAt(*missileRoles, roleIndex);
			if (missile_desc.has_value() && *missile_desc != "NONE")
			{
				::ShipEntity *amiss = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole(*missile_desc) : (::ShipEntity *)nil);
				if (amiss)
				{
					missile_list[missileCount] = OOEquipmentType::equipmentTypeWithIdentifier(*missile_desc).get();
					missile_entity[missileCount] = oo::EntityHold::adopt(amiss);   // retain count = 1
					missileCount++;
				}
				else
				{
					OO_LOG_WARN("load.failed.missileNotFound", "couldn't find missile with role '{}' in [PlayerEntity setCommanderDataFromDictionary:], missile entry discarded.", *missile_desc);
				}
			}
			missiles = missileCount;
		}
	}
	else	// no missile_roles
	{
		for (NSUInteger i = 0; i < missiles; i++)
		{
			missile_list[i] = OOEquipmentType::equipmentTypeWithIdentifier("EQ_MISSILE").get();
			missile_entity[i] = oo::EntityHold::adopt((UNIVERSE != nullptr ? UNIVERSE->newShipWithRole("EQ_MISSILE") : (::ShipEntity *)nil));	// retain count = 1 - should be okay as long as we keep a missile with this role
																			// in the base package.
		}
	}
	
	if (energyBombCompensation)
	{
		/*
			Compensate energy bomb with either a QC mine or the cost of an
			energy bomb (900 credits). This must be done after missiles are
			set up.
		*/
		if (mountMissileWithRole("EQ_QC_MINE"))
		{
			OO_LOG("load.upgrade.replacedEnergyBomb", "{}", "Replaced legacy energy bomb with Quirium cascade mine.");
		}
		else
		{
			credits += 9000;
			OO_LOG("load.upgrade.replacedEnergyBomb", "{}", "Compensated legacy energy bomb with 900 credits.");
		}
	}
	
	setActiveMissile(0);
	
	setHeatInsulation(1.0);

	max_forward_shield				= BASELINE_SHIELD_LEVEL;
	max_aft_shield					= BASELINE_SHIELD_LEVEL;

	forward_shield_recharge_rate	= 2.0;
	aft_shield_recharge_rate		= 2.0;

	forward_shield = maxForwardShieldLevel();
	aft_shield = maxAftShieldLevel();
	
	// used to get current_system and target_system here,
	// but stores the ID in the save file instead
	
	// restore subentities status
	deserializeShipSubEntitiesFrom(StringForKey(dict, "subentities_status").value_or(""));
	
	// wormholes
	const oo::PList whArray = ValueForKey(dict, "wormholes");
	scannedWormholes.clear();
	const oo::PList::Array *whList = whArray.getIf<oo::PList::Array>();
	if (whList != nullptr)  scannedWormholes.reserve(whList->size());
	for (const oo::PList &whCurrDict : (whList != nullptr) ? *whList : oo::PList::Array())
	{
		oo::Ref<WormholeEntity> whRef = oo::makeRef<WormholeEntity>();
		Entity *wh = oo::RetainEntity(oo::MadeEntity(whRef));	// its object (the +1 of the old +alloc is still never released, as before)
		whRef->initWithDict(whCurrDict);
		scannedWormholes.push_back(oo::EntityHold(wh));
		/* TODO - add to Universe if the wormhole hasn't expired yet; but in this case
		 * we need to save/load position and mass as well, which we currently 
		 * don't
		if (equal_seeds([wh origin], system_seed))
		{
			if (UNIVERSE != nullptr)  UNIVERSE->addEntity(wh);
		}
		*/
	}
	
	// custom view no.
	if (!_customViews.empty())	// (an empty custom_views array divided by zero before)
		_customViewIndex = dict.get<unsigned int>("custom_view_index") % _customViews.size();


	// docking clearance protocol
	if (UNIVERSE != nullptr)  UNIVERSE->setDockingClearanceProtocolActive(dict.get<bool>("docking_clearance_protocol", NO));
	
	// trumble information
	setUpTrumbles();
	const oo::PList *trumbles = dict.find("trumbles");
	setTrumbleValueFrom((trumbles != nullptr) ? *trumbles : oo::PList());	// if it doesn't exist we'll check user-defaults

	return YES;
}



// Slice 5 of docs/phases/3-slices/PlayerEntity.md (bead oo-mmcfq): set-up and start-up, ship set-up from the dictionary, the session, warning about hostiles.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

bool PlayerEntity::setUpAndConfirmOK(bool stopOnError)
{
	return setUpAndConfirmOK(stopOnError, NO);
}


bool PlayerEntity::setUpAndConfirmOK(bool stopOnError, bool saveGame)
{
	fieldOfView = (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->fov(YES) : 0.0f);
	unsigned i;
	
	showDemoShips = NO;
	show_info_flag = NO;
	marketSelectedCommodity.reset();
	
	// Reset JavaScript.
	::OOScriptTimer::noteGameReset();
	::OOScriptTimer::updateTimers();
	
	::GameController		*gc = (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getGameController() : (::GameController *)nullptr);
	
	if (!(gc != nullptr ? gc->inFullScreenMode() : false) && stopOnError)	{ if (gc != nullptr)  gc->stopAnimationTimer(); }	// start of critical section
	
	if (EXPECT_NOT(!OOJavaScriptEngine::sharedEngine()->reset() && stopOnError)) // always (try to) reset the engine, then find out if we need to stop.
	{
		/*
			Occasionally there's a racing condition between timers being deleted
			and the js engine needing to be reset: the engine reset stops the timers
			from being deleted, and undeleted timers don't allow the engine to reset
			itself properly.
			
			If the engine can't reset, let's give ourselves an extra 20ms to allow the
			timers to delete themselves.
			
			We'll piggyback performDeadUpdates: when STATUS_DEAD, the engine waits until 
			kDeadResetTime then restarts Oolite via [UNIVERSE updateGameOver]
			The variable shot_time is used to keep track of how long ago we were
			shot.
			
			If we're loading a savegame the code will try a new JS reset immediately
			after failing this reset...
		*/
		
		// set up STATUS_DEAD
		setDockedStation(nullptr);	// needed for STATUS_DEAD
		setStatus(STATUS_DEAD);
		OO_LOG("script.javascript.init.error", "{}", "Scheduling new JavaScript reset.");
		shot_time = kDeadResetTime - 0.02f;	// schedule reinit 20 milliseconds from now.
		
		if (!(gc != nullptr ? gc->inFullScreenMode() : false))	{ if (gc != nullptr)  gc->startAnimationTimer(); }	// keep the game ticking over.
		return NO;
	}
	
	// end of critical section
	if (!(gc != nullptr ? gc->inFullScreenMode() : false) && stopOnError)	{ if (gc != nullptr)  gc->startAnimationTimer(); }
	
	// Load locale script before any regular scripts.
	OOScriptAutorelease(OOScript::jsScriptFromFileNamed("oolite-locale-functions.js", oo::PList()));	// (nothing keeps it)
	
	::GameController::sharedController()->logProgress(OO_DESC("loading-scripts"));
	
	if (UNIVERSE != nullptr)  UNIVERSE->setBlockJSPlayerShipProps(NO);	// full access to player.ship properties!
	worldScripts.clear();
	worldScriptsRequiringTickle.reset();
	commodityScripts.clear();

#if OOLITE_WINDOWS
	if (saveGame)
	{
		if (UNIVERSE != nullptr)  UNIVERSE->preloadSounds();
		setUpSound();
		worldScripts = ResourceManager::loadScripts();
		if (UNIVERSE != nullptr)  UNIVERSE->loadConditionScripts();
	}
#else
	/* on OSes that allow safe deletion of open files, can use sounds
	 * on the OXZ screen and other start screens */
	if (UNIVERSE != nullptr)  UNIVERSE->preloadSounds();
	setUpSound();	// the C++ member (by name on the object until bead oo-9ht.39.7.3)
	if (saveGame)
	{
		worldScripts = ResourceManager::loadScripts();
		if (UNIVERSE != nullptr)  UNIVERSE->loadConditionScripts();
	}
#endif

	// make sure extraGuiScreenKeys is clear
	extraGuiScreenKeys.clear();

	::GameController::sharedController()->logProgress(cxx_OOExpandKeyRandomized("loading-miscellany").value_or(std::string()));
	
	// if there is cargo remaining from previously (e.g. a game restart), remove it (-cargoList was never nil)
	removeAllCargo(YES);		// force removal of cargo
	
	setShipDataKey(std::string(PLAYER_SHIP_DESC));
	ship_trade_in_factor = 95;
	
	// reset HUD & default commlog behaviour
	if (UNIVERSE != nullptr)  UNIVERSE->setAutoCommLog(YES);
	if (UNIVERSE != nullptr)  UNIVERSE->setPermanentCommLog(NO);
	
	multiFunctionDisplayText.clear();

	multiFunctionDisplaySettings.clear();

	customDialSettings.clear();

	switchHudTo("hud.plist");
	scanner_zoom_rate = 0.0f;
	longRangeChartMode = OOLRC_MODE_SUNCOLOR;

	mission_variables = oo::PList(oo::PList::Dict{});

	localVariables.clear();
	
	setScriptTarget(nullptr);
	resetMissionChoice();
	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->resetTypedString();
	found_system_id = -1;
	
	reputation = oo::PList::Dict{
		{ std::string(CONTRACTS_GOOD_KEY), oo::PList::signedInteger(0) },
		{ std::string(CONTRACTS_BAD_KEY), oo::PList::signedInteger(0) },
		{ std::string(CONTRACTS_UNKNOWN_KEY), oo::PList::signedInteger(MAX_CONTRACT_REP) },
		{ std::string(PASSAGE_GOOD_KEY), oo::PList::signedInteger(0) },
		{ std::string(PASSAGE_BAD_KEY), oo::PList::signedInteger(0) },
		{ std::string(PASSAGE_UNKNOWN_KEY), oo::PList::signedInteger(MAX_CONTRACT_REP) },
		{ std::string(PARCEL_GOOD_KEY), oo::PList::signedInteger(0) },
		{ std::string(PARCEL_BAD_KEY), oo::PList::signedInteger(0) },
		{ std::string(PARCEL_UNKNOWN_KEY), oo::PList::signedInteger(MAX_CONTRACT_REP) },
	};
	
	roleWeights.assign(8, "player-unknown");
	roleWeightFlags.clear();

	roleSystemList.clear();

	energy					= 256;
	weapon_temp				= 0.0f;
	forward_weapon_temp		= 0.0f;
	aft_weapon_temp			= 0.0f;
	port_weapon_temp		= 0.0f;
	starboard_weapon_temp	= 0.0f;
	lastShot.clear();
	forward_shot_time		= INITIAL_SHOT_TIME;
	aft_shot_time			= INITIAL_SHOT_TIME;
	port_shot_time			= INITIAL_SHOT_TIME;
	starboard_shot_time		= INITIAL_SHOT_TIME;
	ship_temperature		= 60.0f;
	alertFlags				= 0;
	hyperspeed_engaged		= NO;
	autopilot_engaged = NO;
	velocity = kZeroVector;
	
	flightRoll = 0.0f;
	flightPitch = 0.0f;
	flightYaw = 0.0f;

	max_passengers = 0;
	passengers.clear();
	passenger_record.clear();
	
	contracts.clear();
	contract_record.clear();

	parcels.clear();
	parcel_record.clear();
	
	missionDestinations.clear();

	shipyard_record.clear();
	
	target_memory.clear();
	target_memory.reserve(PLAYER_TARGET_MEMORY_SIZE);
	clearTargetMemory(); // also does first-time initialisation

	setMissionOverlayDescriptor(oo::PList());
	setMissionBackgroundDescriptor(oo::PList());
	setMissionBackgroundSpecial("");
	setEquipScreenBackgroundDescriptor(oo::PList());
	marketOffset = 0;
	marketSelectedCommodity.reset();

	script_time = 0.0;
	script_time_check = SCRIPT_TIMER_INTERVAL;
	script_time_interval = SCRIPT_TIMER_INTERVAL;
	
	// The local hour, minute and second of now, as the calendar date gave them (oofnd/Date.hpp; bead oo-qps.24).
	const oo::date::Clock::time_point now = oo::date::Clock::now();
	long long secondOfDay = (static_cast<long long>(std::chrono::floor<std::chrono::seconds>(now.time_since_epoch()).count()) +
							 static_cast<long long>(oo::date::localUTCOffsetMinutes(now)) * 60) % 86400;
	if (secondOfDay < 0)  secondOfDay += 86400;
	ship_clock = PLAYER_SHIP_CLOCK_START;
	ship_clock += static_cast<int>(secondOfDay / 3600) * 3600.0;
	ship_clock += static_cast<int>(secondOfDay / 60 % 60) * 60.0;
	ship_clock += static_cast<int>(secondOfDay % 60);
	fps_check_time = ship_clock;
	ship_clock_adjust = 0.0;
	escape_pod_rescue_time = 0.0;

	isSpeechOn = OOSPEECHSETTINGS_OFF;
#if OOLITE_ESPEAK
	voice_gender_m = YES;
	voice_no = (UNIVERSE != nullptr ? UNIVERSE->setVoice(-1, voice_gender_m) : 0u);
#endif
	
	_customViews.clear();
	_customViewIndex = 0;
	
	mouse_control_on = NO;
	
	// player commander data
	// Most of this is probably also set more than once
	
	setCommanderName(std::string(PLAYER_DEFAULT_NAME));
	setLastsaveName(std::string(PLAYER_DEFAULT_NAME));
	
	galaxy_coordinates		= NSMakePoint(0x14,0xAD);	// 20,173

	credits					= 1000;
	fuel					= PLAYER_MAX_FUEL;
	fuel_accumulator		= 0.0f;
	fuel_leak_rate			= 0.0f;
	
	galaxy_number			= 0;
	// will load real weapon data later
	forward_weapon_type		= nil;
	aft_weapon_type			= nil;
	port_weapon_type		= nil;
	starboard_weapon_type	= nil;
	scannerRange = (float)SCANNER_MAX_RANGE; 
	
	weapons_online			= YES;
	
	ecm_in_operation = NO;
	last_ecm_time = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0);
	compassMode = COMPASS_MODE_BASIC;
	ident_engaged = NO;
	
	max_cargo				= 20; // will be reset later
	marketFilterMode		= MARKET_FILTER_MODE_OFF;
	
	shipCommodityData = ((UNIVERSE != nullptr ? UNIVERSE->getCommodities() : nullptr) != nullptr ? UNIVERSE->getCommodities()->generateManifestForPlayer() : oo::Ref<OOCommodityMarket>());
	
	// set up missiles
	missiles				= PLAYER_STARTING_MISSILES;
	max_missiles			= PLAYER_STARTING_MAX_MISSILES;
	
	eqScripts.clear();
	primedEquipment = 0;
	setFastEquipmentA("EQ_CLOAKING_DEVICE");
	setFastEquipmentB("EQ_ENERGY_BOMB"); // for compatibility purposes

	setActiveMissile(0);
	for (i = 0; i < missiles; i++)
	{
		missile_entity[i] = nullptr;
	}
	safeAllMissiles();
	
	clearSubEntities();
	
	legalStatusValue				= 0;
	
	market_rnd				= 0;
	ship_kills				= 0;
	chart_centre_coordinates	= galaxy_coordinates;
	target_chart_centre		= chart_centre_coordinates;
	cursor_coordinates		= galaxy_coordinates;
	chart_focus_coordinates		= cursor_coordinates;
	target_chart_focus		= chart_focus_coordinates;
	chart_zoom			= 1.0;
	target_chart_zoom		= 1.0;
	saved_chart_zoom		= 1.0;
	ANA_mode			= OPTIMIZED_BY_NONE;

	
	scripted_misjump		= NO;
	_scriptedMisjumpRange	= 0.5;
	scoopOverride			= NO;
	
	max_forward_shield		= BASELINE_SHIELD_LEVEL;
	max_aft_shield			= BASELINE_SHIELD_LEVEL;

	forward_shield_recharge_rate	= 2.0;
	aft_shield_recharge_rate		= 2.0;

	forward_shield			= maxForwardShieldLevel();
	aft_shield				= maxAftShieldLevel();
	
	scanClass				= CLASS_PLAYER;
	
	if (UNIVERSE != nullptr)  UNIVERSE->clearGUIs();
	
	dockingClearanceStatus = DOCKING_CLEARANCE_STATUS_GRANTED;
	targetDockStation = nil;
	
	setDockedStation((UNIVERSE != nullptr ? UNIVERSE->station() : nullptr));
	
	commLog.clear();
	
	specialCargo.reset();

	// views
	forwardViewOffset		= kZeroVector;
	aftViewOffset			= kZeroVector;
	portViewOffset			= kZeroVector;
	starboardViewOffset		= kZeroVector;
	customViewOffset		= kZeroVector;
	
	currentWeaponFacing		= WEAPON_FACING_FORWARD;
	currentWeaponStats();
	
	save_path.reset();
	
	scannedWormholes.clear();
	
	setUpTrumbles();
	
	suppressTargetLostFlag = NO;
	
	scoopsActive = NO;
	
	dockingReport.clear();
	
	shipAI = ::AI::newWithStateMachine(std::string(PLAYER_DOCKING_AI_NAME), "GLOBAL");	// [shipAI release]; [[AI alloc] cxx_initWithStateMachine:andState:]
	resetAutopilotAI();
	
	lastScriptAlertCondition = getAlertCondition();
	
	entity_personality = ranrot_rand() & 0x7FFF;
	
	setSystemID((UNIVERSE != nullptr ? UNIVERSE->findSystemNumberAtCoords(getGalaxy_coordinates(), galaxy_number, YES) : 0));
	if (UNIVERSE != nullptr)  UNIVERSE->setGalaxyTo(galaxy_number);
	if (UNIVERSE != nullptr)  UNIVERSE->setSystemTo(system_id);

	setUpWeaponSounds();
	
	setGalacticHyperspaceBehaviourTo(StringForKey((UNIVERSE != nullptr ? UNIVERSE->getGlobalSettings() : oo::PList()), "galactic_hyperspace_behaviour").value_or("BEHAVIOUR_STANDARD"));
	setGalacticHyperspaceFixedCoordsTo(StringForKey((UNIVERSE != nullptr ? UNIVERSE->getGlobalSettings() : oo::PList()), "galactic_hyperspace_fixed_coords").value_or("96 96"));
	
	cloaking_device_active = NO;

	demoShip.leak();	// dropped without a release, as assigning nil to the raw pointer did (bead oo-5q11i keeps that)
	
	OOMusicController::sharedController()->justStop();
	stickProfileScreen = oo::makeRef<StickProfileScreen>();
	return YES;
}


void PlayerEntity::completeSetUp()
{
	completeSetUpAndSetTarget(YES);
}


void PlayerEntity::completeSetUpAndSetTarget(bool /*setTarget*/)
{
	::OOSoundSource::stopAll();

	setDockedStation((UNIVERSE != nullptr ? UNIVERSE->station() : nullptr));
	setLastAegisLock((UNIVERSE != nullptr ? UNIVERSE->planet() : nullptr));	// the planet is C++ since bead oo-9ht.129
	// only do this if we're not in strict mode, otherwise all previously saved OXP key/joystick defs will be wiped.
	if ((UNIVERSE != nullptr ? UNIVERSE->getUseAddOns() : std::optional<std::string>()) != std::string(SCENARIO_OXP_DEFINITION_NONE)) 
	{
		validateCustomEquipActivationArray();
	}

	ooscript::Context context = OOJSAcquireContext();
	{ const oo::PList startLimit = oo::Defaults::standard().object("start-script-limit-value");
	  doWorldScriptEvent(OOJSID("startUp"), context, NULL, 0, MAX(0.0, oo::PListGet<float>::from(startLimit.isNull() ? nullptr : &startLimit, kOOJSLongTimeLimit))); }
	OOJSRelinquishContext(context);
}


void PlayerEntity::startUpComplete()
{
	ooscript::Context context = OOJSAcquireContext();
	doWorldScriptEvent(OOJSID("startUpComplete"), context, NULL, 0, kOOJSLongTimeLimit);
	OOJSRelinquishContext(context);
}


bool PlayerEntity::setUpShipFromDictionary(const oo::PList &shipDict)
{
	compassTarget = nullptr;
	if (UNIVERSE != nullptr)  UNIVERSE->setBlockJSPlayerShipProps(NO);	// full access to player.ship properties!

	if (!ShipEntity::setUpFromDictionary(shipDict)) return NO;
	
	cargo.clear();

	// Player-only settings.
	//
	// set control factors..
	roll_delta =		2.0f * max_flight_roll;
	pitch_delta =		2.0f * max_flight_pitch;
	yaw_delta =			2.0f * max_flight_yaw;
	
	energy = maxEnergy;
	//if (forward_weapon_type == WEAPON_NONE) [self setWeaponDataFromType:forward_weapon_type]; 
	scannerRange = (float)SCANNER_MAX_RANGE; 
	
	roleSet = nullptr;
	setPrimaryRole("player");
	
	removeAllEquipment();
	const oo::PList *extraEquipment = shipDict.find("extra_equipment");
	addEquipmentFromCollection((extraEquipment != nullptr) ? *extraEquipment : oo::PList());

	resetHud();
	if (hud != nullptr)  hud->setHidden(NO);	// a message to nil did nothing
	
	// set up missiles
	// sanity check the number of missiles...
	if (max_missiles > PLAYER_MAX_MISSILES)  max_missiles = PLAYER_MAX_MISSILES;
	if (missiles > max_missiles)  missiles = max_missiles;
	// end sanity check

	unsigned i;
	for (i = 0; i < PLAYER_MAX_MISSILES; i++)
	{
		missile_entity[i] = nullptr;
	}
	for (i = 0; i < missiles; i++)
	{
		missile_list[i] = OOEquipmentType::equipmentTypeWithIdentifier("EQ_MISSILE").get();
		missile_entity[i] = oo::EntityHold::adopt((UNIVERSE != nullptr ? UNIVERSE->newShipWithRole("EQ_MISSILE") : (::ShipEntity *)nil));   // retain count = 1
	}
	
	_primaryTarget = nullptr;
	safeAllMissiles();
	setActiveMissile(0);
	
	// set view offsets
	setDefaultViewOffsets();
	
	if (EXPECT(_scaleFactor == 1.0f))
	{
		forwardViewOffset = VectorForKey(shipDict, "view_position_forward", forwardViewOffset);
		aftViewOffset = VectorForKey(shipDict, "view_position_aft", aftViewOffset);
		portViewOffset = VectorForKey(shipDict, "view_position_port", portViewOffset);
		starboardViewOffset = VectorForKey(shipDict, "view_position_starboard", starboardViewOffset);
	}
	else
	{
		forwardViewOffset = vector_multiply_scalar(VectorForKey(shipDict, "view_position_forward", forwardViewOffset),_scaleFactor);
		aftViewOffset = vector_multiply_scalar(VectorForKey(shipDict, "view_position_aft", aftViewOffset),_scaleFactor);
		portViewOffset = vector_multiply_scalar(VectorForKey(shipDict, "view_position_port", portViewOffset),_scaleFactor);
		starboardViewOffset = vector_multiply_scalar(VectorForKey(shipDict, "view_position_starboard", starboardViewOffset),_scaleFactor);
	}

	setDefaultCustomViews();
	
	const oo::PList &customViews = ValueForKey(shipDict, "custom_views");
	if (customViews.isArray())
	{
		_customViews = CustomViewsFrom(customViews);
		_customViewIndex = 0;
	}
	
	massLockable = shipDict.get<bool>("mass_lockable", YES);
	
	// Load js script
	OOScriptAutorelease(std::move(script));	// [script autorelease]
	const oo::PList scriptProperties(oo::PList::Dict{ { "ship", oo::EntityObjectNode(this) } });
	script = OOScript::jsScriptFromFileNamed(StringForKey(shipDict, "script").value_or(std::string()),	// (nil loaded nothing)
											 scriptProperties);
	if (script == nullptr)
	{
		// Do not switch to using a default value above; we want to use the default script if loading fails.
		script = OOScript::jsScriptFromFileNamed("oolite-default-player-script.js", scriptProperties);
	}
	
	return YES;
}


NSUInteger PlayerEntity::sessionID()
{
	// The player ship always belongs to the current session.
	return (UNIVERSE != nullptr ? UNIVERSE->sessionID() : 0);
}


void PlayerEntity::warnAboutHostiles()
{
	playHostileWarning();
}


bool PlayerEntity::canCollide()
{
	switch (status())
	{
		case STATUS_START_GAME:
		case STATUS_DOCKING:
		case STATUS_DOCKED:
		case STATUS_DEAD:
		case STATUS_ESCAPE_SEQUENCE:
			return NO;
		
		default:
			return YES;
	}
}



// Slice 6 of docs/phases/3-slices/PlayerEntity.md (bead oo-vzjco): sun glare, the atmosphere, update:.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

OOComparisonResult PlayerEntity::compareZeroDistance(Entity * /*otherEntity*/)
{
	return OOOrderedDescending;  // always the most near
}


bool PlayerEntity::validForAddToUniverse()
{
	return YES;
}


GLfloat PlayerEntity::lookingAtSunWithThresholdAngleCos(GLfloat thresholdAngleCos)
{
	::OOSunEntity	*sun = (UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr);
	GLfloat measuredCos = 999.0f, measuredCosAbs;
	GLfloat sunBrightness = 0.0f;
	Vector relativePosition, unitRelativePosition;
	
	if (EXPECT_NOT(!sun))  return 0.0f;
	
	// check if camera position is shadowed
	OOViewID vdir = (UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{});
	unsigned i;
	unsigned	ent_count =	UNIVERSE->n_entities;
	Entity		**uni_entities = UNIVERSE->sortedEntities;	// grab the public sorted list
	for (i = 0; i < ent_count; i++)
	{
		if (uni_entities[i]->isSunlit)
		{
			if (oo::EntityIsPlanet(uni_entities[i]) || 
				(oo::EntityIsShip(uni_entities[i]) &&
				 uni_entities[i]->isVisible()))
			{
				// the player ship can't shadow internal views
				if (EXPECT(vdir > VIEW_STARBOARD || !oo::EntityIsPlayer(uni_entities[i])))
				{
					float shadow = 1.5f;
					shadowAtPointOcclusionToValue(viewpointPosition(),1.0f,uni_entities[i],sun,&shadow);
					/* BUG: if the shadowing entity is not spherical, this gives over-shadowing. True elsewhere as well, but not so obvious there. */
					if (shadow < 1) {
						return 0.0f;
					}
				}
			}
		}
	}


	relativePosition = HPVectorToVector(HPvector_subtract(viewpointPosition(), (sun != nullptr ? sun->getPosition() : HPVector{})));
	unitRelativePosition = vector_normal_or_zbasis(relativePosition);
	switch (vdir)
	{
		case VIEW_FORWARD:
			measuredCos = -dot_product(unitRelativePosition, v_forward);
			break;
		case VIEW_AFT:
			measuredCos = +dot_product(unitRelativePosition, v_forward);
			break;
		case VIEW_PORT:
			measuredCos = +dot_product(unitRelativePosition, v_right);
			break;
		case VIEW_STARBOARD:
			measuredCos = -dot_product(unitRelativePosition, v_right);
			break;
 		case VIEW_CUSTOM:
			{
				Vector relativeView = getCustomViewForwardVector();
				Vector absoluteView = quaternion_rotate_vector(quaternion_conjugate(getOrientation()),relativeView);
				measuredCos = -dot_product(unitRelativePosition, absoluteView);
			}
			break;
			
		default:
			break;
	}
	measuredCosAbs = fabs(measuredCos);
	/*
	  Bugfix: 1.1f - floating point errors can mean the dot product of two
	  normalised vectors can be very slightly more than 1, which can
	  cause extreme flickering of the glare at certain ranges to the
	  sun. The real test is just that it's not still 999 - CIM
	 */
	if (thresholdAngleCos <= measuredCosAbs && measuredCosAbs <= 1.1f)	// angle from viewpoint to sun <= desired threshold
	{
		sunBrightness =  (measuredCos - thresholdAngleCos) / (1.0f - thresholdAngleCos);
//		/* glare.debug */ raw brightness = %f,sunBrightness);
		if (sunBrightness < 0.0f)  sunBrightness = 0.0f;
		else if (sunBrightness > 1.0f)  sunBrightness = 1.0f;
	}
//	/* glare.debug */ cos=%f, threshold = %f, brightness = %f,measuredCosAbs,thresholdAngleCos,sunBrightness);
	return sunBrightness * sunBrightness * sunBrightness;
}


GLfloat PlayerEntity::insideAtmosphereFraction()
{
	GLfloat insideAtmoFrac = 0.0f;
	
	if ((UNIVERSE != nullptr ? UNIVERSE->getAirResistanceFactor() : 0.0f) > 0.01)  // player is inside planetary atmosphere
	{
		insideAtmoFrac = 1.0f - (dialAltitude() *  (GLfloat)PLAYER_DIAL_MAX_ALTITUDE / (10.0f * (GLfloat)ATMOSPHERE_DEPTH));
	}
	
	return insideAtmoFrac;
}


void PlayerEntity::update(OOTimeDelta delta_t)
{
	STAGE_TRACKING_BEGIN
	
	UPDATE_STAGE("updateMovementFlags");
	updateMovementFlags();
	UPDATE_STAGE("updateAlertCondition");
	updateAlertCondition();
	UPDATE_STAGE("updateFuelScoops:");
	updateFuelScoops(delta_t);
	
	UPDATE_STAGE("updateClocks:");
	updateClocks(delta_t);
	
	// scripting
	UPDATE_STAGE("updateTimers");
	::OOScriptTimer::updateTimers();
	UPDATE_STAGE("checkScriptsIfAppropriate");
	checkScriptsIfAppropriate();
	
	// deal with collisions
	UPDATE_STAGE("manageCollisions");
	manageCollisions();
	
	UPDATE_STAGE("pollControls:");
	getPollControls(delta_t);
	
	UPDATE_STAGE("updateTrumbles:");
	updateTrumbles(delta_t);
	
	OOEntityStatus status = this->status();
	/* Validate that if the status is STATUS_START_GAME we're on one
	 * of the few GUI screens which that makes sense for */
	if (EXPECT_NOT(status == STATUS_START_GAME && 
				   gui_screen != GUI_SCREEN_INTRO1 && 
				   gui_screen != GUI_SCREEN_SHIPLIBRARY && 
				   gui_screen != GUI_SCREEN_GAMEOPTIONS && 
				   gui_screen != GUI_SCREEN_STICKMAPPER && 
				   gui_screen != GUI_SCREEN_STICKPROFILE && 
				   gui_screen != GUI_SCREEN_NEWGAME && 
				   gui_screen != GUI_SCREEN_OXZMANAGER && 
				   gui_screen != GUI_SCREEN_LOAD && 
				   gui_screen != GUI_SCREEN_KEYBOARD && 
				   gui_screen != GUI_SCREEN_KEYBOARD_CONFIRMCLEAR &&
				   gui_screen != GUI_SCREEN_KEYBOARD_CONFIG &&
				   gui_screen != GUI_SCREEN_KEYBOARD_ENTRY &&
				   gui_screen != GUI_SCREEN_KEYBOARD_LAYOUT))
	{
		// and if not, do a restart of the GUI
		UPDATE_STAGE("setGuiToIntroFirstGo:");
		setGuiToIntroFirstGo(YES);	//set up demo mode
	}
	
	if (status == STATUS_AUTOPILOT_ENGAGED || status == STATUS_ESCAPE_SEQUENCE)
	{
		UPDATE_STAGE("performAutopilotUpdates:");
		performAutopilotUpdates(delta_t);
	}
	else  if (!isDocked())
	{
		UPDATE_STAGE("performInFlightUpdates:");
		performInFlightUpdates(delta_t);
	}
	
	/*	NOTE: status-contingent updates are not a switch since they can
		cascade when status changes.
	*/
	if (status == STATUS_IN_FLIGHT)
	{
		UPDATE_STAGE("doBookkeeping:");
		doBookkeeping(delta_t);
	}
	if (status == STATUS_WITCHSPACE_COUNTDOWN)
	{
		UPDATE_STAGE("performWitchspaceCountdownUpdates:");
		performWitchspaceCountdownUpdates(delta_t);
	}
	if (status == STATUS_EXITING_WITCHSPACE)
	{
		UPDATE_STAGE("performWitchspaceExitUpdates:");
		performWitchspaceExitUpdates(delta_t);
	}
	if (status == STATUS_LAUNCHING)
	{
		UPDATE_STAGE("performLaunchingUpdates:");
		performLaunchingUpdates(delta_t);
	}
	if (status == STATUS_DOCKING)
	{
		UPDATE_STAGE("performDockingUpdates:");
		performDockingUpdates(delta_t);
	}
	if (status == STATUS_DEAD)
	{
		UPDATE_STAGE("performDeadUpdates:");
		performDeadUpdates(delta_t);
	}
	
	UPDATE_STAGE("updateWormholes");
	updateWormholes();
	
	STAGE_TRACKING_END
}



// Slice 7 of docs/phases/3-slices/PlayerEntity.md (bead oo-5c466): the bookkeeping tick (doBookkeeping:), movement flags.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

void PlayerEntity::doBookkeeping(double delta_t)
{
	STAGE_TRACKING_BEGIN
	
	double speed_delta = SHIP_THRUST_FACTOR * thrust;

  	static BOOL		gettingInterference = NO;
	
	::OOSunEntity	*sun = (UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr);
	double		external_temp = 0;
	GLfloat		air_friction = 0.0f;
	air_friction = 0.5f * (UNIVERSE != nullptr ? UNIVERSE->getAirResistanceFactor() : 0.0f);
	if (air_friction < 0.005f) // aRF < 0.01
	{
		// stops mysteriously overheating and exploding in the middle of empty space
		air_friction = 0;
	}

	UPDATE_STAGE("updating weapon temperatures and shot times");
	// cool all weapons.
	float coolAmount = WEAPON_COOLING_FACTOR * delta_t;
	forward_weapon_temp = fdim(forward_weapon_temp, coolAmount);
	aft_weapon_temp = fdim(aft_weapon_temp, coolAmount);
	port_weapon_temp = fdim(port_weapon_temp, coolAmount);
	starboard_weapon_temp = fdim(starboard_weapon_temp, coolAmount);
	
	// update shot times.
	forward_shot_time += delta_t;
	aft_shot_time += delta_t;
	port_shot_time += delta_t;
	starboard_shot_time += delta_t;
		
	// copy new temp & shot time to main temp & shot time
	switch (currentWeaponFacing)
	{
		case WEAPON_FACING_FORWARD:
			weapon_temp = forward_weapon_temp;
			shot_time = forward_shot_time;
			break;
		case WEAPON_FACING_AFT:
			weapon_temp = aft_weapon_temp;
			shot_time = aft_shot_time;
			break;
		case WEAPON_FACING_PORT:
			weapon_temp = port_weapon_temp;
			shot_time = port_shot_time;
			break;
		case WEAPON_FACING_STARBOARD:
			weapon_temp = starboard_weapon_temp;
			shot_time = starboard_shot_time;
			break;
			
		case WEAPON_FACING_NONE:
			break;
	}
	
	// cloaking device
	if (hasCloakingDevice() && cloaking_device_active)
	{
		UPDATE_STAGE("updating cloaking device");
		
		energy -= (float)delta_t * CLOAKING_DEVICE_ENERGY_RATE;
		if (energy < CLOAKING_DEVICE_MIN_ENERGY)
			deactivateCloakingDevice();
	}
	
	// military_jammer
	if (hasMilitaryJammer())
	{
		UPDATE_STAGE("updating military jammer");
		
		if (military_jammer_active)
		{
			energy -= (float)delta_t * MILITARY_JAMMER_ENERGY_RATE;
			if (energy < MILITARY_JAMMER_MIN_ENERGY)
				military_jammer_active = NO;
		}
		else
		{
			if (energy > 1.5 * MILITARY_JAMMER_MIN_ENERGY)
				military_jammer_active = YES;
		}
	}
	
	// ecm
	if (ecm_in_operation)
	{
		UPDATE_STAGE("updating ECM");
		
		if (energy > 0.0)
			energy -= (float)(ECM_ENERGY_DRAIN_FACTOR * delta_t);		// drain energy because of the ECM
		else
		{
			ecm_in_operation = NO;
			if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("ecm-out-of-juice"), 3.0);
		}
		if ((UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) > ecm_start_time + ECM_DURATION)
		{
			ecm_in_operation = NO;
		}
	}

  	// ecm interference visual effect
	if ((UNIVERSE != nullptr ? UNIVERSE->useShaders() : false) && (UNIVERSE != nullptr ? UNIVERSE->getECMVisualFXEnabled() : false))
	{
		// we want to start and stop the effect exactly once, not start it
		// or stop it on every frame
		if (scannerFuzziness() > 0.0)
		{
			if (!gettingInterference)
			{
				if (UNIVERSE != nullptr)  UNIVERSE->setCurrentPostFX(OO_POSTFX_CRTBADSIGNAL);
				gettingInterference = YES;
			}
		}
		else
		{
			if (gettingInterference)
			{
				if (UNIVERSE != nullptr)  UNIVERSE->terminatePostFX(OO_POSTFX_CRTBADSIGNAL);
				gettingInterference = NO;
			}
		}	
	}
	
	// Energy Banks and Shields
	
	/* Shield-charging behaviour, as per Eric's proposal:
	   1. If shields are less than a threshold, recharge with all available energy
	   2. If energy banks are below threshold, recharge with generated energy
	   3. Charge shields with any surplus energy
	*/
	UPDATE_STAGE("updating energy and shield charges");
	
	// 1. (Over)charge energy banks (will get normalised later)
	energy += energyRechargeRate() * delta_t;
	
	// 2. Calculate shield recharge rates
	float fwdMax = maxForwardShieldLevel();
	float aftMax = maxAftShieldLevel();
	float shieldRechargeFwd = forwardShieldRechargeRate() * delta_t;
	float shieldRechargeAft = aftShieldRechargeRate() * delta_t;
	/* there is potential for negative rechargeFwd and rechargeAFt values here
	   (e.g. getting shield boosters damaged while shields are full). This may
	   lead to energy being gained rather than consumed when recharging. Leaving
	   as-is for now, as there might be OXPs that rely in such behaviour.
	   Boosters case example mentioned above is the only known core equipment
	   occurrence at this time and it has been fixed inside the
	   oolite-equipment-control.js script. - Nikos 20160104.
	 */
	float rechargeFwd = MIN(shieldRechargeFwd, fwdMax - forward_shield);
	float rechargeAft = MIN(shieldRechargeAft, aftMax - aft_shield);
	
	// Note: we've simplified this a little, so if either shield is below
	//       the critical threshold, we allocate all energy.  Ideally we
	//       would only allocate the full recharge to the critical shield,
	//       but doing so would add another few levels of if-then below.
	float energyForShields = energy;
	if( (forward_shield > fwdMax * 0.25) && (aft_shield > aftMax * 0.25) )
	{
		// TODO: Can this be cached anywhere sensibly (without adding another member variable)?
		float minEnergyBankLevel = (UNIVERSE != nullptr ? UNIVERSE->getGlobalSettings() : oo::PList()).get<float>("shield_charge_energybank_threshold", 0.25);
		energyForShields = MAX(0.0, energy -0.1 - (maxEnergy * minEnergyBankLevel)); // NB: The - 0.1 ensures the energy value does not 'bounce' across the critical energy message and causes spurious energy-low warnings
	}
	
	if( forward_shield < aft_shield )
	{
		rechargeFwd = MIN(rechargeFwd, energyForShields);
		rechargeAft = MIN(rechargeAft, energyForShields - rechargeFwd);
	}
	else
	{
		rechargeAft = MIN(rechargeAft, energyForShields);
		rechargeFwd = MIN(rechargeFwd, energyForShields - rechargeAft);
	}
	
	// 3. Recharge shields, drain banks, and clamp values
	forward_shield += rechargeFwd;
	aft_shield += rechargeAft;
	energy -= rechargeFwd + rechargeAft;
	
	forward_shield = OOClamp_0_max_f(forward_shield, fwdMax);
	aft_shield = OOClamp_0_max_f(aft_shield, aftMax);
	energy = OOClamp_0_max_f(energy, maxEnergy);
	
	if (sun)
	{
		UPDATE_STAGE("updating sun effects");
		
		// set the ambient temperature here
		double  sun_zd = sun->zero_distance;	// square of distance
		double  sun_cr = sun->collision_radius;
		double	alt1 = sun_cr * sun_cr / sun_zd;
		external_temp = SUN_TEMPERATURE * alt1;

		if ((sun != nullptr ? sun->goneNova() : false))
			external_temp *= 100;
		// fuel scooping during the nova mission very unlikely
		if ((sun != nullptr ? sun->willGoNova() : false))
			external_temp *= 3;
			
		// do Revised sun-skimming check here...
		if (hasFuelScoop() && alt1 > 0.75 && getFuel() < fuelCapacity())
		{
			fuel_accumulator += (float)(delta_t * flightSpeed * 0.010 / fuelChargeRate());
			// are we fast enough to collect any fuel?
			scoopsActive = YES && flightSpeed > 0.1f;
			while (fuel_accumulator > 1.0f)
			{
				setFuel(getFuel() + 1);
				fuel_accumulator -= 1.0f;
				doScriptEvent(OOJSID("shipScoopedFuel"));
			}
			if (UNIVERSE != nullptr)  UNIVERSE->displayCountdownMessage(OO_DESC("fuel-scoop-active"), 1.0);
		}
	}
	
	//Bug #11692 CmdrJames added Status entering witchspace
	OOEntityStatus status = this->status();
	if ((status != STATUS_ESCAPE_SEQUENCE) && (status != STATUS_ENTERING_WITCHSPACE))
	{
		UPDATE_STAGE("updating cabin temperature");
		
		// work on the cabin temperature
		float heatInsulation = this->heatInsulation(); // Optimisation, suggested by EricW
		float deltaInsulation = delta_t/heatInsulation;
		float heatThreshold = heatInsulation * 100.0f;
		ship_temperature += (float)( flightSpeed * air_friction * deltaInsulation);	// wind_speed
		
		if (external_temp > heatThreshold && external_temp > ship_temperature)
			ship_temperature += (float)((external_temp - ship_temperature) * SHIP_INSULATION_FACTOR  * deltaInsulation);
		else
		{
			if (ship_temperature > SHIP_MIN_CABIN_TEMP)
				ship_temperature += (float)((external_temp - heatThreshold - ship_temperature) * SHIP_COOLING_FACTOR  * deltaInsulation);
		}
		
		if (ship_temperature > SHIP_MAX_CABIN_TEMP)
			takeHeatDamage(delta_t * ship_temperature);
	}
	
	if ((status == STATUS_ESCAPE_SEQUENCE)&&(shot_time > ESCAPE_SEQUENCE_TIME))
	{
		UPDATE_STAGE("resetting after escape");
		::ShipEntity	*doppelganger = oo::ToShip(foundTarget());
		// reset legal status again! Could have changed if a previously launched missile hit a clean NPC while in the escape pod.
		setBounty(0, kOOLegalStatusReasonEscapePod);
		bounty = 0;
		thrust = max_thrust; // re-enable inertialess drives
		// no access to all player.ship properties while inside the escape pod,
		// we're not supposed to be inside our ship anymore! 
		doScriptEvent(OOJSID("escapePodSequenceOver"));	// allow oxps to override the escape pod target
		/**
		 * This code branch doesn't seem to be used any more - see ~line 6000
		 * Should we remove it? - CIM
		 */
		if (EXPECT_NOT(target_system_id != system_id)) // overridden: we're going to a nearby system!
		{
			system_id = target_system_id;
			info_system_id = target_system_id;
			if (UNIVERSE != nullptr)  UNIVERSE->setSystemTo(system_id);
			galaxy_coordinates = PointFromCoordinates(((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getProperty("coordinates", system_id, galaxy_number) : oo::PList()));
			
			if (UNIVERSE != nullptr)  UNIVERSE->setUpSpace();
			// run initial system population
			if (UNIVERSE != nullptr)  UNIVERSE->populateNormalSpace();

			setDockTarget((UNIVERSE != nullptr ? UNIVERSE->station() : nullptr));
			// send world script events to let oxps know we're in a new system.
			// all player.ship properties are still disabled at this stage.
			if (UNIVERSE != nullptr)  UNIVERSE->setWitchspaceBreakPattern(YES);
			doScriptEvent(OOJSID("shipWillExitWitchspace"));
			doScriptEvent(OOJSID("shipExitedWitchspace"));
			
			if ((UNIVERSE != nullptr ? UNIVERSE->planet() : nullptr) != nullptr)  UNIVERSE->planet()->update(2.34375 * market_rnd);	// from 0..10 minutes
			if ((UNIVERSE != nullptr ? UNIVERSE->station() : nullptr) != nullptr)  UNIVERSE->station()->update(2.34375 * market_rnd);	// from 0..10 minutes
		}
		
		Entity	*dockTargetEntity = (UNIVERSE != nullptr ? UNIVERSE->entityForUniversalID(_dockTarget) : nullptr);	// main station in the original system, unless overridden.
		if (dockTargetEntity != nullptr && dockTargetEntity->getIsStation()) // fails if _dockTarget is NO_TARGET
		{
			if (doppelganger != nullptr)  doppelganger->becomeExplosion();	// blow up the doppelganger
			// restore player ship
			::ShipEntity *player_ship = (UNIVERSE != nullptr ? UNIVERSE->newShipWithName(shipDataKey().value_or("")) : (::ShipEntity *)nil);	// retained
			if (player_ship)
			{
				// FIXME: this should use OOShipType, which should exist. -- Ahruman
				setMesh((player_ship != nullptr ? player_ship->mesh() : (OOMesh *)nullptr));
				if (player_ship != nullptr)  oo::ReleaseEntity(player_ship);						// we only wanted it for its polygons!
			}
			if (UNIVERSE != nullptr)  UNIVERSE->setViewDirection(VIEW_FORWARD);
			if (UNIVERSE != nullptr)  UNIVERSE->setBlockJSPlayerShipProps(NO);	// re-enable player.ship!
			enterDock(oo::ToStation(dockTargetEntity));
		}
		else	// no dock target? dock target is not a station? game over!
		{
			setStatus(STATUS_DEAD);
			//[self playGameOver];	// no death explosion sounds for player pods
			// no shipDied events for player pods, either
			if (UNIVERSE != nullptr)  UNIVERSE->displayMessage(OO_DESC("gameoverscreen-escape-pod"), kDeadResetTime);
			if (UNIVERSE != nullptr)  UNIVERSE->displayMessage("", kDeadResetTime);
			showGameOver();
		}
	}
	
	
	// MOVED THE FOLLOWING FROM PLAYERENTITY POLLFLIGHTCONTROLS:
	travelling_at_hyperspeed = (flightSpeed > maxFlightSpeed);
	if (hyperspeed_engaged)
	{
		UPDATE_STAGE("updating hyperspeed");
		
		// increase speed up to maximum hyperspeed
		if (flightSpeed < maxFlightSpeed * HYPERSPEED_FACTOR)
			flightSpeed += (float)(speed_delta * delta_t * HYPERSPEED_FACTOR);
		if (flightSpeed > maxFlightSpeed * HYPERSPEED_FACTOR)
			flightSpeed = (float)(maxFlightSpeed * HYPERSPEED_FACTOR);
		
		// check for mass lock
		hyperspeed_locked = (massLocked() != NO);
		// check for mass lock & external temperature?
		//hyperspeed_locked = flightSpeed * air_friction > 40.0f+(ship_temperature - external_temp ) * SHIP_COOLING_FACTOR || [self massLocked];
		
		if (hyperspeed_locked)
		{
			playJumpMassLocked();
			if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("jump-mass-locked"), 4.5);
			hyperspeed_engaged = NO;
		}
	}
	else
	{
		if (afterburner_engaged)
		{
			UPDATE_STAGE("updating afterburner");
			
			float abFactor = afterburnerFactor();
			float maxInjectionSpeed = maxFlightSpeed * abFactor;
			if (flightSpeed > maxInjectionSpeed)
			{
				// decellerate to maxInjectionSpeed but slower than without afterburner.
				flightSpeed -= (float)(speed_delta * delta_t * abFactor);
			}
			else
			{
				if (flightSpeed < maxInjectionSpeed)
					flightSpeed += (float)(speed_delta * delta_t * abFactor);
				if (flightSpeed > maxInjectionSpeed)
					flightSpeed = maxInjectionSpeed;
			}
			fuel_accumulator -= (float)(delta_t * afterburner_rate);
			while ((fuel_accumulator < 0)&&(fuel > 0))
			{
				fuel_accumulator += 1.0f;
				if (--fuel <= MIN_FUEL)
					afterburner_engaged = NO;
			}
		}
		else
		{
			UPDATE_STAGE("slowing from hyperspeed");
			
			// slow back down...
			if (travelling_at_hyperspeed)
			{
				// decrease speed to maximum normal speed
				float deceleration = (speed_delta * delta_t * HYPERSPEED_FACTOR);
				if (alertFlags & ALERT_FLAG_MASS_LOCK)
				{
					// decelerate much quicker in masslocks
					// this does also apply to injector deceleration
					// but it's not very noticeable
					deceleration *= 3;
				}
				flightSpeed -= deceleration;
				if (flightSpeed < maxFlightSpeed)
					flightSpeed = maxFlightSpeed;
			}
		}
	}
	
	
	
	// fuel leakage
	if ((fuel_leak_rate > 0.0)&&(fuel > 0))
	{
		UPDATE_STAGE("updating fuel leakage");
		
		fuel_accumulator -= (float)(fuel_leak_rate * delta_t);
		while ((fuel_accumulator < 0)&&(fuel > 0))
		{
			fuel_accumulator += 1.0f;
			fuel--;
		}
		if (fuel == 0)
			fuel_leak_rate = 0;
	}
	
	// smart_zoom
	UPDATE_STAGE("updating scanner zoom");
	if (scanner_zoom_rate)
	{
		double z = (hud != nullptr) ? hud->scannerZoom() : 0.0f;	// a nil HUD answered 0
		double z1 = z + scanner_zoom_rate * delta_t;
		if (scanner_zoom_rate > 0.0)
		{
			if (floor(z1) > floor(z))
			{
				z1 = floor(z1);
				scanner_zoom_rate = 0.0f;
			}
		}
		else
		{
			if (z1 < 1.0)
			{
				z1 = 1.0;
				scanner_zoom_rate = 0.0f;
			}
		}
		if (hud != nullptr)  hud->setScannerZoom(z1);
	}

	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->setFov(fieldOfView, YES);
	
	// scanner sanity check - lose any targets further than maximum scanner range
	Entity *primeTarget = primaryTarget();	// any entity (a wormhole too; the object was typed ShipEntity until bead oo-9ht.144)
	if (primeTarget && HPdistance2(primeTarget->getPosition(), getPosition()) > SCANNER_MAX_RANGE2 && !autopilot_engaged)
	{
		if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("target-lost"), 3.0);
		removeTarget(primeTarget);
	}
	// compass sanity check and update target for changed mode
	validateCompassTarget();
	
	// update subentities
	UPDATE_STAGE("updating subentities");
	totalBoundingBox = boundingBox; //	reset totalBoundingBox
	for (const auto &seRef : getSubEntities())
	{
		Entity *se = seRef.get();
		if (se != nullptr)  se->update(delta_t);
		if (oo::EntityIsShip(se))
		{
			BoundingBox sebb = (oo::ToShip(se) != nullptr ? oo::ToShip(se)->findSubentityBoundingBox() : BoundingBox{});
			bounding_box_add_vector(&totalBoundingBox, sebb.max);
			bounding_box_add_vector(&totalBoundingBox, sebb.min);
		}
	}
	// and one thing which isn't a subentity. Fixes bug with
	// mispositioned laser beams particularly noticeable on side view.
	if (!lastShot.empty())
	{
		for (const oo::Ref<OOLaserShotEntity> &lse : lastShot)
		{
			lse->update(0.0);
		}
		lastShot.clear();
	}
	
	// update mousewheel status
	UPDATE_STAGE("updating mousewheel delta");
	::MyOpenGLView *gView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	float mouseWheelDelta = (gView != nullptr ? gView->mouseWheelDelta() : 0.0f);
	if (mouseWheelDelta > 0.0f)
	{
		if (mouseWheelDelta < delta_t)  { if (gView != nullptr)  gView->setMouseWheelDelta(0.0f); }
		else  { if (gView != nullptr)  gView->setMouseWheelDelta(mouseWheelDelta - delta_t); }
	}
	else if (mouseWheelDelta < 0.0f)
	{
		if (mouseWheelDelta > -delta_t)  { if (gView != nullptr)  gView->setMouseWheelDelta(0.0f); }
		else  { if (gView != nullptr)  gView->setMouseWheelDelta(mouseWheelDelta + delta_t); }
	}
	
	STAGE_TRACKING_END
}


void PlayerEntity::updateMovementFlags()
{
	hasMoved = !HPvector_equal(position, lastPosition);
	hasRotated = !quaternion_equal(orientation, lastOrientation);
	lastPosition = position;
	lastOrientation = orientation;
}



// Slice 8 of docs/phases/3-slices/PlayerEntity.md (bead oo-ijf0s): alert conditions, mass lock, fuel scoops, clocks, script and trumble ticks, the autopilot and docking requests.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

void PlayerEntity::updateAlertConditionForNearbyEntities()
{
	if (!isInSpace() || status() == STATUS_DOCKING)
	{
		clearAlertFlags();
		// not needed while docked
		return;
	}

	int				i, ent_count	= UNIVERSE->n_entities;
	Entity			**uni_entities	= UNIVERSE->sortedEntities;	// grab the public sorted list
	std::vector<Entity *> my_entities(ent_count);	// the C++ entities, their objects retained (bead oo-9ht.39.18)
	Entity			*scannedEntity = nullptr;
	for (i = 0; i < ent_count; i++)
	{
		my_entities[i] = oo::RetainEntity(uni_entities[i]);	// retained
	}
	BOOL massLocked = NO;
	BOOL foundHostiles = NO;
#if OO_VARIABLE_TORUS_SPEED
	BOOL needHyperspeedNearest = YES;
	double hsnDistance = 0;
#endif
	for (i = 0; i < ent_count; i++)  // scanner lollypops
	{
		scannedEntity = my_entities[i];

#if OO_VARIABLE_TORUS_SPEED
		if (EXPECT_NOT(needHyperspeedNearest))
		{
			// not visual effects, waypoints, ships, etc.
			if (scannedEntity != this && scannedEntity->canCollide() && (!oo::EntityIsShip(scannedEntity) || !collisionExceptedFor(oo::ToShip(scannedEntity))))
			{
				hsnDistance = sqrt(scannedEntity->zero_distance)-scannedEntity->collisionRadius();
				needHyperspeedNearest = NO;
			}
		} 
		else if (scannedEntity->isStellarObject())
		{
			// planets, stars might be closest surface even if not
			// closest centre. That could be true of others, but the
			// error is negligible there.
			double thisHSN = sqrt(scannedEntity->zero_distance)-scannedEntity->collisionRadius();
			if (thisHSN < hsnDistance)
			{
				hsnDistance = thisHSN;
			}
		}
#endif
		
		if (scannedEntity->zero_distance < SCANNER_MAX_RANGE2 || !scannedEntity->isShip)
		{
			int theirClass = scannedEntity->getScanClass();
			// here we could also force masslock for higher than yellow alert, but
			// if we are going to hand over masslock control to scripting, might as well
			// hand it over fully
			if (getMassLockable() /*|| alertFlags > ALERT_FLAG_YELLOW_LIMIT*/)
			{
				massLocked |= checkEntityForMassLock(scannedEntity, theirClass);	// we just need one masslocker..
			}
			if (theirClass != CLASS_NO_DRAW)
			{
				if (theirClass == CLASS_THARGOID || OOEntityIsCascadeWeapon(scannedEntity))
				{
					foundHostiles = YES;
				}
				else if (oo::EntityIsShip(scannedEntity))
				{
					::ShipEntity *ship = oo::ToShip(scannedEntity);
					foundHostiles |= (((ship != nullptr ? ship->hasHostileTarget() : false))&&((ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) == this));
				}
			}
		}
	}
#if OO_VARIABLE_TORUS_SPEED
	if (EXPECT_NOT(needHyperspeedNearest))
	{
		// this case should only occur in an otherwise empty
		// interstellar space - unlikely but possible
		hyperspeedFactor = MIN_HYPERSPEED_FACTOR;
	}
	else
	{
		// once nearest object is >4x scanner range
		// start increasing torus speed
		double factor = hsnDistance/(4*SCANNER_MAX_RANGE);
		if (factor < 1.0)
		{
			hyperspeedFactor = MIN_HYPERSPEED_FACTOR;
		}
		else
		{
			hyperspeedFactor = MIN_HYPERSPEED_FACTOR * sqrt(factor);
			if (hyperspeedFactor > MAX_HYPERSPEED_FACTOR)
			{
				// caps out at ~10^8m from nearest object
				// which takes ~10 minutes of flying
				hyperspeedFactor = MAX_HYPERSPEED_FACTOR;
			}
		}
	}
#endif

	setAlertFlag(ALERT_FLAG_MASS_LOCK, massLocked);
		
	setAlertFlag(ALERT_FLAG_HOSTILES, foundHostiles);

	for (i = 0; i < ent_count; i++)
	{
		oo::ReleaseEntity(my_entities[i]);	//	released
	}
	
	BOOL energyCritical = NO;
	if (energy < 64 && energy < maxEnergy * 0.8)
	{
		energyCritical = YES;
	}
	setAlertFlag(ALERT_FLAG_ENERGY, energyCritical);

	setAlertFlag(ALERT_FLAG_TEMP, (hullHeatLevel() > .90));

	setAlertFlag(ALERT_FLAG_ALT, (dialAltitude() < .10));
}


void PlayerEntity::setMaxFlightPitch(GLfloat newValue)
{
	max_flight_pitch = newValue;
	pitch_delta = 2.0 * newValue;
}


void PlayerEntity::setMaxFlightRoll(GLfloat newValue)
{
	max_flight_roll = newValue;
	roll_delta = 2.0 * newValue;
}


void PlayerEntity::setMaxFlightYaw(GLfloat newValue)
{
	max_flight_yaw = newValue;
	yaw_delta = 2.0 * newValue;
}


bool PlayerEntity::checkEntityForMassLock(Entity *ent, int theirClass)
{
	BOOL massLocked = NO;
	BOOL entIsCloakedShip = oo::EntityIsShip(ent) && (oo::ToShip(ent) != nullptr ? oo::ToShip(ent)->isCloaked() : false);
	
	if (EXPECT_NOT(ent->isStellarObject()))
	{
		Entity *stellar = ent;	// a sun or a planet (bead oo-9ht.39.18)
		if (EXPECT(OOStellarBodyPlanetType(stellar) != STELLAR_TYPE_MINIATURE))
		{
			double dist = stellar->zero_distance;
			double rad = stellar->collision_radius;
			double factor = (stellar->isSun()) ? 2.0 : 4.0;
			// plus ensure mass lock when 25 km or less from the surface of small stellar bodies
			// dist is a square distance so it needs to be compared to (rad+25000) * (rad+25000)!
			if (dist < rad*rad*factor || dist < rad*rad + 50000*rad + 625000000 ) 
			{
				massLocked = YES;
			}
		}
	}
	else if (theirClass != CLASS_NO_DRAW)
	{
		if (EXPECT_NOT (entIsCloakedShip))
		{
			theirClass = CLASS_NO_DRAW;
		}
	}

	if (!massLocked && ent->zero_distance <= SCANNER_MAX_RANGE2)
	{
		switch (theirClass)
		{
			case CLASS_NO_DRAW:
				// cloaked ships do mass lock! - Nikos 20200718
				if (entIsCloakedShip && !oo::EntityIsPlayer(ent))
				{
					massLocked = YES;
				}
				break;
			case CLASS_PLAYER:
			case CLASS_BUOY:
			case CLASS_ROCK:
			case CLASS_CARGO:
			case CLASS_MINE:
			case CLASS_VISUAL_EFFECT:
				break;
				
			case CLASS_THARGOID:
			case CLASS_MISSILE:
			case CLASS_STATION:
			case CLASS_POLICE:
			case CLASS_MILITARY:
			case CLASS_WORMHOLE:
			default:
				massLocked = YES;
				break;
		}
	}
	
	return massLocked;
}


void PlayerEntity::updateAlertCondition()
{
	updateAlertConditionForNearbyEntities();
	/*	TODO: update alert condition once per frame. Tried this before, but
		there turned out to be complications. See mailing list archive.
		-- Ahruman 20070802
	 */
	OOAlertCondition cond = getAlertCondition();
	OOTimeAbsolute t = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0);
	if (cond != lastScriptAlertCondition)
	{
		ShipScriptEventNoCx(this, "alertConditionChanged", ooscript::int32Value(cond), ooscript::int32Value(lastScriptAlertCondition));
		lastScriptAlertCondition = cond;
	}
	/* Update heuristic assessment of whether player is fleeing */
	if (cond == ALERT_CONDITION_DOCKED || cond == ALERT_CONDITION_GREEN || (cond == ALERT_CONDITION_YELLOW && energy == maxEnergy))
	{
		fleeing_status = PLAYER_FLEEING_NONE;
	}
	else if (fleeing_status == PLAYER_FLEEING_UNLIKELY && (energy > maxEnergy*0.6 || cond != ALERT_CONDITION_RED))
	{
		fleeing_status = PLAYER_FLEEING_NONE;
	}
	else if ((fleeing_status == PLAYER_FLEEING_MAYBE || fleeing_status == PLAYER_FLEEING_UNLIKELY) && cargo_dump_time > last_shot_time)
	{
		fleeing_status = PLAYER_FLEEING_CARGO;
	}
	else if (fleeing_status == PLAYER_FLEEING_MAYBE && last_shot_time + 10 > t)
	{
		fleeing_status = PLAYER_FLEEING_NONE;
	}
	else if (fleeing_status == PLAYER_FLEEING_LIKELY && last_shot_time + 10 > t)
	{
		fleeing_status = PLAYER_FLEEING_UNLIKELY;
	}
	else if (fleeing_status == PLAYER_FLEEING_NONE && cond == ALERT_CONDITION_RED && last_shot_time + 10 < t && flightSpeed > 0.75*maxFlightSpeed)
	{
		fleeing_status = PLAYER_FLEEING_MAYBE;
	}
	else if ((fleeing_status == PLAYER_FLEEING_MAYBE || fleeing_status == PLAYER_FLEEING_CARGO) && cond == ALERT_CONDITION_RED && last_shot_time + 10 < t && flightSpeed > 0.75*maxFlightSpeed && energy < maxEnergy * 0.5 && (forward_shield < maxForwardShieldLevel()*0.25 || aft_shield < maxAftShieldLevel()*0.25))
	{
		fleeing_status = PLAYER_FLEEING_LIKELY;
	}
}


void PlayerEntity::updateFuelScoops(OOTimeDelta delta_t)
{
	if (scoopsActive)
	{
		updateFuelScoopSoundWithInterval(delta_t);
		if (!getScoopOverride())
		{
			scoopsActive = NO;
			updateFuelScoopSoundWithInterval(delta_t);
		}
	}
}


void PlayerEntity::updateClocks(OOTimeDelta delta_t)
{
	// shot time updates are still needed here for STATUS_DEAD!
	shot_time += delta_t;
	script_time += delta_t;
	unsigned prev_day = floor(ship_clock / 86400);
	ship_clock += delta_t;
	if (ship_clock_adjust > 0.0)				// adjust for coming out of warp (add LY * LY hrs)
	{
		double fine_adjust = delta_t * 7200.0;
		if (ship_clock_adjust > 86400)			// more than a day
			fine_adjust = delta_t * 115200.0;	// 16 times faster
		if (ship_clock_adjust > 0)
		{
			if (fine_adjust > ship_clock_adjust)
				fine_adjust = ship_clock_adjust;
			ship_clock += fine_adjust;
			ship_clock_adjust -= fine_adjust;
		}
		else
		{
			if (fine_adjust < ship_clock_adjust)
				fine_adjust = ship_clock_adjust;
			ship_clock -= fine_adjust;
			ship_clock_adjust += fine_adjust;
		}
	}
	else 
		ship_clock_adjust = 0.0;
	
	unsigned now_day = floor(ship_clock / 86400.0);
	while (prev_day < now_day)
	{
		prev_day++;
		doScriptEvent(OOJSID("dayChanged"), { oo::PList::unsignedInteger(prev_day) });
		// not impossible that at ultra-low frame rates two of these will
		// happen in a single update.
	}

	//fps
	if (ship_clock > fps_check_time)
	{
		if (!clockAdjusting())
		{
			fps_counter = (int)((UNIVERSE != nullptr ? UNIVERSE->getTimeAccelerationFactor() : 0.0) * floor((UNIVERSE != nullptr ? UNIVERSE->getFramesDoneThisUpdate() : 0) / (fps_check_time - last_fps_check_time)));
			last_fps_check_time = fps_check_time;
			fps_check_time = ship_clock + MINIMUM_GAME_TICK;
		}
		else
		{
			// Good approximation for when the clock is adjusting and proper fps calculation
			// cannot be performed.
			fps_counter = (int)((UNIVERSE != nullptr ? UNIVERSE->getTimeAccelerationFactor() : 0.0) * floor(1.0 / delta_t));
			fps_check_time = ship_clock + MINIMUM_GAME_TICK;
		}
		if (UNIVERSE != nullptr)  UNIVERSE->resetFramesDoneThisUpdate();	// Reset frame counter
	}
}


void PlayerEntity::checkScriptsIfAppropriate()
{
	if (script_time <= script_time_check)  return;
	
	if (status() != STATUS_IN_FLIGHT)
	{
		switch (gui_screen)
		{
			// Screens where no world script tickles are performed
			case GUI_SCREEN_MAIN:
			case GUI_SCREEN_INTRO1:
			case GUI_SCREEN_SHIPLIBRARY:
			case GUI_SCREEN_KEYBOARD:
			case GUI_SCREEN_NEWGAME:
			case GUI_SCREEN_OXZMANAGER:
			case GUI_SCREEN_MARKET:
			case GUI_SCREEN_MARKETINFO:
			case GUI_SCREEN_OPTIONS:
			case GUI_SCREEN_GAMEOPTIONS:
			case GUI_SCREEN_LOAD:
			case GUI_SCREEN_SAVE:
			case GUI_SCREEN_SAVE_OVERWRITE:
			case GUI_SCREEN_STICKMAPPER:
			case GUI_SCREEN_STICKPROFILE:
			case GUI_SCREEN_MISSION:
			case GUI_SCREEN_REPORT:
			case GUI_SCREEN_KEYBOARD_CONFIRMCLEAR:
			case GUI_SCREEN_KEYBOARD_CONFIG:
			case GUI_SCREEN_KEYBOARD_ENTRY:
			case GUI_SCREEN_KEYBOARD_LAYOUT:
				return;
			
			// Screens from which it's safe to jump to the mission screen
//			case GUI_SCREEN_CONTRACTS:
			case GUI_SCREEN_EQUIP_SHIP:
			case GUI_SCREEN_INTERFACES:
			case GUI_SCREEN_MANIFEST:
			case GUI_SCREEN_SHIPYARD:
			case GUI_SCREEN_LONG_RANGE_CHART:
			case GUI_SCREEN_SHORT_RANGE_CHART:
			case GUI_SCREEN_STATUS:
			case GUI_SCREEN_SYSTEM_DATA:
				// Test passed, we can run scripts. Nothing to do here.
				break;
		}
	}
	
	// Test either passed or never ran, run scripts.
	checkScript();
	script_time_check += script_time_interval;
}


void PlayerEntity::updateTrumbles(OOTimeDelta delta_t)
{
	oo::Ref<OOTrumble> *trumbles = trumbleArray();
	NSUInteger	i;
	
	for (i = getTrumbleCount() ; i > 0; i--)
	{
		oo::Ref<OOTrumble> trum = trumbles[i - 1];
		trum->updateTrumble(delta_t);
	}
}


void PlayerEntity::performAutopilotUpdates(OOTimeDelta delta_t)
{
	processBehaviour(delta_t);
	applyVelocity(delta_t);
	doBookkeeping(delta_t);
}


void PlayerEntity::performDockingRequest(::StationEntity *stationForDocking)
{
	if (stationForDocking == nil) return;
	if (!(stationForDocking != nullptr ? stationForDocking->getIsStation() : false)) return;	// a StationEntity (-isKindOfClass:) by its type since bead oo-9ht.175
	if (isDocked())  return;
	if (autopilot_engaged && targetStation() == stationForDocking)	return;
	if (autopilot_engaged && targetStation() != stationForDocking)
	{
		disengageAutopilot();
	}
	const std::optional<std::string> stationDockingClearanceStatus = (stationForDocking != nullptr ? stationForDocking->acceptDockingClearanceRequestFrom(this) : std::optional<std::string>());
	if (stationDockingClearanceStatus.has_value())
	{
		doScriptEvent(OOJSID("playerRequestedDockingClearance"), { oo::PList(*stationDockingClearanceStatus) });
		if (*stationDockingClearanceStatus == "DOCKING_CLEARANCE_GRANTED") 
		{
			doScriptEvent(OOJSID("playerDockingClearanceGranted"));
		}
	} 
}


void PlayerEntity::requestDockingClearance(::StationEntity *stationForDocking)
{
	if (dockingClearanceStatus != DOCKING_CLEARANCE_STATUS_REQUESTED && dockingClearanceStatus != DOCKING_CLEARANCE_STATUS_GRANTED)
	{
		performDockingRequest(stationForDocking);
	}
}


void PlayerEntity::cancelDockingRequest(::StationEntity *stationForDocking)
{
	if (stationForDocking == nil) return;
	if (!(stationForDocking != nullptr ? stationForDocking->getIsStation() : false)) return;	// a StationEntity (-isKindOfClass:) by its type since bead oo-9ht.175
	if (isDocked())  return;
	if (autopilot_engaged && targetStation() == stationForDocking)	return;
	if (autopilot_engaged && targetStation() != stationForDocking)
	{
		disengageAutopilot();
	}
	if (dockingClearanceStatus == DOCKING_CLEARANCE_STATUS_GRANTED || dockingClearanceStatus == DOCKING_CLEARANCE_STATUS_REQUESTED)
	{
		const std::optional<std::string> stationDockingClearanceStatus = (stationForDocking != nullptr ? stationForDocking->acceptDockingClearanceRequestFrom(this) : std::optional<std::string>());
		if (stationDockingClearanceStatus == "DOCKING_CLEARANCE_CANCELLED")
		{
			doScriptEvent(OOJSID("playerDockingClearanceCancelled"));
		} 
	}
}


bool PlayerEntity::engageAutopilotToStation(::StationEntity *stationForDocking)
{
	if (stationForDocking == nil)   return NO;
	if (isDocked())  return NO;
	
	if (autopilot_engaged && targetStation() == stationForDocking)
	{	
		return YES;
	}
		
	setTargetStation(stationForDocking);
	_primaryTarget = nullptr;
	autopilot_engaged = YES;
	ident_engaged = NO;
	safeAllMissiles();
	velocity = kZeroVector;
	if (status() == STATUS_WITCHSPACE_COUNTDOWN) cancelWitchspaceCountdown(); // cancel witchspace countdown properly
	setStatus(STATUS_AUTOPILOT_ENGAGED);
	resetAutopilotAI();
	if (shipAI != nullptr)  shipAI->setState("BEGIN_DOCKING");	// reboot the AI
	playAutopilotOn();
	OOMusicController::sharedController()->playDockingMusic();
	doScriptEvent(OOJSID("playerStartedAutoPilot"), stationForDocking);
	setDockingClearanceStatus(DOCKING_CLEARANCE_STATUS_GRANTED);
		
	if (afterburner_engaged)
	{
		afterburner_engaged = NO;
		if (afterburnerSoundLooping)  stopAfterburnerSound();
	}
	return YES;
}


void PlayerEntity::disengageAutopilot()
{
	if (autopilot_engaged)
	{
		abortDocking();			// let the station know that you are no longer on approach
		behaviour = BEHAVIOUR_IDLE;
		frustration = 0.0;
		autopilot_engaged = NO;
		_primaryTarget = nullptr;
		setTargetStation(nullptr);
		setStatus(STATUS_IN_FLIGHT);
		playAutopilotOff();
		setDockingClearanceStatus(DOCKING_CLEARANCE_STATUS_NONE);
		OOMusicController::sharedController()->stopDockingMusic();
		doScriptEvent(OOJSID("playerCancelledAutoPilot"));
		
		resetAutopilotAI();
	}
}



// Slice 9 of docs/phases/3-slices/PlayerEntity.md (bead oo-qyjcv): the autopilot AI, hyperspeed, in-flight / witchspace / launch / docking / dead updates, game over, the ship model view, targeting.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

void PlayerEntity::resetAutopilotAI()
{
	::AI *myAI = getAI();
	// JSAI: will need changing if oolite-dockingAI.js written
	if ((myAI != nullptr ? myAI->name() : std::optional<std::string>()) != std::string(PLAYER_DOCKING_AI_NAME))	// (no AI never matched)
	{
		setAITo(std::string(PLAYER_DOCKING_AI_NAME));
	}
	if (myAI != nullptr)  myAI->clearAllData();
	if (myAI != nullptr)  myAI->setState("GLOBAL");
	if (myAI != nullptr)  myAI->setNextThinkTime((UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) + 2);
	if (myAI != nullptr)  myAI->setOwner(this);
}


#if OO_VARIABLE_TORUS_SPEED
GLfloat PlayerEntity::getHyperspeedFactor()
{
	return hyperspeedFactor;
}
#endif


bool PlayerEntity::injectorsEngaged()
{
	return afterburner_engaged;
}


bool PlayerEntity::hyperspeedEngaged()
{
	return hyperspeed_engaged;
}


void PlayerEntity::performInFlightUpdates(OOTimeDelta delta_t)
{
	STAGE_TRACKING_BEGIN
	
	// do flight routines
	//// velocity stuff
	UPDATE_STAGE("applying newtonian drift");
	assert(VELOCITY_CLEANUP_FULL > VELOCITY_CLEANUP_MIN);
	
	applyVelocity(delta_t);
	
	GLfloat thrust_factor = 1.0;
	if (flightSpeed > maxFlightSpeed)
	{
		if (afterburner_engaged)
		{
			thrust_factor = afterburnerFactor();
		}
		else
		{
			thrust_factor = HYPERSPEED_FACTOR;
		}
	}
	

	GLfloat velmag = magnitude(velocity);
	GLfloat velmag2 = velmag - (float)delta_t * thrust * thrust_factor;
	if (velmag > 0)
	{
		UPDATE_STAGE("applying power braking");
		
		if (velmag > VELOCITY_CLEANUP_MIN)
		{
			GLfloat rate;
			// Fix up extremely ridiculous speeds that can happen in collisions or explosions
			if (velmag > VELOCITY_CLEANUP_FULL)  rate = VELOCITY_CLEANUP_RATE;
			else  rate = (velmag - VELOCITY_CLEANUP_MIN) / (VELOCITY_CLEANUP_FULL - VELOCITY_CLEANUP_MIN) * VELOCITY_CLEANUP_RATE;
			velmag2 -= velmag * rate;
		}
		if (velmag2 < 0.0f)  velocity = kZeroVector;
		else  velocity = vector_multiply_scalar(velocity, velmag2 / velmag);
		
	}
	
	UPDATE_STAGE("updating joystick");
	applyRoll((float)delta_t*flightRoll, (float)delta_t*flightPitch);
	if (flightYaw != 0.0)
	{
		applyYaw((float)delta_t*flightYaw);
	}
	
	UPDATE_STAGE("applying para-newtonian thrust");
	moveForward(delta_t*flightSpeed);
	
	UPDATE_STAGE("updating targeting");
	updateTargeting();
	
	STAGE_TRACKING_END
}


void PlayerEntity::performWitchspaceCountdownUpdates(OOTimeDelta delta_t)
{
	STAGE_TRACKING_BEGIN
	
	UPDATE_STAGE("doing bookkeeping");
	doBookkeeping(delta_t);
	
	UPDATE_STAGE("updating countdown timer");
	witchspaceCountdown = fdim(witchspaceCountdown, delta_t);
	
	// damaged gal drive? abort!
	/* TODO: this check should possibly be hasEquipmentItemProviding:,
	 * but if it was we'd need to know which item was actually doing
	 * the providing so it could be removed. */
	if (EXPECT_NOT(galactic_witchjump && !hasEquipmentItem(oo::PList("EQ_GAL_DRIVE"))))
	{
		galactic_witchjump = NO;
		setStatus(STATUS_IN_FLIGHT);
		playHyperspaceAborted();
		ShipScriptEventNoCx(this, "playerJumpFailed", OOJSSTR("malfunction"));
		return;
	}
	
	int seconds = round(witchspaceCountdown);
	if (galactic_witchjump)
	{
		if (UNIVERSE != nullptr)  UNIVERSE->displayCountdownMessage(cxx_OOExpandKey("witch-galactic-in-x-seconds", seconds), 1.0);
	}
	else
	{
		const std::string destination = (UNIVERSE != nullptr ? UNIVERSE->getSystemName(nextHopTargetSystemID()) : std::optional<std::string>()).value_or(std::string());	// (nil raised in the expansion)
		if (UNIVERSE != nullptr)  UNIVERSE->displayCountdownMessage(ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "witch-to-x-in-y-seconds", { { "seconds", oo::PList::signedInteger(seconds) }, { "destination", oo::PList(destination) } }), 1.0);
	}
	
	if (witchspaceCountdown == 0.0)
	{
		UPDATE_STAGE("preloading planet textures");
		if (!galactic_witchjump)
		{
			/*	Note: planet texture preloading is done twice for hyperspace jumps:
				once when starting the countdown and once at the beginning of the
				jump. The reason is that the preloading may have been skipped the
				first time because of rate limiting (see notes at
				-preloadPlanetTexturesForSystem:). There is no significant overhead
				from doing it twice thanks to the texture cache.
				-- Ahruman 2009-12-19
			*/
			if (UNIVERSE != nullptr)  UNIVERSE->preloadPlanetTexturesForSystem(target_system_id);
		}
		else
		{
			// FIXME: preload target system for galactic jump?
		}

		UPDATE_STAGE("JUMP!");
		if (galactic_witchjump)  enterGalacticWitchspace();
		else  enterWitchspace();
		galactic_witchjump = NO;
	}
	
	STAGE_TRACKING_END
}


void PlayerEntity::performWitchspaceExitUpdates(OOTimeDelta delta_t)
{
	if ((UNIVERSE != nullptr ? UNIVERSE->breakPatternOver() : false))
	{
		resetExhaustPlumes();
		// time to check the script!
		checkScript();
		// next check in 10s
		resetScriptTimer();	// reset the in-system timer
		
		// announce arrival
		if ((UNIVERSE != nullptr && UNIVERSE->planet() != nullptr))
		{
			if (UNIVERSE != nullptr)  UNIVERSE->addMessage(oo::str::format(" %s. ", (UNIVERSE != nullptr ? UNIVERSE->getSystemName(system_id) : std::optional<std::string>()).value_or("(null)").c_str()), 3.0);
			// and reset the compass
			if (hasEquipmentItemProviding("EQ_ADVANCED_COMPASS"))
				compassMode = COMPASS_MODE_PLANET;
			else
				compassMode = COMPASS_MODE_BASIC;
		}
		else
		{
			if ((UNIVERSE != nullptr ? UNIVERSE->inInterstellarSpace() : false))  { if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("witch-engine-malfunction"), 3.0); } // if sun gone nova, print nothing
		}
		
		setStatus(STATUS_IN_FLIGHT);
		
		// If we are exiting witchspace after a scripted misjump. then make sure it gets reset now.
		// Scripted misjump situations should have a lifespan of one jump only, to keep things
		// simple - Nikos 20090728
		if (scriptedMisjump())  setScriptedMisjump(NO);
		// similarly reset the misjump range to the traditional 0.5
		setScriptedMisjumpRange(0.5);

		const std::optional<std::string> jumpCause = this->jumpCause();
		doScriptEvent(OOJSID("shipExitedWitchspace"), { jumpCause.has_value() ? oo::PList(*jumpCause) : oo::PList() });

		doBookkeeping(delta_t); // arrival frame updates

		suppressAegisMessages=NO;
	}
}


void PlayerEntity::performLaunchingUpdates(OOTimeDelta delta_t)
{
	if (!(UNIVERSE != nullptr ? UNIVERSE->breakPatternHide() : false))
	{
		flightRoll = launchRoll;	// synchronise player's & launching station's spins.
		doBookkeeping(delta_t);	// don't show ghost exhaust plumes from previous docking!
	}
	
	if ((UNIVERSE != nullptr ? UNIVERSE->breakPatternOver() : false))
	{
		// time to check the legacy scripts!
		checkScript();
		// next check in 10s
		
		setStatus(STATUS_IN_FLIGHT);

		setDockingClearanceStatus(DOCKING_CLEARANCE_STATUS_NONE);
		::StationEntity *stationLaunchedFrom = oo::ToStation((UNIVERSE != nullptr ? UNIVERSE->nearestEntityMatchingPredicate(IsStationPredicate, NULL, this) : nullptr));
		doScriptEvent(OOJSID("shipLaunchedFromStation"), stationLaunchedFrom);
	}
}


void PlayerEntity::performDockingUpdates(OOTimeDelta /*delta_t*/)
{
	if ((UNIVERSE != nullptr ? UNIVERSE->breakPatternOver() : false))
	{
		docked();		// bookkeeping for docking
	}

  	// if cloak or ecm visual effects are playing while docking, terminate them
	if (UNIVERSE != nullptr)  UNIVERSE->terminatePostFX(OO_POSTFX_CLOAK);
	if ((UNIVERSE != nullptr ? UNIVERSE->getECMVisualFXEnabled() : false))  { if (UNIVERSE != nullptr)  UNIVERSE->terminatePostFX(OO_POSTFX_CRTBADSIGNAL); }
}


void PlayerEntity::performDeadUpdates(OOTimeDelta /*delta_t*/)
{
	if (UNIVERSE != nullptr)  UNIVERSE->terminatePostFX(OO_POSTFX_CLOAK);
	if ((UNIVERSE != nullptr ? UNIVERSE->getECMVisualFXEnabled() : false))  { if (UNIVERSE != nullptr)  UNIVERSE->terminatePostFX(OO_POSTFX_CRTBADSIGNAL); }
 	
	gameOverFadeToBW();
	
	if (shotTime() > kDeadResetTime)
	{
		BOOL was_mouse_control_on = mouse_control_on;
		if (UNIVERSE != nullptr)  UNIVERSE->handleGameOver();				//  we restart the UNIVERSE
		mouse_control_on = (was_mouse_control_on != NO);
	}
}


void PlayerEntity::gameOverFadeToBW()
{
	const oo::PList fadeOut = oo::Defaults::standard().object("gameover-seconds-to-bw-fadeout");
	float secondsToBWFadeOut = oo::PListGet<float>::from(fadeOut.isNull() ? nullptr : &fadeOut, 5.0f);
	if ((UNIVERSE != nullptr ? UNIVERSE->getDetailLevel() : OOGraphicsDetail{}) >= DETAIL_LEVEL_SHADERS && secondsToBWFadeOut > 0.0f)
	{
		::MyOpenGLView *gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
		static float originalColorSaturation = -1.0f;
		if (originalColorSaturation == -1.0f)  originalColorSaturation = (gameView != nullptr ? gameView->colorSaturation() : 0.0f);
		if (shotTime() < secondsToBWFadeOut)
		{
			// fade to black & white within secondsToBWFadeOut, independently of
			// frame rate and original color saturation
			if (fps_counter != 0)
			{
				if (gameView != nullptr)  gameView->adjustColorSaturation(-(originalColorSaturation * (1.0f / secondsToBWFadeOut) * (UNIVERSE != nullptr ? UNIVERSE->getTimeAccelerationFactor() : 0.0) / fps_counter));
			}
		}
		
		if (shotTime() > kDeadResetTime)
		{
			// make sure to subtract the current saturation because if the user presses space to skip
			// the game over screen before the transition to b/w has been completed, whatever is left
			// will be added to the original saturation, resulting in an oversaturated image
			if (gameView != nullptr)  gameView->adjustColorSaturation(originalColorSaturation - (gameView != nullptr ? gameView->colorSaturation() : 0.0f));
			originalColorSaturation = -1.0f;
		}
	}
}


// Target is valid if it's within Scanner range, AND
// Target is a ship AND is not cloaked or jamming, OR
// Target is a wormhole AND player has the Wormhole Scanner
bool PlayerEntity::isValidTarget(Entity *target)	// the C++ entity since bead oo-9ht.39.23
{
	// Just in case we got called with a bad target.
	if (!target)
		return NO;

	// If target is beyond scanner range, it's lost
	if(target->zero_distance > SCANNER_MAX_RANGE2)
		return NO;

	// If target is a ship, check whether it's cloaked or is actively jamming our scanner
	if (target->getIsShip())
	{
		::ShipEntity *targetShip = oo::ToShip(target);
		if ((targetShip != nullptr ? targetShip->isCloaked() : false) ||	// checks for cloaked ships
			((targetShip != nullptr ? targetShip->isJammingScanning() : false) && !hasMilitaryScannerFilter()))	// checks for activated jammer
		{
			return NO;
		}
		OOEntityStatus tstatus = (targetShip != nullptr ? targetShip->status() : OOEntityStatus{});
		if (tstatus == STATUS_ENTERING_WITCHSPACE || tstatus == STATUS_IN_HOLD || tstatus == STATUS_DOCKED)
		{ // checks for ships entering wormholes, docking, or been scooped
			return NO;
		}
		return YES;
	}

	// If target is an unexpired wormhole and the player has bought the Wormhole Scanner and we're in ID mode
	if (target->getIsWormhole() && target->getScanClass() != CLASS_NO_DRAW && 
		hasEquipmentItemProviding("EQ_WORMHOLE_SCANNER") && ident_engaged)
	{
		return YES;
	}
	
	// Target is neither a wormhole nor a ship
	return NO;
}


void PlayerEntity::showGameOver()
{
	if (hud != nullptr)  hud->resetGuis(oo::PList(oo::PList::Dict{ { "message_gui", oo::PList(oo::PList::Dict()) } }));
	const std::string scoreMS = oo::str::formatRuntime(cxx_OOExpandKey("gameoverscreen-score-@").value_or(std::string()),
							{ cxx_KillCountToRatingAndKillString(ship_kills) });
	
	if (UNIVERSE != nullptr)  UNIVERSE->displayMessage(cxx_OOExpandKey("gameoverscreen-game-over"), kDeadResetTime);
	if (UNIVERSE != nullptr)  UNIVERSE->displayMessage("", kDeadResetTime);
	if (UNIVERSE != nullptr)  UNIVERSE->displayMessage(scoreMS, kDeadResetTime);
	if (UNIVERSE != nullptr)  UNIVERSE->displayMessage("", kDeadResetTime);
	if (UNIVERSE != nullptr)  UNIVERSE->displayMessage(cxx_OOExpandKey("gameoverscreen-press-space"), kDeadResetTime);
	if (UNIVERSE != nullptr)  UNIVERSE->displayMessage(" ", kDeadResetTime);
	if (UNIVERSE != nullptr)  UNIVERSE->displayMessage("", kDeadResetTime);
	resetShotTime();
}


void PlayerEntity::showShipModelWithKey(const std::string &shipKey, const oo::PList &shipDataIn, uint16_t personality, GLfloat factorX, GLfloat factorY, GLfloat factorZ, const std::optional<std::string> &context)
{
	// (a nil key returns in the bridged -showShipModelWithKey:...)
	const oo::PList shipData = shipDataIn.isNull() ? OOShipRegistry::sharedRegistry()->shipInfoForKey(shipKey) : shipDataIn;
	if (shipData.isNull())  return;
	
	Quaternion		q2 = { (GLfloat)M_SQRT1_2, (GLfloat)M_SQRT1_2, (GLfloat)0.0f, (GLfloat)0.0f };
	// MKW - retrieve last demo ships' orientation and release it
	if( demoShip )
	{
		q2 = demoShip->getOrientation();
		demoShip = nullptr;
	}
	
	::ShipEntity *ship = ::ProxyPlayerEntity::newProxyObject(shipKey, shipData);	// [[ProxyPlayerEntity alloc] cxx_initWithKey:definition:] until bead oo-9ht.183
	if (personality != ENTITY_PERSONALITY_INVALID)  { if (ship != nullptr)  ship->setEntityPersonalityInt(personality); }
	
	if (ship != nullptr)  ship->wasAddedToUniverse();
	
	if (context.has_value())  OO_LOG("script.debug.note.showShipModel", "::::: showShipModel:'{}' in context: {}.", (ship != nullptr ? ship->getName() : std::optional<std::string>()).value_or("(null)"), *context);
	
	GLfloat cr = (ship != nullptr ? ship->collisionRadius() : 0.0f);
	if (ship != nullptr)  ship->setOrientation(q2);
	if (ship != nullptr)  ship->setPositionX(factorX * cr, factorY * cr, factorZ * cr);
	if (ship != nullptr)  ship->setScanClass(CLASS_NO_DRAW);
	if (ship != nullptr)  ship->setDemoShip(0.6);
	if (ship != nullptr)  ship->setDemoStartTime((UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0));
	if((ship != nullptr ? ship->pendingEscortCount() : uint8_t{}) > 0) { if (ship != nullptr)  ship->setPendingEscortCount(0); }
	if (ship != nullptr)  ship->setAITo("nullAI.plist");
	const oo::PList *subEntStatus = shipData.find("subentities_status");
	// show missing subentities if there's a subentities_status key
	if (subEntStatus != nullptr) { if (ship != nullptr)  ship->deserializeShipSubEntitiesFrom(oo::PListGet<std::string>::from(subEntStatus, std::string())); }
	if (UNIVERSE != nullptr)  UNIVERSE->addEntity(ship);
	// MKW - save demo ship for its rotation
	demoShip = oo::EntityHold(ship);
	
	if (ship != nullptr)  ship->setStatus(STATUS_COCKPIT_DISPLAY);
	
	if (ship != nullptr)  oo::ReleaseEntity(ship);
}


// Check for lost targeting - both on the ships' main target as well as each
// missile.
// If we're actively scanning and we don't have a current target, then check
// to see if we've locked onto a new target.
// Finally, if we have a target and it's a wormhole, check whether we have more
// information
void PlayerEntity::updateTargeting()
{
	STAGE_TRACKING_BEGIN
	
	// check for lost ident target and ensure the ident system is actually scanning
	UPDATE_STAGE("checking ident target");
	if (ident_engaged && primaryTarget() != nil)
	{
		if (!isValidTarget(primaryTarget()))
		{
			if (!suppressTargetLostFlag)
			{
				if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("target-lost"), 3.0);
				playTargetLost();
				noteLostTarget();
			}
			else
			{
				suppressTargetLostFlag = NO;
			}

			_primaryTarget = nullptr;
		}
	}

	// check each unlaunched missile's target still exists and is in-range
	UPDATE_STAGE("checking missile targets");
	if (missile_status != MISSILE_STATUS_SAFE)
	{
		unsigned i;
		for (i = 0; i < max_missiles; i++)
		{
			if ((oo::ToShip(missile_entity[i].get()) != nullptr ? oo::ToShip(missile_entity[i].get())->primaryTarget() : (Entity *)nullptr) != nil &&
					!isValidTarget((oo::ToShip(missile_entity[i].get()) != nullptr ? oo::ToShip(missile_entity[i].get())->primaryTarget() : (Entity *)nullptr)))
			{
				if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("target-lost"), 3.0);
				playTargetLost();
				if (oo::ToShip(missile_entity[i].get()) != nullptr)  oo::ToShip(missile_entity[i].get())->removeTarget(nullptr);
				if (i == activeMissile)
				{
					noteLostTarget();
					_primaryTarget = nullptr;
					missile_status = MISSILE_STATUS_ARMED;
				}
			} else if (i == activeMissile && (oo::ToShip(missile_entity[i].get()) != nullptr ? oo::ToShip(missile_entity[i].get())->primaryTarget() : (Entity *)nullptr) == nil) {
				missile_status = MISSILE_STATUS_ARMED;
			}
		}
	}

	// if we don't have a primary target, and we're scanning, then check for a new
	// target to lock on to
	UPDATE_STAGE("looking for new target");
	if (primaryTarget() == nil && 
			(ident_engaged || missile_status != MISSILE_STATUS_SAFE) &&
			(status() == STATUS_IN_FLIGHT || status() == STATUS_WITCHSPACE_COUNTDOWN))
	{
		Entity *target = (UNIVERSE != nullptr ? UNIVERSE->firstEntityTargetedByPlayer() : nullptr);
		if (isValidTarget(target))
		{
			addTarget(target);
		}
	}
	
	// If our primary target is a wormhole, check to see if we have additional
	// information
	UPDATE_STAGE("checking for additional wormhole information");
	if ((primaryTarget() != nullptr && primaryTarget()->getIsWormhole()))
	{
		WormholeEntity *wh = static_cast<WormholeEntity *>(primaryTarget());	// -isWormhole
		switch ((wh != nullptr ? wh->scanInfo() : WORMHOLE_SCANINFO{}))
		{
			case WH_SCANINFO_NONE:
				OO_LOG(cxx_kOOLogInconsistentState, "{}", "Internal Error - WH_SCANINFO_NONE reached in [PlayerEntity updateTargeting:]");
				dumpState();
				if (wh != nullptr)  wh->dumpState();
				// Workaround a reported hit of the assert here.  We really
				// should work out how/why this could happen though and fix
				// the underlying cause.
				// - MKW 2011.03.11
				//assert([wh scanInfo] != WH_SCANINFO_NONE);
				if (wh != nullptr)  wh->setScannedAt(clockTimeAdjusted());
				break;
			case WH_SCANINFO_SCANNED:
				if (clockTimeAdjusted() > (wh != nullptr ? wh->scanTime() : 0.0) + 2)
				{
					if (wh != nullptr)  wh->setScanInfo(WH_SCANINFO_COLLAPSE_TIME);
					//[UNIVERSE cxx_addCommsMessage:oo::str::formatRuntime(OO_DESC("wormhole-collapse-time-computed"),
					//						   { [UNIVERSE cxx_getSystemName:[wh destination]].value_or(std::string()) }) forCount:5.0];
				}
				break;
			case WH_SCANINFO_COLLAPSE_TIME:
				if(clockTimeAdjusted() > (wh != nullptr ? wh->scanTime() : 0.0) + 4)
				{
					if (wh != nullptr)  wh->setScanInfo(WH_SCANINFO_ARRIVAL_TIME);
					if (UNIVERSE != nullptr)
					{
						const std::string arrivalFormat = OO_DESC("wormhole-arrival-time-computed-@");	// the format first, as Clang evaluates the arguments: a description that is an array draws (ADR-0063 item 5)
						UNIVERSE->addCommsMessage(oo::str::formatRuntime(arrivalFormat, { cxx_ClockToString((wh != nullptr ? wh->estimatedArrivalTime() : 0.0), NO) }), 5.0);
					}
				}
				break;
			case WH_SCANINFO_ARRIVAL_TIME:
				if (clockTimeAdjusted() > (wh != nullptr ? wh->scanTime() : 0.0) + 7)
				{
					if (wh != nullptr)  wh->setScanInfo(WH_SCANINFO_DESTINATION);
					if (UNIVERSE != nullptr)  UNIVERSE->addCommsMessage(oo::str::formatRuntime(OO_DESC("wormhole-destination-computed-@"), { (UNIVERSE != nullptr ? UNIVERSE->getSystemName((wh != nullptr ? wh->getDestination() : 0)) : std::optional<std::string>()).value_or("(null)") }), 5.0);
				}
				break;
			case WH_SCANINFO_DESTINATION:
				if (clockTimeAdjusted() > (wh != nullptr ? wh->scanTime() : 0.0) + 10)
				{
					if (wh != nullptr)  wh->setScanInfo(WH_SCANINFO_SHIP);
					// TODO: Extract last ship from wormhole and display its name
				}
				break;
			case WH_SCANINFO_SHIP:
				break;
		}
	}
	
	STAGE_TRACKING_END
}



// Slice 10 of docs/phases/3-slices/PlayerEntity.md (bead oo-9u9w6): attitude, view matrices and viewpoints, drawing, mass lock, the docked station, the HUD and its custom dials, shield levels.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

void PlayerEntity::orientationChanged()
{
	quaternion_normalize(&orientation);
	rotMatrix = OOMatrixForQuaternionRotation(orientation);
	OOMatrixGetBasisVectors(rotMatrix, &v_right, &v_up, &v_forward);
	
	orientation.w = -orientation.w;
	playerRotMatrix = OOMatrixForQuaternionRotation(orientation);	// this is the rotation similar to ordinary ships
	orientation.w = -orientation.w;
}


void PlayerEntity::applyAttitudeChanges(double delta_t)
{
	applyRoll(flightRoll*delta_t, flightPitch*delta_t);
	applyYaw(flightYaw*delta_t);
}


void PlayerEntity::applyRoll(GLfloat roll1, GLfloat climb1)
{
	if (roll1 == 0.0 && climb1 == 0.0 && hasRotated == NO)
		return;

	if (roll1)
		quaternion_rotate_about_z(&orientation, -roll1);
	if (climb1)
		quaternion_rotate_about_x(&orientation, -climb1);
	
	/*	Bugginess may put us in a state where the orientation quat is all
		zeros, at which point it’s impossible to move.
	*/
	if (EXPECT_NOT(quaternion_equal(orientation, kZeroQuaternion)))
	{
		if (!quaternion_equal(lastOrientation, kZeroQuaternion))
		{
			orientation = lastOrientation;
		}
		else
		{
			orientation = kIdentityQuaternion;
		}
	}
	
	orientationChanged();
}


/*
 * This method should not be necessary, but when I replaced the above with applyRoll:andClimb:andYaw, the
 * ship went crazy. Perhaps applyRoll:andClimb is called from one of the subclasses and that was messing
 * things up.
 */
void PlayerEntity::applyYaw(GLfloat yaw)
{
	quaternion_rotate_about_y(&orientation, -yaw);
	
	orientationChanged();
}


OOMatrix PlayerEntity::drawRotationMatrix()
{
	return playerRotMatrix;
}


OOMatrix PlayerEntity::drawTransformationMatrix()
{
	OOMatrix result = playerRotMatrix;
	// HPVect: modify to use camera-relative positioning
	return OOMatrixTranslate(result, HPVectorToVector(position));
}


Quaternion PlayerEntity::normalOrientation()
{
	return make_quaternion(-orientation.w, orientation.x, orientation.y, orientation.z);
}


void PlayerEntity::setNormalOrientation(Quaternion quat)
{
	setOrientation(make_quaternion(-quat.w, quat.x, quat.y, quat.z));
}


void PlayerEntity::moveForward(double amount)
{
	distanceTravelled += (float)amount;
	setPosition(HPvector_add(position, vectorToHPVector(vector_multiply_scalar(v_forward, (float)amount))));
}


HPVector PlayerEntity::breakPatternPosition()
{
	return HPvector_add(position,vectorToHPVector(quaternion_rotate_vector(quaternion_conjugate(orientation),forwardViewOffset)));
}


Vector PlayerEntity::viewpointOffset()
{
//	if ([UNIVERSE breakPatternHide])
//		return kZeroVector;	// center view for break pattern
	// now done by positioning break pattern correctly

	switch ((UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{}))
	{
		case VIEW_FORWARD:
			return forwardViewOffset;
		case VIEW_AFT:
			return aftViewOffset;
		case VIEW_PORT:
			return portViewOffset;
		case VIEW_STARBOARD:
			return starboardViewOffset;
		/* GILES custom viewpoints */
		case VIEW_CUSTOM:
			return customViewOffset;
		/* -- */
		
		default:
			break;
	}

	return kZeroVector;
}


Vector PlayerEntity::viewpointOffsetAft()
{
	return aftViewOffset;
}


Vector PlayerEntity::viewpointOffsetForward()
{
	return forwardViewOffset;
}


Vector PlayerEntity::viewpointOffsetPort()
{
	return portViewOffset;
}


Vector PlayerEntity::viewpointOffsetStarboard()
{
	return starboardViewOffset;
}


/* TODO post 1.78: profiling suggests this gets called often enough
 * that it's worth caching the result per-frame - CIM */
HPVector PlayerEntity::viewpointPosition()
{
	HPVector		viewpoint = position;
	if (showDemoShips)
	{
		viewpoint = kZeroHPVector;
	}
	Vector		offset = viewpointOffset();
	
	// FIXME: this ought to be done with matrix or quaternion functions.
	OOMatrix r = rotMatrix;
	
	viewpoint.x += offset.x * r.m[0][0];	viewpoint.y += offset.x * r.m[1][0];	viewpoint.z += offset.x * r.m[2][0];
	viewpoint.x += offset.y * r.m[0][1];	viewpoint.y += offset.y * r.m[1][1];	viewpoint.z += offset.y * r.m[2][1];
	viewpoint.x += offset.z * r.m[0][2];	viewpoint.y += offset.z * r.m[1][2];	viewpoint.z += offset.z * r.m[2][2];
	
	return viewpoint;
}


void PlayerEntity::drawImmediate(bool immediate, bool translucent)
{
	switch (status())
	{
		case STATUS_DEAD:
		case STATUS_COCKPIT_DISPLAY:
		case STATUS_DOCKED:
		case STATUS_START_GAME:
			return;
			
		default:
			if ((UNIVERSE != nullptr ? UNIVERSE->breakPatternHide() : false))  return;
	}
	
	ShipEntity::drawImmediate(immediate, translucent);
}


void PlayerEntity::setMassLockable(bool newValue)
{
	massLockable = !!newValue;
	updateAlertCondition();
}


bool PlayerEntity::getMassLockable()
{
	return massLockable;
}


bool PlayerEntity::massLocked()
{
	return ((alertFlags & ALERT_FLAG_MASS_LOCK) != 0);
}


bool PlayerEntity::atHyperspeed()
{
	return travelling_at_hyperspeed;
}


float PlayerEntity::occlusionLevel()
{
	return occlusion_dial;
}


void PlayerEntity::setOcclusionLevel(float level)
{
	occlusion_dial = level;
}


void PlayerEntity::setDockedAtMainStation()
{
	setDockedStation((UNIVERSE != nullptr ? UNIVERSE->station() : nullptr));
	if (_dockedStation != oo::WeakRef<Entity>())  setStatus(STATUS_DOCKED);
}


::StationEntity *PlayerEntity::dockedStation()
{
	return oo::ToStation(_dockedStation.get());
}


void PlayerEntity::setDockedStation(::StationEntity *station)
{
	_dockedStation = oo::WeakRef<Entity>(station);
}


void PlayerEntity::setTargetDockStationTo(::StationEntity *value)
{
	targetDockStation = value;
}


::StationEntity *PlayerEntity::getTargetDockStation()
{
	return targetDockStation;
}


::HeadUpDisplay *PlayerEntity::getHud()
{
	return hud.get();
}


void PlayerEntity::resetHud()
{
	// set up defauld HUD for the ship
	const oo::PList shipDict = OOShipRegistry::sharedRegistry()->shipInfoForKey(shipDataKey().value_or(""));
	const std::string hud_desc = shipDict.get<std::string>("hud", "hud.plist");
	if (!switchHudTo(hud_desc))  switchHudTo("hud.plist");	// ensure we have a HUD to fall back to
}


bool PlayerEntity::switchHudTo(const std::string &hudFileName)
{
	BOOL 			wasHidden = NO;
	BOOL 			wasCompassActive = YES;
	double			scannerZoom = 1.0;
	NSUInteger		lastMFD = 0;
	NSUInteger		i;

	// (a nil name returns NO in the bridged -switchHudTo:)
	// is the HUD in the process of being rendered? If yes, set it to defer state and abort the switching now
	if (hud != nil && hud->isUpdating())
	{
		hud->setDeferredHudName(hudFileName);
		return NO;
	}
	
	const oo::PList hudDict = ResourceManager::dictionaryFromFilesNamed(hudFileName, std::string("Config"), YES);
	// hud defined, but buggy?
	if (hudDict.isNull())
	{
		OO_LOG("PlayerEntity.switchHudTo.failed", "HUD dictionary file {} to switch to not found or invalid.", hudFileName);
		return NO;
	}
	
	if (hud != nil)
	{
		// remember these values
		wasHidden = hud->isHidden();
		wasCompassActive = hud->isCompassActive();
		scannerZoom = hud->scannerZoom();
		lastMFD = activeMFD;
	}
	
	// buggy oxp could override hud.plist with a non-dictionary.
	if (!hudDict.isNull())
	{
		if (hud != nullptr)  hud->setHidden(YES);	// hide the hud while rebuilding it.
		hud = nullptr;
		hud = oo::makeRef<HeadUpDisplay>();	// [[HeadUpDisplay alloc] cxx_initWithDictionary:inFile:]
		hud->initWithDictionary(hudDict, hudFileName);
		hud->resetGuis(hudDict);
		// reset zoom & hidden to what they were before the swich
		hud->setScannerZoom(scannerZoom);
		hud->setCompassActive(wasCompassActive);
		hud->setHidden(wasHidden);
		activeMFD = 0;
		const std::vector<std::optional<std::string>> savedMFDs = multiFunctionDisplaySettings;
		multiFunctionDisplaySettings.clear();
		for (i = 0; i < hud->mfdCount() ; i++)
		{
			if (savedMFDs.size() > i)
			{
				multiFunctionDisplaySettings.push_back(savedMFDs[i]);
			}
			else
			{
				multiFunctionDisplaySettings.push_back(std::nullopt);
			}
		}
		if (lastMFD < hud->mfdCount()) activeMFD = lastMFD;
	}
	
	return YES;
}


float PlayerEntity::dialCustomFloat(const std::string &dialKey)
{
	const auto found = customDialSettings.find(dialKey);
	return oo::PListGet<float>::from(found != customDialSettings.end() ? &found->second : nullptr, 0.0f);
}


std::string PlayerEntity::dialCustomString(const std::string &dialKey)
{
	const auto found = customDialSettings.find(dialKey);
	return oo::PListGet<std::string>::from(found != customDialSettings.end() ? &found->second : nullptr, "");
}


oo::Ref<OOColor> PlayerEntity::dialCustomColor(const std::string &dialKey)
{
	const auto found = customDialSettings.find(dialKey);
	return OOColor::colorWithDescription((found != customDialSettings.end() ? found->second : oo::PList()));
}


void PlayerEntity::setDialCustom(const oo::PList &value, const std::string &dialKey)
{
	customDialSettings[dialKey] = value;	// non-plist values (colours...) are Object nodes; null is a null entry (it raised before)
}


void PlayerEntity::setShowDemoShips(bool value)
{
	showDemoShips = value;
}


bool PlayerEntity::getShowDemoShips()
{
	return showDemoShips;
}


float PlayerEntity::maxForwardShieldLevel()
{
	return max_forward_shield;
}


float PlayerEntity::maxAftShieldLevel()
{
	return max_aft_shield;
}


float PlayerEntity::forwardShieldRechargeRate()
{
	return forward_shield_recharge_rate;
}


float PlayerEntity::aftShieldRechargeRate()
{
	return aft_shield_recharge_rate;
}


void PlayerEntity::setMaxForwardShieldLevel(float newValue)
{
	max_forward_shield = newValue;
}


void PlayerEntity::setMaxAftShieldLevel(float newValue)
{
	max_aft_shield = newValue;
}


void PlayerEntity::setForwardShieldRechargeRate(float newValue)
{
	forward_shield_recharge_rate = newValue;
}


void PlayerEntity::setAftShieldRechargeRate(float newValue)
{
	aft_shield_recharge_rate = newValue;
}


GLfloat PlayerEntity::forwardShieldLevel()
{
	return forward_shield;
}


GLfloat PlayerEntity::aftShieldLevel()
{
	return aft_shield;
}


void PlayerEntity::setForwardShieldLevel(GLfloat level)
{
	forward_shield = OOClamp_0_max_f(level, maxForwardShieldLevel());
}


void PlayerEntity::setAftShieldLevel(GLfloat level)
{
	aft_shield = OOClamp_0_max_f(level, maxAftShieldLevel());
}


oo::PList PlayerEntity::keyConfig()
{
	//return keyconfig_settings;
	return oo::PList(keyconfig2_settings);
}


bool PlayerEntity::isMouseControlOn()
{
	return mouse_control_on;
}


GLfloat PlayerEntity::dialRoll()
{
	GLfloat result = flightRoll / max_flight_roll;
	if ((result < 1.0f)&&(result > -1.0f))
		return result;
	if (result > 0.0f)
		return 1.0f;
	return -1.0f;
}


GLfloat PlayerEntity::dialPitch()
{
	GLfloat result = flightPitch / max_flight_pitch;
	if ((result < 1.0f)&&(result > -1.0f))
		return result;
	if (result > 0.0f)
		return 1.0f;
	return -1.0f;
}


GLfloat PlayerEntity::dialYaw()
{
	GLfloat result = -flightYaw / max_flight_yaw;
	if ((result < 1.0f)&&(result > -1.0f))
	return result;
	if (result > 0.0f)
		return 1.0f;
	return -1.0f;
}


GLfloat PlayerEntity::dialSpeed()
{
	GLfloat result = flightSpeed / maxFlightSpeed;
	return OOClamp_0_1_f(result);
}


GLfloat PlayerEntity::dialHyperSpeed()
{
	return flightSpeed / maxFlightSpeed;
}


GLfloat PlayerEntity::dialForwardShield()
{
	if (EXPECT_NOT(maxForwardShieldLevel() <= 0))
	{
		return 0.0;
	}
	GLfloat result = forward_shield / maxForwardShieldLevel();
	return OOClamp_0_1_f(result);
}



// Slice 11 of docs/phases/3-slices/PlayerEntity.md (bead oo-zxg1h): the dials (shields, energy, fuel, heat, altitude, clock, missiles, scoop), fuel leak, the comm log, player roles, system memory, the compass target.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

GLfloat PlayerEntity::dialAftShield()
{
	if (EXPECT_NOT(maxAftShieldLevel() <= 0))
	{
		return 0.0;
	}
	GLfloat result = aft_shield / maxAftShieldLevel();
	return OOClamp_0_1_f(result);
}


GLfloat PlayerEntity::dialEnergy()
{
	GLfloat result = energy / maxEnergy;
	return OOClamp_0_1_f(result);
}


GLfloat PlayerEntity::dialMaxEnergy()
{
	return maxEnergy;
}


GLfloat PlayerEntity::dialFuel()
{
	if (fuel <= 0.0f)
		return 0.0f;
	if (fuel > fuelCapacity())
		return 1.0f;
	return (GLfloat)fuel / (GLfloat)fuelCapacity();
}


GLfloat PlayerEntity::dialHyperRange()
{
	if (target_system_id == system_id && !(UNIVERSE != nullptr ? UNIVERSE->inInterstellarSpace() : false))  return 0.0f;
	return fuelRequiredForJump() / (GLfloat)PLAYER_MAX_FUEL;
}


GLfloat PlayerEntity::laserHeatLevel()
{
	GLfloat result = (GLfloat)weapon_temp / (GLfloat)PLAYER_MAX_WEAPON_TEMP;
	return OOClamp_0_1_f(result);
}


GLfloat PlayerEntity::laserHeatLevelAft()
{
	GLfloat result = aft_weapon_temp / (GLfloat)PLAYER_MAX_WEAPON_TEMP;
	return OOClamp_0_1_f(result);
}


GLfloat PlayerEntity::laserHeatLevelForward()
{
	GLfloat result = forward_weapon_temp / (GLfloat)PLAYER_MAX_WEAPON_TEMP;
// no need to check subents here
	return OOClamp_0_1_f(result);
}


GLfloat PlayerEntity::laserHeatLevelPort()
{
	GLfloat result = port_weapon_temp / PLAYER_MAX_WEAPON_TEMP;
	return OOClamp_0_1_f(result);
}


GLfloat PlayerEntity::laserHeatLevelStarboard()
{
	GLfloat result = starboard_weapon_temp / PLAYER_MAX_WEAPON_TEMP;
	return OOClamp_0_1_f(result);
}


GLfloat PlayerEntity::dialAltitude()
{
	if (isDocked())  return 0.0f;
	
	// find nearest planet type entity...
	assert(UNIVERSE != nil);
	
	Entity	*nearestPlanet = findNearestStellarBody();
	if (nearestPlanet == nullptr)  return 1.0f;
	
	GLfloat	zd = nearestPlanet->zero_distance;
	GLfloat	cr = nearestPlanet->collision_radius;
	GLfloat	alt = sqrt(zd) - cr;
	
	return OOClamp_0_1_f(alt / (GLfloat)PLAYER_DIAL_MAX_ALTITUDE);
}


double PlayerEntity::clockTime()
{
	return ship_clock;
}


double PlayerEntity::clockTimeAdjusted()
{
	return ship_clock + ship_clock_adjust;
}


bool PlayerEntity::clockAdjusting()
{
	return ship_clock_adjust > 0;
}


void PlayerEntity::addToAdjustTime(double seconds)
{
	ship_clock_adjust += seconds;
}


double PlayerEntity::escapePodRescueTime()
{
	return escape_pod_rescue_time;
}


void PlayerEntity::setEscapePodRescueTime(double seconds)
{
	escape_pod_rescue_time = seconds;
}


std::string PlayerEntity::dial_clock()
{
	return cxx_ClockToString(ship_clock, ship_clock_adjust > 0);
}


std::string PlayerEntity::dial_clock_adjusted()
{
	return cxx_ClockToString(ship_clock + ship_clock_adjust, NO);
}


std::string PlayerEntity::dial_fpsinfo()
{
	unsigned fpsVal = fps_counter;
	return oo::str::format("FPS: %3d", fpsVal);
}


std::string PlayerEntity::dial_objinfo()
{
	std::string result = oo::str::format("Entities: %3zu", (UNIVERSE != nullptr ? UNIVERSE->entityCount() : 0));
#ifndef NDEBUG
	result = oo::str::format("%s (%d, %zu KiB, avg %zu bytes)", result.c_str(), gLiveEntityCount, gTotalEntityMemory >> 10, gTotalEntityMemory / gLiveEntityCount);
#endif
	
	return result;
}


unsigned PlayerEntity::countMissiles()
{
	unsigned n_missiles = 0;
	unsigned i;
	for (i = 0; i < max_missiles; i++)
	{
		if (missile_entity[i])
			n_missiles++;
	}
	return n_missiles;
}


OOMissileStatus PlayerEntity::dialMissileStatus()
{
	if (weaponsOnline())
	{
		return missile_status;
	}
	else
	{
		// Invariant/safety interlock: weapons offline implies missiles safe. -- Ahruman 2012-07-21
		if (missile_status != MISSILE_STATUS_SAFE)
		{
			OO_LOG_ERR("player.missilesUnsafe", "{}", "Missile state is not SAFE when weapons are offline. This is a bug, please report it.");
			safeAllMissiles();
		}
		return MISSILE_STATUS_SAFE;
	}
}


bool PlayerEntity::canScoop(::ShipEntity *other)
{
	if (specialCargo)	return NO;
	return ShipEntity::canScoop(other);
}


OOFuelScoopStatus PlayerEntity::dialFuelScoopStatus()
{
	// need to account for the different ways of calculating cargo on board when docked/in-flight
	OOCargoQuantity cargoOnBoard = status() == STATUS_DOCKED ? current_cargo : (OOCargoQuantity)cargo.size();
	if (hasScoop())
	{
		if (scoopsActive)
			return SCOOP_STATUS_ACTIVE;
		if (cargoOnBoard >= maxAvailableCargoSpace() || specialCargo)
			return SCOOP_STATUS_FULL_HOLD;
		return SCOOP_STATUS_OKAY;
	}
	else
	{
		return SCOOP_STATUS_NOT_INSTALLED;
	}
}


float PlayerEntity::fuelLeakRate()
{
	return fuel_leak_rate;
}


void PlayerEntity::setFuelLeakRate(float value)
{
	fuel_leak_rate = fmax(value, 0.0f);
}


std::vector<std::string> *PlayerEntity::getCommLog()
{
	assert(kCommLogTrimSize < kCommLogTrimThreshold);

	const std::size_t count = commLog.size();
	if (count >= kCommLogTrimThreshold)
	{
		commLog.erase(commLog.begin(), commLog.begin() + static_cast<std::ptrdiff_t>(count - kCommLogTrimSize));
	}

	return &commLog;	// (a nil receiver gives nullptr)
}


std::vector<std::string> PlayerEntity::getRoleWeights()
{
	return roleWeights;
}


void PlayerEntity::addRoleForAggression(::ShipEntity *victim)
{
	if ((victim != nullptr ? victim->isExplicitlyUnpiloted() : false) || (victim != nullptr ? victim->getIsHulk() : false) || (victim != nullptr ? victim->hasHostileTarget() : false) || oo::EntityIsPlayer((victim != nullptr ? victim->primaryAggressor() : (Entity *)nullptr)))
	{
		return;
	}
	std::optional<std::string> role;
	if ((victim != nullptr ? victim->getPrimaryRole() : std::optional<std::string>()) == "escape-capsule")
	{
		role = "assassin-player";
	}
	else if ((victim != nullptr ? victim->getBounty() : 0) > 0)
	{
		role = "hunter";
	}
	else if ((victim != nullptr ? victim->isPirateVictim() : false))
	{
		role = "pirate";
	}
	else if ((getPrimaryRole().has_value() && (UNIVERSE != nullptr ? UNIVERSE->role(*getPrimaryRole(), "oolite-hunter") : false)) || (victim != nullptr ? victim->getScanClass() : OOScanClass{}) == CLASS_POLICE)
	{
		role = "pirate-interceptor";
	}
	if (!role.has_value())
	{
		return;
	}
	NSUInteger times = RoleFlagCount(roleWeightFlags, *role);
	times++;
	roleWeightFlags.insert_or_assign(*role, oo::PList::signedInteger(static_cast<std::int64_t>(times)));
	if ((times & (times-1)) == 0) // is power of 2
	{
		addRoleToPlayer(*role);
	}
}


void PlayerEntity::addRoleForMining()
{
	const std::string role = "miner";
	NSUInteger times = RoleFlagCount(roleWeightFlags, role);
	times++;
	roleWeightFlags.insert_or_assign(role, oo::PList::signedInteger(static_cast<std::int64_t>(times)));
	if ((times & (times-1)) == 0) // is power of 2
	{
		addRoleToPlayer(role);
	}
}


void PlayerEntity::addRoleToPlayer(const std::string &role)
{
	NSUInteger slot = Ranrot() & (maxPlayerRoles()-1);
	addRoleToPlayer(role, slot);
}


void PlayerEntity::addRoleToPlayer(const std::string &role, NSUInteger slot)
{
	if (slot >= maxPlayerRoles())
	{
		slot = maxPlayerRoles()-1;
	}
	if (slot >= roleWeights.size())
	{
		roleWeights.push_back(role);
	}
	else
	{
		roleWeights[slot] = role;
	}
}


void PlayerEntity::clearRoleFromPlayer(bool includingLongRange)
{
	NSUInteger slot = Ranrot() % roleWeights.size();
	if (!includingLongRange)
	{
		const std::string &role = roleWeights[slot];
		// long range roles cleared at 1/2 normal rate
		if (oo::str::hasSuffix(role, "+") && randf() > 0.5)
		{
			return;
		}
	}
	roleWeights[slot] = "player-unknown";
}


void PlayerEntity::clearRolesFromPlayer(float chance)
{
	NSUInteger i, count=roleWeights.size();
	for (i = 0; i < count; i++)
	{
		if (randf() < chance)
		{
			roleWeights[i] = "player-unknown";
		}
	}
}


NSUInteger PlayerEntity::maxPlayerRoles()
{
	if (ship_kills >= 6400)
	{
		return 32;
	}
	else if (ship_kills >= 128)
	{
		return 16;
	}
	else
	{
		return 8;
	}
}


void PlayerEntity::updateSystemMemory()
{
	OOSystemID sys = currentSystemID();
	if (sys < 0)
	{
		return;
	}
	NSUInteger memory = 4;
	if (ship_kills >= 6400)
	{
		memory = 32;
	}
	else if (ship_kills >= 256)
	{
		memory = 16;
	}
	else if (ship_kills >= 64)
	{
		memory = 8;
	}
	if (roleSystemList.size() >= memory)
	{
		roleSystemList.erase(roleSystemList.begin());
	}
	roleSystemList.push_back(sys);
}


// Virtual: a test's player answers it. What the object-answering getCompassTarget() answered the C++
// entity of (bead oo-zwnvp): null once the target's object has gone, which also forgets it.
Entity *PlayerEntity::getCompassTargetEntity()
{
	Entity *result = oo::LiveEntity(compassTarget);
	if (result == nullptr)
	{
		compassTarget = nullptr;
		return nullptr;
	}
	return result;
}


void PlayerEntity::setCompassTargetEntity(Entity *value)
{
	compassTarget = oo::WeakRef<Entity>(value);	// oo::WeakEntityRef() of its object
}


void PlayerEntity::validateCompassTarget()
{
	::OOSunEntity		*the_sun = (UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr);
	Entity			*the_planet = (UNIVERSE != nullptr ? UNIVERSE->planet() : nullptr);	// C++ since bead oo-9ht.129
	::StationEntity	*the_station = (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr);
	Entity			*the_target = primaryTarget();
	Entity		*beacon = nextBeacon();
	if (isInSpace() && the_sun && the_planet		// be in a system
		&& !(the_sun != nullptr ? the_sun->goneNova() : false))			// and the system has not been novabombed
	{
		Entity *new_target = nullptr;	// the C++ entities (bead oo-9ht.39.18)
		OOAegisStatus	aegis = checkForAegis();
		
		switch (getCompassMode())
		{
			case COMPASS_MODE_INACTIVE:
				break;
			
			case COMPASS_MODE_BASIC:
				if ((aegis == AEGIS_CLOSE_TO_MAIN_PLANET || aegis == AEGIS_IN_DOCKING_RANGE) && the_station)
				{
					new_target = the_station;
				}
				else
				{
					new_target = the_planet;
				}
				break;
				
			case COMPASS_MODE_PLANET:
				new_target = the_planet;
				break;
				
			case COMPASS_MODE_STATION:
				new_target = the_station;
				break;
				
			case COMPASS_MODE_SUN:
				new_target = the_sun;	// the sun is C++ since bead oo-9ht.111
				break;
				
			case COMPASS_MODE_TARGET:
				new_target = the_target;
				break;
				
			case COMPASS_MODE_BEACONS:
				new_target = beacon;
				break;
		}
		
		if (new_target == nullptr || oo::EntityStatus(new_target) < STATUS_ACTIVE || oo::EntityStatus(new_target) == STATUS_IN_HOLD)
		{
			setCompassMode(COMPASS_MODE_PLANET);
			new_target = the_planet;
		}
		
		if (EXPECT_NOT(new_target != getCompassTargetEntity()))
		{
			setCompassTargetEntity(new_target);
			// a nil target was left out of the Objective-C argument array, as before
			std::vector<oo::PList> compassArguments;
			if (new_target != nullptr)  compassArguments.push_back(oo::EntityObjectNode(new_target));
			compassArguments.emplace_back(cxx_OOStringFromCompassMode(getCompassMode()));
			doScriptEvent(OOJSID("compassTargetChanged"), compassArguments);
		}
	}
}


std::optional<std::string> PlayerEntity::compassTargetLabel()
{
	switch (compassMode)
	{
	case COMPASS_MODE_INACTIVE:
		return "";
	case COMPASS_MODE_BASIC:
		return "";
	case COMPASS_MODE_BEACONS:
	{
		Entity *target = getCompassTargetEntity();
		if (target)
		{
			return oo::BeaconLabel(target);	// the beacon category's answer (bead oo-w9pi2)
		}
		return "";
	}
	case COMPASS_MODE_PLANET:
		return ((UNIVERSE != nullptr ? UNIVERSE->planet() : nullptr) != nullptr ? UNIVERSE->planet()->name() : std::optional<std::string>());
	case COMPASS_MODE_SUN:
		return ((UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr) != nullptr ? UNIVERSE->sun()->name() : std::optional<std::string>());
	case COMPASS_MODE_STATION:
		return ((UNIVERSE != nullptr ? UNIVERSE->station() : nullptr) != nullptr ? UNIVERSE->station()->getDisplayName() : std::optional<std::string>());
	case COMPASS_MODE_TARGET:
		return OO_DESC("oolite-beacon-label-target");
	}
	return "";
}



// Slice 12 of docs/phases/3-slices/PlayerEntity.md (bead oo-rqcfz): compass mode, missiles and pylons, special cargo, the multi-function displays, alert flags.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

OOCompassMode PlayerEntity::getCompassMode()
{
	return compassMode;
}


void PlayerEntity::setCompassMode(OOCompassMode value)
{
	compassMode = value;
}


void PlayerEntity::setPrevCompassMode()
{
	OOAegisStatus	aegis = AEGIS_NONE;
	Entity		*beacon = nullptr;	// the C++ beacons, linked through their objects (bead oo-9ht.39.18)
	
	switch (compassMode)
	{
		case COMPASS_MODE_INACTIVE:
		case COMPASS_MODE_BASIC:
		case COMPASS_MODE_PLANET:
			beacon = (UNIVERSE != nullptr ? UNIVERSE->lastBeacon() : nullptr);
			while (beacon != nullptr && oo::BeaconIsJammingScanning(beacon))
			{
				beacon = oo::PrevBeacon(beacon);
			}
			setNextBeacon(beacon);
			
			if (beacon != nil)
			{
				setCompassMode(COMPASS_MODE_BEACONS);
				break;
			}
			// else fall through to switch to target mode.

		case COMPASS_MODE_BEACONS:
			beacon = nextBeacon();
			do
			{
				beacon = oo::PrevBeacon(beacon);
			} while (beacon != nullptr && oo::BeaconIsJammingScanning(beacon));
			setNextBeacon(beacon);
			
			if (beacon == nil)
			{
				if (primaryTarget())
				{
					setCompassMode(COMPASS_MODE_TARGET);
				}
				else
				{
					setCompassMode(COMPASS_MODE_SUN);
				}
				break;
			}
			break;

		case COMPASS_MODE_TARGET:
			setCompassMode(COMPASS_MODE_SUN);
			break;

		case COMPASS_MODE_SUN:
			aegis = checkForAegis();
			if (aegis == AEGIS_CLOSE_TO_MAIN_PLANET || aegis == AEGIS_IN_DOCKING_RANGE)
			{ 
				setCompassMode(COMPASS_MODE_STATION);
			}
			else
			{
				setCompassMode(COMPASS_MODE_PLANET);
			} 
			break;

		case COMPASS_MODE_STATION:
			setCompassMode(COMPASS_MODE_PLANET);
			break;
	}
}


void PlayerEntity::setNextCompassMode()
{
	OOAegisStatus	aegis = AEGIS_NONE;
	Entity		*beacon = nullptr;	// the C++ beacons, linked through their objects (bead oo-9ht.39.18)
	
	switch (compassMode)
	{
		case COMPASS_MODE_INACTIVE:
		case COMPASS_MODE_BASIC:
		case COMPASS_MODE_PLANET:
			aegis = checkForAegis();
			if ((UNIVERSE != nullptr && UNIVERSE->station() != nullptr) && (aegis == AEGIS_CLOSE_TO_MAIN_PLANET || aegis == AEGIS_IN_DOCKING_RANGE))
			{ 
				setCompassMode(COMPASS_MODE_STATION);
			}
			else
			{
				setCompassMode(COMPASS_MODE_SUN);
			}
			break;
			
		case COMPASS_MODE_STATION:
			setCompassMode(COMPASS_MODE_SUN);
			break;
			
		case COMPASS_MODE_SUN:
			if (primaryTarget())
			{
				setCompassMode(COMPASS_MODE_TARGET);
				break;
			}
			// else fall through to switch to beacon mode.
			
		case COMPASS_MODE_TARGET:
			beacon = (UNIVERSE != nullptr ? UNIVERSE->firstBeacon() : nullptr);
			while (beacon != nullptr && oo::BeaconIsJammingScanning(beacon))
			{
				beacon = oo::NextBeacon(beacon);
			}
			setNextBeacon(beacon);
			
			if (beacon != nil)  setCompassMode(COMPASS_MODE_BEACONS);
			else  setCompassMode(COMPASS_MODE_PLANET);
			break;

		case COMPASS_MODE_BEACONS:
			beacon = nextBeacon();
			do
			{
				beacon = oo::NextBeacon(beacon);
			} while (beacon != nullptr && oo::BeaconIsJammingScanning(beacon));
			setNextBeacon(beacon);
			
			if (beacon == nil)
			{
				setCompassMode(COMPASS_MODE_PLANET);
			}
			break;
	}
}


NSUInteger PlayerEntity::getActiveMissile()
{
	return activeMissile;
}


void PlayerEntity::setActiveMissile(NSUInteger value)
{
	activeMissile = value;
}


NSUInteger PlayerEntity::dialMaxMissiles()
{
	return max_missiles;
}


bool PlayerEntity::dialIdentEngaged()
{
	return ident_engaged;
}


void PlayerEntity::setDialIdentEngaged(bool newValue)
{
	ident_engaged = !!newValue;
}


std::optional<std::string> PlayerEntity::getSpecialCargo()
{
	return specialCargo;
}


std::optional<std::string> PlayerEntity::dialTargetName()
{
	Entity		*target_entity = primaryTarget();
	std::optional<std::string>	result;

	if (target_entity == nullptr)
	{
		result = OO_DESC("no-target-string");
	}

	// A wormhole answered -identFromShip: through its facade until bead oo-9ht.112; it is asked
	// directly now, and any other target that answers the selector as before.
	if (WormholeEntity *wh = dynamic_cast<WormholeEntity *>(target_entity))
	{
		result = wh->identFromShip(this);
	}
	else if (::ShipEntity *ship = oo::ToShip(target_entity))	// what answered -identFromShip: (a ship's facade until bead oo-9ht.144)
	{
		result = ship->identFromShip(this);
	}

	if (!result.has_value())  result = OO_DESC("unknown-target");
	
	return result;
}


std::vector<std::optional<std::string>> PlayerEntity::multiFunctionDisplayList()
{
	return multiFunctionDisplaySettings;
}


std::optional<std::string> PlayerEntity::multiFunctionText(NSUInteger i)
{
	if (i >= multiFunctionDisplaySettings.size() || !multiFunctionDisplaySettings[i].has_value())
	{
		return std::nullopt;
	}
	const auto text = multiFunctionDisplayText.find(*multiFunctionDisplaySettings[i]);
	if (text == multiFunctionDisplayText.end())  return std::nullopt;
	return text->second;
}


void PlayerEntity::setMultiFunctionText(const std::optional<std::string> &text, const std::optional<std::string> &key)
{
	if (text.has_value())
	{
		if (key.has_value())  multiFunctionDisplayText[*key] = *text;	// (a nil key raised before)
	}
	else if (key.has_value())
	{
		multiFunctionDisplayText.erase(*key);
		// and blank any MFDs currently using it
		std::replace(multiFunctionDisplaySettings.begin(), multiFunctionDisplaySettings.end(), key, std::optional<std::string>());
	}
}


bool PlayerEntity::setMultiFunctionDisplay(NSUInteger index, const std::optional<std::string> &key)
{
	if (index >= ((hud != nullptr) ? hud->mfdCount() : 0))	// a nil HUD answered 0
	{
		// is first inactive display
		const auto inactive = std::find(multiFunctionDisplaySettings.begin(), multiFunctionDisplaySettings.end(), std::nullopt);
		if (inactive == multiFunctionDisplaySettings.end())
		{
			return NO;
		}
		index = static_cast<NSUInteger>(inactive - multiFunctionDisplaySettings.begin());
	}

	if (index < ((hud != nullptr) ? hud->mfdCount() : 0))
	{
		multiFunctionDisplaySettings.at(index) = key;	// nullopt = inactive
		return YES;
	}
	else
	{
		return NO;
	}
}


void PlayerEntity::cycleNextMultiFunctionDisplay(NSUInteger index)
{
	if (getHud() == nullptr || getHud()->mfdCount() == 0) return;
	std::vector<std::string> keys;	// byte order (was -allKeys hash order)
	keys.reserve(multiFunctionDisplayText.size());
	for (const auto &entry : multiFunctionDisplayText)  keys.push_back(entry.first);
	std::optional<std::string> key;
	if (keys.empty())
	{
		setMultiFunctionDisplay(index, std::nullopt);
		return;
	}
	const std::optional<std::string> current = multiFunctionDisplaySettings.at(index);
	if (!current.has_value())
	{
		key = keys[0];
		setMultiFunctionDisplay(index, key);
	}
	else
	{
		const auto currentKey = std::find(keys.begin(), keys.end(), *current);
		const NSUInteger cIndex = (currentKey != keys.end()) ? static_cast<NSUInteger>(currentKey - keys.begin()) : NSNotFound;
		if (cIndex == NSNotFound || cIndex + 1 >= keys.size())
		{
			key = std::nullopt;
			setMultiFunctionDisplay(index, std::nullopt);
		}
		else 
		{
			key = keys[cIndex+1];
			setMultiFunctionDisplay(index, key);
		}
	}
	ooscript::Context context = OOJSAcquireContext();
	ooscript::Value keyVal = OOJSValueFromPList(context, key.has_value() ? oo::PList(*key) : oo::PList());
	ShipScriptEvent(context, this, "mfdKeyChanged", ooscript::int32Value(activeMFD), keyVal);
	OOJSRelinquishContext(context);
}


void PlayerEntity::cyclePreviousMultiFunctionDisplay(NSUInteger index)
{
	if (getHud() == nullptr || getHud()->mfdCount() == 0) return;
	std::vector<std::string> keys;	// byte order (was -allKeys hash order)
	keys.reserve(multiFunctionDisplayText.size());
	for (const auto &entry : multiFunctionDisplayText)  keys.push_back(entry.first);
	std::optional<std::string> key;
	if (keys.empty())
	{
		setMultiFunctionDisplay(index, std::nullopt);
		return;
	}
	const std::optional<std::string> current = multiFunctionDisplaySettings.at(index);
	if (!current.has_value())
	{
		key = keys[keys.size()-1];
		setMultiFunctionDisplay(index, key);
	}
	else
	{
		const auto currentKey = std::find(keys.begin(), keys.end(), *current);
		const NSUInteger cIndex = (currentKey != keys.end()) ? static_cast<NSUInteger>(currentKey - keys.begin()) : NSNotFound;
		if (cIndex == NSNotFound || cIndex == 0)
		{
			key = std::nullopt;
			setMultiFunctionDisplay(index, std::nullopt);
		}
		else 
		{
			key = keys[cIndex-1];
			setMultiFunctionDisplay(index, key);
		}
	}
	ooscript::Context context = OOJSAcquireContext();
	ooscript::Value keyVal = OOJSValueFromPList(context, key.has_value() ? oo::PList(*key) : oo::PList());
	ShipScriptEvent(context, this, "mfdKeyChanged", ooscript::int32Value(activeMFD), keyVal);
	OOJSRelinquishContext(context);
}


void PlayerEntity::selectNextMultiFunctionDisplay()
{
	if (getHud() == nullptr || getHud()->mfdCount() == 0) return;
	activeMFD = (activeMFD + 1) % getHud()->mfdCount();
	NSUInteger mfdID = activeMFD + 1;
	if (UNIVERSE != nullptr)  UNIVERSE->addMessage(cxx_OOExpandKey("mfd-N-selected", mfdID), 3.0);
	ooscript::Context context = OOJSAcquireContext();
	ShipScriptEvent(context, this, "selectedMFDChanged", ooscript::int32Value(activeMFD));
	OOJSRelinquishContext(context);
}


void PlayerEntity::selectPreviousMultiFunctionDisplay()
{
	if (getHud() == nullptr || getHud()->mfdCount() == 0) return;
	if (activeMFD == 0) 
	{
		activeMFD = (getHud()->mfdCount() - 1);
	}
	else
	{
		activeMFD = (activeMFD - 1);
	}
	NSUInteger mfdID = activeMFD + 1;
	if (UNIVERSE != nullptr)  UNIVERSE->addMessage(cxx_OOExpandKey("mfd-N-selected", mfdID), 3.0);
	ooscript::Context context = OOJSAcquireContext();
	ShipScriptEvent(context, this, "selectedMFDChanged", ooscript::int32Value(activeMFD));
	OOJSRelinquishContext(context);
}


NSUInteger PlayerEntity::getActiveMFD()
{
	return activeMFD;
}


::ShipEntity *PlayerEntity::missileForPylon(NSUInteger value)
{
	if (value < max_missiles)  return oo::ToShip(missile_entity[value].get());
	return nil;
}


void PlayerEntity::safeAllMissiles()
{
	//	sets all missile targets to NO_TARGET
	
	unsigned i;
	for (i = 0; i < max_missiles; i++)
	{
		if (missile_entity[i] && (oo::ToShip(missile_entity[i].get()) != nullptr ? oo::ToShip(missile_entity[i].get())->primaryTarget() : (Entity *)nullptr) != nil)
			if (oo::ToShip(missile_entity[i].get()) != nullptr)  oo::ToShip(missile_entity[i].get())->removeTarget(nullptr);
	}
	missile_status = MISSILE_STATUS_SAFE;
}


void PlayerEntity::tidyMissilePylons()
{
	// Make sure there's no gaps between missiles, synchronise missile_entity & missile_list.
	int i, pylon = 0;
	OO_LOG("missile.tidying.debug", "Tidying fitted {} of possible {} missiles", missiles, PLAYER_MAX_MISSILES);
	for(i = 0; i < PLAYER_MAX_MISSILES; i++)
	{
		OO_LOG("missile.tidying.debug", "{} {} {}", i, oo::EntityDescription(missile_entity[i].get()), (missile_list[i] != nullptr) ? missile_list[i]->description() : std::string("(null)"));
		if(missile_entity[i])
		{
			missile_entity[pylon] = missile_entity[i];
			const std::optional<std::string> missileRole = (oo::ToShip(missile_entity[i].get()) != nullptr ? oo::ToShip(missile_entity[i].get())->getPrimaryRole() : std::optional<std::string>());
			missile_list[pylon] = missileRole.has_value() ? OOEquipmentType::equipmentTypeWithIdentifier(*missileRole).get() : nil;
			pylon++;
		}
	}

	// Now clean up the remainder of the pylons.
	for(i = pylon; i < PLAYER_MAX_MISSILES; i++)
	{
		missile_entity[i] = nullptr;
		// not strictly needed, but helps clear things up
		missile_list[i] = nil;
	}
}


void PlayerEntity::selectNextMissile()
{
	if (!weaponsOnline())  return;
	
	unsigned i;
	for (i = 1; i < max_missiles; i++)
	{
		int next_missile = (activeMissile + i) % max_missiles;
		if (missile_entity[next_missile])
		{
			// If we don't have the multi-targeting module installed, clear the active missiles' target
			if( !hasEquipmentItemProviding("EQ_MULTI_TARGET") && (oo::ToShip(missile_entity[activeMissile].get()) != nullptr ? oo::ToShip(missile_entity[activeMissile].get())->getIsMissile() : false) )
			{
				if (oo::ToShip(missile_entity[activeMissile].get()) != nullptr)  oo::ToShip(missile_entity[activeMissile].get())->removeTarget(nullptr);
			}

			// Set next missile to active
			setActiveMissile(next_missile);

			if (missile_status != MISSILE_STATUS_SAFE)
			{
				missile_status = MISSILE_STATUS_ARMED;

				// If the newly active pylon contains a missile then work out its target, if any
				if( (oo::ToShip(missile_entity[activeMissile].get()) != nullptr ? oo::ToShip(missile_entity[activeMissile].get())->getIsMissile() : false) )
				{
					if( hasEquipmentItemProviding("EQ_MULTI_TARGET") &&
							((oo::ToShip(missile_entity[next_missile].get()) != nullptr ? oo::ToShip(missile_entity[next_missile].get())->primaryTarget() : (Entity *)nullptr) != nil))
					{
						// copy the missile's target
						addTarget((oo::ToShip(missile_entity[next_missile].get()) != nullptr ? oo::ToShip(missile_entity[next_missile].get())->primaryTarget() : (Entity *)nullptr));
						missile_status = MISSILE_STATUS_TARGET_LOCKED;
					}
					else if (primaryTarget() != nil)
					{
						// never inherit target if we have EQ_MULTI_TARGET installed! [ Bug #16221 : Targeting enhancement regression ]
						/* CIM: seems okay to do this when launching a
						 * missile to stop multi-target being a bit
						 * irritating in a fight - 20/8/2014 */
						if(hasEquipmentItemProviding("EQ_MULTI_TARGET") && !launchingMissile)
						{
							noteLostTarget();
							_primaryTarget = nullptr;
						}
						else
						{
							if (oo::ToShip(missile_entity[activeMissile].get()) != nullptr)  oo::ToShip(missile_entity[activeMissile].get())->addTarget(primaryTarget());
							missile_status = MISSILE_STATUS_TARGET_LOCKED;
						}
					}
				}
			}
			return;
		}
	}
}


void PlayerEntity::clearAlertFlags()
{
	alertFlags = 0;
}


int PlayerEntity::getAlertFlags()
{
	return alertFlags;
}


void PlayerEntity::setAlertFlag(int flag, bool value)
{
	if (value)
	{
		alertFlags |= flag;
	}
	else
	{
		int comp = ~flag;
		alertFlags &= comp;
	}
}


// used by Javascript and the distinction is important for NPCs
OOAlertCondition PlayerEntity::realAlertCondition()
{
	return getAlertCondition();
}



// Slice 13 of docs/phases/3-slices/PlayerEntity.md (bead oo-30g73): alert condition, AI messages, mounting and firing missiles and mines, the cloak, ECM, energy units, the main weapons.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

OOAlertCondition PlayerEntity::getAlertCondition()
{
	OOAlertCondition old_alert_condition = alertConditionLevel;
	alertConditionLevel = ALERT_CONDITION_GREEN;
	
	setAlertFlag(ALERT_FLAG_DOCKED, status() == STATUS_DOCKED);
	
	if (alertFlags & ALERT_FLAG_DOCKED)
	{
		alertConditionLevel = ALERT_CONDITION_DOCKED;
	}
	else
	{
		if (alertFlags != 0)
		{
			alertConditionLevel = ALERT_CONDITION_YELLOW;
		}
		if (alertFlags > ALERT_FLAG_YELLOW_LIMIT)
		{
			alertConditionLevel = ALERT_CONDITION_RED;
		}
	}
	if ((alertConditionLevel == ALERT_CONDITION_RED)&&(old_alert_condition < ALERT_CONDITION_RED))
	{
		playAlertConditionRed();
	}
	
	return alertConditionLevel;
}


OOPlayerFleeingStatus PlayerEntity::fleeingStatus()
{
	return fleeing_status;
}


void PlayerEntity::interpretAIMessage(const std::string &message)
{

	if ((message == "HOLD_FULL"))
	{
		playHoldFull();
		if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("hold-full"), 4.5);
	}

	if ((message == "INCOMING_MISSILE"))
	{
		if (primaryAggressor() != nil)
		{
			playIncomingMissile(HPVectorToVector((primaryAggressor() != nullptr ? primaryAggressor()->getPosition() : kZeroHPVector)));
		}
		else
		{
			playIncomingMissile(kZeroVector);
		}
		if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("incoming-missile"), 4.5);
	}

	if ((message == "ENERGY_LOW"))
	{
		if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("energy-low"), 6.0);
	}

	if ((message == "ECM") && !isDocked())  playHitByECMSound();

	if ((message == "DOCKING_REFUSED") && status() == STATUS_AUTOPILOT_ENGAGED)
	{
		playDockingDenied();
		if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("autopilot-denied"), 4.5);
		autopilot_engaged = NO;
		resetAutopilotAI();
		_primaryTarget = nullptr;
		setStatus(STATUS_IN_FLIGHT);
		OOMusicController::sharedController()->stopDockingMusic();
		doScriptEvent(OOJSID("playerDockingRefused"));
	}

	// aegis messages to advanced compass so in planet mode it behaves like the old compass
	if (compassMode != COMPASS_MODE_BASIC)
	{
		if ((message == "AEGIS_CLOSE_TO_MAIN_PLANET")&&(compassMode == COMPASS_MODE_PLANET))
		{
			playAegisCloseToPlanet();
			setCompassMode(COMPASS_MODE_STATION);
		}
		if ((message == "AEGIS_IN_DOCKING_RANGE")&&(compassMode == COMPASS_MODE_PLANET))
		{
			playAegisCloseToStation();
			setCompassMode(COMPASS_MODE_STATION);
		}
		if ((message == "AEGIS_NONE")&&(compassMode == COMPASS_MODE_STATION))
		{
			setCompassMode(COMPASS_MODE_PLANET);
		}
	}
}


bool PlayerEntity::mountMissile(::ShipEntity *missile)
{
	if (missile == nil)  return NO;
	
	unsigned i;
	for (i = 0; i < max_missiles; i++)
	{
		if (!missile_entity[i])
		{
			missile_entity[i] = oo::EntityHold(missile);
			const std::optional<std::string> missileRole = (missile != nullptr ? missile->getPrimaryRole() : std::optional<std::string>());
			missile_list[missiles] = missileRole.has_value() ? OOEquipmentType::equipmentTypeWithIdentifier(*missileRole).get() : nil;
			missiles++;
			if (missiles == 1) setActiveMissile(0);	// auto select the first purchased missile
			return YES;
		}
	}
	
	return NO;
}


bool PlayerEntity::mountMissileWithRole(const std::string &role)
{
	if (missileCount() >= missileCapacity()) return NO;
	return mountMissile(oo::ToShip(oo::AutoreleaseEntity((UNIVERSE != nullptr ? UNIVERSE->newShipWithRole(role) : (::ShipEntity *)nil))));
}


::ShipEntity *PlayerEntity::fireMissile()
{
	::ShipEntity	*missile = oo::ToShip(missile_entity[activeMissile].get());	// retain count is 1
	const std::optional<std::string>	identifier = (missile != nullptr ? missile->getPrimaryRole() : std::optional<std::string>());	// a copy: the missile goes below
	::ShipEntity	*firedMissile = nil;

	if (missile == nil) return nil;
	
	if (!weaponsOnline())  return nil;
	
	// check if we were cloaked before firing the missile - can't use
	// cloaking_device_active directly because fireMissilewithIdentifier: andTarget:
	// will reset it in case passive cloak is set - Nikos 20130313
	BOOL cloakedPriorToFiring = cloaking_device_active;
	
	launchingMissile = YES;
	replacingMissile = NO;

	if ((missile != nullptr ? missile->isMine() : false) && (missile_status != MISSILE_STATUS_SAFE))
	{
		firedMissile = launchMine(missile);
		if (!replacingMissile) removeFromPylon(activeMissile);
		if (firedMissile != nil) playMineLaunched(missileLaunchPosition(), identifier.value_or(std::string()));
	}
	else
	{
		if (missile_status != MISSILE_STATUS_TARGET_LOCKED) return nil;
		//  release this before creating it anew in fireMissileWithIdentifier
		firedMissile = fireMissileWithIdentifier(identifier, (missile != nullptr ? missile->primaryTarget() : (Entity *)nullptr));

		if (firedMissile != nil)
		{
			if (!replacingMissile) removeFromPylon(activeMissile);
			playMissileLaunched(missileLaunchPosition(), identifier.value_or(std::string()));
		}
	}
	
	if (cloakedPriorToFiring && cloakPassive)
	{
		// fireMissilewithIdentifier: andTarget: has already taken care of deactivating
		// the cloak in the case of missiles by the time we get here, but explicitly
		// calling deactivateCloakingDevice is needed in order to be covered fully with mines too
		deactivateCloakingDevice();
	}
	
	replacingMissile = NO;
	launchingMissile = NO;
	
	return firedMissile;
}


::ShipEntity *PlayerEntity::launchMine(::ShipEntity *mine)
{
	if (!mine)
		return nil;
		
	if (!weaponsOnline())
		return nil;
		
	if (mine != nullptr)  mine->setOwner(this);
	if (mine != nullptr)  mine->setBehaviour(BEHAVIOUR_IDLE);
	dumpItem(mine);	// includes UNIVERSE addEntity: CLASS_CARGO, STATUS_IN_FLIGHT, AI state GLOBAL ( the last one starts the timer !)
	if (mine != nullptr)  mine->setScanClass(CLASS_MINE);
	
	float  mine_speed = 500.0f;
	Vector mvel = vector_subtract((mine != nullptr ? mine->getVelocity() : Vector{}), vector_multiply_scalar(v_forward, mine_speed));
	if (mine != nullptr)  mine->setVelocity(mvel);
	doScriptEvent(OOJSID("shipReleasedEquipment"), mine);
	return mine;
}


bool PlayerEntity::assignToActivePylon(const std::string &equipmentKey)
{
	if (!launchingMissile) return NO;
	
	::OOEquipmentType			*eqType = nil;
	
	if (oo::str::hasSuffix(equipmentKey, "_DAMAGED"))
	{
		return NO;
	}
	else
	{
		eqType = OOEquipmentType::equipmentTypeWithIdentifier(equipmentKey).get();
	}
	
	// missiles with techlevel above 99 (kOOVariableTechLevel) are never available to the player
	if (!(eqType != nullptr ? eqType->isMissileOrMine() : false) || (eqType != nullptr ? eqType->effectiveTechLevel() : 0) > kOOVariableTechLevel)
	{
		return NO;
	}

	::ShipEntity *amiss = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole(equipmentKey) : (::ShipEntity *)nil);
	
	if (!amiss) return NO;

	// replace the missile now.
	missile_entity[activeMissile] = oo::EntityHold::adopt(amiss);
	missile_list[activeMissile] = eqType;
	
	// make sure the new missile is properly activated.
	if (activeMissile > 0) activeMissile--;
	else activeMissile = max_missiles - 1;
	selectNextMissile();
	
	replacingMissile = YES;
	
	return YES;
}


bool PlayerEntity::activateCloakingDevice()
{
	if (!hasCloakingDevice())  return NO;
	
	if (ShipEntity::activateCloakingDevice())
	{
		if (UNIVERSE != nullptr)  UNIVERSE->setCurrentPostFX(OO_POSTFX_CLOAK);
		if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("cloak-on"), 2);
		playCloakingDeviceOn();
		return YES;
	}
	else
	{
		if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("cloak-low-juice"), 3);
		playCloakingDeviceInsufficientEnergy();
		return NO;
	}
}


void PlayerEntity::deactivateCloakingDevice()
{
	if (!hasCloakingDevice())  return;

	ShipEntity::deactivateCloakingDevice();
	if (UNIVERSE != nullptr)  UNIVERSE->terminatePostFX(OO_POSTFX_CLOAK);
	if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("cloak-off"), 2);
	playCloakingDeviceOff();
}


/* Scanner fuzziness is entirely cosmetic - it doesn't affect the
 * player's actual target locks */
double PlayerEntity::scannerFuzziness()
{
	double fuzz = 0.0;
	
	/* Fuzziness from ECM bursts */
	if (last_ecm_time > 0.0)
	{
		double since = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) - last_ecm_time;
		if (since < SCANNER_ECM_FUZZINESS)
		{
			fuzz += (SCANNER_ECM_FUZZINESS - since) * (SCANNER_ECM_FUZZINESS - since) * 500.0;
		}
	}
	/* Other causes could go here */
	
	return fuzz;
}


void PlayerEntity::noticeECM()
{
	last_ecm_time = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0);
}


bool PlayerEntity::fireECM()
{
	if (ShipEntity::fireECM())
	{
		ecm_in_operation = YES;
		ecm_start_time = (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0);
		return YES;
	}
	else
	{
		return NO;
	}
}


OOEnergyUnitType PlayerEntity::installedEnergyUnitType()
{
	if (hasEquipmentItem(oo::PList("EQ_NAVAL_ENERGY_UNIT")))  return ENERGY_UNIT_NAVAL;
	if (hasEquipmentItem(oo::PList("EQ_ENERGY_UNIT")))  return ENERGY_UNIT_NORMAL;
	return ENERGY_UNIT_NONE;
}


OOEnergyUnitType PlayerEntity::energyUnitType()
{
	if (hasEquipmentItem(oo::PList("EQ_NAVAL_ENERGY_UNIT")))  return ENERGY_UNIT_NAVAL;
	if (hasEquipmentItem(oo::PList("EQ_ENERGY_UNIT")))  return ENERGY_UNIT_NORMAL;
	if (hasEquipmentItem(oo::PList("EQ_NAVAL_ENERGY_UNIT_DAMAGED")))  return ENERGY_UNIT_NAVAL_DAMAGED;
	if (hasEquipmentItem(oo::PList("EQ_ENERGY_UNIT_DAMAGED")))  return ENERGY_UNIT_NORMAL_DAMAGED;
	return ENERGY_UNIT_NONE;
}


void PlayerEntity::currentWeaponStats()
{
	OOWeaponType currentWeapon = this->currentWeapon();
	// Did find & correct a minor mismatch between player and NPC weapon stats. This is the resulting code - Kaks 20101027
	
	// Basic stats: weapon_damage & weaponRange (weapon_recharge_rate is not used by the player)
	setWeaponDataFromType(currentWeapon);
}


bool PlayerEntity::weaponsOnline()
{
	return weapons_online;
}


void PlayerEntity::setWeaponsOnline(bool newValue)
{
	weapons_online = !!newValue;
	if (!weapons_online)  safeAllMissiles();
}


std::vector<Vector> PlayerEntity::currentLaserOffset()
{
	return laserPortOffset(currentWeaponFacing);
}


bool PlayerEntity::fireMainWeapon()
{
	OOWeaponType weapon_to_be_fired = currentWeapon();

	if (!weaponsOnline())
	{
		return NO;
	}
	
	if (weapon_temp / PLAYER_MAX_WEAPON_TEMP >= WEAPON_COOLING_CUTOUT)
	{
		playWeaponOverheated(currentLaserOffset().at(0));
		if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("weapon-overheat"), 3.0);
		return NO;
	}

	if (isWeaponNone(weapon_to_be_fired))
	{
		return NO;
	}

	currentWeaponStats();

	NSUInteger multiplier = 1;
	if (_multiplyWeapons)
	{
		// multiple fitted
		multiplier = laserPortOffset(currentWeaponFacing).size();
	}
	
	if (energy <= weapon_energy_use * multiplier)
	{
		if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("weapon-out-of-juice"), 3.0);
		return NO;
	}

	using_mining_laser = ((weapon_to_be_fired != nullptr ? weapon_to_be_fired->isMiningLaser() : false) != NO);

	energy -= weapon_energy_use * multiplier;

	switch (currentWeaponFacing)
	{
		case WEAPON_FACING_FORWARD:
			forward_weapon_temp += weapon_shot_temperature * multiplier;
			forward_shot_time = 0.0;
			break;
			
		case WEAPON_FACING_AFT:
			aft_weapon_temp += weapon_shot_temperature * multiplier;
			aft_shot_time = 0.0;
			break;
			
		case WEAPON_FACING_PORT:
			port_weapon_temp += weapon_shot_temperature * multiplier;
			port_shot_time = 0.0;
			break;
			
		case WEAPON_FACING_STARBOARD:
			starboard_weapon_temp += weapon_shot_temperature * multiplier;
			starboard_shot_time = 0.0;
			break;
			
		case WEAPON_FACING_NONE:
			break;
	}
	
	BOOL	weaponFired = NO;
	if (!isWeaponNone(weapon_to_be_fired))
	{
		if (!(weapon_to_be_fired != nullptr ? weapon_to_be_fired->isTurretLaser() : false))
		{
			fireLaserShotInDirection(currentWeaponFacing, (currentWeapon() != nullptr ? currentWeapon()->identifier() : std::optional<std::string>()).value_or(std::string()));
			weaponFired = YES;
		}
		else
		{
			// nothing: compatible with previous versions
		}
	}
	
	if (weaponFired && cloaking_device_active && cloakPassive)
	{
		deactivateCloakingDevice();
	}	
	
	return weaponFired;
}


OOWeaponType PlayerEntity::weaponForFacing(OOWeaponFacing facing)
{
	switch (facing)
	{
		case WEAPON_FACING_FORWARD:
			return forward_weapon_type;
			
		case WEAPON_FACING_AFT:
			return aft_weapon_type;
			
		case WEAPON_FACING_PORT:
			return port_weapon_type;
			
		case WEAPON_FACING_STARBOARD:
			return starboard_weapon_type;
			
		case WEAPON_FACING_NONE:
			break;
	}
	return nil;
}


OOWeaponType PlayerEntity::currentWeapon()
{
	return weaponForFacing(currentWeaponFacing);
}



// Slice 14 of docs/phases/3-slices/PlayerEntity.md (bead oo-m8x1y): hit testing, damage, the doppelganger, the escape capsule, dumping cargo, bounty.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

// override ShipEntity definition to ensure that 
// if shields are still up, always hit the main entity and take the damage
// on the shields
GLfloat PlayerEntity::doesHitLine(HPVector v0, HPVector v1, ::ShipEntity **hitEntity)
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
			hitEntity[0] = oo::ToShip(this);
	}

	bool shields = false;
	if ((w0.z >= 0 && forward_shield > 1) || (w0.z <= 0 && aft_shield > 1))
	{
		shields = true;
	}
	
	for (const oo::EntityHold &seRef : shipSubEntities())	// the -shipSubEntityEnumerator order
	{
		::ShipEntity		*se = oo::ToShip(seRef.get());
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
			if (hitEntity && !shields)
			{
				*hitEntity = se;
			}
		}
	}
	
	return hit_distance;
}


void PlayerEntity::takeEnergyDamage(double amount, Entity *entPart, Entity *otherPart, const std::string &weaponIdentifier)
{
	Entity *ent = entPart;	// the C++ entities (bead oo-9ht.39.18)
	Entity *other = otherPart;
	HPVector		rel_pos;
	OOScalar		d_forward, d_right, d_up;
	BOOL		internal_damage = NO;	// base chance
	
	OO_LOG("player.ship.damage", "Player took damage from {} becauseOf {}", oo::EntityDescription(ent), oo::EntityDescription(other));
	
	if (status() == STATUS_DEAD)  return;
	if (status() == STATUS_ESCAPE_SEQUENCE) return; // if the player has ejected, don't deal more damage
	if (amount == 0.0)  return;
	
	BOOL cascadeWeapon = OOEntityIsCascadeWeapon(entPart);
	BOOL cascading = NO;
	if (cascadeWeapon)
	{
		cascading = cascadeIfAppropriateWithDamageAmount(amount, oo::LiveOwner(ent));
	}
	
	// make sure ent (& its position) is the attacking _ship_/missile !
	if (ent && oo::EntityIsSubEntity(ent)) ent = oo::LiveOwner(ent);
	
	oo::AutoreleaseEntity(oo::RetainEntity(ent));
	oo::AutoreleaseEntity(oo::RetainEntity(other));
	
	rel_pos = (ent != nullptr) ? ent->getPosition() : kZeroHPVector;
	rel_pos = HPvector_subtract(rel_pos, position);
	
	doScriptEvent(OOJSID("shipBeingAttacked"), ent);
	if (oo::EntityIsShip(ent)) { if (oo::ToShip(ent) != nullptr)  oo::ToShip(ent)->doScriptEvent(OOJSID("shipAttackedOther"), this); }

	d_forward = dot_product(HPVectorToVector(rel_pos), v_forward);
	d_right = dot_product(HPVectorToVector(rel_pos), v_right);
	d_up = dot_product(HPVectorToVector(rel_pos), v_up);
	Vector relative = make_vector(d_right,d_up,d_forward);

	playShieldHit(relative, weaponIdentifier);

	// firing on an innocent ship is an offence
	if (oo::EntityIsShip(other))
	{
		broadcastHitByLaserFrom(oo::ToShip(other));
	}

	if (d_forward >= 0)
	{
		forward_shield -= amount;
		if (forward_shield < 0.0)
		{
			amount = -forward_shield;
			forward_shield = 0.0f;
		}
		else
		{
			amount = 0.0;
		}
	}
	else
	{
		aft_shield -= amount;
		if (aft_shield < 0.0)
		{
			amount = -aft_shield;
			aft_shield = 0.0f;
		}
		else
		{
			amount = 0.0;
		}
	}
	
	OOShipDamageType damageType = cascadeWeapon ? kOODamageTypeCascadeWeapon : kOODamageTypeEnergy;
	
	if (amount > 0.0)
	{
		energy -= amount;
		playDirectHit(relative, weaponIdentifier);
		if (ship_temperature < SHIP_MAX_CABIN_TEMP)
		{
			/* Heat increase from energy impacts will never directly cause
			 * overheating - too easy for missile hits to cause an uncredited
			 * death by overheating against NPCs, so same rules for player */
			ship_temperature += amount * (mass > 400000 ? 200000 / mass : 0.5) / heatInsulation();	// SHIP_ENERGY_DAMAGE_TO_HEAT_FACTOR, which named the facade's C++ entity
			if (ship_temperature > SHIP_MAX_CABIN_TEMP)
			{
				ship_temperature = SHIP_MAX_CABIN_TEMP;
			}
		}
	}
	noteTakingDamage(amount, other, damageType);
	if (cascading) energy = 0.0; // explicitly set energy to zero when cascading, in case an oxp raised the energy in noteTakingDamage.
	
	if (energy <= 0.0) //use normal ship temperature calculations for heat damage
	{
		if (oo::EntityIsShip(other))
		{
			if (oo::ToShip(other) != nullptr)  oo::ToShip(other)->noteTargetDestroyed(this);
		}
		
		getDestroyedBy(other, damageType);
	}
	else
	{
		while (amount > 0.0)
		{
			internal_damage = ((ranrot_rand() & PLAYER_INTERNAL_DAMAGE_FACTOR) < amount);	// base chance of damage to systems
			if (internal_damage)
			{
				takeInternalDamage();
			}
			amount -= (PLAYER_INTERNAL_DAMAGE_FACTOR + 1);
		}
	}
}


void PlayerEntity::takeScrapeDamage(double amount, Entity *ent)
{
	HPVector  rel_pos;
	OOScalar  d_forward, d_right, d_up;
	BOOL	internal_damage = NO;	// base chance
	
	if (status() == STATUS_DEAD)  return;
	
	if (amount < 0) 
	{
		OO_LOG("player.ship.damage", "Player took negative scrape damage {:.3f} so we made it positive", amount);
		amount = -amount;
	}
	OO_LOG("player.ship.damage", "Player took {:.3f} scrape damage from {}", amount, oo::EntityDescription(ent));
	
	oo::AutoreleaseEntity(oo::RetainEntity(ent));
	rel_pos = (ent != nullptr) ? ent->getPosition() : kZeroHPVector;
	rel_pos = HPvector_subtract(rel_pos, position);
	// rel_pos is now small
	d_forward = dot_product(HPVectorToVector(rel_pos), v_forward);
	d_right = dot_product(HPVectorToVector(rel_pos), v_right);
	d_up = dot_product(HPVectorToVector(rel_pos), v_up);
	Vector relative = make_vector(d_right,d_up,d_forward);

	playScrapeDamage(relative);
	if (d_forward >= 0)
	{
		forward_shield -= amount;
		if (forward_shield < 0.0)
		{
			amount = -forward_shield;
			forward_shield = 0.0f;
		}
		else
		{
			amount = 0.0;
		}
	}
	else
	{
		aft_shield -= amount;
		if (aft_shield < 0.0)
		{
			amount = -aft_shield;
			aft_shield = 0.0f;
		}
		else
		{
			amount = 0.0;
		}
	}
	
	ShipEntity::takeScrapeDamage(amount, ent);
	
	while (amount > 0.0)
	{
		internal_damage = ((ranrot_rand() & PLAYER_INTERNAL_DAMAGE_FACTOR) < amount);	// base chance of damage to systems
		if (internal_damage)
		{
			takeInternalDamage();
		}
		amount -= (PLAYER_INTERNAL_DAMAGE_FACTOR + 1);
	}
}


void PlayerEntity::takeHeatDamage(double amount)
{
	if (status() == STATUS_DEAD || amount < 0)  return;
	
	// hit the shields first!
	float fwd_amount = (float)(0.5 * amount);
	float aft_amount = (float)(0.5 * amount);

	forward_shield -= fwd_amount;
	if (forward_shield < 0.0)
	{
		fwd_amount = -forward_shield;
		forward_shield = 0.0f;
	}
	else
	{
		fwd_amount = 0.0f;
	}

	aft_shield -= aft_amount;
	if (aft_shield < 0.0)
	{
		aft_amount = -aft_shield;
		aft_shield = 0.0f;
	}
	else
	{
		aft_amount = 0.0f;
	}

	double residual_amount = fwd_amount + aft_amount;
	
	ShipEntity::takeHeatDamage(residual_amount);
}


::ShipEntity *PlayerEntity::createDoppelganger()
{
	::ShipEntity *result = oo::ToShip(oo::AutoreleaseEntity((UNIVERSE != nullptr ? UNIVERSE->newShipWithName(shipDataKey().value_or(""), YES) : (::ShipEntity *)nil)));
	
	if (result != nil)
	{
		if (result != nullptr)  result->setPosition(getPosition());
		if (result != nullptr)  result->setScanClass(CLASS_NEUTRAL);
		if (result != nullptr)  result->setOrientation(normalOrientation());
		if (result != nullptr)  result->setVelocity(getVelocity());
		if (result != nullptr)  result->setSpeed(getFlightSpeed());
		if (result != nullptr)  result->setDesiredSpeed(getFlightSpeed());
		if (result != nullptr)  result->setRoll(flightRoll);
		if (result != nullptr)  result->setBehaviour(BEHAVIOUR_IDLE);
		if (result != nullptr)  result->switchAITo("nullAI.plist");  // fly straight on
		if (result != nullptr)  result->setTemperature(temperature());
		// The proxy's member since bead oo-9ht.183 (a ship of another class, which a proxy definition
		// never makes, did not answer -copyValuesFromPlayer:).
		if (::ProxyPlayerEntity *proxy = dynamic_cast<::ProxyPlayerEntity *>(result))  proxy->copyValuesFromPlayer(this);
	}
	
	return result;
}


::ShipEntity *PlayerEntity::launchEscapeCapsule()
{
	::ShipEntity		*doppelganger = nil;
	::ShipEntity		*escapePod = nil;
	
	if ((UNIVERSE != nullptr ? UNIVERSE->getDisplayGUI() : false)) switchToMainView();	// Clear the F7 screen!
	if (UNIVERSE != nullptr)  UNIVERSE->setViewDirection(VIEW_FORWARD);
	
	if (status() == STATUS_DEAD)  return nil;
	
	/*
		While inside the escape pod, we need to block access to all player.ship properties,
		since we're not supposed to be inside our ship anymore! -- Kaks 20101114
	*/
	
	if (UNIVERSE != nullptr)  UNIVERSE->setBlockJSPlayerShipProps(YES); 	// no player.ship properties while inside the pod!
	// if a specific amount of time has been provided for the rescue, use it now
	if (escape_pod_rescue_time > 0) 
	{
		ship_clock_adjust += escape_pod_rescue_time;
		escape_pod_rescue_time = 0; // reset value
	} 
	else 
	{
		// otherwise, use the default time calc
		ship_clock_adjust += 43200 + 5400 * (ranrot_rand() & 127);	// add up to 8 days until rescue!
	}
	dockingClearanceStatus = DOCKING_CLEARANCE_STATUS_NOT_REQUIRED;
	flightSpeed = fmin(flightSpeed, maxFlightSpeed);
	
	doppelganger = createDoppelganger();
	if (doppelganger)
	{
		if (doppelganger != nullptr)  doppelganger->setVelocity(vector_multiply_scalar(v_forward, flightSpeed));
		if (doppelganger != nullptr)  doppelganger->setSpeed(0.0);
		if (doppelganger != nullptr)  doppelganger->setDesiredSpeed(0.0);
		if (doppelganger != nullptr)  doppelganger->setRoll(0.2 * (randf() - 0.5));
		if (doppelganger != nullptr)  doppelganger->setOwner(this);
		if (doppelganger != nullptr)  doppelganger->setThrust(0); // drifts
		if (UNIVERSE != nullptr)  UNIVERSE->addEntity(doppelganger);
	}

	setFoundTarget(doppelganger); // must do this before setting status
	setStatus(STATUS_ESCAPE_SEQUENCE);	// now set up the escape sequence.


	// must do this before next step or uses BBox of pod, not old ship!
	float sheight = (float)(boundingBox.max.y - boundingBox.min.y);
	position = HPvector_subtract(position, vectorToHPVector(vector_multiply_scalar(v_up, sheight)));
	float sdepth = (float)(boundingBox.max.z - boundingBox.min.z);
	position = HPvector_subtract(position, vectorToHPVector(vector_multiply_scalar(v_forward, sdepth/2.0)));

	// set up you
	escapePod = (UNIVERSE != nullptr ? UNIVERSE->newShipWithName("escape-capsule") : (::ShipEntity *)nil);	// retained
	if (escapePod != nil)
	{
		// FIXME: this should use OOShipType, which should exist. -- Ahruman
		setMesh((escapePod != nullptr ? escapePod->mesh() : (OOMesh *)nullptr));
	}
	
	/* These used to be non-zero, but BEHAVIOUR_IDLE levels off flight
	 * anyway, and inertial velocity is used instead of inertialess
	 * thrust - CIM */
	flightSpeed = 0.0f;
	flightPitch = 0.0f;
	flightRoll = 0.0f;
	flightYaw = 0.0f;
	// and turn off inertialess drive
	thrust = 0.0f;
	

	/*	Add an impulse upwards and backwards to the escape pod. This avoids
		flying straight through the doppelganger in interstellar space or when
		facing the main station/escape target, and generally looks cool.
		-- Ahruman 2011-04-02
	*/
	Vector launchVector = vector_add((doppelganger != nullptr ? doppelganger->getVelocity() : Vector{}),
							vector_add(vector_multiply_scalar(v_up, 15.0f),
									   vector_multiply_scalar(v_forward, -90.0f)));
	setVelocity(launchVector);
	


	// if multiple items providing escape pod, remove the first one
	removeEquipmentItem(equipmentItemProviding("EQ_ESCAPE_POD").value_or(std::string()));	// none: "", as nil was

	
	// set up the standard location where the escape pod will dock.
	target_system_id = system_id;			// we're staying in this system
	info_system_id = system_id;
	setDockTarget((UNIVERSE != nullptr ? UNIVERSE->station() : nullptr));	// we're docking at the main station, if there is one
	
	doScriptEvent(OOJSID("shipLaunchedEscapePod"), escapePod);	// no player.ship properties should be available to script

	// reset legal status
	setBounty(0, kOOLegalStatusReasonEscapePod);
	bounty = 0;

	// new ship, so lose some memory of player actions
	if (ship_kills >= 6400)
	{
		clearRolesFromPlayer(0.1);
	}
	else if (ship_kills >= 2560)
	{
		clearRolesFromPlayer(0.25);
	}
	else
	{
		clearRolesFromPlayer(0.5);
	}	

	// reset trumbles
	if (trumbleCount != 0)  trumbleCount = 1;
	
	// remove cargo
	cargo.clear();
	
	energy = 25;
	if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("escape-sequence"), 4.5);
	resetShotTime();
	
	// need to zero out all facings shot_times too, otherwise we may end up
	// with a broken escape pod sequence - Nikos 20100909
	forward_shot_time = 0.0;
	aft_shot_time = 0.0;
	port_shot_time = 0.0;
	starboard_shot_time = 0.0;
	
	if (escapePod != nullptr)  oo::ReleaseEntity(escapePod);
	
	return doppelganger;
}


void PlayerEntity::dumpCargo()
{
	if (flightSpeed > 4.0 * maxFlightSpeed)
	{
		if (UNIVERSE != nullptr)  UNIVERSE->addMessage(cxx_OOExpandKey("hold-locked"), 3.0);
		return;
	}

	// what -[ShipEntity dumpCargo] did, keeping the commodity it returned (nil for no pod or no type)
	::ShipEntity *jetto = dumpCargoItem(std::nullopt);
	const std::optional<std::string> result = jetto != nil ? (jetto != nullptr ? jetto->commodityType() : std::optional<std::string>()) : std::nullopt;
	if (result.has_value())
	{
		const std::string commodity = (UNIVERSE != nullptr ? UNIVERSE->displayNameForCommodity(*result) : std::optional<std::string>()).value_or(std::string());
		if (UNIVERSE != nullptr)  UNIVERSE->addMessage(ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "commodity-ejected", { { "commodity", oo::PList(commodity) } }), 3.0, YES);
		playCargoJettisioned();
	}
}


void PlayerEntity::rotateCargo()
{
	NSInteger i, n_cargo = cargo.size();
	if (n_cargo == 0)  return;
	
	::ShipEntity *pod = oo::ToShip(oo::RetainEntity(cargo[0].get()));
	const std::optional<std::string> current_contents = (pod != nullptr ? pod->commodityType() : std::optional<std::string>());
	std::optional<std::string> contents;
	// -isEqualToString: with a nil on either side was NO
	const auto sameContents = [&current_contents](const std::optional<std::string> &other) { return other.has_value() && current_contents.has_value() && *other == *current_contents; };
	NSInteger rotates = 0;
	
	do
	{
		cargo.erase(cargo.begin());	// take it from the eject position
		cargo.emplace_back(pod);	// move it to the last position
		if (pod != nullptr)  oo::ReleaseEntity(pod);
		pod = oo::ToShip(oo::RetainEntity(cargo[0].get()));
		contents = (pod != nullptr ? pod->commodityType() : std::optional<std::string>());
		rotates++;
	} while (sameContents(contents)&&(rotates < n_cargo));
	if (pod != nullptr)  oo::ReleaseEntity(pod);
	
	const std::string commodity = (UNIVERSE != nullptr ? UNIVERSE->displayNameForCommodity(contents.value_or(std::string())) : std::optional<std::string>()).value_or(std::string());	// (nil raised in the expansion)
	if (UNIVERSE != nullptr)  UNIVERSE->addMessage(ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "ready-to-eject-commodity", { { "commodity", oo::PList(commodity) } }), 3.0);

	// now scan through the remaining 1..(n_cargo - rotates) places moving similar cargo to the last place
	// this means the cargo gets to be sorted as it is rotated through
	for (i = 1; i < (n_cargo - rotates); i++)
	{
		pod = oo::ToShip(cargo[i].get());
		if (sameContents((pod != nullptr ? pod->commodityType() : std::optional<std::string>())))
		{
			if (pod != nullptr)  oo::ToShip(oo::RetainEntity(pod));
			cargo.erase(cargo.begin() + i--);
			cargo.emplace_back(pod);
			if (pod != nullptr)  oo::ReleaseEntity(pod);
			rotates++;
		}
	}
}


void PlayerEntity::setBounty(OOCreditsQuantity amount)
{
	setBounty(amount, kOOLegalStatusReasonUnknown);
}


void PlayerEntity::setBounty(OOCreditsQuantity amount, OOLegalStatusReason reason)
{
	setBounty(amount, cxx_OOStringFromLegalStatusReason(reason));
}


void PlayerEntity::setBounty(OOCreditsQuantity amount, const std::string &reason)
{
	ooscript::Context context = OOJSAcquireContext();
	
	ooscript::Value amountVal = ooscript::undefinedValue();
	int amountVal2 = (int)amount-(int)legalStatusValue;
	ooscript::newNumberValue(context, amountVal2, &amountVal);

	legalStatusValue = (int)amount; // can't set the new bounty until the size of the change is known

	ooscript::Value reasonVal = OOJSValueFromPList(context, oo::PList(reason));
		
	ShipScriptEvent(context, this, "shipBountyChanged", amountVal, reasonVal);
		
	OOJSRelinquishContext(context);
}



// Slice 15 of docs/phases/3-slices/PlayerEntity.md (bead oo-2lpiu): legal status, offences, bounties collected, internal damage, destruction, ending a scenario, docking and leaving dock.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

OOCreditsQuantity PlayerEntity::getBounty()
{
	return legalStatusValue;
}


int PlayerEntity::getLegalStatus()
{
	return legalStatusValue;
}


void PlayerEntity::markAsOffender(int offence_value)
{
	markAsOffender(offence_value, kOOLegalStatusReasonUnknown);
}


void PlayerEntity::markAsOffender(int offence_value, OOLegalStatusReason reason)
{
	if (!isCloaked())
	{
		ooscript::Context context = OOJSAcquireContext();
	
		ooscript::Value amountVal = ooscript::undefinedValue();
		int amountVal2 = (legalStatusValue | offence_value) - legalStatusValue;
		ooscript::newNumberValue(context, amountVal2, &amountVal);

		legalStatusValue |= offence_value; // can't set the new bounty until the size of the change is known

		ooscript::Value reasonVal = OOJSValueFromLegalStatusReason(context, reason);
		
		ShipScriptEvent(context, this, "shipBountyChanged", amountVal, reasonVal);
		
		OOJSRelinquishContext(context);

	}
}


void PlayerEntity::collectBountyFor(::ShipEntity *other)
{
	if (status() == STATUS_DEAD)  return; // no bounty if we died while trying
	
	if (other == nil || (other != nullptr ? other->getIsSubEntity() : false))  return;
	
	if (other == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr))
	{
		// there is no way the player can destroy the main station
		// and so the explosion will be cancelled, so there shouldn't
		// be a kill award
		return;
	}

	if (isCloaked())
	{
		// no-one knows about it; no award
		return;
	}

	OOCreditsQuantity	score = 10 * (other != nullptr ? other->getBounty() : 0);
	OOScanClass			killClass = (other != nullptr ? other->getScanClass() : OOScanClass{}); // **tgape** change (+line)
	BOOL				killAward = (other != nullptr ? other->countsAsKill() : false);
	
	if ((other != nullptr ? other->isPolice() : false))   // oops, we shot a copper!
	{
		markAsOffender(64, kOOLegalStatusReasonAttackedPolice);
	}
	
	BOOL killIsCargo = ((killClass == CLASS_CARGO) && ((other != nullptr ? other->commodityAmount() : 0) > 0) && !(other != nullptr ? other->getIsHulk() : false));
	if ((killIsCargo) || (killClass == CLASS_BUOY) || (killClass == CLASS_ROCK))
	{
		// EMMSTRAN: no killaward (but full bounty) for tharglets?
		if (!(other != nullptr ? other->hasRole("tharglet") : false))	// okay, we'll count tharglets as proper kills
		{
			score /= 10;	// reduce bounty awarded
			killAward = NO;	// don't award a kill
		}
	}
	
	credits += score;
	
	if (score > 9)
	{
		if (UNIVERSE != nullptr)  UNIVERSE->addDelayedMessage(cxx_OOExpandKey("bounty-awarded", score, credits), 6, 0.15);
	}
	
	if (killAward)
	{
		ship_kills++;
		if ((ship_kills % 256) == 0)
		{
			// congratulations method needs to be delayed a fraction of a second
			if (UNIVERSE != nullptr)  UNIVERSE->addDelayedMessage(OO_DESC("right-on-commander"), 4, 0.2);
		}
	}
}


bool PlayerEntity::takeInternalDamage()
{
	unsigned n_cargo = maxAvailableCargoSpace();
	unsigned n_mass = getMass() / 10000;
	unsigned n_considered = (n_cargo + n_mass) * ship_trade_in_factor / 100; // a lower value of n_considered means more vulnerable to damage.
	unsigned damage_to = n_considered ? (ranrot_rand() % n_considered) : 0;	// n_considered can be 0 for small ships.
	BOOL     result = NO;
	// cargo damage
	if (damage_to < cargo.size())
	{
		::ShipEntity* pod = oo::ToShip(cargo[damage_to].get());
		const std::optional<std::string> cargo_desc = (UNIVERSE != nullptr ? UNIVERSE->displayNameForCommodity((pod != nullptr ? pod->commodityType() : std::optional<std::string>()).value_or("")) : std::optional<std::string>());
		if (!cargo_desc)
			return NO;
		if (UNIVERSE != nullptr)  UNIVERSE->clearPreviousMessage();
		if (UNIVERSE != nullptr)  UNIVERSE->addMessage(oo::str::formatRuntime(OO_DESC("@-destroyed"), { *cargo_desc }), 4.5);
		std::erase(cargo, static_cast<Entity *>(pod));
		return YES;
	}
	else
	{
		damage_to = n_considered - (damage_to + 1);	// reverse the die-roll
	}
	// equipment damage
	::OOEquipmentType	*eqType = nil;
	unsigned damageableCounter = 0;
	GLfloat damageableOdds = 0.0;
	for (const std::string &key : equipmentKeys())	// the -equipmentEnumerator order
	{
		eqType = OOEquipmentType::equipmentTypeWithIdentifier(key).get();
		if ((eqType != nullptr ? eqType->canBeDamaged() : false))
		{
			damageableCounter++;
			damageableOdds += (eqType != nullptr ? eqType->damageProbability() : 0.0f);
		}
	}

	if (damage_to < damageableCounter)
	{
		GLfloat target = randf() * damageableOdds;
		GLfloat accumulator = 0.0;
		std::optional<std::string>	system_key;
		for (const std::string &key : equipmentKeys())
		{
			eqType = OOEquipmentType::equipmentTypeWithIdentifier(key).get();
			accumulator += (eqType != nullptr ? eqType->damageProbability() : 0.0f);
			if (accumulator > target)
			{
				system_key = key;
				break;
			}
		}
		if (!system_key.has_value())
		{
			return NO;
		}

		const std::optional<std::string>	system_name = (eqType != nullptr ? eqType->name() : std::optional<std::string>());
		if (!(eqType != nullptr ? eqType->canBeDamaged() : false) || !system_name.has_value())
		{
			return NO;
		}

		// set the following so removeEquipment works on the right entity
		setScriptTarget(this);
		if (UNIVERSE != nullptr)  UNIVERSE->clearPreviousMessage();
		removeEquipmentItem(*system_key);

		const std::string damagedKey = oo::str::format("%s_DAMAGED", system_key->c_str());
		addEquipmentItem(damagedKey, NO, "damage");	// for possible future repair.
		doScriptEvent(OOJSID("equipmentDamaged"), { oo::PList(*system_key) });

		if (!hasEquipmentItem(oo::PList(*system_name)) && hasEquipmentItem(oo::PList(damagedKey)))
		{
			/*
				Display "foo damaged" message only if no script has
				repaired or removed the equipment item. (If a script does
				either of those and wants a message, it can write it
				itself.)
			*/
			if (UNIVERSE != nullptr)  UNIVERSE->addMessage(oo::str::formatRuntime(OO_DESC("@-damaged"), { *system_name }), 4.5);
		}
		
		/* There used to be a check for docking computers here, but
		 * that didn't cover other ways they might fail in flight, so
		 * it has been moved to the removeEquipment method. */
		return YES;
	}
	//cosmetic damage
	if (((damage_to & 7) == 7)&&(ship_trade_in_factor > 75))
	{
		ship_trade_in_factor--;
		result = YES;
	}
	return result;
}


void PlayerEntity::getDestroyedBy(Entity *whom, OOShipDamageType type)
{
	if (isDocked())  return;	// Can't die while docked. (Doing so would cause breakage elsewhere.)
	
	OO_LOG("player.ship.damage", "Player destroyed by {} due to {}", oo::EntityDescription(whom), cxx_OOStringFromShipDamageType(type));
	
	if (!(UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr ? UNIVERSE->gameController()->playerFileToLoad() : std::optional<std::string>()).has_value())
	{
		if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setPlayerFileToLoad(save_path.value_or(""));	// make sure we load the correct game
	}
	
	energy = 0.0f;
	afterburner_engaged = NO;
	disengageAutopilot();

	if (UNIVERSE != nullptr)  UNIVERSE->setDisplayText(NO);
	if (UNIVERSE != nullptr)  UNIVERSE->setViewDirection(VIEW_AFT);
	
	// Let scripts know the player died.
	noteKilledBy(whom, type); // called before exploding, consistant with npc ships.
	
	becomeLargeExplosion(4.0); // also sets STATUS_DEAD
	moveForward(100.0);
	
	flightSpeed = 160.0f;
	velocity = kZeroVector;
	flightRoll = 0.0;
	flightPitch = 0.0;
	flightYaw = 0.0;
	UNIVERSE->messageGUI()->clear();		// No messages for the dead.
	getSuppressTargetLost();			// No target lost messages when dead.
	playGameOver();
	if (UNIVERSE != nullptr)  UNIVERSE->setBlockJSPlayerShipProps(YES);	// Treat JS player as stale entity.
	removeAllEquipment();			// No scooping / equipment damage when dead.
	loseTargetStatus();
	showGameOver();
}


void PlayerEntity::loseTargetStatus()
{
	if (!UNIVERSE)
		return;
	int			ent_count =		UNIVERSE->n_entities;
	Entity**	uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
	std::vector<Entity *> my_entities(ent_count);
	int i;
	for (i = 0; i < ent_count; i++)
		my_entities[i] = oo::RetainEntity(uni_entities[i]);		//	retained (its object; bead oo-9ht.39.18)
	for (i = 0; i < ent_count ; i++)
	{
		Entity* thing = my_entities[i];
		if (thing->isShip)
		{
			::ShipEntity* ship = oo::ToShip(thing);
			if (this == (ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr))
			{
				if (ship != nullptr)  ship->noteLostTarget();
			}
		}
	}
	for (i = 0; i < ent_count; i++)
	{
		oo::ReleaseEntity(my_entities[i]);		//	released
	}
}


bool PlayerEntity::endScenario(const std::string &key)
{
	if (scenarioKey.has_value() && key == *scenarioKey)
	{
		setStatus(STATUS_RESTART_GAME);
		return YES;
	}
	return NO;
}


void PlayerEntity::enterDock(::StationEntity *station)
{
	OOCParameterAssert(station != nil);
	if (status() == STATUS_DEAD)  return;
	
	setStatus(STATUS_DOCKING);
	setDockedStation(station);
	doScriptEvent(OOJSID("shipWillDockWithStation"), station);

	if (hud != nullptr && !hud->nonlinearScanner())	// (a message to nil did nothing)
	{
		hud->setScannerZoom(1.0);
	}
	ident_engaged = NO;
	afterburner_engaged = NO;
	autopilot_engaged = NO;
	resetAutopilotAI();
	
	cloaking_device_active = NO;
	hyperspeed_engaged = NO;
	hyperspeed_locked = NO;
	safeAllMissiles();
	_primaryTarget = nullptr; // must happen before showing break_pattern to suppress active reticule.
	clearTargetMemory();
	
	scanner_zoom_rate = 0.0f;
	if (UNIVERSE != nullptr)  UNIVERSE->setDisplayText(NO);
	if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setMouseInteractionModeForFlight();
	if (status() == STATUS_LAUNCHING)  return; // a JS script has aborted the docking.
	
	setOrientation(kIdentityQuaternion);	// reset orientation to dock
	if (UNIVERSE != nullptr)  UNIVERSE->setUpBreakPattern(breakPatternPosition(), orientation, YES);
	playDockWithStation();
	if (station != nullptr)  station->noteDockedShip(this);
	
	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->clearKeys();	// try to stop key bounces
}


void PlayerEntity::docked()
{
	::StationEntity *dockedStation = this->dockedStation();
	if (dockedStation == nil)
	{
		setStatus(STATUS_IN_FLIGHT);
		return;
	}
	
	setStatus(STATUS_DOCKED);
	if (UNIVERSE != nullptr)  UNIVERSE->enterGUIViewModeWithMouseInteraction(NO);
	
	loseTargetStatus();
	
	setPosition((dockedStation != nullptr ? dockedStation->getPosition() : HPVector{}));
	setOrientation(kIdentityQuaternion);	// reset orientation to dock
	
	flightRoll = 0.0f;
	flightPitch = 0.0f;
	flightYaw = 0.0f;
	flightSpeed = 0.0f;
	
	hyperspeed_engaged = NO;
	hyperspeed_locked = NO;
	
	forward_shield =	maxForwardShieldLevel();
	aft_shield =		maxAftShieldLevel();
	energy =			maxEnergy;
	weapon_temp =		0.0f;
	ship_temperature =	60.0f;

	setAlertFlag(ALERT_FLAG_DOCKED, YES);

	if ((dockedStation != nullptr ? dockedStation->getLocalMarket() : (OOCommodityMarket *)nullptr) == nil)
	{
		if (dockedStation != nullptr)  dockedStation->initialiseLocalMarket();
	}

	const std::optional<std::string> escapepodReport = processEscapePods();
	addMessageToReport(escapepodReport.value_or(std::string()));
	
	unloadCargoPods();	// fill up the on-ship commodities before...

	// check import status of station
	// escape pods must be cleared before this happens
	if ((dockedStation != nullptr ? dockedStation->getMarketMonitored() : false))
	{
		OOCreditsQuantity oldbounty = getBounty();
		markAsOffender((dockedStation != nullptr ? dockedStation->legalStatusOfManifest(shipCommodityData.get(), NO) : 0), kOOLegalStatusReasonIllegalImports);
		if (getBounty() > oldbounty)
		{
			addRoleToPlayer("trader-smuggler");
		}
	}

	// check contracts
	const std::optional<std::string> passengerAndCargoReport = checkPassengerContracts(); // Is also processing cargo and parcel contracts.
	if (passengerAndCargoReport.has_value())  addMessageToReport(*passengerAndCargoReport);	// (the bridged form took nil as nothing)
		
	if (UNIVERSE != nullptr)  UNIVERSE->setDisplayText(YES);
	
	OOMusicController::sharedController()->stopDockingMusic();
	OOMusicController::sharedController()->playDockedMusic();
	
	// Did we fail to observe traffic control regulations? However, due to the state of emergency,
	// apply no unauthorized docking penalties if a nova is ongoing.
	if ((dockedStation != nullptr ? dockedStation->getRequiresDockingClearance() : false) &&
			!clearedToDock() && !((UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr) != nullptr ? UNIVERSE->sun()->willGoNova() : false))
	{
		penaltyForUnauthorizedDocking();
	}
		
	// apply any pending fines. (No need to check gui_screen as fines is no longer an on-screen message).
	if (dockedStation == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr))
	{
		// TODO: A proper system to allow some OXP stations to have a
		// galcop presence for fines. - CIM 18/11/2012
		if (being_fined && !((UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr) != nullptr ? UNIVERSE->sun()->willGoNova() : false) && !(dockedStation != nullptr ? dockedStation->suppressArrivalReports() : false)) getFined();
	}

	// it's time to check the script - can trigger legacy missions
	if (gui_screen != GUI_SCREEN_MISSION)  checkScript(); // a scripted pilot could have created a mission screen.
	
	OOJSStartTimeLimiterWithTimeLimit(kOOJSLongTimeLimit);
	doScriptEvent(OOJSID("shipDockedWithStation"), dockedStation);
	OOJSStopTimeLimiter();
	if (status() == STATUS_LAUNCHING) return;

	// if we've not switched to the mission screen yet then proceed normally..
	if (gui_screen != GUI_SCREEN_MISSION)
	{
		setGuiToStatusScreen();
	}
	OOCacheManager::sharedCache()->flush();
	OOJavaScriptEngine::sharedEngine()->garbageCollectionOpportunity(YES);
	
	// When a mission screen is started, any on-screen message is removed immediately.
	doWorldEventUntilMissionScreen(OOJSID("missionScreenOpportunity"));	// also displays docking reports first.
}


void PlayerEntity::leaveDock(::StationEntity *station)
{
	if (station == nil)  return;
	OOCParameterAssert(station == dockedStation());
	
	// ensure we've not left keyboard entry on
	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->allowStringInput(NO);
	
	if (gui_screen == GUI_SCREEN_MISSION)
	{
		UNIVERSE->getGui()->clearBackground();
		if (_missionWithCallback)
		{
			doMissionCallback();
		}
		// notify older scripts, but do not trigger missionScreenOpportunity.
		doWorldEventUntilMissionScreen(OOJSID("missionScreenEnded"));
	}
	
	if ((station != nullptr ? station->getMarketMonitored() : false))
	{
		// 'leaving with those guns were you sir?'
		OOCreditsQuantity oldbounty = getBounty();
		markAsOffender((station != nullptr ? station->legalStatusOfManifest(shipCommodityData.get(), YES) : 0), kOOLegalStatusReasonIllegalExports);
		if (getBounty() > oldbounty)
		{
			addRoleToPlayer("trader-smuggler");
		}
	}
	OOGUIScreenID	oldScreen = gui_screen;
	gui_screen = GUI_SCREEN_MAIN;
	noteGUIDidChangeFrom(oldScreen, gui_screen);

	if (hud != nullptr && !hud->nonlinearScanner())	// (a message to nil did nothing)
	{
		hud->setScannerZoom(1.0);
	}
	loadCargoPods();
	// do not do anything that calls JS handlers between now and calling
	// [station launchShip] below, or the cargo returned by JS may be off
	// CIM - 3.2.2012
	
	// clear the way
	if (station != nullptr)  station->autoDockShipsOnApproach();
	if (station != nullptr)  station->clearDockingCorridor();

//	[self setAlertFlag:ALERT_FLAG_DOCKED to:NO];
	clearAlertFlags();
	setDockingClearanceStatus(DOCKING_CLEARANCE_STATUS_NONE);
	
	scanner_zoom_rate = 0.0f;
	currentWeaponFacing = WEAPON_FACING_FORWARD;
	currentWeaponStats();
	
	forward_weapon_temp = 0.0f;
	aft_weapon_temp = 0.0f;
	port_weapon_temp = 0.0f;
	starboard_weapon_temp = 0.0f;
	
	forward_shield = maxForwardShieldLevel();
	aft_shield = maxAftShieldLevel();

	clearTargetMemory();
	setShowDemoShips(NO);
	if (UNIVERSE != nullptr)  UNIVERSE->setDisplayText(NO);
	if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setMouseInteractionModeForFlight();

	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->clearKeys();	// try to stop keybounces
	
	if (isMouseControlOn())
	{
		if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->resetMouse();
	}
	
	OOMusicController::sharedController()->stop();

	if (UNIVERSE != nullptr)  UNIVERSE->forceWitchspaceEntries();
	ship_clock_adjust += 600.0;			// 10 minutes to leave dock
	velocity = kZeroVector; // just in case

	if (station != nullptr)  station->launchShip(this);

	launchRoll = -flightRoll; // save the station's spin. (inverted for player)
	flightRoll = 0; // don't spin when showing the break pattern.
	if (UNIVERSE != nullptr)  UNIVERSE->setUpBreakPattern(breakPatternPosition(), orientation, YES);

	setDockedStation(nullptr);
	
	suppressAegisMessages = YES;
	checkForAegis();
	suppressAegisMessages = NO;
	ident_engaged = NO;
	
	if (UNIVERSE != nullptr)  UNIVERSE->removeDemoShips();
	// MKW - ensure GUI Screen ship is removed
	demoShip = nullptr;
	
	playLaunchFromStation();
}



// Slice 16 of docs/phases/3-slices/PlayerEntity.md (bead oo-vqjjb): witchspace: start, end, checklist, jump type and distance, fuel, galactic and wormhole jumps.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

void PlayerEntity::witchStart()
{
	// chances of entering witchspace with autopilot on are very low, but as Berlios bug #18307 has shown us, entirely possible
	// so in such cases we need to ensure that at least the docking music stops playing
	if (autopilot_engaged)  disengageAutopilot();
	
	if (hud != nullptr && !hud->nonlinearScanner())	// (a message to nil did nothing)
	{
		hud->setScannerZoom(1.0);
	}
	safeAllMissiles();
	
	OOViewID	previousViewDirection = (UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{});
	if (UNIVERSE != nullptr)  UNIVERSE->setViewDirection(VIEW_FORWARD);
	noteSwitchToView(VIEW_FORWARD, previousViewDirection); // notifies scripts of the switch
	
	currentWeaponFacing = WEAPON_FACING_FORWARD;
	currentWeaponStats();

	transitionToAegisNone();
	suppressAegisMessages=YES;
	hyperspeed_engaged = NO;
	
	if (primaryTarget() != nil)
	{
		noteLostTarget();	// losing target? Fire lost target event!
		_primaryTarget = nullptr;
	}
	
	scanner_zoom_rate = 0.0f;
	if (UNIVERSE != nullptr)  UNIVERSE->setDisplayText(NO);
	
	if ( !getWormhole() && !galactic_witchjump)	// galactic hyperspace does not generate a wormhole
	{
		OO_LOG(cxx_kOOLogInconsistentState, "{}", "Internal Error : Player entering witchspace with no wormhole.");
	}
	if (UNIVERSE != nullptr)  UNIVERSE->allShipsDoScriptEvent(OOJSID("playerWillEnterWitchspace"), "PLAYER WITCHSPACE");
	
	// set the new market seed now!
	// reseeding the RNG should be completely unnecessary here
//	ranrot_srand((uint32_t)oo::date::timeIntervalSince1970());	// seed randomiser by time
	market_rnd = ranrot_rand() & 255;						// random factor for market values is reset
}


void PlayerEntity::witchEnd()
{
	if (UNIVERSE != nullptr)  UNIVERSE->setSystemTo(system_id);
	galaxy_coordinates = ((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getCoordinatesForSystem(system_id, galaxy_number) : NSMakePoint(0, 0));

	if (UNIVERSE != nullptr)  UNIVERSE->setUpUniverseFromWitchspace();
	if ((UNIVERSE != nullptr ? UNIVERSE->planet() : nullptr) != nullptr)  UNIVERSE->planet()->update(2.34375 * market_rnd);	// from 0..10 minutes
	if ((UNIVERSE != nullptr ? UNIVERSE->station() : nullptr) != nullptr)  UNIVERSE->station()->update(2.34375 * market_rnd);	// from 0..10 minutes
	
	chart_centre_coordinates = galaxy_coordinates;
	target_chart_centre = chart_centre_coordinates;
}


bool PlayerEntity::witchJumpChecklist(bool isGalacticJump)
{
	// Perform this check only when doing the actual jump
	if (status() == STATUS_WITCHSPACE_COUNTDOWN)
	{
		// check nearby masses
		//UPDATE_STAGE("checking for mass blockage");
		::ShipEntity* blocker = oo::ToShip((UNIVERSE != nullptr ? UNIVERSE->entityForUniversalID(checkShipsInVicinityForWitchJumpExit()) : nullptr));
		if (blocker)
		{
			if (UNIVERSE != nullptr)  UNIVERSE->clearPreviousMessage();
			const std::string blockerName = (blocker != nullptr ? blocker->getName() : std::optional<std::string>()).value_or(std::string());	// (nil raised in the expansion)
			if (UNIVERSE != nullptr)  UNIVERSE->addMessage(ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "witch-blocked", { { "blockerName", oo::PList(blockerName) } }), 4.5);
			playWitchjumpBlocked();
			setStatus(STATUS_IN_FLIGHT);
			ShipScriptEventNoCx(this, "playerJumpFailed", OOJSSTR("blocked"));
			return NO;
		}
	}

	// For galactic hyperspace jumps we skip the remaining checks
	if (isGalacticJump)
	{
		return YES;
	}

	// Check we're not jumping into the current system
	if (!(UNIVERSE != nullptr ? UNIVERSE->inInterstellarSpace() : false) && system_id == target_system_id)
	{
		//dont allow player to hyperspace to current location.
		//Note interstellar space will have a system_seed place we came from
		if (UNIVERSE != nullptr)  UNIVERSE->clearPreviousMessage();
		if (UNIVERSE != nullptr)  UNIVERSE->addMessage(cxx_OOExpandKey("witch-no-target"), 4.5);
		if (status() == STATUS_WITCHSPACE_COUNTDOWN)
		{
			playWitchjumpInsufficientFuel();
			setStatus(STATUS_IN_FLIGHT);
			ShipScriptEventNoCx(this, "playerJumpFailed", OOJSSTR("no target"));
		}
		else  playHyperspaceNoTarget();

		return NO;
	}

	// check max distance permitted
	if (hyperspaceJumpDistance() > maxHyperspaceDistance())
	{
		if (UNIVERSE != nullptr)  UNIVERSE->clearPreviousMessage();
		if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("witch-too-far"), 4.5);
		if (status() == STATUS_WITCHSPACE_COUNTDOWN)
		{
			playWitchjumpDistanceTooGreat();
			setStatus(STATUS_IN_FLIGHT);
			ShipScriptEventNoCx(this, "playerJumpFailed", OOJSSTR("too far"));
		}
		else  playHyperspaceDistanceTooGreat();
		
		return NO;
	}

	// check fuel level
	if (!hasSufficientFuelForJump())
	{
		if (UNIVERSE != nullptr)  UNIVERSE->clearPreviousMessage();
		if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("witch-no-fuel"), 4.5);
		if (status() == STATUS_WITCHSPACE_COUNTDOWN)
		{
			playWitchjumpInsufficientFuel();
			setStatus(STATUS_IN_FLIGHT);
			ShipScriptEventNoCx(this, "playerJumpFailed", OOJSSTR("insufficient fuel"));
		}
		else  playHyperspaceNoFuel();
		
		return NO;
	}

	// All checks passed
	return YES;
}


void PlayerEntity::setJumpType(bool isGalacticJump)
{
	if (isGalacticJump)
	{
		galactic_witchjump = YES;
	}
	else
	{
		galactic_witchjump = NO;
	}
}


double PlayerEntity::hyperspaceJumpDistance()
{
	NSPoint targetCoordinates = PointFromCoordinates(((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getProperty("coordinates", nextHopTargetSystemID(), galaxy_number) : oo::PList()));
	return distanceBetweenPlanetPositions(targetCoordinates.x,targetCoordinates.y,galaxy_coordinates.x,galaxy_coordinates.y);
}


OOFuelQuantity PlayerEntity::fuelRequiredForJump()
{
	return 10.0 * MAX(0.1, hyperspaceJumpDistance());
}


bool PlayerEntity::hasSufficientFuelForJump()
{
	return fuel >= fuelRequiredForJump();
}


void PlayerEntity::noteCompassLostTarget()
{
	if (getHud() != nullptr && getHud()->isCompassActive())
	{
		// "the compass, it says we're lost!" :)
		ooscript::Context context = OOJSAcquireContext();
		ooscript::Value jsmode = OOJSValueFromCompassMode(context, getCompassMode());
		ShipScriptEvent(context, this, "compassTargetChanged", ooscript::undefinedValue(), jsmode);
		OOJSRelinquishContext(context);
		
		getHud()->setCompassActive(NO);	// ensure a target change when returning to normal space.
	}
}


void PlayerEntity::enterGalacticWitchspace()
{
	if (!witchJumpChecklist(true))
		return;


	OOGalaxyID destGalaxy = galaxy_number + 1;
	if (EXPECT_NOT(destGalaxy >= OO_GALAXIES_AVAILABLE))
	{
		destGalaxy = 0;
	}


	setStatus(STATUS_ENTERING_WITCHSPACE);
	ooscript::Context context = OOJSAcquireContext();
	setJumpCause(std::string("galactic jump"));
	setPreviousSystemID(currentSystemID());
	ShipScriptEvent(context, this, "shipWillEnterWitchspace", ooscript::stringValue(ooscript::internString(context, jumpCause().value_or(std::string()).c_str())), ooscript::int32Value(destGalaxy));
	OOJSRelinquishContext(context);

	noteCompassLostTarget();

	witchStart();
	
	if (UNIVERSE != nullptr)  UNIVERSE->removeAllEntitiesExceptPlayer();
	
	// remove any contracts and parcels for the old galaxy
	contracts.clear();

	parcels.clear();
	
	// remove any mission destinations for the old galaxy
	missionDestinations.clear();
	
	// expire passenger contracts for the old galaxy
	{
		unsigned i;
		for (i = 0; i < passengers.size(); i++)
		{
			// set the expected arrival time to now, so they storm off the ship at the first port
			oo::PList::Dict passenger_info = passengers[i].isDict() ? *passengers[i].getIf<oo::PList::Dict>() : oo::PList::Dict();
			passenger_info[std::string(CONTRACT_KEY_ARRIVAL_TIME)] = oo::PList(ship_clock);	// +numberWithDouble:
			passengers[i] = oo::PList(std::move(passenger_info));
		}
	}

	// clear a lot of memory of player actions
	if (ship_kills >= 6400)
	{
		clearRolesFromPlayer(0.25);
	}
	else if (ship_kills >= 2560)
	{
		clearRolesFromPlayer(0.5);
	}
	else
	{
		clearRolesFromPlayer(0.9);
	}	
	roleWeightFlags.clear();
	roleSystemList.clear();
	
	// may be more than one item providing this
	removeEquipmentItem(equipmentItemProviding("EQ_GAL_DRIVE").value_or(std::string()));	// none: "", as nil was
	
	galaxy_number = destGalaxy;

	if (UNIVERSE != nullptr)  UNIVERSE->setGalaxyTo(galaxy_number);

	// Choose the galactic hyperspace behaviour. Refers to where we may actually end up after an intergalactic jump.
	// The default behaviour is that the player cannot arrive on unreachable or isolated systems. The options
	// in planetinfo.plist, galactic_hyperspace_behaviour key can be used to allow arrival even at unreachable systems,
	// or at fixed coordinates on the galactic chart. The key galactic_hyperspace_fixed_coords in planetinfo.plist is
	// used in the fixed coordinates case and specifies the exact coordinates for the intergalactic jump.
	switch (galacticHyperspaceBehaviour)
	{
		case GALACTIC_HYPERSPACE_BEHAVIOUR_FIXED_COORDINATES:			
			system_id = (UNIVERSE != nullptr ? UNIVERSE->findSystemNumberAtCoords(galacticHyperspaceFixedCoords, galaxy_number, YES) : 0);
			break;
		case GALACTIC_HYPERSPACE_BEHAVIOUR_ALL_SYSTEMS_REACHABLE:
			system_id = (UNIVERSE != nullptr ? UNIVERSE->findSystemNumberAtCoords(galaxy_coordinates, galaxy_number, YES) : 0);
			break;
		case GALACTIC_HYPERSPACE_BEHAVIOUR_STANDARD:
		default:
			// instead find a system connected to system 0 near the current coordinates...
			system_id = (UNIVERSE != nullptr ? UNIVERSE->findConnectedSystemAtCoords(galaxy_coordinates, galaxy_number) : 0);
			break;
	}
	target_system_id = system_id;
	info_system_id = system_id;
	
	setBounty(0, kOOLegalStatusReasonNewGalaxy);	// let's make a fresh start!
	cursor_coordinates = PointFromCoordinates(((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getProperty("coordinates", system_id, galaxy_number) : oo::PList()));

	witchEnd(); // sets coordinates, calls exiting witchspace JS events
}


// now with added misjump goodness!
// If the wormhole generator misjumped, the player's ship misjumps too. Kaks 20110211
void PlayerEntity::enterWormhole(::WormholeEntity *w_hole)
{
	if (status() == STATUS_ENTERING_WITCHSPACE
			|| status() == STATUS_EXITING_WITCHSPACE)
	{
		return; // has already entered a different wormhole
	}
	BOOL misjump = scriptedMisjump() || (w_hole != nullptr ? w_hole->withMisjump() : false) || flightPitch == max_flight_pitch || randf() > 0.995;
	wormholeObject.leak();	// a wormhole held here was dropped without a release, as before (bead oo-5q11i keeps that)
	wormholeObject = oo::EntityHold(w_hole);	// held (its Objective-C object, bead oo-9ht.112; a hold since bead oo-xn1j1)
	wormhole = w_hole;
	addScannedWormhole(wormhole);
	setStatus(STATUS_ENTERING_WITCHSPACE);
	ooscript::Context context = OOJSAcquireContext();
	setJumpCause("wormhole");
	setPreviousSystemID(currentSystemID());
	ShipScriptEvent(context, this, "shipWillEnterWitchspace", ooscript::stringValue(ooscript::internString(context, jumpCause().value_or("").c_str())), ooscript::int32Value((w_hole != nullptr ? w_hole->getDestination() : 0)));
	OOJSRelinquishContext(context);
	if (scriptedMisjump()) 
	{
		misjump = YES; // a script could just have changed this to true;
	}
#ifdef OO_DUMP_PLANETINFO
	misjump = NO;
#endif
	if (misjump && scriptedMisjumpRange() != 0.5)
	{
		if (w_hole != nullptr)  w_hole->setMisjumpWithRange(scriptedMisjumpRange()); // overrides wormholes, if player also had non-default scriptedMisjumpRange
	}
	witchJumpTo((w_hole != nullptr ? w_hole->getDestination() : 0), misjump);
}


void PlayerEntity::enterWitchspace()
{
	if (!witchJumpChecklist(false))  return;
	
	OOSystemID jumpTarget = nextHopTargetSystemID();

	//  perform any check here for forced witchspace encounters
	unsigned malfunc_chance = 253;
	if (ship_trade_in_factor < 80)
	{
		malfunc_chance -= (1 + ranrot_rand() % (81-ship_trade_in_factor)) / 2;	// increase chance of misjump in worn-out craft
	}
	else if (ship_trade_in_factor >= 100)
	{
		malfunc_chance = 256; // force no misjumps on first jump
	}

#ifdef OO_DUMP_PLANETINFO
	BOOL misjump = NO; // debugging
#else
	BOOL malfunc = ((ranrot_rand() & 0xff) > malfunc_chance);
	// 75% of the time a malfunction means a misjump
	BOOL misjump = scriptedMisjump() || (flightPitch == max_flight_pitch) || (malfunc && (randf() > 0.75));

	if (malfunc && !misjump)
	{
		// some malfunctions will start fuel leaks, some will result in no witchjump at all.
		if (takeInternalDamage())  // Depending on ship type and loaded cargo, this will be true for 20 - 50% of the time.
		{
			playWitchjumpFailure();
			setStatus(STATUS_IN_FLIGHT);
			ShipScriptEventNoCx(this, "playerJumpFailed", OOJSSTR("malfunction"));
			return;
		}
		else
		{
			setFuelLeak(oo::str::format("%f", (randf() + randf()) * 5.0));
		}
	}
#endif	

	// From this point forward we are -definitely- witchjumping
	
	// burn the full fuel amount to create the wormhole
	fuel -= fuelRequiredForJump();
	
	// Create the players' wormhole
	{
		// +alloc/-init...: a new C++ wormhole and its Objective-C object, +1 (bead oo-9ht.112).
		oo::Ref<WormholeEntity> whRef = oo::makeRef<WormholeEntity>();
		wormholeObject.leak();	// a wormhole held here was dropped without a release, as before (bead oo-5q11i keeps that)
		wormholeObject = oo::EntityHold(oo::MadeEntity(whRef));
		whRef->initWormholeTo(jumpTarget, this);
		wormhole = whRef.get();
	}
	if (UNIVERSE != nullptr)  UNIVERSE->addEntity(wormhole); // Add new wormhole to Universe to let other ships target it. Required for ships following the player.
	addScannedWormhole(wormhole);
	
	setStatus(STATUS_ENTERING_WITCHSPACE);
	ooscript::Context context = OOJSAcquireContext();
	setJumpCause(std::string("standard jump"));
	setPreviousSystemID(currentSystemID());
	ShipScriptEvent(context, this, "shipWillEnterWitchspace", ooscript::stringValue(ooscript::internString(context, jumpCause().value_or(std::string()).c_str())), ooscript::int32Value(jumpTarget));
	OOJSRelinquishContext(context);

	updateSystemMemory();
	NSUInteger legality = legalStatusOfCargoList();
	OOCargoQuantity maxSpace = maxAvailableCargoSpace();
	OOCargoQuantity availSpace = availableCargoSpace();
	if (roleWeightFlags.contains("bought-legal"))
	{
		if (maxSpace != availSpace)
		{
			addRoleToPlayer("trader");
			if (maxSpace - availSpace > 20 || availSpace == 0)
			{
				if (legality == 0)
				{
					addRoleToPlayer("trader");
				}
			}
		}
	}
	if (roleWeightFlags.contains("bought-illegal"))
	{
		if (maxSpace != availSpace && legality > 0)
		{
			addRoleToPlayer("trader-smuggler");
			if (maxSpace - availSpace > 20 || availSpace == 0)
			{
				if (legality >= 20 || legality >= maxSpace)
				{
					addRoleToPlayer("trader-smuggler");
				}
			}
		}
	}
	roleWeightFlags.clear();

	noteCompassLostTarget();
	if (scriptedMisjump()) 
	{
		misjump = YES; // a script could just have changed this to true;
	}
	if (misjump)
	{
		if (wormhole != nullptr)  wormhole->setMisjumpWithRange(scriptedMisjumpRange());
	}
	witchJumpTo(jumpTarget, misjump);
}


void PlayerEntity::witchJumpTo(OOSystemID sTo, bool misjump)
{
	witchStart();
	if (info_system_id == system_id)
	{
		setInfoSystemID(sTo, YES);
	}
	//wear and tear on all jumps (inc misjumps, failures, and wormholes)
	if (2 * market_rnd < ship_trade_in_factor)
	{
		// every eight jumps or so drop the price down towards 75%
		adjustTradeInFactorBy(-(1 + (market_rnd & 3)));
	}
	
	// set clock after "playerWillEnterWitchspace" and before  removeAllEntitiesExceptPlayer, to allow escorts time to follow their mother. 
	NSPoint destCoords = PointFromCoordinates(((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getProperty("coordinates", sTo, galaxy_number) : oo::PList()));
	double distance = distanceBetweenPlanetPositions(destCoords.x,destCoords.y,galaxy_coordinates.x,galaxy_coordinates.y);
	
	// if we just escaped a system gone nova, make sure all nova parameters are reset
	::OOSunEntity *theSun = (UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr);
	if (theSun && (theSun != nullptr ? theSun->goneNova() : false))
	{
		if (theSun != nullptr)  theSun->resetNova();
	}
	
	if (UNIVERSE != nullptr)  UNIVERSE->removeAllEntitiesExceptPlayer();
	if (!misjump)
	{
		ship_clock_adjust += distance * distance * 3600.0;
		setSystemID(sTo);
		setBounty((legalStatusValue/2), kOOLegalStatusReasonNewSystem);	// 'another day, another system'
		witchEnd();
		if (market_rnd < 8) erodeReputation();		// every 32 systems or so, drop back towards 'unknown'
	}
	else
	{
		// Misjump: move halfway there!
		// misjumps do not change legal status.
		if (randf() < 0.1) erodeReputation();		// once every 10 misjumps - should be much rarer than successful jumps!

		if (wormhole != nullptr)  wormhole->setMisjump(); 
		// just in case, but this has usually been set already

		// and now the wormhole has travel time and coordinates calculated
		// so rather than duplicate the calculation we'll just ask it...
		NSPoint dest = (wormhole != nullptr ? wormhole->destinationCoordinates() : NSPoint{});
		galaxy_coordinates.x = dest.x;
		galaxy_coordinates.y = dest.y;

		ship_clock_adjust += (wormhole != nullptr ? wormhole->travelTime() : 0.0);

		playWitchjumpMisjump();
		if (UNIVERSE != nullptr)  UNIVERSE->setUpUniverseFromMisjump();
	}
}



// Slice 17 of docs/phases/3-slices/PlayerEntity.md (bead oo-6tuef): leaving witchspace, the status screen, the equipment list, primed and fast equipment, weapon types.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

void PlayerEntity::leaveWitchspace()
{
	double		d1 = SCANNER_MAX_RANGE * ((Ranrot() & 255)/256.0 - 0.5);
	HPVector		pos = (UNIVERSE != nullptr ? UNIVERSE->getWitchspaceExitPosition() : HPVector{});		// no need to reset the PRNG
	Quaternion	q1;
	HPVector		whpos, exitpos;

	double min_d1 = (UNIVERSE != nullptr ? UNIVERSE->safeWitchspaceExitDistance() : 0.0f);
	quaternion_set_random(&q1);
	if (abs((int)d1) < min_d1)
	{
		d1 += ((d1 > 0.0)? min_d1: -min_d1); // not too close to the buoy.
	}
	HPVector		v1 = HPvector_forward_from_quaternion(q1);
	exitpos = HPvector_add(pos, HPvector_multiply_scalar(v1, d1)); // randomise exit position
	position = exitpos;
	setOrientation((UNIVERSE != nullptr ? UNIVERSE->getWitchspaceExitRotation() : Quaternion{}));

	// While setting the wormhole position to the player position looks very nice for ships following the player, 
	// the more common case of the player following other ships, the player tends to
	// ram the back of the ships, or even jump on top of is when the ship jumped without initial speed, which is messy. 
	// To avoid this problem, a small wormhole displacement is added.
	if (wormhole)	// will be nil for galactic jump
	{
		if ((wormhole != nullptr ? wormhole->getShipsInTransit() : oo::PList()).count() > 0)
		{
			// player is not allone in his wormhole, synchronise player and wormhole position.
			double	wh_arrival_time = ((PLAYER != nullptr ? PLAYER->clockTimeAdjusted() : 0.0) - (wormhole != nullptr ? wormhole->arrivalTime() : 0.0));
			if (wh_arrival_time > 0)
			{
				// Player is following other ship 
				whpos = HPvector_add(exitpos, vectorToHPVector(vector_multiply_scalar(forwardVector(), 1000.0f)));
				if (wormhole != nullptr)  wormhole->setContainsPlayer(YES);
			}
			else
			{
				// Player is the leadship 
				whpos = HPvector_add(exitpos, vectorToHPVector(vector_multiply_scalar(forwardVector(), -500.0f)));
				// so it won't contain the player by the time they exit
				if (wormhole != nullptr)  wormhole->setExitSpeed(maxFlightSpeed*WORMHOLE_LEADER_SPEED_FACTOR);
			} 

			HPVector distance = HPvector_subtract(whpos, pos);
			if (HPmagnitude2(distance) < min_d1*min_d1 ) // within safety distance from the buoy?
			{
				// the wormhole is to close to the buoy. Move both player and wormhole away from it in the x-y plane.
				distance.z = 0;
				distance = HPvector_multiply_scalar(HPvector_normal(distance), min_d1);
				whpos = HPvector_add(whpos, distance);
				position = HPvector_add(position, distance);
			}
			if (wormhole != nullptr)  wormhole->setExitPosition(whpos);
		}
		else
		{
			// no-one else in the wormhole
			if (wormhole != nullptr)  wormhole->setExitSpeed(maxFlightSpeed*WORMHOLE_LEADER_SPEED_FACTOR);
		}
	}
	/* there's going to be a slight pause at this stage anyway;
	 * there's also going to be a lot of stale ship scripts. Force a
	 * garbage collection while we have chance. - CIM */
	OOJavaScriptEngine::sharedEngine()->garbageCollectionOpportunity(YES);
	flightSpeed = wormhole ? (wormhole != nullptr ? wormhole->exitSpeed() : 0.0) : fmin(maxFlightSpeed,50.0f);
	wormholeObject = nullptr;	// OK even if nil
	wormhole = nullptr;

	flightRoll = 0.0f;
	flightPitch = 0.0f;
	flightYaw = 0.0f;

	velocity = kZeroVector;
	setStatus(STATUS_EXITING_WITCHSPACE);
	gui_screen = GUI_SCREEN_MAIN;
	being_fined = NO;				// until you're scanned by a copper!
	clearTargetMemory();
	setShowDemoShips(NO);
	if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setMouseInteractionModeForFlight();
	if (UNIVERSE != nullptr)  UNIVERSE->setDisplayText(NO);
	if (UNIVERSE != nullptr)  UNIVERSE->setWitchspaceBreakPattern(YES);
	playExitWitchspace();
	if (currentSystemID() >= 0)
	{
		if (std::find(roleSystemList.begin(), roleSystemList.end(), currentSystemID()) == roleSystemList.end())
		{
			// going somewhere new?
			clearRoleFromPlayer(NO);
		}
	}
	
	if (galactic_witchjump)
	{
		doScriptEvent(OOJSID("playerEnteredNewGalaxy"), { oo::PList::unsignedInteger(galaxy_number) });
	}
	
	const std::optional<std::string> jumpCause = this->jumpCause();
	doScriptEvent(OOJSID("shipWillExitWitchspace"), { jumpCause.has_value() ? oo::PList(*jumpCause) : oo::PList() });
	if (UNIVERSE != nullptr)  UNIVERSE->setUpBreakPattern(breakPatternPosition(), orientation, NO);
}


void PlayerEntity::setGuiToStatusScreen()
{
	std::optional<std::string>	systemName;
	std::optional<std::string>	targetSystemName;
	std::string		text;
	
	::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	OOGUIScreenID	oldScreen = gui_screen;
	if (oldScreen != GUI_SCREEN_STATUS)
	{
		noteGUIWillChangeTo(GUI_SCREEN_STATUS);
	}

	gui_screen = GUI_SCREEN_STATUS;
	BOOL			guiChanged = (oldScreen != gui_screen);
	
	if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setMouseInteractionModeForUIWithMouseInteraction(NO);
	
	// Both system_seed & target_system_seed are != nil at all times when this function is called.
	
	systemName = (UNIVERSE != nullptr ? UNIVERSE->inInterstellarSpace() : false) ? OO_DESC("interstellar-space") : (UNIVERSE != nullptr ? UNIVERSE->getSystemName(system_id) : std::optional<std::string>());
	if (isDocked() && dockedStation() != (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr))
	{
		systemName = oo::str::format("%s : %s", systemName.value_or("(null)").c_str(), (dockedStation() != nullptr ? dockedStation()->getDisplayName() : std::optional<std::string>()).value_or("(null)").c_str());
	}

	targetSystemName =	(UNIVERSE != nullptr ? UNIVERSE->getSystemName(target_system_id) : std::optional<std::string>());
	oo::PList systemInfo = ((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getPropertiesForSystem(target_system_id, galaxy_number) : oo::PList());
	NSInteger concealment = systemInfo.get<int>("concealment", OO_SYSTEMCONCEALMENT_NONE);
	if (concealment >= OO_SYSTEMCONCEALMENT_NONAME) targetSystemName = OO_DESC("status-unknown-system");

	OOSystemID nextHop = nextHopTargetSystemID();
	if (nextHop != target_system_id) {
		std::optional<std::string> nextHopSystemName = (UNIVERSE != nullptr ? UNIVERSE->getSystemName(nextHop) : std::optional<std::string>());
		systemInfo = ((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getPropertiesForSystem(nextHop, galaxy_number) : oo::PList());
		concealment = systemInfo.get<int>("concealment", OO_SYSTEMCONCEALMENT_NONE);
		if (concealment >= OO_SYSTEMCONCEALMENT_NONAME) nextHopSystemName = OO_DESC("status-unknown-system");
		// (a nil name raised in the expansion)
		targetSystemName = ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "status-hyperspace-system-multi",
			{ { "targetSystemName", oo::PList(targetSystemName.value_or(std::string())) }, { "nextHopSystemName", oo::PList(nextHopSystemName.value_or(std::string())) } });
	}

	// GUI stuff
	{
		const std::optional<std::string>	shipName = getDisplayName();
		std::optional<std::string>	legal_desc, rating_desc,
							alert_desc, fuel_desc,
							credits_desc;
		
		OOGUIRow			i;
		OOGUITabSettings 	tab_stops;
		tab_stops[0] = 20;
		tab_stops[1] = 160;
		tab_stops[2] = 290;
		gui->overrideTabs(tab_stops, cxx_kGuiStatusTabs, 3);
		gui->setTabStops(tab_stops);
		
		const std::string	lightYearsDesc = OO_DESC("status-light-years-desc");

		legal_desc = cxx_OODisplayStringFromLegalStatus(legalStatusValue);
		rating_desc = cxx_KillCountToRatingAndKillString(ship_kills);
		alert_desc = cxx_OODisplayStringFromAlertCondition(getAlertCondition());
		fuel_desc = oo::str::format("%.1f %s", fuel/10.0, lightYearsDesc.c_str());
		credits_desc = cxx_OOCredits(credits);

		gui->clearAndKeepBackground(!guiChanged);
		text = OO_DESC("status-commander-@");
		gui->setTitle(oo::str::formatRuntime(text, { commanderName().value_or("(null)") }));

		gui->setText(shipName, 0, GUI_ALIGN_CENTER);

		gui->setArray(RowOf(OO_DESC("status-present-system"), systemName), 1);
		if (hasHyperspaceMotor()) gui->setArray(RowOf(OO_DESC("status-hyperspace-system"), targetSystemName), 2);
		gui->setArray(RowOf(OO_DESC("status-condition"), alert_desc), 3);
		gui->setArray(RowOf(OO_DESC("status-fuel"), fuel_desc), 4);
		gui->setArray(RowOf(OO_DESC("status-cash"), credits_desc), 5);
		gui->setArray(RowOf(OO_DESC("status-legal-status"), legal_desc), 6);
		gui->setArray(RowOf(OO_DESC("status-rating"), rating_desc), 7);
		

		gui->setColor(gui->colorFromSetting(cxx_kGuiStatusShipnameColor, nil).get(), 0);
		for (i = 1 ; i <= 7 ; ++i)
		{
			// nil default = fall back to global default colour
			gui->setColor(gui->colorFromSetting(cxx_kGuiStatusDataColor, nil).get(), i);
		}

		gui->setText(OO_DESC("status-equipment"), 9);

		gui->setColor(gui->colorFromSetting(cxx_kGuiStatusEquipmentHeadingColor, nil).get(), 9);
		
		gui->setShowTextCursor(NO);
	}
	/* ends */

	lastTextKey.reset();
	
	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->clearMouse();
	
	// Contributed by Pleb - show ship model if the appropriate user default key has been set - Nikos 20140127
	if (EXPECT_NOT(oo::Defaults::standard().boolForKey("show-ship-model-in-status-screen")))
	{
		if (UNIVERSE != nullptr)  UNIVERSE->removeDemoShips();
		const std::optional<std::string> demoShipKey = shipDataKey();
		if (demoShipKey.has_value())  showShipModelWithKey(*demoShipKey, oo::PList(), entityPersonalityInt(), 2.5, 1.7, 8.0, "GUI_SCREEN_STATUS");
		setShowDemoShips(YES);
	}
	else
	{
		setShowDemoShips(NO);
	}
	
	if (UNIVERSE != nullptr)  UNIVERSE->enterGUIViewModeWithMouseInteraction(NO);
	
	if (guiChanged)
	{
		oo::PList fgDescriptor, bgDescriptor;
		if (status() == STATUS_DOCKED)
		{
			fgDescriptor = (UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey("docked_overlay") : oo::PList());
			bgDescriptor = (UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey("status_docked") : oo::PList());
		}
		else
		{
			fgDescriptor = (UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey("overlay") : oo::PList());
			if (alertConditionLevel == ALERT_CONDITION_RED) bgDescriptor = (UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey("status_red_alert") : oo::PList());
			else bgDescriptor = (UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey("status_in_flight") : oo::PList());
		}

		gui->setForegroundTextureDescriptor(fgDescriptor);

		if (bgDescriptor.isNull())  bgDescriptor = (UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey("status") : oo::PList());
		gui->setBackgroundTextureDescriptor(bgDescriptor);
		
		gui->setStatusPage(0);
		noteGUIDidChangeFrom(oldScreen, gui_screen);
	}
}


std::vector<oo::PList> PlayerEntity::equipmentList()
{
	::GuiDisplayGen		*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	std::vector<oo::PList>	quip1; // damaged
	std::vector<oo::PList>	quip2; // working
	std::optional<std::string>	desc;
	std::optional<std::string>	alldesc;

	BOOL prioritiseDamaged = gui->userSettings().get<bool>(cxx_kGuiStatusPrioritiseDamaged, true);

	const std::vector<oo::Ref<::OOEquipmentType>> allEquipmentTypes = OOEquipmentType::allEquipmentTypes();
	for (auto eqTypeRef = allEquipmentTypes.rbegin(); eqTypeRef != allEquipmentTypes.rend(); ++eqTypeRef)
	{
		::OOEquipmentType *eqType = eqTypeRef->get();
		if ((eqType != nullptr ? eqType->isVisible() : false))
		{
			if ((eqType != nullptr ? eqType->canCarryMultiple() : false) && !(eqType != nullptr ? eqType->isMissileOrMine() : false))
			{
				const std::string identifier = (eqType != nullptr ? eqType->identifier() : std::optional<std::string>()).value_or("");
				const std::string damagedIdentifier = identifier + "_DAMAGED";
				NSUInteger count = 0, okcount = 0;
				okcount = countEquipmentItem(identifier);
				count = okcount + countEquipmentItem(damagedIdentifier);
				if (count == 0)
				{
					// do nothing
				}
				// all items okay
				else if (count == okcount)
				{
					// only one installed display normally
					if (count == 1)
					{
						quip2.push_back(EquipmentRow((eqType != nullptr ? eqType->name() : std::optional<std::string>()), true, (eqType != nullptr ? eqType->displayColor().get() : (OOColor *)nullptr)));
					}
					// display plural form
					else
					{
						const std::string equipmentName = (eqType != nullptr ? eqType->name() : std::optional<std::string>()).value_or(std::string());	// (nil raised in the expansion)
						alldesc = ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "equipment-plural",
							{ { "count", oo::PList::unsignedInteger(count) }, { "equipmentName", oo::PList(equipmentName) } });
						quip2.push_back(EquipmentRow(alldesc, true, (eqType != nullptr ? eqType->displayColor().get() : (OOColor *)nullptr)));
					}
				}
				// all broken, only one installed
				else if (count == 1 && okcount == 0)
				{
					desc = oo::str::formatRuntime(OO_DESC("equipment-@-not-available"), { (eqType != nullptr ? eqType->name() : std::optional<std::string>()).value_or("(null)") });
					if (prioritiseDamaged)
					{
						quip1.push_back(EquipmentRow(desc, false, (eqType != nullptr ? eqType->displayColor().get() : (OOColor *)nullptr)));
					}
					else
					{
						quip2.push_back(EquipmentRow(desc, false, (eqType != nullptr ? eqType->displayColor().get() : (OOColor *)nullptr)));
					}
				}
				// some broken, multiple installed
				else
				{
					const std::string equipmentName = (eqType != nullptr ? eqType->name() : std::optional<std::string>()).value_or(std::string());	// (nil raised in the expansion)
					alldesc = ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "equipment-plural-some-na",
						{ { "okcount", oo::PList::unsignedInteger(okcount) }, { "count", oo::PList::unsignedInteger(count) }, { "equipmentName", oo::PList(equipmentName) } });
					if (prioritiseDamaged)
					{
						quip1.push_back(EquipmentRow(alldesc, false, (eqType != nullptr ? eqType->displayColor().get() : (OOColor *)nullptr)));
					}
					else
					{
						quip2.push_back(EquipmentRow(alldesc, false, (eqType != nullptr ? eqType->displayColor().get() : (OOColor *)nullptr)));
					}
				}
			}
			else if (hasEquipmentItem(OptionalKeyPList((eqType != nullptr ? eqType->identifier() : std::optional<std::string>()))))
			{
				quip2.push_back(EquipmentRow((eqType != nullptr ? eqType->name() : std::optional<std::string>()), true, (eqType != nullptr ? eqType->displayColor().get() : (OOColor *)nullptr)));
			}
			else
			{
				// Check for damaged version
				if (hasEquipmentItem(oo::PList((eqType != nullptr ? eqType->identifier() : std::optional<std::string>()).value_or("") + "_DAMAGED")))
				{
					desc = oo::str::formatRuntime(OO_DESC("equipment-@-not-available"), { (eqType != nullptr ? eqType->name() : std::optional<std::string>()).value_or("(null)") });

					if (prioritiseDamaged)
					{
						quip1.push_back(EquipmentRow(desc, false, (eqType != nullptr ? eqType->displayColor().get() : (OOColor *)nullptr)));
					}
					else
					{
						// just add in to the normal array
						quip2.push_back(EquipmentRow(desc, false, (eqType != nullptr ? eqType->displayColor().get() : (OOColor *)nullptr)));
					}
				}
			}
		}
	}
	
	if (max_passengers > 0)
	{
		desc = oo::str::formatRuntime(OO_DESC_PLURAL("equipment-pass-berth-@", max_passengers), { static_cast<int>(max_passengers) });	// %d
		quip2.push_back(EquipmentRow(desc, true, (OOEquipmentType::equipmentTypeWithIdentifier("EQ_PASSENGER_BERTH").get() != nullptr ? OOEquipmentType::equipmentTypeWithIdentifier("EQ_PASSENGER_BERTH").get()->displayColor().get() : (OOColor *)nullptr)));
	}
	
	if (!isWeaponNone(forward_weapon_type))
	{
		desc = oo::str::formatRuntime(OO_DESC("equipment-fwd-weapon-@"), { (forward_weapon_type != nullptr ? forward_weapon_type->name() : std::optional<std::string>()).value_or("(null)") });
		quip2.push_back(EquipmentRow(desc, true, (forward_weapon_type != nullptr ? forward_weapon_type->displayColor().get() : (OOColor *)nullptr)));
	}
	if (!isWeaponNone(aft_weapon_type))
	{
		desc = oo::str::formatRuntime(OO_DESC("equipment-aft-weapon-@"), { (aft_weapon_type != nullptr ? aft_weapon_type->name() : std::optional<std::string>()).value_or("(null)") });
		quip2.push_back(EquipmentRow(desc, true, (aft_weapon_type != nullptr ? aft_weapon_type->displayColor().get() : (OOColor *)nullptr)));
	}
	if (!isWeaponNone(port_weapon_type))
	{
		desc = oo::str::formatRuntime(OO_DESC("equipment-port-weapon-@"), { (port_weapon_type != nullptr ? port_weapon_type->name() : std::optional<std::string>()).value_or("(null)") });
		quip2.push_back(EquipmentRow(desc, true, (port_weapon_type != nullptr ? port_weapon_type->displayColor().get() : (OOColor *)nullptr)));
	}
	if (!isWeaponNone(starboard_weapon_type))
	{
		desc = oo::str::formatRuntime(OO_DESC("equipment-stb-weapon-@"), { (starboard_weapon_type != nullptr ? starboard_weapon_type->name() : std::optional<std::string>()).value_or("(null)") });
		quip2.push_back(EquipmentRow(desc, true, (starboard_weapon_type != nullptr ? starboard_weapon_type->displayColor().get() : (OOColor *)nullptr)));
	}
	
	// list damaged first, then working
	quip1.insert(quip1.end(), quip2.begin(), quip2.end());
	return quip1;
}


NSUInteger PlayerEntity::primedEquipmentCount()
{
	return eqScripts.size();
}


std::optional<std::string> PlayerEntity::primedEquipmentName(NSInteger offset)
{
	NSUInteger c = primedEquipmentCount();
	NSUInteger idx = (primedEquipment+(c+1)+offset)%(c+1);
	if (idx == c)
	{
		return OO_DESC("equipment-primed-none-hud-label");
	}
	else
	{
		return (OOEquipmentType::equipmentTypeWithIdentifier(eqScripts[idx].first).get() != nullptr ? OOEquipmentType::equipmentTypeWithIdentifier(eqScripts[idx].first).get()->name() : std::optional<std::string>());
	}
}


std::string PlayerEntity::currentPrimedEquipment()
{
	std::string result;	// "": primed-none
	NSUInteger c = eqScripts.size();
	if (primedEquipment != c && primedEquipment < c)
	{
		result = eqScripts[primedEquipment].first;
	}
	return result;
}


bool PlayerEntity::setPrimedEquipment(const std::string &eqKey, bool showMsg)
{
	// (a nil key primed nothing and answered NO: the bridged -setPrimedEquipment:showMessage:)
	NSUInteger c = eqScripts.size();
	NSUInteger current = primedEquipment;
	primedEquipment = eqScriptIndexForKey(eqKey);	// if key not found primedEquipment is set to primed-none
	BOOL unprimeEq = eqKey.empty();
	BOOL result = YES;

	if (primedEquipment == c && !unprimeEq)
	{
		primedEquipment = current;
		result = NO;
	}
	else 
	{
		if (primedEquipment != current && showMsg == YES)
		{
			if (unprimeEq)
			{
				if (UNIVERSE != nullptr)  UNIVERSE->addMessage(cxx_OOExpandKey("equipment-primed-none"), 2.0);
			}
			else
			{
				// (a nil name raised in the expansion)
				const std::string equipmentName = (OOEquipmentType::equipmentTypeWithIdentifier(eqScripts[primedEquipment].first).get() != nullptr ? OOEquipmentType::equipmentTypeWithIdentifier(eqScripts[primedEquipment].first).get()->name() : std::optional<std::string>()).value_or(std::string());
				if (UNIVERSE != nullptr)  UNIVERSE->addMessage(ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "equipment-primed", { { "equipmentName", oo::PList(equipmentName) } }), 2.0);
			}
		}
	}
	return result;
}


void PlayerEntity::activatePrimableEquipment(NSUInteger index, OOPrimedEquipmentMode mode)
{
	// index == eqScripts.size() means we don't want to activate any equipment.
	if(index < eqScripts.size())
	{
		::OOScript *eqScript = eqScripts[index].second.get();
		ooscript::Context context = OOJSAcquireContext();
		OOCAssert(mode <= OOPRIMEDEQUIP_MODE, "Primable equipment mode %i out of range", (int)mode);
		
		switch (mode)
		{
			case OOPRIMEDEQUIP_MODE:
				if (eqScript != nullptr)  eqScript->callMethod(OOJSID("mode"), context, NULL, 0, NULL);
				break;
			case OOPRIMEDEQUIP_ACTIVATED:
				if (eqScript != nullptr)  eqScript->callMethod(OOJSID("activated"), context, NULL, 0, NULL);
				break;
		}
		OOJSRelinquishContext(context);
	}
}


std::optional<std::string> PlayerEntity::fastEquipmentA()
{
	return _fastEquipmentA;
}


std::optional<std::string> PlayerEntity::fastEquipmentB()
{
	return _fastEquipmentB;
}


void PlayerEntity::setFastEquipmentA(const std::optional<std::string> &eqKey)
{
	_fastEquipmentA = eqKey;
}


void PlayerEntity::setFastEquipmentB(const std::optional<std::string> &eqKey)
{
	_fastEquipmentB = eqKey;
}


::OOEquipmentType *PlayerEntity::weaponTypeForFacing(OOWeaponFacing facing, bool /*strict*/)
{
	OOWeaponType weaponType = nil;
	
	switch (facing)
	{
		case WEAPON_FACING_FORWARD:
			weaponType = forward_weapon_type;
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

	return weaponType;
}



// Slice 18 of docs/phases/3-slices/PlayerEntity.md (bead oo-3fzv5): scripting lists (missiles, cargo, contracts), the system data screen, marked destinations, the chart screens.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

std::vector<oo::Ref<::OOEquipmentType>> PlayerEntity::missilesList()
{
	tidyMissilePylons();	// just in case.
	return ShipEntity::missilesList();
}


std::vector<std::string> PlayerEntity::cargoList()
{
	std::vector<std::string>	manifest;
	const oo::PList			list = cargoListForScripting();

	if (specialCargo) manifest.push_back(*specialCargo);

	for (size_t commodityIndex = 0; commodityIndex < list.count(); commodityIndex++)
	{
		const oo::PList &commodity = *list.at(commodityIndex);
		NSInteger quantity = commodity.get<NSInteger>("quantity");
		const std::optional<std::string> units = StringForKey(commodity, "unit");
		const std::optional<std::string> commodityName = StringForKey(commodity, "displayName");
		NSInteger containers = commodity.get<int>("containers");
		BOOL extended = !(units.has_value() && *units == OO_DESC("cargo-tons-symbol")) && containers > 0;

		// (a nil unit or name raised in the expansion)
		if (extended) {
			manifest.push_back(ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "manifest-cargo-quantity-extended",
				{ { "quantity", oo::PList::signedInteger(quantity) }, { "units", oo::PList(units.value_or(std::string())) },
				  { "commodityName", oo::PList(commodityName.value_or(std::string())) }, { "containers", oo::PList::signedInteger(containers) } }));
		} else {
			manifest.push_back(ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "manifest-cargo-quantity",
				{ { "quantity", oo::PList::signedInteger(quantity) }, { "units", oo::PList(units.value_or(std::string())) },
				  { "commodityName", oo::PList(commodityName.value_or(std::string())) } }));
		}
	}

	return manifest;
}


oo::PList PlayerEntity::cargoListForScripting()
{
	oo::PList::Array	list;

	const std::vector<std::string> goods = (shipCommodityData != nullptr ? shipCommodityData->goods() : std::vector<std::string>());
	NSUInteger			i, commodityCount = goods.size();
	std::vector<OOCargoQuantity>	quantityInHold(commodityCount, 0);
	std::vector<OOCargoQuantity>	containersInHold(commodityCount, 0);

	// following changed to work whether docked or not
	for (i = 0; i < commodityCount; i++)
	{
		quantityInHold[i] = (shipCommodityData != nullptr ? shipCommodityData->quantityForGood(goods[i]) : 0);
	}
	for (i = 0; i < cargo.size(); i++)
	{
		::ShipEntity *container = oo::ToShip(cargo[i].get());
		const std::optional<std::string> good = (container != nullptr ? container->commodityType() : std::optional<std::string>());
		const auto j = good.has_value() ? std::ranges::find(goods, *good) : goods.end();
		// A pod whose commodity is not a good (or has none) indexed past the arrays before; it is skipped.
		if (j == goods.end())  continue;
		quantityInHold[(std::size_t)(j - goods.begin())] += (container != nullptr ? container->commodityAmount() : 0);
		++containersInHold[(std::size_t)(j - goods.begin())];
	}

	for (i = 0; i < commodityCount; i++)
	{
		if (quantityInHold[i] > 0)
		{
			oo::PList::Dict	commodity;
			const std::string &symName = goods[i];
			// commodity, quantity - keep consistency between .manifest and .contracts
			commodity["commodity"] = symName;
			commodity["quantity"] = oo::PList::unsignedInteger(quantityInHold[i]);	// +numberWithUnsignedInt:
			commodity["containers"] = oo::PList::unsignedInteger(containersInHold[i]);
			const std::optional<std::string> goodName = (shipCommodityData != nullptr ? shipCommodityData->nameForGood(symName) : std::optional<std::string>());
			if (goodName.has_value())  commodity["displayName"] = *goodName;	// (nil raised before)
			commodity["unit"] = cxx_DisplayStringForMassUnitForCommodity(symName).value_or("");
			list.emplace_back(std::move(commodity));
		}
	}

	return oo::PList(std::move(list));
}


// determines general export legality, not tied to a station
unsigned PlayerEntity::legalStatusOfCargoList()
{
	OOCargoQuantity amount;
	unsigned		penalty = 0;

	for (const std::string &good : (shipCommodityData != nullptr ? shipCommodityData->goods() : std::vector<std::string>()))
	{
		amount = (shipCommodityData != nullptr ? shipCommodityData->quantityForGood(good) : 0);
		penalty += (shipCommodityData != nullptr ? shipCommodityData->exportLegalityForGood(good) : 0) * amount;
	}
	return penalty;
}


oo::PList::Array PlayerEntity::contractsListForScriptingFromArray(const oo::PList::Array &contracts_array, bool forCargo)
{
	oo::PList::Array	result;
	NSUInteger 			i;

	// (a nil value raised in -setObject:forKey: before; it is left out)
	const auto setString = [](oo::PList::Dict &contract, const std::string &key, const std::optional<std::string> &value)
	{
		if (value.has_value())  contract[key] = *value;
	};

	for (i = 0; i < contracts_array.size(); i++)
	{
		oo::PList::Dict		contract;
		const oo::PList		&dict = contracts_array[i];
		if (forCargo)
		{
			// commodity, quantity - keep consistency between .manifest and .contracts
			setString(contract, "commodity", StringForKey(dict, std::string(CARGO_KEY_TYPE)));
			contract["quantity"] = oo::PList::unsignedInteger(static_cast<unsigned int>(dict.get<int>(std::string(CARGO_KEY_AMOUNT))));	// +numberWithUnsignedInt:
			setString(contract, "description", StringForKey(dict, std::string(CARGO_KEY_DESCRIPTION)));
		}
		else
		{
			setString(contract, std::string(PASSENGER_KEY_NAME), StringForKey(dict, std::string(PASSENGER_KEY_NAME)));
			contract[std::string(CONTRACT_KEY_RISK)] = oo::PList::unsignedInteger(dict.get<unsigned int>(std::string(CONTRACT_KEY_RISK)));
		}

		OOSystemID 	planet = dict.get<int>(std::string(CONTRACT_KEY_DESTINATION));
		std::optional<std::string>	planetName = (UNIVERSE != nullptr ? UNIVERSE->getSystemName(planet) : std::optional<std::string>());
		contract[std::string(CONTRACT_KEY_DESTINATION)] = oo::PList::unsignedInteger(static_cast<unsigned int>(planet));
		setString(contract, "destinationName", planetName);
		planet = dict.get<int>(std::string(CONTRACT_KEY_START));
		planetName = (UNIVERSE != nullptr ? UNIVERSE->getSystemName(planet) : std::optional<std::string>());
		contract[std::string(CONTRACT_KEY_START)] = oo::PList::unsignedInteger(static_cast<unsigned int>(planet));
		setString(contract, "startName", planetName);

		int 		dest_eta = dict.get<double>(std::string(CONTRACT_KEY_ARRIVAL_TIME)) - ship_clock;
		contract["eta"] = oo::PList::signedInteger(dest_eta);
		setString(contract, "etaDescription", (UNIVERSE != nullptr ? UNIVERSE->shortTimeDescription(dest_eta) : std::optional<std::string>()));
		contract[std::string(CONTRACT_KEY_PREMIUM)] = oo::PList::signedInteger(dict.get<int>(std::string(CONTRACT_KEY_PREMIUM)));
		contract[std::string(CONTRACT_KEY_FEE)] = oo::PList::signedInteger(dict.get<int>(std::string(CONTRACT_KEY_FEE)));
		result.emplace_back(std::move(contract));
	}

	return result;
}


oo::PList PlayerEntity::passengerListForScripting()
{
	return oo::PList(contractsListForScriptingFromArray(passengers, NO));
}


oo::PList PlayerEntity::parcelListForScripting()
{
	return oo::PList(contractsListForScriptingFromArray(parcels, NO));
}


oo::PList PlayerEntity::contractListForScripting()
{
	return oo::PList(contractsListForScriptingFromArray(contracts, YES));
}


void PlayerEntity::setGuiToSystemDataScreen()
{
	setGuiToSystemDataScreenRefreshBackground(NO);
}


void PlayerEntity::setGuiToSystemDataScreenRefreshBackground(bool refreshBackground)
{
	const oo::PList	infoSystemData = (UNIVERSE != nullptr ? UNIVERSE->generateSystemData(info_system_id) : oo::PList());
	NSInteger concealment = infoSystemData.get<int>("concealment", OO_SYSTEMCONCEALMENT_NONE);
	const std::string infoSystemName = StringForKey(infoSystemData, std::string(KEY_NAME)).value_or(std::string());	// (a nil name raised in the expansions below)

	BOOL			sunGoneNova = (infoSystemData.get<bool>("sun_gone_nova"));
	OOGUIScreenID	oldScreen = gui_screen;
	
	::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	gui_screen = GUI_SCREEN_SYSTEM_DATA;
	BOOL			guiChanged = (oldScreen != gui_screen);

	Random_Seed		infoSystemRandomSeed = ((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getRandomSeedForSystem(info_system_id, galaxyNumber()) : Random_Seed());
	
	if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setMouseInteractionModeForUIWithMouseInteraction(NO);
	
	// GUI stuff
	{
		OOGUITabSettings tab_stops;
		tab_stops[0] = 0;
		tab_stops[1] = 96;
		tab_stops[2] = 144;
		gui->overrideTabs(tab_stops, cxx_kGuiSystemdataTabs, 3);
		gui->setTabStops(tab_stops);
		
		NSUInteger techLevel = infoSystemData.get<int>(std::string(KEY_TECHLEVEL)) + 1;
		int population = infoSystemData.get<int>(std::string(KEY_POPULATION));
		int productivity = infoSystemData.get<int>(std::string(KEY_PRODUCTIVITY));
		int radius = infoSystemData.get<int>(std::string(KEY_RADIUS));

		std::string	government_desc =	StringForKey(infoSystemData, std::string(KEY_GOVERNMENT_DESC))
											.value_or(cxx_OODisplayStringFromGovernmentID(infoSystemData.get<int>(std::string(KEY_GOVERNMENT))).value_or(""));
		std::string	economy_desc =		StringForKey(infoSystemData, std::string(KEY_ECONOMY_DESC))
											.value_or(cxx_OODisplayStringFromEconomyID(infoSystemData.get<int>(std::string(KEY_ECONOMY))).value_or(""));
		std::string	inhabitants =		StringForKey(infoSystemData, std::string(KEY_INHABITANTS)).value_or(std::string());	// (nil raised in the expansion)
		std::optional<std::string>	system_desc = StringForKey(infoSystemData, std::string(KEY_DESCRIPTION));

		std::string	populationDesc =	StringForKey(infoSystemData, std::string(KEY_POPULATION_DESC))
											.value_or(cxx_OOExpandKeyWithSeed(kNilRandomSeed, "sysdata-pop-value", population).value_or(std::string()));

		if (sunGoneNova)
		{
			population = 0;
			productivity = 0;
			radius = 0;
			techLevel = 0;

			government_desc = cxx_OOExpandKeyWithSeed(infoSystemRandomSeed, "nova-system-government").value_or(std::string());
			economy_desc = cxx_OOExpandKeyWithSeed(infoSystemRandomSeed, "nova-system-economy").value_or(std::string());
			inhabitants = cxx_OOExpandKeyWithSeed(infoSystemRandomSeed, "nova-system-inhabitants").value_or(std::string());
			system_desc = ExpandKeyWithSeed(infoSystemRandomSeed, "nova-system-description", { { "system", oo::PList(infoSystemName) } });
			populationDesc = cxx_OOExpandKeyWithSeed(infoSystemRandomSeed, "sysdata-pop-value", population).value_or(std::string());
		}

		
		gui->clearAndKeepBackground(!refreshBackground && !guiChanged);
		if (UNIVERSE != nullptr)  UNIVERSE->removeDemoShips();

		if (concealment < OO_SYSTEMCONCEALMENT_NONAME)
		{
			gui->setTitle(ExpandKeyWithSeed(infoSystemRandomSeed, "sysdata-data-on-system", { { "system", oo::PList(infoSystemName) } }));
		}
		else
		{
			gui->setTitle(cxx_OOExpandKey("sysdata-data-on-system-no-name"));
		}

		if (concealment >= OO_SYSTEMCONCEALMENT_NODATA)
		{
			OOGUIRow i = gui->addLongText(cxx_OOExpandKey("sysdata-data-on-system-no-data"), 15, GUI_ALIGN_LEFT);
			missionTextRow = i;
			for (i-- ; i > 14 ; --i)
			{
				gui->setColor(gui->colorFromSetting(cxx_kGuiSystemdataDescriptionColor, OOColor::greenColor().get()).get(), i);
			}
		}
		else
		{
			NSPoint infoSystemCoordinates = ((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getCoordinatesForSystem(info_system_id, galaxy_number) : NSMakePoint(0, 0));
			double distance = distanceBetweenPlanetPositions(infoSystemCoordinates.x, infoSystemCoordinates.y, galaxy_coordinates.x, galaxy_coordinates.y);
			if(distance == 0.0 && info_system_id != system_id)
			{
				distance = 0.1;
			}
			std::string distanceInfo = oo::str::format("%.1f ly", distance);
			if (ANA_mode != OPTIMIZED_BY_NONE)
			{
				const oo::PList routeInfo = (UNIVERSE != nullptr ? UNIVERSE->routeFromSystem(system_id, info_system_id, ANA_mode) : oo::PList());
				if (!routeInfo.isNull())
				{
					double routeDistance = routeInfo.get<double>("distance");
					double routeTime = routeInfo.get<double>("time");
					int routeJumps = routeInfo.get<int>("jumps");
					if(routeDistance == 0.0 && info_system_id != system_id) {
						routeDistance = 0.1;
						routeTime = 0.01;
						routeJumps = 0;
					}
					// don't rely on DESC_PLURAL for routeTime since it is of type double
					const std::string hoursText = (routeTime > 1.05 || routeTime < 0.95 ? OO_DESC("sysdata-route-hours%1") : OO_DESC("sysdata-route-hours%0"));	// one description per local, in the order Clang evaluates the arguments (ADR-0063 item 5)
					const std::string jumpsText = OO_DESC_PLURAL("sysdata-route-jumps", routeJumps);
					distanceInfo = oo::str::format("%.1f ly / %.1f %s / %d %s",
							routeDistance,
							routeTime,
							hoursText.c_str(),
							routeJumps,
							jumpsText.c_str());
				}
			}

			OOGUIRow i;

			for (i = 1; i <= 16; i++) {
				const std::string ln = oo::str::format("sysdata-line-%ld", (long)i);
				const std::string line = ExpandKeyWithSeed(infoSystemRandomSeed, ln, {
					{ "economy_desc", oo::PList(economy_desc) },
					{ "government_desc", oo::PList(government_desc) },
					{ "techLevel", oo::PList::unsignedInteger(techLevel) },
					{ "populationDesc", oo::PList(populationDesc) },
					{ "inhabitants", oo::PList(inhabitants) },
					{ "productivity", oo::PList::signedInteger(productivity) },
					{ "radius", oo::PList::signedInteger(radius) },
					{ "distanceInfo", oo::PList(distanceInfo) } });
				if (!line.empty())
				{
					const std::vector<std::string> lines = oo::str::split(line, "\t");
					if (lines.size() == 1)
					{
						gui->setArray({ lines[0] }, i);
					}
					if (lines.size() == 2)
					{
						gui->setArray({ lines[0], lines[1] }, i);
					}
					if (lines.size() == 3)
					{
						if (lines[2].empty())
						{
							gui->setArray({ lines[0], lines[1] }, i);
						}
						else
						{
							gui->setArray({ lines[0], lines[1], lines[2] }, i);
						}
					}
				}
				else
				{
					gui->setArray(std::vector<std::string>{ std::string() }, i);
				}
			}


			i = gui->addLongText(system_desc, 17, GUI_ALIGN_LEFT);
			missionTextRow = i;
			for (i-- ; i > 16 ; --i)
			{
				gui->setColor(gui->colorFromSetting(cxx_kGuiSystemdataDescriptionColor, OOColor::greenColor().get()).get(), i);
			}
			for (i = 1 ; i <= 14 ; ++i)
			{
				// nil default = fall back to global default colour
				gui->setColor(gui->colorFromSetting(cxx_kGuiSystemdataFactsColor, nil).get(), i);
			}
		}

		gui->setShowTextCursor(NO);
	}
	/* ends */
	
	lastTextKey.reset();
	
	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->clearMouse();
	
	setShowDemoShips(NO);
	if (UNIVERSE != nullptr)  UNIVERSE->enterGUIViewModeWithMouseInteraction(NO);
	
	// if the system has gone nova, there's no planet to display
	if (!sunGoneNova && concealment < OO_SYSTEMCONCEALMENT_NODATA)
	{
		// The next code is generating the miniature planets.
		// When normal planets are displayed, the PRNG is reset. This happens not with procedural planet display.
		RANROTSeed ranrotSavedSeed = RANROTGetFullSeed();
		RNG_Seed saved_seed = currentRandomSeed();
		
		if (info_system_id == system_id)
		{
			setBackgroundFromDescriptionsKey("gui-scene-show-local-planet");
		}
		else
		{
			setBackgroundFromDescriptionsKey("gui-scene-show-planet");
		}
		
		setRandomSeed(saved_seed);
		RANROTSetFullSeed(ranrotSavedSeed);
	}
	
	if (refreshBackground || guiChanged)
	{
		gui->setForegroundTextureKey(std::optional<std::string>(status() == STATUS_DOCKED ? "docked_overlay" : "overlay"));
		gui->setBackgroundTextureKey(std::optional<std::string>(sunGoneNova ? "system_data_nova" : "system_data"));
		
		noteGUIDidChangeFrom(oldScreen, gui_screen, refreshBackground);
		checkScript();	// Still needed by some OXPs?
	}
}


std::optional<std::map<int, std::vector<oo::PList>>> PlayerEntity::markedDestinations()
{
	// get a list of systems marked as contract destinations
	std::map<int, std::vector<oo::PList>>	destinations;
	unsigned		i;
	OOSystemID sysid;

	for (i = 0; i < passengers.size(); i++)
	{
		sysid = passengers[i].get<unsigned char>(std::string(CONTRACT_KEY_DESTINATION));
		PrepareMarkedDestination(destinations, passengerContractMarker(sysid));
	}
	for (i = 0; i < parcels.size(); i++)
	{
		sysid = parcels[i].get<unsigned char>(std::string(CONTRACT_KEY_DESTINATION));
		PrepareMarkedDestination(destinations, parcelContractMarker(sysid));
	}
	for (i = 0; i < contracts.size(); i++)
	{
		sysid = contracts[i].get<unsigned char>(std::string(CONTRACT_KEY_DESTINATION));
		PrepareMarkedDestination(destinations, cargoContractMarker(sysid));
	}

	// ORDER-SENSITIVE: markers within a system now come in the map's byte order of keys (the
	// dictionary's own key order before); a marker is plist data
	for (const auto &entry : missionDestinations)
	{
		PrepareMarkedDestination(destinations, entry.second);
	}

	return destinations;
}


void PlayerEntity::setGuiToLongRangeChartScreen()
{
	OOGUIScreenID	oldScreen = gui_screen;
	::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	gui->clearAndKeepBackground(NO);
	gui->setBackgroundTextureKey("short_range_chart");
	setMissionBackgroundSpecial("");
	gui_screen = GUI_SCREEN_LONG_RANGE_CHART;
	target_chart_zoom = CHART_MAX_ZOOM;
	setGuiToChartScreenFrom(oldScreen);
}


void PlayerEntity::setGuiToShortRangeChartScreen()
{
	OOGUIScreenID	oldScreen = gui_screen;
	::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	gui->clearAndKeepBackground(NO);
	gui->setBackgroundTextureKey("short_range_chart");
	setMissionBackgroundSpecial("");
	gui_screen = GUI_SCREEN_SHORT_RANGE_CHART;
	setGuiToChartScreenFrom(oldScreen);
}


void PlayerEntity::setGuiToChartScreenFrom(OOGUIScreenID oldScreen)
{
	::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	
	BOOL			guiChanged = (oldScreen != gui_screen);
	
	if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setMouseInteractionModeForUIWithMouseInteraction(YES);
	
	target_system_id = (UNIVERSE != nullptr ? UNIVERSE->findSystemNumberAtCoords(cursor_coordinates, galaxy_number, NO) : 0);
	
	if (UNIVERSE != nullptr)  UNIVERSE->preloadPlanetTexturesForSystem(target_system_id);
	
	// GUI stuff
	{
		//[gui clearAndKeepBackground:!guiChanged];
		gui->setStarChartTitle();
		// refresh the short range chart cache, in case we've just loaded a save game with different local overrides, etc.
		gui->refreshStarChart();
		//[gui setText:targetSystemName forRow:19];
		// distance-f & est-travel-time-f are identical between short & long range charts in standard Oolite, however can be alterered separately via OXPs
		//[gui cxx_setText:cxx_OOExpandKey("short-range-chart-distance", distance) forRow:20];
		//std::string travelTimeRow;
		//if ([self hasHyperspaceMotor] && distance > 0.0 && distance * 10.0 <= fuel)
		//{
		//	double time = estimatedTravelTime;
		//	travelTimeRow = cxx_OOExpandKey("short-range-chart-est-travel-time", time);
		//}
		//[gui setText:travelTimeRow forRow:21];
		if (gui_screen == GUI_SCREEN_LONG_RANGE_CHART)
		{
			const std::optional<std::string> searchString = planetSearchString;
			const std::string displaySearchString = searchString.has_value() ? oo::str::capitalized(*searchString) : std::string();
			gui->setText(oo::str::formatRuntime(OO_DESC("long-range-chart-find-planet-@"), { displaySearchString }), GUI_ROW_PLANET_FINDER);
			gui->setColor(OOColor::cyanColor().get(), GUI_ROW_PLANET_FINDER);
			gui->setShowTextCursor(YES);
			gui->setCurrentRow(GUI_ROW_PLANET_FINDER);
		}
		else
		{
			gui->setShowTextCursor(NO);
		}
	}
	/* ends */
	
	setShowDemoShips(NO);
	if (UNIVERSE != nullptr)  UNIVERSE->enterGUIViewModeWithMouseInteraction(YES);
	
	if (guiChanged)
	{
		gui->setForegroundTextureKey(std::optional<std::string>(status() == STATUS_DOCKED ? "docked_overlay" : "overlay"));
		
		gui->setBackgroundTextureKey("short_range_chart");
		if (found_system_id >= 0)
		{		
			const std::optional<std::string> foundName = (UNIVERSE != nullptr ? UNIVERSE->getSystemName(found_system_id) : std::optional<std::string>());
			if (foundName.has_value())  { if (UNIVERSE != nullptr)  UNIVERSE->findSystemCoordinatesWithPrefix(oo::str::lowercase(*foundName), YES); }
			else  for (int i = 0; i < 256; i++)  (UNIVERSE != nullptr ? UNIVERSE->systemsFound() : nullptr)[i] = NO;	// a nil prefix matched no system, clearing every flag
		}
		noteGUIDidChangeFrom(oldScreen, gui_screen);
	}
}



// Slice 19 of docs/phases/3-slices/PlayerEntity.md (bead oo-4tqku): the game options and load / save screens, equip-screen key highlight, available facings.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

void PlayerEntity::setGuiToGameOptionsScreen()
{
	::MyOpenGLView *gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);

	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->clearMouse();
	if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setMouseInteractionModeForUIWithMouseInteraction(YES);

	gui_screen = GUI_SCREEN_GAMEOPTIONS;

	// GUI stuff
	{
		#define OO_SETACCESSCONDITIONFORROW(condition, row)				\
		do {													\
			if ((condition))									\
			{												\
				gui->setKey(std::string(GUI_KEY_OK), (row));			\
			}												\
			else												\
			{												\
				gui->setColor(OOColor::grayColor().get(), (row));	\
			}												\
		} while(0)
		BOOL startingGame = status() == STATUS_START_GAME;
		::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
		GUI_ROW_INIT(gui);

		int first_sel_row = GUI_FIRST_ROW(GAME)-4; // repositioned menu

		gui->clear();
		gui->setTitle(oo::str::formatRuntime(OO_DESC("status-commander-@"), { TextArg(commanderName()) })); // Same title as status screen.
		
#if OO_RESOLUTION_OPTION
		::GameController	*controller = (UNIVERSE != nullptr ? UNIVERSE->gameController() : nullptr);
		
		NSUInteger		displayModeIndex = (controller != nullptr ? controller->indexOfCurrentDisplayMode() : 0);
		if (displayModeIndex == NSNotFound)
		{
			OO_LOG_WARN("display.currentMode.notFound", "{}", "couldn't find current fullscreen setting, switching to default.");
			displayModeIndex = 0;
		}
		
		const oo::PList	modeList = (controller != nullptr ? controller->getDisplayModes() : oo::PList());
		const oo::PList	*mode = nullptr;
		if (modeList.count())
		{
			mode = modeList.at(displayModeIndex);
		}
		if (mode == nullptr)  return;	// Got a better idea?

		unsigned modeWidth = mode->get<unsigned int>(std::string(kOODisplayWidth));
		unsigned modeHeight = mode->get<unsigned int>(std::string(kOODisplayHeight));
		float modeRefresh = mode->get<float>(std::string(kOODisplayRefreshRate));

		BOOL runningOnPrimaryDisplayDevice = (gameView != nullptr ? gameView->isRunningOnPrimaryDisplayDevice() : false);
#if OOLITE_WINDOWS
		if (!runningOnPrimaryDisplayDevice)
		{
			if (gameView != nullptr)  gameView->getDisplayDimensions(&modeWidth, &modeHeight);
		}
#endif
		
		const std::optional<std::string> displayModeString = screenModeStringForWidth(modeWidth, modeHeight, modeRefresh);

		gui->setText(displayModeString, GUI_ROW(GAME,DISPLAY), GUI_ALIGN_CENTER);
		if (runningOnPrimaryDisplayDevice)
		{
			gui->setKey(std::string(GUI_KEY_OK), GUI_ROW(GAME,DISPLAY));
		}
		else
		{
			gui->setColor(OOColor::grayColor().get(), GUI_ROW(GAME,DISPLAY));
		}
#endif	// OO_RESOLUTIOM_OPTION


#if OOLITE_WINDOWS
		if ((gameView != nullptr ? gameView->hdrOutput() : false))
		{
			const oo::PList	*brightnessesNode = UNIVERSE->descriptions()->find("hdr_maxBrightness_array");
			const oo::PList	brightnessesValue = (brightnessesNode != nullptr) ? *brightnessesNode : oo::PList();
			const oo::PList	brightnesses = brightnessesValue.isArray() ? brightnessesValue : oo::PList();
			// -indexOfObject: with the %d string: only string elements ever matched; not found was NSNotFound narrowed to int
			const std::string	currentBrightness = std::to_string((int)(gameView != nullptr ? gameView->hdrMaxBrightness() : 0.0f));
			int			brightnessIdx = static_cast<int>(NSNotFound);
			for (std::size_t i = 0; i < brightnesses.count(); i++)
			{
				const oo::PList *element = brightnesses.at(i);
				if (element->isString() && *element->getIf<std::string>() == currentBrightness)
				{
					brightnessIdx = static_cast<int>(i);
					break;
				}
			}
			
			if (static_cast<NSInteger>(brightnessIdx) == NSNotFound)
			{
				OO_LOG_WARN("hdr.maxBrightness.notFound", "{}", "couldn't find current max brightness setting, switching to 400 nits.");
				brightnessIdx = 0;
			}
				
			int brightnessValue = brightnesses.at<int>(static_cast<std::size_t>(brightnessIdx));
			const std::string maxBrightnessString = cxx_OOExpandKey("gameoptions-hdr-maxbrightness", brightnessValue).value_or(std::string());

			gui->setText(maxBrightnessString, GUI_ROW(GAME,HDRMAXBRIGHTNESS), GUI_ALIGN_CENTER);
			gui->setKey(std::string(GUI_KEY_OK), GUI_ROW(GAME,HDRMAXBRIGHTNESS));
		}
#endif


		if ((UNIVERSE != nullptr ? UNIVERSE->getAutoSave() : false))
			gui->setText(OO_DESC("gameoptions-autosave-yes"), GUI_ROW(GAME,AUTOSAVE), GUI_ALIGN_CENTER);
		else
			gui->setText(OO_DESC("gameoptions-autosave-no"), GUI_ROW(GAME,AUTOSAVE), GUI_ALIGN_CENTER);
		gui->setKey(std::string(GUI_KEY_OK), GUI_ROW(GAME,AUTOSAVE));
	
		// volume control
		if (::OOSound::isSoundOK())	// (+respondsToSelector:@selector(masterVolume) was always YES)
		{
			double volume = 100.0 * ::OOSound::masterVolume();
			int vol = (volume / 5.0 + 0.5); // avoid rounding errors
			const std::string soundVolumeWordDesc = OO_DESC("gameoptions-sound-volume");
			if (vol > 0)
				gui->setText(oo::str::format("%s%s ", soundVolumeWordDesc.c_str(), SliderString(vol).c_str()), GUI_ROW(GAME,VOLUME), GUI_ALIGN_CENTER);
			else
				gui->setText(OO_DESC("gameoptions-sound-volume-mute"), GUI_ROW(GAME,VOLUME), GUI_ALIGN_CENTER);
			gui->setKey(std::string(GUI_KEY_OK), GUI_ROW(GAME,VOLUME));
		}
		else
		{
			gui->setText(OO_DESC("gameoptions-volume-external-only"), GUI_ROW(GAME,VOLUME), GUI_ALIGN_CENTER);
			gui->setColor(OOColor::grayColor().get(), GUI_ROW(GAME,VOLUME));
		}
		

		// field of view control
		float fov = (gameView != nullptr ? gameView->fov(NO) : 0.0f);
		int fovTicks = (int)((fov - MIN_FOV_DEG) * 20 / (MAX_FOV_DEG - MIN_FOV_DEG));
		const std::string fovWordDesc = OO_DESC("gameoptions-fov-value");
		// %c 176 gave U+00B0 (probed on GNUstep base, oo-3rb.218); written as its UTF-8 bytes
		gui->setText(oo::str::format("%s%s (%d%s) ", fovWordDesc.c_str(), SliderString(fovTicks).c_str(), (int)fov, "\xC2\xB0" /*the degrees symbol*/), GUI_ROW(GAME,FOV), GUI_ALIGN_CENTER);
		gui->setKey(std::string(GUI_KEY_OK), GUI_ROW(GAME,FOV));
		
		// color blind mode
		int colorblindMode = (UNIVERSE != nullptr ? UNIVERSE->colorblindMode() : 0);
		const oo::PList *colorblindModesNode = UNIVERSE->descriptions()->find("colorblind_mode");
		const oo::PList colorblindModes = (colorblindModesNode != nullptr) ? *colorblindModesNode : oo::PList();
		const std::string colorblindModeDesc = colorblindModes.isArray() ? colorblindModes.at<std::string>(static_cast<std::size_t>((UNIVERSE != nullptr ? UNIVERSE->useShaders() : false) ? colorblindMode : 0)) : std::string();	// (nil raised in the expansion)
		const std::string colorblindModeMsg = ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "gameoptions-colorblind-mode", { { "colorblindModeDesc", oo::PList(colorblindModeDesc) } });
		gui->setText(colorblindModeMsg, GUI_ROW(GAME,COLORBLINDMODE), GUI_ALIGN_CENTER);
		if ((UNIVERSE != nullptr ? UNIVERSE->useShaders() : false))
		{
			gui->setKey(std::string(GUI_KEY_OK), GUI_ROW(GAME,COLORBLINDMODE));
		}
		else
		{
			gui->setColor(OOColor::grayColor().get(), GUI_ROW(GAME,COLORBLINDMODE));
		}
		
#if OOLITE_SPEECH_SYNTH
		// Speech control
		switch (isSpeechOn)
		{
		case OOSPEECHSETTINGS_OFF:
			gui->setText(OO_DESC("gameoptions-spoken-messages-no"), GUI_ROW(GAME,SPEECH), GUI_ALIGN_CENTER);
			break;
		case OOSPEECHSETTINGS_COMMS:
			gui->setText(OO_DESC("gameoptions-spoken-messages-comms"), GUI_ROW(GAME,SPEECH), GUI_ALIGN_CENTER);
			break;
		case OOSPEECHSETTINGS_ALL:
			gui->setText(OO_DESC("gameoptions-spoken-messages-yes"), GUI_ROW(GAME,SPEECH), GUI_ALIGN_CENTER);
			break;
		}
		OO_SETACCESSCONDITIONFORROW(!startingGame, GUI_ROW(GAME,SPEECH));
		
#if OOLITE_ESPEAK
		{
			const std::string voiceName = (UNIVERSE != nullptr ? UNIVERSE->voiceName(voice_no) : std::optional<std::string>()).value_or(std::string());
			std::string message = ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "gameoptions-voice-name", { { "voiceName", oo::PList(voiceName) } });
			gui->setText(message, GUI_ROW(GAME,SPEECH_LANGUAGE), GUI_ALIGN_CENTER);
			OO_SETACCESSCONDITIONFORROW(!startingGame, GUI_ROW(GAME,SPEECH_LANGUAGE));

			message = OO_DESC(voice_gender_m ? "gameoptions-voice-M" : "gameoptions-voice-F");
			gui->setText(message, GUI_ROW(GAME,SPEECH_GENDER), GUI_ALIGN_CENTER);
			OO_SETACCESSCONDITIONFORROW(!startingGame, GUI_ROW(GAME,SPEECH_GENDER));
		}
#endif
#endif
#if !OOLITE_MAC_OS_X
		// window/fullscreen
		if((gameView != nullptr ? gameView->inFullScreenMode() : false))
		{
			gui->setText(OO_DESC("gameoptions-play-in-window"), GUI_ROW(GAME,DISPLAYSTYLE), GUI_ALIGN_CENTER);
		}
		else
		{
			gui->setText(OO_DESC("gameoptions-play-in-fullscreen"), GUI_ROW(GAME,DISPLAYSTYLE), GUI_ALIGN_CENTER);
		}
		gui->setKey(std::string(GUI_KEY_OK), GUI_ROW(GAME,DISPLAYSTYLE));
#endif
		
		gui->setText(OO_DESC("gameoptions-joystick-configuration"), GUI_ROW(GAME,STICKMAPPER), GUI_ALIGN_CENTER);
		OO_SETACCESSCONDITIONFORROW(OOJoystickManager::sharedStickHandler()->joystickCount(), GUI_ROW(GAME,STICKMAPPER));

		gui->setText(OO_DESC("gameoptions-keyboard-configuration"), GUI_ROW(GAME,KEYMAPPER), GUI_ALIGN_CENTER);
		gui->setKey(std::string(GUI_KEY_OK), GUI_ROW(GAME,KEYMAPPER));

		
		const std::string musicMode = (UNIVERSE != nullptr ? UNIVERSE->descriptionForArrayKey("music-mode", OOMusicController::sharedController()->mode()) : std::optional<std::string>()).value_or(std::string());
		const std::string message = ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "gameoptions-music-mode", { { "musicMode", oo::PList(musicMode) } });
		gui->setText(message, GUI_ROW(GAME,MUSIC), GUI_ALIGN_CENTER);
		gui->setKey(std::string(GUI_KEY_OK), GUI_ROW(GAME,MUSIC));

		if (!(gameView != nullptr ? gameView->hdrOutput() : false))
		{
			if ((UNIVERSE != nullptr ? UNIVERSE->getWireframeGraphics() : false))
				gui->setText(OO_DESC("gameoptions-wireframe-graphics-yes"), GUI_ROW(GAME,WIREFRAMEGRAPHICS), GUI_ALIGN_CENTER);
			else
				gui->setText(OO_DESC("gameoptions-wireframe-graphics-no"), GUI_ROW(GAME,WIREFRAMEGRAPHICS), GUI_ALIGN_CENTER);
			gui->setKey(std::string(GUI_KEY_OK), GUI_ROW(GAME,WIREFRAMEGRAPHICS));
		}
#if OOLITE_WINDOWS
		else
		{
			float paperWhite = (gameView != nullptr ? gameView->hdrPaperWhiteBrightness() : 0.0f);
			int paperWhiteTicks = (int)((paperWhite - MIN_HDR_PAPERWHITE) * 20 / (MAX_HDR_PAPERWHITE - MIN_HDR_PAPERWHITE));
			const std::string paperWhiteWordDesc = OO_DESC("gameoptions-hdr-paperwhite");
			gui->setText(oo::str::format("%s%s (%d) ", paperWhiteWordDesc.c_str(), SliderString(paperWhiteTicks).c_str(), (int)paperWhite), GUI_ROW(GAME,HDRPAPERWHITE), GUI_ALIGN_CENTER);
			gui->setKey(std::string(GUI_KEY_OK), GUI_ROW(GAME,HDRPAPERWHITE));
		}
#endif
		

		OOGraphicsDetail detailLevel = (UNIVERSE != nullptr ? UNIVERSE->getDetailLevel() : OOGraphicsDetail{});
		const std::string shaderEffectsOptionsString = cxx_OOExpand("gameoptions-detaillevel-[detailLevel]", detailLevel).value_or(std::string());
		gui->setText(ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), shaderEffectsOptionsString, {}), GUI_ROW(GAME,SHADEREFFECTS), GUI_ALIGN_CENTER);
		if (!OOOpenGLExtensionManager::sharedManager()->shadersForceDisabled())
		{
			gui->setKey(std::string(GUI_KEY_OK), GUI_ROW(GAME,SHADEREFFECTS));
		}
		else
		{
			// deactivate this option if shaders have been disabled from the commend line
			gui->setColor(OOColor::grayColor().get(), GUI_ROW(GAME,SHADEREFFECTS));
		}
		
		
		if ((UNIVERSE != nullptr ? UNIVERSE->dockingClearanceProtocolActive() : false))
		{
			gui->setText(OO_DESC("gameoptions-docking-clearance-yes"), GUI_ROW(GAME,DOCKINGCLEARANCE), GUI_ALIGN_CENTER);
		}
		else
		{
			gui->setText(OO_DESC("gameoptions-docking-clearance-no"), GUI_ROW(GAME,DOCKINGCLEARANCE), GUI_ALIGN_CENTER);
		}
		OO_SETACCESSCONDITIONFORROW(!startingGame, GUI_ROW(GAME,DOCKINGCLEARANCE));
		
		// Back menu option
		gui->setText(OO_DESC("gui-back"), GUI_ROW(GAME,BACK), GUI_ALIGN_CENTER);
		gui->setKey(std::string(GUI_KEY_OK), GUI_ROW(GAME,BACK));

		gui->setSelectableRange(NSMakeRange(first_sel_row, GUI_ROW_GAMEOPTIONS_END_OF_LIST));
		gui->setSelectedRow(first_sel_row);

		gui->setShowTextCursor(NO);
		gui->setForegroundTextureKey(std::optional<std::string>(status() == STATUS_DOCKED ? "docked_overlay" : "paused_overlay"));
		gui->setBackgroundTextureKey("settings");
	}
	/* ends */

	setShowDemoShips(NO);
	if (UNIVERSE != nullptr)  UNIVERSE->enterGUIViewModeWithMouseInteraction(YES);
}


void PlayerEntity::setGuiToLoadSaveScreen()
{
	BOOL			gamePaused = (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr ? UNIVERSE->gameController()->isGamePaused() : false);
	BOOL			canLoadOrSave = NO;
	::MyOpenGLView	*gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	OOGUIScreenID	oldScreen = gui_screen;
	
	if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setMouseInteractionModeForUIWithMouseInteraction(YES);

	gui_screen = GUI_SCREEN_OPTIONS;

	if (status() == STATUS_DOCKED)
	{
		if (dockedStation() == nil)  setDockedAtMainStation();
		canLoadOrSave = ((dockedStation() == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr) || (dockedStation() != nullptr ? dockedStation()->getAllowsSaving() : false)) && !(((UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr) != nullptr ? UNIVERSE->sun()->goneNova() : false) || ((UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr) != nullptr ? UNIVERSE->sun()->willGoNova() : false)));
	}
	
	BOOL canQuickSave = (canLoadOrSave && (gameView != nullptr && gameView->getGameController() != nullptr ? gameView->getGameController()->playerFileToLoad() : std::optional<std::string>()).has_value());
	
	// GUI stuff
	{
		::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
		GUI_ROW_INIT(gui);

		int first_sel_row = (canLoadOrSave)? GUI_ROW(,SAVE) : GUI_ROW(,GAMEOPTIONS);
		if (canQuickSave)
			first_sel_row = GUI_ROW(,QUICKSAVE);

		gui->clear();
		gui->setTitle(oo::str::formatRuntime(OO_DESC("status-commander-@"), { TextArg(commanderName()) })); //Same title as status screen.
		
		gui->setText(OO_DESC("options-quick-save"), GUI_ROW(,QUICKSAVE), GUI_ALIGN_CENTER);
		if (canQuickSave)
			gui->setKey(std::string(GUI_KEY_OK), GUI_ROW(,QUICKSAVE));
		else
			gui->setColor(OOColor::grayColor().get(), GUI_ROW(,QUICKSAVE));

		gui->setText(OO_DESC("options-save-commander"), GUI_ROW(,SAVE), GUI_ALIGN_CENTER);
		gui->setText(OO_DESC("options-load-commander"), GUI_ROW(,LOAD), GUI_ALIGN_CENTER);
		if (canLoadOrSave)
		{
			gui->setKey(std::string(GUI_KEY_OK), GUI_ROW(,SAVE));
			gui->setKey(std::string(GUI_KEY_OK), GUI_ROW(,LOAD));
		}
		else
		{
			gui->setColor(OOColor::grayColor().get(), GUI_ROW(,SAVE));
			gui->setColor(OOColor::grayColor().get(), GUI_ROW(,LOAD));
		}

		gui->setText(OO_DESC("options-return-to-menu"), GUI_ROW(,BEGIN_NEW), GUI_ALIGN_CENTER);
		gui->setKey(std::string(GUI_KEY_OK), GUI_ROW(,BEGIN_NEW));

		gui->setText(OO_DESC("options-game-options"), GUI_ROW(,GAMEOPTIONS), GUI_ALIGN_CENTER);
		gui->setKey(std::string(GUI_KEY_OK), GUI_ROW(,GAMEOPTIONS));
		
#if OOLITE_SDL
		// GNUstep needs a quit option at present (no Cmd-Q) but
		// doesn't need speech.
		
		// quit menu option
		gui->setText(OO_DESC("options-exit-game"), GUI_ROW(,QUIT), GUI_ALIGN_CENTER);
		gui->setKey(std::string(GUI_KEY_OK), GUI_ROW(,QUIT));
#endif
		
		gui->setSelectableRange(NSMakeRange(first_sel_row, GUI_ROW_OPTIONS_END_OF_LIST));

		if (gamePaused || (!canLoadOrSave && status() == STATUS_DOCKED))
		{
			gui->setSelectedRow(GUI_ROW(,GAMEOPTIONS));
		}
		else
		{
			gui->setSelectedRow(first_sel_row);
		}
		
		gui->setShowTextCursor(NO);
		
		if (gui->setForegroundTextureKey(std::optional<std::string>(status() == STATUS_DOCKED ? "docked_overlay" : "paused_overlay")) && (UNIVERSE != nullptr ? UNIVERSE->pauseMessageVisible() : false))
					UNIVERSE->messageGUI()->clear();
		// Graphically, this screen is analogous to the various settings screens
		gui->setBackgroundTextureKey("settings");
	}
	/* ends */
	
	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->clearMouse();
	
	setShowDemoShips(NO);
	
	if (UNIVERSE != nullptr)  UNIVERSE->enterGUIViewModeWithMouseInteraction(YES);
	
	if (gamePaused)
	{
		UNIVERSE->messageGUI()->clear(); 
		const std::optional<std::string> pauseKey = (PLAYER != nullptr ? PLAYER->keyBindingDescription2("key_pausebutton") : std::optional<std::string>());
		if (UNIVERSE != nullptr)  UNIVERSE->addMessage(ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "game-paused-docked", { { "pauseKey", oo::PList(pauseKey.value_or(std::string())) } }), 1.0, YES);	// (nil raised in the expansion)
	}
	
	noteGUIDidChangeFrom(oldScreen, gui_screen);
}


void PlayerEntity::highlightEquipShipScreenKey(const std::string &highlightKey)
{
	int 			i=0;
	OOGUIRow		row;
	std::optional<std::string>	otherKey = std::string();
	::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	last_outfitting_key = highlightKey;
	setGuiToEquipShipScreen(-1);
	const std::optional<std::string> key = last_outfitting_key;
	// TODO: redo the equipShipScreen in a way that isn't broken. this whole method 'works'
	// based on the way setGuiToEquipShipScreen  'worked' on 20090913 - Kaks 
	
	// setGuiToEquipShipScreen doesn't take a page number, it takes an offset from the beginning
	// of the dictionary, the first line will show the key at that offset...
	
	// try the last page first - 10 pages max.
	while (otherKey)
	{
		setGuiToEquipShipScreen(i);
		for (row = GUI_ROW_EQUIPMENT_START;row<=GUI_MAX_ROWS_EQUIPMENT+2;row++)
		{
			otherKey = gui->keyForRow(row);
			if (!otherKey)
			{
				setGuiToEquipShipScreen(0);
				return;
			}
			if (otherKey == key)
			{
				gui->setSelectedRow(row);
				showInformationForSelectedUpgrade();
				return;
			}
		}
		if (oo::str::hasPrefix(*otherKey, "More:"))
		{
			const std::vector<std::string> components = oo::str::split(*otherKey, ":");
			i = (components.size() > 1) ? oo::str::intValue(components[1]) : 0;
		}
		else
		{
			setGuiToEquipShipScreen(0);
			return;
		}
	}
}


OOWeaponFacingSet PlayerEntity::availableFacings()
{
	::OOShipRegistry		*registry = OOShipRegistry::sharedRegistry();
	const oo::PList		shipyardInfo = registry->shipyardInfoForKey(shipDataKey().value_or(""));
	unsigned			available_facings = shipyardInfo.get<unsigned int>(std::string(KEY_WEAPON_FACINGS), weaponFacings());	// use defaults  explicitly
	
	return available_facings & VALID_WEAPON_FACINGS;
}



// Slice 20 of docs/phases/3-slices/PlayerEntity.md (bead oo-dycza): the equip-ship screen and upgrade information.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

void PlayerEntity::setGuiToEquipShipScreen(int skipParam, const std::optional<std::string> &eqKeyForSelectFacing)
{
	if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setMouseInteractionModeForUIWithMouseInteraction(YES);
	
	missiles = countMissiles();
	OOEntityStatus searchStatus; // use STATUS_TEST, STATUS_DEAD & STATUS_ACTIVE
	std::optional<std::string> showKey;
	unsigned skip;

	if (skipParam < 0)
	{
		skip = 0;
		searchStatus = STATUS_TEST;
	}
	else
	{
		skip = skipParam;
		searchStatus = STATUS_ACTIVE;
	}

	// don't show a "Back" item if we're only skipping one item - just show the item
	if (skip == 1)
		skip = 0;

	double priceFactor = 1.0;
	OOTechLevelID techlevel = (UNIVERSE != nullptr ? UNIVERSE->currentSystemData() : oo::PList()).get<int>(std::string(KEY_TECHLEVEL));

	::StationEntity *dockedStation = this->dockedStation();
	if (dockedStation)
	{
		priceFactor = (dockedStation != nullptr ? dockedStation->getEquipmentPriceFactor() : 0.0f);
		if ((dockedStation != nullptr ? dockedStation->getEquivalentTechLevel() : 0) != NSNotFound)
			techlevel = (dockedStation != nullptr ? dockedStation->getEquivalentTechLevel() : 0);
	}

	// build an array of all equipment - and take away that which has been bought (or is not permitted)
	std::vector<std::string>	equipmentAllowed;

	// find options that agree with this ship (a set of keys: only the string elements could ever match)
	::OOShipRegistry		*registry = OOShipRegistry::sharedRegistry();
	const oo::PList		shipyardInfo = registry->shipyardInfoForKey(shipDataKey().value_or(""));
	std::set<std::string>	options;
	const auto addOptions = [&options](const oo::PList *list)
	{
		for (std::size_t n = 0; list != nullptr && n < list->count(); n++)
		{
			const oo::PList *item = list->at(n);
			if (item->isString())  options.insert(*item->getIf<std::string>());
		}
	};
	addOptions(shipyardInfo.get<oo::PList::Array>(std::string(KEY_OPTIONAL_EQUIPMENT)));

	// add standard items too!
	const oo::PList		*standardEquipment = shipyardInfo.get<oo::PList::Dict>(std::string(KEY_STANDARD_EQUIPMENT));
	addOptions(standardEquipment != nullptr ? standardEquipment->get<oo::PList::Array>(std::string(KEY_EQUIPMENT_EXTRAS)) : nullptr);

	unsigned			i = 0;
	unsigned			available_facings = shipyardInfo.get<unsigned int>(std::string(KEY_WEAPON_FACINGS), weaponFacings());	// use defaults  explicitly

	
	if (eqKeyForSelectFacing.has_value()) // Weapons purchase subscreen.
	{
		skip = 1;	// show the back button
		// The 3 lines below are needed by the present GUI. TODO:create a sane GUI. Kaks - 20090915 & 201005
		equipmentAllowed.push_back(*eqKeyForSelectFacing);
		equipmentAllowed.push_back(*eqKeyForSelectFacing);
		equipmentAllowed.push_back(*eqKeyForSelectFacing);
	}
	else for (const oo::Ref<::OOEquipmentType> &eqTypeRef : OOEquipmentType::allEquipmentTypesOutfitting())	// (i counts at the end of the body)
	{
		::OOEquipmentType *eqType = eqTypeRef.get();
		const std::string	eqKey = (eqType != nullptr ? eqType->identifier() : std::optional<std::string>()).value_or("");
		OOTechLevelID		minTechLevel = (eqType != nullptr ? eqType->effectiveTechLevel() : 0);
		
		// set initial availability to NO
		BOOL isOK = NO;
		
		// check special availability
		if ((eqType != nullptr ? eqType->isAvailableToAll() : false))  options.insert(eqKey);
		
		// if you have a damaged system you can get it repaired at a tech level one less than that required to buy it
		if (minTechLevel != 0 && hasEquipmentItem(OptionalKeyPList((eqType != nullptr ? eqType->damagedIdentifier() : std::optional<std::string>()))))  minTechLevel--;
		
		// reduce the minimum techlevel occasionally as a bonus..
		if (techlevel < minTechLevel && techlevel + 3 > minTechLevel)
		{
			unsigned day = i * 13 + (unsigned)floor((UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) / 86400.0);
			unsigned char dayRnd = (day & 0xff) ^ (unsigned char)system_id;
			OOTechLevelID originalMinTechLevel = minTechLevel;
			
			while (minTechLevel > 0 && minTechLevel > originalMinTechLevel - 3 && !(dayRnd & 7))	// bargain tech days every 1/8 days
			{
				dayRnd = dayRnd >> 2;
				minTechLevel--;	// occasional bonus items according to TL
			}
		}
		
		// check initial availability against options AND standard extras
		if (options.contains(eqKey))
		{
			isOK = YES;
			options.erase(eqKey);
		}

		if (isOK)
		{
			if (techlevel < minTechLevel) isOK = NO;
			if (!canAddEquipment(eqKey, "purchase")) isOK = NO;
			if (available_facings == 0 && (eqType != nullptr ? eqType->isPrimaryWeapon() : false)) isOK = NO;
			if (isOK)  equipmentAllowed.push_back(eqKey);
		}
		
		if (searchStatus == STATUS_DEAD && isOK)
		{
			showKey = eqKey;
			searchStatus = STATUS_ACTIVE;
		}
		if (searchStatus == STATUS_TEST)
		{
			if (isOK) showKey = eqKey;
			if (eqKey == last_outfitting_key)
				searchStatus = isOK ? STATUS_ACTIVE : STATUS_DEAD;
		}
		i++;
	}
	if (searchStatus != STATUS_TEST && showKey.has_value())
	{
		last_outfitting_key = showKey;
	}
	
	// GUI stuff
	{
		::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
		OOGUIRow		start_row = GUI_ROW_EQUIPMENT_START;
		OOGUIRow		row = start_row;
		unsigned        facing_count = 0;
		BOOL			displayRow = YES;
		BOOL			weaponMounted = NO;
		BOOL			guiChanged = (gui_screen != GUI_SCREEN_EQUIP_SHIP);

		gui_screen = GUI_SCREEN_EQUIP_SHIP;

		gui->clearAndKeepBackground(!guiChanged);
		gui->setTitle(OO_DESC("equip-title"));
		
		gui->setColor(gui->colorFromSetting(cxx_kGuiEquipmentCashColor, nil).get(), GUI_ROW_EQUIPMENT_CASH);
		gui->setText(cxx_OOExpandKey("equip-cash-value", credits).value_or(std::string()), GUI_ROW_EQUIPMENT_CASH);
		
		OOGUITabSettings tab_stops;
		tab_stops[0] = 0;
		tab_stops[1] = -360;
		tab_stops[2] = -480;
		gui->overrideTabs(tab_stops, cxx_kGuiEquipmentTabs, 3);
		gui->setTabStops(tab_stops);
		
		unsigned n_rows = GUI_MAX_ROWS_EQUIPMENT;
		NSUInteger count = equipmentAllowed.size();

		if (count > 0)
		{
			if (skip > 0)	// lose the first row to Back <--
			{
				unsigned previous;

				if (count <= n_rows || skip < n_rows)
					previous = 0;					// single page
				else
				{
					previous = skip - (n_rows - 2);	// multi-page. 
					if (previous < 2)
						previous = 0;				// if only one previous item, just show it
				}

				if (eqKeyForSelectFacing.has_value())
				{
					previous = 0;
					// keep weapon selected if we go back.
					gui->setKey(oo::str::format("More:%d:%s", previous, eqKeyForSelectFacing->c_str()), row);
				}
				else
				{
					gui->setKey(oo::str::format("More:%d", previous), row);
				}
				gui->setColor(gui->colorFromSetting(cxx_kGuiEquipmentScrollColor, OOColor::greenColor().get()).get(), row);
				gui->setArray({ OO_DESC("gui-back"), "", " <-- " }, row);
				row++;
			}
			
			for (i = skip; i < count && (row - start_row < (OOGUIRow)n_rows); i++)
			{
				const std::string	&eqKey = equipmentAllowed[i];
				::OOEquipmentType		*eqInfo = OOEquipmentType::equipmentTypeWithIdentifier(eqKey).get();
				OOCreditsQuantity	pricePerUnit = (eqInfo != nullptr ? eqInfo->price() : 0);
				std::string			desc = oo::str::format(" %s ", (eqInfo != nullptr ? eqInfo->name() : std::optional<std::string>()).value_or("(null)").c_str());
				double				price;

				oo::Ref<OOColor>	dispCol((eqInfo != nullptr ? eqInfo->displayColor().get() : (OOColor *)nullptr));
				if (dispCol == nil) dispCol = gui->colorFromSetting(cxx_kGuiEquipmentOptionColor, nil);
				gui->setColor(dispCol.get(), row); 

				if (eqKey == "EQ_FUEL")
				{
					price = (PLAYER_MAX_FUEL - fuel) * pricePerUnit * fuelChargeRate();
				}
				else if (eqKey == "EQ_RENOVATION")
				{
					price = renovationCosts();
					gui->setColor(gui->colorFromSetting(cxx_kGuiEquipmentRepairColor, OOColor::orangeColor().get()).get(), row);
				}
				else
				{
					price = pricePerUnit;
				}
				
				price = adjustPriceByScriptForEqKey(eqKey, price);

				price *= priceFactor;  // increased prices at some stations
				
				NSUInteger installTime = (eqInfo != nullptr ? eqInfo->installTime() : 0);
				if (installTime == 0)
				{
					installTime = 600 + price;
				}
				// is this item damaged?
				if (hasEquipmentItem(OptionalKeyPList((eqInfo != nullptr ? eqInfo->damagedIdentifier() : std::optional<std::string>()))))
				{
					desc = oo::str::formatRuntime(OO_DESC("equip-repair-@"), { desc });
					price /= 2.0;
					installTime = (eqInfo != nullptr ? eqInfo->repairTime() : 0);
					if (installTime == 0)
					{
						installTime = 600 + price;
					}
					gui->setColor(gui->colorFromSetting(cxx_kGuiEquipmentRepairColor, OOColor::orangeColor().get()).get(), row);

				}
				
				const std::string timeString = (UNIVERSE != nullptr ? UNIVERSE->shortTimeDescription(installTime) : std::optional<std::string>()).value_or("(null)");
				std::string priceString = oo::str::format(" %s ", cxx_OOCredits(price).c_str());

				if (eqKeyForSelectFacing == eqKey)
				{
					// Weapons purchase subscreen.
					while (facing_count < 5)
					{
						NSUInteger multiplier = 1;
						switch (facing_count)
						{
							case 0:
								break;
								
							case 1:
								displayRow = available_facings & WEAPON_FACING_FORWARD;
								desc = FORWARD_FACING_STRING;
								weaponMounted = !isWeaponNone(forward_weapon_type);
								if (_multiplyWeapons)
								{
									multiplier = forwardWeaponOffset.size();
								}
								break;
								
							case 2:
								displayRow = available_facings & WEAPON_FACING_AFT;
								desc = AFT_FACING_STRING;
								weaponMounted = !isWeaponNone(aft_weapon_type);
								if (_multiplyWeapons)
								{
									multiplier = aftWeaponOffset.size();
								}
								break;
								
							case 3:
								displayRow = available_facings & WEAPON_FACING_PORT;
								desc = PORT_FACING_STRING;
								weaponMounted = !isWeaponNone(port_weapon_type);
								if (_multiplyWeapons)
								{
									multiplier = portWeaponOffset.size();
								}
								break;
								
							case 4:
								displayRow = available_facings & WEAPON_FACING_STARBOARD;
								desc = STARBOARD_FACING_STRING;
								weaponMounted = !isWeaponNone(starboard_weapon_type);
								if (_multiplyWeapons)
								{
									multiplier = starboardWeaponOffset.size();
								}
								break;
						}
						
						if(weaponMounted)
						{
							gui->setColor(gui->colorFromSetting(cxx_kGuiEquipmentLaserFittedColor, OOColor::colorWithRed(0.0f, 0.6f, 0.0f, 1.0f).get()).get(), row);
						}
						else
						{
							gui->setColor(gui->colorFromSetting(cxx_kGuiEquipmentLaserColor, OOColor::greenColor().get()).get(), row);
						}
						if (displayRow)	// Always true for the first pass. The first pass is used to display the name of the weapon being purchased.
						{

							priceString = oo::str::format(" %s ", cxx_OOCredits(price*multiplier).c_str());

							gui->setKey(eqKey, row);
							gui->setArray({ desc, (facing_count > 0 ? priceString : std::string()), timeString }, row);
							row++;
						}
						facing_count++;
					}
				}
				else
				{
					// Normal equipment list.
					gui->setKey(eqKey, row);
					// check if the hidevalues property has been set
					if (!(eqInfo != nullptr ? eqInfo->hideValues() : false))
					{
						gui->setArray({ desc, priceString, timeString }, row);
					}
					else
					{
						// if so, only output the description
						gui->setArray({ desc }, row);
					}
					row++;
				}
			}

			if (i < count)
			{
				// just overwrite the last item :-)
				gui->setColor(gui->colorFromSetting(cxx_kGuiEquipmentScrollColor, OOColor::greenColor().get()).get(), row-1);
				gui->setArray({ OO_DESC("gui-more"), "", " --> " }, row - 1);
				gui->setKey(oo::str::format("More:%d", i - 1), row - 1);
			}
			
			gui->setSelectableRange(NSMakeRange(start_row,row - start_row));

			if (gui->getSelectedRow() != start_row)
				gui->setSelectedRow(start_row);

			if (eqKeyForSelectFacing.has_value())
			{
				gui->setSelectedRow(start_row + 1);
				showInformationForSelectedUpgradeWithFormatString(OO_DESC("@-select-where-to-install"));
			}
			else
			{
				showInformationForSelectedUpgrade();
			}
		}
		else
		{
			gui->setText(OO_DESC("equip-no-equipment-available-for-purchase"), GUI_ROW_NO_SHIPS, GUI_ALIGN_CENTER);
			gui->setColor(gui->colorFromSetting(cxx_kGuiEquipmentUnavailableColor, OOColor::greenColor().get()).get(), GUI_ROW_NO_SHIPS);
			
			gui->setSelectableRange(NSMakeRange(0,0));
			gui->setNoSelectedRow();
			showInformationForSelectedUpgrade();
		}
		
		gui->setShowTextCursor(NO);
		
		// TODO: split the mount_weapon sub-screen into a separate screen, and use it for pylon mounted wepons as well?
		if (guiChanged)
		{
			gui->setForegroundTextureKey("docked_overlay");
			const oo::PList background = (UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey("equip_ship") : oo::PList());
			setEquipScreenBackgroundDescriptor(background);
			gui->setBackgroundTextureDescriptor(background);
		}
		else if (eqKeyForSelectFacing.has_value()) // weapon purchase
		{
			const oo::PList bgDescriptor = (UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey("mount_weapon") : oo::PList());
			if (!bgDescriptor.isNull())  gui->setBackgroundTextureDescriptor(bgDescriptor);
		}
		else // Returning from a weapon purchase. (Also called, redundantly, when paging)
		{
			gui->setBackgroundTextureDescriptor(equipScreenBackgroundDescriptor());
		}
	}
	/* ends */

	chosen_weapon_facing = WEAPON_FACING_NONE;

	setShowDemoShips(NO);
	if (UNIVERSE != nullptr)  UNIVERSE->enterGUIViewModeWithMouseInteraction(YES);
}


void PlayerEntity::setGuiToEquipShipScreen(int skip)
{
	setGuiToEquipShipScreen(skip, std::nullopt);
}


void PlayerEntity::showInformationForSelectedUpgrade()
{
	showInformationForSelectedUpgradeWithFormatString(std::nullopt);
}


void PlayerEntity::showInformationForSelectedUpgradeWithFormatString(const std::optional<std::string> &formatString)
{
	::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	const std::optional<std::string> eqKey = gui->selectedRowKey();
	int i;

	oo::Ref<OOColor>	descColor = gui->colorFromSetting(cxx_kGuiEquipmentDescriptionColor, OOColor::greenColor().get());
	for (i = GUI_ROW_EQUIPMENT_DETAIL; i < GUI_MAX_ROWS; i++)
	{
		gui->setText(std::string(), i);
		gui->setColor(descColor.get(), i);
	}
	if (eqKey)
	{
		if (!oo::str::hasPrefix(*eqKey, "More:"))
		{
			std::optional<std::string> desc = (OOEquipmentType::equipmentTypeWithIdentifier(*eqKey).get() != nullptr ? OOEquipmentType::equipmentTypeWithIdentifier(*eqKey).get()->descriptiveText() : std::optional<std::string>());
			const std::string eq_key_damaged = *eqKey + "_DAMAGED";
			int weight = (OOEquipmentType::equipmentTypeWithIdentifier(*eqKey).get() != nullptr ? OOEquipmentType::equipmentTypeWithIdentifier(*eqKey).get()->requiredCargoSpace() : 0);
			if (hasEquipmentItem(oo::PList(eq_key_damaged)))
			{
				desc = oo::str::formatRuntime(OO_DESC("upgradeinfo-@-price-is-for-repairing"), { TextArg(desc) });
			}
			else
			{
				if(oo::str::hasSuffix(*eqKey, "ENERGY_UNIT") && (hasEquipmentItem(oo::PList("EQ_ENERGY_UNIT_DAMAGED")) || hasEquipmentItem(oo::PList("EQ_ENERGY_UNIT")) || hasEquipmentItem(oo::PList("EQ_NAVAL_ENERGY_UNIT_DAMAGED"))))
					desc = oo::str::formatRuntime(OO_DESC("@-will-replace-other-energy"), { TextArg(desc) });
				if (weight > 0) desc = oo::str::formatRuntime(OO_DESC("upgradeinfo-@-weight-d-of-equipment"), { TextArg(desc), weight });
			}
			if (formatString.has_value()) desc = oo::str::formatRuntime(*formatString, { TextArg(desc) });
			gui->addLongText(desc, GUI_ROW_EQUIPMENT_DETAIL, GUI_ALIGN_LEFT);
		}
	}
}



// Slice 21 of docs/phases/3-slices/PlayerEntity.md (bead oo-a602n): the interfaces screen, the start screen and intro, the OXZ manager, GUI and view change notes.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

void PlayerEntity::setGuiToInterfacesScreen(int skip)
{
	if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setMouseInteractionModeForUIWithMouseInteraction(YES);
	if (gui_screen != GUI_SCREEN_INTERFACES)
	{
		noteGUIWillChangeTo(GUI_SCREEN_INTERFACES);
	}
	
	// build an array of available interfaces
	const auto *interfaces = (dockedStation() != nullptr ? dockedStation()->getLocalInterfaces() : (std::map<std::string, oo::Ref<OOJSInterfaceDefinition>, std::less<>> *)nullptr);
	std::vector<std::string> interfaceKeys;
	if (interfaces != nullptr)
	{
		for (const auto &entry : *interfaces)  interfaceKeys.push_back(entry.first);
		// sorts by category, then title. ORDER-SENSITIVE: ties now keep the map's byte order of keys
		std::stable_sort(interfaceKeys.begin(), interfaceKeys.end(), [interfaces](const std::string &a, const std::string &b)
		{
			return interfaces->find(a)->second->interfaceCompare(interfaces->find(b)->second.get()) == OOOrderedAscending;
		});
	}
	int i;

	OOGUIScreenID	oldScreen = gui_screen;

	// GUI stuff
	{
		::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
		OOGUIRow		start_row = GUI_ROW_INTERFACES_START;
		OOGUIRow		row = start_row;
		BOOL			guiChanged = (gui_screen != GUI_SCREEN_INTERFACES);

		gui->clearAndKeepBackground(!guiChanged);
		gui->setTitle(OO_DESC("interfaces-title"));
		
		gui_screen = GUI_SCREEN_INTERFACES;
		
		OOGUITabSettings tab_stops;
		tab_stops[0] = 0;
		tab_stops[1] = -480;
		gui->overrideTabs(tab_stops, cxx_kGuiInterfaceTabs, 2);
		gui->setTabStops(tab_stops);
		
		unsigned n_rows = GUI_MAX_ROWS_INTERFACES;
		NSUInteger count = interfaceKeys.size();

		if (count > 0)
		{
			if (skip > 0)	// lose the first row to Back <--
			{
				unsigned previous;
				
				if (count <= n_rows || skip < (NSInteger)n_rows)
				{
					previous = 0;					// single page
				}
				else
				{
					previous = skip - (n_rows - 2);	// multi-page. 
					if (previous < 2)
					{
						previous = 0;				// if only one previous item, just show it
					}
				}
				
				gui->setKey(oo::str::format("More:%d", static_cast<int>(previous)), row);
				gui->setColor(gui->colorFromSetting(cxx_kGuiInterfaceScrollColor, OOColor::greenColor().get()).get(), row);
				gui->setArray({ OO_DESC("gui-back"), " <-- " }, row);
				row++;
			}
			
			for (i = skip; i < (NSInteger)count && (row - start_row < (OOGUIRow)n_rows); i++)
			{
				const std::string &interfaceKey = interfaceKeys[i];
				::OOJSInterfaceDefinition *definition = interfaces->find(interfaceKey)->second.get();

				gui->setColor(gui->colorFromSetting(cxx_kGuiInterfaceEntryColor, nil).get(), row);
				gui->setKey(interfaceKey, row);
				// title, category: the list ends at the first nil, as arrayWithObjects: did
				std::vector<std::string> columns;
				const std::optional<std::string> title = definition->title();
				if (title.has_value())
				{
					columns.push_back(*title);
					const std::optional<std::string> category = definition->category();
					if (category.has_value())  columns.push_back(*category);
				}
				gui->setArray(columns, row);

				row++;
			}

			if (i < (NSInteger)count)
			{
				// just overwrite the last item :-)
				gui->setColor(gui->colorFromSetting(cxx_kGuiInterfaceScrollColor, OOColor::greenColor().get()).get(), row - 1);
				gui->setArray({ OO_DESC("gui-more"), " --> " }, row - 1);
				gui->setKey(oo::str::format("More:%d", i - 1), row - 1);
			}
			
			gui->setSelectableRange(NSMakeRange(start_row,row - start_row));

			if (gui->getSelectedRow() != start_row)
			{
				gui->setSelectedRow(start_row);
			}

			showInformationForSelectedInterface();
		}
		else
		{
			gui->setText(OO_DESC("interfaces-no-interfaces-available-for-use"), GUI_ROW_NO_INTERFACES, GUI_ALIGN_LEFT);
			gui->setColor(gui->colorFromSetting(cxx_kGuiInterfaceNoneColor, OOColor::greenColor().get()).get(), GUI_ROW_NO_INTERFACES);
			
			gui->setSelectableRange(NSMakeRange(0,0));
			gui->setNoSelectedRow();

		}
		
		gui->setShowTextCursor(NO);

		const std::string desc = oo::str::formatRuntime(OO_DESC("interfaces-for-ship-@-and-station-@"),
			{ getDisplayName().value_or("(null)"), (dockedStation() != nullptr ? dockedStation()->getDisplayName() : std::optional<std::string>()).value_or("(null)") });
		gui->setColor(gui->colorFromSetting(cxx_kGuiInterfaceHeadingColor, nil).get(), GUI_ROW_INTERFACES_HEADING);
		gui->setText(desc, GUI_ROW_INTERFACES_HEADING);

		
		if (guiChanged)
		{
			gui->setForegroundTextureKey("docked_overlay");
			gui->setBackgroundTextureDescriptor((UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey("interfaces") : oo::PList()));
		}
	}
	/* ends */

	setShowDemoShips(NO);
	
	noteGUIDidChangeFrom(oldScreen, gui_screen);
	
	setShowDemoShips(NO);
	if (UNIVERSE != nullptr)  UNIVERSE->enterGUIViewModeWithMouseInteraction(YES);
}


void PlayerEntity::showInformationForSelectedInterface()
{
	::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	const std::optional<std::string> interfaceKey = gui->selectedRowKey();
	
	int i;
	
	for (i = GUI_ROW_EQUIPMENT_DETAIL; i < GUI_MAX_ROWS; i++)
	{
		gui->setText("", i);
		gui->setColor(gui->colorFromSetting(cxx_kGuiInterfaceDescriptionColor, OOColor::greenColor().get()).get(), i);
	}
	
	if (interfaceKey.has_value() && !oo::str::hasPrefix(*interfaceKey, "More:"))
	{
		::OOJSInterfaceDefinition *definition = InterfaceForKey(dockedStation(), interfaceKey);
		if (definition)
		{
			gui->addLongText(definition->summary(), GUI_ROW_INTERFACES_DETAIL, GUI_ALIGN_LEFT);
		}
	}
}


void PlayerEntity::activateSelectedInterface()
{
	::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	const std::optional<std::string> key = gui->selectedRowKey();

	if (key.has_value() && oo::str::hasPrefix(*key, "More:"))
	{
		int 		from_item = oo::str::intValue(RowKeyField(*key, 1).value_or(std::string()));
		setGuiToInterfacesScreen(from_item);

		if (gui->getSelectedRow() < 0)
			gui->setSelectedRow(GUI_ROW_INTERFACES_START);
		if (from_item == 0)
			gui->setSelectedRow(GUI_ROW_INTERFACES_START + GUI_MAX_ROWS_INTERFACES - 1);
		showInformationForSelectedInterface();


		return;
	}

	::OOJSInterfaceDefinition *definition = InterfaceForKey(dockedStation(), key);
	if (definition)
	{
		if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->clearKeys();
		definition->runCallback(*key);	// a definition was found, so key has a value
	}
	else
	{
		OO_LOG("interface.missingCallback", "Unable to find callback definition for key {}", key.value_or("(null)"));
	}
}


void PlayerEntity::setupStartScreenGui()
{
	::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	std::string		text;

	if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setMouseInteractionModeForUIWithMouseInteraction(YES);

	gui->clear();

	gui->setTitle("Oolite");

	text = OO_DESC("game-copyright");
	gui->setText(text, 15, GUI_ALIGN_CENTER);
	gui->setColor(OOColor::whiteColor().get(), 15);
		
	text = OO_DESC("theme-music-credit");
	gui->setText(text, 17, GUI_ALIGN_CENTER);
	gui->setColor(OOColor::grayColor().get(), 17);
		
	int initialRow = 22;
	int row = initialRow;

	text = OO_DESC("oolite-start-option-1");
	gui->setText(text, row, GUI_ALIGN_CENTER);
	gui->setColor(OOColor::yellowColor().get(), row);
	gui->setKey(oo::str::format("Start:%d", row), row);

	++row;

	text = OO_DESC("oolite-start-option-2");
	gui->setText(text, row, GUI_ALIGN_CENTER);
	gui->setColor(OOColor::yellowColor().get(), row);
	gui->setKey(oo::str::format("Start:%d", row), row);

	++row;

	text = OO_DESC("oolite-start-option-3");
	gui->setText(text, row, GUI_ALIGN_CENTER);
	gui->setColor(OOColor::yellowColor().get(), row);
	gui->setKey(oo::str::format("Start:%d", row), row);

	++row;

	text = OO_DESC("oolite-start-option-4");
	gui->setText(text, row, GUI_ALIGN_CENTER);
	gui->setColor(OOColor::yellowColor().get(), row);
	gui->setKey(oo::str::format("Start:%d", row), row);

	++row;

	text = OO_DESC("oolite-start-option-5");
	gui->setText(text, row, GUI_ALIGN_CENTER);
	gui->setColor(OOColor::yellowColor().get(), row);
	gui->setKey(oo::str::format("Start:%d", row), row);

	++row;

	text = OO_DESC("oolite-start-option-6");
	gui->setText(text, row, GUI_ALIGN_CENTER);
	gui->setColor(OOColor::yellowColor().get(), row);
	gui->setKey(oo::str::format("Start:%d", row), row);


	gui->setSelectableRange(NSMakeRange(initialRow, row - initialRow + 1));
	gui->setSelectedRow(initialRow);

	gui->setBackgroundTextureKey("intro");
}


/**
 * \ingroup cli
 * Scans the command line for -message or -showversion arguments.
 */
void PlayerEntity::setGuiToIntroFirstGo(bool justCobra)
{
	std::string 	text;
	::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	OOGUIRow 		msgLine = 2;
	
	if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setMouseInteractionModeForUIWithMouseInteraction(NO);
	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->clearMouse();
	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->clearKeys();


	if (justCobra)
	{
		if (UNIVERSE != nullptr)  UNIVERSE->removeDemoShips();
		OOCacheManager::sharedCache()->flush();	// At first startup, a lot of stuff is cached
	}
	
	if (justCobra)
	{
		setupStartScreenGui();
		
		// check for error messages from Resource Manager
		//ResourceManager::paths(); done in Universe already
		const std::optional<std::string> errors = ResourceManager::errors();
		if (errors.has_value())
		{
			OOGUIRow ms_start = msgLine;
			OOGUIRow i = msgLine = gui->addLongText(errors, ms_start, GUI_ALIGN_LEFT);
			for (i-- ; i >= ms_start ; i--) gui->setColor(OOColor::redColor().get(), i);
			msgLine++;
		}
		
		// check for messages from OXPs
		const std::vector<std::string> OXPsWithMessages = ResourceManager::OXPsWithMessagesFound();
		if (OXPsWithMessages.size() > 0)
		{
			std::optional<std::string> messageToDisplay = std::string();

			// Show which OXPs were found with messages, but don't spam the screen if more than
			// a certain number of them exist
			if (OXPsWithMessages.size() < 5)
			{
				std::string messageSourceList;	// joined with ", "
				for (const std::string &source : OXPsWithMessages)
				{
					if (!messageSourceList.empty())  messageSourceList += ", ";
					messageSourceList += source;
				}
				messageToDisplay = ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "oxp-containing-messages-list", { { "messageSourceList", oo::PList(messageSourceList) } });
			} else {
				messageToDisplay = cxx_OOExpandKey("oxp-containing-messages-found");
			}

			OOGUIRow ms_start = msgLine;
			OOGUIRow i = msgLine = gui->addLongText(messageToDisplay, ms_start, GUI_ALIGN_LEFT);
			for (i--; i >= ms_start; i--)
			{
				gui->setColor(OOColor::orangeColor().get(), i);
			}
			msgLine++;
		}
		
		// check for messages from the command line
		const std::vector<std::string> &arguments = oo::process::arguments();
		unsigned i;
		for (i = 0; i < arguments.size(); i++)
		{
			if ((arguments[i] == "-message")&&(i < arguments.size() - 1))
			{
				OOGUIRow ms_start = msgLine;
				const std::string &message = arguments[i + 1];
				OOGUIRow i = msgLine = gui->addLongText(message, ms_start, GUI_ALIGN_CENTER);
				for (i-- ; i >= ms_start; i--)
				{
					gui->setColor(OOColor::magentaColor().get(), i);
				}
			}
			if (arguments[i] == "-showversion")
			{
				OOGUIRow ms_start = msgLine;
				const std::string version = "Version " OO_VERSION_FULL;
				OOGUIRow i = msgLine = gui->addLongText(version, ms_start, GUI_ALIGN_CENTER);
				for (i-- ; i >= ms_start; i--)
				{
					gui->setColor(OOColor::magentaColor().get(), i);
				}
			}
		}
	}
	else
	{
		gui->clear();

        text = OO_DESC("oolite-ship-library-title");
		gui->setTitle(text);

        text = OO_DESC("oolite-ship-library-exit");
        gui->setText(text, 27, GUI_ALIGN_CENTER);
        gui->setColor(OOColor::yellowColor().get(), 27);
	}
	
	gui->setShowTextCursor(NO);
	
	if (UNIVERSE != nullptr)  UNIVERSE->setupIntroFirstGo(justCobra);
	
	if (gui != nil)  
	{
		gui_screen = justCobra ? GUI_SCREEN_INTRO1 : GUI_SCREEN_SHIPLIBRARY;
	}
	if (status() == STATUS_START_GAME)
	{
		OOMusicController::sharedController()->playThemeMusic();
	}
	
	setShowDemoShips(YES);
	if (justCobra)
	{
		gui->setBackgroundTextureKey("intro");
	}
	else
	{
		gui->setBackgroundTextureKey("shiplibrary");
	}
	if (UNIVERSE != nullptr)  UNIVERSE->enterGUIViewModeWithMouseInteraction(YES);
}


void PlayerEntity::setGuiToOXZManager()
{

	if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setMouseInteractionModeForUIWithMouseInteraction(NO);
	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->clearMouse();
	if (UNIVERSE != nullptr)  UNIVERSE->removeDemoShips();

	gui_screen = GUI_SCREEN_OXZMANAGER;

	UNIVERSE->getGui()->clearAndKeepBackground(NO);

	::OOOXZManager::sharedManager()->gui();
	
	OOMusicController::sharedController()->playThemeMusic();
	UNIVERSE->getGui()->setBackgroundTextureKey("oxz-manager");
	if (UNIVERSE != nullptr)  UNIVERSE->enterGUIViewModeWithMouseInteraction(YES);
}


void PlayerEntity::noteGUIWillChangeTo(OOGUIScreenID toScreen)
{
	ooscript::Context context = OOJSAcquireContext();
	ShipScriptEvent(context, this, "guiScreenWillChange", OOJSValueFromGUIScreenID(context, toScreen), OOJSValueFromGUIScreenID(context, gui_screen));
	OOJSRelinquishContext(context);
}


void PlayerEntity::noteGUIDidChangeFrom(OOGUIScreenID fromScreen, OOGUIScreenID toScreen)
{
	noteGUIDidChangeFrom(fromScreen, toScreen, NO);
}


void PlayerEntity::noteGUIDidChangeFrom(OOGUIScreenID fromScreen, OOGUIScreenID toScreen, bool refresh)
{
	// No events triggered if we're changing screens while paused, or if screen never actually changed.
	if (fromScreen != toScreen || refresh)
	{
		// MKW - release GUI Screen ship, if we have one
		switch (fromScreen)
		{
			case GUI_SCREEN_SHIPYARD:
			case GUI_SCREEN_LOAD:
			case GUI_SCREEN_SAVE:
				demoShip = nullptr;
				break;
			default:
				// Nothing
				break;

		}
		
		if (toScreen == GUI_SCREEN_SYSTEM_DATA)
		{
			// system data screen: ensure correct sun light color is used on miniature planet
			if ((UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr) != nullptr)  UNIVERSE->sun()->setSunColor(OOColor::colorWithDescription(((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getProperty("sun_color", info_system_id, galaxyNumber()) : oo::PList())).get());
		}
		else
		{
			// any other screen: reset local sun light color
			if ((UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr) != nullptr)  UNIVERSE->sun()->setSunColor(OOColor::colorWithDescription(((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getProperty("sun_color", system_id, galaxyNumber()) : oo::PList())).get());
		}
		
		if (!(UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr ? UNIVERSE->gameController()->isGamePaused() : false))
		{
			ooscript::Context context = OOJSAcquireContext();
			ShipScriptEvent(context, this, "guiScreenChanged", OOJSValueFromGUIScreenID(context, toScreen), OOJSValueFromGUIScreenID(context, fromScreen));
			OOJSRelinquishContext(context);
		}
	}
}


void PlayerEntity::noteViewDidChangeFrom(OOViewID fromView, OOViewID toView)
{
	noteSwitchToView(toView, fromView);
}



// Slice 22 of docs/phases/3-slices/PlayerEntity.md (bead oo-mv49m): buying equipment, script price adjustment, weapon mounts, passenger berths, removing missiles, trade-in.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

void PlayerEntity::buySelectedItem()
{
	::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	const std::optional<std::string> key = gui->selectedRowKey();

	if (key.has_value() && oo::str::hasPrefix(*key, "More:"))
	{
		int 		from_item = oo::str::intValue(RowKeyField(*key, 1).value_or(std::string()));
		const std::optional<std::string> weaponKey = RowKeyField(*key, 2);

		setGuiToEquipShipScreen(from_item);
		if (weaponKey.has_value())
		{
			highlightEquipShipScreenKey(*weaponKey);
		}
		else
		{
			if (gui->getSelectedRow() < 0)
				gui->setSelectedRow(GUI_ROW_EQUIPMENT_START);
			if (from_item == 0)
				gui->setSelectedRow(GUI_ROW_EQUIPMENT_START + GUI_MAX_ROWS_EQUIPMENT - 1);
			showInformationForSelectedUpgrade();
		}

		return;
	}
	
	const std::optional<std::string> itemText = gui->selectedRowText();

	// isEqual: of the row text (nil matched nothing)
	const auto itemTextIs = [&itemText](const std::string &facingString) { return itemText.has_value() && *itemText == facingString; };
	// FIXME: this is nuts, should be associating lines with keys in some sensible way. --Ahruman 20080311
	if (itemTextIs(FORWARD_FACING_STRING))
		chosen_weapon_facing = WEAPON_FACING_FORWARD;
	if (itemTextIs(AFT_FACING_STRING))
		chosen_weapon_facing = WEAPON_FACING_AFT;
	if (itemTextIs(PORT_FACING_STRING))
		chosen_weapon_facing = WEAPON_FACING_PORT;
	if (itemTextIs(STARBOARD_FACING_STRING))
		chosen_weapon_facing = WEAPON_FACING_STARBOARD;

	OOCreditsQuantity old_credits = credits;
	::OOEquipmentType *eqInfo = (key.has_value() ? OOEquipmentType::equipmentTypeWithIdentifier(*key).get() : nil);
	BOOL isRepair = hasEquipmentItem(OptionalKeyPList((eqInfo != nullptr ? eqInfo->damagedIdentifier() : std::optional<std::string>())));
	if (tryBuyingItem(key.value_or(std::string())))	// (a nil key bought nothing, as "" does)
	{
		if (credits == old_credits)
		{
			// laser pre-purchase, or free equipment
			playMenuNavigationDown();
		}
		else
		{
			playBuyCommodity();
		}			
			
		if(credits != old_credits || !(key.has_value() && oo::str::hasPrefix(*key, "EQ_WEAPON_")))
		{
			// adjust time before playerBoughtEquipment gets to change credits dynamically
			// wind the clock forward by 10 minutes plus 10 minutes for every 60 credits spent
			NSUInteger adjust = 0;
			if (isRepair)
			{
				adjust = (eqInfo != nullptr ? eqInfo->repairTime() : 0);
			}
			else
			{
				adjust = (eqInfo != nullptr ? eqInfo->installTime() : 0);
			}
			double time_adjust = (old_credits > credits) ? (old_credits - credits) : 0.0;
			if (UNIVERSE != nullptr)  UNIVERSE->forceWitchspaceEntries();
			if (adjust == 0)
			{
				ship_clock_adjust += time_adjust + 600.0;
			}
			else
			{
				ship_clock_adjust += (double)adjust;
			}
			
			// [key, price paid as a long long]; a nil key ended the list
			oo::PList::Array boughtArguments;
			if (key.has_value())  boughtArguments = { oo::PList(*key), oo::PList::signedInteger(static_cast<long long>(old_credits - credits)) };
			doScriptEvent(OOJSID("playerBoughtEquipment"), boughtArguments);
			if (gui_screen == GUI_SCREEN_EQUIP_SHIP) //if we haven't changed gui screen inside playerBoughtEquipment
			{ 
				// show any change due to playerBoughtEquipment
				setGuiToEquipShipScreen(0);
				// then try to go back where we were
				highlightEquipShipScreenKey(key.value_or(std::string()));
			}

			if ((UNIVERSE != nullptr ? UNIVERSE->getAutoSave() : false)) { if (UNIVERSE != nullptr)  UNIVERSE->setAutoSaveNow(YES); }
		}
	}
	else
	{
		playCantBuyCommodity();
	}
}


OOCreditsQuantity PlayerEntity::adjustPriceByScriptForEqKey(const std::string &eqKey, OOCreditsQuantity price)
{
	const std::optional<std::string> condition_script = (OOEquipmentType::equipmentTypeWithIdentifier(eqKey).get() != nullptr ? OOEquipmentType::equipmentTypeWithIdentifier(eqKey).get()->conditionScript() : std::optional<std::string>());
	if (condition_script.has_value())
	{
		::OOScript *condScript = (UNIVERSE != nullptr ? UNIVERSE->getConditionScript(*condition_script) : nullptr);
		if (condScript != nil) // should always be non-nil, but just in case
		{
			ooscript::Context JScontext = OOJSAcquireContext();
			BOOL OK;
			ooscript::Value result;
			int32_t newPrice;
			ooscript::Value args[] = { OOJSValueFromPList(JScontext, oo::PList(eqKey)) , ooscript::nullValue() };
			OK = ooscript::newNumberValue(JScontext, price, &args[1]);
				
			if (OK)
			{
				OK = (condScript != nullptr ? condScript->callMethod(OOJSID("updateEquipmentPrice"), JScontext, args, sizeof args / sizeof *args, &result) : false);
			}

			if (OK)
			{
				OK = ooscript::valueToInt32(JScontext, result, &newPrice);
				if (OK && newPrice >= 0)
				{
					price = (OOCreditsQuantity)newPrice;
				}
			}
			OOJSRelinquishContext(JScontext);
		}
	}
	return price;
}


bool PlayerEntity::tryBuyingItem(const std::string &eqKey)
{
	// note this doesn't check the availability by tech-level
	::OOEquipmentType			*eqType			= OOEquipmentType::equipmentTypeWithIdentifier(eqKey).get();
	OOCreditsQuantity		pricePerUnit	= (eqType != nullptr ? eqType->price() : 0);
	const std::optional<std::string>	eqKeyDamaged	= (eqType != nullptr ? eqType->damagedIdentifier() : std::optional<std::string>());
	double					price			= pricePerUnit;
	double					priceFactor		= 1.0;
	OOCreditsQuantity		tradeIn			= 0;
	BOOL	isRepair = NO;
	
	// repairs cost 50%
	if (hasEquipmentItem(OptionalKeyPList(eqKeyDamaged)))
	{
		price /= 2.0;
		isRepair = YES;
	}
	
	if ((eqKey == "EQ_RENOVATION"))
	{
		price = renovationCosts();
	}
	
	price = adjustPriceByScriptForEqKey(eqKey, price);

	::StationEntity *dockedStation = this->dockedStation();
	if (dockedStation)
	{
		priceFactor = (dockedStation != nullptr ? dockedStation->getEquipmentPriceFactor() : 0.0f);
	}
	
	price *= priceFactor;  // increased prices at some stations
	
	if (price > credits)
	{
		return NO;
	}
	
	if ((eqType != nullptr ? eqType->isPrimaryWeapon() : false))
	{
		if (chosen_weapon_facing == WEAPON_FACING_NONE)
		{
			setGuiToEquipShipScreen(0, eqKey);	// reset
			return YES;
		}
		
		OOWeaponType chosen_weapon = cxx_OOWeaponTypeFromEquipmentIdentifierStrict(eqKey);
		OOWeaponType current_weapon = nil;

		NSUInteger multiplier = 1;
		
		switch (chosen_weapon_facing)
		{
			case WEAPON_FACING_FORWARD:
				current_weapon = forward_weapon_type;
				forward_weapon_type = chosen_weapon;
				if (_multiplyWeapons)
				{
					multiplier = forwardWeaponOffset.size();
				}
				break;
				
			case WEAPON_FACING_AFT:
				current_weapon = aft_weapon_type;
				aft_weapon_type = chosen_weapon;
				if (_multiplyWeapons)
				{
					multiplier = aftWeaponOffset.size();
				}
				break;
				
			case WEAPON_FACING_PORT:
				current_weapon = port_weapon_type;
				port_weapon_type = chosen_weapon;
				if (_multiplyWeapons)
				{
					multiplier = portWeaponOffset.size();
				}
				break;
				
			case WEAPON_FACING_STARBOARD:
				current_weapon = starboard_weapon_type;
				starboard_weapon_type = chosen_weapon;
				if (_multiplyWeapons)
				{
					multiplier = starboardWeaponOffset.size();
				}
				break;
				
			case WEAPON_FACING_NONE:
				break;
		}

		price *= multiplier;
		
		if (price > credits)
		{
			// not enough money - ensure that weapon
			// type is reset to what it was before
			// the attempt to buy took place
			switch (chosen_weapon_facing)
			{
				case WEAPON_FACING_FORWARD:
					forward_weapon_type = current_weapon;
					break;
				case WEAPON_FACING_AFT:
					aft_weapon_type = current_weapon;
					break;
				case WEAPON_FACING_PORT:
					port_weapon_type = current_weapon;
					break;
				case WEAPON_FACING_STARBOARD:
					starboard_weapon_type = current_weapon;
					break;
				case WEAPON_FACING_NONE:
					break;
			}
			return NO;
		}
		credits -= price;
		
		// Refund current_weapon
		if (current_weapon != nil)
		{
			const std::optional<std::string> weaponKey = cxx_OOEquipmentIdentifierFromWeaponType(current_weapon);
			tradeIn = (weaponKey.has_value() ? (UNIVERSE != nullptr ? UNIVERSE->getEquipmentPriceForKey(*weaponKey) : 0) : 0) * multiplier;	// (a nil key priced 0)
		}
		
		doTradeIn(tradeIn, priceFactor);
		// If equipped, remove damaged weapon after repairs. -- But there's no way we should get a damaged weapon. Ever.
		removeEquipmentItem(eqKeyDamaged.value_or(std::string()));	// none: "", as nil was
		return YES;
	}
	
	if ((eqType != nullptr ? eqType->isMissileOrMine() : false) && missiles >= max_missiles)
	{
		OO_LOG("equip.buy.mounted.failed.full", "{}", "rejecting missile because already full");
		return NO;
	}
	
	// NSFO!
	//unsigned 	passenger_space = [[OOEquipmentType equipmentTypeWithIdentifier:@"EQ_PASSENGER_BERTH"] requiredCargoSpace];
	//if (passenger_space == 0) passenger_space = PASSENGER_BERTH_SPACE;
	
	if ((eqKey == "EQ_PASSENGER_BERTH") && availableCargoSpace() < PASSENGER_BERTH_SPACE)
	{
		return NO;
	}
	
	if ((eqKey == "EQ_FUEL"))
	{
#if MASS_DEPENDENT_FUEL_PRICES
		OOCreditsQuantity creditsForRefuel = (fuelCapacity() - getFuel()) * pricePerUnit * fuelChargeRate();
#else
		OOCreditsQuantity creditsForRefuel = (fuelCapacity() - getFuel()) * pricePerUnit;
#endif
		if (credits >= creditsForRefuel)	// Ensure we don't overflow
		{
			credits -= creditsForRefuel;
			fuel = fuelCapacity();
			return YES;
		}
		else
		{
			return NO;
		}
	}
	
	// check energy unit replacement
	if (oo::str::hasSuffix(eqKey, "ENERGY_UNIT") && energyUnitType() != ENERGY_UNIT_NONE)
	{
		switch (energyUnitType())
		{
			case ENERGY_UNIT_NAVAL :
				removeEquipmentItem("EQ_NAVAL_ENERGY_UNIT");
				tradeIn = (UNIVERSE != nullptr ? UNIVERSE->getEquipmentPriceForKey("EQ_NAVAL_ENERGY_UNIT") : 0) / 2;	// 50 % refund
				break;
			case ENERGY_UNIT_NAVAL_DAMAGED :
				removeEquipmentItem("EQ_NAVAL_ENERGY_UNIT_DAMAGED");
				tradeIn = (UNIVERSE != nullptr ? UNIVERSE->getEquipmentPriceForKey("EQ_NAVAL_ENERGY_UNIT") : 0) / 4;	// half of the working one
				break;
			case ENERGY_UNIT_NORMAL :
				removeEquipmentItem("EQ_ENERGY_UNIT");
				tradeIn = (UNIVERSE != nullptr ? UNIVERSE->getEquipmentPriceForKey("EQ_ENERGY_UNIT") : 0) * 3 / 4;		// 75 % refund
				break;
			case ENERGY_UNIT_NORMAL_DAMAGED :
				removeEquipmentItem("EQ_ENERGY_UNIT_DAMAGED");
				tradeIn = (UNIVERSE != nullptr ? UNIVERSE->getEquipmentPriceForKey("EQ_ENERGY_UNIT") : 0) * 3 / 8;		// half of the working one
				break;

			default:
				break;
		}
		doTradeIn(tradeIn, priceFactor);
	}
	
	// maintain ship
	if ((eqKey == "EQ_RENOVATION"))
	{
		OOTechLevelID techLevel = NSNotFound;
		if (dockedStation != nil)  techLevel = (dockedStation != nullptr ? dockedStation->getEquivalentTechLevel() : 0);
		if (techLevel == NSNotFound)  techLevel = (UNIVERSE != nullptr ? UNIVERSE->currentSystemData() : oo::PList()).get<unsigned int>(std::string(KEY_TECHLEVEL));
		
		credits -= price;
		ship_trade_in_factor += 5 + techLevel;	// you get better value at high-tech repair bases
		if (ship_trade_in_factor > 100) ship_trade_in_factor = 100;
		
		clearSubEntities();
		setUpSubEntities();
		
		return YES;
	}
	
	if (oo::str::hasSuffix(eqKey, "MISSILE") || oo::str::hasSuffix(eqKey, "MINE"))
	{
		::ShipEntity* weapon = oo::ToShip(oo::AutoreleaseEntity((UNIVERSE != nullptr ? UNIVERSE->newShipWithRole(eqKey) : (::ShipEntity *)nil)));
		if (weapon)  OO_LOG("equip.buy.mounted", "Got ship for mounted weapon role {}", eqKey);
		else  OO_LOG("equip.buy.mounted.failed", "Could not find ship for mounted weapon role {}", eqKey);
		
		BOOL mounted_okay = mountMissile(weapon);
		if (mounted_okay)
		{
			credits -= price;
			safeAllMissiles();
			tidyMissilePylons();
			setActiveMissile(0);
		}
		return mounted_okay;
	}
	
	if ((eqKey == "EQ_PASSENGER_BERTH"))
	{
		changePassengerBerths(+1);
		credits -= price;
		return YES;
	}
	
	if ((eqKey == "EQ_PASSENGER_BERTH_REMOVAL"))
	{
		changePassengerBerths(-1);
		credits -= price;
		return YES;
	}
	
	if ((eqKey == "EQ_MISSILE_REMOVAL"))
	{
		credits -= price;
		tradeIn += removeMissiles();
		doTradeIn(tradeIn, priceFactor);
		return YES;
	}
	
	if (canAddEquipment(eqKey, "purchase"))
	{
		credits -= price;
		addEquipmentItem(eqKey, NO, "purchase"); // no need to validate twice.
		if (isRepair)
		{
			doScriptEvent(OOJSID("equipmentRepaired"), { oo::PList(eqKey) });
		}
		return YES;
	}
	
	return NO;
}


bool PlayerEntity::setWeaponMount(OOWeaponFacing facing, const std::string &eqKey)
{
	return setWeaponMount(facing, eqKey, std::string("purchase"));
}


bool PlayerEntity::setWeaponMount(OOWeaponFacing facing, const std::string &eqKey, const std::optional<std::string> &context)
{

	const oo::PList		shipyardInfo = OOShipRegistry::sharedRegistry()->shipyardInfoForKey(shipDataKey().value_or(""));
	unsigned			available_facings = shipyardInfo.get<unsigned int>(std::string(KEY_WEAPON_FACINGS), weaponFacings());	// use defaults  explicitly
	
	// facing exists?
	if (!(available_facings & facing)) 
	{
		return NO;
	}
	
	// weapon allowed (or NONE)?
	if (eqKey != "EQ_WEAPON_NONE")
	{
		if (!canAddEquipment(eqKey, context.value_or(std::string())))	// nil context read as "", as now  
		{
			return NO;
		}
	}
	
	// sets WEAPON_NONE if not recognised
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


bool PlayerEntity::changePassengerBerths(int addRemove)
{
	if (addRemove == 0) return NO;
	addRemove = (addRemove > 0) ? 1 : -1;	// change only by one berth at a time!
	// NSFO!
	//unsigned 	passenger_space = [[OOEquipmentType equipmentTypeWithIdentifier:@"EQ_PASSENGER_BERTH"] requiredCargoSpace];
	//if (passenger_space == 0) passenger_space = PASSENGER_BERTH_SPACE;
	if ((max_passengers < 1 && addRemove == -1) || (maxAvailableCargoSpace() - current_cargo < PASSENGER_BERTH_SPACE && addRemove == 1)) return NO;
	max_passengers += addRemove;
	max_cargo -= PASSENGER_BERTH_SPACE * addRemove;
	return YES;
}


OOCreditsQuantity PlayerEntity::removeMissiles()
{
	safeAllMissiles();
	OOCreditsQuantity tradeIn = 0;
	unsigned i;
	for (i = 0; i < missiles; i++)
	{
		const std::optional<std::string> weapon_key = (missile_list[i] != nullptr ? missile_list[i]->identifier() : std::optional<std::string>());

		if (weapon_key.has_value())
			tradeIn += (int)(UNIVERSE != nullptr ? UNIVERSE->getEquipmentPriceForKey(*weapon_key) : 0);
	}
	
	for (i = 0; i < max_missiles; i++)
	{
		missile_entity[i] = nullptr;
	}
	
	missiles = 0;
	return tradeIn;
}


void PlayerEntity::doTradeIn(OOCreditsQuantity tradeInValue, double priceFactor)
{
	if (tradeInValue != 0)
	{
		if (priceFactor < 1.0)  tradeInValue *= priceFactor;
		credits += tradeInValue;
	}
}



// Slice 23 of docs/phases/3-slices/PlayerEntity.md (bead oo-wt5jv): cargo quantities, the local market, market filters and sorters, market screen rows.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

OOCargoQuantity PlayerEntity::cargoQuantityForType(const std::string &type)
{
	OOCargoQuantity 	amount = (shipCommodityData != nullptr ? shipCommodityData->quantityForGood(type) : 0);

	if  (status() != STATUS_DOCKED)
	{
		NSInteger		i;
		::ShipEntity		*cargoItem = nil;
		
		for (i = cargo.size() - 1; i >= 0 ; i--)
		{
			cargoItem = oo::ToShip(cargo[i].get());
			if ((cargoItem != nullptr ? cargoItem->commodityType() : std::optional<std::string>()) == type)	// (a nil commodity type never matched)
			{
				amount += (cargoItem != nullptr ? cargoItem->commodityAmount() : 0);
			}
		}
	}
	
	return amount;
}


OOCargoQuantity PlayerEntity::setCargoQuantityForType(const std::string &type, OOCargoQuantity amount)
{
	OOMassUnit			unit = (shipCommodityData != nullptr ? shipCommodityData->massUnitForGood(type) : UNITS_TONS);
	if(getSpecialCargo().has_value() && unit == UNITS_TONS) return 0;	// don't do anything if we've got a special cargo...
	
	OOCargoQuantity		oldAmount = cargoQuantityForType(type);
	OOCargoQuantity		available = availableCargoSpace();
	BOOL				inPods = (status() != STATUS_DOCKED);
	
	// check it against the max amount.
	if (unit == UNITS_TONS && (available + oldAmount) < amount)
	{
		amount =  available + oldAmount;
	}
	// if we have 1499 kg the ship registers only 1 ton, so it's possible to exceed the max cargo:
	// eg: with maxAvailableCargoSpace 2 & gold 1499kg, you can still add 1 ton alloy. 
	else if (unit == UNITS_KILOGRAMS && amount > oldAmount)
	{
		// Allow up to 0.5 ton of kg (& g) goods above the cargo capacity but respect existing quantities.
		OOCargoQuantity		safeAmount = available * KILOGRAMS_PER_POD + MAX_KILOGRAMS_IN_SAFE;
		if (safeAmount < amount) amount = (safeAmount < oldAmount) ? oldAmount : safeAmount;
	}
	else if (unit == UNITS_GRAMS && amount > oldAmount)
	{
		OOCargoQuantity		safeAmount = available * GRAMS_PER_POD + MAX_GRAMS_IN_SAFE;
		if (safeAmount < amount) amount = (safeAmount < oldAmount) ? oldAmount : safeAmount;
	}
	
	if (inPods)
	{
		if (amount > oldAmount) // increase
		{
			loadCargoPodsForType(type, (amount - oldAmount));
		}
		else
		{
			unloadCargoPodsForType(type, (oldAmount - amount));
		}
	}
	else
	{
		if (shipCommodityData != nullptr)  shipCommodityData->setQuantity(amount, type);
	}

	calculateCurrentCargo();
	return (shipCommodityData != nullptr ? shipCommodityData->quantityForGood(type) : 0);
}


void PlayerEntity::calculateCurrentCargo()
{
	current_cargo = cargoQuantityOnBoard();
}


OOCargoQuantity PlayerEntity::cargoQuantityOnBoard()
{
	if (getSpecialCargo().has_value())
	{
		return maxAvailableCargoSpace();
	}	
	
	/*
		The cargo array is nil when the player ship is docked, due to action in unloadCargopods. For
		this reason, we must use a slightly more complex method to determine the quantity of cargo
		carried in this case - Nikos 20090830
		
		Optimised this method, to compensate for increased usage - Kaks 20091002
	*/
	OOCargoQuantity		cargoQtyOnBoard = 0;

	for (const std::string &good : (shipCommodityData != nullptr ? shipCommodityData->goods() : std::vector<std::string>()))
	{
		OOCargoQuantity quantity = (shipCommodityData != nullptr ? shipCommodityData->quantityForGood(good) : 0);

		OOMassUnit commodityUnits = (shipCommodityData != nullptr ? shipCommodityData->massUnitForGood(good) : UNITS_TONS);
		
		if (commodityUnits != UNITS_TONS)
		{
			// calculate the number of pods that would be used
			// we're using integer math, so 99/100 = 0 ,  100/100 = 1, etc...
			
			assert(KILOGRAMS_PER_POD > MAX_KILOGRAMS_IN_SAFE && GRAMS_PER_POD > MAX_GRAMS_IN_SAFE); // otherwise we're in trouble!
			
			if (commodityUnits == UNITS_KILOGRAMS)  quantity = ((KILOGRAMS_PER_POD - MAX_KILOGRAMS_IN_SAFE - 1) + quantity) / KILOGRAMS_PER_POD;
			else  quantity = ((GRAMS_PER_POD - MAX_GRAMS_IN_SAFE - 1) + quantity) / GRAMS_PER_POD;
		}
		cargoQtyOnBoard += quantity;
	}
	cargoQtyOnBoard += cargoCount();
	
	return cargoQtyOnBoard;
}


::OOCommodityMarket *PlayerEntity::localMarket()
{
	::StationEntity *station = dockedStation();
	if (station == nil)  
	{
		if ((primaryTarget() != nullptr && primaryTarget()->getIsStation()) && (oo::ToStation(primaryTarget()) != nullptr ? oo::ToStation(primaryTarget())->getMarketBroadcast() : false))
		{
			station = oo::ToStation(primaryTarget());
		}
		else
		{
			station = (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr);
		}
		if (station == nil)
		{
			// interstellar space or similar
			return nil;
		}
	}
	::OOCommodityMarket *localMarket = (station != nullptr ? station->getLocalMarket() : (OOCommodityMarket *)nullptr);
	if (localMarket == nil)
	{
		localMarket = (station != nullptr ? station->initialiseLocalMarket() : (OOCommodityMarket *)nullptr);
	}
	
	return localMarket;
}


std::vector<std::string> PlayerEntity::applyMarketFilter(const std::vector<std::string> &goods, ::OOCommodityMarket *market)
{
	if (marketFilterMode == MARKET_FILTER_MODE_OFF)
	{
		return goods;
	}
	std::vector<std::string>	filteredGoods;
	filteredGoods.reserve(goods.size());
	for (const std::string &good : goods)
	{
		switch (marketFilterMode)
		{
		case MARKET_FILTER_MODE_OFF:
			// never reached, but keeps compiler happy
			filteredGoods.push_back(good);
			break;
		case MARKET_FILTER_MODE_TRADE:
			if (market->quantityForGood(good) > 0 || cargoQuantityForType(good) > 0)
			{
				filteredGoods.push_back(good);
			}
			break;
		case MARKET_FILTER_MODE_HOLD:
			if (cargoQuantityForType(good) > 0)
			{
				filteredGoods.push_back(good);
			}
			break;
		case MARKET_FILTER_MODE_STOCK:
			if (market->quantityForGood(good) > 0)
			{
				filteredGoods.push_back(good);
			}
			break;
		case MARKET_FILTER_MODE_LEGAL:
			if (market->exportLegalityForGood(good) == 0 && market->importLegalityForGood(good) == 0)
			{
				filteredGoods.push_back(good);
			}
			break;
		case MARKET_FILTER_MODE_RESTRICTED:
			if (market->exportLegalityForGood(good) > 0 || market->importLegalityForGood(good) > 0)
			{
				filteredGoods.push_back(good);
			}
			break;
		}
	}
	return filteredGoods;
}


std::vector<std::string> PlayerEntity::applyMarketSorter(const std::vector<std::string> &goods, ::OOCommodityMarket *market)
{
	// -sortedArrayUsingFunction:context: was a stable sort (probed), so std::stable_sort gives the same order
	const auto sortedBy = [&goods](int (*sorter)(const std::string &, const std::string &, OOCommodityMarket *), ::OOCommodityMarket *sortMarket)
	{
		std::vector<std::string> sorted = goods;
		std::stable_sort(sorted.begin(), sorted.end(), [sorter, context = sortMarket](const std::string &a, const std::string &b) { return sorter(a, b, context) < 0; });
		return sorted;
	};
	switch (marketSorterMode)
	{
	case MARKET_SORTER_MODE_ALPHA:
		return sortedBy(marketSorterByName, market);
	case MARKET_SORTER_MODE_PRICE:
		return sortedBy(marketSorterByPrice, market);
	case MARKET_SORTER_MODE_STOCK:
		return sortedBy(marketSorterByQuantity, market);
	case MARKET_SORTER_MODE_HOLD:
		return sortedBy(marketSorterByQuantity, shipCommodityData.get());
	case MARKET_SORTER_MODE_UNIT:
		return sortedBy(marketSorterByMassUnit, market);
	case MARKET_SORTER_MODE_OFF:
		// keep default sort order
		break;
	}
	return goods;
}


void PlayerEntity::showMarketScreenHeaders()
{
	::GuiDisplayGen		*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	OOGUITabSettings tab_stops;
	tab_stops[0] = 0;
	tab_stops[1] = 137; 
	tab_stops[2] = 187;
	tab_stops[3] = 267;
	tab_stops[4] = 321;
	tab_stops[5] = 431;
	gui->overrideTabs(tab_stops, cxx_kGuiMarketTabs, 6);
	gui->setTabStops(tab_stops);
	
	gui->setColor(gui->colorFromSetting(cxx_kGuiMarketHeadingColor, OOColor::greenColor().get()).get(), GUI_ROW_MARKET_KEY);
	gui->setArray({ OO_DESC("commodity-column-title"), cxx_OOPadStringToEms(OO_DESC("price-column-title"),3.5), cxx_OOPadStringToEms(OO_DESC("for-sale-column-title"),3.75), cxx_OOPadStringToEms(OO_DESC("in-hold-column-title"),5.75), OO_DESC("oolite-legality-column-title"), OO_DESC("oolite-extras-column-title") }, GUI_ROW_MARKET_KEY);
	gui->setArray({ OO_DESC("commodity-column-title"), OO_DESC("oolite-extras-column-title"), cxx_OOPadStringToEms(OO_DESC("price-column-title"),3.5), cxx_OOPadStringToEms(OO_DESC("for-sale-column-title"),3.75), cxx_OOPadStringToEms(OO_DESC("in-hold-column-title"),5.75), OO_DESC("oolite-legality-column-title") }, GUI_ROW_MARKET_KEY);
}


void PlayerEntity::showMarketScreenDataLine(OOGUIRow row, const std::string &good, ::OOCommodityMarket *localMarket, OOCargoQuantity quantity)
{
	::GuiDisplayGen		*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	const std::string desc = oo::str::format(" %s ", (shipCommodityData != nullptr ? shipCommodityData->nameForGood(good) : std::optional<std::string>()).value_or("(null)").c_str());	// %@ of nil
	OOCargoQuantity available_units = (localMarket != nullptr ? localMarket->quantityForGood(good) : 0);
	OOCargoQuantity units_in_hold = quantity;
	OOCreditsQuantity pricePerUnit = (localMarket != nullptr ? localMarket->priceForGood(good) : 0);
	OOMassUnit unit = (shipCommodityData != nullptr ? shipCommodityData->massUnitForGood(good) : UNITS_TONS);

	const std::string available = cxx_OOPadStringToEms(((available_units > 0) ? oo::str::format("%d",available_units) : OO_DESC("commodity-quantity-none")), 2.5);

	NSUInteger priceDecimal = pricePerUnit % 10;
	const std::string price = oo::str::format(" %s.%zu ",cxx_OOPadStringToEms(oo::str::format("%zu",(pricePerUnit/10)),2.5).c_str(),priceDecimal);

	// this works with up to 9999 tons of gemstones. Any more than that, they deserve the formatting they get! :)

	const std::string owned = cxx_OOPadStringToEms((units_in_hold > 0) ? oo::str::format("%d",units_in_hold) : OO_DESC("commodity-quantity-none"), 4.5);
	const std::string units = cxx_DisplayStringForMassUnit(unit).value_or("(null)");
	const std::string units_available = oo::str::format(" %s %s ",available.c_str(), units.c_str());
	const std::string units_owned = oo::str::format(" %s %s ",owned.c_str(), units.c_str());

	NSUInteger import_legality = (localMarket != nullptr ? localMarket->importLegalityForGood(good) : 0);
	NSUInteger export_legality = (localMarket != nullptr ? localMarket->exportLegalityForGood(good) : 0);
	std::string legaldesc;
	if (import_legality == 0)
	{
		if (export_legality == 0)
		{
			legaldesc = OO_DESC("oolite-legality-clear");
		}
		else
		{
			legaldesc = OO_DESC("oolite-legality-import");
		}
	} 
	else
	{
		if (export_legality == 0)
		{
			legaldesc = OO_DESC("oolite-legality-export");
		}
		else
		{
			legaldesc = OO_DESC("oolite-legality-neither");
		}
	}
	legaldesc = oo::str::format(" %s ",legaldesc.c_str());

	const std::optional<std::string> extradesc = (shipCommodityData != nullptr ? shipCommodityData->shortCommentForGood(good) : std::optional<std::string>());

	gui->setKey(good, row);
	gui->setColor(gui->colorFromSetting(cxx_kGuiMarketCommodityColor, nil).get(), row);
	if (extradesc.has_value())  gui->setArray({ desc, *extradesc, price, units_available, units_owned, legaldesc }, row++);
	else  gui->setArray({ desc }, row++);	// a nil comment ended the -arrayWithObjects: list
}


std::optional<std::string> PlayerEntity::marketScreenTitle()
{
	::StationEntity *dockedStation = this->dockedStation();

	/* Override normal behaviour if station broadcasts market */
	if (dockedStation == nil)  
	{
		if ((primaryTarget() != nullptr && primaryTarget()->getIsStation()) && (oo::ToStation(primaryTarget()) != nullptr ? oo::ToStation(primaryTarget())->getMarketBroadcast() : false))
		{
			dockedStation = oo::ToStation(primaryTarget());
		}
	}

	std::string system;	// (used only when there is a sun)
	if ((UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr) != nil)  system = (UNIVERSE != nullptr ? UNIVERSE->getSystemName(system_id) : std::optional<std::string>()).value_or(std::string());
	
	if (dockedStation == nil || dockedStation == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr))
	{
		if ((UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr) != nil)
		{
			return ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "system-commodity-market", { { "system", oo::PList(system) } });
		}
		else
		{
			// Witchspace
			return cxx_OOExpandKey("commodity-market");
		}
	}
	else
	{
		const std::string station = (dockedStation != nullptr ? dockedStation->getDisplayName() : std::optional<std::string>()).value_or("");
		return ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "station-commodity-market", { { "station", oo::PList(station) } });
	}
}



// Slice 24 of docs/phases/3-slices/PlayerEntity.md (bead oo-bj7u8): the market screens, buying and selling commodities, mining and speech flags, adding equipment.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

void PlayerEntity::setGuiToMarketScreen()
{
	::OOCommodityMarket	*localMarket = this->localMarket();
	::GuiDisplayGen		*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	OOGUIScreenID		oldScreen = gui_screen;
	
	gui_screen = GUI_SCREEN_MARKET;
	BOOL			guiChanged = (oldScreen != gui_screen);

	
	if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setMouseInteractionModeForUIWithMouseInteraction(YES);
	
	// fix problems with economies in witchspace
	oo::Ref<OOCommodityMarket>	blankMarket;	// held for the screen, as the autoreleased market was
	if (localMarket == nil)
	{
		blankMarket = ((UNIVERSE != nullptr ? UNIVERSE->getCommodities() : nullptr) != nullptr ? UNIVERSE->getCommodities()->generateBlankMarket() : oo::Ref<OOCommodityMarket>());
		localMarket = blankMarket.get();
	}

	// following changed to work whether docked or not
	const std::vector<std::string> goods = applyMarketSorter(applyMarketFilter((localMarket != nullptr ? localMarket->goods() : std::vector<std::string>()), localMarket), localMarket);
	NSInteger maxOffset = 0;
	if (goods.size() > (GUI_ROW_MARKET_END-GUI_ROW_MARKET_START))
	{
		maxOffset = goods.size()-(GUI_ROW_MARKET_END-GUI_ROW_MARKET_START);
	}

	NSUInteger			commodityCount = (shipCommodityData != nullptr ? shipCommodityData->count() : 0);
	std::vector<OOCargoQuantity> quantityInHold(commodityCount);
		
	for (NSUInteger i = 0; i < commodityCount; i++)
	{
		quantityInHold[i] = (i < goods.size()) ? (shipCommodityData != nullptr ? shipCommodityData->quantityForGood(goods[i]) : 0) : 0;	// (a nil good had none)
	}
	for (NSUInteger i = 0; i < cargo.size(); i++)
	{
		::ShipEntity *container = oo::ToShip(cargo[i].get());
		NSUInteger goodsIndex = IndexOfGood(goods, (container != nullptr ? container->commodityType() : std::optional<std::string>()));
		// can happen with filters
		if (goodsIndex != NSNotFound)
		{
			quantityInHold[goodsIndex] += (container != nullptr ? container->commodityAmount() : 0);
		}
	}

	if (marketSelectedCommodity.has_value() && (marketSelectedCommodity == "<<<" || marketSelectedCommodity == ">>>"))
	{
		// nothing?
	}
	else
	{
		if (!marketSelectedCommodity.has_value() || IndexOfGood(goods, marketSelectedCommodity) == NSNotFound)
		{
			marketSelectedCommodity.reset();
			if (goods.size() > 0)
			{
				marketSelectedCommodity = goods[0];
			}
		}
		if (maxOffset > 0)
		{
			NSInteger goodsIndex = IndexOfGood(goods, marketSelectedCommodity);
			// validate marketOffset when returning from infoscreen
			if (goodsIndex <= marketOffset)
			{
				// is off top of list, move list upwards
				if (goodsIndex == 0) {
					marketOffset = 0;
				} else {
					marketOffset = goodsIndex-1;
				}
			}
			else if (goodsIndex > marketOffset+(GUI_ROW_MARKET_END-GUI_ROW_MARKET_START)-2)
			{
				// is off bottom of list, move list downwards
				marketOffset = 2+goodsIndex-(GUI_ROW_MARKET_END-GUI_ROW_MARKET_START);
				if (marketOffset > maxOffset)
				{
					marketOffset = maxOffset;
				}
			}
		}
	}

	// GUI stuff
	{
		OOGUIRow			start_row = GUI_ROW_MARKET_START;
		OOGUIRow			row = start_row;
		OOGUIRow			active_row = gui->getSelectedRow();

		gui->clearAndKeepBackground(!guiChanged);


		// The docked station (else a targeted station that broadcasts its market) was looked up
		// here and never read; the dead lookup went with the facade (bead oo-9ht.177).

gui->setTitle(marketScreenTitle());
		
		showMarketScreenHeaders();

		if (marketOffset > maxOffset)
		{
			marketOffset = 0;
		}
		else if (marketOffset < 0)
		{
			marketOffset = maxOffset;
		}

		if (goods.size() > 0)
		{
			const std::optional<std::string> selectedCommodity = marketSelectedCommodity;
			NSInteger i = 0;
			for (const std::string &good : goods)
			{
				if (i < marketOffset)
				{
					++i;
					continue;
				}
				showMarketScreenDataLine(row, good, localMarket, quantityInHold[i++]);
				if (good == selectedCommodity)
				{
					active_row = row;
				}

				++row;
				if (row >= GUI_ROW_MARKET_END)
				{
					break;
				}
			}

			if (marketOffset < maxOffset)
			{
				if (selectedCommodity == ">>>")
				{
					active_row = GUI_ROW_MARKET_LAST;
				}
				gui->setKey(">>>", GUI_ROW_MARKET_LAST);
				gui->setColor(gui->colorFromSetting(cxx_kGuiMarketScrollColor, OOColor::greenColor().get()).get(), GUI_ROW_MARKET_LAST);
				gui->setArray({ OO_DESC("gui-more"), "", "", "", " --> " }, GUI_ROW_MARKET_LAST);
			}
			if (marketOffset > 0)
			{
				if (selectedCommodity == "<<<")
				{
					active_row = GUI_ROW_MARKET_START;
				}
				gui->setKey("<<<", GUI_ROW_MARKET_START);
				gui->setColor(gui->colorFromSetting(cxx_kGuiMarketScrollColor, OOColor::greenColor().get()).get(), GUI_ROW_MARKET_START);
				gui->setArray({ OO_DESC("gui-back"), "", "", "", " <-- " }, GUI_ROW_MARKET_START);
			}
		}
		else
		{
			// filter is excluding everything
			gui->setColor(gui->colorFromSetting(cxx_kGuiMarketFilteredAllColor, OOColor::yellowColor().get()).get(), GUI_ROW_MARKET_START);
			gui->setText(OO_DESC("oolite-market-filtered-all"), GUI_ROW_MARKET_START);
			active_row = -1;
		}

		 // actually count the containers and  valuables (may be > max_cargo)
		current_cargo = cargoQuantityOnBoard();
		if (current_cargo > maxAvailableCargoSpace()) current_cargo = maxAvailableCargoSpace(); 

		// filter sort info
		{
			const std::string filterMode = cxx_OOExpandKey(cxx_OOExpand("oolite-market-filter-[marketFilterMode]", marketFilterMode).value_or(std::string())).value_or(std::string());
			const std::string filterText = ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "oolite-market-filter-line", { { "filterMode", oo::PList(filterMode) } });
			const std::string sortMode = cxx_OOExpandKey(cxx_OOExpand("oolite-market-sorter-[marketSorterMode]", marketSorterMode).value_or(std::string())).value_or(std::string());
			const std::string sorterText = ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "oolite-market-sorter-line", { { "sortMode", oo::PList(sortMode) } });
			gui->setArray({ filterText, "", sorterText }, GUI_ROW_MARKET_END);
		}
		gui->setColor(gui->colorFromSetting(cxx_kGuiMarketFilterInfoColor, OOColor::greenColor().get()).get(), GUI_ROW_MARKET_END);

		showMarketCashAndLoadLine();
		
		gui->setSelectableRange(NSMakeRange(start_row,row - start_row));
		gui->setSelectedRow(active_row);
		
		gui->setShowTextCursor(NO);
	}

	
	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->clearMouse();
	
	setShowDemoShips(NO);
	if (UNIVERSE != nullptr)  UNIVERSE->enterGUIViewModeWithMouseInteraction(YES);
	
	if (guiChanged)
	{
		gui->setForegroundTextureKey(std::optional<std::string>(status() == STATUS_DOCKED ? "docked_overlay" : "overlay"));
		gui->setBackgroundTextureKey("market");
		noteGUIDidChangeFrom(oldScreen, gui_screen);
	}
}


void PlayerEntity::setGuiToMarketInfoScreen()
{
	::OOCommodityMarket	*localMarket = this->localMarket();
	::GuiDisplayGen		*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	OOGUIScreenID		oldScreen = gui_screen;
	
	gui_screen = GUI_SCREEN_MARKETINFO;
	BOOL			guiChanged = (oldScreen != gui_screen);

	
	if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setMouseInteractionModeForUIWithMouseInteraction(YES);
	
	// fix problems with economies in witchspace
	oo::Ref<OOCommodityMarket>	blankMarket;	// held for the screen, as the autoreleased market was
	if (localMarket == nil)
	{
		blankMarket = ((UNIVERSE != nullptr ? UNIVERSE->getCommodities() : nullptr) != nullptr ? UNIVERSE->getCommodities()->generateBlankMarket() : oo::Ref<OOCommodityMarket>());
		localMarket = blankMarket.get();
	}

	// following changed to work whether docked or not
	const std::vector<std::string>	goods = applyMarketSorter(applyMarketFilter((localMarket != nullptr ? localMarket->goods() : std::vector<std::string>()), localMarket), localMarket);

	NSUInteger			i, j, commodityCount = (shipCommodityData != nullptr ? shipCommodityData->count() : 0);
	std::vector<OOCargoQuantity> quantityInHold(commodityCount);
		
	for (i = 0; i < commodityCount; i++)
	{
		quantityInHold[i] = (i < goods.size()) ? (shipCommodityData != nullptr ? shipCommodityData->quantityForGood(goods[i]) : 0) : 0;	// (a nil good had none)
	}
	for (i = 0; i < cargo.size(); i++)
	{
		::ShipEntity *container = oo::ToShip(cargo[i].get());
		j = IndexOfGood(goods, (container != nullptr ? container->commodityType() : std::optional<std::string>()));
		quantityInHold[j] += (container != nullptr ? container->commodityAmount() : 0);
	}


	// GUI stuff
	{
		if (EXPECT_NOT(!marketSelectedCommodity.has_value()))
		{
			j = NSNotFound;
		}
		else
		{
			j = IndexOfGood(goods, marketSelectedCommodity);
		}
		if (j == NSNotFound)
		{
			marketSelectedCommodity.reset();
			setGuiToMarketScreen();
			return;
		}

		gui->clearAndKeepBackground(!guiChanged);

		const std::string selectedCommodity = *marketSelectedCommodity;	// (non-nil here)
		const std::string informationFormat = OO_DESC("oolite-commodity-information-@");	// the format first, as Clang evaluates the arguments: a description that is an array draws (ADR-0063 item 5)
		gui->setTitle(oo::str::formatRuntime(informationFormat, { TextArg((shipCommodityData != nullptr ? shipCommodityData->nameForGood(selectedCommodity) : std::optional<std::string>())) }));

		showMarketScreenHeaders();
		showMarketScreenDataLine(GUI_ROW_MARKET_START, selectedCommodity, localMarket, quantityInHold[j]);

		OOCargoQuantity contracted = contractedVolumeForGood(selectedCommodity);
		if (contracted > 0)
		{
			OOMassUnit unit = (shipCommodityData != nullptr ? shipCommodityData->massUnitForGood(selectedCommodity) : UNITS_TONS);
			gui->setColor(gui->colorFromSetting(cxx_kGuiMarketContractedColor, nil).get(), GUI_ROW_MARKET_START+1);
			const std::string contractedFormat = OO_DESC("oolite-commodity-contracted-d-@");	// the format first, as Clang evaluates the arguments: a description that is an array draws (ADR-0063 item 5)
			gui->setText(oo::str::formatRuntime(contractedFormat, { contracted, cxx_DisplayStringForMassUnit(unit).value_or("(null)") }), GUI_ROW_MARKET_START+1);
		}

		const std::optional<std::string> info = (shipCommodityData != nullptr ? shipCommodityData->commentForGood(selectedCommodity) : std::optional<std::string>());
		OOGUIRow i = 0;
		if (!info.has_value() || info->empty())
		{
			i = gui->addLongText(OO_DESC("oolite-commodity-no-comment"), GUI_ROW_MARKET_START+2, GUI_ALIGN_LEFT);
		}
		else
		{
			i = gui->addLongText(info, GUI_ROW_MARKET_START+2, GUI_ALIGN_LEFT);
		}
		for (i-- ; i > GUI_ROW_MARKET_START+2 ; --i)
		{
			gui->setColor(gui->colorFromSetting(cxx_kGuiMarketDescriptionColor, nil).get(), i);
		}

		showMarketCashAndLoadLine();

	}

	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->clearMouse();
	
	setShowDemoShips(NO);
	if (UNIVERSE != nullptr)  UNIVERSE->enterGUIViewModeWithMouseInteraction(YES);
	
	if (guiChanged)
	{
		gui->setForegroundTextureKey(std::optional<std::string>(status() == STATUS_DOCKED ? "docked_overlay" : "overlay"));
		gui->setBackgroundTextureKey("marketinfo");
		noteGUIDidChangeFrom(oldScreen, gui_screen);
	}
}


void PlayerEntity::showMarketCashAndLoadLine()
{
	::GuiDisplayGen *gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	OOCargoQuantity currentCargo = current_cargo;
	OOCargoQuantity cargoCapacity = maxAvailableCargoSpace();
	gui->setText(cxx_OOExpandKey("market-cash-and-load", credits, currentCargo, cargoCapacity).value_or(std::string()), GUI_ROW_MARKET_CASH);
	gui->setColor(gui->colorFromSetting(cxx_kGuiMarketCashColor, OOColor::yellowColor().get()).get(), GUI_ROW_MARKET_CASH);
}


OOGUIScreenID PlayerEntity::guiScreen()
{
	return gui_screen;
}


bool PlayerEntity::tryBuyingCommodity(const std::string &index, bool all)
{
	if (index == "<<<" || index == ">>>")
	{
		++marketOffset;
		return NO;
	}

	if (!isDocked())  return NO; // can't buy if not docked.
	
	::OOCommodityMarket	*localMarket = this->localMarket();
	OOCreditsQuantity	pricePerUnit	= (localMarket != nullptr ? localMarket->priceForGood(index) : 0);
	OOMassUnit			unit			= (localMarket != nullptr ? localMarket->massUnitForGood(index) : UNITS_TONS);

	if (specialCargo.has_value() && unit == UNITS_TONS)
	{
		return NO;									// can't buy tons of stuff when carrying a specialCargo
	}
	int manifest_quantity = (shipCommodityData != nullptr ? shipCommodityData->quantityForGood(index) : 0);
	int market_quantity = (localMarket != nullptr ? localMarket->quantityForGood(index) : 0);
	
	int purchase = 1;
	if (all)
	{
		// if cargo contracts, put a break point on the contract volume
		int contracted = contractedVolumeForGood(index);
		if (manifest_quantity >= contracted)
		{
			purchase = (localMarket != nullptr ? localMarket->capacityForGood(index) : 0);
		}
		else
		{
			purchase = contracted-manifest_quantity;
		}
	}
	if (purchase > market_quantity)
	{
		purchase = market_quantity;					// limit to what's available
	}
	if (purchase * pricePerUnit > credits)
	{
		purchase = floor (credits / pricePerUnit);	// limit to what's affordable
	}
	// TODO - fix brokenness here...
	if (unit == UNITS_TONS && purchase + current_cargo > maxAvailableCargoSpace())
	{
		purchase = availableCargoSpace();		// limit to available cargo space
	}
	else
	{
		if (current_cargo == maxAvailableCargoSpace())
		{
			// other cases are fine so long as buying is limited to <1000kg / <1000000g
			// but if this case is true, we need to see if there is more space in
			// the manifest (safe) or an already-accounted-for pod
			if (unit == UNITS_KILOGRAMS)
			{
				if (manifest_quantity % KILOGRAMS_PER_POD <= MAX_KILOGRAMS_IN_SAFE && (manifest_quantity + purchase) % KILOGRAMS_PER_POD > MAX_KILOGRAMS_IN_SAFE)
				{
					// going from < n500 to >= n500 would increase pods needed by 1
					purchase = MAX_KILOGRAMS_IN_SAFE - manifest_quantity; // max possible
				}
			}
			else // UNITS_GRAMS
			{
				if (manifest_quantity % GRAMS_PER_POD <= MAX_GRAMS_IN_SAFE && (manifest_quantity + purchase) % GRAMS_PER_POD > MAX_GRAMS_IN_SAFE)
				{
					// going from < n500000 to >= n500000 would increase pods needed by 1
					purchase = MAX_GRAMS_IN_SAFE - manifest_quantity; // max possible
				}
			}
		}
	}
	if (purchase <= 0)
	{
		return NO;									// stop if that results in nothing to be bought
	}
	
	if (localMarket != nullptr)  localMarket->removeQuantity(purchase, index);
	if (shipCommodityData != nullptr)  shipCommodityData->addQuantity(purchase, index);
	credits -= pricePerUnit * purchase;

	calculateCurrentCargo();
	
	if ((UNIVERSE != nullptr ? UNIVERSE->getAutoSave() : false))  { if (UNIVERSE != nullptr)  UNIVERSE->setAutoSaveNow(YES); }
	
	doScriptEvent(OOJSID("playerBoughtCargo"), { oo::PList(index), oo::PList::signedInteger(purchase), oo::PList::unsignedInteger(pricePerUnit) });	// the same number kinds (signed, unsigned long long)
	if ((localMarket != nullptr ? localMarket->exportLegalityForGood(index) : 0) > 0)
	{
		roleWeightFlags.insert_or_assign("bought-illegal", oo::PList::signedInteger(1));	// +numberWithInt:
	}
	else
	{
		roleWeightFlags.insert_or_assign("bought-legal", oo::PList::signedInteger(1));	// +numberWithInt:
	}
	
	return YES;
}


bool PlayerEntity::trySellingCommodity(const std::string &index, bool all)
{
	if (index == "<<<" || index == ">>>")
	{
		--marketOffset;
		return NO;
	}

	if (!isDocked())  return NO; // can't sell if not docked.
	
	::OOCommodityMarket *localMarket = this->localMarket();
	int available_units = (shipCommodityData != nullptr ? shipCommodityData->quantityForGood(index) : 0);
	OOCreditsQuantity pricePerUnit = (localMarket != nullptr ? localMarket->priceForGood(index) : 0);
	
	if (available_units == 0)  return NO;

	int market_quantity = (localMarket != nullptr ? localMarket->quantityForGood(index) : 0);

	int capacity = (localMarket != nullptr ? localMarket->capacityForGood(index) : 0);
	int sell = 1;
	if (all)
	{
		// if cargo contracts, put a break point on the contract volume
		int contracted = contractedVolumeForGood(index);
		if (available_units <= contracted)
		{
			sell = capacity;
		}
		else
		{
			sell = available_units-contracted;
		}
	}

	if (sell > available_units)
		sell = available_units;					// limit to what's in the hold
	if (sell + market_quantity > capacity)
		sell = capacity - market_quantity;			// avoid flooding the market
	if (sell <= 0)
		return NO;								// stop if that results in nothing to be sold
	
	if (localMarket != nullptr)  localMarket->addQuantity(sell, index);
	if (shipCommodityData != nullptr)  shipCommodityData->removeQuantity(sell, index);
	credits += pricePerUnit * sell;

	calculateCurrentCargo();
	
	if ((UNIVERSE != nullptr ? UNIVERSE->getAutoSave() : false)) { if (UNIVERSE != nullptr)  UNIVERSE->setAutoSaveNow(YES); }
	
	doScriptEvent(OOJSID("playerSoldCargo"), { oo::PList(index), oo::PList::signedInteger(sell), oo::PList::unsignedInteger(pricePerUnit) });	// the same number kinds (signed, unsigned long long)
	
	return YES;
}


bool PlayerEntity::isMining()
{
	return using_mining_laser;
}


OOSpeechSettings PlayerEntity::getIsSpeechOn()
{
	return isSpeechOn;
}


bool PlayerEntity::canAddEquipment(const std::string &equipmentKey, const std::string &context)
{
	if (equipmentKey == "EQ_RENOVATION" && !(ship_trade_in_factor < 85 || shipSubEntities().size() < maxShipSubEntities()))  return NO;
	if (!ShipEntity::canAddEquipment(equipmentKey, context))  return NO;

	::OOEquipmentType *eqType = OOEquipmentType::equipmentTypeWithIdentifier(equipmentKey).get();
	const oo::PList conditions = (eqType != nil) ? (eqType != nullptr ? eqType->conditions() : oo::PList()) : oo::PList();
	if (!conditions.isNull() && !scriptTestConditions(conditions))  return NO;
	
	return YES;
}


bool PlayerEntity::addEquipmentItem(const std::string &equipmentKey, const std::string &context)
{
	return addEquipmentItem(equipmentKey, YES, context);
}



// Slice 25 of docs/phases/3-slices/PlayerEntity.md (bead oo-hu1xk): adding / removing / custom-activated equipment, pylons, parcels and passengers, comms, fines, trade-in factor, renovation, view offsets, trumbles.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

bool PlayerEntity::addEquipmentItem(const std::string &equipmentKey, bool validateAddition, const std::string &context)
{
	// deal with trumbles..
	if (equipmentKey == "EQ_TRUMBLE")
	{
		/*	Bug fix: must return here if eqKey == @"EQ_TRUMBLE", even if
			trumbleCount >= 1. Otherwise, the player becomes immune to
			trumbles. See comment in -setCommanderDataFromDictionary: for more
			details.
		 -- Ahruman 2008-12-04
		 */
		// the old trumbles will kill the new one if there are enough of them.
		if ((trumbleCount < PLAYER_MAX_TRUMBLES / 6) || (trumbleCount < PLAYER_MAX_TRUMBLES / 3 && ranrot_rand() % 2 > 0))
		{
			addTrumble(trumble[ranrot_rand() % PLAYER_MAX_TRUMBLES].get());	// randomise its looks.
			return YES;
		}
		return NO;
	}
	
	BOOL OK = ShipEntity::addEquipmentItem(equipmentKey, validateAddition, context);
	
	if (OK)
	{
		if (hasEquipmentItemProviding("EQ_ADVANCED_COMPASS") && getCompassMode() == COMPASS_MODE_BASIC)
		{
			setCompassMode(COMPASS_MODE_PLANET);
		}
		
		if (!equipmentKey.empty())  addEqScriptForKey(equipmentKey);	// ("" stands for the former nil key)
		addEquipmentWithScriptToCustomKeyArray(equipmentKey);
	}
	return OK;
}


std::vector<oo::PList> *PlayerEntity::customEquipmentActivation()
{
	return &customEquipActivation;	// the live entries (ADR-0043 item 22)
}


void PlayerEntity::addEquipmentWithScriptToCustomKeyArray(const std::string &equipmentKey)
{
	NSUInteger i, j;
	oo::PList object;

	for (i = 0; i < eqScripts.size(); i++) 
	{
		if (eqScripts[i].first == equipmentKey) 
		{
			//check if this equipment item is already in the array
			for (j = 0; j < customEquipActivation.size(); j++) {
				if (StringForKey(customEquipActivation[j], std::string(CUSTOMEQUIP_EQUIPKEY)) == equipmentKey) return;
			}
			// if we get here, this item is new
			// add the basic info at this point (equipkey and name only; a nil name ended the list)
			::OOEquipmentType *eq = OOEquipmentType::equipmentTypeWithIdentifier(equipmentKey).get();
			oo::PList::Dict customKey;
			customKey[std::string(CUSTOMEQUIP_EQUIPKEY)] = equipmentKey;
			const std::optional<std::string> equipmentName = (eq != nullptr ? eq->name() : std::optional<std::string>());
			if (equipmentName.has_value())  customKey[std::string(CUSTOMEQUIP_EQUIPNAME)] = *equipmentName;

			// grab any default keys from the equipment item
			// default activate
			object = (eq != nullptr ? eq->defaultActivateKey() : oo::PList());
			if ((object.isArray() && object.count() > 0))
				customKey[std::string(CUSTOMEQUIP_KEYACTIVATE)] = object;
			// default mode
			object = (eq != nullptr ? eq->defaultModeKey() : oo::PList());
			if ((object.isArray() && object.count() > 0))
				customKey[std::string(CUSTOMEQUIP_KEYMODE)] = object;

			customEquipActivation.push_back(oo::PList(std::move(customKey)));
			// keep the keypress arrays in sync
			customActivatePressed.push_back(NO);
			customModePressed.push_back(NO);			

			oo::Defaults::standard().setObject(std::string(KEYCONFIG_CUSTOMEQUIP), oo::PList(customEquipActivation));
			return;
		}
	}
}


void PlayerEntity::validateCustomEquipActivationArray()
{
	int i;
	bool update = NO;
	std::optional<std::string> equipmentKey;
	if (customEquipActivation.size() == 0) return;
	for (i = customEquipActivation.size() - 1; i >= 0; i--) {
		equipmentKey = StringForKey(customEquipActivation[i], std::string(CUSTOMEQUIP_EQUIPKEY));
		::OOEquipmentType *eq = (equipmentKey.has_value() ? OOEquipmentType::equipmentTypeWithIdentifier(*equipmentKey).get() : nil);
		if (!eq) {
			customEquipActivation.erase(customEquipActivation.begin() + i);
			customActivatePressed.erase(customActivatePressed.begin() + i);
			customModePressed.erase(customModePressed.begin() + i);
			update = YES;
		}
	}
	if (update) {
		oo::Defaults::standard().setObject(std::string(KEYCONFIG_CUSTOMEQUIP), oo::PList(customEquipActivation));
	}
}


void PlayerEntity::removeEquipmentItem(const std::string &equipmentKey)
{
	if(!hasEquipmentItemProviding("EQ_ADVANCED_COMPASS") && getCompassMode() != COMPASS_MODE_BASIC)
	{
		setCompassMode(COMPASS_MODE_BASIC);
	}
	ShipEntity::removeEquipmentItem(equipmentKey);
	if(!hasOneEquipmentItem(equipmentKey, NO, NO)) {	// -hasEquipmentItem: with one string key
		// removed the last one
		if (!equipmentKey.empty())  removeEqScriptForKey(equipmentKey);	// ("" stands for the former nil key)
	}
}


void PlayerEntity::addEquipmentFromCollection(const oo::PList &equipment)
{
	oo::PList	dict;	// null unless the collection is a dictionary
	std::vector<std::string>	eqKeys;	// the keys / elements in the collection's enumeration order
	NSUInteger	i, count;

	// Pass 1: Load the entire collection.
	if (const oo::PList::Dict *equipmentDict = equipment.getIf<oo::PList::Dict>())
	{
		dict = equipment;
		for (const auto &[eqKey, value] : *equipmentDict)  eqKeys.push_back(eqKey);	// key byte order (was NSDictionary order)
	}
	else if (const oo::PList::Array *equipmentArray = equipment.getIf<oo::PList::Array>())
	{
		for (const oo::PList &element : *equipmentArray)
		{
			if (const std::string *eqKey = element.getIf<std::string>())  eqKeys.push_back(*eqKey);	// strings only, as before
		}
	}
	else if (const std::string *eqKey = equipment.getIf<std::string>())
	{
		eqKeys = { *eqKey };
	}
	else
	{
		return;
	}

	for (const std::string &eqDesc : eqKeys)
	{
		/*	Bug workaround: extra_equipment should never contain EQ_TRUMBLE,
			which is basically a magic flag passed to awardEquipment: to infect
			the player. However, prior to Oolite 1.70.1, if the player had a
			trumble infection and awardEquipment:EQ_TRUMBLE was called, an
			EQ_TRUMBLE would be added to the equipment list. Subsequent calls
			to awardEquipment:EQ_TRUMBLE would exit early because there was an
			EQ_TRUMBLE in the equipment list. as a result, it would no longer
			be possible to infect the player after the current infection ended.
			
			The bug is fixed in 1.70.1. The following line is to fix old saved
			games which had been "corrupted" by the bug.
			-- Ahruman 2007-12-04
		 */
		if (eqDesc == "EQ_TRUMBLE")  continue;
		
		// Traditional form is a dictionary of booleans; we only accept those where the value is true.
		if (!dict.isNull() && !dict.get<bool>(eqDesc))  continue;
		
		// We need to add the entire collection without validation first and then remove the items that are
		// not compliant (like items that do not satisfy the requiresEquipment criterion). This is to avoid
		// unintentionally excluding valid equipment, just because the required equipment existed but had
		// not been yet added to the equipment list at the time of the canAddEquipment validation check.
		// Nikos, 20080817.
		count = dict.get<NSUInteger>(eqDesc);	// (0 for a list: nothing is added from one here, as before)
		for (i=0;i<count;i++)
		{
			addEquipmentItem(eqDesc, NO, "loading");
		}
	}
	
	// Pass 2: Remove items that do not satisfy validation criteria (like requires_equipment etc.).
	// (the same collection, walked again in the same order)
	// Now remove items that should not be in the equipment list.
	for (const std::string &eqDesc : eqKeys)
	{
		if (!equipmentValidToAdd(eqDesc, YES, "loading"))
		{
			removeEquipmentItem(eqDesc);
		}
	}
}


bool PlayerEntity::hasOneEquipmentItem(const std::string &itemKey, bool includeMissiles)
{
	// Check basic equipment the normal way.
	if (ShipEntity::hasOneEquipmentItemIncludingMissiles(itemKey, false, false))  return YES;
	
	// Custom handling for player missiles.
	if (includeMissiles)
	{
		unsigned i;
		for (i = 0; i < max_missiles; i++)
		{
			if ((missileForPylon(i) != nullptr ? missileForPylon(i)->hasPrimaryRole(itemKey) : false))  return YES;
		}
	}
	
	if (itemKey == "EQ_TRUMBLE")
	{
		return getTrumbleCount() > 0;
	}
	
	return NO;
}


bool PlayerEntity::hasPrimaryWeapon(OOWeaponType weaponType)
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
	
	return ShipEntity::hasPrimaryWeapon(weaponType);
}


bool PlayerEntity::removeExternalStore(::OOEquipmentType *eqType)
{
	// Look for matching missile.
	unsigned i;
	for (i = 0; i < max_missiles; i++)
	{
		const std::optional<std::string> identifier = (eqType != nullptr ? eqType->identifier() : std::optional<std::string>());
		if (identifier.has_value() ? (missileForPylon(i) != nullptr ? missileForPylon(i)->hasPrimaryRole(*identifier) : false) : ((void)(missileForPylon(i) != nullptr ? missileForPylon(i)->getPrimaryRole() : std::optional<std::string>()), NO))	// nil: NO, after still choosing a primary role, as -hasPrimaryRole: did
		{
			removeFromPylon(i);
			
			// Just remove one at a time.
			return YES;
		}
	}
	return NO;
}


bool PlayerEntity::removeFromPylon(NSUInteger pylon)
{
	if (pylon >= max_missiles) return NO;
	
	if (missile_entity[pylon])
	{
		const std::optional<std::string> missileRole = (oo::ToShip(missile_entity[pylon].get()) != nullptr ? oo::ToShip(missile_entity[pylon].get())->getPrimaryRole() : std::optional<std::string>());
		ShipEntity::removeExternalStore(missileRole.has_value() ? OOEquipmentType::equipmentTypeWithIdentifier(*missileRole).get() : nil);

		// Remove the missile (must wait until we've finished with its identifier string!)
		missile_entity[pylon] = nullptr;
		
		tidyMissilePylons();
		
		// This should be the currently selected missile, deselect it.
		if (pylon <= activeMissile)
		{
			if (activeMissile == missiles && missiles > 0) activeMissile--;
			if (activeMissile > 0) activeMissile--;
			else activeMissile = max_missiles - 1;
			
			selectNextMissile();
		}
		
		return YES;
	}

	return NO;
}


NSUInteger PlayerEntity::parcelCount()
{
	return parcels.size();
}


NSUInteger PlayerEntity::passengerCount()
{
	return passengers.size();
}


NSUInteger PlayerEntity::passengerCapacity()
{
	return max_passengers;
}


bool PlayerEntity::hasHostileTarget()
{
	::ShipEntity *playersTarget = oo::ToShip(primaryTarget());
	return ((playersTarget != nullptr ? playersTarget->getIsShip() : false) && (playersTarget != nullptr ? playersTarget->hasHostileTarget() : false) && (playersTarget != nullptr ? playersTarget->primaryTarget() : (Entity *)nullptr) == this);
}


void PlayerEntity::receiveCommsMessage(const std::string &message_text, ::ShipEntity *other)
{
	if (status() == STATUS_DEAD || status() == STATUS_DOCKED)
	{
		// only when in flight
		return;
	}
	if (UNIVERSE != nullptr)  UNIVERSE->addCommsMessage(oo::str::format("%s:\n %s", (other != nullptr ? other->getDisplayName() : std::optional<std::string>()).value_or("(null)").c_str(), message_text.c_str()), 4.5);
	ShipEntity::receiveCommsMessage(message_text, other);
}


void PlayerEntity::getFined()
{
	if (legalStatusValue == 0)  return;				// nothing to pay for
	
	OOGovernmentID local_gov = (UNIVERSE != nullptr ? UNIVERSE->currentSystemData() : oo::PList()).get<int>(std::string(KEY_GOVERNMENT));
	if ((UNIVERSE != nullptr ? UNIVERSE->inInterstellarSpace() : false))  local_gov = 1;	// equivalent to Feudal. I'm assuming any station in interstellar space is military. -- Ahruman 2008-05-29
	OOCreditsQuantity fine = 500 + ((local_gov < 2 || local_gov > 5) ? 500 : 0);
	fine *= legalStatusValue;
	if (fine > credits)
	{
		int payback = (int)(legalStatusValue * credits / fine);
		setBounty((legalStatusValue-payback), kOOLegalStatusReasonPaidFine);
		credits = 0;
	}
	else
	{
		setBounty(0, kOOLegalStatusReasonPaidFine);
		credits -= fine;
	}
	
	// one of the fined-@-credits strings includes expansion tokens
	const std::string fined_message = oo::str::formatRuntime(cxx_OOExpandKey("fined-@-credits").value_or(std::string()), { cxx_OOCredits(fine) });
	addMessageToReport(fined_message);
	if (UNIVERSE != nullptr)  UNIVERSE->forceWitchspaceEntries();
	ship_clock_adjust += 24 * 3600;	// take up a day
}


void PlayerEntity::adjustTradeInFactorBy(int value)
{
	ship_trade_in_factor += value;
	if (ship_trade_in_factor < 75)  ship_trade_in_factor = 75;
	if (ship_trade_in_factor > 100)  ship_trade_in_factor = 100;
}


int PlayerEntity::tradeInFactor()
{
	return ship_trade_in_factor;
}


double PlayerEntity::renovationCosts()
{
	// 5% of value of ships wear + correction for missing subentities.
	OOCreditsQuantity shipValue = (UNIVERSE != nullptr ? UNIVERSE->tradeInValueForCommanderDictionary(commanderDataDictionary()) : 0);

	double costs = 0.005 * (100 - ship_trade_in_factor) * shipValue;
	costs += 0.01 * shipValue * missingSubEntitiesAdjustment();
	costs *= renovationFactor();
	return cunningFee(costs, 0.05);
}


double PlayerEntity::renovationFactor()
{
	::OOShipRegistry		*registry = OOShipRegistry::sharedRegistry();
	const oo::PList		shipyardInfo = registry->shipyardInfoForKey(shipDataKey().value_or(""));
	return shipyardInfo.get<double>(std::string(KEY_RENOVATION_MULTIPLIER), 1.0);
}


void PlayerEntity::setDefaultViewOffsets()
{
	float halfLength = 0.5f * (boundingBox.max.z - boundingBox.min.z);
	float halfWidth = 0.5f * (boundingBox.max.x - boundingBox.min.x);

	forwardViewOffset = make_vector(0.0f, 0.0f, boundingBox.max.z - halfLength);
	aftViewOffset = make_vector(0.0f, 0.0f, boundingBox.min.z + halfLength);
	portViewOffset = make_vector(boundingBox.min.x + halfWidth, 0.0f, 0.0f);
	starboardViewOffset = make_vector(boundingBox.max.x - halfWidth, 0.0f, 0.0f);
	customViewOffset = kZeroVector;
}


void PlayerEntity::setDefaultCustomViews()
{
	const oo::PList shipInfo = OOShipRegistry::sharedRegistry()->shipInfoForKey(std::string(PLAYER_SHIP_DESC));
	const oo::PList *customViews = shipInfo.find("custom_views");

	_customViews.clear();
	_customViewIndex = 0;
	if (customViews != nullptr)
	{
		_customViews = CustomViewsFrom(*customViews);
	}
}


Vector PlayerEntity::weaponViewOffset()
{
	switch (currentWeaponFacing)
	{
		case WEAPON_FACING_FORWARD:
			return forwardViewOffset;
		case WEAPON_FACING_AFT:
			return aftViewOffset;
		case WEAPON_FACING_PORT:
			return portViewOffset;
		case WEAPON_FACING_STARBOARD:
			return starboardViewOffset;
			
		case WEAPON_FACING_NONE:
			// N.b.: this case should never happen.
			return customViewOffset;
	}
	return kZeroVector;
}


void PlayerEntity::setUpTrumbles()
{
	std::u16string trumbleDigrams;	// UTF-16 units, as the old mutable string held them
	uint16_t	xchar = (uint16_t)0;
	uint16_t digramchars[2];

	while (trumbleDigrams.size() < PLAYER_MAX_TRUMBLES + 2)
	{
		const std::optional<std::string> commanderName = this->commanderName();
		if (commanderName.has_value() && !commanderName->empty())
		{
			trumbleDigrams += oo::utf8ToUtf16(*commanderName + (mesh() != nullptr ? mesh()->modelName() : std::nullopt).value_or("(null)"));	// "%@%@"
		}
		else
		{
			trumbleDigrams += u"Some Random Text!";
		}
	}
	int i;
	for (i = 0; i < PLAYER_MAX_TRUMBLES; i++)
	{
		digramchars[0] = (trumbleDigrams[i] & 0x007f) | 0x0020;
		digramchars[1] = ((trumbleDigrams[i + 1] ^ xchar) & 0x007f) | 0x0020;
		xchar = digramchars[0];
		const std::string digramstring = { static_cast<char>(digramchars[0]), static_cast<char>(digramchars[1]) };	// both ASCII
		trumble[i] = oo::makeRef<OOTrumble>(this, digramstring);
	}
	
	trumbleCount = 0;
	
	setTrumbleAppetiteAccumulator(0.0f);
}


void PlayerEntity::addTrumble(OOTrumble *papaTrumble)
{
	if (trumbleCount >= PLAYER_MAX_TRUMBLES)
	{
		return;
	}
	trumble[trumbleCount]->spawnFrom(papaTrumble);
	trumbleCount++;
}


void PlayerEntity::removeTrumble(OOTrumble *deadTrumble)
{
	if (trumbleCount <= 0)
	{
		return;
	}
	NSUInteger	trumble_index = NSNotFound;
	NSUInteger	i;
	
	for (i = 0; (trumble_index == NSNotFound)&&(i < trumbleCount); i++)
	{
		if (trumble[i] == deadTrumble)
			trumble_index = i;
	}
	if (trumble_index == NSNotFound)
	{
		OO_LOG("trumble.zombie", "DEBUG can't get rid of inactive trumble {}", static_cast<const void *>(deadTrumble));
		return;
	}
	trumbleCount--;	// reduce number of trumbles
	std::swap(trumble[trumble_index], trumble[trumbleCount]);	// swap with the current last trumble
}


oo::Ref<OOTrumble> *PlayerEntity::trumbleArray()
{
	return trumble;
}


NSUInteger PlayerEntity::getTrumbleCount()
{
	return trumbleCount;
}



// Slice 26 of docs/phases/3-slices/PlayerEntity.md (bead oo-cpam5): trumble values, checksums, screen modes, target memory, missile ident, rotating and panning the custom view.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

oo::PList PlayerEntity::trumbleValue()
{
	const std::string	namekey = oo::str::format("%s-humbletrash", commanderName().value_or("(null)").c_str());
	int			trumbleHash;
	
	clear_checksum();
	mungChecksumWithString(commanderName());
	munge_checksum(credits);
	munge_checksum(ship_kills);
	trumbleHash = munge_checksum(trumbleCount);
	
	oo::Defaults::standard().setInteger(namekey, trumbleHash);
	
	int i;
	oo::PList::Array trumbleArray;
	trumbleArray.reserve(PLAYER_MAX_TRUMBLES);
	for (i = 0; i < PLAYER_MAX_TRUMBLES; i++)
	{
		trumbleArray.push_back(trumble[i]->dictionary());
	}

	// [count (unsigned), hash (signed), trumbles]: the same number kinds as before
	return oo::PList(oo::PList::Array{ oo::PList::unsignedInteger(trumbleCount), oo::PList::signedInteger(trumbleHash), oo::PList(std::move(trumbleArray)) });
}


void PlayerEntity::setTrumbleValueFrom(const oo::PList &trumbleValue)
{
	BOOL info_failed = NO;
	int trumbleHash;
	int putativeHash = 0;
	int putativeNTrumbles = 0;
	oo::PList putativeTrumbleArray;	// null unless an array
	int i;
	const std::string namekey = oo::str::format("%s-humbletrash", commanderName().value_or("(null)").c_str());
	
	setUpTrumbles();
	
	if (!trumbleValue.isNull())
	{
		BOOL possible_cheat = NO;
		if (!trumbleValue.isArray())
			info_failed = YES;
		else
		{
			const oo::PList &values = trumbleValue;
			if (values.count() >= 1)
				putativeNTrumbles = values.at<int>(0);
			if (values.count() >= 2)
				putativeHash = values.at<int>(1);
			if (values.count() >= 3 && values.at(2)->isArray())
				putativeTrumbleArray = *values.at(2);
		}
		// calculate a hash for the putative values
		clear_checksum();
		mungChecksumWithString(commanderName());
		munge_checksum(credits);
		munge_checksum(ship_kills);
		trumbleHash = munge_checksum(putativeNTrumbles);
		
		if (putativeHash != trumbleHash)
			info_failed = YES;
		
		if (info_failed)
		{
			OO_LOG("cheat.tentative", "{}", "POSSIBLE CHEAT DETECTED");
			possible_cheat = YES;
		}
		
		for (i = 1; (info_failed)&&(i < PLAYER_MAX_TRUMBLES); i++)
		{
			// try to determine trumbleCount from the key in the saved game
			clear_checksum();
			mungChecksumWithString(commanderName());
			munge_checksum(credits);
			munge_checksum(ship_kills);
			trumbleHash = munge_checksum(i);
			if (putativeHash == trumbleHash)
			{
				info_failed = NO;
				putativeNTrumbles = i;
			}
		}
		
		if (possible_cheat && !info_failed)
			OO_LOG("cheat.verified", "{}", "CHEAT DEFEATED - that's not the way to get rid of trumbles!");
	}
	else
	// if trumbleValue comes in as nil, then probably someone has toyed with the save file
	// by removing the entire trumbles array
	{
		OO_LOG("cheat.tentative", "{}", "POSSIBLE CHEAT DETECTED");
		info_failed = YES;
	}
	
	if (info_failed && !oo::Defaults::standard().object(namekey).isNull())
	{
		// try to determine trumbleCount from the key in user defaults
		putativeHash = (int)oo::Defaults::standard().integerForKey(namekey);
		for (i = 1; (info_failed)&&(i < PLAYER_MAX_TRUMBLES); i++)
		{
			clear_checksum();
			mungChecksumWithString(commanderName());
			munge_checksum(credits);
			munge_checksum(ship_kills);
			trumbleHash = munge_checksum(i);
			if (putativeHash == trumbleHash)
			{
				info_failed = NO;
				putativeNTrumbles = i;
			}
		}
		
		if (!info_failed)
			OO_LOG("cheat.verified", "{}", "CHEAT DEFEATED - that's not the way to get rid of trumbles!");
	}
	// at this stage we've done the best we can to stop cheaters
	trumbleCount = putativeNTrumbles;

	if ((!putativeTrumbleArray.isNull()) && (putativeTrumbleArray.count() == PLAYER_MAX_TRUMBLES))
	{
		for (i = 0; i < PLAYER_MAX_TRUMBLES; i++)
			trumble[i]->setFromDictionary(putativeTrumbleArray.at(i)->isDict() ? *putativeTrumbleArray.at(i) : oo::PList());	// null PList unless a dictionary
	}
	
	clear_checksum();
	mungChecksumWithString(commanderName());
	munge_checksum(credits);
	munge_checksum(ship_kills);
	trumbleHash = munge_checksum(trumbleCount);
	
	oo::Defaults::standard().setInteger(namekey, trumbleHash);
}


float PlayerEntity::trumbleAppetiteAccumulator()
{
	return _trumbleAppetiteAccumulator;
}


void PlayerEntity::setTrumbleAppetiteAccumulator(float value)
{
	_trumbleAppetiteAccumulator = value;
}


void PlayerEntity::mungChecksumWithString(const std::optional<std::string> &str)
{
	if (!str.has_value())  return;

	for (char16_t unit : oo::utf8ToUtf16(*str))	// the UTF-16 units, as -characterAtIndex: gave them
	{
		munge_checksum(unit);
	}
}


std::optional<std::string> PlayerEntity::screenModeStringForWidth(unsigned width, unsigned height, float refreshRate)
{
	if (0.0f != refreshRate)
	{
		return cxx_OOExpandKey("gameoptions-fullscreen-with-refresh-rate", width, height, refreshRate);
	}
	else
	{
		return cxx_OOExpandKey("gameoptions-fullscreen", width, height);
	}
}


void PlayerEntity::getSuppressTargetLost()
{
	suppressTargetLostFlag = YES;
}


void PlayerEntity::setScoopsActive()
{
	scoopsActive = YES;
}


// override shipentity to stop foundTarget being changed during escape sequence
void PlayerEntity::setFoundTarget(Entity *targetEntity)
{
	/* Rare, but can happen, e.g. if a Q-mine goes off nearby during
	 * the sequence */
	if (status() == STATUS_ESCAPE_SEQUENCE)
	{
		return;
	}
	_foundTarget = oo::WeakRef<Entity>(targetEntity);
}


// override shipentity addTarget to implement target_memory
void PlayerEntity::addTarget(Entity *targetEntity)	// the C++ entity since bead oo-9ht.39.23
{
	if (status() != STATUS_IN_FLIGHT && status() != STATUS_WITCHSPACE_COUNTDOWN)  return;
	if (targetEntity == this)  return;
	
	ShipEntity::addTarget(targetEntity);
	
	if (targetEntity != nullptr && targetEntity->getIsWormhole())
	{
		assert (hasEquipmentItemProviding("EQ_WORMHOLE_SCANNER"));
		addScannedWormhole(static_cast<WormholeEntity *>(targetEntity));
	}
	// wormholes don't go in target memory
	else if (hasEquipmentItemProviding("EQ_TARGET_MEMORY") && targetEntity != nullptr)
	{
		const oo::WeakRef<Entity> targetRef = oo::WeakRef<Entity>(targetEntity);	// was [targetEntity weakSelf] (bead oo-9ht.39.5.2)
		// -indexOfObject: compared the weak references (proxies) by identity; WeakRef's == compares the same identity
		const auto slotFor = [this](const oo::WeakRef<Entity> &ref) -> NSUInteger
		{
			const auto found = std::find_if(target_memory.begin(), target_memory.end(), [&ref](const oo::WeakRef<Entity> &slot) { return slot == ref; });
			return (found != target_memory.end()) ? static_cast<NSUInteger>(found - target_memory.begin()) : NSNotFound;
		};
		NSUInteger i = slotFor(targetRef);
		// if already in target memory, preserve that and just change the index
		if (i != NSNotFound)
		{
			target_memory_index = i;
		}		
		else
		{
			i = slotFor(oo::WeakRef<Entity>());	// an empty slot
			// find and use a blank space in memory
			if (i != NSNotFound)
			{
				target_memory.at(i) = targetRef;
				target_memory_index = i;
			}
			else
			{
				// use the next memory space
				target_memory_index = (target_memory_index + 1) % PLAYER_TARGET_MEMORY_SIZE;
				target_memory.at(target_memory_index) = targetRef;
			}
		}
	}
	
	if (ident_engaged)
	{
		playIdentLockedOn();
		printIdentLockedOnForMissile(NO);
	}
	else if (oo::EntityIsShip(targetEntity) && weaponsOnline()) // Only let missiles target-lock onto ships
	{
		if ((oo::ToShip(missile_entity[activeMissile].get()) != nullptr ? oo::ToShip(missile_entity[activeMissile].get())->getIsMissile() : false))
		{
			missile_status = MISSILE_STATUS_TARGET_LOCKED;
			if (oo::ToShip(missile_entity[activeMissile].get()) != nullptr)  oo::ToShip(missile_entity[activeMissile].get())->addTarget(targetEntity);
			playMissileLockedOn();
			printIdentLockedOnForMissile(YES);
		}
		else // It's a mine or something
		{
			missile_status = MISSILE_STATUS_ARMED;
			playIdentLockedOn();
			printIdentLockedOnForMissile(NO);
		}
	}
}


void PlayerEntity::clearTargetMemory()
{
	NSUInteger memoryCount = target_memory.size();
	for (NSUInteger i = 0; i < PLAYER_TARGET_MEMORY_SIZE; i++)
	{
		if (i < memoryCount)
		{
			target_memory[i] = nullptr;
		}
		else
		{
			target_memory.emplace_back();
		}
	}
	target_memory_index = 0;
}


std::vector<oo::WeakRef<Entity>> PlayerEntity::targetMemory()
{
	return target_memory;
}


bool PlayerEntity::moveTargetMemoryBy(NSInteger delta)
{
	unsigned i = 0;
	while (i++ < PLAYER_TARGET_MEMORY_SIZE)	// limit loops
	{
		NSInteger idx = (NSInteger)target_memory_index + delta;
		while (idx < 0)  idx += PLAYER_TARGET_MEMORY_SIZE;
		while (idx >= PLAYER_TARGET_MEMORY_SIZE) idx -= PLAYER_TARGET_MEMORY_SIZE;
		target_memory_index = idx;

		const oo::WeakRef<Entity> &targ_ref = target_memory.at(target_memory_index);
		if (targ_ref != oo::WeakRef<Entity>())	// a weak reference (-isProxy), not an empty slot
		{
			::ShipEntity *potential_target = oo::ToShip(targ_ref.get());
		
			if ((potential_target)&&(potential_target->isShip)&&((potential_target != nullptr ? potential_target->isInSpace() : false)))
			{
				if (potential_target->zero_distance < SCANNER_MAX_RANGE2 && (!(potential_target != nullptr ? potential_target->isCloaked() : false)))
				{
					ShipEntity::addTarget(potential_target);
					if (missile_status != MISSILE_STATUS_SAFE)
					{
						if( (oo::ToShip(missile_entity[activeMissile].get()) != nullptr ? oo::ToShip(missile_entity[activeMissile].get())->getIsMissile() : false))
						{
							if (oo::ToShip(missile_entity[activeMissile].get()) != nullptr)  oo::ToShip(missile_entity[activeMissile].get())->addTarget(potential_target);
							missile_status = MISSILE_STATUS_TARGET_LOCKED;
							printIdentLockedOnForMissile(YES);
						}
						else
						{
							missile_status = MISSILE_STATUS_ARMED;
							playIdentLockedOn();
							printIdentLockedOnForMissile(NO);
						}
					}
					else
					{
						ident_engaged = YES;
						printIdentLockedOnForMissile(NO);
					}
					playTargetSwitched();
					return YES;
				}
			}
			else
			{
				target_memory.at(target_memory_index) = nullptr;
			}
		}
	}
	
	playNoTargetInMemory();
	return NO;
}


void PlayerEntity::printIdentLockedOnForMissile(bool missile)
{
	if (primaryTarget() == nil) return;
	
	const std::string fmt = missile ? "missile-locked-onto-target" : "ident-locked-onto-target";
	const std::string target = (oo::ToShip(primaryTarget()) != nullptr ? oo::ToShip(primaryTarget())->identFromShip(this) : std::optional<std::string>()).value_or("");	// (disengaged raised in the expansion; was nil)
	if (UNIVERSE != nullptr)  UNIVERSE->addMessage(ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), fmt, { { "target", oo::PList(target) } }), 4.5);
}


Quaternion PlayerEntity::getCustomViewQuaternion()
{
	return customViewQuaternion;
}


void PlayerEntity::setCustomViewQuaternion(Quaternion q)
{
	customViewQuaternion = q;
	setCustomViewData();
}


OOMatrix PlayerEntity::getCustomViewMatrix()
{
	return customViewMatrix;
}


Vector PlayerEntity::getCustomViewOffset()
{
	return customViewOffset;
}


void PlayerEntity::setCustomViewOffset(Vector offset)
{
	customViewOffset = offset;
}


Vector PlayerEntity::getCustomViewRotationCenter()
{
	return customViewRotationCenter;
}


void PlayerEntity::setCustomViewRotationCenter(Vector center)
{
	customViewRotationCenter = center;
}


void PlayerEntity::customViewZoomIn(OOScalar rate)
{
	customViewOffset = vector_subtract(customViewOffset, customViewRotationCenter);
	customViewOffset = vector_multiply_scalar(customViewOffset, 1.0/rate);
	OOScalar m = magnitude(customViewOffset);
	if (m < CUSTOM_VIEW_MAX_ZOOM_IN * collision_radius)
	{
		scale_vector(&customViewOffset, CUSTOM_VIEW_MAX_ZOOM_IN * collision_radius / m);
	}
	customViewOffset = vector_add(customViewOffset, customViewRotationCenter);
}


void PlayerEntity::customViewZoomOut(OOScalar rate)
{
	customViewOffset = vector_subtract(customViewOffset, customViewRotationCenter);
	customViewOffset = vector_multiply_scalar(customViewOffset, rate);
	OOScalar m = magnitude(customViewOffset);
	if (m > CUSTOM_VIEW_MAX_ZOOM_OUT * collision_radius)
	{
		scale_vector(&customViewOffset, CUSTOM_VIEW_MAX_ZOOM_OUT * collision_radius / m);
	}
	customViewOffset = vector_add(customViewOffset, customViewRotationCenter);
}


void PlayerEntity::customViewRotateLeft(OOScalar angle)
{
	customViewOffset = vector_subtract(customViewOffset, customViewRotationCenter);
	OOScalar m = magnitude(customViewOffset);
	quaternion_rotate_about_axis(&customViewQuaternion, customViewUpVector, -angle);
	setCustomViewData();
	customViewOffset = vector_flip(customViewForwardVector);
	scale_vector(&customViewOffset, m / magnitude(customViewOffset));
	customViewOffset = vector_add(customViewOffset, customViewRotationCenter);
}


void PlayerEntity::customViewRotateRight(OOScalar angle)
{
	customViewOffset = vector_subtract(customViewOffset, customViewRotationCenter);
	OOScalar m = magnitude(customViewOffset);
	quaternion_rotate_about_axis(&customViewQuaternion, customViewUpVector, angle);
	setCustomViewData();
	customViewOffset = vector_flip(customViewForwardVector);
	scale_vector(&customViewOffset, m / magnitude(customViewOffset));
	customViewOffset = vector_add(customViewOffset, customViewRotationCenter);
}


void PlayerEntity::customViewRotateUp(OOScalar angle)
{
	customViewOffset = vector_subtract(customViewOffset, customViewRotationCenter);
	OOScalar m = magnitude(customViewOffset);
	quaternion_rotate_about_axis(&customViewQuaternion, customViewRightVector, -angle);
	setCustomViewData();
	customViewOffset = vector_flip(customViewForwardVector);
	scale_vector(&customViewOffset, m / magnitude(customViewOffset));
	customViewOffset = vector_add(customViewOffset, customViewRotationCenter);
}


void PlayerEntity::customViewRotateDown(OOScalar angle)
{
	customViewOffset = vector_subtract(customViewOffset, customViewRotationCenter);
	OOScalar m = magnitude(customViewOffset);
	quaternion_rotate_about_axis(&customViewQuaternion, customViewRightVector, angle);
	setCustomViewData();
	customViewOffset = vector_flip(customViewForwardVector);
	scale_vector(&customViewOffset, m / magnitude(customViewOffset));
	customViewOffset = vector_add(customViewOffset, customViewRotationCenter);
}


void PlayerEntity::customViewRollRight(OOScalar angle)
{
	customViewOffset = vector_subtract(customViewOffset, customViewRotationCenter);
	OOScalar m = magnitude(customViewOffset);
	quaternion_rotate_about_axis(&customViewQuaternion, customViewForwardVector, -angle);
	setCustomViewData();
	customViewOffset = vector_flip(customViewForwardVector);
	scale_vector(&customViewOffset, m / magnitude(customViewOffset));
	customViewOffset = vector_add(customViewOffset, customViewRotationCenter);
}


void PlayerEntity::customViewRollLeft(OOScalar angle)
{
	customViewOffset = vector_subtract(customViewOffset, customViewRotationCenter);
	OOScalar m = magnitude(customViewOffset);
	quaternion_rotate_about_axis(&customViewQuaternion, customViewForwardVector, angle);
	setCustomViewData();
	customViewOffset = vector_flip(customViewForwardVector);
	scale_vector(&customViewOffset, m / magnitude(customViewOffset));
	customViewOffset = vector_add(customViewOffset, customViewRotationCenter);
}


void PlayerEntity::customViewPanUp(OOScalar angle)
{
	quaternion_rotate_about_axis(&customViewQuaternion, customViewRightVector, angle);
	setCustomViewData();
	customViewRotationCenter = vector_subtract(customViewOffset, vector_multiply_scalar(customViewForwardVector, dot_product(customViewOffset, customViewForwardVector)));
}


void PlayerEntity::customViewPanDown(OOScalar angle)
{
	quaternion_rotate_about_axis(&customViewQuaternion, customViewRightVector, -angle);
	setCustomViewData();
	customViewRotationCenter = vector_subtract(customViewOffset, vector_multiply_scalar(customViewForwardVector, dot_product(customViewOffset, customViewForwardVector)));
}



// Slice 27 of docs/phases/3-slices/PlayerEntity.md (bead oo-u1e9m): custom view vectors and data, the mission overlay and background, world scripts and script events, galactic hyperspace, jump cause, commander and save names.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

void PlayerEntity::customViewPanLeft(OOScalar angle)
{
	quaternion_rotate_about_axis(&customViewQuaternion, customViewUpVector, angle);
	setCustomViewData();
	customViewRotationCenter = vector_subtract(customViewOffset, vector_multiply_scalar(customViewForwardVector, dot_product(customViewOffset, customViewForwardVector)));
}


void PlayerEntity::customViewPanRight(OOScalar angle)
{
	quaternion_rotate_about_axis(&customViewQuaternion, customViewUpVector, -angle);
	setCustomViewData();
	customViewRotationCenter = vector_subtract(customViewOffset, vector_multiply_scalar(customViewForwardVector, dot_product(customViewOffset, customViewForwardVector)));
}


Vector PlayerEntity::getCustomViewForwardVector()
{
	return customViewForwardVector;
}


Vector PlayerEntity::getCustomViewUpVector()
{
	return customViewUpVector;
}


Vector PlayerEntity::getCustomViewRightVector()
{
	return customViewRightVector;
}


std::optional<std::string> PlayerEntity::getCustomViewDescription()
{
	return customViewDescription;
}


void PlayerEntity::resetCustomView()
{
	const oo::PList customView = (_customViewIndex < _customViews.size()) ? _customViews[_customViewIndex] : oo::PList();
	setCustomViewDataFromDictionary((customView.isDict() ? customView : oo::PList()), NO);	// null unless a Dict, as oo_dictionaryAtIndex:
}


void PlayerEntity::setCustomViewData()
{
	customViewRightVector = vector_right_from_quaternion(customViewQuaternion);
	customViewUpVector = vector_up_from_quaternion(customViewQuaternion);
	customViewForwardVector = vector_forward_from_quaternion(customViewQuaternion);
	
	Quaternion q1 = customViewQuaternion;
	q1.w = -q1.w;
	customViewMatrix = OOMatrixForQuaternionRotation(q1);
}


void PlayerEntity::setCustomViewDataFromDictionary(const oo::PList &viewDict, bool withScaling)
{
	customViewMatrix = kIdentityMatrix;
	customViewOffset = kZeroVector;
	if (viewDict.isNull())  return;

	customViewQuaternion = QuaternionForKey(viewDict, "view_orientation");
	setCustomViewData();
	
	// easier to do the multiplication at this point than at load time
	if (withScaling)
	{
		customViewOffset = vector_multiply_scalar(VectorForKey(viewDict, "view_position"),_scaleFactor);
	}
	else
	{
		// but don't do this when the custom view is set through JS
		customViewOffset = VectorForKey(viewDict, "view_position");
	}
	customViewRotationCenter = vector_subtract(customViewOffset, vector_multiply_scalar(customViewForwardVector, dot_product(customViewOffset, customViewForwardVector)));
	customViewDescription = StringForKey(viewDict, "view_description");

	const std::optional<std::string> facing = StringForKey(viewDict, "weapon_facing");	// nil compares unequal
	const std::string lowerFacing = facing.has_value() ? oo::str::lowercase(*facing) : std::string();
	if (facing.has_value() && lowerFacing == "aft")
	{
		currentWeaponFacing = WEAPON_FACING_AFT;
	}
	else if (facing.has_value() && lowerFacing == "port")
	{
		currentWeaponFacing = WEAPON_FACING_PORT;
	}
	else if (facing.has_value() && lowerFacing == "starboard")
	{
		currentWeaponFacing = WEAPON_FACING_STARBOARD;
	}
	else if (facing.has_value() && lowerFacing == "forward")
	{
		currentWeaponFacing = WEAPON_FACING_FORWARD;
	}
	// if the weapon facing is unset / unknown, 
	// don't change current weapon facing!
}


bool PlayerEntity::showInfoFlag()
{
	return show_info_flag;
}


oo::PList PlayerEntity::missionOverlayDescriptor()
{
	return _missionOverlayDescriptor;
}


oo::PList PlayerEntity::missionOverlayDescriptorOrDefault()
{
	oo::PList result = missionOverlayDescriptor();
	if (result.isNull())
	{
		if (missionTitle().value_or("").empty())
		{
			result = (UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey("mission_overlay_no_title") : oo::PList());
		}
		else
		{
			result = (UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey("mission_overlay_with_title") : oo::PList());
		}
	}

	return result;
}


void PlayerEntity::setMissionOverlayDescriptor(const oo::PList &descriptor)
{
	_missionOverlayDescriptor = descriptor;
}


oo::PList PlayerEntity::missionBackgroundDescriptor()
{
	return _missionBackgroundDescriptor;
}


oo::PList PlayerEntity::missionBackgroundDescriptorOrDefault()
{
	oo::PList result = missionBackgroundDescriptor();
	if (result.isNull())
	{
		result = (UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey("mission") : oo::PList());
	}

	return result;
}


void PlayerEntity::setMissionBackgroundDescriptor(const oo::PList &descriptor)
{
	_missionBackgroundDescriptor = descriptor;
}


OOGUIBackgroundSpecial PlayerEntity::missionBackgroundSpecial()
{
	return _missionBackgroundSpecial;
}


void PlayerEntity::setMissionBackgroundSpecial(const std::string &special)
{
	if (special.empty()) {	// (nil, from the bridge)
		_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_NONE;
	}
	else if (special == "SHORT_RANGE_CHART")
	{
		_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_SHORT;
	}
	else if (special == "SHORT_RANGE_CHART_SHORTEST")
	{
		if (hasEquipmentItemProviding("EQ_ADVANCED_NAVIGATIONAL_ARRAY"))
		{
			_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_SHORT_ANA_SHORTEST;
		}
		else
		{
			_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_SHORT;
		}
	}
	else if (special == "SHORT_RANGE_CHART_QUICKEST")
	{
		if (hasEquipmentItemProviding("EQ_ADVANCED_NAVIGATIONAL_ARRAY"))
		{
			_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_SHORT_ANA_QUICKEST;
		}
		else
		{
			_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_SHORT;
		}
	} 
	else if (special == "CUSTOM_CHART")
	{
		_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_CUSTOM;
	}
	else if (special == "CUSTOM_CHART_SHORTEST")
	{
		if (hasEquipmentItemProviding("EQ_ADVANCED_NAVIGATIONAL_ARRAY"))
		{
			_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_SHORTEST;
		}
		else
		{
			_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_CUSTOM;
		}
	}
	else if (special == "CUSTOM_CHART_QUICKEST")
	{
		if (hasEquipmentItemProviding("EQ_ADVANCED_NAVIGATIONAL_ARRAY"))
		{
			_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_QUICKEST;
		}
		else
		{
			_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_CUSTOM;
		}
	} 
	else if (special == "LONG_RANGE_CHART")
	{
		_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_LONG;
	}
	else if (special == "LONG_RANGE_CHART_SHORTEST")
	{
		if (hasEquipmentItemProviding("EQ_ADVANCED_NAVIGATIONAL_ARRAY"))
		{
			_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_LONG_ANA_SHORTEST;
		}
		else
		{
			_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_LONG;
		}
	}
	else if (special == "LONG_RANGE_CHART_QUICKEST")
	{
		if (hasEquipmentItemProviding("EQ_ADVANCED_NAVIGATIONAL_ARRAY"))
		{
			_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_LONG_ANA_QUICKEST;
		}
		else
		{
			_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_LONG;
		}
	} 
	else 
	{
		_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_NONE;
	}
}


void PlayerEntity::setMissionExitScreen(OOGUIScreenID screen)
{
	_missionExitScreen = screen;
}


OOGUIScreenID PlayerEntity::missionExitScreen()
{
	return _missionExitScreen;
}


oo::PList PlayerEntity::equipScreenBackgroundDescriptor()
{
	return _equipScreenBackgroundDescriptor;
}


void PlayerEntity::setEquipScreenBackgroundDescriptor(const oo::PList &descriptor)
{
	_equipScreenBackgroundDescriptor = descriptor;
}


bool PlayerEntity::scriptsLoaded()
{
	return !worldScripts.empty();
}


std::vector<std::string> PlayerEntity::worldScriptNames()
{
	std::vector<std::string> names;
	names.reserve(worldScripts.size());
	for (const auto &entry : worldScripts)  names.push_back(entry.first);
	return names;
}


std::vector<std::pair<std::string, oo::Ref<OOScript>>> PlayerEntity::worldScriptsByName()
{
	return worldScripts;
}


::OOScript *PlayerEntity::commodityScriptNamed(const std::optional<std::string> &scriptName)
{
	if (!scriptName.has_value())
	{
		return nil;
	}
	::OOScript *cscript = nullptr;
	const auto found = commodityScripts.find(*scriptName);
	if (found != commodityScripts.end())
	{
		cscript = found->second.get();
	}
	if (cscript != nullptr)
	{
		return cscript;
	}
	const oo::Ref<OOScript> loaded = OOScript::jsScriptFromFileNamed(*scriptName, oo::PList());
	cscript = loaded.get();
	if (cscript != nullptr)
	{
		// storing it in here retains it
		commodityScripts[*scriptName] = loaded;
	}
	else
	{
		OO_LOG("script.commodityScript.load", "Could not load script {}", *scriptName);
	}
	return cscript;
}


void PlayerEntity::doScriptEvent(ooscript::PropertyId message, ooscript::Context context, ooscript::Value *argv, unsigned argc)
{
	ShipEntity::doScriptEvent(message, context, argv, argc);
	doWorldScriptEvent(message, context, argv, argc, 0.0);
}


// ORDER-SENSITIVE (decision D): the world scripts run in load order (was the dictionary's order).
bool PlayerEntity::doWorldEventUntilMissionScreen(ooscript::PropertyId message)
{
	const std::vector<std::pair<std::string, oo::Ref<OOScript>>> scripts = worldScripts;	// a snapshot, as the enumerator kept the dictionary
	auto			scriptEntry = scripts.begin();

	// Check for the presence of report messages first.
	if (gui_screen != GUI_SCREEN_MISSION && !dockingReport.empty() && isDocked() && !(dockedStation() != nullptr ? dockedStation()->suppressArrivalReports() : false))
	{
		setGuiToDockingReportScreen();	// go here instead!
		UNIVERSE->messageGUI()->clear();
		return YES;
	}
	
	ooscript::Context context = OOJSAcquireContext();
	while (scriptEntry != scripts.end() && gui_screen != GUI_SCREEN_MISSION && isDocked())
	{
		if (scriptEntry->second.get() != nullptr)  scriptEntry->second.get()->callMethod(message, context, NULL, 0, NULL);
		++scriptEntry;
	}
	OOJSRelinquishContext(context);
	
	if (gui_screen == GUI_SCREEN_MISSION)
	{
		// remove any comms/console messages from the screen!
		UNIVERSE->messageGUI()->clear();
		return YES;
	}
	
	return NO;
}


void PlayerEntity::doWorldScriptEvent(ooscript::PropertyId message, ooscript::Context context, ooscript::Value *argv, unsigned argc, OOTimeDelta limit)
{
	OOCParameterAssert(context != NULL && ooscript::isInRequest(context));
	
	// ORDER-SENSITIVE (decision D): load order (was -allValues order); a snapshot, as -allValues was.
	const std::vector<std::pair<std::string, oo::Ref<OOScript>>> scripts = worldScripts;
	for (const auto &entry : scripts)
	{
		OOJSStartTimeLimiterWithTimeLimit(limit);
		if (entry.second.get() != nullptr)  entry.second.get()->callMethod(message, context, argv, argc, NULL);
		OOJSStopTimeLimiter();
	}
}


void PlayerEntity::setGalacticHyperspaceBehaviour(OOGalacticHyperspaceBehaviour inBehaviour)
{
	if (GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN < inBehaviour && inBehaviour <= GALACTIC_HYPERSPACE_MAX)
	{
		galacticHyperspaceBehaviour = inBehaviour;
	}
}


OOGalacticHyperspaceBehaviour PlayerEntity::getGalacticHyperspaceBehaviour()
{
	return galacticHyperspaceBehaviour;
}


void PlayerEntity::setGalacticHyperspaceFixedCoords(NSPoint point)
{
	return setGalacticHyperspaceFixedCoordsX(OOClamp_0_max_f(round(point.x), 255.0f), OOClamp_0_max_f(round(point.y), 255.0f));
}


void PlayerEntity::setGalacticHyperspaceFixedCoordsX(unsigned char x, unsigned char y)
{
	galacticHyperspaceFixedCoords.x = x;
	galacticHyperspaceFixedCoords.y = y;
}


NSPoint PlayerEntity::getGalacticHyperspaceFixedCoords()
{
	return galacticHyperspaceFixedCoords;
}


void PlayerEntity::setWitchspaceCountdown(int spin_time)
{
	witchspaceCountdown = spin_time;
}


OOLongRangeChartMode PlayerEntity::getLongRangeChartMode()
{
	return longRangeChartMode;
}


void PlayerEntity::setLongRangeChartMode(OOLongRangeChartMode mode)
{
	longRangeChartMode = mode;
}


bool PlayerEntity::getScoopOverride()
{
	return scoopOverride;
}


void PlayerEntity::setScoopOverride(bool newValue)
{
	scoopOverride = !!newValue;
	if (scoopOverride)  setScoopsActive();
}


GLfloat PlayerEntity::fuelChargeRate()
{
#if MASS_DEPENDENT_FUEL_PRICES
	GLfloat		rate = 1.0; // Standard charge rate.
	
	rate = ShipEntity::fuelChargeRate();
	
	// Experimental: the state of repair affects the fuel charge rate - more fuel needed for jumps, etc... 
	if (EXPECT(ship_trade_in_factor <= 90 && ship_trade_in_factor >= 75))
	{
		const int tradeInHundreds = ship_trade_in_factor / 100;	// integer division kept: upstream behaviour
		rate *= 2.0 - tradeInHundreds; // between 1.1x and 1.25x
		//fuelPrices: shipDataKey repair status ship_trade_in_factor rate (retired log)
	}

	return rate;
#else
	return ShipEntity::fuelChargeRate();	// the method was compiled out: the ship's answered
#endif
}


void PlayerEntity::setDockTarget(::ShipEntity *entity)
{
if ((entity != nullptr ? entity->getIsStation() : false)) _dockTarget = (entity != nullptr ? entity->getUniversalID() : OOUniversalID{});
else _dockTarget = NO_TARGET;
	//_dockTarget = [entity isStation] ? [entity universalID]: NO_TARGET;
}


std::optional<std::string> PlayerEntity::jumpCause()
{
	return _jumpCause;
}


void PlayerEntity::setJumpCause(const std::optional<std::string> &value)
{
	OOCParameterAssert(value.has_value());
	_jumpCause = value;
}


std::optional<std::string> PlayerEntity::commanderName()
{
	return _commanderName;
}


std::optional<std::string> PlayerEntity::lastsaveName()
{
	return _lastsaveName;
}


void PlayerEntity::setCommanderName(const std::optional<std::string> &value)
{
	OOCParameterAssert(value.has_value());
	_commanderName = value;
}


void PlayerEntity::setLastsaveName(const std::optional<std::string> &value)
{
	OOCParameterAssert(value.has_value());
	_lastsaveName = value;
}



// Slice 28 of docs/phases/3-slices/PlayerEntity.md (bead oo-zn1vy): docking clearance, scanned wormholes, mission destinations, the shipyard record, extra mission and GUI-screen keys, the state dump.
// (Its facade forwarded each selector until bead oo-9ht.177 deleted it; sends to self are member calls.)

bool PlayerEntity::isDocked()
{
	BOOL isDockedStatus = NO;
	
	switch (status())
	{
		case STATUS_DOCKED:
		case STATUS_DOCKING:
        case STATUS_START_GAME:
            isDockedStatus = YES;
            break;   
			// special case - can be either docked or not, so avoid safety check below
		case STATUS_RESTART_GAME:
			return NO;
		case STATUS_EFFECT:
		case STATUS_ACTIVE:
		case STATUS_COCKPIT_DISPLAY:
		case STATUS_TEST:
		case STATUS_INACTIVE:
		case STATUS_DEAD:
		case STATUS_IN_FLIGHT:
		case STATUS_AUTOPILOT_ENGAGED:
		case STATUS_LAUNCHING:
		case STATUS_WITCHSPACE_COUNTDOWN:
		case STATUS_ENTERING_WITCHSPACE:
		case STATUS_EXITING_WITCHSPACE:
		case STATUS_ESCAPE_SEQUENCE:
		case STATUS_IN_HOLD:
		case STATUS_BEING_SCOOPED:
		case STATUS_HANDLING_ERROR:
            break;
		//no default, so that we get notified by the compiler if something is missing
	}
	
#ifndef NDEBUG
	// Sanity check
	if (isDockedStatus)
	{
		if (dockedStation() == nil)
		{
			//there are a number of possible current statuses, not just STATUS_DOCKED
			OO_LOG_ERR(cxx_kOOLogInconsistentState, "status is {}, but dockedStation is nil; treating as not docked. {}", cxx_OOStringFromEntityStatus(status()), "This is an internal error, please report it.");
			setStatus(STATUS_IN_FLIGHT);
			isDockedStatus = NO;
		}
	}
	else
	{
		if (dockedStation() != nil && status() != STATUS_LAUNCHING)
		{
			OO_LOG_ERR(cxx_kOOLogInconsistentState, "status is {}, but dockedStation is not nil; treating as docked. {}", cxx_OOStringFromEntityStatus(status()), "This is an internal error, please report it.");
			setStatus(STATUS_DOCKED);
			isDockedStatus = YES;
		}
	}
#endif
	
	return isDockedStatus;
}


bool PlayerEntity::clearedToDock()
{
	return dockingClearanceStatus > DOCKING_CLEARANCE_STATUS_REQUESTED || dockingClearanceStatus == DOCKING_CLEARANCE_STATUS_NOT_REQUIRED;
}


void PlayerEntity::setDockingClearanceStatus(OODockingClearanceStatus newValue)
{
	dockingClearanceStatus = newValue;
	if (dockingClearanceStatus == DOCKING_CLEARANCE_STATUS_NONE)
	{
		targetDockStation = nil;
	}
	else if (dockingClearanceStatus == DOCKING_CLEARANCE_STATUS_REQUESTED || dockingClearanceStatus == DOCKING_CLEARANCE_STATUS_NOT_REQUIRED)
	{
		if ((primaryTarget() != nullptr && primaryTarget()->getIsStation()))
		{
			targetDockStation = oo::ToStation(primaryTarget());
		}
		else
		{
			OO_LOG("player.badDockingTarget", "Attempt to dock at {}.", oo::EntityDescription(primaryTarget()));
			targetDockStation = nil;
			dockingClearanceStatus = DOCKING_CLEARANCE_STATUS_NONE;
		}
	}
}


OODockingClearanceStatus PlayerEntity::getDockingClearanceStatus()
{
	return dockingClearanceStatus;
}


void PlayerEntity::penaltyForUnauthorizedDocking()
{
	OOCreditsQuantity	amountToPay = 0;
	OOCreditsQuantity	calculatedFine = credits * 0.05;
	OOCreditsQuantity	maximumFine = 50000ULL;
	
	if (clearedToDock())
		return;
		
	amountToPay = MIN(maximumFine, calculatedFine);
	credits -= amountToPay;
	addMessageToReport(oo::str::formatRuntime(OO_DESC("station-docking-clearance-fined-@-cr"), { cxx_OOCredits(amountToPay) }));
}


//
// Wormhole Scanner support functions
//
void PlayerEntity::addScannedWormhole(::WormholeEntity *whole)
{
	assert(whole != nil);

	// Only add if we don't have it already!
	for (const oo::EntityHold &wh : scannedWormholes)
	{
		if (wh.get() == whole)  return;
	}
	if (whole != nullptr)  whole->setScannedAt(clockTimeAdjusted());
	scannedWormholes.push_back(oo::EntityHold(whole));
}


// Checks through our array of wormholes for any which have expired
// If it is in the current system, spawn ships
// Else remove it
void PlayerEntity::updateWormholes()
{
	if (scannedWormholes.empty())
		return;

	double now = clockTimeAdjusted();

	std::vector<oo::EntityHold> savedWormholes;
	savedWormholes.reserve(scannedWormholes.size());

	for (const oo::EntityHold &whRef : scannedWormholes)
	{
		WormholeEntity *wh = static_cast<WormholeEntity *>(whRef.get());
		// TODO: Start drawing wormhole exit a few seconds before the first
		//       ship is disgorged.
		if ((wh != nullptr ? wh->arrivalTime() : 0.0) > now)
		{
			savedWormholes.push_back(whRef);
		}
		else if (NSEqualPoints(galaxy_coordinates, (wh != nullptr ? wh->destinationCoordinates() : NSPoint{})))
		{
			if (wh != nullptr)  wh->disgorgeShips();
			if ((wh != nullptr ? wh->getShipsInTransit() : oo::PList()).count() > 0)
			{
				savedWormholes.push_back(whRef);
			}
		}
		// Else wormhole has expired in another system, let it expire
	}

	scannedWormholes = std::move(savedWormholes);
}


std::vector<oo::EntityHold> PlayerEntity::getScannedWormholes()
{
	return scannedWormholes;
}


void PlayerEntity::initialiseMissionDestinations(const oo::PList &destinations, const oo::PList &legacy)
{
	missionDestinations.clear();

	// the dictionary entries that are themselves dictionaries
	if (const oo::PList::Dict *entries = destinations.getIf<oo::PList::Dict>())
	{
		for (const auto &[key, value] : *entries)
		{
			if (value.isDict())
			{
				missionDestinations.insert_or_assign(key, value);
			}
		}
	}

	if (legacy.isArray())
	{
		OOSystemID dest;
		for (size_t legacyMarker = 0; legacyMarker < legacy.count(); legacyMarker++)
		{
			dest = legacy.at<int>(legacyMarker);	// -intValue
			addMissionDestinationMarker(defaultMarker(dest));
		}
	}
}


std::optional<std::string> PlayerEntity::markerKey(const oo::PList &marker)
{
	// "%d-%@": a missing (or non-string) name reads "(null)"
	const oo::PList *markerName = marker.find("name");
	const std::string *nameText = (markerName != nullptr) ? markerName->getIf<std::string>() : nullptr;
	return oo::str::format("%d-%s", marker.get<int>("system", 0), (nameText != nullptr) ? nameText->c_str() : "(null)");
}


void PlayerEntity::addMissionDestinationMarker(const oo::PList &marker)
{
	const oo::PList validated = validatedMarker(marker);
	if (validated.isNull())
	{
		return;
	}

	missionDestinations.insert_or_assign(*markerKey(validated), validated);
}


bool PlayerEntity::removeMissionDestinationMarker(const oo::PList &marker)
{
	const oo::PList validated = validatedMarker(marker);
	if (validated.isNull())
	{
		return NO;
	}
	// YES if there was one to remove
	return missionDestinations.erase(*markerKey(validated)) > 0 ? YES : NO;
}


oo::PList PlayerEntity::getMissionDestinations()
{
	return oo::PList(missionDestinations);	// a snapshot
}


oo::PList::Dict *PlayerEntity::shipyardRecord()
{
	return &shipyard_record;
}


void PlayerEntity::setLastShot(const std::vector<oo::Ref<OOLaserShotEntity>> &shot)
{
	lastShot = shot;
}


void PlayerEntity::clearExtraMissionKeys()
{
	extraMissionKeys.clear();
}


void PlayerEntity::setExtraMissionKeys(const oo::PList &keys)
{
	std::map<std::string, oo::PList, std::less<>> final;
	if (const oo::PList::Dict *keyDict = keys.getIf<oo::PList::Dict>())
	{
		for (const auto &[key, value] : *keyDict)
		{
			final[key] = processKeyCode((value.isArray() ? value : oo::PList()));	// oo_arrayForKey:
		}
	}
	extraMissionKeys = std::move(final);
}


void PlayerEntity::clearExtraGuiScreenKeys(OOGUIScreenID gui, const std::string &key)
{
	const auto screenKeys = extraGuiScreenKeys.find(gui);
	if (screenKeys == extraGuiScreenKeys.end())  return;
	std::vector<oo::Ref<::OOJSGuiScreenKeyDefinition>> &keydefs = screenKeys->second;
	std::size_t i = keydefs.size();
	while (i--)
	{
		::OOJSGuiScreenKeyDefinition *def = keydefs[i].get();
		// the old code read "name" from the definition object with PListView, which only reads
		// dictionaries, so this never matched; kept as it was (the definition was an Object node,
		// which find() does not look into; bead oo-9ht.62 deleted the facade it wrapped)
		const oo::PList definitionValue;
		const oo::PList *definitionName = definitionValue.find("name");
		if (def && definitionName != nullptr && definitionName->isString() && *definitionName->getIf<std::string>() == key)
		{
			keydefs.erase(keydefs.begin() + static_cast<std::ptrdiff_t>(i));
			break;
		}
	}
}


bool PlayerEntity::setExtraGuiScreenKeys(OOGUIScreenID gui, ::OOJSGuiScreenKeyDefinition *definition)
{
	// process all the keys in the definition
	BOOL result = YES;
	oo::PList::Dict final;
	const oo::PList keys = (definition != nullptr) ? definition->registerKeys() : oo::PList();	// a message to nil answered nil
	std::vector<oo::PList> checklist;

	if (const oo::PList::Dict *keyDict = keys.getIf<oo::PList::Dict>())
	{
		for (const auto &[key, value] : *keyDict)
		{
			oo::PList item = processKeyCode((value.isArray() ? value : oo::PList()));	// oo_arrayForKey:
			checklist.push_back(item);
			final[key] = std::move(item);
		}
	}
	if (definition != nullptr)  definition->setRegisterKeys(oo::PList(std::move(final)));

	std::vector<oo::Ref<::OOJSGuiScreenKeyDefinition>> newarray;
	const auto existing = extraGuiScreenKeys.find(gui);
	if (existing != extraGuiScreenKeys.end())
	{
		newarray = existing->second;
		std::size_t i = newarray.size();
		while (i--)
		{
			::OOJSGuiScreenKeyDefinition *def_existing = newarray[i].get();
			// if we find this name already in the array, remove it
			if (def_existing && def_existing->name().has_value() && def_existing->name() == ((definition != nullptr) ? definition->name() : std::nullopt))	// (-isEqualToString: of nil was NO)
			{
				newarray.erase(newarray.begin() + static_cast<std::ptrdiff_t>(i));
			}
			else
			{
				// check whether any of those keycodes is already in use on this screen
				const oo::PList keydefs = (def_existing != nullptr) ? def_existing->registerKeys() : oo::PList();
				const oo::PList::Dict *keydefsDict = keydefs.getIf<oo::PList::Dict>();

				for (const auto &[key, keydef] : (keydefsDict != nullptr) ? *keydefsDict : oo::PList::Dict())	// byte order (was -allKeys order): only the log order can differ
				{
					std::size_t j = checklist.size();
					while (j--)
					{
						// the "%@" texts of the two key-code arrays
						if (oo::DescriptionOf(keydef) == oo::DescriptionOf(checklist[j]))
						{
							result = NO;
							OO_LOG(cxx_kOOLogException, "***** Exception in setExtraGuiScreenKeys: {} : {} ({})", "invalid key settings", "key already in use", key);
						}
					}
				}
			}
		}
	}
	newarray.push_back(oo::Ref<::OOJSGuiScreenKeyDefinition>(definition));
	// only add the item if there were no errors
	if (result) extraGuiScreenKeys[gui] = std::move(newarray);
	return result;
}


#ifndef NDEBUG
void PlayerEntity::dumpSelfState()
{
	std::vector<std::string>	flags;
	std::string			flagsString;
	
	ShipEntity::dumpSelfState();
	
	OO_LOG("dumpState.playerEntity", "Script time: {:g}", script_time);
	OO_LOG("dumpState.playerEntity", "Script time check: {:g}", script_time_check);
	OO_LOG("dumpState.playerEntity", "Script time interval: {:g}", script_time_interval);
	OO_LOG("dumpState.playerEntity", "Roll/pitch/yaw delta: {:g}, {:g}, {:g}", roll_delta, pitch_delta, yaw_delta);
	OO_LOG("dumpState.playerEntity", "Shield: {:g} fore, {:g} aft", forward_shield, aft_shield);
	OO_LOG("dumpState.playerEntity", "Alert level: {}, flags: {:#x}", static_cast<unsigned>(alertFlags), static_cast<unsigned>(alertConditionLevel));
	OO_LOG("dumpState.playerEntity", "Missile status: {}", static_cast<unsigned>(missile_status));
	OO_LOG("dumpState.playerEntity", "Energy unit: {}", cxx_EnergyUnitTypeToString(installedEnergyUnitType()));
	OO_LOG("dumpState.playerEntity", "Fuel leak rate: {:g}", fuel_leak_rate);
	OO_LOG("dumpState.playerEntity", "Trumble count: {}", trumbleCount);
	
	#define ADD_FLAG_IF_SET(x)		if (x) { flags.push_back(#x); }
	ADD_FLAG_IF_SET(found_equipment);
	ADD_FLAG_IF_SET(pollControls);
	if (suppressTargetLostFlag) { flags.push_back("suppressTargetLost"); }	// the ivar's name, as the dump printed it
	ADD_FLAG_IF_SET(scoopsActive);
	ADD_FLAG_IF_SET(game_over);
	ADD_FLAG_IF_SET(finished);
	ADD_FLAG_IF_SET(bomb_detonated);
	ADD_FLAG_IF_SET(autopilot_engaged);
	ADD_FLAG_IF_SET(afterburner_engaged);
	ADD_FLAG_IF_SET(afterburnerSoundLooping);
	ADD_FLAG_IF_SET(hyperspeed_engaged);
	ADD_FLAG_IF_SET(travelling_at_hyperspeed);
	ADD_FLAG_IF_SET(hyperspeed_locked);
	ADD_FLAG_IF_SET(ident_engaged);
	ADD_FLAG_IF_SET(galactic_witchjump);
	ADD_FLAG_IF_SET(ecm_in_operation);
	ADD_FLAG_IF_SET(show_info_flag);
	ADD_FLAG_IF_SET(showDemoShips);
	ADD_FLAG_IF_SET(rolling);
	ADD_FLAG_IF_SET(pitching);
	ADD_FLAG_IF_SET(yawing);
	ADD_FLAG_IF_SET(using_mining_laser);
	ADD_FLAG_IF_SET(mouse_control_on);
//	ADD_FLAG_IF_SET(isSpeechOn);
	ADD_FLAG_IF_SET(keyboardRollOverride);   // Handle keyboard roll...
	ADD_FLAG_IF_SET(keyboardPitchOverride);  // ...and pitch override separately - (fix for BUG #17490)
	ADD_FLAG_IF_SET(keyboardYawOverride);
	ADD_FLAG_IF_SET(waitingForStickCallback);
	for (const std::string &flag : flags)  flagsString += (flagsString.empty() ? "" : ", ") + flag;
	if (flags.empty())  flagsString = "none";
	OO_LOG("dumpState.playerEntity", "Flags: {}", flagsString);
}
#endif


#if OO_DEBUG
// What the deleted categories PlayerEntity (JSVectorStatistics) / (JSQuaternionStatistics) answered
// (bead oo-9ht.15): one-line forwarders to the functions that hold their bodies.
oo::PList PlayerEntity::reportJSVectorStatistics()		{ return ::reportJSVectorStatistics(); }
void PlayerEntity::clearJSVectorStatistics()			{ ::clearJSVectorStatistics(); }
oo::PList PlayerEntity::reportJSQuaternionStatistics()	{ return ::reportJSQuaternionStatistics(); }
void PlayerEntity::clearJSQuaternionStatistics()		{ ::clearJSQuaternionStatistics(); }
#endif




#ifndef NDEBUG
/*	This method exists purely to suppress Clang static analyzer warnings that
	these ivars are unused (but may be used by categories, which they are).
	FIXME: there must be a feature macro we can use to avoid actually building
	this into the app, but I can't find it in docs.
	
	Mind you, we could suppress some of this by using civilized accessors.
*/
bool PlayerEntity::suppressClangStuff() const
{
	return missionChoice.has_value() &&
	!commanderNameString.empty() &&
	!cdrDetailArray.empty() &&
	currentPage &&
	n_key_roll_left &&
	n_key_roll_right &&
	n_key_pitch_forward &&
	n_key_pitch_back &&
	n_key_yaw_left &&
	n_key_yaw_right &&
	n_key_view_forward &&
	n_key_view_aft &&
	n_key_view_port &&
	n_key_view_starboard &&
	n_key_launch_ship &&
	n_key_gui_screen_options &&
	n_key_gui_screen_equipship &&
	n_key_gui_screen_interfaces &&
	n_key_gui_screen_status &&
	n_key_gui_chart_screens &&
	n_key_gui_system_data &&
	n_key_gui_market &&
	n_key_gui_arrow_left &&
	n_key_gui_arrow_right &&
	n_key_gui_arrow_up &&
	n_key_gui_arrow_down &&
	n_key_gui_page_up &&
	n_key_gui_page_down &&
	n_key_gui_select &&
	n_key_increase_speed &&
	n_key_decrease_speed &&
	n_key_inject_fuel &&
	n_key_fire_lasers &&
	n_key_launch_missile &&
	n_key_next_missile &&
	n_key_ecm &&
	n_key_prime_next_equipment &&
	n_key_prime_previous_equipment &&
	n_key_activate_equipment &&
	n_key_mode_equipment &&
	n_key_fastactivate_equipment_a &&
	n_key_fastactivate_equipment_b &&
	n_key_target_missile &&
	n_key_untarget_missile &&
	n_key_target_incoming_missile &&
	n_key_ident_system &&
	n_key_scanner_zoom &&
	n_key_scanner_unzoom &&
	n_key_launch_escapepod &&
	n_key_galactic_hyperspace &&
	n_key_hyperspace &&
	n_key_jumpdrive &&
	n_key_dump_cargo &&
	n_key_rotate_cargo &&
	n_key_autopilot &&
	n_key_autodock &&
	n_key_snapshot &&
	n_key_docking_music &&
	n_key_advanced_nav_array_next &&
	n_key_advanced_nav_array_previous &&
	n_key_info_next_system &&
	n_key_info_previous_system &&
	n_key_map_home &&
	n_key_map_end &&
	n_key_map_next_system &&
	n_key_map_previous_system &&
	n_key_map_info &&
	n_key_map_zoom_in &&
	n_key_map_zoom_out &&
	n_key_system_home &&
	n_key_system_end &&
	n_key_system_next_system &&
	n_key_system_previous_system &&
	n_key_pausebutton &&
	n_key_show_fps &&
	n_key_bloom_toggle &&
	n_key_mouse_control_roll &&
	n_key_mouse_control_yaw &&
	n_key_hud_toggle &&
	n_key_comms_log &&
	n_key_prev_compass_mode &&
	n_key_next_compass_mode &&
	n_key_chart_highlight &&
	n_key_market_filter_cycle &&
	n_key_market_sorter_cycle &&
	n_key_market_buy_one &&
	n_key_market_sell_one &&
	n_key_market_buy_max &&
	n_key_market_sell_max &&
	n_key_next_target &&
	n_key_previous_target &&
	n_key_custom_view &&
	n_key_custom_view_zoom_out &&
	n_key_custom_view_zoom_in &&
	n_key_custom_view_roll_left &&
	n_key_custom_view_pan_left &&
	n_key_custom_view_roll_right &&
	n_key_custom_view_pan_right &&
	n_key_custom_view_rotate_up &&
	n_key_custom_view_pan_up &&
	n_key_custom_view_rotate_down &&
	n_key_custom_view_pan_down &&
	n_key_custom_view_rotate_left &&
	n_key_custom_view_rotate_right &&
	n_key_docking_clearance_request &&
	n_key_weapons_online_toggle &&
	n_key_cycle_next_mfd &&
	n_key_cycle_previous_mfd &&
	n_key_switch_next_mfd &&
	n_key_switch_previous_mfd &&
	n_key_oxzmanager_setfilter &&
	n_key_oxzmanager_showinfo &&
	n_key_oxzmanager_extract &&
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
	n_key_inc_field_of_view &&
	n_key_dec_field_of_view &&
#endif
	n_key_dump_target_state &&
	n_key_dump_entity_list &&
	n_key_debug_full &&
	n_key_debug_collision &&
	n_key_debug_console_connect &&
	n_key_debug_bounding_boxes &&
	n_key_debug_shaders &&
	n_key_debug_off &&
	_sysInfoLight.x &&
	selFunctionIdx &&
	!stickFunctions.empty() &&
	!keyFunctions.empty() &&
	!customEquipActivation.empty() &&
	!customActivatePressed.empty() &&
	!customModePressed.empty() &&
	!kbdLayouts.empty() &&
	showingLongRangeChart &&
	_missionAllowInterrupt &&
	_missionScreenID.has_value() &&
	_missionTitle.has_value() &&
	_missionTextEntry;
}
#endif

