/*	test_OOCheckPListSyntaxVerifierStage.mm
	Unit tests for OOCheckPListSyntaxVerifierStage.h/.mm (bead oo-li7k; proposed ADR-0056
	Amendment 1 and amendment oo-up4b item 6): the stage that checks the top-level type of each
	known Config plist, a leaf of OOFileHandlingVerifierStage.

	What the stage computed before the conversion is pinned: its name and neighbours (the
	intermediate class's), that it always runs, and what it logs for each plist verifyOXP.plist
	knows (knownFiles.Config): the files it checks, an array or dictionary where the other was
	expected (both worded "should be an array"), neither, and nothing for a missing, unparseable or
	script file. Then the crossing: the converted stage is global, so Objective-C sees it as an
	OOOXPVerifierStage.
	Bead oo-9ht.4 deleted the stage facade: the verifier registers and answers the C++ stage
	itself, so the facade case asks the stage (its description through description()), and the
	checks that pinned only the facade crossing (one live facade, oo::ToObjC/oo::ToCxx, its class,
	oo::AsObjCStage) were retired with it (ADR-0049, standing approval oo-9n5p9).
	Run: bash tools/check-core-tests.sh
*/

#import "OOCheckPListSyntaxVerifierStage.h"
#import "OOOXPVerifierStage.h"
#import "OODescription.h"

#include "oofnd/Log.hpp"
#include "oofnd/PListParsing.hpp"
#include "oo_test.hpp"

#include <filesystem>
#include <fstream>


/*	The game's OOLogging.mm reaches the resource manager, so it is not linked; the base calls
	this one function of it (a subclass responsibility).
*/
void OOLogGenericSubclassResponsibilityForFunction(const char *inFunction)
{
	(void)inFunction;
}


/*	The verifier and the resource manager are not linked either (they reach the whole game). The
	stages talk to the verifier through its interface only, so the test is the verifier (as in
	test_OOFileScannerVerifierStage.mm). The resource manager has no built-in files here.
*/
#include "OOOXPVerifierTestDouble.h"


@interface ResourceManager: OOObject

+ (std::optional<std::string>) cxx_pathForFileNamed:(const std::string &)fileName inFolder:(const std::optional<std::string> &)folderName;

@end


@implementation ResourceManager

+ (std::optional<std::string>) cxx_pathForFileNamed:(const std::string &)fileName inFolder:(const std::optional<std::string> &)folderName
{
	(void)fileName;
	(void)folderName;
	return std::nullopt;
}

@end


namespace {

const char * const kConfiguration =
	"{"
	"	knownRootDirectories = (\"Config\");"
	"	knownFiles ="
	"	{"
	"		Config = (\"array.plist\", \"dict.plist\", \"wrongArray.plist\", \"wrongDict.plist\", \"string.plist\", \"bad.plist\", \"missing.plist\", \"script.js\");"
	"		ConfigArrays = (\"array.plist\", \"missing.plist\");"
	"		ConfigDictionaries = (\"dict.plist\", \"string.plist\");"
	"	};"
	"}";


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


void WriteFile(const std::filesystem::path &path, const char *contents)
{
	std::filesystem::create_directories(path.parent_path());
	std::ofstream(path, std::ios::binary) << contents;
}


// The scanner, registered with the verifier and run over its OXP, as the verifier runs it first.
void RunScanner(cxx::OOOXPVerifier *verifier)
{
	OOFileScannerVerifierStage::nameForDependencyForVerifier(verifier);
	verifier->stageWithName(OOFileScannerVerifierStage::kName)->run();	// was -fileScannerStage (bead oo-9ht.7); the C++ stage since oo-9ht.4
}


const std::vector<std::string> kScannerName = { "Scanning files" };
const std::vector<std::string> kUnusedName = { "Checking for unused files" };

const std::filesystem::path kBase = std::filesystem::current_path() / "test_OOCheckPListSyntaxVerifierStage.oxp";


// An OXP with the given Config files (name, contents), and its verifier with the scanner run over it.
cxx::OOOXPVerifier *MakeVerifier(std::initializer_list<std::pair<const char *, const char *>> files)
{
	std::filesystem::remove_all(kBase);
	std::filesystem::create_directories(kBase);
	for (const auto &[name, contents] : files)  WriteFile(kBase / "Config" / name, contents);
	cxx::OOOXPVerifier *verifier = OOOXPVerifierTestAccess::Make(kBase.generic_string(), kConfiguration);
	RunScanner(verifier);
	StartLog();
	return verifier;
}

}	// namespace


OO_TEST(nameAndNeighbours)
{
	@autoreleasepool
	{
		const oo::Ref<OOCheckPListSyntaxVerifierStage> stage = oo::makeRef<OOCheckPListSyntaxVerifierStage>();
		stage->setVerifier(MakeVerifier({}));
		OO_CHECK(stage->name() == std::optional<std::string>("Checking plist well-formedness"));
		OO_CHECK(stage->dependencies() == kScannerName);
		OO_CHECK(stage->dependents() == kUnusedName);
		OO_CHECK(stage->shouldRun());	// always
		stage->run();
		OO_CHECK(gLog.empty());	// no Config files
	}
	std::filesystem::remove_all(kBase);
}


OO_TEST(checksEachKnownPList)
{
	@autoreleasepool
	{
		const oo::Ref<OOCheckPListSyntaxVerifierStage> stage = oo::makeRef<OOCheckPListSyntaxVerifierStage>();
		stage->setVerifier(MakeVerifier({
			{ "array.plist", "( 1, 2 )" },
			{ "dict.plist", "{ a = 1; }" },
			{ "wrongArray.plist", "( 1 )" },
			{ "wrongDict.plist", "{ a = 1; }" },
			{ "string.plist", "\"text\"" },
			{ "bad.plist", "{ a = " },
			{ "script.js", "( 1 )" },
			{ "unknown.plist", "\"text\"" },
		}));
		gLog.clear();	// the scanner's own findings
		stage->run();

		// Each known file that exists is announced, in the order of knownFiles.Config; the script is skipped.
		OO_CHECK(LogLinesContaining("Checking ") == 6);
		for (const char *name : { "array.plist", "dict.plist", "wrongArray.plist", "wrongDict.plist", "string.plist", "bad.plist" })
		{
			OO_CHECK(LogLinesContaining(std::string("Checking ") + name) == 1);
		}
		OO_CHECK(LogLinesContaining("script.js") == 0 && LogLinesContaining("missing.plist") == 0 && LogLinesContaining("unknown.plist") == 0);

		// The wrong kinds (the dictionary's message says "array" too), and neither.
		OO_CHECK(LogLinesContaining("wrongArray.plist should be an array but isn't.") == 1);
		OO_CHECK(LogLinesContaining("wrongDict.plist should be an array but isn't.") == 1);
		OO_CHECK(LogLinesContaining("string.plist is neither an array nor a dictionary.") == 1);
		OO_CHECK(LogLinesContaining("array.plist should") == 0 && LogLinesContaining("dict.plist should") == 0 && LogLinesContaining("\"dict.plist\"") == 0);

		// An unparseable plist: the scanner's parse error, nothing from the stage.
		OO_CHECK(LogLinesContaining("bad.plist should") == 0 && LogLinesContaining("bad.plist is") == 0);
		OO_CHECK(LogLinesContaining("Could not interpret property list Config/bad.plist.") == 1);
		OO_CHECK(gLog.size() == 11);	// 6 announced, 3 wrong, 2 lines of parse error

		// In order: each file's findings follow its announcement.
		OO_CHECK(gLog[0] == "Checking array.plist" && gLog[2] == "Checking wrongArray.plist" && gLog[3] == "wrongArray.plist should be an array but isn't.");
		OO_CHECK(gLog[8] == "Checking bad.plist");
	}
	std::filesystem::remove_all(kBase);
}


// The converted stage is global: the verifier registers it and finds it by name (it held its
// OOOXPVerifierStage facade until bead oo-9ht.4), and it describes itself with its class's name.
OO_TEST(facade)
{
	@autoreleasepool
	{
		cxx::OOOXPVerifier *verifier = MakeVerifier({});
		const oo::Ref<OOCheckPListSyntaxVerifierStage> stage = oo::makeRef<OOCheckPListSyntaxVerifierStage>();
		OO_CHECK(stage->description().starts_with("<OOCheckPListSyntaxVerifierStage 0x"));

		verifier->registerStage(stage.get());
		OO_CHECK(verifier->stageWithName("Checking plist well-formedness") == stage.get());
		OO_CHECK(stage->name() == std::optional<std::string>("Checking plist well-formedness"));
		OO_CHECK(stage->dependencies() == kScannerName);
		OO_CHECK(stage->dependents() == kUnusedName);
	}
}

OO_TEST_MAIN()
