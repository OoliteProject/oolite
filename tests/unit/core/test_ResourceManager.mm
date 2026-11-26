/*	test_ResourceManager.mm
	Unit tests for ResourceManager (src/Core/ResourceManager.h): bead oo-jfno, slice 1 of the Phase 3
	slice plan docs/phases/3-slices/ResourceManager.md (the class shell, the file-scope state, the
	search paths, the add-on selection and the path utilities), in the house style of the OOColor
	exemplar (proposed ADR-0056, amendments oo-pni4 and oo-3bgz).

	ResourceManager is class methods over file-scope state. These tests pin, through the Objective-C
	API its callers use, what the slice's units answered before the conversion: the state before any
	scan (no add-on selection, no errors, no OXP messages, no manifests), external paths, which make
	the search paths without a scan, the root paths (the built-in data, the managed add-ons, the
	user's add-on folders, as oo::ResourcePaths computes them), masking the user's name in paths, and
	resetting. They never scan for add-ons: that would read the machine's installed expansions
	(CLAUDE.md rule 6), so the search paths are always given as external paths first. The
	expectations were written against the unconverted class and run on it first. After the
	conversion the class is cxx::ResourceManager (static members) behind an Objective-C facade; the
	last test checks that the C++ API answers the same.

	ResourceManager.mm reaches the universe, the HUD, the OXZ manager and the scripts, so the test
	links every game object but main's (tests/unit/core/meson.build entry ['*'], ADR-0056 amendment
	oo-44gg) and defines gDebugFlags. UNIVERSE is nil.
	Bead oo-he11 (slice 2: the OXP manifests) runs the tests in a scratch game folder (see
	ScratchGameFolder) and adds a scan of fixture add-ons whose manifests the slice accepts or rejects.
	Run: bash tools/check-core-tests.sh test_ResourceManager
*/

#import "ResourceManager.h"
#import "OODescription.h"
#import "OOSystemDescriptionManager.h"

#include "oofnd/Data.hpp"
#include "oofnd/FileSystem.hpp"
#include "oofnd/PListParsing.hpp"
#include "oofnd/ResourcePaths.hpp"
#include "oofnd/String.hpp"
#include "oo_test.hpp"

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <process.h>
#include <string>
#include <vector>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


namespace {

/*	Bead oo-he11: every folder ResourceManager reads is under a scratch game folder, made before
	main() and so before the first ResourceManager call (the root paths are computed once): the
	home (HOMEPATH), the managed and extract add-on folders, and the current directory, whose
	Resources folder holds only an Info-gnustep.plist (version 9.9.9) and whose AddOns folder holds
	only the fixtures the slice 2 test writes. The machine's own add-ons are never read.
*/
struct ScratchGameFolder
{
	ScratchGameFolder()
	{
		namespace stdfs = std::filesystem;
		const stdfs::path root = stdfs::temp_directory_path() / ("oo-test-resourcemanager-" + std::to_string(static_cast<unsigned long>(::_getpid())));
		stdfs::remove_all(root);
		stdfs::create_directories(root / "work" / "Resources");
		stdfs::create_directories(root / "work" / "AddOns");
		::_putenv_s("HOMEPATH", root.string().c_str());
		::_putenv_s("OO_MANAGEDADDONSDIR", (root / "managed").string().c_str());
		::_putenv_s("OO_ADDONSEXTRACTDIR", (root / "extract").string().c_str());
		stdfs::current_path(root / "work");
		const std::string info = "{ CFBundleVersion = \"9.9.9\"; }";
		if (!oo::fs::writeFile(root / "work" / "Resources" / "Info-gnustep.plist", oo::Data(info.data(), info.size()), oo::fs::WriteMode::direct))
		{
			std::fprintf(stderr, "  could not write the scratch Info-gnustep.plist\n");
		}
	}
};
const ScratchGameFolder sScratchGameFolder;


// The user name the masking functions read, as they read it (the last component of the profile path).
std::string UserName()
{
	const char *profile = std::getenv("USERPROFILE");
	return oo::str::lastPathComponent(oo::str::format("%s", profile));
}

}	// namespace


OO_TEST(stateBeforeAnyScan)
{
	@autoreleasepool
	{
		OO_CHECK([ResourceManager cxx_useAddOns] == std::nullopt);
		OO_CHECK([ResourceManager cxx_errors] == std::nullopt);
		OO_CHECK([ResourceManager cxx_OXPsWithMessagesFound].empty());
		OO_CHECK([ResourceManager cxx_manifestForIdentifier:"org.test.none"].isNull());
		[ResourceManager clearCaches];
	}
}


OO_TEST(rootPathsAreTheResourcePaths)
{
	@autoreleasepool
	{
		const oo::ResourcePaths paths = oo::ResourcePaths::current();
		const std::string builtIn = oo::fs::utf8String(paths.builtInResourcesDirectory());
		OO_CHECK([ResourceManager cxx_builtInPath] == std::optional<std::string>(builtIn));

		std::vector<std::string> userRoots;
		for (const oo::fs::Path &path : paths.userRootDirectories())  userRoots.push_back(oo::fs::utf8String(path));
		OO_CHECK([ResourceManager cxx_userRootPaths] == userRoots);

		const std::vector<std::string> roots = [ResourceManager cxx_rootPaths];
		OO_CHECK_EQ(roots.size(), userRoots.size() + 2);
		OO_CHECK(roots.size() >= 2 && roots[0] == builtIn);
		OO_CHECK(roots.size() >= 2 && roots[1] == oo::fs::utf8String(paths.managedAddOnsDirectory()));
		OO_CHECK(roots.size() >= 2 && std::vector<std::string>(roots.begin() + 2, roots.end()) == userRoots);
		OO_CHECK([ResourceManager cxx_rootPaths] == roots);	// computed once
	}
}


OO_TEST(maskUserName)
{
	@autoreleasepool
	{
		OO_CHECK([ResourceManager cxx_maskUserName:"jon" inPath:"C:/Users/jon/AddOns"] == std::optional<std::string>("C:/Users/*/AddOns"));
		OO_CHECK([ResourceManager cxx_maskUserName:"jon" inPath:"/home/jon/jon.oxp"] == std::optional<std::string>("/home/*/*.oxp"));
		OO_CHECK([ResourceManager cxx_maskUserName:"jon" inPath:"/srv/oolite"] == std::optional<std::string>("/srv/oolite"));
		OO_CHECK([ResourceManager cxx_maskUserName:"jon" inPath:""] == std::optional<std::string>(""));

		// The array form masks the name of the user running the game, in every path.
		const std::string user = UserName();
		if (!user.empty())
		{
			const std::vector<std::string> masked = [ResourceManager cxx_maskUserNameInPathArray:{ "/a/" + user + "/b", "/c/d" }];
			OO_CHECK(masked == (std::vector<std::string>{ "/a/*/b", "/c/d" }));
		}
		OO_CHECK([ResourceManager cxx_maskUserNameInPathArray:{}].empty());
	}
}


OO_TEST(externalPathsAreTheSearchPathsWithoutAScan)
{
	@autoreleasepool
	{
		[ResourceManager cxx_addExternalPath:"ext/one.oxp"];
		[ResourceManager cxx_addExternalPath:"ext/two.oxp"];
		[ResourceManager cxx_addExternalPath:"ext/one.oxp"];	// already there
		const std::vector<std::string> expected{ "ext/one.oxp", "ext/two.oxp" };
		OO_CHECK([ResourceManager cxx_paths] == expected);
		OO_CHECK([ResourceManager cxx_pathsWithAddOns] == expected);
		OO_CHECK([ResourceManager cxx_useAddOns] == std::nullopt);	// no scan, so no selection

		// -reset forgets them (the next -cxx_paths would scan again, which the test does not do).
		[ResourceManager reset];
		OO_CHECK([ResourceManager cxx_useAddOns] == std::nullopt);
		OO_CHECK([ResourceManager cxx_errors] == std::nullopt);
		[ResourceManager cxx_addExternalPath:"ext/three.oxp"];
		OO_CHECK([ResourceManager cxx_paths] == std::vector<std::string>{ "ext/three.oxp" });
		[ResourceManager reset];
	}
}


OO_TEST(cxxAPIAnswersTheSame)
{
	@autoreleasepool
	{
		// The facade forwards each class method to the static member of the same name.
		OO_CHECK(cxx::ResourceManager::builtInPath() == [ResourceManager cxx_builtInPath]);
		OO_CHECK(cxx::ResourceManager::rootPaths() == [ResourceManager cxx_rootPaths]);
		OO_CHECK(cxx::ResourceManager::userRootPaths() == [ResourceManager cxx_userRootPaths]);
		OO_CHECK(cxx::ResourceManager::maskUserName("jon", "/home/jon") == std::optional<std::string>("/home/*"));
		OO_CHECK(cxx::ResourceManager::useAddOns() == std::nullopt);
		OO_CHECK(cxx::ResourceManager::errors() == std::nullopt);
		OO_CHECK(cxx::ResourceManager::manifestForIdentifier("org.test.none").isNull());
		OO_CHECK(cxx::ResourceManager::OXPsWithMessagesFound().empty());
		cxx::ResourceManager::addExternalPath("ext/cxx.oxp");
		OO_CHECK([ResourceManager cxx_paths] == std::vector<std::string>{ "ext/cxx.oxp" });
		OO_CHECK(cxx::ResourceManager::paths() == std::vector<std::string>{ "ext/cxx.oxp" });
		OO_CHECK(cxx::ResourceManager::pathsWithAddOns() == std::vector<std::string>{ "ext/cxx.oxp" });
		cxx::ResourceManager::reset();
		cxx::ResourceManager::clearCaches();
	}
}


// --- bead oo-he11: slice 2 (OXP manifests: validation, requirements, conflicts, dependencies, scenarios) ---
// A scan of a scratch game folder whose only add-ons are fixtures the test writes: every root the
// scan reads (the built-in data, the managed, extract and additional add-on folders, <cwd>/AddOns)
// is under the scratch folder, set before the first ResourceManager call by ScratchGameFolder.

namespace {

void WriteText(const std::filesystem::path &path, const std::string &text)
{
	std::filesystem::create_directories(path.parent_path());
	OO_CHECK(oo::fs::writeFile(path, oo::Data(text.data(), text.size()), oo::fs::WriteMode::direct).has_value());
}


oo::PList Manifest(const char *text)
{
	auto result = oo::parsePropertyList(text);
	OO_CHECK(result.has_value());
	return result ? *result : oo::PList();
}


bool EndsWith(const std::string &s, const std::string &suffix)
{
	return s.size() >= suffix.size() && s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

}	// namespace


OO_TEST(versionsAndCompatibility)
{
	@autoreleasepool
	{
		const oo::PList range = Manifest("{ version = \"1.0\"; maximum_version = \"2.0\"; }");
		OO_CHECK([ResourceManager cxx_matchVersions:range withVersion:"1.5"]);
		OO_CHECK([ResourceManager cxx_matchVersions:range withVersion:"1.0"]);
		OO_CHECK([ResourceManager cxx_matchVersions:range withVersion:"2.0"]);
		OO_CHECK(![ResourceManager cxx_matchVersions:range withVersion:"0.9"]);
		OO_CHECK(![ResourceManager cxx_matchVersions:range withVersion:"2.0.1"]);
		OO_CHECK([ResourceManager cxx_matchVersions:Manifest("{}") withVersion:""]);
		OO_CHECK(![ResourceManager cxx_matchVersions:Manifest("{ version = \"1\"; }") withVersion:""]);

		// The game's version is the scratch Info-gnustep.plist's, 9.9.9.
		OO_CHECK([ResourceManager cxx_checkVersionCompatibility:Manifest("{ required_oolite_version = \"1.80\"; }") forOXP:"t"]);
		OO_CHECK(![ResourceManager cxx_checkVersionCompatibility:Manifest("{ required_oolite_version = \"10.0\"; }") forOXP:"t"]);
		OO_CHECK(![ResourceManager cxx_checkVersionCompatibility:Manifest("{ required_oolite_version = \"1.0\"; maximum_oolite_version = \"9.0\"; }") forOXP:"t"]);
		OO_CHECK([ResourceManager cxx_checkVersionCompatibility:Manifest("{ required_oolite_version = \"1.0\"; maximum_oolite_version = \"\"; }") forOXP:std::nullopt]);
		OO_CHECK([ResourceManager cxx_checkVersionCompatibility:Manifest("{}") forOXP:"t"]);	// nothing required
	}
}


OO_TEST(scanKeepsTheAddOnsWhoseManifestsAllowThem)
{
	@autoreleasepool
	{
		const std::filesystem::path addOns = std::filesystem::current_path() / "AddOns";
		WriteText(addOns / "a.oxp" / "manifest.plist", "{ identifier = \"org.test.a\"; version = \"1.0\"; required_oolite_version = \"1.0\"; title = A; tags = (alpha); }");
		WriteText(addOns / "a.oxp" / "OXPMessages.plist", "( \"hello from a\" )");
		WriteText(addOns / "b.oxp" / "manifest.plist", "{ identifier = \"org.test.b\"; version = \"1.0\"; required_oolite_version = \"1.0\"; title = B; requires_oxps = ( { identifier = \"org.test.a\"; version = \"2.0\"; } ); }");
		WriteText(addOns / "c.oxp" / "manifest.plist", "{ identifier = \"org.test.c\"; version = \"1.0\"; required_oolite_version = \"1.0\"; title = C; conflict_oxps = ( { identifier = \"org.test.a\"; } ); }");
		WriteText(addOns / "d.oxp" / "manifest.plist", "{ identifier = \"org.test.d\"; version = \"1.0\"; required_oolite_version = \"99.0\"; title = D; }");
		WriteText(addOns / "e.oxp" / "manifest.plist", "{ identifier = \"org.test.e\"; version = \"1.0\"; required_oolite_version = \"1.0\"; }");
		WriteText(addOns / "f.oxp" / "manifest.plist", "{ identifier = \"org.test.f\"; version = \"1.0\"; required_oolite_version = \"1.0\"; title = F; tags = (\"oolite-scenario-only\"); }");
		WriteText(addOns / "g.oxp" / "requires.plist", "{ version = \"99\"; }");
		WriteText(addOns / "h.oxp" / "manifest.plist", "{ identifier = \"org.test.h\"; version = \"3.0\"; required_oolite_version = \"1.0\"; title = H; requires_oxps = ( { identifier = \"org.test.a\"; } ); }");

		[ResourceManager reset];
		const std::vector<std::string> paths = [ResourceManager cxx_paths];
		for (const std::string &path : paths)  std::printf("  search path: %s\n", path.c_str());
		bool sawA = false, sawH = false, sawOther = false;
		for (const std::string &path : paths)
		{
			if (EndsWith(path, "a.oxp"))  sawA = true;
			else if (EndsWith(path, "h.oxp"))  sawH = true;
			else if (EndsWith(path, ".oxp"))  sawOther = true;
		}
		OO_CHECK(sawA && sawH && !sawOther);
		OO_CHECK([ResourceManager cxx_useAddOns] == std::optional<std::string>(""));	// the scan chose "all"

		const oo::PList a = [ResourceManager cxx_manifestForIdentifier:"org.test.a"];
		OO_CHECK(a.isDict() && EndsWith(a.get<std::string>("file_path"), "a.oxp"));
		OO_CHECK(a.find("required_by") != nullptr && a.find("required_by")->count() == 1);	// h requires it
		OO_CHECK([ResourceManager cxx_manifestForIdentifier:"org.test.b"].isNull());
		OO_CHECK([ResourceManager cxx_manifestForIdentifier:"org.test.c"].isNull());
		OO_CHECK([ResourceManager cxx_manifestForIdentifier:"org.test.f"].isNull());
		OO_CHECK([ResourceManager cxx_OXPsWithMessagesFound] == std::vector<std::string>{ "a.oxp" });

		// With a in the list, c's conflict and b's requirement are seen again (not logged).
		const oo::PList c = Manifest("{ identifier = \"org.test.c\"; title = C; conflict_oxps = ( { identifier = \"org.test.a\"; } ); }");
		OO_CHECK([ResourceManager cxx_manifestHasConflicts:c logErrors:NO]);
		OO_CHECK(![ResourceManager cxx_manifestHasConflicts:Manifest("{ conflict_oxps = ( { identifier = \"org.test.zz\"; } ); }") logErrors:NO]);
		const oo::PList b = Manifest("{ identifier = \"org.test.b\"; title = B; requires_oxps = ( { identifier = \"org.test.a\"; version = \"2.0\"; } ); }");
		OO_CHECK([ResourceManager cxx_manifestHasMissingDependencies:b logErrors:NO]);
		OO_CHECK([ResourceManager cxx_manifest:b HasUnmetDependency:Manifest("{ identifier = \"org.test.a\"; version = \"2.0\"; }") logErrors:NO]);
		OO_CHECK(![ResourceManager cxx_manifest:b HasUnmetDependency:Manifest("{ identifier = \"org.test.a\"; }") logErrors:NO]);
		OO_CHECK(![ResourceManager cxx_manifestHasMissingDependencies:Manifest("{}") logErrors:NO]);

		// The rejections were recorded; with no universe their texts are empty, and reading them clears them.
		const std::optional<std::string> errors = [ResourceManager cxx_errors];
		OO_CHECK(errors == std::optional<std::string>(""));
		OO_CHECK([ResourceManager cxx_errors] == std::nullopt);

		[ResourceManager reset];
	}
}


OO_TEST(cxxSlice2API)
{
	@autoreleasepool
	{
		const oo::PList range = Manifest("{ version = \"1.0\"; maximum_version = \"2.0\"; }");
		OO_CHECK(cxx::ResourceManager::matchVersions(range, "1.5"));
		OO_CHECK(!cxx::ResourceManager::matchVersions(range, "3"));
		OO_CHECK(cxx::ResourceManager::checkVersionCompatibility(Manifest("{ required_oolite_version = \"1.0\"; }"), "t"));
		OO_CHECK(!cxx::ResourceManager::checkVersionCompatibility(Manifest("{ required_oolite_version = \"10.0\"; }"), std::nullopt));
		OO_CHECK(!cxx::ResourceManager::manifestHasConflicts(Manifest("{}"), false));
		OO_CHECK(!cxx::ResourceManager::manifestHasMissingDependencies(Manifest("{}"), false));
		OO_CHECK(cxx::ResourceManager::manifest(Manifest("{ title = X; }"), Manifest("{ identifier = \"org.test.none\"; }"), false));
		OO_CHECK([ResourceManager cxx_matchVersions:range withVersion:"1.5"] == cxx::ResourceManager::matchVersions(range, "1.5"));
	}
}


// --- bead oo-elve: slice 3 (plist loading and merging, the configuration dictionaries) ---
// Over the scratch game folder of slice 2's test: the built-in data and two fixture add-ons, a.oxp
// and h.oxp (both kept by the scan), each with Config plists that the test writes. No cache:
// every load is asked with the cache off, or for a file name no other test loads.

OO_TEST(mergedPlistsFromTheSearchPaths)
{
	@autoreleasepool
	{
		namespace stdfs = std::filesystem;
		const stdfs::path work = stdfs::current_path();
		WriteText(work / "Resources" / "Config" / "oo-test-dict.plist", "{ base = 1; shared = { x = 1; y = 1; }; list = (a); }");
		WriteText(work / "AddOns" / "a.oxp" / "Config" / "oo-test-dict.plist", "{ fromA = 2; shared = { y = 2; z = 2; }; list = (b); }");
		WriteText(work / "AddOns" / "h.oxp" / "Config" / "oo-test-dict.plist", "{ fromH = 3; }");
		WriteText(work / "Resources" / "Config" / "oo-test-array.plist", "( one, two )");
		WriteText(work / "AddOns" / "a.oxp" / "Config" / "oo-test-array.plist", "( three )");
		WriteText(work / "Resources" / "Config" / "role-categories.plist", "{ oolite-trader = ( trader, \"trader-courier\" ); }");
		WriteText(work / "AddOns" / "a.oxp" / "Config" / "role-categories.plist", "{ oolite-trader = ( trader, \"a-trader\" ); oolite-test = ( tester ); }");
		WriteText(work / "Resources" / "Config" / "pirate-victim-roles.plist", "( trader, courier )");
		WriteText(work / "Resources" / "Config" / "logcontrol.plist", "{ \"oo-test.base\" = yes; \"oo-test.overridden\" = no; }");
		WriteText(work / "AddOns" / "a.oxp" / "Config" / "logcontrol.plist", "{ \"oo-test.overridden\" = yes; \"oo-test.fromA\" = no; }");

		[ResourceManager reset];
		const std::vector<std::string> paths = [ResourceManager cxx_paths];
		OO_CHECK(paths.size() >= 2);

		// MERGE_NONE: the last file in search order; MERGE_BASIC: top-level keys; MERGE_SMART: second level.
		const oo::PList last = [ResourceManager cxx_dictionaryFromFilesNamed:"oo-test-dict.plist" inFolder:std::string("Config") mergeMode:MERGE_NONE cache:NO];
		std::printf("  MERGE_NONE: %s\n", oo::DescriptionOf(last).c_str());
		const oo::PList basic = [ResourceManager cxx_dictionaryFromFilesNamed:"oo-test-dict.plist" inFolder:std::string("Config") mergeMode:MERGE_BASIC cache:NO];
		std::printf("  MERGE_BASIC: %s\n", oo::DescriptionOf(basic).c_str());
		const oo::PList smart = [ResourceManager cxx_dictionaryFromFilesNamed:"oo-test-dict.plist" inFolder:std::string("Config") mergeMode:MERGE_SMART cache:NO];
		std::printf("  MERGE_SMART: %s\n", oo::DescriptionOf(smart).c_str());
		OO_CHECK(basic.find("base") != nullptr && basic.find("fromA") != nullptr && basic.find("fromH") != nullptr);
		OO_CHECK(smart.find("shared") != nullptr && smart.find("shared")->find("x") != nullptr && smart.find("shared")->find("z") != nullptr);
		OO_CHECK([ResourceManager cxx_dictionaryFromFilesNamed:"oo-test-none.plist" inFolder:std::string("Config") andMerge:YES].isNull());

		const oo::PList array = [ResourceManager cxx_arrayFromFilesNamed:"oo-test-array.plist" inFolder:std::string("Config") andMerge:YES cache:NO];
		std::printf("  array merged: %s\n", oo::DescriptionOf(array).c_str());
		OO_CHECK(array.isArray());
		const oo::PList arrayLast = [ResourceManager cxx_arrayFromFilesNamed:"oo-test-array.plist" inFolder:std::string("Config") andMerge:NO cache:NO];
		std::printf("  array last: %s\n", oo::DescriptionOf(arrayLast).c_str());
		OO_CHECK([ResourceManager cxx_arrayFromFilesNamed:"oo-test-none.plist" inFolder:std::string("Config") andMerge:YES].isNull());

		// The built-in path is not excluded for a core plist; an add-on is, unless it overrides it.
		OO_CHECK(![ResourceManager cxx_corePlist:"oo-test-dict.plist" excludedAt:*[ResourceManager cxx_builtInPath]]);

		const oo::PList roles = [ResourceManager cxx_roleCategoriesDictionary];
		std::printf("  role categories: %s\n", oo::DescriptionOf(roles).c_str());
		OO_CHECK(roles.isDict() && roles.find("oolite-trader") != nullptr && roles.find("oolite-test") != nullptr);

		const oo::PList logControl = [ResourceManager cxx_logControlDictionary];
		OO_CHECK(logControl.isDict());
		std::printf("  log control oo-test.*: base=%s overridden=%s fromA=%s\n",
					logControl.find("oo-test.base") ? oo::DescriptionOf(*logControl.find("oo-test.base")).c_str() : "-",
					logControl.find("oo-test.overridden") ? oo::DescriptionOf(*logControl.find("oo-test.overridden")).c_str() : "-",
					logControl.find("oo-test.fromA") ? oo::DescriptionOf(*logControl.find("oo-test.fromA")).c_str() : "-");

		OO_CHECK([ResourceManager cxx_whitelistDictionary].isNull());	// no whitelist.plist in the scratch data
	}
}


OO_TEST(equipmentAndStarListMerging)
{
	@autoreleasepool
	{
		// Equipment lists: an entry of an earlier file whose key (index 3) a later file also has is
		// replaced by the later one.
		oo::PList lists(oo::PList::Array{
			oo::PList(oo::PList::Array{
				oo::PList(oo::PList::Array{ oo::PList(1), oo::PList(10), oo::PList("Old"), oo::PList("EQ_A") }),
				oo::PList(oo::PList::Array{ oo::PList(1), oo::PList(10), oo::PList("Keep"), oo::PList("EQ_B") }) }),
			oo::PList(oo::PList::Array{
				oo::PList(oo::PList::Array{ oo::PList(2), oo::PList(20), oo::PList("New"), oo::PList("EQ_A") }) }) });
		[ResourceManager handleEquipmentListMerging:lists forLookupIndex:3];
		std::printf("  equipment lists merged: %s\n", oo::DescriptionOf(lists).c_str());
		OO_CHECK(lists.at(0) != nullptr && lists.at(0)->at(0) != nullptr && lists.at(0)->at(0)->at<std::string>(2) == "New");
		OO_CHECK(lists.at(0) != nullptr && lists.at(0)->at(1) != nullptr && lists.at(0)->at(1)->at<std::string>(2) == "Keep");

		// Star and nebula lists: the same by the entry itself (or a dictionary's key / texture).
		oo::PList stars(oo::PList::Array{
			oo::PList(oo::PList::Array{ oo::PList("star1.png"), oo::PList(oo::PList::Dict{ { "key", oo::PList("k") }, { "texture", oo::PList("old.png") } }) }),
			oo::PList(oo::PList::Array{ oo::PList(oo::PList::Dict{ { "key", oo::PList("k") }, { "texture", oo::PList("new.png") } }) }) });
		[ResourceManager handleStarNebulaListMerging:stars];
		std::printf("  star lists merged: %s\n", oo::DescriptionOf(stars).c_str());
		OO_CHECK(stars.at(0) != nullptr && stars.at(0)->at(1) != nullptr && stars.at(0)->at(1)->get<std::string>("texture") == "new.png");

		// No equipment-overrides.plist: the lists are unchanged.
		oo::PList equipment(oo::PList::Array{ oo::PList(oo::PList::Array{ oo::PList(1), oo::PList(10), oo::PList("Name"), oo::PList("EQ_A") }) });
		const oo::PList before = equipment;
		[ResourceManager handleEquipmentOverrides:equipment];
		OO_CHECK(oo::DescriptionOf(equipment) == oo::DescriptionOf(before));
	}
}


OO_TEST(cxxSlice3API)
{
	@autoreleasepool
	{
		OO_CHECK(cxx::ResourceManager::dictionaryFromFilesNamed("oo-test-dict.plist", std::string("Config"), MERGE_BASIC, false).find("fromA") != nullptr);
		OO_CHECK(cxx::ResourceManager::dictionaryFromFilesNamed("oo-test-none.plist", std::string("Config"), true).isNull());
		OO_CHECK(cxx::ResourceManager::arrayFromFilesNamed("oo-test-array.plist", std::string("Config"), true, false).isArray());
		OO_CHECK(!cxx::ResourceManager::corePlist("oo-test-dict.plist", *cxx::ResourceManager::builtInPath()));
		OO_CHECK(cxx::ResourceManager::whitelistDictionary().isNull());
		OO_CHECK(cxx::ResourceManager::roleCategoriesDictionary().isDict());
		OO_CHECK(cxx::ResourceManager::logControlDictionary().isDict());
	}
}


// --- bead oo-5dzou: slice 4 (file lookup, sounds, music, strings, scripts, diagnostics) ---
// Over the same scratch game folder.

OO_TEST(singleFileLookups)
{
	@autoreleasepool
	{
		namespace stdfs = std::filesystem;
		const stdfs::path work = stdfs::current_path();
		WriteText(work / "Resources" / "Config" / "oo-test-text.txt", "hello, built-in");
		WriteText(work / "AddOns" / "a.oxp" / "Config" / "oo-test-text.txt", "hello, a.oxp");
		WriteText(work / "Resources" / "oo-test-loose.txt", "loose");
		[ResourceManager reset];
		(void)[ResourceManager cxx_paths];

		// The last search path that has the file (an add-on overrides the built-in data), with the
		// folder, else without it; nullopt when no path has it.
		const std::optional<std::string> path = [ResourceManager cxx_pathForFileNamed:"oo-test-text.txt" inFolder:std::string("Config") cache:NO];
		OO_CHECK(path.has_value() && EndsWith(*path, "a.oxp/Config/oo-test-text.txt"));
		const std::optional<std::string> loose = [ResourceManager cxx_pathForFileNamed:"oo-test-loose.txt" inFolder:std::string("Config") cache:NO];
		OO_CHECK(loose.has_value() && EndsWith(*loose, "Resources/oo-test-loose.txt"));
		OO_CHECK([ResourceManager cxx_pathForFileNamed:"oo-test-missing.txt" inFolder:std::string("Config")] == std::nullopt);
		OO_CHECK([ResourceManager cxx_pathForFileNamed:"oo-test-text.txt" inFolder:std::nullopt cache:NO] == std::nullopt);

		OO_CHECK([ResourceManager cxx_stringFromFilesNamed:"oo-test-text.txt" inFolder:std::string("Config")] == std::optional<std::string>("hello, a.oxp"));
		OO_CHECK([ResourceManager cxx_stringFromFilesNamed:"oo-test-missing.txt" inFolder:std::string("Config") cache:NO] == std::nullopt);

		// No such sound or music file: nil.
		OO_CHECK([ResourceManager cxx_ooSoundNamed:"oo-test-missing.ogg" inFolder:std::string("Sounds")] == nil);
		OO_CHECK([ResourceManager cxx_ooMusicNamed:"oo-test-missing.ogg" inFolder:std::string("Music")] == nil);

		// No shader-uniform-bindings.plist and no material-defaults.plist in the scratch data.
		OO_CHECK([ResourceManager cxx_shaderBindingTypesDictionary].isNull());
		OO_CHECK([ResourceManager cxx_materialDefaults].isNull());
	}
}


OO_TEST(scriptsAndSystemsAndDiagnostics)
{
	@autoreleasepool
	{
		// No add-on has world scripts.
		OO_CHECK([ResourceManager cxx_loadScripts].empty());

		// No planetinfo.plist: a manager with nothing set, made anew on each call.
		OOSystemDescriptionManager *manager = [ResourceManager systemDescriptionManager];
		OO_CHECK(manager != nil);
		OO_CHECK(manager != [ResourceManager systemDescriptionManager]);

		// Diagnostics go under the log folder, which is under the scratch home.
		const std::optional<std::string> logs = [ResourceManager cxx_diagnosticFileLocation];
		std::printf("  diagnostics at: %s\n", logs ? logs->c_str() : "(none)");
		if (logs.has_value())
		{
			OO_CHECK([ResourceManager cxx_writeDiagnosticString:"diagnostic text" toFileNamed:"oo-test/.hidden/note.txt"]);
			const auto written = oo::fs::readFile(oo::fs::pathFromUTF8(*logs) / "oo-test" / "!hidden" / "note.txt");
			OO_CHECK(written.has_value() && std::string(written->stringView()) == "diagnostic text");
			OO_CHECK([ResourceManager cxx_writeDiagnosticPList:oo::PList(oo::PList::Dict{ { "k", oo::PList("v") } }) toFileNamed:"oo-test-plist.plist"]);
		}
	}
}


OO_TEST(cxxSlice4API)
{
	@autoreleasepool
	{
		OO_CHECK(cxx::ResourceManager::stringFromFilesNamed("oo-test-text.txt", std::string("Config")) == std::optional<std::string>("hello, a.oxp"));
		OO_CHECK(cxx::ResourceManager::pathForFileNamed("oo-test-missing.txt", std::string("Config"), false) == std::nullopt);
		OO_CHECK(cxx::ResourceManager::ooSoundNamed("oo-test-missing.ogg", std::string("Sounds")) == nil);
		OO_CHECK(cxx::ResourceManager::shaderBindingTypesDictionary().isNull());
		OO_CHECK(cxx::ResourceManager::loadScripts().empty());
		OO_CHECK(cxx::ResourceManager::systemDescriptionManager().get() != nullptr);
		OO_CHECK(cxx::ResourceManager::diagnosticFileLocation() == [ResourceManager cxx_diagnosticFileLocation]);
		// The facade answers the new manager's facade.
		OOSystemDescriptionManager *manager = [ResourceManager systemDescriptionManager];
		OO_CHECK(manager != nil && oo::ToCxx(manager) != nullptr);
	}
}


OO_TEST_MAIN()
