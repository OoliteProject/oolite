/*	test_OOJSPlanet.mm
	Unit tests for the Planet JS binding (src/Core/Scripting/OOJSPlanet.h/.mm) and its
	OOPlanetEntity category (whose forwarders were on the OOPlanetEntity facade from bead oo-9ht.92
	until bead oo-9ht.129 deleted it: the C++ class's overrides answer the engine now, through the
	root's JS category, and this test's stand-ins are C++ the same way, amendment oo-9ht.107 item 6):
	bead oo-7ixd, converted the way bead oo-ppc converted OOJSVector (proposed ADR-0056 amendments
	oo-ppc and oo-ykoy).

	As test_OOJSWormhole.mm does (amendment oo-ykoy, item 4), it runs the JS class in a real
	context on the game's own façade backend (ooscript/JSEngine_quickjs.cpp), links the game's own
	objects for the binding, the engine's exception translator
	(OOJSEngineNativeWrappers.mm) and OOColor (a converted class, reached through its façade), and
	stands in for the classes the binding messages (Entity, OOPlanetEntity and the universe answer
	only the selectors the binding sends), for the Vector and Quaternion conversions (arrays
	[x, y, z] and [w, x, y, z] here) and for the engine functions the binding links against, with
	the engine headers' linkage. The expectations were written against the Objective-C file and run
	on it first; they pin the JS-visible behaviour (the twelve properties, the colours both ways, a
	texture that loads or does not, a moon, a non-planet, a native's exception) and what the
	category answers the engine. Run: bash tools/check-core-tests.sh
*/

#include "OOCocoa.h"
#include "OOColor.h"
#include "OOMaths.h"
#include "OOStellarBody.h"
#include "ooscript/JSEngine.hpp"
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"


// MARK: The classes, as far as the binding sees them ----------------------------------------------

class Universe;
class TestEntityObject;

// The C++ root, as far as the binding and the root's JS category reach it. _object stands in for the
// game's peer table (oo::ToObjC, below).
class Entity : public oo::RefCounted
{
public:
	virtual ~Entity();
	virtual void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype);
	virtual std::optional<std::string> jsClassName();
	virtual bool isVisibleToScripts();
	Quaternion normalOrientation();	// the game's is virtual; the binding calls the root's (bead oo-9ht.39.8.2)

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

	void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype) override;
	std::optional<std::string> jsClassName() override;
	bool isVisibleToScripts() override;

	OOStellarBodyType _type = (OOStellarBodyType)0;
	double _radius = 0;
	std::optional<std::string> _name;
	oo::Ref<OOColor> _airColor;
	oo::Ref<OOColor> _illuminationColor;
	float _airColorMixRatio = 0;
	float _airDensity = 0;
	BOOL _hasAtmosphere = NO;
	std::optional<std::string> _texture;
	double _rotationalVelocity = 0;
	Vector _terminatorThresholdVector = {};
	int _textureLoads = 0;
};


// The root's facade: the planet's object (the C++ part first, where oo::ToCxx reads it); it holds the
// orientation, which the C++ members answer (the root's selectors, which the binding sent until bead
// oo-9ht.39.8.2).
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

	oo::Ref<Entity> _cxxEntity;	// the planet's C++ part (oo::ToCxx reads it)
	Quaternion _orientation = {};	// zeroed, as the object's ivar was
};

// The universe, as far as the binding asks it anything: its main planet (the C++ planet since bead
// oo-9ht.129).
#include "UniverseStandIn.h"

// The universe as the code under test sees it: a stand-in for the C++ class (bead oo-ql9rn deleted
// the Objective-C facade the test's FakeUniverse stood in for), with the header's names and signatures.
// It answers virtual members, so it has the game's vtable (UniverseStandIn.h) and FakeUniverse overrides them.
class Universe : public oo::RefCounted
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
#include <vector>





// The root's JS category, as the game's asks the C++ part (EntityOOJavaScriptExtensions+ObjCBridge.mm,
// bead oo-9ht.107): the engine sends these selectors to the wrapped object.
void TestEntityObject::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)  { _cxxEntity->getJSClass(outClass, outPrototype); }
std::optional<std::string> TestEntityObject::cxx_oo_jsClassName()  { return _cxxEntity->jsClassName(); }
bool TestEntityObject::isVisibleToScripts()  { return _cxxEntity->isVisibleToScripts(); }


// oo::ToObjC (Entity+ObjCBridge.mm) until bead oo-4aq6a.11: the object of a C++ entity, null for null.
::TestEntityObject *TestObjectOf(Entity *entity)  { return entity != nullptr ? entity->_object : nullptr; }


Entity::~Entity()  {}
void Entity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)  { *outClass = nullptr; *outPrototype = nullptr; }
std::optional<std::string> Entity::jsClassName()  { return std::string("Entity"); }
bool Entity::isVisibleToScripts()  { return false; }
// The orientation the object's -normalOrientation and -setOrientation: answered and set until bead oo-9ht.39.8.2.
Quaternion Entity::normalOrientation()  { return TestObjectOf(this)->_orientation; }
void OOPlanetEntity::setOrientation(Quaternion quat)  { TestObjectOf(this)->_orientation = quat; }


OOStellarBodyType OOPlanetEntity::planetType()  { return _type; }
std::optional<std::string> OOPlanetEntity::name()  { return _name; }
void OOPlanetEntity::setName(const std::optional<std::string> &name)  { _name = name; }
OOColor *OOPlanetEntity::airColor()  { return _airColor.get(); }
void OOPlanetEntity::setAirColor(OOColor *newColor)  { _airColor = oo::Ref<OOColor>(newColor); }
OOColor *OOPlanetEntity::illuminationColor()  { return _illuminationColor.get(); }
void OOPlanetEntity::setIlluminationColor(OOColor *newColor)  { _illuminationColor = oo::Ref<OOColor>(newColor); }
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
	if (!fileName.has_value() || *fileName == "missing.png")  return NO;
	_texture = fileName;
	return YES;
}

double OOPlanetEntity::radius()
{
	if (_radius == 99)  OORaiseException(OOInvalidArgumentException, "radius %s", "boom");
	if (_radius == 98)  throw std::runtime_error("cxx boom");
	return _radius;
}


// The binding's category, as the C++ class's overrides answer it (bead oo-9ht.129; the
// OOPlanetEntity facade forwarded it from bead oo-9ht.92).
void OOPlanetEntity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)  { ::OOJSPlanetGetJSClass(outClass, outPrototype); }
std::optional<std::string> OOPlanetEntity::jsClassName()  { return ::OOJSPlanetJSClassName(this); }
bool OOPlanetEntity::isVisibleToScripts()  { return ::OOJSPlanetIsVisibleToScripts(this); }


// A new C++ planet and its object (what oo::NewEntityFacade makes in the game); the object owns it.
OOPlanetEntity *NewPlanet()
{
	oo::Ref<OOPlanetEntity> planet = oo::makeRef<OOPlanetEntity>();
	TestEntityObject *object = oo::makeRef<TestEntityObject>().leakRef();
	object->_cxxEntity = planet;
	planet->_object = object;
	return planet.get();
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


namespace {
std::string sLastWarning;
}

void cxx_OOJSReportWarning(ooscript::Context, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	sLastWarning = oo::str::vformat(format, args);
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
	if (plist.isNumber())  return ooscript::numberValue(plist.doubleValue());
	if (const oo::PList::Array *array = plist.getIf<oo::PList::Array>())
	{
		std::vector<ooscript::Value> values;
		for (const oo::PList &element : *array)  values.push_back(OOJSValueFromPList(context, element));
		ooscript::Object object = ooscript::newArrayObject(context, static_cast<unsigned>(values.size()), values.data());
		return object != nullptr ? ooscript::objectValue(object) : ooscript::nullValue();
	}
	return ooscript::nullValue();
}


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


namespace {
ooscript::ClassDef sFakeEntityClass = { "Entity", ooscript::ClassFlag::HasPrivate };
std::map<ooscript::ClassDef *, ooscript::ClassDef *> sSuperclasses;
std::map<ooscript::ClassDef *, int> sConverters;


// An array of numbers as JavaScript, and back: enough to see what the binding hands over and takes.
bool NumbersToJSValue(ooscript::Context context, const double *numbers, unsigned count, ooscript::Value *outValue)
{
	std::vector<ooscript::Value> parts;
	for (unsigned i = 0; i < count; i++)  parts.push_back(ooscript::numberValue(numbers[i]));
	ooscript::Object array = ooscript::newArrayObject(context, count, parts.data());
	if (array == nullptr)  return false;
	*outValue = ooscript::objectValue(array);
	return true;
}


bool JSValueToNumbers(ooscript::Context context, ooscript::Value value, double *numbers, unsigned count)
{
	ooscript::Value element;
	if (!ooscript::isObject(value) || !ooscript::isArrayObject(context, ooscript::toObject(value)))  return false;
	for (unsigned i = 0; i < count; i++)
	{
		if (!ooscript::getElement(context, ooscript::toObject(value), i, &element) || !ooscript::valueToNumber(context, element, &numbers[i]))  return false;
	}
	return true;
}

} // namespace

ooscript::Object gOOEntityJSPrototype = nullptr;
Universe *gSharedUniverse = nil;


extern "C" {

// A vector is the array [x, y, z] here, a quaternion [w, x, y, z].
bool VectorToJSValue(ooscript::Context context, Vector vector, ooscript::Value *outValue)
{
	const double parts[3] = { vector.x, vector.y, vector.z };
	return NumbersToJSValue(context, parts, 3, outValue);
}


bool JSValueToVector(ooscript::Context context, ooscript::Value value, Vector *outVector)
{
	double v[3] = {};
	if (!JSValueToNumbers(context, value, v, 3))  return false;
	*outVector = make_vector(v[0], v[1], v[2]);
	return true;
}



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



bool QuaternionToJSValue(ooscript::Context context, Quaternion quaternion, ooscript::Value *outValue)
{
	const double parts[4] = { quaternion.w, quaternion.x, quaternion.y, quaternion.z };
	return NumbersToJSValue(context, parts, 4, outValue);
}


bool JSValueToQuaternion(ooscript::Context context, ooscript::Value value, Quaternion *outQuaternion)
{
	double q[4] = {};
	if (!JSValueToNumbers(context, value, q, 4))  return false;
	*outQuaternion = make_quaternion(q[0], q[1], q[2], q[3]);
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


// MARK: The context -------------------------------------------------------------------------------

namespace {

ooscript::Runtime sRuntime;
ooscript::Context sContext;
ooscript::Object sGlobal;
OOPlanetEntity *sPlanet = nil;
OOPlanetEntity *sMoon = nil;
FakeUniverse *sUniverse = nil;


ooscript::Value JSValueForObject(ooscript::ClassDef *jsClass, ooscript::Object prototype, TestEntityObject *entity)
{
	ooscript::Object object = ooscript::newObject(sContext, jsClass, prototype, nullptr);
	if (entity->_cxxEntity == nullptr)  entity->_cxxEntity = oo::makeRef<Entity>();	// a plain entity's C++ part
	if (object == nullptr || !OOJSSetCxxPrivate(sContext, object, oo::makeRef<OOJSEntityHolder>(entity->_cxxEntity.get()).get()))  return ooscript::nullValue();	// the slot holds the C++ entity (bead oo-9ht.39.3)
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
	InitOOJSPlanet(sContext, sGlobal);

	sPlanet = NewPlanet();	// its object is kept for the life of the test
	sPlanet->_type = STELLAR_TYPE_NORMAL_PLANET;
	sPlanet->_radius = 5000;
	sPlanet->_name = "Lave";
	sPlanet->_airColor = OOColor::colorWithRed(0.5f, 0.25f, 1, 1);
	sPlanet->_airColorMixRatio = 0.5f;
	sPlanet->_airDensity = 0.75f;
	sPlanet->_hasAtmosphere = YES;
	sPlanet->_texture = "lave.png";
	sPlanet->_rotationalVelocity = 0.125;
	sPlanet->_terminatorThresholdVector = make_vector(0.25, 1, 2);
	TestObjectOf(sPlanet)->_orientation = make_quaternion(1, 0, 0, 0);
	sMoon = NewPlanet();
	sMoon->_type = STELLAR_TYPE_MOON;
	sMoon->_radius = 1000;
	sUniverse = new FakeUniverse();
	sUniverse->_planet = sPlanet;
	gSharedUniverse = sUniverse;
	Define("planet", JSValueForEntity(TestObjectOf(sPlanet)));
	Define("moon", JSValueForEntity(TestObjectOf(sMoon)));
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
	ooscript::ClassDef *planetClass = nullptr;
	ooscript::Object prototype = nullptr;
	TestObjectOf(sPlanet)->getJSClass(&planetClass, &prototype);
	OO_CHECK(planetClass != nullptr && std::strcmp(planetClass->name, "Planet") == 0);
	OO_CHECK(prototype != nullptr);
	OO_CHECK(OOJSIsSubclass(planetClass, &sFakeEntityClass));
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
	OO_CHECK(TestObjectOf(sPlanet)->cxx_oo_jsClassName() == std::optional<std::string>("Planet"));
	OO_CHECK(TestObjectOf(sPlanet)->isVisibleToScripts());
	OO_CHECK(TestObjectOf(sMoon)->cxx_oo_jsClassName() == std::optional<std::string>("Moon"));
	OO_CHECK(TestObjectOf(sMoon)->isVisibleToScripts());
	OOPlanetEntity *mini = NewPlanet();
	oo::autorelease(TestObjectOf(mini));
	mini->_type = STELLAR_TYPE_MINIATURE;
	OO_CHECK(TestObjectOf(mini)->cxx_oo_jsClassName() == std::optional<std::string>("Unknown"));
	OO_CHECK(!TestObjectOf(mini)->isVisibleToScripts());
	mini->_type = STELLAR_TYPE_SUN;
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
	OO_CHECK_EVAL("Object.getOwnPropertyDescriptor(Planet.prototype, 'radius').get.call(plainEntity)", "threw: Native method expected Planet, got [object Entity].");
	OO_CHECK_EVAL("Object.getOwnPropertyDescriptor(Planet.prototype, 'name').set.call({}, 'x')", "threw: Native method expected Planet, got [object Object].");
	OO_CHECK_EVAL("Object.create(Planet.prototype).radius", "threw: Native method expected Planet, got [object Planet].");
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
	OO_CHECK(ooscript::isInRequest(sContext));
}


OO_TEST_MAIN()
