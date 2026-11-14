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
	Values follow the engine's ownership conventions (OOJSEngineCore.h): every owned value the test
	makes is freed.
	Run: bash tools/check-core-tests.sh test_OOJavaScriptEngine
*/

#import "OOJavaScriptEngine.h"
#import "OOJSScript.h"
#import "OOJSPropID.h"
#import "OODescription.h"
#import "Entity.h"
#import "EntityOOJavaScriptExtensions.h"
#import "OOVector.h"
#import "OOObjCPList.h"
#include "oofnd/FileSystem.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/Notification.hpp"
#include "oo_test.hpp"

#include <quickjs.h>

#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <process.h>
#include <string>
#include <vector>


extern JSContext *gOOJSMainThreadContext;	// OOJavaScriptEngine.mm


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


// A plain OOObject, as a script's native object: counts its JS wrapper's finalisation and its own.
@interface TestNative: OOObject
{
@public
	int		_clears;
}
@end

static int sNativeDeallocs = 0;

@implementation TestNative

- (std::optional<std::string>) cxx_descriptionComponents
{
	return std::string("x=1");
}


- (void) oo_clearJSSelf:(JSValueConst)selfVal
{
	_clears++;
}


- (void) dealloc
{
	sNativeDeallocs++;
	[super dealloc];
}

@end


// An entity whose script-visible answers the test chooses (the predicates ask only these).
@interface TestScriptEntity: Entity
{
@public
	BOOL			_scriptVisible;
	BOOL			_ship;
	BOOL			_subEntity;
	OOEntityStatus	_testStatus;
}
@end

@implementation TestScriptEntity

- (BOOL) isVisibleToScripts							{ return _scriptVisible; }
- (BOOL) isShip										{ return _ship; }
- (BOOL) isSubEntity								{ return _subEntity; }
- (BOOL) isPlanet									{ return NO; }
- (OOEntityStatus) status							{ return _testStatus; }
- (JSValue) oo_jsValueInContext:(JSContext *)context	{ return JS_NewInt32(context, 42); }

@end


#if OOJSENGINE_MONITOR_SUPPORT
// A debug monitor that records what the engine sends it.
@interface TestMonitor: OOObject <OOJavaScriptEngineMonitor>
{
@public
	int							_errors;
	int							_logs;
	id							_engine;
	BOOL						_showLocation;
	std::string					_message;
	std::optional<std::string>	_messageClass;
}
@end

@implementation TestMonitor

- (void)jsEngine:(OOJavaScriptEngine *)engine
		   context:(JSContext *)context
 problemOfSeverity:(const std::string &)severity
			inFile:(const std::optional<std::string> &)file
			  line:(unsigned)line
		 stackSkip:(unsigned)stackSkip
   showingLocation:(BOOL)showLocation
	   withMessage:(const std::string &)message
{
	_errors++;
	_engine = engine;
	_showLocation = showLocation;
	_message = message;
}


- (void)jsEngine:(OOJavaScriptEngine *)engine
		 context:(JSContext *)context
	  logMessage:(const std::string &)message
		 ofClass:(const std::optional<std::string> &)messageClass
{
	_logs++;
	_engine = engine;
	_message = message;
	_messageClass = messageClass;
}

@end
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
	(void)[OOJavaScriptEngine sharedEngine];
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


// An owned value, freed when it goes out of scope; it reads as the borrowed value.
class Owned
{
public:
	explicit Owned(JSValue value): _value(value)  {}
	~Owned()  { JS_FreeValue(OOJSAcquireContext(), _value); }
	Owned(const Owned &) = delete;
	Owned &operator=(const Owned &) = delete;
	operator JSValueConst() const  { return _value; }

private:
	JSValue _value;
};


// Evaluates source as a global script in file (line 1 first); the result, or JS_EXCEPTION with the
// exception pending. Owned by the caller.
JSValue EvalIn(JSContext *context, const std::string &source, const char *file)
{
	return JS_Eval(context, source.c_str(), source.size(), file, JS_EVAL_TYPE_GLOBAL);
}


// Evaluates source in the global object, which must not throw.
Owned Eval(JSContext *context, const std::string &source)
{
	JSValue result = EvalIn(context, source, "test.js");
	OO_CHECK(!JS_IsException(result));
	return Owned(result);
}


std::string Describe(JSContext *context, const std::string &source, BOOL abbreviate)
{
	return cxx_OOJSDescribeValue(context, Eval(context, source), abbreviate);
}


// Whether value is the object other.
bool IsSameObject(JSValueConst value, JSValueConst other)
{
	return JS_IsObject(value) && JS_IsObject(other) && JS_VALUE_GET_PTR(value) == JS_VALUE_GET_PTR(other);
}


// object.toString(), as a string.
std::string CallToString(JSContext *context, JSValueConst object)
{
	Owned function(JS_GetPropertyStr(context, object, "toString"));
	Owned result(JS_Call(context, function, object, 0, nullptr));
	OO_CHECK(!JS_IsException(result));
	return cxx_OOStringFromJSValue(context, result).value_or("<none>");
}


// A JS class whose objects hold a retained native object, finalised by the engine's wrapper hook.
JSClassID sTestWrapperClassID = 0;
const JSClassDef sTestWrapperClass =
{
	.class_name = "TestWrapper",
	.finalizer = OOJSObjectWrapperFinalize,
};

}	// namespace


// MARK: The engine ---------------------------------------------------------------------------------

OO_TEST(sharedEngine)
{
	SetUp();
	@autoreleasepool
	{
		OOJavaScriptEngine *engine = [OOJavaScriptEngine sharedEngine];
		OO_CHECK(engine != nil);
		OO_CHECK([OOJavaScriptEngine sharedEngine] == engine);
		OO_CHECK(gOOJSMainThreadContext != NULL);
		OO_CHECK(JS_IsObject([engine globalObject]));

		JSContext *context = OOJSAcquireContext();
		OO_CHECK(IsSameObject(Owned(JS_GetGlobalObject(context)), [engine globalObject]));
		// The Oolite classes and the prefix script are set up on the global object.
		OO_CHECK(JS_IsObject(Eval(context, "Vector3D")));
		OO_CHECK(JS_IsObject(Eval(context, "missionVariables")));
		OOJSRelinquishContext(context);

		[engine runMissionCallback];	// no callback set: does nothing
	}
}


OO_TEST(standardClasses)
{
	SetUp();
	@autoreleasepool
	{
		// The engine looks the standard classes' IDs up when it starts.
		OO_CHECK(gOOJSObjectClassID != 0);
		OO_CHECK(gOOJSStringClassID != 0);
		OO_CHECK(gOOJSArrayClassID != 0);
		OO_CHECK(gOOJSNumberClassID != 0);
		OO_CHECK(gOOJSBooleanClassID != 0);
		OO_CHECK(gOOJSObjectClassID != gOOJSArrayClassID);
		OO_CHECK(gOOJSStringClassID != gOOJSNumberClassID);
		OO_CHECK(gOOJSNumberClassID != gOOJSBooleanClassID);

		JSContext *context = OOJSAcquireContext();
		OO_CHECK(JS_GetClassID(Eval(context, "[1, 2]")) == gOOJSArrayClassID);
		OO_CHECK(JS_GetClassID(Eval(context, "({ a: 1 })")) == gOOJSObjectClassID);
		OO_CHECK(JS_GetClassID(Eval(context, "new String('s')")) == gOOJSStringClassID);
		OO_CHECK(JS_GetClassID(Eval(context, "new Number(1)")) == gOOJSNumberClassID);
		OO_CHECK(JS_GetClassID(Eval(context, "new Boolean(false)")) == gOOJSBooleanClassID);
		OOJSRelinquishContext(context);
	}
}


OO_TEST(flags)
{
	SetUp();
	@autoreleasepool
	{
		OOJavaScriptEngine *engine = [OOJavaScriptEngine sharedEngine];
		const BOOL show = [engine showErrorLocations];
		[engine setShowErrorLocations:YES];
		OO_CHECK([engine showErrorLocations]);
		[engine setShowErrorLocations:NO];
		OO_CHECK(![engine showErrorLocations]);
		[engine setShowErrorLocations:show];

#ifndef NDEBUG
		// Off unless the preferences say otherwise (the scratch home has none).
		OO_CHECK(![engine dumpStackForErrors]);
		OO_CHECK(![engine dumpStackForWarnings]);
		[engine setDumpStackForErrors:YES];
		OO_CHECK([engine dumpStackForErrors]);
		OO_CHECK(![engine dumpStackForWarnings]);
		[engine setDumpStackForWarnings:YES];
		OO_CHECK([engine dumpStackForWarnings]);
		[engine setDumpStackForErrors:NO];
		[engine setDumpStackForWarnings:NO];
		OO_CHECK(![engine dumpStackForErrors]);
		OO_CHECK(![engine dumpStackForWarnings]);
#endif
	}
}


OO_TEST(callJSFunction)
{
	SetUp();
	@autoreleasepool
	{
		OOJavaScriptEngine *engine = [OOJavaScriptEngine sharedEngine];
		JSContext *context = OOJSAcquireContext();
		Owned function = Eval(context, "(function (a, b) { return this.base + a * b; })");
		Owned thisValue = Eval(context, "({ base: 100 })");
		OOJSRelinquishContext(context);

		JSValueConst argv[2] = { JS_NewInt32(context, 6), JS_NewInt32(context, 7) };
		JSValue result = JS_UNDEFINED;
		OO_CHECK([engine callJSFunction:function forObject:thisValue argc:2 argv:argv result:&result]);
		OO_CHECK(JS_VALUE_GET_TAG(result) == JS_TAG_INT && JS_VALUE_GET_INT(result) == 142);
		JS_FreeValue(context, result);
		result = JS_UNDEFINED;

		// A function that throws: NO, and the exception is reported (not left pending).
		StartLog();
		context = OOJSAcquireContext();
		Owned thrower = Eval(context, "(function () { throw new Error('call boom'); })");
		OOJSRelinquishContext(context);
		OO_CHECK(![engine callJSFunction:thrower forObject:thisValue argc:0 argv:NULL result:&result]);
		OO_CHECK(LogLinesContaining("call boom") >= 1);
		context = OOJSAcquireContext();
		OO_CHECK(!JS_HasException(context));
		OOJSRelinquishContext(context);
	}
}


// What a holder of a JS value does in place of the old GC roots: it keeps its own reference
// (OOJSEngineCore.h, rule 4), and the collector leaves the values alone.
OO_TEST(gcRoots)
{
	SetUp();
	@autoreleasepool
	{
		OOJavaScriptEngine *engine = [OOJavaScriptEngine sharedEngine];
		JSContext *context = OOJSAcquireContext();
		JSValue value = EvalIn(context, "({ kept: 'value' })", "test.js");
		JSValue object = EvalIn(context, "({ kept: 'object' })", "test.js");
		OOJSRelinquishContext(context);

		[engine garbageCollectionOpportunity:YES];
		[engine garbageCollectionOpportunity:NO];
		context = OOJSAcquireContext();
		OO_CHECK(cxx_OOStringFromJSValue(context, Eval(context, "1, 'ok'")).value_or("") == "ok");
		OOJSRelinquishContext(context);

		JS_FreeValue(context, value);
		JS_FreeValue(context, object);
		[engine garbageCollectionOpportunity:YES];
	}
}


// MARK: Errors and warnings ------------------------------------------------------------------------

OO_TEST(errorReporting)
{
	SetUp();
	@autoreleasepool
	{
		OOJavaScriptEngine *engine = [OOJavaScriptEngine sharedEngine];
		const BOOL show = [engine showErrorLocations];
#if OOJSENGINE_MONITOR_SUPPORT
		TestMonitor *monitor = [[[TestMonitor alloc] init] autorelease];
		[engine setMonitor:monitor];
#endif

		// An error reported by a native, with the caller's prefix.
		StartLog();
		[engine setShowErrorLocations:NO];
		JSContext *context = OOJSAcquireContext();
		cxx_OOJSReportErrorForCaller(context, std::string("TestClass"), std::string("doThing"), "bad %s %d", "input", 7);
		OOJSReportPendingException(context);
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
		{
			Owned three = Eval(context, "'three'");
			JSValueConst args[2] = { JS_NewInt32(context, 3), three };
			cxx_OOJSReportBadArguments(context, std::string("Ship"), std::string("fly"), 2, args, std::nullopt, std::string("number"));
		}
		OOJSReportPendingException(context);
		OOJSRelinquishContext(context);
		OO_CHECK(LogLinesContaining("Ship.fly: Invalid arguments (3, \"three\") -- expected number.") == 1);

		// An uncaught exception with locations shown: two lines.
		StartLog();
		[engine setShowErrorLocations:YES];
		context = OOJSAcquireContext();
		const char *source = "\n\nthrow new Error('located boom');";
		JSValue result = EvalIn(context, source, "located.js");
		OO_CHECK(JS_IsException(result));
		OOJSReportPendingException(context);
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
		result = EvalIn(context, source, "located.js");
		OO_CHECK(JS_IsException(result));
		OOJSReportPendingException(context);
		OOJSRelinquishContext(context);
		OOJSSetWarningOrErrorStackSkip(0);
		OO_CHECK(LogLinesContaining("located boom") >= 1);
		OO_CHECK(LogLinesContaining("located.js, line 3") == 0);

		// A warning: dashes, and nothing pending.
		StartLog();
		[engine setShowErrorLocations:NO];
		context = OOJSAcquireContext();
		cxx_OOJSReportWarningForCaller(context, std::nullopt, std::string("warnFunc"), "careful %s", "now");
		OO_CHECK(!JS_HasException(context));
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
		[engine setMonitor:nil];
#endif
		[engine setShowErrorLocations:show];
	}
}


#ifndef NDEBUG
// A native that dumps the JS stack it is called from.
JSValue DumpStackNative(OOJS_NATIVE_ARGS)
{
	(void)oojsThis;
	(void)argc;
	(void)oojsArgv;
	OOJSDumpStack(context);
	return JS_UNDEFINED;
}


OO_TEST(stackDump)
{
	SetUp();
	@autoreleasepool
	{
		OOJavaScriptEngine *engine = [OOJavaScriptEngine sharedEngine];
		JSContext *context = OOJSAcquireContext();
		OO_CHECK(JS_SetPropertyStr(context, [engine globalObject], "testDumpStack", JS_NewCFunction(context, DumpStackNative, "testDumpStack", 0)) >= 0);

		// #768's dump is QuickJS's own stack text: each frame's function and location
		// (file:line:column), no variables, innermost first.
		StartLog();
		const char *source = "function dumpTarget(a) {\n\tvar b = a + 1;\n\ttestDumpStack();\n\treturn b;\n}\ndumpTarget(41);\n";
		JSValue result = EvalIn(context, source, "dumpstack.js");
		OO_CHECK(!JS_IsException(result));
		JS_FreeValue(context, result);
		OO_CHECK(LogLinesContaining("at dumpTarget (dumpstack.js:3:") == 1);
		OO_CHECK(LogLinesContaining("at <eval> (dumpstack.js:6:") == 1);
		if (LogLinesContaining("dumpstack.js") == 0)  fprintf(stderr, "%s", LogText().c_str());
		OOJSRelinquishContext(context);

		// The stack skip is the error handler's (#768): a dump keeps every frame.
		StartLog();
		OOJSSetWarningOrErrorStackSkip(1);
		context = OOJSAcquireContext();
		result = EvalIn(context, source, "dumpstack.js");
		OO_CHECK(!JS_IsException(result));
		JS_FreeValue(context, result);
		OOJSRelinquishContext(context);
		OOJSSetWarningOrErrorStackSkip(0);
		OO_CHECK(LogLinesContaining("at dumpTarget (dumpstack.js:3:") == 1);
		OO_CHECK(LogLinesContaining("at <eval> (dumpstack.js:6:") == 1);

		// This backend has no `debugger` hook: the statement does nothing.
		[engine enableDebuggerStatement];
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
	@autoreleasepool
	{
		JSContext *context = OOJSAcquireContext();
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

		Owned p = Eval(context, "'p'");
		JSValueConst params[2] = { JS_NewInt32(context, 1), p };
		OO_CHECK_EQ(cxx_OOJSStringWithJavaScriptParameters(params, 2, context).value_or("<none>"), "(1, \"p\")");
		OOJSRelinquishContext(context);
	}
}


OO_TEST(idAndStringCaches)
{
	SetUp();
	@autoreleasepool
	{
		JSAtom identifier = OOJSID("testIdentifier");
		OO_CHECK_EQ(cxx_OOStringFromJSID(identifier).value_or("<none>"), "testIdentifier");
		OO_CHECK(OOJSID("testIdentifier") == identifier);

		JSContext *context = OOJSAcquireContext();
		Owned literal(OOJSSTR("test literal"));
		OO_CHECK(JS_IsString(literal));
		OO_CHECK_EQ(cxx_OOStringFromJSValue(context, literal).value_or("<none>"), "test literal");
		OOJSRelinquishContext(context);
	}
}


OO_TEST(nativeObjectValues)
{
	SetUp();
	@autoreleasepool
	{
		JSContext *context = OOJSAcquireContext();

		// nil and OONull are JS null; OONull is one object that copies as itself.
		OO_CHECK(JS_IsNull(Owned(OOJSValueFromNativeObject(context, nil))));
		OONull *null = [OONull null];
		OO_CHECK(null != nil && [OONull null] == null);
		OO_CHECK([[null copy] autorelease] == null);
		OO_CHECK_EQ(oo::DescriptionOf(null), "<null>");
		OO_CHECK(JS_IsNull(Owned(OOJSValueFromNativeObject(context, null))));
		OO_CHECK(JS_IsNull(Owned([null oo_jsValueInContext:context])));

		// A plain OOObject has no JS value, and describes itself by its class name and components.
		TestNative *native = [[[TestNative alloc] init] autorelease];
		OO_CHECK(JS_IsUndefined(Owned(OOJSValueFromNativeObject(context, native))));
		{
			// No JS object for it either. #768's OOJSObjectFromNativeObject() boxes the undefined
			// with JS_ToObject(), which throws: the exception it leaves is cleared.
			Owned noObject(OOJSObjectFromNativeObject(context, native));
			OO_CHECK(!JS_IsObject(noObject));
			JS_FreeValue(context, JS_GetException(context));
		}
		OO_CHECK(![native cxx_oo_jsClassName].has_value());
		OO_CHECK_EQ([native cxx_oo_jsDescription].value_or("<none>"), "[TestNative x=1]");
		OO_CHECK_EQ([native cxx_oo_jsDescriptionWithClassName:std::string("Named")].value_or("<none>"), "[Named x=1]");
		OO_CHECK_EQ([[[[OOObject alloc] init] autorelease] cxx_oo_jsDescription].value_or("<none>"), "[object OOObject]");

		// A native vector is a Vector3D.
		oo::Ref<OONativeVector> vector = oo::makeRef<OONativeVector>(make_vector(1.0f, 2.0f, 3.0f));
		Owned vectorValue(OOJSValueFromPList(context, oo::PList(oo::PList::Object(vector))));
		OO_CHECK(JS_IsObject(vectorValue));
		const char *className = OOJSClassName(JS_GetClassID(vectorValue));
		OO_CHECK(className != nullptr && std::strcmp(className, "Vector3D") == 0);
		OO_CHECK_EQ(cxx_OOStringFromJSValue(context, vectorValue).value_or("<none>"), "(1, 2, 3)");

		OOJSRelinquishContext(context);
	}
}


OO_TEST(jsValueHolder)
{
	SetUp();
	@autoreleasepool
	{
		JSContext *context = OOJSAcquireContext();
		Owned object = Eval(context, "({ held: 'yes' })");
		OOJSValue *holder = [OOJSValue valueWithJSValue:object inContext:context];
		OO_CHECK(holder != nil);
		OO_CHECK(IsSameObject(Owned([holder oo_jsValueInContext:context]), object));
		OO_CHECK(IsSameObject(Owned(OOJSValueFromNativeObject(context, holder)), object));
		OOJSRelinquishContext(context);

		// A nil context is acquired for the call.
		OOJSValue *noContext = [[[OOJSValue alloc] initWithJSValue:JS_NewInt32(context, 9) inContext:NULL] autorelease];
		JSValue nine = [noContext oo_jsValueInContext:NULL];
		OO_CHECK(JS_VALUE_GET_TAG(nine) == JS_TAG_INT && JS_VALUE_GET_INT(nine) == 9);

		// Undefined holds undefined.
		OOJSValue *undefinedHolder = [OOJSValue valueWithJSValue:JS_UNDEFINED inContext:NULL];
		OO_CHECK(JS_IsUndefined([undefinedHolder oo_jsValueInContext:NULL]));

		[[OOJavaScriptEngine sharedEngine] garbageCollectionOpportunity:YES];	// the held object survives
		context = OOJSAcquireContext();
		OO_CHECK_EQ(cxx_OOStringFromJSValue(context, Owned([holder oo_jsValueInContext:context])).value_or("<none>"), "[object Object]");
		OOJSRelinquishContext(context);
	}
}


OO_TEST(objectWrapper)
{
	SetUp();
	TestNative *native = nil;
	const int deallocs = sNativeDeallocs;
	@autoreleasepool
	{
		native = [[TestNative alloc] init];
		JSContext *context = OOJSAcquireContext();
		OOJSRegisterClass(&sTestWrapperClassID, &sTestWrapperClass);
		Owned wrapper(JS_NewObjectClass(context, static_cast<int>(sTestWrapperClassID)));
		OO_CHECK(JS_IsObject(wrapper));
		OO_CHECK(JS_SetOpaque(wrapper, [native retain]) == 0);
		OO_CHECK(JS_SetPropertyStr(context, wrapper, "toString", JS_NewCFunction(context, OOJSObjectWrapperToString, "toString", 0)) >= 0);

		// Unconverted, the wrapper has no native object: toString names the JS class.
		OO_CHECK_EQ(CallToString(context, wrapper), "[object TestWrapper]");

		// With the basic private-object converter, toString is the native object's JS description.
		OOJSRegisterObjectConverter(sTestWrapperClassID, OOJSBasicPrivateObjectConverter);
		OO_CHECK_EQ(CallToString(context, wrapper), "[TestNative x=1]");

		// The class-checked getters.
		OO_CHECK(OOJSNativeObjectFromJSObject(context, wrapper) == native);
		OO_CHECK(OOJSNativeObjectOfClassFromJSObject(context, wrapper, [TestNative class]) == native);
		OO_CHECK(OOJSNativeObjectOfClassFromJSObject(context, wrapper, [OOObject class]) == native);
		OO_CHECK(OOJSNativeObjectOfClassFromJSObject(context, wrapper, [OONull class]) == nil);
		OO_CHECK(OOJSNativeObjectOfClassFromJSValue(context, wrapper, [TestNative class]) == native);
		OO_CHECK(OOJSNativeObjectOfClassFromJSValue(context, wrapper, [OONull class]) == nil);
		OO_CHECK(OOJSNativeObjectOfClassFromJSValue(context, JS_NewInt32(context, 1), [TestNative class]) == nil);

		// Finalising clears the native object's JS self, releases it and empties the slot.
		OOJSObjectWrapperFinalize(JS_GetRuntime(context), wrapper);
		OO_CHECK(native->_clears == 1);
		JSClassID ignored;
		OO_CHECK(JS_GetAnyOpaque(wrapper, &ignored) == NULL);
		OO_CHECK(OOJSNativeObjectFromJSObject(context, wrapper) == nil);
		OOJSObjectWrapperFinalize(JS_GetRuntime(context), wrapper);	// nothing left: does nothing
		OO_CHECK(native->_clears == 1);

		// With no native object, toString names the JS class.
		OO_CHECK_EQ(CallToString(context, wrapper), "[object TestWrapper]");

		OOJSRegisterObjectConverter(sTestWrapperClassID, NULL);
		OOJSRelinquishContext(context);
	}
	OO_CHECK(sNativeDeallocs == deallocs);	// the test's own reference
	[native release];
	OO_CHECK(sNativeDeallocs == deallocs + 1);
}


OO_TEST(entityPredicates)
{
	SetUp();
	@autoreleasepool
	{
		OO_CHECK(!JSEntityIsJavaScriptVisiblePredicate(nil, NULL));
		OO_CHECK(!JSEntityIsJavaScriptSearchablePredicate(nil, NULL));
		OO_CHECK(!JSEntityIsDemoShipPredicate(nil, NULL));

		TestScriptEntity *entity = [[[TestScriptEntity alloc] init] autorelease];
		entity->_testStatus = STATUS_IN_FLIGHT;
		OO_CHECK(!JSEntityIsJavaScriptVisiblePredicate(entity, NULL));
		OO_CHECK(!JSEntityIsJavaScriptSearchablePredicate(entity, NULL));

		entity->_scriptVisible = YES;
		OO_CHECK(JSEntityIsJavaScriptVisiblePredicate(entity, NULL));
		OO_CHECK(JSEntityIsJavaScriptSearchablePredicate(entity, NULL));	// neither ship nor planet
		OO_CHECK(!JSEntityIsDemoShipPredicate(entity, NULL));

		entity->_ship = YES;
		OO_CHECK(JSEntityIsJavaScriptSearchablePredicate(entity, NULL));
		OO_CHECK(!JSEntityIsDemoShipPredicate(entity, NULL));
		entity->_subEntity = YES;
		OO_CHECK(!JSEntityIsJavaScriptSearchablePredicate(entity, NULL));
		entity->_subEntity = NO;
		entity->_testStatus = STATUS_COCKPIT_DISPLAY;
		OO_CHECK(!JSEntityIsJavaScriptSearchablePredicate(entity, NULL));
		OO_CHECK(JSEntityIsDemoShipPredicate(entity, NULL));
		entity->_subEntity = YES;
		OO_CHECK(!JSEntityIsDemoShipPredicate(entity, NULL));

		// A JS function as a predicate: called with the entity's JS value.
		JSContext *context = OOJSAcquireContext();
		Owned isFortyTwo = Eval(context, "(function (e) { return e === 42; })");
		JSFunctionPredicateParameter param = { context, isFortyTwo, JS_UNDEFINED, NO };
		OO_CHECK(JSFunctionPredicate(entity, &param));
		OO_CHECK(!param.errorFlag);
		Owned isNotFortyTwo = Eval(context, "(function (e) { return e !== 42; })");
		param.function = isNotFortyTwo;
		OO_CHECK(!JSFunctionPredicate(entity, &param));
		OO_CHECK(!param.errorFlag);

		StartLog();
		Owned thrower = Eval(context, "(function (e) { throw new Error('predicate boom'); })");
		param.function = thrower;
		OO_CHECK(!JSFunctionPredicate(entity, &param));
		OO_CHECK(param.errorFlag);
		OO_CHECK(LogLinesContaining("predicate boom") >= 1);
		Owned always = Eval(context, "(function (e) { return true; })");
		param.function = always;
		OO_CHECK(!JSFunctionPredicate(entity, &param));	// the error flag stops further filtering
		OOJSRelinquishContext(context);
	}
}


OO_TEST(propertyListsFromJS)
{
	SetUp();
	@autoreleasepool
	{
		JSContext *context = OOJSAcquireContext();
		oo::PList array = cxx_OOJSPListFromJSValue(context, Eval(context, "[1, null, 'a', [true]]"));
		OO_CHECK(array.isArray());
		const oo::PList::Array *elements = array.getIf<oo::PList::Array>();
		OO_CHECK(elements != nullptr && elements->size() == 4);
		if (elements != nullptr && elements->size() == 4)
		{
			OO_CHECK((*elements)[0] == oo::PList::signedInteger(1));
			OO_CHECK(oo::ObjectIn((*elements)[1]) == [OONull null]);	// a null element is OONull
			OO_CHECK((*elements)[2] == oo::PList(std::string("a")));
			OO_CHECK((*elements)[3].isArray());
		}
		OO_CHECK(oo::ObjectIn(cxx_OOJSPListFromJSValue(context, Eval(context, "[]"))) == nil);
		OO_CHECK(cxx_OOJSPListFromJSValue(context, Eval(context, "[]")).isArray());

		oo::PList dict = cxx_OOJSPListFromJSValue(context, Eval(context, "({ s: new String('x'), n: new Number(2.5), b: new Boolean(false) })"));
		OO_CHECK(dict.isDict());
		OO_CHECK(dict.find("s") != nullptr && *dict.find("s") == oo::PList(std::string("x")));
		OO_CHECK(dict.find("n") != nullptr && *dict.find("n") == oo::PList(2.5));
		OO_CHECK(dict.find("b") != nullptr && *dict.find("b") == oo::PList(static_cast<bool>(false)));	// OOCocoa.h defines false as 0 (amendment oo-kq7 item 8)

		// Round trip through OOJSValueFromPList.
		oo::PList back = cxx_OOJSPListFromJSValue(context, Owned(OOJSValueFromPList(context, oo::PList(oo::PList::Array{oo::PList(std::string("q")), oo::PList::signedInteger(5)}))));
		OO_CHECK(back == oo::PList(oo::PList::Array{oo::PList(std::string("q")), oo::PList::signedInteger(5)}));
		OOJSRelinquishContext(context);
	}
}


// MARK: Reset (last: it rebuilds the context) -----------------------------------------------------

OO_TEST(reset)
{
	SetUp();
	@autoreleasepool
	{
		OOJavaScriptEngine *engine = [OOJavaScriptEngine sharedEngine];
		JSContext *context = OOJSAcquireContext();
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

		OO_CHECK([engine reset]);
		OO_CHECK(willResets == 1 && didResets == 1 && otherSender == 0);
		OO_CHECK(contextDuringWill);
		OO_CHECK([OOJavaScriptEngine sharedEngine] == engine);
		OO_CHECK(gOOJSMainThreadContext != NULL);
		OO_CHECK(JS_IsObject([engine globalObject]));
		OO_CHECK(gOOJSArrayClassID != 0);

		context = OOJSAcquireContext();
		OO_CHECK_EQ(cxx_OOStringFromJSValue(context, Eval(context, "typeof survivesReset")).value_or("<none>"), "undefined");
		OO_CHECK(JS_IsObject(Eval(context, "Vector3D")));
		OO_CHECK(JS_GetClassID(Eval(context, "[1]")) == gOOJSArrayClassID);
		// The standard converters are registered again.
		OO_CHECK(cxx_OOJSPListFromJSValue(context, Eval(context, "[1]")).isArray());
		OOJSRelinquishContext(context);

		oo::NotificationCenter::defaultCenter().removeObserver(&marker);
	}
}


// A held value left autoreleased in the thread's own pool (no @autoreleasepool here, as the
// game's exit(0) leaves the frame's pools open) is freed when libobjc drains that pool at thread
// detach, after the C++ static destructors; freeing its reference and removing its observer must
// still find the engine and the notification center. The check is the process exiting 0.
OO_TEST(aValueLeftInTheThreadPoolAtExit)
{
	SetUp();
	JSContext *context = OOJSAcquireContext();
	Owned object = Eval(context, "({ leftAtExit: true })");
	OOJSValue *holder = [OOJSValue valueWithJSValue:object inContext:context];
	OO_CHECK(holder != nil && IsSameObject(Owned([holder oo_jsValueInContext:context]), object));
	OOJSRelinquishContext(context);
}


OO_TEST(cleanUp)
{
	oo::log::logger().setSink(nullptr);
	stdfs::current_path(stdfs::temp_directory_path());
	std::error_code ignored;
	stdfs::remove_all(sRoot, ignored);
	OO_CHECK(true);
}


OO_TEST_MAIN()
