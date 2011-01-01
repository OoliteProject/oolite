/*

OOJSTimer.m


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
		NSAssert(JSVAL_IS_OBJECT(function) && JS_ObjectIsFunction(context, JSVAL_TO_OBJECT(function)), @"Attempt to init OOJSTimer with a function that isn't.");
		
		_jsThis = jsThis;
		OOJS_AddGCObjectRoot(context, &_jsThis, "OOJSTimer this");
		
		_function = function;
		OOJS_AddGCValueRoot(context, &_function, "OOJSTimer function");
		
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
	}
	
	return self;
}


- (void) dealloc
{
	[_owningScript release];
	
	// Allow garbage collection.
	[[OOJavaScriptEngine sharedEngine] removeGCObjectRoot:&_jsThis];
	[[OOJavaScriptEngine sharedEngine] removeGCValueRoot:&_function];
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	JSString				*funcJSName = NULL;
	NSString				*funcName = nil;
	JSContext				*context = NULL;
	
	context = [[OOJavaScriptEngine sharedEngine] acquireContext];
	funcJSName = JS_GetFunctionId(JS_ValueToFunction(context, _function));
	[[OOJavaScriptEngine sharedEngine] releaseContext:context];
	
	if (funcJSName == NULL)
	{
		funcName = @"anonymous";
	}
	else
	{
		funcName = [NSString stringWithFormat:@"\"%@\"", [NSString stringWithJavaScriptString:funcJSName]];
	}
	
	return [NSString stringWithFormat:@"%@, function: %@", [super descriptionComponents], funcName];
}


- (NSString *)jsClassName
{
	return @"Timer";
}


- (void) timerFired
{
	jsval					rval = JSVAL_VOID;
	NSString				*description = nil;
	
	OOJavaScriptEngine *engine = [OOJavaScriptEngine sharedEngine];
	JSContext *context = [engine acquireContext];
	JS_BeginRequest(context);
	
	// stop and remove the timer if _jsThis (the first parameter in the constructor) dies.
	id object = JSObjectToObject(context, _jsThis);
	if (object != nil)
	{
		description = [object javaScriptDescription];
		if (description == nil)  description = [object description];
	}
	
	if (description == nil)
	{
		[self unscheduleTimer];
		[self autorelease];
		return;
	}
	
	[OOJSScript pushScript:_owningScript];
	[engine callJSFunction:_function
				 forObject:_jsThis
					  argc:0
					  argv:NULL
					result:&rval];
	[OOJSScript popScript:_owningScript];
	
	JS_EndRequest(context);
	[engine releaseContext:context];
}


- (jsval) javaScriptValueInContext:(JSContext *)context
{
	return OBJECT_TO_JSVAL(_jsSelf);
}

@end


static JSBool TimerGetProperty(OOJS_PROP_ARGS);
static JSBool TimerSetProperty(OOJS_PROP_ARGS);
static void TimerFinalize(JSContext *context, JSObject *this);
static JSBool TimerConstruct(OOJS_NATIVE_ARGS);

// Methods
static JSBool TimerStart(OOJS_NATIVE_ARGS);
static JSBool TimerStop(OOJS_NATIVE_ARGS);


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
	{ "nextTime",				kTimer_nextTime,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "interval",				kTimer_interval,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "isRunning",				kTimer_isRunning,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ 0 }
};


static JSFunctionSpec sTimerMethods[] =
{
	// JS name					Function					min args
	{ "toString",				JSObjectWrapperToString,	0 },
	{ "start",					TimerStart,					0 },
	{ "stop",					TimerStop,					0 },
	{ 0 }
};


DEFINE_JS_OBJECT_GETTER(JSTimerGetTimer, &sTimerClass, sTimerPrototype, OOJSTimer);


void InitOOJSTimer(JSContext *context, JSObject *global)
{
	sTimerPrototype = JS_InitClass(context, global, NULL, &sTimerClass, TimerConstruct, 0, sTimerProperties, sTimerMethods, NULL, NULL);
	JSRegisterObjectConverter(&sTimerClass, JSBasicPrivateObjectConverter);
}


static JSBool TimerGetProperty(OOJS_PROP_ARGS)
{
	if (!OOJS_PROPID_IS_INT)  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	OOJSTimer				*timer = nil;
	BOOL					OK = NO;
	
	if (EXPECT_NOT(!JSTimerGetTimer(context, this, &timer))) return NO;
	
	switch (OOJS_PROPID_INT)
	{
		case kTimer_nextTime:
			OK = JS_NewDoubleValue(context, [timer nextTime], value);
			break;
			
		case kTimer_interval:
			OK = JS_NewDoubleValue(context, [timer interval], value);
			break;
			
		case kTimer_isRunning:
			*value = BOOLToJSVal([timer isScheduled]);
			OK = YES;
			break;
			
		default:
			OOReportJSBadPropertySelector(context, @"Timer", OOJS_PROPID_INT);
	}
	
	return OK;
	
	OOJS_NATIVE_EXIT
}


static JSBool TimerSetProperty(OOJS_PROP_ARGS)
{
	if (!OOJS_PROPID_IS_INT)  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	BOOL					OK = YES;
	OOJSTimer				*timer = nil;
	double					fValue;
	
	if (EXPECT_NOT(!JSTimerGetTimer(context, this, &timer))) return NO;
	
	switch (OOJS_PROPID_INT)
	{
		case kTimer_nextTime:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				OK = YES;
				if (![timer setNextTime:fValue])
				{
					OOReportJSWarning(context, @"Ignoring attempt to change next fire time for running timer %@.", timer);
				}
			}
			break;
			
		case kTimer_interval:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				OK = YES;
				[timer setInterval:fValue];
			}
			break;
			
		default:
			OOReportJSBadPropertySelector(context, @"Timer", OOJS_PROPID_INT);
	}
	
	return OK;
	
	OOJS_NATIVE_EXIT
}


static void TimerFinalize(JSContext *context, JSObject *this)
{
	OOJS_PROFILE_ENTER
	
	OOJSTimer *timer = (OOJSTimer *)JS_GetPrivate(context, this);
	
	if (timer != nil)
	{
		if ([timer isScheduled])
		{
			OOReportJSWarning(context, @"Timer %@ is being garbage-collected while still running. You must keep a reference to all running timers, or they will stop unpredictably!", timer);
		}
		[timer release];
		JS_SetPrivate(context, this, NULL);
	}
	
	OOJS_PROFILE_EXIT_VOID
}


// new Timer(this : Object, function : Function, delay : Number [, interval : Number]) : Timer
static JSBool TimerConstruct(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	jsval					function = JSVAL_VOID;
	double					delay;
	double					interval = -1.0;
	OOJSTimer				*timer = nil;
	JSObject				*callbackThis = NULL;
	
	if (EXPECT_NOT(!OOJS_IS_CONSTRUCTING))
	{
		OOReportJSError(context, @"Timer() cannot be called as a function, it must be used as a constructor (as in new Timer(...)).");
		return NO;
	}
	
	if (argc < 3)
	{
		OOReportJSBadArguments(context, nil, @"Timer", argc, OOJS_ARGV, @"Invalid arguments in constructor", @"(object, function, number [, number])");
		return NO;
	}
	
	if (!JSVAL_IS_NULL(OOJS_ARG(0)) && !JSVAL_IS_VOID(OOJS_ARG(0)))
	{
		if (!JS_ValueToObject(context, OOJS_ARG(0), &callbackThis))
		{
			OOReportJSBadArguments(context, nil, @"Timer", 1, OOJS_ARGV, @"Invalid argument in constructor", @"object");
			return NO;
		}
	}
	
	function = OOJS_ARG(1);
	if (JS_ValueToFunction(context, function) == NULL)
	{
		OOReportJSBadArguments(context, nil, @"Timer", 1, OOJS_ARGV + 1, @"Invalid argument in constructor", @"function");
		return NO;
	}
	
	if (!JS_ValueToNumber(context, OOJS_ARG(2), &delay) || isnan(delay))
	{
		OOReportJSBadArguments(context, nil, @"Timer", 1, OOJS_ARGV + 2, @"Invalid argument in constructor", @"number");
		return NO;
	}
	
	// Fourth argument is optional.
	if (3 < argc && !JS_ValueToNumber(context, OOJS_ARG(3), &interval))  interval = -1;
	
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
static JSBool TimerStart(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	OOJSTimer					*thisTimer = nil;
	
	if (EXPECT_NOT(!JSTimerGetTimer(context, OOJS_THIS, &thisTimer)))  return NO;
	
	OOJS_RETURN_BOOL([thisTimer scheduleTimer]);
	
	OOJS_NATIVE_EXIT
}


// stop()
static JSBool TimerStop(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	OOJSTimer					*thisTimer = nil;
	
	if (EXPECT_NOT(!JSTimerGetTimer(context, OOJS_THIS, &thisTimer)))  return NO;
	
	[thisTimer unscheduleTimer];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
