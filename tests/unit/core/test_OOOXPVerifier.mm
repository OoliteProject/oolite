/*	test_OOOXPVerifier.mm
	Unit tests for cxx::OOOXPVerifier (src/Core/OXPVerifier/OOOXPVerifier.h) and its Objective-C
	facade (OOOXPVerifier+ObjCBridge.h): bead oo-tsa4, the last class of the OXPVerifier hierarchy
	exemplar (proposed ADR-0056 and its amendments oo-cwz, oo-up4b, oo-94qk).

	The verifier reaches the resource manager, the cache manager, the game controller and the log
	handler, so the test links every game object but main's (tests/unit/core/meson.build entry
	['*'], amendment oo-44gg) and defines gDebugFlags. The user's directories and the game folder
	are a scratch folder (amendment oo-rmd7 item 4) holding the verifier's own configuration,
	Resources/Config/verifyOXP.plist, which names the test's stages (Objective-C subclasses of the
	stage facade, as OOModelVerifierStage still is); the stages record what the verifier asks of
	them. Opening the log at the end is switched off in the defaults.

	It is driven as the game drives it, through +runVerificationIfRequested with -verify-oxp on
	the command line: no request, a request without a path, a missing path, a file. Then a run:
	registration (unknown, excluded, nameless and same-named classes; a stage registered while
	another answers its dependents; registration refused once it closes), dependency resolution
	(order, reverse dependencies, an unresolved dependency, a loop), running (a stage that should
	not run, an exception in a stage), and what a stage reads from the verifier (path, display
	name, configuration, other stages by name). The expectations were written against the
	Objective-C class and run on it first.

	Bead oo-9ht.4 deleted the stage facade, so a stage can no longer be an Objective-C class that
	the verifier makes from its name: the test's stages became C++ subclasses of OOOXPVerifierStage
	with the same names and answers, which the verifier makes by name through its test hook
	(OOOXPVerifierTestAccess, asked where the class lookup was), and the stages hand and compare the
	C++ stages with -registerStage: and -cxx_stageWithName: (ADR-0049, standing approval oo-9n5p9;
	no case or expectation changed). Run: bash tools/check-core-tests.sh test_OOOXPVerifier
*/

#import "OOOXPVerifier.h"
#import "OOOXPVerifierStage.h"
#include "oofnd/FileSystem.hpp"
#include "oofnd/Defaults.hpp"
#include "oofnd/Process.hpp"
#include "oofnd/objc/OOException.h"
#include "oo_test.hpp"

#include <cstdlib>
#include <filesystem>
#include <map>
#include <process.h>
#include <string>
#include <vector>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


/*	The verifier makes the stages verifyOXP.plist names; a test's stage by its class name through
	this hook (it made an Objective-C stage class from its name until bead oo-9ht.4).
*/
struct OOOXPVerifierTestAccess
{
	static void SetStageMaker(oo::Ref<OOOXPVerifierStage> (*maker)(const std::string &name))
	{
		cxx::OOOXPVerifier::sTestStageMaker = maker;
	}
};


namespace {

namespace stdfs = std::filesystem;

stdfs::path sRoot;
std::vector<std::string> gEvents;

oo::Ref<OOOXPVerifierStage> MakeTestStage(const std::string &name);	// with the test's stages, below

// What a stage read from the verifier during its run.
struct VerifierView
{
	bool									seen = false;
	std::optional<std::string>				path, displayName, string, number, notAString;
	oo::PList								value, array, dictionary, notAnArray, notADictionary, missing;
	std::optional<std::vector<std::string>>	set, notASet;
	bool									foundA = false, foundNothing = false;
};
VerifierView gView;


void WriteText(const stdfs::path &path, const std::string &text)
{
	stdfs::create_directories(path.parent_path());
	OO_CHECK(oo::fs::writeFile(path, oo::Data(text.data(), text.size()), oo::fs::WriteMode::direct).has_value());
}


const char *const kConfiguration = R"(<?xml version="1.0" encoding="UTF-8"?>
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


// The scratch home and game folder with the verifier's configuration, made once.
void SetUp()
{
	if (!sRoot.empty())  return;
	sRoot = stdfs::temp_directory_path() / ("oo-test-oxpverifier-" + std::to_string(static_cast<unsigned long>(::_getpid())));
	stdfs::remove_all(sRoot);
	stdfs::create_directories(sRoot);
	OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
	stdfs::current_path(sRoot);
	WriteText(sRoot / "Resources" / "Info-gnustep.plist", "{ CFBundleVersion = \"9.9.9-test\"; }");
	WriteText(sRoot / "Resources" / "Config" / "verifyOXP.plist", kConfiguration);
	WriteText(sRoot / "Test.oxp" / "Config" / "script.js", "this.name = \"test\";\n");
	WriteText(sRoot / "a-file.txt", "not an OXP\n");
	// The verifier opens its log in the user's editor at the end unless told not to.
	oo::Defaults::standard().setObject("oxp-verifier-open-log", oo::PList(false));
	OOOXPVerifierTestAccess::SetStageMaker(MakeTestStage);
}


// +runVerificationIfRequested with this command line (after the program's name).
bool RunWithArguments(std::vector<std::string> arguments)
{
	arguments.insert(arguments.begin(), "core_test_OOOXPVerifier");
	std::vector<const char *> argv;
	for (const std::string &argument : arguments)  argv.push_back(argument.c_str());
	oo::process::setArguments(static_cast<int>(argv.size()), argv.data());
	gEvents.clear();
	return [OOOXPVerifier runVerificationIfRequested];
}

}	// namespace


// --- The test's stages ------------------------------------------------------------------------
// C++ subclasses of OOOXPVerifierStage (Objective-C subclasses of its facade until bead oo-9ht.4).

class OOTestStage : public OOOXPVerifierStage
{
public:
	std::optional<std::string> name() override	{ return std::nullopt; }
	void run() override
	{
		gEvents.push_back("run " + name().value_or("(null)"));
	}
};

#define TEST_STAGE(cls, stageName)  class cls : public OOTestStage { public:  std::optional<std::string> name() override { return std::string(stageName); }
#define DEPENDS_ON(...)  std::optional<std::vector<std::string>> dependencies() override { return std::vector<std::string>{ __VA_ARGS__ }; }
#define DEPENDENTS(...)  std::optional<std::vector<std::string>> dependents() override { return std::vector<std::string>{ __VA_ARGS__ }; }

TEST_STAGE(OOTestStageB, "B")  DEPENDS_ON("A")  };
TEST_STAGE(OOTestStageC, "C")  DEPENDS_ON("Missing")  };
TEST_STAGE(OOTestStageD, "D")  DEPENDENTS("A", "Nowhere")  };
TEST_STAGE(OOTestStageE, "E")  bool shouldRun() override { gEvents.push_back("should E"); return false; }  };
TEST_STAGE(OOTestStageF, "F")  DEPENDS_ON("E")  };
TEST_STAGE(OOTestStageH, "H")  DEPENDS_ON("G")  };
TEST_STAGE(OOTestStageI, "I")  DEPENDS_ON("J")  };
TEST_STAGE(OOTestStageJ, "J")  DEPENDS_ON("I")  };
TEST_STAGE(OOTestStageX, "X")  };
TEST_STAGE(OOTestStageDup1, "Dup")  void run() override { gEvents.push_back("run Dup1"); }  };
TEST_STAGE(OOTestStageDup2, "Dup")  void run() override { gEvents.push_back("run Dup2"); }  };
TEST_STAGE(OOTestStageSub, "Sub")  };
TEST_STAGE(OOTestStageLate, "Late")  };

class OOTestStageNameless : public OOTestStage {};


// A reads the verifier while it runs.
TEST_STAGE(OOTestStageA, "A")
void run() override
{
	OOTestStage::run();
	OOOXPVerifier *verifier = this->verifier();
	gView.seen = (verifier != nil);
	gView.path = [verifier cxx_oxpPath];
	gView.displayName = [verifier cxx_oxpDisplayName];
	gView.value = [verifier configurationValueForKey:"aNumber"];
	gView.missing = [verifier configurationValueForKey:"noSuchKey"];
	gView.array = [verifier cxx_configurationArrayForKey:"anArray"];
	gView.notAnArray = [verifier cxx_configurationArrayForKey:"aString"];
	gView.dictionary = [verifier cxx_configurationDictionaryForKey:"aDictionary"];
	gView.notADictionary = [verifier cxx_configurationDictionaryForKey:"anArray"];
	gView.string = [verifier cxx_configurationStringForKey:"aString"];
	gView.number = [verifier cxx_configurationStringForKey:"aNumber"];
	gView.notAString = [verifier cxx_configurationStringForKey:"notAString"];
	gView.set = [verifier cxx_configurationSetForKey:"anArray"];
	gView.notASet = [verifier cxx_configurationSetForKey:"aDictionary"];
	gView.foundA = ([verifier cxx_stageWithName:"A"] == this);
	gView.foundNothing = ([verifier cxx_stageWithName:"Missing"] == nullptr);
}
};


// G raises while it runs.
TEST_STAGE(OOTestStageG, "G")
void run() override
{
	OOTestStage::run();
	[OOException raise:"OOTestException" format:"%s", "G fails"];
}
};


// K registers a substage when asked for its dependents, as the verifier allows.
TEST_STAGE(OOTestStageK, "K")
std::optional<std::vector<std::string>> dependents() override
{
	const oo::Ref<OOTestStageSub> sub = oo::makeRef<OOTestStageSub>();
	[verifier() registerStage:sub.get()];
	return std::nullopt;
}
};


// L registers a stage while it runs, which the verifier refuses.
TEST_STAGE(OOTestStageL, "L")
void run() override
{
	OOTestStage::run();
	const oo::Ref<OOTestStageLate> late = oo::makeRef<OOTestStageLate>();
	[verifier() registerStage:late.get()];
	gEvents.push_back([verifier() cxx_stageWithName:"Late"] == nullptr ? "Late refused" : "Late registered");
}
};


// The stages the verifier makes by name through the test hook.
namespace {

template <class Stage>
oo::Ref<OOOXPVerifierStage> Make()
{
	return oo::Ref<OOOXPVerifierStage>(oo::makeRef<Stage>());
}


oo::Ref<OOOXPVerifierStage> MakeTestStage(const std::string &name)
{
	static const std::map<std::string, oo::Ref<OOOXPVerifierStage> (*)()> makers = {
		{ "OOTestStageA", Make<OOTestStageA> }, { "OOTestStageB", Make<OOTestStageB> },
		{ "OOTestStageC", Make<OOTestStageC> }, { "OOTestStageD", Make<OOTestStageD> },
		{ "OOTestStageE", Make<OOTestStageE> }, { "OOTestStageF", Make<OOTestStageF> },
		{ "OOTestStageG", Make<OOTestStageG> }, { "OOTestStageH", Make<OOTestStageH> },
		{ "OOTestStageI", Make<OOTestStageI> }, { "OOTestStageJ", Make<OOTestStageJ> },
		{ "OOTestStageK", Make<OOTestStageK> }, { "OOTestStageL", Make<OOTestStageL> },
		{ "OOTestStageX", Make<OOTestStageX> }, { "OOTestStageNameless", Make<OOTestStageNameless> },
		{ "OOTestStageDup1", Make<OOTestStageDup1> }, { "OOTestStageDup2", Make<OOTestStageDup2> },
		{ "OOTestStageSub", Make<OOTestStageSub> }, { "OOTestStageLate", Make<OOTestStageLate> },
	};
	const auto found = makers.find(name);
	return found != makers.end() ? found->second() : nullptr;
}

}	// namespace


// --- Tests ------------------------------------------------------------------------------------

OO_TEST(noRequest)
{
	SetUp();
	@autoreleasepool
	{
		OO_CHECK(!RunWithArguments({}));
		OO_CHECK(!RunWithArguments({ "-load", "Test.oxp" }));
		OO_CHECK(gEvents.empty());
	}
}


// -verify-oxp or --verify-oxp is answered YES even when there is nothing to verify.
OO_TEST(requestWithoutAnOXP)
{
	SetUp();
	@autoreleasepool
	{
		OO_CHECK(RunWithArguments({ "-verify-oxp" }));
		OO_CHECK(RunWithArguments({ "--verify-oxp", "NoSuch.oxp" }));
		OO_CHECK(RunWithArguments({ "-verify-oxp", "a-file.txt" }));
		OO_CHECK(gEvents.empty());
	}
}


OO_TEST(verification)
{
	SetUp();
	@autoreleasepool
	{
		const std::string path = (sRoot / "Test.oxp").generic_string();
		OO_CHECK(RunWithArguments({ "-verify-oxp", path }));

		// Registration in the configuration's (sorted, distinct) order, X excluded, the unknown class,
		// the nameless stage and the second "Dup" refused, Sub added by K. Resolution drops C
		// (unresolved) and the I/J loop; D runs before A (its dependent); E is asked and skipped, and
		// F (after E) still runs; G raises and H (after G) still runs; L's late registration is refused.
		const std::vector<std::string> expected = {
			"run D", "run A", "run B", "run Dup1", "should E", "run F", "run G", "run H", "run K",
			"run L", "Late refused", "run Sub",
		};
		OO_CHECK(gEvents == expected);
		if (gEvents != expected)
		{
			for (const std::string &event : gEvents)  std::printf("  event: %s\n", event.c_str());
		}

		OO_CHECK(gView.seen);
		OO_CHECK(gView.path == std::optional<std::string>(path));
		OO_CHECK(gView.displayName == std::optional<std::string>("Test.oxp"));
		OO_CHECK(gView.value.isNumber() && gView.value.int64Value() == 42);
		OO_CHECK(gView.missing.isNull());
		OO_CHECK(gView.array.isArray() && gView.array.count() == 4);
		OO_CHECK(gView.notAnArray.isNull());
		OO_CHECK(gView.dictionary.isDict() && gView.dictionary.get<std::string>("key") == "value");
		OO_CHECK(gView.notADictionary.isNull());
		OO_CHECK(gView.string == std::optional<std::string>("text"));
		OO_CHECK(gView.number == std::optional<std::string>("42"));
		OO_CHECK(!gView.notAString.has_value());
		OO_CHECK(gView.set == std::optional<std::vector<std::string>>(std::vector<std::string>{ "a", "b" }));
		OO_CHECK(!gView.notASet.has_value());
		OO_CHECK(gView.foundA);
		OO_CHECK(gView.foundNothing);
	}
}


OO_TEST_MAIN()
