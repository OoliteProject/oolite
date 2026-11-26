/*	test_OOCacheManager.mm
	Unit tests for OOCacheManager (src/Core/OOCacheManager.h): bead oo-rmd7, a Phase 3 conversion
	in the house style of the OOColor exemplar (proposed ADR-0056).

	The manager is a process-wide singleton that keeps named caches of property lists and writes
	them to one file in the user's caches directory. The test points that directory (HOMEPATH) and
	the built-in Resources (the current directory) at a scratch folder before the singleton exists,
	so nothing of the user's is read or written. It pins what the manager computed before the
	conversion: one shared instance; storing, replacing, reading and removing entries and whole
	caches; dirtiness (in the description); the cache directory (not made unless asked); a flush
	writing through the asynchronous work manager and a reload reading it back; writes refused
	while disallowed; a cache from another game version, or one that does not parse, discarded;
	clearing everything. The expectations were written against the Objective-C API and run on the
	unconverted class first (commit 079054e79); they now run through the facade, which is its
	forwarding test (amendment oo-8kx7 item 6). The C++ API and the facade's contract (one facade,
	identity both ways, nil and null) follow.
	Run: bash tools/check-core-tests.sh
*/

#import "OOCacheManager.h"

#include "oofnd/FileSystem.hpp"
#include "oo_test.hpp"

#include <cstdlib>
#include <process.h>
#include <filesystem>
#include <string>
#include <vector>


/*	The asynchronous work manager (OOAsyncWorkManager.mm) starts worker threads, so it is not
	linked. A stub of the same name answers the three selectors the cache manager sends
	(proposed ADR-0056 amendment oo-z1s4 item 4): it keeps each task and runs it when it is waited
	for, as a worker thread would have run it by then, and counts both.
*/
@protocol StubAsyncTask
- (void) performAsyncTask;
- (void) completeAsyncTask;
@end


static int gTasksAdded = 0;
static int gTasksPerformed = 0;


@interface OOAsyncWorkManager: OOObject
{
@private
	std::vector<id>		_pending;
}
+ (OOAsyncWorkManager *) sharedAsyncWorkManager;
- (BOOL) addTask:(id)task priority:(int)priority;
- (void) waitForTaskToComplete:(id)task;
@end


@implementation OOAsyncWorkManager

+ (OOAsyncWorkManager *) sharedAsyncWorkManager
{
	static OOAsyncWorkManager *manager = [[OOAsyncWorkManager alloc] init];
	return manager;
}


- (BOOL) addTask:(id)task priority:(int)priority
{
	(void)priority;
	if (task == nil)  return NO;
	_pending.push_back([task retain]);
	gTasksAdded++;
	return YES;
}


- (void) waitForTaskToComplete:(id)task
{
	for (auto it = _pending.begin(); it != _pending.end(); ++it)
	{
		if (*it == task)
		{
			_pending.erase(it);
			[(id<StubAsyncTask>)task performAsyncTask];
			[(id<StubAsyncTask>)task completeAsyncTask];
			gTasksPerformed++;
			[task release];
			return;
		}
	}
}

@end


namespace {

namespace stdfs = std::filesystem;

stdfs::path sRoot;


void WriteText(const stdfs::path &path, const std::string &text)
{
	stdfs::create_directories(path.parent_path());
	OO_CHECK(oo::fs::writeFile(path, oo::Data(text.data(), text.size()), oo::fs::WriteMode::direct).has_value());
}


void SetGameVersion(const std::string &version)
{
	WriteText(sRoot / "Resources" / "Info-gnustep.plist", "{ CFBundleVersion = \"" + version + "\"; }");
}


stdfs::path CacheFile()
{
	return sRoot / "GNUstep" / "Library" / "Caches" / "org.aegidian.oolite" / "Oolite-cache.plist";
}


std::string CacheFileText()
{
	const oo::fs::Result<oo::Data> data = oo::fs::readFile(CacheFile());
	if (!data.has_value())  return std::string();
	return std::string(reinterpret_cast<const char *>(data->bytes()), data->length());
}


// The scratch home and game folder, made once, before the singleton exists.
void SetUp()
{
	if (!sRoot.empty())  return;
	sRoot = stdfs::temp_directory_path() / ("oo-test-cachemanager-" + std::to_string(static_cast<unsigned long>(::_getpid())));
	stdfs::remove_all(sRoot);
	stdfs::create_directories(sRoot);
	OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
	stdfs::current_path(sRoot);
	SetGameVersion("9.9.9-test");
}


oo::PList Str(const char *string)
{
	return oo::PList(std::string(string));
}

}	// namespace


OO_TEST(sharedInstanceStartsEmpty)
{
	SetUp();
	@autoreleasepool
	{
		OO_CHECK(!stdfs::exists(CacheFile()));
		OOCacheManager *cache = [OOCacheManager sharedCache];
		OO_CHECK(cache != nil);
		OO_CHECK([OOCacheManager sharedCache] == cache);
		OO_CHECK([cache cxx_pListForKey:"key" inCache:"cache"].isNull());
		OO_CHECK([cache cxx_descriptionComponents] == std::optional<std::string>("dirty=no"));

		// Loading made no directory.
		OO_CHECK(!stdfs::exists(sRoot / "GNUstep"));
		OO_CHECK(![cache cxx_cacheDirectoryPathCreatingIfNecessary:NO].has_value());
		OO_CHECK(!stdfs::exists(sRoot / "GNUstep"));
	}
}


OO_TEST(entriesAndCaches)
{
	SetUp();
	@autoreleasepool
	{
		OOCacheManager *cache = [OOCacheManager sharedCache];
		[cache cxx_setPList:Str("one") forKey:"a" inCache:"first"];
		[cache cxx_setPList:oo::PList(2) forKey:"b" inCache:"first"];
		[cache cxx_setPList:Str("three") forKey:"a" inCache:"second"];
		OO_CHECK([cache cxx_descriptionComponents] == std::optional<std::string>("dirty=yes"));
		OO_CHECK([cache cxx_pListForKey:"a" inCache:"first"] == Str("one"));
		OO_CHECK([cache cxx_pListForKey:"b" inCache:"first"] == oo::PList(2));
		OO_CHECK([cache cxx_pListForKey:"a" inCache:"second"] == Str("three"));
		OO_CHECK([cache cxx_pListForKey:"b" inCache:"second"].isNull());
		OO_CHECK([cache cxx_pListForKey:"a" inCache:"third"].isNull());

		// Replacing.
		[cache cxx_setPList:Str("uno") forKey:"a" inCache:"first"];
		OO_CHECK([cache cxx_pListForKey:"a" inCache:"first"] == Str("uno"));

		// Removing an entry, and entries or caches that are not there.
		[cache cxx_removeObjectForKey:"b" inCache:"first"];
		OO_CHECK([cache cxx_pListForKey:"b" inCache:"first"].isNull());
		OO_CHECK([cache cxx_pListForKey:"a" inCache:"first"] == Str("uno"));
		[cache cxx_removeObjectForKey:"b" inCache:"first"];
		[cache cxx_removeObjectForKey:"b" inCache:"none"];
		[cache cxx_clearCache:"none"];

		// Clearing one cache.
		[cache cxx_clearCache:"second"];
		OO_CHECK([cache cxx_pListForKey:"a" inCache:"second"].isNull());
		OO_CHECK([cache cxx_pListForKey:"a" inCache:"first"] == Str("uno"));

		[cache cxx_clearCache:"first"];
		OO_CHECK([cache cxx_pListForKey:"a" inCache:"first"].isNull());
	}
}


OO_TEST(flushWritesAndReloadReads)
{
	SetUp();
	@autoreleasepool
	{
		OOCacheManager *cache = [OOCacheManager sharedCache];
		[cache cxx_setPList:Str("kept") forKey:"k" inCache:"flushed"];
		oo::PList::Dict dict;
		dict.emplace("x", oo::PList(1.5));
		dict.emplace("y", oo::PList(oo::PList::Array{Str("p"), Str("q")}));
		[cache cxx_setPList:oo::PList(dict) forKey:"d" inCache:"flushed"];

		gTasksAdded = gTasksPerformed = 0;
		[cache flush];
		// The write is one task; flushing marks the manager clean at once.
		OO_CHECK(gTasksAdded == 1);
		OO_CHECK(gTasksPerformed == 0);
		OO_CHECK([cache cxx_descriptionComponents] == std::optional<std::string>("dirty=no"));
		// Nothing to flush while clean.
		[cache flush];
		OO_CHECK(gTasksAdded == 1);

		[cache finishOngoingFlush];
		OO_CHECK(gTasksPerformed == 1);
		OO_CHECK(stdfs::exists(CacheFile()));
		const std::string text = CacheFileText();
		OO_CHECK(text.find("<plist") != std::string::npos);
		OO_CHECK(text.find("9.9.9-test") != std::string::npos);
		OO_CHECK(text.find("kept") != std::string::npos);
		// Waiting again, with no write under way, does nothing.
		[cache finishOngoingFlush];
		OO_CHECK(gTasksPerformed == 1);

		// The directory now exists, so it is answered without being made.
		const std::optional<std::string> directory = [cache cxx_cacheDirectoryPathCreatingIfNecessary:NO];
		OO_CHECK(directory.has_value());
		OO_CHECK(directory.has_value() && stdfs::equivalent(oo::fs::pathFromUTF8(*directory), CacheFile().parent_path()));

		// A change after the flush is lost by reloading; what was written comes back.
		[cache cxx_setPList:Str("unsaved") forKey:"u" inCache:"flushed"];
		[cache reloadAllCaches];
		OO_CHECK([cache cxx_pListForKey:"u" inCache:"flushed"].isNull());
		OO_CHECK([cache cxx_pListForKey:"k" inCache:"flushed"] == Str("kept"));
		OO_CHECK([cache cxx_pListForKey:"d" inCache:"flushed"] == oo::PList(dict));
		OO_CHECK([cache cxx_descriptionComponents] == std::optional<std::string>("dirty=no"));
	}
}


OO_TEST(writesDisallowed)
{
	SetUp();
	@autoreleasepool
	{
		OOCacheManager *cache = [OOCacheManager sharedCache];
		[cache setAllowCacheWrites:NO];
		[cache cxx_setPList:Str("never written") forKey:"n" inCache:"flushed"];
		gTasksAdded = 0;
		[cache flush];
		OO_CHECK(gTasksAdded == 0);
		OO_CHECK([cache cxx_descriptionComponents] == std::optional<std::string>("dirty=yes"));

		[cache setAllowCacheWrites:YES];
		[cache flush];
		OO_CHECK(gTasksAdded == 1);
		[cache finishOngoingFlush];
		OO_CHECK(CacheFileText().find("never written") != std::string::npos);
	}
}


OO_TEST(staleOrBadCacheDiscarded)
{
	SetUp();
	@autoreleasepool
	{
		OOCacheManager *cache = [OOCacheManager sharedCache];
		OO_CHECK([cache cxx_pListForKey:"k" inCache:"flushed"] == Str("kept"));

		// Another game version: the cache is dropped on reload, and the manager is clean.
		SetGameVersion("1.0-other");
		[cache reloadAllCaches];
		OO_CHECK([cache cxx_pListForKey:"k" inCache:"flushed"].isNull());
		OO_CHECK([cache cxx_descriptionComponents] == std::optional<std::string>("dirty=no"));
		// It still takes new entries.
		[cache cxx_setPList:Str("fresh") forKey:"f" inCache:"new"];
		OO_CHECK([cache cxx_pListForKey:"f" inCache:"new"] == Str("fresh"));

		// A file that does not parse: no caches, and no crash.
		SetGameVersion("9.9.9-test");
		WriteText(CacheFile(), "this is not a property list {");
		[cache reloadAllCaches];
		OO_CHECK([cache cxx_pListForKey:"f" inCache:"new"].isNull());
		[cache cxx_setPList:Str("again") forKey:"g" inCache:"new"];
		OO_CHECK([cache cxx_pListForKey:"g" inCache:"new"] == Str("again"));
	}
}


OO_TEST(cxxApi)
{
	SetUp();
	@autoreleasepool
	{
		cxx::OOCacheManager *cache = cxx::OOCacheManager::sharedCache();
		OO_CHECK(cache != nullptr);
		OO_CHECK(cxx::OOCacheManager::sharedCache() == cache);
		cache->setPList(Str("c"), "k", "cxx");
		OO_CHECK(cache->pListForKey("k", "cxx") == Str("c"));
		OO_CHECK(cache->descriptionComponents() == std::optional<std::string>("dirty=yes"));
		cache->removeObjectForKey("k", "cxx");
		OO_CHECK(cache->pListForKey("k", "cxx").isNull());
		cache->setPList(Str("d"), "k", "cxx");
		cache->clearCache("cxx");
		OO_CHECK(cache->pListForKey("k", "cxx").isNull());

		gTasksAdded = gTasksPerformed = 0;
		cache->flush();
		OO_CHECK(gTasksAdded == 1);
		OO_CHECK(cache->descriptionComponents() == std::optional<std::string>("dirty=no"));
		cache->finishOngoingFlush();
		OO_CHECK(gTasksPerformed == 1);
		OO_CHECK(cache->cacheDirectoryPathCreatingIfNecessary(false).has_value());
	}
}


OO_TEST(facadeContract)
{
	SetUp();
	@autoreleasepool
	{
		OOCacheManager *facade = [OOCacheManager sharedCache];
		cxx::OOCacheManager *cache = cxx::OOCacheManager::sharedCache();
		OO_CHECK(oo::ToCxx(facade) == cache);
		OO_CHECK(oo::ToObjC(cache) == facade);
		OO_CHECK(oo::ToObjC(nullptr) == nil);
		OO_CHECK(oo::ToCxx(nil) == nullptr);

		// One store: what either side writes, the other reads.
		cache->setPList(Str("from C++"), "x", "shared");
		OO_CHECK([facade cxx_pListForKey:"x" inCache:"shared"] == Str("from C++"));
		[facade cxx_setPList:Str("from Objective-C") forKey:"y" inCache:"shared"];
		OO_CHECK(cache->pListForKey("y", "shared") == Str("from Objective-C"));
		OO_CHECK([facade cxx_descriptionComponents] == cache->descriptionComponents());
	}
}


OO_TEST(clearAllCaches)
{
	SetUp();
	@autoreleasepool
	{
		OOCacheManager *cache = [OOCacheManager sharedCache];
		[cache cxx_setPList:Str("v") forKey:"k" inCache:"c1"];
		[cache flush];
		[cache finishOngoingFlush];
		OO_CHECK([cache cxx_descriptionComponents] == std::optional<std::string>("dirty=no"));

		[cache clearAllCaches];
		OO_CHECK([cache cxx_pListForKey:"k" inCache:"c1"].isNull());
		OO_CHECK([cache cxx_descriptionComponents] == std::optional<std::string>("dirty=yes"));
		[cache cxx_setPList:Str("w") forKey:"k" inCache:"c1"];
		OO_CHECK([cache cxx_pListForKey:"k" inCache:"c1"] == Str("w"));
	}
	std::error_code ignored;
	stdfs::current_path(stdfs::temp_directory_path(), ignored);
	stdfs::remove_all(sRoot, ignored);
}


OO_TEST_MAIN()
