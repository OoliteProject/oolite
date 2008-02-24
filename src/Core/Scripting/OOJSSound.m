/*

OOJSSound.m

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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

#import "OOJSSound.h"
#import "OOJavaScriptEngine.h"
#import "OOSound.h"
#import "OOMusicController.h"
#import "ResourceManager.h"


static JSObject *sSoundPrototype;


static JSBool SoundGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);

// Static methods
static JSBool SoundStaticLoad(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SoundStaticPlayMusic(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SoundStaticStopMusic(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


static JSExtendedClass sSoundClass =
{
	{
		"Sound",
		JSCLASS_HAS_PRIVATE | JSCLASS_IS_EXTENDED,
		
		JS_PropertyStub,		// addProperty
		JS_PropertyStub,		// delProperty
		SoundGetProperty,		// getProperty
		JS_PropertyStub,		// setProperty
		JS_EnumerateStub,		// enumerate
		JS_ResolveStub,			// resolve
		JS_ConvertStub,			// convert
		JSObjectWrapperFinalize, // finalize
		JSCLASS_NO_OPTIONAL_MEMBERS
	},
	JSObjectWrapperEquality,	// equality. Relies on the fact that the resource manager will always return the same object for a given sound name.
	NULL,						// outerObject
	NULL,						// innerObject
	JSCLASS_NO_RESERVED_MEMBERS
};


enum
{
	// Property IDs
	kSound_name
};


static JSPropertySpec sSoundProperties[] =
{
	// JS name					ID							flags
	{ "name",					kSound_name,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ 0 }
};


static JSFunctionSpec sSoundMethods[] =
{
	// JS name					Function					min args
	{ "toString",				JSObjectWrapperToString,	0, },
	{ 0 }
};


static JSFunctionSpec sSoundStaticMethods[] =
{
	// JS name					Function					min args
	{ "load",					SoundStaticLoad,			1, },
	{ "playMusic",				SoundStaticPlayMusic,		1, },
	{ "stopMusic",				SoundStaticStopMusic,		0, },
	{ 0 }
};


// *** Public ***

void InitOOJSSound(JSContext *context, JSObject *global)
{
    sSoundPrototype = JS_InitClass(context, global, NULL, &sSoundClass.base, NULL, 0, sSoundProperties, sSoundMethods, NULL, sSoundStaticMethods);
	JSRegisterObjectConverter(&sSoundClass.base, JSBasicPrivateObjectConverter);
}


BOOL JSSoundGetSound(JSContext *context, JSObject *soundObj, OOSound **outSound)
{
	if (outSound == NULL)  return NO;
	*outSound = JSObjectToObjectOfClass(context, soundObj, [OOSound class]);
	return *outSound != nil;
}


OOSound *SoundFromJSValue(JSContext *context, jsval value)
{
	if (JSVAL_IS_STRING(value))
	{
		return [ResourceManager ooSoundNamed:JSValToNSString(context, value) inFolder:@"Sounds"];
	}
	else
	{
		return JSValueToObjectOfClass(context, value, [OOSound class]);
	}
}


// *** Implementation stuff ***

static JSBool SoundGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	OOSound						*sound = nil;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSSoundGetSound(context, this, &sound)) return NO;
	
	switch (JSVAL_TO_INT(name))
	{
		case kSound_name:
			*outValue = [[sound name] javaScriptValueInContext:context];
			break;
		
		default:
			OOReportJavaScriptBadPropertySelector(context, @"Sound", JSVAL_TO_INT(name));
			return NO;
	}
	
	return YES;
}


// *** Methods ***

// load(name : String) : Sound
static JSBool SoundStaticLoad(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString					*name = nil;
	OOSound						*sound = nil;
	
	name = JSValToNSString(context, argv[0]);
	sound = [ResourceManager ooSoundNamed:name inFolder:@"Sounds"];
	
	*outResult = [sound javaScriptValueInContext:context];
	if (*outResult == JSVAL_VOID)  *outResult = JSVAL_NULL;
	return YES;
}


static JSBool SoundStaticPlayMusic(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString					*name = nil;
	
	name = JSValToNSString(context, argv[0]);
	[[OOMusicController sharedController] playMusicNamed:name loop:NO];
	
	return YES;
}


static JSBool SoundStaticStopMusic(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString					*name = nil;
	
	if (argc > 0)
	{
		name = JSValToNSString(context, argv[0]);
		[[OOMusicController sharedController] stopMusicNamed:name];
	}
	else
	{
		[[OOMusicController sharedController] stop];
	}
	
	return YES;
}


@implementation OOSound (OOJavaScriptExtentions)

- (jsval) javaScriptValueInContext:(JSContext *)context
{
	JSObject					*jsSelf = NULL;
	jsval						result = JSVAL_NULL;
	
	jsSelf = JS_NewObject(context, &sSoundClass.base, sSoundPrototype, NULL);
	if (jsSelf != NULL)
	{
		if (!JS_SetPrivate(context, jsSelf, [self retain]))  jsSelf = NULL;
	}
	if (jsSelf != NULL)  result = OBJECT_TO_JSVAL(jsSelf);
	
	return result;
}


- (NSString *) javaScriptDescription
{
	return [NSString stringWithFormat:@"[Sound \"%@\"]", [self name]];
}


- (NSString *) jsClassName
{
	return @"Sound";
}

@end
