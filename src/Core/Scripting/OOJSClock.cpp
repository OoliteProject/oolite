/*

OOJSClock.m


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#include "OOJSClock.h"

#include "OODebugStandards.h"
#include "OOJSPlayer.h"
#include "OOJavaScriptEngine.h"
#include "OOStringParsing.h"
#include "PlayerEntity.h"
#include "PlayerEntityScriptMethods.h"
#include "Universe.h"

static JSValue ClockGetProperty(OOJS_GETTER_ARGS);

// Methods
static JSValue JSClockToString(OOJS_NATIVE_ARGS);
static JSValue ClockClockStringForTime(OOJS_NATIVE_ARGS);
static JSValue ClockAddSeconds(OOJS_NATIVE_ARGS);

static JSClassID sClockClassID;
static JSClassDef sClockClass = {
    .class_name = "Clock",
};

namespace {

enum class ClockProperty : std::int16_t {
  // Property IDs
  kAbsoluteSeconds,   // game real time clock, double, read-only
  kSeconds,           // game clock time, double, read-only
  kMinutes,           // game clock time minutes (rounded down), integer double,
                      // read-only
  kHours,             // game clock time hours (rounded down), integer double,
                      // read-only
  kDays,              // game clock time days (rounded down), int, read-only
  kSecondsComponent,  // second component of game clock time, double,
                      // read-only
  kMinutesComponent,  // minute component of game clock time (rounded
                      // down), int, read-only
  kHoursComponent,    // hour component of game clock time (rounded down),
                      // int, read-only
  kDaysComponent,     // day component of game clock time (rounded down),
                      // int, read-only
  kClockString,       // game clock time as display string, string, read-only
  kIsAdjusting,       // clock is adjusting, boolean, read-only
  kAdjustedSeconds,   // game clock time, including adjustments, double,
                      // read-only
  kLegacy_scriptTimer  // legacy scriptTimer_number, double, read-only
};

}  // namespace

static const JSCFunctionListEntry sClockProperties[] = {
    // JS name					Getter ID
    OOJS_PROPERTY_RO("absoluteSeconds", ClockGetProperty,
                     ClockProperty::kAbsoluteSeconds),
    OOJS_PROPERTY_RO("seconds", ClockGetProperty, ClockProperty::kSeconds),
    OOJS_PROPERTY_RO("minutes", ClockGetProperty, ClockProperty::kMinutes),
    OOJS_PROPERTY_RO("hours", ClockGetProperty, ClockProperty::kHours),
    OOJS_PROPERTY_RO("days", ClockGetProperty, ClockProperty::kDays),
    OOJS_PROPERTY_RO("secondsComponent", ClockGetProperty,
                     ClockProperty::kSecondsComponent),
    OOJS_PROPERTY_RO("minutesComponent", ClockGetProperty,
                     ClockProperty::kMinutesComponent),
    OOJS_PROPERTY_RO("hoursComponent", ClockGetProperty,
                     ClockProperty::kHoursComponent),
    OOJS_PROPERTY_RO("daysComponent", ClockGetProperty,
                     ClockProperty::kDaysComponent),
    OOJS_PROPERTY_RO("clockString", ClockGetProperty,
                     ClockProperty::kClockString),
    OOJS_PROPERTY_RO("isAdjusting", ClockGetProperty,
                     ClockProperty::kIsAdjusting),
    OOJS_PROPERTY_RO("adjustedSeconds", ClockGetProperty,
                     ClockProperty::kAdjustedSeconds),
    OOJS_PROPERTY_RO("legacy_scriptTimer", ClockGetProperty,
                     ClockProperty::kLegacy_scriptTimer),
};

static const JSCFunctionListEntry sClockMethods[] = {
    // JS name						Function
    // min args
    JS_CFUNC_DEF("toString", 0, JSClockToString),
    JS_CFUNC_DEF("clockStringForTime", 1, ClockClockStringForTime),
    JS_CFUNC_DEF("addSeconds", 1, ClockAddSeconds),
};

void InitOOJSClock(JSContext* context, JSValueConst global) {
  OOJSRegisterClass(&sClockClassID, &sClockClass);
  JSValueConst clockPrototype =
      OOJSInitClass(context, global, sClockClassID, JS_UNDEFINED,
                    OOJSUnconstructableConstruct, 0, sClockProperties,
                    OOJS_COUNT(sClockProperties), sClockMethods,
                    OOJS_COUNT(sClockMethods), nullptr, 0);
  JS_DefinePropertyValueStr(
      context, global, "clock",
      JS_NewObjectProtoClass(context, clockPrototype, sClockClassID),
      OOJS_PROP_READONLY);
}

static JSValue ClockGetProperty(OOJS_GETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();
  double clockTime;

  clockTime = (player != nullptr ? player->PlayerEntity::clockTime()
                                 : 0.0);  // qualified: the final overrider, so
                                          // the binding test stands in for it

  /*	INT_TO_JSVAL() truncated its (double) argument to an integer;
     JS_NewInt32() does the same through the implicit conversion.
  */
  switch (static_cast<ClockProperty>(magic)) {
    using enum ClockProperty;
    case kAbsoluteSeconds:
      return JS_NewNumber(context,
                          (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0));

    case kSeconds:
      return JS_NewNumber(context, clockTime);

    case kMinutes:
      return JS_NewNumber(context, floor(clockTime / 60.0));

    case kHours:
      return JS_NewNumber(context, floor(clockTime / 3600.0));

    case kSecondsComponent:
      return JS_NewInt32(context, fmod(clockTime, 60.0));

    case kMinutesComponent:
      return JS_NewInt32(context, fmod(floor(clockTime / 60.0), 60.0));

    case kHoursComponent:
      return JS_NewInt32(context, fmod(floor(clockTime / 3600.0), 24.0));

    case kDays:
    case kDaysComponent:
      return JS_NewInt32(context, floor(clockTime / 86400.0));

    case kClockString:
      return OOJSValueFromPList(
          context, oo::PList((player != nullptr ? player->dial_clock()
                                                : std::string())));

    case kIsAdjusting:
      return OOJSValueFromBOOL(
          (player != nullptr ? player->clockAdjusting() : false));

    case kAdjustedSeconds:
      return JS_NewNumber(
          context,
          (player != nullptr ? player->PlayerEntity::clockTimeAdjusted()
                             : 0.0));  // qualified: the final overrider, so the
                                       // binding test stands in for it

    case kLegacy_scriptTimer:
      cxx_OOStandardsDeprecated(
          "The legacy_scriptTimer property is deprecated");
      return JS_NewNumber(
          context, (player != nullptr ? player->scriptTimer() : OOTimeDelta{}));

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic, sClockProperties,
                                    OOJS_COUNT(sClockProperties));
      return JS_EXCEPTION;
  }

  OOJS_NATIVE_EXIT
}

// *** Methods ***

// toString() : String
static JSValue JSClockToString(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();
  OOJS_RETURN_PLIST(
      oo::PList(player != nullptr ? player->dial_clock() : std::string()));

  OOJS_NATIVE_EXIT
}

// clockStringForTime(time : Number) : String
static JSValue ClockClockStringForTime(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  double time;

  if (EXPECT_NOT(argc < 1 || JS_ToFloat64(context, &time, OOJS_ARGV[0]) < 0)) {
    if (JS_HasException(context))
      JS_FreeValue(context, JS_GetException(context));
    JSValueConst arg = JS_UNDEFINED;
    if (argc > 0) arg = OOJS_ARGV[0];
    cxx_OOJSReportBadArguments(context, "Clock", "clockStringForTime", 1, &arg,
                               std::nullopt, "number");
    return JS_EXCEPTION;
  }

  OOJS_RETURN(
      OOJSValueFromPList(context, oo::PList(cxx_ClockToString(time, false))));

  OOJS_NATIVE_EXIT
}

// addSeconds(seconds : Number) : String
static JSValue ClockAddSeconds(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  double time;
  const double kMaxTime = 30.0 * 24.0 * 3600.0;  // 30 days

  if (EXPECT_NOT(argc < 1 || JS_ToFloat64(context, &time, OOJS_ARGV[0]) < 0)) {
    if (JS_HasException(context))
      JS_FreeValue(context, JS_GetException(context));
    JSValueConst arg = JS_UNDEFINED;
    if (argc > 0) arg = OOJS_ARGV[0];
    cxx_OOJSReportBadArguments(context, "Clock", "addSeconds", 1, &arg,
                               std::nullopt, "number");
    return JS_EXCEPTION;
  }

  if (time > kMaxTime || time < 1.0 || !isfinite(time)) {
    OOJS_RETURN_BOOL(false);
  }

  if (PlayerEntity* player = OOPlayerForScripting())
    player->addToAdjustTime(time);

  OOJS_RETURN_BOOL(true);

  OOJS_NATIVE_EXIT
}
