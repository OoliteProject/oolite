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

#import "PlayerEntity.h"

#include <vector>
#import "PlayerEntityContracts.h"
#import "PlayerEntityControls.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "PlayerEntityScriptMethods.h"
#import "PlayerEntitySound.h"
#include "oofnd/Process.hpp"

#import "OOLaserShotEntity.h"
#import "OOMesh.h"
#import "OOPlanetEntity.h"
#import "OOQuiriumCascadeEntity.h"
#import "OOSunEntity.h"
#import "ProxyPlayerEntity.h"
#import "StationEntity.h"
#import "WormholeEntity.h"

#import "AI.h"
#import "GameController.h"
#import "HeadUpDisplay.h"
#import "MyOpenGLView.h"
#import "NSFileManagerOOExtensions.h"
#import "OOCacheManager.h"
#import "OOColor.h"
#import "OOConstToString.h"
#import "OODebugSupport.h"
#import "OOEntityFilterPredicate.h"
#import "OOEquipmentType.h"
#import "OOFullScreenController.h"
#import "OOMaths.h"
#import "OOMusicController.h"
#import "OOOXZManager.h"
#import "OOOpenGLExtensionManager.h"
#import "OOPListParsing.h"
#import "OOPListView.h"
#import "OORoleSet.h"
#import "OOShipRegistry.h"
#import "OOSound.h"
#import "OOStringExpander.h"
#import "OOStringParsing.h"
#import "OOTexture.h"
#import "OOTrumble.h"
#import "Octree.h"
#import "PlayerEntityLoadSave.h"
#import "ResourceManager.h"
#import "ShipEntityAI.h"
#import "Universe.h"

#import "CollisionRegion.h"

#import "OOConstToJSString.h"
#import "OOJSEngineTimeManagement.h"
#import "OOJSGuiScreenKeyDefinition.h"
#import "OOJSInterfaceDefinition.h"
#import "OOJSScript.h"
#import "OOScriptTimer.h"

#import "OOFoundationBridge.h"
#import "OOFoundationException.h"
#import "OOJoystickManager.h"
#import "OOStringBridge.h"
#import "OOSystemDescriptionManager.h"
#import "PlayerEntityKeyMapper.h"
#import "PlayerEntityStickMapper.h"
#import "PlayerEntityStickProfile.h"
#include "oofnd/Defaults.hpp"
#include "oofnd/FileSystem.hpp"
#include "oofnd/PListGet.hpp"
#include "oofnd/PListParsing.hpp"
#include "oofnd/ResourcePaths.hpp"

#define PLAYER_DEFAULT_NAME @"Jameson"

enum {
    // If comm log is kCommLogTrimThreshold or more lines long, it will be cut to kCommLogTrimSize.
    kCommLogTrimThreshold = 15U,
    kCommLogTrimSize = 10U
};

namespace {

/*	What oo::PListView(dict).get<NSString *> / get<Vector> / get<Quaternion> answered, for a
        configuration held as an oo::PList (the Foundation sweep, proposed ADR-0043): a string is
        nullopt when the key is absent or holds neither a string nor a number; vectors and quaternions
        go through OOCollectionExtractors' readers (unmigrated) with their defaults for a missing key.
        (Same readers as ShipEntity.mm's.)
*/
std::optional<std::string> StringForKey(const oo::PList& dict, std::string_view key)
{
    const oo::PList* value = dict.find(key);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return oo::PListGet<std::string>::from(value, std::string());
}

Vector VectorForKey(const oo::PList& dict, std::string_view key)
{
    const oo::PList* value = dict.find(key);
    return OOVectorFromObject(value != nullptr ? oo::ObjectFromPList(*value) : nil, kZeroVector);
}

Quaternion QuaternionForKey(const oo::PList& dict, std::string_view key)
{
    const oo::PList* value = dict.find(key);
    return OOQuaternionFromObject(value != nullptr ? oo::ObjectFromPList(*value) : nil, kIdentityQuaternion);
}

// OOExpandKeyWithSeed(seed, key, ...) with its arguments as a Dict (ints as PList::signedInteger,
// NSUIntegers as PList::unsignedInteger, strings as std::string); no arguments passes nil, as the
// macro did. Exemplar: OOShipLibraryDescriptions.mm ExpandCategoryKey.
std::string ExpandKeyWithSeed(Random_Seed seed, const std::string& key, const oo::PList::Dict& args)
{
    return oo::StdString(OOExpandDescriptionString(seed, oo::NSStringFrom(key),
        args.empty() ? nil : oo::ObjectFromPList(oo::PList(args)), nil, nil, kOOExpandKey));
}

// A %@ argument for oo::str::formatRuntime: the text, or "(null)" for nil.
oo::str::FormatArg TextArg(const std::optional<std::string>& text)
{
    return text.has_value() ? oo::str::FormatArg(*text) : oo::str::FormatArg::null();
}

// -indexOfObject: on the goods list: NSNotFound when absent, or for nil.
NSUInteger IndexOfGood(const std::vector<std::string>& goods, const std::optional<std::string>& good)
{
    if (!good.has_value())
        return NSNotFound;
    const auto found = std::find(goods.begin(), goods.end(), *good);
    return (found != goods.end()) ? static_cast<NSUInteger>(found - goods.begin()) : NSNotFound;
}

// The market sorters, as orderings (< 0, 0, > 0 for NSOrderedAscending, Same, Descending) over
// commodity keys; used with std::stable_sort, as -sortedArrayUsingFunction:context: is a stable
// sort in GNUstep (probed on gnustep-base: ties keep their order).
int marketSorterByName(const std::string& a, const std::string& b, OOCommodityMarket* market)
{
    // (-compare: on a nil name: goods always have names)
    return oo::str::compare([market cxx_nameForGood:a].value_or(std::string()), [market cxx_nameForGood:b].value_or(std::string()));
}

int marketSorterByPrice(const std::string& a, const std::string& b, OOCommodityMarket* market)
{
    int result = (int)[market cxx_priceForGood:a] - (int)[market cxx_priceForGood:b];
    return (result < 0) ? -1 : ((result > 0) ? 1 : 0);
}

int marketSorterByQuantity(const std::string& a, const std::string& b, OOCommodityMarket* market)
{
    int result = (int)[market cxx_quantityForGood:a] - (int)[market cxx_quantityForGood:b];
    return (result < 0) ? -1 : ((result > 0) ? 1 : 0);
}

int marketSorterByMassUnit(const std::string& a, const std::string& b, OOCommodityMarket* market)
{
    int result = (int)[market massUnitForGood:oo::NSStringFrom(a)] - (int)[market massUnitForGood:oo::NSStringFrom(b)];
    return (result < 0) ? -1 : ((result > 0) ? 1 : 0);
}

// A custom_views value as the list of views (oo_arrayForKey: nil unless an array -> empty).
std::vector<oo::PList> CustomViewsFrom(const oo::PList& value)
{
    const oo::PList::Array* views = value.getIf<oo::PList::Array>();
    return (views != nullptr) ? *views : std::vector<oo::PList>();
}

// The docked station's interface for <key>, or nil (objectForKey: on a nil dictionary or key).
OOJSInterfaceDefinition* InterfaceForKey(StationEntity* station, const std::optional<std::string>& key)
{
    const auto* interfaces = [station cxx_localInterfaces];
    if (interfaces == nullptr || !key.has_value())
        return nil;
    const auto it = interfaces->find(*key);
    return (it != interfaces->end()) ? it->second.get() : nil;
}

// A roleWeightFlags count (-oo_intForKey: with default 0).
int RoleFlagCount(const oo::PList::Dict& flags, const std::string& role)
{
    const auto it = flags.find(role);
    return (it != flags.end()) ? oo::PListGet<int>::from(&it->second, 0) : 0;
}

// The recently visited systems as saved: an array of signed integers (+numberWithInt:).
oo::PList SystemListPList(const std::vector<OOSystemID>& systems)
{
    oo::PList::Array result;
    result.reserve(systems.size());
    for (OOSystemID system : systems)
        result.push_back(oo::PList::signedInteger(system));
    return oo::PList(std::move(result));
}

// A two-column GUI row as [NSArray arrayWithObjects:first, second, nil] built it: it ends at the first nil.
std::vector<std::string> RowOf(const std::optional<std::string>& first, const std::optional<std::string>& second)
{
    std::vector<std::string> row;
    if (first.has_value()) {
        row.push_back(*first);
        if (second.has_value())
            row.push_back(*second);
    }
    return row;
}

// An equipment-list row: [text, availability, colour], ending at the first nil as arrayWithObjects: did.
oo::PList EquipmentRow(const std::optional<std::string>& text, bool available, OOColor* color)
{
    oo::PList::Array row;
    if (text.has_value()) {
        row.push_back(oo::PList(*text));
        row.push_back(oo::PList(available)); // +numberWithBool:
        if (color != nil)
            row.push_back(oo::PListObject(color));
    }
    return oo::PList(std::move(row));
}

// "More:<n>[:<key>]" row keys: field <index>, or nullopt past the end.
std::optional<std::string> RowKeyField(const std::string& key, size_t index)
{
    const std::vector<std::string> fields = oo::str::split(key, ":");
    if (index < fields.size())
        return fields[index];
    return std::nullopt;
}

} // namespace

static float const kDeadResetTime = 30.0f;

PlayerEntity* gOOPlayer = nil;
static GLfloat sBaseMass = 0.0;

@interface PlayerEntity (OOPrivate)

- (void)setExtraEquipmentFromFlags;
- (void)doTradeIn:(OOCreditsQuantity)tradeInValue forPriceFactor:(double)priceFactor;

// Subs of update:
- (void)updateMovementFlags;
- (void)updateAlertCondition;
- (void)updateFuelScoops:(OOTimeDelta)delta_t;
- (void)updateClocks:(OOTimeDelta)delta_t;
- (void)checkScriptsIfAppropriate;
- (void)updateTrumbles:(OOTimeDelta)delta_t;
- (void)performAutopilotUpdates:(OOTimeDelta)delta_t;
- (void)performInFlightUpdates:(OOTimeDelta)delta_t;
- (void)performWitchspaceCountdownUpdates:(OOTimeDelta)delta_t;
- (void)performWitchspaceExitUpdates:(OOTimeDelta)delta_t;
- (void)performLaunchingUpdates:(OOTimeDelta)delta_t;
- (void)performDockingUpdates:(OOTimeDelta)delta_t;
- (void)performDeadUpdates:(OOTimeDelta)delta_t;
- (void)gameOverFadeToBW;
- (void)updateTargeting;
- (void)showGameOver;
- (void)updateWormholes;

- (void)updateAlertConditionForNearbyEntities;
- (BOOL)checkEntityForMassLock:(Entity*)ent withScanClass:(int)scanClass;

// Shopping
- (void)showMarketScreenHeaders;
- (void)showMarketScreenDataLine:(OOGUIRow)row forGood:(const std::string&)good inMarket:(OOCommodityMarket*)localMarket holdQuantity:(OOCargoQuantity)quantity;
- (void)showMarketCashAndLoadLine;

- (BOOL)tryBuyingItem:(const std::string&)eqKey;

// Cargo & passenger contracts
- (oo::PList::Array)contractsListForScriptingFromArray:(const oo::PList::Array&)contractsArray forCargo:(BOOL)forCargo;

- (void)witchStart;
- (void)witchJumpTo:(OOSystemID)sTo misjump:(BOOL)misjump;
- (void)witchEnd;

// Jump distance/cost calculations for selected target.
- (double)hyperspaceJumpDistance;
- (OOFuelQuantity)fuelRequiredForJump;

- (void)noteCompassLostTarget;

@end

@interface ShipEntity (Hax)

- (id)initBypassForPlayer;

@end

namespace {

// Info-gnustep.plist string (CFBundleVersion / CFBundleName as the Override category used to expose).
std::optional<std::string> OoliteInfoString(std::string_view key)
{
    const oo::fs::Path plistPath = oo::ResourcePaths::current().builtInResourcesDirectory() / "Info-gnustep.plist";
    oo::PList info;
    if (const oo::fs::Result<oo::Data> bytes = oo::fs::readFile(plistPath); bytes && !bytes->empty()) {
        if (oo::Expected<oo::PList, oo::PListError> parsed = oo::parsePropertyList(bytes->stringView());
            parsed && parsed->isDict())
            info = std::move(*parsed);
    }
    if (const oo::PList* v = info.find(key); v != nullptr && v->isString())
        return *v->getIf<std::string>();
    return std::nullopt;
}

} // namespace

@implementation PlayerEntity

+ (PlayerEntity*)sharedPlayer
{
    if (EXPECT_NOT(gOOPlayer == nil)) {
        gOOPlayer = [[PlayerEntity alloc] init];
    }
    return gOOPlayer;
}

- (void)setName:(id)inName // shared selector (proposed ADR-0043): an Objective-C string
{
    // Block super method; player ship can't be renamed.
}

- (GLfloat)baseMass
{
    if (sBaseMass <= 0.0) {
        // First call with initialised mass (in [UNIVERSE setUpInitialUniverse]) is always to the cobra 3, even when starting with a savegame.
        if ([self mass] > 0.0) // bootstrap the base mass.
        {
            OO_LOG("fuelPrices", "Setting Cobra3 base mass to: {:.2f} ", [self mass]);
            sBaseMass = [self mass];
        } else {
            // This happened on startup when [UNIVERSE setUpSpace] was called before player init, inside [UNIVERSE setUpInitialUniverse].
            OO_LOG("fuelPrices", "{}", "Player ship not initialised properly yet, using precalculated base mass.");
            return 185580.0;
        }
    }

    return sBaseMass;
}

- (void)unloadAllCargoPodsForType:(const std::string&)type toManifest:(OOCommodityMarket*)manifest
{
    NSInteger i, cargoCount = cargo.size();
    if (cargoCount == 0)
        return;

    // step through the cargo pods adding in the quantities
    for (i = cargoCount - 1; i >= 0; i--) {
        ShipEntity* cargoItem = cargo[i].get();
        const std::optional<std::string> commodityType = [cargoItem cxx_commodityType];
        if (!commodityType.has_value() || *commodityType == type) {
            if (commodityType.has_value()) {
                // transfer
                [manifest cxx_addQuantity:[cargoItem commodityAmount] forGood:type];
            } else // undefined
            {
                OO_LOG("player.badCargoPod", "Cargo pod {} has bad commodity type, rejecting.", oo::DescriptionOf(cargoItem));
                continue;
            }
            cargo.erase(cargo.begin() + i);
        }
    }
}

- (void)unloadCargoPodsForType:(const std::string&)type amount:(OOCargoQuantity)quantity
{
    NSInteger i, n_cargo = cargo.size();
    if (n_cargo == 0)
        return;

    ShipEntity* cargoItem = nil;
    std::optional<std::string> co_type;
    OOCargoQuantity amount;
    OOCargoQuantity cargoToGo = quantity;

    // step through the cargo pods removing pods or quantities
    for (i = n_cargo - 1; (i >= 0 && cargoToGo > 0); i--) {
        cargoItem = cargo[i].get();
        co_type = [cargoItem cxx_commodityType];
        if (!co_type.has_value() || *co_type == type) {
            if (co_type.has_value()) {
                amount = [cargoItem commodityAmount];
                if (amount <= cargoToGo) {
                    cargo.erase(cargo.begin() + i);
                    cargoToGo -= amount;
                } else {
                    // we only need to remove a part of the cargo to meet our target
                    [cargoItem cxx_setCommodity:*co_type andAmount:(amount - cargoToGo)];
                    cargoToGo = 0;
                }
            } else // undefined
            {
                OO_LOG("player.badCargoPod", "Cargo pod {} has bad commodity type (COMMODITY_UNDEFINED), rejecting.", oo::DescriptionOf(cargoItem));
                continue;
            }
        }
    }

    // now check if we are ready. When not, proceed with quantities in the manifest.
    if (cargoToGo > 0) {
        [shipCommodityData cxx_removeQuantity:cargoToGo forGood:type];
    }
}

- (void)unloadCargoPods
{
    NSAssert([self isDocked], @"Cannot unload cargo pods unless docked.");

    /* loads commodities from the cargo pods onto the ship's manifest */
    for (const std::string& good : oo::StringsFrom([shipCommodityData goods])) {
        [self unloadAllCargoPodsForType:good toManifest:shipCommodityData];
    }
#ifndef NDEBUG
    if (cargo.size() > 0) {
        OO_LOG("player.unloadCargo", "Cargo remains in pods after unloading - {}", oo::DescriptionOf(oo::NSArrayFromObjects(cargo)));
    }
#endif

    [self calculateCurrentCargo]; // work out the correct value for current_cargo
}

// TODO: better feedback on the log as to why failing to create player cargo pods causes a CTD?
- (void)createCargoPodWithType:(const std::string&)type andAmount:(OOCargoQuantity)amount
{
    ShipEntity* container = [UNIVERSE newShipWithRole:@"1t-cargopod"];
    if (container) {
        [container setScanClass:CLASS_CARGO];
        [container setStatus:STATUS_IN_HOLD];
        [container cxx_setCommodity:type andAmount:amount];
        cargo.emplace_back(container);
        [container release];
    } else {
        OO_LOG_ERR("player.loadCargoPods.noContainer", "{}", "couldn't create a container in [PlayerEntity loadCargoPods]");
        // throw an exception here...
        [OOException raise:OOLITE_EXCEPTION_FATAL
                    format:"[PlayerEntity loadCargoPods] failed to create a container for cargo with role 'cargopod'"];
    }
}

- (void)loadCargoPodsForType:(const std::string&)type fromManifest:(OOCommodityMarket*)manifest
{
    // load commodities from the ships manifest into individual cargo pods
    unsigned j;

    OOCargoQuantity quantity = [manifest cxx_quantityForGood:type];
    OOMassUnit units = [manifest massUnitForGood:oo::NSStringFrom(type)];

    if (quantity > 0) {
        if (units == UNITS_TONS) {
            // easy case
            for (j = 0; j < quantity; j++) {
                [self createCargoPodWithType:type andAmount:1]; // or CTD if unsuccesful (!)
            }
            [manifest cxx_setQuantity:0 forGood:type];
        } else {
            OOCargoQuantity podsRequiredForQuantity, amountToLoadInCargopod, tmpQuantity;
            // reserve up to 1/2 ton of each commodity for the safe
            if (units == UNITS_KILOGRAMS) {
                if (quantity <= MAX_KILOGRAMS_IN_SAFE) {
                    tmpQuantity = quantity;
                    quantity = 0;
                } else {
                    tmpQuantity = MAX_KILOGRAMS_IN_SAFE;
                    quantity -= tmpQuantity;
                }
                amountToLoadInCargopod = KILOGRAMS_PER_POD;
            } else {
                if (quantity <= MAX_GRAMS_IN_SAFE) {
                    tmpQuantity = quantity;
                    quantity = 0;
                } else {
                    tmpQuantity = MAX_GRAMS_IN_SAFE;
                    quantity -= tmpQuantity;
                }
                amountToLoadInCargopod = GRAMS_PER_POD;
            }
            if (quantity > 0) {
                podsRequiredForQuantity = 1 + (quantity / amountToLoadInCargopod);
                // this check is needed so that initial quantities like 1499kg or 1499999g
                // do not result in generation of an empty cargopod
                if (quantity % amountToLoadInCargopod == 0)
                    podsRequiredForQuantity--;

                // put each ton or part-ton beyond that in a separate container
                for (j = 0; j < podsRequiredForQuantity; j++) {
                    if (amountToLoadInCargopod > quantity) {
                        // last pod gets the dregs. :)
                        amountToLoadInCargopod = quantity;
                    }
                    [self createCargoPodWithType:type andAmount:amountToLoadInCargopod]; // or CTD if unsuccesful (!)
                    quantity -= amountToLoadInCargopod;
                }
                // adjust manifest for this commodity
                [manifest cxx_setQuantity:tmpQuantity forGood:type];
            }
        }
    }
}

- (void)loadCargoPodsForType:(const std::string&)type amount:(OOCargoQuantity)quantity
{
    OOMassUnit unit = [shipCommodityData massUnitForGood:oo::NSStringFrom(type)];

    while (quantity) {
        if (unit != UNITS_TONS) {
            int amount_per_container = (unit == UNITS_KILOGRAMS) ? KILOGRAMS_PER_POD : GRAMS_PER_POD;
            while (quantity > 0) {
                int smaller_quantity = 1 + ((quantity - 1) % amount_per_container);
                if (cargo.size() < [self maxAvailableCargoSpace]) {
                    ShipEntity* container = [UNIVERSE newShipWithRole:@"1t-cargopod"];
                    if (container) {
                        // the cargopod ship is just being set up. If ejected,  will call UNIVERSE addEntity
                        [container setStatus:STATUS_IN_HOLD];
                        [container setScanClass:CLASS_CARGO];
                        [container cxx_setCommodity:type andAmount:smaller_quantity];
                        cargo.emplace_back(container);
                        [container release];
                    }
                } else {
                    // try to squeeze any surplus, up to half a ton, in the manifest.
                    int amount = [shipCommodityData cxx_quantityForGood:type] + smaller_quantity;
                    if (amount > MAX_GRAMS_IN_SAFE && unit == UNITS_GRAMS)
                        amount = MAX_GRAMS_IN_SAFE;
                    else if (amount > MAX_KILOGRAMS_IN_SAFE && unit == UNITS_KILOGRAMS)
                        amount = MAX_KILOGRAMS_IN_SAFE;

                    [shipCommodityData cxx_setQuantity:amount forGood:type];
                }
                quantity -= smaller_quantity;
            }
        } else {
            // put each ton in a separate container
            while (quantity) {
                if (cargo.size() < [self maxAvailableCargoSpace]) {
                    ShipEntity* container = [UNIVERSE newShipWithRole:@"1t-cargopod"];
                    if (container) {
                        // the cargopod ship is just being set up. If ejected, will call UNIVERSE addEntity
                        [container setScanClass:CLASS_CARGO];
                        [container setStatus:STATUS_IN_HOLD];
                        [container cxx_setCommodity:type andAmount:1];
                        cargo.emplace_back(container);
                        [container release];
                    }
                }
                quantity--;
            }
        }
    }
}

- (void)loadCargoPods
{
    /* loads commodities from the ships manifest into individual cargo pods */
    for (const std::string& good : oo::StringsFrom([shipCommodityData goods])) {
        [self loadCargoPodsForType:good fromManifest:shipCommodityData];
    }
    [self calculateCurrentCargo]; // work out the correct value for current_cargo
    cargo_dump_time = 0;
}

- (OOCommodityMarket*)shipCommodityData
{
    return shipCommodityData;
}

- (OOCreditsQuantity)deciCredits
{
    return credits;
}

- (int)random_factor
{
    return market_rnd;
}

- (void)setRandom_factor:(int)rf
{
    market_rnd = rf;
}

- (OOGalaxyID)galaxyNumber
{
    return galaxy_number;
}

- (NSPoint)galaxy_coordinates
{
    return galaxy_coordinates;
}

- (void)setGalaxyCoordinates:(NSPoint)newPosition
{
    galaxy_coordinates.x = newPosition.x;
    galaxy_coordinates.y = newPosition.y;
}

- (NSPoint)cursor_coordinates
{
    return cursor_coordinates;
}

- (NSPoint)chart_centre_coordinates
{
    return chart_centre_coordinates;
}

- (OOScalar)chart_zoom
{
    if (_missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_SHORT || _missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_SHORT_ANA_QUICKEST || _missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_SHORT_ANA_SHORTEST) {
        return 1.0;
    } else if (_missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG || _missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_SHORTEST || _missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_QUICKEST) {
        return CHART_MAX_ZOOM;
    } else if (_missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_CUSTOM || _missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_QUICKEST || _missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_SHORTEST) {
        return custom_chart_zoom;
    }
    return chart_zoom;
}

- (OOScalar)custom_chart_zoom
{
    return custom_chart_zoom;
}

- (void)setCustomChartZoom:(OOScalar)zoom
{
    custom_chart_zoom = zoom;
}

- (NSPoint)custom_chart_centre_coordinates
{
    return custom_chart_centre_coordinates;
}

- (void)setCustomChartCentre:(NSPoint)coords
{
    custom_chart_centre_coordinates.x = coords.x;
    custom_chart_centre_coordinates.y = coords.y;
}

- (NSPoint)adjusted_chart_centre
{
    NSPoint acc; // adjusted chart centre
    double scroll_pos; // cursor coordinate at which we'd want to scoll chart in the direction we're currently considering
    double ecc; // chart centre coordinate we'd want if the cursor was on the edge of the galaxy in the current direction

    if (_missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_SHORT || _missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_SHORT_ANA_QUICKEST || _missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_SHORT_ANA_SHORTEST) {
        return galaxy_coordinates;
    } else if (_missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG || _missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_QUICKEST || _missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_SHORTEST) {
        return NSMakePoint(128.0, 128.0);
    } else if (_missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_CUSTOM || _missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_QUICKEST || _missionBackgroundSpecial == GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_SHORTEST) {
        return custom_chart_centre_coordinates;
    }
    // When fully zoomed in we want to centre chart on chart_centre_coordinates.  When zoomed out we want the chart centred on
    // (128.0, 128.0) so the galaxy fits the screen width.  For intermediate zoom we interpolate.
    acc.x = chart_centre_coordinates.x + (128.0 - chart_centre_coordinates.x) * (chart_zoom - 1.0) / (CHART_MAX_ZOOM - 1.0);
    acc.y = chart_centre_coordinates.y + (128.0 - chart_centre_coordinates.y) * (chart_zoom - 1.0) / (CHART_MAX_ZOOM - 1.0);

    // If the cursor is out of the centre non-scrolling part of the screen adjust the chart centre.  If the cursor is just at scroll_pos
    // we want to return the chart centre as it is, but if it's at the edge of the galaxy we want the centre positioned so the cursor is
    // at the edge of the screen
    if (chart_focus_coordinates.x - acc.x <= -CHART_SCROLL_AT_X * chart_zoom) {
        scroll_pos = acc.x - CHART_SCROLL_AT_X * chart_zoom;
        ecc = CHART_WIDTH_AT_MAX_ZOOM * chart_zoom / 2.0;
        if (scroll_pos <= 0) {
            acc.x = ecc;
        } else {
            acc.x = ((scroll_pos - chart_focus_coordinates.x) * ecc + chart_focus_coordinates.x * acc.x) / scroll_pos;
        }
    } else if (chart_focus_coordinates.x - acc.x >= CHART_SCROLL_AT_X * chart_zoom) {
        scroll_pos = acc.x + CHART_SCROLL_AT_X * chart_zoom;
        ecc = 256.0 - CHART_WIDTH_AT_MAX_ZOOM * chart_zoom / 2.0;
        if (scroll_pos >= 256.0) {
            acc.x = ecc;
        } else {
            acc.x = ((chart_focus_coordinates.x - scroll_pos) * ecc + (256.0 - chart_focus_coordinates.x) * acc.x) / (256.0 - scroll_pos);
        }
    }
    if (chart_focus_coordinates.y - acc.y <= -CHART_SCROLL_AT_Y * chart_zoom) {
        scroll_pos = acc.y - CHART_SCROLL_AT_Y * chart_zoom;
        ecc = CHART_HEIGHT_AT_MAX_ZOOM * chart_zoom / 2.0;
        if (scroll_pos <= 0) {
            acc.y = ecc;
        } else {
            acc.y = ((scroll_pos - chart_focus_coordinates.y) * ecc + chart_focus_coordinates.y * acc.y) / scroll_pos;
        }
    } else if (chart_focus_coordinates.y - acc.y >= CHART_SCROLL_AT_Y * chart_zoom) {
        scroll_pos = acc.y + CHART_SCROLL_AT_Y * chart_zoom;
        ecc = 256.0 - CHART_HEIGHT_AT_MAX_ZOOM * chart_zoom / 2.0;
        if (scroll_pos >= 256.0) {
            acc.y = ecc;
        } else {
            acc.y = ((chart_focus_coordinates.y - scroll_pos) * ecc + (256.0 - chart_focus_coordinates.y) * acc.y) / (256.0 - scroll_pos);
        }
    }
    return acc;
}

- (OORouteType)ANAMode
{
    return ANA_mode;
}

- (OOSystemID)systemID
{
    return system_id;
}

- (void)setSystemID:(OOSystemID)sid
{
    system_id = sid;
    galaxy_coordinates = PointFromString([[UNIVERSE systemManager] getProperty:@"coordinates" forSystem:sid inGalaxy:galaxy_number]);
    chart_centre_coordinates = galaxy_coordinates;
    target_chart_centre = chart_centre_coordinates;
}

- (OOSystemID)previousSystemID
{
    return previous_system_id;
}

- (void)setPreviousSystemID:(OOSystemID)sid
{
    previous_system_id = sid;
}

- (OOSystemID)targetSystemID
{
    return target_system_id;
}

- (void)setTargetSystemID:(OOSystemID)sid
{
    target_system_id = sid;
    cursor_coordinates = PointFromString([[UNIVERSE systemManager] getProperty:@"coordinates" forSystemKey:[UNIVERSE keyForPlanetOverridesForSystem:sid inGalaxy:galaxy_number]]);
}

// just return target system id if no valid next hop
- (OOSystemID)nextHopTargetSystemID
{
    // not available if no ANA
    if (![self hasEquipmentItemProviding:@"EQ_ADVANCED_NAVIGATIONAL_ARRAY"]) {
        return target_system_id;
    }
    // not available if ANA is turned off
    if (ANA_mode == OPTIMIZED_BY_NONE) {
        return target_system_id;
    }
    // easy case
    if (system_id == target_system_id) {
        return system_id; // no need to calculate
    }
    const oo::PList routeInfo = oo::PListFrom([UNIVERSE routeFromSystem:system_id toSystem:target_system_id optimizedBy:ANA_mode]);
    // no route to destination
    if (routeInfo.isNull()) {
        return target_system_id;
    }
    const oo::PList* route = routeInfo.get<oo::PList::Array>("route");
    return (route != nullptr) ? route->at<int>(1) : 0;
}

- (OOSystemID)infoSystemID
{
    return info_system_id;
}

- (void)setInfoSystemID:(OOSystemID)sid moveChart:(BOOL)moveChart
{
    if (sid != info_system_id) {
        OOSystemID old = info_system_id;
        info_system_id = sid;
        JSContext* context = OOJSAcquireContext();
        ShipScriptEvent(context, self, "infoSystemWillChange", OOJSValueFromDouble(context, info_system_id), OOJSValueFromDouble(context, old));
        if (gui_screen == GUI_SCREEN_LONG_RANGE_CHART || gui_screen == GUI_SCREEN_SHORT_RANGE_CHART) {
            if (moveChart) {
                target_chart_focus = [[UNIVERSE systemManager] getCoordinatesForSystem:info_system_id inGalaxy:galaxy_number];
            }
        } else {
            if (gui_screen == GUI_SCREEN_SYSTEM_DATA) {
                [self setGuiToSystemDataScreenRefreshBackground:YES];
            }
            if (moveChart) {
                chart_centre_coordinates = [[UNIVERSE systemManager] getCoordinatesForSystem:info_system_id inGalaxy:galaxy_number];
                target_chart_centre = chart_centre_coordinates;
                chart_focus_coordinates = chart_centre_coordinates;
                target_chart_focus = chart_focus_coordinates;
            }
        }
        ShipScriptEvent(context, self, "infoSystemChanged", OOJSValueFromDouble(context, info_system_id), OOJSValueFromDouble(context, old));
        OOJSRelinquishContext(context);
    }
}

- (void)nextInfoSystem
{
    if (ANA_mode == OPTIMIZED_BY_NONE) {
        [self setInfoSystemID:target_system_id moveChart:YES];
        return;
    }
    const oo::PList routeInfo = oo::PListFrom([UNIVERSE routeFromSystem:system_id toSystem:target_system_id optimizedBy:ANA_mode]);
    const oo::PList* route = routeInfo.get<oo::PList::Array>("route");
    NSUInteger i;
    if (route == nullptr) {
        [self setInfoSystemID:target_system_id moveChart:YES];
        return;
    }
    for (i = 0; i < route->count(); i++) {
        if (route->at<int>(i) == info_system_id) {
            if (i + 1 < route->count()) {
                [self setInfoSystemID:route->at<unsigned int>(i + 1) moveChart:YES];
                return;
            }
            break;
        }
    }
    [self setInfoSystemID:target_system_id moveChart:YES];
    return;
}

- (void)previousInfoSystem
{
    if (ANA_mode == OPTIMIZED_BY_NONE) {
        [self setInfoSystemID:system_id moveChart:YES];
        return;
    }
    const oo::PList routeInfo = oo::PListFrom([UNIVERSE routeFromSystem:system_id toSystem:target_system_id optimizedBy:ANA_mode]);
    const oo::PList* route = routeInfo.get<oo::PList::Array>("route");
    NSUInteger i;
    if (route == nullptr) {
        [self setInfoSystemID:system_id moveChart:YES];
        return;
    }
    for (i = 0; i < route->count(); i++) {
        if (route->at<int>(i) == info_system_id) {
            if (i > 0) {
                [self setInfoSystemID:route->at<unsigned int>(i - 1) moveChart:YES];
                return;
            }
            break;
        }
    }
    [self setInfoSystemID:system_id moveChart:YES];
    return;
}

- (void)homeInfoSystem
{
    [self setInfoSystemID:system_id moveChart:YES];
    return;
}

- (void)targetInfoSystem
{
    [self setInfoSystemID:target_system_id moveChart:YES];
    return;
}

- (BOOL)infoSystemOnRoute
{
    const oo::PList routeInfo = oo::PListFrom([UNIVERSE routeFromSystem:system_id toSystem:target_system_id optimizedBy:ANA_mode]);
    const oo::PList* route = routeInfo.get<oo::PList::Array>("route");
    NSUInteger i;
    if (route == nullptr) {
        return NO;
    }
    for (i = 0; i < route->count(); i++) {
        if (route->at<int>(i) == info_system_id) {
            return YES;
        }
    }
    return NO;
}

- (WormholeEntity*)wormhole
{
    return wormhole;
}

- (void)setWormhole:(WormholeEntity*)newWormhole
{
    [wormhole release];
    if (newWormhole != nil) {
        wormhole = [newWormhole retain];
    } else {
        wormhole = nil;
    }
}

- (NSDictionary*)commanderDataDictionary
{
    int i;

    NSMutableDictionary* result = [NSMutableDictionary dictionary];

    [result setObject:oo::NSStringOrNil(OoliteInfoString("CFBundleVersion")) forKey:@"written_by_version"];

    NSString* gal_id = [NSString stringWithFormat:@"%u", galaxy_number];
    NSString* sys_id = [NSString stringWithFormat:@"%d", system_id];
    NSString* tgt_id = [NSString stringWithFormat:@"%d", target_system_id];
    NSString* prv_id = [NSString stringWithFormat:@"%d", previous_system_id];

    // Variable requiredCargoSpace not suitable for Oolite as it currently stands: it retroactively changes a savegame cargo space.
    // unsigned 	passenger_space = [[OOEquipmentType equipmentTypeWithIdentifier:@"EQ_PASSENGER_BERTH"] requiredCargoSpace];
    // if (passenger_space == 0) passenger_space = PASSENGER_BERTH_SPACE;

    [result setObject:gal_id forKey:@"galaxy_id"];
    [result setObject:sys_id forKey:@"system_id"];
    [result setObject:tgt_id forKey:@"target_id"];
    [result setObject:prv_id forKey:@"previous_system_id"];
    [result setObject:[NSNumber numberWithFloat:saved_chart_zoom] forKey:@"chart_zoom"];
    [result setObject:[NSNumber numberWithInt:ANA_mode] forKey:@"chart_ana_mode"];
    [result setObject:[NSNumber numberWithInt:longRangeChartMode] forKey:@"chart_colour_mode"];

    if (found_system_id >= 0) {
        NSString* found_id = [NSString stringWithFormat:@"%d", found_system_id];
        [result setObject:found_id forKey:@"found_system_id"];
    }

    // Write the name of the current system. Useful for looking up saved game information and for overlapping systems.
    if (![UNIVERSE inInterstellarSpace]) {
        [result setObject:[UNIVERSE getSystemName:[self currentSystemID]] forKey:@"current_system_name"];
        OOGovernmentID government = oo::PListView([UNIVERSE currentSystemData]).get<int>(KEY_GOVERNMENT);
        OOTechLevelID techlevel = oo::PListView([UNIVERSE currentSystemData]).get<int>(KEY_TECHLEVEL);
        OOEconomyID economy = oo::PListView([UNIVERSE currentSystemData]).get<int>(KEY_ECONOMY);
        [result setObject:[NSNumber numberWithUnsignedShort:government] forKey:@"current_system_government"];
        [result setObject:[NSNumber numberWithUnsignedInteger:techlevel] forKey:@"current_system_techlevel"];
        [result setObject:[NSNumber numberWithUnsignedShort:economy] forKey:@"current_system_economy"];
    }

    [result setObject:[self commanderName] forKey:@"player_name"];
    [result setObject:[self lastsaveName] forKey:@"player_save_name"];
    [result setObject:[self shipUniqueName] forKey:@"ship_unique_name"];
    [result setObject:[self shipClassName] forKey:@"ship_class_name"];

    /*
            BUG: GNUstep truncates integer values to 32 bits when loading XML plists.
            Workaround: store credits as a double. 53 bits of precision ought to
            be good enough for anybody. Besides, we display credits with double
            precision anyway.
            -- Ahruman 2011-02-15
    */
    [result oo_setFloat:credits forKey:@"credits"];
    [result oo_setUnsignedInteger:fuel forKey:@"fuel"];

    [result oo_setInteger:galaxy_number forKey:@"galaxy_number"];

    [result oo_setBool:[self weaponsOnline] forKey:@"weapons_online"];

    if (forward_weapon_type != nil) {
        [result setObject:[forward_weapon_type identifier] forKey:@"forward_weapon"];
    }
    if (aft_weapon_type != nil) {
        [result setObject:[aft_weapon_type identifier] forKey:@"aft_weapon"];
    }
    if (port_weapon_type != nil) {
        [result setObject:[port_weapon_type identifier] forKey:@"port_weapon"];
    }
    if (starboard_weapon_type != nil) {
        [result setObject:[starboard_weapon_type identifier] forKey:@"starboard_weapon"];
    }
    [result setObject:[self serializeShipSubEntities] forKey:@"subentities_status"];
    if (hud != nil && [hud nonlinearScanner]) {
        [result oo_setFloat:[hud scannerZoom] forKey:@"ship_scanner_zoom"];
    }

    [result oo_setInteger:max_cargo + PASSENGER_BERTH_SPACE * max_passengers forKey:@"max_cargo"];

    [result setObject:[shipCommodityData savePlayerAmounts] forKey:@"shipCommodityData"];

    NSMutableArray* missileRoles = [NSMutableArray arrayWithCapacity:max_missiles];

    for (i = 0; i < (int)max_missiles; i++) {
        if (missile_entity[i]) {
            [missileRoles addObject:[missile_entity[i] primaryRole]];
        } else {
            [missileRoles addObject:@"NONE"];
        }
    }
    [result setObject:missileRoles forKey:@"missile_roles"];

    [result oo_setInteger:missiles forKey:@"missiles"];

    [result oo_setInteger:legalStatus forKey:@"legal_status"];
    [result oo_setInteger:market_rnd forKey:@"market_rnd"];
    [result oo_setInteger:ship_kills forKey:@"ship_kills"];

    // ship depreciation
    [result oo_setInteger:ship_trade_in_factor forKey:@"ship_trade_in_factor"];

    // mission variables
    if (mission_variables != nil) {
        [result setObject:[NSDictionary dictionaryWithDictionary:mission_variables] forKey:@"mission_variables"];
    }

    // communications log
    const std::vector<std::string>* log = [self cxx_commLog];
    if (log != nullptr)
        [result setObject:oo::NSArrayFromStrings(*log) forKey:@"comm_log"];

    [result oo_setUnsignedInteger:entity_personality forKey:@"entity_personality"];

    // extra equipment flags
    NSMutableDictionary* equipment = [NSMutableDictionary dictionary];
    NSEnumerator* eqEnum = nil;
    NSString* eqDesc = nil;
    for (eqEnum = [self equipmentEnumerator]; (eqDesc = [eqEnum nextObject]);) {
        [equipment oo_setInteger:[self countEquipmentItem:eqDesc] forKey:eqDesc];
    }
    if ([equipment count] != 0) {
        [result setObject:equipment forKey:@"extra_equipment"];
    }
    if (primedEquipment < eqScripts.size())
        [result setObject:oo::NSStringFrom(eqScripts[primedEquipment].first) forKey:@"primed_equipment"];

    [result setObject:[self fastEquipmentA] forKey:@"primed_equipment_a"];
    [result setObject:[self fastEquipmentB] forKey:@"primed_equipment_b"];

    // roles
    [result setObject:oo::NSArrayFromStrings(roleWeights) forKey:@"role_weights"];

    // role information
    [result setObject:oo::ObjectFromPList(oo::PList(roleWeightFlags)) forKey:@"role_weight_flags"];

    // role information
    [result setObject:oo::ObjectFromPList(SystemListPList(roleSystemList)) forKey:@"role_system_memory"];

    // reputation
    // initialise parcel reputations in dictionary if not set (the saved dictionary was the live one,
    // so it is built after this backfill)
    const auto reputationValue = [&](const std::string& key) {
        const auto it = reputation.find(key);
        return it != reputation.end() ? oo::PListGet<int>::from(&it->second, 0) : 0; // -oo_intForKey:
    };
    int pGood = reputationValue(oo::StdString(PARCEL_GOOD_KEY));
    int pBad = reputationValue(oo::StdString(PARCEL_BAD_KEY));
    int pUnknown = reputationValue(oo::StdString(PARCEL_UNKNOWN_KEY));
    if (pGood + pBad + pUnknown != MAX_CONTRACT_REP) {
        reputation[oo::StdString(PARCEL_GOOD_KEY)] = oo::PList::signedInteger(0);
        reputation[oo::StdString(PARCEL_BAD_KEY)] = oo::PList::signedInteger(0);
        reputation[oo::StdString(PARCEL_UNKNOWN_KEY)] = oo::PList::signedInteger(MAX_CONTRACT_REP);
    }
    [result setObject:oo::ObjectFromPList(oo::PList(reputation)) forKey:@"reputation"];

    // passengers
    [result oo_setInteger:max_passengers forKey:@"max_passengers"];
    [result setObject:oo::ObjectFromPList(oo::PList(passengers)) forKey:@"passengers"];
    [result setObject:oo::ObjectFromPList(oo::PList(passenger_record)) forKey:@"passenger_record"];

    // parcels
    [result setObject:oo::ObjectFromPList(oo::PList(parcels)) forKey:@"parcels"];
    [result setObject:oo::ObjectFromPList(oo::PList(parcel_record)) forKey:@"parcel_record"];

    // specialCargo
    if (specialCargo)
        [result setObject:oo::NSStringFrom(*specialCargo) forKey:@"special_cargo"];

    // contracts
    [result setObject:oo::ObjectFromPList(oo::PList(contracts)) forKey:@"contracts"];
    [result setObject:oo::ObjectFromPList(oo::PList(contract_record)) forKey:@"contract_record"];

    [result setObject:oo::ObjectFromPList(oo::PList(missionDestinations)) forKey:@"mission_destinations"];

    // shipyard
    [result setObject:oo::ObjectFromPList(oo::PList(shipyard_record)) forKey:@"shipyard_record"];

    // ship's clock
    [result setObject:[NSNumber numberWithDouble:ship_clock] forKey:@"ship_clock"];

    // speech
    [result setObject:[NSNumber numberWithInt:isSpeechOn] forKey:@"speech_on"];
#if OOLITE_ESPEAK
    [result setObject:[UNIVERSE voiceName:voice_no]
               forKey:@"speech_voice"];
    [result setObject:[NSNumber numberWithBool:voice_gender_m] forKey:@"speech_gender"];
#endif

    // docking clearance
    [result setObject:[NSNumber numberWithBool:[UNIVERSE dockingClearanceProtocolActive]] forKey:@"docking_clearance_protocol"];

    // base ship description
    [result setObject:[self shipDataKey] forKey:@"ship_desc"];
    [result setObject:oo::PListView([self shipInfoDictionary]).get<NSString*>(KEY_NAME) forKey:@"ship_name"];

    // custom view no.
    [result oo_setUnsignedInteger:_customViewIndex forKey:@"custom_view_index"];

    // escape pod rescue time
    [result oo_setFloat:[self escapePodRescueTime] forKey:@"escape_pod_rescue_time"];

    // local market for main station
    if ([[UNIVERSE station] localMarket])
        [result setObject:[[[UNIVERSE station] localMarket] saveStationAmounts] forKey:@"localMarket"];

    // Scenario restriction on OXZs
    [result setObject:[UNIVERSE useAddOns] forKey:@"scenario_restriction"];

    [result setObject:[[UNIVERSE systemManager] exportScriptedChanges] forKey:@"scripted_planetinfo_overrides"];

    // trumble information
    [result setObject:[self trumbleValue] forKey:@"trumbles"];

    // wormhole information
    oo::PList::Array wormholeDicts;
    wormholeDicts.reserve(scannedWormholes.size());
    for (const oo::ObjCRef<WormholeEntity*>& wh : scannedWormholes) {
        wormholeDicts.push_back([wh.get() getDict]);
    }
    [result setObject:oo::ObjectFromPList(oo::PList(std::move(wormholeDicts))) forKey:@"wormholes"];

    // docked station
    StationEntity* dockedStation = [self dockedStation];
    [result setObject:dockedStation != nil ? [dockedStation primaryRole] : (NSString*)@"" forKey:@"docked_station_role"];
    if (dockedStation) {
        HPVector dpos = [dockedStation position];
        [result setObject:ArrayFromHPVector(dpos) forKey:@"docked_station_position"];
    } else {
        [result setObject:[NSArray array] forKey:@"docked_station_position"];
    }
    [result setObject:[UNIVERSE getStationMarkets] forKey:@"station_markets"];

    // scenario information
    if (scenarioKey != nil) {
        [result setObject:scenarioKey forKey:@"scenario"];
    }

    // create checksum
    clear_checksum();
    // TODO: should checksum checks be removed?
    //	munge_checksum(galaxy_seed.a);	munge_checksum(galaxy_seed.b);	munge_checksum(galaxy_seed.c);
    //	munge_checksum(galaxy_seed.d);	munge_checksum(galaxy_seed.e);	munge_checksum(galaxy_seed.f);
    munge_checksum(galaxy_coordinates.x);
    munge_checksum(galaxy_coordinates.y);
    munge_checksum(credits);
    munge_checksum(fuel);
    munge_checksum(max_cargo);
    munge_checksum(missiles);
    munge_checksum(legalStatus);
    munge_checksum(market_rnd);
    munge_checksum(ship_kills);

    if (mission_variables != nil) {
        munge_checksum([[mission_variables description] length]);
    }
    if (equipment != nil) {
        munge_checksum([[equipment description] length]);
    }

    int final_checksum = munge_checksum([[self shipDataKey] length]);

    // set checksum
    [result oo_setInteger:final_checksum forKey:@"checksum"];

    return result;
}

- (BOOL)setCommanderDataFromDictionary:(NSDictionary*)dict
{
    // multi-function displays
    // must be reset before ship setup
    multiFunctionDisplayText.clear();

    multiFunctionDisplaySettings.clear();

    customDialSettings.clear();

    [[UNIVERSE gameView] resetTypedString];

    // Required keys
    if (oo::PListView(dict).get<NSString*>(@"ship_desc") == nil)
        return NO;
    // galaxy_seed is used is 1.80 or earlier
    if (oo::PListView(dict).get<NSString*>(@"galaxy_seed") == nil && oo::PListView(dict).get<NSString*>(@"galaxy_id") == nil)
        return NO;
    // galaxy_coordinates is used is 1.80 or earlier
    if (oo::PListView(dict).get<NSString*>(@"galaxy_coordinates") == nil && oo::PListView(dict).get<NSString*>(@"system_id") == nil)
        return NO;

    NSString* scenarioRestrict = oo::PListView(dict).get<NSString*>(@"scenario_restriction", nil);
    if (scenarioRestrict == nil) {
        // older save game - use the 'strict' key instead
        BOOL strict = oo::PListView(dict).get<bool>(@"strict", NO);
        if (strict) {
            scenarioRestrict = SCENARIO_OXP_DEFINITION_NONE;
        } else {
            scenarioRestrict = SCENARIO_OXP_DEFINITION_ALL;
        }
    }

    if (![UNIVERSE setUseAddOns:scenarioRestrict fromSaveGame:YES]) {
        return NO;
    }

    // base ship description
    [self setShipDataKey:oo::PListView(dict).get<NSString*>(@"ship_desc")];

    NSDictionary* shipDict = [[OOShipRegistry sharedRegistry] shipInfoForKey:[self shipDataKey]];
    if (shipDict == nil)
        return NO;
    if (![self setUpShipFromDictionary:shipDict])
        return NO;
    OO_LOG("fuelPrices", "Got \"{}\", fuel charge rate: {:.2f}", oo::DescriptionOf([self shipDataKey]), [self fuelChargeRate]);

    // ship depreciation
    ship_trade_in_factor = oo::PListView(dict).get<int>(@"ship_trade_in_factor", 95);

    // newer savegames use galaxy_id
    if (oo::PListView(dict).get<NSString*>(@"galaxy_id") != nil) {
        galaxy_number = oo::PListView(dict).get<NSUInteger>(@"galaxy_id");
        if (galaxy_number >= OO_GALAXIES_AVAILABLE) {
            return NO;
        }
        [UNIVERSE setGalaxyTo:galaxy_number andReinit:YES];

        system_id = oo::PListView(dict).get<int>(@"system_id");
        if (system_id < 0 || system_id >= OO_SYSTEMS_PER_GALAXY) {
            return NO;
        }

        [UNIVERSE setSystemTo:system_id];

        NSArray* coord_vals = ScanTokensFromString([[UNIVERSE systemManager] getProperty:@"coordinates" forSystem:system_id inGalaxy:galaxy_number]);
        galaxy_coordinates.x = oo::PListView(coord_vals).at<unsigned char>(0);
        galaxy_coordinates.y = oo::PListView(coord_vals).at<unsigned char>(1);
        chart_centre_coordinates = galaxy_coordinates;
        target_chart_centre = chart_centre_coordinates;
        cursor_coordinates = galaxy_coordinates;
        chart_zoom = oo::PListView(dict).get<float>(@"chart_zoom", 1.0);
        target_chart_zoom = chart_zoom;
        saved_chart_zoom = chart_zoom;
        ANA_mode = (OORouteType)oo::PListView(dict).get<int>(@"chart_ana_mode", OPTIMIZED_BY_NONE);
        longRangeChartMode = (OOLongRangeChartMode)oo::PListView(dict).get<int>(@"chart_colour_mode", OOLRC_MODE_SUNCOLOR);
        if (longRangeChartMode == OOLRC_MODE_UNKNOWN)
            longRangeChartMode = OOLRC_MODE_SUNCOLOR;

        target_system_id = oo::PListView(dict).get<int>(@"target_id", system_id);
        previous_system_id = oo::PListView(dict).get<int>(@"previous_system_id", system_id);
        info_system_id = target_system_id;
        coord_vals = ScanTokensFromString([[UNIVERSE systemManager] getProperty:@"coordinates" forSystem:target_system_id inGalaxy:galaxy_number]);
        cursor_coordinates.x = oo::PListView(coord_vals).at<unsigned char>(0);
        cursor_coordinates.y = oo::PListView(coord_vals).at<unsigned char>(1);

        chart_focus_coordinates = chart_centre_coordinates;
        target_chart_focus = chart_focus_coordinates;

        found_system_id = oo::PListView(dict).get<int>(@"found_system_id", -1);
    } else
    // compatibility for loading 1.80 savegames
    {
        galaxy_number = oo::PListView(dict).get<NSUInteger>(@"galaxy_number");

        [UNIVERSE setGalaxyTo:galaxy_number andReinit:YES];

        NSArray* coord_vals = ScanTokensFromString(oo::PListView(dict).get<NSString*>(@"galaxy_coordinates"));
        galaxy_coordinates.x = oo::PListView(coord_vals).at<unsigned char>(0);
        galaxy_coordinates.y = oo::PListView(coord_vals).at<unsigned char>(1);
        chart_centre_coordinates = galaxy_coordinates;
        target_chart_centre = chart_centre_coordinates;
        cursor_coordinates = galaxy_coordinates;
        chart_zoom = 1.0;
        target_chart_zoom = 1.0;
        saved_chart_zoom = 1.0;
        ANA_mode = OPTIMIZED_BY_NONE;

        NSString* keyStringValue = oo::PListView(dict).get<NSString*>(@"target_coordinates");

        if (keyStringValue != nil) {
            coord_vals = ScanTokensFromString(keyStringValue);
            cursor_coordinates.x = oo::PListView(coord_vals).at<unsigned char>(0);
            cursor_coordinates.y = oo::PListView(coord_vals).at<unsigned char>(1);
        }
        chart_focus_coordinates = chart_centre_coordinates;
        target_chart_focus = chart_focus_coordinates;

        // calculate system ID, target ID
        if ([dict objectForKey:@"current_system_name"]) {
            system_id = [UNIVERSE findSystemFromName:oo::PListView(dict).get<NSString*>(@"current_system_name")];
            if (system_id == -1)
                system_id = [UNIVERSE findSystemNumberAtCoords:galaxy_coordinates withGalaxy:galaxy_number includingHidden:YES];
        } else {
            // really old save games don't have system name saved
            // use coordinates instead - unreliable in zero-distance pairs.
            system_id = [UNIVERSE findSystemNumberAtCoords:galaxy_coordinates withGalaxy:galaxy_number includingHidden:YES];
        }
        // and current_system_name and target_system_name
        // were introduced at different times, too
        if ([dict objectForKey:@"target_system_name"]) {
            target_system_id = [UNIVERSE findSystemFromName:oo::PListView(dict).get<NSString*>(@"target_system_name")];
            if (target_system_id == -1)
                target_system_id = [UNIVERSE findSystemNumberAtCoords:cursor_coordinates withGalaxy:galaxy_number includingHidden:YES];
        } else {
            target_system_id = [UNIVERSE findSystemNumberAtCoords:cursor_coordinates withGalaxy:galaxy_number includingHidden:YES];
        }
        info_system_id = target_system_id;
        found_system_id = -1;
    }

    NSString* cname = oo::PListView(dict).get<NSString*>(@"player_name", PLAYER_DEFAULT_NAME);
    [self setCommanderName:cname];
    [self setLastsaveName:oo::PListView(dict).get<NSString*>(@"player_save_name", cname)];

    [self setShipUniqueName:oo::PListView(dict).get<NSString*>(@"ship_unique_name", @"")];
    [self setShipClassName:oo::PListView(dict).get<NSString*>(@"ship_class_name", oo::PListView(shipDict).get<NSString*>(@"name"))];

    [shipCommodityData loadPlayerAmounts:oo::PListView(dict).get<NSArray*>(@"shipCommodityData")];

    // extra equipment flags
    [self removeAllEquipment];
    NSMutableDictionary* equipment = [NSMutableDictionary dictionaryWithDictionary:oo::PListView(dict).get<NSDictionary*>(@"extra_equipment")];

    // Equipment flags	(deprecated in favour of equipment dictionary, keep for compatibility)
    if (oo::PListView(dict).get<bool>(@"has_docking_computer"))
        [equipment oo_setInteger:1 forKey:@"EQ_DOCK_COMP"];
    if (oo::PListView(dict).get<bool>(@"has_galactic_hyperdrive"))
        [equipment oo_setInteger:1 forKey:@"EQ_GAL_DRIVE"];
    if (oo::PListView(dict).get<bool>(@"has_escape_pod"))
        [equipment oo_setInteger:1 forKey:@"EQ_ESCAPE_POD"];
    if (oo::PListView(dict).get<bool>(@"has_ecm"))
        [equipment oo_setInteger:1 forKey:@"EQ_ECM"];
    if (oo::PListView(dict).get<bool>(@"has_scoop"))
        [equipment oo_setInteger:1 forKey:@"EQ_FUEL_SCOOPS"];
    if (oo::PListView(dict).get<bool>(@"has_energy_bomb"))
        [equipment oo_setInteger:1 forKey:@"EQ_ENERGY_BOMB"];
    if (oo::PListView(dict).get<bool>(@"has_fuel_injection"))
        [equipment oo_setInteger:1 forKey:@"EQ_FUEL_INJECTION"];

    // Legacy energy unit type -> energy unit equipment item
    if (oo::PListView(dict).get<bool>(@"has_energy_unit") && [self installedEnergyUnitType] == ENERGY_UNIT_NONE) {
        OOEnergyUnitType eType = (OOEnergyUnitType)oo::PListView(dict).get<int>(@"energy_unit", ENERGY_UNIT_NORMAL);
        switch (eType) {
        // look for NEU first!
        case OLD_ENERGY_UNIT_NAVAL:
            [equipment oo_setInteger:1 forKey:@"EQ_NAVAL_ENERGY_UNIT"];
            break;

        case OLD_ENERGY_UNIT_NORMAL:
            [equipment oo_setInteger:1 forKey:@"EQ_ENERGY_UNIT"];
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
    if (oo::PListView(equipment).get<bool>(@"EQ_ENERGY_BOMB") && [OOEquipmentType equipmentTypeWithIdentifier:@"EQ_ENERGY_BOMB"] == nil) {
        energyBombCompensation = YES;
        [equipment removeObjectForKey:@"EQ_ENERGY_BOMB"];
    }

    eqScripts.clear();
    [self addEquipmentFromCollection:equipment];
    primedEquipment = [self eqScriptIndexForKey:oo::PListView(dict).get<NSString*>(@"primed_equipment")]; // if key not found primedEquipment is set to primed-none

    [self setFastEquipmentA:oo::PListView(dict).get<NSString*>(@"primed_equipment_a", @"EQ_CLOAKING_DEVICE")];
    [self setFastEquipmentB:oo::PListView(dict).get<NSString*>(@"primed_equipment_b", @"EQ_ENERGY_BOMB")]; // even though there isn't one, for compatibility.

    if ([self hasEquipmentItemProviding:@"EQ_ADVANCED_COMPASS"])
        compassMode = COMPASS_MODE_PLANET;
    else
        compassMode = COMPASS_MODE_BASIC;
    DESTROY(compassTarget);

    // speech
    isSpeechOn = (OOSpeechSettings)oo::PListView(dict).get<int>(@"speech_on");
#if OOLITE_ESPEAK
    voice_gender_m = oo::PListView(dict).get<bool>(@"speech_gender", YES);
    voice_no = [UNIVERSE setVoice:[UNIVERSE voiceNumber:oo::PListView(dict).get<NSString*>(@"speech_voice", nil)] withGenderM:voice_gender_m];
#endif

    // reputation
    const oo::PList savedReputation = oo::PListFrom([dict objectForKey:@"reputation"]);
    reputation = savedReputation.isDict() ? *savedReputation.getIf<oo::PList::Dict>() : oo::PList::Dict(); // -oo_dictionaryForKey:, empty if none
    [self normaliseReputation];

    // passengers and contracts

    max_passengers = oo::PListView(dict).get<int>(@"max_passengers", 0);
    const oo::PList savedPassengers = oo::PListFrom([dict objectForKey:@"passengers"]);
    passengers = savedPassengers.isArray() ? *savedPassengers.getIf<oo::PList::Array>() : oo::PList::Array(); // -oo_arrayForKey:, empty if none
    const oo::PList savedPassengerRecord = oo::PListFrom([dict objectForKey:@"passenger_record"]);
    passenger_record = savedPassengerRecord.isDict() ? *savedPassengerRecord.getIf<oo::PList::Dict>() : oo::PList::Dict();
    /* Note: contracts from older savegames will have ints in the commodity.
     * Need to fix this up */
    const oo::PList savedContracts = oo::PListFrom([dict objectForKey:@"contracts"]);
    contracts = savedContracts.isArray() ? *savedContracts.getIf<oo::PList::Array>() : oo::PList::Array(); // -oo_arrayForKey:, empty if none

    // iterate downwards; lets us remove invalid ones as we go
    for (NSInteger i = (NSInteger)contracts.size() - 1; i >= 0; i--) {
        oo::PList contractInfo = contracts[i].isDict() ? contracts[i] : oo::PList(oo::PList::Dict());
        const oo::PList* cargoType = contractInfo.find(oo::StdString(CARGO_KEY_TYPE));
        // if the trade good ID is an int
        if (cargoType != nullptr && cargoType->isNumber()) {
            // look it up, and replace with a string
            NSUInteger legacy_type = contractInfo.get<NSUInteger>(oo::StdString(CARGO_KEY_TYPE));
            (*contractInfo.getIf<oo::PList::Dict>())[oo::StdString(CARGO_KEY_TYPE)] = oo::PList(oo::StdString([OOCommodities legacyCommodityType:legacy_type]));
            contracts[i] = std::move(contractInfo);
        } else {
            // -oo_stringForKey: (nil when absent)
            const oo::PList* typeValue = contractInfo.find(oo::StdString(CARGO_KEY_TYPE));
            const std::optional<std::string> new_type = (typeValue != nullptr && typeValue->isString()) ? std::optional<std::string>(*typeValue->getIf<std::string>()) : std::nullopt;
            // check that that the type still exists
            if (![[UNIVERSE commodities] goodDefined:oo::NSStringOrNil(new_type)]) {
                OO_LOG("setCommanderDataFromDictionary.warning.contract", "Cargo contract to deliver {} could not be loaded from the saved game, as the commodity is no longer defined", new_type.value_or("(null)"));
                contracts.erase(contracts.begin() + i);
            }
        }
    }

    const oo::PList savedContractRecord = oo::PListFrom([dict objectForKey:@"contract_record"]);
    contract_record = savedContractRecord.isDict() ? *savedContractRecord.getIf<oo::PList::Dict>() : oo::PList::Dict();
    const oo::PList savedParcels = oo::PListFrom([dict objectForKey:@"parcels"]);
    parcels = savedParcels.isArray() ? *savedParcels.getIf<oo::PList::Array>() : oo::PList::Array(); // -oo_arrayForKey:, empty if none
    const oo::PList savedParcelRecord = oo::PListFrom([dict objectForKey:@"parcel_record"]);
    parcel_record = savedParcelRecord.isDict() ? *savedParcelRecord.getIf<oo::PList::Dict>() : oo::PList::Dict();

    // specialCargo
    //  a string (or a number, as text), else none: as -oo_stringForKey: read it
    const oo::PList savedSpecialCargo = oo::PListFrom([dict objectForKey:@"special_cargo"]);
    specialCargo = (savedSpecialCargo.isString() || savedSpecialCargo.isNumber()) ? std::optional<std::string>(oo::PListGet<std::string>::from(&savedSpecialCargo, std::string())) : std::nullopt;

    // mission destinations
    const oo::PList legacyDestinations = oo::PListFrom([dict objectForKey:@"missionDestinations"]); // used only if an array

    const oo::PList newDestinations = oo::PListFrom([dict objectForKey:@"mission_destinations"]); // used only if a dictionary
    [self initialiseMissionDestinations:newDestinations andLegacy:legacyDestinations];

    // shipyard
    const oo::PList savedShipyardRecord = oo::PListFrom([dict objectForKey:@"shipyard_record"]);
    shipyard_record = savedShipyardRecord.isDict() ? *savedShipyardRecord.getIf<oo::PList::Dict>() : oo::PList::Dict(); // -oo_dictionaryForKey:, empty if none

    // Normalize cargo capacity
    unsigned original_hold_size = [UNIVERSE maxCargoForShip:[self shipDataKey]];
    // Not Suitable For Oolite
    // unsigned 	passenger_space = [[OOEquipmentType equipmentTypeWithIdentifier:@"EQ_PASSENGER_BERTH"] requiredCargoSpace];
    // if (passenger_space == 0) passenger_space = PASSENGER_BERTH_SPACE;

    max_cargo = oo::PListView(dict).get<unsigned int>(@"max_cargo", max_cargo);
    if (max_cargo > original_hold_size)
        [self addEquipmentItem:@"EQ_CARGO_BAY" inContext:@"loading"];
    max_cargo = original_hold_size + ([self hasExpandedCargoBay] ? extra_cargo : 0);
    if (max_cargo < max_passengers * PASSENGER_BERTH_SPACE) {
        // Something went wrong. Possibly the save file was hacked to contain more passenger cabins than the available cargo space would allow - Nikos 20110731
        unsigned originalMaxPassengers = max_passengers;
        max_passengers = (unsigned)(max_cargo / PASSENGER_BERTH_SPACE);
        OO_LOG_WARN("setCommanderDataFromDictionary.inconsistency.max_passengers", "player ship {} had max_passengers set to a value requiring more cargo space than currently available ({}). Setting max_passengers to maximum possible value ({}).", oo::DescriptionOf([self name]), static_cast<unsigned>(originalMaxPassengers), static_cast<unsigned>(max_passengers));
    }
    max_cargo -= max_passengers * PASSENGER_BERTH_SPACE;

    // Do we have extra passengers?
    if (passengers.size() > max_passengers) {
        OO_LOG_WARN("setCommanderDataFromDictionary.inconsistency.passengers", "player ship {} had more passengers ({}) than passenger berths ({}). Removing extra passengers.", oo::DescriptionOf([self name]), passengers.size(), static_cast<unsigned>(max_passengers));
        for (NSInteger i = (NSInteger)passengers.size() - 1; i >= max_passengers; i--) {
            const oo::PList* passengerName = passengers[i].find(oo::StdString(PASSENGER_KEY_NAME));
            if (passengerName != nullptr && (passengerName->isString() || passengerName->isNumber()))
                passenger_record.erase(passengers[i].get<std::string>(oo::StdString(PASSENGER_KEY_NAME))); // -oo_stringForKey:
            passengers.erase(passengers.begin() + i);
        }
    }

    // too much cargo?
    NSInteger excessCargo = (NSInteger)[self cargoQuantityOnBoard] - (NSInteger)[self maxAvailableCargoSpace];
    if (excessCargo > 0) {
        OO_LOG_WARN("setCommanderDataFromDictionary.inconsistency.cargo", "player ship {} had more cargo ({}) than it can hold ({}). Removing extra cargo.", oo::DescriptionOf([self name]), [self cargoQuantityOnBoard], static_cast<unsigned>([self maxAvailableCargoSpace]));

        OOCommodityType type;
        OOMassUnit units;
        OOCargoQuantity oldAmount, toRemove;

        OOCargoQuantity remainingExcess = (OOCargoQuantity)excessCargo;

        // manifest always contains entries for all 17 commodities, even if their quantity is 0.
        foreach (type, [shipCommodityData goods]) {
            units = [shipCommodityData massUnitForGood:type];

            oldAmount = [shipCommodityData quantityForGood:type];
            BOOL roundedTon = (units != UNITS_TONS) && ((units == UNITS_KILOGRAMS && oldAmount > MAX_KILOGRAMS_IN_SAFE) || (units == UNITS_GRAMS && oldAmount > MAX_GRAMS_IN_SAFE));
            if (roundedTon || (units == UNITS_TONS && oldAmount > 0)) {
                // let's remove stuff
                OOCargoQuantity partAmount = oldAmount;
                toRemove = 0;
                while (remainingExcess > 0 && partAmount > 0) {
                    if (EXPECT_NOT(roundedTon && ((units == UNITS_KILOGRAMS && partAmount > MAX_KILOGRAMS_IN_SAFE) || (units == UNITS_GRAMS && partAmount > MAX_GRAMS_IN_SAFE)))) {
                        toRemove += (units == UNITS_KILOGRAMS) ? (partAmount > (KILOGRAMS_PER_POD + MAX_KILOGRAMS_IN_SAFE) ? KILOGRAMS_PER_POD : partAmount - MAX_KILOGRAMS_IN_SAFE)
                                                               : (partAmount > (GRAMS_PER_POD + MAX_GRAMS_IN_SAFE) ? GRAMS_PER_POD : partAmount - MAX_GRAMS_IN_SAFE);
                        partAmount = oldAmount - toRemove;
                        remainingExcess--;
                    } else if (!roundedTon) {
                        toRemove++;
                        partAmount--;
                        remainingExcess--;
                    } else {
                        partAmount = 0;
                    }
                }
                [shipCommodityData removeQuantity:toRemove forGood:type];
            }
        }
    }

    credits = OODeciCreditsFromObject([dict objectForKey:@"credits"]);

    fuel = oo::PListView(dict).get<unsigned int>(@"fuel", fuel);
    galaxy_number = oo::PListView(dict).get<int>(@"galaxy_number");
    //
    NSDictionary* shipyard_info = [[OOShipRegistry sharedRegistry] shipyardInfoForKey:[self shipDataKey]];
    OOWeaponFacingSet available_facings = oo::PListView(shipyard_info).get<unsigned int>(KEY_WEAPON_FACINGS, [self weaponFacings]);

    if (available_facings & WEAPON_FACING_FORWARD)
        forward_weapon_type = OOWeaponTypeFromEquipmentIdentifierLegacy(oo::PListView(dict).get<NSString*>(@"forward_weapon"));
    else
        forward_weapon_type = OOWeaponTypeFromEquipmentIdentifierSloppy(@"EQ_WEAPON_NONE");

    if (available_facings & WEAPON_FACING_AFT)
        aft_weapon_type = OOWeaponTypeFromEquipmentIdentifierLegacy(oo::PListView(dict).get<NSString*>(@"aft_weapon"));
    else
        aft_weapon_type = OOWeaponTypeFromEquipmentIdentifierSloppy(@"EQ_WEAPON_NONE");

    if (available_facings & WEAPON_FACING_PORT)
        port_weapon_type = OOWeaponTypeFromEquipmentIdentifierLegacy(oo::PListView(dict).get<NSString*>(@"port_weapon"));
    else
        port_weapon_type = OOWeaponTypeFromEquipmentIdentifierSloppy(@"EQ_WEAPON_NONE");

    if (available_facings & WEAPON_FACING_STARBOARD)
        starboard_weapon_type = OOWeaponTypeFromEquipmentIdentifierLegacy(oo::PListView(dict).get<NSString*>(@"starboard_weapon"));
    else
        starboard_weapon_type = OOWeaponTypeFromEquipmentIdentifierSloppy(@"EQ_WEAPON_NONE");

    [self setWeaponDataFromType:forward_weapon_type];

    if (hud != nil && [hud nonlinearScanner]) {
        [hud setScannerZoom:oo::PListView(dict).get<float>(@"ship_scanner_zoom", 1.0)];
    }

    weapons_online = oo::PListView(dict).get<bool>(@"weapons_online", YES);

    legalStatus = oo::PListView(dict).get<int>(@"legal_status");
    market_rnd = oo::PListView(dict).get<int>(@"market_rnd");
    ship_kills = oo::PListView(dict).get<int>(@"ship_kills");

    ship_clock = oo::PListView(dict).get<double>(@"ship_clock", PLAYER_SHIP_CLOCK_START);
    fps_check_time = ship_clock;

    escape_pod_rescue_time = oo::PListView(dict).get<double>(@"escape_pod_rescue_time", 0.0);

    // role weights
    const oo::PList savedRoles = oo::PListFrom([dict objectForKey:@"role_weights"]);
    NSUInteger rc = [self maxPlayerRoles];
    roleWeights.clear();
    if (!savedRoles.isArray()) {
        roleWeights.assign(rc, "player-unknown");
    } else {
        for (size_t roleIndex = 0; roleIndex < savedRoles.count(); roleIndex++) {
            // the roles are strings: anything else is dropped
            if (const std::string* role = savedRoles.at(roleIndex)->getIf<std::string>())
                roleWeights.push_back(*role);
        }
        if (roleWeights.size() > rc) {
            roleWeights.resize(rc);
        }
    }

    const oo::PList savedFlags = oo::PListFrom([dict objectForKey:@"role_weight_flags"]);
    roleWeightFlags = savedFlags.isDict() ? *savedFlags.getIf<oo::PList::Dict>() : oo::PList::Dict();

    const oo::PList savedSystems = oo::PListFrom([dict objectForKey:@"role_system_memory"]);
    roleSystemList.clear();
    for (size_t systemIndex = 0; savedSystems.isArray() && systemIndex < savedSystems.count(); systemIndex++) {
        roleSystemList.push_back(savedSystems.at<int>(systemIndex)); // -intValue
    }

    // mission_variables
    [mission_variables release];
    mission_variables = [oo::PListView(dict).get<NSDictionary*>(@"mission_variables") mutableCopy];
    if (mission_variables == nil)
        mission_variables = [[NSMutableDictionary alloc] init];

    // persistant UNIVERSE info
    NSDictionary* planetInfoOverrides = oo::PListView(dict).get<NSDictionary*>(@"scripted_planetinfo_overrides");
    if (planetInfoOverrides != nil) {
        [[UNIVERSE systemManager] importScriptedChanges:planetInfoOverrides];
    } else {
        // no scripted overrides? What about 1.80-style local overrides?
        planetInfoOverrides = oo::PListView(dict).get<NSDictionary*>(@"local_planetinfo_overrides");
        if (planetInfoOverrides != nil) {
            [[UNIVERSE systemManager] importLegacyScriptedChanges:planetInfoOverrides];
        }
    }

    // communications log
    commLog.clear();
    commLog.reserve(kCommLogTrimThreshold);

    const oo::PList savedCommLog = oo::PListFrom([dict objectForKey:@"comm_log"]);
    const std::size_t commCount = savedCommLog.isArray() ? savedCommLog.count() : 0; // oo_arrayForKey:
    for (std::size_t i = 0; i < commCount; i++) {
        [UNIVERSE addCommsMessage:oo::ObjectFromPList(*savedCommLog.at(i)) forCount:0 andShowComms:NO logOnly:YES];
    }

    /*	entity_personality for scripts and shaders. If undefined, we fall back
            to old behaviour of using a random value each time game is loaded (set
            up in -setUp). Saving of entity_personality was added in 1.74.
            -- Ahruman 2009-09-13
    */
    entity_personality = oo::PListView(dict).get<unsigned short>(@"entity_personality", entity_personality);

    // set up missiles
    [self setActiveMissile:0];
    for (NSUInteger i = 0; i < PLAYER_MAX_MISSILES; i++) {
        [missile_entity[i] release];
        missile_entity[i] = nil;
    }
    NSArray* missileRoles = oo::PListView(dict).get<NSArray*>(@"missile_roles");
    if (missileRoles != nil) {
        unsigned missileCount = 0;
        for (NSUInteger roleIndex = 0; roleIndex < [missileRoles count] && missileCount < max_missiles; roleIndex++) {
            NSString* missile_desc = oo::PListView(missileRoles).at<NSString*>(roleIndex);
            if (missile_desc != nil && ![missile_desc isEqualToString:@"NONE"]) {
                ShipEntity* amiss = [UNIVERSE newShipWithRole:missile_desc];
                if (amiss) {
                    missile_list[missileCount] = [OOEquipmentType equipmentTypeWithIdentifier:missile_desc];
                    missile_entity[missileCount] = amiss; // retain count = 1
                    missileCount++;
                } else {
                    OO_LOG_WARN("load.failed.missileNotFound", "couldn't find missile with role '{}' in [PlayerEntity setCommanderDataFromDictionary:], missile entry discarded.", oo::DescriptionOf(missile_desc));
                }
            }
            missiles = missileCount;
        }
    } else // no missile_roles
    {
        for (NSUInteger i = 0; i < missiles; i++) {
            missile_list[i] = [OOEquipmentType equipmentTypeWithIdentifier:@"EQ_MISSILE"];
            missile_entity[i] = [UNIVERSE newShipWithRole:@"EQ_MISSILE"]; // retain count = 1 - should be okay as long as we keep a missile with this role
                                                                          // in the base package.
        }
    }

    if (energyBombCompensation) {
        /*
                Compensate energy bomb with either a QC mine or the cost of an
                energy bomb (900 credits). This must be done after missiles are
                set up.
        */
        if ([self mountMissileWithRole:@"EQ_QC_MINE"]) {
            OO_LOG("load.upgrade.replacedEnergyBomb", "{}", "Replaced legacy energy bomb with Quirium cascade mine.");
        } else {
            credits += 9000;
            OO_LOG("load.upgrade.replacedEnergyBomb", "{}", "Compensated legacy energy bomb with 900 credits.");
        }
    }

    [self setActiveMissile:0];

    [self setHeatInsulation:1.0];

    max_forward_shield = BASELINE_SHIELD_LEVEL;
    max_aft_shield = BASELINE_SHIELD_LEVEL;

    forward_shield_recharge_rate = 2.0;
    aft_shield_recharge_rate = 2.0;

    forward_shield = [self maxForwardShieldLevel];
    aft_shield = [self maxAftShieldLevel];

    // used to get current_system and target_system here,
    // but stores the ID in the save file instead

    // restore subentities status
    [self deserializeShipSubEntitiesFrom:oo::PListView(dict).get<NSString*>(@"subentities_status")];

    // wormholes
    const oo::PList whArray = oo::PListFrom([dict objectForKey:@"wormholes"]);
    scannedWormholes.clear();
    const oo::PList::Array* whList = whArray.getIf<oo::PList::Array>();
    if (whList != nullptr)
        scannedWormholes.reserve(whList->size());
    for (const oo::PList& whCurrDict : (whList != nullptr) ? *whList : oo::PList::Array()) {
        WormholeEntity* wh = [[WormholeEntity alloc] initWithDict:whCurrDict];
        scannedWormholes.push_back(oo::ObjCRef<WormholeEntity*>(wh)); // (the +1 from +alloc is still never released, as before)
        /* TODO - add to Universe if the wormhole hasn't expired yet; but in this case
         * we need to save/load position and mass as well, which we currently
         * don't
        if (equal_seeds([wh origin], system_seed))
        {
                [UNIVERSE addEntity:wh];
        }
        */
    }

    // custom view no.
    if (!_customViews.empty()) // (an empty custom_views array divided by zero before)
        _customViewIndex = oo::PListView(dict).get<unsigned int>(@"custom_view_index") % _customViews.size();

    // docking clearance protocol
    [UNIVERSE setDockingClearanceProtocolActive:oo::PListView(dict).get<bool>(@"docking_clearance_protocol", NO)];

    // trumble information
    [self setUpTrumbles];
    [self setTrumbleValueFrom:[dict objectForKey:@"trumbles"]]; // if it doesn't exist we'll check user-defaults

    return YES;
}

/////////////////////////////////////////////////////////

/*	Nasty initialization mechanism:
        PlayerEntity is alloced and inited on demand by +sharedPlayer. This
        initialization doesn't actually set anything up -- apart from the
        assertion, it's like doing a bare alloc. -deferredInit does the work
        that -init "should" be doing. It assumes that -[ShipEntity initWithKey:
        definition:] will not return an object other than self.
        This is necessary because we need a pointer to the PlayerEntity early in
        startup, when ship data hasn't been loaded yet. In particular, we need
        a pointer to the player to set up the JavaScript environment, we need the
        JavaScript environment to set up OpenGL, and we need OpenGL set up to load
        ships.
*/
- (id)init
{
    NSAssert(gOOPlayer == nil, @"Expected only one PlayerEntity to exist at a time.");
    return [super initBypassForPlayer];
}

- (void)deferredInit
{
    NSAssert(gOOPlayer == self, @"Expected only one PlayerEntity to exist at a time.");
    NSAssert([super initWithKey:PLAYER_SHIP_DESC definition:[NSDictionary dictionary]] == self, @"PlayerEntity requires -[ShipEntity initWithKey:definition:] to return unmodified self.");

    maxFieldOfView = MAX_FOV;
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
    fov_delta = 2.0; // multiply by 2 each second
#endif

    compassMode = COMPASS_MODE_BASIC;

    afterburnerSoundLooping = NO;

    isPlayer = YES;

    [self setStatus:STATUS_START_GAME];

    int i;
    for (i = 0; i < PLAYER_MAX_MISSILES; i++) {
        missile_entity[i] = nil;
    }
    [self setUpAndConfirmOK:NO];

    save_path = nil;

    scoopsActive = NO;

    target_memory_index = 0;

    dockingReport.clear();
    [hud resetGuis:[NSDictionary dictionaryWithObjectsAndKeys:[NSDictionary dictionary], @"message_gui",
                       [NSDictionary dictionary], @"comm_log_gui", nil]];

    [self initControls];
}

- (BOOL)setUpAndConfirmOK:(BOOL)stopOnError
{
    return [self setUpAndConfirmOK:stopOnError saveGame:NO];
}

- (BOOL)setUpAndConfirmOK:(BOOL)stopOnError saveGame:(BOOL)saveGame
{
    fieldOfView = [[UNIVERSE gameView] fov:YES];
    unsigned i;

    showDemoShips = NO;
    show_info_flag = NO;
    marketSelectedCommodity.reset();

    // Reset JavaScript.
    [OOScriptTimer noteGameReset];
    [OOScriptTimer updateTimers];

    GameController* gc = [[UNIVERSE gameView] gameController];

    if (![gc inFullScreenMode] && stopOnError)
        [gc stopAnimationTimer]; // start of critical section

    if (EXPECT_NOT(![[OOJavaScriptEngine sharedEngine] reset] && stopOnError)) // always (try to) reset the engine, then find out if we need to stop.
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
        [self setDockedStation:nil]; // needed for STATUS_DEAD
        [self setStatus:STATUS_DEAD];
        OO_LOG("script.javascript.init.error", "{}", "Scheduling new JavaScript reset.");
        shot_time = kDeadResetTime - 0.02f; // schedule reinit 20 milliseconds from now.

        if (![gc inFullScreenMode])
            [gc startAnimationTimer]; // keep the game ticking over.
        return NO;
    }

    // end of critical section
    if (![gc inFullScreenMode] && stopOnError)
        [gc startAnimationTimer];

    // Load locale script before any regular scripts.
    [OOJSScript jsScriptFromFileNamed:@"oolite-locale-functions.js"
                           properties:nil];

    [[GameController sharedController] logProgress:DESC(@"loading-scripts")];

    [UNIVERSE setBlockJSPlayerShipProps:NO]; // full access to player.ship properties!
    DESTROY(worldScripts);
    DESTROY(worldScriptsRequiringTickle);
    DESTROY(commodityScripts);

#if OOLITE_WINDOWS
    if (saveGame) {
        [UNIVERSE preloadSounds];
        [self setUpSound];
        worldScripts = [[ResourceManager loadScripts] retain];
        [UNIVERSE loadConditionScripts];
        commodityScripts = [[NSMutableDictionary alloc] init];
    }
#else
    /* on OSes that allow safe deletion of open files, can use sounds
     * on the OXZ screen and other start screens */
    [UNIVERSE preloadSounds];
    [self setUpSound];
    if (saveGame) {
        worldScripts = [[ResourceManager loadScripts] retain];
        [UNIVERSE loadConditionScripts];
        commodityScripts = [[NSMutableDictionary alloc] init];
    }
#endif

    // make sure extraGuiScreenKeys is clear
    extraGuiScreenKeys.clear();

    [[GameController sharedController] logProgress:OOExpandKeyRandomized(@"loading-miscellany")];

    // if there is cargo remaining from previously (e.g. a game restart), remove it
    if ([self cargoList] != nil) {
        [self removeAllCargo:YES]; // force removal of cargo
    }

    [self setShipDataKey:PLAYER_SHIP_DESC];
    ship_trade_in_factor = 95;

    // reset HUD & default commlog behaviour
    [UNIVERSE setAutoCommLog:YES];
    [UNIVERSE setPermanentCommLog:NO];

    multiFunctionDisplayText.clear();

    multiFunctionDisplaySettings.clear();

    customDialSettings.clear();

    [self cxx_switchHudTo:"hud.plist"];
    scanner_zoom_rate = 0.0f;
    longRangeChartMode = OOLRC_MODE_SUNCOLOR;

    [mission_variables release];
    mission_variables = [[NSMutableDictionary alloc] init];

    [localVariables release];
    localVariables = [[NSMutableDictionary alloc] init];

    [self setScriptTarget:nil];
    [self resetMissionChoice];
    [[UNIVERSE gameView] resetTypedString];
    found_system_id = -1;

    reputation = oo::PList::Dict {
        { oo::StdString(CONTRACTS_GOOD_KEY), oo::PList::signedInteger(0) },
        { oo::StdString(CONTRACTS_BAD_KEY), oo::PList::signedInteger(0) },
        { oo::StdString(CONTRACTS_UNKNOWN_KEY), oo::PList::signedInteger(MAX_CONTRACT_REP) },
        { oo::StdString(PASSAGE_GOOD_KEY), oo::PList::signedInteger(0) },
        { oo::StdString(PASSAGE_BAD_KEY), oo::PList::signedInteger(0) },
        { oo::StdString(PASSAGE_UNKNOWN_KEY), oo::PList::signedInteger(MAX_CONTRACT_REP) },
        { oo::StdString(PARCEL_GOOD_KEY), oo::PList::signedInteger(0) },
        { oo::StdString(PARCEL_BAD_KEY), oo::PList::signedInteger(0) },
        { oo::StdString(PARCEL_UNKNOWN_KEY), oo::PList::signedInteger(MAX_CONTRACT_REP) },
    };

    roleWeights.assign(8, "player-unknown");
    roleWeightFlags.clear();

    roleSystemList.clear();

    energy = 256;
    weapon_temp = 0.0f;
    forward_weapon_temp = 0.0f;
    aft_weapon_temp = 0.0f;
    port_weapon_temp = 0.0f;
    starboard_weapon_temp = 0.0f;
    lastShot.clear();
    forward_shot_time = INITIAL_SHOT_TIME;
    aft_shot_time = INITIAL_SHOT_TIME;
    port_shot_time = INITIAL_SHOT_TIME;
    starboard_shot_time = INITIAL_SHOT_TIME;
    ship_temperature = 60.0f;
    alertFlags = 0;
    hyperspeed_engaged = NO;
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
    [self clearTargetMemory]; // also does first-time initialisation

    [self setMissionOverlayDescriptor:nil];
    [self setMissionBackgroundDescriptor:nil];
    [self setMissionBackgroundSpecial:nil];
    [self setEquipScreenBackgroundDescriptor:nil];
    marketOffset = 0;
    marketSelectedCommodity.reset();

    script_time = 0.0;
    script_time_check = SCRIPT_TIMER_INTERVAL;
    script_time_interval = SCRIPT_TIMER_INTERVAL;

    NSCalendarDate* nowDate = [NSCalendarDate calendarDate];
    ship_clock = PLAYER_SHIP_CLOCK_START;
    ship_clock += [nowDate hourOfDay] * 3600.0;
    ship_clock += [nowDate minuteOfHour] * 60.0;
    ship_clock += [nowDate secondOfMinute];
    fps_check_time = ship_clock;
    ship_clock_adjust = 0.0;
    escape_pod_rescue_time = 0.0;

    isSpeechOn = OOSPEECHSETTINGS_OFF;
#if OOLITE_ESPEAK
    voice_gender_m = YES;
    voice_no = [UNIVERSE setVoice:-1 withGenderM:voice_gender_m];
#endif

    _customViews.clear();
    _customViewIndex = 0;

    mouse_control_on = NO;

    // player commander data
    // Most of this is probably also set more than once

    [self setCommanderName:PLAYER_DEFAULT_NAME];
    const oo::PList savedName = oo::Defaults::standard().object("last_savename");
    if (const std::string* savedLastsaveName = savedName.getIf<std::string>()) {
        _lastsaveName = *savedLastsaveName;
    }

    galaxy_coordinates = NSMakePoint(0x14, 0xAD); // 20,173

    credits = 1000;
    fuel = PLAYER_MAX_FUEL;
    fuel_accumulator = 0.0f;
    fuel_leak_rate = 0.0f;

    galaxy_number = 0;
    // will load real weapon data later
    forward_weapon_type = nil;
    aft_weapon_type = nil;
    port_weapon_type = nil;
    starboard_weapon_type = nil;
    scannerRange = (float)SCANNER_MAX_RANGE;

    weapons_online = YES;

    ecm_in_operation = NO;
    last_ecm_time = [UNIVERSE getTime];
    compassMode = COMPASS_MODE_BASIC;
    ident_engaged = NO;

    max_cargo = 20; // will be reset later
    marketFilterMode = MARKET_FILTER_MODE_OFF;

    DESTROY(shipCommodityData);
    shipCommodityData = [[[UNIVERSE commodities] generateManifestForPlayer] retain];

    // set up missiles
    missiles = PLAYER_STARTING_MISSILES;
    max_missiles = PLAYER_STARTING_MAX_MISSILES;

    eqScripts.clear();
    primedEquipment = 0;
    [self setFastEquipmentA:@"EQ_CLOAKING_DEVICE"];
    [self setFastEquipmentB:@"EQ_ENERGY_BOMB"]; // for compatibility purposes

    [self setActiveMissile:0];
    for (i = 0; i < missiles; i++) {
        [missile_entity[i] release];
        missile_entity[i] = nil;
    }
    [self safeAllMissiles];

    [self clearSubEntities];

    legalStatus = 0;

    market_rnd = 0;
    ship_kills = 0;
    chart_centre_coordinates = galaxy_coordinates;
    target_chart_centre = chart_centre_coordinates;
    cursor_coordinates = galaxy_coordinates;
    chart_focus_coordinates = cursor_coordinates;
    target_chart_focus = chart_focus_coordinates;
    chart_zoom = 1.0;
    target_chart_zoom = 1.0;
    saved_chart_zoom = 1.0;
    ANA_mode = OPTIMIZED_BY_NONE;

    scripted_misjump = NO;
    _scriptedMisjumpRange = 0.5;
    scoopOverride = NO;

    max_forward_shield = BASELINE_SHIELD_LEVEL;
    max_aft_shield = BASELINE_SHIELD_LEVEL;

    forward_shield_recharge_rate = 2.0;
    aft_shield_recharge_rate = 2.0;

    forward_shield = [self maxForwardShieldLevel];
    aft_shield = [self maxAftShieldLevel];

    scanClass = CLASS_PLAYER;

    [UNIVERSE clearGUIs];

    dockingClearanceStatus = DOCKING_CLEARANCE_STATUS_GRANTED;
    targetDockStation = nil;

    [self setDockedStation:[UNIVERSE station]];

    commLog.clear();

    specialCargo.reset();

    // views
    forwardViewOffset = kZeroVector;
    aftViewOffset = kZeroVector;
    portViewOffset = kZeroVector;
    starboardViewOffset = kZeroVector;
    customViewOffset = kZeroVector;

    currentWeaponFacing = WEAPON_FACING_FORWARD;
    [self currentWeaponStats];

    [save_path autorelease];
    save_path = nil;

    scannedWormholes.clear();

    [self setUpTrumbles];

    suppressTargetLost = NO;

    scoopsActive = NO;

    dockingReport.clear();

    [shipAI release];
    shipAI = [[AI alloc] initWithStateMachine:PLAYER_DOCKING_AI_NAME andState:@"GLOBAL"];
    [self resetAutopilotAI];

    lastScriptAlertCondition = [self alertCondition];

    entity_personality = ranrot_rand() & 0x7FFF;

    [self setSystemID:[UNIVERSE findSystemNumberAtCoords:[self galaxy_coordinates] withGalaxy:galaxy_number includingHidden:YES]];
    [UNIVERSE setGalaxyTo:galaxy_number];
    [UNIVERSE setSystemTo:system_id];

    [self setUpWeaponSounds];

    [self setGalacticHyperspaceBehaviourTo:oo::PListView([UNIVERSE globalSettings]).get<NSString*>(@"galactic_hyperspace_behaviour", @"BEHAVIOUR_STANDARD")];
    [self setGalacticHyperspaceFixedCoordsTo:oo::PListView([UNIVERSE globalSettings]).get<NSString*>(@"galactic_hyperspace_fixed_coords", @"96 96")];

    cloaking_device_active = NO;

    demoShip = nil;

    [[OOMusicController sharedController] justStop];
    [stickProfileScreen release];
    stickProfileScreen = [[StickProfileScreen alloc] init];
    return YES;
}

- (void)completeSetUp
{
    [self completeSetUpAndSetTarget:YES];
}

- (void)completeSetUpAndSetTarget:(BOOL)setTarget
{
    [OOSoundSource stopAll];

    [self setDockedStation:[UNIVERSE station]];
    [self setLastAegisLock:[UNIVERSE planet]];
    // only do this if we're not in strict mode, otherwise all previously saved OXP key/joystick defs will be wiped.
    if (![[UNIVERSE useAddOns] isEqualToString:SCENARIO_OXP_DEFINITION_NONE]) {
        [self validateCustomEquipActivationArray];
    }

    JSContext* context = OOJSAcquireContext();
    {
        const oo::PList startLimit = oo::Defaults::standard().object("start-script-limit-value");
        [self doWorldScriptEvent:OOJSID("startUp") inContext:context withArguments:NULL count:0 timeLimit:MAX(0.0, oo::PListGet<float>::from(startLimit.isNull() ? nullptr : &startLimit, kOOJSLongTimeLimit))];
    }
    OOJSRelinquishContext(context);
}

- (void)startUpComplete
{
    JSContext* context = OOJSAcquireContext();
    [self doWorldScriptEvent:OOJSID("startUpComplete") inContext:context withArguments:NULL count:0 timeLimit:kOOJSLongTimeLimit];
    OOJSRelinquishContext(context);
}

- (BOOL)setUpShipFromDictionary:(NSDictionary*)shipDict
{
    DESTROY(compassTarget);
    [UNIVERSE setBlockJSPlayerShipProps:NO]; // full access to player.ship properties!

    if (![super setUpFromDictionary:shipDict])
        return NO;

    cargo.clear();

    // Player-only settings.
    //
    // set control factors..
    roll_delta = 2.0f * max_flight_roll;
    pitch_delta = 2.0f * max_flight_pitch;
    yaw_delta = 2.0f * max_flight_yaw;

    energy = maxEnergy;
    // if (forward_weapon_type == WEAPON_NONE) [self setWeaponDataFromType:forward_weapon_type];
    scannerRange = (float)SCANNER_MAX_RANGE;

    [roleSet release];
    roleSet = nil;
    [self setPrimaryRole:@"player"];

    [self removeAllEquipment];
    [self addEquipmentFromCollection:[shipDict objectForKey:@"extra_equipment"]];

    [self resetHud];
    [hud setHidden:NO];

    // set up missiles
    // sanity check the number of missiles...
    if (max_missiles > PLAYER_MAX_MISSILES)
        max_missiles = PLAYER_MAX_MISSILES;
    if (missiles > max_missiles)
        missiles = max_missiles;
    // end sanity check

    unsigned i;
    for (i = 0; i < PLAYER_MAX_MISSILES; i++) {
        [missile_entity[i] release];
        missile_entity[i] = nil;
    }
    for (i = 0; i < missiles; i++) {
        missile_list[i] = [OOEquipmentType equipmentTypeWithIdentifier:@"EQ_MISSILE"];
        missile_entity[i] = [UNIVERSE newShipWithRole:@"EQ_MISSILE"]; // retain count = 1
    }

    DESTROY(_primaryTarget);
    [self safeAllMissiles];
    [self setActiveMissile:0];

    // set view offsets
    [self setDefaultViewOffsets];

    if (EXPECT(_scaleFactor == 1.0f)) {
        forwardViewOffset = oo::PListView(shipDict).get<Vector>(@"view_position_forward", forwardViewOffset);
        aftViewOffset = oo::PListView(shipDict).get<Vector>(@"view_position_aft", aftViewOffset);
        portViewOffset = oo::PListView(shipDict).get<Vector>(@"view_position_port", portViewOffset);
        starboardViewOffset = oo::PListView(shipDict).get<Vector>(@"view_position_starboard", starboardViewOffset);
    } else {
        forwardViewOffset = vector_multiply_scalar(oo::PListView(shipDict).get<Vector>(@"view_position_forward", forwardViewOffset), _scaleFactor);
        aftViewOffset = vector_multiply_scalar(oo::PListView(shipDict).get<Vector>(@"view_position_aft", aftViewOffset), _scaleFactor);
        portViewOffset = vector_multiply_scalar(oo::PListView(shipDict).get<Vector>(@"view_position_port", portViewOffset), _scaleFactor);
        starboardViewOffset = vector_multiply_scalar(oo::PListView(shipDict).get<Vector>(@"view_position_starboard", starboardViewOffset), _scaleFactor);
    }

    [self setDefaultCustomViews];

    const oo::PList customViews = oo::PListFrom([shipDict objectForKey:@"custom_views"]);
    if (customViews.isArray()) {
        _customViews = CustomViewsFrom(customViews);
        _customViewIndex = 0;
    }

    massLockable = oo::PListView(shipDict).get<bool>(@"mass_lockable", YES);

    // Load js script
    [script autorelease];
    NSDictionary* scriptProperties = [NSDictionary dictionaryWithObject:self forKey:@"ship"];
    script = [OOScript jsScriptFromFileNamed:oo::PListView(shipDict).get<NSString*>(@"script")
                                  properties:scriptProperties];
    if (script == nil) {
        // Do not switch to using a default value above; we want to use the default script if loading fails.
        script = [OOScript jsScriptFromFileNamed:@"oolite-default-player-script.js"
                                      properties:scriptProperties];
    }
    [script retain];

    return YES;
}

- (void)dealloc
{
    DESTROY(compassTarget);
    DESTROY(hud);

    DESTROY(worldScripts);
    DESTROY(worldScriptsRequiringTickle);
    DESTROY(commodityScripts);
    DESTROY(mission_variables);

    DESTROY(localVariables);

    DESTROY(shipCommodityData);

    DESTROY(save_path);
    DESTROY(scenarioKey);

    [self destroySound];

    DESTROY(wormhole);

    int i;
    for (i = 0; i < PLAYER_MAX_MISSILES; i++)
        DESTROY(missile_entity[i]);
    for (i = 0; i < PLAYER_MAX_TRUMBLES; i++)
        DESTROY(trumble[i]);

    [super dealloc];
}

- (NSUInteger)sessionID
{
    // The player ship always belongs to the current session.
    return [UNIVERSE sessionID];
}

- (void)warnAboutHostiles
{
    [self playHostileWarning];
}

- (BOOL)canCollide
{
    switch ([self status]) {
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

- (NSComparisonResult)compareZeroDistance:(Entity*)otherEntity
{
    return NSOrderedDescending; // always the most near
}

- (BOOL)validForAddToUniverse
{
    return YES;
}

- (GLfloat)lookingAtSunWithThresholdAngleCos:(GLfloat)thresholdAngleCos
{
    OOSunEntity* sun = [UNIVERSE sun];
    GLfloat measuredCos = 999.0f, measuredCosAbs;
    GLfloat sunBrightness = 0.0f;
    Vector relativePosition, unitRelativePosition;

    if (EXPECT_NOT(!sun))
        return 0.0f;

    // check if camera position is shadowed
    OOViewID vdir = [UNIVERSE viewDirection];
    unsigned i;
    unsigned ent_count = UNIVERSE->n_entities;
    Entity** uni_entities = UNIVERSE->sortedEntities; // grab the public sorted list
    for (i = 0; i < ent_count; i++) {
        if (uni_entities[i]->isSunlit) {
            if ([uni_entities[i] isPlanet] || ([uni_entities[i] isShip] && [uni_entities[i] isVisible])) {
                // the player ship can't shadow internal views
                if (EXPECT(vdir > VIEW_STARBOARD || ![uni_entities[i] isPlayer])) {
                    float shadow = 1.5f;
                    shadowAtPointOcclusionToValue([self viewpointPosition], 1.0f, uni_entities[i], sun, &shadow);
                    /* BUG: if the shadowing entity is not spherical, this gives over-shadowing. True elsewhere as well, but not so obvious there. */
                    if (shadow < 1) {
                        return 0.0f;
                    }
                }
            }
        }
    }

    relativePosition = HPVectorToVector(HPvector_subtract([self viewpointPosition], [sun position]));
    unitRelativePosition = vector_normal_or_zbasis(relativePosition);
    switch (vdir) {
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
    case VIEW_CUSTOM: {
        Vector relativeView = [self customViewForwardVector];
        Vector absoluteView = quaternion_rotate_vector(quaternion_conjugate([self orientation]), relativeView);
        measuredCos = -dot_product(unitRelativePosition, absoluteView);
    } break;

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
    if (thresholdAngleCos <= measuredCosAbs && measuredCosAbs <= 1.1f) // angle from viewpoint to sun <= desired threshold
    {
        sunBrightness = (measuredCos - thresholdAngleCos) / (1.0f - thresholdAngleCos);
        //		/* glare.debug */ raw brightness = %f,sunBrightness);
        if (sunBrightness < 0.0f)
            sunBrightness = 0.0f;
        else if (sunBrightness > 1.0f)
            sunBrightness = 1.0f;
    }
    //	/* glare.debug */ cos=%f, threshold = %f, brightness = %f,measuredCosAbs,thresholdAngleCos,sunBrightness);
    return sunBrightness * sunBrightness * sunBrightness;
}

- (GLfloat)insideAtmosphereFraction
{
    GLfloat insideAtmoFrac = 0.0f;

    if ([UNIVERSE airResistanceFactor] > 0.01) // player is inside planetary atmosphere
    {
        insideAtmoFrac = 1.0f - ([self dialAltitude] * (GLfloat)PLAYER_DIAL_MAX_ALTITUDE / (10.0f * (GLfloat)ATMOSPHERE_DEPTH));
    }

    return insideAtmoFrac;
}

#ifndef NDEBUG
#define STAGE_TRACKING_BEGIN                                 \
    {                                                        \
        const char* volatile updateStage = "initialisation"; \
        @try {
#define STAGE_TRACKING_END                                                                                                                                                                                                                                  \
    }                                                                                                                                                                                                                                                       \
    @catch (OOException * exception)                                                                                                                                                                                                                        \
    {                                                                                                                                                                                                                                                       \
        OO_LOG(cxx_kOOLogException, "***** Exception during [{}] in {} : {} : {} *****", static_cast<const char*>(updateStage), static_cast<const char*>(__PRETTY_FUNCTION__), [exception name], [exception reason]);                                       \
        @throw exception;                                                                                                                                                                                                                                   \
    }                                                                                                                                                                                                                                                       \
    @catch (OOFoundationException * exception)                                                                                                                                                                                                              \
    {                                                                                                                                                                                                                                                       \
        OO_LOG(cxx_kOOLogException, "***** Exception during [{}] in {} : {} : {} *****", static_cast<const char*>(updateStage), static_cast<const char*>(__PRETTY_FUNCTION__), oo::DescriptionOf([exception name]), oo::DescriptionOf([exception reason])); \
        @throw exception;                                                                                                                                                                                                                                   \
    }                                                                                                                                                                                                                                                       \
    }
#define UPDATE_STAGE(x)    \
    do {                   \
        updateStage = (x); \
    } while (0)
#else
#define STAGE_TRACKING_BEGIN {
#define STAGE_TRACKING_END }
#define UPDATE_STAGE(x) \
    do {                \
        (void)(x);      \
    } while (0);
#endif

- (void)update:(OOTimeDelta)delta_t
{
    STAGE_TRACKING_BEGIN

    UPDATE_STAGE("updateMovementFlags");
    [self updateMovementFlags];
    UPDATE_STAGE("updateAlertCondition");
    [self updateAlertCondition];
    UPDATE_STAGE("updateFuelScoops:");
    [self updateFuelScoops:delta_t];

    UPDATE_STAGE("updateClocks:");
    [self updateClocks:delta_t];

    // scripting
    UPDATE_STAGE("updateTimers");
    [OOScriptTimer updateTimers];
    UPDATE_STAGE("checkScriptsIfAppropriate");
    [self checkScriptsIfAppropriate];

    // deal with collisions
    UPDATE_STAGE("manageCollisions");
    [self manageCollisions];

    UPDATE_STAGE("pollControls:");
    [self pollControls:delta_t];

    UPDATE_STAGE("updateTrumbles:");
    [self updateTrumbles:delta_t];

    OOEntityStatus status = [self status];
    /* Validate that if the status is STATUS_START_GAME we're on one
     * of the few GUI screens which that makes sense for */
    if (EXPECT_NOT(status == STATUS_START_GAME && gui_screen != GUI_SCREEN_INTRO1 && gui_screen != GUI_SCREEN_SHIPLIBRARY && gui_screen != GUI_SCREEN_GAMEOPTIONS && gui_screen != GUI_SCREEN_STICKMAPPER && gui_screen != GUI_SCREEN_STICKPROFILE && gui_screen != GUI_SCREEN_NEWGAME && gui_screen != GUI_SCREEN_OXZMANAGER && gui_screen != GUI_SCREEN_LOAD && gui_screen != GUI_SCREEN_KEYBOARD && gui_screen != GUI_SCREEN_KEYBOARD_CONFIRMCLEAR && gui_screen != GUI_SCREEN_KEYBOARD_CONFIG && gui_screen != GUI_SCREEN_KEYBOARD_ENTRY && gui_screen != GUI_SCREEN_KEYBOARD_LAYOUT)) {
        // and if not, do a restart of the GUI
        UPDATE_STAGE("setGuiToIntroFirstGo:");
        [self setGuiToIntroFirstGo:YES]; // set up demo mode
    }

    if (status == STATUS_AUTOPILOT_ENGAGED || status == STATUS_ESCAPE_SEQUENCE) {
        UPDATE_STAGE("performAutopilotUpdates:");
        [self performAutopilotUpdates:delta_t];
    } else if (![self isDocked]) {
        UPDATE_STAGE("performInFlightUpdates:");
        [self performInFlightUpdates:delta_t];
    }

    /*	NOTE: status-contingent updates are not a switch since they can
            cascade when status changes.
    */
    if (status == STATUS_IN_FLIGHT) {
        UPDATE_STAGE("doBookkeeping:");
        [self doBookkeeping:delta_t];
    }
    if (status == STATUS_WITCHSPACE_COUNTDOWN) {
        UPDATE_STAGE("performWitchspaceCountdownUpdates:");
        [self performWitchspaceCountdownUpdates:delta_t];
    }
    if (status == STATUS_EXITING_WITCHSPACE) {
        UPDATE_STAGE("performWitchspaceExitUpdates:");
        [self performWitchspaceExitUpdates:delta_t];
    }
    if (status == STATUS_LAUNCHING) {
        UPDATE_STAGE("performLaunchingUpdates:");
        [self performLaunchingUpdates:delta_t];
    }
    if (status == STATUS_DOCKING) {
        UPDATE_STAGE("performDockingUpdates:");
        [self performDockingUpdates:delta_t];
    }
    if (status == STATUS_DEAD) {
        UPDATE_STAGE("performDeadUpdates:");
        [self performDeadUpdates:delta_t];
    }

    UPDATE_STAGE("updateWormholes");
    [self updateWormholes];

    STAGE_TRACKING_END
}

- (void)doBookkeeping:(double)delta_t
{
    STAGE_TRACKING_BEGIN

    double speed_delta = SHIP_THRUST_FACTOR * thrust;

    static BOOL gettingInterference = NO;

    OOSunEntity* sun = [UNIVERSE sun];
    double external_temp = 0;
    GLfloat air_friction = 0.0f;
    air_friction = 0.5f * [UNIVERSE airResistanceFactor];
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
    switch (currentWeaponFacing) {
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
    if ([self hasCloakingDevice] && cloaking_device_active) {
        UPDATE_STAGE("updating cloaking device");

        energy -= (float)delta_t * CLOAKING_DEVICE_ENERGY_RATE;
        if (energy < CLOAKING_DEVICE_MIN_ENERGY)
            [self deactivateCloakingDevice];
    }

    // military_jammer
    if ([self hasMilitaryJammer]) {
        UPDATE_STAGE("updating military jammer");

        if (military_jammer_active) {
            energy -= (float)delta_t * MILITARY_JAMMER_ENERGY_RATE;
            if (energy < MILITARY_JAMMER_MIN_ENERGY)
                military_jammer_active = NO;
        } else {
            if (energy > 1.5 * MILITARY_JAMMER_MIN_ENERGY)
                military_jammer_active = YES;
        }
    }

    // ecm
    if (ecm_in_operation) {
        UPDATE_STAGE("updating ECM");

        if (energy > 0.0)
            energy -= (float)(ECM_ENERGY_DRAIN_FACTOR * delta_t); // drain energy because of the ECM
        else {
            ecm_in_operation = NO;
            [UNIVERSE addMessage:DESC(@"ecm-out-of-juice") forCount:3.0];
        }
        if ([UNIVERSE getTime] > ecm_start_time + ECM_DURATION) {
            ecm_in_operation = NO;
        }
    }

    // ecm interference visual effect
    if ([UNIVERSE useShaders] && [UNIVERSE ECMVisualFXEnabled]) {
        // we want to start and stop the effect exactly once, not start it
        // or stop it on every frame
        if ([self scannerFuzziness] > 0.0) {
            if (!gettingInterference) {
                [UNIVERSE setCurrentPostFX:OO_POSTFX_CRTBADSIGNAL];
                gettingInterference = YES;
            }
        } else {
            if (gettingInterference) {
                [UNIVERSE terminatePostFX:OO_POSTFX_CRTBADSIGNAL];
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
    energy += [self energyRechargeRate] * delta_t;

    // 2. Calculate shield recharge rates
    float fwdMax = [self maxForwardShieldLevel];
    float aftMax = [self maxAftShieldLevel];
    float shieldRechargeFwd = [self forwardShieldRechargeRate] * delta_t;
    float shieldRechargeAft = [self aftShieldRechargeRate] * delta_t;
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
    if ((forward_shield > fwdMax * 0.25) && (aft_shield > aftMax * 0.25)) {
        // TODO: Can this be cached anywhere sensibly (without adding another member variable)?
        float minEnergyBankLevel = oo::PListView([UNIVERSE globalSettings]).get<float>(@"shield_charge_energybank_threshold", 0.25);
        energyForShields = MAX(0.0, energy - 0.1 - (maxEnergy * minEnergyBankLevel)); // NB: The - 0.1 ensures the energy value does not 'bounce' across the critical energy message and causes spurious energy-low warnings
    }

    if (forward_shield < aft_shield) {
        rechargeFwd = MIN(rechargeFwd, energyForShields);
        rechargeAft = MIN(rechargeAft, energyForShields - rechargeFwd);
    } else {
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

    if (sun) {
        UPDATE_STAGE("updating sun effects");

        // set the ambient temperature here
        double sun_zd = sun->zero_distance; // square of distance
        double sun_cr = sun->collision_radius;
        double alt1 = sun_cr * sun_cr / sun_zd;
        external_temp = SUN_TEMPERATURE * alt1;

        if ([sun goneNova])
            external_temp *= 100;
        // fuel scooping during the nova mission very unlikely
        if ([sun willGoNova])
            external_temp *= 3;

        // do Revised sun-skimming check here...
        if ([self hasFuelScoop] && alt1 > 0.75 && [self fuel] < [self fuelCapacity]) {
            fuel_accumulator += (float)(delta_t * flightSpeed * 0.010 / [self fuelChargeRate]);
            // are we fast enough to collect any fuel?
            scoopsActive = YES && flightSpeed > 0.1f;
            while (fuel_accumulator > 1.0f) {
                [self setFuel:[self fuel] + 1];
                fuel_accumulator -= 1.0f;
                [self doScriptEvent:OOJSID("shipScoopedFuel")];
            }
            [UNIVERSE displayCountdownMessage:DESC(@"fuel-scoop-active") forCount:1.0];
        }
    }

    // Bug #11692 CmdrJames added Status entering witchspace
    OOEntityStatus status = [self status];
    if ((status != STATUS_ESCAPE_SEQUENCE) && (status != STATUS_ENTERING_WITCHSPACE)) {
        UPDATE_STAGE("updating cabin temperature");

        // work on the cabin temperature
        float heatInsulation = [self heatInsulation]; // Optimisation, suggested by EricW
        float deltaInsulation = delta_t / heatInsulation;
        float heatThreshold = heatInsulation * 100.0f;
        ship_temperature += (float)(flightSpeed * air_friction * deltaInsulation); // wind_speed

        if (external_temp > heatThreshold && external_temp > ship_temperature)
            ship_temperature += (float)((external_temp - ship_temperature) * SHIP_INSULATION_FACTOR * deltaInsulation);
        else {
            if (ship_temperature > SHIP_MIN_CABIN_TEMP)
                ship_temperature += (float)((external_temp - heatThreshold - ship_temperature) * SHIP_COOLING_FACTOR * deltaInsulation);
        }

        if (ship_temperature > SHIP_MAX_CABIN_TEMP)
            [self takeHeatDamage:delta_t * ship_temperature];
    }

    if ((status == STATUS_ESCAPE_SEQUENCE) && (shot_time > ESCAPE_SEQUENCE_TIME)) {
        UPDATE_STAGE("resetting after escape");
        ShipEntity* doppelganger = (ShipEntity*)[self foundTarget];
        // reset legal status again! Could have changed if a previously launched missile hit a clean NPC while in the escape pod.
        [self setBounty:0 withReason:kOOLegalStatusReasonEscapePod];
        bounty = 0;
        thrust = max_thrust; // re-enable inertialess drives
        // no access to all player.ship properties while inside the escape pod,
        // we're not supposed to be inside our ship anymore!
        [self doScriptEvent:OOJSID("escapePodSequenceOver")]; // allow oxps to override the escape pod target
        /**
         * This code branch doesn't seem to be used any more - see ~line 6000
         * Should we remove it? - CIM
         */
        if (EXPECT_NOT(target_system_id != system_id)) // overridden: we're going to a nearby system!
        {
            system_id = target_system_id;
            info_system_id = target_system_id;
            [UNIVERSE setSystemTo:system_id];
            galaxy_coordinates = PointFromString([[UNIVERSE systemManager] getProperty:@"coordinates" forSystem:system_id inGalaxy:galaxy_number]);

            [UNIVERSE setUpSpace];
            // run initial system population
            [UNIVERSE populateNormalSpace];

            [self setDockTarget:[UNIVERSE station]];
            // send world script events to let oxps know we're in a new system.
            // all player.ship properties are still disabled at this stage.
            [UNIVERSE setWitchspaceBreakPattern:YES];
            [self doScriptEvent:OOJSID("shipWillExitWitchspace")];
            [self doScriptEvent:OOJSID("shipExitedWitchspace")];

            [[UNIVERSE planet] update:2.34375 * market_rnd]; // from 0..10 minutes
            [[UNIVERSE station] update:2.34375 * market_rnd]; // from 0..10 minutes
        }

        Entity* dockTargetEntity = [UNIVERSE entityForUniversalID:_dockTarget]; // main station in the original system, unless overridden.
        if ([dockTargetEntity isStation]) // fails if _dockTarget is NO_TARGET
        {
            [doppelganger becomeExplosion]; // blow up the doppelganger
            // restore player ship
            ShipEntity* player_ship = [UNIVERSE newShipWithName:[self shipDataKey]]; // retained
            if (player_ship) {
                // FIXME: this should use OOShipType, which should exist. -- Ahruman
                [self setMesh:[player_ship mesh]];
                [player_ship release]; // we only wanted it for its polygons!
            }
            [UNIVERSE setViewDirection:VIEW_FORWARD];
            [UNIVERSE setBlockJSPlayerShipProps:NO]; // re-enable player.ship!
            [self enterDock:(StationEntity*)dockTargetEntity];
        } else // no dock target? dock target is not a station? game over!
        {
            [self setStatus:STATUS_DEAD];
            //[self playGameOver];	// no death explosion sounds for player pods
            // no shipDied events for player pods, either
            [UNIVERSE displayMessage:DESC(@"gameoverscreen-escape-pod") forCount:kDeadResetTime];
            [UNIVERSE displayMessage:@"" forCount:kDeadResetTime];
            [self showGameOver];
        }
    }

    // MOVED THE FOLLOWING FROM PLAYERENTITY POLLFLIGHTCONTROLS:
    travelling_at_hyperspeed = (flightSpeed > maxFlightSpeed);
    if (hyperspeed_engaged) {
        UPDATE_STAGE("updating hyperspeed");

        // increase speed up to maximum hyperspeed
        if (flightSpeed < maxFlightSpeed * HYPERSPEED_FACTOR)
            flightSpeed += (float)(speed_delta * delta_t * HYPERSPEED_FACTOR);
        if (flightSpeed > maxFlightSpeed * HYPERSPEED_FACTOR)
            flightSpeed = (float)(maxFlightSpeed * HYPERSPEED_FACTOR);

        // check for mass lock
        hyperspeed_locked = [self massLocked];
        // check for mass lock & external temperature?
        // hyperspeed_locked = flightSpeed * air_friction > 40.0f+(ship_temperature - external_temp ) * SHIP_COOLING_FACTOR || [self massLocked];

        if (hyperspeed_locked) {
            [self playJumpMassLocked];
            [UNIVERSE addMessage:DESC(@"jump-mass-locked") forCount:4.5];
            hyperspeed_engaged = NO;
        }
    } else {
        if (afterburner_engaged) {
            UPDATE_STAGE("updating afterburner");

            float abFactor = [self afterburnerFactor];
            float maxInjectionSpeed = maxFlightSpeed * abFactor;
            if (flightSpeed > maxInjectionSpeed) {
                // decellerate to maxInjectionSpeed but slower than without afterburner.
                flightSpeed -= (float)(speed_delta * delta_t * abFactor);
            } else {
                if (flightSpeed < maxInjectionSpeed)
                    flightSpeed += (float)(speed_delta * delta_t * abFactor);
                if (flightSpeed > maxInjectionSpeed)
                    flightSpeed = maxInjectionSpeed;
            }
            fuel_accumulator -= (float)(delta_t * afterburner_rate);
            while ((fuel_accumulator < 0) && (fuel > 0)) {
                fuel_accumulator += 1.0f;
                if (--fuel <= MIN_FUEL)
                    afterburner_engaged = NO;
            }
        } else {
            UPDATE_STAGE("slowing from hyperspeed");

            // slow back down...
            if (travelling_at_hyperspeed) {
                // decrease speed to maximum normal speed
                float deceleration = (speed_delta * delta_t * HYPERSPEED_FACTOR);
                if (alertFlags & ALERT_FLAG_MASS_LOCK) {
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
    if ((fuel_leak_rate > 0.0) && (fuel > 0)) {
        UPDATE_STAGE("updating fuel leakage");

        fuel_accumulator -= (float)(fuel_leak_rate * delta_t);
        while ((fuel_accumulator < 0) && (fuel > 0)) {
            fuel_accumulator += 1.0f;
            fuel--;
        }
        if (fuel == 0)
            fuel_leak_rate = 0;
    }

    // smart_zoom
    UPDATE_STAGE("updating scanner zoom");
    if (scanner_zoom_rate) {
        double z = [hud scannerZoom];
        double z1 = z + scanner_zoom_rate * delta_t;
        if (scanner_zoom_rate > 0.0) {
            if (floor(z1) > floor(z)) {
                z1 = floor(z1);
                scanner_zoom_rate = 0.0f;
            }
        } else {
            if (z1 < 1.0) {
                z1 = 1.0;
                scanner_zoom_rate = 0.0f;
            }
        }
        [hud setScannerZoom:z1];
    }

    [[UNIVERSE gameView] setFov:fieldOfView fromFraction:YES];

    // scanner sanity check - lose any targets further than maximum scanner range
    ShipEntity* primeTarget = [self primaryTarget];
    if (primeTarget && HPdistance2([primeTarget position], [self position]) > SCANNER_MAX_RANGE2 && !autopilot_engaged) {
        [UNIVERSE addMessage:DESC(@"target-lost") forCount:3.0];
        [self removeTarget:primeTarget];
    }
    // compass sanity check and update target for changed mode
    [self validateCompassTarget];

    // update subentities
    UPDATE_STAGE("updating subentities");
    totalBoundingBox = boundingBox; //	reset totalBoundingBox
    ShipEntity* se = nil;
    foreach (se, [self subEntities]) {
        [se update:delta_t];
        if ([se isShip]) {
            BoundingBox sebb = [se findSubentityBoundingBox];
            bounding_box_add_vector(&totalBoundingBox, sebb.max);
            bounding_box_add_vector(&totalBoundingBox, sebb.min);
        }
    }
    // and one thing which isn't a subentity. Fixes bug with
    // mispositioned laser beams particularly noticeable on side view.
    if (!lastShot.empty()) {
        for (const oo::ObjCRef<OOLaserShotEntity*>& lse : lastShot) {
            [lse.get() update:0.0];
        }
        lastShot.clear();
    }

    // update mousewheel status
    UPDATE_STAGE("updating mousewheel delta");
    MyOpenGLView* gView = [UNIVERSE gameView];
    float mouseWheelDelta = [gView mouseWheelDelta];
    if (mouseWheelDelta > 0.0f) {
        if (mouseWheelDelta < delta_t)
            [gView setMouseWheelDelta:0.0f];
        else
            [gView setMouseWheelDelta:mouseWheelDelta - delta_t];
    } else if (mouseWheelDelta < 0.0f) {
        if (mouseWheelDelta > -delta_t)
            [gView setMouseWheelDelta:0.0f];
        else
            [gView setMouseWheelDelta:mouseWheelDelta + delta_t];
    }

    STAGE_TRACKING_END
}

- (void)updateMovementFlags
{
    hasMoved = !HPvector_equal(position, lastPosition);
    hasRotated = !quaternion_equal(orientation, lastOrientation);
    lastPosition = position;
    lastOrientation = orientation;
}

- (void)updateAlertConditionForNearbyEntities
{
    if (![self isInSpace] || [self status] == STATUS_DOCKING) {
        [self clearAlertFlags];
        // not needed while docked
        return;
    }

    int i, ent_count = UNIVERSE->n_entities;
    Entity** uni_entities = UNIVERSE->sortedEntities; // grab the public sorted list
    std::vector<Entity*> my_entities(ent_count);
    Entity* scannedEntity = nil;
    for (i = 0; i < ent_count; i++) {
        my_entities[i] = [uni_entities[i] retain]; // retained
    }
    BOOL massLocked = NO;
    BOOL foundHostiles = NO;
#if OO_VARIABLE_TORUS_SPEED
    BOOL needHyperspeedNearest = YES;
    double hsnDistance = 0;
#endif
    for (i = 0; i < ent_count; i++) // scanner lollypops
    {
        scannedEntity = my_entities[i];

#if OO_VARIABLE_TORUS_SPEED
        if (EXPECT_NOT(needHyperspeedNearest)) {
            // not visual effects, waypoints, ships, etc.
            if (scannedEntity != self && [scannedEntity canCollide] && (![scannedEntity isShip] || ![self collisionExceptedFor:(ShipEntity*)scannedEntity])) {
                hsnDistance = sqrt(scannedEntity->zero_distance) - [scannedEntity collisionRadius];
                needHyperspeedNearest = NO;
            }
        } else if ([scannedEntity isStellarObject]) {
            // planets, stars might be closest surface even if not
            // closest centre. That could be true of others, but the
            // error is negligible there.
            double thisHSN = sqrt(scannedEntity->zero_distance) - [scannedEntity collisionRadius];
            if (thisHSN < hsnDistance) {
                hsnDistance = thisHSN;
            }
        }
#endif

        if (scannedEntity->zero_distance < SCANNER_MAX_RANGE2 || !scannedEntity->isShip) {
            int theirClass = [scannedEntity scanClass];
            // here we could also force masslock for higher than yellow alert, but
            // if we are going to hand over masslock control to scripting, might as well
            // hand it over fully
            if ([self massLockable] /*|| alertFlags > ALERT_FLAG_YELLOW_LIMIT*/) {
                massLocked |= [self checkEntityForMassLock:scannedEntity withScanClass:theirClass]; // we just need one masslocker..
            }
            if (theirClass != CLASS_NO_DRAW) {
                if (theirClass == CLASS_THARGOID || [scannedEntity isCascadeWeapon]) {
                    foundHostiles = YES;
                } else if ([scannedEntity isShip]) {
                    ShipEntity* ship = (ShipEntity*)scannedEntity;
                    foundHostiles |= (([ship hasHostileTarget]) && ([ship primaryTarget] == self));
                }
            }
        }
    }
#if OO_VARIABLE_TORUS_SPEED
    if (EXPECT_NOT(needHyperspeedNearest)) {
        // this case should only occur in an otherwise empty
        // interstellar space - unlikely but possible
        hyperspeedFactor = MIN_HYPERSPEED_FACTOR;
    } else {
        // once nearest object is >4x scanner range
        // start increasing torus speed
        double factor = hsnDistance / (4 * SCANNER_MAX_RANGE);
        if (factor < 1.0) {
            hyperspeedFactor = MIN_HYPERSPEED_FACTOR;
        } else {
            hyperspeedFactor = MIN_HYPERSPEED_FACTOR * sqrt(factor);
            if (hyperspeedFactor > MAX_HYPERSPEED_FACTOR) {
                // caps out at ~10^8m from nearest object
                // which takes ~10 minutes of flying
                hyperspeedFactor = MAX_HYPERSPEED_FACTOR;
            }
        }
    }
#endif

    [self setAlertFlag:ALERT_FLAG_MASS_LOCK
                    to:massLocked];

    [self setAlertFlag:ALERT_FLAG_HOSTILES to:foundHostiles];

    for (i = 0; i < ent_count; i++) {
        [my_entities[i] release]; //	released
    }

    BOOL energyCritical = NO;
    if (energy < 64 && energy < maxEnergy * 0.8) {
        energyCritical = YES;
    }
    [self setAlertFlag:ALERT_FLAG_ENERGY to:energyCritical];

    [self setAlertFlag:ALERT_FLAG_TEMP to:([self hullHeatLevel] > .90)];

    [self setAlertFlag:ALERT_FLAG_ALT to:([self dialAltitude] < .10)];
}

- (void)setMaxFlightPitch:(GLfloat)newValue
{
    max_flight_pitch = newValue;
    pitch_delta = 2.0 * newValue;
}

- (void)setMaxFlightRoll:(GLfloat)newValue
{
    max_flight_roll = newValue;
    roll_delta = 2.0 * newValue;
}

- (void)setMaxFlightYaw:(GLfloat)newValue
{
    max_flight_yaw = newValue;
    yaw_delta = 2.0 * newValue;
}

- (BOOL)checkEntityForMassLock:(Entity*)ent withScanClass:(int)theirClass
{
    BOOL massLocked = NO;
    BOOL entIsCloakedShip = [ent isShip] && [(ShipEntity*)ent isCloaked];

    if (EXPECT_NOT([ent isStellarObject])) {
        Entity<OOStellarBody>* stellar = (Entity<OOStellarBody>*)ent;
        if (EXPECT([stellar planetType] != STELLAR_TYPE_MINIATURE)) {
            double dist = stellar->zero_distance;
            double rad = stellar->collision_radius;
            double factor = ([stellar isSun]) ? 2.0 : 4.0;
            // plus ensure mass lock when 25 km or less from the surface of small stellar bodies
            // dist is a square distance so it needs to be compared to (rad+25000) * (rad+25000)!
            if (dist < rad * rad * factor || dist < rad * rad + 50000 * rad + 625000000) {
                massLocked = YES;
            }
        }
    } else if (theirClass != CLASS_NO_DRAW) {
        if (EXPECT_NOT(entIsCloakedShip)) {
            theirClass = CLASS_NO_DRAW;
        }
    }

    if (!massLocked && ent->zero_distance <= SCANNER_MAX_RANGE2) {
        switch (theirClass) {
        case CLASS_NO_DRAW:
            // cloaked ships do mass lock! - Nikos 20200718
            if (entIsCloakedShip && ![ent isPlayer]) {
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

- (void)updateAlertCondition
{
    [self updateAlertConditionForNearbyEntities];
    /*	TODO: update alert condition once per frame. Tried this before, but
            there turned out to be complications. See mailing list archive.
            -- Ahruman 20070802
     */
    OOAlertCondition cond = [self alertCondition];
    OOTimeAbsolute t = [UNIVERSE getTime];
    if (cond != lastScriptAlertCondition) {
        [self doScriptEvent:OOJSID("alertConditionChanged") withArgument:[NSNumber numberWithInt:cond] andArgument:[NSNumber numberWithInt:lastScriptAlertCondition]];
        lastScriptAlertCondition = cond;
    }
    /* Update heuristic assessment of whether player is fleeing */
    if (cond == ALERT_CONDITION_DOCKED || cond == ALERT_CONDITION_GREEN || (cond == ALERT_CONDITION_YELLOW && energy == maxEnergy)) {
        fleeing_status = PLAYER_FLEEING_NONE;
    } else if (fleeing_status == PLAYER_FLEEING_UNLIKELY && (energy > maxEnergy * 0.6 || cond != ALERT_CONDITION_RED)) {
        fleeing_status = PLAYER_FLEEING_NONE;
    } else if ((fleeing_status == PLAYER_FLEEING_MAYBE || fleeing_status == PLAYER_FLEEING_UNLIKELY) && cargo_dump_time > last_shot_time) {
        fleeing_status = PLAYER_FLEEING_CARGO;
    } else if (fleeing_status == PLAYER_FLEEING_MAYBE && last_shot_time + 10 > t) {
        fleeing_status = PLAYER_FLEEING_NONE;
    } else if (fleeing_status == PLAYER_FLEEING_LIKELY && last_shot_time + 10 > t) {
        fleeing_status = PLAYER_FLEEING_UNLIKELY;
    } else if (fleeing_status == PLAYER_FLEEING_NONE && cond == ALERT_CONDITION_RED && last_shot_time + 10 < t && flightSpeed > 0.75 * maxFlightSpeed) {
        fleeing_status = PLAYER_FLEEING_MAYBE;
    } else if ((fleeing_status == PLAYER_FLEEING_MAYBE || fleeing_status == PLAYER_FLEEING_CARGO) && cond == ALERT_CONDITION_RED && last_shot_time + 10 < t && flightSpeed > 0.75 * maxFlightSpeed && energy < maxEnergy * 0.5 && (forward_shield < [self maxForwardShieldLevel] * 0.25 || aft_shield < [self maxAftShieldLevel] * 0.25)) {
        fleeing_status = PLAYER_FLEEING_LIKELY;
    }
}

- (void)updateFuelScoops:(OOTimeDelta)delta_t
{
    if (scoopsActive) {
        [self updateFuelScoopSoundWithInterval:delta_t];
        if (![self scoopOverride]) {
            scoopsActive = NO;
            [self updateFuelScoopSoundWithInterval:delta_t];
        }
    }
}

- (void)updateClocks:(OOTimeDelta)delta_t
{
    // shot time updates are still needed here for STATUS_DEAD!
    shot_time += delta_t;
    script_time += delta_t;
    unsigned prev_day = floor(ship_clock / 86400);
    ship_clock += delta_t;
    if (ship_clock_adjust > 0.0) // adjust for coming out of warp (add LY * LY hrs)
    {
        double fine_adjust = delta_t * 7200.0;
        if (ship_clock_adjust > 86400) // more than a day
            fine_adjust = delta_t * 115200.0; // 16 times faster
        if (ship_clock_adjust > 0) {
            if (fine_adjust > ship_clock_adjust)
                fine_adjust = ship_clock_adjust;
            ship_clock += fine_adjust;
            ship_clock_adjust -= fine_adjust;
        } else {
            if (fine_adjust < ship_clock_adjust)
                fine_adjust = ship_clock_adjust;
            ship_clock -= fine_adjust;
            ship_clock_adjust += fine_adjust;
        }
    } else
        ship_clock_adjust = 0.0;

    unsigned now_day = floor(ship_clock / 86400.0);
    while (prev_day < now_day) {
        prev_day++;
        [self doScriptEvent:OOJSID("dayChanged") withArgument:oo::ObjectFromPList(oo::PList::unsignedInteger(prev_day))];
        // not impossible that at ultra-low frame rates two of these will
        // happen in a single update.
    }

    // fps
    if (ship_clock > fps_check_time) {
        if (![self clockAdjusting]) {
            fps_counter = (int)([UNIVERSE timeAccelerationFactor] * floor([UNIVERSE framesDoneThisUpdate] / (fps_check_time - last_fps_check_time)));
            last_fps_check_time = fps_check_time;
            fps_check_time = ship_clock + MINIMUM_GAME_TICK;
        } else {
            // Good approximation for when the clock is adjusting and proper fps calculation
            // cannot be performed.
            fps_counter = (int)([UNIVERSE timeAccelerationFactor] * floor(1.0 / delta_t));
            fps_check_time = ship_clock + MINIMUM_GAME_TICK;
        }
        [UNIVERSE resetFramesDoneThisUpdate]; // Reset frame counter
    }
}

- (void)checkScriptsIfAppropriate
{
    if (script_time <= script_time_check)
        return;

    if ([self status] != STATUS_IN_FLIGHT) {
        switch (gui_screen) {
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
    [self checkScript];
    script_time_check += script_time_interval;
}

- (void)updateTrumbles:(OOTimeDelta)delta_t
{
    OOTrumble** trumbles = [self trumbleArray];
    NSUInteger i;

    for (i = [self trumbleCount]; i > 0; i--) {
        OOTrumble* trum = trumbles[i - 1];
        [trum updateTrumble:delta_t];
    }
}

- (void)performAutopilotUpdates:(OOTimeDelta)delta_t
{
    [self processBehaviour:delta_t];
    [self applyVelocity:delta_t];
    [self doBookkeeping:delta_t];
}

- (void)performDockingRequest:(StationEntity*)stationForDocking
{
    if (stationForDocking == nil)
        return;
    if (![stationForDocking isStation] || ![stationForDocking isKindOfClass:[StationEntity class]])
        return;
    if ([self isDocked])
        return;
    if (autopilot_engaged && [self targetStation] == stationForDocking)
        return;
    if (autopilot_engaged && [self targetStation] != stationForDocking) {
        [self disengageAutopilot];
    }
    const std::optional<std::string> stationDockingClearanceStatus = [stationForDocking cxx_acceptDockingClearanceRequestFrom:self];
    if (stationDockingClearanceStatus.has_value()) {
        [self doScriptEvent:OOJSID("playerRequestedDockingClearance") withArgument:oo::NSStringFrom(*stationDockingClearanceStatus)];
        if (*stationDockingClearanceStatus == "DOCKING_CLEARANCE_GRANTED") {
            [self doScriptEvent:OOJSID("playerDockingClearanceGranted")];
        }
    }
}

- (void)requestDockingClearance:(StationEntity*)stationForDocking
{
    if (dockingClearanceStatus != DOCKING_CLEARANCE_STATUS_REQUESTED && dockingClearanceStatus != DOCKING_CLEARANCE_STATUS_GRANTED) {
        [self performDockingRequest:stationForDocking];
    }
}

- (void)cancelDockingRequest:(StationEntity*)stationForDocking
{
    if (stationForDocking == nil)
        return;
    if (![stationForDocking isStation] || ![stationForDocking isKindOfClass:[StationEntity class]])
        return;
    if ([self isDocked])
        return;
    if (autopilot_engaged && [self targetStation] == stationForDocking)
        return;
    if (autopilot_engaged && [self targetStation] != stationForDocking) {
        [self disengageAutopilot];
    }
    if (dockingClearanceStatus == DOCKING_CLEARANCE_STATUS_GRANTED || dockingClearanceStatus == DOCKING_CLEARANCE_STATUS_REQUESTED) {
        const std::optional<std::string> stationDockingClearanceStatus = [stationForDocking cxx_acceptDockingClearanceRequestFrom:self];
        if (stationDockingClearanceStatus == "DOCKING_CLEARANCE_CANCELLED") {
            [self doScriptEvent:OOJSID("playerDockingClearanceCancelled")];
        }
    }
}

- (BOOL)engageAutopilotToStation:(StationEntity*)stationForDocking
{
    if (stationForDocking == nil)
        return NO;
    if ([self isDocked])
        return NO;

    if (autopilot_engaged && [self targetStation] == stationForDocking) {
        return YES;
    }

    [self setTargetStation:stationForDocking];
    DESTROY(_primaryTarget);
    autopilot_engaged = YES;
    ident_engaged = NO;
    [self safeAllMissiles];
    velocity = kZeroVector;
    if ([self status] == STATUS_WITCHSPACE_COUNTDOWN)
        [self cancelWitchspaceCountdown]; // cancel witchspace countdown properly
    [self setStatus:STATUS_AUTOPILOT_ENGAGED];
    [self resetAutopilotAI];
    [shipAI setState:@"BEGIN_DOCKING"]; // reboot the AI
    [self playAutopilotOn];
    [[OOMusicController sharedController] playDockingMusic];
    [self doScriptEvent:OOJSID("playerStartedAutoPilot") withArgument:stationForDocking];
    [self setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_GRANTED];

    if (afterburner_engaged) {
        afterburner_engaged = NO;
        if (afterburnerSoundLooping)
            [self stopAfterburnerSound];
    }
    return YES;
}

- (void)disengageAutopilot
{
    if (autopilot_engaged) {
        [self abortDocking]; // let the station know that you are no longer on approach
        behaviour = BEHAVIOUR_IDLE;
        frustration = 0.0;
        autopilot_engaged = NO;
        DESTROY(_primaryTarget);
        [self setTargetStation:nil];
        [self setStatus:STATUS_IN_FLIGHT];
        [self playAutopilotOff];
        [self setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
        [[OOMusicController sharedController] stopDockingMusic];
        [self doScriptEvent:OOJSID("playerCancelledAutoPilot")];

        [self resetAutopilotAI];
    }
}

- (void)resetAutopilotAI
{
    AI* myAI = [self getAI];
    // JSAI: will need changing if oolite-dockingAI.js written
    if (![[myAI name] isEqualToString:PLAYER_DOCKING_AI_NAME]) {
        [self setAITo:PLAYER_DOCKING_AI_NAME];
    }
    [myAI clearAllData];
    [myAI setState:@"GLOBAL"];
    [myAI setNextThinkTime:[UNIVERSE getTime] + 2];
    [myAI setOwner:self];
}

#define VELOCITY_CLEANUP_MIN 2000.0f // Minimum speed for "power braking".
#define VELOCITY_CLEANUP_FULL 5000.0f // Speed at which full "power braking" factor is used.
#define VELOCITY_CLEANUP_RATE 0.001f // Factor for full "power braking".

#if OO_VARIABLE_TORUS_SPEED
- (GLfloat)hyperspeedFactor
{
    return hyperspeedFactor;
}
#endif

- (BOOL)injectorsEngaged
{
    return afterburner_engaged;
}

- (BOOL)hyperspeedEngaged
{
    return hyperspeed_engaged;
}

- (void)performInFlightUpdates:(OOTimeDelta)delta_t
{
    STAGE_TRACKING_BEGIN

    // do flight routines
    //// velocity stuff
    UPDATE_STAGE("applying newtonian drift");
    assert(VELOCITY_CLEANUP_FULL > VELOCITY_CLEANUP_MIN);

    [self applyVelocity:delta_t];

    GLfloat thrust_factor = 1.0;
    if (flightSpeed > maxFlightSpeed) {
        if (afterburner_engaged) {
            thrust_factor = [self afterburnerFactor];
        } else {
            thrust_factor = HYPERSPEED_FACTOR;
        }
    }

    GLfloat velmag = magnitude(velocity);
    GLfloat velmag2 = velmag - (float)delta_t * thrust * thrust_factor;
    if (velmag > 0) {
        UPDATE_STAGE("applying power braking");

        if (velmag > VELOCITY_CLEANUP_MIN) {
            GLfloat rate;
            // Fix up extremely ridiculous speeds that can happen in collisions or explosions
            if (velmag > VELOCITY_CLEANUP_FULL)
                rate = VELOCITY_CLEANUP_RATE;
            else
                rate = (velmag - VELOCITY_CLEANUP_MIN) / (VELOCITY_CLEANUP_FULL - VELOCITY_CLEANUP_MIN) * VELOCITY_CLEANUP_RATE;
            velmag2 -= velmag * rate;
        }
        if (velmag2 < 0.0f)
            velocity = kZeroVector;
        else
            velocity = vector_multiply_scalar(velocity, velmag2 / velmag);
    }

    UPDATE_STAGE("updating joystick");
    [self applyRoll:(float)delta_t * flightRoll andClimb:(float)delta_t * flightPitch];
    if (flightYaw != 0.0) {
        [self applyYaw:(float)delta_t * flightYaw];
    }

    UPDATE_STAGE("applying para-newtonian thrust");
    [self moveForward:delta_t * flightSpeed];

    UPDATE_STAGE("updating targeting");
    [self updateTargeting];

    STAGE_TRACKING_END
}

- (void)performWitchspaceCountdownUpdates:(OOTimeDelta)delta_t
{
    STAGE_TRACKING_BEGIN

    UPDATE_STAGE("doing bookkeeping");
    [self doBookkeeping:delta_t];

    UPDATE_STAGE("updating countdown timer");
    witchspaceCountdown = fdim(witchspaceCountdown, delta_t);

    // damaged gal drive? abort!
    /* TODO: this check should possibly be hasEquipmentItemProviding:,
     * but if it was we'd need to know which item was actually doing
     * the providing so it could be removed. */
    if (EXPECT_NOT(galactic_witchjump && ![self hasEquipmentItem:@"EQ_GAL_DRIVE"])) {
        galactic_witchjump = NO;
        [self setStatus:STATUS_IN_FLIGHT];
        [self playHyperspaceAborted];
        [self doScriptEvent:OOJSID("playerJumpFailed") withArgument:@"malfunction"];
        return;
    }

    int seconds = round(witchspaceCountdown);
    if (galactic_witchjump) {
        [UNIVERSE displayCountdownMessage:OOExpandKey(@"witch-galactic-in-x-seconds", seconds) forCount:1.0];
    } else {
        const std::string destination = oo::StdString([UNIVERSE getSystemName:[self nextHopTargetSystemID]]); // (nil raised in the expansion)
        [UNIVERSE displayCountdownMessage:oo::NSStringFrom(ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "witch-to-x-in-y-seconds",
                                              { { "seconds", oo::PList::signedInteger(seconds) }, { "destination", oo::PList(destination) } }))
                                 forCount:1.0];
    }

    if (witchspaceCountdown == 0.0) {
        UPDATE_STAGE("preloading planet textures");
        if (!galactic_witchjump) {
            /*	Note: planet texture preloading is done twice for hyperspace jumps:
                    once when starting the countdown and once at the beginning of the
                    jump. The reason is that the preloading may have been skipped the
                    first time because of rate limiting (see notes at
                    -preloadPlanetTexturesForSystem:). There is no significant overhead
                    from doing it twice thanks to the texture cache.
                    -- Ahruman 2009-12-19
            */
            [UNIVERSE preloadPlanetTexturesForSystem:target_system_id];
        } else {
            // FIXME: preload target system for galactic jump?
        }

        UPDATE_STAGE("JUMP!");
        if (galactic_witchjump)
            [self enterGalacticWitchspace];
        else
            [self enterWitchspace];
        galactic_witchjump = NO;
    }

    STAGE_TRACKING_END
}

- (void)performWitchspaceExitUpdates:(OOTimeDelta)delta_t
{
    if ([UNIVERSE breakPatternOver]) {
        [self resetExhaustPlumes];
        // time to check the script!
        [self checkScript];
        // next check in 10s
        [self resetScriptTimer]; // reset the in-system timer

        // announce arrival
        if ([UNIVERSE planet]) {
            [UNIVERSE addMessage:oo::NSStringFrom(oo::str::format(" %s. ", oo::DescriptionOf([UNIVERSE getSystemName:system_id]).c_str())) forCount:3.0];
            // and reset the compass
            if ([self hasEquipmentItemProviding:@"EQ_ADVANCED_COMPASS"])
                compassMode = COMPASS_MODE_PLANET;
            else
                compassMode = COMPASS_MODE_BASIC;
        } else {
            if ([UNIVERSE inInterstellarSpace])
                [UNIVERSE addMessage:DESC(@"witch-engine-malfunction") forCount:3.0]; // if sun gone nova, print nothing
        }

        [self setStatus:STATUS_IN_FLIGHT];

        // If we are exiting witchspace after a scripted misjump. then make sure it gets reset now.
        // Scripted misjump situations should have a lifespan of one jump only, to keep things
        // simple - Nikos 20090728
        if ([self scriptedMisjump])
            [self setScriptedMisjump:NO];
        // similarly reset the misjump range to the traditional 0.5
        [self setScriptedMisjumpRange:0.5];

        [self doScriptEvent:OOJSID("shipExitedWitchspace") withArgument:[self jumpCause]];

        [self doBookkeeping:delta_t]; // arrival frame updates

        suppressAegisMessages = NO;
    }
}

- (void)performLaunchingUpdates:(OOTimeDelta)delta_t
{
    if (![UNIVERSE breakPatternHide]) {
        flightRoll = launchRoll; // synchronise player's & launching station's spins.
        [self doBookkeeping:delta_t]; // don't show ghost exhaust plumes from previous docking!
    }

    if ([UNIVERSE breakPatternOver]) {
        // time to check the legacy scripts!
        [self checkScript];
        // next check in 10s

        [self setStatus:STATUS_IN_FLIGHT];

        [self setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
        StationEntity* stationLaunchedFrom = [UNIVERSE nearestEntityMatchingPredicate:IsStationPredicate parameter:NULL relativeToEntity:self];
        [self doScriptEvent:OOJSID("shipLaunchedFromStation") withArgument:stationLaunchedFrom];
    }
}

- (void)performDockingUpdates:(OOTimeDelta)delta_t
{
    if ([UNIVERSE breakPatternOver]) {
        [self docked]; // bookkeeping for docking
    }

    // if cloak or ecm visual effects are playing while docking, terminate them
    [UNIVERSE terminatePostFX:OO_POSTFX_CLOAK];
    if ([UNIVERSE ECMVisualFXEnabled])
        [UNIVERSE terminatePostFX:OO_POSTFX_CRTBADSIGNAL];
}

- (void)performDeadUpdates:(OOTimeDelta)delta_t
{
    [UNIVERSE terminatePostFX:OO_POSTFX_CLOAK];
    if ([UNIVERSE ECMVisualFXEnabled])
        [UNIVERSE terminatePostFX:OO_POSTFX_CRTBADSIGNAL];

    [self gameOverFadeToBW];

    if ([self shotTime] > kDeadResetTime) {
        BOOL was_mouse_control_on = mouse_control_on;
        [UNIVERSE handleGameOver]; //  we restart the UNIVERSE
        mouse_control_on = was_mouse_control_on;
    }
}

- (void)gameOverFadeToBW
{
    const oo::PList fadeOut = oo::Defaults::standard().object("gameover-seconds-to-bw-fadeout");
    float secondsToBWFadeOut = oo::PListGet<float>::from(fadeOut.isNull() ? nullptr : &fadeOut, 5.0f);
    if ([UNIVERSE detailLevel] >= DETAIL_LEVEL_SHADERS && secondsToBWFadeOut > 0.0f) {
        MyOpenGLView* gameView = [UNIVERSE gameView];
        static float originalColorSaturation = -1.0f;
        if (originalColorSaturation == -1.0f)
            originalColorSaturation = [gameView colorSaturation];
        if ([self shotTime] < secondsToBWFadeOut) {
            // fade to black & white within secondsToBWFadeOut, independently of
            // frame rate and original color saturation
            if (fps_counter != 0) {
                [gameView adjustColorSaturation:-(originalColorSaturation * (1.0f / secondsToBWFadeOut) * [UNIVERSE timeAccelerationFactor] / fps_counter)];
            }
        }

        if ([self shotTime] > kDeadResetTime) {
            // make sure to subtract the current saturation because if the user presses space to skip
            // the game over screen before the transition to b/w has been completed, whatever is left
            // will be added to the original saturation, resulting in an oversaturated image
            [gameView adjustColorSaturation:originalColorSaturation - [gameView colorSaturation]];
            originalColorSaturation = -1.0f;
        }
    }
}

// Target is valid if it's within Scanner range, AND
// Target is a ship AND is not cloaked or jamming, OR
// Target is a wormhole AND player has the Wormhole Scanner
- (BOOL)isValidTarget:(Entity*)target
{
    // Just in case we got called with a bad target.
    if (!target)
        return NO;

    // If target is beyond scanner range, it's lost
    if (target->zero_distance > SCANNER_MAX_RANGE2)
        return NO;

    // If target is a ship, check whether it's cloaked or is actively jamming our scanner
    if ([target isShip]) {
        ShipEntity* targetShip = (ShipEntity*)target;
        if ([targetShip isCloaked] || // checks for cloaked ships
            ([targetShip isJammingScanning] && ![self hasMilitaryScannerFilter])) // checks for activated jammer
        {
            return NO;
        }
        OOEntityStatus tstatus = [targetShip status];
        if (tstatus == STATUS_ENTERING_WITCHSPACE || tstatus == STATUS_IN_HOLD || tstatus == STATUS_DOCKED) { // checks for ships entering wormholes, docking, or been scooped
            return NO;
        }
        return YES;
    }

    // If target is an unexpired wormhole and the player has bought the Wormhole Scanner and we're in ID mode
    if ([target isWormhole] && [target scanClass] != CLASS_NO_DRAW &&
        [self hasEquipmentItemProviding:@"EQ_WORMHOLE_SCANNER"] && ident_engaged) {
        return YES;
    }

    // Target is neither a wormhole nor a ship
    return NO;
}

- (void)showGameOver
{
    [hud cxx_resetGuis:oo::PList(oo::PList::Dict { { "message_gui", oo::PList(oo::PList::Dict()) } })];
    const std::string scoreMS = oo::str::formatRuntime(oo::StdString(OOExpandKey(@"gameoverscreen-score-@")),
        { oo::DescriptionOf(KillCountToRatingAndKillString(ship_kills)) });

    [UNIVERSE displayMessage:OOExpandKey(@"gameoverscreen-game-over") forCount:kDeadResetTime];
    [UNIVERSE displayMessage:@"" forCount:kDeadResetTime];
    [UNIVERSE displayMessage:oo::NSStringFrom(scoreMS) forCount:kDeadResetTime];
    [UNIVERSE displayMessage:@"" forCount:kDeadResetTime];
    [UNIVERSE displayMessage:OOExpandKey(@"gameoverscreen-press-space") forCount:kDeadResetTime];
    [UNIVERSE displayMessage:@" " forCount:kDeadResetTime];
    [UNIVERSE displayMessage:@"" forCount:kDeadResetTime];
    [self resetShotTime];
}

- (void)cxx_showShipModelWithKey:(const std::string&)shipKey shipData:(const oo::PList&)shipDataIn personality:(uint16_t)personality factorX:(GLfloat)factorX factorY:(GLfloat)factorY factorZ:(GLfloat)factorZ inContext:(const std::optional<std::string>&)context
{
    // (a nil key returns in the bridged -showShipModelWithKey:...)
    const oo::PList shipData = shipDataIn.isNull() ? [[OOShipRegistry sharedRegistry] cxx_shipInfoForKey:shipKey] : shipDataIn;
    if (shipData.isNull())
        return;

    Quaternion q2 = { (GLfloat)M_SQRT1_2, (GLfloat)M_SQRT1_2, (GLfloat)0.0f, (GLfloat)0.0f };
    // MKW - retrieve last demo ships' orientation and release it
    if (demoShip != nil) {
        q2 = [demoShip orientation];
        [demoShip release];
    }

    ShipEntity* ship = [[ProxyPlayerEntity alloc] initWithKey:oo::NSStringFrom(shipKey) definition:oo::ObjectFromPList(shipData)];
    if (personality != ENTITY_PERSONALITY_INVALID)
        [ship setEntityPersonalityInt:personality];

    [ship wasAddedToUniverse];

    if (context.has_value())
        OO_LOG("script.debug.note.showShipModel", "::::: showShipModel:'{}' in context: {}.", oo::DescriptionOf([ship name]), *context);

    GLfloat cr = [ship collisionRadius];
    [ship setOrientation:q2];
    [ship setPositionX:factorX * cr y:factorY * cr z:factorZ * cr];
    [ship setScanClass:CLASS_NO_DRAW];
    [ship setDemoShip:0.6];
    [ship setDemoStartTime:[UNIVERSE getTime]];
    if ([ship pendingEscortCount] > 0)
        [ship setPendingEscortCount:0];
    [ship setAITo:@"nullAI.plist"];
    const oo::PList* subEntStatus = shipData.find("subentities_status");
    // show missing subentities if there's a subentities_status key
    if (subEntStatus != nullptr)
        [ship cxx_deserializeShipSubEntitiesFrom:oo::PListGet<std::string>::from(subEntStatus, std::string())];
    [UNIVERSE addEntity:ship];
    // MKW - save demo ship for its rotation
    demoShip = [ship retain];

    [ship setStatus:STATUS_COCKPIT_DISPLAY];

    [ship release];
}

// Check for lost targeting - both on the ships' main target as well as each
// missile.
// If we're actively scanning and we don't have a current target, then check
// to see if we've locked onto a new target.
// Finally, if we have a target and it's a wormhole, check whether we have more
// information
- (void)updateTargeting
{
    STAGE_TRACKING_BEGIN

    // check for lost ident target and ensure the ident system is actually scanning
    UPDATE_STAGE("checking ident target");
    if (ident_engaged && [self primaryTarget] != nil) {
        if (![self isValidTarget:[self primaryTarget]]) {
            if (!suppressTargetLost) {
                [UNIVERSE addMessage:DESC(@"target-lost") forCount:3.0];
                [self playTargetLost];
                [self noteLostTarget];
            } else {
                suppressTargetLost = NO;
            }

            DESTROY(_primaryTarget);
        }
    }

    // check each unlaunched missile's target still exists and is in-range
    UPDATE_STAGE("checking missile targets");
    if (missile_status != MISSILE_STATUS_SAFE) {
        unsigned i;
        for (i = 0; i < max_missiles; i++) {
            if ([missile_entity[i] primaryTarget] != nil && ![self isValidTarget:[missile_entity[i] primaryTarget]]) {
                [UNIVERSE addMessage:DESC(@"target-lost") forCount:3.0];
                [self playTargetLost];
                [missile_entity[i] removeTarget:nil];
                if (i == activeMissile) {
                    [self noteLostTarget];
                    DESTROY(_primaryTarget);
                    missile_status = MISSILE_STATUS_ARMED;
                }
            } else if (i == activeMissile && [missile_entity[i] primaryTarget] == nil) {
                missile_status = MISSILE_STATUS_ARMED;
            }
        }
    }

    // if we don't have a primary target, and we're scanning, then check for a new
    // target to lock on to
    UPDATE_STAGE("looking for new target");
    if ([self primaryTarget] == nil && (ident_engaged || missile_status != MISSILE_STATUS_SAFE) && ([self status] == STATUS_IN_FLIGHT || [self status] == STATUS_WITCHSPACE_COUNTDOWN)) {
        Entity* target = [UNIVERSE firstEntityTargetedByPlayer];
        if ([self isValidTarget:target]) {
            [self addTarget:target];
        }
    }

    // If our primary target is a wormhole, check to see if we have additional
    // information
    UPDATE_STAGE("checking for additional wormhole information");
    if ([[self primaryTarget] isWormhole]) {
        WormholeEntity* wh = [self primaryTarget];
        switch ([wh scanInfo]) {
        case WH_SCANINFO_NONE:
            OO_LOG(cxx_kOOLogInconsistentState, "{}", "Internal Error - WH_SCANINFO_NONE reached in [PlayerEntity updateTargeting:]");
            [self dumpState];
            [wh dumpState];
            // Workaround a reported hit of the assert here.  We really
            // should work out how/why this could happen though and fix
            // the underlying cause.
            // - MKW 2011.03.11
            // assert([wh scanInfo] != WH_SCANINFO_NONE);
            [wh setScannedAt:[self clockTimeAdjusted]];
            break;
        case WH_SCANINFO_SCANNED:
            if ([self clockTimeAdjusted] > [wh scanTime] + 2) {
                [wh setScanInfo:WH_SCANINFO_COLLAPSE_TIME];
                //[UNIVERSE addCommsMessage:oo::NSStringFrom(oo::str::formatRuntime(oo::StdString(DESC(@"wormhole-collapse-time-computed")),
                //						   { oo::StdString([UNIVERSE getSystemName:[wh destination]]) })) forCount:5.0];
            }
            break;
        case WH_SCANINFO_COLLAPSE_TIME:
            if ([self clockTimeAdjusted] > [wh scanTime] + 4) {
                [wh setScanInfo:WH_SCANINFO_ARRIVAL_TIME];
                [UNIVERSE addCommsMessage:oo::NSStringFrom(oo::str::formatRuntime(oo::StdString(DESC(@"wormhole-arrival-time-computed-@")),
                                              { cxx_ClockToString([wh estimatedArrivalTime], NO) }))
                                 forCount:5.0];
            }
            break;
        case WH_SCANINFO_ARRIVAL_TIME:
            if ([self clockTimeAdjusted] > [wh scanTime] + 7) {
                [wh setScanInfo:WH_SCANINFO_DESTINATION];
                [UNIVERSE addCommsMessage:oo::NSStringFrom(oo::str::formatRuntime(oo::StdString(DESC(@"wormhole-destination-computed-@")),
                                              { oo::DescriptionOf([UNIVERSE getSystemName:[wh destination]]) }))
                                 forCount:5.0];
            }
            break;
        case WH_SCANINFO_DESTINATION:
            if ([self clockTimeAdjusted] > [wh scanTime] + 10) {
                [wh setScanInfo:WH_SCANINFO_SHIP];
                // TODO: Extract last ship from wormhole and display its name
            }
            break;
        case WH_SCANINFO_SHIP:
            break;
        }
    }

    STAGE_TRACKING_END
}

- (void)orientationChanged
{
    quaternion_normalize(&orientation);
    rotMatrix = OOMatrixForQuaternionRotation(orientation);
    OOMatrixGetBasisVectors(rotMatrix, &v_right, &v_up, &v_forward);

    orientation.w = -orientation.w;
    playerRotMatrix = OOMatrixForQuaternionRotation(orientation); // this is the rotation similar to ordinary ships
    orientation.w = -orientation.w;
}

- (void)applyAttitudeChanges:(double)delta_t
{
    [self applyRoll:flightRoll * delta_t andClimb:flightPitch * delta_t];
    [self applyYaw:flightYaw * delta_t];
}

- (void)applyRoll:(GLfloat)roll1 andClimb:(GLfloat)climb1
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
    if (EXPECT_NOT(quaternion_equal(orientation, kZeroQuaternion))) {
        if (!quaternion_equal(lastOrientation, kZeroQuaternion)) {
            orientation = lastOrientation;
        } else {
            orientation = kIdentityQuaternion;
        }
    }

    [self orientationChanged];
}

/*
 * This method should not be necessary, but when I replaced the above with applyRoll:andClimb:andYaw, the
 * ship went crazy. Perhaps applyRoll:andClimb is called from one of the subclasses and that was messing
 * things up.
 */
- (void)applyYaw:(GLfloat)yaw
{
    quaternion_rotate_about_y(&orientation, -yaw);

    [self orientationChanged];
}

- (OOMatrix)drawRotationMatrix // override to provide the 'correct' drawing matrix
{
    return playerRotMatrix;
}

- (OOMatrix)drawTransformationMatrix
{
    OOMatrix result = playerRotMatrix;
    // HPVect: modify to use camera-relative positioning
    return OOMatrixTranslate(result, HPVectorToVector(position));
}

- (Quaternion)normalOrientation
{
    return make_quaternion(-orientation.w, orientation.x, orientation.y, orientation.z);
}

- (void)setNormalOrientation:(Quaternion)quat
{
    [self setOrientation:make_quaternion(-quat.w, quat.x, quat.y, quat.z)];
}

- (void)moveForward:(double)amount
{
    distanceTravelled += (float)amount;
    [self setPosition:HPvector_add(position, vectorToHPVector(vector_multiply_scalar(v_forward, (float)amount)))];
}

- (HPVector)breakPatternPosition
{
    return HPvector_add(position, vectorToHPVector(quaternion_rotate_vector(quaternion_conjugate(orientation), forwardViewOffset)));
}

- (Vector)viewpointOffset
{
    //	if ([UNIVERSE breakPatternHide])
    //		return kZeroVector;	// center view for break pattern
    // now done by positioning break pattern correctly

    switch ([UNIVERSE viewDirection]) {
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

- (Vector)viewpointOffsetAft
{
    return aftViewOffset;
}

- (Vector)viewpointOffsetForward
{
    return forwardViewOffset;
}

- (Vector)viewpointOffsetPort
{
    return portViewOffset;
}

- (Vector)viewpointOffsetStarboard
{
    return starboardViewOffset;
}

/* TODO post 1.78: profiling suggests this gets called often enough
 * that it's worth caching the result per-frame - CIM */
- (HPVector)viewpointPosition
{
    HPVector viewpoint = position;
    if (showDemoShips) {
        viewpoint = kZeroHPVector;
    }
    Vector offset = [self viewpointOffset];

    // FIXME: this ought to be done with matrix or quaternion functions.
    OOMatrix r = rotMatrix;

    viewpoint.x += offset.x * r.m[0][0];
    viewpoint.y += offset.x * r.m[1][0];
    viewpoint.z += offset.x * r.m[2][0];
    viewpoint.x += offset.y * r.m[0][1];
    viewpoint.y += offset.y * r.m[1][1];
    viewpoint.z += offset.y * r.m[2][1];
    viewpoint.x += offset.z * r.m[0][2];
    viewpoint.y += offset.z * r.m[1][2];
    viewpoint.z += offset.z * r.m[2][2];

    return viewpoint;
}

- (void)drawImmediate:(bool)immediate translucent:(bool)translucent
{
    switch ([self status]) {
    case STATUS_DEAD:
    case STATUS_COCKPIT_DISPLAY:
    case STATUS_DOCKED:
    case STATUS_START_GAME:
        return;

    default:
        if ([UNIVERSE breakPatternHide])
            return;
    }

    [super drawImmediate:immediate translucent:translucent];
}

- (void)setMassLockable:(BOOL)newValue
{
    massLockable = !!newValue;
    [self updateAlertCondition];
}

- (BOOL)massLockable
{
    return massLockable;
}

- (BOOL)massLocked
{
    return ((alertFlags & ALERT_FLAG_MASS_LOCK) != 0);
}

- (BOOL)atHyperspeed
{
    return travelling_at_hyperspeed;
}

- (float)occlusionLevel
{
    return occlusion_dial;
}

- (void)setOcclusionLevel:(float)level
{
    occlusion_dial = level;
}

- (void)setDockedAtMainStation
{
    [self setDockedStation:[UNIVERSE station]];
    if (_dockedStation != nil)
        [self setStatus:STATUS_DOCKED];
}

- (StationEntity*)dockedStation
{
    return [_dockedStation weakRefUnderlyingObject];
}

- (void)setDockedStation:(StationEntity*)station
{
    [_dockedStation release];
    _dockedStation = [station weakRetain];
}

- (void)setTargetDockStationTo:(StationEntity*)value
{
    targetDockStation = value;
}

- (StationEntity*)getTargetDockStation
{
    return targetDockStation;
}

- (HeadUpDisplay*)hud
{
    return hud;
}

- (void)resetHud
{
    // set up defauld HUD for the ship
    const oo::PList shipDict = [[OOShipRegistry sharedRegistry] cxx_shipInfoForKey:oo::StdString([self shipDataKey])];
    const std::string hud_desc = shipDict.get<std::string>("hud", "hud.plist");
    if (![self cxx_switchHudTo:hud_desc])
        [self cxx_switchHudTo:"hud.plist"]; // ensure we have a HUD to fall back to
}

- (BOOL)cxx_switchHudTo:(const std::string&)hudFileName
{
    BOOL wasHidden = NO;
    BOOL wasCompassActive = YES;
    double scannerZoom = 1.0;
    NSUInteger lastMFD = 0;
    NSUInteger i;

    // (a nil name returns NO in the bridged -switchHudTo:)
    // is the HUD in the process of being rendered? If yes, set it to defer state and abort the switching now
    if (hud != nil && [hud isUpdating]) {
        [hud cxx_setDeferredHudName:hudFileName];
        return NO;
    }

    const oo::PList hudDict = [ResourceManager cxx_dictionaryFromFilesNamed:hudFileName inFolder:std::string("Config") andMerge:YES];
    // hud defined, but buggy?
    if (hudDict.isNull()) {
        OO_LOG("PlayerEntity.switchHudTo.failed", "HUD dictionary file {} to switch to not found or invalid.", hudFileName);
        return NO;
    }

    if (hud != nil) {
        // remember these values
        wasHidden = [hud isHidden];
        wasCompassActive = [hud isCompassActive];
        scannerZoom = [hud scannerZoom];
        lastMFD = activeMFD;
    }

    // buggy oxp could override hud.plist with a non-dictionary.
    if (!hudDict.isNull()) {
        [hud setHidden:YES]; // hide the hud while rebuilding it.
        DESTROY(hud);
        hud = [[HeadUpDisplay alloc] cxx_initWithDictionary:hudDict inFile:hudFileName];
        [hud cxx_resetGuis:hudDict];
        // reset zoom & hidden to what they were before the swich
        [hud setScannerZoom:scannerZoom];
        [hud setCompassActive:wasCompassActive];
        [hud setHidden:wasHidden];
        activeMFD = 0;
        const std::vector<std::optional<std::string>> savedMFDs = multiFunctionDisplaySettings;
        multiFunctionDisplaySettings.clear();
        for (i = 0; i < [hud mfdCount]; i++) {
            if (savedMFDs.size() > i) {
                multiFunctionDisplaySettings.push_back(savedMFDs[i]);
            } else {
                multiFunctionDisplaySettings.push_back(std::nullopt);
            }
        }
        if (lastMFD < [hud mfdCount])
            activeMFD = lastMFD;
    }

    return YES;
}

- (float)cxx_dialCustomFloat:(const std::string&)dialKey
{
    const auto found = customDialSettings.find(dialKey);
    return oo::PListGet<float>::from(found != customDialSettings.end() ? &found->second : nullptr, 0.0f);
}

- (std::string)cxx_dialCustomString:(const std::string&)dialKey
{
    const auto found = customDialSettings.find(dialKey);
    return oo::PListGet<std::string>::from(found != customDialSettings.end() ? &found->second : nullptr, "");
}

- (OOColor*)cxx_dialCustomColor:(const std::string&)dialKey
{
    const auto found = customDialSettings.find(dialKey);
    return [OOColor colorWithDescription:(found != customDialSettings.end() ? oo::ObjectFromPList(found->second) : nil)];
}

- (void)cxx_setDialCustom:(id)value forKey:(const std::string&)dialKey
{
    customDialSettings[dialKey] = oo::PListFrom(value); // non-plist values (colours...) are kept as Object nodes; nil is a null entry (it raised before)
}

- (void)setShowDemoShips:(BOOL)value
{
    showDemoShips = value;
}

- (BOOL)showDemoShips
{
    return showDemoShips;
}

- (float)maxForwardShieldLevel
{
    return max_forward_shield;
}

- (float)maxAftShieldLevel
{
    return max_aft_shield;
}

- (float)forwardShieldRechargeRate
{
    return forward_shield_recharge_rate;
}

- (float)aftShieldRechargeRate
{
    return aft_shield_recharge_rate;
}

- (void)setMaxForwardShieldLevel:(float)newValue
{
    max_forward_shield = newValue;
}

- (void)setMaxAftShieldLevel:(float)newValue
{
    max_aft_shield = newValue;
}

- (void)setForwardShieldRechargeRate:(float)newValue
{
    forward_shield_recharge_rate = newValue;
}

- (void)setAftShieldRechargeRate:(float)newValue
{
    aft_shield_recharge_rate = newValue;
}

- (GLfloat)forwardShieldLevel
{
    return forward_shield;
}

- (GLfloat)aftShieldLevel
{
    return aft_shield;
}

- (void)setForwardShieldLevel:(GLfloat)level
{
    forward_shield = OOClamp_0_max_f(level, [self maxForwardShieldLevel]);
}

- (void)setAftShieldLevel:(GLfloat)level
{
    aft_shield = OOClamp_0_max_f(level, [self maxAftShieldLevel]);
}

- (oo::PList)cxx_keyConfig
{
    // return keyconfig_settings;
    return oo::PList(keyconfig2_settings);
}

- (BOOL)isMouseControlOn
{
    return mouse_control_on;
}

- (GLfloat)dialRoll
{
    GLfloat result = flightRoll / max_flight_roll;
    if ((result < 1.0f) && (result > -1.0f))
        return result;
    if (result > 0.0f)
        return 1.0f;
    return -1.0f;
}

- (GLfloat)dialPitch
{
    GLfloat result = flightPitch / max_flight_pitch;
    if ((result < 1.0f) && (result > -1.0f))
        return result;
    if (result > 0.0f)
        return 1.0f;
    return -1.0f;
}

- (GLfloat)dialYaw
{
    GLfloat result = -flightYaw / max_flight_yaw;
    if ((result < 1.0f) && (result > -1.0f))
        return result;
    if (result > 0.0f)
        return 1.0f;
    return -1.0f;
}

- (GLfloat)dialSpeed
{
    GLfloat result = flightSpeed / maxFlightSpeed;
    return OOClamp_0_1_f(result);
}

- (GLfloat)dialHyperSpeed
{
    return flightSpeed / maxFlightSpeed;
}

- (GLfloat)dialForwardShield
{
    if (EXPECT_NOT([self maxForwardShieldLevel] <= 0)) {
        return 0.0;
    }
    GLfloat result = forward_shield / [self maxForwardShieldLevel];
    return OOClamp_0_1_f(result);
}

- (GLfloat)dialAftShield
{
    if (EXPECT_NOT([self maxAftShieldLevel] <= 0)) {
        return 0.0;
    }
    GLfloat result = aft_shield / [self maxAftShieldLevel];
    return OOClamp_0_1_f(result);
}

- (GLfloat)dialEnergy
{
    GLfloat result = energy / maxEnergy;
    return OOClamp_0_1_f(result);
}

- (GLfloat)dialMaxEnergy
{
    return maxEnergy;
}

- (GLfloat)dialFuel
{
    if (fuel <= 0.0f)
        return 0.0f;
    if (fuel > [self fuelCapacity])
        return 1.0f;
    return (GLfloat)fuel / (GLfloat)[self fuelCapacity];
}

- (GLfloat)dialHyperRange
{
    if (target_system_id == system_id && ![UNIVERSE inInterstellarSpace])
        return 0.0f;
    return [self fuelRequiredForJump] / (GLfloat)PLAYER_MAX_FUEL;
}

- (GLfloat)laserHeatLevel
{
    GLfloat result = (GLfloat)weapon_temp / (GLfloat)PLAYER_MAX_WEAPON_TEMP;
    return OOClamp_0_1_f(result);
}

- (GLfloat)laserHeatLevelAft
{
    GLfloat result = aft_weapon_temp / (GLfloat)PLAYER_MAX_WEAPON_TEMP;
    return OOClamp_0_1_f(result);
}

- (GLfloat)laserHeatLevelForward
{
    GLfloat result = forward_weapon_temp / (GLfloat)PLAYER_MAX_WEAPON_TEMP;
    // no need to check subents here
    return OOClamp_0_1_f(result);
}

- (GLfloat)laserHeatLevelPort
{
    GLfloat result = port_weapon_temp / PLAYER_MAX_WEAPON_TEMP;
    return OOClamp_0_1_f(result);
}

- (GLfloat)laserHeatLevelStarboard
{
    GLfloat result = starboard_weapon_temp / PLAYER_MAX_WEAPON_TEMP;
    return OOClamp_0_1_f(result);
}

- (GLfloat)dialAltitude
{
    if ([self isDocked])
        return 0.0f;

    // find nearest planet type entity...
    assert(UNIVERSE != nil);

    Entity* nearestPlanet = [self findNearestStellarBody];
    if (nearestPlanet == nil)
        return 1.0f;

    GLfloat zd = nearestPlanet->zero_distance;
    GLfloat cr = nearestPlanet->collision_radius;
    GLfloat alt = sqrt(zd) - cr;

    return OOClamp_0_1_f(alt / (GLfloat)PLAYER_DIAL_MAX_ALTITUDE);
}

- (double)clockTime
{
    return ship_clock;
}

- (double)clockTimeAdjusted
{
    return ship_clock + ship_clock_adjust;
}

- (BOOL)clockAdjusting
{
    return ship_clock_adjust > 0;
}

- (void)addToAdjustTime:(double)seconds
{
    ship_clock_adjust += seconds;
}

- (double)escapePodRescueTime
{
    return escape_pod_rescue_time;
}

- (void)setEscapePodRescueTime:(double)seconds
{
    escape_pod_rescue_time = seconds;
}

- (std::string)cxx_dial_clock
{
    return cxx_ClockToString(ship_clock, ship_clock_adjust > 0);
}

- (std::string)cxx_dial_clock_adjusted
{
    return cxx_ClockToString(ship_clock + ship_clock_adjust, NO);
}

- (std::string)cxx_dial_fpsinfo
{
    unsigned fpsVal = fps_counter;
    return oo::str::format("FPS: %3d", fpsVal);
}

- (std::string)cxx_dial_objinfo
{
    std::string result = oo::str::format("Entities: %3zu", [UNIVERSE entityCount]);
#ifdef OO_DEBUG_MONITOR_ENABLED
    result = oo::str::format("%s (%d, %zu KiB, avg %zu bytes)", result.c_str(), gLiveEntityCount, gTotalEntityMemory >> 10, gTotalEntityMemory / gLiveEntityCount);
#endif

    return result;
}

- (unsigned)countMissiles
{
    unsigned n_missiles = 0;
    unsigned i;
    for (i = 0; i < max_missiles; i++) {
        if (missile_entity[i])
            n_missiles++;
    }
    return n_missiles;
}

- (OOMissileStatus)dialMissileStatus
{
    if ([self weaponsOnline]) {
        return missile_status;
    } else {
        // Invariant/safety interlock: weapons offline implies missiles safe. -- Ahruman 2012-07-21
        if (missile_status != MISSILE_STATUS_SAFE) {
            OO_LOG_ERR("player.missilesUnsafe", "{}", "Missile state is not SAFE when weapons are offline. This is a bug, please report it.");
            [self safeAllMissiles];
        }
        return MISSILE_STATUS_SAFE;
    }
}

- (BOOL)canScoop:(ShipEntity*)other
{
    if (specialCargo)
        return NO;
    return [super canScoop:other];
}

- (OOFuelScoopStatus)dialFuelScoopStatus
{
    // need to account for the different ways of calculating cargo on board when docked/in-flight
    OOCargoQuantity cargoOnBoard = [self status] == STATUS_DOCKED ? current_cargo : (OOCargoQuantity)cargo.size();
    if ([self hasScoop]) {
        if (scoopsActive)
            return SCOOP_STATUS_ACTIVE;
        if (cargoOnBoard >= [self maxAvailableCargoSpace] || specialCargo)
            return SCOOP_STATUS_FULL_HOLD;
        return SCOOP_STATUS_OKAY;
    } else {
        return SCOOP_STATUS_NOT_INSTALLED;
    }
}

- (float)fuelLeakRate
{
    return fuel_leak_rate;
}

- (void)setFuelLeakRate:(float)value
{
    fuel_leak_rate = fmax(value, 0.0f);
}

- (std::vector<std::string>*)cxx_commLog
{
    assert(kCommLogTrimSize < kCommLogTrimThreshold);

    const std::size_t count = commLog.size();
    if (count >= kCommLogTrimThreshold) {
        commLog.erase(commLog.begin(), commLog.begin() + static_cast<std::ptrdiff_t>(count - kCommLogTrimSize));
    }

    return &commLog; // (a nil receiver gives nullptr)
}

- (std::vector<std::string>)cxx_roleWeights
{
    return roleWeights;
}

- (void)addRoleForAggression:(ShipEntity*)victim
{
    if ([victim isExplicitlyUnpiloted] || [victim isHulk] || [victim hasHostileTarget] || [[victim primaryAggressor] isPlayer]) {
        return;
    }
    std::optional<std::string> role;
    if (oo::OptionalString([victim primaryRole]) == "escape-capsule") {
        role = "assassin-player";
    } else if ([victim bounty] > 0) {
        role = "hunter";
    } else if ([victim isPirateVictim]) {
        role = "pirate";
    } else if ([UNIVERSE role:[self primaryRole] isInCategory:@"oolite-hunter"] || [victim scanClass] == CLASS_POLICE) {
        role = "pirate-interceptor";
    }
    if (!role.has_value()) {
        return;
    }
    NSUInteger times = RoleFlagCount(roleWeightFlags, *role);
    times++;
    roleWeightFlags.insert_or_assign(*role, oo::PList::signedInteger(static_cast<std::int64_t>(times)));
    if ((times & (times - 1)) == 0) // is power of 2
    {
        [self cxx_addRoleToPlayer:*role];
    }
}

- (void)addRoleForMining
{
    const std::string role = "miner";
    NSUInteger times = RoleFlagCount(roleWeightFlags, role);
    times++;
    roleWeightFlags.insert_or_assign(role, oo::PList::signedInteger(static_cast<std::int64_t>(times)));
    if ((times & (times - 1)) == 0) // is power of 2
    {
        [self cxx_addRoleToPlayer:role];
    }
}

- (void)cxx_addRoleToPlayer:(const std::string&)role
{
    NSUInteger slot = Ranrot() & ([self maxPlayerRoles] - 1);
    [self cxx_addRoleToPlayer:role inSlot:slot];
}

- (void)cxx_addRoleToPlayer:(const std::string&)role inSlot:(NSUInteger)slot
{
    if (slot >= [self maxPlayerRoles]) {
        slot = [self maxPlayerRoles] - 1;
    }
    if (slot >= roleWeights.size()) {
        roleWeights.push_back(role);
    } else {
        roleWeights[slot] = role;
    }
}

- (void)clearRoleFromPlayer:(BOOL)includingLongRange
{
    NSUInteger slot = Ranrot() % roleWeights.size();
    if (!includingLongRange) {
        const std::string& role = roleWeights[slot];
        // long range roles cleared at 1/2 normal rate
        if (oo::str::hasSuffix(role, "+") && randf() > 0.5) {
            return;
        }
    }
    roleWeights[slot] = "player-unknown";
}

- (void)clearRolesFromPlayer:(float)chance
{
    NSUInteger i, count = roleWeights.size();
    for (i = 0; i < count; i++) {
        if (randf() < chance) {
            roleWeights[i] = "player-unknown";
        }
    }
}

- (NSUInteger)maxPlayerRoles
{
    if (ship_kills >= 6400) {
        return 32;
    } else if (ship_kills >= 128) {
        return 16;
    } else {
        return 8;
    }
}

- (void)updateSystemMemory
{
    OOSystemID sys = [self currentSystemID];
    if (sys < 0) {
        return;
    }
    NSUInteger memory = 4;
    if (ship_kills >= 6400) {
        memory = 32;
    } else if (ship_kills >= 256) {
        memory = 16;
    } else if (ship_kills >= 64) {
        memory = 8;
    }
    if (roleSystemList.size() >= memory) {
        roleSystemList.erase(roleSystemList.begin());
    }
    roleSystemList.push_back(sys);
}

- (Entity*)compassTarget
{
    Entity* result = [compassTarget weakRefUnderlyingObject];
    if (result == nil) {
        DESTROY(compassTarget);
        return nil;
    }
    return result;
}

- (void)setCompassTarget:(Entity*)value
{
    [compassTarget release];
    compassTarget = [value weakRetain];
}

- (void)validateCompassTarget
{
    OOSunEntity* the_sun = [UNIVERSE sun];
    OOPlanetEntity* the_planet = [UNIVERSE planet];
    StationEntity* the_station = [UNIVERSE station];
    Entity* the_target = [self primaryTarget];
    Entity<OOBeaconEntity>* beacon = [self nextBeacon];
    if ([self isInSpace] && the_sun && the_planet // be in a system
        && ![the_sun goneNova]) // and the system has not been novabombed
    {
        Entity* new_target = nil;
        OOAegisStatus aegis = [self checkForAegis];

        switch ([self compassMode]) {
        case COMPASS_MODE_INACTIVE:
            break;

        case COMPASS_MODE_BASIC:
            if ((aegis == AEGIS_CLOSE_TO_MAIN_PLANET || aegis == AEGIS_IN_DOCKING_RANGE) && the_station) {
                new_target = the_station;
            } else {
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
            new_target = the_sun;
            break;

        case COMPASS_MODE_TARGET:
            new_target = the_target;
            break;

        case COMPASS_MODE_BEACONS:
            new_target = beacon;
            break;
        }

        if (new_target == nil || [new_target status] < STATUS_ACTIVE || [new_target status] == STATUS_IN_HOLD) {
            [self setCompassMode:COMPASS_MODE_PLANET];
            new_target = the_planet;
        }

        if (EXPECT_NOT(new_target != [self compassTarget])) {
            [self setCompassTarget:new_target];
            [self doScriptEvent:OOJSID("compassTargetChanged") withArguments:oo::ObjectFromPList(oo::PList(oo::PList::Array { oo::PListObject(new_target), oo::PListFrom(OOStringFromCompassMode([self compassMode])) }))];
        }
    }
}

- (std::optional<std::string>)cxx_compassTargetLabel
{
    switch (compassMode) {
    case COMPASS_MODE_INACTIVE:
        return "";
    case COMPASS_MODE_BASIC:
        return "";
    case COMPASS_MODE_BEACONS: {
        Entity* target = [self compassTarget];
        if (target) {
            return oo::OptionalString([(Entity<OOBeaconEntity>*)target beaconLabel]);
        }
        return "";
    }
    case COMPASS_MODE_PLANET:
        return oo::OptionalString([[UNIVERSE planet] name]);
    case COMPASS_MODE_SUN:
        return oo::OptionalString([[UNIVERSE sun] name]);
    case COMPASS_MODE_STATION:
        return oo::OptionalString([[UNIVERSE station] displayName]);
    case COMPASS_MODE_TARGET:
        return oo::StdString(DESC(@"oolite-beacon-label-target"));
    }
    return "";
}

- (OOCompassMode)compassMode
{
    return compassMode;
}

- (void)setCompassMode:(OOCompassMode)value
{
    compassMode = value;
}

- (void)setPrevCompassMode
{
    OOAegisStatus aegis = AEGIS_NONE;
    Entity<OOBeaconEntity>* beacon = nil;

    switch (compassMode) {
    case COMPASS_MODE_INACTIVE:
    case COMPASS_MODE_BASIC:
    case COMPASS_MODE_PLANET:
        beacon = [UNIVERSE lastBeacon];
        while (beacon != nil && [beacon isJammingScanning]) {
            beacon = [beacon prevBeacon];
        }
        [self setNextBeacon:beacon];

        if (beacon != nil) {
            [self setCompassMode:COMPASS_MODE_BEACONS];
            break;
        }
        // else fall through to switch to target mode.

    case COMPASS_MODE_BEACONS:
        beacon = [self nextBeacon];
        do {
            beacon = [beacon prevBeacon];
        } while (beacon != nil && [beacon isJammingScanning]);
        [self setNextBeacon:beacon];

        if (beacon == nil) {
            if ([self primaryTarget]) {
                [self setCompassMode:COMPASS_MODE_TARGET];
            } else {
                [self setCompassMode:COMPASS_MODE_SUN];
            }
            break;
        }
        break;

    case COMPASS_MODE_TARGET:
        [self setCompassMode:COMPASS_MODE_SUN];
        break;

    case COMPASS_MODE_SUN:
        aegis = [self checkForAegis];
        if (aegis == AEGIS_CLOSE_TO_MAIN_PLANET || aegis == AEGIS_IN_DOCKING_RANGE) {
            [self setCompassMode:COMPASS_MODE_STATION];
        } else {
            [self setCompassMode:COMPASS_MODE_PLANET];
        }
        break;

    case COMPASS_MODE_STATION:
        [self setCompassMode:COMPASS_MODE_PLANET];
        break;
    }
}

- (void)setNextCompassMode
{
    OOAegisStatus aegis = AEGIS_NONE;
    Entity<OOBeaconEntity>* beacon = nil;

    switch (compassMode) {
    case COMPASS_MODE_INACTIVE:
    case COMPASS_MODE_BASIC:
    case COMPASS_MODE_PLANET:
        aegis = [self checkForAegis];
        if ([UNIVERSE station] && (aegis == AEGIS_CLOSE_TO_MAIN_PLANET || aegis == AEGIS_IN_DOCKING_RANGE)) {
            [self setCompassMode:COMPASS_MODE_STATION];
        } else {
            [self setCompassMode:COMPASS_MODE_SUN];
        }
        break;

    case COMPASS_MODE_STATION:
        [self setCompassMode:COMPASS_MODE_SUN];
        break;

    case COMPASS_MODE_SUN:
        if ([self primaryTarget]) {
            [self setCompassMode:COMPASS_MODE_TARGET];
            break;
        }
        // else fall through to switch to beacon mode.

    case COMPASS_MODE_TARGET:
        beacon = [UNIVERSE firstBeacon];
        while (beacon != nil && [beacon isJammingScanning]) {
            beacon = [beacon nextBeacon];
        }
        [self setNextBeacon:beacon];

        if (beacon != nil)
            [self setCompassMode:COMPASS_MODE_BEACONS];
        else
            [self setCompassMode:COMPASS_MODE_PLANET];
        break;

    case COMPASS_MODE_BEACONS:
        beacon = [self nextBeacon];
        do {
            beacon = [beacon nextBeacon];
        } while (beacon != nil && [beacon isJammingScanning]);
        [self setNextBeacon:beacon];

        if (beacon == nil) {
            [self setCompassMode:COMPASS_MODE_PLANET];
        }
        break;
    }
}

- (NSUInteger)activeMissile
{
    return activeMissile;
}

- (void)setActiveMissile:(NSUInteger)value
{
    activeMissile = value;
}

- (NSUInteger)dialMaxMissiles
{
    return max_missiles;
}

- (BOOL)dialIdentEngaged
{
    return ident_engaged;
}

- (void)setDialIdentEngaged:(BOOL)newValue
{
    ident_engaged = !!newValue;
}

- (std::optional<std::string>)cxx_specialCargo
{
    return specialCargo;
}

- (std::optional<std::string>)cxx_dialTargetName
{
    Entity* target_entity = [self primaryTarget];
    std::optional<std::string> result;

    if (target_entity == nil) {
        result = oo::StdString(DESC(@"no-target-string"));
    }

    if ([target_entity respondsToSelector:@selector(identFromShip:)]) {
        result = oo::OptionalString([(ShipEntity*)target_entity identFromShip:self]);
    }

    if (!result.has_value())
        result = oo::StdString(DESC(@"unknown-target"));

    return result;
}

- (std::vector<std::optional<std::string>>)cxx_multiFunctionDisplayList
{
    return multiFunctionDisplaySettings;
}

- (std::optional<std::string>)cxx_multiFunctionText:(NSUInteger)i
{
    if (i >= multiFunctionDisplaySettings.size() || !multiFunctionDisplaySettings[i].has_value()) {
        return std::nullopt;
    }
    const auto text = multiFunctionDisplayText.find(*multiFunctionDisplaySettings[i]);
    if (text == multiFunctionDisplayText.end())
        return std::nullopt;
    return text->second;
}

- (void)cxx_setMultiFunctionText:(const std::optional<std::string>&)text forKey:(const std::optional<std::string>&)key
{
    if (text.has_value()) {
        if (key.has_value())
            multiFunctionDisplayText[*key] = *text; // (a nil key raised before)
    } else if (key.has_value()) {
        multiFunctionDisplayText.erase(*key);
        // and blank any MFDs currently using it
        std::replace(multiFunctionDisplaySettings.begin(), multiFunctionDisplaySettings.end(), key, std::optional<std::string>());
    }
}

- (BOOL)cxx_setMultiFunctionDisplay:(NSUInteger)index toKey:(const std::optional<std::string>&)key
{
    if (index >= [hud mfdCount]) {
        // is first inactive display
        const auto inactive = std::find(multiFunctionDisplaySettings.begin(), multiFunctionDisplaySettings.end(), std::nullopt);
        if (inactive == multiFunctionDisplaySettings.end()) {
            return NO;
        }
        index = static_cast<NSUInteger>(inactive - multiFunctionDisplaySettings.begin());
    }

    if (index < [hud mfdCount]) {
        multiFunctionDisplaySettings.at(index) = key; // nullopt = inactive
        return YES;
    } else {
        return NO;
    }
}

- (void)cycleNextMultiFunctionDisplay:(NSUInteger)index
{
    if ([[self hud] mfdCount] == 0)
        return;
    std::vector<std::string> keys; // byte order (was -allKeys hash order)
    for (const auto& entry : multiFunctionDisplayText)
        keys.push_back(entry.first);
    std::optional<std::string> key;
    if (keys.empty()) {
        [self cxx_setMultiFunctionDisplay:index toKey:std::nullopt];
        return;
    }
    const std::optional<std::string> current = multiFunctionDisplaySettings.at(index);
    if (!current.has_value()) {
        key = keys[0];
        [self cxx_setMultiFunctionDisplay:index toKey:key];
    } else {
        const auto currentKey = std::find(keys.begin(), keys.end(), *current);
        const NSUInteger cIndex = (currentKey != keys.end()) ? static_cast<NSUInteger>(currentKey - keys.begin()) : NSNotFound;
        if (cIndex == NSNotFound || cIndex + 1 >= keys.size()) {
            key = std::nullopt;
            [self cxx_setMultiFunctionDisplay:index toKey:std::nullopt];
        } else {
            key = keys[cIndex + 1];
            [self cxx_setMultiFunctionDisplay:index toKey:key];
        }
    }
    JSContext* context = OOJSAcquireContext();
    OOJSVal keyVal = OOJSValueFromNativeObject(context, oo::NSStringOrNil(key));
    ShipScriptEvent(context, self, "mfdKeyChanged", OOJSValueFromDouble(context, activeMFD), keyVal);
    OOJSRelinquishContext(context);
}

- (void)cyclePreviousMultiFunctionDisplay:(NSUInteger)index
{
    if ([[self hud] mfdCount] == 0)
        return;
    std::vector<std::string> keys; // byte order (was -allKeys hash order)
    for (const auto& entry : multiFunctionDisplayText)
        keys.push_back(entry.first);
    std::optional<std::string> key;
    if (keys.empty()) {
        [self cxx_setMultiFunctionDisplay:index toKey:std::nullopt];
        return;
    }
    const std::optional<std::string> current = multiFunctionDisplaySettings.at(index);
    if (!current.has_value()) {
        key = keys[keys.size() - 1];
        [self cxx_setMultiFunctionDisplay:index toKey:key];
    } else {
        const auto currentKey = std::find(keys.begin(), keys.end(), *current);
        const NSUInteger cIndex = (currentKey != keys.end()) ? static_cast<NSUInteger>(currentKey - keys.begin()) : NSNotFound;
        if (cIndex == NSNotFound || cIndex == 0) {
            key = std::nullopt;
            [self cxx_setMultiFunctionDisplay:index toKey:std::nullopt];
        } else {
            key = keys[cIndex - 1];
            [self cxx_setMultiFunctionDisplay:index toKey:key];
        }
    }
    JSContext* context = OOJSAcquireContext();
    OOJSVal keyVal = OOJSValueFromNativeObject(context, oo::NSStringOrNil(key));
    ShipScriptEvent(context, self, "mfdKeyChanged", OOJSValueFromDouble(context, activeMFD), keyVal);
    OOJSRelinquishContext(context);
}

- (void)selectNextMultiFunctionDisplay
{
    if ([[self hud] mfdCount] == 0)
        return;
    activeMFD = (activeMFD + 1) % [[self hud] mfdCount];
    NSUInteger mfdID = activeMFD + 1;
    [UNIVERSE addMessage:OOExpandKey(@"mfd-N-selected", mfdID) forCount:3.0];
    JSContext* context = OOJSAcquireContext();
    ShipScriptEvent(context, self, "selectedMFDChanged", OOJSValueFromDouble(context, activeMFD));
    OOJSRelinquishContext(context);
}

- (void)selectPreviousMultiFunctionDisplay
{
    if ([[self hud] mfdCount] == 0)
        return;
    if (activeMFD == 0) {
        activeMFD = ([[self hud] mfdCount] - 1);
    } else {
        activeMFD = (activeMFD - 1);
    }
    NSUInteger mfdID = activeMFD + 1;
    [UNIVERSE addMessage:OOExpandKey(@"mfd-N-selected", mfdID) forCount:3.0];
    JSContext* context = OOJSAcquireContext();
    ShipScriptEvent(context, self, "selectedMFDChanged", OOJSValueFromDouble(context, activeMFD));
    OOJSRelinquishContext(context);
}

- (NSUInteger)activeMFD
{
    return activeMFD;
}

- (ShipEntity*)missileForPylon:(NSUInteger)value
{
    if (value < max_missiles)
        return missile_entity[value];
    return nil;
}

- (void)safeAllMissiles
{
    //	sets all missile targets to NO_TARGET

    unsigned i;
    for (i = 0; i < max_missiles; i++) {
        if (missile_entity[i] && [missile_entity[i] primaryTarget] != nil)
            [missile_entity[i] removeTarget:nil];
    }
    missile_status = MISSILE_STATUS_SAFE;
}

- (void)tidyMissilePylons
{
    // Make sure there's no gaps between missiles, synchronise missile_entity & missile_list.
    int i, pylon = 0;
    OO_LOG("missile.tidying.debug", "Tidying fitted {} of possible {} missiles", missiles, PLAYER_MAX_MISSILES);
    for (i = 0; i < PLAYER_MAX_MISSILES; i++) {
        OO_LOG("missile.tidying.debug", "{} {} {}", i, oo::DescriptionOf(missile_entity[i]), oo::DescriptionOf(missile_list[i]));
        if (missile_entity[i] != nil) {
            missile_entity[pylon] = missile_entity[i];
            missile_list[pylon] = [OOEquipmentType equipmentTypeWithIdentifier:[missile_entity[i] primaryRole]];
            pylon++;
        }
    }

    // Now clean up the remainder of the pylons.
    for (i = pylon; i < PLAYER_MAX_MISSILES; i++) {
        missile_entity[i] = nil;
        // not strictly needed, but helps clear things up
        missile_list[i] = nil;
    }
}

- (void)selectNextMissile
{
    if (![self weaponsOnline])
        return;

    unsigned i;
    for (i = 1; i < max_missiles; i++) {
        int next_missile = (activeMissile + i) % max_missiles;
        if (missile_entity[next_missile]) {
            // If we don't have the multi-targeting module installed, clear the active missiles' target
            if (![self hasEquipmentItemProviding:@"EQ_MULTI_TARGET"] && [missile_entity[activeMissile] isMissile]) {
                [missile_entity[activeMissile] removeTarget:nil];
            }

            // Set next missile to active
            [self setActiveMissile:next_missile];

            if (missile_status != MISSILE_STATUS_SAFE) {
                missile_status = MISSILE_STATUS_ARMED;

                // If the newly active pylon contains a missile then work out its target, if any
                if ([missile_entity[activeMissile] isMissile]) {
                    if ([self hasEquipmentItemProviding:@"EQ_MULTI_TARGET"] && ([missile_entity[next_missile] primaryTarget] != nil)) {
                        // copy the missile's target
                        [self addTarget:[missile_entity[next_missile] primaryTarget]];
                        missile_status = MISSILE_STATUS_TARGET_LOCKED;
                    } else if ([self primaryTarget] != nil) {
                        // never inherit target if we have EQ_MULTI_TARGET installed! [ Bug #16221 : Targeting enhancement regression ]
                        /* CIM: seems okay to do this when launching a
                         * missile to stop multi-target being a bit
                         * irritating in a fight - 20/8/2014 */
                        if ([self hasEquipmentItemProviding:@"EQ_MULTI_TARGET"] && !launchingMissile) {
                            [self noteLostTarget];
                            DESTROY(_primaryTarget);
                        } else {
                            [missile_entity[activeMissile] addTarget:[self primaryTarget]];
                            missile_status = MISSILE_STATUS_TARGET_LOCKED;
                        }
                    }
                }
            }
            return;
        }
    }
}

- (void)clearAlertFlags
{
    alertFlags = 0;
}

- (int)alertFlags
{
    return alertFlags;
}

- (void)setAlertFlag:(int)flag to:(BOOL)value
{
    if (value) {
        alertFlags |= flag;
    } else {
        int comp = ~flag;
        alertFlags &= comp;
    }
}

// used by Javascript and the distinction is important for NPCs
- (OOAlertCondition)realAlertCondition
{
    return [self alertCondition];
}

- (OOAlertCondition)alertCondition
{
    OOAlertCondition old_alert_condition = alertCondition;
    alertCondition = ALERT_CONDITION_GREEN;

    [self setAlertFlag:ALERT_FLAG_DOCKED to:[self status] == STATUS_DOCKED];

    if (alertFlags & ALERT_FLAG_DOCKED) {
        alertCondition = ALERT_CONDITION_DOCKED;
    } else {
        if (alertFlags != 0) {
            alertCondition = ALERT_CONDITION_YELLOW;
        }
        if (alertFlags > ALERT_FLAG_YELLOW_LIMIT) {
            alertCondition = ALERT_CONDITION_RED;
        }
    }
    if ((alertCondition == ALERT_CONDITION_RED) && (old_alert_condition < ALERT_CONDITION_RED)) {
        [self playAlertConditionRed];
    }

    return alertCondition;
}

- (OOPlayerFleeingStatus)fleeingStatus
{
    return fleeing_status;
}

/////////////////////////////////////////////////////////////////////

- (void)interpretAIMessage:(id)ms // shared selector (proposed ADR-0043): an Objective-C string
{
    const std::optional<std::string> message = oo::OptionalString(ms);

    if ((message == "HOLD_FULL")) {
        [self playHoldFull];
        [UNIVERSE addMessage:DESC(@"hold-full") forCount:4.5];
    }

    if ((message == "INCOMING_MISSILE")) {
        if ([self primaryAggressor] != nil) {
            [self playIncomingMissile:HPVectorToVector([[self primaryAggressor] position])];
        } else {
            [self playIncomingMissile:kZeroVector];
        }
        [UNIVERSE addMessage:DESC(@"incoming-missile") forCount:4.5];
    }

    if ((message == "ENERGY_LOW")) {
        [UNIVERSE addMessage:DESC(@"energy-low") forCount:6.0];
    }

    if ((message == "ECM") && ![self isDocked])
        [self playHitByECMSound];

    if ((message == "DOCKING_REFUSED") && [self status] == STATUS_AUTOPILOT_ENGAGED) {
        [self playDockingDenied];
        [UNIVERSE addMessage:DESC(@"autopilot-denied") forCount:4.5];
        autopilot_engaged = NO;
        [self resetAutopilotAI];
        DESTROY(_primaryTarget);
        [self setStatus:STATUS_IN_FLIGHT];
        [[OOMusicController sharedController] stopDockingMusic];
        [self doScriptEvent:OOJSID("playerDockingRefused")];
    }

    // aegis messages to advanced compass so in planet mode it behaves like the old compass
    if (compassMode != COMPASS_MODE_BASIC) {
        if ((message == "AEGIS_CLOSE_TO_MAIN_PLANET") && (compassMode == COMPASS_MODE_PLANET)) {
            [self playAegisCloseToPlanet];
            [self setCompassMode:COMPASS_MODE_STATION];
        }
        if ((message == "AEGIS_IN_DOCKING_RANGE") && (compassMode == COMPASS_MODE_PLANET)) {
            [self playAegisCloseToStation];
            [self setCompassMode:COMPASS_MODE_STATION];
        }
        if ((message == "AEGIS_NONE") && (compassMode == COMPASS_MODE_STATION)) {
            [self setCompassMode:COMPASS_MODE_PLANET];
        }
    }
}

- (BOOL)mountMissile:(ShipEntity*)missile
{
    if (missile == nil)
        return NO;

    unsigned i;
    for (i = 0; i < max_missiles; i++) {
        if (missile_entity[i] == nil) {
            missile_entity[i] = [missile retain];
            missile_list[missiles] = [OOEquipmentType equipmentTypeWithIdentifier:[missile primaryRole]];
            missiles++;
            if (missiles == 1)
                [self setActiveMissile:0]; // auto select the first purchased missile
            return YES;
        }
    }

    return NO;
}

- (BOOL)cxx_mountMissileWithRole:(const std::string&)role
{
    if ([self missileCount] >= [self missileCapacity])
        return NO;
    return [self mountMissile:[[UNIVERSE newShipWithRole:oo::NSStringFrom(role)] autorelease]];
}

- (ShipEntity*)fireMissile
{
    ShipEntity* missile = missile_entity[activeMissile]; // retain count is 1
    const std::optional<std::string> identifier = oo::OptionalString([missile primaryRole]); // a copy: the missile goes below
    ShipEntity* firedMissile = nil;

    if (missile == nil)
        return nil;

    if (![self weaponsOnline])
        return nil;

    // check if we were cloaked before firing the missile - can't use
    // cloaking_device_active directly because fireMissilewithIdentifier: andTarget:
    // will reset it in case passive cloak is set - Nikos 20130313
    BOOL cloakedPriorToFiring = cloaking_device_active;

    launchingMissile = YES;
    replacingMissile = NO;

    if ([missile isMine] && (missile_status != MISSILE_STATUS_SAFE)) {
        firedMissile = [self launchMine:missile];
        if (!replacingMissile)
            [self removeFromPylon:activeMissile];
        if (firedMissile != nil)
            [self cxx_playMineLaunched:[self missileLaunchPosition] weaponIdentifier:identifier.value_or(std::string())];
    } else {
        if (missile_status != MISSILE_STATUS_TARGET_LOCKED)
            return nil;
        //  release this before creating it anew in fireMissileWithIdentifier
        firedMissile = [self cxx_fireMissileWithIdentifier:identifier andTarget:[missile primaryTarget]];

        if (firedMissile != nil) {
            if (!replacingMissile)
                [self removeFromPylon:activeMissile];
            [self cxx_playMissileLaunched:[self missileLaunchPosition] weaponIdentifier:identifier.value_or(std::string())];
        }
    }

    if (cloakedPriorToFiring && cloakPassive) {
        // fireMissilewithIdentifier: andTarget: has already taken care of deactivating
        // the cloak in the case of missiles by the time we get here, but explicitly
        // calling deactivateCloakingDevice is needed in order to be covered fully with mines too
        [self deactivateCloakingDevice];
    }

    replacingMissile = NO;
    launchingMissile = NO;

    return firedMissile;
}

- (ShipEntity*)launchMine:(ShipEntity*)mine
{
    if (!mine)
        return nil;

    if (![self weaponsOnline])
        return nil;

    [mine setOwner:self];
    [mine setBehaviour:BEHAVIOUR_IDLE];
    [self dumpItem:mine]; // includes UNIVERSE addEntity: CLASS_CARGO, STATUS_IN_FLIGHT, AI state GLOBAL ( the last one starts the timer !)
    [mine setScanClass:CLASS_MINE];

    float mine_speed = 500.0f;
    Vector mvel = vector_subtract([mine velocity], vector_multiply_scalar(v_forward, mine_speed));
    [mine setVelocity:mvel];
    [self doScriptEvent:OOJSID("shipReleasedEquipment") withArgument:mine];
    return mine;
}

- (BOOL)cxx_assignToActivePylon:(const std::string&)equipmentKey
{
    if (!launchingMissile)
        return NO;

    OOEquipmentType* eqType = nil;

    if (oo::str::hasSuffix(equipmentKey, "_DAMAGED")) {
        return NO;
    } else {
        eqType = [OOEquipmentType equipmentTypeWithIdentifier:oo::NSStringFrom(equipmentKey)];
    }

    // missiles with techlevel above 99 (kOOVariableTechLevel) are never available to the player
    if (![eqType isMissileOrMine] || [eqType effectiveTechLevel] > kOOVariableTechLevel) {
        return NO;
    }

    ShipEntity* amiss = [UNIVERSE newShipWithRole:oo::NSStringFrom(equipmentKey)];

    if (!amiss)
        return NO;

    // replace the missile now.
    [missile_entity[activeMissile] release];
    missile_entity[activeMissile] = amiss;
    missile_list[activeMissile] = eqType;

    // make sure the new missile is properly activated.
    if (activeMissile > 0)
        activeMissile--;
    else
        activeMissile = max_missiles - 1;
    [self selectNextMissile];

    replacingMissile = YES;

    return YES;
}

- (BOOL)activateCloakingDevice
{
    if (![self hasCloakingDevice])
        return NO;

    if ([super activateCloakingDevice]) {
        [UNIVERSE setCurrentPostFX:OO_POSTFX_CLOAK];
        [UNIVERSE addMessage:DESC(@"cloak-on") forCount:2];
        [self playCloakingDeviceOn];
        return YES;
    } else {
        [UNIVERSE addMessage:DESC(@"cloak-low-juice") forCount:3];
        [self playCloakingDeviceInsufficientEnergy];
        return NO;
    }
}

- (void)deactivateCloakingDevice
{
    if (![self hasCloakingDevice])
        return;

    [super deactivateCloakingDevice];
    [UNIVERSE terminatePostFX:OO_POSTFX_CLOAK];
    [UNIVERSE addMessage:DESC(@"cloak-off") forCount:2];
    [self playCloakingDeviceOff];
}

/* Scanner fuzziness is entirely cosmetic - it doesn't affect the
 * player's actual target locks */
- (double)scannerFuzziness
{
    double fuzz = 0.0;

    /* Fuzziness from ECM bursts */
    if (last_ecm_time > 0.0) {
        double since = [UNIVERSE getTime] - last_ecm_time;
        if (since < SCANNER_ECM_FUZZINESS) {
            fuzz += (SCANNER_ECM_FUZZINESS - since) * (SCANNER_ECM_FUZZINESS - since) * 500.0;
        }
    }
    /* Other causes could go here */

    return fuzz;
}

- (void)noticeECM
{
    last_ecm_time = [UNIVERSE getTime];
}

- (BOOL)fireECM
{
    if ([super fireECM]) {
        ecm_in_operation = YES;
        ecm_start_time = [UNIVERSE getTime];
        return YES;
    } else {
        return NO;
    }
}

- (OOEnergyUnitType)installedEnergyUnitType
{
    if ([self hasEquipmentItem:@"EQ_NAVAL_ENERGY_UNIT"])
        return ENERGY_UNIT_NAVAL;
    if ([self hasEquipmentItem:@"EQ_ENERGY_UNIT"])
        return ENERGY_UNIT_NORMAL;
    return ENERGY_UNIT_NONE;
}

- (OOEnergyUnitType)energyUnitType
{
    if ([self hasEquipmentItem:@"EQ_NAVAL_ENERGY_UNIT"])
        return ENERGY_UNIT_NAVAL;
    if ([self hasEquipmentItem:@"EQ_ENERGY_UNIT"])
        return ENERGY_UNIT_NORMAL;
    if ([self hasEquipmentItem:@"EQ_NAVAL_ENERGY_UNIT_DAMAGED"])
        return ENERGY_UNIT_NAVAL_DAMAGED;
    if ([self hasEquipmentItem:@"EQ_ENERGY_UNIT_DAMAGED"])
        return ENERGY_UNIT_NORMAL_DAMAGED;
    return ENERGY_UNIT_NONE;
}

- (void)currentWeaponStats
{
    OOWeaponType currentWeapon = [self currentWeapon];
    // Did find & correct a minor mismatch between player and NPC weapon stats. This is the resulting code - Kaks 20101027

    // Basic stats: weapon_damage & weaponRange (weapon_recharge_rate is not used by the player)
    [self setWeaponDataFromType:currentWeapon];
}

- (BOOL)weaponsOnline
{
    return weapons_online;
}

- (void)setWeaponsOnline:(BOOL)newValue
{
    weapons_online = !!newValue;
    if (!weapons_online)
        [self safeAllMissiles];
}

- (std::vector<Vector>)cxx_currentLaserOffset
{
    return [self cxx_laserPortOffset:currentWeaponFacing];
}

- (BOOL)fireMainWeapon
{
    OOWeaponType weapon_to_be_fired = [self currentWeapon];

    if (![self weaponsOnline]) {
        return NO;
    }

    if (weapon_temp / PLAYER_MAX_WEAPON_TEMP >= WEAPON_COOLING_CUTOUT) {
        [self playWeaponOverheated:oo::PListView([self currentLaserOffset]).at<Vector>(0)];
        [UNIVERSE addMessage:DESC(@"weapon-overheat") forCount:3.0];
        return NO;
    }

    if (isWeaponNone(weapon_to_be_fired)) {
        return NO;
    }

    [self currentWeaponStats];

    NSUInteger multiplier = 1;
    if (_multiplyWeapons) {
        // multiple fitted
        multiplier = [[self laserPortOffset:currentWeaponFacing] count];
    }

    if (energy <= weapon_energy_use * multiplier) {
        [UNIVERSE addMessage:DESC(@"weapon-out-of-juice") forCount:3.0];
        return NO;
    }

    using_mining_laser = [weapon_to_be_fired isMiningLaser];

    energy -= weapon_energy_use * multiplier;

    switch (currentWeaponFacing) {
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

    BOOL weaponFired = NO;
    if (!isWeaponNone(weapon_to_be_fired)) {
        if (![weapon_to_be_fired isTurretLaser]) {
            [self fireLaserShotInDirection:currentWeaponFacing weaponIdentifier:[[self currentWeapon] identifier]];
            weaponFired = YES;
        } else {
            // nothing: compatible with previous versions
        }
    }

    if (weaponFired && cloaking_device_active && cloakPassive) {
        [self deactivateCloakingDevice];
    }

    return weaponFired;
}

- (OOWeaponType)weaponForFacing:(OOWeaponFacing)facing
{
    switch (facing) {
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

- (OOWeaponType)currentWeapon
{
    return [self weaponForFacing:currentWeaponFacing];
}

// override ShipEntity definition to ensure that
// if shields are still up, always hit the main entity and take the damage
// on the shields
- (GLfloat)doesHitLine:(HPVector)v0 v1:(HPVector)v1 hitEntity:(ShipEntity**)hitEntity
{
    if (hitEntity)
        hitEntity[0] = (ShipEntity*)nil;
    Vector u0 = HPVectorToVector(HPvector_between(position, v0)); // relative to origin of model / octree
    Vector u1 = HPVectorToVector(HPvector_between(position, v1));
    Vector w0 = make_vector(dot_product(u0, v_right), dot_product(u0, v_up), dot_product(u0, v_forward)); // in ijk vectors
    Vector w1 = make_vector(dot_product(u1, v_right), dot_product(u1, v_up), dot_product(u1, v_forward));
    GLfloat hit_distance = [octree isHitByLine:w0 v1:w1];
    if (hit_distance) {
        if (hitEntity)
            hitEntity[0] = self;
    }

    bool shields = false;
    if ((w0.z >= 0 && forward_shield > 1) || (w0.z <= 0 && aft_shield > 1)) {
        shields = true;
    }

    for (const oo::ObjCRef<ShipEntity*>& seRef : [self cxx_shipSubEntities]) // the -shipSubEntityEnumerator order
    {
        ShipEntity* se = seRef.get();
        HPVector p0 = [se absolutePositionForSubentity];
        Triangle ijk = [se absoluteIJKForSubentity];
        u0 = HPVectorToVector(HPvector_between(p0, v0));
        u1 = HPVectorToVector(HPvector_between(p0, v1));
        w0 = resolveVectorInIJK(u0, ijk);
        w1 = resolveVectorInIJK(u1, ijk);

        GLfloat hitSub = [se->octree isHitByLine:w0 v1:w1];
        if (hitSub && (hit_distance == 0 || hit_distance > hitSub)) {
            hit_distance = hitSub;
            if (hitEntity && !shields) {
                *hitEntity = se;
            }
        }
    }

    return hit_distance;
}

- (void)takeEnergyDamage:(double)amount from:(Entity*)ent becauseOf:(Entity*)other weaponIdentifier:(id)weaponIdentifier // shared selector (proposed ADR-0043): an Objective-C string
{
    const std::string weaponId = oo::StdString(weaponIdentifier);
    HPVector rel_pos;
    OOScalar d_forward, d_right, d_up;
    BOOL internal_damage = NO; // base chance

    OO_LOG("player.ship.damage", "Player took damage from {} becauseOf {}", oo::DescriptionOf(ent), oo::DescriptionOf(other));

    if ([self status] == STATUS_DEAD)
        return;
    if ([self status] == STATUS_ESCAPE_SEQUENCE)
        return; // if the player has ejected, don't deal more damage
    if (amount == 0.0)
        return;

    BOOL cascadeWeapon = [ent isCascadeWeapon];
    BOOL cascading = NO;
    if (cascadeWeapon) {
        cascading = [self cascadeIfAppropriateWithDamageAmount:amount cascadeOwner:[ent owner]];
    }

    // make sure ent (& its position) is the attacking _ship_/missile !
    if (ent && [ent isSubEntity])
        ent = [ent owner];

    [[ent retain] autorelease];
    [[other retain] autorelease];

    rel_pos = (ent != nil) ? [ent position] : kZeroHPVector;
    rel_pos = HPvector_subtract(rel_pos, position);

    [self doScriptEvent:OOJSID("shipBeingAttacked") withArgument:ent];
    if ([ent isShip])
        [(ShipEntity*)ent doScriptEvent:OOJSID("shipAttackedOther") withArgument:self];

    d_forward = dot_product(HPVectorToVector(rel_pos), v_forward);
    d_right = dot_product(HPVectorToVector(rel_pos), v_right);
    d_up = dot_product(HPVectorToVector(rel_pos), v_up);
    Vector relative = make_vector(d_right, d_up, d_forward);

    [self cxx_playShieldHit:relative weaponIdentifier:weaponId];

    // firing on an innocent ship is an offence
    if ([other isShip]) {
        [self broadcastHitByLaserFrom:(ShipEntity*)other];
    }

    if (d_forward >= 0) {
        forward_shield -= amount;
        if (forward_shield < 0.0) {
            amount = -forward_shield;
            forward_shield = 0.0f;
        } else {
            amount = 0.0;
        }
    } else {
        aft_shield -= amount;
        if (aft_shield < 0.0) {
            amount = -aft_shield;
            aft_shield = 0.0f;
        } else {
            amount = 0.0;
        }
    }

    OOShipDamageType damageType = cascadeWeapon ? kOODamageTypeCascadeWeapon : kOODamageTypeEnergy;

    if (amount > 0.0) {
        energy -= amount;
        [self cxx_playDirectHit:relative weaponIdentifier:weaponId];
        if (ship_temperature < SHIP_MAX_CABIN_TEMP) {
            /* Heat increase from energy impacts will never directly cause
             * overheating - too easy for missile hits to cause an uncredited
             * death by overheating against NPCs, so same rules for player */
            ship_temperature += amount * SHIP_ENERGY_DAMAGE_TO_HEAT_FACTOR / [self heatInsulation];
            if (ship_temperature > SHIP_MAX_CABIN_TEMP) {
                ship_temperature = SHIP_MAX_CABIN_TEMP;
            }
        }
    }
    [self noteTakingDamage:amount from:other type:damageType];
    if (cascading)
        energy = 0.0; // explicitly set energy to zero when cascading, in case an oxp raised the energy in noteTakingDamage.

    if (energy <= 0.0) // use normal ship temperature calculations for heat damage
    {
        if ([other isShip]) {
            [(ShipEntity*)other noteTargetDestroyed:self];
        }

        [self getDestroyedBy:other damageType:damageType];
    } else {
        while (amount > 0.0) {
            internal_damage = ((ranrot_rand() & PLAYER_INTERNAL_DAMAGE_FACTOR) < amount); // base chance of damage to systems
            if (internal_damage) {
                [self takeInternalDamage];
            }
            amount -= (PLAYER_INTERNAL_DAMAGE_FACTOR + 1);
        }
    }
}

- (void)takeScrapeDamage:(double)amount from:(Entity*)ent
{
    HPVector rel_pos;
    OOScalar d_forward, d_right, d_up;
    BOOL internal_damage = NO; // base chance

    if ([self status] == STATUS_DEAD)
        return;

    if (amount < 0) {
        OO_LOG("player.ship.damage", "Player took negative scrape damage {:.3f} so we made it positive", amount);
        amount = -amount;
    }
    OO_LOG("player.ship.damage", "Player took {:.3f} scrape damage from {}", amount, oo::DescriptionOf(ent));

    [[ent retain] autorelease];
    rel_pos = ent ? [ent position] : kZeroHPVector;
    rel_pos = HPvector_subtract(rel_pos, position);
    // rel_pos is now small
    d_forward = dot_product(HPVectorToVector(rel_pos), v_forward);
    d_right = dot_product(HPVectorToVector(rel_pos), v_right);
    d_up = dot_product(HPVectorToVector(rel_pos), v_up);
    Vector relative = make_vector(d_right, d_up, d_forward);

    [self playScrapeDamage:relative];
    if (d_forward >= 0) {
        forward_shield -= amount;
        if (forward_shield < 0.0) {
            amount = -forward_shield;
            forward_shield = 0.0f;
        } else {
            amount = 0.0;
        }
    } else {
        aft_shield -= amount;
        if (aft_shield < 0.0) {
            amount = -aft_shield;
            aft_shield = 0.0f;
        } else {
            amount = 0.0;
        }
    }

    [super takeScrapeDamage:amount from:ent];

    while (amount > 0.0) {
        internal_damage = ((ranrot_rand() & PLAYER_INTERNAL_DAMAGE_FACTOR) < amount); // base chance of damage to systems
        if (internal_damage) {
            [self takeInternalDamage];
        }
        amount -= (PLAYER_INTERNAL_DAMAGE_FACTOR + 1);
    }
}

- (void)takeHeatDamage:(double)amount
{
    if ([self status] == STATUS_DEAD || amount < 0)
        return;

    // hit the shields first!
    float fwd_amount = (float)(0.5 * amount);
    float aft_amount = (float)(0.5 * amount);

    forward_shield -= fwd_amount;
    if (forward_shield < 0.0) {
        fwd_amount = -forward_shield;
        forward_shield = 0.0f;
    } else {
        fwd_amount = 0.0f;
    }

    aft_shield -= aft_amount;
    if (aft_shield < 0.0) {
        aft_amount = -aft_shield;
        aft_shield = 0.0f;
    } else {
        aft_amount = 0.0f;
    }

    double residual_amount = fwd_amount + aft_amount;

    [super takeHeatDamage:residual_amount];
}

- (ProxyPlayerEntity*)createDoppelganger
{
    ProxyPlayerEntity* result = (ProxyPlayerEntity*)[[UNIVERSE newShipWithName:[self shipDataKey] usePlayerProxy:YES] autorelease];

    if (result != nil) {
        [result setPosition:[self position]];
        [result setScanClass:CLASS_NEUTRAL];
        [result setOrientation:[self normalOrientation]];
        [result setVelocity:[self velocity]];
        [result setSpeed:[self flightSpeed]];
        [result setDesiredSpeed:[self flightSpeed]];
        [result setRoll:flightRoll];
        [result setBehaviour:BEHAVIOUR_IDLE];
        [result switchAITo:@"nullAI.plist"]; // fly straight on
        [result setTemperature:[self temperature]];
        [result copyValuesFromPlayer:self];
    }

    return result;
}

- (ShipEntity*)launchEscapeCapsule
{
    ShipEntity* doppelganger = nil;
    ShipEntity* escapePod = nil;

    if ([UNIVERSE displayGUI])
        [self switchToMainView]; // Clear the F7 screen!
    [UNIVERSE setViewDirection:VIEW_FORWARD];

    if ([self status] == STATUS_DEAD)
        return nil;

    /*
            While inside the escape pod, we need to block access to all player.ship properties,
            since we're not supposed to be inside our ship anymore! -- Kaks 20101114
    */

    [UNIVERSE setBlockJSPlayerShipProps:YES]; // no player.ship properties while inside the pod!
    // if a specific amount of time has been provided for the rescue, use it now
    if (escape_pod_rescue_time > 0) {
        ship_clock_adjust += escape_pod_rescue_time;
        escape_pod_rescue_time = 0; // reset value
    } else {
        // otherwise, use the default time calc
        ship_clock_adjust += 43200 + 5400 * (ranrot_rand() & 127); // add up to 8 days until rescue!
    }
    dockingClearanceStatus = DOCKING_CLEARANCE_STATUS_NOT_REQUIRED;
    flightSpeed = fmin(flightSpeed, maxFlightSpeed);

    doppelganger = [self createDoppelganger];
    if (doppelganger) {
        [doppelganger setVelocity:vector_multiply_scalar(v_forward, flightSpeed)];
        [doppelganger setSpeed:0.0];
        [doppelganger setDesiredSpeed:0.0];
        [doppelganger setRoll:0.2 * (randf() - 0.5)];
        [doppelganger setOwner:self];
        [doppelganger setThrust:0]; // drifts
        [UNIVERSE addEntity:doppelganger];
    }

    [self setFoundTarget:doppelganger]; // must do this before setting status
    [self setStatus:STATUS_ESCAPE_SEQUENCE]; // now set up the escape sequence.

    // must do this before next step or uses BBox of pod, not old ship!
    float sheight = (float)(boundingBox.max.y - boundingBox.min.y);
    position = HPvector_subtract(position, vectorToHPVector(vector_multiply_scalar(v_up, sheight)));
    float sdepth = (float)(boundingBox.max.z - boundingBox.min.z);
    position = HPvector_subtract(position, vectorToHPVector(vector_multiply_scalar(v_forward, sdepth / 2.0)));

    // set up you
    escapePod = [UNIVERSE newShipWithName:@"escape-capsule"]; // retained
    if (escapePod != nil) {
        // FIXME: this should use OOShipType, which should exist. -- Ahruman
        [self setMesh:[escapePod mesh]];
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
    Vector launchVector = vector_add([doppelganger velocity],
        vector_add(vector_multiply_scalar(v_up, 15.0f),
            vector_multiply_scalar(v_forward, -90.0f)));
    [self setVelocity:launchVector];

    // if multiple items providing escape pod, remove the first one
    [self removeEquipmentItem:[self equipmentItemProviding:@"EQ_ESCAPE_POD"]];

    // set up the standard location where the escape pod will dock.
    target_system_id = system_id; // we're staying in this system
    info_system_id = system_id;
    [self setDockTarget:[UNIVERSE station]]; // we're docking at the main station, if there is one

    [self doScriptEvent:OOJSID("shipLaunchedEscapePod") withArgument:escapePod]; // no player.ship properties should be available to script

    // reset legal status
    [self setBounty:0 withReason:kOOLegalStatusReasonEscapePod];
    bounty = 0;

    // new ship, so lose some memory of player actions
    if (ship_kills >= 6400) {
        [self clearRolesFromPlayer:0.1];
    } else if (ship_kills >= 2560) {
        [self clearRolesFromPlayer:0.25];
    } else {
        [self clearRolesFromPlayer:0.5];
    }

    // reset trumbles
    if (trumbleCount != 0)
        trumbleCount = 1;

    // remove cargo
    cargo.clear();

    energy = 25;
    [UNIVERSE addMessage:DESC(@"escape-sequence") forCount:4.5];
    [self resetShotTime];

    // need to zero out all facings shot_times too, otherwise we may end up
    // with a broken escape pod sequence - Nikos 20100909
    forward_shot_time = 0.0;
    aft_shot_time = 0.0;
    port_shot_time = 0.0;
    starboard_shot_time = 0.0;

    [escapePod release];

    return doppelganger;
}

- (id)dumpCargo // shared selector (proposed ADR-0043), called by name: an Objective-C string (the commodity), or nil
{
    if (flightSpeed > 4.0 * maxFlightSpeed) {
        [UNIVERSE addMessage:OOExpandKey(@"hold-locked") forCount:3.0];
        return nil;
    }

    id result = [super dumpCargo];
    if (result != nil) {
        const std::string commodity = oo::StdString([UNIVERSE displayNameForCommodity:result]); // (nil raised in the expansion)
        [UNIVERSE addMessage:oo::NSStringFrom(ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "commodity-ejected", { { "commodity", oo::PList(commodity) } })) forCount:3.0 forceDisplay:YES];
        [self playCargoJettisioned];
    }
    return result;
}

- (void)rotateCargo
{
    NSInteger i, n_cargo = cargo.size();
    if (n_cargo == 0)
        return;

    ShipEntity* pod = (ShipEntity*)[cargo[0].get() retain];
    const std::optional<std::string> current_contents = [pod cxx_commodityType];
    std::optional<std::string> contents;
    // -isEqualToString: with a nil on either side was NO
    const auto sameContents = [&current_contents](const std::optional<std::string>& other) { return other.has_value() && current_contents.has_value() && *other == *current_contents; };
    NSInteger rotates = 0;

    do {
        cargo.erase(cargo.begin()); // take it from the eject position
        cargo.emplace_back(pod); // move it to the last position
        [pod release];
        pod = (ShipEntity*)[cargo[0].get() retain];
        contents = [pod cxx_commodityType];
        rotates++;
    } while (sameContents(contents) && (rotates < n_cargo));
    [pod release];

    const std::string commodity = oo::StdString([UNIVERSE displayNameForCommodity:oo::NSStringOrNil(contents)]); // (nil raised in the expansion)
    [UNIVERSE addMessage:oo::NSStringFrom(ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "ready-to-eject-commodity", { { "commodity", oo::PList(commodity) } })) forCount:3.0];

    // now scan through the remaining 1..(n_cargo - rotates) places moving similar cargo to the last place
    // this means the cargo gets to be sorted as it is rotated through
    for (i = 1; i < (n_cargo - rotates); i++) {
        pod = cargo[i].get();
        if (sameContents([pod cxx_commodityType])) {
            [pod retain];
            cargo.erase(cargo.begin() + i--);
            cargo.emplace_back(pod);
            [pod release];
            rotates++;
        }
    }
}

- (void)setBounty:(OOCreditsQuantity)amount
{
    [self setBounty:amount withReason:kOOLegalStatusReasonUnknown];
}

- (void)setBounty:(OOCreditsQuantity)amount withReason:(OOLegalStatusReason)reason
{
    [self setBounty:amount withReasonAsString:OOStringFromLegalStatusReason(reason)];
}

- (void)setBounty:(OOCreditsQuantity)amount withReasonAsString:(id)reason // shared selector (proposed ADR-0043): an Objective-C string
{
    JSContext* context = OOJSAcquireContext();

    int amountVal2 = (int)amount - (int)legalStatus;
    OOJSVal amountVal = OOJSValueFromDouble(context, amountVal2);

    legalStatus = (int)amount; // can't set the new bounty until the size of the change is known

    OOJSVal reasonVal = OOJSValueFromNativeObject(context, reason);

    ShipScriptEvent(context, self, "shipBountyChanged", amountVal, reasonVal);

    OOJSRelinquishContext(context);
}

- (OOCreditsQuantity)bounty // overrides returning 'bounty'
{
    return legalStatus;
}

- (int)legalStatus
{
    return legalStatus;
}

- (void)markAsOffender:(int)offence_value
{
    [self markAsOffender:offence_value withReason:kOOLegalStatusReasonUnknown];
}

- (void)markAsOffender:(int)offence_value withReason:(OOLegalStatusReason)reason
{
    if (![self isCloaked]) {
        JSContext* context = OOJSAcquireContext();

        int amountVal2 = (legalStatus | offence_value) - legalStatus;
        OOJSVal amountVal = OOJSValueFromDouble(context, amountVal2);

        legalStatus |= offence_value; // can't set the new bounty until the size of the change is known

        OOJSVal reasonVal = OOJSValueFromLegalStatusReason(context, reason);

        ShipScriptEvent(context, self, "shipBountyChanged", amountVal, reasonVal);

        OOJSRelinquishContext(context);
    }
}

- (void)collectBountyFor:(ShipEntity*)other
{
    if ([self status] == STATUS_DEAD)
        return; // no bounty if we died while trying

    if (other == nil || [other isSubEntity])
        return;

    if (other == [UNIVERSE station]) {
        // there is no way the player can destroy the main station
        // and so the explosion will be cancelled, so there shouldn't
        // be a kill award
        return;
    }

    if ([self isCloaked]) {
        // no-one knows about it; no award
        return;
    }

    OOCreditsQuantity score = 10 * [other bounty];
    OOScanClass killClass = [other scanClass]; // **tgape** change (+line)
    BOOL killAward = [other countsAsKill];

    if ([other isPolice]) // oops, we shot a copper!
    {
        [self markAsOffender:64 withReason:kOOLegalStatusReasonAttackedPolice];
    }

    BOOL killIsCargo = ((killClass == CLASS_CARGO) && ([other commodityAmount] > 0) && ![other isHulk]);
    if ((killIsCargo) || (killClass == CLASS_BUOY) || (killClass == CLASS_ROCK)) {
        // EMMSTRAN: no killaward (but full bounty) for tharglets?
        if (![other hasRole:@"tharglet"]) // okay, we'll count tharglets as proper kills
        {
            score /= 10; // reduce bounty awarded
            killAward = NO; // don't award a kill
        }
    }

    credits += score;

    if (score > 9) {
        [UNIVERSE addDelayedMessage:OOExpandKey(@"bounty-awarded", score, credits) forCount:6 afterDelay:0.15];
    }

    if (killAward) {
        ship_kills++;
        if ((ship_kills % 256) == 0) {
            // congratulations method needs to be delayed a fraction of a second
            [UNIVERSE addDelayedMessage:DESC(@"right-on-commander") forCount:4 afterDelay:0.2];
        }
    }
}

- (BOOL)takeInternalDamage
{
    unsigned n_cargo = [self maxAvailableCargoSpace];
    unsigned n_mass = [self mass] / 10000;
    unsigned n_considered = (n_cargo + n_mass) * ship_trade_in_factor / 100; // a lower value of n_considered means more vulnerable to damage.
    unsigned damage_to = n_considered ? (ranrot_rand() % n_considered) : 0; // n_considered can be 0 for small ships.
    BOOL result = NO;
    // cargo damage
    if (damage_to < cargo.size()) {
        ShipEntity* pod = (ShipEntity*)cargo[damage_to].get();
        const std::optional<std::string> cargo_desc = oo::OptionalString([UNIVERSE displayNameForCommodity:[pod commodityType]]);
        if (!cargo_desc)
            return NO;
        [UNIVERSE clearPreviousMessage];
        [UNIVERSE addMessage:oo::NSStringFrom(oo::str::formatRuntime(oo::StdString(DESC(@"@-destroyed")), { *cargo_desc })) forCount:4.5];
        std::erase(cargo, pod);
        return YES;
    } else {
        damage_to = n_considered - (damage_to + 1); // reverse the die-roll
    }
    // equipment damage
    OOEquipmentType* eqType = nil;
    unsigned damageableCounter = 0;
    GLfloat damageableOdds = 0.0;
    for (const std::string& key : [self cxx_equipmentKeys]) // the -equipmentEnumerator order
    {
        eqType = [OOEquipmentType equipmentTypeWithIdentifier:oo::NSStringFrom(key)];
        if ([eqType canBeDamaged]) {
            damageableCounter++;
            damageableOdds += [eqType damageProbability];
        }
    }

    if (damage_to < damageableCounter) {
        GLfloat target = randf() * damageableOdds;
        GLfloat accumulator = 0.0;
        std::optional<std::string> system_key;
        for (const std::string& key : [self cxx_equipmentKeys]) {
            eqType = [OOEquipmentType equipmentTypeWithIdentifier:oo::NSStringFrom(key)];
            accumulator += [eqType damageProbability];
            if (accumulator > target) {
                system_key = key;
                break;
            }
        }
        if (!system_key.has_value()) {
            return NO;
        }

        const std::optional<std::string> system_name = oo::OptionalString([eqType name]);
        if (![eqType canBeDamaged] || !system_name.has_value()) {
            return NO;
        }

        // set the following so removeEquipment works on the right entity
        [self setScriptTarget:self];
        [UNIVERSE clearPreviousMessage];
        [self removeEquipmentItem:oo::NSStringFrom(*system_key)];

        const std::string damagedKey = oo::str::format("%s_DAMAGED", system_key->c_str());
        [self addEquipmentItem:oo::NSStringFrom(damagedKey) withValidation:NO inContext:@"damage"]; // for possible future repair.
        [self doScriptEvent:OOJSID("equipmentDamaged") withArgument:oo::NSStringFrom(*system_key)];

        if (![self hasEquipmentItem:oo::NSStringFrom(*system_name)] && [self hasEquipmentItem:oo::NSStringFrom(damagedKey)]) {
            /*
                    Display "foo damaged" message only if no script has
                    repaired or removed the equipment item. (If a script does
                    either of those and wants a message, it can write it
                    itself.)
            */
            [UNIVERSE addMessage:oo::NSStringFrom(oo::str::formatRuntime(oo::StdString(DESC(@"@-damaged")), { *system_name })) forCount:4.5];
        }

        /* There used to be a check for docking computers here, but
         * that didn't cover other ways they might fail in flight, so
         * it has been moved to the removeEquipment method. */
        return YES;
    }
    // cosmetic damage
    if (((damage_to & 7) == 7) && (ship_trade_in_factor > 75)) {
        ship_trade_in_factor--;
        result = YES;
    }
    return result;
}

- (void)getDestroyedBy:(Entity*)whom damageType:(OOShipDamageType)type
{
    if ([self isDocked])
        return; // Can't die while docked. (Doing so would cause breakage elsewhere.)

    OO_LOG("player.ship.damage", "Player destroyed by {} due to {}", oo::DescriptionOf(whom), cxx_OOStringFromShipDamageType(type));

    if (![[UNIVERSE gameController] playerFileToLoad]) {
        [[UNIVERSE gameController] setPlayerFileToLoad:save_path]; // make sure we load the correct game
    }

    energy = 0.0f;
    afterburner_engaged = NO;
    [self disengageAutopilot];

    [UNIVERSE setDisplayText:NO];
    [UNIVERSE setViewDirection:VIEW_AFT];

    // Let scripts know the player died.
    [self noteKilledBy:whom damageType:type]; // called before exploding, consistant with npc ships.

    [self becomeLargeExplosion:4.0]; // also sets STATUS_DEAD
    [self moveForward:100.0];

    flightSpeed = 160.0f;
    velocity = kZeroVector;
    flightRoll = 0.0;
    flightPitch = 0.0;
    flightYaw = 0.0;
    [[UNIVERSE messageGUI] clear]; // No messages for the dead.
    [self suppressTargetLost]; // No target lost messages when dead.
    [self playGameOver];
    [UNIVERSE setBlockJSPlayerShipProps:YES]; // Treat JS player as stale entity.
    [self removeAllEquipment]; // No scooping / equipment damage when dead.
    [self loseTargetStatus];
    [self showGameOver];
}

- (void)loseTargetStatus
{
    if (!UNIVERSE)
        return;
    int ent_count = UNIVERSE->n_entities;
    Entity** uni_entities = UNIVERSE->sortedEntities; // grab the public sorted list
    std::vector<Entity*> my_entities(ent_count);
    int i;
    for (i = 0; i < ent_count; i++)
        my_entities[i] = [uni_entities[i] retain]; //	retained
    for (i = 0; i < ent_count; i++) {
        Entity* thing = my_entities[i];
        if (thing->isShip) {
            ShipEntity* ship = (ShipEntity*)thing;
            if (self == [ship primaryTarget]) {
                [ship noteLostTarget];
            }
        }
    }
    for (i = 0; i < ent_count; i++) {
        [my_entities[i] release]; //	released
    }
}

- (BOOL)cxx_endScenario:(const std::string&)key
{
    if (scenarioKey != nil && key == oo::StdString(scenarioKey)) {
        [self setStatus:STATUS_RESTART_GAME];
        return YES;
    }
    return NO;
}

- (void)enterDock:(StationEntity*)station
{
    NSParameterAssert(station != nil);
    if ([self status] == STATUS_DEAD)
        return;

    [self setStatus:STATUS_DOCKING];
    [self setDockedStation:station];
    [self doScriptEvent:OOJSID("shipWillDockWithStation") withArgument:station];

    if (![hud nonlinearScanner]) {
        [hud setScannerZoom:1.0];
    }
    ident_engaged = NO;
    afterburner_engaged = NO;
    autopilot_engaged = NO;
    [self resetAutopilotAI];

    cloaking_device_active = NO;
    hyperspeed_engaged = NO;
    hyperspeed_locked = NO;
    [self safeAllMissiles];
    DESTROY(_primaryTarget); // must happen before showing break_pattern to suppress active reticule.
    [self clearTargetMemory];

    scanner_zoom_rate = 0.0f;
    [UNIVERSE setDisplayText:NO];
    [[UNIVERSE gameController] setMouseInteractionModeForFlight];
    if ([self status] == STATUS_LAUNCHING)
        return; // a JS script has aborted the docking.

    [self setOrientation:kIdentityQuaternion]; // reset orientation to dock
    [UNIVERSE setUpBreakPattern:[self breakPatternPosition] orientation:orientation forDocking:YES];
    [self playDockWithStation];
    [station noteDockedShip:self];

    [[UNIVERSE gameView] clearKeys]; // try to stop key bounces
}

- (void)docked
{
    StationEntity* dockedStation = [self dockedStation];
    if (dockedStation == nil) {
        [self setStatus:STATUS_IN_FLIGHT];
        return;
    }

    [self setStatus:STATUS_DOCKED];
    [UNIVERSE enterGUIViewModeWithMouseInteraction:NO];

    [self loseTargetStatus];

    [self setPosition:[dockedStation position]];
    [self setOrientation:kIdentityQuaternion]; // reset orientation to dock

    flightRoll = 0.0f;
    flightPitch = 0.0f;
    flightYaw = 0.0f;
    flightSpeed = 0.0f;

    hyperspeed_engaged = NO;
    hyperspeed_locked = NO;

    forward_shield = [self maxForwardShieldLevel];
    aft_shield = [self maxAftShieldLevel];
    energy = maxEnergy;
    weapon_temp = 0.0f;
    ship_temperature = 60.0f;

    [self setAlertFlag:ALERT_FLAG_DOCKED to:YES];

    if ([dockedStation localMarket] == nil) {
        [dockedStation initialiseLocalMarket];
    }

    const std::optional<std::string> escapepodReport = [self cxx_processEscapePods];
    [self cxx_addMessageToReport:escapepodReport.value_or(std::string())];

    [self unloadCargoPods]; // fill up the on-ship commodities before...

    // check import status of station
    // escape pods must be cleared before this happens
    if ([dockedStation marketMonitored]) {
        OOCreditsQuantity oldbounty = [self bounty];
        [self markAsOffender:[dockedStation legalStatusOfManifest:shipCommodityData export:NO] withReason:kOOLegalStatusReasonIllegalImports];
        if ([self bounty] > oldbounty) {
            [self cxx_addRoleToPlayer:"trader-smuggler"];
        }
    }

    // check contracts
    const std::optional<std::string> passengerAndCargoReport = [self cxx_checkPassengerContracts]; // Is also processing cargo and parcel contracts.
    if (passengerAndCargoReport.has_value())
        [self cxx_addMessageToReport:*passengerAndCargoReport]; // (the bridged form took nil as nothing)

    [UNIVERSE setDisplayText:YES];

    [[OOMusicController sharedController] stopDockingMusic];
    [[OOMusicController sharedController] playDockedMusic];

    // Did we fail to observe traffic control regulations? However, due to the state of emergency,
    // apply no unauthorized docking penalties if a nova is ongoing.
    if ([dockedStation requiresDockingClearance] && ![self clearedToDock] && ![[UNIVERSE sun] willGoNova]) {
        [self penaltyForUnauthorizedDocking];
    }

    // apply any pending fines. (No need to check gui_screen as fines is no longer an on-screen message).
    if (dockedStation == [UNIVERSE station]) {
        // TODO: A proper system to allow some OXP stations to have a
        // galcop presence for fines. - CIM 18/11/2012
        if (being_fined && ![[UNIVERSE sun] willGoNova] && ![dockedStation suppressArrivalReports])
            [self getFined];
    }

    // it's time to check the script - can trigger legacy missions
    if (gui_screen != GUI_SCREEN_MISSION)
        [self checkScript]; // a scripted pilot could have created a mission screen.

    OOJSStartTimeLimiterWithTimeLimit(kOOJSLongTimeLimit);
    [self doScriptEvent:OOJSID("shipDockedWithStation") withArgument:dockedStation];
    OOJSStopTimeLimiter();
    if ([self status] == STATUS_LAUNCHING)
        return;

    // if we've not switched to the mission screen yet then proceed normally..
    if (gui_screen != GUI_SCREEN_MISSION) {
        [self setGuiToStatusScreen];
    }
    [[OOCacheManager sharedCache] flush];
    [[OOJavaScriptEngine sharedEngine] garbageCollectionOpportunity:YES];

    // When a mission screen is started, any on-screen message is removed immediately.
    [self doWorldEventUntilMissionScreen:OOJSID("missionScreenOpportunity")]; // also displays docking reports first.
}

- (void)leaveDock:(StationEntity*)station
{
    if (station == nil)
        return;
    NSParameterAssert(station == [self dockedStation]);

    // ensure we've not left keyboard entry on
    [[UNIVERSE gameView] allowStringInput:NO];

    if (gui_screen == GUI_SCREEN_MISSION) {
        [[UNIVERSE gui] clearBackground];
        if (_missionWithCallback) {
            [self doMissionCallback];
        }
        // notify older scripts, but do not trigger missionScreenOpportunity.
        [self doWorldEventUntilMissionScreen:OOJSID("missionScreenEnded")];
    }

    if ([station marketMonitored]) {
        // 'leaving with those guns were you sir?'
        OOCreditsQuantity oldbounty = [self bounty];
        [self markAsOffender:[station legalStatusOfManifest:shipCommodityData export:YES] withReason:kOOLegalStatusReasonIllegalExports];
        if ([self bounty] > oldbounty) {
            [self cxx_addRoleToPlayer:"trader-smuggler"];
        }
    }
    OOGUIScreenID oldScreen = gui_screen;
    gui_screen = GUI_SCREEN_MAIN;
    [self noteGUIDidChangeFrom:oldScreen to:gui_screen];

    if (![hud nonlinearScanner]) {
        [hud setScannerZoom:1.0];
    }
    [self loadCargoPods];
    // do not do anything that calls JS handlers between now and calling
    // [station launchShip] below, or the cargo returned by JS may be off
    // CIM - 3.2.2012

    // clear the way
    [station autoDockShipsOnApproach];
    [station clearDockingCorridor];

    //	[self setAlertFlag:ALERT_FLAG_DOCKED to:NO];
    [self clearAlertFlags];
    [self setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];

    scanner_zoom_rate = 0.0f;
    currentWeaponFacing = WEAPON_FACING_FORWARD;
    [self currentWeaponStats];

    forward_weapon_temp = 0.0f;
    aft_weapon_temp = 0.0f;
    port_weapon_temp = 0.0f;
    starboard_weapon_temp = 0.0f;

    forward_shield = [self maxForwardShieldLevel];
    aft_shield = [self maxAftShieldLevel];

    [self clearTargetMemory];
    [self setShowDemoShips:NO];
    [UNIVERSE setDisplayText:NO];
    [[UNIVERSE gameController] setMouseInteractionModeForFlight];

    [[UNIVERSE gameView] clearKeys]; // try to stop keybounces

    if ([self isMouseControlOn]) {
        [[UNIVERSE gameView] resetMouse];
    }

    [[OOMusicController sharedController] stop];

    [UNIVERSE forceWitchspaceEntries];
    ship_clock_adjust += 600.0; // 10 minutes to leave dock
    velocity = kZeroVector; // just in case

    [station launchShip:self];

    launchRoll = -flightRoll; // save the station's spin. (inverted for player)
    flightRoll = 0; // don't spin when showing the break pattern.
    [UNIVERSE setUpBreakPattern:[self breakPatternPosition] orientation:orientation forDocking:YES];

    [self setDockedStation:nil];

    suppressAegisMessages = YES;
    [self checkForAegis];
    suppressAegisMessages = NO;
    ident_engaged = NO;

    [UNIVERSE removeDemoShips];
    // MKW - ensure GUI Screen ship is removed
    [demoShip release];
    demoShip = nil;

    [self playLaunchFromStation];
}

- (void)witchStart
{
    // chances of entering witchspace with autopilot on are very low, but as Berlios bug #18307 has shown us, entirely possible
    // so in such cases we need to ensure that at least the docking music stops playing
    if (autopilot_engaged)
        [self disengageAutopilot];

    if (![hud nonlinearScanner]) {
        [hud setScannerZoom:1.0];
    }
    [self safeAllMissiles];

    OOViewID previousViewDirection = [UNIVERSE viewDirection];
    [UNIVERSE setViewDirection:VIEW_FORWARD];
    [self noteSwitchToView:VIEW_FORWARD fromView:previousViewDirection]; // notifies scripts of the switch

    currentWeaponFacing = WEAPON_FACING_FORWARD;
    [self currentWeaponStats];

    [self transitionToAegisNone];
    suppressAegisMessages = YES;
    hyperspeed_engaged = NO;

    if ([self primaryTarget] != nil) {
        [self noteLostTarget]; // losing target? Fire lost target event!
        DESTROY(_primaryTarget);
    }

    scanner_zoom_rate = 0.0f;
    [UNIVERSE setDisplayText:NO];

    if (![self wormhole] && !galactic_witchjump) // galactic hyperspace does not generate a wormhole
    {
        OO_LOG(cxx_kOOLogInconsistentState, "{}", "Internal Error : Player entering witchspace with no wormhole.");
    }
    [UNIVERSE allShipsDoScriptEvent:OOJSID("playerWillEnterWitchspace") andReactToAIMessage:@"PLAYER WITCHSPACE"];

    // set the new market seed now!
    // reseeding the RNG should be completely unnecessary here
    //	ranrot_srand((uint32_t)oo::date::timeIntervalSince1970());	// seed randomiser by time
    market_rnd = ranrot_rand() & 255; // random factor for market values is reset
}

- (void)witchEnd
{
    [UNIVERSE setSystemTo:system_id];
    galaxy_coordinates = [[UNIVERSE systemManager] getCoordinatesForSystem:system_id inGalaxy:galaxy_number];

    [UNIVERSE setUpUniverseFromWitchspace];
    [[UNIVERSE planet] update:2.34375 * market_rnd]; // from 0..10 minutes
    [[UNIVERSE station] update:2.34375 * market_rnd]; // from 0..10 minutes

    chart_centre_coordinates = galaxy_coordinates;
    target_chart_centre = chart_centre_coordinates;
}

- (BOOL)witchJumpChecklist:(BOOL)isGalacticJump
{
    // Perform this check only when doing the actual jump
    if ([self status] == STATUS_WITCHSPACE_COUNTDOWN) {
        // check nearby masses
        // UPDATE_STAGE("checking for mass blockage");
        ShipEntity* blocker = [UNIVERSE entityForUniversalID:[self checkShipsInVicinityForWitchJumpExit]];
        if (blocker) {
            [UNIVERSE clearPreviousMessage];
            const std::string blockerName = oo::StdString([blocker name]); // (nil raised in the expansion)
            [UNIVERSE addMessage:oo::NSStringFrom(ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "witch-blocked", { { "blockerName", oo::PList(blockerName) } })) forCount:4.5];
            [self playWitchjumpBlocked];
            [self setStatus:STATUS_IN_FLIGHT];
            [self doScriptEvent:OOJSID("playerJumpFailed") withArgument:@"blocked"];
            return NO;
        }
    }

    // For galactic hyperspace jumps we skip the remaining checks
    if (isGalacticJump) {
        return YES;
    }

    // Check we're not jumping into the current system
    if (![UNIVERSE inInterstellarSpace] && system_id == target_system_id) {
        // dont allow player to hyperspace to current location.
        // Note interstellar space will have a system_seed place we came from
        [UNIVERSE clearPreviousMessage];
        [UNIVERSE addMessage:OOExpandKey(@"witch-no-target") forCount:4.5];
        if ([self status] == STATUS_WITCHSPACE_COUNTDOWN) {
            [self playWitchjumpInsufficientFuel];
            [self setStatus:STATUS_IN_FLIGHT];
            [self doScriptEvent:OOJSID("playerJumpFailed") withArgument:@"no target"];
        } else
            [self playHyperspaceNoTarget];

        return NO;
    }

    // check max distance permitted
    if ([self hyperspaceJumpDistance] > [self maxHyperspaceDistance]) {
        [UNIVERSE clearPreviousMessage];
        [UNIVERSE addMessage:DESC(@"witch-too-far") forCount:4.5];
        if ([self status] == STATUS_WITCHSPACE_COUNTDOWN) {
            [self playWitchjumpDistanceTooGreat];
            [self setStatus:STATUS_IN_FLIGHT];
            [self doScriptEvent:OOJSID("playerJumpFailed") withArgument:@"too far"];
        } else
            [self playHyperspaceDistanceTooGreat];

        return NO;
    }

    // check fuel level
    if (![self hasSufficientFuelForJump]) {
        [UNIVERSE clearPreviousMessage];
        [UNIVERSE addMessage:DESC(@"witch-no-fuel") forCount:4.5];
        if ([self status] == STATUS_WITCHSPACE_COUNTDOWN) {
            [self playWitchjumpInsufficientFuel];
            [self setStatus:STATUS_IN_FLIGHT];
            [self doScriptEvent:OOJSID("playerJumpFailed") withArgument:@"insufficient fuel"];
        } else
            [self playHyperspaceNoFuel];

        return NO;
    }

    // All checks passed
    return YES;
}

- (void)setJumpType:(BOOL)isGalacticJump
{
    if (isGalacticJump) {
        galactic_witchjump = YES;
    } else {
        galactic_witchjump = NO;
    }
}

- (double)hyperspaceJumpDistance
{
    NSPoint targetCoordinates = PointFromString([[UNIVERSE systemManager] getProperty:@"coordinates" forSystem:[self nextHopTargetSystemID] inGalaxy:galaxy_number]);
    return distanceBetweenPlanetPositions(targetCoordinates.x, targetCoordinates.y, galaxy_coordinates.x, galaxy_coordinates.y);
}

- (OOFuelQuantity)fuelRequiredForJump
{
    return 10.0 * MAX(0.1, [self hyperspaceJumpDistance]);
}

- (BOOL)hasSufficientFuelForJump
{
    return fuel >= [self fuelRequiredForJump];
}

- (void)noteCompassLostTarget
{
    if ([[self hud] isCompassActive]) {
        // "the compass, it says we're lost!" :)
        JSContext* context = OOJSAcquireContext();
        OOJSVal jsmode = OOJSValueFromCompassMode(context, [self compassMode]);
        ShipScriptEvent(context, self, "compassTargetChanged", OOJSUndefinedValue(), jsmode);
        OOJSRelinquishContext(context);

        [[self hud] setCompassActive:NO]; // ensure a target change when returning to normal space.
    }
}

- (void)enterGalacticWitchspace
{
    if (![self witchJumpChecklist:true])
        return;

    OOGalaxyID destGalaxy = galaxy_number + 1;
    if (EXPECT_NOT(destGalaxy >= OO_GALAXIES_AVAILABLE)) {
        destGalaxy = 0;
    }

    [self setStatus:STATUS_ENTERING_WITCHSPACE];
    JSContext* context = OOJSAcquireContext();
    [self cxx_setJumpCause:std::string("galactic jump")];
    [self setPreviousSystemID:[self currentSystemID]];
    ShipScriptEvent(context, self, "shipWillEnterWitchspace", OOJSValueFromNativeObject(context, oo::NSStringOrNil([self cxx_jumpCause])), OOJSValueFromDouble(context, destGalaxy));
    OOJSRelinquishContext(context);

    [self noteCompassLostTarget];

    [self witchStart];

    [UNIVERSE removeAllEntitiesExceptPlayer];

    // remove any contracts and parcels for the old galaxy
    contracts.clear();

    parcels.clear();

    // remove any mission destinations for the old galaxy
    missionDestinations.clear();

    // expire passenger contracts for the old galaxy
    {
        unsigned i;
        for (i = 0; i < passengers.size(); i++) {
            // set the expected arrival time to now, so they storm off the ship at the first port
            oo::PList::Dict passenger_info = passengers[i].isDict() ? *passengers[i].getIf<oo::PList::Dict>() : oo::PList::Dict();
            passenger_info[oo::StdString(CONTRACT_KEY_ARRIVAL_TIME)] = oo::PList(ship_clock); // +numberWithDouble:
            passengers[i] = oo::PList(std::move(passenger_info));
        }
    }

    // clear a lot of memory of player actions
    if (ship_kills >= 6400) {
        [self clearRolesFromPlayer:0.25];
    } else if (ship_kills >= 2560) {
        [self clearRolesFromPlayer:0.5];
    } else {
        [self clearRolesFromPlayer:0.9];
    }
    roleWeightFlags.clear();
    roleSystemList.clear();

    // may be more than one item providing this
    [self removeEquipmentItem:[self equipmentItemProviding:@"EQ_GAL_DRIVE"]];

    galaxy_number = destGalaxy;

    [UNIVERSE setGalaxyTo:galaxy_number];

    // Choose the galactic hyperspace behaviour. Refers to where we may actually end up after an intergalactic jump.
    // The default behaviour is that the player cannot arrive on unreachable or isolated systems. The options
    // in planetinfo.plist, galactic_hyperspace_behaviour key can be used to allow arrival even at unreachable systems,
    // or at fixed coordinates on the galactic chart. The key galactic_hyperspace_fixed_coords in planetinfo.plist is
    // used in the fixed coordinates case and specifies the exact coordinates for the intergalactic jump.
    switch (galacticHyperspaceBehaviour) {
    case GALACTIC_HYPERSPACE_BEHAVIOUR_FIXED_COORDINATES:
        system_id = [UNIVERSE findSystemNumberAtCoords:galacticHyperspaceFixedCoords withGalaxy:galaxy_number includingHidden:YES];
        break;
    case GALACTIC_HYPERSPACE_BEHAVIOUR_ALL_SYSTEMS_REACHABLE:
        system_id = [UNIVERSE findSystemNumberAtCoords:galaxy_coordinates withGalaxy:galaxy_number includingHidden:YES];
        break;
    case GALACTIC_HYPERSPACE_BEHAVIOUR_STANDARD:
    default:
        // instead find a system connected to system 0 near the current coordinates...
        system_id = [UNIVERSE findConnectedSystemAtCoords:galaxy_coordinates withGalaxy:galaxy_number];
        break;
    }
    target_system_id = system_id;
    info_system_id = system_id;

    [self setBounty:0 withReason:kOOLegalStatusReasonNewGalaxy]; // let's make a fresh start!
    cursor_coordinates = PointFromString([[UNIVERSE systemManager] getProperty:@"coordinates" forSystem:system_id inGalaxy:galaxy_number]);

    [self witchEnd]; // sets coordinates, calls exiting witchspace JS events
}

// now with added misjump goodness!
// If the wormhole generator misjumped, the player's ship misjumps too. Kaks 20110211
- (void)enterWormhole:(WormholeEntity*)w_hole
{
    if ([self status] == STATUS_ENTERING_WITCHSPACE
        || [self status] == STATUS_EXITING_WITCHSPACE) {
        return; // has already entered a different wormhole
    }
    BOOL misjump = [self scriptedMisjump] || [w_hole withMisjump] || flightPitch == max_flight_pitch || randf() > 0.995;
    wormhole = [w_hole retain];
    [self addScannedWormhole:wormhole];
    [self setStatus:STATUS_ENTERING_WITCHSPACE];
    JSContext* context = OOJSAcquireContext();
    [self setJumpCause:@"wormhole"];
    [self setPreviousSystemID:[self currentSystemID]];
    ShipScriptEvent(context, self, "shipWillEnterWitchspace", OOJSValueFromNativeObject(context, [self jumpCause]), OOJSValueFromDouble(context, [w_hole destination]));
    OOJSRelinquishContext(context);
    if ([self scriptedMisjump]) {
        misjump = YES; // a script could just have changed this to true;
    }
#ifdef OO_DUMP_PLANETINFO
    misjump = NO;
#endif
    if (misjump && [self scriptedMisjumpRange] != 0.5) {
        [w_hole setMisjumpWithRange:[self scriptedMisjumpRange]]; // overrides wormholes, if player also had non-default scriptedMisjumpRange
    }
    [self witchJumpTo:[w_hole destination] misjump:misjump];
}

- (void)enterWitchspace
{
    if (![self witchJumpChecklist:false])
        return;

    OOSystemID jumpTarget = [self nextHopTargetSystemID];

    //  perform any check here for forced witchspace encounters
    unsigned malfunc_chance = 253;
    if (ship_trade_in_factor < 80) {
        malfunc_chance -= (1 + ranrot_rand() % (81 - ship_trade_in_factor)) / 2; // increase chance of misjump in worn-out craft
    } else if (ship_trade_in_factor >= 100) {
        malfunc_chance = 256; // force no misjumps on first jump
    }

#ifdef OO_DUMP_PLANETINFO
    BOOL misjump = NO; // debugging
#else
    BOOL malfunc = ((ranrot_rand() & 0xff) > malfunc_chance);
    // 75% of the time a malfunction means a misjump
    BOOL misjump = [self scriptedMisjump] || (flightPitch == max_flight_pitch) || (malfunc && (randf() > 0.75));

    if (malfunc && !misjump) {
        // some malfunctions will start fuel leaks, some will result in no witchjump at all.
        if ([self takeInternalDamage]) // Depending on ship type and loaded cargo, this will be true for 20 - 50% of the time.
        {
            [self playWitchjumpFailure];
            [self setStatus:STATUS_IN_FLIGHT];
            [self doScriptEvent:OOJSID("playerJumpFailed") withArgument:@"malfunction"];
            return;
        } else {
            [self setFuelLeak:oo::NSStringFrom(oo::str::format("%f", (randf() + randf()) * 5.0))];
        }
    }
#endif

    // From this point forward we are -definitely- witchjumping

    // burn the full fuel amount to create the wormhole
    fuel -= [self fuelRequiredForJump];

    // Create the players' wormhole
    wormhole = [[WormholeEntity alloc] initWormholeTo:jumpTarget fromShip:self];
    [UNIVERSE addEntity:wormhole]; // Add new wormhole to Universe to let other ships target it. Required for ships following the player.
    [self addScannedWormhole:wormhole];

    [self setStatus:STATUS_ENTERING_WITCHSPACE];
    JSContext* context = OOJSAcquireContext();
    [self cxx_setJumpCause:std::string("standard jump")];
    [self setPreviousSystemID:[self currentSystemID]];
    ShipScriptEvent(context, self, "shipWillEnterWitchspace", OOJSValueFromNativeObject(context, oo::NSStringOrNil([self cxx_jumpCause])), OOJSValueFromDouble(context, jumpTarget));
    OOJSRelinquishContext(context);

    [self updateSystemMemory];
    NSUInteger legality = [self legalStatusOfCargoList];
    OOCargoQuantity maxSpace = [self maxAvailableCargoSpace];
    OOCargoQuantity availSpace = [self availableCargoSpace];
    if (roleWeightFlags.contains("bought-legal")) {
        if (maxSpace != availSpace) {
            [self cxx_addRoleToPlayer:"trader"];
            if (maxSpace - availSpace > 20 || availSpace == 0) {
                if (legality == 0) {
                    [self cxx_addRoleToPlayer:"trader"];
                }
            }
        }
    }
    if (roleWeightFlags.contains("bought-illegal")) {
        if (maxSpace != availSpace && legality > 0) {
            [self cxx_addRoleToPlayer:"trader-smuggler"];
            if (maxSpace - availSpace > 20 || availSpace == 0) {
                if (legality >= 20 || legality >= maxSpace) {
                    [self cxx_addRoleToPlayer:"trader-smuggler"];
                }
            }
        }
    }
    roleWeightFlags.clear();

    [self noteCompassLostTarget];
    if ([self scriptedMisjump]) {
        misjump = YES; // a script could just have changed this to true;
    }
    if (misjump) {
        [wormhole setMisjumpWithRange:[self scriptedMisjumpRange]];
    }
    [self witchJumpTo:jumpTarget misjump:misjump];
}

- (void)witchJumpTo:(OOSystemID)sTo misjump:(BOOL)misjump
{
    [self witchStart];
    if (info_system_id == system_id) {
        [self setInfoSystemID:sTo moveChart:YES];
    }
    // wear and tear on all jumps (inc misjumps, failures, and wormholes)
    if (2 * market_rnd < ship_trade_in_factor) {
        // every eight jumps or so drop the price down towards 75%
        [self adjustTradeInFactorBy:-(1 + (market_rnd & 3))];
    }

    // set clock after "playerWillEnterWitchspace" and before  removeAllEntitiesExceptPlayer, to allow escorts time to follow their mother.
    NSPoint destCoords = PointFromString([[UNIVERSE systemManager] getProperty:@"coordinates" forSystem:sTo inGalaxy:galaxy_number]);
    double distance = distanceBetweenPlanetPositions(destCoords.x, destCoords.y, galaxy_coordinates.x, galaxy_coordinates.y);

    // if we just escaped a system gone nova, make sure all nova parameters are reset
    OOSunEntity* theSun = [UNIVERSE sun];
    if (theSun && [theSun goneNova]) {
        [theSun resetNova];
    }

    [UNIVERSE removeAllEntitiesExceptPlayer];
    if (!misjump) {
        ship_clock_adjust += distance * distance * 3600.0;
        [self setSystemID:sTo];
        [self setBounty:(legalStatus / 2) withReason:kOOLegalStatusReasonNewSystem]; // 'another day, another system'
        [self witchEnd];
        if (market_rnd < 8)
            [self erodeReputation]; // every 32 systems or so, drop back towards 'unknown'
    } else {
        // Misjump: move halfway there!
        // misjumps do not change legal status.
        if (randf() < 0.1)
            [self erodeReputation]; // once every 10 misjumps - should be much rarer than successful jumps!

        [wormhole setMisjump];
        // just in case, but this has usually been set already

        // and now the wormhole has travel time and coordinates calculated
        // so rather than duplicate the calculation we'll just ask it...
        NSPoint dest = [wormhole destinationCoordinates];
        galaxy_coordinates.x = dest.x;
        galaxy_coordinates.y = dest.y;

        ship_clock_adjust += [wormhole travelTime];

        [self playWitchjumpMisjump];
        [UNIVERSE setUpUniverseFromMisjump];
    }
}

- (void)leaveWitchspace
{
    double d1 = SCANNER_MAX_RANGE * ((Ranrot() & 255) / 256.0 - 0.5);
    HPVector pos = [UNIVERSE getWitchspaceExitPosition]; // no need to reset the PRNG
    Quaternion q1;
    HPVector whpos, exitpos;

    double min_d1 = [UNIVERSE safeWitchspaceExitDistance];
    quaternion_set_random(&q1);
    if (abs((int)d1) < min_d1) {
        d1 += ((d1 > 0.0) ? min_d1 : -min_d1); // not too close to the buoy.
    }
    HPVector v1 = HPvector_forward_from_quaternion(q1);
    exitpos = HPvector_add(pos, HPvector_multiply_scalar(v1, d1)); // randomise exit position
    position = exitpos;
    [self setOrientation:[UNIVERSE getWitchspaceExitRotation]];

    // While setting the wormhole position to the player position looks very nice for ships following the player,
    // the more common case of the player following other ships, the player tends to
    // ram the back of the ships, or even jump on top of is when the ship jumped without initial speed, which is messy.
    // To avoid this problem, a small wormhole displacement is added.
    if (wormhole) // will be nil for galactic jump
    {
        if ([wormhole shipsInTransit].count() > 0) {
            // player is not allone in his wormhole, synchronise player and wormhole position.
            double wh_arrival_time = ([PLAYER clockTimeAdjusted] - [wormhole arrivalTime]);
            if (wh_arrival_time > 0) {
                // Player is following other ship
                whpos = HPvector_add(exitpos, vectorToHPVector(vector_multiply_scalar([self forwardVector], 1000.0f)));
                [wormhole setContainsPlayer:YES];
            } else {
                // Player is the leadship
                whpos = HPvector_add(exitpos, vectorToHPVector(vector_multiply_scalar([self forwardVector], -500.0f)));
                // so it won't contain the player by the time they exit
                [wormhole setExitSpeed:maxFlightSpeed * WORMHOLE_LEADER_SPEED_FACTOR];
            }

            HPVector distance = HPvector_subtract(whpos, pos);
            if (HPmagnitude2(distance) < min_d1 * min_d1) // within safety distance from the buoy?
            {
                // the wormhole is to close to the buoy. Move both player and wormhole away from it in the x-y plane.
                distance.z = 0;
                distance = HPvector_multiply_scalar(HPvector_normal(distance), min_d1);
                whpos = HPvector_add(whpos, distance);
                position = HPvector_add(position, distance);
            }
            [wormhole setExitPosition:whpos];
        } else {
            // no-one else in the wormhole
            [wormhole setExitSpeed:maxFlightSpeed * WORMHOLE_LEADER_SPEED_FACTOR];
        }
    }
    /* there's going to be a slight pause at this stage anyway;
     * there's also going to be a lot of stale ship scripts. Force a
     * garbage collection while we have chance. - CIM */
    [[OOJavaScriptEngine sharedEngine] garbageCollectionOpportunity:YES];
    flightSpeed = wormhole ? [wormhole exitSpeed] : fmin(maxFlightSpeed, 50.0f);
    [wormhole release]; // OK even if nil
    wormhole = nil;

    flightRoll = 0.0f;
    flightPitch = 0.0f;
    flightYaw = 0.0f;

    velocity = kZeroVector;
    [self setStatus:STATUS_EXITING_WITCHSPACE];
    gui_screen = GUI_SCREEN_MAIN;
    being_fined = NO; // until you're scanned by a copper!
    [self clearTargetMemory];
    [self setShowDemoShips:NO];
    [[UNIVERSE gameController] setMouseInteractionModeForFlight];
    [UNIVERSE setDisplayText:NO];
    [UNIVERSE setWitchspaceBreakPattern:YES];
    [self playExitWitchspace];
    if ([self currentSystemID] >= 0) {
        if (std::find(roleSystemList.begin(), roleSystemList.end(), [self currentSystemID]) == roleSystemList.end()) {
            // going somewhere new?
            [self clearRoleFromPlayer:NO];
        }
    }

    if (galactic_witchjump) {
        [self doScriptEvent:OOJSID("playerEnteredNewGalaxy") withArgument:oo::ObjectFromPList(oo::PList::unsignedInteger(galaxy_number))];
    }

    [self doScriptEvent:OOJSID("shipWillExitWitchspace") withArgument:[self jumpCause]];
    [UNIVERSE setUpBreakPattern:[self breakPatternPosition] orientation:orientation forDocking:NO];
}

///////////////////////////////////

- (void)setGuiToStatusScreen
{
    std::optional<std::string> systemName;
    std::optional<std::string> targetSystemName;
    std::string text;

    GuiDisplayGen* gui = [UNIVERSE gui];
    OOGUIScreenID oldScreen = gui_screen;
    if (oldScreen != GUI_SCREEN_STATUS) {
        [self noteGUIWillChangeTo:GUI_SCREEN_STATUS];
    }

    gui_screen = GUI_SCREEN_STATUS;
    BOOL guiChanged = (oldScreen != gui_screen);

    [[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:NO];

    // Both system_seed & target_system_seed are != nil at all times when this function is called.

    systemName = oo::OptionalString([UNIVERSE inInterstellarSpace] ? DESC(@"interstellar-space") : [UNIVERSE getSystemName:system_id]);
    if ([self isDocked] && [self dockedStation] != [UNIVERSE station]) {
        systemName = oo::str::format("%s : %s", systemName.value_or("(null)").c_str(), oo::DescriptionOf([[self dockedStation] displayName]).c_str());
    }

    targetSystemName = oo::OptionalString([UNIVERSE getSystemName:target_system_id]);
    oo::PList systemInfo = oo::PListFrom([[UNIVERSE systemManager] getPropertiesForSystem:target_system_id inGalaxy:galaxy_number]);
    NSInteger concealment = systemInfo.get<int>("concealment", OO_SYSTEMCONCEALMENT_NONE);
    if (concealment >= OO_SYSTEMCONCEALMENT_NONAME)
        targetSystemName = oo::OptionalString(DESC(@"status-unknown-system"));

    OOSystemID nextHop = [self nextHopTargetSystemID];
    if (nextHop != target_system_id) {
        std::optional<std::string> nextHopSystemName = oo::OptionalString([UNIVERSE getSystemName:nextHop]);
        systemInfo = oo::PListFrom([[UNIVERSE systemManager] getPropertiesForSystem:nextHop inGalaxy:galaxy_number]);
        concealment = systemInfo.get<int>("concealment", OO_SYSTEMCONCEALMENT_NONE);
        if (concealment >= OO_SYSTEMCONCEALMENT_NONAME)
            nextHopSystemName = oo::OptionalString(DESC(@"status-unknown-system"));
        // (a nil name raised in the expansion)
        targetSystemName = ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "status-hyperspace-system-multi",
            { { "targetSystemName", oo::PList(targetSystemName.value_or(std::string())) }, { "nextHopSystemName", oo::PList(nextHopSystemName.value_or(std::string())) } });
    }

    // GUI stuff
    {
        const std::optional<std::string> shipName = oo::OptionalString([self displayName]);
        std::optional<std::string> legal_desc, rating_desc,
            alert_desc, fuel_desc,
            credits_desc;

        OOGUIRow i;
        OOGUITabSettings tab_stops;
        tab_stops[0] = 20;
        tab_stops[1] = 160;
        tab_stops[2] = 290;
        [gui overrideTabs:tab_stops from:kGuiStatusTabs length:3];
        [gui setTabStops:tab_stops];

        const std::string lightYearsDesc = oo::StdString(DESC(@"status-light-years-desc"));

        legal_desc = cxx_OODisplayStringFromLegalStatus(legalStatus);
        rating_desc = cxx_KillCountToRatingAndKillString(ship_kills);
        alert_desc = cxx_OODisplayStringFromAlertCondition([self alertCondition]);
        fuel_desc = oo::str::format("%.1f %s", fuel / 10.0, lightYearsDesc.c_str());
        credits_desc = cxx_OOCredits(credits);

        [gui clearAndKeepBackground:!guiChanged];
        text = oo::StdString(DESC(@"status-commander-@"));
        [gui setTitle:oo::NSStringFrom(oo::str::formatRuntime(text, { [self cxx_commanderName].value_or("(null)") }))];

        [gui cxx_setText:shipName forRow:0 align:GUI_ALIGN_CENTER];

        [gui cxx_setArray:RowOf(oo::OptionalString(DESC(@"status-present-system")), systemName) forRow:1];
        if ([self hasHyperspaceMotor])
            [gui cxx_setArray:RowOf(oo::OptionalString(DESC(@"status-hyperspace-system")), targetSystemName) forRow:2];
        [gui cxx_setArray:RowOf(oo::OptionalString(DESC(@"status-condition")), alert_desc) forRow:3];
        [gui cxx_setArray:RowOf(oo::OptionalString(DESC(@"status-fuel")), fuel_desc) forRow:4];
        [gui cxx_setArray:RowOf(oo::OptionalString(DESC(@"status-cash")), credits_desc) forRow:5];
        [gui cxx_setArray:RowOf(oo::OptionalString(DESC(@"status-legal-status")), legal_desc) forRow:6];
        [gui cxx_setArray:RowOf(oo::OptionalString(DESC(@"status-rating")), rating_desc) forRow:7];

        [gui setColor:[gui colorFromSetting:kGuiStatusShipnameColor defaultValue:nil] forRow:0];
        for (i = 1; i <= 7; ++i) {
            // nil default = fall back to global default colour
            [gui setColor:[gui colorFromSetting:kGuiStatusDataColor defaultValue:nil] forRow:i];
        }

        [gui setText:DESC(@"status-equipment") forRow:9];

        [gui setColor:[gui colorFromSetting:kGuiStatusEquipmentHeadingColor defaultValue:nil] forRow:9];

        [gui setShowTextCursor:NO];
    }
    /* ends */

    lastTextKey.reset();

    [[UNIVERSE gameView] clearMouse];

    // Contributed by Pleb - show ship model if the appropriate user default key has been set - Nikos 20140127
    if (EXPECT_NOT(oo::Defaults::standard().boolForKey("show-ship-model-in-status-screen"))) {
        [UNIVERSE removeDemoShips];
        [self showShipModelWithKey:[self shipDataKey]
                          shipData:nil
                       personality:[self entityPersonalityInt]
                           factorX:2.5
                           factorY:1.7
                           factorZ:8.0
                         inContext:@"GUI_SCREEN_STATUS"];
        [self setShowDemoShips:YES];
    } else {
        [self setShowDemoShips:NO];
    }

    [UNIVERSE enterGUIViewModeWithMouseInteraction:NO];

    if (guiChanged) {
        oo::PList fgDescriptor, bgDescriptor;
        if ([self status] == STATUS_DOCKED) {
            fgDescriptor = oo::PListFrom([UNIVERSE screenTextureDescriptorForKey:@"docked_overlay"]);
            bgDescriptor = oo::PListFrom([UNIVERSE screenTextureDescriptorForKey:@"status_docked"]);
        } else {
            fgDescriptor = oo::PListFrom([UNIVERSE screenTextureDescriptorForKey:@"overlay"]);
            if (alertCondition == ALERT_CONDITION_RED)
                bgDescriptor = oo::PListFrom([UNIVERSE screenTextureDescriptorForKey:@"status_red_alert"]);
            else
                bgDescriptor = oo::PListFrom([UNIVERSE screenTextureDescriptorForKey:@"status_in_flight"]);
        }

        [gui cxx_setForegroundTextureDescriptor:fgDescriptor];

        if (bgDescriptor.isNull())
            bgDescriptor = oo::PListFrom([UNIVERSE screenTextureDescriptorForKey:@"status"]);
        [gui cxx_setBackgroundTextureDescriptor:bgDescriptor];

        [gui setStatusPage:0];
        [self noteGUIDidChangeFrom:oldScreen to:gui_screen];
    }
}

- (std::vector<oo::PList>)cxx_equipmentList
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    std::vector<oo::PList> quip1; // damaged
    std::vector<oo::PList> quip2; // working
    std::optional<std::string> desc;
    std::optional<std::string> alldesc;

    BOOL prioritiseDamaged = [gui cxx_userSettings].get<bool>(cxx_kGuiStatusPrioritiseDamaged, true);

    for (OOEquipmentType* eqType in [OOEquipmentType reverseEquipmentEnumerator]) {
        if ([eqType isVisible]) {
            if ([eqType canCarryMultiple] && ![eqType isMissileOrMine]) {
                const std::string identifier = oo::StdString([eqType identifier]);
                const std::string damagedIdentifier = identifier + "_DAMAGED";
                NSUInteger count = 0, okcount = 0;
                okcount = [self cxx_countEquipmentItem:identifier];
                count = okcount + [self cxx_countEquipmentItem:damagedIdentifier];
                if (count == 0) {
                    // do nothing
                }
                // all items okay
                else if (count == okcount) {
                    // only one installed display normally
                    if (count == 1) {
                        quip2.push_back(EquipmentRow(oo::OptionalString([eqType name]), true, [eqType displayColor]));
                    }
                    // display plural form
                    else {
                        const std::string equipmentName = oo::StdString([eqType name]); // (nil raised in the expansion)
                        alldesc = ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "equipment-plural",
                            { { "count", oo::PList::unsignedInteger(count) }, { "equipmentName", oo::PList(equipmentName) } });
                        quip2.push_back(EquipmentRow(alldesc, true, [eqType displayColor]));
                    }
                }
                // all broken, only one installed
                else if (count == 1 && okcount == 0) {
                    desc = oo::str::formatRuntime(oo::StdString(DESC(@"equipment-@-not-available")), { oo::DescriptionOf([eqType name]) });
                    if (prioritiseDamaged) {
                        quip1.push_back(EquipmentRow(desc, false, [eqType displayColor]));
                    } else {
                        quip2.push_back(EquipmentRow(desc, false, [eqType displayColor]));
                    }
                }
                // some broken, multiple installed
                else {
                    const std::string equipmentName = oo::StdString([eqType name]); // (nil raised in the expansion)
                    alldesc = ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "equipment-plural-some-na",
                        { { "okcount", oo::PList::unsignedInteger(okcount) }, { "count", oo::PList::unsignedInteger(count) }, { "equipmentName", oo::PList(equipmentName) } });
                    if (prioritiseDamaged) {
                        quip1.push_back(EquipmentRow(alldesc, false, [eqType displayColor]));
                    } else {
                        quip2.push_back(EquipmentRow(alldesc, false, [eqType displayColor]));
                    }
                }
            } else if ([self hasEquipmentItem:[eqType identifier]]) {
                quip2.push_back(EquipmentRow(oo::OptionalString([eqType name]), true, [eqType displayColor]));
            } else {
                // Check for damaged version
                if ([self hasEquipmentItem:oo::NSStringFrom(oo::StdString([eqType identifier]) + "_DAMAGED")]) {
                    desc = oo::str::formatRuntime(oo::StdString(DESC(@"equipment-@-not-available")), { oo::DescriptionOf([eqType name]) });

                    if (prioritiseDamaged) {
                        quip1.push_back(EquipmentRow(desc, false, [eqType displayColor]));
                    } else {
                        // just add in to the normal array
                        quip2.push_back(EquipmentRow(desc, false, [eqType displayColor]));
                    }
                }
            }
        }
    }

    if (max_passengers > 0) {
        desc = oo::str::formatRuntime(oo::StdString(DESC_PLURAL(@"equipment-pass-berth-@", max_passengers)), { static_cast<int>(max_passengers) }); // %d
        quip2.push_back(EquipmentRow(desc, true, [[OOEquipmentType equipmentTypeWithIdentifier:@"EQ_PASSENGER_BERTH"] displayColor]));
    }

    if (!isWeaponNone(forward_weapon_type)) {
        desc = oo::str::formatRuntime(oo::StdString(DESC(@"equipment-fwd-weapon-@")), { oo::DescriptionOf([forward_weapon_type name]) });
        quip2.push_back(EquipmentRow(desc, true, [forward_weapon_type displayColor]));
    }
    if (!isWeaponNone(aft_weapon_type)) {
        desc = oo::str::formatRuntime(oo::StdString(DESC(@"equipment-aft-weapon-@")), { oo::DescriptionOf([aft_weapon_type name]) });
        quip2.push_back(EquipmentRow(desc, true, [aft_weapon_type displayColor]));
    }
    if (!isWeaponNone(port_weapon_type)) {
        desc = oo::str::formatRuntime(oo::StdString(DESC(@"equipment-port-weapon-@")), { oo::DescriptionOf([port_weapon_type name]) });
        quip2.push_back(EquipmentRow(desc, true, [port_weapon_type displayColor]));
    }
    if (!isWeaponNone(starboard_weapon_type)) {
        desc = oo::str::formatRuntime(oo::StdString(DESC(@"equipment-stb-weapon-@")), { oo::DescriptionOf([starboard_weapon_type name]) });
        quip2.push_back(EquipmentRow(desc, true, [starboard_weapon_type displayColor]));
    }

    // list damaged first, then working
    quip1.insert(quip1.end(), quip2.begin(), quip2.end());
    return quip1;
}

- (NSUInteger)primedEquipmentCount
{
    return eqScripts.size();
}

- (std::optional<std::string>)cxx_primedEquipmentName:(NSInteger)offset
{
    NSUInteger c = [self primedEquipmentCount];
    NSUInteger idx = (primedEquipment + (c + 1) + offset) % (c + 1);
    if (idx == c) {
        return oo::OptionalString(DESC(@"equipment-primed-none-hud-label"));
    } else {
        return oo::OptionalString([[OOEquipmentType equipmentTypeWithIdentifier:oo::NSStringFrom(eqScripts[idx].first)] name]);
    }
}

- (std::string)cxx_currentPrimedEquipment
{
    std::string result; // "": primed-none
    NSUInteger c = eqScripts.size();
    if (primedEquipment != c && primedEquipment < c) {
        result = eqScripts[primedEquipment].first;
    }
    return result;
}

- (BOOL)cxx_setPrimedEquipment:(const std::string&)eqKey showMessage:(BOOL)showMsg
{
    // (a nil key primed nothing and answered NO: the bridged -setPrimedEquipment:showMessage:)
    NSUInteger c = eqScripts.size();
    NSUInteger current = primedEquipment;
    primedEquipment = [self cxx_eqScriptIndexForKey:eqKey]; // if key not found primedEquipment is set to primed-none
    BOOL unprimeEq = eqKey.empty();
    BOOL result = YES;

    if (primedEquipment == c && !unprimeEq) {
        primedEquipment = current;
        result = NO;
    } else {
        if (primedEquipment != current && showMsg == YES) {
            if (unprimeEq) {
                [UNIVERSE addMessage:OOExpandKey(@"equipment-primed-none") forCount:2.0];
            } else {
                // (a nil name raised in the expansion)
                const std::string equipmentName = oo::StdString([[OOEquipmentType equipmentTypeWithIdentifier:oo::NSStringFrom(eqScripts[primedEquipment].first)] name]);
                [UNIVERSE addMessage:oo::NSStringFrom(ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "equipment-primed", { { "equipmentName", oo::PList(equipmentName) } })) forCount:2.0];
            }
        }
    }
    return result;
}

- (void)activatePrimableEquipment:(NSUInteger)index withMode:(OOPrimedEquipmentMode)mode
{
    // index == eqScripts.size() means we don't want to activate any equipment.
    if (index < eqScripts.size()) {
        OOJSScript* eqScript = eqScripts[index].second.get();
        JSContext* context = OOJSAcquireContext();
        NSAssert1(mode <= OOPRIMEDEQUIP_MODE, @"Primable equipment mode %i out of range", (int)mode);

        switch (mode) {
        case OOPRIMEDEQUIP_MODE:
            [eqScript callMethod:OOJSID("mode") inContext:context withArguments:NULL count:0 result:NULL];
            break;
        case OOPRIMEDEQUIP_ACTIVATED:
            [eqScript callMethod:OOJSID("activated") inContext:context withArguments:NULL count:0 result:NULL];
            break;
        }
        OOJSRelinquishContext(context);
    }
}

- (std::optional<std::string>)cxx_fastEquipmentA
{
    return _fastEquipmentA;
}

- (std::optional<std::string>)cxx_fastEquipmentB
{
    return _fastEquipmentB;
}

- (void)cxx_setFastEquipmentA:(const std::optional<std::string>&)eqKey
{
    _fastEquipmentA = eqKey;
}

- (void)cxx_setFastEquipmentB:(const std::optional<std::string>&)eqKey
{
    _fastEquipmentB = eqKey;
}

- (OOEquipmentType*)weaponTypeForFacing:(OOWeaponFacing)facing strict:(BOOL)strict
{
    OOWeaponType weaponType = nil;

    switch (facing) {
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

- (id)missilesList // shared selector (proposed ADR-0043)
{
    [self tidyMissilePylons]; // just in case.
    return [super missilesList];
}

- (std::vector<std::string>)cxx_cargoList
{
    std::vector<std::string> manifest;
    const oo::PList list = oo::PListFrom([self cargoListForScripting]);

    if (specialCargo)
        manifest.push_back(*specialCargo);

    for (size_t commodityIndex = 0; commodityIndex < list.count(); commodityIndex++) {
        const oo::PList& commodity = *list.at(commodityIndex);
        NSInteger quantity = commodity.get<NSInteger>("quantity");
        const std::optional<std::string> units = StringForKey(commodity, "unit");
        const std::optional<std::string> commodityName = StringForKey(commodity, "displayName");
        NSInteger containers = commodity.get<int>("containers");
        BOOL extended = !(units.has_value() && *units == oo::StdString(DESC(@"cargo-tons-symbol"))) && containers > 0;

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

- (id)cargoListForScripting // shared selector (proposed ADR-0043)
{
    oo::PList::Array list;

    const std::vector<std::string> goods = oo::StringsFrom([shipCommodityData goods]);
    NSUInteger i, commodityCount = goods.size();
    std::vector<OOCargoQuantity> quantityInHold(commodityCount, 0);
    std::vector<OOCargoQuantity> containersInHold(commodityCount, 0);

    // following changed to work whether docked or not
    for (i = 0; i < commodityCount; i++) {
        quantityInHold[i] = [shipCommodityData cxx_quantityForGood:goods[i]];
    }
    for (i = 0; i < cargo.size(); i++) {
        ShipEntity* container = cargo[i].get();
        const std::optional<std::string> good = [container cxx_commodityType];
        const auto j = good.has_value() ? std::ranges::find(goods, *good) : goods.end();
        // A pod whose commodity is not a good (or has none) indexed past the arrays before; it is skipped.
        if (j == goods.end())
            continue;
        quantityInHold[(std::size_t)(j - goods.begin())] += [container commodityAmount];
        ++containersInHold[(std::size_t)(j - goods.begin())];
    }

    for (i = 0; i < commodityCount; i++) {
        if (quantityInHold[i] > 0) {
            oo::PList::Dict commodity;
            const std::string& symName = goods[i];
            // commodity, quantity - keep consistency between .manifest and .contracts
            commodity["commodity"] = symName;
            commodity["quantity"] = oo::PList::unsignedInteger(quantityInHold[i]); // +numberWithUnsignedInt:
            commodity["containers"] = oo::PList::unsignedInteger(containersInHold[i]);
            const std::optional<std::string> goodName = [shipCommodityData cxx_nameForGood:symName];
            if (goodName.has_value())
                commodity["displayName"] = *goodName; // (nil raised before)
            commodity["unit"] = oo::StdString(DisplayStringForMassUnitForCommodity(oo::NSStringFrom(symName)));
            list.emplace_back(std::move(commodity));
        }
    }

    return oo::ObjectFromPList(oo::PList(std::move(list))); // an immutable array
}

// determines general export legality, not tied to a station
- (unsigned)legalStatusOfCargoList
{
    OOCargoQuantity amount;
    unsigned penalty = 0;

    for (const std::string& good : oo::StringsFrom([shipCommodityData goods])) {
        amount = [shipCommodityData cxx_quantityForGood:good];
        penalty += [shipCommodityData cxx_exportLegalityForGood:good] * amount;
    }
    return penalty;
}

- (oo::PList::Array)contractsListForScriptingFromArray:(const oo::PList::Array&)contracts_array forCargo:(BOOL)forCargo
{
    oo::PList::Array result;
    NSUInteger i;

    // (a nil value raised in -setObject:forKey: before; it is left out)
    const auto setString = [](oo::PList::Dict& contract, const std::string& key, const std::optional<std::string>& value) {
        if (value.has_value())
            contract[key] = *value;
    };

    for (i = 0; i < contracts_array.size(); i++) {
        oo::PList::Dict contract;
        const oo::PList& dict = contracts_array[i];
        if (forCargo) {
            // commodity, quantity - keep consistency between .manifest and .contracts
            setString(contract, "commodity", StringForKey(dict, oo::StdString(CARGO_KEY_TYPE)));
            contract["quantity"] = oo::PList::unsignedInteger(static_cast<unsigned int>(dict.get<int>(oo::StdString(CARGO_KEY_AMOUNT)))); // +numberWithUnsignedInt:
            setString(contract, "description", StringForKey(dict, oo::StdString(CARGO_KEY_DESCRIPTION)));
        } else {
            setString(contract, oo::StdString(PASSENGER_KEY_NAME), StringForKey(dict, oo::StdString(PASSENGER_KEY_NAME)));
            contract[oo::StdString(CONTRACT_KEY_RISK)] = oo::PList::unsignedInteger(dict.get<unsigned int>(oo::StdString(CONTRACT_KEY_RISK)));
        }

        OOSystemID planet = dict.get<int>(oo::StdString(CONTRACT_KEY_DESTINATION));
        std::optional<std::string> planetName = oo::OptionalString([UNIVERSE getSystemName:planet]);
        contract[oo::StdString(CONTRACT_KEY_DESTINATION)] = oo::PList::unsignedInteger(static_cast<unsigned int>(planet));
        setString(contract, "destinationName", planetName);
        planet = dict.get<int>(oo::StdString(CONTRACT_KEY_START));
        planetName = oo::OptionalString([UNIVERSE getSystemName:planet]);
        contract[oo::StdString(CONTRACT_KEY_START)] = oo::PList::unsignedInteger(static_cast<unsigned int>(planet));
        setString(contract, "startName", planetName);

        int dest_eta = dict.get<double>(oo::StdString(CONTRACT_KEY_ARRIVAL_TIME)) - ship_clock;
        contract["eta"] = oo::PList::signedInteger(dest_eta);
        setString(contract, "etaDescription", oo::OptionalString([UNIVERSE shortTimeDescription:dest_eta]));
        contract[oo::StdString(CONTRACT_KEY_PREMIUM)] = oo::PList::signedInteger(dict.get<int>(oo::StdString(CONTRACT_KEY_PREMIUM)));
        contract[oo::StdString(CONTRACT_KEY_FEE)] = oo::PList::signedInteger(dict.get<int>(oo::StdString(CONTRACT_KEY_FEE)));
        result.emplace_back(std::move(contract));
    }

    return result;
}

- (id)passengerListForScripting // shared selector (proposed ADR-0043)
{
    return oo::ObjectFromPList(oo::PList([self contractsListForScriptingFromArray:passengers forCargo:NO])); // an immutable array
}

- (id)parcelListForScripting // shared selector (proposed ADR-0043)
{
    return oo::ObjectFromPList(oo::PList([self contractsListForScriptingFromArray:parcels forCargo:NO])); // an immutable array
}

- (id)contractListForScripting // shared selector (proposed ADR-0043)
{
    return oo::ObjectFromPList(oo::PList([self contractsListForScriptingFromArray:contracts forCargo:YES])); // an immutable array
}

- (void)setGuiToSystemDataScreen
{
    [self setGuiToSystemDataScreenRefreshBackground:NO];
}

- (void)setGuiToSystemDataScreenRefreshBackground:(BOOL)refreshBackground
{
    const oo::PList infoSystemData = oo::PListFrom([UNIVERSE generateSystemData:info_system_id]);
    NSInteger concealment = infoSystemData.get<int>("concealment", OO_SYSTEMCONCEALMENT_NONE);
    const std::string infoSystemName = StringForKey(infoSystemData, oo::StdString(KEY_NAME)).value_or(std::string()); // (a nil name raised in the expansions below)

    BOOL sunGoneNova = (infoSystemData.get<bool>("sun_gone_nova"));
    OOGUIScreenID oldScreen = gui_screen;

    GuiDisplayGen* gui = [UNIVERSE gui];
    gui_screen = GUI_SCREEN_SYSTEM_DATA;
    BOOL guiChanged = (oldScreen != gui_screen);

    Random_Seed infoSystemRandomSeed = [[UNIVERSE systemManager] getRandomSeedForSystem:info_system_id
                                                                               inGalaxy:[self galaxyNumber]];

    [[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:NO];

    // GUI stuff
    {
        OOGUITabSettings tab_stops;
        tab_stops[0] = 0;
        tab_stops[1] = 96;
        tab_stops[2] = 144;
        [gui overrideTabs:tab_stops from:kGuiSystemdataTabs length:3];
        [gui setTabStops:tab_stops];

        NSUInteger techLevel = infoSystemData.get<int>(oo::StdString(KEY_TECHLEVEL)) + 1;
        int population = infoSystemData.get<int>(oo::StdString(KEY_POPULATION));
        int productivity = infoSystemData.get<int>(oo::StdString(KEY_PRODUCTIVITY));
        int radius = infoSystemData.get<int>(oo::StdString(KEY_RADIUS));

        std::string government_desc = StringForKey(infoSystemData, oo::StdString(KEY_GOVERNMENT_DESC))
                                          .value_or(oo::StdString(OODisplayStringFromGovernmentID(infoSystemData.get<int>(oo::StdString(KEY_GOVERNMENT)))));
        std::string economy_desc = StringForKey(infoSystemData, oo::StdString(KEY_ECONOMY_DESC))
                                       .value_or(oo::StdString(OODisplayStringFromEconomyID(infoSystemData.get<int>(oo::StdString(KEY_ECONOMY)))));
        std::string inhabitants = StringForKey(infoSystemData, oo::StdString(KEY_INHABITANTS)).value_or(std::string()); // (nil raised in the expansion)
        std::optional<std::string> system_desc = StringForKey(infoSystemData, oo::StdString(KEY_DESCRIPTION));

        std::string populationDesc = StringForKey(infoSystemData, oo::StdString(KEY_POPULATION_DESC))
                                         .value_or(oo::StdString(OOExpandKeyWithSeed(kNilRandomSeed, @"sysdata-pop-value", population)));

        if (sunGoneNova) {
            population = 0;
            productivity = 0;
            radius = 0;
            techLevel = 0;

            government_desc = oo::StdString(OOExpandKeyWithSeed(infoSystemRandomSeed, @"nova-system-government"));
            economy_desc = oo::StdString(OOExpandKeyWithSeed(infoSystemRandomSeed, @"nova-system-economy"));
            inhabitants = oo::StdString(OOExpandKeyWithSeed(infoSystemRandomSeed, @"nova-system-inhabitants"));
            system_desc = ExpandKeyWithSeed(infoSystemRandomSeed, "nova-system-description", { { "system", oo::PList(infoSystemName) } });
            populationDesc = oo::StdString(OOExpandKeyWithSeed(infoSystemRandomSeed, @"sysdata-pop-value", population));
        }

        [gui clearAndKeepBackground:!refreshBackground && !guiChanged];
        [UNIVERSE removeDemoShips];

        if (concealment < OO_SYSTEMCONCEALMENT_NONAME) {
            [gui setTitle:oo::NSStringFrom(ExpandKeyWithSeed(infoSystemRandomSeed, "sysdata-data-on-system", { { "system", oo::PList(infoSystemName) } }))];
        } else {
            [gui setTitle:OOExpandKey(@"sysdata-data-on-system-no-name")];
        }

        if (concealment >= OO_SYSTEMCONCEALMENT_NODATA) {
            OOGUIRow i = [gui addLongText:OOExpandKey(@"sysdata-data-on-system-no-data") startingAtRow:15 align:GUI_ALIGN_LEFT];
            missionTextRow = i;
            for (i--; i > 14; --i) {
                [gui setColor:[gui colorFromSetting:kGuiSystemdataDescriptionColor defaultValue:[OOColor greenColor]] forRow:i];
            }
        } else {
            NSPoint infoSystemCoordinates = [[UNIVERSE systemManager] getCoordinatesForSystem:info_system_id inGalaxy:galaxy_number];
            double distance = distanceBetweenPlanetPositions(infoSystemCoordinates.x, infoSystemCoordinates.y, galaxy_coordinates.x, galaxy_coordinates.y);
            if (distance == 0.0 && info_system_id != system_id) {
                distance = 0.1;
            }
            std::string distanceInfo = oo::str::format("%.1f ly", distance);
            if (ANA_mode != OPTIMIZED_BY_NONE) {
                const oo::PList routeInfo = oo::PListFrom([UNIVERSE routeFromSystem:system_id toSystem:info_system_id optimizedBy:ANA_mode]);
                if (!routeInfo.isNull()) {
                    double routeDistance = routeInfo.get<double>("distance");
                    double routeTime = routeInfo.get<double>("time");
                    int routeJumps = routeInfo.get<int>("jumps");
                    if (routeDistance == 0.0 && info_system_id != system_id) {
                        routeDistance = 0.1;
                        routeTime = 0.01;
                        routeJumps = 0;
                    }
                    distanceInfo = oo::str::format("%.1f ly / %.1f %s / %d %s",
                        routeDistance,
                        routeTime,
                        // don't rely on DESC_PLURAL for routeTime since it is of type double
                        oo::DescriptionOf(routeTime > 1.05 || routeTime < 0.95 ? DESC(@"sysdata-route-hours%1") : DESC(@"sysdata-route-hours%0")).c_str(),
                        routeJumps,
                        oo::DescriptionOf(DESC_PLURAL(@"sysdata-route-jumps", routeJumps)).c_str());
                }
            }

            OOGUIRow i;

            for (i = 1; i <= 16; i++) {
                const std::string ln = oo::str::format("sysdata-line-%ld", (long)i);
                const std::string line = ExpandKeyWithSeed(infoSystemRandomSeed, ln, { { "economy_desc", oo::PList(economy_desc) }, { "government_desc", oo::PList(government_desc) }, { "techLevel", oo::PList::unsignedInteger(techLevel) }, { "populationDesc", oo::PList(populationDesc) }, { "inhabitants", oo::PList(inhabitants) }, { "productivity", oo::PList::signedInteger(productivity) }, { "radius", oo::PList::signedInteger(radius) }, { "distanceInfo", oo::PList(distanceInfo) } });
                if (!line.empty()) {
                    const std::vector<std::string> lines = oo::str::split(line, "\t");
                    if (lines.size() == 1) {
                        [gui cxx_setArray: { lines[0] }
                                   forRow:i];
                    }
                    if (lines.size() == 2) {
                        [gui cxx_setArray: { lines[0], lines[1] }
                                   forRow:i];
                    }
                    if (lines.size() == 3) {
                        if (lines[2].empty()) {
                            [gui cxx_setArray: { lines[0], lines[1] }
                                       forRow:i];
                        } else {
                            [gui cxx_setArray: { lines[0], lines[1], lines[2] }
                                       forRow:i];
                        }
                    }
                } else {
                    [gui cxx_setArray:std::vector<std::string> { std::string() }
                               forRow:i];
                }
            }

            i = [gui cxx_addLongText:system_desc startingAtRow:17 align:GUI_ALIGN_LEFT];
            missionTextRow = i;
            for (i--; i > 16; --i) {
                [gui setColor:[gui colorFromSetting:kGuiSystemdataDescriptionColor defaultValue:[OOColor greenColor]] forRow:i];
            }
            for (i = 1; i <= 14; ++i) {
                // nil default = fall back to global default colour
                [gui setColor:[gui colorFromSetting:kGuiSystemdataFactsColor defaultValue:nil] forRow:i];
            }
        }

        [gui setShowTextCursor:NO];
    }
    /* ends */

    lastTextKey.reset();

    [[UNIVERSE gameView] clearMouse];

    [self setShowDemoShips:NO];
    [UNIVERSE enterGUIViewModeWithMouseInteraction:NO];

    // if the system has gone nova, there's no planet to display
    if (!sunGoneNova && concealment < OO_SYSTEMCONCEALMENT_NODATA) {
        // The next code is generating the miniature planets.
        // When normal planets are displayed, the PRNG is reset. This happens not with procedural planet display.
        RANROTSeed ranrotSavedSeed = RANROTGetFullSeed();
        RNG_Seed saved_seed = currentRandomSeed();

        if (info_system_id == system_id) {
            [self setBackgroundFromDescriptionsKey:@"gui-scene-show-local-planet"];
        } else {
            [self setBackgroundFromDescriptionsKey:@"gui-scene-show-planet"];
        }

        setRandomSeed(saved_seed);
        RANROTSetFullSeed(ranrotSavedSeed);
    }

    if (refreshBackground || guiChanged) {
        [gui setForegroundTextureKey:[self status] == STATUS_DOCKED ? @"docked_overlay" : @"overlay"];
        [gui setBackgroundTextureKey:sunGoneNova ? @"system_data_nova" : @"system_data"];

        [self noteGUIDidChangeFrom:oldScreen to:gui_screen refresh:refreshBackground];
        [self checkScript]; // Still needed by some OXPs?
    }
}

namespace {

// -prepareMarkedDestination:: appended the marker to the list for its "system" (the old
// +numberWithInt: key), creating the list on first use.
void PrepareMarkedDestination(std::map<int, std::vector<oo::PList>>& markers, oo::PList marker)
{
    const int system = marker.get<int>("system");
    markers[system].push_back(std::move(marker));
}

} // namespace

- (std::optional<std::map<int, std::vector<oo::PList>>>)cxx_markedDestinations // passengers, parcels, contracts, then mission destinations
{
    // get a list of systems marked as contract destinations
    std::map<int, std::vector<oo::PList>> destinations;
    unsigned i;
    OOSystemID sysid;

    for (i = 0; i < passengers.size(); i++) {
        sysid = passengers[i].get<unsigned char>(oo::StdString(CONTRACT_KEY_DESTINATION));
        PrepareMarkedDestination(destinations, [self cxx_passengerContractMarker:sysid]);
    }
    for (i = 0; i < parcels.size(); i++) {
        sysid = parcels[i].get<unsigned char>(oo::StdString(CONTRACT_KEY_DESTINATION));
        PrepareMarkedDestination(destinations, [self cxx_parcelContractMarker:sysid]);
    }
    for (i = 0; i < contracts.size(); i++) {
        sysid = contracts[i].get<unsigned char>(oo::StdString(CONTRACT_KEY_DESTINATION));
        PrepareMarkedDestination(destinations, [self cxx_cargoContractMarker:sysid]);
    }

    // ORDER-SENSITIVE: markers within a system now come in the map's byte order of keys (the
    // dictionary's own key order before); a marker is plist data
    for (const auto& entry : missionDestinations) {
        PrepareMarkedDestination(destinations, entry.second);
    }

    return destinations;
}

- (void)setGuiToLongRangeChartScreen
{
    OOGUIScreenID oldScreen = gui_screen;
    GuiDisplayGen* gui = [UNIVERSE gui];
    [gui clearAndKeepBackground:NO];
    [gui setBackgroundTextureKey:@"short_range_chart"];
    [self setMissionBackgroundSpecial:nil];
    gui_screen = GUI_SCREEN_LONG_RANGE_CHART;
    target_chart_zoom = CHART_MAX_ZOOM;
    [self setGuiToChartScreenFrom:oldScreen];
}

- (void)setGuiToShortRangeChartScreen
{
    OOGUIScreenID oldScreen = gui_screen;
    GuiDisplayGen* gui = [UNIVERSE gui];
    [gui clearAndKeepBackground:NO];
    [gui setBackgroundTextureKey:@"short_range_chart"];
    [self setMissionBackgroundSpecial:nil];
    gui_screen = GUI_SCREEN_SHORT_RANGE_CHART;
    [self setGuiToChartScreenFrom:oldScreen];
}

- (void)setGuiToChartScreenFrom:(OOGUIScreenID)oldScreen
{
    GuiDisplayGen* gui = [UNIVERSE gui];

    BOOL guiChanged = (oldScreen != gui_screen);

    [[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:YES];

    target_system_id = [UNIVERSE findSystemNumberAtCoords:cursor_coordinates withGalaxy:galaxy_number includingHidden:NO];

    [UNIVERSE preloadPlanetTexturesForSystem:target_system_id];

    // GUI stuff
    {
        //[gui clearAndKeepBackground:!guiChanged];
        [gui setStarChartTitle];
        // refresh the short range chart cache, in case we've just loaded a save game with different local overrides, etc.
        [gui refreshStarChart];
        //[gui setText:targetSystemName forRow:19];
        // distance-f & est-travel-time-f are identical between short & long range charts in standard Oolite, however can be alterered separately via OXPs
        //[gui setText:OOExpandKey(@"short-range-chart-distance", distance) forRow:20];
        // std::string travelTimeRow;
        // if ([self hasHyperspaceMotor] && distance > 0.0 && distance * 10.0 <= fuel)
        //{
        //	double time = estimatedTravelTime;
        //	travelTimeRow = OOExpandKey(@"short-range-chart-est-travel-time", time);
        //}
        //[gui setText:travelTimeRow forRow:21];
        if (gui_screen == GUI_SCREEN_LONG_RANGE_CHART) {
            const std::optional<std::string> searchString = planetSearchString;
            const std::string displaySearchString = searchString.has_value() ? oo::str::capitalized(*searchString) : std::string();
            [gui cxx_setText:oo::str::formatRuntime(oo::StdString(DESC(@"long-range-chart-find-planet-@")), { displaySearchString }) forRow:GUI_ROW_PLANET_FINDER];
            [gui setColor:[OOColor cyanColor] forRow:GUI_ROW_PLANET_FINDER];
            [gui setShowTextCursor:YES];
            [gui setCurrentRow:GUI_ROW_PLANET_FINDER];
        } else {
            [gui setShowTextCursor:NO];
        }
    }
    /* ends */

    [self setShowDemoShips:NO];
    [UNIVERSE enterGUIViewModeWithMouseInteraction:YES];

    if (guiChanged) {
        [gui setForegroundTextureKey:[self status] == STATUS_DOCKED ? @"docked_overlay" : @"overlay"];

        [gui setBackgroundTextureKey:@"short_range_chart"];
        if (found_system_id >= 0) {
            [UNIVERSE findSystemCoordinatesWithPrefix:[[UNIVERSE getSystemName:found_system_id] lowercaseString] exactMatch:YES];
        }
        [self noteGUIDidChangeFrom:oldScreen to:gui_screen];
    }
}

namespace {

std::string SliderString(NSInteger amountIn20ths)
{
    std::string filledSlider = std::string("|||||||||||||||||||||||||").substr(0, static_cast<std::size_t>(amountIn20ths));
    std::string emptySlider = std::string(".........................").substr(0, static_cast<std::size_t>(20 - amountIn20ths));
    return filledSlider + emptySlider;
}

} // namespace

- (void)setGuiToGameOptionsScreen
{
    MyOpenGLView* gameView = [UNIVERSE gameView];

    [[UNIVERSE gameView] clearMouse];
    [[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:YES];

    gui_screen = GUI_SCREEN_GAMEOPTIONS;

    // GUI stuff
    {
#define OO_SETACCESSCONDITIONFORROW(condition, row)                  \
    do {                                                             \
        if ((condition)) {                                           \
            [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:(row)]; \
        } else {                                                     \
            [gui setColor:[OOColor grayColor] forRow:(row)];         \
        }                                                            \
    } while (0)
        BOOL startingGame = [self status] == STATUS_START_GAME;
        GuiDisplayGen* gui = [UNIVERSE gui];
        GUI_ROW_INIT(gui);

        int first_sel_row = GUI_FIRST_ROW(GAME) - 4; // repositioned menu

        [gui clear];
        [gui setTitle:oo::NSStringFrom(oo::str::formatRuntime(oo::StdString(DESC(@"status-commander-@")), { TextArg([self cxx_commanderName]) }))]; // Same title as status screen.

#if OO_RESOLUTION_OPTION
        GameController* controller = [UNIVERSE gameController];

        NSUInteger displayModeIndex = [controller indexOfCurrentDisplayMode];
        if (displayModeIndex == NSNotFound) {
            OO_LOG_WARN("display.currentMode.notFound", "{}", "couldn't find current fullscreen setting, switching to default.");
            displayModeIndex = 0;
        }

        const oo::PList modeList = oo::PListFrom([controller displayModes]);
        const oo::PList* mode = nullptr;
        if (modeList.count()) {
            mode = modeList.at(displayModeIndex);
        }
        if (mode == nullptr)
            return; // Got a better idea?

        unsigned modeWidth = mode->get<unsigned int>(oo::StdString(kOODisplayWidth));
        unsigned modeHeight = mode->get<unsigned int>(oo::StdString(kOODisplayHeight));
        float modeRefresh = mode->get<float>(oo::StdString(kOODisplayRefreshRate));

        BOOL runningOnPrimaryDisplayDevice = [gameView isRunningOnPrimaryDisplayDevice];
        if (!runningOnPrimaryDisplayDevice) {
            [gameView getDisplayDimensions:&modeWidth height:&modeHeight];
        }

        const std::optional<std::string> displayModeString = [self cxx_screenModeStringForWidth:modeWidth height:modeHeight refreshRate:modeRefresh];

        [gui cxx_setText:displayModeString forRow:GUI_ROW(GAME, DISPLAY) align:GUI_ALIGN_CENTER];
        if (runningOnPrimaryDisplayDevice) {
            [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW(GAME, DISPLAY)];
        } else {
            [gui setColor:[OOColor grayColor] forRow:GUI_ROW(GAME, DISPLAY)];
        }
#endif // OO_RESOLUTIOM_OPTION

#if OOLITE_WINDOWS
        if ([gameView hdrOutput]) {
            const oo::PList brightnessesValue = oo::PListFrom([[UNIVERSE descriptions] objectForKey:@"hdr_maxBrightness_array"]);
            const oo::PList brightnesses = brightnessesValue.isArray() ? brightnessesValue : oo::PList();
            // -indexOfObject: with the %d string: only string elements ever matched; not found was NSNotFound narrowed to int
            const std::string currentBrightness = std::to_string((int)[gameView hdrMaxBrightness]);
            int brightnessIdx = static_cast<int>(NSNotFound);
            for (std::size_t i = 0; i < brightnesses.count(); i++) {
                const oo::PList* element = brightnesses.at(i);
                if (element->isString() && *element->getIf<std::string>() == currentBrightness) {
                    brightnessIdx = static_cast<int>(i);
                    break;
                }
            }

            if (static_cast<NSInteger>(brightnessIdx) == NSNotFound) {
                OO_LOG_WARN("hdr.maxBrightness.notFound", "{}", "couldn't find current max brightness setting, switching to 400 nits.");
                brightnessIdx = 0;
            }

            int brightnessValue = brightnesses.at<int>(static_cast<std::size_t>(brightnessIdx));
            const std::string maxBrightnessString = oo::StdString(OOExpandKey(@"gameoptions-hdr-maxbrightness", brightnessValue));

            [gui cxx_setText:maxBrightnessString forRow:GUI_ROW(GAME, HDRMAXBRIGHTNESS) align:GUI_ALIGN_CENTER];
            [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW(GAME, HDRMAXBRIGHTNESS)];
        }
#endif

        if ([UNIVERSE autoSave])
            [gui cxx_setText:oo::StdString(DESC(@"gameoptions-autosave-yes")) forRow:GUI_ROW(GAME, AUTOSAVE) align:GUI_ALIGN_CENTER];
        else
            [gui cxx_setText:oo::StdString(DESC(@"gameoptions-autosave-no")) forRow:GUI_ROW(GAME, AUTOSAVE) align:GUI_ALIGN_CENTER];
        [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW(GAME, AUTOSAVE)];

        // volume control
        if ([OOSound respondsToSelector:@selector(masterVolume)] && [OOSound isSoundOK]) {
            double volume = 100.0 * [OOSound masterVolume];
            int vol = (volume / 5.0 + 0.5); // avoid rounding errors
            const std::string soundVolumeWordDesc = oo::StdString(DESC(@"gameoptions-sound-volume"));
            if (vol > 0)
                [gui cxx_setText:oo::str::format("%s%s ", soundVolumeWordDesc.c_str(), SliderString(vol).c_str()) forRow:GUI_ROW(GAME, VOLUME) align:GUI_ALIGN_CENTER];
            else
                [gui cxx_setText:oo::StdString(DESC(@"gameoptions-sound-volume-mute")) forRow:GUI_ROW(GAME, VOLUME) align:GUI_ALIGN_CENTER];
            [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW(GAME, VOLUME)];
        } else {
            [gui cxx_setText:oo::StdString(DESC(@"gameoptions-volume-external-only")) forRow:GUI_ROW(GAME, VOLUME) align:GUI_ALIGN_CENTER];
            [gui setColor:[OOColor grayColor] forRow:GUI_ROW(GAME, VOLUME)];
        }

        // field of view control
        float fov = [gameView fov:NO];
        int fovTicks = (int)((fov - MIN_FOV_DEG) * 20 / (MAX_FOV_DEG - MIN_FOV_DEG));
        const std::string fovWordDesc = oo::DescriptionOf(DESC(@"gameoptions-fov-value"));
        // %c 176 gave U+00B0 (probed on GNUstep base, oo-3rb.218); written as its UTF-8 bytes
        [gui cxx_setText:oo::str::format("%s%s (%d%s) ", fovWordDesc.c_str(), SliderString(fovTicks).c_str(), (int)fov, "\xC2\xB0" /*the degrees symbol*/) forRow:GUI_ROW(GAME, FOV) align:GUI_ALIGN_CENTER];
        [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW(GAME, FOV)];

        // color blind mode
        int colorblindMode = [UNIVERSE colorblindMode];
        const oo::PList colorblindModes = oo::PListFrom([[UNIVERSE descriptions] objectForKey:@"colorblind_mode"]);
        const std::string colorblindModeDesc = colorblindModes.isArray() ? colorblindModes.at<std::string>(static_cast<std::size_t>([UNIVERSE useShaders] ? colorblindMode : 0)) : std::string(); // (nil raised in the expansion)
        const std::string colorblindModeMsg = ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "gameoptions-colorblind-mode", { { "colorblindModeDesc", oo::PList(colorblindModeDesc) } });
        [gui cxx_setText:colorblindModeMsg forRow:GUI_ROW(GAME, COLORBLINDMODE) align:GUI_ALIGN_CENTER];
        if ([UNIVERSE useShaders]) {
            [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW(GAME, COLORBLINDMODE)];
        } else {
            [gui setColor:[OOColor grayColor] forRow:GUI_ROW(GAME, COLORBLINDMODE)];
        }

#if OOLITE_SPEECH_SYNTH
        // Speech control
        switch (isSpeechOn) {
        case OOSPEECHSETTINGS_OFF:
            [gui cxx_setText:oo::StdString(DESC(@"gameoptions-spoken-messages-no")) forRow:GUI_ROW(GAME, SPEECH) align:GUI_ALIGN_CENTER];
            break;
        case OOSPEECHSETTINGS_COMMS:
            [gui cxx_setText:oo::StdString(DESC(@"gameoptions-spoken-messages-comms")) forRow:GUI_ROW(GAME, SPEECH) align:GUI_ALIGN_CENTER];
            break;
        case OOSPEECHSETTINGS_ALL:
            [gui cxx_setText:oo::StdString(DESC(@"gameoptions-spoken-messages-yes")) forRow:GUI_ROW(GAME, SPEECH) align:GUI_ALIGN_CENTER];
            break;
        }
        OO_SETACCESSCONDITIONFORROW(!startingGame, GUI_ROW(GAME, SPEECH));

#if OOLITE_ESPEAK
        {
            const std::string voiceName = oo::StdString([UNIVERSE voiceName:voice_no]);
            std::string message = ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "gameoptions-voice-name", { { "voiceName", oo::PList(voiceName) } });
            [gui cxx_setText:message forRow:GUI_ROW(GAME, SPEECH_LANGUAGE) align:GUI_ALIGN_CENTER];
            OO_SETACCESSCONDITIONFORROW(!startingGame, GUI_ROW(GAME, SPEECH_LANGUAGE));

            message = oo::DescriptionOf(DESC(voice_gender_m ? @"gameoptions-voice-M" : @"gameoptions-voice-F"));
            [gui cxx_setText:message forRow:GUI_ROW(GAME, SPEECH_GENDER) align:GUI_ALIGN_CENTER];
            OO_SETACCESSCONDITIONFORROW(!startingGame, GUI_ROW(GAME, SPEECH_GENDER));
        }
#endif
#endif
#if !OOLITE_MAC_COCOA_UI
        // window/fullscreen
        if ([gameView inFullScreenMode]) {
            [gui cxx_setText:oo::StdString(DESC(@"gameoptions-play-in-window")) forRow:GUI_ROW(GAME, DISPLAYSTYLE) align:GUI_ALIGN_CENTER];
        } else {
            [gui cxx_setText:oo::StdString(DESC(@"gameoptions-play-in-fullscreen")) forRow:GUI_ROW(GAME, DISPLAYSTYLE) align:GUI_ALIGN_CENTER];
        }
        [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW(GAME, DISPLAYSTYLE)];
#endif

        [gui cxx_setText:oo::StdString(DESC(@"gameoptions-joystick-configuration"))
                  forRow:GUI_ROW(GAME, STICKMAPPER)
                   align:GUI_ALIGN_CENTER];
        OO_SETACCESSCONDITIONFORROW([[OOJoystickManager sharedStickHandler] joystickCount], GUI_ROW(GAME, STICKMAPPER));

        [gui cxx_setText:oo::StdString(DESC(@"gameoptions-keyboard-configuration")) forRow:GUI_ROW(GAME, KEYMAPPER) align:GUI_ALIGN_CENTER];
        [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW(GAME, KEYMAPPER)];

        const std::string musicMode = oo::StdString([UNIVERSE descriptionForArrayKey:@"music-mode" index:[[OOMusicController sharedController] mode]]);
        const std::string message = ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "gameoptions-music-mode", { { "musicMode", oo::PList(musicMode) } });
        [gui cxx_setText:message forRow:GUI_ROW(GAME, MUSIC) align:GUI_ALIGN_CENTER];
        [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW(GAME, MUSIC)];

        if (![gameView hdrOutput]) {
            if ([UNIVERSE wireframeGraphics])
                [gui cxx_setText:oo::StdString(DESC(@"gameoptions-wireframe-graphics-yes")) forRow:GUI_ROW(GAME, WIREFRAMEGRAPHICS) align:GUI_ALIGN_CENTER];
            else
                [gui cxx_setText:oo::StdString(DESC(@"gameoptions-wireframe-graphics-no")) forRow:GUI_ROW(GAME, WIREFRAMEGRAPHICS) align:GUI_ALIGN_CENTER];
            [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW(GAME, WIREFRAMEGRAPHICS)];
        }
#if OOLITE_WINDOWS
        else {
            float paperWhite = [gameView hdrPaperWhiteBrightness];
            int paperWhiteTicks = (int)((paperWhite - MIN_HDR_PAPERWHITE) * 20 / (MAX_HDR_PAPERWHITE - MIN_HDR_PAPERWHITE));
            const std::string paperWhiteWordDesc = oo::DescriptionOf(DESC(@"gameoptions-hdr-paperwhite"));
            [gui cxx_setText:oo::str::format("%s%s (%d) ", paperWhiteWordDesc.c_str(), SliderString(paperWhiteTicks).c_str(), (int)paperWhite) forRow:GUI_ROW(GAME, HDRPAPERWHITE) align:GUI_ALIGN_CENTER];
            [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW(GAME, HDRPAPERWHITE)];
        }
#endif

#if !NEW_PLANETS
        if ([UNIVERSE doProcedurallyTexturedPlanets])
            [gui cxx_setText:oo::StdString(DESC(@"gameoptions-procedurally-textured-planets-yes")) forRow:GUI_ROW(GAME, PROCEDURALLYTEXTUREDPLANETS) align:GUI_ALIGN_CENTER];
        else
            [gui cxx_setText:oo::StdString(DESC(@"gameoptions-procedurally-textured-planets-no")) forRow:GUI_ROW(GAME, PROCEDURALLYTEXTUREDPLANETS) align:GUI_ALIGN_CENTER];
        [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW(GAME, PROCEDURALLYTEXTUREDPLANETS)];
#endif

        OOGraphicsDetail detailLevel = [UNIVERSE detailLevel];
        const std::string shaderEffectsOptionsString = oo::StdString(OOExpand(@"gameoptions-detaillevel-[detailLevel]", detailLevel));
        [gui cxx_setText:ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), shaderEffectsOptionsString, { }) forRow:GUI_ROW(GAME, SHADEREFFECTS) align:GUI_ALIGN_CENTER];
        if (![[OOOpenGLExtensionManager sharedManager] shadersForceDisabled]) {
            [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW(GAME, SHADEREFFECTS)];
        } else {
            // deactivate this option if shaders have been disabled from the commend line
            [gui setColor:[OOColor grayColor] forRow:GUI_ROW(GAME, SHADEREFFECTS)];
        }

        if ([UNIVERSE dockingClearanceProtocolActive]) {
            [gui cxx_setText:oo::StdString(DESC(@"gameoptions-docking-clearance-yes")) forRow:GUI_ROW(GAME, DOCKINGCLEARANCE) align:GUI_ALIGN_CENTER];
        } else {
            [gui cxx_setText:oo::StdString(DESC(@"gameoptions-docking-clearance-no")) forRow:GUI_ROW(GAME, DOCKINGCLEARANCE) align:GUI_ALIGN_CENTER];
        }
        OO_SETACCESSCONDITIONFORROW(!startingGame, GUI_ROW(GAME, DOCKINGCLEARANCE));

        // Back menu option
        [gui cxx_setText:oo::StdString(DESC(@"gui-back")) forRow:GUI_ROW(GAME, BACK) align:GUI_ALIGN_CENTER];
        [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW(GAME, BACK)];

        [gui setSelectableRange:NSMakeRange(first_sel_row, GUI_ROW_GAMEOPTIONS_END_OF_LIST)];
        [gui setSelectedRow:first_sel_row];

        [gui setShowTextCursor:NO];
        [gui setForegroundTextureKey:[self status] == STATUS_DOCKED ? @"docked_overlay" : @"paused_overlay"];
        [gui setBackgroundTextureKey:@"settings"];
    }
    /* ends */

    [self setShowDemoShips:NO];
    [UNIVERSE enterGUIViewModeWithMouseInteraction:YES];
}

- (void)setGuiToLoadSaveScreen
{
    BOOL gamePaused = [[UNIVERSE gameController] isGamePaused];
    BOOL canLoadOrSave = NO;
    MyOpenGLView* gameView = [UNIVERSE gameView];
    OOGUIScreenID oldScreen = gui_screen;

    [[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:YES];

    gui_screen = GUI_SCREEN_OPTIONS;

    if ([self status] == STATUS_DOCKED) {
        if ([self dockedStation] == nil)
            [self setDockedAtMainStation];
        canLoadOrSave = (([self dockedStation] == [UNIVERSE station] || [[self dockedStation] allowsSaving]) && !([[UNIVERSE sun] goneNova] || [[UNIVERSE sun] willGoNova]));
    }

    BOOL canQuickSave = (canLoadOrSave && ([[gameView gameController] playerFileToLoad] != nil));

    // GUI stuff
    {
        GuiDisplayGen* gui = [UNIVERSE gui];
        GUI_ROW_INIT(gui);

        int first_sel_row = (canLoadOrSave) ? GUI_ROW(, SAVE) : GUI_ROW(, GAMEOPTIONS);
        if (canQuickSave)
            first_sel_row = GUI_ROW(, QUICKSAVE);

        [gui clear];
        [gui setTitle:oo::NSStringFrom(oo::str::formatRuntime(oo::StdString(DESC(@"status-commander-@")), { TextArg([self cxx_commanderName]) }))]; // Same title as status screen.

        [gui cxx_setText:oo::StdString(DESC(@"options-quick-save")) forRow:GUI_ROW(, QUICKSAVE) align:GUI_ALIGN_CENTER];
        if (canQuickSave)
            [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW(, QUICKSAVE)];
        else
            [gui setColor:[OOColor grayColor] forRow:GUI_ROW(, QUICKSAVE)];

        [gui cxx_setText:oo::StdString(DESC(@"options-save-commander")) forRow:GUI_ROW(, SAVE) align:GUI_ALIGN_CENTER];
        [gui cxx_setText:oo::StdString(DESC(@"options-load-commander")) forRow:GUI_ROW(, LOAD) align:GUI_ALIGN_CENTER];
        if (canLoadOrSave) {
            [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW(, SAVE)];
            [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW(, LOAD)];
        } else {
            [gui setColor:[OOColor grayColor] forRow:GUI_ROW(, SAVE)];
            [gui setColor:[OOColor grayColor] forRow:GUI_ROW(, LOAD)];
        }

        [gui cxx_setText:oo::StdString(DESC(@"options-return-to-menu")) forRow:GUI_ROW(, BEGIN_NEW) align:GUI_ALIGN_CENTER];
        [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW(, BEGIN_NEW)];

        [gui cxx_setText:oo::StdString(DESC(@"options-game-options")) forRow:GUI_ROW(, GAMEOPTIONS) align:GUI_ALIGN_CENTER];
        [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW(, GAMEOPTIONS)];

#if OOLITE_SDL
        // GNUstep needs a quit option at present (no Cmd-Q) but
        // doesn't need speech.

        // quit menu option
        [gui cxx_setText:oo::StdString(DESC(@"options-exit-game")) forRow:GUI_ROW(, QUIT) align:GUI_ALIGN_CENTER];
        [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW(, QUIT)];
#endif

        [gui setSelectableRange:NSMakeRange(first_sel_row, GUI_ROW_OPTIONS_END_OF_LIST)];

        if (gamePaused || (!canLoadOrSave && [self status] == STATUS_DOCKED)) {
            [gui setSelectedRow:GUI_ROW(, GAMEOPTIONS)];
        } else {
            [gui setSelectedRow:first_sel_row];
        }

        [gui setShowTextCursor:NO];

        if ([gui setForegroundTextureKey:[self status] == STATUS_DOCKED ? @"docked_overlay" : @"paused_overlay"] && [UNIVERSE pauseMessageVisible])
            [[UNIVERSE messageGUI] clear];
        // Graphically, this screen is analogous to the various settings screens
        [gui setBackgroundTextureKey:@"settings"];
    }
    /* ends */

    [[UNIVERSE gameView] clearMouse];

    [self setShowDemoShips:NO];

    [UNIVERSE enterGUIViewModeWithMouseInteraction:YES];

    if (gamePaused) {
        [[UNIVERSE messageGUI] clear];
        const std::optional<std::string> pauseKey = [PLAYER cxx_keyBindingDescription2:"key_pausebutton"];
        [UNIVERSE addMessage:oo::NSStringFrom(ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "game-paused-docked", { { "pauseKey", oo::PList(pauseKey.value_or(std::string())) } })) forCount:1.0 forceDisplay:YES]; // (nil raised in the expansion)
    }

    [self noteGUIDidChangeFrom:oldScreen to:gui_screen];
}

namespace {

std::optional<std::string> last_outfitting_key; // nullopt = none (was nil)

} // namespace

- (void)highlightEquipShipScreenKey:(const std::string&)highlightKey
{
    int i = 0;
    OOGUIRow row;
    std::optional<std::string> otherKey = std::string();
    GuiDisplayGen* gui = [UNIVERSE gui];
    last_outfitting_key = highlightKey;
    [self setGuiToEquipShipScreen:-1];
    const std::optional<std::string> key = last_outfitting_key;
    // TODO: redo the equipShipScreen in a way that isn't broken. this whole method 'works'
    // based on the way setGuiToEquipShipScreen  'worked' on 20090913 - Kaks

    // setGuiToEquipShipScreen doesn't take a page number, it takes an offset from the beginning
    // of the dictionary, the first line will show the key at that offset...

    // try the last page first - 10 pages max.
    while (otherKey) {
        [self setGuiToEquipShipScreen:i];
        for (row = GUI_ROW_EQUIPMENT_START; row <= GUI_MAX_ROWS_EQUIPMENT + 2; row++) {
            otherKey = [gui cxx_keyForRow:row];
            if (!otherKey) {
                [self setGuiToEquipShipScreen:0];
                return;
            }
            if (otherKey == key) {
                [gui setSelectedRow:row];
                [self showInformationForSelectedUpgrade];
                return;
            }
        }
        if (oo::str::hasPrefix(*otherKey, "More:")) {
            const std::vector<std::string> components = oo::str::split(*otherKey, ":");
            i = (components.size() > 1) ? oo::str::intValue(components[1]) : 0;
        } else {
            [self setGuiToEquipShipScreen:0];
            return;
        }
    }
}

- (OOWeaponFacingSet)availableFacings
{
    OOShipRegistry* registry = [OOShipRegistry sharedRegistry];
    const oo::PList shipyardInfo = [registry cxx_shipyardInfoForKey:oo::StdString([self shipDataKey])];
    unsigned available_facings = shipyardInfo.get<unsigned int>(oo::StdString(KEY_WEAPON_FACINGS), [self weaponFacings]); // use defaults  explicitly

    return available_facings & VALID_WEAPON_FACINGS;
}

- (void)cxx_setGuiToEquipShipScreen:(int)skipParam selectingFacingFor:(const std::optional<std::string>&)eqKeyForSelectFacing
{
    [[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:YES];

    missiles = [self countMissiles];
    OOEntityStatus searchStatus; // use STATUS_TEST, STATUS_DEAD & STATUS_ACTIVE
    std::optional<std::string> showKey;
    unsigned skip;

    if (skipParam < 0) {
        skip = 0;
        searchStatus = STATUS_TEST;
    } else {
        skip = skipParam;
        searchStatus = STATUS_ACTIVE;
    }

    // don't show a "Back" item if we're only skipping one item - just show the item
    if (skip == 1)
        skip = 0;

    double priceFactor = 1.0;
    OOTechLevelID techlevel = oo::PListView([UNIVERSE currentSystemData]).get<int>(KEY_TECHLEVEL);

    StationEntity* dockedStation = [self dockedStation];
    if (dockedStation) {
        priceFactor = [dockedStation equipmentPriceFactor];
        if ([dockedStation equivalentTechLevel] != NSNotFound)
            techlevel = [dockedStation equivalentTechLevel];
    }

    // build an array of all equipment - and take away that which has been bought (or is not permitted)
    std::vector<std::string> equipmentAllowed;

    // find options that agree with this ship (a set of keys: only the string elements could ever match)
    OOShipRegistry* registry = [OOShipRegistry sharedRegistry];
    const oo::PList shipyardInfo = [registry cxx_shipyardInfoForKey:oo::StdString([self shipDataKey])];
    std::set<std::string> options;
    const auto addOptions = [&options](const oo::PList* list) {
        for (std::size_t n = 0; list != nullptr && n < list->count(); n++) {
            const oo::PList* item = list->at(n);
            if (item->isString())
                options.insert(*item->getIf<std::string>());
        }
    };
    addOptions(shipyardInfo.get<oo::PList::Array>(oo::StdString(KEY_OPTIONAL_EQUIPMENT)));

    // add standard items too!
    const oo::PList* standardEquipment = shipyardInfo.get<oo::PList::Dict>(oo::StdString(KEY_STANDARD_EQUIPMENT));
    addOptions(standardEquipment != nullptr ? standardEquipment->get<oo::PList::Array>(oo::StdString(KEY_EQUIPMENT_EXTRAS)) : nullptr);

    unsigned i = 0;
    unsigned available_facings = shipyardInfo.get<unsigned int>(oo::StdString(KEY_WEAPON_FACINGS), [self weaponFacings]); // use defaults  explicitly

    if (eqKeyForSelectFacing.has_value()) // Weapons purchase subscreen.
    {
        skip = 1; // show the back button
        // The 3 lines below are needed by the present GUI. TODO:create a sane GUI. Kaks - 20090915 & 201005
        equipmentAllowed.push_back(*eqKeyForSelectFacing);
        equipmentAllowed.push_back(*eqKeyForSelectFacing);
        equipmentAllowed.push_back(*eqKeyForSelectFacing);
    } else
        for (OOEquipmentType* eqType in [OOEquipmentType equipmentEnumeratorOutfitting]) // (i counts at the end of the body)
        {
            const std::string eqKey = oo::StdString([eqType identifier]);
            OOTechLevelID minTechLevel = [eqType effectiveTechLevel];

            // set initial availability to NO
            BOOL isOK = NO;

            // check special availability
            if ([eqType isAvailableToAll])
                options.insert(eqKey);

            // if you have a damaged system you can get it repaired at a tech level one less than that required to buy it
            if (minTechLevel != 0 && [self hasEquipmentItem:[eqType damagedIdentifier]])
                minTechLevel--;

            // reduce the minimum techlevel occasionally as a bonus..
            if (techlevel < minTechLevel && techlevel + 3 > minTechLevel) {
                unsigned day = i * 13 + (unsigned)floor([UNIVERSE getTime] / 86400.0);
                unsigned char dayRnd = (day & 0xff) ^ (unsigned char)system_id;
                OOTechLevelID originalMinTechLevel = minTechLevel;

                while (minTechLevel > 0 && minTechLevel > originalMinTechLevel - 3 && !(dayRnd & 7)) // bargain tech days every 1/8 days
                {
                    dayRnd = dayRnd >> 2;
                    minTechLevel--; // occasional bonus items according to TL
                }
            }

            // check initial availability against options AND standard extras
            if (options.contains(eqKey)) {
                isOK = YES;
                options.erase(eqKey);
            }

            if (isOK) {
                if (techlevel < minTechLevel)
                    isOK = NO;
                if (![self canAddEquipment:oo::NSStringFrom(eqKey) inContext:@"purchase"])
                    isOK = NO;
                if (available_facings == 0 && [eqType isPrimaryWeapon])
                    isOK = NO;
                if (isOK)
                    equipmentAllowed.push_back(eqKey);
            }

            if (searchStatus == STATUS_DEAD && isOK) {
                showKey = eqKey;
                searchStatus = STATUS_ACTIVE;
            }
            if (searchStatus == STATUS_TEST) {
                if (isOK)
                    showKey = eqKey;
                if (eqKey == last_outfitting_key)
                    searchStatus = isOK ? STATUS_ACTIVE : STATUS_DEAD;
            }
            i++;
        }
    if (searchStatus != STATUS_TEST && showKey.has_value()) {
        last_outfitting_key = showKey;
    }

    // GUI stuff
    {
        GuiDisplayGen* gui = [UNIVERSE gui];
        OOGUIRow start_row = GUI_ROW_EQUIPMENT_START;
        OOGUIRow row = start_row;
        unsigned facing_count = 0;
        BOOL displayRow = YES;
        BOOL weaponMounted = NO;
        BOOL guiChanged = (gui_screen != GUI_SCREEN_EQUIP_SHIP);

        gui_screen = GUI_SCREEN_EQUIP_SHIP;

        [gui clearAndKeepBackground:!guiChanged];
        [gui setTitle:DESC(@"equip-title")];

        [gui setColor:[gui colorFromSetting:kGuiEquipmentCashColor defaultValue:nil] forRow:GUI_ROW_EQUIPMENT_CASH];
        [gui cxx_setText:oo::StdString(OOExpandKey(@"equip-cash-value", credits)) forRow:GUI_ROW_EQUIPMENT_CASH];

        OOGUITabSettings tab_stops;
        tab_stops[0] = 0;
        tab_stops[1] = -360;
        tab_stops[2] = -480;
        [gui overrideTabs:tab_stops from:kGuiEquipmentTabs length:3];
        [gui setTabStops:tab_stops];

        unsigned n_rows = GUI_MAX_ROWS_EQUIPMENT;
        NSUInteger count = equipmentAllowed.size();

        if (count > 0) {
            if (skip > 0) // lose the first row to Back <--
            {
                unsigned previous;

                if (count <= n_rows || skip < n_rows)
                    previous = 0; // single page
                else {
                    previous = skip - (n_rows - 2); // multi-page.
                    if (previous < 2)
                        previous = 0; // if only one previous item, just show it
                }

                if (eqKeyForSelectFacing.has_value()) {
                    previous = 0;
                    // keep weapon selected if we go back.
                    [gui cxx_setKey:oo::str::format("More:%d:%s", previous, eqKeyForSelectFacing->c_str()) forRow:row];
                } else {
                    [gui cxx_setKey:oo::str::format("More:%d", previous) forRow:row];
                }
                [gui setColor:[gui colorFromSetting:kGuiEquipmentScrollColor defaultValue:[OOColor greenColor]] forRow:row];
                [gui cxx_setArray: { oo::StdString(DESC(@"gui-back")), "", " <-- " } forRow:row];
                row++;
            }

            for (i = skip; i < count && (row - start_row < (OOGUIRow)n_rows); i++) {
                const std::string& eqKey = equipmentAllowed[i];
                OOEquipmentType* eqInfo = [OOEquipmentType equipmentTypeWithIdentifier:oo::NSStringFrom(eqKey)];
                OOCreditsQuantity pricePerUnit = [eqInfo price];
                std::string desc = oo::str::format(" %s ", oo::DescriptionOf([eqInfo name]).c_str());
                double price;

                OOColor* dispCol = [eqInfo displayColor];
                if (dispCol == nil)
                    dispCol = [gui colorFromSetting:kGuiEquipmentOptionColor defaultValue:nil];
                [gui setColor:dispCol forRow:row];

                if (eqKey == "EQ_FUEL") {
                    price = (PLAYER_MAX_FUEL - fuel) * pricePerUnit * [self fuelChargeRate];
                } else if (eqKey == "EQ_RENOVATION") {
                    price = [self renovationCosts];
                    [gui setColor:[gui colorFromSetting:kGuiEquipmentRepairColor defaultValue:[OOColor orangeColor]] forRow:row];
                } else {
                    price = pricePerUnit;
                }

                price = [self cxx_adjustPriceByScriptForEqKey:eqKey withCurrent:price];

                price *= priceFactor; // increased prices at some stations

                NSUInteger installTime = [eqInfo installTime];
                if (installTime == 0) {
                    installTime = 600 + price;
                }
                // is this item damaged?
                if ([self hasEquipmentItem:[eqInfo damagedIdentifier]]) {
                    desc = oo::str::formatRuntime(oo::StdString(DESC(@"equip-repair-@")), { desc });
                    price /= 2.0;
                    installTime = [eqInfo repairTime];
                    if (installTime == 0) {
                        installTime = 600 + price;
                    }
                    [gui setColor:[gui colorFromSetting:kGuiEquipmentRepairColor defaultValue:[OOColor orangeColor]] forRow:row];
                }

                const std::string timeString = oo::DescriptionOf([UNIVERSE shortTimeDescription:installTime]);
                std::string priceString = oo::str::format(" %s ", cxx_OOCredits(price).c_str());

                if (eqKeyForSelectFacing == eqKey) {
                    // Weapons purchase subscreen.
                    while (facing_count < 5) {
                        NSUInteger multiplier = 1;
                        switch (facing_count) {
                        case 0:
                            break;

                        case 1:
                            displayRow = available_facings & WEAPON_FACING_FORWARD;
                            desc = oo::StdString(FORWARD_FACING_STRING);
                            weaponMounted = !isWeaponNone(forward_weapon_type);
                            if (_multiplyWeapons) {
                                multiplier = forwardWeaponOffset.size();
                            }
                            break;

                        case 2:
                            displayRow = available_facings & WEAPON_FACING_AFT;
                            desc = oo::StdString(AFT_FACING_STRING);
                            weaponMounted = !isWeaponNone(aft_weapon_type);
                            if (_multiplyWeapons) {
                                multiplier = aftWeaponOffset.size();
                            }
                            break;

                        case 3:
                            displayRow = available_facings & WEAPON_FACING_PORT;
                            desc = oo::StdString(PORT_FACING_STRING);
                            weaponMounted = !isWeaponNone(port_weapon_type);
                            if (_multiplyWeapons) {
                                multiplier = portWeaponOffset.size();
                            }
                            break;

                        case 4:
                            displayRow = available_facings & WEAPON_FACING_STARBOARD;
                            desc = oo::StdString(STARBOARD_FACING_STRING);
                            weaponMounted = !isWeaponNone(starboard_weapon_type);
                            if (_multiplyWeapons) {
                                multiplier = starboardWeaponOffset.size();
                            }
                            break;
                        }

                        if (weaponMounted) {
                            [gui setColor:[gui colorFromSetting:kGuiEquipmentLaserFittedColor defaultValue:[OOColor colorWithRed:0.0f green:0.6f blue:0.0f alpha:1.0f]] forRow:row];
                        } else {
                            [gui setColor:[gui colorFromSetting:kGuiEquipmentLaserColor defaultValue:[OOColor greenColor]] forRow:row];
                        }
                        if (displayRow) // Always true for the first pass. The first pass is used to display the name of the weapon being purchased.
                        {

                            priceString = oo::str::format(" %s ", cxx_OOCredits(price * multiplier).c_str());

                            [gui cxx_setKey:eqKey forRow:row];
                            [gui cxx_setArray: { desc, (facing_count > 0 ? priceString : std::string()), timeString } forRow:row];
                            row++;
                        }
                        facing_count++;
                    }
                } else {
                    // Normal equipment list.
                    [gui cxx_setKey:eqKey forRow:row];
                    // check if the hidevalues property has been set
                    if (![eqInfo hideValues]) {
                        [gui cxx_setArray: { desc, priceString, timeString } forRow:row];
                    } else {
                        // if so, only output the description
                        [gui cxx_setArray: { desc } forRow:row];
                    }
                    row++;
                }
            }

            if (i < count) {
                // just overwrite the last item :-)
                [gui setColor:[gui colorFromSetting:kGuiEquipmentScrollColor defaultValue:[OOColor greenColor]] forRow:row - 1];
                [gui cxx_setArray: { oo::StdString(DESC(@"gui-more")), "", " --> " } forRow:row - 1];
                [gui cxx_setKey:oo::str::format("More:%d", i - 1) forRow:row - 1];
            }

            [gui setSelectableRange:NSMakeRange(start_row, row - start_row)];

            if ([gui selectedRow] != start_row)
                [gui setSelectedRow:start_row];

            if (eqKeyForSelectFacing.has_value()) {
                [gui setSelectedRow:start_row + 1];
                [self cxx_showInformationForSelectedUpgradeWithFormatString:oo::StdString(DESC(@"@-select-where-to-install"))];
            } else {
                [self showInformationForSelectedUpgrade];
            }
        } else {
            [gui cxx_setText:oo::StdString(DESC(@"equip-no-equipment-available-for-purchase")) forRow:GUI_ROW_NO_SHIPS align:GUI_ALIGN_CENTER];
            [gui setColor:[gui colorFromSetting:kGuiEquipmentUnavailableColor defaultValue:[OOColor greenColor]] forRow:GUI_ROW_NO_SHIPS];

            [gui setSelectableRange:NSMakeRange(0, 0)];
            [gui setNoSelectedRow];
            [self showInformationForSelectedUpgrade];
        }

        [gui setShowTextCursor:NO];

        // TODO: split the mount_weapon sub-screen into a separate screen, and use it for pylon mounted wepons as well?
        if (guiChanged) {
            [gui setForegroundTextureKey:@"docked_overlay"];
            const oo::PList background = oo::PListFrom([UNIVERSE screenTextureDescriptorForKey:@"equip_ship"]);
            [self cxx_setEquipScreenBackgroundDescriptor:background];
            [gui cxx_setBackgroundTextureDescriptor:background];
        } else if (eqKeyForSelectFacing.has_value()) // weapon purchase
        {
            const oo::PList bgDescriptor = oo::PListFrom([UNIVERSE screenTextureDescriptorForKey:@"mount_weapon"]);
            if (!bgDescriptor.isNull())
                [gui cxx_setBackgroundTextureDescriptor:bgDescriptor];
        } else // Returning from a weapon purchase. (Also called, redundantly, when paging)
        {
            [gui cxx_setBackgroundTextureDescriptor:[self cxx_equipScreenBackgroundDescriptor]];
        }
    }
    /* ends */

    chosen_weapon_facing = WEAPON_FACING_NONE;

    [self setShowDemoShips:NO];
    [UNIVERSE enterGUIViewModeWithMouseInteraction:YES];
}

- (void)setGuiToEquipShipScreen:(int)skip
{
    [self cxx_setGuiToEquipShipScreen:skip selectingFacingFor:std::nullopt];
}

- (void)showInformationForSelectedUpgrade
{
    [self cxx_showInformationForSelectedUpgradeWithFormatString:std::nullopt];
}

- (void)cxx_showInformationForSelectedUpgradeWithFormatString:(const std::optional<std::string>&)formatString
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    const std::optional<std::string> eqKey = [gui cxx_selectedRowKey];
    int i;

    OOColor* descColor = [gui colorFromSetting:kGuiEquipmentDescriptionColor defaultValue:[OOColor greenColor]];
    for (i = GUI_ROW_EQUIPMENT_DETAIL; i < GUI_MAX_ROWS; i++) {
        [gui cxx_setText:std::string() forRow:i];
        [gui setColor:descColor forRow:i];
    }
    if (eqKey) {
        if (!oo::str::hasPrefix(*eqKey, "More:")) {
            std::optional<std::string> desc = oo::OptionalString([[OOEquipmentType equipmentTypeWithIdentifier:oo::NSStringFrom(*eqKey)] descriptiveText]);
            const std::string eq_key_damaged = *eqKey + "_DAMAGED";
            int weight = [[OOEquipmentType equipmentTypeWithIdentifier:oo::NSStringFrom(*eqKey)] requiredCargoSpace];
            if ([self hasEquipmentItem:oo::NSStringFrom(eq_key_damaged)]) {
                desc = oo::str::formatRuntime(oo::StdString(DESC(@"upgradeinfo-@-price-is-for-repairing")), { TextArg(desc) });
            } else {
                if (oo::str::hasSuffix(*eqKey, "ENERGY_UNIT") && ([self hasEquipmentItem:@"EQ_ENERGY_UNIT_DAMAGED"] || [self hasEquipmentItem:@"EQ_ENERGY_UNIT"] || [self hasEquipmentItem:@"EQ_NAVAL_ENERGY_UNIT_DAMAGED"]))
                    desc = oo::str::formatRuntime(oo::StdString(DESC(@"@-will-replace-other-energy")), { TextArg(desc) });
                if (weight > 0)
                    desc = oo::str::formatRuntime(oo::StdString(DESC(@"upgradeinfo-@-weight-d-of-equipment")), { TextArg(desc), weight });
            }
            if (formatString.has_value())
                desc = oo::str::formatRuntime(*formatString, { TextArg(desc) });
            [gui cxx_addLongText:desc startingAtRow:GUI_ROW_EQUIPMENT_DETAIL align:GUI_ALIGN_LEFT];
        }
    }
}

- (void)setGuiToInterfacesScreen:(int)skip
{
    [[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:YES];
    if (gui_screen != GUI_SCREEN_INTERFACES) {
        [self noteGUIWillChangeTo:GUI_SCREEN_INTERFACES];
    }

    // build an array of available interfaces
    const auto* interfaces = [[self dockedStation] cxx_localInterfaces];
    std::vector<std::string> interfaceKeys;
    if (interfaces != nullptr) {
        for (const auto& entry : *interfaces)
            interfaceKeys.push_back(entry.first);
        // sorts by category, then title. ORDER-SENSITIVE: ties now keep the map's byte order of keys
        std::stable_sort(interfaceKeys.begin(), interfaceKeys.end(), [interfaces](const std::string& a, const std::string& b) {
            return [interfaces->find(a)->second.get() interfaceCompare:interfaces->find(b)->second.get()] == NSOrderedAscending;
        });
    }
    int i;

    OOGUIScreenID oldScreen = gui_screen;

    // GUI stuff
    {
        GuiDisplayGen* gui = [UNIVERSE gui];
        OOGUIRow start_row = GUI_ROW_INTERFACES_START;
        OOGUIRow row = start_row;
        BOOL guiChanged = (gui_screen != GUI_SCREEN_INTERFACES);

        [gui clearAndKeepBackground:!guiChanged];
        [gui setTitle:DESC(@"interfaces-title")];

        gui_screen = GUI_SCREEN_INTERFACES;

        OOGUITabSettings tab_stops;
        tab_stops[0] = 0;
        tab_stops[1] = -480;
        [gui overrideTabs:tab_stops from:kGuiInterfaceTabs length:2];
        [gui setTabStops:tab_stops];

        unsigned n_rows = GUI_MAX_ROWS_INTERFACES;
        NSUInteger count = interfaceKeys.size();

        if (count > 0) {
            if (skip > 0) // lose the first row to Back <--
            {
                unsigned previous;

                if (count <= n_rows || skip < (NSInteger)n_rows) {
                    previous = 0; // single page
                } else {
                    previous = skip - (n_rows - 2); // multi-page.
                    if (previous < 2) {
                        previous = 0; // if only one previous item, just show it
                    }
                }

                [gui cxx_setKey:oo::str::format("More:%d", static_cast<int>(previous)) forRow:row];
                [gui setColor:[gui colorFromSetting:kGuiInterfaceScrollColor defaultValue:[OOColor greenColor]] forRow:row];
                [gui cxx_setArray: { oo::StdString(DESC(@"gui-back")), " <-- " } forRow:row];
                row++;
            }

            for (i = skip; i < (NSInteger)count && (row - start_row < (OOGUIRow)n_rows); i++) {
                const std::string& interfaceKey = interfaceKeys[i];
                OOJSInterfaceDefinition* definition = interfaces->find(interfaceKey)->second.get();

                [gui setColor:[gui colorFromSetting:kGuiInterfaceEntryColor defaultValue:nil] forRow:row];
                [gui cxx_setKey:interfaceKey forRow:row];
                // title, category: the list ends at the first nil, as arrayWithObjects: did
                std::vector<std::string> columns;
                id title = [definition title];
                if (title != nil) {
                    columns.push_back(oo::StdString(title));
                    const std::optional<std::string> category = [definition category];
                    if (category.has_value())
                        columns.push_back(*category);
                }
                [gui cxx_setArray:columns forRow:row];

                row++;
            }

            if (i < (NSInteger)count) {
                // just overwrite the last item :-)
                [gui setColor:[gui colorFromSetting:kGuiInterfaceScrollColor defaultValue:[OOColor greenColor]] forRow:row - 1];
                [gui cxx_setArray: { oo::StdString(DESC(@"gui-more")), " --> " } forRow:row - 1];
                [gui cxx_setKey:oo::str::format("More:%d", i - 1) forRow:row - 1];
            }

            [gui setSelectableRange:NSMakeRange(start_row, row - start_row)];

            if ([gui selectedRow] != start_row) {
                [gui setSelectedRow:start_row];
            }

            [self showInformationForSelectedInterface];
        } else {
            [gui setText:DESC(@"interfaces-no-interfaces-available-for-use") forRow:GUI_ROW_NO_INTERFACES align:GUI_ALIGN_LEFT];
            [gui setColor:[gui colorFromSetting:kGuiInterfaceNoneColor defaultValue:[OOColor greenColor]] forRow:GUI_ROW_NO_INTERFACES];

            [gui setSelectableRange:NSMakeRange(0, 0)];
            [gui setNoSelectedRow];
        }

        [gui setShowTextCursor:NO];

        const std::string desc = oo::str::formatRuntime(oo::StdString(DESC(@"interfaces-for-ship-@-and-station-@")),
            { oo::DescriptionOf([self displayName]), oo::DescriptionOf([[self dockedStation] displayName]) });
        [gui setColor:[gui colorFromSetting:kGuiInterfaceHeadingColor defaultValue:nil] forRow:GUI_ROW_INTERFACES_HEADING];
        [gui cxx_setText:desc forRow:GUI_ROW_INTERFACES_HEADING];

        if (guiChanged) {
            [gui setForegroundTextureKey:@"docked_overlay"];
            [gui setBackgroundTextureDescriptor:[UNIVERSE screenTextureDescriptorForKey:@"interfaces"]];
        }
    }
    /* ends */

    [self setShowDemoShips:NO];

    [self noteGUIDidChangeFrom:oldScreen to:gui_screen];

    [self setShowDemoShips:NO];
    [UNIVERSE enterGUIViewModeWithMouseInteraction:YES];
}

- (void)showInformationForSelectedInterface
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    const std::optional<std::string> interfaceKey = [gui cxx_selectedRowKey];

    int i;

    for (i = GUI_ROW_EQUIPMENT_DETAIL; i < GUI_MAX_ROWS; i++) {
        [gui setText:@"" forRow:i];
        [gui setColor:[gui colorFromSetting:kGuiInterfaceDescriptionColor defaultValue:[OOColor greenColor]] forRow:i];
    }

    if (interfaceKey.has_value() && !oo::str::hasPrefix(*interfaceKey, "More:")) {
        OOJSInterfaceDefinition* definition = InterfaceForKey([self dockedStation], interfaceKey);
        if (definition) {
            [gui cxx_addLongText:[definition summary] startingAtRow:GUI_ROW_INTERFACES_DETAIL align:GUI_ALIGN_LEFT];
        }
    }
}

- (void)activateSelectedInterface
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    const std::optional<std::string> key = [gui cxx_selectedRowKey];

    if (key.has_value() && oo::str::hasPrefix(*key, "More:")) {
        int from_item = oo::str::intValue(RowKeyField(*key, 1).value_or(std::string()));
        [self setGuiToInterfacesScreen:from_item];

        if ([gui selectedRow] < 0)
            [gui setSelectedRow:GUI_ROW_INTERFACES_START];
        if (from_item == 0)
            [gui setSelectedRow:GUI_ROW_INTERFACES_START + GUI_MAX_ROWS_INTERFACES - 1];
        [self showInformationForSelectedInterface];

        return;
    }

    OOJSInterfaceDefinition* definition = InterfaceForKey([self dockedStation], key);
    if (definition) {
        [[UNIVERSE gameView] clearKeys];
        [definition runCallback:oo::NSStringOrNil(key)];
    } else {
        OO_LOG("interface.missingCallback", "Unable to find callback definition for key {}", key.value_or("(null)"));
    }
}

- (void)setupStartScreenGui
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    std::string text;

    [[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:YES];

    [gui clear];

    [gui setTitle:@"Oolite"];

    text = oo::StdString(DESC(@"game-copyright"));
    [gui cxx_setText:text forRow:15 align:GUI_ALIGN_CENTER];
    [gui setColor:[OOColor whiteColor] forRow:15];

    text = oo::StdString(DESC(@"theme-music-credit"));
    [gui cxx_setText:text forRow:17 align:GUI_ALIGN_CENTER];
    [gui setColor:[OOColor grayColor] forRow:17];

    int initialRow = 22;
    int row = initialRow;

    text = oo::StdString(DESC(@"oolite-start-option-1"));
    [gui cxx_setText:text forRow:row align:GUI_ALIGN_CENTER];
    [gui setColor:[OOColor yellowColor] forRow:row];
    [gui cxx_setKey:oo::str::format("Start:%d", row) forRow:row];

    ++row;

    text = oo::StdString(DESC(@"oolite-start-option-2"));
    [gui cxx_setText:text forRow:row align:GUI_ALIGN_CENTER];
    [gui setColor:[OOColor yellowColor] forRow:row];
    [gui cxx_setKey:oo::str::format("Start:%d", row) forRow:row];

    ++row;

    text = oo::StdString(DESC(@"oolite-start-option-3"));
    [gui cxx_setText:text forRow:row align:GUI_ALIGN_CENTER];
    [gui setColor:[OOColor yellowColor] forRow:row];
    [gui cxx_setKey:oo::str::format("Start:%d", row) forRow:row];

    ++row;

    text = oo::StdString(DESC(@"oolite-start-option-4"));
    [gui cxx_setText:text forRow:row align:GUI_ALIGN_CENTER];
    [gui setColor:[OOColor yellowColor] forRow:row];
    [gui cxx_setKey:oo::str::format("Start:%d", row) forRow:row];

    ++row;

    text = oo::StdString(DESC(@"oolite-start-option-5"));
    [gui cxx_setText:text forRow:row align:GUI_ALIGN_CENTER];
    [gui setColor:[OOColor yellowColor] forRow:row];
    [gui cxx_setKey:oo::str::format("Start:%d", row) forRow:row];

    ++row;

    text = oo::StdString(DESC(@"oolite-start-option-6"));
    [gui cxx_setText:text forRow:row align:GUI_ALIGN_CENTER];
    [gui setColor:[OOColor yellowColor] forRow:row];
    [gui cxx_setKey:oo::str::format("Start:%d", row) forRow:row];

    [gui setSelectableRange:NSMakeRange(initialRow, row - initialRow + 1)];
    [gui setSelectedRow:initialRow];

    [gui setBackgroundTextureKey:@"intro"];
}

/**
 * \ingroup cli
 * Scans the command line for -message or -showversion arguments.
 */
- (void)setGuiToIntroFirstGo:(BOOL)justCobra
{
    std::string text;
    GuiDisplayGen* gui = [UNIVERSE gui];
    OOGUIRow msgLine = 2;

    [[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:NO];
    [[UNIVERSE gameView] clearMouse];
    [[UNIVERSE gameView] clearKeys];

    if (justCobra) {
        [UNIVERSE removeDemoShips];
        [[OOCacheManager sharedCache] flush]; // At first startup, a lot of stuff is cached
    }

    if (justCobra) {
        [self setupStartScreenGui];

        // check for error messages from Resource Manager
        //[ResourceManager paths]; done in Universe already
        const std::optional<std::string> errors = [ResourceManager cxx_errors];
        if (errors.has_value()) {
            OOGUIRow ms_start = msgLine;
            OOGUIRow i = msgLine = [gui cxx_addLongText:errors startingAtRow:ms_start align:GUI_ALIGN_LEFT];
            for (i--; i >= ms_start; i--)
                [gui setColor:[OOColor redColor] forRow:i];
            msgLine++;
        }

        // check for messages from OXPs
        const std::vector<std::string> OXPsWithMessages = [ResourceManager cxx_OXPsWithMessagesFound];
        if (OXPsWithMessages.size() > 0) {
            std::optional<std::string> messageToDisplay = std::string();

            // Show which OXPs were found with messages, but don't spam the screen if more than
            // a certain number of them exist
            if (OXPsWithMessages.size() < 5) {
                std::string messageSourceList; // joined with ", "
                for (const std::string& source : OXPsWithMessages) {
                    if (!messageSourceList.empty())
                        messageSourceList += ", ";
                    messageSourceList += source;
                }
                messageToDisplay = ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "oxp-containing-messages-list", { { "messageSourceList", oo::PList(messageSourceList) } });
            } else {
                messageToDisplay = oo::OptionalString(OOExpandKey(@"oxp-containing-messages-found"));
            }

            OOGUIRow ms_start = msgLine;
            OOGUIRow i = msgLine = [gui cxx_addLongText:messageToDisplay startingAtRow:ms_start align:GUI_ALIGN_LEFT];
            for (i--; i >= ms_start; i--) {
                [gui setColor:[OOColor orangeColor] forRow:i];
            }
            msgLine++;
        }

        // check for messages from the command line
        const std::vector<std::string>& arguments = oo::process::arguments();
        unsigned i;
        for (i = 0; i < arguments.size(); i++) {
            if ((arguments[i] == "-message") && (i < arguments.size() - 1)) {
                OOGUIRow ms_start = msgLine;
                const std::string& message = arguments[i + 1];
                OOGUIRow i = msgLine = [gui cxx_addLongText:message startingAtRow:ms_start align:GUI_ALIGN_CENTER];
                for (i--; i >= ms_start; i--) {
                    [gui setColor:[OOColor magentaColor] forRow:i];
                }
            }
            if (arguments[i] == "-showversion") {
                OOGUIRow ms_start = msgLine;
                const std::string version = "Version " OO_VERSION_FULL;
                OOGUIRow i = msgLine = [gui cxx_addLongText:version startingAtRow:ms_start align:GUI_ALIGN_CENTER];
                for (i--; i >= ms_start; i--) {
                    [gui setColor:[OOColor magentaColor] forRow:i];
                }
            }
        }
    } else {
        [gui clear];

        text = oo::StdString(DESC(@"oolite-ship-library-title"));
        [gui setTitle:oo::NSStringFrom(text)];

        text = oo::StdString(DESC(@"oolite-ship-library-exit"));
        [gui cxx_setText:text forRow:27 align:GUI_ALIGN_CENTER];
        [gui setColor:[OOColor yellowColor] forRow:27];
    }

    [gui setShowTextCursor:NO];

    [UNIVERSE setupIntroFirstGo:justCobra];

    if (gui != nil) {
        gui_screen = justCobra ? GUI_SCREEN_INTRO1 : GUI_SCREEN_SHIPLIBRARY;
    }
    if ([self status] == STATUS_START_GAME) {
        [[OOMusicController sharedController] playThemeMusic];
    }

    [self setShowDemoShips:YES];
    if (justCobra) {
        [gui setBackgroundTextureKey:@"intro"];
    } else {
        [gui setBackgroundTextureKey:@"shiplibrary"];
    }
    [UNIVERSE enterGUIViewModeWithMouseInteraction:YES];
}

- (void)setGuiToOXZManager
{

    [[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:NO];
    [[UNIVERSE gameView] clearMouse];
    [UNIVERSE removeDemoShips];

    gui_screen = GUI_SCREEN_OXZMANAGER;

    [[UNIVERSE gui] clearAndKeepBackground:NO];

    [[OOOXZManager sharedManager] gui];

    [[OOMusicController sharedController] playThemeMusic];
    [[UNIVERSE gui] setBackgroundTextureKey:@"oxz-manager"];
    [UNIVERSE enterGUIViewModeWithMouseInteraction:YES];
}

- (void)noteGUIWillChangeTo:(OOGUIScreenID)toScreen
{
    JSContext* context = OOJSAcquireContext();
    ShipScriptEvent(context, self, "guiScreenWillChange", OOJSValueFromGUIScreenID(context, toScreen), OOJSValueFromGUIScreenID(context, gui_screen));
    OOJSRelinquishContext(context);
}

- (void)noteGUIDidChangeFrom:(OOGUIScreenID)fromScreen to:(OOGUIScreenID)toScreen
{
    [self noteGUIDidChangeFrom:fromScreen to:toScreen refresh:NO];
}

- (void)noteGUIDidChangeFrom:(OOGUIScreenID)fromScreen to:(OOGUIScreenID)toScreen refresh:(BOOL)refresh
{
    // No events triggered if we're changing screens while paused, or if screen never actually changed.
    if (fromScreen != toScreen || refresh) {
        // MKW - release GUI Screen ship, if we have one
        switch (fromScreen) {
        case GUI_SCREEN_SHIPYARD:
        case GUI_SCREEN_LOAD:
        case GUI_SCREEN_SAVE:
            [demoShip release];
            demoShip = nil;
            break;
        default:
            // Nothing
            break;
        }

        if (toScreen == GUI_SCREEN_SYSTEM_DATA) {
            // system data screen: ensure correct sun light color is used on miniature planet
            [[UNIVERSE sun] setSunColor:[OOColor colorWithDescription:[[UNIVERSE systemManager] getProperty:@"sun_color" forSystem:info_system_id inGalaxy:[self galaxyNumber]]]];
        } else {
            // any other screen: reset local sun light color
            [[UNIVERSE sun] setSunColor:[OOColor colorWithDescription:[[UNIVERSE systemManager] getProperty:@"sun_color" forSystem:system_id inGalaxy:[self galaxyNumber]]]];
        }

        if (![[UNIVERSE gameController] isGamePaused]) {
            JSContext* context = OOJSAcquireContext();
            ShipScriptEvent(context, self, "guiScreenChanged", OOJSValueFromGUIScreenID(context, toScreen), OOJSValueFromGUIScreenID(context, fromScreen));
            OOJSRelinquishContext(context);
        }
    }
}

- (void)noteViewDidChangeFrom:(OOViewID)fromView toView:(OOViewID)toView
{
    [self noteSwitchToView:toView fromView:fromView];
}

- (void)buySelectedItem
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    const std::optional<std::string> key = [gui cxx_selectedRowKey];

    if (key.has_value() && oo::str::hasPrefix(*key, "More:")) {
        int from_item = oo::str::intValue(RowKeyField(*key, 1).value_or(std::string()));
        const std::optional<std::string> weaponKey = RowKeyField(*key, 2);

        [self setGuiToEquipShipScreen:from_item];
        if (weaponKey.has_value()) {
            [self highlightEquipShipScreenKey:*weaponKey];
        } else {
            if ([gui selectedRow] < 0)
                [gui setSelectedRow:GUI_ROW_EQUIPMENT_START];
            if (from_item == 0)
                [gui setSelectedRow:GUI_ROW_EQUIPMENT_START + GUI_MAX_ROWS_EQUIPMENT - 1];
            [self showInformationForSelectedUpgrade];
        }

        return;
    }

    const std::optional<std::string> itemText = [gui cxx_selectedRowText];

    // isEqual: of the row text (nil matched nothing)
    const auto itemTextIs = [&itemText](id facingString) { return itemText.has_value() && facingString != nil && *itemText == oo::StdString(facingString); };
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
    OOEquipmentType* eqInfo = [OOEquipmentType equipmentTypeWithIdentifier:oo::NSStringOrNil(key)];
    BOOL isRepair = [self hasEquipmentItem:[eqInfo damagedIdentifier]];
    if ([self tryBuyingItem:key.value_or(std::string())]) // (a nil key bought nothing, as "" does)
    {
        if (credits == old_credits) {
            // laser pre-purchase, or free equipment
            [self playMenuNavigationDown];
        } else {
            [self playBuyCommodity];
        }

        if (credits != old_credits || !(key.has_value() && oo::str::hasPrefix(*key, "EQ_WEAPON_"))) {
            // adjust time before playerBoughtEquipment gets to change credits dynamically
            // wind the clock forward by 10 minutes plus 10 minutes for every 60 credits spent
            NSUInteger adjust = 0;
            if (isRepair) {
                adjust = [eqInfo repairTime];
            } else {
                adjust = [eqInfo installTime];
            }
            double time_adjust = (old_credits > credits) ? (old_credits - credits) : 0.0;
            [UNIVERSE forceWitchspaceEntries];
            if (adjust == 0) {
                ship_clock_adjust += time_adjust + 600.0;
            } else {
                ship_clock_adjust += (double)adjust;
            }

            // [key, price paid as a long long]; a nil key ended the list
            oo::PList::Array boughtArguments;
            if (key.has_value())
                boughtArguments = { oo::PList(*key), oo::PList::signedInteger(static_cast<long long>(old_credits - credits)) };
            [self doScriptEvent:OOJSID("playerBoughtEquipment") withArguments:oo::ObjectFromPList(oo::PList(std::move(boughtArguments)))];
            if (gui_screen == GUI_SCREEN_EQUIP_SHIP) // if we haven't changed gui screen inside playerBoughtEquipment
            {
                // show any change due to playerBoughtEquipment
                [self setGuiToEquipShipScreen:0];
                // then try to go back where we were
                [self highlightEquipShipScreenKey:key.value_or(std::string())];
            }

            if ([UNIVERSE autoSave])
                [UNIVERSE setAutoSaveNow:YES];
        }
    } else {
        [self playCantBuyCommodity];
    }
}

- (OOCreditsQuantity)cxx_adjustPriceByScriptForEqKey:(const std::string&)eqKey withCurrent:(OOCreditsQuantity)price
{
    const std::optional<std::string> condition_script = oo::OptionalString([[OOEquipmentType equipmentTypeWithIdentifier:oo::NSStringFrom(eqKey)] conditionScript]);
    if (condition_script.has_value()) {
        OOJSScript* condScript = [UNIVERSE getConditionScript:oo::NSStringFrom(*condition_script)];
        if (condScript != nil) // should always be non-nil, but just in case
        {
            JSContext* JScontext = OOJSAcquireContext();
            BOOL OK;
            OOJSVal result = OOJSUndefinedValue();
            int32_t newPrice;
            OOJSVal args[] = { OOJSValueFromNativeObject(JScontext, oo::NSStringFrom(eqKey)), OOJSValueFromDouble(JScontext, price) };

            OK = [condScript callMethod:OOJSID("updateEquipmentPrice")
                              inContext:JScontext
                          withArguments:args
                                  count:sizeof args / sizeof *args
                                 result:&result];

            if (OK) {
                OK = OOJSValueToInt32(JScontext, result, &newPrice);
                if (OK && newPrice >= 0) {
                    price = (OOCreditsQuantity)newPrice;
                }
                if (!OK)
                    OOJSReportPendingException(JScontext);
            }
            OOJSFreeValue(JScontext, result);
            OOJSFreeValue(JScontext, args[0]);
            OOJSFreeValue(JScontext, args[1]);
            OOJSRelinquishContext(JScontext);
        }
    }
    return price;
}

- (BOOL)tryBuyingItem:(const std::string&)eqKey
{
    // note this doesn't check the availability by tech-level
    OOEquipmentType* eqType = [OOEquipmentType equipmentTypeWithIdentifier:oo::NSStringFrom(eqKey)];
    OOCreditsQuantity pricePerUnit = [eqType price];
    const std::optional<std::string> eqKeyDamaged = oo::OptionalString([eqType damagedIdentifier]);
    double price = pricePerUnit;
    double priceFactor = 1.0;
    OOCreditsQuantity tradeIn = 0;
    BOOL isRepair = NO;

    // repairs cost 50%
    if ([self hasEquipmentItem:oo::NSStringOrNil(eqKeyDamaged)]) {
        price /= 2.0;
        isRepair = YES;
    }

    if ((eqKey == "EQ_RENOVATION")) {
        price = [self renovationCosts];
    }

    price = [self cxx_adjustPriceByScriptForEqKey:eqKey withCurrent:price];

    StationEntity* dockedStation = [self dockedStation];
    if (dockedStation) {
        priceFactor = [dockedStation equipmentPriceFactor];
    }

    price *= priceFactor; // increased prices at some stations

    if (price > credits) {
        return NO;
    }

    if ([eqType isPrimaryWeapon]) {
        if (chosen_weapon_facing == WEAPON_FACING_NONE) {
            [self cxx_setGuiToEquipShipScreen:0 selectingFacingFor:eqKey]; // reset
            return YES;
        }

        OOWeaponType chosen_weapon = cxx_OOWeaponTypeFromEquipmentIdentifierStrict(eqKey);
        OOWeaponType current_weapon = nil;

        NSUInteger multiplier = 1;

        switch (chosen_weapon_facing) {
        case WEAPON_FACING_FORWARD:
            current_weapon = forward_weapon_type;
            forward_weapon_type = chosen_weapon;
            if (_multiplyWeapons) {
                multiplier = forwardWeaponOffset.size();
            }
            break;

        case WEAPON_FACING_AFT:
            current_weapon = aft_weapon_type;
            aft_weapon_type = chosen_weapon;
            if (_multiplyWeapons) {
                multiplier = aftWeaponOffset.size();
            }
            break;

        case WEAPON_FACING_PORT:
            current_weapon = port_weapon_type;
            port_weapon_type = chosen_weapon;
            if (_multiplyWeapons) {
                multiplier = portWeaponOffset.size();
            }
            break;

        case WEAPON_FACING_STARBOARD:
            current_weapon = starboard_weapon_type;
            starboard_weapon_type = chosen_weapon;
            if (_multiplyWeapons) {
                multiplier = starboardWeaponOffset.size();
            }
            break;

        case WEAPON_FACING_NONE:
            break;
        }

        price *= multiplier;

        if (price > credits) {
            // not enough money - ensure that weapon
            // type is reset to what it was before
            // the attempt to buy took place
            switch (chosen_weapon_facing) {
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
        if (current_weapon != nil) {
            tradeIn = [UNIVERSE getEquipmentPriceForKey:OOEquipmentIdentifierFromWeaponType(current_weapon)] * multiplier;
        }

        [self doTradeIn:tradeIn forPriceFactor:priceFactor];
        // If equipped, remove damaged weapon after repairs. -- But there's no way we should get a damaged weapon. Ever.
        [self removeEquipmentItem:oo::NSStringOrNil(eqKeyDamaged)];
        return YES;
    }

    if ([eqType isMissileOrMine] && missiles >= max_missiles) {
        OO_LOG("equip.buy.mounted.failed.full", "{}", "rejecting missile because already full");
        return NO;
    }

    // NSFO!
    // unsigned 	passenger_space = [[OOEquipmentType equipmentTypeWithIdentifier:@"EQ_PASSENGER_BERTH"] requiredCargoSpace];
    // if (passenger_space == 0) passenger_space = PASSENGER_BERTH_SPACE;

    if ((eqKey == "EQ_PASSENGER_BERTH") && [self availableCargoSpace] < PASSENGER_BERTH_SPACE) {
        return NO;
    }

    if ((eqKey == "EQ_FUEL")) {
#if MASS_DEPENDENT_FUEL_PRICES
        OOCreditsQuantity creditsForRefuel = ([self fuelCapacity] - [self fuel]) * pricePerUnit * [self fuelChargeRate];
#else
        OOCreditsQuantity creditsForRefuel = ([self fuelCapacity] - [self fuel]) * pricePerUnit;
#endif
        if (credits >= creditsForRefuel) // Ensure we don't overflow
        {
            credits -= creditsForRefuel;
            fuel = [self fuelCapacity];
            return YES;
        } else {
            return NO;
        }
    }

    // check energy unit replacement
    if (oo::str::hasSuffix(eqKey, "ENERGY_UNIT") && [self energyUnitType] != ENERGY_UNIT_NONE) {
        switch ([self energyUnitType]) {
        case ENERGY_UNIT_NAVAL:
            [self removeEquipmentItem:@"EQ_NAVAL_ENERGY_UNIT"];
            tradeIn = [UNIVERSE getEquipmentPriceForKey:@"EQ_NAVAL_ENERGY_UNIT"] / 2; // 50 % refund
            break;
        case ENERGY_UNIT_NAVAL_DAMAGED:
            [self removeEquipmentItem:@"EQ_NAVAL_ENERGY_UNIT_DAMAGED"];
            tradeIn = [UNIVERSE getEquipmentPriceForKey:@"EQ_NAVAL_ENERGY_UNIT"] / 4; // half of the working one
            break;
        case ENERGY_UNIT_NORMAL:
            [self removeEquipmentItem:@"EQ_ENERGY_UNIT"];
            tradeIn = [UNIVERSE getEquipmentPriceForKey:@"EQ_ENERGY_UNIT"] * 3 / 4; // 75 % refund
            break;
        case ENERGY_UNIT_NORMAL_DAMAGED:
            [self removeEquipmentItem:@"EQ_ENERGY_UNIT_DAMAGED"];
            tradeIn = [UNIVERSE getEquipmentPriceForKey:@"EQ_ENERGY_UNIT"] * 3 / 8; // half of the working one
            break;

        default:
            break;
        }
        [self doTradeIn:tradeIn forPriceFactor:priceFactor];
    }

    // maintain ship
    if ((eqKey == "EQ_RENOVATION")) {
        OOTechLevelID techLevel = NSNotFound;
        if (dockedStation != nil)
            techLevel = [dockedStation equivalentTechLevel];
        if (techLevel == NSNotFound)
            techLevel = oo::PListView([UNIVERSE currentSystemData]).get<unsigned int>(KEY_TECHLEVEL);

        credits -= price;
        ship_trade_in_factor += 5 + techLevel; // you get better value at high-tech repair bases
        if (ship_trade_in_factor > 100)
            ship_trade_in_factor = 100;

        [self clearSubEntities];
        [self setUpSubEntities];

        return YES;
    }

    if (oo::str::hasSuffix(eqKey, "MISSILE") || oo::str::hasSuffix(eqKey, "MINE")) {
        ShipEntity* weapon = [[UNIVERSE newShipWithRole:oo::NSStringFrom(eqKey)] autorelease];
        if (weapon)
            OO_LOG("equip.buy.mounted", "Got ship for mounted weapon role {}", eqKey);
        else
            OO_LOG("equip.buy.mounted.failed", "Could not find ship for mounted weapon role {}", eqKey);

        BOOL mounted_okay = [self mountMissile:weapon];
        if (mounted_okay) {
            credits -= price;
            [self safeAllMissiles];
            [self tidyMissilePylons];
            [self setActiveMissile:0];
        }
        return mounted_okay;
    }

    if ((eqKey == "EQ_PASSENGER_BERTH")) {
        [self changePassengerBerths:+1];
        credits -= price;
        return YES;
    }

    if ((eqKey == "EQ_PASSENGER_BERTH_REMOVAL")) {
        [self changePassengerBerths:-1];
        credits -= price;
        return YES;
    }

    if ((eqKey == "EQ_MISSILE_REMOVAL")) {
        credits -= price;
        tradeIn += [self removeMissiles];
        [self doTradeIn:tradeIn forPriceFactor:priceFactor];
        return YES;
    }

    if ([self canAddEquipment:oo::NSStringFrom(eqKey) inContext:@"purchase"]) {
        credits -= price;
        [self addEquipmentItem:oo::NSStringFrom(eqKey) withValidation:NO inContext:@"purchase"]; // no need to validate twice.
        if (isRepair) {
            [self doScriptEvent:OOJSID("equipmentRepaired") withArgument:oo::NSStringFrom(eqKey)];
        }
        return YES;
    }

    return NO;
}

- (BOOL)setWeaponMount:(OOWeaponFacing)facing toWeapon:(id)eqKey // shared selector (proposed ADR-0043)
{
    // canAddEquipment: read a nil key as "", as cxx_ does
    return [self cxx_setWeaponMount:facing toWeapon:oo::StdString(eqKey) inContext:std::string("purchase")];
}

- (BOOL)cxx_setWeaponMount:(OOWeaponFacing)facing toWeapon:(const std::string&)eqKey inContext:(const std::optional<std::string>&)context
{

    const oo::PList shipyardInfo = [[OOShipRegistry sharedRegistry] cxx_shipyardInfoForKey:oo::StdString([self shipDataKey])];
    unsigned available_facings = shipyardInfo.get<unsigned int>(oo::StdString(KEY_WEAPON_FACINGS), [self weaponFacings]); // use defaults  explicitly

    // facing exists?
    if (!(available_facings & facing)) {
        return NO;
    }

    // weapon allowed (or NONE)?
    if (eqKey != "EQ_WEAPON_NONE") {
        if (![self canAddEquipment:oo::NSStringFrom(eqKey) inContext:oo::NSStringOrNil(context)]) {
            return NO;
        }
    }

    // sets WEAPON_NONE if not recognised
    OOWeaponType chosen_weapon = cxx_OOWeaponTypeFromEquipmentIdentifierStrict(eqKey);

    switch (facing) {
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

- (BOOL)changePassengerBerths:(int)addRemove
{
    if (addRemove == 0)
        return NO;
    addRemove = (addRemove > 0) ? 1 : -1; // change only by one berth at a time!
    // NSFO!
    // unsigned 	passenger_space = [[OOEquipmentType equipmentTypeWithIdentifier:@"EQ_PASSENGER_BERTH"] requiredCargoSpace];
    // if (passenger_space == 0) passenger_space = PASSENGER_BERTH_SPACE;
    if ((max_passengers < 1 && addRemove == -1) || ([self maxAvailableCargoSpace] - current_cargo < PASSENGER_BERTH_SPACE && addRemove == 1))
        return NO;
    max_passengers += addRemove;
    max_cargo -= PASSENGER_BERTH_SPACE * addRemove;
    return YES;
}

- (OOCreditsQuantity)removeMissiles
{
    [self safeAllMissiles];
    OOCreditsQuantity tradeIn = 0;
    unsigned i;
    for (i = 0; i < missiles; i++) {
        const std::optional<std::string> weapon_key = oo::OptionalString([missile_list[i] identifier]);

        if (weapon_key.has_value())
            tradeIn += (int)[UNIVERSE getEquipmentPriceForKey:oo::NSStringFrom(*weapon_key)];
    }

    for (i = 0; i < max_missiles; i++) {
        [missile_entity[i] release];
        missile_entity[i] = nil;
    }

    missiles = 0;
    return tradeIn;
}

- (void)doTradeIn:(OOCreditsQuantity)tradeInValue forPriceFactor:(double)priceFactor
{
    if (tradeInValue != 0) {
        if (priceFactor < 1.0)
            tradeInValue *= priceFactor;
        credits += tradeInValue;
    }
}

- (OOCargoQuantity)cxx_cargoQuantityForType:(const std::string&)type
{
    OOCargoQuantity amount = [shipCommodityData cxx_quantityForGood:type];

    if ([self status] != STATUS_DOCKED) {
        NSInteger i;
        ShipEntity* cargoItem = nil;

        for (i = cargo.size() - 1; i >= 0; i--) {
            cargoItem = cargo[i].get();
            if ([cargoItem cxx_commodityType] == type) // (a nil commodity type never matched)
            {
                amount += [cargoItem commodityAmount];
            }
        }
    }

    return amount;
}

- (OOCargoQuantity)cxx_setCargoQuantityForType:(const std::string&)type amount:(OOCargoQuantity)amount
{
    OOMassUnit unit = [shipCommodityData massUnitForGood:oo::NSStringFrom(type)];
    if ([self cxx_specialCargo].has_value() && unit == UNITS_TONS)
        return 0; // don't do anything if we've got a special cargo...

    OOCargoQuantity oldAmount = [self cxx_cargoQuantityForType:type];
    OOCargoQuantity available = [self availableCargoSpace];
    BOOL inPods = ([self status] != STATUS_DOCKED);

    // check it against the max amount.
    if (unit == UNITS_TONS && (available + oldAmount) < amount) {
        amount = available + oldAmount;
    }
    // if we have 1499 kg the ship registers only 1 ton, so it's possible to exceed the max cargo:
    // eg: with maxAvailableCargoSpace 2 & gold 1499kg, you can still add 1 ton alloy.
    else if (unit == UNITS_KILOGRAMS && amount > oldAmount) {
        // Allow up to 0.5 ton of kg (& g) goods above the cargo capacity but respect existing quantities.
        OOCargoQuantity safeAmount = available * KILOGRAMS_PER_POD + MAX_KILOGRAMS_IN_SAFE;
        if (safeAmount < amount)
            amount = (safeAmount < oldAmount) ? oldAmount : safeAmount;
    } else if (unit == UNITS_GRAMS && amount > oldAmount) {
        OOCargoQuantity safeAmount = available * GRAMS_PER_POD + MAX_GRAMS_IN_SAFE;
        if (safeAmount < amount)
            amount = (safeAmount < oldAmount) ? oldAmount : safeAmount;
    }

    if (inPods) {
        if (amount > oldAmount) // increase
        {
            [self loadCargoPodsForType:type amount:(amount - oldAmount)];
        } else {
            [self unloadCargoPodsForType:type amount:(oldAmount - amount)];
        }
    } else {
        [shipCommodityData cxx_setQuantity:amount forGood:type];
    }

    [self calculateCurrentCargo];
    return [shipCommodityData cxx_quantityForGood:type];
}

- (void)calculateCurrentCargo
{
    current_cargo = [self cargoQuantityOnBoard];
}

- (OOCargoQuantity)cargoQuantityOnBoard
{
    if ([self cxx_specialCargo].has_value()) {
        return [self maxAvailableCargoSpace];
    }

    /*
            The cargo array is nil when the player ship is docked, due to action in unloadCargopods. For
            this reason, we must use a slightly more complex method to determine the quantity of cargo
            carried in this case - Nikos 20090830

            Optimised this method, to compensate for increased usage - Kaks 20091002
    */
    OOCargoQuantity cargoQtyOnBoard = 0;

    for (const std::string& good : oo::StringsFrom([shipCommodityData goods])) {
        OOCargoQuantity quantity = [shipCommodityData cxx_quantityForGood:good];

        OOMassUnit commodityUnits = [shipCommodityData massUnitForGood:oo::NSStringFrom(good)];

        if (commodityUnits != UNITS_TONS) {
            // calculate the number of pods that would be used
            // we're using integer math, so 99/100 = 0 ,  100/100 = 1, etc...

            assert(KILOGRAMS_PER_POD > MAX_KILOGRAMS_IN_SAFE && GRAMS_PER_POD > MAX_GRAMS_IN_SAFE); // otherwise we're in trouble!

            if (commodityUnits == UNITS_KILOGRAMS)
                quantity = ((KILOGRAMS_PER_POD - MAX_KILOGRAMS_IN_SAFE - 1) + quantity) / KILOGRAMS_PER_POD;
            else
                quantity = ((GRAMS_PER_POD - MAX_GRAMS_IN_SAFE - 1) + quantity) / GRAMS_PER_POD;
        }
        cargoQtyOnBoard += quantity;
    }
    cargoQtyOnBoard += [self cxx_cargoCount];

    return cargoQtyOnBoard;
}

- (OOCommodityMarket*)localMarket
{
    StationEntity* station = [self dockedStation];
    if (station == nil) {
        if ([[self primaryTarget] isStation] && [(StationEntity*)[self primaryTarget] marketBroadcast]) {
            station = [self primaryTarget];
        } else {
            station = [UNIVERSE station];
        }
        if (station == nil) {
            // interstellar space or similar
            return nil;
        }
    }
    OOCommodityMarket* localMarket = [station localMarket];
    if (localMarket == nil) {
        localMarket = [station initialiseLocalMarket];
    }

    return localMarket;
}

- (std::vector<std::string>)cxx_applyMarketFilter:(const std::vector<std::string>&)goods onMarket:(OOCommodityMarket*)market
{
    if (marketFilterMode == MARKET_FILTER_MODE_OFF) {
        return goods;
    }
    std::vector<std::string> filteredGoods;
    filteredGoods.reserve(goods.size());
    for (const std::string& good : goods) {
        switch (marketFilterMode) {
        case MARKET_FILTER_MODE_OFF:
            // never reached, but keeps compiler happy
            filteredGoods.push_back(good);
            break;
        case MARKET_FILTER_MODE_TRADE:
            if ([market cxx_quantityForGood:good] > 0 || [self cxx_cargoQuantityForType:good] > 0) {
                filteredGoods.push_back(good);
            }
            break;
        case MARKET_FILTER_MODE_HOLD:
            if ([self cxx_cargoQuantityForType:good] > 0) {
                filteredGoods.push_back(good);
            }
            break;
        case MARKET_FILTER_MODE_STOCK:
            if ([market cxx_quantityForGood:good] > 0) {
                filteredGoods.push_back(good);
            }
            break;
        case MARKET_FILTER_MODE_LEGAL:
            if ([market cxx_exportLegalityForGood:good] == 0 && [market cxx_importLegalityForGood:good] == 0) {
                filteredGoods.push_back(good);
            }
            break;
        case MARKET_FILTER_MODE_RESTRICTED:
            if ([market cxx_exportLegalityForGood:good] > 0 || [market cxx_importLegalityForGood:good] > 0) {
                filteredGoods.push_back(good);
            }
            break;
        }
    }
    return filteredGoods;
}

- (std::vector<std::string>)cxx_applyMarketSorter:(const std::vector<std::string>&)goods onMarket:(OOCommodityMarket*)market
{
    // -sortedArrayUsingFunction:context: was a stable sort (probed), so std::stable_sort gives the same order
    const auto sortedBy = [&goods](int (*sorter)(const std::string&, const std::string&, OOCommodityMarket*), OOCommodityMarket* context) {
        std::vector<std::string> sorted = goods;
        std::stable_sort(sorted.begin(), sorted.end(), [sorter, context](const std::string& a, const std::string& b) { return sorter(a, b, context) < 0; });
        return sorted;
    };
    switch (marketSorterMode) {
    case MARKET_SORTER_MODE_ALPHA:
        return sortedBy(marketSorterByName, market);
    case MARKET_SORTER_MODE_PRICE:
        return sortedBy(marketSorterByPrice, market);
    case MARKET_SORTER_MODE_STOCK:
        return sortedBy(marketSorterByQuantity, market);
    case MARKET_SORTER_MODE_HOLD:
        return sortedBy(marketSorterByQuantity, shipCommodityData);
    case MARKET_SORTER_MODE_UNIT:
        return sortedBy(marketSorterByMassUnit, market);
    case MARKET_SORTER_MODE_OFF:
        // keep default sort order
        break;
    }
    return goods;
}

- (void)showMarketScreenHeaders
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    OOGUITabSettings tab_stops;
    tab_stops[0] = 0;
    tab_stops[1] = 137;
    tab_stops[2] = 187;
    tab_stops[3] = 267;
    tab_stops[4] = 321;
    tab_stops[5] = 431;
    [gui overrideTabs:tab_stops from:kGuiMarketTabs length:6];
    [gui setTabStops:tab_stops];

    [gui setColor:[gui colorFromSetting:kGuiMarketHeadingColor defaultValue:[OOColor greenColor]] forRow:GUI_ROW_MARKET_KEY];
    [gui cxx_setArray:{ oo::StdString(DESC(@"commodity-column-title")), cxx_OOPadStringToEms(oo::StdString(DESC(@"price-column-title")), 3.5),
                          cxx_OOPadStringToEms(oo::StdString(DESC(@"for-sale-column-title")), 3.75), cxx_OOPadStringToEms(oo::StdString(DESC(@"in-hold-column-title")), 5.75), oo::StdString(DESC(@"oolite-legality-column-title")), oo::StdString(DESC(@"oolite-extras-column-title")) }
               forRow:GUI_ROW_MARKET_KEY];
    [gui cxx_setArray:{ oo::StdString(DESC(@"commodity-column-title")), oo::StdString(DESC(@"oolite-extras-column-title")), cxx_OOPadStringToEms(oo::StdString(DESC(@"price-column-title")), 3.5),
                          cxx_OOPadStringToEms(oo::StdString(DESC(@"for-sale-column-title")), 3.75), cxx_OOPadStringToEms(oo::StdString(DESC(@"in-hold-column-title")), 5.75), oo::StdString(DESC(@"oolite-legality-column-title")) }
               forRow:GUI_ROW_MARKET_KEY];
}

- (void)showMarketScreenDataLine:(OOGUIRow)row forGood:(const std::string&)good inMarket:(OOCommodityMarket*)localMarket holdQuantity:(OOCargoQuantity)quantity
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    const std::string desc = oo::str::format(" %s ", [shipCommodityData cxx_nameForGood:good].value_or("(null)").c_str()); // %@ of nil
    OOCargoQuantity available_units = [localMarket cxx_quantityForGood:good];
    OOCargoQuantity units_in_hold = quantity;
    OOCreditsQuantity pricePerUnit = [localMarket cxx_priceForGood:good];
    OOMassUnit unit = [shipCommodityData massUnitForGood:oo::NSStringFrom(good)];

    const std::string available = cxx_OOPadStringToEms(((available_units > 0) ? oo::str::format("%d", available_units) : oo::StdString(DESC(@"commodity-quantity-none"))), 2.5);

    NSUInteger priceDecimal = pricePerUnit % 10;
    const std::string price = oo::str::format(" %s.%zu ", cxx_OOPadStringToEms(oo::str::format("%zu", (pricePerUnit / 10)), 2.5).c_str(), priceDecimal);

    // this works with up to 9999 tons of gemstones. Any more than that, they deserve the formatting they get! :)

    const std::string owned = cxx_OOPadStringToEms((units_in_hold > 0) ? oo::str::format("%d", units_in_hold) : oo::StdString(DESC(@"commodity-quantity-none")), 4.5);
    const std::string units = oo::DescriptionOf(DisplayStringForMassUnit(unit));
    const std::string units_available = oo::str::format(" %s %s ", available.c_str(), units.c_str());
    const std::string units_owned = oo::str::format(" %s %s ", owned.c_str(), units.c_str());

    NSUInteger import_legality = [localMarket cxx_importLegalityForGood:good];
    NSUInteger export_legality = [localMarket cxx_exportLegalityForGood:good];
    std::string legaldesc;
    if (import_legality == 0) {
        if (export_legality == 0) {
            legaldesc = oo::StdString(DESC(@"oolite-legality-clear"));
        } else {
            legaldesc = oo::StdString(DESC(@"oolite-legality-import"));
        }
    } else {
        if (export_legality == 0) {
            legaldesc = oo::StdString(DESC(@"oolite-legality-export"));
        } else {
            legaldesc = oo::StdString(DESC(@"oolite-legality-neither"));
        }
    }
    legaldesc = oo::str::format(" %s ", legaldesc.c_str());

    const std::optional<std::string> extradesc = [shipCommodityData cxx_shortCommentForGood:good];

    [gui cxx_setKey:good forRow:row];
    [gui setColor:[gui colorFromSetting:kGuiMarketCommodityColor defaultValue:nil] forRow:row];
    if (extradesc.has_value())
        [gui cxx_setArray:{ desc, *extradesc, price, units_available, units_owned, legaldesc } forRow:row++];
    else
        [gui cxx_setArray:{ desc } forRow:row++]; // a nil comment ended the -arrayWithObjects: list
}

- (std::optional<std::string>)marketScreenTitle
{
    StationEntity* dockedStation = [self dockedStation];

    /* Override normal behaviour if station broadcasts market */
    if (dockedStation == nil) {
        if ([[self primaryTarget] isStation] && [(StationEntity*)[self primaryTarget] marketBroadcast]) {
            dockedStation = [self primaryTarget];
        }
    }

    std::string system; // (used only when there is a sun)
    if ([UNIVERSE sun] != nil)
        system = oo::StdString([UNIVERSE getSystemName:system_id]);

    if (dockedStation == nil || dockedStation == [UNIVERSE station]) {
        if ([UNIVERSE sun] != nil) {
            return ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "system-commodity-market", { { "system", oo::PList(system) } });
        } else {
            // Witchspace
            return oo::OptionalString(OOExpandKey(@"commodity-market"));
        }
    } else {
        const std::string station = oo::StdString([dockedStation displayName]);
        return ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "station-commodity-market", { { "station", oo::PList(station) } });
    }
}

- (void)setGuiToMarketScreen
{
    OOCommodityMarket* localMarket = [self localMarket];
    GuiDisplayGen* gui = [UNIVERSE gui];
    OOGUIScreenID oldScreen = gui_screen;

    gui_screen = GUI_SCREEN_MARKET;
    BOOL guiChanged = (oldScreen != gui_screen);

    [[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:YES];

    // fix problems with economies in witchspace
    if (localMarket == nil) {
        localMarket = [[UNIVERSE commodities] generateBlankMarket];
    }

    // following changed to work whether docked or not
    const std::vector<std::string> goods = [self cxx_applyMarketSorter:[self cxx_applyMarketFilter:oo::StringsFrom([localMarket goods]) onMarket:localMarket] onMarket:localMarket];
    NSInteger maxOffset = 0;
    if (goods.size() > (GUI_ROW_MARKET_END - GUI_ROW_MARKET_START)) {
        maxOffset = goods.size() - (GUI_ROW_MARKET_END - GUI_ROW_MARKET_START);
    }

    NSUInteger commodityCount = [shipCommodityData count];
    std::vector<OOCargoQuantity> quantityInHold(commodityCount);

    for (NSUInteger i = 0; i < commodityCount; i++) {
        quantityInHold[i] = (i < goods.size()) ? [shipCommodityData cxx_quantityForGood:goods[i]] : 0; // (a nil good had none)
    }
    for (NSUInteger i = 0; i < cargo.size(); i++) {
        ShipEntity* container = cargo[i].get();
        NSUInteger goodsIndex = IndexOfGood(goods, [container cxx_commodityType]);
        // can happen with filters
        if (goodsIndex != NSNotFound) {
            quantityInHold[goodsIndex] += [container commodityAmount];
        }
    }

    if (marketSelectedCommodity.has_value() && (marketSelectedCommodity == "<<<" || marketSelectedCommodity == ">>>")) {
        // nothing?
    } else {
        if (!marketSelectedCommodity.has_value() || IndexOfGood(goods, marketSelectedCommodity) == NSNotFound) {
            marketSelectedCommodity.reset();
            if (goods.size() > 0) {
                marketSelectedCommodity = goods[0];
            }
        }
        if (maxOffset > 0) {
            NSInteger goodsIndex = IndexOfGood(goods, marketSelectedCommodity);
            // validate marketOffset when returning from infoscreen
            if (goodsIndex <= marketOffset) {
                // is off top of list, move list upwards
                if (goodsIndex == 0) {
                    marketOffset = 0;
                } else {
                    marketOffset = goodsIndex - 1;
                }
            } else if (goodsIndex > marketOffset + (GUI_ROW_MARKET_END - GUI_ROW_MARKET_START) - 2) {
                // is off bottom of list, move list downwards
                marketOffset = 2 + goodsIndex - (GUI_ROW_MARKET_END - GUI_ROW_MARKET_START);
                if (marketOffset > maxOffset) {
                    marketOffset = maxOffset;
                }
            }
        }
    }

    // GUI stuff
    {
        OOGUIRow start_row = GUI_ROW_MARKET_START;
        OOGUIRow row = start_row;
        OOGUIRow active_row = [gui selectedRow];

        [gui clearAndKeepBackground:!guiChanged];

        StationEntity* dockedStation = [self dockedStation];
        if (dockedStation == nil && [[self primaryTarget] isStation] && [(StationEntity*)[self primaryTarget] marketBroadcast]) {
            dockedStation = [self primaryTarget];
        }

        [gui setTitle:oo::NSStringOrNil([self marketScreenTitle])];

        [self showMarketScreenHeaders];

        if (marketOffset > maxOffset) {
            marketOffset = 0;
        } else if (marketOffset < 0) {
            marketOffset = maxOffset;
        }

        if (goods.size() > 0) {
            const std::optional<std::string> selectedCommodity = marketSelectedCommodity;
            NSInteger i = 0;
            for (const std::string& good : goods) {
                if (i < marketOffset) {
                    ++i;
                    continue;
                }
                [self showMarketScreenDataLine:row forGood:good inMarket:localMarket holdQuantity:quantityInHold[i++]];
                if (good == selectedCommodity) {
                    active_row = row;
                }

                ++row;
                if (row >= GUI_ROW_MARKET_END) {
                    break;
                }
            }

            if (marketOffset < maxOffset) {
                if (selectedCommodity == ">>>") {
                    active_row = GUI_ROW_MARKET_LAST;
                }
                [gui cxx_setKey:">>>" forRow:GUI_ROW_MARKET_LAST];
                [gui setColor:[gui colorFromSetting:kGuiMarketScrollColor defaultValue:[OOColor greenColor]] forRow:GUI_ROW_MARKET_LAST];
                [gui cxx_setArray: { oo::StdString(DESC(@"gui-more")), "", "", "", " --> " } forRow:GUI_ROW_MARKET_LAST];
            }
            if (marketOffset > 0) {
                if (selectedCommodity == "<<<") {
                    active_row = GUI_ROW_MARKET_START;
                }
                [gui cxx_setKey:"<<<" forRow:GUI_ROW_MARKET_START];
                [gui setColor:[gui colorFromSetting:kGuiMarketScrollColor defaultValue:[OOColor greenColor]] forRow:GUI_ROW_MARKET_START];
                [gui cxx_setArray: { oo::StdString(DESC(@"gui-back")), "", "", "", " <-- " } forRow:GUI_ROW_MARKET_START];
            }
        } else {
            // filter is excluding everything
            [gui setColor:[gui colorFromSetting:kGuiMarketFilteredAllColor defaultValue:[OOColor yellowColor]] forRow:GUI_ROW_MARKET_START];
            [gui cxx_setText:oo::StdString(DESC(@"oolite-market-filtered-all")) forRow:GUI_ROW_MARKET_START];
            active_row = -1;
        }

        // actually count the containers and  valuables (may be > max_cargo)
        current_cargo = [self cargoQuantityOnBoard];
        if (current_cargo > [self maxAvailableCargoSpace])
            current_cargo = [self maxAvailableCargoSpace];

        // filter sort info
        {
            const std::string filterMode = oo::StdString(OOExpandKey(OOExpand(@"oolite-market-filter-[marketFilterMode]", marketFilterMode)));
            const std::string filterText = ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "oolite-market-filter-line", { { "filterMode", oo::PList(filterMode) } });
            const std::string sortMode = oo::StdString(OOExpandKey(OOExpand(@"oolite-market-sorter-[marketSorterMode]", marketSorterMode)));
            const std::string sorterText = ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), "oolite-market-sorter-line", { { "sortMode", oo::PList(sortMode) } });
            [gui cxx_setArray: { filterText, "", sorterText } forRow:GUI_ROW_MARKET_END];
        }
        [gui setColor:[gui colorFromSetting:kGuiMarketFilterInfoColor defaultValue:[OOColor greenColor]] forRow:GUI_ROW_MARKET_END];

        [self showMarketCashAndLoadLine];

        [gui setSelectableRange:NSMakeRange(start_row, row - start_row)];
        [gui setSelectedRow:active_row];

        [gui setShowTextCursor:NO];
    }

    [[UNIVERSE gameView] clearMouse];

    [self setShowDemoShips:NO];
    [UNIVERSE enterGUIViewModeWithMouseInteraction:YES];

    if (guiChanged) {
        [gui setForegroundTextureKey:[self status] == STATUS_DOCKED ? @"docked_overlay" : @"overlay"];
        [gui setBackgroundTextureKey:@"market"];
        [self noteGUIDidChangeFrom:oldScreen to:gui_screen];
    }
}

- (void)setGuiToMarketInfoScreen
{
    OOCommodityMarket* localMarket = [self localMarket];
    GuiDisplayGen* gui = [UNIVERSE gui];
    OOGUIScreenID oldScreen = gui_screen;

    gui_screen = GUI_SCREEN_MARKETINFO;
    BOOL guiChanged = (oldScreen != gui_screen);

    [[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:YES];

    // fix problems with economies in witchspace
    if (localMarket == nil) {
        localMarket = [[UNIVERSE commodities] generateBlankMarket];
    }

    // following changed to work whether docked or not
    const std::vector<std::string> goods = [self cxx_applyMarketSorter:[self cxx_applyMarketFilter:oo::StringsFrom([localMarket goods]) onMarket:localMarket] onMarket:localMarket];

    NSUInteger i, j, commodityCount = [shipCommodityData count];
    std::vector<OOCargoQuantity> quantityInHold(commodityCount);

    for (i = 0; i < commodityCount; i++) {
        quantityInHold[i] = (i < goods.size()) ? [shipCommodityData cxx_quantityForGood:goods[i]] : 0; // (a nil good had none)
    }
    for (i = 0; i < cargo.size(); i++) {
        ShipEntity* container = cargo[i].get();
        j = IndexOfGood(goods, [container cxx_commodityType]);
        quantityInHold[j] += [container commodityAmount];
    }

    // GUI stuff
    {
        if (EXPECT_NOT(!marketSelectedCommodity.has_value())) {
            j = NSNotFound;
        } else {
            j = IndexOfGood(goods, marketSelectedCommodity);
        }
        if (j == NSNotFound) {
            marketSelectedCommodity.reset();
            [self setGuiToMarketScreen];
            return;
        }

        [gui clearAndKeepBackground:!guiChanged];

        const std::string selectedCommodity = *marketSelectedCommodity; // (non-nil here)
        [gui setTitle:oo::NSStringFrom(oo::str::formatRuntime(oo::StdString(DESC(@"oolite-commodity-information-@")), { TextArg([shipCommodityData cxx_nameForGood:selectedCommodity]) }))];

        [self showMarketScreenHeaders];
        [self showMarketScreenDataLine:GUI_ROW_MARKET_START forGood:selectedCommodity inMarket:localMarket holdQuantity:quantityInHold[j]];

        OOCargoQuantity contracted = [self cxx_contractedVolumeForGood:selectedCommodity];
        if (contracted > 0) {
            OOMassUnit unit = [shipCommodityData massUnitForGood:oo::NSStringFrom(selectedCommodity)];
            [gui setColor:[gui colorFromSetting:kGuiMarketContractedColor defaultValue:nil] forRow:GUI_ROW_MARKET_START + 1];
            [gui cxx_setText:oo::str::formatRuntime(oo::StdString(DESC(@"oolite-commodity-contracted-d-@")), { contracted, oo::DescriptionOf(DisplayStringForMassUnit(unit)) }) forRow:GUI_ROW_MARKET_START + 1];
        }

        const std::optional<std::string> info = [shipCommodityData cxx_commentForGood:selectedCommodity];
        OOGUIRow i = 0;
        if (!info.has_value() || info->empty()) {
            i = [gui addLongText:DESC(@"oolite-commodity-no-comment") startingAtRow:GUI_ROW_MARKET_START + 2 align:GUI_ALIGN_LEFT];
        } else {
            i = [gui cxx_addLongText:info startingAtRow:GUI_ROW_MARKET_START + 2 align:GUI_ALIGN_LEFT];
        }
        for (i--; i > GUI_ROW_MARKET_START + 2; --i) {
            [gui setColor:[gui colorFromSetting:kGuiMarketDescriptionColor defaultValue:nil] forRow:i];
        }

        [self showMarketCashAndLoadLine];
    }

    [[UNIVERSE gameView] clearMouse];

    [self setShowDemoShips:NO];
    [UNIVERSE enterGUIViewModeWithMouseInteraction:YES];

    if (guiChanged) {
        [gui setForegroundTextureKey:[self status] == STATUS_DOCKED ? @"docked_overlay" : @"overlay"];
        [gui setBackgroundTextureKey:@"marketinfo"];
        [self noteGUIDidChangeFrom:oldScreen to:gui_screen];
    }
}

- (void)showMarketCashAndLoadLine
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    OOCargoQuantity currentCargo = current_cargo;
    OOCargoQuantity cargoCapacity = [self maxAvailableCargoSpace];
    [gui cxx_setText:oo::StdString(OOExpandKey(@"market-cash-and-load", credits, currentCargo, cargoCapacity)) forRow:GUI_ROW_MARKET_CASH];
    [gui setColor:[gui colorFromSetting:kGuiMarketCashColor defaultValue:[OOColor yellowColor]] forRow:GUI_ROW_MARKET_CASH];
}

- (OOGUIScreenID)guiScreen
{
    return gui_screen;
}

- (BOOL)cxx_tryBuyingCommodity:(const std::string&)index all:(BOOL)all
{
    if (index == "<<<" || index == ">>>") {
        ++marketOffset;
        return NO;
    }

    if (![self isDocked])
        return NO; // can't buy if not docked.

    OOCommodityMarket* localMarket = [self localMarket];
    OOCreditsQuantity pricePerUnit = [localMarket cxx_priceForGood:index];
    OOMassUnit unit = [localMarket massUnitForGood:oo::NSStringFrom(index)];

    if (specialCargo.has_value() && unit == UNITS_TONS) {
        return NO; // can't buy tons of stuff when carrying a specialCargo
    }
    int manifest_quantity = [shipCommodityData cxx_quantityForGood:index];
    int market_quantity = [localMarket cxx_quantityForGood:index];

    int purchase = 1;
    if (all) {
        // if cargo contracts, put a break point on the contract volume
        int contracted = [self cxx_contractedVolumeForGood:index];
        if (manifest_quantity >= contracted) {
            purchase = [localMarket cxx_capacityForGood:index];
        } else {
            purchase = contracted - manifest_quantity;
        }
    }
    if (purchase > market_quantity) {
        purchase = market_quantity; // limit to what's available
    }
    if (purchase * pricePerUnit > credits) {
        purchase = floor(credits / pricePerUnit); // limit to what's affordable
    }
    // TODO - fix brokenness here...
    if (unit == UNITS_TONS && purchase + current_cargo > [self maxAvailableCargoSpace]) {
        purchase = [self availableCargoSpace]; // limit to available cargo space
    } else {
        if (current_cargo == [self maxAvailableCargoSpace]) {
            // other cases are fine so long as buying is limited to <1000kg / <1000000g
            // but if this case is true, we need to see if there is more space in
            // the manifest (safe) or an already-accounted-for pod
            if (unit == UNITS_KILOGRAMS) {
                if (manifest_quantity % KILOGRAMS_PER_POD <= MAX_KILOGRAMS_IN_SAFE && (manifest_quantity + purchase) % KILOGRAMS_PER_POD > MAX_KILOGRAMS_IN_SAFE) {
                    // going from < n500 to >= n500 would increase pods needed by 1
                    purchase = MAX_KILOGRAMS_IN_SAFE - manifest_quantity; // max possible
                }
            } else // UNITS_GRAMS
            {
                if (manifest_quantity % GRAMS_PER_POD <= MAX_GRAMS_IN_SAFE && (manifest_quantity + purchase) % GRAMS_PER_POD > MAX_GRAMS_IN_SAFE) {
                    // going from < n500000 to >= n500000 would increase pods needed by 1
                    purchase = MAX_GRAMS_IN_SAFE - manifest_quantity; // max possible
                }
            }
        }
    }
    if (purchase <= 0) {
        return NO; // stop if that results in nothing to be bought
    }

    [localMarket cxx_removeQuantity:purchase forGood:index];
    [shipCommodityData cxx_addQuantity:purchase forGood:index];
    credits -= pricePerUnit * purchase;

    [self calculateCurrentCargo];

    if ([UNIVERSE autoSave])
        [UNIVERSE setAutoSaveNow:YES];

    [self doScriptEvent:OOJSID("playerBoughtCargo") withArguments:oo::ObjectFromPList(oo::PList(oo::PList::Array { oo::PList(index), oo::PList::signedInteger(purchase), oo::PList::unsignedInteger(pricePerUnit) }))]; // the same number kinds (signed, unsigned long long)
    if ([localMarket cxx_exportLegalityForGood:index] > 0) {
        roleWeightFlags.insert_or_assign("bought-illegal", oo::PList::signedInteger(1)); // +numberWithInt:
    } else {
        roleWeightFlags.insert_or_assign("bought-legal", oo::PList::signedInteger(1)); // +numberWithInt:
    }

    return YES;
}

- (BOOL)cxx_trySellingCommodity:(const std::string&)index all:(BOOL)all
{
    if (index == "<<<" || index == ">>>") {
        --marketOffset;
        return NO;
    }

    if (![self isDocked])
        return NO; // can't sell if not docked.

    OOCommodityMarket* localMarket = [self localMarket];
    int available_units = [shipCommodityData cxx_quantityForGood:index];
    OOCreditsQuantity pricePerUnit = [localMarket cxx_priceForGood:index];

    if (available_units == 0)
        return NO;

    int market_quantity = [localMarket cxx_quantityForGood:index];

    int capacity = [localMarket cxx_capacityForGood:index];
    int sell = 1;
    if (all) {
        // if cargo contracts, put a break point on the contract volume
        int contracted = [self cxx_contractedVolumeForGood:index];
        if (available_units <= contracted) {
            sell = capacity;
        } else {
            sell = available_units - contracted;
        }
    }

    if (sell > available_units)
        sell = available_units; // limit to what's in the hold
    if (sell + market_quantity > capacity)
        sell = capacity - market_quantity; // avoid flooding the market
    if (sell <= 0)
        return NO; // stop if that results in nothing to be sold

    [localMarket cxx_addQuantity:sell forGood:index];
    [shipCommodityData cxx_removeQuantity:sell forGood:index];
    credits += pricePerUnit * sell;

    [self calculateCurrentCargo];

    if ([UNIVERSE autoSave])
        [UNIVERSE setAutoSaveNow:YES];

    [self doScriptEvent:OOJSID("playerSoldCargo") withArguments:oo::ObjectFromPList(oo::PList(oo::PList::Array { oo::PList(index), oo::PList::signedInteger(sell), oo::PList::unsignedInteger(pricePerUnit) }))]; // the same number kinds (signed, unsigned long long)

    return YES;
}

- (BOOL)isMining
{
    return using_mining_laser;
}

- (OOSpeechSettings)isSpeechOn
{
    return isSpeechOn;
}

- (BOOL)canAddEquipment:(id)equipmentKey inContext:(id)context // shared selector (proposed ADR-0043): Objective-C strings
{
    if (oo::OptionalString(equipmentKey) == "EQ_RENOVATION" && !(ship_trade_in_factor < 85 || [self cxx_shipSubEntities].size() < [self maxShipSubEntities]))
        return NO;
    if (![super canAddEquipment:equipmentKey inContext:context])
        return NO;

    OOEquipmentType* eqType = [OOEquipmentType equipmentTypeWithIdentifier:equipmentKey];
    if ([eqType conditions] != nil && ![self scriptTestConditions:[eqType conditions]])
        return NO;

    return YES;
}

- (BOOL)addEquipmentItem:(id)equipmentKey inContext:(id)context // shared selector (proposed ADR-0043): Objective-C strings
{
    return [self addEquipmentItem:equipmentKey withValidation:YES inContext:context];
}

- (BOOL)addEquipmentItem:(id)equipmentKey withValidation:(BOOL)validateAddition inContext:(id)context // shared selector (proposed ADR-0043): Objective-C strings
{
    // deal with trumbles..
    if (oo::OptionalString(equipmentKey) == "EQ_TRUMBLE") {
        /*	Bug fix: must return here if eqKey == @"EQ_TRUMBLE", even if
                trumbleCount >= 1. Otherwise, the player becomes immune to
                trumbles. See comment in -setCommanderDataFromDictionary: for more
                details.
         -- Ahruman 2008-12-04
         */
        // the old trumbles will kill the new one if there are enough of them.
        if ((trumbleCount < PLAYER_MAX_TRUMBLES / 6) || (trumbleCount < PLAYER_MAX_TRUMBLES / 3 && ranrot_rand() % 2 > 0)) {
            [self addTrumble:trumble[ranrot_rand() % PLAYER_MAX_TRUMBLES]]; // randomise its looks.
            return YES;
        }
        return NO;
    }

    BOOL OK = [super addEquipmentItem:equipmentKey withValidation:validateAddition inContext:context];

    if (OK) {
        if ([self hasEquipmentItemProviding:@"EQ_ADVANCED_COMPASS"] && [self compassMode] == COMPASS_MODE_BASIC) {
            [self setCompassMode:COMPASS_MODE_PLANET];
        }

        [self addEqScriptForKey:equipmentKey];
        [self addEquipmentWithScriptToCustomKeyArray:oo::StdString(equipmentKey)]; // (nil matched no script)
    }
    return OK;
}

- (std::vector<oo::PList>*)cxx_customEquipmentActivation
{
    return &customEquipActivation; // the live entries (ADR-0043 item 22)
}

- (void)addEquipmentWithScriptToCustomKeyArray:(const std::string&)equipmentKey
{
    NSUInteger i, j;
    oo::PList object;

    for (i = 0; i < eqScripts.size(); i++) {
        if (eqScripts[i].first == equipmentKey) {
            // check if this equipment item is already in the array
            for (j = 0; j < customEquipActivation.size(); j++) {
                if (StringForKey(customEquipActivation[j], oo::StdString(CUSTOMEQUIP_EQUIPKEY)) == equipmentKey)
                    return;
            }
            // if we get here, this item is new
            // add the basic info at this point (equipkey and name only; a nil name ended the list)
            OOEquipmentType* eq = [OOEquipmentType equipmentTypeWithIdentifier:oo::NSStringFrom(equipmentKey)];
            oo::PList::Dict customKey;
            customKey[oo::StdString(CUSTOMEQUIP_EQUIPKEY)] = equipmentKey;
            const std::optional<std::string> equipmentName = oo::OptionalString([eq name]);
            if (equipmentName.has_value())
                customKey[oo::StdString(CUSTOMEQUIP_EQUIPNAME)] = *equipmentName;

            // grab any default keys from the equipment item
            // default activate
            object = oo::PListFrom([eq defaultActivateKey]);
            if ((object.isArray() && object.count() > 0))
                customKey[oo::StdString(CUSTOMEQUIP_KEYACTIVATE)] = object;
            // default mode
            object = oo::PListFrom([eq defaultModeKey]);
            if ((object.isArray() && object.count() > 0))
                customKey[oo::StdString(CUSTOMEQUIP_KEYMODE)] = object;

            customEquipActivation.push_back(oo::PList(std::move(customKey)));
            // keep the keypress arrays in sync
            customActivatePressed.push_back(NO);
            customModePressed.push_back(NO);

            oo::Defaults::standard().setObject(oo::StdString(KEYCONFIG_CUSTOMEQUIP), oo::PList(customEquipActivation));
            return;
        }
    }
}

- (void)validateCustomEquipActivationArray
{
    int i;
    bool update = NO;
    std::optional<std::string> equipmentKey;
    if (customEquipActivation.size() == 0)
        return;
    for (i = customEquipActivation.size() - 1; i >= 0; i--) {
        equipmentKey = StringForKey(customEquipActivation[i], oo::StdString(CUSTOMEQUIP_EQUIPKEY));
        OOEquipmentType* eq = [OOEquipmentType equipmentTypeWithIdentifier:oo::NSStringOrNil(equipmentKey)];
        if (!eq) {
            customEquipActivation.erase(customEquipActivation.begin() + i);
            customActivatePressed.erase(customActivatePressed.begin() + i);
            customModePressed.erase(customModePressed.begin() + i);
            update = YES;
        }
    }
    if (update) {
        oo::Defaults::standard().setObject(oo::StdString(KEYCONFIG_CUSTOMEQUIP), oo::PList(customEquipActivation));
    }
}

- (void)removeEquipmentItem:(id)equipmentKey // shared selector (proposed ADR-0043): an Objective-C string
{
    if (![self hasEquipmentItemProviding:@"EQ_ADVANCED_COMPASS"] && [self compassMode] != COMPASS_MODE_BASIC) {
        [self setCompassMode:COMPASS_MODE_BASIC];
    }
    [super removeEquipmentItem:equipmentKey];
    if (![self hasEquipmentItem:equipmentKey]) {
        // removed the last one
        [self removeEqScriptForKey:equipmentKey];
    }
}

- (void)addEquipmentFromCollection:(id)equipment
{
    oo::PList dict; // null unless the collection is a dictionary
    std::vector<std::string> eqKeys; // the keys / elements in the collection's enumeration order
    NSUInteger i, count;

    // Pass 1: Load the entire collection.
    if (oo::IsNSDictionary(equipment)) {
        dict = oo::PListFrom(equipment);
        eqKeys = oo::StringsFrom(equipment);
    } else if (oo::IsNSArray(equipment) || oo::IsNSSet(equipment)) {
        eqKeys = oo::StringsFrom(equipment);
    } else if (oo::IsNSString(equipment)) {
        eqKeys = { oo::StdString(equipment) };
    } else {
        return;
    }

    for (const std::string& eqDesc : eqKeys) {
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
        if (eqDesc == "EQ_TRUMBLE")
            continue;

        // Traditional form is a dictionary of booleans; we only accept those where the value is true.
        if (!dict.isNull() && !dict.get<bool>(eqDesc))
            continue;

        // We need to add the entire collection without validation first and then remove the items that are
        // not compliant (like items that do not satisfy the requiresEquipment criterion). This is to avoid
        // unintentionally excluding valid equipment, just because the required equipment existed but had
        // not been yet added to the equipment list at the time of the canAddEquipment validation check.
        // Nikos, 20080817.
        count = dict.get<NSUInteger>(eqDesc); // (0 for a list: nothing is added from one here, as before)
        for (i = 0; i < count; i++) {
            [self addEquipmentItem:oo::NSStringFrom(eqDesc) withValidation:NO inContext:@"loading"];
        }
    }

    // Pass 2: Remove items that do not satisfy validation criteria (like requires_equipment etc.).
    // (the same collection, walked again in the same order)
    // Now remove items that should not be in the equipment list.
    for (const std::string& eqDesc : eqKeys) {
        if (![self cxx_equipmentValidToAdd:eqDesc whileLoading:YES inContext:"loading"]) {
            [self removeEquipmentItem:oo::NSStringFrom(eqDesc)];
        }
    }
}

- (BOOL)hasOneEquipmentItem:(const std::string&)itemKey includeMissiles:(BOOL)includeMissiles
{
    // Check basic equipment the normal way.
    if ([super cxx_hasOneEquipmentItem:itemKey includeMissiles:NO whileLoading:NO])
        return YES;

    // Custom handling for player missiles.
    if (includeMissiles) {
        unsigned i;
        for (i = 0; i < max_missiles; i++) {
            if ([[self missileForPylon:i] hasPrimaryRole:oo::NSStringFrom(itemKey)])
                return YES;
        }
    }

    if (itemKey == "EQ_TRUMBLE") {
        return [self trumbleCount] > 0;
    }

    return NO;
}

- (BOOL)hasPrimaryWeapon:(OOWeaponType)weaponType
{
    if ([[forward_weapon_type identifier] isEqualToString:[weaponType identifier]] ||
        [[aft_weapon_type identifier] isEqualToString:[weaponType identifier]] ||
        [[port_weapon_type identifier] isEqualToString:[weaponType identifier]] ||
        [[starboard_weapon_type identifier] isEqualToString:[weaponType identifier]]) {
        return YES;
    }

    return [super hasPrimaryWeapon:weaponType];
}

- (BOOL)removeExternalStore:(OOEquipmentType*)eqType
{
    // Look for matching missile.
    unsigned i;
    for (i = 0; i < max_missiles; i++) {
        if ([[self missileForPylon:i] hasPrimaryRole:[eqType identifier]]) {
            [self removeFromPylon:i];

            // Just remove one at a time.
            return YES;
        }
    }
    return NO;
}

- (BOOL)removeFromPylon:(NSUInteger)pylon
{
    if (pylon >= max_missiles)
        return NO;

    if (missile_entity[pylon] != nil) {
        [super removeExternalStore:[OOEquipmentType equipmentTypeWithIdentifier:[missile_entity[pylon] primaryRole]]];

        // Remove the missile (must wait until we've finished with its identifier string!)
        [missile_entity[pylon] release];
        missile_entity[pylon] = nil;

        [self tidyMissilePylons];

        // This should be the currently selected missile, deselect it.
        if (pylon <= activeMissile) {
            if (activeMissile == missiles && missiles > 0)
                activeMissile--;
            if (activeMissile > 0)
                activeMissile--;
            else
                activeMissile = max_missiles - 1;

            [self selectNextMissile];
        }

        return YES;
    }

    return NO;
}

- (NSUInteger)parcelCount
{
    return parcels.size();
}

- (NSUInteger)passengerCount
{
    return passengers.size();
}

- (NSUInteger)passengerCapacity
{
    return max_passengers;
}

- (BOOL)hasHostileTarget
{
    ShipEntity* playersTarget = [self primaryTarget];
    return ([playersTarget isShip] && [playersTarget hasHostileTarget] && [playersTarget primaryTarget] == self);
}

- (void)receiveCommsMessage:(id)message_text from:(ShipEntity*)other // shared selector (proposed ADR-0043): an Objective-C string
{
    if ([self status] == STATUS_DEAD || [self status] == STATUS_DOCKED) {
        // only when in flight
        return;
    }
    [UNIVERSE addCommsMessage:oo::NSStringFrom(oo::str::format("%s:\n %s", oo::DescriptionOf([other displayName]).c_str(), oo::DescriptionOf(message_text).c_str())) forCount:4.5];
    [super receiveCommsMessage:message_text from:other];
}

- (void)getFined
{
    if (legalStatus == 0)
        return; // nothing to pay for

    OOGovernmentID local_gov = oo::PListView([UNIVERSE currentSystemData]).get<int>(KEY_GOVERNMENT);
    if ([UNIVERSE inInterstellarSpace])
        local_gov = 1; // equivalent to Feudal. I'm assuming any station in interstellar space is military. -- Ahruman 2008-05-29
    OOCreditsQuantity fine = 500 + ((local_gov < 2 || local_gov > 5) ? 500 : 0);
    fine *= legalStatus;
    if (fine > credits) {
        int payback = (int)(legalStatus * credits / fine);
        [self setBounty:(legalStatus - payback) withReason:kOOLegalStatusReasonPaidFine];
        credits = 0;
    } else {
        [self setBounty:0 withReason:kOOLegalStatusReasonPaidFine];
        credits -= fine;
    }

    // one of the fined-@-credits strings includes expansion tokens
    const std::string fined_message = oo::str::formatRuntime(oo::StdString(OOExpandKey(@"fined-@-credits")), { cxx_OOCredits(fine) });
    [self cxx_addMessageToReport:fined_message];
    [UNIVERSE forceWitchspaceEntries];
    ship_clock_adjust += 24 * 3600; // take up a day
}

- (void)adjustTradeInFactorBy:(int)value
{
    ship_trade_in_factor += value;
    if (ship_trade_in_factor < 75)
        ship_trade_in_factor = 75;
    if (ship_trade_in_factor > 100)
        ship_trade_in_factor = 100;
}

- (int)tradeInFactor
{
    return ship_trade_in_factor;
}

- (double)renovationCosts
{
    // 5% of value of ships wear + correction for missing subentities.
    OOCreditsQuantity shipValue = [UNIVERSE tradeInValueForCommanderDictionary:[self commanderDataDictionary]];

    double costs = 0.005 * (100 - ship_trade_in_factor) * shipValue;
    costs += 0.01 * shipValue * [self missingSubEntitiesAdjustment];
    costs *= [self renovationFactor];
    return cunningFee(costs, 0.05);
}

- (double)renovationFactor
{
    OOShipRegistry* registry = [OOShipRegistry sharedRegistry];
    const oo::PList shipyardInfo = [registry cxx_shipyardInfoForKey:oo::StdString([self shipDataKey])];
    return shipyardInfo.get<double>(oo::StdString(KEY_RENOVATION_MULTIPLIER), 1.0);
}

- (void)setDefaultViewOffsets
{
    float halfLength = 0.5f * (boundingBox.max.z - boundingBox.min.z);
    float halfWidth = 0.5f * (boundingBox.max.x - boundingBox.min.x);

    forwardViewOffset = make_vector(0.0f, 0.0f, boundingBox.max.z - halfLength);
    aftViewOffset = make_vector(0.0f, 0.0f, boundingBox.min.z + halfLength);
    portViewOffset = make_vector(boundingBox.min.x + halfWidth, 0.0f, 0.0f);
    starboardViewOffset = make_vector(boundingBox.max.x - halfWidth, 0.0f, 0.0f);
    customViewOffset = kZeroVector;
}

- (void)setDefaultCustomViews
{
    const oo::PList shipInfo = [[OOShipRegistry sharedRegistry] cxx_shipInfoForKey:oo::StdString(PLAYER_SHIP_DESC)];
    const oo::PList* customViews = shipInfo.find("custom_views");

    _customViews.clear();
    _customViewIndex = 0;
    if (customViews != nullptr) {
        _customViews = CustomViewsFrom(*customViews);
    }
}

- (Vector)weaponViewOffset
{
    switch (currentWeaponFacing) {
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

- (void)setUpTrumbles
{
    std::u16string trumbleDigrams; // UTF-16 units, as the old mutable string held them
    unichar xchar = (unichar)0;
    unichar digramchars[2];

    while (trumbleDigrams.size() < PLAYER_MAX_TRUMBLES + 2) {
        const std::optional<std::string> commanderName = [self cxx_commanderName];
        if (commanderName.has_value() && !commanderName->empty()) {
            trumbleDigrams += oo::utf8ToUtf16(*commanderName + [[self mesh] modelName].value_or("(null)")); // "%@%@"
        } else {
            trumbleDigrams += u"Some Random Text!";
        }
    }
    int i;
    for (i = 0; i < PLAYER_MAX_TRUMBLES; i++) {
        digramchars[0] = (trumbleDigrams[i] & 0x007f) | 0x0020;
        digramchars[1] = ((trumbleDigrams[i + 1] ^ xchar) & 0x007f) | 0x0020;
        xchar = digramchars[0];
        const std::string digramstring = { static_cast<char>(digramchars[0]), static_cast<char>(digramchars[1]) }; // both ASCII
        [trumble[i] release];
        trumble[i] = [[OOTrumble alloc] initForPlayer:self digram:digramstring];
    }

    trumbleCount = 0;

    [self setTrumbleAppetiteAccumulator:0.0f];
}

- (void)addTrumble:(OOTrumble*)papaTrumble
{
    if (trumbleCount >= PLAYER_MAX_TRUMBLES) {
        return;
    }
    OOTrumble* trumblePup = trumble[trumbleCount];
    [trumblePup spawnFrom:papaTrumble];
    trumbleCount++;
}

- (void)removeTrumble:(OOTrumble*)deadTrumble
{
    if (trumbleCount <= 0) {
        return;
    }
    NSUInteger trumble_index = NSNotFound;
    NSUInteger i;

    for (i = 0; (trumble_index == NSNotFound) && (i < trumbleCount); i++) {
        if (trumble[i] == deadTrumble)
            trumble_index = i;
    }
    if (trumble_index == NSNotFound) {
        OO_LOG("trumble.zombie", "DEBUG can't get rid of inactive trumble {}", oo::DescriptionOf(deadTrumble));
        return;
    }
    trumbleCount--; // reduce number of trumbles
    trumble[trumble_index] = trumble[trumbleCount]; // swap with the current last trumble
    trumble[trumbleCount] = deadTrumble; // swap with the current last trumble
}

- (OOTrumble**)trumbleArray
{
    return trumble;
}

- (NSUInteger)trumbleCount
{
    return trumbleCount;
}

- (id)trumbleValue
{
    const std::string namekey = oo::str::format("%s-humbletrash", [self cxx_commanderName].value_or("(null)").c_str());
    int trumbleHash;

    clear_checksum();
    [self mungChecksumWithString:[self cxx_commanderName]];
    munge_checksum(credits);
    munge_checksum(ship_kills);
    trumbleHash = munge_checksum(trumbleCount);

    oo::Defaults::standard().setInteger(namekey, trumbleHash);

    int i;
    oo::PList::Array trumbleArray;
    trumbleArray.reserve(PLAYER_MAX_TRUMBLES);
    for (i = 0; i < PLAYER_MAX_TRUMBLES; i++) {
        trumbleArray.push_back([trumble[i] dictionary]);
    }

    // [count (unsigned), hash (signed), trumbles]: the same number kinds as before
    return oo::ObjectFromPList(oo::PList(oo::PList::Array { oo::PList::unsignedInteger(trumbleCount), oo::PList::signedInteger(trumbleHash), oo::PList(std::move(trumbleArray)) }));
}

- (void)setTrumbleValueFrom:(NSObject*)trumbleValue
{
    BOOL info_failed = NO;
    int trumbleHash;
    int putativeHash = 0;
    int putativeNTrumbles = 0;
    oo::PList putativeTrumbleArray; // null unless an array
    int i;
    const std::string namekey = oo::str::format("%s-humbletrash", [self cxx_commanderName].value_or("(null)").c_str());

    [self setUpTrumbles];

    if (trumbleValue) {
        BOOL possible_cheat = NO;
        if (!oo::IsNSArray(trumbleValue))
            info_failed = YES;
        else {
            const oo::PList values = oo::PListFrom(trumbleValue);
            if (values.count() >= 1)
                putativeNTrumbles = values.at<int>(0);
            if (values.count() >= 2)
                putativeHash = values.at<int>(1);
            if (values.count() >= 3 && values.at(2)->isArray())
                putativeTrumbleArray = *values.at(2);
        }
        // calculate a hash for the putative values
        clear_checksum();
        [self mungChecksumWithString:[self cxx_commanderName]];
        munge_checksum(credits);
        munge_checksum(ship_kills);
        trumbleHash = munge_checksum(putativeNTrumbles);

        if (putativeHash != trumbleHash)
            info_failed = YES;

        if (info_failed) {
            OO_LOG("cheat.tentative", "{}", "POSSIBLE CHEAT DETECTED");
            possible_cheat = YES;
        }

        for (i = 1; (info_failed) && (i < PLAYER_MAX_TRUMBLES); i++) {
            // try to determine trumbleCount from the key in the saved game
            clear_checksum();
            [self mungChecksumWithString:[self cxx_commanderName]];
            munge_checksum(credits);
            munge_checksum(ship_kills);
            trumbleHash = munge_checksum(i);
            if (putativeHash == trumbleHash) {
                info_failed = NO;
                putativeNTrumbles = i;
            }
        }

        if (possible_cheat && !info_failed)
            OO_LOG("cheat.verified", "{}", "CHEAT DEFEATED - that's not the way to get rid of trumbles!");
    } else
    // if trumbleValue comes in as nil, then probably someone has toyed with the save file
    // by removing the entire trumbles array
    {
        OO_LOG("cheat.tentative", "{}", "POSSIBLE CHEAT DETECTED");
        info_failed = YES;
    }

    if (info_failed && !oo::Defaults::standard().object(namekey).isNull()) {
        // try to determine trumbleCount from the key in user defaults
        putativeHash = (int)oo::Defaults::standard().integerForKey(namekey);
        for (i = 1; (info_failed) && (i < PLAYER_MAX_TRUMBLES); i++) {
            clear_checksum();
            [self mungChecksumWithString:[self cxx_commanderName]];
            munge_checksum(credits);
            munge_checksum(ship_kills);
            trumbleHash = munge_checksum(i);
            if (putativeHash == trumbleHash) {
                info_failed = NO;
                putativeNTrumbles = i;
            }
        }

        if (!info_failed)
            OO_LOG("cheat.verified", "{}", "CHEAT DEFEATED - that's not the way to get rid of trumbles!");
    }
    // at this stage we've done the best we can to stop cheaters
    trumbleCount = putativeNTrumbles;

    if ((!putativeTrumbleArray.isNull()) && (putativeTrumbleArray.count() == PLAYER_MAX_TRUMBLES)) {
        for (i = 0; i < PLAYER_MAX_TRUMBLES; i++)
            [trumble[i] setFromDictionary:(putativeTrumbleArray.at(i)->isDict() ? *putativeTrumbleArray.at(i) : oo::PList())]; // null PList unless a dictionary
    }

    clear_checksum();
    [self mungChecksumWithString:[self cxx_commanderName]];
    munge_checksum(credits);
    munge_checksum(ship_kills);
    trumbleHash = munge_checksum(trumbleCount);

    oo::Defaults::standard().setInteger(namekey, trumbleHash);
}

- (float)trumbleAppetiteAccumulator
{
    return _trumbleAppetiteAccumulator;
}

- (void)setTrumbleAppetiteAccumulator:(float)value
{
    _trumbleAppetiteAccumulator = value;
}

- (void)mungChecksumWithString:(const std::optional<std::string>&)str
{
    if (!str.has_value())
        return;

    for (char16_t unit : oo::utf8ToUtf16(*str)) // the UTF-16 units, as -characterAtIndex: gave them
    {
        munge_checksum(unit);
    }
}

- (std::optional<std::string>)cxx_screenModeStringForWidth:(unsigned)width height:(unsigned)height refreshRate:(float)refreshRate
{
    if (0.0f != refreshRate) {
        return oo::OptionalString(OOExpandKey(@"gameoptions-fullscreen-with-refresh-rate", width, height, refreshRate));
    } else {
        return oo::OptionalString(OOExpandKey(@"gameoptions-fullscreen", width, height));
    }
}

- (void)suppressTargetLost
{
    suppressTargetLost = YES;
}

- (void)setScoopsActive
{
    scoopsActive = YES;
}

// override shipentity to stop foundTarget being changed during escape sequence
- (void)setFoundTarget:(Entity*)targetEntity
{
    /* Rare, but can happen, e.g. if a Q-mine goes off nearby during
     * the sequence */
    if ([self status] == STATUS_ESCAPE_SEQUENCE) {
        return;
    }
    [_foundTarget release];
    _foundTarget = [targetEntity weakRetain];
}

// override shipentity addTarget to implement target_memory
- (void)addTarget:(Entity*)targetEntity
{
    if ([self status] != STATUS_IN_FLIGHT && [self status] != STATUS_WITCHSPACE_COUNTDOWN)
        return;
    if (targetEntity == self)
        return;

    [super addTarget:targetEntity];

    if ([targetEntity isWormhole]) {
        assert([self hasEquipmentItemProviding:@"EQ_WORMHOLE_SCANNER"]);
        [self addScannedWormhole:(WormholeEntity*)targetEntity];
    }
    // wormholes don't go in target memory
    else if ([self hasEquipmentItemProviding:@"EQ_TARGET_MEMORY"] && targetEntity != nil) {
        OOWeakReference* targetRef = [targetEntity weakSelf];
        // -indexOfObject: compared the weak references (proxies) by identity
        const auto slotFor = [self](OOWeakReference* ref) -> NSUInteger {
            const auto found = std::find_if(target_memory.begin(), target_memory.end(), [ref](const oo::ObjCRef<OOWeakReference*>& slot) { return slot.get() == ref; });
            return (found != target_memory.end()) ? static_cast<NSUInteger>(found - target_memory.begin()) : NSNotFound;
        };
        NSUInteger i = slotFor(targetRef);
        // if already in target memory, preserve that and just change the index
        if (i != NSNotFound) {
            target_memory_index = i;
        } else {
            i = slotFor(nil); // an empty slot
            // find and use a blank space in memory
            if (i != NSNotFound) {
                target_memory.at(i) = oo::ObjCRef<OOWeakReference*>(targetRef);
                target_memory_index = i;
            } else {
                // use the next memory space
                target_memory_index = (target_memory_index + 1) % PLAYER_TARGET_MEMORY_SIZE;
                target_memory.at(target_memory_index) = oo::ObjCRef<OOWeakReference*>(targetRef);
            }
        }
    }

    if (ident_engaged) {
        [self playIdentLockedOn];
        [self printIdentLockedOnForMissile:NO];
    } else if ([targetEntity isShip] && [self weaponsOnline]) // Only let missiles target-lock onto ships
    {
        if ([missile_entity[activeMissile] isMissile]) {
            missile_status = MISSILE_STATUS_TARGET_LOCKED;
            [missile_entity[activeMissile] addTarget:targetEntity];
            [self playMissileLockedOn];
            [self printIdentLockedOnForMissile:YES];
        } else // It's a mine or something
        {
            missile_status = MISSILE_STATUS_ARMED;
            [self playIdentLockedOn];
            [self printIdentLockedOnForMissile:NO];
        }
    }
}

- (void)clearTargetMemory
{
    NSUInteger memoryCount = target_memory.size();
    for (NSUInteger i = 0; i < PLAYER_TARGET_MEMORY_SIZE; i++) {
        if (i < memoryCount) {
            target_memory[i] = nullptr;
        } else {
            target_memory.emplace_back();
        }
    }
    target_memory_index = 0;
}

- (std::vector<oo::ObjCRef<OOWeakReference*>>)cxx_targetMemory
{
    return target_memory;
}

- (BOOL)moveTargetMemoryBy:(NSInteger)delta
{
    unsigned i = 0;
    while (i++ < PLAYER_TARGET_MEMORY_SIZE) // limit loops
    {
        NSInteger idx = (NSInteger)target_memory_index + delta;
        while (idx < 0)
            idx += PLAYER_TARGET_MEMORY_SIZE;
        while (idx >= PLAYER_TARGET_MEMORY_SIZE)
            idx -= PLAYER_TARGET_MEMORY_SIZE;
        target_memory_index = idx;

        id targ_id = target_memory.at(target_memory_index).get(); // nil for an empty slot, which is not a proxy either
        if ([targ_id isProxy]) {
            ShipEntity* potential_target = [(OOWeakReference*)targ_id weakRefUnderlyingObject];

            if ((potential_target) && (potential_target->isShip) && ([potential_target isInSpace])) {
                if (potential_target->zero_distance < SCANNER_MAX_RANGE2 && (![potential_target isCloaked])) {
                    [super addTarget:potential_target];
                    if (missile_status != MISSILE_STATUS_SAFE) {
                        if ([missile_entity[activeMissile] isMissile]) {
                            [missile_entity[activeMissile] addTarget:potential_target];
                            missile_status = MISSILE_STATUS_TARGET_LOCKED;
                            [self printIdentLockedOnForMissile:YES];
                        } else {
                            missile_status = MISSILE_STATUS_ARMED;
                            [self playIdentLockedOn];
                            [self printIdentLockedOnForMissile:NO];
                        }
                    } else {
                        ident_engaged = YES;
                        [self printIdentLockedOnForMissile:NO];
                    }
                    [self playTargetSwitched];
                    return YES;
                }
            } else {
                target_memory.at(target_memory_index) = nullptr;
            }
        }
    }

    [self playNoTargetInMemory];
    return NO;
}

- (void)printIdentLockedOnForMissile:(BOOL)missile
{
    if ([self primaryTarget] == nil)
        return;

    const std::string fmt = missile ? "missile-locked-onto-target" : "ident-locked-onto-target";
    const std::string target = oo::StdString([[self primaryTarget] identFromShip:self]); // (nil raised in the expansion)
    [UNIVERSE addMessage:oo::NSStringFrom(ExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), fmt, { { "target", oo::PList(target) } })) forCount:4.5];
}

- (Quaternion)customViewQuaternion
{
    return customViewQuaternion;
}

- (void)setCustomViewQuaternion:(Quaternion)q
{
    customViewQuaternion = q;
    [self setCustomViewData];
}

- (OOMatrix)customViewMatrix
{
    return customViewMatrix;
}

- (Vector)customViewOffset
{
    return customViewOffset;
}

- (void)setCustomViewOffset:(Vector)offset
{
    customViewOffset = offset;
}

- (Vector)customViewRotationCenter
{
    return customViewRotationCenter;
}

- (void)setCustomViewRotationCenter:(Vector)center
{
    customViewRotationCenter = center;
}

- (void)customViewZoomIn:(OOScalar)rate
{
    customViewOffset = vector_subtract(customViewOffset, customViewRotationCenter);
    customViewOffset = vector_multiply_scalar(customViewOffset, 1.0 / rate);
    OOScalar m = magnitude(customViewOffset);
    if (m < CUSTOM_VIEW_MAX_ZOOM_IN * collision_radius) {
        scale_vector(&customViewOffset, CUSTOM_VIEW_MAX_ZOOM_IN * collision_radius / m);
    }
    customViewOffset = vector_add(customViewOffset, customViewRotationCenter);
}

- (void)customViewZoomOut:(OOScalar)rate
{
    customViewOffset = vector_subtract(customViewOffset, customViewRotationCenter);
    customViewOffset = vector_multiply_scalar(customViewOffset, rate);
    OOScalar m = magnitude(customViewOffset);
    if (m > CUSTOM_VIEW_MAX_ZOOM_OUT * collision_radius) {
        scale_vector(&customViewOffset, CUSTOM_VIEW_MAX_ZOOM_OUT * collision_radius / m);
    }
    customViewOffset = vector_add(customViewOffset, customViewRotationCenter);
}

- (void)customViewRotateLeft:(OOScalar)angle
{
    customViewOffset = vector_subtract(customViewOffset, customViewRotationCenter);
    OOScalar m = magnitude(customViewOffset);
    quaternion_rotate_about_axis(&customViewQuaternion, customViewUpVector, -angle);
    [self setCustomViewData];
    customViewOffset = vector_flip(customViewForwardVector);
    scale_vector(&customViewOffset, m / magnitude(customViewOffset));
    customViewOffset = vector_add(customViewOffset, customViewRotationCenter);
}

- (void)customViewRotateRight:(OOScalar)angle
{
    customViewOffset = vector_subtract(customViewOffset, customViewRotationCenter);
    OOScalar m = magnitude(customViewOffset);
    quaternion_rotate_about_axis(&customViewQuaternion, customViewUpVector, angle);
    [self setCustomViewData];
    customViewOffset = vector_flip(customViewForwardVector);
    scale_vector(&customViewOffset, m / magnitude(customViewOffset));
    customViewOffset = vector_add(customViewOffset, customViewRotationCenter);
}

- (void)customViewRotateUp:(OOScalar)angle
{
    customViewOffset = vector_subtract(customViewOffset, customViewRotationCenter);
    OOScalar m = magnitude(customViewOffset);
    quaternion_rotate_about_axis(&customViewQuaternion, customViewRightVector, -angle);
    [self setCustomViewData];
    customViewOffset = vector_flip(customViewForwardVector);
    scale_vector(&customViewOffset, m / magnitude(customViewOffset));
    customViewOffset = vector_add(customViewOffset, customViewRotationCenter);
}

- (void)customViewRotateDown:(OOScalar)angle
{
    customViewOffset = vector_subtract(customViewOffset, customViewRotationCenter);
    OOScalar m = magnitude(customViewOffset);
    quaternion_rotate_about_axis(&customViewQuaternion, customViewRightVector, angle);
    [self setCustomViewData];
    customViewOffset = vector_flip(customViewForwardVector);
    scale_vector(&customViewOffset, m / magnitude(customViewOffset));
    customViewOffset = vector_add(customViewOffset, customViewRotationCenter);
}

- (void)customViewRollRight:(OOScalar)angle
{
    customViewOffset = vector_subtract(customViewOffset, customViewRotationCenter);
    OOScalar m = magnitude(customViewOffset);
    quaternion_rotate_about_axis(&customViewQuaternion, customViewForwardVector, -angle);
    [self setCustomViewData];
    customViewOffset = vector_flip(customViewForwardVector);
    scale_vector(&customViewOffset, m / magnitude(customViewOffset));
    customViewOffset = vector_add(customViewOffset, customViewRotationCenter);
}

- (void)customViewRollLeft:(OOScalar)angle
{
    customViewOffset = vector_subtract(customViewOffset, customViewRotationCenter);
    OOScalar m = magnitude(customViewOffset);
    quaternion_rotate_about_axis(&customViewQuaternion, customViewForwardVector, angle);
    [self setCustomViewData];
    customViewOffset = vector_flip(customViewForwardVector);
    scale_vector(&customViewOffset, m / magnitude(customViewOffset));
    customViewOffset = vector_add(customViewOffset, customViewRotationCenter);
}

- (void)customViewPanUp:(OOScalar)angle
{
    quaternion_rotate_about_axis(&customViewQuaternion, customViewRightVector, angle);
    [self setCustomViewData];
    customViewRotationCenter = vector_subtract(customViewOffset, vector_multiply_scalar(customViewForwardVector, dot_product(customViewOffset, customViewForwardVector)));
}

- (void)customViewPanDown:(OOScalar)angle
{
    quaternion_rotate_about_axis(&customViewQuaternion, customViewRightVector, -angle);
    [self setCustomViewData];
    customViewRotationCenter = vector_subtract(customViewOffset, vector_multiply_scalar(customViewForwardVector, dot_product(customViewOffset, customViewForwardVector)));
}

- (void)customViewPanLeft:(OOScalar)angle
{
    quaternion_rotate_about_axis(&customViewQuaternion, customViewUpVector, angle);
    [self setCustomViewData];
    customViewRotationCenter = vector_subtract(customViewOffset, vector_multiply_scalar(customViewForwardVector, dot_product(customViewOffset, customViewForwardVector)));
}

- (void)customViewPanRight:(OOScalar)angle
{
    quaternion_rotate_about_axis(&customViewQuaternion, customViewUpVector, -angle);
    [self setCustomViewData];
    customViewRotationCenter = vector_subtract(customViewOffset, vector_multiply_scalar(customViewForwardVector, dot_product(customViewOffset, customViewForwardVector)));
}

- (Vector)customViewForwardVector
{
    return customViewForwardVector;
}

- (Vector)customViewUpVector
{
    return customViewUpVector;
}

- (Vector)customViewRightVector
{
    return customViewRightVector;
}

- (std::optional<std::string>)cxx_customViewDescription
{
    return customViewDescription;
}

- (void)resetCustomView
{
    const oo::PList customView = (_customViewIndex < _customViews.size()) ? _customViews[_customViewIndex] : oo::PList();
    [self cxx_setCustomViewDataFromDictionary:(customView.isDict() ? customView : oo::PList()) withScaling:NO]; // null unless a Dict, as oo_dictionaryAtIndex:
}

- (void)setCustomViewData
{
    customViewRightVector = vector_right_from_quaternion(customViewQuaternion);
    customViewUpVector = vector_up_from_quaternion(customViewQuaternion);
    customViewForwardVector = vector_forward_from_quaternion(customViewQuaternion);

    Quaternion q1 = customViewQuaternion;
    q1.w = -q1.w;
    customViewMatrix = OOMatrixForQuaternionRotation(q1);
}

- (void)cxx_setCustomViewDataFromDictionary:(const oo::PList&)viewDict withScaling:(BOOL)withScaling
{
    customViewMatrix = kIdentityMatrix;
    customViewOffset = kZeroVector;
    if (viewDict.isNull())
        return;

    customViewQuaternion = QuaternionForKey(viewDict, "view_orientation");
    [self setCustomViewData];

    // easier to do the multiplication at this point than at load time
    if (withScaling) {
        customViewOffset = vector_multiply_scalar(VectorForKey(viewDict, "view_position"), _scaleFactor);
    } else {
        // but don't do this when the custom view is set through JS
        customViewOffset = VectorForKey(viewDict, "view_position");
    }
    customViewRotationCenter = vector_subtract(customViewOffset, vector_multiply_scalar(customViewForwardVector, dot_product(customViewOffset, customViewForwardVector)));
    customViewDescription = StringForKey(viewDict, "view_description");

    const std::optional<std::string> facing = StringForKey(viewDict, "weapon_facing"); // nil compares unequal
    const std::string lowerFacing = facing.has_value() ? oo::str::lowercase(*facing) : std::string();
    if (facing.has_value() && lowerFacing == "aft") {
        currentWeaponFacing = WEAPON_FACING_AFT;
    } else if (facing.has_value() && lowerFacing == "port") {
        currentWeaponFacing = WEAPON_FACING_PORT;
    } else if (facing.has_value() && lowerFacing == "starboard") {
        currentWeaponFacing = WEAPON_FACING_STARBOARD;
    } else if (facing.has_value() && lowerFacing == "forward") {
        currentWeaponFacing = WEAPON_FACING_FORWARD;
    }
    // if the weapon facing is unset / unknown,
    // don't change current weapon facing!
}

- (BOOL)showInfoFlag
{
    return show_info_flag;
}

- (oo::PList)cxx_missionOverlayDescriptor
{
    return _missionOverlayDescriptor;
}

- (oo::PList)cxx_missionOverlayDescriptorOrDefault
{
    oo::PList result = [self cxx_missionOverlayDescriptor];
    if (result.isNull()) {
        if ([[self missionTitle] length] == 0) {
            result = oo::PListFrom([UNIVERSE screenTextureDescriptorForKey:@"mission_overlay_no_title"]);
        } else {
            result = oo::PListFrom([UNIVERSE screenTextureDescriptorForKey:@"mission_overlay_with_title"]);
        }
    }

    return result;
}

- (void)cxx_setMissionOverlayDescriptor:(const oo::PList&)descriptor
{
    _missionOverlayDescriptor = descriptor;
}

- (oo::PList)cxx_missionBackgroundDescriptor
{
    return _missionBackgroundDescriptor;
}

- (oo::PList)cxx_missionBackgroundDescriptorOrDefault
{
    oo::PList result = [self cxx_missionBackgroundDescriptor];
    if (result.isNull()) {
        result = oo::PListFrom([UNIVERSE screenTextureDescriptorForKey:@"mission"]);
    }

    return result;
}

- (void)cxx_setMissionBackgroundDescriptor:(const oo::PList&)descriptor
{
    _missionBackgroundDescriptor = descriptor;
}

- (OOGUIBackgroundSpecial)missionBackgroundSpecial
{
    return _missionBackgroundSpecial;
}

- (void)cxx_setMissionBackgroundSpecial:(const std::string&)special
{
    if (special.empty()) { // (nil, from the bridge)
        _missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_NONE;
    } else if (special == "SHORT_RANGE_CHART") {
        _missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_SHORT;
    } else if (special == "SHORT_RANGE_CHART_SHORTEST") {
        if ([self hasEquipmentItemProviding:@"EQ_ADVANCED_NAVIGATIONAL_ARRAY"]) {
            _missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_SHORT_ANA_SHORTEST;
        } else {
            _missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_SHORT;
        }
    } else if (special == "SHORT_RANGE_CHART_QUICKEST") {
        if ([self hasEquipmentItemProviding:@"EQ_ADVANCED_NAVIGATIONAL_ARRAY"]) {
            _missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_SHORT_ANA_QUICKEST;
        } else {
            _missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_SHORT;
        }
    } else if (special == "CUSTOM_CHART") {
        _missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_CUSTOM;
    } else if (special == "CUSTOM_CHART_SHORTEST") {
        if ([self hasEquipmentItemProviding:@"EQ_ADVANCED_NAVIGATIONAL_ARRAY"]) {
            _missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_SHORTEST;
        } else {
            _missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_CUSTOM;
        }
    } else if (special == "CUSTOM_CHART_QUICKEST") {
        if ([self hasEquipmentItemProviding:@"EQ_ADVANCED_NAVIGATIONAL_ARRAY"]) {
            _missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_QUICKEST;
        } else {
            _missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_CUSTOM;
        }
    } else if (special == "LONG_RANGE_CHART") {
        _missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_LONG;
    } else if (special == "LONG_RANGE_CHART_SHORTEST") {
        if ([self hasEquipmentItemProviding:@"EQ_ADVANCED_NAVIGATIONAL_ARRAY"]) {
            _missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_LONG_ANA_SHORTEST;
        } else {
            _missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_LONG;
        }
    } else if (special == "LONG_RANGE_CHART_QUICKEST") {
        if ([self hasEquipmentItemProviding:@"EQ_ADVANCED_NAVIGATIONAL_ARRAY"]) {
            _missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_LONG_ANA_QUICKEST;
        } else {
            _missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_LONG;
        }
    } else {
        _missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_NONE;
    }
}

- (void)setMissionExitScreen:(OOGUIScreenID)screen
{
    _missionExitScreen = screen;
}

- (OOGUIScreenID)missionExitScreen
{
    return _missionExitScreen;
}

- (oo::PList)cxx_equipScreenBackgroundDescriptor
{
    return _equipScreenBackgroundDescriptor;
}

- (void)cxx_setEquipScreenBackgroundDescriptor:(const oo::PList&)descriptor
{
    _equipScreenBackgroundDescriptor = descriptor;
}

- (BOOL)scriptsLoaded
{
    return worldScripts != nil && [worldScripts count] > 0;
}

- (NSArray*)worldScriptNames
{
    return [worldScripts allKeys];
}

- (NSDictionary*)worldScriptsByName
{
    return [[worldScripts copy] autorelease];
}

- (OOScript*)commodityScriptNamed:(NSString*)scriptName
{
    if (scriptName == nil) {
        return nil;
    }
    OOScript* cscript = nil;
    if ((cscript = [commodityScripts objectForKey:scriptName])) {
        return cscript;
    }
    cscript = [OOScript jsScriptFromFileNamed:scriptName properties:nil];
    if (cscript != nil) {
        // storing it in here retains it
        [commodityScripts setObject:cscript forKey:scriptName];
    } else {
        OO_LOG("script.commodityScript.load", "Could not load script {}", oo::DescriptionOf(scriptName));
    }
    return cscript;
}

- (void)doScriptEvent:(OOJSPropID)message inContext:(JSContext*)context withArguments:(OOJSVal*)argv count:(int)argc
{
    [super doScriptEvent:message inContext:context withArguments:argv count:argc];
    [self doWorldScriptEvent:message inContext:context withArguments:argv count:argc timeLimit:0.0];
}

- (BOOL)doWorldEventUntilMissionScreen:(OOJSPropID)message
{
    NSEnumerator* scriptEnum = [worldScripts objectEnumerator];
    OOScript* theScript;

    // Check for the presence of report messages first.
    if (gui_screen != GUI_SCREEN_MISSION && !dockingReport.empty() && [self isDocked] && ![[self dockedStation] suppressArrivalReports]) {
        [self setGuiToDockingReportScreen]; // go here instead!
        [[UNIVERSE messageGUI] clear];
        return YES;
    }

    JSContext* context = OOJSAcquireContext();
    while ((theScript = [scriptEnum nextObject]) && gui_screen != GUI_SCREEN_MISSION && [self isDocked]) {
        [theScript callMethod:message inContext:context withArguments:NULL count:0 result:NULL];
    }
    OOJSRelinquishContext(context);

    if (gui_screen == GUI_SCREEN_MISSION) {
        // remove any comms/console messages from the screen!
        [[UNIVERSE messageGUI] clear];
        return YES;
    }

    return NO;
}

- (void)doWorldScriptEvent:(OOJSPropID)message inContext:(JSContext*)context withArguments:(OOJSVal*)argv count:(int)argc timeLimit:(OOTimeDelta)limit
{
    NSParameterAssert(context != NULL);

    OOScript* theScript = nil;

    foreach (theScript, [worldScripts allValues]) {
        OOJSStartTimeLimiterWithTimeLimit(limit);
        [theScript callMethod:message inContext:context withArguments:argv count:argc result:NULL];
        OOJSStopTimeLimiter();
    }
}

- (void)setGalacticHyperspaceBehaviour:(OOGalacticHyperspaceBehaviour)inBehaviour
{
    if (GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN < inBehaviour && inBehaviour <= GALACTIC_HYPERSPACE_MAX) {
        galacticHyperspaceBehaviour = inBehaviour;
    }
}

- (OOGalacticHyperspaceBehaviour)galacticHyperspaceBehaviour
{
    return galacticHyperspaceBehaviour;
}

- (void)setGalacticHyperspaceFixedCoords:(NSPoint)point
{
    return [self setGalacticHyperspaceFixedCoordsX:OOClamp_0_max_f(round(point.x), 255.0f) y:OOClamp_0_max_f(round(point.y), 255.0f)];
}

- (void)setGalacticHyperspaceFixedCoordsX:(unsigned char)x y:(unsigned char)y
{
    galacticHyperspaceFixedCoords.x = x;
    galacticHyperspaceFixedCoords.y = y;
}

- (NSPoint)galacticHyperspaceFixedCoords
{
    return galacticHyperspaceFixedCoords;
}

- (void)setWitchspaceCountdown:(int)spin_time
{
    witchspaceCountdown = spin_time;
}

- (OOLongRangeChartMode)longRangeChartMode
{
    return longRangeChartMode;
}

- (void)setLongRangeChartMode:(OOLongRangeChartMode)mode
{
    longRangeChartMode = mode;
}

- (BOOL)scoopOverride
{
    return scoopOverride;
}

- (void)setScoopOverride:(BOOL)newValue
{
    scoopOverride = !!newValue;
    if (scoopOverride)
        [self setScoopsActive];
}

#if MASS_DEPENDENT_FUEL_PRICES
- (GLfloat)fuelChargeRate
{
    GLfloat rate = 1.0; // Standard charge rate.

    rate = [super fuelChargeRate];

    // Experimental: the state of repair affects the fuel charge rate - more fuel needed for jumps, etc...
    if (EXPECT(ship_trade_in_factor <= 90 && ship_trade_in_factor >= 75)) {
        rate *= 2.0 - (ship_trade_in_factor / 100); // between 1.1x and 1.25x
        // fuelPrices: shipDataKey repair status ship_trade_in_factor rate (retired log)
    }

    return rate;
}
#endif

- (void)setDockTarget:(ShipEntity*)entity
{
    if ([entity isStation])
        _dockTarget = [entity universalID];
    else
        _dockTarget = NO_TARGET;
    //_dockTarget = [entity isStation] ? [entity universalID]: NO_TARGET;
}

- (std::optional<std::string>)cxx_jumpCause
{
    return _jumpCause;
}

- (void)cxx_setJumpCause:(const std::optional<std::string>&)value
{
    NSParameterAssert(value.has_value());
    _jumpCause = value;
}

- (std::optional<std::string>)cxx_commanderName
{
    return _commanderName;
}

- (std::optional<std::string>)cxx_lastsaveName
{
    return _lastsaveName;
}

- (void)cxx_setCommanderName:(const std::optional<std::string>&)value
{
    NSParameterAssert(value.has_value());
    _commanderName = value;
}

- (void)cxx_setLastsaveName:(const std::optional<std::string>&)value
{
    NSParameterAssert(value.has_value());
    _lastsaveName = value;
    oo::Defaults::standard().setObject("last_savename", _lastsaveName.has_value() ? oo::PList(*_lastsaveName) : oo::PList());
}

- (BOOL)isDocked
{
    BOOL isDockedStatus = NO;

    switch ([self status]) {
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
        // no default, so that we get notified by the compiler if something is missing
    }

#ifndef NDEBUG
    // Sanity check
    if (isDockedStatus) {
        if ([self dockedStation] == nil) {
            // there are a number of possible current statuses, not just STATUS_DOCKED
            OO_LOG_ERR(cxx_kOOLogInconsistentState, "status is {}, but dockedStation is nil; treating as not docked. {}", cxx_OOStringFromEntityStatus([self status]), "This is an internal error, please report it.");
            [self setStatus:STATUS_IN_FLIGHT];
            isDockedStatus = NO;
        }
    } else {
        if ([self dockedStation] != nil && [self status] != STATUS_LAUNCHING) {
            OO_LOG_ERR(cxx_kOOLogInconsistentState, "status is {}, but dockedStation is not nil; treating as docked. {}", cxx_OOStringFromEntityStatus([self status]), "This is an internal error, please report it.");
            [self setStatus:STATUS_DOCKED];
            isDockedStatus = YES;
        }
    }
#endif

    return isDockedStatus;
}

- (BOOL)clearedToDock
{
    return dockingClearanceStatus > DOCKING_CLEARANCE_STATUS_REQUESTED || dockingClearanceStatus == DOCKING_CLEARANCE_STATUS_NOT_REQUIRED;
}

- (void)setDockingClearanceStatus:(OODockingClearanceStatus)newValue
{
    dockingClearanceStatus = newValue;
    if (dockingClearanceStatus == DOCKING_CLEARANCE_STATUS_NONE) {
        targetDockStation = nil;
    } else if (dockingClearanceStatus == DOCKING_CLEARANCE_STATUS_REQUESTED || dockingClearanceStatus == DOCKING_CLEARANCE_STATUS_NOT_REQUIRED) {
        if ([[self primaryTarget] isStation]) {
            targetDockStation = [self primaryTarget];
        } else {
            OO_LOG("player.badDockingTarget", "Attempt to dock at {}.", oo::DescriptionOf([self primaryTarget]));
            targetDockStation = nil;
            dockingClearanceStatus = DOCKING_CLEARANCE_STATUS_NONE;
        }
    }
}

- (OODockingClearanceStatus)getDockingClearanceStatus
{
    return dockingClearanceStatus;
}

- (void)penaltyForUnauthorizedDocking
{
    OOCreditsQuantity amountToPay = 0;
    OOCreditsQuantity calculatedFine = credits * 0.05;
    OOCreditsQuantity maximumFine = 50000ULL;

    if ([self clearedToDock])
        return;

    amountToPay = MIN(maximumFine, calculatedFine);
    credits -= amountToPay;
    [self cxx_addMessageToReport:oo::str::formatRuntime(oo::StdString(DESC(@"station-docking-clearance-fined-@-cr")), { cxx_OOCredits(amountToPay) })];
}

//
// Wormhole Scanner support functions
//
- (void)addScannedWormhole:(WormholeEntity*)whole
{
    assert(whole != nil);

    // Only add if we don't have it already!
    for (const oo::ObjCRef<WormholeEntity*>& wh : scannedWormholes) {
        if (wh.get() == whole)
            return;
    }
    [whole setScannedAt:[self clockTimeAdjusted]];
    scannedWormholes.push_back(oo::ObjCRef<WormholeEntity*>(whole));
}

// Checks through our array of wormholes for any which have expired
// If it is in the current system, spawn ships
// Else remove it
- (void)updateWormholes
{
    if (scannedWormholes.empty())
        return;

    double now = [self clockTimeAdjusted];

    std::vector<oo::ObjCRef<WormholeEntity*>> savedWormholes;
    savedWormholes.reserve(scannedWormholes.size());

    for (const oo::ObjCRef<WormholeEntity*>& whRef : scannedWormholes) {
        WormholeEntity* wh = whRef.get();
        // TODO: Start drawing wormhole exit a few seconds before the first
        //       ship is disgorged.
        if ([wh arrivalTime] > now) {
            savedWormholes.push_back(whRef);
        } else if (NSEqualPoints(galaxy_coordinates, [wh destinationCoordinates])) {
            [wh disgorgeShips];
            if ([wh shipsInTransit].count() > 0) {
                savedWormholes.push_back(whRef);
            }
        }
        // Else wormhole has expired in another system, let it expire
    }

    scannedWormholes = std::move(savedWormholes);
}

- (std::vector<oo::ObjCRef<WormholeEntity*>>)cxx_scannedWormholes
{
    return scannedWormholes;
}

- (void)initialiseMissionDestinations:(const oo::PList&)destinations andLegacy:(const oo::PList&)legacy
{
    missionDestinations.clear();

    // the dictionary entries that are themselves dictionaries
    if (const oo::PList::Dict* entries = destinations.getIf<oo::PList::Dict>()) {
        for (const auto& [key, value] : *entries) {
            if (value.isDict()) {
                missionDestinations.insert_or_assign(key, value);
            }
        }
    }

    if (legacy.isArray()) {
        OOSystemID dest;
        for (size_t legacyMarker = 0; legacyMarker < legacy.count(); legacyMarker++) {
            dest = legacy.at<int>(legacyMarker); // -intValue
            [self cxx_addMissionDestinationMarker:[self cxx_defaultMarker:dest]];
        }
    }
}

- (std::optional<std::string>)markerKey:(const oo::PList&)marker
{
    // "%d-%@": a missing (or non-string) name reads "(null)"
    const oo::PList* markerName = marker.find("name");
    const std::string* nameText = (markerName != nullptr) ? markerName->getIf<std::string>() : nullptr;
    return oo::str::format("%d-%s", marker.get<int>("system", 0), (nameText != nullptr) ? nameText->c_str() : "(null)");
}

- (void)cxx_addMissionDestinationMarker:(const oo::PList&)marker
{
    const oo::PList validated = [self cxx_validatedMarker:marker];
    if (validated.isNull()) {
        return;
    }

    missionDestinations.insert_or_assign(*[self markerKey:validated], validated);
}

- (BOOL)cxx_removeMissionDestinationMarker:(const oo::PList&)marker
{
    const oo::PList validated = [self cxx_validatedMarker:marker];
    if (validated.isNull()) {
        return NO;
    }
    // YES if there was one to remove
    return missionDestinations.erase(*[self markerKey:validated]) > 0 ? YES : NO;
}

- (oo::PList)cxx_getMissionDestinations
{
    return oo::PList(missionDestinations); // a snapshot
}

- (oo::PList::Dict*)cxx_shipyardRecord
{
    return &shipyard_record;
}

- (void)cxx_setLastShot:(const std::vector<oo::ObjCRef<OOLaserShotEntity*>>&)shot
{
    lastShot = shot;
}

- (void)clearExtraMissionKeys
{
    extraMissionKeys.clear();
}

- (void)cxx_setExtraMissionKeys:(const oo::PList&)keys
{
    std::map<std::string, oo::PList, std::less<>> final;
    if (const oo::PList::Dict* keyDict = keys.getIf<oo::PList::Dict>()) {
        for (const auto& [key, value] : *keyDict) {
            final[key] = [self cxx_processKeyCode:(value.isArray() ? value : oo::PList())]; // oo_arrayForKey:
        }
    }
    extraMissionKeys = std::move(final);
}

- (void)cxx_clearExtraGuiScreenKeys:(OOGUIScreenID)gui key:(const std::string&)key
{
    const auto screenKeys = extraGuiScreenKeys.find(gui);
    if (screenKeys == extraGuiScreenKeys.end())
        return;
    std::vector<oo::ObjCRef<OOJSGuiScreenKeyDefinition*>>& keydefs = screenKeys->second;
    std::size_t i = keydefs.size();
    while (i--) {
        OOJSGuiScreenKeyDefinition* def = keydefs[i].get();
        // the old code read "name" from the definition object with PListView, which only reads
        // dictionaries, so this never matched; kept as it was (oo::PListFrom(def) is an Object node)
        const oo::PList definitionValue = oo::PListFrom(def);
        const oo::PList* definitionName = definitionValue.find("name");
        if (def && definitionName != nullptr && definitionName->isString() && *definitionName->getIf<std::string>() == key) {
            keydefs.erase(keydefs.begin() + static_cast<std::ptrdiff_t>(i));
            break;
        }
    }
}

- (BOOL)setExtraGuiScreenKeys:(OOGUIScreenID)gui definition:(OOJSGuiScreenKeyDefinition*)definition
{
    // process all the keys in the definition
    BOOL result = YES;
    oo::PList::Dict final;
    const oo::PList keys = [definition registerKeys];
    std::vector<oo::PList> checklist;

    if (const oo::PList::Dict* keyDict = keys.getIf<oo::PList::Dict>()) {
        for (const auto& [key, value] : *keyDict) {
            oo::PList item = [self cxx_processKeyCode:(value.isArray() ? value : oo::PList())]; // oo_arrayForKey:
            checklist.push_back(item);
            final[key] = std::move(item);
        }
    }
    [definition setRegisterKeys:oo::PList(std::move(final))];

    std::vector<oo::ObjCRef<OOJSGuiScreenKeyDefinition*>> newarray;
    const auto existing = extraGuiScreenKeys.find(gui);
    if (existing != extraGuiScreenKeys.end()) {
        newarray = existing->second;
        std::size_t i = newarray.size();
        while (i--) {
            OOJSGuiScreenKeyDefinition* def_existing = newarray[i].get();
            // if we find this name already in the array, remove it
            if (def_existing && [[def_existing name] isEqualToString:[definition name]]) {
                newarray.erase(newarray.begin() + static_cast<std::ptrdiff_t>(i));
            } else {
                // check whether any of those keycodes is already in use on this screen
                const oo::PList keydefs = [def_existing registerKeys];
                const oo::PList::Dict* keydefsDict = keydefs.getIf<oo::PList::Dict>();

                for (const auto& [key, keydef] : (keydefsDict != nullptr) ? *keydefsDict : oo::PList::Dict()) // byte order (was -allKeys order): only the log order can differ
                {
                    std::size_t j = checklist.size();
                    while (j--) {
                        // the "%@" texts of the two key-code arrays
                        if (oo::DescriptionOf(oo::ObjectFromPList(keydef)) == oo::DescriptionOf(oo::ObjectFromPList(checklist[j]))) {
                            result = NO;
                            OO_LOG(cxx_kOOLogException, "***** Exception in setExtraGuiScreenKeys: {} : {} ({})", "invalid key settings", "key already in use", key);
                        }
                    }
                }
            }
        }
    }
    newarray.push_back(oo::ObjCRef<OOJSGuiScreenKeyDefinition*>(definition));
    // only add the item if there were no errors
    if (result)
        extraGuiScreenKeys[gui] = std::move(newarray);
    return result;
}

#ifdef OO_DEBUG_MONITOR_ENABLED
- (void)dumpSelfState
{
    std::vector<std::string> flags;
    std::string flagsString;

    [super dumpSelfState];

    OO_LOG("dumpState.playerEntity", "Script time: {:g}", script_time);
    OO_LOG("dumpState.playerEntity", "Script time check: {:g}", script_time_check);
    OO_LOG("dumpState.playerEntity", "Script time interval: {:g}", script_time_interval);
    OO_LOG("dumpState.playerEntity", "Roll/pitch/yaw delta: {:g}, {:g}, {:g}", roll_delta, pitch_delta, yaw_delta);
    OO_LOG("dumpState.playerEntity", "Shield: {:g} fore, {:g} aft", forward_shield, aft_shield);
    OO_LOG("dumpState.playerEntity", "Alert level: {}, flags: {:#x}", static_cast<unsigned>(alertFlags), static_cast<unsigned>(alertCondition));
    OO_LOG("dumpState.playerEntity", "Missile status: {}", static_cast<unsigned>(missile_status));
    OO_LOG("dumpState.playerEntity", "Energy unit: {}", cxx_EnergyUnitTypeToString([self installedEnergyUnitType]));
    OO_LOG("dumpState.playerEntity", "Fuel leak rate: {:g}", fuel_leak_rate);
    OO_LOG("dumpState.playerEntity", "Trumble count: {}", trumbleCount);

#define ADD_FLAG_IF_SET(x)   \
    if (x) {                 \
        flags.push_back(#x); \
    }
    ADD_FLAG_IF_SET(found_equipment);
    ADD_FLAG_IF_SET(pollControls);
    ADD_FLAG_IF_SET(suppressTargetLost);
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
    ADD_FLAG_IF_SET(keyboardRollOverride); // Handle keyboard roll...
    ADD_FLAG_IF_SET(keyboardPitchOverride); // ...and pitch override separately - (fix for BUG #17490)
    ADD_FLAG_IF_SET(keyboardYawOverride);
    ADD_FLAG_IF_SET(waitingForStickCallback);
    for (const std::string& flag : flags)
        flagsString += (flagsString.empty() ? "" : ", ") + flag;
    if (flags.empty())
        flagsString = "none";
    OO_LOG("dumpState.playerEntity", "Flags: {}", flagsString);
}

/*	This method exists purely to suppress Clang static analyzer warnings that
        these ivars are unused (but may be used by categories, which they are).
        FIXME: there must be a feature macro we can use to avoid actually building
        this into the app, but I can't find it in docs.

        Mind you, we could suppress some of this by using civilized accessors.
*/
- (BOOL)suppressClangStuff
{
    return missionChoice.has_value() && !commanderNameString.empty() && !cdrDetailArray.empty() && currentPage && n_key_roll_left && n_key_roll_right && n_key_pitch_forward && n_key_pitch_back && n_key_yaw_left && n_key_yaw_right && n_key_view_forward && n_key_view_aft && n_key_view_port && n_key_view_starboard && n_key_launch_ship && n_key_gui_screen_options && n_key_gui_screen_equipship && n_key_gui_screen_interfaces && n_key_gui_screen_status && n_key_gui_chart_screens && n_key_gui_system_data && n_key_gui_market && n_key_gui_arrow_left && n_key_gui_arrow_right && n_key_gui_arrow_up && n_key_gui_arrow_down && n_key_gui_page_up && n_key_gui_page_down && n_key_gui_select && n_key_increase_speed && n_key_decrease_speed && n_key_inject_fuel && n_key_fire_lasers && n_key_launch_missile && n_key_next_missile && n_key_ecm && n_key_prime_next_equipment && n_key_prime_previous_equipment && n_key_activate_equipment && n_key_mode_equipment && n_key_fastactivate_equipment_a && n_key_fastactivate_equipment_b && n_key_target_missile && n_key_untarget_missile && n_key_target_incoming_missile && n_key_ident_system && n_key_scanner_zoom && n_key_scanner_unzoom && n_key_launch_escapepod && n_key_galactic_hyperspace && n_key_hyperspace && n_key_jumpdrive && n_key_dump_cargo && n_key_rotate_cargo && n_key_autopilot && n_key_autodock && n_key_snapshot && n_key_docking_music && n_key_advanced_nav_array_next && n_key_advanced_nav_array_previous && n_key_info_next_system && n_key_info_previous_system && n_key_map_home && n_key_map_end && n_key_map_next_system && n_key_map_previous_system && n_key_map_info && n_key_map_zoom_in && n_key_map_zoom_out && n_key_system_home && n_key_system_end && n_key_system_next_system && n_key_system_previous_system && n_key_pausebutton && n_key_show_fps && n_key_bloom_toggle && n_key_mouse_control_roll && n_key_mouse_control_yaw && n_key_hud_toggle && n_key_comms_log && n_key_prev_compass_mode && n_key_next_compass_mode && n_key_chart_highlight && n_key_market_filter_cycle && n_key_market_sorter_cycle && n_key_market_buy_one && n_key_market_sell_one && n_key_market_buy_max && n_key_market_sell_max && n_key_next_target && n_key_previous_target && n_key_custom_view && n_key_custom_view_zoom_out && n_key_custom_view_zoom_in && n_key_custom_view_roll_left && n_key_custom_view_pan_left && n_key_custom_view_roll_right && n_key_custom_view_pan_right && n_key_custom_view_rotate_up && n_key_custom_view_pan_up && n_key_custom_view_rotate_down && n_key_custom_view_pan_down && n_key_custom_view_rotate_left && n_key_custom_view_rotate_right && n_key_docking_clearance_request && n_key_weapons_online_toggle && n_key_cycle_next_mfd && n_key_cycle_previous_mfd && n_key_switch_next_mfd && n_key_switch_previous_mfd && n_key_oxzmanager_setfilter && n_key_oxzmanager_showinfo && n_key_oxzmanager_copyurl && n_key_oxzmanager_extract &&
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
        n_key_inc_field_of_view && n_key_dec_field_of_view &&
#endif
        n_key_dump_target_state && n_key_dump_entity_list && n_key_debug_full && n_key_debug_collision && n_key_debug_console_connect && n_key_debug_bounding_boxes && n_key_debug_shaders && n_key_debug_off && _sysInfoLight.x && selFunctionIdx && !stickFunctions.empty() && !keyFunctions.empty() && !customEquipActivation.empty() && !customActivatePressed.empty() && !customModePressed.empty() && !kbdLayouts.empty() && showingLongRangeChart && _missionAllowInterrupt && _missionScreenID.has_value() && _missionTitle.has_value() && _missionTextEntry;
}
#endif

@end
