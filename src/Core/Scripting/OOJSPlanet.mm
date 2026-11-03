/*

OOJSPlanet.m (QuickJS-ng)


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

#import "OOJSPlanet.h"
#import "EntityOOJavaScriptExtensions.h"
#import "OOJSEntity.h"
#import "OOJSQuaternion.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import "OOPlanetEntity.h"
#include "oofnd/objc/OOAssert.h"

/*
        C++20 since bead oo-7ixd, converted the way bead oo-ppc converted OOJSVector.mm (proposed
        ADR-0056 amendment oo-ppc). The JS class was already C++ on QuickJS-ng;
        OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
        (OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. The category on OOPlanetEntity
        became two free functions, and its methods moved to a bridge file of the binding (amendment
        oo-ykoy), then onto the OOPlanetEntity facade in OOPlanetEntity+ObjCBridge.mm (bead oo-9ht.92,
        amendment oo-6ia4 item 3), then into the C++ planet's overrides when that facade was deleted;
        the planet is C++ and called directly, null-guarded where the message to nil was harmless. Its
        JS class is JSPlanetClassID(). OOColor, which is C++ since bead oo-11m, is reached as OOColor
        through oo::ToCxx/oo::ToObjC (amendment oo-ppc, item 4). Messages to classes that are still Objective-C (OOPlanetEntity, Universe) stay as
        they are, which is why the file is still .mm until Phase 4.
*/

static JSClassID sPlanetClassID;

static JSValue PlanetGetProperty(OOJS_GETTER_ARGS);
static JSValue PlanetSetProperty(OOJS_SETTER_ARGS);

namespace {

    // A colour's components as its -normalizedArray gave them to JavaScript: floats, null for no colour.
    oo::PList NormalizedColorComponents(OOColor* color)
    {
        if (color == nullptr)
            return oo::PList();
        oo::PList::Array components;
        for (float component : color->normalizedArray())
            components.push_back(oo::PList::singleReal(component));
        return oo::PList(std::move(components));
    }

} // namespace

static JSClassDef sPlanetClass = {
    .class_name = "Planet",
    .finalizer = OOJSCxxObjectWrapperFinalize, // the slot holds an OOJSEntityHolder
};

enum {
    // Property IDs
    kPlanet_airColor, // air color, read/write
    kPlanet_airColorMixRatio, // air color mix ratio, float, read/write
    kPlanet_airDensity, // air density, float, read/write
    kPlanet_hasAtmosphere,
    kPlanet_illuminationColor, // illumination color, read/write
    kPlanet_isMainPlanet, // Is [UNIVERSE planet], boolean, read-only
    kPlanet_name, // Name of planet, string, read/write
    kPlanet_radius, // Radius of planet in metres, read-only
    kPlanet_texture, // Planet texture read / write
    kPlanet_orientation, // orientation, quaternion, read/write
    kPlanet_rotationalVelocity, // read/write
    kPlanet_terminatorThresholdVector,
};

static const JSCFunctionListEntry sPlanetProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RW("airColor", PlanetGetProperty, PlanetSetProperty, kPlanet_airColor),
    OOJS_PROPERTY_RW("airColorMixRatio", PlanetGetProperty, PlanetSetProperty, kPlanet_airColorMixRatio),
    OOJS_PROPERTY_RW("airDensity", PlanetGetProperty, PlanetSetProperty, kPlanet_airDensity),
    OOJS_PROPERTY_RO("hasAtmosphere", PlanetGetProperty, kPlanet_hasAtmosphere),
    OOJS_PROPERTY_RW("illuminationColor", PlanetGetProperty, PlanetSetProperty, kPlanet_illuminationColor),
    OOJS_PROPERTY_RO("isMainPlanet", PlanetGetProperty, kPlanet_isMainPlanet),
    OOJS_PROPERTY_RW("name", PlanetGetProperty, PlanetSetProperty, kPlanet_name),
    OOJS_PROPERTY_RO("radius", PlanetGetProperty, kPlanet_radius),
    OOJS_PROPERTY_RW("rotationalVelocity", PlanetGetProperty, PlanetSetProperty, kPlanet_rotationalVelocity),
    OOJS_PROPERTY_RW("texture", PlanetGetProperty, PlanetSetProperty, kPlanet_texture),
    OOJS_PROPERTY_RW("orientation", PlanetGetProperty, PlanetSetProperty, kPlanet_orientation), // Not documented since it's inherited from Entity
    OOJS_PROPERTY_RW("terminatorThresholdVector", PlanetGetProperty, PlanetSetProperty, kPlanet_terminatorThresholdVector),
};

// The planet is C++ behind the root's facade: the getter checks the JS class (a Planet object's
// private slot holds the planet's Objective-C object, so -isKindOfClass: of the facade class always
// held) and answers the C++ planet; null for a stale entity, as nil before.
// The slot holds the C++ entity now (OOJSEntityGetEntityOfClass for the Planet class,
// DEFINE_JS_OBJECT_GETTER(JSPlanetGetPlanetObject, sPlanetClassID, Entity) before).
static bool JSPlanetGetPlanetEntity(JSContext* context, JSValueConst inObject, OOPlanetEntity** outObject)
{
    Entity* entity = nullptr;
    if (!OOJSEntityGetEntityOfClass(context, inObject, sPlanetClassID, &entity))
        return false;
    *outObject = dynamic_cast<OOPlanetEntity*>(entity);
    return true;
}

void InitOOJSPlanet(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sPlanetClassID, &sPlanetClass);

    JSValue parentPrototype = JS_GetClassProto(context, JSEntityClassID());
    OOCAssert(JS_IsObject(parentPrototype), "Entity must be initialized before Planet.");
    OOJSInitClass(context, global, sPlanetClassID, parentPrototype, OOJSUnconstructableConstruct, 0,
        sPlanetProperties, OOJS_COUNT(sPlanetProperties), NULL, 0, NULL, 0);
    JS_FreeValue(context, parentPrototype);

    OOJSRegisterObjectConverter(sPlanetClassID, OOJSEntityObjectConverter);
    OOJSRegisterSubclass(sPlanetClassID, JSEntityClassID());
}

JSClassID JSPlanetClassID(void)
{
    return sPlanetClassID;
}

// The bodies of OOPlanetEntity (OOJavaScriptExtensions), called by the C++ planet's overrides (the
// OOPlanetEntity facade forwarded to them before).
bool OOJSPlanetIsVisibleToScripts(OOPlanetEntity* planet)
{
    OOStellarBodyType type = (planet != nullptr ? planet->planetType() : (OOStellarBodyType)0);
    return type == STELLAR_TYPE_NORMAL_PLANET || type == STELLAR_TYPE_MOON;
}

std::optional<std::string> OOJSPlanetJSClassName(OOPlanetEntity* planet)
{
    switch ((planet != nullptr ? planet->planetType() : (OOStellarBodyType)0)) {
    case STELLAR_TYPE_NORMAL_PLANET:
        return std::string("Planet");
    case STELLAR_TYPE_MOON:
        return std::string("Moon");
    default:
        return std::string("Unknown");
    }
}

static JSValue PlanetGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOPlanetEntity* planet = nil;
    if (!JSPlanetGetPlanetEntity(context, thisObj, &planet))
        return OOJSNativeFailure(context);

    switch (magic) {
    case kPlanet_airColor:
        return OOJSValueFromPList(context, NormalizedColorComponents((planet != nullptr ? planet->airColor() : (OOColor*)nullptr)));

    case kPlanet_airColorMixRatio:
        return JS_NewNumber(context, (planet != nullptr ? planet->airColorMixRatio() : 0.0f));

    case kPlanet_airDensity:
        return JS_NewNumber(context, (planet != nullptr ? planet->airDensity() : 0.0f));

    case kPlanet_illuminationColor:
        return OOJSValueFromPList(context, NormalizedColorComponents((planet != nullptr ? planet->illuminationColor() : (OOColor*)nullptr)));

    case kPlanet_isMainPlanet:
        return OOJSValueFromBOOL(planet == (UNIVERSE != nullptr ? UNIVERSE->planet() : nullptr));

    case kPlanet_radius:
        return JS_NewNumber(context, (planet != nullptr ? planet->radius() : 0.0));

    case kPlanet_hasAtmosphere:
        return OOJSValueFromBOOL((planet != nullptr ? planet->hasAtmosphere() : false));

    case kPlanet_texture: {
        const std::optional<std::string> textureName = (planet != nullptr ? planet->textureFileName() : std::optional<std::string>());
        return OOJSValueFromPList(context, textureName.has_value() ? oo::PList(*textureName) : oo::PList());
    }

    case kPlanet_name: {
        const std::optional<std::string> name = (planet != nullptr ? planet->name() : std::optional<std::string>());
        return OOJSValueFromPList(context, name.has_value() ? oo::PList(*name) : oo::PList());
    }

    case kPlanet_orientation:
        // The C++ member the root's selector reached, qualified: the final overrider for a
        // planet (OOPlanetEntity has no subclass and does not override it), so the binding test stands in for
        // it; zero for none, as the message to nil.
        OOJS_RETURN_QUATERNION(planet != nullptr ? planet->Entity::normalOrientation() : Quaternion { });

    case kPlanet_rotationalVelocity:
        return JS_NewNumber(context, (planet != nullptr ? planet->rotationalVelocity() : 0.0));

    case kPlanet_terminatorThresholdVector:
        OOJS_RETURN_VECTOR((planet != nullptr ? planet->terminatorThresholdVector() : Vector { }));

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sPlanetProperties, OOJS_COUNT(sPlanetProperties));
        return OOJSNativeFailure(context);
    }

    OOJS_NATIVE_EXIT
}

static JSValue PlanetSetProperty(OOJS_SETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOPlanetEntity* planet = nil;
    std::optional<std::string> sValue;
    Quaternion qValue;
    Vector vValue;
    double dValue;
    oo::Ref<OOColor> colorForScript;

    if (!JSPlanetGetPlanetEntity(context, thisObj, &planet))
        return OOJSNativeFailure(context);

    switch (magic) {
    case kPlanet_airColor:
        colorForScript = OOColor::colorWithDescription(cxx_OOJSPListFromJSValue(context, value));
        if (colorForScript != nullptr || JS_IsNull(value)) {
            if (planet != nullptr)
                planet->setAirColor(colorForScript.get());
            return JS_UNDEFINED;
        }
        break;

    case kPlanet_airColorMixRatio:
        if (JS_ToFloat64(context, &dValue, value) == 0) {
            if (planet != nullptr)
                planet->setAirColorMixRatio(dValue);
            return JS_UNDEFINED;
        }
        break;

    case kPlanet_airDensity:
        if (JS_ToFloat64(context, &dValue, value) == 0) {
            if (planet != nullptr)
                planet->setAirDensity(dValue);
            return JS_UNDEFINED;
        }
        break;

    case kPlanet_illuminationColor:
        colorForScript = OOColor::colorWithDescription(cxx_OOJSPListFromJSValue(context, value));
        if (colorForScript != nullptr || JS_IsNull(value)) {
            if (planet != nullptr)
                planet->setIlluminationColor(colorForScript.get());
            return JS_UNDEFINED;
        }
        break;

    case kPlanet_name:
        sValue = cxx_OOStringFromJSValue(context, value);
        if (planet != nullptr)
            planet->setName(sValue);
        return JS_UNDEFINED;

    case kPlanet_texture: {
        bool OK = false;
        sValue = cxx_OOStringFromJSValue(context, value);


        OOJSPauseTimeLimiter();

        if (planet != nullptr) // was -isKindOfClass: of the facade class: false only for nil
        {
            if (!sValue.has_value()) {
                cxx_OOJSReportWarning(context, "Expected texture string. Value not set.");
            } else {
                OK = true;
            }
        }

        if (OK) {
            OK = (planet != nullptr ? planet->setUpPlanetFromTexture(sValue) : false); // has a value here
            if (!OK)
                cxx_OOJSReportWarning(context, "Cannot find texture \"%s\". Value not set.", sValue->c_str());
        }

        OOJSResumeTimeLimiter();

        return JS_UNDEFINED; // Even if !OK, no exception was raised.
    }

    case kPlanet_orientation:
        if (JSValueToQuaternion(context, value, &qValue)) {
            quaternion_normalize(&qValue);
            // The C++ member the root's selector reached, qualified: the final overrider
            // (OOPlanetEntity has no subclass), so the binding test stands in for it; nothing for none.
            if (planet != nullptr)
                planet->OOPlanetEntity::setOrientation(qValue);
            return JS_UNDEFINED;
        }
        break;

    case kPlanet_rotationalVelocity:
        if (JS_ToFloat64(context, &dValue, value) == 0) {
            if (planet != nullptr)
                planet->setRotationalVelocity(dValue);
            return JS_UNDEFINED;
        }
        break;

    case kPlanet_terminatorThresholdVector:
        if (JSValueToVector(context, value, &vValue)) {
            if (planet != nullptr)
                planet->setTerminatorThresholdVector(vValue);
            return JS_UNDEFINED;
        }
        break;

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sPlanetProperties, OOJS_COUNT(sPlanetProperties));
        return OOJSNativeFailure(context);
    }

    OOJSReportBadPropertyValue(context, thisObj, magic, sPlanetProperties, OOJS_COUNT(sPlanetProperties), value);
    return OOJSNativeFailure(context);

    OOJS_NATIVE_EXIT
}
