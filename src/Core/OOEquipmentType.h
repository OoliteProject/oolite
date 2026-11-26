/*

OOEquipmentType.h

Class representing a type of ship equipment. Exposed to JavaScript as
EquipmentInfo.


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

#pragma once

#import "OOFoundation.h"
#import "OOScript.h"
#import "OOTypes.h"
#import "Universe.h"
#include "oofnd/objc/OOObjCRef.h"
#import "oofnd/objc/OOObject.h"

#include <quickjs.h>

#include <map>
#include <optional>
#include <string>
#include <vector>

#include "oofnd/PList.hpp"

@interface OOEquipmentType : OOObject <OOCopying> {
@private
    OOTechLevelID _techLevel;
    OOCreditsQuantity _price;
    std::string _name; // never empty-for-nil: -initWithInfo: fails without all three
    std::string _identifier;
    std::string _description;
    unsigned _isAvailableToAll : 1,
        _requiresEmptyPylon : 1,
        _requiresMountedPylon : 1,
        _requiresClean : 1,
        _requiresNotClean : 1,
        _portableBetweenShips : 1,
        _requiresFreePassengerBerth : 1,
        _requiresFullFuel : 1,
        _requiresNonFullFuel : 1,
        _isMissileOrMine : 1,
        _isVisible : 1,
        _isAvailableToPlayer : 1,
        _isAvailableToNPCs : 1,
        _fastAffinityA : 1,
        _fastAffinityB : 1,
        _canCarryMultiple : 1,
        _hideValues : 1;
    OOColor* _displayColor;
    NSUInteger _installTime;
    NSUInteger _repairTime;
    GLfloat _damageProbability;
    OOCargoQuantity _requiredCargoSpace;
    // Sorted, de-duplicated equipment keys; nullopt when the key is absent (was nil).
    std::optional<std::vector<std::string>> _requiresEquipment;
    std::optional<std::vector<std::string>> _requiresAnyEquipment;
    std::optional<std::vector<std::string>> _incompatibleEquipment;
    oo::PList _conditions; // an array; null: none (was nil)
    std::vector<std::string> _provides;
    oo::PList _defaultActivateKey; // an array; null: none (was nil)
    oo::PList _defaultModeKey; // an array; null: none (was nil)
    oo::PList _scriptInfo; // a dictionary; null: none (was nil)
    oo::PList _weaponInfo; // a dictionary (empty by default)
    std::optional<std::string> _script;
    std::optional<std::string> _condition_script;

    JSValue _jsSelf; // Zero-filled (not an object) until created; test with JS_IsObject().
}

+ (void)loadEquipment; // Load equipment data; called on loading and when changing to/from strict mode.
+ (void)cxx_addEquipmentWithInfo:(const oo::PList&)itemInfo; // Used to generate equipment from missile_role entries.

+ (std::optional<std::string>)cxx_getMissileRegistryRoleForShip:(const std::string&)shipKey; // nullopt: none registered
+ (void)cxx_setMissileRegistryRole:(const std::string&)role forShip:(const std::string&)shipKey;

+ (std::vector<oo::ObjCRef<OOEquipmentType*>>)cxx_allEquipmentTypes; // a snapshot, in equipment.plist order
+ (std::vector<oo::ObjCRef<OOEquipmentType*>>)cxx_allEquipmentTypesOutfitting; // the outfitting dataset

+ (OOEquipmentType*)cxx_equipmentTypeWithIdentifier:(const std::string&)identifier; // nil: none

- (std::optional<std::string>)cxx_identifier;
- (std::optional<std::string>)cxx_damagedIdentifier;
- (id)name; // localized; shared selector (Foundation declares -name too): -cxx_name as an Objective-C string
- (std::optional<std::string>)cxx_name; // localized (bead oo-3rb.289.10)
- (std::optional<std::string>)cxx_descriptiveText; // localized
- (OOTechLevelID)techLevel;
- (OOCreditsQuantity)price; // Tenths of credits

- (BOOL)isAvailableToAll;
- (BOOL)requiresEmptyPylon;
- (BOOL)requiresMountedPylon;
- (BOOL)requiresCleanLegalRecord;
- (BOOL)requiresNonCleanLegalRecord;
- (BOOL)requiresFreePassengerBerth;
- (BOOL)requiresFullFuel;
- (BOOL)requiresNonFullFuel;
- (BOOL)isPrimaryWeapon;
- (BOOL)isMissileOrMine;
- (BOOL)isPortableBetweenShips;

- (BOOL)canCarryMultiple;
- (GLfloat)damageProbability;
- (BOOL)canBeDamaged;
- (BOOL)isVisible; // Visible in UI?
- (BOOL)hideValues;
- (OOColor*)displayColor;
- (void)setDisplayColor:(OOColor*)newColor;

- (BOOL)isAvailableToPlayer;
- (BOOL)isAvailableToNPCs;

- (OOCargoQuantity)requiredCargoSpace;
// Equipment identifiers, sorted and de-duplicated; nullopt when not specified.
- (std::optional<std::vector<std::string>>)cxx_requiresEquipment; // all items required
- (std::optional<std::vector<std::string>>)cxx_requiresAnyEquipment; // any item required
- (std::optional<std::vector<std::string>>)cxx_incompatibleEquipment; // all items prohibited

// FIXME: should have general mechanism to handle scripts or legacy conditions.
- (oo::PList)cxx_conditions; // an array; null: none

- (std::optional<std::string>)cxx_conditionScript;

- (oo::PList)scriptInfo; // flipped with its family (bead oo-3rb.284); null: none
- (std::optional<std::string>)cxx_scriptName;

- (BOOL)fastAffinityDefensive;
- (BOOL)fastAffinityOffensive;

- (oo::PList)cxx_defaultActivateKey; // an array; null: none
- (oo::PList)cxx_defaultModeKey; // an array; null: none

- (NSUInteger)installTime;
- (NSUInteger)repairTime;

- (std::vector<std::string>)cxx_providesForScripting;
- (BOOL)cxx_provides:(const std::string&)key;

// weapon properties
- (BOOL)isTurretLaser;
- (BOOL)isMiningLaser;
- (oo::PList)cxx_weaponInfo; // a dictionary
- (GLfloat)weaponRange;
- (GLfloat)weaponEnergyUse;
- (GLfloat)weaponDamage;
- (GLfloat)weaponRechargeRate;
- (GLfloat)weaponShotTemperature;
- (GLfloat)weaponThreatAssessment;
- (OOColor*)weaponColor;
- (std::optional<std::string>)cxx_fxShotMissName;
- (std::optional<std::string>)cxx_fxShotHitName;
- (std::optional<std::string>)cxx_fxShieldHitName;
- (std::optional<std::string>)cxx_fxUnshieldedHitName;
- (std::optional<std::string>)cxx_fxWeaponLaunchedName;

@end

@interface OOEquipmentType (Conveniences)

- (OOTechLevelID)effectiveTechLevel;

@end
