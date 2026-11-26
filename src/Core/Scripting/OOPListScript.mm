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
#import "OOFoundationBridge.h"
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

// -objectForKey: of a dictionary held as a PList: the value as an Objective-C object, or nil.
id ObjectForKey(const oo::PList& dictionary, const char* key)
{
    const oo::PList* value = dictionary.get<oo::PList>(key);
    return (value != nullptr) ? oo::ObjectFromPList(*value) : nil;
}
} // namespace

@interface OOPListScript (SetUp)

+ (std::vector<oo::ObjCRef<OOScript*>>)scriptsFromDictionaryOfScripts:(const oo::PList&)dictionary filePath:(const std::string&)filePath;
+ (std::vector<oo::ObjCRef<OOScript*>>)loadCachedScripts:(const oo::PList&)cachedScripts;
- (id)initWithName:(const std::string&)name scriptArray:(const oo::PList&)script metadata:(const oo::PList*)metadata;

@end

@implementation OOPListScript

+ (std::optional<std::vector<oo::ObjCRef<OOScript*>>>)scriptsInPListFile:(const std::string&)filePath
{
    const oo::PList cachedScripts = oo::PListFrom([[OOCacheManager sharedCache] cxx_objectForKey:filePath inCache:kCacheName]);
    if (cachedScripts) {
        return [self loadCachedScripts:cachedScripts];
    } else {
        const oo::PList dict = oo::PListFrom(OODictionaryFromFile(oo::NSStringFrom(filePath)));
        if (!dict)
            return std::nullopt;
        return [self scriptsFromDictionaryOfScripts:dict filePath:filePath];
    }
}

- (id)name // shared selector (proposed ADR-0043)
{
    return ObjectForKey(_metadata, kMDKeyName);
}

- (id)scriptDescription // shared selector (proposed ADR-0043)
{
    return ObjectForKey(_metadata, kMDKeyDescription);
}

- (id)version // shared selector (proposed ADR-0043)
{
    return ObjectForKey(_metadata, kMDKeyVersion);
}

- (BOOL)requiresTickle
{
    return YES;
}

- (void)runWithTarget:(Entity*)target
{
    if (target != nil && ![target isKindOfClass:[ShipEntity class]]) {
        OOLog(@"script.legacy.run.badTarget", @"Expected ShipEntity or nil for target, got %@.", [target class]);
        return;
    }

    OOLog(@"script.legacy.run", @"Running script %@", [self displayName]);
    OOLogIndentIf(@"script.legacy.run");

    [PLAYER runScriptActions:oo::ObjectFromPList(_script)
             withContextName:[self name]
                   forTarget:(ShipEntity*)target];

    OOLogOutdentIf(@"script.legacy.run");
}

@end

@implementation OOPListScript (SetUp)

+ (std::vector<oo::ObjCRef<OOScript*>>)scriptsFromDictionaryOfScripts:(const oo::PList&)dictionary filePath:(const std::string&)filePath
{
    std::vector<oo::ObjCRef<OOScript*>> result;
    oo::PList::Dict cachedScripts;
    const oo::PList* metadata = nullptr;
    OOPListScript* script = nil;

    result.reserve(dictionary.count());

    metadata = dictionary.get<oo::PList::Dict>(kKeyMetadata); // nil unless a dictionary

    // Order-sensitive: the scripts come out in key order (they came out in hash order).
    for (const auto& [key, scriptArray] : *dictionary.getIf<oo::PList::Dict>()) {
        // (every key is a string: a dictionary with another key read as no dictionary)
        if (scriptArray.isArray() && key != kKeyMetadata) {
            const oo::PList sanitized = oo::PListFrom(OOSanitizeLegacyScript(oo::ObjectFromPList(scriptArray), oo::NSStringFrom(key), NO));
            if (sanitized) {
                script = [[self alloc] initWithName:key scriptArray:sanitized metadata:metadata];
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

    [[OOCacheManager sharedCache] cxx_setObject:oo::ObjectFromPList(oo::PList(std::move(cachedScripts))) forKey:filePath inCache:kCacheName];

    return result;
}

+ (std::vector<oo::ObjCRef<OOScript*>>)loadCachedScripts:(const oo::PList&)cachedScripts
{
    std::vector<oo::ObjCRef<OOScript*>> result;
    result.reserve(cachedScripts.count());

    const oo::PList::Dict* entries = cachedScripts.getIf<oo::PList::Dict>();
    if (entries == nullptr)
        return result;

    // Order-sensitive: the scripts come out in key order (they came out in hash order).
    for (const auto& [key, entry] : *entries) {
        const oo::PList* cacheValue = entry.isDict() ? &entry : nullptr;
        const oo::PList* scriptArray = (cacheValue != nullptr) ? cacheValue->get<oo::PList::Array>(kKeyScript) : nullptr;
        const oo::PList* metadata = (cacheValue != nullptr) ? cacheValue->get<oo::PList::Dict>(kKeyMetadata) : nullptr;
        OOPListScript* script = [[self alloc] initWithName:key scriptArray:((scriptArray != nullptr) ? *scriptArray : oo::PList()) metadata:metadata];
        if (script != nil) {
            result.emplace_back(script);
            [script release];
        }
    }

    return result;
}

- (id)initWithName:(const std::string&)name scriptArray:(const oo::PList&)script metadata:(const oo::PList*)metadata
{
    self = [super init];
    if (self != nil) {
        _script = script;
        // (every caller passes a name: the "no name" branch, which kept the metadata as given, is gone)
        oo::PList::Dict namedMetadata;
        if (metadata != nullptr)
            namedMetadata = *metadata->getIf<oo::PList::Dict>();
        namedMetadata[kMDKeyName] = name;
        _metadata = oo::PList(std::move(namedMetadata));
    }

    return self;
}

@end
