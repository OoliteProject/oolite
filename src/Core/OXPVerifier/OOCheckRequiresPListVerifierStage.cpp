/*

OOCheckRequiresPListVerifierStage.m


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

#include "OOCheckRequiresPListVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#include "OOFileScannerVerifierStage.h"
#include "OOStringParsing.h"
#include "oofnd/FileSystem.hpp"
#include "oofnd/PListParsing.hpp"
#include "oofnd/ResourcePaths.hpp"
#include "oofnd/String.hpp"

static const char* const kStageName = "Checking requires.plist";

namespace {

// The string value of <key>, or nullopt (logging an error) when it is present
// but not a string.
std::optional<std::string> VersionStringForKey(const oo::PList& requiresPList,
                                               std::string_view key,
                                               std::string_view errorMessage) {
  const oo::PList* value = requiresPList.find(key);
  if (value == nullptr) return std::nullopt;
  if (const std::string* string = value->getIf<std::string>()) return *string;
  OO_LOG("verifyOXP.requiresPList.badValue", "{}", errorMessage);
  return std::nullopt;
}

}  // namespace

namespace {

// Info-gnustep.plist string (CFBundleVersion / CFBundleName as the Override
// category used to expose).
std::optional<std::string> OoliteInfoString(std::string_view key) {
  const oo::fs::Path plistPath =
      oo::ResourcePaths::current().builtInResourcesDirectory() /
      "Info-gnustep.plist";
  oo::PList info;
  if (const oo::fs::Result<oo::Data> bytes = oo::fs::readFile(plistPath);
      bytes && !bytes->empty()) {
    if (oo::Expected<oo::PList, oo::PListError> parsed =
            oo::parsePropertyList(bytes->stringView());
        parsed && parsed->isDict())
      info = std::move(*parsed);
  }
  if (const oo::PList* v = info.find(key); v != nullptr && v->isString())
    return *v->getIf<std::string>();
  return std::nullopt;
}

}  // namespace

std::optional<std::string> OOCheckRequiresPListVerifierStage::name() {
  return kStageName;
}

bool OOCheckRequiresPListVerifierStage::shouldRun() {
  OOFileScannerVerifierStage* fileScanner = nullptr;

  fileScanner = static_cast<OOFileScannerVerifierStage*>(
      verifier()->stageWithName(OOFileScannerVerifierStage::kName));
  return fileScanner != nullptr &&
         fileScanner->fileExists("requires.plist", "Config", std::nullopt,
                                 false);
}

void OOCheckRequiresPListVerifierStage::run() {
  OOFileScannerVerifierStage* fileScanner = nullptr;
  oo::PList requiresPList;
  std::vector<std::string> knownKeys;
  std::string unknownKeys;
  std::optional<std::string> version, maxVersion;
  std::vector<unsigned>
      ooVersionComponents;  // empty where ComponentsFromVersionString()
                            // answered nil
  std::optional<std::vector<unsigned>> versionComponents, maxVersionComponents;

  fileScanner = static_cast<OOFileScannerVerifierStage*>(
      verifier()->stageWithName(OOFileScannerVerifierStage::kName));
  if (fileScanner != nullptr)
    requiresPList = fileScanner->plistNamed("requires.plist", "Config",
                                            std::nullopt, false);

  if (requiresPList.isNull()) return;

  // Check that it's a dictionary
  if (!requiresPList.isDict()) {
    OO_LOG("verifyOXP.requiresPList.notDict", "{}",
           "***** ERROR: requires.plist is not a dictionary.");
    return;
  }

  // Check that all the keys are known.
  knownKeys = verifier()
                  ->configurationSetForKey("requiresPListSupportedKeys")
                  .value_or(std::vector<std::string>());
  for (const auto& [key, value] : *requiresPList.getIf<oo::PList::Dict>()) {
    if (std::find(knownKeys.begin(), knownKeys.end(), key) != knownKeys.end())
      continue;
    if (!unknownKeys.empty()) unknownKeys += ", ";
    unknownKeys += key;
  }

  if (!unknownKeys.empty()) {
    OO_LOG("verifyOXP.requiresPList.unknownKeys",
           "----- WARNING: requires.plist contains unknown keys. This OXP will "
           "not be loaded by this version of Oolite. Unknown keys are: {}.",
           unknownKeys);
  }

  // Sanity check the known keys.
  version =
      VersionStringForKey(requiresPList, "version",
                          "***** ERROR: Value for 'version' is not a string.");
  maxVersion = VersionStringForKey(
      requiresPList, "max_version",
      "***** ERROR: Value for 'max_version' is not a string.");

  if (version.has_value() || maxVersion.has_value()) {
    ooVersionComponents = oo::str::versionComponents(
        OoliteInfoString("CFBundleVersion").value_or(""));
    if (ooVersionComponents.empty()) {
      OO_LOG("verifyOXP.requiresPList.cantFindOoliteVersion", "{}",
             "----- WARNING: could not find Oolite's version for "
             "requires.plist sanity check.");
    }
    if (version.has_value()) {
      versionComponents = oo::str::versionComponents(*version);
      if (versionComponents->empty()) {
        OO_LOG("verifyOXP.requiresPList.badValue",
               "***** ERROR: could not interpret version string \"{}\" as "
               "version number.",
               *version);
        versionComponents = std::nullopt;
      } else if (!ooVersionComponents.empty()) {
        if (oo::str::compareVersions(ooVersionComponents, *versionComponents) <
            0) {
          OO_LOG("verifyOXP.requiresPList.oxpRequiresNewerOolite",
                 "----- WARNING: this OXP requires a newer version of Oolite "
                 "({}) to work.",
                 *version);
        }
      }
    }
    if (maxVersion.has_value()) {
      maxVersionComponents = oo::str::versionComponents(*maxVersion);
      if (maxVersionComponents->empty()) {
        OO_LOG("verifyOXP.requiresPList.badValue",
               "***** ERROR: could not interpret max_version string \"{}\" as "
               "version number.",
               *maxVersion);
        maxVersionComponents = std::nullopt;
      } else if (!ooVersionComponents.empty()) {
        if (oo::str::compareVersions(ooVersionComponents,
                                     *maxVersionComponents) > 0) {
          OO_LOG("verifyOXP.requiresPList.oxpRequiresOlderOolite",
                 "----- WARNING: this OXP requires an older version of Oolite "
                 "({}) to work.",
                 *maxVersion);
        }
      }
    }

    if (versionComponents.has_value() && maxVersionComponents.has_value()) {
      if (oo::str::compareVersions(*versionComponents, *maxVersionComponents) >
          0) {
        OO_LOG("verifyOXP.requiresPList.noVersionsInRange",
               "***** ERROR: this OXP's maximum version ({}) is less than its "
               "minimum version ({}).",
               *maxVersion, *version);
      }
    }
  }
}

#endif
