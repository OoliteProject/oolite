/*

OOJSOolite.h

JavaScript proxy for Oolite (for version checking and similar).


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

#include "OOJSOolite.h"
#include "MyOpenGLView.h"
#include "OOConstToString.h"
#include "OOJSPlayer.h"
#include "OOJavaScriptEngine.h"
#include "OOStringParsing.h"
#include "ResourceManager.h"
#include "oofnd/FileSystem.hpp"
#include "oofnd/PListParsing.hpp"
#include "oofnd/ResourcePaths.hpp"
#include "oofnd/String.hpp"

static JSValue OoliteGetProperty(OOJS_GETTER_ARGS);
static JSValue OoliteSetProperty(OOJS_SETTER_ARGS);

namespace {

// Info-gnustep.plist string (CFBundleVersion / CFBundleName as the Override category used to expose).
std::optional<std::string> OoliteInfoString(std::string_view key)
{
    const oo::fs::Path plistPath = oo::ResourcePaths::current().builtInResourcesDirectory() / "Info-gnustep.plist";
    oo::PList info;
    if (const oo::fs::Result<oo::Data> bytes = oo::fs::readFile(plistPath); bytes && !bytes->empty()) {
        if (oo::Expected<oo::PList, oo::PListError> parsed = oo::parsePropertyList(bytes->stringView());
            parsed && parsed->isDict())
            info = std::move(*parsed);
    }
    if (const oo::PList* v = info.find(key); v != nullptr && v->isString())
        return *v->getIf<std::string>();
    return std::nullopt;
}

} // namespace

/*
        C++20 since bead oo-whvg, converted the way bead oo-ppc converted OOJSVector.mm (proposed
        ADR-0056 amendment oo-ppc). The natives were already C++ on QuickJS-ng;
        OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
        (OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. Nothing else in the file was
        Objective-C: the universe, its game view and the resource manager, which are not converted, are
        still messaged, which is why the file is still .mm until Phase 4.
*/

static std::optional<std::string> VersionString(void);
static std::vector<unsigned> VersionComponents(void);
static unsigned UnsignedIntValue(const oo::PList& number);

static JSValue OoliteCompareVersion(OOJS_NATIVE_ARGS);

/*	oolite.jsVersion was SpiderMonkey's JS_GetVersion(), 185 (JSVERSION_ECMA_5).
        OXPs compare it numerically, so it stays 185: QuickJS implements a
        superset of ES5. jsVersionString was "1.8.5"; it now names the engine.
*/
enum {
    kOOJSCompatibleJSVersion = 185
};

static JSClassID sOoliteClassID;
static JSClassDef sOoliteClass = {
    .class_name = "Oolite",
};

enum {
    // Property IDs
    kOolite_version, // version number components, array, read-only
    kOolite_versionString, // version number as string, string, read-only
    kOolite_jsVersion, // JavaScript version, integer, read-only
    kOolite_jsVersionString, // JavaScript version as string, string, read-only
    kOolite_gameSettings, // Various game settings, object, read-only
    kOolite_resourcePaths, // Paths containing resources, built-in plus oxp/oxz, read-only
    kOolite_colorSaturation, // Color saturation, integer, read/write
    kOolite_postFX, // current post processing effect, integer, read/write
    kOolite_hdrToneMapper, // currently active HDR tone mapper, string, read/write
    kOolite_sdrToneMapper, // currently active SDR tone mapper, string, read/write
#ifdef OO_DEBUG_MONITOR_ENABLED
    kOolite_timeAccelerationFactor, // time acceleration, float, read/write
#endif
};

static const JSCFunctionListEntry sOoliteProperties[] = {
    // JS name					Getter				Setter				ID
    OOJS_PROPERTY_RO("gameSettings", OoliteGetProperty, kOolite_gameSettings),
    OOJS_PROPERTY_RO("jsVersion", OoliteGetProperty, kOolite_jsVersion),
    OOJS_PROPERTY_RO("jsVersionString", OoliteGetProperty, kOolite_jsVersionString),
    OOJS_PROPERTY_RO("version", OoliteGetProperty, kOolite_version),
    OOJS_PROPERTY_RO("versionString", OoliteGetProperty, kOolite_versionString),
    OOJS_PROPERTY_RO("resourcePaths", OoliteGetProperty, kOolite_resourcePaths),
    OOJS_PROPERTY_RW("colorSaturation", OoliteGetProperty, OoliteSetProperty, kOolite_colorSaturation),
    OOJS_PROPERTY_RW("postFX", OoliteGetProperty, OoliteSetProperty, kOolite_postFX),
    OOJS_PROPERTY_RW("hdrToneMapper", OoliteGetProperty, OoliteSetProperty, kOolite_hdrToneMapper),
    OOJS_PROPERTY_RW("sdrToneMapper", OoliteGetProperty, OoliteSetProperty, kOolite_sdrToneMapper),
#ifdef OO_DEBUG_MONITOR_ENABLED
    OOJS_PROPERTY_RW("timeAccelerationFactor", OoliteGetProperty, OoliteSetProperty, kOolite_timeAccelerationFactor),
#endif
};

static const JSCFunctionListEntry sOoliteMethods[] = {
    // JS name					Function					min args
    JS_CFUNC_DEF("compareVersion", 1, OoliteCompareVersion),
};

void InitOOJSOolite(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sOoliteClassID, &sOoliteClass);
    JSValueConst oolitePrototype = OOJSInitClass(context, global, sOoliteClassID, JS_UNDEFINED, OOJSUnconstructableConstruct, 0,
        sOoliteProperties, OOJS_COUNT(sOoliteProperties), sOoliteMethods, OOJS_COUNT(sOoliteMethods), NULL, 0);
    JS_DefinePropertyValueStr(context, global, "oolite", JS_NewObjectProtoClass(context, oolitePrototype, sOoliteClassID), OOJS_PROP_READONLY);
}

static JSValue OoliteGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    oo::PList result; // null: nil
    MyOpenGLView* gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);

    switch (magic) {
    case kOolite_version: {
        // The components as ComponentsFromVersionString() gave them: an array of unsigned numbers.
        oo::PList::Array components;
        for (unsigned component : VersionComponents())
            components.push_back(oo::PList::unsignedInteger(component));
        result = oo::PList(std::move(components));
        break;
    }

    case kOolite_versionString: {
        const std::optional<std::string> version = VersionString();
        if (version.has_value())
            result = oo::PList(*version);
        break;
    }

    case kOolite_jsVersion:
        return JS_NewInt32(context, kOOJSCompatibleJSVersion);

    case kOolite_jsVersionString:
        result = oo::PList(std::string("QuickJS-ng ") + JS_GetVersion());
        break;

    case kOolite_gameSettings:
        result = (UNIVERSE != nullptr ? UNIVERSE->gameSettings() : oo::PList());
        break;

    case kOolite_resourcePaths:
        // user name in displayed paths masked for privacy - remember that the console can be run remotely too
        {
            oo::PList::Array paths;
            for (const std::string& path : ResourceManager::maskUserNameInPathArray(ResourceManager::paths()))
                paths.push_back(oo::PList(path));
            result = oo::PList(std::move(paths));
            break;
        }

    case kOolite_colorSaturation:
        return JS_NewNumber(context, (gameView != nullptr ? gameView->colorSaturation() : 0.0f));

    case kOolite_postFX:
        return JS_NewInt32(context, (UNIVERSE != nullptr ? UNIVERSE->currentPostFX() : 0));

    case kOolite_hdrToneMapper: {
        std::optional<std::string> toneMapperStr = "OOHDR_TONEMAPPER_UNDEFINED";
#if OOLITE_WINDOWS
        if ((gameView != nullptr ? gameView->hdrOutput() : false)) {
            toneMapperStr = cxx_OOStringFromHDRToneMapper((gameView != nullptr ? gameView->hdrToneMapper() : OOHDRToneMapper { }));
        }
#endif
        if (toneMapperStr.has_value())
            result = oo::PList(*toneMapperStr);
        break;
    }

    case kOolite_sdrToneMapper: {
        std::optional<std::string> toneMapperStr = "OOSDR_TONEMAPPER_UNDEFINED";
        if (!(gameView != nullptr ? gameView->hdrOutput() : false)) {
            toneMapperStr = cxx_OOStringFromSDRToneMapper((gameView != nullptr ? gameView->sdrToneMapper() : OOSDRToneMapper { }));
        }
        if (toneMapperStr.has_value())
            result = oo::PList(*toneMapperStr);
        break;
    }

#ifdef OO_DEBUG_MONITOR_ENABLED
    case kOolite_timeAccelerationFactor:
        return JS_NewNumber(context, (UNIVERSE != nullptr ? UNIVERSE->getTimeAccelerationFactor() : 0.0));
#endif

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sOoliteProperties, OOJS_COUNT(sOoliteProperties));
        return JS_EXCEPTION;
    }

    return OOJSValueFromPList(context, result);

    OOJS_NATIVE_EXIT
}

static JSValue OoliteSetProperty(OOJS_SETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    double fValue;
    int32_t iValue;
    std::optional<std::string> sValue;
    MyOpenGLView* gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);

    switch (magic) {
    case kOolite_colorSaturation:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            float currentColorSaturation = (gameView != nullptr ? gameView->colorSaturation() : 0.0f);
            if (gameView != nullptr)
                gameView->adjustColorSaturation(fValue - currentColorSaturation);
            return JS_UNDEFINED;
        }
        break;

    case kOolite_postFX:
        if (OOJSValueToInt32(context, value, &iValue)) {
            iValue = MAX(iValue, 0);
            if (UNIVERSE != nullptr)
                UNIVERSE->setCurrentPostFX(iValue);
            return JS_UNDEFINED;
        }
        break;

    case kOolite_hdrToneMapper:
        if (!JS_IsString(value))
            break; // non-string is not allowed
        sValue = cxx_OOStringFromJSValue(context, value);
        if (sValue.has_value()) {
#if OOLITE_WINDOWS
            if ((gameView != nullptr ? gameView->hdrOutput() : false)) {
                if (gameView != nullptr)
                    gameView->setHDRToneMapper(cxx_OOHDRToneMapperFromString(*sValue));
            } else
                cxx_OOJSReportWarning(context, "hdrToneMapper cannot be set if not running in HDR mode");
#endif
            return JS_UNDEFINED;
        }
        break;

    case kOolite_sdrToneMapper:
        if (!JS_IsString(value))
            break; // non-string is not allowed
        sValue = cxx_OOStringFromJSValue(context, value);
        if (sValue.has_value()) {
            if (!(gameView != nullptr ? gameView->hdrOutput() : false)) {
                if (gameView != nullptr)
                    gameView->setSDRToneMapper(cxx_OOSDRToneMapperFromString(*sValue));
            } else
                cxx_OOJSReportWarning(context, "sdrToneMapper cannot be set if not running in SDR mode");
            return JS_UNDEFINED;
        }
        break;

#ifdef OO_DEBUG_MONITOR_ENABLED
    case kOolite_timeAccelerationFactor:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (UNIVERSE != nullptr)
                UNIVERSE->setTimeAccelerationFactor(fValue);
            return JS_UNDEFINED;
        }
        break;
#endif

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sOoliteProperties, OOJS_COUNT(sOoliteProperties));
        return JS_EXCEPTION;
    }

    // A failed conversion may have left an exception pending; report the bad value instead, as before.
    if (JS_HasException(context))
        JS_FreeValue(context, JS_GetException(context));
    OOJSReportBadPropertyValue(context, thisObj, magic, sOoliteProperties, OOJS_COUNT(sOoliteProperties), value);
    return JS_EXCEPTION;

    OOJS_NATIVE_EXIT
}

static std::optional<std::string> VersionString(void)
{
    return OoliteInfoString("CFBundleVersion");
}

static std::vector<unsigned> VersionComponents(void)
{
    const std::optional<std::string> version = VersionString();
    if (!version.has_value())
        return { }; // ComponentsFromVersionString(nil) was empty
    return oo::str::versionComponents(*version);
}

// A JavaScript number's -unsignedIntValue, as CompareVersions() read it: C conversions.
static unsigned UnsignedIntValue(const oo::PList& number)
{
    if (const bool* boolean = number.getIf<bool>())
        return *boolean ? 1u : 0u;
    if (const oo::PList::Integer* integer = number.getIf<oo::PList::Integer>())
        return static_cast<unsigned>(integer->value);
    return static_cast<unsigned>(*number.getIf<double>());
}

/*	oolite.compareVersion(versionSpec) : Number
        returns -1 if the current version of Oolite is less than versionSpec, 0 if
        they are equal, and 1 if the current version is newer. versionSpec may be
        a string or an array. Example:
        if (0 < oolite.compareVersion("1.70"))  log("Old version of Oolite!")
        else  this.doStuffThatRequires170()
*/
static JSValue OoliteCompareVersion(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    oo::PList components;
    std::optional<std::vector<unsigned>> versionSpec;

    if (argc == 0)
        OOJS_RETURN_VOID; // Backwards-compatibility: be overly lenient.

    components = cxx_OOJSPListFromJSValue(context, OOJS_ARGV[0]);
    if (const oo::PList::Array* componentArray = components.getIf<oo::PList::Array>()) {
        // Require each element to be a number
        std::vector<unsigned> numbers;
        bool allNumbers = true;
        for (const oo::PList& component : *componentArray) {
            if (!component.isNumber()) {
                allNumbers = false;
                break;
            }
            numbers.push_back(UnsignedIntValue(component));
        }
        if (allNumbers)
            versionSpec = std::move(numbers);
    } else if (const std::string* componentString = components.getIf<std::string>()) {
        versionSpec = oo::str::versionComponents(*componentString);
    }

    if (versionSpec.has_value()) {
        OOJS_RETURN_INT((int32_t)oo::str::compareVersions(*versionSpec, VersionComponents()));
    } else {
        OOJS_RETURN_VOID;
    }

    OOJS_NATIVE_EXIT
}
