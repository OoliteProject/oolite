/*	test_OOJSManifest.mm
	Unit tests for the Manifest JS binding (src/Core/Scripting/OOJSManifest.h/.mm): bead oo-7nfv,
	converted the way bead oo-ppc converted OOJSVector (proposed ADR-0056 amendment oo-ppc).

	As the binding tests of amendment oo-ppc item 6 do, it runs the JS class in a real context on
	the game's own façade backend (ooscript/JSEngine_quickjs.cpp), and links the game's own objects
	for the binding, the engine's exception translator (OOJSEngineNativeWrappers.mm) and the
	commodity classes it asks (OOCommodities and OOCommodityMarket, C++ since beads oo-9ht.25 and
	oo-9ht.21 deleted their façades, as test_OOCommodities.mm links them, reading the trade goods
	below; the stand-ins hold them as oo::Ref). It
	stands in for the player (its cargo and its manifest market), the universe (its commodities and
	its market), the resource manager and string expander the commodity classes call, the player
	ship's JS object, and the engine functions the binding links against, with the engine headers'
	linkage. The expectations were written against the Objective-C file and run on it first; they
	pin the JS-visible behaviour: the Manifest class and its two objects, the list, a commodity's
	quantity both ways (clamped at zero, refused for tonnage with special cargo, delete), the four
	comment methods and their errors, and a native's exception. Run: bash tools/check-core-tests.sh
*/

#include "OOCommodities.h"
#include "OOCommodityMarket.h"
#include "OOStringExpander.h"
#include "ooscript/JSEngine.hpp"
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"


// MARK: The classes, as far as the binding and the commodities see them ---------------------------

class StationEntity;

/*	The player: its cargo by good, its special cargo, its list for scripts and its manifest market.
	Asking for the quantity of "furs" raises, and of "gems" while _throwCxx is set throws a C++
	exception, so the test sees what an exception under a native becomes.
*/
// PLAYER: C++ since bead oo-9ht.177 deleted the Objective-C player this stood in for: the members
// the code under test calls, declared as the game headers declare them (the test imports none
// that defines the classes), with the stand-in's answers.
class PlayerEntity
{
public:
	oo::PList cargoListForScripting();
	OOCargoQuantity cargoQuantityForType(const std::string &type);
	OOCargoQuantity setCargoQuantityForType(const std::string &type, OOCargoQuantity amount);
	std::optional<std::string> getSpecialCargo();
	::OOCommodityMarket * getShipCommodityData();
	::OOScript * commodityScriptNamed(const std::optional<std::string> &scriptName);

	std::map<std::string, OOCargoQuantity> _cargo;
	std::optional<std::string> _specialCargo;
	oo::Ref<OOCommodityMarket> _shipCommodityData;
	int _sets = {};
	BOOL _throwCxx = {};
};

// The universe as the code under test sees it: a stand-in for the C++ class (bead oo-ql9rn deleted
// the Objective-C facade this stood in for), with the header's names and signatures.
class Universe
{
public:
	oo::Ref<OOCommodities> _commodities;
	oo::Ref<OOCommodityMarket> _market;

	::OOCommodities *getCommodities();
	::OOCommodityMarket *getCommodityMarket();
	OOSystemID currentSystemID();
};

::OOCommodities *Universe::getCommodities()	{ return _commodities.get(); }
::OOCommodityMarket *Universe::getCommodityMarket()	{ return _market.get(); }
OOSystemID Universe::currentSystemID()	{ return 7; }

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


#include "OOJSManifest.h"

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


// trade-goods.plist: food (tons), furs (tons), gems (grams).
oo::PList TradeGoods()
{
	return Dict({
		{ "food", Dict({ { "name", oo::PList("Food") }, { "quantity_unit", oo::PList(0) }, { "price_average", oo::PList(50) }, { "quantity_average", oo::PList(40) } }) },
		{ "furs", Dict({ { "name", oo::PList("Furs") }, { "quantity_unit", oo::PList(0) }, { "price_average", oo::PList(600) }, { "quantity_average", oo::PList(50) } }) },
		{ "gems", Dict({ { "name", oo::PList("Gem-stones") }, { "quantity_unit", oo::PList(2) }, { "price_average", oo::PList(160) }, { "quantity_average", oo::PList(200) } }) },
	});
}

}	// namespace


oo::PList PlayerEntity::cargoListForScripting()
{
	oo::PList::Array list;
	for (const auto &[good, quantity] : _cargo)
	{
		if (quantity > 0)  list.push_back(Dict({ { "commodity", oo::PList(good) }, { "quantity", oo::PList(static_cast<double>(quantity)) } }));
	}
	return oo::PList(std::move(list));
}
OOCargoQuantity PlayerEntity::cargoQuantityForType(const std::string &type)
{
	if (type == "furs")  OORaiseException(OOInvalidArgumentException, "cargo %s", "boom");
	if (type == "gems" && _throwCxx)  throw std::runtime_error("cxx boom");
	return _cargo[type];
}
OOCargoQuantity PlayerEntity::setCargoQuantityForType(const std::string &type, OOCargoQuantity amount)
{
	_sets++;
	_cargo[type] = amount;
	return amount;
}
std::optional<std::string> PlayerEntity::getSpecialCargo()  { return _specialCargo; }
::OOCommodityMarket * PlayerEntity::getShipCommodityData()  { return _shipCommodityData.get(); }
::OOScript * PlayerEntity::commodityScriptNamed(const std::optional<std::string> &script)  { (void)script; return nil; }




// ResourceManager is C++ since bead oo-9ht.150 deleted its Objective-C facade: C++ definitions of the
// statics the code under test calls, with the Objective-C stand-in's answers.
oo::PList ResourceManager::dictionaryFromFilesNamed(const std::string &fileName, const std::optional<std::string> &folderName, OOResourceMergeMode mergeMode, bool useCache)
{
	(void)fileName; (void)folderName; (void)mergeMode; (void)useCache;
	return TradeGoods();
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
// or an array or dictionary of those.
ooscript::Value OOJSValueFromPList(ooscript::Context context, const oo::PList &plist)
{
	if (const std::string *str = plist.getIf<std::string>())
	{
		ooscript::String js = ooscript::newStringCopyN(context, str->data(), str->size());
		return js != nullptr ? ooscript::stringValue(js) : ooscript::nullValue();
	}
	if (plist.isNumber())  return ooscript::numberValue(plist.doubleValue());
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


// Link stubs (amendment oo-zffj, item 2): what the commodity classes reach for commodity scripts.
// The player answers no script, so the test never runs one.
oo::PList cxx_OOJSPListFromJSObject(ooscript::Context, ooscript::Object)	{ std::abort(); }
ooscript::Context gOOJSMainThreadContext = nullptr;


namespace {
PlayerEntity *sPlayer = nullptr;
ooscript::Object sPlayerShip = nullptr;
std::map<ooscript::ClassDef *, int> sConverters;
}

PlayerEntity *gOOPlayer = nullptr;
Universe *gSharedUniverse = nil;


extern "C" {

PlayerEntity *OOPlayerForScripting(void)
{
	return sPlayer;
}


ooscript::Object JSPlayerShipObject(void)
{
	return sPlayerShip;
}


void OOJSReportBadPropertySelector(ooscript::Context context, ooscript::Object, ooscript::PropertyId, ooscript::PropertySpec *)
{
	cxx_OOJSReportError(context, "bad property selector");
}


void OOJSReportBadPropertyValue(ooscript::Context context, ooscript::Object, ooscript::PropertyId, ooscript::PropertySpec *, ooscript::Value)
{
	cxx_OOJSReportError(context, "bad property value");
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


void OOJSObjectWrapperFinalize(ooscript::Context, ooscript::Object)
{
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


// MARK: The context -------------------------------------------------------------------------------

namespace {

ooscript::Runtime sRuntime;
ooscript::Context sContext;
ooscript::Object sGlobal;
Universe *sUniverse = nil;


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = ooscript::newRuntime(8u * 1024u * 1024u);
	sContext = ooscript::newContext(sRuntime, 8192);
	ooscript::beginRequest(sContext);
	sGlobal = ooscript::getGlobalObject(sContext);
	ooscript::initStandardClasses(sContext, sGlobal);

	sUniverse = new Universe();	// kept for the life of the test
	gSharedUniverse = sUniverse;
	sPlayer = new PlayerEntity;
	gOOPlayer = sPlayer;
	sUniverse->_commodities = oo::makeRef<OOCommodities>();
	sUniverse->_market = sUniverse->_commodities->generateBlankMarket();
	sPlayer->_shipCommodityData = sUniverse->_commodities->generateManifestForPlayer();
	sPlayer->_cargo["food"] = 3;
	sPlayer->_cargo["gems"] = 12;

	sPlayerShip = ooscript::newObject(sContext, nullptr, nullptr, nullptr);
	ooscript::Value ship = ooscript::objectValue(sPlayerShip);
	ooscript::setProperty(sContext, sGlobal, "playerShip", &ship);
	InitOOJSManifest(sContext, sGlobal);
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
	OO_CHECK_EVAL("typeof Manifest", "function");
	OO_CHECK_EVAL("new Manifest()", "threw: unconstructable");
	OO_CHECK_EVAL("manifest instanceof Manifest && playerShip.manifest instanceof Manifest", "true");
	OO_CHECK_EVAL("manifest === playerShip.manifest", "false");
	OO_CHECK_EVAL("(function () { manifest = 5; return manifest instanceof Manifest; })()", "true");	// read-only
	OO_CHECK_EVAL("Object.keys(Manifest.prototype).join()", "list");
	OO_CHECK_EVAL("['comment', 'setComment', 'shortComment', 'setShortComment'].map(function (m) { return typeof Manifest.prototype[m]; }).join()", "function,function,function,function");
}


OO_TEST(quantities)
{
	SetUpContext();
	OO_CHECK_EVAL("JSON.stringify(manifest.list)", "[{\"commodity\":\"food\",\"quantity\":3},{\"commodity\":\"gems\",\"quantity\":12}]");
	OO_CHECK_EVAL("manifest.food", "3");
	OO_CHECK_EVAL("playerShip.manifest.gems", "12");
	OO_CHECK_EVAL("manifest.unobtainium", "undefined");	// not a commodity
	sPlayer->_sets = 0;
	OO_CHECK_EVAL("(function () { manifest.food = 7; return manifest.food; })()", "7");
	OO_CHECK_EVAL("(function () { manifest.food = -2; return manifest.food; })()", "0");	// clamped
	OO_CHECK_EVAL("(function () { manifest.food = 4.6; return manifest.food; })()", "5");
	// A value that is not a number, and delete (which sets undefined), change nothing.
	OO_CHECK_EVAL("(function () { manifest.food = 'x'; return manifest.food; })()", "5");
	OO_CHECK_EQ(sPlayer->_sets, 3);
	OO_CHECK_EVAL("(function () { manifest.food = 9; delete manifest.food; return manifest.food; })()", "9");
	OO_CHECK_EQ(sPlayer->_sets, 4);
	// Any other name is set on the player as it is, commodity or not, and kept on the object.
	OO_CHECK_EVAL("(function () { manifest.unobtainium = 3; return manifest.unobtainium; })()", "3");
	OO_CHECK_EQ(sPlayer->_sets, 5);
	OO_CHECK_EQ(sPlayer->_cargo["unobtainium"], 3u);
	sPlayer->_cargo.erase("unobtainium");
	sPlayer->_cargo["food"] = 3;
}


OO_TEST(specialCargo)
{
	SetUpContext();
	sPlayer->_specialCargo = std::string("a sealed crate");
	sLastWarning.clear();
	sPlayer->_sets = 0;
	// Tonnage cannot change with special cargo; grams and kilograms can.
	OO_CHECK_EVAL("(function () { manifest.food = 10; return manifest.food; })()", "3");
	OO_CHECK_EQ(sLastWarning, std::string("PlayerShip.manifest['foo'] - cannot modify cargo tonnage when Special Cargo is in use."));
	OO_CHECK_EQ(sPlayer->_sets, 0);
	OO_CHECK_EVAL("(function () { manifest.gems = 20; return manifest.gems; })()", "20");
	OO_CHECK_EQ(sPlayer->_sets, 1);
	sPlayer->_specialCargo = std::nullopt;
	sPlayer->_cargo["gems"] = 12;
}


OO_TEST(comments)
{
	SetUpContext();
	// The market expands its comments (the expander here gives "<text>").
	OO_CHECK_EVAL("manifest.comment('food')", "<[oolite-commodity-no-comment]>");
	OO_CHECK_EVAL("manifest.setComment('food', 'Edible')", "true");
	OO_CHECK_EVAL("manifest.comment('food')", "<Edible>");
	OO_CHECK_EVAL("manifest.setShortComment('gems', 'shiny')", "true");
	OO_CHECK_EVAL("manifest.shortComment('gems')", "<shiny>");
	OO_CHECK_EVAL("manifest.shortComment('food')", "<[oolite-commodity-no-short-comment]>");
	OO_CHECK_EVAL("manifest.setComment('unobtainium', 'x')", "false");
	OO_CHECK_EVAL("manifest.comment('unobtainium')", "<[oolite-unknown-commodity-name]>");
	OO_CHECK(sPlayer->_shipCommodityData->commentForGood("food") == std::optional<std::string>("<Edible>"));
	OO_CHECK_EVAL("manifest.comment()", "threw: bad arguments: Manifest.comment(0) - / good");
	OO_CHECK_EVAL("manifest.shortComment(null)", "threw: bad arguments: Manifest.shortComment(1) - / good");
	OO_CHECK_EVAL("manifest.setComment('food')", "threw: bad arguments: Manifest.setComment(1) - / good and information text");
	OO_CHECK_EVAL("manifest.setShortComment('food', null)", "threw: bad arguments: Manifest.setShortComment(2) - / good and information text");
}


OO_TEST(nativeExceptions)
{
	SetUpContext();
	OO_CHECK_EVAL("manifest.furs", "threw: Native exception: cargo boom");
	sPlayer->_throwCxx = YES;
	OO_CHECK_EVAL("manifest.gems", "threw: Native exception: cxx boom");
	sPlayer->_throwCxx = NO;
	OO_CHECK_EVAL("manifest.gems", "12");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
	OO_CHECK(ooscript::isInRequest(sContext));
}


OO_TEST_MAIN()
