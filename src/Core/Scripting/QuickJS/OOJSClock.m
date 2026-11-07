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

#import "OOJSClock.h"
#import "OODebugStandards.h"
#import "OOJSPlayer.h"
#import "OOJavaScriptEngine.h"
#import "OOStringParsing.h"
#import "PlayerEntity.h"
#import "PlayerEntityScriptMethods.h"
#import "Universe.h"

static JSValue ClockGetProperty(OOJS_GETTER_ARGS);

// Methods
static JSValue JSClockToString(OOJS_NATIVE_ARGS);
static JSValue ClockClockStringForTime(OOJS_NATIVE_ARGS);
static JSValue ClockAddSeconds(OOJS_NATIVE_ARGS);

static JSClassID sClockClassID;
static JSClassDef sClockClass = {
    .class_name = "Clock",
};

enum {
    // Property IDs
    kClock_absoluteSeconds, // game real time clock, double, read-only
    kClock_seconds, // game clock time, double, read-only
    kClock_minutes, // game clock time minutes (rounded down), integer double, read-only
    kClock_hours, // game clock time hours (rounded down), integer double, read-only
    kClock_days, // game clock time days (rounded down), int, read-only
    kClock_secondsComponent, // second component of game clock time, double, read-only
    kClock_minutesComponent, // minute component of game clock time (rounded down), int, read-only
    kClock_hoursComponent, // hour component of game clock time (rounded down), int, read-only
    kClock_daysComponent, // day component of game clock time (rounded down), int, read-only
    kClock_clockString, // game clock time as display string, string, read-only
    kClock_isAdjusting, // clock is adjusting, boolean, read-only
    kClock_adjustedSeconds, // game clock time, including adjustments, double, read-only
    kClock_legacy_scriptTimer // legacy scriptTimer_number, double, read-only
};

static const JSCFunctionListEntry sClockProperties[] = {
    // JS name					Getter				ID
    OOJS_PROPERTY_RO("absoluteSeconds", ClockGetProperty, kClock_absoluteSeconds),
    OOJS_PROPERTY_RO("seconds", ClockGetProperty, kClock_seconds),
    OOJS_PROPERTY_RO("minutes", ClockGetProperty, kClock_minutes),
    OOJS_PROPERTY_RO("hours", ClockGetProperty, kClock_hours),
    OOJS_PROPERTY_RO("days", ClockGetProperty, kClock_days),
    OOJS_PROPERTY_RO("secondsComponent", ClockGetProperty, kClock_secondsComponent),
    OOJS_PROPERTY_RO("minutesComponent", ClockGetProperty, kClock_minutesComponent),
    OOJS_PROPERTY_RO("hoursComponent", ClockGetProperty, kClock_hoursComponent),
    OOJS_PROPERTY_RO("daysComponent", ClockGetProperty, kClock_daysComponent),
    OOJS_PROPERTY_RO("clockString", ClockGetProperty, kClock_clockString),
    OOJS_PROPERTY_RO("isAdjusting", ClockGetProperty, kClock_isAdjusting),
    OOJS_PROPERTY_RO("adjustedSeconds", ClockGetProperty, kClock_adjustedSeconds),
    OOJS_PROPERTY_RO("legacy_scriptTimer", ClockGetProperty, kClock_legacy_scriptTimer),
};

static const JSCFunctionListEntry sClockMethods[] = {
    // JS name						Function						min args
    JS_CFUNC_DEF("toString", 0, JSClockToString),
    JS_CFUNC_DEF("clockStringForTime", 1, ClockClockStringForTime),
    JS_CFUNC_DEF("addSeconds", 1, ClockAddSeconds),
};

void InitOOJSClock(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sClockClassID, &sClockClass);
    JSValueConst clockPrototype = OOJSInitClass(context, global, sClockClassID, JS_UNDEFINED, OOJSUnconstructableConstruct, 0,
        sClockProperties, OOJS_COUNT(sClockProperties), sClockMethods, OOJS_COUNT(sClockMethods), NULL, 0);
    JS_DefinePropertyValueStr(context, global, "clock", JS_NewObjectProtoClass(context, clockPrototype, sClockClassID), OOJS_PROP_READONLY);
}

static JSValue ClockGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    double clockTime;

    clockTime = [player clockTime];

    /*	INT_TO_JSVAL() truncated its (double) argument to an integer; JS_NewInt32()
            does the same through the implicit conversion.
    */
    switch (magic) {
    case kClock_absoluteSeconds:
        return JS_NewNumber(context, [UNIVERSE getTime]);

    case kClock_seconds:
        return JS_NewNumber(context, clockTime);

    case kClock_minutes:
        return JS_NewNumber(context, floor(clockTime / 60.0));

    case kClock_hours:
        return JS_NewNumber(context, floor(clockTime / 3600.0));

    case kClock_secondsComponent:
        return JS_NewInt32(context, fmod(clockTime, 60.0));

    case kClock_minutesComponent:
        return JS_NewInt32(context, fmod(floor(clockTime / 60.0), 60.0));

    case kClock_hoursComponent:
        return JS_NewInt32(context, fmod(floor(clockTime / 3600.0), 24.0));

    case kClock_days:
    case kClock_daysComponent:
        return JS_NewInt32(context, floor(clockTime / 86400.0));

    case kClock_clockString:
        return OOJSValueFromNativeObject(context, [player dial_clock]);

    case kClock_isAdjusting:
        return OOJSValueFromBOOL([player clockAdjusting]);

    case kClock_adjustedSeconds:
        return JS_NewNumber(context, [player clockTimeAdjusted]);

    case kClock_legacy_scriptTimer:
        OOStandardsDeprecated(@"The legacy_scriptTimer property is deprecated");
        return JS_NewNumber(context, [player scriptTimer]);

    default:
        OOJSReportBadPropertySelector(context, this, magic, sClockProperties, OOJS_COUNT(sClockProperties));
        return JS_EXCEPTION;
    }

    OOJS_NATIVE_EXIT
}

// *** Methods ***

// toString() : String
static JSValue JSClockToString(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOJS_RETURN_OBJECT([OOPlayerForScripting() dial_clock]);

    OOJS_NATIVE_EXIT
}

// clockStringForTime(time : Number) : String
static JSValue ClockClockStringForTime(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    double time;

    if (EXPECT_NOT(argc < 1 || JS_ToFloat64(context, &time, OOJS_ARGV[0]) < 0)) {
        if (JS_HasException(context))
            JS_FreeValue(context, JS_GetException(context));
        JSValueConst arg = JS_UNDEFINED;
        if (argc > 0)
            arg = OOJS_ARGV[0];
        OOJSReportBadArguments(context, @"Clock", @"clockStringForTime", 1, &arg, nil, @"number");
        return JS_EXCEPTION;
    }

    OOJS_RETURN_OBJECT(ClockToString(time, NO));

    OOJS_NATIVE_EXIT
}

// addSeconds(seconds : Number) : String
static JSValue ClockAddSeconds(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    double time;
    const double kMaxTime = 30.0 * 24.0 * 3600.0; // 30 days

    if (EXPECT_NOT(argc < 1 || JS_ToFloat64(context, &time, OOJS_ARGV[0]) < 0)) {
        if (JS_HasException(context))
            JS_FreeValue(context, JS_GetException(context));
        JSValueConst arg = JS_UNDEFINED;
        if (argc > 0)
            arg = OOJS_ARGV[0];
        OOJSReportBadArguments(context, @"Clock", @"addSeconds", 1, &arg, nil, @"number");
        return JS_EXCEPTION;
    }

    if (time > kMaxTime || time < 1.0 || !isfinite(time)) {
        OOJS_RETURN_BOOL(NO);
    }

    [OOPlayerForScripting() addToAdjustTime:time];

    OOJS_RETURN_BOOL(YES);

    OOJS_NATIVE_EXIT
}
