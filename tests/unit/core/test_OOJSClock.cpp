/*	test_OOJSClock.mm
        Unit tests for the clock JS binding
   (src/Core/Scripting/OOJSClock.h/.mm).

        Like test_OOJSVector.mm, it runs the JS class in a real QuickJS-ng
   context and links the game's own objects for the binding, the class
   registration (OOJSClasses.mm) and the engine's exception translator
   (OOJSEngineNativeWrappers.mm). What the rest of the game would provide (the
   player's clock, the universe's time, the clock-string formatter, the
   deprecation warning, error reporting and the string helpers) is defined below
   as the smallest stand-in that does the same thing. The tests pin the
        JS-visible behaviour: the global `clock` object and every property, the
   three methods, their errors, and how an exception under a native reaches JS.
        Run: tests/run.sh unit
*/

#include <cstdarg>
#include <cstring>
#include <stdexcept>
#include <string>

#include "OODebugStandards.h"
#include "OOJSClock.h"
#include "OOJSPlayer.h"
#include "OOJavaScriptEngine.h"
#include "OOStringParsing.h"
#include "Universe.h"
#include "oo_test.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOException.h"

// MARK: What the rest of the engine provides
// ------------------------------------------------------

JSContext* gOOJSMainThreadContext = NULL;  // the engine's

void OOJSReportErrorWithArguments(JSContext* context, const char* format,
                                      va_list args) {
  std::string msg = oo::str::vformat(format, args);
  JS_ThrowPlainError(context, "%s", msg.c_str());
}

void OOJSReportError(JSContext* context, const char* format, ...) {
  va_list args;
  va_start(args, format);
  OOJSReportErrorWithArguments(context, format, args);
  va_end(args);
}

void OOJSReportBadArguments(
    JSContext* context, const std::optional<std::string>& scriptClass,
    const std::optional<std::string>& function, int argc, JSValueConst*,
    const std::optional<std::string>& message,
    const std::optional<std::string>& expectedArgsDescription) {
  OOJSReportError(context, "bad arguments: %s.%s (%d): %s; expected %s",
                      scriptClass.value_or("").c_str(),
                      function.value_or("").c_str(), argc,
                      message.value_or("").c_str(),
                      expectedArgsDescription.value_or("").c_str());
}

void OOJSReportBadPropertySelector(JSContext* context, JSValueConst, int,
                                   const JSCFunctionListEntry*, size_t) {
  OOJSReportError(context, "bad property selector");
}

std::optional<std::string> OOStringFromJSValue(JSContext* context,
                                                   JSValueConst value) {
  if (JS_IsNull(value) || JS_IsUndefined(value)) return std::nullopt;
  std::size_t length = 0;
  const char* chars = JS_ToCStringLen(context, &length, value);
  if (chars == NULL) {
    JS_FreeValue(context, JS_GetException(context));
    return std::nullopt;
  }
  std::string result(chars, length);
  JS_FreeCString(context, chars);
  return result;
}

JSValue OOJSValueFromPList(JSContext* context, const oo::PList& plist) {
  const std::string* str = plist.getIf<std::string>();
  return str != nullptr ? JS_NewStringLen(context, str->data(), str->size())
                        : JS_NULL;
}

JSValue OOJSUnconstructableConstruct(JSContext* context, JSValueConst, int,
                                     JSValueConst*) {
  OOJSReportError(context, "unconstructable");
  return JS_EXCEPTION;
}

// What the class registration (OOJSClasses.mm) asks of the engine.
void OOJSReportPendingException(JSContext* context) {
  JS_FreeValue(context, JS_GetException(context));
}

JSAtom OOJSIDFromString(const std::string& string) {
  return JS_NewAtom(OOJSAcquireContext(), string.c_str());
}

#if OOJS_PROFILE
namespace {
int sProfileDepth = 0;
}  // namespace

void OOJSProfileEnter(OOJSProfileStackFrame*, const char*) { sProfileDepth++; }
void OOJSProfileExit(OOJSProfileStackFrame*) { sProfileDepth--; }
#endif

namespace {
int sLimiterPauses = 0;
int sDeprecations = 0;
}  // namespace

void OOJSPauseTimeLimiter(void) { sLimiterPauses++; }
void OOJSResumeTimeLimiter(void) { sLimiterPauses--; }

#ifndef NDEBUG
void OOJSUnreachable(const char* function, const char*, unsigned) {
  std::printf("unreachable reached in %s\n", function);
  abort();
}
#endif

void OOStandardsDeprecated(const std::string&) { sDeprecations++; }

// The formatter, as far as the clock sees it: what it was asked for.
std::string ClockToString(double clock, bool adjusting) {
  return oo::str::format("clock(%g, %d)", clock, adjusting ? 1 : 0);
}

/*	The player, as far as the clock sees it: the clock selectors. A clock
   time of -1 makes -clockTime raise, -2 makes it throw a C++ exception, so the
   test sees what an exception under a native becomes.
*/
/*	PLAYER: The binding calls the members below (PlayerEntity.h, which the
   engine's header imports, declares them), which answer from the FakePlayer's
   values; the binding never reads the player's own state, so PLAYER is a
   FakePlayer's address.
*/
struct FakePlayer {
  double _clockTime = 0;
  double _adjusted = 0;
  double _added = 0;
  bool _adjusting = false;
};

namespace {
FakePlayer* sPlayer = nullptr;
}  // namespace

double PlayerEntity::clockTime() {
  if (sPlayer->_clockTime == -1)
    OORaiseException(OOInvalidArgumentException, "clock %s", "boom");
  if (sPlayer->_clockTime == -2) throw std::runtime_error("cxx boom");
  return sPlayer->_clockTime;
}

double PlayerEntity::clockTimeAdjusted() { return sPlayer->_adjusted; }
bool PlayerEntity::clockAdjusting() { return sPlayer->_adjusting; }
OOTimeDelta PlayerEntity::scriptTimer() { return 42.5; }
std::string PlayerEntity::dial_clock() {
  return oo::str::format("dial %.1f", sPlayer->_clockTime);
}
void PlayerEntity::addToAdjustTime(double seconds) {
  sPlayer->_added += seconds;
}

/*	The universe is the C++ class. Universe.h is included (through the
   headers above) and Universe.mm is not linked, so the
   test defines the members the code under test calls, with the stand-in's
   bodies, and UNIVERSE is storage nothing constructs: those members read no
   state.
*/
OOTimeAbsolute Universe::getTime() { return 1234.5; }

alignas(Universe) unsigned char sUniverseStorage[sizeof(Universe)];

Universe* gSharedUniverse = nullptr;

PlayerEntity* OOPlayerForScripting(void) {
  return reinterpret_cast<PlayerEntity*>(
      sPlayer);  // never dereferenced: the members above answer
}

// MARK: The context
// -------------------------------------------------------------------------------

namespace {

JSContext* sContext = NULL;

void SetUpContext() {
  if (sContext != NULL) return;
  sContext = JS_NewContext(JS_NewRuntime());
  gOOJSMainThreadContext = sContext;  // the class registration's runtime
  JSValue global = JS_GetGlobalObject(sContext);
  InitOOJSClock(sContext, global);
  JS_FreeValue(sContext, global);
  sPlayer = new FakePlayer;  // never deleted
  gSharedUniverse = reinterpret_cast<Universe*>(sUniverseStorage);
}

// Evaluates src and gives its result as a string ("undefined", "null", ...), or
// "threw: <message>".
std::string Eval(const char* src) {
  SetUpContext();
  std::string wrapped = std::string("(function () { try { return String(") +
                        src +
                        "); } catch (e) { return 'threw: ' + (e && e.message "
                        "!== undefined ? e.message : e); } })()";
  JSValue result = JS_Eval(sContext, wrapped.c_str(), wrapped.size(), "test.js",
                           JS_EVAL_TYPE_GLOBAL);
  if (JS_IsException(result)) {
    JS_FreeValue(sContext, JS_GetException(sContext));
    return "<evaluation failed>";
  }
  std::string text =
      OOStringFromJSValue(sContext, result).value_or("<not a string>");
  JS_FreeValue(sContext, result);
  return text;
}

// Eval, and print what came back when it is not what the check expects.
std::string EvalShown(const char* src, const char* expected) {
  std::string result = Eval(src);
  if (result != expected)
    std::printf("    %s\n    gave: %s\n", src, result.c_str());
  return result;
}
#define OO_CHECK_EVAL(src, expected) \
  OO_CHECK_EQ(EvalShown(src, expected), expected)

void SetClock(double seconds) {
  SetUpContext();
  sPlayer->_clockTime = seconds;
}

}  // namespace

// MARK: Tests
// -------------------------------------------------------------------------------------

OO_TEST(properties) {
  // 3 days, 4 hours, 5 minutes, 6.5 seconds.
  SetClock(((3 * 24 + 4) * 60 + 5) * 60 + 6.5);
  sPlayer->_adjusted = 99.25;
  sPlayer->_adjusting = false;
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
  sPlayer->_adjusting = true;
  OO_CHECK_EVAL("clock.isAdjusting", "true");
  OO_CHECK_EVAL("typeof clock.isAdjusting", "boolean");
  OO_CHECK_EVAL("clock.adjustedSeconds", "99.25");
  int deprecations = sDeprecations;
  OO_CHECK_EVAL("clock.legacy_scriptTimer", "42.5");
  OO_CHECK_EQ(sDeprecations, deprecations + 1);
  OO_CHECK_EVAL("Object.keys(clock).length", "13");
  // Read-only.
  OO_CHECK_EVAL("(function () { clock.seconds = 5; return clock.seconds; })()",
                "273906.5");
}

OO_TEST(methods) {
  SetClock(100);
  OO_CHECK_EVAL("clock.toString()", "dial 100.0");
  OO_CHECK_EVAL("String(clock)", "dial 100.0");
  OO_CHECK_EVAL("clock.clockStringForTime(3600)", "clock(3600, 0)");
  OO_CHECK_EVAL("clock.clockStringForTime('x')", "clock(nan, 0)");
  OO_CHECK_EVAL(
      "clock.clockStringForTime()",
      "threw: bad arguments: Clock.clockStringForTime (1): ; expected number");
  sPlayer->_added = 0;
  OO_CHECK_EVAL("clock.addSeconds(60)", "true");
  OO_CHECK(sPlayer->_added == 60);
  OO_CHECK_EVAL("clock.addSeconds(0.5)", "false");
  OO_CHECK_EVAL("clock.addSeconds(31 * 24 * 3600)", "false");
  OO_CHECK_EVAL("clock.addSeconds(Infinity)", "false");
  OO_CHECK(sPlayer->_added == 60);
  OO_CHECK_EVAL(
      "clock.addSeconds()",
      "threw: bad arguments: Clock.addSeconds (1): ; expected number");
  OO_CHECK_EVAL("new clock.constructor()", "threw: unconstructable");
}

OO_TEST(nativeExceptions) {
  // The property getter is a native (OOJS_NATIVE_ENTER): a raise from the
  // player is a JS error, and so is a C++ exception.
  SetClock(-1);
  OO_CHECK_EVAL("clock.seconds", "threw: Native exception: clock boom");
  SetClock(-2);
  OO_CHECK_EVAL("clock.days", "threw: Native exception: cxx boom");
  SetClock(0);
  OO_CHECK_EVAL("clock.seconds", "0");
  OO_CHECK_EQ(sLimiterPauses, 0);
#if OOJS_PROFILE
  OO_CHECK_EQ(sProfileDepth, 0);
#endif
}

OO_TEST_MAIN()
