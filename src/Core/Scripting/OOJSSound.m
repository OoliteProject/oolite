/*

OOJSSound.m

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

#import "OOJSSound.h"
#import "OOJavaScriptEngine.h"
#import "OOSound.h"
#import "OOMusicController.h"
#import "ResourceManager.h"
#import "Universe.h"


static JSObject *sSoundPrototype;


static OOSound *GetNamedSound(NSString *name);


static JSBool SoundGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);

// Static methods
static JSBool SoundStaticLoad(JSContext *context, uintN argc, jsval *vp);
static JSBool SoundStaticPlayMusic(JSContext *context, uintN argc, jsval *vp);
static JSBool SoundStaticStopMusic(JSContext *context, uintN argc, jsval *vp);


static JSClass sSoundClass =
{
	"Sound",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,		// addProperty
	JS_PropertyStub,		// delProperty
	SoundGetProperty,		// getProperty
	JS_StrictPropertyStub,	// setProperty
	JS_EnumerateStub,		// enumerate
	JS_ResolveStub,			// resolve
	JS_ConvertStub,			// convert
	OOJSObjectWrapperFinalize, // finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
};


enum
{
	// Property IDs
	kSound_name
};


static JSPropertySpec sSoundProperties[] =
{
	// JS name					ID							flags
	{ "name",					kSound_name,				OOJS_PROP_READONLY_CB },
	{ 0 }
};


static JSFunctionSpec sSoundMethods[] =
{
	// JS name					Function					min args
	{ "toString",				OOJSObjectWrapperToString,	0, },
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


DEFINE_JS_OBJECT_GETTER(JSSoundGetSound, &sSoundClass, sSoundPrototype, OOSound)


// *** Public ***

void InitOOJSSound(JSContext *context, JSObject *global)
{
	sSoundPrototype = JS_InitClass(context, global, NULL, &sSoundClass, OOJSUnconstructableConstruct, 0, sSoundProperties, sSoundMethods, NULL, sSoundStaticMethods);
	OOJSRegisterObjectConverter(&sSoundClass, OOJSBasicPrivateObjectConverter);
}


OOSound *SoundFromJSValue(JSContext *context, jsval value)
{
	OOJS_PROFILE_ENTER
	
	OOJSPauseTimeLimiter();
	if (JSVAL_IS_STRING(value))
	{
		return GetNamedSound(OOStringFromJSValue(context, value));
	}
	else
	{
		return OOJSNativeObjectOfClassFromJSValue(context, value, [OOSound class]);
	}
	OOJSResumeTimeLimiter();
	
	OOJS_PROFILE_EXIT
}


// *** Implementation stuff ***

static JSBool SoundGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	OOSound						*sound = nil;
	
	if (EXPECT_NOT(!JSSoundGetSound(context, this, &sound)))  return NO;
	
	switch (JSID_TO_INT(propID))
	{
		case kSound_name:
			*value = OOJSValueFromNativeObject(context, [sound name]);
			return YES;
		
		default:
			OOJSReportBadPropertySelector(context, this, propID, sSoundProperties);
			return NO;
	}
	
	OOJS_NATIVE_EXIT
}


static OOSound *GetNamedSound(NSString *name)
{
	OOSound						*sound = nil;
	
	if ([name hasPrefix:@"["] && [name hasSuffix:@"]"])
	{
		sound = [OOSound soundWithCustomSoundKey:name];
	}
	else
	{
		sound = [ResourceManager ooSoundNamed:name inFolder:@"Sounds"];
	}
	
	return sound;
}


// *** Static methods ***

// load(name : String) : Sound
static JSBool SoundStaticLoad(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString					*name = nil;
	OOSound						*sound = nil;
	
	if (argc > 0)  name = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (name == nil)
	{
		OOJSReportBadArguments(context, @"Sound", @"load", MIN(argc, 1U), OOJS_ARGV, nil, @"string");
		return NO;
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	sound = GetNamedSound(name);
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_OBJECT(sound);
	
	OOJS_NATIVE_EXIT
}


// playMusic(name : String [, loop : Boolean])
static JSBool SoundStaticPlayMusic(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString					*name = nil;
	JSBool						loop = NO;
	
	if (argc > 0)  name = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (name == nil)
	{
		OOJSReportBadArguments(context, @"Sound", @"playMusic", MIN(argc, 1U), OOJS_ARGV, nil, @"string");
		return NO;
	}
	if (argc > 1)
	{
		if (!JS_ValueToBoolean(context, OOJS_ARGV[1], &loop))
		{
			OOJSReportBadArguments(context, @"Sound", @"playMusic", 1, OOJS_ARGV + 1, nil, @"boolean");
			return NO;
		}
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	[[OOMusicController sharedController] playMusicNamed:name loop:loop];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// Sound.stopMusic([name : String])
static JSBool SoundStaticStopMusic(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString					*name = nil;
	
	if (argc > 0)
	{
		name = OOStringFromJSValue(context, OOJS_ARGV[0]);
		if (EXPECT_NOT(name == nil))
		{
			OOJSReportBadArguments(context, @"Sound", @"stopMusic", argc, OOJS_ARGV, nil, @"string or no argument");
			return NO;
		}
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	OOMusicController *controller = [OOMusicController sharedController];
	if (name == nil || [name isEqualToString:[controller playingMusic]])
	{
		[[OOMusicController sharedController] stop];
	}
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


@implementation OOSound (OOJavaScriptExtentions)

- (jsval) oo_jsValueInContext:(JSContext *)context
{
	JSObject					*jsSelf = NULL;
	jsval						result = JSVAL_NULL;
	
	jsSelf = JS_NewObject(context, &sSoundClass, sSoundPrototype, NULL);
	if (jsSelf != NULL)
	{
		if (!JS_SetPrivate(context, jsSelf, [self retain]))  jsSelf = NULL;
	}
	if (jsSelf != NULL)  result = OBJECT_TO_JSVAL(jsSelf);
	
	return result;
}


- (NSString *) oo_jsDescription
{
	return [NSString stringWithFormat:@"[Sound \"%@\"]", [self name]];
}


- (NSString *) oo_jsClassName
{
	return @"Sound";
}

@end
