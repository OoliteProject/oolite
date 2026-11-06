/*

OOJSSun.m (QuickJS-ng)


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

#include "OOJSSun.h"

#include "EntityOOJavaScriptExtensions.h"
#include "OOJSEntity.h"
#include "OOJavaScriptEngine.h"
#include "OOSunEntity.h"

static JSClassID sSunClassID;

static JSValue SunGetProperty(OOJS_GETTER_ARGS);
static JSValue SunGoNova(OOJS_NATIVE_ARGS);
static JSValue SunCancelNova(OOJS_NATIVE_ARGS);

static JSClassDef sSunClass = {
    .class_name = "Sun",
    .finalizer =
        OOJSCxxObjectWrapperFinalize,  // the slot holds an OOJSEntityHolder
};

enum {
  // Property IDs
  kSun_radius,       // Radius of sun in metres, number, read-only
  kSun_hasGoneNova,  // Has sun gone nova, boolean, read-only
  kSun_isGoingNova,  // Will sun go nova, boolean, read-only
  kSun_name          // Name of sun, string, read-only (writable via systeminfo)
};

static const JSCFunctionListEntry sSunProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RO("hasGoneNova", SunGetProperty, kSun_hasGoneNova),
    OOJS_PROPERTY_RO("isGoingNova", SunGetProperty, kSun_isGoingNova),
    OOJS_PROPERTY_RO("name", SunGetProperty, kSun_name),
    OOJS_PROPERTY_RO("radius", SunGetProperty, kSun_radius),
};

static const JSCFunctionListEntry sSunMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("cancelNova", 0, SunCancelNova),
    JS_CFUNC_DEF("goNova", 1, SunGoNova),
};

namespace {
// The getter checks the JS class and answers the C++ sun (the slot holds the
// C++ entity, read by OOJSEntityGetEntityOfClass for the Sun class); null for a
// stale entity.
bool JSSunGetSunEntity(JSContext* context, JSValueConst inObject,
                       OOSunEntity** outObject) {
  Entity* entity = nullptr;
  if (!OOJSEntityGetEntityOfClass(context, inObject, sSunClassID, &entity))
    return false;
  *outObject = dynamic_cast<OOSunEntity*>(entity);
  return true;
}
}  // namespace

void InitOOJSSun(JSContext* context, JSValueConst global) {
  OOJSRegisterClass(&sSunClassID, &sSunClass);

  JSValue parentPrototype = JS_GetClassProto(context, JSEntityClassID());
  OOCAssert(JS_IsObject(parentPrototype),
            "Entity must be initialized before Sun.");
  OOJSInitClass(context, global, sSunClassID, parentPrototype,
                OOJSUnconstructableConstruct, 0, sSunProperties,
                OOJS_COUNT(sSunProperties), sSunMethods,
                OOJS_COUNT(sSunMethods), nullptr, 0);
  JS_FreeValue(context, parentPrototype);

  OOJSRegisterObjectConverter(sSunClassID, OOJSEntityObjectConverter);
  OOJSRegisterSubclass(sSunClassID, JSEntityClassID());
}

JSClassID JSSunClassID(void) { return sSunClassID; }

// The bodies of OOSunEntity (OOJavaScriptExtensions).
bool OOJSSunIsVisibleToScripts(void) { return true; }

std::optional<std::string> OOJSSunJSClassName(void) {
  return std::string("Sun");
}

static JSValue SunGetProperty(OOJS_GETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOSunEntity* sun = nullptr;

  if (EXPECT_NOT(!JSSunGetSunEntity(context, thisObj, &sun)))
    return OOJSNativeFailure(context);

  switch (magic) {
    case kSun_radius:
      return JS_NewNumber(context, (sun != nullptr ? sun->radius() : 0.0));

    case kSun_name: {
      const std::optional<std::string> name =
          (sun != nullptr ? sun->name() : std::optional<std::string>());
      return OOJSValueFromPList(
          context, name.has_value() ? oo::PList(*name) : oo::PList());
    }

    case kSun_hasGoneNova:
      return OOJSValueFromBOOL((sun != nullptr ? sun->goneNova() : false));

    case kSun_isGoingNova:
      return OOJSValueFromBOOL((sun != nullptr ? sun->willGoNova() : false) &&
                               !(sun != nullptr ? sun->goneNova() : false));

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic, sSunProperties,
                                    OOJS_COUNT(sSunProperties));
      return OOJSNativeFailure(context);
  }

  OOJS_NATIVE_EXIT
}

// namespace

// *** Methods ***

// goNova([delay : Number])
static JSValue SunGoNova(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOSunEntity* sun = nullptr;
  double delay = 0;

  if (EXPECT_NOT(!JSSunGetSunEntity(context, OOJS_THIS, &sun)))
    return OOJSNativeFailure(context);
  if (argc > 0 && EXPECT_NOT(JS_ToFloat64(context, &delay, OOJS_ARGV[0]) != 0))
    return OOJSNativeFailure(context);

  if (sun != nullptr) sun->setGoingNova(true, delay);
  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// namespace

// cancelNova()
static JSValue SunCancelNova(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOSunEntity* sun = nullptr;

  if (EXPECT_NOT(!JSSunGetSunEntity(context, OOJS_THIS, &sun)))
    return OOJSNativeFailure(context);

  if ((sun != nullptr ? sun->willGoNova() : false) &&
      !(sun != nullptr ? sun->goneNova() : false)) {
    if (sun != nullptr) sun->setGoingNova(false, 0);
  }
  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}
