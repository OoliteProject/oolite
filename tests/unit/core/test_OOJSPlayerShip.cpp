/*	test_OOJSPlayerShip.mm
	Unit tests for the player ship JS binding (src/Core/Scripting/OOJSPlayerShip.h/.mm): the
	test-first half of its slice beads (oo-ft5n, slice 1 of docs/phases/3-slices/OOJSPlayerShip.md,
	and the slices after it), converted the way bead oo-ppc converted OOJSVector (proposed ADR-0056,
	amendments oo-ppc, oo-ykoy and oo-9ht.139).

	The PlayerShip object is made by the real engine (player.ship, with the real player in its
	private slot), so the test links every game object but main's (tests/unit/core/meson.build entry
	['*'], as test_OOJSScript does) and runs the binding in the engine's own context. The player the
	natives read (PLAYER) and the universe are stand-ins of other names (FakePlayer, FakeUniverse,
	amendment oo-ppc item 6) that answer only the selectors the binding sends and record what they
	are told; the player's HUD is a real one (made from an empty hud.plist, in a hidden GL context),
	and the message GUI's colours are real colours (the GUI stand-in is a C++ subclass since bead
	oo-9ht.143 deleted the GUI's facade). The expectations were written against the
	Objective-C file and run on it first; they pin the JS-visible behaviour of the property getter
	(every property), the passenger, parcel and contract methods with their argument checks
	(ValidateContracts()), and the PlayerEntity category the engine sends (the class name, and the
	JS object the player keeps until the engine resets).
	Run: bash tools/check-core-tests.sh test_OOJSPlayerShip
*/

#include "OOJavaScriptEngine.h"
#include "OOJSPlayerShip.h"
#include "OOJSPlayer.h"
#include "Universe.h"
#include "PlayerEntity.h"
#include "PlayerEntityContracts.h"
#include "HeadUpDisplay.h"
#include "OOColor.h"
#include "ResourceManager.h"
#include "EntityOOJavaScriptExtensions.h"
#include "StationEntity.h"
#include "oofnd/FileSystem.hpp"
#include "oofnd/Notification.hpp"
#include "oofnd/String.hpp"
#include "oo_test.hpp"
#include "oo_gl_test_context.hpp"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <process.h>
#include <string>
#include <set>
#include <vector>


// What UNIVERSE and PLAYER read (Universe.mm, PlayerEntity.mm).
extern Universe *gSharedUniverse;
extern PlayerEntity *gOOPlayer;


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


// MARK: The stand-ins -----------------------------------------------------------------------------

// An entity scripts can see; it answers like any Entity otherwise (an Objective-C subclass until bead
// oo-j12i2; a C++ one overriding the member its selector became).
class TestEntity : public Entity
{
public:
	bool isVisibleToScripts() override  { return true; }
};


// The GUI is C++ since bead oo-9ht.143 deleted its facade: the stand-in overrides the members the
// facade stand-in answered (proposed ADR-0056 amendment oo-9ht.1), with the same answers.
class FakeGui : public GuiDisplayGen
{
public:
	FakeGui() : GuiDisplayGen(NSMakeSize(480, 160), 1, 9, 19, 20, std::nullopt) {}

	oo::Ref<OOColor> _textColor, _textCommsColor;

	OOColor *getTextColor() override  { return _textColor.get(); }
	OOColor *getTextCommsColor() override  { return _textCommsColor.get(); }
	void setTextColor(OOColor *color) override  { _textColor = oo::Ref<OOColor>(color); }
	void setTextCommsColor(OOColor *color) override  { _textCommsColor = oo::Ref<OOColor>(color); }
	std::optional<std::string> reflowTextForMFD(const std::optional<std::string> &input) override  { return "[reflowed " + input.value_or("(nil)") + "]"; }
};


class FakeUniverse : public Universe
{
public:
	OOViewID _viewDirection = {};
	oo::Ref<FakeGui> _gui = {};
	std::string _lastCommander = {};
	std::vector<std::string> _messages = {};

	OOViewID getViewDirection() override	{ return _viewDirection; }
	::GuiDisplayGen *messageGUI() override	{ return _gui.get(); }
	OOCreditsQuantity tradeInValueForCommanderDictionary(const oo::PList &cmdrDict) override
	{
		_lastCommander = oo::DescriptionOf(cmdrDict);
		return 123456;
	}
	std::optional<std::string> descriptionForKey(const std::string &/*key*/) override	{ return std::nullopt; }
	::GuiDisplayGen *getGui() override	{ return _gui.get(); }
	void addMessage(const std::optional<std::string> &text, OOTimeDelta count) override	{ _messages.push_back(oo::str::format("%s %g", text.value_or("(nil)").c_str(), count)); }
};


class FakePlayer : public PlayerEntity	// C++ since bead oo-9ht.177 deleted the Objective-C player
{
public:
	oo::Ref<HeadUpDisplay> _hud;	// C++ since bead oo-mwd58
	Entity *_dockedStation = {}, *_compassTarget = {};
	BOOL _docked = {};
	std::optional<std::string> _specialCargo, _fastA, _fastB;
	std::string _primed;
	std::vector<std::optional<std::string>> _mfds;
	NSUInteger _passengers = {}, _capacity = {}, _parcels = {};
	double _clockTime = {};
	BOOL _contractsAccept = {};
	std::vector<std::string> _log;
	Entity *_other = {};
	std::vector<Entity *> _compassCycle;
	std::set<std::string> _equipment;
	BOOL _hyperspaceMotor = {};

	void setScriptTarget(::ShipEntity * /*ship*/) override	{  }
	NSUInteger getActiveMissile() override	{ return 2; }
	float fuelLeakRate() override	{ return 0.5f; }
	bool isDocked() override	{ return _docked; }
	// The station is C++ since bead oo-9ht.175: the stand-in entity's C++ part, which only crosses back to
	// its Objective-C object (oo::ToObjC) in the code the test runs, as the stub universe's planet does.
	::StationEntity * dockedStation() override	{ return static_cast<::StationEntity *>(_dockedStation); }
	std::optional<std::string> getSpecialCargo() override	{ return _specialCargo; }
	::HeadUpDisplay * getHud() override	{ return _hud.get(); }
	OOGalacticHyperspaceBehaviour getGalacticHyperspaceBehaviour() override	{ return GALACTIC_HYPERSPACE_BEHAVIOUR_FIXED_COORDINATES; }
	NSPoint getGalacticHyperspaceFixedCoords() override	{ return NSMakePoint(64, 128); }
	std::optional<std::string> fastEquipmentA() override	{ return _fastA; }
	std::optional<std::string> fastEquipmentB() override	{ return _fastB; }
	std::string currentPrimedEquipment() override	{ return _primed; }
	GLfloat forwardShieldLevel() override	{ return 10; }
	GLfloat aftShieldLevel() override	{ return 20; }
	float maxForwardShieldLevel() override	{ return 128; }
	float maxAftShieldLevel() override	{ return 256; }
	float forwardShieldRechargeRate() override	{ return 1.5f; }
	float aftShieldRechargeRate() override	{ return 2.5f; }
	std::vector<std::optional<std::string>> multiFunctionDisplayList() override	{ return _mfds; }
	bool dialIdentEngaged() override	{ return YES; }
	OOLongRangeChartMode getLongRangeChartMode() override	{ return OOLRC_MODE_ECONOMY; }
	NSPoint getGalaxy_coordinates() override	{ return NSMakePoint(20, 40); }
	NSPoint getCursor_coordinates() override	{ return NSMakePoint(30, 60); }
	OOSystemID targetSystemID() override	{ return 7; }
	OOSystemID nextHopTargetSystemID() override	{ return 8; }
	OOSystemID infoSystemID() override	{ return 9; }
	OOSystemID previousSystemID() override	{ return 6; }
	OORouteType ANAMode() override	{ return OPTIMIZED_BY_TIME; }
	bool getScoopOverride() override	{ return YES; }
	bool injectorsEngaged() override	{ return NO; }
	bool getMassLockable() override	{ return YES; }
	bool hyperspeedEngaged() override	{ return NO; }
	Entity * getCompassTargetEntity() override	{ return _compassTarget; }
	OOCompassMode getCompassMode() override	{ return COMPASS_MODE_PLANET; }
	bool weaponsOnline() override	{ return YES; }
	Vector viewpointOffsetAft() override	{ return make_vector(0, 0, -1); }
	Vector viewpointOffsetForward() override	{ return make_vector(0, 0, 1); }
	Vector viewpointOffsetPort() override	{ return make_vector(-1, 0, 0); }
	Vector viewpointOffsetStarboard() override	{ return make_vector(1, 0, 0); }
	OOWeaponFacing getCurrentWeaponFacing() override	{ return WEAPON_FACING_FORWARD; }
	::OOEquipmentType * weaponTypeForFacing(OOWeaponFacing facing, bool strict) override	{ _log.push_back(oo::str::format("weaponTypeForFacing %d %d", static_cast<int>(facing), strict ? 1 : 0)); return nil; }
	oo::PList commanderDataDictionary() override	{ return oo::PList(std::string("commander")); }
	int tradeInFactor() override	{ return 95; }
	double renovationCosts() override	{ return 1500; }
	double renovationFactor() override	{ return 1.25; }
	GLfloat getFlightPitch() override	{ return 0.25f; }
	GLfloat getFlightRoll() override	{ return -0.5f; }
	GLfloat getFlightYaw() override	{ return 0.125f; }
	NSUInteger passengerCount() override	{ return _passengers; }
	NSUInteger passengerCapacity() override	{ return _capacity; }
	NSUInteger parcelCount() override	{ return _parcels; }
	double clockTime() override	{ return _clockTime; }
	void setFuelLeakRate(float value) override	{ _log.push_back(oo::str::format("setFuelLeakRate %g", value)); }
	void setMassLockable(bool newValue) override	{ _log.push_back(oo::str::format("setMassLockable %d", newValue ? 1 : 0)); }
	void setLongRangeChartMode(OOLongRangeChartMode mode) override	{ _log.push_back(oo::str::format("setLongRangeChartMode %d", static_cast<int>(mode))); }
	using PlayerEntity::doScriptEvent;
	void doScriptEvent(ooscript::PropertyId /*message*/, const std::vector<oo::PList> & arguments) override
	{
		std::string event = "event(";
		for (std::size_t i = 0; i < arguments.size(); i++)  event += (i != 0 ? ", " : "") + oo::DescriptionOf(arguments[i]);
		_log.push_back(event + ")");
	}
	void setCompassMode(OOCompassMode value) override	{ _log.push_back(oo::str::format("setCompassMode %d", static_cast<int>(value))); }
	void validateCompassTarget() override	{ _log.push_back("validateCompassTarget"); }
	void setNextCompassMode() override
	{
		_log.push_back("setNextCompassMode");
		if (!_compassCycle.empty())
		{
			_compassTarget = _compassCycle.front();
			_compassCycle.erase(_compassCycle.begin());
		}
	}
	bool hasEquipmentItemProviding(const std::string & equipmentType) override	{ return _equipment.count(equipmentType) != 0; }
	void setGalacticHyperspaceBehaviour(OOGalacticHyperspaceBehaviour behaviour) override	{ _log.push_back(oo::str::format("setGalacticHyperspaceBehaviour %d", static_cast<int>(behaviour))); }
	void setGalacticHyperspaceFixedCoords(NSPoint point) override	{ _log.push_back(oo::str::format("setGalacticHyperspaceFixedCoords %g %g", point.x, point.y)); }
	void setFastEquipmentA(const std::optional<std::string> & eqKey) override	{ _log.push_back("setFastEquipmentA " + eqKey.value_or("(nil)")); }
	void setFastEquipmentB(const std::optional<std::string> & eqKey) override	{ _log.push_back("setFastEquipmentB " + eqKey.value_or("(nil)")); }
	bool setPrimedEquipment(const std::string & eqKey, bool showMsg) override
	{
		_log.push_back(oo::str::format("setPrimedEquipment %s %d", eqKey.c_str(), showMsg ? 1 : 0));
		return eqKey != "EQ_NONE_SUCH";
	}
	void decrease_flight_pitch(double delta) override	{ _log.push_back(oo::str::format("decrease_flight_pitch %g", delta)); }
	void decrease_flight_roll(double delta) override	{ _log.push_back(oo::str::format("decrease_flight_roll %g", delta)); }
	void decrease_flight_yaw(double delta) override	{ _log.push_back(oo::str::format("decrease_flight_yaw %g", delta)); }
	void setForwardShieldLevel(GLfloat level) override	{ _log.push_back(oo::str::format("setForwardShieldLevel %g", level)); }
	void setAftShieldLevel(GLfloat level) override	{ _log.push_back(oo::str::format("setAftShieldLevel %g", level)); }
	void setMaxForwardShieldLevel(float newValue) override	{ _log.push_back(oo::str::format("setMaxForwardShieldLevel %g", newValue)); }
	void setMaxAftShieldLevel(float newValue) override	{ _log.push_back(oo::str::format("setMaxAftShieldLevel %g", newValue)); }
	void setForwardShieldRechargeRate(float newValue) override	{ _log.push_back(oo::str::format("setForwardShieldRechargeRate %g", newValue)); }
	void setAftShieldRechargeRate(float newValue) override	{ _log.push_back(oo::str::format("setAftShieldRechargeRate %g", newValue)); }
	void setScoopOverride(bool newValue) override	{ _log.push_back(oo::str::format("setScoopOverride %d", newValue ? 1 : 0)); }
	bool switchHudTo(const std::string & hudFileName) override
	{
		_log.push_back("switchHudTo " + hudFileName);
		return YES;
	}
	void resetHud() override	{ _log.push_back("resetHud"); }
	void adjustTradeInFactorBy(int value) override	{ _log.push_back(oo::str::format("adjustTradeInFactorBy %d", value)); }
	bool setWeaponMount(OOWeaponFacing facing, const std::string & eqKey, const std::optional<std::string> & context) override
	{
		_log.push_back(oo::str::format("setWeaponMount %d %s %s", static_cast<int>(facing), eqKey.c_str(), context.value_or("(nil)").c_str()));
		return YES;
	}
	void setStatus(OOEntityStatus stat) override	{ _log.push_back(oo::str::format("setStatus %d", static_cast<int>(stat))); Entity::setStatus(stat); }	// the root's status, which status() answers
	void setTargetSystemID(OOSystemID sid) override	{ _log.push_back(oo::str::format("setTargetSystemID %d", sid)); }
	void setInfoSystemID(OOSystemID sid, bool moveChart) override	{ _log.push_back(oo::str::format("setInfoSystemID %d %d", sid, moveChart ? 1 : 0)); }
	void launchFromStation() override	{ _log.push_back("launchFromStation"); }
	void removeAllCargo() override	{ _log.push_back("removeAllCargo"); }
	void useSpecialCargo(const std::string & descriptionString) override	{ _log.push_back("useSpecialCargo " + descriptionString); }
	bool engageAutopilotToStation(::StationEntity * /*stationForDocking*/) override	{ _log.push_back("engageAutopilotToStation"); return YES; }
	void disengageAutopilot() override	{ _log.push_back("disengageAutopilot"); }
	void requestDockingClearance(::StationEntity * /*stationForDocking*/) override	{ _log.push_back("requestDockingClearance"); }
	void cancelDockingRequest(::StationEntity * /*stationForDocking*/) override	{ _log.push_back("cancelDockingRequest"); }
	bool assignToActivePylon(const std::string & identifierKey) override	{ _log.push_back("assignToActivePylon " + identifierKey); return YES; }
	void setCustomViewDataFromDictionary(const oo::PList & viewDict, bool withScaling) override	{ _log.push_back(oo::str::format("setCustomViewData %s %d", oo::DescriptionOf(viewDict).c_str(), withScaling ? 1 : 0)); }
	void noteSwitchToView(OOViewID toView, OOViewID fromView) override	{ _log.push_back(oo::str::format("noteSwitchToView %d %d", static_cast<int>(toView), static_cast<int>(fromView))); }
	void resetCustomView() override	{ _log.push_back("resetCustomView"); }
	void resetScannerZoom() override	{ _log.push_back("resetScannerZoom"); }
	bool takeInternalDamage() override	{ _log.push_back("takeInternalDamage"); return YES; }
	bool hasHyperspaceMotor() override	{ return _hyperspaceMotor; }
	bool witchJumpChecklist(bool isGalacticJump) override	{ _log.push_back(oo::str::format("witchJumpChecklist %d", isGalacticJump ? 1 : 0)); return YES; }
	void beginWitchspaceCountdown(int spin_time) override	{ _log.push_back(oo::str::format("beginWitchspaceCountdown %d", spin_time)); }
	void cancelWitchspaceCountdown() override	{ _log.push_back("cancelWitchspaceCountdown"); }
	void setJumpType(bool isGalacticJump) override	{ _log.push_back(oo::str::format("setJumpType %d", isGalacticJump ? 1 : 0)); }
	void setWitchspaceCountdown(int spin_time) override	{ _log.push_back(oo::str::format("setWitchspaceCountdown %d", spin_time)); }
	void playGalacticHyperspace() override	{ _log.push_back("playGalacticHyperspace"); }
	bool setMultiFunctionDisplay(NSUInteger index, const std::optional<std::string> & key) override
	{
		_log.push_back(oo::str::format("setMultiFunctionDisplay %u %s", static_cast<unsigned>(index), key.value_or("(nil)").c_str()));
		return index < 3;
	}
	void setMultiFunctionText(const std::optional<std::string> & text, const std::optional<std::string> & key) override	{ _log.push_back("setMultiFunctionText " + key.value_or("(nil)") + " " + text.value_or("(nil)")); }
	void setDialCustom(const oo::PList & value, const std::string & dialKey) override	{ _log.push_back("setDialCustom " + dialKey + " " + oo::DescriptionOf(value)); }
	bool addPassenger(const std::string & Name, unsigned start, unsigned destination, double eta, double fee, double advance, unsigned risk) override
	{
		_log.push_back(oo::str::format("addPassenger %s %u %u %g %g %g %u", Name.c_str(), start, destination, eta, fee, advance, risk));
		return _contractsAccept;
	}
	bool removePassenger(const std::string & Name) override
	{
		_log.push_back("removePassenger " + Name);
		return _contractsAccept;
	}
	bool addParcel(const std::string & Name, unsigned start, unsigned destination, double eta, double fee, double premium, unsigned risk) override
	{
		_log.push_back(oo::str::format("addParcel %s %u %u %g %g %g %u", Name.c_str(), start, destination, eta, fee, premium, risk));
		return _contractsAccept;
	}
	bool removeParcel(const std::string & Name) override
	{
		_log.push_back("removeParcel " + Name);
		return _contractsAccept;
	}
	bool awardContract(unsigned qty, const std::string & commodity, unsigned start, unsigned destination, double eta, double fee, double premium) override
	{
		_log.push_back(oo::str::format("awardContract %u %s %u %u %g %g %g", qty, commodity.c_str(), start, destination, eta, fee, premium));
		return _contractsAccept;
	}
	bool removeContract(const std::string & commodity, unsigned destination) override
	{
		_log.push_back(oo::str::format("removeContract %s %u", commodity.c_str(), destination));
		return _contractsAccept;
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

namespace stdfs = std::filesystem;

stdfs::path sRoot;
FakeUniverse *sUniverse = nil;
FakePlayer *sPlayer = nullptr;
PlayerEntity *sRealPlayer = nullptr;


// The scratch home and game folder, the engine, and the stand-ins; made once.
void SetUp()
{
	OO_CHECK(OOTestGLContext());
	if (!sRoot.empty())  return;
	std::setvbuf(stdout, nullptr, _IONBF, 0);	// a crash keeps the results so far
	sRoot = stdfs::temp_directory_path() / ("oo-test-jsplayership-" + std::to_string(static_cast<unsigned long>(::_getpid())));
	stdfs::remove_all(sRoot);
	stdfs::create_directories(sRoot / "Resources");
	OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
	stdfs::current_path(sRoot);
	const std::string info = "{ CFBundleVersion = \"9.9.9-test\"; }";
	OO_CHECK(oo::fs::writeFile(sRoot / "Resources" / "Info-gnustep.plist", oo::Data(info.data(), info.size()), oo::fs::WriteMode::direct).has_value());
	ResourceManager::setUseAddOns(std::string(SCENARIO_OXP_DEFINITION_NONE));	// strict: the built-in Resources alone
	(void)OOJavaScriptEngine::sharedEngine();

	sRealPlayer = gOOPlayer;	// the one InitOOJSPlayerShip() made, which player.ship holds

	sUniverse = new FakeUniverse();
	sUniverse->_viewDirection = VIEW_AFT;
	sUniverse->_gui = oo::makeRef<FakeGui>();
	sUniverse->_gui->_textColor = OOColor::colorWithRed(1.0f, 0.5f, 0.25f, 1.0f);
	sUniverse->_gui->_textCommsColor = OOColor::colorWithRed(0.0f, 1.0f, 0.0f, 0.5f);
	gSharedUniverse = sUniverse;

	sPlayer = NewTestPlayer<FakePlayer>();
	sPlayer->_hud = oo::makeRef<HeadUpDisplay>();
	sPlayer->_hud->initWithDictionary(oo::PList(oo::PList::Dict{}), std::string("test-hud.plist"));
	{
		sPlayer->_dockedStation = oo::RetainEntity(oo::MadeEntity(oo::makeRef<TestEntity>()));	// +1, as +alloc's was
		sPlayer->_other = oo::RetainEntity(oo::MadeEntity(oo::makeRef<TestEntity>()));
	}
	sPlayer->_dockedStation->setPosition(make_HPvector(5, 0, 0));
	sPlayer->_docked = YES;
	sPlayer->_specialCargo = "Ten tonnes of rare orchids";
	sPlayer->_fastA = "EQ_CLOAKING_DEVICE";
	sPlayer->_primed = "EQ_ECM";
	sPlayer->_mfds = { std::string("mfd-a"), std::nullopt, std::string("mfd-c") };
	sPlayer->_capacity = 2;
	sPlayer->_clockTime = 1000;
	sPlayer->_contractsAccept = YES;
	sPlayer->Entity::setStatus(STATUS_DOCKED);
	gOOPlayer = sPlayer;
}


// Evaluates src in the engine's context and gives its result as a string ("undefined", "null",
// ...), or "threw: <message>".
std::string Eval(const std::string &src)
{
	SetUp();
	ooscript::Context context = OOJSAcquireContext();
	ooscript::Object global = OOJavaScriptEngine::sharedEngine()->globalObject();
	std::string wrapped = "(function () { try { return String(" + src + "); } catch (e) { return 'threw: ' + (e && e.message !== undefined ? e.message : e); } })()";
	ooscript::Value result = ooscript::undefinedValue();
	std::string text;
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
	OO_CHECK(sRealPlayer != nullptr);
	OO_CHECK_EVAL("typeof player.ship", "object");
	OO_CHECK(std::strcmp(JSPlayerShipClass()->name, "PlayerShip") == 0);
	OO_CHECK(JSPlayerShipPrototype() != nullptr);
	OO_CHECK_EVAL("player.ship instanceof Ship", "true");
	OO_CHECK_EVAL("Object.getPrototypeOf(player.ship) === Object.getPrototypeOf(Object.getPrototypeOf(player.ship)) ? 'same' : 'derived'", "derived");
}


OO_TEST(getterPlayerState)
{
	SetUp();
	OO_CHECK_EVAL("player.ship.activeMissile", "2");
	OO_CHECK_EVAL("player.ship.fuelLeakRate", "0.5");
	OO_CHECK_EVAL("player.ship.docked", "true");
	OO_CHECK_EVAL("player.ship.dockedStation === null", "false");
	OO_CHECK_EVAL("player.ship.specialCargo", "Ten tonnes of rare orchids");
	OO_CHECK_EVAL("player.ship.galacticHyperspaceBehaviour", "BEHAVIOUR_FIXED_COORDINATES");
	OO_CHECK_EVAL("player.ship.galacticHyperspaceFixedCoords", "(64, 128, 0)");
	OO_CHECK_EVAL("player.ship.galacticHyperspaceFixedCoordsInLY", "(25.6, 25.6, 0)");
	OO_CHECK_EVAL("player.ship.fastEquipmentA", "EQ_CLOAKING_DEVICE");
	OO_CHECK_EVAL("player.ship.fastEquipmentB", "null");
	OO_CHECK_EVAL("player.ship.primedEquipment", "EQ_ECM");
	OO_CHECK_EVAL("player.ship.forwardShield", "10");
	OO_CHECK_EVAL("player.ship.aftShield", "20");
	OO_CHECK_EVAL("player.ship.maxForwardShield", "128");
	OO_CHECK_EVAL("player.ship.maxAftShield", "256");
	OO_CHECK_EVAL("player.ship.forwardShieldRechargeRate", "1.5");
	OO_CHECK_EVAL("player.ship.aftShieldRechargeRate", "2.5");
	OO_CHECK_EVAL("JSON.stringify(player.ship.multiFunctionDisplayList)", "[\"mfd-a\",null,\"mfd-c\"]");
	OO_CHECK_EVAL("player.ship.missilesOnline", "false");
	OO_CHECK_EVAL("player.ship.chartHighlightMode", "OOLRC_MODE_ECONOMY");
	OO_CHECK_EVAL("player.ship.galaxyCoordinates", "(20, 40, 0)");
	OO_CHECK_EVAL("player.ship.galaxyCoordinatesInLY", "(8, 8, 0)");
	OO_CHECK_EVAL("player.ship.cursorCoordinates", "(30, 60, 0)");
	OO_CHECK_EVAL("player.ship.cursorCoordinatesInLY", "(12, 12, 0)");
	OO_CHECK_EVAL("player.ship.targetSystem", "7");
	OO_CHECK_EVAL("player.ship.nextSystem", "8");
	OO_CHECK_EVAL("player.ship.infoSystem", "9");
	OO_CHECK_EVAL("player.ship.previousSystem", "6");
	OO_CHECK_EVAL("player.ship.routeMode", "OPTIMIZED_BY_TIME");
	OO_CHECK_EVAL("player.ship.scoopOverride", "true");
	OO_CHECK_EVAL("player.ship.injectorsEngaged", "false");
	OO_CHECK_EVAL("player.ship.massLockable", "true");
	OO_CHECK_EVAL("player.ship.torusEngaged", "false");
	OO_CHECK_EVAL("player.ship.compassTarget", "null");
	OO_CHECK_EVAL("player.ship.compassType", "OO_COMPASSTYPE_ADVANCED");
	OO_CHECK_EVAL("player.ship.compassMode", "COMPASS_MODE_PLANET");
	OO_CHECK_EVAL("player.ship.weaponsOnline", "true");
	OO_CHECK_EVAL("player.ship.viewDirection", "VIEW_AFT");
	OO_CHECK_EVAL("player.ship.viewPositionAft", "(0, 0, -1)");
	OO_CHECK_EVAL("player.ship.viewPositionForward", "(0, 0, 1)");
	OO_CHECK_EVAL("player.ship.viewPositionPort", "(-1, 0, 0)");
	OO_CHECK_EVAL("player.ship.viewPositionStarboard", "(1, 0, 0)");
	Log(sPlayer->_log);
	OO_CHECK_EVAL("player.ship.currentWeapon", "null");
	OO_CHECK_LOG(sPlayer->_log, oo::str::format("weaponTypeForFacing %d 0", static_cast<int>(WEAPON_FACING_FORWARD)));
	OO_CHECK_EVAL("player.ship.price", "123456");
	OO_CHECK_EQ(sUniverse->_lastCommander, "commander");
	OO_CHECK_EVAL("player.ship.serviceLevel", "95");
	OO_CHECK_EVAL("player.ship.renovationCost", "1500");
	OO_CHECK_EVAL("player.ship.renovationMultiplier", "1.25");
	OO_CHECK_EVAL("player.ship.pitch", "-0.25");
	OO_CHECK_EVAL("player.ship.roll", "0.5");
	OO_CHECK_EVAL("player.ship.yaw", "-0.125");
	OO_CHECK_EVAL("player.ship.messageGuiTextColor", "1,0.5,0.25,1");
	OO_CHECK_EVAL("player.ship.messageGuiTextCommsColor", "0,1,0,0.5");
}


OO_TEST(getterHUD)
{
	SetUp();
	OO_CHECK_EVAL("player.ship.reticleColorTarget.length", "4");
	OO_CHECK_EVAL("player.ship.reticleColorTargetSensitive.length", "4");
	OO_CHECK_EVAL("player.ship.reticleColorWormhole.length", "4");
	OO_CHECK_EVAL("player.ship.reticleTargetSensitive", "false");
	OO_CHECK_EVAL("player.ship.multiFunctionDisplays", "0");
	OO_CHECK_EVAL("player.ship.scannerMinimalistic", "false");
	OO_CHECK_EVAL("player.ship.scannerNonLinear", "false");
	OO_CHECK_EVAL("player.ship.scannerUltraZoom", "false");
	OO_CHECK_EVAL("player.ship.hud", "test-hud.plist");
	OO_CHECK_EVAL("player.ship.crosshairs", "null");
	OO_CHECK_EVAL("player.ship.hudAllowsBigGui", "false");
	OO_CHECK_EVAL("player.ship.hudHidden", "false");

	// A player with no HUD: what messages to nil answered.
	oo::Ref<HeadUpDisplay> hud = sPlayer->_hud;
	sPlayer->_hud = nullptr;
	OO_CHECK_EVAL("player.ship.reticleColorTarget", "null");
	OO_CHECK_EVAL("player.ship.reticleTargetSensitive", "false");
	OO_CHECK_EVAL("player.ship.multiFunctionDisplays", "0");
	OO_CHECK_EVAL("player.ship.hud", "null");
	OO_CHECK_EVAL("player.ship.crosshairs", "null");
	OO_CHECK_EVAL("player.ship.hudHidden", "false");
	sPlayer->_hud = hud;
}


OO_TEST(passengersAndParcels)
{
	SetUp();
	Log(sPlayer->_log);
	OO_CHECK_EVAL("player.ship.addPassenger('Ann', 3, 4, 2000, 50)", "true");
	OO_CHECK_EVAL("player.ship.addPassenger('Bob', 3, 4, 2000, 50, 10, 2)", "true");
	OO_CHECK_LOG(sPlayer->_log, "addPassenger Ann 3 4 2000 50 0 0; addPassenger Bob 3 4 2000 50 10 2");
	sPlayer->_passengers = 2;	// full
	OO_CHECK_EVAL("player.ship.addPassenger('Cy', 3, 4, 2000, 50)", "false");
	OO_CHECK_LOG(sPlayer->_log, "");
	OO_CHECK_EVAL("player.ship.removePassenger('Ann')", "true");
	OO_CHECK_EVAL("player.ship.removePassenger('')", "false");
	OO_CHECK_LOG(sPlayer->_log, "removePassenger Ann");
	sPlayer->_passengers = 0;
	OO_CHECK_EVAL("player.ship.removePassenger('Ann')", "false");	// none aboard

	OO_CHECK_EVAL("player.ship.addParcel('Box', 1, 2, 3000, 20, 5)", "true");
	OO_CHECK_LOG(sPlayer->_log, "addParcel Box 1 2 3000 20 5 0");
	OO_CHECK_EVAL("player.ship.removeParcel('Box')", "false");	// none aboard
	sPlayer->_parcels = 1;
	OO_CHECK_EVAL("player.ship.removeParcel('Box')", "true");
	OO_CHECK_LOG(sPlayer->_log, "removeParcel Box");
	sPlayer->_parcels = 0;

	// The argument checks.
	OO_CHECK(Eval("player.ship.addPassenger('Ann', 3, 4, 2000)").rfind("threw: ", 0) == 0);	// too few
	OO_CHECK(Eval("player.ship.addPassenger(null, 3, 4, 2000, 50)").rfind("threw: ", 0) == 0);	// no name
	OO_CHECK(Eval("player.ship.addPassenger('Ann', -1, 4, 2000, 50)").rfind("threw: ", 0) == 0);	// bad start
	OO_CHECK(Eval("player.ship.addPassenger('Ann', 3, 300, 2000, 50)").rfind("threw: ", 0) == 0);	// bad destination
	OO_CHECK(Eval("player.ship.addPassenger('Ann', 3, 4, 999, 50)").rfind("threw: ", 0) == 0);	// in the past
	OO_CHECK(Eval("player.ship.addPassenger('Ann', 3, 4, 2000, -5)").rfind("threw: ", 0) == 0);	// negative fee
	OO_CHECK(Eval("player.ship.addParcel('Box', 1, 2, 3000)").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("player.ship.removePassenger()").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("player.ship.removeParcel()").rfind("threw: ", 0) == 0);
	OO_CHECK_LOG(sPlayer->_log, "");
}


OO_TEST(contracts)
{
	SetUp();
	Log(sPlayer->_log);
	OO_CHECK_EVAL("player.ship.awardContract(5, 'food', 1, 2, 4000, 100)", "true");
	OO_CHECK_EVAL("player.ship.awardContract(5, 'food', 1, 2, 4000, 100, 30)", "true");
	OO_CHECK_LOG(sPlayer->_log, "awardContract 5 food 1 2 4000 100 0; awardContract 5 food 1 2 4000 100 30");
	sPlayer->_contractsAccept = NO;
	OO_CHECK_EVAL("player.ship.awardContract(5, 'food', 1, 2, 4000, 100)", "false");
	OO_CHECK_EVAL("player.ship.removeContract('food', 2)", "false");
	sPlayer->_contractsAccept = YES;
	OO_CHECK_EVAL("player.ship.removeContract('food', 2)", "true");
	OO_CHECK_LOG(sPlayer->_log, "awardContract 5 food 1 2 4000 100 0; removeContract food 2; removeContract food 2");

	OO_CHECK(Eval("player.ship.awardContract(5, 'food', 1, 2, 4000)").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("player.ship.awardContract('x', 'food', 1, 2, 4000, 100)").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("player.ship.awardContract(5, null, 1, 2, 4000, 100)").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("player.ship.awardContract(5, 'food', 1, 2, 10, 100)").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("player.ship.removeContract('food')").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("player.ship.removeContract('food', 256)").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("player.ship.removeContract(null, 2)").rfind("threw: ", 0) == 0);
	OO_CHECK_LOG(sPlayer->_log, "");
}




// Slice 2 (bead oo-9t14): the property setter, launch, cargo, autopilot, docking and the pylon.
OO_TEST(setterPlayerState)
{
	SetUp();
	Log(sPlayer->_log);
	OO_CHECK_EVAL("(function () { player.ship.fuelLeakRate = 2; player.ship.massLockable = false; player.ship.scoopOverride = true; })()", "undefined");
	OO_CHECK_LOG(sPlayer->_log, "setFuelLeakRate 2; setMassLockable 0; setScoopOverride 1");
	OO_CHECK_EVAL("(function () { player.ship.forwardShield = 1; player.ship.aftShield = 2; player.ship.maxForwardShield = 3; player.ship.maxAftShield = 4; player.ship.forwardShieldRechargeRate = 5; player.ship.aftShieldRechargeRate = 6; })()", "undefined");
	OO_CHECK_LOG(sPlayer->_log, "setForwardShieldLevel 1; setAftShieldLevel 2; setMaxForwardShieldLevel 3; setMaxAftShieldLevel 4; setForwardShieldRechargeRate 5; setAftShieldRechargeRate 6");
	OO_CHECK_EVAL("(function () { player.ship.pitch = 0.5; player.ship.roll = 1; player.ship.yaw = -0.5; player.ship.pitch = NaN; })()", "undefined");
	OO_CHECK_LOG(sPlayer->_log, "decrease_flight_pitch 0.75; decrease_flight_roll 0.5; decrease_flight_yaw -0.375");
	OO_CHECK_EVAL("(function () { player.ship.fastEquipmentA = 'EQ_A'; player.ship.fastEquipmentB = 'EQ_B'; return player.ship.primedEquipment = 'EQ_ECM'; })()", "EQ_ECM");
	OO_CHECK_LOG(sPlayer->_log, "setFastEquipmentA EQ_A; setFastEquipmentB EQ_B; setPrimedEquipment EQ_ECM 0");
	OO_CHECK_EVAL("(function () { player.ship.galacticHyperspaceBehaviour = 'BEHAVIOUR_ALL_SYSTEMS_REACHABLE'; player.ship.galacticHyperspaceFixedCoords = [10, 20, 0]; player.ship.galacticHyperspaceFixedCoordsInLY = [4, 4, 0]; })()", "undefined");
	OO_CHECK_LOG(sPlayer->_log, oo::str::format("setGalacticHyperspaceBehaviour %d; setGalacticHyperspaceFixedCoords 10 20; setGalacticHyperspaceFixedCoords 10 20", static_cast<int>(GALACTIC_HYPERSPACE_BEHAVIOUR_ALL_SYSTEMS_REACHABLE)));
	OO_CHECK_EVAL("(function () { player.ship.serviceLevel = 90; })()", "undefined");
	OO_CHECK_LOG(sPlayer->_log, "adjustTradeInFactorBy -5");
	OO_CHECK_EVAL("(function () { player.ship.infoSystem = 12; })()", "undefined");
	// Out of range: the setter answers false with no exception, which ends the script uncatchably.
	OO_CHECK_EVAL("(function () { player.ship.infoSystem = 300; })()", "<evaluation failed>");
	OO_CHECK_LOG(sPlayer->_log, "setInfoSystemID 12 1");
	OO_CHECK_EVAL("(function () { player.ship.currentWeapon = 'EQ_NO_SUCH_WEAPON_X'; })()", "undefined");
	OO_CHECK_LOG(sPlayer->_log, oo::str::format("setWeaponMount %d EQ_WEAPON_NONE scripted", static_cast<int>(WEAPON_FACING_FORWARD)));
}


OO_TEST(setterChartAndCompass)
{
	SetUp();
	Log(sPlayer->_log);
	OO_CHECK_EVAL("(function () { player.ship.chartHighlightMode = 'OOLRC_MODE_TECHLEVEL'; })()", "undefined");
	OO_CHECK_LOG(sPlayer->_log, oo::str::format("setLongRangeChartMode %d; event(OOLRC_MODE_ECONOMY)", static_cast<int>(OOLRC_MODE_TECHLEVEL)));
	OO_CHECK(Eval("(function () { player.ship.chartHighlightMode = 'OOLRC_MODE_NONSENSE'; })()").rfind("threw: ", 0) == 0);
	OO_CHECK_EVAL("(function () { player.ship.compassMode = 'COMPASS_MODE_SUN'; })()", "undefined");
	OO_CHECK_LOG(sPlayer->_log, oo::str::format("setCompassMode %d; validateCompassTarget", static_cast<int>(COMPASS_MODE_SUN)));
	// The compass target: only with an advanced compass; the modes are cycled until it is found.
	OO_CHECK_EVAL("(function () { player.ship.compassTarget = player.ship.dockedStation; })()", "threw: Compass target cannot be set with a basic compass.");
	sPlayer->_equipment.insert("EQ_ADVANCED_COMPASS");

	// (Without the equipment, the advanced type also logs a warning through the engine's error
	// reporter, which reaches parts of the game this test does not stand in for.)
	OO_CHECK_EVAL("(function () { player.ship.compassType = 'OO_COMPASSTYPE_BASIC'; player.ship.compassType = 'OO_COMPASSTYPE_ADVANCED'; })()", "undefined");
	OO_CHECK_LOG(sPlayer->_log, oo::str::format("setCompassMode %d; setCompassMode %d", static_cast<int>(COMPASS_MODE_BASIC), static_cast<int>(COMPASS_MODE_PLANET)));
	OO_CHECK(Eval("(function () { player.ship.compassType = 'OO_COMPASSTYPE_FANCY'; })()").rfind("threw: ", 0) == 0);
	Log(sPlayer->_log);
	sPlayer->_compassCycle = { sPlayer->_other, sPlayer->_dockedStation };
	OO_CHECK_EVAL("(function () { player.ship.compassTarget = player.ship.dockedStation; return player.ship.compassTarget === player.ship.dockedStation; })()", "true");
	OO_CHECK_LOG(sPlayer->_log, "setNextCompassMode; validateCompassTarget; setNextCompassMode; validateCompassTarget");
	OO_CHECK(Eval("(function () { player.ship.compassTarget = null; })()").rfind("threw: ", 0) == 0);
	sPlayer->_compassTarget = nil;
	sPlayer->_equipment.clear();
}


OO_TEST(setterHUD)
{
	SetUp();
	Log(sPlayer->_log);
	OO_CHECK_EVAL("(function () { player.ship.reticleTargetSensitive = true; return player.ship.reticleTargetSensitive; })()", "true");
	OO_CHECK_EVAL("(function () { player.ship.scannerMinimalistic = true; return player.ship.scannerMinimalistic; })()", "true");
	OO_CHECK_EVAL("(function () { player.ship.scannerNonLinear = true; return player.ship.scannerNonLinear; })()", "true");
	OO_CHECK_EVAL("(function () { player.ship.scannerUltraZoom = true; return player.ship.scannerUltraZoom; })()", "true");
	OO_CHECK_EVAL("(function () { player.ship.hudHidden = true; return player.ship.hudHidden; })()", "true");
	OO_CHECK_EVAL("(function () { player.ship.reticleTargetSensitive = false; player.ship.scannerMinimalistic = false; player.ship.scannerNonLinear = false; player.ship.scannerUltraZoom = false; player.ship.hudHidden = false; })()", "undefined");
	OO_CHECK_EVAL("(function () { player.ship.reticleColorTarget = 'redColor'; return player.ship.reticleColorTarget; })()", "1,0,0,1");
	OO_CHECK_EVAL("(function () { player.ship.reticleColorTargetSensitive = [0, 0, 1]; return player.ship.reticleColorTargetSensitive; })()", "0,0,1,1");
	OO_CHECK_EVAL("(function () { player.ship.reticleColorWormhole = 'greenColor'; return player.ship.reticleColorWormhole; })()", "0,1,0,1");
	OO_CHECK_EVAL("(function () { player.ship.hud = 'other-hud.plist'; player.ship.hud = null; })()", "undefined");
	OO_CHECK_LOG(sPlayer->_log, "switchHudTo other-hud.plist; resetHud");
	OO_CHECK_EVAL("(function () { player.ship.crosshairs = null; })()", "undefined");
	OO_CHECK_LOG(sPlayer->_log, "switchHudTo test-hud.plist");

	// The message GUI's colours.
	OO_CHECK_EVAL("(function () { player.ship.messageGuiTextColor = 'blueColor'; player.ship.messageGuiTextCommsColor = null; return player.ship.messageGuiTextColor; })()", "0,0,1,1");
	OO_CHECK(sUniverse->_gui->_textCommsColor == nil);
	OO_CHECK_EVAL("(function () { player.ship.messageGuiTextColor = 'notAColor'; })()", "threw: Cannot set property messageGuiTextColor of instance of PlayerShip to invalid value \"notAColor\".");

	// No HUD: nothing to set.
	oo::Ref<HeadUpDisplay> hud = sPlayer->_hud;
	sPlayer->_hud = nullptr;
	OO_CHECK_EVAL("(function () { player.ship.hudHidden = true; return player.ship.hudHidden; })()", "false");
	// A reticle colour answers what the HUD answered, NO: false with no exception, which ends the script.
	OO_CHECK_EVAL("(function () { player.ship.reticleColorTarget = 'redColor'; })()", "<evaluation failed>");
	sPlayer->_hud = hud;
	OO_CHECK_EVAL("player.ship.hudHidden", "false");
}


OO_TEST(setterTargetSystem)
{
	SetUp();
	Log(sPlayer->_log);
	sPlayer->Entity::setStatus(STATUS_DOCKED);
	OO_CHECK_EVAL("(function () { player.ship.targetSystem = 33; })()", "undefined");
	OO_CHECK_LOG(sPlayer->_log, "setTargetSystemID 33");
	sPlayer->Entity::setStatus(STATUS_IN_FLIGHT);
	OO_CHECK(Eval("(function () { player.ship.targetSystem = 33; })()").rfind("threw: ", 0) == 0);
	sPlayer->Entity::setStatus(STATUS_ENTERING_WITCHSPACE);
	OO_CHECK(Eval("(function () { player.ship.targetSystem = 33; })()").rfind("threw: ", 0) == 0);
	OO_CHECK_LOG(sPlayer->_log, "");
	sPlayer->Entity::setStatus(STATUS_DOCKED);
}


OO_TEST(slice2Methods)
{
	SetUp();
	Log(sPlayer->_log);
	OO_CHECK_EVAL("player.ship.launch()", "undefined");
	OO_CHECK_EVAL("player.ship.disengageAutopilot()", "undefined");
	OO_CHECK_EVAL("player.ship.removeAllCargo()", "undefined");
	OO_CHECK_EVAL("player.ship.useSpecialCargo('Rocks')", "undefined");
	OO_CHECK_LOG(sPlayer->_log, "launchFromStation; disengageAutopilot; removeAllCargo; useSpecialCargo Rocks");
	sPlayer->_docked = NO;
	OO_CHECK_EVAL("player.ship.removeAllCargo()", "threw: PlayerShip.removeAllCargo only works when docked.");
	sPlayer->_docked = YES;
	OO_CHECK(Eval("player.ship.useSpecialCargo()").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("player.ship.engageAutopilotToStation(player.ship.dockedStation)").rfind("threw: ", 0) == 0);	// not a station
	OO_CHECK(Eval("player.ship.requestDockingClearance()").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("player.ship.cancelDockingRequest(5)").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("player.ship.awardEquipmentToCurrentPylon('EQ_NO_SUCH_THING')").rfind("threw: ", 0) == 0);
	OO_CHECK_LOG(sPlayer->_log, "");
}


// Slice 3 (bead oo-1qr5): the custom views, scanner zoom, internal damage, the hyperspace
// countdowns, the MFDs, primed equipment, the HUD dials and selectors.
OO_TEST(customViews)
{
	SetUp();
	Log(sPlayer->_log);
	OO_CHECK_EVAL("player.ship.setCustomView([1, 2, 3], [1, 0, 0, 0])", "threw: PlayerShip.setCustomView only works when custom view is active.");
	OO_CHECK_EVAL("player.ship.resetCustomView()", "threw: PlayerShip.setCustomView only works when custom view is active.");
	sUniverse->_viewDirection = VIEW_CUSTOM;
	OO_CHECK_EVAL("player.ship.setCustomView([1, 2, 3], [1, 0, 0, 0])", "true");
	OO_CHECK_EVAL("player.ship.setCustomView([1, 2, 3], [1, 0, 0, 0], 'WEAPON_FACING_AFT')", "true");
	OO_CHECK_EVAL("player.ship.resetCustomView()", "true");
	OO_CHECK_LOG(sPlayer->_log, oo::str::format("setCustomViewData {\"view_orientation\" = \"1.000000 0.000000 0.000000 0.000000\"; \"view_position\" = \"1.000000 2.000000 3.000000\"; } 0; noteSwitchToView %d %d; "
													 "setCustomViewData {\"view_orientation\" = \"1.000000 0.000000 0.000000 0.000000\"; \"view_position\" = \"1.000000 2.000000 3.000000\"; \"weapon_facing\" = \"WEAPON_FACING_AFT\"; } 0; noteSwitchToView %d %d; "
													 "resetCustomView; noteSwitchToView %d %d",
													 static_cast<int>(VIEW_CUSTOM), static_cast<int>(VIEW_CUSTOM), static_cast<int>(VIEW_CUSTOM), static_cast<int>(VIEW_CUSTOM), static_cast<int>(VIEW_CUSTOM), static_cast<int>(VIEW_CUSTOM)));
	OO_CHECK(Eval("player.ship.setCustomView([1, 2, 3])").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("player.ship.setCustomView('here', [1, 0, 0, 0])").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("player.ship.setCustomView([1, 2, 3], 'up')").rfind("threw: ", 0) == 0);
	OO_CHECK_EVAL("player.ship.setCustomView([1, 2, 3], [1, 0, 0, 0], null)", "threw: Native exception: Tried to add nil value for key 'weapon_facing' to dictionary");
	OO_CHECK_LOG(sPlayer->_log, "");
	sUniverse->_viewDirection = VIEW_AFT;

	OO_CHECK_EVAL("player.ship.resetScannerZoom()", "undefined");
	OO_CHECK_EVAL("player.ship.takeInternalDamage()", "true");
	OO_CHECK_LOG(sPlayer->_log, "resetScannerZoom; takeInternalDamage");
}


OO_TEST(hyperspaceCountdowns)
{
	SetUp();
	Log(sPlayer->_log);
	sPlayer->_hyperspaceMotor = NO;
	OO_CHECK_EVAL("player.ship.beginHyperspaceCountdown()", "false");
	OO_CHECK_EVAL("player.ship.cancelHyperspaceCountdown()", "false");
	sPlayer->_hyperspaceMotor = YES;
	sPlayer->Entity::setStatus(STATUS_IN_FLIGHT);
	OO_CHECK_EVAL("player.ship.beginHyperspaceCountdown(10)", "true");
	OO_CHECK_EVAL("player.ship.beginHyperspaceCountdown()", "true");
	OO_CHECK_LOG(sPlayer->_log, "witchJumpChecklist 0; beginWitchspaceCountdown 10; witchJumpChecklist 0; beginWitchspaceCountdown 0");
	OO_CHECK(Eval("player.ship.beginHyperspaceCountdown(4)").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("player.ship.beginHyperspaceCountdown(61)").rfind("threw: ", 0) == 0);
	OO_CHECK_EVAL("player.ship.cancelHyperspaceCountdown()", "false");	// not counting down
	sPlayer->Entity::setStatus(STATUS_WITCHSPACE_COUNTDOWN);
	OO_CHECK_EVAL("player.ship.cancelHyperspaceCountdown()", "true");
	OO_CHECK_LOG(sPlayer->_log, "cancelWitchspaceCountdown; setJumpType 0");

	// Galactic: needs the drive, in flight.
	sPlayer->Entity::setStatus(STATUS_IN_FLIGHT);
	OO_CHECK_EVAL("player.ship.beginGalacticHyperspaceCountdown()", "false");
	sPlayer->_equipment.insert("EQ_GAL_DRIVE");
	Log(sUniverse->_messages);
	OO_CHECK_EVAL("player.ship.beginGalacticHyperspaceCountdown(20)", "true");
	OO_CHECK_LOG(sPlayer->_log, oo::str::format("witchJumpChecklist 1; setJumpType 1; setWitchspaceCountdown 20; setStatus %d; playGalacticHyperspace", static_cast<int>(STATUS_WITCHSPACE_COUNTDOWN)));
	OO_CHECK_LOG(sUniverse->_messages, "witch-galactic-in-f-seconds 1");
	OO_CHECK(Eval("player.ship.beginGalacticHyperspaceCountdown(3)").rfind("threw: ", 0) == 0);
	sPlayer->_equipment.clear();
	sPlayer->Entity::setStatus(STATUS_DOCKED);
}


OO_TEST(mfdsAndDials)
{
	SetUp();
	Log(sPlayer->_log);
	OO_CHECK_EVAL("player.ship.setMultiFunctionDisplay(1, 'mfd-x')", "true");
	OO_CHECK_EVAL("player.ship.setMultiFunctionDisplay(5)", "false");
	OO_CHECK_EVAL("player.ship.setMultiFunctionDisplay()", "true");
	OO_CHECK(Eval("player.ship.setMultiFunctionDisplay(-1)").rfind("<", 0) != 0);
	Log(sPlayer->_log);
	OO_CHECK_EVAL("player.ship.setMultiFunctionText('mfd-x', 'Hello')", "undefined");
	OO_CHECK_EVAL("player.ship.setMultiFunctionText('mfd-x')", "undefined");
	OO_CHECK_EVAL("player.ship.setMultiFunctionText('mfd-x', 'Hello', true)", "undefined");
	OO_CHECK_LOG(sPlayer->_log, "setMultiFunctionText mfd-x Hello; setMultiFunctionText mfd-x (nil); setMultiFunctionText mfd-x [reflowed Hello]");
	OO_CHECK(Eval("player.ship.setMultiFunctionText()").rfind("threw: ", 0) == 0);

	OO_CHECK_EVAL("player.ship.setPrimedEquipment('EQ_ECM')", "true");
	OO_CHECK_EVAL("player.ship.setPrimedEquipment('EQ_NONE_SUCH', false)", "false");
	OO_CHECK_LOG(sPlayer->_log, "setPrimedEquipment EQ_ECM 1; setPrimedEquipment EQ_NONE_SUCH 0");
	OO_CHECK(Eval("player.ship.setPrimedEquipment()").rfind("threw: ", 0) == 0);

	OO_CHECK_EVAL("player.ship.setCustomHUDDial('dial', 5)", "undefined");
	OO_CHECK_EVAL("player.ship.setCustomHUDDial('dial')", "undefined");
	OO_CHECK_LOG(sPlayer->_log, "setDialCustom dial 5; setDialCustom dial ");
	OO_CHECK(Eval("player.ship.setCustomHUDDial()").rfind("threw: ", 0) == 0);

	// The HUD's selectors.
	OO_CHECK_EVAL("player.ship.hideHUDSelector('drawCompass:')", "undefined");
	OO_CHECK(sPlayer->_hud->hasHidden(std::string("drawCompass:")));
	OO_CHECK_EVAL("player.ship.showHUDSelector('drawCompass:')", "undefined");
	OO_CHECK(!sPlayer->_hud->hasHidden(std::string("drawCompass:")));
	OO_CHECK(Eval("player.ship.hideHUDSelector()").rfind("threw: ", 0) == 0);
	OO_CHECK(Eval("player.ship.showHUDSelector()").rfind("threw: ", 0) == 0);
	oo::Ref<HeadUpDisplay> hud = sPlayer->_hud;
	sPlayer->_hud = nullptr;
	OO_CHECK_EVAL("player.ship.hideHUDSelector('drawCompass:')", "undefined");	// no HUD: nothing
	sPlayer->_hud = hud;
	OO_CHECK_LOG(sPlayer->_log, "");
}


// What the engine asks of the player (the category on the Objective-C PlayerEntity until bead
// oo-9ht.177 deleted it; now the ship's facade, which asks the C++ player): the class name, and the
// JS object.
OO_TEST(playerCategory)
{
	SetUp();
	OO_CHECK_EQ(OOJSEntityJSClassName(sRealPlayer).value_or("<none>"), "PlayerShip");
	OO_CHECK(sRealPlayer->_jsSelf == JSPlayerShipObject());
	ooscript::Context context = OOJSAcquireContext();
	OO_CHECK(ooscript::isObject(OOJSEntityJSValue(sRealPlayer, context)) && ooscript::toObject(OOJSEntityJSValue(sRealPlayer, context)) == JSPlayerShipObject());
	OOJSRelinquishContext(context);

	// The engine's reset drops the player's JS object.
	oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineWillResetNotificationName, OOJavaScriptEngine::sharedEngine());
	OO_CHECK(sRealPlayer->_jsSelf == nullptr);
	context = OOJSAcquireContext();
	OOJSPlayerShipSetJSSelf(sRealPlayer, JSPlayerShipObject(), context);	// as InitOOJSPlayerShip() did
	OOJSRelinquishContext(context);
	OO_CHECK(sRealPlayer->_jsSelf == JSPlayerShipObject());
}


OO_TEST(cleanUp)
{
	stdfs::current_path(stdfs::temp_directory_path());
	std::error_code ignored;
	stdfs::remove_all(sRoot, ignored);
	OO_CHECK(true);
}


OO_TEST_MAIN()
