/*	test_OOJSFlasher.mm
	Unit tests for the Flasher JS binding (src/Core/Scripting/OOJSFlasher.h/.mm) and its
	OOFlasherEntity category (whose forwarders were on the OOFlasherEntity facade from bead
	oo-9ht.49, and are the C++ class's overrides of the root's JS members since that facade's
	deletion, bead oo-9ht.107): bead oo-ub2g, converted the way bead oo-ppc converted OOJSVector
	(proposed ADR-0056 amendments oo-ppc and oo-ykoy).

	As test_OOJSWormhole.mm does (amendment oo-ykoy, item 4), it runs the JS class in a real
	context on the game's own façade backend (ooscript/JSEngine_quickjs.cpp), links the game's own
	objects for the binding, the engine's exception translator
	(OOJSEngineNativeWrappers.mm) and OOColor (a converted class, reached through its façade), and
	stands in for the entity classes (Entity answers only the selectors the binding sends; ShipEntity
	and, since bead oo-9ht.165, OOVisualEffectEntity are C++ parts with only the members it calls) and for the engine functions the binding links against, with the
	engine headers' linkage. Since bead oo-9ht.107 the flasher is the C++ OOFlasherEntity, which
	the binding finds through its object's C++ part: the stand-in is that C++ class, declared with
	the game header's names and signatures but not its class (OOFlasherEntity.h pulls in the game's
	classes), as test_OOJSGlobal.mm stands in for the engine, under a stand-in C++ root whose JS
	members the stand-in root category asks, as the game's does (amendment oo-9ht.107). The binding header is not imported, because until
	this bead it imported OOFlasherEntity.h; InitOOJSFlasher is declared here. The expectations
	were written against the Objective-C file and run on it first; they pin the JS-visible
	behaviour (the six properties and their ranges, the colour both ways, remove() from a ship and
	from a visual effect, a stale flasher, a native's exception) and what the category answers the
	engine. Run: bash tools/check-core-tests.sh
*/

#include "OOCocoa.h"
#include "OOColor.h"
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
	Entity *owner();	// the binding calls it since bead oo-9ht.39.8.20 (its object's -owner did); the C++ entity since bead oo-dpyk8
	bool getIsShip();	// what its object's -isShip forwarded to (bead oo-dpyk8)
};


// Global since bead oo-9ht.76 deleted its Objective-C facade, as the game's.
class OOLightParticleEntity : public Entity
{
public:
	float diameter();
	void setDiameter(float diameter);
	void setColor(OOColor *color);

	float _diameter = 0;
	oo::Ref<OOColor> _color;
};


/*	A flasher whose frequency is 99 raises from frequency(), one whose frequency is 98 throws a C++
	exception, so the test sees what an exception under a native becomes.
*/
class OOFlasherEntity : public OOLightParticleEntity
{
public:
	bool isActive();
	void setActive(bool active);
	oo::Ref<OOColor> color();
	float frequency();
	void setFrequency(float frequency);
	float phase();
	void setPhase(float phase);
	float fraction();
	void setFraction(float fraction);

	void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype) override;
	std::optional<std::string> jsClassName() override;
	bool isVisibleToScripts() override;

	bool _active = false;
	float _frequency = 0;
	float _fraction = 0;
	float _phase = 0;
};


// What an entity's JS object holds since bead oo-9ht.39.3: a weak reference to the C++ entity.
#include "OOJSEntityHolder.h"


// C++ since bead oo-4aq6a.11 (it was rooted on the Objective-C root class OOObject, which Phase 4
// deletes); its selectors and its category's are members of the same names.
class TestEntityObject final : public oo::RefCounted
{
public:
	bool isShip();
	void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype);
	std::optional<std::string> cxx_oo_jsClassName();
	bool isVisibleToScripts();
	const char *className() const  { return "Entity"; }	// its Objective-C class's runtime name

	oo::Ref<Entity> _cxxEntity;	// the flasher's C++ part (oo::ToCxx reads it)
	::TestEntityObject *_owner = nullptr;
	::TestEntityObject *_removed = nullptr;
	BOOL _isShip = NO;
};

// A ship: C++ since bead oo-9ht.144 deleted the Objective-C ship this stood in for, the C++ part of
// its object, with the one member the binding calls (declared as ShipEntity.h declares it).
class ShipEntity : public Entity
{
public:
	void removeFlasher(OOFlasherEntity *flasher);

	OOFlasherEntity *_removedFlasher = nullptr;
};

// A visual effect: C++ since bead oo-9ht.165 deleted the Objective-C effect this stood in for, the
// C++ part of its object, with the one member the binding calls (declared as OOVisualEffectEntity.h
// declares it).
typedef TestEntityObject OOVisualEffectSubEntity;	// as OOVisualEffectEntity.h names it (an object conforming to OOSubEntity until bead oo-4aq6a.11)

class OOVisualEffectEntity : public Entity
{
public:
	void removeSubEntity(OOVisualEffectSubEntity *sub);
	void removeSubEntity(Entity *sub);	// the binding's since bead oo-9ht.39.8.20

	::TestEntityObject *_removed = nullptr;
};

extern "C" void InitOOJSFlasher(ooscript::Context context, ooscript::Object global);
// The category's bodies, which the stand-in's overrides call as the C++ class's do (declared in OOJSFlasher.h).
void OOJSFlasherGetJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype);
std::optional<std::string> OOJSFlasherJSClassName(void);
bool OOJSFlasherIsVisibleToScripts(void);


#include "oo_test.hpp"

#include <cstdarg>
#include <cstdint>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>


bool TestEntityObject::isShip()  { return _isShip; }


void ShipEntity::removeFlasher(OOFlasherEntity *flasher)  { _removedFlasher = flasher; }


void OOVisualEffectEntity::removeSubEntity(OOVisualEffectSubEntity *sub)  { _removed = sub; }
::TestEntityObject *TestObjectOf(Entity *entity);	// defined below (oo::ToObjC until bead oo-4aq6a.11)
#define OO_ENTITY_HELPERS_STAND_IN_CXX
#include "EntityHelpersStandIn.h"	// EntityHelpers.mm's, on the test's objects (bead oo-dpyk8)
void OOVisualEffectEntity::removeSubEntity(Entity *sub)  { _removed = TestObjectOf(sub); }	// its object, as the binding passed it until bead oo-9ht.39.8.20


// The root's JS category, as the game's asks the C++ part (EntityOOJavaScriptExtensions+ObjCBridge.mm,
// bead oo-9ht.107): the engine sends these selectors to the wrapped object.
void TestEntityObject::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)  { _cxxEntity->getJSClass(outClass, outPrototype); }
std::optional<std::string> TestEntityObject::cxx_oo_jsClassName()  { return _cxxEntity->jsClassName(); }
bool TestEntityObject::isVisibleToScripts()  { return _cxxEntity->isVisibleToScripts(); }


Entity::~Entity()  {}
void Entity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)  { *outClass = nullptr; *outPrototype = nullptr; }
std::optional<std::string> Entity::jsClassName()  { return std::string("Entity"); }
bool Entity::isVisibleToScripts()  { return false; }

float OOLightParticleEntity::diameter()  { return _diameter; }
void OOLightParticleEntity::setDiameter(float diameter)  { _diameter = diameter; }
void OOLightParticleEntity::setColor(OOColor *color)  { _color = oo::Ref<OOColor>(color); }

bool OOFlasherEntity::isActive()  { return _active; }
void OOFlasherEntity::setActive(bool active)  { _active = active; }
oo::Ref<OOColor> OOFlasherEntity::color()  { return _color; }
void OOFlasherEntity::setFrequency(float frequency)  { _frequency = frequency; }
float OOFlasherEntity::fraction()  { return _fraction; }
void OOFlasherEntity::setFraction(float fraction)  { _fraction = fraction; }
float OOFlasherEntity::phase()  { return _phase; }
void OOFlasherEntity::setPhase(float phase)  { _phase = phase; }

float OOFlasherEntity::frequency()
{
	if (_frequency == 99)  OORaiseException(OOInvalidArgumentException, "frequency %s", "boom");
	if (_frequency == 98)  throw std::runtime_error("cxx boom");
	return _frequency;
}


// The binding's category, as the C++ class's overrides answer it (bead oo-9ht.107).
void OOFlasherEntity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)  { ::OOJSFlasherGetJSClass(outClass, outPrototype); }
std::optional<std::string> OOFlasherEntity::jsClassName()  { return ::OOJSFlasherJSClassName(); }
bool OOFlasherEntity::isVisibleToScripts()  { return ::OOJSFlasherIsVisibleToScripts(); }


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


// A property list as JavaScript, as far as the binding hands one over: null, a string, a number,
// or an array of those.
ooscript::Value OOJSValueFromPList(ooscript::Context context, const oo::PList &plist)
{
	if (const std::string *str = plist.getIf<std::string>())
	{
		ooscript::String js = ooscript::newStringCopyN(context, str->data(), str->size());
		return js != nullptr ? ooscript::stringValue(js) : ooscript::nullValue();
	}
	if (const double *number = plist.getIf<double>())  return ooscript::numberValue(*number);
	if (const oo::PList::Array *array = plist.getIf<oo::PList::Array>())
	{
		std::vector<ooscript::Value> values;
		for (const oo::PList &element : *array)  values.push_back(OOJSValueFromPList(context, element));
		ooscript::Object object = ooscript::newArrayObject(context, static_cast<unsigned>(values.size()), values.data());
		return object != nullptr ? ooscript::objectValue(object) : ooscript::nullValue();
	}
	return ooscript::nullValue();
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


// A JS value's plist form, as far as a colour description needs one: a string, a number, an array
// of those, or null.
oo::PList cxx_OOJSPListFromJSValue(ooscript::Context context, ooscript::Value value)
{
	double number = 0;
	if (ooscript::isString(value))  return oo::PList(cxx_OOStringFromJSValue(context, value).value_or(""));
	if (ooscript::isNumber(value) && ooscript::valueToNumber(context, value, &number))  return oo::PList(number);
	if (ooscript::isObject(value) && ooscript::isArrayObject(context, ooscript::toObject(value)))
	{
		std::uint32_t length = 0;
		ooscript::getArrayLength(context, ooscript::toObject(value), &length);
		oo::PList::Array array;
		for (std::uint32_t i = 0; i < length; i++)
		{
			ooscript::Value element;
			if (ooscript::getElement(context, ooscript::toObject(value), i, &element))  array.push_back(cxx_OOJSPListFromJSValue(context, element));
		}
		return oo::PList(std::move(array));
	}
	return oo::PList();
}


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
::TestEntityObject *TestObjectOf(Entity *entity)
{
	auto found = sObjects.find(entity);
	return found != sObjects.end() ? found->second : nullptr;
}

// The owner its object's -owner answered until bead oo-9ht.39.8.20, on the same object field.
Entity *Entity::owner()
{
	::TestEntityObject *object = TestObjectOf(this)->_owner;
	return object != nullptr ? object->_cxxEntity.get() : nullptr;	// its C++ part (bead oo-dpyk8)
}
bool Entity::getIsShip()  { ::TestEntityObject *object = TestObjectOf(this); return object != nullptr && object->isShip(); }	// (a message to nil answered NO)


// MARK: The context -------------------------------------------------------------------------------

namespace {

ooscript::Runtime sRuntime;
ooscript::Context sContext;
ooscript::Object sGlobal;
TestEntityObject *sFlasher = nullptr;					// the flasher's object
OOFlasherEntity *sFlasherPart = nullptr;	// its C++ part
TestEntityObject *sShip = nullptr;	// a ship's object and its C++ part (the Objective-C ship until bead oo-9ht.144)
ShipEntity *sShipPart = nullptr;
TestEntityObject *sEffect = nullptr;	// an effect's object and its C++ part (the Objective-C effect until bead oo-9ht.165)
OOVisualEffectEntity *sEffectPart = nullptr;


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
	InitOOJSFlasher(sContext, sGlobal);

	sShip = oo::makeRef<TestEntityObject>().leakRef();	// kept for the life of the test
	sShip->_cxxEntity = oo::makeRef<ShipEntity>();
	sShipPart = static_cast<ShipEntity *>(sShip->_cxxEntity.get());
	sShip->_isShip = YES;
	sEffect = oo::makeRef<TestEntityObject>().leakRef();
	sEffect->_cxxEntity = oo::makeRef<OOVisualEffectEntity>();
	sEffectPart = static_cast<OOVisualEffectEntity *>(sEffect->_cxxEntity.get());
	sFlasher = oo::makeRef<TestEntityObject>().leakRef();
	const oo::Ref<OOFlasherEntity> part = oo::makeRef<OOFlasherEntity>();
	sFlasher->_cxxEntity = part;
	sFlasherPart = part.get();
	sFlasherPart->_active = YES;
	sFlasherPart->_color = OOColor::colorWithRed(1, 0.5f, 0.25f, 1);
	sFlasherPart->_frequency = 2;
	sFlasherPart->_fraction = 0.5f;
	sFlasherPart->_phase = 0.25f;
	sFlasherPart->_diameter = 10;
	sFlasher->_owner = sShip;
	Define("flasher", JSValueForEntity(sFlasher));
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
	ooscript::ClassDef *flasherClass = nullptr;
	ooscript::Object prototype = nullptr;
	sFlasher->getJSClass(&flasherClass, &prototype);
	OO_CHECK(flasherClass != nullptr && std::strcmp(flasherClass->name, "Flasher") == 0);
	OO_CHECK(prototype != nullptr);
	OO_CHECK(OOJSIsSubclass(flasherClass, &sFakeEntityClass));
	OO_CHECK_EQ(sConverters[flasherClass], 1);
	OO_CHECK(sFlasher->cxx_oo_jsClassName() == std::optional<std::string>("Flasher"));
	OO_CHECK(sFlasher->isVisibleToScripts());
	OO_CHECK_EVAL("typeof Flasher", "function");
	OO_CHECK_EVAL("new Flasher()", "threw: unconstructable");
	OO_CHECK_EVAL("Object.getPrototypeOf(Flasher.prototype) === Entity.prototype", "true");
	OO_CHECK_EVAL("flasher instanceof Flasher", "true");
}


OO_TEST(properties)
{
	OO_CHECK_EVAL("flasher.active", "true");
	OO_CHECK_EVAL("flasher.color", "1,0.5,0.25,1");
	OO_CHECK_EVAL("flasher.frequency", "2");
	OO_CHECK_EVAL("flasher.fraction", "0.5");
	OO_CHECK_EVAL("flasher.phase", "0.25");
	OO_CHECK_EVAL("flasher.size", "10");
	OO_CHECK_EVAL("Object.keys(Flasher.prototype).join()", "active,color,fraction,frequency,phase,size");
}


OO_TEST(setters)
{
	OO_CHECK_EVAL("(function () { flasher.active = 0; return flasher.active; })()", "false");
	OO_CHECK_EVAL("(function () { flasher.active = 'yes'; return flasher.active; })()", "true");
	OO_CHECK_EVAL("(function () { flasher.frequency = 3.5; return flasher.frequency; })()", "3.5");
	OO_CHECK_EVAL("(function () { flasher.frequency = 0; return flasher.frequency; })()", "0");
	OO_CHECK_EVAL("(function () { flasher.frequency = -1; return flasher.frequency; })()", "threw: bad property value");
	OO_CHECK_EVAL("(function () { flasher.fraction = 1; return flasher.fraction; })()", "1");
	OO_CHECK_EVAL("(function () { flasher.fraction = 0; return flasher.fraction; })()", "threw: bad property value");
	OO_CHECK_EVAL("(function () { flasher.fraction = 1.5; return flasher.fraction; })()", "threw: bad property value");
	OO_CHECK_EVAL("(function () { flasher.phase = -0.75; return flasher.phase; })()", "-0.75");
	OO_CHECK_EVAL("(function () { flasher.size = 4; return flasher.size; })()", "4");
	OO_CHECK_EVAL("(function () { flasher.size = 0; return flasher.size; })()", "threw: bad property value");
	OO_CHECK_EVAL("(function () { flasher.size = 'abc'; return flasher.size; })()", "threw: bad property value");
	OO_CHECK(sFlasherPart->_frequency == 0 && sFlasherPart->_fraction == 1 && sFlasherPart->_phase == -0.75f && sFlasherPart->_diameter == 4);
}


OO_TEST(color)
{
	OO_CHECK_EVAL("(function () { flasher.color = [0, 1, 0]; return flasher.color; })()", "0,1,0,1");
	OO_CHECK_EVAL("(function () { flasher.color = 'redColor'; return flasher.color; })()", "1,0,0,1");
	OO_CHECK_EVAL("(function () { flasher.color = null; return flasher.color; })()", "null");
	OO_CHECK(sFlasherPart->_color == nullptr);
	OO_CHECK_EVAL("(function () { flasher.color = 'not a colour'; return flasher.color; })()", "threw: bad property value");
	OO_CHECK_EVAL("(function () { flasher.color = [0.25, 0.5, 0.75, 0.5]; return flasher.color; })()", "0.25,0.5,0.75,0.5");
	OO_CHECK(sFlasherPart->_color != nullptr && sFlasherPart->_color->alphaComponent() == 0.5f);
}


OO_TEST(remove)
{
	SetUpContext();
	sShipPart->_removedFlasher = nullptr;
	sFlasher->_owner = sShip;
	OO_CHECK_EVAL("flasher.remove()", "undefined");
	OO_CHECK(sShipPart->_removedFlasher == sFlasherPart);
	sFlasher->_owner = sEffect;
	OO_CHECK_EVAL("flasher.remove()", "undefined");
	OO_CHECK(sEffectPart->_removed == sFlasher);
	sFlasher->_owner = sShip;
	// The prototype has no entity: the binding's getter fails without reporting an error, which
	// ends the script uncatchably, and nothing is removed.
	sShipPart->_removedFlasher = nullptr;
	OO_CHECK_EVAL("Flasher.prototype.remove()", "<evaluation failed>");
	OO_CHECK(sShipPart->_removedFlasher == nullptr);
}


OO_TEST(otherObjects)
{
	// An entity that is not a flasher, and the prototype: the binding's getter fails without
	// reporting an error, which ends the script uncatchably.
	OO_CHECK_EVAL("Object.getOwnPropertyDescriptor(Flasher.prototype, 'size').get.call(ship)", "<evaluation failed>");
	OO_CHECK_EVAL("Flasher.prototype.size", "<evaluation failed>");
	// Something that is not an entity: the engine's getter reports it.
	OO_CHECK_EVAL("Object.getOwnPropertyDescriptor(Flasher.prototype, 'size').get.call({})", "threw: Native method expected Entity, got [object Object].");
	OO_CHECK_EVAL("flasher.active", "true");
}


OO_TEST(nativeExceptions)
{
	SetUpContext();
	// The property getter is a native (OOJS_NATIVE_ENTER): a raise from the entity is a JS error,
	// and so is a C++ exception.
	sFlasherPart->_frequency = 99;
	OO_CHECK_EVAL("flasher.frequency", "threw: Native exception: frequency boom");
	sFlasherPart->_frequency = 98;
	OO_CHECK_EVAL("flasher.frequency", "threw: Native exception: cxx boom");
	sFlasherPart->_frequency = 2;
	OO_CHECK_EVAL("flasher.frequency", "2");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
	OO_CHECK(ooscript::isInRequest(sContext));
}


OO_TEST_MAIN()
