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

#include "OOJSFrameCallbacks.h"
#include "OOJSEngineTimeManagement.h"
#include "oofnd/Date.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/objc/OOAssert.h"


/*	Converted in bead oo-n041 (proposed ADR-0056 amendment oo-ppc): a binding with no class of its
	own. BOOL/YES/NO are bool/true/false; the file statics and functions whose lines that touched
	are in an anonymous namespace, as the others already were. A deferred add still keeps its
	callback in an OOJSValue (a C++ object since bead oo-wdqw1), and the universe's time acceleration is still a message.
*/


/*
	By default, tracking IDs are scrambled to discourage people from trying to
	be clever or making assumptions about them. If DEBUG_FCB_SIMPLE_TRACKING_IDS
	is non-zero, tracking IDs starting from 1 and rising monotonously are used
	instead. Additionally, the next ID is reset to 1 when all frame callbacks
	are removed.
*/
#ifndef DEBUG_FCB_SIMPLE_TRACKING_IDS
#define DEBUG_FCB_SIMPLE_TRACKING_IDS	0
#endif

#ifndef DEBUG_FCB_VERBOSE_LOGGING
#define DEBUG_FCB_VERBOSE_LOGGING		0
#endif



#if defined (NDEBUG) && DEBUG_FCB_SIMPLE_TRACKING_IDS
#error Deployment builds may not be built with DEBUG_FCB_SIMPLE_TRACKING_IDS.
#endif

#if DEBUG_FCB_VERBOSE_LOGGING
#define FCBLog					OO_LOG
#define FCBLogIndentIf(key)		oo::log::indentIf(key)
#define FCBLogOutdentIf(key)	oo::log::outdentIf(key)
#else
#define FCBLog(...)				do {} while (0)
#define FCBLogIndentIf(key)		do {} while (0)
#define FCBLogOutdentIf(key)	do {} while (0)
#endif


enum
{
	kMinCount					= 16,
	
#if DEBUG_FCB_SIMPLE_TRACKING_IDS
	kIDScrambleMask				= 0,
	kIDIncrement				= 1
#else
	kIDScrambleMask				= 0x2315EB16,	// Just a random number.
	kIDIncrement				= 992699		// A large prime number, to produce a non-obvious sequence which still uses all 2^32 values.
#endif
};


typedef struct
{
	ooscript::Value					callback;
	uint32_t					trackingID;
	uint32_t					_padding;
} CallbackEntry;


static CallbackEntry	*sCallbacks;
static NSUInteger		sCount;			// Number of slots in use.
static NSUInteger		sSpace;			// Number of slots allocated.
static NSUInteger		sHighWaterMark;	// Number of slots which are GC roots.
// A deferred add or remove (proposed ADR-0043: was a Foundation dictionary with the same three entries).
typedef struct
{
	std::string					operation;		// "add" or "remove"
	uint32_t					trackingID;
	oo::Ref<OOJSValue>		value;			// the callback, for "add"
} DeferredOperation;

namespace {
static std::vector<DeferredOperation>	*sDeferredOps;	// Deferred adds/removes while running.
} // namespace
static uint32_t			sNextID;
namespace {
static bool				sRunning;
} // namespace


// Methods
static bool GlobalAddFrameCallback(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool GlobalRemoveFrameCallback(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool GlobalIsValidFrameCallback(ooscript::Context context, ooscript::CallArgs &oojsArgs);


// Internals
namespace {
static bool AddCallback(ooscript::Context context, ooscript::Value callback, uint32_t trackingID, std::optional<std::string> *errorString);
static bool GrowCallbackList(ooscript::Context context, std::optional<std::string> *errorString);
} // namespace

namespace {
static bool GetIndexForTrackingID(uint32_t trackingID, NSUInteger *outIndex);
} // namespace

namespace {
static bool RemoveCallbackWithTrackingID(ooscript::Context context, uint32_t trackingID);
} // namespace
static void RemoveCallbackAtIndex(ooscript::Context context, NSUInteger index);

namespace {
static void QueueDeferredOperation(const std::string &opType, uint32_t trackingID, OOJSValue *value);
} // namespace
static void RunDeferredOperations(ooscript::Context context);


// MARK: Public

void InitOOJSFrameCallbacks(ooscript::Context context, ooscript::Object global)
{
	ooscript::defineFunction(context, global, "addFrameCallback", GlobalAddFrameCallback, 1, OOJS_METHOD_READONLY);
	ooscript::defineFunction(context, global, "removeFrameCallback", GlobalRemoveFrameCallback, 1, OOJS_METHOD_READONLY);
	ooscript::defineFunction(context, global, "isValidFrameCallback", GlobalIsValidFrameCallback, 1, OOJS_METHOD_READONLY);
	
#if DEBUG_FCB_SIMPLE_TRACKING_IDS
	sNextID = 1;
#else
	// Set randomish initial ID to catch bad habits.
	sNextID =  oo::date::timeIntervalSinceReferenceDate();
#endif
}


void OOJSFrameCallbacksInvoke(OOTimeDelta inDeltaT)
{
	OOCAssert(!sRunning, "%s cannot be called while frame callbacks are running.", __PRETTY_FUNCTION__);
	
	if (sCount != 0)
	{
		const OOTimeDelta	delta = inDeltaT * (UNIVERSE != nullptr ? UNIVERSE->getTimeAccelerationFactor() : 0.0);
		ooscript::Context context = OOJSAcquireContext();
		ooscript::Value				deltaVal, result;
		NSUInteger			i;
		
		if (EXPECT(ooscript::newNumberValue(context, delta, &deltaVal)))
		{
			// Block mutations.
			sRunning = true;
			
			/*
				The watchdog timer only fires once per second in deployment builds,
				but in testrelease builds at least we can keep them on a short leash.
			*/
			OOJSStartTimeLimiterWithTimeLimit(0.1);
			
			for (i = 0; i < sCount; i++)
			{
				// TODO: remove out of scope callbacks - post MNSR!
				ooscript::callFunctionValue(context, NULL, sCallbacks[i].callback, 1, &deltaVal, &result);
				ooscript::reportPendingException(context);
			}
			
			OOJSStopTimeLimiter();
			sRunning = false;
			
			if (EXPECT_NOT(sDeferredOps != NULL))
			{
				RunDeferredOperations(context);
				delete sDeferredOps;
				sDeferredOps = NULL;
			}
		}
		OOJSRelinquishContext(context);
	}
}


void OOJSFrameCallbacksRemoveAll(void)
{
	OOCAssert(!sRunning, "%s cannot be called while frame callbacks are running.", __PRETTY_FUNCTION__);
	
	if (sCount != 0)
	{
		ooscript::Context context = OOJSAcquireContext();
		while (sCount != 0)  RemoveCallbackAtIndex(context, sCount - 1);
		OOJSRelinquishContext(context);
	}
}


// MARK: Methods

// addFrameCallback(callback : Function) : Number
static bool GlobalAddFrameCallback(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	// Get callback argument and verify that it's a function.
	ooscript::Value callback = OOJS_ARGV[0];
	if (EXPECT_NOT(oojsArgs.count() < 1 || !OOJSValueIsFunction(context, callback)))
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "addFrameCallback", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "function");
		return false;
	}
	
	// Assign a tracking ID.
	uint32_t trackingID = sNextID ^ kIDScrambleMask;
	sNextID += kIDIncrement;
	
	if (EXPECT(!sRunning))
	{
		// Add to list immediately.
		std::optional<std::string> errorString;
		if (EXPECT_NOT(!AddCallback(context, callback, trackingID, &errorString)))
		{
			cxx_OOJSReportError(context, "%s", (errorString ? errorString->c_str() : "(null)"));
			return false;
		}
	}
	else
	{
		// Defer mutations during callback invocation.
		FCBLog("script.frameCallback.debug.add.deferred", "Deferring addition of frame callback with tracking ID {}.", trackingID);
		QueueDeferredOperation("add", trackingID, OOJSValue::valueWithJSValue(callback, context).get());
	}
	
	OOJS_RETURN_INT(trackingID);
	
	OOJS_NATIVE_EXIT
}


// removeFrameCallback(trackingID : Number)
static bool GlobalRemoveFrameCallback(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	// Get tracking ID argument.
	uint32_t trackingID;
	if (EXPECT_NOT(oojsArgs.count() < 1 || !ooscript::valueToECMAUint32(context, OOJS_ARGV[0], &trackingID)))
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "removeFrameCallback", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "frame callback tracking ID");
		return false;
	}
	
	if (EXPECT(!sRunning))
	{
		// Remove it.
		if (EXPECT_NOT(!RemoveCallbackWithTrackingID(context, trackingID)))
		{
			cxx_OOJSReportWarning(context, "removeFrameCallback(): invalid tracking ID.");
		}
	}
	else
	{
		// Defer mutations during callback invocation.
		FCBLog("script.frameCallback.debug.remove.deferred", "Deferring removal of frame callback with tracking ID {}.", trackingID);
		QueueDeferredOperation("remove", trackingID, nullptr);
	}
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// isValidFrameCallback(trackingID : Number)
static bool GlobalIsValidFrameCallback(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(oojsArgs.count() < 1))
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "isValidFrameCallback", 0, OOJS_ARGV, std::nullopt, "frame callback tracking ID");
		return false;
	}
	
	// Get tracking ID argument.
	uint32_t trackingID;
	if (EXPECT_NOT(!ooscript::valueToECMAUint32(context, OOJS_ARGV[0], &trackingID)))
	{
		OOJS_RETURN_BOOL(false);
	}
	
	NSUInteger index;
	OOJS_RETURN_BOOL(GetIndexForTrackingID(trackingID, &index));
	
	OOJS_NATIVE_EXIT
}


// MARK: Internals

namespace {
static bool AddCallback(ooscript::Context context, ooscript::Value callback, uint32_t trackingID, std::optional<std::string> *errorString)
{
	OOCParameterAssert(context != NULL && ooscript::isInRequest(context));
	OOCParameterAssert(errorString != NULL);
	OOCAssert(!sRunning, "%s cannot be called while frame callbacks are running.", __PRETTY_FUNCTION__);
	
	if (EXPECT_NOT(sCount == sSpace))
	{
		if (!GrowCallbackList(context, errorString))  return false;
	}
	
	FCBLog("script.frameCallback.debug.add", "Adding frame callback with tracking ID {}.", trackingID);
	
	sCallbacks[sCount].callback = callback;
	if (sCount >= sHighWaterMark)
	{
		// If we haven't used this slot before, root it.
		
		if (EXPECT_NOT(!OOJSAddGCValueRoot(context, &sCallbacks[sCount].callback, "frame callback")))
		{
			*errorString = "Failed to add GC root for frame callback.";
			return false;
		}
		
		sHighWaterMark = sCount + 1;
	}
	
	sCallbacks[sCount].trackingID = trackingID;
	sCount++;
	
	return true;
}
} // namespace


namespace {
static bool GrowCallbackList(ooscript::Context context, std::optional<std::string> *errorString)
{
	OOCParameterAssert(context != NULL && ooscript::isInRequest(context));
	OOCParameterAssert(errorString != NULL);
	
	NSUInteger newSpace = MAX(sSpace * 2, (NSUInteger)kMinCount);
	
	CallbackEntry *newCallbacks = (CallbackEntry *)calloc(sizeof (CallbackEntry), newSpace);
	if (newCallbacks == NULL)  return false;
	
	CallbackEntry *oldCallbacks = sCallbacks;
	
	// Root and copy occupied slots.
	NSUInteger newHighWaterMark = sCount;
	NSUInteger i;
	for (i = 0; i < newHighWaterMark; i++)
	{
		if (EXPECT_NOT(!OOJSAddGCValueRoot(context, &newCallbacks[i].callback, "frame callback")))
		{
			// If we can't root them all, we fail; unroot all entries to date, free the buffer and return false.
			NSUInteger j;
			for (j = 0; j < i; j++)
			{
				ooscript::removeValueRoot(context, &newCallbacks[j].callback);
			}
			free(newCallbacks);
			
			*errorString = "Failed to add GC root for frame callback.";
			return false;
		}
		newCallbacks[i] = oldCallbacks[i];
	}
	
	// Unroot old array's slots.
	for (i = 0; i < sHighWaterMark; i++)
	{
		ooscript::removeValueRoot(context, &oldCallbacks[i].callback);
	}
	
	// We only rooted the occupied slots, so reset high water mark.
	sHighWaterMark = newHighWaterMark;
	
	// Replace array.
	sCallbacks = newCallbacks;
	free(oldCallbacks);
	sSpace = newSpace;
	
	return true;
}
} // namespace


namespace {
static bool GetIndexForTrackingID(uint32_t trackingID, NSUInteger *outIndex)
{
	OOCParameterAssert(outIndex != NULL);
	
	/*	It is assumed that few frame callbacks will be active at once, so a
		linear search is reasonable. If they become unexpectedly popular, we
		can switch to a sorted list or a separate lookup table without changing
		the API.
	*/
	NSUInteger i;
	for (i = 0; i < sCount; i++)
	{
		if (sCallbacks[i].trackingID == trackingID)
		{
			*outIndex = i;
			return true;
		}
	}
	
	return false;
}
} // namespace


namespace {
static bool RemoveCallbackWithTrackingID(ooscript::Context context, uint32_t trackingID)
{
	OOCParameterAssert(context != NULL && ooscript::isInRequest(context));
	OOCAssert(!sRunning, "%s cannot be called while frame callbacks are running.", __PRETTY_FUNCTION__);
	
	NSUInteger index = 0;
	if (GetIndexForTrackingID(trackingID, &index))
	{
		RemoveCallbackAtIndex(context, index);
		return true;
	}
	
	return false;
}
} // namespace


static void RemoveCallbackAtIndex(ooscript::Context context, NSUInteger index)
{
	OOCParameterAssert(context != NULL && ooscript::isInRequest(context));
	OOCParameterAssert(index < sCount && sCallbacks != NULL);
	OOCAssert(!sRunning, "%s cannot be called while frame callbacks are running.", __PRETTY_FUNCTION__);
	
	FCBLog("script.frameCallback.debug.remove", "Removing frame callback with tracking ID {}.", sCallbacks[index].trackingID);
	
	// Overwrite entry to be removed with last entry, and decrement count.
	sCount--;
	sCallbacks[index] = sCallbacks[sCount];
	sCallbacks[sCount].callback = ooscript::nullValue();
	
#if DEBUG_FCB_SIMPLE_TRACKING_IDS
	if (sCount == 0)
	{
		OO_LOG("script.frameCallback.debug.reset", "All frame callbacks removed, resetting next ID to 1.");
		sNextID = 1;
	}
#endif
}


namespace {
static void QueueDeferredOperation(const std::string &opType, uint32_t trackingID, OOJSValue *value)
{
	OOCAssert(sRunning, "%s can only be called while frame callbacks are running.", __PRETTY_FUNCTION__);
	
	if (sDeferredOps == NULL)  sDeferredOps = new std::vector<DeferredOperation>;
	sDeferredOps->push_back(DeferredOperation{ opType, trackingID, oo::Ref<OOJSValue>(value) });
}
} // namespace


static void RunDeferredOperations(ooscript::Context context)
{
	FCBLog("script.frameCallback.debug.run-deferred", "Running {} deferred frame callback operations.", (long)sDeferredOps->size());
	FCBLogIndentIf("script.frameCallback.debug.run-deferred");
	
	for (const DeferredOperation &operation : *sDeferredOps)
	{
		const std::string	&opType = operation.operation;
		uint32_t		trackingID = operation.trackingID;
		
		if (opType == "add")
		{
			OOJSValue	*callbackObj = operation.value.get();
			std::optional<std::string>	errorString;
			
			if (!AddCallback(context, (callbackObj != nullptr ? callbackObj->jsValueInContext(context) : ooscript::nullValue()), trackingID, &errorString))
			{
				OO_LOG_WARN("script.frameCallback.deferredAdd.failed", "Deferred frame callback insertion failed: {}", errorString.value_or("(null)"));
			}
		}
		else if (opType == "remove")
		{
			RemoveCallbackWithTrackingID(context, trackingID);
		}
	}
	
	FCBLogOutdentIf("script.frameCallback.debug.run-deferred");
}
