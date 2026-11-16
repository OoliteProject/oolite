/*

OOEquipmentType+ObjCBridge.mm
Oolite

TRANSITIONAL (proposed ADR-0056, bead oo-fg7i): the Objective-C OOEquipmentType facade over
cxx::OOEquipmentType. Every method forwards to its C++ member; results that were OOEquipmentType *
or OOColor * come back through oo::ToObjC, arguments go through oo::ToCxx. The class methods that
change the registries re-pin the registered types' facades (ADR-0056 amendment oo-fg7i). Deleted
with OOEquipmentType+ObjCBridge.h.

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

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

// The facades of the registered types, kept alive while they are registered: the Objective-C
// types were owned by the registries, and ships keep weapon and missile types unretained.
std::vector<oo::ObjCRef<OOEquipmentType*>>& Pinned()
{
    static auto* pinned = new std::vector<oo::ObjCRef<OOEquipmentType*>>;
    return *pinned;
}

void PinRegisteredTypes()
{
    std::vector<oo::ObjCRef<OOEquipmentType*>> pinned;
    @autoreleasepool {
        for (const auto& type : cxx::OOEquipmentType::allEquipmentTypes())
            pinned.emplace_back(oo::ToObjC(type));
        for (const auto& type : cxx::OOEquipmentType::allEquipmentTypesOutfitting())
            pinned.emplace_back(oo::ToObjC(type));
    }
    Pinned().swap(pinned); // the old pins go (the old registries released their types)
}

std::vector<oo::ObjCRef<OOEquipmentType*>> Facades(const std::vector<oo::Ref<cxx::OOEquipmentType>>& types)
{
    std::vector<oo::ObjCRef<OOEquipmentType*>> facades;
    facades.reserve(types.size());
    for (const auto& type : types)
        facades.emplace_back(oo::ToObjC(type));
    return facades;
}

} // namespace

@interface OOEquipmentType (OOObjCBridgePrivate)

- (id)initWithCxxEquipmentType:(cxx::OOEquipmentType*)type;

@end

@implementation OOEquipmentType

// Inside the @implementation for the private ivar.
OOEquipmentType* oo::ToObjC(cxx::OOEquipmentType* type)
{
    return Peers().peerFor(type, [type] { return [[OOEquipmentType alloc] initWithCxxEquipmentType:type]; });
}

cxx::OOEquipmentType* oo::ToCxx(OOEquipmentType* type)
{
    if (type == nil)
        return nullptr;
    return type->_cxxEquipmentType.get();
}

- (id)initWithCxxEquipmentType:(cxx::OOEquipmentType*)type
{
    self = [super init];
    if (self != nil)
        _cxxEquipmentType = oo::Ref<cxx::OOEquipmentType>(type);
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxEquipmentType.get());
    [super dealloc];
}

- (id)copyWithZone:(OOZone*)zone
{
    // OOEquipmentTypes are immutable.
    return [self retain];
}

- (std::optional<std::string>)cxx_descriptionComponents
{
    return _cxxEquipmentType->descriptionComponents();
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

+ (void)loadEquipment
{
    cxx::OOEquipmentType::loadEquipment();
    PinRegisteredTypes();
}

+ (void)cxx_addEquipmentWithInfo:(const oo::PList&)itemInfo
{
    cxx::OOEquipmentType::addEquipmentWithInfo(itemInfo);
    PinRegisteredTypes();
}

+ (std::optional<std::string>)cxx_getMissileRegistryRoleForShip:(const std::string&)shipKey
{
    return cxx::OOEquipmentType::getMissileRegistryRoleForShip(shipKey);
}

+ (void)cxx_setMissileRegistryRole:(const std::string&)role forShip:(const std::string&)shipKey
{
    cxx::OOEquipmentType::setMissileRegistryRole(role, shipKey);
}

+ (std::vector<oo::ObjCRef<OOEquipmentType*>>)cxx_allEquipmentTypes
{
    return Facades(cxx::OOEquipmentType::allEquipmentTypes());
}
+ (std::vector<oo::ObjCRef<OOEquipmentType*>>)cxx_allEquipmentTypesOutfitting
{
    return Facades(cxx::OOEquipmentType::allEquipmentTypesOutfitting());
}

+ (OOEquipmentType*)cxx_equipmentTypeWithIdentifier:(const std::string&)identifier
{
    return oo::ToObjC(cxx::OOEquipmentType::equipmentTypeWithIdentifier(identifier));
}

- (std::optional<std::string>)cxx_identifier
{
    return _cxxEquipmentType->identifier();
}
- (std::optional<std::string>)cxx_damagedIdentifier
{
    return _cxxEquipmentType->damagedIdentifier();
}
- (std::optional<std::string>)cxx_name
{
    return _cxxEquipmentType->name();
}
- (std::optional<std::string>)cxx_descriptiveText
{
    return _cxxEquipmentType->descriptiveText();
}
- (OOTechLevelID)techLevel
{
    return _cxxEquipmentType->techLevel();
}
- (OOCreditsQuantity)price
{
    return _cxxEquipmentType->price();
}

- (BOOL)isAvailableToAll
{
    return _cxxEquipmentType->isAvailableToAll();
}
- (BOOL)requiresEmptyPylon
{
    return _cxxEquipmentType->requiresEmptyPylon();
}
- (BOOL)requiresMountedPylon
{
    return _cxxEquipmentType->requiresMountedPylon();
}
- (BOOL)requiresCleanLegalRecord
{
    return _cxxEquipmentType->requiresCleanLegalRecord();
}
- (BOOL)requiresNonCleanLegalRecord
{
    return _cxxEquipmentType->requiresNonCleanLegalRecord();
}
- (BOOL)requiresFreePassengerBerth
{
    return _cxxEquipmentType->requiresFreePassengerBerth();
}
- (BOOL)requiresFullFuel
{
    return _cxxEquipmentType->requiresFullFuel();
}
- (BOOL)requiresNonFullFuel
{
    return _cxxEquipmentType->requiresNonFullFuel();
}
- (BOOL)isPrimaryWeapon
{
    return _cxxEquipmentType->isPrimaryWeapon();
}
- (BOOL)isMissileOrMine
{
    return _cxxEquipmentType->isMissileOrMine();
}
- (BOOL)isPortableBetweenShips
{
    return _cxxEquipmentType->isPortableBetweenShips();
}

- (BOOL)canCarryMultiple
{
    return _cxxEquipmentType->canCarryMultiple();
}
- (GLfloat)damageProbability
{
    return _cxxEquipmentType->damageProbability();
}
- (BOOL)canBeDamaged
{
    return _cxxEquipmentType->canBeDamaged();
}
- (BOOL)isVisible
{
    return _cxxEquipmentType->isVisible();
}
- (BOOL)hideValues
{
    return _cxxEquipmentType->hideValues();
}
- (OOColor*)displayColor
{
    return oo::ToObjC(_cxxEquipmentType->displayColor());
}
- (void)setDisplayColor:(OOColor*)newColor
{
    _cxxEquipmentType->setDisplayColor(oo::ToCxx(newColor));
}

- (BOOL)isAvailableToPlayer
{
    return _cxxEquipmentType->isAvailableToPlayer();
}
- (BOOL)isAvailableToNPCs
{
    return _cxxEquipmentType->isAvailableToNPCs();
}

- (OOCargoQuantity)requiredCargoSpace
{
    return _cxxEquipmentType->requiredCargoSpace();
}
- (std::optional<std::vector<std::string>>)cxx_requiresEquipment
{
    return _cxxEquipmentType->requiresEquipment();
}
- (std::optional<std::vector<std::string>>)cxx_requiresAnyEquipment
{
    return _cxxEquipmentType->requiresAnyEquipment();
}
- (std::optional<std::vector<std::string>>)cxx_incompatibleEquipment
{
    return _cxxEquipmentType->incompatibleEquipment();
}

- (oo::PList)cxx_conditions
{
    return _cxxEquipmentType->conditions();
}
- (std::optional<std::string>)cxx_conditionScript
{
    return _cxxEquipmentType->conditionScript();
}

- (oo::PList)scriptInfo
{
    return _cxxEquipmentType->scriptInfo();
}
- (std::optional<std::string>)cxx_scriptName
{
    return _cxxEquipmentType->scriptName();
}

- (BOOL)fastAffinityDefensive
{
    return _cxxEquipmentType->fastAffinityDefensive();
}
- (BOOL)fastAffinityOffensive
{
    return _cxxEquipmentType->fastAffinityOffensive();
}

- (oo::PList)cxx_defaultActivateKey
{
    return _cxxEquipmentType->defaultActivateKey();
}
- (oo::PList)cxx_defaultModeKey
{
    return _cxxEquipmentType->defaultModeKey();
}

- (NSUInteger)installTime
{
    return _cxxEquipmentType->installTime();
}
- (NSUInteger)repairTime
{
    return _cxxEquipmentType->repairTime();
}

- (std::vector<std::string>)cxx_providesForScripting
{
    return _cxxEquipmentType->providesForScripting();
}
- (BOOL)cxx_provides:(const std::string&)key
{
    return _cxxEquipmentType->provides(key);
}

- (BOOL)isTurretLaser
{
    return _cxxEquipmentType->isTurretLaser();
}
- (BOOL)isMiningLaser
{
    return _cxxEquipmentType->isMiningLaser();
}
- (oo::PList)cxx_weaponInfo
{
    return _cxxEquipmentType->weaponInfo();
}
- (GLfloat)weaponRange
{
    return _cxxEquipmentType->weaponRange();
}
- (GLfloat)weaponEnergyUse
{
    return _cxxEquipmentType->weaponEnergyUse();
}
- (GLfloat)weaponDamage
{
    return _cxxEquipmentType->weaponDamage();
}
- (GLfloat)weaponRechargeRate
{
    return _cxxEquipmentType->weaponRechargeRate();
}
- (GLfloat)weaponShotTemperature
{
    return _cxxEquipmentType->weaponShotTemperature();
}
- (GLfloat)weaponThreatAssessment
{
    return _cxxEquipmentType->weaponThreatAssessment();
}
- (OOColor*)weaponColor
{
    return oo::ToObjC(_cxxEquipmentType->weaponColor());
}
- (std::optional<std::string>)cxx_fxShotMissName
{
    return _cxxEquipmentType->fxShotMissName();
}
- (std::optional<std::string>)cxx_fxShotHitName
{
    return _cxxEquipmentType->fxShotHitName();
}
- (std::optional<std::string>)cxx_fxShieldHitName
{
    return _cxxEquipmentType->fxShieldHitName();
}
- (std::optional<std::string>)cxx_fxUnshieldedHitName
{
    return _cxxEquipmentType->fxUnshieldedHitName();
}
- (std::optional<std::string>)cxx_fxWeaponLaunchedName
{
    return _cxxEquipmentType->fxWeaponLaunchedName();
}

@end

@implementation OOEquipmentType (Conveniences)

- (OOTechLevelID)effectiveTechLevel
{
    return _cxxEquipmentType->effectiveTechLevel();
}

@end
