/*

OOJSQuaternion.m (QuickJS-ng proof of concept)

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

#include "OOJSQuaternion.h"

#include "OOJSVector.h"
#if !OOJS_POC_HARNESS
#include "OOJSEntity.h"
#endif
#include <memory>
#include <new>

#include "OOJavaScriptEngine.h"

/*
        The Quaternion class, in the design of upstream #768's OOJSQuaternion.m:
        the private slot holds a malloced Quaternion, freed by the finalizer;
        the prototype is an instance with no slot, which converts to the zero
        quaternion.
*/

static JSClassID sQuaternionClassID;

static bool GetThisQuaternion(JSContext* context, JSValueConst quaternionObj,
                              Quaternion* outQuaternion,
                              const std::string& method) NONNULL_FUNC;

static JSValue QuaternionGetProperty(JSContext* context, JSValueConst thisObj,
                                     int magic);
static JSValue QuaternionSetProperty(JSContext* context, JSValueConst thisObj,
                                     JSValueConst value, int magic);
static void QuaternionFinalize(JSRuntime* runtime, JSValueConst thisObj);
static JSValue QuaternionConstruct(JSContext* context, JSValueConst newTarget,
                                   int argc, JSValueConst* argv);

// Methods
static JSValue QuaternionToString(OOJS_NATIVE_ARGS);
static JSValue QuaternionToSource(OOJS_NATIVE_ARGS);
static JSValue QuaternionMultiply(OOJS_NATIVE_ARGS);
static JSValue QuaternionDot(OOJS_NATIVE_ARGS);
static JSValue QuaternionRotate(OOJS_NATIVE_ARGS);
static JSValue QuaternionRotateX(OOJS_NATIVE_ARGS);
static JSValue QuaternionRotateY(OOJS_NATIVE_ARGS);
static JSValue QuaternionRotateZ(OOJS_NATIVE_ARGS);
static JSValue QuaternionNormalize(OOJS_NATIVE_ARGS);
static JSValue QuaternionConjugate(OOJS_NATIVE_ARGS);
static JSValue QuaternionVectorForward(OOJS_NATIVE_ARGS);
static JSValue QuaternionVectorUp(OOJS_NATIVE_ARGS);
static JSValue QuaternionVectorRight(OOJS_NATIVE_ARGS);
static JSValue QuaternionToArray(OOJS_NATIVE_ARGS);

// Static methods
static JSValue QuaternionStaticRandom(OOJS_NATIVE_ARGS);

static JSClassDef sQuaternionClass = {
    .class_name = "Quaternion",
    .finalizer = QuaternionFinalize,
};

namespace {

enum class QuaternionProperty : std::int16_t {
  // Property IDs
  kW,
  kX,
  kY,
  kZ
};

}  // namespace

static const JSCFunctionListEntry sQuaternionProperties[] = {
    // JS name, getter, setter, ID, flags
    JS_CGETSET_MAGIC_DEF2("w", QuaternionGetProperty, QuaternionSetProperty,
                          OOJSPropertyMagic(QuaternionProperty::kW),
                          OOJS_PROP_READWRITE_CB),
    JS_CGETSET_MAGIC_DEF2("x", QuaternionGetProperty, QuaternionSetProperty,
                          OOJSPropertyMagic(QuaternionProperty::kX),
                          OOJS_PROP_READWRITE_CB),
    JS_CGETSET_MAGIC_DEF2("y", QuaternionGetProperty, QuaternionSetProperty,
                          OOJSPropertyMagic(QuaternionProperty::kY),
                          OOJS_PROP_READWRITE_CB),
    JS_CGETSET_MAGIC_DEF2("z", QuaternionGetProperty, QuaternionSetProperty,
                          OOJSPropertyMagic(QuaternionProperty::kZ),
                          OOJS_PROP_READWRITE_CB),
};

static const JSCFunctionListEntry sQuaternionMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("toString", 0, QuaternionToString),
    JS_CFUNC_DEF("toSource", 0, QuaternionToSource),
    JS_CFUNC_DEF("dot", 1, QuaternionDot),
    JS_CFUNC_DEF("multiply", 1, QuaternionMultiply),
    JS_CFUNC_DEF("normalize", 0, QuaternionNormalize),
    JS_CFUNC_DEF("conjugate", 0, QuaternionConjugate),
    JS_CFUNC_DEF("rotate", 2, QuaternionRotate),
    JS_CFUNC_DEF("rotateX", 1, QuaternionRotateX),
    JS_CFUNC_DEF("rotateY", 1, QuaternionRotateY),
    JS_CFUNC_DEF("rotateZ", 1, QuaternionRotateZ),
    JS_CFUNC_DEF("toArray", 0, QuaternionToArray),
    JS_CFUNC_DEF("vectorForward", 0, QuaternionVectorForward),
    JS_CFUNC_DEF("vectorRight", 0, QuaternionVectorRight),
    JS_CFUNC_DEF("vectorUp", 0, QuaternionVectorUp),
};

static const JSCFunctionListEntry sQuaternionStaticMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("random", 0, QuaternionStaticRandom),
};

// *** Public ***

void InitOOJSQuaternion(JSContext* context, JSValueConst global) {
  OOJSRegisterClass(&sQuaternionClassID, &sQuaternionClass);

  // As in SpiderMonkey, the prototype is itself an instance with no private
  // data, treated as zero.
  OOJSInitClass(context, global, sQuaternionClassID, JS_UNDEFINED,
                QuaternionConstruct, 4, sQuaternionProperties,
                OOJS_COUNT(sQuaternionProperties), sQuaternionMethods,
                OOJS_COUNT(sQuaternionMethods), sQuaternionStaticMethods,
                OOJS_COUNT(sQuaternionStaticMethods));
}

JSValue JSQuaternionWithQuaternion(JSContext* context, Quaternion quaternion) {
  OOJS_PROFILE_ENTER

  // The object's private data, deleted by the class finaliser.
  std::unique_ptr<Quaternion> priv(new (std::nothrow) Quaternion(quaternion));
  if (EXPECT_NOT(priv == nullptr)) return JS_ThrowOutOfMemory(context);

  JSValue result = JS_NewObjectClass(context, sQuaternionClassID);
  if (EXPECT_NOT(JS_IsException(result))) return result;
  JS_SetOpaque(result, priv.release());

  return result;

  OOJS_PROFILE_EXIT
}

bool QuaternionToJSValue(JSContext* context, Quaternion quaternion,
                         JSValue* outValue) {
  OOJS_PROFILE_ENTER

  assert(outValue != nullptr);

  JSValue object = JSQuaternionWithQuaternion(context, quaternion);
  if (EXPECT_NOT(JS_IsException(object))) {
    *outValue = JS_UNDEFINED;
    return false;
  }

  *outValue = object;
  return true;

  OOJS_PROFILE_EXIT
}

bool JSValueToQuaternion(JSContext* context, JSValueConst value,
                         Quaternion* outQuaternion) {
  if (EXPECT_NOT(!JS_IsObject(value))) return false;

  return JSObjectGetQuaternion(context, value, outQuaternion);
}

static bool GetArrayElementNumber(JSContext* context, JSValueConst array,
                                  uint32_t index, double* outNumber) {
  JSValue element = JS_GetPropertyUint32(context, array, index);
  int status =
      JS_IsException(element) ? -1 : JS_ToFloat64(context, outNumber, element);
  JS_FreeValue(context, element);
  return status == 0;
}

bool JSObjectGetQuaternion(JSContext* context, JSValueConst quaternionObj,
                           Quaternion* outQuaternion) {
  OOJS_PROFILE_ENTER

  assert(outQuaternion != nullptr);

  Quaternion* priv = nullptr;
  int64_t arrayLength;
  double dVal;

  // quaternionObj can legitimately be null or a primitive.
  if (EXPECT_NOT(!JS_IsObject(quaternionObj))) {
    return false;
  }

  // If this is a (JS) Quaternion...
  priv =
      static_cast<Quaternion*>(JS_GetOpaque(quaternionObj, sQuaternionClassID));
  if (EXPECT(priv != nullptr)) {
    *outQuaternion = *priv;
    return true;
  }

  // If it's an array...
  if (EXPECT(JS_IsArray(quaternionObj))) {
    // ...and it has exactly four elements...
    if (JS_GetLength(context, quaternionObj, &arrayLength) == 0 &&
        arrayLength == 4) {
      // ...use the four numbers as [w, x, y, z]
      if (!GetArrayElementNumber(context, quaternionObj, 0, &dVal))
        return false;
      outQuaternion->w = dVal;
      if (!GetArrayElementNumber(context, quaternionObj, 1, &dVal))
        return false;
      outQuaternion->x = dVal;
      if (!GetArrayElementNumber(context, quaternionObj, 2, &dVal))
        return false;
      outQuaternion->y = dVal;
      if (!GetArrayElementNumber(context, quaternionObj, 3, &dVal))
        return false;
      outQuaternion->z = dVal;

      return true;
    }
  }

#if !OOJS_POC_HARNESS
  // If it's an entity, use its orientation.
  if (OOJSIsMemberOfSubclass(context, quaternionObj, JSEntityClassID())) {
    *outQuaternion = OOJSEntityOrientationOfJSObject(
        context, quaternionObj);  // the C++ entity's
    return true;
  }
#endif

  /*
          If it's actually a Quaternion but with no private field (this happens
     for Quaternion.prototype)...

          NOTE: it would be prettier to do this at the top when we handle normal
          Quaternions, but it's a rare case which should be kept off the fast
     path.
  */
  if (JS_GetClassID(quaternionObj) == sQuaternionClassID) {
    *outQuaternion = kZeroQuaternion;
    return true;
  }

  return false;

  OOJS_PROFILE_EXIT
}

static bool GetThisQuaternion(JSContext* context, JSValueConst quaternionObj,
                              Quaternion* outQuaternion,
                              const std::string& method) {
  if (EXPECT(JSObjectGetQuaternion(context, quaternionObj, outQuaternion)))
    return true;

  OOJSReportBadArguments(context, "Quaternion", method, 1, &quaternionObj,
                         "Invalid target object", "Quaternion");
  return false;
}

bool JSQuaternionSetQuaternion(JSContext* context, JSValueConst quaternionObj,
                               Quaternion quaternion) {
  OOJS_PROFILE_ENTER

  Quaternion* priv = nullptr;

  priv =
      static_cast<Quaternion*>(JS_GetOpaque(quaternionObj, sQuaternionClassID));
  if (priv != nullptr)  // If this is a (JS) Quaternion...
  {
    *priv = quaternion;
    return true;
  }

  if (JS_GetClassID(quaternionObj) == sQuaternionClassID) {
    // Silently fail for the prototype.
    return true;
  }

  return false;

  OOJS_PROFILE_EXIT
}

static bool QuaternionFromArgumentListNoErrorInternal(
    JSContext* context, int argc, JSValueConst* argv, Quaternion* outQuaternion,
    int* outConsumed, bool permitNumberList) {
  OOJS_PROFILE_ENTER

  double w, x, y, z;

  if (EXPECT_NOT(argc == 0)) return false;
  assert(argv != nullptr && outQuaternion != nullptr);

  if (outConsumed != nullptr) *outConsumed = 0;

  // Is first object a quaternion or entity?
  if (JS_IsObject(argv[0])) {
    if (JSObjectGetQuaternion(context, argv[0], outQuaternion)) {
      if (outConsumed != nullptr) *outConsumed = 1;
      return true;
    }
  }

  if (!permitNumberList) return false;

  // As a special case for QuaternionConstruct(), look for four numbers.
  if (EXPECT_NOT(argc < 4)) return false;

  // Given a string, JS_ToFloat64() succeeds but provides a NaN number.
  if (EXPECT_NOT(JS_ToFloat64(context, &w, argv[0]) < 0 || isnan(w)))
    return false;
  if (EXPECT_NOT(JS_ToFloat64(context, &x, argv[1]) < 0 || isnan(x)))
    return false;
  if (EXPECT_NOT(JS_ToFloat64(context, &y, argv[2]) < 0 || isnan(y)))
    return false;
  if (EXPECT_NOT(JS_ToFloat64(context, &z, argv[3]) < 0 || isnan(z)))
    return false;

  // We got our four numbers.
  *outQuaternion = make_quaternion(w, x, y, z);
  if (outConsumed != nullptr) *outConsumed = 4;

  return true;

  OOJS_PROFILE_EXIT
}

// EMMSTRAN: remove outConsumed, since it can only be 1 except in failure
// (constructor is an exception, but it uses
// QuaternionFromArgumentListNoErrorInternal() directly).
bool QuaternionFromArgumentList(JSContext* context,
                                const std::string& scriptClass,
                                const std::string& function, int argc,
                                JSValueConst* argv, Quaternion* outQuaternion,
                                int* outConsumed) {
  if (QuaternionFromArgumentListNoErrorInternal(
          context, argc, argv, outQuaternion, outConsumed, false))
    return true;
  else {
    OOJSReportBadArguments(context, scriptClass, function, argc, argv,
                           "Could not construct quaternion from parameters",
                           "Quaternion, Entity or four numbers");
    return false;
  }
}

bool QuaternionFromArgumentListNoError(JSContext* context, int argc,
                                       JSValueConst* argv,
                                       Quaternion* outQuaternion,
                                       int* outConsumed) {
  return QuaternionFromArgumentListNoErrorInternal(
      context, argc, argv, outQuaternion, outConsumed, false);
}

// *** Implementation stuff ***

static JSValue QuaternionGetProperty(JSContext* context, JSValueConst thisObj,
                                     int magic) {
  OOJS_PROFILE_ENTER

  Quaternion quaternion;
  GLfloat fValue;  // Single precision, as in the SpiderMonkey version.

  if (EXPECT_NOT(!JSObjectGetQuaternion(context, thisObj, &quaternion)))
    return JS_UNDEFINED;

  switch (static_cast<QuaternionProperty>(magic)) {
    using enum QuaternionProperty;
    case kW:
      fValue = quaternion.w;
      break;

    case kX:
      fValue = quaternion.x;
      break;

    case kY:
      fValue = quaternion.y;
      break;

    case kZ:
      fValue = quaternion.z;
      break;

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic,
                                    sQuaternionProperties,
                                    OOJS_COUNT(sQuaternionProperties));
      return JS_EXCEPTION;
  }

  return JS_NewFloat64(context, fValue);

  OOJS_PROFILE_EXIT
}

static JSValue QuaternionSetProperty(JSContext* context, JSValueConst thisObj,
                                     JSValueConst value, int magic) {
  OOJS_PROFILE_ENTER

  Quaternion quaternion;
  double dval;

  if (EXPECT_NOT(!JSObjectGetQuaternion(context, thisObj, &quaternion)))
    return JS_UNDEFINED;
  if (EXPECT_NOT(JS_ToFloat64(context, &dval, value) < 0)) {
    JS_FreeValue(context, JS_GetException(context));
    OOJSReportBadPropertyValue(context, thisObj, magic, sQuaternionProperties,
                               OOJS_COUNT(sQuaternionProperties), value);
    return JS_EXCEPTION;
  }

  switch (static_cast<QuaternionProperty>(magic)) {
    using enum QuaternionProperty;
    case kW:
      quaternion.w = dval;
      break;

    case kX:
      quaternion.x = dval;
      break;

    case kY:
      quaternion.y = dval;
      break;

    case kZ:
      quaternion.z = dval;
      break;

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic,
                                    sQuaternionProperties,
                                    OOJS_COUNT(sQuaternionProperties));
      return JS_EXCEPTION;
  }

  JSQuaternionSetQuaternion(context, thisObj, quaternion);
  return JS_UNDEFINED;

  OOJS_PROFILE_EXIT
}

static void QuaternionFinalize(JSRuntime* runtime, JSValueConst thisObj) {
  OOJS_PROFILE_ENTER

  delete static_cast<Quaternion*>(JS_GetOpaque(thisObj, sQuaternionClassID));

  OOJS_PROFILE_EXIT_VOID
}

static JSValue QuaternionConstruct(JSContext* context, JSValueConst newTarget,
                                   int argc, JSValueConst* argv) {
  OOJS_PROFILE_ENTER

  Quaternion quaternion = kIdentityQuaternion;

  if (argc != 0) {
    if (EXPECT_NOT(!QuaternionFromArgumentListNoErrorInternal(
            context, argc, argv, &quaternion, nullptr, true))) {
      OOJSReportBadArguments(context, std::nullopt, std::nullopt, argc, argv,
                             "Could not construct quaternion from parameters",
                             "Quaternion, Entity or array of four numbers");
      return JS_EXCEPTION;
    }
  }

  return JSQuaternionWithQuaternion(context, quaternion);

  OOJS_PROFILE_EXIT
}

// *** Methods ***

// toString() : String
static JSValue QuaternionToString(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  Quaternion thisq;

  if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, "toString")))
    return JS_EXCEPTION;

  OOJS_RETURN_PLIST(oo::PList(QuaternionDescription(thisq)));

  OOJS_NATIVE_EXIT
}

// toSource() : String
static JSValue QuaternionToSource(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  Quaternion thisq;

  if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, "toSource")))
    return JS_EXCEPTION;

  OOJS_RETURN_PLIST(oo::PList(std::format("Quaternion({:g}, {:g}, {:g}, {:g})",
                                          thisq.w, thisq.x, thisq.y, thisq.z)));

  OOJS_NATIVE_EXIT
}

// multiply(q : quaternionExpression) : Quaternion
static JSValue QuaternionMultiply(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  Quaternion thisq, thatq, result;

  if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, "multiply")))
    return JS_EXCEPTION;
  if (EXPECT_NOT(!QuaternionFromArgumentList(context, "Quaternion", "multiply",
                                             argc, OOJS_ARGV, &thatq, nullptr)))
    return JS_EXCEPTION;

  result = quaternion_multiply(thisq, thatq);

  OOJS_RETURN_QUATERNION(result);

  OOJS_PROFILE_EXIT
}

// dot(q : quaternionExpression) : Number
static JSValue QuaternionDot(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  Quaternion thisq, thatq;
  OOScalar result;

  if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, "dot")))
    return JS_EXCEPTION;
  if (EXPECT_NOT(!QuaternionFromArgumentList(context, "Quaternion", "dot", argc,
                                             OOJS_ARGV, &thatq, nullptr)))
    return JS_EXCEPTION;

  result = quaternion_dot_product(thisq, thatq);

  OOJS_RETURN_DOUBLE(result);

  OOJS_PROFILE_EXIT
}

// rotate(axis : vectorExpression, angle : Number) : Quaternion
static JSValue QuaternionRotate(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  Quaternion thisq;
  HPVector axis;
  double angle;
  int consumed;
  JSValueConst* argv = OOJS_ARGV;

  if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, "rotate")))
    return JS_EXCEPTION;
  if (EXPECT_NOT(!VectorFromArgumentList(context, "Quaternion", "rotate", argc,
                                         argv, &axis, &consumed)))
    return JS_EXCEPTION;

  argv += consumed;
  argc -= consumed;
  if (argc > 0) {
    if (EXPECT_NOT(!OOJSArgumentListGetNumber(context, "Quaternion", "rotate",
                                              argc, argv, &angle, nullptr)))
      return JS_EXCEPTION;
    quaternion_rotate_about_axis(&thisq, HPVectorToVector(axis), angle);
  }
  // Else no angle specified, so don't rotate and pass value through unchanged.

  OOJS_RETURN_QUATERNION(thisq);

  OOJS_PROFILE_EXIT
}

// rotateX(angle : Number) : Quaternion
static JSValue QuaternionRotateX(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  Quaternion quat;
  double angle;

  if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &quat, "rotateX")))
    return JS_EXCEPTION;
  if (EXPECT_NOT(!OOJSArgumentListGetNumber(context, "Quaternion", "rotateX",
                                            argc, OOJS_ARGV, &angle, nullptr)))
    return JS_EXCEPTION;

  quaternion_rotate_about_x(&quat, angle);

  OOJS_RETURN_QUATERNION(quat);

  OOJS_PROFILE_EXIT
}

// rotateY(angle : Number) : Quaternion
static JSValue QuaternionRotateY(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  Quaternion quat;
  double angle;

  if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &quat, "rotateY")))
    return JS_EXCEPTION;
  if (EXPECT_NOT(!OOJSArgumentListGetNumber(context, "Quaternion", "rotateY",
                                            argc, OOJS_ARGV, &angle, nullptr)))
    return JS_EXCEPTION;

  quaternion_rotate_about_y(&quat, angle);

  OOJS_RETURN_QUATERNION(quat);

  OOJS_PROFILE_EXIT
}

// rotateZ(angle : Number) : Quaternion
static JSValue QuaternionRotateZ(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  Quaternion quat;
  double angle;

  if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &quat, "rotateZ")))
    return JS_EXCEPTION;
  if (EXPECT_NOT(!OOJSArgumentListGetNumber(context, "Quaternion", "rotateZ",
                                            argc, OOJS_ARGV, &angle, nullptr)))
    return JS_EXCEPTION;

  quaternion_rotate_about_z(&quat, angle);

  OOJS_RETURN_QUATERNION(quat);

  OOJS_PROFILE_EXIT
}

// normalize() : Quaternion
static JSValue QuaternionNormalize(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  Quaternion quat;

  if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &quat, "normalize")))
    return JS_EXCEPTION;

  quaternion_normalize(&quat);

  OOJS_RETURN_QUATERNION(quat);

  OOJS_PROFILE_EXIT
}

// conjugate() : Quaternion
static JSValue QuaternionConjugate(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  Quaternion quat, result;

  if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &quat, "conjugate")))
    return JS_EXCEPTION;

  result = quaternion_conjugate(quat);

  OOJS_RETURN_QUATERNION(result);

  OOJS_PROFILE_EXIT
}

// vectorForward() : Vector
static JSValue QuaternionVectorForward(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  Quaternion thisq;
  Vector result;

  if (EXPECT_NOT(
          !GetThisQuaternion(context, OOJS_THIS, &thisq, "vectorForward")))
    return JS_EXCEPTION;

  result = vector_forward_from_quaternion(thisq);

  OOJS_RETURN_VECTOR(result);

  OOJS_PROFILE_EXIT
}

// vectorUp() : Vector
static JSValue QuaternionVectorUp(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  Quaternion thisq;
  Vector result;

  if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, "vectorUp")))
    return JS_EXCEPTION;

  result = vector_up_from_quaternion(thisq);

  OOJS_RETURN_VECTOR(result);

  OOJS_PROFILE_EXIT
}

// vectorRight() : Vector
static JSValue QuaternionVectorRight(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  Quaternion thisq;
  Vector result;

  if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, "vectorRight")))
    return JS_EXCEPTION;

  result = vector_right_from_quaternion(thisq);

  OOJS_RETURN_VECTOR(result);

  OOJS_PROFILE_EXIT
}

// toArray() : Array
static JSValue QuaternionToArray(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  Quaternion thisq;

  if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, "toArray")))
    return JS_EXCEPTION;

  JSValue result = JS_NewArray(context);
  if (EXPECT_NOT(JS_IsException(result))) return result;

  // JS_SetPropertyUint32() takes ownership of the element values.
  if (JS_SetPropertyUint32(context, result, 0,
                           JS_NewFloat64(context, thisq.w)) < 0 ||
      JS_SetPropertyUint32(context, result, 1,
                           JS_NewFloat64(context, thisq.x)) < 0 ||
      JS_SetPropertyUint32(context, result, 2,
                           JS_NewFloat64(context, thisq.y)) < 0 ||
      JS_SetPropertyUint32(context, result, 3,
                           JS_NewFloat64(context, thisq.z)) < 0) {
    JS_FreeValue(context, result);
    return JS_EXCEPTION;
  }

  return result;

  OOJS_PROFILE_EXIT
}

// *** Static methods ***

// random() : Quaternion
static JSValue QuaternionStaticRandom(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  OOJS_RETURN_QUATERNION(OORandomQuaternion());

  OOJS_PROFILE_EXIT
}
