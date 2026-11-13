/*

OOJSManifest.m

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

#include "OOJSManifest.h"

#include "OOCommodities.h"
#include "OOCommodityMarket.h"
#include "OOIsNumberLiteral.h"
#include "OOJSPlayer.h"
#include "OOJSPlayerShip.h"
#include "OOJavaScriptEngine.h"
#include "PlayerEntity.h"
#include "PlayerEntityContracts.h"
#include "PlayerEntityScriptMethods.h"
#include "Universe.h"

static JSValue ManifestComment(OOJS_NATIVE_ARGS);
static JSValue ManifestSetComment(OOJS_NATIVE_ARGS);
static JSValue ManifestShortComment(OOJS_NATIVE_ARGS);
static JSValue ManifestSetShortComment(OOJS_NATIVE_ARGS);

static JSValue ManifestGetProperty(OOJS_GETTER_ARGS);

/*	SpiderMonkey called the Manifest class's get, set and delete hooks for
        every property; string-named properties map to cargo quantities. QuickJS
        has no such hooks, so the class's exotic methods provide the same view:
        each defined commodity appears as an own property whose value is the
        cargo quantity, assignments to any other name set the cargo quantity as
        before and are also stored as an ordinary property (as the SpiderMonkey
        object kept them in a slot), and delete sets the quantity to undefined,
        which is an error, as before. The tinyid property list stays on the
        prototype, and is reported as an own property as SpiderMonkey did for
        shared permanent properties (commodities are not enumerated, as before).
*/
static int ManifestGetOwnProperty(JSContext* context,
                                  JSPropertyDescriptor* desc,
                                  JSValueConst object, JSAtom propID);
static int ManifestDeleteProperty(JSContext* context, JSValueConst object,
                                  JSAtom propID);
static int ManifestSetPropertyExotic(JSContext* context, JSValueConst object,
                                     JSAtom propID, JSValueConst value,
                                     JSValueConst receiver, int flags);

static JSClassExoticMethods sManifestExoticMethods = {
    .get_own_property = ManifestGetOwnProperty,
    .get_own_property_names = OOJSGetSharedPermanentOwnPropertyNames,
    .delete_property = ManifestDeleteProperty,
    .set_property = ManifestSetPropertyExotic,
};

static JSClassID sManifestClassID;
static JSClassDef sManifestClass = {
    .class_name = "Manifest",
    .finalizer = OOJSObjectWrapperFinalize,
    .exotic = &sManifestExoticMethods,
};

namespace {

enum class ManifestProperty : std::int16_t {
  kList  // manifest list, array of commodities: name, unit, quantity,
         // displayName - read-only
};

}  // namespace

static const JSCFunctionListEntry sManifestProperties[] = {
    // JS name					Getter ID
    OOJS_PROPERTY_RO("list", ManifestGetProperty, ManifestProperty::kList),
};

static const JSCFunctionListEntry sManifestMethods[] = {
    // JS name					Function
    // min args
    JS_CFUNC_DEF("shortComment", 1, ManifestShortComment),
    JS_CFUNC_DEF("setShortComment", 2, ManifestSetShortComment),
    JS_CFUNC_DEF("comment", 1, ManifestComment),
    JS_CFUNC_DEF("setComment", 2, ManifestSetComment),
};

// namespace

// Both Manifest objects are defined with no private object (InitOOJSManifest).

void InitOOJSManifest(JSContext* context, JSValueConst global) {
  OOJSRegisterClass(&sManifestClassID, &sManifestClass);
  JSValueConst manifestPrototype =
      OOJSInitClass(context, global, sManifestClassID, JS_UNDEFINED,
                    OOJSUnconstructableConstruct, 0, sManifestProperties,
                    OOJS_COUNT(sManifestProperties), sManifestMethods,
                    OOJS_COUNT(sManifestMethods), nullptr, 0);
  OOJSRegisterObjectConverter(sManifestClassID,
                              OOJSBasicPrivateObjectConverter);

  // Create manifest object as a property of the player.ship object. (Its
  // private value is NULL.)
  JSValue playerShip = JSPlayerShipObject();  // Owned.
  if (JS_IsObject(playerShip)) {
    JSValue shipManifest =
        JS_NewObjectProtoClass(context, manifestPrototype, sManifestClassID);
    if (JS_DefinePropertyValueStr(context, playerShip, "manifest", shipManifest,
                                  OOJS_PROP_READONLY) < 0) {
      OOJSReportPendingException(context);
    }
  } else if (JS_IsException(playerShip)) {
    OOJSReportPendingException(context);
    playerShip = JS_UNDEFINED;
  }
  JS_FreeValue(context, playerShip);

  // Also define manifest object as a property of the global object.
  // Wait, what? Why? Oh well, too late now. Deprecate for EMMSTRAN? -- Ahruman
  // 2011-02-10
  JS_DefinePropertyValueStr(
      context, global, "manifest",
      JS_NewObjectProtoClass(context, manifestPrototype, sManifestClassID),
      OOJS_PROP_READONLY);
}

// Name for a string property ID, or nullopt for other IDs (symbols and
// integers, which SpiderMonkey's hooks ignored).
static std::optional<std::string> NameForPropertyID(JSContext* context,
                                                    JSAtom propID) {
  std::optional<std::string> result;
  JSValue idValue = JS_AtomToValue(context, propID);
  if (JS_IsString(idValue)) {
    result = OOStringFromJSValue(context, idValue);
  }
  JS_FreeValue(context, idValue);
  return result;
}

static JSValue ManifestGetProperty(OOJS_GETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  oo::PList result;  // null: nil
  PlayerEntity* entity = OOPlayerForScripting();

  switch (static_cast<ManifestProperty>(magic)) {
    using enum ManifestProperty;
    case kList:
      result = (entity != nullptr
                    ? entity->PlayerEntity::cargoListForScripting()
                    : oo::PList());  // qualified: the final overrider, so the
                                     // binding test stands in for it
      break;

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic,
                                    sManifestProperties,
                                    OOJS_COUNT(sManifestProperties));
      return JS_EXCEPTION;
  }

  return OOJSValueFromPList(context, result);

  OOJS_NATIVE_EXIT
}

static int ManifestGetOwnProperty(JSContext* context,
                                  JSPropertyDescriptor* desc,
                                  JSValueConst object, JSAtom propID) {
  try {
    PlayerEntity* entity = OOPlayerForScripting();

    /* 'list' property is hard-coded
     * others map to the commodity keys in trade-goods.plist
     * compatible-ish with 1.80 and earlier except that
     * alienItems and similar aliases don't work */
    std::optional<std::string> key = NameForPropertyID(context, propID);
    OOCommodities* commodities =
        (UNIVERSE != nullptr
             ? UNIVERSE->getCommodities()
             : nullptr);  // null: no good is defined, as a message to nil
    if (key.has_value() && commodities != nullptr &&
        commodities->goodDefined(*key)) {
      if (desc != nullptr) {
        desc->flags = JS_PROP_C_W_E;
        desc->value = JS_NewInt32(
            context,
            (entity != nullptr ? entity->cargoQuantityForType(*key) : 0));
        desc->getter = JS_UNDEFINED;
        desc->setter = JS_UNDEFINED;
      }
      return true;
    }
    // As SpiderMonkey did, report "list" (a shared permanent prototype
    // property) as an own property.
    return OOJSGetSharedPermanentOwnProperty(context, desc, object, propID);
  } catch (...) {
    OOJSReportCurrentException(context);
    return -1;
  }
}

// Returns false with an exception pending on failure.
static bool ManifestSetProperty(JSContext* context, JSValueConst thisObj,
                                const std::string& key, JSValueConst value) {
  PlayerEntity* entity = OOPlayerForScripting();
  int32_t iValue;

  OOCommodityMarket* market =
      (UNIVERSE != nullptr ? UNIVERSE->getCommodityMarket() : nullptr);
  OOMassUnit unit = (market != nullptr)
                        ? market->massUnitForGood(key)
                        : OOMassUnit::kTons;  // OOMassUnit::kTons (0): what a
                                              // message to nil answered
  // we can always change gold, platinum & gem-stones quantities, even with
  // special cargo
  if (unit == OOMassUnit::kTons &&
      (entity != nullptr ? entity->PlayerEntity::getSpecialCargo()
                         : std::optional<std::string>())
          .has_value())  // qualified: the final overrider, so the binding test
                         // stands in for it
  {
    OOJSReportWarning(context,
                      "PlayerShip.manifest['foo'] - cannot modify cargo "
                      "tonnage when Special Cargo is in use.");
    return true;
  }

  if (OOJSValueToInt32(context, value, &iValue)) {
    if (iValue < 0) iValue = 0;
    if (entity != nullptr) entity->setCargoQuantityForType(key, iValue);
  } else {
    // OOJSReportBadPropertyValue() takes a tinyid; this is the same message for
    // a named property.
    if (JS_HasException(context))
      JS_FreeValue(context, JS_GetException(context));
    OOJSReportError(
        context,
        "Cannot set property %s of instance of %s to invalid value %s.",
        key.c_str(), OOJSClassNameOfValue(context, thisObj).c_str(),
        OOJSDescribeValue(context, value, true).c_str());
    return false;
  }
  return true;
}

static int ManifestSetPropertyExotic(JSContext* context, JSValueConst object,
                                     JSAtom propID, JSValueConst value,
                                     JSValueConst receiver, int flags) {
  try {
    std::optional<std::string> key = NameForPropertyID(context, propID);
    if (!key.has_value()) {
      // Not handled by the SpiderMonkey hook; store as an ordinary property.
      return JS_DefinePropertyValue(context, receiver, propID,
                                    JS_DupValue(context, value), JS_PROP_C_W_E);
    }

    // A read-only property inherited from the prototype (list) can't be
    // assigned.
    JSValue prototype = JS_GetPrototype(context, object);
    if (JS_IsException(prototype)) return -1;
    JSPropertyDescriptor protoDesc;
    int found = JS_IsObject(prototype)
                    ? JS_GetOwnProperty(context, &protoDesc, prototype, propID)
                    : 0;
    JS_FreeValue(context, prototype);
    if (found < 0) return -1;
    if (found) {
      bool readOnly = (protoDesc.flags & JS_PROP_GETSET)
                          ? JS_IsUndefined(protoDesc.setter)
                          : !(protoDesc.flags & JS_PROP_WRITABLE);
      JS_FreeValue(context, protoDesc.value);
      JS_FreeValue(context, protoDesc.getter);
      JS_FreeValue(context, protoDesc.setter);
      if (readOnly) {
        if (flags & JS_PROP_THROW) {
          OOJSReportError(
              context, "Cannot set read-only property %s of instance of %s.",
              key->c_str(), OOJSClassNameOfValue(context, receiver).c_str());
          return -1;
        }
        return false;
      }
    }

    if (!ManifestSetProperty(context, receiver, *key, value)) return -1;

    /*	SpiderMonkey also stored the value in a slot. For commodities, the
            get hook overrode it; for other names, it was what later reads
            returned.
    */
    OOCommodities* commodities =
        (UNIVERSE != nullptr
             ? UNIVERSE->getCommodities()
             : nullptr);  // null: no good is defined, as a message to nil
    if (commodities == nullptr || !commodities->goodDefined(*key)) {
      return JS_DefinePropertyValue(context, receiver, propID,
                                    JS_DupValue(context, value), JS_PROP_C_W_E);
    }
    return true;
  } catch (...) {
    OOJSReportCurrentException(context);
    return -1;
  }
}

static int ManifestDeleteProperty(JSContext* context, JSValueConst object,
                                  JSAtom propID) {
  try {
    // As before, deleting is setting to undefined.
    std::optional<std::string> key = NameForPropertyID(context, propID);
    if (!key.has_value()) return true;
    return ManifestSetProperty(context, object, *key, JS_UNDEFINED) ? true : -1;
  } catch (...) {
    OOJSReportCurrentException(context);
    return -1;
  }
}

static JSValue ManifestComment(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> good;
  std::optional<std::string> information;

  if (argc > 0) {
    good = OOStringFromJSValue(context, OOJS_ARGV[0]);
  }
  if (!good.has_value()) {
    OOJSReportBadArguments(context, "Manifest", "comment", MIN(argc, 1),
                           OOJS_ARGV, std::nullopt, "good");
    return JS_EXCEPTION;
  }

  OOCommodityMarket* market =
      (PLAYER != nullptr
           ? PLAYER->getShipCommodityData()
           : static_cast<OOCommodityMarket*>(nullptr));  // null: no comment,
                                                         // as a message to nil
  if (market != nullptr) information = market->commentForGood(*good);

  OOJS_RETURN_STRING_OR_NULL(information);

  OOJS_NATIVE_EXIT
}

static JSValue ManifestSetComment(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  bool OK;
  std::optional<std::string> good;
  std::optional<std::string> information;

  if (argc > 1) {
    good = OOStringFromJSValue(context, OOJS_ARGV[0]);
    information = OOStringFromJSValue(context, OOJS_ARGV[1]);
  }
  if (!good.has_value() || !information.has_value()) {
    OOJSReportBadArguments(context, "Manifest", "setComment", MIN(argc, 2),
                           OOJS_ARGV, std::nullopt,
                           "good and information text");
    return JS_EXCEPTION;
  }

  OOCommodityMarket* market =
      (PLAYER != nullptr ? PLAYER->getShipCommodityData()
                         : static_cast<OOCommodityMarket*>(
                               nullptr));  // null: false, as a message to nil
  OK = market != nullptr && market->setComment(*information, *good);

  OOJS_RETURN_BOOL(OK);

  OOJS_NATIVE_EXIT
}

static JSValue ManifestShortComment(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> good;
  std::optional<std::string> information;

  if (argc > 0) {
    good = OOStringFromJSValue(context, OOJS_ARGV[0]);
  }
  if (!good.has_value()) {
    OOJSReportBadArguments(context, "Manifest", "shortComment", MIN(argc, 1),
                           OOJS_ARGV, std::nullopt, "good");
    return JS_EXCEPTION;
  }

  OOCommodityMarket* market =
      (PLAYER != nullptr
           ? PLAYER->getShipCommodityData()
           : static_cast<OOCommodityMarket*>(nullptr));  // null: no comment,
                                                         // as a message to nil
  if (market != nullptr) information = market->shortCommentForGood(*good);

  OOJS_RETURN_STRING_OR_NULL(information);

  OOJS_NATIVE_EXIT
}

static JSValue ManifestSetShortComment(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  bool OK;
  std::optional<std::string> good;
  std::optional<std::string> information;

  if (argc > 1) {
    good = OOStringFromJSValue(context, OOJS_ARGV[0]);
    information = OOStringFromJSValue(context, OOJS_ARGV[1]);
  }
  if (!good.has_value() || !information.has_value()) {
    OOJSReportBadArguments(context, "Manifest", "setShortComment", MIN(argc, 2),
                           OOJS_ARGV, std::nullopt,
                           "good and information text");
    return JS_EXCEPTION;
  }

  OOCommodityMarket* market =
      (PLAYER != nullptr ? PLAYER->getShipCommodityData()
                         : static_cast<OOCommodityMarket*>(
                               nullptr));  // null: false, as a message to nil
  OK = market != nullptr && market->setShortComment(*information, *good);

  OOJS_RETURN_BOOL(OK);

  OOJS_NATIVE_EXIT
}
