/*	test_OOJSShipGroup.mm
	Unit tests for the ShipGroup JS binding (src/Core/Scripting/OOJSShipGroup.h/.mm) and the JS glue
	of OOShipGroup: bead oo-n64m, converted the way bead oo-ppc converted OOJSVector (proposed
	ADR-0056 amendments oo-ppc and oo-ykoy); the group's façade was deleted by bead oo-9ht.19, so a
	group reaches the engine as a PList Object node holding the C++ group, and the stand-in ship
	holds its groups as oo::Ref where it held the autoreleased façades.

	As test_OOJSWormhole.mm does (amendment oo-ykoy, item 4), it runs the JS class in a real
	context on the game's own façade backend (ooscript/JSEngine_quickjs.cpp), links the game's own
	objects for the binding, its bridge, the engine's exception translator
	(OOJSEngineNativeWrappers.mm) and OOShipGroup (a converted class, reached through its façade,
	as test_OOShipGroup.mm links it), and stands in for ShipEntity (a weakly referenced object
	answering only the selectors the binding and the group send, with a JS object of its own; a C++
	ship under a stand-in root object since bead oo-9ht.144),
	OONull, and the engine functions the binding links against, with the engine headers' linkage.
	The engine's native-object conversion asks the object for its JS value, as the engine does, so
	a group's JS object is the one the category makes. The expectations were written against the
	Objective-C file and run on it first; they pin the JS-visible behaviour (the constructor, the
	four properties both ways, addShip() with its escort rules, removeShip(), containsShip(), a
	non-group, a native's exception) and what the category answers the engine (one JS object per
	group until the engine clears it). Run: bash tools/check-core-tests.sh
*/

#include "OOShipGroup.h"
#include "ooscript/JSEngine.hpp"
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#include "OODescription.h"
#include "OOObjCPList.h"
#include "EntityPListForeign.h"	// an entity's node (bead oo-dpyk8)


// MARK: The classes, as far as the binding sees them ----------------------------------------------

/*	A ship: the group it is in, the group it leads as escorts, and whether it takes an escort. A
	ship named "boom" raises from acceptAsEscort(), so the test sees what an exception under a
	native becomes. C++ since bead oo-9ht.144 deleted the Objective-C ship this stood in for: a
	ship's object is the root's (a weakly referenced object with a JS object of its own), which
	holds the C++ part (oo::ToCxx reads it) and which TestObjectOf answers for it; declared as
	Entity.h and ShipEntity.h declare them (the test imports neither).
*/
class TestEntityObject;

class Entity : public oo::RefCounted
{
public:
	virtual ~Entity();

	::TestEntityObject *_object = nullptr;	// its object (not retained)
};

class ShipEntity : public Entity
{
public:
	::OOShipGroup *group();
	void setGroup(::OOShipGroup *group);
	void setOwner(Entity *who_owns_entity);
	::OOShipGroup *escortGroup();
	bool acceptAsEscort(::ShipEntity *other_ship);

	std::string _name;
	oo::Ref<OOShipGroup> _group;
	oo::Ref<OOShipGroup> _escortGroup;
	BOOL _acceptsEscorts = NO;
	int _accepted = 0;
};

// The ship's object. C++ since bead oo-4aq6a.13 (it was rooted on the Objective-C root class OOObject,
// which Phase 4 deletes): its selectors are members of the same names; the JS slot holds it (not
// retained, as it held the Objective-C object).
class TestEntityObject final : public oo::RefCounted
{
public:
	const char *className() const  { return "Entity"; }	// its Objective-C class's runtime name
	std::optional<std::string> cxx_descriptionComponents();
	ooscript::Value oo_jsValueInContext(ooscript::Context context);

	oo::Ref<Entity> _cxxEntity;
	std::string _name;
	ooscript::Object _jsSelf = nullptr;
};

// The one null (OOJavaScriptEngine.h; a C++ class since bead oo-wdqw1 deleted its facade), declared
// with the header's names and signatures but not its class: its own property-list node's object.
class OONull : public oo::PListForeign
{
public:
	static OONull *null();
	std::string className() const override;
	std::string description() const override;
};



#include "OOJSShipGroup.h"

#include "oo_test.hpp"

#include <cstdarg>
#include <cstdint>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>


namespace {
ooscript::Context sContext;
ooscript::ClassDef sFakeShipClass = { "Ship", ooscript::ClassFlag::HasPrivate };
ooscript::Object sFakeShipPrototype = nullptr;
}


Entity::~Entity() = default;
OOShipGroup *ShipEntity::group()  { return _group.get(); }
void ShipEntity::setGroup(OOShipGroup *group)  { _group = oo::Ref<OOShipGroup>(group); }
void ShipEntity::setOwner(Entity *who_owns_entity)  { (void)who_owns_entity; }
OOShipGroup *ShipEntity::escortGroup()  { return _escortGroup.get(); }

bool ShipEntity::acceptAsEscort(::ShipEntity *other_ship)
{
	if (other_ship->_name == "boom")  OORaiseException(OOInvalidArgumentException, "escort %s", "boom");
	if (!_acceptsEscorts)  return NO;
	_accepted++;
	return YES;
}

// Entity+ObjCBridge.mm's oo::ToObjC (which the test does not link) until bead oo-4aq6a.13.
::TestEntityObject *TestObjectOf(Entity *entity)  { return entity != nullptr ? entity->_object : nullptr; }
#define OO_ENTITY_HELPERS_STAND_IN_CXX
#include "EntityHelpersStandIn.h"	// EntityHelpers.mm's, on the test's objects (bead oo-dpyk8)


std::optional<std::string> TestEntityObject::cxx_descriptionComponents()  { return _name; }

ooscript::Value TestEntityObject::oo_jsValueInContext(ooscript::Context context)
{
	if (_jsSelf == nullptr)
	{
		_jsSelf = ooscript::newObject(context, &sFakeShipClass, sFakeShipPrototype, nullptr);
		ooscript::setPrivate(context, _jsSelf, static_cast<oo::RefCounted *>(this));
	}
	return ooscript::objectValue(_jsSelf);
}


OONull *OONull::null()
{
	static OONull *null = oo::makeRef<OONull>().leakRef();
	return null;
}

std::string OONull::className() const	{ return "OONull"; }
std::string OONull::description() const	{ return "<null>"; }


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

void cxx_OOJSReportWarningForCaller(ooscript::Context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	sLastWarning = scriptClass.value_or("-") + "." + function.value_or("-") + ": " + oo::str::vformat(format, args);
	va_end(args);
}


void cxx_OOJSReportBadArguments(ooscript::Context context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, unsigned argc, ooscript::Value *, const std::optional<std::string> &message, const std::optional<std::string> &expectedArgsDescription)
{
	cxx_OOJSReportError(context, "bad arguments: %s.%s(%u) %s / %s", scriptClass.value_or("-").c_str(), function.value_or("-").c_str(), argc, message.value_or("-").c_str(), expectedArgsDescription.value_or("-").c_str());
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


std::optional<std::string> cxx_OOStringFromJSValueEvenIfNull(ooscript::Context context, ooscript::Value value)
{
	if (ooscript::isNull(value))  return std::string("null");
	if (ooscript::isUndefined(value))  return std::string("undefined");
	return cxx_OOStringFromJSValue(context, value);
}




// A property list as JavaScript, as far as the binding hands one over: null, a string, a number,
// an object (its JS value; OONull is null), or an array of those.
ooscript::Value OOJSValueFromPList(ooscript::Context context, const oo::PList &plist)
{
	if (const std::string *str = plist.getIf<std::string>())
	{
		ooscript::String js = ooscript::newStringCopyN(context, str->data(), str->size());
		return js != nullptr ? ooscript::stringValue(js) : ooscript::nullValue();
	}
	if (plist.isNumber())  return ooscript::numberValue(plist.doubleValue());
	if (const oo::PList::Object *node = plist.getIf<oo::PList::Object>())	// a C++ object that is its own JS glue, as the engine asks it
	{
		if (OOJSPrivateObject *glue = dynamic_cast<OOJSPrivateObject *>(node->get()))  return OOJSValueFromCxxObject(context, glue);
		if (dynamic_cast<OONull *>(node->get()) != nullptr)  return ooscript::nullValue();	// OONull is null
	}
	if (Entity *entity = oo::EntityIn(plist))	// an entity's node: its object's value (bead oo-dpyk8), as OOJSValueFromNativeObject() gave it
	{
		::TestEntityObject *object = TestObjectOf(entity);
		return object != nullptr ? object->oo_jsValueInContext(context) : ooscript::nullValue();
	}
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
std::map<ooscript::ClassDef *, int> sConverters;
int sFinalized = 0;
} // namespace


extern "C" {

void OOJSReportBadPropertySelector(ooscript::Context context, ooscript::Object, ooscript::PropertyId, ooscript::PropertySpec *)
{
	cxx_OOJSReportError(context, "bad property selector");
}


void OOJSReportBadPropertyValue(ooscript::Context context, ooscript::Object, ooscript::PropertyId, ooscript::PropertySpec *, ooscript::Value)
{
	cxx_OOJSReportError(context, "bad property value");
}


void OOJSRegisterObjectConverter(ooscript::ClassDef *theClass, oo::PList (*)(ooscript::Context, ooscript::Object))
{
	sConverters[theClass]++;
}






// The JS class check of the engine's C++ getter (OOJSPrivateObject.cpp, linked since bead
// oo-6symp.1, whose slot holds the C++ group): no subclass of ShipGroup is registered.
BOOL OOJSIsSubclass(ooscript::ClassDef *putativeSubclass, ooscript::ClassDef *superclass)
{
	return putativeSubclass == superclass;
}


// (No longer reached for a group, whose toString() is OOJSCxxObjectWrapperToString.)
// A link stub (bead oo-dbz.4): unreached, the slot holding the C++ object since bead oo-4aq6a.6; it
// described the slot as an Objective-C object, which oo::DescriptionOf(id) did until libobjc2 went.
bool OOJSObjectWrapperToString(ooscript::Context, ooscript::CallArgs &)
{
	std::abort();
}


// The engine's wrapper finalizer: the slot's C++ object (src's OOJSObjectWrapperFinalize since bead
// oo-4aq6a.6.1) is released and the slot emptied. (Unreached: a group's finalizer is the C++ one.)
void OOJSObjectWrapperFinalize(ooscript::Context context, ooscript::Object object)
{
	oo::RefCounted *native = static_cast<oo::RefCounted *>(ooscript::getPrivate(context, object));
	if (native != nullptr)
	{
		ooscript::setPrivate(context, object, nullptr);
		native->release();
		sFinalized++;
	}
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


// OOJSEntity.mm's (not linked): the C++ entity of an entity's JS object, null for any other value,
// with no error (OOJSNativeObjectOfClassFromJSValue(context, value, [TestEntityObject class]) until bead
// oo-9ht.39.3, whose stand-in this was). The test's ships keep their object in the slot, as the
// game's slot held the object's weak reference before.
Entity *OOJSEntityFromJSValue(ooscript::Context context, ooscript::Value value)
{
	if (!ooscript::isObject(value) || ooscript::isNull(value))  return nullptr;
	// The slot holds an oo::RefCounted: a ship's object, or a group (bead oo-4aq6a.13: the class
	// check, -isKindOfClass: until then, is the C++ one).
	TestEntityObject *entity = dynamic_cast<TestEntityObject *>(static_cast<oo::RefCounted *>(ooscript::getPrivate(context, ooscript::toObject(value))));
	return entity != nullptr ? entity->_cxxEntity.get() : nullptr;
}


oo::PList OOJSBasicPrivateObjectConverter(ooscript::Context, ooscript::Object)
{
	return oo::PList();
}


// MARK: The context -------------------------------------------------------------------------------

namespace {

ooscript::Runtime sRuntime;
ooscript::Object sGlobal;


void Define(const char *name, ooscript::Value value)
{
	ooscript::setProperty(sContext, sGlobal, name, &value);
}


// A ship and its object (kept for the life of the test), defined by name.
ShipEntity *NewShip(const char *name)
{
	::TestEntityObject *object = oo::makeRef<::TestEntityObject>().leakRef();
	oo::Ref<ShipEntity> ship = oo::makeRef<ShipEntity>();
	ship->_object = object;
	ship->_name = name;
	object->_cxxEntity = ship;
	object->_name = name;
	Define(name, object->oo_jsValueInContext(sContext));
	return ship.get();
}


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = ooscript::newRuntime(8u * 1024u * 1024u);
	sContext = ooscript::newContext(sRuntime, 8192);
	ooscript::beginRequest(sContext);
	sGlobal = ooscript::getGlobalObject(sContext);
	ooscript::initStandardClasses(sContext, sGlobal);
	sFakeShipPrototype = ooscript::initClass(sContext, sGlobal, nullptr, &sFakeShipClass, nullptr, 0, nullptr, nullptr, nullptr, nullptr);
	InitOOJSShipGroup(sContext, sGlobal);
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
	OO_CHECK_EQ(sConverters.size(), 1u);
	OO_CHECK_EVAL("typeof ShipGroup", "function");
	OO_CHECK_EVAL("Object.keys(ShipGroup.prototype).join()", "count,leader,name,ships");
	OO_CHECK_EVAL("ShipGroup()", "threw: ShipGroup() cannot be called as a function, it must be used as a constructor (as in new ShipGroup(...)).");
	OO_CHECK_EVAL("new ShipGroup() instanceof ShipGroup", "true");
}


OO_TEST(category)
{
	SetUpContext();
	// One JS object per group, made on first use; the engine's finalizer clears it.
	oo::Ref<OOShipGroup> group = OOShipGroup::groupWithName(std::string("cat"));
	ooscript::Value first = group->jsValueInContext(sContext);
	OO_CHECK(ooscript::isObject(first));
	OO_CHECK(ooscript::toObject(group->jsValueInContext(sContext)) == ooscript::toObject(first));
	OO_CHECK(static_cast<oo::RefCounted *>(ooscript::getPrivate(sContext, ooscript::toObject(first))) == static_cast<oo::RefCounted *>(group.get()));
	Define("catGroup", first);
	OO_CHECK_EVAL("catGroup.name", "cat");
	// Clearing with another object leaves it; clearing with its own makes the next one new.
	group->clearJSSelf(nullptr);
	OO_CHECK(ooscript::toObject(group->jsValueInContext(sContext)) == ooscript::toObject(first));
	group->clearJSSelf(ooscript::toObject(first));
	ooscript::Value second = group->jsValueInContext(sContext);
	OO_CHECK(ooscript::isObject(second) && ooscript::toObject(second) != ooscript::toObject(first));
}


OO_TEST(constructor)
{
	SetUpContext();
	NewShip("alpha");
	OO_CHECK_EVAL("new ShipGroup().name", "null");
	OO_CHECK_EVAL("new ShipGroup().count", "0");
	OO_CHECK_EVAL("new ShipGroup('wing').name", "wing");
	OO_CHECK_EVAL("(function () { var g = new ShipGroup('wing', alpha); return g.leader === alpha && g.count === 1 && g.ships[0] === alpha; })()", "true");
	OO_CHECK_EVAL("new ShipGroup('wing', null).leader", "null");
	OO_CHECK_EVAL("new ShipGroup(5)", "threw: bad arguments: -.ShipGroup()(1) Could not create ShipGroup / group name");
	OO_CHECK_EVAL("new ShipGroup('wing', {})", "threw: bad arguments: -.ShipGroup()(1) Could not create ShipGroup / ship");
	OO_CHECK_EVAL("String(new ShipGroup('wing')).replace(/0x[0-9a-f]+/, 'ADDR')", "[OOShipGroup \"wing\", 0 ships]");
}


OO_TEST(properties)
{
	SetUpContext();
	NewShip("beta");
	NewShip("gamma");
	OO_CHECK_EVAL("(function () { var g = new ShipGroup('g'); g.name = 'h'; return g.name; })()", "h");
	OO_CHECK_EVAL("(function () { var g = new ShipGroup('g'); g.name = null; return g.name; })()", "null");
	OO_CHECK_EVAL("(function () { var g = new ShipGroup('g'); g.name = 3; return g.name; })()", "3");
	OO_CHECK_EVAL("(function () { var g = new ShipGroup('g'); g.leader = beta; return g.leader === beta && g.count; })()", "1");
	OO_CHECK_EVAL("(function () { var g = new ShipGroup('g', beta); g.leader = null; return String(g.leader) + ' ' + g.count; })()", "null 1");
	OO_CHECK_EVAL("(function () { var g = new ShipGroup('g'); g.leader = 'x'; return g.leader; })()", "threw: bad property value");
	OO_CHECK_EVAL("(function () { var g = new ShipGroup('g'); g.addShip(beta); g.addShip(gamma); return g.ships.length + ' ' + g.count; })()", "2 2");
	// Read-only.
	OO_CHECK_EVAL("(function () { var g = new ShipGroup('g'); g.count = 5; return g.count; })()", "0");
	OO_CHECK_EVAL("(function () { var g = new ShipGroup('g'); g.ships = [beta]; return g.ships.length; })()", "0");
}


OO_TEST(membership)
{
	SetUpContext();
	NewShip("delta");
	NewShip("epsilon");
	OO_CHECK_EVAL("(function () { var g = new ShipGroup('m'); return [g.addShip(delta), g.containsShip(delta), g.containsShip(epsilon), g.count].join(); })()", "true,true,false,1");
	OO_CHECK_EVAL("(function () { var g = new ShipGroup('m'); g.addShip(delta); return [g.addShip(delta), g.count].join(); })()", ",1");	// already there: nothing to do
	OO_CHECK_EVAL("(function () { var g = new ShipGroup('m'); g.addShip(delta); return [g.removeShip(delta), g.containsShip(delta), g.count].join(); })()", "true,false,0");
	OO_CHECK_EVAL("(function () { var g = new ShipGroup('m'); return g.removeShip(epsilon); })()", "false");
	// null is accepted and does nothing; anything else is an error.
	OO_CHECK_EVAL("new ShipGroup('m').addShip(null)", "undefined");
	OO_CHECK_EVAL("new ShipGroup('m').removeShip(null)", "undefined");
	OO_CHECK_EVAL("new ShipGroup('m').containsShip(null)", "false");
	OO_CHECK_EVAL("new ShipGroup('m').addShip()", "threw: bad arguments: ShipGroup.addShip(0) - / ship");
	OO_CHECK_EVAL("new ShipGroup('m').removeShip({})", "threw: bad arguments: ShipGroup.removeShip(1) - / ship");
	OO_CHECK_EVAL("new ShipGroup('m').containsShip('x')", "threw: bad arguments: ShipGroup.containsShip(1) - / ship");
}


OO_TEST(escorts)
{
	SetUpContext();
	ShipEntity *leader = NewShip("leader");
	ShipEntity *escort = NewShip("escort");
	ShipEntity *other = NewShip("otherLeader");
	ShipEntity *taken = NewShip("taken");
	// The leader's escort group with escorts already: the new ship must be accepted as an escort.
	oo::Ref<OOShipGroup> escorts = OOShipGroup::groupWithName(std::string("escorts"), leader);
	escorts->addShip(NewShip("first"));
	leader->_escortGroup = escorts;
	leader->_group = escorts;
	Define("escorts", escorts->jsValueInContext(sContext));
	leader->_acceptsEscorts = NO;
	OO_CHECK_EVAL("[escorts.addShip(escort), escorts.containsShip(escort)].join()", "false,false");
	leader->_acceptsEscorts = YES;
	OO_CHECK_EVAL("[escorts.addShip(escort), escorts.containsShip(escort)].join()", "true,true");
	OO_CHECK_EQ(leader->_accepted, 1);
	// A ship that already escorts someone else is refused, with a warning.
	oo::Ref<OOShipGroup> otherEscorts = OOShipGroup::groupWithName(std::string("other"), other);
	otherEscorts->addShip(taken);
	other->_escortGroup = otherEscorts;
	taken->_group = otherEscorts;
	sLastWarning.clear();
	OO_CHECK_EVAL("escorts.addShip(taken)", "false");
	OO_CHECK_EQ(sLastWarning, "ShipGroup.addShip: Ship " + TestEntityObjectDescription(TestObjectOf(taken), true) + " cannot be assigned to two escort groups, ignoring.");
	OO_CHECK(TestEntityObjectDescription(TestObjectOf(taken), true).find("{taken}") != std::string::npos);
	// A lone leader whose escort group is its own group gets a new group, and the ship joins that.
	ShipEntity *lone = NewShip("lone");
	oo::Ref<OOShipGroup> loneGroup = OOShipGroup::groupWithName(std::string("alone"), lone);
	lone->_escortGroup = loneGroup;
	lone->_group = loneGroup;
	Define("loneGroup", loneGroup->jsValueInContext(sContext));
	OO_CHECK_EVAL("[loneGroup.addShip(escort), loneGroup.containsShip(escort)].join()", "true,false");
	OO_CHECK(lone->_group != loneGroup && lone->_group->containsShip(escort));
	OO_CHECK(lone->_group->name() == std::optional<std::string>("ship group"));
	// A lone leader with a group of its own: it is asked to accept the escort.
	ShipEntity *custom = NewShip("custom");
	oo::Ref<OOShipGroup> customGroup = OOShipGroup::groupWithName(std::string("custom"), custom);
	custom->_escortGroup = customGroup;
	custom->_group = OOShipGroup::groupWithName(std::string("elsewhere"));
	Define("customGroup", customGroup->jsValueInContext(sContext));
	custom->_acceptsEscorts = NO;
	OO_CHECK_EVAL("customGroup.addShip(escort)", "false");
	custom->_acceptsEscorts = YES;
	OO_CHECK_EVAL("customGroup.addShip(escort)", "true");
	OO_CHECK_EQ(custom->_accepted, 1);
}


OO_TEST(otherObjects)
{
	SetUpContext();
	NewShip("zeta");
	OO_CHECK_EVAL("ShipGroup.prototype.addShip.call(zeta, zeta)", "threw: Native method expected ShipGroup, got [object Ship].");
	OO_CHECK_EVAL("Object.getOwnPropertyDescriptor(ShipGroup.prototype, 'count').get.call({})", "threw: Native method expected ShipGroup, got [object Object].");
	OO_CHECK_EVAL("ShipGroup.prototype.count", "0");	// the prototype has no group: a message to nil
	OO_CHECK_EVAL("ShipGroup.prototype.ships.length", "0");
	OO_CHECK_EVAL("ShipGroup.prototype.name", "null");
}


OO_TEST(nativeExceptions)
{
	SetUpContext();
	ShipEntity *chief = NewShip("chief");
	NewShip("boom");
	oo::Ref<OOShipGroup> group = OOShipGroup::groupWithName(std::string("ex"), chief);
	group->addShip(NewShip("wingman"));
	chief->_escortGroup = group;
	chief->_group = group;
	Define("exGroup", group->jsValueInContext(sContext));
	OO_CHECK_EVAL("exGroup.addShip(boom)", "threw: Native exception: escort boom");
	OO_CHECK_EVAL("exGroup.count", "2");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
	OO_CHECK(ooscript::isInRequest(sContext));
}


OO_TEST_MAIN()
