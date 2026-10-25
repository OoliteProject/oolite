/*

OOEquipmentType.h

C++20 since bead oo-fg7i (Phase 3, proposed ADR-0056). Its Objective-C facade was deleted by bead
oo-9ht.28 (batch F, ADR-0056 amendment oo-9ht.19). The registries of types are the class's and
keep each registered type alive while it is registered; ships keep weapon and missile types
unretained (OOWeaponType, null: no weapon). A type is its own PList::Object payload
(oo::PListForeign) and its own JS glue (OOJSPrivateObject).

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

#ifndef OOEQUIPMENTTYPE_H
#define OOEQUIPMENTTYPE_H

#include "OOCocoa.h"
#include "oofnd/objc/OOObject.h"
#include "ooscript/JSEngine.hpp"
#include "OOTypes.h"
#include "OOOpenGL.h"
#include "oofnd/Ref.hpp"
#include "OOColor.h"

#include <map>
#include <optional>
#include <string>
#include <vector>

#include "oofnd/PList.hpp"
#include "Scripting/OOJSPrivateObject.h"


class OOEquipmentType : public oo::PListForeign, public ::OOJSPrivateObject
{
public:
	static void loadEquipment();			// Load equipment data; called on loading and when changing to/from strict mode.
	static void addEquipmentWithInfo(const oo::PList &itemInfo);	// Used to generate equipment from missile_role entries.

	static std::optional<std::string> getMissileRegistryRoleForShip(const std::string &shipKey);	// nullopt: none registered
	static void setMissileRegistryRole(const std::string &role, const std::string &shipKey);

	static std::vector<oo::Ref<OOEquipmentType>> allEquipmentTypes();			// a snapshot, in equipment.plist order
	static std::vector<oo::Ref<OOEquipmentType>> allEquipmentTypesOutfitting();	// the outfitting dataset

	static oo::Ref<OOEquipmentType> equipmentTypeWithIdentifier(const std::string &identifier);	// null: none

	std::optional<std::string> identifier();
	std::optional<std::string> damagedIdentifier();
	std::optional<std::string> name();	// localized (bead oo-3rb.289.10)
	std::optional<std::string> descriptiveText();	// localized
	OOTechLevelID techLevel();
	OOCreditsQuantity price();	// Tenths of credits

	bool isAvailableToAll();
	bool requiresEmptyPylon();
	bool requiresMountedPylon();
	bool requiresCleanLegalRecord();
	bool requiresNonCleanLegalRecord();
	bool requiresFreePassengerBerth();
	bool requiresFullFuel();
	bool requiresNonFullFuel();
	bool isPrimaryWeapon();
	bool isMissileOrMine();
	bool isPortableBetweenShips();

	bool canCarryMultiple();
	GLfloat damageProbability();
	bool canBeDamaged();
	bool isVisible();				// Visible in UI?
	bool hideValues();
	oo::Ref<OOColor> displayColor();
	void setDisplayColor(OOColor *newColor);

	bool isAvailableToPlayer();
	bool isAvailableToNPCs();

	OOCargoQuantity requiredCargoSpace();
	// Equipment identifiers, sorted and de-duplicated; nullopt when not specified.
	std::optional<std::vector<std::string>> requiresEquipment();		// all items required
	std::optional<std::vector<std::string>> requiresAnyEquipment();	// any item required
	std::optional<std::vector<std::string>> incompatibleEquipment();	// all items prohibited

	// FIXME: should have general mechanism to handle scripts or legacy conditions.
	oo::PList conditions();	// an array; null: none

	std::optional<std::string> conditionScript();

	oo::PList scriptInfo();	// null: none
	std::optional<std::string> scriptName();

	bool fastAffinityDefensive();
	bool fastAffinityOffensive();

	oo::PList defaultActivateKey();	// an array; null: none
	oo::PList defaultModeKey();		// an array; null: none

	NSUInteger installTime();
	NSUInteger repairTime();

	std::vector<std::string> providesForScripting();
	bool provides(const std::string &key);

	// weapon properties
	bool isTurretLaser();
	bool isMiningLaser();
	oo::PList weaponInfo();	// a dictionary
	GLfloat weaponRange();
	GLfloat weaponEnergyUse();
	GLfloat weaponDamage();
	GLfloat weaponRechargeRate();
	GLfloat weaponShotTemperature();
	GLfloat weaponThreatAssessment();
	oo::Ref<OOColor> weaponColor();
	std::optional<std::string> fxShotMissName();
	std::optional<std::string> fxShotHitName();
	std::optional<std::string> fxShieldHitName();
	std::optional<std::string> fxUnshieldedHitName();
	std::optional<std::string> fxWeaponLaunchedName();

	// Conveniences
	OOTechLevelID effectiveTechLevel();

	// What "%@" prints between the braces of <OOEquipmentType 0x...>{...} (OODescription.h).
	std::optional<std::string> descriptionComponents() const;

	// The JS glue (OOJSPrivateObject), defined in OOJSEquipmentInfo.mm: the EquipmentInfo object,
	// made on first use; forgetting it when it is finalized; "[EquipmentInfo <components>]".
	ooscript::Value jsValueInContext(ooscript::Context context) override;
	void clearJSSelf(ooscript::Object selfVal) override;
	std::optional<std::string> jsDescription() override;

	// oo::PListForeign: what the facade answered (its class, and "%@" as <OOEquipmentType 0x...>{...}).
	std::string className() const override;
	std::string description() const override;

private:
	OOEquipmentType() = default;

	// -initWithInfo:, which could fail: createWithInfo() runs it on a new object (ADR-0056
	// amendment oo-fg7i).
	static oo::Ref<OOEquipmentType> createWithInfo(const oo::PList &info);
	bool initWithInfo(const oo::PList &info);	// an equipment.plist entry (an array)

	OOTechLevelID			_techLevel = {};
	OOCreditsQuantity		_price = {};
	std::string				_name;			// never empty-for-nil: initWithInfo() fails without all three
	std::string				_identifier;
	std::string				_description;
	unsigned				_isAvailableToAll: 1 = 0,
							_requiresEmptyPylon: 1 = 0,
							_requiresMountedPylon: 1 = 0,
							_requiresClean: 1 = 0,
							_requiresNotClean: 1 = 0,
							_portableBetweenShips: 1 = 0,
							_requiresFreePassengerBerth: 1 = 0,
							_requiresFullFuel: 1 = 0,
							_requiresNonFullFuel: 1 = 0,
							_isMissileOrMine: 1 = 0,
							_isVisible: 1 = 0,
							_isAvailableToPlayer: 1 = 0,
							_isAvailableToNPCs: 1 = 0,
							_fastAffinityA: 1 = 0,
							_fastAffinityB: 1 = 0,
							_canCarryMultiple: 1 = 0,
							_hideValues: 1 = 0;
	oo::Ref<OOColor>		_displayColor;
	NSUInteger				_installTime = {};
	NSUInteger				_repairTime = {};
	GLfloat     			_damageProbability = {};
	OOCargoQuantity			_requiredCargoSpace = {};
	// Sorted, de-duplicated equipment keys; nullopt when the key is absent (was nil).
	std::optional<std::vector<std::string>>	_requiresEquipment;
	std::optional<std::vector<std::string>>	_requiresAnyEquipment;
	std::optional<std::vector<std::string>>	_incompatibleEquipment;
	oo::PList				_conditions;		// an array; null: none (was nil)
	std::vector<std::string>	_provides;
	oo::PList				_defaultActivateKey;	// an array; null: none (was nil)
	oo::PList				_defaultModeKey;		// an array; null: none (was nil)
	oo::PList				_scriptInfo;			// a dictionary; null: none (was nil)
	oo::PList				_weaponInfo;			// a dictionary (empty by default)
	std::optional<std::string>	_script;
	std::optional<std::string>	_condition_script;
	ooscript::Object		_jsSelf = {};	// the EquipmentInfo object (OOJSEquipmentInfo.mm)
};


/*	A type carried through plist data as a PList::Object node (proposed ADR-0043 Amendment 2):
	the type is the node's foreign object (bead oo-9ht.28; what oo::PListObject() and
	oo::ObjectIn() did for the facade).
*/
inline oo::PList OOEquipmentTypeObjectNode(OOEquipmentType *type)	// null type -> null PList
{
	if (type == nullptr)  return oo::PList();
	return oo::PList(oo::PList::Object(oo::Ref<oo::PListForeign>(type)));
}

inline OOEquipmentType *OOEquipmentTypeInObjectNode(const oo::PList &plist)	// null for any other node
{
	const oo::PList::Object *node = plist.getIf<oo::PList::Object>();
	return (node != nullptr) ? dynamic_cast<OOEquipmentType *>(node->get()) : nullptr;
}

// An array of Object nodes, one per non-null type, in order (what oo::PListFromObjects() made of
// the facades).
inline oo::PList OOEquipmentTypeObjectNodes(const std::vector<oo::Ref<OOEquipmentType>> &types)
{
	oo::PList::Array result;
	result.reserve(types.size());
	for (const oo::Ref<OOEquipmentType> &type : types)
	{
		if (type != nullptr)  result.push_back(OOEquipmentTypeObjectNode(type.get()));
	}
	return oo::PList(std::move(result));
}

#endif	// OOEQUIPMENTTYPE_H
