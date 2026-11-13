/*	test_OOJSVisualEffect.mm
	Unit tests for the VisualEffect JS binding (src/Core/Scripting/OOJSVisualEffect.h/.mm) and its
	OOVisualEffectEntity category (the C++ class's overrides of the root's JS members: this test's
	stand-in is that C++ class under a stand-in root object, as test_OOJSFlasher.mm stands in for
	the flasher).

	As test_OOJSWormhole.mm does, it runs the JS class in a real QuickJS-ng context, links the
	game's own objects for the binding, the engine's class registration (OOJSClasses.mm), the
	engine's exception translator (OOJSEngineNativeWrappers.mm) and OOColor (a converted class,
	reached through its façade), and stands in for the classes the binding messages (Entity,
	OOVisualEffectEntity, OOMesh, ResourceManager, and the universe's beacon list and the player's
	compass answer only the selectors the binding sends), for the Vector conversions (an array [x,
	y, z] here) and for the engine functions the binding links against, with the engine headers'
	linkage. The binding header is not imported; InitOOJSVisualEffect is declared here. The
	expectations pin the
	JS-visible behaviour (the properties both ways, a beacon code that registers or clears a beacon,
	the methods, a stale effect, a non-effect, a native's exception) and what the category answers
	the engine. The binding makes and asks a C++ mesh, so the stand-in for it is a C++ class OOMesh
	with the members the binding calls and the same answers. Run: bash tests/run.sh unit
*/

#include "OOFoundation.h"
#include "OOColor.h"
#include "OOMaths.h"
#include "OOTypes.h"
#include <quickjs.h>
#include "oofnd/objc/OOException.h"
#include "OOEntityHold.h"	// the sub-entity lists
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#include "OODescription.h"
#include "oofnd/StdLib.hpp"
#include "EntityPListForeign.h"	// an entity's node
#include "OOScript.h"


// MARK: The classes, as far as the binding sees them ----------------------------------------------

class Universe;
class PlayerEntity;
class TestEntityObject;	// the test's stand-in root object, below

// The C++ root, as far as the binding and the root's JS category reach it (the
// members the binding calls, declared as Entity.h declares them), and the C++
// part's object (TestObjectOf).
class Entity : public oo::RefCounted
{
public:
	virtual ~Entity();
	virtual JSClassID jsClassID();
	virtual std::optional<std::string> jsClassName();
	virtual bool isVisibleToScripts();
	bool getIsSubEntity();
	Entity *owner();	// the C++ entity

	bool _isSubEntity = false;
	::TestEntityObject *_owner = nullptr;
	::TestEntityObject *_object = nullptr;	// the object holding this part (not retained)
};

// What an entity's JS object holds: a weak reference to the C++ entity.
#include "OOJSEntityHolder.h"


// Its category's selectors are members of the same names.
class TestEntityObject final : public oo::RefCounted
{
public:
	const char *className() const  { return "Entity"; }	// the class's runtime name
	JSClassID oo_jsClassID();
	std::optional<std::string> cxx_oo_jsClassName();
	bool isVisibleToScripts();

	std::shared_ptr<Entity> _cxxEntity;
};

// A mesh: its materials and shaders, and the arguments the last one was made
// with. The members of OOMesh (OOMesh.h) the binding calls, with their
// signatures.

class OOMesh : public oo::RefCounted
{
public:
	static std::shared_ptr<OOMesh> meshWithName(const std::string &name,
										const std::optional<std::string> &cacheKey,
										const oo::PList &materialDict,
										const oo::PList &shadersDict,
										bool smooth,
										const oo::PList &macros,
										Entity *object);	// the C++ effect
	oo::PList getMaterials();
	oo::PList shaders();

	oo::PList _materials;
	oo::PList _shaders;
};

#include "ResourceManager.h"

/*	An effect whose hull heat level is 99 raises from hullHeatLevel(), one
   whose level is 98 throws a C++ exception, so the test sees what an exception
   under a native becomes. It is the C++ part of its object, with the members
   the binding calls (declared as OOVisualEffectEntity.h declares them; the test
   imports none that defines the classes).
*/
typedef TestEntityObject OOVisualEffectSubEntity;	// the object conforming to OOSubEntity
typedef TestEntityObject OOVisualEffectBeaconEntity;	// the object conforming to OOBeaconEntity

class OOVisualEffectEntity : public Entity
{
public:
	std::optional<std::string> effectKey();
	bool isBreakPattern();
	void setIsBreakPattern(bool bp);
	Vector forwardVector();
	Vector rightVector();
	Vector upVector();
	GLfloat scaleX();
	void setScaleX(GLfloat factor);
	GLfloat scaleY();
	void setScaleY(GLfloat factor);
	GLfloat scaleZ();
	void setScaleZ(GLfloat factor);
	OOColor *scannerDisplayColor1();
	OOColor *scannerDisplayColor2();
	void setScannerDisplayColor1(OOColor *color);
	void setScannerDisplayColor2(OOColor *color);
	GLfloat hullHeatLevel();
	void setHullHeatLevel(GLfloat value);
	GLfloat shaderFloat1();
	void setShaderFloat1(GLfloat value);
	GLfloat shaderFloat2();
	void setShaderFloat2(GLfloat value);
	int shaderInt1();
	void setShaderInt1(int value);
	int shaderInt2();
	void setShaderInt2(int value);
	Vector shaderVector1();
	void setShaderVector1(Vector value);
	Vector shaderVector2();
	void setShaderVector2(Vector value);
	std::optional<std::vector<oo::EntityHold>> visualEffectSubEntityEnumerator();
	::OOScript *script();
	oo::PList scriptInfo();
	oo::PList effectInfoDictionary();
	::OOMesh *mesh();
	void setMesh(::OOMesh *mesh);
	void removeSubEntity(OOVisualEffectSubEntity *sub);
	void removeSubEntity(Entity *sub);	// the binding's
	void remove();
	void clearSubEntities();
	bool setUpSubEntities();
	std::optional<std::string> beaconCode();
	void setBeaconCode(const std::optional<std::string> &bcode);
	std::optional<std::string> beaconLabel();
	void setBeaconLabel(const std::optional<std::string> &blabel);
	bool isBeacon();

	JSClassID jsClassID() override;
	std::optional<std::string> jsClassName() override;
	bool isVisibleToScripts() override;

	std::optional<std::string> _effectKey;
	bool _isBreakPattern = false;
	float _scaleX = 0, _scaleY = 0, _scaleZ = 0;
	std::shared_ptr<OOColor> _color1;
	std::shared_ptr<OOColor> _color2;
	float _hullHeatLevel = 0;
	float _shaderFloat1 = 0, _shaderFloat2 = 0;
	int _shaderInt1 = 0, _shaderInt2 = 0;
	Vector _shaderVector1 = {}, _shaderVector2 = {};
	std::optional<std::vector<oo::EntityHold>> _subs;
	int _subsAfterSetUp = 0;
	OOScript *_script = nullptr;	// a C++ script (retained)
	oo::PList _scriptInfo;
	oo::PList _effectInfo;
	std::shared_ptr<OOMesh> _mesh;
	::TestEntityObject *_removedSub = nullptr;
	int _removed = 0;
	std::optional<std::string> _beaconCode;
	std::optional<std::string> _beaconLabel;
};

// The universe's beacon list and the player's compass: what the binding tells them.
#include "UniverseStandIn.h"

// The universe as the code under test sees it: a stand-in for the C++ class. It
// answers virtual members, so it has the game's vtable (UniverseStandIn.h) and
// FakeGame overrides them; FakeGame also answers the player's compass (the
// player stand-in calls it).
class Universe : public oo::RefCounted
{
public:
	OO_UNIVERSE_STAND_IN_VIRTUAL_MEMBERS
};

class FakeGame : public Universe
{
public:
	::TestEntityObject *_nextBeacon = nullptr;
	int _cleared = 0;
	int _added = 0;
	int _compassMode = 0;

	// The C++ entity (the effect's object holds this part).
	void setNextBeacon(Entity *beacon) override  { _added++; (void)beacon; }
	void clearBeacon(Entity *beacon) override  { _cleared++; static_cast<OOVisualEffectEntity *>(beacon)->_beaconCode = std::nullopt; }
	TestEntityObject *nextBeacon()  { return _nextBeacon; }
	void setCompassMode(OOCompassMode mode)  { _compassMode = static_cast<int>(mode); }
};

// PLAYER: the compass members the binding calls (declared as the game headers
// declare them; the test imports none that defines the classes), which ask the
// fake game as the binding asked it.
class ShipEntity : public Entity
{
public:
	::TestEntityObject *nextBeacon();
	Entity *nextBeaconEntity();
};

class PlayerEntity : public ShipEntity
{
public:
	void setCompassMode(OOCompassMode value);

	FakeGame *_game = nullptr;
};


void InitOOJSVisualEffect(JSContext* context, JSValueConst global);
// The category's bodies, which the stand-in's overrides call as the C++ class's do (declared in OOJSVisualEffect.h).
JSClassID JSVisualEffectClassID(void);
std::optional<std::string> OOJSVisualEffectJSClassName(void);
bool OOJSVisualEffectIsVisibleToScripts(void);
std::vector<oo::EntityHold> OOJSVisualEffectSubEntitiesForScript(OOVisualEffectEntity *effect);	// what -subEntitiesForScript answered
#include "OOJSEngineCore.h"


#include "oo_test.hpp"

#include <cmath>

// OOScript's virtual members (OOScript.mm reaches the whole game), for the
// test's script (the effect's script is C++). It stands in for the OOObject the
// case gave the effect before, so its node names that class.
std::optional<std::string> OOScript::descriptionComponents()	{ return std::nullopt; }
std::optional<std::string> OOScript::name()					{ return std::nullopt; }
std::optional<std::string> OOScript::scriptDescription()		{ return std::nullopt; }
std::optional<std::string> OOScript::version()				{ return std::nullopt; }
bool OOScript::requiresTickle()								{ return false; }
void OOScript::runWithTarget(Entity *)						{}
bool OOScript::callMethod(JSAtom, JSContext *, JSValueConst *, int, JSValue *)	{ return false; }
std::string OOScript::className() const						{ return "OOObject"; }
std::string OOScript::description() const						{ return "<OOObject>"; }
JSValue OOScript::jsValueInContext(JSContext *)				{ return JS_UNDEFINED; }
void OOScript::clearJSSelf(JSValueConst)						{}

#include <cstdarg>
#include <cstdint>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>


// The root's JS category, as the game's asks the C++ part: the
// engine sends these selectors to the wrapped object.
JSClassID TestEntityObject::oo_jsClassID()  { return _cxxEntity->jsClassID(); }
std::optional<std::string> TestEntityObject::cxx_oo_jsClassName()  { return _cxxEntity->jsClassName(); }
bool TestEntityObject::isVisibleToScripts()  { return _cxxEntity->isVisibleToScripts(); }


Entity::~Entity()  {}
JSClassID Entity::jsClassID()  { return 0; }
std::optional<std::string> Entity::jsClassName()  { return std::nullopt; }
bool Entity::isVisibleToScripts()  { return false; }
bool Entity::getIsSubEntity()  { return _isSubEntity; }
Entity *Entity::owner()  { return _owner != nullptr ? _owner->_cxxEntity.get() : nullptr; }	// its object's C++ part

// The object of a C++ part: the one that holds it (the game's never makes one
// here either).
::TestEntityObject *TestObjectOf(Entity *entity)  { return entity != nullptr ? entity->_object : nullptr; }
#define OO_ENTITY_HELPERS_STAND_IN_CXX
#include "EntityHelpersStandIn.h"	// EntityHelpers.mm's, on the test's objects


namespace {

// An effect's object and its C++ part, as oo::NewVisualEffectObject() makes them (autoreleased).
TestEntityObject *NewEffectObject()
{
	TestEntityObject *object = oo::autorelease(oo::makeRef<TestEntityObject>());
	object->_cxxEntity = oo::makeRef<OOVisualEffectEntity>();
	object->_cxxEntity->_object = object;
	return object;
}

}	// namespace


namespace {
std::string sMeshName;
std::optional<std::string> sMeshCacheKey;
oo::PList sMeshMaterials;
oo::PList sMeshShaders;
oo::PList sMeshMacros;
bool sMeshSmooth = false;
::TestEntityObject *sMeshTarget = nullptr;
int sMeshesMade = 0;
}  // namespace

std::shared_ptr<OOMesh> OOMesh::meshWithName(const std::string &name,
									 const std::optional<std::string> &cacheKey,
									 const oo::PList &materialDict,
									 const oo::PList &shadersDict,
									 bool smooth,
									 const oo::PList &macros,
									 Entity *object)
{
	sMeshName = name;
	sMeshCacheKey = cacheKey;
	sMeshMaterials = materialDict;
	sMeshShaders = shadersDict;
	sMeshSmooth = smooth;
	sMeshMacros = macros;
	sMeshTarget = TestObjectOf(object);	// its object
	sMeshesMade++;
	if (name == "nomesh.dat")  return nullptr;
	std::shared_ptr<OOMesh> mesh = oo::makeRef<OOMesh>();
	mesh->_materials = materialDict;
	mesh->_shaders = shadersDict;
	return mesh;
}

oo::PList OOMesh::getMaterials()  { return _materials; }
oo::PList OOMesh::shaders()  { return _shaders; }


// ResourceManager: C++ definitions of the statics the code under test calls,
// with the stand-in's answers.
oo::PList ResourceManager::materialDefaults()
{
	oo::PList::Dict macros;
	macros["OO_TEST"] = oo::PList(1.0);
	oo::PList::Dict defaults;
	defaults["ship-prefix-macros"] = oo::PList(std::move(macros));
	return oo::PList(std::move(defaults));
}



std::optional<std::string> OOVisualEffectEntity::effectKey()  { return _effectKey; }
bool OOVisualEffectEntity::isBreakPattern()  { return _isBreakPattern; }
void OOVisualEffectEntity::setIsBreakPattern(bool bp)  { _isBreakPattern = bp; }
Vector OOVisualEffectEntity::forwardVector()  { return make_vector(0, 0, 1); }
Vector OOVisualEffectEntity::rightVector()  { return make_vector(1, 0, 0); }
Vector OOVisualEffectEntity::upVector()  { return make_vector(0, 1, 0); }
GLfloat OOVisualEffectEntity::scaleX()  { return _scaleX; }
void OOVisualEffectEntity::setScaleX(GLfloat factor)  { _scaleX = factor; }
GLfloat OOVisualEffectEntity::scaleY()  { return _scaleY; }
void OOVisualEffectEntity::setScaleY(GLfloat factor)  { _scaleY = factor; }
GLfloat OOVisualEffectEntity::scaleZ()  { return _scaleZ; }
void OOVisualEffectEntity::setScaleZ(GLfloat factor)  { _scaleZ = factor; }
OOColor *OOVisualEffectEntity::scannerDisplayColor1()  { return _color1.get(); }
OOColor *OOVisualEffectEntity::scannerDisplayColor2()  { return _color2.get(); }
void OOVisualEffectEntity::setScannerDisplayColor1(OOColor *color)  { _color1 = oo::share(color); }
void OOVisualEffectEntity::setScannerDisplayColor2(OOColor *color)  { _color2 = oo::share(color); }
void OOVisualEffectEntity::setHullHeatLevel(GLfloat value)  { _hullHeatLevel = value; }
GLfloat OOVisualEffectEntity::shaderFloat1()  { return _shaderFloat1; }
void OOVisualEffectEntity::setShaderFloat1(GLfloat value)  { _shaderFloat1 = value; }
GLfloat OOVisualEffectEntity::shaderFloat2()  { return _shaderFloat2; }
void OOVisualEffectEntity::setShaderFloat2(GLfloat value)  { _shaderFloat2 = value; }
int OOVisualEffectEntity::shaderInt1()  { return _shaderInt1; }
void OOVisualEffectEntity::setShaderInt1(int value)  { _shaderInt1 = value; }
int OOVisualEffectEntity::shaderInt2()  { return _shaderInt2; }
void OOVisualEffectEntity::setShaderInt2(int value)  { _shaderInt2 = value; }
Vector OOVisualEffectEntity::shaderVector1()  { return _shaderVector1; }
void OOVisualEffectEntity::setShaderVector1(Vector value)  { _shaderVector1 = value; }
Vector OOVisualEffectEntity::shaderVector2()  { return _shaderVector2; }
void OOVisualEffectEntity::setShaderVector2(Vector value)  { _shaderVector2 = value; }
std::optional<std::vector<oo::EntityHold>> OOVisualEffectEntity::visualEffectSubEntityEnumerator()  { return _subs; }
::OOScript *OOVisualEffectEntity::script()  { return _script; }
oo::PList OOVisualEffectEntity::scriptInfo()  { return _scriptInfo; }
oo::PList OOVisualEffectEntity::effectInfoDictionary()  { return _effectInfo; }
::OOMesh *OOVisualEffectEntity::mesh()  { return _mesh.get(); }
void OOVisualEffectEntity::setMesh(::OOMesh *mesh)  { _mesh = oo::share(mesh); }
void OOVisualEffectEntity::removeSubEntity(OOVisualEffectSubEntity *sub)  { _removedSub = sub; }
void OOVisualEffectEntity::removeSubEntity(Entity *sub)  { _removedSub = TestObjectOf(sub); }	// its object, as the binding passed it
void OOVisualEffectEntity::remove()  { _removed++; }
std::optional<std::string> OOVisualEffectEntity::beaconCode()  { return _beaconCode; }
void OOVisualEffectEntity::setBeaconCode(const std::optional<std::string> &bcode)  { _beaconCode = bcode; }
std::optional<std::string> OOVisualEffectEntity::beaconLabel()  { return _beaconLabel; }
void OOVisualEffectEntity::setBeaconLabel(const std::optional<std::string> &blabel)  { _beaconLabel = blabel; }
bool OOVisualEffectEntity::isBeacon()  { return _beaconCode.has_value() && !_beaconCode->empty(); }

GLfloat OOVisualEffectEntity::hullHeatLevel()
{
	if (_hullHeatLevel == 99)  OORaiseException(OOInvalidArgumentException, "heat %s", "boom");
	if (_hullHeatLevel == 98)  throw std::runtime_error("cxx boom");
	return _hullHeatLevel;
}

void OOVisualEffectEntity::clearSubEntities()
{
	_subs = std::nullopt;
}

bool OOVisualEffectEntity::setUpSubEntities()
{
	std::vector<oo::EntityHold> subs;
	for (int i = 0; i < _subsAfterSetUp; i++)  subs.emplace_back(NewEffectObject()->_cxxEntity.get());
	if (!subs.empty())  _subs = subs;
	return true;
}


// The JS questions the engine asks the object, which the effect's C++ class's
// overrides answer.
JSClassID OOVisualEffectEntity::jsClassID()  { return ::JSVisualEffectClassID(); }
std::optional<std::string> OOVisualEffectEntity::jsClassName()  { return ::OOJSVisualEffectJSClassName(); }
bool OOVisualEffectEntity::isVisibleToScripts()  { return ::OOJSVisualEffectIsVisibleToScripts(); }



::TestEntityObject *ShipEntity::nextBeacon()  { return static_cast<PlayerEntity *>(this)->_game->nextBeacon(); }
Entity *ShipEntity::nextBeaconEntity()  { ::TestEntityObject *object = nextBeacon(); return object != nullptr ? object->_cxxEntity.get() : nullptr; }	// as the game's (oo::ToCxx of it)
void PlayerEntity::setCompassMode(OOCompassMode value)  { static_cast<PlayerEntity *>(this)->_game->setCompassMode(value); }


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


namespace {
std::string sLastWarning;
}

void cxx_OOJSReportWarning(JSContext *, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	sLastWarning = oo::str::vformat(format, args);
	va_end(args);
}


void cxx_OOJSReportBadArguments(JSContext *context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, int argc, JSValueConst *, const std::optional<std::string> &message, const std::optional<std::string> &expectedArgsDescription)
{
	cxx_OOJSReportError(context, "bad arguments: %s.%s(%d) %s / %s", scriptClass.value_or("-").c_str(), function.value_or("-").c_str(), argc, message.value_or("-").c_str(), expectedArgsDescription.value_or("-").c_str());
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


std::optional<std::string> cxx_OOStringFromJSValueEvenIfNull(JSContext *context, JSValueConst value)
{
	if (JS_IsNull(value))  return std::string("null");
	if (JS_IsUndefined(value))  return std::string("undefined");
	return cxx_OOStringFromJSValue(context, value);
}


// The engine's: rounded to nearest; NaN or out of range is an error.
bool OOJSValueToInt32(JSContext *context, JSValueConst value, int32_t *outValue)
{
	double number;
	if (JS_ToFloat64(context, &number, value) < 0)  return false;
	number = std::floor(number + 0.5);
	if (std::isnan(number) || number < INT32_MIN || number > INT32_MAX)
	{
		cxx_OOJSReportError(context, "can't convert %s to an integer", cxx_OOStringFromJSValueEvenIfNull(context, value).value_or("(null)").c_str());
		return false;
	}
	*outValue = static_cast<int32_t>(number);
	return true;
}


// A property list as JavaScript, as far as the binding hands one over: null, a string, a number,
// an object (as the string "[ClassName]"), or an array or dictionary of those.
JSValue OOJSValueFromPList(JSContext *context, const oo::PList &plist)
{
	if (const std::string *str = plist.getIf<std::string>())  return JS_NewStringLen(context, str->data(), str->size());
	if (plist.isNumber())  return JS_NewNumber(context, plist.doubleValue());
	Entity *nodeEntity = oo::EntityIn(plist);	// an entity's node: its object
	if (::TestEntityObject *object = (nodeEntity != nullptr) ? TestObjectOf(nodeEntity) : nullptr)
	{
		std::string name = std::string("[") + object->className() + "]";
		// An entity's object is named by its C++ part's class, as
    // oo::EntityClassName() names it.
		if (object->_cxxEntity != nullptr)
		{
			if (dynamic_cast<OOVisualEffectEntity *>(object->_cxxEntity.get()) != nullptr)  name = "[OOVisualEffectEntity]";
		}
		return JS_NewStringLen(context, name.data(), name.size());
	}
	// A C++ object node (a script), named by its className().
	if (const oo::PList::Object *node = plist.getIf<oo::PList::Object>())
	{
		std::string name = "[" + node->get()->className() + "]";
		return JS_NewStringLen(context, name.data(), name.size());
	}
	if (const oo::PList::Array *array = plist.getIf<oo::PList::Array>())
	{
		JSValue object = JS_NewArray(context);
		std::uint32_t index = 0;
		for (const oo::PList &element : *array)  JS_SetPropertyUint32(context, object, index++, OOJSValueFromPList(context, element));
		return object;
	}
	if (const oo::PList::Dict *dict = plist.getIf<oo::PList::Dict>())
	{
		JSValue object = JS_NewObject(context);
		for (const auto &entry : *dict)  JS_SetPropertyStr(context, object, entry.first.c_str(), OOJSValueFromPList(context, entry.second));
		return object;
	}
	return JS_NULL;
}


// A JS value's plist form: a string, a number, an array, an object's own enumerable properties
// (by JSON), or null.
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


// An object as a dictionary, as far as the test hands one over: its "key" property, if any.
oo::PList cxx_OOJSPListFromJSObject(JSContext *context, JSValueConst object)
{
	oo::PList::Dict dict;
	JSValue value = JS_GetPropertyStr(context, object, "key");
	if (JS_IsException(value))  JS_FreeValue(context, JS_GetException(context));
	else if (!JS_IsUndefined(value))  dict["key"] = cxx_OOJSPListFromJSValue(context, value);
	JS_FreeValue(context, value);
	return oo::PList(std::move(dict));
}


namespace {
JSClassID sFakeEntityClassID = 0;
JSClassDef sFakeEntityClass = { .class_name = "Entity" };
std::map<JSClassID, int> sConverters;
} // namespace

Entity *gOOJSPlayerIfStale = nullptr;	// the player's C++ entity
Universe *gSharedUniverse = nullptr;
PlayerEntity *gOOPlayer = nullptr;


// A vector is the array [x, y, z] here.
bool VectorToJSValue(JSContext *context, Vector vector, JSValue *outValue)
{
	JSValue array = JS_NewArray(context);
	if (JS_IsException(array))  return false;
	JS_SetPropertyUint32(context, array, 0, JS_NewNumber(context, vector.x));
	JS_SetPropertyUint32(context, array, 1, JS_NewNumber(context, vector.y));
	JS_SetPropertyUint32(context, array, 2, JS_NewNumber(context, vector.z));
	*outValue = array;
	return true;
}


bool JSValueToVector(JSContext *context, JSValueConst value, Vector *outVector)
{
	double v[3] = {};
	if (!JS_IsArray(value))  return false;
	for (std::uint32_t i = 0; i < 3; i++)
	{
		JSValue element = JS_GetPropertyUint32(context, value, i);
		const bool ok = !JS_IsException(element) && JS_ToFloat64(context, &v[i], element) == 0;
		JS_FreeValue(context, element);
		if (!ok)  return false;
	}
	*outVector = make_vector(v[0], v[1], v[2]);
	return true;
}


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


// The engine's object getter is OOJSPrivateObject.cpp's (linked): the JS class must be a subclass
// of the required one, and the slot holds the entity's holder.

// The shared toString(), which OOJSCxxObjectWrapperToString() hands a `this` of another class.
JSValue OOJSObjectWrapperToString(JSContext *context, JSValueConst, int, JSValueConst *)
{
	return JS_NewString(context, "[object]");
}


JSValue OOJSUnconstructableConstruct(JSContext *context, JSValueConst, int, JSValueConst *)
{
	cxx_OOJSReportError(context, "unconstructable");
	return JS_EXCEPTION;
}


int sLimiterPauses = 0;
int sProfileDepth = 0;
int sFullNatives = 0;

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

JSRuntime *sRuntime = nullptr;
JSContext *sContext = nullptr;
JSValue sGlobal = JS_UNDEFINED;	// held for the life of the test
TestEntityObject *sEffect = nullptr;	// an effect's object and its C++ part
OOVisualEffectEntity *sEffectPart = nullptr;
TestEntityObject *sSub = nullptr;
OOVisualEffectEntity *sSubPart = nullptr;
FakeGame *sGame = nullptr;


// A JS object of the class, with the class's prototype and a holder of the entity's C++ part in
// the private slot; owned by the caller.
JSValue JSValueForObject(JSClassID jsClass, TestEntityObject *entity)
{
	JSValue object = JS_NewObjectClass(sContext, static_cast<int>(jsClass));
	if (entity->_cxxEntity == nullptr)  entity->_cxxEntity = oo::makeRef<Entity>();	// a plain entity's C++ part
	if (JS_IsException(object) || !OOJSSetCxxPrivate(object, oo::makeShared<OOJSEntityHolder>(entity->_cxxEntity.get())))	// the slot holds the C++ entity
	{
		JS_FreeValue(sContext, object);
		return JS_NULL;
	}
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
	InitOOJSVisualEffect(sContext, sGlobal);
	sGame = new FakeGame();	// kept for the life of the test
	gSharedUniverse = sGame;
	gOOPlayer = new PlayerEntity;	// never deleted
	gOOPlayer->_game = sGame;
	sEffect = NewEffectObject();
	sEffect->retain();
	sEffectPart = static_cast<OOVisualEffectEntity *>(sEffect->_cxxEntity.get());
	sEffectPart->_beaconLabel = "Label";
	sEffectPart->_effectKey = "test-effect";
	sEffectPart->_scaleX = 1;
	sEffectPart->_scaleY = 2;
	sEffectPart->_scaleZ = 4;
	sEffectPart->_color1 = OOColor::colorWithRed(1, 0.5f, 0.25f, 1);
	sEffectPart->_hullHeatLevel = 0.5f;
	sEffectPart->_shaderFloat1 = 1.5f;
	sEffectPart->_shaderInt2 = -3;
	sEffectPart->_shaderVector1 = make_vector(1, 2, 3);
	oo::PList::Dict info;
	info["note"] = oo::PList(std::string("hello"));
	sEffectPart->_scriptInfo = oo::PList(std::move(info));
	oo::PList::Dict effectInfo;
	effectInfo["model"] = oo::PList(std::string("effect.dat"));
	effectInfo["smooth"] = oo::PList(true);
	sEffectPart->_effectInfo = oo::PList(std::move(effectInfo));
	sSub = NewEffectObject();
	sSub->retain();
	sSubPart = static_cast<OOVisualEffectEntity *>(sSub->_cxxEntity.get());
	sSubPart->_isSubEntity = true;
	sSubPart->_owner = sEffect;
	Define("effect", JSValueForEntity(sEffect));
	Define("sub", JSValueForEntity(sSub));
	Define("plainEntity", JSValueForObject(sFakeEntityClassID, oo::makeRef<TestEntityObject>().leakRef()));
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
	JSClassID effectClass = sEffect->oo_jsClassID();
	OO_CHECK(effectClass != 0 && OOJSClassName(effectClass) != nullptr && std::strcmp(OOJSClassName(effectClass), "VisualEffect") == 0);
	JSValue prototype = JS_GetClassProto(sContext, effectClass);
	OO_CHECK(JS_IsObject(prototype));
	JS_FreeValue(sContext, prototype);
	OO_CHECK(OOJSIsSubclass(effectClass, sFakeEntityClassID));
	OO_CHECK_EQ(sConverters[effectClass], 1);
	OO_CHECK(sEffect->cxx_oo_jsClassName() == std::optional<std::string>("VisualEffect"));
	OO_CHECK(sEffect->isVisibleToScripts());
	OO_CHECK_EVAL("typeof VisualEffect", "function");
	OO_CHECK_EVAL("new VisualEffect()", "threw: unconstructable");
	OO_CHECK_EVAL("Object.getPrototypeOf(VisualEffect.prototype) === Entity.prototype", "true");
	OO_CHECK_EVAL("effect instanceof VisualEffect", "true");
}


OO_TEST(subEntitiesForScript)
{
	SetUpContext();
	// None before the first subentity, then the visual-effect subentities, in
  // order.
	OO_CHECK(OOJSVisualEffectSubEntitiesForScript(sEffectPart).empty());
	sEffectPart->_subs = std::vector<oo::EntityHold>{ oo::EntityHold(sSub->_cxxEntity.get()) };
	std::vector<oo::EntityHold> subs = OOJSVisualEffectSubEntitiesForScript(sEffectPart);
	OO_CHECK_EQ(subs.size(), 1u);
	OO_CHECK(subs.size() == 1 && subs[0].get() == sSub->_cxxEntity.get());
	OO_CHECK_EVAL("effect.subEntities", "[OOVisualEffectEntity]");
	sEffectPart->_subs = std::nullopt;
	OO_CHECK_EVAL("effect.subEntities", "null");
}


OO_TEST(properties)
{
	SetUpContext();
	OO_CHECK_EVAL("effect.beaconCode", "null");
	OO_CHECK_EVAL("effect.beaconLabel", "Label");
	OO_CHECK_EVAL("effect.dataKey", "test-effect");
	OO_CHECK_EVAL("effect.isBreakPattern", "false");
	OO_CHECK_EVAL("effect.vectorForward + ';' + effect.vectorRight + ';' + effect.vectorUp", "0,0,1;1,0,0;0,1,0");
	OO_CHECK_EVAL("[effect.scaleX, effect.scaleY, effect.scaleZ].join(' ')", "1 2 4");
	OO_CHECK_EVAL("effect.scannerDisplayColor1", "1,0.5,0.25,1");
	OO_CHECK_EVAL("effect.scannerDisplayColor2", "null");
	OO_CHECK_EVAL("effect.hullHeatLevel", "0.5");
	OO_CHECK_EVAL("effect.shaderFloat1 + ' ' + effect.shaderFloat2", "1.5 0");
	OO_CHECK_EVAL("effect.shaderInt1 + ' ' + effect.shaderInt2", "0 -3");
	OO_CHECK_EVAL("effect.shaderVector1 + ';' + effect.shaderVector2", "1,2,3;0,0,0");
	OO_CHECK_EVAL("effect.script", "null");
	sEffectPart->_script = oo::makeRef<OOScript>().leakRef();
	OO_CHECK_EVAL("effect.script", "[OOObject]");
	sEffectPart->_script->release();
	sEffectPart->_script = nullptr;
	OO_CHECK_EVAL("JSON.stringify(effect.scriptInfo)", "{\"note\":\"hello\"}");
	OO_CHECK_EVAL("Object.keys(VisualEffect.prototype).join()", "beaconCode,beaconLabel,dataKey,isBreakPattern,scaleX,scaleY,scaleZ,scannerDisplayColor1,scannerDisplayColor2,hullHeatLevel,script,scriptInfo,shaderFloat1,shaderFloat2,shaderInt1,shaderInt2,shaderVector1,shaderVector2,subEntities,vectorForward,vectorRight,vectorUp");
	// Read-only.
	OO_CHECK_EVAL("(function () { effect.dataKey = 'x'; return effect.dataKey; })()", "test-effect");
}


OO_TEST(setters)
{
	SetUpContext();
	OO_CHECK_EVAL("(function () { effect.beaconLabel = 'Other'; return effect.beaconLabel; })()", "Other");
	OO_CHECK_EVAL("(function () { effect.beaconLabel = null; return effect.beaconLabel; })()", "threw: bad property value");
	OO_CHECK_EVAL("(function () { effect.isBreakPattern = 1; return effect.isBreakPattern; })()", "true");
	OO_CHECK_EVAL("(function () { effect.isBreakPattern = ''; return effect.isBreakPattern; })()", "false");
	OO_CHECK_EVAL("(function () { effect.scaleX = 3; return effect.scaleX; })()", "3");
	OO_CHECK_EVAL("(function () { effect.scaleY = 0; return effect.scaleY; })()", "threw: bad property value");
	OO_CHECK_EVAL("(function () { effect.scaleZ = -1; return effect.scaleZ; })()", "threw: bad property value");
	OO_CHECK_EVAL("(function () { effect.hullHeatLevel = 0.25; return effect.hullHeatLevel; })()", "0.25");
	OO_CHECK_EVAL("(function () { effect.shaderFloat2 = 2.5; return effect.shaderFloat2; })()", "2.5");
	OO_CHECK_EVAL("(function () { effect.shaderInt1 = 7.9; return effect.shaderInt1; })()", "8");
	OO_CHECK_EVAL("(function () { effect.shaderVector2 = [4, 5, 6]; return effect.shaderVector2; })()", "4,5,6");
	OO_CHECK_EVAL("(function () { effect.shaderVector2 = 'x'; return effect.shaderVector2; })()", "threw: bad property value");
	OO_CHECK_EVAL("(function () { effect.scannerDisplayColor2 = [0, 1, 0]; return effect.scannerDisplayColor2; })()", "0,1,0,1");
	OO_CHECK_EVAL("(function () { effect.scannerDisplayColor2 = null; return effect.scannerDisplayColor2; })()", "null");
	OO_CHECK_EVAL("(function () { effect.scannerDisplayColor1 = 'not a colour'; return effect.scannerDisplayColor1; })()", "threw: bad property value");
	OO_CHECK_EVAL("(function () { effect.subEntities = []; return effect.subEntities; })()", "null");
	sEffectPart->_scaleX = 1;
	sEffectPart->_hullHeatLevel = 0.5f;
}


OO_TEST(beacons)
{
	SetUpContext();
	sGame->_added = sGame->_cleared = 0;
	// Setting a code on a non-beacon registers it with the universe.
	OO_CHECK_EVAL("(function () { effect.beaconCode = 'B'; return effect.beaconCode; })()", "B");
	OO_CHECK_EQ(sGame->_added, 1);
	// Changing the code of a beacon does not.
	OO_CHECK_EVAL("(function () { effect.beaconCode = 'C'; return effect.beaconCode; })()", "C");
	OO_CHECK_EQ(sGame->_added, 1);
	// Clearing it clears the beacon, and resets the compass if the player was aiming at it.
	sGame->_nextBeacon = sEffect;
	sGame->_compassMode = -1;
	OO_CHECK_EVAL("(function () { effect.beaconCode = ''; return effect.beaconCode; })()", "null");
	OO_CHECK_EQ(sGame->_cleared, 1);
	OO_CHECK_EQ(sGame->_compassMode, static_cast<int>(OOCompassMode::kPlanet));
	// Clearing a non-beacon does nothing.
	sGame->_compassMode = -1;
	OO_CHECK_EVAL("(function () { effect.beaconCode = null; return effect.beaconCode; })()", "null");
	OO_CHECK_EQ(sGame->_cleared, 1);
	OO_CHECK_EQ(sGame->_compassMode, -1);
	sGame->_nextBeacon = nullptr;
}


OO_TEST(methods)
{
	SetUpContext();
	// remove(): a subentity leaves its owner, anything else leaves the universe.
	OO_CHECK_EVAL("sub.remove()", "undefined");
	OO_CHECK(sEffectPart->_removedSub == sSub);
	OO_CHECK_EQ(sEffectPart->_removed, 0);
	OO_CHECK_EVAL("effect.remove()", "undefined");
	OO_CHECK_EQ(sEffectPart->_removed, 1);
	// scale(): all three scales; a missing or non-positive factor is an error.
	// It answers undefined (#768's native returns it; SpiderMonkey's left the callee in the result
	// slot).
	OO_CHECK_EVAL("typeof effect.scale(2)", "undefined");
	OO_CHECK_EVAL("[effect.scaleX, effect.scaleY, effect.scaleZ].join(' ')", "2 2 2");
	OO_CHECK_EVAL("effect.scale(0)", "threw: bad arguments: VisualEffect.scale(1) - / scale factor must be positive");
	OO_CHECK_EVAL("effect.scale()", "threw: bad arguments: VisualEffect.scale(0) - / scale factor needed");
	// restoreSubEntities(): true if there are more than before.
	sEffectPart->_subsAfterSetUp = 2;
	OO_CHECK_EVAL("effect.restoreSubEntities()", "true");
	OO_CHECK_EVAL("effect.subEntities.length", "2");
	OO_CHECK_EVAL("effect.restoreSubEntities()", "false");
	sEffectPart->_subsAfterSetUp = 0;
	sEffectPart->_subs = std::nullopt;
	OO_CHECK_EQ(sLimiterPauses, 0);
}


OO_TEST(materials)
{
	SetUpContext();
	// No mesh: empty dictionaries.
	OO_CHECK_EVAL("JSON.stringify(effect.getMaterials()) + JSON.stringify(effect.getShaders())", "{}{}");
	// setMaterials() makes a mesh from the effect's model with the new materials and the old shaders.
	sMeshesMade = 0;
	OO_CHECK_EVAL("effect.setMaterials({key: 'm'})", "true");
	OO_CHECK_EQ(sMeshesMade, 1);
	OO_CHECK_EQ(sMeshName, std::string("effect.dat"));
	OO_CHECK(!sMeshCacheKey.has_value());
	OO_CHECK(sMeshSmooth);
	OO_CHECK(sMeshTarget == sEffect);
	OO_CHECK_EQ(oo::DescriptionOf(sMeshMacros), oo::DescriptionOf(oo::PList(oo::PList::Dict{ { "OO_TEST", oo::PList(1.0) } })));
	OO_CHECK_EVAL("JSON.stringify(effect.getMaterials())", "{\"key\":\"m\"}");
	OO_CHECK_EVAL("JSON.stringify(effect.getShaders())", "{}");
	// setShaders() keeps the materials.
	OO_CHECK_EVAL("effect.setShaders({key: 's'})", "true");
	OO_CHECK_EVAL("JSON.stringify(effect.getMaterials()) + JSON.stringify(effect.getShaders())", "{\"key\":\"m\"}{\"key\":\"s\"}");
	// Both at once.
	OO_CHECK_EVAL("effect.setMaterials({key: 'm2'}, {key: 's2'})", "true");
	OO_CHECK_EVAL("JSON.stringify(effect.getMaterials()) + JSON.stringify(effect.getShaders())", "{\"key\":\"m2\"}{\"key\":\"s2\"}");
	// A second argument that is not an object is ignored, with a warning.
	sLastWarning.clear();
	OO_CHECK_EVAL("effect.setMaterials({key: 'm3'}, 5)", "true");
	OO_CHECK_EQ(sLastWarning, std::string("VisualEffect.setMaterials: expected object as second parameter instead of '5'."));
	OO_CHECK_EVAL("JSON.stringify(effect.getShaders())", "{\"key\":\"s2\"}");
	// Bad first arguments.
	OO_CHECK_EVAL("effect.setMaterials(null)", "false");
	OO_CHECK_EQ(sLastWarning, std::string("VisualEffect.setMaterials: expected object instead of 'null'."));
	OO_CHECK_EVAL("effect.setShaders('x')", "false");
	OO_CHECK_EQ(sLastWarning, std::string("VisualEffect.setShaders: expected object instead of 'x'."));
	OO_CHECK_EVAL("effect.setMaterials()", "threw: bad arguments: VisualEffect.setMaterials(0) - / parameter object");
	// A mesh that cannot be made leaves the old one.
	oo::PList::Dict effectInfo;
	effectInfo["model"] = oo::PList(std::string("nomesh.dat"));
	sEffectPart->_effectInfo = oo::PList(std::move(effectInfo));
	OO_CHECK_EVAL("effect.setMaterials({key: 'm4'})", "false");
	OO_CHECK(!sMeshSmooth);
	OO_CHECK_EVAL("JSON.stringify(effect.getMaterials())", "{\"key\":\"m3\"}");
	OO_CHECK_EQ(sLimiterPauses, 0);
}


OO_TEST(otherObjects)
{
	SetUpContext();
	// A non-effect entity is refused without a JS error; a non-entity is an error.
	OO_CHECK_EVAL("Object.getOwnPropertyDescriptor(VisualEffect.prototype, 'dataKey').get.call(plainEntity)", "<evaluation failed>");
	OO_CHECK_EVAL("VisualEffect.prototype.remove.call(plainEntity)", "<evaluation failed>");
	OO_CHECK_EVAL("VisualEffect.prototype.remove.call({})", "threw: Native method expected Entity, got [object Object].");
	OO_CHECK_EVAL("VisualEffect.prototype.dataKey", "<evaluation failed>");	// the prototype is not an effect
	// A stale effect: methods do nothing.
	gOOJSPlayerIfStale = sEffectPart;	// its C++ part
	sEffectPart->_removed = 0;
	OO_CHECK_EVAL("effect.remove()", "undefined");
	OO_CHECK_EQ(sEffectPart->_removed, 0);
	OO_CHECK_EVAL("effect.getMaterials()", "undefined");
	gOOJSPlayerIfStale = nullptr;
}


OO_TEST(nativeExceptions)
{
	SetUpContext();
	// The property getter is a native (OOJS_NATIVE_ENTER): a raise from the entity is a JS error,
	// and so is a C++ exception.
	sEffectPart->_hullHeatLevel = 99;
	OO_CHECK_EVAL("effect.hullHeatLevel", "threw: Native exception: heat boom");
	sEffectPart->_hullHeatLevel = 98;
	OO_CHECK_EVAL("effect.hullHeatLevel", "threw: Native exception: cxx boom");
	sEffectPart->_hullHeatLevel = 0.5f;
	OO_CHECK_EVAL("effect.hullHeatLevel", "0.5");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
}


OO_TEST_MAIN()
