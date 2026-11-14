/*	test_OOPListScript.mm
	Unit tests for OOPListScript (src/Core/Scripting/OOPListScript.h/.mm): bead oo-q9q4, a Phase 3
	conversion in the house style of the OOColor exemplar (proposed ADR-0056).

	OOPListScript is a legacy (property-list) world script: +scriptsInPListFile: reads a file of
	named script arrays, sanitizes each, caches the sanitized scripts in OOCacheManager, and makes
	one script per array, answering the name, the metadata's description and version, and running
	its actions on the player. Its superclass OOScript was still Objective-C, and its file reaches
	the cache manager, the legacy-script sanitizer and the player, so the test links every game
	object but main's (tests/unit/core/meson.build entry ['*'], ADR-0056 amendment oo-44gg) and
	defines gDebugFlags. The user's directories point at a scratch folder (amendment oo-rmd7 item
	4). The sanitizer needs the game's resources, so the scripts come from the cache, as the game
	loads them after the first run, and from files with no script arrays. The expectations were
	written against the Objective-C API and run on the unconverted class first: the cached path
	(names in key order, metadata, a missing or ill-typed script array), the file path (no file, a
	file that is not a dictionary, a dictionary with nothing to sanitize and what it caches), the
	description and version, the display name, -requiresTickle, and a run with a target that is
	not a ship (commit 60996db56). They then ran through the facade, and the facade's contract was
	checked last.

	Bead oo-9ht.57 deleted the facade: OOPListScript is a C++ subclass of cxx::OOScript, and the
	scripts it makes cross as the root's facade, an OOScript, through which the cases above still
	ask (the OOScript selectors are the root's) with every expectation kept; +scriptsInPListFile:
	is the C++ member, and -isKindOfClass:[OOPListScript class] a dynamic_cast of the C++ script.
	The facade's own case (facade) was retired with it (ADR-0049, standing approval oo-9n5p9), and
	plistScriptCrossesAsTheRootFacade pinned the crossing. Bead oo-9ht.133 deleted the root's facade
	(ADR-0056 amendment oo-9ht.133, the same approval): the scripts are held as oo::Ref<OOScript>, the
	cases ask the C++ class what they asked through the root's selectors, with every expectation kept,
	and plistScriptIsItsOwnObject replaces the root-facade crossing case.
	Run: bash tools/check-core-tests.sh
*/

#import "OOPListScript.h"
#import "OOCacheManager.h"
#import "Entity.h"
#import "OODescription.h"
#include "oofnd/FileSystem.hpp"
#include "oo_test.hpp"

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

namespace stdfs = std::filesystem;

stdfs::path sRoot;
const char *const kCacheName = "sanitized legacy scripts";


void WriteText(const stdfs::path &path, const std::string &text)
{
	stdfs::create_directories(path.parent_path());
	OO_CHECK(oo::fs::writeFile(path, oo::Data(text.data(), text.size()), oo::fs::WriteMode::direct).has_value());
}


// The scratch home and game folder, made once, before the cache manager exists.
void SetUp()
{
	if (!sRoot.empty())  return;
	sRoot = stdfs::temp_directory_path() / ("oo-test-plistscript-" + std::to_string(static_cast<unsigned long>(::_getpid())));
	stdfs::remove_all(sRoot);
	stdfs::create_directories(sRoot);
	OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
	stdfs::current_path(sRoot);
	WriteText(sRoot / "Resources" / "Info-gnustep.plist", "{ CFBundleVersion = \"9.9.9-test\"; }");
}


oo::PList Str(const char *string)
{
	return oo::PList(std::string(string));
}


oo::PList Dict(std::vector<std::pair<std::string, oo::PList>> entries)
{
	oo::PList::Dict dict;
	for (auto &entry : entries)  dict[entry.first] = std::move(entry.second);
	return oo::PList(std::move(dict));
}


std::vector<std::string> Names(const std::vector<oo::Ref<OOScript>> &scripts)
{
	std::vector<std::string> names;
	for (const auto &script : scripts)  names.push_back(script->name().value_or("<none>"));
	return names;
}

}	// namespace


OO_TEST(cachedScripts)
{
	SetUp();
	@autoreleasepool
	{
		const oo::PList metadata = Dict({ { "description", Str("A test script") }, { "version", Str("1.2") } });
		const oo::PList actions = oo::PList(oo::PList::Array{ Str("set: mission_x 1") });
		[[OOCacheManager sharedCache] cxx_setPList:Dict({
				{ "zeta", Dict({ { "script", actions }, { "!metadata!", metadata } }) },
				{ "alpha", Dict({ { "script", actions } }) },
				{ "badScript", Dict({ { "script", Str("not an array") } }) },
				{ "notADict", Str("x") },
			}) forKey:"cached.plist" inCache:kCacheName];

		const auto scripts = OOPListScript::scriptsInPListFile("cached.plist");
		OO_CHECK(scripts.has_value());
		if (!scripts.has_value())  return;
		OO_CHECK_EQ(scripts->size(), 4u);
		OO_CHECK((Names(*scripts) == std::vector<std::string>{ "alpha", "badScript", "notADict", "zeta" }));	// key order
		for (const auto &script : *scripts)  OO_CHECK(dynamic_cast<OOPListScript *>(script.get()) != nullptr);

		OOScript *alpha = (*scripts)[0].get();
		OOScript *zeta = (*scripts)[3].get();
		OO_CHECK(!alpha->scriptDescription().has_value());
		OO_CHECK(!alpha->version().has_value());
		OO_CHECK_EQ(alpha->displayName().value_or("<none>"), "alpha");
		OO_CHECK_EQ(zeta->scriptDescription().value_or("<none>"), "A test script");
		OO_CHECK_EQ(zeta->version().value_or("<none>"), "1.2");
		OO_CHECK_EQ(zeta->displayName().value_or("<none>"), "zeta 1.2");
		OO_CHECK(zeta->requiresTickle());
		OO_CHECK(zeta->description().find("OOPListScript") != std::string::npos);

		// A run whose target is not a ship logs and does nothing (it never reaches the player).
		Entity *notAShip = [[[Entity alloc] init] autorelease];
		zeta->runWithTarget(notAShip);
	}
}


OO_TEST(metadataTypes)
{
	SetUp();
	@autoreleasepool
	{
		// A description or version that is not a string reads as none.
		const oo::PList metadata = Dict({ { "description", oo::PList(3) }, { "version", oo::PList(oo::PList::Array{}) } });
		[[OOCacheManager sharedCache] cxx_setPList:Dict({ { "odd", Dict({ { "script", oo::PList(oo::PList::Array{}) }, { "!metadata!", metadata } }) } })
											forKey:"odd.plist" inCache:kCacheName];
		const auto scripts = OOPListScript::scriptsInPListFile("odd.plist");
		OO_CHECK(scripts.has_value() && scripts->size() == 1);
		if (!scripts.has_value() || scripts->size() != 1)  return;
		OOScript *odd = (*scripts)[0].get();
		OO_CHECK(!odd->scriptDescription().has_value());
		OO_CHECK(!odd->version().has_value());
		OO_CHECK_EQ(odd->displayName().value_or("<none>"), "odd");
		OO_CHECK_EQ(odd->name().value_or("<none>"), "odd");	// the name is the key, whatever the metadata says

		// The metadata's own name does not win over the key.
		[[OOCacheManager sharedCache] cxx_setPList:Dict({ { "key", Dict({ { "script", oo::PList(oo::PList::Array{}) }, { "!metadata!", Dict({ { "name", Str("other") } }) } }) } })
											forKey:"named.plist" inCache:kCacheName];
		const auto named = OOPListScript::scriptsInPListFile("named.plist");
		OO_CHECK(named.has_value() && named->size() == 1 && (*named)[0]->name().value_or("<none>") == "key");
	}
}


OO_TEST(files)
{
	SetUp();
	@autoreleasepool
	{
		// No file (and nothing cached): none.
		OO_CHECK(!OOPListScript::scriptsInPListFile((sRoot / "missing.plist").string()).has_value());

		// A file that is not a dictionary: none.
		WriteText(sRoot / "array.plist", "( a, b )");
		OO_CHECK(!OOPListScript::scriptsInPListFile((sRoot / "array.plist").string()).has_value());

		// A dictionary with no script arrays: no scripts, and an empty dictionary is cached for it.
		const std::string path = (sRoot / "empty.plist").string();
		WriteText(sRoot / "empty.plist", "{ \"!metadata!\" = { version = \"2\"; }; notAScript = \"text\"; }");
		const auto scripts = OOPListScript::scriptsInPListFile(path);
		OO_CHECK(scripts.has_value() && scripts->empty());
		const oo::PList cached = [[OOCacheManager sharedCache] cxx_pListForKey:path inCache:kCacheName];
		OO_CHECK(cached.isDict() && cached.count() == 0);
		// The second read comes from the cache (the file is gone).
		stdfs::remove(sRoot / "empty.plist");
		const auto again = OOPListScript::scriptsInPListFile(path);
		OO_CHECK(again.has_value() && again->empty());
	}
}


// A plist script is its own object, held as oo::Ref<OOScript> (bead oo-9ht.133 deleted the root's
// facade, as which Objective-C saw it since bead oo-9ht.57).
OO_TEST(plistScriptIsItsOwnObject)
{
	SetUp();
	@autoreleasepool
	{
		[[OOCacheManager sharedCache] cxx_setPList:Dict({ { "one", Dict({ { "script", oo::PList(oo::PList::Array{}) }, { "!metadata!", Dict({ { "version", Str("3") } }) } }) } })
											forKey:"facade.plist" inCache:kCacheName];
		const auto scripts = OOPListScript::scriptsInPListFile("facade.plist");
		OO_CHECK(scripts.has_value() && scripts->size() == 1);
		if (!scripts.has_value() || scripts->size() != 1)  return;
		OOPListScript *script = dynamic_cast<OOPListScript *>((*scripts)[0].get());
		OO_CHECK(script != nullptr);
		if (script == nullptr)  return;
		OO_CHECK_EQ(script->name().value_or("<none>"), "one");
		OO_CHECK_EQ(script->version().value_or("<none>"), "3");
		OO_CHECK(script->requiresTickle());
		OO_CHECK(script->description().starts_with("<OOPListScript 0x"));
		OO_CHECK(OOScriptInObjectNode(OOScriptObjectNode(script)) == script);	// it travels in plist data as itself
	}
}


OO_TEST(cleanUp)
{
	stdfs::current_path(stdfs::temp_directory_path());
	std::error_code ignored;
	stdfs::remove_all(sRoot, ignored);
	OO_CHECK(true);
}


OO_TEST_MAIN()
