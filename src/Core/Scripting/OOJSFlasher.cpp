/*
OOJSFlasher.m (QuickJS-ng)

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

#include "OOJSFlasher.h"

#include "EntityOOJavaScriptExtensions.h"
#include "OOColor.h"
#include "OOFlasherEntity.h"
#include "OOJSEntity.h"
#include "OOJavaScriptEngine.h"
#include "OOVisualEffectEntity.h"
#include "ShipEntity.h"

static JSClassID sFlasherClassID;

static bool JSFlasherGetFlasherEntity(JSContext* context, JSValueConst jsobj,
                                      OOFlasherEntity** outEntity);

static JSValue FlasherGetProperty(OOJS_GETTER_ARGS);
static JSValue FlasherSetProperty(OOJS_SETTER_ARGS);

static JSValue FlasherRemove(OOJS_NATIVE_ARGS);

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

static JSClassDef sFlasherClass = {
    .class_name = "Flasher",
    .finalizer =
        OOJSCxxObjectWrapperFinalize,  // the slot holds an OOJSEntityHolder
};

namespace {

enum class FlasherProperty : std::int16_t {
  // Property IDs
  kActive,
  kColor,
  kFraction,
  kFrequency,
  kPhase,
  kSize
};

}  // namespace

static const JSCFunctionListEntry sFlasherProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RW("active", FlasherGetProperty, FlasherSetProperty,
                     FlasherProperty::kActive),
    OOJS_PROPERTY_RW("color", FlasherGetProperty, FlasherSetProperty,
                     FlasherProperty::kColor),
    OOJS_PROPERTY_RW("fraction", FlasherGetProperty, FlasherSetProperty,
                     FlasherProperty::kFraction),
    OOJS_PROPERTY_RW("frequency", FlasherGetProperty, FlasherSetProperty,
                     FlasherProperty::kFrequency),
    OOJS_PROPERTY_RW("phase", FlasherGetProperty, FlasherSetProperty,
                     FlasherProperty::kPhase),
    OOJS_PROPERTY_RW("size", FlasherGetProperty, FlasherSetProperty,
                     FlasherProperty::kSize),
};

static const JSCFunctionListEntry sFlasherMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("remove", 0, FlasherRemove),
};

void InitOOJSFlasher(JSContext* context, JSValueConst global) {
  OOJSRegisterClass(&sFlasherClassID, &sFlasherClass);

  JSValue parentPrototype = JS_GetClassProto(context, JSEntityClassID());
  OOCAssert(JS_IsObject(parentPrototype),
            "Entity must be initialized before Flasher.");
  OOJSInitClass(context, global, sFlasherClassID, parentPrototype,
                OOJSUnconstructableConstruct, 0, sFlasherProperties,
                OOJS_COUNT(sFlasherProperties), sFlasherMethods,
                OOJS_COUNT(sFlasherMethods), nullptr, 0);
  JS_FreeValue(context, parentPrototype);

  OOJSRegisterObjectConverter(sFlasherClassID, OOJSEntityObjectConverter);
  OOJSRegisterSubclass(sFlasherClassID, JSEntityClassID());
}

JSClassID JSFlasherClassID() { return sFlasherClassID; }

static bool JSFlasherGetFlasherEntity(JSContext* context, JSValueConst jsobj,
                                      OOFlasherEntity** outEntity) {
  OOJS_PROFILE_ENTER

  bool result;
  Entity* entity = nullptr;  // the slot holds the C++ entity

  if (outEntity == nullptr) return false;
  *outEntity = nullptr;

  result = OOJSEntityGetEntity(context, jsobj, &entity);
  if (!result) return false;

  // A flasher is an OOFlasherEntity.
  OOFlasherEntity* flasher = dynamic_cast<OOFlasherEntity*>(entity);
  if (flasher == nullptr) return false;

  *outEntity = flasher;
  return true;

  OOJS_PROFILE_EXIT
}

// The bodies of OOFlasherEntity (OOJavaScriptExtensions), which the C++ class's
// overrides of the root's JS members call.
std::optional<std::string> OOJSFlasherJSClassName() {
  return std::string("Flasher");
}

bool OOJSFlasherIsVisibleToScripts() { return true; }

static JSValue FlasherGetProperty(OOJS_GETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOFlasherEntity* entity = nullptr;
  oo::PList result;  // null: nil

  if (!JSFlasherGetFlasherEntity(context, thisObj, &entity))
    return OOJSNativeFailure(context);
  if (entity == nullptr) {
    return JS_UNDEFINED;
  }

  switch (static_cast<FlasherProperty>(magic)) {
    using enum FlasherProperty;
    case kActive:
      return OOJSValueFromBOOL(entity->isActive());

    case kColor:
      result = NormalizedColorComponents(entity->color().get());
      break;

    case kFrequency:
      return JS_NewNumber(context, entity->frequency());

    case kFraction:
      return JS_NewNumber(context, entity->fraction());

    case kPhase:
      return JS_NewNumber(context, entity->phase());

    case kSize:
      return JS_NewNumber(context, entity->diameter());

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic, sFlasherProperties,
                                    OOJS_COUNT(sFlasherProperties));
      return OOJSNativeFailure(context);
  }

  return OOJSValueFromPList(context, result);

  OOJS_NATIVE_EXIT
}

static JSValue FlasherSetProperty(OOJS_SETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOFlasherEntity* entity = nullptr;
  double fValue;
  int bValue;
  std::shared_ptr<OOColor> colorForScript;

  if (!JSFlasherGetFlasherEntity(context, thisObj, &entity))
    return OOJSNativeFailure(context);
  if (entity == nullptr) return JS_UNDEFINED;

  switch (static_cast<FlasherProperty>(magic)) {
    using enum FlasherProperty;
    case kActive:
      if ((bValue = JS_ToBool(context, value)) >= 0) {
        entity->setActive(static_cast<bool>(bValue));
        return JS_UNDEFINED;
      }
      break;

    case kColor:
      colorForScript =
          OOColor::colorWithDescription(OOJSPListFromJSValue(context, value));
      if (colorForScript != nullptr || JS_IsNull(value)) {
        entity->setColor(colorForScript.get());
        return JS_UNDEFINED;
      }
      break;

    case kFrequency:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        if (fValue >= 0.0) {
          entity->setFrequency(fValue);
          return JS_UNDEFINED;
        }
      }
      break;

    case kFraction:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        if (fValue > 0.0 && fValue <= 1.0) {
          entity->setFraction(fValue);
          return JS_UNDEFINED;
        }
      }
      break;

    case kPhase:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        entity->setPhase(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kSize:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        if (fValue > 0.0) {
          entity->setDiameter(fValue);
          return JS_UNDEFINED;
        }
      }
      break;

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic, sFlasherProperties,
                                    OOJS_COUNT(sFlasherProperties));
      return OOJSNativeFailure(context);
  }

  OOJSReportBadPropertyValue(context, thisObj, magic, sFlasherProperties,
                             OOJS_COUNT(sFlasherProperties), value);
  return OOJSNativeFailure(context);

  OOJS_NATIVE_EXIT
}

// *** Methods ***

#define GET_THIS_FLASHER(THISENT)                                           \
  do {                                                                      \
    if (EXPECT_NOT(                                                         \
            !JSFlasherGetFlasherEntity(context, OOJS_THIS, &(THISENT))))    \
      return OOJSNativeFailure(context);            /* Exception */         \
    if (OOIsStaleEntity(THISENT)) OOJS_RETURN_VOID; /* the C++ flasher's */ \
  } while (0)

static JSValue FlasherRemove(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOFlasherEntity* thisEnt = nullptr;
  GET_THIS_FLASHER(thisEnt);

  Entity* parent = thisEnt->owner();  // the C++ member
  if (oo::EntityIsShip(parent)) {
    if (oo::ToShip(parent) != nullptr)
      oo::ToShip(parent)->removeFlasher(thisEnt);
  } else {
    if (OOVisualEffectEntity* effect = oo::ToEffect(parent))
      effect->removeSubEntity(thisEnt);  // the C++ flasher
  }

  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}
