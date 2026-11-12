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

#include "OOJSPlanet.h"

#include "EntityOOJavaScriptExtensions.h"
#include "OOJSEntity.h"
#include "OOJSQuaternion.h"
#include "OOJSVector.h"
#include "OOJavaScriptEngine.h"
#include "OOPlanetEntity.h"
#include "oofnd/objc/OOAssert.h"

static JSClassID sPlanetClassID;

static JSValue PlanetGetProperty(OOJS_GETTER_ARGS);
static JSValue PlanetSetProperty(OOJS_SETTER_ARGS);

namespace {

// A colour's components as its -normalizedArray gave them to JavaScript:
// floats, null for no colour.
oo::PList NormalizedColorComponents(OOColor* color) {
  if (color == nullptr) return oo::PList();
  oo::PList::Array components;
  for (float component : color->normalizedArray())
    components.push_back(oo::PList::singleReal(component));
  return oo::PList(std::move(components));
}

}  // namespace

static JSClassDef sPlanetClass = {
    .class_name = "Planet",
    .finalizer =
        OOJSCxxObjectWrapperFinalize,  // the slot holds an OOJSEntityHolder
};

namespace {

enum class PlanetProperty : std::int16_t {
  // Property IDs
  kAirColor,          // air color, read/write
  kAirColorMixRatio,  // air color mix ratio, float, read/write
  kAirDensity,        // air density, float, read/write
  kHasAtmosphere,
  kIlluminationColor,   // illumination color, read/write
  kIsMainPlanet,        // Is [UNIVERSE planet], boolean, read-only
  kName,                // Name of planet, string, read/write
  kRadius,              // Radius of planet in metres, read-only
  kTexture,             // Planet texture read / write
  kOrientation,         // orientation, quaternion, read/write
  kRotationalVelocity,  // read/write
  kTerminatorThresholdVector,
};

}  // namespace

static const JSCFunctionListEntry sPlanetProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RW("airColor", PlanetGetProperty, PlanetSetProperty,
                     PlanetProperty::kAirColor),
    OOJS_PROPERTY_RW("airColorMixRatio", PlanetGetProperty, PlanetSetProperty,
                     PlanetProperty::kAirColorMixRatio),
    OOJS_PROPERTY_RW("airDensity", PlanetGetProperty, PlanetSetProperty,
                     PlanetProperty::kAirDensity),
    OOJS_PROPERTY_RO("hasAtmosphere", PlanetGetProperty,
                     PlanetProperty::kHasAtmosphere),
    OOJS_PROPERTY_RW("illuminationColor", PlanetGetProperty, PlanetSetProperty,
                     PlanetProperty::kIlluminationColor),
    OOJS_PROPERTY_RO("isMainPlanet", PlanetGetProperty,
                     PlanetProperty::kIsMainPlanet),
    OOJS_PROPERTY_RW("name", PlanetGetProperty, PlanetSetProperty,
                     PlanetProperty::kName),
    OOJS_PROPERTY_RO("radius", PlanetGetProperty, PlanetProperty::kRadius),
    OOJS_PROPERTY_RW("rotationalVelocity", PlanetGetProperty, PlanetSetProperty,
                     PlanetProperty::kRotationalVelocity),
    OOJS_PROPERTY_RW("texture", PlanetGetProperty, PlanetSetProperty,
                     PlanetProperty::kTexture),
    OOJS_PROPERTY_RW(
        "orientation", PlanetGetProperty, PlanetSetProperty,
        PlanetProperty::kOrientation),  // Not documented since it's
                                        // inherited from Entity
    OOJS_PROPERTY_RW("terminatorThresholdVector", PlanetGetProperty,
                     PlanetSetProperty,
                     PlanetProperty::kTerminatorThresholdVector),
};

// The getter checks the JS class and answers the C++ planet (the slot holds the
// C++ entity, read by OOJSEntityGetEntityOfClass for the Planet class); null
// for a stale entity.
static bool JSPlanetGetPlanetEntity(JSContext* context, JSValueConst inObject,
                                    OOPlanetEntity** outObject) {
  Entity* entity = nullptr;
  if (!OOJSEntityGetEntityOfClass(context, inObject, sPlanetClassID, &entity))
    return false;
  *outObject = dynamic_cast<OOPlanetEntity*>(entity);
  return true;
}

void InitOOJSPlanet(JSContext* context, JSValueConst global) {
  OOJSRegisterClass(&sPlanetClassID, &sPlanetClass);

  JSValue parentPrototype = JS_GetClassProto(context, JSEntityClassID());
  OOCAssert(JS_IsObject(parentPrototype),
            "Entity must be initialized before Planet.");
  OOJSInitClass(context, global, sPlanetClassID, parentPrototype,
                OOJSUnconstructableConstruct, 0, sPlanetProperties,
                OOJS_COUNT(sPlanetProperties), nullptr, 0, nullptr, 0);
  JS_FreeValue(context, parentPrototype);

  OOJSRegisterObjectConverter(sPlanetClassID, OOJSEntityObjectConverter);
  OOJSRegisterSubclass(sPlanetClassID, JSEntityClassID());
}

JSClassID JSPlanetClassID() { return sPlanetClassID; }

// The bodies of OOPlanetEntity (OOJavaScriptExtensions), called by the C++
// planet's overrides.
bool OOJSPlanetIsVisibleToScripts(OOPlanetEntity* planet) {
  OOStellarBodyType type =
      (planet != nullptr ? planet->planetType() : (OOStellarBodyType)0);
  return type == OOStellarBodyType::kNormalPlanet ||
         type == OOStellarBodyType::kMoon;
}

std::optional<std::string> OOJSPlanetJSClassName(OOPlanetEntity* planet) {
  switch ((planet != nullptr ? planet->planetType() : (OOStellarBodyType)0)) {
    case OOStellarBodyType::kNormalPlanet:
      return std::string("Planet");
    case OOStellarBodyType::kMoon:
      return std::string("Moon");
    default:
      return std::string("Unknown");
  }
}

static JSValue PlanetGetProperty(OOJS_GETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOPlanetEntity* planet = nullptr;
  if (!JSPlanetGetPlanetEntity(context, thisObj, &planet))
    return OOJSNativeFailure(context);

  switch (static_cast<PlanetProperty>(magic)) {
    using enum PlanetProperty;
    case kAirColor:
      return OOJSValueFromPList(
          context,
          NormalizedColorComponents(
              (planet != nullptr ? planet->airColor() : (OOColor*)nullptr)));

    case kAirColorMixRatio:
      return JS_NewNumber(
          context, (planet != nullptr ? planet->airColorMixRatio() : 0.0f));

    case kAirDensity:
      return JS_NewNumber(context,
                          (planet != nullptr ? planet->airDensity() : 0.0f));

    case kIlluminationColor:
      return OOJSValueFromPList(
          context, NormalizedColorComponents((planet != nullptr
                                                  ? planet->illuminationColor()
                                                  : (OOColor*)nullptr)));

    case kIsMainPlanet:
      return OOJSValueFromBOOL(
          planet == (UNIVERSE != nullptr ? UNIVERSE->planet() : nullptr));

    case kRadius:
      return JS_NewNumber(context,
                          (planet != nullptr ? planet->radius() : 0.0));

    case kHasAtmosphere:
      return OOJSValueFromBOOL(
          (planet != nullptr ? planet->hasAtmosphere() : false));

    case kTexture: {
      const std::optional<std::string> textureName =
          (planet != nullptr ? planet->textureFileName()
                             : std::optional<std::string>());
      return OOJSValueFromPList(context, textureName.has_value()
                                             ? oo::PList(*textureName)
                                             : oo::PList());
    }

    case kName: {
      const std::optional<std::string> name =
          (planet != nullptr ? planet->name() : std::optional<std::string>());
      return OOJSValueFromPList(
          context, name.has_value() ? oo::PList(*name) : oo::PList());
    }

    case kOrientation:
      // The C++ member, qualified: the final overrider for a planet
      // (OOPlanetEntity has no subclass and does not override it), so the
      // binding test stands in for it; zero for none.
      OOJS_RETURN_QUATERNION(planet != nullptr
                                 ? planet->Entity::normalOrientation()
                                 : Quaternion{});

    case kRotationalVelocity:
      return JS_NewNumber(
          context, (planet != nullptr ? planet->rotationalVelocity() : 0.0));

    case kTerminatorThresholdVector:
      OOJS_RETURN_VECTOR(
          (planet != nullptr ? planet->terminatorThresholdVector() : Vector{}));

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic, sPlanetProperties,
                                    OOJS_COUNT(sPlanetProperties));
      return OOJSNativeFailure(context);
  }

  OOJS_NATIVE_EXIT
}

static JSValue PlanetSetProperty(OOJS_SETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOPlanetEntity* planet = nullptr;
  std::optional<std::string> sValue;
  Quaternion qValue;
  Vector vValue;
  double dValue;
  oo::Ref<OOColor> colorForScript;

  if (!JSPlanetGetPlanetEntity(context, thisObj, &planet))
    return OOJSNativeFailure(context);

  switch (static_cast<PlanetProperty>(magic)) {
    using enum PlanetProperty;
    case kAirColor:
      colorForScript = OOColor::colorWithDescription(
          cxx_OOJSPListFromJSValue(context, value));
      if (colorForScript != nullptr || JS_IsNull(value)) {
        if (planet != nullptr) planet->setAirColor(colorForScript.get());
        return JS_UNDEFINED;
      }
      break;

    case kAirColorMixRatio:
      if (JS_ToFloat64(context, &dValue, value) == 0) {
        if (planet != nullptr) planet->setAirColorMixRatio(dValue);
        return JS_UNDEFINED;
      }
      break;

    case kAirDensity:
      if (JS_ToFloat64(context, &dValue, value) == 0) {
        if (planet != nullptr) planet->setAirDensity(dValue);
        return JS_UNDEFINED;
      }
      break;

    case kIlluminationColor:
      colorForScript = OOColor::colorWithDescription(
          cxx_OOJSPListFromJSValue(context, value));
      if (colorForScript != nullptr || JS_IsNull(value)) {
        if (planet != nullptr)
          planet->setIlluminationColor(colorForScript.get());
        return JS_UNDEFINED;
      }
      break;

    case kName:
      sValue = cxx_OOStringFromJSValue(context, value);
      if (planet != nullptr) planet->setName(sValue);
      return JS_UNDEFINED;

    case kTexture: {
      bool OK = false;
      sValue = cxx_OOStringFromJSValue(context, value);

      OOJSPauseTimeLimiter();

      if (planet != nullptr)  // false only for null
      {
        if (!sValue.has_value()) {
          cxx_OOJSReportWarning(context,
                                "Expected texture string. Value not set.");
        } else {
          OK = true;
        }
      }

      if (OK) {
        OK = (planet != nullptr ? planet->setUpPlanetFromTexture(sValue)
                                : false);  // has a value here
        if (!OK)
          cxx_OOJSReportWarning(context,
                                "Cannot find texture \"%s\". Value not set.",
                                sValue->c_str());
      }

      OOJSResumeTimeLimiter();

      return JS_UNDEFINED;  // Even if !OK, no exception was raised.
    }

    case kOrientation:
      if (JSValueToQuaternion(context, value, &qValue)) {
        quaternion_normalize(&qValue);
        // The C++ member, qualified: the final overrider (OOPlanetEntity has no
        // subclass), so the binding test stands in for it; nothing for none.
        if (planet != nullptr) planet->OOPlanetEntity::setOrientation(qValue);
        return JS_UNDEFINED;
      }
      break;

    case kRotationalVelocity:
      if (JS_ToFloat64(context, &dValue, value) == 0) {
        if (planet != nullptr) planet->setRotationalVelocity(dValue);
        return JS_UNDEFINED;
      }
      break;

    case kTerminatorThresholdVector:
      if (JSValueToVector(context, value, &vValue)) {
        if (planet != nullptr) planet->setTerminatorThresholdVector(vValue);
        return JS_UNDEFINED;
      }
      break;

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic, sPlanetProperties,
                                    OOJS_COUNT(sPlanetProperties));
      return OOJSNativeFailure(context);
  }

  OOJSReportBadPropertyValue(context, thisObj, magic, sPlanetProperties,
                             OOJS_COUNT(sPlanetProperties), value);
  return OOJSNativeFailure(context);

  OOJS_NATIVE_EXIT
}
