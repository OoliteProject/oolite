/*

OOJSSoundSource.m

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
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import "OOSound.h"
#import "ResourceManager.h"


static JSObject *sSoundSourcePrototype;


static JSBool SoundSourceGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool SoundSourceSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);
static JSBool SoundSourceConstruct(JSContext *context, uintN argc, jsval *vp);

// Methods
static JSBool SoundSourcePlay(JSContext *context, uintN argc, jsval *vp);
static JSBool SoundSourceStop(JSContext *context, uintN argc, jsval *vp);
static JSBool SoundSourcePlayOrRepeat(JSContext *context, uintN argc, jsval *vp);


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
	OOJSObjectWrapperFinalize, // finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
};


enum
{
	// Property IDs
	kSoundSource_sound,
	kSoundSource_isPlaying,
	kSoundSource_loop,
	kSoundSource_position,
	kSoundSource_positional,
	kSoundSource_repeatCount,
	kSoundSource_volume
};


static JSPropertySpec sSoundSourceProperties[] =
{
	// JS name					ID							flags
	{ "isPlaying",				kSoundSource_isPlaying,		OOJS_PROP_READONLY_CB },
	{ "loop",					kSoundSource_loop,			OOJS_PROP_READWRITE_CB },
	{ "position",				kSoundSource_position,		OOJS_PROP_READWRITE_CB },
	{ "positional",				kSoundSource_positional,	OOJS_PROP_READWRITE_CB },
	{ "repeatCount",			kSoundSource_repeatCount,	OOJS_PROP_READWRITE_CB },
	{ "sound",					kSoundSource_sound,			OOJS_PROP_READWRITE_CB },
	{ "volume",					kSoundSource_volume,		OOJS_PROP_READWRITE_CB },
	{ 0 }
};


static JSFunctionSpec sSoundSourceMethods[] =
{
	// JS name					Function					min args
	{ "toString",				OOJSObjectWrapperToString,	0, },
	{ "play",					SoundSourcePlay,			0, },
	{ "playOrRepeat",			SoundSourcePlayOrRepeat,	0, },
	// playSound is defined in oolite-global-prefix.js.
	{ "stop",					SoundSourceStop,			0, },
	{ 0 }
};


DEFINE_JS_OBJECT_GETTER(JSSoundSourceGetSoundSource, &sSoundSourceClass, sSoundSourcePrototype, OOSoundSource)


// *** Public ***

void InitOOJSSoundSource(JSContext *context, JSObject *global)
{
	sSoundSourcePrototype = JS_InitClass(context, global, NULL, &sSoundSourceClass, SoundSourceConstruct, 0, sSoundSourceProperties, sSoundSourceMethods, NULL, NULL);
	OOJSRegisterObjectConverter(&sSoundSourceClass, OOJSBasicPrivateObjectConverter);
}


static JSBool SoundSourceConstruct(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(!JS_IsConstructing(context, vp)))
	{
		OOJSReportError(context, @"SoundSource() cannot be called as a function, it must be used as a constructor (as in new SoundSource()).");
		return NO;
	}
	
	OOJS_RETURN_OBJECT([[[OOSoundSource alloc] init] autorelease]);
	
	OOJS_NATIVE_EXIT
}


// *** Implementation stuff ***

static JSBool SoundSourceGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	OOSoundSource				*soundSource = nil;
	
	if (!JSSoundSourceGetSoundSource(context, this, &soundSource))  return NO;
	
	switch (JSID_TO_INT(propID))
	{
		case kSoundSource_sound:
			*value = OOJSValueFromNativeObject(context, [soundSource sound]);
			return YES;
			
		case kSoundSource_isPlaying:
			*value = OOJSValueFromBOOL([soundSource isPlaying]);
			return YES;
			
		case kSoundSource_loop:
			*value = OOJSValueFromBOOL([soundSource loop]);
			return YES;
			
		case kSoundSource_repeatCount:
			*value = INT_TO_JSVAL([soundSource repeatCount]);
			return YES;

		case kSoundSource_position:
			return VectorToJSValue(context, [soundSource position], value);

		case kSoundSource_positional:
			*value = OOJSValueFromBOOL([soundSource positional]);
			return YES;

		case kSoundSource_volume:
			return JS_NewNumberValue(context, [soundSource gain], value);


		default:
			OOJSReportBadPropertySelector(context, this, propID, sSoundSourceProperties);
			return NO;
	}
	
	OOJS_NATIVE_EXIT
}


static JSBool SoundSourceSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	OOSoundSource				*soundSource = nil;
	int32						iValue;
	JSBool						bValue;
	Vector						vValue;
	double						fValue;

	if (!JSSoundSourceGetSoundSource(context, this, &soundSource)) return NO;
	
	switch (JSID_TO_INT(propID))
	{
		case kSoundSource_sound:
			[soundSource setSound:SoundFromJSValue(context, *value)];
			return YES;
			break;
			
		case kSoundSource_loop:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[soundSource setLoop:bValue];
				return YES;
			}
			break;
			
		case kSoundSource_repeatCount:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue > 100)  iValue = 100;
				if (100 < 1)  iValue = 1;
				[soundSource setRepeatCount:iValue];
				return YES;
			}
			break;
		

		case kSoundSource_position:
			if (JSValueToVector(context, *value, &vValue))
			{
				[soundSource setPosition:vValue];
				return YES;
			}
			break;

		case kSoundSource_positional:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[soundSource setPositional:bValue];
				return YES;
			}
			break;

		case kSoundSource_volume:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				fValue = OOClamp_0_max_d(fValue, 1);
				[soundSource setGain:fValue];
				return YES;
			}
			break;

		default:
			OOJSReportBadPropertySelector(context, this, propID, sSoundSourceProperties);
			return NO;
	}
	
	OOJSReportBadPropertyValue(context, this, propID, sSoundSourceProperties, *value);
	return NO;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

// play([count : Number])
static JSBool SoundSourcePlay(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	OOSoundSource			*thisv = nil;
	int32					count = 0;
	
	if (EXPECT_NOT(!JSSoundSourceGetSoundSource(context, OOJS_THIS, &thisv)))  return NO;
	if (argc > 0 && !JSVAL_IS_VOID(OOJS_ARGV[0]) && !JS_ValueToInt32(context, OOJS_ARGV[0], &count))
	{
		OOJSReportBadArguments(context, @"SoundSource", @"play", 1, OOJS_ARGV, nil, @"integer count or no argument");
		return NO;
	}
	
	if (count > 0)
	{
		if (count > 100)  count = 100;
		[thisv setRepeatCount:count];
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	[thisv play];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// stop()
static JSBool SoundSourceStop(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	OOSoundSource			*thisv = nil;
	
	if (EXPECT_NOT(!JSSoundSourceGetSoundSource(context, OOJS_THIS, &thisv)))  return NO;
	
	OOJS_BEGIN_FULL_NATIVE(context)
	[thisv stop];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// playOrRepeat()
static JSBool SoundSourcePlayOrRepeat(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	OOSoundSource			*thisv = nil;
	
	if (EXPECT_NOT(!JSSoundSourceGetSoundSource(context, OOJS_THIS, &thisv)))  return NO;
	
	OOJS_BEGIN_FULL_NATIVE(context)
	[thisv playOrRepeat];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


@implementation OOSoundSource (OOJavaScriptExtentions)

- (jsval) oo_jsValueInContext:(JSContext *)context
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


- (NSString *) oo_jsClassName
{
	return @"SoundSource";
}

@end
