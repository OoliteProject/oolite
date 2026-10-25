/*	test_OOJSClock.mm
	Unit tests for the clock JS binding (src/Core/Scripting/OOJSClock.h/.mm): bead oo-xy5r,
	converted the way bead oo-ppc converted OOJSVector (proposed ADR-0056 amendment oo-ppc).

	Like test_OOJSVector.mm, it runs the JS class in a real context on the game's own façade
	backend (ooscript/JSEngine_quickjs.cpp) and links the game's own objects for the binding and
	the engine's exception translator (OOJSEngineNativeWrappers.mm). What the rest of the game
	would provide (the player's clock, the universe's time, the clock-string formatter, the
	deprecation warning, error reporting and the string helpers) is defined below as the smallest
	stand-in that does the same thing. The expectations were written against the Objective-C file
	and run on it first; they pin the JS-visible behaviour: the global `clock` object and every
	property, the three methods, their errors, and how an exception under a native reaches JS.
	Run: bash tools/check-core-tests.sh
*/

#include "OOJSClock.h"
#include "OOJavaScriptEngine.h"
#include "OOJSPlayer.h"
#include "Universe.h"
#include "OODebugStandards.h"
#include "OOStringParsing.h"
#include "oofnd/objc/OOException.h"
#include "oofnd/String.hpp"

#include "oo_test.hpp"

#include <cstdarg>
#include <cstring>
#include <stdexcept>
#include <string>


// MARK: What the rest of the engine provides ------------------------------------------------------

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


void cxx_OOJSReportBadArguments(ooscript::Context context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, unsigned argc, ooscript::Value *, const std::optional<std::string> &message, const std::optional<std::string> &expectedArgsDescription)
{
	cxx_OOJSReportError(context, "bad arguments: %s.%s (%u): %s; expected %s", scriptClass.value_or("").c_str(), function.value_or("").c_str(), argc, message.value_or("").c_str(), expectedArgsDescription.value_or("").c_str());
}


void OOJSReportBadPropertySelector(ooscript::Context context, ooscript::Object, ooscript::PropertyId, ooscript::PropertySpec *)
{
	cxx_OOJSReportError(context, "bad property selector");
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


ooscript::Value OOJSValueFromPList(ooscript::Context context, const oo::PList &plist)
{
	const std::string *str = plist.getIf<std::string>();
	ooscript::String js = str != nullptr ? ooscript::newStringCopyN(context, str->data(), str->size()) : nullptr;
	return js != nullptr ? ooscript::stringValue(js) : ooscript::nullValue();
}


bool OOJSUnconstructableConstruct(ooscript::Context context, ooscript::CallArgs &)
{
	cxx_OOJSReportError(context, "unconstructable");
	return false;
}


#if OOJS_PROFILE
namespace {
int sProfileDepth = 0;
} // namespace

void OOJSProfileEnter(OOJSProfileStackFrame *, const char *)  { sProfileDepth++; }
void OOJSProfileExit(OOJSProfileStackFrame *)  { sProfileDepth--; }
#endif


namespace {
int sLimiterPauses = 0;
int sDeprecations = 0;
} // namespace

void OOJSPauseTimeLimiter(void)  { sLimiterPauses++; }
void OOJSResumeTimeLimiter(void)  { sLimiterPauses--; }


#ifndef NDEBUG
void OOJSUnreachable(const char *function, const char *, unsigned)
{
	std::printf("unreachable reached in %s\n", function);
	abort();
}
#endif


void cxx_OOStandardsDeprecated(const std::string &)
{
	sDeprecations++;
}


// The formatter, as far as the clock sees it: what it was asked for.
std::string cxx_ClockToString(double clock, BOOL adjusting)
{
	return oo::str::format("clock(%g, %d)", clock, adjusting ? 1 : 0);
}


/*	The player, as far as the clock sees it: the clock selectors. A clock time of -1 makes
	-clockTime raise, -2 makes it throw a C++ exception, so the test sees what an exception under a
	native becomes.
*/
/*	PLAYER: C++ since bead oo-9ht.177 deleted the Objective-C player this stood in for. The binding
	calls the members below (PlayerEntity.h, which the engine's header imports, declares them),
	which answer from the FakePlayer's values; the binding never reads the player's own state, so
	PLAYER is a FakePlayer's address.
*/
struct FakePlayer
{
	double _clockTime = 0;
	double _adjusted = 0;
	double _added = 0;
	BOOL _adjusting = NO;
};

namespace {
FakePlayer *sPlayer = nullptr;
} // namespace

double PlayerEntity::clockTime()
{
	if (sPlayer->_clockTime == -1)  OORaiseException(OOInvalidArgumentException, "clock %s", "boom");
	if (sPlayer->_clockTime == -2)  throw std::runtime_error("cxx boom");
	return sPlayer->_clockTime;
}

double PlayerEntity::clockTimeAdjusted()  { return sPlayer->_adjusted; }
bool PlayerEntity::clockAdjusting()  { return sPlayer->_adjusting; }
OOTimeDelta PlayerEntity::scriptTimer()  { return 42.5; }
std::string PlayerEntity::dial_clock()  { return oo::str::format("dial %.1f", sPlayer->_clockTime); }
void PlayerEntity::addToAdjustTime(double seconds)  { sPlayer->_added += seconds; }


/*	The universe is the C++ class since bead oo-ql9rn deleted its Objective-C facade, which the
	test's FakeUniverse stood in for. Universe.h is included (through the headers above) and
	Universe.mm is not linked, so the test defines the members the code under test calls, with the
	stand-in's bodies, and UNIVERSE is storage nothing constructs: those members read no state.
*/
OOTimeAbsolute Universe::getTime()  { return 1234.5; }

alignas(Universe) unsigned char sUniverseStorage[sizeof(Universe)];

Universe *gSharedUniverse = nil;

PlayerEntity *OOPlayerForScripting(void)
{
	return reinterpret_cast<PlayerEntity *>(sPlayer);	// never dereferenced: the members above answer
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
	ooscript::beginRequest(sContext);
	sGlobal = ooscript::getGlobalObject(sContext);
	ooscript::initStandardClasses(sContext, sGlobal);
	InitOOJSClock(sContext, sGlobal);
	sPlayer = new FakePlayer;	// never deleted
	gSharedUniverse = reinterpret_cast<Universe *>(sUniverseStorage);
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


// Eval, and print what came back when it is not what the check expects.
std::string EvalShown(const char *src, const char *expected)
{
	std::string result = Eval(src);
	if (result != expected)  std::printf("    %s\n    gave: %s\n", src, result.c_str());
	return result;
}
#define OO_CHECK_EVAL(src, expected)  OO_CHECK_EQ(EvalShown(src, expected), expected)


void SetClock(double seconds)
{
	SetUpContext();
	sPlayer->_clockTime = seconds;
}

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

OO_TEST(properties)
{
	// 3 days, 4 hours, 5 minutes, 6.5 seconds.
	SetClock(((3 * 24 + 4) * 60 + 5) * 60 + 6.5);
	sPlayer->_adjusted = 99.25;
	sPlayer->_adjusting = NO;
	OO_CHECK_EVAL("clock.absoluteSeconds", "1234.5");
	OO_CHECK_EVAL("clock.seconds", "273906.5");
	OO_CHECK_EVAL("clock.minutes", "4565");
	OO_CHECK_EVAL("clock.hours", "76");
	OO_CHECK_EVAL("clock.days", "3");
	OO_CHECK_EVAL("clock.secondsComponent", "6");
	OO_CHECK_EVAL("clock.minutesComponent", "5");
	OO_CHECK_EVAL("clock.hoursComponent", "4");
	OO_CHECK_EVAL("clock.daysComponent", "3");
	OO_CHECK_EVAL("clock.clockString", "dial 273906.5");
	OO_CHECK_EVAL("clock.isAdjusting", "false");
	sPlayer->_adjusting = YES;
	OO_CHECK_EVAL("clock.isAdjusting", "true");
	OO_CHECK_EVAL("typeof clock.isAdjusting", "boolean");
	OO_CHECK_EVAL("clock.adjustedSeconds", "99.25");
	int deprecations = sDeprecations;
	OO_CHECK_EVAL("clock.legacy_scriptTimer", "42.5");
	OO_CHECK_EQ(sDeprecations, deprecations + 1);
	OO_CHECK_EVAL("Object.keys(clock).length", "13");
	// Read-only.
	OO_CHECK_EVAL("(function () { clock.seconds = 5; return clock.seconds; })()", "273906.5");
}


OO_TEST(methods)
{
	SetClock(100);
	OO_CHECK_EVAL("clock.toString()", "dial 100.0");
	OO_CHECK_EVAL("String(clock)", "dial 100.0");
	OO_CHECK_EVAL("clock.clockStringForTime(3600)", "clock(3600, 0)");
	OO_CHECK_EVAL("clock.clockStringForTime('x')", "clock(nan, 0)");
	OO_CHECK_EVAL("clock.clockStringForTime()", "threw: bad arguments: Clock.clockStringForTime (1): ; expected number");
	sPlayer->_added = 0;
	OO_CHECK_EVAL("clock.addSeconds(60)", "true");
	OO_CHECK(sPlayer->_added == 60);
	OO_CHECK_EVAL("clock.addSeconds(0.5)", "false");
	OO_CHECK_EVAL("clock.addSeconds(31 * 24 * 3600)", "false");
	OO_CHECK_EVAL("clock.addSeconds(Infinity)", "false");
	OO_CHECK(sPlayer->_added == 60);
	OO_CHECK_EVAL("clock.addSeconds()", "threw: bad arguments: Clock.addSeconds (1): ; expected number");
	OO_CHECK_EVAL("new clock.constructor()", "threw: unconstructable");
}


OO_TEST(nativeExceptions)
{
	// The property getter is a native (OOJS_NATIVE_ENTER): a raise from the player is a JS error,
	// and so is a C++ exception.
	SetClock(-1);
	OO_CHECK_EVAL("clock.seconds", "threw: Native exception: clock boom");
	SetClock(-2);
	OO_CHECK_EVAL("clock.days", "threw: Native exception: cxx boom");
	SetClock(0);
	OO_CHECK_EVAL("clock.seconds", "0");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK(ooscript::isInRequest(sContext));
#if OOJS_PROFILE
	OO_CHECK_EQ(sProfileDepth, 0);
#endif
}


OO_TEST_MAIN()
