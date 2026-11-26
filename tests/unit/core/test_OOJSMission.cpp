/*	test_OOJSMission.mm
	Unit tests for the mission JS binding (src/Core/Scripting/OOJSMission.h/.mm).

	As the other binding tests do, it runs the JS class in a real QuickJS-ng context, and links the
	game's own objects for the binding, the engine's class registry (OOJSClasses.mm), its exception
	translator (OOJSEngineNativeWrappers.mm) and the constant strings (OOConstToJSString.cpp). It
	stands in for the player (PlayerEntity records what the binding tells it), the universe and its
	GUI, a demo ship, the running script and the script engine (OOScript and OOJavaScriptEngine,
	which call the mission screen's callback), the music controller (a converted class the binding
	only calls, stood in for by C++ members), the string expander, the standards switches and the
	engine functions the binding links against, with the engine headers' linkage; the log is
	captured with oo::log::logger().setSink. The tests pin the JS-visible behaviour: the mission object and its
	properties, markSystem()/unmarkSystem() with numbers and markers, addMessageText(),
	setInstructions()/setInstructionsKey() in each form, runScreen() (its settings, its errors, and
	the callback MissionRunCallback() makes, including an exception in it, which is logged and
	ignored), runShipLibrary(), and a native's exception. Run: bash tools/check-core-tests.sh
*/

#include "OOFoundation.h"
#include "OOMaths.h"
#include "OOTypes.h"
#include "OOEntityEnums.h"
#include <quickjs.h>
#include "oofnd/objc/OOException.h"
#include "oofnd/Log.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#include "OOConstToJSString.h"
#include "OOStringExpander.h"


// MARK: The classes, as far as the binding sees them ----------------------------------------------

typedef NSInteger OOGUIRow;	// as GuiDisplayGen.h declares it

// The demo ship's object (the root's), which TestObjectOf answers for the demo
// ship. Its selector is a member of the same name.
class TestEntityObject final : public oo::RefCounted
{
public:
	JSValue oo_jsValueInContext(JSContext *context);	// owned by the caller

	JSValue _jsSelf = JS_UNDEFINED;	// owned; not an object until made
};


/*	The player: it records what it is told, as "selector(arguments)" lines.
   While _raise is set, -cxx_missionScreenID raises, and while _throwCxx is set
   it throws a C++ exception, so the test sees what an exception under a native
   becomes.
*/
// PLAYER: the members the code under test calls, declared as the game headers
// declare them (the test imports none that defines the classes), with the
// stand-in's answers.
#include "oofnd/Ref.hpp"
#include "OOJSPrivateObject.h"

class Entity : public oo::RefCounted, public OOJSPrivateObject	// the game's root's bases (its JS glue)
{
public:
	OOEntityStatus status();
	JSValue jsValueInContext(JSContext *context) override;
	void clearJSSelf(JSValueConst selfVal) override;
};

// The ship (the demo ship is a plain one).
class ShipEntity : public Entity
{
public:
	void setEntityPersonalityInt(uint16_t value);

	uint16_t _personality = {};
};

class PlayerEntity : public ShipEntity
{
public:
	void setScriptTarget(::ShipEntity *ship);
	oo::PList getMissionDestinations();
	std::optional<std::string> missionScreenID();
	OOGUIScreenID missionExitScreen();
	void setMissionExitScreen(OOGUIScreenID screen);
	void addMissionDestinationMarker(const oo::PList &marker);
	oo::PList defaultMarker(OOSystemID system);
	bool removeMissionDestinationMarker(const oo::PList &marker);
	void addLiteralMissionText(const std::string &text);
	void setMissionDescription(const std::string &textKey, const std::optional<std::string> &key);
	void setMissionInstructions(const std::string &text, const std::optional<std::string> &key);
	void setMissionInstructionsList(const oo::PList &list, const std::optional<std::string> &key);
	void clearMissionDescriptionForMission(const std::string &key);
	void setMissionTitle(const std::optional<std::string> &value);
	void setMissionOverlayDescriptor(const oo::PList &descriptor);
	void setMissionBackgroundDescriptor(const oo::PList &descriptor);
	void setMissionBackgroundSpecial(const std::string &special);
	void setCustomChartZoom(OOScalar zoom);
	void setCustomChartCentre(NSPoint coords);
	NSPoint getGalaxy_coordinates();
	void setMissionScreenID(const std::optional<std::string> &msid);
	void clearMissionScreenID();
	void clearExtraMissionKeys();
	void setExtraMissionKeys(const oo::PList &keys);
	void setMissionChoiceByTextEntry(bool enable);
	void setGuiToMissionScreenWithCallback(bool callback);
	void allowMissionInterrupt();
	void addMissionText(const std::string &textKey);
	void setMissionChoices(const std::string &choicesKey);
	void setMissionChoicesDictionary(const oo::PList &choicesDict);
	void setMissionMusic(const std::string &value);
	void setGuiToIntroFirstGo(bool justCobra);
	oo::PList missionChoice_string();
	oo::PList missionKeyPress_string();
	void setMissionChoice(const std::optional<std::string> &newChoice, const std::optional<std::string> &keyPress, bool withEvent);

	std::vector<std::string> _calls;
	OOEntityStatus _status = {};
	oo::PList::Dict _destinations;
	std::optional<std::string> _screenID;
	OOGUIScreenID _exitScreen = {};
	oo::PList _choice;
	oo::PList _keyPress;
	BOOL _removeFails = {};
	BOOL _raise = {};
	BOOL _throwCxx = {};
};


// The GUI: the members the binding calls are defined below (a C++ stand-in
// with the facade stand-in's answers), recording into sGuiCalls.
#include "GuiDisplayGen.h"
#include "OOTextureSprite.h"	// the stand-in's destructor destroys the GUI's sprite members
#include "OOColor.h"	// and its row colours


#include "UniverseStandIn.h"

// The universe as the code under test sees it: a stand-in for the C++ class
// with the header's names and signatures. It answers virtual members, so it has
// the game's vtable (UniverseStandIn.h) and StandInUniverse overrides them.
class Universe : public oo::RefCounted
{
public:
	OO_UNIVERSE_STAND_IN_VIRTUAL_MEMBERS

	GuiDisplayGen *_gui;
	ShipEntity *_demoShip;
	std::vector<std::string> _calls;

	oo::PList getMissiontext();
	void removeDemoShips();
	::ShipEntity *makeDemoShipWithRole(const std::string &, bool);
};

class StandInUniverse : public Universe
{
public:
	::GuiDisplayGen *getGui() override	{ return _gui; }
};




/*	The engine calls the mission screen's callback. While _raise is set it raises instead, as a
	script error could, which MissionRunCallback() logs and ignores.
*/
class OOJavaScriptEngine	// the header's names and signatures
{
public:
	static OOJavaScriptEngine *sharedEngine();
	bool callJSFunction(JSValueConst function, JSValueConst jsThis, int argc, JSValueConst *argv, JSValue *outResult);

	int _calls = 0;
	BOOL _raise = NO;
};


// The music controller, a converted class the binding only calls: the members
// the binding calls are defined below.
#include "OOMusicController.h"


#include "OOJSEngineCore.h"
#include "OOJSMission.h"

#include "oo_test.hpp"

#include <cmath>
#include <cstdarg>
#include <cstdint>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>


class OOJSScript;

namespace {

std::vector<std::string> sMusic;			// what the music controller was told
std::vector<std::string> sScriptStack;		// pushScript:/popScript:, as "+name"/"-name"
std::vector<std::string> sLog;
OOJSScript *sRunningScript = nullptr;
JSContext *sContext = nullptr;


std::string Describe(const oo::PList &plist)
{
	if (plist.isNull())  return "null";
	if (const std::string *str = plist.getIf<std::string>())  return "'" + *str + "'";
	if (const bool *boolean = plist.getIf<bool>())  return *boolean ? "true" : "false";
	if (plist.isNumber())  return oo::str::format("%g", plist.doubleValue());
	if (const oo::PList::Array *array = plist.getIf<oo::PList::Array>())
	{
		std::string result = "[";
		for (const oo::PList &element : *array)  result += (result.size() > 1 ? "," : "") + Describe(element);
		return result + "]";
	}
	if (const oo::PList::Dict *dict = plist.getIf<oo::PList::Dict>())
	{
		std::string result = "{";
		for (const auto &[key, value] : *dict)  result += (result.size() > 1 ? "," : "") + key + ":" + Describe(value);
		return result + "}";
	}
	return "?";
}


std::string Optional(const std::optional<std::string> &string)
{
	return string.has_value() ? "'" + *string + "'" : "nullopt";
}


oo::PList Dict(std::initializer_list<std::pair<const char *, oo::PList>> entries)
{
	oo::PList::Dict dict;
	for (const auto &[key, value] : entries)  dict[key] = value;
	return oo::PList(std::move(dict));
}


std::string Take(std::vector<std::string> &calls)
{
	std::string result;
	for (const std::string &call : calls)  result += (result.empty() ? "" : "; ") + call;
	calls.clear();
	return result;
}


void CaptureLog(std::string_view line)
{
	sLog.emplace_back(line);
}

}	// namespace


JSValue TestEntityObject::oo_jsValueInContext(JSContext *context)
{
	if (!JS_IsObject(_jsSelf))
	{
		_jsSelf = JS_NewObject(context);
		JS_SetPropertyStr(context, _jsSelf, "name", JS_NewString(context, "demo ship"));
	}
	return JS_DupValue(context, _jsSelf);
}


void PlayerEntity::setScriptTarget(::ShipEntity *ship)  { (void)ship; }
void ShipEntity::setEntityPersonalityInt(uint16_t value)  { _personality = value; }
OOEntityStatus Entity::status()  { return static_cast<PlayerEntity *>(this)->_status; }
oo::PList PlayerEntity::getMissionDestinations()  { return oo::PList(_destinations); }
std::optional<std::string> PlayerEntity::missionScreenID()
{
	if (_raise)  OORaiseException(OOInvalidArgumentException, "screen %s", "boom");
	if (_throwCxx)  throw std::runtime_error("cxx boom");
	return _screenID;
}
OOGUIScreenID PlayerEntity::missionExitScreen()  { return _exitScreen; }
void PlayerEntity::setMissionExitScreen(OOGUIScreenID screen)
{
	_exitScreen = screen; _calls.push_back(oo::str::format("exitScreen(%d)", static_cast<int>(screen)));
}
void PlayerEntity::addMissionDestinationMarker(const oo::PList &marker)
{
	_calls.push_back("addMarker(" + Describe(marker) + ")");
	_destinations[oo::str::format("%d", marker.get<int>("system", -1))] = marker;
}
oo::PList PlayerEntity::defaultMarker(OOSystemID system)
{
	return Dict({ { "system", oo::PList(static_cast<int>(system)) }, { "name", oo::PList("default") } });
}
bool PlayerEntity::removeMissionDestinationMarker(const oo::PList &marker)
{
	_calls.push_back("removeMarker(" + Describe(marker) + ")");
	_destinations.erase(oo::str::format("%d", marker.get<int>("system", -1)));
	return !_removeFails;
}
void PlayerEntity::addLiteralMissionText(const std::string &text)  { _calls.push_back("literalText('" + text + "')"); }
void PlayerEntity::setMissionDescription(const std::string &textKey, const std::optional<std::string> &key)
{
	_calls.push_back("description('" + textKey + "', " + Optional(key) + ")");
}
void PlayerEntity::setMissionInstructions(const std::string &text, const std::optional<std::string> &key)
{
	_calls.push_back("instructions('" + text + "', " + Optional(key) + ")");
}
void PlayerEntity::setMissionInstructionsList(const oo::PList &list, const std::optional<std::string> &key)
{
	_calls.push_back("instructionsList(" + Describe(list) + ", " + Optional(key) + ")");
}
void PlayerEntity::clearMissionDescriptionForMission(const std::string &key)  { _calls.push_back("clearDescription('" + key + "')"); }
void PlayerEntity::setMissionTitle(const std::optional<std::string> &value)  { _calls.push_back("title(" + Optional(value) + ")"); }
void PlayerEntity::setMissionOverlayDescriptor(const oo::PList &descriptor)  { _calls.push_back("overlay(" + Describe(descriptor) + ")"); }
void PlayerEntity::setMissionBackgroundDescriptor(const oo::PList &descriptor)
{
	_calls.push_back("background(" + Describe(descriptor) + ")");
}
void PlayerEntity::setMissionBackgroundSpecial(const std::string &special)  { _calls.push_back("backgroundSpecial('" + special + "')"); }
void PlayerEntity::setCustomChartZoom(OOScalar zoom)
{
	_calls.push_back(oo::str::format("chartZoom(%g)", static_cast<double>(zoom)));
}
void PlayerEntity::setCustomChartCentre(NSPoint coords)
{
	_calls.push_back(oo::str::format("chartCentre(%g, %g)", static_cast<double>(coords.x), static_cast<double>(coords.y)));
}
NSPoint PlayerEntity::getGalaxy_coordinates()  { return NSMakePoint(10, 20); }
void PlayerEntity::setMissionScreenID(const std::optional<std::string> &msid)  { _calls.push_back("screenID(" + Optional(msid) + ")"); }
void PlayerEntity::clearMissionScreenID()  { _calls.push_back("clearScreenID"); }
void PlayerEntity::clearExtraMissionKeys()  { _calls.push_back("clearExtraKeys"); }
void PlayerEntity::setExtraMissionKeys(const oo::PList &keys)  { _calls.push_back("extraKeys(" + Describe(keys) + ")"); }
void PlayerEntity::setMissionChoiceByTextEntry(bool enable)
{
	_calls.push_back(enable ? "textEntry(YES)" : "textEntry(NO)");
}
void PlayerEntity::setGuiToMissionScreenWithCallback(bool callback)
{
	_calls.push_back(callback ? "missionScreen(YES)" : "missionScreen(NO)");
}
void PlayerEntity::allowMissionInterrupt()  { _calls.push_back("allowInterrupt"); }
void PlayerEntity::addMissionText(const std::string &textKey)  { _calls.push_back("text('" + textKey + "')"); }
void PlayerEntity::setMissionChoices(const std::string &choicesKey)  { _calls.push_back("choices('" + choicesKey + "')"); }
void PlayerEntity::setMissionChoicesDictionary(const oo::PList &choicesDict)
{
	_calls.push_back("choicesDict(" + Describe(choicesDict) + ")");
}
void PlayerEntity::setMissionMusic(const std::string &value)  { _calls.push_back("missionMusic('" + value + "')"); }
void PlayerEntity::setGuiToIntroFirstGo(bool justCobra)
{
	_calls.push_back(justCobra ? "introFirstGo(YES)" : "introFirstGo(NO)");
}
oo::PList PlayerEntity::missionChoice_string()  { return _choice; }
oo::PList PlayerEntity::missionKeyPress_string()  { return _keyPress; }
void PlayerEntity::setMissionChoice(const std::optional<std::string> &newChoice, const std::optional<std::string> &keyPress, bool withEvent)
{
	_calls.push_back("choice(" + Optional(newChoice) + ", " + Optional(keyPress) + (withEvent ? ", YES)" : ", NO)"));
}


namespace {
std::vector<std::string> sGuiCalls;	// the facade stand-in's _calls
}

GuiDisplayGen::GuiDisplayGen() {}
GuiDisplayGen::~GuiDisplayGen() {}

oo::PList GuiDisplayGen::textureDescriptorFromJSValue(JSValue value, JSContext *context, const std::optional<std::string> &callerDescription)
{
	sGuiCalls.push_back("texture(" + Optional(callerDescription) + ")");
	if (JS_IsNull(value) || JS_IsUndefined(value))  return oo::PList();
	const char *chars = JS_ToCString(context, value);
	std::string name = chars != nullptr ? chars : "";
	JS_FreeCString(context, chars);
	return Dict({ { "name", oo::PList(name) } });
}

OOGUIRow GuiDisplayGen::rowForKey(const std::optional<std::string> &key)
{
	sGuiCalls.push_back("rowForKey(" + Optional(key) + ")");
	return key == std::optional<std::string>("2_NO") ? 7 : -1;
}

bool GuiDisplayGen::setSelectedRow(OOGUIRow row)
{
	sGuiCalls.push_back(oo::str::format("selectRow(%ld)", static_cast<long>(row)));
	return true;
}

// The GUI's virtual members the binding does not call (its vtable needs them): never run.
void GuiDisplayGen::setTitle(const std::optional<std::string> &)  { std::abort(); }
OOColor *GuiDisplayGen::getTextColor()  { std::abort(); }
void GuiDisplayGen::setTextColor(OOColor *)  { std::abort(); }
OOColor *GuiDisplayGen::getTextCommsColor()  { std::abort(); }
void GuiDisplayGen::setTextCommsColor(OOColor *)  { std::abort(); }
void GuiDisplayGen::setColor(OOColor *, OOGUIRow)  { std::abort(); }
OOGUIRow GuiDisplayGen::getSelectedRow()  { std::abort(); }
void GuiDisplayGen::setSelectableRange(NSRange)  { std::abort(); }
void GuiDisplayGen::setTabStops(OOGUITabSettings)  { std::abort(); }
void GuiDisplayGen::clearAndKeepBackground(bool)  { std::abort(); }
void GuiDisplayGen::setKey(const std::string &, OOGUIRow)  { std::abort(); }
void GuiDisplayGen::setText(const std::string &, OOGUIRow)  { std::abort(); }
void GuiDisplayGen::setText(const std::optional<std::string> &, OOGUIRow, OOGUIAlignment)  { std::abort(); }
std::optional<std::string> GuiDisplayGen::reflowTextForMFD(const std::optional<std::string> &)  { std::abort(); }
OOGUIRow GuiDisplayGen::addLongText(const std::optional<std::string> &, OOGUIRow, OOGUIAlignment)  { std::abort(); }
void GuiDisplayGen::setArray(const std::vector<std::string> &, OOGUIRow)  { std::abort(); }


// The demo ship's object, which TestObjectOf answers (only the demo ship
// crosses).
::TestEntityObject *sDemoShipObject = nullptr;
::TestEntityObject *TestObjectOf(Entity *entity)  { return entity != nullptr ? sDemoShipObject : nullptr; }
// The C++ ship's JS value (displayModel is OOJSValueFromCxxObject of the demo
// ship): its object's.
JSValue Entity::jsValueInContext(JSContext *context)  { ::TestEntityObject *object = TestObjectOf(this); return object != nullptr ? object->oo_jsValueInContext(context) : JS_NULL; }
void Entity::clearJSSelf(JSValueConst)  {}


oo::PList Universe::getMissiontext()	{ return Dict({ { "mission_title", oo::PList("The [name] Job") }, { "mission_number", oo::PList(12) } }); }
void Universe::removeDemoShips()	{ _calls.push_back("removeDemoShips"); }
::ShipEntity *Universe::makeDemoShipWithRole(const std::string &role, bool spinning)
{
	_calls.push_back("demoShip('" + role + "', " + (spinning ? "YES)" : "NO)"));
	return role == "none" ? nil : _demoShip;
}


#include "OOScript.h"


// OOJSScript (OOJSScript.h), which the code under test calls. A script is a
// C++ object, so the stand-in is a C++ subclass of OOScript declaring the
// members that code calls.
class OOJSScript : public OOScript
{
public:
	static OOJSScript *currentlyRunningScript();
	static void pushScript(OOJSScript *script);
	static void popScript(OOJSScript *script);

	std::optional<std::string> name() override  { return _name; }

	std::optional<std::string> _name;
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

OOJSScript *OOJSScript::currentlyRunningScript()  { return sRunningScript; }
void OOJSScript::pushScript(OOJSScript *script)  { sScriptStack.push_back("+" + (script != nullptr ? script->_name.value_or("?") : std::string("nil"))); }
void OOJSScript::popScript(OOJSScript *script)  { sScriptStack.push_back("-" + (script != nullptr ? script->_name.value_or("?") : std::string("nil"))); }


namespace {
OOJavaScriptEngine *sEngine = nullptr;
}

OOJavaScriptEngine *OOJavaScriptEngine::sharedEngine()  { return sEngine; }

bool OOJavaScriptEngine::callJSFunction(JSValueConst function, JSValueConst jsThis, int argc, JSValueConst *argv, JSValue *outResult)
{
	_calls++;
	if (_raise)  OORaiseException(OOInvalidArgumentException, "callback %s", "boom");
	JSValue result = JS_Call(sContext, function, jsThis, argc, argv);
	if (JS_IsException(result))
	{
		JS_FreeValue(sContext, JS_GetException(sContext));	// the engine reports and clears it
		if (outResult != nullptr)  *outResult = JS_UNDEFINED;
		return NO;
	}
	if (outResult != nullptr)  *outResult = result;
	else  JS_FreeValue(sContext, result);
	return YES;
}


OOMusicController::OOMusicController()
{
}


OOMusicController *OOMusicController::sharedController()
{
	static OOMusicController *shared = new OOMusicController();	// never released, as the game's
	return shared;
}


void OOMusicController::setMissionMusic(const std::optional<std::string> &missionMusicName)
{
	sMusic.push_back(Optional(missionMusicName));
}


// MARK: What the rest of the engine provides ------------------------------------------------------

const char *const cxx_kOOLogException = "exception";


// The expander: "<string>".
std::optional<std::string> cxx_OOExpandDescriptionString(Random_Seed, const std::string &string, const oo::PList &, const oo::PList &, const std::optional<std::string> &, OOExpandOptions)
{
	return "<" + string + ">";
}

Random_Seed OOStringExpanderDefaultRandomSeed(void)
{
	return Random_Seed{};
}


namespace {
int sDeprecations = 0;
bool sEnforceStandards = false;
std::string sLastWarning;
std::vector<std::string> sWarnings;
}  // namespace

void cxx_OOStandardsDeprecated(const std::string &message)
{
	(void)message;
	sDeprecations++;
}

extern "C" bool OOEnforceStandards(void)
{
	return sEnforceStandards;
}


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


void cxx_OOJSReportWarning(JSContext *, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	sLastWarning = oo::str::vformat(format, args);
	va_end(args);
	sWarnings.push_back(sLastWarning);
}


void cxx_OOJSReportBadArguments(JSContext *context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, int argc, JSValueConst *, const std::optional<std::string> &message, const std::optional<std::string> &expectedArgsDescription)
{
	cxx_OOJSReportError(context, "bad arguments: %s.%s(%d) %s / %s", scriptClass.value_or("-").c_str(), function.value_or("-").c_str(), argc, message.value_or("-").c_str(), expectedArgsDescription.value_or("-").c_str());
}


// As the engine's: the pending exception is reported (here, dropped) and cleared.
void OOJSReportPendingException(JSContext *context)
{
	JS_FreeValue(context, JS_GetException(context));
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


std::optional<std::string> cxx_OOStringFromJSValueEvenIfNull(JSContext *context, JSValueConst value)
{
	if (JS_IsNull(value))  return "null";
	if (JS_IsUndefined(value))  return "undefined";
	return cxx_OOStringFromJSValue(context, value);
}


oo::PList cxx_OOJSPListFromJSValue(JSContext *context, JSValueConst value);

oo::PList cxx_OOJSPListFromJSObject(JSContext *context, JSValueConst object)
{
	if (!JS_IsObject(object))  return oo::PList();
	if (JS_IsArray(object))
	{
		std::int64_t length = 0;
		JS_GetLength(context, object, &length);
		oo::PList::Array array;
		for (std::int64_t i = 0; i < length; i++)
		{
			JSValue element = JS_GetPropertyUint32(context, object, static_cast<std::uint32_t>(i));
			array.push_back(cxx_OOJSPListFromJSValue(context, element));
			JS_FreeValue(context, element);
		}
		return oo::PList(std::move(array));
	}
	// An object's own enumerable properties, in the order Object.keys() gives them.
	oo::PList::Dict dict;
	JSPropertyEnum *properties = nullptr;
	uint32_t count = 0;
	if (JS_GetOwnPropertyNames(context, &properties, &count, object, JS_GPN_STRING_MASK | JS_GPN_ENUM_ONLY) == 0)
	{
		for (uint32_t i = 0; i < count; i++)
		{
			const char *key = JS_AtomToCString(context, properties[i].atom);
			JSValue element = JS_GetProperty(context, object, properties[i].atom);
			dict[key != nullptr ? key : ""] = cxx_OOJSPListFromJSValue(context, element);
			JS_FreeValue(context, element);
			JS_FreeCString(context, key);
		}
		JS_FreePropertyEnum(context, properties, count);
	}
	return oo::PList(std::move(dict));
}


oo::PList cxx_OOJSPListFromJSValue(JSContext *context, JSValueConst value)
{
	if (JS_IsNull(value) || JS_IsUndefined(value))  return oo::PList();
	if (JS_IsString(value))  return oo::PList(cxx_OOStringFromJSValue(context, value).value_or(std::string()));
	if (JS_IsBool(value))  return oo::PList(JS_ToBool(context, value) > 0);
	if (JS_IsNumber(value))
	{
		double number = 0;
		JS_ToFloat64(context, &number, value);
		return oo::PList(number);
	}
	if (JS_IsObject(value))  return cxx_OOJSPListFromJSObject(context, value);
	return oo::PList();
}


// A property list as JavaScript (owned), as far as the binding hands one over: null, a string, a
// number, or an array or dictionary of those.
JSValue OOJSValueFromPList(JSContext *context, const oo::PList &plist)
{
	if (const std::string *str = plist.getIf<std::string>())  return JS_NewStringLen(context, str->data(), str->size());
	if (plist.isNumber())  return JS_NewNumber(context, plist.doubleValue());
	if (const oo::PList::Array *array = plist.getIf<oo::PList::Array>())
	{
		JSValue object = JS_NewArray(context);
		std::uint32_t index = 0;
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


// The internal chart coordinates of a galactic position: (x * 4, y * 2) here.
extern "C" NSPoint OOInternalCoordinatesFromGalactic(Vector galacticCoordinates)
{
	return NSMakePoint(galacticCoordinates.x * 4, galacticCoordinates.y * 2);
}


namespace {
JSValue sScriptObject = JS_UNDEFINED;	// held for the life of the test
}

PlayerEntity *gOOPlayer = nullptr;
Universe *gSharedUniverse = nil;
JSContext *gOOJSMainThreadContext = nullptr;
// The engine's reset notification, which the binding observes (never posted).
extern const char * const kOOJavaScriptEngineWillResetNotificationName;
const char * const kOOJavaScriptEngineWillResetNotificationName = "org.aegidian.oolite OOJavaScriptEngine will reset";


// Property IDs (OOJSID(), and those OOJSClasses.mm records): interned for the life of the process,
// as the engine's.
JSAtom OOJSInternAtomPRIVATE(const char *name)
{
	return JS_NewAtom(gOOJSMainThreadContext, name);
}


JSAtom cxx_OOJSIDFromString(const std::string &string)
{
	return JS_NewAtomLen(gOOJSMainThreadContext, string.data(), string.size());
}


// The engine's: rounded to nearest; NaN or out of range is an error.
BOOL OOJSValueToInt32(JSContext *context, JSValueConst value, int32_t *outValue)
{
	double number;
	if (JS_ToFloat64(context, &number, value) < 0)  return NO;
	number = std::floor(number + 0.5);
	if (std::isnan(number) || number < INT32_MIN || number > INT32_MAX)
	{
		cxx_OOJSReportError(context, "can't convert %s to an integer", cxx_OOStringFromJSValueEvenIfNull(context, value).value_or("(null)").c_str());
		return NO;
	}
	*outValue = static_cast<int32_t>(number);
	return YES;
}


PlayerEntity *OOPlayerForScripting(void)
{
	return gOOPlayer;
}


// A vector is the array [x, y, z] here.
bool JSValueToVector(JSContext *context, JSValueConst value, Vector *outVector)
{
	if (!JS_IsArray(value))  return false;
	double v[3] = {};
	for (std::uint32_t i = 0; i < 3; i++)
	{
		JSValue element = JS_GetPropertyUint32(context, value, i);
		const bool ok = !JS_IsException(element) && JS_ToFloat64(context, &v[i], element) == 0;
		JS_FreeValue(context, element);
		if (!ok)  return false;
	}
	*outVector = make_vector(static_cast<OOScalar>(v[0]), static_cast<OOScalar>(v[1]), static_cast<OOScalar>(v[2]));
	return true;
}




void OOJSReportBadPropertySelector(JSContext *context, JSValueConst, int, const JSCFunctionListEntry *, size_t)
{
	cxx_OOJSReportError(context, "bad property selector");
}


void OOJSReportBadPropertyValue(JSContext *context, JSValueConst, int, const JSCFunctionListEntry *, size_t, JSValueConst)
{
	cxx_OOJSReportError(context, "bad property value");
}


JSValue OOJSUnconstructableConstruct(JSContext *context, JSValueConst, int, JSValueConst *)
{
	cxx_OOJSReportError(context, "unconstructable");
	return JS_EXCEPTION;
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


// (a C++ function, outside the C block above): the running script's JS object, or the demo ship's,
// owned by the caller.
JSValue OOJSValueFromCxxObject(JSContext *context, OOJSPrivateObject *object)
{
	if (object != nullptr && object == static_cast<OOJSPrivateObject *>(sRunningScript))  return JS_DupValue(context, sScriptObject);
	if (dynamic_cast<Entity *>(object) != nullptr)  return object->jsValueInContext(context);	// the demo ship
	return JS_NULL;
}


// MARK: The context -------------------------------------------------------------------------------

namespace {

JSRuntime *sRuntime;
JSValue sGlobal = JS_UNDEFINED;	// held for the life of the test
PlayerEntity *sPlayer = nullptr;
Universe *sUniverse = nil;


void SetUpContext()
{
	if (sContext != nullptr)  return;
	oo::log::logger().setInitialized(true);
	oo::log::logger().setSink(&CaptureLog);

	sRuntime = JS_NewRuntime();
	JS_SetMemoryLimit(sRuntime, 8u * 1024u * 1024u);
	sContext = JS_NewContext(sRuntime);
	gOOJSMainThreadContext = sContext;
	sGlobal = JS_GetGlobalObject(sContext);
	OOConstToJSStringInit(sContext);

	// Kept for the life of the test.
	sPlayer = new PlayerEntity;
	sPlayer->_status = STATUS_DOCKED;
	sPlayer->_exitScreen = GUI_SCREEN_STATUS;
	gOOPlayer = sPlayer;
	sUniverse = new StandInUniverse();
	sUniverse->_gui = oo::makeRef<GuiDisplayGen>().leakRef();	// kept for the life of the test
	sUniverse->_demoShip = new ShipEntity;
	sDemoShipObject = oo::makeRef<TestEntityObject>().leakRef();
	gSharedUniverse = sUniverse;
	sEngine = new OOJavaScriptEngine;
	sRunningScript = oo::makeRef<OOJSScript>().leakRef();
	sRunningScript->_name = "oolite-test-mission";
	sScriptObject = JS_NewObject(sContext);
	JS_SetPropertyStr(sContext, sGlobal, "theScript", JS_DupValue(sContext, sScriptObject));

	InitOOJSMission(sContext, sGlobal);
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

#define OO_CHECK_CALLS(calls, expected) \
	do { std::string got_ = Take(calls); if (got_ != (expected))  std::printf("    calls: %s\n", got_.c_str()); OO_CHECK_EQ(got_, std::string(expected)); } while (0)

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

OO_TEST(registration)
{
	SetUpContext();
	OO_CHECK_EVAL("typeof Mission", "function");
	OO_CHECK_EVAL("new Mission()", "threw: unconstructable");
	OO_CHECK_EVAL("mission instanceof Mission", "true");
	OO_CHECK_EVAL("(function () { mission = 5; return mission instanceof Mission; })()", "true");	// read-only
	OO_CHECK_EVAL("Object.keys(Mission.prototype).join()", "markedSystems,screenID,exitScreen");
	OO_CHECK_EVAL("['addMessageText', 'markSystem', 'runScreen', 'setInstructions', 'setInstructionsKey', 'unmarkSystem', 'runShipLibrary'].map(function (m) { return typeof mission[m]; }).join()",
				  "function,function,function,function,function,function,function");
}


OO_TEST(properties)
{
	SetUpContext();
	OO_CHECK_EVAL("JSON.stringify(mission.markedSystems)", "[]");
	sPlayer->_destinations["7"] = Dict({ { "system", oo::PList(7) } });
	sPlayer->_destinations["12"] = Dict({ { "system", oo::PList(12) }, { "name", oo::PList("x") } });
	OO_CHECK_EVAL("mission.markedSystems.map(function (m) { return m.system + ':' + m.name; }).join()", "12:x,7:undefined");	// in key order
	sPlayer->_destinations.clear();

	OO_CHECK_EVAL("mission.screenID", "null");
	sPlayer->_screenID = "oolite-intro";
	OO_CHECK_EVAL("mission.screenID", "oolite-intro");
	sPlayer->_screenID = std::nullopt;

	OO_CHECK_EVAL("mission.exitScreen", "GUI_SCREEN_STATUS");
	OO_CHECK_EVAL("(function () { mission.exitScreen = 'GUI_SCREEN_MARKET'; return mission.exitScreen; })()", "GUI_SCREEN_MARKET");
	OO_CHECK_EVAL("(function () { mission.exitScreen = 'nonsense'; return mission.exitScreen; })()", "GUI_SCREEN_MAIN");	// the default
	sPlayer->_calls.clear();
	sPlayer->_exitScreen = GUI_SCREEN_STATUS;
	OO_CHECK_EVAL("(function () { mission.screenID = 'x'; return mission.screenID; })()", "null");	// read-only
}


OO_TEST(markSystems)
{
	SetUpContext();
	sDeprecations = 0;
	OO_CHECK_EVAL("mission.markSystem(7, {system: 12, name: 'twelve'}, {name: 'none'})", "undefined");
	OO_CHECK_CALLS(sPlayer->_calls, "addMarker({name:'default',system:7}); addMarker({name:'twelve',system:12})");
	OO_CHECK_EQ(sDeprecations, 1);
	OO_CHECK_EVAL("mission.markSystem(3, 'x')", "threw: bad arguments: Mission.markSystem(1) - / numbers or objects");
	OO_CHECK_CALLS(sPlayer->_calls, "");	// nothing marked when one is bad
	OO_CHECK_EVAL("mission.markSystem(null)", "undefined");	// null is the number 0
	OO_CHECK_CALLS(sPlayer->_calls, "addMarker({name:'default',system:0})");
	sEnforceStandards = true;
	OO_CHECK_EVAL("mission.markSystem(9)", "undefined");	// numbers are ignored when standards are enforced
	OO_CHECK_CALLS(sPlayer->_calls, "");
	sEnforceStandards = false;

	OO_CHECK_EVAL("mission.unmarkSystem(7, {system: 12})", "true");
	OO_CHECK_CALLS(sPlayer->_calls, "removeMarker({name:'default',system:7}); removeMarker({system:12})");
	sPlayer->_removeFails = YES;
	OO_CHECK_EVAL("mission.unmarkSystem({system: 4})", "false");
	OO_CHECK_EVAL("mission.unmarkSystem({name: 'no system'})", "true");	// not tried
	sPlayer->_removeFails = NO;
	OO_CHECK_EVAL("mission.unmarkSystem(true, 'x')", "threw: bad arguments: Mission.unmarkSystem(1) - / numbers or objects");
	sPlayer->_calls.clear();
	sPlayer->_destinations.clear();
}


OO_TEST(messageAndInstructions)
{
	SetUpContext();
	OO_CHECK_EVAL("mission.addMessageText('Hello')", "undefined");
	OO_CHECK_EVAL("mission.addMessageText()", "undefined");	// nothing
	OO_CHECK_EVAL("mission.addMessageText(null)", "undefined");	// nothing
	OO_CHECK_CALLS(sPlayer->_calls, "literalText('Hello')");

	// The mission key is the running script's name unless given.
	OO_CHECK_EVAL("mission.setInstructions('Go to Lave.')", "undefined");
	OO_CHECK_EVAL("mission.setInstructions('Go home.', 'other')", "undefined");
	OO_CHECK_EVAL("mission.setInstructions(['One.', 'Two.'])", "undefined");
	OO_CHECK_EVAL("mission.setInstructions(null)", "undefined");
	OO_CHECK_EVAL("mission.setInstructions(null, null)", "undefined");	// the key "null"
	OO_CHECK_CALLS(sPlayer->_calls, "instructions('Go to Lave.', 'oolite-test-mission'); instructions('Go home.', 'other'); "
				   "instructionsList(['One.','Two.'], 'oolite-test-mission'); clearDescription('oolite-test-mission'); clearDescription('null')");
	OO_CHECK_EVAL("mission.setInstructionsKey('lave_key')", "undefined");
	OO_CHECK_EVAL("mission.setInstructionsKey(['a'])", "undefined");	// a list is not a key: cleared
	OO_CHECK_CALLS(sPlayer->_calls, "description('lave_key', 'oolite-test-mission'); clearDescription('oolite-test-mission')");

	sLastWarning.clear();
	OO_CHECK_EVAL("mission.setInstructions()", "undefined");
	OO_CHECK_EQ(sLastWarning, std::string("Usage error: mission.setInstructions() called with no arguments. Treating as Mission.setInstructions(null). This call may fail in a future version of Oolite."));
	OO_CHECK_CALLS(sPlayer->_calls, "clearDescription('oolite-test-mission')");
	OO_CHECK_EVAL("mission.setInstructionsKey(undefined)", "threw: bad arguments: Mission.setInstructionsKey(1) - / string or null");

	// No running script and no key: the player is told with no key (and logs it).
	OOJSScript *running = sRunningScript;
	sRunningScript = nullptr;
	OO_CHECK_EVAL("mission.setInstructions(null)", "undefined");
	OO_CHECK_CALLS(sPlayer->_calls, "instructions('', nullopt)");
	sRunningScript = running;
}


OO_TEST(runScreen)
{
	SetUpContext();
	sPlayer->_calls.clear();
	sUniverse->_calls.clear();
	sGuiCalls.clear();
	sMusic.clear();
	sLimiterPauses = 0;

	OO_CHECK_EVAL("mission.runScreen({title: 'A Job', music: 'tune.ogg', overlay: 'over.png', message: 'Hello', "
				  "choices: {'1_YES': 'Yes', '2_NO': 'No'}, initialChoicesKey: '2_NO', screenID: 'job', exitScreen: 'GUI_SCREEN_MARKET', "
				  "allowInterrupt: true, registerKeys: {k: [{key: 'k'}]}, customChartZoom: 2, customChartCentre: [1, 2, 0]}, "
				  "function (choice, key) { this.lastChoice = choice + '/' + key; })", "true");
	OO_CHECK_CALLS(sPlayer->_calls, "title('A Job'); overlay({name:'over.png'}); background(null); backgroundSpecial(''); chartZoom(2); chartCentre(1, 2); "
				   "exitScreen(13); screenID('job'); clearExtraKeys; extraKeys({k:[{key:'k'}]}); textEntry(NO); missionScreen(YES); allowInterrupt; "
				   "literalText('Hello'); choicesDict({1_YES:'Yes',2_NO:'No'}); overlay(null); background(null); title(nullopt); missionMusic('')");
	OO_CHECK_CALLS(sUniverse->_calls, "removeDemoShips");
	OO_CHECK_CALLS(sGuiCalls, "texture('mission.runScreen()'); texture('mission.runScreen()'); rowForKey('2_NO'); selectRow(7)");
	OO_CHECK(sMusic == (std::vector<std::string>{ "'tune.ogg'" }));
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EVAL("'displayModel' in mission", "false");

	// The callback runs as the script that set the screen, with the choice and the key pressed,
	// and this is the script; the choice is reset first, without an event.
	sPlayer->_choice = oo::PList("1_YES");
	sPlayer->_keyPress = oo::PList("y");
	sScriptStack.clear();
	MissionRunCallback();
	OO_CHECK_EVAL("theScript.lastChoice", "1_YES/y");
	OO_CHECK_CALLS(sPlayer->_calls, "choice(nullopt, '', NO)");
	OO_CHECK(sScriptStack == (std::vector<std::string>{ "+oolite-test-mission", "-oolite-test-mission" }));
	OO_CHECK_EQ(sEngine->_calls, 1);
	// Only once.
	MissionRunCallback();
	OO_CHECK_EQ(sEngine->_calls, 1);
	OO_CHECK_CALLS(sPlayer->_calls, "");
}


OO_TEST(runScreenOtherSettings)
{
	SetUpContext();
	sPlayer->_calls.clear();
	sUniverse->_calls.clear();
	sGuiCalls.clear();
	sMusic.clear();

	// No callback, a title key, a model, text entry, a choices key and a message key; a third
	// argument is the callback's this.
	OO_CHECK_EVAL("mission.runScreen({titleKey: 'mission_title', model: 'cobra', spinModel: false, modelPersonality: 9, textEntry: true, "
				  "choicesKey: 'my_choices', messageKey: 'my_message', customChartCentreInLY: [3, 4, 0], customChartZoom: 0.5, background: 'back.png', backgroundSpecial: 'SHORT_RANGE_CHART'})", "true");
	OO_CHECK_CALLS(sPlayer->_calls, "title('<The [name] Job>'); overlay(null); background({name:'back.png'}); backgroundSpecial('SHORT_RANGE_CHART'); "
				   "chartZoom(1); chartCentre(12, 8); exitScreen(6); clearScreenID; clearExtraKeys; textEntry(YES); missionScreen(NO); "
				   "text('my_message'); overlay(null); background(null); title(nullopt); missionMusic('')");
	OO_CHECK_EQ(sLastWarning, std::string("Mission.runScreen: invalid customChartZoom value specified."));
	OO_CHECK_CALLS(sUniverse->_calls, "removeDemoShips; demoShip('cobra', NO)");
	OO_CHECK_EQ(sUniverse->_demoShip->_personality, 9);
	OO_CHECK_EVAL("mission.displayModel.name", "demo ship");
	OO_CHECK(sMusic == (std::vector<std::string>{ "nullopt" }));

	OO_CHECK_EVAL("mission.runScreen({titleKey: 'no_such_key', model: 'none', customChartCentre: 'x'})", "true");
	OO_CHECK_EVAL("'displayModel' in mission", "false");
	OO_CHECK(sWarnings.size() >= 2 && sWarnings[sWarnings.size() - 2] == "Mission.runScreen: titleKey 'no_such_key' has no entry in missiontext.plist.");
	OO_CHECK_EQ(sLastWarning, std::string("Mission.runScreen: invalid value for customChartCentre. Must be valid vector. Defaulting to current location."));
	OO_CHECK_CALLS(sPlayer->_calls, "overlay(null); background(null); backgroundSpecial(''); chartCentre(10, 20); exitScreen(6); clearScreenID; clearExtraKeys; "
				   "textEntry(NO); missionScreen(NO); choices(''); overlay(null); background(null); title(nullopt); missionMusic('')");
	sUniverse->_calls.clear();

	// In flight: interruptible, and no model by role.
	sPlayer->_status = STATUS_IN_FLIGHT;
	OO_CHECK_EVAL("mission.runScreen({model: 'cobra', allowInterrupt: false})", "true");
	OO_CHECK_EQ(sLastWarning, std::string("Mission.runScreen: model cannot be displayed while in flight."));
	OO_CHECK_CALLS(sUniverse->_calls, "removeDemoShips");
	OO_CHECK(Take(sPlayer->_calls).find("allowInterrupt") != std::string::npos);
	sPlayer->_status = STATUS_DOCKED;

	// The callback with a this of its own; an exception in it is logged and ignored.
	OO_CHECK_EVAL("mission.runScreen({}, function () { this.called = true; }, theScript)", "true");
	sPlayer->_calls.clear();
	sEngine->_raise = YES;
	sLog.clear();
	sScriptStack.clear();
	MissionRunCallback();
	sEngine->_raise = NO;
	OO_CHECK_EQ(sLog.size(), static_cast<std::size_t>(1));
	OO_CHECK(!sLog.empty() && sLog[0].find("Ignoring exception") != std::string::npos && sLog[0].find("callback boom") != std::string::npos);
	OO_CHECK(sScriptStack == (std::vector<std::string>{ "+oolite-test-mission", "-oolite-test-mission" }));
	OO_CHECK_EVAL("theScript.called", "undefined");
}


OO_TEST(runScreenErrors)
{
	SetUpContext();
	sPlayer->_calls.clear();
	OO_CHECK_EVAL("mission.runScreen()", "threw: bad arguments: mission.runScreen(0) - / parameter object");
	OO_CHECK_EVAL("mission.runScreen({}, 'not a function')", "threw: bad arguments: mission.runScreen(1) - / function");
	OO_CHECK_CALLS(sPlayer->_calls, "");
	sPlayer->_status = STATUS_START_GAME;
	OO_CHECK_EVAL("mission.runScreen({title: 'x'})", "false");	// not during the intro
	OO_CHECK_CALLS(sPlayer->_calls, "");
	sPlayer->_status = STATUS_DOCKED;
	OO_CHECK_EQ(sLimiterPauses, 0);
}


OO_TEST(runShipLibrary)
{
	SetUpContext();
	sPlayer->_calls.clear();
	OO_CHECK_EVAL("mission.runShipLibrary()", "true");
	OO_CHECK_CALLS(sPlayer->_calls, "introFirstGo(NO)");
	sPlayer->_status = STATUS_IN_FLIGHT;
	sLastWarning.clear();
	OO_CHECK_EVAL("mission.runShipLibrary()", "false");
	OO_CHECK_EQ(sLastWarning, std::string("Mission.runShipLibrary: must be docked."));
	OO_CHECK_CALLS(sPlayer->_calls, "");
	sPlayer->_status = STATUS_DOCKED;
}


OO_TEST(nativeExceptions)
{
	SetUpContext();
	sPlayer->_raise = YES;
	OO_CHECK_EVAL("mission.screenID", "threw: Native exception: screen boom");
	sPlayer->_raise = NO;
	sPlayer->_throwCxx = YES;
	OO_CHECK_EVAL("mission.screenID", "threw: Native exception: cxx boom");
	sPlayer->_throwCxx = NO;
	OO_CHECK_EVAL("mission.screenID", "null");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
}


OO_TEST_MAIN()
