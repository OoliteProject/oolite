/*	test_OOJSWormhole.mm
	Unit tests for the Wormhole JS binding (src/Core/Scripting/OOJSWormhole.h/.mm) and its
	WormholeEntity category (OOJSWormhole+ObjCBridge.mm): bead oo-ykoy, converted the way bead
	oo-ppc converted OOJSVector (proposed ADR-0056 amendments oo-ppc and oo-ykoy).

	It runs the JS class in a real QuickJS-ng context and links the game's own objects for the
	binding, its bridge, the engine's class registry (OOJSClasses.mm) and its exception translator
	(OOJSEngineNativeWrappers.mm). The entity classes it reads are stand-ins of the same names
	(amendment oo-z1s4, item 4), so the test imports neither their headers nor
	OOJavaScriptEngine.h (which imports them): Entity and WormholeEntity answer only the selectors
	the binding sends, and the JS side of an entity is a JS object of the binding's class whose
	private slot is the entity. What the engine provides (the Entity JS class, the object getter,
	the object converter, error reporting) is defined below as the smallest stand-in that does the
	same thing, with the engine header's linkage. The expectations were written against the
	Objective-C file and run on it first; they pin the JS-visible behaviour (the four properties,
	read-only, a stale entity, the wrong kind of object, a native's exception) and what the
	category answers the engine.
	Run: tests/run.sh unit
*/

#import "oofnd/objc/OOObject.h"
#include <objc/runtime.h>
#include "OOTypes.h"
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"

#include <quickjs.h>


// MARK: The entity classes, as far as the binding sees them ---------------------------------------

/*	A wormhole whose arrival time is -1 raises from -arrivalTime, one whose arrival time is -2
	throws a C++ exception, so the test sees what an exception under a native becomes.
*/
@interface Entity: OOObject
- (id) weakRefUnderlyingObject;
@end

@interface WormholeEntity: Entity
{
@public
	double _arrivalTime;
	double _expiryTime;
	OOSystemID _origin;
	OOSystemID _destination;
}
- (double) arrivalTime;
- (double) expiryTime;
- (OOSystemID) origin;
- (OOSystemID) destination;
@end

@interface Entity (OOJavaScriptExtensions)
- (JSClassID) oo_jsClassID;
- (std::optional<std::string>) cxx_oo_jsClassName;
- (BOOL) isVisibleToScripts;
@end


#import "OOJSWormhole.h"
#include "OOJSEngineCore.h"

#include "oo_test.hpp"

#include <cstdarg>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>


@implementation Entity

- (id) weakRefUnderlyingObject
{
	return self;
}

@end


@implementation WormholeEntity

- (double) arrivalTime
{
	if (_arrivalTime == -1)  [OOException raise:OOInvalidArgumentException format:"arrival %s", "boom"];
	if (_arrivalTime == -2)  throw std::runtime_error("cxx boom");
	return _arrivalTime;
}

- (double) expiryTime  { return _expiryTime; }
- (OOSystemID) origin  { return _origin; }
- (OOSystemID) destination  { return _destination; }

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


// The atom cache and the pending-exception reporter, which the class registry calls.
JSAtom cxx_OOJSIDFromString(const std::string &string)
{
	return JS_NewAtomLen(gOOJSMainThreadContext, string.data(), string.size());
}


void OOJSReportPendingException(JSContext *context)
{
	JS_FreeValue(context, JS_GetException(context));
}


// As the engine's: the pending exception, else an uncatchable error that ends the script.
JSValue OOJSNativeFailure(JSContext *context)
{
	if (JS_HasException(context))  return JS_EXCEPTION;
	JSValue error = JS_NewError(context);
	JS_SetUncatchableError(context, error);
	return JS_Throw(context, error);
}


namespace {
JSClassDef sFakeEntityClass = { .class_name = "Entity" };
JSClassID sFakeEntityClassID = 0;
std::map<JSClassID, int> sConverters;
} // namespace

int sFinalized = 0;	// the finalizer's count


JSClassID JSEntityClassID(void)
{
	return sFakeEntityClassID;
}


void OOJSReportBadPropertySelector(JSContext *context, JSValueConst, int, const JSCFunctionListEntry *, size_t)
{
	cxx_OOJSReportError(context, "bad property selector");
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
	sFinalized++;
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

JSRuntime *sRuntime;
JSContext *sContext;
JSValue sGlobal;
WormholeEntity *sWormhole = nil;


// A JS object for an entity, as -[Entity oo_jsValueInContext:] makes it: the class the entity's
// category names (its prototype is the class's), and the entity in the private slot. Owned by
// the caller.
JSValue JSValueForEntity(JSClassID classID, Entity *entity)
{
	JSValue object = JS_NewObjectClass(sContext, static_cast<int>(classID));
	if (JS_IsException(object) || JS_SetOpaque(object, entity) != 0)
	{
		JS_FreeValue(sContext, object);
		return JS_NULL;
	}
	return object;
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
	InitOOJSWormhole(sContext, sGlobal);

	sWormhole = [[WormholeEntity alloc] init];	// kept for the life of the test
	sWormhole->_arrivalTime = 1000.5;
	sWormhole->_expiryTime = 900.25;
	sWormhole->_origin = 7;
	sWormhole->_destination = 129;
	JS_SetPropertyStr(sContext, sGlobal, "wormhole", JSValueForEntity([sWormhole oo_jsClassID], sWormhole));
	JS_SetPropertyStr(sContext, sGlobal, "plainEntity", JSValueForEntity(sFakeEntityClassID, [[Entity alloc] init]));	// kept for the life of the test
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
	const JSClassID wormholeClassID = [sWormhole oo_jsClassID];
	const char *wormholeClassName = OOJSClassName(wormholeClassID);
	OO_CHECK(wormholeClassID != 0 && wormholeClassName != nullptr && std::strcmp(wormholeClassName, "Wormhole") == 0);
	JSValue prototype = JS_GetClassProto(sContext, wormholeClassID);
	OO_CHECK(JS_IsObject(prototype));
	JS_FreeValue(sContext, prototype);
	OO_CHECK(OOJSIsSubclass(wormholeClassID, sFakeEntityClassID));
	OO_CHECK_EQ(sConverters[wormholeClassID], 1);
	OO_CHECK([sWormhole cxx_oo_jsClassName] == std::optional<std::string>("Wormhole"));
	OO_CHECK([sWormhole isVisibleToScripts]);
	OO_CHECK_EVAL("typeof Wormhole", "function");
	OO_CHECK_EVAL("new Wormhole()", "threw: unconstructable");
	OO_CHECK_EVAL("Object.getPrototypeOf(Wormhole.prototype) === Entity.prototype", "true");
	OO_CHECK_EVAL("wormhole instanceof Wormhole", "true");
}


OO_TEST(properties)
{
	OO_CHECK_EVAL("wormhole.arrivalTime", "1000.5");
	OO_CHECK_EVAL("wormhole.expiryTime", "900.25");
	OO_CHECK_EVAL("wormhole.origin", "7");
	OO_CHECK_EVAL("wormhole.destination", "129");
	OO_CHECK_EVAL("Object.keys(Wormhole.prototype).join()", "arrivalTime,destination,expiryTime,origin");
	// Read-only. As in #768, a read-only property has no setter, so strict code that assigns to
	// one gets a TypeError (the old scripting layer tolerated it silently).
	OO_CHECK_EVAL("(function () { wormhole.origin = 3; return wormhole.origin; })()", "7");
	OO_CHECK_EVAL("(function () { 'use strict'; try { wormhole.origin = 3; return 'no throw'; } catch (e) { return e instanceof TypeError; } })()", "true");
}


OO_TEST(otherObjects)
{
	// An Entity that is not a wormhole, and the prototype (no entity at all): the binding's getter
	// fails without reporting an error, which ends the script uncatchably.
	OO_CHECK_EVAL("Object.getOwnPropertyDescriptor(Wormhole.prototype, 'origin').get.call(plainEntity)", "<evaluation failed>");
	OO_CHECK_EVAL("Wormhole.prototype.origin", "<evaluation failed>");
	// Something that is not an entity: the engine's getter reports it.
	OO_CHECK_EVAL("Object.getOwnPropertyDescriptor(Wormhole.prototype, 'origin').get.call({})", "threw: Native method expected Entity, got [object Object].");
	OO_CHECK_EVAL("wormhole.origin", "7");
}


OO_TEST(nativeExceptions)
{
	SetUpContext();
	// The property getter is a native (OOJS_NATIVE_ENTER): a raise from the entity is a JS error,
	// and so is a C++ exception.
	sWormhole->_arrivalTime = -1;
	OO_CHECK_EVAL("wormhole.arrivalTime", "threw: Native exception: arrival boom");
	sWormhole->_arrivalTime = -2;
	OO_CHECK_EVAL("wormhole.arrivalTime", "threw: Native exception: cxx boom");
	sWormhole->_arrivalTime = 1000.5;
	OO_CHECK_EVAL("wormhole.arrivalTime", "1000.5");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
}


OO_TEST_MAIN()
