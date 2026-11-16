/*	test_OOTextureVerifierStage.mm
	Unit tests for OOTextureVerifierStage.h/.mm (bead oo-tuq8; proposed ADR-0056 Amendment 1 and
	amendment oo-up4b items 2 and 6): the texture stage, a leaf of OOFileHandlingVerifierStage,
	and OOTextureHandlingStage, an intermediate class that the ship data and model stages still
	subclass in Objective-C.

	What the file computed before the conversion is pinned: the texture stage's name and
	neighbours, the textures other stages name (found or not, each once, empty names ignored), when
	it runs, and what it logs for each texture and image it loads (unreadable, failed, not a power
	of two, OK). The texture loader reaches the whole game, so the test replaces it with a class
	that reads "<width>x<height>" from the file. A texture-handling stage adds the texture stage to
	its intermediate class's dependents, also through [super dependents]. Then the crossing: the
	converted texture stage is global; an Objective-C subclass of OOTextureHandlingStage is behind a
	C++ pointer whose class derives from cxx::OOTextureHandlingStage; a C++ subclass of it is behind
	the root's facade; and the adapter outlives its owner.
	Run: bash tools/check-core-tests.sh
*/

#import "OOTextureVerifierStage.h"
#import "OOOXPVerifierStageInternal.h"
#import "OODescription.h"
#import "OOPixMap.h"
#import "OOTexture.h"

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


/*	The verifier and the resource manager are not linked either (they reach the whole game). The
	stages talk to the verifier through its interface only, so the test is the verifier (as in
	test_OOFileScannerVerifierStage.mm). The resource manager has one built-in texture.
*/
#include "OOOXPVerifierTestDouble.h"


@interface ResourceManager: OOObject

+ (std::optional<std::string>) cxx_pathForFileNamed:(const std::string &)fileName inFolder:(const std::optional<std::string> &)folderName;

@end


@implementation ResourceManager

+ (std::optional<std::string>) cxx_pathForFileNamed:(const std::string &)fileName inFolder:(const std::optional<std::string> &)folderName
{
	if (fileName != "builtin.png")  return std::nullopt;
	return "builtin/" + folderName.value_or("") + "/" + fileName;
}

@end


/*	The texture loader (OOTextureLoader.mm reaches the whole game): a file saying "unreadable" has
	no loader, one saying "fail" fails to load, and "<width>x<height>" loads at that size.
*/
namespace {

uint32_t gLoaderOptions = 0;
int gPixMapsFreed = 0;

}	// namespace


void OOFreePixMap(OOPixMap *ioPixMap)
{
	gPixMapsFreed++;
	*ioPixMap = OOPixMap{};
}


@interface OOTextureLoader: OOObject
{
@private
	std::string _contents;
}

+ (id) cxx_loaderWithPath:(const std::optional<std::string> &)path options:(uint32_t)options;
- (BOOL) getResult:(OOPixMap *)result format:(OOTextureDataFormat *)outFormat originalWidth:(uint32_t *)outWidth originalHeight:(uint32_t *)outHeight;

@end


@implementation OOTextureLoader

+ (id) cxx_loaderWithPath:(const std::optional<std::string> &)path options:(uint32_t)options
{
	gLoaderOptions = options;
	std::ifstream file(path.value_or(""), std::ios::binary);
	std::stringstream bytes;
	bytes << file.rdbuf();
	if (bytes.str() == "unreadable")  return nil;
	OOTextureLoader *loader = [[[OOTextureLoader alloc] init] autorelease];
	loader->_contents = bytes.str();
	return loader;
}


- (BOOL) getResult:(OOPixMap *)result format:(OOTextureDataFormat *)outFormat originalWidth:(uint32_t *)outWidth originalHeight:(uint32_t *)outHeight
{
	(void)outFormat;
	(void)outWidth;
	(void)outHeight;
	unsigned width = 0, height = 0;
	if (std::sscanf(_contents.c_str(), "%ux%u", &width, &height) != 2)  return NO;
	*result = OOPixMap{};
	result->width = width;
	result->height = height;
	return YES;
}

@end


// An unconverted texture-handling stage, as the ship data and model stages are.
@interface TestTextureUser: OOTextureHandlingStage
@end


@implementation TestTextureUser

- (std::optional<std::string>)cxx_name	{ return "Using textures"; }

@end


// Extends its superclass's dependents through [super dependents], as the ship data stage does.
@interface TestSuperCallingTextureUser: TestTextureUser
@end


@implementation TestSuperCallingTextureUser

- (std::optional<std::vector<std::string>>)dependents
{
	std::vector<std::string> result = [super dependents].value_or(std::vector<std::string>());
	result.push_back("Extra dependent");
	return result;
}

@end


namespace {

const char * const kConfiguration =
	"{"
	"	knownRootDirectories = (\"Textures\", \"Images\");"
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

const std::filesystem::path kBase = std::filesystem::current_path() / "test_OOTextureVerifierStage.oxp";
const std::vector<std::string> kTextureUserDependents = { "Checking for unused files", "Testing textures and images" };


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


OO_TEST(nameAndNeighbours)
{
	@autoreleasepool
	{
		OOOXPVerifier *verifier = MakeVerifier({});
		OO_CHECK(OOTextureVerifierStage::nameForReverseDependencyForVerifier(verifier) == "Testing textures and images");

		const oo::Ref<OOTextureVerifierStage> stage = oo::makeRef<OOTextureVerifierStage>();
		stage->setVerifier(verifier);
		OO_CHECK(stage->name() == std::optional<std::string>("Testing textures and images"));
		OO_CHECK(stage->dependencies() == kScannerName);
		OO_CHECK(stage->dependents() == kUnusedName);
		OO_CHECK(!stage->shouldRun());	// nothing named, no Images
		stage->run();
		OO_CHECK(gLog.empty());

		stage->setVerifier(MakeVerifier({ { "Images/a.png", "8x8" } }));
		OO_CHECK(stage->shouldRun());
	}
	std::filesystem::remove_all(kBase);
}


OO_TEST(stagesNameTextures)
{
	@autoreleasepool
	{
		const oo::Ref<OOTextureVerifierStage> stage = oo::makeRef<OOTextureVerifierStage>();
		stage->setVerifier(MakeVerifier({ { "Textures/hull.png", "8x8" } }));

		stage->textureNamed("", "nowhere");
		OO_CHECK(!stage->shouldRun() && gLog.empty());	// an empty name is ignored

		stage->textureNamed("hull.png", "ship.dat");
		stage->textureNamed("builtin.png", "ship.dat");
		OO_CHECK(stage->shouldRun() && gLog.empty());

		stage->textureNamed("missing.png", "shipdata.plist entry \"a\"");
		stage->textureNamed("missing.png", "shipdata.plist entry \"b\"");
		OO_CHECK(gLog.size() == 1);
		OO_CHECK(LogLinesContaining("----- WARNING: texture \"missing.png\" referenced in shipdata.plist entry \"a\" could not be found in Test.oxp or in Oolite.") == 1);
	}
	std::filesystem::remove_all(kBase);
}


OO_TEST(runLoadsTexturesAndImages)
{
	@autoreleasepool
	{
		const oo::Ref<OOTextureVerifierStage> stage = oo::makeRef<OOTextureVerifierStage>();
		stage->setVerifier(MakeVerifier({
			{ "Textures/pot.png", "64x32" },
			{ "Textures/npot.png", "100x30" },
			{ "Textures/unreadable.png", "unreadable" },
			{ "Textures/fail.png", "fail" },
			{ "Textures/unused.png", "8x8" },
			{ "Images/b.png", "16x16" },
			{ "Images/A.png", "3x3" },
		}));
		for (const char *name : { "unreadable.png", "pot.png", "npot.png", "fail.png", "builtin.png", "missing.png" })
		{
			stage->textureNamed(name, "a test");
		}
		gLog.clear();
		gPixMapsFreed = 0;
		stage->run();

		OO_CHECK(gLoaderOptions == (kOOTextureMinFilterNearest | kOOTextureNoShrink | kOOTextureNoFNFMessage | kOOTextureNeverScale));
		OO_CHECK(LogLinesContaining("- Textures/pot.png (64x32 px) OK.") == 1);
		OO_CHECK(LogLinesContaining("----- WARNING: image Textures/npot.png has non-power-of-two dimensions; it will have to be rescaled (from 100x30 pixels to 128x32 pixels) at runtime.") == 1);
		OO_CHECK(LogLinesContaining("***** ERROR: image Textures/unreadable.png could not be read.") == 1);
		OO_CHECK(LogLinesContaining("***** ERROR: texture loader failed to load Textures/fail.png.") == 1);
		OO_CHECK(LogLinesContaining("unused.png") == 0 && LogLinesContaining("builtin.png") == 0 && LogLinesContaining("missing.png") == 0);

		// Every image is checked, named textures first (byte order), then Images (as listed).
		OO_CHECK(LogLinesContaining("- Images/A.png (3x3 px) OK.") == 0);
		OO_CHECK(LogLinesContaining("image Images/A.png has non-power-of-two dimensions; it will have to be rescaled (from 3x3 pixels to 2x2 pixels)") == 1);
		OO_CHECK(LogLinesContaining("- Images/b.png (16x16 px) OK.") == 1);
		OO_CHECK(gLog.size() == 6 && gLog.front().find("fail.png") != std::string::npos && gLog.back().find("Images/b.png") != std::string::npos);
		OO_CHECK(gPixMapsFreed == 4);

		// The named textures are forgotten after the run; the images are not.
		gLog.clear();
		stage->run();
		OO_CHECK(gLog.size() == 2);
		OO_CHECK(stage->shouldRun());
	}
	std::filesystem::remove_all(kBase);
}


OO_TEST(textureHandlingStage)
{
	@autoreleasepool
	{
		OOOXPVerifier *verifier = MakeVerifier({});
		TestTextureUser *user = [[[TestTextureUser alloc] init] autorelease];
		[user setVerifier:verifier];
		OO_CHECK([user cxx_name] == std::optional<std::string>("Using textures"));
		OO_CHECK([user cxx_dependencies] == kScannerName);
		OO_CHECK([user dependents] == kTextureUserDependents);
		OO_CHECK([user dependents] == kTextureUserDependents);	// asked again: no duplicate

		TestSuperCallingTextureUser *superCalling = [[[TestSuperCallingTextureUser alloc] init] autorelease];
		[superCalling setVerifier:verifier];
		OO_CHECK([superCalling dependents] == (std::vector<std::string>{ "Checking for unused files", "Testing textures and images", "Extra dependent" }));

		OO_CHECK([user isKindOfClass:[OOTextureHandlingStage class]] && [user isKindOfClass:[OOFileHandlingVerifierStage class]]);
	}
}


// A converted texture-handling stage: a C++ subclass of the intermediate class. Global, as the
// ship data and model stages will be, so Objective-C sees it as an OOOXPVerifierStage.
class TestCxxTextureUser : public cxx::OOTextureHandlingStage
{
public:
	std::optional<std::string> name() override	{ return "Using textures in C++"; }
};


// An Objective-C subclass of the intermediate class is behind a C++ pointer whose class derives
// from cxx::OOTextureHandlingStage; virtual calls reach the subclass, or the intermediate class.
OO_TEST(objCTextureUserBehindACxxPointer)
{
	@autoreleasepool
	{
		OOOXPVerifier *verifier = MakeVerifier({});
		TestTextureUser *user = [[[TestTextureUser alloc] init] autorelease];
		[user setVerifier:verifier];
		cxx::OOOXPVerifierStage *part = oo::ToCxx(user);
		OO_CHECK(part != nullptr && oo::ToObjC(part) == user);
		OO_CHECK(dynamic_cast<cxx::OOTextureHandlingStage *>(part) != nullptr);
		OO_CHECK(part->name() == std::optional<std::string>("Using textures"));
		OO_CHECK(part->dependencies() == kScannerName);
		OO_CHECK(part->dependents() == kTextureUserDependents);

		TestSuperCallingTextureUser *superCalling = [[[TestSuperCallingTextureUser alloc] init] autorelease];
		[superCalling setVerifier:verifier];
		OO_CHECK(oo::ToCxx(superCalling)->dependents() == (std::vector<std::string>{ "Checking for unused files", "Testing textures and images", "Extra dependent" }));
	}
}


OO_TEST(cxxTextureUserBehindTheFacade)
{
	@autoreleasepool
	{
		OOOXPVerifier *verifier = MakeVerifier({});
		const oo::Ref<TestCxxTextureUser> user = oo::makeRef<TestCxxTextureUser>();
		user->setVerifier(verifier);
		OO_CHECK(user->dependents() == kTextureUserDependents);

		OOOXPVerifierStage *facade = oo::ToObjC(user.get());
		OO_CHECK(facade != nil && facade == oo::ToObjC(user.get()) && oo::ToCxx(facade) == user.get());
		OO_CHECK([facade class] == [OOOXPVerifierStage class]);
		OO_CHECK([facade cxx_name] == std::optional<std::string>("Using textures in C++"));
		OO_CHECK([facade dependents] == kTextureUserDependents);
		OO_CHECK(oo::DescriptionOf(facade).starts_with("<TestCxxTextureUser 0x"));
	}
}


// The texture stage is global: Objective-C sees it as an OOOXPVerifierStage, which the verifier's
// -textureVerifierStage (no caller left) answers once it is registered.
OO_TEST(textureStageFacade)
{
	@autoreleasepool
	{
		OOOXPVerifier *verifier = MakeVerifier({ { "Images/a.png", "8x8" } });
		const oo::Ref<OOTextureVerifierStage> stage = oo::makeRef<OOTextureVerifierStage>();
		OOOXPVerifierStage *facade = oo::ToObjC(stage.get());
		OO_CHECK(facade != nil && facade == oo::ToObjC(stage.get()) && oo::ToCxx(facade) == stage.get());
		OO_CHECK([facade class] == [OOOXPVerifierStage class]);
		OO_CHECK(oo::DescriptionOf(facade).starts_with("<OOTextureVerifierStage 0x"));

		OO_CHECK([verifier textureVerifierStage] == nil);
		[verifier registerStage:facade];
		OO_CHECK([verifier textureVerifierStage] == facade);
		OO_CHECK([facade cxx_name] == std::optional<std::string>("Testing textures and images"));
		OO_CHECK([facade cxx_dependencies] == kScannerName);
		OO_CHECK([facade dependents] == kUnusedName);
		OO_CHECK([facade shouldRun]);
		gLog.clear();
		[facade dependencyRegistrationComplete];
		[facade performRun];
		OO_CHECK(gLog.size() == 1 && LogLinesContaining("- Images/a.png (8x8 px) OK.") == 1);
	}
	std::filesystem::remove_all(kBase);
}


OO_TEST(adapterOutlivesItsOwner)
{
	oo::Ref<cxx::OOOXPVerifierStage> part;
	@autoreleasepool
	{
		part = oo::Ref<cxx::OOOXPVerifierStage>(oo::ToCxx([[[TestTextureUser alloc] init] autorelease]));
	}
	OO_CHECK(!part->name().has_value());
	OO_CHECK(!part->dependents().has_value());
	OO_CHECK(oo::ToObjC(part) == nil);
}

OO_TEST_MAIN()
