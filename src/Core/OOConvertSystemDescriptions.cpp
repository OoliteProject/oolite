/*

OOConvertSystemDescriptions.m
Oolite


Copyright (C) 2008 Jens Ayton

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

#include "Universe.h"

#if OO_LOCALIZATION_TOOLS

#include "OOConvertSystemDescriptions.h"
#include "ResourceManager.h"
#include "Universe.h"
#include "oofnd/PListWriting.hpp"
#include "oofnd/String.hpp"

/*	Foundation sweep (proposed ADR-0043, bead oo-xh1g): the descriptions are oo::PLists, the lines
        std::strings scanned in UTF-16 units as -rangeOfString: scanned them. The indices are integers
        (an index from the key table's -intValue may be negative, as the Foundation number was). Dictionaries are
        visited in key order (byte order; they were in hash order), which decides the slot an unknown
        key is given and the order of the "Assigning key" log lines. Where the Foundation code raised on
        a malformed line (a "[" with no "]" after it), the line is left as it stands.
*/
namespace {

using KeysToIndices = std::map<std::string, long long>;
using UsedIndices = std::set<long long>;

void InitKeyToIndexDict(const oo::PList& dict, KeysToIndices& outKeysToIndices, UsedIndices& outUsedIndices)
{
    if (const oo::PList::Dict* entries = dict.getIf<oo::PList::Dict>()) {
        for (const auto& [key, value] : *entries) {
            // Convert keys of dict to array indices
            const long long number = oo::str::intValue(key);
            if (const std::string* name = value.getIf<std::string>())
                outKeysToIndices[*name] = number;
            outUsedIndices.insert(number);
        }
    }
}

std::optional<std::string> IndexToKey(NSUInteger index, const oo::PList& indicesToKeys, BOOL useFallback)
{
    const oo::PList* value = indicesToKeys.find(oo::str::format("%zu", index));
    if (value != nullptr && value->getIf<std::string>() != nullptr)
        return *value->getIf<std::string>();
    if (useFallback)
        return oo::str::format("block_%zu", index);

    return std::nullopt;
}

long long KeyToIndex(const std::string& key, KeysToIndices& ioKeysToIndices, UsedIndices& ioUsedIndicies, NSUInteger* ioSlotCache)
{
    assert(ioSlotCache != NULL);

    const auto found = ioKeysToIndices.find(key);
    if (found != ioKeysToIndices.end())
        return found->second;

    // Search for free index
    long long result;
    do {
        result = static_cast<long long>((*ioSlotCache)++);
    } while (ioUsedIndicies.contains(result));

    ioKeysToIndices[key] = result;
    ioUsedIndicies.insert(result);
    OO_LOG("sysdesc.compile.unknownKey", "Assigning key \"{}\" to index {}.", key, result);

    return result;
}

// One "[...]" at a time within searchRange, as -rangeOfString:options:NSLiteralSearch range: found
// them; false where the Foundation code raised (no "]" after the "[").
bool NextBrackets(const std::u16string& line, std::size_t location, std::size_t length, std::size_t& p1, std::size_t& p2)
{
    const std::size_t end = location + length;
    p1 = line.find(u'[', location);
    if (p1 == std::u16string::npos || p1 >= end)
        return false;
    const std::size_t close = line.find(u']', location);
    if (close == std::u16string::npos || close >= end || close < p1)
        return false;
    p2 = close + 1;
    return true;
}

oo::PList ConvertKeysToIndices(const oo::PList& entry, KeysToIndices& ioKeysToIndices, UsedIndices& ioUsedIndicies, NSUInteger* ioSlotCache)
{
    oo::PList::Array result;

    for (std::size_t i = 0; i < entry.count(); i++) {
        std::u16string line = oo::utf8ToUtf16(entry.at<std::string>(i));
        std::size_t location = 0, length = line.size(), p1, p2;

        while (NextBrackets(line, location, length, p1, p2)) {
            const std::u16string before = line.substr(0, p1);
            const std::u16string after = line.substr(p2);
            const std::u16string middle = line.substr(p1 + 1, p2 - p1 - 2);

            if (middle.size() > 1 && middle[0] == u'#') {
                // Found [] around key
                const long long index = KeyToIndex(oo::utf16ToUtf8(middle.substr(1)), ioKeysToIndices, ioUsedIndicies, ioSlotCache);
                std::u16string replaced = before;
                replaced += oo::utf8ToUtf16(oo::str::format("[%lld]", index));
                replaced += after;
                line = std::move(replaced);
            }

            length -= p2 - location;
            location = line.size() - length;
        }

        result.push_back(oo::PList(oo::utf16ToUtf8(line)));
    }

    return oo::PList(std::move(result));
}

oo::PList ConvertIndicesToKeys(const oo::PList& entry, const oo::PList& indicesToKeys)
{
    oo::PList::Array result;

    for (std::size_t i = 0; i < entry.count(); i++) {
        result.push_back(oo::PList(OOStringifySystemDescriptionLine(entry.at<std::string>(i), indicesToKeys, YES)));
    }

    return oo::PList(std::move(result));
}

// The highest index, as the Foundation code worked it out (each through -intValue into an
// NSUInteger). Its callers use it as the count, so the highest entry is not copied.
NSUInteger HighestIndex(const std::map<long long, oo::PList>& sparseArray)
{
    NSUInteger curr, highest = 0;

    for (const auto& [key, value] : sparseArray) {
        curr = static_cast<NSUInteger>(static_cast<int>(key));
        if (highest < curr)
            highest = curr;
    }

    return highest;
}

// The plist as the file text: XML, or the old-school format.
oo::Expected<oo::Data, oo::PListError> WriteSystemDescriptions(const oo::PList& plist, BOOL asXML)
{
    return asXML ? oo::writeXMLPList(plist) : oo::writeOldStylePList(plist);
}

} // namespace

void CompileSystemDescriptions(BOOL asXML)
{
    const oo::PList sysDescDict = ResourceManager::dictionaryFromFilesNamed("sysdesc.plist", std::string("Config"), false);
    if (sysDescDict.isNull()) {
        OO_LOG("sysdesc.compile.failed.fileNotFound", "{}", "Could not load a dictionary from sysdesc.plist, ignoring --compile-sysdesc option.");
        return;
    }

    const oo::PList keyMap = ResourceManager::dictionaryFromFilesNamed("sysdesc_key_table.plist", std::string("Config"), false);
    // keyMap is optional, so no nil check

    oo::PList sysDescArray = OOConvertSystemDescriptionsToArrayFormat(sysDescDict, keyMap);

    oo::PList::Dict wrapper;
    wrapper.emplace("system_description", std::move(sysDescArray));
    const oo::Expected<oo::Data, oo::PListError> data = WriteSystemDescriptions(oo::PList(std::move(wrapper)), asXML);

    if (!data.has_value()) {
        OO_LOG("sysdesc.compile.failed.XML", "Could not convert translated sysdesc.plist to property list: {}.", data.error().message);
        return;
    }

    if (ResourceManager::writeDiagnosticData(*data, "sysdesc-compiled.plist")) {
        OO_LOG("sysdesc.compile.success", "{}", "Wrote translated sysdesc.plist to sysdesc-compiled.plist.");
    } else {
        OO_LOG("sysdesc.compile.failed.writeFailure", "{}", "Could not write translated sysdesc.plist to sysdesc-compiled.plist.");
    }
}

void ExportSystemDescriptions(BOOL asXML)
{
    const oo::PList descriptions = *UNIVERSE->descriptions();
    const oo::PList* sysDescArray = descriptions.get<oo::PList::Array>("system_description");

    const oo::PList keyMap = ResourceManager::dictionaryFromFilesNamed("sysdesc_key_table.plist", std::string("Config"), false);
    // keyMap is optional, so no nil check

    const oo::PList sysDescDict = OOConvertSystemDescriptionsToDictionaryFormat((sysDescArray != nullptr) ? *sysDescArray : oo::PList(), keyMap);
    if (sysDescArray == nullptr) {
        OO_LOG("sysdesc.export.failed.conversion", "{}", "Could not convert system_description do sysdesc.plist format for some reason.");
        return;
    }

    const oo::Expected<oo::Data, oo::PListError> data = WriteSystemDescriptions(sysDescDict, asXML);

    if (!data.has_value()) {
        OO_LOG("sysdesc.export.failed.XML", "Could not convert translated system_description to XML property list: {}.", data.error().message);
        return;
    }

    if (ResourceManager::writeDiagnosticData(*data, "sysdesc.plist")) {
        OO_LOG("sysdesc.export.success", "{}", "Wrote translated system_description to sysdesc.plist.");
    } else {
        OO_LOG("sysdesc.export.failed.writeFailure", "{}", "Could not write translated system_description to sysdesc.plist.");
    }
}

oo::PList OOConvertSystemDescriptionsToArrayFormat(const oo::PList& descriptionsInDictionaryFormat, const oo::PList& indicesToKeys)
{
    std::map<long long, oo::PList> result; // a sparse array
    KeysToIndices keysToIndices;
    UsedIndices usedIndices;
    NSUInteger slotCache = 0;
    NSUInteger i, count;
    oo::PList::Array realResult;

    InitKeyToIndexDict(indicesToKeys, keysToIndices, usedIndices);

    if (const oo::PList::Dict* descriptions = descriptionsInDictionaryFormat.getIf<oo::PList::Dict>()) {
        for (const auto& [key, value] : *descriptions) {
            oo::PList entry = ConvertKeysToIndices(value, keysToIndices, usedIndices, &slotCache);
            const long long index = KeyToIndex(key, keysToIndices, usedIndices, &slotCache);

            result[index] = std::move(entry);
        }
    }

    count = HighestIndex(result);
    realResult.reserve(count);
    for (i = 0; i < count; i++) {
        const auto found = result.find(static_cast<long long>(i));
        realResult.push_back((found != result.end()) ? found->second : oo::PList(oo::PList::Array()));
    }

    return oo::PList(std::move(realResult));
}

oo::PList OOConvertSystemDescriptionsToDictionaryFormat(const oo::PList& descriptionsInArrayFormat, const oo::PList& indicesToKeys)
{
    oo::PList::Dict result;

    for (std::size_t i = 0; i < descriptionsInArrayFormat.count(); i++) {
        oo::PList entry = ConvertIndicesToKeys(*descriptionsInArrayFormat.at(i), indicesToKeys);
        result[*IndexToKey(i, indicesToKeys, YES)] = std::move(entry);
    }

    return oo::PList(std::move(result));
}

std::string OOStringifySystemDescriptionLine(const std::string& lineText, const oo::PList& indicesToKeys, BOOL useFallback)
{
    std::u16string line = oo::utf8ToUtf16(lineText);
    std::size_t location = 0, length = line.size(), p1, p2;

    while (NextBrackets(line, location, length, p1, p2)) {
        const std::u16string before = line.substr(0, p1);
        const std::u16string after = line.substr(p2);
        const std::u16string middle = line.substr(p1 + 1, p2 - p1 - 2);

        if (!middle.empty() && middle.find_first_not_of(u"0123456789") == std::u16string::npos) {
            // Found [] around integers only
            const std::optional<std::string> key = IndexToKey(static_cast<NSUInteger>(oo::str::intValue(oo::utf16ToUtf8(middle))), indicesToKeys, useFallback);
            if (key.has_value()) {
                std::u16string replaced = before;
                replaced += u"[#";
                replaced += oo::utf8ToUtf16(*key);
                replaced += u"]";
                replaced += after;
                line = std::move(replaced);
            }
        }

        length -= p2 - location;
        location = line.size() - length;
    }
    return oo::utf16ToUtf8(line);
}

#endif
