/*	test_OOJSScript.mm
	Unit tests for OOJSScript (src/Core/Scripting/OOJSScript.h/.mm): bead oo-u61e.3, the test-first
	half of oo-u61e's Phase 3 conversion (proposed ADR-0056, the OOColor house style; the conversion
	is oo-u61e.4).

	OOJSScript is a JavaScript world or ship script: it compiles a file into a JS object of class
	Script, sets that object's default properties from the OXP's manifest and the caller's
	properties, runs the file, and then answers the name, version and description the script set
	(or a name made from the path), reads and sets the object's properties, calls its methods with
	itself on the stack of running scripts, and goes invalid when the engine resets. It needs the
	real engine and the cache, so the test links every game object but main's
	(tests/unit/core/meson.build entry ['*'], amendment oo-44gg), defines gDebugFlags and points the
	user's directories at a scratch folder (amendment oo-rmd7 item 4). The scripts are written to
	that folder. The expectations were written against the Objective-C API and run on the
	unconverted class first; the crossing test (facade identity, the C++ members, the running stack
	from both sides, the weak reference) came with the conversion, oo-u61e.4, and changed when bead
	oo-9ht.137 deleted the facade (standing approval oo-9n5p9): the script's object was the OOScript
	root's facade, made by OOJSScript::scriptWithPath(), and the property members were asked of the
	C++ script. Bead oo-9ht.133 deleted the root's facade (ADR-0056 amendment oo-9ht.133, under the
	same approval): the script is held as oo::Ref<OOJSScript>, every case asks the C++ class what it
	asked through the selectors, with every expectation kept, and the crossing case pins the new
	identity (the running stack holds the C++ script, the Script object's private slot refers to it
	weakly).
	Run: bash tools/check-core-tests.sh test_OOJSScript
*/

#include "OOJSScript.h"
#include "OOJavaScriptEngine.h"
#include "OOJSPropID.h"
#include "OODescription.h"
#include "oofnd/FileSystem.hpp"
#include "oofnd/Notification.hpp"
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


void WriteText(const stdfs::path &path, const std::string &text)
{
	stdfs::create_directories(path.parent_path());
	OO_CHECK(oo::fs::writeFile(path, oo::Data(text.data(), text.size()), oo::fs::WriteMode::direct).has_value());
}


// The scratch home and game folder, made once, before the cache manager and the engine exist.
void SetUp()
{
	if (!sRoot.empty())  return;
	sRoot = stdfs::temp_directory_path() / ("oo-test-jsscript-" + std::to_string(static_cast<unsigned long>(::_getpid())));
	stdfs::remove_all(sRoot);
	stdfs::create_directories(sRoot);
	OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
	stdfs::current_path(sRoot);
	WriteText(sRoot / "Resources" / "Info-gnustep.plist", "{ CFBundleVersion = \"9.9.9-test\"; }");
	(void)OOJavaScriptEngine::sharedEngine();
}


// A script file under the scratch root, as the game spells paths (forward slashes).
std::string Script(const std::string &relativePath, const std::string &source)
{
	const stdfs::path path = sRoot / relativePath;
	WriteText(path, source);
	return path.generic_string();
}


// The script (its facades, which answered -cxx_propertyNamed: and the property setters, were
// deleted by beads oo-9ht.137 and oo-9ht.133).
OOJSScript *JS(const oo::Ref<OOJSScript> &script)
{
	return script.get();
}


std::string Text(const oo::PList &value)
{
	if (const std::string *string = value.getIf<std::string>())  return *string;
	return value.isNull() ? "<null>" : oo::DescriptionOf(value);
}


const char *const kNamedScript =
	"\"use strict\";\n"
	"this.name = \"  test-script_ \";\n"
	"this.version = \"1.0\";\n"
	"this.description = \"A test\";\n"
	"this.counter = 0;\n"
	"this.bump = function (n) { this.counter += n; return this.counter; };\n";

}	// namespace


OO_TEST(load)
{
	SetUp();
	{
		const oo::Ref<OOJSScript> script = OOJSScript::scriptWithPath(Script("named/named.js", kNamedScript), oo::PList());
		OO_CHECK(script != nullptr);
		if (script == nullptr)  return;
		OO_CHECK(dynamic_cast<OOScript *>(script.get()) != nullptr);
		OO_CHECK_EQ(script->name().value_or("<none>"), "test-script");	// spaces and underscores stripped
		OO_CHECK_EQ(script->version().value_or("<none>"), "1.0");
		OO_CHECK_EQ(script->scriptDescription().value_or("<none>"), "A test");
		OO_CHECK_EQ(script->displayName().value_or("<none>"), "test-script 1.0");
		OO_CHECK(!script->requiresTickle());
		script->runWithTarget(nil);	// does nothing
		OO_CHECK(script->description().find("\"test-script\" version 1.0") != std::string::npos);
		OO_CHECK_EQ(Text(JS(script)->propertyNamed("name")), "  test-script_ ");	// the property keeps what the script set
		OO_CHECK(!OOJSScript::currentlyRunningScript());
		OO_CHECK(OOJSScript::scriptStack().empty());

		// No file: nil. (A file that does not compile is not loaded here: its error report goes
		// through the game's JS error reporter, which needs the running game.)
		OO_CHECK(OOJSScript::scriptWithPath((sRoot / "missing.js").generic_string(), oo::PList()) == nullptr);
	}
}


OO_TEST(defaultNames)
{
	SetUp();
	{
		// A script that names itself nothing is named after its file, or its OXP for script.js.
		const oo::Ref<OOJSScript> byFile = OOJSScript::scriptWithPath(Script("loose/unnamed.js", "\"use strict\";\n"), oo::PList());
		OO_CHECK_EQ(byFile->name().value_or("<none>"), "unnamed.js.anon-script");
		OO_CHECK(!byFile->version().has_value());
		OO_CHECK_EQ(byFile->displayName().value_or("<none>"), "unnamed.js.anon-script");
		OO_CHECK_EQ(Text(JS(byFile)->propertyNamed("name")), "unnamed.js.anon-script");

		const oo::Ref<OOJSScript> byOXP = OOJSScript::scriptWithPath(Script("Foo.oxp/Config/script.js", "\"use strict\";\n"), oo::PList());
		OO_CHECK_EQ(byOXP->name().value_or("<none>"), "Foo.anon-script");

		const oo::Ref<OOJSScript> byFolder = OOJSScript::scriptWithPath(Script("Bar/Scripts/script.js", "\"use strict\";\n"), oo::PList());
		OO_CHECK_EQ(byFolder->name().value_or("<none>"), "Scripts.anon-script");
	}
}


OO_TEST(manifestAndProperties)
{
	SetUp();
	{
		WriteText(sRoot / "Baz.oxp" / "manifest.plist",
				  "{ identifier = \"org.test.baz\"; version = \"2.5\"; author = \"Tester\"; license = \"CC0\"; }");
		oo::PList::Dict given;
		given["mission"] = oo::PList(std::string("given"));
		const oo::Ref<OOJSScript> script = OOJSScript::scriptWithPath(Script("Baz.oxp/Config/script.js", "\"use strict\";\nthis.name = \"baz\";\n")
											, oo::PList(std::move(given)));
		OO_CHECK(script != nullptr);
		if (script == nullptr)  return;
		OO_CHECK_EQ(script->version().value_or("<none>"), "2.5");	// from the manifest
		OO_CHECK_EQ(Text(JS(script)->propertyNamed("author")), "Tester");
		OO_CHECK_EQ(Text(JS(script)->propertyNamed("license")), "CC0");
		OO_CHECK_EQ(Text(JS(script)->propertyNamed(kLocalManifestProperty)), "org.test.baz");
		OO_CHECK_EQ(Text(JS(script)->propertyNamed("mission")), "given");

		// Set and define from outside; nothing to set is refused.
		OO_CHECK(JS(script)->setProperty(oo::PList(3), "three"));
		OO_CHECK_EQ(Text(JS(script)->propertyNamed("three")), "3");
		OO_CHECK(JS(script)->defineProperty(oo::PList(std::string("fixed")), "constant"));
		OO_CHECK_EQ(Text(JS(script)->propertyNamed("constant")), "fixed");
		OO_CHECK(!JS(script)->setProperty(oo::PList(), "nothing"));
		OO_CHECK(!JS(script)->defineProperty(oo::PList(), "nothing"));
		OO_CHECK(JS(script)->propertyNamed("neverSet").isNull());

		// A temporary manifest identifier sets nothing.
		WriteText(sRoot / "Tmp.oxp" / "manifest.plist", "{ identifier = \"__oolite.tmp.1\"; version = \"9\"; }");
		const oo::Ref<OOJSScript> temporary = OOJSScript::scriptWithPath(Script("Tmp.oxp/Config/script.js", "\"use strict\";\nthis.name = \"tmp\";\n"), oo::PList());
		OO_CHECK(!temporary->version().has_value());
		OO_CHECK(JS(temporary)->propertyNamed(kLocalManifestProperty).isNull());
	}
}


OO_TEST(callMethod)
{
	SetUp();
	{
		const oo::Ref<OOJSScript> script = OOJSScript::scriptWithPath(Script("call/call.js", kNamedScript), oo::PList());
		OO_CHECK(script != nullptr);
		if (script == nullptr)  return;

		ooscript::Context context = OOJSAcquireContext();
		ooscript::Value argv[1] = { ooscript::int32Value(5) };
		ooscript::Value result = ooscript::undefinedValue();
		OO_CHECK(script->callMethod(OOJSID("bump"), context, argv, 1, &result));
		double number = 0;
		OO_CHECK(ooscript::valueToNumber(context, result, &number) && number == 5);
		OO_CHECK(script->callMethod(OOJSID("bump"), context, argv, 1, NULL));
		OO_CHECK_EQ(Text(JS(script)->propertyWithID(OOJSID("counter"), context)), "10");
		OO_CHECK(!script->callMethod(OOJSID("noSuchMethod"), context, NULL, 0, NULL));
		OO_CHECK(!ooscript::isUndefined(script->jsValueInContext(context)));

		// A script that is not JavaScript answers NO (OOScript (JavaScriptEvents)).
		const oo::Ref<OOScript> plain = oo::makeRef<OOScript>();
		OO_CHECK(!plain->callMethod(OOJSID("bump"), context, argv, 1, NULL));
		OOJSRelinquishContext(context);

		// After the call the stack of running scripts is empty again.
		OO_CHECK(OOJSScript::currentlyRunningScript() == nullptr);
	}
}


OO_TEST(runningStack)
{
	SetUp();
	{
		const oo::Ref<OOJSScript> first = OOJSScript::scriptWithPath(Script("stack/first.js", "\"use strict\";\nthis.name = \"first\";\n"), oo::PList());
		const oo::Ref<OOJSScript> second = OOJSScript::scriptWithPath(Script("stack/second.js", "\"use strict\";\nthis.name = \"second\";\n"), oo::PList());
		OO_CHECK(first != nullptr && second != nullptr);

		OOJSScript::pushScript(first.get());
		OO_CHECK(OOJSScript::currentlyRunningScript() == first.get());
		OOJSScript::pushScript(second.get());
		OO_CHECK(OOJSScript::currentlyRunningScript() == second.get());
		const std::vector<oo::Ref<OOJSScript>> stack = OOJSScript::scriptStack();
		OO_CHECK(stack.size() == 2 && stack[0].get() == first.get() && stack[1].get() == second.get());	// outermost first
		OOJSScript::popScript(second.get());
		OO_CHECK(OOJSScript::currentlyRunningScript() == first.get());
		OOJSScript::popScript(first.get());
		OO_CHECK(OOJSScript::currentlyRunningScript() == nullptr);
		OO_CHECK(OOJSScript::scriptStack().empty());

		// A script-less push is allowed; the stack cannot be listed while it is on it.
		OOJSScript::pushScript(nullptr);
		OO_CHECK(OOJSScript::currentlyRunningScript() == nullptr);
		OOJSScript::popScript(nullptr);
	}
}


// The crossing, after the facades' deletion (beads oo-9ht.137 and oo-9ht.133; the conversion was
// oo-u61e.4): the script's identity is the C++ object. The running stack holds it, weakly, and the
// Script object's private slot refers to it weakly, as it held the facade's weak reference.
OO_TEST(crossing)
{
	SetUp();
	{
		oo::Ref<OOJSScript> script = OOJSScript::scriptWithPath(Script("crossing/crossing.js", kNamedScript), oo::PList());
		OO_CHECK(script != nullptr);
		if (script == nullptr)  return;

		// The C++ members answer, and the root's members reach the overrides.
		OOScript *root = script.get();
		OO_CHECK_EQ(script->name().value_or("<none>"), "test-script");
		OO_CHECK_EQ(root->name().value_or("<none>"), "test-script");
		OO_CHECK_EQ(root->displayName().value_or("<none>"), "test-script 1.0");
		OO_CHECK_EQ(Text(script->propertyNamed("counter")), "0");
		OO_CHECK(script->setProperty(oo::PList(7), "counter"));
		OO_CHECK_EQ(Text(script->propertyNamed("counter")), "7");

		// The running stack holds the script.
		OOJSScript::pushScript(script.get());
		OO_CHECK(OOJSScript::currentlyRunningScript() == script.get());
		OOJSScript::popScript(script.get());
		OO_CHECK(OOJSScript::scriptStack().empty());

		// A weak push answers the script while it lives (a timer's or definition's).
		const oo::WeakRef<OOJSScript> weak = script.get();
		OOJSScript::pushScript(weak);
		OO_CHECK(OOJSScript::currentlyRunningScript() == script.get());
		OOJSScript::popScript(weak.get());

		// The Script object converts back to the script (a plist Object node), and its JS glue
		// answers; any other script answers undefined.
		ooscript::Context context = OOJSAcquireContext();
		ooscript::Value value = script->jsValueInContext(context);
		OOJSAddGCValueRoot(context, &value, "test_OOJSScript crossing");
		OO_CHECK(!ooscript::isUndefined(value));
		OO_CHECK(OOScriptInObjectNode(cxx_OOJSPListFromJSValue(context, value)) == script.get());
		OO_CHECK(script->jsClassName() == std::optional<std::string>("Script"));
		OO_CHECK(script->jsDescription() == std::optional<std::string>("[Script \"test-script\" version 1.0]"));
		const oo::Ref<OOScript> plain = oo::makeRef<OOScript>();
		OO_CHECK(ooscript::isUndefined(plain->jsValueInContext(context)));

		// The slot does not keep the script: once it goes, the object converts to nothing, and a
		// weak push answers no script.
		script = nullptr;
		OO_CHECK(weak.get() == nullptr);
		OO_CHECK(cxx_OOJSPListFromJSValue(context, value).isNull());
		OOJSScript::pushScript(weak);
		OO_CHECK(OOJSScript::currentlyRunningScript() == nullptr);
		OO_CHECK(OOJSScript::scriptStack().size() == 1 && OOJSScript::scriptStack()[0] == nullptr);
		OOJSScript::popScript(nullptr);
		ooscript::removeValueRoot(context, &value);
		OOJSRelinquishContext(context);
	}
}


OO_TEST(engineReset)
{
	SetUp();
	{
		const oo::Ref<OOJSScript> script = OOJSScript::scriptWithPath(Script("reset/reset.js", kNamedScript), oo::PList());
		OO_CHECK(script != nullptr);
		if (script == nullptr)  return;
		oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineWillResetNotificationName, OOJavaScriptEngine::sharedEngine());

		// Invalid from now on: no properties, no calls, and so described.
		OO_CHECK(script->description().find("invalid script") != std::string::npos);
		OO_CHECK(JS(script)->propertyNamed("counter").isNull());
		OO_CHECK(!JS(script)->setProperty(oo::PList(1), "counter"));
		ooscript::Context context = OOJSAcquireContext();
		OO_CHECK(!script->callMethod(OOJSID("bump"), context, NULL, 0, NULL));
		OO_CHECK(ooscript::isUndefined(script->jsValueInContext(context)));
		OOJSRelinquishContext(context);
		OO_CHECK_EQ(script->name().value_or("<none>"), "test-script");	// the name was kept
	}
}


// oo-9ht.142: a file that does not compile is not loaded (nil), its error goes through the
// engine's error reporter, and the failure path leaves nothing running and nothing dangling: the
// next script loads and runs as before.
OO_TEST(broken)
{
	SetUp();
	{
		OO_CHECK(OOJSScript::scriptWithPath(Script("broken/broken.js", "\"use strict\";\nthis.name = ;\n"), oo::PList()) == nullptr);
		OO_CHECK(OOJSScript::currentlyRunningScript() == nullptr);
		OO_CHECK(OOJSScript::scriptStack().empty());
	}
	{
		const oo::Ref<OOJSScript> after = OOJSScript::scriptWithPath(Script("broken/after.js", kNamedScript), oo::PList());
		OO_CHECK(after != nullptr);
		OO_CHECK_EQ(after->name().value_or("<none>"), "test-script");
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
