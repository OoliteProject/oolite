/*	test_OOJSSun.mm
	Unit tests for the Sun JS binding (src/Core/Scripting/OOJSSun.h/.mm) and its OOSunEntity
	category (whose forwarders were on the OOSunEntity facade from bead oo-9ht.51 until bead
	oo-9ht.111 deleted it: the C++ class's overrides answer the engine now, through the root's JS
	category, and this test's stand-ins are C++ the same way, amendment oo-9ht.107 item 6): bead
	oo-hgfh, converted the way bead oo-ppc converted OOJSVector (proposed ADR-0056 amendments oo-ppc
	and oo-ykoy).

	As test_OOJSWormhole.mm does (amendment oo-ykoy, item 4), it runs the JS class in a real
	context on the game's own façade backend (ooscript/JSEngine_quickjs.cpp), links the game's own
	objects for the binding and the engine's exception translator
	(OOJSEngineNativeWrappers.mm), and stands in for the entity classes (Entity and OOSunEntity
	answer only the selectors the binding sends) and for the engine functions the binding links
	against, with the engine headers' linkage. The expectations were written against the
	Objective-C file and run on it first; they pin the JS-visible behaviour (the four properties,
	goNova() and cancelNova(), a non-sun, a native's exception) and what the category answers the
	engine. Run: bash tools/check-core-tests.sh
*/

#include "OOCocoa.h"
#include "ooscript/JSEngine.hpp"
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"


// MARK: The entity classes, as far as the binding sees them ---------------------------------------

// The C++ root, as far as the binding and the root's JS category reach it.
class Entity : public oo::RefCounted
{
public:
	virtual ~Entity();
	virtual void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype);
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

	void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype) override;
	std::optional<std::string> jsClassName() override;
	bool isVisibleToScripts() override;

	double _radius = 0;
	std::optional<std::string> _name;
	BOOL _willGoNova = NO;
	BOOL _goneNova = NO;
	double _novaTime = 0;
	int _novaCalls = 0;
};


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

	oo::Ref<Entity> _cxxEntity;	// the sun's C++ part (oo::ToCxx reads it)
};

#include "OOJSSun.h"

#include "oo_test.hpp"

#include <cstdarg>
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


Entity::~Entity()  {}
void Entity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)  { *outClass = nullptr; *outPrototype = nullptr; }
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


// The binding's category, as the C++ class's overrides answer it (bead oo-9ht.111; the OOSunEntity
// facade forwarded it from bead oo-9ht.51).
void OOSunEntity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)  { ::OOJSSunGetJSClass(outClass, outPrototype); }
std::optional<std::string> OOSunEntity::jsClassName()  { return ::OOJSSunJSClassName(); }
bool OOSunEntity::isVisibleToScripts()  { return ::OOJSSunIsVisibleToScripts(); }


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
	if (const double *number = plist.getIf<double>())  return ooscript::numberValue(*number);
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
ooscript::ClassDef sFakeEntityClass = { "Entity", ooscript::ClassFlag::HasPrivate };
std::map<ooscript::ClassDef *, ooscript::ClassDef *> sSuperclasses;
std::map<ooscript::ClassDef *, int> sConverters;
} // namespace

ooscript::Object gOOEntityJSPrototype = nullptr;


extern "C" {

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
TestEntityObject *sSunObject = nullptr;	// the sun's object, which the JS object holds
OOSunEntity *sSun = nullptr;	// its C++ part


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
	InitOOJSSun(sContext, sGlobal);

	sSunObject = oo::makeRef<TestEntityObject>().leakRef();	// kept for the life of the test
	sSunObject->_cxxEntity = oo::makeRef<OOSunEntity>();
	sSun = static_cast<OOSunEntity *>(sSunObject->_cxxEntity.get());
	sSun->_radius = 250000.5;
	sSun->_name = "Lave";
	Define("sun", JSValueForEntity(sSunObject));
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
	ooscript::ClassDef *sunClass = nullptr;
	ooscript::Object prototype = nullptr;
	sSunObject->getJSClass(&sunClass, &prototype);
	OO_CHECK(sunClass != nullptr && std::strcmp(sunClass->name, "Sun") == 0);
	OO_CHECK(prototype != nullptr);
	OO_CHECK(OOJSIsSubclass(sunClass, &sFakeEntityClass));
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
	sSun->_willGoNova = YES;
	sSun->_goneNova = YES;
	OO_CHECK_EVAL("sun.hasGoneNova", "true");
	OO_CHECK_EVAL("sun.isGoingNova", "false");
	OO_CHECK_EVAL("sun.cancelNova()", "undefined");
	OO_CHECK_EQ(sSun->_novaCalls, 3);
	sSun->_willGoNova = NO;
	sSun->_goneNova = NO;
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
	OO_CHECK(ooscript::isInRequest(sContext));
}


OO_TEST_MAIN()
