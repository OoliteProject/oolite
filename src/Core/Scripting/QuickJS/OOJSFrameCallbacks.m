/*

OOJSFrameCallbacks.m


Copyright (C) 2011-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOJSFrameCallbacks.h"
#import "OOCollectionExtractors.h"
#import "OOJSEngineTimeManagement.h"

/*
        By default, tracking IDs are scrambled to discourage people from trying to
        be clever or making assumptions about them. If DEBUG_FCB_SIMPLE_TRACKING_IDS
        is non-zero, tracking IDs starting from 1 and rising monotonously are used
        instead. Additionally, the next ID is reset to 1 when all frame callbacks
        are removed.
*/
#ifndef DEBUG_FCB_SIMPLE_TRACKING_IDS
#define DEBUG_FCB_SIMPLE_TRACKING_IDS 0
#endif

#ifndef DEBUG_FCB_VERBOSE_LOGGING
#define DEBUG_FCB_VERBOSE_LOGGING 0
#endif

#if defined(NDEBUG) && DEBUG_FCB_SIMPLE_TRACKING_IDS
#error Deployment builds may not be built with DEBUG_FCB_SIMPLE_TRACKING_IDS.
#endif

#if DEBUG_FCB_VERBOSE_LOGGING
#define FCBLog OOLog
#define FCBLogIndentIf OOLogIndentIf
#define FCBLogOutdentIf OOLogOutdentIf
#else
#define FCBLog(...) \
    do {            \
    } while (0)
#define FCBLogIndentIf(key) \
    do {                    \
    } while (0)
#define FCBLogOutdentIf(key) \
    do {                     \
    } while (0)
#endif

enum {
    kMinCount = 16,

#if DEBUG_FCB_SIMPLE_TRACKING_IDS
    kIDScrambleMask = 0,
    kIDIncrement = 1
#else
    kIDScrambleMask = 0x2315EB16, // Just a random number.
    kIDIncrement = 992699 // A large prime number, to produce a non-obvious sequence which still uses all 2^32 values.
#endif
};

typedef struct
{
    JSValue callback; // Owned.
    uint32_t trackingID;
    uint32_t _padding;
} CallbackEntry;

/*	SpiderMonkey needed each slot to be a GC root. With QuickJS, each occupied
        slot simply owns a reference to its callback, which is freed when the
        callback is removed. OOJavaScriptEngine calls OOJSFrameCallbacksRemoveAll()
        before resetting or shutting down, so no reset observer is needed.
*/
static CallbackEntry* sCallbacks;
static NSUInteger sCount; // Number of slots in use.
static NSUInteger sSpace; // Number of slots allocated.
static NSMutableArray* sDeferredOps; // Deferred adds/removes while running.
static uint32_t sNextID;
static BOOL sRunning;

// Methods
static JSValue GlobalAddFrameCallback(OOJS_NATIVE_ARGS);
static JSValue GlobalRemoveFrameCallback(OOJS_NATIVE_ARGS);
static JSValue GlobalIsValidFrameCallback(OOJS_NATIVE_ARGS);

// Internals
static BOOL AddCallback(JSContext* context, JSValueConst callback, uint32_t trackingID, NSString** errorString);
static BOOL GrowCallbackList(JSContext* context, NSString** errorString);

static BOOL GetIndexForTrackingID(uint32_t trackingID, NSUInteger* outIndex);

static BOOL RemoveCallbackWithTrackingID(JSContext* context, uint32_t trackingID);
static void RemoveCallbackAtIndex(JSContext* context, NSUInteger index);

static void QueueDeferredOperation(NSString* opType, uint32_t trackingID, OOJSValue* value);
static void RunDeferredOperations(JSContext* context);

static const JSCFunctionListEntry sFrameCallbackMethods[] = {
    // JS name						Function						min args
    JS_CFUNC_DEF2("addFrameCallback", 1, GlobalAddFrameCallback, OOJS_METHOD_READONLY),
    JS_CFUNC_DEF2("removeFrameCallback", 1, GlobalRemoveFrameCallback, OOJS_METHOD_READONLY),
    JS_CFUNC_DEF2("isValidFrameCallback", 1, GlobalIsValidFrameCallback, OOJS_METHOD_READONLY),
};

// MARK: Public

void InitOOJSFrameCallbacks(JSContext* context, JSValueConst global)
{
    JS_SetPropertyFunctionList(context, global, sFrameCallbackMethods, OOJS_COUNT(sFrameCallbackMethods));

#if DEBUG_FCB_SIMPLE_TRACKING_IDS
    sNextID = 1;
#else
    // Set randomish initial ID to catch bad habits.
    sNextID = [[NSDate date] timeIntervalSinceReferenceDate];
#endif
}

void OOJSFrameCallbacksInvoke(OOTimeDelta inDeltaT)
{
    NSCAssert1(!sRunning, @"%s cannot be called while frame callbacks are running.", __PRETTY_FUNCTION__);

    if (sCount != 0) {
        const OOTimeDelta delta = inDeltaT * [UNIVERSE timeAccelerationFactor];
        JSContext* context = OOJSAcquireContext();
        JSValue deltaVal = JS_NewNumber(context, delta);
        // As with JS_CallFunctionValue() with a NULL this, callbacks are called with the global object as this.
        JSValue global = JS_GetGlobalObject(context);
        NSUInteger i;

        // Block mutations.
        sRunning = YES;

        /*
                The watchdog timer only fires once per second in deployment builds,
                but in testrelease builds at least we can keep them on a short leash.
                (With QuickJS the limit is checked by the interrupt handler.)
        */
        OOJSStartTimeLimiterWithTimeLimit(0.1);

        for (i = 0; i < sCount; i++) {
            // TODO: remove out of scope callbacks - post MNSR!
            JSValue result = JS_Call(context, sCallbacks[i].callback, global, 1, (JSValueConst*)&deltaVal);
            if (JS_IsException(result)) {
                OOJSReportPendingException(context);
            }
            JS_FreeValue(context, result);
        }

        OOJSStopTimeLimiter();
        sRunning = NO;

        JS_FreeValue(context, global);
        JS_FreeValue(context, deltaVal);

        if (EXPECT_NOT(sDeferredOps != NULL)) {
            RunDeferredOperations(context);
            DESTROY(sDeferredOps);
        }
        OOJSRelinquishContext(context);
    }
}

void OOJSFrameCallbacksRemoveAll(void)
{
    NSCAssert1(!sRunning, @"%s cannot be called while frame callbacks are running.", __PRETTY_FUNCTION__);

    if (sCount != 0) {
        JSContext* context = OOJSAcquireContext();
        while (sCount != 0)
            RemoveCallbackAtIndex(context, sCount - 1);
        OOJSRelinquishContext(context);
    }
}

// MARK: Methods

// addFrameCallback(callback : Function) : Number
static JSValue GlobalAddFrameCallback(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    // Get callback argument and verify that it's a function.
    JSValueConst callback = OOJS_ARGV[0];
    if (EXPECT_NOT(argc < 1 || !OOJSValueIsFunction(context, callback))) {
        OOJSReportBadArguments(context, nil, @"addFrameCallback", MIN(argc, 1), OOJS_ARGV, nil, @"function");
        return JS_EXCEPTION;
    }

    // Assign a tracking ID.
    uint32_t trackingID = sNextID ^ kIDScrambleMask;
    sNextID += kIDIncrement;

    if (EXPECT(!sRunning)) {
        // Add to list immediately.
        NSString* errorString = nil;
        if (EXPECT_NOT(!AddCallback(context, callback, trackingID, &errorString))) {
            OOJSReportError(context, @"%@", errorString);
            return JS_EXCEPTION;
        }
    } else {
        // Defer mutations during callback invocation.
        FCBLog(@"script.frameCallback.debug.add.deferred", @"Deferring addition of frame callback with tracking ID %u.", trackingID);
        QueueDeferredOperation(@"add", trackingID, [OOJSValue valueWithJSValue:callback inContext:context]);
    }

    OOJS_RETURN_INT(trackingID);

    OOJS_NATIVE_EXIT
}

// removeFrameCallback(trackingID : Number)
static JSValue GlobalRemoveFrameCallback(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    // Get tracking ID argument.
    uint32_t trackingID;
    if (EXPECT_NOT(argc < 1 || JS_ToUint32(context, &trackingID, OOJS_ARGV[0]) < 0)) {
        if (JS_HasException(context))
            JS_FreeValue(context, JS_GetException(context));
        OOJSReportBadArguments(context, nil, @"removeFrameCallback", MIN(argc, 1), OOJS_ARGV, nil, @"frame callback tracking ID");
        return JS_EXCEPTION;
    }

    if (EXPECT(!sRunning)) {
        // Remove it.
        if (EXPECT_NOT(!RemoveCallbackWithTrackingID(context, trackingID))) {
            OOJSReportWarning(context, @"removeFrameCallback(): invalid tracking ID.");
        }
    } else {
        // Defer mutations during callback invocation.
        FCBLog(@"script.frameCallback.debug.remove.deferred", @"Deferring removal of frame callback with tracking ID %u.", trackingID);
        QueueDeferredOperation(@"remove", trackingID, nil);
    }

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// isValidFrameCallback(trackingID : Number)
static JSValue GlobalIsValidFrameCallback(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (EXPECT_NOT(argc < 1)) {
        OOJSReportBadArguments(context, nil, @"isValidFrameCallback", 0, OOJS_ARGV, nil, @"frame callback tracking ID");
        return JS_EXCEPTION;
    }

    // Get tracking ID argument.
    uint32_t trackingID;
    if (EXPECT_NOT(JS_ToUint32(context, &trackingID, OOJS_ARGV[0]) < 0)) {
        JS_FreeValue(context, JS_GetException(context));
        OOJS_RETURN_BOOL(NO);
    }

    NSUInteger index;
    OOJS_RETURN_BOOL(GetIndexForTrackingID(trackingID, &index));

    OOJS_NATIVE_EXIT
}

// MARK: Internals

static BOOL AddCallback(JSContext* context, JSValueConst callback, uint32_t trackingID, NSString** errorString)
{
    NSCParameterAssert(context != NULL);
    NSCParameterAssert(errorString != NULL);
    NSCAssert1(!sRunning, @"%s cannot be called while frame callbacks are running.", __PRETTY_FUNCTION__);

    if (EXPECT_NOT(sCount == sSpace)) {
        if (!GrowCallbackList(context, errorString))
            return NO;
    }

    FCBLog(@"script.frameCallback.debug.add", @"Adding frame callback with tracking ID %u.", trackingID);

    sCallbacks[sCount].callback = JS_DupValue(context, callback);
    sCallbacks[sCount].trackingID = trackingID;
    sCount++;

    return YES;
}

static BOOL GrowCallbackList(JSContext* context, NSString** errorString)
{
    NSCParameterAssert(context != NULL);
    NSCParameterAssert(errorString != NULL);

    NSUInteger newSpace = MAX(sSpace * 2, (NSUInteger)kMinCount);

    CallbackEntry* newCallbacks = calloc(sizeof(CallbackEntry), newSpace);
    if (newCallbacks == NULL) {
        *errorString = @"Failed to allocate space for frame callback.";
        return NO;
    }

    // Move occupied slots; the references move with them.
    if (sCount != 0)
        memcpy(newCallbacks, sCallbacks, sizeof(CallbackEntry) * sCount);

    // Replace array.
    free(sCallbacks);
    sCallbacks = newCallbacks;
    sSpace = newSpace;

    return YES;
}

static BOOL GetIndexForTrackingID(uint32_t trackingID, NSUInteger* outIndex)
{
    NSCParameterAssert(outIndex != NULL);

    /*	It is assumed that few frame callbacks will be active at once, so a
            linear search is reasonable. If they become unexpectedly popular, we
            can switch to a sorted list or a separate lookup table without changing
            the API.
    */
    NSUInteger i;
    for (i = 0; i < sCount; i++) {
        if (sCallbacks[i].trackingID == trackingID) {
            *outIndex = i;
            return YES;
        }
    }

    return NO;
}

static BOOL RemoveCallbackWithTrackingID(JSContext* context, uint32_t trackingID)
{
    NSCParameterAssert(context != NULL);
    NSCAssert1(!sRunning, @"%s cannot be called while frame callbacks are running.", __PRETTY_FUNCTION__);

    NSUInteger index = 0;
    if (GetIndexForTrackingID(trackingID, &index)) {
        RemoveCallbackAtIndex(context, index);
        return YES;
    }

    return NO;
}

static void RemoveCallbackAtIndex(JSContext* context, NSUInteger index)
{
    NSCParameterAssert(context != NULL);
    NSCParameterAssert(index < sCount && sCallbacks != NULL);
    NSCAssert1(!sRunning, @"%s cannot be called while frame callbacks are running.", __PRETTY_FUNCTION__);

    FCBLog(@"script.frameCallback.debug.remove", @"Removing frame callback with tracking ID %u.", sCallbacks[index].trackingID);

    // Overwrite entry to be removed with last entry, and decrement count.
    JSValue removed = sCallbacks[index].callback;
    sCount--;
    sCallbacks[index] = sCallbacks[sCount];
    sCallbacks[sCount].callback = JS_NULL;
    JS_FreeValue(context, removed);

#if DEBUG_FCB_SIMPLE_TRACKING_IDS
    if (sCount == 0) {
        OOLog(@"script.frameCallback.debug.reset", @"All frame callbacks removed, resetting next ID to 1.");
        sNextID = 1;
    }
#endif
}

static void QueueDeferredOperation(NSString* opType, uint32_t trackingID, OOJSValue* value)
{
    NSCAssert1(sRunning, @"%s can only be called while frame callbacks are running.", __PRETTY_FUNCTION__);

    if (sDeferredOps == nil)
        sDeferredOps = [[NSMutableArray alloc] init];
    [sDeferredOps addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                    opType, @"operation",
                                [NSNumber numberWithInt:trackingID], @"trackingID",
                                value, @"value",
                                nil]];
}

static void RunDeferredOperations(JSContext* context)
{
    NSDictionary* operation = nil;

    FCBLog(@"script.frameCallback.debug.run-deferred", @"Running %zu deferred frame callback operations.", (long)[sDeferredOps count]);
    FCBLogIndentIf(@"script.frameCallback.debug.run-deferred");

    foreach (operation, sDeferredOps) {
        NSString* opType = [operation objectForKey:@"operation"];
        uint32_t trackingID = [operation oo_intForKey:@"trackingID"];

        if ([opType isEqualToString:@"add"]) {
            OOJSValue* callbackObj = [operation objectForKey:@"value"];
            NSString* errorString = nil;

            JSValue callback = OOJSValueFromNativeObject(context, callbackObj);
            if (!AddCallback(context, callback, trackingID, &errorString)) {
                OOLogWARN(@"script.frameCallback.deferredAdd.failed", @"Deferred frame callback insertion failed: %@", errorString);
            }
            JS_FreeValue(context, callback);
        } else if ([opType isEqualToString:@"remove"]) {
            RemoveCallbackWithTrackingID(context, trackingID);
        }
    }

    FCBLogOutdentIf(@"script.frameCallback.debug.run-deferred");
}
