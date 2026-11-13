/*	test_OOJSSun.mm
	Unit tests for the Sun JS binding (src/Core/Scripting/OOJSSun.h/.mm) and its OOSunEntity
	category (the C++ class's overrides answer the engine, through the root's JS category, and this
	test's stand-ins are C++ the same way).

	As test_OOJSWormhole.mm does, it runs the JS class in a real QuickJS-ng context, links the
	game's own objects for the binding, the engine's class registry (OOJSClasses.mm) and its
	exception translator (OOJSEngineNativeWrappers.mm), and stands in for the entity classes (Entity
	and OOSunEntity answer only the selectors the binding sends) and for the engine functions the
	binding links against, with the engine headers' linkage. The expectations pin the JS-visible
	behaviour (the four
	properties, goNova() and cancelNova(), a non-sun, a native's exception) and what the category
	answers the engine. Run: tests/run.sh unit
*/

#include "OOFoundation.h"
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"

#include <quickjs.h>


// MARK: The entity classes, as far as the binding sees them ---------------------------------------

// The C++ root, as far as the binding and the root's JS category reach it.
class Entity : public oo::RefCounted
{
public:
	virtual ~Entity();
	virtual JSClassID jsClassID();
	virtual std::optional<std::string> jsClassName();
	virtual bool isVisibleToScripts();
};


/*	A sun whose radius is 99 raises from radius(), one whose radius is 98 throws a C++ exception, so
	the test sees what an exception under a native becomes.
*/
class OOSunEntity : public Entity
{
public:
	double radius();
	std::optional<std::string> name();
	bool willGoNova();
	bool goneNova();
	void setGoingNova(bool yesno, double interval);

	JSClassID jsClassID() override;
	std::optional<std::string> jsClassName() override;
	bool isVisibleToScripts() override;

	double _radius = 0;
	std::optional<std::string> _name;
	bool _willGoNova = false;
	bool _goneNova = false;
	double _novaTime = 0;
	int _novaCalls = 0;
};


// What an entity's JS object holds: a weak reference to the C++ entity.
#include "OOJSEntityHolder.h"


// Its category's selectors are members of the same names.
class TestEntityObject final : public oo::RefCounted
{
public:
	JSClassID oo_jsClassID();
	std::optional<std::string> cxx_oo_jsClassName();
	bool isVisibleToScripts();

	std::shared_ptr<Entity> _cxxEntity;	// the sun's C++ part (oo::ToCxx reads it)
};

#include "OOJSSun.h"
#include "OOJSEngineCore.h"

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
std::optional<std::string> TestEntityObject::cxx_oo_jsClassName()  { return _cxxEntity->jsClassName(); }
bool TestEntityObject::isVisibleToScripts()  { return _cxxEntity->isVisibleToScripts(); }


Entity::~Entity()  {}
JSClassID Entity::jsClassID()  { return 0; }
std::optional<std::string> Entity::jsClassName()  { return std::string("Entity"); }
bool Entity::isVisibleToScripts()  { return false; }


std::optional<std::string> OOSunEntity::name()  { return _name; }
bool OOSunEntity::willGoNova()  { return _willGoNova; }
bool OOSunEntity::goneNova()  { return _goneNova; }

double OOSunEntity::radius()
{
	if (_radius == 99)  OORaiseException(OOInvalidArgumentException, "radius %s", "boom");
	if (_radius == 98)  throw std::runtime_error("cxx boom");
	return _radius;
}

void OOSunEntity::setGoingNova(bool yesno, double interval)
{
	_willGoNova = yesno;
	_novaTime = interval;
	_novaCalls++;
}


// The binding's category, as the C++ class's overrides answer it.
JSClassID OOSunEntity::jsClassID()  { return ::JSSunClassID(); }
std::optional<std::string> OOSunEntity::jsClassName()  { return ::OOJSSunJSClassName(); }
bool OOSunEntity::isVisibleToScripts()  { return ::OOJSSunIsVisibleToScripts(); }


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


// As the engine's: the pending exception, else an uncatchable error that ends the script.
JSValue OOJSNativeFailure(JSContext *context)
{
	if (JS_HasException(context))  return JS_EXCEPTION;
	JSValue error = JS_NewError(context);
	JS_SetUncatchableError(context, error);
	return JS_Throw(context, error);
}


// A property list as JavaScript, as far as the binding hands one over: null, a string, a number,
// or an array of those. Owned by the caller.
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
JSClassDef sFakeEntityClass = { .class_name = "Entity" };
JSClassID sFakeEntityClassID = 0;
std::map<JSClassID, int> sConverters;


/*	Entity's toString(), as the game's (OOJSEntity.mm: OOJSCxxObjectWrapperToString() of an object
	with no description of its own): "[object <its class>]". QuickJS-ng gives class prototypes no
	Symbol.toStringTag, so without it String(plainEntity) would be "[object Object]".
*/
JSValue FakeEntityToString(OOJS_NATIVE_ARGS)
{
	(void)argc;
	(void)OOJS_ARGV;
	return OOJSCxxObjectWrapperToString(context, OOJS_THIS, sFakeEntityClassID);
}

const JSCFunctionListEntry sFakeEntityMethods[] = {
	JS_CFUNC_DEF("toString", 0, FakeEntityToString),
};
} // namespace


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

JSRuntime *sRuntime;
JSContext *sContext;
JSValue sGlobal;
TestEntityObject *sSunObject = nullptr;	// the sun's object, which the JS object holds
OOSunEntity *sSun = nullptr;	// its C++ part


// A JS object of the class (its prototype is the class's), with a holder of the entity's C++ part
// in the private slot; owned by the caller.
JSValue JSValueForObject(JSClassID classID, TestEntityObject *entity)
{
	JSValue object = JS_NewObjectClass(sContext, static_cast<int>(classID));
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
	OOJSInitClass(sContext, sGlobal, sFakeEntityClassID, JS_UNDEFINED, OOJSUnconstructableConstruct, 0, nullptr, 0, sFakeEntityMethods, OOJS_COUNT(sFakeEntityMethods), nullptr, 0);
	InitOOJSSun(sContext, sGlobal);

	sSunObject = oo::makeRef<TestEntityObject>().leakRef();	// kept for the life of the test
	sSunObject->_cxxEntity = oo::makeRef<OOSunEntity>();
	sSun = static_cast<OOSunEntity *>(sSunObject->_cxxEntity.get());
	sSun->_radius = 250000.5;
	sSun->_name = "Lave";
	Define("sun", JSValueForEntity(sSunObject));
	Define("plainEntity", JSValueForObject(sFakeEntityClassID, oo::makeRef<TestEntityObject>().leakRef()));	// kept for the life of the test
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
	const JSClassID sunClass = sSunObject->oo_jsClassID();
	OO_CHECK(sunClass != 0 && OOJSClassName(sunClass) != nullptr && std::strcmp(OOJSClassName(sunClass), "Sun") == 0);
	JSValue prototype = JS_GetClassProto(sContext, sunClass);
	OO_CHECK(JS_IsObject(prototype));
	JS_FreeValue(sContext, prototype);
	OO_CHECK(OOJSIsSubclass(sunClass, sFakeEntityClassID));
	OO_CHECK_EQ(sConverters[sunClass], 1);
	OO_CHECK(sSunObject->cxx_oo_jsClassName() == std::optional<std::string>("Sun"));
	OO_CHECK(sSunObject->isVisibleToScripts());
	OO_CHECK_EVAL("typeof Sun", "function");
	OO_CHECK_EVAL("new Sun()", "threw: unconstructable");
	OO_CHECK_EVAL("Object.getPrototypeOf(Sun.prototype) === Entity.prototype", "true");
	OO_CHECK_EVAL("sun instanceof Sun", "true");
}


OO_TEST(properties)
{
	SetUpContext();
	OO_CHECK_EVAL("sun.radius", "250000.5");
	OO_CHECK_EVAL("sun.name", "Lave");
	OO_CHECK_EVAL("sun.hasGoneNova", "false");
	OO_CHECK_EVAL("sun.isGoingNova", "false");
	OO_CHECK_EVAL("Object.keys(Sun.prototype).join()", "hasGoneNova,isGoingNova,name,radius");
	sSun->_name = std::nullopt;
	OO_CHECK_EVAL("sun.name", "null");
	sSun->_name = "Lave";
	// Read-only.
	OO_CHECK_EVAL("(function () { sun.radius = 1; return sun.radius; })()", "250000.5");
}


OO_TEST(nova)
{
	SetUpContext();
	sSun->_novaCalls = 0;
	OO_CHECK_EVAL("sun.goNova(30)", "undefined");
	OO_CHECK(sSun->_willGoNova && sSun->_novaTime == 30 && sSun->_novaCalls == 1);
	OO_CHECK_EVAL("sun.isGoingNova", "true");
	OO_CHECK_EVAL("sun.goNova()", "undefined");
	OO_CHECK(sSun->_novaTime == 0 && sSun->_novaCalls == 2);
	OO_CHECK_EVAL("sun.cancelNova()", "undefined");
	OO_CHECK(!sSun->_willGoNova && sSun->_novaCalls == 3);
	OO_CHECK_EVAL("sun.cancelNova()", "undefined");	// not going nova: nothing to cancel
	OO_CHECK_EQ(sSun->_novaCalls, 3);
	// Gone nova: isGoingNova is false, and cancelNova() does nothing.
	sSun->_willGoNova = true;
	sSun->_goneNova = true;
	OO_CHECK_EVAL("sun.hasGoneNova", "true");
	OO_CHECK_EVAL("sun.isGoingNova", "false");
	OO_CHECK_EVAL("sun.cancelNova()", "undefined");
	OO_CHECK_EQ(sSun->_novaCalls, 3);
	sSun->_willGoNova = false;
	sSun->_goneNova = false;
}


OO_TEST(otherObjects)
{
	OO_CHECK_EVAL("Object.getOwnPropertyDescriptor(Sun.prototype, 'radius').get.call(plainEntity)", "threw: Native method expected Sun, got [object Entity].");
	OO_CHECK_EVAL("Sun.prototype.goNova.call({})", "threw: Native method expected Sun, got [object Object].");
	OO_CHECK_EVAL("Sun.prototype.radius", "0");	// the prototype has no sun: a message to nil
}


OO_TEST(nativeExceptions)
{
	SetUpContext();
	// The property getter is a native (OOJS_NATIVE_ENTER): a raise from the entity is a JS error,
	// and so is a C++ exception.
	sSun->_radius = 99;
	OO_CHECK_EVAL("sun.radius", "threw: Native exception: radius boom");
	sSun->_radius = 98;
	OO_CHECK_EVAL("sun.radius", "threw: Native exception: cxx boom");
	sSun->_radius = 250000.5;
	OO_CHECK_EVAL("sun.radius", "250000.5");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
}


OO_TEST_MAIN()
