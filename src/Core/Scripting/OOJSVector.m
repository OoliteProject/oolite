/*

OOJSVector.m

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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
#import "OOJavaScriptEngine.h"

#if OOLITE_GNUSTEP
#import <GNUstepBase/GSObjCRuntime.h>
#else
#import <objc/objc-runtime.h>
#endif

#import "OOConstToString.h"
#import "OOJSEntity.h"
#import "OOJSQuaternion.h"


static JSObject *sVectorPrototype;


static JSBool VectorGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool VectorSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);
static void VectorFinalize(JSContext *context, JSObject *this);
static JSBool VectorConstruct(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorEquality(JSContext *context, JSObject *this, jsval value, JSBool *outEqual);

// Methods
static JSBool VectorToString(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorToSource(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorAdd(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorSubtract(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorDistanceTo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorSquaredDistanceTo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorMultiply(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorDot(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorAngleTo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorCross(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorTripleProduct(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorDirection(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorMagnitude(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorSquaredMagnitude(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorRotationTo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorRotateBy(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorToArray(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);

// Static methods
static JSBool VectorStaticInterpolate(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorStaticRandom(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorStaticRandomDirection(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorStaticRandomDirectionAndLength(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
//static JSBool VectorStaticConstruct(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


static JSExtendedClass sVectorClass =
{
	{
		"Vector3D",
		JSCLASS_HAS_PRIVATE | JSCLASS_IS_EXTENDED,
		
		JS_PropertyStub,		// addProperty
		JS_PropertyStub,		// delProperty
		VectorGetProperty,		// getProperty
		VectorSetProperty,		// setProperty
		JS_EnumerateStub,		// enumerate
		JS_ResolveStub,			// resolve
		JS_ConvertStub,			// convert
		VectorFinalize,			// finalize
		JSCLASS_NO_OPTIONAL_MEMBERS
	},
	VectorEquality,				// equality
	NULL,						// outerObject
	NULL,						// innerObject
	JSCLASS_NO_RESERVED_MEMBERS
};


enum
{
	// Property IDs
	kVector_x,
	kVector_y,
	kVector_z
};


static JSPropertySpec sVectorProperties[] =
{
	// JS name					ID							flags
	{ "x",						kVector_x,					JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "y",						kVector_y,					JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "z",						kVector_z,					JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ 0 }
};


static JSFunctionSpec sVectorMethods[] =
{
	// JS name					Function					min args
	{ "toString",				VectorToString,				0, },
	{ "toSource",				VectorToSource,				0, },
	{ "add",					VectorAdd,					1, },
	{ "subtract",				VectorSubtract,				1, },
	{ "distanceTo",				VectorDistanceTo,			1, },
	{ "squaredDistanceTo",		VectorSquaredDistanceTo,	1, },
	{ "multiply",				VectorMultiply,				1, },
	{ "dot",					VectorDot,					1, },
	{ "angleTo",				VectorAngleTo,				1, },
	{ "cross",					VectorCross,				1, },
	{ "tripleProduct",			VectorTripleProduct,		2, },
	{ "direction",				VectorDirection,			0, },
	{ "magnitude",				VectorMagnitude,			0, },
	{ "squaredMagnitude",		VectorSquaredMagnitude,		0, },
	{ "rotateBy",				VectorRotateBy,				1, },
	{ "rotationTo",				VectorRotationTo,			1, },
	{ "toArray",				VectorToArray,				0, },
	{ 0 }
};


static JSFunctionSpec sVectorStaticMethods[] =
{
	// JS name					Function					min args
	{ "interpolate",			VectorStaticInterpolate,	3, },
	{ "random",					VectorStaticRandom,			0, },
	{ "randomDirection",		VectorStaticRandomDirection, 0, },
	{ "randomDirectionAndLength", VectorStaticRandomDirectionAndLength, 0, },
	{ 0 }
};


// *** Public ***

void InitOOJSVector(JSContext *context, JSObject *global)
{
	sVectorPrototype = JS_InitClass(context, global, NULL, &sVectorClass.base, VectorConstruct, 0, sVectorProperties, sVectorMethods, NULL, sVectorStaticMethods);
}


JSObject *JSVectorWithVector(JSContext *context, Vector vector)
{
	JSObject				*result = NULL;
	Vector					*private = NULL;
	
	private = malloc(sizeof *private);
	if (EXPECT_NOT(private == NULL))  return NULL;
	
	*private = vector;
	
	result = JS_NewObject(context, &sVectorClass.base, sVectorPrototype, NULL);
	if (result != NULL)
	{
		if (EXPECT_NOT(!JS_SetPrivate(context, result, private)))  result = NULL;
	}
	
	if (EXPECT_NOT(result == NULL)) free(private);
	
	return result;
}


BOOL VectorToJSValue(JSContext *context, Vector vector, jsval *outValue)
{
	JSObject				*object = NULL;
	
	if (EXPECT_NOT(outValue == NULL)) return NO;
	
	object = JSVectorWithVector(context, vector);
	if (EXPECT_NOT(object == NULL)) return NO;
	
	*outValue = OBJECT_TO_JSVAL(object);
	return YES;
}


BOOL NSPointToVectorJSValue(JSContext *context, NSPoint point, jsval *outValue)
{
	return VectorToJSValue(context, make_vector(point.x, point.y, 0), outValue);
}


BOOL JSValueToVector(JSContext *context, jsval value, Vector *outVector)
{
	if (EXPECT_NOT(!JSVAL_IS_OBJECT(value)))  return NO;
	
	return JSObjectGetVector(context, JSVAL_TO_OBJECT(value), outVector);
}


BOOL JSObjectGetVector(JSContext *context, JSObject *vectorObj, Vector *outVector)
{
	Vector					*private = NULL;
	Entity					*entity = nil;
	jsuint					arrayLength;
	jsval					arrayX, arrayY, arrayZ;
	jsdouble				x, y, z;
	
	if (EXPECT_NOT(outVector == NULL || vectorObj == NULL)) return NO;
	
	private = JS_GetInstancePrivate(context, vectorObj, &sVectorClass.base, NULL);
	if (private != NULL)	// If this is a (JS) Vector...
	{
		*outVector = *private;
		return YES;
	}
	
	// If it's an entity, use its position.
	if (JSEntityGetEntity(context, vectorObj, &entity))
	{
		*outVector = [entity position];
		return YES;
	}
	
	// If it's an array...
	if (JS_IsArrayObject(context, vectorObj))
	{
		// ...and it has exactly three elements...
		if (JS_GetArrayLength(context, vectorObj, &arrayLength) && arrayLength == 3)
		{
			if (JS_LookupElement(context, vectorObj, 0, &arrayX) &&
				JS_LookupElement(context, vectorObj, 1, &arrayY) &&
				JS_LookupElement(context, vectorObj, 2, &arrayZ))
			{
				// ...use the three numbers as [x, y, z]
				if (JS_ValueToNumber(context, arrayX, &x) &&
					JS_ValueToNumber(context, arrayY, &y) &&
					JS_ValueToNumber(context, arrayZ, &z))
				{
					*outVector = make_vector(x, y, z);
					return YES;
				}
			}
		}
	}
	
	return NO;
}


BOOL JSVectorSetVector(JSContext *context, JSObject *vectorObj, Vector vector)
{
	Vector					*private = NULL;
	
	if (EXPECT_NOT(vectorObj == NULL))  return NO;
	
	private = JS_GetInstancePrivate(context, vectorObj, &sVectorClass.base, NULL);
	if (private != NULL)	// If this is a (JS) Vector...
	{
		*private = vector;
		return YES;
	}
	
	return NO;
}


BOOL VectorFromArgumentList(JSContext *context, NSString *scriptClass, NSString *function, uintN argc, jsval *argv, Vector *outVector, uintN *outConsumed)
{
	if (VectorFromArgumentListNoError(context, argc, argv, outVector, outConsumed))  return YES;
	else
	{
		OOReportJSBadArguments(context, scriptClass, function, argc, argv,
									   @"Could not construct vector from parameters",
									   @"Vector, Entity or array of three numbers");
		return NO;
	}
}


static BOOL VectorFromArgumentListNoErrorInternal(JSContext *context, uintN argc, jsval *argv, Vector *outVector, uintN *outConsumed, BOOL permitNumberList)
{
	double				x, y, z;
	
	if (outConsumed != NULL)  *outConsumed = 0;
	// Sanity checks.
	if (EXPECT_NOT(argc == 0 || argv == NULL || outVector == NULL))
	{
		OOLogGenericParameterError();
		return NO;
	}
	
	// Is first object a vector, array or entity?
	if (JSVAL_IS_OBJECT(argv[0]))
	{
		if (JSObjectGetVector(context, JSVAL_TO_OBJECT(argv[0]), outVector))
		{
			if (outConsumed != NULL)  *outConsumed = 1;
			return YES;
		}
	}
	
	if (!permitNumberList)  return NO;
	
	// Otherwise, look for three numbers.
	if (argc < 3)  return NO;
	
	// Given a string, JS_ValueToNumber() returns YES but provides a NaN number.
	if (EXPECT_NOT(!JS_ValueToNumber(context, argv[0], &x) || isnan(x)))  return NO;
	if (EXPECT_NOT(!JS_ValueToNumber(context, argv[1], &y) || isnan(y)))  return NO;
	if (EXPECT_NOT(!JS_ValueToNumber(context, argv[2], &z) || isnan(z)))  return NO;
	
	// We got our three numbers.
	*outVector = make_vector(x, y, z);
	if (outConsumed != NULL)  *outConsumed = 3;
	
	return YES;
}
BOOL VectorFromArgumentListNoError(JSContext *context, uintN argc, jsval *argv, Vector *outVector, uintN *outConsumed)
{
	return VectorFromArgumentListNoErrorInternal(context, argc, argv, outVector, outConsumed, NO);
}


// *** Implementation stuff ***

static JSBool VectorGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	Vector				vector;
	GLfloat				value;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (EXPECT_NOT(!JSObjectGetVector(context, this, &vector))) return NO;
	
	switch (JSVAL_TO_INT(name))
	{
		case kVector_x:
			value = vector.x;
			break;
		
		case kVector_y:
			value = vector.y;
			break;
		
		case kVector_z:
			value = vector.z;
			break;
		
		default:
			OOReportJSBadPropertySelector(context, @"Vector3D", JSVAL_TO_INT(name));
			return NO;
	}
	
	return JS_NewDoubleValue(context, value, outValue);
}


static JSBool VectorSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	Vector				vector;
	jsdouble			dval;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (EXPECT_NOT(!JSObjectGetVector(context, this, &vector))) return NO;
	if (EXPECT_NOT(!JS_ValueToNumber(context, *value, &dval))) return NO;
	
	switch (JSVAL_TO_INT(name))
	{
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
			OOReportJSBadPropertySelector(context, @"Vector3D", JSVAL_TO_INT(name));
			return NO;
	}
	
	return JSVectorSetVector(context, this, vector);
}


static void VectorFinalize(JSContext *context, JSObject *this)
{
	Vector					*private = NULL;
	
	private = JS_GetInstancePrivate(context, this, &sVectorClass.base, NULL);
	if (private != NULL)
	{
		free(private);
	}
}


static JSBool VectorConstruct(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					vector = kZeroVector;
	Vector					*private = NULL;
	
	private = malloc(sizeof *private);
	if (EXPECT_NOT(private == NULL))  return NO;
	
    //	If called without new, replace this with a new Vector object.
    if (!JS_IsConstructing(context))
	{
        this = JS_NewObject(context, &sVectorClass.base, NULL, NULL);
        if (this == NULL)  return NO;
		*outResult = OBJECT_TO_JSVAL(this);
    }
	
	if (argc != 0)
	{
		if (EXPECT_NOT(!VectorFromArgumentListNoErrorInternal(context, argc, argv, &vector, NULL, YES)))
		{
			free(private);
			OOReportJSBadArguments(context, NULL, NULL, argc, argv,
								   @"Could not construct vector from parameters",
								   @"Vector, Entity or array of three numbers");
			return NO;
		}
	}
	
	*private = vector;
	
	if (EXPECT_NOT(!JS_SetPrivate(context, this, private)))
	{
		free(private);
		return NO;
	}
	
	return YES;
}


static JSBool VectorEquality(JSContext *context, JSObject *this, jsval value, JSBool *outEqual)
{
	Vector					thisv, thatv;
	
	*outEqual = NO;
	if (EXPECT_NOT(!JSObjectGetVector(context, this, &thisv))) return NO;
	if (EXPECT_NOT(!JSVAL_IS_OBJECT(value))) return YES;
	if (EXPECT_NOT(!JSObjectGetVector(context, JSVAL_TO_OBJECT(value), &thatv))) return YES;
	
	*outEqual = vector_equal(thisv, thatv);
	return YES;
}


// *** Methods ***

// toString() : String
static JSBool VectorToString(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv;
	
	if (EXPECT_NOT(!JSObjectGetVector(context, this, &thisv))) return NO;
	
	*outResult = [VectorDescription(thisv) javaScriptValueInContext:context];
	return YES;
}


// toSource() : String
static JSBool VectorToSource(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv;
	
	if (EXPECT_NOT(!JSObjectGetVector(context, this, &thisv))) return NO;
	
	*outResult = [[NSString stringWithFormat:@"Vector(%g, %g, %g)", thisv.x, thisv.y, thisv.z]
				  javaScriptValueInContext:context];
	return YES;
}


// add(v : vectorExpression) : Vector3D
static JSBool VectorAdd(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv, result;
	
	if (EXPECT_NOT(!JSObjectGetVector(context, this, &thisv))) return NO;
	if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"add", argc, argv, &thatv, NULL)))  return NO;
	
	result = vector_add(thisv, thatv);
	
	return VectorToJSValue(context, result, outResult);
}


// subtract(v : vectorExpression) : Vector3D
static JSBool VectorSubtract(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv, result;
	
	if (EXPECT_NOT(!JSObjectGetVector(context, this, &thisv))) return NO;
	if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"subtract", argc, argv, &thatv, NULL)))  return NO;
	
	result = vector_subtract(thisv, thatv);
	
	return VectorToJSValue(context, result, outResult);
}


// distanceTo(v : vectorExpression) : Vector3D
static JSBool VectorDistanceTo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv;
	GLfloat					result;
	
	if (EXPECT_NOT(!JSObjectGetVector(context, this, &thisv))) return NO;
	if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"distanceTo", argc, argv, &thatv, NULL)))  return NO;
	
	result = distance(thisv, thatv);
	
	return JS_NewDoubleValue(context, result, outResult);
}


// squaredDistanceTo(v : vectorExpression) : Vector3D
static JSBool VectorSquaredDistanceTo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv;
	GLfloat					result;
	
	if (EXPECT_NOT(!JSObjectGetVector(context, this, &thisv))) return NO;
	if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"squaredDistanceTo", argc, argv, &thatv, NULL)))  return NO;
	
	result = distance2(thisv, thatv);
	
	return JS_NewDoubleValue(context, result, outResult);
}


// multiply(n : Number) : Vector3D
static JSBool VectorMultiply(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, result;
	double					scalar;
	
	if (EXPECT_NOT(!JSObjectGetVector(context, this, &thisv))) return NO;
	if (EXPECT_NOT(!NumberFromArgumentList(context, @"Vector3D", @"multiply", argc, argv, &scalar, NULL)))  return NO;
	
	result = vector_multiply_scalar(thisv, scalar);
	
	return VectorToJSValue(context, result, outResult);
}


// dot(v : vectorExpression) : Number
static JSBool VectorDot(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv;
	GLfloat					result;
	
	if (EXPECT_NOT(!JSObjectGetVector(context, this, &thisv))) return NO;
	if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"dot", argc, argv, &thatv, NULL)))  return NO;
	
	result = dot_product(thisv, thatv);
	
	return JS_NewDoubleValue(context, result, outResult);
}


// angleTo(v : vectorExpression) : Number
static JSBool VectorAngleTo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv;
	GLfloat					result;
	
	if (EXPECT_NOT(!JSObjectGetVector(context, this, &thisv))) return NO;
	if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"angleTo", argc, argv, &thatv, NULL)))  return NO;
	
	result = acosf(dot_product(vector_normal(thisv), vector_normal(thatv)));
	
	return JS_NewDoubleValue(context, result, outResult);
}


// cross(v : vectorExpression) : Vector3D
static JSBool VectorCross(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv, result;
	
	if (EXPECT_NOT(!JSObjectGetVector(context, this, &thisv))) return NO;
	if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"cross", argc, argv, &thatv, NULL)))  return NO;
	
	result = true_cross_product(thisv, thatv);
	
	return VectorToJSValue(context, result, outResult);
}


// tripleProduct(v : vectorExpression, u : vectorExpression) : Number
static JSBool VectorTripleProduct(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv, theotherv;
	GLfloat					result;
	uintN					consumed;
	
	if (EXPECT_NOT(!JSObjectGetVector(context, this, &thisv))) return NO;
	if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"tripleProduct", argc, argv, &thatv, &consumed)))  return NO;
	argc += consumed;
	argv += consumed;
	if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"tripleProduct", argc, argv, &theotherv, NULL)))  return NO;
	
	result = triple_product(thisv, thatv, theotherv);
	
	return JS_NewDoubleValue(context, result, outResult);
}


// direction() : Vector3D
static JSBool VectorDirection(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, result;
	
	if (EXPECT_NOT(!JSObjectGetVector(context, this, &thisv))) return NO;
	
	result = vector_normal(thisv);
	
	return VectorToJSValue(context, result, outResult);
}


// magnitude() : Number
static JSBool VectorMagnitude(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv;
	GLfloat					result;
	
	if (EXPECT_NOT(!JSObjectGetVector(context, this, &thisv))) return NO;
	
	result = magnitude(thisv);
	
	return JS_NewDoubleValue(context, result, outResult);
}


// squaredMagnitude() : Number
static JSBool VectorSquaredMagnitude(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv;
	GLfloat					result;
	
	if (EXPECT_NOT(!JSObjectGetVector(context, this, &thisv))) return NO;
	
	result = magnitude2(thisv);
	
	return JS_NewDoubleValue(context, result, outResult);
}


// rotationTo(v : vectorExpression [, limit : Number]) : Quaternion
static JSBool VectorRotationTo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv;
	double					limit;
	BOOL					gotLimit;
	Quaternion				result;
	uintN					consumed;
	
	if (EXPECT_NOT(!JSObjectGetVector(context, this, &thisv))) return NO;
	if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"rotationTo", argc, argv, &thatv, &consumed)))  return NO;
	
	argc -= consumed;
	argv += consumed;
	if (argc != 0)	// limit parameter is optional.
	{
		if (EXPECT_NOT(!NumberFromArgumentList(context, @"Vector3D", @"rotationTo", argc, argv, &limit, NULL)))  return NO;
		gotLimit = YES;
	}
	else gotLimit = NO;
	
	if (gotLimit)  result = quaternion_limited_rotation_between(thisv, thatv, limit);
	else  result = quaternion_rotation_between(thisv, thatv);
	
	return QuaternionToJSValue(context, result, outResult);
}


// rotateBy(q : quaternionExpression) : Vector3D
static JSBool VectorRotateBy(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, result;
	Quaternion				q;
	
	if (EXPECT_NOT(!JSObjectGetVector(context, this, &thisv))) return NO;
	if (EXPECT_NOT(!QuaternionFromArgumentList(context, @"Vector3D", @"rotateBy", argc, argv, &q, NULL)))  return NO;
	
	result = quaternion_rotate_vector(q, thisv);
	
	return VectorToJSValue(context, result, outResult);
}


// toArray() : Array
static JSBool VectorToArray(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv;
	JSObject				*result = NULL;
	jsval					nVal;
	
	if (EXPECT_NOT(!JSObjectGetVector(context, this, &thisv))) return NO;
	
	result = JS_NewArrayObject(context, 0, NULL);
	if (result != NULL)
	{
		// We do this at the top because *outResult is a GC root.
		*outResult = OBJECT_TO_JSVAL(result);
		
		if (JS_NewNumberValue(context, thisv.x, &nVal) && JS_SetElement(context, result, 0, &nVal) &&
			JS_NewNumberValue(context, thisv.y, &nVal) && JS_SetElement(context, result, 1, &nVal) &&
			JS_NewNumberValue(context, thisv.z, &nVal) && JS_SetElement(context, result, 2, &nVal))
		{
			return YES;
		}
		// If we get here, the conversion and stuffing in the previous condition failed.
		*outResult = JSVAL_VOID;
	}
	
	return NO;
}


// interpolate(v : Vector3D, u : Vector3D, alpha : Number) : Vector3D
static JSBool VectorStaticInterpolate(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					av, bv;
	double					interp;
	Vector					result;
	uintN					consumed;
	uintN					inArgc = argc;
	jsval					*inArgv = argv;
	
	if (EXPECT_NOT(argc < 3))  goto INSUFFICIENT_ARGUMENTS;
	if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"interpolate", argc, argv, &av, &consumed)))  return NO;
	argc -= consumed;
	argv += consumed;
	if (EXPECT_NOT(argc < 2))  goto INSUFFICIENT_ARGUMENTS;
	if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"interpolate", argc, argv, &bv, &consumed)))  return NO;
	argc -= consumed;
	argv += consumed;
	if (EXPECT_NOT(argc < 1))  goto INSUFFICIENT_ARGUMENTS;
	if (EXPECT_NOT(!NumberFromArgumentList(context, @"Vector3D", @"interpolate", argc, argv, &interp, NULL)))  return NO;
	
	result = OOVectorInterpolate(av, bv, interp);
	
	return VectorToJSValue(context, result, outResult);
	
INSUFFICIENT_ARGUMENTS:
	OOReportJSBadArguments(context, @"Vector3D", @"interpolate", inArgc, inArgv, 
								   @"Insufficient parameters",
								   @"vector expression, vector expression and number");
	return NO;
}


// random([maxLength : Number]) : Vector3D
static JSBool VectorStaticRandom(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	double					maxLength;
	
	if (argc == 0 || !NumberFromArgumentListNoError(context, argc, argv, &maxLength, NULL))  maxLength = 1.0;
	
	return VectorToJSValue(context, OOVectorRandomSpatial(maxLength), outResult);
}


// randomDirection([scale : Number]) : Vector3D
static JSBool VectorStaticRandomDirection(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	double					scale;
	
	if (argc == 0 || !NumberFromArgumentListNoError(context, argc, argv, &scale, NULL))  scale = 1.0;
	
	return VectorToJSValue(context, vector_multiply_scalar(OORandomUnitVector(), scale), outResult);
}


// randomDirectionAndLength([maxLength : Number]) : Vector3D
static JSBool VectorStaticRandomDirectionAndLength(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	double					maxLength;
	
	if (argc == 0 || !NumberFromArgumentListNoError(context, argc, argv, &maxLength, NULL))  maxLength = 1.0;
	
	return VectorToJSValue(context, OOVectorRandomSpatial(maxLength), outResult);
}
