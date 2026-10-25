/*	test_OOJSStation.mm
	Unit tests for the Station JS binding (src/Core/Scripting/OOJSStation.h/.mm) and its
	StationEntity answers for the class (StationEntity::getJSClass): bead oo-3oxq, converted the way bead oo-ppc
	converted OOJSVector (proposed ADR-0056 amendments oo-ppc, oo-ykoy and oo-6ia4).

	As test_OOJSWormhole.mm does (amendment oo-ykoy, item 4), it runs the JS class in a real
	context on the game's own façade backend (ooscript/JSEngine_quickjs.cpp), links the game's own
	objects for the binding, its bridge, the engine's exception translator
	(OOJSEngineNativeWrappers.mm) and the converted classes it uses (OOCommodities and
	OOCommodityMarket, C++ since beads oo-9ht.25 and oo-9ht.21 deleted their façades (held as
	oo::Ref), OOEquipmentType, reached through its façade, and OOJSInterfaceDefinition, C++ since
	bead oo-9ht.61 deleted its façade), and
	stands in for the classes the binding messages (Entity, ShipEntity and StationEntity, the
	player, the universe, the game controller and the ship registry answer only the selectors the
	binding sends), for the resource manager and string expander the commodities call, the script
	engine and running script the interface definitions call, and the engine functions the binding
	links against, with the engine headers' linkage. The expectations were written against the
	Objective-C file and run on it first; they pin the JS-visible behaviour (the properties both
	ways, docking, the alert level, the launches, the interfaces, the market, the shipyard's errors,
	a non-station, a native's exception) and what the category answers the engine.
	Run: bash tools/check-core-tests.sh
*/

#include "OOCocoa.h"
#include "OOCommodities.h"
#include "OOCommodityMarket.h"
#include "OOJSInterfaceDefinition.h"
#include "OOEquipmentType.h"
#include "OOStringExpander.h"
#include "OOShipRegistry.h"
#include "OOTypes.h"
#include "OOEntityEnums.h"
#include "ooscript/JSEngine.hpp"
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#include "OODescription.h"
#include "OOObjCPList.h"
#include "EntityPListForeign.h"	// an entity's node (bead oo-dpyk8)


// MARK: The classes, as far as the binding sees them ----------------------------------------------

class StationEntity;
class GameController;

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

#include "OOJSPrivateObject.h"

// The C++ root, as far as the binding and the root's JS category reach it; its JS glue
// (OOJSPrivateObject, as the game's root implements it) answers its object's JS value
// (bead oo-9ht.39.8.2: the binding's launches return OOJSValueFromCxxObject of the C++ ship).
class Entity : public oo::RefCounted, public OOJSPrivateObject
{
public:
	virtual ~Entity();
	virtual void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype);
	virtual std::optional<std::string> jsClassName();
	ooscript::Value jsValueInContext(ooscript::Context context) override;
	void clearJSSelf(ooscript::Object selfVal) override;
};

// The ship's members the binding calls on a station, by their final overrider (bead oo-9ht.175);
// the ship is C++ since bead oo-9ht.144 deleted the Objective-C ship (a ship's part is a plain one).
class ShipEntity : public Entity
{
public:
	GLfloat getFlightRoll();
	void setRawRoll(double amount);
	OOAlertCondition alertCondition();
};

// What an entity's JS object holds since bead oo-9ht.39.3: a weak reference to the C++ entity.
#include "OOJSEntityHolder.h"

// The object: the root's, which holds the C++ part (oo::ToCxx reads it) and asks it the JS questions.
// C++ since bead oo-4aq6a.12 (it was rooted on the Objective-C root class OOObject, which Phase 4
// deletes); its selectors are members of the same names, and what its -respondsToSelector: answered
// for the category's two is answersJSClass().
class TestEntityObject final : public oo::RefCounted
{
public:
	const char *className() const  { return "Entity"; }	// its Objective-C class's runtime name
	std::optional<std::string> cxx_descriptionComponents();
	bool answersJSClass();
	void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype);
	std::optional<std::string> cxx_oo_jsClassName();
	ooscript::Value oo_jsValueInContext(ooscript::Context context);

	oo::Ref<Entity> _cxxEntity;
	std::string _name;
	ooscript::Object _jsSelf = nullptr;
};

/*	A station: C++ since bead oo-9ht.175 deleted the Objective-C station this stood in for (its object
	is the ship's facade); the members the binding calls, declared as StationEntity.h declares them
	(the test imports no game header that defines the class), with the stand-in's answers. One whose
	equivalent tech level is 99 raises from getEquivalentTechLevel(), one whose level is 98 throws a
	C++ exception, so the test sees what an exception under a native becomes.
*/
class StationEntity : public ShipEntity
{
public:
	void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype) override;
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
	BOOL _npcTraffic = NO;
	BOOL _hasShipyard = NO;
	OOStationAlertLevel _alertLevel = {};
	std::optional<std::string> _allegiance;
	BOOL _requiresClearance = NO;
	float _roll = 0;
	BOOL _fastDocking = NO;
	BOOL _autoDocking = NO;
	unsigned _contractors = 0, _police = 0, _defenders = 0;
	OOTechLevelID _techLevel = 0;
	float _priceFactor = 0;
	BOOL _suppressReports = NO;
	BOOL _breakPattern = NO;
	std::vector<oo::PList> *_shipyard = nullptr;
	int _shipyardsMade = 0;
	oo::Ref<OOCommodityMarket> _market;
	int _abortAll = 0;
	::ShipEntity *_abortedShip = nullptr;
	BOOL _fits = NO;
	std::map<std::string, oo::Ref<OOJSInterfaceDefinition>> _interfaces;
	std::string _lastLaunch;
	::ShipEntity *_launched = nil;
};

// PLAYER: C++ since bead oo-9ht.177 deleted the Objective-C player this stood in for: the members
// the code under test calls, declared as the game headers declare them (the test imports none
// that defines the classes), with the stand-in's answers.
class PlayerEntity
{
public:
	::StationEntity * dockedStation();
	OOGUIScreenID guiScreen();
	void setGuiToMarketScreen();
	void setGuiToShipyardScreen(NSUInteger skip);
	bool isDocked();
	void setDockingClearanceStatus(OODockingClearanceStatus newValue);
	void safeAllMissiles();
	void enterDock(::StationEntity *station);
	::OOScript * commodityScriptNamed(const std::optional<std::string> &scriptName);
	// OOEquipmentType.mm's (linked, never reached by these cases: the Objective-C stand-in had none).
	oo::PList processKeyCode(const oo::PList &key_def);
	std::optional<std::string> validateKey(const std::string &key, const oo::PList &check_keys);
	oo::PList missionVariableForKey(const std::string &key);

	StationEntity *_dockedStation = {};
	OOGUIScreenID _screen = {};
	BOOL _docked = {};
	int _marketRefreshes = {};
	int _shipyardRefreshes = {};
	std::string _dockLog;
	std::string _name;
};

// The game controller: a stand-in for the C++ class (bead oo-9ht.164 deleted the Objective-C facade
// the test's Objective-C stand-in stood in for), with the header's names and signatures, defined out
// of line below with the stand-in's answers.
class GameController : public oo::RefCounted
{
public:
	BOOL _paused = NO;

	bool isGamePaused();
	void setGamePaused(bool value);
};

#include "UniverseStandIn.h"

// The universe as the code under test sees it: a stand-in for the C++ class (bead oo-ql9rn deleted
// the Objective-C facade the test's Objective-C stand-in stood in for), with the header's names and signatures.
// It answers virtual members, so it has the game's vtable (UniverseStandIn.h) and StandInUniverse overrides them.
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

// Link stubs, never reached: the code under test calls them on paths the test does not take (the
// Objective-C stand-in did not answer them; bead oo-ql9rn).
::OOCommodityMarket *Universe::getCommodityMarket()  { std::abort(); }
oo::PList Universe::getEquipmentData()  { std::abort(); }
oo::PList Universe::getEquipmentDataOutfitting()  { std::abort(); }


class StandInUniverse : public Universe
{
public:
	::StationEntity *station() override	{ return _station; }
};

#include "ResourceManager.h"

// The engine (OOJavaScriptEngine.h; a C++ class since bead oo-wdqw1 deleted its facade), declared
// with the header's names and signatures but not its class.
class OOJavaScriptEngine
{
public:
	static OOJavaScriptEngine *sharedEngine();
	bool callJSFunction(ooscript::Value function, ooscript::Object jsThis, unsigned argc, ooscript::Value *argv, ooscript::Value *outResult);
};


#include "OOJSStation.h"

#include "oo_test.hpp"

#include <cstdarg>
#include <cstdint>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>


namespace {
ooscript::Context sContext;
ooscript::ClassDef sFakeEntityClass = { "Entity", ooscript::ClassFlag::HasPrivate };
ooscript::ClassDef sFakeShipClass = { "Ship", ooscript::ClassFlag::HasPrivate };
ooscript::Object sShipPrototype = nullptr;
std::map<ooscript::ClassDef *, ooscript::ClassDef *> sSuperclasses;
std::map<ooscript::ClassDef *, int> sConverters;
std::map<Entity *, ::TestEntityObject *> sObjects;	// what TestObjectOf answers (oo::ToObjC until bead oo-4aq6a.12): each ship's object
}

ooscript::Object gOOEntityJSPrototype = nullptr;


std::optional<std::string> TestEntityObject::cxx_descriptionComponents()  { return _name; }

// As the game's Entity (OOJavaScriptExtensions) answers for an entity made in C++: its C++ part's.
bool TestEntityObject::answersJSClass()  { return _cxxEntity != nullptr; }
void TestEntityObject::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)  { _cxxEntity->getJSClass(outClass, outPrototype); }
std::optional<std::string> TestEntityObject::cxx_oo_jsClassName()  { return _cxxEntity->jsClassName(); }

// As -[TestEntityObject oo_jsValueInContext:] made one: the class and prototype the entity's category names.
ooscript::Value TestEntityObject::oo_jsValueInContext(ooscript::Context context)
{
	if (_jsSelf == nullptr)
	{
		ooscript::ClassDef *jsClass = &sFakeShipClass;
		ooscript::Object prototype = sShipPrototype;
		if (answersJSClass())  getJSClass(&jsClass, &prototype);
		_jsSelf = ooscript::newObject(context, jsClass, prototype, nullptr);
		if (_cxxEntity == nullptr)  _cxxEntity = oo::makeRef<Entity>();	// a plain entity's C++ part
		sObjects[_cxxEntity.get()] = this;
		OOJSSetCxxPrivate(context, _jsSelf, oo::makeRef<OOJSEntityHolder>(_cxxEntity.get()).get());	// the slot holds the C++ entity (bead oo-9ht.39.3)
	}
	return ooscript::objectValue(_jsSelf);
}


::TestEntityObject *TestObjectOf(Entity *entity);	// Entity+ObjCBridge.mm's oo::ToObjC until bead oo-4aq6a.12, defined below
#define OO_ENTITY_HELPERS_STAND_IN_CXX
#include "EntityHelpersStandIn.h"	// EntityHelpers.mm's, on the test's objects (bead oo-dpyk8)

namespace {

// A ship's object (the root's, holding a C++ ship since bead oo-9ht.144 deleted the Objective-C
// ship this made), kept for the life of the test.
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
void Entity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)  { (void)outClass; (void)outPrototype; }
std::optional<std::string> Entity::jsClassName()  { return std::nullopt; }
// What OOJSValueFromNativeObject made of the entity's object, which the binding returned until bead
// oo-9ht.39.8.2: its -oo_jsValueInContext:, null for none.
ooscript::Value Entity::jsValueInContext(ooscript::Context context)
{
	::TestEntityObject *object = TestObjectOf(this);
	return object != nullptr ? object->oo_jsValueInContext(context) : ooscript::nullValue();
}
void Entity::clearJSSelf(ooscript::Object)  {}
GLfloat ShipEntity::getFlightRoll()  { return static_cast<StationEntity *>(this)->_roll; }	// the cases ask stations only
void ShipEntity::setRawRoll(double amount)  { static_cast<StationEntity *>(this)->_roll = static_cast<float>(amount); }
OOAlertCondition ShipEntity::alertCondition()  { return static_cast<OOAlertCondition>(static_cast<StationEntity *>(this)->_alertLevel); }

// As StationEntity::getJSClass and ::jsClassName answer for the engine.
void StationEntity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)  { OOJSStationGetJSClass(outClass, outPrototype); }
std::optional<std::string> StationEntity::jsClassName()  { return OOJSStationJSClassName(); }
bool StationEntity::getHasNPCTraffic()  { return _npcTraffic; }
void StationEntity::setHasNPCTraffic(bool flag)  { _npcTraffic = flag; }
bool StationEntity::hasShipyard()  { return _hasShipyard; }
OOStationAlertLevel StationEntity::getAlertLevel()  { return _alertLevel; }
void StationEntity::increaseAlertLevel()  { _alertLevel = static_cast<OOStationAlertLevel>(_alertLevel + 1); }
void StationEntity::decreaseAlertLevel()  { _alertLevel = static_cast<OOStationAlertLevel>(_alertLevel - 1); }
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
	if (level < STATION_ALERT_LEVEL_GREEN)  level = STATION_ALERT_LEVEL_GREEN;
	if (level > STATION_ALERT_LEVEL_RED)  level = STATION_ALERT_LEVEL_RED;
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

oo::PList StationEntity::launchIndependentShip(const std::string &role)  { _lastLaunch = "role " + role; return oo::EntityObjectNode(_launched); }	// the C++ entity's node (bead oo-dpyk8)
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
	// nil object was left out). The C++ entity's nodes since bead oo-dpyk8.
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
void PlayerEntity::setGuiToShipyardScreen(NSUInteger skip)  { (void)skip; _shipyardRefreshes++; }
bool PlayerEntity::isDocked()  { return _docked; }
void PlayerEntity::setDockingClearanceStatus(OODockingClearanceStatus newValue)
{
	_dockLog += "clearance " + std::to_string(static_cast<int>(newValue)) + "; ";
}
void PlayerEntity::safeAllMissiles()  { _dockLog += "safe; "; }
void PlayerEntity::enterDock(::StationEntity *station)
{
	_dockLog += "dock " + (station != nil ? station->_name : std::string("nil")); _docked = YES;
}
oo::PList PlayerEntity::processKeyCode(const oo::PList &/*key_def*/)  { std::abort(); }
std::optional<std::string> PlayerEntity::validateKey(const std::string &/*key*/, const oo::PList &/*check_keys*/)  { std::abort(); }
oo::PList PlayerEntity::missionVariableForKey(const std::string &/*key*/)  { std::abort(); }
::OOScript * PlayerEntity::commodityScriptNamed(const std::optional<std::string> &script)  { (void)script; return nil; }


bool GameController::isGamePaused()  { return _paused; }
void GameController::setGamePaused(bool value)  { _paused = value; }


::OOCommodities *Universe::getCommodities()	{ return _commodities.get(); }
::GameController *Universe::gameController()	{ return _controller; }
void Universe::setViewDirection(OOViewID vd)	{ _view = vd; }
Random_Seed Universe::marketSeed()	{ return Random_Seed{}; }
OOSystemID Universe::currentSystemID()	{ return 7; }


// The ship registry is C++ (bead oo-9ht.122): a C++ stand-in with the facade stand-in's answers.
OOShipRegistry *OOShipRegistry::sharedRegistry()  { return nullptr; }	// the test adds no ship to a shipyard
oo::PList OOShipRegistry::shipInfoForKey(const std::string &key)  { (void)key; return oo::PList(); }
oo::PList OOShipRegistry::shipyardInfoForKey(const std::string &key)  { (void)key; return oo::PList(); }


// ResourceManager is C++ since bead oo-9ht.150 deleted its Objective-C facade: C++ definitions of the
// statics the code under test calls, with the Objective-C stand-in's answers.
// trade-goods.plist: food and gems.
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
bool OOJavaScriptEngine::callJSFunction(ooscript::Value, ooscript::Object, unsigned, ooscript::Value *, ooscript::Value *)  { std::abort(); }


#include "OOScript.h"


// OOJSScript (OOJSScript.h), which the code under test calls. Since bead oo-9ht.133 deleted the
// OOScript root's facade (a script's object since bead oo-9ht.137) a script is the C++ object, so
// the stand-in is a C++ subclass of OOScript declaring the members that code calls.
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

// Link stubs (amendment oo-zffj item 2): what OOEquipmentType reaches to load equipment, which the
// test never does (no equipment type is made), and the weapon lookups of addShipToShipyard(), which
// the test's shipyard items never reach.
OOCacheManager *OOCacheManager::sharedCache()  { std::abort(); }	// C++ since bead oo-9ht.31 (was an empty Objective-C class)
void OOCacheManager::setPList(const oo::PList &, const std::string &, const std::string &)  { std::abort(); }

oo::Ref<OOScript> OOScript::jsScriptFromFileNamed(const std::string &, const oo::PList &)  { std::abort(); }
void OOScriptAutorelease(oo::Ref<OOScript>)  { std::abort(); }

void cxx_OOStandardsDeprecated(const std::string &)  { std::abort(); }
extern "C" BOOL OOEnforceStandards(void)  { std::abort(); }
oo::PList OOSanitizeLegacyScriptConditions(const oo::PList &, const std::optional<std::string> &)  { std::abort(); }
OOWeaponType cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(const std::string &)  { std::abort(); }
extern "C" BOOL isWeaponNone(OOWeaponType)  { std::abort(); }

extern const char * const kOOJavaScriptEngineWillResetNotificationName;
const char * const kOOJavaScriptEngineWillResetNotificationName = "org.aegidian.oolite OOJavaScriptEngine will reset";


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

void cxx_OOJSReportWarningForCaller(ooscript::Context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	sLastWarning = scriptClass.value_or("-") + "." + function.value_or("-") + ": " + oo::str::vformat(format, args);
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
	if (Entity *entity = oo::EntityIn(plist))	// an entity's node: its object's value (bead oo-dpyk8), as OOJSValueFromNativeObject() gave it
	{
		::TestEntityObject *object = TestObjectOf(entity);
		return object != nullptr ? object->oo_jsValueInContext(context) : ooscript::nullValue();
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


// An object as a dictionary, as far as the test hands one over: its "short_description" property.
oo::PList cxx_OOJSPListFromJSObject(ooscript::Context context, ooscript::Object object)
{
	if (ooscript::isArrayObject(context, object))  return oo::PList(oo::PList::Array{});
	oo::PList::Dict dict;
	ooscript::Value value = ooscript::undefinedValue();
	if (ooscript::getProperty(context, object, "short_description", &value) && !ooscript::isUndefined(value))  dict["short_description"] = oo::PList(cxx_OOStringFromJSValue(context, value).value_or(""));
	return oo::PList(std::move(dict));
}


namespace {
PlayerEntity *sPlayer = nullptr;
}

ooscript::Context gOOJSMainThreadContext = nullptr;
Entity *gOOJSPlayerIfStale = nullptr;	// the player's C++ entity (bead oo-9ht.39.25)
PlayerEntity *gOOPlayer = nullptr;
Universe *gSharedUniverse = nil;


extern "C" {

PlayerEntity *OOPlayerForScripting(void)
{
	return sPlayer;
}


ooscript::ClassDef *JSEntityClass(void)
{
	return &sFakeEntityClass;
}


ooscript::ClassDef *JSShipClass(void)
{
	return &sFakeShipClass;
}


ooscript::Object JSShipPrototype(void)
{
	return sShipPrototype;
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



void OOJSInitJSIDCachePRIVATE(const char *, ooscript::PropertyId *)
{
	std::abort();	// link stub: the commodity classes' script path
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
ooscript::Object sGlobal;
StationEntity *sStation = nullptr;	// the C++ station (its object: sStationObject)
StationEntity *sOther = nullptr;
::TestEntityObject *sStationObject = nullptr;
::TestEntityObject *sOtherObject = nullptr;
::TestEntityObject *sShip = nullptr;	// a ship's object and its C++ part
::ShipEntity *sShipPart = nullptr;
Universe *sUniverse = nil;


void Define(const char *name, ooscript::Value value)
{
	ooscript::setProperty(sContext, sGlobal, name, &value);
}


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = ooscript::newRuntime(8u * 1024u * 1024u);
	sContext = ooscript::newContext(sRuntime, 8192);
	gOOJSMainThreadContext = sContext;
	ooscript::beginRequest(sContext);
	sGlobal = ooscript::getGlobalObject(sContext);
	ooscript::initStandardClasses(sContext, sGlobal);
	gOOEntityJSPrototype = ooscript::initClass(sContext, sGlobal, nullptr, &sFakeEntityClass, OOJSUnconstructableConstruct, 0, nullptr, nullptr, nullptr, nullptr);
	sShipPrototype = ooscript::initClass(sContext, sGlobal, gOOEntityJSPrototype, &sFakeShipClass, OOJSUnconstructableConstruct, 0, nullptr, nullptr, nullptr, nullptr);
	OOJSRegisterSubclass(&sFakeShipClass, &sFakeEntityClass);
	InitOOJSStation(sContext, sGlobal);

	sUniverse = new StandInUniverse();	// kept for the life of the test
	gSharedUniverse = sUniverse;
	sUniverse->_controller = new GameController();	// kept for the life of the test
	sUniverse->_commodities = oo::makeRef<OOCommodities>();
	sPlayer = new PlayerEntity;
	sPlayer->_name = "player";
	sPlayer->_screen = GUI_SCREEN_STATUS;
	gOOPlayer = sPlayer;
	sStationObject = NewShipObject("Coriolis", oo::makeRef<StationEntity>());	// kept for the life of the test; a station's object (the ship's facade from bead oo-9ht.175, the root's since bead oo-9ht.144)
	sStation = static_cast<StationEntity *>(sStationObject->_cxxEntity.get());
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
	ooscript::ClassDef *stationClass = nullptr;
	ooscript::Object prototype = nullptr;
	sStationObject->getJSClass(&stationClass, &prototype);
	OO_CHECK(stationClass != nullptr && std::strcmp(stationClass->name, "Station") == 0);
	OO_CHECK(prototype != nullptr);
	OO_CHECK(OOJSIsSubclass(stationClass, &sFakeShipClass));
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
	OO_CHECK(sStation->_abortedShip == sShipPart);
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
		OO_CHECK(ooscript::isObject(definition->callback()) && definition->callbackThis() == nullptr);
	}
	OO_CHECK_EVAL("station.setInterface('k2', {title: 'T', summary: 'S', callback: function () {}, cbThis: station})", "undefined");
	OO_CHECK(sStation->_interfaces.count("k2") == 1 && sStation->_interfaces["k2"]->category() == std::optional<std::string>("desc(interfaces-category-uncategorised)"));
	OO_CHECK(sStation->_interfaces.count("k2") == 1 && sStation->_interfaces["k2"]->callbackThis() == sStationObject->_jsSelf);
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
	OO_CHECK_EVAL("Station.prototype.launchMiner.call({})", "undefined");	// not a station: no-op
	OO_CHECK_EVAL("Station.prototype.roll", "threw: Native method expected Entity, got [object Object].");
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
	OO_CHECK(ooscript::isInRequest(sContext));
}


// The JS glue of OOEquipmentType (OOJSPrivateObject), defined in OOJSEquipmentInfo.mm, which
// this test does not link (bead oo-6symp.3): the vtable names these.
ooscript::Value OOEquipmentType::jsValueInContext(ooscript::Context)  { return ooscript::Value(); }
void OOEquipmentType::clearJSSelf(ooscript::Object)  {}
std::optional<std::string> OOEquipmentType::jsDescription()  { return std::nullopt; }


OO_TEST_MAIN()
