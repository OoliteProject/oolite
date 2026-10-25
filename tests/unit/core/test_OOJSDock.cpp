/*	test_OOJSDock.mm
	Unit tests for the Dock JS binding (src/Core/Scripting/OOJSDock.h/.mm) and the DockEntity
	answers that DockEntity's overrides give the engine (bead oo-9ht.47): bead oo-zbx3, converted the way bead oo-ppc converted
	OOJSVector (proposed ADR-0056 amendments oo-ppc and oo-ykoy).

	As test_OOJSWormhole.mm does (amendment oo-ykoy, item 4), it runs the JS class in a real
	context on the game's own façade backend (ooscript/JSEngine_quickjs.cpp), links the game's own
	objects for the binding, its bridge and the engine's exception translator
	(OOJSEngineNativeWrappers.mm), and stands in for the entity classes (Entity, ShipEntity,
	DockEntity answer only the selectors the binding sends) and for the engine functions the
	binding links against, with the engine header's linkage. The expectations were written against
	the Objective-C file and run on it first; they pin the JS-visible behaviour (the five
	properties, the three writable ones, isQueued(), a non-dock, a native's exception) and what the
	category answers the engine. Run: bash tools/check-core-tests.sh
*/

#include "OOCocoa.h"
#include "ooscript/JSEngine.hpp"
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"


// MARK: The entity classes, as far as the binding sees them ---------------------------------------

// The C++ root, as far as the binding and the root's JS category reach it.
class Entity : public oo::RefCounted
{
public:
	virtual ~Entity();
	virtual void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype);
	virtual std::optional<std::string> jsClassName();
};

// The ship: C++ since bead oo-9ht.144 deleted the Objective-C ship this stood in for (a ship's part
// is a plain one, held by its object as a dock's is).
class ShipEntity : public Entity
{
};

// The object: the root's, which holds the C++ part (oo::ToCxx reads it) and asks it the JS questions.
// What an entity's JS object holds since bead oo-9ht.39.3: a weak reference to the C++ entity.
#include "OOJSEntityHolder.h"


// C++ since bead oo-4aq6a.11 (it was rooted on the Objective-C root class OOObject, which Phase 4
// deletes); its category's two selectors are members of the same names.
class TestEntityObject final : public oo::RefCounted
{
public:
	void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype);
	std::optional<std::string> cxx_oo_jsClassName();

	oo::Ref<Entity> _cxxEntity;
};

/*	A dock: C++ since bead oo-9ht.180 deleted the Objective-C dock this stood in for (its object is the
	ship's facade); the members the binding calls, declared as DockEntity.h declares them (the test
	imports no game header that defines the class), with the stand-in's answers. A dock whose
	docking queue holds 99 ships raises from countOfShipsInDockingQueue(), one whose queue holds 98
	throws a C++ exception, so the test sees what an exception under a native becomes.
*/
class DockEntity : public ShipEntity
{
public:
	void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype) override;
	std::optional<std::string> jsClassName() override;
	bool allowsDocking();
	void setAllowsDocking(bool allowed);
	bool disallowedDockingCollides();
	void setDisallowedDockingCollides(bool ddc);
	bool allowsLaunching();
	void setAllowsLaunching(bool allowed);
	NSUInteger countOfShipsInDockingQueue();
	NSUInteger countOfShipsInLaunchQueue();
	bool shipIsInDockingQueue(::ShipEntity *ship);

	BOOL _allowsDocking = NO;
	BOOL _disallowedDockingCollides = NO;
	BOOL _allowsLaunching = NO;
	NSUInteger _dockingQueue = 0;
	NSUInteger _launchQueue = 0;
	::ShipEntity *_queued = nullptr;
};

#include "OOJSDock.h"

#include "oo_test.hpp"

#include <cstdarg>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>


Entity::~Entity() = default;
void Entity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)  { (void)outClass; (void)outPrototype; }
std::optional<std::string> Entity::jsClassName()  { return std::nullopt; }


// As the game's Entity (OOJavaScriptExtensions) answers for an entity made in C++: its C++ part's.
void TestEntityObject::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)  { _cxxEntity->getJSClass(outClass, outPrototype); }
std::optional<std::string> TestEntityObject::cxx_oo_jsClassName()  { return _cxxEntity->jsClassName(); }


bool DockEntity::allowsDocking()  { return _allowsDocking; }
void DockEntity::setAllowsDocking(bool allowed)  { _allowsDocking = allowed; }
bool DockEntity::disallowedDockingCollides()  { return _disallowedDockingCollides; }
void DockEntity::setDisallowedDockingCollides(bool ddc)  { _disallowedDockingCollides = ddc; }
bool DockEntity::allowsLaunching()  { return _allowsLaunching; }
void DockEntity::setAllowsLaunching(bool allowed)  { _allowsLaunching = allowed; }
NSUInteger DockEntity::countOfShipsInLaunchQueue()  { return _launchQueue; }
bool DockEntity::shipIsInDockingQueue(::ShipEntity *ship)  { return ship == _queued; }

NSUInteger DockEntity::countOfShipsInDockingQueue()
{
	if (_dockingQueue == 99)  OORaiseException(OOInvalidArgumentException, "queue %s", "boom");
	if (_dockingQueue == 98)  throw std::runtime_error("cxx boom");
	return _dockingQueue;
}


// What the game's C++ DockEntity answers the engine (its overrides call these two functions).
void DockEntity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)
{
	::OOJSDockGetJSClass(outClass, outPrototype);
}


std::optional<std::string> DockEntity::jsClassName()
{
	return ::OOJSDockJSClassName();
}


// MARK: What the rest of the engine provides ------------------------------------------------------

void cxx_OOJSReportErrorWithArguments(ooscript::Context context, const char *format, va_list args)
{
	std::string msg = oo::str::vformat(format, args);
	ooscript::reportError(context, msg.c_str());
}


void cxx_OOJSReportError(ooscript::Context context, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	cxx_OOJSReportErrorWithArguments(context, format, args);
	va_end(args);
}


void cxx_OOJSReportBadArguments(ooscript::Context context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, unsigned argc, ooscript::Value *, const std::optional<std::string> &message, const std::optional<std::string> &expectedArgsDescription)
{
	cxx_OOJSReportError(context, "bad arguments: %s.%s (%u): %s; expected %s", scriptClass.value_or("").c_str(), function.value_or("").c_str(), argc, message.value_or("").c_str(), expectedArgsDescription.value_or("").c_str());
}


std::optional<std::string> cxx_OOStringFromJSValue(ooscript::Context context, ooscript::Value value)
{
	if (ooscript::isNullOrUndefined(value))  return std::nullopt;
	ooscript::String str = ooscript::valueToString(context, value);
	if (str == nullptr)  return std::nullopt;
	std::size_t length = 0;
	const ooscript::Char16 *chars = ooscript::getStringCharsAndLength(context, str, &length);
	std::string result;
	for (std::size_t i = 0; i < length; i++)  result += static_cast<char>(chars[i]);	// the test's strings are ASCII
	return result;
}


namespace {
ooscript::ClassDef sFakeEntityClass = { "Entity", ooscript::ClassFlag::HasPrivate };
ooscript::ClassDef sFakeShipClass = { "Ship", ooscript::ClassFlag::HasPrivate };
ooscript::Object sShipPrototype = nullptr;
std::map<ooscript::ClassDef *, ooscript::ClassDef *> sSuperclasses;
std::map<ooscript::ClassDef *, int> sConverters;
} // namespace

ooscript::Object gOOEntityJSPrototype = nullptr;


extern "C" {

ooscript::ClassDef *JSEntityClass(void)
{
	return &sFakeEntityClass;
}


ooscript::ClassDef *JSShipClass(void)
{
	return &sFakeShipClass;
}


ooscript::Object JSShipPrototype(void)
{
	return sShipPrototype;
}


void OOJSReportBadPropertySelector(ooscript::Context context, ooscript::Object, ooscript::PropertyId, ooscript::PropertySpec *)
{
	cxx_OOJSReportError(context, "bad property selector");
}


void OOJSReportBadPropertyValue(ooscript::Context context, ooscript::Object, ooscript::PropertyId, ooscript::PropertySpec *, ooscript::Value)
{
	cxx_OOJSReportError(context, "bad property value");
}


void OOJSRegisterSubclass(ooscript::ClassDef *subclass, ooscript::ClassDef *superclass)
{
	sSuperclasses[subclass] = superclass;
}


BOOL OOJSIsSubclass(ooscript::ClassDef *putativeSubclass, ooscript::ClassDef *superclass)
{
	for (ooscript::ClassDef *c = putativeSubclass; c != nullptr; c = sSuperclasses.count(c) != 0 ? sSuperclasses[c] : nullptr)
	{
		if (c == superclass)  return YES;
	}
	return NO;
}


void OOJSRegisterObjectConverter(ooscript::ClassDef *theClass, oo::PList (*)(ooscript::Context, ooscript::Object))
{
	sConverters[theClass]++;
}


// The engine's object getter is OOJSPrivateObject.cpp's (linked) since bead oo-9ht.39.3: the JS
// class must be a subclass of the required one, and the slot holds the entity's holder.

// The shared toString(), which OOJSCxxObjectWrapperToString() hands a `this` of another class.
bool OOJSObjectWrapperToString(ooscript::Context context, ooscript::CallArgs &args)
{
	const std::string text = "[object]";
	args.setRval(ooscript::stringValue(ooscript::newStringCopyN(context, text.data(), text.size())));
	return true;
}


bool OOJSUnconstructableConstruct(ooscript::Context context, ooscript::CallArgs &)
{
	cxx_OOJSReportError(context, "unconstructable");
	return false;
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

}	// extern "C"


oo::PList OOJSEntityObjectConverter(ooscript::Context, ooscript::Object)
{
	return oo::PList();
}


// The holder's glue is OOJSEntity.mm's, which the test does not link; the binding never asks it.
ooscript::Value OOJSEntityHolder::jsValueInContext(ooscript::Context)  { return ooscript::undefinedValue(); }
void OOJSEntityHolder::clearJSSelf(ooscript::Object)  {}
std::optional<std::string> OOJSEntityHolder::jsDescription()  { return std::nullopt; }


// MARK: The context -------------------------------------------------------------------------------

namespace {

ooscript::Runtime sRuntime;
ooscript::Context sContext;
ooscript::Object sGlobal;
DockEntity *sDock = nullptr;	// the C++ dock (its object: sDockObject)
TestEntityObject *sDockObject = nullptr;
TestEntityObject *sShip = nullptr;	// a ship's object and its C++ part (the Objective-C ship until bead oo-9ht.144)
ShipEntity *sShipPart = nullptr;


// A ship's object holding its C++ part, kept for the life of the test.
TestEntityObject *NewShipObject(oo::Ref<Entity> part)
{
	TestEntityObject *object = oo::makeRef<TestEntityObject>().leakRef();
	object->_cxxEntity = part;
	return object;
}


ooscript::Value JSValueForObject(ooscript::ClassDef *jsClass, ooscript::Object prototype, TestEntityObject *entity)
{
	ooscript::Object object = ooscript::newObject(sContext, jsClass, prototype, nullptr);
	if (entity->_cxxEntity == nullptr)  entity->_cxxEntity = oo::makeRef<Entity>();	// a plain entity's C++ part
	if (object == nullptr || !OOJSSetCxxPrivate(sContext, object, oo::makeRef<OOJSEntityHolder>(entity->_cxxEntity.get()).get()))  return ooscript::nullValue();	// the slot holds the C++ entity (bead oo-9ht.39.3)
	return ooscript::objectValue(object);
}


// A JS object for an entity, as the object's -oo_jsValueInContext: made it: the class and prototype
// the entity's category names, and the entity in the private slot.
ooscript::Value JSValueForEntity(TestEntityObject *entity)
{
	ooscript::ClassDef *jsClass = nullptr;
	ooscript::Object prototype = nullptr;
	entity->getJSClass(&jsClass, &prototype);
	return JSValueForObject(jsClass, prototype, entity);
}


void Define(const char *name, ooscript::Value value)
{
	ooscript::setProperty(sContext, sGlobal, name, &value);
}


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = ooscript::newRuntime(8u * 1024u * 1024u);
	sContext = ooscript::newContext(sRuntime, 8192);
	ooscript::beginRequest(sContext);
	sGlobal = ooscript::getGlobalObject(sContext);
	ooscript::initStandardClasses(sContext, sGlobal);
	gOOEntityJSPrototype = ooscript::initClass(sContext, sGlobal, nullptr, &sFakeEntityClass, OOJSUnconstructableConstruct, 0, nullptr, nullptr, nullptr, nullptr);
	sShipPrototype = ooscript::initClass(sContext, sGlobal, gOOEntityJSPrototype, &sFakeShipClass, OOJSUnconstructableConstruct, 0, nullptr, nullptr, nullptr, nullptr);
	OOJSRegisterSubclass(&sFakeShipClass, &sFakeEntityClass);
	InitOOJSDock(sContext, sGlobal);

	sDockObject = NewShipObject(oo::makeRef<DockEntity>());	// a dock's object is a ship's since bead oo-9ht.180
	sDock = static_cast<DockEntity *>(sDockObject->_cxxEntity.get());
	sDock->_allowsDocking = YES;
	sDock->_disallowedDockingCollides = NO;
	sDock->_allowsLaunching = YES;
	sDock->_dockingQueue = 3;
	sDock->_launchQueue = 2;
	sShip = NewShipObject(oo::makeRef<ShipEntity>());
	sShipPart = static_cast<ShipEntity *>(sShip->_cxxEntity.get());
	Define("dock", JSValueForEntity(sDockObject));
	Define("ship", JSValueForObject(&sFakeShipClass, sShipPrototype, sShip));
	Define("otherShip", JSValueForObject(&sFakeShipClass, sShipPrototype, NewShipObject(oo::makeRef<ShipEntity>())));
	Define("plainEntity", JSValueForObject(&sFakeEntityClass, gOOEntityJSPrototype, oo::makeRef<TestEntityObject>().leakRef()));
}


// Evaluates src and gives its result as a string ("undefined", "null", ...), or "threw: <message>".
std::string Eval(const char *src)
{
	SetUpContext();
	std::string wrapped = std::string("(function () { try { return String(") + src + "); } catch (e) { return 'threw: ' + (e && e.message !== undefined ? e.message : e); } })()";
	ooscript::Value result = ooscript::undefinedValue();
	if (!ooscript::evaluateScript(sContext, sGlobal, wrapped.c_str(), static_cast<unsigned>(wrapped.size()), "test.js", 1, &result))
	{
		ooscript::clearPendingException(sContext);
		return "<evaluation failed>";
	}
	return cxx_OOStringFromJSValue(sContext, result).value_or("<not a string>");
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
	ooscript::ClassDef *dockClass = nullptr;
	ooscript::Object prototype = nullptr;
	sDockObject->getJSClass(&dockClass, &prototype);
	OO_CHECK(dockClass != nullptr && std::strcmp(dockClass->name, "Dock") == 0);
	OO_CHECK(prototype != nullptr);
	OO_CHECK(OOJSIsSubclass(dockClass, &sFakeShipClass));
	OO_CHECK_EQ(sConverters[dockClass], 1);
	OO_CHECK(sDockObject->cxx_oo_jsClassName() == std::optional<std::string>("Dock"));
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
	OO_CHECK(ooscript::isInRequest(sContext));
}


OO_TEST_MAIN()
