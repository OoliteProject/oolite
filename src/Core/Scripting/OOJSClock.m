/*

OOJSClock.m


Oolite
Copyright (C) 2004-2010 Giles C Williams and contributors

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
#import "OOJavaScriptEngine.h"
#import "Universe.h"
#import "OOJSPlayer.h"
#import "PlayerEntity.h"
#import "PlayerEntityScriptMethods.h"
#import "OOStringParsing.h"


static JSBool ClockGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);

// Methods
static JSBool JSClockToString(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ClockClockStringForTime(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ClockAddSeconds(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


static JSClass sClockClass =
{
	"Clock",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,		// addProperty
	JS_PropertyStub,		// delProperty
	ClockGetProperty,		// getProperty
	JS_PropertyStub,		// setProperty
	JS_EnumerateStub,		// enumerate
	JS_ResolveStub,			// resolve
	JS_ConvertStub,			// convert
	JS_FinalizeStub,		// finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
};


enum
{
	// Property IDs
	kClock_absoluteSeconds,		// game real time clock, double, read-only
	kClock_seconds,				// game clock time, double, read-only
	kClock_minutes,				// game clock time minutes (rounded down), integer double, read-only
	kClock_hours,				// game clock time hours (rounded down), integer double, read-only
	kClock_days,				// game clock time days (rounded down), int, read-only
	kClock_secondsComponent,	// second component of game clock time, double, read-only
	kClock_minutesComponent,	// minute component of game clock time (rounded down), int, read-only
	kClock_hoursComponent,		// hour component of game clock time (rounded down), int, read-only
	kClock_daysComponent,		// day component of game clock time (rounded down), int, read-only
	kClock_clockString,			// game clock time as display string, string, read-only
	kClock_isAdjusting,			// clock is adjusting, boolean, read-only
	kClock_legacy_scriptTimer	// legacy scriptTimer_number, double, read-only
};


static JSPropertySpec sClockProperties[] =
{
	// JS name					ID							flags
	{ "absoluteSeconds",		kClock_absoluteSeconds,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "seconds",				kClock_seconds,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "minutes",				kClock_minutes,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "hours",					kClock_hours,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "days",					kClock_days,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "secondsComponent",		kClock_secondsComponent,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "minutesComponent",		kClock_minutesComponent,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "hoursComponent",			kClock_hoursComponent,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "daysComponent",			kClock_daysComponent,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "clockString",			kClock_clockString,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isAdjusting",			kClock_isAdjusting,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "legacy_scriptTimer",		kClock_legacy_scriptTimer,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ 0 }
};


static JSFunctionSpec sClockMethods[] =
{
	// JS name						Function						min args
	{ "toString",				JSClockToString,			0 },
	{ "clockStringForTime",		ClockClockStringForTime,	1 },
	{ "addSeconds",				ClockAddSeconds,			1 },
	{ 0 }
};


void InitOOJSClock(JSContext *context, JSObject *global)
{
	JSObject *clockPrototype = JS_InitClass(context, global, NULL, &sClockClass, NULL, 0, sClockProperties, sClockMethods, NULL, NULL);
	JS_DefineObject(context, global, "clock", &sClockClass, clockPrototype, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
}


static JSBool ClockGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	if (!JSVAL_IS_INT(name))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	BOOL						OK = NO;
	PlayerEntity				*player = nil;
	double						clockTime;
	
	player = OOPlayerForScripting();
	clockTime = [player clockTime];
	
	switch (JSVAL_TO_INT(name))
	{
		case kClock_absoluteSeconds:
			OK = JS_NewDoubleValue(context, [UNIVERSE getTime], outValue);
			break;
			
		case kClock_seconds:
			OK = JS_NewDoubleValue(context, clockTime, outValue);
			break;
			
		case kClock_minutes:
			OK = JS_NewDoubleValue(context, floor(clockTime / 60.0), outValue);
			break;
			
		case kClock_hours:
			OK = JS_NewDoubleValue(context, floor(clockTime / 3600.0), outValue);
			break;
			
		case kClock_secondsComponent:
			*outValue = INT_TO_JSVAL(fmod(clockTime, 60.0));
			OK = YES;
			break;
			
		case kClock_minutesComponent:
			*outValue = INT_TO_JSVAL(fmod(floor(clockTime / 60.0), 60.0));
			OK = YES;
			break;
			
		case kClock_hoursComponent:
			*outValue = INT_TO_JSVAL(fmod(floor(clockTime / 3600.0), 24.0));
			OK = YES;
			break;
			
		case kClock_days:
		case kClock_daysComponent:
			*outValue = INT_TO_JSVAL(floor(clockTime / 86400.0));
			OK = YES;
			break;
			
		case kClock_clockString:
			*outValue = [[player dial_clock] javaScriptValueInContext:context];
			OK = YES;
			break;
			
		case kClock_isAdjusting:
			*outValue = BOOLToJSVal([player clockAdjusting]);
			OK = YES;
			break;
			
		case kClock_legacy_scriptTimer:
			OK = JS_NewDoubleValue(context, [OOPlayerForScripting() scriptTimer], outValue);
			break;
			
		default:
			OOReportJSBadPropertySelector(context, @"Clock", JSVAL_TO_INT(name));
	}
	
	return OK;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

// toString() : String
static JSBool JSClockToString(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	*outResult = [[OOPlayerForScripting() dial_clock] javaScriptValueInContext:context];
	return YES;
	
	OOJS_NATIVE_EXIT
}


// clockStringForTime(time : Number) : String
static JSBool ClockClockStringForTime(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	double						time;
	
	if (EXPECT_NOT(!JS_ValueToNumber(context, argv[0], &time)))  return NO;
	
	*outResult = [ClockToString(time, NO) javaScriptValueInContext:context];
	return YES;
	
	OOJS_NATIVE_EXIT
}


// clockAddSeconds(seconds : Number) : String
static JSBool ClockAddSeconds(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	double						time;
	
	if (EXPECT_NOT(!JS_ValueToNumber(context, argv[0], &time)))  return YES;	// no-op
	if (time > 2592000.0f || time < 1.0f)	// 30 * 24 * 3600
	{
		OOReportJSWarning(context, @"Clock.addSeconds: use a value between 1 and 2592000 (30 days).");

		*outResult = JSVAL_FALSE;
		return YES;
	}
	
	[OOPlayerForScripting() addToAdjustTime:time];
	
	*outResult = JSVAL_TRUE;
	return YES;
	
	OOJS_NATIVE_EXIT
}
