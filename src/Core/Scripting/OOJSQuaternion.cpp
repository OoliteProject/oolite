/*

OOJSQuaternion.mm

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
#include "OOJavaScriptEngine.h"

#include "OOConstToString.h"
#include "OOJSEntity.h"
#include "OOJSVector.h"

#include "ooscript/JSEngine.hpp"
#include <cstring>
#include "oofnd/String.hpp"

/*
	Retargeted onto the ooscript façade (JSEngine.hpp) per bead oo-45g, the same way bead oo-sdz
	retargeted OOJSVector.mm (the exemplar for this sweep; see its header comment for the full
	rationale). `this` and `private` are renamed to `thisObj`/`priv` because both are reserved
	words once this file compiles as Objective-C++ (ADR-0001).
*/

/*
	C++20 since bead oo-hwae, converted the way bead oo-ppc converted OOJSVector.mm (proposed
	ADR-0056 amendment oo-ppc). The JS class was already C++ on the ooscript façade;
	OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
	(OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false; the debug-build category on
	PlayerEntity became two free functions, which the C++ PlayerEntity's members call (oo-9ht.15).
	Messages to classes that are still Objective-C (Entity) stay as they are, which is why the
	file is still .mm until Phase 4.
*/

namespace ooscript { }
using ooscript::Context;
using ooscript::Object;
using ooscript::Value;
using ooscript::PropertyId;
using ooscript::CallArgs;
using ooscript::ClassDef;
using ooscript::ClassFlag;
using ooscript::PropertyFlag;
using ooscript::PropertySpec;
using ooscript::FunctionSpec;


namespace {
static ooscript::Object sQuaternionPrototype;
} // namespace


namespace {
static bool GetThisQuaternion(ooscript::Context context, ooscript::Object quaternionObj, Quaternion *outQuaternion, const std::string &method)  NONNULL_FUNC;

static bool QuaternionGetProperty(Context cx, Object obj, PropertyId propID, Value *value);
static bool QuaternionSetProperty(Context cx, Object obj, PropertyId propID, bool strict, Value *value);
static void QuaternionFinalize(Context cx, Object obj);
static bool QuaternionConstruct(ooscript::Context cx, ooscript::CallArgs &oojsArgs);

// Methods
static bool QuaternionToString(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool QuaternionToSource(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool QuaternionMultiply(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool QuaternionDot(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool QuaternionRotate(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool QuaternionRotateX(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool QuaternionRotateY(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool QuaternionRotateZ(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool QuaternionNormalize(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool QuaternionConjugate(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool QuaternionVectorForward(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool QuaternionVectorUp(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool QuaternionVectorRight(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool QuaternionToArray(ooscript::Context cx, ooscript::CallArgs &oojsArgs);

// Static methods
static bool QuaternionStaticRandom(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace


namespace {
static ClassDef sQuaternionClass =
{
	"Quaternion",
	ClassFlag::HasPrivate,

	nullptr,				// addProperty (engine default: PropertyStub)
	nullptr,				// delProperty (engine default: PropertyStub)
	QuaternionGetProperty,	// getProperty
	QuaternionSetProperty,	// setProperty
	nullptr,				// enumerate (engine default: EnumerateStub)
	nullptr,				// newEnumerate (ooscript::ClassFlag::NewEnumerate not used)
	nullptr,				// resolve (engine default: ResolveStub)
	nullptr,				// convert (engine default: ConvertStub)
	QuaternionFinalize,		// finalize
	nullptr,				// call
	nullptr,				// construct
	nullptr,				// backend: owned by the façade backend, must start null
};
} // namespace


enum : std::uint8_t
{
	// Property IDs
	kQuaternion_w,
	kQuaternion_x,
	kQuaternion_y,
	kQuaternion_z
};


namespace {
static PropertySpec sQuaternionProperties[] =
{
	// JS name						ID							flags										getter		setter
	{ "w",							kQuaternion_w,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared,	nullptr, nullptr },
	{ "x",							kQuaternion_x,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared,	nullptr, nullptr },
	{ "y",							kQuaternion_y,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared,	nullptr, nullptr },
	{ "z",							kQuaternion_z,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared,	nullptr, nullptr },
	{ 0 }
};
} // namespace

namespace {
static FunctionSpec sQuaternionMethods[] =
{
	// JS name						Function					min args	flags
	{ "toString",					QuaternionToString,			0,			0 },
	{ "toSource",					QuaternionToSource,			0,			0 },
	{ "dot",						QuaternionDot,				1,			0 },
	{ "multiply",					QuaternionMultiply,			1,			0 },
	{ "normalize",					QuaternionNormalize,		0,			0 },
	{ "conjugate",					QuaternionConjugate,		0,			0 },
	{ "rotate",						QuaternionRotate,			2,			0 },
	{ "rotateX",					QuaternionRotateX,			1,			0 },
	{ "rotateY",					QuaternionRotateY,			1,			0 },
	{ "rotateZ",					QuaternionRotateZ,			1,			0 },
	{ "toArray",					QuaternionToArray,			0,			0 },
	{ "vectorForward",				QuaternionVectorForward,	0,			0 },
	{ "vectorRight",				QuaternionVectorRight,		0,			0 },
	{ "vectorUp",					QuaternionVectorUp,			0,			0 },
	{ 0 }
};
} // namespace


namespace {
static FunctionSpec sQuaternionStaticMethods[] =
{
	// JS name						Function					min args	flags
	{ "random",						QuaternionStaticRandom,		0,			0 },
	{ 0 }
};
} // namespace


// *** Public ***

void InitOOJSQuaternion(ooscript::Context context, ooscript::Object global)
{
	Object proto = ooscript::initClass((context), (global), nullptr, &sQuaternionClass,
										QuaternionConstruct, 4, sQuaternionProperties, sQuaternionMethods,
										nullptr, sQuaternionStaticMethods);
	sQuaternionPrototype = (proto);
}


ooscript::Object JSQuaternionWithQuaternion(ooscript::Context context, Quaternion quaternion)
{
	OOJS_PROFILE_ENTER
	
	ooscript::Object result = NULL;
	Quaternion				*priv = NULL;
	
	priv = static_cast<Quaternion*>(malloc(sizeof *priv));
	if (EXPECT_NOT(priv == NULL))  return NULL;
	
	*priv = quaternion;
	
	result = (ooscript::newObject((context), &sQuaternionClass, (sQuaternionPrototype), nullptr));
	if (result != NULL)
	{
		if (EXPECT_NOT(!ooscript::setPrivate((context), (result), priv)))  result = NULL;
	}
	
	if (EXPECT_NOT(result == NULL)) free(priv);
	
	return result;
	
	OOJS_PROFILE_EXIT
}


bool QuaternionToJSValue(ooscript::Context context, Quaternion quaternion, ooscript::Value *outValue)
{
	OOJS_PROFILE_ENTER
	
	ooscript::Object object = NULL;
	
	assert(outValue != NULL);
	
	object = JSQuaternionWithQuaternion(context, quaternion);
	if (EXPECT_NOT(object == NULL)) return false;
	
	*outValue = ooscript::objectValue(object);
	return true;
	
	OOJS_PROFILE_EXIT
}


bool JSValueToQuaternion(ooscript::Context context, ooscript::Value value, Quaternion *outQuaternion)
{
	if (EXPECT_NOT(!ooscript::isObjectOrNull(value)))  return false;
	
	return JSObjectGetQuaternion(context, ooscript::toObject(value), outQuaternion);
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
namespace {
static QuaternionStatistics sQuaternionConversionStats;
} // namespace


// The bodies of the C++ PlayerEntity's statistics members, which were the category PlayerEntity
// (JSQuaternionStatistics) until bead oo-9ht.15 (proposed ADR-0056 amendments oo-ppc, oo-9ht.15).
oo::PList reportJSQuaternionStatistics(void)
{
	QuaternionStatistics *stats = &sQuaternionConversionStats;
	
	NSUInteger sum = stats->quatCount + stats->entityCount + stats->arrayCount + stats->protoCount;
	double convFac = 100.0 / sum;
	
	return oo::PList(oo::str::format(
		   "quaternion-to-quaternion conversions: %zu (%g %%)\n"
			"    entity-to-quaternion conversions: %zu (%g %%)\n"
			"     array-to-quaternion conversions: %zu (%g %%)\n"
			"       prototype-to-zero conversions: %zu (%g %%)\n"
			"                    null conversions: %zu (%g %%)\n"
			"                  failed conversions: %zu (%g %%)\n"
			"                               total: %zu",
			(size_t)stats->quatCount, stats->quatCount * convFac,
			(size_t)stats->entityCount, stats->entityCount * convFac,
			(size_t)stats->arrayCount, stats->arrayCount * convFac,
			(size_t)stats->protoCount, stats->protoCount * convFac,
			(size_t)stats->nullCount, stats->nullCount * convFac,
			(size_t)stats->failCount, stats->failCount * convFac,
			(size_t)sum));
}


void clearJSQuaternionStatistics(void)
{
	memset(&sQuaternionConversionStats, 0, sizeof sQuaternionConversionStats);
}

#define COUNT(FIELD) do { sQuaternionConversionStats.FIELD++; } while (0)

#else

#define COUNT(FIELD) do {} while (0)

#endif


bool JSObjectGetQuaternion(ooscript::Context context, ooscript::Object quaternionObj, Quaternion *outQuaternion)
{
	OOJS_PROFILE_ENTER
	
	assert(outQuaternion != NULL);
	
	Quaternion				*priv = NULL;
	std::uint32_t			arrayLength;
	ooscript::Value					arrayW, arrayX, arrayY, arrayZ;
	double				dVal;
	
	Context cx = (context);
	Object obj = (quaternionObj);
	
	// quaternionObj can legitimately be NULL, e.g. when a null value is converted to a ooscript::Object .
	if (EXPECT_NOT(quaternionObj == NULL))
	{
		COUNT(nullCount);
		return false;
	}
	
	// If this is a (JS) Quaternion...
	priv = static_cast<Quaternion*>(ooscript::getInstancePrivate(cx, obj, &sQuaternionClass, nullptr));
	if (EXPECT(priv != NULL))
	{
		COUNT(quatCount);
		*outQuaternion = *priv;
		return true;
	}
	
	// If it's an array...
	if (EXPECT(ooscript::isArrayObject(cx, obj)))
	{
		// ...and it has exactly four elements...
		if (ooscript::getArrayLength(cx, obj, &arrayLength) && arrayLength == 4)
		{
			if (ooscript::lookupElement(cx, obj, 0, (&arrayW)) &&
				ooscript::lookupElement(cx, obj, 1, (&arrayX)) &&
				ooscript::lookupElement(cx, obj, 2, (&arrayY)) &&
				ooscript::lookupElement(cx, obj, 3, (&arrayZ)))
			{
				// ...use the four numbers as [w, x, y, z]
				if (!ooscript::valueToNumber(cx, (arrayW), &dVal))  return false;
				outQuaternion->w = dVal;
				if (!ooscript::valueToNumber(cx, (arrayX), &dVal))  return false;
				outQuaternion->x = dVal;
				if (!ooscript::valueToNumber(cx, (arrayY), &dVal))  return false;
				outQuaternion->y = dVal;
				if (!ooscript::valueToNumber(cx, (arrayZ), &dVal))  return false;
				outQuaternion->z = dVal;
				
				COUNT(arrayCount);
				return true;
			}
		}
	}
	
	// If it's an entity, use its orientation.
	if (OOJSIsMemberOfSubclass(context, quaternionObj, JSEntityClass()))
	{
		COUNT(entityCount);
		*outQuaternion = OOJSEntityOrientationOfJSObject(context, quaternionObj);	// the C++ entity's (bead oo-9ht.39.8.12)
		return true;
	}
	
	/*
		If it's actually a Quaternion but with no private field (this happens for
		Quaternion.prototype)...
		
		NOTE: it would be prettier to do this at the top when we handle normal
		Quaternions, but it's a rare case which should be kept off the fast path.
	*/
	if (ooscript::instanceOf(cx, obj, &sQuaternionClass, nullptr))
	{
		COUNT(protoCount);
		*outQuaternion = kZeroQuaternion;
		return true;
	}
	
	COUNT(failCount);
	return false;
	
	OOJS_PROFILE_EXIT
}


namespace {
static bool GetThisQuaternion(ooscript::Context context, ooscript::Object quaternionObj, Quaternion *outQuaternion, const std::string &method)
{
	if (EXPECT(JSObjectGetQuaternion(context, quaternionObj, outQuaternion)))  return true;
	
	ooscript::Value arg = ooscript::objectValue(quaternionObj);
	cxx_OOJSReportBadArguments(context, "Quaternion", method, 1, &arg, "Invalid target object", "Quaternion");
	return false;
}
} // namespace


bool JSQuaternionSetQuaternion(ooscript::Context context, ooscript::Object quaternionObj, Quaternion quaternion)
{
	OOJS_PROFILE_ENTER
	
	Quaternion				*priv = NULL;
	
	assert(quaternionObj != NULL);
	
	Context cx = (context);
	Object obj = (quaternionObj);
	
	priv = static_cast<Quaternion*>(ooscript::getInstancePrivate(cx, obj, &sQuaternionClass, nullptr));
	if (priv != NULL)	// If this is a (JS) Quaternion...
	{
		*priv = quaternion;
		return true;
	}
	
	if (ooscript::instanceOf(cx, obj, &sQuaternionClass, nullptr))
	{
		// Silently fail for the prototype.
		return true;
	}
	
	return false;
	
	OOJS_PROFILE_EXIT
}


namespace {
static bool QuaternionFromArgumentListNoErrorInternal(ooscript::Context context, unsigned argc, ooscript::Value *argv, Quaternion *outQuaternion, unsigned *outConsumed, bool permitNumberList)
{
	OOJS_PROFILE_ENTER
	
	double				w, x, y, z;
	
	if (EXPECT_NOT(argc == 0))  return false;
	assert(argv != NULL && outQuaternion != NULL);
	
	if (outConsumed != NULL)  *outConsumed = 0;
	
	// Is first object a quaternion or entity?
	if (ooscript::isObjectOrNull(argv[0]))
	{
		if (JSObjectGetQuaternion(context, ooscript::toObject(argv[0]), outQuaternion))
		{
			if (outConsumed != NULL)  *outConsumed = 1;
			return true;
		}
	}
	
	if (!permitNumberList)  return false;
	
	// As a special case for QuaternionConstruct(), look for four numbers.
	if (EXPECT_NOT(argc < 4))  return false;
	
	// Given a string, ooscript::valueToNumber() returns YES but provides a NaN number.
	Context cx = (context);
	if (EXPECT_NOT(!ooscript::valueToNumber(cx, (argv[0]), &w) || isnan(w)))  return false;
	if (EXPECT_NOT(!ooscript::valueToNumber(cx, (argv[1]), &x) || isnan(x)))  return false;
	if (EXPECT_NOT(!ooscript::valueToNumber(cx, (argv[2]), &y) || isnan(y)))  return false;
	if (EXPECT_NOT(!ooscript::valueToNumber(cx, (argv[3]), &z) || isnan(z)))  return false;
	
	// We got our four numbers.
	*outQuaternion = make_quaternion(w, x, y, z);
	if (outConsumed != NULL)  *outConsumed = 4;

	return true;
	
	OOJS_PROFILE_EXIT
}
} // namespace


// EMMSTRAN: remove outConsumed, since it can only be 1 except in failure (constructor is an exception, but it uses QuaternionFromArgumentListNoErrorInternal() directly).
bool QuaternionFromArgumentList(ooscript::Context context, const std::string &scriptClass, const std::string &function, unsigned argc, ooscript::Value *argv, Quaternion *outQuaternion, unsigned *outConsumed)
{
	if (QuaternionFromArgumentListNoErrorInternal(context, argc, argv, outQuaternion, outConsumed, false))  return true;
	else
	{
		cxx_OOJSReportBadArguments(context, scriptClass, function, argc, argv,
							   "Could not construct quaternion from parameters",
							   "Quaternion, Entity or four numbers");
		return false;
	}
}


bool QuaternionFromArgumentListNoError(ooscript::Context context, unsigned argc, ooscript::Value *argv, Quaternion *outQuaternion, unsigned *outConsumed)
{
	return QuaternionFromArgumentListNoErrorInternal(context, argc, argv, outQuaternion, outConsumed, false);
}


// *** Implementation stuff ***

namespace {
static bool QuaternionGetProperty(Context cx, Object obj, PropertyId propID, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);
	
	OOJS_PROFILE_ENTER
	
	Quaternion			quaternion;
	GLfloat				fValue;
	
	if (EXPECT_NOT(!JSObjectGetQuaternion(context, thisObj, &quaternion))) return false;
	
	switch (ooscript::idToInt32(propID))
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
			OOJSReportBadPropertySelector(context, thisObj, (propID), sQuaternionProperties);
			return false;
	}
	
	return ooscript::newNumberValue(cx, fValue, value);
	
	OOJS_PROFILE_EXIT
}
} // namespace


namespace {
static bool QuaternionSetProperty(Context cx, Object obj, PropertyId propID, bool /*strict*/, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);
	
	OOJS_PROFILE_ENTER
	
	Quaternion			quaternion;
	double			dval;
	
	if (EXPECT_NOT(!JSObjectGetQuaternion(context, thisObj, &quaternion))) return false;
	if (EXPECT_NOT(!ooscript::valueToNumber(cx, *value, &dval)))
	{
		OOJSReportBadPropertyValue(context, thisObj, (propID), sQuaternionProperties, *(value));
		return false;
	}
	
	switch (ooscript::idToInt32(propID))
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
			OOJSReportBadPropertySelector(context, thisObj, (propID), sQuaternionProperties);
			return false;
	}
	
	return JSQuaternionSetQuaternion(context, thisObj, quaternion);
	
	OOJS_PROFILE_EXIT
}
} // namespace


namespace {
static void QuaternionFinalize(Context cx, Object obj)
{
	OOJS_PROFILE_ENTER
	
	Quaternion				*priv = NULL;
	
	priv = static_cast<Quaternion*>(ooscript::getInstancePrivate(cx, obj, &sQuaternionClass, nullptr));
	if (priv != NULL)
	{
		free(priv);
	}
	
	OOJS_PROFILE_EXIT_VOID
}
} // namespace


namespace {
static bool QuaternionConstruct(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_PROFILE_ENTER
	
	Quaternion				quaternion = kIdentityQuaternion;
	Quaternion				*priv = NULL;
	ooscript::Object thisObj = NULL;
	
	priv = static_cast<Quaternion*>(malloc(sizeof *priv));
	if (EXPECT_NOT(priv == NULL))  return false;
	
	thisObj = (ooscript::newObject(context, &sQuaternionClass, nullptr, nullptr));
	if (EXPECT_NOT(thisObj == NULL))
	{
		free(priv);	// leaked before bead oo-hwae; the analyser sees this path now that it is not in an Objective-C try
		return false;
	}
	
	if (oojsArgs.count() != 0)
	{
		if (EXPECT_NOT(!QuaternionFromArgumentListNoErrorInternal(context, oojsArgs.count(), OOJS_ARGV, &quaternion, NULL, true)))
		{
			free(priv);
			cxx_OOJSReportBadArguments(context, std::nullopt, std::nullopt, oojsArgs.count(), OOJS_ARGV,
								   "Could not construct quaternion from parameters",
								   "Quaternion, Entity or array of four numbers");
			return false;
		}
	}
	
	*priv = quaternion;
	
	if (EXPECT_NOT(!ooscript::setPrivate(context, (thisObj), priv)))
	{
		free(priv);
		return false;
	}
	
	OOJS_RETURN_JSOBJECT(thisObj);
	
	OOJS_PROFILE_EXIT
}
} // namespace


// *** Methods ***

// toString() : String
namespace {
static bool QuaternionToString(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	Quaternion				thisq;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, "toString"))) return false;
	
	OOJS_RETURN_PLIST(oo::PList(QuaternionDescription(thisq)));
	
	OOJS_NATIVE_EXIT
}
} // namespace


// toSource() : String
namespace {
static bool QuaternionToSource(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	Quaternion				thisq;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, "toSource"))) return false;
	
	OOJS_RETURN_PLIST(oo::PList(oo::str::format("Quaternion(%g, %g, %g, %g)", thisq.w, thisq.x, thisq.y, thisq.z)));
	
	OOJS_NATIVE_EXIT
}
} // namespace


// multiply(q : quaternionExpression) : Quaternion
namespace {
static bool QuaternionMultiply(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_PROFILE_ENTER
	
	Quaternion				thisq, thatq, result;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, "multiply"))) return false;
	if (EXPECT_NOT(!QuaternionFromArgumentList(context, "Quaternion", "multiply", oojsArgs.count(), OOJS_ARGV, &thatq, NULL)))  return false;
	
	result = quaternion_multiply(thisq, thatq);
	
	OOJS_RETURN_QUATERNION(result);
	
	OOJS_PROFILE_EXIT
}
} // namespace


// dot(q : quaternionExpression) : Number
namespace {
static bool QuaternionDot(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_PROFILE_ENTER
	
	Quaternion				thisq, thatq;
	OOScalar				result;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, "dot"))) return false;
	if (EXPECT_NOT(!QuaternionFromArgumentList(context, "Quaternion", "dot", oojsArgs.count(), OOJS_ARGV, &thatq, NULL)))  return false;
	
	result = quaternion_dot_product(thisq, thatq);
	
	OOJS_RETURN_DOUBLE(result);
	
	OOJS_PROFILE_EXIT
}
} // namespace


// rotate(axis : vectorExpression, angle : Number) : Quaternion
namespace {
static bool QuaternionRotate(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_PROFILE_ENTER
	
	Quaternion				thisq;
	HPVector					axis;
	double					angle;
	unsigned					consumed;
	unsigned						argc = oojsArgs.count();
	ooscript::Value					*argv = OOJS_ARGV;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, "rotate"))) return false;
	if (EXPECT_NOT(!VectorFromArgumentList(context, "Quaternion", "rotate", argc, argv, &axis, &consumed)))  return false;
	argv += consumed;
	argc -= consumed;
	if (argc > 0)
	{
		if (EXPECT_NOT(!cxx_OOJSArgumentListGetNumber(context, "Quaternion", "rotate", argc, argv, &angle, NULL)))  return false;
		quaternion_rotate_about_axis(&thisq, HPVectorToVector(axis), angle);
	}
	// Else no angle specified, so don't rotate and pass value through unchanged.
	
	OOJS_RETURN_QUATERNION(thisq);
	
	OOJS_PROFILE_EXIT
}
} // namespace


// rotateX(angle : Number) : Quaternion
namespace {
static bool QuaternionRotateX(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_PROFILE_ENTER
	
	Quaternion				quat;
	double					angle;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &quat, "rotateX"))) return false;
	if (EXPECT_NOT(!cxx_OOJSArgumentListGetNumber(context, "Quaternion", "rotateX", oojsArgs.count(), OOJS_ARGV, &angle, NULL)))  return false;
	
	quaternion_rotate_about_x(&quat, angle);
	
	OOJS_RETURN_QUATERNION(quat);
	
	OOJS_PROFILE_EXIT
}
} // namespace


// rotateY(angle : Number) : Quaternion
namespace {
static bool QuaternionRotateY(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_PROFILE_ENTER
	
	Quaternion				quat;
	double					angle;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &quat, "rotateY"))) return false;
	if (EXPECT_NOT(!cxx_OOJSArgumentListGetNumber(context, "Quaternion", "rotateY", oojsArgs.count(), OOJS_ARGV, &angle, NULL)))  return false;
	
	quaternion_rotate_about_y(&quat, angle);
	
	OOJS_RETURN_QUATERNION(quat);
	
	OOJS_PROFILE_EXIT
}
} // namespace


// rotateZ(angle : Number) : Quaternion
namespace {
static bool QuaternionRotateZ(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_PROFILE_ENTER
	
	Quaternion				quat;
	double					angle;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &quat, "rotateZ"))) return false;
	if (EXPECT_NOT(!cxx_OOJSArgumentListGetNumber(context, "Quaternion", "rotateZ", oojsArgs.count(), OOJS_ARGV, &angle, NULL)))  return false;
	
	quaternion_rotate_about_z(&quat, angle);
	
	OOJS_RETURN_QUATERNION(quat);
	
	OOJS_PROFILE_EXIT
}
} // namespace


// normalize() : Quaternion
namespace {
static bool QuaternionNormalize(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_PROFILE_ENTER
	
	Quaternion				quat;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &quat, "normalize"))) return false;
	
	quaternion_normalize(&quat);
	
	OOJS_RETURN_QUATERNION(quat);
	
	OOJS_PROFILE_EXIT
}
} // namespace


// conjugate() : Quaternion
namespace {
static bool QuaternionConjugate(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_PROFILE_ENTER
	
		Quaternion				quat, result;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &quat, "conjugate"))) return false;
	
	result = quaternion_conjugate(quat);
	
	OOJS_RETURN_QUATERNION(result);
	
	OOJS_PROFILE_EXIT
}
} // namespace


// vectorForward() : Vector
namespace {
static bool QuaternionVectorForward(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_PROFILE_ENTER
	
	Quaternion				thisq;
	Vector					result;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, "vectorForward"))) return false;
	
	result = vector_forward_from_quaternion(thisq);
	
	OOJS_RETURN_VECTOR(result);
	
	OOJS_PROFILE_EXIT
}
} // namespace


// vectorUp() : Vector
namespace {
static bool QuaternionVectorUp(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_PROFILE_ENTER
	
	Quaternion				thisq;
	Vector					result;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, "vectorUp"))) return false;
	
	result = vector_up_from_quaternion(thisq);
	
	OOJS_RETURN_VECTOR(result);
	
	OOJS_PROFILE_EXIT
}
} // namespace


// vectorRight() : Vector
namespace {
static bool QuaternionVectorRight(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_PROFILE_ENTER
	
	Quaternion				thisq;
	Vector					result;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, "vectorRight"))) return false;
	
	result = vector_right_from_quaternion(thisq);
	
	OOJS_RETURN_VECTOR(result);
	
	OOJS_PROFILE_EXIT
}
} // namespace


// toArray() : Array
namespace {
static bool QuaternionToArray(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_PROFILE_ENTER
	
	Quaternion				thisq;
	ooscript::Object result = NULL;
	bool					OK = true;
	ooscript::Value					nVal;
	
	if (EXPECT_NOT(!GetThisQuaternion(context, OOJS_THIS, &thisq, "toArray"))) return false;
	
	result = (ooscript::newArrayObject(context, 0, nullptr));
	if (result != NULL)
	{
		// We do this at the top because *outResult is a GC root.
		OOJS_SET_RVAL(ooscript::objectValue(result));
		
		Object resultObj = (result);
		if (ooscript::newNumberValue(context, thisq.w, (&nVal)))  ooscript::setElement(context, resultObj, 0, (&nVal));
		else  OK = false;
		if (ooscript::newNumberValue(context, thisq.x, (&nVal)))  ooscript::setElement(context, resultObj, 1, (&nVal));
		else  OK = false;
		if (ooscript::newNumberValue(context, thisq.y, (&nVal)))  ooscript::setElement(context, resultObj, 2, (&nVal));
		else  OK = false;
		if (ooscript::newNumberValue(context, thisq.z, (&nVal)))  ooscript::setElement(context, resultObj, 3, (&nVal));
		else  OK = false;
	}
	
	if (!OK)  OOJS_SET_RVAL(ooscript::undefinedValue());
	return true;
	
	OOJS_PROFILE_EXIT
}
} // namespace


// *** Static methods ***

// random() : Quaternion
namespace {
static bool QuaternionStaticRandom(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_PROFILE_ENTER
	
	OOJS_RETURN_QUATERNION(OORandomQuaternion());
	
	OOJS_PROFILE_EXIT
}
} // namespace
