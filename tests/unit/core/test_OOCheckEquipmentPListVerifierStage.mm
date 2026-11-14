/*	test_OOCheckEquipmentPListVerifierStage.mm
	Unit tests for OOCheckEquipmentPListVerifierStage.h/.mm (bead oo-z2wr; proposed ADR-0056
	Amendment 1 and amendment oo-up4b item 6): the stage that checks equipment.plist, a leaf of
	OOFileHandlingVerifierStage.

	What the stage computed before the conversion is pinned: its name and neighbours (the
	intermediate class's), that it runs when the OXP has an equipment.plist, and what it logs for
	each entry: not an array, too few or too many elements, a tech level or price that is not a
	non-negative integer, descriptions and key that are not strings, and extra information that is
	not a dictionary, each entry named by its number and key. Then the crossing: the converted stage
	is global, so Objective-C sees it as an OOOXPVerifierStage.
	Run: bash tools/check-core-tests.sh
*/

#import "OOCheckEquipmentPListVerifierStage.h"
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

const std::filesystem::path kBase = std::filesystem::current_path() / "test_OOCheckEquipmentPListVerifierStage.oxp";


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
		const oo::Ref<OOCheckEquipmentPListVerifierStage> stage = oo::makeRef<OOCheckEquipmentPListVerifierStage>();
		stage->setVerifier(MakeVerifier({}));
		OO_CHECK(stage->name() == std::optional<std::string>("Checking equipment.plist"));
		OO_CHECK(stage->dependencies() == kScannerName);
		OO_CHECK(stage->dependents() == kUnusedName);
		OO_CHECK(!stage->shouldRun());
		stage->run();
		OO_CHECK(gLog.empty());

		stage->setVerifier(MakeVerifier({ { "equipment.plist", "{ a = b; }" } }));
		OO_CHECK(stage->shouldRun());
		stage->run();
		OO_CHECK(gLog.size() == 1 && LogLinesContaining("***** ERROR: equipment.plist is not an array.") == 1);
	}
	std::filesystem::remove_all(kBase);
}


OO_TEST(checksEachEntry)
{
	@autoreleasepool
	{
		const oo::Ref<OOCheckEquipmentPListVerifierStage> stage = oo::makeRef<OOCheckEquipmentPListVerifierStage>();
		stage->setVerifier(MakeVerifier({ { "equipment.plist",
			"("
			"	notAnArray,"
			"	( 1, 2 ),"
			"	( 1, 100, Short, EQ_GOOD, Long ),"
			"	( 1, 100, Short, EQ_LONG, Long, { a = b; }, extra ),"
			"	( \"-1\", price, ( s ), ( k ), ( l ) ),"
			"	( 2, 5, Short, EQ_EXTRA, Long, notADict ),"
			"	( 3, 7, Short, EQ_NUMBERS, 42 ),"
			"	( 1, 2, 3, 4 )"
			")" } }));
		stage->run();

		OO_CHECK(LogLinesContaining("***** ERROR: equipment.plist entry 1 of equipment.plist is not an array.") == 1);
		OO_CHECK(LogLinesContaining("***** ERROR: equipment.plist entry 2 has too few elements (2, should be 5 or 6).") == 1);
		OO_CHECK(LogLinesContaining("EQ_GOOD") == 0);
		OO_CHECK(LogLinesContaining("----- WARNING: equipment.plist entry 4 (\"EQ_LONG\") has too many elements (7, should be 5 or 6).") == 1);
		OO_CHECK(LogLinesContaining("EQ_LONG") == 1);	// its extra information is a dictionary

		// Entry 5: elements of the wrong type; it has no key to be named by.
		OO_CHECK(LogLinesContaining("***** ERROR: tech level for entry 5 of equipment.plist is not a positive integer.") == 1);
		OO_CHECK(LogLinesContaining("price for entry 5") == 0);	// a word reads as the number 0, as -intValue did
		OO_CHECK(LogLinesContaining("***** ERROR: short description for entry 5 of equipment.plist is not a string.") == 1);
		OO_CHECK(LogLinesContaining("***** ERROR: key for entry 5 of equipment.plist is not a string.") == 1);
		OO_CHECK(LogLinesContaining("***** ERROR: long description for entry 5 of equipment.plist is not a string.") == 1);

		OO_CHECK(LogLinesContaining("***** ERROR: equipment.plist entry 6 (\"EQ_EXTRA\")'s extra information dictionary is not a dictionary.") == 1);
		OO_CHECK(LogLinesContaining("EQ_NUMBERS") == 0);	// a number where a string is expected is its text
		OO_CHECK(LogLinesContaining("***** ERROR: equipment.plist entry 8 (\"4\") has too few elements (4, should be 5 or 6).") == 1);
		OO_CHECK(gLog.size() == 9);
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
		const oo::Ref<OOCheckEquipmentPListVerifierStage> stage = oo::makeRef<OOCheckEquipmentPListVerifierStage>();
		OOOXPVerifierStage *facade = oo::ToObjC(stage.get());
		OO_CHECK(facade != nil && facade == oo::ToObjC(stage.get()) && oo::ToCxx(facade) == stage.get());
		OO_CHECK([facade class] == [OOOXPVerifierStage class]);
		OO_CHECK(oo::AsObjCStage(stage.get()) == nullptr);
		OO_CHECK(oo::DescriptionOf(facade).starts_with("<OOCheckEquipmentPListVerifierStage 0x"));

		[verifier registerStage:facade];
		OO_CHECK([verifier cxx_stageWithName:"Checking equipment.plist"] == facade);
		OO_CHECK([facade cxx_name] == std::optional<std::string>("Checking equipment.plist"));
		OO_CHECK([facade cxx_dependencies] == kScannerName);
		OO_CHECK([facade dependents] == kUnusedName);
		OO_CHECK([facade shouldRun] == stage->shouldRun());
	}
}

OO_TEST_MAIN()
