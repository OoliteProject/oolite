/*

OOPlanetDescriptionManager.h

Singleton class responsible for planet description data.

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

#include "OOSystemDescriptionManager.h"
#include "OOStringParsing.h"
#include "OOTypes.h"
#include "PlayerEntity.h"
#include "ResourceManager.h"
#include "Universe.h"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"

namespace {

// character sequence which can't be in property name, system key or layer
// and is highly unlikely to be in a manifest identifier
constexpr std::string_view kOOScriptedChangeJoiner = "~|~";

}

// likely maximum number of planetinfo properties to be applied to a system
// just for efficiency - no harm in exceeding it
#define OO_LIKELY_PROPERTIES_PER_SYSTEM 50

namespace {

constexpr const char* kOOSystemLayerProperty = "layer";

// A layer number read from data, as an OOSystemLayer. 0-3 are the layers themselves; anything
// else (only a hand-edited saved game gives one) takes the rule -setProperties:inDescription:
// applies to a bad layer number, OO_LAYER_OXP_PRIORITY, read as the enum's own unsigned
// underlying type would read it, so a negative number is a large one. Clamping as an integer
// means the enum is only ever given one of its own values; the bare cast this replaces was
// undefined for any other value and then indexed past layers[] (bead oo-2eby).
OOSystemLayer OOSystemLayerFromNumber(unsigned int number)
{
    return (number > OO_LAYER_OXP_PRIORITY) ? OO_LAYER_OXP_PRIORITY : static_cast<OOSystemLayer>(number);
}

// ScanTokensFromString(key) as a property-list array, so at<NSUInteger>(i) reads a token as the
// collection extractors read it from the token array.
oo::PList KeyTokens(const std::string& key)
{
    const std::vector<std::string> tokens = oo::str::tokens(key);
    return oo::PList(oo::PList::Array(tokens.begin(), tokens.end()));
}

// [dict objectForKey:key] of a property dictionary, as a value (null = nil).
oo::PList ValueForKey(const oo::PList& dict, const std::string& key)
{
    const oo::PList* value = dict.find(key);
    return value != nullptr ? *value : oo::PList();
}

// get<std::string> as the string extractor answered it: nullopt where that was nil (no such key,
// or neither a string nor a number).
std::optional<std::string> StringForKey(const oo::PList& dict, const char* key)
{
    const oo::PList* value = dict.find(key);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return dict.get<std::string>(key);
}

}

OOSystemDescriptionManager::OOSystemDescriptionManager()
{
    universalProperties = oo::PList(oo::PList::Dict());
    interstellarSpace = oo::makeRef<OOSystemDescriptionEntry>();
    for (NSUInteger i = 0; i < OO_SYSTEM_CACHE_LENGTH; i++) {
        propertyCache[i] = oo::PList(oo::PList::Dict());
        // hub count of 24 is considerably higher than occurs in
        // standard planetinfo
        neighbourCache[i].reserve(24);
    }
    scriptedChanges = oo::PList(oo::PList::Dict());
}

void OOSystemDescriptionManager::buildRouteCache()
{
    NSUInteger i, j, k, jIndex, kIndex;
    // firstly, cache all coordinates
    for (i = 0; i < OO_SYSTEM_CACHE_LENGTH; i++) {
        // (nil and "" both have no tokens: the zero point)
        coordinatesCache[i] = cxx_PointFromString(StringForKey(propertyCache[i], "coordinates").value_or(""));
    }
    // now for each system find its neighbours
    for (i = 0; i < OO_GALAXIES_AVAILABLE; i++) {
        // one galaxy at a time
        for (j = 0; j < OO_SYSTEMS_PER_GALAXY; j++) {
            jIndex = j + (i * OO_SYSTEMS_PER_GALAXY);
            for (k = j + 1; k < OO_SYSTEMS_PER_GALAXY; k++) {
                kIndex = k + (i * OO_SYSTEMS_PER_GALAXY);
                if (distanceBetweenPlanetPositions(coordinatesCache[jIndex].x, coordinatesCache[jIndex].y, coordinatesCache[kIndex].x, coordinatesCache[kIndex].y) <= MAX_JUMP_RANGE) {
                    // arrays are of system number only
                    neighbourCache[jIndex].push_back(static_cast<OOSystemID>(k));
                    neighbourCache[kIndex].push_back(static_cast<OOSystemID>(j));
                }
            }
        }
    }
}

void OOSystemDescriptionManager::setUniversalProperties(const oo::PList& properties)
{
    if (const oo::PList::Dict* entries = properties.getIf<oo::PList::Dict>()) {
        oo::PList::Dict& universal = *universalProperties.getIf<oo::PList::Dict>();
        for (const auto& [property, value] : *entries) {
            universal.insert_or_assign(property, value);
            propertiesInUse.insert(property);
        }
    }
    for (NSUInteger i = 0; i < OO_SYSTEM_CACHE_LENGTH; i++) {
        updateCacheEntry(i);
    }
}

void OOSystemDescriptionManager::setInterstellarProperties(const oo::PList& properties)
{
    setProperties(properties, interstellarSpace.get());
}

void OOSystemDescriptionManager::setProperties(const oo::PList& properties, const std::string& key)
{
    oo::Ref<OOSystemDescriptionEntry>& desc = systemDescriptions[key];
    if (desc.get() == nullptr) {
        // create it
        desc = oo::makeRef<OOSystemDescriptionEntry>();
    }
    setProperties(properties, desc.get());
    if (const oo::PList::Dict* entries = properties.getIf<oo::PList::Dict>()) {
        for (const auto& [property, value] : *entries)
            propertiesInUse.insert(property);
    }

    const oo::PList tokens = KeyTokens(key);
    if (tokens.count() == 2 && tokens.at<NSUInteger>(0) < OO_GALAXIES_AVAILABLE && tokens.at<NSUInteger>(1) < OO_SYSTEMS_PER_GALAXY) {
        OOGalaxyID g = tokens.at<NSUInteger>(0);
        OOSystemID s = tokens.at<NSUInteger>(1);
        NSUInteger index = (g * OO_SYSTEMS_PER_GALAXY) + s;
        if (index >= OO_SYSTEM_CACHE_LENGTH) {
            OO_LOG("system.description.error", "'{}' is an invalid system key. This is an internal error. Please report it.", key);
        } else {
            updateCacheEntry(index);
        }
    }
}

void OOSystemDescriptionManager::setProperty(const std::string& property, const std::string& key, OOSystemLayer layer, const oo::PList& value, const std::optional<std::string>& manifest)
{
    oo::Ref<OOSystemDescriptionEntry>& desc = systemDescriptions[key];
    if (desc.get() == nullptr) {
        // create it
        desc = oo::makeRef<OOSystemDescriptionEntry>();
    }
    desc->setProperty(property, layer, value);
    propertiesInUse.insert(property);

    const oo::PList tokens = KeyTokens(key);
    if (tokens.count() == 2 && tokens.at<NSUInteger>(0) < OO_GALAXIES_AVAILABLE && tokens.at<NSUInteger>(1) < OO_SYSTEMS_PER_GALAXY) {
        saveScriptedChangeToProperty(property, key, layer, value, manifest);

        OOGalaxyID g = tokens.at<NSUInteger>(0);
        OOSystemID s = tokens.at<NSUInteger>(1);
        NSUInteger index = (g * OO_SYSTEMS_PER_GALAXY) + s;
        if (index >= OO_SYSTEM_CACHE_LENGTH) {
            OO_LOG("system.description.error", "'{}' is an invalid system key. This is an internal error. Please report it.", key);
        } else {
            updateCacheEntry(index, property);
        }
    }
    // for interstellar updates, save but don't update cache
    else if (tokens.count() == 4 && tokens.at<NSUInteger>(1) < OO_GALAXIES_AVAILABLE && tokens.at<NSUInteger>(2) < OO_SYSTEMS_PER_GALAXY && tokens.at<NSUInteger>(3) < OO_SYSTEMS_PER_GALAXY) {
        saveScriptedChangeToProperty(property, key, layer, value, manifest);
    }
}

void OOSystemDescriptionManager::saveScriptedChangeToProperty(const std::string& property, const std::string& key, OOSystemLayer layer, const oo::PList& value, const std::optional<std::string>& manifest)
{
    // if OXP doesn't have a manifest, cancel saving the change
    if (!manifest.has_value()) {
        return;
    }
    //	OO_LOG("saving change", "{} {} {} {}", oo::DescriptionOf(manifest), oo::DescriptionOf(key), oo::DescriptionOf(property), static_cast<int>(layer));
    // The four parts (the layer as its number's text) joined into one key: the plist
    // format can't have array keys, so they couldn't be saved.
    std::string overrideKeyStr = *manifest;
    overrideKeyStr += kOOScriptedChangeJoiner;
    overrideKeyStr += key;
    overrideKeyStr += kOOScriptedChangeJoiner;
    overrideKeyStr += property;
    overrideKeyStr += kOOScriptedChangeJoiner;
    overrideKeyStr += std::to_string(static_cast<int>(layer));
    oo::PList::Dict& changes = *scriptedChanges.getIf<oo::PList::Dict>();
    if (!value.isNull()) {
        changes[overrideKeyStr] = value;
    } else {
        changes.erase(overrideKeyStr);
    }
}

void OOSystemDescriptionManager::importScriptedChanges(const oo::PList& scripted)
{
    const oo::PList::Dict* changes = scripted.getIf<oo::PList::Dict>();
    if (changes == nullptr)
        return;
    // (in key order; was hash order: a later key overwrites the same property and layer)
    for (const auto& [keyStr, value] : *changes) {
        const std::vector<std::string> key = oo::str::split(keyStr, kOOScriptedChangeJoiner);
        if (key.size() == 4) {
            const std::string& manifest = key[0];
            if (!ResourceManager::manifestForIdentifier(manifest).isNull()) {
                //				OO_LOG("importing", "{} -> {}", oo::DescriptionOf(keyStr), oo::DescriptionOf([scripted objectForKey:keyStr]));
                setProperty(key[2],
                    key[1],
                    OOSystemLayerFromNumber(static_cast<unsigned int>(oo::str::intValue(key[3]))),
                    value,
                    manifest);
                // and doing this set stores it into the manager's copy
                // of scripted changes
                // this means in theory we could import more than one
            }
            // else OXP not installed, do not load
        } else {
            OO_LOG("systemManager.import", "Key '{}' has unexpected format - skipping", keyStr);
        }
    }
}

// import of the old local_planetinfo_overrides dictionary
void OOSystemDescriptionManager::importLegacyScriptedChanges(const oo::PList& scripted)
{
    const oo::PList::Dict* systems = scripted.getIf<oo::PList::Dict>();
    if (systems == nullptr)
        return;
    const std::string defaultManifest = "org.oolite.oolite";

    // (systems and properties in key order; was hash order: each is set once)
    for (const auto& [systemKey, systemChanges] : *systems) {
        if (systemChanges.isDict() && systemChanges.find("sun_gone_nova") != nullptr) {
            // then this is a change to import even if we don't know
            // if the OXP is still installed
            for (const auto& [propertyKey, value] : *systemChanges.getIf<oo::PList::Dict>()) {
                setProperty(propertyKey,
                    systemKey,
                    OO_LAYER_OXP_DYNAMIC,
                    value,
                    defaultManifest);
            }
            /* Fix for older savegames not having a larger sun radius
             * property set from the Nova mission. */
            // -floatValue of the value (0 for nil)
            const oo::PList sr = getProperty("sun_radius", systemKey);
            float sr_num = oo::plist_get::realFrom<float>(&sr, 0.0f);
            if (sr_num < 600000) {
                // fix sun radius values (a float: written to disk as a single real)
                setProperty("sun_radius",
                    systemKey,
                    OO_LAYER_OXP_DYNAMIC,
                    oo::PList::singleReal(sr_num + 600000.0f),
                    defaultManifest);
            }
        }
    }
}

oo::PList OOSystemDescriptionManager::exportScriptedChanges()
{
    return scriptedChanges;
}

oo::PList OOSystemDescriptionManager::getPropertiesForCurrentSystem()
{
    OOSystemID s = (UNIVERSE != nullptr ? UNIVERSE->currentSystemID() : 0);
    if (s >= 0) {
        NSUInteger index = ((PLAYER != nullptr ? PLAYER->PlayerEntity::galaxyNumber() : OOGalaxyID { }) * OO_SYSTEMS_PER_GALAXY) + s; // qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
        if (index >= OO_SYSTEM_CACHE_LENGTH) {
            OO_LOG("system.description.error", "'{}' is an invalid system index for the current system. This is an internal error. Please report it.", static_cast<size_t>(index));
            return oo::PList(oo::PList::Dict());
        }
        return propertyCache[index];
    } else {
        OO_LOG("system.description.error", "{}", "getPropertiesForCurrentSystem called while player in interstellar space. This is an internal error. Please report it.");
        // this shouldn't be called for interstellar space
        return oo::PList(oo::PList::Dict());
    }
}

oo::PList OOSystemDescriptionManager::getPropertiesForSystemKey(const std::string& key)
{
    const oo::PList tokens = KeyTokens(key);
    if (tokens.count() == 2 && tokens.at<NSUInteger>(0) < OO_GALAXIES_AVAILABLE && tokens.at<NSUInteger>(1) < OO_SYSTEMS_PER_GALAXY) {
        OOGalaxyID g = tokens.at<NSUInteger>(0);
        OOSystemID s = tokens.at<NSUInteger>(1);
        NSUInteger index = (g * OO_SYSTEMS_PER_GALAXY) + s;
        if (index >= OO_SYSTEM_CACHE_LENGTH) {
            OO_LOG("system.description.error", "'{}' is an invalid system key. This is an internal error. Please report it.", key);
            return oo::PList(oo::PList::Dict());
        }
        return propertyCache[index];
    }
    // interstellar spaces aren't cached
    return calculatePropertiesForSystemKey(key);
}

oo::PList OOSystemDescriptionManager::getPropertiesForSystem(OOSystemID s, OOGalaxyID g)
{
    NSUInteger index = (g * OO_SYSTEMS_PER_GALAXY) + s;
    if (index >= OO_SYSTEM_CACHE_LENGTH) {
        OO_LOG("system.description.error", "'{}, {}' is an invalid system. This is an internal error. Please report it.", static_cast<unsigned>(g), static_cast<unsigned>(s));
        return oo::PList(oo::PList::Dict());
    }
    return propertyCache[index];
}

oo::PList OOSystemDescriptionManager::getProperty(const std::string& property, const std::string& key)
{
    return getProperty(property, key, YES);
}

oo::PList OOSystemDescriptionManager::getProperty(const std::string& property, OOSystemID s, OOGalaxyID g)
{
    if (s < 0) {
        OO_LOG("system.description.error", "'{} {}' is an invalid system key. This is an internal error. Please report it.", static_cast<int>(g), static_cast<int>(s));
        return oo::PList();
    }
    NSUInteger index = (g * OO_SYSTEMS_PER_GALAXY) + s;
    if (index >= OO_SYSTEM_CACHE_LENGTH) {
        OO_LOG("system.description.error", "'{} {}' is an invalid system key. This is an internal error. Please report it.", static_cast<int>(g), static_cast<int>(s));
        return oo::PList();
    }
    return ValueForKey(propertyCache[index], property);
}

oo::PList OOSystemDescriptionManager::getProperty(const std::string& property, const std::string& key, bool universal)
{
    OOSystemDescriptionEntry* desc = nullptr;
    if (EXPECT_NOT(key == "interstellar")) {
        desc = interstellarSpace.get();
    } else {
        auto entry = systemDescriptions.find(key);
        if (entry != systemDescriptions.end())
            desc = entry->second.get();
    }
    if (desc == nullptr) {
        return oo::PList();
    }
    oo::PList result = desc->getProperty(property, OO_LAYER_OXP_PRIORITY);
    if (result.isNull()) {
        result = desc->getProperty(property, OO_LAYER_OXP_DYNAMIC);
    }
    if (result.isNull()) {
        result = desc->getProperty(property, OO_LAYER_OXP_STATIC);
    }
    if (result.isNull() && universal) {
        result = ValueForKey(universalProperties, property);
    }
    if (result.isNull()) {
        result = desc->getProperty(property, OO_LAYER_CORE);
    }
    return result;
}

oo::PList OOSystemDescriptionManager::getProperty(const std::string& property1, const std::string& property2, const std::string& key, bool universal)
{
    auto entry = systemDescriptions.find(key);
    if (entry == systemDescriptions.end() || entry->second.get() == nullptr) {
        return oo::PList();
    }
    OOSystemDescriptionEntry* desc = entry->second.get();
    oo::PList result = desc->getProperty(property1, OO_LAYER_OXP_PRIORITY);
    if (result.isNull()) {
        result = desc->getProperty(property2, OO_LAYER_OXP_PRIORITY);
    }
    if (result.isNull()) {
        result = desc->getProperty(property1, OO_LAYER_OXP_DYNAMIC);
    }
    if (result.isNull()) {
        result = desc->getProperty(property2, OO_LAYER_OXP_DYNAMIC);
    }
    if (result.isNull()) {
        result = desc->getProperty(property1, OO_LAYER_OXP_STATIC);
    }
    if (result.isNull()) {
        result = desc->getProperty(property2, OO_LAYER_OXP_STATIC);
    }
    if (universal) {
        if (result.isNull()) {
            result = ValueForKey(universalProperties, property1);
        }
        if (result.isNull()) {
            result = ValueForKey(universalProperties, property2);
        }
    }
    if (result.isNull()) {
        result = desc->getProperty(property1, OO_LAYER_CORE);
    }
    if (result.isNull()) {
        result = desc->getProperty(property2, OO_LAYER_CORE);
    }
    return result;
}

void OOSystemDescriptionManager::setProperties(const oo::PList& properties, OOSystemDescriptionEntry* desc)
{
    // Range-checked as the number it is read as, then converted: the enum only ever holds a layer.
    unsigned int layerNumber = properties.get<unsigned int>(kOOSystemLayerProperty, OO_LAYER_OXP_STATIC);
    if (layerNumber > OO_LAYER_OXP_PRIORITY) {
        OO_LOG("system.description.error", "Layer {} is not a valid layer number in system information.", static_cast<unsigned>(layerNumber));
    }
    OOSystemLayer layer = OOSystemLayerFromNumber(layerNumber);
    const oo::PList::Dict* entries = properties.getIf<oo::PList::Dict>();
    if (entries == nullptr)
        return;
    // (in key order; was hash order: each key is set once)
    for (const auto& [key, value] : *entries) {
        if (key != kOOSystemLayerProperty) {
            propertiesInUse.insert(key);
            desc->setProperty(key, layer, value);
        }
    }
}

oo::PList OOSystemDescriptionManager::calculatePropertiesForSystemKey(const std::string& key)
{
    oo::PList::Dict dict;
    BOOL interstellar = oo::str::hasPrefix(key, "interstellar:");
    for (const std::string& property : propertiesInUse) {
        // don't use universal properties on interstellar specific regions
        oo::PList val = getProperty(property, key, !interstellar);

        if (!val.isNull()) {
            dict[property] = std::move(val);
        } else if (interstellar) {
            // interstellar is always overridden by specific regions
            // universal properties for interstellar get picked up here
            val = getProperty(property, "interstellar", YES);
            if (!val.isNull()) {
                dict[property] = std::move(val);
            }
        }
    }
    return oo::PList(std::move(dict));
}

void OOSystemDescriptionManager::updateCacheEntry(NSUInteger i)
{
    OOCAssert(i < static_cast<NSUInteger>(OO_SYSTEM_CACHE_LENGTH), "Invalid cache entry number"); // (the cast: tier-a re-keyed a pre-existing widening finding when OOAssert became OOCAssert)
    const std::string key = oo::str::format("%zu %zu", i / OO_SYSTEMS_PER_GALAXY, i % OO_SYSTEMS_PER_GALAXY);
    propertyCache[i] = calculatePropertiesForSystemKey(key);
}

void OOSystemDescriptionManager::updateCacheEntry(NSUInteger i, const std::string& property)
{
    OOCAssert(i < static_cast<NSUInteger>(OO_SYSTEM_CACHE_LENGTH), "Invalid cache entry number"); // (the cast: tier-a re-keyed a pre-existing widening finding when OOAssert became OOCAssert)
    const std::string key = oo::str::format("%zu %zu", i / OO_SYSTEMS_PER_GALAXY, i % OO_SYSTEMS_PER_GALAXY);
    oo::PList current = getProperty(property, key);
    oo::PList::Dict& cache = *propertyCache[i].getIf<oo::PList::Dict>();
    if (current.isNull()) {
        cache.erase(property);
    } else {
        cache[property] = std::move(current);
    }
}

NSPoint OOSystemDescriptionManager::getCoordinatesForSystem(OOSystemID s, OOGalaxyID g)
{
    if (s < 0) {
        OO_LOG("system.description.error", "'{} {}' is an invalid system key. This is an internal error. Please report it.", static_cast<int>(g), static_cast<int>(s));
        return (NSPoint) { 0, 0 };
    }
    NSUInteger index = (g * OO_SYSTEMS_PER_GALAXY) + s;
    if (index >= OO_SYSTEM_CACHE_LENGTH) {
        OO_LOG("system.description.error", "'{} {}' is an invalid system key. This is an internal error. Please report it.", static_cast<int>(g), static_cast<int>(s));
        return (NSPoint) { 0, 0 };
    }
    return coordinatesCache[index];
}

std::vector<OOSystemID> OOSystemDescriptionManager::getNeighbourIDsForSystem(OOSystemID s, OOGalaxyID g)
{
    if (s < 0) {
        OO_LOG("system.description.error", "'{} {}' is an invalid system key. This is an internal error. Please report it.", static_cast<int>(g), static_cast<int>(s));
        return { };
    }
    NSUInteger index = (g * OO_SYSTEMS_PER_GALAXY) + s;
    if (index >= OO_SYSTEM_CACHE_LENGTH) {
        OO_LOG("system.description.error", "'{} {}' is an invalid system key. This is an internal error. Please report it.", static_cast<int>(g), static_cast<int>(s));
        return { };
    }

    return neighbourCache[index];
}

Random_Seed OOSystemDescriptionManager::getRandomSeedForCurrentSystem()
{
    if ((UNIVERSE != nullptr ? UNIVERSE->currentSystemID() : 0) < 0) {
        return kNilRandomSeed;
    } else {
        OOSystemID s = (UNIVERSE != nullptr ? UNIVERSE->currentSystemID() : 0);
        NSUInteger index = ((PLAYER != nullptr ? PLAYER->PlayerEntity::galaxyNumber() : OOGalaxyID { }) * OO_SYSTEMS_PER_GALAXY) + s; // qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
        if (index >= OO_SYSTEM_CACHE_LENGTH) {
            OO_LOG("system.description.error", "'{}' is an invalid system index for the current system. This is an internal error. Please report it.", static_cast<size_t>(index));
            return kNilRandomSeed;
        }
        // (nullopt reads as nil did)
        return cxx_RandomSeedFromString(StringForKey(propertyCache[index], "random_seed"));
    }
}

Random_Seed OOSystemDescriptionManager::getRandomSeedForSystem(OOSystemID s, OOGalaxyID g)
{
    if (s < 0) {
        OO_LOG("system.description.error", "'{} {}' is an invalid system key. This is an internal error. Please report it.", static_cast<int>(g), static_cast<int>(s));
        return kNilRandomSeed;
    }
    NSUInteger index = (g * OO_SYSTEMS_PER_GALAXY) + s;
    if (index >= OO_SYSTEM_CACHE_LENGTH) {
        OO_LOG("system.description.error", "'{} {}' is an invalid system key. This is an internal error. Please report it.", static_cast<int>(g), static_cast<int>(s));
        return kNilRandomSeed;
    }
    return cxx_RandomSeedFromString(StringForKey(propertyCache[index], "random_seed"));
}

OOSystemDescriptionEntry::OOSystemDescriptionEntry()
{
    for (NSUInteger i = 0; i < OO_SYSTEM_LAYERS; i++) {
        layers[i] = oo::PList(oo::PList::Dict());
    }
}

void OOSystemDescriptionEntry::setProperty(const std::string& property, OOSystemLayer layer, const oo::PList& value)
{
    oo::PList::Dict& properties = *layers[layer].getIf<oo::PList::Dict>();
    if (value.isNull()) {
        properties.erase(property);
    } else {
        // validate type of object for certain properties
        oo::PList validated = validateProperty(property, value);
        // if it's nil now, validation failed and could not be recovered
        // so don't actually set anything
        if (!validated.isNull()) {
            properties[property] = std::move(validated);
        }
    }
}

oo::PList OOSystemDescriptionEntry::getProperty(const std::string& property, OOSystemLayer layer)
{
    return ValueForKey(layers[layer], property);
}

/* Mostly the rest of the game gets a system dictionary from
 * [UNIVERSE currentSystemData] or similar, which means that it uses
 * safe methods like get<std::string> - a few things use a direct call
 * to getProperty for various reasons, so need some type validation
 * here instead. */
oo::PList OOSystemDescriptionEntry::validateProperty(const std::string& property, const oo::PList& value)
{
    // OOLog's %@ of the value: its object, as it was before it became a property list
    if (property == "coordinates") {
        // must be a string with two numbers in it
        // TODO: convert two element arrays
        if (!value.isString()) {
            OO_LOG("system.description.error", "'{}' is not a valid format for coordinates", oo::DescriptionOf(value));
            return oo::PList();
        }
        if (oo::str::tokens(*value.getIf<std::string>()).size() != 2) {
            OO_LOG("system.description.error", "'{}' is not a valid format for coordinates (must have exactly two numbers)", oo::DescriptionOf(value));
            return oo::PList();
        }
    } else if (property == "radius" || property == "government") {
        // read in a context which expects a string, but it's a string representation of a number
        if (!value.isString()) {
            if (value.isNumber()) {
                // -stringValue
                return oo::PList(oo::plist_get::numberStringValue(value));
            } else {
                OO_LOG("system.description.error", "'{}' is not a valid value for '{}' (string required)", oo::DescriptionOf(value), property);
                return oo::PList();
            }
        }
    } else if (property == "inhabitant" || property == "inhabitants" || property == "name") {
        // read in a context which expects a string
        if (!value.isString()) {
            OO_LOG("system.description.error", "'{}' is not a valid value for '{}' (string required)", oo::DescriptionOf(value), property);
            return oo::PList();
        }
    }

    return value;
}
