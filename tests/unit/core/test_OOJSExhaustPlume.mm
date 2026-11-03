/*	test_OOJSExhaustPlume.mm
	Unit tests for the ExhaustPlume JS binding (src/Core/Scripting/OOJSExhaustPlume.h/.mm) and its
	OOExhaustPlumeEntity category (whose forwarders are on the OOExhaustPlumeEntity facade since
	bead oo-9ht.48; this test's stand-in OOExhaustPlumeEntity forwards the same way): bead oo-utlm,
	converted the way bead oo-ppc converted OOJSVector (proposed ADR-0056 amendments oo-ppc and
	oo-ykoy).

	As test_OOJSWormhole.mm does (amendment oo-ykoy, item 4), it runs the JS class in a real
	QuickJS-ng context, links the game's own objects for the binding, the engine's
	class registration (OOJSClasses.mm) and the engine's exception translator
	(OOJSEngineNativeWrappers.mm), and stands in for the entity classes (Entity, ShipEntity,
	OOExhaustPlumeEntity answer only the selectors the binding sends), for the Vector3D conversions
	(a vector is the array [x, y, z] here) and for the engine functions the binding links against,
	with the engine headers' linkage. The binding header is not imported, because until this bead
	it imported OOExhaustPlumeEntity.h; InitOOJSExhaustPlume is declared here. The expectations
	were written against the Objective-C file and run on it first; they pin the JS-visible
	behaviour (size, remove(), a stale plume, a non-plume, a native's exception) and what the
	category answers the engine. Run: tests/run.sh unit
*/

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"
#include <objc/runtime.h>
#include "OOMaths.h"
#include <quickjs.h>
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"


// MARK: The entity classes, as far as the binding sees them ---------------------------------------

@class OOExhaustPlumeEntity;

@interface Entity: OOObject
{
@public
	id _owner;
}
- (id) weakRefUnderlyingObject;
- (id) owner;
@end

@interface ShipEntity: Entity
{
@public
	OOExhaustPlumeEntity *_removed;
}
- (void) removeExhaust:(OOExhaustPlumeEntity *)exhaust;
@end

/*	A plume whose scale has x = -1 raises from -scale, one with x = -2 throws a C++ exception, so the
	test sees what an exception under a native becomes.
*/
@interface OOExhaustPlumeEntity: Entity
{
@public
	Vector _scale;
}
- (Vector) scale;
- (void) setScale:(Vector)scale;
@end

@interface Entity (OOJavaScriptExtensions)
- (JSClassID) oo_jsClassID;
- (std::optional<std::string>) cxx_oo_jsClassName;
- (BOOL) isVisibleToScripts;
@end


void InitOOJSExhaustPlume(JSContext* context, JSValueConst global);
// The category's bodies, which the stand-in forwards to as the facade does (declared in OOJSExhaustPlume.h).
JSClassID JSExhaustPlumeClassID(void);
std::optional<std::string> OOJSExhaustPlumeJSClassName(void);
bool OOJSExhaustPlumeIsVisibleToScripts(void);
#include "OOJSEngineCore.h"

#include "oo_test.hpp"

#include <cstdarg>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>


@implementation Entity

- (id) weakRefUnderlyingObject  { return self; }
- (id) owner  { return _owner; }

@end


@implementation ShipEntity

- (void) removeExhaust:(OOExhaustPlumeEntity *)exhaust  { _removed = exhaust; }

@end


@implementation OOExhaustPlumeEntity

- (Vector) scale
{
	if (_scale.x == -1)  [OOException raise:OOInvalidArgumentException format:"scale %s", "boom"];
	if (_scale.x == -2)  throw std::runtime_error("cxx boom");
	return _scale;
}

- (void) setScale:(Vector)scale  { _scale = scale; }


// The binding's category, as the OOExhaustPlumeEntity facade forwards it
// (OOExhaustPlumeEntity+ObjCBridge.mm, bead oo-9ht.48): the engine sends these selectors to the
// wrapped object.
- (JSClassID) oo_jsClassID  { return ::JSExhaustPlumeClassID(); }
- (std::optional<std::string>) cxx_oo_jsClassName  { return ::OOJSExhaustPlumeJSClassName(); }
- (BOOL) isVisibleToScripts  { return ::OOJSExhaustPlumeIsVisibleToScripts(); }

@end


// MARK: What the rest of the engine provides ------------------------------------------------------

JSContext *gOOJSMainThreadContext = nullptr;	// the engine's


void cxx_OOJSReportErrorWithArguments(JSContext *context, const char *format, va_list args)
{
	std::string msg = oo::str::vformat(format, args);
	JS_ThrowPlainError(context, "%s", msg.c_str());
}


void cxx_OOJSReportError(JSContext *context, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	cxx_OOJSReportErrorWithArguments(context, format, args);
	va_end(args);
}


// What the class registration (OOJSClasses.mm) asks of the engine.
void OOJSReportPendingException(JSContext *context)
{
	JS_FreeValue(context, JS_GetException(context));
}


JSAtom cxx_OOJSIDFromString(const std::string &string)
{
	return JS_NewAtomLen(OOJSAcquireContext(), string.data(), string.size());
}


// As the engine's: a native that fails with nothing reported ends the script with an uncatchable
// error.
JSValue OOJSNativeFailure(JSContext *context)
{
	if (JS_HasException(context))  return JS_EXCEPTION;
	JSValue error = JS_NewError(context);
	JS_SetUncatchableError(context, error);
	return JS_Throw(context, error);
}


std::optional<std::string> cxx_OOStringFromJSValue(JSContext *context, JSValueConst value)
{
	if (JS_IsNull(value) || JS_IsUndefined(value))  return std::nullopt;
	std::size_t length = 0;
	const char *chars = JS_ToCStringLen(context, &length, value);
	if (chars == nullptr)
	{
		JS_FreeValue(context, JS_GetException(context));
		return std::nullopt;
	}
	std::string result(chars, length);
	JS_FreeCString(context, chars);
	return result;
}


namespace {
JSClassID sFakeEntityClassID = 0;
JSClassDef sFakeEntityClass = { .class_name = "Entity" };
std::map<JSClassID, int> sConverters;
} // namespace

Entity *gOOJSPlayerIfStale = nil;


JSClassID JSEntityClassID(void)
{
	return sFakeEntityClassID;
}


void OOJSReportBadPropertySelector(JSContext *context, JSValueConst, int, const JSCFunctionListEntry *, size_t)
{
	cxx_OOJSReportError(context, "bad property selector");
}


void OOJSReportBadPropertyValue(JSContext *context, JSValueConst, int, const JSCFunctionListEntry *, size_t, JSValueConst)
{
	cxx_OOJSReportError(context, "bad property value");
}


void OOJSRegisterObjectConverter(JSClassID classID, OOJSClassConverterCallback)
{
	sConverters[classID]++;
}


// The engine's object getter: the JS class must be a subclass of the required one, and the
// underlying object must be of the required Objective-C class.
BOOL OOJSObjectGetterImplPRIVATE(JSContext *context, JSValueConst object, JSClassID requiredClassID, Class requiredObjCClass, const char *, id *outObject)
{
	if (!OOJSIsSubclass(JS_GetClassID(object), requiredClassID))
	{
		cxx_OOJSReportError(context, "Native method expected %s, got %s.", OOJSClassName(requiredClassID), cxx_OOStringFromJSValue(context, object).value_or("(null)").c_str());
		return NO;
	}
	JSClassID ignored;
	*outObject = [(id)JS_GetAnyOpaque(object, &ignored) weakRefUnderlyingObject];
	if (*outObject != nil && ![*outObject isKindOfClass:requiredObjCClass])
	{
		cxx_OOJSReportError(context, "Native method expected %s from %s.", class_getName(requiredObjCClass), OOJSClassName(requiredClassID));
		*outObject = nil;
		return NO;
	}
	return YES;
}


JSValue OOJSValueFromNativeObject(JSContext *, id)
{
	return JS_UNDEFINED;
}


JSValue OOJSUnconstructableConstruct(JSContext *context, JSValueConst, int, JSValueConst *)
{
	cxx_OOJSReportError(context, "unconstructable");
	return JS_EXCEPTION;
}


void OOJSObjectWrapperFinalize(JSRuntime *, JSValueConst)
{
}


// A vector is the array [x, y, z] here: enough to see what the binding hands over and takes.
bool VectorToJSValue(JSContext *context, Vector vector, JSValue *outValue)
{
	JSValue array = JS_NewArray(context);
	if (JS_IsException(array))  return false;
	JS_SetPropertyUint32(context, array, 0, JS_NewNumber(context, vector.x));
	JS_SetPropertyUint32(context, array, 1, JS_NewNumber(context, vector.y));
	JS_SetPropertyUint32(context, array, 2, JS_NewNumber(context, vector.z));
	*outValue = array;
	return true;
}


bool JSValueToVector(JSContext *context, JSValueConst value, Vector *outVector)
{
	double v[3] = {};
	if (!JS_IsArray(value))  return false;
	for (std::uint32_t i = 0; i < 3; i++)
	{
		JSValue element = JS_GetPropertyUint32(context, value, i);
		const bool ok = !JS_IsException(element) && JS_ToFloat64(context, &v[i], element) == 0;
		JS_FreeValue(context, element);
		if (!ok)  return false;
	}
	*outVector = make_vector(v[0], v[1], v[2]);
	return true;
}



int sLimiterPauses = 0;
int sProfileDepth = 0;

void OOJSProfileEnter(struct OOJSProfileStackFrame *, const char *)  { sProfileDepth++; }
void OOJSProfileExit(struct OOJSProfileStackFrame *)  { sProfileDepth--; }

void OOJSPauseTimeLimiter(void)  { sLimiterPauses++; }
void OOJSResumeTimeLimiter(void)  { sLimiterPauses--; }


#ifndef NDEBUG
void OOJSUnreachable(const char *function, const char *, unsigned)
{
	std::printf("unreachable reached in %s\n", function);
	abort();
}
#endif


oo::PList OOJSBasicPrivateObjectConverter(JSContext *, JSValueConst)
{
	return oo::PList();
}


// MARK: The context -------------------------------------------------------------------------------

namespace {

JSRuntime *sRuntime = nullptr;
JSContext *sContext = nullptr;
JSValue sGlobal = JS_UNDEFINED;	// held for the life of the test
OOExhaustPlumeEntity *sPlume = nil;
ShipEntity *sShip = nil;


// A JS object of the class, with the class's prototype and the entity in the private slot; owned
// by the caller.
JSValue JSValueForObject(JSClassID jsClass, Entity *entity)
{
	JSValue object = JS_NewObjectClass(sContext, static_cast<int>(jsClass));
	if (JS_IsException(object) || JS_SetOpaque(object, entity) != 0)
	{
		JS_FreeValue(sContext, object);
		return JS_NULL;
	}
	return object;
}


// A JS object for an entity, as -[Entity oo_jsValueInContext:] makes it: the class the entity's
// category names, and the entity in the private slot.
JSValue JSValueForEntity(Entity *entity)
{
	return JSValueForObject([entity oo_jsClassID], entity);
}


// Defines a global; takes value's reference.
void Define(const char *name, JSValue value)
{
	JS_SetPropertyStr(sContext, sGlobal, name, value);
}


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = JS_NewRuntime();
	sContext = JS_NewContext(sRuntime);
	gOOJSMainThreadContext = sContext;	// the class registration's runtime
	sGlobal = JS_GetGlobalObject(sContext);
	OOJSRegisterClass(&sFakeEntityClassID, &sFakeEntityClass);
	OOJSInitClass(sContext, sGlobal, sFakeEntityClassID, JS_UNDEFINED, OOJSUnconstructableConstruct, 0, nullptr, 0, nullptr, 0, nullptr, 0);
	InitOOJSExhaustPlume(sContext, sGlobal);

	sShip = [[ShipEntity alloc] init];	// kept for the life of the test
	sPlume = [[OOExhaustPlumeEntity alloc] init];
	sPlume->_scale = make_vector(1, 2, 3.5);
	sPlume->_owner = sShip;
	Define("plume", JSValueForEntity(sPlume));
	Define("ship", JSValueForObject(sFakeEntityClassID, sShip));
}


// Evaluates src and gives its result as a string ("undefined", "null", ...), or "threw: <message>".
std::string Eval(const char *src)
{
	SetUpContext();
	std::string wrapped = std::string("(function () { try { return String(") + src + "); } catch (e) { return 'threw: ' + (e && e.message !== undefined ? e.message : e); } })()";
	JSValue result = JS_Eval(sContext, wrapped.c_str(), wrapped.size(), "test.js", JS_EVAL_TYPE_GLOBAL);
	if (JS_IsException(result))
	{
		JS_FreeValue(sContext, JS_GetException(sContext));
		return "<evaluation failed>";
	}
	std::string text = cxx_OOStringFromJSValue(sContext, result).value_or("<not a string>");
	JS_FreeValue(sContext, result);
	return text;
}


// Eval, and print what came back when it is not what the check expects.
std::string EvalShown(const char *src, const char *expected)
{
	std::string result = Eval(src);
	if (result != expected)  std::printf("    %s\n    gave: %s\n", src, result.c_str());
	return result;
}
#define OO_CHECK_EVAL(src, expected)  OO_CHECK_EQ(EvalShown(src, expected), expected)

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

OO_TEST(registration)
{
	SetUpContext();
	JSClassID plumeClass = [sPlume oo_jsClassID];
	OO_CHECK(plumeClass != 0 && OOJSClassName(plumeClass) != nullptr && std::strcmp(OOJSClassName(plumeClass), "ExhaustPlume") == 0);
	JSValue prototype = JS_GetClassProto(sContext, plumeClass);
	OO_CHECK(JS_IsObject(prototype));
	JS_FreeValue(sContext, prototype);
	OO_CHECK(OOJSIsSubclass(plumeClass, sFakeEntityClassID));
	OO_CHECK_EQ(sConverters[plumeClass], 1);
	OO_CHECK([sPlume cxx_oo_jsClassName] == std::optional<std::string>("ExhaustPlume"));
	OO_CHECK([sPlume isVisibleToScripts]);
	OO_CHECK_EVAL("typeof ExhaustPlume", "function");
	OO_CHECK_EVAL("new ExhaustPlume()", "threw: unconstructable");
	OO_CHECK_EVAL("Object.getPrototypeOf(ExhaustPlume.prototype) === Entity.prototype", "true");
	OO_CHECK_EVAL("plume instanceof ExhaustPlume", "true");
}


OO_TEST(properties)
{
	OO_CHECK_EVAL("plume.size", "1,2,3.5");
	OO_CHECK_EVAL("Object.keys(ExhaustPlume.prototype).join()", "size");
	OO_CHECK_EVAL("(function () { plume.size = [4, 5, 6]; return plume.size; })()", "4,5,6");
	OO_CHECK(sPlume->_scale.x == 4 && sPlume->_scale.y == 5 && sPlume->_scale.z == 6);
	OO_CHECK_EVAL("(function () { plume.size = 'big'; return plume.size; })()", "threw: bad property value");
	OO_CHECK_EVAL("plume.size", "4,5,6");
}


OO_TEST(remove)
{
	SetUpContext();
	sShip->_removed = nil;
	OO_CHECK_EVAL("plume.remove()", "undefined");
	OO_CHECK(sShip->_removed == sPlume);
	// The prototype has no entity: the binding's getter fails without reporting an error, which
	// ends the script uncatchably, and nothing is removed.
	sShip->_removed = nil;
	OO_CHECK_EVAL("ExhaustPlume.prototype.remove()", "<evaluation failed>");
	OO_CHECK(sShip->_removed == nil);
}


OO_TEST(otherObjects)
{
	// An entity that is not a plume, and the prototype: the binding's getter fails without
	// reporting an error, which ends the script uncatchably.
	OO_CHECK_EVAL("Object.getOwnPropertyDescriptor(ExhaustPlume.prototype, 'size').get.call(ship)", "<evaluation failed>");
	OO_CHECK_EVAL("ExhaustPlume.prototype.remove.call(ship)", "<evaluation failed>");
	OO_CHECK_EVAL("ExhaustPlume.prototype.size", "<evaluation failed>");
	// Something that is not an entity: the engine's getter reports it.
	OO_CHECK_EVAL("Object.getOwnPropertyDescriptor(ExhaustPlume.prototype, 'size').get.call({})", "threw: Native method expected Entity, got [object Object].");
	OO_CHECK_EVAL("plume.size", "4,5,6");
}


OO_TEST(nativeExceptions)
{
	SetUpContext();
	// The property getter is a native (OOJS_NATIVE_ENTER): a raise from the entity is a JS error,
	// and so is a C++ exception.
	sPlume->_scale = make_vector(-1, 0, 0);
	OO_CHECK_EVAL("plume.size", "threw: Native exception: scale boom");
	sPlume->_scale = make_vector(-2, 0, 0);
	OO_CHECK_EVAL("plume.size", "threw: Native exception: cxx boom");
	sPlume->_scale = make_vector(1, 1, 1);
	OO_CHECK_EVAL("plume.size", "1,1,1");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
}


OO_TEST_MAIN()
