/*	test_OOCacheManager.mm
        Unit tests for OOCacheManager (src/Core/OOCacheManager.h).

        The manager is a process-wide singleton that keeps named caches of
   property lists and writes them to one file in the user's caches directory.
   The test points that directory (HOMEPATH) and the built-in Resources (the
   current directory) at a scratch folder before the singleton exists, so
   nothing of the user's is read or written. It pins what the manager does:
   one shared instance; storing, replacing, reading and
   removing entries and whole caches; dirtiness (in the description); the cache
   directory (not made unless asked); a flush writing through the asynchronous
   work manager and a reload reading it back; writes refused while disallowed; a
   cache from another game version, or one that does not parse, discarded;
        clearing everything. The tests ask the C++ class. Run: bash
   tests/run.sh unit
*/

#include <process.h>

#include <cstdlib>
#include <filesystem>
#include <string>
#include <vector>

#include "OOCacheManager.h"
#include "oo_test.hpp"
#include "oofnd/FileSystem.hpp"

/*	The asynchronous work manager (OOAsyncWorkManager.mm) starts worker
   threads, so it is not linked. A stand-in answers the three calls the cache
   manager makes: it keeps each
   task and runs it when it is waited for, as a worker thread would have run it
   by then, and counts both.
*/
static int gTasksAdded = 0;
static int gTasksPerformed = 0;
static std::vector<oo::Ref<OOAsyncWorkTask>> gPendingTasks;

namespace {

class StubAsyncWorkManager : public OOAsyncWorkManager {
 public:
  StubAsyncWorkManager() = default;
};

}  // namespace

OOAsyncWorkManager* OOAsyncWorkManager::sharedAsyncWorkManager() {
  static OOAsyncWorkManager* manager = new StubAsyncWorkManager;
  return manager;
}

OOAsyncWorkManager::~OOAsyncWorkManager() {}

bool OOAsyncWorkManager::addTask(OOAsyncWorkTask* task,
                                 OOAsyncWorkPriority priority) {
  (void)priority;
  if (task == nullptr) return false;
  gPendingTasks.emplace_back(task);
  gTasksAdded++;
  return true;
}

void OOAsyncWorkManager::completePendingTasks() {}

void OOAsyncWorkManager::waitForTaskToComplete(OOAsyncWorkTask* task) {
  for (auto it = gPendingTasks.begin(); it != gPendingTasks.end(); ++it) {
    if (*it == task) {
      const oo::Ref<OOAsyncWorkTask> pending = *it;
      gPendingTasks.erase(it);
      pending->performAsyncTask();
      pending->completeAsyncTask();
      gTasksPerformed++;
      return;
    }
  }
}

namespace {

namespace stdfs = std::filesystem;

stdfs::path sRoot;

void WriteText(const stdfs::path& path, const std::string& text) {
  stdfs::create_directories(path.parent_path());
  OO_CHECK(oo::fs::writeFile(path, oo::Data(text.data(), text.size()),
                             oo::fs::WriteMode::direct)
               .has_value());
}

void SetGameVersion(const std::string& version) {
  WriteText(sRoot / "Resources" / "Info-gnustep.plist",
            "{ CFBundleVersion = \"" + version + "\"; }");
}

stdfs::path CacheFile() {
  return sRoot / "GNUstep" / "Library" / "Caches" / "org.aegidian.oolite" /
         "Oolite-cache.plist";
}

std::string CacheFileText() {
  const oo::fs::Result<oo::Data> data = oo::fs::readFile(CacheFile());
  if (!data.has_value()) return std::string();
  return std::string(reinterpret_cast<const char*>(data->bytes()),
                     data->length());
}

// The scratch home and game folder, made once, before the singleton exists.
void SetUp() {
  if (!sRoot.empty()) return;
  sRoot = stdfs::temp_directory_path() /
          ("oo-test-cachemanager-" +
           std::to_string(static_cast<unsigned long>(::_getpid())));
  stdfs::remove_all(sRoot);
  stdfs::create_directories(sRoot);
  OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
  stdfs::current_path(sRoot);
  SetGameVersion("9.9.9-test");
}

oo::PList Str(const char* string) { return oo::PList(std::string(string)); }

}  // namespace

OO_TEST(sharedInstanceStartsEmpty) {
  SetUp();
  {
    OO_CHECK(!stdfs::exists(CacheFile()));
    OOCacheManager* cache = OOCacheManager::sharedCache();
    OO_CHECK(cache != nullptr);
    OO_CHECK(OOCacheManager::sharedCache() == cache);
    OO_CHECK(cache->pListForKey("key", "cache").isNull());
    OO_CHECK(cache->descriptionComponents() ==
             std::optional<std::string>("dirty=no"));

    // Loading made no directory.
    OO_CHECK(!stdfs::exists(sRoot / "GNUstep"));
    OO_CHECK(!cache->cacheDirectoryPathCreatingIfNecessary(false).has_value());
    OO_CHECK(!stdfs::exists(sRoot / "GNUstep"));
  }
}

OO_TEST(entriesAndCaches) {
  SetUp();
  {
    OOCacheManager* cache = OOCacheManager::sharedCache();
    cache->setPList(Str("one"), "a", "first");
    cache->setPList(oo::PList(2), "b", "first");
    cache->setPList(Str("three"), "a", "second");
    OO_CHECK(cache->descriptionComponents() ==
             std::optional<std::string>("dirty=yes"));
    OO_CHECK(cache->pListForKey("a", "first") == Str("one"));
    OO_CHECK(cache->pListForKey("b", "first") == oo::PList(2));
    OO_CHECK(cache->pListForKey("a", "second") == Str("three"));
    OO_CHECK(cache->pListForKey("b", "second").isNull());
    OO_CHECK(cache->pListForKey("a", "third").isNull());

    // Replacing.
    cache->setPList(Str("uno"), "a", "first");
    OO_CHECK(cache->pListForKey("a", "first") == Str("uno"));

    // Removing an entry, and entries or caches that are not there.
    cache->removeObjectForKey("b", "first");
    OO_CHECK(cache->pListForKey("b", "first").isNull());
    OO_CHECK(cache->pListForKey("a", "first") == Str("uno"));
    cache->removeObjectForKey("b", "first");
    cache->removeObjectForKey("b", "none");
    cache->clearCache("none");

    // Clearing one cache.
    cache->clearCache("second");
    OO_CHECK(cache->pListForKey("a", "second").isNull());
    OO_CHECK(cache->pListForKey("a", "first") == Str("uno"));

    cache->clearCache("first");
    OO_CHECK(cache->pListForKey("a", "first").isNull());
  }
}

OO_TEST(flushWritesAndReloadReads) {
  SetUp();
  {
    OOCacheManager* cache = OOCacheManager::sharedCache();
    cache->setPList(Str("kept"), "k", "flushed");
    oo::PList::Dict dict;
    dict.emplace("x", oo::PList(1.5));
    dict.emplace("y", oo::PList(oo::PList::Array{Str("p"), Str("q")}));
    cache->setPList(oo::PList(dict), "d", "flushed");

    gTasksAdded = gTasksPerformed = 0;
    cache->flush();
    // The write is one task; flushing marks the manager clean at once.
    OO_CHECK(gTasksAdded == 1);
    OO_CHECK(gTasksPerformed == 0);
    OO_CHECK(cache->descriptionComponents() ==
             std::optional<std::string>("dirty=no"));
    // Nothing to flush while clean.
    cache->flush();
    OO_CHECK(gTasksAdded == 1);

    cache->finishOngoingFlush();
    OO_CHECK(gTasksPerformed == 1);
    OO_CHECK(stdfs::exists(CacheFile()));
    const std::string text = CacheFileText();
    OO_CHECK(text.find("<plist") != std::string::npos);
    OO_CHECK(text.find("9.9.9-test") != std::string::npos);
    OO_CHECK(text.find("kept") != std::string::npos);
    // Waiting again, with no write under way, does nothing.
    cache->finishOngoingFlush();
    OO_CHECK(gTasksPerformed == 1);

    // The directory now exists, so it is answered without being made.
    const std::optional<std::string> directory =
        cache->cacheDirectoryPathCreatingIfNecessary(false);
    OO_CHECK(directory.has_value());
    OO_CHECK(directory.has_value() &&
             stdfs::equivalent(oo::fs::pathFromUTF8(*directory),
                               CacheFile().parent_path()));

    // A change after the flush is lost by reloading; what was written comes
    // back.
    cache->setPList(Str("unsaved"), "u", "flushed");
    cache->reloadAllCaches();
    OO_CHECK(cache->pListForKey("u", "flushed").isNull());
    OO_CHECK(cache->pListForKey("k", "flushed") == Str("kept"));
    OO_CHECK(cache->pListForKey("d", "flushed") == oo::PList(dict));
    OO_CHECK(cache->descriptionComponents() ==
             std::optional<std::string>("dirty=no"));
  }
}

OO_TEST(writesDisallowed) {
  SetUp();
  {
    OOCacheManager* cache = OOCacheManager::sharedCache();
    cache->setAllowCacheWrites(false);
    cache->setPList(Str("never written"), "n", "flushed");
    gTasksAdded = 0;
    cache->flush();
    OO_CHECK(gTasksAdded == 0);
    OO_CHECK(cache->descriptionComponents() ==
             std::optional<std::string>("dirty=yes"));

    cache->setAllowCacheWrites(true);
    cache->flush();
    OO_CHECK(gTasksAdded == 1);
    cache->finishOngoingFlush();
    OO_CHECK(CacheFileText().find("never written") != std::string::npos);
  }
}

OO_TEST(staleOrBadCacheDiscarded) {
  SetUp();
  {
    OOCacheManager* cache = OOCacheManager::sharedCache();
    OO_CHECK(cache->pListForKey("k", "flushed") == Str("kept"));

    // Another game version: the cache is dropped on reload, and the manager is
    // clean.
    SetGameVersion("1.0-other");
    cache->reloadAllCaches();
    OO_CHECK(cache->pListForKey("k", "flushed").isNull());
    OO_CHECK(cache->descriptionComponents() ==
             std::optional<std::string>("dirty=no"));
    // It still takes new entries.
    cache->setPList(Str("fresh"), "f", "new");
    OO_CHECK(cache->pListForKey("f", "new") == Str("fresh"));

    // A file that does not parse: no caches, and no crash.
    SetGameVersion("9.9.9-test");
    WriteText(CacheFile(), "this is not a property list {");
    cache->reloadAllCaches();
    OO_CHECK(cache->pListForKey("f", "new").isNull());
    cache->setPList(Str("again"), "g", "new");
    OO_CHECK(cache->pListForKey("g", "new") == Str("again"));
  }
}

OO_TEST(cxxApi) {
  SetUp();
  {
    OOCacheManager* cache = OOCacheManager::sharedCache();
    OO_CHECK(cache != nullptr);
    OO_CHECK(OOCacheManager::sharedCache() == cache);
    cache->setPList(Str("c"), "k", "cxx");
    OO_CHECK(cache->pListForKey("k", "cxx") == Str("c"));
    OO_CHECK(cache->descriptionComponents() ==
             std::optional<std::string>("dirty=yes"));
    cache->removeObjectForKey("k", "cxx");
    OO_CHECK(cache->pListForKey("k", "cxx").isNull());
    cache->setPList(Str("d"), "k", "cxx");
    cache->clearCache("cxx");
    OO_CHECK(cache->pListForKey("k", "cxx").isNull());

    gTasksAdded = gTasksPerformed = 0;
    cache->flush();
    OO_CHECK(gTasksAdded == 1);
    OO_CHECK(cache->descriptionComponents() ==
             std::optional<std::string>("dirty=no"));
    cache->finishOngoingFlush();
    OO_CHECK(gTasksPerformed == 1);
    OO_CHECK(cache->cacheDirectoryPathCreatingIfNecessary(false).has_value());
  }
}

OO_TEST(clearAllCaches) {
  SetUp();
  {
    OOCacheManager* cache = OOCacheManager::sharedCache();
    cache->setPList(Str("v"), "k", "c1");
    cache->flush();
    cache->finishOngoingFlush();
    OO_CHECK(cache->descriptionComponents() ==
             std::optional<std::string>("dirty=no"));

    cache->clearAllCaches();
    OO_CHECK(cache->pListForKey("k", "c1").isNull());
    OO_CHECK(cache->descriptionComponents() ==
             std::optional<std::string>("dirty=yes"));
    cache->setPList(Str("w"), "k", "c1");
    OO_CHECK(cache->pListForKey("k", "c1") == Str("w"));
  }
  std::error_code ignored;
  stdfs::current_path(stdfs::temp_directory_path(), ignored);
  stdfs::remove_all(sRoot, ignored);
}

OO_TEST_MAIN()
