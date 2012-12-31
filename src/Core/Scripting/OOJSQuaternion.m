/*

OOJSQuaternion.m

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


static BOOL GetThisQuaternion(JSContext *context, JSObject *quaternionObj, Quaternion *outQuaternion, NSString *method)  NONNULL_FUNC;


static JSBool QuaternionGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool QuaternionSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);
static void QuaternionFinalize(JSContext *context, JSObject *this);
static JSBool QuaternionConstruct(JSContext *context, uintN argc, jsval *vp);

// Methods
static JSBool QuaternionToString(JSContext *context, uintN argc, jsval *vp);
static JSBool QuaternionToSource(JSContext *context, uintN argc, jsval *vp);
static JSBool QuaternionMultiply(JSContext *context, uintN argc, jsval *vp);
static JSBool QuaternionDot(JSContext *context, uintN argc, jsval *vp);
static JSBool QuaternionRotate(JSContext *context, uintN argc, jsval *vp);
static JSBool QuaternionRotateX(JSContext *context, uintN argc, jsval *vp);
static JSBool QuaternionRotateY(JSContext *context, uintN argc, jsval *vp);
static JSBool QuaternionRotateZ(JSContext *context, uintN argc, jsval *vp);
static JSBool QuaternionNormalize(JSContext *context, uintN argc, jsval *vp);
static JSBool QuaternionConjugate(JSContext *context, uintN argc, jsval *vp);
static JSBool QuaternionVectorForward(JSContext *context, uintN argc, jsval *vp);
static JSBool QuaternionVectorUp(JSContext *context, uintN argc, jsval *vp);
static JSBool QuaternionVectorRight(JSContext *context, uintN argc, jsval *vp);
static JSBool QuaternionToArray(JSContext *context, uintN argc, jsval *vp);

// Static methods
static JSBool QuaternionStaticRandom(JSContext *context, uintN argc, jsval *vp);


static JSClass sQuaternionClass =
{
	"Quaternion",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,		// addProperty
	JS_PropertyStub,		// delProperty
	QuaternionGetProperty,	// getProperty
	QuaternionSetProperty,	// setProperty
	JS_EnumerateStub,		// enumerate
	JS_ResolveStub,			// resolve
	JS_ConvertStub,			// convert
	QuaternionFinalize,		// finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
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
	{ "w",						kQuaternion_w,				OOJS_PROP_READWRITE_CB },
	{ "x",						kQuaternion_x,				OOJS_PROP_READWRITE_CB },
	{ "y",						kQuaternion_y,				OOJS_PROP_READWRITE_CB },
	{ "z",						kQuaternion_z,				OOJS_PROP_READWRITE_CB },
	{ 0 }
};


static JSFunctionSpec sQuaternionMethods[] =
{
	// JS name					Function					min args
	{ "toString",				QuaternionToString,			0, },
	{ "toSource",				QuaternionToSource,			0, },
	{ "dot",					QuaternionDot,				1, },
	{ "multiply",				QuaternionMultiply,			1, },
	{ "normalize",				QuaternionNormalize,		0, },
	{ "conjugate",				QuaternionConjugate,		0, },
	{ "rotate",					QuaternionRotate,			2, },
	{ "rotateX",				QuaternionRotateX,			1, },
	{ "rotateY",				QuaternionRotateY,			1, },
	{ "rotateZ",				QuaternionRotateZ,			1, },
	{ "toArray",				QuaternionToArray,			0, },
	{ "vectorForward",			QuaternionVectorForward,	0, },
	{ "vectorRight",			QuaternionVectorRight,		0, },
	{ "vectorUp",				QuaternionVectorUp,			0, },
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
	sQuaternionPrototype = JS_InitClass(context, global, NULL, &sQuaternionClass, QuaternionConstruct, 4, sQuaternionProperties, sQuaternionMethods, NULL, sQuaternionStaticMethods);
}


JSObject *JSQuaternionWithQuaternion(JSContext *context, Quaternion quaternion)
{
	OOJS_PROFILE_ENTER
	
	JSObject				*result = NULL;
	Quaternion				*private = NULL;
	
	private = malloc(sizeof *private);
	if (EXPECT_NOT(private == NULL))  return NULL;
	
	*private = quaternion;
	
	result = JS_NewObject(context, &sQuaternionClass, sQuaternionPrototype, NULL);
	if (result != NULL)
	{
		if (!JS_SetPrivate(context, result, private))  result = NULL;
	}
	
	if (EXPECT_NOT(result == NULL)) free(private);
	
	return result;
	
	OOJS_PROFILE_EXIT
}


BOOL QuaternionToJSValue(JSContext *context, Quaternion quaternion, jsval *outValue)
{
	OOJS_PROFILE_ENTER
	
	JSObject				*object = NULL;
	
	assert(outValue != NULL);
	
	object = JSQuaternionWithQuaternion(context, quaternion);
	if (EXPECT_NOT(object == NULL)) return NO;
	
	*outValue = OBJECT_TO_JSVAL(object);
	return YES;
	
	OOJS_PROFILE_EXIT
}


BOOL JSValueToQuaternion(JSContext *context, jsval value, Quaternion *outQuaternion)
{
	if (EXPECT_NOT(!JSVAL_IS_OBJECT(value)))  return NO;
	
	return JSObjectGetQuaternion(context, JSVAL_TO_OBJECT(value), outQuaternion);
}


#if OO_DEBUG

typedef struct
{
	NSUInteger			quatCount;
	NSUInteger			entityCount;
	NSUInteger			arrayCount;
	NSUInteger			protoCount;
	NSUInteger			nullCount;
	NSUInteger			failCount;
} QuaternionStatistics;
static QuaternionStatistics sQuaternionConversionStats;


@implementation PlayerEntity (JSQuaternionStatistics)

// :setM quatStats PS.callObjC("reportJSQuaternionStatistics")
// :quatStats

- (NSString *) reportJSQuaternionStatistics
{
	QuaternionStatistics *stats = &sQuaternionConversionStats;
	
	NSUInteger sum = stats->quatCount + stats->entityCount + stats->arrayCount + stats->protoCount;
	double convFac = 100.0 / sum;
	
	return [NSString stringWithFormat:
		   @"quaternion-to-quaternion conversions: %lu (%g %%)\n"
			"    entity-to-quaternion conversions: %lu (%g %%)\n"
			"     array-to-quaternion conversions: %lu (%g %%)\n"
			"       prototype-to-zero conversions: %lu (%g %%)\n"
			"                    null conversions: %lu (%g %%)\n"
			"                  failed conversions: %lu (%g %%)\n"
			"                               total: %lu",
			(long)stats->quatCount, stats->quatCount * convFac,
			(long)stats->entityCount, stats->entityCount * convFac,
			(long)stats->arrayCount, stats->arrayCount * convFac,
			(long)stats->protoCount, stats->protoCount * convFac,
			(long)stats->nullCount, stats->nullCount * convFac,
			(long)stats->failCount, stats->failCount * convFac,
			(long)sum];
}


- (void) clearJSQuaternionStatistics
{
	memset(&sQuaternionConversionStats, 0, sizeof sQuaternionConversionStats);
}

@end

#define COUNT(FIELD) do { sQuaternionConversionStats.FIELD++; } while (0)

#else

#define COUNT(FIELD) do {} while (0)

#endif


BOOL JSObjectGetQuaternion(JSContext *context, JSObject *quaternionObj, Quaternion *outQuaternion)
{
	OOJS_PROFILE_ENTER
	
	assert(outQuaternion != NULL);
	
	Quaternion				*private = NULL;
	jsuint					arrayLength;
	jsval					arrayW, arrayX, arrayY, arrayZ;
	jsdouble				dVal;
	
	// quaternionObj can legitimately be NULL, e.g. when JS_NULL is converted to a JSObject *.
	if (EXPECT_NOT(quaternionObj == NULL))
	{
		COUNT(nullCount);
		return NO;
	}
	
	// If this is a (JS) Quaternion...
	private = JS_GetInstancePrivate(context, quaternionObj, &sQuaternionClass, NULL);
	if (EXPECT(private != NULL))
	{
		COUNT(quatCount);
		*outQuaternion = *private;
		return YES;
	}
	
	// If it's an array...
	if (EXPECT(JS_IsArrayObject(context, quaternionObj)))
	{
		// ...and it has exactly four elements...
		if (JS_GetArrayLength(context, quaternionObj, &arrayLength) && arrayLength == 4)
		{
			if (JS_LookupElement(context, quaternionObj, 0, &arrayW) &&
				JS_LookupElement(context, quaternionObj, 1, &arrayX) &&
				JS_LookupElement(context, quaternionObj, 2, &arrayY) &&
				JS_LookupElement(context, quaternionObj, 3, &arrayZ))
			{
				// ...se the four numbers as [w, x, y, z]
				if (!JS_ValueToNumber(context, arrayW, &dVal))  return NO;
				outQuaternion->w = dVal;
				if (!JS_ValueToNumber(context, arrayX, &dVal))  return NO;
				outQuaternion->x = dVal;
				if (!JS_ValueToNumber(context, arrayY, &dVal))  return NO;
				outQuaternion->y = dVal;
				if (!JS_ValueToNumber(context, arrayZ, &dVal))  return NO;
				outQuaternion->z = dVal;
				
				COUNT(arrayCount);
				return YES;
			}
		}
	}
	
	// If it's an entity, use its orientation.
	if (OOJSIsMemberOfSubclass(context, quaternionObj, JSEntityClass()))
	{
		COUNT(entityCount);
		Entity *entity = JS_GetPrivate(context, quaternionObj);
		*outQuaternion = [entity orientation];
		return YES;
	}
	
	/*
		If it's actually a Quaternion but with no private field (this happens for
		Quaternion.prototype)...
		
		NOTE: it would be prettier to do this at the top when we handle normal
		Quaternions, but it's a rare case which should be kept off the fast path.
	*/
	if (JS_InstanceOf(context, quaternionObj, &sQuaternionClass, NULL))
	{
		COUNT(protoCount);
		*outQuaternion = kZeroQuaternion;
		return YES;
	}
	
	COUNT(failCount);
	return NO;
	
	OOJS_PROFILE_EXIT
}


static BOOL GetThisQuaternion(JSContext *context, JSObject *quaternionObj, Quaternion *outQuaternion, NSString *method)
{
	if (EXPECT(JSObjectGetQuaternion(context, quaternionObj, outQuaternion)))  return YES;
	
	jsval arg = OBJECT_TO_JSVAL(quaternionObj);
	OOJSReportBadArguments(context, @"Quaternion", method, 1, &arg, @"Invalid target object", @"Quaternion");
	return NO;
}


BOOL JSQuaternionSetQuaternion(JSContext *context, JSObject *quaternionObj, Quaternion quaternion)
{
	OOJS_PROFILE_ENTER
	
	Quaternion				*private = NULL;
	
	assert(quaternionObj != NULL);
	
	private = JS_GetInstancePrivate(context, quaternionObj, &sQuaternionClass, NULL);
	if (private != NULL)	// If this is a (JS) Quaternion...
	{
		*private = quaternion;
		return YES;
	}
	
	if (JS_InstanceOf(context, quaternionObj, &sQuaternionClass, NULL))
	{
		// Silently fail for the prototype.
		return YES;
	}
	
	return NO;
	
	OOJS_PROFILE_EXIT
}


static BOOL QuaternionFromArgumentListNoErrorInternal(JSContext *context, uintN argc, jsval *argv, Quaternion *outQuaternion, uintN *outConsumed, BOOL permitNumberList)
{
	OOJS_PROFILE_ENTER
	
	double				w, x, y, z;
	
	if (EXPECT_NOT(argc == 0))  return NO;
	assert(argv != NULL && outQuaternion != NULL);
	
	if (outConsumed != NULL)  *outConsumed = 0;
	
	// Is first object a quaternion or entity?
	if (JSVAL_IS_OBJECT(argv[0]))
	{
		if (JSObjectGetQuaternion(context, JSVAL_TO_OBJECT(argv[0]), outQuaternion))
		{
			if (outConsumed != NULL)  *outConsumed = 1;
			return YES;
		}
	}
	
	if (!permitNumberList)  return NO;
	
	// As a special case for QuaternionConstruct(), look for four numbers.
	if (EXPECT_NOT(argc < 4))  return NO;
	
	// Given a string, JS_ValueToNumber() returns YES but provides a NaN number.
	if (EXPECT_NOT(!JS_ValueToNumber(context, argv[0], &w) || isnan(w)))  return NO;
	if (EXPECT_NOT(!JS_ValueToNumber(context, argv[1], &x) || isnan(x)))  return NO;
	if (EXPECT_NOT(!JS_ValueToNumber(context, argv[2], &y) || isnan(y)))  return NO;
	if (EXPECT_NOT(!JS_ValueToNumber(context, argv[3], &z) || isnan(z)))  return NO;
	
	// We got our four numbers.
	*outQuaternion = make_quaternion(w, x, y, z);
	if (outConsumed != NULL)  *outConsumed = 4;

	return YES;
	
	OOJS_PROFILE_EXIT
}


// EMMSTRAN: remove outConsumed, since it can only be 1 except in failure (constructor is an exception, but it uses QuaternionFromArgumentListNoErrorInternal() directly).
BOOL QuaternionFromArgumentList(JSContext *context, NSString *scriptClass, NSString *function, uintN argc, jsval *argv, Quaternion *outQuaternion, uintN *outConsumed)
{
	if (QuaternionFromArgumentListNoErrorInternal(context, argc, argv, outQuaternion, outConsumed, NO))  return YES;
	else
	{
		OOJSReportBadArguments(context, scriptClass, function, argc, argv,
							   @"Could not construct quaternion from parameters",
							   @"Quaternion, Entity or four numbers");
		return NO;
	}
}


BOOL QuaternionFromArgumentListNoError(JSContext *context, uintN argc, jsval *argv, Quaternion *outQuaternion, uintN *outConsumed)
{
	return QuaternionFromArgumentListNoErrorInternal(context, argc, argv, outQuaternion, outConsumed, NO);
}


// *** Implementation stuff ***

static JSBool QuaternionGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_PROFILE_ENTER
	
	Quaternion			quaternion;
	GLfloat				fValue;
	
	if (EXPECT_NOT(!JSObjectGetQuaternion(context, this, &quaternion))) return NO;
	
	switch (JSID_TO_INT(propID))
	{
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
			OOJSReportBadPropertySelector(context, this, propID, sQuaternionProperties);
			return NO;
	}
	
	return JS_NewNumberValue(context, fValue, value);
	
	OOJS_PROFILE_EXIT
}


static JSBool QuaternionSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_PROFILE_ENTER
	
	Quaternion			quaternion;
	jsdouble			dval;
	
	if (EXPECT_NOT(!JSObjectGetQuaternion(context, this, &quaternion))) return NO;
	if (EXPECT_NOT(!JS_ValueToNumber(context, *value, &dval)))
	{
		OOJSReportBadPropertyValue(context, this, propID, sQuaternionProperties, *value);
		return NO;
	}
	
	switch (JSID_TO_INT(propID))
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
			OOJSReportBadPropertySelector(context, this, propID, sQuaternionProperties);
			return NO;
	}
	
	return JSQuaternionSetQuaternion(context, this, quaternion);
	
	OOJS_PROFILE_EXIT
}


static void QuaternionFinalize(JSContext *context, JSObject *this)
{
	Quaternion				*private = NULL;
	
	private = JS_GetInstancePrivate(context, this, &sQuaternionClass, NULL);
	if (private != NULL)
	{
		free(private);
	}
}


static JSBool QuaternionConstruct(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	Quaternion				quaternion = kZeroQuaternion;
	Quaternion				*private = NULL;
	JSObject				*this = NULL;
	
	private = malloc(sizeof *private);
	if (EXPECT_NOT(private == NULL))  return NO;
	
	this = JS_NewObject(context, &sQuaternionClass, NULL, NULL);
	if (EXPECT_NOT(this == NULL))  return NO;
	
	if (argc != 0)
	{
		if (EXPECT_NOT(!QuaternionFromArgumentListNoErrorInternal(context, argc, OOJS_ARGV, &quaternion, NULL, YES)))
		{
			free(private);
			OOJSReportBadArguments(context, NULL, NULL, argc, OOJS_ARGV,
								   @"Could not construct quaternion from parameters",
								   @"Quaternion, Entity or array of four numbers");
			return NO;
		}
	}
	
	*private = quaternion;
	
	if (!JS_SetPrivate(context, this, private))
	{
		free(private);
		return NO;
	}
	
	OOJS_RETURN_JSOBJECT(this);
	
	OOJS_PROFILE_EXIT
}


// *** Methods ***

// toString() : String
static JSBool QuaternionToString(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	Quaternion				thisq;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, @"toString"))) return NO;
	
	OOJS_RETURN_OBJECT(QuaternionDescription(thisq));
	
	OOJS_NATIVE_EXIT
}


// toSource() : String
static JSBool QuaternionToSource(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	Quaternion				thisq;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, @"toSource"))) return NO;
	
	NSString *str = [NSString stringWithFormat:@"Quaternion(%g, %g, %g, %g)", thisq.w, thisq.x, thisq.y, thisq.z];
	OOJS_RETURN_OBJECT(str);
	
	OOJS_NATIVE_EXIT
}


// multiply(q : quaternionExpression) : Quaternion
static JSBool QuaternionMultiply(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	Quaternion				thisq, thatq, result;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, @"multiply"))) return NO;
	if (EXPECT_NOT(!QuaternionFromArgumentList(context, @"Quaternion", @"multiply", argc, OOJS_ARGV, &thatq, NULL)))  return NO;
	
	result = quaternion_multiply(thisq, thatq);
	
	OOJS_RETURN_QUATERNION(result);
	
	OOJS_PROFILE_EXIT
}


// dot(q : quaternionExpression) : Number
static JSBool QuaternionDot(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	Quaternion				thisq, thatq;
	double					result;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, @"dot"))) return NO;
	if (EXPECT_NOT(!QuaternionFromArgumentList(context, @"Quaternion", @"dot", argc, OOJS_ARGV, &thatq, NULL)))  return NO;
	
	result = quaternion_dot_product(thisq, thatq);
	
	OOJS_RETURN_DOUBLE(result);
	
	OOJS_PROFILE_EXIT
}


// rotate(axis : vectorExpression, angle : Number) : Quaternion
static JSBool QuaternionRotate(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	Quaternion				thisq;
	Vector					axis;
	double					angle;
	uintN					consumed;
	jsval					*argv = OOJS_ARGV;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, @"rotate"))) return NO;
	if (EXPECT_NOT(!VectorFromArgumentList(context, @"Quaternion", @"rotate", argc, argv, &axis, &consumed)))  return NO;
	argv += consumed;
	argc -= consumed;
	if (argc > 0)
	{
		if (EXPECT_NOT(!OOJSArgumentListGetNumber(context, @"Quaternion", @"rotate", argc, argv, &angle, NULL)))  return NO;
		quaternion_rotate_about_axis(&thisq, axis, angle);
	}
	// Else no angle specified, so don't rotate and pass value through unchanged.
	
	OOJS_RETURN_QUATERNION(thisq);
	
	OOJS_PROFILE_EXIT
}


// rotateX(angle : Number) : Quaternion
static JSBool QuaternionRotateX(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	Quaternion				quat;
	double					angle;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &quat, @"rotateX"))) return NO;
	if (EXPECT_NOT(!OOJSArgumentListGetNumber(context, @"Quaternion", @"rotateX", argc, OOJS_ARGV, &angle, NULL)))  return NO;
	
	quaternion_rotate_about_x(&quat, angle);
	
	OOJS_RETURN_QUATERNION(quat);
	
	OOJS_PROFILE_EXIT
}


// rotateY(angle : Number) : Quaternion
static JSBool QuaternionRotateY(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	Quaternion				quat;
	double					angle;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &quat, @"rotateY"))) return NO;
	if (EXPECT_NOT(!OOJSArgumentListGetNumber(context, @"Quaternion", @"rotateY", argc, OOJS_ARGV, &angle, NULL)))  return NO;
	
	quaternion_rotate_about_y(&quat, angle);
	
	OOJS_RETURN_QUATERNION(quat);
	
	OOJS_PROFILE_EXIT
}


// rotateZ(angle : Number) : Quaternion
static JSBool QuaternionRotateZ(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	Quaternion				quat;
	double					angle;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &quat, @"rotateZ"))) return NO;
	if (EXPECT_NOT(!OOJSArgumentListGetNumber(context, @"Quaternion", @"rotateZ", argc, OOJS_ARGV, &angle, NULL)))  return NO;
	
	quaternion_rotate_about_z(&quat, angle);
	
	OOJS_RETURN_QUATERNION(quat);
	
	OOJS_PROFILE_EXIT
}


// normalize() : Quaternion
static JSBool QuaternionNormalize(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	Quaternion				quat;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &quat, @"normalize"))) return NO;
	
	quaternion_normalize(&quat);
	
	OOJS_RETURN_QUATERNION(quat);
	
	OOJS_PROFILE_EXIT
}


// conjugate() : Quaternion
static JSBool QuaternionConjugate(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
		Quaternion				quat, result;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &quat, @"conjugate"))) return NO;
	
	result = quaternion_conjugate(quat);
	
	OOJS_RETURN_QUATERNION(result);
	
	OOJS_PROFILE_EXIT
}


// vectorForward() : Vector
static JSBool QuaternionVectorForward(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	Quaternion				thisq;
	Vector					result;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, @"vectorForward"))) return NO;
	
	result = vector_forward_from_quaternion(thisq);
	
	OOJS_RETURN_VECTOR(result);
	
	OOJS_PROFILE_EXIT
}


// vectorUp() : Vector
static JSBool QuaternionVectorUp(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	Quaternion				thisq;
	Vector					result;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, @"vectorUp"))) return NO;
	
	result = vector_up_from_quaternion(thisq);
	
	OOJS_RETURN_VECTOR(result);
	
	OOJS_PROFILE_EXIT
}


// vectorRight() : Vector
static JSBool QuaternionVectorRight(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	Quaternion				thisq;
	Vector					result;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, @"vectorRight"))) return NO;
	
	result = vector_right_from_quaternion(thisq);
	
	OOJS_RETURN_VECTOR(result);
	
	OOJS_PROFILE_EXIT
}


// toArray() : Array
static JSBool QuaternionToArray(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	Quaternion				thisq;
	JSObject				*result = NULL;
	BOOL					OK = YES;
	jsval					nVal;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, @"toArray"))) return NO;
	
	result = JS_NewArrayObject(context, 0, NULL);
	if (result != NULL)
	{
		// We do this at the top because *outResult is a GC root.
		OOJS_SET_RVAL(OBJECT_TO_JSVAL(result));
		
		if (JS_NewNumberValue(context, thisq.w, &nVal))  JS_SetElement(context, result, 0, &nVal);
		else  OK = NO;
		if (JS_NewNumberValue(context, thisq.x, &nVal))  JS_SetElement(context, result, 1, &nVal);
		else  OK = NO;
		if (JS_NewNumberValue(context, thisq.y, &nVal))  JS_SetElement(context, result, 2, &nVal);
		else  OK = NO;
		if (JS_NewNumberValue(context, thisq.z, &nVal))  JS_SetElement(context, result, 3, &nVal);
		else  OK = NO;
	}
	
	if (!OK)  OOJS_SET_RVAL(JSVAL_VOID);
	return YES;
	
	OOJS_PROFILE_EXIT
}


// *** Static methods ***

// random() : Quaternion
static JSBool QuaternionStaticRandom(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	OOJS_RETURN_QUATERNION(OORandomQuaternion());
	
	OOJS_PROFILE_EXIT
}
