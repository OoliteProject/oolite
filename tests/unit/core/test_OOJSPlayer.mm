/*	test_OOJSPlayer.mm
	Unit tests for the player JS binding (src/Core/Scripting/OOJSPlayer.h/.mm): bead oo-5rva,
	converted the way bead oo-ppc converted OOJSVector (proposed ADR-0056 amendment oo-ppc).

	As the binding tests of amendment oo-ppc item 6 do, it runs the JS class in a real QuickJS-ng
	context, and links the game's own objects for the binding, the engine's class registration
	(OOJSClasses.mm), its exception translator (OOJSEngineNativeWrappers.mm) and the random numbers
	it draws (legacy_random.c). It stands in for the player and a station (PlayerEntity and
	ShipEntity answer only the selectors the binding sends, and record what they are told), the
	universe (messages, speech, nearby systems), the display strings, the script event names and
	the engine functions the binding links against, with the engine headers' signatures
	(OOJSEngineCore.h, upstream #768's QuickJS-ng API; script event names are atoms). The
	expectations were written against the Objective-C file and run on it first; they pin the
	JS-visible behaviour: the Player class and the player object, every property both ways, each
	method with its arguments and errors (messages, reputations, the arrival report, speech,
	replaceShip(), setEscapePodDestination() in each of its forms, setPlayerRole()), the events
	the player is sent, and a native's exception. Run: bash tools/check-core-tests.sh
*/

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"
#include <objc/runtime.h>
#include "OOTypes.h"
#include "OOEntityEnums.h"
#include <quickjs.h>
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#import "OOObjCPList.h"


// MARK: The classes, as far as the binding sees them ----------------------------------------------

@class Entity;

// As ShipEntity.h and PlayerEntity.h declare them (the test imports neither).
typedef enum
{
	ALERT_CONDITION_DOCKED	= 0,
	ALERT_CONDITION_GREEN	= 1,
	ALERT_CONDITION_YELLOW	= 2,
	ALERT_CONDITION_RED		= 3
} OOAlertCondition;

typedef enum
{
	OOSPEECHSETTINGS_OFF = 0,
	OOSPEECHSETTINGS_COMMS = 1,
	OOSPEECHSETTINGS_ALL = 2
} OOSpeechSettings;

enum
{
	ALERT_FLAG_DOCKED				= 0x010,
	ALERT_FLAG_MASS_LOCK			= 0x020,
	ALERT_FLAG_TEMP					= 0x040,
	ALERT_FLAG_ALT					= 0x080,
	ALERT_FLAG_ENERGY				= 0x100,
	ALERT_FLAG_HOSTILES				= 0x200
};


@interface ShipEntity: OOObject
{
@public
	BOOL _isStation;
	OOEntityStatus _status;
}
- (BOOL) isStation;
- (OOEntityStatus) status;
@end


/*	The player. While _raise is set, -score raises, and while _throwCxx is set it throws a C++
	exception, so the test sees what an exception under a native becomes.
*/
@interface PlayerEntity: ShipEntity
{
@public
	std::optional<std::string> _commanderName;
	unsigned _score;
	double _credits;
	int _legalStatus;
	OOLegalStatusReason _bountyReason;
	OOAlertCondition _alertCondition;
	int _alertFlags;
	double _escapePodRescueTime;
	NSUInteger _trumbleCount;
	int _contractReputation, _passengerReputation, _parcelReputation;
	OODockingClearanceStatus _dockingClearanceStatus;
	std::vector<std::string> _roleWeights;
	std::vector<std::string> _events;
	std::vector<std::string> _report;
	std::string _endedScenario;
	OOSpeechSettings _speech;
	std::string _replacedWith;
	uint16_t _personality;
	ShipEntity *_dockTarget;
	BOOL _dockTargetSet;
	double _adjustTime;
	OOSystemID _targetSystem;
	std::string _lastRole;
	NSUInteger _lastRoleSlot;
	int _scriptTargetSets;
	BOOL _raise;
	BOOL _throwCxx;
}
- (void) setScriptTarget:(ShipEntity *)ship;
- (std::optional<std::string>) cxx_commanderName;
- (void) cxx_setCommanderName:(const std::optional<std::string> &)value;
- (unsigned) score;
- (void) setScore:(unsigned)value;
- (double) creditBalance;
- (void) setCreditBalance:(double)value;
- (int) legalStatus;
- (void) setBounty:(OOCreditsQuantity)amount withReason:(OOLegalStatusReason)reason;
- (OOAlertCondition) alertCondition;
- (int) alertFlags;
- (double) escapePodRescueTime;
- (void) setEscapePodRescueTime:(double)seconds;
- (NSUInteger) trumbleCount;
- (int) contractReputation;
- (int) passengerReputation;
- (int) parcelReputation;
- (void) increaseContractReputation:(unsigned)amount;
- (void) decreaseContractReputation:(unsigned)amount;
- (void) increasePassengerReputation:(unsigned)amount;
- (void) decreasePassengerReputation:(unsigned)amount;
- (void) increaseParcelReputation:(unsigned)amount;
- (void) decreaseParcelReputation:(unsigned)amount;
- (OODockingClearanceStatus) getDockingClearanceStatus;
- (std::vector<std::string>) cxx_roleWeights;
- (void) cxx_doScriptEvent:(JSAtom)message withPListArguments:(const std::vector<oo::PList> &)arguments;
- (void) doScriptEvent:(JSAtom)message withArgument:(id)argument;
- (BOOL) cxx_endScenario:(const std::string &)key;
- (void) cxx_addMessageToReport:(const std::string &)report;
- (OOSpeechSettings) isSpeechOn;
- (BOOL) cxx_replaceShipWithNamedShip:(const std::string &)shipName;
- (void) setEntityPersonalityInt:(uint16_t)value;
- (void) setDockTarget:(ShipEntity *)entity;
- (void) addToAdjustTime:(double)seconds;
- (void) setTargetSystemID:(OOSystemID)sid;
- (void) cxx_addRoleToPlayer:(const std::string &)role;
- (void) cxx_addRoleToPlayer:(const std::string &)role inSlot:(NSUInteger)slot;
@end


@interface Universe: OOObject
{
@public
	std::vector<std::string> _comms;
	std::vector<std::string> _console;
	std::vector<double> _counts;
	std::vector<std::string> _spoken;
	BOOL _speaking;
	int _stops;
	BOOL _interstellar;
	double _range;
	oo::PList _destinations;
}
- (void) cxx_addCommsMessage:(const std::optional<std::string> &)text forCount:(OOTimeDelta)count;
- (void) cxx_addMessage:(const std::optional<std::string> &)text forCount:(OOTimeDelta)count;
- (void) cxx_startSpeakingString:(const std::string &)text;
- (BOOL) isSpeaking;
- (void) stopSpeaking;
- (BOOL) inInterstellarSpace;
- (oo::PList) cxx_nearbyDestinationsWithinRange:(double)range;
@end


#import "OOJSPlayer.h"
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

std::map<JSAtom, std::string> sJSIDNames;

std::string EventName(JSAtom propID)
{
	auto found = sJSIDNames.find(propID);
	return found != sJSIDNames.end() ? found->second : "?";
}


std::string Describe(const oo::PList &plist)
{
	if (plist.isNull())  return "null";
	if (const std::string *str = plist.getIf<std::string>())  return *str;
	if (plist.isNumber())  return oo::str::format("%g", plist.doubleValue());
	if (id object = oo::ObjectIn(plist))  return class_getName(object_getClass(object));
	return "?";
}

oo::PList Dict(std::initializer_list<std::pair<const char *, oo::PList>> entries)
{
	oo::PList::Dict dict;
	for (const auto &[key, value] : entries)  dict[key] = value;
	return oo::PList(std::move(dict));
}

}	// namespace


@implementation ShipEntity

- (BOOL) isStation  { return _isStation; }
- (OOEntityStatus) status  { return _status; }

@end


@implementation PlayerEntity

- (void) setScriptTarget:(ShipEntity *)ship  { if (ship == self)  _scriptTargetSets++; }
- (std::optional<std::string>) cxx_commanderName  { return _commanderName; }
- (void) cxx_setCommanderName:(const std::optional<std::string> &)value  { _commanderName = value; }

- (unsigned) score
{
	if (_raise)  [OOException raise:OOInvalidArgumentException format:"score %s", "boom"];
	if (_throwCxx)  throw std::runtime_error("cxx boom");
	return _score;
}

- (void) setScore:(unsigned)value  { _score = value; }
- (double) creditBalance  { return _credits; }
- (void) setCreditBalance:(double)value  { _credits = value; }
- (int) legalStatus  { return _legalStatus; }
- (void) setBounty:(OOCreditsQuantity)amount withReason:(OOLegalStatusReason)reason  { _legalStatus = static_cast<int>(amount); _bountyReason = reason; }
- (OOAlertCondition) alertCondition  { return _alertCondition; }
- (int) alertFlags  { return _alertFlags; }
- (double) escapePodRescueTime  { return _escapePodRescueTime; }
- (void) setEscapePodRescueTime:(double)seconds  { _escapePodRescueTime = seconds; }
- (NSUInteger) trumbleCount  { return _trumbleCount; }
- (int) contractReputation  { return _contractReputation; }
- (int) passengerReputation  { return _passengerReputation; }
- (int) parcelReputation  { return _parcelReputation; }
- (void) increaseContractReputation:(unsigned)amount  { _contractReputation += static_cast<int>(amount); }
- (void) decreaseContractReputation:(unsigned)amount  { _contractReputation -= static_cast<int>(amount); }
- (void) increasePassengerReputation:(unsigned)amount  { _passengerReputation += static_cast<int>(amount); }
- (void) decreasePassengerReputation:(unsigned)amount  { _passengerReputation -= static_cast<int>(amount); }
- (void) increaseParcelReputation:(unsigned)amount  { _parcelReputation += static_cast<int>(amount); }
- (void) decreaseParcelReputation:(unsigned)amount  { _parcelReputation -= static_cast<int>(amount); }
- (OODockingClearanceStatus) getDockingClearanceStatus  { return _dockingClearanceStatus; }
- (std::vector<std::string>) cxx_roleWeights  { return _roleWeights; }

- (void) cxx_doScriptEvent:(JSAtom)message withPListArguments:(const std::vector<oo::PList> &)arguments
{
	std::string event = EventName(message) + "(";
	for (std::size_t i = 0; i < arguments.size(); i++)  event += (i != 0 ? ", " : "") + Describe(arguments[i]);
	_events.push_back(event + ")");
}

- (void) doScriptEvent:(JSAtom)message withArgument:(id)argument
{
	_events.push_back(EventName(message) + "(" + Describe(oo::PListObject(argument)) + ")");
}

- (BOOL) cxx_endScenario:(const std::string &)key
{
	_endedScenario = key;
	return key == "oolite-tutorial";
}

- (void) cxx_addMessageToReport:(const std::string &)report  { _report.push_back(report); }
- (OOSpeechSettings) isSpeechOn  { return _speech; }

- (BOOL) cxx_replaceShipWithNamedShip:(const std::string &)shipName
{
	_replacedWith = shipName;
	return shipName != "no-such-ship";
}

- (void) setEntityPersonalityInt:(uint16_t)value  { _personality = value; }
- (void) setDockTarget:(ShipEntity *)entity  { _dockTarget = entity; _dockTargetSet = YES; }
- (void) addToAdjustTime:(double)seconds  { _adjustTime += seconds; }
- (void) setTargetSystemID:(OOSystemID)sid  { _targetSystem = sid; }
- (void) cxx_addRoleToPlayer:(const std::string &)role  { _lastRole = role; _lastRoleSlot = 999; }
- (void) cxx_addRoleToPlayer:(const std::string &)role inSlot:(NSUInteger)slot  { _lastRole = role; _lastRoleSlot = slot; }

@end


@implementation Universe

- (void) cxx_addCommsMessage:(const std::optional<std::string> &)text forCount:(OOTimeDelta)count  { _comms.push_back(text.value_or("(nil)")); _counts.push_back(count); }
- (void) cxx_addMessage:(const std::optional<std::string> &)text forCount:(OOTimeDelta)count  { _console.push_back(text.value_or("(nil)")); _counts.push_back(count); }
- (void) cxx_startSpeakingString:(const std::string &)text  { _spoken.push_back(text); }
- (BOOL) isSpeaking  { return _speaking; }
- (void) stopSpeaking  { _stops++; _speaking = NO; }
- (BOOL) inInterstellarSpace  { return _interstellar; }
- (oo::PList) cxx_nearbyDestinationsWithinRange:(double)range  { _range = range; return _destinations; }

@end


// The display strings, as PlayerEntity.m and OOConstToString.mm make them, for what the test uses.
std::optional<std::string> cxx_OODisplayRatingStringFromKillCount(unsigned kills)
{
	return kills >= 8 ? std::optional<std::string>("Poor") : std::optional<std::string>("Harmless");
}

std::optional<std::string> cxx_OODisplayStringFromLegalStatus(int legalStatus)
{
	if (legalStatus < 0)  return std::nullopt;
	return legalStatus == 0 ? "Clean" : (legalStatus <= 50 ? "Offender" : "Fugitive");
}

std::string cxx_DockingClearanceStatusToString(OODockingClearanceStatus dockingClearanceStatus)
{
	return dockingClearanceStatus == DOCKING_CLEARANCE_STATUS_GRANTED ? "DOCKING_CLEARANCE_STATUS_GRANTED" : "DOCKING_CLEARANCE_STATUS_NONE";
}


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


// As the engine's: a number rounded to the nearest integer; NaN or out of range is an error.
BOOL OOJSValueToInt32(JSContext *context, JSValueConst value, int32_t *outValue)
{
	double number;
	if (JS_ToFloat64(context, &number, value) < 0)  return NO;
	number = std::floor(number + 0.5);
	if (std::isnan(number) || number < INT32_MIN || number > INT32_MAX)
	{
		cxx_OOJSReportError(context, "can't convert to an integer");
		return NO;
	}
	*outValue = static_cast<int32_t>(number);
	return YES;
}


namespace {
JSClassDef sFakeStationClass = { .class_name = "Station" };
JSClassID sFakeStationClassID = 0;
}


// A JS value as a property list, as far as setEscapePodDestination() hands one over: null, a
// string, a number, a boolean, or a station (its object).
oo::PList cxx_OOJSPListFromJSValue(JSContext *context, JSValueConst value)
{
	if (JS_IsNull(value) || JS_IsUndefined(value))  return oo::PList();
	if (JS_IsString(value))  return oo::PList(cxx_OOStringFromJSValue(context, value).value_or(std::string()));
	if (JS_IsBool(value))  return oo::PList(JS_ToBool(context, value) != 0);
	if (JS_IsNumber(value))
	{
		double number = 0;
		JS_ToFloat64(context, &number, value);
		return oo::PList(number);
	}
	if (id object = (id)JS_GetOpaque(value, sFakeStationClassID))
	{
		return oo::PListObject(object);
	}
	return oo::PList(std::string("[object]"));
}


// A property list as JavaScript, as far as the binding hands one over: null, a string, a number,
// or an array of those. Owned by the caller.
JSValue OOJSValueFromPList(JSContext *context, const oo::PList &plist)
{
	if (const std::string *str = plist.getIf<std::string>())  return JS_NewStringLen(context, str->data(), str->size());
	if (plist.isNumber())  return JS_NewNumber(context, plist.doubleValue());
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
}

PlayerEntity *gOOPlayer = nil;
Universe *gSharedUniverse = nil;
Entity *gOOJSPlayerIfStale = nil;


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


// Script event names: each name is interned as the engine interns it, and the test keeps the name
// of each atom so it can read them back.
JSAtom OOJSInternAtomPRIVATE(const char *name)
{
	JSAtom atom = JS_NewAtom(gOOJSMainThreadContext, name);
	sJSIDNames[atom] = name;
	return atom;
}


// The atom cache and the pending-exception reporter, which the class registry (OOJSClasses.mm,
// linked) calls.
JSAtom cxx_OOJSIDFromString(const std::string &string)
{
	return JS_NewAtomLen(gOOJSMainThreadContext, string.data(), string.size());
}


void OOJSReportPendingException(JSContext *context)
{
	JS_FreeValue(context, JS_GetException(context));
}


// As the engine's: the pending exception, else an uncatchable one that ends the script.
JSValue OOJSNativeFailure(JSContext *context)
{
	if (JS_HasException(context))  return JS_EXCEPTION;
	JSValue error = JS_NewError(context);
	JS_SetUncatchableError(context, error);
	return JS_Throw(context, error);
}


JSValue OOJSUnconstructableConstruct(JSContext *context, JSValueConst, int, JSValueConst *)
{
	cxx_OOJSReportError(context, "unconstructable");
	return JS_EXCEPTION;
}


void OOJSObjectWrapperFinalize(JSRuntime *, JSValueConst)
{
}


int sLimiterPauses = 0;
int sProfileDepth = 0;

#if OOJS_PROFILE
void OOJSProfileEnter(OOJSProfileStackFrame *, const char *)  { sProfileDepth++; }
void OOJSProfileExit(OOJSProfileStackFrame *)  { sProfileDepth--; }
#endif

void OOJSPauseTimeLimiter(void)  { sLimiterPauses++; }
void OOJSResumeTimeLimiter(void)  { sLimiterPauses--; }


oo::PList OOJSBasicPrivateObjectConverter(JSContext *, JSValueConst)
{
	return oo::PList();
}


// MARK: The context -------------------------------------------------------------------------------

namespace {

JSRuntime *sRuntime;
JSContext *sContext;
JSValue sGlobal = JS_UNDEFINED;	// held for the life of the test
PlayerEntity *sPlayer = nil;
Universe *sUniverse = nil;
ShipEntity *sStation = nil;
ShipEntity *sNonStation = nil;


void Define(const char *name, JSClassID jsClassID, id object)
{
	JSValue jsObject = JS_NewObjectClass(sContext, static_cast<int>(jsClassID));
	JS_SetOpaque(jsObject, object);
	JS_SetPropertyStr(sContext, sGlobal, name, jsObject);
}


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = JS_NewRuntime();
	JS_SetMemoryLimit(sRuntime, 8u * 1024u * 1024u);
	sContext = JS_NewContext(sRuntime);
	gOOJSMainThreadContext = sContext;
	sGlobal = JS_GetGlobalObject(sContext);
	OOJSRegisterClass(&sFakeStationClassID, &sFakeStationClass);

	// Kept for the life of the test.
	sUniverse = [[Universe alloc] init];
	gSharedUniverse = sUniverse;
	sPlayer = [[PlayerEntity alloc] init];
	gOOPlayer = sPlayer;
	sPlayer->_commanderName = "Jameson";
	sPlayer->_score = 5;
	sPlayer->_credits = 100.5;
	sPlayer->_legalStatus = 30;
	sPlayer->_alertCondition = ALERT_CONDITION_YELLOW;
	sPlayer->_alertFlags = ALERT_FLAG_MASS_LOCK | ALERT_FLAG_ENERGY;
	sPlayer->_escapePodRescueTime = 3600;
	sPlayer->_trumbleCount = 12;
	sPlayer->_contractReputation = 35;
	sPlayer->_passengerReputation = -17;
	sPlayer->_parcelReputation = 70;
	sPlayer->_dockingClearanceStatus = DOCKING_CLEARANCE_STATUS_GRANTED;
	sPlayer->_roleWeights = { "trader", "pirate", "trader" };
	sPlayer->_status = STATUS_DOCKED;
	sPlayer->_targetSystem = -1;
	sStation = [[ShipEntity alloc] init];
	sStation->_isStation = YES;
	sNonStation = [[ShipEntity alloc] init];

	InitOOJSPlayer(sContext, sGlobal);
	Define("station", sFakeStationClassID, sStation);
	Define("freighter", sFakeStationClassID, sNonStation);
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


std::string Events()
{
	std::string result;
	for (const std::string &event : sPlayer->_events)  result += (result.empty() ? "" : "; ") + event;
	sPlayer->_events.clear();
	return result;
}

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

OO_TEST(registration)
{
	SetUpContext();
	OO_CHECK_EQ(sConverters[JSPlayerClassID()], 1);
	const char *playerClassName = OOJSClassName(JSPlayerClassID());
	OO_CHECK(playerClassName != nullptr && std::strcmp(playerClassName, "Player") == 0);
	JSValue prototype = JS_GetClassProto(sContext, JSPlayerClassID());
	OO_CHECK(JS_IsObject(prototype));
	JS_FreeValue(sContext, prototype);
	JSValue player = JS_GetPropertyStr(sContext, sGlobal, "player");
	JSValue playerObject = JSPlayerObject();
	OO_CHECK(JS_IsObject(player) && JS_VALUE_GET_PTR(player) == JS_VALUE_GET_PTR(playerObject));
	JS_FreeValue(sContext, playerObject);
	JS_FreeValue(sContext, player);
	OO_CHECK_EVAL("typeof Player", "function");
	OO_CHECK_EVAL("new Player()", "threw: unconstructable");
	OO_CHECK_EVAL("player instanceof Player", "true");
	OO_CHECK_EVAL("(function () { player = 5; return player instanceof Player; })()", "true");	// read-only
	OO_CHECK_EVAL("Object.keys(Player.prototype).join()",
				  "alertAltitude,alertCondition,alertEnergy,alertHostiles,alertMassLocked,alertTemperature,bounty,contractReputation,contractReputationPrecise,credits,dockingClearanceStatus,escapePodRescueTime,legalStatus,name,parcelReputation,parcelReputationPrecise,passengerReputation,passengerReputationPrecise,rank,roleWeights,score,trumbleCount");
	OO_CHECK(OOPlayerForScripting() == sPlayer);
}


OO_TEST(readProperties)
{
	SetUpContext();
	sPlayer->_scriptTargetSets = 0;
	OO_CHECK_EVAL("player.name", "Jameson");
	OO_CHECK_EVAL("player.score + ':' + player.rank", "5:Harmless");
	OO_CHECK_EVAL("player.credits", "100.5");
	OO_CHECK_EVAL("player.bounty + ':' + player.legalStatus", "30:Offender");
	OO_CHECK_EVAL("player.alertCondition", "2");
	OO_CHECK_EVAL("[player.alertTemperature, player.alertMassLocked, player.alertAltitude, player.alertEnergy, player.alertHostiles].join()",
				  "false,true,false,true,false");
	OO_CHECK_EVAL("player.escapePodRescueTime", "3600");
	OO_CHECK_EVAL("player.trumbleCount", "12");
	// Reputations: -7 to +7, truncated, and the precise ones.
	OO_CHECK_EVAL("[player.contractReputation, player.passengerReputation, player.parcelReputation].join()", "3,-1,7");
	OO_CHECK_EVAL("[player.contractReputationPrecise, player.passengerReputationPrecise, player.parcelReputationPrecise].join()", "3.5,-1.7,7");
	OO_CHECK_EVAL("player.dockingClearanceStatus", "DOCKING_CLEARANCE_STATUS_GRANTED");
	OO_CHECK_EVAL("JSON.stringify(player.roleWeights)", "[\"trader\",\"pirate\",\"trader\"]");
	sPlayer->_commanderName = std::nullopt;
	sPlayer->_legalStatus = -1;
	OO_CHECK_EVAL("player.name + ':' + player.legalStatus", "null:null");
	sPlayer->_commanderName = "Jameson";
	sPlayer->_legalStatus = 30;
	OO_CHECK(sPlayer->_scriptTargetSets > 0);	// every native asks for the player for scripting
}


OO_TEST(writeProperties)
{
	SetUpContext();
	OO_CHECK_EVAL("(function () { player.name = 'Blake'; return player.name; })()", "Blake");
	OO_CHECK_EVAL("(function () { player.name = 42; return player.name; })()", "42");
	OO_CHECK_EVAL("(function () { player.name = null; return 'set'; })()", "threw: bad property value");
	OO_CHECK_EVAL("player.name", "42");
	sPlayer->_commanderName = "Jameson";

	OO_CHECK_EVAL("(function () { player.score = 9; return player.score + ':' + player.rank; })()", "9:Poor");
	OO_CHECK_EVAL("(function () { player.score = -4; return player.score; })()", "0");	// at least 0
	OO_CHECK_EVAL("(function () { player.score = 'many'; return player.score; })()", "threw: bad property value");
	sPlayer->_score = 5;

	OO_CHECK_EVAL("(function () { player.credits = 12.25; return player.credits; })()", "12.25");
	OO_CHECK_EVAL("(function () { player.credits = -3; return player.credits; })()", "-3");
	OO_CHECK_EVAL("(function () { player.credits = {}; return 'set'; })()", "set");	// NaN is a number
	sPlayer->_credits = 100.5;

	OO_CHECK_EVAL("(function () { player.bounty = 60; return player.bounty + ':' + player.legalStatus; })()", "60:Fugitive");
	OO_CHECK(sPlayer->_bountyReason == kOOLegalStatusReasonByScript);
	OO_CHECK_EVAL("(function () { player.bounty = -10; return player.bounty; })()", "0");
	OO_CHECK_EVAL("(function () { player.bounty = 'x'; return 'set'; })()", "threw: bad property value");
	sPlayer->_legalStatus = 30;

	OO_CHECK_EVAL("(function () { player.escapePodRescueTime = 60; return player.escapePodRescueTime; })()", "60");
	sPlayer->_escapePodRescueTime = 3600;

	// Read-only properties keep their values.
	OO_CHECK_EVAL("(function () { player.trumbleCount = 1; return player.trumbleCount; })()", "12");
	OO_CHECK_EVAL("(function () { player.rank = 'Elite'; return player.rank; })()", "Harmless");
}


OO_TEST(messages)
{
	SetUpContext();
	OO_CHECK_EVAL("player.commsMessage('Hello')", "undefined");
	OO_CHECK_EVAL("player.commsMessage('Again', 10)", "undefined");
	OO_CHECK(sUniverse->_comms == (std::vector<std::string>{ "Hello", "Again" }));
	OO_CHECK(sUniverse->_counts == (std::vector<double>{ 4.5, 10 }));
	OO_CHECK_EQ(Events(), std::string("commsMessageReceived(Hello, null); commsMessageReceived(Again, null)"));
	OO_CHECK_EVAL("player.commsMessage()", "threw: bad arguments: Player.commsMessage(0) - / message and optional duration");
	OO_CHECK_EQ(sUniverse->_comms.size(), static_cast<std::size_t>(2));
	// Any duration that converts to a number will do, NaN included.
	OO_CHECK_EVAL("player.commsMessage('x', 'y')", "undefined");
	OO_CHECK(sUniverse->_comms.size() == 3 && std::isnan(sUniverse->_counts[2]));
	OO_CHECK_EQ(Events(), std::string("commsMessageReceived(x, null)"));
	sUniverse->_counts.clear();

	OO_CHECK_EVAL("player.consoleMessage('Status')", "undefined");
	OO_CHECK_EVAL("player.consoleMessage('Longer', 7.5)", "undefined");
	OO_CHECK(sUniverse->_console == (std::vector<std::string>{ "Status", "Longer" }));
	OO_CHECK(sUniverse->_counts == (std::vector<double>{ 3.0, 7.5 }));
	OO_CHECK_EVAL("player.consoleMessage(null)", "threw: bad arguments: Player.consoleMessage(1) - / message and optional duration");
	OO_CHECK_EQ(Events(), std::string());

	OO_CHECK_EVAL("player.addMessageToArrivalReport('Cargo delivered.')", "undefined");
	OO_CHECK(sPlayer->_report == (std::vector<std::string>{ "Cargo delivered." }));
	OO_CHECK_EVAL("player.addMessageToArrivalReport()", "threw: bad arguments: Player.addMessageToArrivalReport(0) - / string (arrival message)");

	// Speech: spoken only when speech is on for comms; stopped only while speaking.
	sPlayer->_speech = OOSPEECHSETTINGS_OFF;
	OO_CHECK_EVAL("player.audioMessage('quiet')", "undefined");
	sPlayer->_speech = OOSPEECHSETTINGS_COMMS;
	OO_CHECK_EVAL("player.audioMessage('loud')", "undefined");
	sPlayer->_speech = OOSPEECHSETTINGS_ALL;
	OO_CHECK_EVAL("player.audioMessage('louder')", "undefined");
	OO_CHECK(sUniverse->_spoken == (std::vector<std::string>{ "loud", "louder" }));
	OO_CHECK_EVAL("player.audioMessage()", "threw: bad arguments: Player.audioMessage(0) - / audiomessage (string)");
	OO_CHECK_EVAL("player.stopAudioMessage()", "undefined");
	OO_CHECK_EQ(sUniverse->_stops, 0);
	sUniverse->_speaking = YES;
	OO_CHECK_EVAL("player.stopAudioMessage()", "undefined");
	OO_CHECK_EQ(sUniverse->_stops, 1);
}


OO_TEST(reputationsAndScenarios)
{
	SetUpContext();
	OO_CHECK_EVAL("[player.increaseContractReputation(), player.decreasePassengerReputation(), player.increaseParcelReputation(), player.decreaseParcelReputation(), player.increasePassengerReputation(), player.decreaseContractReputation()].join()",
				  ",,,,,");
	OO_CHECK_EQ(sPlayer->_contractReputation, 35);
	OO_CHECK_EQ(sPlayer->_passengerReputation, -17);
	OO_CHECK_EQ(sPlayer->_parcelReputation, 70);
	OO_CHECK_EVAL("(function () { player.increaseContractReputation(); return player.contractReputationPrecise; })()", "3.6");
	sPlayer->_contractReputation = 35;

	OO_CHECK_EVAL("player.endScenario('oolite-tutorial')", "true");
	OO_CHECK_EVAL("player.endScenario('other')", "false");
	OO_CHECK_EQ(sPlayer->_endedScenario, std::string("other"));
	OO_CHECK_EVAL("player.endScenario()", "threw: bad arguments: Player.endScenario(0) - / scenario key");

	// setPlayerRole() and setEscapePodDestination() succeed without setting a result, so the test
	// does not look at what the call gives.
	OO_CHECK_EVAL("(player.setPlayerRole('hunter'), 'called')", "called");
	OO_CHECK(sPlayer->_lastRole == "hunter" && sPlayer->_lastRoleSlot == 999);
	OO_CHECK_EVAL("(player.setPlayerRole('miner', 3), 'called')", "called");
	OO_CHECK(sPlayer->_lastRole == "miner" && sPlayer->_lastRoleSlot == 3);
	OO_CHECK_EVAL("(player.setPlayerRole('miner', -1), 'called')", "called");
	OO_CHECK(sPlayer->_lastRoleSlot == 4294967295u);	// as an ECMA uint32
	OO_CHECK_EVAL("player.setPlayerRole()", "threw: bad arguments: Player.setPlayerRole(0) - / string (role) [, number (index)]");
}


OO_TEST(replaceShip)
{
	SetUpContext();
	OO_CHECK_EVAL("player.replaceShip('cobra3-player')", "true");
	OO_CHECK_EQ(sPlayer->_replacedWith, std::string("cobra3-player"));
	OO_CHECK_EQ(Events(), std::string("playerReplacedShip(PlayerEntity); playerBoughtNewShip(PlayerEntity, 0)"));
	OO_CHECK_EVAL("player.replaceShip('no-such-ship', 12)", "false");
	OO_CHECK_EQ(sPlayer->_personality, 12);	// the personality is set either way
	OO_CHECK_EQ(Events(), std::string());
	OO_CHECK_EVAL("player.replaceShip('cobra3-player', 32767)", "true");
	OO_CHECK_EQ(sPlayer->_personality, 12);	// out of range
	OO_CHECK_EVAL("player.replaceShip('cobra3-player', -1)", "true");
	OO_CHECK_EQ(sPlayer->_personality, 12);
	OO_CHECK_EVAL("player.replaceShip('cobra3-player', 32766)", "true");
	OO_CHECK_EQ(sPlayer->_personality, 32766);
	Events();
	OO_CHECK_EVAL("player.replaceShip()", "threw: bad arguments: Player.replaceShip(0) - / string (shipyard key)");
	sPlayer->_status = STATUS_IN_FLIGHT;
	OO_CHECK_EVAL("player.replaceShip('cobra3-player')", "threw: Player.replaceShip() only works while the player is docked.");
	sPlayer->_status = STATUS_DOCKED;
}


OO_TEST(escapePodDestination)
{
	SetUpContext();
	// Only while the escape pod is in flight (the player is stale).
	OO_CHECK_EVAL("player.setEscapePodDestination(null)", "threw: Player.setEscapePodDestination() only works while the escape pod is in flight.");
	gOOJSPlayerIfStale = (Entity *)sPlayer;

	sPlayer->_dockTargetSet = NO;
	OO_CHECK_EVAL("(player.setEscapePodDestination(station), 'called')", "called");
	OO_CHECK(sPlayer->_dockTargetSet && sPlayer->_dockTarget == sStation);
	OO_CHECK_EVAL("(player.setEscapePodDestination(null), 'called')", "called");
	OO_CHECK(sPlayer->_dockTarget == nil);
	sPlayer->_dockTarget = sStation;
	OO_CHECK_EVAL("(player.setEscapePodDestination(false), 'called')", "called");
	OO_CHECK(sPlayer->_dockTarget == nil);

	OO_CHECK_EVAL("player.setEscapePodDestination(freighter)", "threw: bad arguments: Player.setEscapePodDestination(1) - / a valid station, null, or 'NEARBY_SYSTEM'");
	OO_CHECK_EVAL("player.setEscapePodDestination(true)", "threw: bad arguments: Player.setEscapePodDestination(1) - / a valid station, null, or 'NEARBY_SYSTEM'");
	OO_CHECK_EVAL("player.setEscapePodDestination('ELSEWHERE')", "threw: bad arguments: Player.setEscapePodDestination(1) - / a valid station, null, or 'NEARBY_SYSTEM'");
	OO_CHECK_EVAL("player.setEscapePodDestination()", "threw: bad arguments: Player.setEscapePodDestination(0) - / a valid station, null, or 'NEARBY_SYSTEM'");
	OO_CHECK_EVAL("player.setEscapePodDestination(null, 1)", "threw: bad arguments: Player.setEscapePodDestination(2) - / a valid station, null, or 'NEARBY_SYSTEM'");

	// A nearby system: none in range leaves the target and the time alone.
	sPlayer->_dockTarget = sStation;
	sPlayer->_adjustTime = 0;
	sUniverse->_destinations = oo::PList(oo::PList::Array{});
	OO_CHECK_EVAL("(player.setEscapePodDestination('NEARBY_SYSTEM'), 'called')", "called");
	OO_CHECK(sPlayer->_dockTarget == nil && sPlayer->_adjustTime == 0 && sPlayer->_targetSystem == -1);
	OO_CHECK(sUniverse->_range == 7.0);
	sUniverse->_interstellar = YES;
	OO_CHECK_EVAL("(player.setEscapePodDestination('NEARBY_SYSTEM'), 'called')", "called");
	OO_CHECK(sUniverse->_range == 3.5);
	sUniverse->_interstellar = NO;
	// Systems going nova are skipped (but not the first one, which the loop never looks at); with
	// one left, it is chosen without a random draw. The target is its index in the list that is left.
	sUniverse->_destinations = oo::PList(oo::PList::Array{
		Dict({ { "distance", oo::PList(2.0) }, { "sysID", oo::PList(17) }, { "nova", oo::PList(false) } }),
		Dict({ { "distance", oo::PList(1.0) }, { "sysID", oo::PList(18) }, { "nova", oo::PList(true) } }),
	});
	OO_CHECK_EVAL("(player.setEscapePodDestination('NEARBY_SYSTEM'), 'called')", "called");
	OO_CHECK_EQ(sPlayer->_targetSystem, 0);
	OO_CHECK(sPlayer->_adjustTime >= (0.2 + 4.0) * 3600.0 + 0 && sPlayer->_adjustTime <= (0.2 + 4.0) * 3600.0 + 5400.0 * 127);
	OO_CHECK(std::fmod(sPlayer->_adjustTime - (0.2 + 4.0) * 3600.0, 5400.0) == 0);

	gOOJSPlayerIfStale = nil;
	sPlayer->_targetSystem = -1;
}


OO_TEST(nativeExceptions)
{
	SetUpContext();
	sPlayer->_raise = YES;
	OO_CHECK_EVAL("player.score", "threw: Native exception: score boom");
	sPlayer->_raise = NO;
	sPlayer->_throwCxx = YES;
	OO_CHECK_EVAL("player.rank", "threw: Native exception: cxx boom");
	sPlayer->_throwCxx = NO;
	OO_CHECK_EVAL("player.score", "5");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
}


OO_TEST_MAIN()
