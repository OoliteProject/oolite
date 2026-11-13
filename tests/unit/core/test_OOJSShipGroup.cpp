/*	test_OOJSShipGroup.mm
	Unit tests for the ShipGroup JS binding (src/Core/Scripting/OOJSShipGroup.h/.mm) and the JS glue
	of OOShipGroup: a group reaches the engine as a PList Object node holding the C++ group, and the
	stand-in ship holds its groups as a std::shared_ptr.

	As test_OOJSWormhole.mm does, it runs the JS class in a real QuickJS-ng context, links the
	game's own objects for the binding, the engine's private-slot glue (OOJSPrivateObject.cpp), its
	class registry (OOJSClasses.mm), its exception translator (OOJSEngineNativeWrappers.mm) and
	OOShipGroup (a converted class, as test_OOShipGroup.mm links it), and stands in for ShipEntity
	(a weakly referenced object answering only the selectors the binding and the group send, with a
	JS object of its own; a C++ ship under a stand-in root object), OONull, and the engine functions
	the binding links against, with the engine headers' linkage. The engine's native-object
	conversion asks the object for its JS value, as the engine does, so a group's JS object is the
	one the category makes. The expectations pin the JS-visible behaviour (the constructor, the
	four properties both ways,
	addShip() with its escort rules, removeShip(), containsShip(), a non-group, a native's
	exception) and what the category answers the engine (one JS object per group until the engine
	clears it). Run: tests/run.sh unit
*/

#include "OOShipGroup.h"
#include <quickjs.h>
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#include <cstddef>
#include <cstdint>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include "EntityPListForeign.h"	// an entity's node
#include "EntityManualRefs.h"  // the tests' manual references (T096)


// MARK: The classes, as far as the binding sees them ----------------------------------------------

/*	A ship: the group it is in, the group it leads as escorts, and whether it takes an escort. A
	ship named "boom" raises from acceptAsEscort(), so the test sees what an exception under a
	native becomes. A ship's object is
	the root's (a weakly referenced object with a JS object of its own), which holds the C++ part
	(oo::ToCxx reads it) and which TestObjectOf answers for it; declared as Entity.h and ShipEntity.h
	declare them (the test imports neither). The object holds one reference to its JS object,
	which lives as long as it does; the JS object's slot holds the object (not retained).
*/
class TestEntityObject;

class Entity : public oo::Object
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
	std::shared_ptr<OOShipGroup> _group;
	std::shared_ptr<OOShipGroup> _escortGroup;
	bool _acceptsEscorts = false;
	int _accepted = 0;
};

// The ship's object. Its selectors are members of the same names; the JS slot
// holds it (not retained).
class TestEntityObject final : public oo::Object
{
public:
	const char *className() const  { return "Entity"; }	// the class's runtime name
	std::optional<std::string> descriptionComponents();
	JSValue oo_jsValueInContext(JSContext *context);	// owned by the caller

	std::shared_ptr<Entity> _cxxEntity;
	std::string _name;
	JSValue _jsSelf = JS_UNDEFINED;	// Not an object until made; owned.
};

// The one null (OOJavaScriptEngine.h), declared with the header's names and
// signatures but not its class: its own property-list node's object.
class OONull : public oo::PListForeign
{
public:
	static OONull *null();
	std::string className() const override;
	std::string description() const override;
};


#include "OOJSShipGroup.h"
#include "OOJSEngineCore.h"

#include "oo_test.hpp"

#include <cstdarg>
#include <cstdint>
#include <cstring>
#include <map>
#include <string>


namespace {
JSContext *sContext;
JSClassID sFakeShipClassID = 0;
}


Entity::~Entity() = default;
OOShipGroup *ShipEntity::group()  { return _group.get(); }
void ShipEntity::setGroup(OOShipGroup *group)  { _group = oo::share(group); }
void ShipEntity::setOwner(Entity *who_owns_entity)  { (void)who_owns_entity; }
OOShipGroup *ShipEntity::escortGroup()  { return _escortGroup.get(); }

bool ShipEntity::acceptAsEscort(::ShipEntity *other_ship)
{
	if (other_ship->_name == "boom")  OORaiseException(OOInvalidArgumentException, "escort %s", "boom");
	if (!_acceptsEscorts)  return false;
	_accepted++;
	return true;
}

::TestEntityObject *TestObjectOf(Entity *entity)  { return entity != nullptr ? entity->_object : nullptr; }
#define OO_ENTITY_HELPERS_STAND_IN_CXX
#include "EntityHelpersStandIn.h"	// EntityHelpers.mm's, on the test's objects


std::optional<std::string> TestEntityObject::descriptionComponents()  { return _name; }

JSValue TestEntityObject::oo_jsValueInContext(JSContext *context)
{
	if (!JS_IsObject(_jsSelf))
	{
		_jsSelf = JS_NewObjectClass(context, static_cast<int>(sFakeShipClassID));
		JS_SetOpaque(_jsSelf, static_cast<oo::Object *>(this));
	}
	return JS_DupValue(context, _jsSelf);
}


OONull *OONull::null()
{
	static OONull *null = oo::test::NewRetained<OONull>();
	return null;
}

std::string OONull::className() const	{ return "OONull"; }
std::string OONull::description() const	{ return "<null>"; }


// MARK: What the rest of the engine provides ------------------------------------------------------

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


namespace {
std::string sLastWarning;
}

void OOJSReportWarningForCaller(JSContext *, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	sLastWarning = scriptClass.value_or("-") + "." + function.value_or("-") + ": " + oo::str::vformat(format, args);
	va_end(args);
}


void OOJSReportBadArguments(JSContext *context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, int argc, JSValueConst *, const std::optional<std::string> &message, const std::optional<std::string> &expectedArgsDescription)
{
	OOJSReportError(context, "bad arguments: %s.%s(%d) %s / %s", scriptClass.value_or("-").c_str(), function.value_or("-").c_str(), argc, message.value_or("-").c_str(), expectedArgsDescription.value_or("-").c_str());
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


std::optional<std::string> OOStringFromJSValueEvenIfNull(JSContext *context, JSValueConst value)
{
	if (JS_IsNull(value))  return std::string("null");
	if (JS_IsUndefined(value))  return std::string("undefined");
	return OOStringFromJSValue(context, value);
}


// The atom cache and the pending-exception reporter, which the class registry calls.
JSAtom OOJSIDFromString(const std::string &string)
{
	return JS_NewAtomLen(gOOJSMainThreadContext, string.data(), string.size());
}


void OOJSReportPendingException(JSContext *context)
{
	JS_FreeValue(context, JS_GetException(context));
}


// As the engine's: the pending exception, else an uncatchable error that stops the script.
JSValue OOJSNativeFailure(JSContext *context)
{
	if (JS_HasException(context))  return JS_EXCEPTION;
	JSValue error = JS_NewError(context);
	JS_SetUncatchableError(context, error);
	return JS_Throw(context, error);
}


namespace {

// The private object of a JS object of one of the registered classes (the fake Ship class or
// ShipGroup), an oo::Object (a ship's object or a group); null for any other value. A fake
// ship's slot holds its object itself; a group's is the engine's (OOJSSetCxxPrivate).
oo::Object *PrivateOf(JSValueConst value)
{
	if (!JS_IsObject(value))  return nullptr;
	JSClassID classID = JS_GetClassID(value);
	if (OOJSClassName(classID) == nullptr)  return nullptr;
	if (classID == sFakeShipClassID)  return static_cast<oo::RefCounted *>(JS_GetOpaque(value, classID));
	return OOJSCxxPrivateFromOpaque(JS_GetOpaque(value, classID));
}

} // namespace


// A property list as JavaScript, as far as the binding hands one over: null, a string, a number,
// an object (its JS value; OONull is null), or an array of those. Owned by the caller.
JSValue OOJSValueFromPList(JSContext *context, const oo::PList &plist)
{
	if (const std::string *str = plist.getIf<std::string>())  return JS_NewStringLen(context, str->data(), str->size());
	if (plist.isNumber())  return JS_NewNumber(context, plist.doubleValue());
	if (const oo::PList::Object *node = plist.getIf<oo::PList::Object>())	// a C++ object that is its own JS glue, as the engine asks it
	{
		if (OOJSPrivateObject *glue = dynamic_cast<OOJSPrivateObject *>(node->get()))  return OOJSValueFromCxxObject(context, glue);
		if (dynamic_cast<OONull *>(node->get()) != nullptr)  return JS_NULL;	// OONull is null
	}
	if (Entity *entity = oo::EntityIn(plist))	// an entity's node: its object's value, as OOJSValueFromNativeObject() gave it
	{
		::TestEntityObject *object = TestObjectOf(entity);
		return object != nullptr ? object->oo_jsValueInContext(context) : JS_NULL;
	}
	if (const oo::PList::Array *array = plist.getIf<oo::PList::Array>())
	{
		JSValue result = JS_NewArray(context);
		uint32_t index = 0;
		for (const oo::PList &element : *array)  JS_SetPropertyUint32(context, result, index++, OOJSValueFromPList(context, element));
		return result;
	}
	return JS_NULL;
}


namespace {
std::map<JSClassID, int> sConverters;
} // namespace


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


// (No longer reached for a group, whose toString() is
// OOJSCxxObjectWrapperToString.) A link stub: unreached, the slot holding the
// C++ object.
JSValue OOJSObjectWrapperToString(JSContext *, JSValueConst, int, JSValueConst *)
{
	std::abort();
}


// The engine's wrapper finalizer, which is the glue's (OOJSPrivateObject.cpp, linked): the slot's
// C++ object is told its wrapper is gone (clearJSSelf), released, and the slot emptied.
// (Unreached: a group's finalizer is the C++ one.)
void OOJSObjectWrapperFinalize(JSRuntime *runtime, JSValueConst thisObj)
{
	OOJSCxxObjectWrapperFinalize(runtime, thisObj);
}


int sLimiterPauses = 0;
int sProfileDepth = 0;

void OOJSProfileEnter(OOJSProfileStackFrame *, const char *)  { sProfileDepth++; }
void OOJSProfileExit(OOJSProfileStackFrame *)  { sProfileDepth--; }

void OOJSPauseTimeLimiter(void)  { sLimiterPauses++; }
void OOJSResumeTimeLimiter(void)  { sLimiterPauses--; }


#ifndef NDEBUG
void OOJSUnreachable(const char *function, const char *, unsigned)
{
	std::printf("unreachable reached in %s\n", function);
	abort();
}
#endif


// OOJSEntity.mm's (not linked): the C++ entity of an entity's JS object, null
// for any other value, with no error
// (OOJSNativeObjectOfClassFromJSValue(context, value, [TestEntityObject
// class]), whose stand-in this was). The test's ships keep their object in the
// slot, as the game's slot held the object's weak reference before.
Entity *OOJSEntityFromJSValue(JSContext *, JSValueConst value)
{
	// The slot holds an oo::RefCounted: a ship's object, or a group (the class
  // check is the C++ one).
	TestEntityObject *entity = dynamic_cast<TestEntityObject *>(PrivateOf(value));
	return entity != nullptr ? entity->_cxxEntity.get() : nullptr;
}


oo::PList OOJSBasicPrivateObjectConverter(JSContext *, JSValueConst)
{
	return oo::PList();
}


// The game's Ship class's toString(): the fake Ship class names its JS class, as the façade's
// Symbol.toStringTag made Object.prototype.toString() do (QuickJS-ng and #768 tag no class).
namespace {
JSValue FakeShipToString(JSContext *context, JSValueConst, int, JSValueConst *)
{
	return JS_NewString(context, "[object Ship]");
}
} // namespace


// MARK: The context -------------------------------------------------------------------------------

namespace {

JSClassDef sFakeShipClass = { .class_name = "Ship" };
const JSCFunctionListEntry sFakeShipMethods[] = {
	JS_CFUNC_DEF("toString", 0, FakeShipToString),
};

JSRuntime *sRuntime;
JSValue sGlobal;


// Defines a global; takes value (owned).
void Define(const char *name, JSValue value)
{
	JS_SetPropertyStr(sContext, sGlobal, name, value);
}


// A ship and its object (kept for the life of the test), defined by name.
ShipEntity *NewShip(const char *name)
{
	::TestEntityObject *object = oo::test::NewRetained<::TestEntityObject>();
	std::shared_ptr<ShipEntity> ship = oo::makeShared<ShipEntity>();
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
	sRuntime = JS_NewRuntime();
	JS_SetMemoryLimit(sRuntime, 8u * 1024u * 1024u);
	sContext = JS_NewContext(sRuntime);
	gOOJSMainThreadContext = sContext;
	sGlobal = JS_GetGlobalObject(sContext);
	OOJSRegisterClass(&sFakeShipClassID, &sFakeShipClass);
	OOJSInitClass(sContext, sGlobal, sFakeShipClassID, JS_UNDEFINED, nullptr, 0, nullptr, 0, sFakeShipMethods, OOJS_COUNT(sFakeShipMethods), nullptr, 0);
	InitOOJSShipGroup(sContext, sGlobal);
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
	std::shared_ptr<OOShipGroup> group = OOShipGroup::groupWithName(std::string("cat"));
	JSValue first = group->jsValueInContext(sContext);
	OO_CHECK(JS_IsObject(first));
	JSValue again = group->jsValueInContext(sContext);
	OO_CHECK(JS_VALUE_GET_PTR(again) == JS_VALUE_GET_PTR(first));
	JS_FreeValue(sContext, again);
	OO_CHECK(OOJSCxxPrivateFromOpaque(JS_GetOpaque(first, JS_GetClassID(first))) == static_cast<oo::Object *>(group.get()));
	Define("catGroup", first);	// the global holds it from here on
	OO_CHECK_EVAL("catGroup.name", "cat");
	// Clearing with another object leaves it; clearing with its own makes the next one new.
	group->clearJSSelf(JS_NULL);
	again = group->jsValueInContext(sContext);
	OO_CHECK(JS_VALUE_GET_PTR(again) == JS_VALUE_GET_PTR(first));
	JS_FreeValue(sContext, again);
	group->clearJSSelf(first);
	JSValue second = group->jsValueInContext(sContext);
	OO_CHECK(JS_IsObject(second) && JS_VALUE_GET_PTR(second) != JS_VALUE_GET_PTR(first));
	JS_FreeValue(sContext, second);
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
	std::shared_ptr<OOShipGroup> escorts = OOShipGroup::groupWithName(std::string("escorts"), leader);
	escorts->addShip(NewShip("first"));
	leader->_escortGroup = escorts;
	leader->_group = escorts;
	Define("escorts", escorts->jsValueInContext(sContext));
	leader->_acceptsEscorts = false;
	OO_CHECK_EVAL("[escorts.addShip(escort), escorts.containsShip(escort)].join()", "false,false");
	leader->_acceptsEscorts = true;
	OO_CHECK_EVAL("[escorts.addShip(escort), escorts.containsShip(escort)].join()", "true,true");
	OO_CHECK_EQ(leader->_accepted, 1);
	// A ship that already escorts someone else is refused, with a warning.
	std::shared_ptr<OOShipGroup> otherEscorts = OOShipGroup::groupWithName(std::string("other"), other);
	otherEscorts->addShip(taken);
	other->_escortGroup = otherEscorts;
	taken->_group = otherEscorts;
	sLastWarning.clear();
	OO_CHECK_EVAL("escorts.addShip(taken)", "false");
	OO_CHECK_EQ(sLastWarning, "ShipGroup.addShip: Ship " + TestEntityObjectDescription(TestObjectOf(taken), true) + " cannot be assigned to two escort groups, ignoring.");
	OO_CHECK(TestEntityObjectDescription(TestObjectOf(taken), true).find("{taken}") != std::string::npos);
	// A lone leader whose escort group is its own group gets a new group, and the ship joins that.
	ShipEntity *lone = NewShip("lone");
	std::shared_ptr<OOShipGroup> loneGroup = OOShipGroup::groupWithName(std::string("alone"), lone);
	lone->_escortGroup = loneGroup;
	lone->_group = loneGroup;
	Define("loneGroup", loneGroup->jsValueInContext(sContext));
	OO_CHECK_EVAL("[loneGroup.addShip(escort), loneGroup.containsShip(escort)].join()", "true,false");
	OO_CHECK(lone->_group != loneGroup && lone->_group->containsShip(escort));
	OO_CHECK(lone->_group->name() == std::optional<std::string>("ship group"));
	// A lone leader with a group of its own: it is asked to accept the escort.
	ShipEntity *custom = NewShip("custom");
	std::shared_ptr<OOShipGroup> customGroup = OOShipGroup::groupWithName(std::string("custom"), custom);
	custom->_escortGroup = customGroup;
	custom->_group = OOShipGroup::groupWithName(std::string("elsewhere"));
	Define("customGroup", customGroup->jsValueInContext(sContext));
	custom->_acceptsEscorts = false;
	OO_CHECK_EVAL("customGroup.addShip(escort)", "false");
	custom->_acceptsEscorts = true;
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
	std::shared_ptr<OOShipGroup> group = OOShipGroup::groupWithName(std::string("ex"), chief);
	group->addShip(NewShip("wingman"));
	chief->_escortGroup = group;
	chief->_group = group;
	Define("exGroup", group->jsValueInContext(sContext));
	OO_CHECK_EVAL("exGroup.addShip(boom)", "threw: Native exception: escort boom");
	OO_CHECK_EVAL("exGroup.count", "2");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
}


OO_TEST_MAIN()
