/*

OOJSClock.mm


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
#include "OOJavaScriptEngine.h"
#include "Universe.h"
#include "OOJSPlayer.h"
#include "PlayerEntity.h"
#include "PlayerEntityScriptMethods.h"
#include "OOStringParsing.h"
#include "OODebugStandards.h"

#include "ooscript/JSEngine.hpp"
#include <cstring>

/*
	Retargeted onto the ooscript façade (JSEngine.hpp) the way OOJSVector.mm does it (bead
	oo-sdz, the sweep exemplar): the class dispatch table becomes a static ooscript::ClassDef
	(the stub hooks are nullptr), InitClass becomes ooscript::initClass, the engine's
	DefineObject call becomes ooscript::defineObject, and the directly spelled numeric-conversion call becomes
	ooscript::newNumberValue. `this` is renamed to `thisObj` because it is a reserved word once
	this file compiles as Objective-C++ (ADR-0001). Natives take the façade signature
	(Context, CallArgs reference) directly, and the OOJS_* argument-marshalling macros
	(OOJS_NATIVE_ENTER, OOJS_ARGV, OOJS_RETURN_*) expand to the CallArgs accessors.
*/

/*
	C++20 since bead oo-xy5r, converted the way bead oo-ppc converted OOJSVector.mm (proposed
	ADR-0056 amendment oo-ppc). The JS class was already C++ on the ooscript façade;
	OOJS_NATIVE_ENTER/EXIT are a C++ try/catch (OOJSEngineNativeWrappers.h) and BOOL/YES/NO are
	bool/true/false. The file has no category, so there is no bridge. Messages to classes that are
	still Objective-C (PlayerEntity, Universe) stay as they are, which is why the file is still
	.mm until Phase 4.
*/
namespace ooscript { }
using ooscript::Context;
using ooscript::Object;
using ooscript::Value;
using ooscript::PropertyId;
using ooscript::CallArgs;
using ooscript::ClassDef;
using ooscript::ClassFlag;
using ooscript::PropertyFlag;
using ooscript::PropertySpec;
using ooscript::FunctionSpec;

namespace {
static bool ClockGetProperty(Context cx, Object obj, PropertyId propID, Value *value);
} // namespace

// Methods
namespace {
static bool JSClockToString(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool ClockClockStringForTime(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool ClockAddSeconds(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace


namespace {
static ClassDef sClockClass =
{
	"Clock",
	ClassFlag::HasPrivate,

	nullptr,			// addProperty (engine default: PropertyStub)
	nullptr,			// delProperty (engine default: PropertyStub)
	ClockGetProperty,	// getProperty
	nullptr,			// setProperty (engine default: StrictPropertyStub)
	nullptr,			// enumerate (engine default: EnumerateStub)
	nullptr,			// newEnumerate (ooscript::ClassFlag::NewEnumerate not used)
	nullptr,			// resolve (engine default: ResolveStub)
	nullptr,			// convert (engine default: ConvertStub)
	nullptr,			// finalize (engine default: FinalizeStub)
	nullptr,			// call
	nullptr,			// construct
	nullptr,			// backend: owned by the façade backend, must start null
};
} // namespace


enum : std::uint8_t
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
	kClock_adjustedSeconds,	// game clock time, including adjustments, double, read-only
	kClock_legacy_scriptTimer	// legacy scriptTimer_number, double, read-only
};


// A mirror of the property table with the read-only flags the property-selector error reporter
// in OOJavaScriptEngine.mm (OOJSReportBadPropertySelector) describes the properties by (see
// OOJSVector.mm's sVectorPropertiesRaw); initClass() is given sClockPropertiesFacade.
namespace {
static ooscript::PropertySpec sClockProperties[] =
{
	// JS name					ID							flags
	{ "absoluteSeconds",		kClock_absoluteSeconds,		OOJS_PROP_READONLY_CB },
	{ "seconds",				kClock_seconds,				OOJS_PROP_READONLY_CB },
	{ "minutes",				kClock_minutes,				OOJS_PROP_READONLY_CB },
	{ "hours",					kClock_hours,				OOJS_PROP_READONLY_CB },
	{ "days",					kClock_days,				OOJS_PROP_READONLY_CB },
	{ "secondsComponent",		kClock_secondsComponent,	OOJS_PROP_READONLY_CB },
	{ "minutesComponent",		kClock_minutesComponent,	OOJS_PROP_READONLY_CB },
	{ "hoursComponent",			kClock_hoursComponent,		OOJS_PROP_READONLY_CB },
	{ "daysComponent",			kClock_daysComponent,		OOJS_PROP_READONLY_CB },
	{ "clockString",			kClock_clockString,			OOJS_PROP_READONLY_CB },
	{ "isAdjusting",			kClock_isAdjusting,			OOJS_PROP_READONLY_CB },
	{ "adjustedSeconds",			kClock_adjustedSeconds,			OOJS_PROP_READONLY_CB },
	{ "legacy_scriptTimer",		kClock_legacy_scriptTimer,	OOJS_PROP_READONLY_CB },
	{ 0 }
};
} // namespace


namespace {
constexpr PropertyFlag kClockPropertyFlags = PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared;
} // namespace


namespace {
static PropertySpec sClockPropertiesFacade[] =
{
	// JS name					ID							flags					getter	setter
	{ "absoluteSeconds",		kClock_absoluteSeconds,		kClockPropertyFlags,	nullptr, nullptr },
	{ "seconds",				kClock_seconds,				kClockPropertyFlags,	nullptr, nullptr },
	{ "minutes",				kClock_minutes,				kClockPropertyFlags,	nullptr, nullptr },
	{ "hours",					kClock_hours,				kClockPropertyFlags,	nullptr, nullptr },
	{ "days",					kClock_days,				kClockPropertyFlags,	nullptr, nullptr },
	{ "secondsComponent",		kClock_secondsComponent,	kClockPropertyFlags,	nullptr, nullptr },
	{ "minutesComponent",		kClock_minutesComponent,	kClockPropertyFlags,	nullptr, nullptr },
	{ "hoursComponent",			kClock_hoursComponent,		kClockPropertyFlags,	nullptr, nullptr },
	{ "daysComponent",			kClock_daysComponent,		kClockPropertyFlags,	nullptr, nullptr },
	{ "clockString",			kClock_clockString,			kClockPropertyFlags,	nullptr, nullptr },
	{ "isAdjusting",			kClock_isAdjusting,			kClockPropertyFlags,	nullptr, nullptr },
	{ "adjustedSeconds",			kClock_adjustedSeconds,			kClockPropertyFlags,	nullptr, nullptr },
	{ "legacy_scriptTimer",		kClock_legacy_scriptTimer,	kClockPropertyFlags,	nullptr, nullptr },
	{ 0 }
};
} // namespace


namespace {
static FunctionSpec sClockMethods[] =
{
	// JS name						Function						min args
	{ "toString",				JSClockToString,			0 },
	{ "clockStringForTime",		ClockClockStringForTime,	1 },
	{ "addSeconds",				ClockAddSeconds,			1 },
	{ 0 }
};
} // namespace


namespace {
constexpr PropertyFlag kClockObjectFlags = PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly;
} // namespace


void InitOOJSClock(ooscript::Context context, ooscript::Object global)
{
	Object clockPrototype = ooscript::initClass((context), (global), nullptr, &sClockClass, OOJSUnconstructableConstruct, 0, sClockPropertiesFacade, sClockMethods, nullptr, nullptr);
	ooscript::defineObject((context), (global), "clock", &sClockClass, clockPrototype, kClockObjectFlags);
}


namespace {
static bool ClockGetProperty(Context cx, Object obj, PropertyId propID, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;

	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);

	OOJS_NATIVE_ENTER(context)

	PlayerEntity				*player = OOPlayerForScripting();
	double						clockTime;

	clockTime = (player != nullptr ? player->PlayerEntity::clockTime() : 0.0);	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it

	switch (ooscript::idToInt32(propID))
	{
		case kClock_absoluteSeconds:
			return ooscript::newNumberValue(cx, (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0), value);

		case kClock_seconds:
			return ooscript::newNumberValue(cx, clockTime, value);

		case kClock_minutes:
			return ooscript::newNumberValue(cx, floor(clockTime / 60.0), value);

		case kClock_hours:
			return ooscript::newNumberValue(cx, floor(clockTime /3600.0), value);

		case kClock_secondsComponent:
			*value = ooscript::int32Value(fmod(clockTime, 60.0));
			return true;

		case kClock_minutesComponent:
			*value = ooscript::int32Value(fmod(floor(clockTime / 60.0), 60.0));
			return true;

		case kClock_hoursComponent:
			*value = ooscript::int32Value(fmod(floor(clockTime / 3600.0), 24.0));
			return true;

		case kClock_days:
		case kClock_daysComponent:
			*value = ooscript::int32Value(floor(clockTime / 86400.0));
			return true;

		case kClock_clockString:
			*value = OOJSValueFromPList(context, oo::PList((player != nullptr ? player->dial_clock() : std::string())));
			return true;

		case kClock_isAdjusting:
			*value = OOJSValueFromBOOL((player != nullptr ? player->clockAdjusting() : false));
			return true;

		case kClock_adjustedSeconds:
			return ooscript::newNumberValue(cx, (player != nullptr ? player->PlayerEntity::clockTimeAdjusted() : 0.0), value);	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it

		case kClock_legacy_scriptTimer:
			cxx_OOStandardsDeprecated("The legacy_scriptTimer property is deprecated");
			return ooscript::newNumberValue(cx, (player != nullptr ? player->scriptTimer() : OOTimeDelta{}), value);

		default:
			OOJSReportBadPropertySelector(context, thisObj, (propID), sClockProperties);
			return false;
	}

	OOJS_NATIVE_EXIT
}
} // namespace


// *** Methods ***

// toString() : String
namespace {
static bool JSClockToString(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)

	PlayerEntity *player = OOPlayerForScripting();
	OOJS_RETURN_PLIST(oo::PList(player != nullptr ? player->dial_clock() : std::string()));

	OOJS_NATIVE_EXIT
}
} // namespace


// clockStringForTime(time : Number) : String
namespace {
static bool ClockClockStringForTime(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)

	double						time;

	if (EXPECT_NOT(oojsArgs.count() < 1 || !ooscript::valueToNumber(context, (OOJS_ARGV[0]), &time)))
	{
		ooscript::Value arg = ooscript::undefinedValue();
		if (oojsArgs.count() > 0)  arg = OOJS_ARGV[0];
		cxx_OOJSReportBadArguments(context, "Clock", "clockStringForTime", 1, &arg, std::nullopt, "number");
		return false;
	}

	OOJS_RETURN(OOJSValueFromPList(context, oo::PList(cxx_ClockToString(time, false))));

	OOJS_NATIVE_EXIT
}
} // namespace


// addSeconds(seconds : Number) : String
namespace {
static bool ClockAddSeconds(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)

	double						time;
	const double				kMaxTime = 30.0 * 24.0 * 3600.0;	// 30 days

	if (EXPECT_NOT(oojsArgs.count() < 1 || !ooscript::valueToNumber(context, (OOJS_ARGV[0]), &time)))
	{
		ooscript::Value arg = ooscript::undefinedValue();
		if (oojsArgs.count() > 0)  arg = OOJS_ARGV[0];
		cxx_OOJSReportBadArguments(context, "Clock", "addSeconds", 1, &arg, std::nullopt, "number");
		return false;
	}

	if (time > kMaxTime || time < 1.0 || !isfinite(time))
	{
		OOJS_RETURN_BOOL(false);
	}

	if (PlayerEntity *player = OOPlayerForScripting())  player->addToAdjustTime(time);

	OOJS_RETURN_BOOL(true);

	OOJS_NATIVE_EXIT
}
} // namespace
