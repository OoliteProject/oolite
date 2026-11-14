/*	test_OOAIStateMachineVerifierStage.mm
	Unit tests for OOAIStateMachineVerifierStage.h/.mm (bead oo-94qk; proposed ADR-0056 Amendment 1
	and amendment oo-up4b item 6): the AI stage, a leaf of OOFileHandlingVerifierStage.

	What the stage computed before the conversion is pinned: its name and its neighbours (the
	intermediate class's), the AIs a ship names (found or not, each once), and the check of each
	AI against the whitelist (states that are not dictionaries, handlers that are not arrays,
	actions that are not strings, and the unpermitted methods, sorted case-insensitively). What it
	reports goes to the log, which the test captures. Then the crossing: the converted stage is
	global, so Objective-C sees it as an OOOXPVerifierStage (the verifier registers its facade, and
	the ship data stage finds it by name), and it reaches the scanner through
	the stage lookup by the scanner's name (the verifier's -fileScannerStage until bead oo-9ht.7).
	Bead oo-9ht.4 deleted the stage facade: the verifier registers and answers the C++ stage
	itself, so the facade case asks the stage (its description through description()), and the
	checks that pinned only the facade crossing (one live facade, oo::ToObjC/oo::ToCxx, its class,
	oo::AsObjCStage) were retired with it (ADR-0049, standing approval oo-9n5p9).
	Run: bash tools/check-core-tests.sh
*/

#import "OOAIStateMachineVerifierStage.h"
#import "OOOXPVerifierStage.h"
#import "OODescription.h"

#import "OOLogging.h"
#import "OOPListParsing.h"
#include "oofnd/Log.hpp"
#include "oofnd/PListParsing.hpp"
#include "oo_test.hpp"

#include <filesystem>
#include <fstream>
#include <sstream>


/*	The game's OOLogging.mm reaches the resource manager, so it is not linked; the base calls
	this one function of it (a subclass responsibility).
*/
void OOLogGenericSubclassResponsibilityForFunction(const char *inFunction)
{
	(void)inFunction;
}


// OOPListParsing.mm reaches the universe; the stage reads each AI with this one function of it.
oo::PList cxx_OOPropertyListFromFile(const std::string &path)
{
	std::ifstream file(path, std::ios::binary);
	if (!file)  return oo::PList();
	std::stringstream bytes;
	bytes << file.rdbuf();
	auto parsed = oo::parsePropertyListData(bytes.str());
	return parsed ? *parsed : oo::PList();
}


/*	The verifier and the resource manager are not linked either (they reach the whole game). The
	stages talk to the verifier through its interface only, so the test is the verifier (as in
	test_OOFileScannerVerifierStage.mm). The resource manager answers the whitelist and, for
	built-in files, one AI.
*/
#include "OOOXPVerifierTestDouble.h"


@interface ResourceManager: OOObject

+ (std::optional<std::string>) cxx_pathForFileNamed:(const std::string &)fileName inFolder:(const std::optional<std::string> &)folderName;
+ (oo::PList) cxx_whitelistDictionary;

@end


@implementation ResourceManager

+ (std::optional<std::string>) cxx_pathForFileNamed:(const std::string &)fileName inFolder:(const std::optional<std::string> &)folderName
{
	if (fileName != "builtinAI.plist")  return std::nullopt;
	return "builtin/" + folderName.value_or("") + "/" + fileName;
}


+ (oo::PList) cxx_whitelistDictionary
{
	return *oo::parsePropertyListData(
		"{"
		"	ai_methods = (\"setStateTo:\", exitAI);"
		"	ai_and_action_methods = (performIdle, 7);"
		"	ai_method_aliases = { performAlias = performIdle; };"
		"}");
}

@end


namespace {

const char * const kConfiguration =
	"{"
	"	knownRootDirectories = (\"AIs\", \"Config\");"
	"}";


void WriteFile(const std::filesystem::path &path, const char *contents)
{
	std::filesystem::create_directories(path.parent_path());
	std::ofstream(path, std::ios::binary) << contents;
}


// An OXP with a clean AI, one with every kind of error, and a file that is not a dictionary.
std::string MakeOXP()
{
	const std::filesystem::path base = std::filesystem::current_path() / "test_OOAIStateMachineVerifierStage.oxp";
	std::filesystem::remove_all(base);
	WriteFile(base / "AIs" / "goodAI.plist",
		"{ GLOBAL = { ENTER = (\"setStateTo: ATTACK\", performAlias); }; ATTACK = { EXIT = (\"  exitAI  \"); }; }");
	WriteFile(base / "AIs" / "badAI.plist",
		"{ GLOBAL = { ENTER = (\"zapTarget: now\", Beep, zapTarget, (3), performIdle); UPDATE = oops; }; BROKEN = broken; }");
	WriteFile(base / "AIs" / "listAI.plist", "( a, b )");
	WriteFile(base / "AIs" / "oneAI.plist", "{ GLOBAL = { ENTER = (fly); }; }");
	return base.generic_string();
}


cxx::OOOXPVerifier *MakeVerifier(const std::string &path)
{
	return OOOXPVerifierTestAccess::Make(path, kConfiguration);
}


// The log, as the stage writes it.
std::vector<std::string> gLog;


void Capture(std::string_view line)
{
	gLog.emplace_back(line);
}


void StartLog()
{
	oo::log::logger().setInitialized(true);
	oo::log::logger().setSink(&Capture);
	gLog.clear();
}


int LogLinesContaining(std::string_view text)
{
	int count = 0;
	for (const std::string &line : gLog)
	{
		if (line.find(text) != std::string::npos)  count++;
	}
	return count;
}


// The scanner, registered with the verifier and run over its OXP, as the verifier runs it first.
void RunScanner(cxx::OOOXPVerifier *verifier)
{
	OOFileScannerVerifierStage::nameForDependencyForVerifier(verifier);
	verifier->stageWithName(OOFileScannerVerifierStage::kName)->run();	// was -fileScannerStage (bead oo-9ht.7); the C++ stage since oo-9ht.4
}

const std::vector<std::string> kScannerName = { "Scanning files" };
const std::vector<std::string> kUnusedName = { "Checking for unused files" };

}	// namespace


OO_TEST(nameAndNeighbours)
{
	@autoreleasepool
	{
		cxx::OOOXPVerifier *verifier = MakeVerifier("");
		OO_CHECK(OOAIStateMachineVerifierStage::nameForReverseDependencyForVerifier(verifier) == "Validating AIs");

		const oo::Ref<OOAIStateMachineVerifierStage> stage = oo::makeRef<OOAIStateMachineVerifierStage>();
		stage->setVerifier(verifier);
		OO_CHECK(stage->name() == std::optional<std::string>("Validating AIs"));
		OO_CHECK(stage->dependencies() == kScannerName);
		OO_CHECK(stage->dependents() == kUnusedName);
		OO_CHECK(!stage->shouldRun());	// no ship named an AI
	}
}


OO_TEST(shipsNameAIs)
{
	@autoreleasepool
	{
		const std::string base = MakeOXP();
		cxx::OOOXPVerifier *verifier = MakeVerifier(base);
		RunScanner(verifier);
		const oo::Ref<OOAIStateMachineVerifierStage> stage = oo::makeRef<OOAIStateMachineVerifierStage>();
		stage->setVerifier(verifier);
		StartLog();

		// Found in the OXP or built in: nothing to say. In another case, the scanner's case warning.
		stage->stateMachineNamed("goodAI.plist", "ship one");
		stage->stateMachineNamed("builtinAI.plist", "ship one");
		OO_CHECK(gLog.empty());
		stage->stateMachineNamed("GOODAI.plist", "ship one");
		OO_CHECK(gLog.size() == 1 && LogLinesContaining("***** ERROR: case mismatch: request for file 'AIs/GOODAI.plist' referenced in shipdata.plist entry \"ship one\" resolved to 'AIs/goodAI.plist'.") == 1);
		OO_CHECK(stage->shouldRun());

		// Missing: one warning, naming the AI, the ship and the OXP; each name is checked once.
		stage->stateMachineNamed("missingAI.plist", "ship two");
		stage->stateMachineNamed("missingAI.plist", "ship three");
		OO_CHECK(LogLinesContaining("----- WARNING: AI state machine \"missingAI.plist\" referenced in shipdata.plist entry \"ship two\" could not be found in Test.oxp or in Oolite.") == 1);
		OO_CHECK(LogLinesContaining("ship three") == 0);

		std::filesystem::remove_all(base);
	}
}


OO_TEST(runChecksEachAIAgainstTheWhitelist)
{
	@autoreleasepool
	{
		const std::string base = MakeOXP();
		cxx::OOOXPVerifier *verifier = MakeVerifier(base);
		RunScanner(verifier);
		const oo::Ref<OOAIStateMachineVerifierStage> stage = oo::makeRef<OOAIStateMachineVerifierStage>();
		stage->setVerifier(verifier);
		for (const char *name : { "oneAI.plist", "goodAI.plist", "badAI.plist", "listAI.plist", "builtinAI.plist", "missingAI.plist" })
		{
			stage->stateMachineNamed(name, "a ship");
		}
		StartLog();
		stage->run();

		// Each AI read is announced (verifyOXP.verbose); a clean one (whitelisted methods and
		// aliases, arguments cut off, spaces trimmed) says nothing else.
		OO_CHECK(LogLinesContaining("- Validating AI \"goodAI.plist\".") == 1);
		OO_CHECK(LogLinesContaining("\"goodAI.plist\"") == 1);

		// Every kind of error in one AI; the unpermitted methods (the action up to its first space)
		// once each, sorted case-insensitively.
		OO_CHECK(LogLinesContaining("***** ERROR: state \"BROKEN\" in AI \"badAI.plist\" is not a dictionary.") == 1);
		OO_CHECK(LogLinesContaining("***** ERROR: handler \"UPDATE\" for state \"GLOBAL\" in AI \"badAI.plist\" is not an array, ignoring.") == 1);
		OO_CHECK(LogLinesContaining("***** ERROR: action 3 in handler \"ENTER\" for state \"GLOBAL\" in AI \"badAI.plist\" is not a string, ignoring.") == 1);
		OO_CHECK(LogLinesContaining("***** ERROR: the AI \"badAI.plist\" uses 3 unpermitted methods: Beep, zapTarget, zapTarget:") == 1);

		// One unpermitted method; a file that is not a dictionary; built-in and missing AIs are not read.
		OO_CHECK(LogLinesContaining("***** ERROR: the AI \"oneAI.plist\" uses 1 unpermitted method: fly") == 1);
		OO_CHECK(LogLinesContaining("***** ERROR: could not interpret \"" + base + "/AIs/listAI.plist\" as a dictionary.") == 1);
		OO_CHECK(LogLinesContaining("\"builtinAI.plist\"") == 1 && LogLinesContaining("\"missingAI.plist\"") == 1);	// announced only
		OO_CHECK(LogLinesContaining("ERROR") == 6);

		// An AI that returns early leaves the log indented (the indent is not undone): pinned as it was.
		// Three early returns (built-in, list, missing), then oneAI's own indent for its error.
		const size_t firstIndent = gLog.front().find_first_not_of(' ');
		OO_CHECK(gLog.front().substr(firstIndent).starts_with("- Validating AI \"badAI.plist\"."));
		OO_CHECK(gLog.back().find_first_not_of(' ') == firstIndent + 8);
		OO_CHECK(gLog.back().ends_with("***** ERROR: the AI \"oneAI.plist\" uses 1 unpermitted method: fly"));

		// The AIs are checked in case-insensitive order of their names.
		int one = -1, bad = -1;
		for (int i = 0; i < (int)gLog.size(); i++)
		{
			if (gLog[i].find("\"oneAI.plist\"") != std::string::npos)  one = i;
			if (gLog[i].find("\"badAI.plist\"") != std::string::npos && bad < 0)  bad = i;
		}
		OO_CHECK(bad >= 0 && one > bad);

		// A second run starts from a fresh whitelist and says the same again.
		const size_t lines = gLog.size();
		gLog.clear();
		stage->run();
		OO_CHECK(gLog.size() == lines);

		std::filesystem::remove_all(base);
	}
}


// The converted stage is global: the verifier (the ship data stage's holder) registers it and
// finds it by name (it held its OOOXPVerifierStage facade until bead oo-9ht.4).
OO_TEST(facade)
{
	@autoreleasepool
	{
		const std::string base = MakeOXP();
		cxx::OOOXPVerifier *verifier = MakeVerifier(base);
		RunScanner(verifier);
		const oo::Ref<OOAIStateMachineVerifierStage> stage = oo::makeRef<OOAIStateMachineVerifierStage>();

		// Registered as the verifier registers it, found again by name, as the ship data stage finds it.
		verifier->registerStage(stage.get());
		OO_CHECK(verifier->stageWithName("Validating AIs") == stage.get());
		OO_CHECK(static_cast<OOAIStateMachineVerifierStage *>(verifier->stageWithName("Validating AIs")) == stage.get());

		// The stage answers as its facade did.
		OO_CHECK(stage->name() == std::optional<std::string>("Validating AIs"));
		OO_CHECK(stage->dependencies() == kScannerName);
		OO_CHECK(stage->dependents() == kUnusedName);
		OO_CHECK(!stage->shouldRun());
		stage->stateMachineNamed("oneAI.plist", "a ship");
		OO_CHECK(stage->shouldRun());
		StartLog();
		stage->dependencyRegistrationComplete();
		stage->performRun();
		OO_CHECK(LogLinesContaining("***** ERROR: the AI \"oneAI.plist\" uses 1 unpermitted method: fly") == 1);
		OO_CHECK(stage->description().starts_with("<OOAIStateMachineVerifierStage 0x"));

		std::filesystem::remove_all(base);
	}
}

OO_TEST_MAIN()
