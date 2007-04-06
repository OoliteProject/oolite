/*

OOJSVector.m

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


#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import <objc/objc-runtime.h>
#import "OOConstToString.h"
#import "OOJSEntity.h"


static JSObject *sVectorPrototype;


static JSBool VectorGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool VectorSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);
static JSBool VectorConvert(JSContext *context, JSObject *this, JSType type, jsval *outValue);
static void VectorFinalize(JSContext *context, JSObject *this);
static JSBool VectorConstruct(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool VectorEquality(JSContext *context, JSObject *this, jsval value, JSBool *outEqual);

// Methods
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


static JSExtendedClass sVectorClass =
{
	{
		"Vector",
		JSCLASS_HAS_PRIVATE | JSCLASS_IS_EXTENDED,
		
		JS_PropertyStub,		// addProperty
		JS_PropertyStub,		// delProperty
		VectorGetProperty,		// getProperty
		VectorSetProperty,		// setProperty
		JS_EnumerateStub,		// enumerate
		JS_ResolveStub,			// resolve
		VectorConvert,			// convert
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
	{ 0 }
};


void InitOOJSVector(JSContext *context, JSObject *global)
{
    sVectorPrototype = JS_InitClass(context, global, NULL, &sVectorClass.base, VectorConstruct, 3, sVectorProperties, sVectorMethods, NULL, NULL);
}


JSObject *JSVectorWithVector(JSContext *context, Vector vector)
{
	JSObject				*result = NULL;
	Vector					*private = NULL;
	
	if (context == NULL) context = [[OOJavaScriptEngine sharedEngine] context];
	
	private = malloc(sizeof *private);
	if (private == NULL)  return NULL;
	
	*private = vector;
	
	result = JS_NewObject(context, &sVectorClass.base, sVectorPrototype, NULL);
	if (result != NULL)
	{
		if (!JS_SetPrivate(context, result, private))  result = NULL;
	}
	
	if (result == NULL) free(private);
	
	return result;
}


BOOL VectorToJSValue(JSContext *context, Vector vector, jsval *outValue)
{
	JSObject				*object = NULL;
	
	if (outValue == NULL) return NO;
	if (context == NULL)  context = [[OOJavaScriptEngine sharedEngine] context];
	
	object = JSVectorWithVector(context, vector);
	if (object == NULL) return NO;
	
	*outValue = OBJECT_TO_JSVAL(object);
	return YES;
}


BOOL JSValueToVector(JSContext *context, jsval value, Vector *outVector)
{
	if (!JSVAL_IS_OBJECT(value))  return NO;
	
	return JSVectorGetVector(context, JSVAL_TO_OBJECT(value), outVector);
}


BOOL JSVectorGetVector(JSContext *context, JSObject *vectorObj, Vector *outVector)
{
	Vector					*private = NULL;
	Entity					*entity = nil;
	
	if (outVector == NULL || vectorObj == NULL) return NO;
	if (context == NULL)  context = [[OOJavaScriptEngine sharedEngine] context];
	
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
	
	return NO;
}


BOOL JSVectorSetVector(JSContext *context, JSObject *vectorObj, Vector vector)
{
	Vector					*private = NULL;
	
	if (vectorObj == NULL) return NO;
	if (context == NULL)  context = [[OOJavaScriptEngine sharedEngine] context];
	
	private = JS_GetInstancePrivate(context, vectorObj, &sVectorClass.base, NULL);
	if (private != NULL)	// If this is a (JS) Vector...
	{
		*private = vector;
		return YES;
	}
	// TODO: handle entity proxy
	
	return NO;
}


BOOL VectorFromArgumentList(JSContext *context, uintN argc, jsval *argv, Vector *outVector, uintN *outConsumed)
{
	double				x, y, z;
	
	if (outConsumed != NULL)  *outConsumed = 0;
	if (argc == 0 || argv == NULL || outVector == NULL)  return NO;
	if (context == NULL)  context = [[OOJavaScriptEngine sharedEngine] context];
	
	// Is first object a vector or entity?
	if (JSVAL_IS_OBJECT(argv[0]))
	{
		if (JSVectorGetVector(context, JSVAL_TO_OBJECT(argv[0]), outVector))
		{
			if (outConsumed != NULL)  *outConsumed = 1;
			return YES;
		}
	}
	
	// Otherwise, look for three numbers.
	if (argc < 3)  return NO;
	
	if (!JS_ValueToNumber(context, argv[0], &x))  return NO;
	if (!JS_ValueToNumber(context, argv[1], &y))  return NO;
	if (!JS_ValueToNumber(context, argv[2], &z))  return NO;
	
	if (isnan(x) || isnan(y) || isnan(z)) return NO;	// NaN indicates a string with non-numeric characters.
	
	*outVector = make_vector(x, y, z);
	if (outConsumed != NULL)  *outConsumed = 3;
	return YES;
}


static JSBool VectorGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	Vector				vector;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSVectorGetVector(context, this, &vector)) return NO;
	
	switch (JSVAL_TO_INT(name))
	{
		case kVector_x:
			JS_NewDoubleValue(context, vector.x, outValue);
			break;
		
		case kVector_y:
			JS_NewDoubleValue(context, vector.y, outValue);
			break;
		
		case kVector_z:
			JS_NewDoubleValue(context, vector.z, outValue);
			break;
		
		default:
			return NO;
	}
	
	return YES;
}


static JSBool VectorSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	Vector				vector;
	jsdouble			dval;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSVectorGetVector(context, this, &vector)) return NO;
	JS_ValueToNumber(context, *value, &dval);
	
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
			return NO;
	}
	
	return JSVectorSetVector(context, this, vector);
}


static JSBool VectorConvert(JSContext *context, JSObject *this, JSType type, jsval *outValue)
{
	Vector					vector;
	
	switch (type)
	{
		// We could return magnitude for JSTYPE_NUMBER, but that seems incogruous in a language without operator overloading.
		case JSTYPE_BOOLEAN:
			// Return true if vector is non-zero
			if (!JSVectorGetVector(context, this, &vector))  return NO;
			*outValue = BOOLEAN_TO_JSVAL(vector_equal(vector, kZeroVector));
			return YES;
		
		case JSTYPE_VOID:		// Used for string concatenation.
		case JSTYPE_STRING:
			// Return description of vector
			if (!JSVectorGetVector(context, this, &vector))  return NO;
			*outValue = [VectorDescription(vector) javaScriptValueInContext:context];
			return YES;
		
		default:
			// Contrary to what passes for documentation, JS_ConvertStub is not a no-op.
			return JS_ConvertStub(context, this, type, outValue);
	}
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
	Vector					vector;
	Vector					*private = NULL;
	
	private = malloc(sizeof *private);
	if (private == NULL)  return NO;
	
	if (!VectorFromArgumentList(context, argc, argv, &vector, NULL))  vector = kZeroVector;
	
	*private = vector;
	
	if (!JS_SetPrivate(context, this, private))
	{
		free(private);
		return NO;
	}
	
	return YES;
}


static JSBool VectorEquality(JSContext *context, JSObject *this, jsval value, JSBool *outEqual)
{
	Vector					thisv, thatv;
	
	if (!JSVAL_IS_OBJECT(value)) return NO;
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	if (!JSVectorGetVector(context, JSVAL_TO_OBJECT(value), &thatv)) return NO;
	
	*outEqual = vector_equal(thisv, thatv);
	return YES;
}


static JSBool VectorAdd(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv, result;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	if (!VectorFromArgumentList(context, argc, argv, &thatv, NULL)) return NO;
	
	result = vector_add(thisv, thatv);
	
	return VectorToJSValue(context, result, outResult);
}


static JSBool VectorSubtract(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv, result;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	if (!VectorFromArgumentList(context, argc, argv, &thatv, NULL)) return NO;
	
	result = vector_subtract(thisv, thatv);
	
	return VectorToJSValue(context, result, outResult);
}


static JSBool VectorDistanceTo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv;
	GLfloat					result;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	if (!VectorFromArgumentList(context, argc, argv, &thatv, NULL)) return NO;
	
	result = distance(thisv, thatv);
	
	return JS_NewDoubleValue(context, result, outResult);
}


static JSBool VectorSquaredDistanceTo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv;
	GLfloat					result;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	if (!VectorFromArgumentList(context, argc, argv, &thatv, NULL)) return NO;
	
	result = distance2(thisv, thatv);
	
	return JS_NewDoubleValue(context, result, outResult);
}


static JSBool VectorMultiply(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, result;
	double					scalar;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	if (!JS_ValueToNumber(context, argv[0], &scalar)) return NO;
	
	result = vector_multiply_scalar(thisv, scalar);
	
	return VectorToJSValue(context, result, outResult);
}


static JSBool VectorDot(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv;
	GLfloat					result;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	if (!VectorFromArgumentList(context, argc, argv, &thatv, NULL)) return NO;
	
	result = dot_product(thisv, thatv);
	
	return JS_NewDoubleValue(context, result, outResult);
}


static JSBool VectorAngleTo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv;
	GLfloat					result;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	if (!VectorFromArgumentList(context, argc, argv, &thatv, NULL)) return NO;
	
	result = acosf(dot_product(vector_normal(thisv), vector_normal(thatv)));
	
	return JS_NewDoubleValue(context, result, outResult);
}


static JSBool VectorCross(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv, result;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	if (!VectorFromArgumentList(context, argc, argv, &thatv, NULL)) return NO;
	
	result = true_cross_product(thisv, thatv);
	
	return VectorToJSValue(context, result, outResult);
}


static JSBool VectorTripleProduct(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, thatv, theotherv;
	GLfloat					result;
	uintN					consumed;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	if (!VectorFromArgumentList(context, argc, argv, &thatv, &consumed)) return NO;
	if (!VectorFromArgumentList(context, argc + consumed, argv, &theotherv, NULL)) return NO;
	
	result = triple_product(thisv, thatv, theotherv);
	
	return JS_NewDoubleValue(context, result, outResult);
}


static JSBool VectorDirection(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv, result;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	
	result = vector_normal(thisv);
	
	return VectorToJSValue(context, result, outResult);
}


static JSBool VectorMagnitude(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv;
	GLfloat					result;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	
	result = magnitude(thisv);
	
	return JS_NewDoubleValue(context, result, outResult);
}


static JSBool VectorSquaredMagnitude(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Vector					thisv;
	GLfloat					result;
	
	if (!JSVectorGetVector(context, this, &thisv)) return NO;
	
	result = magnitude2(thisv);
	
	return JS_NewDoubleValue(context, result, outResult);
}
