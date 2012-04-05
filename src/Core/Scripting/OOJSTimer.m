/*

OOJSTimer.m


Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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


static JSObject *sTimerPrototype;
static JSClass sTimerClass;


@interface OOJSTimer (Private)

- (id) initWithDelay:(OOTimeAbsolute)delay
			interval:(OOTimeDelta)interval
			 context:(JSContext *)context
			function:(jsval)function
				this:(JSObject *)jsThis;

@end


@implementation OOJSTimer

- (id) initWithDelay:(OOTimeAbsolute)delay
			interval:(OOTimeDelta)interval
			 context:(JSContext *)context
			function:(jsval)function
				this:(JSObject *)jsThis
{
	self = [super initWithNextTime:[UNIVERSE getTime] + delay interval:interval];
	if (self != nil)
	{
		NSAssert(OOJSValueIsFunction(context, function), @"Attempt to init OOJSTimer with a function that isn't.");
		
		_jsThis = jsThis;
		OOJSAddGCObjectRoot(context, &_jsThis, "OOJSTimer this");
		
		_function = function;
		OOJSAddGCValueRoot(context, &_function, "OOJSTimer function");
		
		_jsSelf = JS_NewObject(context, &sTimerClass, sTimerPrototype, NULL);
		if (_jsSelf != NULL)
		{
			if (!JS_SetPrivate(context, _jsSelf, [self retain]))  _jsSelf = NULL;
		}
		if (_jsSelf == NULL)
		{
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


- (void) deleteJSPointers
{
	[self unscheduleTimer];
	
	if (_jsThis != NULL)
	{
		_jsThis = NULL;
		_function = JSVAL_VOID;
		
		JSContext *context = OOJSAcquireContext();
		JS_RemoveObjectRoot(context, &_jsThis);
		JS_RemoveValueRoot(context, &_function);
		OOJSRelinquishContext(context);
		
		[[NSNotificationCenter defaultCenter] removeObserver:self
														name:kOOJavaScriptEngineWillResetNotification
													  object:[OOJavaScriptEngine sharedEngine]];
	}
}


- (void) dealloc
{
	[_owningScript release];
	
	[self deleteJSPointers];
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	NSString				*funcName = nil;
	JSContext				*context = NULL;
	
	if (JSVAL_IS_VOID(_function) || JSVAL_IS_NULL(_function))
	{
		return @"invalid";
	}
	
	context = OOJSAcquireContext();
	funcName = OOStringFromJSString(context, JS_GetFunctionId(JS_ValueToFunction(context, _function)));
	OOJSRelinquishContext(context);
	
	if (funcName == nil)
	{
		funcName = @"anonymous";
	}
	
	return [NSString stringWithFormat:@"%@, function: %@", [super descriptionComponents], funcName];
}


- (NSString *) oo_jsClassName
{
	return @"Timer";
}


- (void) timerFired
{
	jsval					rval = JSVAL_VOID;
	NSString				*description = nil;
	
	OOJavaScriptEngine *engine = [OOJavaScriptEngine sharedEngine];
	JSContext *context = OOJSAcquireContext();
	
	// stop and remove the timer if _jsThis (the first parameter in the constructor) dies.
	id object = OOJSNativeObjectFromJSObject(context, _jsThis);
	if (object != nil)
	{
		description = [object oo_jsDescription];
		if (description == nil)  description = [object description];
	}
	
	if (description == nil)
	{
		[self unscheduleTimer];
		OOJSRelinquishContext(context);
		return;
	}
	
	[OOJSScript pushScript:_owningScript];
	[engine callJSFunction:_function
				 forObject:_jsThis
					  argc:0
					  argv:NULL
					result:&rval];
	[OOJSScript popScript:_owningScript];
	
	OOJSRelinquishContext(context);
}


- (jsval) oo_jsValueInContext:(JSContext *)context
{
	return OBJECT_TO_JSVAL(_jsSelf);
}

@end


static JSBool TimerGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool TimerSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);
static void TimerFinalize(JSContext *context, JSObject *this);
static JSBool TimerConstruct(JSContext *context, uintN argc, jsval *vp);

// Methods
static JSBool TimerStart(JSContext *context, uintN argc, jsval *vp);
static JSBool TimerStop(JSContext *context, uintN argc, jsval *vp);


static JSClass sTimerClass =
{
	"Timer",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,		// addProperty
	JS_PropertyStub,		// delProperty
	TimerGetProperty,		// getProperty
	TimerSetProperty,		// setProperty
	JS_EnumerateStub,		// enumerate
	JS_ResolveStub,			// resolve
	JS_ConvertStub,			// convert
	TimerFinalize,			// finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
};


enum
{
	// Property IDs
	kTimer_nextTime,			// next fire time, double, read/write
	kTimer_interval,			// interval, double, read/write
	kTimer_isRunning			// is scheduled, boolean, read-only
};


static JSPropertySpec sTimerProperties[] =
{
	// JS name					ID							flags
	{ "interval",				kTimer_interval,			OOJS_PROP_READWRITE_CB },
	{ "isRunning",				kTimer_isRunning,			OOJS_PROP_READONLY_CB },
	{ "nextTime",				kTimer_nextTime,			OOJS_PROP_READWRITE_CB },
	{ 0 }
};


static JSFunctionSpec sTimerMethods[] =
{
	// JS name					Function					min args
	{ "toString",				OOJSObjectWrapperToString,	0 },
	{ "start",					TimerStart,					0 },
	{ "stop",					TimerStop,					0 },
	{ 0 }
};


DEFINE_JS_OBJECT_GETTER(JSTimerGetTimer, &sTimerClass, sTimerPrototype, OOJSTimer);


void InitOOJSTimer(JSContext *context, JSObject *global)
{
	sTimerPrototype = JS_InitClass(context, global, NULL, &sTimerClass, TimerConstruct, 0, sTimerProperties, sTimerMethods, NULL, NULL);
	OOJSRegisterObjectConverter(&sTimerClass, OOJSBasicPrivateObjectConverter);
}


static JSBool TimerGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	OOJSTimer				*timer = nil;
	
	if (EXPECT_NOT(!JSTimerGetTimer(context, this, &timer))) return NO;
	
	switch (JSID_TO_INT(propID))
	{
		case kTimer_nextTime:
			return JS_NewNumberValue(context, [timer nextTime], value);
			
		case kTimer_interval:
			return JS_NewNumberValue(context, [timer interval], value);
			
		case kTimer_isRunning:
			*value = OOJSValueFromBOOL([timer isScheduled]);
			return YES;
			
		default:
			OOJSReportBadPropertySelector(context, this, propID, sTimerProperties);
			return NO;
	}
	
	OOJS_NATIVE_EXIT
}


static JSBool TimerSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	OOJSTimer				*timer = nil;
	double					fValue;
	
	if (EXPECT_NOT(!JSTimerGetTimer(context, this, &timer))) return NO;
	
	switch (JSID_TO_INT(propID))
	{
		case kTimer_nextTime:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				if (![timer setNextTime:fValue])
				{
					OOJSReportWarning(context, @"Ignoring attempt to change next fire time for running timer %@.", timer);
				}
				return YES;
			}
			break;
			
		case kTimer_interval:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[timer setInterval:fValue];
				return YES;
			}
			break;
			
		default:
			OOJSReportBadPropertySelector(context, this, propID, sTimerProperties);
			return NO;
	}
	
	OOJSReportBadPropertyValue(context, this, propID, sTimerProperties, *value);
	return NO;
	
	OOJS_NATIVE_EXIT
}


static void TimerFinalize(JSContext *context, JSObject *this)
{
	OOJS_PROFILE_ENTER
	
	// Can't use JSTimerGetTimer() here - potential chicken-and-egg problem manifesting as a crash.
	OOJSTimer *timer = (OOJSTimer *)JS_GetPrivate(context, this);
	
	if (timer != nil)
	{
		if ([timer isScheduled])
		{
			OOLogWARN(@"script.javaScript.unrootedTimer", @"Timer %@ is being garbage-collected while still running. You must keep a reference to all running timers, or they will stop unpredictably!", timer);
		}
		[timer release];
		JS_SetPrivate(context, this, NULL);
	}
	
	OOJS_PROFILE_EXIT_VOID
}


// new Timer(this : Object, function : Function, delay : Number [, interval : Number]) : Timer
static JSBool TimerConstruct(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	jsval					function = JSVAL_VOID;
	double					delay;
	double					interval = -1.0;
	OOJSTimer				*timer = nil;
	JSObject				*callbackThis = NULL;
	
	if (EXPECT_NOT(!JS_IsConstructing(context, vp)))
	{
		OOJSReportError(context, @"Timer() cannot be called as a function, it must be used as a constructor (as in new Timer(...)).");
		return NO;
	}
	
	if (argc < 3)
	{
		OOJSReportBadArguments(context, nil, @"Timer", argc, OOJS_ARGV, @"Invalid arguments in constructor", @"(object, function, number [, number])");
		return NO;
	}
	
	if (!JSVAL_IS_NULL(OOJS_ARGV[0]) && !JSVAL_IS_VOID(OOJS_ARGV[0]))
	{
		if (!JS_ValueToObject(context, OOJS_ARGV[0], &callbackThis))
		{
			OOJSReportBadArguments(context, nil, @"Timer", 1, OOJS_ARGV, @"Invalid argument in constructor", @"object");
			return NO;
		}
	}
	
	function = OOJS_ARGV[1];
	if (JS_ValueToFunction(context, function) == NULL)
	{
		OOJSReportBadArguments(context, nil, @"Timer", 1, OOJS_ARGV + 1, @"Invalid argument in constructor", @"function");
		return NO;
	}
	
	if (!JS_ValueToNumber(context, OOJS_ARGV[2], &delay) || isnan(delay))
	{
		OOJSReportBadArguments(context, nil, @"Timer", 1, OOJS_ARGV + 2, @"Invalid argument in constructor", @"number");
		return NO;
	}
	
	// Fourth argument is optional.
	if (3 < argc && !JS_ValueToNumber(context, OOJS_ARGV[3], &interval))  interval = -1;
	
	// Ensure interval is not too small.
	if (0.0 < interval && interval < kMinInterval)  interval = kMinInterval;
	
	timer = [[OOJSTimer alloc] initWithDelay:delay
									interval:interval
									 context:context
									function:function
										this:callbackThis];
	if (EXPECT_NOT(!timer))  return NO;
	
	if (delay >= 0)	// Leave in stopped state if delay is negative
	{
		[timer scheduleTimer];
	}
	[timer autorelease];
	OOJS_RETURN_OBJECT(timer);
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

// start() : Boolean
static JSBool TimerStart(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	OOJSTimer					*thisTimer = nil;
	
	if (EXPECT_NOT(!JSTimerGetTimer(context, OOJS_THIS, &thisTimer)))  return NO;
	
	OOJS_RETURN_BOOL([thisTimer scheduleTimer]);
	
	OOJS_NATIVE_EXIT
}


// stop()
static JSBool TimerStop(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	OOJSTimer					*thisTimer = nil;
	
	if (EXPECT_NOT(!JSTimerGetTimer(context, OOJS_THIS, &thisTimer)))  return NO;
	
	[thisTimer unscheduleTimer];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
