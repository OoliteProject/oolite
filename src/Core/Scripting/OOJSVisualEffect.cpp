/*
OOJSVisualEffect.m (QuickJS-ng)

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

#include "OOJSVisualEffect.h"

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "EntityOOJavaScriptExtensions.h"
#include "OOColor.h"
#include "OODescription.h"
#include "OOJSEntity.h"
#include "OOJSVector.h"
#include "OOJavaScriptEngine.h"
#include "OOMesh.h"
#include "OOScript.h"
#include "OOVisualEffectEntity.h"
#include "ResourceManager.h"
#include "oofnd/PList.hpp"
#include "oofnd/objc/OOAssert.h"

/*
        The class is a static JSClassDef registered with OOJSRegisterClass(),
        its properties a JSCFunctionListEntry table whose magic is the property
        ID, as in #768. OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are
        C++ try/catch and scope guards (OOJSEngineNativeWrappers.h). The
        category on OOVisualEffectEntity is free functions; restoreSubEntities()
        calls the function that holds -subEntitiesForScript's body.
*/

static JSClassID sVisualEffectClassID;

static bool JSVisualEffectGetVisualEffectEntity(
    JSContext* context, JSValueConst visualEffectObj,
    OOVisualEffectEntity** outEntity);

static JSValue VisualEffectGetProperty(OOJS_GETTER_ARGS);
static JSValue VisualEffectSetProperty(OOJS_SETTER_ARGS);

static JSValue VisualEffectRemove(OOJS_NATIVE_ARGS);
static JSValue VisualEffectGetShaders(OOJS_NATIVE_ARGS);
static JSValue VisualEffectSetShaders(OOJS_NATIVE_ARGS);
static JSValue VisualEffectGetMaterials(OOJS_NATIVE_ARGS);
static JSValue VisualEffectSetMaterials(OOJS_NATIVE_ARGS);
static JSValue VisualEffectScale(OOJS_NATIVE_ARGS);
static JSValue VisualEffectRestoreSubEntities(OOJS_NATIVE_ARGS);

static JSValue VisualEffectSetMaterialsInternal(OOJS_NATIVE_ARGS,
                                                OOVisualEffectEntity* thisEnt,
                                                bool fromShaders);

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

static JSClassDef sVisualEffectClass = {
    .class_name = "VisualEffect",
    .finalizer =
        OOJSCxxObjectWrapperFinalize,  // the slot holds an OOJSEntityHolder
};

namespace {

enum class VisualEffectProperty : std::int16_t {
  // Property IDs
  kBeaconCode,
  kBeaconLabel,
  kDataKey,
  kHullHeatLevel,
  kIsBreakPattern,
  kScaleX,
  kScaleY,
  kScaleZ,
  kScannerDisplayColor1,
  kScannerDisplayColor2,
  kScript,
  kScriptInfo,
  kShaderFloat1,
  kShaderFloat2,
  kShaderInt1,
  kShaderInt2,
  kShaderVector1,
  kShaderVector2,
  kSubEntities,
  kVectorForward,
  kVectorRight,
  kVectorUp
};

}  // namespace

static const JSCFunctionListEntry sVisualEffectProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RW("beaconCode", VisualEffectGetProperty,
                     VisualEffectSetProperty,
                     VisualEffectProperty::kBeaconCode),
    OOJS_PROPERTY_RW("beaconLabel", VisualEffectGetProperty,
                     VisualEffectSetProperty,
                     VisualEffectProperty::kBeaconLabel),
    OOJS_PROPERTY_RO("dataKey", VisualEffectGetProperty,
                     VisualEffectProperty::kDataKey),
    OOJS_PROPERTY_RW("isBreakPattern", VisualEffectGetProperty,
                     VisualEffectSetProperty,
                     VisualEffectProperty::kIsBreakPattern),
    OOJS_PROPERTY_RW("scaleX", VisualEffectGetProperty, VisualEffectSetProperty,
                     VisualEffectProperty::kScaleX),
    OOJS_PROPERTY_RW("scaleY", VisualEffectGetProperty, VisualEffectSetProperty,
                     VisualEffectProperty::kScaleY),
    OOJS_PROPERTY_RW("scaleZ", VisualEffectGetProperty, VisualEffectSetProperty,
                     VisualEffectProperty::kScaleZ),
    OOJS_PROPERTY_RW("scannerDisplayColor1", VisualEffectGetProperty,
                     VisualEffectSetProperty,
                     VisualEffectProperty::kScannerDisplayColor1),
    OOJS_PROPERTY_RW("scannerDisplayColor2", VisualEffectGetProperty,
                     VisualEffectSetProperty,
                     VisualEffectProperty::kScannerDisplayColor2),
    OOJS_PROPERTY_RW("hullHeatLevel", VisualEffectGetProperty,
                     VisualEffectSetProperty,
                     VisualEffectProperty::kHullHeatLevel),
    OOJS_PROPERTY_RO("script", VisualEffectGetProperty,
                     VisualEffectProperty::kScript),
    OOJS_PROPERTY_RO("scriptInfo", VisualEffectGetProperty,
                     VisualEffectProperty::kScriptInfo),
    OOJS_PROPERTY_RW("shaderFloat1", VisualEffectGetProperty,
                     VisualEffectSetProperty,
                     VisualEffectProperty::kShaderFloat1),
    OOJS_PROPERTY_RW("shaderFloat2", VisualEffectGetProperty,
                     VisualEffectSetProperty,
                     VisualEffectProperty::kShaderFloat2),
    OOJS_PROPERTY_RW("shaderInt1", VisualEffectGetProperty,
                     VisualEffectSetProperty,
                     VisualEffectProperty::kShaderInt1),
    OOJS_PROPERTY_RW("shaderInt2", VisualEffectGetProperty,
                     VisualEffectSetProperty,
                     VisualEffectProperty::kShaderInt2),
    OOJS_PROPERTY_RW("shaderVector1", VisualEffectGetProperty,
                     VisualEffectSetProperty,
                     VisualEffectProperty::kShaderVector1),
    OOJS_PROPERTY_RW("shaderVector2", VisualEffectGetProperty,
                     VisualEffectSetProperty,
                     VisualEffectProperty::kShaderVector2),
    OOJS_PROPERTY_RO("subEntities", VisualEffectGetProperty,
                     VisualEffectProperty::kSubEntities),
    OOJS_PROPERTY_RO("vectorForward", VisualEffectGetProperty,
                     VisualEffectProperty::kVectorForward),
    OOJS_PROPERTY_RO("vectorRight", VisualEffectGetProperty,
                     VisualEffectProperty::kVectorRight),
    OOJS_PROPERTY_RO("vectorUp", VisualEffectGetProperty,
                     VisualEffectProperty::kVectorUp),
};

static const JSCFunctionListEntry sVisualEffectMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("getMaterials", 0, VisualEffectGetMaterials),
    JS_CFUNC_DEF("getShaders", 0, VisualEffectGetShaders),
    JS_CFUNC_DEF("remove", 0, VisualEffectRemove),
    JS_CFUNC_DEF("restoreSubEntities", 0, VisualEffectRestoreSubEntities),
    JS_CFUNC_DEF("scale", 1, VisualEffectScale),
    JS_CFUNC_DEF("setMaterials", 1, VisualEffectSetMaterials),
    JS_CFUNC_DEF("setShaders", 2, VisualEffectSetShaders),
};

void InitOOJSVisualEffect(JSContext* context, JSValueConst global) {
  OOJSRegisterClass(&sVisualEffectClassID, &sVisualEffectClass);

  JSValue parentPrototype = JS_GetClassProto(context, JSEntityClassID());
  OOCAssert(JS_IsObject(parentPrototype),
            "Entity must be initialized before VisualEffect.");
  OOJSInitClass(context, global, sVisualEffectClassID, parentPrototype,
                OOJSUnconstructableConstruct, 0, sVisualEffectProperties,
                OOJS_COUNT(sVisualEffectProperties), sVisualEffectMethods,
                OOJS_COUNT(sVisualEffectMethods), nullptr, 0);
  JS_FreeValue(context, parentPrototype);

  OOJSRegisterObjectConverter(sVisualEffectClassID, OOJSEntityObjectConverter);
  OOJSRegisterSubclass(sVisualEffectClassID, JSEntityClassID());
}

JSClassID JSVisualEffectClassID() { return sVisualEffectClassID; }

static bool JSVisualEffectGetVisualEffectEntity(
    JSContext* context, JSValueConst visualEffectObj,
    OOVisualEffectEntity** outEntity) {
  OOJS_PROFILE_ENTER

  bool result;
  Entity* entity = nullptr;  // the slot holds the C++ entity

  if (outEntity == nullptr) return false;
  *outEntity = nullptr;

  result = OOJSEntityGetEntity(context, visualEffectObj, &entity);
  if (!result) return false;

  OOVisualEffectEntity* effect = oo::ToEffect(entity);
  if (effect == nullptr) return false;

  *outEntity = effect;
  return true;

  OOJS_PROFILE_EXIT
}

// The bodies the C++ effect's overrides call.
std::optional<std::string> OOJSVisualEffectJSClassName() {
  return std::string("VisualEffect");
}

bool OOJSVisualEffectIsVisibleToScripts() { return true; }

std::vector<oo::EntityHold> OOJSVisualEffectSubEntitiesForScript(
    OOVisualEffectEntity* effect) {
  const auto subs = effect->visualEffectSubEntityEnumerator();
  if (!subs.has_value()) return {};
  std::vector<oo::EntityHold> result;
  result.reserve(subs->size());
  for (const auto& sub : *subs) {
    result.emplace_back(sub.get());
  }
  return result;
}

static JSValue VisualEffectGetProperty(OOJS_GETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOVisualEffectEntity* entity = nullptr;
  oo::PList result;  // null maps to null

  if (!JSVisualEffectGetVisualEffectEntity(context, thisObj, &entity))
    return OOJSNativeFailure(context);
  if (entity == nullptr) {
    return JS_UNDEFINED;
  }

  switch (static_cast<VisualEffectProperty>(magic)) {
    using enum VisualEffectProperty;
    case kBeaconCode:
      if (const std::optional<std::string> text =
              (entity != nullptr ? entity->beaconCode()
                                 : std::optional<std::string>()))
        result = oo::PList(*text);
      break;

    case kBeaconLabel:
      if (const std::optional<std::string> text =
              (entity != nullptr ? entity->beaconLabel()
                                 : std::optional<std::string>()))
        result = oo::PList(*text);
      break;

    case kDataKey:
      if (const std::optional<std::string> text =
              (entity != nullptr ? entity->effectKey()
                                 : std::optional<std::string>()))
        result = oo::PList(*text);
      break;

    case kIsBreakPattern:
      return OOJSValueFromBOOL(
          (entity != nullptr ? entity->isBreakPattern() : false));

    case kVectorRight:
      OOJS_RETURN_VECTOR(
          (entity != nullptr ? entity->rightVector() : kZeroVector));

    case kVectorForward:
      OOJS_RETURN_VECTOR(
          (entity != nullptr ? entity->forwardVector() : kZeroVector));

    case kVectorUp:
      OOJS_RETURN_VECTOR(
          (entity != nullptr ? entity->upVector() : kZeroVector));

    case kScaleX:
      return JS_NewNumber(context,
                          (entity != nullptr ? entity->scaleX() : 0.0f));

    case kScaleY:
      return JS_NewNumber(context,
                          (entity != nullptr ? entity->scaleY() : 0.0f));

    case kScaleZ:
      return JS_NewNumber(context,
                          (entity != nullptr ? entity->scaleZ() : 0.0f));

    case kScannerDisplayColor1:
      result = NormalizedColorComponents(
          (entity != nullptr ? entity->scannerDisplayColor1()
                             : static_cast<OOColor*>(nullptr)));
      break;

    case kScannerDisplayColor2:
      result = NormalizedColorComponents(
          (entity != nullptr ? entity->scannerDisplayColor2()
                             : static_cast<OOColor*>(nullptr)));
      break;

    case kHullHeatLevel:
      return JS_NewNumber(context,
                          (entity != nullptr ? entity->hullHeatLevel() : 0.0f));

    case kShaderFloat1:
      return JS_NewNumber(context,
                          (entity != nullptr ? entity->shaderFloat1() : 0.0f));

    case kShaderFloat2:
      return JS_NewNumber(context,
                          (entity != nullptr ? entity->shaderFloat2() : 0.0f));

    case kShaderInt1:
      return JS_NewInt32(context,
                         (entity != nullptr ? entity->shaderInt1() : 0));

    case kShaderInt2:
      return JS_NewInt32(context,
                         (entity != nullptr ? entity->shaderInt2() : 0));

    case kShaderVector1:
      OOJS_RETURN_VECTOR(
          (entity != nullptr ? entity->shaderVector1() : kZeroVector));

    case kShaderVector2:
      OOJS_RETURN_VECTOR(
          (entity != nullptr ? entity->shaderVector2() : kZeroVector));

    case kSubEntities: {
      // nil before the first subentity (was [subEntitiesForScript] == nil)
      const auto subs =
          (entity != nullptr ? entity->visualEffectSubEntityEnumerator()
                             : std::optional<std::vector<oo::EntityHold>>());
      if (subs.has_value()) result = oo::EntityNodesFrom(*subs);
    } break;

    case kScript:
      result = OOScriptObjectNode((entity != nullptr
                                       ? entity->script()
                                       : static_cast<OOScript*>(nullptr)));
      break;

    case kScriptInfo:
      result = (entity != nullptr ? entity->scriptInfo()
                                  : oo::PList());  // empty dict, never null
      break;

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic,
                                    sVisualEffectProperties,
                                    OOJS_COUNT(sVisualEffectProperties));
      return OOJSNativeFailure(context);
  }

  return OOJSValueFromPList(context, result);

  OOJS_NATIVE_EXIT
}

static JSValue VisualEffectSetProperty(OOJS_SETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOVisualEffectEntity* entity = nullptr;
  int bValue;
  std::shared_ptr<OOColor> colorForScript;
  int32_t iValue;
  double fValue;
  Vector vValue;
  std::optional<std::string> sValue;

  if (!JSVisualEffectGetVisualEffectEntity(context, thisObj, &entity))
    return OOJSNativeFailure(context);
  if (entity == nullptr) return JS_UNDEFINED;

  switch (static_cast<VisualEffectProperty>(magic)) {
    using enum VisualEffectProperty;
    case kBeaconCode:
      sValue = cxx_OOStringFromJSValue(context, value);
      if (!sValue.has_value() || sValue->empty()) {
        if ((entity != nullptr ? entity->isBeacon() : false)) {
          if (UNIVERSE != nullptr) UNIVERSE->clearBeacon(entity);
          if ((PLAYER != nullptr ? PLAYER->nextBeaconEntity() : nullptr) ==
              entity)  // not virtual, so the binding test stands in for it
          {
            if (PLAYER != nullptr)
              PLAYER->PlayerEntity::setCompassMode(
                  OOCompassMode::kPlanet);  // qualified: the final overrider,
                                            // so the binding test stands in for
                                            // it
          }
        }
      } else {
        if ((entity != nullptr ? entity->isBeacon() : false)) {
          if (entity != nullptr) entity->setBeaconCode(sValue);
        } else  // Universe needs to update beacon lists in this case only
        {
          if (entity != nullptr) entity->setBeaconCode(sValue);
          if (UNIVERSE != nullptr) UNIVERSE->setNextBeacon(entity);
        }
      }
      return JS_UNDEFINED;
      break;

    case kBeaconLabel:
      sValue = cxx_OOStringFromJSValue(context, value);
      if (sValue.has_value()) {
        if (entity != nullptr) entity->setBeaconLabel(sValue);
        return JS_UNDEFINED;
      }
      break;

    case kIsBreakPattern:
      if ((bValue = JS_ToBool(context, value)) >= 0) {
        if (entity != nullptr) entity->setIsBreakPattern(bValue);
        return JS_UNDEFINED;
      }
      break;

    case kScannerDisplayColor1:
      colorForScript = OOColor::colorWithDescription(
          cxx_OOJSPListFromJSValue(context, value));
      if (colorForScript != nullptr || JS_IsNull(value)) {
        if (entity != nullptr)
          entity->setScannerDisplayColor1(colorForScript.get());
        return JS_UNDEFINED;
      }
      break;

    case kScannerDisplayColor2:
      colorForScript = OOColor::colorWithDescription(
          cxx_OOJSPListFromJSValue(context, value));
      if (colorForScript != nullptr || JS_IsNull(value)) {
        if (entity != nullptr)
          entity->setScannerDisplayColor2(colorForScript.get());
        return JS_UNDEFINED;
      }
      break;

    case kScaleX:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        if (fValue > 0.0) {
          if (entity != nullptr) entity->setScaleX(fValue);
          return JS_UNDEFINED;
        }
      }
      break;

    case kScaleY:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        if (fValue > 0.0) {
          if (entity != nullptr) entity->setScaleY(fValue);
          return JS_UNDEFINED;
        }
      }
      break;

    case kScaleZ:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        if (fValue > 0.0) {
          if (entity != nullptr) entity->setScaleZ(fValue);
          return JS_UNDEFINED;
        }
      }
      break;

    case kHullHeatLevel:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        if (entity != nullptr) entity->setHullHeatLevel(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kShaderFloat1:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        if (entity != nullptr) entity->setShaderFloat1(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kShaderFloat2:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        if (entity != nullptr) entity->setShaderFloat2(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kShaderInt1:
      if (OOJSValueToInt32(context, value, &iValue)) {
        if (entity != nullptr) entity->setShaderInt1(iValue);
        return JS_UNDEFINED;
      }
      break;

    case kShaderInt2:
      if (OOJSValueToInt32(context, value, &iValue)) {
        if (entity != nullptr) entity->setShaderInt2(iValue);
        return JS_UNDEFINED;
      }
      break;

    case kShaderVector1:
      if (JSValueToVector(context, value, &vValue)) {
        if (entity != nullptr) entity->setShaderVector1(vValue);
        return JS_UNDEFINED;
      }
      break;

    case kShaderVector2:
      if (JSValueToVector(context, value, &vValue)) {
        if (entity != nullptr) entity->setShaderVector2(vValue);
        return JS_UNDEFINED;
      }
      break;

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic,
                                    sVisualEffectProperties,
                                    OOJS_COUNT(sVisualEffectProperties));
      return OOJSNativeFailure(context);
  }

  OOJSReportBadPropertyValue(context, thisObj, magic, sVisualEffectProperties,
                             OOJS_COUNT(sVisualEffectProperties), value);
  return OOJSNativeFailure(context);

  OOJS_NATIVE_EXIT
}

// *** Methods ***

// The effect's mesh's materials and shaders; null for no mesh, as a message to
// nil answered.
namespace {
oo::PList MeshMaterials(OOVisualEffectEntity* effect) {
  OOMesh* mesh =
      (effect != nullptr ? effect->mesh() : static_cast<OOMesh*>(nullptr));
  return (mesh != nullptr) ? mesh->getMaterials() : oo::PList();
}

oo::PList MeshShaders(OOVisualEffectEntity* effect) {
  OOMesh* mesh =
      (effect != nullptr ? effect->mesh() : static_cast<OOMesh*>(nullptr));
  return (mesh != nullptr) ? mesh->shaders() : oo::PList();
}
}  // namespace

#define GET_THIS_EFFECT(THISENT)                                            \
  do {                                                                      \
    if (EXPECT_NOT(!JSVisualEffectGetVisualEffectEntity(context, OOJS_THIS, \
                                                        &(THISENT))))       \
      return OOJSNativeFailure(context); /* Exception */                    \
    if (OOIsStaleEntity(THISENT)) OOJS_RETURN_VOID;                         \
  } while (0)

static JSValue VisualEffectRemove(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOVisualEffectEntity* thisEnt = nullptr;
  GET_THIS_EFFECT(thisEnt);

  if ((thisEnt != nullptr ? thisEnt->getIsSubEntity() : false)) {
    OOVisualEffectEntity* parent = oo::ToEffect(oo::LiveOwner(thisEnt));
    if (parent != nullptr) parent->removeSubEntity(thisEnt);
  } else {
    if (thisEnt != nullptr) thisEnt->remove();
  }

  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// getMaterials()
static JSValue VisualEffectGetMaterials(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  oo::PList result;
  OOVisualEffectEntity* thisEnt = nullptr;

  GET_THIS_EFFECT(thisEnt);

  result = MeshMaterials(thisEnt);
  if (result.isNull())
    result = oo::PList(oo::PList::Dict{});  // an empty dictionary
  OOJS_RETURN_PLIST(result);

  OOJS_PROFILE_EXIT
}

// getShaders()
static JSValue VisualEffectGetShaders(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  oo::PList result;
  OOVisualEffectEntity* thisEnt = nullptr;

  GET_THIS_EFFECT(thisEnt);

  result = MeshShaders(thisEnt);
  if (result.isNull())
    result = oo::PList(oo::PList::Dict{});  // an empty dictionary
  OOJS_RETURN_PLIST(result);

  OOJS_PROFILE_EXIT
}

// setMaterials(params: dict, [shaders: dict])  // sets materials dictionary.
// Optional parameter sets the shaders dictionary too.
static JSValue VisualEffectSetMaterials(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOVisualEffectEntity* thisEnt = nullptr;

  if (argc < 1) {
    cxx_OOJSReportBadArguments(context, "VisualEffect", "setMaterials", 0,
                               OOJS_ARGV, std::nullopt, "parameter object");
    return OOJSNativeFailure(context);
  }

  GET_THIS_EFFECT(thisEnt);

  return VisualEffectSetMaterialsInternal(context, OOJS_THIS, argc, OOJS_ARGV,
                                          thisEnt, false);

  OOJS_NATIVE_EXIT
}

// setShaders(params: dict)
static JSValue VisualEffectSetShaders(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOVisualEffectEntity* thisEnt = nullptr;

  GET_THIS_EFFECT(thisEnt);

  if (argc < 1) {
    cxx_OOJSReportBadArguments(context, "VisualEffect", "setShaders", 0,
                               OOJS_ARGV, std::nullopt, "parameter object");
    return OOJSNativeFailure(context);
  }

  if (JS_IsNull(OOJS_ARGV[0]) ||
      (!JS_IsNull(OOJS_ARGV[0]) && !JS_IsObject(OOJS_ARGV[0]))) {
    // EMMSTRAN: JS_ValueToObject() and normal error handling here.
    cxx_OOJSReportWarning(
        context, "VisualEffect.%s: expected %s instead of '%s'.", "setShaders",
        "object",
        cxx_OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[0])
            .value_or("(null)")
            .c_str());
    OOJS_RETURN_BOOL(false);
  }

  /*	SpiderMonkey's version overwrote OOJS_ARGV[1] in place. QuickJS argv
          belongs to the caller (and its values are reference counted), so pass
          a borrowed copy instead.
  */
  JSValueConst shaderArgv[2] = {OOJS_ARGV[0], OOJS_ARGV[0]};
  return VisualEffectSetMaterialsInternal(context, OOJS_THIS, argc, shaderArgv,
                                          thisEnt, true);

  OOJS_NATIVE_EXIT
}

/* **  helper functions ** */

static JSValue VisualEffectSetMaterialsInternal(OOJS_NATIVE_ARGS,
                                                OOVisualEffectEntity* thisEnt,
                                                bool fromShaders) {
  OOJS_PROFILE_ENTER

  JSValueConst params = JS_UNDEFINED;
  oo::PList materials;
  oo::PList shaders;
  bool withShaders = false;
  bool success = false;

  GET_THIS_EFFECT(thisEnt);

  if (JS_IsNull(OOJS_ARGV[0]) ||
      (!JS_IsNull(OOJS_ARGV[0]) && !JS_IsObject(OOJS_ARGV[0]))) {
    cxx_OOJSReportWarning(
        context, "VisualEffect.%s: expected %s instead of '%s'.",
        "setMaterials", "object",
        cxx_OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[0])
            .value_or("(null)")
            .c_str());
    OOJS_RETURN_BOOL(false);
  }

  if (argc > 1) {
    withShaders = true;
    if (JS_IsNull(OOJS_ARGV[1]) ||
        (!JS_IsNull(OOJS_ARGV[1]) && !JS_IsObject(OOJS_ARGV[1]))) {
      cxx_OOJSReportWarning(
          context, "VisualEffect.%s: expected %s instead of '%s'.",
          "setMaterials", "object as second parameter",
          cxx_OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[1])
              .value_or("(null)")
              .c_str());
      withShaders = false;
    }
  }

  if (fromShaders) {
    materials = MeshMaterials(thisEnt);
    params = OOJS_ARGV[0];
    shaders = cxx_OOJSPListFromJSObject(context, params);
  } else {
    params = OOJS_ARGV[0];
    materials = cxx_OOJSPListFromJSObject(context, params);
    if (withShaders) {
      params = OOJS_ARGV[1];
      shaders = cxx_OOJSPListFromJSObject(context, params);
    } else {
      shaders = MeshShaders(thisEnt);
    }
  }

  OOJS_BEGIN_FULL_NATIVE(context)
  const oo::PList effectDict =
      (thisEnt != nullptr ? thisEnt->effectInfoDictionary() : oo::PList());
  // -oo_stringForKey: / -oo_dictionaryForKey: as the mesh call read them: nil
  // unless a string (or a number's text) / a dictionary.
  const oo::PList* model = effectDict.get<oo::PList>("model");
  std::optional<std::string> modelName;
  if (model != nullptr && (model->isString() || model->isNumber()))
    modelName = effectDict.get<std::string>("model");
  // The ship-prefix-macros default as the mesh call read it: a dictionary, else
  // nothing.
  const oo::PList materialDefaults = ResourceManager::materialDefaults();
  const oo::PList* macros =
      materialDefaults.get<oo::PList::Dict>("ship-prefix-macros");
  const oo::PList shaderMacros = (macros != nullptr) ? *macros : oo::PList();

  // First we test to see if we can create the mesh.
  const std::shared_ptr<OOMesh> mesh = OOMesh::meshWithName(
      modelName.value_or(std::string()), std::nullopt, materials, shaders,
      effectDict.get<bool>("smooth", false), shaderMacros, thisEnt);

  if (mesh != nullptr) {
    if (thisEnt != nullptr) thisEnt->setMesh(mesh.get());
    success = true;
  }
  OOJS_END_FULL_NATIVE

  OOJS_RETURN_BOOL(success);

  OOJS_PROFILE_EXIT
}

static JSValue VisualEffectScale(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOVisualEffectEntity* thisEnt = nullptr;
  GET_THIS_EFFECT(thisEnt);
  double scale = 0.0;
  bool gotScale;

  if (argc < 1) {
    cxx_OOJSReportBadArguments(context, "VisualEffect", "scale", argc,
                               OOJS_ARGV, std::nullopt, "scale factor needed");
    return OOJSNativeFailure(context);
  }

  gotScale = JS_ToFloat64(context, &scale, OOJS_ARGV[0]) == 0;
  if (EXPECT_NOT(scale <= 0.0 || !gotScale)) {
    cxx_OOJSReportBadArguments(context, "VisualEffect", "scale", argc,
                               OOJS_ARGV, std::nullopt,
                               "scale factor must be positive");
    return OOJSNativeFailure(context);
  }

  // set all three scales
  if (thisEnt != nullptr) thisEnt->setScaleX(scale);
  if (thisEnt != nullptr) thisEnt->setScaleY(scale);
  if (thisEnt != nullptr) thisEnt->setScaleZ(scale);

  return JS_UNDEFINED;
  OOJS_NATIVE_EXIT
}

// restoreSubEntities(): boolean
static JSValue VisualEffectRestoreSubEntities(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOVisualEffectEntity* thisEnt = nullptr;
  std::size_t numSubEntitiesRestored = 0U;

  GET_THIS_EFFECT(thisEnt);

  // -subEntitiesForScript, called as the function that holds its body.
  std::size_t subCount = OOJSVisualEffectSubEntitiesForScript(thisEnt).size();

  if (thisEnt != nullptr) thisEnt->clearSubEntities();
  if (thisEnt != nullptr) thisEnt->setUpSubEntities();

  if (OOJSVisualEffectSubEntitiesForScript(thisEnt).size() - subCount > 0)
    numSubEntitiesRestored =
        OOJSVisualEffectSubEntitiesForScript(thisEnt).size() - subCount;

  OOJS_RETURN_BOOL(numSubEntitiesRestored > 0);

  OOJS_NATIVE_EXIT
}
