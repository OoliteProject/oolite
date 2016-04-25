/*

OOJSPopulatorDefinition.m


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

#import "OOJSPopulatorDefinition.h"
#import "OOJavaScriptEngine.h"
#import "OOMaths.h"
#import "OOJSVector.h"

@implementation OOJSPopulatorDefinition

- (id) init {
	self = [super init];
	_callback = JSVAL_VOID;
	_callbackThis = NULL;

	_owningScript = [[OOJSScript currentlyRunningScript] weakRetain];

	[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(deleteJSPointers)
												 name:kOOJavaScriptEngineWillResetNotification
											   object:[OOJavaScriptEngine sharedEngine]];

	return self;
}

- (void) deleteJSPointers
{

	JSContext				*context = OOJSAcquireContext();
	_callback = JSVAL_VOID;
	_callbackThis = NULL;
	JS_RemoveValueRoot(context, &_callback);
	JS_RemoveObjectRoot(context, &_callbackThis);

	OOJSRelinquishContext(context);

	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:kOOJavaScriptEngineWillResetNotification
												  object:[OOJavaScriptEngine sharedEngine]];

}

- (void) dealloc 
{
	[_owningScript release];

	[self deleteJSPointers];

	[super dealloc];
}

- (jsval)callback
{
	return _callback;
}


- (void)setCallback:(jsval)callback
{
	JSContext				*context = OOJSAcquireContext();
	JS_RemoveValueRoot(context, &_callback);
	_callback = callback;
	OOJSAddGCValueRoot(context, &_callback, "OOJSPopulatorDefinition callback function");
	OOJSRelinquishContext(context);
}


- (JSObject *)callbackThis
{
	return _callbackThis;
}


- (void)setCallbackThis:(JSObject *)callbackThis
{
	JSContext				*context = OOJSAcquireContext();
	JS_RemoveObjectRoot(context, &_callbackThis);
	_callbackThis = callbackThis;
	OOJSAddGCObjectRoot(context, &_callbackThis, "OOJSPopulatorDefinition callback this");
	OOJSRelinquishContext(context);
}


- (void)runCallback:(HPVector)location
{
	OOJavaScriptEngine *engine = [OOJavaScriptEngine sharedEngine];
	JSContext			*context = OOJSAcquireContext();		
	jsval					loc, rval = JSVAL_VOID;

	VectorToJSValue(context, HPVectorToVector(location), &loc);

	OOJSScript *owner = [_owningScript retain]; // local copy needed
	[OOJSScript pushScript:owner];

	[engine callJSFunction:_callback
				 forObject:_callbackThis
					  argc:1
					  argv:&loc
					result:&rval];
	
	[OOJSScript popScript:owner];
	[owner release];

	OOJSRelinquishContext(context);
}

@end
