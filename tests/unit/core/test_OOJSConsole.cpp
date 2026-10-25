/*	test_OOJSConsole.mm
	Unit tests for the debug console's JS binding (src/Core/Debug/OOJSConsole.h/.mm): bead oo-jy98,
	a binding file converted the way amendment oo-ppc converts the OOJS* files, in the Debug module
	of amendment oo-kq7 (proposed ADR-0056).

	It runs the Console and ConsoleSettings classes in a real context on the game's own facade
	backend (ooscript/JSEngine_quickjs.cpp) and links the game's own objects for the binding, the
	engine's exception translator (OOJSEngineNativeWrappers.mm); the console's JS objects hold the
	C++ debug monitor (bead oo-9ht.74 deleted its Objective-C facade, which they held through its
	weak reference). What the rest of the game provides is defined below as the smallest stand-in that
	does the same thing (amendments oo-z1s4 item 4, oo-ppc item 6, oo-ykoy item 4): the C++ debug
	monitor's members (recording what they are asked), the JavaScript engine's flags, the universe's
	detail level and FPS display, the OpenGL extension manager's answers, an entity that can be
	inspected, the script stack, the error reporters and the string and property-list converters.
	It imports neither OOJavaScriptEngine.h nor Universe.h, which would bring in the game classes.
	The expectations were written against the Objective-C file and run on it first (commit
	ea566a254, with an Objective-C stand-in of the extension manager's facade; since the
	conversion the stand-in is the C++ manager's members); they pin the JS-visible behaviour of
	every property and method that compiles in the test flavour.
	Run: bash tools/check-core-tests.sh test_OOJSConsole
*/

#include "OOCocoa.h"
#include "OOJSConsole.h"
#include "OODebugMonitor.h"
#include "OOOpenGLExtensionManager.h"
#include "OOJSEngineCore.h"
#include "OODebugFlags.h"
#include "oofnd/Log.hpp"
#include "oofnd/String.hpp"

#include "oo_test.hpp"

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
#if OOLITE_GNUSTEP
void OODebugMonitor::applicationWillTerminate()  {}
#endif
void OODebugMonitor::jsEngine(OOJavaScriptEngine *, ooscript::Context, ooscript::ErrorReport *, unsigned, bool, const std::string &)  {}
void OODebugMonitor::jsEngine(OOJavaScriptEngine *, ooscript::Context, const std::string &, const std::optional<std::string> &)  {}
// The monitor's JS glue and description (bead oo-9ht.74): its JS value is defined below, with the
// console object it answers.
void OODebugMonitor::clearJSSelf(ooscript::Object)  {}
std::string OODebugMonitor::className() const  { return "OODebugMonitor"; }
std::string OODebugMonitor::description() const  { return "<OODebugMonitor>"; }


// MARK: What the rest of the game provides ---------------------------------------------------------

#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

ooscript::Context gOOJSMainThreadContext = nullptr;

namespace {

std::vector<std::string> sWarnings;
int sLogMarkers = 0;
int sInspections = 0;

}	// namespace


void cxx_OOJSReportErrorWithArguments(ooscript::Context context, const char *format, va_list args)
{
	std::string msg = oo::str::vformat(format, args);
	ooscript::reportError(context, msg.c_str());
}


void cxx_OOJSReportError(ooscript::Context context, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	cxx_OOJSReportErrorWithArguments(context, format, args);
	va_end(args);
}


void cxx_OOJSReportWarning(ooscript::Context /*context*/, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	sWarnings.push_back(oo::str::vformat(format, args));
	va_end(args);
}


void cxx_OOJSReportBadArguments(ooscript::Context context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, unsigned argc, ooscript::Value *, const std::optional<std::string> &message, const std::optional<std::string> &expectedArgsDescription)
{
	cxx_OOJSReportError(context, "bad arguments: %s.%s (%u): %s; expected %s", scriptClass.value_or("").c_str(), function.value_or("").c_str(), argc, message.value_or("").c_str(), expectedArgsDescription.value_or("").c_str());
}


void OOJSReportBadPropertySelector(ooscript::Context context, ooscript::Object, ooscript::PropertyId, ooscript::PropertySpec *)
{
	cxx_OOJSReportError(context, "bad property selector");
}


std::optional<std::string> cxx_OOStringFromJSString(ooscript::Context context, ooscript::String str)
{
	if (str == nullptr)  return std::nullopt;
	std::size_t length = 0;
	const ooscript::Char16 *chars = ooscript::getStringCharsAndLength(context, str, &length);
	std::string result;
	for (std::size_t i = 0; i < length; i++)  result += static_cast<char>(chars[i]);	// the test's strings are ASCII
	return result;
}


std::optional<std::string> cxx_OOStringFromJSValue(ooscript::Context context, ooscript::Value value)
{
	if (ooscript::isNullOrUndefined(value))  return std::nullopt;
	return cxx_OOStringFromJSString(context, ooscript::valueToString(context, value));
}


// Strings, integers, reals and booleans, as the engine converts them; null for anything else.
ooscript::Value OOJSValueFromPList(ooscript::Context context, const oo::PList &plist)
{
	if (const std::string *str = plist.getIf<std::string>())
	{
		ooscript::String js = ooscript::newStringCopyN(context, str->data(), str->size());
		return js != nullptr ? ooscript::stringValue(js) : ooscript::nullValue();
	}
	if (plist.isBool())  return OOJSValueFromBOOL(*plist.getIf<bool>());
	if (plist.isNumber())
	{
		ooscript::Value result = ooscript::nullValue();
		ooscript::newNumberValue(context, plist.doubleValue(), &result);
		return result;
	}
	if (plist.isArray())
	{
		ooscript::Object array = ooscript::newArrayObject(context, 0, nullptr);
		return ooscript::objectValue(array);	// the script stack: its length is what the test reads
	}
	return ooscript::nullValue();
}


oo::PList cxx_OOJSPListFromJSValue(ooscript::Context context, ooscript::Value value)
{
	if (ooscript::isString(value))  return oo::PList(cxx_OOStringFromJSValue(context, value).value_or(""));
	if (ooscript::isBoolean(value))  return oo::PList(ooscript::toBoolean(value));
	double number = 0;
	if (ooscript::isNumber(value) && ooscript::valueToNumber(context, value, &number))  return oo::PList(number);
	return oo::PList();
}


namespace {
ooscript::Object sConsoleObject = nullptr;
}	// namespace


// The monitor's JS value is the console object (as the monitor's jsValueInContext() makes it; the
// stand-in was the engine's OOJSValueFromNativeObject() of the monitor's facade until bead
// oo-9ht.74); undefined before it is made.
ooscript::Value OODebugMonitor::jsValueInContext(ooscript::Context)
{
	if (sConsoleObject != nullptr)  return ooscript::objectValue(sConsoleObject);
	return ooscript::undefinedValue();
}




// The node of a JS object, which the console reads to name what it was given (bead oo-dpyk8: an
// entity's node names its object's class): as above, none in the test wraps a native object.
oo::PList cxx_OOJSPListFromJSObject(ooscript::Context, ooscript::Object)
{
	return oo::PList();
}




void OOJSRegisterObjectConverter(ooscript::ClassDef *, OOJSClassConverterCallback)  {}
oo::PList OOJSBasicPrivateObjectConverter(ooscript::Context, ooscript::Object)  { return oo::PList(); }


bool OOJSUnconstructableConstruct(ooscript::Context context, ooscript::CallArgs &)
{
	cxx_OOJSReportError(context, "unconstructable");
	return false;
}


#ifndef NDEBUG
void OOJSUnreachable(const char *function, const char *, unsigned)
{
	std::printf("unreachable reached in %s\n", function);
	abort();
}
#endif


#ifndef OOJSDumpStack
void OOJSDumpStack(ooscript::Context)  {}	// the profiler's, when a time limit is hit
#endif


std::string OOPlatformDescription(void)  { return "test platform"; }
void OOLogInsertMarker(void)  { sLogMarkers++; }


std::string cxx_OOStringFromGraphicsDetail(OOGraphicsDetail detail)
{
	return "DETAIL_" + std::to_string(static_cast<int>(detail));
}


OOGraphicsDetail cxx_OOGraphicsDetailFromString(const std::string &string)
{
	return (string == "DETAIL_2") ? DETAIL_LEVEL_SHADERS : DETAIL_LEVEL_MINIMUM;
}


// EntityHelpers.mm's (bead oo-dpyk8), which the test does not link: an entity's node (its hold and
// its description) is reached only for an entity, which the test has none of. A null hold releases
// nothing.
class Entity;
namespace oo {
namespace detail { void EntityRelease(Entity *entity) noexcept; }
std::string EntityDescription(Entity *entity);
Entity *WithObject(Entity *entity);
}
void oo::detail::EntityRelease(Entity *entity) noexcept  { if (entity != nullptr)  std::abort(); }
std::string oo::EntityDescription(Entity *)  { std::abort(); }
Entity *oo::WithObject(Entity *entity)  { if (entity != nullptr)  std::abort();  return nullptr; }


// MARK: Debug-flavour link stand-ins (bead oo-iimku) -------------------------------------------------
// OOJSConsole.mm's callObjC() (#if OO_DEBUG) and its diagnostic dumps (#if DEBUG) compile only in
// the debug flavour, which builds this test for Tier C's ASan stage. No case reaches them; a call
// is a test bug.

#if OO_DEBUG
#include "OOShaderUniformMethodType.h"

class Entity;

std::optional<std::string> cxx_OOStringFromJSValueEvenIfNull(ooscript::Context, ooscript::Value)  { std::abort(); }
std::optional<std::string> OOJSEntityJSClassName(Entity *)  { std::abort(); }
bool OOJSCallEntityMethod(ooscript::Context, Entity *, const std::string &, unsigned, ooscript::Value *, ooscript::Value *)  { std::abort(); }
OOShaderUniformType OOShaderUniformTypeFromEncoding(const char *)  { std::abort(); }
// oo::EntityIn() (Entity+ObjCBridge.h) reads ::TestEntityObject's _cxxEntity ivar; its offset variable is
// emitted by the @implementation in Entity+ObjCBridge.mm, which this test does not link. The name
// is the one clang gives it: the ivar's type encoding, with its '=' written as byte 2.
extern "C" int gOOTestEntityCxxEntityIvarOffset __asm__("__objc_ivar_offset_Entity._cxxEntity.{Ref<Entity>\002^{Entity}}");
int gOOTestEntityCxxEntityIvarOffset = 0;
#endif

#if DEBUG
#include "ResourceManager.h"

std::string cxx_OOJSDescribeValue(ooscript::Context, ooscript::Value, BOOL)  { std::abort(); }
std::optional<std::string> ResourceManager::diagnosticFileLocation()  { std::abort(); }
#endif


// The engine (OOJavaScriptEngine.h; a C++ class since bead oo-wdqw1 deleted its facade), declared
// with the header's names and signatures but not its class; the stand-in's answers are kept.
class OOJavaScriptEngine
{
public:
	static OOJavaScriptEngine *sharedEngine();
	ooscript::Object globalObject();
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

ooscript::Object OOJavaScriptEngine::globalObject()  { return ooscript::getGlobalObject(gOOJSMainThreadContext); }
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
OOGraphicsDetail OOOpenGLExtensionManager::maximumDetailLevel()  { return DETAIL_LEVEL_MAXIMUM; }
std::optional<std::string> OOOpenGLExtensionManager::vendorString()  { return std::string("Test Vendor"); }
std::optional<std::string> OOOpenGLExtensionManager::rendererString()  { return std::nullopt; }
GLint OOOpenGLExtensionManager::textureUnitCount()  { return 4; }
GLint OOOpenGLExtensionManager::textureImageUnitCount()  { return 16; }


// The universe as the code under test sees it: a stand-in for the C++ class (bead oo-ql9rn deleted
// the Objective-C facade the test's FakeUniverse stood in for), with the header's names and signatures.
class Universe
{
public:
	OOGraphicsDetail _detailLevel;
	BOOL _displayFPS;

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
Universe *gSharedUniverse = nil;


// An entity, as the console's inspectEntity() sees it: one answers -inspect (the Mac debug OXP's
// inspector), one does not. C++ since bead oo-4aq6a.11 (rooted on the Objective-C root class
// OOObject, which Phase 4 deletes, until then): answersInspect() is what -respondsToSelector: of
// -inspect answered.
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


// Each entity's C++ part (bead oo-9ht.39.3: an entity's JS object holds it, JSValueToEntity() answers
// it and TestObjectOf its object, which the console asks to -inspect). Kept for the life of the test.
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
// (OOJSEntity.h declares it with C linkage.)
extern "C" BOOL JSValueToEntity(ooscript::Context, ooscript::Value value, Entity **outEntity);
BOOL JSValueToEntity(ooscript::Context, ooscript::Value value, Entity **outEntity)
{
	if (!ooscript::isBoolean(value))  return NO;
	*outEntity = ooscript::toBoolean(value) ? InspectablePart() : PlainPart();
	return YES;
}


// oo::ToObjC (Entity+ObjCBridge.mm) until bead oo-4aq6a.11: each C++ part's entity, null for any other.
::TestEntityObject *TestObjectOf(Entity *entity)
{
	if (entity == InspectablePart())  return sInspectableEntity;
	if (entity == PlainPart())  return sPlainEntity;
	return nullptr;
}

// EntityHelpers.mm's oo::InspectEntity() (bead oo-dpyk8), as the console asked the object until then:
// -inspect, if the entity's object answers it.
namespace oo { void InspectEntity(Entity *entity); }
void oo::InspectEntity(Entity *entity)
{
	::TestEntityObject *object = TestObjectOf(entity);
	if (object != nullptr && object->answersInspect())  object->inspect();
}


#include "OOScript.h"


// OOJSScript (OOJSScript.h), which the code under test calls. Since bead oo-9ht.133 deleted the
// OOScript root's facade (a script's object since bead oo-9ht.137) a script is the C++ object, so
// the stand-in is a C++ subclass of OOScript declaring the members that code calls.
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

ooscript::Runtime sRuntime;
ooscript::Context sContext;
ooscript::Object sGlobal;


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = ooscript::newRuntime(8u * 1024u * 1024u);
	sContext = ooscript::newContext(sRuntime, 8192);
	gOOJSMainThreadContext = sContext;
	ooscript::beginRequest(sContext);
	sGlobal = ooscript::getGlobalObject(sContext);
	ooscript::initStandardClasses(sContext, sGlobal);
	gSharedUniverse = new FakeUniverse();
	sPlainEntity = oo::makeRef<TestEntityObject>().leakRef();
	sInspectableEntity = oo::makeRef<InspectableEntity>().leakRef();

	sConsoleObject = DebugMonitorToJSConsole(sContext, OODebugMonitor::sharedDebugMonitor());
	ooscript::Value value = ooscript::objectValue(sConsoleObject);
	ooscript::setProperty(sContext, sGlobal, "console", &value);
}


// Evaluates src and gives its result as a string ("undefined", "null", ...), or "threw: <message>".
std::string Eval(const char *src)
{
	SetUpContext();
	std::string wrapped = std::string("(function () { try { return String(") + src + "); } catch (e) { return 'threw: ' + (e && e.message !== undefined ? e.message : e); } })()";
	ooscript::Value result = ooscript::undefinedValue();
	if (!ooscript::evaluateScript(sContext, sGlobal, wrapped.c_str(), static_cast<unsigned>(wrapped.size()), "test.js", 1, &result))
	{
		ooscript::clearPendingException(sContext);
		return "<evaluation failed>";
	}
	return cxx_OOStringFromJSValue(sContext, result).value_or("<not a string>");
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
	OO_CHECK_EVAL("console.DEBUG_LINKED_LISTS", std::to_string(DEBUG_LINKED_LISTS).c_str());
	OO_CHECK_EVAL("console.DEBUG_SHADER_VALIDATION", std::to_string(DEBUG_SHADER_VALIDATION).c_str());
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
	// delete of a setting is true, but the backend does not call the class's delete hook for a
	// property the object does not have, so the monitor is not told.
	OO_CHECK_EVAL("delete console.settings['also-gone']", "true");
	OO_CHECK(sMonitor.configurationSets.size() == 3);
	if (sMonitor.configurationSets.size() == 3)
	{
		OO_CHECK(sMonitor.configurationSets[0].first == "font-size" && sMonitor.configurationSets[0].second == oo::PList(14.0));
		OO_CHECK(sMonitor.configurationSets[1].first == "font-face" && sMonitor.configurationSets[1].second == oo::PList(std::string("Courier")));
		OO_CHECK(sMonitor.configurationSets[2].first == "gone" && sMonitor.configurationSets[2].second.isNull());
	}

	// A value the engine cannot convert is a warning, not a setting.
	sWarnings.clear();
	OO_CHECK_EVAL("console.settings['f'] = {}", "[object Object]");
	OO_CHECK(sMonitor.configurationSets.size() == 3);
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

	// Not the console: an internal error.
#if defined(__GNUC__) && !defined(__clang__)
	OO_CHECK_EVAL("console.consoleMessage.call({}, 'x', 'y')", "threw: Expected OODebugMonitor, got (null) in bool ConsoleConsoleMessage(ooscript::Context, ooscript::CallArgs&). This is an internal error, please report it.");
#else
	OO_CHECK_EVAL("console.consoleMessage.call({}, 'x', 'y')", "threw: Expected OODebugMonitor, got (null) in bool ConsoleConsoleMessage(ooscript::Context, ooscript::CallArgs &). This is an internal error, please report it.");
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
	OO_CHECK_EVAL("console.clearConsole.call({})", "threw: Expected OODebugMonitor, got (null) in bool ConsoleClearConsole(ooscript::Context, ooscript::CallArgs&). This is an internal error, please report it.");
#else
	OO_CHECK_EVAL("console.clearConsole.call({})", "threw: Expected OODebugMonitor, got (null) in bool ConsoleClearConsole(ooscript::Context, ooscript::CallArgs &). This is an internal error, please report it.");
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
	OO_CHECK_EVAL("console.isExecutableJavaScript(this, '1 +')", "true");	// the backend's answer for incomplete input
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
