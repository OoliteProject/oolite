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
	from both sides, the weak reference) came with the conversion, oo-u61e.4.
	Run: bash tools/check-core-tests.sh test_OOJSScript
*/

#import "OOJSScript.h"
#import "OOJavaScriptEngine.h"
#import "OOJSPropID.h"
#import "OODescription.h"
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
	(void)[OOJavaScriptEngine sharedEngine];
}


// A script file under the scratch root, as the game spells paths (forward slashes).
std::string Script(const std::string &relativePath, const std::string &source)
{
	const stdfs::path path = sRoot / relativePath;
	WriteText(path, source);
	return path.generic_string();
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
	@autoreleasepool
	{
		OOJSScript *script = [OOJSScript scriptWithPath:Script("named/named.js", kNamedScript) properties:oo::PList()];
		OO_CHECK(script != nil);
		if (script == nil)  return;
		OO_CHECK([script isKindOfClass:[OOScript class]]);
		OO_CHECK_EQ([script cxx_name].value_or("<none>"), "test-script");	// spaces and underscores stripped
		OO_CHECK_EQ([script cxx_version].value_or("<none>"), "1.0");
		OO_CHECK_EQ([script scriptDescription].value_or("<none>"), "A test");
		OO_CHECK_EQ([script displayName].value_or("<none>"), "test-script 1.0");
		OO_CHECK(![script requiresTickle]);
		[script runWithTarget:nil];	// does nothing
		OO_CHECK(oo::DescriptionOf(script).find("\"test-script\" version 1.0") != std::string::npos);
		OO_CHECK_EQ(Text([script cxx_propertyNamed:"name"]), "  test-script_ ");	// the property keeps what the script set
		OO_CHECK(![OOJSScript currentlyRunningScript]);
		OO_CHECK([OOJSScript scriptStack].empty());

		// No file: nil. (A file that does not compile is not loaded here: its error report goes
		// through the game's JS error reporter, which needs the running game.)
		OO_CHECK([OOJSScript scriptWithPath:(sRoot / "missing.js").generic_string() properties:oo::PList()] == nil);
	}
}


OO_TEST(defaultNames)
{
	SetUp();
	@autoreleasepool
	{
		// A script that names itself nothing is named after its file, or its OXP for script.js.
		OOJSScript *byFile = [OOJSScript scriptWithPath:Script("loose/unnamed.js", "\"use strict\";\n") properties:oo::PList()];
		OO_CHECK_EQ([byFile cxx_name].value_or("<none>"), "unnamed.js.anon-script");
		OO_CHECK(![byFile cxx_version].has_value());
		OO_CHECK_EQ([byFile displayName].value_or("<none>"), "unnamed.js.anon-script");
		OO_CHECK_EQ(Text([byFile cxx_propertyNamed:"name"]), "unnamed.js.anon-script");

		OOJSScript *byOXP = [OOJSScript scriptWithPath:Script("Foo.oxp/Config/script.js", "\"use strict\";\n") properties:oo::PList()];
		OO_CHECK_EQ([byOXP cxx_name].value_or("<none>"), "Foo.anon-script");

		OOJSScript *byFolder = [OOJSScript scriptWithPath:Script("Bar/Scripts/script.js", "\"use strict\";\n") properties:oo::PList()];
		OO_CHECK_EQ([byFolder cxx_name].value_or("<none>"), "Scripts.anon-script");
	}
}


OO_TEST(manifestAndProperties)
{
	SetUp();
	@autoreleasepool
	{
		WriteText(sRoot / "Baz.oxp" / "manifest.plist",
				  "{ identifier = \"org.test.baz\"; version = \"2.5\"; author = \"Tester\"; license = \"CC0\"; }");
		oo::PList::Dict given;
		given["mission"] = oo::PList(std::string("given"));
		OOJSScript *script = [OOJSScript scriptWithPath:Script("Baz.oxp/Config/script.js", "\"use strict\";\nthis.name = \"baz\";\n")
											 properties:oo::PList(std::move(given))];
		OO_CHECK(script != nil);
		if (script == nil)  return;
		OO_CHECK_EQ([script cxx_version].value_or("<none>"), "2.5");	// from the manifest
		OO_CHECK_EQ(Text([script cxx_propertyNamed:"author"]), "Tester");
		OO_CHECK_EQ(Text([script cxx_propertyNamed:"license"]), "CC0");
		OO_CHECK_EQ(Text([script cxx_propertyNamed:kLocalManifestProperty]), "org.test.baz");
		OO_CHECK_EQ(Text([script cxx_propertyNamed:"mission"]), "given");

		// Set and define from outside; nothing to set is refused.
		OO_CHECK([script setProperty:oo::PList(3) named:"three"]);
		OO_CHECK_EQ(Text([script cxx_propertyNamed:"three"]), "3");
		OO_CHECK([script defineProperty:oo::PList(std::string("fixed")) named:"constant"]);
		OO_CHECK_EQ(Text([script cxx_propertyNamed:"constant"]), "fixed");
		OO_CHECK(![script setProperty:oo::PList() named:"nothing"]);
		OO_CHECK(![script defineProperty:oo::PList() named:"nothing"]);
		OO_CHECK([script cxx_propertyNamed:"neverSet"].isNull());

		// A temporary manifest identifier sets nothing.
		WriteText(sRoot / "Tmp.oxp" / "manifest.plist", "{ identifier = \"__oolite.tmp.1\"; version = \"9\"; }");
		OOJSScript *temporary = [OOJSScript scriptWithPath:Script("Tmp.oxp/Config/script.js", "\"use strict\";\nthis.name = \"tmp\";\n") properties:oo::PList()];
		OO_CHECK(![temporary cxx_version].has_value());
		OO_CHECK([temporary cxx_propertyNamed:kLocalManifestProperty].isNull());
	}
}


OO_TEST(callMethod)
{
	SetUp();
	@autoreleasepool
	{
		OOJSScript *script = [OOJSScript scriptWithPath:Script("call/call.js", kNamedScript) properties:oo::PList()];
		OO_CHECK(script != nil);
		if (script == nil)  return;

		JSContext *context = OOJSAcquireContext();
		JSValue argv[1] = { JS_NewInt32(context, 5) };
		JSValue result = JS_UNDEFINED;
		OO_CHECK([script callMethod:OOJSID("bump") inContext:context withArguments:argv count:1 result:&result]);
		double number = 0;
		OO_CHECK(JS_ToFloat64(context, &number, result) == 0 && number == 5);
		JS_FreeValue(context, result);
		OO_CHECK([script callMethod:OOJSID("bump") inContext:context withArguments:argv count:1 result:NULL]);
		OO_CHECK_EQ(Text([script cxx_propertyWithID:OOJSID("counter") inContext:context]), "10");
		OO_CHECK(![script callMethod:OOJSID("noSuchMethod") inContext:context withArguments:NULL count:0 result:NULL]);
		JSValue self = [script oo_jsValueInContext:context];
		OO_CHECK(!JS_IsUndefined(self));
		JS_FreeValue(context, self);

		// A script that is not JavaScript answers NO (OOScript (JavaScriptEvents)).
		OOScript *plain = [[[OOScript alloc] init] autorelease];
		OO_CHECK(![plain callMethod:OOJSID("bump") inContext:context withArguments:argv count:1 result:NULL]);
		OOJSRelinquishContext(context);

		// After the call the stack of running scripts is empty again.
		OO_CHECK([OOJSScript currentlyRunningScript] == nil);
	}
}


OO_TEST(runningStack)
{
	SetUp();
	@autoreleasepool
	{
		OOJSScript *first = [OOJSScript scriptWithPath:Script("stack/first.js", "\"use strict\";\nthis.name = \"first\";\n") properties:oo::PList()];
		OOJSScript *second = [OOJSScript scriptWithPath:Script("stack/second.js", "\"use strict\";\nthis.name = \"second\";\n") properties:oo::PList()];
		OO_CHECK(first != nil && second != nil);

		[OOJSScript pushScript:first];
		OO_CHECK([OOJSScript currentlyRunningScript] == first);
		[OOJSScript pushScript:second];
		OO_CHECK([OOJSScript currentlyRunningScript] == second);
		const std::vector<oo::ObjCRef<OOJSScript *>> stack = [OOJSScript scriptStack];
		OO_CHECK(stack.size() == 2 && stack[0].get() == first && stack[1].get() == second);	// outermost first
		[OOJSScript popScript:second];
		OO_CHECK([OOJSScript currentlyRunningScript] == first);
		[OOJSScript popScript:first];
		OO_CHECK([OOJSScript currentlyRunningScript] == nil);
		OO_CHECK([OOJSScript scriptStack].empty());

		// A script-less push is allowed; the stack cannot be listed while it is on it.
		[OOJSScript pushScript:nil];
		OO_CHECK([OOJSScript currentlyRunningScript] == nil);
		[OOJSScript popScript:nil];
	}
}


// The crossing, after the conversion (bead oo-u61e.4): the facade is the script's identity.
OO_TEST(crossing)
{
	SetUp();
	@autoreleasepool
	{
		OOJSScript *script = [OOJSScript scriptWithPath:Script("crossing/crossing.js", kNamedScript) properties:oo::PList()];
		OO_CHECK(script != nil);
		if (script == nil)  return;
		cxx::OOJSScript *cxxScript = oo::ToCxx(script);
		OO_CHECK(cxxScript != nullptr);
		OO_CHECK(oo::ToObjC(cxxScript) == script);
		OO_CHECK(oo::ToCxx(static_cast<OOScript *>(script)) == cxxScript);	// through the root's facade too
		OO_CHECK(oo::ToObjC(static_cast<cxx::OOScript *>(cxxScript)) == script);
		OO_CHECK(oo::ToCxx(static_cast<OOJSScript *>(nil)) == nullptr);

		// The C++ members answer as the facade does, and the root's members reach the overrides.
		OO_CHECK_EQ(cxxScript->name().value_or("<none>"), "test-script");
		OO_CHECK_EQ(cxxScript->displayName().value_or("<none>"), "test-script 1.0");
		OO_CHECK_EQ(Text(cxxScript->propertyNamed("counter")), "0");
		OO_CHECK(cxxScript->setProperty(oo::PList(7), "counter"));
		OO_CHECK_EQ(Text([script cxx_propertyNamed:"counter"]), "7");

		// The running stack holds facades, from either side.
		cxx::OOJSScript::pushScript(script);
		OO_CHECK([OOJSScript currentlyRunningScript] == script);
		OO_CHECK(cxx::OOJSScript::currentlyRunningScript() == script);
		[OOJSScript popScript:script];
		OO_CHECK(cxx::OOJSScript::scriptStack().empty());

		// A weak reference is to the facade.
		OOWeakReference *weak = [[script weakRetain] autorelease];
		OO_CHECK([weak weakRefUnderlyingObject] == script);
	}
}


OO_TEST(engineReset)
{
	SetUp();
	@autoreleasepool
	{
		OOJSScript *script = [OOJSScript scriptWithPath:Script("reset/reset.js", kNamedScript) properties:oo::PList()];
		OO_CHECK(script != nil);
		if (script == nil)  return;
		oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineWillResetNotificationName, [OOJavaScriptEngine sharedEngine]);

		// Invalid from now on: no properties, no calls, and so described.
		OO_CHECK(oo::DescriptionOf(script).find("invalid script") != std::string::npos);
		OO_CHECK([script cxx_propertyNamed:"counter"].isNull());
		OO_CHECK(![script setProperty:oo::PList(1) named:"counter"]);
		JSContext *context = OOJSAcquireContext();
		OO_CHECK(![script callMethod:OOJSID("bump") inContext:context withArguments:NULL count:0 result:NULL]);
		JSValue self = [script oo_jsValueInContext:context];
		OO_CHECK(JS_IsUndefined(self));
		JS_FreeValue(context, self);
		OOJSRelinquishContext(context);
		OO_CHECK_EQ([script cxx_name].value_or("<none>"), "test-script");	// the name was kept
	}
}


// oo-9ht.142: a file that does not compile is not loaded (nil), its error goes through the
// engine's error reporter, and the failure path leaves nothing running and nothing dangling: the
// next script loads and runs as before.
OO_TEST(broken)
{
	SetUp();
	@autoreleasepool
	{
		OO_CHECK([OOJSScript scriptWithPath:Script("broken/broken.js", "\"use strict\";\nthis.name = ;\n") properties:oo::PList()] == nil);
		OO_CHECK([OOJSScript currentlyRunningScript] == nil);
		OO_CHECK([OOJSScript scriptStack].empty());
	}
	@autoreleasepool
	{
		OOJSScript *after = [OOJSScript scriptWithPath:Script("broken/after.js", kNamedScript) properties:oo::PList()];
		OO_CHECK(after != nil);
		OO_CHECK_EQ([after cxx_name].value_or("<none>"), "test-script");
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
