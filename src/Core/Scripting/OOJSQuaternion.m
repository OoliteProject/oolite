/*

OOJSQuaternion.m

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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
#import "OOJavaScriptEngine.h"

#if OOLITE_GNUSTEP
#import <GNUstepBase/GSObjCRuntime.h>
#else
#import <objc/objc-runtime.h>
#endif

#import "OOConstToString.h"
#import "OOJSEntity.h"
#import "OOJSVector.h"


static JSObject *sQuaternionPrototype;


static JSBool QuaternionGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool QuaternionSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);
static void QuaternionFinalize(JSContext *context, JSObject *this);
static JSBool QuaternionConstruct(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool QuaternionEquality(JSContext *context, JSObject *this, jsval value, JSBool *outEqual);

// Methods
static JSBool QuaternionToString(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool QuaternionMultiply(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool QuaternionDot(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool QuaternionRotate(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool QuaternionRotateX(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool QuaternionRotateY(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool QuaternionRotateZ(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool QuaternionNormalize(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool QuaternionVectorForward(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool QuaternionVectorUp(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool QuaternionVectorRight(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool QuaternionToArray(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);

// Static methods
static JSBool QuaternionStaticRandom(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


static JSExtendedClass sQuaternionClass =
{
	{
		"Quaternion",
		JSCLASS_HAS_PRIVATE | JSCLASS_IS_EXTENDED,
		
		JS_PropertyStub,		// addProperty
		JS_PropertyStub,		// delProperty
		QuaternionGetProperty,	// getProperty
		QuaternionSetProperty,	// setProperty
		JS_EnumerateStub,		// enumerate
		JS_ResolveStub,			// resolve
		JS_ConvertStub,			// convert
		QuaternionFinalize,		// finalize
		JSCLASS_NO_OPTIONAL_MEMBERS
	},
	QuaternionEquality,			// equality
	NULL,						// outerObject
	NULL,						// innerObject
	JSCLASS_NO_RESERVED_MEMBERS
};


enum
{
	// Property IDs
	kQuaternion_w,
	kQuaternion_x,
	kQuaternion_y,
	kQuaternion_z
};


static JSPropertySpec sQuaternionProperties[] =
{
	// JS name					ID							flags
	{ "w",						kQuaternion_w,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "x",						kQuaternion_x,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "y",						kQuaternion_y,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "z",						kQuaternion_z,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ 0 }
};


static JSFunctionSpec sQuaternionMethods[] =
{
	// JS name					Function					min args
	{ "toString",				QuaternionToString,			0, },
	{ "multiply",				QuaternionMultiply,			1, },
	{ "dot",					QuaternionDot,				1, },
	{ "rotate",					QuaternionRotate,			2, },
	{ "rotateX",				QuaternionRotateX,			1, },
	{ "rotateY",				QuaternionRotateY,			1, },
	{ "rotateZ",				QuaternionRotateZ,			1, },
	{ "normalize",				QuaternionNormalize,		0, },
	{ "vectorForward",			QuaternionVectorForward,	0, },
	{ "vectorUp",				QuaternionVectorUp,			0, },
	{ "vectorRight",			QuaternionVectorRight,		0, },
	{ "toArray",				QuaternionToArray,			0, },
	{ 0 }
};


static JSFunctionSpec sQuaternionStaticMethods[] =
{
	// JS name					Function					min args
	{ "random",					QuaternionStaticRandom,		0, },
	{ 0 }
};


// *** Public ***

void InitOOJSQuaternion(JSContext *context, JSObject *global)
{
    sQuaternionPrototype = JS_InitClass(context, global, NULL, &sQuaternionClass.base, QuaternionConstruct, 4, sQuaternionProperties, sQuaternionMethods, NULL, sQuaternionStaticMethods);
}


JSObject *JSQuaternionWithQuaternion(JSContext *context, Quaternion quaternion)
{
	JSObject				*result = NULL;
	Quaternion				*private = NULL;
	
	private = malloc(sizeof *private);
	if (private == NULL)  return NULL;
	
	*private = quaternion;
	
	result = JS_NewObject(context, &sQuaternionClass.base, sQuaternionPrototype, NULL);
	if (result != NULL)
	{
		if (!JS_SetPrivate(context, result, private))  result = NULL;
	}
	
	if (result == NULL) free(private);
	
	return result;
}


BOOL QuaternionToJSValue(JSContext *context, Quaternion quaternion, jsval *outValue)
{
	JSObject				*object = NULL;
	
	if (outValue == NULL) return NO;
	
	object = JSQuaternionWithQuaternion(context, quaternion);
	if (object == NULL) return NO;
	
	*outValue = OBJECT_TO_JSVAL(object);
	return YES;
}


BOOL JSValueToQuaternion(JSContext *context, jsval value, Quaternion *outQuaternion)
{
	if (!JSVAL_IS_OBJECT(value))  return NO;
	
	return JSObjectGetQuaternion(context, JSVAL_TO_OBJECT(value), outQuaternion);
}


BOOL JSObjectGetQuaternion(JSContext *context, JSObject *quaternionObj, Quaternion *outQuaternion)
{
	Quaternion				*private = NULL;
	Entity					*entity = nil;
	jsuint					arrayLength;
	jsval					arrayW, arrayX, arrayY, arrayZ;
	jsdouble				dVal;
	
	if (outQuaternion == NULL || quaternionObj == NULL) return NO;
	
	private = JS_GetInstancePrivate(context, quaternionObj, &sQuaternionClass.base, NULL);
	if (private != NULL)	// If this is a (JS) Quaternion...
	{
		*outQuaternion = *private;
		return YES;
	}
	
	// If it's an entity, use its orientation.
	if (JSEntityGetEntity(context, quaternionObj, &entity))
	{
		*outQuaternion = [entity orientation];
		return YES;
	}
	
	// If it's an array...
	if (JS_IsArrayObject(context, quaternionObj))
	{
		// ...and it has exactly four elements...
		if (JS_GetArrayLength(context, quaternionObj, &arrayLength) && arrayLength == 4)
		{
			if (JS_LookupElement(context, quaternionObj, 0, &arrayW) &&
				JS_LookupElement(context, quaternionObj, 1, &arrayX) &&
				JS_LookupElement(context, quaternionObj, 2, &arrayY) &&
				JS_LookupElement(context, quaternionObj, 3, &arrayZ))
			{
				// ...and all four elements are numbers...
				if (JSVAL_IS_NUMBER(arrayW) &&
					JSVAL_IS_NUMBER(arrayX) &&
					JSVAL_IS_NUMBER(arrayY) &&
					JSVAL_IS_NUMBER(arrayZ))
				{
					// Use the four numbers as [w, x, y, z]
					if (!JS_ValueToNumber(context, arrayW, &dVal))  return NO;
					outQuaternion->w = dVal;
					if (!JS_ValueToNumber(context, arrayX, &dVal))  return NO;
					outQuaternion->x = dVal;
					if (!JS_ValueToNumber(context, arrayY, &dVal))  return NO;
					outQuaternion->y = dVal;
					if (!JS_ValueToNumber(context, arrayZ, &dVal))  return NO;
					outQuaternion->z = dVal;
					return YES;
				}
			}
		}
	}
	
	return NO;
}


BOOL JSQuaternionSetQuaternion(JSContext *context, JSObject *quaternionObj, Quaternion quaternion)
{
	Quaternion				*private = NULL;
	
	if (quaternionObj == NULL) return NO;
	
	private = JS_GetInstancePrivate(context, quaternionObj, &sQuaternionClass.base, NULL);
	if (private != NULL)	// If this is a (JS) Quaternion...
	{
		*private = quaternion;
		return YES;
	}
	
	return NO;
}


BOOL QuaternionFromArgumentList(JSContext *context, NSString *scriptClass, NSString *function, uintN argc, jsval *argv, Quaternion *outQuaternion, uintN *outConsumed)
{
	double				w, x, y, z;
	
	// Sanity checks.
	if (outConsumed != NULL)  *outConsumed = 0;
	if (EXPECT_NOT(argc == 0 || argv == NULL || outQuaternion == NULL))
	{
		OOLogGenericParameterError();
		return NO;
	}
	
	
	// Is first object a quaternion or entity?
	if (JSVAL_IS_OBJECT(argv[0]))
	{
		if (JSObjectGetQuaternion(context, JSVAL_TO_OBJECT(argv[0]), outQuaternion))
		{
			if (outConsumed != NULL)  *outConsumed = 1;
			return YES;
		}
	}
	
	// Otherwise, look for four numbers.
	if (argc < 3)  goto FAIL;
	
	if (EXPECT_NOT(!JS_ValueToNumber(context, argv[0], &w)))  goto FAIL;
	if (EXPECT_NOT(!JS_ValueToNumber(context, argv[1], &x)))  goto FAIL;
	if (EXPECT_NOT(!JS_ValueToNumber(context, argv[2], &y)))  goto FAIL;
	if (EXPECT_NOT(!JS_ValueToNumber(context, argv[3], &z)))  goto FAIL;
	
	// Given a string, JS_ValueToNumber() returns YES but provides a NaN number.
	if (EXPECT_NOT(isnan(w) || isnan(x) || isnan(y) || isnan(z))) goto FAIL;
	
	// We got our four numbers.
	*outQuaternion = make_quaternion(w, x, y, z);
	if (outConsumed != NULL)  *outConsumed = 4;
	return YES;
	
FAIL:
	// Report bad parameters, if given a class and function.
	if (scriptClass != nil && function != nil)
	{
		OOReportJavaScriptError(context, @"%@.%@(): could not construct vector from parameters %@ -- expected Vector, Entity or three numbers.", scriptClass, function, [NSString stringWithJavaScriptParameters:argv count:argc inContext:context]);
	}
	return NO;
}


// *** Implementation stuff ***

static JSBool QuaternionGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	Quaternion			quaternion;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSObjectGetQuaternion(context, this, &quaternion)) return NO;
	
	switch (JSVAL_TO_INT(name))
	{
		case kQuaternion_w:
			JS_NewDoubleValue(context, quaternion.w, outValue);
			break;
		
		case kQuaternion_x:
			JS_NewDoubleValue(context, quaternion.x, outValue);
			break;
		
		case kQuaternion_y:
			JS_NewDoubleValue(context, quaternion.y, outValue);
			break;
		
		case kQuaternion_z:
			JS_NewDoubleValue(context, quaternion.z, outValue);
			break;
		
		default:
			OOReportJavaScriptBadPropertySelector(context, @"Quaternion", JSVAL_TO_INT(name));
			return NO;
	}
	
	return YES;
}


static JSBool QuaternionSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	Quaternion			quaternion;
	jsdouble			dval;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSObjectGetQuaternion(context, this, &quaternion)) return NO;
	JS_ValueToNumber(context, *value, &dval);
	
	switch (JSVAL_TO_INT(name))
	{
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
			OOReportJavaScriptBadPropertySelector(context, @"Quaternion", JSVAL_TO_INT(name));
			return NO;
	}
	
	return JSQuaternionSetQuaternion(context, this, quaternion);
}


static void QuaternionFinalize(JSContext *context, JSObject *this)
{
	Quaternion				*private = NULL;
	
	private = JS_GetInstancePrivate(context, this, &sQuaternionClass.base, NULL);
	if (private != NULL)
	{
		free(private);
	}
}


static JSBool QuaternionConstruct(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Quaternion				quaternion;
	Quaternion				*private = NULL;
	
	private = malloc(sizeof *private);
	if (private == NULL)  return NO;
	
	if (!QuaternionFromArgumentList(context, NULL, NULL, argc, argv, &quaternion, NULL))  quaternion = kIdentityQuaternion;
	
	*private = quaternion;
	
	if (!JS_SetPrivate(context, this, private))
	{
		free(private);
		return NO;
	}
	
	return YES;
}


static JSBool QuaternionEquality(JSContext *context, JSObject *this, jsval value, JSBool *outEqual)
{
	Quaternion				thisq, thatq;
	
	*outEqual = NO;
	if (!JSObjectGetQuaternion(context, this, &thisq)) return NO;
	if (!JSVAL_IS_OBJECT(value)) return YES;
	if (!JSObjectGetQuaternion(context, JSVAL_TO_OBJECT(value), &thatq)) return YES;
	
	*outEqual = quaternion_equal(thisq, thatq);
	return YES;
}


// *** Methods ***

// toString() : String
static JSBool QuaternionToString(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Quaternion				thisq;
	
	if (!JSObjectGetQuaternion(context, this, &thisq)) return NO;
	
	*outResult = [QuaternionDescription(thisq) javaScriptValueInContext:context];
	return YES;
}


// multiply(q : quaternionExpression) : Quaternion
static JSBool QuaternionMultiply(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Quaternion				thisq, thatq, result;
	
	if (!JSObjectGetQuaternion(context, this, &thisq)) return NO;
	if (!QuaternionFromArgumentList(context, @"Quaternion", @"multiply", argc, argv, &thatq, NULL))  return YES;
	
	result = quaternion_multiply(thisq, thatq);
	
	return QuaternionToJSValue(context, result, outResult);
}


// dot(q : quaternionExpression) : Number
static JSBool QuaternionDot(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Quaternion				thisq, thatq;
	double					result;
	
	if (!JSObjectGetQuaternion(context, this, &thisq)) return NO;
	if (!QuaternionFromArgumentList(context, @"Quaternion", @"dot", argc, argv, &thatq, NULL))  return YES;
	
	result = quaternion_dot_product(thisq, thatq);
	
	return JS_NewDoubleValue(context, result, outResult);
}


// rotate(axis : vectorExpression, angle : Number) : Quaternion
static JSBool QuaternionRotate(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Quaternion				quat;
	Vector					axis;
	double					angle;
	
	if (!JSObjectGetQuaternion(context, this, &quat)) return NO;
	if (!VectorFromArgumentList(context, @"Quaternion", @"rotate", argc, argv, &axis, NULL))  return YES;
	if (!NumberFromArgumentList(context, @"Quaternion", @"rotate", argc, argv, &angle, NULL))  return YES;
	
	quaternion_rotate_about_axis(&quat, axis, angle);
	
	return QuaternionToJSValue(context, quat, outResult);
}


// rotateX(angle : Number) : Quaternion
static JSBool QuaternionRotateX(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Quaternion				quat;
	double					angle;
	
	if (!JSObjectGetQuaternion(context, this, &quat)) return NO;
	if (!NumberFromArgumentList(context, @"Quaternion", @"rotateX", argc, argv, &angle, NULL))  return YES;
	
	quaternion_rotate_about_x(&quat, angle);
	
	return QuaternionToJSValue(context, quat, outResult);
}


// rotateY(angle : Number) : Quaternion
static JSBool QuaternionRotateY(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Quaternion				quat;
	double					angle;
	
	if (!JSObjectGetQuaternion(context, this, &quat)) return NO;
	if (!NumberFromArgumentList(context, @"Quaternion", @"rotateY", argc, argv, &angle, NULL))  return YES;
	
	quaternion_rotate_about_y(&quat, angle);
	
	return QuaternionToJSValue(context, quat, outResult);
}


// rotateZ(angle : Number) : Quaternion
static JSBool QuaternionRotateZ(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Quaternion				quat;
	double					angle;
	
	if (!JSObjectGetQuaternion(context, this, &quat)) return NO;
	if (!NumberFromArgumentList(context, @"Quaternion", @"rotateZ", argc, argv, &angle, NULL))  return YES;
	
	quaternion_rotate_about_z(&quat, angle);
	
	return QuaternionToJSValue(context, quat, outResult);
}


// normalize() : Quaternion
static JSBool QuaternionNormalize(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Quaternion				quat;
	
	if (!JSObjectGetQuaternion(context, this, &quat)) return NO;
	
	quaternion_normalize(&quat);
	
	return QuaternionToJSValue(context, quat, outResult);
}


// vectorForward() : Vector
static JSBool QuaternionVectorForward(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Quaternion				thisq;
	Vector					result;
	
	if (!JSObjectGetQuaternion(context, this, &thisq)) return NO;
	
	result = vector_forward_from_quaternion(thisq);
	
	return VectorToJSValue(context, result, outResult);
}


// vectorUp() : Vector
static JSBool QuaternionVectorUp(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Quaternion				thisq;
	Vector					result;
	
	if (!JSObjectGetQuaternion(context, this, &thisq)) return NO;
	
	result = vector_up_from_quaternion(thisq);
	
	return VectorToJSValue(context, result, outResult);
}


// vectorRight() : Vector
static JSBool QuaternionVectorRight(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Quaternion				thisq;
	Vector					result;
	
	if (!JSObjectGetQuaternion(context, this, &thisq)) return NO;
	
	result = vector_right_from_quaternion(thisq);
	
	return VectorToJSValue(context, result, outResult);
}


// toArray() : Array
static JSBool QuaternionToArray(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Quaternion				thisq;
	JSObject				*result = NULL;
	BOOL					OK = YES;
	jsval					nVal;
	
	if (!JSObjectGetQuaternion(context, this, &thisq)) return NO;
	
	result = JS_NewArrayObject(context, 0, NULL);
	if (result != NULL)
	{
		// We do this at the top because *outResult is a GC root.
		*outResult = OBJECT_TO_JSVAL(result);
		
		if (JS_NewNumberValue(context, thisq.w, &nVal))  JS_SetElement(context, result, 0, &nVal);
		else  OK = NO;
		if (JS_NewNumberValue(context, thisq.x, &nVal))  JS_SetElement(context, result, 1, &nVal);
		else  OK = NO;
		if (JS_NewNumberValue(context, thisq.y, &nVal))  JS_SetElement(context, result, 2, &nVal);
		else  OK = NO;
		if (JS_NewNumberValue(context, thisq.z, &nVal))  JS_SetElement(context, result, 3, &nVal);
		else  OK = NO;
	}
	
	if (!OK)  *outResult = JSVAL_VOID;
	return YES;
}


// random() : Quaternion
static JSBool QuaternionStaticRandom(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	return QuaternionToJSValue(context, OORandomQuaternion(), outResult);
}
