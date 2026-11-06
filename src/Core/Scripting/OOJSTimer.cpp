/*

OOJSTimer.m


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

#include "OODescription.h"
#include "OOJSScript.h"
#include "OOJavaScriptEngine.h"
#include "Universe.h"
#include "oofnd/Notification.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"

/*
        The class is OOJSTimer, a C++ subclass of OOScriptTimer.

        The JS private slot holds the OOJSTimer itself, retained, which
        implements OOJSPrivateObject: the natives read it with OOJSGetCxxPrivate
        (the class check of DEFINE_JS_OBJECT_GETTER), the finalizer is the
        engine's OOJSCxxObjectWrapperFinalize (which calls clearJSSelf(), where
        TimerFinalize's warning now is), and toString() is
        OOJSCxxObjectWrapperToString with the timer's jsDescription(). The
        converter answers the timer itself as a plist Object node, which
        converts back to the Timer object.
*/

// Minimum allowable interval for repeating timers.
#define kMinInterval 0.25

static JSClassID sTimerClassID;

/*	Ownership

        The JS Timer object owns a retain on its OOJSTimer (its opaque value).
        The OOJSTimer owns references to its function and this, as the
        SpiderMonkey version rooted them, and holds a non-owning reference to
        its JS Timer object, cleared when that object is finalized.

        The function and this references are deliberately not reported through
        a gc_mark hook. A scheduled timer outlives its JS object (the scheduler
        retains it), and QuickJS's cycle collector would free any object marked
        from a garbage JS Timer even though the OOJSTimer still holds it. As in
        SpiderMonkey, where they were GC roots, they keep their targets (and any
        cycle through them back to the Timer object) alive until the timer is
        deallocated or the engine is reset.
*/

oo::Ref<OOJSTimer> OOJSTimer::timerWithDelay(OOTimeAbsolute delay,
                                             OOTimeDelta interval,
                                             JSContext* context,
                                             JSValueConst function,
                                             JSValueConst jsThis) {
  oo::Ref<OOJSTimer> timer = oo::adopt(new OOJSTimer);
  if (!timer->initWithDelay(delay, interval, context, function, jsThis))
    return nullptr;
  return timer;
}

bool OOJSTimer::initWithDelay(OOTimeAbsolute delay, OOTimeDelta interval,
                              JSContext* context, JSValueConst function,
                              JSValueConst jsThis) {
  if (!initWithNextTime(
          (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) + delay, interval))
    return false;
  {
    OOCAssert(OOJSValueIsFunction(context, function),
              "Attempt to init OOJSTimer with a function that isn't.");

    _jsThis = JS_DupValue(context, jsThis);
    _function = JS_DupValue(context, function);

    /*	QuickJS has no JS_GetFunctionId(); use the function's name property.
            It's cached because descriptionComponents() is used by the
            finalizer, which must not run JS code (the property could be a
            getter, or the function a Proxy).
    */
    JSValue nameValue = JS_GetPropertyStr(context, function, "name");
    if (JS_IsException(nameValue)) {
      JS_FreeValue(context, JS_GetException(context));
    } else {
      std::optional<std::string> name =
          cxx_OOStringFromJSValue(context, nameValue);
      if (name.has_value() && !name->empty()) _functionName = std::move(name);
    }
    JS_FreeValue(context, nameValue);

    _jsSelf = JS_NewObjectClass(context, sTimerClassID);
    if (!JS_IsException(_jsSelf)) {
      // The private slot holds the timer, retained, as it kept self.
      if (!OOJSSetCxxPrivate(_jsSelf, this)) {
        JS_FreeValue(context, _jsSelf);
        _jsSelf = JS_EXCEPTION;
      }
    }
    if (JS_IsException(_jsSelf)) {
      _jsSelf = JS_UNDEFINED;
      releaseJSValues();
      return false;
    }

    _owningScript = OOJSScript::currentlyRunningScript();

    oo::NotificationCenter::defaultCenter().addObserver(
        this, kOOJavaScriptEngineWillResetNotificationName,
        OOJavaScriptEngine::sharedEngine(),
        [this](const oo::Notification&) { deleteJSPointers(); });
  }

  return true;
}

// Notification handler: engine reset.
void OOJSTimer::deleteJSPointers() {
  /*	Freeing _jsThis may free the JS Timer object, whose finalizer releases
          us, so stay alive until we're done.
  */
  oo::Ref<OOJSTimer> keepAlive(this);
  releaseJSValues();
}

void OOJSTimer::releaseJSValues() {
  unscheduleTimer();

  if (JS_IsObject(_function)) {
    // Don't touch the members after freeing (see deleteJSPointers()).
    JSValue function = _function;
    JSValue jsThis = _jsThis;
    _function = JS_UNDEFINED;
    _jsThis = JS_UNDEFINED;

    oo::NotificationCenter::defaultCenter().removeObserver(
        this, kOOJavaScriptEngineWillResetNotificationName,
        OOJavaScriptEngine::sharedEngine());

    JSContext* context = OOJSAcquireContext();
    JS_FreeValue(context, function);
    JS_FreeValue(context, jsThis);
    OOJSRelinquishContext(context);
  }
}

OOJSTimer::~OOJSTimer() {
  _owningScript = nullptr;

  /*	Not deleteJSPointers(): we can't be retained during destruction. Freeing
          _jsThis can't re-enter, since the JS Timer object, which held our
          retain, has already been finalized.
  */
  releaseJSValues();
}

std::optional<std::string> OOJSTimer::descriptionComponents() const {
  if (!JS_IsObject(_function)) {
    return "invalid";
  }

  return oo::str::format(
      "%s, function: %s",
      OOScriptTimer::descriptionComponents().value_or("(null)").c_str(),
      _functionName.value_or("anonymous").c_str());
}

std::optional<std::string> OOJSTimer::oo_jsClassName() {
  return std::string("Timer");
}

void OOJSTimer::timerFired() {
  JSValue rval = JS_UNDEFINED;
  bool described =
      false;  // was the description itself, used only to test for nil

  ::OOJavaScriptEngine* engine = OOJavaScriptEngine::sharedEngine();
  JSContext* context = OOJSAcquireContext();

  // stop and remove the timer if _jsThis (the first parameter in the
  // constructor) dies.
  const oo::PList thisValue = cxx_OOJSPListFromJSObject(context, _jsThis);
  if (oo::EntityIn(thisValue) != nullptr)
    described = true;  // an entity's object described itself
  else {
    // A plain value (object, array, String/Number/Boolean object): its
    // Foundation form's -oo_jsDescription was never nil.
    described = !thisValue.isNull();
  }

  if (!described || !JS_IsObject(_function)) {
    unscheduleTimer();
    OOJSRelinquishContext(context);
    return;
  }

  // The callback may stop the timer and drop the last references to it.
  oo::Ref<OOJSTimer> keepAlive(this);
  JSValue function = JS_DupValue(context, _function);
  JSValue jsThis = JS_DupValue(context, _jsThis);

  OOJSScript::pushScript(_owningScript);
  _firing = true;
  engine->callJSFunction(function, jsThis, 0, NULL, &rval);
  _firing = false;
  OOJSScript::popScript(_owningScript.get());

  JS_FreeValue(context, rval);
  JS_FreeValue(context, function);
  JS_FreeValue(context, jsThis);

  OOJSRelinquishContext(context);
}

JSValue OOJSTimer::jsValueInContext(JSContext* context) {
  /*	_jsSelf is cleared when the JS object is finalized (which, as before,
          can happen while the timer is still scheduled). SpiderMonkey returned
          the dangling object; return null instead.
  */
  if (JS_IsObject(_jsSelf)) return JS_DupValue(context, _jsSelf);
  return JS_NULL;
}

// TimerFinalize's warning, before the engine's finalizer releases the slot's
// retain.
void OOJSTimer::clearJSSelf(JSValueConst selfVal) {
  if (isScheduled() && !willNotFireAgain()) {
    // Described from the timer's own state and the cached function name: the
    // finalizer must not run JS code.
    OO_LOG_WARN("script.javaScript.unrootedTimer",
                "Timer {} is being garbage-collected while still running. You "
                "must keep a reference to all running timers, or they will "
                "stop unpredictably!",
                description());
  }
  if (JS_IsObject(_jsSelf) &&
      JS_VALUE_GET_PTR(_jsSelf) == JS_VALUE_GET_PTR(selfVal))
    _jsSelf = JS_UNDEFINED;
}

// The JS class name and the components.
std::optional<std::string> OOJSTimer::jsDescription() {
  const std::optional<std::string> components = descriptionComponents();
  const std::string name = oo_jsClassName().value_or("OOJSTimer");
  if (components.has_value())
    return oo::str::format("[%s %s]", name.c_str(), components->c_str());
  return oo::str::format("[object %s]", name.c_str());
}

/*	A one-shot timer stays scheduled while its callback runs, and is dropped
        afterwards. A callback that replaces the only reference to its own timer
        (e.g. with a new timer) frees the JS object at once under QuickJS's
        reference counting, which SpiderMonkey's GC almost never did.
*/
bool OOJSTimer::willNotFireAgain() { return _firing && interval() <= 0.0; }

/*	The reference created with the JS object in initWithDelay() belongs to
        whoever calls this, once (the constructor, which returns it).
        SpiderMonkey's unrooted _jsSelf pointer added no reference, so this is
        what lets the JS object be collected (and finalized) as before.
*/
JSValue OOJSTimer::transferJSSelf() { return _jsSelf; }

static JSValue TimerGetProperty(OOJS_GETTER_ARGS);
static JSValue TimerSetProperty(OOJS_SETTER_ARGS);
static JSValue TimerConstruct(OOJS_NATIVE_ARGS);

// Methods
static JSValue TimerToString(OOJS_NATIVE_ARGS);
static JSValue TimerStart(OOJS_NATIVE_ARGS);
static JSValue TimerStop(OOJS_NATIVE_ARGS);

static JSClassDef sTimerClass = {
    .class_name = "Timer",
    .finalizer = OOJSCxxObjectWrapperFinalize,
};

enum {
  // Property IDs
  kTimer_nextTime,  // next fire time, double, read/write
  kTimer_interval,  // interval, double, read/write
  kTimer_isRunning  // is scheduled, boolean, read-only
};

static const JSCFunctionListEntry sTimerProperties[] = {
    // JS name					Getter
    // Setter				ID
    OOJS_PROPERTY_RW("interval", TimerGetProperty, TimerSetProperty,
                     kTimer_interval),
    OOJS_PROPERTY_RO("isRunning", TimerGetProperty, kTimer_isRunning),
    OOJS_PROPERTY_RW("nextTime", TimerGetProperty, TimerSetProperty,
                     kTimer_nextTime),
};

static const JSCFunctionListEntry sTimerMethods[] = {
    // JS name					Function
    // min args
    JS_CFUNC_DEF("toString", 0, TimerToString),
    JS_CFUNC_DEF("start", 0, TimerStart),
    JS_CFUNC_DEF("stop", 0, TimerStop),
};

// DEFINE_JS_OBJECT_GETTER(JSTimerGetTimer, sTimerClassID, OOJSTimer) for the
// C++ timer the slot holds.
static bool JSTimerGetTimer(JSContext* context, JSValueConst inObject,
                            OOJSTimer** outObject) {
  return OOJSGetCxxPrivate(context, inObject, sTimerClassID, outObject);
}

// OOJSBasicPrivateObjectConverter for the C++ timer the slot holds: the timer
// as a plist Object node; null for the prototype.
static oo::PList TimerConverter(JSContext* /*context*/, JSValueConst object) {
  OOJSTimer* timer = static_cast<OOJSTimer*>(
      static_cast<oo::RefCounted*>(JS_GetOpaque(object, sTimerClassID)));
  if (timer == nullptr) return oo::PList();
  return oo::PList(oo::PList::Object(oo::Ref<oo::PListForeign>(timer)));
}

void InitOOJSTimer(JSContext* context, JSValueConst global) {
  OOJSRegisterClass(&sTimerClassID, &sTimerClass);
  OOJSInitClass(context, global, sTimerClassID, JS_UNDEFINED, TimerConstruct, 0,
                sTimerProperties, OOJS_COUNT(sTimerProperties), sTimerMethods,
                OOJS_COUNT(sTimerMethods), NULL, 0);
  OOJSRegisterObjectConverter(sTimerClassID, TimerConverter);
}

static JSValue TimerGetProperty(OOJS_GETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOJSTimer* timer = nullptr;  // null for Timer.prototype, which has none

  if (EXPECT_NOT(!JSTimerGetTimer(context, thisObj, &timer)))
    return OOJSNativeFailure(context);

  switch (magic) {
    case kTimer_nextTime:
      return JS_NewNumber(context, timer != nullptr ? timer->nextTime() : 0.0);

    case kTimer_interval:
      return JS_NewNumber(context, timer != nullptr ? timer->interval() : 0.0);

    case kTimer_isRunning:
      return OOJSValueFromBOOL(timer != nullptr && timer->isScheduled());

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic, sTimerProperties,
                                    OOJS_COUNT(sTimerProperties));
      return JS_EXCEPTION;
  }

  OOJS_NATIVE_EXIT
}

static JSValue TimerSetProperty(OOJS_SETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOJSTimer* timer = nullptr;  // null for Timer.prototype, which has none
  double fValue;

  if (EXPECT_NOT(!JSTimerGetTimer(context, thisObj, &timer)))
    return OOJSNativeFailure(context);

  switch (magic) {
    case kTimer_nextTime:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        if (!(timer != nullptr && timer->setNextTime(fValue))) {
          cxx_OOJSReportWarning(
              context,
              "Ignoring attempt to change next fire time for running timer %s.",
              (timer != nullptr ? timer->description() : std::string("(null)"))
                  .c_str());
        }
        return JS_UNDEFINED;
      }
      JS_FreeValue(context, JS_GetException(context));
      break;

    case kTimer_interval:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        if (timer != nullptr) timer->setInterval(fValue);
        return JS_UNDEFINED;
      }
      JS_FreeValue(context, JS_GetException(context));
      break;

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic, sTimerProperties,
                                    OOJS_COUNT(sTimerProperties));
      return JS_EXCEPTION;
  }

  OOJSReportBadPropertyValue(context, thisObj, magic, sTimerProperties,
                             OOJS_COUNT(sTimerProperties), value);
  return JS_EXCEPTION;

  OOJS_NATIVE_EXIT
}

// new Timer(this : Object, function : Function, delay : Number [, interval :
// Number]) : Timer
static JSValue TimerConstruct(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  JSValueConst function = JS_UNDEFINED;
  double delay;
  double interval = -1.0;
  oo::Ref<OOJSTimer> timer;
  JSValue callbackThis = JS_NULL;

  if (EXPECT_NOT(!OOJS_IS_CONSTRUCTING)) {
    cxx_OOJSReportError(context,
                        "Timer() cannot be called as a function, it must be "
                        "used as a constructor (as in new Timer(...)).");
    return JS_EXCEPTION;
  }

  if (argc < 3) {
    cxx_OOJSReportBadArguments(context, std::nullopt, "Timer", argc, OOJS_ARGV,
                               "Invalid arguments in constructor",
                               "(object, function, number [, number])");
    return JS_EXCEPTION;
  }

  if (!JS_IsNull(OOJS_ARGV[0]) && !JS_IsUndefined(OOJS_ARGV[0])) {
    callbackThis = JS_ToObject(context, OOJS_ARGV[0]);
    if (JS_IsException(callbackThis)) {
      JS_FreeValue(context, JS_GetException(context));
      cxx_OOJSReportBadArguments(context, std::nullopt, "Timer", 1, OOJS_ARGV,
                                 "Invalid argument in constructor", "object");
      return JS_EXCEPTION;
    }
  }

  function = OOJS_ARGV[1];
  if (!JS_IsFunction(context, function)) {
    JS_FreeValue(context, callbackThis);
    cxx_OOJSReportBadArguments(context, std::nullopt, "Timer", 1, OOJS_ARGV + 1,
                               "Invalid argument in constructor", "function");
    return JS_EXCEPTION;
  }

  if (JS_ToFloat64(context, &delay, OOJS_ARGV[2]) < 0 || isnan(delay)) {
    if (JS_HasException(context))
      JS_FreeValue(context, JS_GetException(context));
    JS_FreeValue(context, callbackThis);
    cxx_OOJSReportBadArguments(context, std::nullopt, "Timer", 1, OOJS_ARGV + 2,
                               "Invalid argument in constructor", "number");
    return JS_EXCEPTION;
  }

  // Fourth argument is optional.
  if (3 < argc && JS_ToFloat64(context, &interval, OOJS_ARGV[3]) < 0) {
    JS_FreeValue(context, JS_GetException(context));
    interval = -1;
  }

  // Ensure interval is not too small.
  if (0.0 < interval && interval < kMinInterval) interval = kMinInterval;

  timer = OOJSTimer::timerWithDelay(delay, interval, context, function,
                                    callbackThis);
  JS_FreeValue(context, callbackThis);
  if (EXPECT_NOT(!timer)) return OOJSNativeFailure(context);

  if (delay >= 0)  // Leave in stopped state if delay is negative
  {
    timer->scheduleTimer();
  }
  // The Timer object's private slot keeps the timer alive once `timer` goes.
  return timer->transferJSSelf();

  OOJS_NATIVE_EXIT
}

// *** Methods ***

// start() : Boolean
static JSValue TimerStart(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOJSTimer* thisTimer = nullptr;

  if (EXPECT_NOT(!JSTimerGetTimer(context, OOJS_THIS, &thisTimer)))
    return OOJSNativeFailure(context);

  OOJS_RETURN_BOOL(thisTimer != nullptr && thisTimer->scheduleTimer());

  OOJS_NATIVE_EXIT
}

// stop()
static JSValue TimerStop(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOJSTimer* thisTimer = nullptr;

  if (EXPECT_NOT(!JSTimerGetTimer(context, OOJS_THIS, &thisTimer)))
    return OOJSNativeFailure(context);

  if (thisTimer != nullptr) thisTimer->unscheduleTimer();
  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// toString() : String
static JSValue TimerToString(OOJS_NATIVE_ARGS) {
  return OOJSCxxObjectWrapperToString(context, OOJS_THIS, sTimerClassID);
}
