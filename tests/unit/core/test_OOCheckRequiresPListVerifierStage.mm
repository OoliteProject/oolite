/*	test_OOCheckRequiresPListVerifierStage.mm
	Unit tests for OOCheckRequiresPListVerifierStage.h/.mm (bead oo-uw42; proposed ADR-0056
	Amendment 1 and amendment oo-up4b item 6): the stage that checks requires.plist, a leaf of
	OOFileHandlingVerifierStage.

	What the stage computed before the conversion is pinned: its name and neighbours (the
	intermediate class's), that it runs when the OXP has a requires.plist, and what it logs: a
	requires.plist that is not a dictionary, unknown keys, versions that are not strings (a string
	that is no version number reads below every version), a range that is empty, and the comparison
	with Oolite's own version, which it
	reads from Resources/Info-gnustep.plist under the current directory (the test makes one there,
	and none). Then the crossing: the converted stage is global, so Objective-C sees it as an
	OOOXPVerifierStage.
	Bead oo-9ht.4 deleted the stage facade: the verifier registers and answers the C++ stage
	itself, so the facade case asks the stage (its description through description()), and the
	checks that pinned only the facade crossing (one live facade, oo::ToObjC/oo::ToCxx, its class,
	oo::AsObjCStage) were retired with it (ADR-0049, standing approval oo-9n5p9).
	Run: bash tools/check-core-tests.sh
*/

#import "OOCheckRequiresPListVerifierStage.h"
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
	"	requiresPListSupportedKeys = (version, max_version);"
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

const std::filesystem::path kBase = std::filesystem::current_path() / "test_OOCheckRequiresPListVerifierStage.oxp";


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


namespace {

// Runs the stage over a requires.plist, from a directory whose Resources/Info-gnustep.plist has
// CFBundleVersion <ooliteVersion> (none: no such file), as the game's working directory has.
void RunWith(const char *requiresPList, const char *ooliteVersion)
{
	const std::filesystem::path previous = std::filesystem::current_path();
	const std::filesystem::path game = previous / "test_OOCheckRequiresPListVerifierStage.game";
	std::filesystem::remove_all(game);
	std::filesystem::create_directories(game / "Resources");
	if (ooliteVersion != nullptr)
	{
		WriteFile(game / "Resources" / "Info-gnustep.plist", (std::string("{ CFBundleName = Oolite; CFBundleVersion = \"") + ooliteVersion + "\"; }").c_str());
	}

	const oo::Ref<OOCheckRequiresPListVerifierStage> stage = oo::makeRef<OOCheckRequiresPListVerifierStage>();
	stage->setVerifier(MakeVerifier({ { "requires.plist", requiresPList } }));
	std::filesystem::current_path(game);
	stage->run();
	std::filesystem::current_path(previous);
	std::filesystem::remove_all(game);
}

}	// namespace


OO_TEST(nameAndNeighbours)
{
	@autoreleasepool
	{
		const oo::Ref<OOCheckRequiresPListVerifierStage> stage = oo::makeRef<OOCheckRequiresPListVerifierStage>();
		stage->setVerifier(MakeVerifier({}));
		OO_CHECK(stage->name() == std::optional<std::string>("Checking requires.plist"));
		OO_CHECK(stage->dependencies() == kScannerName);
		OO_CHECK(stage->dependents() == kUnusedName);
		OO_CHECK(!stage->shouldRun());
		stage->run();
		OO_CHECK(gLog.empty());

		stage->setVerifier(MakeVerifier({ { "requires.plist", "{}" } }));
		OO_CHECK(stage->shouldRun());
		stage->run();
		OO_CHECK(gLog.empty());	// nothing required
	}
	std::filesystem::remove_all(kBase);
}


OO_TEST(shapeAndKeys)
{
	@autoreleasepool
	{
		RunWith("( version )", "1.90");
		OO_CHECK(gLog.size() == 1 && LogLinesContaining("***** ERROR: requires.plist is not a dictionary.") == 1);

		RunWith("{ zeta = 1; version = \"1.80\"; alpha = 2; }", "1.90");
		OO_CHECK(gLog.size() == 1 && LogLinesContaining("----- WARNING: requires.plist contains unknown keys. This OXP will not be loaded by this version of Oolite. Unknown keys are: alpha, zeta.") == 1);

		RunWith("{ version = ( 1 ); max_version = { a = b; }; }", "1.90");
		OO_CHECK(gLog.size() == 2);
		OO_CHECK(LogLinesContaining("***** ERROR: Value for 'version' is not a string.") == 1);
		OO_CHECK(LogLinesContaining("***** ERROR: Value for 'max_version' is not a string.") == 1);
	}
	std::filesystem::remove_all(kBase);
}


OO_TEST(versions)
{
	@autoreleasepool
	{
		// In range: nothing.
		RunWith("{ version = \"1.80\"; max_version = \"2.0\"; }", "1.90");
		OO_CHECK(gLog.empty());

		// Needs a newer Oolite, or an older one.
		RunWith("{ version = \"1.91\"; }", "1.90");
		OO_CHECK(gLog.size() == 1 && LogLinesContaining("----- WARNING: this OXP requires a newer version of Oolite (1.91) to work.") == 1);
		RunWith("{ max_version = \"1.89.9\"; }", "1.90");
		OO_CHECK(gLog.size() == 1 && LogLinesContaining("----- WARNING: this OXP requires an older version of Oolite (1.89.9) to work.") == 1);

		// A string that is not a version number reads as one below any other (no error is
		// logged): "abc" is below 1.90, and an empty max_version is too.
		RunWith("{ version = \"abc\"; max_version = \"\"; }", "1.90");
		OO_CHECK(gLog.size() == 1 && LogLinesContaining("----- WARNING: this OXP requires an older version of Oolite () to work.") == 1);

		// An empty range, whatever Oolite's version.
		RunWith("{ version = \"2.0\"; max_version = \"1.5\"; }", "1.90");
		OO_CHECK(LogLinesContaining("***** ERROR: this OXP's maximum version (1.5) is less than its minimum version (2.0).") == 1);
		OO_CHECK(gLog.size() == 3);	// and both comparisons with 1.90

		// No Info-gnustep.plist, or no version in it: Oolite's version reads the same way, below
		// any other, so the comparisons still run and the "could not find" warning is not reached.
		RunWith("{ version = \"2.0\"; max_version = \"1.5\"; }", nullptr);
		OO_CHECK(gLog.size() == 2);
		OO_CHECK(LogLinesContaining("----- WARNING: this OXP requires a newer version of Oolite (2.0) to work.") == 1);
		OO_CHECK(LogLinesContaining("this OXP's maximum version (1.5)") == 1);
		OO_CHECK(LogLinesContaining("could not find Oolite's version") == 0);
		RunWith("{ max_version = \"1.5\"; }", "not a version");
		OO_CHECK(gLog.empty());
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
		const oo::Ref<OOCheckRequiresPListVerifierStage> stage = oo::makeRef<OOCheckRequiresPListVerifierStage>();
		OO_CHECK(stage->description().starts_with("<OOCheckRequiresPListVerifierStage 0x"));

		verifier->registerStage(stage.get());
		OO_CHECK(verifier->stageWithName("Checking requires.plist") == stage.get());
		OO_CHECK(stage->name() == std::optional<std::string>("Checking requires.plist"));
		OO_CHECK(stage->dependencies() == kScannerName);
		OO_CHECK(stage->dependents() == kUnusedName);
	}
}

OO_TEST_MAIN()
