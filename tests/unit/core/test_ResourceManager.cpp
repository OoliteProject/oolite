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
	conversion the class was a C++ class (static members) behind an Objective-C facade; the
	last test checked that the C++ API answered the same. Bead oo-9ht.150 deleted the facade: every
	send is now the static member it forwarded to, with the same expectations.

	ResourceManager.mm reaches the universe, the HUD, the OXZ manager and the scripts, so the test
	links every game object but main's (tests/unit/core/meson.build entry ['*'], ADR-0056 amendment
	oo-44gg) and defines gDebugFlags. UNIVERSE is nil.
	Bead oo-he11 (slice 2: the OXP manifests) runs the tests in a scratch game folder (see
	ScratchGameFolder) and adds a scan of fixture add-ons whose manifests the slice accepts or rejects.
	Run: bash tools/check-core-tests.sh test_ResourceManager
*/

#include "ResourceManager.h"
#include "OOALMusic.h"
#include "OODescription.h"
#include "OOSystemDescriptionManager.h"

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
	{
		OO_CHECK(ResourceManager::useAddOns() == std::nullopt);
		OO_CHECK(ResourceManager::errors() == std::nullopt);
		OO_CHECK(ResourceManager::OXPsWithMessagesFound().empty());
		OO_CHECK(ResourceManager::manifestForIdentifier("org.test.none").isNull());
		ResourceManager::clearCaches();
	}
}


OO_TEST(rootPathsAreTheResourcePaths)
{
	{
		const oo::ResourcePaths paths = oo::ResourcePaths::current();
		const std::string builtIn = oo::fs::utf8String(paths.builtInResourcesDirectory());
		OO_CHECK(ResourceManager::builtInPath() == std::optional<std::string>(builtIn));

		std::vector<std::string> userRoots;
		for (const oo::fs::Path &path : paths.userRootDirectories())  userRoots.push_back(oo::fs::utf8String(path));
		OO_CHECK(ResourceManager::userRootPaths() == userRoots);

		const std::vector<std::string> roots = ResourceManager::rootPaths();
		OO_CHECK_EQ(roots.size(), userRoots.size() + 2);
		OO_CHECK(roots.size() >= 2 && roots[0] == builtIn);
		OO_CHECK(roots.size() >= 2 && roots[1] == oo::fs::utf8String(paths.managedAddOnsDirectory()));
		OO_CHECK(roots.size() >= 2 && std::vector<std::string>(roots.begin() + 2, roots.end()) == userRoots);
		OO_CHECK(ResourceManager::rootPaths() == roots);	// computed once
	}
}


OO_TEST(maskUserName)
{
	{
		OO_CHECK(ResourceManager::maskUserName("jon", "C:/Users/jon/AddOns") == std::optional<std::string>("C:/Users/*/AddOns"));
		OO_CHECK(ResourceManager::maskUserName("jon", "/home/jon/jon.oxp") == std::optional<std::string>("/home/*/*.oxp"));
		OO_CHECK(ResourceManager::maskUserName("jon", "/srv/oolite") == std::optional<std::string>("/srv/oolite"));
		OO_CHECK(ResourceManager::maskUserName("jon", "") == std::optional<std::string>(""));

		// The array form masks the name of the user running the game, in every path.
		const std::string user = UserName();
		if (!user.empty())
		{
			const std::vector<std::string> masked = ResourceManager::maskUserNameInPathArray({ "/a/" + user + "/b", "/c/d" });
			OO_CHECK(masked == (std::vector<std::string>{ "/a/*/b", "/c/d" }));
		}
		OO_CHECK(ResourceManager::maskUserNameInPathArray({}).empty());
	}
}


OO_TEST(externalPathsAreTheSearchPathsWithoutAScan)
{
	{
		ResourceManager::addExternalPath("ext/one.oxp");
		ResourceManager::addExternalPath("ext/two.oxp");
		ResourceManager::addExternalPath("ext/one.oxp");	// already there
		const std::vector<std::string> expected{ "ext/one.oxp", "ext/two.oxp" };
		OO_CHECK(ResourceManager::paths() == expected);
		OO_CHECK(ResourceManager::pathsWithAddOns() == expected);
		OO_CHECK(ResourceManager::useAddOns() == std::nullopt);	// no scan, so no selection

		// -reset forgets them (the next -cxx_paths would scan again, which the test does not do).
		ResourceManager::reset();
		OO_CHECK(ResourceManager::useAddOns() == std::nullopt);
		OO_CHECK(ResourceManager::errors() == std::nullopt);
		ResourceManager::addExternalPath("ext/three.oxp");
		OO_CHECK(ResourceManager::paths() == std::vector<std::string>{ "ext/three.oxp" });
		ResourceManager::reset();
	}
}


OO_TEST(cxxAPIAnswersTheSame)
{
	{
		// The static members (the facade that forwarded to them went with bead oo-9ht.150).
		OO_CHECK(ResourceManager::builtInPath() == ResourceManager::builtInPath());
		OO_CHECK(ResourceManager::rootPaths() == ResourceManager::rootPaths());
		OO_CHECK(ResourceManager::userRootPaths() == ResourceManager::userRootPaths());
		OO_CHECK(ResourceManager::maskUserName("jon", "/home/jon") == std::optional<std::string>("/home/*"));
		OO_CHECK(ResourceManager::useAddOns() == std::nullopt);
		OO_CHECK(ResourceManager::errors() == std::nullopt);
		OO_CHECK(ResourceManager::manifestForIdentifier("org.test.none").isNull());
		OO_CHECK(ResourceManager::OXPsWithMessagesFound().empty());
		ResourceManager::addExternalPath("ext/cxx.oxp");
		OO_CHECK(ResourceManager::paths() == std::vector<std::string>{ "ext/cxx.oxp" });
		OO_CHECK(ResourceManager::paths() == std::vector<std::string>{ "ext/cxx.oxp" });
		OO_CHECK(ResourceManager::pathsWithAddOns() == std::vector<std::string>{ "ext/cxx.oxp" });
		ResourceManager::reset();
		ResourceManager::clearCaches();
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
	{
		const oo::PList range = Manifest("{ version = \"1.0\"; maximum_version = \"2.0\"; }");
		OO_CHECK(ResourceManager::matchVersions(range, "1.5"));
		OO_CHECK(ResourceManager::matchVersions(range, "1.0"));
		OO_CHECK(ResourceManager::matchVersions(range, "2.0"));
		OO_CHECK(!ResourceManager::matchVersions(range, "0.9"));
		OO_CHECK(!ResourceManager::matchVersions(range, "2.0.1"));
		OO_CHECK(ResourceManager::matchVersions(Manifest("{}"), ""));
		OO_CHECK(!ResourceManager::matchVersions(Manifest("{ version = \"1\"; }"), ""));

		// The game's version is the scratch Info-gnustep.plist's, 9.9.9.
		OO_CHECK(ResourceManager::checkVersionCompatibility(Manifest("{ required_oolite_version = \"1.80\"; }"), "t"));
		OO_CHECK(!ResourceManager::checkVersionCompatibility(Manifest("{ required_oolite_version = \"10.0\"; }"), "t"));
		OO_CHECK(!ResourceManager::checkVersionCompatibility(Manifest("{ required_oolite_version = \"1.0\"; maximum_oolite_version = \"9.0\"; }"), "t"));
		OO_CHECK(ResourceManager::checkVersionCompatibility(Manifest("{ required_oolite_version = \"1.0\"; maximum_oolite_version = \"\"; }"), std::nullopt));
		OO_CHECK(ResourceManager::checkVersionCompatibility(Manifest("{}"), "t"));	// nothing required
	}
}


OO_TEST(scanKeepsTheAddOnsWhoseManifestsAllowThem)
{
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

		ResourceManager::reset();
		const std::vector<std::string> paths = ResourceManager::paths();
		for (const std::string &path : paths)  std::printf("  search path: %s\n", path.c_str());
		bool sawA = false, sawH = false, sawOther = false;
		for (const std::string &path : paths)
		{
			if (EndsWith(path, "a.oxp"))  sawA = true;
			else if (EndsWith(path, "h.oxp"))  sawH = true;
			else if (EndsWith(path, ".oxp"))  sawOther = true;
		}
		OO_CHECK(sawA && sawH && !sawOther);
		OO_CHECK(ResourceManager::useAddOns() == std::optional<std::string>(""));	// the scan chose "all"

		const oo::PList a = ResourceManager::manifestForIdentifier("org.test.a");
		OO_CHECK(a.isDict() && EndsWith(a.get<std::string>("file_path"), "a.oxp"));
		OO_CHECK(a.find("required_by") != nullptr && a.find("required_by")->count() == 1);	// h requires it
		OO_CHECK(ResourceManager::manifestForIdentifier("org.test.b").isNull());
		OO_CHECK(ResourceManager::manifestForIdentifier("org.test.c").isNull());
		OO_CHECK(ResourceManager::manifestForIdentifier("org.test.f").isNull());
		OO_CHECK(ResourceManager::OXPsWithMessagesFound() == std::vector<std::string>{ "a.oxp" });

		// With a in the list, c's conflict and b's requirement are seen again (not logged).
		const oo::PList c = Manifest("{ identifier = \"org.test.c\"; title = C; conflict_oxps = ( { identifier = \"org.test.a\"; } ); }");
		OO_CHECK(ResourceManager::manifestHasConflicts(c, NO));
		OO_CHECK(!ResourceManager::manifestHasConflicts(Manifest("{ conflict_oxps = ( { identifier = \"org.test.zz\"; } ); }"), NO));
		const oo::PList b = Manifest("{ identifier = \"org.test.b\"; title = B; requires_oxps = ( { identifier = \"org.test.a\"; version = \"2.0\"; } ); }");
		OO_CHECK(ResourceManager::manifestHasMissingDependencies(b, NO));
		OO_CHECK(ResourceManager::manifest(b, Manifest("{ identifier = \"org.test.a\"; version = \"2.0\"; }"), NO));
		OO_CHECK(!ResourceManager::manifest(b, Manifest("{ identifier = \"org.test.a\"; }"), NO));
		OO_CHECK(!ResourceManager::manifestHasMissingDependencies(Manifest("{}"), NO));

		// The rejections were recorded; with no universe their texts are empty, and reading them clears them.
		const std::optional<std::string> errors = ResourceManager::errors();
		OO_CHECK(errors == std::optional<std::string>(""));
		OO_CHECK(ResourceManager::errors() == std::nullopt);

		ResourceManager::reset();
	}
}


OO_TEST(cxxSlice2API)
{
	{
		const oo::PList range = Manifest("{ version = \"1.0\"; maximum_version = \"2.0\"; }");
		OO_CHECK(ResourceManager::matchVersions(range, "1.5"));
		OO_CHECK(!ResourceManager::matchVersions(range, "3"));
		OO_CHECK(ResourceManager::checkVersionCompatibility(Manifest("{ required_oolite_version = \"1.0\"; }"), "t"));
		OO_CHECK(!ResourceManager::checkVersionCompatibility(Manifest("{ required_oolite_version = \"10.0\"; }"), std::nullopt));
		OO_CHECK(!ResourceManager::manifestHasConflicts(Manifest("{}"), false));
		OO_CHECK(!ResourceManager::manifestHasMissingDependencies(Manifest("{}"), false));
		OO_CHECK(ResourceManager::manifest(Manifest("{ title = X; }"), Manifest("{ identifier = \"org.test.none\"; }"), false));
		OO_CHECK(ResourceManager::matchVersions(range, "1.5") == ResourceManager::matchVersions(range, "1.5"));
	}
}


// --- bead oo-elve: slice 3 (plist loading and merging, the configuration dictionaries) ---
// Over the scratch game folder of slice 2's test: the built-in data and two fixture add-ons, a.oxp
// and h.oxp (both kept by the scan), each with Config plists that the test writes. No cache:
// every load is asked with the cache off, or for a file name no other test loads.

OO_TEST(mergedPlistsFromTheSearchPaths)
{
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

		ResourceManager::reset();
		const std::vector<std::string> paths = ResourceManager::paths();
		OO_CHECK(paths.size() >= 2);

		// MERGE_NONE: the last file in search order; MERGE_BASIC: top-level keys; MERGE_SMART: second level.
		const oo::PList last = ResourceManager::dictionaryFromFilesNamed("oo-test-dict.plist", std::string("Config"), MERGE_NONE, NO);
		std::printf("  MERGE_NONE: %s\n", oo::DescriptionOf(last).c_str());
		const oo::PList basic = ResourceManager::dictionaryFromFilesNamed("oo-test-dict.plist", std::string("Config"), MERGE_BASIC, NO);
		std::printf("  MERGE_BASIC: %s\n", oo::DescriptionOf(basic).c_str());
		const oo::PList smart = ResourceManager::dictionaryFromFilesNamed("oo-test-dict.plist", std::string("Config"), MERGE_SMART, NO);
		std::printf("  MERGE_SMART: %s\n", oo::DescriptionOf(smart).c_str());
		OO_CHECK(basic.find("base") != nullptr && basic.find("fromA") != nullptr && basic.find("fromH") != nullptr);
		OO_CHECK(smart.find("shared") != nullptr && smart.find("shared")->find("x") != nullptr && smart.find("shared")->find("z") != nullptr);
		OO_CHECK(ResourceManager::dictionaryFromFilesNamed("oo-test-none.plist", std::string("Config"), YES).isNull());

		const oo::PList array = ResourceManager::arrayFromFilesNamed("oo-test-array.plist", std::string("Config"), YES, NO);
		std::printf("  array merged: %s\n", oo::DescriptionOf(array).c_str());
		OO_CHECK(array.isArray());
		const oo::PList arrayLast = ResourceManager::arrayFromFilesNamed("oo-test-array.plist", std::string("Config"), NO, NO);
		std::printf("  array last: %s\n", oo::DescriptionOf(arrayLast).c_str());
		OO_CHECK(ResourceManager::arrayFromFilesNamed("oo-test-none.plist", std::string("Config"), YES).isNull());

		// The built-in path is not excluded for a core plist; an add-on is, unless it overrides it.
		OO_CHECK(!ResourceManager::corePlist("oo-test-dict.plist", *ResourceManager::builtInPath()));

		const oo::PList roles = ResourceManager::roleCategoriesDictionary();
		std::printf("  role categories: %s\n", oo::DescriptionOf(roles).c_str());
		OO_CHECK(roles.isDict() && roles.find("oolite-trader") != nullptr && roles.find("oolite-test") != nullptr);

		const oo::PList logControl = ResourceManager::logControlDictionary();
		OO_CHECK(logControl.isDict());
		std::printf("  log control oo-test.*: base=%s overridden=%s fromA=%s\n",
					logControl.find("oo-test.base") ? oo::DescriptionOf(*logControl.find("oo-test.base")).c_str() : "-",
					logControl.find("oo-test.overridden") ? oo::DescriptionOf(*logControl.find("oo-test.overridden")).c_str() : "-",
					logControl.find("oo-test.fromA") ? oo::DescriptionOf(*logControl.find("oo-test.fromA")).c_str() : "-");

		OO_CHECK(ResourceManager::whitelistDictionary().isNull());	// no whitelist.plist in the scratch data
	}
}


OO_TEST(equipmentAndStarListMerging)
{
	{
		// Equipment lists: an entry of an earlier file whose key (index 3) a later file also has is
		// replaced by the later one.
		oo::PList lists(oo::PList::Array{
			oo::PList(oo::PList::Array{
				oo::PList(oo::PList::Array{ oo::PList(1), oo::PList(10), oo::PList("Old"), oo::PList("EQ_A") }),
				oo::PList(oo::PList::Array{ oo::PList(1), oo::PList(10), oo::PList("Keep"), oo::PList("EQ_B") }) }),
			oo::PList(oo::PList::Array{
				oo::PList(oo::PList::Array{ oo::PList(2), oo::PList(20), oo::PList("New"), oo::PList("EQ_A") }) }) });
		ResourceManager::handleEquipmentListMerging(lists, 3);
		std::printf("  equipment lists merged: %s\n", oo::DescriptionOf(lists).c_str());
		OO_CHECK(lists.at(0) != nullptr && lists.at(0)->at(0) != nullptr && lists.at(0)->at(0)->at<std::string>(2) == "New");
		OO_CHECK(lists.at(0) != nullptr && lists.at(0)->at(1) != nullptr && lists.at(0)->at(1)->at<std::string>(2) == "Keep");

		// Star and nebula lists: the same by the entry itself (or a dictionary's key / texture).
		oo::PList stars(oo::PList::Array{
			oo::PList(oo::PList::Array{ oo::PList("star1.png"), oo::PList(oo::PList::Dict{ { "key", oo::PList("k") }, { "texture", oo::PList("old.png") } }) }),
			oo::PList(oo::PList::Array{ oo::PList(oo::PList::Dict{ { "key", oo::PList("k") }, { "texture", oo::PList("new.png") } }) }) });
		ResourceManager::handleStarNebulaListMerging(stars);
		std::printf("  star lists merged: %s\n", oo::DescriptionOf(stars).c_str());
		OO_CHECK(stars.at(0) != nullptr && stars.at(0)->at(1) != nullptr && stars.at(0)->at(1)->get<std::string>("texture") == "new.png");

		// No equipment-overrides.plist: the lists are unchanged.
		oo::PList equipment(oo::PList::Array{ oo::PList(oo::PList::Array{ oo::PList(1), oo::PList(10), oo::PList("Name"), oo::PList("EQ_A") }) });
		const oo::PList before = equipment;
		ResourceManager::handleEquipmentOverrides(equipment);
		OO_CHECK(oo::DescriptionOf(equipment) == oo::DescriptionOf(before));
	}
}


OO_TEST(cxxSlice3API)
{
	{
		OO_CHECK(ResourceManager::dictionaryFromFilesNamed("oo-test-dict.plist", std::string("Config"), MERGE_BASIC, false).find("fromA") != nullptr);
		OO_CHECK(ResourceManager::dictionaryFromFilesNamed("oo-test-none.plist", std::string("Config"), true).isNull());
		OO_CHECK(ResourceManager::arrayFromFilesNamed("oo-test-array.plist", std::string("Config"), true, false).isArray());
		OO_CHECK(!ResourceManager::corePlist("oo-test-dict.plist", *ResourceManager::builtInPath()));
		OO_CHECK(ResourceManager::whitelistDictionary().isNull());
		OO_CHECK(ResourceManager::roleCategoriesDictionary().isDict());
		OO_CHECK(ResourceManager::logControlDictionary().isDict());
	}
}


// --- bead oo-5dzou: slice 4 (file lookup, sounds, music, strings, scripts, diagnostics) ---
// Over the same scratch game folder.

OO_TEST(singleFileLookups)
{
	{
		namespace stdfs = std::filesystem;
		const stdfs::path work = stdfs::current_path();
		WriteText(work / "Resources" / "Config" / "oo-test-text.txt", "hello, built-in");
		WriteText(work / "AddOns" / "a.oxp" / "Config" / "oo-test-text.txt", "hello, a.oxp");
		WriteText(work / "Resources" / "oo-test-loose.txt", "loose");
		ResourceManager::reset();
		(void)ResourceManager::paths();

		// The last search path that has the file (an add-on overrides the built-in data), with the
		// folder, else without it; nullopt when no path has it.
		const std::optional<std::string> path = ResourceManager::pathForFileNamed("oo-test-text.txt", std::string("Config"), NO);
		OO_CHECK(path.has_value() && EndsWith(*path, "a.oxp/Config/oo-test-text.txt"));
		const std::optional<std::string> loose = ResourceManager::pathForFileNamed("oo-test-loose.txt", std::string("Config"), NO);
		OO_CHECK(loose.has_value() && EndsWith(*loose, "Resources/oo-test-loose.txt"));
		OO_CHECK(ResourceManager::pathForFileNamed("oo-test-missing.txt", std::string("Config")) == std::nullopt);
		OO_CHECK(ResourceManager::pathForFileNamed("oo-test-text.txt", std::nullopt, NO) == std::nullopt);

		OO_CHECK(ResourceManager::stringFromFilesNamed("oo-test-text.txt", std::string("Config")) == std::optional<std::string>("hello, a.oxp"));
		OO_CHECK(ResourceManager::stringFromFilesNamed("oo-test-missing.txt", std::string("Config"), NO) == std::nullopt);

		// No such sound or music file: nil.
		OO_CHECK(ResourceManager::ooSoundNamed("oo-test-missing.ogg", std::string("Sounds")) == nil);
		OO_CHECK(!ResourceManager::ooMusicNamed("oo-test-missing.ogg", std::string("Music")));

		// No shader-uniform-bindings.plist and no material-defaults.plist in the scratch data.
		OO_CHECK(ResourceManager::shaderBindingTypesDictionary().isNull());
		OO_CHECK(ResourceManager::materialDefaults().isNull());
	}
}


OO_TEST(scriptsAndSystemsAndDiagnostics)
{
	{
		// No add-on has world scripts.
		OO_CHECK(ResourceManager::loadScripts().empty());

		// No planetinfo.plist: a manager with nothing set, made anew on each call.
		oo::Ref<OOSystemDescriptionManager> manager = ResourceManager::systemDescriptionManager();
		OO_CHECK(manager != nullptr);
		OO_CHECK(manager != ResourceManager::systemDescriptionManager());

		// Diagnostics go under the log folder, which is under the scratch home.
		const std::optional<std::string> logs = ResourceManager::diagnosticFileLocation();
		std::printf("  diagnostics at: %s\n", logs ? logs->c_str() : "(none)");
		if (logs.has_value())
		{
			OO_CHECK(ResourceManager::writeDiagnosticString("diagnostic text", "oo-test/.hidden/note.txt"));
			const auto written = oo::fs::readFile(oo::fs::pathFromUTF8(*logs) / "oo-test" / "!hidden" / "note.txt");
			OO_CHECK(written.has_value() && std::string(written->stringView()) == "diagnostic text");
			OO_CHECK(ResourceManager::writeDiagnosticPList(oo::PList(oo::PList::Dict{ { "k", oo::PList("v") } }), "oo-test-plist.plist"));
		}
	}
}


OO_TEST(cxxSlice4API)
{
	{
		OO_CHECK(ResourceManager::stringFromFilesNamed("oo-test-text.txt", std::string("Config")) == std::optional<std::string>("hello, a.oxp"));
		OO_CHECK(ResourceManager::pathForFileNamed("oo-test-missing.txt", std::string("Config"), false) == std::nullopt);
		OO_CHECK(ResourceManager::ooSoundNamed("oo-test-missing.ogg", std::string("Sounds")) == nil);
		OO_CHECK(ResourceManager::shaderBindingTypesDictionary().isNull());
		OO_CHECK(ResourceManager::loadScripts().empty());
		OO_CHECK(ResourceManager::systemDescriptionManager().get() != nullptr);
		OO_CHECK(ResourceManager::diagnosticFileLocation() == ResourceManager::diagnosticFileLocation());
		// A new C++ manager (bead oo-9ht.32 deleted the manager's facade).
		oo::Ref<OOSystemDescriptionManager> manager = ResourceManager::systemDescriptionManager();
		OO_CHECK(manager != nullptr);
	}
}


/*	Bead oo-31u.9: ooSoundNamed() goes through the sound cache. A sound found is kept by the cache
	and answered borrowed; a missing one is nil. Neither reaches retrieveFileNamed()'s uncached
	oo::autorelease with an object, so nothing waits for a scope's drain, and nothing is counted as
	autoreleased without a scope, whether or not a scope is open.
*/
OO_TEST(soundLookupHandsNothingToTheScope)
{
	const std::size_t leaked = oo::AutoreleaseScope::leakedWithoutScope();
	{
		oo::AutoreleaseScope scope;
		OO_CHECK(ResourceManager::ooSoundNamed("oo-test-missing.ogg", std::string("Sounds")) == nil);
		OO_CHECK(scope.pendingCount() == 0);
	}
	OO_CHECK(oo::AutoreleaseScope::current() == nullptr);
	OO_CHECK(ResourceManager::ooSoundNamed("oo-test-missing.ogg", std::string("Sounds")) == nil);
	OO_CHECK(oo::AutoreleaseScope::leakedWithoutScope() == leaked);
}


OO_TEST_MAIN()
