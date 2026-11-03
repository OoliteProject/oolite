/*	test_OOCheckJSSyntaxVerifierStage.mm
	Unit tests for OOCheckJSSyntaxVerifierStage.h/.mm (bead oo-kdnm; proposed ADR-0056 Amendment 1
	and amendment oo-up4b item 6): the stage that compiles an OXP's scripts, a leaf of
	OOFileHandlingVerifierStage.

	What the stage computed before the conversion is pinned: its name and neighbours (the
	intermediate class's), when it runs (a non-empty Scripts folder, or Config/script.js), and which
	files it hands to the script loader (.js and .es in Scripts, in any case, then Config/script.js),
	with error locations switched on first. The script loader and the engine reach the whole game,
	so the test replaces them with classes that record what they are asked. Then the crossing: the
	converted stage is global, so Objective-C sees it as an OOOXPVerifierStage.
	Run: bash tools/check-core-tests.sh
*/

#import "OOCheckJSSyntaxVerifierStage.h"
#import "OOOXPVerifierStageInternal.h"
#import "OODescription.h"

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


// The engine and the script loader (OOJavaScriptEngine.mm and OOJSScript.mm reach the whole game).
namespace {

int gShowErrorLocations = 0;				// -setShowErrorLocations:YES calls
std::vector<std::string> gScriptPaths;		// +scriptWithPath:properties:, in order

}	// namespace


@interface OOJavaScriptEngine: OOObject

+ (OOJavaScriptEngine *) sharedEngine;
- (void) setShowErrorLocations:(BOOL)value;

@end


@implementation OOJavaScriptEngine

+ (OOJavaScriptEngine *) sharedEngine
{
	static OOJavaScriptEngine *engine = [[OOJavaScriptEngine alloc] init];
	return engine;
}


- (void) setShowErrorLocations:(BOOL)value
{
	if (value)  gShowErrorLocations++;
}

@end


@interface OOScript: OOObject
@end


@implementation OOScript
@end


@interface OOJSScript: OOScript

+ (id) scriptWithPath:(const std::optional<std::string> &)path properties:(const oo::PList &)properties;

@end


@implementation OOJSScript

+ (id) scriptWithPath:(const std::optional<std::string> &)path properties:(const oo::PList &)properties
{
	gScriptPaths.push_back(path.value_or("(nil)") + (properties.isNull() ? "" : " with properties"));
	return nil;
}

@end


namespace {

const char * const kConfiguration =
	"{"
	"	knownRootDirectories = (\"Config\", \"Scripts\");"
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

const std::filesystem::path kBase = std::filesystem::current_path() / "test_OOCheckJSSyntaxVerifierStage.oxp";


// An OXP with the given files (relative paths), and its verifier with the scanner run over it.
OOOXPVerifier *MakeVerifier(std::initializer_list<const char *> files)
{
	std::filesystem::remove_all(kBase);
	std::filesystem::create_directories(kBase);
	for (const char *file : files)  WriteFile(kBase / file, "// script");
	OOOXPVerifier *verifier = [[[OOOXPVerifier alloc] initWithPath:kBase.generic_string() configuration:kConfiguration] autorelease];
	RunScanner(verifier);
	gShowErrorLocations = 0;
	gScriptPaths.clear();
	return verifier;
}

}	// namespace


OO_TEST(nameAndNeighbours)
{
	@autoreleasepool
	{
		const oo::Ref<OOCheckJSSyntaxVerifierStage> stage = oo::makeRef<OOCheckJSSyntaxVerifierStage>();
		stage->setVerifier(MakeVerifier({}));
		OO_CHECK(stage->name() == std::optional<std::string>("Checking JS Script file syntax"));
		OO_CHECK(stage->dependencies() == kScannerName);
		OO_CHECK(stage->dependents() == kUnusedName);
	}
}


OO_TEST(runsWhenThereAreScripts)
{
	@autoreleasepool
	{
		const oo::Ref<OOCheckJSSyntaxVerifierStage> stage = oo::makeRef<OOCheckJSSyntaxVerifierStage>();
		stage->setVerifier(MakeVerifier({ "Config/shipdata.plist" }));
		OO_CHECK(!stage->shouldRun());
		stage->run();
		OO_CHECK(gShowErrorLocations == 0 && gScriptPaths.empty());	// nothing to do

		stage->setVerifier(MakeVerifier({ "Scripts/readme.txt" }));
		OO_CHECK(stage->shouldRun());	// any file in Scripts

		stage->setVerifier(MakeVerifier({ "Config/script.js" }));
		OO_CHECK(stage->shouldRun());

		stage->setVerifier(MakeVerifier({ "Config/Script.js" }));
		OO_CHECK(!stage->shouldRun());	// the Config listing is as on disk
	}
	std::filesystem::remove_all(kBase);
}


OO_TEST(compilesEachScript)
{
	@autoreleasepool
	{
		const oo::Ref<OOCheckJSSyntaxVerifierStage> stage = oo::makeRef<OOCheckJSSyntaxVerifierStage>();
		stage->setVerifier(MakeVerifier({ "Scripts/b.js", "Scripts/A.JS", "Scripts/c.es", "Scripts/notes.txt", "Scripts/noext", "Config/script.js" }));
		StartLog();
		stage->run();
		OO_CHECK(LogLinesContaining("ERROR") == 0 && LogLinesContaining("WARNING") == 0);	// the loader reports, not the stage
		OO_CHECK(gShowErrorLocations == 1);
		const std::string base = kBase.generic_string();
		OO_CHECK(gScriptPaths == (std::vector<std::string>{ base + "/Scripts/A.JS", base + "/Scripts/b.js", base + "/Scripts/c.es", base + "/Config/script.js" }));

		// Only the Config script.
		stage->setVerifier(MakeVerifier({ "Config/script.js" }));
		stage->run();
		OO_CHECK(gShowErrorLocations == 1);
		OO_CHECK(gScriptPaths == std::vector<std::string>{ base + "/Config/script.js" });
	}
	std::filesystem::remove_all(kBase);
}


// The converted stage is global: Objective-C (the verifier) sees it as an OOOXPVerifierStage, one
// facade per stage, whose methods answer as the stage does; its C++ part is the stage itself.
OO_TEST(facade)
{
	@autoreleasepool
	{
		OOOXPVerifier *verifier = MakeVerifier({ "Config/script.js" });
		const oo::Ref<OOCheckJSSyntaxVerifierStage> stage = oo::makeRef<OOCheckJSSyntaxVerifierStage>();
		OOOXPVerifierStage *facade = oo::ToObjC(stage.get());
		OO_CHECK(facade != nil && facade == oo::ToObjC(stage.get()) && oo::ToCxx(facade) == stage.get());
		OO_CHECK([facade class] == [OOOXPVerifierStage class]);
		OO_CHECK(oo::AsObjCStage(stage.get()) == nullptr);
		OO_CHECK(oo::DescriptionOf(facade).starts_with("<OOCheckJSSyntaxVerifierStage 0x"));

		[verifier registerStage:facade];
		OO_CHECK([verifier cxx_stageWithName:"Checking JS Script file syntax"] == facade);
		OO_CHECK([facade cxx_name] == std::optional<std::string>("Checking JS Script file syntax"));
		OO_CHECK([facade cxx_dependencies] == kScannerName);
		OO_CHECK([facade dependents] == kUnusedName);
		OO_CHECK([facade shouldRun] == stage->shouldRun());
	}
}

OO_TEST_MAIN()
