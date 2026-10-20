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

#import "OOJSQuaternion.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"

static JSClassID sQuaternionClassID;

static BOOL GetThisQuaternion(JSContext* context, JSValueConst quaternionObj, Quaternion* outQuaternion, NSString* method) NONNULL_FUNC;

static JSValue QuaternionGetProperty(JSContext* context, JSValueConst this, int magic);
static JSValue QuaternionSetProperty(JSContext* context, JSValueConst this, JSValueConst value, int magic);
static void QuaternionFinalize(JSRuntime* runtime, JSValueConst this);
static JSValue QuaternionConstruct(JSContext* context, JSValueConst newTarget, int argc, JSValueConst* argv);

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

enum {
    // Property IDs
    kQuaternion_w,
    kQuaternion_x,
    kQuaternion_y,
    kQuaternion_z
};

static const JSCFunctionListEntry sQuaternionProperties[] = {
    // JS name, getter, setter, ID, flags
    JS_CGETSET_MAGIC_DEF2("w", QuaternionGetProperty, QuaternionSetProperty, kQuaternion_w, OOJS_PROP_READWRITE_CB),
    JS_CGETSET_MAGIC_DEF2("x", QuaternionGetProperty, QuaternionSetProperty, kQuaternion_x, OOJS_PROP_READWRITE_CB),
    JS_CGETSET_MAGIC_DEF2("y", QuaternionGetProperty, QuaternionSetProperty, kQuaternion_y, OOJS_PROP_READWRITE_CB),
    JS_CGETSET_MAGIC_DEF2("z", QuaternionGetProperty, QuaternionSetProperty, kQuaternion_z, OOJS_PROP_READWRITE_CB),
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

void InitOOJSQuaternion(JSContext* context, JSValueConst global)
{
    JSRuntime* runtime = JS_GetRuntime(context);
    JS_NewClassID(runtime, &sQuaternionClassID);
    JS_NewClass(runtime, sQuaternionClassID, &sQuaternionClass);

    // As in SpiderMonkey, the prototype is itself a Quaternion with no private data.
    JSValue prototype = JS_NewObjectClass(context, sQuaternionClassID);
    JS_SetPropertyFunctionList(context, prototype, sQuaternionProperties, OOJS_COUNT(sQuaternionProperties));
    JS_SetPropertyFunctionList(context, prototype, sQuaternionMethods, OOJS_COUNT(sQuaternionMethods));

    JSValue constructor = JS_NewCFunction2(context, QuaternionConstruct, "Quaternion", 4, JS_CFUNC_constructor_or_func, 0);
    JS_SetConstructor(context, constructor, prototype);
    JS_SetPropertyFunctionList(context, constructor, sQuaternionStaticMethods, OOJS_COUNT(sQuaternionStaticMethods));

    JS_SetClassProto(context, sQuaternionClassID, prototype); // Takes ownership of prototype.
    JS_SetPropertyStr(context, global, "Quaternion", constructor); // Takes ownership of constructor.
}

JSValue JSQuaternionWithQuaternion(JSContext* context, Quaternion quaternion)
{
    OOJS_PROFILE_ENTER

    Quaternion* private = NULL;

private
    = malloc(sizeof *private);
    if (EXPECT_NOT(private == NULL))
        return JS_ThrowOutOfMemory(context);

    *private = quaternion;

    JSValue result = JS_NewObjectClass(context, sQuaternionClassID);
    if (EXPECT_NOT(JS_IsException(result))) {
        free(private);
        return result;
    }
    JS_SetOpaque(result, private);

    return result;

    OOJS_PROFILE_EXIT
}

BOOL QuaternionToJSValue(JSContext* context, Quaternion quaternion, JSValue* outValue)
{
    OOJS_PROFILE_ENTER

    assert(outValue != NULL);

    JSValue object = JSQuaternionWithQuaternion(context, quaternion);
    if (EXPECT_NOT(JS_IsException(object))) {
        *outValue = JS_UNDEFINED;
        return NO;
    }

    *outValue = object;
    return YES;

    OOJS_PROFILE_EXIT
}

BOOL JSValueToQuaternion(JSContext* context, JSValueConst value, Quaternion* outQuaternion)
{
    if (EXPECT_NOT(!JS_IsObject(value)))
        return NO;

    return JSObjectGetQuaternion(context, value, outQuaternion);
}

static BOOL GetArrayElementNumber(JSContext* context, JSValueConst array, uint32_t index, double* outNumber)
{
    JSValue element = JS_GetPropertyUint32(context, array, index);
    int status = JS_IsException(element) ? -1 : JS_ToFloat64(context, outNumber, element);
    JS_FreeValue(context, element);
    return status == 0;
}

BOOL JSObjectGetQuaternion(JSContext* context, JSValueConst quaternionObj, Quaternion* outQuaternion)
{
    OOJS_PROFILE_ENTER

    assert(outQuaternion != NULL);

    Quaternion* private = NULL;
    int64_t arrayLength;
    double dVal;

    // quaternionObj can legitimately be null or a primitive.
    if (EXPECT_NOT(!JS_IsObject(quaternionObj))) {
        return NO;
    }

    // If this is a (JS) Quaternion...
private
    = JS_GetOpaque(quaternionObj, sQuaternionClassID);
    if (EXPECT(private != NULL)) {
        *outQuaternion = *private;
        return YES;
    }

    // If it's an array...
    if (EXPECT(JS_IsArray(quaternionObj))) {
        // ...and it has exactly four elements...
        if (JS_GetLength(context, quaternionObj, &arrayLength) == 0 && arrayLength == 4) {
            // ...use the four numbers as [w, x, y, z]
            if (!GetArrayElementNumber(context, quaternionObj, 0, &dVal))
                return NO;
            outQuaternion->w = dVal;
            if (!GetArrayElementNumber(context, quaternionObj, 1, &dVal))
                return NO;
            outQuaternion->x = dVal;
            if (!GetArrayElementNumber(context, quaternionObj, 2, &dVal))
                return NO;
            outQuaternion->y = dVal;
            if (!GetArrayElementNumber(context, quaternionObj, 3, &dVal))
                return NO;
            outQuaternion->z = dVal;

            return YES;
        }
    }

    // TODO (phase 3): if it's an entity, use its orientation.

    /*
            If it's actually a Quaternion but with no private field (this happens for
            Quaternion.prototype)...

            NOTE: it would be prettier to do this at the top when we handle normal
            Quaternions, but it's a rare case which should be kept off the fast path.
    */
    if (JS_GetClassID(quaternionObj) == sQuaternionClassID) {
        *outQuaternion = kZeroQuaternion;
        return YES;
    }

    return NO;

    OOJS_PROFILE_EXIT
}

static BOOL GetThisQuaternion(JSContext* context, JSValueConst quaternionObj, Quaternion* outQuaternion, NSString* method)
{
    if (EXPECT(JSObjectGetQuaternion(context, quaternionObj, outQuaternion)))
        return YES;

    OOJSReportBadArguments(context, @"Quaternion", method, 1, &quaternionObj, @"Invalid target object", @"Quaternion");
    return NO;
}

BOOL JSQuaternionSetQuaternion(JSContext* context, JSValueConst quaternionObj, Quaternion quaternion)
{
    OOJS_PROFILE_ENTER

    Quaternion* private = NULL;

private
    = JS_GetOpaque(quaternionObj, sQuaternionClassID);
    if (private != NULL) // If this is a (JS) Quaternion...
    {
        *private = quaternion;
        return YES;
    }

    if (JS_GetClassID(quaternionObj) == sQuaternionClassID) {
        // Silently fail for the prototype.
        return YES;
    }

    return NO;

    OOJS_PROFILE_EXIT
}

static BOOL QuaternionFromArgumentListNoErrorInternal(JSContext* context, int argc, JSValueConst* argv, Quaternion* outQuaternion, int* outConsumed, BOOL permitNumberList)
{
    OOJS_PROFILE_ENTER

    double w, x, y, z;

    if (EXPECT_NOT(argc == 0))
        return NO;
    assert(argv != NULL && outQuaternion != NULL);

    if (outConsumed != NULL)
        *outConsumed = 0;

    // Is first object a quaternion or entity?
    if (JS_IsObject(argv[0])) {
        if (JSObjectGetQuaternion(context, argv[0], outQuaternion)) {
            if (outConsumed != NULL)
                *outConsumed = 1;
            return YES;
        }
    }

    if (!permitNumberList)
        return NO;

    // As a special case for QuaternionConstruct(), look for four numbers.
    if (EXPECT_NOT(argc < 4))
        return NO;

    // Given a string, JS_ToFloat64() succeeds but provides a NaN number.
    if (EXPECT_NOT(JS_ToFloat64(context, &w, argv[0]) < 0 || isnan(w)))
        return NO;
    if (EXPECT_NOT(JS_ToFloat64(context, &x, argv[1]) < 0 || isnan(x)))
        return NO;
    if (EXPECT_NOT(JS_ToFloat64(context, &y, argv[2]) < 0 || isnan(y)))
        return NO;
    if (EXPECT_NOT(JS_ToFloat64(context, &z, argv[3]) < 0 || isnan(z)))
        return NO;

    // We got our four numbers.
    *outQuaternion = make_quaternion(w, x, y, z);
    if (outConsumed != NULL)
        *outConsumed = 4;

    return YES;

    OOJS_PROFILE_EXIT
}

// EMMSTRAN: remove outConsumed, since it can only be 1 except in failure (constructor is an exception, but it uses QuaternionFromArgumentListNoErrorInternal() directly).
BOOL QuaternionFromArgumentList(JSContext* context, NSString* scriptClass, NSString* function, int argc, JSValueConst* argv, Quaternion* outQuaternion, int* outConsumed)
{
    if (QuaternionFromArgumentListNoErrorInternal(context, argc, argv, outQuaternion, outConsumed, NO))
        return YES;
    else {
        OOJSReportBadArguments(context, scriptClass, function, argc, argv,
            @"Could not construct quaternion from parameters",
            @"Quaternion, Entity or four numbers");
        return NO;
    }
}

BOOL QuaternionFromArgumentListNoError(JSContext* context, int argc, JSValueConst* argv, Quaternion* outQuaternion, int* outConsumed)
{
    return QuaternionFromArgumentListNoErrorInternal(context, argc, argv, outQuaternion, outConsumed, NO);
}

// *** Implementation stuff ***

static JSValue QuaternionGetProperty(JSContext* context, JSValueConst this, int magic)
{
    OOJS_PROFILE_ENTER

    Quaternion quaternion;
    GLfloat fValue; // Single precision, as in the SpiderMonkey version.

    if (EXPECT_NOT(!JSObjectGetQuaternion(context, this, &quaternion)))
        return JS_UNDEFINED;

    switch (magic) {
    case kQuaternion_w:
        fValue = quaternion.w;
        break;

    case kQuaternion_x:
        fValue = quaternion.x;
        break;

    case kQuaternion_y:
        fValue = quaternion.y;
        break;

    case kQuaternion_z:
        fValue = quaternion.z;
        break;

    default:
        OOJSReportBadPropertySelector(context, this, magic, sQuaternionProperties, OOJS_COUNT(sQuaternionProperties));
        return JS_EXCEPTION;
    }

    return JS_NewFloat64(context, fValue);

    OOJS_PROFILE_EXIT
}

static JSValue QuaternionSetProperty(JSContext* context, JSValueConst this, JSValueConst value, int magic)
{
    OOJS_PROFILE_ENTER

    Quaternion quaternion;
    double dval;

    if (EXPECT_NOT(!JSObjectGetQuaternion(context, this, &quaternion)))
        return JS_UNDEFINED;
    if (EXPECT_NOT(JS_ToFloat64(context, &dval, value) < 0)) {
        JS_FreeValue(context, JS_GetException(context));
        OOJSReportBadPropertyValue(context, this, magic, sQuaternionProperties, OOJS_COUNT(sQuaternionProperties), value);
        return JS_EXCEPTION;
    }

    switch (magic) {
    case kQuaternion_w:
        quaternion.w = dval;
        break;

    case kQuaternion_x:
        quaternion.x = dval;
        break;

    case kQuaternion_y:
        quaternion.y = dval;
        break;

    case kQuaternion_z:
        quaternion.z = dval;
        break;

    default:
        OOJSReportBadPropertySelector(context, this, magic, sQuaternionProperties, OOJS_COUNT(sQuaternionProperties));
        return JS_EXCEPTION;
    }

    JSQuaternionSetQuaternion(context, this, quaternion);
    return JS_UNDEFINED;

    OOJS_PROFILE_EXIT
}

static void QuaternionFinalize(JSRuntime* runtime, JSValueConst this)
{
    OOJS_PROFILE_ENTER

    free(JS_GetOpaque(this, sQuaternionClassID));

    OOJS_PROFILE_EXIT_VOID
}

static JSValue QuaternionConstruct(JSContext* context, JSValueConst newTarget, int argc, JSValueConst* argv)
{
    OOJS_PROFILE_ENTER

    Quaternion quaternion = kIdentityQuaternion;

    if (argc != 0) {
        if (EXPECT_NOT(!QuaternionFromArgumentListNoErrorInternal(context, argc, argv, &quaternion, NULL, YES))) {
            OOJSReportBadArguments(context, NULL, NULL, argc, argv,
                @"Could not construct quaternion from parameters",
                @"Quaternion, Entity or array of four numbers");
            return JS_EXCEPTION;
        }
    }

    return JSQuaternionWithQuaternion(context, quaternion);

    OOJS_PROFILE_EXIT
}

// *** Methods ***

// toString() : String
static JSValue QuaternionToString(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    Quaternion thisq;

    if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, @"toString")))
        return JS_EXCEPTION;

    OOJS_RETURN_OBJECT(QuaternionDescription(thisq));

    OOJS_NATIVE_EXIT
}

// toSource() : String
static JSValue QuaternionToSource(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    Quaternion thisq;

    if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, @"toSource")))
        return JS_EXCEPTION;

    NSString* str = [NSString stringWithFormat:@"Quaternion(%g, %g, %g, %g)", thisq.w, thisq.x, thisq.y, thisq.z];
    OOJS_RETURN_OBJECT(str);

    OOJS_NATIVE_EXIT
}

// multiply(q : quaternionExpression) : Quaternion
static JSValue QuaternionMultiply(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    Quaternion thisq, thatq, result;

    if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, @"multiply")))
        return JS_EXCEPTION;
    if (EXPECT_NOT(!QuaternionFromArgumentList(context, @"Quaternion", @"multiply", argc, OOJS_ARGV, &thatq, NULL)))
        return JS_EXCEPTION;

    result = quaternion_multiply(thisq, thatq);

    OOJS_RETURN_QUATERNION(result);

    OOJS_PROFILE_EXIT
}

// dot(q : quaternionExpression) : Number
static JSValue QuaternionDot(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    Quaternion thisq, thatq;
    OOScalar result;

    if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, @"dot")))
        return JS_EXCEPTION;
    if (EXPECT_NOT(!QuaternionFromArgumentList(context, @"Quaternion", @"dot", argc, OOJS_ARGV, &thatq, NULL)))
        return JS_EXCEPTION;

    result = quaternion_dot_product(thisq, thatq);

    OOJS_RETURN_DOUBLE(result);

    OOJS_PROFILE_EXIT
}

// rotate(axis : vectorExpression, angle : Number) : Quaternion
static JSValue QuaternionRotate(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    Quaternion thisq;
    HPVector axis;
    double angle;
    int consumed;
    JSValueConst* argv = OOJS_ARGV;

    if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, @"rotate")))
        return JS_EXCEPTION;
    if (EXPECT_NOT(!VectorFromArgumentList(context, @"Quaternion", @"rotate", argc, argv, &axis, &consumed)))
        return JS_EXCEPTION;

    argv += consumed;
    argc -= consumed;
    if (argc > 0) {
        if (EXPECT_NOT(!OOJSArgumentListGetNumber(context, @"Quaternion", @"rotate", argc, argv, &angle, NULL)))
            return JS_EXCEPTION;
        quaternion_rotate_about_axis(&thisq, HPVectorToVector(axis), angle);
    }
    // Else no angle specified, so don't rotate and pass value through unchanged.

    OOJS_RETURN_QUATERNION(thisq);

    OOJS_PROFILE_EXIT
}

// rotateX(angle : Number) : Quaternion
static JSValue QuaternionRotateX(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    Quaternion quat;
    double angle;

    if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &quat, @"rotateX")))
        return JS_EXCEPTION;
    if (EXPECT_NOT(!OOJSArgumentListGetNumber(context, @"Quaternion", @"rotateX", argc, OOJS_ARGV, &angle, NULL)))
        return JS_EXCEPTION;

    quaternion_rotate_about_x(&quat, angle);

    OOJS_RETURN_QUATERNION(quat);

    OOJS_PROFILE_EXIT
}

// rotateY(angle : Number) : Quaternion
static JSValue QuaternionRotateY(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    Quaternion quat;
    double angle;

    if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &quat, @"rotateY")))
        return JS_EXCEPTION;
    if (EXPECT_NOT(!OOJSArgumentListGetNumber(context, @"Quaternion", @"rotateY", argc, OOJS_ARGV, &angle, NULL)))
        return JS_EXCEPTION;

    quaternion_rotate_about_y(&quat, angle);

    OOJS_RETURN_QUATERNION(quat);

    OOJS_PROFILE_EXIT
}

// rotateZ(angle : Number) : Quaternion
static JSValue QuaternionRotateZ(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    Quaternion quat;
    double angle;

    if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &quat, @"rotateZ")))
        return JS_EXCEPTION;
    if (EXPECT_NOT(!OOJSArgumentListGetNumber(context, @"Quaternion", @"rotateZ", argc, OOJS_ARGV, &angle, NULL)))
        return JS_EXCEPTION;

    quaternion_rotate_about_z(&quat, angle);

    OOJS_RETURN_QUATERNION(quat);

    OOJS_PROFILE_EXIT
}

// normalize() : Quaternion
static JSValue QuaternionNormalize(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    Quaternion quat;

    if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &quat, @"normalize")))
        return JS_EXCEPTION;

    quaternion_normalize(&quat);

    OOJS_RETURN_QUATERNION(quat);

    OOJS_PROFILE_EXIT
}

// conjugate() : Quaternion
static JSValue QuaternionConjugate(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    Quaternion quat, result;

    if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &quat, @"conjugate")))
        return JS_EXCEPTION;

    result = quaternion_conjugate(quat);

    OOJS_RETURN_QUATERNION(result);

    OOJS_PROFILE_EXIT
}

// vectorForward() : Vector
static JSValue QuaternionVectorForward(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    Quaternion thisq;
    Vector result;

    if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, @"vectorForward")))
        return JS_EXCEPTION;

    result = vector_forward_from_quaternion(thisq);

    OOJS_RETURN_VECTOR(result);

    OOJS_PROFILE_EXIT
}

// vectorUp() : Vector
static JSValue QuaternionVectorUp(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    Quaternion thisq;
    Vector result;

    if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, @"vectorUp")))
        return JS_EXCEPTION;

    result = vector_up_from_quaternion(thisq);

    OOJS_RETURN_VECTOR(result);

    OOJS_PROFILE_EXIT
}

// vectorRight() : Vector
static JSValue QuaternionVectorRight(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    Quaternion thisq;
    Vector result;

    if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, @"vectorRight")))
        return JS_EXCEPTION;

    result = vector_right_from_quaternion(thisq);

    OOJS_RETURN_VECTOR(result);

    OOJS_PROFILE_EXIT
}

// toArray() : Array
static JSValue QuaternionToArray(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    Quaternion thisq;

    if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, @"toArray")))
        return JS_EXCEPTION;

    JSValue result = JS_NewArray(context);
    if (EXPECT_NOT(JS_IsException(result)))
        return result;

    // JS_SetPropertyUint32() takes ownership of the element values.
    if (JS_SetPropertyUint32(context, result, 0, JS_NewFloat64(context, thisq.w)) < 0 || JS_SetPropertyUint32(context, result, 1, JS_NewFloat64(context, thisq.x)) < 0 || JS_SetPropertyUint32(context, result, 2, JS_NewFloat64(context, thisq.y)) < 0 || JS_SetPropertyUint32(context, result, 3, JS_NewFloat64(context, thisq.z)) < 0) {
        JS_FreeValue(context, result);
        return JS_EXCEPTION;
    }

    return result;

    OOJS_PROFILE_EXIT
}

// *** Static methods ***

// random() : Quaternion
static JSValue QuaternionStaticRandom(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    OOJS_RETURN_QUATERNION(OORandomQuaternion());

    OOJS_PROFILE_EXIT
}
