/*	test_OOCheckDemoShipsPListVerifierStage.mm
	Unit tests for OOCheckDemoShipsPListVerifierStage.h/.mm (bead oo-si5w; proposed ADR-0056
	Amendment 1 and amendment oo-up4b item 6): the stage that checks demoships.plist against
	shipdata.plist, a leaf of OOFileHandlingVerifierStage.

	What the stage computed before the conversion is pinned: its name and neighbours (the
	intermediate class's), that it runs when the OXP has a demoships.plist, and what it logs: a
	demoships.plist or shipdata.plist of the wrong type, and each entry that names no ship (or is
	not a string). Then the crossing: the converted stage is global, so Objective-C sees it as an
	OOOXPVerifierStage.
	Run: bash tools/check-core-tests.sh
*/

#import "OOCheckDemoShipsPListVerifierStage.h"
#import "OOOXPVerifierStageInternal.h"
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
void RunScanner(OOOXPVerifier *verifier)
{
	[OOFileScannerVerifierStage nameForDependencyForVerifier:verifier];
	[[verifier fileScannerStage] run];
}


const std::vector<std::string> kScannerName = { "Scanning files" };
const std::vector<std::string> kUnusedName = { "Checking for unused files" };

const std::filesystem::path kBase = std::filesystem::current_path() / "test_OOCheckDemoShipsPListVerifierStage.oxp";


// An OXP with the given Config files (name, contents), and its verifier with the scanner run over it.
OOOXPVerifier *MakeVerifier(std::initializer_list<std::pair<const char *, const char *>> files)
{
	std::filesystem::remove_all(kBase);
	std::filesystem::create_directories(kBase);
	for (const auto &[name, contents] : files)  WriteFile(kBase / "Config" / name, contents);
	OOOXPVerifier *verifier = [[[OOOXPVerifier alloc] initWithPath:kBase.generic_string() configuration:kConfiguration] autorelease];
	RunScanner(verifier);
	StartLog();
	return verifier;
}

}	// namespace


OO_TEST(nameAndNeighbours)
{
	@autoreleasepool
	{
		const oo::Ref<OOCheckDemoShipsPListVerifierStage> stage = oo::makeRef<OOCheckDemoShipsPListVerifierStage>();
		stage->setVerifier(MakeVerifier({}));
		OO_CHECK(stage->name() == std::optional<std::string>("Checking demoships.plist"));
		OO_CHECK(stage->dependencies() == kScannerName);
		OO_CHECK(stage->dependents() == kUnusedName);
		OO_CHECK(!stage->shouldRun());
		stage->run();
		OO_CHECK(gLog.empty());

		stage->setVerifier(MakeVerifier({ { "demoships.plist", "( a )" } }));
		OO_CHECK(stage->shouldRun());
		stage->run();
		OO_CHECK(gLog.empty());	// no shipdata.plist: nothing to check against
	}
	std::filesystem::remove_all(kBase);
}


OO_TEST(wrongTypes)
{
	@autoreleasepool
	{
		const oo::Ref<OOCheckDemoShipsPListVerifierStage> stage = oo::makeRef<OOCheckDemoShipsPListVerifierStage>();
		stage->setVerifier(MakeVerifier({ { "demoships.plist", "{ a = b; }" }, { "shipdata.plist", "{ a = {}; }" } }));
		stage->run();
		OO_CHECK(gLog.size() == 1 && LogLinesContaining("***** ERROR: demoships.plist is not an array.") == 1);

		stage->setVerifier(MakeVerifier({ { "demoships.plist", "( a )" }, { "shipdata.plist", "( a )" } }));
		stage->run();
		OO_CHECK(gLog.size() == 1 && LogLinesContaining("***** ERROR: shipdata.plist is not a dictionary.") == 1);

		stage->setVerifier(MakeVerifier({ { "demoships.plist", "( a" }, { "shipdata.plist", "{ a = {}; }" } }));
		gLog.clear();	// the scanner's own findings
		stage->run();
		OO_CHECK(LogLinesContaining("demoships.plist is") == 0 && LogLinesContaining("demoships.plist entry") == 0);	// unparseable: the scanner said so
	}
	std::filesystem::remove_all(kBase);
}


OO_TEST(entriesNameShips)
{
	@autoreleasepool
	{
		const oo::Ref<OOCheckDemoShipsPListVerifierStage> stage = oo::makeRef<OOCheckDemoShipsPListVerifierStage>();
		stage->setVerifier(MakeVerifier({
			{ "demoships.plist", "( cobra, \"no such ship\", viper, ( x ), Cobra )" },
			{ "shipdata.plist", "{ cobra = {}; viper = {}; }" },
		}));
		stage->run();
		OO_CHECK(gLog.size() == 3);
		OO_CHECK(LogLinesContaining("----- WARNING: demoships.plist entry \"no such ship\" not found in shipdata.plist.") == 1);
		OO_CHECK(LogLinesContaining("----- WARNING: demoships.plist entry \"Cobra\" not found in shipdata.plist.") == 1);	// case matters
		OO_CHECK(gLog.size() == 3 && gLog[1].find("----- WARNING: demoships.plist entry \"") != std::string::npos && gLog[1].find("\" not found in shipdata.plist.") != std::string::npos);	// the array, by its description
		OO_CHECK(LogLinesContaining("\"cobra\"") == 0 && LogLinesContaining("viper") == 0);
	}
	std::filesystem::remove_all(kBase);
}


// The converted stage is global: Objective-C (the verifier) sees it as an OOOXPVerifierStage, one
// facade per stage, whose methods answer as the stage does; its C++ part is the stage itself.
OO_TEST(facade)
{
	@autoreleasepool
	{
		OOOXPVerifier *verifier = MakeVerifier({});
		const oo::Ref<OOCheckDemoShipsPListVerifierStage> stage = oo::makeRef<OOCheckDemoShipsPListVerifierStage>();
		OOOXPVerifierStage *facade = oo::ToObjC(stage.get());
		OO_CHECK(facade != nil && facade == oo::ToObjC(stage.get()) && oo::ToCxx(facade) == stage.get());
		OO_CHECK([facade class] == [OOOXPVerifierStage class]);
		OO_CHECK(oo::AsObjCStage(stage.get()) == nullptr);
		OO_CHECK(oo::DescriptionOf(facade).starts_with("<OOCheckDemoShipsPListVerifierStage 0x"));

		[verifier registerStage:facade];
		OO_CHECK([verifier cxx_stageWithName:"Checking demoships.plist"] == facade);
		OO_CHECK([facade cxx_name] == std::optional<std::string>("Checking demoships.plist"));
		OO_CHECK([facade cxx_dependencies] == kScannerName);
		OO_CHECK([facade dependents] == kUnusedName);
		OO_CHECK([facade shouldRun] == stage->shouldRun());
	}
}

OO_TEST_MAIN()
