/*	test_OOJSFrameCallbacks.mm
	Unit tests for the frame callbacks (src/Core/Scripting/OOJSFrameCallbacks.h/.mm): bead oo-n041,
	a Phase 3 scripting file (proposed ADR-0056 amendment oo-ppc).

	The file defines the global functions addFrameCallback(), removeFrameCallback() and
	isValidFrameCallback(), and OOJSFrameCallbacksInvoke(), which the game calls every frame. The
	test runs them in a real context on the game's own façade backend
	(ooscript/JSEngine_quickjs.cpp) and links the game's own objects for the file and the engine's
	exception translator (OOJSEngineNativeWrappers.mm). What the rest of the engine would provide
	is defined below as the smallest stand-in that does the same thing (amendment oo-ppc item 6):
	the error and warning reporters, OOJSValue (a rooted JS value, which a deferred add keeps), the
	time limiter and the universe's time acceleration. The engine's header is not imported,
	because the test defines OOJSValue (amendment oo-z1s4 item 4). The expectations were written
	against the Objective-C file and run on it first; they pin the three functions and their
	errors, the delta each callback receives, adds and removes made while the callbacks run
	(deferred to the end of the frame), a throwing callback, growth past the first 16 slots, and
	removing all.
	Run: bash tools/check-core-tests.sh
*/

#include "oofnd/objc/OOObject.h"
#include "OOTypes.h"
#include "ooscript/JSEngine.hpp"
#include "OOJSEngineNativeWrappers.h"
#include "OOJSEngineCore.h"	// OOJSValue
#include "oofnd/String.hpp"

#include "oo_test.hpp"

#include <cstdarg>
#include <cstring>
#include <string>
#include <vector>


extern "C" void InitOOJSFrameCallbacks(ooscript::Context context, ooscript::Object global);
extern "C" void OOJSFrameCallbacksInvoke(OOTimeDelta delta);
extern "C" void OOJSFrameCallbacksRemoveAll(void);


// MARK: What the rest of the engine provides ------------------------------------------------------

namespace {
std::vector<std::string> sWarnings;
int sLimiterDepth = 0;
double sLastLimit = -1;
ooscript::Object sGlobal;
} // namespace

ooscript::Context gOOJSMainThreadContext = nullptr;


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


void cxx_OOJSReportWarning(ooscript::Context context, const char *format, ...)
{
	(void)context;
	va_list args;
	va_start(args, format);
	sWarnings.push_back(oo::str::vformat(format, args));
	va_end(args);
}


void cxx_OOJSReportBadArguments(ooscript::Context context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, unsigned argc, ooscript::Value *, const std::optional<std::string> &message, const std::optional<std::string> &expectedArgsDescription)
{
	cxx_OOJSReportError(context, "bad arguments: %s.%s (%u): %s; expected %s", scriptClass.value_or("").c_str(), function.value_or("").c_str(), argc, message.value_or("").c_str(), expectedArgsDescription.value_or("").c_str());
}


std::optional<std::string> cxx_OOStringFromJSValue(ooscript::Context context, ooscript::Value value)
{
	if (ooscript::isNullOrUndefined(value))  return std::nullopt;
	ooscript::String str = ooscript::valueToString(context, value);
	if (str == nullptr)  return std::nullopt;
	std::size_t length = 0;
	const ooscript::Char16 *chars = ooscript::getStringCharsAndLength(context, str, &length);
	std::string result;
	for (std::size_t i = 0; i < length; i++)  result += static_cast<char>(chars[i]);	// the test's strings are ASCII
	return result;
}


// A JS value kept alive for C++ (OOJSEngineCore.h; a C++ class since bead oo-wdqw1 deleted its
// facade): the members the deferred add calls, defined here with the stand-in's answers.
oo::Ref<OOJSValue> OOJSValue::valueWithJSValue(ooscript::Value value, ooscript::Context context)
{
	oo::Ref<OOJSValue> result = oo::makeRef<OOJSValue>();
	result->_val = value;
	ooscript::addNamedValueRoot(context, &result->_val, "test OOJSValue");
	return result;
}


OOJSValue::~OOJSValue()
{
	ooscript::removeValueRoot(gOOJSMainThreadContext, &_val);
}


ooscript::Value OOJSValue::jsValueInContext(ooscript::Context)  { return _val; }
std::string OOJSValue::className() const  { return "OOJSValue"; }
std::string OOJSValue::description() const  { return "<OOJSValue>"; }


#ifndef NDEBUG
extern "C" void OOJSStartTimeLimiterWithTimeLimit_(OOTimeDelta limit, const char *, unsigned)  { sLimiterDepth++; sLastLimit = limit; }
extern "C" void OOJSStopTimeLimiter_(const char *, unsigned)  { sLimiterDepth--; }
#else
void OOJSStartTimeLimiterWithTimeLimit(OOTimeDelta limit)  { sLimiterDepth++; sLastLimit = limit; }
void OOJSStopTimeLimiter(void)  { sLimiterDepth--; }
#endif

#if OOJS_PROFILE
extern "C" void OOJSProfileEnter(OOJSProfileStackFrame *, const char *)  {}
extern "C" void OOJSProfileExit(OOJSProfileStackFrame *)  {}
#endif

extern "C" void OOJSPauseTimeLimiter(void)  {}
extern "C" void OOJSResumeTimeLimiter(void)  {}

#ifndef NDEBUG
extern "C" void OOJSUnreachable(const char *function, const char *, unsigned)
{
	std::printf("unreachable reached in %s\n", function);
	abort();
}
#endif


// The universe's time acceleration, which scales each frame's delta.
// The universe as the code under test sees it: a stand-in for the C++ class (bead oo-ql9rn deleted
// the Objective-C facade the test's FakeUniverse stood in for), with the header's names and signatures.
class Universe
{
public:
	double getTimeAccelerationFactor();
};
typedef Universe FakeUniverse;

double Universe::getTimeAccelerationFactor()	{ return 2.0; }

class Universe;
Universe *gSharedUniverse = nil;


// MARK: The context -------------------------------------------------------------------------------

namespace {

void SetUpContext()
{
	if (gOOJSMainThreadContext != nullptr)  return;
	ooscript::Runtime runtime = ooscript::newRuntime(8u * 1024u * 1024u);
	gOOJSMainThreadContext = ooscript::newContext(runtime, 8192);
	ooscript::beginRequest(gOOJSMainThreadContext);
	sGlobal = ooscript::getGlobalObject(gOOJSMainThreadContext);
	ooscript::initStandardClasses(gOOJSMainThreadContext, sGlobal);
	InitOOJSFrameCallbacks(gOOJSMainThreadContext, sGlobal);
	gSharedUniverse = new FakeUniverse();
}


// Evaluates src (statements; the value of the last one) and gives its result as a string, or
// "threw: <message>".
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
	ooscript::Value result = ooscript::undefinedValue();
	bool OK = false;
	{
		OK = ooscript::evaluateScript(gOOJSMainThreadContext, sGlobal, wrapped.c_str(), static_cast<unsigned>(wrapped.size()), "test.js", 1, &result);
	}
	if (!OK)
	{
		ooscript::clearPendingException(gOOJSMainThreadContext);
		return "<evaluation failed>";
	}
	return cxx_OOStringFromJSValue(gOOJSMainThreadContext, result).value_or("<not a string>");
}


void Frame(double delta)
{
	{
		OOJSFrameCallbacksInvoke(delta);
	}
}

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

OO_TEST(functions)
{
	OO_CHECK_EQ(Eval("typeof addFrameCallback + typeof removeFrameCallback + typeof isValidFrameCallback"), "functionfunctionfunction");
	OO_CHECK_EQ(Eval("addFrameCallback()"), "threw: bad arguments: .addFrameCallback (0): ; expected function");
	OO_CHECK_EQ(Eval("addFrameCallback(5)"), "threw: bad arguments: .addFrameCallback (1): ; expected function");
	OO_CHECK_EQ(Eval("removeFrameCallback()"), "threw: bad arguments: .removeFrameCallback (0): ; expected frame callback tracking ID");
	OO_CHECK_EQ(Eval("isValidFrameCallback()"), "threw: bad arguments: .isValidFrameCallback (0): ; expected frame callback tracking ID");

	OO_CHECK_EQ(Eval("globalThis.id1 = addFrameCallback(function () {}); typeof id1"), "number");
	OO_CHECK_EQ(Eval("isValidFrameCallback(id1)"), "true");
	OO_CHECK_EQ(Eval("globalThis.id2 = addFrameCallback(function () {}); id1 !== id2 && isValidFrameCallback(id2)"), "true");
	OO_CHECK_EQ(Eval("isValidFrameCallback({})"), "false");
	sWarnings.clear();
	OO_CHECK_EQ(Eval("removeFrameCallback(id1)"), "undefined");
	OO_CHECK_EQ(Eval("isValidFrameCallback(id1) + ',' + isValidFrameCallback(id2)"), "false,true");
	OO_CHECK(sWarnings.empty());
	OO_CHECK_EQ(Eval("removeFrameCallback(id1)"), "undefined");
	OO_CHECK_EQ(sWarnings.size(), 1u);
	if (!sWarnings.empty())  OO_CHECK_EQ(sWarnings[0], "removeFrameCallback(): invalid tracking ID.");
	OOJSFrameCallbacksRemoveAll();
	OO_CHECK_EQ(Eval("isValidFrameCallback(id2)"), "false");
}


OO_TEST(invoke)
{
	OO_CHECK_EQ(Eval("globalThis.log = []; globalThis.a = addFrameCallback(function (delta) { log.push('a' + delta + (this === globalThis)); }); "
					 "globalThis.b = addFrameCallback(function (delta) { log.push('b' + delta); }); log.length"), "0");
	sLastLimit = -1;
	Frame(0.25);
	OO_CHECK_EQ(Eval("log.join()"), "a0.5true,b0.5");	// the delta times the time acceleration
	OO_CHECK_EQ(sLimiterDepth, 0);
	OO_CHECK_EQ(sLastLimit, 0.1);
	Frame(1.0);
	OO_CHECK_EQ(Eval("log.join()"), "a0.5true,b0.5,a2true,b2");

	// Removing the first puts the last in its place.
	OO_CHECK_EQ(Eval("globalThis.c = addFrameCallback(function () { log.push('c'); }); removeFrameCallback(a); log.length = 0"), "0");
	Frame(0.5);
	OO_CHECK_EQ(Eval("log.join()"), "c,b1");
	OOJSFrameCallbacksRemoveAll();
	Frame(0.5);
	OO_CHECK_EQ(Eval("log.join()"), "c,b1");
}


OO_TEST(changesWhileRunning)
{
	// An add or remove made by a callback waits until every callback of the frame has run.
	OO_CHECK_EQ(Eval("globalThis.log = []; globalThis.added = null; globalThis.validDuring = null; "
					 "globalThis.adder = addFrameCallback(function () { log.push('adder'); if (added === null) { added = addFrameCallback(function () { log.push('added'); }); validDuring = isValidFrameCallback(added); } }); "
					 "globalThis.self = addFrameCallback(function () { log.push('self'); removeFrameCallback(self); log.push('still ' + isValidFrameCallback(self)); }); log.length"), "0");
	Frame(1);
	OO_CHECK_EQ(Eval("log.join() + ';' + validDuring + ';' + isValidFrameCallback(added) + ';' + isValidFrameCallback(self)"), "adder,self,still true;false;true;false");
	OO_CHECK_EQ(Eval("log.length = 0; typeof added"), "number");
	Frame(1);
	OO_CHECK_EQ(Eval("log.join()"), "adder,added");
	OOJSFrameCallbacksRemoveAll();
}


OO_TEST(throwingCallback)
{
	OO_CHECK_EQ(Eval("globalThis.log = []; addFrameCallback(function () { throw new Error('boom'); }); addFrameCallback(function () { log.push('after'); }); log.length"), "0");
	Frame(1);
	OO_CHECK_EQ(Eval("log.join()"), "after");
	OO_CHECK_EQ(sLimiterDepth, 0);
	OO_CHECK(ooscript::isInRequest(gOOJSMainThreadContext));
	OOJSFrameCallbacksRemoveAll();
}


OO_TEST(growth)
{
	// Past the first 16 slots the list grows, and every callback still runs once per frame.
	OO_CHECK_EQ(Eval("globalThis.count = 0; globalThis.ids = []; for (var i = 0; i < 40; i++) ids.push(addFrameCallback(function () { count++; })); ids.length"), "40");
	Frame(1);
	OO_CHECK_EQ(Eval("count"), "40");
	OO_CHECK_EQ(Eval("ids.every(isValidFrameCallback)"), "true");
	OO_CHECK_EQ(Eval("for (var i = 0; i < 40; i += 2) removeFrameCallback(ids[i]); count = 0"), "0");
	Frame(1);
	OO_CHECK_EQ(Eval("count"), "20");
	OO_CHECK_EQ(Eval("ids.filter(isValidFrameCallback).length"), "20");
	OOJSFrameCallbacksRemoveAll();
	OO_CHECK_EQ(Eval("ids.some(isValidFrameCallback)"), "false");
}


OO_TEST_MAIN()
