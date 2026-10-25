/*	test_OOJSExhaustPlume.mm
	Unit tests for the ExhaustPlume JS binding (src/Core/Scripting/OOJSExhaustPlume.h/.mm) and its
	OOExhaustPlumeEntity category (whose forwarders were on the OOExhaustPlumeEntity facade from
	bead oo-9ht.48, and are the C++ class's overrides of the root's JS members since that facade's
	deletion, bead oo-9ht.110): bead oo-utlm,
	converted the way bead oo-ppc converted OOJSVector (proposed ADR-0056 amendments oo-ppc and
	oo-ykoy).

	As test_OOJSWormhole.mm does (amendment oo-ykoy, item 4), it runs the JS class in a real
	context on the game's own façade backend (ooscript/JSEngine_quickjs.cpp), links the game's own
	objects for the binding and the engine's exception translator
	(OOJSEngineNativeWrappers.mm), and stands in for the entity classes (Entity and ShipEntity
	answer only the selectors the binding sends), for the Vector3D conversions (a vector is the
	array [x, y, z] here) and for the engine functions the binding links against, with the engine
	headers' linkage. Since bead oo-9ht.110 the plume is the C++ OOExhaustPlumeEntity, which the
	binding finds through its object's C++ part: the stand-in is that C++ class, declared with the
	game header's names and signatures but not its class (OOExhaustPlumeEntity.h pulls in the
	game's classes), as test_OOJSGlobal.mm stands in for the engine, under a stand-in C++ root
	whose JS members the stand-in root category asks, as the game's does (amendment oo-9ht.107). The binding header is not imported, because until this bead
	it imported OOExhaustPlumeEntity.h; InitOOJSExhaustPlume is declared here. The expectations
	were written against the Objective-C file and run on it first; they pin the JS-visible
	behaviour (size, remove(), a stale plume, a non-plume, a native's exception) and what the
	category answers the engine. Run: bash tools/check-core-tests.sh
*/

#include "OOCocoa.h"
#include "OOMaths.h"
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
	Entity *owner();	// the binding calls it since bead oo-9ht.39.8.19 (its object's -owner did); the C++ entity since bead oo-dpyk8
};


/*	A plume whose scale has x = -1 raises from scale(), one with x = -2 throws a C++ exception, so the
	test sees what an exception under a native becomes.
*/
class OOExhaustPlumeEntity : public Entity
{
public:
	Vector scale();
	void setScale(Vector scale);

	void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype) override;
	std::optional<std::string> jsClassName() override;
	bool isVisibleToScripts() override;

	Vector _scale = {};
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

	oo::Ref<Entity> _cxxEntity;	// the plume's C++ part (oo::ToCxx reads it)
	::TestEntityObject *_owner = nullptr;
};

// A ship: C++ since bead oo-9ht.144 deleted the Objective-C ship this stood in for, the C++ part of
// its object, with the one member the binding calls (declared as ShipEntity.h declares it).
class ShipEntity : public Entity
{
public:
	void removeExhaust(OOExhaustPlumeEntity *exhaust);

	OOExhaustPlumeEntity *_removed = nullptr;
};

extern "C" void InitOOJSExhaustPlume(ooscript::Context context, ooscript::Object global);
// The category's bodies, which the stand-in's overrides call as the C++ class's do (declared in OOJSExhaustPlume.h).
void OOJSExhaustPlumeGetJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype);
std::optional<std::string> OOJSExhaustPlumeJSClassName(void);
bool OOJSExhaustPlumeIsVisibleToScripts(void);

#include "oo_test.hpp"

#include <cstdarg>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>


void ShipEntity::removeExhaust(OOExhaustPlumeEntity *exhaust)  { _removed = exhaust; }


// The root's JS category, as the game's asks the C++ part (EntityOOJavaScriptExtensions+ObjCBridge.mm,
// bead oo-9ht.107): the engine sends these selectors to the wrapped object.
void TestEntityObject::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)  { _cxxEntity->getJSClass(outClass, outPrototype); }
std::optional<std::string> TestEntityObject::cxx_oo_jsClassName()  { return _cxxEntity->jsClassName(); }
bool TestEntityObject::isVisibleToScripts()  { return _cxxEntity->isVisibleToScripts(); }


Entity::~Entity()  {}
void Entity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)  { *outClass = nullptr; *outPrototype = nullptr; }
std::optional<std::string> Entity::jsClassName()  { return std::string("Entity"); }
bool Entity::isVisibleToScripts()  { return false; }

Vector OOExhaustPlumeEntity::scale()
{
	if (_scale.x == -1)  OORaiseException(OOInvalidArgumentException, "scale %s", "boom");
	if (_scale.x == -2)  throw std::runtime_error("cxx boom");
	return _scale;
}

void OOExhaustPlumeEntity::setScale(Vector scale)  { _scale = scale; }


// The binding's category, as the C++ class's overrides answer it (bead oo-9ht.110).
void OOExhaustPlumeEntity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)  { ::OOJSExhaustPlumeGetJSClass(outClass, outPrototype); }
std::optional<std::string> OOExhaustPlumeEntity::jsClassName()  { return ::OOJSExhaustPlumeJSClassName(); }
bool OOExhaustPlumeEntity::isVisibleToScripts()  { return ::OOJSExhaustPlumeIsVisibleToScripts(); }


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
Entity *gOOJSPlayerIfStale = nullptr;	// the player's C++ entity (bead oo-9ht.39.25)


extern "C" {

ooscript::ClassDef *JSEntityClass(void)
{
	return &sFakeEntityClass;
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



// A vector is the array [x, y, z] here: enough to see what the binding hands over and takes.
bool VectorToJSValue(ooscript::Context context, Vector vector, ooscript::Value *outValue)
{
	ooscript::Value parts[3] = { ooscript::numberValue(vector.x), ooscript::numberValue(vector.y), ooscript::numberValue(vector.z) };
	ooscript::Object array = ooscript::newArrayObject(context, 3, parts);
	if (array == nullptr)  return false;
	*outValue = ooscript::objectValue(array);
	return true;
}


bool JSValueToVector(ooscript::Context context, ooscript::Value value, Vector *outVector)
{
	double v[3] = {};
	ooscript::Value element;
	if (!ooscript::isObject(value) || !ooscript::isArrayObject(context, ooscript::toObject(value)))  return false;
	for (int i = 0; i < 3; i++)
	{
		if (!ooscript::getElement(context, ooscript::toObject(value), i, &element) || !ooscript::valueToNumber(context, element, &v[i]))  return false;
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

}	// extern "C"


oo::PList OOJSEntityObjectConverter(ooscript::Context, ooscript::Object)
{
	return oo::PList();
}


// The holder's glue is OOJSEntity.mm's, which the test does not link; the binding never asks it.
ooscript::Value OOJSEntityHolder::jsValueInContext(ooscript::Context)  { return ooscript::undefinedValue(); }
void OOJSEntityHolder::clearJSSelf(ooscript::Object)  {}
std::optional<std::string> OOJSEntityHolder::jsDescription()  { return std::nullopt; }


// oo::ToObjC (Entity+ObjCBridge.mm): the object of each C++ part the test wrapped, nil for any
// other (the binding asks it where its natives still message the object, bead oo-9ht.39.3).
namespace {
std::map<Entity *, TestEntityObject *> sObjects;
}
::TestEntityObject *TestObjectOf(Entity *entity);	// oo::ToObjC until bead oo-4aq6a.11
::TestEntityObject *TestObjectOf(Entity *entity)
{
	auto found = sObjects.find(entity);
	return found != sObjects.end() ? found->second : nullptr;
}

// The owner its object's -owner answered until bead oo-9ht.39.8.19, on the same object field.
Entity *Entity::owner()
{
	::TestEntityObject *object = TestObjectOf(this)->_owner;
	return object != nullptr ? object->_cxxEntity.get() : nullptr;	// its C++ part (bead oo-dpyk8)
}


// MARK: The context -------------------------------------------------------------------------------

namespace {

ooscript::Runtime sRuntime;
ooscript::Context sContext;
ooscript::Object sGlobal;
TestEntityObject *sPlume = nullptr;						// the plume's object
OOExhaustPlumeEntity *sPlumePart = nullptr;	// its C++ part
TestEntityObject *sShip = nullptr;	// a ship's object and its C++ part (the Objective-C ship until bead oo-9ht.144)
ShipEntity *sShipPart = nullptr;


ooscript::Value JSValueForObject(ooscript::ClassDef *jsClass, ooscript::Object prototype, TestEntityObject *entity)
{
	ooscript::Object object = ooscript::newObject(sContext, jsClass, prototype, nullptr);
	if (entity->_cxxEntity == nullptr)  entity->_cxxEntity = oo::makeRef<Entity>();	// a plain entity's C++ part
	if (object == nullptr || !OOJSSetCxxPrivate(sContext, object, oo::makeRef<OOJSEntityHolder>(entity->_cxxEntity.get()).get()))  return ooscript::nullValue();	// the slot holds the C++ entity (bead oo-9ht.39.3)
	sObjects[entity->_cxxEntity.get()] = entity;
	return ooscript::objectValue(object);
}


// A JS object for an entity, as -[TestEntityObject oo_jsValueInContext:] makes it: the class and prototype
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
	InitOOJSExhaustPlume(sContext, sGlobal);

	sShip = oo::makeRef<TestEntityObject>().leakRef();	// kept for the life of the test
	sShip->_cxxEntity = oo::makeRef<ShipEntity>();
	sShipPart = static_cast<ShipEntity *>(sShip->_cxxEntity.get());
	sPlume = oo::makeRef<TestEntityObject>().leakRef();
	const oo::Ref<OOExhaustPlumeEntity> part = oo::makeRef<OOExhaustPlumeEntity>();
	sPlume->_cxxEntity = part;
	sPlumePart = part.get();
	sPlumePart->_scale = make_vector(1, 2, 3.5);
	sPlume->_owner = sShip;
	Define("plume", JSValueForEntity(sPlume));
	Define("ship", JSValueForObject(&sFakeEntityClass, gOOEntityJSPrototype, sShip));
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
	ooscript::ClassDef *plumeClass = nullptr;
	ooscript::Object prototype = nullptr;
	sPlume->getJSClass(&plumeClass, &prototype);
	OO_CHECK(plumeClass != nullptr && std::strcmp(plumeClass->name, "ExhaustPlume") == 0);
	OO_CHECK(prototype != nullptr);
	OO_CHECK(OOJSIsSubclass(plumeClass, &sFakeEntityClass));
	OO_CHECK_EQ(sConverters[plumeClass], 1);
	OO_CHECK(sPlume->cxx_oo_jsClassName() == std::optional<std::string>("ExhaustPlume"));
	OO_CHECK(sPlume->isVisibleToScripts());
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
	OO_CHECK(sPlumePart->_scale.x == 4 && sPlumePart->_scale.y == 5 && sPlumePart->_scale.z == 6);
	OO_CHECK_EVAL("(function () { plume.size = 'big'; return plume.size; })()", "threw: bad property value");
	OO_CHECK_EVAL("plume.size", "4,5,6");
}


OO_TEST(remove)
{
	SetUpContext();
	sShipPart->_removed = nullptr;
	OO_CHECK_EVAL("plume.remove()", "undefined");
	OO_CHECK(sShipPart->_removed == sPlumePart);
	// The prototype has no entity: the binding's getter fails without reporting an error, which
	// ends the script uncatchably, and nothing is removed.
	sShipPart->_removed = nullptr;
	OO_CHECK_EVAL("ExhaustPlume.prototype.remove()", "<evaluation failed>");
	OO_CHECK(sShipPart->_removed == nullptr);
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
	sPlumePart->_scale = make_vector(-1, 0, 0);
	OO_CHECK_EVAL("plume.size", "threw: Native exception: scale boom");
	sPlumePart->_scale = make_vector(-2, 0, 0);
	OO_CHECK_EVAL("plume.size", "threw: Native exception: cxx boom");
	sPlumePart->_scale = make_vector(1, 1, 1);
	OO_CHECK_EVAL("plume.size", "1,1,1");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
	OO_CHECK(ooscript::isInRequest(sContext));
}


OO_TEST_MAIN()
