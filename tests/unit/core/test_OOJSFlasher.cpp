/*	test_OOJSFlasher.mm
	Unit tests for the Flasher JS binding (src/Core/Scripting/OOJSFlasher.h/.mm) and its
	OOFlasherEntity category (the C++ class's overrides of the root's JS members).

	As test_OOJSWormhole.mm does, it runs the JS class in a real QuickJS-ng context, links the
	game's own objects for the binding, the engine's class registration (OOJSClasses.mm), the
	engine's exception translator (OOJSEngineNativeWrappers.mm) and OOColor (a converted class,
	reached through its façade), and stands in for the entity classes (Entity answers only the
	selectors the binding sends; ShipEntity and OOVisualEffectEntity are C++ parts with only the
	members it calls) and for the engine functions the binding links against, with the engine
	headers' linkage. The flasher is the C++ OOFlasherEntity, which the binding finds through its
	object's C++ part: the stand-in is that C++ class, declared with the game header's names and
	signatures but not its class (OOFlasherEntity.h pulls in the game's classes), as
	test_OOJSGlobal.mm stands in for the engine, under a stand-in C++ root whose JS members the
	stand-in root category asks, as the game's does. The binding header is not imported;
	InitOOJSFlasher is declared here. The tests pin the JS-visible behaviour (the six properties and their ranges,
	the colour both ways, remove() from a ship and from a visual effect, a stale flasher, a
	native's exception) and what the category answers the engine.
	Run: tests/run.sh unit
*/

#include "OOFoundation.h"
#include "OOColor.h"
#include <quickjs.h>
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#include "EntityManualRefs.h"  // the tests' manual references (T097)


// MARK: The entity classes, as far as the binding sees them ---------------------------------------

// The C++ root, as far as the binding and the root's JS category reach it.
class Entity : public oo::Object
{
public:
	virtual ~Entity();
	virtual JSClassID jsClassID();
	virtual std::optional<std::string> jsClassName();
	virtual bool isVisibleToScripts();
	Entity *owner();	// the binding calls it (its object's -owner did)
	bool getIsShip();	// what its object's -isShip forwarded to
};


// Global, as the game's.
class OOLightParticleEntity : public Entity
{
public:
	float diameter();
	void setDiameter(float diameter);
	void setColor(OOColor *color);

	float _diameter = 0;
	std::shared_ptr<OOColor> _color;
};


/*	A flasher whose frequency is 99 raises from frequency(), one whose frequency is 98 throws a C++
	exception, so the test sees what an exception under a native becomes.
*/
class OOFlasherEntity : public OOLightParticleEntity
{
public:
	bool isActive();
	void setActive(bool active);
	std::shared_ptr<OOColor> color();
	float frequency();
	void setFrequency(float frequency);
	float phase();
	void setPhase(float phase);
	float fraction();
	void setFraction(float fraction);

	JSClassID jsClassID() override;
	std::optional<std::string> jsClassName() override;
	bool isVisibleToScripts() override;

	bool _active = false;
	float _frequency = 0;
	float _fraction = 0;
	float _phase = 0;
};


// What an entity's JS object holds: a weak reference to the C++ entity.
#include "OOJSEntityHolder.h"


// Its selectors and its category's are members of the same names.
class TestEntityObject final : public oo::Object
{
public:
	bool isShip();
	JSClassID oo_jsClassID();
	std::optional<std::string> oo_jsClassName();
	bool isVisibleToScripts();
	const char *className() const  { return "Entity"; }	// its Objective-C class's runtime name

	std::shared_ptr<Entity> _cxxEntity;	// the flasher's C++ part (oo::ToCxx reads it)
	::TestEntityObject *_owner = nullptr;
	::TestEntityObject *_removed = nullptr;
	bool _isShip = false;
};

// A ship: the C++ part of its object, with the one member the binding calls
// (declared as ShipEntity.h declares it).
class ShipEntity : public Entity
{
public:
	void removeFlasher(OOFlasherEntity *flasher);

	OOFlasherEntity *_removedFlasher = nullptr;
};

// A visual effect: the C++ part of its object, with the one member the
// binding calls (declared as OOVisualEffectEntity.h declares it).
typedef TestEntityObject OOVisualEffectSubEntity;	// as OOVisualEffectEntity.h names it

class OOVisualEffectEntity : public Entity
{
public:
	void removeSubEntity(OOVisualEffectSubEntity *sub);
	void removeSubEntity(Entity *sub);	// the binding's

	::TestEntityObject *_removed = nullptr;
};

void InitOOJSFlasher(JSContext* context, JSValueConst global);
// The category's bodies, which the stand-in's overrides call as the C++ class's do (declared in OOJSFlasher.h).
JSClassID JSFlasherClassID(void);
std::optional<std::string> OOJSFlasherJSClassName(void);
bool OOJSFlasherIsVisibleToScripts(void);
#include "OOJSEngineCore.h"


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
::TestEntityObject *TestObjectOf(Entity *entity);	// defined below
#define OO_ENTITY_HELPERS_STAND_IN_CXX
#include "EntityHelpersStandIn.h"	// EntityHelpers.mm's, on the test's objects
void OOVisualEffectEntity::removeSubEntity(Entity *sub)  { _removed = TestObjectOf(sub); }	// its object, as the binding passed it

// The root's JS category, as the game's asks the C++ part: the engine sends these
// selectors to the wrapped object.
JSClassID TestEntityObject::oo_jsClassID()  { return _cxxEntity->jsClassID(); }
std::optional<std::string> TestEntityObject::oo_jsClassName()  { return _cxxEntity->jsClassName(); }
bool TestEntityObject::isVisibleToScripts()  { return _cxxEntity->isVisibleToScripts(); }


Entity::~Entity()  {}
JSClassID Entity::jsClassID()  { return 0; }
std::optional<std::string> Entity::jsClassName()  { return std::string("Entity"); }
bool Entity::isVisibleToScripts()  { return false; }

float OOLightParticleEntity::diameter()  { return _diameter; }
void OOLightParticleEntity::setDiameter(float diameter)  { _diameter = diameter; }
void OOLightParticleEntity::setColor(OOColor *color)  { _color = oo::share(color); }

bool OOFlasherEntity::isActive()  { return _active; }
void OOFlasherEntity::setActive(bool active)  { _active = active; }
std::shared_ptr<OOColor> OOFlasherEntity::color()  { return _color; }
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


// The binding's category, as the C++ class's overrides answer it.
JSClassID OOFlasherEntity::jsClassID()  { return ::JSFlasherClassID(); }
std::optional<std::string> OOFlasherEntity::jsClassName()  { return ::OOJSFlasherJSClassName(); }
bool OOFlasherEntity::isVisibleToScripts()  { return ::OOJSFlasherIsVisibleToScripts(); }


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


// What the class registration (OOJSClasses.mm) asks of the engine.
void OOJSReportPendingException(JSContext *context)
{
	JS_FreeValue(context, JS_GetException(context));
}


JSAtom OOJSIDFromString(const std::string &string)
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


// A property list as JavaScript, as far as the binding hands one over: null, a string, a number,
// or an array of those.
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
JSClassID sFakeEntityClassID = 0;
JSClassDef sFakeEntityClass = { .class_name = "Entity" };
std::map<JSClassID, int> sConverters;
} // namespace

Entity *gOOJSPlayerIfStale = nullptr;	// the player's C++ entity


JSClassID JSEntityClassID(void)
{
	return sFakeEntityClassID;
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


// The engine's object getter is OOJSPrivateObject.cpp's (linked): the JS class must be a subclass
// of the required one, and the slot holds the entity's holder.

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


// A JS value's plist form, as far as a colour description needs one: a string, a number, an array
// of those, or null.
oo::PList OOJSPListFromJSValue(JSContext *context, JSValueConst value)
{
	double number = 0;
	if (JS_IsString(value))  return oo::PList(OOStringFromJSValue(context, value).value_or(""));
	if (JS_IsNumber(value) && JS_ToFloat64(context, &number, value) == 0)  return oo::PList(number);
	if (JS_IsArray(value))
	{
		std::int64_t length = 0;
		JS_GetLength(context, value, &length);
		oo::PList::Array array;
		for (std::int64_t i = 0; i < length; i++)
		{
			JSValue element = JS_GetPropertyUint32(context, value, static_cast<std::uint32_t>(i));
			if (!JS_IsException(element))  array.push_back(OOJSPListFromJSValue(context, element));
			JS_FreeValue(context, element);
		}
		return oo::PList(std::move(array));
	}
	return oo::PList();
}


// The holder's glue is OOJSEntity.mm's, which the test does not link; the binding never asks it.
JSValue OOJSEntityHolder::jsValueInContext(JSContext *)  { return JS_UNDEFINED; }
void OOJSEntityHolder::clearJSSelf(JSValueConst)  {}
std::optional<std::string> OOJSEntityHolder::jsDescription()  { return std::nullopt; }


// oo::ToObjC: the object of each C++ part the test wrapped, nil for any
// other (the binding asks it where its natives still message the object).
namespace {
std::map<Entity *, TestEntityObject *> sObjects;
}
::TestEntityObject *TestObjectOf(Entity *entity)
{
	auto found = sObjects.find(entity);
	return found != sObjects.end() ? found->second : nullptr;
}

// The owner its object's -owner answered, on the same object field.
Entity *Entity::owner()
{
	::TestEntityObject *object = TestObjectOf(this)->_owner;
	return object != nullptr ? object->_cxxEntity.get() : nullptr;	// its C++ part
}
bool Entity::getIsShip()  { ::TestEntityObject *object = TestObjectOf(this); return object != nullptr && object->isShip(); }	// (a message to nil answered NO)


// MARK: The context -------------------------------------------------------------------------------

namespace {

JSRuntime *sRuntime = nullptr;
JSContext *sContext = nullptr;
JSValue sGlobal = JS_UNDEFINED;	// held for the life of the test
TestEntityObject *sFlasher = nullptr;					// the flasher's object
OOFlasherEntity *sFlasherPart = nullptr;	// its C++ part
TestEntityObject *sShip = nullptr;	// a ship's object and its C++ part
ShipEntity *sShipPart = nullptr;
TestEntityObject *sEffect = nullptr;	// an effect's object and its C++ part
OOVisualEffectEntity *sEffectPart = nullptr;


// A JS object of the class, with the class's prototype and a holder of the entity's C++ part in
// the private slot; owned by the caller.
JSValue JSValueForObject(JSClassID jsClass, TestEntityObject *entity)
{
	JSValue object = JS_NewObjectClass(sContext, static_cast<int>(jsClass));
	if (entity->_cxxEntity == nullptr)  entity->_cxxEntity = oo::makeShared<Entity>();	// a plain entity's C++ part
	if (JS_IsException(object) || !OOJSSetCxxPrivate(object, oo::makeShared<OOJSEntityHolder>(entity->_cxxEntity.get())))	// the slot holds the C++ entity
	{
		JS_FreeValue(sContext, object);
		return JS_NULL;
	}
	sObjects[entity->_cxxEntity.get()] = entity;
	return object;
}


// A JS object for an entity, as EntityJSValueInContext() makes it: the class the entity's
// category names, and a holder of the entity in the private slot.
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
	InitOOJSFlasher(sContext, sGlobal);

	sShip = oo::test::NewRetained<TestEntityObject>();	// kept for the life of the test
	sShip->_cxxEntity = oo::makeShared<ShipEntity>();
	sShipPart = static_cast<ShipEntity *>(sShip->_cxxEntity.get());
	sShip->_isShip = true;
	sEffect = oo::test::NewRetained<TestEntityObject>();
	sEffect->_cxxEntity = oo::makeShared<OOVisualEffectEntity>();
	sEffectPart = static_cast<OOVisualEffectEntity *>(sEffect->_cxxEntity.get());
	sFlasher = oo::test::NewRetained<TestEntityObject>();
	const std::shared_ptr<OOFlasherEntity> part = oo::makeShared<OOFlasherEntity>();
	sFlasher->_cxxEntity = part;
	sFlasherPart = part.get();
	sFlasherPart->_active = true;
	sFlasherPart->_color = OOColor::colorWithRed(1, 0.5f, 0.25f, 1);
	sFlasherPart->_frequency = 2;
	sFlasherPart->_fraction = 0.5f;
	sFlasherPart->_phase = 0.25f;
	sFlasherPart->_diameter = 10;
	sFlasher->_owner = sShip;
	Define("flasher", JSValueForEntity(sFlasher));
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
	JSClassID flasherClass = sFlasher->oo_jsClassID();
	OO_CHECK(flasherClass != 0 && OOJSClassName(flasherClass) != nullptr && std::strcmp(OOJSClassName(flasherClass), "Flasher") == 0);
	JSValue prototype = JS_GetClassProto(sContext, flasherClass);
	OO_CHECK(JS_IsObject(prototype));
	JS_FreeValue(sContext, prototype);
	OO_CHECK(OOJSIsSubclass(flasherClass, sFakeEntityClassID));
	OO_CHECK_EQ(sConverters[flasherClass], 1);
	OO_CHECK(sFlasher->oo_jsClassName() == std::optional<std::string>("Flasher"));
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
}


OO_TEST_MAIN()
