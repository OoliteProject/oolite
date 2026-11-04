/*	test_OOJSTimer.mm
	Unit tests for the Timer JS binding (src/Core/Scripting/OOJSTimer.h/.mm), covering OOScriptTimer
	and its one subclass OOJSTimer.

	The binding's test runs its JS class in a real QuickJS-ng context, and links the game's own
	objects for the binding, its base class OOScriptTimer, the priority queue that schedules it, the
	engine's class registry (OOJSClasses.mm), its exception translator (OOJSEngineNativeWrappers.mm)
	and, since the Timer's private slot holds the C++ timer, the engine's C++ private-slot glue
	(OOJSPrivateObject.cpp: the getter, finalizer and toString()). What the rest of the engine would
	provide is defined below as the smallest stand-in that does the same thing: the error and
	warning reporters, the object getter and converters, the JS glue that OOObject gets from
	OOJavaScriptEngine.mm, the engine object (which calls the timer's function), the script stack
	and the universe's clock. The engine's and OOJSScript's headers are not imported, because the
	test defines those classes. The expectations were written against the Objective-C files and run
	on them first; they pin the JS-visible behaviour: the constructor and its errors, the three
	properties, start() and stop(), toString(), firing with the right `this`, a timer whose `this`
	is null, and what an engine reset does. A timer that is garbage-collected while running
	(unrootedRunningTimerGC) must not call back into the engine from its finalizer: describing it
	for the warning did, and on QuickJS that corrupted the heap (the test crashed at exit about one
	run in six with a single collection). Run: bash tools/check-core-tests.sh
*/

#include "OOScriptTimer.h"
#include "oofnd/objc/OOObject.h"
#include "OODescription.h"
#include "oofnd/Notification.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"

#include "oo_test.hpp"

#include <quickjs.h>

#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>


// EntityHelpers.mm's, which the test does not link: an entity's node (its hold and its description)
// is reached only for an entity, which the test has none of. A null hold releases nothing.
class Entity;
namespace oo {
namespace detail { void EntityRelease(Entity *entity) noexcept; }
std::string EntityDescription(Entity *entity);
}  // namespace oo
void oo::detail::EntityRelease(Entity *entity) noexcept  { if (entity != nullptr)  std::abort(); }
std::string oo::EntityDescription(Entity *)  { std::abort(); }


void InitOOJSTimer(JSContext *context, JSValueConst global);


// MARK: What the rest of the engine provides ------------------------------------------------------

namespace {
std::vector<std::string> sWarnings;
int sScriptDepth = 0;
int sScriptPushes = 0;
int sCalls = 0;
bool sConverterRegistered = false;
} // namespace

JSContext *gOOJSMainThreadContext = nullptr;
extern const char * const kOOJavaScriptEngineWillResetNotificationName;
const char * const kOOJavaScriptEngineWillResetNotificationName = "org.aegidian.oolite OOJavaScriptEngine will reset";

// The class registry's (OOJSClasses.mm, linked).
const char *OOJSClassName(JSClassID classID);
BOOL OOJSIsSubclass(JSClassID putativeSubclass, JSClassID superclass);


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


void OOJSReportBadPropertyValue(JSContext *context, JSValueConst, int, const JSCFunctionListEntry *, size_t, JSValueConst)
{
	cxx_OOJSReportError(context, "bad property value");
}


// As the engine's: the pending exception, else an uncatchable error that stops the script.
JSValue OOJSNativeFailure(JSContext *context)
{
	if (JS_HasException(context))  return JS_EXCEPTION;
	JSValue error = JS_NewError(context);
	JS_SetUncatchableError(context, error);
	return JS_Throw(context, error);
}


// The atom cache and the pending-exception reporter, which the class registry calls.
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


// A JS object as a property list: the test's `this` objects are plain, so any object is a
// non-null value and no object (null) is null (what the engine's conversion gives them).
oo::PList cxx_OOJSPListFromJSObject(JSContext *, JSValueConst object)
{
	if (!JS_IsObject(object))  return oo::PList();
	return oo::PList(std::string("object"));
}


typedef oo::PList (*OOJSClassConverterCallback)(JSContext *context, JSValueConst object);

void OOJSRegisterObjectConverter(JSClassID classID, OOJSClassConverterCallback converter)
{
	const char *className = OOJSClassName(classID);
	sConverterRegistered = className != nullptr && std::string(className) == "Timer" && converter != nullptr;
}


oo::PList OOJSBasicPrivateObjectConverter(JSContext *, JSValueConst)
{
	return oo::PList();
}




// OOJavaScriptEngine.mm's toString() for object wrappers.
JSValue OOJSObjectWrapperToString(JSContext *context, JSValueConst, int, JSValueConst *)
{
	// (Unreached: a timer's toString() is its own.)
	std::string description("[object]");
	return JS_NewStringLen(context, description.data(), description.size());
}


// OOJS_PROFILE (OOJavaScriptEngine.h) is OOLITE_DEBUG outside the proof-of-concept harness.
#if OOLITE_DEBUG
struct OOJSProfileStackFrame;
void OOJSProfileEnter(OOJSProfileStackFrame *, const char *)  {}
void OOJSProfileExit(OOJSProfileStackFrame *)  {}
#endif

void OOJSPauseTimeLimiter(void)  {}
void OOJSResumeTimeLimiter(void)  {}

#ifndef NDEBUG
void OOJSUnreachable(const char *function, const char *, unsigned)
{
	std::printf("unreachable reached in %s\n", function);
	abort();
}
#endif


/*	The engine object: the one method the timer sends it
   (-callJSFunction:...), which calls the function as the engine does, and the
   script stack the timer pushes its owner on.
*/
// The engine (OOJavaScriptEngine.h; a C++ class), declared with the header's
// names and signatures but not its class; the stand-in's answers are kept.
class OOJavaScriptEngine
{
public:
	static OOJavaScriptEngine *sharedEngine();
	bool callJSFunction(JSValueConst function, JSValueConst jsThis, int argc, JSValueConst *argv, JSValue *outResult);
};


OOJavaScriptEngine *OOJavaScriptEngine::sharedEngine()
{
	static OOJavaScriptEngine *engine = new OOJavaScriptEngine;
	return engine;
}


bool OOJavaScriptEngine::callJSFunction(JSValueConst function, JSValueConst jsThis, int argc, JSValueConst *argv, JSValue *outResult)
{
	sCalls++;
	JSContext *context = gOOJSMainThreadContext;
	JSValue result = JS_Call(context, function, jsThis, argc, argv);
	if (JS_IsException(result))
	{
		JS_FreeValue(context, JS_GetException(context));
		return NO;
	}
	*outResult = result;
	return YES;
}


#include "OOScript.h"


// OOJSScript (OOJSScript.h), which the code under test calls. A script is a C++
// object, so the stand-in is a C++ subclass of OOScript declaring the members
// that code calls.
class OOJSScript : public OOScript
{
public:
	static OOJSScript *currentlyRunningScript();
	static void pushScript(const oo::WeakRef<OOJSScript> &script);
	static void popScript(OOJSScript *script);
};

OOJSScript *OOJSScript::currentlyRunningScript()  { return nullptr; }
void OOJSScript::pushScript(const oo::WeakRef<OOJSScript> &script)  { (void)script; sScriptDepth++; sScriptPushes++; }
void OOJSScript::popScript(OOJSScript *script)  { (void)script; sScriptDepth--; }


// The universe's clock, which the test sets.
namespace {
double sNow = 100.0;
} // namespace

// The universe as the code under test sees it: a stand-in for the C++ class,
// with the header's names and signatures.
class Universe
{
public:
	OOTimeAbsolute getTime();
};
typedef Universe FakeUniverse;

OOTimeAbsolute Universe::getTime()	{ return sNow; }

class Universe;
Universe *gSharedUniverse = nil;


extern const char *const cxx_kOOLogException;
const char *const cxx_kOOLogException = "exception";

void OOLogGenericSubclassResponsibilityForFunction(const char *inFunction)
{
	(void)inFunction;
}


// MARK: The context -------------------------------------------------------------------------------

namespace {

JSRuntime *sRuntime;
JSValue sGlobal = JS_UNDEFINED;	// owned for the life of the test


void SetUpContext()
{
	if (gOOJSMainThreadContext != nullptr)  return;
	sRuntime = JS_NewRuntime();
	JS_SetMemoryLimit(sRuntime, 8u * 1024u * 1024u);
	gOOJSMainThreadContext = JS_NewContext(sRuntime);
	sGlobal = JS_GetGlobalObject(gOOJSMainThreadContext);
	InitOOJSTimer(gOOJSMainThreadContext, sGlobal);
	gSharedUniverse = new FakeUniverse();
}


// Evaluates src (statements; the value of the last one) and gives its result as a string
// ("undefined", "null", ...), or "threw: <message>".
std::string Eval(const char *src)
{
	SetUpContext();
	std::string quoted;
	for (const char *c = src; *c != '\0'; c++)
	{
		if (*c == '\\' || *c == '"')  quoted += '\\';
		quoted += *c;
	}
	std::string wrapped = std::string("(function () { try { return String((0, eval)(\"") + quoted + "\")); } catch (e) { return 'threw: ' + (e && e.message !== undefined ? e.message : e); } })()";
	JSValue result = JS_UNDEFINED;
	{	// As the game's frame loop drains: nothing is left to the thread's pool
     // at exit
		result = JS_Eval(gOOJSMainThreadContext, wrapped.c_str(), wrapped.size(), "test.js", JS_EVAL_TYPE_GLOBAL);
	}
	if (JS_IsException(result))
	{
		JS_FreeValue(gOOJSMainThreadContext, JS_GetException(gOOJSMainThreadContext));
		return "<evaluation failed>";
	}
	std::string text = cxx_OOStringFromJSValue(gOOJSMainThreadContext, result).value_or("<not a string>");
	JS_FreeValue(gOOJSMainThreadContext, result);
	return text;
}


void Update(double now)
{
	sNow = now;
	{
		OOScriptTimer::updateTimers();
	}
}

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

OO_TEST(classSetUp)
{
	OO_CHECK_EQ(Eval("typeof Timer"), "function");
	OO_CHECK(sConverterRegistered);
	OO_CHECK_EQ(Eval("Object.keys(Timer.prototype).sort().join()"), "interval,isRunning,nextTime");
}


OO_TEST(constructorErrors)
{
	OO_CHECK_EQ(Eval("Timer({}, function () {}, 1)"), "threw: Timer() cannot be called as a function, it must be used as a constructor (as in new Timer(...)).");
	OO_CHECK_EQ(Eval("new Timer({}, function () {})"), "threw: bad arguments: .Timer (2): Invalid arguments in constructor; expected (object, function, number [, number])");
	OO_CHECK_EQ(Eval("new Timer({}, 5, 1)"), "threw: bad arguments: .Timer (1): Invalid argument in constructor; expected function");
	OO_CHECK_EQ(Eval("new Timer({}, function () {}, 'x')"), "threw: bad arguments: .Timer (1): Invalid argument in constructor; expected number");
	OO_CHECK_EQ(Eval("new Timer({}, function () {}, NaN)"), "threw: bad arguments: .Timer (1): Invalid argument in constructor; expected number");
}


OO_TEST(properties)
{
	sNow = 100.0;
	OO_CHECK_EQ(Eval("globalThis.t1 = new Timer({}, function () {}, 5); t1.nextTime"), "105");
	OO_CHECK_EQ(Eval("t1.interval"), "-1");
	OO_CHECK_EQ(Eval("t1.isRunning"), "true");
	OO_CHECK_EQ(Eval("t1 instanceof Timer"), "true");

	// The interval: at least 0.25; a fourth argument that is not a number is ignored.
	OO_CHECK_EQ(Eval("globalThis.t2 = new Timer({}, function () {}, 1, 0.1); t2.interval"), "0.25");
	OO_CHECK_EQ(Eval("new Timer({}, function () {}, 1, 3).interval"), "3");
	OO_CHECK_EQ(Eval("new Timer({}, function () {}, 1, 'x').interval"), "NaN");
	OO_CHECK_EQ(Eval("new Timer({}, function () {}, 1, {}).interval"), "NaN");
	OO_CHECK_EQ(Eval("new Timer({}, function () {}, 1, -4).interval"), "-1");

	// A negative delay leaves a repeating timer stopped. A one-shot timer whose time has passed
	// cannot be made: the constructor fails without an exception, which ends the script.
	OO_CHECK_EQ(Eval("globalThis.t3 = new Timer({}, function () {}, -1, 5); t3.isRunning"), "false");
	OO_CHECK_EQ(Eval("t3.nextTime + ',' + t3.interval"), "99,5");
	OO_CHECK_EQ(Eval("new Timer({}, function () {}, -1)"), "<evaluation failed>");

	// The next time cannot change while the timer runs: a warning, and the old time stays.
	sWarnings.clear();
	OO_CHECK_EQ(Eval("t1.nextTime = 200; t1.nextTime"), "105");
	OO_CHECK_EQ(sWarnings.size(), 1u);
	if (sWarnings.size() == 1)  OO_CHECK(sWarnings[0].find("Ignoring attempt to change next fire time for running timer <OOJSTimer") == 0);
	OO_CHECK_EQ(Eval("t3.nextTime = 200; t3.nextTime"), "200");
	OO_CHECK_EQ(Eval("t3.interval = 7; t3.interval"), "7");
	OO_CHECK_EQ(Eval("t3.interval = -7; t3.interval"), "-1");
	OO_CHECK_EQ(Eval("t3.interval = 'abc'; t3.interval"), "NaN");
	OO_CHECK_EQ(Eval("t3.isRunning = true; t3.isRunning"), "false");
	// As in #768, a read-only property has no setter, so strict code that assigns to one gets a
	// TypeError (the old binding ignored it even there).
	OO_CHECK_EQ(Eval("(function () { 'use strict'; t3.isRunning = true; return t3.isRunning; })()"), "threw: no setter for property");

	OO_CHECK_EQ(Eval("t1.stop(); t2.stop(); t1.isRunning"), "false");
	OO_CHECK_EQ(Eval("Timer.prototype.nextTime"), "0");	// the prototype is a Timer with no timer: nil answered 0
}


OO_TEST(startAndStop)
{
	sNow = 100.0;
	OO_CHECK_EQ(Eval("globalThis.s = new Timer({}, function () {}, -1, 1); s.isRunning"), "false");
	OO_CHECK_EQ(Eval("s.start()"), "true");
	OO_CHECK_EQ(Eval("s.isRunning"), "true");
	OO_CHECK_EQ(Eval("s.start()"), "true");
	OO_CHECK_EQ(Eval("s.stop()"), "undefined");
	OO_CHECK_EQ(Eval("s.isRunning"), "false");
	OO_CHECK_EQ(Eval("Timer.prototype.start.call({})"), "threw: Native method expected Timer, got [object Object].");
	OO_CHECK_EQ(Eval("Timer.prototype.stop.call(new Date(0)) === undefined").rfind("threw: Native method expected Timer, got ", 0), 0u);
}


OO_TEST(toString)
{
	sNow = 100.0;
	OO_CHECK_EQ(Eval("new Timer({}, function tick() {}, 1)"), "[Timer nextTime: 101, one-shot, running, function: tick]");
	OO_CHECK_EQ(Eval("new Timer({}, function () {}, 2, 5)"), "[Timer nextTime: 102, interval: 5, running, function: anonymous]");
	OO_CHECK_EQ(Eval("new Timer({}, function () {}, -2, 5)"), "[Timer nextTime: 98, interval: 5, not running, function: anonymous]");
	OO_CHECK_EQ(Eval("(function () { var t = new Timer({}, function tock() {}, 1); t.stop(); return t; })()"), "[Timer nextTime: 101, one-shot, not running, function: tock]");
	OO_CHECK_EQ(Eval("Timer.prototype.toString.call({})"), "[object]");
	// Stop the running ones above, so that later tests do not fire them.
	Update(100.0);
	OOScriptTimer::noteGameReset();
}


OO_TEST(firing)
{
	sNow = 100.0;
	OO_CHECK_EQ(Eval("globalThis.log = []; globalThis.owner = { name: 'owner' }; "
					 "globalThis.once = new Timer(owner, function () { log.push('once:' + this.name); }, 1); "
					 "globalThis.rep = new Timer(owner, function () { log.push('rep:' + this.name); }, 0.5, 2); "
					 "log.length"), "0");
	sCalls = 0;
	sScriptPushes = 0;
	Update(100.4);
	OO_CHECK_EQ(Eval("log.join()"), "");
	Update(101.0);
	OO_CHECK_EQ(Eval("log.join()"), "rep:owner,once:owner");
	OO_CHECK_EQ(Eval("once.isRunning + ',' + rep.isRunning + ',' + rep.nextTime"), "false,true,102.5");
	Update(105.0);
	OO_CHECK_EQ(Eval("log.join()"), "rep:owner,once:owner,rep:owner");
	OO_CHECK_EQ(Eval("rep.nextTime"), "106.5");
	OO_CHECK_EQ(sCalls, 3);
	OO_CHECK_EQ(sScriptPushes, 3);
	OO_CHECK_EQ(sScriptDepth, 0);

	// A timer that stops itself when it fires.
	OO_CHECK_EQ(Eval("rep.stop(); globalThis.self = new Timer(owner, function () { log.push('self'); self.stop(); }, 1, 1); self.isRunning"), "true");
	Update(106.0);
	OO_CHECK_EQ(Eval("log.join() + ';' + self.isRunning"), "rep:owner,once:owner,rep:owner,self;false");
	Update(110.0);
	OO_CHECK_EQ(Eval("log.length"), "4");
}


OO_TEST(nullThis)
{
	// A timer whose `this` is null or undefined is stopped when it is due, without a call.
	sNow = 100.0;
	OO_CHECK_EQ(Eval("globalThis.log2 = []; globalThis.orphan = new Timer(null, function () { log2.push('x'); }, 1, 1); orphan.isRunning"), "true");
	sCalls = 0;
	Update(101.0);
	OO_CHECK_EQ(sCalls, 0);
	OO_CHECK_EQ(Eval("log2.length + ',' + orphan.isRunning"), "0,false");
	OO_CHECK_EQ(Eval("orphan.start()"), "true");
	Update(103.0);
	OO_CHECK_EQ(Eval("orphan.isRunning"), "false");
}


OO_TEST(engineReset)
{
	sNow = 100.0;
	OO_CHECK_EQ(Eval("globalThis.log3 = []; globalThis.r = new Timer({}, function () { log3.push('r'); }, 1, 1); r.isRunning"), "true");
	oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineWillResetNotificationName, OOJavaScriptEngine::sharedEngine());
	OO_CHECK_EQ(Eval("r.isRunning"), "false");
	OO_CHECK_EQ(Eval("String(r)"), "[Timer invalid]");
	Update(105.0);
	OO_CHECK_EQ(Eval("log3.length"), "0");
}


OO_TEST(unrootedRunningTimerGC)
{
	// A script drops its last reference to a running timer and the engine
  // collects it: the finalizer warns and lets go of the timer, without
  // re-entering the engine. The function's name is a getter that counts its
  // calls: reading it from the finalizer would run script inside the
  // collection, which is the defect.
	sNow = 100.0;
	OO_CHECK_EQ(Eval("globalThis.nameReads = 0; (function () { var f = function () {}; Object.defineProperty(f, 'name', { get: function () { nameReads++; return 'spy'; } }); new Timer({}, f, 1, 1); })(); 'dropped'"), "dropped");
	JS_RunGC(sRuntime);
	// As in #768, the constructor reads the name once and keeps it, so the one read is the
	// constructor's; the finalizer adds none.
	OO_CHECK_EQ(Eval("nameReads"), "1");

	// Many collections in one process, then more script, so a corrupted heap shows up here or
	// at exit rather than one run in six.
	for (int i = 0; i < 40; i++)
	{
		OO_CHECK_EQ(Eval("(function () { new Timer({}, function tick() {}, 1, 1); new Timer({}, function () {}, 2); })(); 'dropped'"), "dropped");
		JS_RunGC(sRuntime);
	}
	OO_CHECK_EQ(Eval("var a = []; for (var i = 0; i < 1000; i++) a.push({ n: String(i) }); a.length"), "1000");
	JS_RunGC(sRuntime);
	OO_CHECK_EQ(Eval("String(new Timer({}, function after() {}, 1))"), "[Timer nextTime: 101, one-shot, running, function: after]");
}


OO_TEST_MAIN()
