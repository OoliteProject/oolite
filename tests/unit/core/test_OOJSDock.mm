/*	test_OOJSDock.mm
	Unit tests for the Dock JS binding (src/Core/Scripting/OOJSDock.h/.mm) and its DockEntity
	category (OOJSDock+ObjCBridge.mm): bead oo-zbx3, converted the way bead oo-ppc converted
	OOJSVector (proposed ADR-0056 amendments oo-ppc and oo-ykoy).

	As test_OOJSWormhole.mm does (amendment oo-ykoy, item 4), it runs the JS class in a real
	QuickJS-ng context, links the game's own objects for the binding, its bridge, the engine's class
	registry (OOJSClasses.mm) and its exception translator (OOJSEngineNativeWrappers.mm), and stands
	in for the entity classes (Entity, ShipEntity, DockEntity answer only the selectors the binding
	sends) and for the engine functions the binding links against, with the engine header's
	linkage. The expectations were written against the Objective-C file and run on it first; they
	pin the JS-visible behaviour (the five properties, the three writable ones, isQueued(), a
	non-dock, a native's exception) and what the category answers the engine.
	Run: tests/run.sh unit
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

@interface ShipEntity: Entity
@end

/*	A dock whose docking queue holds 99 ships raises from -countOfShipsInDockingQueue, one whose
	queue holds 98 throws a C++ exception, so the test sees what an exception under a native
	becomes.
*/
@interface DockEntity: ShipEntity
{
@public
	BOOL _allowsDocking;
	BOOL _disallowedDockingCollides;
	BOOL _allowsLaunching;
	NSUInteger _dockingQueue;
	NSUInteger _launchQueue;
	ShipEntity *_queued;
}
- (BOOL) allowsDocking;
- (void) setAllowsDocking:(BOOL)allow;
- (BOOL) disallowedDockingCollides;
- (void) setDisallowedDockingCollides:(BOOL)ddc;
- (BOOL) allowsLaunching;
- (void) setAllowsLaunching:(BOOL)allow;
- (NSUInteger) countOfShipsInDockingQueue;
- (NSUInteger) countOfShipsInLaunchQueue;
- (BOOL) shipIsInDockingQueue:(ShipEntity *)ship;
@end

@interface Entity (OOJavaScriptExtensions)
- (JSClassID) oo_jsClassID;
- (std::optional<std::string>) cxx_oo_jsClassName;
@end


#import "OOJSDock.h"
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


@implementation ShipEntity
@end


@implementation DockEntity

- (BOOL) allowsDocking  { return _allowsDocking; }
- (void) setAllowsDocking:(BOOL)allow  { _allowsDocking = allow; }
- (BOOL) disallowedDockingCollides  { return _disallowedDockingCollides; }
- (void) setDisallowedDockingCollides:(BOOL)ddc  { _disallowedDockingCollides = ddc; }
- (BOOL) allowsLaunching  { return _allowsLaunching; }
- (void) setAllowsLaunching:(BOOL)allow  { _allowsLaunching = allow; }
- (NSUInteger) countOfShipsInLaunchQueue  { return _launchQueue; }
- (BOOL) shipIsInDockingQueue:(ShipEntity *)ship  { return ship == _queued; }

- (NSUInteger) countOfShipsInDockingQueue
{
	if (_dockingQueue == 99)  [OOException raise:OOInvalidArgumentException format:"queue %s", "boom"];
	if (_dockingQueue == 98)  throw std::runtime_error("cxx boom");
	return _dockingQueue;
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


void cxx_OOJSReportBadArguments(JSContext *context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, int argc, JSValueConst *, const std::optional<std::string> &message, const std::optional<std::string> &expectedArgsDescription)
{
	cxx_OOJSReportError(context, "bad arguments: %s.%s (%d): %s; expected %s", scriptClass.value_or("").c_str(), function.value_or("").c_str(), argc, message.value_or("").c_str(), expectedArgsDescription.value_or("").c_str());
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
JSClassDef sFakeShipClass = { .class_name = "Ship" };
JSClassID sFakeEntityClassID = 0;
JSClassID sFakeShipClassID = 0;
std::map<JSClassID, int> sConverters;
} // namespace


JSClassID JSEntityClassID(void)
{
	return sFakeEntityClassID;
}


JSClassID JSShipClassID(void)
{
	return sFakeShipClassID;
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
DockEntity *sDock = nil;
ShipEntity *sShip = nil;


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
	OOJSInitClass(sContext, sGlobal, sFakeEntityClassID, JS_UNDEFINED, OOJSUnconstructableConstruct, 0, nullptr, 0, nullptr, 0, nullptr, 0);
	OOJSRegisterClass(&sFakeShipClassID, &sFakeShipClass);
	JSValue entityPrototype = JS_GetClassProto(sContext, sFakeEntityClassID);
	OOJSInitClass(sContext, sGlobal, sFakeShipClassID, entityPrototype, OOJSUnconstructableConstruct, 0, nullptr, 0, nullptr, 0, nullptr, 0);
	JS_FreeValue(sContext, entityPrototype);
	OOJSRegisterSubclass(sFakeShipClassID, sFakeEntityClassID);
	InitOOJSDock(sContext, sGlobal);

	sDock = [[DockEntity alloc] init];	// kept for the life of the test
	sDock->_allowsDocking = YES;
	sDock->_disallowedDockingCollides = NO;
	sDock->_allowsLaunching = YES;
	sDock->_dockingQueue = 3;
	sDock->_launchQueue = 2;
	sShip = [[ShipEntity alloc] init];
	Define("dock", JSValueForEntity(sDock));
	Define("ship", JSValueForObject(sFakeShipClassID, sShip));
	Define("otherShip", JSValueForObject(sFakeShipClassID, [[ShipEntity alloc] init]));
	Define("plainEntity", JSValueForObject(sFakeEntityClassID, [[Entity alloc] init]));
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
	const JSClassID dockClassID = [sDock oo_jsClassID];
	const char *dockClassName = OOJSClassName(dockClassID);
	OO_CHECK(dockClassID != 0 && dockClassName != nullptr && std::strcmp(dockClassName, "Dock") == 0);
	JSValue prototype = JS_GetClassProto(sContext, dockClassID);
	OO_CHECK(JS_IsObject(prototype));
	JS_FreeValue(sContext, prototype);
	OO_CHECK(OOJSIsSubclass(dockClassID, sFakeShipClassID));
	OO_CHECK_EQ(sConverters[dockClassID], 1);
	OO_CHECK([sDock cxx_oo_jsClassName] == std::optional<std::string>("Dock"));
	OO_CHECK_EVAL("typeof Dock", "function");
	OO_CHECK_EVAL("new Dock()", "threw: unconstructable");
	OO_CHECK_EVAL("Object.getPrototypeOf(Dock.prototype) === Ship.prototype", "true");
	OO_CHECK_EVAL("dock instanceof Dock && dock instanceof Ship", "true");
}


OO_TEST(properties)
{
	OO_CHECK_EVAL("dock.allowsDocking", "true");
	OO_CHECK_EVAL("dock.disallowedDockingCollides", "false");
	OO_CHECK_EVAL("dock.allowsLaunching", "true");
	OO_CHECK_EVAL("dock.dockingQueueLength", "3");
	OO_CHECK_EVAL("dock.launchingQueueLength", "2");
	OO_CHECK_EVAL("Object.keys(Dock.prototype).join()", "allowsDocking,disallowedDockingCollides,allowsLaunching,dockingQueueLength,launchingQueueLength");
	// The three flags are writable, and a value converts to a boolean.
	OO_CHECK_EVAL("(function () { dock.allowsDocking = false; return dock.allowsDocking; })()", "false");
	OO_CHECK(sDock->_allowsDocking == NO);
	OO_CHECK_EVAL("(function () { dock.allowsLaunching = 0; return dock.allowsLaunching; })()", "false");
	OO_CHECK_EVAL("(function () { dock.disallowedDockingCollides = 'yes'; return dock.disallowedDockingCollides; })()", "true");
	OO_CHECK_EVAL("(function () { dock.allowsDocking = true; dock.allowsLaunching = 1; return dock.allowsDocking && dock.allowsLaunching; })()", "true");
	// The queue lengths are read-only.
	OO_CHECK_EVAL("(function () { dock.dockingQueueLength = 7; return dock.dockingQueueLength; })()", "3");
}


OO_TEST(isQueued)
{
	SetUpContext();
	sDock->_queued = sShip;
	OO_CHECK_EVAL("dock.isQueued(ship)", "true");
	OO_CHECK_EVAL("dock.isQueued(otherShip)", "false");
	OO_CHECK_EVAL("dock.isQueued()", "threw: bad arguments: Dock.isQueued (0): ; expected ship");
	sDock->_queued = nil;
	OO_CHECK_EVAL("dock.isQueued(ship)", "false");
}


OO_TEST(otherObjects)
{
	// A ship that is not a dock, and the prototype (no entity at all): the binding's getter and
	// setter fail without reporting an error, which ends the script uncatchably.
	OO_CHECK_EVAL("Object.getOwnPropertyDescriptor(Dock.prototype, 'allowsDocking').get.call(ship)", "<evaluation failed>");
	OO_CHECK_EVAL("Dock.prototype.allowsDocking", "<evaluation failed>");
	OO_CHECK_EVAL("(function () { Dock.prototype.allowsDocking = false; return 'ok'; })()", "<evaluation failed>");
	// Something that is not an entity: the engine's getter reports it.
	OO_CHECK_EVAL("Object.getOwnPropertyDescriptor(Dock.prototype, 'allowsDocking').get.call({})", "threw: Native method expected Entity, got [object Object].");
	OO_CHECK_EVAL("dock.allowsLaunching", "true");
}


OO_TEST(nativeExceptions)
{
	SetUpContext();
	// The property getter is a native (OOJS_NATIVE_ENTER): a raise from the entity is a JS error,
	// and so is a C++ exception.
	sDock->_dockingQueue = 99;
	OO_CHECK_EVAL("dock.dockingQueueLength", "threw: Native exception: queue boom");
	sDock->_dockingQueue = 98;
	OO_CHECK_EVAL("dock.dockingQueueLength", "threw: Native exception: cxx boom");
	sDock->_dockingQueue = 3;
	OO_CHECK_EVAL("dock.dockingQueueLength", "3");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
}


OO_TEST_MAIN()
