/*	test_OOOXPVerifier.mm
        Unit tests for OOOXPVerifier (src/Core/OXPVerifier/OOOXPVerifier.h).

        The verifier reaches the resource manager, the cache manager, the game
   controller and the log handler, so the test links every game object but
   main's (tests/unit/core/meson.build entry ['*']) and defines gDebugFlags. The
   user's directories and the game folder are a scratch folder holding the
   verifier's own configuration, Resources/Config/verifyOXP.plist, which names
   the test's stages (C++ subclasses of OOOXPVerifierStage); the stages record
   what the verifier asks of them. Opening the log at the end is switched off in
   the defaults.

        It is driven as the game drives it, through +runVerificationIfRequested
   with -verify-oxp on the command line: no request, a request without a path, a
   missing path, a file. Then a run: registration (unknown, excluded, nameless
   and same-named classes; a stage registered while another answers its
   dependents; registration refused once it closes), dependency resolution
   (order, reverse dependencies, an unresolved dependency, a loop), running (a
   stage that should not run, an exception in a stage), and what a stage reads
   from the verifier (path, display name, configuration, other stages by name).

        The test's stages are C++ subclasses of OOOXPVerifierStage, which the
   verifier makes by name through its test hook (OOOXPVerifierTestAccess), and
   the stages hand and compare the C++ stages with -registerStage: and
   -cxx_stageWithName:. The test runs the verification through the static
   OOOXPVerifier::runVerificationIfRequested(), as GameController does, and the
   stages call the C++ verifier they keep (verifier()). Run: bash
   meson test -C build/meson_test test_OOOXPVerifier
*/

#include <process.h>

#include <cstdlib>
#include <filesystem>
#include <map>
#include <string>
#include <vector>

#include "OOOXPVerifier.h"
#include "OOOXPVerifierStage.h"
#include "oo_test.hpp"
#include "oofnd/Defaults.hpp"
#include "oofnd/FileSystem.hpp"
#include "oofnd/Process.hpp"
#include "oofnd/objc/OOException.h"

// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

/*	The verifier makes the stages verifyOXP.plist names; a test's stage by
   its class name through this hook.
*/
struct OOOXPVerifierTestAccess {
  static void SetStageMaker(
      std::shared_ptr<OOOXPVerifierStage> (*maker)(const std::string& name)) {
    OOOXPVerifier::sTestStageMaker = maker;
  }
};

namespace {

namespace stdfs = std::filesystem;

stdfs::path sRoot;
std::vector<std::string> gEvents;

std::shared_ptr<OOOXPVerifierStage> MakeTestStage(
    const std::string& name);  // with the test's stages, below

// What a stage read from the verifier during its run.
struct VerifierView {
  bool seen = false;
  std::optional<std::string> path, displayName, string, number, notAString;
  oo::PList value, array, dictionary, notAnArray, notADictionary, missing;
  std::optional<std::vector<std::string>> set, notASet;
  bool foundA = false, foundNothing = false;
};
VerifierView gView;

void WriteText(const stdfs::path& path, const std::string& text) {
  stdfs::create_directories(path.parent_path());
  OO_CHECK(oo::fs::writeFile(path, oo::Data(text.data(), text.size()),
                             oo::fs::WriteMode::kDirect)
               .has_value());
}

const char* const kConfiguration = R"(<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>stages</key>
	<array><string>OOTestStageA</string><string>OOTestStageB</string><string>OOTestStageC</string><string>OOTestStageD</string><string>OOTestStageE</string><string>OOTestStageF</string><string>OOTestStageG</string><string>OOTestStageH</string><string>OOTestStageI</string><string>OOTestStageJ</string><string>OOTestStageK</string><string>OOTestStageL</string><string>OOTestStageNameless</string><string>OOTestStageDup2</string><string>OOTestStageDup1</string><string>OOTestStageX</string><string>OOTestNoSuchClass</string><string>OOTestStageA</string></array>
	<key>excludeStages</key>
	<array><string>OOTestStageX</string></array>
	<key>aString</key>
	<string>text</string>
	<key>aNumber</key>
	<integer>42</integer>
	<key>notAString</key>
	<array><integer>1</integer></array>
	<key>anArray</key>
	<array><string>b</string><string>a</string><string>b</string><integer>7</integer></array>
	<key>aDictionary</key>
	<dict><key>key</key><string>value</string></dict>
</dict>
</plist>
)";

// The scratch home and game folder with the verifier's configuration, made
// once.
void SetUp() {
  if (!sRoot.empty()) return;
  sRoot = stdfs::temp_directory_path() /
          ("oo-test-oxpverifier-" +
           std::to_string(static_cast<unsigned long>(::_getpid())));
  stdfs::remove_all(sRoot);
  stdfs::create_directories(sRoot);
  OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
  stdfs::current_path(sRoot);
  WriteText(sRoot / "Resources" / "Info-gnustep.plist",
            "{ CFBundleVersion = \"9.9.9-test\"; }");
  WriteText(sRoot / "Resources" / "Config" / "verifyOXP.plist", kConfiguration);
  WriteText(sRoot / "Test.oxp" / "Config" / "script.js",
            "this.name = \"test\";\n");
  WriteText(sRoot / "a-file.txt", "not an OXP\n");
  // The verifier opens its log in the user's editor at the end unless told not
  // to.
  oo::Defaults::standard().setObject("oxp-verifier-open-log", oo::PList(false));
  OOOXPVerifierTestAccess::SetStageMaker(MakeTestStage);
}

// runVerificationIfRequested() with this command line (after the program's
// name).
bool RunWithArguments(std::vector<std::string> arguments) {
  arguments.insert(arguments.begin(), "core_test_OOOXPVerifier");
  std::vector<const char*> argv;
  for (const std::string& argument : arguments)
    argv.push_back(argument.c_str());
  oo::process::setArguments(static_cast<int>(argv.size()), argv.data());
  gEvents.clear();
  return OOOXPVerifier::runVerificationIfRequested();
}

}  // namespace

// --- The test's stages
// ------------------------------------------------------------------------ C++
// subclasses of OOOXPVerifierStage.

class OOTestStage : public OOOXPVerifierStage {
 public:
  std::optional<std::string> name() override { return std::nullopt; }
  void run() override { gEvents.push_back("run " + name().value_or("(null)")); }
};

#define TEST_STAGE(cls, stageName)               \
  class cls : public OOTestStage {               \
   public:                                       \
    std::optional<std::string> name() override { \
      return std::string(stageName);             \
    }
#define DEPENDS_ON(...)                                             \
  std::optional<std::vector<std::string>> dependencies() override { \
    return std::vector<std::string>{__VA_ARGS__};                   \
  }
#define DEPENDENTS(...)                                           \
  std::optional<std::vector<std::string>> dependents() override { \
    return std::vector<std::string>{__VA_ARGS__};                 \
  }

TEST_STAGE(OOTestStageB, "B") DEPENDS_ON("A")
}
;
TEST_STAGE(OOTestStageC, "C") DEPENDS_ON("Missing")
}
;
TEST_STAGE(OOTestStageD, "D") DEPENDENTS("A", "Nowhere")
}
;
TEST_STAGE(OOTestStageE, "E") bool shouldRun() override {
  gEvents.push_back("should E");
  return false;
}
}
;
TEST_STAGE(OOTestStageF, "F") DEPENDS_ON("E")
}
;
TEST_STAGE(OOTestStageH, "H") DEPENDS_ON("G")
}
;
TEST_STAGE(OOTestStageI, "I") DEPENDS_ON("J")
}
;
TEST_STAGE(OOTestStageJ, "J") DEPENDS_ON("I")
}
;
TEST_STAGE(OOTestStageX, "X")
}
;
TEST_STAGE(OOTestStageDup1, "Dup") void run() override {
  gEvents.push_back("run Dup1");
}
}
;
TEST_STAGE(OOTestStageDup2, "Dup") void run() override {
  gEvents.push_back("run Dup2");
}
}
;
TEST_STAGE(OOTestStageSub, "Sub")
}
;
TEST_STAGE(OOTestStageLate, "Late")
}
;

class OOTestStageNameless : public OOTestStage {};

// A reads the verifier while it runs.
TEST_STAGE(OOTestStageA, "A")
void run() override {
  OOTestStage::run();
  OOOXPVerifier* verifier = this->verifier();
  gView.seen = (verifier != nullptr);
  gView.path = verifier->oxpPath();
  gView.displayName = verifier->oxpDisplayName();
  gView.value = verifier->configurationValueForKey("aNumber");
  gView.missing = verifier->configurationValueForKey("noSuchKey");
  gView.array = verifier->configurationArrayForKey("anArray");
  gView.notAnArray = verifier->configurationArrayForKey("aString");
  gView.dictionary = verifier->configurationDictionaryForKey("aDictionary");
  gView.notADictionary = verifier->configurationDictionaryForKey("anArray");
  gView.string = verifier->configurationStringForKey("aString");
  gView.number = verifier->configurationStringForKey("aNumber");
  gView.notAString = verifier->configurationStringForKey("notAString");
  gView.set = verifier->configurationSetForKey("anArray");
  gView.notASet = verifier->configurationSetForKey("aDictionary");
  gView.foundA = (verifier->stageWithName("A") == this);
  gView.foundNothing = (verifier->stageWithName("Missing") == nullptr);
}
}
;

// G raises while it runs.
TEST_STAGE(OOTestStageG, "G")
void run() override {
  OOTestStage::run();
  OORaiseException("OOTestException", "%s", "G fails");
}
}
;

// K registers a substage when asked for its dependents, as the verifier allows.
TEST_STAGE(OOTestStageK, "K")
std::optional<std::vector<std::string>> dependents() override {
  const std::shared_ptr<OOTestStageSub> sub = oo::makeShared<OOTestStageSub>();
  verifier()->registerStage(sub.get());
  return std::nullopt;
}
}
;

// L registers a stage while it runs, which the verifier refuses.
TEST_STAGE(OOTestStageL, "L")
void run() override {
  OOTestStage::run();
  const std::shared_ptr<OOTestStageLate> late = oo::makeShared<OOTestStageLate>();
  verifier()->registerStage(late.get());
  gEvents.push_back(verifier()->stageWithName("Late") == nullptr
                        ? "Late refused"
                        : "Late registered");
}
}
;

// The stages the verifier makes by name through the test hook.
namespace {

template <class Stage>
std::shared_ptr<OOOXPVerifierStage> Make() {
  return std::shared_ptr<OOOXPVerifierStage>(oo::makeShared<Stage>());
}

std::shared_ptr<OOOXPVerifierStage> MakeTestStage(const std::string& name) {
  static const std::map<std::string, std::shared_ptr<OOOXPVerifierStage> (*)()> makers =
      {
          {"OOTestStageA", Make<OOTestStageA>},
          {"OOTestStageB", Make<OOTestStageB>},
          {"OOTestStageC", Make<OOTestStageC>},
          {"OOTestStageD", Make<OOTestStageD>},
          {"OOTestStageE", Make<OOTestStageE>},
          {"OOTestStageF", Make<OOTestStageF>},
          {"OOTestStageG", Make<OOTestStageG>},
          {"OOTestStageH", Make<OOTestStageH>},
          {"OOTestStageI", Make<OOTestStageI>},
          {"OOTestStageJ", Make<OOTestStageJ>},
          {"OOTestStageK", Make<OOTestStageK>},
          {"OOTestStageL", Make<OOTestStageL>},
          {"OOTestStageX", Make<OOTestStageX>},
          {"OOTestStageNameless", Make<OOTestStageNameless>},
          {"OOTestStageDup1", Make<OOTestStageDup1>},
          {"OOTestStageDup2", Make<OOTestStageDup2>},
          {"OOTestStageSub", Make<OOTestStageSub>},
          {"OOTestStageLate", Make<OOTestStageLate>},
      };
  const auto found = makers.find(name);
  return found != makers.end() ? found->second() : nullptr;
}

}  // namespace

// --- Tests
// ------------------------------------------------------------------------------------

OO_TEST(noRequest) {
  SetUp();
  {
    OO_CHECK(!RunWithArguments({}));
    OO_CHECK(!RunWithArguments({"-load", "Test.oxp"}));
    OO_CHECK(gEvents.empty());
  }
}

// -verify-oxp or --verify-oxp is answered YES even when there is nothing to
// verify.
OO_TEST(requestWithoutAnOXP) {
  SetUp();
  {
    OO_CHECK(RunWithArguments({"-verify-oxp"}));
    OO_CHECK(RunWithArguments({"--verify-oxp", "NoSuch.oxp"}));
    OO_CHECK(RunWithArguments({"-verify-oxp", "a-file.txt"}));
    OO_CHECK(gEvents.empty());
  }
}

OO_TEST(verification) {
  SetUp();
  {
    const std::string path = (sRoot / "Test.oxp").generic_string();
    OO_CHECK(RunWithArguments({"-verify-oxp", path}));

    // Registration in the configuration's (sorted, distinct) order, X excluded,
    // the unknown class, the nameless stage and the second "Dup" refused, Sub
    // added by K. Resolution drops C (unresolved) and the I/J loop; D runs
    // before A (its dependent); E is asked and skipped, and F (after E) still
    // runs; G raises and H (after G) still runs; L's late registration is
    // refused.
    const std::vector<std::string> expected = {
        "run D", "run A", "run B", "run Dup1", "should E",     "run F",
        "run G", "run H", "run K", "run L",    "Late refused", "run Sub",
    };
    OO_CHECK(gEvents == expected);
    if (gEvents != expected) {
      for (const std::string& event : gEvents)
        std::printf("  event: %s\n", event.c_str());
    }

    OO_CHECK(gView.seen);
    OO_CHECK(gView.path == std::optional<std::string>(path));
    OO_CHECK(gView.displayName == std::optional<std::string>("Test.oxp"));
    OO_CHECK(gView.value.isNumber() && gView.value.int64Value() == 42);
    OO_CHECK(gView.missing.isNull());
    OO_CHECK(gView.array.isArray() && gView.array.count() == 4);
    OO_CHECK(gView.notAnArray.isNull());
    OO_CHECK(gView.dictionary.isDict() &&
             gView.dictionary.get<std::string>("key") == "value");
    OO_CHECK(gView.notADictionary.isNull());
    OO_CHECK(gView.string == std::optional<std::string>("text"));
    OO_CHECK(gView.number == std::optional<std::string>("42"));
    OO_CHECK(!gView.notAString.has_value());
    OO_CHECK(gView.set == std::optional<std::vector<std::string>>(
                              std::vector<std::string>{"a", "b"}));
    OO_CHECK(!gView.notASet.has_value());
    OO_CHECK(gView.foundA);
    OO_CHECK(gView.foundNothing);
  }
}

OO_TEST_MAIN()
