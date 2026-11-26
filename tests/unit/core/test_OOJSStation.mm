/*	test_OOJSStation.mm
	Unit tests for the Station JS binding (src/Core/Scripting/OOJSStation.h/.mm) and its
	StationEntity category (OOJSStation+ObjCBridge.mm): bead oo-3oxq, converted the way bead oo-ppc
	converted OOJSVector (proposed ADR-0056 amendments oo-ppc, oo-ykoy and oo-6ia4).

	As test_OOJSWormhole.mm does (amendment oo-ykoy, item 4), it runs the JS class in a real
	QuickJS-ng context, links the game's own objects for the binding, its bridge, the engine's class
	registry (OOJSClasses.mm), its exception translator (OOJSEngineNativeWrappers.mm) and the
	converted classes it uses (OOCommodities and
	OOCommodityMarket, OOJSInterfaceDefinition, OOEquipmentType, reached through their façades), and
	stands in for the classes the binding messages (Entity, ShipEntity and StationEntity, the
	player, the universe, the game controller and the ship registry answer only the selectors the
	binding sends), for the resource manager and string expander the commodities call, the script
	engine and running script the interface definitions call, and the engine functions the binding
	links against, with the engine headers' linkage. The expectations were written against the
	Objective-C file and run on it first; they pin the JS-visible behaviour (the properties both
	ways, docking, the alert level, the launches, the interfaces, the market, the shipyard's errors,
	a non-station, a native's exception) and what the category answers the engine.
	Run: tests/run.sh unit
*/

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"
#import "OOWeakReference.h"
#import "OOCommodities.h"
#import "OOCommodityMarket.h"
#import "OOJSInterfaceDefinition.h"
#import "OOEquipmentType.h"
#import "OOStringExpander.h"
#include <objc/runtime.h>
#include "OOTypes.h"
#include "OOEntityEnums.h"
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#import "OODescription.h"
#import "OOObjCPList.h"

#include <quickjs.h>


// MARK: The classes, as far as the binding sees them ----------------------------------------------

@class StationEntity, GameController, OOEquipmentType;

// As ShipEntity.h and StationEntity.h declare them (the test imports neither).
typedef enum
{
	ALERT_CONDITION_DOCKED	= 0,
	ALERT_CONDITION_GREEN	= 1,
	ALERT_CONDITION_YELLOW	= 2,
	ALERT_CONDITION_RED		= 3
} OOAlertCondition;

typedef enum
{
	STATION_ALERT_LEVEL_GREEN	= ALERT_CONDITION_GREEN,
	STATION_ALERT_LEVEL_YELLOW	= ALERT_CONDITION_YELLOW,
	STATION_ALERT_LEVEL_RED		= ALERT_CONDITION_RED
} OOStationAlertLevel;

typedef OOEquipmentType* OOWeaponType;

@interface Entity: OOWeakRefObject
{
@public
	std::string _name;
	JSValue _jsSelf;	// owned; not an object until first asked for
}
- (id) weakRefUnderlyingObject;
@end

@interface ShipEntity: Entity
@end

/*	A station. One whose equivalent tech level is 99 raises from -equivalentTechLevel, one whose
	level is 98 throws a C++ exception, so the test sees what an exception under a native becomes.
*/
@interface StationEntity: ShipEntity
{
@public
	BOOL _npcTraffic;
	BOOL _hasShipyard;
	OOStationAlertLevel _alertLevel;
	std::optional<std::string> _allegiance;
	BOOL _requiresClearance;
	float _roll;
	BOOL _fastDocking;
	BOOL _autoDocking;
	unsigned _contractors, _police, _defenders;
	OOTechLevelID _techLevel;
	float _priceFactor;
	BOOL _suppressReports;
	BOOL _breakPattern;
	std::vector<oo::PList> *_shipyard;
	int _shipyardsMade;
	OOCommodityMarket *_market;
	int _abortAll;
	id _abortedShip;
	BOOL _fits;
	std::map<std::string, oo::ObjCRef<OOJSInterfaceDefinition *>> _interfaces;
	std::string _lastLaunch;
	ShipEntity *_launched;
}
- (BOOL) hasNPCTraffic;
- (void) setHasNPCTraffic:(BOOL)flag;
- (BOOL) hasShipyard;
- (OOStationAlertLevel) alertLevel;
- (void) setAlertLevel:(OOStationAlertLevel)level signallingScript:(BOOL)signallingScript;
- (OOAlertCondition) alertCondition;
- (void) increaseAlertLevel;
- (void) decreaseAlertLevel;
- (std::optional<std::string>) cxx_allegiance;
- (void) cxx_setAllegiance:(const std::optional<std::string> &)newAllegiance;
- (BOOL) requiresDockingClearance;
- (void) setRequiresDockingClearance:(BOOL)newValue;
- (GLfloat) flightRoll;
- (void) setRawRoll:(double)amount;
- (BOOL) allowsFastDocking;
- (void) setAllowsFastDocking:(BOOL)newValue;
- (BOOL) allowsAutoDocking;
- (void) setAllowsAutoDocking:(BOOL)newValue;
- (unsigned) countOfDockedContractors;
- (unsigned) countOfDockedPolice;
- (unsigned) countOfDockedDefenders;
- (OOTechLevelID) equivalentTechLevel;
- (float) equipmentPriceFactor;
- (BOOL) suppressArrivalReports;
- (void) setSuppressArrivalReports:(BOOL)newValue;
- (BOOL) hasBreakPattern;
- (void) setHasBreakPattern:(BOOL)newValue;
- (std::vector<oo::PList> *) cxx_localShipyard;
- (void) generateShipyard;
- (oo::PList) cxx_localMarketForScripting;
- (OOCommodityMarket *) localMarket;
- (void) cxx_setPrice:(OOCreditsQuantity)price forCommodity:(const std::string &)commodity;
- (void) cxx_setQuantity:(OOCargoQuantity)quantity forCommodity:(const std::string &)commodity;
- (void) abortAllDockings;
- (void) abortDockingForShip:(ShipEntity *)ship;
- (BOOL) fitsInDock:(ShipEntity *)ship andLogNoFit:(BOOL)logNoFit;
- (oo::PList) launchIndependentShip:(const std::string &)role;
- (ShipEntity *) launchDefenseShip;
- (ShipEntity *) launchEscort;
- (ShipEntity *) launchScavenger;
- (ShipEntity *) launchMiner;
- (ShipEntity *) launchPirateShip;
- (ShipEntity *) launchShuttle;
- (ShipEntity *) launchPatrol;
- (oo::PList) launchPolice;
- (void) cxx_setInterfaceDefinition:(OOJSInterfaceDefinition *)definition forKey:(const std::string &)key;
@end

@interface PlayerEntity: ShipEntity
{
@public
	StationEntity *_dockedStation;
	OOGUIScreenID _screen;
	BOOL _docked;
	int _marketRefreshes;
	int _shipyardRefreshes;
	std::string _dockLog;
}
- (StationEntity *) dockedStation;
- (OOGUIScreenID) guiScreen;
- (void) setGuiToMarketScreen;
- (void) setGuiToShipyardScreen:(NSUInteger)skip;
- (BOOL) isDocked;
- (void) setDockingClearanceStatus:(OODockingClearanceStatus)newValue;
- (void) safeAllMissiles;
- (void) enterDock:(StationEntity *)station;
- (id) cxx_commodityScriptNamed:(const std::optional<std::string> &)script;
@end

@interface GameController: OOObject
{
@public
	BOOL _paused;
}
- (BOOL) isGamePaused;
- (void) setGamePaused:(BOOL)value;
@end

@interface Universe: OOObject
{
@public
	StationEntity *_station;
	OOCommodities *_commodities;
	GameController *_controller;
	OOViewID _view;
}
- (StationEntity *) station;
- (OOCommodities *) commodities;
- (GameController *) gameController;
- (void) setViewDirection:(OOViewID)vd;
- (Random_Seed) marketSeed;
- (OOSystemID) currentSystemID;
@end

@interface OOShipRegistry: OOObject
+ (OOShipRegistry *) sharedRegistry;
- (oo::PList) cxx_shipInfoForKey:(const std::string &)key;
- (oo::PList) cxx_shipyardInfoForKey:(const std::string &)key;
@end

@interface ResourceManager: OOObject
+ (oo::PList) cxx_dictionaryFromFilesNamed:(const std::string &)fileName inFolder:(const std::optional<std::string> &)folderName mergeMode:(int)mergeMode cache:(BOOL)useCache;
@end

@interface OOJavaScriptEngine: OOObject
+ (OOJavaScriptEngine *) sharedEngine;
@end

@interface OOJSScript: OOWeakRefObject
+ (OOJSScript *) currentlyRunningScript;
@end

@interface Entity (OOJavaScriptExtensions)
- (JSClassID) oo_jsClassID;
- (std::optional<std::string>) cxx_oo_jsClassName;
@end


#import "OOJSStation.h"
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
JSContext *sContext;
JSClassDef sFakeEntityClass = { .class_name = "Entity" };
JSClassDef sFakeShipClass = { .class_name = "Ship" };
JSClassID sFakeEntityClassID = 0;
JSClassID sFakeShipClassID = 0;
std::map<JSClassID, int> sConverters;
}


@implementation Entity

- (id) weakRefUnderlyingObject  { return self; }
- (std::optional<std::string>) cxx_descriptionComponents  { return _name; }

// As -[Entity oo_jsValueInContext:] makes one: the class the entity's category names (its
// prototype is the class's), else the Ship class; the entity keeps it, and the caller owns the
// value returned.
- (JSValue) oo_jsValueInContext:(JSContext *)context
{
	if (!JS_IsObject(_jsSelf))
	{
		JSClassID classID = sFakeShipClassID;
		if ([self respondsToSelector:@selector(oo_jsClassID)])  classID = [self oo_jsClassID];
		_jsSelf = JS_NewObjectClass(context, static_cast<int>(classID));
		if (JS_IsException(_jsSelf))
		{
			JS_FreeValue(context, JS_GetException(context));
			return JS_NULL;
		}
		JS_SetOpaque(_jsSelf, self);
	}
	return JS_DupValue(context, _jsSelf);
}

@end


@implementation ShipEntity
@end


namespace {

ShipEntity *NewShip(const char *name)
{
	ShipEntity *ship = [[ShipEntity alloc] init];	// kept for the life of the test
	ship->_name = name;
	return ship;
}

}	// namespace


@implementation StationEntity

- (BOOL) hasNPCTraffic  { return _npcTraffic; }
- (void) setHasNPCTraffic:(BOOL)flag  { _npcTraffic = flag; }
- (BOOL) hasShipyard  { return _hasShipyard; }
- (OOStationAlertLevel) alertLevel  { return _alertLevel; }
- (OOAlertCondition) alertCondition  { return static_cast<OOAlertCondition>(_alertLevel); }
- (void) increaseAlertLevel  { _alertLevel = static_cast<OOStationAlertLevel>(_alertLevel + 1); }
- (void) decreaseAlertLevel  { _alertLevel = static_cast<OOStationAlertLevel>(_alertLevel - 1); }
- (std::optional<std::string>) cxx_allegiance  { return _allegiance; }
- (void) cxx_setAllegiance:(const std::optional<std::string> &)newAllegiance  { _allegiance = newAllegiance; }
- (BOOL) requiresDockingClearance  { return _requiresClearance; }
- (void) setRequiresDockingClearance:(BOOL)newValue  { _requiresClearance = newValue; }
- (GLfloat) flightRoll  { return _roll; }
- (void) setRawRoll:(double)amount  { _roll = static_cast<float>(amount); }
- (BOOL) allowsFastDocking  { return _fastDocking; }
- (void) setAllowsFastDocking:(BOOL)newValue  { _fastDocking = newValue; }
- (BOOL) allowsAutoDocking  { return _autoDocking; }
- (void) setAllowsAutoDocking:(BOOL)newValue  { _autoDocking = newValue; }
- (unsigned) countOfDockedContractors  { return _contractors; }
- (unsigned) countOfDockedPolice  { return _police; }
- (unsigned) countOfDockedDefenders  { return _defenders; }
- (float) equipmentPriceFactor  { return _priceFactor; }
- (BOOL) suppressArrivalReports  { return _suppressReports; }
- (void) setSuppressArrivalReports:(BOOL)newValue  { _suppressReports = newValue; }
- (BOOL) hasBreakPattern  { return _breakPattern; }
- (void) setHasBreakPattern:(BOOL)newValue  { _breakPattern = newValue; }
- (std::vector<oo::PList> *) cxx_localShipyard  { return _shipyard; }
- (OOCommodityMarket *) localMarket  { return _market; }
- (oo::PList) cxx_localMarketForScripting  { return [_market dictionaryForScripting]; }
- (void) cxx_setPrice:(OOCreditsQuantity)price forCommodity:(const std::string &)commodity  { [_market cxx_setPrice:price forGood:commodity]; }
- (void) cxx_setQuantity:(OOCargoQuantity)quantity forCommodity:(const std::string &)commodity  { [_market cxx_setQuantity:quantity forGood:commodity]; }
- (void) abortAllDockings  { _abortAll++; }
- (void) abortDockingForShip:(ShipEntity *)ship  { _abortedShip = ship; }
- (BOOL) fitsInDock:(ShipEntity *)ship andLogNoFit:(BOOL)logNoFit  { (void)ship; (void)logNoFit; return _fits; }

- (void) setAlertLevel:(OOStationAlertLevel)level signallingScript:(BOOL)signallingScript
{
	(void)signallingScript;
	if (level < STATION_ALERT_LEVEL_GREEN)  level = STATION_ALERT_LEVEL_GREEN;
	if (level > STATION_ALERT_LEVEL_RED)  level = STATION_ALERT_LEVEL_RED;
	_alertLevel = level;
}

- (OOTechLevelID) equivalentTechLevel
{
	if (_techLevel == 99)  [OOException raise:OOInvalidArgumentException format:"techlevel %s", "boom"];
	if (_techLevel == 98)  throw std::runtime_error("cxx boom");
	return _techLevel;
}

- (void) generateShipyard
{
	_shipyardsMade++;
	if (_shipyard == nullptr)  _shipyard = new std::vector<oo::PList>;
	_shipyard->push_back(oo::PList(oo::PList::Dict{ { "short_description", oo::PList(std::string("Cobra")) } }));
}

- (ShipEntity *) launched:(const char *)what
{
	_lastLaunch = what;
	return _launched;
}

- (oo::PList) launchIndependentShip:(const std::string &)role  { _lastLaunch = "role " + role; return oo::PListObject(_launched); }
- (ShipEntity *) launchDefenseShip  { return [self launched:"defense"]; }
- (ShipEntity *) launchEscort  { return [self launched:"escort"]; }
- (ShipEntity *) launchScavenger  { return [self launched:"scavenger"]; }
- (ShipEntity *) launchMiner  { return [self launched:"miner"]; }
- (ShipEntity *) launchPirateShip  { return [self launched:"pirate"]; }
- (ShipEntity *) launchShuttle  { return [self launched:"shuttle"]; }
- (ShipEntity *) launchPatrol  { return [self launched:"patrol"]; }

- (oo::PList) launchPolice
{
	_lastLaunch = "police";
	std::vector<oo::ObjCRef<ShipEntity *>> ships;
	if (_launched != nil)  ships.emplace_back(_launched);
	ships.emplace_back(_launched);
	return oo::PListFromObjects(ships);
}

- (void) cxx_setInterfaceDefinition:(OOJSInterfaceDefinition *)definition forKey:(const std::string &)key
{
	if (definition == nil)  _interfaces.erase(key);
	else  _interfaces[key] = oo::ObjCRef<OOJSInterfaceDefinition *>(definition);
}

@end


@implementation PlayerEntity

- (StationEntity *) dockedStation  { return _dockedStation; }
- (OOGUIScreenID) guiScreen  { return _screen; }
- (void) setGuiToMarketScreen  { _marketRefreshes++; }
- (void) setGuiToShipyardScreen:(NSUInteger)skip  { (void)skip; _shipyardRefreshes++; }
- (BOOL) isDocked  { return _docked; }
- (void) setDockingClearanceStatus:(OODockingClearanceStatus)newValue  { _dockLog += "clearance " + std::to_string(static_cast<int>(newValue)) + "; "; }
- (void) safeAllMissiles  { _dockLog += "safe; "; }
- (void) enterDock:(StationEntity *)station  { _dockLog += "dock " + (station != nil ? station->_name : std::string("nil")); _docked = YES; }
- (id) cxx_commodityScriptNamed:(const std::optional<std::string> &)script  { (void)script; return nil; }

@end


@implementation GameController
- (BOOL) isGamePaused  { return _paused; }
- (void) setGamePaused:(BOOL)value  { _paused = value; }
@end


@implementation Universe
- (StationEntity *) station  { return _station; }
- (OOCommodities *) commodities  { return _commodities; }
- (GameController *) gameController  { return _controller; }
- (void) setViewDirection:(OOViewID)vd  { _view = vd; }
- (Random_Seed) marketSeed  { return Random_Seed{}; }
- (OOSystemID) currentSystemID  { return 7; }
@end


@implementation OOShipRegistry
+ (OOShipRegistry *) sharedRegistry  { return nil; }	// the test adds no ship to a shipyard
- (oo::PList) cxx_shipInfoForKey:(const std::string &)key  { (void)key; return oo::PList(); }
- (oo::PList) cxx_shipyardInfoForKey:(const std::string &)key  { (void)key; return oo::PList(); }
@end


@implementation ResourceManager

// trade-goods.plist: food and gems.
+ (oo::PList) cxx_dictionaryFromFilesNamed:(const std::string &)fileName inFolder:(const std::optional<std::string> &)folderName mergeMode:(int)mergeMode cache:(BOOL)useCache
{
	(void)fileName; (void)folderName; (void)mergeMode; (void)useCache;
	return oo::PList(oo::PList::Dict{
		{ "food", oo::PList(oo::PList::Dict{ { "name", oo::PList(std::string("Food")) }, { "quantity_unit", oo::PList(0.0) }, { "price_average", oo::PList(50.0) }, { "quantity_average", oo::PList(40.0) }, { "capacity", oo::PList(100.0) } }) },
		{ "gems", oo::PList(oo::PList::Dict{ { "name", oo::PList(std::string("Gem-stones")) }, { "quantity_unit", oo::PList(2.0) }, { "price_average", oo::PList(160.0) }, { "quantity_average", oo::PList(200.0) } }) },
	});
}

@end


@implementation OOJavaScriptEngine
+ (OOJavaScriptEngine *) sharedEngine
{
	static OOJavaScriptEngine *engine = [[OOJavaScriptEngine alloc] init];
	return engine;
}
@end


@implementation OOJSScript
+ (OOJSScript *) currentlyRunningScript  { return nil; }
@end


// MARK: What the rest of the game provides --------------------------------------------------------

std::optional<std::string> cxx_OOExpandDescriptionString(Random_Seed, const std::string &string, const oo::PList &, const oo::PList &, const std::optional<std::string> &, OOExpandOptions)
{
	return "<" + string + ">";
}

Random_Seed OOStringExpanderDefaultRandomSeed(void)
{
	return Random_Seed{};
}

std::string cxx_OOLookUpDescriptionPRIV(const std::string &key)
{
	return "desc(" + key + ")";
}

// Link stubs (amendment oo-zffj item 2): what OOEquipmentType reaches to load equipment, which the
// test never does (no equipment type is made), and the weapon lookups of addShipToShipyard(), which
// the test's shipyard items never reach.
@interface OOCacheManager: OOObject
@end
@implementation OOCacheManager
@end

@interface OOScript: OOObject
@end
@implementation OOScript
@end

void cxx_OOStandardsDeprecated(const std::string &)  { std::abort(); }
extern "C" BOOL OOEnforceStandards(void)  { std::abort(); }
oo::PList OOSanitizeLegacyScriptConditions(const oo::PList &, const std::optional<std::string> &)  { std::abort(); }
OOWeaponType cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(const std::string &)  { std::abort(); }
extern "C" BOOL isWeaponNone(OOWeaponType)  { std::abort(); }

extern const char * const kOOJavaScriptEngineWillResetNotificationName;
const char * const kOOJavaScriptEngineWillResetNotificationName = "org.aegidian.oolite OOJavaScriptEngine will reset";


// MARK: What the rest of the engine provides ------------------------------------------------------

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


// The engine reports a pending exception; the test drops it.
void OOJSReportPendingException(JSContext *context)
{
	JS_FreeValue(context, JS_GetException(context));
}


namespace {
std::string sLastWarning;
}

void cxx_OOJSReportWarningForCaller(JSContext *, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	sLastWarning = scriptClass.value_or("-") + "." + function.value_or("-") + ": " + oo::str::vformat(format, args);
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


// A property list as JavaScript, as far as the binding hands one over: null, a string, a number,
// an object (its JS value), or an array or dictionary of those. Owned by the caller.
JSValue OOJSValueFromPList(JSContext *context, const oo::PList &plist)
{
	if (const std::string *str = plist.getIf<std::string>())  return JS_NewStringLen(context, str->data(), str->size());
	if (plist.isNumber())  return JS_NewNumber(context, plist.doubleValue());
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


// An object as a dictionary, as far as the test hands one over: its "short_description" property.
oo::PList cxx_OOJSPListFromJSObject(JSContext *context, JSValueConst object)
{
	if (JS_IsArray(object))  return oo::PList(oo::PList::Array{});
	oo::PList::Dict dict;
	JSValue value = JS_GetPropertyStr(context, object, "short_description");
	if (JS_IsException(value))  JS_FreeValue(context, JS_GetException(context));
	else if (!JS_IsUndefined(value))  dict["short_description"] = oo::PList(cxx_OOStringFromJSValue(context, value).value_or(""));
	JS_FreeValue(context, value);
	return oo::PList(std::move(dict));
}


namespace {
PlayerEntity *sPlayer = nil;
}

JSContext *gOOJSMainThreadContext = nullptr;
Entity *gOOJSPlayerIfStale = nil;
PlayerEntity *gOOPlayer = nil;
Universe *gSharedUniverse = nil;


PlayerEntity *OOPlayerForScripting(void)
{
	return sPlayer;
}


JSClassID JSEntityClassID(void)
{
	return sFakeEntityClassID;
}


JSClassID JSShipClassID(void)
{
	return sFakeShipClassID;
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


// The engine's object getter: the JS class must be a subclass of the required one, and the
// underlying object must be of the required Objective-C class. Class registration and the
// subclass table are OOJSClasses.mm's (linked).
BOOL OOJSObjectGetterImplPRIVATE(JSContext *context, JSValueConst object, JSClassID requiredClassID, Class requiredObjCClass, const char *, id *outObject)
{
	if (!OOJSIsSubclass(JS_GetClassID(object), requiredClassID))
	{
		cxx_OOJSReportError(context, "Native method expected %s, got %s.", OOJSClassName(requiredClassID), cxx_OOStringFromJSValue(context, object).value_or("(null)").c_str());
		return NO;
	}
	JSClassID ignored;
	*outObject = [(id)JS_GetAnyOpaque(object, &ignored) weakRefUnderlyingObject];
	if (*outObject != nil && ![*outObject isKindOfClass:requiredObjCClass])
	{
		cxx_OOJSReportError(context, "Native method expected %s from %s.", class_getName(requiredObjCClass), OOJSClassName(requiredClassID));
		*outObject = nil;
		return NO;
	}
	return YES;
}


// The engine's conversion asks the object for its JS value (owned); nil is null.
JSValue OOJSValueFromNativeObject(JSContext *context, id object)
{
	if (object == nil)  return JS_NULL;
	return [object oo_jsValueInContext:context];
}


JSValue OOJSUnconstructableConstruct(JSContext *context, JSValueConst, int, JSValueConst *)
{
	cxx_OOJSReportError(context, "unconstructable");
	return JS_EXCEPTION;
}


void OOJSObjectWrapperFinalize(JSRuntime *, JSValueConst)
{
}


JSAtom OOJSInternAtomPRIVATE(const char *)
{
	std::abort();	// link stub: the commodity classes' script path
}


// Property IDs, which OOJSClasses.mm records: interned for the life of the process, as the
// engine's.
JSAtom cxx_OOJSIDFromString(const std::string &string)
{
	return JS_NewAtomLen(gOOJSMainThreadContext, string.data(), string.size());
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
JSValue sGlobal = JS_UNDEFINED;
StationEntity *sStation = nil;
StationEntity *sOther = nil;
ShipEntity *sShip = nil;
Universe *sUniverse = nil;


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
	JSValueConst entityPrototype = OOJSInitClass(sContext, sGlobal, sFakeEntityClassID, JS_UNDEFINED, OOJSUnconstructableConstruct, 0, nullptr, 0, nullptr, 0, nullptr, 0);
	OOJSRegisterClass(&sFakeShipClassID, &sFakeShipClass);
	OOJSInitClass(sContext, sGlobal, sFakeShipClassID, entityPrototype, OOJSUnconstructableConstruct, 0, nullptr, 0, nullptr, 0, nullptr, 0);
	OOJSRegisterSubclass(sFakeShipClassID, sFakeEntityClassID);
	InitOOJSStation(sContext, sGlobal);

	sUniverse = [[Universe alloc] init];	// kept for the life of the test
	gSharedUniverse = sUniverse;
	sUniverse->_controller = [[GameController alloc] init];
	sUniverse->_commodities = [[OOCommodities alloc] init];
	sPlayer = [[PlayerEntity alloc] init];
	sPlayer->_name = "player";
	sPlayer->_screen = GUI_SCREEN_STATUS;
	gOOPlayer = sPlayer;
	sStation = [[StationEntity alloc] init];
	sStation->_name = "Coriolis";
	sStation->_npcTraffic = YES;
	sStation->_alertLevel = STATION_ALERT_LEVEL_GREEN;
	sStation->_allegiance = "galcop";
	sStation->_roll = 0.25f;
	sStation->_autoDocking = YES;
	sStation->_contractors = 2;
	sStation->_police = 3;
	sStation->_defenders = 4;
	sStation->_techLevel = 9;
	sStation->_priceFactor = 1.5f;
	sStation->_market = [[sUniverse->_commodities generateBlankMarket] retain];
	sUniverse->_station = sStation;
	sOther = [[StationEntity alloc] init];
	sOther->_name = "Rock Hermit";
	sShip = NewShip("Cobra");
	Define("station", [sStation oo_jsValueInContext:sContext]);
	Define("other", [sOther oo_jsValueInContext:sContext]);
	Define("ship", [sShip oo_jsValueInContext:sContext]);
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


// Whether an owned value (freed here) is the object other.
bool SameObject(JSValue value, JSValueConst other)
{
	const bool same = JS_IsObject(value) && JS_IsObject(other) && JS_VALUE_GET_PTR(value) == JS_VALUE_GET_PTR(other);
	JS_FreeValue(sContext, value);
	return same;
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
	const JSClassID stationClass = [sStation oo_jsClassID];
	OO_CHECK(stationClass != 0 && OOJSClassName(stationClass) != nullptr && std::strcmp(OOJSClassName(stationClass), "Station") == 0);
	JSValue prototype = JS_GetClassProto(sContext, stationClass);
	OO_CHECK(JS_IsObject(prototype));
	JS_FreeValue(sContext, prototype);
	OO_CHECK(OOJSIsSubclass(stationClass, sFakeShipClassID));
	OO_CHECK_EQ(sConverters[stationClass], 1);
	OO_CHECK([sStation cxx_oo_jsClassName] == std::optional<std::string>("Station"));
	OO_CHECK_EVAL("typeof Station", "function");
	OO_CHECK_EVAL("new Station()", "threw: unconstructable");
	OO_CHECK_EVAL("Object.getPrototypeOf(Station.prototype) === Ship.prototype", "true");
	OO_CHECK_EVAL("station instanceof Station && !(ship instanceof Station)", "true");
}


OO_TEST(properties)
{
	SetUpContext();
	OO_CHECK_EVAL("station.isMainStation + ' ' + other.isMainStation", "true false");
	OO_CHECK_EVAL("station.hasNPCTraffic", "true");
	OO_CHECK_EVAL("station.hasShipyard", "false");
	OO_CHECK_EVAL("station.alertCondition", "1");
	OO_CHECK_EVAL("station.allegiance + ' ' + other.allegiance", "galcop null");
	OO_CHECK_EVAL("station.requiresDockingClearance", "false");
	OO_CHECK_EVAL("station.roll", "0.25");
	OO_CHECK_EVAL("station.allowsFastDocking + ' ' + station.allowsAutoDocking", "false true");
	OO_CHECK_EVAL("[station.dockedContractors, station.dockedPolice, station.dockedDefenders].join()", "2,3,4");
	OO_CHECK_EVAL("station.equivalentTechLevel", "9");
	OO_CHECK_EVAL("station.equipmentPriceFactor", "1.5");
	OO_CHECK_EVAL("station.suppressArrivalReports + ' ' + station.breakPattern", "false false");
	OO_CHECK_EVAL("station.shipyard", "null");
	OO_CHECK_EVAL("typeof station.market.food", "object");
	OO_CHECK_EVAL("Object.keys(Station.prototype).join()", "alertCondition,allegiance,allowsAutoDocking,allowsFastDocking,breakPattern,dockedContractors,dockedDefenders,dockedPolice,equipmentPriceFactor,equivalentTechLevel,hasNPCTraffic,hasShipyard,isMainStation,market,requiresDockingClearance,roll,suppressArrivalReports,shipyard");
	// Read-only.
	OO_CHECK_EVAL("(function () { station.dockedPolice = 9; return station.dockedPolice; })()", "3");
}


OO_TEST(setters)
{
	SetUpContext();
	OO_CHECK_EVAL("(function () { station.hasNPCTraffic = false; return station.hasNPCTraffic; })()", "false");
	OO_CHECK_EVAL("(function () { station.alertCondition = 3; return station.alertCondition; })()", "3");
	OO_CHECK_EVAL("(function () { station.alertCondition = 7; return station.alertCondition; })()", "3");	// range-checked by the station
	OO_CHECK_EVAL("(function () { station.alertCondition = 1; return station.alertCondition; })()", "1");
	OO_CHECK_EVAL("(function () { station.allegiance = 'pirate'; return station.allegiance; })()", "pirate");
	OO_CHECK_EVAL("(function () { station.allegiance = null; return station.allegiance; })()", "threw: bad property value");
	OO_CHECK_EVAL("(function () { station.requiresDockingClearance = 1; return station.requiresDockingClearance; })()", "true");
	OO_CHECK_EVAL("(function () { station.roll = 1; return station.roll; })()", "1");
	OO_CHECK_EVAL("(function () { station.roll = 10; return station.roll.toFixed(4); })()", "3.1416");	// clamped to ±pi
	OO_CHECK_EVAL("(function () { station.roll = -10; return station.roll.toFixed(4); })()", "-3.1416");
	OO_CHECK_EVAL("(function () { station.allowsFastDocking = true; station.allowsAutoDocking = false; return station.allowsFastDocking + ' ' + station.allowsAutoDocking; })()", "true false");
	OO_CHECK_EVAL("(function () { station.suppressArrivalReports = true; station.breakPattern = true; return station.suppressArrivalReports + ' ' + station.breakPattern; })()", "true true");
	sStation->_npcTraffic = YES;
	sStation->_allegiance = "galcop";
	sStation->_requiresClearance = NO;
	sStation->_roll = 0.25f;
	sStation->_fastDocking = NO;
	sStation->_autoDocking = YES;
	sStation->_suppressReports = NO;
	sStation->_breakPattern = NO;
}


OO_TEST(docking)
{
	SetUpContext();
	sStation->_abortAll = 0;
	OO_CHECK_EVAL("station.abortAllDockings()", "undefined");
	OO_CHECK_EQ(sStation->_abortAll, 1);
	OO_CHECK_EVAL("station.abortDockingForShip(ship)", "undefined");
	OO_CHECK(sStation->_abortedShip == sShip);
	OO_CHECK_EVAL("station.abortDockingForShip()", "threw: bad arguments: Station.abortDockingForShip(0) - / ship in docking queue");
	sStation->_fits = YES;
	OO_CHECK_EVAL("station.canDockShip(ship)", "true");
	sStation->_fits = NO;
	OO_CHECK_EVAL("station.canDockShip(ship)", "false");
	OO_CHECK_EVAL("station.canDockShip()", "threw: bad arguments: Station.canDockShip(0) - / shipEntity");
	// dockPlayer(): unpauses the game, then docks the player unless it is docked.
	sUniverse->_controller->_paused = YES;
	OO_CHECK_EVAL("station.dockPlayer()", "undefined");
	OO_CHECK(!sUniverse->_controller->_paused);
	OO_CHECK_EQ(sPlayer->_dockLog, "clearance " + std::to_string(static_cast<int>(DOCKING_CLEARANCE_STATUS_GRANTED)) + "; safe; dock Coriolis");
	OO_CHECK_EQ(static_cast<int>(sUniverse->_view), static_cast<int>(VIEW_FORWARD));
	sPlayer->_dockLog.clear();
	OO_CHECK_EVAL("other.dockPlayer()", "undefined");
	OO_CHECK_EQ(sPlayer->_dockLog, std::string());
	sPlayer->_docked = NO;
}


OO_TEST(alertLevel)
{
	SetUpContext();
	sStation->_alertLevel = STATION_ALERT_LEVEL_GREEN;
	OO_CHECK_EVAL("(function () { station.increaseAlertLevel(); station.increaseAlertLevel(); station.increaseAlertLevel(); return station.alertCondition; })()", "3");
	OO_CHECK_EVAL("(function () { station.decreaseAlertLevel(); station.decreaseAlertLevel(); station.decreaseAlertLevel(); return station.alertCondition; })()", "1");
}


OO_TEST(launches)
{
	SetUpContext();
	sStation->_launched = sShip;
	OO_CHECK_EVAL("station.launchShipWithRole('trader') === ship", "true");
	OO_CHECK_EQ(sStation->_lastLaunch, std::string("role trader"));
	sStation->_abortAll = 0;
	OO_CHECK_EVAL("station.launchShipWithRole('trader', true) === ship", "true");
	OO_CHECK_EQ(sStation->_abortAll, 1);
	OO_CHECK_EVAL("station.launchShipWithRole()", "threw: bad arguments: Station.launchShipWithRole(0) - / string (role)");
	const char *launches[][2] = { { "launchDefenseShip", "defense" }, { "launchEscort", "escort" }, { "launchScavenger", "scavenger" }, { "launchMiner", "miner" }, { "launchPirateShip", "pirate" }, { "launchShuttle", "shuttle" }, { "launchPatrol", "patrol" } };
	for (const auto &launch : launches)
	{
		std::string src = std::string("station.") + launch[0] + "() === ship";
		OO_CHECK_EVAL(src.c_str(), "true");
		OO_CHECK_EQ(sStation->_lastLaunch, std::string(launch[1]));
	}
	OO_CHECK_EVAL("station.launchPolice().length + ' ' + (station.launchPolice()[0] === ship)", "2 true");
	sStation->_launched = nil;
	OO_CHECK_EVAL("station.launchMiner()", "null");
	OO_CHECK_EVAL("station.launchShipWithRole('trader')", "null");
	OO_CHECK_EVAL("station.launchPolice().length", "0");	// no ship: none in the array
	OO_CHECK_EQ(sLimiterPauses, 0);
}


OO_TEST(interfaces)
{
	SetUpContext();
	OO_CHECK_EVAL("station.setInterface('k', {title: 'T', summary: 'S', category: 'C', callback: function () {}})", "undefined");
	OO_CHECK(sStation->_interfaces.count("k") == 1);
	if (sStation->_interfaces.count("k") == 1)
	{
		OOJSInterfaceDefinition *definition = sStation->_interfaces["k"].get();
		OO_CHECK([definition cxx_title] == std::optional<std::string>("T"));
		OO_CHECK([definition summary] == std::optional<std::string>("S"));
		OO_CHECK([definition category] == std::optional<std::string>("C"));
		JSValue callback = [definition callback];
		JSValue callbackThis = [definition callbackThis];
		OO_CHECK(JS_IsObject(callback) && !JS_IsObject(callbackThis));
		JS_FreeValue(sContext, callbackThis);
		JS_FreeValue(sContext, callback);
	}
	OO_CHECK_EVAL("station.setInterface('k2', {title: 'T', summary: 'S', callback: function () {}, cbThis: station})", "undefined");
	OO_CHECK(sStation->_interfaces.count("k2") == 1 && [sStation->_interfaces["k2"].get() category] == std::optional<std::string>("desc(interfaces-category-uncategorised)"));
	OO_CHECK(sStation->_interfaces.count("k2") == 1 && SameObject([sStation->_interfaces["k2"].get() callbackThis], sStation->_jsSelf));
	OO_CHECK_EVAL("station.setInterface('k2', {title: 'T', summary: 'S', category: '', callback: function () {}})", "undefined");
	OO_CHECK(sStation->_interfaces.count("k2") == 1 && [sStation->_interfaces["k2"].get() category] == std::optional<std::string>("desc(interfaces-category-uncategorised)"));
	OO_CHECK_EVAL("station.setInterface('k')", "undefined");
	OO_CHECK(sStation->_interfaces.count("k") == 0);
	OO_CHECK_EVAL("station.setInterface('k2', null)", "undefined");
	OO_CHECK(sStation->_interfaces.empty());
	OO_CHECK_EVAL("station.setInterface()", "threw: bad arguments: Station.setInterface(0) - / key [, definition]");
	OO_CHECK_EVAL("station.setInterface('k', {summary: 'S'})", "threw: bad arguments: Station.setInterface(1) - / key [, definition]; if definition is set, it must have a 'title' property.");
	OO_CHECK_EVAL("station.setInterface('k', {title: ''})", "threw: bad arguments: Station.setInterface(1) - / key [, definition]; if definition is set, 'title' property must be a non-empty string.");
	OO_CHECK_EVAL("station.setInterface('k', {title: 'T'})", "threw: bad arguments: Station.setInterface(1) - / key [, definition]; if definition is set, it must have a 'summary' property.");
	OO_CHECK_EVAL("station.setInterface('k', {title: 'T', summary: ''})", "threw: bad arguments: Station.setInterface(1) - / key [, definition]; if definition is set, 'summary' property must be a non-empty string.");
	OO_CHECK_EVAL("station.setInterface('k', {title: 'T', summary: 'S'})", "threw: bad arguments: Station.setInterface(1) - / key [, definition]; if definition is set, it must have a 'callback' property.");
	OO_CHECK_EVAL("station.setInterface('k', {title: 'T', summary: 'S', callback: 5})", "threw: bad arguments: Station.setInterface(1) - / key [, definition]; 'callback' property must be a function.");
	OO_CHECK(sStation->_interfaces.empty());
}


OO_TEST(market)
{
	SetUpContext();
	OO_CHECK_EVAL("station.setMarketPrice('food', 120)", "true");
	OO_CHECK_EQ([sStation->_market cxx_priceForGood:"food"], 120u);
	// A blank market has no capacity: only 0 fits.
	[sStation->_market cxx_setQuantity:5 forGood:"food"];
	OO_CHECK_EVAL("station.setMarketQuantity('food', 0)", "true");
	OO_CHECK_EQ([sStation->_market cxx_quantityForGood:"food"], 0u);
	OO_CHECK_EVAL("station.market.food.quantity + ' ' + station.market.food.price", "0 120");
	OO_CHECK_EVAL("station.setMarketQuantity('food', 1)", "threw: bad arguments: Station.setMarketQuantity(2) - / Quantity must be between 0 and the station market capacity");
	OO_CHECK_EVAL("station.setMarketQuantity('food', -1)", "threw: bad arguments: Station.setMarketQuantity(2) - / Quantity must be between 0 and the station market capacity");
	OO_CHECK_EVAL("station.setMarketPrice('food', -1)", "threw: bad arguments: Station.setMarketPrice(2) - / Price must be at least 0 decicredits");
	OO_CHECK_EVAL("station.setMarketPrice('unobtainium', 1)", "threw: bad arguments: Station.setMarketPrice(2) - / Unrecognised commodity type");
	OO_CHECK_EVAL("station.setMarketQuantity('unobtainium', 1)", "threw: bad arguments: Station.setMarketQuantity(2) - / Unrecognised commodity type");
	OO_CHECK_EVAL("station.setMarketPrice('food')", "threw: bad arguments: Station.setMarketPrice(1) - / commodity, credits");
	OO_CHECK_EVAL("station.setMarketQuantity('food')", "threw: bad arguments: Station.setMarketQuantity(1) - / commodity, units");
	// The market screen is refreshed when the player is docked here and looking at it.
	sPlayer->_dockedStation = sStation;
	sPlayer->_screen = GUI_SCREEN_MARKET;
	sPlayer->_marketRefreshes = 0;
	OO_CHECK_EVAL("station.setMarketPrice('food', 100) && station.setMarketQuantity('food', 0)", "true");
	OO_CHECK_EQ(sPlayer->_marketRefreshes, 2);
	sPlayer->_dockedStation = nil;
	sPlayer->_screen = GUI_SCREEN_STATUS;
}


OO_TEST(shipyard)
{
	SetUpContext();
	sLastWarning.clear();
	OO_CHECK_EVAL("station.addShipToShipyard({short_description: 'x'})", "<evaluation failed>");
	OO_CHECK_EQ(sLastWarning, std::string("Station.removeShipFromShipyard: Station does not have shipyard."));
	OO_CHECK_EVAL("station.removeShipFromShipyard(0)", "<evaluation failed>");
	sStation->_hasShipyard = YES;
	sStation->_shipyardsMade = 0;
	OO_CHECK_EVAL("station.shipyard.length + ' ' + station.shipyard[0].short_description", "1 Cobra");
	OO_CHECK_EQ(sStation->_shipyardsMade, 1);
	OO_CHECK_EVAL("station.addShipToShipyard(null)", "undefined");
	OO_CHECK_EVAL("station.addShipToShipyard()", "threw: bad arguments: Station.addShipToShipyard(0) - / shipyard item definition");
	OO_CHECK_EVAL("station.addShipToShipyard({})", "threw: bad arguments: Station.addShipToShipyard(1) - / 'short_description' in dictionary");
	OO_CHECK_EVAL("station.addShipToShipyard([])", "threw: Unidentified native exception");
	OO_CHECK_EVAL("station.addShipToShipyard({short_description: 'x'})", "threw: bad arguments: Station.addShipToShipyard(1) - / 'shipdata_key' in dictionary");
	OO_CHECK_EVAL("station.removeShipFromShipyard(3)", "threw: bad arguments: Station.removeShipFromShipyard(1) - / valid ship index");
	sPlayer->_dockedStation = sStation;
	sPlayer->_screen = GUI_SCREEN_SHIPYARD;
	OO_CHECK_EVAL("station.removeShipFromShipyard(0) + ' ' + station.shipyard.length", "true 0");
	OO_CHECK_EQ(sPlayer->_shipyardRefreshes, 1);
	sPlayer->_dockedStation = nil;
	sPlayer->_screen = GUI_SCREEN_STATUS;
	sStation->_hasShipyard = NO;
}


OO_TEST(otherObjects)
{
	SetUpContext();
	// A non-station entity is refused without a JS error; a non-entity is an error.
	OO_CHECK_EVAL("Object.getOwnPropertyDescriptor(Station.prototype, 'roll').get.call(ship)", "<evaluation failed>");
	OO_CHECK_EVAL("Station.prototype.launchMiner.call(ship)", "undefined");	// stale reference: no-op
	// Not an entity: the getter's error is thrown (#768's natives do not return normally with an
	// exception pending).
	OO_CHECK_EVAL("Station.prototype.launchMiner.call({})", "threw: Native method expected Entity, got [object Object].");
	// The prototype is an instance of its class with no entity (#768's OOJSInitClass, as
	// SpiderMonkey's JS_InitClass): refused without a JS error.
	OO_CHECK_EVAL("Station.prototype.roll", "<evaluation failed>");
}


OO_TEST(nativeExceptions)
{
	SetUpContext();
	sStation->_techLevel = 99;
	OO_CHECK_EVAL("station.equivalentTechLevel", "threw: Native exception: techlevel boom");
	sStation->_techLevel = 98;
	OO_CHECK_EVAL("station.equivalentTechLevel", "threw: Native exception: cxx boom");
	sStation->_techLevel = 9;
	OO_CHECK_EVAL("station.equivalentTechLevel", "9");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
}


OO_TEST_MAIN()
