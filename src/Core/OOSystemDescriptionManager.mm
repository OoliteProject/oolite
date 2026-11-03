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

#import "OOSystemDescriptionManager.h"
#import "OOFoundationBridge.h"
#import "OOPListView.h"
#import "OOStringParsing.h"
#import "OOTypes.h"
#import "PlayerEntity.h"
#import "ResourceManager.h"
#import "Universe.h"
#include "oofnd/objc/OOAssert.h"

namespace {

// character sequence which can't be in property name, system key or layer
// and is highly unlikely to be in a manifest identifier
constexpr std::string_view kOOScriptedChangeJoiner = "~|~";

}

// likely maximum number of planetinfo properties to be applied to a system
// just for efficiency - no harm in exceeding it
#define OO_LIKELY_PROPERTIES_PER_SYSTEM 50

@interface OOSystemDescriptionManager (OOPrivate)
// Property dictionaries are oo::PList Dicts; a single property value is an oo::PList (null = nil).
- (void)setProperties:(const oo::PList&)properties inDescription:(OOSystemDescriptionEntry*)desc;
- (oo::PList)calculatePropertiesForSystemKey:(const std::string&)key;
- (void)updateCacheEntry:(NSUInteger)i;
- (void)updateCacheEntry:(NSUInteger)i forProperty:(const std::string&)property;
- (oo::PList)getProperty:(const std::string&)property forSystemKey:(const std::string&)key withUniversal:(BOOL)universal;
/* some planetinfo properties have two ways to specify
 * need to get the one with higher layer (if they're both at the same layer,
 * go with property1) */
- (oo::PList)getProperty:(const std::string&)property1 orProperty:(const std::string&)property2 forSystemKey:(const std::string&)key withUniversal:(BOOL)universal;

// value null = nil (removes the saved change); manifest nullopt = nil (cancels saving it)
- (void)saveScriptedChangeToProperty:(const std::string&)property forSystemKey:(const std::string&)key andLayer:(OOSystemLayer)layer toValue:(const oo::PList&)value fromManifest:(const std::optional<std::string>&)manifest;

@end

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

@implementation OOSystemDescriptionManager

- (id)init
{
    self = [super init];
    if (self != nil) {
        universalProperties = oo::PList(oo::PList::Dict());
        interstellarSpace = [[OOSystemDescriptionEntry alloc] init];
        for (NSUInteger i = 0; i < OO_SYSTEM_CACHE_LENGTH; i++) {
            propertyCache[i] = oo::PList(oo::PList::Dict());
            // hub count of 24 is considerably higher than occurs in
            // standard planetinfo
            neighbourCache[i].reserve(24);
        }
        scriptedChanges = oo::PList(oo::PList::Dict());
    }
    return self;
}

- (void)dealloc
{
    DESTROY(interstellarSpace);
    [super dealloc];
}

- (void)buildRouteCache
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

- (void)cxx_setUniversalProperties:(const oo::PList&)properties
{
    if (const oo::PList::Dict* entries = properties.getIf<oo::PList::Dict>()) {
        oo::PList::Dict& universal = *universalProperties.getIf<oo::PList::Dict>();
        for (const auto& [property, value] : *entries) {
            universal.insert_or_assign(property, value);
            propertiesInUse.insert(property);
        }
    }
    for (NSUInteger i = 0; i < OO_SYSTEM_CACHE_LENGTH; i++) {
        [self updateCacheEntry:i];
    }
}

- (void)cxx_setInterstellarProperties:(const oo::PList&)properties
{
    [self setProperties:properties inDescription:interstellarSpace];
}

- (void)cxx_setProperties:(const oo::PList&)properties forSystemKey:(const std::string&)key
{
    oo::ObjCRef<OOSystemDescriptionEntry*>& desc = systemDescriptions[key];
    if (desc.get() == nil) {
        // create it
        desc = oo::ObjCRef<OOSystemDescriptionEntry*>::adopt([[OOSystemDescriptionEntry alloc] init]);
    }
    [self setProperties:properties inDescription:desc.get()];
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
            [self updateCacheEntry:index];
        }
    }
}

- (void)cxx_setProperty:(const std::string&)property forSystemKey:(const std::string&)key andLayer:(OOSystemLayer)layer toValue:(const oo::PList&)value fromManifest:(const std::optional<std::string>&)manifest
{
    oo::ObjCRef<OOSystemDescriptionEntry*>& desc = systemDescriptions[key];
    if (desc.get() == nil) {
        // create it
        desc = oo::ObjCRef<OOSystemDescriptionEntry*>::adopt([[OOSystemDescriptionEntry alloc] init]);
    }
    [desc.get() setProperty:property forLayer:layer toValue:value];
    propertiesInUse.insert(property);

    const oo::PList tokens = KeyTokens(key);
    if (tokens.count() == 2 && tokens.at<NSUInteger>(0) < OO_GALAXIES_AVAILABLE && tokens.at<NSUInteger>(1) < OO_SYSTEMS_PER_GALAXY) {
        [self saveScriptedChangeToProperty:property forSystemKey:key andLayer:layer toValue:value fromManifest:manifest];

        OOGalaxyID g = tokens.at<NSUInteger>(0);
        OOSystemID s = tokens.at<NSUInteger>(1);
        NSUInteger index = (g * OO_SYSTEMS_PER_GALAXY) + s;
        if (index >= OO_SYSTEM_CACHE_LENGTH) {
            OO_LOG("system.description.error", "'{}' is an invalid system key. This is an internal error. Please report it.", key);
        } else {
            [self updateCacheEntry:index forProperty:property];
        }
    }
    // for interstellar updates, save but don't update cache
    else if (tokens.count() == 4 && tokens.at<NSUInteger>(1) < OO_GALAXIES_AVAILABLE && tokens.at<NSUInteger>(2) < OO_SYSTEMS_PER_GALAXY && tokens.at<NSUInteger>(3) < OO_SYSTEMS_PER_GALAXY) {
        [self saveScriptedChangeToProperty:property forSystemKey:key andLayer:layer toValue:value fromManifest:manifest];
    }
}

- (void)saveScriptedChangeToProperty:(const std::string&)property forSystemKey:(const std::string&)key andLayer:(OOSystemLayer)layer toValue:(const oo::PList&)value fromManifest:(const std::optional<std::string>&)manifest
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

- (void)cxx_importScriptedChanges:(const oo::PList&)scripted
{
    const oo::PList::Dict* changes = scripted.getIf<oo::PList::Dict>();
    if (changes == nullptr)
        return;
    // (in key order; was hash order: a later key overwrites the same property and layer)
    for (const auto& [keyStr, value] : *changes) {
        const std::vector<std::string> key = oo::str::split(keyStr, kOOScriptedChangeJoiner);
        if (key.size() == 4) {
            const std::string& manifest = key[0];
            if (![ResourceManager cxx_manifestForIdentifier:manifest].isNull()) {
                //				OO_LOG("importing", "{} -> {}", oo::DescriptionOf(keyStr), oo::DescriptionOf([scripted objectForKey:keyStr]));
                [self cxx_setProperty:key[2]
                         forSystemKey:key[1]
                             andLayer:OOSystemLayerFromNumber(static_cast<unsigned int>(oo::str::intValue(key[3])))
                              toValue:value
                         fromManifest:manifest];
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
- (void)cxx_importLegacyScriptedChanges:(const oo::PList&)scripted
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
                [self cxx_setProperty:propertyKey
                         forSystemKey:systemKey
                             andLayer:OO_LAYER_OXP_DYNAMIC
                              toValue:value
                         fromManifest:defaultManifest];
            }
            /* Fix for older savegames not having a larger sun radius
             * property set from the Nova mission. */
            // -floatValue of the value (0 for nil)
            const oo::PList sr = [self cxx_getProperty:"sun_radius" forSystemKey:systemKey];
            float sr_num = oo::plist_get::realFrom<float>(&sr, 0.0f);
            if (sr_num < 600000) {
                // fix sun radius values (a float: written to disk as a single real)
                [self cxx_setProperty:"sun_radius"
                         forSystemKey:systemKey
                             andLayer:OO_LAYER_OXP_DYNAMIC
                              toValue:oo::PList::singleReal(sr_num + 600000.0f)
                         fromManifest:defaultManifest];
            }
        }
    }
}

- (oo::PList)cxx_exportScriptedChanges
{
    return scriptedChanges;
}

- (oo::PList)cxx_getPropertiesForCurrentSystem
{
    OOSystemID s = [UNIVERSE currentSystemID];
    if (s >= 0) {
        NSUInteger index = ([PLAYER galaxyNumber] * OO_SYSTEMS_PER_GALAXY) + s;
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

- (oo::PList)cxx_getPropertiesForSystemKey:(const std::string&)key
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
    return [self calculatePropertiesForSystemKey:key];
}

- (oo::PList)cxx_getPropertiesForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g
{
    NSUInteger index = (g * OO_SYSTEMS_PER_GALAXY) + s;
    if (index >= OO_SYSTEM_CACHE_LENGTH) {
        OO_LOG("system.description.error", "'{}, {}' is an invalid system. This is an internal error. Please report it.", static_cast<unsigned>(g), static_cast<unsigned>(s));
        return oo::PList(oo::PList::Dict());
    }
    return propertyCache[index];
}

- (oo::PList)cxx_getProperty:(const std::string&)property forSystemKey:(const std::string&)key
{
    return [self getProperty:property forSystemKey:key withUniversal:YES];
}

- (oo::PList)cxx_getProperty:(const std::string&)property forSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g
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

- (oo::PList)getProperty:(const std::string&)property forSystemKey:(const std::string&)key withUniversal:(BOOL)universal
{
    OOSystemDescriptionEntry* desc = nil;
    if (EXPECT_NOT(key == "interstellar")) {
        desc = interstellarSpace;
    } else {
        auto entry = systemDescriptions.find(key);
        if (entry != systemDescriptions.end())
            desc = entry->second.get();
    }
    if (desc == nil) {
        return oo::PList();
    }
    oo::PList result = [desc getProperty:property forLayer:OO_LAYER_OXP_PRIORITY];
    if (result.isNull()) {
        result = [desc getProperty:property forLayer:OO_LAYER_OXP_DYNAMIC];
    }
    if (result.isNull()) {
        result = [desc getProperty:property forLayer:OO_LAYER_OXP_STATIC];
    }
    if (result.isNull() && universal) {
        result = ValueForKey(universalProperties, property);
    }
    if (result.isNull()) {
        result = [desc getProperty:property forLayer:OO_LAYER_CORE];
    }
    return result;
}

- (oo::PList)getProperty:(const std::string&)property1 orProperty:(const std::string&)property2 forSystemKey:(const std::string&)key withUniversal:(BOOL)universal
{
    auto entry = systemDescriptions.find(key);
    if (entry == systemDescriptions.end() || entry->second.get() == nil) {
        return oo::PList();
    }
    OOSystemDescriptionEntry* desc = entry->second.get();
    oo::PList result = [desc getProperty:property1 forLayer:OO_LAYER_OXP_PRIORITY];
    if (result.isNull()) {
        result = [desc getProperty:property2 forLayer:OO_LAYER_OXP_PRIORITY];
    }
    if (result.isNull()) {
        result = [desc getProperty:property1 forLayer:OO_LAYER_OXP_DYNAMIC];
    }
    if (result.isNull()) {
        result = [desc getProperty:property2 forLayer:OO_LAYER_OXP_DYNAMIC];
    }
    if (result.isNull()) {
        result = [desc getProperty:property1 forLayer:OO_LAYER_OXP_STATIC];
    }
    if (result.isNull()) {
        result = [desc getProperty:property2 forLayer:OO_LAYER_OXP_STATIC];
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
        result = [desc getProperty:property1 forLayer:OO_LAYER_CORE];
    }
    if (result.isNull()) {
        result = [desc getProperty:property2 forLayer:OO_LAYER_CORE];
    }
    return result;
}

- (void)setProperties:(const oo::PList&)properties inDescription:(OOSystemDescriptionEntry*)desc
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
            [desc setProperty:key forLayer:layer toValue:value];
        }
    }
}

- (oo::PList)calculatePropertiesForSystemKey:(const std::string&)key
{
    oo::PList::Dict dict;
    BOOL interstellar = oo::str::hasPrefix(key, "interstellar:");
    for (const std::string& property : propertiesInUse) {
        // don't use universal properties on interstellar specific regions
        oo::PList val = [self getProperty:property forSystemKey:key withUniversal:!interstellar];

        if (!val.isNull()) {
            dict[property] = std::move(val);
        } else if (interstellar) {
            // interstellar is always overridden by specific regions
            // universal properties for interstellar get picked up here
            val = [self getProperty:property forSystemKey:"interstellar" withUniversal:YES];
            if (!val.isNull()) {
                dict[property] = std::move(val);
            }
        }
    }
    return oo::PList(std::move(dict));
}

- (void)updateCacheEntry:(NSUInteger)i
{
    OOAssert(i < OO_SYSTEM_CACHE_LENGTH, "Invalid cache entry number");
    const std::string key = oo::str::format("%zu %zu", i / OO_SYSTEMS_PER_GALAXY, i % OO_SYSTEMS_PER_GALAXY);
    propertyCache[i] = [self calculatePropertiesForSystemKey:key];
}

- (void)updateCacheEntry:(NSUInteger)i forProperty:(const std::string&)property
{
    OOAssert(i < OO_SYSTEM_CACHE_LENGTH, "Invalid cache entry number");
    const std::string key = oo::str::format("%zu %zu", i / OO_SYSTEMS_PER_GALAXY, i % OO_SYSTEMS_PER_GALAXY);
    oo::PList current = [self cxx_getProperty:property forSystemKey:key];
    oo::PList::Dict& cache = *propertyCache[i].getIf<oo::PList::Dict>();
    if (current.isNull()) {
        cache.erase(property);
    } else {
        cache[property] = std::move(current);
    }
}

- (NSPoint)getCoordinatesForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g
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

- (std::vector<OOSystemID>)cxx_getNeighbourIDsForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g
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

- (Random_Seed)getRandomSeedForCurrentSystem
{
    if ([UNIVERSE currentSystemID] < 0) {
        return kNilRandomSeed;
    } else {
        OOSystemID s = [UNIVERSE currentSystemID];
        NSUInteger index = ([PLAYER galaxyNumber] * OO_SYSTEMS_PER_GALAXY) + s;
        if (index >= OO_SYSTEM_CACHE_LENGTH) {
            OO_LOG("system.description.error", "'{}' is an invalid system index for the current system. This is an internal error. Please report it.", static_cast<size_t>(index));
            return kNilRandomSeed;
        }
        // (nullopt reads as nil did)
        return cxx_RandomSeedFromString(StringForKey(propertyCache[index], "random_seed"));
    }
}

- (Random_Seed)getRandomSeedForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g
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

@end

@interface OOSystemDescriptionEntry (OOPrivate)
// null = nil (validation failed and could not be recovered)
- (oo::PList)validateProperty:(const std::string&)property withValue:(const oo::PList&)value;
@end

@implementation OOSystemDescriptionEntry

- (id)init
{
    self = [super init];
    if (self != nil) {
        for (NSUInteger i = 0; i < OO_SYSTEM_LAYERS; i++) {
            layers[i] = oo::PList(oo::PList::Dict());
        }
    }
    return self;
}

- (void)setProperty:(const std::string&)property forLayer:(OOSystemLayer)layer toValue:(const oo::PList&)value
{
    oo::PList::Dict& properties = *layers[layer].getIf<oo::PList::Dict>();
    if (value.isNull()) {
        properties.erase(property);
    } else {
        // validate type of object for certain properties
        oo::PList validated = [self validateProperty:property withValue:value];
        // if it's nil now, validation failed and could not be recovered
        // so don't actually set anything
        if (!validated.isNull()) {
            properties[property] = std::move(validated);
        }
    }
}

- (oo::PList)getProperty:(const std::string&)property forLayer:(OOSystemLayer)layer
{
    return ValueForKey(layers[layer], property);
}

/* Mostly the rest of the game gets a system dictionary from
 * [UNIVERSE currentSystemData] or similar, which means that it uses
 * safe methods like get<std::string> - a few things use a direct call
 * to getProperty for various reasons, so need some type validation
 * here instead. */
- (oo::PList)validateProperty:(const std::string&)property withValue:(const oo::PList&)value
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

@end
