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

#import "OOJSTimer.h"
#import "OOJavaScriptEngine.h"
#import "Universe.h"

// Minimum allowable interval for repeating timers.
#define kMinInterval 0.25

static JSClassID sTimerClassID;
static JSClassDef sTimerClass;

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

@interface OOJSTimer (Private)

- (id)initWithDelay:(OOTimeAbsolute)delay
           interval:(OOTimeDelta)interval
            context:(JSContext*)context
           function:(JSValueConst)function
               this:(JSValueConst)jsThis;

- (void)clearJSSelf;
- (JSValue)transferJSSelf;
- (void)releaseJSValues;

@end

@implementation OOJSTimer

- (id)initWithDelay:(OOTimeAbsolute)delay
           interval:(OOTimeDelta)interval
            context:(JSContext*)context
           function:(JSValueConst)function
               this:(JSValueConst)jsThis
{
    self = [super initWithNextTime:[UNIVERSE getTime] + delay interval:interval];
    if (self != nil) {
        NSAssert(OOJSValueIsFunction(context, function), @"Attempt to init OOJSTimer with a function that isn't.");

        _jsThis = JS_DupValue(context, jsThis);
        _function = JS_DupValue(context, function);

        /*	QuickJS has no JS_GetFunctionId(); use the function's name property.
                It's cached because -descriptionComponents is used by the
                finalizer, which must not run JS code (the property could be a
                getter, or the function a Proxy).
        */
        JSValue nameValue = JS_GetPropertyStr(context, function, "name");
        if (JS_IsException(nameValue)) {
            JS_FreeValue(context, JS_GetException(context));
        } else {
            NSString* name = OOStringFromJSValue(context, nameValue);
            if ([name length] != 0)
                _functionName = [name copy];
        }
        JS_FreeValue(context, nameValue);

        _jsSelf = JS_NewObjectClass(context, sTimerClassID);
        if (!JS_IsException(_jsSelf)) {
            if (JS_SetOpaque(_jsSelf, [self retain]) < 0) {
                [self release];
                JS_FreeValue(context, _jsSelf);
                _jsSelf = JS_EXCEPTION;
            }
        }
        if (JS_IsException(_jsSelf)) {
            _jsSelf = JS_UNDEFINED;
            [self releaseJSValues];
            [self release];
            return nil;
        }

        _owningScript = [[OOJSScript currentlyRunningScript] weakRetain];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(deleteJSPointers)
                                                     name:kOOJavaScriptEngineWillResetNotification
                                                   object:[OOJavaScriptEngine sharedEngine]];
    }

    return self;
}

// Notification handler: engine reset.
- (void)deleteJSPointers
{
    /*	Freeing _jsThis may free the JS Timer object, whose finalizer releases
            us, so stay alive until we're done.
    */
    [[self retain] autorelease];
    [self releaseJSValues];
}

- (void)releaseJSValues
{
    [self unscheduleTimer];

    // Ivars are zero-filled (not objects) before they are set.
    if (JS_IsObject(_function)) {
        // Don't touch the ivars after freeing (see -deleteJSPointers).
        JSValue function = _function;
        JSValue jsThis = _jsThis;
        _function = JS_UNDEFINED;
        _jsThis = JS_UNDEFINED;

        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:kOOJavaScriptEngineWillResetNotification
                                                      object:[OOJavaScriptEngine sharedEngine]];

        JSContext* context = OOJSAcquireContext();
        JS_FreeValue(context, function);
        JS_FreeValue(context, jsThis);
        OOJSRelinquishContext(context);
    }
}

- (void)dealloc
{
    [_owningScript release];
    [_functionName release];

    /*	Not -deleteJSPointers: we can't be retained during dealloc. Freeing
            _jsThis can't re-enter, since the JS Timer object, which held our
            retain, has already been finalized.
    */
    [self releaseJSValues];

    [super dealloc];
}

- (NSString*)descriptionComponents
{
    NSString* funcName = nil;

    if (!JS_IsObject(_function)) {
        return @"invalid";
    }

    funcName = _functionName;
    if (funcName == nil) {
        funcName = @"anonymous";
    }

    return [NSString stringWithFormat:@"%@, function: %@", [super descriptionComponents], funcName];
}

- (NSString*)oo_jsClassName
{
    return @"Timer";
}

- (void)timerFired
{
    JSValue rval = JS_UNDEFINED;
    NSString* description = nil;

    OOJavaScriptEngine* engine = [OOJavaScriptEngine sharedEngine];
    JSContext* context = OOJSAcquireContext();

    // stop and remove the timer if _jsThis (the first parameter in the constructor) dies.
    id object = OOJSNativeObjectFromJSObject(context, _jsThis);
    if (object != nil) {
        description = [object oo_jsDescription];
        if (description == nil)
            description = [object description];
    }

    if (description == nil || !JS_IsObject(_function)) {
        [self unscheduleTimer];
        OOJSRelinquishContext(context);
        return;
    }

    // The callback may stop the timer and drop the last references to it.
    [[self retain] autorelease];
    JSValue function = JS_DupValue(context, _function);
    JSValue jsThis = JS_DupValue(context, _jsThis);

    [OOJSScript pushScript:_owningScript];
    [engine callJSFunction:function
                 forObject:jsThis
                      argc:0
                      argv:NULL
                    result:&rval];
    [OOJSScript popScript:_owningScript];

    JS_FreeValue(context, rval);
    JS_FreeValue(context, function);
    JS_FreeValue(context, jsThis);

    OOJSRelinquishContext(context);
}

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    /*	_jsSelf is cleared when the JS object is finalized (which, as before,
            can happen while the timer is still scheduled). SpiderMonkey returned
            the dangling object; return null instead.
    */
    if (JS_IsObject(_jsSelf))
        return JS_DupValue(context, _jsSelf);
    return JS_NULL;
}

- (void)clearJSSelf
{
    _jsSelf = JS_UNDEFINED;
}

/*	The reference created with the JS object in -initWithDelay:... belongs to
        whoever calls this, once (the constructor, which returns it).
        SpiderMonkey's unrooted _jsSelf pointer added no reference, so this is
        what lets the JS object be collected (and finalized) as before.
*/
- (JSValue)transferJSSelf
{
    return _jsSelf;
}

@end

static JSValue TimerGetProperty(OOJS_GETTER_ARGS);
static JSValue TimerSetProperty(OOJS_SETTER_ARGS);
static void TimerFinalize(JSRuntime* runtime, JSValueConst this);
static JSValue TimerConstruct(OOJS_NATIVE_ARGS);

// Methods
static JSValue TimerStart(OOJS_NATIVE_ARGS);
static JSValue TimerStop(OOJS_NATIVE_ARGS);

static JSClassDef sTimerClass = {
    .class_name = "Timer",
    .finalizer = TimerFinalize,
};

enum {
    // Property IDs
    kTimer_nextTime, // next fire time, double, read/write
    kTimer_interval, // interval, double, read/write
    kTimer_isRunning // is scheduled, boolean, read-only
};

static const JSCFunctionListEntry sTimerProperties[] = {
    // JS name					Getter				Setter				ID
    OOJS_PROPERTY_RW("interval", TimerGetProperty, TimerSetProperty, kTimer_interval),
    OOJS_PROPERTY_RO("isRunning", TimerGetProperty, kTimer_isRunning),
    OOJS_PROPERTY_RW("nextTime", TimerGetProperty, TimerSetProperty, kTimer_nextTime),
};

static const JSCFunctionListEntry sTimerMethods[] = {
    // JS name					Function					min args
    JS_CFUNC_DEF("toString", 0, OOJSObjectWrapperToString),
    JS_CFUNC_DEF("start", 0, TimerStart),
    JS_CFUNC_DEF("stop", 0, TimerStop),
};

DEFINE_JS_OBJECT_GETTER(JSTimerGetTimer, sTimerClassID, OOJSTimer);

void InitOOJSTimer(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sTimerClassID, &sTimerClass);
    OOJSInitClass(context, global, sTimerClassID, JS_UNDEFINED, TimerConstruct, 0,
        sTimerProperties, OOJS_COUNT(sTimerProperties), sTimerMethods, OOJS_COUNT(sTimerMethods), NULL, 0);
    OOJSRegisterObjectConverter(sTimerClassID, OOJSBasicPrivateObjectConverter);
}

static JSValue TimerGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOJSTimer* timer = nil;

    if (EXPECT_NOT(!JSTimerGetTimer(context, this, &timer)))
        return OOJSNativeFailure(context);

    switch (magic) {
    case kTimer_nextTime:
        return JS_NewNumber(context, [timer nextTime]);

    case kTimer_interval:
        return JS_NewNumber(context, [timer interval]);

    case kTimer_isRunning:
        return OOJSValueFromBOOL([timer isScheduled]);

    default:
        OOJSReportBadPropertySelector(context, this, magic, sTimerProperties, OOJS_COUNT(sTimerProperties));
        return JS_EXCEPTION;
    }

    OOJS_NATIVE_EXIT
}

static JSValue TimerSetProperty(OOJS_SETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOJSTimer* timer = nil;
    double fValue;

    if (EXPECT_NOT(!JSTimerGetTimer(context, this, &timer)))
        return OOJSNativeFailure(context);

    switch (magic) {
    case kTimer_nextTime:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (![timer setNextTime:fValue]) {
                OOJSReportWarning(context, @"Ignoring attempt to change next fire time for running timer %@.", timer);
            }
            return JS_UNDEFINED;
        }
        JS_FreeValue(context, JS_GetException(context));
        break;

    case kTimer_interval:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            [timer setInterval:fValue];
            return JS_UNDEFINED;
        }
        JS_FreeValue(context, JS_GetException(context));
        break;

    default:
        OOJSReportBadPropertySelector(context, this, magic, sTimerProperties, OOJS_COUNT(sTimerProperties));
        return JS_EXCEPTION;
    }

    OOJSReportBadPropertyValue(context, this, magic, sTimerProperties, OOJS_COUNT(sTimerProperties), value);
    return JS_EXCEPTION;

    OOJS_NATIVE_EXIT
}

static void TimerFinalize(JSRuntime* runtime, JSValueConst this)
{
    OOJS_PROFILE_ENTER

    // Can't use JSTimerGetTimer() here - potential chicken-and-egg problem manifesting as a crash.
    OOJSTimer* timer = (OOJSTimer*)JS_GetOpaque(this, sTimerClassID);

    if (timer != nil) {
        if ([timer isScheduled]) {
            OOLogWARN(@"script.javaScript.unrootedTimer", @"Timer %@ is being garbage-collected while still running. You must keep a reference to all running timers, or they will stop unpredictably!", timer);
        }
        [timer clearJSSelf];
        [timer release];
        JS_SetOpaque(this, NULL);
    }

    OOJS_PROFILE_EXIT_VOID
}

// new Timer(this : Object, function : Function, delay : Number [, interval : Number]) : Timer
static JSValue TimerConstruct(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    JSValueConst function = JS_UNDEFINED;
    double delay;
    double interval = -1.0;
    OOJSTimer* timer = nil;
    JSValue callbackThis = JS_NULL;

    if (EXPECT_NOT(!OOJS_IS_CONSTRUCTING)) {
        OOJSReportError(context, @"Timer() cannot be called as a function, it must be used as a constructor (as in new Timer(...)).");
        return JS_EXCEPTION;
    }

    if (argc < 3) {
        OOJSReportBadArguments(context, nil, @"Timer", argc, OOJS_ARGV, @"Invalid arguments in constructor", @"(object, function, number [, number])");
        return JS_EXCEPTION;
    }

    if (!JS_IsNull(OOJS_ARGV[0]) && !JS_IsUndefined(OOJS_ARGV[0])) {
        callbackThis = JS_ToObject(context, OOJS_ARGV[0]);
        if (JS_IsException(callbackThis)) {
            JS_FreeValue(context, JS_GetException(context));
            OOJSReportBadArguments(context, nil, @"Timer", 1, OOJS_ARGV, @"Invalid argument in constructor", @"object");
            return JS_EXCEPTION;
        }
    }

    function = OOJS_ARGV[1];
    if (!JS_IsFunction(context, function)) {
        JS_FreeValue(context, callbackThis);
        OOJSReportBadArguments(context, nil, @"Timer", 1, OOJS_ARGV + 1, @"Invalid argument in constructor", @"function");
        return JS_EXCEPTION;
    }

    if (JS_ToFloat64(context, &delay, OOJS_ARGV[2]) < 0 || isnan(delay)) {
        if (JS_HasException(context))
            JS_FreeValue(context, JS_GetException(context));
        JS_FreeValue(context, callbackThis);
        OOJSReportBadArguments(context, nil, @"Timer", 1, OOJS_ARGV + 2, @"Invalid argument in constructor", @"number");
        return JS_EXCEPTION;
    }

    // Fourth argument is optional.
    if (3 < argc && JS_ToFloat64(context, &interval, OOJS_ARGV[3]) < 0) {
        JS_FreeValue(context, JS_GetException(context));
        interval = -1;
    }

    // Ensure interval is not too small.
    if (0.0 < interval && interval < kMinInterval)
        interval = kMinInterval;

    timer = [[OOJSTimer alloc] initWithDelay:delay
                                    interval:interval
                                     context:context
                                    function:function
                                        this:callbackThis];
    JS_FreeValue(context, callbackThis);
    if (EXPECT_NOT(!timer))
        return OOJSNativeFailure(context);

    if (delay >= 0) // Leave in stopped state if delay is negative
    {
        [timer scheduleTimer];
    }
    JSValue result = [timer transferJSSelf];
    [timer autorelease];
    return result;

    OOJS_NATIVE_EXIT
}

// *** Methods ***

// start() : Boolean
static JSValue TimerStart(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOJSTimer* thisTimer = nil;

    if (EXPECT_NOT(!JSTimerGetTimer(context, OOJS_THIS, &thisTimer)))
        return OOJSNativeFailure(context);

    OOJS_RETURN_BOOL([thisTimer scheduleTimer]);

    OOJS_NATIVE_EXIT
}

// stop()
static JSValue TimerStop(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOJSTimer* thisTimer = nil;

    if (EXPECT_NOT(!JSTimerGetTimer(context, OOJS_THIS, &thisTimer)))
        return OOJSNativeFailure(context);

    [thisTimer unscheduleTimer];
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}
