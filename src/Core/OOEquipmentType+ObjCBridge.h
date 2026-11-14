/*

OOEquipmentType+ObjCBridge.h
Oolite

TRANSITIONAL (proposed ADR-0056, bead oo-fg7i): the Objective-C OOEquipmentType, a facade over the
C++ cxx::OOEquipmentType (OOEquipmentType.h), for callers that are not converted yet (ShipEntity,
PlayerEntity and its categories, Universe, OOConstToString and the JS bindings). Its interface is
the one OOEquipmentType.h declared before the conversion, copied exactly (same selectors, same
types), so those callers compile and behave unchanged; each method forwards to its C++ member.
Imported as the last line of OOEquipmentType.h; do not import it directly.

Two things differ from the plain facade (ADR-0056 amendment oo-fg7i):
- the facade also keeps _jsSelf, the ivar the JavaScript category (OOJSEquipmentInfo.mm) reads and
  writes: it is the Objective-C object's JavaScript wrapper, not the C++ type's state;
- a registered type's facade lives as long as it is registered, as the Objective-C type did: ships
  keep weapon and missile types unretained. +loadEquipment and +cxx_addEquipmentWithInfo: pin the
  facades of the registries after forwarding.

Never add to this file; converted code does not message the facade. Deleted by its deletion bead
once no file outside OOEquipmentType.* names the Objective-C OOEquipmentType.

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

#ifndef OOEQUIPMENTTYPE_OBJCBRIDGE_H
#define OOEQUIPMENTTYPE_OBJCBRIDGE_H

@interface OOEquipmentType : OOObject <OOCopying> {
@private
    oo::Ref<cxx::OOEquipmentType> _cxxEquipmentType;

    JSValue _jsSelf; // the JavaScript category's (OOJSEquipmentInfo.mm). Zero-filled (not an object) until created; test with JS_IsObject().
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

namespace oo {

// The type's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOEquipmentType* ToObjC(cxx::OOEquipmentType* type);
inline OOEquipmentType* ToObjC(const Ref<cxx::OOEquipmentType>& type) { return ToObjC(type.get()); }

// The C++ type behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOEquipmentType* ToCxx(OOEquipmentType* type);

} // namespace oo

#endif // OOEQUIPMENTTYPE_OBJCBRIDGE_H
