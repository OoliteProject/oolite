/*	test_OOJSPrivateObject.mm
	Unit tests for the engine's C++ private-slot glue (src/Core/Scripting/OOJSPrivateObject.h/.cpp):
	bead oo-6symp, proposed ADR-0056 amendment oo-6symp, which carries out amendment oo-ppc item 5.

	As the binding tests do (amendment oo-ppc item 6), it runs a JS class in a real context on the
	game's own façade backend (ooscript/JSEngine_quickjs.cpp) and links the glue and the engine's
	exception translator (OOJSEngineNativeWrappers.mm). The class is the test's own: a JS class
	"Thing" whose private slot holds a C++ Thing (an oo::RefCounted that implements
	OOJSPrivateObject), with OOJSCxxObjectWrapperFinalize as its finalizer, a toString() that is
	OOJSCxxObjectWrapperToString, and a "name" property read through OOJSGetCxxPrivate; a JS
	subclass "SubThing" is registered as the engine's subclasses are. What the rest of the engine
	provides (the error reporter, the string conversion, the subclass test and the Objective-C
	toString() a foreign `this` falls back to) is the smallest stand-in that does the same thing.
	The cases pin what replaced each selector the engine sent an id: -oo_jsValueInContext: (one JS
	object per object, null for null), the getter's class check and its error text, the
	finalizer's -oo_clearJSSelf: and release, and toString()'s -cxx_oo_jsDescription with its
	fallbacks and a native's exception. Run: bash tools/check-core-tests.sh
*/

#include "OOJSPrivateObject.h"
#include "OOJSEngineNativeWrappers.h"
#include "ooscript/JSEngine.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/String.hpp"

#include "oo_test.hpp"

#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <map>
#include <optional>
#include <stdexcept>
#include <string>


// MARK: The test's class --------------------------------------------------------------------------

namespace {

ooscript::ClassDef sThingClass =
{
	"Thing",
	ooscript::ClassFlag::HasPrivate,
	nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr,
	OOJSCxxObjectWrapperFinalize,	// finalize
	nullptr, nullptr, nullptr,
};
ooscript::ClassDef sSubThingClass =
{
	"SubThing",
	ooscript::ClassFlag::HasPrivate,
	nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr,
	OOJSCxxObjectWrapperFinalize,	// finalize
	nullptr, nullptr, nullptr,
};
ooscript::Object sThingPrototype = nullptr;
ooscript::Object sSubThingPrototype = nullptr;
int sDestroyed = 0;


/*	A C++ object a JS object wraps: it makes its wrapper on first use, as the bindings' classes do,
	and counts what the engine tells it. A Thing named "boom" throws from jsDescription().
*/
class Thing : public oo::RefCounted, public OOJSPrivateObject
{
public:
	Thing(std::string name, std::optional<std::string> description, ooscript::ClassDef *jsClass = &sThingClass)
		: _name(std::move(name)), _description(std::move(description)), _jsClass(jsClass)  {}
	~Thing() override  { sDestroyed++; }

	ooscript::Value jsValueInContext(ooscript::Context context) override
	{
		if (_jsSelf == nullptr)
		{
			_jsSelf = ooscript::newObject(context, _jsClass, _jsClass == &sThingClass ? sThingPrototype : sSubThingPrototype, nullptr);
			if (_jsSelf != nullptr && !OOJSSetCxxPrivate(context, _jsSelf, this))  _jsSelf = nullptr;
		}
		return ooscript::objectValue(_jsSelf);
	}

	void clearJSSelf(ooscript::Object selfVal) override
	{
		_clearCalls++;
		_lastCleared = selfVal;
		if (_jsSelf == selfVal)  _jsSelf = nullptr;
	}

	std::optional<std::string> jsDescription() override
	{
		if (_name == "boom")  throw std::runtime_error("description boom");
		return _description;
	}

	std::string _name;
	std::optional<std::string> _description;
	ooscript::ClassDef *_jsClass;
	ooscript::Object _jsSelf = nullptr;
	int _clearCalls = 0;
	ooscript::Object _lastCleared = nullptr;
};


// A slot object that does not implement OOJSPrivateObject: the finalizer only releases it.
class PlainThing : public oo::RefCounted
{
public:
	~PlainThing() override  { sDestroyed++; }
};

}	// namespace


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
	std::u16string units(reinterpret_cast<const char16_t *>(chars), length);
	return oo::utf16ToUtf8(units);
}


namespace {
std::map<ooscript::ClassDef *, ooscript::ClassDef *> sSuperclasses;
int sForeignToStrings = 0;
} // namespace

extern "C" BOOL OOJSIsSubclass(ooscript::ClassDef *putativeSubclass, ooscript::ClassDef *superclass)
{
	for (ooscript::ClassDef *c = putativeSubclass; c != nullptr; c = sSuperclasses.count(c) != 0 ? sSuperclasses[c] : nullptr)
	{
		if (c == superclass)  return YES;
	}
	return NO;
}


// The engine's Objective-C toString(), which a `this` of another class falls back to.
extern "C" bool OOJSObjectWrapperToString(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	sForeignToStrings++;
	oojsArgs.setRval(ooscript::stringValue(ooscript::newStringCopyN(context, "foreign", 7)));
	return true;
}


#if OOJS_PROFILE
extern "C" void OOJSProfileEnter(OOJSProfileStackFrame *, const char *)  {}
extern "C" void OOJSProfileExit(OOJSProfileStackFrame *)  {}
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

bool ThingToString(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	return OOJSCxxObjectWrapperToString(context, oojsArgs, &sThingClass);
}


// thing.name(): the C++ object's name, "<none>" for a prototype.
bool ThingName(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	Thing *thing = nullptr;
	if (!OOJSGetCxxPrivate(context, oojsArgs.thisObject(), &sThingClass, &thing))  return false;
	std::string name = thing != nullptr ? thing->_name : std::string("<none>");
	oojsArgs.setRval(ooscript::stringValue(ooscript::newStringCopyN(context, name.data(), name.size())));
	return true;
}


ooscript::FunctionSpec sThingMethods[] =
{
	{ "toString",	ThingToString,	0,	0 },
	{ "name",		ThingName,		0,	0 },
	{ nullptr, nullptr, 0, 0 }
};


// MARK: The context -------------------------------------------------------------------------------

ooscript::Runtime sRuntime;
ooscript::Context sContext;
ooscript::Object sGlobal;


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = ooscript::newRuntime(8u * 1024u * 1024u);
	sContext = ooscript::newContext(sRuntime, 8192);
	ooscript::beginRequest(sContext);
	sGlobal = ooscript::getGlobalObject(sContext);
	ooscript::initStandardClasses(sContext, sGlobal);
	sThingPrototype = ooscript::initClass(sContext, sGlobal, nullptr, &sThingClass, nullptr, 0, nullptr, sThingMethods, nullptr, nullptr);
	sSubThingPrototype = ooscript::initClass(sContext, sGlobal, sThingPrototype, &sSubThingClass, nullptr, 0, nullptr, nullptr, nullptr, nullptr);
	sSuperclasses[&sSubThingClass] = &sThingClass;
	ooscript::Value proto = ooscript::objectValue(sThingPrototype);
	ooscript::setProperty(sContext, sGlobal, "thingPrototype", &proto);
}


void Define(const char *name, ooscript::Value value)
{
	ooscript::setProperty(sContext, sGlobal, name, &value);
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
	OO_CHECK(ooscript::isNull(OOJSValueFromCxxObject(sContext, nullptr)));
	oo::Ref<Thing> thing = oo::adopt(new Thing("alpha", std::nullopt));
	OO_CHECK_EQ(thing->retainCount(), 1u);
	ooscript::Value first = OOJSValueFromCxxObject(sContext, thing.get());
	OO_CHECK(ooscript::isObject(first));
	OO_CHECK(ooscript::toObject(OOJSValueFromCxxObject(sContext, thing.get())) == ooscript::toObject(first));
	// The slot holds the object as an oo::RefCounted *, with one retain.
	OO_CHECK(ooscript::getPrivate(sContext, ooscript::toObject(first)) == static_cast<oo::RefCounted *>(thing.get()));
	OO_CHECK_EQ(thing->retainCount(), 2u);
	Define("alpha", first);
	OO_CHECK_EVAL("alpha.name()", "alpha");
	OO_CHECK_EVAL("Object.getPrototypeOf(alpha) === thingPrototype", "true");
}


OO_TEST(getter)
{
	SetUpContext();
	oo::Ref<Thing> sub = oo::adopt(new Thing("beta", std::nullopt, &sSubThingClass));
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
	Thing *thing = new Thing("gamma", std::nullopt);	// the test's reference, released below
	ooscript::Object wrapper = ooscript::toObject(OOJSValueFromCxxObject(sContext, thing));
	OO_CHECK(wrapper != nullptr);
	OO_CHECK_EQ(thing->retainCount(), 2u);
	ooscript::gc(sContext);
	OO_CHECK_EQ(thing->_clearCalls, 1);
	OO_CHECK(thing->_lastCleared == wrapper);
	OO_CHECK(thing->_jsSelf == nullptr);
	OO_CHECK_EQ(thing->retainCount(), 1u);
	// A new wrapper is made on the next use, and its finalizer's release is the last one.
	OO_CHECK(ooscript::isObject(OOJSValueFromCxxObject(sContext, thing)));
	const int destroyed = sDestroyed;
	thing->release();
	OO_CHECK_EQ(sDestroyed, destroyed);
	ooscript::gc(sContext);
	OO_CHECK_EQ(sDestroyed, destroyed + 1);

	// A slot object without the JS glue is released all the same.
	ooscript::Object plainWrapper = ooscript::newObject(sContext, &sThingClass, sThingPrototype, nullptr);
	PlainThing *plain = new PlainThing;
	OO_CHECK(OOJSSetCxxPrivate(sContext, plainWrapper, plain));
	OO_CHECK_EQ(plain->retainCount(), 2u);
	plain->release();
	plainWrapper = nullptr;
	ooscript::gc(sContext);
	OO_CHECK_EQ(sDestroyed, destroyed + 2);
}


OO_TEST(toString)
{
	SetUpContext();
	oo::Ref<Thing> described = oo::adopt(new Thing("delta", std::string("[Thing delta, caf\xC3\xA9]")));
	oo::Ref<Thing> plain = oo::adopt(new Thing("epsilon", std::nullopt));
	oo::Ref<Thing> sub = oo::adopt(new Thing("zeta", std::nullopt, &sSubThingClass));
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
	OO_CHECK(ooscript::isInRequest(sContext));
}


OO_TEST_MAIN()
