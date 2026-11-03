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
#import "OOJSPrivateObject.h"
#import "OOJSSound.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import "OOSound.h"
#import "ResourceManager.h"

#include "oofnd/String.hpp"

/*
        C++20 since bead oo-cib0, converted the way bead oo-ppc converted OOJSVector.mm (proposed
        ADR-0056 amendment oo-ppc). The JS class was already C++ on QuickJS-ng;
        OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
        (OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. The category on OOSoundSource
        became two free functions, and its methods moved to the Scripting bridge file (amendment
        oo-ykoy). The source's and the sound's facades and that file are gone: both are C++, and a
        SoundSource object's private slot holds an OOJSSoundSourceHolder of the source.
*/

static JSClassID sSoundSourceClassID;

static JSValue SoundSourceGetProperty(OOJS_GETTER_ARGS);
static JSValue SoundSourceSetProperty(OOJS_SETTER_ARGS);
static JSValue SoundSourceConstruct(OOJS_NATIVE_ARGS);

// Methods
static JSValue SoundSourceToString(OOJS_NATIVE_ARGS);
static JSValue SoundSourcePlay(OOJS_NATIVE_ARGS);
static JSValue SoundSourceStop(OOJS_NATIVE_ARGS);
static JSValue SoundSourcePlayOrRepeat(OOJS_NATIVE_ARGS);

static JSClassDef sSoundSourceClass = {
    .class_name = "SoundSource",
    .finalizer = OOJSCxxObjectWrapperFinalize,
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
    JS_CFUNC_DEF("toString", 0, SoundSourceToString),
    JS_CFUNC_DEF("play", 0, SoundSourcePlay),
    JS_CFUNC_DEF("playOrRepeat", 0, SoundSourcePlayOrRepeat),
    // playSound is defined in oolite-global-prefix.js.
    JS_CFUNC_DEF("stop", 0, SoundSourceStop),
};

// OOJSSoundSourceHolder (OOJSSoundSource.h): the JS glue of a SoundSource object's slot.
OOJSSoundSourceHolder::OOJSSoundSourceHolder(OOSoundSource* inSource)
    : _source(inSource)
{
}
OOJSSoundSourceHolder::~OOJSSoundSourceHolder() = default;
OOSoundSource* OOJSSoundSourceHolder::source() const { return _source.get(); }
JSValue OOJSSoundSourceHolder::jsValueInContext(JSContext* context) { return OOJSSoundSourceJSValueInContext(_source.get(), context); }
void OOJSSoundSourceHolder::clearJSSelf(JSValueConst) { } // no wrapper is kept

std::optional<std::string> OOJSSoundSourceHolder::jsDescription()
{
    const std::optional<std::string> components = _source->descriptionComponents();
    if (components.has_value())
        return oo::str::format("[SoundSource %s]", components->c_str());
    return std::string("[object SoundSource]");
}

// DEFINE_JS_OBJECT_GETTER's equivalent for the slot's holder (OOJSPrivateObject.h): the source, or
// null for SoundSource.prototype, which has none.
static bool JSSoundSourceGetSoundSource(JSContext* context, JSValueConst object, OOSoundSource** outSource)
{
    OOJSSoundSourceHolder* holder = nullptr;
    if (!OOJSGetCxxPrivate(context, object, sSoundSourceClassID, &holder))
        return false;
    *outSource = (holder != nullptr) ? holder->source() : nullptr;
    return true;
}

// The class's converter: the slot held the source's facade, which OOJSBasicPrivateObjectConverter
// handed to Objective-C callers of OOJSNativeObjectFromJSValue. No Objective-C object is left to
// hand over, and nothing asks for one.
static oo::PList SoundSourceConverter(JSContext*, JSValueConst)
{
    return oo::PList();
}

// *** Public ***

void InitOOJSSoundSource(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sSoundSourceClassID, &sSoundSourceClass);
    OOJSInitClass(context, global, sSoundSourceClassID, JS_UNDEFINED, SoundSourceConstruct, 0,
        sSoundSourceProperties, OOJS_COUNT(sSoundSourceProperties), sSoundSourceMethods, OOJS_COUNT(sSoundSourceMethods), NULL, 0);
    OOJSRegisterObjectConverter(sSoundSourceClassID, SoundSourceConverter);
}

static JSValue SoundSourceConstruct(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (EXPECT_NOT(!OOJS_IS_CONSTRUCTING)) {
        cxx_OOJSReportError(context, "SoundSource() cannot be called as a function, it must be used as a constructor (as in new SoundSource()).");
        return JS_EXCEPTION;
    }

    const oo::Ref<OOSoundSource> source = oo::makeRef<OOSoundSource>(); // [[[OOSoundSource alloc] init] autorelease]
    OOJS_RETURN(OOJSSoundSourceJSValueInContext(source.get(), context));

    OOJS_NATIVE_EXIT
}

// *** Implementation stuff ***

static JSValue SoundSourceGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOSoundSource* soundSource = nullptr; // null for SoundSource.prototype

    if (!JSSoundSourceGetSoundSource(context, thisObj, &soundSource))
        return OOJSNativeFailure(context);

    switch (magic) {
    // (Each answers what a message to nil did for the prototype, which has no source.)
    case kSoundSource_sound:
        return OOJSSoundJSValueInContext((soundSource != nullptr) ? soundSource->sound() : nullptr, context);

    case kSoundSource_isPlaying:
        return OOJSValueFromBOOL(soundSource != nullptr && soundSource->isPlaying());

    case kSoundSource_loop:
        return OOJSValueFromBOOL(soundSource != nullptr && soundSource->loop());

    case kSoundSource_repeatCount:
        return JS_NewInt32(context, (soundSource != nullptr) ? soundSource->repeatCount() : 0);

    case kSoundSource_position:
        OOJS_RETURN_VECTOR((soundSource != nullptr) ? soundSource->position() : Vector { }); // a zeroed struct, as from nil

    case kSoundSource_positional:
        return OOJSValueFromBOOL(soundSource != nullptr && soundSource->positional());

    case kSoundSource_volume:
        return JS_NewNumber(context, (soundSource != nullptr) ? soundSource->gain() : 0.0f);

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sSoundSourceProperties, OOJS_COUNT(sSoundSourceProperties));
        return OOJSNativeFailure(context);
    }

    OOJS_NATIVE_EXIT
}

static JSValue SoundSourceSetProperty(OOJS_SETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOSoundSource* soundSource = nullptr; // null for SoundSource.prototype
    int32_t iValue;
    int bValue;
    Vector vValue;
    double fValue;

    if (!JSSoundSourceGetSoundSource(context, thisObj, &soundSource))
        return OOJSNativeFailure(context);

    switch (magic) {
    case kSoundSource_sound:
        if (soundSource != nullptr)
            soundSource->setSound(SoundFromJSValue(context, value));
        return JS_UNDEFINED;
        break;

    case kSoundSource_loop:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            if (soundSource != nullptr)
                soundSource->setLoop(bValue != 0);
            return JS_UNDEFINED;
        }
        break;

    case kSoundSource_repeatCount:
        if (OOJSValueToInt32(context, value, &iValue)) {
            if (iValue > 100)
                iValue = 100;
            if (100 < 1)
                iValue = 1;
            if (soundSource != nullptr)
                soundSource->setRepeatCount(iValue);
            return JS_UNDEFINED;
        }
        break;

    case kSoundSource_position:
        if (JSValueToVector(context, value, &vValue)) {
            if (soundSource != nullptr)
                soundSource->setPosition(vValue);
            return JS_UNDEFINED;
        }
        break;

    case kSoundSource_positional:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            if (soundSource != nullptr)
                soundSource->setPositional(bValue != 0);
            return JS_UNDEFINED;
        }
        break;

    case kSoundSource_volume:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            fValue = OOClamp_0_max_d(fValue, 1);
            if (soundSource != nullptr)
                soundSource->setGain(fValue);
            return JS_UNDEFINED;
        }
        break;

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sSoundSourceProperties, OOJS_COUNT(sSoundSourceProperties));
        return OOJSNativeFailure(context);
    }

    OOJSReportBadPropertyValue(context, thisObj, magic, sSoundSourceProperties, OOJS_COUNT(sSoundSourceProperties), value);
    return OOJSNativeFailure(context);

    OOJS_NATIVE_EXIT
}

// *** Methods ***

// toString() : String
static JSValue SoundSourceToString(OOJS_NATIVE_ARGS)
{
    return OOJSCxxObjectWrapperToString(context, OOJS_THIS, sSoundSourceClassID);
}

// play([count : Number])
static JSValue SoundSourcePlay(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOSoundSource* thisv = nullptr; // null for SoundSource.prototype
    int32_t count = 0;

    if (EXPECT_NOT(!JSSoundSourceGetSoundSource(context, OOJS_THIS, &thisv)))
        return OOJSNativeFailure(context);
    if (argc > 0 && !JS_IsUndefined(OOJS_ARGV[0]) && !OOJSValueToInt32(context, OOJS_ARGV[0], &count)) {
        cxx_OOJSReportBadArguments(context, "SoundSource", "play", 1, OOJS_ARGV, std::nullopt, "integer count or no argument");
        return OOJSNativeFailure(context);
    }

    if (count > 0) {
        if (count > 100)
            count = 100;
        if (thisv != nullptr)
            thisv->setRepeatCount(count);
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    if (thisv != nullptr)
        thisv->play();
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// stop()
static JSValue SoundSourceStop(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOSoundSource* thisv = nullptr; // null for SoundSource.prototype

    if (EXPECT_NOT(!JSSoundSourceGetSoundSource(context, OOJS_THIS, &thisv)))
        return OOJSNativeFailure(context);

    OOJS_BEGIN_FULL_NATIVE(context)
    if (thisv != nullptr)
        thisv->stop();
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// playOrRepeat()
static JSValue SoundSourcePlayOrRepeat(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOSoundSource* thisv = nullptr; // null for SoundSource.prototype

    if (EXPECT_NOT(!JSSoundSourceGetSoundSource(context, OOJS_THIS, &thisv)))
        return OOJSNativeFailure(context);

    OOJS_BEGIN_FULL_NATIVE(context)
    if (thisv != nullptr)
        thisv->playOrRepeat();
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// The bodies of OOSoundSource (OOJavaScriptExtentions), whose methods were in the Scripting bridge
// file while the source had a facade (proposed ADR-0056 amendments oo-ppc and oo-ykoy). A null
// source is JS null, as OOJSValueFromNativeObject() answered nil.
JSValue OOJSSoundSourceJSValueInContext(OOSoundSource* source, JSContext* context)
{
    if (source == nullptr)
        return JS_NULL;

    JSValue result = JS_NewObjectClass(context, (int)sSoundSourceClassID);
    if (JS_IsException(result)) {
        JS_FreeValue(context, JS_GetException(context));
        return JS_NULL;
    }
    const oo::Ref<OOJSSoundSourceHolder> holder = oo::makeRef<OOJSSoundSourceHolder>(source);
    if (!OOJSSetCxxPrivate(result, holder.get())) {
        JS_FreeValue(context, result);
        return JS_NULL;
    }

    return result;
}

std::optional<std::string> OOJSSoundSourceJSClassName(void)
{
    return std::string("SoundSource");
}
