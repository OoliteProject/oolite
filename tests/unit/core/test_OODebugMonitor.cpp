/*	test_OODebugMonitor.mm
	Unit tests for OODebugMonitor (src/Core/Debug/OODebugMonitor.h).

	OODebugMonitor is the singleton that connects a debugger (the TCP console client the integration
	tests drive the game through) to the game: it keeps the debug configuration (the OXPs'
	debugConfig.plist under the user's overrides, normalised), relays the JavaScript console to the
	debugger, is the JavaScript engine's monitor (errors, warnings and log lines), serves source
	lines to the console, and dumps memory statistics.

	The classes and functions the monitor reaches would bring the whole game into the link, so they
	are this file's stand-ins, answering only what the monitor asks and recording it: the resource
	manager (the OXPs' configuration and the console script's path), the JavaScript engine (the
	monitor it is given), OOJSScript (the console script it makes, and the command it is asked to
	run), the console's JS wrapper, the time limiter, the universe and the player (no entities),
	the texture registry (none). The JS context is a real one (QuickJS-ng), for the heap statistics
	and the wrapper object. The user's defaults are a scratch folder's (HOMEPATH). The monitor is a
	singleton, so the tests run in order on one monitor.
	Run: tests/run.sh unit
*/

#include "OODebugMonitor.h"
#include "OOColor.h"
#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#include "OODescription.h"
#include "OOEntityHold.h"	// the universe's entity list holds C++ entities

#include "oofnd/Defaults.hpp"
#include "oofnd/FileSystem.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/Notification.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOException.h"
#include "oo_test.hpp"

#include <climits>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <process.h>
#include <string>
#include <string_view>
#include <vector>

namespace stdfs = std::filesystem;


// MARK: What the rest of the game provides ---------------------------------------------------------

namespace {

// Bool nodes. (OOCocoa.h defines true and false as 1 and 0, which would make Integer nodes.)
const bool kTrue = (1 == 1), kFalse = (1 == 0);

stdfs::path sRoot;
oo::PList sOXPConfig;						// what debugConfig.plist merges to
std::optional<std::string> sConsoleScriptPath;	// where oolite-debug-console.js is
int sConsoleScriptsMade = 0;
oo::PList sConsoleScriptProperties;
int sConsoleCommands = 0;
oo::PList sLastJSValuePList;
int sTimeLimiterStarts = 0, sTimeLimiterStops = 0, sTimeLimiterPauses = 0, sTimeLimiterResumes = 0;
int sConsoleWrappersMade = 0;
std::vector<std::string> sDefinedGlobals;

}	// namespace


// Main.mm's globals, and the universe's and the player's (none: no entities, no wormholes).
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif
uint32_t gLiveEntityCount = 0;

// WormholeEntity.mm's: the monitor's dump asks it through this function. The
// test dumps no entity.
class Entity;
oo::PList WormholeEntityShipsInTransit(Entity *)  { return oo::PList(); }

// UNIVERSE stays nil here, so the monitor's guarded call never reaches it; the
// stand-in only links it.
class Universe
{
public:
	std::vector<oo::EntityHold> entityList();	// held C++ entities
};
std::vector<oo::EntityHold> Universe::entityList()  { return {}; }

Universe *gSharedUniverse = nullptr;

// What the monitor's entity dump links against (a ship's object, the root's,
// holds its C++ part, which oo::ToCxx reads), declared as Entity.h and
// ShipEntity.h declare them (the test imports neither). The test dumps no
// entity, so none is reached.
class Entity : public oo::RefCounted
{
public:
	virtual ~Entity();
	bool getIsShip();
	bool getIsPlayer();
	bool getIsWormhole();
};

class TestEntityObject final : public oo::RefCounted
{
public:
	const char *className() const  { return "Entity"; }

	oo::Ref<Entity> _cxxEntity;
};

class ShipEntity : public Entity
{
public:
	std::vector<oo::EntityHold> subEntityEnumerator();
};

Entity::~Entity() = default;
bool Entity::getIsShip()  { std::abort(); }
bool Entity::getIsPlayer()  { std::abort(); }
bool Entity::getIsWormhole()  { std::abort(); }
std::vector<oo::EntityHold> ShipEntity::subEntityEnumerator()  { std::abort(); }
::TestEntityObject *TestObjectOf(Entity *)  { std::abort(); }
#define OO_ENTITY_HELPERS_STAND_IN_CXX
#include "EntityHelpersStandIn.h"	// EntityHelpers.mm's, on the test's objects: never reached either

// PLAYER: the members the monitor calls on it (declared as PlayerEntity.h
// declares them; the test imports no game header that defines the class). The
// test has no player, so none is reached.
class PlayerEntity
{
public:
	std::size_t dialMaxMissiles();
	::ShipEntity *missileForPylon(std::size_t value);
	std::vector<oo::EntityHold> getScannedWormholes();
};

std::size_t PlayerEntity::dialMaxMissiles()  { std::abort(); }
::ShipEntity *PlayerEntity::missileForPylon(std::size_t /*value*/)  { std::abort(); }
std::vector<oo::EntityHold> PlayerEntity::getScannedWormholes()  { return {}; }	// no wormholes (the memory statistics' stand-in player asks)

PlayerEntity *gOOPlayer = nullptr;

JSContext *gOOJSMainThreadContext = nullptr;

extern const char * const kOOJavaScriptEngineWillResetNotificationName;
extern const char * const kOOJavaScriptEngineDidResetNotificationName;
const char * const kOOJavaScriptEngineWillResetNotificationName = "org.aegidian.oolite OOJavaScriptEngine will reset";
const char * const kOOJavaScriptEngineDidResetNotificationName = "org.aegidian.oolite OOJavaScriptEngine did reset";


#include "ResourceManager.h"

// C++ definitions of the ResourceManager statics the code under test calls,
// with the stand-in's answers.
oo::PList ResourceManager::dictionaryFromFilesNamed(const std::string &fileName, const std::optional<std::string> &folderName, bool mergeFiles)
{
	if (fileName == "debugConfig.plist" && folderName == "Config" && mergeFiles)  return sOXPConfig;
	return oo::PList();
}


std::optional<std::string> ResourceManager::pathForFileNamed(const std::string &fileName, const std::optional<std::string> &folderName)
{
	if (fileName == "oolite-debug-console.js" && folderName == "Scripts")  return sConsoleScriptPath;
	return std::nullopt;
}



// The engine and the one null (OOJavaScriptEngine.h), declared with the
// header's names and signatures but not their classes; the null is its own
// property-list node's foreign object, as in the game.
class OOJavaScriptEngine
{
public:
	static OOJavaScriptEngine *sharedEngine();
	void setMonitor(OOJavaScriptEngineMonitor *monitor);
	JSValueConst globalObject();

	OOJavaScriptEngineMonitor	*_monitor = nullptr;	// the C++ monitor interface
	JSValue						_global = JS_UNDEFINED;	// owned
};

OOJavaScriptEngine *OOJavaScriptEngine::sharedEngine()
{
	static OOJavaScriptEngine *engine = new OOJavaScriptEngine;
	return engine;
}


void OOJavaScriptEngine::setMonitor(OOJavaScriptEngineMonitor *monitor)
{
	_monitor = monitor;
}


// Borrowed, as the engine's.
JSValueConst OOJavaScriptEngine::globalObject()
{
	if (!JS_IsObject(_global))  _global = JS_GetGlobalObject(gOOJSMainThreadContext);
	return _global;
}


class OONull : public oo::PListForeign
{
public:
	static OONull *null();
	std::string className() const override;
	std::string description() const override;
};

OONull *OONull::null()
{
	static OONull *sNull = oo::makeRef<OONull>().leakRef();
	return sNull;
}

std::string OONull::className() const	{ return "OONull"; }
std::string OONull::description() const	{ return "<null>"; }



#include "OOScript.h"
#include "OOTexture.h"


// OOJSScript (OOJSScript.h), which the code under test calls. The stand-in is a
// C++ subclass of OOScript declaring the members that code calls. The console
// script: made from its path with the console as a property; runs commands.
class OOJSScript : public OOScript
{
public:
	static oo::Ref<OOJSScript> scriptWithPath(const std::optional<std::string> &path, const oo::PList &properties);
	static OOJSScript *currentlyRunningScript();

	bool callMethod(JSAtom methodID, JSContext *context, JSValueConst *argv, int argc, JSValue *outResult) override
	{
		(void)methodID; (void)context; (void)argv; (void)outResult;
		if (argc == 1)  sConsoleCommands++;
		return true;
	}
};

// OOScript's virtual members (OOScript.mm reaches the whole game), for the test's scripts' vtable.
std::optional<std::string> OOScript::descriptionComponents()	{ return std::nullopt; }
std::optional<std::string> OOScript::name()					{ return std::nullopt; }
std::optional<std::string> OOScript::scriptDescription()		{ return std::nullopt; }
std::optional<std::string> OOScript::version()				{ return std::nullopt; }
bool OOScript::requiresTickle()								{ return false; }
void OOScript::runWithTarget(Entity *)						{}
bool OOScript::callMethod(JSAtom, JSContext *, JSValueConst *, int, JSValue *)	{ return false; }
std::string OOScript::className() const						{ return "OOScript"; }
std::string OOScript::description() const						{ return "<OOScript>"; }
JSValue OOScript::jsValueInContext(JSContext *)				{ return JS_UNDEFINED; }
void OOScript::clearJSSelf(JSValueConst)						{}
std::optional<std::string> OOScript::displayName()			{ return "test script"; }

oo::Ref<OOJSScript> OOJSScript::scriptWithPath(const std::optional<std::string> &path, const oo::PList &properties)
{
	(void)path;
	sConsoleScriptsMade++;
	sConsoleScriptProperties = properties;
	return oo::makeRef<OOJSScript>();
}
OOJSScript *OOJSScript::currentlyRunningScript()
{
	return nullptr;
}


#include "OOJSEngineCore.h"	// OOJSValue complete: GCC instantiates ~Ref<OOJSValue> where a Ref is returned

// The special-functions object (OOJSSpecialFunctions.h): none, as the stand-in gave (nil).
JSValue JSSpecialFunctionsObjectWrapper(JSContext *context)
{
	(void)context;
	return JS_UNDEFINED;
}


// A held JS value (OOJSEngineCore.h): the special-functions object's wrapper, which the monitor
// makes only for an object (never here).
oo::Ref<OOJSValue> OOJSValue::valueWithJSValue(JSValueConst, JSContext *)	{ std::abort(); }
OOJSValue::~OOJSValue()										{}
std::string OOJSValue::className() const						{ return "OOJSValue"; }
std::string OOJSValue::description() const					{ return "<OOJSValue>"; }


// The console's JS object: a plain object (OOJSConsole.mm gives it the Console class), owned by
// the caller.
JSValue DebugMonitorToJSConsole(JSContext *context, OODebugMonitor *monitor)
{
	(void)monitor;
	sConsoleWrappersMade++;
	return JS_NewObject(context);
}


JSValue OOJSValueFromPList(JSContext *context, const oo::PList &plist)
{
	(void)context;
	sLastJSValuePList = plist;
	return JS_UNDEFINED;
}


JSAtom OOJSInternAtomPRIVATE(const char *name)
{
	(void)name;
	return JS_ATOM_NULL;
}


void OOJSStartTimeLimiterWithTimeLimit(double limit)		{ (void)limit; sTimeLimiterStarts++; }
void OOJSStopTimeLimiter(void)								{ sTimeLimiterStops++; }
void OOJSPauseTimeLimiter(void)								{ sTimeLimiterPauses++; }
void OOJSResumeTimeLimiter(void)							{ sTimeLimiterResumes++; }


// The source files the console shows: plain files (OODataFromOXZFile reads through an .oxz too).
std::optional<oo::Data> OODataFromOXZFile(const std::string &path)
{
	const oo::fs::Result<oo::Data> data = oo::fs::readFile(oo::fs::pathFromUTF8(path));
	if (!data.has_value())  return std::nullopt;
	return *data;
}


// No textures, so the memory dump lists none; and no entity class is ever an
// entity. The C++ OOTexture's static members, and the member the dump calls on
// each texture (there are none: never reached).
std::vector<oo::Ref<OOTexture>> OOTexture::cachedTexturesByAge()	{ return {}; }
std::vector<oo::Ref<OOTexture>> OOTexture::allTextures()			{ return {}; }
size_t OOTexture::dataSize()	{ std::abort(); }


// An entity with a drawable: the member the monitor's entity dump calls
// (declared as OOEntityWithDrawable.h declares it). The test dumps no entity,
// so none is reached.
class OODrawable;
class OOEntityWithDrawable : public Entity
{
public:
	OODrawable *getDrawable();
};

OODrawable *OOEntityWithDrawable::getDrawable()  { std::abort(); }


// MARK: The debugger
// -------------------------------------------------------------------------------

// Records what the monitor sends it. Refuses to connect, or raises, when told
// to. A C++ OODebuggerInterface.
namespace {

// The records (the Objective-C class's @public ivars).
struct TestDebuggerRecord : public OODebuggerInterface
{
	bool						_refuse = false;
	bool						_raise = false;
	int							_connects = 0;
	std::vector<std::string>	_disconnects;	// the messages ("(none)" for nullopt)
	std::vector<std::string>	_output;		// "colorKey|text|location,length"
	int							_clears = 0;
	int							_shows = 0;
	oo::PList					_configuration;
	std::vector<std::string>	_changes;		// "key=<description>"
};


class TestDebugger : public TestDebuggerRecord
{
public:
	bool connectDebugMonitor(OODebugMonitor *debugMonitor, std::optional<std::string> *message) override
	{
		(void)debugMonitor;
		_connects++;
		if (_raise)  OORaiseException("TestException", "%s", "no thanks");
		if (_refuse)
		{
			*message = "refused";
			return false;
		}
		return true;
	}


	void disconnectDebugMonitor(OODebugMonitor *debugMonitor, const std::optional<std::string> &message) override
	{
		(void)debugMonitor;
		_disconnects.push_back(message.value_or("(none)"));
	}


	void debugMonitor(OODebugMonitor *debugMonitor,
					  const std::string &output,
					  const std::optional<std::string> &colorKey,
					  NSRange emphasisRange) override
	{
		(void)debugMonitor;
		_output.push_back(oo::str::format("%s|%s|%lu,%lu", colorKey.value_or("(none)").c_str(), output.c_str(), (unsigned long)emphasisRange.location, (unsigned long)emphasisRange.length));
	}


	void debugMonitorClearConsole(OODebugMonitor *debugMonitor) override	{ (void)debugMonitor; _clears++; }
	void debugMonitorShowConsole(OODebugMonitor *debugMonitor) override	{ (void)debugMonitor; _shows++; }


	void debugMonitor(OODebugMonitor *debugMonitor, const oo::PList &configuration) override
	{
		(void)debugMonitor;
		_configuration = configuration;
	}


	void debugMonitor(OODebugMonitor *debugMonitor, const oo::PList &newValue, const std::string &key) override
	{
		(void)debugMonitor;
		const oo::PList::Integer *integer = newValue.getIf<oo::PList::Integer>();
		_changes.push_back(key + "=" + (newValue.isNull() ? std::string("(null)") : integer != nullptr ? std::to_string(integer->value) : std::string("(value)")));
	}


	std::string description() const override	{ return oo::str::format("<TestDebugger %s>", oo::str::pointerDescription(this).c_str()); }
};

}	// namespace


// MARK: Helpers ------------------------------------------------------------------------------------

namespace {

// The scratch home and the OXPs' configuration, before the monitor exists.
void SetUp()
{
	if (!sRoot.empty())  return;
	sRoot = stdfs::temp_directory_path() / ("oo-test-debugmonitor-" + std::to_string(static_cast<unsigned long>(::_getpid())));
	stdfs::remove_all(sRoot);
	stdfs::create_directories(sRoot);
	OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
	stdfs::current_path(sRoot);

	gOOJSMainThreadContext = JS_NewContext(JS_NewRuntime());

	oo::PList::Dict oxp;
	oxp.emplace("console-host", oo::PList("127.0.0.1"));
	oxp.emplace("font-size", oo::PList(12));
	oxp.emplace("Big-number", oo::PList("42"));
	oxp.emplace("real-number", oo::PList(2.75));
	oxp.emplace("show-console-on-warning", oo::PList("yes"));
	oxp.emplace("show-console-on-log", oo::PList(kFalse));
	oxp.emplace("error-fg-color", oo::PList("redColor"));
	oxp.emplace("bogus-color", oo::PList("not a colour"));
	oxp.emplace("hidden", oo::PList(oo::PList::Object(oo::Ref<oo::PListForeign>(OONull::null()))));	// [OONull null]
	sOXPConfig = oo::PList(std::move(oxp));

	oo::PList::Dict overrides;
	overrides.emplace("font-size", oo::PList(14));
	overrides.emplace("log-fg-colour", oo::PList(oo::PList::Array{ oo::PList(0.0), oo::PList(1.0), oo::PList(0.0) }));
	oo::Defaults::standard().setObject("debug-settings-override", oo::PList(std::move(overrides)));

	sConsoleScriptPath = (sRoot / "oolite-debug-console.js").generic_string();
}


oo::PList RGBA(float r, float g, float b, float a)
{
	return oo::PList(oo::PList::Array{ oo::PList::singleReal(r), oo::PList::singleReal(g), oo::PList::singleReal(b), oo::PList::singleReal(a) });
}


std::string WriteSource(const std::string &name, const std::string &text)
{
	const stdfs::path path = sRoot / name;
	std::ofstream(path, std::ios::binary) << text;
	return path.generic_string();
}


// The log, as the monitor writes it.
std::vector<std::string> gLog;


void Capture(std::string_view line)
{
	gLog.emplace_back(line);
}


void StartLog()
{
	oo::log::logger().setInitialized(true);
	oo::log::logger().setSink(&Capture);
	gLog.clear();
}


int LogLinesContaining(std::string_view text)
{
	int count = 0;
	for (const std::string &line : gLog)
	{
		if (line.find(text) != std::string::npos)  count++;
	}
	return count;
}


TestDebugger *NewDebugger()
{
	// Kept for the rest of the run (the Objective-C debugger lived until its test's pool drained).
	static std::vector<oo::Ref<TestDebugger>> debuggers;
	debuggers.push_back(oo::makeRef<TestDebugger>());
	return debuggers.back().get();
}

}	// namespace


// MARK: Tests --------------------------------------------------------------------------------------

// First: making the monitor registers it with the engine, makes the console script and observes
// the engine's resets.
OO_TEST(sharedMonitorIsSetUpOnce)
{
	SetUp();
	{
		oo::AutoreleaseScope pool;
		OODebugMonitor *monitor = OODebugMonitor::sharedDebugMonitor();
		OO_CHECK(monitor != nullptr);
		OO_CHECK(OODebugMonitor::sharedDebugMonitor() == monitor);
		OO_CHECK(OOJavaScriptEngine::sharedEngine()->_monitor == static_cast<OOJavaScriptEngineMonitor *>(monitor));

		OO_CHECK(sConsoleScriptsMade == 1);
		// The console property is an Object node of the monitor itself.
		const oo::PList *console = sConsoleScriptProperties.find("console");
		const oo::PList::Object *consoleNode = (console != nullptr) ? console->getIf<oo::PList::Object>() : nullptr;
		OO_CHECK(consoleNode != nullptr && consoleNode->get() == monitor);
		OO_CHECK(sConsoleScriptProperties.find("special") == nullptr);	// no special-functions object
		OO_CHECK(sConsoleWrappersMade == 0);	// a script exists, so no global debugConsole

		OO_CHECK(!monitor->debuggerConnected());
		OO_CHECK(!monitor->TCPIgnoresDroppedPackets() && !monitor->usingPlugInController());
	}
}


// The OXPs' configuration under the user's overrides, normalised: colours become RGBA arrays (an
// unreadable colour is dropped), "show-console..." values booleans, and a null hides a value.
OO_TEST(configurationIsNormalisedAndOverridden)
{
	SetUp();
	OODebugMonitor *monitor = OODebugMonitor::sharedDebugMonitor();

	OO_CHECK(monitor->configurationValueForKey("console-host") == oo::PList("127.0.0.1"));
	OO_CHECK(monitor->configurationValueForKey("font-size") == oo::PList(14));	// the override
	OO_CHECK(monitor->configurationValueForKey("show-console-on-warning") == oo::PList(kTrue));
	OO_CHECK(monitor->configurationValueForKey("show-console-on-log") == oo::PList(kFalse));
	OO_CHECK(monitor->configurationValueForKey("error-fg-color") == RGBA(1.0f, 0.0f, 0.0f, 1.0f));
	OO_CHECK(monitor->configurationValueForKey("log-fg-colour") == RGBA(0.0f, 1.0f, 0.0f, 1.0f));
	OO_CHECK(monitor->configurationValueForKey("bogus-color").isNull());
	OO_CHECK(monitor->configurationValueForKey("hidden").isNull());
	OO_CHECK(monitor->configurationValueForKey("no-such-key").isNull());

	OO_CHECK(monitor->configurationIntValueForKey("font-size", -1) == 14);
	OO_CHECK(monitor->configurationIntValueForKey("Big-number", -1) == 42);
	OO_CHECK(monitor->configurationIntValueForKey("real-number", -1) == 2);
	OO_CHECK(monitor->configurationIntValueForKey("show-console-on-warning", -1) == 1);
	OO_CHECK(monitor->configurationIntValueForKey("error-fg-color", -1) == -1);
	OO_CHECK(monitor->configurationIntValueForKey("no-such-key", 7) == 7);

	// Every key of both, sorted without regard to case.
	// (The unreadable colour was dropped when the OXPs' configuration was normalised.)
	const std::vector<std::string> expected = { "Big-number", "console-host", "error-fg-color", "font-size", "hidden",
												"log-fg-colour", "real-number", "show-console-on-log", "show-console-on-warning" };
	OO_CHECK(monitor->configurationKeys() == expected);
}


// A debugger connects, is told the merged configuration, and receives the console.
OO_TEST(debuggerConnectsAndReceivesTheConsole)
{
	SetUp();
	StartLog();
	{
		oo::AutoreleaseScope pool;
		OODebugMonitor *monitor = OODebugMonitor::sharedDebugMonitor();
		TestDebugger *debugger = NewDebugger();
		OO_CHECK(monitor->setDebugger(debugger));
		OO_CHECK(monitor->debuggerConnected());
		OO_CHECK(debugger->_connects == 1);
		OO_CHECK(debugger->_configuration.find("font-size") != nullptr && *debugger->_configuration.find("font-size") == oo::PList(14));
		OO_CHECK(debugger->_configuration.find("console-host") != nullptr);
		OO_CHECK(debugger->_configuration.find("bogus-color") == nullptr);
		OO_CHECK(monitor->setDebugger(debugger));	// the same one again: nothing happens
		OO_CHECK(debugger->_connects == 1 && debugger->_disconnects.empty());

		const int pauses = sTimeLimiterPauses, resumes = sTimeLimiterResumes;
		monitor->appendJSConsoleLine("hello", std::string("log"), NSMakeRange(1, 2));
		monitor->appendJSConsoleLine("plain", std::nullopt);
		monitor->clearJSConsole();
		monitor->showJSConsole();
		OO_CHECK(debugger->_output.size() == 2);
		OO_CHECK(debugger->_output.size() == 2 && debugger->_output[0] == "log|hello|1,2" && debugger->_output[1] == "(none)|plain|0,0");
		OO_CHECK(debugger->_clears == 1 && debugger->_shows == 1);
		OO_CHECK(sTimeLimiterPauses == pauses + 4 && sTimeLimiterResumes == resumes + 4);

		// A configuration change is normalised, kept as an override and sent to the debugger;
		// setting null removes the override and sends what is left (the OXPs' value).
		monitor->setConfigurationValue(oo::PList("blueColor"), "console-fg-color");
		OO_CHECK(monitor->configurationValueForKey("console-fg-color") == RGBA(0.0f, 0.0f, 1.0f, 1.0f));
		monitor->setConfigurationValue(oo::PList(20), "font-size");
		monitor->setConfigurationValue(oo::PList(), "font-size");
		OO_CHECK(monitor->configurationValueForKey("font-size") == oo::PList(12));
		monitor->setConfigurationValue(oo::PList(1), "");	// ignored
		OO_CHECK(debugger->_changes.size() == 3);
		OO_CHECK(debugger->_changes.size() == 3 && debugger->_changes[0] == "console-fg-color=(value)" && debugger->_changes[1] == "font-size=20" && debugger->_changes[2] == "font-size=12");

		// Another debugger's disconnection is ignored; this one's is passed on.
		monitor->disconnectDebugger(NewDebugger(), std::string("not you"));
		OO_CHECK(LogLinesContaining("which is not current debugger; ignoring.") == 1);
		OO_CHECK(monitor->debuggerConnected());
		monitor->disconnectDebugger(nullptr, std::string("nobody"));
		monitor->disconnectDebugger(debugger, std::string("bye"));
		OO_CHECK(!monitor->debuggerConnected());
		OO_CHECK(debugger->_disconnects.size() == 1 && debugger->_disconnects[0] == "bye");
		monitor->showJSConsole();	// no debugger: nothing
		OO_CHECK(debugger->_shows == 1);
	}
}


OO_TEST(debuggersThatRefuseOrRaise)
{
	SetUp();
	StartLog();
	{
		oo::AutoreleaseScope pool;
		OODebugMonitor *monitor = OODebugMonitor::sharedDebugMonitor();
		TestDebugger *first = NewDebugger();
		OO_CHECK(monitor->setDebugger(first));

		// A new debugger disconnects the old one first, even if it then fails.
		TestDebugger *refusing = NewDebugger();
		refusing->_refuse = true;
		OO_CHECK(!monitor->setDebugger(refusing));
		OO_CHECK(first->_disconnects.size() == 1 && first->_disconnects[0] == "New debugger set.");
		OO_CHECK(!monitor->debuggerConnected());
		OO_CHECK(LogLinesContaining("because an error occurred: refused") == 1);

		TestDebugger *raising = NewDebugger();
		raising->_raise = true;
		OO_CHECK(!monitor->setDebugger(raising));
		OO_CHECK(LogLinesContaining("because an exception occurred: TestException -- no thanks") == 1);

		TestDebugger *second = NewDebugger();
		OO_CHECK(monitor->setDebugger(second));
		OO_CHECK(monitor->setDebugger(nullptr));
		OO_CHECK(second->_disconnects.size() == 1 && second->_disconnects[0] == "Debugger disconnected programatically.");
	}
}


// The console's commands go to the console script, under the long time limit.
OO_TEST(consoleCommandsRunInTheScript)
{
	SetUp();
	OODebugMonitor *monitor = OODebugMonitor::sharedDebugMonitor();
	const int commands = sConsoleCommands, starts = sTimeLimiterStarts, stops = sTimeLimiterStops;
	monitor->performJSConsoleCommand("1 + 1");
	OO_CHECK(sConsoleCommands == commands + 1);
	OO_CHECK(sLastJSValuePList == oo::PList("1 + 1"));
	OO_CHECK(sTimeLimiterStarts == starts + 1 && sTimeLimiterStops == stops + 1);
}


OO_TEST(sourceLinesAreServedAndCached)
{
	SetUp();
	OODebugMonitor *monitor = OODebugMonitor::sharedDebugMonitor();
	const std::string path = WriteSource("source.js", "first\nsecond\nthird");
	OO_CHECK(monitor->sourceCodeForFile(path, 2) == "second");
	OO_CHECK(monitor->sourceCodeForFile(path, 3) == "third");
	OO_CHECK(monitor->sourceCodeForFile(path, 0) == "<line out of range!>");
	OO_CHECK(monitor->sourceCodeForFile(path, 4) == "<line out of range!>");

	WriteSource("source.js", "changed\n");
	OO_CHECK(monitor->sourceCodeForFile(path, 1) == "first");	// read once

	const std::string missing = (sRoot / "missing.js").generic_string();
	OO_CHECK(monitor->sourceCodeForFile(missing, 1) == "<Can't load file " + missing + ">");
	OO_CHECK(monitor->sourceCodeForFile(missing, 2) == "<line out of range!>");
}


// The engine's monitor: errors and warnings go to the console, formatted, with the source line,
// and show it if the configuration says so; so do log lines.
OO_TEST(engineErrorsAndLogLinesReachTheConsole)
{
	SetUp();
	{
		oo::AutoreleaseScope pool;
		OODebugMonitor *monitor = OODebugMonitor::sharedDebugMonitor();
		OOJavaScriptEngineMonitor *engineMonitor = monitor;	// the C++ monitor interface
		const std::string path = WriteSource("script.js", "line one\n  line two\n");

		// The engine reports a problem by severity ("warning" or "exception"), file and line.

		// No debugger: nothing at all.
		engineMonitor->jsEngine(nullptr, gOOJSMainThreadContext, "warning", path, 2, 0, true, std::string("ignored"));

		TestDebugger *debugger = NewDebugger();
		OO_CHECK(monitor->setDebugger(debugger));
		engineMonitor->jsEngine(nullptr, gOOJSMainThreadContext, "warning", path, 2, 0, true, std::string("careful"));
		OO_CHECK(debugger->_output.size() == 1);
		OO_CHECK(debugger->_output.size() == 1 && debugger->_output[0] == "warning|Warning: careful\n    script.js, line 2:\n      line two|0,8");
		OO_CHECK(debugger->_shows == 1);	// show-console-on-warning is yes

		// QuickJS has no strict-mode reports and no errors that are not exceptions (#768): an
		// exception is the only other severity.
		engineMonitor->jsEngine(nullptr, gOOJSMainThreadContext, "exception", path, 2, 1, true, std::string("boom"));
		OO_CHECK(debugger->_output.size() == 2 && debugger->_output[1] == "exception|Exception: boom|0,10");
		OO_CHECK(debugger->_shows == 1);	// show-console-on-error is not set

		engineMonitor->jsEngine(nullptr, gOOJSMainThreadContext, std::string("logged"), std::nullopt);
		OO_CHECK(debugger->_output.size() == 3 && debugger->_output[2] == "log|logged|0,0");
		OO_CHECK(debugger->_shows == 1);	// show-console-on-log is no
		monitor->setConfigurationValue(oo::PList("yes"), "show-console-on-log");
		engineMonitor->jsEngine(nullptr, gOOJSMainThreadContext, std::string("again"), std::string("class"));
		OO_CHECK(debugger->_shows == 2);
		monitor->setConfigurationValue(oo::PList(), "show-console-on-log");

		OO_CHECK(monitor->setDebugger(nullptr));
	}
}


OO_TEST(settingsFlags)
{
	SetUp();
	StartLog();
	OODebugMonitor *monitor = OODebugMonitor::sharedDebugMonitor();
	monitor->setTCPIgnoresDroppedPackets(true);
	monitor->setTCPIgnoresDroppedPackets(true);
	OO_CHECK(monitor->TCPIgnoresDroppedPackets());
	monitor->setTCPIgnoresDroppedPackets(false);
	OO_CHECK(!monitor->TCPIgnoresDroppedPackets());
	OO_CHECK(LogLinesContaining("The TCP console will try to stay connected, ignoring dropped TCP packets.") == 1);
	OO_CHECK(LogLinesContaining("The TCP console will disconnect if an error affects TCP packets.") == 1);

	monitor->setUsingPlugInController(true);
	OO_CHECK(monitor->usingPlugInController());
	monitor->setUsingPlugInController(false);
	OO_CHECK(!monitor->usingPlugInController());
}


// The memory dump with no entities and no textures: the totals, and the JavaScript heap.
OO_TEST(memoryStatistics)
{
	SetUp();
	StartLog();
	{
		oo::AutoreleaseScope pool;
		OODebugMonitor *monitor = OODebugMonitor::sharedDebugMonitor();
		TestDebugger *debugger = NewDebugger();
		OO_CHECK(monitor->setDebugger(debugger));

		const size_t jsSize = monitor->dumpJSMemoryStatistics();
		OO_CHECK(jsSize > 0);
		OO_CHECK(LogLinesContaining("JavaScript heap: ") == 1);
		OO_CHECK(debugger->_output.size() == 1 && debugger->_output[0].starts_with("command-result|JavaScript heap: "));

		gLiveEntityCount = 3;
		gLog.clear();
		static PlayerEntity sStandInPlayer;	// the debug build asserts that PLAYER is set (OOGetPlayer()): one with no wormholes
		gOOPlayer = &sStandInPlayer;
		monitor->dumpMemoryStatistics();
		gOOPlayer = nullptr;
		OO_CHECK(LogLinesContaining("Memory statistics:") == 1);
		OO_CHECK(LogLinesContaining("Entitites:") == 1);
		OO_CHECK(LogLinesContaining("Total entity size (excluding 3 entities not accounted for): 0 bytes (0 bytes entity objects, 0 bytes drawables)") == 1);
		OO_CHECK(LogLinesContaining("Textures:") == 1);
		OO_CHECK(LogLinesContaining("Total texture size: 0 bytes (0 bytes object overhead, 0 bytes data, 0 bytes visible texture data)") == 1);
		OO_CHECK(LogLinesContaining("JavaScript heap: ") == 1);
		OO_CHECK(LogLinesContaining("Total: ") == 1);
		OO_CHECK(debugger->_output.size() == 7);	// the six written lines after the heap line ("Memory statistics:" is logged only)
		gLiveEntityCount = 0;

		OO_CHECK(monitor->setDebugger(nullptr));
	}
}


// The console's JS object is made once and kept; an engine reset drops it and the console script,
// and the engine's "did reset" makes the script again.
OO_TEST(javaScriptValueAndEngineReset)
{
	SetUp();
	{
		oo::AutoreleaseScope pool;
		OODebugMonitor *monitor = OODebugMonitor::sharedDebugMonitor();
		JSValue first = monitor->jsValueInContext(gOOJSMainThreadContext);
		OO_CHECK(JS_IsObject(first));
		OO_CHECK(sConsoleWrappersMade == 1);
		JSValue again = monitor->jsValueInContext(gOOJSMainThreadContext);
		OO_CHECK(JS_IsObject(again) && JS_VALUE_GET_PTR(again) == JS_VALUE_GET_PTR(first) && sConsoleWrappersMade == 1);
		JS_FreeValue(gOOJSMainThreadContext, again);
		JS_FreeValue(gOOJSMainThreadContext, first);

		// The reset drops the console's JS object (#768 frees it; there is no OOJSConsoleDestroy()).
		OOJavaScriptEngine *engine = OOJavaScriptEngine::sharedEngine();
		const int scripts = sConsoleScriptsMade;
		oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineWillResetNotificationName, engine);
		JS_FreeValue(gOOJSMainThreadContext, monitor->jsValueInContext(gOOJSMainThreadContext));
		OO_CHECK(sConsoleWrappersMade == 2);	// made again

		oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineDidResetNotificationName, engine);
		OO_CHECK(sConsoleScriptsMade == scripts + 1);
		oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineDidResetNotificationName, nullptr);	// another object's
		OO_CHECK(sConsoleScriptsMade == scripts + 1);

		// With no console script, the console is the global debugConsole instead.
		const std::optional<std::string> path = sConsoleScriptPath;
		sConsoleScriptPath = std::nullopt;
		oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineWillResetNotificationName, engine);
		oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineDidResetNotificationName, engine);
		OO_CHECK(sConsoleScriptsMade == scripts + 2);	// the path was remembered from the first time
		sConsoleScriptPath = path;
	}
}


// The one C++ monitor for the life of the process, described as "%@".
OO_TEST(cxxMonitorAndItsFacade)
{
	SetUp();
	OODebugMonitor *monitor = OODebugMonitor::sharedDebugMonitor();
	OO_CHECK(monitor != nullptr && OODebugMonitor::sharedDebugMonitor() == monitor);
	if (monitor == nullptr)  return;
	OO_CHECK(monitor->description().starts_with("<OODebugMonitor 0x"));

	monitor->setUsingPlugInController(true);
	OO_CHECK(monitor->usingPlugInController());
	monitor->setUsingPlugInController(false);
	OO_CHECK(!monitor->usingPlugInController());
}


// Last: on exit the overrides are saved to the user's defaults and the debugger is told.
OO_TEST(applicationWillTerminate)
{
	SetUp();
	{
		oo::AutoreleaseScope pool;
		OODebugMonitor *monitor = OODebugMonitor::sharedDebugMonitor();
		TestDebugger *debugger = NewDebugger();
		OO_CHECK(monitor->setDebugger(debugger));
		monitor->setConfigurationValue(oo::PList(16), "font-size");

		monitor->applicationWillTerminate();
		OO_CHECK(debugger->_disconnects.size() == 1 && debugger->_disconnects[0] == "Oolite is terminating.");
		OO_CHECK(!monitor->debuggerConnected());
		const oo::PList saved = oo::Defaults::standard().dictionaryForKey("debug-settings-override");
		OO_CHECK(saved.find("font-size") != nullptr && *saved.find("font-size") == oo::PList(16));
		OO_CHECK(saved.find("log-fg-colour") != nullptr && *saved.find("log-fg-colour") == RGBA(0.0f, 1.0f, 0.0f, 1.0f));
		OO_CHECK(saved.find("console-fg-color") != nullptr);
	}
}


OO_TEST_MAIN()
