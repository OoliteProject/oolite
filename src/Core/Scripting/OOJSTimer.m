/*

OOJSTimer.m


Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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
			function:(JSFunction *)function
				this:(JSObject *)jsThis;

@end


@implementation OOJSTimer

- (id) initWithDelay:(OOTimeAbsolute)delay
			interval:(OOTimeDelta)interval
			function:(JSFunction *)function
				this:(JSObject *)jsThis
{
	JSContext				*context = NULL;
	
	if (function == NULL)
	{
		[self release];
		return nil;
	}
	
	self = [super initWithNextTime:[UNIVERSE getTime] + delay interval:interval];
	if (self != nil)
	{
		context = [[OOJavaScriptEngine sharedEngine] context];
		
		_jsThis = jsThis;
		JS_AddNamedRoot(context, &_jsThis, "OOJSTimer this");
		
		_function = function;
		_functionObject = JS_GetFunctionObject(_function);
		
		JS_AddNamedRoot(context, &_functionObject, "OOJSTimer function");
		
		_jsSelf = JS_NewObject(context, &sTimerClass, sTimerPrototype, NULL);
		JS_AddNamedRoot(context, &_jsSelf, "OOJSTimer jsSelf");
		if (_jsSelf != NULL)
		{
			if (!JS_SetPrivate(context, _jsSelf, [self retain]))  _jsSelf = NULL;
		}
		if (_jsSelf == NULL)
		{
			[self release];
			self = nil;
		}
		
		_owningScript = [OOJSScript currentlyRunningScript];
	}
	
	return self;
}


- (void) dealloc
{
	JSContext				*context = NULL;
	
	// Allow GCing of function and this.
	context = [[OOJavaScriptEngine sharedEngine] context];
	JS_RemoveRoot(context, &_jsThis);
	JS_RemoveRoot(context, _functionObject);
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	JSString				*funcJSName = NULL;
	NSString				*funcName = nil;
	NSString				*thisDesc = nil;
	
	funcJSName = JS_GetFunctionId(_function);
	if (funcJSName == NULL)  funcName = @"anonymous";
	else
	{
		funcName = [NSString stringWithFormat:@"\"%@\"", [NSString stringWithJavaScriptString:funcJSName]];
	}  
	
	if (_jsThis == NULL)  thisDesc = @"null";
	else
	{
		thisDesc = [NSString stringWithJavaScriptValue:OBJECT_TO_JSVAL(_jsThis)
											 inContext:[[OOJavaScriptEngine sharedEngine] context]];
	}
	
	return [NSString stringWithFormat:@"%@, %spersistent, function: %@", [super descriptionComponents], [self isPersistent] ? "" : "not ", funcName];
}


- (NSString *)jsClassName
{
	return @"Timer";
}


- (void) timerFired
{
	JSContext				*context = NULL;
	jsval					rval = JSVAL_VOID;
	
	[OOJSScript pushScript:_owningScript];
	context = [[OOJavaScriptEngine sharedEngine] context];
	if (!JS_CallFunction(context, _jsThis, _function, 0, NULL, &rval))
	{
		[self unscheduleTimer];
	}
	[OOJSScript popScript:_owningScript];
}


- (BOOL) isPersistent
{
	return _persistent;
}


- (void) setPersistent:(BOOL)value
{
	_persistent = (value != NO);
}


- (jsval)javaScriptValueInContext:(JSContext *)context
{
	return OBJECT_TO_JSVAL(_jsSelf);
}

@end


static JSBool TimerGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool TimerSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);
static void TimerFinalize(JSContext *context, JSObject *this);
static JSBool TimerConstruct(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);

// Methods
static JSBool TimerStart(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool TimerStop(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


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
	kTimer_isPersistent,		// is persistent, boolean, read/write
	kTimer_isRunning			// is scheduled, boolean, read-only
};


static JSPropertySpec sTimerProperties[] =
{
	// JS name					ID							flags
	{ "nextTime",				kTimer_nextTime,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "interval",				kTimer_interval,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "isPersistent",			kTimer_isPersistent,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
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


void InitOOJSTimer(JSContext *context, JSObject *global)
{
    sTimerPrototype = JS_InitClass(context, global, NULL, &sTimerClass, TimerConstruct, 0, sTimerProperties, sTimerMethods, NULL, NULL);
	JSRegisterObjectConverter(&sTimerClass, JSBasicPrivateObjectConverter);
}


static BOOL JSTimerGetTimer(JSContext *context, JSObject *entityObj, OOJSTimer **outTimer)
{
	id						value = nil;
	
	value = JSObjectToObject(context, entityObj);
	if ([value isKindOfClass:[OOJSTimer class]] && outTimer != NULL)
	{
		*outTimer = value;
		return YES;
	}
	return NO;
}


static JSBool TimerGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	OOJSTimer				*timer = nil;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSTimerGetTimer(context, this, &timer)) return NO;
	
	switch (JSVAL_TO_INT(name))
	{
		case kTimer_nextTime:
			JS_NewDoubleValue(context, [timer nextTime], outValue);
			break;
			
		case kTimer_interval:
			JS_NewDoubleValue(context, [timer interval], outValue);
			break;
			
		case kTimer_isPersistent:
			*outValue = BOOLEAN_TO_JSVAL([timer isPersistent]);
			break;
			
		case kTimer_isRunning:
			*outValue = BOOLEAN_TO_JSVAL([timer isScheduled]);
			break;
			
		default:
			OOReportJavaScriptBadPropertySelector(context, @"Timer", JSVAL_TO_INT(name));
			return NO;
	}
	
	return YES;
}


static JSBool TimerSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	OOJSTimer				*timer = nil;
	double					fValue;
	JSBool					bValue;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSTimerGetTimer(context, this, &timer)) return NO;
	
	switch (JSVAL_TO_INT(name))
	{
		case kTimer_nextTime:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				if (![timer setNextTime:fValue])
				{
					OOReportJavaScriptWarning(context, @"Ignoring attempt to change next fire time for running timer %@.", timer);
				}
			}
			break;
			
		case kTimer_interval:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[timer setInterval:fValue];
			}
			break;
			
		case kTimer_isPersistent:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[timer setPersistent:bValue];
			}
			break;
			
		default:
			OOReportJavaScriptBadPropertySelector(context, @"Timer", JSVAL_TO_INT(name));
			return NO;
	}
	
	return YES;
}


static void TimerFinalize(JSContext *context, JSObject *this)
{
	OOJSTimer				*timer = nil;
	
	if (JSTimerGetTimer(context, this, &timer))
	{
		if ([timer isScheduled])
		{
			OOReportJavaScriptWarning(context, @"Timer %@ is being garbage-collected while still running. You must keep a reference to all running timers, or they will stop unpredictably!", timer);
		}
		[timer release];
		JS_SetPrivate(context, this, NULL);
	}
}


// new Timer(this : Object, function : Function, delay : Number [, interval : Number]) : Timer
static JSBool TimerConstruct(JSContext *context, JSObject *inThis, uintN argc, jsval *argv, jsval *outResult)
{
	JSObject				*this = NULL;
	JSFunction				*function = NULL;
	double					delay;
	double					interval = -1.0;
	OOJSTimer				*timer = nil;
	
	if (!JSVAL_IS_NULL(argv[0]) && !JSVAL_IS_VOID(argv[0]))
	{
		if (!JS_ValueToObject(context, argv[0], &this))
		{
			// Should be TypeException, but SpiderMonkey doesn't seem to have a sane way to throw exceptions at the moment.
			OOReportJavaScriptError(context, @"Could not construct Timer because %@ argument ('%@') is not %@.", "first", "this", "an object");
			return YES;
		}
	}
	
	function = JS_ValueToFunction(context, argv[1]);
	if (function == NULL)
	{
		// Should be TypeException, but SpiderMonkey doesn't seem to have a sane way to throw exceptions at the moment.
		OOReportJavaScriptError(context, @"Could not construct Timer because %@ argument ('%@') is not %@.", "second", "function", "a function");
		return YES;
	}
	
	if (!JS_ValueToNumber(context, argv[2], &delay))
	{
		// Should be TypeException, but SpiderMonkey doesn't seem to have a sane way to throw exceptions at the moment.
		OOReportJavaScriptError(context, @"Could not construct Timer because %@ argument ('%@') is not %@.", "third", "delay", "a number");
		return YES;
	}
	
	// Fourth argument is optional.
	if (3 < argc && !JS_ValueToNumber(context, argv[3], &interval))  interval = -1;
	
	// Ensure interval is not too small.
	if (0.0 < interval && interval < kMinInterval)  interval = kMinInterval;
	
	timer = [[OOJSTimer alloc] initWithDelay:delay
									interval:interval
									function:function
										this:this];
	*outResult = [timer javaScriptValueInContext:context];
	[timer scheduleTimer];
	[timer release];	// The JS object retains the ObjC object.
	
	return YES;
}


// Methods
static JSBool TimerStart(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJSTimer					*thisTimer = nil;
	
	if (JSTimerGetTimer(context, this, &thisTimer))  *outResult = BOOLEAN_TO_JSVAL([thisTimer scheduleTimer]);
	else  *outResult = JSVAL_TRUE;
	
	return YES;
}


static JSBool TimerStop(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJSTimer					*thisTimer = nil;
	
	if (JSTimerGetTimer(context, this, &thisTimer))  [thisTimer unscheduleTimer];
	
	return YES;
}
