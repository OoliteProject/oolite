/*	test_OOJSFlasher.mm
	Unit tests for the Flasher JS binding (src/Core/Scripting/OOJSFlasher.h/.mm) and its
	OOFlasherEntity category (whose forwarders were on the OOFlasherEntity facade from bead
	oo-9ht.49, and are the C++ class's overrides of the root's JS members since that facade's
	deletion): bead oo-ub2g, converted the way bead oo-ppc converted OOJSVector
	(proposed ADR-0056 amendments oo-ppc and oo-ykoy).

	As test_OOJSWormhole.mm does (amendment oo-ykoy, item 4), it runs the JS class in a real
	QuickJS-ng context, links the game's own objects for the binding, the engine's
	class registration (OOJSClasses.mm), the engine's exception translator
	(OOJSEngineNativeWrappers.mm) and OOColor (a converted class, reached through its façade), and
	stands in for the entity classes (Entity, ShipEntity and OOVisualEffectEntity answer only the
	selectors the binding sends) and for the engine functions the binding links against, with the
	engine headers' linkage. The flasher is the C++ OOFlasherEntity, which the binding finds
	through its object's C++ part: the stand-in is that C++ class, declared with the game header's
	names and signatures but not its class (OOFlasherEntity.h pulls in the game's classes), as
	test_OOJSGlobal.mm stands in for the engine, under a stand-in C++ root whose JS members the
	stand-in root category asks, as the game's does. The binding header is not imported, because
	until this bead it imported OOFlasherEntity.h; InitOOJSFlasher is declared here. The expectations
	were written against the Objective-C file and run on it first; they pin the JS-visible
	behaviour (the six properties and their ranges, the colour both ways, remove() from a ship and
	from a visual effect, a stale flasher, a native's exception) and what the category answers the
	engine. Run: tests/run.sh unit
*/

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"
#include <objc/runtime.h>
#import "OOColor.h"
#include <quickjs.h>
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"


// MARK: The entity classes, as far as the binding sees them ---------------------------------------

namespace cxx {

// The C++ root, as far as the binding and the root's JS category reach it.
class Entity : public oo::RefCounted
{
public:
	virtual ~Entity();
	virtual JSClassID jsClassID();
	virtual std::optional<std::string> jsClassName();
	virtual bool isVisibleToScripts();
};

class OOLightParticleEntity : public Entity
{
public:
	float diameter();
	void setDiameter(float diameter);
	void setColor(OOColor *color);

	float _diameter = 0;
	oo::Ref<OOColor> _color;
};

}	// namespace cxx


/*	A flasher whose frequency is 99 raises from frequency(), one whose frequency is 98 throws a C++
	exception, so the test sees what an exception under a native becomes.
*/
class OOFlasherEntity : public cxx::OOLightParticleEntity
{
public:
	bool isActive();
	void setActive(bool active);
	oo::Ref<cxx::OOColor> color();
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


@interface Entity: OOObject
{
@public
	oo::Ref<cxx::Entity> _cxxEntity;	// the flasher's C++ part (oo::ToCxx reads it)
	id _owner;
	id _removed;
	OOFlasherEntity *_removedFlasher;
}
- (id) weakRefUnderlyingObject;
- (id) owner;
- (BOOL) isShip;
@end

@interface ShipEntity: Entity
- (void) removeFlasher:(OOFlasherEntity *)flasher;
@end

@interface OOVisualEffectEntity: Entity
- (void) removeSubEntity:(Entity *)sub;
@end

@interface Entity (OOJavaScriptExtensions)
- (JSClassID) oo_jsClassID;
- (std::optional<std::string>) cxx_oo_jsClassName;
- (BOOL) isVisibleToScripts;
@end

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


@implementation Entity

- (id) weakRefUnderlyingObject  { return self; }
- (id) owner  { return _owner; }
- (BOOL) isShip  { return NO; }

@end


@implementation ShipEntity

- (BOOL) isShip  { return YES; }
- (void) removeFlasher:(OOFlasherEntity *)flasher  { _removedFlasher = flasher; }

@end


@implementation OOVisualEffectEntity

- (void) removeSubEntity:(Entity *)sub  { _removed = sub; }

@end


// The root's JS category, as the game's asks the C++ part (EntityOOJavaScriptExtensions+ObjCBridge.mm):
// the engine sends these selectors to the wrapped object.
@implementation Entity (OOJavaScriptExtensions)

- (JSClassID) oo_jsClassID  { return _cxxEntity->jsClassID(); }
- (std::optional<std::string>) cxx_oo_jsClassName  { return _cxxEntity->jsClassName(); }
- (BOOL) isVisibleToScripts  { return _cxxEntity->isVisibleToScripts(); }

@end


cxx::Entity::~Entity()  {}
JSClassID cxx::Entity::jsClassID()  { return 0; }
std::optional<std::string> cxx::Entity::jsClassName()  { return std::string("Entity"); }
bool cxx::Entity::isVisibleToScripts()  { return false; }

float cxx::OOLightParticleEntity::diameter()  { return _diameter; }
void cxx::OOLightParticleEntity::setDiameter(float diameter)  { _diameter = diameter; }
void cxx::OOLightParticleEntity::setColor(OOColor *color)  { _color = oo::Ref<OOColor>(color); }

bool OOFlasherEntity::isActive()  { return _active; }
void OOFlasherEntity::setActive(bool active)  { _active = active; }
oo::Ref<cxx::OOColor> OOFlasherEntity::color()  { return _color; }
void OOFlasherEntity::setFrequency(float frequency)  { _frequency = frequency; }
float OOFlasherEntity::fraction()  { return _fraction; }
void OOFlasherEntity::setFraction(float fraction)  { _fraction = fraction; }
float OOFlasherEntity::phase()  { return _phase; }
void OOFlasherEntity::setPhase(float phase)  { _phase = phase; }

float OOFlasherEntity::frequency()
{
	if (_frequency == 99)  [OOException raise:OOInvalidArgumentException format:"frequency %s", "boom"];
	if (_frequency == 98)  throw std::runtime_error("cxx boom");
	return _frequency;
}


// The binding's category, as the C++ class's overrides answer it.
JSClassID OOFlasherEntity::jsClassID()  { return ::JSFlasherClassID(); }
std::optional<std::string> OOFlasherEntity::jsClassName()  { return ::OOJSFlasherJSClassName(); }
bool OOFlasherEntity::isVisibleToScripts()  { return ::OOJSFlasherIsVisibleToScripts(); }


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


// A JS value's plist form, as far as a colour description needs one: a string, a number, an array
// of those, or null.
oo::PList cxx_OOJSPListFromJSValue(JSContext *context, JSValueConst value)
{
	double number = 0;
	if (JS_IsString(value))  return oo::PList(cxx_OOStringFromJSValue(context, value).value_or(""));
	if (JS_IsNumber(value) && JS_ToFloat64(context, &number, value) == 0)  return oo::PList(number);
	if (JS_IsArray(value))
	{
		std::int64_t length = 0;
		JS_GetLength(context, value, &length);
		oo::PList::Array array;
		for (std::int64_t i = 0; i < length; i++)
		{
			JSValue element = JS_GetPropertyUint32(context, value, static_cast<std::uint32_t>(i));
			if (!JS_IsException(element))  array.push_back(cxx_OOJSPListFromJSValue(context, element));
			JS_FreeValue(context, element);
		}
		return oo::PList(std::move(array));
	}
	return oo::PList();
}


// MARK: The context -------------------------------------------------------------------------------

namespace {

JSRuntime *sRuntime = nullptr;
JSContext *sContext = nullptr;
JSValue sGlobal = JS_UNDEFINED;	// held for the life of the test
Entity *sFlasher = nil;					// the flasher's object
OOFlasherEntity *sFlasherPart = nullptr;	// its C++ part
ShipEntity *sShip = nil;
OOVisualEffectEntity *sEffect = nil;


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
	InitOOJSFlasher(sContext, sGlobal);

	sShip = [[ShipEntity alloc] init];	// kept for the life of the test
	sEffect = [[OOVisualEffectEntity alloc] init];
	sFlasher = [[Entity alloc] init];
	const oo::Ref<OOFlasherEntity> part = oo::makeRef<OOFlasherEntity>();
	sFlasher->_cxxEntity = part;
	sFlasherPart = part.get();
	sFlasherPart->_active = YES;
	sFlasherPart->_color = cxx::OOColor::colorWithRed(1, 0.5f, 0.25f, 1);
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
	JSClassID flasherClass = [sFlasher oo_jsClassID];
	OO_CHECK(flasherClass != 0 && OOJSClassName(flasherClass) != nullptr && std::strcmp(OOJSClassName(flasherClass), "Flasher") == 0);
	JSValue prototype = JS_GetClassProto(sContext, flasherClass);
	OO_CHECK(JS_IsObject(prototype));
	JS_FreeValue(sContext, prototype);
	OO_CHECK(OOJSIsSubclass(flasherClass, sFakeEntityClassID));
	OO_CHECK_EQ(sConverters[flasherClass], 1);
	OO_CHECK([sFlasher cxx_oo_jsClassName] == std::optional<std::string>("Flasher"));
	OO_CHECK([sFlasher isVisibleToScripts]);
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
	sShip->_removedFlasher = nullptr;
	sFlasher->_owner = sShip;
	OO_CHECK_EVAL("flasher.remove()", "undefined");
	OO_CHECK(sShip->_removedFlasher == sFlasherPart);
	sFlasher->_owner = sEffect;
	OO_CHECK_EVAL("flasher.remove()", "undefined");
	OO_CHECK(sEffect->_removed == sFlasher);
	sFlasher->_owner = sShip;
	// The prototype has no entity: the binding's getter fails without reporting an error, which
	// ends the script uncatchably, and nothing is removed.
	sShip->_removedFlasher = nullptr;
	OO_CHECK_EVAL("Flasher.prototype.remove()", "<evaluation failed>");
	OO_CHECK(sShip->_removedFlasher == nullptr);
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
