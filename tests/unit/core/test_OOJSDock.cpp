/*	test_OOJSDock.mm
	Unit tests for the Dock JS binding (src/Core/Scripting/OOJSDock.h/.mm) and the DockEntity
	answers that DockEntity's overrides give the engine.

	As test_OOJSWormhole.mm does, it runs the JS class in a real QuickJS-ng context, links the
	game's own objects for the binding, its bridge, the engine's class registry (OOJSClasses.mm) and
	its exception translator (OOJSEngineNativeWrappers.mm), and stands in for the entity classes
	(Entity, ShipEntity, DockEntity answer only the selectors the binding sends) and for the engine
	functions the binding links against, with the engine header's linkage. The tests pin the JS-visible behaviour
	(the five properties, the three writable ones, isQueued(), a non-dock, a native's exception)
	and what the category answers the engine.
	Run: tests/run.sh unit
*/

#include "OOFoundation.h"
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#include "EntityManualRefs.h"  // the tests' manual references (T097)

#include <quickjs.h>


// MARK: The entity classes, as far as the binding sees them ---------------------------------------

// The C++ root, as far as the binding and the root's JS category reach it.
class Entity : public oo::Object
{
public:
	virtual ~Entity();
	virtual JSClassID jsClassID();
	virtual std::optional<std::string> jsClassName();
};

// The ship (a ship's part is a plain one, held by its object as a dock's is).
class ShipEntity : public Entity
{
};

// The object: the root's, which holds the C++ part (oo::ToCxx reads it) and asks it the JS questions.
// What an entity's JS object holds: a weak reference to the C++ entity.
#include "OOJSEntityHolder.h"


// Its category's two selectors are members of the same names.
class TestEntityObject final : public oo::Object
{
public:
	JSClassID oo_jsClassID();
	std::optional<std::string> oo_jsClassName();

	std::shared_ptr<Entity> _cxxEntity;
};

/*	A dock (its object is the ship's facade); the members the binding calls,
   declared as DockEntity.h declares them (the test imports no game header that
   defines the class), with the stand-in's answers. A dock whose docking queue
   holds 99 ships raises from countOfShipsInDockingQueue(), one whose queue
   holds 98 throws a C++ exception, so the test sees what an exception under a
   native becomes.
*/
class DockEntity : public ShipEntity
{
public:
	JSClassID jsClassID() override;
	std::optional<std::string> jsClassName() override;
	bool allowsDocking();
	void setAllowsDocking(bool allowed);
	bool disallowedDockingCollides();
	void setDisallowedDockingCollides(bool ddc);
	bool allowsLaunching();
	void setAllowsLaunching(bool allowed);
	std::size_t countOfShipsInDockingQueue();
	std::size_t countOfShipsInLaunchQueue();
	bool shipIsInDockingQueue(::ShipEntity *ship);

	bool _allowsDocking = false;
	bool _disallowedDockingCollides = false;
	bool _allowsLaunching = false;
	std::size_t _dockingQueue = 0;
	std::size_t _launchQueue = 0;
	::ShipEntity *_queued = nullptr;
};

#include "OOJSDock.h"
#include "OOJSEngineCore.h"

#include "oo_test.hpp"

#include <cstdarg>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>


Entity::~Entity() = default;
std::optional<std::string> Entity::jsClassName()  { return std::nullopt; }


// As the game's Entity (OOJavaScriptExtensions) answers for an entity made in C++: its C++ part's.
JSClassID TestEntityObject::oo_jsClassID()  { return _cxxEntity->jsClassID(); }
std::optional<std::string> TestEntityObject::oo_jsClassName()  { return _cxxEntity->jsClassName(); }


bool DockEntity::allowsDocking()  { return _allowsDocking; }
void DockEntity::setAllowsDocking(bool allowed)  { _allowsDocking = allowed; }
bool DockEntity::disallowedDockingCollides()  { return _disallowedDockingCollides; }
void DockEntity::setDisallowedDockingCollides(bool ddc)  { _disallowedDockingCollides = ddc; }
bool DockEntity::allowsLaunching()  { return _allowsLaunching; }
void DockEntity::setAllowsLaunching(bool allowed)  { _allowsLaunching = allowed; }
std::size_t DockEntity::countOfShipsInLaunchQueue()  { return _launchQueue; }
bool DockEntity::shipIsInDockingQueue(::ShipEntity *ship)  { return ship == _queued; }

std::size_t DockEntity::countOfShipsInDockingQueue()
{
	if (_dockingQueue == 99)  OORaiseException(OOInvalidArgumentException, "queue %s", "boom");
	if (_dockingQueue == 98)  throw std::runtime_error("cxx boom");
	return _dockingQueue;
}


// What the game's C++ DockEntity answers the engine (its overrides call these two functions).
JSClassID DockEntity::jsClassID()
{
	return ::JSDockClassID();
}


std::optional<std::string> DockEntity::jsClassName()
{
	return ::OOJSDockJSClassName();
}


// MARK: What the rest of the engine provides ------------------------------------------------------

JSContext *gOOJSMainThreadContext = nullptr;	// the engine's


void OOJSReportErrorWithArguments(JSContext *context, const char *format, va_list args)
{
	std::string msg = oo::str::vformat(format, args);
	JS_ThrowPlainError(context, "%s", msg.c_str());
}


void OOJSReportError(JSContext *context, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	OOJSReportErrorWithArguments(context, format, args);
	va_end(args);
}


void OOJSReportBadArguments(JSContext *context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, int argc, JSValueConst *, const std::optional<std::string> &message, const std::optional<std::string> &expectedArgsDescription)
{
	OOJSReportError(context, "bad arguments: %s.%s (%d): %s; expected %s", scriptClass.value_or("").c_str(), function.value_or("").c_str(), argc, message.value_or("").c_str(), expectedArgsDescription.value_or("").c_str());
}


std::optional<std::string> OOStringFromJSValue(JSContext *context, JSValueConst value)
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
JSAtom OOJSIDFromString(const std::string &string)
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


JSClassID Entity::jsClassID()
{
	return sFakeEntityClassID;
}


JSClassID JSShipClassID(void)
{
	return sFakeShipClassID;
}


void OOJSReportBadPropertySelector(JSContext *context, JSValueConst, int, const JSCFunctionListEntry *, size_t)
{
	OOJSReportError(context, "bad property selector");
}


void OOJSReportBadPropertyValue(JSContext *context, JSValueConst, int, const JSCFunctionListEntry *, size_t, JSValueConst)
{
	OOJSReportError(context, "bad property value");
}


void OOJSRegisterObjectConverter(JSClassID classID, OOJSClassConverterCallback)
{
	sConverters[classID]++;
}


// The engine's object getter is OOJSPrivateObject.cpp's (linked): the JS class must be a
// subclass of the required one, and the slot holds the entity's holder.

// The shared toString(), which OOJSCxxObjectWrapperToString() hands a `this` of another class.
JSValue OOJSObjectWrapperToString(JSContext *context, JSValueConst, int, JSValueConst *)
{
	return JS_NewString(context, "[object]");
}


JSValue OOJSUnconstructableConstruct(JSContext *context, JSValueConst, int, JSValueConst *)
{
	OOJSReportError(context, "unconstructable");
	return JS_EXCEPTION;
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


oo::PList OOJSEntityObjectConverter(JSContext *, JSValueConst)
{
	return oo::PList();
}


// The holder's glue is OOJSEntity.mm's, which the test does not link; the binding never asks it.
JSValue OOJSEntityHolder::jsValueInContext(JSContext *)  { return JS_UNDEFINED; }
void OOJSEntityHolder::clearJSSelf(JSValueConst)  {}
std::optional<std::string> OOJSEntityHolder::jsDescription()  { return std::nullopt; }


// MARK: The context -------------------------------------------------------------------------------

namespace {

JSRuntime *sRuntime;
JSContext *sContext;
JSValue sGlobal;
DockEntity *sDock = nullptr;	// the C++ dock (its object: sDockObject)
TestEntityObject *sDockObject = nullptr;
TestEntityObject *sShip = nullptr;	// a ship's object and its C++ part
ShipEntity *sShipPart = nullptr;


// A ship's object holding its C++ part, kept for the life of the test.
TestEntityObject *NewShipObject(std::shared_ptr<Entity> part)
{
	TestEntityObject *object = oo::test::NewRetained<TestEntityObject>();
	object->_cxxEntity = part;
	return object;
}


// A JS object of the class (its prototype is the class's), with the entity in the private slot;
// owned by the caller.
JSValue JSValueForObject(JSClassID classID, TestEntityObject *entity)
{
	JSValue object = JS_NewObjectClass(sContext, static_cast<int>(classID));
	if (entity->_cxxEntity == nullptr)  entity->_cxxEntity = oo::makeShared<Entity>();	// a plain entity's C++ part
	if (JS_IsException(object) || !OOJSSetCxxPrivate(object, oo::makeShared<OOJSEntityHolder>(entity->_cxxEntity.get())))	// the slot holds the C++ entity
	{
		JS_FreeValue(sContext, object);
		return JS_NULL;
	}
	return object;
}


// A JS object for an entity, as the object's -oo_jsValueInContext: made it: the class the entity's
// category names, and the entity in the private slot.
JSValue JSValueForEntity(TestEntityObject *entity)
{
	return JSValueForObject(entity->oo_jsClassID(), entity);
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

	sDockObject = NewShipObject(oo::makeShared<DockEntity>());	// a dock's object is a ship's
	sDock = static_cast<DockEntity *>(sDockObject->_cxxEntity.get());
	sDock->_allowsDocking = true;
	sDock->_disallowedDockingCollides = false;
	sDock->_allowsLaunching = true;
	sDock->_dockingQueue = 3;
	sDock->_launchQueue = 2;
	sShip = NewShipObject(oo::makeShared<ShipEntity>());
	sShipPart = static_cast<ShipEntity *>(sShip->_cxxEntity.get());
	Define("dock", JSValueForEntity(sDockObject));
	Define("ship", JSValueForObject(sFakeShipClassID, sShip));
	Define("otherShip", JSValueForObject(sFakeShipClassID, NewShipObject(oo::makeShared<ShipEntity>())));
	Define("plainEntity", JSValueForObject(sFakeEntityClassID, oo::test::NewRetained<TestEntityObject>()));
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
	std::string text = OOStringFromJSValue(sContext, result).value_or("<not a string>");
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
	const JSClassID dockClassID = sDockObject->oo_jsClassID();
	const char *dockClassName = OOJSClassName(dockClassID);
	OO_CHECK(dockClassID != 0 && dockClassName != nullptr && std::strcmp(dockClassName, "Dock") == 0);
	JSValue prototype = JS_GetClassProto(sContext, dockClassID);
	OO_CHECK(JS_IsObject(prototype));
	JS_FreeValue(sContext, prototype);
	OO_CHECK(OOJSIsSubclass(dockClassID, sFakeShipClassID));
	OO_CHECK_EQ(sConverters[dockClassID], 1);
	OO_CHECK(sDockObject->oo_jsClassName() == std::optional<std::string>("Dock"));
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
	OO_CHECK(sDock->_allowsDocking == false);
	OO_CHECK_EVAL("(function () { dock.allowsLaunching = 0; return dock.allowsLaunching; })()", "false");
	OO_CHECK_EVAL("(function () { dock.disallowedDockingCollides = 'yes'; return dock.disallowedDockingCollides; })()", "true");
	OO_CHECK_EVAL("(function () { dock.allowsDocking = true; dock.allowsLaunching = 1; return dock.allowsDocking && dock.allowsLaunching; })()", "true");
	// The queue lengths are read-only.
	OO_CHECK_EVAL("(function () { dock.dockingQueueLength = 7; return dock.dockingQueueLength; })()", "3");
}


OO_TEST(isQueued)
{
	SetUpContext();
	sDock->_queued = sShipPart;
	OO_CHECK_EVAL("dock.isQueued(ship)", "true");
	OO_CHECK_EVAL("dock.isQueued(otherShip)", "false");
	OO_CHECK_EVAL("dock.isQueued()", "threw: bad arguments: Dock.isQueued (0): ; expected ship");
	sDock->_queued = nullptr;
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
