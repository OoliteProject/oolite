/*

OOJSVector.m (QuickJS-ng proof of concept)

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

#import "OOJSVector.h"
#import "OOJSQuaternion.h"
#import "OOJavaScriptEngine.h"

static JSClassID sVectorClassID;

static BOOL GetThisVector(JSContext* context, JSValueConst vectorObj, HPVector* outVector, NSString* method) NONNULL_FUNC;

static JSValue VectorGetProperty(JSContext* context, JSValueConst this, int magic);
static JSValue VectorSetProperty(JSContext* context, JSValueConst this, JSValueConst value, int magic);
static void VectorFinalize(JSRuntime* runtime, JSValueConst this);
static JSValue VectorConstruct(JSContext* context, JSValueConst newTarget, int argc, JSValueConst* argv);

// Methods
static JSValue VectorToString(OOJS_NATIVE_ARGS);
static JSValue VectorToSource(OOJS_NATIVE_ARGS);
static JSValue VectorAdd(OOJS_NATIVE_ARGS);
static JSValue VectorSubtract(OOJS_NATIVE_ARGS);
static JSValue VectorDistanceTo(OOJS_NATIVE_ARGS);
static JSValue VectorSquaredDistanceTo(OOJS_NATIVE_ARGS);
static JSValue VectorMultiply(OOJS_NATIVE_ARGS);
static JSValue VectorDot(OOJS_NATIVE_ARGS);
static JSValue VectorAngleTo(OOJS_NATIVE_ARGS);
static JSValue VectorCross(OOJS_NATIVE_ARGS);
static JSValue VectorTripleProduct(OOJS_NATIVE_ARGS);
static JSValue VectorDirection(OOJS_NATIVE_ARGS);
static JSValue VectorMagnitude(OOJS_NATIVE_ARGS);
static JSValue VectorSquaredMagnitude(OOJS_NATIVE_ARGS);
static JSValue VectorRotationTo(OOJS_NATIVE_ARGS);
static JSValue VectorRotateBy(OOJS_NATIVE_ARGS);
static JSValue VectorToArray(OOJS_NATIVE_ARGS);

// Static methods
static JSValue VectorStaticInterpolate(OOJS_NATIVE_ARGS);
static JSValue VectorStaticRandom(OOJS_NATIVE_ARGS);
static JSValue VectorStaticRandomDirection(OOJS_NATIVE_ARGS);
static JSValue VectorStaticRandomDirectionAndLength(OOJS_NATIVE_ARGS);

static JSClassDef sVectorClass = {
    .class_name = "Vector3D",
    .finalizer = VectorFinalize,
};

enum {
    // Property IDs
    kVector_x,
    kVector_y,
    kVector_z
};

static const JSCFunctionListEntry sVectorProperties[] = {
    // JS name, getter, setter, ID, flags
    JS_CGETSET_MAGIC_DEF2("x", VectorGetProperty, VectorSetProperty, kVector_x, OOJS_PROP_READWRITE_CB),
    JS_CGETSET_MAGIC_DEF2("y", VectorGetProperty, VectorSetProperty, kVector_y, OOJS_PROP_READWRITE_CB),
    JS_CGETSET_MAGIC_DEF2("z", VectorGetProperty, VectorSetProperty, kVector_z, OOJS_PROP_READWRITE_CB),
};

/*	TODO (phase 3): toCoordinateSystem() and fromCoordinateSystem() need
        Universe, which is not part of the proof-of-concept harness.
*/
static const JSCFunctionListEntry sVectorMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("toSource", 0, VectorToSource),
    JS_CFUNC_DEF("toString", 0, VectorToString),
    JS_CFUNC_DEF("add", 1, VectorAdd),
    JS_CFUNC_DEF("angleTo", 1, VectorAngleTo),
    JS_CFUNC_DEF("cross", 1, VectorCross),
    JS_CFUNC_DEF("direction", 0, VectorDirection),
    JS_CFUNC_DEF("distanceTo", 1, VectorDistanceTo),
    JS_CFUNC_DEF("dot", 1, VectorDot),
    JS_CFUNC_DEF("magnitude", 0, VectorMagnitude),
    JS_CFUNC_DEF("multiply", 1, VectorMultiply),
    JS_CFUNC_DEF("rotateBy", 1, VectorRotateBy),
    JS_CFUNC_DEF("rotationTo", 1, VectorRotationTo),
    JS_CFUNC_DEF("squaredDistanceTo", 1, VectorSquaredDistanceTo),
    JS_CFUNC_DEF("squaredMagnitude", 0, VectorSquaredMagnitude),
    JS_CFUNC_DEF("subtract", 1, VectorSubtract),
    JS_CFUNC_DEF("toArray", 0, VectorToArray),
    JS_CFUNC_DEF("tripleProduct", 2, VectorTripleProduct),
};

static const JSCFunctionListEntry sVectorStaticMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("interpolate", 3, VectorStaticInterpolate),
    JS_CFUNC_DEF("random", 0, VectorStaticRandom),
    JS_CFUNC_DEF("randomDirection", 0, VectorStaticRandomDirection),
    JS_CFUNC_DEF("randomDirectionAndLength", 0, VectorStaticRandomDirectionAndLength),
};

// *** Public ***

void InitOOJSVector(JSContext* context, JSValueConst global)
{
    JSRuntime* runtime = JS_GetRuntime(context);
    JS_NewClassID(runtime, &sVectorClassID);
    JS_NewClass(runtime, sVectorClassID, &sVectorClass);

    /*	As in SpiderMonkey, the prototype is itself a Vector3D, with no
            private data; JSObjectGetVector() treats it as a zero vector.
    */
    JSValue prototype = JS_NewObjectClass(context, sVectorClassID);
    JS_SetPropertyFunctionList(context, prototype, sVectorProperties, OOJS_COUNT(sVectorProperties));
    JS_SetPropertyFunctionList(context, prototype, sVectorMethods, OOJS_COUNT(sVectorMethods));

    JSValue constructor = JS_NewCFunction2(context, VectorConstruct, "Vector3D", 0, JS_CFUNC_constructor_or_func, 0);
    JS_SetConstructor(context, constructor, prototype);
    JS_SetPropertyFunctionList(context, constructor, sVectorStaticMethods, OOJS_COUNT(sVectorStaticMethods));

    JS_SetClassProto(context, sVectorClassID, prototype); // Takes ownership of prototype.
    JS_SetPropertyStr(context, global, "Vector3D", constructor); // Takes ownership of constructor.
}

JSValue JSVectorWithVector(JSContext* context, Vector vector)
{
    return JSVectorWithHPVector(context, vectorToHPVector(vector));
}

BOOL VectorToJSValue(JSContext* context, Vector vector, JSValue* outValue)
{
    assert(outValue != NULL);

    return HPVectorToJSValue(context, vectorToHPVector(vector), outValue);
}

JSValue JSVectorWithHPVector(JSContext* context, HPVector vector)
{
    OOJS_PROFILE_ENTER

    HPVector* private = NULL;

private
    = malloc(sizeof *private);
    if (EXPECT_NOT(private == NULL))
        return JS_ThrowOutOfMemory(context);

    *private = vector;

    JSValue result = JS_NewObjectClass(context, sVectorClassID);
    if (EXPECT_NOT(JS_IsException(result))) {
        free(private);
        return result;
    }
    JS_SetOpaque(result, private);

    return result;

    OOJS_PROFILE_EXIT
}

BOOL HPVectorToJSValue(JSContext* context, HPVector vector, JSValue* outValue)
{
    OOJS_PROFILE_ENTER

    assert(outValue != NULL);

    JSValue object = JSVectorWithHPVector(context, vector);
    if (EXPECT_NOT(JS_IsException(object))) {
        *outValue = JS_UNDEFINED;
        return NO;
    }

    *outValue = object;
    return YES;

    OOJS_PROFILE_EXIT
}

BOOL NSPointToVectorJSValue(JSContext* context, NSPoint point, JSValue* outValue)
{
    return VectorToJSValue(context, make_vector(point.x, point.y, 0), outValue);
}

BOOL JSValueToHPVector(JSContext* context, JSValueConst value, HPVector* outVector)
{
    if (EXPECT_NOT(!JS_IsObject(value)))
        return NO;

    return JSObjectGetVector(context, value, outVector);
}

BOOL JSValueToVector(JSContext* context, JSValueConst value, Vector* outVector)
{
    if (EXPECT_NOT(!JS_IsObject(value)))
        return NO;
    HPVector tmp = kZeroHPVector;
    BOOL result = JSObjectGetVector(context, value, &tmp);
    *outVector = HPVectorToVector(tmp);
    return result;
}

// Get array element as a number. Like JS_ValueToNumber(), non-numbers give NaN rather than failing.
static BOOL GetArrayElementNumber(JSContext* context, JSValueConst array, uint32_t index, double* outNumber)
{
    JSValue element = JS_GetPropertyUint32(context, array, index);
    int status = JS_IsException(element) ? -1 : JS_ToFloat64(context, outNumber, element);
    JS_FreeValue(context, element);
    return status == 0;
}

BOOL JSObjectGetVector(JSContext* context, JSValueConst vectorObj, HPVector* outVector)
{
    OOJS_PROFILE_ENTER

    assert(outVector != NULL);

    HPVector* private = NULL;
    int64_t arrayLength;
    double x, y, z;

    // vectorObj can legitimately be null or a primitive.
    if (EXPECT_NOT(!JS_IsObject(vectorObj))) {
        return NO;
    }

    // If this is a (JS) Vector...
private
    = JS_GetOpaque(vectorObj, sVectorClassID);
    if (EXPECT(private != NULL)) {
        *outVector = *private;
        return YES;
    }

    // If it's an array...
    if (EXPECT(JS_IsArray(vectorObj))) {
        // ...and it has exactly three elements...
        if (JS_GetLength(context, vectorObj, &arrayLength) == 0 && arrayLength == 3) {
            // ...use the three numbers as [x, y, z]
            if (GetArrayElementNumber(context, vectorObj, 0, &x) && GetArrayElementNumber(context, vectorObj, 1, &y) && GetArrayElementNumber(context, vectorObj, 2, &z)) {
                *outVector = make_HPvector(x, y, z);
                return YES;
            }
        }
    }

    // TODO (phase 3): if it's an entity, use its position.

    /*
            If it's actually a Vector3D but with no private field (this happens for
            Vector3D.prototype)...

            NOTE: it would be prettier to do this at the top when we handle normal
            Vector3Ds, but it's a rare case which should be kept off the fast path.
    */
    if (JS_GetClassID(vectorObj) == sVectorClassID) {
        *outVector = kZeroHPVector;
        return YES;
    }

    return NO;

    OOJS_PROFILE_EXIT
}

static BOOL GetThisVector(JSContext* context, JSValueConst vectorObj, HPVector* outVector, NSString* method)
{
    if (EXPECT(JSObjectGetVector(context, vectorObj, outVector)))
        return YES;

    OOJSReportBadArguments(context, @"Vector3D", method, 1, &vectorObj, @"Invalid target object", @"Vector3D");
    return NO;
}

BOOL JSVectorSetVector(JSContext* context, JSValueConst vectorObj, Vector vector)
{
    return JSVectorSetHPVector(context, vectorObj, vectorToHPVector(vector));
}

BOOL JSVectorSetHPVector(JSContext* context, JSValueConst vectorObj, HPVector vector)
{
    OOJS_PROFILE_ENTER

    HPVector* private = NULL;

    if (EXPECT_NOT(!JS_IsObject(vectorObj)))
        return NO;

private
    = JS_GetOpaque(vectorObj, sVectorClassID);
    if (private != NULL) // If this is a (JS) Vector...
    {
        *private = vector;
        return YES;
    }

    if (JS_GetClassID(vectorObj) == sVectorClassID) {
        // Silently fail for the prototype.
        return YES;
    }

    return NO;

    OOJS_PROFILE_EXIT
}

static BOOL VectorFromArgumentListNoErrorInternal(JSContext* context, int argc, JSValueConst* argv, HPVector* outVector, int* outConsumed, BOOL permitNumberList)
{
    OOJS_PROFILE_ENTER

    double x, y, z;

    if (EXPECT_NOT(argc == 0))
        return NO;
    assert(argv != NULL && outVector != NULL);

    if (outConsumed != NULL)
        *outConsumed = 0;

    // Is first object a vector, array or entity?
    if (JS_IsObject(argv[0])) {
        if (JSObjectGetVector(context, argv[0], outVector)) {
            if (outConsumed != NULL)
                *outConsumed = 1;
            return YES;
        }
    }

    if (!permitNumberList)
        return NO;

    // As a special case for VectorConstruct(), look for three numbers.
    if (argc < 3)
        return NO;

    // Given a string, JS_ToFloat64() succeeds but provides a NaN number.
    if (EXPECT_NOT(JS_ToFloat64(context, &x, argv[0]) < 0 || isnan(x)))
        return NO;
    if (EXPECT_NOT(JS_ToFloat64(context, &y, argv[1]) < 0 || isnan(y)))
        return NO;
    if (EXPECT_NOT(JS_ToFloat64(context, &z, argv[2]) < 0 || isnan(z)))
        return NO;

    // We got our three numbers.
    *outVector = make_HPvector(x, y, z);
    if (outConsumed != NULL)
        *outConsumed = 3;

    return YES;

    OOJS_PROFILE_EXIT
}

// EMMSTRAN: remove outConsumed, since it can only be 1 except in failure (constructor is an exception, but it uses VectorFromArgumentListNoErrorInternal() directly).
BOOL VectorFromArgumentList(JSContext* context, NSString* scriptClass, NSString* function, int argc, JSValueConst* argv, HPVector* outVector, int* outConsumed)
{
    if (VectorFromArgumentListNoErrorInternal(context, argc, argv, outVector, outConsumed, NO))
        return YES;
    else {
        OOJSReportBadArguments(context, scriptClass, function, argc, argv,
            @"Could not construct vector from parameters",
            @"Vector, Entity or array of three numbers");
        return NO;
    }
}

BOOL VectorFromArgumentListNoError(JSContext* context, int argc, JSValueConst* argv, HPVector* outVector, int* outConsumed)
{
    return VectorFromArgumentListNoErrorInternal(context, argc, argv, outVector, outConsumed, NO);
}

// *** Implementation stuff ***

static JSValue VectorGetProperty(JSContext* context, JSValueConst this, int magic)
{
    OOJS_PROFILE_ENTER

    HPVector vector;
    OOHPScalar fValue;

    if (EXPECT_NOT(!JSObjectGetVector(context, this, &vector)))
        return JS_UNDEFINED;

    switch (magic) {
    case kVector_x:
        fValue = vector.x;
        break;

    case kVector_y:
        fValue = vector.y;
        break;

    case kVector_z:
        fValue = vector.z;
        break;

    default:
        OOJSReportBadPropertySelector(context, this, magic, sVectorProperties, OOJS_COUNT(sVectorProperties));
        return JS_EXCEPTION;
    }

    return JS_NewFloat64(context, fValue);

    OOJS_PROFILE_EXIT
}

static JSValue VectorSetProperty(JSContext* context, JSValueConst this, JSValueConst value, int magic)
{
    OOJS_PROFILE_ENTER

    HPVector vector;
    double dval;

    if (EXPECT_NOT(!JSObjectGetVector(context, this, &vector)))
        return JS_UNDEFINED;
    if (EXPECT_NOT(JS_ToFloat64(context, &dval, value) < 0)) {
        JS_FreeValue(context, JS_GetException(context));
        OOJSReportBadPropertyValue(context, this, magic, sVectorProperties, OOJS_COUNT(sVectorProperties), value);
        return JS_EXCEPTION;
    }

    switch (magic) {
    case kVector_x:
        vector.x = dval;
        break;

    case kVector_y:
        vector.y = dval;
        break;

    case kVector_z:
        vector.z = dval;
        break;

    default:
        OOJSReportBadPropertySelector(context, this, magic, sVectorProperties, OOJS_COUNT(sVectorProperties));
        return JS_EXCEPTION;
    }

    JSVectorSetHPVector(context, this, vector);
    return JS_UNDEFINED;

    OOJS_PROFILE_EXIT
}

static void VectorFinalize(JSRuntime* runtime, JSValueConst this)
{
    OOJS_PROFILE_ENTER

    free(JS_GetOpaque(this, sVectorClassID));

    OOJS_PROFILE_EXIT_VOID
}

static JSValue VectorConstruct(JSContext* context, JSValueConst newTarget, int argc, JSValueConst* argv)
{
    OOJS_PROFILE_ENTER

    HPVector vector = kZeroHPVector;

    if (argc != 0) {
        if (EXPECT_NOT(!VectorFromArgumentListNoErrorInternal(context, argc, argv, &vector, NULL, YES))) {
            OOJSReportBadArguments(context, NULL, NULL, argc, argv,
                @"Could not construct vector from parameters",
                @"Vector, Entity or array of three numbers");
            return JS_EXCEPTION;
        }
    }

    return JSVectorWithHPVector(context, vector);

    OOJS_PROFILE_EXIT
}

// *** Methods ***

// toString() : String
static JSValue VectorToString(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    HPVector thisv;

    if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"toString")))
        return JS_EXCEPTION;

    OOJS_RETURN_OBJECT(HPVectorDescription(thisv));

    OOJS_NATIVE_EXIT
}

// toSource() : String
static JSValue VectorToSource(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    HPVector thisv;

    if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"toSource")))
        return JS_EXCEPTION;

    NSString* str = [NSString stringWithFormat:@"Vector3D(%g, %g, %g)", thisv.x, thisv.y, thisv.z];
    OOJS_RETURN_OBJECT(str);

    OOJS_NATIVE_EXIT
}

// add(v : vectorExpression) : Vector3D
static JSValue VectorAdd(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    HPVector thisv, thatv, result;

    if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"add")))
        return JS_EXCEPTION;
    if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"add", argc, OOJS_ARGV, &thatv, NULL)))
        return JS_EXCEPTION;

    result = HPvector_add(thisv, thatv);

    OOJS_RETURN_HPVECTOR(result);

    OOJS_PROFILE_EXIT
}

// subtract(v : vectorExpression) : Vector3D
static JSValue VectorSubtract(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    HPVector thisv, thatv, result;

    if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"subtract")))
        return JS_EXCEPTION;
    if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"subtract", argc, OOJS_ARGV, &thatv, NULL)))
        return JS_EXCEPTION;

    result = HPvector_subtract(thisv, thatv);

    OOJS_RETURN_HPVECTOR(result);

    OOJS_PROFILE_EXIT
}

// distanceTo(v : vectorExpression) : Number
static JSValue VectorDistanceTo(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    HPVector thisv, thatv;
    double result;

    if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"distanceTo")))
        return JS_EXCEPTION;
    if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"distanceTo", argc, OOJS_ARGV, &thatv, NULL)))
        return JS_EXCEPTION;

    result = HPdistance(thisv, thatv);

    OOJS_RETURN_DOUBLE(result);

    OOJS_PROFILE_EXIT
}

// squaredDistanceTo(v : vectorExpression) : Number
static JSValue VectorSquaredDistanceTo(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    HPVector thisv, thatv;
    double result;

    if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"squaredDistanceTo")))
        return JS_EXCEPTION;
    if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"squaredDistanceTo", argc, OOJS_ARGV, &thatv, NULL)))
        return JS_EXCEPTION;

    result = HPdistance2(thisv, thatv);

    OOJS_RETURN_DOUBLE(result);

    OOJS_PROFILE_EXIT
}

// multiply(n : Number) : Vector3D
static JSValue VectorMultiply(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    HPVector thisv, result;
    double scalar;

    if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"multiply")))
        return JS_EXCEPTION;
    if (EXPECT_NOT(!OOJSArgumentListGetNumber(context, @"Vector3D", @"multiply", argc, OOJS_ARGV, &scalar, NULL)))
        return JS_EXCEPTION;

    result = HPvector_multiply_scalar(thisv, scalar);

    OOJS_RETURN_HPVECTOR(result);

    OOJS_PROFILE_EXIT
}

// dot(v : vectorExpression) : Number
static JSValue VectorDot(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    HPVector thisv, thatv;
    double result;

    if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"dot")))
        return JS_EXCEPTION;
    if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"dot", argc, OOJS_ARGV, &thatv, NULL)))
        return JS_EXCEPTION;

    result = HPdot_product(thisv, thatv);

    OOJS_RETURN_DOUBLE(result);

    OOJS_PROFILE_EXIT
}

// angleTo(v : vectorExpression) : Number
static JSValue VectorAngleTo(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    HPVector thisv, thatv;
    double result;

    if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"angleTo")))
        return JS_EXCEPTION;
    if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"angleTo", argc, OOJS_ARGV, &thatv, NULL)))
        return JS_EXCEPTION;

    result = HPdot_product(HPvector_normal(thisv), HPvector_normal(thatv));
    if (result > 1.0)
        result = 1.0;
    if (result < -1.0)
        result = -1.0;
    // for identical vectors the dot_product sometimes returns a value > 1.0 because of rounding errors, resulting
    // in an undefined result for the acos.
    result = acos(result);

    OOJS_RETURN_DOUBLE(result);

    OOJS_PROFILE_EXIT
}

// cross(v : vectorExpression) : Vector3D
static JSValue VectorCross(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    HPVector thisv, thatv, result;

    if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"cross")))
        return JS_EXCEPTION;
    if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"cross", argc, OOJS_ARGV, &thatv, NULL)))
        return JS_EXCEPTION;

    result = HPtrue_cross_product(thisv, thatv);

    OOJS_RETURN_HPVECTOR(result);

    OOJS_PROFILE_EXIT
}

// tripleProduct(v : vectorExpression, u : vectorExpression) : Number
static JSValue VectorTripleProduct(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    HPVector thisv, thatv, theotherv;
    double result;
    int consumed;
    JSValueConst* argv = OOJS_ARGV;

    if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"tripleProduct")))
        return JS_EXCEPTION;
    if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"tripleProduct", argc, argv, &thatv, &consumed)))
        return JS_EXCEPTION;
    argc -= consumed;
    argv += consumed;
    if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"tripleProduct", argc, argv, &theotherv, NULL)))
        return JS_EXCEPTION;

    result = HPtriple_product(thisv, thatv, theotherv);

    OOJS_RETURN_DOUBLE(result);

    OOJS_PROFILE_EXIT
}

// direction() : Vector3D
static JSValue VectorDirection(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    HPVector thisv, result;

    if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"direction")))
        return JS_EXCEPTION;

    result = HPvector_normal(thisv);

    OOJS_RETURN_HPVECTOR(result);

    OOJS_PROFILE_EXIT
}

// magnitude() : Number
static JSValue VectorMagnitude(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    HPVector thisv;
    double result;

    if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"magnitude")))
        return JS_EXCEPTION;

    result = HPmagnitude(thisv);

    OOJS_RETURN_DOUBLE(result);

    OOJS_PROFILE_EXIT
}

// squaredMagnitude() : Number
static JSValue VectorSquaredMagnitude(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    HPVector thisv;
    double result;

    if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"squaredMagnitude")))
        return JS_EXCEPTION;

    result = HPmagnitude2(thisv);

    OOJS_RETURN_DOUBLE(result);

    OOJS_PROFILE_EXIT
}

// rotationTo(v : vectorExpression [, limit : Number]) : Quaternion
static JSValue VectorRotationTo(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    HPVector thisv, thatv;
    double limit;
    BOOL gotLimit;
    Quaternion result;
    int consumed;
    JSValueConst* argv = OOJS_ARGV;

    if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"rotationTo")))
        return JS_EXCEPTION;
    if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"rotationTo", argc, OOJS_ARGV, &thatv, &consumed)))
        return JS_EXCEPTION;

    argc -= consumed;
    argv += consumed;
    if (argc != 0) // limit parameter is optional.
    {
        if (EXPECT_NOT(!OOJSArgumentListGetNumber(context, @"Vector3D", @"rotationTo", argc, argv, &limit, NULL)))
            return JS_EXCEPTION;
        gotLimit = YES;
    } else
        gotLimit = NO;

    if (gotLimit)
        result = quaternion_limited_rotation_between(HPVectorToVector(thisv), HPVectorToVector(thatv), limit);
    else
        result = quaternion_rotation_between(HPVectorToVector(thisv), HPVectorToVector(thatv));

    OOJS_RETURN_QUATERNION(result);

    OOJS_PROFILE_EXIT
}

// rotateBy(q : quaternionExpression) : Vector3D
static JSValue VectorRotateBy(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    HPVector thisv, result;
    Quaternion q;

    if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"rotateBy")))
        return JS_EXCEPTION;
    if (EXPECT_NOT(!QuaternionFromArgumentList(context, @"Vector3D", @"rotateBy", argc, OOJS_ARGV, &q, NULL)))
        return JS_EXCEPTION;

    result = quaternion_rotate_HPvector(q, thisv);

    OOJS_RETURN_HPVECTOR(result);

    OOJS_PROFILE_EXIT
}

// toArray() : Array
static JSValue VectorToArray(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    HPVector thisv;

    if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"toArray")))
        return JS_EXCEPTION;

    JSValue result = JS_NewArray(context);
    if (EXPECT_NOT(JS_IsException(result)))
        return result;

    // JS_SetPropertyUint32() takes ownership of the element values.
    if (JS_SetPropertyUint32(context, result, 0, JS_NewFloat64(context, thisv.x)) < 0 || JS_SetPropertyUint32(context, result, 1, JS_NewFloat64(context, thisv.y)) < 0 || JS_SetPropertyUint32(context, result, 2, JS_NewFloat64(context, thisv.z)) < 0) {
        JS_FreeValue(context, result);
        return JS_EXCEPTION;
    }

    return result;

    OOJS_PROFILE_EXIT
}

// *** Static methods ***

// interpolate(v : Vector3D, u : Vector3D, alpha : Number) : Vector3D
static JSValue VectorStaticInterpolate(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    HPVector av, bv;
    double interp;
    HPVector result;
    int consumed;
    int inArgc = argc;
    JSValueConst* argv = OOJS_ARGV;
    JSValueConst* inArgv = argv;

    if (EXPECT_NOT(argc < 3))
        goto INSUFFICIENT_ARGUMENTS;
    if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"interpolate", argc, argv, &av, &consumed)))
        return JS_EXCEPTION;
    argc -= consumed;
    argv += consumed;
    if (EXPECT_NOT(argc < 2))
        goto INSUFFICIENT_ARGUMENTS;
    if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"interpolate", argc, argv, &bv, &consumed)))
        return JS_EXCEPTION;
    argc -= consumed;
    argv += consumed;
    if (EXPECT_NOT(argc < 1))
        goto INSUFFICIENT_ARGUMENTS;
    if (EXPECT_NOT(!OOJSArgumentListGetNumber(context, @"Vector3D", @"interpolate", argc, argv, &interp, NULL)))
        return JS_EXCEPTION;

    result = OOHPVectorInterpolate(av, bv, interp);

    OOJS_RETURN_HPVECTOR(result);

INSUFFICIENT_ARGUMENTS:
    OOJSReportBadArguments(context, @"Vector3D", @"interpolate", inArgc, inArgv,
        @"Insufficient parameters",
        @"vector expression, vector expression and number");
    return JS_EXCEPTION;

    OOJS_PROFILE_EXIT
}

// random([maxLength : Number]) : Vector3D
static JSValue VectorStaticRandom(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    double maxLength;

    if (argc == 0 || !OOJSArgumentListGetNumberNoError(context, argc, OOJS_ARGV, &maxLength, NULL))
        maxLength = 1.0;

    OOJS_RETURN_HPVECTOR(OOHPVectorRandomSpatial(maxLength));

    OOJS_PROFILE_EXIT
}

// randomDirection([scale : Number]) : Vector3D
static JSValue VectorStaticRandomDirection(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    double scale;

    if (argc == 0 || !OOJSArgumentListGetNumberNoError(context, argc, OOJS_ARGV, &scale, NULL))
        scale = 1.0;

    OOJS_RETURN_HPVECTOR(HPvector_multiply_scalar(OORandomUnitHPVector(), scale));

    OOJS_PROFILE_EXIT
}

// randomDirectionAndLength([maxLength : Number]) : Vector3D
static JSValue VectorStaticRandomDirectionAndLength(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    double maxLength;

    if (argc == 0 || !OOJSArgumentListGetNumberNoError(context, argc, OOJS_ARGV, &maxLength, NULL))
        maxLength = 1.0;

    OOJS_RETURN_HPVECTOR(OOHPVectorRandomRadial(maxLength));

    OOJS_PROFILE_EXIT
}
