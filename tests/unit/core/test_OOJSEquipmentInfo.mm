/*	test_OOJSEquipmentInfo.mm
	Unit tests for the EquipmentInfo JS binding (src/Core/Scripting/OOJSEquipmentInfo.h/.mm) and the
	JS glue of OOEquipmentType: bead oo-supk, converted the way bead oo-ppc converted OOJSVector
	(proposed ADR-0056 amendments oo-ppc and oo-6ia4); the type's façade was deleted, so a type
	reaches the engine as a PList Object node holding the C++ type.

	As test_OOJSShipGroup.mm does (amendment oo-6ia4, item 7), it runs the JS class in a real
	QuickJS-ng context, links the game's own objects for the binding, its bridge, the engine's
	class registry (OOJSClasses.mm), the engine's exception translator
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

#import "OOEquipmentType.h"
#import "OOColor.h"
#import "OOWeakReference.h"
#include <objc/runtime.h>
#include <quickjs.h>
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#import "OOObjCPList.h"


// What the engine sends an Objective-C object by selector for its JS value (the equipment type's
// façade answered it until it was deleted; the engine stand-in below still sends it).
@interface OOObject (OOJSTestGlue)
- (JSValue) oo_jsValueInContext:(JSContext *)context;
@end



#import "OOJSEquipmentInfo.h"

#include "oo_test.hpp"

#include <cmath>
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


// The universe as the code under test sees it: a stand-in for the C++ class (its Objective-C facade,
// deleted, was what this stood in for), with the header's names and signatures.
class Universe
{
public:
	oo::PList getEquipmentData();
	oo::PList getEquipmentDataOutfitting();
};

oo::PList Universe::getEquipmentData()	{ return EquipmentData(); }
oo::PList Universe::getEquipmentDataOutfitting()	{ return EquipmentData(); }


Universe *gSharedUniverse = nil;


#import "OOCacheManager.h"

// The cache manager is C++ since its facade was deleted: a C++ stand-in with the Objective-C
// stand-in's answers.
OOCacheManager *OOCacheManager::sharedCache()
{
	static OOCacheManager *shared = new OOCacheManager;
	return shared;
}
OOCacheManager::~OOCacheManager()  {}
void OOCacheManager::setPList(const oo::PList &value, const std::string &key, const std::string &cache)  { (void)value; (void)key; (void)cache; }


#import "OOScript.h"


// OOScript's members that OOEquipmentType.mm calls (the Objective-C OOScript stand-in until its
// facade was deleted), and the rest of its virtual members, for the vtable.
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
// PLAYER: C++ since the Objective-C player this stood in for was deleted: the members the code
// under test calls, declared as the game headers declare them (the test imports none that defines
// the classes), with the stand-in's answers. The ship is C++ too.
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
	if (eqKey == "EQ_SCOOPER")  [OOException raise:OOInvalidArgumentException format:"price %s", "boom"];
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

// The one context (OOJSAcquireContext(), which OOJSClasses.mm registers classes through).
JSContext *gOOJSMainThreadContext = nullptr;

// The class registry's (OOJSClasses.mm, linked).
const char *OOJSClassName(JSClassID classID);


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


// The engine's: the pending exception, else an uncatchable error, which ends the script.
JSValue OOJSNativeFailure(JSContext *context)
{
	if (JS_HasException(context))  return JS_EXCEPTION;
	JSValue error = JS_NewError(context);
	JS_SetUncatchableError(context, error);
	return JS_Throw(context, error);
}


// OOJSClasses.mm reports what class set-up left pending; the test drops it.
void OOJSReportPendingException(JSContext *context)
{
	JS_FreeValue(context, JS_GetException(context));
}


// Property IDs, which OOJSClasses.mm records: interned for the life of the process, as the engine's.
JSAtom cxx_OOJSIDFromString(const std::string &string)
{
	return JS_NewAtomLen(gOOJSMainThreadContext, string.data(), string.size());
}


std::optional<std::string> cxx_OOStringFromJSValue(JSContext *context, JSValueConst value);

// The engine's: rounded to nearest; NaN or out of range is an error.
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


// A JS value as a property list, as far as the binding hands one over: null, a string, a number,
// an array of those, or an EquipmentInfo (its equipment type, as an object).
oo::PList cxx_OOJSPListFromJSValue(JSContext *context, JSValueConst value)
{
	if (JS_IsNull(value) || JS_IsUndefined(value))  return oo::PList();
	if (JS_IsString(value))  return oo::PList(cxx_OOStringFromJSValue(context, value).value_or(std::string()));
	if (JS_IsBool(value))  return oo::PList(JS_VALUE_GET_BOOL(value) != 0);
	if (JS_IsNumber(value))
	{
		double number = 0;
		JS_ToFloat64(context, &number, value);
		return oo::PList(number);
	}
	if (JS_IsArray(value))
	{
		std::int64_t length = 0;
		JS_GetLength(context, value, &length);
		oo::PList::Array array;
		for (std::int64_t i = 0; i < length; i++)
		{
			JSValue element = JS_GetPropertyUint32(context, value, static_cast<std::uint32_t>(i));
			array.push_back(cxx_OOJSPListFromJSValue(context, element));
			JS_FreeValue(context, element);
		}
		return oo::PList(std::move(array));
	}
	const char *jsClass = OOJSClassName(JS_GetClassID(value));
	if (jsClass != nullptr && std::strcmp(jsClass, "EquipmentInfo") == 0)  return OOEquipmentTypeObjectNode(static_cast<OOEquipmentType *>(static_cast<oo::RefCounted *>(JS_GetOpaque(value, JS_GetClassID(value)))));
	return oo::PList(std::string("[object]"));
}


JSValue OOJSValueFromNativeObject(JSContext *context, id object);

// A property list as JavaScript, as far as the binding hands one over: null, a string, a number,
// a boolean, an object (its JS object), or an array or dictionary of those.
JSValue OOJSValueFromPList(JSContext *context, const oo::PList &plist)
{
	if (const std::string *str = plist.getIf<std::string>())  return JS_NewStringLen(context, str->data(), str->size());
	if (const bool *boolean = plist.getIf<bool>())  return JS_NewBool(context, *boolean);
	if (plist.isNumber())  return JS_NewNumber(context, plist.doubleValue());
	if (const oo::PList::Object *node = plist.getIf<oo::PList::Object>())	// a C++ object that is its own JS glue, as the engine asks it
	{
		if (OOJSPrivateObject *glue = dynamic_cast<OOJSPrivateObject *>(node->get()))  return OOJSValueFromCxxObject(context, glue);
	}
	if (id object = oo::ObjectIn(plist))  return OOJSValueFromNativeObject(context, object);
	if (const oo::PList::Array *array = plist.getIf<oo::PList::Array>())
	{
		JSValue object = JS_NewArray(context);
		std::uint32_t i = 0;
		for (const oo::PList &element : *array)  JS_SetPropertyUint32(context, object, i++, OOJSValueFromPList(context, element));
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


namespace {
std::map<JSClassID, int> sConverters;
}


PlayerEntity *OOPlayerForScripting(void)
{
	return gOOPlayer;
}


void OOJSReportBadPropertySelector(JSContext *context, JSValueConst, int, const JSCFunctionListEntry *, size_t)
{
	cxx_OOJSReportError(context, "bad property selector");
}


void OOJSReportBadPropertyValue(JSContext *context, JSValueConst, int, const JSCFunctionListEntry *, size_t, JSValueConst)
{
	cxx_OOJSReportError(context, "bad property value");
}


typedef oo::PList (*OOJSClassConverterCallback)(JSContext *context, JSValueConst object);

void OOJSRegisterObjectConverter(JSClassID classID, OOJSClassConverterCallback)
{
	sConverters[classID]++;
}


// The engine's object getter: the JS class must be the required one (EquipmentInfo has no
// subclasses), and the underlying object must be of the required Objective-C class.
BOOL OOJSObjectGetterImplPRIVATE(JSContext *context, JSValueConst object, JSClassID requiredClassID, Class requiredObjCClass, const char *, id *outObject)
{
	JSClassID actualClassID = JS_GetClassID(object);
	if (actualClassID != requiredClassID)
	{
		cxx_OOJSReportError(context, "Native method expected %s, got %s.", OOJSClassName(requiredClassID), cxx_OOStringFromJSValue(context, object).value_or("(null)").c_str());
		return NO;
	}
	*outObject = [(id)JS_GetOpaque(object, actualClassID) weakRefUnderlyingObject];
	if (*outObject != nil && ![*outObject isKindOfClass:requiredObjCClass])
	{
		cxx_OOJSReportError(context, "Native method expected %s from %s.", class_getName(requiredObjCClass), OOJSClassName(requiredClassID));
		*outObject = nil;
		return NO;
	}
	return YES;
}


// The engine's native-object conversion: the object's own JS value, null for nil.
JSValue OOJSValueFromNativeObject(JSContext *context, id object)
{
	if (object == nil)  return JS_NULL;
	return [object oo_jsValueInContext:context];
}


// The JS class check of the engine's C++ getter (OOJSPrivateObject.cpp, linked; its slot holds the
// C++ equipment type) is the class registry's (OOJSClasses.mm, linked): no subclass of
// EquipmentInfo is registered.


JSValue OOJSObjectWrapperToString(JSContext *context, JSValueConst, int, JSValueConst *)
{
	return JS_NewString(context, "[EquipmentInfo]");
}


JSValue OOJSUnconstructableConstruct(JSContext *context, JSValueConst, int, JSValueConst *)
{
	cxx_OOJSReportError(context, "unconstructable");
	return JS_EXCEPTION;
}


int sFinalized = 0;

// The shared finalizer, counted. EquipmentInfo's slot holds the C++ type, which the engine's C++
// finalizer (OOJSPrivateObject.cpp, linked) releases.
void OOJSObjectWrapperFinalize(JSRuntime *, JSValueConst)
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


oo::PList OOJSBasicPrivateObjectConverter(JSContext *, JSValueConst)
{
	return oo::PList();
}


// MARK: The context -------------------------------------------------------------------------------

namespace {

JSRuntime *sRuntime;
JSContext *sContext;
JSValue sGlobal = JS_UNDEFINED;
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

	sRuntime = JS_NewRuntime();
	JS_SetMemoryLimit(sRuntime, 8u * 1024u * 1024u);
	sContext = JS_NewContext(sRuntime);
	gOOJSMainThreadContext = sContext;
	sGlobal = JS_GetGlobalObject(sContext);
	InitOOJSEquipmentInfo(sContext, sGlobal);
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


// What a JS object's private slot holds.
oo::RefCounted *SlotOf(JSValueConst object)
{
	return static_cast<oo::RefCounted *>(JS_GetOpaque(object, JS_GetClassID(object)));
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
	JSValue first = fuel->jsValueInContext(sContext);
	JSValue second = fuel->jsValueInContext(sContext);
	OO_CHECK(JS_IsObject(first) && JS_VALUE_GET_PTR(first) == JS_VALUE_GET_PTR(second));
	OO_CHECK(SlotOf(first) == static_cast<oo::RefCounted *>(fuel));
	const char *infoForFuel = "EquipmentInfo.infoForKey('EQ_FUEL')";
	JSValue fromScript = JS_Eval(sContext, infoForFuel, std::strlen(infoForFuel), "test.js", JS_EVAL_TYPE_GLOBAL);
	OO_CHECK(JS_IsObject(fromScript) && JS_VALUE_GET_PTR(fromScript) == JS_VALUE_GET_PTR(first));
	// Clearing another object leaves it; clearing its own makes a new one next time.
	fuel->clearJSSelf(sGlobal);
	JSValue again = fuel->jsValueInContext(sContext);
	OO_CHECK(JS_VALUE_GET_PTR(again) == JS_VALUE_GET_PTR(first));
	fuel->clearJSSelf(first);
	JSValue third = fuel->jsValueInContext(sContext);
	OO_CHECK(JS_IsObject(third) && JS_VALUE_GET_PTR(third) != JS_VALUE_GET_PTR(first));
	OO_CHECK(SlotOf(third) == static_cast<oo::RefCounted *>(fuel));
	JS_FreeValue(sContext, third);
	JS_FreeValue(sContext, again);
	JS_FreeValue(sContext, fromScript);
	JS_FreeValue(sContext, second);
	JS_FreeValue(sContext, first);
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
	JSValue missileValue = missile->jsValueInContext(sContext);
	JSValue key = JS_NewString(sContext, "EQ_MISSILE");
	JSValue damagedKey = JS_NewString(sContext, "EQ_MISSILE_DAMAGED");
	JSValue unknownKey = JS_NewString(sContext, "EQ_SOMETHING");

	OO_CHECK(JSValueToEquipmentType(sContext, missileValue) == missile);
	OO_CHECK(JSValueToEquipmentType(sContext, key) == missile);
	OO_CHECK(JSValueToEquipmentType(sContext, unknownKey) == nil);
	OO_CHECK(JSValueToEquipmentType(sContext, JS_NULL) == nil);
	OO_CHECK(JSValueToEquipmentKey(sContext, missileValue) == std::optional<std::string>("EQ_MISSILE"));
	OO_CHECK(JSValueToEquipmentKey(sContext, unknownKey) == std::nullopt);

	BOOL exists = NO;
	OO_CHECK(JSValueToEquipmentKeyRelaxed(sContext, missileValue, &exists) == std::optional<std::string>("EQ_MISSILE") && exists == YES);
	OO_CHECK(JSValueToEquipmentKeyRelaxed(sContext, key, &exists) == std::optional<std::string>("EQ_MISSILE") && exists == YES);
	OO_CHECK(JSValueToEquipmentKeyRelaxed(sContext, unknownKey, &exists) == std::optional<std::string>("EQ_SOMETHING") && exists == NO);
	OO_CHECK(JSValueToEquipmentKeyRelaxed(sContext, damagedKey, &exists) == std::nullopt && exists == NO);	// _DAMAGED is refused
	OO_CHECK(JSValueToEquipmentKeyRelaxed(sContext, JS_NewInt32(sContext, 3), &exists) == std::nullopt && exists == NO);
	OO_CHECK(JSValueToEquipmentKeyRelaxed(sContext, key, nullptr) == std::optional<std::string>("EQ_MISSILE"));
	OO_CHECK_EQ(sProfileDepth, 0);
	JS_FreeValue(sContext, unknownKey);
	JS_FreeValue(sContext, damagedKey);
	JS_FreeValue(sContext, key);
	JS_FreeValue(sContext, missileValue);
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
}


OO_TEST_MAIN()
