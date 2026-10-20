/*

OOJSSoundSource.m (QuickJS-ng)

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

#import "OOJSSoundSource.h"
#import "OOJSSound.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import "OOSound.h"
#import "ResourceManager.h"

static JSClassID sSoundSourceClassID;

static JSValue SoundSourceGetProperty(OOJS_GETTER_ARGS);
static JSValue SoundSourceSetProperty(OOJS_SETTER_ARGS);
static JSValue SoundSourceConstruct(OOJS_NATIVE_ARGS);

// Methods
static JSValue SoundSourcePlay(OOJS_NATIVE_ARGS);
static JSValue SoundSourceStop(OOJS_NATIVE_ARGS);
static JSValue SoundSourcePlayOrRepeat(OOJS_NATIVE_ARGS);

static JSClassDef sSoundSourceClass = {
    .class_name = "SoundSource",
    .finalizer = OOJSObjectWrapperFinalize,
};

enum {
    // Property IDs
    kSoundSource_sound,
    kSoundSource_isPlaying,
    kSoundSource_loop,
    kSoundSource_position,
    kSoundSource_positional,
    kSoundSource_repeatCount,
    kSoundSource_volume
};

static const JSCFunctionListEntry sSoundSourceProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RO("isPlaying", SoundSourceGetProperty, kSoundSource_isPlaying),
    OOJS_PROPERTY_RW("loop", SoundSourceGetProperty, SoundSourceSetProperty, kSoundSource_loop),
    OOJS_PROPERTY_RW("position", SoundSourceGetProperty, SoundSourceSetProperty, kSoundSource_position),
    OOJS_PROPERTY_RW("positional", SoundSourceGetProperty, SoundSourceSetProperty, kSoundSource_positional),
    OOJS_PROPERTY_RW("repeatCount", SoundSourceGetProperty, SoundSourceSetProperty, kSoundSource_repeatCount),
    OOJS_PROPERTY_RW("sound", SoundSourceGetProperty, SoundSourceSetProperty, kSoundSource_sound),
    OOJS_PROPERTY_RW("volume", SoundSourceGetProperty, SoundSourceSetProperty, kSoundSource_volume),
};

static const JSCFunctionListEntry sSoundSourceMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("toString", 0, OOJSObjectWrapperToString),
    JS_CFUNC_DEF("play", 0, SoundSourcePlay),
    JS_CFUNC_DEF("playOrRepeat", 0, SoundSourcePlayOrRepeat),
    // playSound is defined in oolite-global-prefix.js.
    JS_CFUNC_DEF("stop", 0, SoundSourceStop),
};

DEFINE_JS_OBJECT_GETTER(JSSoundSourceGetSoundSource, sSoundSourceClassID, OOSoundSource)

// *** Public ***

void InitOOJSSoundSource(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sSoundSourceClassID, &sSoundSourceClass);
    OOJSInitClass(context, global, sSoundSourceClassID, JS_UNDEFINED, SoundSourceConstruct, 0,
        sSoundSourceProperties, OOJS_COUNT(sSoundSourceProperties), sSoundSourceMethods, OOJS_COUNT(sSoundSourceMethods), NULL, 0);
    OOJSRegisterObjectConverter(sSoundSourceClassID, OOJSBasicPrivateObjectConverter);
}

static JSValue SoundSourceConstruct(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (EXPECT_NOT(!OOJS_IS_CONSTRUCTING)) {
        OOJSReportError(context, @"SoundSource() cannot be called as a function, it must be used as a constructor (as in new SoundSource()).");
        return JS_EXCEPTION;
    }

    OOJS_RETURN_OBJECT([[[OOSoundSource alloc] init] autorelease]);

    OOJS_NATIVE_EXIT
}

// *** Implementation stuff ***

static JSValue SoundSourceGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOSoundSource* soundSource = nil;

    if (!JSSoundSourceGetSoundSource(context, this, &soundSource))
        return OOJSNativeFailure(context);

    switch (magic) {
    case kSoundSource_sound:
        return OOJSValueFromNativeObject(context, [soundSource sound]);

    case kSoundSource_isPlaying:
        return OOJSValueFromBOOL([soundSource isPlaying]);

    case kSoundSource_loop:
        return OOJSValueFromBOOL([soundSource loop]);

    case kSoundSource_repeatCount:
        return JS_NewInt32(context, [soundSource repeatCount]);

    case kSoundSource_position:
        OOJS_RETURN_VECTOR([soundSource position]);

    case kSoundSource_positional:
        return OOJSValueFromBOOL([soundSource positional]);

    case kSoundSource_volume:
        return JS_NewNumber(context, [soundSource gain]);

    default:
        OOJSReportBadPropertySelector(context, this, magic, sSoundSourceProperties, OOJS_COUNT(sSoundSourceProperties));
        return OOJSNativeFailure(context);
    }

    OOJS_NATIVE_EXIT
}

static JSValue SoundSourceSetProperty(OOJS_SETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOSoundSource* soundSource = nil;
    int32_t iValue;
    int bValue;
    Vector vValue;
    double fValue;

    if (!JSSoundSourceGetSoundSource(context, this, &soundSource))
        return OOJSNativeFailure(context);

    switch (magic) {
    case kSoundSource_sound:
        [soundSource setSound:SoundFromJSValue(context, value)];
        return JS_UNDEFINED;
        break;

    case kSoundSource_loop:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            [soundSource setLoop:bValue];
            return JS_UNDEFINED;
        }
        break;

    case kSoundSource_repeatCount:
        if (OOJSValueToInt32(context, value, &iValue)) {
            if (iValue > 100)
                iValue = 100;
            if (100 < 1)
                iValue = 1;
            [soundSource setRepeatCount:iValue];
            return JS_UNDEFINED;
        }
        break;

    case kSoundSource_position:
        if (JSValueToVector(context, value, &vValue)) {
            [soundSource setPosition:vValue];
            return JS_UNDEFINED;
        }
        break;

    case kSoundSource_positional:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            [soundSource setPositional:bValue];
            return JS_UNDEFINED;
        }
        break;

    case kSoundSource_volume:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            fValue = OOClamp_0_max_d(fValue, 1);
            [soundSource setGain:fValue];
            return JS_UNDEFINED;
        }
        break;

    default:
        OOJSReportBadPropertySelector(context, this, magic, sSoundSourceProperties, OOJS_COUNT(sSoundSourceProperties));
        return OOJSNativeFailure(context);
    }

    OOJSReportBadPropertyValue(context, this, magic, sSoundSourceProperties, OOJS_COUNT(sSoundSourceProperties), value);
    return OOJSNativeFailure(context);

    OOJS_NATIVE_EXIT
}

// *** Methods ***

// play([count : Number])
static JSValue SoundSourcePlay(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOSoundSource* thisv = nil;
    int32_t count = 0;

    if (EXPECT_NOT(!JSSoundSourceGetSoundSource(context, OOJS_THIS, &thisv)))
        return OOJSNativeFailure(context);
    if (argc > 0 && !JS_IsUndefined(OOJS_ARGV[0]) && !OOJSValueToInt32(context, OOJS_ARGV[0], &count)) {
        OOJSReportBadArguments(context, @"SoundSource", @"play", 1, OOJS_ARGV, nil, @"integer count or no argument");
        return OOJSNativeFailure(context);
    }

    if (count > 0) {
        if (count > 100)
            count = 100;
        [thisv setRepeatCount:count];
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    [thisv play];
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// stop()
static JSValue SoundSourceStop(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOSoundSource* thisv = nil;

    if (EXPECT_NOT(!JSSoundSourceGetSoundSource(context, OOJS_THIS, &thisv)))
        return OOJSNativeFailure(context);

    OOJS_BEGIN_FULL_NATIVE(context)
    [thisv stop];
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// playOrRepeat()
static JSValue SoundSourcePlayOrRepeat(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOSoundSource* thisv = nil;

    if (EXPECT_NOT(!JSSoundSourceGetSoundSource(context, OOJS_THIS, &thisv)))
        return OOJSNativeFailure(context);

    OOJS_BEGIN_FULL_NATIVE(context)
    [thisv playOrRepeat];
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

@implementation OOSoundSource (OOJavaScriptExtentions)

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    JSValue result = JS_NewObjectClass(context, (int)sSoundSourceClassID);
    if (JS_IsException(result)) {
        JS_FreeValue(context, JS_GetException(context));
        return JS_NULL;
    }
    JS_SetOpaque(result, [self retain]);

    return result;
}

- (NSString*)oo_jsClassName
{
    return @"SoundSource";
}

@end
