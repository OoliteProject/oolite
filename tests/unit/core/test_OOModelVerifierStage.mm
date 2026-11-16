/*	test_OOModelVerifierStage.mm
	Unit tests for OOModelVerifierStage.h/.mm (bead oo-5zby; proposed ADR-0056 Amendment 1 and
	amendments oo-up4b and oo-94qk): the model stage, a subclass of OOTextureHandlingStage.

	What the stage computed before the conversion is pinned: its name, that asking its name
	registers it (once), its neighbours (the intermediate class's), the models other stages name
	(found in the OXP or built in, or not; an empty name is not found; each model and context once),
	when it runs, and what it logs (a placeholder check of each model, in the order named). The
	verifier finds it again through -modelVerifierStage. Then the crossing: the converted stage is
	global, so Objective-C sees it as an OOOXPVerifierStage.
	Run: bash tools/check-core-tests.sh
*/

#import "OOModelVerifierStage.h"
#import "OOOXPVerifierStageInternal.h"
#import "OODescription.h"
#import "OOPixMap.h"

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
	test_OOFileScannerVerifierStage.mm). The resource manager has one built-in model.
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
	if (fileName != "builtin.dat")  return std::nullopt;
	return "builtin/" + folderName.value_or("") + "/" + fileName;
}

@end


// The texture stage (linked for the intermediate class) loads through these; no model here names a texture.
void OOFreePixMap(OOPixMap *ioPixMap)
{
	*ioPixMap = OOPixMap{};
}


@interface OOTextureLoader: OOObject
+ (id) cxx_loaderWithPath:(const std::optional<std::string> &)path options:(uint32_t)options;
@end


@implementation OOTextureLoader
+ (id) cxx_loaderWithPath:(const std::optional<std::string> &)path options:(uint32_t)options
{
	(void)path;
	(void)options;
	return nil;
}
@end


namespace {

const char * const kConfiguration =
	"{"
	"	knownRootDirectories = (\"Models\");"
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

const std::filesystem::path kBase = std::filesystem::current_path() / "test_OOModelVerifierStage.oxp";


// An OXP with the given files (path, contents), and its verifier with the scanner run over it.
OOOXPVerifier *MakeVerifier(std::initializer_list<std::pair<const char *, const char *>> files)
{
	std::filesystem::remove_all(kBase);
	std::filesystem::create_directories(kBase);
	for (const auto &[name, contents] : files)  WriteFile(kBase / name, contents);
	OOOXPVerifier *verifier = [[[OOOXPVerifier alloc] initWithPath:kBase.generic_string() configuration:kConfiguration] autorelease];
	RunScanner(verifier);
	StartLog();
	return verifier;
}

}	// namespace


OO_TEST(nameRegistersTheStage)
{
	@autoreleasepool
	{
		OOOXPVerifier *verifier = MakeVerifier({});
		OO_CHECK([verifier cxx_stageWithName:"Testing models"] == nil);
		OO_CHECK([verifier modelVerifierStage] == nil);
		OO_CHECK(OOModelVerifierStage::nameForReverseDependencyForVerifier(verifier) == "Testing models");
		OOOXPVerifierStage *registered = [verifier modelVerifierStage];
		OO_CHECK(registered != nil && [verifier cxx_stageWithName:"Testing models"] == registered);
		OO_CHECK(OOModelVerifierStage::nameForReverseDependencyForVerifier(verifier) == "Testing models");
		OO_CHECK([verifier modelVerifierStage] == registered);	// once

		OO_CHECK([registered cxx_name] == std::optional<std::string>("Testing models"));
		OO_CHECK([registered cxx_dependencies] == kScannerName);
		OO_CHECK([registered dependents] == (std::vector<std::string>{ "Checking for unused files", "Testing textures and images" }));
		OO_CHECK(![registered shouldRun]);
	}
	std::filesystem::remove_all(kBase);
}


OO_TEST(stagesNameModels)
{
	@autoreleasepool
	{
		OOOXPVerifier *verifier = MakeVerifier({ { "Models/ship.dat", "model" } });
		const oo::Ref<OOModelVerifierStage> stage = oo::makeRef<OOModelVerifierStage>();
		stage->setVerifier(verifier);
		const oo::PList materials = *oo::parsePropertyListData("{ a = b; }");

		OO_CHECK(!stage->modelNamed("", "a", "shipdata.plist", oo::PList(), oo::PList()));
		OO_CHECK(!stage->modelNamed("missing.dat", "a", "shipdata.plist", oo::PList(), oo::PList()));
		OO_CHECK(!stage->shouldRun() && gLog.empty());	// a missing model: the caller complains

		OO_CHECK(stage->modelNamed("ship.dat", "a", "shipdata.plist", materials, oo::PList()));
		OO_CHECK(stage->shouldRun());
		OO_CHECK(stage->modelNamed("ship.dat", "a", "shipdata.plist", materials, oo::PList()));	// again: once
		OO_CHECK(stage->modelNamed("ship.dat", "b", "shipdata.plist", oo::PList(), oo::PList()));	// another entry
		OO_CHECK(stage->modelNamed("builtin.dat", std::nullopt, "demoships.plist", oo::PList(), oo::PList()));
		OO_CHECK(stage->modelNamed("SHIP.DAT", "c", "shipdata.plist", oo::PList(), oo::PList()));
		const size_t caseWarnings = gLog.size();	// the scanner's case warning for SHIP.DAT
		OO_CHECK(LogLinesContaining("case mismatch") == 1);

		gLog.clear();
		stage->run();
		OO_CHECK(caseWarnings == 1);
		OO_CHECK(gLog == (std::vector<std::string>{
			"TODO: implement model verifier.",
			"- Pretending to verify model ship.dat referenced in entry \"a\" of shipdata.plist.",
			"- Pretending to verify model ship.dat referenced in entry \"b\" of shipdata.plist.",
			"- Pretending to verify model builtin.dat referenced in demoships.plist.",
			"- Pretending to verify model SHIP.DAT referenced in entry \"c\" of shipdata.plist." }));

		// The models are forgotten after the run.
		OO_CHECK(!stage->shouldRun());
		gLog.clear();
		stage->run();
		OO_CHECK(gLog == std::vector<std::string>{ "TODO: implement model verifier." });
	}
	std::filesystem::remove_all(kBase);
}


// The converted stage is global: the stage the verifier registered is its facade, an
// OOOXPVerifierStage, one per stage, and -modelVerifierStage finds it for the ship data stage.
OO_TEST(facade)
{
	@autoreleasepool
	{
		OOOXPVerifier *verifier = MakeVerifier({ { "Models/ship.dat", "model" } });
		OOModelVerifierStage::nameForReverseDependencyForVerifier(verifier);
		OOOXPVerifierStage *facade = [verifier modelVerifierStage];
		OO_CHECK(facade != nil && [facade class] == [OOOXPVerifierStage class]);
		OOModelVerifierStage *stage = static_cast<OOModelVerifierStage *>(oo::ToCxx(facade));
		OO_CHECK(stage != nullptr && oo::ToObjC(stage) == facade);
		OO_CHECK(oo::AsObjCStage(stage) == nullptr);
		OO_CHECK(oo::DescriptionOf(facade).starts_with("<OOModelVerifierStage 0x"));

		OO_CHECK([facade cxx_name] == std::optional<std::string>(OOModelVerifierStage::kName));
		OO_CHECK([facade dependents] == (std::vector<std::string>{ "Checking for unused files", "Testing textures and images" }));
		OO_CHECK(![facade shouldRun]);
		OO_CHECK(stage->modelNamed("ship.dat", "a", "shipdata.plist", oo::PList(), oo::PList()));
		OO_CHECK([facade shouldRun]);
		gLog.clear();
		[facade dependencyRegistrationComplete];
		[facade performRun];
		OO_CHECK(gLog.size() == 2 && LogLinesContaining("- Pretending to verify model ship.dat referenced in entry \"a\" of shipdata.plist.") == 1);
	}
	std::filesystem::remove_all(kBase);
}

OO_TEST_MAIN()
