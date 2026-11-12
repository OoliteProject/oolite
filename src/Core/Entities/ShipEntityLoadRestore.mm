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

#import "ShipEntityLoadRestore.h"
#import "Universe.h"

#import "AI.h"
#import "OOCollectionExtractors.h" // OOHPVectorFromObject() & co., OOPropertyListFromHPVector() & co. (unmigrated callees)
#import "OOConstToString.h"
#import "OOEquipmentType.h"
#import "OOFoundationBridge.h"
#import "OORoleSet.h"
#import "OOShipGroup.h"
#import "OOShipRegistry.h"
#import "ShipEntityAI.h"

#include "oofnd/PListGet.hpp"

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
id ObjectForKey(const oo::PList& dict, std::string_view key);
} // namespace

@interface ShipEntity (LoadRestoreInternal)

// deletes: the keys to delete, empty where the Foundation version gave nil.
- (void)simplifyShipdata:(oo::PList::Dict&)data andGetDeletes:(std::vector<std::string>*)deletes;

@end

@implementation ShipEntity (LoadRestore)

- (oo::PList)savedShipDictionaryWithContext:(OOShipSaveContext*)context
{
    oo::PList::Dict result;
    OOShipSaveContext localContext;
    if (context == nullptr)
        context = &localContext;

    result[KEY_SHIP_KEY] = oo::StdString(_shipKey);

    oo::PList::Dict updatedShipInfo = DictFrom(oo::PListFrom(shipinfoDictionary));

    // A role set without a role string (nil before, which -setObject:forKey: refused) adds no key.
    if (const std::optional<std::string> roleString = [[self roleSet] roleString])
        updatedShipInfo[KEY_ROLES] = *roleString;
    updatedShipInfo[KEY_FUEL] = oo::PList::unsignedInteger(fuel);
    updatedShipInfo[KEY_BOUNTY] = oo::PList::unsignedInteger(bounty);
    updatedShipInfo[KEY_FORWARD_WEAPON] = oo::StdString(OOStringFromWeaponType(forward_weapon_type));
    updatedShipInfo[KEY_AFT_WEAPON] = oo::StdString(OOStringFromWeaponType(aft_weapon_type));
    updatedShipInfo[KEY_SCAN_CLASS] = oo::StdString(OOStringFromScanClass(scanClass));

    std::vector<std::string> deletes;
    [self simplifyShipdata:updatedShipInfo andGetDeletes:&deletes];

    result[KEY_SHIPDATA_OVERRIDES] = oo::PList(std::move(updatedShipInfo));
    if (!deletes.empty())
        result[KEY_SHIPDATA_DELETES] = ArrayFromStrings(deletes);

    if (!HPvector_equal([self position], kZeroHPVector)) {
        result[KEY_POSITION] = oo::PListFrom(OOPropertyListFromHPVector([self position]));
    }
    if (!quaternion_equal([self normalOrientation], kIdentityQuaternion)) {
        result[KEY_ORIENTATION] = oo::PListFrom(OOPropertyListFromQuaternion([self normalOrientation]));
    }

    // -oo_setFloat:forKey: stored a double.
    if (energy != maxEnergy)
        result[KEY_ENERGY_LEVEL] = oo::PList(static_cast<double>(energy / maxEnergy));

    result[KEY_PRIMARY_ROLE] = oo::StdString([self primaryRole]);

    // Add equipment.
    const std::vector<std::string> equipment = oo::StringsFrom([self equipmentEnumerator]);
    if (equipment.size() != 0)
        result[KEY_EQUIPMENT] = ArrayFromStrings(equipment);

    // Add missiles.
    if (missiles > 0) {
        std::vector<std::string> missileArray;
        unsigned i;
        for (i = 0; i < missiles; i++) {
            const std::optional<std::string> missileType = oo::OptionalString([missile_list[i] identifier]);
            if (missileType.has_value())
                missileArray.push_back(*missileType);
        }
        result[KEY_MISSILES] = ArrayFromStrings(missileArray);
    }

    // Add groups.
    if (_group != nil) {
        result[KEY_GROUP_ID] = oo::PList::unsignedInteger(GroupIDForGroup(_group, *context));
        if ([_group leader] == self)
            result[KEY_IS_GROUP_LEADER] = oo::PList(static_cast<bool>(YES));
        const std::optional<std::string> groupName = oo::OptionalString([_group name]);
        if (groupName.has_value()) {
            result[KEY_GROUP_NAME] = *groupName;
        }
    }
    if (_escortGroup != nil) {
        result[KEY_ESCORT_GROUP_ID] = oo::PList::unsignedInteger(GroupIDForGroup(_escortGroup, *context));
    }
    /*	Eric:
            The escortGroup property is removed from the lead ship, on entering witchspace.
            But it is needed in the save file to correctly restore an escorted group.
    */
    else if (_group != nil && [_group leader] == self) {
        result[KEY_ESCORT_GROUP_ID] = oo::PList::unsignedInteger(GroupIDForGroup(_group, *context));
    }

    // FIXME: AI.
    // Eric: I think storing the AI name should be enough. On entering a wormhole, the stack is cleared so there are no preserved AI states.
    // Also the AI restarts itself with the GLOBAL state, so no need to store any old state.
    if (oo::StdString([[self getAI] name]) == "nullAI.plist") {
        // might be a JS version (with none, no key: -setObject:forKey: refused nil)
        if (const std::optional<std::string> js = [[self getAI] cxx_associatedJS])
            result[KEY_AI] = *js;
        // if there isn't, loading nullAI.js will load nullAI.plist anyway
    } else {
        result[KEY_AI] = oo::StdString([[self getAI] name]);
    }

    return oo::PList(std::move(result));
}

+ (id)shipRestoredFromDictionary:(const oo::PList&)dict
                     useFallback:(BOOL)fallback
                         context:(OOShipSaveContext*)context
{
    if (dict.isNull())
        return nil;
    OOShipSaveContext localContext;
    if (context == nullptr)
        context = &localContext;

    ShipEntity* ship = nil;

    const std::string shipKey = dict.get<std::string>(KEY_SHIP_KEY); // "" finds no ship, as nil did
    const oo::PList shipData = oo::PListFrom([[OOShipRegistry sharedRegistry] shipInfoForKey:oo::NSStringFrom(shipKey)]);

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

        // One Objective-C dictionary for both callees, as before.
        id definition = oo::ObjectFromPList(oo::PList(std::move(mergedData)));
        Class shipClass = [UNIVERSE shipClassForShipDictionary:definition];
        ship = [[[shipClass alloc] initWithKey:oo::NSStringFrom(shipKey) definition:definition] autorelease];

        // FIXME: restore AI.
        [ship setAITo:oo::NSStringFrom(dict.get<std::string>(KEY_AI, "nullAI.plist"))];

        [ship setPrimaryRole:oo::NSStringOrNil(OptionalStringForKey(dict, KEY_PRIMARY_ROLE))];

    } else {
        // Unknown ship; fall back on role if desired and possible.
        const std::optional<std::string> shipPrimaryRole = OptionalStringForKey(dict, KEY_PRIMARY_ROLE);
        if (!fallback || !shipPrimaryRole.has_value())
            return nil;

        ship = [[UNIVERSE newShipWithRole:oo::NSStringFrom(*shipPrimaryRole)] autorelease];
        if (ship == nil)
            return nil;
    }

    // The following stuff is deliberately set up the same way even if using role fallback.
    [ship setPosition:OOHPVectorFromObject(ObjectForKey(dict, KEY_POSITION), kZeroHPVector)];
    [ship setNormalOrientation:OOQuaternionFromObject(ObjectForKey(dict, KEY_ORIENTATION), kIdentityQuaternion)];

    float energyLevel = dict.get<float>(KEY_ENERGY_LEVEL, 1.0f);
    [ship setEnergy:energyLevel * [ship maxEnergy]];

    [ship removeAllEquipment];
    if (const oo::PList* equipment = dict.get<oo::PList::Array>(KEY_EQUIPMENT)) {
        for (const oo::PList& eqKey : *equipment->getIf<oo::PList::Array>()) {
            [ship addEquipmentItem:oo::ObjectFromPList(eqKey) withValidation:NO inContext:@"loading"];
        }
    }

    [ship removeMissiles];
    if (const oo::PList* missileList = dict.get<oo::PList::Array>(KEY_MISSILES)) {
        for (const oo::PList& eqKey : *missileList->getIf<oo::PList::Array>()) {
            [ship addEquipmentItem:oo::ObjectFromPList(eqKey) withValidation:NO inContext:@"loading"];
        }
    }

    // Groups.
    NSUInteger groupID = dict.get<NSInteger>(KEY_GROUP_ID, NSNotFound);
    if (groupID != NSNotFound) {
        OOShipGroup* group = GroupForGroupID(groupID, *context);
        [ship setGroup:group]; // Handles adding to group
        if (dict.get<bool>(KEY_IS_GROUP_LEADER))
            [group setLeader:ship];
        const std::optional<std::string> groupName = OptionalStringForKey(dict, KEY_GROUP_NAME);
        if (groupName.has_value())
            [group setName:oo::NSStringFrom(*groupName)];
        if ([ship hasPrimaryRole:@"escort"] && ship != [group leader]) {
            [ship setOwner:[group leader]];
        }
    }

    groupID = dict.get<NSInteger>(KEY_ESCORT_GROUP_ID, NSNotFound);
    if (groupID != NSNotFound) {
        OOShipGroup* group = GroupForGroupID(groupID, *context);
        [group setLeader:ship];
        [group setName:@"escort group"];
        [ship setEscortGroup:group];
    }

    return ship;
}

- (void)simplifyShipdata:(oo::PList::Dict&)data andGetDeletes:(std::vector<std::string>*)deletes
{
    NSParameterAssert(deletes != NULL);
    deletes->clear();

    // Get original ship data.
    oo::PList::Dict referenceData = DictFrom(oo::PListFrom([[OOShipRegistry sharedRegistry] shipInfoForKey:[self shipDataKey]]));

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

@end

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
    oo::ObjCRef<OOShipGroup*>& group = context.groupsByID[groupID];
    if (group.get() == nil) {
        group = oo::adoptObjC([[OOShipGroup alloc] init]);
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

// -objectForKey: for a callee that still takes an Objective-C object (nil when absent).
id ObjectForKey(const oo::PList& dict, std::string_view key)
{
    const oo::PList* value = dict.find(key);
    return value != nullptr ? oo::ObjectFromPList(*value) : nil;
}

} // namespace
