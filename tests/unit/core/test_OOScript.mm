/*	test_OOScript.mm
	Unit tests for OOScript (src/Core/Scripting/OOScript.h/.mm): bead oo-604l, a Phase 3 conversion
	in the house style of the OOColor exemplar (proposed ADR-0056).

	OOScript is the abstract root of the scripts: its subclasses (OOJSScript and OOPListScript, C++)
	answer the name, description and version, whether they need a tickle, and run on a target; the
	root answers a display name and a description from them, and its class methods load scripts
	from files, folders and lists. The class methods reach the resource manager, the cache and the
	legacy-script sanitizer, so the test links every game object but main's
	(tests/unit/core/meson.build entry ['*'], amendment oo-44gg) and defines gDebugFlags. The user's
	directories point at a scratch folder (amendment oo-rmd7 item 4). JavaScript files are not
	loaded (that needs the engine); every path that would reach OOJSScript is one that fails first.
	The expectations were written against the Objective-C API and run on the unconverted class
	first: the root's own answers, an Objective-C subclass's overrides and [super ...], the loaders
	(no file, a folder, an unknown extension, a legacy script from the cache, names not found, a
	world-scripts list, a folder with no scripts). The crossing checks (ADR-0056 Amendment 1 item 8),
	added with the conversion, came last. Bead oo-9ht.133 deleted the Objective-C facade (ADR-0056
	amendment oo-9ht.133; retired under the standing approval oo-9n5p9, tools/retire-test-approvals.txt):
	the facade's crossing cases (crossingObjCSubclass, adapterOutlivesOwner, and crossingCxxSubclass's
	identity checks) went with it, and the cases that asked through the facade's selectors ask the
	C++ class, with every expectation kept (the Objective-C test subclass is a C++ one, its [super ...]
	the root's member).
	Run: bash tools/check-core-tests.sh test_OOScript
*/

#import "OOScript.h"
#import "OOPListScript.h"
#import "OOCacheManager.h"
#import "Entity.h"
#import "OODescription.h"
#include "oofnd/FileSystem.hpp"
#include "oofnd/String.hpp"
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


// A subclass that overrides the subclass responsibilities (an Objective-C one until bead
// oo-9ht.133; its [super ...] are the root's members).
class TestObjCScript final : public OOScript
{
public:
	std::optional<std::string> name() override				{ return std::string("objc"); }
	std::optional<std::string> scriptDescription() override	{ return std::string("an Objective-C test script"); }
	std::optional<std::string> version() override			{ if (hasVersion)  return std::string("1.5"); return std::nullopt; }
	bool requiresTickle() override							{ return true; }
	void runWithTarget(::Entity *target) override			{ runs++; lastTarget = target; }

	std::optional<std::string> superName()					{ return OOScript::name(); }
	std::optional<std::string> superDescriptionComponents()	{ return OOScript::descriptionComponents(); }
	bool superRequiresTickle()								{ return OOScript::requiresTickle(); }

	int		runs = 0;
	Entity	*lastTarget = nil;
	bool	hasVersion = false;
};


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
	sRoot = stdfs::temp_directory_path() / ("oo-test-script-" + std::to_string(static_cast<unsigned long>(::_getpid())));
	stdfs::remove_all(sRoot);
	stdfs::create_directories(sRoot);
	OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
	stdfs::current_path(sRoot);
	WriteText(sRoot / "Resources" / "Info-gnustep.plist", "{ CFBundleVersion = \"9.9.9-test\"; }");
}


// A folder under the scratch root, as the loaders spell paths (forward slashes).
std::string Folder(const char *name)
{
	const stdfs::path folder = sRoot / name;
	stdfs::create_directories(folder);
	return folder.generic_string();
}


// A legacy script file that exists, whose sanitized scripts are already in the cache under its path.
void CacheLegacyScript(const std::string &path, const char *scriptName)
{
	WriteText(stdfs::path(path), "{}");
	oo::PList::Dict entry;
	entry["script"] = oo::PList(oo::PList::Array{});
	oo::PList::Dict scripts;
	scripts[scriptName] = oo::PList(std::move(entry));
	[[OOCacheManager sharedCache] cxx_setPList:oo::PList(std::move(scripts)) forKey:path inCache:kCacheName];
}


std::vector<std::string> Names(const std::vector<oo::Ref<OOScript>> &scripts)
{
	std::vector<std::string> names;
	for (const auto &script : scripts)  names.push_back(script->name().value_or("<none>"));
	return names;
}

}	// namespace


OO_TEST(abstractRoot)
{
	SetUp();
	@autoreleasepool
	{
		// The root's own answers: none, and an error logged for each subclass responsibility.
		const oo::Ref<OOScript> root = oo::makeRef<OOScript>();
		OO_CHECK(root != nullptr);
		OO_CHECK(!root->name().has_value());
		OO_CHECK(!root->scriptDescription().has_value());
		OO_CHECK(!root->version().has_value());
		OO_CHECK(!root->displayName().has_value());
		OO_CHECK(!root->requiresTickle());
		root->runWithTarget(nil);
		OO_CHECK(root->description().find("\"(null)\" version (null)") != std::string::npos);
	}
}


OO_TEST(objCSubclass)
{
	SetUp();
	@autoreleasepool
	{
		const oo::Ref<TestObjCScript> script = oo::makeRef<TestObjCScript>();
		OO_CHECK_EQ(script->name().value_or("<none>"), "objc");
		OO_CHECK_EQ(script->displayName().value_or("<none>"), "objc");	// no version: just the name
		OO_CHECK(script->description().find("\"objc\" version (null)") != std::string::npos);

		script->hasVersion = true;
		OO_CHECK_EQ(script->displayName().value_or("<none>"), "objc 1.5");
		OO_CHECK_EQ(script->superDescriptionComponents().value_or("<none>"), "\"objc\" version 1.5");
		OO_CHECK(script->description().find("\"objc\" version 1.5") != std::string::npos);

		// [super ...] reaches the root's own answers.
		OO_CHECK(!script->superName().has_value());
		OO_CHECK(!script->superRequiresTickle());
		OO_CHECK(script->requiresTickle());

		Entity *target = [[[Entity alloc] init] autorelease];
		script->runWithTarget(target);
		OO_CHECK_EQ(script->runs, 1);
		OO_CHECK(script->lastTarget == target);
	}
}


OO_TEST(scriptsFromFileAtPath)
{
	SetUp();
	@autoreleasepool
	{
		const std::string folder = Folder("files");

		// No file, a folder, and an extension that is not a script's: none.
		OO_CHECK(!OOScript::scriptsFromFileAtPath(folder + "/missing.js").has_value());
		OO_CHECK(!OOScript::scriptsFromFileAtPath(folder).has_value());
		WriteText(stdfs::path(folder) / "notes.txt", "text");
		OO_CHECK(!OOScript::scriptsFromFileAtPath(folder + "/notes.txt").has_value());

		// A legacy script (its extension in any case) loads its property-list scripts.
		const std::string path = folder + "/legacy.PLIST";
		CacheLegacyScript(path, "legacy");
		const auto scripts = OOScript::scriptsFromFileAtPath(path);
		OO_CHECK(scripts.has_value() && scripts->size() == 1);
		if (scripts.has_value() && scripts->size() == 1)
		{
			OO_CHECK((Names(*scripts) == std::vector<std::string>{ "legacy" }));
			OO_CHECK(dynamic_cast<OOPListScript *>((*scripts)[0].get()) != nullptr);	// was -isKindOfClass: of the facade bead oo-9ht.57 deleted
		}
	}
}


OO_TEST(scriptsByName)
{
	SetUp();
	@autoreleasepool
	{
		// A name the resource manager does not find: none, and a list of such names loads nothing.
		OO_CHECK(!OOScript::scriptsFromFileNamed("oo-test-missing.js").has_value());
		const std::vector<oo::Ref<OOScript>> listed = OOScript::scriptsFromList(std::vector<std::string>{ "oo-test-missing.js", "oo-test-missing.plist" });
		OO_CHECK(listed.empty());
		OO_CHECK(OOScript::scriptsFromList(std::vector<std::string>()).empty());

		// The single JavaScript loaders: nil for no name, a legacy or unknown extension, or a name not found.
		for (int ai = 0; ai < 2; ai++)
		{
			auto load = [ai](const std::string &name) -> oo::Ref<OOScript>
			{
				if (ai)  return OOScript::jsAIScriptFromFileNamed(name, oo::PList());
				return OOScript::jsScriptFromFileNamed(name, oo::PList());
			};
			OO_CHECK(load("") == nullptr);
			OO_CHECK(load("oo-test.plist") == nullptr);
			OO_CHECK(load("oo-test.txt") == nullptr);
			OO_CHECK(load("oo-test-missing.js") == nullptr);
			OO_CHECK(load("oo-test-missing.ES") == nullptr);
		}
	}
}


OO_TEST(worldScriptsAtPath)
{
	SetUp();
	@autoreleasepool
	{
		// A folder with no scripts: none.
		OO_CHECK(!OOScript::worldScriptsAtPath(Folder("empty")).has_value());

		// world-scripts.plist names scripts to load by name; names not found load nothing, but the
		// list was found, so the answer is an empty list rather than none.
		const std::string listed = Folder("listed");
		WriteText(stdfs::path(listed) / "world-scripts.plist", "( \"oo-test-missing.js\" )");
		const auto fromList = OOScript::worldScriptsAtPath(listed);
		OO_CHECK(fromList.has_value() && fromList->empty());

		// A world-scripts.plist that is not an array is skipped; script.plist is the fallback.
		const std::string legacy = Folder("legacy");
		WriteText(stdfs::path(legacy) / "world-scripts.plist", "{ a = b; }");
		CacheLegacyScript(oo::str::appendingPathComponent(legacy, "script.plist"), "fallback");
		const auto fromLegacy = OOScript::worldScriptsAtPath(legacy);
		OO_CHECK(fromLegacy.has_value() && fromLegacy->size() == 1);
		if (fromLegacy.has_value() && fromLegacy->size() == 1)
		{
			OO_CHECK((Names(*fromLegacy) == std::vector<std::string>{ "fallback" }));
		}

		// world-scripts.plist wins over script.plist.
		WriteText(stdfs::path(legacy) / "world-scripts.plist", "( )");
		const auto listWins = OOScript::worldScriptsAtPath(legacy);
		OO_CHECK(listWins.has_value() && listWins->empty());
	}
}


// The crossing (ADR-0056 Amendment 1 item 8), after the conversion; its facade checks went with the
// facade (bead oo-9ht.133).

namespace {

// A C++ subclass, as a converted OOJSScript or OOPListScript will be.
class TestCxxScript final : public OOScript
{
public:
	std::optional<std::string> name() override				{ return std::string("cxx"); }
	std::optional<std::string> version() override			{ return std::string("2"); }
	bool requiresTickle() override							{ return true; }
	void runWithTarget(::Entity *target) override			{ runs++; lastTarget = target; }

	int runs = 0;
	::Entity *lastTarget = nullptr;
};

}	// namespace


OO_TEST(crossingCxxSubclass)
{
	SetUp();
	@autoreleasepool
	{
		// A C++ subclass's overrides answer (they answered through its facade).
		const oo::Ref<TestCxxScript> script = oo::makeRef<TestCxxScript>();
		OO_CHECK_EQ(script->name().value_or("<none>"), "cxx");
		OO_CHECK_EQ(script->version().value_or("<none>"), "2");
		OO_CHECK(!script->scriptDescription().has_value());	// not overridden: the root's
		OO_CHECK_EQ(script->displayName().value_or("<none>"), "cxx 2");
		OO_CHECK(script->requiresTickle());
		OO_CHECK(script->description().find("\"cxx\" version 2") != std::string::npos);
		Entity *target = [[[Entity alloc] init] autorelease];
		script->runWithTarget(target);
		OO_CHECK_EQ(script->runs, 1);
		OO_CHECK(script->lastTarget == target);

		// The loaders as static members.
		OO_CHECK(OOScript::scriptsFromList(std::vector<std::string>{ "oo-test-missing.js" }).empty());
		OO_CHECK(!OOScript::scriptsFromFileAtPath(Folder("files") + "/missing.js").has_value());
		OO_CHECK(OOScript::jsScriptFromFileNamed("", oo::PList()) == nullptr);
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
