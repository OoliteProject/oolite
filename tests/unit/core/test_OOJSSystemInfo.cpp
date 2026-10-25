/*	test_OOJSSystemInfo.mm
	Unit tests for the SystemInfo JS binding (src/Core/Scripting/OOJSSystemInfo.h/.mm) and the
	object it wraps, OOSystemInfo (its Objective-C facade deleted by bead oo-9ht.95), after the conversion):
	bead oo-6ia4, converted the way bead oo-ppc converted OOJSVector (proposed
	ADR-0056 amendment oo-ppc).

	As the binding tests of amendment oo-ppc item 6 do, it runs the JS class in a real context on
	the game's own façade backend (ooscript/JSEngine_quickjs.cpp), and links the game's own objects
	for the binding, the engine's exception translator (OOJSEngineNativeWrappers.mm) and the
	converted classes the binding asks (OOSystemDescriptionManager, OOCommodities and
	OOCommodityMarket, C++ since beads oo-9ht.32, oo-9ht.25 and oo-9ht.21 deleted their façades,
	held as oo::Ref, linked as their own tests link them). It
	stands in for the universe (its system data, coordinates and routes), the player (its galaxy
	and position), the running script (its manifest), the resource manager and string expander the
	converted classes call, and the engine functions the binding links against, with the engine
	headers' linkage. The engine's native-object conversion asks the object for its JS value, as
	the engine does, so a SystemInfo's JS object is the one the class makes. Since bead oo-6symp.2
	the SystemInfo's slot holds the C++ system info, so it also links the engine's C++
	private-slot glue (OOJSPrivateObject.cpp: the getter, finalizer and toString()). The expectations were
	written against the Objective-C file and run on it first; they pin the JS-visible behaviour
	(the cached object, the four properties and their errors, system data both ways, enumeration,
	the four methods and the two static ones, interstellar space, a native's exception) and what
	the wrapped object answers the engine (its class name, description and equality).
	Run: bash tools/check-core-tests.sh
*/

#include "OOCocoa.h"
#include "oofnd/objc/OOObject.h"
#include "OOSystemDescriptionManager.h"
#include "OOCommodities.h"
#include "OOCommodityMarket.h"
#include "OOStringExpander.h"
#include "OOMaths.h"
#include "OOTypes.h"
#include "ooscript/JSEngine.hpp"
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#include "OODescription.h"
#include "OOObjCPList.h"


// MARK: The classes, as far as the binding and the converted classes see them --------------------

class StationEntity;

/*	The universe: system data by "galaxy system" and key, the current system's data in interstellar
	space, a system's coordinates (system 99's raise from -coordinatesForSystem:, system 98's throw
	a C++ exception), routes, and what was set last.
*/
#include "UniverseStandIn.h"

// The universe as the code under test sees it: a stand-in for the C++ class (bead oo-ql9rn deleted
// the Objective-C facade the test's Objective-C stand-in stood in for), with the header's names and signatures.
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
// Objective-C stand-in did not answer them; bead oo-ql9rn).
::OOCommodityMarket *Universe::getCommodityMarket()  { std::abort(); }


class StandInUniverse : public Universe
{
public:
	bool inInterstellarSpace() override;
	oo::PList currentSystemData() override;
	::OOSystemDescriptionManager *getSystemManager() override;
	void setSystemDataForGalaxy(OOGalaxyID, OOSystemID, const std::string &, const oo::PList &, const std::optional<std::string> &, OOSystemLayer) override;
};

// PLAYER: C++ since bead oo-9ht.177 deleted the Objective-C player this stood in for: the members
// the code under test calls, declared as the game headers declare them (the test imports none
// that defines the classes), with the stand-in's answers.
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

#include "ResourceManager.h"

// A station: C++ since bead oo-9ht.175 deleted the Objective-C station this stood in for; the
// members the commodities call, declared as StationEntity.h declares them (the test imports no
// game header that defines the class). No case makes a station: link stubs.
class StationEntity
{
public:
	oo::PList getMarketDefinition();
	std::optional<std::string> getMarketScriptName();
	OOCargoQuantity getMarketCapacity();
	bool getMarketMonitored();
};



#include "OOJSSystemInfo.h"

#include "oo_test.hpp"

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
	if (s == 99)  OORaiseException(OOInvalidArgumentException, "coordinates %s", "boom");
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
::OOScript * PlayerEntity::commodityScriptNamed(const std::optional<std::string> &script)  { (void)script; return nil; }


class OOJSScript;

namespace {
OOJSScript *sScript = nullptr;	// the running script
oo::PList sScriptManifest;
}


#include "OOScript.h"


// OOJSScript (OOJSScript.h), which the code under test calls. Since bead oo-9ht.133 deleted the
// OOScript root's facade (a script's object since bead oo-9ht.137) a script is the C++ object, so
// the stand-in is a C++ subclass of OOScript declaring the members that code calls: the running
// script, and its manifest property.
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
bool OOScript::callMethod(ooscript::PropertyId, ooscript::Context, ooscript::Value *, int, ooscript::Value *)	{ return false; }
std::string OOScript::className() const						{ return "OOScript"; }
std::string OOScript::description() const						{ return "<OOScript>"; }
ooscript::Value OOScript::jsValueInContext(ooscript::Context)	{ return ooscript::undefinedValue(); }
void OOScript::clearJSSelf(ooscript::Object)					{}

OOJSScript *OOJSScript::currentlyRunningScript()  { return sScript; }

// The running script's manifest identifier.
oo::PList OOJSScript::propertyNamed(const std::string &name)
{
	return name == "oolite_manifest_identifier" ? sScriptManifest : oo::PList();
}


// ResourceManager is C++ since bead oo-9ht.150 deleted its Objective-C facade: C++ definitions of the
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


void cxx_OOJSReportErrorForCaller(ooscript::Context context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	std::string msg = scriptClass.value_or("-") + "." + function.value_or("-") + ": " + oo::str::vformat(format, args);
	va_end(args);
	ooscript::reportError(context, msg.c_str());
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


void cxx_OOJSReportBadArguments(ooscript::Context context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, unsigned argc, ooscript::Value *, const std::optional<std::string> &message, const std::optional<std::string> &expectedArgsDescription)
{
	cxx_OOJSReportError(context, "bad arguments: %s.%s(%u) %s / %s", scriptClass.value_or("-").c_str(), function.value_or("-").c_str(), argc, message.value_or("-").c_str(), expectedArgsDescription.value_or("-").c_str());
}


std::optional<std::string> cxx_OOStringFromJSString(ooscript::Context context, ooscript::String str)
{
	if (str == nullptr)  return std::nullopt;
	std::size_t length = 0;
	const ooscript::Char16 *chars = ooscript::getStringCharsAndLength(context, str, &length);
	std::string result;
	for (std::size_t i = 0; i < length; i++)  result += static_cast<char>(chars[i]);	// the test's strings are ASCII
	return result;
}


std::optional<std::string> cxx_OOStringFromJSValue(ooscript::Context context, ooscript::Value value)
{
	if (ooscript::isNullOrUndefined(value))  return std::nullopt;
	return cxx_OOStringFromJSString(context, ooscript::valueToString(context, value));
}




// A property list as JavaScript, as far as the binding hands one over: null, a string, a number,
// an object (its JS value), or an array or dictionary of those.
ooscript::Value OOJSValueFromPList(ooscript::Context context, const oo::PList &plist)
{
	if (const std::string *str = plist.getIf<std::string>())
	{
		ooscript::String js = ooscript::newStringCopyN(context, str->data(), str->size());
		return js != nullptr ? ooscript::stringValue(js) : ooscript::nullValue();
	}
	if (plist.isNumber())  return ooscript::numberValue(plist.doubleValue());
	if (const oo::PList::Object *node = plist.getIf<oo::PList::Object>())
	{
		if (OOJSPrivateObject *glue = dynamic_cast<OOJSPrivateObject *>(node->get()))  return OOJSValueFromCxxObject(context, glue);
	}
	if (const oo::PList::Array *array = plist.getIf<oo::PList::Array>())
	{
		std::vector<ooscript::Value> values;
		for (const oo::PList &element : *array)  values.push_back(OOJSValueFromPList(context, element));
		ooscript::Object object = ooscript::newArrayObject(context, static_cast<unsigned>(values.size()), values.data());
		return object != nullptr ? ooscript::objectValue(object) : ooscript::nullValue();
	}
	if (const oo::PList::Dict *dict = plist.getIf<oo::PList::Dict>())
	{
		ooscript::Object object = ooscript::newObject(context, nullptr, nullptr, nullptr);
		for (const auto &entry : *dict)
		{
			ooscript::Value value = OOJSValueFromPList(context, entry.second);
			ooscript::setProperty(context, object, entry.first.c_str(), &value);
		}
		return ooscript::objectValue(object);
	}
	return ooscript::nullValue();
}


// A JS value's plist form, as far as the test sets one: a string, a number, or null.
oo::PList cxx_OOJSPListFromJSValue(ooscript::Context context, ooscript::Value value)
{
	double number = 0;
	if (ooscript::isString(value))  return oo::PList(cxx_OOStringFromJSValue(context, value).value_or(""));
	if (ooscript::isNumber(value) && ooscript::valueToNumber(context, value, &number))  return oo::PList(number);
	return oo::PList();
}


// Link stub (amendment oo-zffj, item 2): the commodity classes' script path, which the test never takes.
oo::PList cxx_OOJSPListFromJSObject(ooscript::Context, ooscript::Object)	{ std::abort(); }
ooscript::Context gOOJSMainThreadContext = nullptr;


namespace {
std::map<ooscript::ClassDef *, int> sConverters;
}

PlayerEntity *gOOPlayer = nullptr;
Universe *gSharedUniverse = nil;


extern "C" {

void OOJSReportBadPropertySelector(ooscript::Context context, ooscript::Object, ooscript::PropertyId, ooscript::PropertySpec *)
{
	cxx_OOJSReportError(context, "bad property selector");
}


void OOJSRegisterObjectConverter(ooscript::ClassDef *theClass, oo::PList (*)(ooscript::Context, ooscript::Object))
{
	sConverters[theClass]++;
}




// The JS class check of the engine's C++ getter (OOJSPrivateObject.cpp, linked since bead
// oo-6symp.2, whose slot holds the C++ system info): no subclass of SystemInfo is registered.
extern "C" BOOL OOJSIsSubclass(ooscript::ClassDef *putativeSubclass, ooscript::ClassDef *superclass)
{
	return putativeSubclass == superclass;
}






// A link stub (bead oo-dbz.4): unreached, the slot holding the C++ object since bead oo-4aq6a.6; it
// described the slot as an Objective-C object, which oo::DescriptionOf(id) did until libobjc2 went.
bool OOJSObjectWrapperToString(ooscript::Context, ooscript::CallArgs &)
{
	std::abort();
}


void OOJSInitJSIDCachePRIVATE(const char *, ooscript::PropertyId *)
{
	std::abort();	// link stub: the commodity classes' script path
}


bool OOJSUnconstructableConstruct(ooscript::Context context, ooscript::CallArgs &)
{
	cxx_OOJSReportError(context, "unconstructable");
	return false;
}


// A vector is the array [x, y, z] here.
bool VectorToJSValue(ooscript::Context context, Vector vector, ooscript::Value *outValue)
{
	ooscript::Value parts[3] = { ooscript::numberValue(vector.x), ooscript::numberValue(vector.y), ooscript::numberValue(vector.z) };
	ooscript::Object array = ooscript::newArrayObject(context, 3, parts);
	if (array == nullptr)  return false;
	*outValue = ooscript::objectValue(array);
	return true;
}


bool NSPointToVectorJSValue(ooscript::Context context, NSPoint point, ooscript::Value *outValue)
{
	return VectorToJSValue(context, make_vector(point.x, point.y, 0), outValue);
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


oo::PList OOJSBasicPrivateObjectConverter(ooscript::Context, ooscript::Object)
{
	return oo::PList();
}


// MARK: The context -------------------------------------------------------------------------------

namespace {

ooscript::Runtime sRuntime;
ooscript::Context sContext;
ooscript::Object sGlobal;
Universe *sUniverse = nil;
PlayerEntity *sPlayer = nullptr;


void Define(const char *name, ooscript::Value value)
{
	ooscript::setProperty(sContext, sGlobal, name, &value);
}


// A native the tests call: info(galaxy, system) is GetJSSystemInfoForSystem().
bool TestInfo(ooscript::Context context, ooscript::CallArgs &args)
{
	std::int32_t g = 0, s = 0;
	ooscript::valueToInt32(context, args[0], &g);
	ooscript::valueToInt32(context, args[1], &s);
	args.setRval(GetJSSystemInfoForSystem(context, static_cast<OOGalaxyID>(g), static_cast<OOSystemID>(s)));
	return true;
}


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = ooscript::newRuntime(8u * 1024u * 1024u);
	sContext = ooscript::newContext(sRuntime, 8192);
	ooscript::beginRequest(sContext);
	sGlobal = ooscript::getGlobalObject(sContext);
	ooscript::initStandardClasses(sContext, sGlobal);
	InitOOJSSystemInfo(sContext, sGlobal);
	static ooscript::FunctionSpec functions[] = { { "info", TestInfo, 2, 0 }, { 0 } };
	ooscript::defineFunctions(sContext, sGlobal, functions);

	sUniverse = new StandInUniverse();	// kept for the life of the test
	gSharedUniverse = sUniverse;
	sPlayer = new PlayerEntity;
	gOOPlayer = sPlayer;
	sUniverse->_systemManager = oo::makeRef<OOSystemDescriptionManager>();
	sUniverse->_commodities = oo::makeRef<OOCommodities>();
	sUniverse->_data[Key(0, 7, "economy")] = oo::PList(2.0);
	sUniverse->_data[Key(0, 7, "government")] = oo::PList(std::string("4"));
	sUniverse->_data[Key(0, 7, "name")] = oo::PList(std::string("Lave"));
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
	ooscript::Value a = GetJSSystemInfoForSystem(sContext, 0, 7);
	ooscript::Value b = GetJSSystemInfoForSystem(sContext, 3, 7);
	// The slot holds the C++ system info (bead oo-6symp.2).
	auto slot = [](ooscript::Value v) { return static_cast<OOSystemInfo *>(static_cast<oo::RefCounted *>(ooscript::getPrivate(sContext, ooscript::toObject(v)))); };
	OOSystemInfo *cxxA = slot(a);
	OOSystemInfo *cxxB = slot(b);
	ooscript::Value c = GetJSSystemInfoForSystem(sContext, 0, 7);
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
	OO_CHECK(ooscript::toObject(cxxA->jsValueInContext(sContext)) != ooscript::toObject(a));
}


OO_TEST(properties)
{
	SetUpContext();
	OO_CHECK_EVAL("lave.galaxyID + ' ' + lave.systemID", "0 7");
	OO_CHECK_EVAL("lave.coordinates", "7,7,0");
	OO_CHECK_EVAL("lave.internalCoordinates", "28,14,0");
	OO_CHECK_EVAL("Object.keys(SystemInfo.prototype).join()", "coordinates,internalCoordinates,galaxyID,systemID");
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
	// Enumeration: the universe's keys for the system, then the properties.
	OO_CHECK_EVAL("(function () { var k = []; for (var p in lave) k.push(p); return k.join(); })()", "economy,government,name,coordinates,internalCoordinates,galaxyID,systemID");
	OO_CHECK_EVAL("Object.keys(info(0, 7)).join()", "economy,government,name,coordinates,internalCoordinates,galaxyID,systemID");
}


OO_TEST(interstellar)
{
	SetUpContext();
	sUniverse->_interstellar = YES;
	sUniverse->_currentSystemData = Dict({ { "name", oo::PList("Interstellar space") }, { "economy", oo::PList(3.0) } });
	sPlayer->_coordinates = NSMakePoint(40, 20);
	OO_CHECK_EVAL("info(0, -1).coordinates", "10,10,0");
	OO_CHECK_EVAL("info(0, -1).name", "Interstellar space");
	OO_CHECK_EVAL("Object.keys(info(0, -1)).join()", "economy,name,coordinates,internalCoordinates,galaxyID,systemID");
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
		expected += key;
		expected += ",";
	}
	expected += "coordinates,internalCoordinates,galaxyID,systemID";
	sUniverse->_interstellar = YES;
	sUniverse->_currentSystemData = oo::PList(std::move(data));
	OO_CHECK_EVAL("Object.keys(info(0, -1)).join()", expected.c_str());
	OO_CHECK_EVAL("Object.keys(info(0, -1)).length", "44");
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
	OO_CHECK(ooscript::isInRequest(sContext));
}


OO_TEST_MAIN()
