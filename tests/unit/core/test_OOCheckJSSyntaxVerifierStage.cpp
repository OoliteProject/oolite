/*	test_OOCheckJSSyntaxVerifierStage.mm
        Unit tests for OOCheckJSSyntaxVerifierStage.h/.mm: the stage that
   compiles an OXP's scripts, a leaf of OOFileHandlingVerifierStage.

        What the stage computes is pinned: its name and
   neighbours (the intermediate class's), when it runs (a non-empty Scripts
   folder, or Config/script.js), and which files it hands to the script loader
   (.js and .es in Scripts, in any case, then Config/script.js), with error
   locations switched on first. The script loader and the engine reach the whole
   game, so the test replaces them with classes that record what they are asked.
   Then the stage is global: the verifier registers and answers the C++ stage
   itself, so the facade case asks the stage (its description through
   description()). Run: tests/run.sh unit
*/

#include <filesystem>
#include <fstream>

#include "OOCheckJSSyntaxVerifierStage.h"
#include "OODescription.h"
#include "OOOXPVerifierStage.h"
#include "oo_test.hpp"
#include "oofnd/PListParsing.hpp"

/*	The game's OOLogging.mm reaches the resource manager, so it is not
   linked; the base calls this one function of it (a subclass responsibility).
*/
void OOLogGenericSubclassResponsibilityForFunction(const char* inFunction) {
  (void)inFunction;
}

/*	The verifier and the resource manager are not linked either (they reach
   the whole game). The stages talk to the verifier through its interface only,
   so the test is the verifier (as in test_OOFileScannerVerifierStage.mm). The
   resource manager has no built-in files here.
*/
#include "OOOXPVerifierTestDouble.h"
#include "ResourceManager.h"

// C++ definitions of the ResourceManager statics the code under test calls,
// with the stand-in's answers.
std::optional<std::string> ResourceManager::pathForFileNamed(
    const std::string& fileName, const std::optional<std::string>& folderName) {
  (void)fileName;
  (void)folderName;
  return std::nullopt;
}

// The engine and the script loader (OOJavaScriptEngine.mm and OOJSScript.mm
// reach the whole game).
namespace {

int gShowErrorLocations = 0;            // -setShowErrorLocations:YES calls
std::vector<std::string> gScriptPaths;  // +scriptWithPath:properties:, in order

}  // namespace

// The engine (OOJavaScriptEngine.h), declared with the header's names and
// signatures but not its class.
class OOJavaScriptEngine {
 public:
  static OOJavaScriptEngine* sharedEngine();
  void setShowErrorLocations(bool value);
};

OOJavaScriptEngine* OOJavaScriptEngine::sharedEngine() {
  static OOJavaScriptEngine* engine = new OOJavaScriptEngine;
  return engine;
}

void OOJavaScriptEngine::setShowErrorLocations(bool value) {
  if (value) gShowErrorLocations++;
}

#include "OOScript.h"

// OOJSScript (OOJSScript.h), which the code under test calls. The stand-in is a
// C++ subclass of OOScript declaring the members that code calls.
class OOJSScript : public OOScript {
 public:
  static oo::Ref<OOJSScript> scriptWithPath(
      const std::optional<std::string>& path, const oo::PList& properties);
};

oo::Ref<OOJSScript> OOJSScript::scriptWithPath(
    const std::optional<std::string>& path, const oo::PList& properties) {
  gScriptPaths.push_back(path.value_or("(nil)") +
                         (properties.isNull() ? "" : " with properties"));
  return nullptr;
}

namespace {

const char* const kConfiguration =
    "{"
    "	knownRootDirectories = (\"Config\", \"Scripts\");"
    "}";

// The log, as the stage writes it.
std::vector<std::string> gLog;

void Capture(std::string_view line) { gLog.emplace_back(line); }

void StartLog() {
  oo::log::logger().setInitialized(true);
  oo::log::logger().setSink(&Capture);
  gLog.clear();
}

int LogLinesContaining(std::string_view text) {
  int count = 0;
  for (const std::string& line : gLog) {
    if (line.find(text) != std::string::npos) count++;
  }
  return count;
}

void WriteFile(const std::filesystem::path& path, const char* contents) {
  std::filesystem::create_directories(path.parent_path());
  std::ofstream(path, std::ios::binary) << contents;
}

// The scanner, registered with the verifier and run over its OXP, as the
// verifier runs it first.
void RunScanner(OOOXPVerifier* verifier) {
  OOFileScannerVerifierStage::nameForDependencyForVerifier(verifier);
  verifier->stageWithName(OOFileScannerVerifierStage::kName)->run();
}

const std::vector<std::string> kScannerName = {"Scanning files"};
const std::vector<std::string> kUnusedName = {"Checking for unused files"};

const std::filesystem::path kBase =
    std::filesystem::current_path() / "test_OOCheckJSSyntaxVerifierStage.oxp";

// An OXP with the given files (relative paths), and its verifier with the
// scanner run over it.
OOOXPVerifier* MakeVerifier(std::initializer_list<const char*> files) {
  std::filesystem::remove_all(kBase);
  std::filesystem::create_directories(kBase);
  for (const char* file : files) WriteFile(kBase / file, "// script");
  OOOXPVerifier* verifier =
      OOOXPVerifierTestAccess::Make(kBase.generic_string(), kConfiguration);
  RunScanner(verifier);
  gShowErrorLocations = 0;
  gScriptPaths.clear();
  return verifier;
}

}  // namespace

OO_TEST(nameAndNeighbours) {
  {
    const oo::Ref<OOCheckJSSyntaxVerifierStage> stage =
        oo::makeRef<OOCheckJSSyntaxVerifierStage>();
    stage->setVerifier(MakeVerifier({}));
    OO_CHECK(stage->name() ==
             std::optional<std::string>("Checking JS Script file syntax"));
    OO_CHECK(stage->dependencies() == kScannerName);
    OO_CHECK(stage->dependents() == kUnusedName);
  }
}

OO_TEST(runsWhenThereAreScripts) {
  {
    const oo::Ref<OOCheckJSSyntaxVerifierStage> stage =
        oo::makeRef<OOCheckJSSyntaxVerifierStage>();
    stage->setVerifier(MakeVerifier({"Config/shipdata.plist"}));
    OO_CHECK(!stage->shouldRun());
    stage->run();
    OO_CHECK(gShowErrorLocations == 0 &&
             gScriptPaths.empty());  // nothing to do

    stage->setVerifier(MakeVerifier({"Scripts/readme.txt"}));
    OO_CHECK(stage->shouldRun());  // any file in Scripts

    stage->setVerifier(MakeVerifier({"Config/script.js"}));
    OO_CHECK(stage->shouldRun());

    stage->setVerifier(MakeVerifier({"Config/Script.js"}));
    OO_CHECK(!stage->shouldRun());  // the Config listing is as on disk
  }
  std::filesystem::remove_all(kBase);
}

OO_TEST(compilesEachScript) {
  {
    const oo::Ref<OOCheckJSSyntaxVerifierStage> stage =
        oo::makeRef<OOCheckJSSyntaxVerifierStage>();
    stage->setVerifier(MakeVerifier({"Scripts/b.js", "Scripts/A.JS",
                                     "Scripts/c.es", "Scripts/notes.txt",
                                     "Scripts/noext", "Config/script.js"}));
    StartLog();
    stage->run();
    OO_CHECK(LogLinesContaining("ERROR") == 0 &&
             LogLinesContaining("WARNING") ==
                 0);  // the loader reports, not the stage
    OO_CHECK(gShowErrorLocations == 1);
    const std::string base = kBase.generic_string();
    OO_CHECK(gScriptPaths ==
             (std::vector<std::string>{
                 base + "/Scripts/A.JS", base + "/Scripts/b.js",
                 base + "/Scripts/c.es", base + "/Config/script.js"}));

    // Only the Config script.
    stage->setVerifier(MakeVerifier({"Config/script.js"}));
    stage->run();
    OO_CHECK(gShowErrorLocations == 1);
    OO_CHECK(gScriptPaths ==
             std::vector<std::string>{base + "/Config/script.js"});
  }
  std::filesystem::remove_all(kBase);
}

// The stage is global: the verifier registers it and finds it by name, and it
// describes itself with its class's name.
OO_TEST(facade) {
  {
    OOOXPVerifier* verifier = MakeVerifier({"Config/script.js"});
    const oo::Ref<OOCheckJSSyntaxVerifierStage> stage =
        oo::makeRef<OOCheckJSSyntaxVerifierStage>();
    OO_CHECK(
        stage->description().starts_with("<OOCheckJSSyntaxVerifierStage 0x"));

    verifier->registerStage(stage.get());
    OO_CHECK(verifier->stageWithName("Checking JS Script file syntax") ==
             stage.get());
    OO_CHECK(stage->name() ==
             std::optional<std::string>("Checking JS Script file syntax"));
    OO_CHECK(stage->dependencies() == kScannerName);
    OO_CHECK(stage->dependents() == kUnusedName);
  }
}

OO_TEST_MAIN()
