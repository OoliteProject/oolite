/*	test_OOJSPrivateObject.mm
	Unit tests for the engine's C++ private-slot glue (src/Core/Scripting/OOJSPrivateObject.h/.cpp).

	As the binding tests do, it runs a JS class in a real QuickJS-ng context and links the glue, the
	engine's class registry (OOJSClasses.mm) and its exception translator
	(OOJSEngineNativeWrappers.mm). The class is the test's own: a JS class "Thing" whose private
	slot holds a C++ Thing (an oo::RefCounted that implements OOJSPrivateObject), with
	OOJSCxxObjectWrapperFinalize as its finalizer, a toString() that is
	OOJSCxxObjectWrapperToString, and a "name" property read through OOJSGetCxxPrivate; a JS
	subclass "SubThing" is registered as the engine's subclasses are. What the rest of the engine
	provides (the error reporter, the string conversion, the atom cache and the toString() a foreign
	`this` falls back to) is the smallest stand-in that does the same thing. The cases pin what
	replaced each selector the engine sent an id: -oo_jsValueInContext: (one JS object per object,
	null for null), the getter's class check and its error text, the finalizer's -oo_clearJSSelf:
	and release, and toString()'s -cxx_oo_jsDescription with its fallbacks and a native's exception.
	Run: tests/run.sh unit
*/

#include "OOJSPrivateObject.h"
#include "OOJSEngineCore.h"
#include "oofnd/Ref.hpp"
#include "oofnd/String.hpp"

#include "oo_test.hpp"

#include <quickjs.h>

#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <optional>
#include <stdexcept>
#include <string>


// MARK: The test's class --------------------------------------------------------------------------

namespace {

JSClassDef sThingClass =
{
	.class_name = "Thing",
	.finalizer = OOJSCxxObjectWrapperFinalize,
};
JSClassDef sSubThingClass =
{
	.class_name = "SubThing",
	.finalizer = OOJSCxxObjectWrapperFinalize,
};
JSClassID sThingClassID = 0;
JSClassID sSubThingClassID = 0;
int sDestroyed = 0;


/*	A C++ object a JS object wraps: it makes its wrapper on first use, as the bindings' classes do
	(a weak reference: the caller gets the only one), and counts what the engine tells it. A Thing
	named "boom" throws from jsDescription().
*/
class Thing : public oo::RefCounted, public OOJSPrivateObject
{
public:
	Thing(std::string name, std::optional<std::string> description, JSClassID *jsClassID = &sThingClassID)
		: _name(std::move(name)), _description(std::move(description)), _jsClassID(jsClassID)  {}
	~Thing() override  { sDestroyed++; }

	JSValue jsValueInContext(JSContext *context) override
	{
		if (!JS_IsObject(_jsSelf))
		{
			JSValue jsSelf = JS_NewObjectClass(context, static_cast<int>(*_jsClassID));
			if (JS_IsException(jsSelf))
			{
				JS_FreeValue(context, JS_GetException(context));
				return JS_NULL;
			}
			if (!OOJSSetCxxPrivate(jsSelf, this))
			{
				JS_FreeValue(context, jsSelf);
				return JS_NULL;
			}
			_jsSelf = jsSelf;
			return jsSelf;
		}
		return JS_DupValue(context, _jsSelf);
	}

	void clearJSSelf(JSValueConst selfVal) override
	{
		_clearCalls++;
		_lastCleared = JS_VALUE_GET_PTR(selfVal);
		if (JS_IsObject(_jsSelf) && JS_VALUE_GET_PTR(_jsSelf) == JS_VALUE_GET_PTR(selfVal))  _jsSelf = JS_UNDEFINED;
	}

	std::optional<std::string> jsDescription() override
	{
		if (_name == "boom")  throw std::runtime_error("description boom");
		return _description;
	}

	std::string _name;
	std::optional<std::string> _description;
	JSClassID *_jsClassID;
	JSValue _jsSelf = JS_UNDEFINED;	// weak
	int _clearCalls = 0;
	void *_lastCleared = nullptr;
};


// A slot object that does not implement OOJSPrivateObject: the finalizer only releases it.
class PlainThing : public oo::RefCounted
{
public:
	~PlainThing() override  { sDestroyed++; }
};

}	// namespace


// MARK: What the rest of the engine provides ------------------------------------------------------

JSContext *gOOJSMainThreadContext = nullptr;


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


// The atom cache and the pending-exception reporter, which the class registry calls.
JSAtom cxx_OOJSIDFromString(const std::string &string)
{
	return JS_NewAtomLen(gOOJSMainThreadContext, string.data(), string.size());
}


void OOJSReportPendingException(JSContext *context)
{
	JS_FreeValue(context, JS_GetException(context));
}


namespace {
int sForeignToStrings = 0;
} // namespace

// The engine's Objective-C toString(), which a `this` of another class falls back to.
JSValue OOJSObjectWrapperToString(JSContext *context, JSValueConst, int, JSValueConst *)
{
	sForeignToStrings++;
	return JS_NewString(context, "foreign");
}


#if OOJS_PROFILE
void OOJSProfileEnter(OOJSProfileStackFrame *, const char *)  {}
void OOJSProfileExit(OOJSProfileStackFrame *)  {}
#endif

#ifndef NDEBUG
void OOJSUnreachable(const char *function, const char *, unsigned)
{
	std::printf("unreachable reached in %s\n", function);
	std::abort();
}
#endif


// MARK: The class's natives -----------------------------------------------------------------------

namespace {

JSValue ThingToString(OOJS_NATIVE_ARGS)
{
	return OOJSCxxObjectWrapperToString(context, OOJS_THIS, sThingClassID);
}


// thing.name(): the C++ object's name, "<none>" for a prototype.
JSValue ThingName(OOJS_NATIVE_ARGS)
{
	Thing *thing = nullptr;
	if (!OOJSGetCxxPrivate(context, OOJS_THIS, sThingClassID, &thing))  return JS_EXCEPTION;
	std::string name = thing != nullptr ? thing->_name : std::string("<none>");
	return JS_NewStringLen(context, name.data(), name.size());
}


const JSCFunctionListEntry sThingMethods[] =
{
	JS_CFUNC_DEF("toString", 0, ThingToString),
	JS_CFUNC_DEF("name", 0, ThingName),
};


// MARK: The context -------------------------------------------------------------------------------

JSRuntime *sRuntime;
JSContext *sContext;
JSValue sGlobal;


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = JS_NewRuntime();
	sContext = JS_NewContext(sRuntime);
	gOOJSMainThreadContext = sContext;
	sGlobal = JS_GetGlobalObject(sContext);
	OOJSRegisterClass(&sThingClassID, &sThingClass);
	OOJSRegisterClass(&sSubThingClassID, &sSubThingClass);
	JSValueConst thingPrototype = OOJSInitClass(sContext, sGlobal, sThingClassID, JS_UNDEFINED, nullptr, 0, nullptr, 0, sThingMethods, OOJS_COUNT(sThingMethods), nullptr, 0);
	OOJSInitClass(sContext, sGlobal, sSubThingClassID, thingPrototype, nullptr, 0, nullptr, 0, nullptr, 0, nullptr, 0);
	OOJSRegisterSubclass(sSubThingClassID, sThingClassID);
	JS_SetPropertyStr(sContext, sGlobal, "thingPrototype", JS_DupValue(sContext, thingPrototype));
}


// Defines a global; takes value (owned).
void Define(const char *name, JSValue value)
{
	JS_SetPropertyStr(sContext, sGlobal, name, value);
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


std::string EvalShown(const char *src, const char *expected)
{
	std::string result = Eval(src);
	if (result != expected)  std::printf("    %s\n    gave: %s\n", src, result.c_str());
	return result;
}
#define OO_CHECK_EVAL(src, expected)  OO_CHECK_EQ(EvalShown(src, expected), expected)

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

OO_TEST(jsValue)
{
	SetUpContext();
	// -oo_jsValueInContext: of nil was null; of an object, its own JS object, made once.
	OO_CHECK(JS_IsNull(OOJSValueFromCxxObject(sContext, nullptr)));
	oo::Ref<Thing> thing = oo::adopt(new Thing("alpha", std::nullopt));
	OO_CHECK_EQ(thing->retainCount(), 1u);
	JSValue first = OOJSValueFromCxxObject(sContext, thing.get());
	OO_CHECK(JS_IsObject(first));
	JSValue again = OOJSValueFromCxxObject(sContext, thing.get());
	OO_CHECK(JS_VALUE_GET_PTR(again) == JS_VALUE_GET_PTR(first));
	JS_FreeValue(sContext, again);
	// The slot holds the object as an oo::RefCounted *, with one retain.
	OO_CHECK(JS_GetOpaque(first, sThingClassID) == static_cast<oo::RefCounted *>(thing.get()));
	OO_CHECK_EQ(thing->retainCount(), 2u);
	Define("alpha", first);
	OO_CHECK_EVAL("alpha.name()", "alpha");
	OO_CHECK_EVAL("Object.getPrototypeOf(alpha) === thingPrototype", "true");
}


OO_TEST(getter)
{
	SetUpContext();
	oo::Ref<Thing> sub = oo::adopt(new Thing("beta", std::nullopt, &sSubThingClassID));
	Define("beta", OOJSValueFromCxxObject(sContext, sub.get()));
	// A registered subclass passes the class check; the prototype has no object.
	OO_CHECK_EVAL("beta.name()", "beta");
	OO_CHECK_EVAL("thingPrototype.name()", "<none>");
	// Anything else is the engine's error, as DEFINE_JS_OBJECT_GETTER reported it.
	OO_CHECK_EVAL("thingPrototype.name.call({})", "threw: Native method expected Thing, got [object Object].");
	OO_CHECK_EQ(Eval("thingPrototype.name.call(new Date(0))").rfind("threw: Native method expected Thing, got ", 0), 0u);
	OO_CHECK_EVAL("Object.getPrototypeOf(Object.getPrototypeOf(beta)) === thingPrototype", "true");
}


OO_TEST(finalize)
{
	SetUpContext();
	// The engine's finalizer sends clearJSSelf() with the dying wrapper, then releases the slot.
	// (QuickJS finalizes an object when its last reference goes, so the test drops its own before
	// collecting.)
	Thing *thing = new Thing("gamma", std::nullopt);	// the test's reference, released below
	JSValue wrapperValue = OOJSValueFromCxxObject(sContext, thing);
	void *wrapper = JS_VALUE_GET_PTR(wrapperValue);
	OO_CHECK(JS_IsObject(wrapperValue));
	OO_CHECK_EQ(thing->retainCount(), 2u);
	JS_FreeValue(sContext, wrapperValue);
	JS_RunGC(sRuntime);
	OO_CHECK_EQ(thing->_clearCalls, 1);
	OO_CHECK(thing->_lastCleared == wrapper);
	OO_CHECK(!JS_IsObject(thing->_jsSelf));
	OO_CHECK_EQ(thing->retainCount(), 1u);
	// A new wrapper is made on the next use, and its finalizer's release is the last one.
	JSValue second = OOJSValueFromCxxObject(sContext, thing);
	OO_CHECK(JS_IsObject(second));
	const int destroyed = sDestroyed;
	thing->release();
	OO_CHECK_EQ(sDestroyed, destroyed);
	JS_FreeValue(sContext, second);
	JS_RunGC(sRuntime);
	OO_CHECK_EQ(sDestroyed, destroyed + 1);

	// A slot object without the JS glue is released all the same.
	JSValue plainWrapper = JS_NewObjectClass(sContext, static_cast<int>(sThingClassID));
	PlainThing *plain = new PlainThing;
	OO_CHECK(OOJSSetCxxPrivate(plainWrapper, plain));
	OO_CHECK_EQ(plain->retainCount(), 2u);
	plain->release();
	JS_FreeValue(sContext, plainWrapper);
	JS_RunGC(sRuntime);
	OO_CHECK_EQ(sDestroyed, destroyed + 2);
}


OO_TEST(toString)
{
	SetUpContext();
	oo::Ref<Thing> described = oo::adopt(new Thing("delta", std::string("[Thing delta, caf\xC3\xA9]")));
	oo::Ref<Thing> plain = oo::adopt(new Thing("epsilon", std::nullopt));
	oo::Ref<Thing> sub = oo::adopt(new Thing("zeta", std::nullopt, &sSubThingClassID));
	Define("delta", OOJSValueFromCxxObject(sContext, described.get()));
	Define("epsilon", OOJSValueFromCxxObject(sContext, plain.get()));
	Define("zeta", OOJSValueFromCxxObject(sContext, sub.get()));
	// -cxx_oo_jsDescription, else "[object <JS class name>]" (the JS object's own class).
	OO_CHECK_EVAL("String(delta)", "[Thing delta, caf\xC3\xA9]");
	OO_CHECK_EVAL("String(epsilon)", "[object Thing]");
	OO_CHECK_EVAL("String(zeta)", "[object SubThing]");
	OO_CHECK_EVAL("String(thingPrototype)", "[object Thing]");
	// Another class's `this` is described by the engine's Objective-C toString().
	sForeignToStrings = 0;
	OO_CHECK_EVAL("thingPrototype.toString.call({})", "foreign");
	OO_CHECK_EQ(sForeignToStrings, 1);
	// An exception under jsDescription() becomes a JS error, as under any native.
	oo::Ref<Thing> boom = oo::adopt(new Thing("boom", std::nullopt));
	Define("boom", OOJSValueFromCxxObject(sContext, boom.get()));
	OO_CHECK_EVAL("String(boom)", "threw: Native exception: description boom");
}


OO_TEST_MAIN()
