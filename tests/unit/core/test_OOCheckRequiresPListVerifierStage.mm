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
	Run: bash tools/check-core-tests.sh
*/

#import "OOCheckRequiresPListVerifierStage.h"
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
@interface OOOXPVerifier ()

- (id)initWithPath:(const std::string &)path configuration:(const char *)configuration;

@end


@implementation OOOXPVerifier

+ (BOOL)runVerificationIfRequested	{ return NO; }


- (id)initWithPath:(const std::string &)path configuration:(const char *)configuration
{
	self = [super init];
	if (self != nil)
	{
		_basePath = path;
		_verifierPList = *oo::parsePropertyListData(configuration);
		_openForRegistration = YES;
	}
	return self;
}


- (void)registerStage:(OOOXPVerifierStage *)stage
{
	_stagesByName[*[stage cxx_name]] = oo::ObjCRef<OOOXPVerifierStage *>(stage);
	[stage setVerifier:self];
}


- (std::optional<std::string>)cxx_oxpPath			{ return _basePath; }
- (std::optional<std::string>)cxx_oxpDisplayName	{ return "Test.oxp"; }


- (id)cxx_stageWithName:(const std::string &)name
{
	const auto found = _stagesByName.find(name);
	return found != _stagesByName.end() ? found->second.get() : nil;
}


- (oo::PList)configurationValueForKey:(const std::string &)key
{
	const oo::PList *value = _verifierPList.find(key);
	return value != nullptr ? *value : oo::PList();
}


- (oo::PList)cxx_configurationArrayForKey:(const std::string &)key
{
	const oo::PList *array = _verifierPList.get<oo::PList::Array>(key);
	return array != nullptr ? *array : oo::PList();
}


- (oo::PList)cxx_configurationDictionaryForKey:(const std::string &)key
{
	const oo::PList *dictionary = _verifierPList.get<oo::PList::Dict>(key);
	return dictionary != nullptr ? *dictionary : oo::PList();
}


- (std::optional<std::string>)cxx_configurationStringForKey:(const std::string &)key
{
	const oo::PList *value = _verifierPList.find(key);
	if (value == nullptr || !(value->isString() || value->isNumber()))  return std::nullopt;
	return _verifierPList.get<std::string>(key);
}


- (std::optional<std::vector<std::string>>)cxx_configurationSetForKey:(const std::string &)key
{
	const oo::PList *array = _verifierPList.get<oo::PList::Array>(key);
	if (array == nullptr)  return std::nullopt;

	std::set<std::string> strings;
	for (const oo::PList &element : *array->getIf<oo::PList::Array>())
	{
		if (const std::string *string = element.getIf<std::string>())  strings.insert(*string);
	}
	return std::vector<std::string>(strings.begin(), strings.end());
}

@end


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
void RunScanner(OOOXPVerifier *verifier)
{
	[OOFileScannerVerifierStage nameForDependencyForVerifier:verifier];
	[[verifier fileScannerStage] run];
}


const std::vector<std::string> kScannerName = { "Scanning files" };
const std::vector<std::string> kUnusedName = { "Checking for unused files" };

const std::filesystem::path kBase = std::filesystem::current_path() / "test_OOCheckRequiresPListVerifierStage.oxp";


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


// The converted stage is global: Objective-C (the verifier) sees it as an OOOXPVerifierStage, one
// facade per stage, whose methods answer as the stage does; its C++ part is the stage itself.
OO_TEST(facade)
{
	@autoreleasepool
	{
		OOOXPVerifier *verifier = MakeVerifier({});
		const oo::Ref<OOCheckRequiresPListVerifierStage> stage = oo::makeRef<OOCheckRequiresPListVerifierStage>();
		OOOXPVerifierStage *facade = oo::ToObjC(stage.get());
		OO_CHECK(facade != nil && facade == oo::ToObjC(stage.get()) && oo::ToCxx(facade) == stage.get());
		OO_CHECK([facade class] == [OOOXPVerifierStage class]);
		OO_CHECK(oo::AsObjCStage(stage.get()) == nullptr);
		OO_CHECK(oo::DescriptionOf(facade).starts_with("<OOCheckRequiresPListVerifierStage 0x"));

		[verifier registerStage:facade];
		OO_CHECK([verifier cxx_stageWithName:"Checking requires.plist"] == facade);
		OO_CHECK([facade cxx_name] == std::optional<std::string>("Checking requires.plist"));
		OO_CHECK([facade cxx_dependencies] == kScannerName);
		OO_CHECK([facade dependents] == kUnusedName);
		OO_CHECK([facade shouldRun] == stage->shouldRun());
	}
}

OO_TEST_MAIN()
