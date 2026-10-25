/*	test_OOOXZManager.mm
	Unit tests for OOOXZManager (src/Core/OOOXZManager.h): bead oo-bwjb, slice 1 of the Phase 3
	slice plan docs/phases/3-slices/OOOXZManager.md (the class shell: state, paths, filters,
	manifests and the download plumbing), in the house style of the OOColor exemplar (proposed
	ADR-0056).

	The manager is a process-wide singleton (amendment oo-r7m0) that keeps the list of OXZ
	manifests, the managed OXZs on disk, a filter over the list, and one download. The test points
	the user's home (HOMEPATH: the caches and the defaults), the managed, extract and additional
	add-on folders, and the built-in Resources (the current directory) at a scratch folder before
	the singleton exists, so nothing of the user's is read or written. Every manifest is synthetic,
	written by the test; no expansion is read. The one download is a file: URL (oofnd/Http.hpp),
	so no network is used.

	It pins what the manager computed before the conversion: the shared instance and the list it
	loads from the manifest cache, sorted; the paths; the filters and their validation; the human
	size; the managed OXZs read from disk and matched against the list; a manifest download from
	start to finish (the list replaced, the cache rewritten, the temporary file removed, the
	managed list rebuilt), and the requests it then refuses. The expectations were written
	against the Objective-C API and run on the unconverted class first. Bead oo-9ht.131 deleted the
	Objective-C facade: every case asks the C++ singleton with every expectation kept, and the
	facade's contract cases (one facade for the singleton, identity both ways, nil and null, the
	forwarded private units) retired under the standing approval oo-9n5p9.
	Run: bash tools/check-core-tests.sh test_OOOXZManager
*/

#include "OOOXZManager.h"
#include "OOCacheManager.h"
#include "ResourceManager.h"
#include "OOManifestProperties.h"
#include "OOXMLExtensions.h"
#include "OOPListParsing.h"
#include "OOColor.h"

#include "oofnd/Date.hpp"
#include "oofnd/Defaults.hpp"
#include "oofnd/FileSystem.hpp"
#include "oofnd/PListParsing.hpp"
#include "oofnd/ResourcePaths.hpp"
#include "oofnd/String.hpp"
#include "oo_test.hpp"
#include "PlayerEntity.h"	// the stand-in PLAYER (bead oo-vdw34)
extern PlayerEntity *gOOPlayer;

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <process.h>
#include <string>
#include <thread>
#include <vector>


// main.mm's global, which the game's objects reference (the test links all of them but main's).
uint32_t gDebugFlags = 0;


// A text check that prints what it got.
static void CheckText(const std::string &actual, const std::string &expected, const char *text, int line)
{
	if (actual != expected)  std::printf("  got \"%s\", expected \"%s\"\n", actual.c_str(), expected.c_str());
	::oo_test::check(actual == expected, text, __FILE__, line);
}

#define OO_CHECK_TEXT(actual, expected) CheckText((actual), (expected), #actual " == " #expected, __LINE__)


namespace {

namespace stdfs = std::filesystem;

stdfs::path sRoot;


void WriteText(const stdfs::path &path, const std::string &text)
{
	stdfs::create_directories(path.parent_path());
	FILE *file = std::fopen(path.string().c_str(), "wb");
	if (file == nullptr)  return;
	std::fwrite(text.data(), 1, text.size(), file);
	std::fclose(file);
}


std::string Generic(const stdfs::path &path)
{
	return path.generic_string();
}


void SetEnv(const char *name, const std::string &value)
{
	OO_CHECK(::_putenv_s(name, value.c_str()) == 0);
}


oo::PList Manifest(const char *identifier, const char *title, const char *version, const char *category, const char *author, const char *description, std::vector<std::string> tags, long long uploadDate, const char *downloadURL)
{
	oo::PList::Dict entries;
	entries[std::string(kOOManifestIdentifier)] = oo::PList(identifier);
	entries[std::string(kOOManifestTitle)] = oo::PList(title);
	entries[std::string(kOOManifestVersion)] = oo::PList(version);
	entries[std::string(kOOManifestCategory)] = oo::PList(category);
	if (author != nullptr)  entries[std::string(kOOManifestAuthor)] = oo::PList(author);
	if (description != nullptr)  entries[std::string(kOOManifestDescription)] = oo::PList(description);
	if (!tags.empty())
	{
		oo::PList::Array array;
		for (const std::string &tag : tags)  array.push_back(oo::PList(tag));
		entries[std::string(kOOManifestTags)] = oo::PList(std::move(array));
	}
	if (uploadDate >= 0)  entries[std::string(kOOManifestUploadDate)] = oo::PList(uploadDate);
	if (downloadURL != nullptr)  entries[std::string(kOOManifestDownloadURL)] = oo::PList(downloadURL);
	return oo::PList(std::move(entries));
}


stdfs::path CacheDirectory()
{
	return sRoot / "GNUstep" / "Library" / "Caches" / "org.aegidian.oolite";
}


// PLAYER (bead oo-vdw34): the debug build asserts it is set (OOGetPlayer()), so the manager's GUI page,
// which asks it to let go of its sounds (Windows), has a player; its viewpoint is the origin. Never released, as the player is not.
class TestPlayer : public PlayerEntity
{
public:
	HPVector viewpointPosition() override	{ return kZeroHPVector; }
};


void SetUpTestPlayer()
{
	static TestPlayer *player = nullptr;
	if (player == nullptr)
	{
		oo::Ref<TestPlayer> made = oo::makeRef<TestPlayer>();
		{
			oo::RetainEntity(oo::MadeEntity(made));	// +1, as PlayerEntity::sharedPlayer() makes the game's
		}
		player = made.get();
	}
	gOOPlayer = player;
}


// The scratch home, add-on folders and game folder, and the manifest cache the manager loads,
// made once, before the singleton exists.
void SetUp()
{
	SetUpTestPlayer();
	if (!sRoot.empty())  return;
	sRoot = stdfs::temp_directory_path() / ("oo-test-oxzmanager-" + std::to_string(static_cast<unsigned long>(::_getpid())));
	stdfs::remove_all(sRoot);
	stdfs::create_directories(sRoot);
	SetEnv("HOMEPATH", sRoot.string());
	SetEnv("OO_MANAGEDADDONSDIR", Generic(sRoot / "Managed"));
	SetEnv("OO_ADDONSEXTRACTDIR", Generic(sRoot / "Extract"));
	SetEnv("OO_ADDITIONALADDONSDIRS", Generic(sRoot / "More1") + ",," + Generic(sRoot / "More2"));
	stdfs::current_path(sRoot);
	WriteText(sRoot / "Resources" / "Info-gnustep.plist", "{ CFBundleVersion = \"1.91\"; CFBundleName = \"oolite\"; }");

	const long long now = static_cast<long long>(oo::date::timeIntervalSince1970());
	oo::PList::Array cached;
	cached.push_back(Manifest("oolite.oxp.test.zeta", "Zeta", "1.0", "Ships", "Ann Author", "A fast ship\nwith a second line", { "fast", "combat" }, now - 86400, "file:///nowhere/zeta.oxz"));
	cached.push_back(Manifest("oolite.oxp.test.alpha", "Alpha", "1.5", "Ships", "Bob Builder", "Cobra variants", { "ships" }, now - 10 * 86400, "file:///nowhere/alpha-1.5.oxz"));
	cached.push_back(Manifest("oolite.oxp.test.alpha", "Alpha", "2.0", "Ships", "Bob Builder", "Cobra variants", { "ships" }, now - 10 * 86400, "file:///nowhere/alpha-2.0.oxz"));
	cached.push_back(Manifest("oolite.oxp.test.mission", "Mission", "0.1", "Missions", "Ann Author", "A mission", { "story" }, 0, nullptr));
	stdfs::create_directories(CacheDirectory());
	OO_CHECK(OOWriteXMLPListToFile(oo::PList(std::move(cached)), Generic(CacheDirectory() / "Oolite-manifests.plist"), nullptr));
}


std::string Str(const oo::PList &manifest, std::string_view key)
{
	const oo::PList *value = manifest.find(key);
	if (value == nullptr)  return "-";
	const std::string *string = value->getIf<std::string>();
	return (string != nullptr) ? *string : "?";
}


// "title version" for each manifest of an Array, space-joined ("" for none, "null" for null).
std::string Titles(const oo::PList &list)
{
	if (list.isNull())  return "null";
	std::string result;
	if (const oo::PList::Array *array = list.getIf<oo::PList::Array>())
	{
		for (const oo::PList &manifest : *array)
		{
			if (!result.empty())  result += ", ";
			result += Str(manifest, kOOManifestTitle) + " " + Str(manifest, kOOManifestVersion);
		}
	}
	return result;
}


// The manager's private API (the units of slice 1 the facade did not declare): its C++ members.
OOOXZManager *Manager()								{ return OOOXZManager::sharedManager(); }
std::optional<std::string> ManifestPath()					{ return Manager()->manifestPath(); }
std::optional<std::string> DownloadPath()					{ return Manager()->downloadPath(); }
std::optional<std::string> ExtractionBase(const std::string &identifier, const std::string &version)	{ return Manager()->extractionBasePathForIdentifier(identifier, version); }
std::optional<std::string> DataURL()						{ return Manager()->dataURL(); }
std::optional<std::string> HumanSize(NSUInteger bytes)		{ return Manager()->humanSize(bytes); }
bool EnsureInstallPath()									{ return Manager()->ensureInstallPath(); }
bool ValidateFilter(const std::string &input)				{ return Manager()->validateFilter(input); }

std::string Filtered(const std::string &filter)
{
	Manager()->setFilter(filter);
	return Titles(Manager()->applyCurrentFilter(Manager()->manifests()));
}

}	// namespace


OO_TEST(sharedManagerLoadsTheCachedListSorted)
{
	SetUp();
	{
		OOOXZManager *manager = OOOXZManager::sharedManager();
		OO_CHECK(manager != nullptr);
		OO_CHECK(OOOXZManager::sharedManager() == manager);
		// category, then title, then version descending
		OO_CHECK_TEXT(Titles(manager->manifests()), "Mission 0.1, Alpha 2.0, Alpha 1.5, Zeta 1.0");
		OO_CHECK(!manager->isRestarting());
		// Nothing to cancel, and no download to deliver.
		OO_CHECK(!manager->cancelUpdate());
		manager->processDownloadEvents();
		OO_CHECK_TEXT(Titles(manager->manifests()), "Mission 0.1, Alpha 2.0, Alpha 1.5, Zeta 1.0");
	}
}


OO_TEST(paths)
{
	SetUp();
	{
		OOOXZManager *manager = OOOXZManager::sharedManager();
		OO_CHECK_EQ(manager->installPath().value_or("(none)"), Generic(sRoot / "Managed"));
		OO_CHECK_EQ(manager->extractAddOnsPath().value_or("(none)"), Generic(sRoot / "Extract"));
		const std::vector<std::string> additional = manager->additionalAddOnsPaths();
		OO_CHECK_EQ(additional.size(), 3u);
		if (additional.size() == 3)
		{
			OO_CHECK_EQ(additional[0], Generic(sRoot / "More1"));
			OO_CHECK_EQ(additional[1], "");
			OO_CHECK_EQ(additional[2], Generic(sRoot / "More2"));
		}

		const std::string cacheDirectory = OOCacheManager::sharedCache()->cacheDirectoryPathCreatingIfNecessary(true).value_or("(none)");
		OO_CHECK_EQ(ManifestPath().value_or("(none)"), oo::str::appendingPathComponent(cacheDirectory, "Oolite-manifests.plist"));
		OO_CHECK_EQ(DownloadPath().value_or("(none)"), oo::str::appendingPathComponent(cacheDirectory, "Oolite-download.oxz"));

		// The extraction folder: the last user root, the blacklisted characters removed.
		const std::vector<std::string> roots = ResourceManager::userRootPaths();
		OO_CHECK(!roots.empty());
		if (!roots.empty())
		{
			OO_CHECK_EQ(ExtractionBase("oolite.oxp.test:alpha", "1.0 beta/2#").value_or("(none)"), oo::str::appendingPathComponent(roots.back(), "oolite.oxp.testalpha-1.0beta2.off"));
		}

		// The install folder is made when missing, and refused when it is a file.
		OO_CHECK(!stdfs::exists(sRoot / "Managed"));
		OO_CHECK(EnsureInstallPath());
		OO_CHECK(stdfs::is_directory(sRoot / "Managed"));
		OO_CHECK(EnsureInstallPath());
		WriteText(sRoot / "AFile", "x");
		SetEnv("OO_MANAGEDADDONSDIR", Generic(sRoot / "AFile"));
		OO_CHECK(!EnsureInstallPath());
		SetEnv("OO_MANAGEDADDONSDIR", Generic(sRoot / "Managed"));

		OO_CHECK_EQ(DataURL().value_or("(none)"), "https://addons.oolite.space/api/1.0/overview");
	}
}


OO_TEST(humanSizeAndFilterValidation)
{
	SetUp();
	{
		// The missing-field description; with no Universe the description lookup answers its key.
		OO_CHECK_EQ(HumanSize(0).value_or("(none)"), "oolite-oxzmanager-missing-field");
		OO_CHECK_EQ(HumanSize(1).value_or("(none)"), "<1 kB");
		OO_CHECK_EQ(HumanSize(1023).value_or("(none)"), "<1 kB");
		OO_CHECK_EQ(HumanSize(1024).value_or("(none)"), "1 kB");
		OO_CHECK_EQ(HumanSize(1048575).value_or("(none)"), "1023 kB");
		OO_CHECK_EQ(HumanSize(1048576).value_or("(none)"), "1.00 MB");
		OO_CHECK_EQ(HumanSize(1572864).value_or("(none)"), "1.50 MB");

		const char *valid[] = { "", "*", "u", "i", "U", "k:x", "A:x", "d:5", "t:a", "c:b", "k: " };
		for (const char *filter : valid)  { if (!ValidateFilter(filter))  std::printf("  valid filter refused: \"%s\"\n", filter);  OO_CHECK(ValidateFilter(filter)); }
		const char *invalid[] = { "k:", "a:", "d:0", "d:x", "d:-1", "t:", "c:", "x", "**", "ux" };
		for (const char *filter : invalid)  { if (ValidateFilter(filter))  std::printf("  invalid filter accepted: \"%s\"\n", filter);  OO_CHECK(!ValidateFilter(filter)); }
	}
}


OO_TEST(filters)
{
	SetUp();
	{
		OO_CHECK_TEXT(Filtered("*"), "Mission 0.1, Alpha 2.0, Alpha 1.5, Zeta 1.0");
		OO_CHECK_TEXT(Filtered("K:cobra"), "Alpha 2.0, Alpha 1.5");
		OO_CHECK_TEXT(Filtered("k:  FAST"), "Zeta 1.0");
		OO_CHECK_TEXT(Filtered("k:"), "Mission 0.1, Alpha 2.0, Alpha 1.5, Zeta 1.0");
		OO_CHECK_TEXT(Filtered("a:ann"), "Mission 0.1, Zeta 1.0");
		OO_CHECK_TEXT(Filtered("c:miss"), "Mission 0.1");
		OO_CHECK_TEXT(Filtered("t:comb"), "Zeta 1.0");
		OO_CHECK_TEXT(Filtered("t:nothing"), "");
		OO_CHECK_TEXT(Filtered("d:3"), "Zeta 1.0");
		OO_CHECK_TEXT(Filtered("d:30"), "Alpha 2.0, Alpha 1.5, Zeta 1.0");
		OO_CHECK_TEXT(Filtered("d:0"), "");
		OO_CHECK_TEXT(Filtered("zzz"), "Mission 0.1, Alpha 2.0, Alpha 1.5, Zeta 1.0");
		// A null list filters to an empty one.
		OO_CHECK_TEXT(Titles(Manager()->applyCurrentFilter(oo::PList())), "");
		Manager()->setFilter("*");
	}
}


OO_TEST(managedOXZs)
{
	SetUp();
	{
		// Two managed OXZs (synthetic manifests), and a stray file with none.
		WriteText(sRoot / "Managed" / "alpha.oxp" / "manifest.plist", "{ identifier = \"oolite.oxp.test.alpha\"; title = Alpha; version = \"1.0\"; category = Ships; }");
		WriteText(sRoot / "Managed" / "local.oxp" / "manifest.plist", "{ identifier = \"oolite.oxp.test.local\"; title = Local; version = \"3\"; category = Ambience; }");
		WriteText(sRoot / "Managed" / "stray.txt", "not a manifest");

		const oo::PList managed = OOOXZManager::sharedManager()->managedOXZs();
		OO_CHECK_TEXT(Titles(managed), "Local 3, Alpha 1.0");
		const oo::PList::Array *array = managed.getIf<oo::PList::Array>();
		OO_CHECK(array != nullptr && array->size() == 2);
		if (array != nullptr && array->size() == 2)
		{
			const oo::PList &local = (*array)[0];
			const oo::PList &alpha = (*array)[1];
			OO_CHECK_EQ(Str(local, kOOManifestFilePath), oo::str::appendingPathComponent(Generic(sRoot / "Managed"), "local.oxp"));
			OO_CHECK_EQ(Str(local, kOOManifestAvailableVersion), "-");
			OO_CHECK_EQ(Str(local, kOOManifestDownloadURL), "-");
			OO_CHECK_EQ(Str(alpha, kOOManifestFilePath), oo::str::appendingPathComponent(Generic(sRoot / "Managed"), "alpha.oxp"));
			OO_CHECK_EQ(Str(alpha, kOOManifestAvailableVersion), "2.0");
			OO_CHECK_EQ(Str(alpha, kOOManifestDownloadURL), "file:///nowhere/alpha-2.0.oxz");
		}

		// Kept until the list changes.
		WriteText(sRoot / "Managed" / "late.oxp" / "manifest.plist", "{ identifier = \"oolite.oxp.test.late\"; title = Late; version = \"1\"; category = Ambience; }");
		OO_CHECK_TEXT(Titles(OOOXZManager::sharedManager()->managedOXZs()), "Local 3, Alpha 1.0");

		// The installable states (slice 2) decide these, from the managed OXZs.
		OO_CHECK_TEXT(Filtered("u"), "Alpha 2.0, Alpha 1.5");
		OO_CHECK_TEXT(Filtered("i"), "Mission 0.1, Alpha 2.0, Alpha 1.5, Zeta 1.0");
		Manager()->setFilter("*");
	}
}


OO_TEST(manifestDownload)
{
	SetUp();
	{
		OOOXZManager *manager = OOOXZManager::sharedManager();

		// The new index, served from a file: URL named by the oxz-index-url default (in memory
		// only: nothing synchronizes the defaults).
		oo::PList::Array index;
		index.push_back(Manifest("oolite.oxp.test.beta", "Beta", "1.0", "Ships", "Cy", "Beta ship", {}, -1, nullptr));
		index.push_back(Manifest("oolite.oxp.test.alpha", "Alpha", "3.0", "Ships", "Bob Builder", "Cobra variants", {}, -1, "file:///nowhere/alpha-3.0.oxz"));
		OO_CHECK(OOWriteXMLPListToFile(oo::PList(std::move(index)), Generic(sRoot / "index.plist"), nullptr));
		const std::string url = "file:///" + Generic(sRoot / "index.plist");
		oo::Defaults::standard().setObject("oxz-index-url", oo::PList(url));
		OO_CHECK_EQ(DataURL().value_or("(none)"), url);

		const std::string cacheDirectory = OOCacheManager::sharedCache()->cacheDirectoryPathCreatingIfNecessary(true).value_or("(none)");
		OO_CHECK(manager->updateManifests());
		OO_CHECK_EQ(DownloadPath().value_or("(none)"), oo::str::appendingPathComponent(cacheDirectory, "Oolite-download.plist"));
		// A second request while one is under way is refused.
		OO_CHECK(!manager->updateManifests());

		const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(20);
		while (Titles(manager->manifests()) != "Alpha 3.0, Beta 1.0" && std::chrono::steady_clock::now() < deadline)
		{
			manager->processDownloadEvents();
			std::this_thread::sleep_for(std::chrono::milliseconds(10));
		}
		OO_CHECK_TEXT(Titles(manager->manifests()), "Alpha 3.0, Beta 1.0");

		// The cache holds the new list, the temporary file is gone, and the managed list is rebuilt.
		const oo::PList cached = cxx_OOPropertyListFromFile(oo::str::appendingPathComponent(cacheDirectory, "Oolite-manifests.plist"));
		OO_CHECK_TEXT(Titles(cached), "Alpha 3.0, Beta 1.0");
		OO_CHECK(!stdfs::exists(stdfs::path(oo::str::appendingPathComponent(cacheDirectory, "Oolite-download.plist"))));
		const oo::PList managed = manager->managedOXZs();
		OO_CHECK_TEXT(Titles(managed), "Late 1, Local 3, Alpha 1.0");
		const oo::PList::Array *array = managed.getIf<oo::PList::Array>();
		if (array != nullptr && array->size() == 3)
		{
			OO_CHECK_EQ(Str((*array)[2], kOOManifestAvailableVersion), "3.0");
			OO_CHECK_EQ(Str((*array)[2], kOOManifestDownloadURL), "file:///nowhere/alpha-3.0.oxz");
		}

		// The download is complete: no new one starts, and there is nothing to cancel.
		OO_CHECK(!manager->updateManifests());
		OO_CHECK(!manager->cancelUpdate());
		OO_CHECK_EQ(DownloadPath().value_or("(none)"), oo::str::appendingPathComponent(cacheDirectory, "Oolite-download.oxz"));
	}
}


// Slice 2 (bead oo-0hyr): installing, updating, removing and extracting OXZs.
namespace {

// A stored (uncompressed) zip of the named files, written by hand: a synthetic OXZ.
uint32_t Crc32(const std::string &data)
{
	uint32_t crc = 0xFFFFFFFFu;
	for (unsigned char byte : data)
	{
		crc ^= byte;
		for (int k = 0; k < 8; k++)  crc = (crc >> 1) ^ (0xEDB88320u & (0u - (crc & 1u)));
	}
	return ~crc;
}


void Put16(std::string &out, unsigned value)  { out += static_cast<char>(value & 0xFF); out += static_cast<char>((value >> 8) & 0xFF); }
void Put32(std::string &out, uint32_t value)  { Put16(out, value & 0xFFFF); Put16(out, value >> 16); }


void WriteZip(const stdfs::path &path, const std::vector<std::pair<std::string, std::string>> &entries)
{
	std::string zip, directory;
	for (const auto &[name, data] : entries)
	{
		const uint32_t offset = static_cast<uint32_t>(zip.size()), crc = Crc32(data), size = static_cast<uint32_t>(data.size());
		Put32(zip, 0x04034b50); Put16(zip, 20); Put16(zip, 0); Put16(zip, 0); Put16(zip, 0); Put16(zip, 0x21);
		Put32(zip, crc); Put32(zip, size); Put32(zip, size); Put16(zip, static_cast<unsigned>(name.size())); Put16(zip, 0);
		zip += name; zip += data;
		Put32(directory, 0x02014b50); Put16(directory, 20); Put16(directory, 20); Put16(directory, 0); Put16(directory, 0);
		Put16(directory, 0); Put16(directory, 0x21); Put32(directory, crc); Put32(directory, size); Put32(directory, size);
		Put16(directory, static_cast<unsigned>(name.size())); Put16(directory, 0); Put16(directory, 0); Put16(directory, 0);
		Put16(directory, 0); Put32(directory, 0); Put32(directory, offset);
		directory += name;
	}
	const uint32_t directoryOffset = static_cast<uint32_t>(zip.size());
	zip += directory;
	Put32(zip, 0x06054b50); Put16(zip, 0); Put16(zip, 0); Put16(zip, static_cast<unsigned>(entries.size())); Put16(zip, static_cast<unsigned>(entries.size()));
	Put32(zip, static_cast<uint32_t>(directory.size())); Put32(zip, directoryOffset); Put16(zip, 0);
	WriteText(path, zip);
}


const char *kGammaManifest = "{ identifier = \"oolite.oxp.test.gamma\"; title = Gamma; version = \"1.0\"; category = Ships; }";


std::string ColorName(OOColor *c)
{
	if (c == nullptr)  return "nil";
	const std::pair<const char *, oo::Ref<OOColor>> named[] = {
		{ "yellow", OOColor::yellowColor() }, { "cyan", OOColor::cyanColor() }, { "orange", OOColor::orangeColor() },
		{ "brown", OOColor::brownColor() }, { "white", OOColor::whiteColor() }, { "red", OOColor::redColor() },
		{ "gray", OOColor::grayColor() }, { "blue", OOColor::blueColor() } };
	for (const auto &[name, n] : named)
	{
		if (n->redComponent() == c->redComponent() && n->greenComponent() == c->greenComponent() && n->blueComponent() == c->blueComponent())  return name;
	}
	return "other";
}


// The slice 2 units: their C++ members.
oo::PList InstalledManifest(const std::string &identifier)		{ return Manager()->installedManifestForIdentifier(identifier); }
std::string InstallStatus(const oo::PList &manifest)			{ return Manager()->installStatusForManifest(manifest).value_or("(none)"); }
std::string Color(const oo::PList &manifest)					{ return ColorName(Manager()->colorForManifest(manifest).get()); }
bool InstallOXZ(NSUInteger item)								{ return Manager()->installOXZ(item); }
bool UpdateAllOXZ()												{ return Manager()->updateAllOXZ(); }
bool RemoveOXZ(NSUInteger item)									{ return Manager()->removeOXZ(item); }
std::string ExtractOXZ(NSUInteger item)							{ return Manager()->extractOXZ(item); }
bool IsRestarting()												{ return OOOXZManager::sharedManager()->isRestarting(); }


// Deliver the download's events until it is no longer under way (at most 20 s).
void FinishDownload()
{
	const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(20);
	while ((Manager()->_downloadStatus == OXZ_DOWNLOAD_STARTED || Manager()->_downloadStatus == OXZ_DOWNLOAD_RECEIVING) && std::chrono::steady_clock::now() < deadline)
	{
		Manager()->processDownloadEvents();
		std::this_thread::sleep_for(std::chrono::milliseconds(10));
	}
}


std::string Element(const oo::PList &list, NSUInteger index)
{
	const oo::PList *element = list.at(index);
	return (element != nullptr) ? Str(*element, kOOManifestTitle) : "(none)";
}

}	// namespace


OO_TEST(installableStates)
{
	SetUp();
	{
		// The list holds Alpha 3.0 and Beta 1.0; Alpha 1.0 is managed.
		const oo::PList list = Manager()->manifests();
		OO_CHECK_TEXT(Titles(list), "Alpha 3.0, Beta 1.0");
		const oo::PList alpha = *list.at(0), beta = *list.at(1);
		OO_CHECK_TEXT(InstallStatus(alpha), "oolite-oxzmanager-installable-update");
		OO_CHECK_TEXT(InstallStatus(beta), "oolite-oxzmanager-installable-okay");
		OO_CHECK_TEXT(Color(alpha), "cyan");
		OO_CHECK_TEXT(Color(beta), "yellow");
		OO_CHECK_TEXT(Str(InstalledManifest("oolite.oxp.test.alpha"), kOOManifestVersion), "1.0");
		OO_CHECK(InstalledManifest("oolite.oxp.test.beta").isNull());
		OO_CHECK(!IsRestarting());
	}
}


OO_TEST(installExtractAndRemove)
{
	SetUp();
	{
		// A synthetic OXZ, offered in the list with a file: URL.
		WriteZip(sRoot / "gamma.oxz", { { "manifest.plist", kGammaManifest }, { "Config/notes.txt", "gamma notes" } });
		oo::PList::Array entries = *Manager()->manifests().getIf<oo::PList::Array>();
		auto parsed = oo::parsePropertyList(kGammaManifest);
		oo::PList gamma = parsed ? *parsed : oo::PList();
		gamma.getIf<oo::PList::Dict>()->insert_or_assign(std::string(kOOManifestDownloadURL), oo::PList("file:///" + Generic(sRoot / "gamma.oxz")));
		entries.push_back(gamma);
		Manager()->setOXZList(oo::PList(std::move(entries)));
		Manager()->setFilteredList(Manager()->manifests());
		OO_CHECK_TEXT(Titles(Manager()->manifests()), "Alpha 3.0, Beta 1.0, Gamma 1.0");
		Manager()->_downloadStatus = OXZ_DOWNLOAD_NONE;

		OO_CHECK(!InstallOXZ(3));
		OO_CHECK(InstallOXZ(2));
		OO_CHECK(Manager()->_interfaceState == OXZ_STATE_INSTALLING);
		OO_CHECK(!InstallOXZ(2));	// one download at a time
		FinishDownload();
		OO_CHECK(Manager()->_downloadStatus == OXZ_DOWNLOAD_COMPLETE);
		OO_CHECK(Manager()->_interfaceState == OXZ_STATE_TASKDONE);
		OO_CHECK(Manager()->_changesMade);
		OO_CHECK(Manager()->_dependencyStack.empty());
		OO_CHECK(stdfs::exists(sRoot / "Managed" / "oolite.oxp.test.gamma.oxz"));
		const oo::PList managed = Manager()->managedOXZs();
		OO_CHECK_TEXT(Titles(managed), "Late 1, Local 3, Alpha 1.0, Gamma 1.0");
		OO_CHECK_TEXT(InstallStatus(*Manager()->manifests().at(2)), "oolite-oxzmanager-installable-already");
		OO_CHECK_TEXT(Color(*Manager()->manifests().at(2)), "white");
		Manager()->_downloadStatus = OXZ_DOWNLOAD_NONE;
		OO_CHECK(!InstallOXZ(2));	// already installed

		// Extracting: Gamma into the extract folder; again (it exists); Alpha (a folder, not a zip); nothing.
		Manager()->setFilteredList(managed);
		OO_CHECK_TEXT(Element(managed, 3), "Gamma");
		OO_CHECK_TEXT(ExtractOXZ(3), "oolite-oxzmanager-extract-log-main-createdoolite-oxzmanager-extract-log-num-u-extractedoolite-oxzmanager-extract-log-extracted-to-@");
		const stdfs::path extracted = sRoot / "Extract" / "oolite.oxp.test.gamma-1.0.off";
		OO_CHECK(stdfs::exists(extracted / "manifest.plist"));
		OO_CHECK(stdfs::exists(extracted / "Config" / "notes.txt"));
		OO_CHECK_TEXT(ExtractOXZ(3), "oolite-oxzmanager-extract-log-main-exists");
		OO_CHECK_TEXT(ExtractOXZ(2), "oolite-oxzmanager-extract-log-bad-original");
		OO_CHECK_TEXT(ExtractOXZ(9), "oolite-oxzmanager-extract-log-no-original");

		// Removing: out of range, then Gamma.
		OO_CHECK(!RemoveOXZ(9));
		OO_CHECK(RemoveOXZ(3));
		OO_CHECK(!stdfs::exists(sRoot / "Managed" / "oolite.oxp.test.gamma.oxz"));
		OO_CHECK(Manager()->_interfaceState == OXZ_STATE_REMOVING);
		OO_CHECK_TEXT(Titles(Manager()->managedOXZs()), "Late 1, Local 3, Alpha 1.0");
	}
}


OO_TEST(restartAndUpdateAll)
{
	SetUp();
	{
		Manager()->_interfaceState = OXZ_STATE_RESTARTING;
		OO_CHECK(IsRestarting());
		OO_CHECK(Manager()->_interfaceState == OXZ_STATE_MAIN);
		OO_CHECK(!Manager()->_changesMade);
		OO_CHECK(Manager()->_downloadStatus == OXZ_DOWNLOAD_NONE);
		OO_CHECK(!IsRestarting());

		// Alpha 3.0 updates the managed Alpha 1.0; its URL names no file, so the download fails.
		OO_CHECK(UpdateAllOXZ());
		OO_CHECK(Manager()->_downloadAllDependencies);
		OO_CHECK_EQ(Manager()->_dependencyStack.size(), 1u);
		OO_CHECK_EQ(Manager()->_item, 0u);
		OO_CHECK(Manager()->_interfaceState == OXZ_STATE_INSTALLING);
		OO_CHECK_TEXT(Titles(Manager()->_filteredList), "Alpha 3.0, Beta 1.0, Gamma 1.0");
		FinishDownload();
		OO_CHECK(Manager()->_downloadStatus == OXZ_DOWNLOAD_ERROR);
	}
}


// Slices 3 and 4 (beads oo-q7r3, oo-qbgo): the GUI pages. A stand-in UNIVERSE (amendment oo-8kx7
// item 7, as an object put in gSharedUniverse for these cases only, since the test links the real
// Universe) answers -gui with a recording screen; the manager's sends to it are the page.
#include "Universe.h"	// the real class: the test links the whole game (bead oo-ql9rn)
#include "MyOpenGLView.h"	// the game view is C++ (bead oo-9ht.153)
extern Universe *gSharedUniverse;

// The page's rows (OOOXZManager.mm's private OXZ_GUI_ROW_* values).
enum
{
	OXZ_GUI_ROW_LISTSTART	= 2,
	OXZ_GUI_ROW_INSTALL		= 22,
	OXZ_GUI_ROW_INSTALLED	= 23,
	OXZ_GUI_ROW_REMOVE		= 25,
	OXZ_GUI_ROW_UPDATE		= 26,
	OXZ_GUI_ROW_CANCEL		= 26,
	OXZ_GUI_ROW_EXIT		= 27
};


// The GUI is C++ since bead oo-9ht.143 deleted its facade: the recording screen overrides the
// members it answered (proposed ADR-0056 amendment oo-9ht.1), recording the same lines.
class TestGui : public GuiDisplayGen
{
public:
	TestGui() : GuiDisplayGen(NSMakeSize(480, 480), GUI_DEFAULT_COLUMNS, GUI_DEFAULT_ROWS, 16, 40, std::nullopt) {}

	std::vector<std::string>	log;
	OOGUIRow					selected = 0;

	void clearAndKeepBackground(bool keepBackground) override	{ log.push_back(keepBackground ? "clear keep" : "clear"); }
	void setTitle(const std::optional<std::string> &str) override	{ log.push_back("title " + str.value_or("(nil)")); }
	void setText(const std::optional<std::string> &str, OOGUIRow row, OOGUIAlignment alignment) override
	{
		log.push_back("text " + std::to_string(row) + " " + std::to_string(static_cast<int>(alignment)) + " " + str.value_or("(nil)"));
	}
	void setText(const std::string &str, OOGUIRow row) override	{ log.push_back("text " + std::to_string(row) + " " + str); }
	OOGUIRow addLongText(const std::optional<std::string> &str, OOGUIRow row, OOGUIAlignment alignment) override
	{
		log.push_back("long " + std::to_string(row) + " " + std::to_string(static_cast<int>(alignment)) + " " + str.value_or("(nil)"));
		return row + 1;
	}
	void setKey(const std::string &str, OOGUIRow row) override	{ log.push_back("key " + std::to_string(row) + " " + str); }
	void setArray(const std::vector<std::string> &arr, OOGUIRow row) override
	{
		std::string line = "array " + std::to_string(row);
		for (const std::string &column : arr)  line += " |" + column;
		log.push_back(line);
	}
	void setColor(OOColor *color, OOGUIRow row) override
	{
		OOColor *c = color;
		log.push_back("color " + std::to_string(row) + " " + (c != nullptr ? std::to_string(static_cast<int>(c->redComponent() * 100)) + "," + std::to_string(static_cast<int>(c->greenComponent() * 100)) + "," + std::to_string(static_cast<int>(c->blueComponent() * 100)) : std::string("nil")));
	}
	OOGUIRow getSelectedRow() override	{ return selected; }
	bool setSelectedRow(OOGUIRow row) override	{ log.push_back("select " + std::to_string(row)); selected = row; return true; }
	void setSelectableRange(NSRange range) override	{ log.push_back("range " + std::to_string(range.location) + "+" + std::to_string(range.length)); }
	void setTabStops(OOGUITabSettings stops) override	{ log.push_back("tabs " + std::to_string(stops[1]) + "," + std::to_string(stops[2])); }
};


// The game view: a C++ subclass of the game's (bead oo-9ht.153 deleted the Objective-C facade the
// test's Objective-C stand-in stood in for), overriding the two members it answered (virtual for it).
class TestGameView : public MyOpenGLView
{
public:
	int				resets = 0;
	std::string		clipboard;

	void resetTypedString() override	{ resets++; }
	void stringToClipboard(const std::string &stringToCopy) override	{ clipboard = stringToCopy; }
};


// The universe the manager sees: a C++ subclass of the game's (bead oo-ql9rn deleted the Objective-C
// facade the test's Objective-C TestUniverse stood in for), overriding the same members. Its
// descriptions are testDescriptions (the class has a member _descriptions).
class TestUniverse : public Universe
{
public:
	oo::Ref<TestGui> testGui = {};
	TestGameView	*testGameView = nullptr;
	oo::PList testDescriptions = {};

	TestUniverse()
	{
		testGui = oo::makeRef<TestGui>();
		testGameView = new TestGameView();
		testDescriptions = oo::PList(oo::PList::Dict());
	}
	::GuiDisplayGen *getGui() override	{ return testGui.get(); }
	::MyOpenGLView *getGameView() override	{ return testGameView; }	// what -gameView answered
	std::optional<std::string> descriptionForKey(const std::string &key) override	{ (void)key; return std::nullopt; }
	const oo::PList *descriptions() override	{ return &testDescriptions; }
	::OOSystemDescriptionManager *getSystemManager() override	{ return nullptr; }
	bool reinitAndShowDemo(bool showDemo) override	{ (void)showDemo; return YES; }
};


namespace {

// Installs the stand-in for the life of one case.
struct StandInUniverse
{
	TestUniverse *universe;
	StandInUniverse()  { universe = new TestUniverse(); gSharedUniverse = universe; }
	~StandInUniverse()  { gSharedUniverse = nil; }	// never released: a universe's teardown (the facade's -dealloc) flushes the caches and the GL objects
	std::string Page()
	{
		std::string page;
		for (const std::string &line : universe->testGui->log)  page += line + "\n";
		universe->testGui->log.clear();
		return page;
	}
};


// Prints a page as C++ string literal lines, to pin it.
void Show(const char *name, const std::string &page)
{
	std::printf("PAGE %s\n", name);
	size_t start = 0;
	while (start < page.size())
	{
		size_t end = page.find('\n', start);
		std::string line = page.substr(start, end - start);
		std::string escaped;
		for (char c : line)  { if (c == '"' || c == '\\')  escaped += '\\'; escaped += c; }
		std::printf("\t\t\t\"%s\\n\"\n", escaped.c_str());
		start = end + 1;
	}
	std::fflush(stdout);
}


void CheckPage(const char *name, const std::string &page, const std::string &expected, int line)
{
	if (page != expected)  Show(name, page);
	::oo_test::check(page == expected, name, __FILE__, line);
}

#define OO_CHECK_PAGE(name, page, expected) CheckPage(name, page, expected, __LINE__)

}	// namespace


OO_TEST(guiPages)
{
	SetUp();
	{
		StandInUniverse standIn;
		OOOXZManager *m = Manager();
		m->_changesMade = false;
		m->_offset = 0;
		m->_item = 0;
		m->setFilter("*");
		standIn.universe->testGui->selected = 0;

		m->_interfaceState = OXZ_STATE_NODATA;
		m->gui();
		OO_CHECK_PAGE("nodata", standIn.Page(),
			"clear keep\n"
			"title oolite-oxzmanager-title\n"
			"long 1 0 oolite-oxzmanager-secondrun\n"
			"text 25 2 oolite-oxzmanager-download-noupdate\n"
			"key 25 _MAIN\n"
			"text 26 2 oolite-oxzmanager-update-list\n"
			"key 26 _UPDATE\n"
			"text 27 2 oolite-oxzmanager-exit\n"
			"key 27 _EXIT\n"
			"range 25+4\n"
			"select 26\n");

		m->_interfaceState = OXZ_STATE_SETFILTER;
		m->gui();
		OO_CHECK_PAGE("setfilter", standIn.Page(),
			"clear keep\n"
			"title oolite-oxzmanager-title\n"
			"title oolite-oxzmanager-title-setfilter\n"
			"text 26 0 oolite-oxzmanager-currentfilter-is-@\n"
			"long 1 0 oolite-oxzmanager-filterhelp\n");

		m->_interfaceState = OXZ_STATE_RESTARTING;
		m->gui();
		OO_CHECK_PAGE("restarting", standIn.Page(),
			"clear keep\n"
			"title oolite-oxzmanager-title\n"
			"long 1 0 oolite-oxzmanager-restart\n");

		m->_interfaceState = OXZ_STATE_MAIN;
		m->gui();
		OO_CHECK_PAGE("main", standIn.Page(),
			"clear keep\n"
			"title oolite-oxzmanager-title\n"
			"long 1 0 oolite-oxzmanager-intro\n"
			"text 22 2 oolite-oxzmanager-install\n"
			"key 22 _INSTALL\n"
			"text 23 2 oolite-oxzmanager-installed\n"
			"key 23 _INSTALLED\n"
			"text 25 2 oolite-oxzmanager-remove\n"
			"key 25 _REMOVE\n"
			"text 26 2 oolite-oxzmanager-update-list\n"
			"key 26 _UPDATE\n"
			"text 24 2 oolite-oxzmanager-update-all\n"
			"key 24 _UPDATE_ALL\n"
			"text 27 2 oolite-oxzmanager-exit\n"
			"key 27 _EXIT\n"
			"range 22+7\n"
			"select 22\n");

		m->_interfaceState = OXZ_STATE_UPDATING;
		m->_downloadStatus = OXZ_DOWNLOAD_RECEIVING;
		m->_currentDownloadName = "The list";
		m->_downloadProgress = 2048;
		m->_downloadExpected = 4096;
		m->setProgressStatus("progress");
		m->gui();
		OO_CHECK_PAGE("updating", standIn.Page(),
			"clear keep\n"
			"title oolite-oxzmanager-title\n"
			"title oolite-oxzmanager-title-downloading\n"
			"long 1 0 oolite-oxzmanager-progress-@-is-@-of-@\n"
			"long 3 0 progress\n"
			"text 26 2 oolite-oxzmanager-cancel\n"
			"key 26 _CANCEL\n"
			"text 27 2 oolite-oxzmanager-exit\n"
			"key 27 _EXIT\n"
			"range 26+3\n"
			"select 26\n");

		m->_interfaceState = OXZ_STATE_DEPENDENCIES;
		m->gui();
		OO_CHECK_PAGE("dependencies", standIn.Page(),
			"clear keep\n"
			"title oolite-oxzmanager-title\n"
			"title oolite-oxzmanager-title-dependencies\n"
			"text 1 0 oolite-oxzmanager-dependencies-decision\n"
			"long 3 0 progress\n"
			"text 23 2 oolite-oxzmanager-dependencies-yes-all\n"
			"key 23 _PROCEED_ALL\n"
			"text 25 2 oolite-oxzmanager-dependencies-yes\n"
			"key 25 _PROCEED\n"
			"text 26 2 oolite-oxzmanager-dependencies-no\n"
			"key 26 _CANCEL\n"
			"text 27 2 oolite-oxzmanager-exit\n"
			"key 27 _EXIT\n"
			"range 23+6\n"
			"select 23\n");

		m->_interfaceState = OXZ_STATE_REMOVING;
		m->gui();
		OO_CHECK_PAGE("removing", standIn.Page(),
			"clear keep\n"
			"title oolite-oxzmanager-title\n"
			"long 1 0 oolite-oxzmanager-removal-done\n"
			"text 26 2 oolite-oxzmanager-acknowledge\n"
			"key 26 _ACK\n"
			"text 27 2 oolite-oxzmanager-exit\n"
			"key 27 _EXIT\n"
			"range 26+3\n"
			"select 26\n");

		m->_interfaceState = OXZ_STATE_TASKDONE;
		m->_downloadStatus = OXZ_DOWNLOAD_COMPLETE;
		m->_changesMade = true;
		m->gui();
		OO_CHECK_PAGE("taskdone", standIn.Page(),
			"clear keep\n"
			"title oolite-oxzmanager-title\n"
			"long 1 0 oolite-oxzmanager-progress-done-3-3\n"
			"long 5 0 progress\n"
			"text 26 2 oolite-oxzmanager-acknowledge\n"
			"key 26 _ACK\n"
			"text 27 2 oolite-oxzmanager-exit-restart\n"
			"key 27 _EXIT\n"
			"range 26+3\n"
			"select 26\n");

		m->_interfaceState = OXZ_STATE_EXTRACTDONE;
		m->gui();
		OO_CHECK_PAGE("extractdone", standIn.Page(),
			"clear keep\n"
			"title oolite-oxzmanager-title\n"
			"long 1 0 progress\n"
			"text 26 2 oolite-oxzmanager-acknowledge\n"
			"key 26 _ACK\n"
			"text 27 2 oolite-oxzmanager-exit-restart\n"
			"key 27 _EXIT\n"
			"range 26+3\n"
			"select 26\n");

		m->setFilteredList(m->managedOXZs());
		m->_item = 2;
		m->_interfaceState = OXZ_STATE_EXTRACT;
		m->gui();
		OO_CHECK_PAGE("extract", standIn.Page(),
			"clear keep\n"
			"title oolite-oxzmanager-title\n"
			"title oolite-oxzmanager-title-extract\n"
			"text 0 0 oolite-oxzmanager-infopage-title-@-version-@\n"
			"long 2 0 oolite-oxzmanager-extract-info\n"
			"long 10 0 oolite-oxzmanager-extract-to-@\n"
			"text 25 2 oolite-oxzmanager-extract-proceed\n"
			"key 25 _PROCEED\n"
			"text 26 2 oolite-oxzmanager-extract-cancel\n"
			"key 26 _CANCEL\n"
			"text 27 2 oolite-oxzmanager-exit-restart\n"
			"key 27 _EXIT\n"
			"range 25+4\n"
			"select 25\n");

		// The list pages (slice 4's options), with the filter line through the string expander.
		m->_changesMade = false;
		m->_downloadStatus = OXZ_DOWNLOAD_NONE;
		standIn.universe->testGui->selected = OXZ_GUI_ROW_LISTSTART;
		m->_interfaceState = OXZ_STATE_PICK_INSTALL;
		m->gui();
		OO_CHECK_PAGE("pick install", standIn.Page(),
			"clear keep\n"
			"title oolite-oxzmanager-title\n"
			"text 21 0 oolite-oxzmanager-currentfilter-is-@-@\n"
			"color 21 0,100,0\n"
			"text 22 2 oolite-oxzmanager-install\n"
			"key 22 _INSTALL\n"
			"text 23 2 oolite-oxzmanager-installed\n"
			"key 23 _INSTALLED\n"
			"text 25 2 oolite-oxzmanager-remove\n"
			"key 25 _REMOVE\n"
			"text 26 2 oolite-oxzmanager-update-list\n"
			"key 26 _UPDATE\n"
			"text 24 2 oolite-oxzmanager-update-all\n"
			"key 24 _UPDATE_ALL\n"
			"title oolite-oxzmanager-title-install\n"
			"tabs 100,320\n"
			"array 0 |oolite-oxzmanager-heading-category |oolite-oxzmanager-heading-title |oolite-oxzmanager-heading-installed |oolite-oxzmanager-heading-downloadable\n"
			"text 1 0 \n"
			"key 1 SKIP-ROW\n"
			"text 12 0 \n"
			"key 12 SKIP-ROW\n"
			"text 14 0 \n"
			"key 14 SKIP-ROW\n"
			"text 15 0 \n"
			"key 15 SKIP-ROW\n"
			"text 16 0 \n"
			"key 16 SKIP-ROW\n"
			"text 17 0 \n"
			"key 17 SKIP-ROW\n"
			"text 18 0 \n"
			"key 18 SKIP-ROW\n"
			"text 19 0 \n"
			"key 19 SKIP-ROW\n"
			"text 20 0 \n"
			"key 20 SKIP-ROW\n"
			"text 2 0 \n"
			"key 2 SKIP-ROW\n"
			"text 3 0 \n"
			"key 3 SKIP-ROW\n"
			"text 4 0 \n"
			"key 4 SKIP-ROW\n"
			"text 5 0 \n"
			"key 5 SKIP-ROW\n"
			"text 6 0 \n"
			"key 6 SKIP-ROW\n"
			"text 7 0 \n"
			"key 7 SKIP-ROW\n"
			"text 8 0 \n"
			"key 8 SKIP-ROW\n"
			"text 9 0 \n"
			"key 9 SKIP-ROW\n"
			"text 10 0 \n"
			"key 10 SKIP-ROW\n"
			"text 11 0 \n"
			"key 11 SKIP-ROW\n"
			"array 2 |Ships |Alpha |oolite-oxzmanager-version-none |3.0\n"
			"key 2 oolite.oxp.test.alpha\n"
			"color 2 0,100,100\n"
			"text 14 oolite-oxzmanager-installable-update\n"
			"color 14 0,100,0\n"
			"long 16 0 Cobra variants\n"
			"array 3 |Ships |Beta |oolite-oxzmanager-version-none |1.0\n"
			"key 3 oolite.oxp.test.beta\n"
			"color 3 100,100,0\n"
			"array 4 |Ships |Gamma |oolite-oxzmanager-version-none |1.0\n"
			"key 4 oolite.oxp.test.gamma\n"
			"color 4 100,100,0\n"
			"text 27 2 oolite-oxzmanager-exit\n"
			"key 27 _EXIT\n"
			"range 1+28\n"
			"select 22\n");

		m->_interfaceState = OXZ_STATE_PICK_INSTALLED;
		m->gui();
		OO_CHECK_PAGE("pick installed", standIn.Page(),
			"clear keep\n"
			"title oolite-oxzmanager-title\n"
			"text 21 0 oolite-oxzmanager-currentfilter-is-@-@\n"
			"color 21 0,100,0\n"
			"text 22 2 oolite-oxzmanager-install\n"
			"key 22 _INSTALL\n"
			"text 23 2 oolite-oxzmanager-installed\n"
			"key 23 _INSTALLED\n"
			"text 25 2 oolite-oxzmanager-remove\n"
			"key 25 _REMOVE\n"
			"text 26 2 oolite-oxzmanager-update-list\n"
			"key 26 _UPDATE\n"
			"text 24 2 oolite-oxzmanager-update-all\n"
			"key 24 _UPDATE_ALL\n"
			"title oolite-oxzmanager-title-installed\n"
			"tabs 100,320\n"
			"array 0 |oolite-oxzmanager-heading-category |oolite-oxzmanager-heading-title |oolite-oxzmanager-heading-installed |oolite-oxzmanager-heading-downloadable\n"
			"text 1 0 \n"
			"key 1 SKIP-ROW\n"
			"text 12 0 \n"
			"key 12 SKIP-ROW\n"
			"text 14 0 \n"
			"key 14 SKIP-ROW\n"
			"text 15 0 \n"
			"key 15 SKIP-ROW\n"
			"text 16 0 \n"
			"key 16 SKIP-ROW\n"
			"text 17 0 \n"
			"key 17 SKIP-ROW\n"
			"text 18 0 \n"
			"key 18 SKIP-ROW\n"
			"text 19 0 \n"
			"key 19 SKIP-ROW\n"
			"text 20 0 \n"
			"key 20 SKIP-ROW\n"
			"text 2 0 \n"
			"key 2 SKIP-ROW\n"
			"text 3 0 \n"
			"key 3 SKIP-ROW\n"
			"text 4 0 \n"
			"key 4 SKIP-ROW\n"
			"text 5 0 \n"
			"key 5 SKIP-ROW\n"
			"text 6 0 \n"
			"key 6 SKIP-ROW\n"
			"text 7 0 \n"
			"key 7 SKIP-ROW\n"
			"text 8 0 \n"
			"key 8 SKIP-ROW\n"
			"text 9 0 \n"
			"key 9 SKIP-ROW\n"
			"text 10 0 \n"
			"key 10 SKIP-ROW\n"
			"text 11 0 \n"
			"key 11 SKIP-ROW\n"
			"array 2 |Ambience |Late |oolite-oxzmanager-version-none |1\n"
			"key 2 oolite.oxp.test.late\n"
			"color 2 100,100,100\n"
			"array 3 |Ambience |Local |oolite-oxzmanager-version-none |3\n"
			"key 3 oolite.oxp.test.local\n"
			"color 3 100,100,100\n"
			"array 4 |Ships |Alpha |oolite-oxzmanager-version-none |3.0\n"
			"key 4 oolite.oxp.test.alpha\n"
			"color 4 0,100,100\n"
			"long 16 0 oolite-oxzmanager-installed-nonepicked\n"
			"text 27 2 oolite-oxzmanager-exit\n"
			"key 27 _EXIT\n"
			"range 1+28\n"
			"select 22\n");

		m->_interfaceState = OXZ_STATE_PICK_REMOVE;
		m->gui();
		OO_CHECK_PAGE("pick remove", standIn.Page(),
			"clear keep\n"
			"title oolite-oxzmanager-title\n"
			"text 21 0 oolite-oxzmanager-currentfilter-is-@-@\n"
			"color 21 0,100,0\n"
			"text 22 2 oolite-oxzmanager-install\n"
			"key 22 _INSTALL\n"
			"text 23 2 oolite-oxzmanager-installed\n"
			"key 23 _INSTALLED\n"
			"text 25 2 oolite-oxzmanager-remove\n"
			"key 25 _REMOVE\n"
			"text 26 2 oolite-oxzmanager-update-list\n"
			"key 26 _UPDATE\n"
			"text 24 2 oolite-oxzmanager-update-all\n"
			"key 24 _UPDATE_ALL\n"
			"title oolite-oxzmanager-title-remove\n"
			"tabs 100,400\n"
			"array 0 |oolite-oxzmanager-heading-category |oolite-oxzmanager-heading-title |oolite-oxzmanager-heading-version\n"
			"text 1 0 \n"
			"key 1 SKIP-ROW\n"
			"text 12 0 \n"
			"key 12 SKIP-ROW\n"
			"text 16 0 \n"
			"key 16 SKIP-ROW\n"
			"text 17 0 \n"
			"key 17 SKIP-ROW\n"
			"text 18 0 \n"
			"key 18 SKIP-ROW\n"
			"text 19 0 \n"
			"key 19 SKIP-ROW\n"
			"text 20 0 \n"
			"key 20 SKIP-ROW\n"
			"text 2 0 \n"
			"key 2 SKIP-ROW\n"
			"text 3 0 \n"
			"key 3 SKIP-ROW\n"
			"text 4 0 \n"
			"key 4 SKIP-ROW\n"
			"text 5 0 \n"
			"key 5 SKIP-ROW\n"
			"text 6 0 \n"
			"key 6 SKIP-ROW\n"
			"text 7 0 \n"
			"key 7 SKIP-ROW\n"
			"text 8 0 \n"
			"key 8 SKIP-ROW\n"
			"text 9 0 \n"
			"key 9 SKIP-ROW\n"
			"text 10 0 \n"
			"key 10 SKIP-ROW\n"
			"text 11 0 \n"
			"key 11 SKIP-ROW\n"
			"array 2 |Ambience |Late |1\n"
			"key 2 oolite.oxp.test.late\n"
			"color 2 100,100,100\n"
			"array 3 |Ambience |Local |3\n"
			"key 3 oolite.oxp.test.local\n"
			"color 3 100,100,100\n"
			"array 4 |Ships |Alpha |1.0\n"
			"key 4 oolite.oxp.test.alpha\n"
			"color 4 0,100,100\n"
			"long 16 0 oolite-oxzmanager-remover-nonepicked\n"
			"text 27 2 oolite-oxzmanager-exit\n"
			"key 27 _EXIT\n"
			"range 1+28\n"
			"select 22\n");

		m->_interfaceState = OXZ_STATE_UPDATING;
		m->_downloadStatus = OXZ_DOWNLOAD_ERROR;
		m->gui();
		OO_CHECK_PAGE("updating error", standIn.Page(),
			"clear keep\n"
			"title oolite-oxzmanager-title\n"
			"title oolite-oxzmanager-title-downloading\n"
			"long 1 0 (nil)\n"
			"long 3 0 progress\n"
			"text 26 2 oolite-oxzmanager-cancel\n"
			"key 26 _CANCEL\n"
			"text 27 2 oolite-oxzmanager-exit\n"
			"key 27 _EXIT\n"
			"range 26+3\n"
			"select 26\n");

		m->_interfaceState = OXZ_STATE_MAIN;
		m->_downloadStatus = OXZ_DOWNLOAD_NONE;
		m->setProgressStatus("");
	}
}


OO_TEST(guiInput)
{
	SetUp();
	// The manager leaves these pages through the intro screen, which it shows only with no PLAYER
	// (PLAYER's setGuiToIntroFirstGo()): they run with none, as before, which only a release-style
	// build can (the debug build asserts PLAYER is set; bead oo-vdw34).
	gOOPlayer = nullptr;
#if !OO_DEBUG
	{
		StandInUniverse standIn;
		OOOXZManager *m = Manager();
		TestGui *gui = standIn.universe->testGui.get();

		// The filter: the key, typed text, its prompt.
		m->_interfaceState = OXZ_STATE_NODATA;
		m->processFilterKey();
		OO_CHECK(m->_interfaceState == OXZ_STATE_NODATA);
		OO_CHECK(!m->isAcceptingTextInput());
		m->_interfaceState = OXZ_STATE_MAIN;
		m->_interfaceShowingOXZDetail = true;
		m->processFilterKey();
		OO_CHECK(m->_interfaceState == OXZ_STATE_SETFILTER);
		OO_CHECK(!m->_interfaceShowingOXZDetail);
		OO_CHECK_EQ(standIn.universe->testGameView->resets, 1);
		OO_CHECK(m->isAcceptingTextInput());
		OO_CHECK(m->isAcceptingGUIInput());
		standIn.Page();
		m->refreshTextInput("k:x");
		OO_CHECK_PAGE("prompt valid", standIn.Page(),
			"text 27 0 oolite-oxzmanager-text-prompt-@\n"
			"color 27 0,100,100\n");
		m->refreshTextInput("k:");
		OO_CHECK_PAGE("prompt invalid", standIn.Page(),
			"text 27 0 oolite-oxzmanager-text-prompt-@\n"
			"color 27 100,50,0\n");
		m->processTextInput("k:");
		OO_CHECK(m->_interfaceState == OXZ_STATE_SETFILTER);
		OO_CHECK_PAGE("text invalid", standIn.Page(), "");
		m->processTextInput("C:Ships");
		OO_CHECK(m->_interfaceState == OXZ_STATE_PICK_INSTALL);
		OO_CHECK_TEXT(m->_currentFilter, "c:ships");
		OO_CHECK_PAGE("text valid", standIn.Page(),
			"clear keep\n"
			"title oolite-oxzmanager-title\n"
			"text 21 0 oolite-oxzmanager-currentfilter-is-@-@\n"
			"color 21 0,100,0\n"
			"text 22 2 oolite-oxzmanager-install\n"
			"key 22 _INSTALL\n"
			"text 23 2 oolite-oxzmanager-installed\n"
			"key 23 _INSTALLED\n"
			"text 25 2 oolite-oxzmanager-remove\n"
			"key 25 _REMOVE\n"
			"text 26 2 oolite-oxzmanager-update-list\n"
			"key 26 _UPDATE\n"
			"text 24 2 oolite-oxzmanager-update-all\n"
			"key 24 _UPDATE_ALL\n"
			"title oolite-oxzmanager-title-install\n"
			"tabs 100,320\n"
			"array 0 |oolite-oxzmanager-heading-category |oolite-oxzmanager-heading-title |oolite-oxzmanager-heading-installed |oolite-oxzmanager-heading-downloadable\n"
			"text 1 0 \n"
			"key 1 SKIP-ROW\n"
			"text 12 0 \n"
			"key 12 SKIP-ROW\n"
			"text 14 0 \n"
			"key 14 SKIP-ROW\n"
			"text 15 0 \n"
			"key 15 SKIP-ROW\n"
			"text 16 0 \n"
			"key 16 SKIP-ROW\n"
			"text 17 0 \n"
			"key 17 SKIP-ROW\n"
			"text 18 0 \n"
			"key 18 SKIP-ROW\n"
			"text 19 0 \n"
			"key 19 SKIP-ROW\n"
			"text 20 0 \n"
			"key 20 SKIP-ROW\n"
			"text 2 0 \n"
			"key 2 SKIP-ROW\n"
			"text 3 0 \n"
			"key 3 SKIP-ROW\n"
			"text 4 0 \n"
			"key 4 SKIP-ROW\n"
			"text 5 0 \n"
			"key 5 SKIP-ROW\n"
			"text 6 0 \n"
			"key 6 SKIP-ROW\n"
			"text 7 0 \n"
			"key 7 SKIP-ROW\n"
			"text 8 0 \n"
			"key 8 SKIP-ROW\n"
			"text 9 0 \n"
			"key 9 SKIP-ROW\n"
			"text 10 0 \n"
			"key 10 SKIP-ROW\n"
			"text 11 0 \n"
			"key 11 SKIP-ROW\n"
			"array 2 |Ships |Alpha |oolite-oxzmanager-version-none |3.0\n"
			"key 2 oolite.oxp.test.alpha\n"
			"color 2 0,100,100\n"
			"array 3 |Ships |Beta |oolite-oxzmanager-version-none |1.0\n"
			"key 3 oolite.oxp.test.beta\n"
			"color 3 100,100,0\n"
			"array 4 |Ships |Gamma |oolite-oxzmanager-version-none |1.0\n"
			"key 4 oolite.oxp.test.gamma\n"
			"color 4 100,100,0\n"
			"long 16 0 oolite-oxzmanager-installer-nonepicked\n"
			"text 27 2 oolite-oxzmanager-exit\n"
			"key 27 _EXIT\n"
			"range 1+28\n"
			"select 22\n");
		m->processTextInput("");
		OO_CHECK_TEXT(m->_currentFilter, "c:ships");
		m->setFilter("*");
		standIn.Page();

		// The info page of the selected entry, and back.
		gui->selected = OXZ_GUI_ROW_LISTSTART + 1;
		m->processShowInfoKey();
		OO_CHECK(m->_interfaceShowingOXZDetail);
		OO_CHECK(!m->isAcceptingGUIInput());
		OO_CHECK_EQ(m->_item, 1u);
		OO_CHECK_TEXT(standIn.universe->testGameView->clipboard, "");
		OO_CHECK_PAGE("info", standIn.Page(),
			"clear keep\n"
			"title oolite-oxzmanager-title-infopage\n"
			"text 0 0 oolite-oxzmanager-infopage-title-@-version-@\n"
			"text 1 0 oolite-oxzmanager-infopage-author-@\n"
			"long 2 0 oolite-oxzmanager-infopage-license-@\n"
			"long 4 0 oolite-oxzmanager-infopage-tags-@\n"
			"long 7 0 oolite-oxzmanager-infopage-description-@\n"
			"text 25 0 oolite-oxzmanager-infopage-infourl-@\n"
			"text 27 2 oolite-oxzmanager-infopage-return\n"
			"color 27 0,100,0\n");
		m->processShowInfoKey();
		OO_CHECK(!m->_interfaceShowingOXZDetail);
		OO_CHECK_PAGE("info closed", standIn.Page(),
			"clear keep\n"
			"title oolite-oxzmanager-title\n"
			"text 21 0 oolite-oxzmanager-currentfilter-is-@-@\n"
			"color 21 0,100,0\n"
			"text 22 2 oolite-oxzmanager-install\n"
			"key 22 _INSTALL\n"
			"text 23 2 oolite-oxzmanager-installed\n"
			"key 23 _INSTALLED\n"
			"text 25 2 oolite-oxzmanager-remove\n"
			"key 25 _REMOVE\n"
			"text 26 2 oolite-oxzmanager-update-list\n"
			"key 26 _UPDATE\n"
			"text 24 2 oolite-oxzmanager-update-all\n"
			"key 24 _UPDATE_ALL\n"
			"title oolite-oxzmanager-title-install\n"
			"tabs 100,320\n"
			"array 0 |oolite-oxzmanager-heading-category |oolite-oxzmanager-heading-title |oolite-oxzmanager-heading-installed |oolite-oxzmanager-heading-downloadable\n"
			"text 1 0 \n"
			"key 1 SKIP-ROW\n"
			"text 12 0 \n"
			"key 12 SKIP-ROW\n"
			"text 14 0 \n"
			"key 14 SKIP-ROW\n"
			"text 15 0 \n"
			"key 15 SKIP-ROW\n"
			"text 16 0 \n"
			"key 16 SKIP-ROW\n"
			"text 17 0 \n"
			"key 17 SKIP-ROW\n"
			"text 18 0 \n"
			"key 18 SKIP-ROW\n"
			"text 19 0 \n"
			"key 19 SKIP-ROW\n"
			"text 20 0 \n"
			"key 20 SKIP-ROW\n"
			"text 2 0 \n"
			"key 2 SKIP-ROW\n"
			"text 3 0 \n"
			"key 3 SKIP-ROW\n"
			"text 4 0 \n"
			"key 4 SKIP-ROW\n"
			"text 5 0 \n"
			"key 5 SKIP-ROW\n"
			"text 6 0 \n"
			"key 6 SKIP-ROW\n"
			"text 7 0 \n"
			"key 7 SKIP-ROW\n"
			"text 8 0 \n"
			"key 8 SKIP-ROW\n"
			"text 9 0 \n"
			"key 9 SKIP-ROW\n"
			"text 10 0 \n"
			"key 10 SKIP-ROW\n"
			"text 11 0 \n"
			"key 11 SKIP-ROW\n"
			"array 2 |Ships |Alpha |oolite-oxzmanager-version-none |3.0\n"
			"key 2 oolite.oxp.test.alpha\n"
			"color 2 0,100,100\n"
			"array 3 |Ships |Beta |oolite-oxzmanager-version-none |1.0\n"
			"key 3 oolite.oxp.test.beta\n"
			"color 3 100,100,0\n"
			"text 14 oolite-oxzmanager-installable-okay\n"
			"color 14 0,100,0\n"
			"long 16 0 Beta ship\n"
			"array 4 |Ships |Gamma |oolite-oxzmanager-version-none |1.0\n"
			"key 4 oolite.oxp.test.gamma\n"
			"color 4 100,100,0\n"
			"text 27 2 oolite-oxzmanager-exit\n"
			"key 27 _EXIT\n"
			"range 1+28\n"
			"select 22\n"
			"select 3\n"
			"tabs 100,320\n"
			"array 0 |oolite-oxzmanager-heading-category |oolite-oxzmanager-heading-title |oolite-oxzmanager-heading-installed |oolite-oxzmanager-heading-downloadable\n"
			"text 1 0 \n"
			"key 1 SKIP-ROW\n"
			"text 12 0 \n"
			"key 12 SKIP-ROW\n"
			"text 14 0 \n"
			"key 14 SKIP-ROW\n"
			"text 15 0 \n"
			"key 15 SKIP-ROW\n"
			"text 16 0 \n"
			"key 16 SKIP-ROW\n"
			"text 17 0 \n"
			"key 17 SKIP-ROW\n"
			"text 18 0 \n"
			"key 18 SKIP-ROW\n"
			"text 19 0 \n"
			"key 19 SKIP-ROW\n"
			"text 20 0 \n"
			"key 20 SKIP-ROW\n"
			"text 2 0 \n"
			"key 2 SKIP-ROW\n"
			"text 3 0 \n"
			"key 3 SKIP-ROW\n"
			"text 4 0 \n"
			"key 4 SKIP-ROW\n"
			"text 5 0 \n"
			"key 5 SKIP-ROW\n"
			"text 6 0 \n"
			"key 6 SKIP-ROW\n"
			"text 7 0 \n"
			"key 7 SKIP-ROW\n"
			"text 8 0 \n"
			"key 8 SKIP-ROW\n"
			"text 9 0 \n"
			"key 9 SKIP-ROW\n"
			"text 10 0 \n"
			"key 10 SKIP-ROW\n"
			"text 11 0 \n"
			"key 11 SKIP-ROW\n"
			"array 2 |Ships |Alpha |oolite-oxzmanager-version-none |3.0\n"
			"key 2 oolite.oxp.test.alpha\n"
			"color 2 0,100,100\n"
			"array 3 |Ships |Beta |oolite-oxzmanager-version-none |1.0\n"
			"key 3 oolite.oxp.test.beta\n"
			"color 3 100,100,0\n"
			"text 14 oolite-oxzmanager-installable-okay\n"
			"color 14 0,100,0\n"
			"long 16 0 Beta ship\n"
			"array 4 |Ships |Gamma |oolite-oxzmanager-version-none |1.0\n"
			"key 4 oolite.oxp.test.gamma\n"
			"color 4 100,100,0\n");
		gui->selected = 0;
		m->processShowInfoKey();
		OO_CHECK(!m->_interfaceShowingOXZDetail);

		// Extracting is offered from the installed list only.
		gui->selected = OXZ_GUI_ROW_LISTSTART;
		m->processExtractKey();
		OO_CHECK(m->_interfaceState == OXZ_STATE_PICK_INSTALL);
		m->_interfaceState = OXZ_STATE_PICK_INSTALLED;
		m->gui();
		standIn.Page();
		OO_CHECK_EQ(gui->selected, OXZ_GUI_ROW_INSTALL);	// the page selected its first control
		m->processExtractKey();
		OO_CHECK(m->_interfaceState == OXZ_STATE_PICK_INSTALLED);
		gui->selected = OXZ_GUI_ROW_LISTSTART;
		m->processExtractKey();
		OO_CHECK(m->_interfaceState == OXZ_STATE_EXTRACT);
		OO_CHECK_EQ(m->_item, 0u);
		OO_CHECK_PAGE("extract key", standIn.Page(),
			"clear keep\n"
			"title oolite-oxzmanager-title\n"
			"title oolite-oxzmanager-title-extract\n"
			"text 0 0 oolite-oxzmanager-infopage-title-@-version-@\n"
			"long 2 0 oolite-oxzmanager-extract-info\n"
			"long 10 0 oolite-oxzmanager-extract-to-@\n"
			"text 25 2 oolite-oxzmanager-extract-proceed\n"
			"key 25 _PROCEED\n"
			"text 26 2 oolite-oxzmanager-extract-cancel\n"
			"key 26 _CANCEL\n"
			"text 27 2 oolite-oxzmanager-exit\n"
			"key 27 _EXIT\n"
			"range 25+4\n"
			"select 25\n");

		// Selections.
		gui->selected = OXZ_GUI_ROW_CANCEL;
		m->processSelection();
		OO_CHECK(m->_interfaceState == OXZ_STATE_MAIN);
		OO_CHECK_PAGE("extract cancelled", standIn.Page(),
			"clear keep\n"
			"title oolite-oxzmanager-title\n"
			"long 1 0 oolite-oxzmanager-intro\n"
			"text 22 2 oolite-oxzmanager-install\n"
			"key 22 _INSTALL\n"
			"text 23 2 oolite-oxzmanager-installed\n"
			"key 23 _INSTALLED\n"
			"text 25 2 oolite-oxzmanager-remove\n"
			"key 25 _REMOVE\n"
			"text 26 2 oolite-oxzmanager-update-list\n"
			"key 26 _UPDATE\n"
			"text 24 2 oolite-oxzmanager-update-all\n"
			"key 24 _UPDATE_ALL\n"
			"text 27 2 oolite-oxzmanager-exit\n"
			"key 27 _EXIT\n"
			"range 22+7\n"
			"select 22\n");
		gui->selected = OXZ_GUI_ROW_INSTALLED;
		m->processSelection();
		OO_CHECK(m->_interfaceState == OXZ_STATE_PICK_INSTALLED);
		standIn.Page();
		gui->selected = OXZ_GUI_ROW_REMOVE;
		m->processSelection();
		OO_CHECK(m->_interfaceState == OXZ_STATE_PICK_REMOVE);
		standIn.Page();
		m->_interfaceState = OXZ_STATE_REMOVING;
		gui->selected = OXZ_GUI_ROW_UPDATE;
		m->processSelection();
		OO_CHECK(m->_interfaceState == OXZ_STATE_PICK_REMOVE);
		standIn.Page();
		gui->selected = OXZ_GUI_ROW_INSTALL;
		m->processSelection();
		OO_CHECK(m->_interfaceState == OXZ_STATE_PICK_INSTALL);
		standIn.Page();
		m->_changesMade = false;
		gui->selected = OXZ_GUI_ROW_EXIT;
		m->processSelection();
		OO_CHECK(m->_interfaceState == OXZ_STATE_MAIN);
		OO_CHECK_PAGE("exit", standIn.Page(), "");
		m->_changesMade = true;
		m->processSelection();
		OO_CHECK(m->_interfaceState == OXZ_STATE_RESTARTING);
		OO_CHECK_PAGE("exit to restart", standIn.Page(),
			"clear keep\n"
			"title oolite-oxzmanager-title\n"
			"long 1 0 oolite-oxzmanager-restart\n");
		OO_CHECK(m->isRestarting());
		OO_CHECK(m->_interfaceState == OXZ_STATE_MAIN);
	}
#endif
}


// Slice 4 (bead oo-qbgo): the install and remove option pages, and their paging. Release-style
// builds only (see the case; bead oo-vdw34).
#if !OO_DEBUG
namespace {

std::vector<oo::PList> InstallOptions()	{ return Manager()->installOptions(); }
std::vector<oo::PList> RemoveOptions()	{ return Manager()->removeOptions(); }


std::string OptionTitles(const std::vector<oo::PList> &options)
{
	return Titles(oo::PList(oo::PList::Array(options.begin(), options.end())));
}

}	// namespace


OO_TEST(optionPages)
{
	SetUp();
	// The manager leaves these pages through the intro screen, which it shows only with no PLAYER
	// (PLAYER's setGuiToIntroFirstGo()): they run with none, as before, which only a release-style
	// build can (the debug build asserts PLAYER is set; bead oo-vdw34).
	gOOPlayer = nullptr;
	{
		StandInUniverse standIn;
		OOOXZManager *m = Manager();
		TestGui *gui = standIn.universe->testGui.get();
		const oo::PList savedList = m->manifests();

		// Thirteen entries: two pages of ten.
		oo::PList::Array many;
		for (int i = 0; i < 13; i++)
		{
			char title[16];
			std::snprintf(title, sizeof title, "Item %02d", i);
			many.push_back(Manifest(("oolite.oxp.test.item" + std::to_string(i)).c_str(), title, "1", "Misc", "Ann", "An item", {}, -1, nullptr));
		}
		m->setOXZList(oo::PList(std::move(many)));
		m->setFilter("*");
		m->setFilteredList(m->manifests());
		m->_interfaceState = OXZ_STATE_PICK_INSTALL;
		m->_offset = 0;

		OO_CHECK_TEXT(OptionTitles(InstallOptions()), "Item 00 1, Item 01 1, Item 02 1, Item 03 1, Item 04 1, Item 05 1, Item 06 1, Item 07 1, Item 08 1, Item 09 1");
		m->_offset = 10;
		OO_CHECK_TEXT(OptionTitles(InstallOptions()), "Item 10 1, Item 11 1, Item 12 1");
		m->_offset = 20;
		OO_CHECK_TEXT(OptionTitles(InstallOptions()), "Item 00 1, Item 01 1, Item 02 1, Item 03 1, Item 04 1, Item 05 1, Item 06 1, Item 07 1, Item 08 1, Item 09 1");
		OO_CHECK_EQ(m->_offset, 0u);

		// Paging through the install list.
		gui->selected = OXZ_GUI_ROW_LISTSTART + 1;
		m->processOptionsNext();
		OO_CHECK_EQ(m->_offset, 10u);
		OO_CHECK_PAGE("install page 2", standIn.Page(),
			"tabs 100,320\n"
			"array 0 |oolite-oxzmanager-heading-category |oolite-oxzmanager-heading-title |oolite-oxzmanager-heading-installed |oolite-oxzmanager-heading-downloadable\n"
			"color 1 0,100,0\n"
			"array 1 |gui-back | | | <-- \n"
			"key 1 _BACK\n"
			"text 12 0 \n"
			"key 12 SKIP-ROW\n"
			"text 14 0 \n"
			"key 14 SKIP-ROW\n"
			"text 15 0 \n"
			"key 15 SKIP-ROW\n"
			"text 16 0 \n"
			"key 16 SKIP-ROW\n"
			"text 17 0 \n"
			"key 17 SKIP-ROW\n"
			"text 18 0 \n"
			"key 18 SKIP-ROW\n"
			"text 19 0 \n"
			"key 19 SKIP-ROW\n"
			"text 20 0 \n"
			"key 20 SKIP-ROW\n"
			"text 2 0 \n"
			"key 2 SKIP-ROW\n"
			"text 3 0 \n"
			"key 3 SKIP-ROW\n"
			"text 4 0 \n"
			"key 4 SKIP-ROW\n"
			"text 5 0 \n"
			"key 5 SKIP-ROW\n"
			"text 6 0 \n"
			"key 6 SKIP-ROW\n"
			"text 7 0 \n"
			"key 7 SKIP-ROW\n"
			"text 8 0 \n"
			"key 8 SKIP-ROW\n"
			"text 9 0 \n"
			"key 9 SKIP-ROW\n"
			"text 10 0 \n"
			"key 10 SKIP-ROW\n"
			"text 11 0 \n"
			"key 11 SKIP-ROW\n"
			"array 2 |Misc |Item 10 |oolite-oxzmanager-version-none |1\n"
			"key 2 oolite.oxp.test.item10\n"
			"color 2 100,100,0\n"
			"array 3 |Misc |Item 11 |oolite-oxzmanager-version-none |1\n"
			"key 3 oolite.oxp.test.item11\n"
			"color 3 100,100,0\n"
			"text 14 oolite-oxzmanager-installable-okay\n"
			"color 14 0,100,0\n"
			"long 16 0 An item\n"
			"array 4 |Misc |Item 12 |oolite-oxzmanager-version-none |1\n"
			"key 4 oolite.oxp.test.item12\n"
			"color 4 100,100,0\n");
		m->processOptionsNext();
		OO_CHECK_EQ(m->_offset, 10u);
		standIn.Page();
		m->processOptionsPrev();
		OO_CHECK_EQ(m->_offset, 0u);
		OO_CHECK_PAGE("install page 1", standIn.Page(),
			"tabs 100,320\n"
			"array 0 |oolite-oxzmanager-heading-category |oolite-oxzmanager-heading-title |oolite-oxzmanager-heading-installed |oolite-oxzmanager-heading-downloadable\n"
			"text 1 0 \n"
			"key 1 SKIP-ROW\n"
			"color 12 0,100,0\n"
			"array 12 |gui-more | | | --> \n"
			"key 12 _NEXT\n"
			"text 14 0 \n"
			"key 14 SKIP-ROW\n"
			"text 15 0 \n"
			"key 15 SKIP-ROW\n"
			"text 16 0 \n"
			"key 16 SKIP-ROW\n"
			"text 17 0 \n"
			"key 17 SKIP-ROW\n"
			"text 18 0 \n"
			"key 18 SKIP-ROW\n"
			"text 19 0 \n"
			"key 19 SKIP-ROW\n"
			"text 20 0 \n"
			"key 20 SKIP-ROW\n"
			"text 2 0 \n"
			"key 2 SKIP-ROW\n"
			"text 3 0 \n"
			"key 3 SKIP-ROW\n"
			"text 4 0 \n"
			"key 4 SKIP-ROW\n"
			"text 5 0 \n"
			"key 5 SKIP-ROW\n"
			"text 6 0 \n"
			"key 6 SKIP-ROW\n"
			"text 7 0 \n"
			"key 7 SKIP-ROW\n"
			"text 8 0 \n"
			"key 8 SKIP-ROW\n"
			"text 9 0 \n"
			"key 9 SKIP-ROW\n"
			"text 10 0 \n"
			"key 10 SKIP-ROW\n"
			"text 11 0 \n"
			"key 11 SKIP-ROW\n"
			"array 2 |Misc |Item 00 |oolite-oxzmanager-version-none |1\n"
			"key 2 oolite.oxp.test.item0\n"
			"color 2 100,100,0\n"
			"array 3 |Misc |Item 01 |oolite-oxzmanager-version-none |1\n"
			"key 3 oolite.oxp.test.item1\n"
			"color 3 100,100,0\n"
			"text 14 oolite-oxzmanager-installable-okay\n"
			"color 14 0,100,0\n"
			"long 16 0 An item\n"
			"array 4 |Misc |Item 02 |oolite-oxzmanager-version-none |1\n"
			"key 4 oolite.oxp.test.item2\n"
			"color 4 100,100,0\n"
			"array 5 |Misc |Item 03 |oolite-oxzmanager-version-none |1\n"
			"key 5 oolite.oxp.test.item3\n"
			"color 5 100,100,0\n"
			"array 6 |Misc |Item 04 |oolite-oxzmanager-version-none |1\n"
			"key 6 oolite.oxp.test.item4\n"
			"color 6 100,100,0\n"
			"array 7 |Misc |Item 05 |oolite-oxzmanager-version-none |1\n"
			"key 7 oolite.oxp.test.item5\n"
			"color 7 100,100,0\n"
			"array 8 |Misc |Item 06 |oolite-oxzmanager-version-none |1\n"
			"key 8 oolite.oxp.test.item6\n"
			"color 8 100,100,0\n"
			"array 9 |Misc |Item 07 |oolite-oxzmanager-version-none |1\n"
			"key 9 oolite.oxp.test.item7\n"
			"color 9 100,100,0\n"
			"array 10 |Misc |Item 08 |oolite-oxzmanager-version-none |1\n"
			"key 10 oolite.oxp.test.item8\n"
			"color 10 100,100,0\n"
			"array 11 |Misc |Item 09 |oolite-oxzmanager-version-none |1\n"
			"key 11 oolite.oxp.test.item9\n"
			"color 11 100,100,0\n");
		m->processOptionsPrev();
		OO_CHECK_EQ(m->_offset, 0u);
		standIn.Page();
		gui->selected = 12;		// the "more" row
		m->showOptionsNext();
		OO_CHECK_EQ(m->_offset, 10u);
		standIn.Page();
		gui->selected = 1;		// the "back" row
		m->showOptionsPrev();
		OO_CHECK_EQ(m->_offset, 0u);
		standIn.Page();
		gui->selected = OXZ_GUI_ROW_LISTSTART;
		m->showOptionsNext();	// not on the "more" row
		OO_CHECK_EQ(m->_offset, 0u);
		OO_CHECK_PAGE("show next elsewhere", standIn.Page(), "");
		OO_CHECK_EQ(m->showInstallOptions(), 1);
		standIn.Page();

		// The remove list: the managed OXZs, then nothing.
		m->_interfaceState = OXZ_STATE_PICK_REMOVE;
		m->showOptionsUpdate();
		OO_CHECK_TEXT(Titles(m->_filteredList), "Late 1, Local 3, Alpha 1.0");
		OO_CHECK_TEXT(OptionTitles(RemoveOptions()), "Late 1, Local 3, Alpha 1.0");
		OO_CHECK_PAGE("remove page", standIn.Page(),
			"tabs 100,400\n"
			"array 0 |oolite-oxzmanager-heading-category |oolite-oxzmanager-heading-title |oolite-oxzmanager-heading-version\n"
			"text 1 0 \n"
			"key 1 SKIP-ROW\n"
			"text 12 0 \n"
			"key 12 SKIP-ROW\n"
			"text 16 0 \n"
			"key 16 SKIP-ROW\n"
			"text 17 0 \n"
			"key 17 SKIP-ROW\n"
			"text 18 0 \n"
			"key 18 SKIP-ROW\n"
			"text 19 0 \n"
			"key 19 SKIP-ROW\n"
			"text 20 0 \n"
			"key 20 SKIP-ROW\n"
			"text 2 0 \n"
			"key 2 SKIP-ROW\n"
			"text 3 0 \n"
			"key 3 SKIP-ROW\n"
			"text 4 0 \n"
			"key 4 SKIP-ROW\n"
			"text 5 0 \n"
			"key 5 SKIP-ROW\n"
			"text 6 0 \n"
			"key 6 SKIP-ROW\n"
			"text 7 0 \n"
			"key 7 SKIP-ROW\n"
			"text 8 0 \n"
			"key 8 SKIP-ROW\n"
			"text 9 0 \n"
			"key 9 SKIP-ROW\n"
			"text 10 0 \n"
			"key 10 SKIP-ROW\n"
			"text 11 0 \n"
			"key 11 SKIP-ROW\n"
			"array 2 |Ambience |Late |1\n"
			"key 2 oolite.oxp.test.late\n"
			"color 2 100,100,100\n"
			"text 14 oolite-oxzmanager-installable-already\n"
			"color 14 0,100,0\n"
			"long 16 0 (nil)\n"
			"array 3 |Ambience |Local |3\n"
			"key 3 oolite.oxp.test.local\n"
			"color 3 100,100,100\n"
			"array 4 |Ships |Alpha |1.0\n"
			"key 4 oolite.oxp.test.alpha\n"
			"color 4 100,100,100\n");
		m->setFilteredList(oo::PList(oo::PList::Array()));
		OO_CHECK(RemoveOptions().empty());
		OO_CHECK_EQ(m->showRemoveOptions(), 1);
		OO_CHECK_PAGE("nothing removable", standIn.Page(),
			"long 1 0 oolite-oxzmanager-nothing-removable\n");

		m->setOXZList(savedList);
		m->setFilteredList(m->manifests());
		m->_offset = 0;
		m->_interfaceState = OXZ_STATE_MAIN;
	}
}
#endif


OO_TEST_MAIN()
