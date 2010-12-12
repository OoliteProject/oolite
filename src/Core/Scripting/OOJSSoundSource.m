/*

OOJSSoundSource.m

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

#import "OOJSSound.h"
#import "OOJavaScriptEngine.h"
#import "OOSound.h"
#import "ResourceManager.h"


static JSObject *sSoundSourcePrototype;


DEFINE_JS_OBJECT_GETTER(JSSoundSourceGetSoundSource, OOSoundSource)


static JSBool SoundSourceGetProperty(OOJS_PROP_ARGS);
static JSBool SoundSourceSetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool SoundSourceConstruct(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);

// Methods
static JSBool SoundSourcePlay(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SoundSourceStop(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SoundSourcePlayOrRepeat(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool SoundSourcePlaySound(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


static JSClass sSoundSourceClass =
{
	"SoundSource",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,		// addProperty
	JS_PropertyStub,		// delProperty
	SoundSourceGetProperty,	// getProperty
	SoundSourceSetProperty,	// setProperty
	JS_EnumerateStub,		// enumerate
	JS_ResolveStub,			// resolve
	JS_ConvertStub,			// convert
	JSObjectWrapperFinalize, // finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
};


enum
{
	// Property IDs
	kSoundSource_sound,
	kSoundSource_isPlaying,
	kSoundSource_loop,
	kSoundSource_repeatCount
};


static JSPropertySpec sSoundSourceProperties[] =
{
	// JS name					ID							flags
	{ "sound",					kSoundSource_sound,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "isPlaying",				kSoundSource_isPlaying,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "loop",					kSoundSource_loop,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "repeatCount",			kSoundSource_repeatCount,	JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ 0 }
};


static JSFunctionSpec sSoundSourceMethods[] =
{
	// JS name					Function					min args
	{ "toString",				JSObjectWrapperToString,	0, },
	{ "play",					SoundSourcePlay,			0, },
	{ "stop",					SoundSourceStop,			0, },
	{ "playOrRepeat",			SoundSourcePlayOrRepeat,	0, },
	{ "playSound",				SoundSourcePlaySound,		1, },
	{ 0 }
};


// *** Public ***

void InitOOJSSoundSource(JSContext *context, JSObject *global)
{
	sSoundSourcePrototype = JS_InitClass(context, global, NULL, &sSoundSourceClass, SoundSourceConstruct, 0, sSoundSourceProperties, sSoundSourceMethods, NULL, NULL);
	JSRegisterObjectConverter(&sSoundSourceClass, JSBasicPrivateObjectConverter);
}


static JSBool SoundSourceConstruct(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOSoundSource				*soundSource = nil;
	
	soundSource = [[[OOSoundSource alloc] init] autorelease];
	if (soundSource == nil)  return NO;
	*outResult = [soundSource javaScriptValueInContext:context];
	return YES;
}


// *** Implementation stuff ***

static JSBool SoundSourceGetProperty(OOJS_PROP_ARGS)
{
	if (!OOJS_PROPID_IS_INT)  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	OOSoundSource				*soundSource = nil;
	
	if (!JSSoundSourceGetSoundSource(context, this, &soundSource)) return NO;
	
	switch (OOJS_PROPID_INT)
	{
		case kSoundSource_sound:
			*value = [[soundSource sound] javaScriptValueInContext:context];
			break;
			
		case kSoundSource_isPlaying:
			*value = BOOLToJSVal([soundSource isPlaying]);
			break;
			
		case kSoundSource_loop:
			*value = BOOLToJSVal([soundSource loop]);
			break;
			
		case kSoundSource_repeatCount:
			*value = INT_TO_JSVAL([soundSource repeatCount]);
			break;
		
		default:
			OOReportJSBadPropertySelector(context, @"SoundSource", OOJS_PROPID_INT);
			return NO;
	}
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool SoundSourceSetProperty(OOJS_PROP_ARGS)
{
	if (!OOJS_PROPID_IS_INT)  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	BOOL						OK = NO;
	OOSoundSource				*soundSource = nil;
	int32						iValue;
	JSBool						bValue;
	
	if (!JSSoundSourceGetSoundSource(context, this, &soundSource)) return NO;
	
	switch (OOJS_PROPID_INT)
	{
		case kSoundSource_sound:
			OOJSPauseTimeLimiter();
			[soundSource setSound:SoundFromJSValue(context, *value)];
			OOJSResumeTimeLimiter();
			OK = YES;
			break;
			
		case kSoundSource_loop:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[soundSource setLoop:bValue];
				OK = YES;
			}
			break;
			
		case kSoundSource_repeatCount:
			if (JS_ValueToInt32(context, *value, &iValue) && 0 < iValue)
			{
				if (iValue > 100)  iValue = 100;
				if (100 < 1)  iValue = 1;
				[soundSource setRepeatCount:iValue];
				OK = YES;
			}
			break;
		
		default:
			OOReportJSBadPropertySelector(context, @"SoundSource", OOJS_PROPID_INT);
	}
	
	return OK;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

// play([count : Number])
static JSBool SoundSourcePlay(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	OOSoundSource			*thisv = nil;
	int32					count = 0;
	
	if (EXPECT_NOT(!JSSoundSourceGetSoundSource(context, this, &thisv))) return NO;
	if (argc > 0 && !JS_ValueToInt32(context, argv[0], &count))
	{
		OOReportJSBadArguments(context, @"SoundSource", @"play", argc, argv, nil, @"integer count or no argument");
		return NO;
	}
	
	if (count > 0)
	{
		if (count > 100)  count = 100;
		[thisv setRepeatCount:count];
	}
	
	OOJSPauseTimeLimiter();
	[thisv play];
	OOJSResumeTimeLimiter();
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


// stop()
static JSBool SoundSourceStop(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	OOSoundSource			*thisv = nil;
	
	if (EXPECT_NOT(!JSSoundSourceGetSoundSource(context, this, &thisv))) return NO;
	
	OOJSPauseTimeLimiter();
	[thisv stop];
	OOJSResumeTimeLimiter();
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


// playOrRepeat()
static JSBool SoundSourcePlayOrRepeat(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	OOSoundSource			*thisv = nil;
	
	if (EXPECT_NOT(!JSSoundSourceGetSoundSource(context, this, &thisv))) return NO;
	
	OOJSPauseTimeLimiter();
	[thisv playOrRepeat];
	OOJSResumeTimeLimiter();
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


// playSound(sound : SoundExpression [, count : Number])
static JSBool SoundSourcePlaySound(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	OOSoundSource			*thisv;
	OOSound					*sound = nil;
	int32					count = 0;
	
	OOJSPauseTimeLimiter();
	if (EXPECT_NOT(!JSSoundSourceGetSoundSource(context, this, &thisv))) return NO;
	sound = SoundFromJSValue(context, argv[0]);
	if (sound == nil)
	{
		OOReportJSBadArguments(context, @"SoundSource", @"playSound", argc, argv, nil, @"sound or sound name");
		OOJSResumeTimeLimiter();
		return NO;
	}
	
	if (argc > 1 && !JS_ValueToInt32(context, argv[1], &count))
	{
		OOReportJSBadArguments(context, @"SoundSource", @"playSound", argc, argv, nil, @"sound or sound name and optional integer count");
		OOJSResumeTimeLimiter();
		return NO;
	}
	
	[thisv setSound:sound];
	if (count > 0)
	{
		if (count > 100)  count = 100;
		[thisv setRepeatCount:count];
	}
	[thisv play];
	OOJSResumeTimeLimiter();
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


@implementation OOSoundSource (OOJavaScriptExtentions)

- (jsval) javaScriptValueInContext:(JSContext *)context
{
	JSObject					*jsSelf = NULL;
	jsval						result = JSVAL_NULL;
	
	jsSelf = JS_NewObject(context, &sSoundSourceClass, sSoundSourcePrototype, NULL);
	if (jsSelf != NULL)
	{
		if (!JS_SetPrivate(context, jsSelf, [self retain]))  jsSelf = NULL;
	}
	if (jsSelf != NULL)  result = OBJECT_TO_JSVAL(jsSelf);
	
	return result;
}


- (NSString *) jsClassName
{
	return @"SoundSource";
}

@end
