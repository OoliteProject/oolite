/*

OOJSTimer.mm


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

#include "OOJSTimer.h"
#include "OOJavaScriptEngine.h"
#include "OOJSScript.h"
#include "Universe.h"

#include "ooscript/JSEngine.hpp"
#include "oofnd/Notification.hpp"
#include <cstring>
#include "oofnd/objc/OOAssert.h"
#include "OOObjCPList.h"
#include "oofnd/String.hpp"

/*
	Retargeted onto the ooscript façade (JSEngine.hpp) the way OOJSVector.mm does it (bead
	oo-sdz, the sweep exemplar): the class dispatch table becomes a static ooscript::ClassDef
	(the stub hooks are nullptr), the engine's InitClass call becomes ooscript::initClass, and
	the directly spelled engine calls (NewObject, SetPrivate, GetPrivate, RemoveObjectRoot,
	RemoveValueRoot, ValueToObject, ValueToFunction, GetFunctionId, IsConstructing,
	ValueToNumber, NewNumberValue) go through ooscript:: instead. `this` is renamed to `thisObj`
	because it is a reserved word once this file compiles as Objective-C++ (ADR-0001).

	OOJSAddGCObjectRoot, OOJSAddGCValueRoot, OOJSAcquireContext and OOJSRelinquishContext are
	OOJS_* macros, not directly spelled engine calls, so they are untouched and out of scope for
	this bead (see JSEngine.hpp's own header comment and OOJSVector.mm's exemplar comment); the
	same is true of the OOJS_ARGV, OOJS_THIS, OOJS_RETURN_ family and OOJS_NATIVE_ENTER.

	Because ooscript::ClassDef, unlike the engine's old plain-C class struct, does not tolerate the old file's
	"forward-declared-then-defined" tentative-definition trick under Objective-C++'s stricter
	one-definition rule, sTimerClass's forward-declared consumer (-initWithDelay:...) is placed
	after the ClassDef's single full definition, so the whole file is reordered relative to the
	old .m layout: forward declarations, the ClassDef and its spec tables come first, then the
	OOJSTimer Objective-C implementation, then InitOOJSTimer() and the native hook bodies.

	OOJSRegisterObjectConverter() is given &sTimerClass itself.

	C++20 since bead oo-kdyh (proposed ADR-0056, amendment oo-ppc): the class is OOJSTimer,
	a C++ subclass of OOScriptTimer (global since beads oo-9ht.37 and oo-9ht.35). BOOL/YES/NO are bool/true/false.

	Since bead oo-6symp (proposed ADR-0056 amendment oo-6symp) the JS private slot holds the
	OOJSTimer itself, retained, which implements OOJSPrivateObject: the natives read it with
	OOJSGetCxxPrivate (the class check of DEFINE_JS_OBJECT_GETTER), the finalizer is the engine's
	OOJSCxxObjectWrapperFinalize (which sends clearJSSelf(), where TimerFinalize's warning now
	is), and toString() is OOJSCxxObjectWrapperToString with the timer's jsDescription(). The
	converter answers the timer itself as a plist Object node (bead oo-9ht.35 deleted its
	Objective-C facade, which it answered before), which converts back to the Timer object.
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

// Minimum allowable interval for repeating timers.
#define kMinInterval 0.25


namespace {
static ooscript::Object sTimerPrototype;
} // namespace


namespace {
static bool TimerGetProperty(Context cx, Object obj, PropertyId propID, Value *value);
} // namespace
namespace {
static bool TimerSetProperty(Context cx, Object obj, PropertyId propID, bool strict, Value *value);
} // namespace
namespace {
static bool TimerConstruct(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace

// Methods
namespace {
static bool TimerToString(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool TimerStart(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool TimerStop(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace


namespace {
static ClassDef sTimerClass =
{
	"Timer",
	ClassFlag::HasPrivate,
	
	nullptr,				// addProperty (engine default: PropertyStub)
	nullptr,				// delProperty (engine default: PropertyStub)
	TimerGetProperty,		// getProperty
	TimerSetProperty,		// setProperty
	nullptr,				// enumerate (engine default: EnumerateStub)
	nullptr,				// newEnumerate (ooscript::ClassFlag::NewEnumerate not used)
	nullptr,				// resolve (engine default: ResolveStub)
	nullptr,				// convert (engine default: ConvertStub)
	OOJSCxxObjectWrapperFinalize,	// finalize
	nullptr,				// call
	nullptr,				// construct
	nullptr,				// backend: owned by the façade backend, must start null
};
} // namespace


enum : std::uint8_t
{
	// Property IDs
	kTimer_nextTime,			// next fire time, double, read/write
	kTimer_interval,			// interval, double, read/write
	kTimer_isRunning			// is scheduled, boolean, read-only
};


namespace {
static PropertySpec sTimerProperties[] =
{
	// JS name					ID						flags																getter		setter
	{ "interval",				kTimer_interval,		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared,								nullptr, nullptr },
	{ "isRunning",				kTimer_isRunning,		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared,	nullptr, nullptr },
	{ "nextTime",				kTimer_nextTime,		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared,								nullptr, nullptr },
	{ 0 }
};
} // namespace

// A mirror of sTimerProperties with the read-only/read-write flags the two bad-property error
// reporters in OOJavaScriptEngine.mm (OOJSReportBadPropertySelector/Value) describe the
// properties by (see OOJSVector.mm's sVectorPropertiesRaw).
namespace {
static ooscript::PropertySpec sTimerPropertiesRaw[] =
{
	{ "interval",				kTimer_interval,		OOJS_PROP_READWRITE_CB },
	{ "isRunning",				kTimer_isRunning,		OOJS_PROP_READONLY_CB },
	{ "nextTime",				kTimer_nextTime,		OOJS_PROP_READWRITE_CB },
	{ 0 }
};
} // namespace


namespace {
static FunctionSpec sTimerMethods[] =
{
	// JS name					Function					min args	flags
	{ "toString",				TimerToString,				0,			0 },
	{ "start",					TimerStart,					0,			0 },
	{ "stop",					TimerStop,					0,			0 },
	{ 0 }
};
} // namespace


// DEFINE_JS_OBJECT_GETTER(JSTimerGetTimer, &sTimerClass, sTimerPrototype, OOJSTimer) for the C++
// timer the slot holds.
namespace {
static bool JSTimerGetTimer(ooscript::Context context, ooscript::Object inObject, OOJSTimer **outObject)
{
	return OOJSGetCxxPrivate(context, inObject, &sTimerClass, outObject);
}
} // namespace


oo::Ref<OOJSTimer> OOJSTimer::timerWithDelay(OOTimeAbsolute delay, OOTimeDelta interval, ooscript::Context context, ooscript::Value function, ooscript::Object jsThis)
{
	oo::Ref<OOJSTimer> timer = oo::adopt(new OOJSTimer);
	if (!timer->initWithDelay(delay, interval, context, function, jsThis))  return nullptr;
	return timer;
}


bool OOJSTimer::initWithDelay(OOTimeAbsolute delay, OOTimeDelta interval, ooscript::Context context, ooscript::Value function, ooscript::Object jsThis)
{
	if (!initWithNextTime((UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) + delay, interval))  return false;
	{
		OOCAssert(OOJSValueIsFunction(context, function), "Attempt to init OOJSTimer with a function that isn't.");

		_jsThis = jsThis;
		OOJSAddGCObjectRoot(context, &_jsThis, "OOJSTimer this");

		_function = function;
		OOJSAddGCValueRoot(context, &_function, "OOJSTimer function");

		_jsSelf = (ooscript::newObject((context), &sTimerClass, (sTimerPrototype), nullptr));
		if (_jsSelf != NULL)
		{
			// The private slot holds the timer, retained, as it kept self (ADR-0056 amendment oo-6symp).
			if (!OOJSSetCxxPrivate(context, _jsSelf, this))  _jsSelf = NULL;
		}
		if (_jsSelf == NULL)
		{
			return false;
		}

		_owningScript = OOJSScript::currentlyRunningScript();

		oo::NotificationCenter::defaultCenter().addObserver(this, kOOJavaScriptEngineWillResetNotificationName,
															OOJavaScriptEngine::sharedEngine(),
															[this](const oo::Notification &) { deleteJSPointers(); });
	}

	return true;
}


void OOJSTimer::deleteJSPointers()
{
	unscheduleTimer();

	if (_jsThis != NULL)
	{
		_jsThis = NULL;
		_function = ooscript::undefinedValue();

		ooscript::Context context = OOJSAcquireContext();
		ooscript::removeObjectRoot((context), &_jsThis);
		ooscript::removeValueRoot((context), (&_function));
		OOJSRelinquishContext(context);

		oo::NotificationCenter::defaultCenter().removeObserver(this, kOOJavaScriptEngineWillResetNotificationName,
																OOJavaScriptEngine::sharedEngine());
	}
}


OOJSTimer::~OOJSTimer()
{
	_owningScript = nullptr;

	deleteJSPointers();
}


std::optional<std::string> OOJSTimer::descriptionComponents() const
{
	std::optional<std::string>	funcName;
	ooscript::Context context = NULL;

	if (ooscript::isUndefined(_function) || ooscript::isNull(_function))
	{
		return "invalid";
	}

	context = OOJSAcquireContext();
	funcName = cxx_OOStringFromJSString(context, (ooscript::getFunctionId(ooscript::valueToFunction((context), (_function)))));
	OOJSRelinquishContext(context);

	if (!funcName.has_value())
	{
		funcName = "anonymous";
	}

	return oo::str::format("%s, function: %s", OOScriptTimer::descriptionComponents().value_or("(null)").c_str(), funcName->c_str());
}


std::optional<std::string> OOJSTimer::oo_jsClassName()
{
	return std::string("Timer");
}


void OOJSTimer::timerFired()
{
	ooscript::Value					rval = ooscript::undefinedValue();
	bool					described = false;	// was the description itself, used only to test for nil

	::OOJavaScriptEngine *engine = OOJavaScriptEngine::sharedEngine();
	ooscript::Context context = OOJSAcquireContext();

	// stop and remove the timer if _jsThis (the first parameter in the constructor) dies.
	const oo::PList thisValue = cxx_OOJSPListFromJSObject(context, _jsThis);
	if (oo::EntityIn(thisValue) != nullptr)  described = true;	// an entity's object described itself (bead oo-dpyk8)
	// (An Objective-C object's node, described by its class's -cxx_oo_jsDescription, went with bead
	// oo-4aq6a.5: no game object is one.)
	else
	{
		// A plain value (object, array, String/Number/Boolean object): its Foundation form's
		// -oo_jsDescription was never nil (ADR-0051).
		described = !thisValue.isNull();
	}

	if (!described)
	{
		unscheduleTimer();
		OOJSRelinquishContext(context);
		return;
	}

	OOJSScript::pushScript(_owningScript);
	engine->callJSFunction(_function, _jsThis, 0, NULL, &rval);
	OOJSScript::popScript(_owningScript.get());

	OOJSRelinquishContext(context);
}


ooscript::Value OOJSTimer::jsValueInContext(ooscript::Context /*context*/)
{
	return ooscript::objectValue(_jsSelf);
}


// TimerFinalize's warning, before the engine's finalizer releases the slot's retain.
void OOJSTimer::clearJSSelf(ooscript::Object selfVal)
{
	if (isScheduled())
	{
		// Described from the timer's own state: its full description reads the function's
		// name, which runs script inside the collection and corrupts the heap (bead oo-r1ci7).
		OO_LOG_WARN("script.javaScript.unrootedTimer", "Timer {} is being garbage-collected while still running. You must keep a reference to all running timers, or they will stop unpredictably!", descriptionWithComponents(OOScriptTimer::descriptionComponents()));
	}
	if (_jsSelf == selfVal)  _jsSelf = NULL;
}


// What the facade's -cxx_oo_jsDescription answered (OOObject (OOJavaScriptConversion)): the JS
// class name and the components.
std::optional<std::string> OOJSTimer::jsDescription()
{
	const std::optional<std::string> components = descriptionComponents();
	const std::string name = oo_jsClassName().value_or("OOJSTimer");
	if (components.has_value())  return oo::str::format("[%s %s]", name.c_str(), components->c_str());
	return oo::str::format("[object %s]", name.c_str());
}


// OOJSBasicPrivateObjectConverter for the C++ timer the slot holds: the timer as a plist Object
// node, where it answered the timer's facade (bead oo-9ht.35); null for the prototype.
namespace {
static oo::PList TimerConverter(ooscript::Context context, ooscript::Object object)
{
	OOJSTimer *timer = static_cast<OOJSTimer *>(static_cast<oo::RefCounted *>(ooscript::getPrivate(context, object)));
	if (timer == nullptr)  return oo::PList();
	return oo::PList(oo::PList::Object(oo::Ref<oo::PListForeign>(timer)));
}
} // namespace


void InitOOJSTimer(ooscript::Context context, ooscript::Object global)
{
	Object proto = ooscript::initClass((context), (global), nullptr, &sTimerClass, TimerConstruct, 0, sTimerProperties, sTimerMethods, nullptr, nullptr);
	sTimerPrototype = (proto);
	OOJSRegisterObjectConverter(&sTimerClass, TimerConverter);
}


namespace {
static bool TimerGetProperty(Context cx, Object obj, PropertyId propID, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);
	
	OOJS_NATIVE_ENTER(context)
	
	OOJSTimer			*timer = nullptr;	// null for Timer.prototype, which has none
	
	if (EXPECT_NOT(!JSTimerGetTimer(context, thisObj, &timer))) return false;
	
	switch (ooscript::idToInt32(propID))
	{
		case kTimer_nextTime:
			return ooscript::newNumberValue(cx, timer != nullptr ? timer->nextTime() : 0.0, value);
			
		case kTimer_interval:
			return ooscript::newNumberValue(cx, timer != nullptr ? timer->interval() : 0.0, value);
			
		case kTimer_isRunning:
			*value = (OOJSValueFromBOOL(timer != nullptr && timer->isScheduled()));
			return true;
			
		default:
			OOJSReportBadPropertySelector(context, thisObj, (propID), sTimerPropertiesRaw);
			return false;
	}
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool TimerSetProperty(Context cx, Object obj, PropertyId propID, bool /*strict*/, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);
	
	OOJS_NATIVE_ENTER(context)
	
	OOJSTimer			*timer = nullptr;	// null for Timer.prototype, which has none
	double					fValue;
	
	if (EXPECT_NOT(!JSTimerGetTimer(context, thisObj, &timer))) return false;
	
	switch (ooscript::idToInt32(propID))
	{
		case kTimer_nextTime:
			if (ooscript::valueToNumber(cx, *value, &fValue))
			{
				if (!(timer != nullptr && timer->setNextTime(fValue)))
				{
					cxx_OOJSReportWarning(context, "Ignoring attempt to change next fire time for running timer %s.", (timer != nullptr ? timer->description() : std::string("(null)")).c_str());
				}
				return true;
			}
			break;
			
		case kTimer_interval:
			if (ooscript::valueToNumber(cx, *value, &fValue))
			{
				if (timer != nullptr)  timer->setInterval(fValue);
				return true;
			}
			break;
			
		default:
			OOJSReportBadPropertySelector(context, thisObj, (propID), sTimerPropertiesRaw);
			return false;
	}
	
	OOJSReportBadPropertyValue(context, thisObj, (propID), sTimerPropertiesRaw, *(value));
	return false;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// new Timer(this : Object, function : Function, delay : Number [, interval : Number]) : Timer
namespace {
static bool TimerConstruct(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	ooscript::Value					function = ooscript::undefinedValue();
	double					delay;
	double					interval = -1.0;
	oo::Ref<OOJSTimer>	timer;
	ooscript::Object callbackThis = NULL;
	
	if (EXPECT_NOT(!oojsArgs.isConstructing()))
	{
		cxx_OOJSReportError(context, "Timer() cannot be called as a function, it must be used as a constructor (as in new Timer(...)).");
		return false;
	}
	
	if (oojsArgs.count() < 3)
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "Timer", oojsArgs.count(), OOJS_ARGV, "Invalid arguments in constructor", "(object, function, number [, number])");
		return false;
	}
	
	if (!ooscript::isNull(OOJS_ARGV[0]) && !ooscript::isUndefined(OOJS_ARGV[0]))
	{
		if (!ooscript::valueToObject(context, (OOJS_ARGV[0]), &callbackThis))
		{
			cxx_OOJSReportBadArguments(context, std::nullopt, "Timer", 1, OOJS_ARGV, "Invalid argument in constructor", "object");
			return false;
		}
	}
	
	function = OOJS_ARGV[1];
	if (ooscript::valueToFunction(context, (function)) == nullptr)
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "Timer", 1, OOJS_ARGV + 1, "Invalid argument in constructor", "function");
		return false;
	}
	
	if (!ooscript::valueToNumber(context, (OOJS_ARGV[2]), &delay) || isnan(delay))
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "Timer", 1, OOJS_ARGV + 2, "Invalid argument in constructor", "number");
		return false;
	}
	
	// Fourth argument is optional.
	if (3 < oojsArgs.count() && !ooscript::valueToNumber(context, (OOJS_ARGV[3]), &interval))  interval = -1;
	
	// Ensure interval is not too small.
	if (0.0 < interval && interval < kMinInterval)  interval = kMinInterval;
	
	timer = OOJSTimer::timerWithDelay(delay, interval, context, function, callbackThis);
	if (EXPECT_NOT(!timer))  return false;
	
	if (delay >= 0)	// Leave in stopped state if delay is negative
	{
		timer->scheduleTimer();
	}
	OOJS_RETURN(OOJSValueFromCxxObject(context, timer.get()));
	
	OOJS_NATIVE_EXIT
}
} // namespace


// *** Methods ***

// start() : Boolean
namespace {
static bool TimerStart(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	OOJSTimer				*thisTimer = nullptr;
	
	if (EXPECT_NOT(!JSTimerGetTimer(context, OOJS_THIS, &thisTimer)))  return false;
	
	OOJS_RETURN_BOOL(thisTimer != nullptr && thisTimer->scheduleTimer());
	
	OOJS_NATIVE_EXIT
}
} // namespace


// stop()
namespace {
static bool TimerStop(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	OOJSTimer				*thisTimer = nullptr;
	
	if (EXPECT_NOT(!JSTimerGetTimer(context, OOJS_THIS, &thisTimer)))  return false;
	
	if (thisTimer != nullptr)  thisTimer->unscheduleTimer();
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// toString() : String
namespace {
static bool TimerToString(ooscript::Context cx, ooscript::CallArgs &oojsArgs)
{
	return OOJSCxxObjectWrapperToString(cx, oojsArgs, &sTimerClass);
}
} // namespace
