/*	test_OOFileScannerVerifierStage.mm
	Unit tests for OOFileScannerVerifierStage.h/.mm (bead oo-up4b; proposed ADR-0056 Amendment 1
	and amendment oo-up4b): OOFileScannerVerifierStage and the intermediate class
	OOFileHandlingVerifierStage that the file-handling stages subclass.

	What the file computed before the conversion is pinned through the Objective-C API the other
	stages use: the dependency and dependent a file-handling stage names (and registers), [super
	dependents] from a subclass, and the scanner's answers over a real directory: case-insensitive
	look-up with folder fallback, junk, skipped and Read Me files, listings, data and property
	lists. Then the crossing: an Objective-C subclass of the intermediate class behind a C++
	pointer, a C++ subclass of it behind the facade, the scanner's own facade class and identity,
	and the adapter outliving its owner.

	Bead oo-9ht.7 deleted both classes' Objective-C facades and the verifier's -fileScannerStage
	(ADR-0056 amendment "deleting a facade"). The cases that asked through their selectors ask the
	C++ classes with the same expectations (the Objective-C test stages became C++ subclasses, the
	super call a qualified base call, -fileScannerStage the stage lookup it made, isKindOfClass: a
	dynamic_cast); the scanner now crosses as the root's facade, as every global stage does. The
	cases that pinned only the deleted facades (scannerMadeByAllocInit, objCFileStageBehindACxxPointer,
	the facade half of scannerFacade, nilAndLifetime) were retired with them (ADR-0049, standing
	approval oo-9n5p9).
	Bead oo-9ht.4 deleted the root's facade (OOOXPVerifierStage): the verifier answers the C++
	stage itself, so cxxFileStageBehindTheFacade asks the stage (its description through
	description(), as scannerFindsFiles does), and the checks that pinned only that facade's
	crossing (one live facade, oo::ToObjC/oo::ToCxx, its class; the C++-made scanner's half of
	scannerFacade) were retired with it (ADR-0049, standing approval oo-9n5p9).
	Run: bash tools/check-core-tests.sh
*/

#import "OOFileScannerVerifierStage.h"
#import "OOOXPVerifierStage.h"
#import "OODescription.h"

#import "OOLogging.h"
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
	stages talk to the verifier through its interface only, so the test is the verifier: the
	configuration is a verifyOXP.plist of the test's, registration keeps stages by name. The
	resource manager answers the one question the scanner asks it, for built-in files.
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


// A file-handling stage, as the leaf stages are.
class TestFileStage : public OOFileHandlingVerifierStage
{
public:
	std::optional<std::string> name() override	{ return "Testing files"; }
};


// Extends its superclass's dependents through the base call, as OOTextureHandlingStage does.
class TestSuperCallingFileStage : public TestFileStage
{
public:
	std::optional<std::vector<std::string>> dependents() override
	{
		std::vector<std::string> result = TestFileStage::dependents().value_or(std::vector<std::string>());
		result.push_back("Extra dependent");
		return result;
	}
};


// A converted file-handling stage: a C++ subclass of the intermediate class. Global, as a leaf
// stage is once converted, so Objective-C sees it as an OOOXPVerifierStage.
class TestCxxFileStage : public OOFileHandlingVerifierStage
{
public:
	std::optional<std::string> name() override	{ return "Testing files in C++"; }
	void run() override							{ runs++; }

	int runs = 0;
};


namespace {

const char * const kConfiguration =
	"{"
	"	junkFiles = (\".DS_Store\");"
	"	skipDirectories = (\".svn\");"
	"	readMeNames = { stems = (\"readme\"); extensions = (\".txt\"); };"
	"	knownRootDirectories = (\"Config\", \"Textures\", \"Images\");"
	"	knownFiles = { Config = (\"shipdata.plist\"); };"
	"	knownConfigFiles = (\"shipdata.plist\");"
	"}";


void WriteFile(const std::filesystem::path &path, const char *contents)
{
	std::filesystem::create_directories(path.parent_path());
	std::ofstream(path, std::ios::binary) << contents;
}


// A small OXP in the working directory: a lowercase textures folder, a root file, a Read Me, a
// junk file, a skipped folder and a nested folder.
std::string MakeOXP()
{
	const std::filesystem::path base = std::filesystem::current_path() / "test_OOFileScannerVerifierStage.oxp";
	std::filesystem::remove_all(base);
	WriteFile(base / "Config" / "shipdata.plist", "{ a = 1; }");
	WriteFile(base / "Config" / "bad.plist", "{ a = ");
	WriteFile(base / "textures" / "Foo.PNG", "png");
	WriteFile(base / "Images" / "b.png", "b");
	WriteFile(base / "Images" / "A.png", "a");
	WriteFile(base / "Images" / "nested" / "c.png", "c");
	WriteFile(base / "Root.png", "root");
	WriteFile(base / "ReadMe.txt", "read me");
	WriteFile(base / ".DS_Store", "junk");
	WriteFile(base / ".svn" / "entries", "svn");
	return base.generic_string();
}


OOOXPVerifier *MakeVerifier(const std::string &path)
{
	return OOOXPVerifierTestAccess::Make(path, kConfiguration);
}


const std::vector<std::string> kScannerName = { "Scanning files" };
const std::vector<std::string> kUnusedName = { "Checking for unused files" };


// The registered scanner, as the stages find it (the verifier's -fileScannerStage until bead oo-9ht.7).
OOFileScannerVerifierStage *ScannerOf(OOOXPVerifier *verifier)
{
	return dynamic_cast<OOFileScannerVerifierStage *>(verifier->stageWithName(OOFileScannerVerifierStage::kName));
}

}	// namespace


OO_TEST(fileHandlingStageNamesAndRegistersItsNeighbours)
{
	@autoreleasepool
	{
		OOOXPVerifier *verifier = MakeVerifier("");
		const oo::Ref<TestFileStage> stage = oo::makeRef<TestFileStage>();
		stage->setVerifier(verifier);
		const int before = OOOXPVerifierTestAccess::Registrations();

		OO_CHECK(stage->dependencies() == kScannerName);
		OO_CHECK(stage->dependents() == kUnusedName);
		OO_CHECK(OOOXPVerifierTestAccess::Registrations() == before + 2);
		OO_CHECK(ScannerOf(verifier) != nullptr);
		OO_CHECK(verifier->stageWithName("Checking for unused files") != nullptr);

		// Asked again (by another stage), nothing new is registered.
		OO_CHECK(stage->dependencies() == kScannerName);
		OO_CHECK(stage->dependents() == kUnusedName);
		OO_CHECK(OOOXPVerifierTestAccess::Registrations() == before + 2);

		// The rest is the base's.
		OO_CHECK(stage->name() == std::optional<std::string>("Testing files"));
		OO_CHECK(stage->shouldRun());
	}
}


OO_TEST(superDependentsReachTheIntermediateClass)
{
	@autoreleasepool
	{
		const oo::Ref<TestSuperCallingFileStage> stage = oo::makeRef<TestSuperCallingFileStage>();
		stage->setVerifier(MakeVerifier(""));
		OO_CHECK(stage->dependents() == (std::vector<std::string>{ "Checking for unused files", "Extra dependent" }));
		OO_CHECK(stage->dependencies() == kScannerName);
	}
}


OO_TEST(scannerFindsFiles)
{
	@autoreleasepool
	{
		const std::string base = MakeOXP();
		OOOXPVerifier *verifier = MakeVerifier(base);
		OO_CHECK(OOFileScannerVerifierStage::nameForDependencyForVerifier(verifier) == std::optional<std::string>("Scanning files"));
		OOFileScannerVerifierStage *scanner = ScannerOf(verifier);
		OO_CHECK(scanner != nullptr && scanner->verifier() == verifier);
		OO_CHECK(scanner->name() == std::optional<std::string>("Scanning files"));
		OO_CHECK(scanner->description().starts_with("<OOFileScannerVerifierStage 0x"));
		OO_CHECK(scanner->description().ends_with(">{\"Scanning files\"}"));
		scanner->run();

		// Case-insensitive, in the folder or bare in the root; the result is the path on disk.
		OO_CHECK(scanner->fileExists("foo.png", "Textures", "a test", false));
		OO_CHECK(scanner->pathForFile("FOO.png", "Textures", std::nullopt, false) == std::optional<std::string>(base + "/textures/Foo.PNG"));
		OO_CHECK(scanner->pathForFile("root.png", "Textures", std::nullopt, false) == std::optional<std::string>(base + "/Root.png"));
		OO_CHECK(scanner->pathForFile("Root.png", std::nullopt, std::nullopt, false) == std::optional<std::string>(base + "/Root.png"));

		// Not found: the built-in files only when asked; no name is no file.
		OO_CHECK(!scanner->pathForFile("builtin.png", "Textures", std::nullopt, false).has_value());
		OO_CHECK(scanner->pathForFile("builtin.png", "Textures", std::nullopt, true) == std::optional<std::string>("builtin/Textures/builtin.png"));
		OO_CHECK(!scanner->pathForFile("missing.png", "Textures", std::nullopt, true).has_value());
		OO_CHECK(!scanner->fileExists(std::nullopt, "Textures", std::nullopt, true));

		// Junk, Read Me files and skipped folders are not part of the OXP; a nested folder is ignored.
		OO_CHECK(!scanner->fileExists(".DS_Store", std::nullopt, std::nullopt, false));
		OO_CHECK(!scanner->fileExists("ReadMe.txt", std::nullopt, std::nullopt, false));
		OO_CHECK(!scanner->filesInFolder(".svn").has_value());
		OO_CHECK(!scanner->fileExists("c.png", "Images", std::nullopt, false));

		// Listings: in the byte order of the lowercase names; the root's is "".
		OO_CHECK(scanner->filesInFolder("IMAGES") == (std::vector<std::string>{ "A.png", "b.png" }));
		OO_CHECK(scanner->filesInFolder("") == std::vector<std::string>{ "Root.png" });
		OO_CHECK(!scanner->filesInFolder("Sounds").has_value());
		OO_CHECK(!scanner->filesInFolder(std::nullopt).has_value());

		OO_CHECK(scanner->displayNameForFile("f", "d") == std::optional<std::string>("d/f"));
		OO_CHECK(scanner->displayNameForFile("f", std::nullopt) == std::optional<std::string>("f"));
		OO_CHECK(!scanner->displayNameForFile(std::nullopt, "d").has_value());

		// Contents.
		OO_CHECK(scanner->dataForFile("shipdata.plist", "config", std::nullopt, false).stringView() == "{ a = 1; }");
		OO_CHECK(scanner->dataForFile("missing.plist", "Config", std::nullopt, false).stringView().empty());
		const oo::PList plist = scanner->plistNamed("shipdata.plist", "Config", std::nullopt, false);
		OO_CHECK(plist.get<std::string>("a") == "1");
		OO_CHECK(scanner->plistNamed("bad.plist", "Config", std::nullopt, false).isNull());	// logs the parse error
		OO_CHECK(scanner->plistNamed("missing.plist", "Config", std::nullopt, false).isNull());

		std::filesystem::remove_all(base);
	}
}


OO_TEST(cxxFileStageBehindTheFacade)
{
	@autoreleasepool
	{
		OOOXPVerifier *verifier = MakeVerifier("");
		const oo::Ref<TestCxxFileStage> stage = oo::makeRef<TestCxxFileStage>();
		stage->setVerifier(verifier);
		OO_CHECK(stage->dependencies() == kScannerName);
		OO_CHECK(stage->dependents() == kUnusedName);
		OO_CHECK(ScannerOf(verifier) != nullptr);

		OO_CHECK(stage->name() == std::optional<std::string>("Testing files in C++"));
		OO_CHECK(stage->dependencies() == kScannerName);
		OO_CHECK(stage->dependents() == kUnusedName);
		stage->dependencyRegistrationComplete();
		stage->performRun();
		OO_CHECK(stage->runs == 1);
		OO_CHECK(stage->description().starts_with("<TestCxxFileStage 0x"));
	}
}


OO_TEST(scannerFacade)
{
	@autoreleasepool
	{
		const std::string base = MakeOXP();
		OOOXPVerifier *verifier = MakeVerifier(base);
		OOFileScannerVerifierStage::nameForDependencyForVerifier(verifier);
		OOFileScannerVerifierStage *cxxScanner = ScannerOf(verifier);
		OO_CHECK(cxxScanner != nullptr);

		// The C++ members answer.
		cxxScanner->run();
		OO_CHECK(cxxScanner->name() == std::optional<std::string>(OOFileScannerVerifierStage::kName));
		OO_CHECK(cxxScanner->pathForFile("foo.png", "Textures", std::nullopt, false) == std::optional<std::string>(base + "/textures/Foo.PNG"));
		OO_CHECK(cxxScanner->fileExists("A.PNG", "images", "a test", false));
		OO_CHECK(cxxScanner->filesInFolder("Images") == (std::vector<std::string>{ "A.png", "b.png" }));
		OO_CHECK(cxxScanner->dataForFile("Root.png", std::nullopt, std::nullopt, false).stringView() == "root");
		OO_CHECK(cxxScanner->plistNamed("shipdata.plist", "Config", std::nullopt, false).get<std::string>("a") == "1");
		OO_CHECK(cxxScanner->displayNameForFile("f", "d") == std::optional<std::string>("d/f"));
		std::filesystem::remove_all(base);
	}
}


OO_TEST_MAIN()
