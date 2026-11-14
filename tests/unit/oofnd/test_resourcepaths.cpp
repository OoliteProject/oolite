/*	test_resourcepaths.cpp
	Unit tests for oofnd/ResourcePaths.hpp (bead oo-i9q): oo::ResourcePaths, checked against the
	paths the Objective-C code computes today (NSHomeDirectory() under GNUstep, SDL/main.mm's
	HOMEPATH, NSFileManagerOOExtensions, OOLogOutputHandler, OOOXZManager, ResourceManager),
	for both the Windows and the POSIX rules, driven by a fake environment.
*/

#include "oofnd/ResourcePaths.hpp"

#include "oo_test.hpp"

#include <map>
#include <optional>
#include <string>
#include <system_error>
#include <vector>

namespace {

namespace fs = oo::fs;
using Platform = oo::PathEnvironment::Platform;

// Paths compare element-wise: "a/b" and "a\\b" are the same path on Windows, and
// lexically_normal() folds the "x/../y" the Objective-C code also leaves in.
bool same(const fs::Path& a, const fs::Path& b)
{
	return a.lexically_normal() == b.lexically_normal();
}

oo::ResourcePaths make(Platform platform, std::map<std::string, std::string> vars, fs::Path cwd, bool userFolder = false)
{
	oo::PathEnvironment env;
	env.platform = platform;
	env.getenv = [vars](const std::string& name) -> std::optional<std::string> {
		auto it = vars.find(name);
		if (it == vars.end())  return std::nullopt;
		return it->second;
	};
	env.currentDirectory = std::move(cwd);
	env.gameDataToUserFolder = userFolder;
	return oo::ResourcePaths(std::move(env));
}

const std::string kExeDir = "C:/Games/Oolite/oolite.app";

// What SDL/main.mm leaves in the environment on Windows: HOMEPATH is the executable's directory.
oo::ResourcePaths windowsGame(std::map<std::string, std::string> extra = {})
{
	std::map<std::string, std::string> vars{
		{"HOMEPATH", kExeDir},
		{"HOMEDRIVE", "C:"},
		{"USERPROFILE", "C:/Users/commander"},
		{"LOCALAPPDATA", "C:/Users/commander/AppData/Local"},
	};
	for (auto& [k, v] : extra)  vars[k] = v;
	return make(Platform::windows, vars, fs::pathFromUTF8(kExeDir));
}

} // namespace

OO_TEST(windowsHomeIsHomepathWhenItHasADrive)
{
	OO_CHECK(same(windowsGame().homeDirectory(), "C:/Games/Oolite/oolite.app"));
	// Spelled as GNUstep spells NSHomeDirectory() (probed on gnustep-base 1.31), even from a
	// backslashed HOMEPATH.
	auto p = make(Platform::windows, {{"HOMEPATH", "C:\\Games\\X"}}, "C:/x");
	OO_CHECK_EQ(fs::utf8String(p.homeDirectory()), std::string("C:/Games/X"));
	OO_CHECK_EQ(fs::utf8String(p.saveDirectory()), std::string("C:/Games/X/oolite-saves"));
	OO_CHECK_EQ(fs::utf8String(p.applicationSupportDirectory()), std::string("C:/Games/X/GNUstep/Library/ApplicationSupport"));
}

OO_TEST(windowsHomeGetsHomedrivePrefixedWhenHomepathHasNoDrive)
{
	auto p = make(Platform::windows, {{"HOMEPATH", "\\Users\\commander"}, {"HOMEDRIVE", "D:"}}, "C:/x");
	OO_CHECK_EQ(fs::utf8String(p.homeDirectory()), std::string("D:/Users/commander"));   // GNUstep's spelling
}

OO_TEST(windowsHomeFallsBackToUserprofileThenCwd)
{
	OO_CHECK(same(make(Platform::windows, {{"USERPROFILE", "C:/Users/c"}}, "C:/x").homeDirectory(), "C:/Users/c"));
	OO_CHECK(same(make(Platform::windows, {}, "C:/x").homeDirectory(), "C:/x"));
}

OO_TEST(posixHomeIsHomeThenCwd)
{
	OO_CHECK(same(make(Platform::posix, {{"HOME", "/home/c"}, {"HOMEPATH", "/ignored"}}, "/cwd").homeDirectory(), "/home/c"));
	OO_CHECK(same(make(Platform::posix, {}, "/cwd").homeDirectory(), "/cwd"));
}

OO_TEST(windowsUserDirectoriesLiveNextToTheExecutable)
{
	const auto p = windowsGame();
	OO_CHECK(same(p.saveDirectory(), kExeDir + "/oolite-saves"));
	OO_CHECK(same(p.snapshotDirectory(), kExeDir + "/oolite-saves/snapshots"));
	OO_CHECK(same(p.logDirectory(), kExeDir + "/Logs"));
	OO_CHECK(same(p.userLibraryDirectory(), kExeDir + "/GNUstep/Library"));
	OO_CHECK(same(p.cachesDirectory(), kExeDir + "/GNUstep/Library/Caches"));
	OO_CHECK(same(p.applicationSupportDirectory(), kExeDir + "/GNUstep/Library/ApplicationSupport"));
	OO_CHECK(same(p.managedAddOnsDirectory(), kExeDir + "/GNUstep/Library/ApplicationSupport/Oolite/ManagedAddOns"));
}

OO_TEST(windowsExtractDirectoryIsRelativeUnlessGameDataGoesToTheUserFolder)
{
	OO_CHECK_EQ(fs::utf8String(windowsGame().extractAddOnsDirectory()), std::string("../AddOns"));
	auto userFolder = make(Platform::windows, {{"LOCALAPPDATA", "C:/Users/c/AppData/Local"}}, "C:/x", true);
	OO_CHECK(same(userFolder.extractAddOnsDirectory(), "C:/Users/c/AppData/Local/Oolite/AddOns"));
}

OO_TEST(posixUserDirectories)
{
	const auto p = make(Platform::posix, {{"HOME", "/home/c"}}, "/opt/oolite/bin");
	OO_CHECK(same(p.saveDirectory(), "/home/c/oolite-saves"));
	OO_CHECK(same(p.snapshotDirectory(), "/home/c/oolite-saves/snapshots"));
	OO_CHECK(same(p.logDirectory(), "/home/c/.Oolite/Logs"));
	OO_CHECK(same(p.extractAddOnsDirectory(), "/home/c/.Oolite/AddOns"));
	OO_CHECK(same(p.managedAddOnsDirectory(), "/home/c/GNUstep/Library/ApplicationSupport/Oolite/ManagedAddOns"));
}

OO_TEST(environmentOverridesWinVerbatim)
{
	const auto p = windowsGame({
		{"OO_SAVEDIR", "E:/saves"},
		{"OO_SNAPSHOTSDIR", "E:/shots"},
		{"OO_LOGSDIR", "E:/logs"},
		{"OO_MANAGEDADDONSDIR", "E:/managed"},
		{"OO_ADDONSEXTRACTDIR", "E:/extract"},
	});
	OO_CHECK_EQ(fs::utf8String(p.saveDirectory()), std::string("E:/saves"));
	OO_CHECK_EQ(fs::utf8String(p.snapshotDirectory()), std::string("E:/shots"));
	OO_CHECK_EQ(fs::utf8String(p.logDirectory()), std::string("E:/logs"));
	OO_CHECK_EQ(fs::utf8String(p.managedAddOnsDirectory()), std::string("E:/managed"));
	OO_CHECK_EQ(fs::utf8String(p.extractAddOnsDirectory()), std::string("E:/extract"));
	// Overriding the save directory does not move the snapshots (they have their own variable).
	const auto q = windowsGame({{"OO_SAVEDIR", "E:/saves"}});
	OO_CHECK(same(q.snapshotDirectory(), kExeDir + "/oolite-saves/snapshots"));
}

OO_TEST(additionalAddOnsSplitOnCommaKeepingEmptyComponents)
{
	OO_CHECK(windowsGame().additionalAddOnsDirectories().empty());
	const auto dirs = windowsGame({{"OO_ADDITIONALADDONSDIRS", "E:/a,,F:/b"}}).additionalAddOnsDirectories();
	OO_CHECK_EQ(dirs.size(), 3u);
	if (dirs.size() != 3)  return;
	OO_CHECK_EQ(fs::utf8String(dirs[0]), std::string("E:/a"));
	OO_CHECK(dirs[1].empty());
	OO_CHECK_EQ(fs::utf8String(dirs[2]), std::string("F:/b"));
}

OO_TEST(userRootsAreAdditionalThenShareThenCwdThenExtract)
{
	const auto roots = windowsGame({{"OO_ADDITIONALADDONSDIRS", "E:/extra"}}).userRootDirectories();
	OO_CHECK_EQ(roots.size(), 4u);
	if (roots.size() != 4)  return;
	OO_CHECK(same(roots[0], "E:/extra"));
	OO_CHECK(same(roots[1], "C:/Games/Oolite/share/oolite/AddOns"));
	OO_CHECK(same(roots[2], kExeDir + "/AddOns"));
	OO_CHECK_EQ(fs::utf8String(roots[3]), std::string("../AddOns"));
}

OO_TEST(builtInResourcesPreferCwdResourcesThenShare)
{
	std::error_code ec;
	const fs::Path base = std::filesystem::temp_directory_path(ec) / "oofnd-resourcepaths-test";
	std::filesystem::remove_all(base, ec);
	const fs::Path cwd = base / "bin";
	std::filesystem::create_directories(cwd, ec);

	const auto p = make(Platform::windows, {}, cwd);
	OO_CHECK(same(p.builtInResourcesDirectory(), base / "share" / "oolite" / "Resources"));

	std::filesystem::create_directories(cwd / "Resources", ec);
	OO_CHECK(same(p.builtInResourcesDirectory(), cwd / "Resources"));

	std::filesystem::remove_all(base, ec);
}

OO_TEST(rootDirectoriesAreBuiltInThenManagedThenUserRoots)
{
	const auto p = windowsGame();
	const auto roots = p.rootDirectories();
	const auto user = p.userRootDirectories();
	OO_CHECK_EQ(roots.size(), 2 + user.size());
	if (roots.size() != 2 + user.size())  return;
	OO_CHECK(same(roots[0], p.builtInResourcesDirectory()));
	OO_CHECK(same(roots[1], p.managedAddOnsDirectory()));
	for (std::size_t i = 0; i < user.size(); ++i)  OO_CHECK(roots[2 + i] == user[i]);
}

OO_TEST(processEnvironmentReadsTheRealEnvironment)
{
	const oo::PathEnvironment env = oo::PathEnvironment::process();
#if defined(_WIN32)
	OO_CHECK(env.platform == Platform::windows);
	OO_CHECK(env.getenv("SystemRoot").has_value());    // always set on Windows
#else
	OO_CHECK(env.platform == Platform::posix);
#endif
	OO_CHECK(env.getenv("OOFND_SURELY_UNSET_VARIABLE_1f3a") == std::nullopt);
	OO_CHECK(!env.currentDirectory.empty());
	OO_CHECK(same(env.currentDirectory, fs::currentDirectory().value_or(fs::Path())));

	// current() is the same computation over process().
	OO_CHECK(same(oo::ResourcePaths::current().saveDirectory(), oo::ResourcePaths(env).saveDirectory()));
}

OO_TEST_MAIN()
