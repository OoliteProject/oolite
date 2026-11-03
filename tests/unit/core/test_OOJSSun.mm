/*	test_OOJSSun.mm
	Unit tests for the Sun JS binding (src/Core/Scripting/OOJSSun.h/.mm) and its OOSunEntity
	category (OOJSSun+ObjCBridge.mm): bead oo-hgfh, converted the way bead oo-ppc converted
	OOJSVector (proposed ADR-0056 amendments oo-ppc and oo-ykoy).

	As test_OOJSWormhole.mm does (amendment oo-ykoy, item 4), it runs the JS class in a real
	QuickJS-ng context, links the game's own objects for the binding, its bridge, the engine's class
	registry (OOJSClasses.mm) and its exception translator (OOJSEngineNativeWrappers.mm), and stands
	in for the entity classes (Entity and OOSunEntity answer only the selectors the binding sends)
	and for the engine functions the binding links against, with the engine headers' linkage. The
	expectations were written against the Objective-C file and run on it first; they pin the
	JS-visible behaviour (the four properties, goNova() and cancelNova(), a non-sun, a native's
	exception) and what the category answers the engine. Run: tests/run.sh unit
*/

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"
#include <objc/runtime.h>
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"

#include <quickjs.h>


// MARK: The entity classes, as far as the binding sees them ---------------------------------------

@interface Entity: OOObject
- (id) weakRefUnderlyingObject;
@end

/*	A sun whose radius is 99 raises from -radius, one whose radius is 98 throws a C++ exception, so
	the test sees what an exception under a native becomes.
*/
@interface OOSunEntity: Entity
{
@public
	double _radius;
	std::optional<std::string> _name;
	BOOL _willGoNova;
	BOOL _goneNova;
	double _novaTime;
	int _novaCalls;
}
- (double) radius;
- (std::optional<std::string>) cxx_name;
- (BOOL) willGoNova;
- (BOOL) goneNova;
- (void) setGoingNova:(BOOL)yesno inTime:(double)interval;
@end

@interface Entity (OOJavaScriptExtensions)
- (JSClassID) oo_jsClassID;
- (std::optional<std::string>) cxx_oo_jsClassName;
- (BOOL) isVisibleToScripts;
@end


#import "OOJSSun.h"
#include "OOJSEngineCore.h"

#include "oo_test.hpp"

#include <cstdarg>
#include <cstdint>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>


@implementation Entity

- (id) weakRefUnderlyingObject  { return self; }

@end


@implementation OOSunEntity

- (std::optional<std::string>) cxx_name  { return _name; }
- (BOOL) willGoNova  { return _willGoNova; }
- (BOOL) goneNova  { return _goneNova; }

- (double) radius
{
	if (_radius == 99)  [OOException raise:OOInvalidArgumentException format:"radius %s", "boom"];
	if (_radius == 98)  throw std::runtime_error("cxx boom");
	return _radius;
}

- (void) setGoingNova:(BOOL)yesno inTime:(double)interval
{
	_willGoNova = yesno;
	_novaTime = interval;
	_novaCalls++;
}

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


// A property list as JavaScript, as far as the binding hands one over: null, a string, a number,
// or an array of those. Owned by the caller.
JSValue OOJSValueFromPList(JSContext *context, const oo::PList &plist)
{
	if (const std::string *str = plist.getIf<std::string>())  return JS_NewStringLen(context, str->data(), str->size());
	if (const double *number = plist.getIf<double>())  return JS_NewNumber(context, *number);
	if (const oo::PList::Array *array = plist.getIf<oo::PList::Array>())
	{
		JSValue object = JS_NewArray(context);
		std::uint32_t index = 0;
		for (const oo::PList &element : *array)  JS_SetPropertyUint32(context, object, index++, OOJSValueFromPList(context, element));
		return object;
	}
	return JS_NULL;
}


namespace {
JSClassDef sFakeEntityClass = { .class_name = "Entity" };
JSClassID sFakeEntityClassID = 0;
std::map<JSClassID, int> sConverters;


/*	Entity's toString(), as the game's (OOJSObjectWrapperToString() of an object with no
	description of its own): "[object <its class>]". QuickJS-ng gives class prototypes no
	Symbol.toStringTag, so without it String(plainEntity) would be "[object Object]".
*/
JSValue FakeEntityToString(OOJS_NATIVE_ARGS)
{
	(void)argc;
	(void)OOJS_ARGV;
	JSClassID ignored;
	id object = (id)JS_GetAnyOpaque(OOJS_THIS, &ignored);
	std::string description = oo::str::format("[object %s]", object != nil ? class_getName(object_getClass(object)) : "Entity");
	return JS_NewStringLen(context, description.data(), description.size());
}

const JSCFunctionListEntry sFakeEntityMethods[] = {
	JS_CFUNC_DEF("toString", 0, FakeEntityToString),
};
} // namespace


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
OOSunEntity *sSun = nil;


// A JS object of the class (its prototype is the class's), with the entity in the private slot;
// owned by the caller.
JSValue JSValueForObject(JSClassID classID, Entity *entity)
{
	JSValue object = JS_NewObjectClass(sContext, static_cast<int>(classID));
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
	OOJSInitClass(sContext, sGlobal, sFakeEntityClassID, JS_UNDEFINED, OOJSUnconstructableConstruct, 0, nullptr, 0, sFakeEntityMethods, OOJS_COUNT(sFakeEntityMethods), nullptr, 0);
	InitOOJSSun(sContext, sGlobal);

	sSun = [[OOSunEntity alloc] init];	// kept for the life of the test
	sSun->_radius = 250000.5;
	sSun->_name = "Lave";
	Define("sun", JSValueForEntity(sSun));
	Define("plainEntity", JSValueForObject(sFakeEntityClassID, [[Entity alloc] init]));	// kept for the life of the test
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
	const JSClassID sunClass = [sSun oo_jsClassID];
	OO_CHECK(sunClass != 0 && OOJSClassName(sunClass) != nullptr && std::strcmp(OOJSClassName(sunClass), "Sun") == 0);
	JSValue prototype = JS_GetClassProto(sContext, sunClass);
	OO_CHECK(JS_IsObject(prototype));
	JS_FreeValue(sContext, prototype);
	OO_CHECK(OOJSIsSubclass(sunClass, sFakeEntityClassID));
	OO_CHECK_EQ(sConverters[sunClass], 1);
	OO_CHECK([sSun cxx_oo_jsClassName] == std::optional<std::string>("Sun"));
	OO_CHECK([sSun isVisibleToScripts]);
	OO_CHECK_EVAL("typeof Sun", "function");
	OO_CHECK_EVAL("new Sun()", "threw: unconstructable");
	OO_CHECK_EVAL("Object.getPrototypeOf(Sun.prototype) === Entity.prototype", "true");
	OO_CHECK_EVAL("sun instanceof Sun", "true");
}


OO_TEST(properties)
{
	SetUpContext();
	OO_CHECK_EVAL("sun.radius", "250000.5");
	OO_CHECK_EVAL("sun.name", "Lave");
	OO_CHECK_EVAL("sun.hasGoneNova", "false");
	OO_CHECK_EVAL("sun.isGoingNova", "false");
	OO_CHECK_EVAL("Object.keys(Sun.prototype).join()", "hasGoneNova,isGoingNova,name,radius");
	sSun->_name = std::nullopt;
	OO_CHECK_EVAL("sun.name", "null");
	sSun->_name = "Lave";
	// Read-only.
	OO_CHECK_EVAL("(function () { sun.radius = 1; return sun.radius; })()", "250000.5");
}


OO_TEST(nova)
{
	SetUpContext();
	sSun->_novaCalls = 0;
	OO_CHECK_EVAL("sun.goNova(30)", "undefined");
	OO_CHECK(sSun->_willGoNova && sSun->_novaTime == 30 && sSun->_novaCalls == 1);
	OO_CHECK_EVAL("sun.isGoingNova", "true");
	OO_CHECK_EVAL("sun.goNova()", "undefined");
	OO_CHECK(sSun->_novaTime == 0 && sSun->_novaCalls == 2);
	OO_CHECK_EVAL("sun.cancelNova()", "undefined");
	OO_CHECK(!sSun->_willGoNova && sSun->_novaCalls == 3);
	OO_CHECK_EVAL("sun.cancelNova()", "undefined");	// not going nova: nothing to cancel
	OO_CHECK_EQ(sSun->_novaCalls, 3);
	// Gone nova: isGoingNova is false, and cancelNova() does nothing.
	sSun->_willGoNova = YES;
	sSun->_goneNova = YES;
	OO_CHECK_EVAL("sun.hasGoneNova", "true");
	OO_CHECK_EVAL("sun.isGoingNova", "false");
	OO_CHECK_EVAL("sun.cancelNova()", "undefined");
	OO_CHECK_EQ(sSun->_novaCalls, 3);
	sSun->_willGoNova = NO;
	sSun->_goneNova = NO;
}


OO_TEST(otherObjects)
{
	OO_CHECK_EVAL("Object.getOwnPropertyDescriptor(Sun.prototype, 'radius').get.call(plainEntity)", "threw: Native method expected Sun, got [object Entity].");
	OO_CHECK_EVAL("Sun.prototype.goNova.call({})", "threw: Native method expected Sun, got [object Object].");
	OO_CHECK_EVAL("Sun.prototype.radius", "0");	// the prototype has no sun: a message to nil
}


OO_TEST(nativeExceptions)
{
	SetUpContext();
	// The property getter is a native (OOJS_NATIVE_ENTER): a raise from the entity is a JS error,
	// and so is a C++ exception.
	sSun->_radius = 99;
	OO_CHECK_EVAL("sun.radius", "threw: Native exception: radius boom");
	sSun->_radius = 98;
	OO_CHECK_EVAL("sun.radius", "threw: Native exception: cxx boom");
	sSun->_radius = 250000.5;
	OO_CHECK_EVAL("sun.radius", "250000.5");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
}


OO_TEST_MAIN()
