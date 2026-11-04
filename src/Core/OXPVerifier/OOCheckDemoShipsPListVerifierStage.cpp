/*

OOCheckDemoShipsPListVerifierStage.m


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

#include "OOCheckDemoShipsPListVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#include "OOFileScannerVerifierStage.h"

static const char* const kStageName = "Checking demoships.plist";

std::optional<std::string> OOCheckDemoShipsPListVerifierStage::name() {
  return kStageName;
}

bool OOCheckDemoShipsPListVerifierStage::shouldRun() {
  OOFileScannerVerifierStage* fileScanner = nullptr;

  fileScanner = static_cast<OOFileScannerVerifierStage*>(
      verifier()->stageWithName(OOFileScannerVerifierStage::kName));
  return fileScanner != nullptr &&
         fileScanner->fileExists("demoships.plist", "Config", std::nullopt,
                                 false);
}

void OOCheckDemoShipsPListVerifierStage::run() {
  OOFileScannerVerifierStage* fileScanner = nullptr;
  oo::PList demoshipsPList;
  oo::PList shipdataPList;

  fileScanner = static_cast<OOFileScannerVerifierStage*>(
      verifier()->stageWithName(OOFileScannerVerifierStage::kName));
  if (fileScanner == nullptr) return;  // a nil scanner found no plist

  demoshipsPList =
      fileScanner->plistNamed("demoships.plist", "Config", std::nullopt, false);

  if (demoshipsPList.isNull()) return;

  // Check that it's an array
  if (!demoshipsPList.isArray()) {
    OO_LOG("verifyOXP.demoshipsPList.notArray", "{}",
           "***** ERROR: demoships.plist is not an array.");
    return;
  }

  shipdataPList =
      fileScanner->plistNamed("shipdata.plist", "Config", std::nullopt, false);

  if (shipdataPList.isNull()) return;

  // Check that it's a dictionary
  if (!shipdataPList.isDict()) {
    OO_LOG("verifyOXP.demoshipsPList.notDict", "{}",
           "***** ERROR: shipdata.plist is not a dictionary.");
    return;
  }

  runCheckWithDemoShips(demoshipsPList, shipdataPList);
}

void OOCheckDemoShipsPListVerifierStage::runCheckWithDemoShips(
    const oo::PList& demoshipsPList, const oo::PList& shipdataPList) {
  for (const oo::PList& entry : *demoshipsPList.getIf<oo::PList::Array>()) {
    // An entry that is not a string is no key of shipdata.plist; print the
    // entry description.
    const std::string* name = entry.getIf<std::string>();
    if (name == nullptr || shipdataPList.find(*name) == nullptr) {
      OO_LOG("verifyOXP.demoshipsPList.unknownShip",
             "----- WARNING: demoships.plist entry \"{}\" not found in "
             "shipdata.plist.",
             name != nullptr ? *name : oo::DescriptionOf(entry));
    }
  }
}

#endif
