/*

ShipEntityLoadRestore.m


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

#include "ShipEntityLoadRestore.h"
#include "StationEntity.h"
#include "Universe.h"

#include "AI.h"
#include "OOConstToString.h"
#include "OOEquipmentType.h"
#include "OOPListGameTypes.h"
#include "OORoleSet.h"
#include "OOShipGroup.h"
#include "OOShipRegistry.h"
#include "ShipEntityAI.h"

#include "oofnd/PListGet.hpp"
#include "oofnd/objc/OOAssert.h"

#define KEY_SHIP_KEY "ship_key"
#define KEY_SHIPDATA_OVERRIDES "shipdata_overrides"
#define KEY_SHIPDATA_DELETES "shipdata_deletes"
#define KEY_PRIMARY_ROLE "primary_role"
#define KEY_POSITION "position"
#define KEY_ORIENTATION "orientation"
#define KEY_ROLES "roles"
#define KEY_FUEL "fuel"
#define KEY_BOUNTY "bounty"
#define KEY_ENERGY_LEVEL "energy_level"
#define KEY_EQUIPMENT "equipment"
#define KEY_MISSILES "missiles"
#define KEY_FORWARD_WEAPON "forward_weapon_type"
#define KEY_AFT_WEAPON "aft_weapon_type"
#define KEY_SCAN_CLASS "scan_class"

// AI is a complete pickled AI state.
#define KEY_AI "AI"

// Group IDs are numbers synchronised through the context object.
#define KEY_GROUP_ID "group"
#define KEY_GROUP_NAME "group_name"
#define KEY_IS_GROUP_LEADER "is_group_leader"
#define KEY_ESCORT_GROUP_ID "escort_group"

namespace {

void StripIgnoredKeys(oo::PList::Dict& dict);
NSUInteger GroupIDForGroup(OOShipGroup* group, OOShipSaveContext& context);
OOShipGroup* GroupForGroupID(NSUInteger groupID, OOShipSaveContext& context);
oo::PList::Dict DictFrom(const oo::PList& plist);
oo::PList ArrayFromStrings(const std::vector<std::string>& strings);
std::optional<std::string> OptionalStringForKey(const oo::PList& dict, std::string_view key);
} // namespace

/*	The category ShipEntity (LoadRestore), bead oo-kw44: members of ShipEntity (ADR-0056
        amendments oo-o89 item 4 and oo-42dr), forwarded by the category of the same name in
        ShipEntity+ObjCBridge.mm until bead oo-9ht.144 deleted the facade and its sends became member
        calls; +shipRestoredFromDictionary:useFallback:context: is a static member, and the private
        category LoadRestoreInternal's -simplifyShipdata:andGetDeletes: a member with no forwarder (only
        the members call it).
*/

oo::PList ShipEntity::savedShipDictionaryWithContext(OOShipSaveContext* context)
{
    oo::PList::Dict result;
    OOShipSaveContext localContext;
    if (context == nullptr)
        context = &localContext;

    result[KEY_SHIP_KEY] = _shipKey.value_or(std::string()); // nil as "", as oo::StdString gave

    oo::PList::Dict updatedShipInfo = DictFrom(shipinfoDictionary);

    // A role set without a role string (nil before, which -setObject:forKey: refused) adds no key.
    const oo::Ref<OORoleSet> roles = getRoleSet();
    if (const std::optional<std::string> roleString = (roles != nullptr) ? roles->roleString() : std::nullopt)
        updatedShipInfo[KEY_ROLES] = *roleString;
    updatedShipInfo[KEY_FUEL] = oo::PList::unsignedInteger(fuel);
    updatedShipInfo[KEY_BOUNTY] = oo::PList::unsignedInteger(bounty);
    updatedShipInfo[KEY_FORWARD_WEAPON] = cxx_OOStringFromWeaponType(forward_weapon_type).value_or("");
    updatedShipInfo[KEY_AFT_WEAPON] = cxx_OOStringFromWeaponType(aft_weapon_type).value_or("");
    updatedShipInfo[KEY_SCAN_CLASS] = cxx_OOStringFromScanClass(scanClass);

    std::vector<std::string> deletes;
    simplifyShipdata(updatedShipInfo, &deletes);

    result[KEY_SHIPDATA_OVERRIDES] = oo::PList(std::move(updatedShipInfo));
    if (!deletes.empty())
        result[KEY_SHIPDATA_DELETES] = ArrayFromStrings(deletes);

    if (!HPvector_equal(getPosition(), kZeroHPVector)) {
        result[KEY_POSITION] = OOPListFromHPVector(getPosition());
    }
    if (!quaternion_equal(normalOrientation(), kIdentityQuaternion)) {
        result[KEY_ORIENTATION] = OOPListFromQuaternion(normalOrientation());
    }

    // -oo_setFloat:forKey: stored a double.
    if (energy != maxEnergy)
        result[KEY_ENERGY_LEVEL] = oo::PList(static_cast<double>(energy / maxEnergy));

    result[KEY_PRIMARY_ROLE] = getPrimaryRole().value_or("");

    // Add equipment.
    const std::vector<std::string> equipment = equipmentKeys();
    if (equipment.size() != 0)
        result[KEY_EQUIPMENT] = ArrayFromStrings(equipment);

    // Add missiles.
    if (missiles > 0) {
        std::vector<std::string> missileArray;
        unsigned i;
        for (i = 0; i < missiles; i++) {
            const std::optional<std::string> missileType = (missile_list[i] != nullptr ? missile_list[i]->identifier() : std::optional<std::string>());
            if (missileType.has_value())
                missileArray.push_back(*missileType);
        }
        result[KEY_MISSILES] = ArrayFromStrings(missileArray);
    }

    // Add groups.
    if (_group != nil) {
        result[KEY_GROUP_ID] = oo::PList::unsignedInteger(GroupIDForGroup(_group.get(), *context));
        if ((_group != nullptr ? _group->leader() : (::ShipEntity*)nil) == this)
            result[KEY_IS_GROUP_LEADER] = oo::PList(static_cast<bool>(YES));
        const std::optional<std::string> groupName = (_group != nullptr ? _group->name() : std::optional<std::string>());
        if (groupName.has_value()) {
            result[KEY_GROUP_NAME] = *groupName;
        }
    }
    if (_escortGroup != nil) {
        result[KEY_ESCORT_GROUP_ID] = oo::PList::unsignedInteger(GroupIDForGroup(_escortGroup.get(), *context));
    }
    /*	Eric:
            The escortGroup property is removed from the lead ship, on entering witchspace.
            But it is needed in the save file to correctly restore an escorted group.
    */
    else if (_group != nil && (_group != nullptr ? _group->leader() : (::ShipEntity*)nil) == this) {
        result[KEY_ESCORT_GROUP_ID] = oo::PList::unsignedInteger(GroupIDForGroup(_group.get(), *context));
    }

    // FIXME: AI.
    // Eric: I think storing the AI name should be enough. On entering a wormhole, the stack is cleared so there are no preserved AI states.
    // Also the AI restarts itself with the GLOBAL state, so no need to store any old state.
    if ((getAI() != nullptr ? getAI()->name() : std::optional<std::string>()).value_or(std::string()) == "nullAI.plist") {
        // might be a JS version (with none, no key: -setObject:forKey: refused nil)
        if (const std::optional<std::string> js = (getAI() != nullptr ? getAI()->associatedJS() : std::optional<std::string>()))
            result[KEY_AI] = *js;
        // if there isn't, loading nullAI.js will load nullAI.plist anyway
    } else {
        result[KEY_AI] = (getAI() != nullptr ? getAI()->name() : std::optional<std::string>()).value_or(std::string());
    }

    return oo::PList(std::move(result));
}

::ShipEntity* ShipEntity::shipRestoredFromDictionary(const oo::PList& dict, bool fallback, OOShipSaveContext* context)
{
    if (dict.isNull())
        return nil;
    OOShipSaveContext localContext;
    if (context == nullptr)
        context = &localContext;

    ::ShipEntity* ship = nil;

    const std::string shipKey = dict.get<std::string>(KEY_SHIP_KEY); // "" finds no ship, as nil did
    const oo::PList shipData = OOShipRegistry::sharedRegistry()->shipInfoForKey(shipKey);

    if (shipData) {
        oo::PList::Dict mergedData = DictFrom(shipData);

        StripIgnoredKeys(mergedData);
        if (const oo::PList* deletes = dict.get<oo::PList::Array>(KEY_SHIPDATA_DELETES)) {
            for (const oo::PList& key : *deletes->getIf<oo::PList::Array>()) {
                if (const std::string* name = key.getIf<std::string>())
                    mergedData.erase(*name);
            }
        }
        if (const oo::PList* overrides = dict.get<oo::PList::Dict>(KEY_SHIPDATA_OVERRIDES)) {
            for (const auto& [key, value] : *overrides->getIf<oo::PList::Dict>())
                mergedData.insert_or_assign(key, value);
        }
        mergedData["auto_ai"] = oo::PList(static_cast<bool>(NO));
        mergedData["escorts"] = oo::PList::unsignedInteger(0);

        const oo::PList mergedPlist(std::move(mergedData));
        // A station is made in C++ since bead oo-9ht.175 (the universe picked its class).
        if ((UNIVERSE != nullptr ? UNIVERSE->isStationShipDictionary(mergedPlist) : false))
            ship = oo::ToShip(oo::AutoreleaseEntity(StationEntity::newStationObject(shipKey, mergedPlist)));
        else
            ship = oo::ToShip(oo::AutoreleaseEntity(oo::NewShipObject(oo::makeRef<::ShipEntity>(), shipKey, mergedPlist)));

        // FIXME: restore AI.
        if (ship != nullptr)
            ship->setAITo(dict.get<std::string>(KEY_AI, "nullAI.plist"));

        const std::optional<std::string> primaryRole = OptionalStringForKey(dict, KEY_PRIMARY_ROLE);
        if (primaryRole.has_value()) {
            if (ship != nullptr)
                ship->setPrimaryRole(*primaryRole);
        } else
            ship->primaryRole = std::nullopt; // as -setPrimaryRole: stored nil

    } else {
        // Unknown ship; fall back on role if desired and possible.
        const std::optional<std::string> shipPrimaryRole = OptionalStringForKey(dict, KEY_PRIMARY_ROLE);
        if (!fallback || !shipPrimaryRole.has_value())
            return nil;

        ship = oo::ToShip(oo::AutoreleaseEntity((UNIVERSE != nullptr ? UNIVERSE->newShipWithRole(*shipPrimaryRole) : (::ShipEntity*)nil)));
        if (ship == nil)
            return nil;
    }

    // The following stuff is deliberately set up the same way even if using role fallback.
    if (ship != nullptr)
        ship->setPosition(OOHPVectorFromPList(dict.find(KEY_POSITION), kZeroHPVector));
    if (ship != nullptr)
        ship->setNormalOrientation(OOQuaternionFromPList(dict.find(KEY_ORIENTATION), kIdentityQuaternion));

    float energyLevel = dict.get<float>(KEY_ENERGY_LEVEL, 1.0f);
    if (ship != nullptr)
        ship->setEnergy(energyLevel * (ship != nullptr ? ship->getMaxEnergy() : 0.0f));

    if (ship != nullptr)
        ship->removeAllEquipment();
    if (const oo::PList* equipment = dict.get<oo::PList::Array>(KEY_EQUIPMENT)) {
        for (const oo::PList& eqKey : *equipment->getIf<oo::PList::Array>()) {
            if (const std::string* key = eqKey.getIf<std::string>()) {
                if (ship != nullptr)
                    ship->addEquipmentItem(*key, NO, "loading");
            } // the saved keys are strings
        }
    }

    if (ship != nullptr)
        ship->removeMissiles();
    if (const oo::PList* missileList = dict.get<oo::PList::Array>(KEY_MISSILES)) {
        for (const oo::PList& eqKey : *missileList->getIf<oo::PList::Array>()) {
            if (const std::string* key = eqKey.getIf<std::string>()) {
                if (ship != nullptr)
                    ship->addEquipmentItem(*key, NO, "loading");
            } // the saved keys are strings
        }
    }

    // Groups.
    NSUInteger groupID = dict.get<NSInteger>(KEY_GROUP_ID, NSNotFound);
    if (groupID != NSNotFound) {
        ::OOShipGroup* group = GroupForGroupID(groupID, *context);
        if (ship != nullptr)
            ship->setGroup(group); // Handles adding to group
        if (dict.get<bool>(KEY_IS_GROUP_LEADER)) {
            if (group != nullptr)
                group->setLeader(ship);
        }
        const std::optional<std::string> groupName = OptionalStringForKey(dict, KEY_GROUP_NAME);
        if (groupName.has_value()) {
            if (group != nullptr)
                group->setName(groupName);
        }
        if ((ship != nullptr ? ship->hasPrimaryRole("escort") : false) && ship != (group != nullptr ? group->leader() : (::ShipEntity*)nil)) {
            if (ship != nullptr)
                ship->setOwner((group != nullptr ? group->leader() : (::ShipEntity*)nil));
        }
    }

    groupID = dict.get<NSInteger>(KEY_ESCORT_GROUP_ID, NSNotFound);
    if (groupID != NSNotFound) {
        ::OOShipGroup* group = GroupForGroupID(groupID, *context);
        if (group != nullptr)
            group->setLeader(ship);
        if (group != nullptr)
            group->setName(std::string("escort group"));
        if (ship != nullptr)
            ship->setEscortGroup(group);
    }

    return ship;
}

void ShipEntity::simplifyShipdata(oo::PList::Dict& data, std::vector<std::string>* deletes)
{
    OOCParameterAssert(deletes != NULL);
    deletes->clear();

    // Get original ship data.
    oo::PList::Dict referenceData = DictFrom(OOShipRegistry::sharedRegistry()->shipInfoForKey(shipDataKey().value_or(std::string())));

    // Discard stuff that we handle separately.
    StripIgnoredKeys(referenceData);
    StripIgnoredKeys(data);

    // Note items that are in referenceData, but not data (in byte order of the key; hash order before).
    for (const auto& [key, value] : referenceData) {
        if (!data.contains(key)) {
            deletes->push_back(key);
        }
    }

    // after rev3010 this loop was using cycles without doing anything - commenting this whole loop out for now. -- kaks 20100207
    /*
            // Discard anything that hasn't changed.
            for (enumerator = [data keyEnumerator]; (key = [enumerator nextObject]); )
            {
                    id referenceVal = [referenceData objectForKey:key];
                    id myVal = [data objectForKey:key];
                    if ([referenceVal isEqual:myVal])
                    {
                    //	[data removeObjectForKey:key];
                    }
            }
    */
}

namespace {

void StripIgnoredKeys(oo::PList::Dict& dict)
{
    static const char* const ignoredKeys[] = { "ai_type", "has_ecm", "has_scoop", "has_escape_pod", "has_energy_bomb", "has_fuel_injection", "has_cloaking_device", "has_military_jammer", "has_military_scanner_filter", "has_shield_booster", "has_shield_enhancer", "escorts", "escort_role", "escort-ship", "conditions", "missiles", "auto_ai" };

    for (const char* key : ignoredKeys) {
        const auto found = dict.find(std::string_view(key));
        if (found != dict.end())
            dict.erase(found);
    }
}

NSUInteger GroupIDForGroup(OOShipGroup* group, OOShipSaveContext& context)
{
    const auto found = context.groupIDs.find(group);
    unsigned groupID;
    if (found == context.groupIDs.end()) {
        // Assign a new group ID.
        groupID = context.nextGroupID;
        context.nextGroupID = groupID + 1;
        context.groupIDs.emplace(group, groupID);

        /*	Also keep references to the groups. This isn't necessary at the
                time of writing, but would be if we e.g. switched to pickling
                ships in wormholes all the time (each wormhole would then need a
                persistent context).
        */
        context.groups.emplace_back(group);
    } else {
        groupID = found->second;
    }

    return groupID;
}

OOShipGroup* GroupForGroupID(NSUInteger groupID, OOShipSaveContext& context)
{
    oo::Ref<OOShipGroup>& group = context.groupsByID[groupID];
    if (group == nullptr) {
        group = OOShipGroup::groupWithName(std::nullopt); // -init
    }

    return group.get();
}

// A dictionary's entries; empty for anything else (as +dictionaryWithDictionary: of nil was).
oo::PList::Dict DictFrom(const oo::PList& plist)
{
    if (const oo::PList::Dict* dict = plist.getIf<oo::PList::Dict>())
        return *dict;
    return { };
}

oo::PList ArrayFromStrings(const std::vector<std::string>& strings)
{
    oo::PList::Array array;
    array.reserve(strings.size());
    for (const std::string& string : strings)
        array.emplace_back(string);
    return oo::PList(std::move(array));
}

// get<std::string> where the Foundation code read nil: std::nullopt when the key is absent or its
// value is neither a string nor a number.
std::optional<std::string> OptionalStringForKey(const oo::PList& dict, std::string_view key)
{
    const oo::PList* value = dict.find(key);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return dict.get<std::string>(key);
}

} // namespace
