/*

OOCheckJSSyntaxVerifierStage.m


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

#include "OOCheckJSSyntaxVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#include "OOFileScannerVerifierStage.h"
#include "OOJSScript.h"
#include "OOJavaScriptEngine.h"
#include "OOScript.h"
#include "OOStringParsing.h"
#include "oofnd/String.hpp"

static const char* const kStageName = "Checking JS Script file syntax";

namespace {

bool Contains(const std::vector<std::string>& strings,
              std::string_view string) {
  return std::find(strings.begin(), strings.end(), string) != strings.end();
}

}  // namespace

std::optional<std::string> OOCheckJSSyntaxVerifierStage::name() {
  return kStageName;
}

bool OOCheckJSSyntaxVerifierStage::shouldRun() {
  OOFileScannerVerifierStage* fileScanner = nullptr;

  fileScanner = static_cast<OOFileScannerVerifierStage*>(
      verifier()->stageWithName(OOFileScannerVerifierStage::kName));
  if (fileScanner == nullptr) return false;  // a nil scanner listed no files
  return (!fileScanner->filesInFolder("Scripts")
               .value_or(std::vector<std::string>{})
               .empty() ||
          Contains(fileScanner->filesInFolder("Config").value_or(
                       std::vector<std::string>{}),
                   "script.js"));
}

void OOCheckJSSyntaxVerifierStage::run() {
  OOFileScannerVerifierStage* fileScanner = nullptr;
  std::vector<std::string> scriptFiles;
  bool scriptsFolder = false;
  bool configScript = false;

  fileScanner = static_cast<OOFileScannerVerifierStage*>(
      verifier()->stageWithName(OOFileScannerVerifierStage::kName));
  if (fileScanner == nullptr) return;  // a nil scanner listed no files
  scriptsFolder = fileScanner->filesInFolder("Scripts").has_value();
  scriptFiles = fileScanner->filesInFolder("Scripts").value_or(
      std::vector<std::string>{});
  configScript = Contains(
      fileScanner->filesInFolder("Config").value_or(std::vector<std::string>{}),
      "script.js");

  if (scriptsFolder == false && configScript == false) return;

  OOJavaScriptEngine::sharedEngine()->setShowErrorLocations(true);

  for (const std::string& scriptFile : scriptFiles) {
    const std::string fileExt =
        oo::str::lowercase(oo::str::pathExtension(scriptFile));
    if (fileExt == "js" || fileExt == "es") {
      const oo::Ref<OOJSScript> script = OOJSScript::scriptWithPath(
          fileScanner->pathForFile(scriptFile, "Scripts", std::nullopt, false),
          oo::PList());
      (void)script;
    }
  }
  if (configScript == true) {
    const oo::Ref<OOJSScript> script = OOJSScript::scriptWithPath(
        fileScanner->pathForFile("script.js", "Config", std::nullopt, false),
        oo::PList());
    (void)script;
  }
}

#endif
