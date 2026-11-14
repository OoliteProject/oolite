/*	test_OOModelVerifierStage.mm
        Unit tests for OOModelVerifierStage.h/.mm: the model stage, a subclass
   of OOTextureHandlingStage.

        The tests pin: its name, that asking its name registers it (once), its
   neighbours (the intermediate class's), the models other stages name (found in
   the OXP or built in, or not; an empty name is not found; each model and
   context once), when it runs, and what it logs (a placeholder check of each
   model, in the order named). The verifier finds it again by its name. The
   stage is global. The verifier registers and answers the C++ stage itself, so
   nameRegistersTheStage and the facade case ask the stage (its description
   through description()). Run: tests/run.sh unit
*/

#include <filesystem>
#include <fstream>

#include "OODescription.h"
#include "OOModelVerifierStage.h"
#include "OOOXPVerifierStage.h"
#include "OOPixMap.h"
#include "OOTextureLoader.h"
#include "oo_test.hpp"
#include "oofnd/Log.hpp"
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
   resource manager has one built-in model.
*/
#include "OOOXPVerifierTestDouble.h"
#include "ResourceManager.h"

// ResourceManager: C++ definitions of the statics the code under test calls,
// with the stand-in's answers.
std::optional<std::string> ResourceManager::pathForFileNamed(
    const std::string& fileName, const std::optional<std::string>& folderName) {
  if (fileName != "builtin.dat") return std::nullopt;
  return "builtin/" + folderName.value_or("") + "/" + fileName;
}

// The texture stage (linked for the intermediate class) loads through these; no
// model here names a texture.
void OOFreePixMap(OOPixMap* ioPixMap) { *ioPixMap = OOPixMap{}; }

// The loader factory, answering nil.
oo::Ref<OOTextureLoader> OOTextureLoader::loaderWithPath(
    const std::optional<std::string>& /*path*/, uint32_t /*options*/) {
  return nullptr;
}

namespace {

const char* const kConfiguration =
    "{"
    "	knownRootDirectories = (\"Models\");"
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
    std::filesystem::current_path() / "test_OOModelVerifierStage.oxp";

// An OXP with the given files (path, contents), and its verifier with the
// scanner run over it.
OOOXPVerifier* MakeVerifier(
    std::initializer_list<std::pair<const char*, const char*>> files) {
  std::filesystem::remove_all(kBase);
  std::filesystem::create_directories(kBase);
  for (const auto& [name, contents] : files) WriteFile(kBase / name, contents);
  OOOXPVerifier* verifier =
      OOOXPVerifierTestAccess::Make(kBase.generic_string(), kConfiguration);
  RunScanner(verifier);
  StartLog();
  return verifier;
}

}  // namespace

OO_TEST(nameRegistersTheStage) {
  {
    OOOXPVerifier* verifier = MakeVerifier({});
    OO_CHECK(verifier->stageWithName("Testing models") == nullptr);
    OO_CHECK(verifier->stageWithName(OOModelVerifierStage::kName) == nullptr);
    OO_CHECK(OOModelVerifierStage::nameForReverseDependencyForVerifier(
                 verifier) == "Testing models");
    OOOXPVerifierStage* registered =
        verifier->stageWithName(OOModelVerifierStage::kName);
    OO_CHECK(registered != nullptr &&
             verifier->stageWithName("Testing models") == registered);
    OO_CHECK(OOModelVerifierStage::nameForReverseDependencyForVerifier(
                 verifier) == "Testing models");
    OO_CHECK(verifier->stageWithName(OOModelVerifierStage::kName) ==
             registered);  // once

    OO_CHECK(registered->name() ==
             std::optional<std::string>("Testing models"));
    OO_CHECK(registered->dependencies() == kScannerName);
    OO_CHECK(registered->dependents() ==
             (std::vector<std::string>{"Checking for unused files",
                                       "Testing textures and images"}));
    OO_CHECK(!registered->shouldRun());
  }
  std::filesystem::remove_all(kBase);
}

OO_TEST(stagesNameModels) {
  {
    OOOXPVerifier* verifier = MakeVerifier({{"Models/ship.dat", "model"}});
    const oo::Ref<OOModelVerifierStage> stage =
        oo::makeRef<OOModelVerifierStage>();
    stage->setVerifier(verifier);
    const oo::PList materials = *oo::parsePropertyListData("{ a = b; }");

    OO_CHECK(!stage->modelNamed("", "a", "shipdata.plist", oo::PList(),
                                oo::PList()));
    OO_CHECK(!stage->modelNamed("missing.dat", "a", "shipdata.plist",
                                oo::PList(), oo::PList()));
    OO_CHECK(!stage->shouldRun() &&
             gLog.empty());  // a missing model: the caller complains

    OO_CHECK(stage->modelNamed("ship.dat", "a", "shipdata.plist", materials,
                               oo::PList()));
    OO_CHECK(stage->shouldRun());
    OO_CHECK(stage->modelNamed("ship.dat", "a", "shipdata.plist", materials,
                               oo::PList()));  // again: once
    OO_CHECK(stage->modelNamed("ship.dat", "b", "shipdata.plist", oo::PList(),
                               oo::PList()));  // another entry
    OO_CHECK(stage->modelNamed("builtin.dat", std::nullopt, "demoships.plist",
                               oo::PList(), oo::PList()));
    OO_CHECK(stage->modelNamed("SHIP.DAT", "c", "shipdata.plist", oo::PList(),
                               oo::PList()));
    const size_t caseWarnings =
        gLog.size();  // the scanner's case warning for SHIP.DAT
    OO_CHECK(LogLinesContaining("case mismatch") == 1);

    gLog.clear();
    stage->run();
    OO_CHECK(caseWarnings == 1);
    OO_CHECK(gLog == (std::vector<std::string>{
                         "TODO: implement model verifier.",
                         "- Pretending to verify model ship.dat referenced in "
                         "entry \"a\" of shipdata.plist.",
                         "- Pretending to verify model ship.dat referenced in "
                         "entry \"b\" of shipdata.plist.",
                         "- Pretending to verify model builtin.dat referenced "
                         "in demoships.plist.",
                         "- Pretending to verify model SHIP.DAT referenced in "
                         "entry \"c\" of shipdata.plist."}));

    // The models are forgotten after the run.
    OO_CHECK(!stage->shouldRun());
    gLog.clear();
    stage->run();
    OO_CHECK(gLog ==
             std::vector<std::string>{"TODO: implement model verifier."});
  }
  std::filesystem::remove_all(kBase);
}

// The stage is global: the verifier registers the stage itself, and finds it by
// name for the ship data stage.
OO_TEST(facade) {
  {
    OOOXPVerifier* verifier = MakeVerifier({{"Models/ship.dat", "model"}});
    OOModelVerifierStage::nameForReverseDependencyForVerifier(verifier);
    OOModelVerifierStage* stage = static_cast<OOModelVerifierStage*>(
        verifier->stageWithName(OOModelVerifierStage::kName));
    OO_CHECK(stage != nullptr);
    OO_CHECK(stage->description().starts_with("<OOModelVerifierStage 0x"));

    OO_CHECK(stage->name() ==
             std::optional<std::string>(OOModelVerifierStage::kName));
    OO_CHECK(stage->dependents() ==
             (std::vector<std::string>{"Checking for unused files",
                                       "Testing textures and images"}));
    OO_CHECK(!stage->shouldRun());
    OO_CHECK(stage->modelNamed("ship.dat", "a", "shipdata.plist", oo::PList(),
                               oo::PList()));
    OO_CHECK(stage->shouldRun());
    gLog.clear();
    stage->dependencyRegistrationComplete();
    stage->performRun();
    OO_CHECK(
        gLog.size() == 2 &&
        LogLinesContaining("- Pretending to verify model ship.dat referenced "
                           "in entry \"a\" of shipdata.plist.") == 1);
  }
  std::filesystem::remove_all(kBase);
}

OO_TEST_MAIN()
