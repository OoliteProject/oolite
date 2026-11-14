/*

OOJSSound.m (QuickJS-ng)

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
#import "OOMusicController.h"
#import "ResourceManager.h"
#import "Universe.h"

#include "oofnd/String.hpp"

static JSClassID sSoundClassID;

static OOSound* GetNamedSound(const std::string& name);

static JSValue SoundGetProperty(OOJS_GETTER_ARGS);

// Static methods
static JSValue SoundStaticLoad(OOJS_NATIVE_ARGS);
static JSValue SoundStaticMusicSoundSource(OOJS_NATIVE_ARGS);
static JSValue SoundStaticPlayMusic(OOJS_NATIVE_ARGS);
static JSValue SoundStaticStopMusic(OOJS_NATIVE_ARGS);

static JSClassDef sSoundClass = {
    .class_name = "Sound",
    .finalizer = OOJSObjectWrapperFinalize,
};

enum {
    // Property IDs
    kSound_name
};

static const JSCFunctionListEntry sSoundProperties[] = {
    // JS name, getter, ID
    OOJS_PROPERTY_RO("name", SoundGetProperty, kSound_name),
};

static const JSCFunctionListEntry sSoundMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("toString", 0, OOJSObjectWrapperToString),
};

static const JSCFunctionListEntry sSoundStaticMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("load", 1, SoundStaticLoad),
    JS_CFUNC_DEF("musicSoundSource", 0, SoundStaticMusicSoundSource),
    JS_CFUNC_DEF("playMusic", 1, SoundStaticPlayMusic),
    JS_CFUNC_DEF("stopMusic", 0, SoundStaticStopMusic),
};

DEFINE_JS_OBJECT_GETTER(JSSoundGetSound, sSoundClassID, OOSound)

// *** Public ***

void InitOOJSSound(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sSoundClassID, &sSoundClass);
    OOJSInitClass(context, global, sSoundClassID, JS_UNDEFINED, OOJSUnconstructableConstruct, 0,
        sSoundProperties, OOJS_COUNT(sSoundProperties), sSoundMethods, OOJS_COUNT(sSoundMethods),
        sSoundStaticMethods, OOJS_COUNT(sSoundStaticMethods));
    OOJSRegisterObjectConverter(sSoundClassID, OOJSBasicPrivateObjectConverter);
}

OOSound* SoundFromJSValue(JSContext* context, JSValueConst value)
{
    OOJS_PROFILE_ENTER

    OOSound* result = nil;

    /*	The SpiderMonkey version returned before resuming the time limiter,
            leaving it paused; the pause is balanced here.
    */
    OOJSPauseTimeLimiter();
    if ([PLAYER status] != STATUS_START_GAME && JS_IsString(value)) {
        result = GetNamedSound(cxx_OOStringFromJSValue(context, value).value_or(std::string()));
    } else {
        result = OOJSNativeObjectOfClassFromJSValue(context, value, [OOSound class]);
    }
    OOJSResumeTimeLimiter();

    return result;

    OOJS_PROFILE_EXIT
}

// *** Implementation stuff ***

static JSValue SoundGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOSound* sound = nil;

    if (EXPECT_NOT(!JSSoundGetSound(context, thisObj, &sound)))
        return OOJSNativeFailure(context);

    switch (magic) {
    case kSound_name: {
        const std::optional<std::string> name = [sound cxx_name];
        return OOJSValueFromPList(context, name.has_value() ? oo::PList(*name) : oo::PList());
    }

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sSoundProperties, OOJS_COUNT(sSoundProperties));
        return OOJSNativeFailure(context);
    }

    OOJS_NATIVE_EXIT
}

static OOSound* GetNamedSound(const std::string& name)
{
    OOSound* sound = nil;

    if (oo::str::hasPrefix(name, "[") && oo::str::hasSuffix(name, "]")) {
        sound = [OOSound cxx_soundWithCustomSoundKey:name];
    } else {
        sound = [ResourceManager cxx_ooSoundNamed:name inFolder:"Sounds"];
    }

    return sound;
}

// *** Static methods ***

// load(name : String) : Sound
static JSValue SoundStaticLoad(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> name;
    OOSound* sound = nil;

    if (argc > 0)
        name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (!name.has_value()) {
        cxx_OOJSReportBadArguments(context, "Sound", "load", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string");
        return OOJSNativeFailure(context);
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    sound = GetNamedSound(*name);
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_OBJECT(sound);

    OOJS_NATIVE_EXIT
}

static JSValue SoundStaticMusicSoundSource(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)
    OOSoundSource* musicSource = nil;
    OOJS_BEGIN_FULL_NATIVE(context)
    musicSource = [[OOMusicController sharedController] soundSource];
    OOJS_END_FULL_NATIVE
    OOJS_RETURN_OBJECT(musicSource);
    OOJS_NATIVE_EXIT
}

// playMusic(name : String [, loop : Boolean] [, gain : float])
static JSValue SoundStaticPlayMusic(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> name;
    BOOL loop = NO;
    double gain = OO_DEFAULT_SOUNDSOURCE_GAIN;

    if (argc > 0)
        name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (!name.has_value()) {
        cxx_OOJSReportBadArguments(context, "Sound", "playMusic", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string");
        return OOJSNativeFailure(context);
    }
    if (argc > 1) {
        int b = JS_ToBool(context, OOJS_ARGV[1]);
        if (b < 0) {
            cxx_OOJSReportBadArguments(context, "Sound", "playMusic", 1, OOJS_ARGV + 1, std::nullopt, "boolean");
            return OOJSNativeFailure(context);
        }
        loop = b;
    }

    if (argc > 2) {
        if (!cxx_OOJSArgumentListGetNumber(context, "Sound", "playMusic", 2, OOJS_ARGV + 2, &gain, NULL)) {
            cxx_OOJSReportBadArguments(context, "Sound", "playMusic", 1, OOJS_ARGV + 2, std::nullopt, "float");
            return OOJSNativeFailure(context);
        }
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    [[OOMusicController sharedController] playMusicNamed:*name loop:loop gain:(float)gain];
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// Sound.stopMusic([name : String])
static JSValue SoundStaticStopMusic(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> name;

    if (argc > 0) {
        name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
        if (EXPECT_NOT(!name.has_value())) {
            cxx_OOJSReportBadArguments(context, "Sound", "stopMusic", argc, OOJS_ARGV, std::nullopt, "string or no argument");
            return OOJSNativeFailure(context);
        }
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    OOMusicController* controller = [OOMusicController sharedController];
    if (!name.has_value() || name == [controller playingMusic]) {
        [[OOMusicController sharedController] stop];
    }
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

@implementation OOSound (OOJavaScriptExtentions)

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    JSValue result = JS_NewObjectClass(context, (int)sSoundClassID);
    if (JS_IsException(result)) {
        JS_FreeValue(context, JS_GetException(context));
        return JS_NULL;
    }
    JS_SetOpaque(result, [self retain]);

    return result;
}

- (std::optional<std::string>)cxx_oo_jsDescription
{
    return oo::str::format("[Sound \"%s\"]", [self cxx_name].value_or("(null)").c_str());
}

- (std::optional<std::string>)cxx_oo_jsClassName
{
    return std::string("Sound");
}

@end
