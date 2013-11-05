/*

OOJSVector.m

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


static BOOL GetThisVector(JSContext *context, JSObject *vectorObj, HPVector *outVector, NSString *method)  NONNULL_FUNC;


static JSBool VectorGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool VectorSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);
static void VectorFinalize(JSContext *context, JSObject *this);
static JSBool VectorConstruct(JSContext *context, uintN argc, jsval *vp);

// Methods
static JSBool VectorToString(JSContext *context, uintN argc, jsval *vp);
static JSBool VectorToSource(JSContext *context, uintN argc, jsval *vp);
static JSBool VectorAdd(JSContext *context, uintN argc, jsval *vp);
static JSBool VectorSubtract(JSContext *context, uintN argc, jsval *vp);
static JSBool VectorDistanceTo(JSContext *context, uintN argc, jsval *vp);
static JSBool VectorSquaredDistanceTo(JSContext *context, uintN argc, jsval *vp);
static JSBool VectorMultiply(JSContext *context, uintN argc, jsval *vp);
static JSBool VectorDot(JSContext *context, uintN argc, jsval *vp);
static JSBool VectorAngleTo(JSContext *context, uintN argc, jsval *vp);
static JSBool VectorFromCoordinateSystem(JSContext *context, uintN argc, jsval *vp);
static JSBool VectorToCoordinateSystem(JSContext *context, uintN argc, jsval *vp);
static JSBool VectorCross(JSContext *context, uintN argc, jsval *vp);
static JSBool VectorTripleProduct(JSContext *context, uintN argc, jsval *vp);
static JSBool VectorDirection(JSContext *context, uintN argc, jsval *vp);
static JSBool VectorMagnitude(JSContext *context, uintN argc, jsval *vp);
static JSBool VectorSquaredMagnitude(JSContext *context, uintN argc, jsval *vp);
static JSBool VectorRotationTo(JSContext *context, uintN argc, jsval *vp);
static JSBool VectorRotateBy(JSContext *context, uintN argc, jsval *vp);
static JSBool VectorToArray(JSContext *context, uintN argc, jsval *vp);

// Static methods
static JSBool VectorStaticInterpolate(JSContext *context, uintN argc, jsval *vp);
static JSBool VectorStaticRandom(JSContext *context, uintN argc, jsval *vp);
static JSBool VectorStaticRandomDirection(JSContext *context, uintN argc, jsval *vp);
static JSBool VectorStaticRandomDirectionAndLength(JSContext *context, uintN argc, jsval *vp);


static JSClass sVectorClass =
{
	"Vector3D",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,		// addProperty
	JS_PropertyStub,		// delProperty
	VectorGetProperty,		// getProperty
	VectorSetProperty,		// setProperty
	JS_EnumerateStub,		// enumerate
	JS_ResolveStub,			// resolve
	JS_ConvertStub,			// convert
	VectorFinalize,			// finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
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
	{ "x",						kVector_x,					OOJS_PROP_READWRITE_CB },
	{ "y",						kVector_y,					OOJS_PROP_READWRITE_CB },
	{ "z",						kVector_z,					OOJS_PROP_READWRITE_CB },
	{ 0 }
};


static JSFunctionSpec sVectorMethods[] =
{
	// JS name					Function					min args
	{ "toSource",				VectorToSource,				0, },
	{ "toString",				VectorToString,				0, },
	{ "add",					VectorAdd,					1, },
	{ "angleTo",				VectorAngleTo,				1, },
	{ "cross",					VectorCross,				1, },
	{ "direction",				VectorDirection,			0, },
	{ "distanceTo",				VectorDistanceTo,			1, },
	{ "dot",					VectorDot,					1, },
	{ "fromCoordinateSystem",	VectorFromCoordinateSystem,	1, },
	{ "magnitude",				VectorMagnitude,			0, },
	{ "multiply",				VectorMultiply,				1, },
	{ "rotateBy",				VectorRotateBy,				1, },
	{ "rotationTo",				VectorRotationTo,			1, },
	{ "squaredDistanceTo",		VectorSquaredDistanceTo,	1, },
	{ "squaredMagnitude",		VectorSquaredMagnitude,		0, },
	{ "subtract",				VectorSubtract,				1, },
	{ "toArray",				VectorToArray,				0, },
	{ "toCoordinateSystem",		VectorToCoordinateSystem,	1, },
	{ "tripleProduct",			VectorTripleProduct,		2, },
	{ 0 }
};


static JSFunctionSpec sVectorStaticMethods[] =
{
	// JS name						Function							min args
	{ "interpolate",				VectorStaticInterpolate,			3, },
	{ "random",						VectorStaticRandom,					0, },
	{ "randomDirection",			VectorStaticRandomDirection, 		0, },
	{ "randomDirectionAndLength",	VectorStaticRandomDirectionAndLength, 0, },
	{ 0 }
};


// *** Public ***

void InitOOJSVector(JSContext *context, JSObject *global)
{
	sVectorPrototype = JS_InitClass(context, global, NULL, &sVectorClass, VectorConstruct, 0, sVectorProperties, sVectorMethods, NULL, sVectorStaticMethods);
}


JSObject *JSVectorWithVector(JSContext *context, Vector vector)
{
	OOJS_PROFILE_ENTER
	
	JSObject				*result = NULL;
	HPVector					*private = NULL;
	
	private = malloc(sizeof *private);
	if (EXPECT_NOT(private == NULL))  return NULL;
	
	*private = vectorToHPVector(vector);
	
	result = JS_NewObject(context, &sVectorClass, sVectorPrototype, NULL);
	if (result != NULL)
	{
		if (EXPECT_NOT(!JS_SetPrivate(context, result, private)))  result = NULL;
	}
	
	if (EXPECT_NOT(result == NULL)) free(private);
	
	return result;
	
	OOJS_PROFILE_EXIT
}


BOOL VectorToJSValue(JSContext *context, Vector vector, jsval *outValue)
{
	OOJS_PROFILE_ENTER
	
	JSObject				*object = NULL;
	
	assert(outValue != NULL);
	
	object = JSVectorWithVector(context, vector);
	if (EXPECT_NOT(object == NULL)) return NO;
	
	*outValue = OBJECT_TO_JSVAL(object);
	return YES;
	
	OOJS_PROFILE_EXIT
}

JSObject *JSVectorWithHPVector(JSContext *context, HPVector vector)
{
	OOJS_PROFILE_ENTER
	
	JSObject				*result = NULL;
	HPVector					*private = NULL;
	
	private = malloc(sizeof *private);
	if (EXPECT_NOT(private == NULL))  return NULL;
	
	*private = vector;
	
	result = JS_NewObject(context, &sVectorClass, sVectorPrototype, NULL);
	if (result != NULL)
	{
		if (EXPECT_NOT(!JS_SetPrivate(context, result, private)))  result = NULL;
	}
	
	if (EXPECT_NOT(result == NULL)) free(private);
	
	return result;
	
	OOJS_PROFILE_EXIT
}


BOOL HPVectorToJSValue(JSContext *context, HPVector vector, jsval *outValue)
{
	OOJS_PROFILE_ENTER
	
	JSObject				*object = NULL;
	
	assert(outValue != NULL);
	
	object = JSVectorWithHPVector(context, vector);
	if (EXPECT_NOT(object == NULL)) return NO;
	
	*outValue = OBJECT_TO_JSVAL(object);
	return YES;
	
	OOJS_PROFILE_EXIT
}


BOOL NSPointToVectorJSValue(JSContext *context, NSPoint point, jsval *outValue)
{
	return VectorToJSValue(context, make_vector(point.x, point.y, 0), outValue);
}


BOOL JSValueToHPVector(JSContext *context, jsval value, HPVector *outVector)
{
	if (EXPECT_NOT(!JSVAL_IS_OBJECT(value)))  return NO;
	
	return JSObjectGetVector(context, JSVAL_TO_OBJECT(value), outVector);
}

BOOL JSValueToVector(JSContext *context, jsval value, Vector *outVector)
{
	if (EXPECT_NOT(!JSVAL_IS_OBJECT(value)))  return NO;
	HPVector tmp = kZeroHPVector;
	BOOL result = JSObjectGetVector(context, JSVAL_TO_OBJECT(value), &tmp);
	*outVector = HPVectorToVector(tmp);
	return result;
}


#if OO_DEBUG

typedef struct
{
	NSUInteger			vectorCount;
	NSUInteger			entityCount;
	NSUInteger			arrayCount;
	NSUInteger			protoCount;
	NSUInteger			nullCount;
	NSUInteger			failCount;
} VectorStatistics;
static VectorStatistics sVectorConversionStats;


@implementation PlayerEntity (JSVectorStatistics)

// :setM vectorStats PS.callObjC("reportJSVectorStatistics")
// :vectorStats

- (NSString *) reportJSVectorStatistics
{
	VectorStatistics *stats = &sVectorConversionStats;
	
	NSUInteger sum = stats->vectorCount + stats->entityCount + stats->arrayCount + stats->protoCount;
	double convFac = 100.0 / sum;
	if (sum == 0)  convFac = 0;
	
	return [NSString stringWithFormat:
		   @" vector-to-vector conversions: %lu (%g %%)\n"
			" entity-to-vector conversions: %lu (%g %%)\n"
			"  array-to-vector conversions: %lu (%g %%)\n"
			"prototype-to-zero conversions: %lu (%g %%)\n"
			"             null conversions: %lu (%g %%)\n"
			"           failed conversions: %lu (%g %%)\n"
			"                        total: %lu",
			(long)stats->vectorCount, stats->vectorCount * convFac,
			(long)stats->entityCount, stats->entityCount * convFac,
			(long)stats->arrayCount, stats->arrayCount * convFac,
			(long)stats->protoCount, stats->protoCount * convFac,
			(long)stats->nullCount, stats->nullCount * convFac,
			(long)stats->failCount, stats->failCount * convFac,
			(long)sum];
}


- (void) clearJSVectorStatistics
{
	memset(&sVectorConversionStats, 0, sizeof sVectorConversionStats);
}

@end

#define COUNT(FIELD) do { sVectorConversionStats.FIELD++; } while (0)

#else

#define COUNT(FIELD) do {} while (0)

#endif


BOOL JSObjectGetVector(JSContext *context, JSObject *vectorObj, HPVector *outVector)
{
	OOJS_PROFILE_ENTER
	
	assert(outVector != NULL);
	
	HPVector					*private = NULL;
	jsuint					arrayLength;
	jsval					arrayX, arrayY, arrayZ;
	jsdouble				x, y, z;
	
	// vectorObj can legitimately be NULL, e.g. when JS_NULL is converted to a JSObject *.
	if (EXPECT_NOT(vectorObj == NULL))
	{
		COUNT(nullCount);
		return NO;
	}
	
	// If this is a (JS) Vector...
	private = JS_GetInstancePrivate(context, vectorObj, &sVectorClass, NULL);
	if (EXPECT(private != NULL))
	{
		COUNT(vectorCount);
		*outVector = *private;
		return YES;
	}
	
	// If it's an array...
	if (EXPECT(JS_IsArrayObject(context, vectorObj)))
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
					COUNT(arrayCount);
					*outVector = make_HPvector(x, y, z);
					return YES;
				}
			}
		}
	}
	
	// If it's an entity, use its position.
	if (OOJSIsMemberOfSubclass(context, vectorObj, JSEntityClass()))
	{
		COUNT(entityCount);
		Entity *entity = [(id)JS_GetPrivate(context, vectorObj) weakRefUnderlyingObject];
		*outVector = [entity position];
		return YES;
	}
	
	/*
		If it's actually a Vector3D but with no private field (this happens for
		Vector3D.prototype)...
		
		NOTE: it would be prettier to do this at the top when we handle normal
		Vector3Ds, but it's a rare case which should be kept off the fast path.
	*/
	if (JS_InstanceOf(context, vectorObj, &sVectorClass, NULL))
	{
		COUNT(protoCount);
		*outVector = kZeroHPVector;
		return YES;
	}
	
	COUNT(failCount);
	return NO;
	
	OOJS_PROFILE_EXIT
}


static BOOL GetThisVector(JSContext *context, JSObject *vectorObj, HPVector *outVector, NSString *method)
{
	if (EXPECT(JSObjectGetVector(context, vectorObj, outVector)))  return YES;
	
	jsval arg = OBJECT_TO_JSVAL(vectorObj);
	OOJSReportBadArguments(context, @"Vector3D", method, 1, &arg, @"Invalid target object", @"Vector3D");
	return NO;
}


BOOL JSVectorSetVector(JSContext *context, JSObject *vectorObj, Vector vector)
{
	return JSVectorSetHPVector(context,vectorObj,vectorToHPVector(vector));
}


BOOL JSVectorSetHPVector(JSContext *context, JSObject *vectorObj, HPVector vector)
{
	OOJS_PROFILE_ENTER
	
	HPVector					*private = NULL;
	
	if (EXPECT_NOT(vectorObj == NULL))  return NO;
	
	private = JS_GetInstancePrivate(context, vectorObj, &sVectorClass, NULL);
	if (private != NULL)	// If this is a (JS) Vector...
	{
		*private = vector;
		return YES;
	}
	
	if (JS_InstanceOf(context, vectorObj, &sVectorClass, NULL))
	{
		// Silently fail for the prototype.
		return YES;
	}
	
	return NO;
	
	OOJS_PROFILE_EXIT
}


static BOOL VectorFromArgumentListNoErrorInternal(JSContext *context, uintN argc, jsval *argv, HPVector *outVector, uintN *outConsumed, BOOL permitNumberList)
{
	OOJS_PROFILE_ENTER
	
	double				x, y, z;
	
	if (EXPECT_NOT(argc == 0))  return NO;
	assert(argv != NULL && outVector != NULL);
	
	if (outConsumed != NULL)  *outConsumed = 0;
	
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
	
	// As a special case for VectorConstruct(), look for three numbers.
	if (argc < 3)  return NO;
	
	// Given a string, JS_ValueToNumber() returns YES but provides a NaN number.
	if (EXPECT_NOT(!JS_ValueToNumber(context, argv[0], &x) || isnan(x)))  return NO;
	if (EXPECT_NOT(!JS_ValueToNumber(context, argv[1], &y) || isnan(y)))  return NO;
	if (EXPECT_NOT(!JS_ValueToNumber(context, argv[2], &z) || isnan(z)))  return NO;
	
	// We got our three numbers.
	*outVector = make_HPvector(x, y, z);
	if (outConsumed != NULL)  *outConsumed = 3;
	
	return YES;
	
	OOJS_PROFILE_EXIT
}


// EMMSTRAN: remove outConsumed, since it can only be 1 except in failure (constructor is an exception, but it uses VectorFromArgumentListNoErrorInternal() directly).
BOOL VectorFromArgumentList(JSContext *context, NSString *scriptClass, NSString *function, uintN argc, jsval *argv, HPVector *outVector, uintN *outConsumed)
{
	if (VectorFromArgumentListNoErrorInternal(context, argc, argv, outVector, outConsumed, NO))  return YES;
	else
	{
		OOJSReportBadArguments(context, scriptClass, function, argc, argv,
							   @"Could not construct vector from parameters",
							   @"Vector, Entity or array of three numbers");
		return NO;
	}
}


BOOL VectorFromArgumentListNoError(JSContext *context, uintN argc, jsval *argv, HPVector *outVector, uintN *outConsumed)
{
	return VectorFromArgumentListNoErrorInternal(context, argc, argv, outVector, outConsumed, NO);
}


// *** Implementation stuff ***

static JSBool VectorGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_PROFILE_ENTER
	
	HPVector				vector;
	OOHPScalar				fValue;
	
	if (EXPECT_NOT(!JSObjectGetVector(context, this, &vector)))  return NO;
	
	switch (JSID_TO_INT(propID))
	{
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
			OOJSReportBadPropertySelector(context, this, propID, sVectorProperties);
			return NO;
	}
	
	return JS_NewNumberValue(context, fValue, value);
	
	OOJS_PROFILE_EXIT
}


static JSBool VectorSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_PROFILE_ENTER
	
	HPVector				vector;
	jsdouble			dval;
	
	if (EXPECT_NOT(!JSObjectGetVector(context, this, &vector)))  return NO;
	if (EXPECT_NOT(!JS_ValueToNumber(context, *value, &dval)))
	{
		OOJSReportBadPropertyValue(context, this, propID, sVectorProperties, *value);
		return NO;
	}
	
	switch (JSID_TO_INT(propID))
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
			OOJSReportBadPropertySelector(context, this, propID, sVectorProperties);
			return NO;
	}
	
	return JSVectorSetHPVector(context, this, vector);
	
	OOJS_PROFILE_EXIT
}


static void VectorFinalize(JSContext *context, JSObject *this)
{
	OOJS_PROFILE_ENTER
	
	Vector					*private = NULL;
	
	private = JS_GetInstancePrivate(context, this, &sVectorClass, NULL);
	if (private != NULL)
	{
		free(private);
	}
	
	OOJS_PROFILE_EXIT_VOID
}


static JSBool VectorConstruct(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	HPVector					vector = kZeroHPVector;
	HPVector					*private = NULL;
	JSObject				*this = NULL;
	
	private = malloc(sizeof *private);
	if (EXPECT_NOT(private == NULL))  return NO;
	
	this = JS_NewObject(context, &sVectorClass, NULL, NULL);
	if (EXPECT_NOT(this == NULL))  return NO;
	
	if (argc != 0)
	{
		if (EXPECT_NOT(!VectorFromArgumentListNoErrorInternal(context, argc, OOJS_ARGV, &vector, NULL, YES)))
		{
			free(private);
			OOJSReportBadArguments(context, NULL, NULL, argc, OOJS_ARGV,
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
	
	OOJS_RETURN_JSOBJECT(this);
	
	OOJS_PROFILE_EXIT
}


// *** Methods ***

// toString() : String
static JSBool VectorToString(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	HPVector					thisv;
	
	if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"toString"))) return NO;
	
	OOJS_RETURN_OBJECT(HPVectorDescription(thisv));
	
	OOJS_NATIVE_EXIT
}


// toSource() : String
static JSBool VectorToSource(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	HPVector					thisv;
	
	if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"toSource"))) return NO;
	
	NSString *str = [NSString stringWithFormat:@"Vector3D(%g, %g, %g)", thisv.x, thisv.y, thisv.z];
	OOJS_RETURN_OBJECT(str);
	
	OOJS_NATIVE_EXIT
}


// add(v : vectorExpression) : Vector3D
static JSBool VectorAdd(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	HPVector					thisv, thatv, result;
	
	if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"add"))) return NO;
	if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"add", argc, OOJS_ARGV, &thatv, NULL)))  return NO;
	
	result = HPvector_add(thisv, thatv);
	
	OOJS_RETURN_HPVECTOR(result);
	
	OOJS_PROFILE_EXIT
}


// subtract(v : vectorExpression) : Vector3D
static JSBool VectorSubtract(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	HPVector					thisv, thatv, result;
	
	if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"subtract"))) return NO;
	if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"subtract", argc, OOJS_ARGV, &thatv, NULL)))  return NO;
	
	result = HPvector_subtract(thisv, thatv);
	
	OOJS_RETURN_HPVECTOR(result);
	
	OOJS_PROFILE_EXIT
}


// distanceTo(v : vectorExpression) : Number
static JSBool VectorDistanceTo(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	HPVector					thisv, thatv;
	GLfloat					result;
	
	if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"distanceTo"))) return NO;
	if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"distanceTo", argc, OOJS_ARGV, &thatv, NULL)))  return NO;
	
	result = HPdistance(thisv, thatv);
	
	OOJS_RETURN_DOUBLE(result);
	
	OOJS_PROFILE_EXIT
}


// squaredDistanceTo(v : vectorExpression) : Number
static JSBool VectorSquaredDistanceTo(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	HPVector					thisv, thatv;
	GLfloat					result;
	
	if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"squaredDistanceTo"))) return NO;
	if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"squaredDistanceTo", argc, OOJS_ARGV, &thatv, NULL)))  return NO;
	
	result = HPdistance2(thisv, thatv);
	
	OOJS_RETURN_DOUBLE(result);
	
	OOJS_PROFILE_EXIT
}


// multiply(n : Number) : Vector3D
static JSBool VectorMultiply(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	HPVector					thisv, result;
	double					scalar;
	
	if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"multiply"))) return NO;
	if (EXPECT_NOT(!OOJSArgumentListGetNumber(context, @"Vector3D", @"multiply", argc, OOJS_ARGV, &scalar, NULL)))  return NO;
	
	result = HPvector_multiply_scalar(thisv, scalar);
	
	OOJS_RETURN_HPVECTOR(result);
	
	OOJS_PROFILE_EXIT
}


// dot(v : vectorExpression) : Number
static JSBool VectorDot(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	HPVector					thisv, thatv;
	GLfloat					result;
	
	if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"dot"))) return NO;
	if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"dot", argc, OOJS_ARGV, &thatv, NULL)))  return NO;
	
	result = HPdot_product(thisv, thatv);
	
	OOJS_RETURN_DOUBLE(result);
	
	OOJS_PROFILE_EXIT
}


// angleTo(v : vectorExpression) : Number
static JSBool VectorAngleTo(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	HPVector					thisv, thatv;
	GLfloat					result;
	
	if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"angleTo"))) return NO;
	if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"angleTo", argc, OOJS_ARGV, &thatv, NULL)))  return NO;
	
	result = HPdot_product(HPvector_normal(thisv), HPvector_normal(thatv));
	if (result > 1.0f) result = 1.0f;
	if (result < -1.0f) result = -1.0f;
	// for identical vectors the dot_product sometimes returnes a value > 1.0 because of rounding errors, resulting
	// in an undefined result for the acos.
	result = acos(result);
	
	OOJS_RETURN_DOUBLE(result);
	
	OOJS_PROFILE_EXIT
}


// cross(v : vectorExpression) : Vector3D
static JSBool VectorCross(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	HPVector					thisv, thatv, result;
	
	if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"cross"))) return NO;
	if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"cross", argc, OOJS_ARGV, &thatv, NULL)))  return NO;
	
	result = HPtrue_cross_product(thisv, thatv);
	
	OOJS_RETURN_HPVECTOR(result);
	
	OOJS_PROFILE_EXIT
}


// tripleProduct(v : vectorExpression, u : vectorExpression) : Number
static JSBool VectorTripleProduct(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	HPVector					thisv, thatv, theotherv;
	GLfloat					result;
	uintN					consumed;
	jsval					*argv = OOJS_ARGV;
	
	if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"tripleProduct"))) return NO;
	if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"tripleProduct", argc, argv, &thatv, &consumed)))  return NO;
	argc -= consumed;
	argv += consumed;
	if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"tripleProduct", argc, argv, &theotherv, NULL)))  return NO;
	
	result = HPtriple_product(thisv, thatv, theotherv);
	
	OOJS_RETURN_DOUBLE(result);
	
	OOJS_PROFILE_EXIT
}


// direction() : Vector3D
static JSBool VectorDirection(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	HPVector					thisv, result;
	
	if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"direction"))) return NO;
	
	result = HPvector_normal(thisv);
	
	OOJS_RETURN_HPVECTOR(result);
	
	OOJS_PROFILE_EXIT
}


// magnitude() : Number
static JSBool VectorMagnitude(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	HPVector					thisv;
	GLfloat					result;
	
	if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"magnitude"))) return NO;
	
	result = HPmagnitude(thisv);
	
	OOJS_RETURN_DOUBLE(result);
	
	OOJS_PROFILE_EXIT
}


// squaredMagnitude() : Number
static JSBool VectorSquaredMagnitude(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	HPVector					thisv;
	GLfloat					result;
	
	if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"squaredMagnitude"))) return NO;
	
	result = HPmagnitude2(thisv);
	
	OOJS_RETURN_DOUBLE(result);
	
	OOJS_PROFILE_EXIT
}


// rotationTo(v : vectorExpression [, limit : Number]) : Quaternion
static JSBool VectorRotationTo(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	HPVector					thisv, thatv;
	double					limit;
	BOOL					gotLimit;
	Quaternion				result;
	uintN					consumed;
	jsval					*argv = OOJS_ARGV;
	
	if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"rotationTo"))) return NO;
	if (EXPECT_NOT(!VectorFromArgumentList(context, @"Vector3D", @"rotationTo", argc, OOJS_ARGV, &thatv, &consumed)))  return NO;
	
	argc -= consumed;
	argv += consumed;
	if (argc != 0)	// limit parameter is optional.
	{
		if (EXPECT_NOT(!OOJSArgumentListGetNumber(context, @"Vector3D", @"rotationTo", argc, argv, &limit, NULL)))  return NO;
		gotLimit = YES;
	}
	else gotLimit = NO;
	
	if (gotLimit)  result = quaternion_limited_rotation_between(HPVectorToVector(thisv), HPVectorToVector(thatv), limit);
	else  result = quaternion_rotation_between(HPVectorToVector(thisv), HPVectorToVector(thatv));
	
	OOJS_RETURN_QUATERNION(result);
	
	OOJS_PROFILE_EXIT
}


// rotateBy(q : quaternionExpression) : Vector3D
static JSBool VectorRotateBy(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	HPVector					thisv, result;
	Quaternion				q;
	
	if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"rotateBy"))) return NO;
	if (EXPECT_NOT(!QuaternionFromArgumentList(context, @"Vector3D", @"rotateBy", argc, OOJS_ARGV, &q, NULL)))  return NO;
	
	result = quaternion_rotate_HPvector(q, thisv);
	
	OOJS_RETURN_HPVECTOR(result);
	
	OOJS_PROFILE_EXIT
}


// toArray() : Array
static JSBool VectorToArray(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	HPVector					thisv;
	JSObject				*result = NULL;
	jsval					nVal;
	
	if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"toArray"))) return NO;
	
	result = JS_NewArrayObject(context, 0, NULL);
	if (result != NULL)
	{
		// We do this at the top because the return value slot is a GC root.
		OOJS_SET_RVAL(OBJECT_TO_JSVAL(result));
		
		if (JS_NewNumberValue(context, thisv.x, &nVal) && JS_SetElement(context, result, 0, &nVal) &&
			JS_NewNumberValue(context, thisv.y, &nVal) && JS_SetElement(context, result, 1, &nVal) &&
			JS_NewNumberValue(context, thisv.z, &nVal) && JS_SetElement(context, result, 2, &nVal))
		{
			return YES;
		}
		// If we get here, the conversion and stuffing in the previous condition failed.
		OOJS_SET_RVAL(JSVAL_VOID);
	}
	
	return YES;
	
	OOJS_PROFILE_EXIT
}


// toCoordinateSystem(coordScheme : String)
static JSBool VectorToCoordinateSystem(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	HPVector				thisv;
	NSString			*coordScheme = nil;
	HPVector				result;
	
	if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"toCoordinateSystem"))) return NO;
	
	if (EXPECT_NOT(argc < 1 ||
				   (coordScheme = OOStringFromJSValue(context, OOJS_ARGV[0])) == nil))
	{
		OOJSReportBadArguments(context, @"Vector3D", @"toCoordinateSystem", MIN(argc, 1U), OOJS_ARGV, nil, @"coordinate system");
		return NO;
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	result = [UNIVERSE legacyPositionFrom:thisv asCoordinateSystem:coordScheme];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_HPVECTOR(result);
	
	OOJS_NATIVE_EXIT
}


// fromCoordinateSystem(coordScheme : String)
static JSBool VectorFromCoordinateSystem(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	HPVector				thisv;
	NSString			*coordScheme = nil;
	HPVector				result;
	
	if (EXPECT_NOT(!GetThisVector(context, OOJS_THIS, &thisv, @"fromCoordinateSystem"))) return NO;
	
	if (EXPECT_NOT(argc < 1 ||
				   (coordScheme = OOStringFromJSValue(context, OOJS_ARGV[0])) == nil))
	{
		OOJSReportBadArguments(context, @"Vector3D", @"fromCoordinateSystem", MIN(argc, 1U), OOJS_ARGV, nil, @"coordinate system");
		return NO;
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	NSString *arg = [NSString stringWithFormat:@"%@ %f %f %f", coordScheme, thisv.x, thisv.y, thisv.z];
	result = [UNIVERSE coordinatesFromCoordinateSystemString:arg];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_HPVECTOR(result);
	
	OOJS_NATIVE_EXIT
}


// *** Static methods ***


// interpolate(v : Vector3D, u : Vector3D, alpha : Number) : Vector3D
static JSBool VectorStaticInterpolate(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	HPVector					av, bv;
	double					interp;
	HPVector					result;
	uintN					consumed;
	uintN					inArgc = argc;
	jsval					*argv = OOJS_ARGV;
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
	if (EXPECT_NOT(!OOJSArgumentListGetNumber(context, @"Vector3D", @"interpolate", argc, argv, &interp, NULL)))  return NO;
	
	result = OOHPVectorInterpolate(av, bv, interp);
	
	OOJS_RETURN_HPVECTOR(result);
	
INSUFFICIENT_ARGUMENTS:
	OOJSReportBadArguments(context, @"Vector3D", @"interpolate", inArgc, inArgv, 
								   @"Insufficient parameters",
								   @"vector expression, vector expression and number");
	return NO;
	
	OOJS_PROFILE_EXIT
}


// random([maxLength : Number]) : Vector3D
static JSBool VectorStaticRandom(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	double					maxLength;
	
	if (argc == 0 || !OOJSArgumentListGetNumberNoError(context, argc, OOJS_ARGV, &maxLength, NULL))  maxLength = 1.0;
	
	OOJS_RETURN_HPVECTOR(OOHPVectorRandomSpatial(maxLength));
	
	OOJS_PROFILE_EXIT
}


// randomDirection([scale : Number]) : Vector3D
static JSBool VectorStaticRandomDirection(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	double					scale;
	
	if (argc == 0 || !OOJSArgumentListGetNumberNoError(context, argc, OOJS_ARGV, &scale, NULL))  scale = 1.0;
	
	OOJS_RETURN_HPVECTOR(HPvector_multiply_scalar(OORandomUnitHPVector(), scale));
	
	OOJS_PROFILE_EXIT
}


// randomDirectionAndLength([maxLength : Number]) : Vector3D
static JSBool VectorStaticRandomDirectionAndLength(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	double					maxLength;
	
	if (argc == 0 || !OOJSArgumentListGetNumberNoError(context, argc, OOJS_ARGV, &maxLength, NULL))  maxLength = 1.0;
	
	OOJS_RETURN_HPVECTOR(OOHPVectorRandomRadial(maxLength));
	
	OOJS_PROFILE_EXIT
}
