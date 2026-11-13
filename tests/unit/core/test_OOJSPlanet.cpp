/*	test_OOJSPlanet.mm
	Unit tests for the Planet JS binding (src/Core/Scripting/OOJSPlanet.h/.mm) and its
	OOPlanetEntity category (the C++ class's overrides answer the engine, through the root's JS
	category, and this test's stand-ins are C++ the same way).

	As test_OOJSWormhole.mm does, it runs the JS class in a real QuickJS-ng context, links the
	game's own objects for the binding, the engine's class registry (OOJSClasses.mm), its exception
	translator (OOJSEngineNativeWrappers.mm) and OOColor (a converted class, reached through its
	façade), and stands in for the classes the binding messages (Entity, OOPlanetEntity and the
	universe answer only the selectors the binding sends), for the Vector and Quaternion conversions
	(arrays [x, y, z] and [w, x, y, z] here) and for the engine functions the binding links against,
	with the engine headers' linkage. The tests pin the JS-visible behaviour (the twelve properties, the colours both
	ways, a texture that loads or does not, a moon, a non-planet, a native's exception) and what the
	category answers the engine. Run: tests/run.sh unit
*/

#include "EntityManualRefs.h"  // the tests' manual references
#include "OOColor.h"
#include "OOJSEngineCore.h"
#include "OOStellarBody.h"
#include "oofnd/AutoreleaseScope.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOException.h"


// MARK: The classes, as far as the binding sees them ----------------------------------------------

class Universe;
class TestEntityObject;

// The C++ root, as far as the binding and the root's JS category reach it. _object stands in for the
// game's peer table (oo::ToObjC, below).
class Entity : public oo::Object
{
public:
	virtual ~Entity();
	virtual JSClassID jsClassID();
	virtual std::optional<std::string> jsClassName();
	virtual bool isVisibleToScripts();
	Quaternion normalOrientation();	// the game's is virtual; the binding calls the root's

	::TestEntityObject *_object = nullptr;
};


/*	A planet whose radius is 99 raises from radius(), one whose radius is 98 throws a C++ exception,
	so the test sees what an exception under a native becomes.
*/
class OOPlanetEntity : public Entity
{
public:
	OOStellarBodyType planetType();
	double radius();
	std::optional<std::string> name();
	void setName(const std::optional<std::string> &name);
	OOColor *airColor();
	void setAirColor(OOColor *newColor);
	OOColor *illuminationColor();
	void setIlluminationColor(OOColor *newColor);
	float airColorMixRatio();
	void setAirColorMixRatio(float newRatio);
	float airDensity();
	void setAirDensity(float newDensity);
	bool hasAtmosphere();
	std::optional<std::string> textureFileName();
	bool setUpPlanetFromTexture(const std::optional<std::string> &fileName);
	double rotationalVelocity();
	void setRotationalVelocity(double v);
	Vector terminatorThresholdVector();
	void setTerminatorThresholdVector(Vector newTerminatorThresholdVector);
	void setOrientation(Quaternion quat);	// the game's overrides the root's virtual; the binding calls it qualified

	JSClassID jsClassID() override;
	std::optional<std::string> jsClassName() override;
	bool isVisibleToScripts() override;

	OOStellarBodyType _type = (OOStellarBodyType)0;
	double _radius = 0;
	std::optional<std::string> _name;
	std::shared_ptr<OOColor> _airColor;
	std::shared_ptr<OOColor> _illuminationColor;
	float _airColorMixRatio = 0;
	float _airDensity = 0;
	bool _hasAtmosphere = false;
	std::optional<std::string> _texture;
	double _rotationalVelocity = 0;
	Vector _terminatorThresholdVector = {};
	int _textureLoads = 0;
};


// The root's facade: the planet's object (the C++ part first, where oo::ToCxx
// reads it); it holds the orientation, which the C++ members answer (the root's
// selectors). What an entity's JS object holds: a weak reference to the C++
// entity.
#include "OOJSEntityHolder.h"


// Its category's selectors are members of the same names.
class TestEntityObject final : public oo::Object
{
public:
	JSClassID oo_jsClassID();
	std::optional<std::string> oo_jsClassName();
	bool isVisibleToScripts();

	std::shared_ptr<Entity> _cxxEntity;	// the planet's C++ part (oo::ToCxx reads it)
	Quaternion _orientation = {};	// zeroed, as the object's ivar was
};

// The universe, as far as the binding asks it anything: its main planet (the
// C++ planet).
#include "UniverseStandIn.h"

// The universe as the code under test sees it: a stand-in for the C++ class
// with the header's names and signatures. It answers virtual members, so it
// has the game's vtable (UniverseStandIn.h) and FakeUniverse overrides them.
class Universe : public oo::Object
{
public:
	OO_UNIVERSE_STAND_IN_VIRTUAL_MEMBERS

	OOPlanetEntity *_planet;


};

class FakeUniverse : public Universe
{
public:
	::OOPlanetEntity *planet() override	{ return _planet; }
};

#include "OOJSPlanet.h"

#include "oo_test.hpp"

#include <cstdarg>
#include <cstdint>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>





// The root's JS category, as the game's asks the C++ part (EntityOOJavaScriptExtensions.cpp): the
// engine sends these selectors to the wrapped object.
JSClassID TestEntityObject::oo_jsClassID()  { return _cxxEntity->jsClassID(); }
std::optional<std::string> TestEntityObject::oo_jsClassName()  { return _cxxEntity->jsClassName(); }
bool TestEntityObject::isVisibleToScripts()  { return _cxxEntity->isVisibleToScripts(); }


// The object of a C++ entity, null for null.
::TestEntityObject *TestObjectOf(Entity *entity)  { return entity != nullptr ? entity->_object : nullptr; }


Entity::~Entity()  {}
JSClassID Entity::jsClassID()  { return 0; }
std::optional<std::string> Entity::jsClassName()  { return std::string("Entity"); }
bool Entity::isVisibleToScripts()  { return false; }
// The orientation the object's -normalOrientation and -setOrientation: answered and set.
Quaternion Entity::normalOrientation()  { return TestObjectOf(this)->_orientation; }
void OOPlanetEntity::setOrientation(Quaternion quat)  { TestObjectOf(this)->_orientation = quat; }


OOStellarBodyType OOPlanetEntity::planetType()  { return _type; }
std::optional<std::string> OOPlanetEntity::name()  { return _name; }
void OOPlanetEntity::setName(const std::optional<std::string> &name)  { _name = name; }
OOColor *OOPlanetEntity::airColor()  { return _airColor.get(); }
void OOPlanetEntity::setAirColor(OOColor *newColor)  { _airColor = oo::share(newColor); }
OOColor *OOPlanetEntity::illuminationColor()  { return _illuminationColor.get(); }
void OOPlanetEntity::setIlluminationColor(OOColor *newColor)  { _illuminationColor = oo::share(newColor); }
float OOPlanetEntity::airColorMixRatio()  { return _airColorMixRatio; }
void OOPlanetEntity::setAirColorMixRatio(float newRatio)  { _airColorMixRatio = newRatio; }
float OOPlanetEntity::airDensity()  { return _airDensity; }
void OOPlanetEntity::setAirDensity(float newDensity)  { _airDensity = newDensity; }
bool OOPlanetEntity::hasAtmosphere()  { return _hasAtmosphere; }
std::optional<std::string> OOPlanetEntity::textureFileName()  { return _texture; }
double OOPlanetEntity::rotationalVelocity()  { return _rotationalVelocity; }
void OOPlanetEntity::setRotationalVelocity(double v)  { _rotationalVelocity = v; }
Vector OOPlanetEntity::terminatorThresholdVector()  { return _terminatorThresholdVector; }
void OOPlanetEntity::setTerminatorThresholdVector(Vector v)  { _terminatorThresholdVector = v; }

bool OOPlanetEntity::setUpPlanetFromTexture(const std::optional<std::string> &fileName)
{
	_textureLoads++;
	if (!fileName.has_value() || *fileName == "missing.png")  return false;
	_texture = fileName;
	return true;
}

double OOPlanetEntity::radius()
{
	if (_radius == 99)  OORaiseException(OOInvalidArgumentException, "radius %s", "boom");
	if (_radius == 98)  throw std::runtime_error("cxx boom");
	return _radius;
}


// The binding's category, as the C++ class's overrides answer it.
JSClassID OOPlanetEntity::jsClassID()  { return ::JSPlanetClassID(); }
std::optional<std::string> OOPlanetEntity::jsClassName()  { return ::OOJSPlanetJSClassName(this); }
bool OOPlanetEntity::isVisibleToScripts()  { return ::OOJSPlanetIsVisibleToScripts(this); }


// A new C++ planet and its object (as in the game); the object owns it.
OOPlanetEntity *NewPlanet()
{
	std::shared_ptr<OOPlanetEntity> planet = oo::makeShared<OOPlanetEntity>();
	TestEntityObject *object = oo::test::NewRetained<TestEntityObject>();
	object->_cxxEntity = planet;
	planet->_object = object;
	return planet.get();
}





// MARK: What the rest of the engine provides ------------------------------------------------------

// The one context (OOJSAcquireContext(), which OOJSClasses.mm registers classes through).
JSContext *gOOJSMainThreadContext = nullptr;


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


// The engine's: the pending exception, else an uncatchable error, which ends the script.
JSValue OOJSNativeFailure(JSContext *context)
{
	if (JS_HasException(context))  return JS_EXCEPTION;
	JSValue error = JS_NewError(context);
	JS_SetUncatchableError(context, error);
	return JS_Throw(context, error);
}


// What the class registration (OOJSClasses.mm) asks of the engine: it reports what class set-up
// left pending (the test drops it), and records property IDs, interned for the life of the
// process, as the engine's.
void OOJSReportPendingException(JSContext *context)
{
	JS_FreeValue(context, JS_GetException(context));
}


JSAtom OOJSIDFromString(const std::string &string)
{
	return JS_NewAtomLen(OOJSAcquireContext(), string.data(), string.size());
}


namespace {
std::string sLastWarning;
}

void OOJSReportWarning(JSContext *, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	sLastWarning = oo::str::vformat(format, args);
	va_end(args);
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
// or an array of those. The value is owned by the caller.
JSValue OOJSValueFromPList(JSContext *context, const oo::PList &plist)
{
	if (const std::string *str = plist.getIf<std::string>())  return JS_NewStringLen(context, str->data(), str->size());
	if (plist.isNumber())  return JS_NewNumber(context, plist.doubleValue());
	if (const oo::PList::Array *array = plist.getIf<oo::PList::Array>())
	{
		JSValue object = JS_NewArray(context);
		std::uint32_t i = 0;
		for (const oo::PList &element : *array)  JS_SetPropertyUint32(context, object, i++, OOJSValueFromPList(context, element));
		return object;
	}
	return JS_NULL;
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


namespace {
JSClassID sFakeEntityClassID = 0;
JSClassDef sFakeEntityClass = {
	.class_name = "Entity",
	.finalizer = OOJSCxxObjectWrapperFinalize,	// the slot holds the entity's holder
};
std::map<JSClassID, int> sConverters;


// An array of numbers as JavaScript, and back: enough to see what the binding hands over and takes.
bool NumbersToJSValue(JSContext *context, const double *numbers, unsigned count, JSValue *outValue)
{
	JSValue array = JS_NewArray(context);
	if (JS_IsException(array))  return false;
	for (unsigned i = 0; i < count; i++)  JS_SetPropertyUint32(context, array, i, JS_NewNumber(context, numbers[i]));
	*outValue = array;
	return true;
}


bool JSValueToNumbers(JSContext *context, JSValueConst value, double *numbers, unsigned count)
{
	if (!JS_IsArray(value))  return false;
	for (unsigned i = 0; i < count; i++)
	{
		JSValue element = JS_GetPropertyUint32(context, value, i);
		const bool ok = !JS_IsException(element) && JS_ToFloat64(context, &numbers[i], element) == 0;
		JS_FreeValue(context, element);
		if (!ok)  return false;
	}
	return true;
}

} // namespace

Universe *gSharedUniverse = nullptr;


// A vector is the array [x, y, z] here, a quaternion [w, x, y, z].
bool VectorToJSValue(JSContext *context, Vector vector, JSValue *outValue)
{
	const double parts[3] = { vector.x, vector.y, vector.z };
	return NumbersToJSValue(context, parts, 3, outValue);
}


bool JSValueToVector(JSContext *context, JSValueConst value, Vector *outVector)
{
	double v[3] = {};
	if (!JSValueToNumbers(context, value, v, 3))  return false;
	*outVector = make_vector(v[0], v[1], v[2]);
	return true;
}


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


bool QuaternionToJSValue(JSContext *context, Quaternion quaternion, JSValue *outValue)
{
	const double parts[4] = { quaternion.w, quaternion.x, quaternion.y, quaternion.z };
	return NumbersToJSValue(context, parts, 4, outValue);
}


bool JSValueToQuaternion(JSContext *context, JSValueConst value, Quaternion *outQuaternion)
{
	double q[4] = {};
	if (!JSValueToNumbers(context, value, q, 4))  return false;
	*outQuaternion = make_quaternion(q[0], q[1], q[2], q[3]);
	return true;
}


int sLimiterPauses = 0;
int sProfileDepth = 0;

#if OOJS_PROFILE
void OOJSProfileEnter(OOJSProfileStackFrame *, const char *)  { sProfileDepth++; }
void OOJSProfileExit(OOJSProfileStackFrame *)  { sProfileDepth--; }
#endif

void OOJSPauseTimeLimiter(void)  { sLimiterPauses++; }
void OOJSResumeTimeLimiter(void)  { sLimiterPauses--; }


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
JSValue sGlobal = JS_UNDEFINED;	// owned for the life of the test
OOPlanetEntity *sPlanet = nullptr;
OOPlanetEntity *sMoon = nullptr;
FakeUniverse *sUniverse = nullptr;


// An owned JS object of the class (its prototype the class's), a holder of the entity's C++ part in
// its private slot.
JSValue JSValueForObject(JSClassID jsClass, TestEntityObject *entity)
{
	JSValue object = JS_NewObjectClass(sContext, static_cast<int>(jsClass));
	if (JS_IsException(object))
	{
		JS_FreeValue(sContext, JS_GetException(sContext));
		return JS_NULL;
	}
	if (entity->_cxxEntity == nullptr)  entity->_cxxEntity = oo::makeShared<Entity>();	// a plain entity's C++ part
	OOJSSetCxxPrivate(object, oo::makeShared<OOJSEntityHolder>(entity->_cxxEntity.get()));	// the slot holds the C++ entity
	return object;
}


// A JS object for an entity, as EntityJSValueInContext() makes it: the class the entity's
// category names, and a holder of the entity in the private slot.
JSValue JSValueForEntity(TestEntityObject *entity)
{
	return JSValueForObject(entity->oo_jsClassID(), entity);
}


// Takes value.
void Define(const char *name, JSValue value)
{
	JS_SetPropertyStr(sContext, sGlobal, name, value);
}


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = JS_NewRuntime();
	JS_SetMemoryLimit(sRuntime, 8u * 1024u * 1024u);
	sContext = JS_NewContext(sRuntime);
	gOOJSMainThreadContext = sContext;
	sGlobal = JS_GetGlobalObject(sContext);
	OOJSRegisterClass(&sFakeEntityClassID, &sFakeEntityClass);
	OOJSInitClass(sContext, sGlobal, sFakeEntityClassID, JS_UNDEFINED, OOJSUnconstructableConstruct, 0, nullptr, 0, nullptr, 0, nullptr, 0);
	InitOOJSPlanet(sContext, sGlobal);

	sPlanet = NewPlanet();	// its object is kept for the life of the test
	sPlanet->_type = OOStellarBodyType::kNormalPlanet;
	sPlanet->_radius = 5000;
	sPlanet->_name = "Lave";
	sPlanet->_airColor = OOColor::colorWithRed(0.5f, 0.25f, 1, 1);
	sPlanet->_airColorMixRatio = 0.5f;
	sPlanet->_airDensity = 0.75f;
	sPlanet->_hasAtmosphere = true;
	sPlanet->_texture = "lave.png";
	sPlanet->_rotationalVelocity = 0.125;
	sPlanet->_terminatorThresholdVector = make_vector(0.25, 1, 2);
	TestObjectOf(sPlanet)->_orientation = make_quaternion(1, 0, 0, 0);
	sMoon = NewPlanet();
	sMoon->_type = OOStellarBodyType::kMoon;
	sMoon->_radius = 1000;
	sUniverse = new FakeUniverse();
	sUniverse->_planet = sPlanet;
	gSharedUniverse = sUniverse;
	Define("planet", JSValueForEntity(TestObjectOf(sPlanet)));
	Define("moon", JSValueForEntity(TestObjectOf(sMoon)));
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
	const JSClassID planetClass = TestObjectOf(sPlanet)->oo_jsClassID();
	OO_CHECK(planetClass != 0 && OOJSClassName(planetClass) != nullptr && std::strcmp(OOJSClassName(planetClass), "Planet") == 0);
	JSValue prototype = JS_GetClassProto(sContext, planetClass);
	OO_CHECK(JS_IsObject(prototype));
	JS_FreeValue(sContext, prototype);
	OO_CHECK(OOJSIsSubclass(planetClass, sFakeEntityClassID));
	OO_CHECK_EQ(sConverters[planetClass], 1);
	OO_CHECK_EVAL("typeof Planet", "function");
	OO_CHECK_EVAL("new Planet()", "threw: unconstructable");
	OO_CHECK_EVAL("Object.getPrototypeOf(Planet.prototype) === Entity.prototype", "true");
	OO_CHECK_EVAL("planet instanceof Planet && moon instanceof Planet", "true");
}


OO_TEST(category)
{
	SetUpContext();
	// A planet or a moon is visible to scripts and says which it is; any other stellar body is not.
	OO_CHECK(TestObjectOf(sPlanet)->oo_jsClassName() == std::optional<std::string>("Planet"));
	OO_CHECK(TestObjectOf(sPlanet)->isVisibleToScripts());
	OO_CHECK(TestObjectOf(sMoon)->oo_jsClassName() == std::optional<std::string>("Moon"));
	OO_CHECK(TestObjectOf(sMoon)->isVisibleToScripts());
	OOPlanetEntity *mini = NewPlanet();
	oo::test::Autorelease(TestObjectOf(mini));
	mini->_type = OOStellarBodyType::kMiniature;
	OO_CHECK(TestObjectOf(mini)->oo_jsClassName() == std::optional<std::string>("Unknown"));
	OO_CHECK(!TestObjectOf(mini)->isVisibleToScripts());
	mini->_type = OOStellarBodyType::kSun;
	OO_CHECK(!TestObjectOf(mini)->isVisibleToScripts());
}


OO_TEST(properties)
{
	SetUpContext();
	OO_CHECK_EVAL("planet.airColor", "0.5,0.25,1,1");
	OO_CHECK_EVAL("planet.airColorMixRatio", "0.5");
	OO_CHECK_EVAL("planet.airDensity", "0.75");
	OO_CHECK_EVAL("planet.hasAtmosphere", "true");
	OO_CHECK_EVAL("planet.illuminationColor", "null");
	OO_CHECK_EVAL("planet.isMainPlanet", "true");
	OO_CHECK_EVAL("moon.isMainPlanet", "false");
	OO_CHECK_EVAL("planet.name", "Lave");
	OO_CHECK_EVAL("moon.name", "null");
	OO_CHECK_EVAL("planet.radius", "5000");
	OO_CHECK_EVAL("planet.rotationalVelocity", "0.125");
	OO_CHECK_EVAL("planet.texture", "lave.png");
	OO_CHECK_EVAL("moon.texture", "null");
	OO_CHECK_EVAL("planet.orientation", "1,0,0,0");
	OO_CHECK_EVAL("planet.terminatorThresholdVector", "0.25,1,2");
	OO_CHECK_EVAL("moon.hasAtmosphere", "false");
	OO_CHECK_EVAL("Object.keys(Planet.prototype).join()", "airColor,airColorMixRatio,airDensity,hasAtmosphere,illuminationColor,isMainPlanet,name,radius,rotationalVelocity,texture,orientation,terminatorThresholdVector");
	// Read-only.
	OO_CHECK_EVAL("(function () { planet.radius = 1; return planet.radius; })()", "5000");
	OO_CHECK_EVAL("(function () { planet.isMainPlanet = false; return planet.isMainPlanet; })()", "true");
}


OO_TEST(setters)
{
	SetUpContext();
	OO_CHECK_EVAL("(function () { planet.airColorMixRatio = 0.25; return planet.airColorMixRatio; })()", "0.25");
	OO_CHECK_EVAL("(function () { planet.airColorMixRatio = 'x'; return planet.airColorMixRatio; })()", "NaN");
	sPlanet->_airColorMixRatio = 0.5f;
	OO_CHECK_EVAL("(function () { planet.airDensity = 2; return planet.airDensity; })()", "2");
	OO_CHECK_EVAL("(function () { planet.rotationalVelocity = -0.5; return planet.rotationalVelocity; })()", "-0.5");
	OO_CHECK_EVAL("(function () { planet.name = 'Diso'; return planet.name; })()", "Diso");
	OO_CHECK_EVAL("(function () { planet.name = null; return planet.name; })()", "null");
	OO_CHECK_EVAL("(function () { planet.name = 7; return planet.name; })()", "7");
	sPlanet->_name = "Lave";
	// An orientation is normalised.
	OO_CHECK_EVAL("(function () { planet.orientation = [2, 0, 0, 0]; return planet.orientation; })()", "1,0,0,0");
	OO_CHECK_EVAL("(function () { planet.orientation = [0, 0, 0, -2]; return planet.orientation; })()", "0,0,0,-1");
	OO_CHECK_EVAL("(function () { planet.orientation = 'x'; return planet.orientation; })()", "threw: bad property value");
	OO_CHECK_EVAL("(function () { planet.terminatorThresholdVector = [1, 2, 3]; return planet.terminatorThresholdVector; })()", "1,2,3");
	OO_CHECK_EVAL("(function () { planet.terminatorThresholdVector = 5; return planet.terminatorThresholdVector; })()", "threw: bad property value");
}


OO_TEST(colors)
{
	SetUpContext();
	OO_CHECK_EVAL("(function () { planet.airColor = [0, 1, 0]; return planet.airColor; })()", "0,1,0,1");
	OO_CHECK_EVAL("(function () { planet.airColor = 'redColor'; return planet.airColor; })()", "1,0,0,1");
	OO_CHECK_EVAL("(function () { planet.airColor = null; return planet.airColor; })()", "null");
	OO_CHECK_EVAL("(function () { planet.airColor = 'not a colour'; return planet.airColor; })()", "threw: bad property value");
	OO_CHECK_EVAL("(function () { planet.illuminationColor = [0.25, 0.5, 0.75, 0.5]; return planet.illuminationColor; })()", "0.25,0.5,0.75,0.5");
	OO_CHECK_EVAL("(function () { planet.illuminationColor = null; return planet.illuminationColor; })()", "null");
	OO_CHECK_EVAL("(function () { planet.illuminationColor = {}; return planet.illuminationColor; })()", "threw: bad property value");
}


OO_TEST(texture)
{
	SetUpContext();
	sPlanet->_textureLoads = 0;
	sLastWarning.clear();
	OO_CHECK_EVAL("(function () { planet.texture = 'diso.png'; return planet.texture; })()", "diso.png");
	OO_CHECK_EQ(sPlanet->_textureLoads, 1);
	OO_CHECK_EQ(sLastWarning, std::string());
	// A texture that is not found keeps the old one, with a warning; no exception.
	OO_CHECK_EVAL("(function () { planet.texture = 'missing.png'; return planet.texture; })()", "diso.png");
	OO_CHECK_EQ(sPlanet->_textureLoads, 2);
	OO_CHECK_EQ(sLastWarning, std::string("Cannot find texture \"missing.png\". Value not set."));
	// No texture name: nothing is loaded.
	OO_CHECK_EVAL("(function () { planet.texture = null; return planet.texture; })()", "diso.png");
	OO_CHECK_EQ(sPlanet->_textureLoads, 2);
	OO_CHECK_EQ(sLastWarning, std::string("Expected texture string. Value not set."));
	OO_CHECK_EQ(sLimiterPauses, 0);
	sPlanet->_texture = "lave.png";
}


OO_TEST(otherObjects)
{
	SetUpContext();
	OO_CHECK_EVAL("Object.getOwnPropertyDescriptor(Planet.prototype, 'radius').get.call(plainEntity)", "threw: Native method expected Planet, got [object Object].");
	OO_CHECK_EVAL("Object.getOwnPropertyDescriptor(Planet.prototype, 'name').set.call({}, 'x')", "threw: Native method expected Planet, got [object Object].");
	// No class tags its prototype with Symbol.toStringTag (the old scripting layer's backend did):
	// the object is described as QuickJS describes it.
	OO_CHECK_EVAL("Object.create(Planet.prototype).radius", "threw: Native method expected Planet, got [object Object].");
	OO_CHECK_EVAL("Planet.prototype.radius", "0");	// the prototype has no planet: a message to nil
	OO_CHECK_EVAL("Planet.prototype.name", "null");
}


OO_TEST(nativeExceptions)
{
	SetUpContext();
	// The property getter is a native (OOJS_NATIVE_ENTER): a raise from the entity is a JS error,
	// and so is a C++ exception.
	sPlanet->_radius = 99;
	OO_CHECK_EVAL("planet.radius", "threw: Native exception: radius boom");
	sPlanet->_radius = 98;
	OO_CHECK_EVAL("planet.radius", "threw: Native exception: cxx boom");
	sPlanet->_radius = 5000;
	OO_CHECK_EVAL("planet.radius", "5000");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
}


OO_TEST_MAIN()
