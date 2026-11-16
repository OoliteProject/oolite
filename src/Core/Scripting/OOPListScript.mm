/*

OOPListScript.h

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

#import "OOPListScript.h"
#import "OOCacheManager.h"
#import "OOLegacyScriptWhitelist.h"
#import "OOPListParsing.h"
#import "PlayerEntityLegacyScriptEngine.h"

namespace {
constexpr const char* kMDKeyName = "name";
constexpr const char* kMDKeyDescription = "description";
constexpr const char* kMDKeyVersion = "version";
constexpr const char* kKeyMetadata = "!metadata!";
constexpr const char* kKeyScript = "script";

constexpr const char* kCacheName = "sanitized legacy scripts";

} // namespace

/*	C++20 since bead oo-q9q4 (proposed ADR-0056): cxx::OOPListScript. Its superclass is still
        Objective-C, so a script object is made by its facade (amendment oo-o89 item 2): the class's
        own factories below make them with [[::OOPListScript alloc] initWithName:...], as
        [[self alloc] ...] did, and hand back the Objective-C scripts. A message to self that
        OOScript implements (-displayName) goes to the facade. The cache manager is C++ and is called
        directly.
*/

namespace cxx {

std::optional<std::vector<oo::ObjCRef<::OOScript*>>> OOPListScript::scriptsInPListFile(const std::string& filePath)
{
    OOCacheManager* cache = OOCacheManager::sharedCache();
    const oo::PList cachedScripts = (cache != nullptr) ? cache->pListForKey(filePath, kCacheName) : oo::PList();
    if (cachedScripts) {
        return loadCachedScripts(cachedScripts);
    } else {
        oo::PList dict = cxx_OOPropertyListFromFile(filePath);
        if (!dict.isDict())
            dict = oo::PList(); // a dictionary or nothing, as OODictionaryFromFile answered (its plist.wrongType line, which named the Foundation class, is not kept)
        if (!dict)
            return std::nullopt;
        return scriptsFromDictionaryOfScripts(dict, filePath);
    }
}

std::optional<std::string> OOPListScript::name()
{
    // Always a string: -initWithName:scriptArray:metadata: sets it.
    const oo::PList* value = _metadata.get<oo::PList>(kMDKeyName);
    const std::string* string = (value != nullptr) ? value->getIf<std::string>() : nullptr;
    return (string != nullptr) ? std::optional<std::string>(*string) : std::nullopt;
}

std::optional<std::string> OOPListScript::scriptDescription()
{
    // The metadata's "description" string. Nothing sends -scriptDescription (bead oo-3rb.266
    // measured), so a non-string value, which the id-typed selector returned as the object, is
    // nullopt here.
    const oo::PList* value = _metadata.get<oo::PList>(kMDKeyDescription);
    if (value == nullptr || !value->isString())
        return std::nullopt;
    return *value->getIf<std::string>();
}

std::optional<std::string> OOPListScript::version()
{
    // The metadata's "version" string, as -displayName read the id-typed -version. A non-string
    // value (which -length could not read: an exception) is nullopt here.
    const oo::PList* value = _metadata.get<oo::PList>(kMDKeyVersion);
    if (value == nullptr || !value->isString())
        return std::nullopt;
    return *value->getIf<std::string>();
}

bool OOPListScript::requiresTickle()
{
    return true;
}

void OOPListScript::runWithTarget(::Entity* target)
{
    if (target != nil && ![target isKindOfClass:[ShipEntity class]]) {
        OO_LOG("script.legacy.run.badTarget", "Expected ShipEntity or nil for target, got {}.", oo::DescriptionOf([target class]));
        return;
    }

    OO_LOG("script.legacy.run", "Running script {}", [oo::ToObjC(this) displayName].value_or("(null)"));
    oo::log::indentIf("script.legacy.run");

    [PLAYER cxx_runScriptActions:_script
                 withContextName:name()
                       forTarget:(ShipEntity*)target];

    oo::log::outdentIf("script.legacy.run");
}

std::vector<oo::ObjCRef<::OOScript*>> OOPListScript::scriptsFromDictionaryOfScripts(const oo::PList& dictionary, const std::string& filePath)
{
    std::vector<oo::ObjCRef<::OOScript*>> result;
    oo::PList::Dict cachedScripts;
    const oo::PList* metadata = nullptr;
    ::OOPListScript* script = nil;

    result.reserve(dictionary.count());

    metadata = dictionary.get<oo::PList::Dict>(kKeyMetadata); // nil unless a dictionary

    // Order-sensitive: the scripts come out in key order (they came out in hash order).
    for (const auto& [key, unsanitized] : *dictionary.getIf<oo::PList::Dict>()) {
        // (every key is a string: a dictionary with another key read as no dictionary)
        if (unsanitized.isArray() && key != kKeyMetadata) {
            const oo::PList sanitized = OOSanitizeLegacyScript(unsanitized, key, false);
            if (sanitized) {
                script = [[::OOPListScript alloc] initWithName:key scriptArray:sanitized metadata:metadata];
                if (script != nil) {
                    result.emplace_back(script);
                    // +dictionaryWithObjectsAndKeys: stopped at a nil metadata.
                    oo::PList::Dict cacheEntry;
                    cacheEntry[kKeyScript] = sanitized;
                    if (metadata != nullptr)
                        cacheEntry[kKeyMetadata] = *metadata;
                    cachedScripts[key] = oo::PList(std::move(cacheEntry));

                    [script release];
                }
            }
        }
    }

    if (OOCacheManager* cache = OOCacheManager::sharedCache())
        cache->setPList(oo::PList(std::move(cachedScripts)), filePath, kCacheName);

    return result;
}

std::vector<oo::ObjCRef<::OOScript*>> OOPListScript::loadCachedScripts(const oo::PList& cachedScripts)
{
    std::vector<oo::ObjCRef<::OOScript*>> result;
    result.reserve(cachedScripts.count());

    const oo::PList::Dict* entries = cachedScripts.getIf<oo::PList::Dict>();
    if (entries == nullptr)
        return result;

    // Order-sensitive: the scripts come out in key order (they came out in hash order).
    for (const auto& [key, entry] : *entries) {
        const oo::PList* cacheValue = entry.isDict() ? &entry : nullptr;
        const oo::PList* scriptArray = (cacheValue != nullptr) ? cacheValue->get<oo::PList::Array>(kKeyScript) : nullptr;
        const oo::PList* metadata = (cacheValue != nullptr) ? cacheValue->get<oo::PList::Dict>(kKeyMetadata) : nullptr;
        ::OOPListScript* script = [[::OOPListScript alloc] initWithName:key scriptArray:((scriptArray != nullptr) ? *scriptArray : oo::PList()) metadata:metadata];
        if (script != nil) {
            result.emplace_back(script);
            [script release];
        }
    }

    return result;
}

OOPListScript::OOPListScript(const std::string& name, const oo::PList& script, const oo::PList* metadata)
{
    {
        _script = script;
        // (every caller passes a name: the "no name" branch, which kept the metadata as given, is gone)
        oo::PList::Dict namedMetadata;
        if (metadata != nullptr)
            namedMetadata = *metadata->getIf<oo::PList::Dict>();
        namedMetadata[kMDKeyName] = name;
        _metadata = oo::PList(std::move(namedMetadata));
    }
}

} // namespace cxx
