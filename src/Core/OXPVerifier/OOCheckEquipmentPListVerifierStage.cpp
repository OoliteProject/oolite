/*

OOCheckEquipmentPListVerifierStage.m


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

#include "OOCheckEquipmentPListVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#include "OOFileScannerVerifierStage.h"
#include "Universe.h"

#include "oofnd/PListGet.hpp"
#include "oofnd/String.hpp"

static const char* const kStageName = "Checking equipment.plist";

namespace {

// oo_stringAtIndex: a string, or a number's string value; nullopt where it answered nil.
std::optional<std::string> StringAt(const oo::PList& array, std::size_t index)
{
    const oo::PList* value = array.at<oo::PList>(index);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return array.at<std::string>(index);
}

} // namespace

std::optional<std::string> OOCheckEquipmentPListVerifierStage::name()
{
    return kStageName;
}

bool OOCheckEquipmentPListVerifierStage::shouldRun()
{
    OOFileScannerVerifierStage* fileScanner = nullptr;

    fileScanner = static_cast<OOFileScannerVerifierStage*>(verifier()->stageWithName(OOFileScannerVerifierStage::kName));
    return fileScanner != nullptr && fileScanner->fileExists("equipment.plist", "Config", std::nullopt, false);
}

void OOCheckEquipmentPListVerifierStage::run()
{
    OOFileScannerVerifierStage* fileScanner = nullptr;
    oo::PList equipmentPList;

    fileScanner = static_cast<OOFileScannerVerifierStage*>(verifier()->stageWithName(OOFileScannerVerifierStage::kName));

    if (fileScanner != nullptr)
        equipmentPList = fileScanner->plistNamed("equipment.plist", "Config", std::nullopt, false);

    if (equipmentPList.isNull())
        return;

    // Check that it's an array
    if (!equipmentPList.isArray()) {
        OO_LOG("verifyOXP.equipmentPList.notArray", "{}", "***** ERROR: equipment.plist is not an array.");
        return;
    }

    runCheckWithEquipment(equipmentPList);
}

void OOCheckEquipmentPListVerifierStage::runCheckWithEquipment(const oo::PList& equipmentPList)
{
    unsigned entryIndex = 0;
    NSUInteger elemCount;
    std::optional<std::string> name;
    std::string entryDesc;

    for (const oo::PList& entry : *equipmentPList.getIf<oo::PList::Array>()) {
        ++entryIndex;

        // Entries should be arrays.
        if (!entry.isArray()) {
            OO_LOG("verifyOXP.equipmentPList.entryNotArray", "***** ERROR: equipment.plist entry {} of equipment.plist is not an array.", static_cast<unsigned>(entryIndex));
            continue;
        }

        elemCount = entry.getIf<oo::PList::Array>()->size();

        // Make a name for entry for display purposes.
        if (EQUIPMENT_KEY_INDEX < elemCount)
            name = StringAt(entry, EQUIPMENT_KEY_INDEX);
        else
            name = std::nullopt;

        if (name.has_value())
            entryDesc = oo::str::format("%u (\"%s\")", entryIndex, name->c_str());
        else
            entryDesc = oo::str::format("%u", entryIndex);

        // Check that the entry has an acceptable number of elements.
        if (elemCount < 5) {
            OO_LOG("verifyOXP.equipmentPList.badEntrySize", "***** ERROR: equipment.plist entry {} has too few elements ({}, should be 5 or 6).", entryDesc, elemCount);
            continue;
        }
        if (6 < elemCount) {
            OO_LOG("verifyOXP.equipmentPList.badEntrySize", "----- WARNING: equipment.plist entry {} has too many elements ({}, should be 5 or 6).", entryDesc, elemCount);
        }

        /*	Check element types. The numbers are required to be unsigned
                integers; the use of a negative default will catch both negative
                values and unconvertible values.
        */
        if (entry.at<long>(EQUIPMENT_TECH_LEVEL_INDEX, -1) < 0) {
            OO_LOG("verifyOXP.equipmentPList.badElementType", "***** ERROR: tech level for entry {} of equipment.plist is not a positive integer.", entryDesc);
        }
        if (entry.at<long>(EQUIPMENT_PRICE_INDEX, -1) < 0) {
            OO_LOG("verifyOXP.equipmentPList.badElementType", "***** ERROR: price for entry {} of equipment.plist is not a positive integer.", entryDesc);
        }
        if (!StringAt(entry, EQUIPMENT_SHORT_DESC_INDEX).has_value()) {
            OO_LOG("verifyOXP.equipmentPList.badElementType", "***** ERROR: short description for entry {} of equipment.plist is not a string.", entryDesc);
        }
        if (!StringAt(entry, EQUIPMENT_KEY_INDEX).has_value()) {
            OO_LOG("verifyOXP.equipmentPList.badElementType", "***** ERROR: key for entry {} of equipment.plist is not a string.", entryDesc);
        }
        if (!StringAt(entry, EQUIPMENT_LONG_DESC_INDEX).has_value()) {
            OO_LOG("verifyOXP.equipmentPList.badElementType", "***** ERROR: long description for entry {} of equipment.plist is not a string.", entryDesc);
        }

        if (5 < elemCount) {
            if (entry.at<oo::PList::Dict>(EQUIPMENT_EXTRA_INFO_INDEX) == nullptr) {
                OO_LOG("verifyOXP.equipmentPList.badElementType", "***** ERROR: equipment.plist entry {}'s extra information dictionary is not a dictionary.", entryDesc);
            }
            // TODO: verify contents of extra info dictionary.
        }
    }
}

#endif
