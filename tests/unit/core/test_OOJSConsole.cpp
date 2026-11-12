/*	test_OOJSConsole.mm
	Unit tests for the debug console's JS binding (src/Core/Debug/OOJSConsole.h/.mm).

	It runs the Console and ConsoleSettings classes in a real QuickJS-ng context and links the
	game's own objects for the binding, the engine's private-slot glue (OOJSPrivateObject.cpp), its
	class registry (OOJSClasses.mm) and its exception translator (OOJSEngineNativeWrappers.mm); the
	console's JS objects hold the C++ debug monitor. What the rest of the game provides is defined
	below as the smallest stand-in that does the same thing: the C++ debug monitor's members
	(recording what they are asked), the JavaScript engine's flags and its time limiter, the
	universe's detail level and FPS display, the OpenGL extension manager's answers, an entity that
	can be inspected, the script stack, the error reporters and the string and property-list
	converters.
	It imports neither OOJavaScriptEngine.h nor Universe.h, which would bring in the game classes.
	The tests pin the JS-visible behaviour of
	every property and method that compiles in the test flavour.
	Run: tests/run.sh unit
*/

#include "OOFoundation.h"
#include "OOJSConsole.h"
#include "OODebugMonitor.h"
#include "OOOpenGLExtensionManager.h"
#include "OOJSEngineCore.h"
#include "OODebugFlags.h"
#include "oofnd/Log.hpp"
#include "oofnd/String.hpp"

#include "oo_test.hpp"

#include <cmath>
#include <cstdarg>
#include <cstdlib>
#include <cstdio>
#include <string>
#include <utility>
#include <vector>


// MARK: The debug monitor's C++ members -----------------------------------------------------------

namespace {

struct MonitorRecord
{
	std::vector<std::pair<std::string, oo::PList>>	configurationSets;
	oo::PList::Dict									configuration;
	std::vector<std::string>						lines;			// "colorKey|text|location,length"
	int												clears = 0;
	int												memoryDumps = 0;
	int												jsMemoryDumps = 0;
	bool											ignoresDroppedPackets = false;
};

MonitorRecord sMonitor;

}	// namespace


OODebugMonitor *OODebugMonitor::sharedDebugMonitor()
{
	static OODebugMonitor *monitor = nullptr;
	if (monitor == nullptr)  monitor = oo::makeRef<OODebugMonitor>().leakRef();
	return monitor;
}

bool OODebugMonitor::setDebugger(OODebuggerInterface *)  { return false; }
void OODebugMonitor::disconnectDebugger(OODebuggerInterface *, const std::optional<std::string> &)  {}
void OODebugMonitor::performJSConsoleCommand(const std::string &)  {}

void OODebugMonitor::appendJSConsoleLine(const std::string &string, const std::optional<std::string> &colorKey, NSRange emphasisRange)
{
	sMonitor.lines.push_back(colorKey.value_or("(none)") + "|" + string + "|" + std::to_string(emphasisRange.location) + "," + std::to_string(emphasisRange.length));
}

void OODebugMonitor::appendJSConsoleLine(const std::string &string, const std::optional<std::string> &colorKey)
{
	appendJSConsoleLine(string, colorKey, NSMakeRange(0, 0));
}

void OODebugMonitor::clearJSConsole()  { sMonitor.clears++; }
void OODebugMonitor::showJSConsole()  {}

oo::PList OODebugMonitor::configurationValueForKey(const std::string &key)
{
	auto found = sMonitor.configuration.find(key);
	return (found != sMonitor.configuration.end()) ? found->second : oo::PList();
}

long long OODebugMonitor::configurationIntValueForKey(const std::string &, long long value)  { return value; }

void OODebugMonitor::setConfigurationValue(const oo::PList &value, const std::string &key)
{
	sMonitor.configurationSets.emplace_back(key, value);
}

std::vector<std::string> OODebugMonitor::configurationKeys()  { return {}; }
bool OODebugMonitor::debuggerConnected()  { return false; }
void OODebugMonitor::dumpMemoryStatistics()  { sMonitor.memoryDumps++; }
size_t OODebugMonitor::dumpJSMemoryStatistics()  { sMonitor.jsMemoryDumps++; return 0; }
void OODebugMonitor::setTCPIgnoresDroppedPackets(bool flag)  { sMonitor.ignoresDroppedPackets = flag; }
bool OODebugMonitor::TCPIgnoresDroppedPackets()  { return sMonitor.ignoresDroppedPackets; }
void OODebugMonitor::setUsingPlugInController(bool)  {}
bool OODebugMonitor::usingPlugInController()  { return false; }
std::string OODebugMonitor::sourceCodeForFile(const std::string &, unsigned)  { return std::string(); }
#if OOLITE_SDL
void OODebugMonitor::applicationWillTerminate()  {}
#endif
void OODebugMonitor::jsEngine(OOJavaScriptEngine *, JSContext *, const std::string &, const std::optional<std::string> &, unsigned, unsigned, bool, const std::string &)  {}
void OODebugMonitor::jsEngine(OOJavaScriptEngine *, JSContext *, const std::string &, const std::optional<std::string> &)  {}
// The monitor's JS glue and description: its JS value is defined below, with the console object it
// answers.
void OODebugMonitor::clearJSSelf(JSValueConst)  {}
std::string OODebugMonitor::className() const  { return "OODebugMonitor"; }
std::string OODebugMonitor::description() const  { return "<OODebugMonitor>"; }


// MARK: What the rest of the game provides ---------------------------------------------------------

#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

JSContext *gOOJSMainThreadContext = nullptr;

namespace {

std::vector<std::string> sWarnings;
int sLogMarkers = 0;
int sInspections = 0;

}	// namespace


void cxx_OOJSReportErrorWithArguments(JSContext *context, const char *format, va_list args)
{
	std::string msg = oo::str::vformat(format, args);
	JS_ThrowPlainError(context, "%s", msg.c_str());
}


void cxx_OOJSReportError(JSContext *context, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	cxx_OOJSReportErrorWithArguments(context, format, args);
	va_end(args);
}


void cxx_OOJSReportWarning(JSContext *context, const char *format, ...)
{
	(void)context;
	va_list args;
	va_start(args, format);
	sWarnings.push_back(oo::str::vformat(format, args));
	va_end(args);
}


void cxx_OOJSReportBadArguments(JSContext *context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, int argc, JSValueConst *, const std::optional<std::string> &message, const std::optional<std::string> &expectedArgsDescription)
{
	cxx_OOJSReportError(context, "bad arguments: %s.%s (%d): %s; expected %s", scriptClass.value_or("").c_str(), function.value_or("").c_str(), argc, message.value_or("").c_str(), expectedArgsDescription.value_or("").c_str());
}


void OOJSReportBadPropertySelector(JSContext *context, JSValueConst, int, const JSCFunctionListEntry *, size_t)
{
	cxx_OOJSReportError(context, "bad property selector");
}


// As the engine's: the pending exception, else an uncatchable error that stops the script.
JSValue OOJSNativeFailure(JSContext *context)
{
	if (JS_HasException(context))  return JS_EXCEPTION;
	JSValue error = JS_NewError(context);
	JS_SetUncatchableError(context, error);
	return JS_Throw(context, error);
}


// The atom cache and the pending-exception reporter, which the class registry and the binding call.
JSAtom cxx_OOJSIDFromString(const std::string &string)
{
	return JS_NewAtomLen(gOOJSMainThreadContext, string.data(), string.size());
}


void OOJSReportPendingException(JSContext *context)
{
	JS_FreeValue(context, JS_GetException(context));
}


std::optional<std::string> cxx_OOStringFromJSValue(JSContext *context, JSValueConst value)
{
	if (JS_IsNull(value) || JS_IsUndefined(value))  return std::nullopt;
	std::size_t length = 0;
	const char *chars = JS_ToCStringLen(context, &length, value);
	if (chars == nullptr)
	{
		JS_FreeValue(context, JS_GetException(context));
		return std::nullopt;
	}
	std::string result(chars, length);
	JS_FreeCString(context, chars);
	return result;
}


// Strings, integers, reals and booleans, as the engine converts them; null for anything else.
// Owned by the caller.
JSValue OOJSValueFromPList(JSContext *context, const oo::PList &plist)
{
	if (const std::string *str = plist.getIf<std::string>())  return JS_NewStringLen(context, str->data(), str->size());
	if (plist.isBool())  return OOJSValueFromBOOL(*plist.getIf<bool>());
	if (plist.isNumber())  return JS_NewNumber(context, plist.doubleValue());
	if (plist.isArray())  return JS_NewArray(context);	// the script stack: its length is what the test reads
	return JS_NULL;
}


// As the engine's: JavaScript truthiness, NO if the conversion throws.
bool OOJSValueToBOOL(JSContext *context, JSValueConst value)
{
	int result = JS_ToBool(context, value);
	if (result < 0)
	{
		JS_FreeValue(context, JS_GetException(context));
		return false;
	}
	return result != 0;
}


// As the engine's: a number rounded to the nearest integer; NaN or out of range is an error.
bool OOJSValueToInt32(JSContext *context, JSValueConst value, int32_t *outValue)
{
	double number;
	if (JS_ToFloat64(context, &number, value) < 0)  return false;
	number = std::floor(number + 0.5);
	if (std::isnan(number) || number < INT32_MIN || number > INT32_MAX)
	{
		cxx_OOJSReportError(context, "can't convert to an integer");
		return false;
	}
	*outValue = static_cast<int32_t>(number);
	return true;
}


oo::PList cxx_OOJSPListFromJSValue(JSContext *context, JSValueConst value)
{
	if (JS_IsString(value))  return oo::PList(cxx_OOStringFromJSValue(context, value).value_or(""));
	if (JS_IsBool(value))  return oo::PList(JS_ToBool(context, value) != 0);
	double number = 0;
	if (JS_IsNumber(value) && JS_ToFloat64(context, &number, value) == 0)  return oo::PList(number);
	return oo::PList();
}


namespace {
JSValue sConsoleObject = JS_UNDEFINED;	// the global holds it
JSValue sGlobal = JS_UNDEFINED;
}	// namespace

// The monitor's JS value is the console object (as the monitor's
// jsValueInContext() makes it), owned by the caller; undefined before it is made.
JSValue OODebugMonitor::jsValueInContext(JSContext *context)
{
	return JS_DupValue(context, sConsoleObject);
}




void OOJSRegisterObjectConverter(JSClassID, OOJSClassConverterCallback)  {}
oo::PList OOJSBasicPrivateObjectConverter(JSContext *, JSValueConst)  { return oo::PList(); }


// The shared toString(), which the private-slot glue hands a `this` of another class (never
// reached here).
JSValue OOJSObjectWrapperToString(JSContext *, JSValueConst, int, JSValueConst *)  { std::abort(); }


JSValue OOJSUnconstructableConstruct(JSContext *context, JSValueConst, int, JSValueConst *)
{
	cxx_OOJSReportError(context, "unconstructable");
	return JS_EXCEPTION;
}


// The engine's time limiter (OOJavaScriptEngine.mm), which the profiler and the binding pause and
// reset: it keeps the limit it is given and nothing else (no script here runs long).
namespace {
OOTimeDelta sTimeLimit = 1.0;
}	// namespace
void OOJSPauseTimeLimiter(void)  {}
void OOJSResumeTimeLimiter(void)  {}
void OOJSResetTimeLimiter(void)  {}
OOTimeDelta OOJSGetTimeLimiterLimit(void)  { return sTimeLimit; }
void OOJSSetTimeLimiterLimit(OOTimeDelta limit)  { sTimeLimit = limit; }
void OOJSExcludeTimeFromLimiter(OOTimeDelta)  {}


#ifndef NDEBUG
void OOJSUnreachable(const char *function, const char *, unsigned)
{
	std::printf("unreachable reached in %s\n", function);
	abort();
}
#endif


#ifndef OOJSDumpStack
void OOJSDumpStack(JSContext *)  {}	// the profiler's, when a time limit is hit
#endif


std::string OOPlatformDescription(void)  { return "test platform"; }
void OOLogInsertMarker(void)  { sLogMarkers++; }


std::string cxx_OOStringFromGraphicsDetail(OOGraphicsDetail detail)
{
	return "DETAIL_" + std::to_string(static_cast<int>(detail));
}


OOGraphicsDetail cxx_OOGraphicsDetailFromString(const std::string &string)
{
	return (string == "DETAIL_2") ? OOGraphicsDetail::kShaders : OOGraphicsDetail::kMinimum;
}


// EntityHelpers.mm's, which the test does not link: an entity's node (its hold and its description)
// is reached only for an entity, which the test has none of. A null hold releases nothing.
class Entity;
namespace oo {
namespace detail { void EntityRelease(Entity *entity) noexcept; }
std::string EntityDescription(Entity *entity);
Entity *WithObject(Entity *entity);
}  // namespace oo
void oo::detail::EntityRelease(Entity *entity) noexcept  { if (entity != nullptr)  std::abort(); }
std::string oo::EntityDescription(Entity *)  { std::abort(); }
Entity *oo::WithObject(Entity *entity)  { if (entity != nullptr)  std::abort();  return nullptr; }


// MARK: Debug-flavour link stand-ins
// ------------------------------------------------- OOJSConsole.mm's callObjC()
// (#if OO_DEBUG) and its diagnostic dumps (#if DEBUG) compile only in the debug
// flavour, which builds this test for the ASan stage. No case reaches
// them; a call is a test bug.

#if OO_DEBUG
#include "OOShaderUniformMethodType.h"

class Entity;

std::optional<std::string> cxx_OOStringFromJSValueEvenIfNull(JSContext *, JSValueConst)  { std::abort(); }
std::optional<std::string> OOJSEntityJSClassName(Entity *)  { std::abort(); }
bool OOJSCallEntityMethod(JSContext *, Entity *, const std::string &, int, JSValueConst *, JSValue *)  { std::abort(); }
OOShaderUniformType OOShaderUniformTypeFromEncoding(const char *)  { std::abort(); }
// oo::EntityIn() reads ::TestEntityObject's _cxxEntity ivar; its offset variable is
// emitted by the game's Entity implementation, which this test does not link. The name
// is the one clang gives it: the ivar's type encoding, with its '=' written as byte 2.
extern "C" int gOOTestEntityCxxEntityIvarOffset __asm__("__objc_ivar_offset_Entity._cxxEntity.{Ref<Entity>\002^{Entity}}");
int gOOTestEntityCxxEntityIvarOffset = 0;
#endif

#if DEBUG
#include "ResourceManager.h"

std::string cxx_OOJSDescribeValue(JSContext *, JSValueConst, bool)  { std::abort(); }
std::optional<std::string> ResourceManager::diagnosticFileLocation()  { std::abort(); }
#endif


// The engine (OOJavaScriptEngine.h), declared with the header's names and
// signatures but not its class; the stand-in's answers are kept.
class OOJavaScriptEngine
{
public:
	static OOJavaScriptEngine *sharedEngine();
	JSValueConst globalObject();
	bool showErrorLocations();
	void setShowErrorLocations(bool flag);
	bool dumpStackForErrors();
	void setDumpStackForErrors(bool flag);
	bool dumpStackForWarnings();
	void setDumpStackForWarnings(bool flag);

	bool _showErrorLocations = false, _dumpStackForErrors = false, _dumpStackForWarnings = false;
};


OOJavaScriptEngine *OOJavaScriptEngine::sharedEngine()
{
	static OOJavaScriptEngine *engine = new OOJavaScriptEngine;
	return engine;
}

JSValueConst OOJavaScriptEngine::globalObject()  { return sGlobal; }
bool OOJavaScriptEngine::showErrorLocations()  { return _showErrorLocations; }
void OOJavaScriptEngine::setShowErrorLocations(bool flag)  { _showErrorLocations = flag; }
bool OOJavaScriptEngine::dumpStackForErrors()  { return _dumpStackForErrors; }
void OOJavaScriptEngine::setDumpStackForErrors(bool flag)  { _dumpStackForErrors = flag; }
bool OOJavaScriptEngine::dumpStackForWarnings()  { return _dumpStackForWarnings; }
void OOJavaScriptEngine::setDumpStackForWarnings(bool flag)  { _dumpStackForWarnings = flag; }


// The OpenGL extension manager's answers: the C++ manager's members the console reads.
OOOpenGLExtensionManager *OOOpenGLExtensionManager::sharedManager()
{
	static OOOpenGLExtensionManager *manager = nullptr;
	if (manager == nullptr)  manager = new OOOpenGLExtensionManager;	// never released, as the game's
	return manager;
}

OOOpenGLExtensionManager::~OOOpenGLExtensionManager()  {}
OOGraphicsDetail OOOpenGLExtensionManager::maximumDetailLevel()  { return kOOGraphicsDetailMaximum; }
std::optional<std::string> OOOpenGLExtensionManager::vendorString()  { return std::string("Test Vendor"); }
std::optional<std::string> OOOpenGLExtensionManager::rendererString()  { return std::nullopt; }
GLint OOOpenGLExtensionManager::textureUnitCount()  { return 4; }
GLint OOOpenGLExtensionManager::textureImageUnitCount()  { return 16; }


// The universe as the code under test sees it: a stand-in for the C++ class,
// with the header's names and signatures.
class Universe
{
public:
	OOGraphicsDetail _detailLevel;
	bool _displayFPS;

	OOGraphicsDetail getDetailLevel();
	void setDetailLevel(OOGraphicsDetail);
	bool getDisplayFPS();
	void setDisplayFPS(bool);
};
typedef Universe FakeUniverse;

OOGraphicsDetail Universe::getDetailLevel()	{ return _detailLevel; }
void Universe::setDetailLevel(OOGraphicsDetail value)	{ _detailLevel = value; }
bool Universe::getDisplayFPS()	{ return _displayFPS; }
void Universe::setDisplayFPS(bool value)	{ _displayFPS = value; }

class Universe;
Universe *gSharedUniverse = nullptr;


// An entity, as the console's inspectEntity() sees it: one answers -inspect
// (the Mac debug OXP's inspector), one does not.
// answersInspect() is what -respondsToSelector: of -inspect answered.
class TestEntityObject : public oo::RefCounted
{
public:
	virtual bool answersInspect()  { return false; }
	virtual void inspect()  {}
};

class InspectableEntity final : public TestEntityObject
{
public:
	bool answersInspect() override  { return true; }
	void inspect() override  { sInspections++; }
};


namespace {

TestEntityObject *sPlainEntity = nullptr;
TestEntityObject *sInspectableEntity = nullptr;

}	// namespace


// Each entity's C++ part (an entity's JS object holds it, JSValueToEntity() answers it and
// TestObjectOf its object, which the console asks to -inspect). Kept for the life of the test.
class Entity : public oo::RefCounted
{
};

namespace {
Entity *PlainPart()
{
	static const oo::Ref<Entity> part = oo::makeRef<Entity>();
	return part.get();
}
Entity *InspectablePart()
{
	static const oo::Ref<Entity> part = oo::makeRef<Entity>();
	return part.get();
}
}	// namespace


// inspectEntity(true) is the inspectable entity, inspectEntity(false) the other; anything else none.
// (Declared as OOJSEntity.h declares it.)
bool JSValueToEntity(JSContext *context, JSValueConst value, Entity **outEntity);
bool JSValueToEntity(JSContext *context, JSValueConst value, Entity **outEntity)
{
	if (!JS_IsBool(value))  return false;
	*outEntity = JS_ToBool(context, value) ? InspectablePart() : PlainPart();
	return true;
}


// Each C++ part's entity, null for any other.
::TestEntityObject *TestObjectOf(Entity *entity)
{
	if (entity == InspectablePart())  return sInspectableEntity;
	if (entity == PlainPart())  return sPlainEntity;
	return nullptr;
}

// EntityHelpers.mm's oo::InspectEntity(): -inspect, if the entity's object
// answers it.
namespace oo { void InspectEntity(Entity *entity); }  // namespace oo
void oo::InspectEntity(Entity *entity)
{
	::TestEntityObject *object = TestObjectOf(entity);
	if (object != nullptr && object->answersInspect())  object->inspect();
}


#include "OOScript.h"


// OOJSScript (OOJSScript.h), which the code under test calls. A script is a
// C++ object, so the stand-in is a C++ subclass of OOScript declaring the
// members that code calls.
class OOJSScript : public OOScript
{
public:
	static std::vector<oo::Ref<OOJSScript>> scriptStack();
	static OOJSScript *currentlyRunningScript();
};

// The time limiter linked here names the running script when a script overruns, which no case does
// (the class method was never sent; as a C++ static it must be defined).
OOJSScript *OOJSScript::currentlyRunningScript()  { std::abort(); }

std::vector<oo::Ref<OOJSScript>> OOJSScript::scriptStack()
{
	return {};
}


// MARK: The context -------------------------------------------------------------------------------

namespace {

JSRuntime *sRuntime;
JSContext *sContext;


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = JS_NewRuntime();
	sContext = JS_NewContext(sRuntime);
	gOOJSMainThreadContext = sContext;
	sGlobal = JS_GetGlobalObject(sContext);
	gSharedUniverse = new FakeUniverse();
	sPlainEntity = oo::makeRef<TestEntityObject>().leakRef();
	sInspectableEntity = oo::makeRef<InspectableEntity>().leakRef();

	sConsoleObject = DebugMonitorToJSConsole(sContext, OODebugMonitor::sharedDebugMonitor());
	// The global holds the console; sConsoleObject borrows it.
	JS_SetPropertyStr(sContext, sGlobal, "console", sConsoleObject);
}


// Evaluates src and gives its result as a string ("undefined", "null", ...), or "threw: <message>".
std::string Eval(const char *src)
{
	SetUpContext();
	std::string wrapped = std::string("(function () { try { return String(") + src + "); } catch (e) { return 'threw: ' + (e && e.message !== undefined ? e.message : e); } })()";
	JSValue result = JS_Eval(sContext, wrapped.c_str(), wrapped.size(), "test.js", JS_EVAL_TYPE_GLOBAL);
	if (JS_IsException(result))
	{
		JS_FreeValue(sContext, JS_GetException(sContext));
		return "<evaluation failed>";
	}
	std::string text = cxx_OOStringFromJSValue(sContext, result).value_or("<not a string>");
	JS_FreeValue(sContext, result);
	return text;
}


std::string EvalShown(const char *src, const char *expected)
{
	std::string result = Eval(src);
	if (result != expected)  std::printf("    %s\n    gave: %s\n", src, result.c_str());
	return result;
}
#define OO_CHECK_EVAL(src, expected)  OO_CHECK_EQ(EvalShown(src, expected), expected)

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

// The console object and its settings object are made, and are not constructible from JS.
OO_TEST(theConsoleObjects)
{
	OO_CHECK_EVAL("typeof console", "object");
	OO_CHECK_EVAL("typeof console.settings", "object");
	OO_CHECK_EVAL("Object.getPrototypeOf(console) === Object.getPrototypeOf(console.settings)", "false");
	OO_CHECK_EVAL("console.DEBUG_LINKED_LISTS", std::to_string(oo::ToUnderlying(OODebugFlags::kLinkedLists)).c_str());
	OO_CHECK_EVAL("console.DEBUG_SHADER_VALIDATION", std::to_string(oo::ToUnderlying(OODebugFlags::kShaderValidation)).c_str());
}


// The settings are the monitor's configuration: read, set, set to null/undefined, deleted.
OO_TEST(theSettingsAreTheMonitorsConfiguration)
{
	SetUpContext();
	sMonitor = MonitorRecord();
	sMonitor.configuration["font-size"] = oo::PList(12);

	OO_CHECK_EVAL("console.settings['font-size']", "12");
	OO_CHECK_EVAL("console.settings['missing']", "undefined");

	OO_CHECK_EVAL("console.settings['font-size'] = 14", "14");
	OO_CHECK_EVAL("console.settings['font-face'] = 'Courier'", "Courier");
	OO_CHECK_EVAL("console.settings['gone'] = null", "null");
	// delete of a setting is true and clears it on the monitor: the class's delete hook runs
	// whether or not the object has the property, as SpiderMonkey ran it (upstream's
	// ConsoleSettingsDeleteProperty sent -setConfigurationValue:nil forKey:).
	OO_CHECK_EVAL("delete console.settings['also-gone']", "true");
	OO_CHECK(sMonitor.configurationSets.size() == 4);
	if (sMonitor.configurationSets.size() == 4)
	{
		OO_CHECK(sMonitor.configurationSets[0].first == "font-size" && sMonitor.configurationSets[0].second == oo::PList(14.0));
		OO_CHECK(sMonitor.configurationSets[1].first == "font-face" && sMonitor.configurationSets[1].second == oo::PList(std::string("Courier")));
		OO_CHECK(sMonitor.configurationSets[2].first == "gone" && sMonitor.configurationSets[2].second.isNull());
		OO_CHECK(sMonitor.configurationSets[3].first == "also-gone" && sMonitor.configurationSets[3].second.isNull());
	}

	// A value the engine cannot convert is a warning, not a setting.
	sWarnings.clear();
	OO_CHECK_EVAL("console.settings['f'] = {}", "[object Object]");
	OO_CHECK(sMonitor.configurationSets.size() == 4);
	OO_CHECK(sWarnings.size() == 1);
}


// consoleMessage(colour, message[, location, length]) is a console line; one argument is a
// command result; none is a warning.
OO_TEST(consoleMessage)
{
	SetUpContext();
	sMonitor = MonitorRecord();
	sWarnings.clear();
	OO_CHECK_EVAL("console.consoleMessage('error', 'hello', 1, 3)", "undefined");
	OO_CHECK_EVAL("console.consoleMessage('general', 'plain')", "undefined");
	OO_CHECK_EVAL("console.consoleMessage('only')", "undefined");
	OO_CHECK_EVAL("console.consoleMessage()", "undefined");
	OO_CHECK(sMonitor.lines == (std::vector<std::string>{ "error|hello|1,3", "general|plain|0,0", "command-result|only|0,0" }));
	OO_CHECK(sWarnings.size() == 1);

	// Not the console: an internal error. (It names the native by its C++ signature, a QuickJS
	// native's since the engine is QuickJS-ng's own.)
#if defined(__GNUC__) && !defined(__clang__)
	OO_CHECK_EVAL("console.consoleMessage.call({}, 'x', 'y')", "threw: Expected OODebugMonitor, got (null) in JSValue ConsoleConsoleMessage(JSContext*, JSValue, int, JSValue*). This is an internal error, please report it.");
#else
	OO_CHECK_EVAL("console.consoleMessage.call({}, 'x', 'y')", "threw: Expected OODebugMonitor, got (null) in JSValue ConsoleConsoleMessage(JSContext *, JSValue, int, JSValue *). This is an internal error, please report it.");
#endif
}


// clearConsole(), writeMemoryStats(), writeJSMemoryStats() and writeLogMarker() reach the monitor
// and the log.
OO_TEST(theMonitorsActions)
{
	SetUpContext();
	sMonitor = MonitorRecord();
	OO_CHECK_EVAL("console.clearConsole()", "undefined");
	OO_CHECK_EVAL("console.writeMemoryStats()", "undefined");
	OO_CHECK_EVAL("console.writeJSMemoryStats()", "undefined");
	OO_CHECK_EVAL("console.writeLogMarker()", "undefined");
	OO_CHECK(sMonitor.clears == 1 && sMonitor.memoryDumps == 1 && sMonitor.jsMemoryDumps == 1);
	OO_CHECK(sLogMarkers == 1);
#if defined(__GNUC__) && !defined(__clang__)
	OO_CHECK_EVAL("console.clearConsole.call({})", "threw: Expected OODebugMonitor, got (null) in JSValue ConsoleClearConsole(JSContext*, JSValue, int, JSValue*). This is an internal error, please report it.");
#else
	OO_CHECK_EVAL("console.clearConsole.call({})", "threw: Expected OODebugMonitor, got (null) in JSValue ConsoleClearConsole(JSContext *, JSValue, int, JSValue *). This is an internal error, please report it.");
#endif
}


// The read-write flags: the monitor's dropped-packet flag, the engine's error flags, the
// universe's FPS display and detail level, the context's strict option and the debug flags.
OO_TEST(theFlags)
{
	SetUpContext();
	sMonitor = MonitorRecord();
	OO_CHECK_EVAL("console.ignoreDroppedPackets", "false");
	OO_CHECK_EVAL("console.ignoreDroppedPackets = true", "true");
	OO_CHECK(sMonitor.ignoresDroppedPackets);
	OO_CHECK_EVAL("console.ignoreDroppedPackets", "true");

	OO_CHECK_EVAL("console.__showErrorLocations = true", "true");
	OO_CHECK_EVAL("console.__showErrorLocations", "true");
	OO_CHECK_EVAL("console.__dumpStackForErrors", "false");
	OO_CHECK_EVAL("console.__dumpStackForWarnings = 1", "1");
	OO_CHECK_EVAL("console.__dumpStackForWarnings", "true");

	OO_CHECK_EVAL("console.displayFPS", "false");
	OO_CHECK_EVAL("console.displayFPS = true", "true");
	OO_CHECK_EVAL("console.displayFPS", "true");
	OO_CHECK_EVAL("console.detailLevel", "DETAIL_0");
	OO_CHECK_EVAL("console.detailLevel = 'DETAIL_2'", "DETAIL_2");
	OO_CHECK_EVAL("console.detailLevel", "DETAIL_2");

	OO_CHECK_EVAL("console.pedanticMode = true", "true");
	OO_CHECK_EVAL("console.pedanticMode", "true");
	OO_CHECK_EVAL("console.pedanticMode = false", "false");
	OO_CHECK_EVAL("console.pedanticMode", "false");

#ifndef NDEBUG
	OO_CHECK_EVAL("console.debugFlags = 5", "5");
	OO_CHECK(gDebugFlags == 5);
	OO_CHECK_EVAL("console.debugFlags", "5");
#endif

	OO_CHECK_EVAL("console.platformDescription", "test platform");
}


// The OpenGL answers, from the extension manager.
OO_TEST(theOpenGLAnswers)
{
	OO_CHECK_EVAL("console.maximumDetailLevel", "DETAIL_3");
	OO_CHECK_EVAL("console.glVendorString", "Test Vendor");
	OO_CHECK_EVAL("console.glRendererString", "null");
	OO_CHECK_EVAL("console.glFixedFunctionTextureUnitCount", "4");
	OO_CHECK_EVAL("console.glFragmentShaderTextureUnitCount", "16");
}


// inspectEntity() asks an entity that can be inspected to do so; other values do nothing.
OO_TEST(inspectEntity)
{
	SetUpContext();
	sInspections = 0;
	OO_CHECK_EVAL("console.inspectEntity(true)", "undefined");
	OO_CHECK_EVAL("console.inspectEntity(false)", "undefined");
	OO_CHECK_EVAL("console.inspectEntity(42)", "undefined");
	OO_CHECK(sInspections == 1);
}


// The rest: the script stack, executable JavaScript, the log's message classes, garbage collection.
OO_TEST(theOtherMethods)
{
	OO_CHECK_EVAL("console.scriptStack().length", "0");
	OO_CHECK_EVAL("console.isExecutableJavaScript(this, '1 + 1')", "true");
	// Incomplete input is not executable, as #768 answers it (SpiderMonkey's
	// JS_BufferIsCompilableUnit(); the old QuickJS backend answered true).
	OO_CHECK_EVAL("console.isExecutableJavaScript(this, '1 +')", "false");
	OO_CHECK_EVAL("console.isExecutableJavaScript(this)", "false");
	// (The log is not set up in this process, so it displays nothing.)
	OO_CHECK_EVAL("console.setDisplayMessagesInClass('test.console.class', true)", "undefined");
	OO_CHECK_EVAL("typeof console.displayMessagesInClass('test.console.class')", "boolean");
	OO_CHECK_EVAL("console.displayMessagesInClass()", "false");
	OO_CHECK_EVAL("console.garbageCollect().indexOf('Bytes before: ') === 0", "true");
	OO_CHECK_EVAL("console.noSuchMethod", "undefined");
	OO_CHECK_EVAL("new (Object.getPrototypeOf(console).constructor)()", "threw: unconstructable");
}


// profile(), getProfile() and trace() run a function under the engine's profiler (this file links
// the real one), with "this" the given object or the console's script.
OO_TEST(profiling)
{
	OO_CHECK_EVAL("console.trace(function () { return 7; }, {})", "7");
	OO_CHECK_EVAL("console.trace(function () { return typeof this; })", "object");
	OO_CHECK_EVAL("typeof console.profile(function () {})", "string");
	OO_CHECK_EVAL("console.getProfile(function () {})", "null");	// the profile's property list, which this file's OOJSValueFromPList stand-in gives as null for a dictionary
	OO_CHECK_EVAL("console.profile(42)", "threw: bad arguments: Console.profile (1): ; expected function");
}


OO_TEST_MAIN()
