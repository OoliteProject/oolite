/*

OOEquipmentType.m


Copyright (C) 2008-2013 Jens Ayton and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOEquipmentType.h"
#import "OOCacheManager.h"
#import "OODebugStandards.h"
#import "OOFoundationBridge.h"
#import "OOLegacyScriptWhitelist.h"
#import "PlayerEntityControls.h"
#import "PlayerEntityKeyMapper.h"
#import "Universe.h"
#include "oofnd/String.hpp"

#include <algorithm>

namespace {
std::vector<oo::ObjCRef<OOEquipmentType*>> sEquipmentTypes;
std::vector<oo::ObjCRef<OOEquipmentType*>> sEquipmentTypesOutfitting;
std::map<std::string, oo::ObjCRef<OOEquipmentType*>, std::less<>> sEquipmentTypesByIdentifier;
std::map<std::string, std::string, std::less<>> sMissilesRegistry; // ship key -> missile role

// requires_equipment & co.: a string or an array of strings (sorted, de-duplicated: was a
// set); nullopt when absent, and after logging when it is anything else.
// oo_stringForKey:defaultValue: on a dictionary: a string, or a number's -stringValue, else the
// fallback.
std::optional<std::string> StringFor(const oo::PList& info, std::string_view key, const std::optional<std::string>& fallback = std::nullopt)
{
    const oo::PList* value = info.find(key);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return fallback;
    return info.get<std::string>(key);
}

// oo_stringAtIndex: on an array: a string, or a number's -stringValue; nullopt (nil) otherwise.
std::optional<std::string> StringAt(const oo::PList& array, std::size_t index)
{
    const oo::PList* value = array.at(index);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return array.at<std::string>(index);
}

// The items of -[UNIVERSE cxx_equipmentData] & co. (enumerating a non-array found none, as nil did).
std::vector<oo::PList> EquipmentItems(const oo::PList& equipmentData)
{
    std::vector<oo::PList> items;
    if (const oo::PList::Array* elements = equipmentData.getIf<oo::PList::Array>())
        items.assign(elements->begin(), elements->end());
    return items;
}

std::optional<std::vector<std::string>> EquipmentKeysFrom(const oo::PList& extra, const char* key, const std::string& identifier)
{
    const oo::PList* value = extra.find(key);
    if (value == nullptr)
        return std::nullopt;
    std::vector<std::string> keys;
    if (const std::string* text = value->getIf<std::string>()) {
        keys.push_back(*text);
    } else if (const oo::PList::Array* elements = value->getIf<oo::PList::Array>()) {
        for (const oo::PList& element : *elements) {
            if (const std::string* elementText = element.getIf<std::string>())
                keys.push_back(*elementText);
        }
        std::sort(keys.begin(), keys.end());
        keys.erase(std::unique(keys.begin(), keys.end()), keys.end());
    } else {
        OO_LOG("equipment.load", "***** ERROR: {} for equipment item {} is not a string or an array.", key, identifier);
        return std::nullopt;
    }
    return keys;
}
}

@interface OOEquipmentType (Private)

- (id)initWithInfo:(const oo::PList&)info; // an equipment.plist entry (an array)

@end

@implementation OOEquipmentType

+ (void)loadEquipment
{
    std::vector<oo::ObjCRef<OOEquipmentType*>> equipmentTypes;
    std::vector<std::string> conditionScripts; // first-seen order
    std::map<std::string, oo::ObjCRef<OOEquipmentType*>, std::less<>> byIdentifier;

    for (const oo::PList& itemInfo : EquipmentItems([UNIVERSE cxx_equipmentData])) {
        OOEquipmentType* item = [[[OOEquipmentType alloc] initWithInfo:itemInfo] autorelease];
        if (item != nil) {
            equipmentTypes.emplace_back(item);
            byIdentifier[*[item cxx_identifier]] = oo::ObjCRef<OOEquipmentType*>(item);
        }
        const std::optional<std::string> condition_script = [item cxx_conditionScript];
        if (condition_script.has_value()) {
            if (std::find(conditionScripts.begin(), conditionScripts.end(), *condition_script) == conditionScripts.end()) {
                conditionScripts.push_back(*condition_script);
            }
        }
    }

    [[OOCacheManager sharedCache] cxx_setObject:oo::NSArrayFromStrings(conditionScripts) forKey:"equipment conditions" inCache:"condition scripts"];

    sEquipmentTypes = equipmentTypes;
    sEquipmentTypesByIdentifier = byIdentifier;

    // same for the outfitting dataset
    equipmentTypes.clear();
    for (const oo::PList& itemInfo : EquipmentItems([UNIVERSE cxx_equipmentDataOutfitting])) {
        OOEquipmentType* item = [[[OOEquipmentType alloc] initWithInfo:itemInfo] autorelease];
        if (item != nil) {
            equipmentTypes.emplace_back(item);
        }
    }
    sEquipmentTypesOutfitting = equipmentTypes;
}

+ (void)cxx_addEquipmentWithInfo:(const oo::PList&)itemInfo
{
    OOEquipmentType* item = [[[OOEquipmentType alloc] initWithInfo:itemInfo] autorelease];
    if (item != nil) {
        sEquipmentTypes.emplace_back(item);
        sEquipmentTypesOutfitting.emplace_back(item);
        sEquipmentTypesByIdentifier[*[item cxx_identifier]] = oo::ObjCRef<OOEquipmentType*>(item);
    }
}

+ (std::optional<std::string>)cxx_getMissileRegistryRoleForShip:(const std::string&)shipKey
{
    const auto entry = sMissilesRegistry.find(shipKey);
    if (entry == sMissilesRegistry.end())
        return std::nullopt;
    return entry->second;
}

+ (void)cxx_setMissileRegistryRole:(const std::string&)role forShip:(const std::string&)shipKey
{
    // (the nil checks on role and ship key are the bridge's; the empty key is still refused here)
    if (!shipKey.empty()) {
        sMissilesRegistry[shipKey] = role;
    }
}

+ (std::vector<oo::ObjCRef<OOEquipmentType*>>)cxx_allEquipmentTypes
{
    return sEquipmentTypes;
}

+ (std::vector<oo::ObjCRef<OOEquipmentType*>>)cxx_allEquipmentTypesOutfitting
{
    return sEquipmentTypesOutfitting;
}

+ (OOEquipmentType*)cxx_equipmentTypeWithIdentifier:(const std::string&)identifier
{
    const auto entry = sEquipmentTypesByIdentifier.find(identifier);
    return (entry != sEquipmentTypesByIdentifier.end()) ? entry->second.get() : nil;
}

- (id)initWithInfo:(const oo::PList&)info
{
    BOOL OK = YES;

    self = [super init];
    if (self == nil)
        OK = NO;

    if (OK && info.count() <= EQUIPMENT_LONG_DESC_INDEX)
        OK = NO;

    if (OK) {
        // Read required attributes
        _techLevel = info.at<unsigned int>(EQUIPMENT_TECH_LEVEL_INDEX);
        _price = info.at<unsigned int>(EQUIPMENT_PRICE_INDEX);
        const std::optional<std::string> name = StringAt(info, EQUIPMENT_SHORT_DESC_INDEX);
        const std::optional<std::string> identifier = StringAt(info, EQUIPMENT_KEY_INDEX);
        const std::optional<std::string> description = StringAt(info, EQUIPMENT_LONG_DESC_INDEX);

        if (!name.has_value() || !identifier.has_value() || !description.has_value()) {
            OO_LOG("equipment.load", "***** ERROR: Invalid equipment.plist entry - missing name, identifier or description (\"{}\", {}, \"{}\")", name.value_or("(null)"), identifier.value_or("(null)"), description.value_or("(null)"));
            OK = NO;
        } else {
            _name = *name;
            _identifier = *identifier;
            _description = *description;
        }
    }

    if (OK) {
        // Implied attributes for backwards-compatibility
        if (oo::str::hasSuffix(_identifier, "_MISSILE") || oo::str::hasSuffix(_identifier, "_MINE")) {
            _isMissileOrMine = YES;
            _requiresEmptyPylon = YES;
        } else if (_identifier == "EQ_PASSENGER_BERTH_REMOVAL") {
            _requiresFreePassengerBerth = YES;
        } else if (_identifier == "EQ_FUEL") {
            _requiresNonFullFuel = YES;
        }
        _isVisible = YES;
        _isAvailableToPlayer = YES;
        _isAvailableToNPCs = YES;
        _damageProbability = 1.0;
        _hideValues = NO;
    }

    if (OK && info.count() > EQUIPMENT_EXTRA_INFO_INDEX) {
        // Read extra info dictionary
        const oo::PList* extra = info.at<oo::PList::Dict>(EQUIPMENT_EXTRA_INFO_INDEX);
        if (extra != nullptr) {
            const oo::PList& extraInfo = *extra;

            _isAvailableToAll = (unsigned char)extraInfo.get<bool>("available_to_all", _isAvailableToAll);
            _isAvailableToPlayer = (unsigned char)extraInfo.get<bool>("available_to_player", _isAvailableToPlayer);
            _isAvailableToNPCs = (unsigned char)extraInfo.get<bool>("available_to_NPCs", _isAvailableToNPCs);

            _isMissileOrMine = (unsigned char)extraInfo.get<bool>("is_external_store", _isMissileOrMine);
            _requiresEmptyPylon = (unsigned char)extraInfo.get<bool>("requires_empty_pylon", _requiresEmptyPylon);
            _requiresMountedPylon = (unsigned char)extraInfo.get<bool>("requires_mounted_pylon", _requiresMountedPylon);
            _requiresClean = (unsigned char)extraInfo.get<bool>("requires_clean", _requiresClean);
            _requiresNotClean = (unsigned char)extraInfo.get<bool>("requires_not_clean", _requiresNotClean);
            _portableBetweenShips = (unsigned char)extraInfo.get<bool>("portable_between_ships", _portableBetweenShips);
            _requiresFreePassengerBerth = (unsigned char)extraInfo.get<bool>("requires_free_passenger_berth", _requiresFreePassengerBerth);
            _requiresFullFuel = (unsigned char)extraInfo.get<bool>("requires_full_fuel", _requiresFullFuel);
            _requiresNonFullFuel = (unsigned char)extraInfo.get<bool>("requires_non_full_fuel", _requiresNonFullFuel);
            _isVisible = (unsigned char)extraInfo.get<bool>("visible", _isVisible);
            _canCarryMultiple = (unsigned char)extraInfo.get<bool>("can_carry_multiple", false);
            _hideValues = (unsigned char)extraInfo.get<bool>("hide_values", false);

            _requiredCargoSpace = extraInfo.get<unsigned int>("requires_cargo_space", _requiredCargoSpace);

            _installTime = extraInfo.get<unsigned int>("installation_time", 0);
            _repairTime = extraInfo.get<unsigned int>("repair_time", 0);
            if (const oo::PList* provides = extraInfo.get<oo::PList::Array>("provides")) {
                for (const oo::PList& element : *provides->getIf<oo::PList::Array>()) {
                    if (const std::string* text = element.getIf<std::string>())
                        _provides.push_back(*text);
                }
            }

            // +colorWithDescription: is not migrated: the node crosses as the object it was.
            const oo::PList* dispColor = extraInfo.find("display_color");
            _displayColor = [[OOColor colorWithDescription:(dispColor != nullptr) ? oo::ObjectFromPList(*dispColor) : nil] retain];

            const oo::PList* weaponInfo = extraInfo.get<oo::PList::Dict>("weapon_info");
            _weaponInfo = (weaponInfo != nullptr) ? *weaponInfo : oo::PList(oo::PList::Dict { });

            _damageProbability = extraInfo.get<float>("damage_probability", (_isMissileOrMine ? 0.0 : 1.0));

            _requiresEquipment = EquipmentKeysFrom(extraInfo, "requires_equipment", _identifier);
            _requiresAnyEquipment = EquipmentKeysFrom(extraInfo, "requires_any_equipment", _identifier);
            _incompatibleEquipment = EquipmentKeysFrom(extraInfo, "incompatible_with_equipment", _identifier);

            oo::PList legacyConditions;
            const oo::PList* value = extraInfo.find("conditions");
            if (value != nullptr && value->isString())
                legacyConditions = oo::PList(oo::PList::Array { *value });
            else if (value != nullptr && value->isArray())
                legacyConditions = *value;
            else if (value != nullptr) {
                OO_LOG("equipment.load", "***** ERROR: {} for equipment item {} is not a string or an array.", "conditions", _identifier);
            }
            if (legacyConditions) {
                cxx_OOStandardsDeprecated(oo::str::format("The conditions key is deprecated for equipment %s", _name.c_str()));
                if (!OOEnforceStandards()) {
                    _conditions = OOSanitizeLegacyScriptConditions(legacyConditions, oo::str::format("<equipment type \"%s\">", _name.c_str()));
                }
            }

            value = extraInfo.find("condition_script");
            if (value != nullptr && value->isString()) {
                _condition_script = *value->getIf<std::string>();
            } else if (value != nullptr) {
                OO_LOG("equipment.load", "***** ERROR: {} for equipment item {} is not a string.", "condition_script", _identifier);
            }
            /* Condition scripts are shared: all equipment/ships using the
             * same condition script use one shared instance. Equipment
             * scripts and ship scripts are not shared and get one instance
             * per item. */

            if (const oo::PList* scriptInfo = extraInfo.get<oo::PList::Dict>("script_info"))
                _scriptInfo = *scriptInfo;

            _script = StringFor(extraInfo, "script");
            if (_script.has_value() && ![OOScript cxx_jsScriptFromFileNamed:*_script properties:oo::PList()])
                _script.reset();
            if (_script.has_value()) {
                _fastAffinityA = !!extraInfo.get<bool>("fast_affinity_defensive");
                _fastAffinityB = !!extraInfo.get<bool>("fast_affinity_offensive");

                // look for default activate and mode key settings
                // note: the customEquipmentActivation array is only populated when starting a game
                // so the application of any default key settings on equipment will only happen then
                for (const bool activate : { true, false }) {
                    const char* keyName = activate ? "default_activate_key" : "default_mode_key";
                    oo::PList& defaultKey = activate ? _defaultActivateKey : _defaultModeKey;

                    const oo::PList* keydef = extraInfo.find(keyName);
                    if (keydef != nullptr && !keydef->isArray()) {
                        OO_LOG("equipment.load", "***** ERROR: {} for equipment item {} is not an array.", keyName, _identifier);
                        keydef = nullptr;
                    }

                    if (keydef != nullptr) {
                        // do processing for key
                        defaultKey = [PLAYER cxx_processKeyCode:*keydef];
                        const std::optional<std::string> checking = [PLAYER validateKey:(activate ? "activate_" : "mode_") + _identifier checkKeys:defaultKey];

                        if (checking.has_value()) {
                            if (activate) {
                                OO_LOG("equipment.load", "***** Error: {} for equipment item {} is already in use for {}. Default not applied", keyName, _identifier, *checking);
                            } else {
                                OO_LOG("equipment.load", "***** Error: {} for equipment item {} is already in use for {}. Default not applied.", keyName, _identifier, *checking);
                            }
                            defaultKey = oo::PList();
                        }
                    }
                }
            }
        }
    }

    if (!OK) {
        [self release];
        self = nil;
    }
    return self;
}

- (void)dealloc
{
    DESTROY(_displayColor);

    [super dealloc];
}

- (id)copyWithZone:(OOZone*)zone
{
    // OOEquipmentTypes are immutable.
    return [self retain];
}

- (std::optional<std::string>)cxx_descriptionComponents
{
    return oo::str::format("%s \"%s\"", _identifier.c_str(), _name.c_str());
}

- (std::optional<std::string>)cxx_identifier
{
    return _identifier;
}

- (std::optional<std::string>)cxx_damagedIdentifier
{
    return _identifier + "_DAMAGED";
}

- (id)name // shared selector (Foundation declares -name too; retires with oo-qps)
{
    return oo::NSStringOrNil([self cxx_name]);
}

- (std::optional<std::string>)cxx_name
{
    return _name;
}

- (std::optional<std::string>)cxx_descriptiveText
{
    return _description;
}

- (OOTechLevelID)techLevel
{
    return _techLevel;
}

- (OOCreditsQuantity)price
{
    return _price;
}

- (BOOL)isAvailableToAll
{
    return _isAvailableToAll;
}

- (BOOL)requiresEmptyPylon
{
    return _requiresEmptyPylon;
}

- (BOOL)requiresMountedPylon
{
    return _requiresMountedPylon;
}

- (BOOL)requiresCleanLegalRecord
{
    return _requiresClean;
}

- (BOOL)requiresNonCleanLegalRecord
{
    return _requiresNotClean;
}

- (BOOL)requiresFreePassengerBerth
{
    return _requiresFreePassengerBerth;
}

- (BOOL)requiresFullFuel
{
    return _requiresFullFuel;
}

- (BOOL)requiresNonFullFuel
{
    return _requiresNonFullFuel;
}

- (BOOL)isPrimaryWeapon
{
    return oo::str::hasPrefix(_identifier, "EQ_WEAPON");
}

- (BOOL)isMissileOrMine
{
    return _isMissileOrMine;
}

- (BOOL)isPortableBetweenShips
{
    return _portableBetweenShips;
}

- (BOOL)canCarryMultiple
{
    if ([self isMissileOrMine])
        return YES;
    // technically multiple can be fitted, but not to the same mount.
    if ([self isPrimaryWeapon])
        return NO;

    // hard-coded as special items
    if (_identifier == "EQ_PASSENGER_BERTH" || _identifier == "EQ_TRUMBLE") {
        return YES;
    }

    return _canCarryMultiple;
}

- (GLfloat)damageProbability
{
    if ([self isMissileOrMine])
        return 0.0;

    return _damageProbability;
}

- (BOOL)canBeDamaged
{
    if ([self isMissileOrMine])
        return NO;

    if ([self damageProbability] > 0.0) {
        return YES;
    }

    return NO;
}

- (BOOL)isVisible
{
    return _isVisible;
}

- (BOOL)hideValues
{
    return _hideValues;
}

- (BOOL)isAvailableToPlayer
{
    return _isAvailableToPlayer;
}

- (BOOL)isAvailableToNPCs
{
    return _isAvailableToNPCs;
}

- (OOCargoQuantity)requiredCargoSpace
{
    return _requiredCargoSpace;
}

- (std::optional<std::vector<std::string>>)cxx_requiresEquipment
{
    return _requiresEquipment;
}

- (std::optional<std::vector<std::string>>)cxx_requiresAnyEquipment
{
    return _requiresAnyEquipment;
}

- (std::optional<std::vector<std::string>>)cxx_incompatibleEquipment
{
    return _incompatibleEquipment;
}

- (OOColor*)displayColor
{
    return _displayColor;
}

- (void)setDisplayColor:(OOColor*)color
{
    [_displayColor release];
    _displayColor = [color retain];
}

- (oo::PList)cxx_conditions
{
    return _conditions;
}

- (std::optional<std::string>)cxx_conditionScript
{
    return _condition_script;
}

- (oo::PList)scriptInfo
{
    return _scriptInfo;
}

- (std::optional<std::string>)cxx_scriptName
{
    return _script;
}

- (BOOL)fastAffinityDefensive
{
    return _fastAffinityA;
}

- (BOOL)fastAffinityOffensive
{
    return _fastAffinityB;
}

- (oo::PList)cxx_defaultActivateKey
{
    return _defaultActivateKey;
}

- (oo::PList)cxx_defaultModeKey
{
    return _defaultModeKey;
}

- (NSUInteger)installTime
{
    return _installTime;
}

- (NSUInteger)repairTime
{
    if (_repairTime > 0) {
        return _repairTime;
    } else {
        return _installTime / 2;
    }
}

- (std::vector<std::string>)cxx_providesForScripting
{
    return _provides;
}

- (BOOL)cxx_provides:(const std::string&)key
{
    return std::find(_provides.begin(), _provides.end(), key) != _provides.end();
}

// weapon properties follow
- (BOOL)isTurretLaser
{
    return _weaponInfo.get<bool>("is_turret_laser", false);
}

- (BOOL)isMiningLaser
{
    return _weaponInfo.get<bool>("is_mining_laser", false);
}

- (oo::PList)cxx_weaponInfo
{
    return _weaponInfo;
}

- (GLfloat)weaponRange
{
    return _weaponInfo.get<float>("range", 12500.0);
}

- (GLfloat)weaponEnergyUse
{
    return _weaponInfo.get<float>("energy", 0.8);
}

- (GLfloat)weaponDamage
{
    return _weaponInfo.get<float>("damage", 15.0);
}

- (GLfloat)weaponRechargeRate
{
    return _weaponInfo.get<float>("recharge_rate", 0.5);
}

- (GLfloat)weaponShotTemperature
{
    return _weaponInfo.get<float>("shot_temperature", 7.0);
}

- (GLfloat)weaponThreatAssessment
{
    return _weaponInfo.get<float>("threat_assessment", 1.0);
}

- (OOColor*)weaponColor
{
    // +brightColorWithDescription: is not migrated: the "color" node crosses as the object it was.
    const oo::PList* color = _weaponInfo.find("color");
    return [OOColor brightColorWithDescription:(color != nullptr) ? oo::ObjectFromPList(*color) : nil];
}

- (std::optional<std::string>)cxx_fxShotMissName
{
    return StringFor(_weaponInfo, "fx_shot_miss_name", "[player-laser-miss]");
}

- (std::optional<std::string>)cxx_fxShotHitName
{
    return StringFor(_weaponInfo, "fx_shot_hit_name", "[player-laser-hit]");
}

- (std::optional<std::string>)cxx_fxShieldHitName
{
    return StringFor(_weaponInfo, "fx_hitplayer_shielded_name", "[player-hit-by-weapon]");
}

- (std::optional<std::string>)cxx_fxUnshieldedHitName
{
    return StringFor(_weaponInfo, "fx_hitplayer_unshielded_name", "[player-direct-hit]");
}

- (std::optional<std::string>)cxx_fxWeaponLaunchedName
{
    return StringFor(_weaponInfo, "fx_weapon_launch_name", (oo::str::hasSuffix(_identifier, "_MINE") ? "[mine-launched]" : "[missile-launched]"));
}

/*	This method exists purely to suppress Clang static analyzer warnings that
        this ivar is unused (but may be used by categories, which it is).
        FIXME: there must be a feature macro we can use to avoid actually building
        this into the app, but I can't find it in docs.
*/
- (BOOL)suppressClangStuff
{
    return !JS_IsObject(_jsSelf);
}

@end

#import "PlayerEntityLegacyScriptEngine.h"

@implementation OOEquipmentType (Conveniences)

- (OOTechLevelID)effectiveTechLevel
{
    OOTechLevelID tl;

    tl = [self techLevel];
    if (tl == kOOVariableTechLevel) {
        cxx_OOStandardsDeprecated(oo::str::format("TL99 is deprecated for %s", _identifier.c_str()));
        if (!OOEnforceStandards()) {
            const oo::PList missionValue = [PLAYER cxx_missionVariableForKey:"mission_TL_FOR_" + _identifier]; // OOUIntegerFromObject: OOUnsignedLongLongFromObject on this 64-bit build
            tl = static_cast<NSInteger>(oo::plist_get::unsignedLongLongFrom(!missionValue.isNull() ? &missionValue : nullptr, tl));
        }
    }

    return tl;
}

@end
