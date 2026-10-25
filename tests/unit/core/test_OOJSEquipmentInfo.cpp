/*	test_OOJSEquipmentInfo.mm
	Unit tests for the EquipmentInfo JS binding (src/Core/Scripting/OOJSEquipmentInfo.h/.mm) and the
	JS glue of OOEquipmentType: bead oo-supk, converted the way bead oo-ppc converted OOJSVector
	(proposed ADR-0056 amendments oo-ppc and oo-6ia4); the type's façade was deleted by bead
	oo-9ht.28, so a type reaches the engine as a PList Object node holding the C++ type.

	As test_OOJSShipGroup.mm does (amendment oo-6ia4, item 7), it runs the JS class in a real
	context on the game's own façade backend (ooscript/JSEngine_quickjs.cpp), links the game's own
	objects for the binding, its bridge, the engine's exception translator
	(OOJSEngineNativeWrappers.mm) and the converted classes it uses (OOEquipmentType and OOColor,
	reached through their façades before the conversion and as C++ after it), and stands in for
	what the equipment types reach (the universe's equipment data, as test_OOEquipmentType.mm gives
	it, the cache, the script loader, the legacy-condition sanitizer, the standards switches) and
	for the player and the engine functions the binding links against, with the engine headers'
	linkage. The engine's native-object conversion asks the object for -oo_jsValueInContext:, as
	the engine does, so the category's JS object is what the script sees. The expectations were
	written against the Objective-C file and run on it first; they pin the JS-visible behaviour
	(every property, the display colour and effective tech level both ways, the prototype,
	infoForKey(), allEquipment, a native's exception), the C functions other bindings call
	(JSValueToEquipmentType(), JSValueToEquipmentKey(), JSValueToEquipmentKeyRelaxed()) and what
	the category answers the engine. Run: bash tools/check-core-tests.sh
*/

#include "OOEquipmentType.h"
#include "OOColor.h"
#include "ooscript/JSEngine.hpp"
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#include "OOObjCPList.h"





#include "OOJSEquipmentInfo.h"

#include "oo_test.hpp"

#include <cstdarg>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>


// MARK: The game around the equipment types (as test_OOEquipmentType.mm gives it) -----------------

namespace {

std::vector<std::string> gLog;
BOOL gEnforceStandards = NO;
int gDeprecations = 0;

oo::PList Dict(std::initializer_list<std::pair<const char *, oo::PList>> entries)
{
	oo::PList::Dict dict;
	for (const auto &[key, value] : entries)  dict[key] = value;
	return oo::PList(std::move(dict));
}


oo::PList Item(int techLevel, int price, const char *name, const char *key, const char *description, oo::PList extra = oo::PList())
{
	oo::PList::Array item{ oo::PList(techLevel), oo::PList(price), oo::PList(name), oo::PList(key), oo::PList(description) };
	if (!extra.isNull())  item.push_back(extra);
	return oo::PList(std::move(item));
}


oo::PList Strings(std::initializer_list<const char *> strings)
{
	oo::PList::Array array;
	for (const char *s : strings)  array.push_back(oo::PList(s));
	return oo::PList(std::move(array));
}


oo::PList EquipmentData()
{
	return oo::PList(oo::PList::Array{
		Item(1, 300, "Fuel", "EQ_FUEL", "Refuel"),
		Item(2, 250, "Missile", "EQ_MISSILE", "A missile", Dict({ { "damage_probability", oo::PList(0.5) } })),
		Item(3, 500, "Renovation", "EQ_RENOVATION", "Clean up"),
		Item(6, 4000, "Pulse laser", "EQ_WEAPON_PULSE_LASER", "Pew", Dict({
			{ "weapon_info", Dict({ { "range", oo::PList(15000) }, { "damage", oo::PList(10) } }) },
			{ "display_color", oo::PList("greenColor") } })),
		Item(99, 7000, "Shield booster", "EQ_SHIELD_BOOSTER", "More shield", Dict({
			{ "available_to_all", oo::PList(true) }, { "available_to_NPCs", oo::PList(false) }, { "requires_clean", oo::PList(true) },
			{ "requires_full_fuel", oo::PList(true) }, { "portable_between_ships", oo::PList(true) }, { "visible", oo::PList(false) },
			{ "can_carry_multiple", oo::PList(true) }, { "requires_cargo_space", oo::PList(2) },
			{ "installation_time", oo::PList(600) }, { "provides", Strings({ "shields", "boost" }) },
			{ "requires_equipment", Strings({ "EQ_B", "EQ_A" }) }, { "requires_any_equipment", oo::PList("EQ_ONE") },
			{ "incompatible_with_equipment", oo::PList("EQ_NAVAL") }, { "script_info", Dict({ { "x", oo::PList(1) } }) },
			{ "script", oo::PList("good.js") }, { "fast_affinity_defensive", oo::PList(true) },
			{ "default_activate_key", oo::PList(oo::PList::Array{ Dict({ { "key", oo::PList("a") } }) }) } })),
		Item(4, 800, "Scooper", "EQ_SCOOPER", "Scoops", Dict({ { "repair_time", oo::PList(30) },
			{ "requires_not_clean", oo::PList(true) }, { "requires_non_full_fuel", oo::PList(true) }, { "requires_empty_pylon", oo::PList(true) },
			{ "requires_mounted_pylon", oo::PList(true) }, { "requires_free_passenger_berth", oo::PList(true) }, { "available_to_player", oo::PList(false) },
			{ "fast_affinity_offensive", oo::PList(true) } })),
	});
}

}	// namespace


// The universe as the code under test sees it: a stand-in for the C++ class (bead oo-ql9rn deleted
// the Objective-C facade this stood in for), with the header's names and signatures.
class Universe
{
public:
	oo::PList getEquipmentData();
	oo::PList getEquipmentDataOutfitting();
};

oo::PList Universe::getEquipmentData()	{ return EquipmentData(); }
oo::PList Universe::getEquipmentDataOutfitting()	{ return EquipmentData(); }


Universe *gSharedUniverse = nil;


#include "OOCacheManager.h"

// The cache manager is C++ since bead oo-9ht.31 deleted its facade: a C++ stand-in with the Objective-C
// stand-in's answers.
OOCacheManager *OOCacheManager::sharedCache()
{
	static OOCacheManager *shared = new OOCacheManager;
	return shared;
}
OOCacheManager::~OOCacheManager()  {}
void OOCacheManager::setPList(const oo::PList &value, const std::string &key, const std::string &cache)  { (void)value; (void)key; (void)cache; }


#include "OOScript.h"


// OOScript's members that OOEquipmentType.mm calls (the Objective-C OOScript stand-in until bead
// oo-9ht.133 deleted the facade), and the rest of its virtual members, for the vtable.
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
void OOScriptAutorelease(oo::Ref<OOScript>)					{}
oo::Ref<OOScript> OOScript::jsScriptFromFileNamed(const std::string &fileName, const oo::PList &properties)
{
	(void)properties;
	return (fileName == "good.js") ? oo::makeRef<OOScript>() : nullptr;
}


/*	The player: its fuel and charge rate, renovation costs, the price scripts adjust, and its
	mission variables (the variable tech levels). Adjusting the price of "EQ_SCOOPER" raises, and of
	"EQ_MISSILE" while _throwCxx is set throws a C++ exception, so the test sees what an exception
	under a native becomes.
*/
// PLAYER: C++ since bead oo-9ht.177 deleted the Objective-C player this stood in for: the members
// the code under test calls, declared as the game headers declare them (the test imports none
// that defines the classes), with the stand-in's answers. The ship is C++ since bead oo-9ht.144.
class Entity
{
public:

};

class ShipEntity : public Entity
{
public:
	OOFuelQuantity getFuel();
};

class PlayerEntity : public ShipEntity
{
public:
	void setScriptTarget(::ShipEntity *ship);
	GLfloat fuelChargeRate();
	double renovationCosts();
	OOCreditsQuantity adjustPriceByScriptForEqKey(const std::string &eqKey, OOCreditsQuantity price);
	oo::PList processKeyCode(const oo::PList &key_def);
	std::optional<std::string> validateKey(const std::string &key, const oo::PList &check_keys);
	oo::PList missionVariableForKey(const std::string &key);
	void setMissionVariable(const oo::PList &value, const std::string &key);

	OOFuelQuantity _fuel = {};
	float _fuelChargeRate = {};
	double _renovationCosts = {};
	oo::PList::Dict _missionVariables;
	BOOL _throwCxx = {};
};

void PlayerEntity::setScriptTarget(::ShipEntity *target)  { (void)target; }
OOFuelQuantity ShipEntity::getFuel()  { return static_cast<PlayerEntity *>(this)->_fuel; }
GLfloat PlayerEntity::fuelChargeRate()  { return _fuelChargeRate; }
double PlayerEntity::renovationCosts()  { return _renovationCosts; }
OOCreditsQuantity PlayerEntity::adjustPriceByScriptForEqKey(const std::string &eqKey, OOCreditsQuantity price)
{
	if (eqKey == "EQ_SCOOPER")  OORaiseException(OOInvalidArgumentException, "price %s", "boom");
	if (eqKey == "EQ_MISSILE" && _throwCxx)  throw std::runtime_error("cxx boom");
	return price * 2;
}
oo::PList PlayerEntity::processKeyCode(const oo::PList &key_def)  { return key_def; }
std::optional<std::string> PlayerEntity::validateKey(const std::string &key, const oo::PList &check_keys)  { (void)key; (void)check_keys; return std::nullopt; }
oo::PList PlayerEntity::missionVariableForKey(const std::string &key)
{
	auto it = _missionVariables.find(key);
	return it != _missionVariables.end() ? it->second : oo::PList();
}
void PlayerEntity::setMissionVariable(const oo::PList &value, const std::string &key)
{
	if (value.isNull())  _missionVariables.erase(key);
	else  _missionVariables[key] = value;
}

PlayerEntity *gOOPlayer = nullptr;


void cxx_OOStandardsDeprecated(const std::string &message)
{
	(void)message;
	gDeprecations++;
}

extern "C" BOOL OOEnforceStandards(void)
{
	return gEnforceStandards;
}

oo::PList OOSanitizeLegacyScriptConditions(const oo::PList &conditions, const std::optional<std::string> &context)
{
	(void)context;
	return conditions;
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


// A JS value as a property list, as far as the binding hands one over: null, a string, a number,
// an array of those, or an EquipmentInfo (its equipment type, as an object).
oo::PList cxx_OOJSPListFromJSValue(ooscript::Context context, ooscript::Value value)
{
	if (ooscript::isNullOrUndefined(value))  return oo::PList();
	if (ooscript::isString(value))  return oo::PList(cxx_OOStringFromJSValue(context, value).value_or(std::string()));
	if (ooscript::isBoolean(value))  return oo::PList(ooscript::toBoolean(value));
	if (ooscript::isNumber(value))
	{
		double number = 0;
		ooscript::valueToNumber(context, value, &number);
		return oo::PList(number);
	}
	ooscript::Object object = ooscript::toObject(value);
	if (ooscript::isArrayObject(context, object))
	{
		std::uint32_t length = 0;
		ooscript::getArrayLength(context, object, &length);
		oo::PList::Array array;
		for (std::uint32_t i = 0; i < length; i++)
		{
			ooscript::Value element = ooscript::undefinedValue();
			ooscript::getElement(context, object, static_cast<std::int32_t>(i), &element);
			array.push_back(cxx_OOJSPListFromJSValue(context, element));
		}
		return oo::PList(std::move(array));
	}
	const ooscript::ClassDef *jsClass = ooscript::getObjectClass(context, object);
	if (jsClass != nullptr && std::strcmp(jsClass->name, "EquipmentInfo") == 0)  return OOEquipmentTypeObjectNode(static_cast<OOEquipmentType *>(static_cast<oo::RefCounted *>(ooscript::getPrivate(context, object))));
	return oo::PList(std::string("[object]"));
}



// A property list as JavaScript, as far as the binding hands one over: null, a string, a number,
// a boolean, an object (its JS object), or an array or dictionary of those.
ooscript::Value OOJSValueFromPList(ooscript::Context context, const oo::PList &plist)
{
	if (const std::string *str = plist.getIf<std::string>())
	{
		ooscript::String js = ooscript::newStringCopyN(context, str->data(), str->size());
		return js != nullptr ? ooscript::stringValue(js) : ooscript::nullValue();
	}
	if (const bool *boolean = plist.getIf<bool>())  return ooscript::booleanValue(*boolean);
	if (plist.isNumber())  return ooscript::numberValue(plist.doubleValue());
	if (const oo::PList::Object *node = plist.getIf<oo::PList::Object>())	// a C++ object that is its own JS glue, as the engine asks it
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


namespace {
std::map<ooscript::ClassDef *, int> sConverters;
}


extern "C" {

PlayerEntity *OOPlayerForScripting(void)
{
	return gOOPlayer;
}


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
// oo-6symp.3, whose slot holds the C++ equipment type): no subclass of EquipmentInfo is registered.
BOOL OOJSIsSubclass(ooscript::ClassDef *putativeSubclass, ooscript::ClassDef *superclass)
{
	return putativeSubclass == superclass;
}


bool OOJSObjectWrapperToString(ooscript::Context context, ooscript::CallArgs &args)
{
	args.setRval(ooscript::stringValue(ooscript::newStringCopyZ(context, "[EquipmentInfo]")));
	return true;
}


bool OOJSUnconstructableConstruct(ooscript::Context context, ooscript::CallArgs &)
{
	cxx_OOJSReportError(context, "unconstructable");
	return false;
}


int sFinalized = 0;

void OOJSObjectWrapperFinalize(ooscript::Context, ooscript::Object)
{
	sFinalized++;
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
PlayerEntity *sPlayer = nullptr;


void SetUpContext()
{
	if (sContext != nullptr)  return;
	gSharedUniverse = new Universe();	// kept for the life of the test
	sPlayer = new PlayerEntity;
	sPlayer->_fuel = 30;
	sPlayer->_fuelChargeRate = 1.5f;
	sPlayer->_renovationCosts = 1234.5;
	gOOPlayer = sPlayer;
	OOEquipmentType::loadEquipment();

	sRuntime = ooscript::newRuntime(8u * 1024u * 1024u);
	sContext = ooscript::newContext(sRuntime, 8192);
	ooscript::beginRequest(sContext);
	sGlobal = ooscript::getGlobalObject(sContext);
	ooscript::initStandardClasses(sContext, sGlobal);
	InitOOJSEquipmentInfo(sContext, sGlobal);
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
	OO_CHECK_EQ(sConverters.size(), static_cast<std::size_t>(1));
	OO_CHECK_EVAL("typeof EquipmentInfo", "function");
	OO_CHECK_EVAL("new EquipmentInfo()", "threw: unconstructable");
	OO_CHECK_EVAL("EquipmentInfo.infoForKey('EQ_FUEL') instanceof EquipmentInfo", "true");
	OO_CHECK_EVAL("String(EquipmentInfo.infoForKey('EQ_FUEL'))", "[EquipmentInfo EQ_FUEL \"Fuel\"]");
	OO_CHECK_EVAL("Object.keys(EquipmentInfo.prototype).length", "38");
}


OO_TEST(categoryAnswersTheEngine)
{
	SetUpContext();
	OOEquipmentType *fuel = OOEquipmentType::equipmentTypeWithIdentifier("EQ_FUEL").get();
	OO_CHECK(OOJSEquipmentInfoJSClassName() == std::optional<std::string>("EquipmentInfo"));
	// One JS object per type, made on first use, with the type (retained) in its private slot.
	ooscript::Value first = fuel->jsValueInContext(sContext);
	ooscript::Value second = fuel->jsValueInContext(sContext);
	OO_CHECK(ooscript::isObject(first) && ooscript::toObject(first) == ooscript::toObject(second));
	OO_CHECK(ooscript::getPrivate(sContext, ooscript::toObject(first)) == static_cast<oo::RefCounted *>(fuel));
	ooscript::Value fromScript = ooscript::undefinedValue();
	const char *infoForFuel = "EquipmentInfo.infoForKey('EQ_FUEL')";
	ooscript::evaluateScript(sContext, sGlobal, infoForFuel, static_cast<unsigned>(std::strlen(infoForFuel)), "test.js", 1, &fromScript);
	OO_CHECK(ooscript::isObject(fromScript) && ooscript::toObject(fromScript) == ooscript::toObject(first));
	// Clearing another object leaves it; clearing its own makes a new one next time.
	fuel->clearJSSelf(sGlobal);
	OO_CHECK(ooscript::toObject(fuel->jsValueInContext(sContext)) == ooscript::toObject(first));
	fuel->clearJSSelf(ooscript::toObject(first));
	ooscript::Value third = fuel->jsValueInContext(sContext);
	OO_CHECK(ooscript::isObject(third) && ooscript::toObject(third) != ooscript::toObject(first));
	OO_CHECK(ooscript::getPrivate(sContext, ooscript::toObject(third)) == static_cast<oo::RefCounted *>(fuel));
}


OO_TEST(properties)
{
	SetUpContext();
	OO_CHECK_EVAL("(function () { var e = EquipmentInfo.infoForKey('EQ_SHIELD_BOOSTER'); return [e.equipmentKey, e.name, e.description, e.techLevel, e.price, e.canCarryMultiple, e.canBeDamaged].join(); })()",
				  "EQ_SHIELD_BOOSTER,Shield booster,More shield,99,7000,true,true");
	OO_CHECK_EVAL("(function () { var e = EquipmentInfo.infoForKey('EQ_SHIELD_BOOSTER'); return [e.isAvailableToAll, e.isAvailableToNPCs, e.isAvailableToPlayer, e.isExternalStore, e.isPortableBetweenShips, e.isVisible].join(); })()",
				  "true,false,true,false,true,false");
	OO_CHECK_EVAL("(function () { var e = EquipmentInfo.infoForKey('EQ_SHIELD_BOOSTER'); return [e.requiresCleanLegalRecord, e.requiresNonCleanLegalRecord, e.requiresFullFuel, e.requiresNonFullFuel, e.requiresEmptyPylon, e.requiresMountedPylon, e.requiresFreePassengerBerth].join(); })()",
				  "true,false,true,false,false,false,false");
	OO_CHECK_EVAL("(function () { var e = EquipmentInfo.infoForKey('EQ_SCOOPER'); return [e.requiresCleanLegalRecord, e.requiresNonCleanLegalRecord, e.requiresFullFuel, e.requiresNonFullFuel, e.requiresEmptyPylon, e.requiresMountedPylon, e.requiresFreePassengerBerth, e.isAvailableToPlayer].join(); })()",
				  "false,true,false,true,true,true,true,false");
	OO_CHECK_EVAL("(function () { var e = EquipmentInfo.infoForKey('EQ_SHIELD_BOOSTER'); return [e.fastAffinityDefensive, e.fastAffinityOffensive, EquipmentInfo.infoForKey('EQ_SCOOPER').fastAffinityOffensive].join(); })()",
				  "true,false,false");	// only a type with a script has affinities
	OO_CHECK_EVAL("JSON.stringify(EquipmentInfo.infoForKey('EQ_SHIELD_BOOSTER').provides)", "[\"shields\",\"boost\"]");
	OO_CHECK_EVAL("JSON.stringify([EquipmentInfo.infoForKey('EQ_SHIELD_BOOSTER').requiresEquipment, EquipmentInfo.infoForKey('EQ_SHIELD_BOOSTER').requiresAnyEquipment, EquipmentInfo.infoForKey('EQ_SHIELD_BOOSTER').incompatibleEquipment])",
				  "[[\"EQ_A\",\"EQ_B\"],[\"EQ_ONE\"],[\"EQ_NAVAL\"]]");
	OO_CHECK_EVAL("JSON.stringify([EquipmentInfo.infoForKey('EQ_FUEL').requiresEquipment, EquipmentInfo.infoForKey('EQ_FUEL').incompatibleEquipment])", "[null,null]");
	OO_CHECK_EVAL("[EquipmentInfo.infoForKey('EQ_SHIELD_BOOSTER').requiredCargoSpace, EquipmentInfo.infoForKey('EQ_SCOOPER').repairTime].join()", "2,30");
	// The installation time is the price plus 600 when there is none.
	OO_CHECK_EVAL("[EquipmentInfo.infoForKey('EQ_SHIELD_BOOSTER').installationTime, EquipmentInfo.infoForKey('EQ_FUEL').installationTime].join()", "600,900");
	OO_CHECK_EVAL("EquipmentInfo.infoForKey('EQ_MISSILE').damageProbability", "0");	// a missile cannot be damaged
	OO_CHECK_EVAL("EquipmentInfo.infoForKey('EQ_SCOOPER').damageProbability", "1");
	OO_CHECK_EVAL("[EquipmentInfo.infoForKey('EQ_MISSILE').isExternalStore, EquipmentInfo.infoForKey('EQ_MISSILE').canCarryMultiple].join()", "true,true");
	OO_CHECK_EVAL("JSON.stringify(EquipmentInfo.infoForKey('EQ_SHIELD_BOOSTER').scriptInfo)", "{\"x\":1}");
	OO_CHECK_EVAL("JSON.stringify(EquipmentInfo.infoForKey('EQ_FUEL').scriptInfo)", "{}");	// empty rather than null
	OO_CHECK_EVAL("[EquipmentInfo.infoForKey('EQ_SHIELD_BOOSTER').scriptName, '|', EquipmentInfo.infoForKey('EQ_FUEL').scriptName].join('')", "good.js|");
	OO_CHECK_EVAL("JSON.stringify([EquipmentInfo.infoForKey('EQ_WEAPON_PULSE_LASER').weaponInfo.range, EquipmentInfo.infoForKey('EQ_FUEL').weaponInfo])", "[15000,{}]");
	OO_CHECK_EVAL("JSON.stringify(EquipmentInfo.infoForKey('EQ_SHIELD_BOOSTER').defaultActivateKey)", "[{\"key\":\"a\"}]");
	OO_CHECK_EVAL("EquipmentInfo.infoForKey('EQ_SHIELD_BOOSTER').defaultModeKey", "null");
	OO_CHECK_EVAL("JSON.stringify(EquipmentInfo.infoForKey('EQ_WEAPON_PULSE_LASER').displayColor)", "[0,1,0,1]");
	OO_CHECK_EVAL("EquipmentInfo.infoForKey('EQ_FUEL').displayColor", "null");
	// Read-only.
	OO_CHECK_EVAL("(function () { var e = EquipmentInfo.infoForKey('EQ_FUEL'); e.price = 1; return e.price; })()", "300");
}


OO_TEST(calculatedPrice)
{
	SetUpContext();
	// Fuel: what it costs to fill the tank (7.0 ly is 70 tenths) at the charge rate.
	OO_CHECK_EVAL("EquipmentInfo.infoForKey('EQ_FUEL').calculatedPrice", "18000");	// (70 - 30) * 300 * 1.5
	OO_CHECK_EVAL("EquipmentInfo.infoForKey('EQ_RENOVATION').calculatedPrice", "1234.5");
	OO_CHECK_EVAL("EquipmentInfo.infoForKey('EQ_SHIELD_BOOSTER').calculatedPrice", "14000");	// as the scripts adjust it
}


OO_TEST(writableProperties)
{
	SetUpContext();
	OO_CHECK_EVAL("(function () { var e = EquipmentInfo.infoForKey('EQ_FUEL'); e.displayColor = 'redColor'; return JSON.stringify(e.displayColor); })()", "[1,0,0,1]");
	OO_CHECK_EVAL("(function () { var e = EquipmentInfo.infoForKey('EQ_FUEL'); e.displayColor = null; return e.displayColor; })()", "null");
	OO_CHECK_EVAL("(function () { var e = EquipmentInfo.infoForKey('EQ_FUEL'); e.displayColor = 'not a colour'; return 'set'; })()", "threw: bad property value");

	// The effective tech level of a type whose tech level is 99 (deprecated, unless standards are
	// enforced): kept as a mission variable.
	gDeprecations = 0;
	OO_CHECK_EVAL("(function () { var e = EquipmentInfo.infoForKey('EQ_SHIELD_BOOSTER'); e.effectiveTechLevel = 7; return e.effectiveTechLevel; })()", "7");
	OO_CHECK(sPlayer->_missionVariables["mission_TL_FOR_EQ_SHIELD_BOOSTER"] == oo::PList("7"));
	OO_CHECK_EVAL("(function () { var e = EquipmentInfo.infoForKey('EQ_SHIELD_BOOSTER'); e.effectiveTechLevel = 40; return e.effectiveTechLevel; })()", "15");
	OO_CHECK_EVAL("(function () { var e = EquipmentInfo.infoForKey('EQ_SHIELD_BOOSTER'); e.effectiveTechLevel = -3; return e.effectiveTechLevel; })()", "0");
	OO_CHECK_EVAL("(function () { var e = EquipmentInfo.infoForKey('EQ_SHIELD_BOOSTER'); e.effectiveTechLevel = 'x'; return 'set'; })()", "threw: bad property value");
	OO_CHECK_EVAL("(function () { var e = EquipmentInfo.infoForKey('EQ_SHIELD_BOOSTER'); e.effectiveTechLevel = null; return e.effectiveTechLevel; })()", "99");
	OO_CHECK(sPlayer->_missionVariables.count("mission_TL_FOR_EQ_SHIELD_BOOSTER") == 0);
	OO_CHECK_EQ(gDeprecations, 9);	// the five sets, and the four reads (the type deprecates a tech level of 99 itself)
	sLastWarning.clear();
	OO_CHECK_EVAL("(function () { var e = EquipmentInfo.infoForKey('EQ_FUEL'); e.effectiveTechLevel = 3; return e.effectiveTechLevel; })()", "1");
	OO_CHECK_EQ(sLastWarning, std::string("Cannot modify effective tech level for EQ_FUEL, because its base tech level is not 99."));
	gEnforceStandards = YES;
	OO_CHECK_EVAL("(function () { var e = EquipmentInfo.infoForKey('EQ_SHIELD_BOOSTER'); e.effectiveTechLevel = 5; return e.effectiveTechLevel; })()", "99");
	OO_CHECK_EQ(sLastWarning, std::string("Cannot modify effective tech level for EQ_SHIELD_BOOSTER, because its base tech level is not 99."));
	gEnforceStandards = NO;
}


OO_TEST(prototypeAndOtherObjects)
{
	SetUpContext();
	// The prototype has no type: what a message to nil answered.
	OO_CHECK_EVAL("[EquipmentInfo.prototype.equipmentKey, EquipmentInfo.prototype.price, EquipmentInfo.prototype.canBeDamaged, EquipmentInfo.prototype.installationTime].join()", ",0,false,600");
	OO_CHECK_EVAL("JSON.stringify([EquipmentInfo.prototype.provides, EquipmentInfo.prototype.scriptInfo, EquipmentInfo.prototype.scriptName, EquipmentInfo.prototype.weaponInfo, EquipmentInfo.prototype.displayColor])", "[[],{},\"\",{},null]");
	OO_CHECK_EVAL("EquipmentInfo.prototype.calculatedPrice", "0");
	OO_CHECK_EVAL("Object.getOwnPropertyDescriptor(EquipmentInfo.prototype, 'name').get.call({})", "threw: Native method expected EquipmentInfo, got [object Object].");
}


OO_TEST(staticMembers)
{
	SetUpContext();
	OO_CHECK_EVAL("EquipmentInfo.infoForKey('EQ_NOTHING')", "null");
	OO_CHECK_EVAL("EquipmentInfo.infoForKey()", "threw: bad arguments: EquipmentInfo.infoForKey(0) - / string");
	OO_CHECK_EVAL("EquipmentInfo.allEquipment.map(function (e) { return e.equipmentKey; }).join()",
				  "EQ_FUEL,EQ_MISSILE,EQ_RENOVATION,EQ_WEAPON_PULSE_LASER,EQ_SHIELD_BOOSTER,EQ_SCOOPER");
	OO_CHECK_EVAL("EquipmentInfo.allEquipment[0] === EquipmentInfo.infoForKey('EQ_FUEL')", "true");
}


OO_TEST(cFunctions)
{
	SetUpContext();
	OOEquipmentType *missile = OOEquipmentType::equipmentTypeWithIdentifier("EQ_MISSILE").get();
	ooscript::Value missileValue = missile->jsValueInContext(sContext);
	ooscript::Value key = ooscript::stringValue(ooscript::newStringCopyZ(sContext, "EQ_MISSILE"));
	ooscript::Value damagedKey = ooscript::stringValue(ooscript::newStringCopyZ(sContext, "EQ_MISSILE_DAMAGED"));
	ooscript::Value unknownKey = ooscript::stringValue(ooscript::newStringCopyZ(sContext, "EQ_SOMETHING"));

	OO_CHECK(JSValueToEquipmentType(sContext, missileValue) == missile);
	OO_CHECK(JSValueToEquipmentType(sContext, key) == missile);
	OO_CHECK(JSValueToEquipmentType(sContext, unknownKey) == nil);
	OO_CHECK(JSValueToEquipmentType(sContext, ooscript::nullValue()) == nil);
	OO_CHECK(JSValueToEquipmentKey(sContext, missileValue) == std::optional<std::string>("EQ_MISSILE"));
	OO_CHECK(JSValueToEquipmentKey(sContext, unknownKey) == std::nullopt);

	BOOL exists = NO;
	OO_CHECK(JSValueToEquipmentKeyRelaxed(sContext, missileValue, &exists) == std::optional<std::string>("EQ_MISSILE") && exists == YES);
	OO_CHECK(JSValueToEquipmentKeyRelaxed(sContext, key, &exists) == std::optional<std::string>("EQ_MISSILE") && exists == YES);
	OO_CHECK(JSValueToEquipmentKeyRelaxed(sContext, unknownKey, &exists) == std::optional<std::string>("EQ_SOMETHING") && exists == NO);
	OO_CHECK(JSValueToEquipmentKeyRelaxed(sContext, damagedKey, &exists) == std::nullopt && exists == NO);	// _DAMAGED is refused
	OO_CHECK(JSValueToEquipmentKeyRelaxed(sContext, ooscript::numberValue(3), &exists) == std::nullopt && exists == NO);
	OO_CHECK(JSValueToEquipmentKeyRelaxed(sContext, key, nullptr) == std::optional<std::string>("EQ_MISSILE"));
	OO_CHECK_EQ(sProfileDepth, 0);
}


OO_TEST(nativeExceptions)
{
	SetUpContext();
	OO_CHECK_EVAL("EquipmentInfo.infoForKey('EQ_SCOOPER').calculatedPrice", "threw: Native exception: price boom");
	sPlayer->_throwCxx = YES;
	OO_CHECK_EVAL("EquipmentInfo.infoForKey('EQ_MISSILE').calculatedPrice", "threw: Native exception: cxx boom");
	sPlayer->_throwCxx = NO;
	OO_CHECK_EVAL("EquipmentInfo.infoForKey('EQ_MISSILE').calculatedPrice", "500");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
	OO_CHECK(ooscript::isInRequest(sContext));
}


OO_TEST_MAIN()
