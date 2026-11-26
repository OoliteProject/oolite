/*

ResourceManager.m

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

#include "ResourceManager.h"
#include "HeadUpDisplay.h"
#include "MyOpenGLView.h"
#include "OOALMusic.h"
#include "OOCacheManager.h"
#include "OODebugStandards.h"
#include "OOLogOutputHandler.h"
#include "OOOXZManager.h"
#include "OOPListParsing.h"
#include "OOSound.h"
#include "OOStringParsing.h"
#include "OOSystemDescriptionManager.h"
#include "Universe.h"
#include "unzip.h"

#include "OOJSScript.h"
#include "OOPListScript.h"

#include "OOManifestProperties.h"
#include "OOObjCPList.h"
#include "oofnd/objc/OOException.h"

#include "oofnd/Defaults.hpp"
#include "oofnd/Encoding.hpp"
#include "oofnd/FileSystem.hpp"
#include "oofnd/PListParsing.hpp"
#include "oofnd/PListWriting.hpp"
#include "oofnd/ResourcePaths.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/String.hpp"

namespace {

// OODictionaryFromFile / OOArrayFromFile (OOPListParsing's bridge) as property lists: the file's
// property list when it is of that kind, a null PList otherwise (their plist.wrongType log line,
// which named the Foundation class, is not kept).
oo::PList PListDictionaryFromFile(const std::string& path)
{
    oo::PList result = cxx_OOPropertyListFromFile(path);
    return result.isDict() ? result : oo::PList();
}

oo::PList PListArrayFromFile(const std::string& path)
{
    oo::PList result = cxx_OOPropertyListFromFile(path);
    return result.isArray() ? result : oo::PList();
}

// OOCacheManager cache and keys for the search-path modification dates (the log classes are
// literals at their OOLog calls).
constexpr const char* kOOCacheSearchPathModDates = "search path modification dates";
constexpr const char* kOOCacheKeySearchPaths = "search paths";
constexpr const char* kOOCacheKeyModificationDates = "modification dates";

} // namespace

namespace {

// A path-scan error: a descriptions.plist key and the text of its two %@ parameters ("" for nil).
struct ResourceManagerError {
    std::string key;
    std::string param1;
    std::string param2;
};

std::optional<std::string> sUseAddOns; // nullopt before the first scan (was nil)
std::vector<std::string> sUseAddOnsParts;
std::vector<std::string> sOXPsWithMessagesFound;
std::vector<std::string> sExternalPaths;
std::vector<ResourceManagerError> sErrors;
std::map<std::string, oo::PList, std::less<>> sOXPManifests; // identifier -> manifest (+ file_path, required_by)
std::optional<std::vector<std::string>> sSearchPaths; // empty and nullopt both mean "scan again" (was [sSearchPaths count] > 0)

// A manifest string property as the string extractor (oo_stringForKey:) answered it: nullopt
// where that was nil (missing, or neither a string nor a number).
std::optional<std::string> ManifestString(const oo::PList& manifest, const std::string& key)
{
    const oo::PList* value = manifest.find(key);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return manifest.get<std::string>(key);
}

// -containsObject: of a string on the array (or set, held as an array) under key.
bool ManifestListContains(const oo::PList& manifest, const std::string& key, std::string_view string)
{
    const oo::PList* list = manifest.get<oo::PList::Array>(key);
    if (list == nullptr)
        return false;
    for (const oo::PList& element : *list->getIf<oo::PList::Array>()) {
        const std::string* elementString = element.getIf<std::string>();
        if (elementString != nullptr && *elementString == string)
            return true;
    }
    return false;
}

// The strings of a required_by set (held as a sorted array of unique strings).
std::set<std::string> ManifestRequiredBy(const oo::PList& manifest)
{
    std::set<std::string> result;
    const oo::PList* list = manifest.get<oo::PList::Array>(std::string(kOOManifestRequiredBy));
    if (list == nullptr)
        return result;
    for (const oo::PList& element : *list->getIf<oo::PList::Array>()) {
        if (const std::string* elementString = element.getIf<std::string>())
            result.insert(*elementString);
    }
    return result;
}

// Whether a string is in searchPaths (-containsObject:).
bool PathListContains(const std::vector<std::string>& searchPaths, const std::string& path)
{
    return std::find(searchPaths.begin(), searchPaths.end(), path) != searchPaths.end();
}

// -removeObject: of a nil-able path: every equal element goes.
void RemovePath(std::vector<std::string>& searchPaths, const std::optional<std::string>& path)
{
    if (!path.has_value())
        return;
    searchPaths.erase(std::remove(searchPaths.begin(), searchPaths.end(), *path), searchPaths.end());
}

// Whether +stringWithUTF8String: would have accepted these bytes (it returns nil for malformed
// UTF-8): they survive the round trip through UTF-16 unchanged.
bool IsWellFormedUTF8(const std::string& bytes)
{
    return oo::utf16ToUtf8(oo::utf8ToUtf16(bytes)) == bytes;
}

// An array of strings, as the Objective-C array of them was.
oo::PList StringArray(const std::vector<std::string>& strings)
{
    oo::PList::Array result;
    result.reserve(strings.size());
    for (const std::string& string : strings)
        result.emplace_back(string);
    return oo::PList(std::move(result));
}

// -stringByAbbreviatingWithTildeInPath of a search path: the home directory (NSHomeDirectory(),
// ResourcePaths::homeDirectory()) at its start becomes "~". The search paths are already standard
// ('/'-separated, absolute, no "." or ".." components: ResourcePaths and the OXP scan build them),
// so -stringByStandardizingPath left them as they were and is not repeated (bead oo-qps.49).
std::string AbbreviatedWithTilde(const std::string& path)
{
    const std::string home = oo::fs::utf8String(oo::ResourcePaths::current().homeDirectory());
    if (home.empty() || path.compare(0, home.size(), home) != 0)
        return path;
    if (path.size() == home.size())
        return "~";
    if (path[home.size()] != '/')
        return path;
    return "~" + path.substr(home.size());
}

// -[a isEqual:b] of the Foundation objects two property-list values converted to (bead oo-qps.49
// replaced the conversion); a missing or null one (nil) is never equal. Numbers (booleans among
// them) compare by value as NSNumber -compare: did: integers as integers, anything with a real as
// doubles (PList's type-strict == does not); a number never equals a string. Arrays compare
// element by element and dictionaries entry by entry, as -isEqualToArray: / -isEqualToDictionary:
// did; strings, data and dates by value; an Object node's object by -isEqual:.
bool PListIsEqual(const oo::PList* a, const oo::PList* b)
{
    if (a == nullptr || b == nullptr || a->isNull() || b->isNull())
        return false;
    if (a->isNumber() && b->isNumber()) {
        if (a->getIf<double>() != nullptr || b->getIf<double>() != nullptr)
            return a->doubleValue() == b->doubleValue();
        const oo::PList::Integer *aInteger = a->getIf<oo::PList::Integer>(), *bInteger = b->getIf<oo::PList::Integer>();
        const oo::PList::Integer aValue = (aInteger != nullptr) ? *aInteger : oo::PList::Integer { *a->getIf<bool>() ? 1 : 0, false };
        const oo::PList::Integer bValue = (bInteger != nullptr) ? *bInteger : oo::PList::Integer { *b->getIf<bool>() ? 1 : 0, false };
        // The same bits are the same number unless one is an unsigned value past INT64_MAX and
        // the other a negative signed one.
        return aValue.value == bValue.value && (aValue.isUnsigned == bValue.isUnsigned || aValue.value >= 0);
    }
    if (a->type() != b->type())
        return false;
    if (const oo::PList::Array* aArray = a->getIf<oo::PList::Array>()) {
        const oo::PList::Array& bArray = *b->getIf<oo::PList::Array>();
        if (aArray->size() != bArray.size())
            return false;
        for (std::size_t i = 0; i != aArray->size(); ++i) {
            if (!PListIsEqual(&(*aArray)[i], &bArray[i]))
                return false;
        }
        return true;
    }
    if (const oo::PList::Dict* aDict = a->getIf<oo::PList::Dict>()) {
        const oo::PList::Dict& bDict = *b->getIf<oo::PList::Dict>();
        if (aDict->size() != bDict.size())
            return false;
        for (const auto& [key, value] : *aDict) {
            const auto other = bDict.find(key);
            if (other == bDict.end() || !PListIsEqual(&value, &other->second))
                return false;
        }
        return true;
    }
    // Object nodes: the -isEqual: of the Objective-C objects they held, nil's NO for any other node
    // (bead oo-4aq6a.5 deleted the Objective-C object's node; no game object was one).
    if (a->getIf<oo::PList::Object>() != nullptr)
        return false;
    return *a == *b; // strings, data, dates
}

// The value if it is an array (the array extractor), else nullptr.
const oo::PList* AsArray(const oo::PList* value)
{
    return (value != nullptr && value->isArray()) ? value : nullptr;
}

// Element index of an array value; nullptr for a missing array or an index past its end (at<id>).
const oo::PList* ArrayElement(const oo::PList* array, std::size_t index)
{
    return array != nullptr ? array->at(index) : nullptr;
}

// -replaceObjectAtIndex:withObject: on an array value, raising as GSMutableArray did past the end.
void ReplaceArrayElement(oo::PList& array, std::size_t index, const oo::PList& value)
{
    oo::PList::Array& elements = *array.getIf<oo::PList::Array>();
    if (index >= elements.size()) {
        OORaiseException(OORangeException, "Index %lu is out of range %lu (in 'replaceObjectAtIndex:withObject:')", (unsigned long)index, (unsigned long)elements.size());
    }
    elements[index] = value;
}

// What the retired dictionary category -mergeEntriesFromDictionary: (OOExtensions) did: a key only in other is added;
// two unequal dictionaries merge recursively, two unequal arrays concatenate; anything else is
// replaced by other's value.
void MergeEntries(oo::PList::Dict& self, const oo::PList::Dict& other)
{
    for (const auto& [key, otherObject] : other) {
        auto existing = self.find(key);
        if (existing == self.end()) {
            self.emplace(key, otherObject);
            continue;
        }
        oo::PList& thisObject = existing->second;
        BOOL merged = NO;
        if (thisObject.isDict() && otherObject.isDict() && !PListIsEqual(&thisObject, &otherObject)) {
            oo::PList mergeObject = thisObject;
            MergeEntries(*mergeObject.getIf<oo::PList::Dict>(), *otherObject.getIf<oo::PList::Dict>());
            thisObject = std::move(mergeObject);
            merged = YES;
        } else if (thisObject.isArray() && otherObject.isArray() && !PListIsEqual(&thisObject, &otherObject)) {
            oo::PList::Array& elements = *thisObject.getIf<oo::PList::Array>();
            for (const oo::PList& element : *otherObject.getIf<oo::PList::Array>())
                elements.push_back(element);
            merged = YES;
        }
        if (!merged)
            thisObject = otherObject;
    }
}

// A star or nebula texture entry's merge key: the string itself, or a dictionary's "key" (else
// its "texture"); nullptr for anything else.
const oo::PList* TextureListKey(const oo::PList* value)
{
    if (value == nullptr)
        return nullptr;
    if (value->isString())
        return value;
    if (value->isDict()) {
        const oo::PList* key = value->find("key");
        return key != nullptr ? key : value->find("texture");
    }
    return nullptr;
}

// +dictionaryWithContentsOfFile: of the dictionary class: the file's property list if it is a dictionary,
// else (missing, unreadable, unparsable, another kind) a null PList.
oo::PList DictionaryWithContentsOfFile(const std::string& path)
{
    const auto data = oo::fs::readFile(oo::fs::pathFromUTF8(path));
    if (!data)
        return oo::PList();
    auto plist = oo::parsePropertyListData(data->stringView());
    if (!plist || !plist->isDict())
        return oo::PList();
    return std::move(*plist);
}

// The text before a log message class's first ".", or the whole class.
std::string LogClassKeyRoot(const std::string& key)
{
    const std::size_t dot = key.find('.');
    if (dot != std::string::npos) {
        return key.substr(0, dot);
    } else {
        return key;
    }
}

// [path lastPathComponent] of a nil-able path, as %@ printed it.
std::optional<std::string> LastPathComponent(const std::optional<std::string>& path)
{
    if (!path.has_value())
        return std::nullopt;
    return oo::str::lastPathComponent(*path);
}

} // namespace

static BOOL sFirstRun = YES;
static BOOL sAllMet = NO;

// caches allow us to load any given file once only
//
namespace {

std::map<std::string, oo::Ref<::OOSound>, std::less<>> sSoundCache;
std::map<std::string, std::string, std::less<>> sStringCache;

} // namespace

namespace {

// Info-gnustep.plist string (CFBundleVersion / CFBundleName as the Override category used to expose).
std::optional<std::string> OoliteInfoString(std::string_view key)
{
    const oo::fs::Path plistPath = oo::ResourcePaths::current().builtInResourcesDirectory() / "Info-gnustep.plist";
    oo::PList info;
    if (const oo::fs::Result<oo::Data> bytes = oo::fs::readFile(plistPath); bytes && !bytes->empty()) {
        if (oo::Expected<oo::PList, oo::PListError> parsed = oo::parsePropertyList(bytes->stringView());
            parsed && parsed->isDict())
            info = std::move(*parsed);
    }
    if (const oo::PList* v = info.find(key); v != nullptr && v->isString())
        return *v->getIf<std::string>();
    return std::nullopt;
}

} // namespace

void ResourceManager::reset()
{
    sFirstRun = YES;
    sUseAddOns.reset();
    sUseAddOnsParts.clear();
    sSearchPaths.reset();
    sOXPsWithMessagesFound.clear();
    sExternalPaths.clear();
    sErrors.clear();
    sOXPManifests.clear();
}

void ResourceManager::resetManifestKnowledgeForOXZManager()
{
    sUseAddOns.reset();
    sUseAddOnsParts.clear();
    sSearchPaths.reset();
    sOXPManifests.clear();
    pathsWithAddOns();
}

std::optional<std::string> ResourceManager::errors()
{
    if (sErrors.empty())
        return std::nullopt;

    // Expand error messages. This is deferred for localizability.
    std::vector<std::string> result;
    result.reserve(sErrors.size());
    for (const ResourceManagerError& error : sErrors) {
        std::optional<std::string> errStr = (UNIVERSE != nullptr ? UNIVERSE->descriptionForKey(error.key) : std::optional<std::string>());
        if (errStr.has_value()) {
            // The descriptions.plist entry is the format (data, not a literal): ADR-0043 item 19.
            result.push_back(oo::str::formatRuntime(*errStr, { error.param1, error.param2 }));
        }
    }

    sErrors.clear();

    std::string joined;
    for (std::size_t i = 0; i != result.size(); ++i) {
        if (i != 0)
            joined += "\n";
        joined += result[i];
    }
    return joined;
}

std::vector<std::string> ResourceManager::rootPaths()
{
    /* Built-in data, then managed OXZs, then manually installed ones,
     * which may be useful for debugging/testing purposes.
     * oo::ResourcePaths computes the same paths as [self builtInPath] and
     * [[OOOXZManager sharedManager] installPath]. */
    static std::optional<std::vector<std::string>> sRootPaths;
    if (!sRootPaths.has_value()) {
        const oo::ResourcePaths resourcePaths = oo::ResourcePaths::current();
        std::vector<std::string> paths { oo::fs::utf8String(resourcePaths.builtInResourcesDirectory()), oo::fs::utf8String(resourcePaths.managedAddOnsDirectory()) };
        for (const std::string& path : userRootPaths())
            paths.push_back(path);
        sRootPaths = std::move(paths);
    }
    return *sRootPaths;
}

std::vector<std::string> ResourceManager::userRootPaths()
{
    // the paths are now in order of preference as per yesterday's talk. -- Kaks 2010-05-05
    // (additional add-ons paths, <cwd>/../share/oolite/AddOns, <cwd>/AddOns, the extract path:
    // oo::ResourcePaths reproduces the list OOOXZManager and the current directory gave)
    static std::optional<std::vector<std::string>> sUserRootPaths;
    if (!sUserRootPaths.has_value()) {
        std::vector<std::string> paths;
        for (const oo::fs::Path& path : oo::ResourcePaths::current().userRootDirectories())
            paths.push_back(oo::fs::utf8String(path));
        sUserRootPaths = std::move(paths);
    }
    OO_LOG("searchPaths.debug", "{}", oo::DescriptionOf(StringArray(*sUserRootPaths)));
    return *sUserRootPaths;
}

std::optional<std::string> ResourceManager::builtInPath()
{
    // Look for a "Resources" folder in the cwd, else cwd/../share/oolite/Resources (Windows & Linux)
    return oo::fs::utf8String(oo::ResourcePaths::current().builtInResourcesDirectory());
}

std::vector<std::string> ResourceManager::pathsWithAddOns()
{
    if (sSearchPaths.has_value() && !sSearchPaths->empty())
        return *sSearchPaths;

    if (!sUseAddOns.has_value()) {
        sUseAddOns = std::string(SCENARIO_OXP_DEFINITION_ALL);
        sUseAddOnsParts = oo::str::split(*sUseAddOns, ";");
    }

    /* Handle special case of 'strict mode' efficiently */
    // testing actual string
    if (sUseAddOns == std::string(SCENARIO_OXP_DEFINITION_NONE)) {
        return { *builtInPath() };
    }

    sErrors.clear();

    // Copy those root paths that actually exist to search paths.
    const std::vector<std::string> rootPaths = ResourceManager::rootPaths();
    std::vector<std::string> existingRootPaths;
    existingRootPaths.reserve(rootPaths.size());
    for (const std::string& root : rootPaths) {
        if (oo::fs::isDirectory(oo::fs::pathFromUTF8(root))) {
            existingRootPaths.push_back(root);
        }
    }

    // validate default search paths
    sSearchPaths.emplace();
    std::vector<std::string>& searchPaths = *sSearchPaths;
    for (const std::string& path : existingRootPaths) {
        checkPotentialPath(path, searchPaths);
    }

    // Iterate over root paths.
    for (const std::string& root : existingRootPaths) {
        // Iterate over each root path's contents.
        if (oo::fs::isDirectory(oo::fs::pathFromUTF8(root))) {
            oo::fs::RecursiveDirectoryEnumerator dirEnum(oo::fs::pathFromUTF8(root));
            for (;;) {
                const std::optional<std::string> subPath = dirEnum.next();
                if (!subPath.has_value())
                    break;

                // Check if it's a directory.
                const std::string path = oo::str::appendingPathComponent(root, *subPath);
                const oo::fs::FileType type = dirEnum.entryType();
                if (type != oo::fs::FileType::none) {
                    if (type == oo::fs::FileType::directory) {
                        // If it is, is it an OXP?.
                        if (oo::str::lowercase(oo::str::pathExtension(path)) == "oxp") {
                            checkPotentialPath(path, searchPaths);
                            if (PathListContains(searchPaths, path))
                                checkOXPMessagesInPath(path);
                        } else {
                            // If not, don't search subdirectories.
                            dirEnum.skipDescendents();
                        }
                    } else {
                        // If not a directory, is it an OXZ?
                        if (oo::str::lowercase(oo::str::pathExtension(path)) == "oxz") {
                            checkPotentialPath(path, searchPaths);
                            if (PathListContains(searchPaths, path))
                                checkOXPMessagesInPath(path);
                        }
                    }
                }
            }
        }
    }

    for (const std::string& path : sExternalPaths) {
        checkPotentialPath(path, searchPaths);
        if (PathListContains(searchPaths, path))
            checkOXPMessagesInPath(path);
    }

    /* If a scenario restriction is *not* in place, remove
     * scenario-only OXPs. */
    // test string
    if (sUseAddOns == std::string(SCENARIO_OXP_DEFINITION_ALL)) {
        filterSearchPathsToExcludeScenarioOnlyPaths(searchPaths);
    }

    /* This is a conservative filter. It probably gets rid of more
     * OXPs than it technically needs to in certain situations with
     * dependency chains, but really any conflict here needs to be
     * resolved by the user rather than Oolite. The point is to avoid
     * loading OXPs which we shouldn't; if doing so takes out other
     * OXPs which would have been safe, that's not important. */
    filterSearchPathsForConflicts(searchPaths);

    /* This one needs to be run repeatedly to be sure. Take the chain
     * A depends on B depends on C. A and B are installed. A is
     * checked first, and depends on B, which is thought to be
     * okay. So A is kept. Then B is checked and removed. A must then
     * be rechecked. This function therefore is run repeatedly until a
     * run of it removes no further items.
     *
     * There may well be more elegant and efficient ways to do this
     * but this is already fast enough for most purposes.
     */
    while (!filterSearchPathsForRequirements(searchPaths)) { }

    /* If a scenario restriction is in place, restrict OXPs to the
     * ones valid for the scenario only. */
    // test string
    if (sUseAddOns != std::string(SCENARIO_OXP_DEFINITION_ALL)) {
        filterSearchPathsByScenario(searchPaths);
    }

    checkCacheUpToDateForPaths(searchPaths);

    return searchPaths;
}

void ResourceManager::preloadFileLists()
{
    // folders which may contain files to be cached
    const std::vector<std::string> folders = { "AIs", "Images", "Models", "Music", "Scenarios", "Scripts", "Shaders", "Sounds", "Textures" };

    const std::vector<std::string> paths = ResourceManager::paths();
    for (auto pathIt = paths.rbegin(); pathIt != paths.rend(); ++pathIt) {
        const std::string& path = *pathIt;
        if (oo::str::hasSuffix(path, ".oxz")) {
            preloadFileListFromOXZ(path, folders);
        } else {
            preloadFileListFromFolder(path, folders);
        }
    }
}

void ResourceManager::preloadFileListFromOXZ(const std::string& path, const std::vector<std::string>& folders)
{
    unzFile uf = NULL;
    const char* zipname = path.c_str();
    char componentName[512];

    if (zipname != NULL) {
        uf = unzOpen64(zipname);
    }
    if (uf == NULL) {
        OO_LOG("resourceManager.error", "Could not open .oxz at {} as zip file", path);
        return;
    }
    if (unzGoToFirstFile(uf) == UNZ_OK) {
        do {
            unzGetCurrentFileInfo64(uf, NULL,
                componentName, 512,
                NULL, 0,
                NULL, 0);
            const std::string zipEntry = componentName;
            // A name that is not UTF-8 was nil, and had no components.
            const std::vector<std::string> pathBits = IsWellFormedUTF8(zipEntry) ? oo::str::pathComponents(zipEntry) : std::vector<std::string>();
            if (pathBits.size() >= 2) {
                const std::string& folder = pathBits[0];
                if (std::find(folders.begin(), folders.end(), folder) != folders.end()) {
                    const std::string file = oo::str::pathWithComponents(std::vector<std::string>(pathBits.begin() + 1, pathBits.end()));
                    const std::string fullPath = oo::str::appendingPathComponent(oo::str::appendingPathComponent(path, folder), file);

                    preloadFilePathFor(file, folder, fullPath);
                }
            }

        } while (unzGoToNextFile(uf) == UNZ_OK);
    }
    unzClose(uf);
}

void ResourceManager::preloadFileListFromFolder(const std::string& path, const std::vector<std::string>& folders)
{
    // search each subfolder for files
    for (const std::string& subFolder : folders) {
        const std::string subFolderPath = oo::str::appendingPathComponent(path, subFolder);
        const std::vector<std::string> fileList = oo::fs::directoryContents(oo::fs::pathFromUTF8(subFolderPath)).value_or(std::vector<std::string>());
        for (const std::string& fileName : fileList) {
            preloadFilePathFor(fileName, subFolder, oo::str::appendingPathComponent(subFolderPath, fileName));
        }
    }
}

void ResourceManager::preloadFilePathFor(const std::string& fileName, const std::string& subFolder, const std::string& path)
{
    OOCacheManager* cache = OOCacheManager::sharedCache(); // C++ since bead oo-rmd7
    const std::string cacheKey = subFolder + "/" + fileName;
    // if nil, not found in another OXP already
    if (cache->pListForKey(cacheKey, "resolved paths").isNull()) {
        OO_LOG("resourceManager.foundFile.preLoad", "Found {}/{} at {}", subFolder, fileName, path);
        cache->setPList(oo::PList(path), cacheKey, "resolved paths");
    }
}

std::vector<std::string> ResourceManager::paths()
{
    if (EXPECT_NOT(!sSearchPaths.has_value())) {
        sSearchPaths.emplace();
    }
    return pathsWithAddOns();
}

std::vector<std::string> ResourceManager::maskUserNameInPathArray(const std::vector<std::string>& inputPathArray)
{
    std::vector<std::string> maskedArray;
    maskedArray.reserve(inputPathArray.size());
    const char* userNamePathEnvVar =
#if OOLITE_WINDOWS
        SDL_getenv("USERPROFILE");
#else
        SDL_getenv("HOME");
#endif
    const std::string userName = oo::str::lastPathComponent(oo::str::format("%s", userNamePathEnvVar));
    for (const std::string& path : inputPathArray) {
        maskedArray.push_back(*maskUserName(userName, path));
    }
    return maskedArray;
}

std::optional<std::string> ResourceManager::maskUserName(const std::string& name, const std::string& path)
{
    return oo::str::replaceOccurrences(path, name, "*", oo::str::Search::literal);
}

std::optional<std::string> ResourceManager::useAddOns()
{
    return sUseAddOns;
}

void ResourceManager::setUseAddOns(const std::string& useAddOns)
{
    if (sFirstRun || useAddOns != sUseAddOns) {
        reset();
        sFirstRun = NO;
        sUseAddOns = useAddOns;
        sUseAddOnsParts = oo::str::split(*sUseAddOns, ";");

        clearCaches();
        OOHUDResetTextEngine();

        OOCacheManager* cmgr = OOCacheManager::sharedCache(); // C++ since bead oo-rmd7
        /* only allow cache writes for the "all OXPs" default
         *
         * cache should be less necessary for restricted sets anyway */
        // testing the actual string here
        if (sUseAddOns == std::string(SCENARIO_OXP_DEFINITION_ALL)) {
            cmgr->reloadAllCaches();
            cmgr->setAllowCacheWrites(true);
        } else {
            cmgr->clearAllCaches();
            cmgr->setAllowCacheWrites(false);
        }

        checkCacheUpToDateForPaths(paths());
        logPaths();
        /* preloading the file lists at this stage helps efficiency a
         * lot when many OXZs are installed */
        preloadFileLists();
    }
}

void ResourceManager::addExternalPath(const std::string& path)
{
    if (!sSearchPaths.has_value())
        sSearchPaths.emplace();
    if (!PathListContains(*sSearchPaths, path)) {
        sSearchPaths->push_back(path);

        sExternalPaths.push_back(path);
    }
}

std::vector<std::string> ResourceManager::OXPsWithMessagesFound()
{
    return sOXPsWithMessagesFound;
}

oo::PList ResourceManager::manifestForIdentifier(const std::string& identifier)
{
    auto it = sOXPManifests.find(identifier);
    if (it == sOXPManifests.end())
        return oo::PList();
    return it->second;
}

void ResourceManager::logPaths()
{
    // Prettify paths for logging, as -stringByStandardizingPath and -stringByAbbreviatingWithTildeInPath
    // did for these (AbbreviatedWithTilde).
    std::string displayPaths;
    if (sSearchPaths.has_value()) {
        bool first = true;
        for (const std::string& path : *sSearchPaths) {
            if (!first)
                displayPaths += "\n    ";
            first = false;
            displayPaths += AbbreviatedWithTilde(path);
        }
    }

    OO_LOG("searchPaths.dumpAll", "Resource paths: {}\n    {}", sUseAddOns.value_or("(null)"), displayPaths);
}

void ResourceManager::clearCaches()
{
    sSoundCache.clear();
    sStringCache.clear();
}

void ResourceManager::checkOXPMessagesInPath(const std::string& path)
{
    // OOArrayFromFile (OOPListParsing) is an unmigrated callee: its array arrives through oo::PListFrom.
    const oo::PList OXPMessageArray = PListArrayFromFile(oo::str::appendingPathComponent(path, "OXPMessages.plist"));

    if (OXPMessageArray.count() > 0) {
        unsigned i;
        for (i = 0; i < OXPMessageArray.count(); i++) {
            // what the string extractor answered: a string (or a number's text); nil for anything else
            const oo::PList* oxpMessage = OXPMessageArray.at(i);
            if (oxpMessage != nullptr && (oxpMessage->isString() || oxpMessage->isNumber())) {
                OO_LOG("oxp.message", "{}: {}", path, OXPMessageArray.at<std::string>(i));
            }
        }
        sOXPsWithMessagesFound.push_back(oo::str::lastPathComponent(path));
    }
}

// Given a path to an assumed OXP (or other location where files are permissible), check for a requires.plist or manifest.plist and add to search paths if acceptable.
void ResourceManager::checkPotentialPath(const std::string& path, std::vector<std::string>& searchPaths)
{
    oo::PList requirements;
    oo::PList manifest;
    BOOL requirementsMet = YES;
    const std::string extension = oo::str::lowercase(oo::str::pathExtension(path));

    // OODictionaryFromFile (OOPListParsing) is an unmigrated callee: its dictionaries arrive through oo::PListFrom.
    if (extension != "oxz") {
        // OXZ format ignores requires.plist
        requirements = PListDictionaryFromFile(oo::str::appendingPathComponent(path, "requires.plist"));
        requirementsMet = areRequirementsFulfilled(requirements, path, "requires.plist");
    }
    if (!requirementsMet) {
        const std::optional<std::string> version = OoliteInfoString("CFBundleVersion");
        OO_LOG("oxp.versionMismatch", "OXP {} is incompatible with version {} of Oolite.", path, version.value_or("(null)"));
        addErrorWithKey("oxp-is-incompatible", oo::str::lastPathComponent(path), version.value_or(""));
        return;
    }

    manifest = PListDictionaryFromFile(oo::str::appendingPathComponent(path, "manifest.plist"));
    if (manifest.isNull()) {
        if (extension == "oxz") {
            OO_LOG("oxp.noManifest", "OXZ {} has no manifest.plist", path);
            addErrorWithKey("oxz-lacks-manifest", oo::str::lastPathComponent(path), "");
            return;
        } else {
            if (extension == "oxp") {
                cxx_OOStandardsError(oo::str::format("OXP %s has no manifest.plist", path.c_str()));
                if (OOEnforceStandards()) {
                    addErrorWithKey("oxp-lacks-manifest", oo::str::lastPathComponent(path), "");
                    return;
                }
            }
            // make up a basic manifest in relaxed mode or for base folders
            oo::PList::Dict basicManifest;
            basicManifest[std::string(kOOManifestIdentifier)] = oo::PList("__oolite.tmp." + path);
            basicManifest[std::string(kOOManifestVersion)] = oo::PList("1");
            basicManifest[std::string(kOOManifestTitle)] = oo::PList("OXP without manifest");
            basicManifest[std::string(kOOManifestRequiredOoliteVersion)] = oo::PList("1");
            manifest = oo::PList(std::move(basicManifest));
        }
    }

    requirementsMet = validateManifest(manifest, path);

    if (requirementsMet) {
        searchPaths.push_back(path);
    }
}

bool ResourceManager::validateManifest(const oo::PList& manifest, const std::string& path)
{
    BOOL OK = YES;
    const std::optional<std::string> identifier = ManifestString(manifest, std::string(kOOManifestIdentifier));
    const std::optional<std::string> version = ManifestString(manifest, std::string(kOOManifestVersion));
    const std::optional<std::string> required = ManifestString(manifest, std::string(kOOManifestRequiredOoliteVersion));
    const std::optional<std::string> title = ManifestString(manifest, std::string(kOOManifestTitle));

    if (!identifier.has_value()) {
        OO_LOG("oxp.noManifest", "OXZ {} manifest.plist has no '{}' field.", path, kOOManifestIdentifier);
        addErrorWithKey("oxp-manifest-incomplete", title.value_or(""), std::string(kOOManifestIdentifier));
        OK = NO;
    }
    if (!version.has_value()) {
        OO_LOG("oxp.noManifest", "OXZ {} manifest.plist has no '{}' field.", path, kOOManifestVersion);
        addErrorWithKey("oxp-manifest-incomplete", title.value_or(""), std::string(kOOManifestVersion));
        OK = NO;
    }
    if (!required.has_value()) {
        OO_LOG("oxp.noManifest", "OXZ {} manifest.plist has no '{}' field.", path, kOOManifestRequiredOoliteVersion);
        addErrorWithKey("oxp-manifest-incomplete", title.value_or(""), std::string(kOOManifestRequiredOoliteVersion));
        OK = NO;
    }
    if (!title.has_value()) {
        OO_LOG("oxp.noManifest", "OXZ {} manifest.plist has no '{}' field.", path, kOOManifestTitle);
        addErrorWithKey("oxp-manifest-incomplete", title.value_or(""), std::string(kOOManifestTitle));
        OK = NO;
    }
    if (!OK) {
        return NO;
    }
    OK = checkVersionCompatibility(manifest, title);

    if (!OK) {
        const std::optional<std::string> ooliteVersion = OoliteInfoString("CFBundleVersion");
        OO_LOG("oxp.versionMismatch", "OXP {} is incompatible with version {} of Oolite.", path, ooliteVersion.value_or("(null)"));
        addErrorWithKey("oxp-is-incompatible", oo::str::lastPathComponent(path), ooliteVersion.value_or(""));
        return NO;
    }

    auto duplicate = sOXPManifests.find(*identifier);
    if (duplicate != sOXPManifests.end()) {
        const std::optional<std::string> duplicatePath = ManifestString(duplicate->second, std::string(kOOManifestFilePath));
        OO_LOG("oxp.duplicate", "OXP {} has the same identifier ({}) as {} which has already been loaded.", path, *identifier, duplicatePath.value_or("(null)"));
        addErrorWithKey("oxp-manifest-duplicate", path, duplicatePath.value_or(""));
        return NO;
    }
    oo::PList mData = manifest;
    // add an extra key
    if (oo::PList::Dict* dict = mData.getIf<oo::PList::Dict>())
        (*dict)[std::string(kOOManifestFilePath)] = oo::PList(path);
    sOXPManifests[*identifier] = std::move(mData);
    return YES;
}

bool ResourceManager::checkVersionCompatibility(const oo::PList& manifest, const std::optional<std::string>& title)
{
    const std::optional<std::string> required = ManifestString(manifest, std::string(kOOManifestRequiredOoliteVersion));
    const std::optional<std::string> maxRequired = ManifestString(manifest, std::string(kOOManifestMaximumOoliteVersion));
    // A nil required version ended the old key/value list at once: an empty requirements dictionary.
    oo::PList::Dict requirements;
    if (required.has_value()) {
        requirements["version"] = oo::PList(*required);
        // ignore empty max version string rather than treating as "version 0"
        if (maxRequired.has_value() && !maxRequired->empty())
            requirements["max_version"] = oo::PList(*maxRequired);
    }
    return areRequirementsFulfilled(oo::PList(std::move(requirements)), title, "manifest.plist");
}

bool ResourceManager::areRequirementsFulfilled(const oo::PList& requirements, const std::optional<std::string>& path, const std::string& file)
{
    BOOL OK = YES;
    unsigned conditionsHandled = 0;
    static std::optional<std::vector<unsigned>> ooVersionComponents;

    if (requirements.isNull())
        return YES;

    if (!ooVersionComponents.has_value()) {
        ooVersionComponents = oo::str::versionComponents(OoliteInfoString("CFBundleVersion").value_or(""));
    }

    // Check "version" (minimum version)
    if (OK) {
        // Not get<std::string>, because we need to be able to complain about non-strings.
        const oo::PList* requiredVersion = requirements.find("version");
        if (requiredVersion != nullptr) {
            ++conditionsHandled;
            if (const std::string* requiredString = requiredVersion->getIf<std::string>()) {
                if (oo::str::compareVersions(*ooVersionComponents, oo::str::versionComponents(*requiredString)) < 0)
                    OK = NO;
            } else {
                // The requirements' property-list type, "dict" (was %@ of [requirements class], the class
                // name of the Foundation dictionary it converted to: bead oo-qps.49)
                OO_LOG("requirements.wrongType", "Expected {} entry \"{}\" to be string, but got {} in OXP {}.", file, "version", oo::typeName(requirements.type()), (LastPathComponent(path)).value_or("(null)"));
                OK = NO;
            }
        }
    }

    // Check "max_version" (minimum max_version)
    if (OK) {
        // Not get<std::string>, because we need to be able to complain about non-strings.
        const oo::PList* maxVersion = requirements.find("max_version");
        if (maxVersion != nullptr) {
            ++conditionsHandled;
            if (const std::string* maxString = maxVersion->getIf<std::string>()) {
                if (oo::str::compareVersions(*ooVersionComponents, oo::str::versionComponents(*maxString)) > 0)
                    OK = NO;
            } else {
                OO_LOG("requirements.wrongType", "Expected {} entry \"{}\" to be string, but got {} in OXP {}.", file, "max_version", oo::typeName(requirements.type()), (LastPathComponent(path)).value_or("(null)"));
                OK = NO;
            }
        }
    }

    if (OK && conditionsHandled < requirements.count()) {
        // There are unknown requirement keys - don't support. NOTE: this check was not made pre 1.69!
        OO_LOG("requirements.unknown", "requires.plist for OXP {} contains unknown keys, rejecting.", (LastPathComponent(path)).value_or("(null)"));
        OK = NO;
    }

    return OK;
}

bool ResourceManager::manifestHasConflicts(const oo::PList& manifest, bool logErrors)
{
    const oo::PList* conflicts = manifest.get<oo::PList::Array>(std::string(kOOManifestConflictOXPs), nullptr);
    // if it has a non-empty conflict_oxps list
    if (conflicts != nullptr && conflicts->count() > 0) {
        // iterate over that list
        for (const oo::PList& conflicting : *conflicts->getIf<oo::PList::Array>()) {
            const std::optional<std::string> conflictID = ManifestString(conflicting, std::string(kOOManifestRelationIdentifier));
            auto conflictManifest = conflictID.has_value() ? sOXPManifests.find(*conflictID) : sOXPManifests.end();
            // if the other OXP is in the list
            if (conflictManifest != sOXPManifests.end()) {
                // then check versions
                if (matchVersions(conflicting, ManifestString(conflictManifest->second, std::string(kOOManifestVersion)).value_or(""))) {
                    if (logErrors) {
                        addErrorWithKey("oxp-conflict", ManifestString(manifest, std::string(kOOManifestTitle)).value_or(""), ManifestString(conflictManifest->second, std::string(kOOManifestTitle)).value_or(""));
                        OO_LOG("oxp.conflict", "OXP {} conflicts with {} and was removed from the loading list", (LastPathComponent(ManifestString(manifest, std::string(kOOManifestFilePath)))).value_or("(null)"), (LastPathComponent(ManifestString(conflictManifest->second, std::string(kOOManifestFilePath)))).value_or("(null)"));
                    }
                    return YES;
                }
            }
        }
    }
    return NO;
}

void ResourceManager::filterSearchPathsForConflicts(std::vector<std::string>& searchPaths)
{
    std::vector<std::string> identifiers; // identifier order (was hash order)
    identifiers.reserve(sOXPManifests.size());
    for (const auto& [identifier, manifest] : sOXPManifests)
        identifiers.push_back(identifier);

    // take a copy because we'll mutate the original
    // foreach identified add-on
    for (const std::string& identifier : identifiers) {
        auto entry = sOXPManifests.find(identifier);
        if (entry != sOXPManifests.end()) {
            const oo::PList manifest = entry->second;
            if (manifestHasConflicts(manifest, YES)) {
                // then we have a conflict, so remove this path
                RemovePath(searchPaths, ManifestString(manifest, std::string(kOOManifestFilePath)));
                sOXPManifests.erase(identifier);
            }
        }
    }
}

bool ResourceManager::manifestHasMissingDependencies(const oo::PList& manifest, bool logErrors)
{
    const oo::PList* requireds = manifest.get<oo::PList::Array>(std::string(kOOManifestRequiresOXPs), nullptr);
    // if it has a non-empty required_oxps list
    if (requireds != nullptr && requireds->count() > 0) {
        // iterate over that list
        for (const oo::PList& required : *requireds->getIf<oo::PList::Array>()) {
            if (ResourceManager::manifest(manifest, required, logErrors)) {
                return YES;
            }
        }
    }
    return NO;
}

bool ResourceManager::manifest(const oo::PList& manifest, const oo::PList& required, bool logErrors)
{
    const std::optional<std::string> requiredID = ManifestString(required, std::string(kOOManifestRelationIdentifier));
    auto requiredManifest = requiredID.has_value() ? sOXPManifests.find(*requiredID) : sOXPManifests.end();
    // if the other OXP is in the list
    BOOL requirementsMet = NO;
    if (requiredManifest != sOXPManifests.end()) {
        // then check versions
        if (matchVersions(required, ManifestString(requiredManifest->second, std::string(kOOManifestVersion)).value_or(""))) {
            requirementsMet = YES;
            /* Mark the requiredManifest as a dependency of the
             * requiring manifest */
            std::set<std::string> reqby = ManifestRequiredBy(requiredManifest->second);
            const std::size_t reqbycount = reqby.size();
            /* then add this manifest to its required set. This is
             * done without checking if it's already there, because
             * the list of nested requirements may have changed. */
            if (std::optional<std::string> identifier = ManifestString(manifest, std::string(kOOManifestIdentifier)))
                reqby.insert(*identifier);
            // *and* anything that requires this OXP to be installed
            const std::set<std::string> manifestReqby = ManifestRequiredBy(manifest);
            reqby.insert(manifestReqby.begin(), manifestReqby.end());
            if (reqbycount < reqby.size()) {
                /* Then the set has increased in size. To handle
                 * potential cases with nested dependencies, need to
                 * re-run the requirement filter until all the sets
                 * stabilise. */
                sAllMet = NO;
            }
            // and push back into the requiring manifest (the set as a sorted array of unique strings)
            oo::PList::Array reqbyList;
            for (const std::string& identifier : reqby)
                reqbyList.emplace_back(identifier);
            if (oo::PList::Dict* dict = requiredManifest->second.getIf<oo::PList::Dict>())
                (*dict)[std::string(kOOManifestRequiredBy)] = oo::PList(std::move(reqbyList));
        }
    }
    if (!requirementsMet) {
        if (logErrors) {
            const std::optional<std::string> requiredDescription = ManifestString(required, std::string(kOOManifestRelationDescription));
            addErrorWithKey("oxp-required", ManifestString(manifest, std::string(kOOManifestTitle)).value_or(""), requiredDescription.has_value() ? *requiredDescription : requiredID.value_or(""));
            OO_LOG("oxp.requirementMissing", "OXP {} had unmet requirements and was removed from the loading list", (LastPathComponent(ManifestString(manifest, std::string(kOOManifestFilePath)))).value_or("(null)"));
        }
        return YES;
    }
    return NO;
}

bool ResourceManager::filterSearchPathsForRequirements(std::vector<std::string>& searchPaths)
{
    std::vector<std::string> identifiers; // identifier order (was hash order)
    identifiers.reserve(sOXPManifests.size());
    for (const auto& [identifier, manifest] : sOXPManifests)
        identifiers.push_back(identifier);

    sAllMet = YES;

    // take a copy because we'll mutate the original
    // foreach identified add-on
    for (const std::string& identifier : identifiers) {
        auto entry = sOXPManifests.find(identifier);
        if (entry != sOXPManifests.end()) {
            const oo::PList manifest = entry->second;
            if (manifestHasMissingDependencies(manifest, YES)) {
                // then we have a missing requirement, so remove this path
                RemovePath(searchPaths, ManifestString(manifest, std::string(kOOManifestFilePath)));
                sOXPManifests.erase(identifier);
                sAllMet = NO;
            }
        }
    }

    return sAllMet;
}

bool ResourceManager::matchVersions(const oo::PList& rangeDict, const std::string& version)
{
    const std::optional<std::string> minimum = ManifestString(rangeDict, std::string(kOOManifestRelationVersion));
    const std::optional<std::string> maximum = ManifestString(rangeDict, std::string(kOOManifestRelationMaxVersion));
    const std::vector<unsigned> isVersionComponents = oo::str::versionComponents(version); // "" (was nil) compares as the empty version
    if (minimum.has_value()) {
        if (oo::str::compareVersions(isVersionComponents, oo::str::versionComponents(*minimum)) < 0) {
            // earlier than minimum version
            return NO;
        }
    }
    if (maximum.has_value()) {
        if (oo::str::compareVersions(isVersionComponents, oo::str::versionComponents(*maximum)) > 0) {
            // later than maximum version
            return NO;
        }
    }
    // either version was okay, or no version info so an unconditional match
    return YES;
}

void ResourceManager::filterSearchPathsToExcludeScenarioOnlyPaths(std::vector<std::string>& searchPaths)
{
    std::vector<std::string> identifiers; // identifier order (was hash order)
    identifiers.reserve(sOXPManifests.size());
    for (const auto& [identifier, manifest] : sOXPManifests)
        identifiers.push_back(identifier);

    // take a copy because we'll mutate the original
    // foreach identified add-on
    for (const std::string& identifier : identifiers) {
        auto entry = sOXPManifests.find(identifier);
        if (entry != sOXPManifests.end()) {
            const oo::PList manifest = entry->second;
            if (ManifestListContains(manifest, std::string(kOOManifestTags), std::string(kOOManifestTagScenarioOnly))) {
                RemovePath(searchPaths, ManifestString(manifest, std::string(kOOManifestFilePath)));
                sOXPManifests.erase(identifier);
            }
        }
    }
}

void ResourceManager::filterSearchPathsByScenario(std::vector<std::string>& searchPaths)
{
    std::vector<std::string> identifiers; // identifier order (was hash order)
    identifiers.reserve(sOXPManifests.size());
    for (const auto& [identifier, manifest] : sOXPManifests)
        identifiers.push_back(identifier);

    // take a copy because we'll mutate the original
    // foreach identified add-on
    for (const std::string& identifier : identifiers) {
        auto entry = sOXPManifests.find(identifier);
        if (entry != sOXPManifests.end()) {
            const oo::PList manifest = entry->second;
            if (!manifestAllowedByScenario(manifest)) {
                // then we don't need this one
                RemovePath(searchPaths, ManifestString(manifest, std::string(kOOManifestFilePath)));
                sOXPManifests.erase(identifier);
            }
        }
    }
}

bool ResourceManager::manifestAllowedByScenario(const oo::PList& manifest)
{
    /* Checks for a couple of "never happens" cases */
#ifndef NDEBUG
    // test string
    if (sUseAddOns == std::string(SCENARIO_OXP_DEFINITION_ALL)) {
        OO_LOG("scenario.check", "{}", "Checked scenario allowances in all state - this is an internal error; please report this");
        return YES;
    }
    if (sUseAddOns == std::string(SCENARIO_OXP_DEFINITION_NONE)) {
        OO_LOG("scenario.check", "{}", "Checked scenario allowances in none state - this is an internal error; please report this");
        return NO;
    }
#endif
    if (ManifestString(manifest, std::string(kOOManifestIdentifier)) == "org.oolite.oolite") {
        // the core data is always allowed!
        return YES;
    }

    const std::string byID = std::string(SCENARIO_OXP_DEFINITION_BYID);
    const std::string byTag = std::string(SCENARIO_OXP_DEFINITION_BYTAG);
    BOOL result = NO;
    for (const std::string& uaoBit : sUseAddOnsParts) {
        if (oo::str::hasPrefix(uaoBit, byID)) {
            result |= manifestAllowedByScenario(manifest, uaoBit.substr(byID.size()));
        } else if (oo::str::hasPrefix(uaoBit, byTag)) {
            result |= manifestAllowedByScenarioWithTag(manifest, uaoBit.substr(byTag.size()));
        }
    }
    return result;
}

bool ResourceManager::manifestAllowedByScenario(const oo::PList& manifest, const std::string& identifier)
{
    if (ManifestString(manifest, std::string(kOOManifestIdentifier)) == identifier) {
        // manifest has the identifier - easy
        return YES;
    }
    // manifest is also allowed if a manifest with that identifier
    // requires it to be installed
    if (ManifestListContains(manifest, std::string(kOOManifestRequiredBy), identifier)) {
        return YES;
    }
    // otherwise, no
    return NO;
}

bool ResourceManager::manifestAllowedByScenarioWithTag(const oo::PList& manifest, const std::string& tag)
{
    if (ManifestListContains(manifest, std::string(kOOManifestTags), tag)) {
        // manifest has the tag - easy
        return YES;
    }
    // manifest is also allowed if a manifest with that tag
    // requires it to be installed
    for (const std::string& identifier : ManifestRequiredBy(manifest)) {
        auto reqManifest = sOXPManifests.find(identifier);
        // need to check for nil as this one may already have been ruled out
        if (reqManifest != sOXPManifests.end() && ManifestListContains(reqManifest->second, std::string(kOOManifestTags), tag)) {
            return YES;
        }
    }
    // otherwise, no
    return NO;
}

void ResourceManager::addErrorWithKey(const std::string& descriptionKey, const std::string& param1, const std::string& param2)
{
    // Every caller passes a key; a nil parameter arrives as "" (was `param ?: @""`).
    sErrors.push_back({ descriptionKey, param1, param2 });
}

bool ResourceManager::checkCacheUpToDateForPaths(const std::vector<std::string>& searchPaths)
{
    /*	Check if caches are up to date.
            The strategy is to use a two-entry cache. One entry is an array
            containing the search paths, the other an array of modification dates
            (in the same order). If either fails to match the correct settings,
            we delete both.
            OOCacheManager holds Foundation objects (an unmigrated callee): the two
            arrays are built for it at each call and compared with -isEqual:, as before.
    */
    OOCacheManager* cacheMgr = OOCacheManager::sharedCache();
    BOOL upToDate = YES;

    if (EXPECT_NOT(oo::Defaults::standard().boolForKey("always-flush-cache"))) {
        OO_LOG("dataCache.rebuild.explicitFlush", "{}", "Cache explicitly flushed with always-flush-cache preference. Rebuilding from scratch.");
        upToDate = NO;
    } else if (::MyOpenGLView::pollShiftKey()) {
        OO_LOG("dataCache.rebuild.explicitFlush", "{}", "Cache explicitly flushed with shift key. Rebuilding from scratch.");
        upToDate = NO;
    }

    const oo::PList oldPaths = cacheMgr->pListForKey(kOOCacheKeySearchPaths, kOOCacheSearchPathModDates); // null: none
    const oo::PList searchPathList = StringArray(searchPaths);
    if (upToDate && !PListIsEqual(&oldPaths, &searchPathList)) {
        // OXPs added/removed
        if (!oldPaths.isNull())
            OO_LOG("dataCache.rebuild.pathsChanged", "{}", "Cache is stale (search paths have changed). Rebuilding from scratch.");
        upToDate = NO;
    }

    // Build modification date list. (We need this regardless of whether the search paths matched.)
    oo::PList::Array modDates;
    modDates.reserve(searchPaths.size());
    for (const std::string& path : searchPaths) {
        const auto modTime = oo::fs::modificationTimeSince1970(oo::fs::pathFromUTF8(path));
        if (modTime) {
            // Double, as before: the cache stored -timeIntervalSince1970 of NSFileModificationDate.
            modDates.emplace_back(*modTime);
        }
    }
    const oo::PList modDateList(std::move(modDates));

    const oo::PList oldModDates = cacheMgr->pListForKey(kOOCacheKeyModificationDates, kOOCacheSearchPathModDates);
    if (upToDate && !PListIsEqual(&oldModDates, &modDateList)) {
        OO_LOG("dataCache.rebuild.datesChanged", "{}", "Cache is stale (modification dates have changed). Rebuilding from scratch.");
        upToDate = NO;
    }

    if (!upToDate) {
        cacheMgr->clearAllCaches();
        cacheMgr->setPList(searchPathList, kOOCacheKeySearchPaths, kOOCacheSearchPathModDates);
        cacheMgr->setPList(modDateList, kOOCacheKeyModificationDates, kOOCacheSearchPathModDates);
    } else
        OO_LOG("dataCache.upToDate", "{}", "Data cache is up to date.");

    return upToDate;
}

/* This method allows the exclusion of particular files from the plist
 * building when they're in builtInPath. The point of this is to allow
 * scenarios to avoid merging in core files without having to override
 * every individual entry (which may not always be possible
 * anyway). It only works on plists, but of course worldscripts can be
 * excluded by not including the plists which reference them, and
 * everything else can be excluded by not referencing it from a plist.
 */
bool ResourceManager::corePlist(const std::string& fileName, const std::string& path)
{
    if (path != builtInPath()) {
        // non-core paths always okay
        return NO;
    }
    const std::string noPList = std::string(SCENARIO_OXP_DEFINITION_NOPLIST);
    for (const std::string& uaoBit : sUseAddOnsParts) {
        if (oo::str::hasPrefix(uaoBit, noPList)) {
            if (uaoBit.substr(noPList.size()) == fileName) {
                // this core plist file should not be loaded at all
                return YES;
            }
        }
    }
    // then not excluded
    return NO;
}

oo::PList ResourceManager::dictionaryFromFilesNamed(const std::string& fileName,
    const std::optional<std::string>& folderName,
    bool mergeFiles)
{
    return dictionaryFromFilesNamed(fileName, folderName, mergeFiles ? MERGE_BASIC : MERGE_NONE, YES);
}

oo::PList ResourceManager::dictionaryFromFilesNamed(const std::string& fileName,
    const std::optional<std::string>& folderName,
    OOResourceMergeMode mergeMode,
    bool cache)
{
    oo::PList result;
    std::string cacheKey;
    const char* mergeType = nullptr;
    OOCacheManager* cacheMgr = OOCacheManager::sharedCache();

    switch (mergeMode) {
    case MERGE_NONE:
        mergeType = "none";
        break;

    case MERGE_BASIC:
        mergeType = "basic";
        break;

    case MERGE_SMART:
        mergeType = "smart";
        break;
    }
    if (mergeType == nullptr) {
        OO_LOG(cxx_kOOLogParameterError, "Unknown dictionary merge mode {} for {}. (This is an internal programming error, please report it.)", static_cast<unsigned>(mergeMode), fileName);
        return oo::PList();
    }

    if (cache) {

        if (folderName.has_value()) {
            cacheKey = oo::str::format("%s/%s merge:%s", folderName->c_str(), fileName.c_str(), mergeType);
        } else {
            cacheKey = oo::str::format("%s merge:%s", fileName.c_str(), mergeType);
        }
        oo::PList cached = cacheMgr->pListForKey(cacheKey, "dictionaries");
        if (!cached.isNull())
            return cached;
    }

    // OODictionaryFromFile (OOPListParsing) is an unmigrated callee: its dictionaries arrive through oo::PListFrom.
    if (mergeMode == MERGE_NONE) {
        // Find "last" matching dictionary
        const std::vector<std::string> paths = ResourceManager::paths();
        for (auto pathIt = paths.rbegin(); pathIt != paths.rend(); ++pathIt) {
            const std::string& path = *pathIt;
            if (folderName.has_value()) {
                result = PListDictionaryFromFile(oo::str::appendingPathComponent(oo::str::appendingPathComponent(path, *folderName), fileName));
                if (!result.isNull())
                    break;
            }
            result = PListDictionaryFromFile(oo::str::appendingPathComponent(path, fileName));
            if (!result.isNull())
                break;
        }
    } else {
        // Find all matching dictionaries
        std::vector<oo::PList> results;
        for (const std::string& path : paths()) {
            if (corePlist(fileName, path)) {
                continue;
            }
            oo::PList dict = PListDictionaryFromFile(oo::str::appendingPathComponent(path, fileName));
            if (!dict.isNull())
                results.push_back(std::move(dict));
            if (folderName.has_value()) {
                dict = PListDictionaryFromFile(oo::str::appendingPathComponent(oo::str::appendingPathComponent(path, *folderName), fileName));
                if (!dict.isNull())
                    results.push_back(std::move(dict));
            }
        }

        if (results.empty())
            return oo::PList();

        // Merge result
        oo::PList::Dict merged;

        for (const oo::PList& dict : results) {
            const oo::PList::Dict& entries = *dict.getIf<oo::PList::Dict>();
            if (mergeMode == MERGE_SMART)
                MergeEntries(merged, entries);
            else
                for (const auto& [key, value] : entries)
                    merged[key] = value; // -addEntriesFromDictionary:
        }
        result = oo::PList(std::move(merged));
    }

    if (cache && !result.isNull())
        cacheMgr->setPList(result, cacheKey, "dictionaries");

    return result;
}

oo::PList ResourceManager::arrayFromFilesNamed(const std::string& fileName, const std::optional<std::string>& folderName, bool mergeFiles)
{
    return arrayFromFilesNamed(fileName, folderName, mergeFiles, YES);
}

oo::PList ResourceManager::arrayFromFilesNamed(const std::string& fileName, const std::optional<std::string>& folderName, bool mergeFiles, bool useCache)
{
    oo::PList result;
    std::string cacheKey;
    OOCacheManager* cache = OOCacheManager::sharedCache();
    const std::string lowercaseName = oo::str::lowercase(fileName);
    const bool textureList = lowercaseName == "nebulatextures.plist" || lowercaseName == "startextures.plist";

    if (useCache) {
        cacheKey = oo::str::format("%s%s merge:%s", folderName.has_value() ? (*folderName + "/").c_str() : "", fileName.c_str(), mergeFiles ? "yes" : "no");
        oo::PList cached = cache->pListForKey(cacheKey, "arrays");
        if (!cached.isNull())
            return cached;
    }

    // OOArrayFromFile (OOPListParsing) is an unmigrated callee: its arrays arrive through oo::PListFrom.
    if (!mergeFiles) {
        // Find "last" matching array
        const std::vector<std::string> paths = ResourceManager::paths();
        for (auto pathIt = paths.rbegin(); pathIt != paths.rend(); ++pathIt) {
            const std::string& path = *pathIt;
            if (folderName.has_value()) {
                result = PListArrayFromFile(oo::str::appendingPathComponent(oo::str::appendingPathComponent(path, *folderName), fileName));
                if (!result.isNull())
                    break;
            }
            result = PListArrayFromFile(oo::str::appendingPathComponent(path, fileName));
            if (!result.isNull())
                break;
        }
    } else {
        // Find all matching arrays (an array of arrays, merged in place by the handlers below)
        oo::PList results = oo::PList(oo::PList::Array());
        oo::PList::Array& resultArrays = *results.getIf<oo::PList::Array>();
        for (const std::string& path : paths()) {
            if (corePlist(fileName, path)) {
                continue;
            }

            std::vector<std::string> arrayPaths = { oo::str::appendingPathComponent(path, fileName) };
            if (folderName.has_value())
                arrayPaths.push_back(oo::str::appendingPathComponent(oo::str::appendingPathComponent(path, *folderName), fileName));
            for (const std::string& arrayPath : arrayPaths) {
                oo::PList array = PListArrayFromFile(arrayPath);
                if (array.isNull())
                    continue; // a nil array was not added, and counted 0 below
                resultArrays.push_back(std::move(array));

                // Special handling for arrays merging. Currently, only equipment.plist, nebulatextures.plist and
                // startextures.plist gets their objects merged.
                // A lookup index is required. For the equipment.plist items, this is the index corresponding to the
                // EQ_* string, which describes the role of an equipment item and is unique.
                // For nebula and star textures, this is the texture filename, although it can be overridden with a
                // "key" property
                // (The array just added is the last of results, which the handlers edit in place.)
                if (resultArrays.back().count() != 0 && textureList)
                    handleStarNebulaListMerging(results);

                if (resultArrays.back().count() != 0 && resultArrays.back().at(0)->isArray()) {
                    if (lowercaseName == "equipment.plist")
                        handleEquipmentListMerging(results, 3); // Index 3 is the role string (EQ_*).
                }
            }
        }

        if (resultArrays.empty())
            return oo::PList();

        // Merge result
        result = oo::PList(oo::PList::Array());
        oo::PList::Array& merged = *result.getIf<oo::PList::Array>();

        for (const oo::PList& array : resultArrays) {
            for (const oo::PList& element : *array.getIf<oo::PList::Array>())
                merged.push_back(element);
        }
        // if we're doing equipment.plist, do equipment overrides now, while the array is still mutable
        if (lowercaseName == "equipment.plist") {
            handleEquipmentOverrides(result);
        }
    }

    if (useCache && !result.isNull())
        cache->setPList(result, cacheKey, "arrays");

    return result;
}

// A method for handling merging of arrays. Currently used with the equipment.plist entries.
// The arrayToProcess array is scanned for repetitions of the item at lookup index location and, if found,
// the latest entry replaces the earliest.
void ResourceManager::handleEquipmentListMerging(oo::PList& arrayToProcess, unsigned lookupIndex)
{
    NSUInteger i, j, k;
    oo::PList::Array& lists = *arrayToProcess.getIf<oo::PList::Array>();
    oo::PList& refArray = lists[lists.size() - 1];

    // Any change to refArray will directly modify arrayToProcess.

    for (i = 0; i < refArray.count(); i++) {
        for (j = 0; j < lists.size() - 1; j++) {
            NSUInteger count = lists[j].isArray() ? lists[j].count() : 0;
            if (count == 0)
                continue;

            for (k = 0; k < count; k++) {
                const oo::PList* processValue = ArrayElement(AsArray(ArrayElement(&lists[j], k)), lookupIndex);
                const oo::PList* refValue = ArrayElement(AsArray(ArrayElement(&refArray, i)), lookupIndex);

                if (PListIsEqual(processValue, refValue)) {
                    ReplaceArrayElement(lists[j], k, *refArray.at(i));
                    refArray.getIf<oo::PList::Array>()->erase(refArray.getIf<oo::PList::Array>()->begin() + static_cast<std::ptrdiff_t>(i));
                }
            }
        }
    }
    // arrayToProcess has been processed at this point. Any necessary merging has been done.
}

// handles processing of equipment-overrides.plist files, updating the source array with values found.
// format of file is slightly different to the standard equipment.plist file, in that it is a
// dictionary of dictionary objects (rather than an array of arrays). this allows properties like
// techlevel, price, name/short_description and description/long_description to be updated via the overrides file.
void ResourceManager::handleEquipmentOverrides(oo::PList& arrayToProcess)
{
    const oo::PList overrides = dictionaryFromFilesNamed("equipment-overrides.plist", std::string("Config"), MERGE_SMART, NO);
    const oo::PList::Dict* overrideEntries = overrides.getIf<oo::PList::Dict>();
    if (overrideEntries == nullptr)
        return;
    oo::PList::Array& entries = *arrayToProcess.getIf<oo::PList::Array>();

    // cycle through all the equipment keys found in override files
    for (const auto& [equipKey, overridesEntry] : *overrideEntries) {
        const oo::PList::Dict* overrideInfo = overridesEntry.getIf<oo::PList::Dict>();
        // loop through our data array to find a match
        for (std::size_t i = 0; i < entries.size(); i++) {
            const oo::PList* refValue = ArrayElement(AsArray(&entries[i]), EQUIPMENT_KEY_INDEX);
            // does the overridden equipment item exist in the equipment array? if so, get working
            const std::string* refKey = refValue != nullptr ? refValue->getIf<std::string>() : nullptr;
            if (refKey != nullptr && *refKey == equipKey) {
                oo::PList equipArray = entries[i];
                // cycle through all the properties found for this equipment key in the overrides file
                if (overrideInfo != nullptr)
                    for (const auto& [infoKey, infoValue] : *overrideInfo) {
                        // special cases for the array items that don't have a direct keyname
                        if (infoKey == "techlevel")
                            ReplaceArrayElement(equipArray, EQUIPMENT_TECH_LEVEL_INDEX, infoValue);
                        else if (infoKey == "price")
                            ReplaceArrayElement(equipArray, EQUIPMENT_PRICE_INDEX, infoValue);
                        else if (infoKey == "short_description" || infoKey == "name")
                            ReplaceArrayElement(equipArray, EQUIPMENT_SHORT_DESC_INDEX, infoValue);
                        else if (infoKey == "long_description" || infoKey == "description")
                            ReplaceArrayElement(equipArray, EQUIPMENT_LONG_DESC_INDEX, infoValue);
                        else {
                            // for everything else
                            // do we actually have an extras dictionary? if not, start from a blank one we can add to
                            const oo::PList* existingExtra = equipArray.at(EQUIPMENT_EXTRA_INFO_INDEX);
                            oo::PList extra = (existingExtra != nullptr && existingExtra->isDict()) ? *existingExtra : oo::PList(oo::PList::Dict());
                            oo::PList::Dict& extraEntries = *extra.getIf<oo::PList::Dict>();
                            // special case for weapon_info && script_info, which are child dictionaries
                            if (infoKey == "weapon_info" || infoKey == "script_info") {
                                // do we actually have a weapon_info/script_info dictionary? if not, start from a blank one
                                const oo::PList* existingSubInfo = extra.get<oo::PList::Dict>(infoKey);
                                oo::PList subInfo = existingSubInfo != nullptr ? *existingSubInfo : oo::PList(oo::PList::Dict());
                                // cycle through all the sub keys found in the overrides file for this equipment key item
                                if (const oo::PList::Dict* subOverrides = infoValue.getIf<oo::PList::Dict>()) {
                                    for (const auto& [subKey, subValue] : *subOverrides) {
                                        (*subInfo.getIf<oo::PList::Dict>())[subKey] = subValue;
                                    }
                                }
                                extraEntries[infoKey] = std::move(subInfo);
                            } else {
                                // for all other keys in the extras dictionary
                                extraEntries[infoKey] = infoValue;
                            }
                            ReplaceArrayElement(equipArray, EQUIPMENT_EXTRA_INFO_INDEX, extra);
                        }
                    }
                entries[i] = std::move(equipArray);
            }
        }
    }
}

// A method for handling merging of arrays. Currently used with the nebulatextures.plist and startextures.plist entries.
// uses the "texture" filename as the key value, or "key" if found
void ResourceManager::handleStarNebulaListMerging(oo::PList& arrayToProcess)
{
    NSUInteger i, j, k;
    oo::PList::Array& lists = *arrayToProcess.getIf<oo::PList::Array>();
    oo::PList& refArray = lists[lists.size() - 1];

    // Any change to refArray will directly modify arrayToProcess.
    for (i = 0; i < refArray.count(); i++) {
        for (j = 0; j < lists.size() - 1; j++) {
            NSUInteger count = lists[j].isArray() ? lists[j].count() : 0;
            if (count == 0)
                continue;

            for (k = 0; k < count; k++) {
                const oo::PList* processValue = ArrayElement(&lists[j], k);
                const oo::PList* refValue = ArrayElement(&refArray, i);

                const oo::PList* key1 = TextureListKey(processValue);
                if (!key1)
                    continue;

                const oo::PList* key2 = TextureListKey(refValue);
                if (!key2)
                    continue;

                if (PListIsEqual(key1, key2)) {
                    ReplaceArrayElement(lists[j], k, *refArray.at(i));
                    refArray.getIf<oo::PList::Array>()->erase(refArray.getIf<oo::PList::Array>()->begin() + static_cast<std::ptrdiff_t>(i));
                }
            }
        }
    }
    // arrayToProcess has been processed at this point. Any necessary merging has been done.
}

oo::PList ResourceManager::whitelistDictionary()
{
    static std::optional<oo::PList> whitelistDictionary; // a missing whitelist is remembered as null, not retried

    if (!whitelistDictionary.has_value()) {
        whitelistDictionary = DictionaryWithContentsOfFile(oo::str::appendingPathComponent(oo::str::appendingPathComponent(*builtInPath(), "Config"), "whitelist.plist"));
    }

    return *whitelistDictionary;
}

oo::PList ResourceManager::logControlDictionary()
{
    // Load built-in copy of logcontrol.plist.
    // OODictionaryFromFile (OOPListParsing) is an unmigrated callee: its dictionaries arrive through oo::PListFrom.
    const std::string builtInPath = oo::str::appendingPathComponent(oo::str::appendingPathComponent(*ResourceManager::builtInPath(), "Config"), "logcontrol.plist");
    oo::PList logControl = PListDictionaryFromFile(builtInPath);
    if (!logControl.isDict())
        logControl = oo::PList(oo::PList::Dict());
    oo::PList::Dict& logControlEntries = *logControl.getIf<oo::PList::Dict>();

    // Build list of root log message classes that appear in the built-in list.
    std::set<std::string> coreRoots;
    for (const auto& [key, value] : logControlEntries) {
        coreRoots.insert(LogClassKeyRoot(key));
    }

    const std::vector<std::string> rootPaths = ResourceManager::rootPaths();

    // The logcontrol.plist in path/Config, else in path itself.
    auto configDictionary = [](const std::string& path) -> oo::PList {
        oo::PList dict = PListDictionaryFromFile(oo::str::appendingPathComponent(oo::str::appendingPathComponent(path, "Config"), "logcontrol.plist"));
        if (dict.isNull()) {
            dict = PListDictionaryFromFile(oo::str::appendingPathComponent(path, "logcontrol.plist"));
        }
        return dict;
    };

    // Look for logcontrol.plists inside OXPs (but not in root paths). These are not allowed to define keys in hierarchies used by the build-in one.
    for (const std::string& path : paths()) {
        if (std::find(rootPaths.begin(), rootPaths.end(), path) != rootPaths.end())
            continue;

        const oo::PList dict = configDictionary(path);
        if (const oo::PList::Dict* entries = dict.getIf<oo::PList::Dict>()) {
            for (const auto& [key, value] : *entries) {
                if (!coreRoots.contains(LogClassKeyRoot(key))) {
                    logControlEntries[key] = value;
                }
            }
        }
    }

    // Now, look for logcontrol.plists in root paths, i.e. not within OXPs. These are allowed to override the built-in copy.
    for (const std::string& path : rootPaths) {
        const oo::PList dict = configDictionary(path);
        if (const oo::PList::Dict* entries = dict.getIf<oo::PList::Dict>()) {
            for (const auto& [key, value] : *entries) {
                logControlEntries[key] = value;
            }
        }
    }

    // Finally, look in preferences, which can override all of the above.
    const oo::PList preferences = oo::Defaults::standard().dictionaryForKey("logging-enable");
    if (const oo::PList::Dict* entries = preferences.getIf<oo::PList::Dict>()) {
        for (const auto& [key, value] : *entries)
            logControlEntries[key] = value;
    }

    return logControl;
}

oo::PList ResourceManager::roleCategoriesDictionary()
{
    oo::PList roleCategories = oo::PList(oo::PList::Dict());

    // OODictionaryFromFile (OOPListParsing) is an unmigrated callee: its dictionaries arrive through oo::PListFrom.
    for (const std::string& path : paths()) {
        if (corePlist("role-categories.plist", path)) {
            continue;
        }

        const std::string configPath = oo::str::appendingPathComponent(oo::str::appendingPathComponent(path, "Config"), "role-categories.plist");
        const oo::PList categories = PListDictionaryFromFile(configPath);
        if (!categories.isNull()) {
            mergeRoleCategories(categories, roleCategories);
        }
    }

    /* If the old pirate-victim-roles files exist, merge them in */
    const oo::PList pirateVictims = arrayFromFilesNamed("pirate-victim-roles.plist", std::string("Config"), YES);
    if (OOEnforceStandards() && pirateVictims.count() > 0) {
        cxx_OOStandardsDeprecated("pirate-victim-roles.plist is still being used.");
    }
    if (pirateVictims.isNull()) {
        // +dictionaryWithObject:forKey: with a nil object raised
        OORaiseException(OOInvalidArgumentException, "Tried to init dictionary with nil value");
    }
    oo::PList::Dict pirateVictimCategory;
    pirateVictimCategory.emplace("oolite-pirate-victim", pirateVictims);
    mergeRoleCategories(oo::PList(std::move(pirateVictimCategory)), roleCategories);

    return roleCategories;
}

void ResourceManager::mergeRoleCategories(const oo::PList& catData, oo::PList& categories)
{
    // A category is a set of roles: an array of unique values (by -isEqual:), in the order first seen.
    const oo::PList::Dict* catDataEntries = catData.getIf<oo::PList::Dict>();
    if (catDataEntries == nullptr)
        return;
    oo::PList::Dict& categoryEntries = *categories.getIf<oo::PList::Dict>();
    for (const auto& [key, value] : *catDataEntries) {
        oo::PList& contents = categoryEntries.try_emplace(key, oo::PList::Array()).first->second;
        const oo::PList* catDataEntry = catData.get<oo::PList::Array>(key);
        OO_LOG("shipData.load.roleCategories", "Adding {} entries for category {}", static_cast<long>((unsigned long)(catDataEntry != nullptr ? catDataEntry->count() : 0)), key);
        if (catDataEntry == nullptr)
            continue;
        oo::PList::Array& members = *contents.getIf<oo::PList::Array>();
        for (const oo::PList& role : *catDataEntry->getIf<oo::PList::Array>()) {
            bool present = false;
            for (const oo::PList& member : members) {
                if (PListIsEqual(&member, &role)) {
                    present = true;
                    break;
                }
            }
            if (!present)
                members.push_back(role);
        }
    }
}

oo::Ref<OOSystemDescriptionManager> ResourceManager::systemDescriptionManager()
{
    OO_LOG("resourceManager.planetinfo.load", "{}", "Initialising manager");
    oo::Ref<OOSystemDescriptionManager> manager = oo::makeRef<OOSystemDescriptionManager>();

    // OODictionaryFromFile (OOPListParsing) and OOSystemDescriptionManager are unmigrated callees:
    // the planetinfo dictionaries arrive through oo::PListFrom and leave through oo::ObjectFromPList.
    for (const std::string& path : paths()) {
        if (corePlist("planetinfo.plist", path)) {
            continue;
        }
        const std::string configPath = oo::str::appendingPathComponent(oo::str::appendingPathComponent(path, "Config"), "planetinfo.plist");
        const oo::PList categories = PListDictionaryFromFile(configPath);
        if (const oo::PList::Dict* systems = categories.getIf<oo::PList::Dict>()) {
            for (const auto& [systemKey, values] : *systems) {
                if (values.isDict()) {
                    if (systemKey == std::string(PLANETINFO_UNIVERSAL_KEY)) {
                        manager->setUniversalProperties(values);
                    } else if (systemKey == std::string(PLANETINFO_INTERSTELLAR_KEY)) {
                        manager->setInterstellarProperties(values);
                    } else {
                        manager->setProperties(values, systemKey);
                    }
                }
            }
        }
    }
    OO_LOG("resourceManager.planetinfo.load", "{}", "Caching routes");
    manager->buildRouteCache();
    OO_LOG("resourceManager.planetinfo.load", "{}", "Initialised manager");
    return manager;
}

oo::PList ResourceManager::shaderBindingTypesDictionary()
{
    static std::optional<oo::PList> shaderBindingTypesDictionary;

    if (!shaderBindingTypesDictionary.has_value()) {
        oo::PList dict = DictionaryWithContentsOfFile(oo::str::appendingPathComponent(oo::str::appendingPathComponent(*builtInPath(), "Config"), "shader-uniform-bindings.plist"));
        oo::PList::Dict* entries = dict.getIf<oo::PList::Dict>();
        std::vector<std::string> keys;
        if (entries != nullptr) {
            keys.reserve(entries->size());
            for (const auto& [key, value] : *entries)
                keys.push_back(key); // key order (was hash order)
        }

        // Resolve all $inherit keys.
        unsigned changeCount = 0;
        do {
            changeCount = 0;
            for (const std::string& key : keys) {
                const oo::PList* value = dict.get<oo::PList::Dict>(key);
                const std::optional<std::string> inheritKey = value != nullptr ? ManifestString(*value, "$inherit") : std::nullopt;
                if (inheritKey.has_value()) {
                    changeCount++;
                    oo::PList mutableValue = *value;
                    oo::PList::Dict& valueEntries = *mutableValue.getIf<oo::PList::Dict>();
                    valueEntries.erase("$inherit");
                    if (const oo::PList* inherited = dict.get<oo::PList::Dict>(*inheritKey)) {
                        for (const auto& [inheritedKey, inheritedValue] : *inherited->getIf<oo::PList::Dict>())
                            valueEntries[inheritedKey] = inheritedValue;
                    }

                    (*entries)[key] = std::move(mutableValue);
                }
            }
        } while (changeCount != 0);

        shaderBindingTypesDictionary = std::move(dict);
    }

    return *shaderBindingTypesDictionary;
}

std::optional<std::string> ResourceManager::pathForFileNamed(const std::string& fileName, const std::optional<std::string>& folderName)
{
    return pathForFileNamed(fileName, folderName, YES);
}

/* This is extremely expensive to call with useCache:NO */
std::optional<std::string> ResourceManager::pathForFileNamed(const std::string& fileName, const std::optional<std::string>& folderName, bool useCache)
{
    std::optional<std::string> result;
    std::string cacheKey;
    OOCacheManager* cache = OOCacheManager::sharedCache();
    std::string filePath;

    // (The resolved-paths cache is consulted whatever useCache says: the old test was of the cache
    // manager, which always exists.) OOCacheManager is an unmigrated callee: it holds the path as a
    // Foundation string.
    if (cache) {
        if (folderName.has_value())
            cacheKey = *folderName + "/" + fileName;
        else
            cacheKey = fileName;
        const oo::PList cached = cache->pListForKey(cacheKey, "resolved paths"); // a string (null: none)
        if (const std::string* cachedPath = cached.getIf<std::string>())
            return *cachedPath;
    }

    // Search for file (OXZ-aware exists, same answers as -oo_oxzFileExistsAtPath:).
    // reverse object enumerator allows OXPs to override core
    const std::vector<std::string> paths = ResourceManager::paths();
    for (auto pathIt = paths.rbegin(); pathIt != paths.rend(); ++pathIt) {
        const std::string& path = *pathIt;
        // appending a nil folder left the path as it was
        filePath = oo::str::appendingPathComponent(folderName.has_value() ? oo::str::appendingPathComponent(path, *folderName) : path, fileName);
        if (OOOxzFileExistsAtPath(filePath)) {
            result = filePath;
            break;
        }

        filePath = oo::str::appendingPathComponent(path, fileName);
        if (OOOxzFileExistsAtPath(filePath)) {
            result = filePath;
            break;
        }
    }

    if (result.has_value()) {
        OO_LOG("resourceManager.foundFile", "Found {}/{} at {}", folderName.value_or("(null)"), fileName, filePath);
        if (useCache) {
            cache->setPList(oo::PList(*result), cacheKey, "resolved paths");
        }
    }
    return result;
}

/* use extreme caution in calling with usePathCache:NO - this can be
 * an extremely expensive operation */
::OOSound* ResourceManager::retrieveFileNamed(const std::string& fileName,
    const std::optional<std::string>& folderName,
    std::map<std::string, oo::Ref<::OOSound>, std::less<>>* ioCache,
    std::optional<std::string> key,
    bool useCache)
{
    oo::Ref<::OOSound> result;

    if (ioCache) {
        if (!key.has_value())
            key = oo::str::format("%s:%s", folderName.has_value() ? folderName->c_str() : "(null)", fileName.c_str());
        // return the cached object, if any
        auto cached = ioCache->find(*key);
        if (cached != ioCache->end())
            return cached->second.get();
    }

    // [[[OOSound alloc] cxx_initWithContentsOfFile:path] autorelease], the facade's class cluster
    // until bead oo-9ht.68: the C++ factory. With no cache the caller is the only user, as the
    // autoreleased sound lived until the pool drained: oo::autorelease keeps that.
    // Its one caller, ooSoundNamed(), always passes the cache, so this reaches oo::autorelease only
    // with nil, as upstream's did (ADR-0056 amendment oo-31u.9).
    const std::optional<std::string> path = pathForFileNamed(fileName, folderName, useCache);
    if (path.has_value())
        result = ::OOSound::initWithContentsOfFile(path);

    if (result != nullptr && ioCache != NULL) {
        (*ioCache)[*key] = result;
        return result.get();
    }

    return oo::autorelease(result.leakRef());
}

oo::Ref<OOMusic> ResourceManager::ooMusicNamed(const std::string& fileName, const std::optional<std::string>& folderName)
{
    // Don't cache music objects; minimizing latency isn't really important.
    const std::optional<std::string> path = pathForFileNamed(fileName, folderName, YES);
    if (!path.has_value())
        return nullptr;
    return OOMusic::initWithContentsOfFile(path);
}

::OOSound* ResourceManager::ooSoundNamed(const std::string& fileName, const std::optional<std::string>& folderName)
{
    return retrieveFileNamed(fileName, folderName, &sSoundCache, oo::str::format("OOSound:%s:%s", folderName.has_value() ? folderName->c_str() : "(null)", fileName.c_str()), YES);
}

std::optional<std::string> ResourceManager::stringFromFilesNamed(const std::string& fileName, const std::optional<std::string>& folderName)
{
    return stringFromFilesNamed(fileName, folderName, YES);
}

std::optional<std::string> ResourceManager::stringFromFilesNamed(const std::string& fileName, const std::optional<std::string>& folderName, bool useCache)
{
    std::optional<std::string> result;
    std::string key;

    if (useCache) {
        key = oo::str::format("%s:%s", folderName.has_value() ? folderName->c_str() : "(null)", fileName.c_str());
        // return the cached object, if any
        auto cached = sStringCache.find(key);
        if (cached != sStringCache.end())
            return cached->second;
    }

    const std::optional<std::string> path = pathForFileNamed(fileName, folderName, YES);
    if (path.has_value()) {
        // +stringWithContentsOfUnicodeFile: (NSStringOOExtensions): the file's bytes, read as it read
        // them (through the OXZ reader), decoded as it decoded them.
        const std::optional<oo::Data> data = OODataFromOXZFile(*path);
        if (data.has_value())
            result = oo::str::decodeUnicodeText(data->stringView());
    }

    if (result.has_value() && useCache) {
        sStringCache[key] = *result;
    }

    return result;
}

std::vector<std::pair<std::string, oo::Ref<OOScript>>> ResourceManager::loadScripts()
{
    // name -> script, in the order each name was first loaded (a later script of the same name replaces the earlier one in place)
    std::vector<std::pair<std::string, oo::Ref<OOScript>>> loadedScripts;

    OO_LOG("script.load.world.begin", "{}", "Loading world scripts...");

    for (const std::string& path : paths()) {
        // excluding world-scripts.plist also excludes script.js / script.plist
        // though as those core files don't and won't exist this is not
        // a problem.
        if (!corePlist("world-scripts.plist", path)) {
            {
                oo::AutoreleaseScope pool; // was @autoreleasepool (oo-31u.8)
                try {
                    std::optional<std::vector<oo::Ref<OOScript>>> results = OOScript::worldScriptsAtPath(oo::str::appendingPathComponent(path, "Config"));
                    if (!results.has_value())
                        results = OOScript::worldScriptsAtPath(path);
                    if (results.has_value()) {
                        for (const oo::Ref<OOScript>& script : *results) {
                            const std::optional<std::string> name = (script != nullptr) ? script->name() : std::nullopt;
                            if (name.has_value()) {
                                auto existing = std::find_if(loadedScripts.begin(), loadedScripts.end(), [&](const auto& entry) { return entry.first == *name; });
                                if (existing != loadedScripts.end())
                                    existing->second = script;
                                else
                                    loadedScripts.emplace_back(*name, script);
                            } else
                                OO_LOG("script.load.unnamed", "Discarding anonymous script {}", (script != nullptr) ? script->description() : std::string("(null)"));
                        }
                    }
                } catch (...) {
                    const auto exception = oo::CurrentOOException();
                    if (!exception)
                        throw; // not an OOException: it goes on up, as before
                    OO_LOG("script.load.exception", "***** {} encountered exception {} ({}) while trying to load script from {} -- ignoring this location.", "+ResourceManager::loadScripts()", exception->name(), exception->reason(), path);
                    // Ignore exception and keep loading other scripts.
                }
            }
        }
    }

    if (oo::log::willDisplay("script.load.world.listAll")) {
        std::size_t count = loadedScripts.size();
        if (count != 0) {
            std::vector<std::string> displayNames;
            displayNames.reserve(count);

            for (const auto& [name, script] : loadedScripts) {
                displayNames.push_back(((script != nullptr) ? script->displayName() : std::nullopt).value_or(""));
            }

            std::stable_sort(displayNames.begin(), displayNames.end(), [](const std::string& a, const std::string& b) { return oo::str::caseInsensitiveCompare(a, b) < 0; });
            std::string displayString;
            for (std::size_t i = 0; i != displayNames.size(); ++i) {
                if (i != 0)
                    displayString += "\n    ";
                displayString += displayNames[i];
            }
            OO_LOG("script.load.world.listAll", "Loaded {} world scripts:\n    {}", static_cast<size_t>(count), displayString);
        } else {
            OO_LOG("script.load.world.listAll", "{}", "*** No world scripts loaded.");
        }
    }

    return loadedScripts;
}

bool ResourceManager::writeDiagnosticData(const oo::Data& data, const std::string& name)
{
    std::optional<std::string> directory = diagnosticFileLocation();
    if (!directory.has_value())
        return NO;

    std::string fileName = name;
    const std::vector<std::string> nameComponents = oo::str::split(name, "/");
    std::size_t count = nameComponents.size();
    if (count > 1) {
        fileName = nameComponents.back();

        for (std::size_t i = 0; i < count - 1; i++) {
            std::string component = nameComponents[i];
            if (oo::str::hasPrefix(component, ".")) {
                component = "!" + component.substr(1);
            }
            // appending an empty component left the directory as it was
            if (!component.empty())
                *directory = oo::str::appendingPathComponent(*directory, component);
            (void)oo::fs::createDirectories(oo::fs::pathFromUTF8(*directory));
        }
    }

    return oo::fs::writeFile(oo::fs::pathFromUTF8(oo::str::appendingPathComponent(*directory, fileName)), data, oo::fs::WriteMode::atomic).has_value();
}

bool ResourceManager::writeDiagnosticString(const std::string& string, const std::string& name)
{
    return writeDiagnosticData(oo::Data::fromString(string), name);
}

bool ResourceManager::writeDiagnosticPList(const oo::PList& plist, const std::string& name)
{
    // The old-school writer (oo::writeOldStylePList, the port of the retired Objective-C old-school plist writer). Its
    // XML fallback's result was never used, so a plist it cannot write is not written.
    const auto data = oo::writeOldStylePList(plist);
    if (!data.has_value())
        return NO;

    return writeDiagnosticData(*data, name);
}

oo::PList ResourceManager::materialDefaults()
{
    return dictionaryFromFilesNamed("material-defaults.plist", std::string("Config"), YES);
}

bool ResourceManager::directoryExists(const std::string& inPath, bool inCreate)
{
    const oo::fs::FileType type = oo::fs::fileType(oo::fs::pathFromUTF8(inPath));
    const BOOL exists = type != oo::fs::FileType::none;
    const BOOL directory = type == oo::fs::FileType::directory;

    if (exists && !directory) {
        OO_LOG("resourceManager.write.buildPath.failed", "Expected {} to be a folder, but it is a file.", inPath);
        return NO;
    }
    if (!exists) {
        if (!inCreate)
            return NO;
        if (!oo::fs::createDirectories(oo::fs::pathFromUTF8(inPath))) {
            OO_LOG("resourceManager.write.buildPath.failed", "Could not create folder {}.", inPath);
            return NO;
        }
    }

    return YES;
}

std::optional<std::string> ResourceManager::diagnosticFileLocation()
{
    return cxx_OOLogHandlerGetLogBasePath();
}
