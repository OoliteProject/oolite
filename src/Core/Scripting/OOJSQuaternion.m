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
static JSBool QuaternionConvert(JSContext *context, JSObject *this, JSType type, jsval *outValue);
static void QuaternionFinalize(JSContext *context, JSObject *this);
static JSBool QuaternionConstruct(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool QuaternionEquality(JSContext *context, JSObject *this, jsval value, JSBool *outEqual);

// Methods
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
		QuaternionConvert,		// convert
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
	{ 0 }
};


// *** Public ***

void InitOOJSQuaternion(JSContext *context, JSObject *global)
{
    sQuaternionPrototype = JS_InitClass(context, global, NULL, &sQuaternionClass.base, QuaternionConstruct, 4, sQuaternionProperties, sQuaternionMethods, NULL, NULL);
}


JSObject *JSQuaternionWithQuaternion(JSContext *context, Quaternion quaternion)
{
	JSObject				*result = NULL;
	Quaternion				*private = NULL;
	
	if (context == NULL) context = [[OOJavaScriptEngine sharedEngine] context];
	
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
	if (EXPECT_NOT(context == NULL))  context = [[OOJavaScriptEngine sharedEngine] context];
	
	object = JSQuaternionWithQuaternion(context, quaternion);
	if (object == NULL) return NO;
	
	*outValue = OBJECT_TO_JSVAL(object);
	return YES;
}


BOOL JSValueToQuaternion(JSContext *context, jsval value, Quaternion *outQuaternion)
{
	if (!JSVAL_IS_OBJECT(value))  return NO;
	
	return JSQuaternionGetQuaternion(context, JSVAL_TO_OBJECT(value), outQuaternion);
}


BOOL JSQuaternionGetQuaternion(JSContext *context, JSObject *quaternionObj, Quaternion *outQuaternion)
{
	Quaternion				*private = NULL;
	Entity					*entity = nil;
	
	if (outQuaternion == NULL || quaternionObj == NULL) return NO;
	if (EXPECT_NOT(context == NULL))  context = [[OOJavaScriptEngine sharedEngine] context];
	
	private = JS_GetInstancePrivate(context, quaternionObj, &sQuaternionClass.base, NULL);
	if (private != NULL)	// If this is a (JS) Quaternion...
	{
		*outQuaternion = *private;
		return YES;
	}
	
	// If it's an entity, use its orientation.
	if (JSEntityGetEntity(context, quaternionObj, &entity))
	{
		*outQuaternion = [entity QRotation];
		return YES;
	}
	
	return NO;
}


BOOL JSQuaternionSetQuaternion(JSContext *context, JSObject *quaternionObj, Quaternion quaternion)
{
	Quaternion				*private = NULL;
	
	if (quaternionObj == NULL) return NO;
	if (EXPECT_NOT(context == NULL))  context = [[OOJavaScriptEngine sharedEngine] context];
	
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
	
	if (EXPECT_NOT(context == NULL))  context = [[OOJavaScriptEngine sharedEngine] context];
	
	// Is first object a quaternion or entity?
	if (JSVAL_IS_OBJECT(argv[0]))
	{
		if (JSQuaternionGetQuaternion(context, JSVAL_TO_OBJECT(argv[0]), outQuaternion))
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
		OOReportJavaScriptWarning(context, @"%@.%@(): could not construct vector from parameters %@ -- expected Vector, Entity or three numbers.", scriptClass, function, [NSString stringWithJavaScriptParameters:argv count:argc inContext:context]);
	}
	return NO;
}


// *** Implementation stuff ***

static JSBool QuaternionGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	Quaternion			quaternion;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSQuaternionGetQuaternion(context, this, &quaternion)) return NO;
	
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
			return YES;
	}
	
	return YES;
}


static JSBool QuaternionSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	Quaternion			quaternion;
	jsdouble			dval;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSQuaternionGetQuaternion(context, this, &quaternion)) return NO;
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
			return YES;
	}
	
	return JSQuaternionSetQuaternion(context, this, quaternion);
}


static JSBool QuaternionConvert(JSContext *context, JSObject *this, JSType type, jsval *outValue)
{
	Quaternion				quaternion;
	
	switch (type)
	{
		case JSTYPE_VOID:		// Used for string concatenation.
		case JSTYPE_STRING:
			// Return description of vector
			if (!JSQuaternionGetQuaternion(context, this, &quaternion))  return NO;
			*outValue = [QuaternionDescription(quaternion) javaScriptValueInContext:context];
			return YES;
		
		default:
			// Contrary to what passes for documentation, JS_ConvertStub is not a no-op.
			return JS_ConvertStub(context, this, type, outValue);
	}
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
	if (!JSQuaternionGetQuaternion(context, this, &thisq)) return NO;
	if (!JSVAL_IS_OBJECT(value)) return YES;
	if (!JSQuaternionGetQuaternion(context, JSVAL_TO_OBJECT(value), &thatq)) return YES;
	
	*outEqual = quaternion_equal(thisq, thatq);
	return YES;
}


// *** Methods ***

// Quaternion multiply(quaternionExpression)
static JSBool QuaternionMultiply(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Quaternion				thisq, thatq, result;
	
	if (!JSQuaternionGetQuaternion(context, this, &thisq)) return NO;
	if (!QuaternionFromArgumentList(context, @"Quaternion", @"multiply", argc, argv, &thatq, NULL))  return YES;
	
	result = quaternion_multiply(thisq, thatq);
	
	return QuaternionToJSValue(context, result, outResult);
}


// double dot(quaternionExpression)
static JSBool QuaternionDot(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Quaternion				thisq, thatq;
	double					result;
	
	if (!JSQuaternionGetQuaternion(context, this, &thisq)) return NO;
	if (!QuaternionFromArgumentList(context, @"Quaternion", @"dot", argc, argv, &thatq, NULL))  return YES;
	
	result = quaternion_dot_product(thisq, thatq);
	
	return JS_NewDoubleValue(context, result, outResult);
}


// Quaternion rotate(vectorExpression, double)
static JSBool QuaternionRotate(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Quaternion				quat;
	Vector					axis;
	double					angle;
	
	if (!JSQuaternionGetQuaternion(context, this, &quat)) return NO;
	if (!VectorFromArgumentList(context, @"Quaternion", @"rotate", argc, argv, &axis, NULL))  return YES;
	if (!NumberFromArgumentList(context, @"Quaternion", @"rotate", argc, argv, &angle, NULL))  return YES;
	
	quaternion_rotate_about_axis(&quat, axis, angle);
	
	return QuaternionToJSValue(context, quat, outResult);
}


// Quaternion rotateX(double)
static JSBool QuaternionRotateX(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Quaternion				quat;
	double					angle;
	
	if (!JSQuaternionGetQuaternion(context, this, &quat)) return NO;
	if (!NumberFromArgumentList(context, @"Quaternion", @"rotateX", argc, argv, &angle, NULL))  return YES;
	
	quaternion_rotate_about_x(&quat, angle);
	
	return QuaternionToJSValue(context, quat, outResult);
}


// Quaternion rotateY(double)
static JSBool QuaternionRotateY(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Quaternion				quat;
	double					angle;
	
	if (!JSQuaternionGetQuaternion(context, this, &quat)) return NO;
	if (!NumberFromArgumentList(context, @"Quaternion", @"rotateY", argc, argv, &angle, NULL))  return YES;
	
	quaternion_rotate_about_y(&quat, angle);
	
	return QuaternionToJSValue(context, quat, outResult);
}


// Quaternion rotateZ(double)
static JSBool QuaternionRotateZ(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Quaternion				quat;
	double					angle;
	
	if (!JSQuaternionGetQuaternion(context, this, &quat)) return NO;
	if (!NumberFromArgumentList(context, @"Quaternion", @"rotateZ", argc, argv, &angle, NULL))  return YES;
	
	quaternion_rotate_about_z(&quat, angle);
	
	return QuaternionToJSValue(context, quat, outResult);
}


// Quaternion normalize()
static JSBool QuaternionNormalize(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Quaternion				quat;
	
	if (!JSQuaternionGetQuaternion(context, this, &quat)) return NO;
	
	quaternion_normalize(&quat);
	
	return QuaternionToJSValue(context, quat, outResult);
}


// Vector vectorForward()
static JSBool QuaternionVectorForward(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Quaternion				thisq;
	Vector					result;
	
	if (!JSQuaternionGetQuaternion(context, this, &thisq)) return NO;
	
	result = vector_forward_from_quaternion(thisq);
	
	return VectorToJSValue(context, result, outResult);
}


// Vector vectorUp()
static JSBool QuaternionVectorUp(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Quaternion				thisq;
	Vector					result;
	
	if (!JSQuaternionGetQuaternion(context, this, &thisq)) return NO;
	
	result = vector_up_from_quaternion(thisq);
	
	return VectorToJSValue(context, result, outResult);
}


// Vector vectorRight()
static JSBool QuaternionVectorRight(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Quaternion				thisq;
	Vector					result;
	
	if (!JSQuaternionGetQuaternion(context, this, &thisq)) return NO;
	
	result = vector_right_from_quaternion(thisq);
	
	return VectorToJSValue(context, result, outResult);
}