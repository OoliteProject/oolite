/*	test_OOJSStation.mm
	Unit tests for the Station JS binding (src/Core/Scripting/OOJSStation.h/.mm) and its
	StationEntity answers for the class (StationEntity::jsClassID).

	As test_OOJSWormhole.mm does, it runs the JS class in a real QuickJS-ng context, links the
	game's own objects for the binding, the engine's class registry (OOJSClasses.mm), its exception
	translator (OOJSEngineNativeWrappers.mm) and the converted classes it uses (OOCommodities and
	OOCommodityMarket (held as oo::Ref), OOEquipmentType and OOJSInterfaceDefinition), and stands in
	for the classes the binding messages (Entity, ShipEntity and StationEntity, the player, the
	universe, the game controller and the ship registry answer only the selectors the binding
	sends), for the resource manager and string expander the commodities call, the script engine and
	running script the interface definitions call, and the engine functions the binding links
	against, with the engine headers' linkage. The expectations pin the JS-visible behaviour (the
	properties both ways, docking,
	the alert level, the launches, the interfaces, the market, the shipyard's errors, a non-station,
	a native's exception) and what the category answers the engine. Run: tests/run.sh unit
*/

#include "OOFoundation.h"
#include "OOCommodities.h"
#include "OOCommodityMarket.h"
#include "OOJSInterfaceDefinition.h"
#include "OOEquipmentType.h"
#include "OOStringExpander.h"
#include "OOShipRegistry.h"
#include "OOTypes.h"
#include "OOEntityEnums.h"
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#include "OODescription.h"
#include "oofnd/StdLib.hpp"
#include "EntityPListForeign.h"	// an entity's node

#include <quickjs.h>


// MARK: The classes, as far as the binding sees them ----------------------------------------------

class StationEntity;
class GameController;

// As ShipEntity.h and StationEntity.h declare them (the test imports neither).
enum class OOAlertCondition : std::int32_t {
	kDocked	= 0,
	kGreen	= 1,
	kYellow	= 2,
	kRed		= 3
};

enum class OOStationAlertLevel : std::int32_t {
	kGreen	= static_cast<std::int32_t>(OOAlertCondition::kGreen),
	kYellow	= static_cast<std::int32_t>(OOAlertCondition::kYellow),
	kRed		= static_cast<std::int32_t>(OOAlertCondition::kRed)
};

typedef OOEquipmentType* OOWeaponType;

#include "OOJSPrivateObject.h"

// The C++ root, as far as the binding and the root's JS category reach it; its JS glue
// (OOJSPrivateObject, as the game's root implements it) answers its object's JS value
// (the binding's launches return OOJSValueFromCxxObject of the C++ ship).
class Entity : public oo::RefCounted, public OOJSPrivateObject
{
public:
	virtual ~Entity();
	virtual JSClassID jsClassID();
	virtual std::optional<std::string> jsClassName();
	JSValue jsValueInContext(JSContext *context) override;
	void clearJSSelf(JSValueConst selfVal) override;
};

// The ship's members the binding calls on a station, by their final overrider
// (a ship's part is a plain one).
class ShipEntity : public Entity
{
public:
	GLfloat getFlightRoll();
	void setRawRoll(double amount);
	OOAlertCondition alertCondition();
};

// What an entity's JS object holds: a weak reference to the C++ entity.
#include "OOJSEntityHolder.h"

// The object: the root's, which holds the C++ part (oo::ToCxx reads it) and
// asks it the JS questions. Its selectors are members of the same names, and
// what its -respondsToSelector: answered for the category's two is
// answersJSClass().
class TestEntityObject final : public oo::RefCounted
{
public:
	const char *className() const  { return "Entity"; }	// the class's runtime name
	std::optional<std::string> cxx_descriptionComponents();
	bool answersJSClass();
	JSClassID oo_jsClassID();
	std::optional<std::string> cxx_oo_jsClassName();
	JSValue oo_jsValueInContext(JSContext *context);

	oo::Ref<Entity> _cxxEntity;
	std::string _name;
	JSValue _jsSelf = JS_UNDEFINED;	// owned; not an object until first asked for
};

/*	A station: the members the binding
   calls, declared as StationEntity.h declares them (the test imports no game
   header that defines the class), with the stand-in's answers. One whose
        equivalent tech level is 99 raises from getEquivalentTechLevel(), one
   whose level is 98 throws a C++ exception, so the test sees what an exception
   under a native becomes.
*/
class StationEntity : public ShipEntity
{
public:
	JSClassID jsClassID() override;
	std::optional<std::string> jsClassName() override;
	bool getHasNPCTraffic();
	void setHasNPCTraffic(bool flag);
	bool hasShipyard();
	OOStationAlertLevel getAlertLevel();
	void setAlertLevel(OOStationAlertLevel level, bool signallingScript);
	void increaseAlertLevel();
	void decreaseAlertLevel();
	std::optional<std::string> getAllegiance();
	void setAllegiance(const std::optional<std::string> &newAllegiance);
	bool getRequiresDockingClearance();
	void setRequiresDockingClearance(bool newValue);
	bool getAllowsFastDocking();
	void setAllowsFastDocking(bool newValue);
	bool getAllowsAutoDocking();
	void setAllowsAutoDocking(bool newValue);
	unsigned countOfDockedContractors();
	unsigned countOfDockedPolice();
	unsigned countOfDockedDefenders();
	OOTechLevelID getEquivalentTechLevel();
	float getEquipmentPriceFactor();
	bool suppressArrivalReports();
	void setSuppressArrivalReports(bool newValue);
	bool getHasBreakPattern();
	void setHasBreakPattern(bool newValue);
	std::vector<oo::PList> *getLocalShipyard();
	void generateShipyard();
	oo::PList localMarketForScripting();
	::OOCommodityMarket *getLocalMarket();
	void setPrice(OOCreditsQuantity price, const std::string &commodity);
	void setQuantity(OOCargoQuantity quantity, const std::string &commodity);
	void abortAllDockings();
	void abortDockingForShip(::ShipEntity *ship);
	bool fitsInDock(::ShipEntity *ship, bool logNoFit);
	oo::PList launchIndependentShip(const std::string &role);
	::ShipEntity *launchDefenseShip();
	::ShipEntity *launchEscort();
	::ShipEntity *launchScavenger();
	::ShipEntity *launchMiner();
	::ShipEntity *launchPirateShip();
	::ShipEntity *launchShuttle();
	::ShipEntity *launchPatrol();
	oo::PList launchPolice();
	void setInterfaceDefinition(::OOJSInterfaceDefinition *definition, const std::string &key);
	oo::PList getMarketDefinition();
	std::optional<std::string> getMarketScriptName();
	OOCargoQuantity getMarketCapacity();
	bool getMarketMonitored();

	::ShipEntity *launched(const char *what);

	std::string _name;
	bool _npcTraffic = false;
	bool _hasShipyard = false;
	OOStationAlertLevel _alertLevel = {};
	std::optional<std::string> _allegiance;
	bool _requiresClearance = false;
	float _roll = 0;
	bool _fastDocking = false;
	bool _autoDocking = false;
	unsigned _contractors = 0, _police = 0, _defenders = 0;
	OOTechLevelID _techLevel = 0;
	float _priceFactor = 0;
	bool _suppressReports = false;
	bool _breakPattern = false;
	std::vector<oo::PList> *_shipyard = nullptr;
	int _shipyardsMade = 0;
	oo::Ref<OOCommodityMarket> _market;
	int _abortAll = 0;
	::ShipEntity *_abortedShip = nullptr;
	bool _fits = false;
	std::map<std::string, oo::Ref<OOJSInterfaceDefinition>> _interfaces;
	std::string _lastLaunch;
	::ShipEntity *_launched = nullptr;
};

// PLAYER: the members the code under test calls, declared as the game headers
// declare them (the test imports none that defines the classes), with the
// stand-in's answers.
class PlayerEntity
{
public:
	::StationEntity * dockedStation();
	OOGUIScreenID guiScreen();
	void setGuiToMarketScreen();
	void setGuiToShipyardScreen(std::size_t skip);
	bool isDocked();
	void setDockingClearanceStatus(OODockingClearanceStatus newValue);
	void safeAllMissiles();
	void enterDock(::StationEntity *station);
	::OOScript * commodityScriptNamed(const std::optional<std::string> &scriptName);
	// OOEquipmentType.mm's (linked, never reached by these cases).
	oo::PList processKeyCode(const oo::PList &key_def);
	std::optional<std::string> validateKey(const std::string &key, const oo::PList &check_keys);
	oo::PList missionVariableForKey(const std::string &key);

	StationEntity *_dockedStation = {};
	OOGUIScreenID _screen = {};
	bool _docked = {};
	int _marketRefreshes = {};
	int _shipyardRefreshes = {};
	std::string _dockLog;
	std::string _name;
};

// The game controller: a stand-in for the C++ class, with the header's names
// and signatures, defined out of line below with the stand-in's answers.
class GameController : public oo::RefCounted
{
public:
	bool _paused = false;

	bool isGamePaused();
	void setGamePaused(bool value);
};

#include "UniverseStandIn.h"

// The universe as the code under test sees it: a stand-in for the C++ class
// with the header's names and signatures. It answers virtual members, so it has
// the game's vtable (UniverseStandIn.h) and StandInUniverse overrides them.
class Universe : public oo::RefCounted
{
public:
	OO_UNIVERSE_STAND_IN_VIRTUAL_MEMBERS

	StationEntity *_station;
	oo::Ref<OOCommodities> _commodities;
	GameController *_controller;
	OOViewID _view;

	::OOCommodities *getCommodities();
	::GameController *gameController();
	void setViewDirection(OOViewID);
	Random_Seed marketSeed();
	OOSystemID currentSystemID();
	::OOCommodityMarket *getCommodityMarket();	// link stub
	oo::PList getEquipmentData();	// link stub
	oo::PList getEquipmentDataOutfitting();	// link stub
};

// Link stubs, never reached: the code under test calls them on paths the test does not take.
::OOCommodityMarket *Universe::getCommodityMarket()  { std::abort(); }
oo::PList Universe::getEquipmentData()  { std::abort(); }
oo::PList Universe::getEquipmentDataOutfitting()  { std::abort(); }


class StandInUniverse : public Universe
{
public:
	::StationEntity *station() override	{ return _station; }
};

#include "ResourceManager.h"

// The engine (OOJavaScriptEngine.h), declared with the header's names and
// signatures but not its class.
class OOJavaScriptEngine
{
public:
	static OOJavaScriptEngine *sharedEngine();
	bool callJSFunction(JSValueConst function, JSValueConst jsThis, int argc, JSValueConst *argv, JSValue *outResult);
};


#include "OOJSStation.h"
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
std::map<Entity *, ::TestEntityObject *> sObjects;	// what TestObjectOf answers: each ship's object
}


std::optional<std::string> TestEntityObject::cxx_descriptionComponents()  { return _name; }

// As the game's Entity (OOJavaScriptExtensions) answers for an entity made in C++: its C++ part's.
bool TestEntityObject::answersJSClass()  { return _cxxEntity != nullptr; }
JSClassID TestEntityObject::oo_jsClassID()  { return _cxxEntity->jsClassID(); }
std::optional<std::string> TestEntityObject::cxx_oo_jsClassName()  { return _cxxEntity->jsClassName(); }

// TestEntityObject::oo_jsValueInContext() makes one: the class the entity's category names (its
// prototype is the class's), else the Ship class; the entity keeps it, and the caller owns the
// value returned.
JSValue TestEntityObject::oo_jsValueInContext(JSContext *context)
{
	if (!JS_IsObject(_jsSelf))
	{
		JSClassID classID = sFakeShipClassID;
		if (answersJSClass())  classID = oo_jsClassID();
		_jsSelf = JS_NewObjectClass(context, static_cast<int>(classID));
		if (JS_IsException(_jsSelf))
		{
			JS_FreeValue(context, JS_GetException(context));
			return JS_NULL;
		}
		if (_cxxEntity == nullptr)  _cxxEntity = oo::makeRef<Entity>();	// a plain entity's C++ part
		sObjects[_cxxEntity.get()] = this;
		OOJSSetCxxPrivate(_jsSelf, oo::makeRef<OOJSEntityHolder>(_cxxEntity.get()).get());	// the slot holds the C++ entity
	}
	return JS_DupValue(context, _jsSelf);
}


::TestEntityObject *TestObjectOf(Entity *entity);	// defined below
#define OO_ENTITY_HELPERS_STAND_IN_CXX
#include "EntityHelpersStandIn.h"	// EntityHelpers.mm's, on the test's objects

namespace {

// A ship's object (the root's, holding a C++ ship), kept for the life of the
// test.
::TestEntityObject *NewShipObject(const char *name, oo::Ref<Entity> ship)
{
	::TestEntityObject *object = oo::makeRef<::TestEntityObject>().leakRef();
	object->_cxxEntity = ship;
	object->_name = name;
	sObjects[ship.get()] = object;
	return object;
}

}	// namespace


Entity::~Entity() = default;
JSClassID Entity::jsClassID()  { return sFakeEntityClassID; }
std::optional<std::string> Entity::jsClassName()  { return std::nullopt; }
// What OOJSValueFromNativeObject made of the entity's object, which the binding
// returned: its -oo_jsValueInContext:, null for none.
JSValue Entity::jsValueInContext(JSContext *context)
{
	::TestEntityObject *object = TestObjectOf(this);
	return object != nullptr ? object->oo_jsValueInContext(context) : JS_NULL;
}
void Entity::clearJSSelf(JSValueConst)  {}
GLfloat ShipEntity::getFlightRoll()  { return static_cast<StationEntity *>(this)->_roll; }	// the cases ask stations only
void ShipEntity::setRawRoll(double amount)  { static_cast<StationEntity *>(this)->_roll = static_cast<float>(amount); }
OOAlertCondition ShipEntity::alertCondition()  { return static_cast<OOAlertCondition>(static_cast<StationEntity *>(this)->_alertLevel); }

// As StationEntity::jsClassID and ::jsClassName answer for the engine.
JSClassID StationEntity::jsClassID()  { return JSStationClassID(); }
std::optional<std::string> StationEntity::jsClassName()  { return OOJSStationJSClassName(); }
bool StationEntity::getHasNPCTraffic()  { return _npcTraffic; }
void StationEntity::setHasNPCTraffic(bool flag)  { _npcTraffic = flag; }
bool StationEntity::hasShipyard()  { return _hasShipyard; }
OOStationAlertLevel StationEntity::getAlertLevel()  { return _alertLevel; }
void StationEntity::increaseAlertLevel()  { _alertLevel = static_cast<OOStationAlertLevel>(static_cast<std::int32_t>(_alertLevel) + 1); }
void StationEntity::decreaseAlertLevel()  { _alertLevel = static_cast<OOStationAlertLevel>(static_cast<std::int32_t>(_alertLevel) - 1); }
std::optional<std::string> StationEntity::getAllegiance()  { return _allegiance; }
void StationEntity::setAllegiance(const std::optional<std::string> &newAllegiance)  { _allegiance = newAllegiance; }
bool StationEntity::getRequiresDockingClearance()  { return _requiresClearance; }
void StationEntity::setRequiresDockingClearance(bool newValue)  { _requiresClearance = newValue; }
bool StationEntity::getAllowsFastDocking()  { return _fastDocking; }
void StationEntity::setAllowsFastDocking(bool newValue)  { _fastDocking = newValue; }
bool StationEntity::getAllowsAutoDocking()  { return _autoDocking; }
void StationEntity::setAllowsAutoDocking(bool newValue)  { _autoDocking = newValue; }
unsigned StationEntity::countOfDockedContractors()  { return _contractors; }
unsigned StationEntity::countOfDockedPolice()  { return _police; }
unsigned StationEntity::countOfDockedDefenders()  { return _defenders; }
float StationEntity::getEquipmentPriceFactor()  { return _priceFactor; }
bool StationEntity::suppressArrivalReports()  { return _suppressReports; }
void StationEntity::setSuppressArrivalReports(bool newValue)  { _suppressReports = newValue; }
bool StationEntity::getHasBreakPattern()  { return _breakPattern; }
void StationEntity::setHasBreakPattern(bool newValue)  { _breakPattern = newValue; }
std::vector<oo::PList> *StationEntity::getLocalShipyard()  { return _shipyard; }
::OOCommodityMarket *StationEntity::getLocalMarket()  { return _market.get(); }
oo::PList StationEntity::localMarketForScripting()  { return _market->dictionaryForScripting(); }
void StationEntity::setPrice(OOCreditsQuantity price, const std::string &commodity)  { _market->setPrice(price, commodity); }
void StationEntity::setQuantity(OOCargoQuantity quantity, const std::string &commodity)  { _market->setQuantity(quantity, commodity); }
void StationEntity::abortAllDockings()  { _abortAll++; }
void StationEntity::abortDockingForShip(::ShipEntity *ship)  { _abortedShip = ship; }
bool StationEntity::fitsInDock(::ShipEntity *ship, bool logNoFit)  { (void)ship; (void)logNoFit; return _fits; }

void StationEntity::setAlertLevel(OOStationAlertLevel level, bool signallingScript)
{
	(void)signallingScript;
	if (level < OOStationAlertLevel::kGreen)  level = OOStationAlertLevel::kGreen;
	if (level > OOStationAlertLevel::kRed)  level = OOStationAlertLevel::kRed;
	_alertLevel = level;
}

OOTechLevelID StationEntity::getEquivalentTechLevel()
{
	if (_techLevel == 99)  OORaiseException(OOInvalidArgumentException, "techlevel %s", "boom");
	if (_techLevel == 98)  throw std::runtime_error("cxx boom");
	return _techLevel;
}

void StationEntity::generateShipyard()
{
	_shipyardsMade++;
	if (_shipyard == nullptr)  _shipyard = new std::vector<oo::PList>;
	_shipyard->push_back(oo::PList(oo::PList::Dict{ { "short_description", oo::PList(std::string("Cobra")) } }));
}

::ShipEntity *StationEntity::launched(const char *what)
{
	_lastLaunch = what;
	return _launched;
}

oo::PList StationEntity::launchIndependentShip(const std::string &role)  { _lastLaunch = "role " + role; return oo::EntityObjectNode(_launched); }	// the C++ entity's node
::ShipEntity *StationEntity::launchDefenseShip()  { return launched("defense"); }
::ShipEntity *StationEntity::launchEscort()  { return launched("escort"); }
::ShipEntity *StationEntity::launchScavenger()  { return launched("scavenger"); }
::ShipEntity *StationEntity::launchMiner()  { return launched("miner"); }
::ShipEntity *StationEntity::launchPirateShip()  { return launched("pirate"); }
::ShipEntity *StationEntity::launchShuttle()  { return launched("shuttle"); }
::ShipEntity *StationEntity::launchPatrol()  { return launched("patrol"); }

oo::PList StationEntity::launchPolice()
{
	_lastLaunch = "police";
	// The launched ship's node twice, as the array of its object twice was; none for no ship (the
	// nil object was left out). The C++ entity's nodes.
	oo::PList::Array ships;
	if (_launched != nullptr)  ships.push_back(oo::EntityObjectNode(_launched));
	if (_launched != nullptr)  ships.push_back(oo::EntityObjectNode(_launched));
	return oo::PList(std::move(ships));
}

void StationEntity::setInterfaceDefinition(::OOJSInterfaceDefinition *definition, const std::string &key)
{
	if (definition == nullptr)  _interfaces.erase(key);
	else  _interfaces[key] = oo::Ref<OOJSInterfaceDefinition>(definition);
}

// Link stubs: what the linked commodities ask a station for its market, and a station's object for
// a commodity script, which no case reaches (the stations' markets are made blank).
oo::PList StationEntity::getMarketDefinition()  { std::abort(); }
std::optional<std::string> StationEntity::getMarketScriptName()  { std::abort(); }
OOCargoQuantity StationEntity::getMarketCapacity()  { std::abort(); }
bool StationEntity::getMarketMonitored()  { std::abort(); }
::TestEntityObject *TestObjectOf(Entity *entity)
{
	auto found = sObjects.find(entity);
	return found != sObjects.end() ? found->second : nullptr;
}


::StationEntity * PlayerEntity::dockedStation()  { return _dockedStation; }
OOGUIScreenID PlayerEntity::guiScreen()  { return _screen; }
void PlayerEntity::setGuiToMarketScreen()  { _marketRefreshes++; }
void PlayerEntity::setGuiToShipyardScreen(std::size_t skip)  { (void)skip; _shipyardRefreshes++; }
bool PlayerEntity::isDocked()  { return _docked; }
void PlayerEntity::setDockingClearanceStatus(OODockingClearanceStatus newValue)
{
	_dockLog += "clearance " + std::to_string(static_cast<int>(newValue)) + "; ";
}
void PlayerEntity::safeAllMissiles()  { _dockLog += "safe; "; }
void PlayerEntity::enterDock(::StationEntity *station)
{
	_dockLog += "dock " + (station != nullptr ? station->_name : std::string("nil")); _docked = true;
}
oo::PList PlayerEntity::processKeyCode(const oo::PList &/*key_def*/)  { std::abort(); }
std::optional<std::string> PlayerEntity::validateKey(const std::string &/*key*/, const oo::PList &/*check_keys*/)  { std::abort(); }
oo::PList PlayerEntity::missionVariableForKey(const std::string &/*key*/)  { std::abort(); }
::OOScript * PlayerEntity::commodityScriptNamed(const std::optional<std::string> &script)  { (void)script; return nullptr; }


bool GameController::isGamePaused()  { return _paused; }
void GameController::setGamePaused(bool value)  { _paused = value; }


::OOCommodities *Universe::getCommodities()	{ return _commodities.get(); }
::GameController *Universe::gameController()	{ return _controller; }
void Universe::setViewDirection(OOViewID vd)	{ _view = vd; }
Random_Seed Universe::marketSeed()	{ return Random_Seed{}; }
OOSystemID Universe::currentSystemID()	{ return 7; }


// The ship registry: a C++ stand-in.
OOShipRegistry *OOShipRegistry::sharedRegistry()  { return nullptr; }	// the test adds no ship to a shipyard
oo::PList OOShipRegistry::shipInfoForKey(const std::string &key)  { (void)key; return oo::PList(); }
oo::PList OOShipRegistry::shipyardInfoForKey(const std::string &key)  { (void)key; return oo::PList(); }


// ResourceManager: C++ definitions of the statics the code under test calls,
// with the stand-in's answers. trade-goods.plist: food and gems.
oo::PList ResourceManager::dictionaryFromFilesNamed(const std::string &fileName, const std::optional<std::string> &folderName, OOResourceMergeMode mergeMode, bool useCache)
{
	(void)fileName; (void)folderName; (void)mergeMode; (void)useCache;
	return oo::PList(oo::PList::Dict{
		{ "food", oo::PList(oo::PList::Dict{ { "name", oo::PList(std::string("Food")) }, { "quantity_unit", oo::PList(0.0) }, { "price_average", oo::PList(50.0) }, { "quantity_average", oo::PList(40.0) }, { "capacity", oo::PList(100.0) } }) },
		{ "gems", oo::PList(oo::PList::Dict{ { "name", oo::PList(std::string("Gem-stones")) }, { "quantity_unit", oo::PList(2.0) }, { "price_average", oo::PList(160.0) }, { "quantity_average", oo::PList(200.0) } }) },
	});
}



OOJavaScriptEngine *OOJavaScriptEngine::sharedEngine()
{
	static OOJavaScriptEngine *engine = new OOJavaScriptEngine;
	return engine;
}

// The interface definitions' callback call: never reached here (the stand-in did not answer it).
bool OOJavaScriptEngine::callJSFunction(JSValueConst, JSValueConst, int, JSValueConst *, JSValue *)  { std::abort(); }


#include "OOScript.h"


// OOJSScript (OOJSScript.h), which the code under test calls. A script is a
// C++ object, so the stand-in is a C++ subclass of OOScript declaring the
// members that code calls.
class OOJSScript : public OOScript
{
public:
	static OOJSScript *currentlyRunningScript();
	static void pushScript(const oo::WeakRef<OOJSScript> &script);
	static void popScript(OOJSScript *script);
};

OOJSScript *OOJSScript::currentlyRunningScript()  { return nullptr; }
// The interface definition linked here pushes its owner when its callback runs, which no case does
// (the class methods were never sent; as C++ statics they must be defined).
void OOJSScript::pushScript(const oo::WeakRef<OOJSScript> &)  { std::abort(); }
void OOJSScript::popScript(OOJSScript *)  { std::abort(); }


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

#include "OOCacheManager.h"

// Link stubs: what OOEquipmentType reaches to load
// equipment, which the test never does (no equipment type is made), and the
// weapon lookups of addShipToShipyard(), which the test's shipyard items never
// reach.
OOCacheManager *OOCacheManager::sharedCache()  { std::abort(); }
void OOCacheManager::setPList(const oo::PList &, const std::string &, const std::string &)  { std::abort(); }

oo::Ref<OOScript> OOScript::jsScriptFromFileNamed(const std::string &, const oo::PList &)  { std::abort(); }
void OOScriptAutorelease(oo::Ref<OOScript>)  { std::abort(); }

void cxx_OOStandardsDeprecated(const std::string&) { std::abort(); }
bool OOEnforceStandards(void) { std::abort(); }
oo::PList OOSanitizeLegacyScriptConditions(const oo::PList&,
                                           const std::optional<std::string>&) {
  std::abort();
}
OOWeaponType cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(const std::string&) {
  std::abort();
}
bool isWeaponNone(OOWeaponType) { std::abort(); }

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
bool OOJSValueToInt32(JSContext *context, JSValueConst value, int32_t *outValue)
{
	double number;
	if (JS_ToFloat64(context, &number, value) < 0)  return false;
	number = std::floor(number + 0.5);
	if (std::isnan(number) || number < INT32_MIN || number > INT32_MAX)
	{
		cxx_OOJSReportError(context, "can't convert %s to an integer", cxx_OOStringFromJSValue(context, value).value_or("(null)").c_str());
		return false;
	}
	*outValue = static_cast<int32_t>(number);
	return true;
}


// A property list as JavaScript, as far as the binding hands one over: null, a string, a number,
// an object (its JS value), or an array or dictionary of those. Owned by the caller.
JSValue OOJSValueFromPList(JSContext *context, const oo::PList &plist)
{
	if (const std::string *str = plist.getIf<std::string>())  return JS_NewStringLen(context, str->data(), str->size());
	if (plist.isNumber())  return JS_NewNumber(context, plist.doubleValue());
	if (Entity *entity = oo::EntityIn(plist))	// an entity's node: its object's value, as OOJSValueFromNativeObject() gave it
	{
		::TestEntityObject *object = TestObjectOf(entity);
		return object != nullptr ? object->oo_jsValueInContext(context) : JS_NULL;
	}
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
PlayerEntity *sPlayer = nullptr;
}

JSContext *gOOJSMainThreadContext = nullptr;
Entity *gOOJSPlayerIfStale = nullptr;	// the player's C++ entity
PlayerEntity *gOOPlayer = nullptr;
Universe *gSharedUniverse = nullptr;


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


// The engine's object getter is OOJSPrivateObject.cpp's (linked): the JS class
// must be a subclass of the required one, and the slot holds the entity's
// holder. Class registration and
// the subclass table are OOJSClasses.mm's (linked).

// The shared toString(), which OOJSCxxObjectWrapperToString() hands a `this` of
// another class.
JSValue OOJSObjectWrapperToString(JSContext *context, JSValueConst, int, JSValueConst *)
{
	return JS_NewString(context, "[object]");
}


JSValue OOJSUnconstructableConstruct(JSContext *context, JSValueConst, int, JSValueConst *)
{
	cxx_OOJSReportError(context, "unconstructable");
	return JS_EXCEPTION;
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
JSValue sGlobal = JS_UNDEFINED;
StationEntity *sStation = nullptr;	// the C++ station (its object: sStationObject)
StationEntity *sOther = nullptr;
::TestEntityObject *sStationObject = nullptr;
::TestEntityObject *sOtherObject = nullptr;
::TestEntityObject *sShip = nullptr;	// a ship's object and its C++ part
::ShipEntity *sShipPart = nullptr;
Universe *sUniverse = nullptr;


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

	sUniverse = new StandInUniverse();	// kept for the life of the test
	gSharedUniverse = sUniverse;
	sUniverse->_controller = new GameController();	// kept for the life of the test
	sUniverse->_commodities = oo::makeRef<OOCommodities>();
	sPlayer = new PlayerEntity;
	sPlayer->_name = "player";
	sPlayer->_screen = OOGUIScreenID::kStatus;
	gOOPlayer = sPlayer;
	sStationObject = NewShipObject("Coriolis", oo::makeRef<StationEntity>());	// kept for the life of the
                                                    // test; a station's object
	sStation = static_cast<StationEntity *>(sStationObject->_cxxEntity.get());
	sStation->_name = "Coriolis";
	sStation->_npcTraffic = true;
	sStation->_alertLevel = OOStationAlertLevel::kGreen;
	sStation->_allegiance = "galcop";
	sStation->_roll = 0.25f;
	sStation->_autoDocking = true;
	sStation->_contractors = 2;
	sStation->_police = 3;
	sStation->_defenders = 4;
	sStation->_techLevel = 9;
	sStation->_priceFactor = 1.5f;
	sStation->_market = sUniverse->_commodities->generateBlankMarket();
	sUniverse->_station = sStation;
	sOtherObject = NewShipObject("Rock Hermit", oo::makeRef<StationEntity>());
	sOther = static_cast<StationEntity *>(sOtherObject->_cxxEntity.get());
	sOther->_name = "Rock Hermit";
	sShip = NewShipObject("Cobra", oo::makeRef<::ShipEntity>());
	sShipPart = static_cast<::ShipEntity *>(sShip->_cxxEntity.get());
	Define("station", sStationObject->oo_jsValueInContext(sContext));
	Define("other", sOtherObject->oo_jsValueInContext(sContext));
	Define("ship", sShip->oo_jsValueInContext(sContext));
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
	const JSClassID stationClass = sStationObject->oo_jsClassID();
	OO_CHECK(stationClass != 0 && OOJSClassName(stationClass) != nullptr && std::strcmp(OOJSClassName(stationClass), "Station") == 0);
	JSValue prototype = JS_GetClassProto(sContext, stationClass);
	OO_CHECK(JS_IsObject(prototype));
	JS_FreeValue(sContext, prototype);
	OO_CHECK(OOJSIsSubclass(stationClass, sFakeShipClassID));
	OO_CHECK_EQ(sConverters[stationClass], 1);
	OO_CHECK(sStationObject->cxx_oo_jsClassName() == std::optional<std::string>("Station"));
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
	sStation->_npcTraffic = true;
	sStation->_allegiance = "galcop";
	sStation->_requiresClearance = false;
	sStation->_roll = 0.25f;
	sStation->_fastDocking = false;
	sStation->_autoDocking = true;
	sStation->_suppressReports = false;
	sStation->_breakPattern = false;
}


OO_TEST(docking)
{
	SetUpContext();
	sStation->_abortAll = 0;
	OO_CHECK_EVAL("station.abortAllDockings()", "undefined");
	OO_CHECK_EQ(sStation->_abortAll, 1);
	OO_CHECK_EVAL("station.abortDockingForShip(ship)", "undefined");
	OO_CHECK(sStation->_abortedShip == sShipPart);
	OO_CHECK_EVAL("station.abortDockingForShip()", "threw: bad arguments: Station.abortDockingForShip(0) - / ship in docking queue");
	sStation->_fits = true;
	OO_CHECK_EVAL("station.canDockShip(ship)", "true");
	sStation->_fits = false;
	OO_CHECK_EVAL("station.canDockShip(ship)", "false");
	OO_CHECK_EVAL("station.canDockShip()", "threw: bad arguments: Station.canDockShip(0) - / shipEntity");
	// dockPlayer(): unpauses the game, then docks the player unless it is docked.
	sUniverse->_controller->_paused = true;
	OO_CHECK_EVAL("station.dockPlayer()", "undefined");
	OO_CHECK(!sUniverse->_controller->_paused);
	OO_CHECK_EQ(sPlayer->_dockLog, "clearance " + std::to_string(static_cast<int>(OODockingClearanceStatus::kGranted)) + "; safe; dock Coriolis");
	OO_CHECK_EQ(static_cast<int>(sUniverse->_view), static_cast<int>(OOViewID::kForward));
	sPlayer->_dockLog.clear();
	OO_CHECK_EVAL("other.dockPlayer()", "undefined");
	OO_CHECK_EQ(sPlayer->_dockLog, std::string());
	sPlayer->_docked = false;
}


OO_TEST(alertLevel)
{
	SetUpContext();
	sStation->_alertLevel = OOStationAlertLevel::kGreen;
	OO_CHECK_EVAL("(function () { station.increaseAlertLevel(); station.increaseAlertLevel(); station.increaseAlertLevel(); return station.alertCondition; })()", "3");
	OO_CHECK_EVAL("(function () { station.decreaseAlertLevel(); station.decreaseAlertLevel(); station.decreaseAlertLevel(); return station.alertCondition; })()", "1");
}


OO_TEST(launches)
{
	SetUpContext();
	sStation->_launched = sShipPart;
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
	sStation->_launched = nullptr;
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
		OO_CHECK(definition->title() == std::optional<std::string>("T"));
		OO_CHECK(definition->summary() == std::optional<std::string>("S"));
		OO_CHECK(definition->category() == std::optional<std::string>("C"));
		JSValue callback = definition->callback();
		JSValue callbackThis = definition->callbackThis();
		OO_CHECK(JS_IsObject(callback) && !JS_IsObject(callbackThis));
		JS_FreeValue(sContext, callbackThis);
		JS_FreeValue(sContext, callback);
	}
	OO_CHECK_EVAL("station.setInterface('k2', {title: 'T', summary: 'S', callback: function () {}, cbThis: station})", "undefined");
	OO_CHECK(sStation->_interfaces.count("k2") == 1 && sStation->_interfaces["k2"]->category() == std::optional<std::string>("desc(interfaces-category-uncategorised)"));
	OO_CHECK(sStation->_interfaces.count("k2") == 1 && SameObject(sStation->_interfaces["k2"]->callbackThis(), sStationObject->_jsSelf));
	OO_CHECK_EVAL("station.setInterface('k2', {title: 'T', summary: 'S', category: '', callback: function () {}})", "undefined");
	OO_CHECK(sStation->_interfaces.count("k2") == 1 && sStation->_interfaces["k2"]->category() == std::optional<std::string>("desc(interfaces-category-uncategorised)"));
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
	OO_CHECK_EQ(sStation->_market->priceForGood("food"), 120u);
	// A blank market has no capacity: only 0 fits.
	sStation->_market->setQuantity(5, "food");
	OO_CHECK_EVAL("station.setMarketQuantity('food', 0)", "true");
	OO_CHECK_EQ(sStation->_market->quantityForGood("food"), 0u);
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
	sPlayer->_screen = OOGUIScreenID::kMarket;
	sPlayer->_marketRefreshes = 0;
	OO_CHECK_EVAL("station.setMarketPrice('food', 100) && station.setMarketQuantity('food', 0)", "true");
	OO_CHECK_EQ(sPlayer->_marketRefreshes, 2);
	sPlayer->_dockedStation = nullptr;
	sPlayer->_screen = OOGUIScreenID::kStatus;
}


OO_TEST(shipyard)
{
	SetUpContext();
	sLastWarning.clear();
	OO_CHECK_EVAL("station.addShipToShipyard({short_description: 'x'})", "<evaluation failed>");
	OO_CHECK_EQ(sLastWarning, std::string("Station.removeShipFromShipyard: Station does not have shipyard."));
	OO_CHECK_EVAL("station.removeShipFromShipyard(0)", "<evaluation failed>");
	sStation->_hasShipyard = true;
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
	sPlayer->_screen = OOGUIScreenID::kShipyard;
	OO_CHECK_EVAL("station.removeShipFromShipyard(0) + ' ' + station.shipyard.length", "true 0");
	OO_CHECK_EQ(sPlayer->_shipyardRefreshes, 1);
	sPlayer->_dockedStation = nullptr;
	sPlayer->_screen = OOGUIScreenID::kStatus;
	sStation->_hasShipyard = false;
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


// The JS glue of OOEquipmentType (OOJSPrivateObject), defined in OOJSEquipmentInfo.mm, which
// this test does not link: the vtable names these.
JSValue OOEquipmentType::jsValueInContext(JSContext *)  { return JS_UNDEFINED; }
void OOEquipmentType::clearJSSelf(JSValueConst)  {}
std::optional<std::string> OOEquipmentType::jsDescription()  { return std::nullopt; }


OO_TEST_MAIN()
