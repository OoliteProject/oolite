/*

OOOXZManager.m

Responsible for installing and uninstalling OXZs

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

#include "OOOXZManager.h"
#include "GameController.h"
#include "GuiDisplayGen.h"
#include "MyOpenGLView.h"
#include "OOCacheManager.h"
#include "OOColor.h"
#include "OOPListParsing.h"
#include "OOStringExpander.h"
#include "OOStringParsing.h"
#include "OOXMLExtensions.h"
#include "PlayerEntity.h"
#include "PlayerEntitySound.h"
#include "ResourceManager.h"
#include "Universe.h"

#include <algorithm>
#include <optional>
#include <string>
#include <vector>

#include "oofnd/Defaults.hpp"
#include "oofnd/FileSystem.hpp"
#include "oofnd/Http.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/PListParsing.hpp"
#include "oofnd/ResourcePaths.hpp"
#include "oofnd/String.hpp"
#include "unzip.h"

#include "OOManifestProperties.h"
#include "oofnd/Date.hpp"

/* The URL for the manifest.plist array. */
/* switching (temporarily maybe) to oolite.space - Nikos 20230507 */
namespace {

// OODictionaryFromFile / OOArrayFromFile (the retired OOPListParsing bridge) as property lists:
// the file's property list when it is of that kind, a null PList otherwise (no path: none; their
// plist.wrongType log line, which named the Foundation class, is not kept).
oo::PList PListDictionaryFromFile(const std::string& path)
{
    oo::PList result = cxx_OOPropertyListFromFile(path);
    return result.isDict() ? result : oo::PList();
}

oo::PList PListArrayFromFile(const std::optional<std::string>& path)
{
    if (!path.has_value())
        return oo::PList();
    oo::PList result = cxx_OOPropertyListFromFile(*path);
    return result.isArray() ? result : oo::PList();
}

} // namespace

namespace {
/*const char *const kOOOXZDataURL = "http://addons.oolite.org/api/1.0/overview";*/
const char* const kOOOXZDataURL = "https://addons.oolite.space/api/1.0/overview";
/* The config parameter to use a non-default URL at runtime */
const char* const kOOOXZDataConfig = "oxz-index-url";
/* The filename to store the downloaded manifest.plist array */
const char* const kOOOXZManifestCache = "Oolite-manifests.plist";
/* The filename to temporarily store the downloaded OXZ. Has an OXZ extension since we might want to read its manifest.plist out of it;  */
const char* const kOOOXZTmpPath = "Oolite-download.oxz";
/* The filename to temporarily store the downloaded plists. */
const char* const kOOOXZTmpPlistPath = "Oolite-download.plist";
} // namespace

/* Log file record types: literals at each OOLog call (@"oxz.manager.error" / @"oxz.manager.debug"). */

/* Filter components */
namespace {
constexpr std::string_view kOOOXZFilterAll = "*";
constexpr std::string_view kOOOXZFilterUpdates = "u";
constexpr std::string_view kOOOXZFilterInstallable = "i";
constexpr std::string_view kOOOXZFilterKeyword = "k:";
constexpr std::string_view kOOOXZFilterAuthor = "a:";
constexpr std::string_view kOOOXZFilterCategory = "c:";
constexpr std::string_view kOOOXZFilterDays = "d:";
constexpr std::string_view kOOOXZFilterTag = "t:";
} // namespace

// OXZInstallableState is declared in OOOXZManager.h (bead oo-0hyr: a member's result).

enum {
    OXZ_GUI_ROW_LISTHEAD = 0,
    OXZ_GUI_ROW_FIRSTRUN = 1,
    OXZ_GUI_ROW_PROGRESS = 1,
    OXZ_GUI_ROW_FILTERHELP = 1,
    OXZ_GUI_ROW_LISTPREV = 1,
    OXZ_GUI_ROW_LISTSTART = 2,
    OXZ_GUI_NUM_LISTROWS = 10,
    OXZ_GUI_ROW_LISTNEXT = 12,
    OXZ_GUI_ROW_LISTSTATUS = 14,
    OXZ_GUI_ROW_LISTDESC = 16,
    OXZ_GUI_ROW_LISTINFO1 = 19,
    OXZ_GUI_ROW_LISTINFO2 = 20,
    OXZ_GUI_ROW_LISTFILTER = 21,
    OXZ_GUI_ROW_INSTALL = 22,
    OXZ_GUI_ROW_INSTALLED = 23,
    OXZ_GUI_ROW_UPDATE_ALL = 24,
    OXZ_GUI_ROW_REMOVE = 25,
    OXZ_GUI_ROW_PROCEED = 25,
    OXZ_GUI_ROW_UPDATE = 26,
    OXZ_GUI_ROW_CANCEL = 26,
    OXZ_GUI_ROW_FILTERCURRENT = 26,
    OXZ_GUI_ROW_INPUT = 27,
    OXZ_GUI_ROW_EXIT = 27
};

namespace {

// Manifest string-or-number key (a string, or a number's stringValue); nullopt (nil) otherwise.
std::optional<std::string> ManifestString(const oo::PList& manifest, const std::string& key)
{
    const oo::PList* value = manifest.find(key);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return manifest.get<std::string>(key);
}

// [haystack rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound, each
// UTF-16 unit folded with oo::str::toLower as -caseInsensitiveCompare: folds. An empty needle is
// found (location 0, captured), and so is anything in a nil haystack: the nil message's range is
// zero-filled, location 0 (captured on GNUstep 1.31.1).
bool FoundIgnoringCase(const std::optional<std::string>& haystack, const std::string& needle)
{
    if (!haystack.has_value())
        return true;
    std::u16string h = oo::utf8ToUtf16(*haystack), n = oo::utf8ToUtf16(needle);
    for (char16_t& u : h)
        u = oo::str::toLower(u);
    for (char16_t& u : n)
        u = oo::str::toLower(u);
    return h.find(n) != std::u16string::npos;
}

// The tags filter: any string tag containing the needle. (A non-string tag raised on
// -rangeOfString:options:; it is skipped.)
bool TagFoundIgnoringCase(const oo::PList& manifest, const std::string& needle)
{
    const oo::PList* tags = manifest.get<oo::PList::Array>(std::string(kOOManifestTags));
    if (tags == nullptr)
        return false;
    for (const oo::PList& tag : *tags->getIf<oo::PList::Array>()) {
        if (const std::string* string = tag.getIf<std::string>()) {
            if (FoundIgnoringCase(*string, needle))
                return true;
        }
    }
    return false;
}

// The elements of an Array node (none for anything else, as messaging nil gave).
const oo::PList::Array& Elements(const oo::PList& list)
{
    static const oo::PList::Array empty;
    const oo::PList::Array* elements = list.getIf<oo::PList::Array>();
    return (elements != nullptr) ? *elements : empty;
}

// Element index of an Array node; null when out of range.
oo::PList ElementAt(const oo::PList& list, NSUInteger index)
{
    const oo::PList* element = list.at(index);
    return (element != nullptr) ? *element : oo::PList();
}

/* Sort by category, then title, then version - and that should be unique (was the C function
   oxzSort, an OOComparisonResult sort function). The version orders descending. Each key collates
   as the old -localizedCompare did: oo::str::localizedCompare, ICU in the default locale. */
bool OXZOrderedBefore(const oo::PList& m1, const oo::PList& m2)
{
    int result = oo::str::localizedCompare(ManifestString(m1, std::string(kOOManifestCategory)).value_or("zz"), ManifestString(m2, std::string(kOOManifestCategory)).value_or("zz"));
    if (result == 0) {
        result = oo::str::localizedCompare(ManifestString(m1, std::string(kOOManifestTitle)).value_or("zz"), ManifestString(m2, std::string(kOOManifestTitle)).value_or("zz"));
        if (result == 0) {
            result = oo::str::localizedCompare(ManifestString(m2, std::string(kOOManifestVersion)).value_or("0"), ManifestString(m1, std::string(kOOManifestVersion)).value_or("0"));
        }
    }
    return result < 0;
}

// DESC(...) formatRuntime: a format read at run time (proposed ADR-0043
// Amendment 3 item 19).
std::string DescFormat(const std::string& format, std::initializer_list<oo::str::FormatArg> args)
{
    return oo::str::formatRuntime(format, args);
}

// A %@ argument that may be nil.
oo::str::FormatArg Arg(const std::optional<std::string>& text)
{
    return text.has_value() ? oo::str::FormatArg(*text) : oo::str::FormatArg::null();
}

// -oo_stringForKey:defaultValue: on a manifest.
std::optional<std::string> ManifestStringOr(const oo::PList& manifest, const std::string& key, const std::optional<std::string>& fallback)
{
    std::optional<std::string> value = ManifestString(manifest, key);
    return value.has_value() ? value : fallback;
}

// The columns of a nil-terminated column list for -setArray:forRow:, which ended at the
// first missing value.
std::vector<std::string> Columns(std::initializer_list<std::optional<std::string>> columns)
{
    std::vector<std::string> result;
    for (const std::optional<std::string>& column : columns) {
        if (!column.has_value())
            break;
        result.push_back(*column);
    }
    return result;
}

// Unique-by-== insert for the dependency stack (was a mutable set of manifests).
void DependencyStackAdd(std::vector<oo::PList>& stack, const oo::PList& item)
{
    for (const oo::PList& existing : stack) {
        if (existing == item)
            return;
    }
    stack.push_back(item);
}

void DependencyStackRemove(std::vector<oo::PList>& stack, const oo::PList& item)
{
    stack.erase(std::remove(stack.begin(), stack.end(), item), stack.end());
}

// The first line of a manifest's description (nullopt: no description, as the nil array gave).
std::optional<std::string> FirstDescriptionLine(const oo::PList& manifest)
{
    const std::optional<std::string> description = ManifestString(manifest, std::string(kOOManifestDescription));
    if (!description.has_value())
        return std::nullopt;
    return oo::str::split(*description, "\n").front();
}

// [tags componentsJoinedByString:@", "] (nullopt: no tags array).
std::optional<std::string> JoinedTags(const oo::PList& manifest)
{
    const oo::PList* tags = manifest.get<oo::PList::Array>(std::string(kOOManifestTags));
    if (tags == nullptr)
        return std::nullopt;
    std::string result;
    bool first = true;
    for (const oo::PList& tag : Elements(*tags)) {
        if (!first)
            result += ", ";
        first = false;
        const std::string* string = tag.getIf<std::string>();
        result += (string != nullptr) ? *string : oo::DescriptionOf(tag);
    }
    return result;
}

OOOXZManager* sSingleton = nullptr; // the one +1 is never released (amendment oo-r7m0 item 1)

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

OOOXZManager* OOOXZManager::sharedManager()
{
    // NOTE: assumes single-threaded first access.
    if (sSingleton == nullptr) {
        OOOXZManager* manager = oo::makeRef<OOOXZManager>().leakRef(); // the one +1, never released (amendment oo-r7m0 item 1)
        manager->init();
        sSingleton = manager;
    }
    return sSingleton;
}

void OOOXZManager::init()
{
    _downloadStatus = OXZ_DOWNLOAD_NONE;
    // if the file has not been downloaded, this will be nil
    setOXZList(PListArrayFromFile(manifestPath()));
    OO_LOG("oxz.manager.debug", "Initialised with {}", oo::DescriptionOf(_oxzList));
    _interfaceState = OXZ_STATE_NODATA;
    _currentFilter = "*";

    _interfaceShowingOXZDetail = false;
    _changesMade = false;
    _downloadAllDependencies = false;
    _dependencyStack.clear();
    _dependencyStack.reserve(8);
    setProgressStatus("");
}

OOOXZManager::~OOOXZManager()
{
    if (sSingleton == this)
        sSingleton = nullptr;

    setCurrentDownload(nullptr, "");
}

/* The install path for OXZs downloaded by
 * Oolite. Library/ApplicationSupport seems to be the most appropriate
 * location. */
std::optional<std::string> OOOXZManager::installPath()
{
    // OO_MANAGEDADDONSDIR, else <ApplicationSupport>/Oolite/ManagedAddOns (GNUstep uses
    // "ApplicationSupport" rather than "Application Support", so no space in "ManagedAddOns"
    // either): oo::ResourcePaths reproduces the NSSearchPathForDirectoriesInDomains result.
    return oo::fs::utf8String(oo::ResourcePaths::current().managedAddOnsDirectory());
}

/* The extract path for OXZs . */
std::optional<std::string> OOOXZManager::extractAddOnsPath()
{
    // OO_ADDONSEXTRACTDIR, else "../AddOns" on Windows (%LOCALAPPDATA%\Oolite\AddOns with
    // OO_GAME_DATA_TO_USER_FOLDER), else ~/.Oolite/AddOns.
    return oo::fs::utf8String(oo::ResourcePaths::current().extractAddOnsDirectory());
}

/* Add additional AddOns paths */
std::vector<std::string> OOOXZManager::additionalAddOnsPaths()
{
    // OO_ADDITIONALADDONSDIRS split on ',' (empty components kept, as before).
    std::vector<std::string> result;
    for (const oo::fs::Path& path : oo::ResourcePaths::current().additionalAddOnsDirectories())
        result.push_back(oo::fs::utf8String(path));
    return result;
}

std::optional<std::string> OOOXZManager::extractionBasePathForIdentifier(const std::string& identifier, const std::string& version)
{
    const std::vector<std::string> userRootPaths = ResourceManager::userRootPaths();
    if (userRootPaths.empty())
        return std::nullopt;
    const std::string& basePath = userRootPaths.back();
    std::string mainDir = identifier + "-" + version + ".off";

    // The blacklisted characters (all ASCII) are removed.
    std::erase_if(mainDir, [](char c) { return std::string_view("'#%^&{}[]/~|\\?<,:\" ").find(c) != std::string_view::npos; });
    return oo::str::appendingPathComponent(basePath, mainDir);
}

bool OOOXZManager::ensureInstallPath()
{
    const std::optional<std::string> path = installPath();
    const oo::fs::Path fsPath = oo::fs::pathFromUTF8(path.value_or(std::string()));
    const bool exists = path.has_value() && oo::fs::fileExists(fsPath);

    if (exists && !oo::fs::isDirectory(fsPath)) {
        OO_LOG("oxz.manager.error", "Expected {} to be a folder, but it is a file.", path.value_or("(null)"));
        return false;
    }
    if (!exists) {
        if (!path.has_value() || !oo::fs::createDirectories(fsPath)) {
            OO_LOG("oxz.manager.error", "Could not create folder {}.", path.value_or("(null)"));
            return false;
        }
    }

    return true;
}

std::optional<std::string> OOOXZManager::manifestPath()
{
    const std::optional<std::string> cacheDirectory = OOCacheManager::sharedCache()->cacheDirectoryPathCreatingIfNecessary(true);
    if (!cacheDirectory.has_value())
        return std::nullopt;
    return oo::str::appendingPathComponent(*cacheDirectory, kOOOXZManifestCache);
}

/* Download mechanism could destroy a correct file if it failed
 * half-way and was downloaded on top of the old one. So this loads it
 * off to the side a bit */
std::optional<std::string> OOOXZManager::downloadPath()
{
    const std::optional<std::string> cacheDirectory = OOCacheManager::sharedCache()->cacheDirectoryPathCreatingIfNecessary(true);
    if (!cacheDirectory.has_value())
        return std::nullopt;
    if (_interfaceState == OXZ_STATE_UPDATING) {
        return oo::str::appendingPathComponent(*cacheDirectory, kOOOXZTmpPlistPath);
    } else {
        return oo::str::appendingPathComponent(*cacheDirectory, kOOOXZTmpPath);
    }
}

std::optional<std::string> OOOXZManager::dataURL()
{
    /* Not expected to be set in general, but might be useful for some users */
    const std::optional<std::string> url = oo::Defaults::standard().stringForKey(kOOOXZDataConfig);
    if (url.has_value()) {
        return url;
    }
    return kOOOXZDataURL;
}

std::optional<std::string> OOOXZManager::humanSize(NSUInteger bytes)
{
    if (bytes == 0) {
        return OO_DESC("oolite-oxzmanager-missing-field");
    } else if (bytes < 1024) {
        return "<1 kB";
    } else if (bytes < static_cast<NSUInteger>(1024) * 1024) // the product in NSUInteger, as the Objective-C compare promoted it
    {
        return oo::str::format("%zu kB", (size_t)(bytes >> 10));
    } else {
        return oo::str::format("%.2f MB", ((float)(bytes >> 10)) / 1024);
    }
}

void OOOXZManager::setOXZList(const oo::PList& list)
{
    _oxzList = oo::PList();
    if (list) {
        // category, then title, then version descending (OXZOrderedBefore); ties keep list order
        oo::PList::Array sorted = Elements(list);
        std::stable_sort(sorted.begin(), sorted.end(), OXZOrderedBefore);
        _oxzList = oo::PList(std::move(sorted));
        // needed for update to available versions
        _managedList = oo::PList();
    }
}

void OOOXZManager::setFilteredList(const oo::PList& list)
{
    _filteredList = list;
}

void OOOXZManager::setFilter(const std::string& filter)
{
    _currentFilter = oo::str::lowercase(filter);
}

void OOOXZManager::setOXPURL(const std::optional<std::string>& url)
{
    _currentOXPURL = url.has_value() ? std::optional<std::string>(oo::str::lowercase(*url)) : std::nullopt;
}

oo::PList OOOXZManager::applyCurrentFilter(const oo::PList& list)
{
    /*	The filter is a member function (was a selector, called through its IMP: bead oo-3rb.53,
            and before that a Foundation invocation object). The one-argument filters take the
            manifest; the rest take the manifest and the parameter (the prefixes are ASCII, so the
            byte offset is the old character offset).
    */
    typedef bool (OOOXZManager::*OneArgumentFilter)(const oo::PList&);
    typedef bool (OOOXZManager::*TwoArgumentFilter)(const oo::PList&, const std::string&);
    OneArgumentFilter oneArgumentFilter = &OOOXZManager::applyFilterByNoFilter;
    TwoArgumentFilter twoArgumentFilter = nullptr;
    std::string parameter;
    if (_currentFilter == kOOOXZFilterUpdates) {
        oneArgumentFilter = &OOOXZManager::applyFilterByUpdateRequired;
    } else if (_currentFilter == kOOOXZFilterInstallable) {
        oneArgumentFilter = &OOOXZManager::applyFilterByInstallable;
    } else if (oo::str::hasPrefix(_currentFilter, kOOOXZFilterKeyword)) {
        twoArgumentFilter = &OOOXZManager::applyFilterByKeyword;
        parameter = _currentFilter.substr(kOOOXZFilterKeyword.size());
    } else if (oo::str::hasPrefix(_currentFilter, kOOOXZFilterAuthor)) {
        twoArgumentFilter = &OOOXZManager::applyFilterByAuthor;
        parameter = _currentFilter.substr(kOOOXZFilterAuthor.size());
    } else if (oo::str::hasPrefix(_currentFilter, kOOOXZFilterDays)) {
        twoArgumentFilter = &OOOXZManager::applyFilterByDays;
        parameter = _currentFilter.substr(kOOOXZFilterDays.size());
    } else if (oo::str::hasPrefix(_currentFilter, kOOOXZFilterTag)) {
        twoArgumentFilter = &OOOXZManager::applyFilterByTag;
        parameter = _currentFilter.substr(kOOOXZFilterTag.size());
    } else if (oo::str::hasPrefix(_currentFilter, kOOOXZFilterCategory)) {
        twoArgumentFilter = &OOOXZManager::applyFilterByCategory;
        parameter = _currentFilter.substr(kOOOXZFilterCategory.size());
    }

    oo::PList::Array filteredList;
    for (const oo::PList& manifest : Elements(list)) {
        bool filterAccepted = false;
        if (twoArgumentFilter != nullptr) {
            filterAccepted = (this->*twoArgumentFilter)(manifest, parameter);
        } else {
            filterAccepted = (this->*oneArgumentFilter)(manifest);
        }
        if (filterAccepted) {
            filteredList.push_back(manifest);
        }
    }
    // any bad filter that gets this far is also treated as '*'
    // so don't need to explicitly test for '*' or ''
    return oo::PList(std::move(filteredList));
}

/*** Start filters ***/
bool OOOXZManager::applyFilterByNoFilter(const oo::PList&)
{
    return true;
}

bool OOOXZManager::applyFilterByUpdateRequired(const oo::PList& manifest)
{
    return (installableState(manifest) == OXZ_INSTALLABLE_UPDATE);
}

bool OOOXZManager::applyFilterByInstallable(const oo::PList& manifest)
{
    return (installableState(manifest) < OXZ_UNINSTALLABLE_ALREADY);
}

bool OOOXZManager::applyFilterByKeyword(const oo::PList& manifest, const std::string& keyword)
{
    // trim any eventual leading whitespace from input string
    const std::string trimmed = oo::str::trimLeadingWhitespaceAndNewlines(keyword);
    const std::string parameters[] = { std::string(kOOManifestTitle), std::string(kOOManifestDescription), std::string(kOOManifestCategory) };

    for (const std::string& parameter : parameters) {
        if (FoundIgnoringCase(ManifestString(manifest, parameter), trimmed)) {
            return true;
        }
    }
    // tags are slightly different
    return TagFoundIgnoringCase(manifest, trimmed);
}

bool OOOXZManager::applyFilterByAuthor(const oo::PList& manifest, const std::string& author)
{
    // trim any eventual leading whitespace from input string
    const std::string trimmed = oo::str::trimLeadingWhitespaceAndNewlines(author);

    return FoundIgnoringCase(ManifestString(manifest, std::string(kOOManifestAuthor)), trimmed);
}

bool OOOXZManager::applyFilterByDays(const oo::PList& manifest, const std::string& days)
{
    NSInteger i = (NSInteger)oo::str::longLongValue(days); // -integerValue
    if (i < 1) {
        return false;
    } else {
        NSUInteger updated = manifest.get<unsigned long long>(std::string(kOOManifestUploadDate));
        NSUInteger now = (NSUInteger)oo::date::timeIntervalSince1970();
        return (updated + (86400 * i) > now);
    }
}

bool OOOXZManager::applyFilterByTag(const oo::PList& manifest, const std::string& tag)
{
    // trim any eventual leading whitespace from input string
    return TagFoundIgnoringCase(manifest, oo::str::trimLeadingWhitespaceAndNewlines(tag));
}

bool OOOXZManager::applyFilterByCategory(const oo::PList& manifest, const std::string& category)
{
    // trim any eventual leading whitespace from input string
    const std::string trimmed = oo::str::trimLeadingWhitespaceAndNewlines(category);

    return FoundIgnoringCase(ManifestString(manifest, std::string(kOOManifestCategory)), trimmed);
}

/*** End filters ***/

bool OOOXZManager::validateFilter(const std::string& input)
{
    const std::string filter = oo::str::lowercase(input);
    // The prefixes are ASCII: a byte count past one is a character past it.
    if ((filter.empty()) // empty is valid
        || (filter == kOOOXZFilterAll)
        || (filter == kOOOXZFilterUpdates)
        || (filter == kOOOXZFilterInstallable)
        || (oo::str::hasPrefix(filter, kOOOXZFilterKeyword) && filter.size() > kOOOXZFilterKeyword.size())
        || (oo::str::hasPrefix(filter, kOOOXZFilterAuthor) && filter.size() > kOOOXZFilterAuthor.size())
        || (oo::str::hasPrefix(filter, kOOOXZFilterDays) && oo::str::intValue(filter.substr(kOOOXZFilterDays.size())) > 0)
        || (oo::str::hasPrefix(filter, kOOOXZFilterTag) && filter.size() > kOOOXZFilterTag.size())
        || (oo::str::hasPrefix(filter, kOOOXZFilterCategory) && filter.size() > kOOOXZFilterCategory.size())) {
        return true;
    }

    return false;
}

void OOOXZManager::setCurrentDownload(oo::http::Download* download, const std::string& label)
{
    // Deleting the previous download cancels it and frees it.
    delete _currentDownload;
    _currentDownload = download;
    _currentDownloadName = label;
}

void OOOXZManager::setProgressStatus(const std::string& newValue)
{
    _progressStatus = newValue;
}

bool OOOXZManager::updateManifests()
{
    const std::string url = dataURL().value_or("");
    if (_downloadStatus != OXZ_DOWNLOAD_NONE) {
        return false;
    }
    _downloadStatus = OXZ_DOWNLOAD_STARTED;
    _interfaceState = OXZ_STATE_UPDATING;
    setProgressStatus("");

    return beginDownload(url);
}

bool OOOXZManager::beginDownload(const std::string& url)
{
    // No cookies are sent or kept, as -setHTTPShouldHandleCookies:NO had it (oofnd/Http.hpp).
    const std::optional<std::string> bundleVersion = OoliteInfoString("CFBundleVersion");
    const std::string userAgent = oo::str::format("Oolite/%s", bundleVersion.value_or("").c_str());
    // A download always starts: a URL it cannot fetch arrives as a failure callback.
    oo::http::Download* download = new oo::http::Download(url, userAgent);
    _downloadProgress = 0;
    _downloadExpected = 0;
    std::string label = OO_DESC("oolite-oxzmanager-download-label-list");
    if (_interfaceState != OXZ_STATE_UPDATING) {
        const oo::PList expectedManifest = ElementAt(_filteredList, _item);
        label = ManifestStringOr(expectedManifest, std::string(kOOManifestTitle),
            OO_DESC("oolite-oxzmanager-download-label-oxz"))
                    .value_or("");
    }

    setCurrentDownload(download, label); // owns it
    OO_LOG("oxz.manager.debug", "Download request received, using {} and downloading to {}", url, downloadPath().value_or("(null)"));
    return true;
}

void OOOXZManager::processDownloadEvents()
{
    // The current download is read afresh for every event: a callback may cancel it or start
    // another, and a cancelled download answers nothing more.
    while (_currentDownload != nullptr) {
        std::optional<oo::http::Event> event = _currentDownload->nextEvent();
        if (!event.has_value())
            break;
        {
            oo::AutoreleaseScope pool; // was @autoreleasepool (oo-31u.8)
            switch (event->kind) {
            case oo::http::Event::Kind::response:
                downloadDidReceiveResponse(event->expectedLength);
                break;
            case oo::http::Event::Kind::data:
                downloadDidReceiveData(event->bytes);
                break;
            case oo::http::Event::Kind::finished:
                downloadDidFinishLoading();
                break;
            case oo::http::Event::Kind::failed:
                downloadDidFailWithError(event->error);
                break;
            }
        }
    }
}

bool OOOXZManager::cancelUpdate()
{
    if (!(_interfaceState == OXZ_STATE_UPDATING || _interfaceState == OXZ_STATE_INSTALLING) || _downloadStatus == OXZ_DOWNLOAD_NONE) {
        return false;
    }
    OO_LOG("oxz.manager.debug", "{}", "Trying to cancel file download");
    if (_currentDownload != nullptr) {
        _currentDownload->cancel(); // kept until the next download replaces it, as the connection was
    } else if (_downloadStatus == OXZ_DOWNLOAD_COMPLETE) {
        if (const std::optional<std::string> path = downloadPath()) {
            (void)oo::fs::removeItem(oo::fs::pathFromUTF8(*path));
        }
    }
    _downloadStatus = OXZ_DOWNLOAD_NONE;
    if (_interfaceState == OXZ_STATE_INSTALLING) {
        _interfaceState = OXZ_STATE_PICK_INSTALL;
    } else {
        _interfaceState = OXZ_STATE_MAIN;
    }
    gui(); // slice 3, still Objective-C on the facade
    return true;
}

oo::PList OOOXZManager::manifests()
{
    return _oxzList;
}

oo::PList OOOXZManager::managedOXZs()
{
    if (!_managedList) {
        // if this list is being reset, also reset the current install list
        ResourceManager::resetManifestKnowledgeForOXZManager();
        const std::optional<std::string> installPath = this->installPath();
        std::vector<std::string> filenames;
        if (installPath.has_value()) {
            auto contents = oo::fs::directoryContents(oo::fs::pathFromUTF8(*installPath));
            if (contents)
                filenames = std::move(*contents);
        }
        oo::PList::Array manifests;
        for (const std::string& filename : filenames) {
            const std::string fullpath = oo::str::appendingPathComponent(*installPath, filename);
            const oo::PList manifest = PListDictionaryFromFile(oo::str::appendingPathComponent(fullpath, "manifest.plist"));
            if (manifest) {
                oo::PList adjManifest = manifest;
                oo::PList::Dict& adjEntries = *adjManifest.getIf<oo::PList::Dict>();
                adjEntries[std::string(kOOManifestFilePath)] = oo::PList(fullpath);

                const std::optional<std::string> identifier = ManifestString(manifest, std::string(kOOManifestIdentifier));
                /* The list is already sorted to put the latest
                 * versions first. This flag means that it stops
                 * checking the list for versions once it finds one
                 * that is plausibly installable */
                bool foundInstallable = false;
                for (const oo::PList& stored : Elements(_oxzList)) {
                    const std::optional<std::string> storedIdentifier = ManifestString(stored, std::string(kOOManifestIdentifier));
                    if (storedIdentifier.has_value() && identifier.has_value() && *storedIdentifier == *identifier) {
                        if (foundInstallable == false) {
                            // (A missing value raised on -setObject:forKey:; it is now not set.)
                            if (const std::optional<std::string> version = ManifestString(stored, std::string(kOOManifestVersion))) {
                                adjEntries[std::string(kOOManifestAvailableVersion)] = oo::PList(*version);
                            }
                            if (const std::optional<std::string> url = ManifestString(stored, std::string(kOOManifestDownloadURL))) {
                                adjEntries[std::string(kOOManifestDownloadURL)] = oo::PList(*url);
                            }
                            if (ResourceManager::checkVersionCompatibility(manifest, std::nullopt)) {
                                foundInstallable = true;
                            }
                        }
                    }
                }

                manifests.push_back(std::move(adjManifest));
            }
        }
        std::stable_sort(manifests.begin(), manifests.end(), OXZOrderedBefore);

        _managedList = oo::PList(std::move(manifests));
    }
    return _managedList;
}

bool OOOXZManager::processDownloadedManifests()
{
    if (_downloadStatus != OXZ_DOWNLOAD_COMPLETE) {
        return false;
    }
    setOXZList(PListArrayFromFile(downloadPath()));
    if (_oxzList) {
        // As -writeToFile:atomically: wrote it: GNUstep's XML property list, atomically; nothing
        // for no cache directory (a nil path), and a failure is ignored as before.
        if (const std::optional<std::string> manifestPath = this->manifestPath())
            (void)OOWriteXMLPListToFile(_oxzList, *manifestPath, nullptr);
        // and clean up the temp file
        if (const std::optional<std::string> downloadPath = this->downloadPath()) {
            (void)oo::fs::removeItem(oo::fs::pathFromUTF8(*downloadPath));
        }
        // invalidate the managed list
        _managedList = oo::PList();
        _interfaceState = OXZ_STATE_TASKDONE;
        gui();
        return true;
    } else {
        _downloadStatus = OXZ_DOWNLOAD_ERROR;
        OO_LOG("oxz.manager.error", "Downloaded manifest was not a valid plist, has been left in {}", downloadPath().value_or("(null)"));
        // revert to the old one
        setOXZList(PListArrayFromFile(manifestPath()));
        _interfaceState = OXZ_STATE_TASKDONE;
        gui();
        return false;
    }
}

bool OOOXZManager::processDownloadedOXZ()
{
    if (_downloadStatus != OXZ_DOWNLOAD_COMPLETE) {
        return false;
    }

    const std::optional<std::string> downloadPath = this->downloadPath();
    const oo::PList downloadedManifest = downloadPath.has_value()
        ? cxx_OOPropertyListFromFile(oo::str::appendingPathComponent(*downloadPath, "manifest.plist"))
        : oo::PList();
    if (!downloadedManifest) {
        _downloadStatus = OXZ_DOWNLOAD_ERROR;
        OO_LOG("oxz.manager.error", "Downloaded OXZ does not contain a manifest.plist, has been left in {}", downloadPath.value_or("(null)"));
        _interfaceState = OXZ_STATE_TASKDONE;
        gui();
        return false;
    }
    const oo::PList expectedManifest = ElementAt(_filteredList, _item);

    const std::optional<std::string> downloadedId = ManifestString(downloadedManifest, std::string(kOOManifestIdentifier));
    const std::optional<std::string> expectedId = ManifestString(expectedManifest, std::string(kOOManifestIdentifier));
    const std::optional<std::string> downloadedVer = ManifestString(downloadedManifest, std::string(kOOManifestVersion));
    const std::optional<std::string> expectedVer = ManifestStringOr(expectedManifest, std::string(kOOManifestAvailableVersion),
        ManifestString(expectedManifest, std::string(kOOManifestVersion)));
    if (!expectedManifest || !downloadedId.has_value() || !expectedId.has_value() || *downloadedId != *expectedId
        || !downloadedVer.has_value() || !expectedVer.has_value() || *downloadedVer != *expectedVer) {
        _downloadStatus = OXZ_DOWNLOAD_ERROR;
        OO_LOG("oxz.manager.error", "{}", "Downloaded OXZ does not have the same identifer and version as expected. This might be due to your manifests list being out of date - try updating it.");
        _interfaceState = OXZ_STATE_TASKDONE;
        gui();
        return false;
    }
    // filename is going to be identifier.oxz
    const std::string filename = *downloadedId + ".oxz";

    if (!ensureInstallPath()) {
        _downloadStatus = OXZ_DOWNLOAD_ERROR;
        OO_LOG("oxz.manager.error", "{}", "Unable to create installation folder.");
        _interfaceState = OXZ_STATE_TASKDONE;
        gui();
        return false;
    }

    const std::optional<std::string> installPath = this->installPath();
    if (!installPath.has_value() || !downloadPath.has_value()) {
        _downloadStatus = OXZ_DOWNLOAD_ERROR;
        OO_LOG("oxz.manager.error", "{}", "Downloaded OXZ could not be installed.");
        _interfaceState = OXZ_STATE_TASKDONE;
        gui();
        return false;
    }
    const std::string destination = oo::str::appendingPathComponent(*installPath, filename);
    (void)oo::fs::removeItem(oo::fs::pathFromUTF8(destination));

    if (!oo::fs::moveItem(oo::fs::pathFromUTF8(*downloadPath), oo::fs::pathFromUTF8(destination))) {
        _downloadStatus = OXZ_DOWNLOAD_ERROR;
        OO_LOG("oxz.manager.error", "{}", "Downloaded OXZ could not be installed.");
        _interfaceState = OXZ_STATE_TASKDONE;
        gui();
        return false;
    }
    _changesMade = true;
    _managedList = oo::PList(); // will need updating
    ResourceManager::resetManifestKnowledgeForOXZManager();

    const oo::PList* requiredNode = downloadedManifest.find(std::string(kOOManifestRequiresOXPs));
    if (requiredNode == nullptr || !requiredNode->isArray()) {
        requiredNode = expectedManifest.find(std::string(kOOManifestRequiresOXPs));
    }
    const oo::PList::Array& requiredOXPs = (requiredNode != nullptr && requiredNode->isArray())
        ? Elements(*requiredNode)
        : Elements(oo::PList());

    std::string progress;
    progress.reserve(2048);
    OO_LOG("oxz.manager.debug", "Dependency stack has {} elements", _dependencyStack.size());

    if (!_dependencyStack.empty()) {
        const std::vector<oo::PList> tempStack = _dependencyStack;
        for (const oo::PList& requirement : tempStack) {
            OO_LOG("oxz.manager.debug", "Dependency stack: checking {}", ManifestString(requirement, std::string(kOOManifestRelationIdentifier)).value_or("(null)"));
            bool inRequired = false;
            for (const oo::PList& req : requiredOXPs) {
                if (req == requirement) {
                    inRequired = true;
                    break;
                }
            }
            if (!ResourceManager::manifest(downloadedManifest, requirement, NO)
                && !requiredOXPs.empty() && inRequired) {
                progress += DescFormat(OO_DESC("oolite-oxzmanager-progress-now-has-@"), { Arg(ManifestStringOr(requirement, std::string(kOOManifestRelationDescription), ManifestString(requirement, std::string(kOOManifestRelationIdentifier)))) });
                DependencyStackRemove(_dependencyStack, requirement);
                OO_LOG("oxz.manager.debug", "{}", "Dependency stack: requirement met");
            } else if (ManifestString(requirement, std::string(kOOManifestRelationIdentifier)) == downloadedId) {
                DependencyStackRemove(_dependencyStack, requirement);
            }
        }
    }
    if (!requiredOXPs.empty()) {
        for (const oo::PList& requirement : requiredOXPs) {
            if (ResourceManager::manifest(downloadedManifest, requirement, NO)) {
                OO_LOG("oxz.manager.debug", "Dependency stack: adding {}", ManifestString(requirement, std::string(kOOManifestRelationIdentifier)).value_or("(null)"));
                DependencyStackAdd(_dependencyStack, requirement);
                progress += DescFormat(OO_DESC("oolite-oxzmanager-progress-requires-@"), { Arg(ManifestStringOr(requirement, std::string(kOOManifestRelationDescription), ManifestString(requirement, std::string(kOOManifestRelationIdentifier)))) });
            }
        }
    }
    if (!_dependencyStack.empty()) {
        bool undownloadedRequirement = false;
        bool foundDownload = false;
        NSUInteger index = 0;
        std::optional<std::string> needsIdentifier;
        oo::PList requirement;

        do {
            undownloadedRequirement = true;
            requirement = _dependencyStack.front(); // was anyObject; order-sensitive — named in commit
            OO_LOG("oxz.manager.debug", "Dependency stack: next is {}", ManifestString(requirement, std::string(kOOManifestRelationIdentifier)).value_or("(null)"));

            if (!_downloadAllDependencies) {
                progress += OO_DESC("oolite-oxzmanager-progress-get-required");
            }
            needsIdentifier = ManifestString(requirement, std::string(kOOManifestRelationIdentifier));

            for (NSUInteger i = 0; i < _oxzList.count(); i++) {
                const oo::PList& availableDownload = *_oxzList.at(i);
                const std::optional<std::string> availableIdentifier = ManifestString(availableDownload, std::string(kOOManifestIdentifier));
                if (availableIdentifier.has_value() && needsIdentifier.has_value() && *availableIdentifier == *needsIdentifier) {
                    if (ResourceManager::matchVersions(requirement, ManifestString(availableDownload, std::string(kOOManifestVersion)).value_or(""))) {
                        OO_LOG("oxz.manager.debug", "{}", "Dependency stack: found download for next item");
                        foundDownload = true;
                        index = i;
                        break;
                    }
                }
            }

            if (foundDownload) {
                if (installableState(ElementAt(_oxzList, index)) == OXZ_UNINSTALLABLE_ALREADY) {
                    OO_LOG("oxz.manager.debug", "Dependency stack: {} is downloaded but not yet loadable, removing from list.", ManifestString(requirement, std::string(kOOManifestRelationIdentifier)).value_or("(null)"));
                    DependencyStackRemove(_dependencyStack, requirement);
                    if (!_dependencyStack.empty()) {
                        undownloadedRequirement = false;
                    } else {
                        foundDownload = false;
                    }
                }
            }
        } while (!undownloadedRequirement);

        if (foundDownload) {
            setFilteredList(_oxzList);
            _downloadStatus = OXZ_DOWNLOAD_NONE;
            if (_downloadAllDependencies) {
                OO_LOG("oxz.manager.debug", "Dependency stack: installing {} from list", index);
                if (!installOXZ(index)) {
                    progress += DescFormat(OO_DESC("oolite-oxzmanager-progress-required-@-not-found"), { Arg(ManifestStringOr(requirement, std::string(kOOManifestRelationDescription), ManifestString(requirement, std::string(kOOManifestRelationIdentifier)))) });
                    setProgressStatus(progress);
                    OO_LOG("oxz.manager.error", "OXZ dependency {} could not be found for automatic download.", needsIdentifier.value_or("(null)"));
                    _downloadStatus = OXZ_DOWNLOAD_ERROR;
                    OO_LOG("oxz.manager.error", "{}", "Downloaded OXZ could not be installed.");
                    _interfaceState = OXZ_STATE_TASKDONE;
                    gui();
                    return false;
                }
            } else {
                _interfaceState = OXZ_STATE_DEPENDENCIES;
                _item = index;
            }
            setProgressStatus(progress);
            gui();
            return true;
        } else if (!_dependencyStack.empty()) {
            progress += DescFormat(OO_DESC("oolite-oxzmanager-progress-required-@-not-found"), { Arg(ManifestStringOr(requirement, std::string(kOOManifestRelationDescription), ManifestString(requirement, std::string(kOOManifestRelationIdentifier)))) });
            setProgressStatus(progress);
            OO_LOG("oxz.manager.error", "OXZ dependency {} could not be found for automatic download.", needsIdentifier.value_or("(null)"));
            _downloadStatus = OXZ_DOWNLOAD_ERROR;
            OO_LOG("oxz.manager.error", "{}", "Downloaded OXZ could not be installed.");
            _interfaceState = OXZ_STATE_TASKDONE;
            gui();
            return false;
        }
    }

    setProgressStatus("");
    _interfaceState = OXZ_STATE_TASKDONE;
    _dependencyStack.clear(); // just in case
    _downloadAllDependencies = false;
    gui();
    return true;
}

oo::PList OOOXZManager::installedManifestForIdentifier(const std::string& identifier)
{
    const oo::PList installed = managedOXZs();
    if (const oo::PList::Array* manifests = installed.getIf<oo::PList::Array>()) {
        for (const oo::PList& manifest : *manifests) {
            if (ManifestString(manifest, std::string(kOOManifestIdentifier)) == identifier) {
                return manifest;
            }
        }
    }
    return oo::PList();
}

OXZInstallableState OOOXZManager::installableState(const oo::PList& manifest)
{
    const std::optional<std::string> title = ManifestString(manifest, std::string(kOOManifestTitle));
    const std::optional<std::string> identifier = ManifestString(manifest, std::string(kOOManifestIdentifier));
    /* Check Oolite version */
    if (!ResourceManager::checkVersionCompatibility(manifest, title)) {
        return OXZ_UNINSTALLABLE_VERSION;
    }
    /* Check for current automated install (a missing identifier matched nothing) */
    oo::PList installed = identifier.has_value() ? installedManifestForIdentifier(*identifier) : oo::PList();
    if (!installed) {
        // check for manual install
        installed = ResourceManager::manifestForIdentifier(identifier.value_or(std::string()));
    }

    // available_version, else version (the fallback of the old string read)
    std::optional<std::string> availableVersion = ManifestString(manifest, std::string(kOOManifestAvailableVersion));
    if (!availableVersion.has_value()) {
        availableVersion = ManifestString(manifest, std::string(kOOManifestVersion));
    }
    if (installed) {
        const std::optional<std::string> filePath = ManifestString(installed, std::string(kOOManifestFilePath));
        const std::optional<std::string> installPath = this->installPath();
        if (!(filePath.has_value() && installPath.has_value() && oo::str::hasPrefix(*filePath, *installPath))) {
            // installed manually
            return OXZ_UNINSTALLABLE_MANUAL;
        }
        const std::optional<std::string> installedVersion = ManifestString(installed, std::string(kOOManifestVersion));
        if (installedVersion.has_value() && availableVersion.has_value() && *installedVersion == *availableVersion
            && oo::fs::fileExists(oo::fs::pathFromUTF8(*filePath))) {
            // installed this exact version already, and haven't
            // uninstalled it since entering the manager, and it's
            // still available
            return OXZ_UNINSTALLABLE_ALREADY;
        } else if (!ManifestString(installed, std::string(kOOManifestAvailableVersion)).has_value()) {
            // installed, but no remote copy is indexed any more
            return OXZ_UNINSTALLABLE_NOREMOTE;
        }
    }
    /* Check for dependencies being met */
    if (ResourceManager::manifestHasConflicts(manifest, NO)) {
        return OXZ_INSTALLABLE_CONFLICTS;
    }
    if (installed) {
        const std::optional<std::string> installedVersion = ManifestString(installed, std::string(kOOManifestVersion));
        OO_LOG("version.debug", "{} mv:{} mav:{}", identifier.value_or("(null)"), installedVersion.value_or("(null)"), availableVersion.value_or("(null)"));
        // A missing version has no components (the bridge's ComponentsFromVersionString(nil)).
        const std::vector<unsigned> installedComponents = installedVersion.has_value() ? cxx_ComponentsFromVersionString(*installedVersion) : std::vector<unsigned>();
        const std::vector<unsigned> availableComponents = availableVersion.has_value() ? cxx_ComponentsFromVersionString(*availableVersion) : std::vector<unsigned>();
        if (cxx_CompareVersions(installedComponents, availableComponents) == OOOrderedDescending) {
            // the installed copy is more recent than the server copy
            return OXZ_UNINSTALLABLE_NOREMOTE;
        }
        return OXZ_INSTALLABLE_UPDATE;
    }
    if (ResourceManager::manifestHasMissingDependencies(manifest, NO)) {
        return OXZ_INSTALLABLE_DEPENDENCIES;
    }
    return OXZ_INSTALLABLE_OKAY;
}

oo::Ref<OOColor> OOOXZManager::colorForManifest(const oo::PList& manifest)
{
    switch (installableState(manifest)) {
    case OXZ_INSTALLABLE_OKAY:
        return OOColor::yellowColor();
    case OXZ_INSTALLABLE_UPDATE:
        return OOColor::cyanColor();
    case OXZ_INSTALLABLE_DEPENDENCIES:
        return OOColor::orangeColor();
    case OXZ_INSTALLABLE_CONFLICTS:
        return OOColor::brownColor();
    case OXZ_UNINSTALLABLE_ALREADY:
        return OOColor::whiteColor();
    case OXZ_UNINSTALLABLE_MANUAL:
        return OOColor::redColor();
    case OXZ_UNINSTALLABLE_VERSION:
        return OOColor::grayColor();
    case OXZ_UNINSTALLABLE_NOREMOTE:
        return OOColor::blueColor();
    }
    return OOColor::yellowColor(); // never
}

std::optional<std::string> OOOXZManager::installStatusForManifest(const oo::PList& manifest)
{
    switch (installableState(manifest)) {
    case OXZ_INSTALLABLE_OKAY:
        return OO_DESC("oolite-oxzmanager-installable-okay");
    case OXZ_INSTALLABLE_UPDATE:
        return OO_DESC("oolite-oxzmanager-installable-update");
    case OXZ_INSTALLABLE_DEPENDENCIES:
        return OO_DESC("oolite-oxzmanager-installable-depend");
    case OXZ_INSTALLABLE_CONFLICTS:
        return OO_DESC("oolite-oxzmanager-installable-conflicts");
    case OXZ_UNINSTALLABLE_ALREADY:
        return OO_DESC("oolite-oxzmanager-installable-already");
    case OXZ_UNINSTALLABLE_MANUAL:
        return OO_DESC("oolite-oxzmanager-installable-manual");
    case OXZ_UNINSTALLABLE_VERSION:
        return OO_DESC("oolite-oxzmanager-installable-version");
    case OXZ_UNINSTALLABLE_NOREMOTE:
        return OO_DESC("oolite-oxzmanager-installable-noremote");
    }
    return std::nullopt; // never
}

bool OOOXZManager::isRestarting()
{
    // for the restart
    if (EXPECT_NOT(_interfaceState == OXZ_STATE_RESTARTING)) {
        // Rebuilds OXP search
        ResourceManager::reset();
        if (UNIVERSE != nullptr)
            UNIVERSE->reinitAndShowDemo(YES);
        _changesMade = false;
        _interfaceState = OXZ_STATE_MAIN;
        _downloadStatus = OXZ_DOWNLOAD_NONE; // clear error state
        return true;
    } else {
        return false;
    }
}

bool OOOXZManager::installOXZ(NSUInteger item)
{
    if (_filteredList.count() <= item) {
        return false;
    }
    const oo::PList manifest = ElementAt(_filteredList, item);
    _item = item;

    if (installableState(manifest) >= OXZ_UNINSTALLABLE_ALREADY) {
        OO_LOG("oxz.manager.debug", "Cannot install {}", oo::DescriptionOf(manifest));
        // can't be installed on this version of Oolite, or already is installed
        return false;
    }
    const oo::PList* url = manifest.find(std::string(kOOManifestDownloadURL));
    if (url == nullptr) {
        OO_LOG("oxz.manager.error", "{}", "Manifest does not have a download URL - cannot install");
        return false;
    }
    // The URL as a string; any other kind fetches nothing and fails at once (proposed ADR-0044).
    const std::string urlString = ManifestString(manifest, std::string(kOOManifestDownloadURL)).value_or("");
    if (_downloadStatus != OXZ_DOWNLOAD_NONE) {
        return false;
    }
    _downloadStatus = OXZ_DOWNLOAD_STARTED;
    _interfaceState = OXZ_STATE_INSTALLING;

    setProgressStatus("");
    return beginDownload(urlString);
}

bool OOOXZManager::updateAllOXZ()
{
    _dependencyStack.clear();
    _downloadAllDependencies = true;
    setFilteredList(_oxzList);

    for (const oo::PList& entry : Elements(_oxzList)) {
        if (installableState(entry) == OXZ_INSTALLABLE_UPDATE) {
            OO_LOG("oxz.manager.debug", "Queuing in for update: {}", oo::DescriptionOf(entry));
            DependencyStackAdd(_dependencyStack, entry);
        }
    }
    // First requirement is front() (was anyObject; order-sensitive — named in commit).
    const std::optional<std::string> identifier = _dependencyStack.empty()
        ? std::nullopt
        : ManifestString(_dependencyStack.front(), std::string(kOOManifestRelationIdentifier));
    NSUInteger item = NSUIntegerMax;
    for (NSUInteger i = 0; i < _oxzList.count(); i++) {
        const std::optional<std::string> availableIdentifier = ManifestString(*_oxzList.at(i), std::string(kOOManifestIdentifier));
        if (availableIdentifier.has_value() && identifier.has_value() && *availableIdentifier == *identifier) {
            item = i; // the first equal manifest, as -indexOfObject: found
            break;
        }
    }
    return installOXZ(item);
}

bool OOOXZManager::removeOXZ(NSUInteger item)
{
    if (_filteredList.count() <= item) {
        OO_LOG("oxz.manager.debug", "Unable to remove item {} as only {} in list", item, _filteredList.count());
        return false;
    }
    const std::optional<std::string> filename = ManifestString(ElementAt(_filteredList, item), std::string(kOOManifestFilePath));
    if (!filename.has_value()) {
        OO_LOG("oxz.manager.debug", "Unable to remove item {} as filename not found", item);
        return false;
    }

    if (!oo::fs::removeItem(oo::fs::pathFromUTF8(*filename))) {
        OO_LOG("oxz.manager.error", "Unable to remove file {}", *filename);
        return false;
    }
    _changesMade = true;
    _managedList = oo::PList(); // will need updating
    _interfaceState = OXZ_STATE_REMOVING;
    gui();
    return true;
}

void OOOXZManager::gui()
{
    ::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
    OOGUIRow startRow = OXZ_GUI_ROW_EXIT;

#if OOLITE_WINDOWS
    /* unlock OXZs ahead of potential changes by making sure sound
     * files aren't being held open */
    ResourceManager::clearCaches();
    if (PLAYER != nullptr)
        PLAYER->destroySound();
#endif

    if (gui != nullptr) {
        gui->clearAndKeepBackground(YES);
        gui->setTitle(OO_DESC("oolite-oxzmanager-title"));
    }

    /* This switch will give warnings unless all states are
     * covered. */
    switch (_interfaceState) {
    case OXZ_STATE_SETFILTER:
        if (gui != nullptr) {
            gui->setTitle(OO_DESC("oolite-oxzmanager-title-setfilter"));
            gui->setText(DescFormat(OO_DESC("oolite-oxzmanager-currentfilter-is-@"), { _currentFilter }), OXZ_GUI_ROW_FILTERCURRENT, GUI_ALIGN_LEFT);
            gui->addLongText(OO_DESC("oolite-oxzmanager-filterhelp"), OXZ_GUI_ROW_FILTERHELP, GUI_ALIGN_LEFT);
        }

        return; // don't do normal row selection stuff
    case OXZ_STATE_NODATA:
        if (!_oxzList) {
            if (gui != nullptr) {
                gui->addLongText(OO_DESC("oolite-oxzmanager-firstrun"), OXZ_GUI_ROW_FIRSTRUN, GUI_ALIGN_LEFT);
                gui->setText(OO_DESC("oolite-oxzmanager-download-list"), OXZ_GUI_ROW_UPDATE, GUI_ALIGN_CENTER);
                gui->setKey("_UPDATE", OXZ_GUI_ROW_UPDATE);
            }

            startRow = OXZ_GUI_ROW_UPDATE;
        } else {
            // update data
            if (gui != nullptr) {
                gui->addLongText(OO_DESC("oolite-oxzmanager-secondrun"), OXZ_GUI_ROW_FIRSTRUN, GUI_ALIGN_LEFT);
                gui->setText(OO_DESC("oolite-oxzmanager-download-noupdate"), OXZ_GUI_ROW_PROCEED, GUI_ALIGN_CENTER);
                gui->setKey("_MAIN", OXZ_GUI_ROW_PROCEED);

                gui->setText(OO_DESC("oolite-oxzmanager-update-list"), OXZ_GUI_ROW_UPDATE, GUI_ALIGN_CENTER);
                gui->setKey("_UPDATE", OXZ_GUI_ROW_UPDATE);
            }

            startRow = OXZ_GUI_ROW_PROCEED;
        }
        break;
    case OXZ_STATE_RESTARTING:
        if (gui != nullptr)
            gui->addLongText(OO_DESC("oolite-oxzmanager-restart"), OXZ_GUI_ROW_FIRSTRUN, GUI_ALIGN_LEFT);
        return; // yes, return, not break: controls are pointless here
    case OXZ_STATE_MAIN:
        if (gui != nullptr)
            gui->addLongText(OO_DESC("oolite-oxzmanager-intro"), OXZ_GUI_ROW_FIRSTRUN, GUI_ALIGN_LEFT);
        // fall through
    case OXZ_STATE_PICK_INSTALL:
    case OXZ_STATE_PICK_INSTALLED:
    case OXZ_STATE_PICK_REMOVE:
        if (_interfaceState != OXZ_STATE_MAIN) {
            if (gui != nullptr) {
                const std::string filterFormat = OO_DESC("oolite-oxzmanager-currentfilter-is-@-@"); // the format first, as Clang evaluates the arguments: a description that is an array draws (ADR-0063 item 5)
                gui->setText(DescFormat(filterFormat, { cxx_OOExpand("[oolite_key_oxzmanager_setfilter]").value_or("(null)"), _currentFilter }), OXZ_GUI_ROW_LISTFILTER, GUI_ALIGN_LEFT);
                gui->setColor(OOColor::greenColor().get(), OXZ_GUI_ROW_LISTFILTER);
            }
        }

        if (gui != nullptr) {
            gui->setText(OO_DESC("oolite-oxzmanager-install"), OXZ_GUI_ROW_INSTALL, GUI_ALIGN_CENTER);
            gui->setKey("_INSTALL", OXZ_GUI_ROW_INSTALL);
            gui->setText(OO_DESC("oolite-oxzmanager-installed"), OXZ_GUI_ROW_INSTALLED, GUI_ALIGN_CENTER);
            gui->setKey("_INSTALLED", OXZ_GUI_ROW_INSTALLED);
            gui->setText(OO_DESC("oolite-oxzmanager-remove"), OXZ_GUI_ROW_REMOVE, GUI_ALIGN_CENTER);
            gui->setKey("_REMOVE", OXZ_GUI_ROW_REMOVE);
            gui->setText(OO_DESC("oolite-oxzmanager-update-list"), OXZ_GUI_ROW_UPDATE, GUI_ALIGN_CENTER);
            gui->setKey("_UPDATE", OXZ_GUI_ROW_UPDATE);
            gui->setText(OO_DESC("oolite-oxzmanager-update-all"), OXZ_GUI_ROW_UPDATE_ALL, GUI_ALIGN_CENTER);
            gui->setKey("_UPDATE_ALL", OXZ_GUI_ROW_UPDATE_ALL);
        }

        startRow = OXZ_GUI_ROW_INSTALL;
        break;
    case OXZ_STATE_UPDATING:
    case OXZ_STATE_INSTALLING:
        if (gui != nullptr)
            gui->setTitle(OO_DESC("oolite-oxzmanager-title-downloading"));

        if (_downloadStatus == OXZ_DOWNLOAD_ERROR) {
            if (gui != nullptr)
                gui->addLongText(cxx_OOExpandKey("oolite-oxzmanager-progress-error"), OXZ_GUI_ROW_PROGRESS, GUI_ALIGN_LEFT);
        } else {
            if (gui != nullptr) {
                const std::string progressFormat = OO_DESC("oolite-oxzmanager-progress-@-is-@-of-@"); // the format first, as Clang evaluates the arguments: a description that is an array draws (ADR-0063 item 5)
                gui->addLongText(DescFormat(progressFormat, { _currentDownloadName, Arg(humanSize(_downloadProgress)), Arg(humanSize(_downloadExpected)) }), OXZ_GUI_ROW_PROGRESS, GUI_ALIGN_LEFT);
            }
        }
        if (gui != nullptr) {
            gui->addLongText(_progressStatus, OXZ_GUI_ROW_PROGRESS + 2, GUI_ALIGN_LEFT);

            gui->setText(OO_DESC("oolite-oxzmanager-cancel"), OXZ_GUI_ROW_CANCEL, GUI_ALIGN_CENTER);
            gui->setKey("_CANCEL", OXZ_GUI_ROW_CANCEL);
        }
        startRow = OXZ_GUI_ROW_UPDATE;
        break;
    case OXZ_STATE_DEPENDENCIES:
        if (gui != nullptr) {
            gui->setTitle(OO_DESC("oolite-oxzmanager-title-dependencies"));

            gui->setText(OO_DESC("oolite-oxzmanager-dependencies-decision"), OXZ_GUI_ROW_PROGRESS, GUI_ALIGN_LEFT);

            gui->addLongText(_progressStatus, OXZ_GUI_ROW_PROGRESS + 2, GUI_ALIGN_LEFT);
        }

        startRow = OXZ_GUI_ROW_INSTALLED;
        if (gui != nullptr) {
            gui->setText(OO_DESC("oolite-oxzmanager-dependencies-yes-all"), OXZ_GUI_ROW_INSTALLED, GUI_ALIGN_CENTER);
            gui->setKey("_PROCEED_ALL", OXZ_GUI_ROW_INSTALLED);

            gui->setText(OO_DESC("oolite-oxzmanager-dependencies-yes"), OXZ_GUI_ROW_PROCEED, GUI_ALIGN_CENTER);
            gui->setKey("_PROCEED", OXZ_GUI_ROW_PROCEED);

            gui->setText(OO_DESC("oolite-oxzmanager-dependencies-no"), OXZ_GUI_ROW_CANCEL, GUI_ALIGN_CENTER);
            gui->setKey("_CANCEL", OXZ_GUI_ROW_CANCEL);
        }
        break;

    case OXZ_STATE_REMOVING:
        if (gui != nullptr) {
            gui->addLongText(OO_DESC("oolite-oxzmanager-removal-done"), OXZ_GUI_ROW_PROGRESS, GUI_ALIGN_LEFT);
            gui->setText(OO_DESC("oolite-oxzmanager-acknowledge"), OXZ_GUI_ROW_UPDATE, GUI_ALIGN_CENTER);
            gui->setKey("_ACK", OXZ_GUI_ROW_UPDATE);
        }
        startRow = OXZ_GUI_ROW_UPDATE;
        break;
    case OXZ_STATE_TASKDONE:
        if (_downloadStatus == OXZ_DOWNLOAD_COMPLETE) {
            const auto doneText = DescFormat(OO_DESC("oolite-oxzmanager-progress-done-%u-%u"), { (unsigned long long)_oxzList.count(), (unsigned long long)managedOXZs().count() }); // (evaluated, as a message's arguments were, whether or not there is a GUI)
            if (gui != nullptr)
                gui->addLongText(doneText, OXZ_GUI_ROW_PROGRESS, GUI_ALIGN_LEFT);
        } else {
            if (gui != nullptr)
                gui->addLongText(cxx_OOExpandKey("oolite-oxzmanager-progress-error"), OXZ_GUI_ROW_PROGRESS, GUI_ALIGN_LEFT);
        }
        if (gui != nullptr) {
            gui->addLongText(_progressStatus, OXZ_GUI_ROW_PROGRESS + 4, GUI_ALIGN_LEFT);

            gui->setText(OO_DESC("oolite-oxzmanager-acknowledge"), OXZ_GUI_ROW_UPDATE, GUI_ALIGN_CENTER);
            gui->setKey("_ACK", OXZ_GUI_ROW_UPDATE);
        }
        startRow = OXZ_GUI_ROW_UPDATE;
        break;
    case OXZ_STATE_EXTRACT: {
        const oo::PList manifest = ElementAt(_filteredList, _item);
        const std::optional<std::string> title = ManifestString(manifest, std::string(kOOManifestTitle));
        const std::optional<std::string> version = ManifestString(manifest, std::string(kOOManifestVersion));
        const std::optional<std::string> identifier = ManifestString(manifest, std::string(kOOManifestIdentifier));
        if (gui != nullptr) {
            gui->setTitle(OO_DESC("oolite-oxzmanager-title-extract"));
            gui->setText(DescFormat(OO_DESC("oolite-oxzmanager-infopage-title-@-version-@"), { Arg(title), Arg(version) }), 0, GUI_ALIGN_LEFT);
            gui->addLongText(OO_DESC("oolite-oxzmanager-extract-info"), 2, GUI_ALIGN_LEFT);
        }
#ifndef OO_DEBUG_MONITOR_ENABLED
        if (gui != nullptr) {
            gui->addLongText(OO_DESC("oolite-oxzmanager-extract-releasebuild"), 7, GUI_ALIGN_LEFT);
            gui->setColor(OOColor::orangeColor().get(), 7);
            gui->setColor(OOColor::orangeColor().get(), 8);
        }
#endif
        // (a nil identifier or version read "(null)" in the directory name)
        const std::optional<std::string> path = extractionBasePathForIdentifier(identifier.value_or("(null)"), version.value_or("(null)"));
        if (path.has_value() && oo::fs::fileExists(oo::fs::pathFromUTF8(*path))) {
            if (gui != nullptr)
                gui->addLongText(DescFormat(OO_DESC("oolite-oxzmanager-extract-@-already-exists"), { Arg(path) }), 10, GUI_ALIGN_LEFT);
            startRow = OXZ_GUI_ROW_CANCEL;
            if (gui != nullptr) {
                gui->setText(OO_DESC("oolite-oxzmanager-extract-unavailable"), OXZ_GUI_ROW_PROCEED, GUI_ALIGN_CENTER);
                gui->setColor(OOColor::grayColor().get(), OXZ_GUI_ROW_PROCEED);
            }
        } else {
            if (gui != nullptr)
                gui->addLongText(DescFormat(OO_DESC("oolite-oxzmanager-extract-to-@"), { Arg(path) }), 10, GUI_ALIGN_LEFT);
            startRow = OXZ_GUI_ROW_PROCEED;
            if (gui != nullptr) {
                gui->setText(OO_DESC("oolite-oxzmanager-extract-proceed"), OXZ_GUI_ROW_PROCEED, GUI_ALIGN_CENTER);
                gui->setKey("_PROCEED", OXZ_GUI_ROW_PROCEED);
            }
        }
        if (gui != nullptr) {
            gui->setText(OO_DESC("oolite-oxzmanager-extract-cancel"), OXZ_GUI_ROW_CANCEL, GUI_ALIGN_CENTER);
            gui->setKey("_CANCEL", OXZ_GUI_ROW_CANCEL);
        }

    } break;
    case OXZ_STATE_EXTRACTDONE:
        if (gui != nullptr) {
            gui->addLongText(_progressStatus, 1, GUI_ALIGN_LEFT);
            gui->setText(OO_DESC("oolite-oxzmanager-acknowledge"), OXZ_GUI_ROW_UPDATE, GUI_ALIGN_CENTER);
            gui->setKey("_ACK", OXZ_GUI_ROW_UPDATE);
        }
        startRow = OXZ_GUI_ROW_UPDATE;
        break;
    }

    if (_interfaceState == OXZ_STATE_PICK_INSTALL) {
        if (gui != nullptr)
            gui->setTitle(OO_DESC("oolite-oxzmanager-title-install"));
        setFilteredList(applyCurrentFilter(_oxzList));
        startRow = showInstallOptions();
    } else if (_interfaceState == OXZ_STATE_PICK_INSTALLED) {
        if (gui != nullptr)
            gui->setTitle(OO_DESC("oolite-oxzmanager-title-installed"));
        setFilteredList(applyCurrentFilter(managedOXZs()));
        startRow = showInstallOptions();
    } else if (_interfaceState == OXZ_STATE_PICK_REMOVE) {
        if (gui != nullptr)
            gui->setTitle(OO_DESC("oolite-oxzmanager-title-remove"));
        setFilteredList(applyCurrentFilter(managedOXZs()));
        startRow = showRemoveOptions();
    }

    if (_changesMade) {
        if (gui != nullptr)
            gui->setText(OO_DESC("oolite-oxzmanager-exit-restart"), OXZ_GUI_ROW_EXIT, GUI_ALIGN_CENTER);
    } else {
        if (gui != nullptr)
            gui->setText(OO_DESC("oolite-oxzmanager-exit"), OXZ_GUI_ROW_EXIT, GUI_ALIGN_CENTER);
    }
    if (gui != nullptr) {
        gui->setKey("_EXIT", OXZ_GUI_ROW_EXIT);
        gui->setSelectableRange(NSMakeRange(startRow, 2 + (OXZ_GUI_ROW_EXIT - startRow)));
    }
    if (startRow < OXZ_GUI_ROW_INSTALL) {
        if (gui != nullptr)
            gui->setSelectedRow(OXZ_GUI_ROW_INSTALL);
    } else if (_interfaceState == OXZ_STATE_NODATA) {
        if (gui != nullptr)
            gui->setSelectedRow(OXZ_GUI_ROW_UPDATE);
    } else {
        if (gui != nullptr)
            gui->setSelectedRow(startRow);
    }
}

void OOOXZManager::processSelection()
{
    ::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
    OOGUIRow selection = (gui != nullptr ? gui->getSelectedRow() : 0);

    if (selection == OXZ_GUI_ROW_EXIT) {
        cancelUpdate(); // doesn't hurt if no update in progress
        _dependencyStack.clear(); // cleanup
        _downloadAllDependencies = false;
        _downloadStatus = OXZ_DOWNLOAD_NONE; // clear error state
        if (_changesMade) {
            _interfaceState = OXZ_STATE_RESTARTING;
        } else {
            if (PLAYER != nullptr)
                PLAYER->setGuiToIntroFirstGo(YES);
            if (_oxzList) {
                _interfaceState = OXZ_STATE_MAIN;
            } else {
                _interfaceState = OXZ_STATE_NODATA;
            }
            return;
        }
    } else if (selection == OXZ_GUI_ROW_UPDATE) // also == _CANCEL
    {
        if (_interfaceState == OXZ_STATE_REMOVING) {
            _interfaceState = OXZ_STATE_PICK_REMOVE;
            _downloadStatus = OXZ_DOWNLOAD_NONE;
        } else if (_interfaceState == OXZ_STATE_TASKDONE || _interfaceState == OXZ_STATE_DEPENDENCIES) {
            _dependencyStack.clear();
            _downloadAllDependencies = false;
            _interfaceState = OXZ_STATE_PICK_INSTALL;
            _downloadStatus = OXZ_DOWNLOAD_NONE;
        } else if (_interfaceState == OXZ_STATE_EXTRACTDONE) {
            _dependencyStack.clear();
            _downloadAllDependencies = false;
            _interfaceState = OXZ_STATE_PICK_INSTALLED;
            _downloadStatus = OXZ_DOWNLOAD_NONE;
        } else if (_interfaceState == OXZ_STATE_INSTALLING || _interfaceState == OXZ_STATE_UPDATING) {
            cancelUpdate(); // sets interface state and download status
        } else if (_interfaceState == OXZ_STATE_EXTRACT) {
            _interfaceState = OXZ_STATE_MAIN;
        } else {
            updateManifests();
        }
    } else if (selection == OXZ_GUI_ROW_INSTALL) {
        _interfaceState = OXZ_STATE_PICK_INSTALL;
    } else if (selection == OXZ_GUI_ROW_INSTALLED) {
        if (_interfaceState == OXZ_STATE_DEPENDENCIES) // also == _PROCEED_ALL
        {
            _downloadAllDependencies = true;
            installOXZ(_item);
        } else {
            _interfaceState = OXZ_STATE_PICK_INSTALLED;
        }
    } else if (selection == OXZ_GUI_ROW_REMOVE) // also == _PROCEED
    {
        if (_interfaceState == OXZ_STATE_DEPENDENCIES) {
            installOXZ(_item);
        } else if (_interfaceState == OXZ_STATE_NODATA) {
            _interfaceState = OXZ_STATE_MAIN;
        } else if (_interfaceState == OXZ_STATE_EXTRACT) {
            setProgressStatus(extractOXZ(_item));
            _interfaceState = OXZ_STATE_EXTRACTDONE;
        } else {
            _interfaceState = OXZ_STATE_PICK_REMOVE;
        }
    } else if (selection == OXZ_GUI_ROW_UPDATE_ALL) {
        OO_LOG("oxz.manager.debug", "{}", "Trying to update all managed OXPs");
        updateAllOXZ();
    } else if (selection == OXZ_GUI_ROW_LISTPREV) {
        processOptionsPrev();
        return;
    } else if (selection == OXZ_GUI_ROW_LISTNEXT) {
        processOptionsNext();
        return;
    } else {
        NSUInteger item = _offset + selection - OXZ_GUI_ROW_LISTSTART;
        if (_interfaceState == OXZ_STATE_PICK_REMOVE) {
            removeOXZ(item);
        } else if (_interfaceState == OXZ_STATE_PICK_INSTALL) {
            OO_LOG("oxz.manager.debug", "Trying to install index {}", item);
            installOXZ(item);
        } else if (_interfaceState == OXZ_STATE_PICK_INSTALLED) {
            OO_LOG("oxz.manager.debug", "Trying to install index {}", item);
            installOXZ(item);
        }
    }

    this->gui(); // update GUI
}

bool OOOXZManager::isAcceptingTextInput()
{
    return (_interfaceState == OXZ_STATE_SETFILTER);
}

bool OOOXZManager::isAcceptingGUIInput()
{
    return !_interfaceShowingOXZDetail;
}

void OOOXZManager::processTextInput(const std::string& input)
{
    if (validateFilter(input)) {
        if (!input.empty()) {
            setFilter(input);
        } // else keep previous filter
        _interfaceState = OXZ_STATE_PICK_INSTALL;
        this->gui();
    }
    // else nothing
}

void OOOXZManager::refreshTextInput(const std::string& input)
{
    ::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
    if (gui != nullptr)
        gui->setText(DescFormat(OO_DESC("oolite-oxzmanager-text-prompt-@"), { input }), OXZ_GUI_ROW_INPUT, GUI_ALIGN_LEFT);
    if (validateFilter(input)) {
        if (gui != nullptr)
            gui->setColor(OOColor::cyanColor().get(), OXZ_GUI_ROW_INPUT);
    } else {
        if (gui != nullptr)
            gui->setColor(OOColor::orangeColor().get(), OXZ_GUI_ROW_INPUT);
    }
}

void OOOXZManager::processFilterKey()
{
    if (_interfaceShowingOXZDetail) {
        _interfaceShowingOXZDetail = false;
    }
    if (_interfaceState == OXZ_STATE_PICK_INSTALL || _interfaceState == OXZ_STATE_PICK_INSTALLED || _interfaceState == OXZ_STATE_PICK_REMOVE || _interfaceState == OXZ_STATE_MAIN) {
        _interfaceState = OXZ_STATE_SETFILTER;
        if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)
            UNIVERSE->getGameView()->resetTypedString();
        this->gui();
    }
    // else this key does nothing
}

void OOOXZManager::processShowInfoKey()
{
    if (_interfaceState == OXZ_STATE_PICK_INSTALL || _interfaceState == OXZ_STATE_PICK_INSTALLED || _interfaceState == OXZ_STATE_PICK_REMOVE) {
        ::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);

        if (_interfaceShowingOXZDetail) {
            _interfaceShowingOXZDetail = false;
            this->gui(); // restore screen
            // reset list selection position
            if (gui != nullptr)
                gui->setSelectedRow((_item - _offset + OXZ_GUI_ROW_LISTSTART));
            // and do the GUI again with the correct positions
            showOptionsUpdate(); // restore screen
        } else {
            OOGUIRow selection = (gui != nullptr ? gui->getSelectedRow() : 0);

            if (selection < OXZ_GUI_ROW_LISTSTART || selection >= OXZ_GUI_ROW_LISTSTART + OXZ_GUI_NUM_LISTROWS) {
                // not on an OXZ
                return;
            }

            _item = _offset + selection - OXZ_GUI_ROW_LISTSTART;

            const oo::PList manifest = ElementAt(_filteredList, _item);
            _interfaceShowingOXZDetail = true;

            if (gui != nullptr) {
                gui->clearAndKeepBackground(YES);
                gui->setTitle(OO_DESC("oolite-oxzmanager-title-infopage"));
            }

            // title, version
            if (gui != nullptr)
                gui->setText(DescFormat(OO_DESC("oolite-oxzmanager-infopage-title-@-version-@"), { Arg(ManifestString(manifest, std::string(kOOManifestTitle))), Arg(ManifestString(manifest, std::string(kOOManifestVersion))) }), 0, GUI_ALIGN_LEFT);

            // author
            if (gui != nullptr)
                gui->setText(DescFormat(OO_DESC("oolite-oxzmanager-infopage-author-@"), { Arg(ManifestString(manifest, std::string(kOOManifestAuthor))) }), 1, GUI_ALIGN_LEFT);

            // license
            if (gui != nullptr)
                gui->addLongText(DescFormat(OO_DESC("oolite-oxzmanager-infopage-license-@"), { Arg(ManifestString(manifest, std::string(kOOManifestLicense))) }), 2, GUI_ALIGN_LEFT);
            // tags

            if (gui != nullptr)
                gui->addLongText(DescFormat(OO_DESC("oolite-oxzmanager-infopage-tags-@"), { Arg(JoinedTags(manifest)) }), 4, GUI_ALIGN_LEFT);
            // description
            if (gui != nullptr)
                gui->addLongText(DescFormat(OO_DESC("oolite-oxzmanager-infopage-description-@"), { Arg(ManifestString(manifest, std::string(kOOManifestDescription))) }), 7, GUI_ALIGN_LEFT);

            // infoURL
            const std::optional<std::string> infoURL = ManifestString(manifest, std::string(kOOManifestInformationURL));
            if (gui != nullptr)
                gui->setText(DescFormat(OO_DESC("oolite-oxzmanager-infopage-infourl-@"), { Arg(infoURL) }), 25, GUI_ALIGN_LEFT);
            setOXPURL(infoURL);
            // instructions
            if (gui != nullptr) {
                gui->setText(cxx_OOExpand(cxx_OOLookUpDescriptionPRIV("oolite-oxzmanager-infopage-return")), 27, GUI_ALIGN_CENTER);
                gui->setColor(OOColor::greenColor().get(), 27);
            }
        }
    }
}

void OOOXZManager::processCopyUrlKey()
{

    if (_interfaceState == OXZ_STATE_PICK_INSTALL || _interfaceState == OXZ_STATE_PICK_INSTALLED || _interfaceState == OXZ_STATE_PICK_REMOVE) {
        ::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);

        if (_interfaceShowingOXZDetail) {
            if (_currentOXPURL.has_value() && UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)
                UNIVERSE->getGameView()->stringToClipboard(*_currentOXPURL);
        } else {
            OOGUIRow selection = (gui != nullptr ? gui->getSelectedRow() : 0);

            if (selection < OXZ_GUI_ROW_LISTSTART || selection >= OXZ_GUI_ROW_LISTSTART + OXZ_GUI_NUM_LISTROWS) {
                // not on an OXZ
                return;
            }
            _item = _offset + selection - OXZ_GUI_ROW_LISTSTART;

            const oo::PList manifest = ElementAt(_filteredList, _item);
            // infoURL
            const std::optional<std::string> infoURL = ManifestString(manifest, std::string(kOOManifestInformationURL));
            // copy url info text to clipboard automatically once we are in the oxz info page
            if (infoURL.has_value() && UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)
                UNIVERSE->getGameView()->stringToClipboard(*infoURL);
        }
    }
}

void OOOXZManager::processExtractKey()
{
    // TODO: Extraction functionality - converts an installed OXZ to
    // an OXP in the main AddOns folder if it's safe to do so.
    if (!_interfaceShowingOXZDetail && (_interfaceState == OXZ_STATE_PICK_INSTALLED || _interfaceState == OXZ_STATE_PICK_REMOVE)) {
        ::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
        OOGUIRow selection = (gui != nullptr ? gui->getSelectedRow() : 0);

        if (selection < OXZ_GUI_ROW_LISTSTART || selection >= OXZ_GUI_ROW_LISTSTART + OXZ_GUI_NUM_LISTROWS) {
            // not on an OXZ
            return;
        }

        _item = _offset + selection - OXZ_GUI_ROW_LISTSTART;
        _interfaceState = OXZ_STATE_EXTRACT;
        this->gui();
    }
}

std::vector<oo::PList> OOOXZManager::installOptions()
{
    NSUInteger start = _offset;
    if (start >= _filteredList.count()) {
        start = 0;
        _offset = 0;
    }
    NSUInteger end = start + OXZ_GUI_NUM_LISTROWS;
    if (end > _filteredList.count()) {
        end = _filteredList.count();
    }
    const oo::PList::Array& all = Elements(_filteredList);
    return std::vector<oo::PList>(all.begin() + start, all.begin() + end);
}

OOGUIRow OOOXZManager::showInstallOptions()
{
    // shows the current installation options page
    OOGUIRow startRow = OXZ_GUI_ROW_LISTPREV;
    const std::vector<oo::PList> options = installOptions();
    NSUInteger optCount = _filteredList.count();
    ::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
    OOGUITabSettings tab_stops;
    tab_stops[0] = 0;
    tab_stops[1] = 100;
    tab_stops[2] = 320;
    tab_stops[3] = 400;
    if (gui != nullptr) {
        gui->setTabStops(tab_stops);

        gui->setArray(Columns({ OO_DESC("oolite-oxzmanager-heading-category"), OO_DESC("oolite-oxzmanager-heading-title"), OO_DESC("oolite-oxzmanager-heading-installed"), OO_DESC("oolite-oxzmanager-heading-downloadable") }), OXZ_GUI_ROW_LISTHEAD);
    }

    if (_offset > 0) {
        if (gui != nullptr) {
            gui->setColor(OOColor::greenColor().get(), OXZ_GUI_ROW_LISTPREV);
            gui->setArray(Columns({ OO_DESC("gui-back"), "", "", " <-- " }), OXZ_GUI_ROW_LISTPREV);
            gui->setKey("_BACK", OXZ_GUI_ROW_LISTPREV);
        }
    } else {
        if ((gui != nullptr ? gui->getSelectedRow() : 0) == OXZ_GUI_ROW_LISTPREV) {
            if (gui != nullptr)
                gui->setSelectedRow(OXZ_GUI_ROW_LISTSTART);
        }
        if (gui != nullptr) {
            gui->setText("", OXZ_GUI_ROW_LISTPREV, GUI_ALIGN_LEFT);
            gui->setKey(std::string(GUI_KEY_SKIP), OXZ_GUI_ROW_LISTPREV);
        }
    }
    if (_offset + 10 < optCount) {
        if (gui != nullptr) {
            gui->setColor(OOColor::greenColor().get(), OXZ_GUI_ROW_LISTNEXT);
            gui->setArray(Columns({ OO_DESC("gui-more"), "", "", " --> " }), OXZ_GUI_ROW_LISTNEXT);
            gui->setKey("_NEXT", OXZ_GUI_ROW_LISTNEXT);
        }
    } else {
        if ((gui != nullptr ? gui->getSelectedRow() : 0) == OXZ_GUI_ROW_LISTNEXT) {
            if (gui != nullptr)
                gui->setSelectedRow(OXZ_GUI_ROW_LISTSTART);
        }
        if (gui != nullptr) {
            gui->setText("", OXZ_GUI_ROW_LISTNEXT, GUI_ALIGN_LEFT);
            gui->setKey(std::string(GUI_KEY_SKIP), OXZ_GUI_ROW_LISTNEXT);
        }
    }

    // clear any previous longtext
    for (NSUInteger i = OXZ_GUI_ROW_LISTSTATUS; i < OXZ_GUI_ROW_INSTALL - 1; i++) {
        if (gui != nullptr) {
            gui->setText("", i, GUI_ALIGN_LEFT);
            gui->setKey(std::string(GUI_KEY_SKIP), i);
        }
    }
    // and any previous listed entries
    for (NSUInteger i = OXZ_GUI_ROW_LISTSTART; i < OXZ_GUI_ROW_LISTNEXT; i++) {
        if (gui != nullptr) {
            gui->setText("", i, GUI_ALIGN_LEFT);
            gui->setKey(std::string(GUI_KEY_SKIP), i);
        }
    }

    OOGUIRow row = OXZ_GUI_ROW_LISTSTART;
    bool oxzLineSelected = false;
    const std::optional<std::string> installPath = this->installPath();

    for (const oo::PList& manifest : options) {
        const std::optional<std::string> identifier = ManifestString(manifest, std::string(kOOManifestIdentifier));
        oo::PList installed = ResourceManager::manifestForIdentifier(identifier.value_or(std::string()));
        const std::string localPath = oo::str::appendingPathComponent(installPath.value_or(std::string()), identifier.value_or(std::string())) + ".oxz";
        const auto readLocalManifest = [&localPath] { return PListDictionaryFromFile(oo::str::appendingPathComponent(localPath, "manifest.plist")); };
        if (!installed) {
            // check that there's not one just been downloaded
            installed = readLocalManifest();
        } else {
            // check for a more recent download
            if (oo::fs::fileExists(oo::fs::pathFromUTF8(localPath))) {

                installed = readLocalManifest();
            } else {
                // check if this was a managed OXZ which has been deleted
                const std::optional<std::string> filePath = ManifestString(installed, std::string(kOOManifestFilePath));
                if (filePath.has_value() && installPath.has_value() && oo::str::hasPrefix(*filePath, *installPath)) {
                    installed = oo::PList();
                }
            }
        }

        std::optional<std::string> installedVersion = OO_DESC("oolite-oxzmanager-version-none");
        if (installed) {
            installedVersion = ManifestStringOr(installed, std::string(kOOManifestVersion), OO_DESC("oolite-oxzmanager-version-none"));
        }

        /* If the filter is in use, the available_version key will
         * contain the version which can be downloaded. */
        if (gui != nullptr) {
            gui->setArray(Columns({ ManifestStringOr(manifest, std::string(kOOManifestCategory), OO_DESC("oolite-oxzmanager-missing-field")), ManifestStringOr(manifest, std::string(kOOManifestTitle), OO_DESC("oolite-oxzmanager-missing-field")), installedVersion, ManifestStringOr(manifest, std::string(kOOManifestAvailableVersion), ManifestStringOr(manifest, std::string(kOOManifestVersion), OO_DESC("oolite-oxzmanager-version-none"))) }), row);

            gui->setKey(identifier.value_or(std::string()), row);
        }
        /* yellow for installable, orange for dependency issues, grey and unselectable for version issues, white and unselectable for already installed (manually or otherwise) at the current version, red and unselectable for already installed manually at a different version. */
        if (gui != nullptr)
            gui->setColor(colorForManifest(manifest).get(), row);

        if (row == (gui != nullptr ? gui->getSelectedRow() : 0)) {
            oxzLineSelected = true;

            if (gui != nullptr) {
                gui->setText(installStatusForManifest(manifest).value_or(std::string()), OXZ_GUI_ROW_LISTSTATUS);
                gui->setColor(OOColor::greenColor().get(), OXZ_GUI_ROW_LISTSTATUS);

                gui->addLongText(FirstDescriptionLine(manifest), OXZ_GUI_ROW_LISTDESC, GUI_ALIGN_LEFT);
            }

            const std::optional<std::string> infoUrl = ManifestString(manifest, std::string(kOOManifestInformationURL));
            if (infoUrl.has_value()) {
                if (gui != nullptr)
                    gui->setArray(Columns({ OO_DESC("oolite-oxzmanager-infoline-url"), infoUrl }), OXZ_GUI_ROW_LISTINFO1);
            }
            NSUInteger size = manifest.get<unsigned int>(std::string(kOOManifestFileSize), 0);

            NSUInteger timestamp = manifest.get<unsigned long long>(std::string(kOOManifestUploadDate), 0);
            if (timestamp > 0) {
                // list of installable OXZs
                // keep only the first part of the date string description, which should be in YYYY-MM-DD format
                const std::string updatedDesc = oo::str::split(oo::date::description(oo::date::dateWithTimeIntervalSince1970(timestamp)), " ").front();

                if (gui != nullptr)
                    gui->setArray(Columns({ OO_DESC("oolite-oxzmanager-infoline-size"), humanSize(size), OO_DESC("oolite-oxzmanager-infoline-date"), updatedDesc }), OXZ_GUI_ROW_LISTINFO2);
            } else if (size > 0) {
                // list of installed/removable OXZs
                if (gui != nullptr)
                    gui->setArray(Columns({ OO_DESC("oolite-oxzmanager-infoline-size"), humanSize(size) }), OXZ_GUI_ROW_LISTINFO2);
            }
        }

        row++;
    }

    if (!oxzLineSelected) {
        if (_interfaceState == OXZ_STATE_PICK_INSTALLED) {
            // installeD
            if (gui != nullptr)
                gui->addLongText(cxx_OOExpand(cxx_OOLookUpDescriptionPRIV("oolite-oxzmanager-installed-nonepicked")), OXZ_GUI_ROW_LISTDESC, GUI_ALIGN_LEFT);
        } else {
            // installeR
            if (gui != nullptr)
                gui->addLongText(cxx_OOExpand(cxx_OOLookUpDescriptionPRIV("oolite-oxzmanager-installer-nonepicked")), OXZ_GUI_ROW_LISTDESC, GUI_ALIGN_LEFT);
        }
    }

    return startRow;
}

std::vector<oo::PList> OOOXZManager::removeOptions()
{
    if (_filteredList.count() == 0) {
        return { };
    }
    NSUInteger start = _offset;
    if (start >= _filteredList.count()) {
        start = 0;
        _offset = 0;
    }
    NSUInteger end = start + OXZ_GUI_NUM_LISTROWS;
    if (end > _filteredList.count()) {
        end = _filteredList.count();
    }
    const oo::PList::Array& all = Elements(_filteredList);
    return std::vector<oo::PList>(all.begin() + start, all.begin() + end);
}

OOGUIRow OOOXZManager::showRemoveOptions()
{
    // shows the current installation options page
    OOGUIRow startRow = OXZ_GUI_ROW_LISTPREV;
    const std::vector<oo::PList> options = removeOptions();
    ::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
    if (options.empty()) {
        if (gui != nullptr)
            gui->addLongText(OO_DESC("oolite-oxzmanager-nothing-removable"), OXZ_GUI_ROW_PROGRESS, GUI_ALIGN_LEFT);
        return startRow;
    }

    OOGUITabSettings tab_stops;
    tab_stops[0] = 0;
    tab_stops[1] = 100;
    tab_stops[2] = 400;
    if (gui != nullptr) {
        gui->setTabStops(tab_stops);

        gui->setArray(Columns({ OO_DESC("oolite-oxzmanager-heading-category"), OO_DESC("oolite-oxzmanager-heading-title"), OO_DESC("oolite-oxzmanager-heading-version") }), OXZ_GUI_ROW_LISTHEAD);
    }
    if (_offset > 0) {
        if (gui != nullptr) {
            gui->setColor(OOColor::greenColor().get(), OXZ_GUI_ROW_LISTPREV);
            gui->setArray(Columns({ OO_DESC("gui-back"), "", " <-- " }), OXZ_GUI_ROW_LISTPREV);
            gui->setKey("_BACK", OXZ_GUI_ROW_LISTPREV);
        }
    } else {
        if ((gui != nullptr ? gui->getSelectedRow() : 0) == OXZ_GUI_ROW_LISTPREV) {
            if (gui != nullptr)
                gui->setSelectedRow(OXZ_GUI_ROW_LISTSTART);
        }
        if (gui != nullptr) {
            gui->setText("", OXZ_GUI_ROW_LISTPREV, GUI_ALIGN_LEFT);
            gui->setKey(std::string(GUI_KEY_SKIP), OXZ_GUI_ROW_LISTPREV);
        }
    }
    if (_offset + OXZ_GUI_NUM_LISTROWS < managedOXZs().count()) {
        if (gui != nullptr) {
            gui->setColor(OOColor::greenColor().get(), OXZ_GUI_ROW_LISTNEXT);
            gui->setArray(Columns({ OO_DESC("gui-more"), "", " --> " }), OXZ_GUI_ROW_LISTNEXT);
            gui->setKey("_NEXT", OXZ_GUI_ROW_LISTNEXT);
        }
    } else {
        if ((gui != nullptr ? gui->getSelectedRow() : 0) == OXZ_GUI_ROW_LISTNEXT) {
            if (gui != nullptr)
                gui->setSelectedRow(OXZ_GUI_ROW_LISTSTART);
        }
        if (gui != nullptr) {
            gui->setText("", OXZ_GUI_ROW_LISTNEXT, GUI_ALIGN_LEFT);
            gui->setKey(std::string(GUI_KEY_SKIP), OXZ_GUI_ROW_LISTNEXT);
        }
    }

    // clear any previous longtext
    for (NSUInteger i = OXZ_GUI_ROW_LISTDESC; i < OXZ_GUI_ROW_INSTALL - 1; i++) {
        if (gui != nullptr) {
            gui->setText("", i, GUI_ALIGN_LEFT);
            gui->setKey(std::string(GUI_KEY_SKIP), i);
        }
    }
    // and any previous listed entries
    for (NSUInteger i = OXZ_GUI_ROW_LISTSTART; i < OXZ_GUI_ROW_LISTNEXT; i++) {
        if (gui != nullptr) {
            gui->setText("", i, GUI_ALIGN_LEFT);
            gui->setKey(std::string(GUI_KEY_SKIP), i);
        }
    }

    OOGUIRow row = OXZ_GUI_ROW_LISTSTART;
    bool oxzSelected = false;

    for (const oo::PList& manifest : options) {

        if (gui != nullptr)
            gui->setArray(Columns({ ManifestStringOr(manifest, std::string(kOOManifestCategory), OO_DESC("oolite-oxzmanager-missing-field")), ManifestStringOr(manifest, std::string(kOOManifestTitle), OO_DESC("oolite-oxzmanager-missing-field")), ManifestStringOr(manifest, std::string(kOOManifestVersion), OO_DESC("oolite-oxzmanager-missing-field")) }), row);
        const std::optional<std::string> identifier = ManifestString(manifest, std::string(kOOManifestIdentifier));
        if (gui != nullptr) {
            gui->setKey(identifier.value_or(std::string()), row);

            gui->setColor(colorForManifest(manifest).get(), row);
        }

        if (row == (gui != nullptr ? gui->getSelectedRow() : 0)) {
            if (gui != nullptr) {
                gui->setText(installStatusForManifest(manifest).value_or(std::string()), OXZ_GUI_ROW_LISTSTATUS);
                gui->setColor(OOColor::greenColor().get(), OXZ_GUI_ROW_LISTSTATUS);

                gui->addLongText(FirstDescriptionLine(manifest), OXZ_GUI_ROW_LISTDESC, GUI_ALIGN_LEFT);
            }

            oxzSelected = true;
        }
        row++;
    }

    if (!oxzSelected) {
        if (gui != nullptr)
            gui->addLongText(OO_DESC("oolite-oxzmanager-remover-nonepicked"), OXZ_GUI_ROW_LISTDESC, GUI_ALIGN_LEFT);
    }

    return startRow;
}

void OOOXZManager::showOptionsUpdate()
{

    if (_interfaceState == OXZ_STATE_PICK_INSTALL) {
        setFilteredList(applyCurrentFilter(_oxzList));
        showInstallOptions();
    } else if (_interfaceState == OXZ_STATE_PICK_INSTALLED) {
        setFilteredList(applyCurrentFilter(managedOXZs()));
        showInstallOptions();
    } else if (_interfaceState == OXZ_STATE_PICK_REMOVE) {
        setFilteredList(applyCurrentFilter(managedOXZs()));
        showRemoveOptions();
    }
    // else nothing necessary
}

void OOOXZManager::showOptionsPrev()
{
    ::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
    if (_interfaceState == OXZ_STATE_PICK_INSTALL || _interfaceState == OXZ_STATE_PICK_REMOVE || _interfaceState == OXZ_STATE_PICK_INSTALLED) {
        if ((gui != nullptr ? gui->getSelectedRow() : 0) == OXZ_GUI_ROW_LISTPREV) {
            processSelection();
        }
    }
}

void OOOXZManager::processOptionsPrev()
{
    if (_offset < OXZ_GUI_NUM_LISTROWS) {
        _offset = 0;
    } else {
        _offset -= OXZ_GUI_NUM_LISTROWS;
    }
    showOptionsUpdate();
}

void OOOXZManager::processOptionsNext()
{
    if (_offset + OXZ_GUI_NUM_LISTROWS < _filteredList.count()) {
        _offset += OXZ_GUI_NUM_LISTROWS;
    }
    showOptionsUpdate();
    return;
}

void OOOXZManager::showOptionsNext()
{
    ::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
    if (_interfaceState == OXZ_STATE_PICK_INSTALL || _interfaceState == OXZ_STATE_PICK_REMOVE || _interfaceState == OXZ_STATE_PICK_INSTALLED) {
        if ((gui != nullptr ? gui->getSelectedRow() : 0) == OXZ_GUI_ROW_LISTNEXT) {
            processSelection();
        }
    }
}

std::string OOOXZManager::extractOXZ(NSUInteger item)
{
    std::string extractionLog;
    const oo::PList manifest = ElementAt(_filteredList, item);
    const std::optional<std::string> version = ManifestString(manifest, std::string(kOOManifestVersion));
    const std::optional<std::string> identifier = ManifestString(manifest, std::string(kOOManifestIdentifier));
    const std::optional<std::string> path = extractionBasePathForIdentifier(identifier.value_or(""), version.value_or(""));

    const std::optional<std::string> oxzfile = ManifestString(manifest, std::string(kOOManifestFilePath));
    if (!oxzfile.has_value() || !oo::fs::fileExists(oo::fs::pathFromUTF8(*oxzfile))) {
        OO_LOG("oxz.manager.error", "OXZ {} could not be found", oxzfile.value_or("(null)"));
        extractionLog += OO_DESC("oolite-oxzmanager-extract-log-no-original");
        return extractionLog;
    }
    const char* zipname = oxzfile->c_str();
    unzFile uf = NULL;
    uf = unzOpen64(zipname);
    if (uf == NULL) {
        OO_LOG("oxz.manager.error", "Could not open .oxz at {} as zip file", path.value_or("(null)"));
        extractionLog += OO_DESC("oolite-oxzmanager-extract-log-bad-original");
        return extractionLog;
    }

    if (!path.has_value()) {
        unzClose(uf);
        extractionLog += OO_DESC("oolite-oxzmanager-extract-log-main-unmakeable");
        return extractionLog;
    }
    if (oo::fs::fileExists(oo::fs::pathFromUTF8(*path))) {
        OO_LOG("oxz.manager.error", "Path {} already exists", *path);
        extractionLog += OO_DESC("oolite-oxzmanager-extract-log-main-exists");
        unzClose(uf);
        return extractionLog;
    }
    if (!oo::fs::createDirectories(oo::fs::pathFromUTF8(*path))) {
        OO_LOG("oxz.manager.error", "Path {} could not be created", *path);
        extractionLog += OO_DESC("oolite-oxzmanager-extract-log-main-unmakeable");
        unzClose(uf);
        return extractionLog;
    }
    extractionLog += OO_DESC("oolite-oxzmanager-extract-log-main-created");
    NSUInteger counter = 0;
    char rawComponentName[512];
    bool error = false;
    unz_file_info64 file_info = { };
    if (unzGoToFirstFile(uf) == UNZ_OK) {
        do {
            unzGetCurrentFileInfo64(uf, &file_info,
                rawComponentName, 512,
                NULL, 0,
                NULL, 0);
            const std::string componentName = rawComponentName;
            if (oo::str::hasSuffix(componentName, "/")) {
                const std::string folderPath = oo::str::appendingPathComponent(*path, componentName);
                if (!oo::fs::createDirectories(oo::fs::pathFromUTF8(folderPath))) {
                    OO_LOG("oxz.manager.error", "Subpath {} could not be created", componentName);
                    extractionLog += OO_DESC("oolite-oxzmanager-extract-log-sub-failed");
                    error = true;
                    break;
                } else {
                    OO_LOG("oxz.manager.debug", "Subpath {} created OK", componentName);
                }
            } else {
                const std::string fullComponent = oo::str::appendingPathComponent(*path, componentName);
                const std::string folder = oo::str::deletingLastPathComponent(fullComponent);
                if (!folder.empty() && !oo::fs::fileExists(oo::fs::pathFromUTF8(folder))
                    && !oo::fs::createDirectories(oo::fs::pathFromUTF8(folder))) {
                    OO_LOG("oxz.manager.error", "Subpath {} could not be created", folder);
                    extractionLog += OO_DESC("oolite-oxzmanager-extract-log-sub-failed");
                    error = true;
                    break;
                }

                const std::string entryPath = oo::str::appendingPathComponent(*oxzfile, componentName);
                std::optional<oo::Data> tmp = OODataFromOXZFile(entryPath);
                if (!tmp.has_value()) {
                    OO_LOG("oxz.manager.error", "Sub file {} could not be extracted from the OXZ", componentName);
                    extractionLog += OO_DESC("oolite-oxzmanager-extract-log-sub-failed");
                    error = true;
                    break;
                } else {
                    if (!oo::fs::writeFile(oo::fs::pathFromUTF8(fullComponent), *tmp, oo::fs::WriteMode::atomic)) {
                        OO_LOG("oxz.manager.error", "Sub file {} could not be created", componentName);
                        extractionLog += OO_DESC("oolite-oxzmanager-extract-log-sub-failed");
                        error = true;
                        break;
                    } else {
                        ++counter;
                    }
                }
            }
        } while (unzGoToNextFile(uf) == UNZ_OK);
    }
    unzClose(uf);

    if (!error) {
        extractionLog += DescFormat(OO_DESC("oolite-oxzmanager-extract-log-num-u-extracted"), { static_cast<unsigned long long>(counter) });
        extractionLog += DescFormat(OO_DESC("oolite-oxzmanager-extract-log-extracted-to-@"), { *path });
    }

    return extractionLog;
}

void OOOXZManager::downloadDidReceiveResponse(long long expectedContentLength)
{
    _downloadStatus = OXZ_DOWNLOAD_RECEIVING;
    OO_LOG("oxz.manager.debug", "{}", "Download receiving");
    _downloadExpected = expectedContentLength;
    _downloadProgress = 0;
    if (_fileWriter != NULL) {
        fclose(_fileWriter);
        _fileWriter = NULL;
    }
    const std::optional<std::string> path = downloadPath();
    _fileWriter = path.has_value() ? oo::fs::createFileForWriting(oo::fs::pathFromUTF8(*path)) : NULL;
    if (_fileWriter == NULL) {
        // file system is full or read-only or something
        OO_LOG("oxz.manager.error", "{}", "Unable to create download file");
        cancelUpdate();
    }
}

void OOOXZManager::downloadDidReceiveData(const std::string& data)
{
    OO_LOG("oxz.manager.debug", "Downloaded {} bytes", data.size());
    if (_fileWriter != NULL) {
        fwrite(data.data(), 1, data.size(), _fileWriter);
    }
    _downloadProgress += data.size();
    gui(); // update GUI
#if OOLITE_WINDOWS
    /* Irritating fix to issue https://github.com/OoliteProject/oolite/issues/95
     *
     * The problem is that on MINGW, GNUStep makes all socket streams
     * blocking, which causes problems with the run loop. Calling this
     * method of the run loop forces it to execute all already
     * scheduled items with a time in the past, before any more items
     * are placed on it, which means that the main game update gets a
     * chance to run.
     *
     * This stops the interface freezing - and Oolite appearing to
     * have stopped responding to the OS - when downloading large
     * (>20Mb) OXZ files.
     *
     * CIM 6 July 2014
     *
     * The game tick is no longer a run-loop timer, so GameController fires
     * it (and the run loop's own due timers) here, as the run loop did.
     * Proposed ADR-0033. The download itself no longer blocks the frame
     * loop (it runs on its own thread, proposed ADR-0044); the call stays
     * so a burst of queued chunks still lets the game tick between them.
     */
    ::GameController::sharedController()->fireDueTimers();
#endif
}

void OOOXZManager::downloadDidFinishLoading()
{
    _downloadStatus = OXZ_DOWNLOAD_COMPLETE;
    OO_LOG("oxz.manager.debug", "{}", "Download complete");
    if (_fileWriter != NULL) {
        oo::fs::synchronizeFile(_fileWriter);
        fclose(_fileWriter);
        _fileWriter = NULL;
    }
    delete _currentDownload;
    _currentDownload = nullptr;
    if (_interfaceState == OXZ_STATE_UPDATING) {
        if (!processDownloadedManifests()) {
            _downloadStatus = OXZ_DOWNLOAD_ERROR;
        }
    } else if (_interfaceState == OXZ_STATE_INSTALLING) {
        if (!processDownloadedOXZ()) {
            _downloadStatus = OXZ_DOWNLOAD_ERROR;
        }
    } else {
        OO_LOG("oxz.manager.error", "Error: download completed in unexpected state {}. This is an internal error - please report it.", static_cast<int>(_interfaceState));
        _downloadStatus = OXZ_DOWNLOAD_ERROR;
    }
}

void OOOXZManager::downloadDidFailWithError(const std::string& error)
{
    _downloadStatus = OXZ_DOWNLOAD_ERROR;
    OO_LOG("oxz.manager.error", "Error downloading file: {}", error);
    if (_fileWriter != NULL) {
        fclose(_fileWriter);
        _fileWriter = NULL;
    }
    delete _currentDownload;
    _currentDownload = nullptr;
}
