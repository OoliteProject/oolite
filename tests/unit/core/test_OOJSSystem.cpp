/*	test_OOJSSystem.mm
	Unit tests for the system JS binding (src/Core/Scripting/OOJSSystem.h/.mm): the test-first half
	of its slice beads (oo-luhd, slice 1 of docs/phases/3-slices/OOJSSystem.md, and the slices after
	it), converted the way bead oo-ppc converted OOJSVector (proposed ADR-0056, amendments oo-ppc and
	oo-9ht.139).

	The System object is made by the real engine, so the test links every game object but main's
	(tests/unit/core/meson.build entry ['*'], as test_OOJSScript does) and runs the binding in the
	engine's own context. The universe and the player are stand-ins of other names (FakeUniverse,
	FakePlayer, amendment oo-ppc item 6) put where UNIVERSE and PLAYER read them; they answer only
	the selectors the binding sends and record what they are told. The entities are real Entity
	objects (a subclass that is visible to scripts), so the engine's predicates, its entity
	wrappers and JSValueToEntity() run unchanged. The expectations were written against the
	Objective-C file and run on it first; they pin the JS-visible behaviour of the property getter
	and setter (in a system and in interstellar space), toString(), addPlanet()/addMoon(),
	sendAllShipsAway(), the counts and the entity searches (filtering, ordering by distance, the
	optional reference entity and range, and their errors) and locationFromCode().
	Run: bash tools/check-core-tests.sh test_OOJSSystem
*/

#include "OOJavaScriptEngine.h"
#include "OOJSSystem.h"
#include "Universe.h"
#include "PlayerEntity.h"
#include "OOSunEntity.h"
#include "StationEntity.h"
#include "OOJSPropID.h"
#include "OOJSPopulatorDefinition.h"
#include "OOShipGroup.h"
#include "OOObjCPList.h"
#include "oofnd/FileSystem.hpp"
#include "oofnd/String.hpp"
#include "oo_test.hpp"

#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <process.h>
#include <string>
#include <vector>


// What UNIVERSE and PLAYER read (Universe.mm, PlayerEntity.mm).
extern Universe *gSharedUniverse;
extern PlayerEntity *gOOPlayer;


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


// The ship's group, private again in C++ (bead oo-9ht.184.1), and nothing else.
struct ShipEntityTestAccess
{
	static oo::Ref<::OOShipGroup> &Group(::ShipEntity *s)	{ return s->_group; }
};


// MARK: The stand-ins -----------------------------------------------------------------------------

// An entity scripts can see; it answers like any Entity otherwise (an Objective-C subclass until bead
// oo-j12i2; a C++ one overriding the member its -isVisibleToScripts became; its -group, which nothing
// asked once the system asked the C++ ship for its group, went with it).
class TestEntity : public Entity
{
public:
	bool isVisibleToScripts() override  { return _visible; }

	bool _visible = false;
};


// The universe answers held C++ entities (bead oo-9ht.39.26): the stand-in's lists of objects, so held.
std::vector<oo::EntityHold> Held(const std::vector<oo::EntityHold> &objects)
{
	std::vector<oo::EntityHold> result;
	for (const auto &object : objects)  result.emplace_back(object.get());
	return result;
}


std::map<std::string, oo::EntityHold, std::less<>> Held(const std::map<std::string, oo::EntityHold, std::less<>> &objects)
{
	std::map<std::string, oo::EntityHold, std::less<>> result;
	for (const auto &[key, object] : objects)  result[key] = oo::EntityHold(object.get());
	return result;
}


// The entities a predicate matches, of the stand-in's list (the stand-in's -matching:parameter:).
std::vector<oo::EntityHold> MatchingEntities(const std::vector<oo::EntityHold> &entities, EntityFilterPredicate predicate, void *parameter)
{
	std::vector<oo::EntityHold> result;
	for (const auto &e : entities)
	{
		if (predicate(e.get(), parameter))  result.push_back(e);
	}
	return result;
}




class FakePlayer : public PlayerEntity	// C++ since bead oo-9ht.177 deleted the Objective-C player
{
public:
	OOGalaxyID _galaxy = {};
	OOSystemID _system = {};
	std::vector<std::string> _log;
	Entity *_planetToAdd = {};

	void setScriptTarget(::ShipEntity * /*ship*/) override	{  }
	OOGalaxyID currentGalaxyID() override	{ return _galaxy; }
	OOSystemID currentSystemID() override	{ return _system; }
	unsigned systemPseudoRandom100() override	{ return 42; }
	unsigned systemPseudoRandom256() override	{ return 200; }
	double systemPseudoRandomFloat() override	{ return 0.25; }
	void sendAllShipsAway() override	{ _log.push_back("sendAllShipsAway"); }
	void addShipsAt(const std::string & roles_number_system_x_y_z) override	{ _log.push_back("addShipsAt " + roles_number_system_x_y_z); }
	void addShipsAtPrecisely(const std::string & roles_number_system_x_y_z) override	{ _log.push_back("addShipsAtPrecisely " + roles_number_system_x_y_z); }
	void addShipsWithinRadius(const std::string & roles_number_system_x_y_z_r) override	{ _log.push_back("addShipsWithinRadius " + roles_number_system_x_y_z_r); }
	::OOPlanetEntity * addPlanetEntity(const std::string & planetKey) override
	{
		_log.push_back("addPlanet " + planetKey);
		return static_cast<OOPlanetEntity *>(_planetToAdd);	// the C++ planet since bead oo-9ht.129
	}
	::OOPlanetEntity * addMoonEntity(const std::string & moonKey) override
	{
		_log.push_back("addMoon " + moonKey);
		return static_cast<OOPlanetEntity *>(_planetToAdd);	// the C++ planet since bead oo-9ht.129
	}
};

// [[TestPlayer alloc] init] (bead oo-9ht.177): a C++ player under the ship's facade, as
// PlayerEntity::sharedPlayer() makes the game's, retained (+1) as +alloc's object was.
template <class T>
T *NewTestPlayer()
{
	oo::Ref<T> player = oo::makeRef<T>();
	{
		oo::RetainEntity(oo::MadeEntity(player));
	}
	return player.get();
}


namespace {

std::string PredicateName(EntityFilterPredicate predicate)
{
	if (predicate == JSEntityIsJavaScriptSearchablePredicate)  return "searchable";
	if (predicate == JSEntityIsDemoShipPredicate)  return "demo";
	return "other";
}


std::string Describe(Entity *entity)
{
	return entity == nil ? "nil" : oo::str::format("%g", entity->position.x);
}

}	// namespace




namespace {

namespace stdfs = std::filesystem;

stdfs::path sRoot;
class FakeUniverse : public Universe
{
public:
	BOOL _interstellar = {};
	Entity *_station, *_planet, *_sun;
	std::vector<oo::EntityHold> _planets, _stations, _wormholes, _entities;
	std::map<std::string, oo::EntityHold, std::less<>> _waypoints;	// the waypoints' objects (bead oo-9ht.108)
	float _ambient = {};
	int _lightings = {};
	BOOL _breakPattern = {};
	oo::PList _populatorSettings = {};
	oo::PList _systemData = {};
	oo::PList _descriptions = {};
	std::vector<std::string> _log = {};
	double _lastRange = {};
	Entity *_lastRelativeTo = {};
	std::string _lastShipsPredicate = {};
	std::vector<oo::EntityHold> _shipsToAdd = {};
	Entity *_effectToAdd = {};
	oo::PList _lastPopulator = {};

	bool inInterstellarSpace() override	{ return _interstellar; }
	::StationEntity *station() override	{ return static_cast<StationEntity *>(_station); }
	::OOPlanetEntity *planet() override	{ return static_cast<OOPlanetEntity *>(_planet); }
	::OOSunEntity *sun() override	{ return static_cast<OOSunEntity *>(_sun); }
	std::vector<oo::EntityHold> planets() override	{ return Held(_planets); }
	std::vector<oo::EntityHold> stations() override
	{
		std::vector<oo::EntityHold> result;
		for (const auto &e : _stations)  result.push_back(oo::EntityHold(e.get()));
		return Held(result);
	}
	std::vector<oo::EntityHold> wormholes() override	{ return Held(_wormholes); }
	std::map<std::string, oo::EntityHold, std::less<>> currentWaypoints() override	{ return Held(_waypoints); }
	std::vector<oo::EntityHold> findShipsMatchingPredicate(EntityFilterPredicate predicate, void *parameter, double range, Entity *entity) override	// the C++ entity since bead oo-9ht.39.26
	{
		_lastShipsPredicate = "ships:" + PredicateName(predicate);
		_lastRange = range;
		_lastRelativeTo = entity;
		return Held(MatchingEntities(this->_entities, predicate, parameter));
	}
	std::vector<oo::EntityHold> findVisualEffectsMatchingPredicate(EntityFilterPredicate predicate, void *parameter, double range, Entity *entity) override
	{
		_lastShipsPredicate = "effects:" + PredicateName(predicate);
		_lastRange = range;
		_lastRelativeTo = entity;
		return Held(MatchingEntities(this->_entities, predicate, parameter));
	}
	std::vector<oo::EntityHold> findEntitiesMatchingPredicate(EntityFilterPredicate predicate, void *parameter, double range, Entity *entity) override	// the reference's C++ entity since bead oo-9ht.39.8.23
	{
		_lastRange = range;
		_lastRelativeTo = entity;
		return Held(MatchingEntities(this->_entities, predicate, parameter));
	}
	float getAmbientLightLevel() override	{ return _ambient; }
	void setAmbientLightLevel(float newValue) override	{ _ambient = newValue; }
	void setLighting() override	{ _lightings++; }
	bool witchspaceBreakPattern() override	{ return _breakPattern; }
	void setWitchspaceBreakPattern(bool newValue) override	{ _breakPattern = newValue; }
	oo::PList getPopulatorSettings() override	{ return _populatorSettings; }
	oo::PList currentSystemData() override	{ return _systemData; }
	const oo::PList *descriptions() override	{ return &_descriptions; }
	std::optional<std::string> descriptionForKey(const std::string &key) override
	{
		if (const oo::PList *entry = _descriptions.find(key))
		{
			if (const std::string *string = entry->getIf<std::string>())  return *string;
		}
		return std::nullopt;
	}
	void setSystemDataForGalaxy(OOGalaxyID gnum, OOSystemID pnum, const std::string &key, const oo::PList &value, const std::optional<std::string> &manifest, OOSystemLayer layer) override	{ _log.push_back(oo::str::format("set %d:%d %s=%s manifest=%s layer=%d", gnum, pnum, key.c_str(), oo::DescriptionOf(value).c_str(), manifest.value_or("none").c_str(), static_cast<int>(layer))); }
	unsigned countShipsWithPrimaryRole(const std::string &role, double range, Entity *entity) override
	{
		_log.push_back(oo::str::format("countPrimary %s %g %s", role.c_str(), range, Describe(entity).c_str()));
		return 3;
	}
	unsigned countShipsWithRole(const std::string &role, double range, Entity *entity) override
	{
		_log.push_back(oo::str::format("countRole %s %g %s", role.c_str(), range, Describe(entity).c_str()));
		return 4;
	}
	unsigned countShipsWithScanClass(OOScanClass scanClass, double range, Entity *entity) override
	{
		_log.push_back(oo::str::format("countScanClass %d %g %s", static_cast<int>(scanClass), range, Describe(entity).c_str()));
		return 5;
	}
	HPVector locationByCode(const std::string &code, ::OOSunEntity *sun, ::OOPlanetEntity *planet) override
	{
		_log.push_back(oo::str::format("location %s %s %s", code.c_str(), Describe(sun).c_str(), Describe(planet).c_str()));
		return make_HPvector(1, 2, 3);
	}
	void witchspaceShipWithPrimaryRole(const std::string &role) override	{ _log.push_back("witchspaceShip " + role); }
	void addShipWithRole(const std::string &desc, double route_fraction) override	{ _log.push_back(oo::str::format("routeOneShip %s %g", desc.c_str(), route_fraction)); }
	bool spawnShip(const std::string &shipdesc) override
	{
		_log.push_back("spawnShip " + shipdesc);
		return YES;
	}
	std::optional<std::string> getSystemName(OOSystemID sys, OOGalaxyID /*gnum*/) override
	{
		_log.push_back(oo::str::format("systemName %d", sys));
		if (sys == 99)  return std::nullopt;
		return oo::str::format("System%d", sys);
	}
	OOSystemID findSystemFromName(const std::string &sysName) override
	{
		_log.push_back("findSystem " + sysName);
		return sysName == "Lave" ? 7 : -1;
	}
	Entity *addVisualEffectAt(HPVector pos, const std::string &key) override	// the C++ effect since bead oo-9ht.39.26
	{
		_log.push_back(oo::str::format("addVisualEffect %s %g %g %g", key.c_str(), pos.x, pos.y, pos.z));
		return _effectToAdd;	// the effect (the stand-in answered its object as the effect)
	}
	void setPopulatorSetting(const std::string &key, const oo::PList &setting) override
	{
		_log.push_back("setPopulator " + key + (setting.isNull() ? " null" : ""));
		_lastPopulator = setting;
	}
	void defineWaypoint(const oo::PList &definition, const std::string &key) override	{ _log.push_back("defineWaypoint " + key + " " + (definition.isNull() ? std::string("null") : oo::DescriptionOf(definition))); }
	HPVector getWitchspaceExitPosition() override	{ return make_HPvector(7, 8, 9); }
	std::vector<oo::EntityHold> addShipsAt(HPVector pos, const std::string &role, unsigned count, GLfloat radius, bool isGroup) override	// held C++ entities since bead oo-9ht.39.26
	{
		_log.push_back(oo::str::format("addShipsAt %g %g %g %s %u %g %d", pos.x, pos.y, pos.z, role.c_str(), count, radius, isGroup ? 1 : 0));
		return Held(_shipsToAdd);
	}
	std::vector<oo::EntityHold> addShipsToRoute(const std::string &route, const std::string &role, unsigned count, double routeFraction, bool isGroup) override
	{
		_log.push_back(oo::str::format("addShipsToRoute %s %s %u %g %d", route.c_str(), role.c_str(), count, routeFraction, isGroup ? 1 : 0));
		return Held(_shipsToAdd);
	}
};


FakeUniverse *sUniverse = nil;
FakePlayer *sPlayer = nullptr;


// Its object (the test keeps entities as their objects), +1 as +alloc's was.
Entity *MakeEntity(double x, BOOL visible)
{
	oo::Ref<TestEntity> part = oo::makeRef<TestEntity>();
	Entity *entity = nil;
	{
		entity = oo::RetainEntity(oo::MadeEntity(part));	// kept for the life of the test
	}
	entity->setPosition(make_HPvector(x, 0, 0));
	part->_visible = visible;
	return entity;
}


// A ship the fake universe adds (bead oo-9ht.144): the system asks the C++ ship for its group, so
// the stand-in that answered -group is a C++ ship under its object (oo::NewEntityFacade, retained
// and never released, as MakeEntity's), placed as the stand-in was and never set up.
::ShipEntity *MakeShip(double x)
{
	oo::Ref<::ShipEntity> ship = oo::makeRef<::ShipEntity>();
	{
		oo::RetainEntity(oo::MadeEntity(ship));
	}
	ship->setPosition(make_HPvector(x, 0, 0));
	return ship.get();
}


oo::PList Dict(std::initializer_list<std::pair<const char *, oo::PList>> entries)
{
	oo::PList::Dict dict;
	for (const auto &[key, value] : entries)  dict[key] = value;
	return oo::PList(std::move(dict));
}


// The scratch home and game folder, the engine, and the stand-ins; made once.
void SetUp()
{
	if (!sRoot.empty())  return;
	sRoot = stdfs::temp_directory_path() / ("oo-test-jssystem-" + std::to_string(static_cast<unsigned long>(::_getpid())));
	stdfs::remove_all(sRoot);
	stdfs::create_directories(sRoot / "Resources");
	OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
	stdfs::current_path(sRoot);
	const std::string info = "{ CFBundleVersion = \"9.9.9-test\"; }";
	OO_CHECK(oo::fs::writeFile(sRoot / "Resources" / "Info-gnustep.plist", oo::Data(info.data(), info.size()), oo::fs::WriteMode::direct).has_value());
	{	// was an Objective-C pool (bead oo-dbz.1: no Objective-C object since oo-4aq6a.8): the engine autoreleases facades as it starts (as Eval(), bead oo-9ht.172)
		(void)OOJavaScriptEngine::sharedEngine();
	}

	sUniverse = new FakeUniverse();
	gSharedUniverse = sUniverse;
	sPlayer = NewTestPlayer<FakePlayer>();
	gOOPlayer = sPlayer;

	sPlayer->_galaxy = 3;
	sPlayer->_system = 17;

	sUniverse->_station = MakeEntity(10, YES);
	sUniverse->_planet = MakeEntity(20, YES);
	sUniverse->_sun = MakeEntity(30, YES);
	sUniverse->_planets = { oo::EntityHold(sUniverse->_planet), oo::EntityHold(MakeEntity(21, NO)), oo::EntityHold(MakeEntity(22, YES)) };
	sUniverse->_stations = { oo::EntityHold(sUniverse->_station), oo::EntityHold(MakeEntity(1000, YES)) };
	sUniverse->_wormholes = { oo::EntityHold(MakeEntity(40, YES)) };
	sUniverse->_waypoints["nav-a"] = oo::EntityHold(MakeEntity(50, YES));
	sUniverse->_waypoints["nav-b"] = oo::EntityHold(MakeEntity(51, YES));

	// The searchable entities, out of distance order; one is invisible.
	Entity *farthest = MakeEntity(300, YES);
	farthest->setScanClass(CLASS_BUOY);
	Entity *nearest = MakeEntity(100, YES);
	nearest->setScanClass(CLASS_NEUTRAL);
	Entity *hidden = MakeEntity(150, NO);
	hidden->setScanClass(CLASS_NEUTRAL);
	Entity *middle = MakeEntity(200, YES);
	middle->setScanClass(CLASS_NEUTRAL);
	sUniverse->_entities = { oo::EntityHold(farthest), oo::EntityHold(nearest), oo::EntityHold(hidden), oo::EntityHold(middle) };

	sUniverse->_ambient = 0.5f;
	sUniverse->_populatorSettings = Dict({ { "pirates", Dict({ { "priority", oo::PList(10) } }) } });
	sUniverse->_systemData = Dict({
		{ "name", oo::PList(std::string("Lave")) },
		{ "description", oo::PList(std::string("A dull world.")) },
		{ "inhabitants", oo::PList(std::string("Humans")) },
		{ "government", oo::PList(4) },
		{ "economy", oo::PList(5) },
		{ "techlevel", oo::PList(7) },
		{ "population", oo::PList(25) },
		{ "productivity", oo::PList(7000) },
	});
	oo::PList::Array governments, economies;
	for (const char *name : { "Anarchy", "Feudal", "Multi-Government", "Dictatorship", "Communist", "Confederacy", "Democracy", "Corporate State" })  governments.push_back(oo::PList(std::string(name)));
	for (const char *name : { "Rich Industrial", "Average Industrial", "Poor Industrial", "Mainly Industrial", "Mainly Agricultural", "Rich Agricultural", "Average Agricultural", "Poor Agricultural" })  economies.push_back(oo::PList(std::string(name)));
	sUniverse->_descriptions = Dict({
		{ "government", oo::PList(std::move(governments)) },
		{ "economy", oo::PList(std::move(economies)) },
		{ "interstellar-space", oo::PList(std::string("Interstellar space")) },
		{ "not-applicable", oo::PList(std::string("N/A")) },
	});
}


// Evaluates src in the engine's context and gives its result as a string ("undefined", "null",
// ...), or "threw: <message>".
// In its own autorelease pool, as the game's frame is (bead oo-9ht.172): an object the engine or
// the binding autoreleases is freed here, while the engine is alive. With no pool it went to the
// main thread's implicit pool, which libobjc drains at thread detach, after the C++ static
// destructors: an OOJSValue freed there (the special-functions facade the engine makes as it
// starts, in SetUp()) looked its context up in the destroyed ooscript context table
// (heap-use-after-free; the test crashed at exit about 1 run in 6).
std::string Eval(const std::string &src)
{
	SetUp();
	std::string text;
	{
		ooscript::Context context = OOJSAcquireContext();
		ooscript::Object global = OOJavaScriptEngine::sharedEngine()->globalObject();
		std::string wrapped = "(function () { try { return String(" + src + "); } catch (e) { return 'threw: ' + (e && e.message !== undefined ? e.message : e); } })()";
		ooscript::Value result = ooscript::undefinedValue();
		if (!ooscript::evaluateScript(context, global, wrapped.c_str(), static_cast<unsigned>(wrapped.size()), "test.js", 1, &result))
		{
			ooscript::clearPendingException(context);
			text = "<evaluation failed>";
		}
		else
		{
			text = cxx_OOStringFromJSValue(context, result).value_or("<not a string>");
		}
		OOJSRelinquishContext(context);
	}
	return text;
}


std::string EvalShown(const std::string &src, const std::string &expected)
{
	std::string result = Eval(src);
	if (result != expected)  std::printf("    %s\n    gave: %s\n", src.c_str(), result.c_str());
	return result;
}
#define OO_CHECK_EVAL(src, expected)  OO_CHECK_EQ(EvalShown(src, expected), expected)


std::string Log(std::vector<std::string> &log)
{
	std::string result;
	for (const std::string &line : log)  result += (result.empty() ? "" : "; ") + line;
	log.clear();
	return result;
}


// Log(), and print what came back when it is not what the check expects.
std::string LogShown(std::vector<std::string> &log, const std::string &expected)
{
	std::string result = Log(log);
	if (result != expected)  std::printf("    log gave: %s\n", result.c_str());
	return result;
}
#define OO_CHECK_LOG(log, expected)  OO_CHECK_EQ(LogShown(log, expected), expected)

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

OO_TEST(registration)
{
	SetUp();
	OO_CHECK_EVAL("typeof system", "object");
	OO_CHECK_EVAL("system", "[System 3:17 \"Lave\"]");
	OO_CHECK_EVAL("(function () { system = 5; return typeof system; })()", "object");	// read-only
	// The properties are enumerable, the methods are not.
	OO_CHECK_EVAL("Object.keys(Object.getPrototypeOf(system)).sort().join()",
				  "ID,allDemoShips,allShips,allVisualEffects,ambientLevel,breakPattern,description,economy,economyDescription,government,governmentDescription,info,inhabitantsDescription,isInterstellarSpace,mainPlanet,mainStation,name,planets,population,populatorSettings,productivity,pseudoRandom100,pseudoRandom256,pseudoRandomNumber,stations,sun,techLevel,waypoints,wormholes");
	OO_CHECK_EVAL("['addGroup', 'addGroupToRoute', 'addMoon', 'addPlanet', 'addShips', 'addShipsToRoute', 'addVisualEffect', 'countEntitiesWithScanClass', 'countShipsWithPrimaryRole', 'countShipsWithRole', 'entitiesWithScanClass', 'filteredEntities', 'legacy_addShips', 'legacy_addShipsAt', 'legacy_addShipsAtPrecisely', 'legacy_addShipsWithinRadius', 'legacy_addSystemShips', 'legacy_spawnShip', 'locationFromCode', 'sendAllShipsAway', 'setPopulator', 'setWaypoint', 'shipsWithPrimaryRole', 'shipsWithRole', 'toString'].every(function (m) { return typeof system[m] === 'function'; })", "true");
	OO_CHECK_EVAL("['infoForSystem', 'systemIDForName', 'systemNameForID'].every(function (m) { return typeof System[m] === 'function'; })", "true");
}


OO_TEST(propertiesWithoutSystemData)
{
	SetUp();
	OO_CHECK_EVAL("system.ID", "17");
	OO_CHECK_EVAL("system.isInterstellarSpace", "false");
	OO_CHECK_EVAL("system.mainStation.position.x", "10");
	OO_CHECK_EVAL("system.mainPlanet.position.x", "20");
	OO_CHECK_EVAL("system.sun.position.x", "30");
	OO_CHECK_EVAL("system.planets.map(function (p) { return p.position.x; }).join()", "20,22");	// the invisible one left out
	OO_CHECK_EVAL("system.stations.map(function (p) { return p.position.x; }).join()", "10,1000");
	OO_CHECK_EVAL("system.wormholes.map(function (p) { return p.position.x; }).join()", "40");
	OO_CHECK_EVAL("Object.keys(system.waypoints).sort().join()", "nav-a,nav-b");
	OO_CHECK_EVAL("system.waypoints['nav-b'].position.x", "51");
	OO_CHECK_EVAL("system.allShips.map(function (p) { return p.position.x; }).join()", "300,100,200");
	OO_CHECK_EQ(sUniverse->_lastShipsPredicate, "ships:searchable");
	OO_CHECK(sUniverse->_lastRange == -1 && sUniverse->_lastRelativeTo == nil);
	OO_CHECK_EVAL("system.allDemoShips.length", "0");
	OO_CHECK_EQ(sUniverse->_lastShipsPredicate, "ships:demo");
	OO_CHECK_EVAL("system.allVisualEffects.length", "3");
	OO_CHECK_EQ(sUniverse->_lastShipsPredicate, "effects:searchable");
	OO_CHECK_EVAL("system.ambientLevel", "0.5");
	OO_CHECK_EVAL("system.pseudoRandomNumber", "0.25");
	OO_CHECK_EVAL("system.pseudoRandom100", "42");
	OO_CHECK_EVAL("system.pseudoRandom256", "200");
	OO_CHECK_EVAL("system.breakPattern", "false");
	OO_CHECK_EVAL("system.populatorSettings.pirates.priority", "10");

	// No station, planet or sun: null.
	Entity *station = sUniverse->_station;
	sUniverse->_station = nil;
	OO_CHECK_EVAL("system.mainStation", "null");
	sUniverse->_station = station;
}


OO_TEST(propertiesFromSystemData)
{
	SetUp();
	OO_CHECK_EVAL("system.name", "Lave");
	OO_CHECK_EVAL("system.description", "A dull world.");
	OO_CHECK_EVAL("system.inhabitantsDescription", "Humans");
	OO_CHECK_EVAL("system.government", "4");
	OO_CHECK_EVAL("system.governmentDescription", "Communist");
	OO_CHECK_EVAL("system.economy", "5");
	OO_CHECK_EVAL("system.economyDescription", "Rich Agricultural");
	OO_CHECK_EVAL("system.techLevel", "7");
	OO_CHECK_EVAL("system.population", "25");
	OO_CHECK_EVAL("system.productivity", "7000");

	// A key the system data lacks reads null, and a number it lacks reads 0.
	oo::PList data = sUniverse->_systemData;
	sUniverse->_systemData = Dict({ { "name", oo::PList(std::string("Diso")) } });
	OO_CHECK_EVAL("system.description", "null");
	OO_CHECK_EVAL("system.government", "0");
	OO_CHECK_EVAL("system", "[System 3:17 \"Diso\"]");
	sUniverse->_systemData = Dict({});
	OO_CHECK_EVAL("system", "[System 3:17 \"(null)\"]");
	sUniverse->_systemData = data;
}


OO_TEST(propertiesInInterstellarSpace)
{
	SetUp();
	sUniverse->_interstellar = YES;
	OO_CHECK_EVAL("system.isInterstellarSpace", "true");
	OO_CHECK_EVAL("system.name", "Interstellar space");
	OO_CHECK_EVAL("JSON.stringify(system.description)", "\"\"");
	OO_CHECK_EVAL("system.inhabitantsDescription", "N/A");
	OO_CHECK_EVAL("system.government", "-1");
	OO_CHECK_EVAL("system.governmentDescription", "N/A");
	OO_CHECK_EVAL("system.economy", "-1");
	OO_CHECK_EVAL("system.economyDescription", "N/A");
	OO_CHECK_EVAL("system.techLevel", "-1");
	OO_CHECK_EVAL("system.population", "0");
	OO_CHECK_EVAL("system.productivity", "0");
	OO_CHECK_EVAL("system.ID", "17");	// still the player's
	sUniverse->_interstellar = NO;
}


OO_TEST(setters)
{
	SetUp();
	OO_CHECK_EVAL("(function () { system.ambientLevel = 0.75; return system.ambientLevel; })()", "0.75");
	OO_CHECK_EQ(sUniverse->_lightings, 1);
	OO_CHECK_EVAL("(function () { system.breakPattern = true; return system.breakPattern; })()", "true");
	OO_CHECK(sUniverse->_breakPattern);
	sUniverse->_breakPattern = NO;
	sUniverse->_ambient = 0.5f;

	Log(sUniverse->_log);
	OO_CHECK_EVAL("(function () { system.name = 'Zaonce'; system.description = 'Dry.'; system.inhabitantsDescription = 'Lizards'; })()", "undefined");
	OO_CHECK_LOG(sUniverse->_log, "set 3:17 name=Zaonce manifest=none layer=2; set 3:17 description=Dry. manifest=none layer=2; set 3:17 inhabitants=Lizards manifest=none layer=2");
	OO_CHECK_EVAL("(function () { system.government = 9; system.economy = -2; system.techLevel = 20; system.population = 66; system.productivity = 1234; })()", "undefined");
	OO_CHECK_LOG(sUniverse->_log, "set 3:17 government=7 manifest=none layer=2; set 3:17 economy=0 manifest=none layer=2; set 3:17 techlevel=15 manifest=none layer=2; set 3:17 population=66 manifest=none layer=2; set 3:17 productivity=1234 manifest=none layer=2");

	// Read-only properties, and anything but the light and the break pattern in interstellar space.
	OO_CHECK_EVAL("(function () { system.ID = 4; return system.ID; })()", "17");
	sPlayer->_system = -1;
	OO_CHECK_EVAL("(function () { system.name = 'Nowhere'; })()", "undefined");
	OO_CHECK_LOG(sUniverse->_log, "");
	sPlayer->_system = 17;
}


OO_TEST(methods)
{
	SetUp();
	OO_CHECK_EVAL("system.toString()", "[System 3:17 \"Lave\"]");

	sPlayer->_planetToAdd = nil;
	OO_CHECK_EVAL("system.addPlanet('rock')", "null");
	sPlayer->_planetToAdd = sUniverse->_planet;
	OO_CHECK_EVAL("system.addMoon('pebble').position.x", "20");
	OO_CHECK_LOG(sPlayer->_log, "addPlanet rock; addMoon pebble");
	OO_CHECK(Eval("system.addPlanet()").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("system.addMoon()").rfind("threw: ", 0) == 0);
	OO_CHECK_LOG(sPlayer->_log, "");

	OO_CHECK_EVAL("system.sendAllShipsAway()", "undefined");
	OO_CHECK_LOG(sPlayer->_log, "sendAllShipsAway");

	OO_CHECK_EVAL("system.locationFromCode('OUTSIDE_SUN')", "(1, 2, 3)");
	OO_CHECK_LOG(sUniverse->_log, "location OUTSIDE_SUN 30 20");
	Entity *sun = sUniverse->_sun;
	sUniverse->_sun = nil;
	OO_CHECK_EVAL("system.locationFromCode('OUTSIDE_SUN')", "(1, 2, 3)");
	OO_CHECK_LOG(sUniverse->_log, "location WITCHPOINT nil nil");
	sUniverse->_sun = sun;
	OO_CHECK(Eval("system.locationFromCode()").rfind("threw: ", 0) == 0);
}


OO_TEST(counts)
{
	SetUp();
	Log(sUniverse->_log);
	OO_CHECK_EVAL("system.countShipsWithPrimaryRole('trader')", "3");
	OO_CHECK_EVAL("system.countShipsWithRole('pirate', system.mainStation, 1000)", "4");
	OO_CHECK_EVAL("system.countEntitiesWithScanClass('CLASS_BUOY', system.sun)", "5");
	OO_CHECK_LOG(sUniverse->_log, oo::str::format("countPrimary trader -1 nil; countRole pirate 1000 10; countScanClass %d -1 30", static_cast<int>(CLASS_BUOY)));

	// Bad arguments: none, a bad reference entity, a bad range, an unknown scan class.
	OO_CHECK(Eval("system.countShipsWithPrimaryRole()").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("system.countShipsWithRole('x', 5)").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("system.countShipsWithRole('x', null)").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("system.countEntitiesWithScanClass('CLASS_NOT_A_CLASS')").rfind("threw: ", 0) == 0);
	OO_CHECK_LOG(sUniverse->_log, "");
	// A range that is not a number converts to NaN, and is used.
	OO_CHECK_EVAL("system.countShipsWithRole('x', system.sun, 'far')", "4");
	OO_CHECK_LOG(sUniverse->_log, "countRole x nan 30");
}


OO_TEST(searches)
{
	SetUp();
	// In the universe's order without a reference entity, by distance from one with it.
	OO_CHECK_EVAL("system.entitiesWithScanClass('CLASS_NEUTRAL').map(function (p) { return p.position.x; }).join()", "100,200");
	OO_CHECK_EVAL("system.filteredEntities(this, function (e) { return true; }).map(function (p) { return p.position.x; }).join()", "300,100,200");
	OO_CHECK(sUniverse->_lastRange == -1 && sUniverse->_lastRelativeTo == nil);
	OO_CHECK_EVAL("system.filteredEntities(this, function (e) { return true; }, system.sun, 500).map(function (p) { return p.position.x; }).join()", "100,200,300");
	OO_CHECK(sUniverse->_lastRange == 500 && sUniverse->_lastRelativeTo == sUniverse->_sun);
	OO_CHECK_EVAL("system.filteredEntities(this, function (e) { return e.position.x > 150; }, system.mainStation).map(function (p) { return p.position.x; }).join()", "200,300");
	OO_CHECK_EVAL("system.entitiesWithScanClass('CLASS_NEUTRAL', system.stations[1]).map(function (p) { return p.position.x; }).join()", "200,100");
	OO_CHECK_EVAL("system.filteredEntities(this, function (e) { return true; }, system.stations[1]).map(function (p) { return p.position.x; }).join()", "300,200,100");

	// No ships among them.
	OO_CHECK_EVAL("system.shipsWithRole('trader').length", "0");
	OO_CHECK_EVAL("system.shipsWithPrimaryRole('trader', system.sun).length", "0");

	// The predicate's exception ends the search with it.
	OO_CHECK_EVAL("system.filteredEntities(this, function (e) { throw new Error('nope'); })", "threw: nope");
	OO_CHECK(Eval("system.filteredEntities(this)").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("system.entitiesWithScanClass()").rfind("threw: ", 0) == 0);
}


// Slice 2 (bead oo-yqoa): the legacy spawners, the static lookups, effects, populators, waypoints
// and the ship creators.
OO_TEST(legacySpawners)
{
	SetUp();
	Log(sUniverse->_log);
	Log(sPlayer->_log);
	OO_CHECK_EVAL("system.legacy_addShips('trader', 2)", "undefined");
	OO_CHECK_EVAL("system.legacy_addSystemShips('pirate', 1, 0.5)", "undefined");
	OO_CHECK_EVAL("system.legacy_spawnShip('cobra3')", "undefined");
	OO_CHECK_LOG(sUniverse->_log, "witchspaceShip trader; witchspaceShip trader; routeOneShip pirate 0.5; spawnShip cobra3");
	OO_CHECK_EVAL("system.legacy_addShipsAt('trader', 2, 'pwm', [1, 2, 3])", "undefined");
	OO_CHECK_EVAL("system.legacy_addShipsAtPrecisely('trader', 3, 'wpu', [4, 5, 6])", "undefined");
	OO_CHECK_EVAL("system.legacy_addShipsWithinRadius('police', 1, 'spm', [7, 8, 9], 1000)", "undefined");
	OO_CHECK_LOG(sPlayer->_log, "addShipsAt trader 2 pwm 1.000000 2.000000 3.000000; addShipsAtPrecisely trader 3 wpu 4.000000 5.000000 6.000000; addShipsWithinRadius police 1 spm 7.000000 8.000000 9.000000 1000.000000");

	OO_CHECK(Eval("system.legacy_addShips('trader', 65)").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("system.legacy_addShips('trader')").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("system.legacy_addSystemShips('pirate', 1)").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("system.legacy_addShipsAt('trader', 2, 'pwm')").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("system.legacy_addShipsAtPrecisely('trader', 0, 'pwm', 1, 2, 3)").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("system.legacy_addShipsWithinRadius('police', 1, 'spm', [7, 8, 9])").rfind("threw: ", 0) == 0);
	// The coordinates are one vector argument: three numbers are not accepted.
	OO_CHECK_EVAL("system.legacy_addShipsAt('trader', 2, 'pwm', 1, 2, 3)", "threw: System.legacy_addShipsAt: Invalid arguments (\"trader\", 2, \"pwm\", 1, 2, 3) -- expected role, positive count no greater than 64, coordinate scheme and coordinates.");
	OO_CHECK(Eval("system.legacy_spawnShip()").rfind("threw: ", 0) == 0);
	OO_CHECK_LOG(sUniverse->_log, "");
	OO_CHECK_LOG(sPlayer->_log, "");
}


OO_TEST(staticLookups)
{
	SetUp();
	Log(sUniverse->_log);
	OO_CHECK_EVAL("System.systemNameForID(5)", "System5");
	OO_CHECK_EVAL("System.systemNameForID(99)", "null");
	OO_CHECK_EVAL("System.systemNameForID(-1)", "Interstellar space");
	OO_CHECK_EVAL("System.systemIDForName('Lave')", "7");
	OO_CHECK_EVAL("System.systemIDForName('Nowhere')", "-1");
	OO_CHECK_LOG(sUniverse->_log, "systemName 5; systemName 99; findSystem Lave; findSystem Nowhere");
	OO_CHECK(Eval("System.systemNameForID(-2)").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("System.systemNameForID(256)").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("System.systemIDForName()").rfind("threw: ", 0) == 0);
	OO_CHECK_LOG(sUniverse->_log, "");
}


OO_TEST(visualEffects)
{
	SetUp();
	Log(sUniverse->_log);
	sUniverse->_effectToAdd = nil;
	OO_CHECK_EVAL("system.addVisualEffect('fx', [1, 2, 3])", "null");
	sUniverse->_effectToAdd = sUniverse->_sun;
	OO_CHECK_EVAL("system.addVisualEffect('fx', new Vector3D(4, 5, 6)).position.x", "30");
	OO_CHECK_LOG(sUniverse->_log, "addVisualEffect fx 1 2 3; addVisualEffect fx 4 5 6");
	OO_CHECK_EVAL("system.addVisualEffect('fx', 4, 5, 6)", "threw: System.addVisualEffect: Invalid arguments (4) -- expected vector.");
	OO_CHECK(Eval("system.addVisualEffect()").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("system.addVisualEffect('fx', 'here')").rfind("threw: ", 0) == 0);
	OO_CHECK_LOG(sUniverse->_log, "");
}


OO_TEST(populators)
{
	SetUp();
	Log(sUniverse->_log);
	OO_CHECK_EVAL("system.setPopulator('mine')", "undefined");
	OO_CHECK_EVAL("system.setPopulator('mine', null)", "undefined");
	OO_CHECK_LOG(sUniverse->_log, "setPopulator mine null; setPopulator mine null");

	OO_CHECK_EVAL("system.setPopulator('mine', { callback: function (pos) { }, priority: 50, coordinates: [1, 2, 3] })", "undefined");
	OO_CHECK_LOG(sUniverse->_log, "setPopulator mine");
	const oo::PList settings = sUniverse->_lastPopulator;
	OO_CHECK(settings.isDict());
	const oo::PList *priority = settings.find("priority");
	OO_CHECK(priority != nullptr && priority->doubleValue() == 50.0);
	const oo::PList *coordinates = settings.find("coordinates");
	OO_CHECK(coordinates != nullptr && coordinates->isArray() && coordinates->count() == 3 && coordinates->at(2)->doubleValue() == 3.0);
	const oo::PList *callbackObj = settings.find("callbackObj");
	OOJSPopulatorDefinition *definition = callbackObj != nullptr ? OOJSPopulatorDefinitionIn(*callbackObj) : nullptr;
	OO_CHECK(definition != nullptr);
	if (definition != nullptr)
	{
		{	// was an Objective-C pool (bead oo-dbz.1: no Objective-C object since oo-4aq6a.8): as Eval() (bead oo-9ht.172)
			ooscript::Context context = OOJSAcquireContext();
			OO_CHECK(OOJSValueIsFunction(context, definition->callback()));
			OOJSRelinquishContext(context);
		}
	}

	// No coordinates: none set.
	OO_CHECK_EVAL("system.setPopulator('other', { callback: function (pos) { } })", "undefined");
	OO_CHECK(sUniverse->_lastPopulator.find("coordinates") == nullptr && sUniverse->_lastPopulator.find("callbackObj") != nullptr);
	Log(sUniverse->_log);

	OO_CHECK(Eval("system.setPopulator()").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("system.setPopulator(null, {})").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("system.setPopulator('mine', { priority: 5 })").rfind("threw: ", 0) == 0);	// no callback
	OO_CHECK_LOG(sUniverse->_log, "");
}


OO_TEST(waypoints)
{
	SetUp();
	Log(sUniverse->_log);
	OO_CHECK_EVAL("system.setWaypoint('nav')", "undefined");
	OO_CHECK_EVAL("system.setWaypoint('nav', [0, 0, 0], [1, 0, 0, 0], null)", "undefined");
	OO_CHECK_LOG(sUniverse->_log, "defineWaypoint nav null; defineWaypoint nav null");
	OO_CHECK_EVAL("system.setWaypoint('nav', [1, 2, 3], [1, 0, 0, 0], { size: 5 })", "undefined");
	const std::string defined = Log(sUniverse->_log);
	OO_CHECK(defined.rfind("defineWaypoint nav ", 0) == 0);
	OO_CHECK(defined.find("size") != std::string::npos && defined.find("position") != std::string::npos && defined.find("orientation") != std::string::npos);
	OO_CHECK(Eval("system.setWaypoint()").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("system.setWaypoint('nav', 'here', [1, 0, 0, 0], {})").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("system.setWaypoint('nav', [1, 2, 3], 'up', {})").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("system.setWaypoint('nav', [1, 2, 3], [1, 0, 0, 0], 5)").rfind("threw: ", 0) == 0);
	OO_CHECK_LOG(sUniverse->_log, "");
}


OO_TEST(shipCreators)
{
	SetUp();
	Log(sUniverse->_log);
	::ShipEntity *first = MakeShip(60);
	::ShipEntity *second = MakeShip(61);
	ShipEntityTestAccess::Group(first) = OOShipGroup::groupWithName(std::string("convoy"));
	sUniverse->_shipsToAdd = { oo::EntityHold(first), oo::EntityHold(second) };

	OO_CHECK_EVAL("system.addShips('trader', 2).map(function (s) { return s.position.x; }).join()", "60,61");
	OO_CHECK_EVAL("system.addShips('trader', 1, [1, 2, 3], 500).length", "2");
	OO_CHECK_EVAL("system.addGroup('trader', 2).name", "convoy");
	OO_CHECK_EVAL("system.addShipsToRoute('trader', 2).length", "2");
	OO_CHECK_EVAL("system.addGroupToRoute('trader', 2, 0.5, 'WP').name", "convoy");
	OO_CHECK_LOG(sUniverse->_log, oo::str::format("addShipsAt 7 8 9 trader 2 %g 0; addShipsAt 1 2 3 trader 1 500 0; addShipsAt 7 8 9 trader 2 %g 1; addShipsToRoute st trader 2 %g 0; addShipsToRoute wp trader 2 0.5 1",
													  static_cast<double>(static_cast<GLfloat>(SCANNER_MAX_RANGE)), static_cast<double>(static_cast<GLfloat>(SCANNER_MAX_RANGE)), static_cast<double>(NSNotFound)));

	// None added: null, for ships and for a group.
	sUniverse->_shipsToAdd.clear();
	OO_CHECK_EVAL("system.addShips('trader', 2)", "null");
	OO_CHECK_EVAL("system.addGroup('trader', 2)", "null");
	OO_CHECK_EVAL("system.addGroupToRoute('trader', 2)", "null");
	Log(sUniverse->_log);

	OO_CHECK(Eval("system.addShips()").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("system.addShips('trader', 0)").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("system.addShips('trader', 2, 'here')").rfind("threw: ", 0) == 0);
	sUniverse->_shipsToAdd = { oo::EntityHold(first) };
	OO_CHECK_EVAL("system.addShips('trader', 2, [1, 2, 3], 'far').length", "1");	// a radius that is not a number is NaN
	OO_CHECK_LOG(sUniverse->_log, "addShipsAt 1 2 3 trader 2 nan 0");
	sUniverse->_shipsToAdd.clear();
	OO_CHECK(Eval("system.addShipsToRoute('trader', 2, 1.5)").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("system.addShipsToRoute('trader', 2, 0.5, 'xy')").rfind("threw: ", 0) == 0);
	OO_CHECK_LOG(sUniverse->_log, "");
}


OO_TEST(cleanUp)
{
	stdfs::current_path(stdfs::temp_directory_path());
	std::error_code ignored;
	stdfs::remove_all(sRoot, ignored);
	OO_CHECK(true);
}


OO_TEST_MAIN()
