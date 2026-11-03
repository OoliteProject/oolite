/*	test_OOJSSystemInfo.mm
	Unit tests for the SystemInfo JS binding (src/Core/Scripting/OOJSSystemInfo.h/.mm) and the
	object it wraps, OOSystemInfo (its Objective-C facade deleted), after the conversion):
	bead oo-6ia4, converted the way bead oo-ppc converted OOJSVector (proposed
	ADR-0056 amendment oo-ppc).

	As the binding tests of amendment oo-ppc item 6 do, it runs the JS class in a real QuickJS-ng
	context, and links the game's own objects for the binding, the class registration
	(OOJSClasses.mm), the engine's exception translator (OOJSEngineNativeWrappers.mm) and the
	converted classes the binding asks (OOSystemDescriptionManager, OOCommodities and
	OOCommodityMarket, C++ with their facades deleted, held as oo::Ref, linked as their own tests
	link them). It
	stands in for the universe (its system data, coordinates and routes), the player (its galaxy
	and position), the running script (its manifest), the resource manager and string expander the
	converted classes call, and the engine functions the binding links against, with the engine
	headers' linkage. The engine's native-object conversion asks the object for its JS value, as
	the engine does, so a SystemInfo's JS object is the one the class makes. The SystemInfo's slot
	holds the C++ system info, so it also links the engine's C++ private-slot glue
	(OOJSPrivateObject.cpp: the getter, finalizer and toString()). The expectations were
	written against the Objective-C file and run on it first; they pin the JS-visible behaviour
	(the cached object, the four properties and their errors, system data both ways, enumeration,
	the four methods and the two static ones, interstellar space, a native's exception) and what
	the wrapped object answers the engine (its class name, description and equality).
	Run: bash tools/check-core-tests.sh
*/

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"
#import "OOSystemDescriptionManager.h"
#import "OOCommodities.h"
#import "OOCommodityMarket.h"
#import "OOStringExpander.h"
#include <objc/runtime.h>
#include "OOMaths.h"
#include "OOTypes.h"
#include <quickjs.h>
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#import "OODescription.h"
#import "OOObjCPList.h"


// MARK: The classes, as far as the binding and the converted classes see them --------------------

class StationEntity;

/*	The universe: system data by "galaxy system" and key, the current system's data in interstellar
	space, a system's coordinates (system 99's raise from -coordinatesForSystem:, system 98's throw
	a C++ exception), routes, and what was set last.
*/
#import "UniverseStandIn.h"

// The universe as the code under test sees it: a stand-in for the C++ class (its Objective-C facade,
// deleted, was what the test's Objective-C stand-in stood in for), with the header's names and signatures.
// It answers virtual members, so it has the game's vtable (UniverseStandIn.h) and StandInUniverse overrides them.
class Universe : public oo::RefCounted
{
public:
	OO_UNIVERSE_STAND_IN_VIRTUAL_MEMBERS

	BOOL _interstellar;
	std::map<std::string, oo::PList> _data;
	oo::PList _currentSystemData;
	oo::Ref<OOSystemDescriptionManager> _systemManager;
	oo::Ref<OOCommodities> _commodities;
	std::string _lastSet;
	OOSystemID _routeFrom, _routeTo;
	OORouteType _routeType;

	::OOCommodities *getCommodities();
	OOSystemID currentSystemID();
	oo::PList systemDataForGalaxy(OOGalaxyID, OOSystemID, const std::string &);
	std::vector<std::string> systemDataKeysForGalaxy(OOGalaxyID, OOSystemID);
	NSPoint coordinatesForSystem(OOSystemID);
	oo::PList routeFromSystem(OOSystemID, OOSystemID, OORouteType);
	::OOCommodityMarket *getCommodityMarket();	// link stub
};

// Link stubs, never reached: the code under test calls them on paths the test does not take (the
// Objective-C stand-in did not answer them).
::OOCommodityMarket *Universe::getCommodityMarket()  { std::abort(); }


class StandInUniverse : public Universe
{
public:
	bool inInterstellarSpace() override;
	oo::PList currentSystemData() override;
	::OOSystemDescriptionManager *getSystemManager() override;
	void setSystemDataForGalaxy(OOGalaxyID, OOSystemID, const std::string &, const oo::PList &, const std::optional<std::string> &, OOSystemLayer) override;
};

// PLAYER: C++, its Objective-C object this stood in for deleted: the members the code under test
// calls, declared as the game headers declare them (the test imports none that defines the
// classes), with the stand-in's answers.
class PlayerEntity
{
public:
	OOGalaxyID currentGalaxyID();
	OOGalaxyID galaxyNumber();
	NSPoint getGalaxy_coordinates();
	::OOScript * commodityScriptNamed(const std::optional<std::string> &scriptName);

	OOGalaxyID _galaxy = {};
	NSPoint _coordinates = {};
};

#import "ResourceManager.h"

// A station: C++, its Objective-C object this stood in for deleted; the members the commodities
// call, declared as StationEntity.h declares them (the test imports no game header that defines
// the class). No case makes a station: link stubs.
class StationEntity
{
public:
	oo::PList getMarketDefinition();
	std::optional<std::string> getMarketScriptName();
	OOCargoQuantity getMarketCapacity();
	bool getMarketMonitored();
};

@interface OOObject (OOJSTestGlue)
- (JSValue) oo_jsValueInContext:(JSContext *)context;
- (std::optional<std::string>) cxx_oo_jsClassName;
@end


#import "OOJSSystemInfo.h"
#include "OOJSEngineCore.h"

#include "oo_test.hpp"

#include <cmath>
#include <cstdarg>
#include <cstdint>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>


namespace {

oo::PList Dict(std::initializer_list<std::pair<const char *, oo::PList>> entries)
{
	oo::PList::Dict dict;
	for (const auto &[key, value] : entries)  dict[key] = value;
	return oo::PList(std::move(dict));
}


std::string Key(OOGalaxyID g, OOSystemID s, const std::string &key)
{
	return oo::str::format("%u %i ", g, s) + key;
}

}	// namespace


bool StandInUniverse::inInterstellarSpace()	{ return _interstellar; }
oo::PList StandInUniverse::currentSystemData()	{ return _currentSystemData; }
::OOSystemDescriptionManager *StandInUniverse::getSystemManager()	{ return _systemManager.get(); }
::OOCommodities *Universe::getCommodities()	{ return _commodities.get(); }
OOSystemID Universe::currentSystemID()	{ return 7; }
oo::PList Universe::systemDataForGalaxy(OOGalaxyID gnum, OOSystemID pnum, const std::string &key)
{
	auto found = _data.find(Key(gnum, pnum, key));
	return found != _data.end() ? found->second : oo::PList();
}
void StandInUniverse::setSystemDataForGalaxy(OOGalaxyID gnum, OOSystemID pnum, const std::string &key, const oo::PList &value, const std::optional<std::string> &manifest, OOSystemLayer layer)
{
	_lastSet = Key(gnum, pnum, key) + "=" + oo::DescriptionOf(value) + " from " + manifest.value_or("(none)") + " layer " + std::to_string(static_cast<int>(layer));
	if (value.isNull())  _data.erase(Key(gnum, pnum, key));
	else  _data[Key(gnum, pnum, key)] = value;
	// The binding reads system data back from the system manager, where the game's universe stores it.
	_systemManager->setProperty(key, oo::str::format("%u %i", gnum, pnum), layer, value, manifest);
}
std::vector<std::string> Universe::systemDataKeysForGalaxy(OOGalaxyID gnum, OOSystemID pnum)
{
	std::vector<std::string> keys;
	const std::string prefix = Key(gnum, pnum, "");
	for (const auto &entry : _data)
	{
		if (entry.first.compare(0, prefix.size(), prefix) == 0)  keys.push_back(entry.first.substr(prefix.size()));
	}
	return keys;
}
NSPoint Universe::coordinatesForSystem(OOSystemID s)
{
	if (s == 99)  [OOException raise:OOInvalidArgumentException format:"coordinates %s", "boom"];
	if (s == 98)  throw std::runtime_error("cxx boom");
	return NSMakePoint(s * 4, s * 2);
}
oo::PList Universe::routeFromSystem(OOSystemID start, OOSystemID goal, OORouteType optimizeBy)
{
	_routeFrom = start;
	_routeTo = goal;
	_routeType = optimizeBy;
	if (goal == 13)  return oo::PList();	// no route
	return Dict({ { "jumps", oo::PList(2.0) }, { "route", oo::PList(oo::PList::Array{ oo::PList(static_cast<double>(start)), oo::PList(static_cast<double>(goal)) }) } });
}


OOGalaxyID PlayerEntity::currentGalaxyID()  { return _galaxy; }
OOGalaxyID PlayerEntity::galaxyNumber()  { return _galaxy; }
NSPoint PlayerEntity::getGalaxy_coordinates()  { return _coordinates; }
::OOScript * PlayerEntity::commodityScriptNamed(const std::optional<std::string> &script)  { (void)script; return nullptr; }


class OOJSScript;

namespace {
OOJSScript *sScript = nullptr;	// the running script
oo::PList sScriptManifest;
}


#import "OOScript.h"


// OOJSScript (OOJSScript.h), which the code under test calls. The OOScript root's facade is gone
// and a script is the C++ object, so the stand-in is a C++ subclass of OOScript declaring the
// members that code calls: the running script, and its manifest property.
class OOJSScript : public OOScript
{
public:
	static OOJSScript *currentlyRunningScript();
	oo::PList propertyNamed(const std::string &name);
};

// OOScript's virtual members (OOScript.mm reaches the whole game), for the test's scripts' vtable.
std::optional<std::string> OOScript::descriptionComponents()	{ return std::nullopt; }
std::optional<std::string> OOScript::name()					{ return std::nullopt; }
std::optional<std::string> OOScript::scriptDescription()		{ return std::nullopt; }
std::optional<std::string> OOScript::version()				{ return std::nullopt; }
bool OOScript::requiresTickle()								{ return false; }
void OOScript::runWithTarget(Entity *)						{}
bool OOScript::callMethod(JSAtom, JSContext *, JSValueConst *, int, JSValue *)	{ return false; }
std::string OOScript::className() const						{ return "OOScript"; }
std::string OOScript::description() const						{ return "<OOScript>"; }
JSValue OOScript::jsValueInContext(JSContext *)				{ return JS_UNDEFINED; }
void OOScript::clearJSSelf(JSValueConst)						{}

OOJSScript *OOJSScript::currentlyRunningScript()  { return sScript; }

// The running script's manifest identifier.
oo::PList OOJSScript::propertyNamed(const std::string &name)
{
	return name == "oolite_manifest_identifier" ? sScriptManifest : oo::PList();
}


// ResourceManager is C++ since its Objective-C facade was deleted: C++ definitions of the
// statics the code under test calls, with the Objective-C stand-in's answers.
// trade-goods.plist: food, with no random spread.
oo::PList ResourceManager::dictionaryFromFilesNamed(const std::string &fileName, const std::optional<std::string> &folderName, OOResourceMergeMode mergeMode, bool useCache)
{
	(void)fileName; (void)folderName; (void)mergeMode; (void)useCache;
	return Dict({ { "food", Dict({ { "name", oo::PList("Food") }, { "quantity_unit", oo::PList(0) }, { "peak_export", oo::PList(7) }, { "peak_import", oo::PList(0) },
		{ "price_average", oo::PList(50) }, { "price_economic", oo::PList(0.5) }, { "price_random", oo::PList(0) },
		{ "quantity_average", oo::PList(40) }, { "quantity_economic", oo::PList(0.5) }, { "quantity_random", oo::PList(0) } }) } });
}

oo::PList ResourceManager::manifestForIdentifier(const std::string &identifier)
{
	return oo::PList(oo::PList::Dict{ { "identifier", oo::PList(identifier) } });
}



oo::PList StationEntity::getMarketDefinition()					{ std::abort(); }
std::optional<std::string> StationEntity::getMarketScriptName()	{ std::abort(); }
OOCargoQuantity StationEntity::getMarketCapacity()				{ std::abort(); }
bool StationEntity::getMarketMonitored()						{ std::abort(); }



// The expander: "<string>".
std::optional<std::string> cxx_OOExpandDescriptionString(Random_Seed, const std::string &string, const oo::PList &, const oo::PList &, const std::optional<std::string> &, OOExpandOptions)
{
	return "<" + string + ">";
}

Random_Seed OOStringExpanderDefaultRandomSeed(void)
{
	return Random_Seed{};
}


// The system manager's parsers, for the inputs the test uses (as test_OOSystemDescriptionManager.mm).
NSPoint cxx_PointFromString(const std::string &xyString)
{
	double x = 0, y = 0;
	if (std::sscanf(xyString.c_str(), "%lf %lf", &x, &y) != 2)  return NSMakePoint(0, 0);
	return NSMakePoint(x, y);
}


Random_Seed cxx_RandomSeedFromString(const std::optional<std::string> &)
{
	return Random_Seed{};
}


// A route type by name: the two the test names.
OORouteType cxx_StringToRouteType(const std::string &string)
{
	if (string == "OPTIMIZED_BY_TIME")  return OPTIMIZED_BY_TIME;
	if (string == "OPTIMIZED_BY_NONE")  return OPTIMIZED_BY_NONE;
	return OPTIMIZED_BY_JUMPS;
}


// Galactic coordinates: x / 4, y / 2 here, so system s is at (s, s).
extern "C" Vector OOGalacticCoordinatesFromInternal(NSPoint internalCoordinates)
{
	return make_vector(internalCoordinates.x / 4, internalCoordinates.y / 2, 0);
}


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


void cxx_OOJSReportErrorForCaller(JSContext *context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	std::string msg = scriptClass.value_or("-") + "." + function.value_or("-") + ": " + oo::str::vformat(format, args);
	va_end(args);
	JS_ThrowPlainError(context, "%s", msg.c_str());
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
	if (chars == NULL)
	{
		JS_FreeValue(context, JS_GetException(context));
		return std::nullopt;
	}
	std::string result(chars, length);
	JS_FreeCString(context, chars);
	return result;
}


// As the engine's: rounded to nearest, an error for NaN or out of range.
BOOL OOJSValueToInt32(JSContext *context, JSValueConst value, int32_t *outValue)
{
	double number;
	if (JS_ToFloat64(context, &number, value) < 0)  return NO;
	number = std::floor(number + 0.5);
	if (std::isnan(number) || number < INT32_MIN || number > INT32_MAX)
	{
		cxx_OOJSReportError(context, "can't convert %s to an integer", cxx_OOStringFromJSValue(context, value).value_or("(null)").c_str());
		return NO;
	}
	*outValue = static_cast<int32_t>(number);
	return YES;
}


// The binding's cache listens for it (OOJavaScriptEngine.mm's name).
const char *const kOOJavaScriptEngineWillResetNotificationName = "org.aegidian.oolite OOJavaScriptEngine will reset";


// The engine's conversion asks the object for its JS value; nil is null.
JSValue OOJSValueFromNativeObject(JSContext *context, id object)
{
	if (object == nil)  return JS_NULL;
	return [object oo_jsValueInContext:context];
}


// A property list as JavaScript (owned), as far as the binding hands one over: null, a string, a
// number, an object (its JS value), or an array or dictionary of those.
JSValue OOJSValueFromPList(JSContext *context, const oo::PList &plist)
{
	if (const std::string *str = plist.getIf<std::string>())  return JS_NewStringLen(context, str->data(), str->size());
	if (plist.isNumber())  return JS_NewNumber(context, plist.doubleValue());
	if (const oo::PList::Object *node = plist.getIf<oo::PList::Object>())
	{
		if (OOJSPrivateObject *glue = dynamic_cast<OOJSPrivateObject *>(node->get()))  return OOJSValueFromCxxObject(context, glue);
	}
	if (id object = oo::ObjectIn(plist))  return OOJSValueFromNativeObject(context, object);
	if (const oo::PList::Array *array = plist.getIf<oo::PList::Array>())
	{
		JSValue object = JS_NewArray(context);
		uint32_t index = 0;
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


// A JS value's plist form, as far as the test sets one: a string, a number, or null.
oo::PList cxx_OOJSPListFromJSValue(JSContext *context, JSValueConst value)
{
	double number = 0;
	if (JS_IsString(value))  return oo::PList(cxx_OOStringFromJSValue(context, value).value_or(""));
	if (JS_IsNumber(value) && JS_ToFloat64(context, &number, value) == 0)  return oo::PList(number);
	return oo::PList();
}


// Link stubs (amendment oo-zffj, item 2): the commodity classes' script path, which the test never takes.
oo::PList cxx_OOJSPListFromJSObject(JSContext *, JSValueConst)	{ std::abort(); }
JSAtom OOJSInternAtomPRIVATE(const char *)	{ std::abort(); }


namespace {
std::map<JSClassID, int> sConverters;
}

PlayerEntity *gOOPlayer = nullptr;
Universe *gSharedUniverse = nil;


void OOJSReportBadPropertySelector(JSContext *context, JSValueConst, int, const JSCFunctionListEntry *, size_t)
{
	cxx_OOJSReportError(context, "bad property selector");
}


void OOJSRegisterObjectConverter(JSClassID classID, OOJSClassConverterCallback)
{
	sConverters[classID]++;
}


// The engine's object getter: the JS class must be the required one, and the private object
// must be of the required Objective-C class.
BOOL OOJSObjectGetterImplPRIVATE(JSContext *context, JSValueConst object, JSClassID requiredClassID, Class requiredObjCClass, const char *, id *outObject)
{
	if (JS_GetClassID(object) != requiredClassID)
	{
		cxx_OOJSReportError(context, "Native method expected %s, got %s.", OOJSClassName(requiredClassID), cxx_OOStringFromJSValue(context, object).value_or("(null)").c_str());
		return NO;
	}
	*outObject = (id)JS_GetOpaque(object, requiredClassID);
	if (*outObject != nil && ![*outObject isKindOfClass:requiredObjCClass])
	{
		cxx_OOJSReportError(context, "Native method expected %s from %s.", class_getName(requiredObjCClass), OOJSClassName(requiredClassID));
		*outObject = nil;
		return NO;
	}
	return YES;
}


// The private object of a JS object, if it is of the class.
id OOJSNativeObjectOfClassFromJSObject(JSContext *, JSValueConst object, Class requiredClass)
{
	JSClassID classID;
	id native = (id)JS_GetAnyOpaque(object, &classID);
	return [native isKindOfClass:requiredClass] ? native : nil;
}


JSValue OOJSObjectWrapperToString(JSContext *context, JSValueConst thisObj, int, JSValueConst *)
{
	JSClassID classID;
	id object = (id)JS_GetAnyOpaque(thisObj, &classID);
	std::string text = "[" + oo::DescriptionOf(object) + "]";
	return JS_NewStringLen(context, text.data(), text.size());
}


// As the engine's: releases the private object.
void OOJSObjectWrapperFinalize(JSRuntime *, JSValueConst thisObj)
{
	JSClassID classID;
	id object = (id)JS_GetAnyOpaque(thisObj, &classID);
	if (object != nil)
	{
		[object release];
		JS_SetOpaque(thisObj, NULL);
	}
}


JSValue OOJSUnconstructableConstruct(JSContext *context, JSValueConst, int, JSValueConst *)
{
	cxx_OOJSReportError(context, "unconstructable");
	return JS_EXCEPTION;
}


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


bool NSPointToVectorJSValue(JSContext *context, NSPoint point, JSValue *outValue)
{
	return VectorToJSValue(context, make_vector(point.x, point.y, 0), outValue);
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


oo::PList OOJSBasicPrivateObjectConverter(JSContext *, JSValueConst)
{
	return oo::PList();
}


// MARK: The context -------------------------------------------------------------------------------

namespace {

JSRuntime *sRuntime = nullptr;
JSContext *sContext = nullptr;
JSValue sGlobal = JS_UNDEFINED;	// held for the life of the test
Universe *sUniverse = nil;
PlayerEntity *sPlayer = nullptr;


// Defines a global; takes value's reference.
void Define(const char *name, JSValue value)
{
	JS_SetPropertyStr(sContext, sGlobal, name, value);
}


// A native the tests call: info(galaxy, system) is GetJSSystemInfoForSystem().
JSValue TestInfo(JSContext *context, JSValueConst, int argc, JSValueConst *argv)
{
	std::int32_t g = 0, s = 0;
	if (argc > 0)  JS_ToInt32(context, &g, argv[0]);
	if (argc > 1)  JS_ToInt32(context, &s, argv[1]);
	return GetJSSystemInfoForSystem(context, static_cast<OOGalaxyID>(g), static_cast<OOSystemID>(s));
}


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = JS_NewRuntime();
	sContext = JS_NewContext(sRuntime);
	gOOJSMainThreadContext = sContext;
	sGlobal = JS_GetGlobalObject(sContext);
	InitOOJSSystemInfo(sContext, sGlobal);
	Define("info", JS_NewCFunction(sContext, TestInfo, "info", 2));

	sUniverse = new StandInUniverse();	// kept for the life of the test
	gSharedUniverse = sUniverse;
	sPlayer = new PlayerEntity;
	gOOPlayer = sPlayer;
	sUniverse->_systemManager = oo::makeRef<OOSystemDescriptionManager>();
	sUniverse->_commodities = oo::makeRef<OOCommodities>();
	sUniverse->_data[Key(0, 7, "economy")] = oo::PList(2.0);
	sUniverse->_data[Key(0, 7, "government")] = oo::PList(std::string("4"));
	sUniverse->_data[Key(0, 7, "name")] = oo::PList(std::string("Lave"));
	// The system manager holds the same data (the binding reads values there).
	sUniverse->_systemManager->setProperty("economy", "0 7", OO_LAYER_CORE, oo::PList(2.0), std::nullopt);
	sUniverse->_systemManager->setProperty("government", "0 7", OO_LAYER_CORE, oo::PList(std::string("4")), std::nullopt);
	sUniverse->_systemManager->setProperty("name", "0 7", OO_LAYER_CORE, oo::PList(std::string("Lave")), std::nullopt);
	sUniverse->_systemManager->setProperty("population", "0 7", OO_LAYER_CORE, oo::PList(std::string("2.5")), std::nullopt);
	sUniverse->_systemManager->setProperty("techlevel", "0 7", OO_LAYER_CORE, oo::PList(8.0), std::nullopt);
	sScript = oo::makeRef<OOJSScript>().leakRef();
	sScriptManifest = oo::PList(std::string("org.test.script"));
	Define("lave", GetJSSystemInfoForSystem(sContext, 0, 7));
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
	OO_CHECK_EQ(sConverters.size(), 1u);
	OO_CHECK_EVAL("typeof SystemInfo", "function");
	OO_CHECK_EVAL("new SystemInfo()", "threw: unconstructable");
	OO_CHECK_EVAL("lave instanceof SystemInfo", "true");
	OO_CHECK_EVAL("typeof SystemInfo.filteredSystems + typeof SystemInfo.setInterstellarProperty", "functionfunction");
}


OO_TEST(cache)
{
	SetUpContext();
	// The last object made is given again for the same system, and a new one for another.
	OO_CHECK_EVAL("info(0, 7) === info(0, 7)", "true");
	OO_CHECK_EVAL("(function () { var a = info(0, 7); var b = info(0, 8); return a !== b && b === info(0, 8) && a !== info(0, 7); })()", "true");
	// A system out of range is null, with a warning.
	sLastWarning.clear();
	OO_CHECK_EVAL("info(9, 7)", "null");
	OO_CHECK_EQ(sLastWarning, std::string("Could not create system info object for galaxy 9, system 7."));
	OO_CHECK_EVAL("info(0, 256)", "null");
	OO_CHECK_EVAL("info(0, -2)", "null");
	OO_CHECK_EVAL("info(1, -1) instanceof SystemInfo", "true");	// interstellar space
}


OO_TEST(wrappedObject)
{
	SetUpContext();
	JSValue a = GetJSSystemInfoForSystem(sContext, 0, 7);
	JSValue b = GetJSSystemInfoForSystem(sContext, 3, 7);
	// The slot holds the C++ system info.
	auto slot = [](JSValueConst v) { JSClassID ignored; return static_cast<OOSystemInfo *>(static_cast<oo::RefCounted *>(JS_GetAnyOpaque(v, &ignored))); };
	OOSystemInfo *cxxA = slot(a);
	OOSystemInfo *cxxB = slot(b);
	JSValue c = GetJSSystemInfoForSystem(sContext, 0, 7);
	OOSystemInfo *cxxC = slot(c);
	OO_CHECK(cxxA != nullptr && cxxB != nullptr && cxxC != nullptr && cxxA != cxxC);
	OO_CHECK(cxxA->oo_jsClassName() == std::optional<std::string>("SystemInfo"));
	OO_CHECK(cxxA->isEqual(cxxC));
	OO_CHECK(!cxxA->isEqual(cxxB));
	OO_CHECK(!cxxA->isEqual(nullptr));
	OO_CHECK_EQ(cxxA->hash(), cxxC->hash());
	OO_CHECK_EQ(cxxB->hash(), static_cast<NSUInteger>((3u << 16) | 7u));
	OO_CHECK(cxxA->description().find(">{galaxy 0, system 7}") != std::string::npos);
	// toString() is the engine's OOJSCxxObjectWrapperToString: the system info's jsDescription().
	OO_CHECK_EVAL("String(lave)", "[SystemInfo galaxy 0, system 7]");
	// Its JS value is a new object each time.
	JSValue another = cxxA->jsValueInContext(sContext);
	OO_CHECK(JS_VALUE_GET_PTR(another) != JS_VALUE_GET_PTR(a));
	JS_FreeValue(sContext, another);
	JS_FreeValue(sContext, c);
	JS_FreeValue(sContext, b);
	JS_FreeValue(sContext, a);
}


OO_TEST(properties)
{
	SetUpContext();
	OO_CHECK_EVAL("lave.galaxyID + ' ' + lave.systemID", "0 7");
	OO_CHECK_EVAL("lave.coordinates", "7,7,0");
	OO_CHECK_EVAL("lave.internalCoordinates", "28,14,0");
	// The fixed properties are hidden (#768: no enumeration lists them).
	OO_CHECK_EVAL("Object.keys(SystemInfo.prototype).join()", "");
	// Other galaxies, and a saved interstellar object out of interstellar space, have no coordinates.
	OO_CHECK_EVAL("info(2, 7).coordinates", "threw: Cannot read systemInfo values for other galaxies.");
	OO_CHECK_EVAL("info(2, 7).internalCoordinates", "threw: Cannot read systemInfo values for other galaxies.");
	OO_CHECK_EVAL("info(2, 7).galaxyID", "2");
	OO_CHECK_EVAL("info(0, -1).coordinates", "threw: Cannot read systemInfo values for invalid interstellar space reference.");
	// Read-only.
	OO_CHECK_EVAL("(function () { lave.systemID = 3; return lave.systemID; })()", "7");
}


OO_TEST(systemData)
{
	SetUpContext();
	// Read from the system manager; numbers, and strings that are number literals, as numbers.
	OO_CHECK_EVAL("lave.name", "Lave");
	OO_CHECK_EVAL("typeof lave.population + ' ' + lave.population", "number 2.5");
	OO_CHECK_EVAL("typeof lave.techlevel + ' ' + lave.techlevel", "number 8");
	OO_CHECK_EVAL("lave.nothing", "undefined");
	// Set through the universe, with the running script's manifest, in the dynamic layer.
	OO_CHECK_EVAL("(function () { lave.motto = 'Hi'; return lave.motto; })()", "Hi");	// kept on the object too
	OO_CHECK_EQ(sUniverse->_lastSet, std::string("0 7 motto=Hi from org.test.script layer 2"));
	OO_CHECK_EVAL("(function () { lave.motto = 5; return 1; })()", "1");
	OO_CHECK_EQ(sUniverse->_lastSet, std::string("0 7 motto=5 from org.test.script layer 2"));
	sScriptManifest = oo::PList(3.0);	// not a string: no manifest
	OO_CHECK_EVAL("(function () { lave.motto = null; return 1; })()", "1");
	OO_CHECK_EQ(sUniverse->_lastSet, std::string("0 7 motto=(null) from (none) layer 2"));
	sScriptManifest = oo::PList(std::string("org.test.script"));
	OO_CHECK_EVAL("(function () { delete lave.motto; return 1; })()", "1");
	OO_CHECK_EQ(sUniverse->_lastSet, std::string("0 7 motto=(null) from org.test.script layer 2"));
	// Enumeration: the universe's keys for the system (#768 hides the fixed properties).
	OO_CHECK_EVAL("(function () { var k = []; for (var p in lave) k.push(p); return k.join(); })()", "economy,government,name");
	// Not own properties, as in SpiderMonkey; but the in operator, which QuickJS-ng's for..in also
	// asks, finds them.
	OO_CHECK_EVAL("lave.hasOwnProperty('economy')", "false");
	OO_CHECK_EVAL("'economy' in lave", "true");
	OO_CHECK_EVAL("'noSuchKey' in lave", "false");
	OO_CHECK_EVAL("'distanceToSystem' in lave", "true");
	// Object.keys(): the system data keys only (#768 hides the fixed ones).
	OO_CHECK_EVAL("Object.keys(info(0, 7)).join()", "economy,government,name");
}


OO_TEST(interstellar)
{
	SetUpContext();
	sUniverse->_interstellar = YES;
	sUniverse->_currentSystemData = Dict({ { "name", oo::PList("Interstellar space") }, { "economy", oo::PList(3.0) } });
	sPlayer->_coordinates = NSMakePoint(40, 20);
	OO_CHECK_EVAL("info(0, -1).coordinates", "10,10,0");
	OO_CHECK_EVAL("info(0, -1).name", "Interstellar space");
	OO_CHECK_EVAL("Object.keys(info(0, -1)).join()", "economy,name");
	sUniverse->_interstellar = NO;
	sUniverse->_currentSystemData = oo::PList();
}


// bead oo-f4241: -cxx_currentSystemData answers a PList by value, so a pointer into it taken in an
// if-init dangled while the keys were read. Long keys (no small-string optimisation) make the copies
// pushed while iterating allocate, so freed dictionary nodes are reused under the loop.
OO_TEST(interstellar_keys_of_a_fresh_snapshot)
{
	SetUpContext();
	oo::PList::Dict data;
	std::string expected;
	for (int i = 0; i < 40; i++)
	{
		char key[64];
		std::snprintf(key, sizeof key, "interstellar_property_with_a_long_name_%02d", i);
		data[key] = oo::PList(static_cast<double>(i));
		if (i != 0)  expected += ",";
		expected += key;
	}	// the system data keys only (#768 hides the fixed properties)
	sUniverse->_interstellar = YES;
	sUniverse->_currentSystemData = oo::PList(std::move(data));
	OO_CHECK_EVAL("Object.keys(info(0, -1)).join()", expected.c_str());
	OO_CHECK_EVAL("Object.keys(info(0, -1)).length", "40");
	sUniverse->_interstellar = NO;
	sUniverse->_currentSystemData = oo::PList();
}


OO_TEST(methods)
{
	SetUpContext();
	OO_CHECK_EVAL("lave.distanceToSystem(info(0, 10)).toFixed(4)", "4.8000");
	OO_CHECK_EVAL("lave.distanceToSystem(info(1, 10))", "threw: SystemInfo.distanceToSystem: Cannot calculate distance for systems in other galaxies.");
	OO_CHECK_EVAL("lave.distanceToSystem({})", "threw: bad arguments: SystemInfo.distanceToSystem(1) - / system info");
	OO_CHECK_EVAL("lave.distanceToSystem()", "threw: bad arguments: SystemInfo.distanceToSystem(0) - / system info");
	OO_CHECK_EVAL("JSON.stringify(lave.routeToSystem(info(0, 10)))", "{\"jumps\":2,\"route\":[7,10]}");
	OO_CHECK_EQ(static_cast<int>(sUniverse->_routeType), static_cast<int>(OPTIMIZED_BY_JUMPS));
	OO_CHECK_EVAL("lave.routeToSystem(info(0, 10), 'OPTIMIZED_BY_TIME').jumps", "2");
	OO_CHECK_EQ(static_cast<int>(sUniverse->_routeType), static_cast<int>(OPTIMIZED_BY_TIME));
	OO_CHECK_EVAL("lave.routeToSystem(info(0, 13))", "null");
	OO_CHECK_EVAL("lave.routeToSystem(info(4, 10))", "threw: SystemInfo.routeToSystem: Cannot calculate route for destinations in other galaxies.");
	OO_CHECK_EVAL("lave.routeToSystem(5)", "threw: bad arguments: SystemInfo.routeToSystem(1) - / system info");
	// samplePrice: the commodities' price for the system's economy.
	OO_CHECK_EVAL("lave.samplePrice('food')", "60");
	OO_CHECK_EVAL("lave.samplePrice('unobtainium')", "threw: bad arguments: SystemInfo.samplePrice(1) - / Unrecognised commodity type");
	OO_CHECK_EVAL("info(1, 7).samplePrice('food')", "threw: SystemInfo.samplePrice: Cannot calculate sample price for destinations in other galaxies.");
	// setProperty(layer, key, value [, manifest]).
	OO_CHECK_EVAL("lave.setProperty(1, 'motto', 'Yo')", "undefined");
	OO_CHECK_EQ(sUniverse->_lastSet, std::string("0 7 motto=Yo from org.test.script layer 1"));
	OO_CHECK_EVAL("lave.setProperty(3, 'motto', null, 'org.other')", "undefined");
	OO_CHECK_EQ(sUniverse->_lastSet, std::string("0 7 motto=(null) from org.other layer 3"));
	OO_CHECK_EVAL("lave.setProperty(4, 'motto', 'x')", "threw: bad arguments: SystemInfo.setProperty(3) - / layer must be 0, 1, 2 or 3");
	OO_CHECK_EVAL("lave.setProperty('a', 'motto', 'x')", "threw: bad arguments: SystemInfo.setProperty(3) - / setProperty(layer, property, value [,manifest])");
	OO_CHECK_EVAL("lave.setProperty(1, 'motto')", "threw: bad arguments: SystemInfo.setProperty(2) - / setProperty(layer, property, value [,manifest])");
	OO_CHECK_EVAL("SystemInfo.prototype.setProperty.call({}, 1, 'a', 'b')", "threw: Native method expected SystemInfo, got [object Object].");
}


OO_TEST(staticMethods)
{
	SetUpContext();
	// filteredSystems: every system of the player's galaxy, through the predicate, with this.
	sPlayer->_galaxy = 2;
	OO_CHECK_EVAL("SystemInfo.filteredSystems({ max: 3 }, function (s) { return s.systemID < this.max; }).map(function (s) { return s.galaxyID + ':' + s.systemID; }).join()", "2:0,2:1,2:2");
	OO_CHECK_EVAL("SystemInfo.filteredSystems(null, function (s) { return false; }).length", "0");
	OO_CHECK_EVAL("SystemInfo.filteredSystems({}, 5)", "threw: bad arguments: SystemInfo.filteredSystems(2) - / this and predicate function");
	sPlayer->_galaxy = 0;
	OO_CHECK_EQ(sLimiterPauses, 0);
	// setInterstellarProperty(galaxy, from, to, layer, key, value [, manifest]): in the system manager.
	OO_CHECK_EVAL("SystemInfo.setInterstellarProperty(0, 7, 10, 2, 'danger', 'high')", "undefined");
	OO_CHECK(sUniverse->_systemManager->getProperty("danger", "interstellar: 0 7 10") == oo::PList(std::string("high")));
	OO_CHECK_EVAL("SystemInfo.setInterstellarProperty(0, 7, 10, 2, 'danger', null)", "undefined");
	OO_CHECK(sUniverse->_systemManager->getProperty("danger", "interstellar: 0 7 10").isNull());
	OO_CHECK_EVAL("SystemInfo.setInterstellarProperty(8, 7, 10, 2, 'danger', 'x')", "threw: bad arguments: SystemInfo.setInterstellarProperty(3) - / galaxy out of range");
	OO_CHECK_EVAL("SystemInfo.setInterstellarProperty(0, 256, 10, 2, 'danger', 'x')", "threw: bad arguments: SystemInfo.setInterstellarProperty(3) - / fromsystem out of range");
	OO_CHECK_EVAL("SystemInfo.setInterstellarProperty(0, 7, -1, 2, 'danger', 'x')", "threw: bad arguments: SystemInfo.setInterstellarProperty(3) - / tosystem out of range");
	OO_CHECK_EVAL("SystemInfo.setInterstellarProperty(0, 7, 10, 4, 'danger', 'x')", "threw: bad arguments: SystemInfo.setInterstellarProperty(3) - / layer must be 0, 1, 2 or 3");
	OO_CHECK_EVAL("SystemInfo.setInterstellarProperty(0, 7, 10, 2, 'danger')", "threw: bad arguments: SystemInfo.setInterstellarProperty(3) - / setProperty(galaxy, fromsystem, tosystem, layer, property, value [,manifest])");
}


OO_TEST(otherObjects)
{
	SetUpContext();
	OO_CHECK_EVAL("SystemInfo.prototype.galaxyID", "undefined");	// the prototype: left to the engine
	OO_CHECK_EVAL("SystemInfo.prototype.distanceToSystem.call(5, lave)", "threw: Native method expected SystemInfo, got 5.");
	OO_CHECK_EVAL("typeof Object.getOwnPropertyDescriptor(SystemInfo.prototype, 'galaxyID')", "object");
}


OO_TEST(nativeExceptions)
{
	SetUpContext();
	OO_CHECK_EVAL("info(0, 99).internalCoordinates", "threw: Native exception: coordinates boom");
	OO_CHECK_EVAL("info(0, 98).coordinates", "threw: Native exception: cxx boom");
	OO_CHECK_EVAL("lave.coordinates", "7,7,0");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
}


OO_TEST_MAIN()
