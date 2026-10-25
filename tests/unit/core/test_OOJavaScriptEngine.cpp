/*	test_OOJavaScriptEngine.mm
	Unit tests for the JavaScript engine (src/Core/Scripting/OOJavaScriptEngine.h/.mm): the four slice
	beads of docs/phases/3-slices/OOJavaScriptEngine.md (oo-10qz, oo-903c, oo-elta, oo-k4nu; proposed
	ADR-0056 amendment oo-dqxj item 2).

	The engine is the singleton that owns the JS runtime and the main thread context: it makes the
	global object and every Oolite class on it, looks up the standard classes, calls JS functions,
	keeps the error-reporting flags, reports errors and warnings (to the log and to a debug monitor),
	describes values and dumps the stack. The same file holds the JS glue of OOObject, OONativeVector
	and OONull, OOJSValue, the generic object wrapper, the entity predicates and the JS -> property
	list converters. It needs the real game, so the test links every game object but main's
	(tests/unit/core/meson.build entry ['*'], as test_OOJSScript does) and points the user's
	directories at a scratch folder. The expectations were written against the Objective-C API and
	run on the unconverted file first (ADR-0056 item 7); they pin what the scripts and the log see.
	Run: bash tools/check-core-tests.sh test_OOJavaScriptEngine
*/

#include "OOJavaScriptEngine.h"
#include "OOJSScript.h"
#include "OOJSPropID.h"
#include "OODescription.h"
#include "Entity.h"
#include "EntityOOJavaScriptExtensions.h"
#include "OOVector.h"
#include "OOObjCPList.h"
#include "oofnd/objc/OOException.h"
#include "OOJSPrivateObject.h"
#include "oofnd/FileSystem.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/Notification.hpp"
#include "oo_test.hpp"

#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <process.h>
#include <string>
#include <vector>


extern ooscript::Context gOOJSMainThreadContext;	// OOJavaScriptEngine.mm


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


// (TestNative, a plain OOObject whose JS value and description the root's JS glue gave, went with
// that glue, bead oo-4aq6a.6.2; cxxObjectWrapper counts TestCxxNative's finalisation.)


// A C++ native object, as a JS object's private slot holds since bead oo-4aq6a.6: counts its JS
// wrapper's finalisation and its own, and is a plist Object node's foreign object.
static int sCxxNativeDeallocs = 0;

class TestCxxNative : public oo::PListForeign, public OOJSPrivateObject
{
public:
	~TestCxxNative() override  { sCxxNativeDeallocs++; }
	std::string className() const override  { return "TestCxxNative"; }
	std::string description() const override  { return "<TestCxxNative>"; }
	ooscript::Value jsValueInContext(ooscript::Context) override  { return ooscript::undefinedValue(); }
	void clearJSSelf(ooscript::Object) override  { _clears++; }
	std::optional<std::string> jsDescription() override  { return std::string("[TestCxxNative x=1]"); }

	int		_clears = 0;
};


// An entity whose script-visible answers the test chooses (the predicates ask only these). An
// Objective-C subclass until bead oo-j12i2: a C++ one overriding the virtual members its selectors
// became; its -isShip, -isSubEntity and -status answers are the C++ entity's own flags and status,
// which the predicates read for a C++ entity, set where the test set its ivars.
class TestScriptEntity : public Entity
{
public:
	bool isVisibleToScripts() override  { return _scriptVisible; }
	bool isPlanet() override  { return false; }
	ooscript::Value jsValueInContext(ooscript::Context) override  { return ooscript::int32Value(42); }

	bool _scriptVisible = false;
};


#if OOJSENGINE_MONITOR_SUPPORT
// A debug monitor that records what the engine sends it. A C++ OOJavaScriptEngineMonitor since bead
// oo-9ht.74.1 (it was an Objective-C object adopting the protocol); the same records.
namespace {

// The records (the Objective-C class's @public ivars).
struct TestMonitorRecord
{
	int							_errors = 0;
	int							_logs = 0;
	OOJavaScriptEngine			*_engine = nullptr;
	BOOL						_showLocation = NO;
	std::string					_message;
	std::optional<std::string>	_messageClass;
};


class TestMonitor : public OOJavaScriptEngineMonitor, public TestMonitorRecord
{
public:
	void jsEngine(OOJavaScriptEngine *engine,
				  ooscript::Context /*context*/,
				  ooscript::ErrorReport * /*errorReport*/,
				  unsigned /*stackSkip*/,
				  bool showLocation,
				  const std::string &message) override
	{
		_errors++;
		_engine = engine;
		_showLocation = showLocation;
		_message = message;
	}


	void jsEngine(OOJavaScriptEngine *engine,
				  ooscript::Context /*context*/,
				  const std::string &message,
				  const std::optional<std::string> &messageClass) override
	{
		_logs++;
		_engine = engine;
		_message = message;
		_messageClass = messageClass;
	}
};

}	// namespace
#endif


namespace {

namespace stdfs = std::filesystem;

stdfs::path sRoot;

std::vector<std::string> sLog;


void Capture(std::string_view line)
{
	sLog.emplace_back(line);
}


void WriteText(const stdfs::path &path, const std::string &text)
{
	stdfs::create_directories(path.parent_path());
	OO_CHECK(oo::fs::writeFile(path, oo::Data(text.data(), text.size()), oo::fs::WriteMode::direct).has_value());
}


// The scratch home and game folder, made once, before the cache manager and the engine exist.
void SetUp()
{
	if (!sRoot.empty())  return;
	sRoot = stdfs::temp_directory_path() / ("oo-test-jsengine-" + std::to_string(static_cast<unsigned long>(::_getpid())));
	stdfs::remove_all(sRoot);
	stdfs::create_directories(sRoot);
	OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
	stdfs::current_path(sRoot);
	WriteText(sRoot / "Resources" / "Info-gnustep.plist", "{ CFBundleVersion = \"9.9.9-test\"; }");
	(void)OOJavaScriptEngine::sharedEngine();
}


void StartLog()
{
	oo::log::logger().setInitialized(true);
	oo::log::logger().setSink(&Capture);
	oo::log::logger().setDisplay("script.javaScript", true);
	oo::log::logger().setDisplay("script.javaScript.debugger", true);
	oo::log::logger().setDisplay("script.javaScript.stackTrace", true);
	oo::log::logger().setDisplay("script.javaScript.exception", true);
	oo::log::logger().setDisplay("script.javaScript.error", true);
	oo::log::logger().setDisplay("script.javaScript.warning", true);
	sLog.clear();
}


int LogLinesContaining(std::string_view text)
{
	int count = 0;
	for (const std::string &line : sLog)
	{
		if (line.find(text) != std::string::npos)  count++;
	}
	return count;
}


std::string LogText()
{
	std::string text;
	for (const std::string &line : sLog)  text += line + "\n";
	return text;
}


// Evaluates source in the global object; needs a request.
ooscript::Value Eval(ooscript::Context context, const std::string &source)
{
	ooscript::Value result = ooscript::undefinedValue();
	OO_CHECK(ooscript::evaluateScript(context, OOJavaScriptEngine::sharedEngine()->globalObject(), source.c_str(), static_cast<unsigned>(source.size()), "test.js", 1, &result));
	return result;
}


std::string Describe(ooscript::Context context, const std::string &source, BOOL abbreviate)
{
	return cxx_OOJSDescribeValue(context, Eval(context, source), abbreviate);
}


// A JS class whose objects hold a retained native object, finalised by the engine's wrapper hook.
ooscript::ClassDef sTestWrapperClass =
{
	"TestWrapper",
	ooscript::ClassFlag::HasPrivate,
	nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr,
	OOJSObjectWrapperFinalize,
	nullptr, nullptr, nullptr
};

}	// namespace


// MARK: The engine ---------------------------------------------------------------------------------

OO_TEST(sharedEngine)
{
	SetUp();
	{
		OOJavaScriptEngine *engine = OOJavaScriptEngine::sharedEngine();
		OO_CHECK(engine != nullptr);
		OO_CHECK(OOJavaScriptEngine::sharedEngine() == engine);
		OO_CHECK(gOOJSMainThreadContext != NULL);
		OO_CHECK(engine->globalObject() != NULL);

		ooscript::Context context = OOJSAcquireContext();
		OO_CHECK(ooscript::getGlobalObject(context) == engine->globalObject());
		// The Oolite classes and the prefix script are set up on the global object.
		OO_CHECK(ooscript::isObject(Eval(context, "Vector3D")));
		OO_CHECK(ooscript::isObject(Eval(context, "missionVariables")));
		OOJSRelinquishContext(context);

		engine->runMissionCallback();	// no callback set: does nothing
	}
}


OO_TEST(standardClasses)
{
	SetUp();
	{
		OOJavaScriptEngine *engine = OOJavaScriptEngine::sharedEngine();
		OO_CHECK(engine->objectClass() != NULL);
		OO_CHECK(engine->stringClass() != NULL);
		OO_CHECK(engine->arrayClass() != NULL);
		OO_CHECK(engine->numberClass() != NULL);
		OO_CHECK(engine->booleanClass() != NULL);
		OO_CHECK(engine->objectClass() != engine->arrayClass());
		OO_CHECK(engine->stringClass() != engine->numberClass());
		OO_CHECK(engine->numberClass() != engine->booleanClass());

		ooscript::Context context = OOJSAcquireContext();
		OO_CHECK(OOJSGetClass(context, ooscript::toObject(Eval(context, "[1, 2]"))) == engine->arrayClass());
		OO_CHECK(OOJSGetClass(context, ooscript::toObject(Eval(context, "({ a: 1 })"))) == engine->objectClass());
		OO_CHECK(OOJSGetClass(context, ooscript::toObject(Eval(context, "new String('s')"))) == engine->stringClass());
		OO_CHECK(OOJSGetClass(context, ooscript::toObject(Eval(context, "new Number(1)"))) == engine->numberClass());
		OO_CHECK(OOJSGetClass(context, ooscript::toObject(Eval(context, "new Boolean(false)"))) == engine->booleanClass());
		OOJSRelinquishContext(context);
	}
}


OO_TEST(flags)
{
	SetUp();
	{
		OOJavaScriptEngine *engine = OOJavaScriptEngine::sharedEngine();
		const BOOL show = engine->showErrorLocations();
		engine->setShowErrorLocations(YES);
		OO_CHECK(engine->showErrorLocations());
		engine->setShowErrorLocations(NO);
		OO_CHECK(!engine->showErrorLocations());
		engine->setShowErrorLocations(show);

#ifndef NDEBUG
		// Off unless the preferences say otherwise (the scratch home has none).
		OO_CHECK(!engine->dumpStackForErrors());
		OO_CHECK(!engine->dumpStackForWarnings());
		engine->setDumpStackForErrors(YES);
		OO_CHECK(engine->dumpStackForErrors());
		OO_CHECK(!engine->dumpStackForWarnings());
		engine->setDumpStackForWarnings(YES);
		OO_CHECK(engine->dumpStackForWarnings());
		engine->setDumpStackForErrors(NO);
		engine->setDumpStackForWarnings(NO);
		OO_CHECK(!engine->dumpStackForErrors());
		OO_CHECK(!engine->dumpStackForWarnings());
#endif
	}
}


OO_TEST(callJSFunction)
{
	SetUp();
	{
		OOJavaScriptEngine *engine = OOJavaScriptEngine::sharedEngine();
		ooscript::Context context = OOJSAcquireContext();
		ooscript::Value function = Eval(context, "(function (a, b) { return this.base + a * b; })");
		ooscript::Value thisValue = Eval(context, "({ base: 100 })");
		OOJSRelinquishContext(context);

		ooscript::Value argv[2] = { ooscript::int32Value(6), ooscript::int32Value(7) };
		ooscript::Value result = ooscript::undefinedValue();
		OO_CHECK(engine->callJSFunction(function, ooscript::toObject(thisValue), 2, argv, &result));
		OO_CHECK(ooscript::isInt32(result) && ooscript::toInt32(result) == 142);

		// A function that throws: NO, and the exception is reported (not left pending).
		StartLog();
		context = OOJSAcquireContext();
		ooscript::Value thrower = Eval(context, "(function () { throw new Error('call boom'); })");
		OOJSRelinquishContext(context);
		OO_CHECK(!engine->callJSFunction(thrower, ooscript::toObject(thisValue), 0, NULL, &result));
		OO_CHECK(LogLinesContaining("call boom") >= 1);
		context = OOJSAcquireContext();
		OO_CHECK(!ooscript::isExceptionPending(context));
		OOJSRelinquishContext(context);
	}
}


OO_TEST(gcRoots)
{
	SetUp();
	{
		OOJavaScriptEngine *engine = OOJavaScriptEngine::sharedEngine();
		ooscript::Context context = OOJSAcquireContext();
		static ooscript::Value value;
		static ooscript::Object object;
		value = Eval(context, "({ kept: 'value' })");
		object = ooscript::toObject(Eval(context, "({ kept: 'object' })"));
		OO_CHECK(ooscript::addNamedValueRoot(context, &value, "test value root"));
		OO_CHECK(ooscript::addNamedObjectRoot(context, &object, "test object root"));
		OOJSRelinquishContext(context);

		engine->garbageCollectionOpportunity(YES);
		engine->garbageCollectionOpportunity(NO);
		context = OOJSAcquireContext();
		OO_CHECK(cxx_OOStringFromJSValue(context, Eval(context, "1, 'ok'")).value_or("") == "ok");
		OOJSRelinquishContext(context);

		engine->removeGCValueRoot(&value);
		engine->removeGCObjectRoot(&object);
		engine->garbageCollectionOpportunity(YES);
	}
}


// MARK: Errors and warnings ------------------------------------------------------------------------

OO_TEST(errorReporting)
{
	SetUp();
	{
		OOJavaScriptEngine *engine = OOJavaScriptEngine::sharedEngine();
		const BOOL show = engine->showErrorLocations();
#if OOJSENGINE_MONITOR_SUPPORT
		TestMonitor monitorObject;	// set while the test runs, then cleared (the engine borrows it)
		TestMonitor *monitor = &monitorObject;
		engine->setMonitor(monitor);
#endif

		// An error reported by a native, with the caller's prefix.
		StartLog();
		engine->setShowErrorLocations(NO);
		ooscript::Context context = OOJSAcquireContext();
		cxx_OOJSReportErrorForCaller(context, std::string("TestClass"), std::string("doThing"), "bad %s %d", "input", 7);
		ooscript::reportPendingException(context);
		OOJSRelinquishContext(context);
		OO_CHECK(LogLinesContaining("***** JavaScript ") == 1);
		OO_CHECK(LogLinesContaining("(<unidentified script>): ") == 1);
		OO_CHECK(LogLinesContaining("TestClass.doThing: bad input 7") == 1);
#if OOJSENGINE_MONITOR_SUPPORT
		OO_CHECK(monitor->_errors == 1);
		OO_CHECK(monitor->_engine == engine);
		OO_CHECK(!monitor->_showLocation);
		OO_CHECK(monitor->_message.find("TestClass.doThing: bad input 7") != std::string::npos);
#endif

		// A bad-arguments report describes the arguments.
		StartLog();
		context = OOJSAcquireContext();
		ooscript::Value args[2] = { ooscript::int32Value(3), Eval(context, "'three'") };
		cxx_OOJSReportBadArguments(context, std::string("Ship"), std::string("fly"), 2, args, std::nullopt, std::string("number"));
		ooscript::reportPendingException(context);
		OOJSRelinquishContext(context);
		OO_CHECK(LogLinesContaining("Ship.fly: Invalid arguments (3, \"three\") -- expected number.") == 1);

		// An uncaught exception with locations shown: two lines.
		StartLog();
		engine->setShowErrorLocations(YES);
		context = OOJSAcquireContext();
		ooscript::Value result = ooscript::undefinedValue();
		const char *source = "\n\nthrow new Error('located boom');";
		OO_CHECK(!ooscript::evaluateScript(context, engine->globalObject(), source, static_cast<unsigned>(strlen(source)), "located.js", 1, &result));
		ooscript::reportPendingException(context);
		OOJSRelinquishContext(context);
		OO_CHECK(LogLinesContaining("located boom") >= 1);
		OO_CHECK(LogLinesContaining("located.js, line 3") == 1);
#if OOJSENGINE_MONITOR_SUPPORT
		OO_CHECK(monitor->_showLocation);
#endif

		// No second line when the stack skip is set.
		StartLog();
		OOJSSetWarningOrErrorStackSkip(1);
		context = OOJSAcquireContext();
		OO_CHECK(!ooscript::evaluateScript(context, engine->globalObject(), source, static_cast<unsigned>(strlen(source)), "located.js", 1, &result));
		ooscript::reportPendingException(context);
		OOJSRelinquishContext(context);
		OOJSSetWarningOrErrorStackSkip(0);
		OO_CHECK(LogLinesContaining("located boom") >= 1);
		OO_CHECK(LogLinesContaining("located.js, line 3") == 0);

		// A warning: dashes, and nothing pending.
		StartLog();
		engine->setShowErrorLocations(NO);
		context = OOJSAcquireContext();
		cxx_OOJSReportWarningForCaller(context, std::nullopt, std::string("warnFunc"), "careful %s", "now");
		OO_CHECK(!ooscript::isExceptionPending(context));
		OOJSRelinquishContext(context);
		OO_CHECK(LogLinesContaining("----- JavaScript warning") == 1);
		OO_CHECK(LogLinesContaining("warnFunc: careful now") == 1);

#if OOJSENGINE_MONITOR_SUPPORT
		// Script log messages go to the monitor too.
		const int logs = monitor->_logs;
		context = OOJSAcquireContext();
		Eval(context, "log('monitored message')");
		OOJSRelinquishContext(context);
		OO_CHECK(monitor->_logs == logs + 1);
		OO_CHECK(monitor->_message == "monitored message");
		OO_CHECK(!monitor->_messageClass.has_value());
		engine->setMonitor(nil);
#endif
		engine->setShowErrorLocations(show);
	}
}


#ifndef NDEBUG
// A native that dumps the JS stack it is called from.
bool DumpStackNative(ooscript::Context context, ooscript::CallArgs &args)
{
	OOJSDumpStack(context);
	args.setRval(ooscript::undefinedValue());
	return true;
}


OO_TEST(stackDump)
{
	SetUp();
	{
		OOJavaScriptEngine *engine = OOJavaScriptEngine::sharedEngine();
		ooscript::Context context = OOJSAcquireContext();
		OO_CHECK(ooscript::defineFunction(context, engine->globalObject(), "testDumpStack", DumpStackNative, 0, ooscript::PropertyFlag::None) != NULL);

		// The QuickJS backend's frames have a file and a line, but no function and no variables.
		StartLog();
		ooscript::Value result = ooscript::undefinedValue();
		const char *source = "function dumpTarget(a) {\n\tvar b = a + 1;\n\ttestDumpStack();\n\treturn b;\n}\ndumpTarget(41);\n";
		OO_CHECK(ooscript::evaluateScript(context, engine->globalObject(), source, static_cast<unsigned>(strlen(source)), "dumpstack.js", 1, &result));
		OO_CHECK(LogLinesContaining("(dumpstack.js:3) <not a function frame>") == 1);
		OO_CHECK(LogLinesContaining("(dumpstack.js:6) <not a function frame>") == 1);
		OO_CHECK(LogLinesContaining(" 0 (dumpstack.js:3)") == 1);
		if (LogLinesContaining("dumpstack.js") == 0)  fprintf(stderr, "%s", LogText().c_str());
		OOJSRelinquishContext(context);

		// The stack skip drops the innermost frames.
		StartLog();
		OOJSSetWarningOrErrorStackSkip(1);
		context = OOJSAcquireContext();
		OO_CHECK(ooscript::evaluateScript(context, engine->globalObject(), source, static_cast<unsigned>(strlen(source)), "dumpstack.js", 1, &result));
		OOJSRelinquishContext(context);
		OOJSSetWarningOrErrorStackSkip(0);
		OO_CHECK(LogLinesContaining("(dumpstack.js:3)") == 0);
		OO_CHECK(LogLinesContaining("(dumpstack.js:6) <not a function frame>") == 1);

		// This backend has no `debugger` hook: the statement does nothing.
		engine->enableDebuggerStatement();
		StartLog();
		context = OOJSAcquireContext();
		Eval(context, "(function () { debugger; return 1; })();");
		OOJSRelinquishContext(context);
		OO_CHECK(LogLinesContaining("debugger invoked") == 0);

		// With no JS on the stack, a dump writes nothing.
		StartLog();
		context = OOJSAcquireContext();
		OOJSDumpStack(context);
		OOJSRelinquishContext(context);
		OO_CHECK(LogLinesContaining("script.javaScript.stackTrace") + LogLinesContaining("<Oolite native>") == 0);
	}
}
#endif


// MARK: Values -------------------------------------------------------------------------------------

OO_TEST(describeValue)
{
	SetUp();
	{
		ooscript::Context context = OOJSAcquireContext();
		OO_CHECK_EQ(Describe(context, "'a\"b\\n'", NO), "\"a\\\"b\\n\"");
		OO_CHECK_EQ(Describe(context, "new String('boxed')", NO), "\"boxed\"");
		OO_CHECK_EQ(Describe(context, "new Array(251).join('x')", NO), "\"" + std::string(200, 'x') + "...\"");
		OO_CHECK_EQ(Describe(context, "[1, 2, 3]", NO), "[1, 2, 3]");
		OO_CHECK_EQ(Describe(context, "[1, 'two', 3, 4, 5, 6]", NO), "[1, \"two\", 3, 4, ... <6 items total>]");
		OO_CHECK_EQ(Describe(context, "[[1, 2], {}]", NO), "[[<2 items>], {...}]");
		OO_CHECK_EQ(Describe(context, "({ a: 1 })", YES), "{...}");
		OO_CHECK_EQ(Describe(context, "({ a: 1 })", NO), "[object Object]");
		OO_CHECK_EQ(Describe(context, "(function namedFn() {})", NO), "function namedFn");
		OO_CHECK_EQ(Describe(context, "3.5", NO), "3.5");
		OO_CHECK_EQ(Describe(context, "null", NO), "null");
		OO_CHECK_EQ(Describe(context, "undefined", NO), "undefined");
		OO_CHECK_EQ(Describe(context, "true", NO), "true");

		ooscript::Value params[2] = { ooscript::int32Value(1), Eval(context, "'p'") };
		OO_CHECK_EQ(cxx_OOJSStringWithJavaScriptParameters(params, 2, context).value_or("<none>"), "(1, \"p\")");
		OOJSRelinquishContext(context);
	}
}


OO_TEST(idAndStringCaches)
{
	SetUp();
	{
		ooscript::PropertyId identifier = OOJSID("testIdentifier");
		OO_CHECK_EQ(cxx_OOStringFromJSID(identifier).value_or("<none>"), "testIdentifier");
		OO_CHECK(OOJSID("testIdentifier") == identifier);

		ooscript::Context context = OOJSAcquireContext();
		ooscript::Value literal = OOJSSTR("test literal");
		OO_CHECK(ooscript::isString(literal));
		OO_CHECK_EQ(cxx_OOStringFromJSValue(context, literal).value_or("<none>"), "test literal");
		OOJSRelinquishContext(context);
	}
}


OO_TEST(nativeObjectValues)
{
	SetUp();
	{
		ooscript::Context context = OOJSAcquireContext();

		// nil and OONull are JS null; OONull is one object that copies as itself. (nil is the null
		// PList: re-pinned through OOJSValueFromPList when bead oo-4aq6a.6.2 deleted
		// OOJSValueFromNativeObject; ADR-0062 item 3.)
		OO_CHECK(ooscript::isNull(OOJSValueFromPList(context, oo::PList())));
		OONull *null = OONull::null();
		OO_CHECK(null != nullptr && OONull::null() == null);
		OO_CHECK(OOIsNullObjectNode(OONullObjectNode()) && OONullObjectNode() == OONullObjectNode());	// the one null, shared (the facade's -copy answered itself)
		OO_CHECK_EQ(null->description(), "<null>");
		OO_CHECK(ooscript::isNull(OOJSValueFromPList(context, OONullObjectNode())));
		OO_CHECK(ooscript::isNull(null->jsValueInContext(context)));

		// (A plain OOObject's JS value and description, through the root's JS glue, retired with that
		// glue, bead oo-4aq6a.6.2: ADR-0062 item 2.)

		// A native vector is a Vector3D.
		oo::Ref<OONativeVector> vector = oo::makeRef<OONativeVector>(make_vector(1.0f, 2.0f, 3.0f));
		ooscript::Value vectorValue = OOJSValueFromPList(context, oo::PList(oo::PList::Object(vector)));
		OO_CHECK(ooscript::isObject(vectorValue));
		OO_CHECK(std::strcmp(OOJSGetClass(context, ooscript::toObject(vectorValue))->name, "Vector3D") == 0);
		OO_CHECK_EQ(cxx_OOStringFromJSValue(context, vectorValue).value_or("<none>"), "(1, 2, 3)");

		OOJSRelinquishContext(context);
	}
}


OO_TEST(jsValueHolder)
{
	SetUp();
	{
		ooscript::Context context = OOJSAcquireContext();
		ooscript::Value object = Eval(context, "({ held: 'yes' })");
		oo::Ref<OOJSValue> holder = OOJSValue::valueWithJSValue(object, context);
		OO_CHECK(holder != nullptr);
		OO_CHECK(holder->jsValueInContext(context) == object);
		OO_CHECK(OOJSValueFromPList(context, OOJSValueObjectNode(holder.get())) == object);

		oo::Ref<OOJSValue> byObject = OOJSValue::valueWithJSObject(ooscript::toObject(object), context);
		OO_CHECK(ooscript::toObject(byObject->jsValueInContext(context)) == ooscript::toObject(object));
		OOJSRelinquishContext(context);

		// A nil context is acquired for the call.
		oo::Ref<OOJSValue> noContext = OOJSValue::valueWithJSValue(ooscript::int32Value(9), NULL);
		OO_CHECK(ooscript::toInt32(noContext->jsValueInContext(NULL)) == 9);

		// Undefined holds undefined.
		oo::Ref<OOJSValue> undefinedHolder = OOJSValue::valueWithJSValue(ooscript::undefinedValue(), NULL);
		OO_CHECK(ooscript::isUndefined(undefinedHolder->jsValueInContext(NULL)));

		OOJavaScriptEngine::sharedEngine()->garbageCollectionOpportunity(YES);	// the held object survives
		context = OOJSAcquireContext();
		OO_CHECK_EQ(cxx_OOStringFromJSValue(context, ooscript::objectValue(ooscript::toObject(holder->jsValueInContext(context)))).value_or("<none>"), "[object Object]");
		OOJSRelinquishContext(context);
	}
}


// (objectWrapper retired with the slot's Objective-C objects, bead oo-4aq6a.6: its Objective-C
// native object's description, the Objective-C class-checked getters and the finalizer's
// -oo_clearJSSelf:/release are deleted. cxxObjectWrapper pins what survives.)


// The generic wrapper's hooks with the C++ object the slot holds: the finalizer tells it its wrapper
// is gone, releases it and empties the slot; toString names the JS class (only an Objective-C
// object described itself through the class's converter).
OO_TEST(cxxObjectWrapper)
{
	SetUp();
	ooscript::Object wrapper = NULL;
	oo::Ref<TestCxxNative> native = oo::makeRef<TestCxxNative>();
	const int deallocs = sCxxNativeDeallocs;
	{
		ooscript::Context context = OOJSAcquireContext();
		wrapper = ooscript::newObject(context, &sTestWrapperClass, NULL, NULL);
		OO_CHECK(wrapper != NULL);
		OO_CHECK(OOJSSetCxxPrivate(context, wrapper, native.get()));
		OO_CHECK(ooscript::defineFunction(context, wrapper, "toString", OOJSObjectWrapperToString, 0, ooscript::PropertyFlag::None) != NULL);

		// Unconverted, toString names the JS class.
		ooscript::Value result = ooscript::undefinedValue();
		OO_CHECK(ooscript::callFunctionName(context, wrapper, "toString", 0, NULL, &result));
		OO_CHECK_EQ(cxx_OOStringFromJSValue(context, result).value_or("<none>"), "[object TestWrapper]");

		// With the basic private-object converter the wrapper is an Object node of the C++ object,
		// and toString still names the JS class.
		OOJSRegisterObjectConverter(&sTestWrapperClass, OOJSBasicPrivateObjectConverter);
		const oo::PList node = cxx_OOJSPListFromJSObject(context, wrapper);
		OO_CHECK(node.getIf<oo::PList::Object>() != nullptr && node.getIf<oo::PList::Object>()->get() == native.get());
		OO_CHECK(ooscript::callFunctionName(context, wrapper, "toString", 0, NULL, &result));
		OO_CHECK_EQ(cxx_OOStringFromJSValue(context, result).value_or("<none>"), "[object TestWrapper]");

		// Finalising clears the native object's JS self, releases it and empties the slot.
		OOJSObjectWrapperFinalize(context, wrapper);
		OO_CHECK(native->_clears == 1);
		OO_CHECK(ooscript::getPrivate(context, wrapper) == NULL);
		OO_CHECK(cxx_OOJSPListFromJSObject(context, wrapper).isNull());
		OOJSObjectWrapperFinalize(context, wrapper);	// nothing left: does nothing
		OO_CHECK(native->_clears == 1);

		// With no native object, toString names the JS class.
		OO_CHECK(ooscript::callFunctionName(context, wrapper, "toString", 0, NULL, &result));
		OO_CHECK_EQ(cxx_OOStringFromJSValue(context, result).value_or("<none>"), "[object TestWrapper]");

		OOJSRegisterObjectConverter(&sTestWrapperClass, NULL);
		OOJSRelinquishContext(context);
	}
	OO_CHECK(sCxxNativeDeallocs == deallocs);	// the test's own reference
	native = nullptr;
	OO_CHECK(sCxxNativeDeallocs == deallocs + 1);
}


OO_TEST(entityPredicates)
{
	SetUp();
	{
		OO_CHECK(!JSEntityIsJavaScriptVisiblePredicate(nullptr, NULL));
		OO_CHECK(!JSEntityIsJavaScriptSearchablePredicate(nullptr, NULL));
		OO_CHECK(!JSEntityIsDemoShipPredicate(nullptr, NULL));

		TestScriptEntity *entity = static_cast<TestScriptEntity *>(oo::MadeEntity(oo::makeRef<TestScriptEntity>()));
		entity->setStatus(STATUS_IN_FLIGHT);
		OO_CHECK(!JSEntityIsJavaScriptVisiblePredicate(entity, NULL));
		OO_CHECK(!JSEntityIsJavaScriptSearchablePredicate(entity, NULL));

		entity->_scriptVisible = true;
		OO_CHECK(JSEntityIsJavaScriptVisiblePredicate(entity, NULL));
		OO_CHECK(JSEntityIsJavaScriptSearchablePredicate(entity, NULL));	// neither ship nor planet
		OO_CHECK(!JSEntityIsDemoShipPredicate(entity, NULL));

		entity->isShip = YES;
		OO_CHECK(JSEntityIsJavaScriptSearchablePredicate(entity, NULL));
		OO_CHECK(!JSEntityIsDemoShipPredicate(entity, NULL));
		entity->isSubEntity = YES;
		OO_CHECK(!JSEntityIsJavaScriptSearchablePredicate(entity, NULL));
		entity->isSubEntity = NO;
		entity->setStatus(STATUS_COCKPIT_DISPLAY);
		OO_CHECK(!JSEntityIsJavaScriptSearchablePredicate(entity, NULL));
		OO_CHECK(JSEntityIsDemoShipPredicate(entity, NULL));
		entity->isSubEntity = YES;
		OO_CHECK(!JSEntityIsDemoShipPredicate(entity, NULL));

		// A JS function as a predicate: called with the entity's JS value.
		ooscript::Context context = OOJSAcquireContext();
		JSFunctionPredicateParameter param = { context, Eval(context, "(function (e) { return e === 42; })"), NULL, NO };
		OO_CHECK(JSFunctionPredicate(entity, &param));
		OO_CHECK(!param.errorFlag);
		param.function = Eval(context, "(function (e) { return e !== 42; })");
		OO_CHECK(!JSFunctionPredicate(entity, &param));
		OO_CHECK(!param.errorFlag);

		StartLog();
		param.function = Eval(context, "(function (e) { throw new Error('predicate boom'); })");
		OO_CHECK(!JSFunctionPredicate(entity, &param));
		OO_CHECK(param.errorFlag);
		OO_CHECK(LogLinesContaining("predicate boom") >= 1);
		param.function = Eval(context, "(function (e) { return true; })");
		OO_CHECK(!JSFunctionPredicate(entity, &param));	// the error flag stops further filtering
		OOJSRelinquishContext(context);
	}
}


OO_TEST(propertyListsFromJS)
{
	SetUp();
	{
		ooscript::Context context = OOJSAcquireContext();
		oo::PList array = cxx_OOJSPListFromJSValue(context, Eval(context, "[1, null, 'a', [true]]"));
		OO_CHECK(array.isArray());
		const oo::PList::Array *elements = array.getIf<oo::PList::Array>();
		OO_CHECK(elements != nullptr && elements->size() == 4);
		if (elements != nullptr && elements->size() == 4)
		{
			OO_CHECK((*elements)[0] == oo::PList::signedInteger(1));
			OO_CHECK(OOIsNullObjectNode((*elements)[1]));	// a null element is OONull
			OO_CHECK((*elements)[2] == oo::PList(std::string("a")));
			OO_CHECK((*elements)[3].isArray());
		}
		OO_CHECK(cxx_OOJSPListFromJSValue(context, Eval(context, "[]")).isArray());

		oo::PList dict = cxx_OOJSPListFromJSValue(context, Eval(context, "({ s: new String('x'), n: new Number(2.5), b: new Boolean(false) })"));
		OO_CHECK(dict.isDict());
		OO_CHECK(dict.find("s") != nullptr && *dict.find("s") == oo::PList(std::string("x")));
		OO_CHECK(dict.find("n") != nullptr && *dict.find("n") == oo::PList(2.5));
		OO_CHECK(dict.find("b") != nullptr && *dict.find("b") == oo::PList(static_cast<bool>(false)));	// OOCocoa.h defines false as 0 (amendment oo-kq7 item 8)

		// Round trip through OOJSValueFromPList.
		oo::PList back = cxx_OOJSPListFromJSValue(context, OOJSValueFromPList(context, oo::PList(oo::PList::Array{oo::PList(std::string("q")), oo::PList::signedInteger(5)})));
		OO_CHECK(back == oo::PList(oo::PList::Array{oo::PList(std::string("q")), oo::PList::signedInteger(5)}));
		OOJSRelinquishContext(context);
	}
}


// MARK: Reset (last: it rebuilds the context) -----------------------------------------------------

OO_TEST(reset)
{
	SetUp();
	{
		OOJavaScriptEngine *engine = OOJavaScriptEngine::sharedEngine();
		ooscript::Context context = OOJSAcquireContext();
		Eval(context, "this.survivesReset = 1;");
		OOJSRelinquishContext(context);

		static int willResets = 0, didResets = 0, otherSender = 0;
		static int marker;
		static bool contextDuringWill = false;
		oo::NotificationCenter::defaultCenter().addObserver(&marker, kOOJavaScriptEngineWillResetNotificationName, engine,
			[](const oo::Notification &) { willResets++; contextDuringWill = (gOOJSMainThreadContext != NULL); });
		oo::NotificationCenter::defaultCenter().addObserver(&marker, kOOJavaScriptEngineDidResetNotificationName, engine,
			[](const oo::Notification &) { didResets++; });
		oo::NotificationCenter::defaultCenter().addObserver(&marker, kOOJavaScriptEngineDidResetNotificationName, &otherSender,
			[](const oo::Notification &) { otherSender++; });

		OO_CHECK(engine->reset());
		OO_CHECK(willResets == 1 && didResets == 1 && otherSender == 0);
		OO_CHECK(contextDuringWill);
		OO_CHECK(OOJavaScriptEngine::sharedEngine() == engine);
		OO_CHECK(gOOJSMainThreadContext != NULL);
		OO_CHECK(engine->globalObject() != NULL);
		OO_CHECK(engine->arrayClass() != NULL);

		context = OOJSAcquireContext();
		OO_CHECK_EQ(cxx_OOStringFromJSValue(context, Eval(context, "typeof survivesReset")).value_or("<none>"), "undefined");
		OO_CHECK(ooscript::isObject(Eval(context, "Vector3D")));
		OO_CHECK(OOJSGetClass(context, ooscript::toObject(Eval(context, "[1]"))) == engine->arrayClass());
		// The standard converters are registered again.
		OO_CHECK(cxx_OOJSPListFromJSValue(context, Eval(context, "[1]")).isArray());
		OOJSRelinquishContext(context);

		oo::NotificationCenter::defaultCenter().removeObserver(&marker);
	}
}


// (aValueLeftInTheThreadPoolAtExit, which left a rooted value in libobjc2's thread pool through an
// OOObject-rooted keeper, retired with OOObject, bead oo-4aq6a.8: no game code puts an object in the
// runtime's pool since the keepers became oo::AutoreleaseScope, amendment oo-31u.6.)


OO_TEST(cleanUp)
{
	oo::log::logger().setSink(nullptr);
	stdfs::current_path(stdfs::temp_directory_path());
	std::error_code ignored;
	stdfs::remove_all(sRoot, ignored);
	OO_CHECK(true);
}


OO_TEST_MAIN()
