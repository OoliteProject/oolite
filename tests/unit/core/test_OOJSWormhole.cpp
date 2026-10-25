/*	test_OOJSWormhole.mm
	Unit tests for the Wormhole JS binding (src/Core/Scripting/OOJSWormhole.h/.mm) and its
	WormholeEntity category (whose forwarders were on the WormholeEntity facade from bead oo-9ht.43
	until bead oo-9ht.112 deleted it: the C++ class's overrides answer the engine now, through the
	root's JS category, and this test's stand-ins are C++ the same way, amendment oo-9ht.107 item
	6): bead oo-ykoy, converted the way bead oo-ppc converted OOJSVector (proposed ADR-0056
	amendments oo-ppc and oo-ykoy).

	It runs the JS class in a real context on the game's own façade backend
	(ooscript/JSEngine_quickjs.cpp) and links the game's own objects for the binding
	and the engine's exception translator (OOJSEngineNativeWrappers.mm). The entity classes it
	reads are stand-ins of the same names (amendment oo-z1s4, item 4), so the test imports neither
	their headers nor OOJavaScriptEngine.h (which imports them): Entity and WormholeEntity answer
	only the selectors the binding sends, and the JS side of an entity is a JS object of the
	binding's class whose private slot is the entity. What the engine provides (the Entity JS
	class, the subclass table, the object getter, error reporting) is defined below as the
	smallest stand-in that does the same thing, with the engine header's linkage. The expectations
	were written against the Objective-C file and run on it first; they pin the JS-visible
	behaviour (the four properties, read-only, a stale entity, the wrong kind of object, a native's
	exception) and what the category answers the engine.
	Run: bash tools/check-core-tests.sh
*/

#include "OOTypes.h"
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
	virtual bool isVisibleToScripts();
};


/*	A wormhole whose arrival time is -1 raises from arrivalTime(), one whose arrival time is -2
	throws a C++ exception, so the test sees what an exception under a native becomes.
*/
class WormholeEntity : public Entity
{
public:
	double arrivalTime();
	double expiryTime();
	OOSystemID getOrigin();
	OOSystemID getDestination();

	void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype) override;
	std::optional<std::string> jsClassName() override;
	bool isVisibleToScripts() override;

	double _arrivalTime = 0;
	double _expiryTime = 0;
	OOSystemID _origin = 0;
	OOSystemID _destination = 0;
};


// What an entity's JS object holds since bead oo-9ht.39.3: a weak reference to the C++ entity.
#include "OOJSEntityHolder.h"


// C++ since bead oo-4aq6a.11 (it was rooted on the Objective-C root class OOObject, which Phase 4
// deletes); its category's selectors are members of the same names.
class TestEntityObject final : public oo::RefCounted
{
public:
	void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype);
	std::optional<std::string> cxx_oo_jsClassName();
	bool isVisibleToScripts();

	oo::Ref<Entity> _cxxEntity;	// the wormhole's C++ part (oo::ToCxx reads it)
};

#include "OOJSWormhole.h"

#include "oo_test.hpp"

#include <cstdarg>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>





// The root's JS category, as the game's asks the C++ part (EntityOOJavaScriptExtensions+ObjCBridge.mm,
// bead oo-9ht.107): the engine sends these selectors to the wrapped object.
void TestEntityObject::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)  { _cxxEntity->getJSClass(outClass, outPrototype); }
std::optional<std::string> TestEntityObject::cxx_oo_jsClassName()  { return _cxxEntity->jsClassName(); }
bool TestEntityObject::isVisibleToScripts()  { return _cxxEntity->isVisibleToScripts(); }


Entity::~Entity()  {}
void Entity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)  { *outClass = nullptr; *outPrototype = nullptr; }
std::optional<std::string> Entity::jsClassName()  { return std::string("Entity"); }
bool Entity::isVisibleToScripts()  { return false; }


double WormholeEntity::arrivalTime()
{
	if (_arrivalTime == -1)  OORaiseException(OOInvalidArgumentException, "arrival %s", "boom");
	if (_arrivalTime == -2)  throw std::runtime_error("cxx boom");
	return _arrivalTime;
}

double WormholeEntity::expiryTime()  { return _expiryTime; }
OOSystemID WormholeEntity::getOrigin()  { return _origin; }
OOSystemID WormholeEntity::getDestination()  { return _destination; }


// The binding's category, as the C++ class's overrides answer it (bead oo-9ht.112; the
// WormholeEntity facade forwarded it from bead oo-9ht.43).
void WormholeEntity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)  { ::OOJSWormholeGetJSClass(outClass, outPrototype); }
std::optional<std::string> WormholeEntity::jsClassName()  { return ::OOJSWormholeJSClassName(); }
bool WormholeEntity::isVisibleToScripts()  { return ::OOJSWormholeIsVisibleToScripts(); }


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
std::map<ooscript::ClassDef *, ooscript::ClassDef *> sSuperclasses;
std::map<ooscript::ClassDef *, int> sConverters;
} // namespace

ooscript::Object gOOEntityJSPrototype = nullptr;


extern "C" {

ooscript::ClassDef *JSEntityClass(void)
{
	return &sFakeEntityClass;
}


void OOJSReportBadPropertySelector(ooscript::Context context, ooscript::Object, ooscript::PropertyId, ooscript::PropertySpec *)
{
	cxx_OOJSReportError(context, "bad property selector");
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
TestEntityObject *sWormhole = nullptr;				// the wormhole's object, which the JS object holds
WormholeEntity *sWormholePart = nullptr;	// its C++ part


// A JS object for an entity, as EntityJSValueInContext() makes it: the class and prototype the
// entity's category names, and a holder of its C++ part in the private slot (bead oo-9ht.39.3).
ooscript::Value JSValueForEntity(TestEntityObject *entity)
{
	ooscript::ClassDef *jsClass = nullptr;
	ooscript::Object prototype = nullptr;
	entity->getJSClass(&jsClass, &prototype);
	ooscript::Object object = ooscript::newObject(sContext, jsClass, prototype, nullptr);
	if (object == nullptr || !OOJSSetCxxPrivate(sContext, object, oo::makeRef<OOJSEntityHolder>(entity->_cxxEntity.get()).get()))  return ooscript::nullValue();
	return ooscript::objectValue(object);
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
	InitOOJSWormhole(sContext, sGlobal);

	sWormhole = oo::makeRef<TestEntityObject>().leakRef();	// kept for the life of the test
	sWormhole->_cxxEntity = oo::makeRef<WormholeEntity>();
	sWormholePart = static_cast<WormholeEntity *>(sWormhole->_cxxEntity.get());
	sWormholePart->_arrivalTime = 1000.5;
	sWormholePart->_expiryTime = 900.25;
	sWormholePart->_origin = 7;
	sWormholePart->_destination = 129;
	ooscript::Value wormhole = JSValueForEntity(sWormhole);
	ooscript::setProperty(sContext, sGlobal, "wormhole", &wormhole);
	ooscript::Value entity = ooscript::nullValue();
	ooscript::Object plain = ooscript::newObject(sContext, &sFakeEntityClass, gOOEntityJSPrototype, nullptr);
	TestEntityObject *plainEntity = oo::makeRef<TestEntityObject>().leakRef();	// kept for the life of the test
	plainEntity->_cxxEntity = oo::makeRef<Entity>();	// an entity that is not a wormhole
	if (plain != nullptr && OOJSSetCxxPrivate(sContext, plain, oo::makeRef<OOJSEntityHolder>(plainEntity->_cxxEntity.get()).get()))  entity = ooscript::objectValue(plain);
	ooscript::setProperty(sContext, sGlobal, "plainEntity", &entity);
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
	ooscript::ClassDef *wormholeClass = nullptr;
	ooscript::Object prototype = nullptr;
	sWormhole->getJSClass(&wormholeClass, &prototype);
	OO_CHECK(wormholeClass != nullptr && std::strcmp(wormholeClass->name, "Wormhole") == 0);
	OO_CHECK(prototype != nullptr);
	OO_CHECK(OOJSIsSubclass(wormholeClass, &sFakeEntityClass));
	OO_CHECK_EQ(sConverters[wormholeClass], 1);
	OO_CHECK(sWormhole->cxx_oo_jsClassName() == std::optional<std::string>("Wormhole"));
	OO_CHECK(sWormhole->isVisibleToScripts());
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
	// Read-only.
	OO_CHECK_EVAL("(function () { wormhole.origin = 3; return wormhole.origin; })()", "7");
	OO_CHECK_EVAL("(function () { 'use strict'; try { wormhole.origin = 3; return 'no throw'; } catch (e) { return e instanceof TypeError; } })()", "no throw");
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
	sWormholePart->_arrivalTime = -1;
	OO_CHECK_EVAL("wormhole.arrivalTime", "threw: Native exception: arrival boom");
	sWormholePart->_arrivalTime = -2;
	OO_CHECK_EVAL("wormhole.arrivalTime", "threw: Native exception: cxx boom");
	sWormholePart->_arrivalTime = 1000.5;
	OO_CHECK_EVAL("wormhole.arrivalTime", "1000.5");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
	OO_CHECK(ooscript::isInRequest(sContext));
}


OO_TEST_MAIN()
