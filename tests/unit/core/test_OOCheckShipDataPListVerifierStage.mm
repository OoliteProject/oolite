/*	test_OOCheckShipDataPListVerifierStage.mm
	Unit tests for OOCheckShipDataPListVerifierStage.h/.mm (bead oo-1v2w; proposed ADR-0056
	Amendment 1, amendments oo-up4b and oo-rmd7): the shipdata.plist stage, a subclass of
	OOTextureHandlingStage.

	What the stage computed before the conversion is pinned: its name, its dependents (the
	intermediate class's, then the model and AI stages, which asking registers), when it runs, and
	what it logs for each ship, grouped under a "Ship" line: keys unknown or of another category,
	a player ship that is also a station, a missing model or like_ship, a model it cannot find,
	and the schema verifier's findings, which reach the stage as its delegate. It hands each model
	to the model stage and each AI to the AI stage. The schema verifier and the resource manager
	reach the whole game, so the test replaces them: the schema verifier reports a value "BAD" as
	a failure and asks its delegate about a value "DELEGATED". Then the crossing: the converted
	stage is global, so Objective-C sees it as an OOOXPVerifierStage.
	Run: bash tools/check-core-tests.sh
*/

#import "OOCheckShipDataPListVerifierStage.h"
#import "OOModelVerifierStage.h"
#import "OOAIStateMachineVerifierStage.h"
#import "OOOXPVerifierStageInternal.h"
#import "OODescription.h"
#import "OOPListSchemaVerifier.h"
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


// OOPListParsing.mm reaches the universe; the AI stage reads AIs with this one function of it.
oo::PList cxx_OOPropertyListFromFile(const std::string &path)
{
	(void)path;
	return oo::PList();
}


/*	The verifier and the resource manager are not linked either (they reach the whole game). The
	stages talk to the verifier through its interface only, so the test is the verifier (as in
	test_OOFileScannerVerifierStage.mm). The resource manager has Oolite's own ships and the
	schema.
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
+ (oo::PList) cxx_dictionaryFromFilesNamed:(const std::string &)fileName inFolder:(const std::optional<std::string> &)folderName andMerge:(BOOL)mergeFiles;
+ (oo::PList) cxx_whitelistDictionary;

@end


@implementation ResourceManager

+ (std::optional<std::string>) cxx_pathForFileNamed:(const std::string &)fileName inFolder:(const std::optional<std::string> &)folderName
{
	if (fileName != "builtin.dat")  return std::nullopt;
	return "builtin/" + folderName.value_or("") + "/" + fileName;
}


+ (oo::PList) cxx_dictionaryFromFilesNamed:(const std::string &)fileName inFolder:(const std::optional<std::string> &)folderName andMerge:(BOOL)mergeFiles
{
	(void)folderName;
	(void)mergeFiles;
	if (fileName == "shipdata.plist")  return *oo::parsePropertyListData("{ cobra3 = { model = \"cobra3.dat\"; }; }");
	return *oo::parsePropertyListData("{ type = dictionary; }");	// the schema
}


+ (oo::PList) cxx_whitelistDictionary
{
	return oo::PList();
}

@end


// The texture stage (linked for the intermediate class) loads through these; no ship here names a texture.
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


/*	The schema verifier (OOPListSchemaVerifier.mm reaches the game's plist types): a value "BAD"
	fails, a value "DELEGATED" is a delegated type, and each is reported to the delegate as the
	real verifier reports it. Its header's ivar is the C++ verifier since oo-pni4, so the stand-in
	keeps its own state in ivars of its @implementation.
*/
const char * const kPListKeyPathErrorKey = "keyPath";

namespace {

int gSchemaVerifiers = 0;

}	// namespace


@implementation OOPListSchemaVerifier
{
	oo::PList	_schema;
	id			_delegate;	// Not retained, as the real verifier's.
}

+ (instancetype)verifierWithSchema:(const oo::PList &)schema
{
	if (schema.isNull())  return nil;
	return [[[self alloc] initWithSchema:schema] autorelease];
}


- (id)initWithSchema:(const oo::PList &)schema
{
	self = [super init];
	if (self != nil)
	{
		_schema = schema;
		gSchemaVerifiers++;
	}
	return self;
}


- (void)setDelegate:(id)delegate	{ _delegate = delegate; }
- (id)delegate						{ return _delegate; }


- (BOOL)verifyPropertyList:(const oo::PList &)plist named:(const std::string &)name
{
	for (const auto &[key, value] : *plist.getIf<oo::PList::Dict>())
	{
		const oo::PList keyPath = *oo::parsePropertyListData("(\"" + key + "\")");
		if (value.getIf<std::string>() != nullptr && *value.getIf<std::string>() == "BAD")
		{
			OOPListSchemaVerifierError error;
			error.failureReason = "a test failure";
			error.userInfo = *oo::parsePropertyListData("{ keyPath = (\"" + key + "\"); }");
			[_delegate verifier:self withPropertyList:plist named:name failedForProperty:value withError:error expectedType:oo::PList()];
		}
		if (value.getIf<std::string>() != nullptr && *value.getIf<std::string>() == "DELEGATED")
		{
			std::optional<OOPListSchemaVerifierError> error;
			[_delegate verifier:self withPropertyList:plist named:name testProperty:value atPath:keyPath againstType:oo::PList(std::string("aTestType")) error:&error];
		}
	}
	return YES;
}


+ (std::optional<std::string>)descriptionForKeyPath:(const oo::PList &)keyPath
{
	std::string result;
	for (const oo::PList &component : *keyPath.getIf<oo::PList::Array>())
	{
		if (!result.empty())  result += ".";
		if (const std::string *text = component.getIf<std::string>())  result += *text;
	}
	return result;
}

@end


namespace {

const char * const kConfiguration =
	"{"
	"	knownRootDirectories = (\"Config\", \"Models\", \"AIs\");"
	"	shipdataPListSettings ="
	"	{"
	"		knownShipKeys = (model, roles, ai_type, like_ship, is_template, is_carrier, materials, shaders, bounty, notes);"
	"		knownStationKeys = (port_radius);"
	"		knownPlayerKeys = (max_cargo);"
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
void RunScanner(OOOXPVerifier *verifier)
{
	[OOFileScannerVerifierStage nameForDependencyForVerifier:verifier];
	[[verifier fileScannerStage] run];
}


const std::vector<std::string> kScannerName = { "Scanning files" };
const std::vector<std::string> kUnusedName = { "Checking for unused files" };

const std::filesystem::path kBase = std::filesystem::current_path() / "test_OOCheckShipDataPListVerifierStage.oxp";


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


// The lines logged for one ship: the indented lines after its "Ship" line.
std::vector<std::string> LinesForShip(const std::string &ship)
{
	std::vector<std::string> result;
	bool in = false;
	for (const std::string &line : gLog)
	{
		const size_t start = line.find_first_not_of(' ');
		const std::string text = start == std::string::npos ? line : line.substr(start);
		if (text.starts_with("Ship \""))  in = (text == "Ship \"" + ship + "\":");
		else if (in && start != 0)  result.push_back(text);	// the ship's findings are indented under it
		else  in = false;
	}
	return result;
}

}	// namespace


OO_TEST(nameAndNeighbours)
{
	@autoreleasepool
	{
		OOOXPVerifier *verifier = MakeVerifier({});
		const oo::Ref<OOCheckShipDataPListVerifierStage> stage = oo::makeRef<OOCheckShipDataPListVerifierStage>();
		stage->setVerifier(verifier);
		OO_CHECK(stage->name() == std::optional<std::string>("Checking shipdata.plist"));
		OO_CHECK(stage->dependencies() == kScannerName);
		OO_CHECK([verifier cxx_stageWithName:"Testing models"] == nil);
		OO_CHECK(stage->dependents() == (std::vector<std::string>{ "Checking for unused files", "Testing textures and images", "Testing models", "Validating AIs" }));
		OO_CHECK([verifier cxx_stageWithName:"Testing models"] != nil);	// asking registers the model stage
		OO_CHECK([verifier cxx_stageWithName:"Validating AIs"] == nil);	// but not the AI stage
		OO_CHECK(!stage->shouldRun());
		stage->run();
		OO_CHECK(gLog.empty());

		stage->setVerifier(MakeVerifier({ { "Config/shipdata.plist", "( a )" } }));
		OO_CHECK(stage->shouldRun());
		stage->run();
		OO_CHECK(gLog.size() == 1 && LogLinesContaining("***** ERROR: shipdata.plist is not a dictionary.") == 1);
	}
	std::filesystem::remove_all(kBase);
}


OO_TEST(checksEachShip)
{
	@autoreleasepool
	{
		OOOXPVerifier *verifier = MakeVerifier({
			{ "Models/ship.dat", "model" },
			{ "AIs/shipAI.plist", "{}" },
			{ "Config/shipdata.plist",
				"{"
				"	good = { model = \"ship.dat\"; roles = \"trader pirate(0.5)\"; ai_type = \"shipAI.plist\"; };"
				"	keys = { model = \"ship.dat\"; roles = trader; port_radius = 5; max_cargo = 3; wibble = 1; };"
				"	both = { model = \"builtin.dat\"; roles = \"player station\"; };"
				"	station = { model = \"ship.dat\"; roles = \"station\"; port_radius = 5; };"
				"	template = { is_template = yes; roles = trader; port_radius = 5; like_ship = good; };"
				"	nomodel = { roles = trader; };"
				"	lost = { model = \"lost.dat\"; roles = trader; ai_type = \"script.js\"; };"
				"	schema = { model = \"ship.dat\"; roles = trader; bounty = BAD; notes = DELEGATED; };"
				"	notDict = 7;"
				"}" },
		});
		const oo::Ref<OOAIStateMachineVerifierStage> aiStage = oo::makeRef<OOAIStateMachineVerifierStage>();
		[verifier registerStage:oo::ToObjC(aiStage.get())];
		const oo::Ref<OOCheckShipDataPListVerifierStage> stage = oo::makeRef<OOCheckShipDataPListVerifierStage>();
		stage->setVerifier(verifier);
		stage->dependents();	// registers the model stage, as the verifier's dependency pass does
		gLog.clear();
		stage->run();

		OO_CHECK(gSchemaVerifiers >= 1);
		OO_CHECK(LinesForShip("good").empty());
		OO_CHECK(LogLinesContaining("- ship \"good\" OK.") == 1);
		OO_CHECK(LinesForShip("keys") == (std::vector<std::string>{
			"----- WARNING: key \"max_cargo\" does not apply to this category of ship.",
			"----- WARNING: key \"port_radius\" does not apply to this category of ship.",
			"----- WARNING: unknown key \"wibble\"." }));
		OO_CHECK(LinesForShip("both") == (std::vector<std::string>{
			"***** ERROR: ship is both a player ship and a station. Treating as non-station." }));
		OO_CHECK(LinesForShip("station").empty() && LogLinesContaining("- ship \"station\" OK.") == 1);
		OO_CHECK(LinesForShip("template").empty());	// another category's key is allowed in a template
		OO_CHECK(LinesForShip("nomodel") == (std::vector<std::string>{
			"***** ERROR: ship does not specify model or like_ship." }));
		OO_CHECK(LinesForShip("lost") == (std::vector<std::string>{
			"----- WARNING: model \"lost.dat\" could not be found in Test.oxp or in Oolite." }));
		OO_CHECK(LinesForShip("schema") == (std::vector<std::string>{
			"***** ERROR: verification of ship \"schema\" failed at \"bounty\": a test failure",
			"- Skipping verification for type aTestType at schema.notes." }));
		OO_CHECK(LogLinesContaining("***** ERROR: shipdata.plist entry for \"notDict\" is not a dictionary.") == 1);

		// Ships in case-insensitive order of their keys.
		OO_CHECK(gLog.front().find("\"both\"") != std::string::npos);

		// The models found went to the model stage; the AI (not the JavaScript one) to the AI stage.
		OO_CHECK([[verifier cxx_stageWithName:"Testing models"] shouldRun]);
		OO_CHECK(aiStage->shouldRun());
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
		const oo::Ref<OOCheckShipDataPListVerifierStage> stage = oo::makeRef<OOCheckShipDataPListVerifierStage>();
		OOOXPVerifierStage *facade = oo::ToObjC(stage.get());
		OO_CHECK(facade != nil && facade == oo::ToObjC(stage.get()) && oo::ToCxx(facade) == stage.get());
		OO_CHECK([facade class] == [OOOXPVerifierStage class]);
		OO_CHECK(oo::AsObjCStage(stage.get()) == nullptr);
		OO_CHECK(oo::DescriptionOf(facade).starts_with("<OOCheckShipDataPListVerifierStage 0x"));

		[verifier registerStage:facade];
		OO_CHECK([verifier cxx_stageWithName:"Checking shipdata.plist"] == facade);
		OO_CHECK([facade cxx_name] == std::optional<std::string>("Checking shipdata.plist"));
		OO_CHECK([facade cxx_dependencies] == kScannerName);
		OO_CHECK([facade dependents] == (std::vector<std::string>{ "Checking for unused files", "Testing textures and images", "Testing models", "Validating AIs" }));
		OO_CHECK([facade shouldRun] == stage->shouldRun());
	}
}

OO_TEST_MAIN()
