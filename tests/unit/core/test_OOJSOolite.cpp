/*	test_OOJSOolite.mm
	Unit tests for the oolite JS binding (src/Core/Scripting/OOJSOolite.h/.mm): bead oo-whvg,
	converted the way bead oo-ppc converted OOJSVector (proposed ADR-0056 amendment oo-ppc).

	As the binding tests of amendment oo-ppc item 6 do, it runs the JS class in a real context on
	the game's own façade backend (ooscript/JSEngine_quickjs.cpp), and links the game's own objects
	for the binding and the engine's exception translator (OOJSEngineNativeWrappers.mm). It stands
	in for the universe (its game view, settings, post-processing effect and time acceleration), the
	game view (colour saturation and the tone mappers), the resource manager (its paths), the tone
	mapper names and the engine functions the binding links against, with the engine headers'
	linkage. The version comes from the Info-gnustep.plist in the built-in resources directory, so
	the test makes one in a directory of its own and runs there. The expectations were written
	against the Objective-C file and run on it first; they pin the JS-visible behaviour: the oolite
	object and its class, every property both ways, compareVersion() with each kind of argument,
	the errors, and a native's exception. Run: bash tools/check-core-tests.sh
*/

#include "oofnd/objc/OOObject.h"
#include "ooscript/JSEngine.hpp"
#include "oofnd/objc/OOException.h"
#include "oofnd/objc/OOFoundationTypes.h"	// BOOL (from <objc/runtime.h> until bead oo-dbz.4)
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/String.hpp"


// MARK: The classes, as far as the binding sees them ----------------------------------------------

// As MyOpenGLView.h declares them (the test imports neither it nor Universe.h).
typedef enum
{
	OOHDR_TONEMAPPER_NONE = -1,
	OOHDR_TONEMAPPER_ACES_APPROX = 0,
	OOHDR_TONEMAPPER_DICE,
	OOHDR_TONEMAPPER_UCHIMURA,
	OOHDR_TONEMAPPER_REINHARD
} OOHDRToneMapper;

typedef enum
{
	OOSDR_TONEMAPPER_NONE = -1,
	OOSDR_TONEMAPPER_ACES = 0,
	OOSDR_TONEMAPPER_AgX,
	OOSDR_TONEMAPPER_HEJLDAWSON,
	OOSDR_TONEMAPPER_UC2,
	OOSDR_TONEMAPPER_UCHIMURA,
	OOSDR_TONEMAPPER_REINHARD
} OOSDRToneMapper;


// The game view: a stand-in for the C++ class (bead oo-9ht.153 deleted the Objective-C facade the
// test's Objective-C stand-in stood in for), with the header's names and signatures, defined out of
// line below with the stand-in's answers.
class MyOpenGLView : public oo::RefCounted
{
public:
	float _colorSaturation = {};
	BOOL _hdrOutput = {};
	OOHDRToneMapper _hdrToneMapper = {};
	OOSDRToneMapper _sdrToneMapper = {};
	int _hdrSets = {};
	int _sdrSets = {};

	float colorSaturation();
	void adjustColorSaturation(float colorSaturationAdjustment);
	bool hdrOutput();
	OOHDRToneMapper hdrToneMapper();
	void setHDRToneMapper(OOHDRToneMapper newToneMapper);
	OOSDRToneMapper sdrToneMapper();
	void setSDRToneMapper(OOSDRToneMapper newToneMapper);
};


/*	The universe. While _raise is set, -cxx_gameSettings raises, and while _throwCxx is set it
	throws a C++ exception, so the test sees what an exception under a native becomes.
*/
#include "UniverseStandIn.h"

// The universe as the code under test sees it: a stand-in for the C++ class (bead oo-ql9rn deleted
// the Objective-C facade the test's Objective-C stand-in stood in for), with the header's names and signatures.
// It answers virtual members, so it has the game's vtable (UniverseStandIn.h) and StandInUniverse overrides them.
class Universe : public oo::RefCounted
{
public:
	OO_UNIVERSE_STAND_IN_VIRTUAL_MEMBERS

	MyOpenGLView *_gameView;
	int _currentPostFX;
	double _timeAccelerationFactor;
	BOOL _raise;
	BOOL _throwCxx;

	oo::PList gameSettings();
	int currentPostFX();
	void setCurrentPostFX(int);
	double getTimeAccelerationFactor();
	void setTimeAccelerationFactor(double);
};

class StandInUniverse : public Universe
{
public:
	::MyOpenGLView *getGameView() override	{ return _gameView; }
};


#include "ResourceManager.h"


#include "OOJSOolite.h"

#include "oo_test.hpp"

#include <cstdarg>
#include <cstring>
#include <filesystem>
#include <fstream>
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

}	// namespace


float MyOpenGLView::colorSaturation()  { return _colorSaturation; }
void MyOpenGLView::adjustColorSaturation(float colorSaturationAdjustment)  { _colorSaturation += colorSaturationAdjustment; }
bool MyOpenGLView::hdrOutput()  { return _hdrOutput; }
OOHDRToneMapper MyOpenGLView::hdrToneMapper()  { return _hdrToneMapper; }
void MyOpenGLView::setHDRToneMapper(OOHDRToneMapper newToneMapper)  { _hdrToneMapper = newToneMapper; _hdrSets++; }
OOSDRToneMapper MyOpenGLView::sdrToneMapper()  { return _sdrToneMapper; }
void MyOpenGLView::setSDRToneMapper(OOSDRToneMapper newToneMapper)  { _sdrToneMapper = newToneMapper; _sdrSets++; }


oo::PList Universe::gameSettings()
{
	if (_raise)  OORaiseException(OOInvalidArgumentException, "settings %s", "boom");
	if (_throwCxx)  throw std::runtime_error("cxx boom");
	return Dict({ { "detailLevel", oo::PList("DETAIL_LEVEL_SHADERS") }, { "musicMode", oo::PList("MUSIC_ON") } });
}
int Universe::currentPostFX()	{ return _currentPostFX; }
void Universe::setCurrentPostFX(int newCurrentPostFX)	{ _currentPostFX = newCurrentPostFX; }
double Universe::getTimeAccelerationFactor()	{ return _timeAccelerationFactor; }
void Universe::setTimeAccelerationFactor(double newTimeAccelerationFactor)	{ _timeAccelerationFactor = newTimeAccelerationFactor; }


// ResourceManager is C++ since bead oo-9ht.150 deleted its Objective-C facade: C++ definitions of the
// statics the code under test calls, with the Objective-C stand-in's answers.
std::vector<std::string> ResourceManager::paths()
{
	return { "C:/Users/jameson/Oolite/Resources", "C:/Users/jameson/AddOns/one.oxp" };
}

std::vector<std::string> ResourceManager::maskUserNameInPathArray(const std::vector<std::string> &inputPathArray)
{
	std::vector<std::string> result;
	for (std::string path : inputPathArray)
	{
		const std::size_t at = path.find("jameson");
		if (at != std::string::npos)  path.replace(at, 7, "~");
		result.push_back(path);
	}
	return result;
}



// The tone mappers' names, as OOConstToString.mm gives them, for the ones the test uses.
std::string cxx_OOStringFromHDRToneMapper(OOHDRToneMapper toneMapper)
{
	switch (toneMapper)
	{
		case OOHDR_TONEMAPPER_ACES_APPROX:  return "OOHDR_TONEMAPPER_ACES_APPROX";
		case OOHDR_TONEMAPPER_DICE:  return "OOHDR_TONEMAPPER_DICE";
		case OOHDR_TONEMAPPER_REINHARD:  return "OOHDR_TONEMAPPER_REINHARD";
		default:  return "OOHDR_TONEMAPPER_UNDEFINED";
	}
}

OOHDRToneMapper cxx_OOHDRToneMapperFromString(const std::string &string)
{
	if (string == "OOHDR_TONEMAPPER_DICE")  return OOHDR_TONEMAPPER_DICE;
	if (string == "OOHDR_TONEMAPPER_REINHARD")  return OOHDR_TONEMAPPER_REINHARD;
	return OOHDR_TONEMAPPER_ACES_APPROX;
}

std::string cxx_OOStringFromSDRToneMapper(OOSDRToneMapper toneMapper)
{
	switch (toneMapper)
	{
		case OOSDR_TONEMAPPER_ACES:  return "OOSDR_TONEMAPPER_ACES";
		case OOSDR_TONEMAPPER_AgX:  return "OOSDR_TONEMAPPER_AGX";
		case OOSDR_TONEMAPPER_REINHARD:  return "OOSDR_TONEMAPPER_REINHARD";
		default:  return "OOSDR_TONEMAPPER_UNDEFINED";
	}
}

OOSDRToneMapper cxx_OOSDRToneMapperFromString(const std::string &string)
{
	if (string == "OOSDR_TONEMAPPER_AGX")  return OOSDR_TONEMAPPER_AgX;
	if (string == "OOSDR_TONEMAPPER_REINHARD")  return OOSDR_TONEMAPPER_REINHARD;
	return OOSDR_TONEMAPPER_ACES;
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


// A JS value as a property list, as far as compareVersion() hands one over: a string, a number, a
// boolean, an array of those, or null for anything else.
oo::PList cxx_OOJSPListFromJSValue(ooscript::Context context, ooscript::Value value)
{
	if (ooscript::isString(value))  return oo::PList(cxx_OOStringFromJSValue(context, value).value_or(std::string()));
	if (ooscript::isBoolean(value))  return oo::PList(ooscript::toBoolean(value));
	if (ooscript::isNumber(value))
	{
		double number = 0;
		ooscript::valueToNumber(context, value, &number);
		return oo::PList(number);
	}
	if (ooscript::isObject(value) && ooscript::isArrayObject(context, ooscript::toObject(value)))
	{
		ooscript::Object array = ooscript::toObject(value);
		std::uint32_t length = 0;
		ooscript::getArrayLength(context, array, &length);
		oo::PList::Array elements;
		for (std::uint32_t i = 0; i < length; i++)
		{
			ooscript::Value element = ooscript::undefinedValue();
			ooscript::getElement(context, array, static_cast<std::int32_t>(i), &element);
			elements.push_back(cxx_OOJSPListFromJSValue(context, element));
		}
		return oo::PList(std::move(elements));
	}
	return oo::PList();
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


Universe *gSharedUniverse = nil;


extern "C" {

void OOJSReportBadPropertySelector(ooscript::Context context, ooscript::Object, ooscript::PropertyId, ooscript::PropertySpec *)
{
	cxx_OOJSReportError(context, "bad property selector");
}


void OOJSReportBadPropertyValue(ooscript::Context context, ooscript::Object, ooscript::PropertyId, ooscript::PropertySpec *, ooscript::Value)
{
	cxx_OOJSReportError(context, "bad property value");
}


bool OOJSUnconstructableConstruct(ooscript::Context context, ooscript::CallArgs &)
{
	cxx_OOJSReportError(context, "unconstructable");
	return false;
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
MyOpenGLView *sView = nil;
std::filesystem::path sResources;


// The built-in resources directory is ./Resources: the test runs in a directory of its own.
void WriteInfoPlist(const char *version)
{
	std::ofstream out(sResources / "Info-gnustep.plist", std::ios::binary | std::ios::trunc);
	out << "{\n\tCFBundleName = \"Oolite\";\n";
	if (version != nullptr)  out << "\tCFBundleVersion = \"" << version << "\";\n";
	out << "}\n";
}


void SetUpContext()
{
	if (sContext != nullptr)  return;
	const std::filesystem::path home = std::filesystem::temp_directory_path() / "oo_test_OOJSOolite";
	sResources = home / "Resources";
	std::filesystem::create_directories(sResources);
	std::filesystem::current_path(home);
	WriteInfoPlist("1.91.0.7");

	sRuntime = ooscript::newRuntime(8u * 1024u * 1024u);
	sContext = ooscript::newContext(sRuntime, 8192);
	ooscript::beginRequest(sContext);
	sGlobal = ooscript::getGlobalObject(sContext);
	ooscript::initStandardClasses(sContext, sGlobal);

	sView = new MyOpenGLView();	// kept for the life of the test
	sView->_colorSaturation = 1.0f;
	sView->_hdrToneMapper = OOHDR_TONEMAPPER_DICE;
	sView->_sdrToneMapper = OOSDR_TONEMAPPER_AgX;
	sUniverse = new StandInUniverse();
	sUniverse->_gameView = sView;
	sUniverse->_currentPostFX = 2;
	sUniverse->_timeAccelerationFactor = 1.0;
	gSharedUniverse = sUniverse;
	InitOOJSOolite(sContext, sGlobal);
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
	OO_CHECK_EVAL("typeof Oolite", "function");
	OO_CHECK_EVAL("new Oolite()", "threw: unconstructable");
	OO_CHECK_EVAL("oolite instanceof Oolite", "true");
	OO_CHECK_EVAL("(function () { oolite = 5; return oolite instanceof Oolite; })()", "true");	// read-only
#ifndef NDEBUG
	OO_CHECK_EVAL("Object.keys(Oolite.prototype).join()", "gameSettings,jsVersion,jsVersionString,version,versionString,resourcePaths,colorSaturation,postFX,hdrToneMapper,sdrToneMapper,timeAccelerationFactor");
#else
	OO_CHECK_EVAL("Object.keys(Oolite.prototype).join()", "gameSettings,jsVersion,jsVersionString,version,versionString,resourcePaths,colorSaturation,postFX,hdrToneMapper,sdrToneMapper");
#endif
	OO_CHECK_EVAL("typeof Oolite.prototype.compareVersion", "function");
}


OO_TEST(version)
{
	SetUpContext();
	OO_CHECK_EVAL("oolite.versionString", "1.91.0.7");
	OO_CHECK_EVAL("JSON.stringify(oolite.version)", "[1,91,0,7]");
	OO_CHECK_EVAL("typeof oolite.jsVersion", "number");
	OO_CHECK_EVAL("typeof oolite.jsVersionString + ':' + (oolite.jsVersionString.length > 0)", "string:true");
	// Read each time.
	WriteInfoPlist("1.92");
	OO_CHECK_EVAL("JSON.stringify([oolite.versionString, oolite.version])", "[\"1.92\",[1,92]]");
	WriteInfoPlist(nullptr);
	OO_CHECK_EVAL("JSON.stringify([oolite.versionString, oolite.version])", "[null,[]]");
	WriteInfoPlist("1.91.0.7");
}


OO_TEST(compareVersion)
{
	SetUpContext();
	OO_CHECK_EVAL("oolite.compareVersion('1.91.0.7')", "0");
	OO_CHECK_EVAL("oolite.compareVersion('1.91')", "-1");
	OO_CHECK_EVAL("oolite.compareVersion('1.90')", "-1");
	OO_CHECK_EVAL("oolite.compareVersion('1.92')", "1");
	OO_CHECK_EVAL("oolite.compareVersion('2')", "1");
	OO_CHECK_EVAL("oolite.compareVersion([1, 91, 0, 7])", "0");
	OO_CHECK_EVAL("oolite.compareVersion([1, 90])", "-1");
	OO_CHECK_EVAL("oolite.compareVersion([1, 91, 0, 7, 1])", "1");
	OO_CHECK_EVAL("oolite.compareVersion([1.9, 91.2, 0, 7])", "0");	// each element as an unsigned integer
	OO_CHECK_EVAL("oolite.compareVersion([true, 91, 0, 7])", "0");	// a boolean counts as the number 1, as it did before
	OO_CHECK_EVAL("oolite.compareVersion([1, '91'])", "undefined");
	OO_CHECK_EVAL("oolite.compareVersion(1.5)", "undefined");	// neither array nor string
	OO_CHECK_EVAL("oolite.compareVersion()", "undefined");	// lenient
	OO_CHECK_EVAL("oolite.compareVersion(null)", "undefined");
}


OO_TEST(settingsAndPaths)
{
	SetUpContext();
	OO_CHECK_EVAL("JSON.stringify(oolite.gameSettings)", "{\"detailLevel\":\"DETAIL_LEVEL_SHADERS\",\"musicMode\":\"MUSIC_ON\"}");
	OO_CHECK_EVAL("JSON.stringify(oolite.resourcePaths)", "[\"C:/Users/~/Oolite/Resources\",\"C:/Users/~/AddOns/one.oxp\"]");
	// Read-only.
	OO_CHECK_EVAL("(function () { oolite.versionString = 'x'; return oolite.versionString; })()", "1.91.0.7");
	OO_CHECK_EVAL("(function () { oolite.gameSettings = 1; return typeof oolite.gameSettings; })()", "object");
}


OO_TEST(display)
{
	SetUpContext();
	OO_CHECK_EVAL("oolite.colorSaturation", "1");
	OO_CHECK_EVAL("(function () { oolite.colorSaturation = 1.5; return oolite.colorSaturation; })()", "1.5");
	OO_CHECK(sView->_colorSaturation == 1.5f);
	OO_CHECK_EVAL("(function () { oolite.colorSaturation = 'x'; return 'set'; })()", "set");	// NaN is a number
	sView->_colorSaturation = 1.0f;

	OO_CHECK_EVAL("oolite.postFX", "2");
	OO_CHECK_EVAL("(function () { oolite.postFX = 4; return oolite.postFX; })()", "4");
	OO_CHECK_EVAL("(function () { oolite.postFX = -3; return oolite.postFX; })()", "0");	// at least 0
	OO_CHECK_EVAL("(function () { oolite.postFX = 'a'; return oolite.postFX; })()", "threw: bad property value");
	OO_CHECK_EQ(sUniverse->_currentPostFX, 0);
	sUniverse->_currentPostFX = 2;

#ifndef NDEBUG
	OO_CHECK_EVAL("oolite.timeAccelerationFactor", "1");
	OO_CHECK_EVAL("(function () { oolite.timeAccelerationFactor = 4; return oolite.timeAccelerationFactor; })()", "4");
	OO_CHECK_EVAL("(function () { oolite.timeAccelerationFactor = 'fast'; return 'set'; })()", "set");	// NaN is a number
	sUniverse->_timeAccelerationFactor = 1.0;
#endif
}


OO_TEST(toneMappers)
{
	SetUpContext();
	// SDR output: the SDR mapper is read and set, the HDR one is undefined and refused with a warning.
	sView->_hdrOutput = NO;
	OO_CHECK_EVAL("oolite.sdrToneMapper", "OOSDR_TONEMAPPER_AGX");
	OO_CHECK_EVAL("oolite.hdrToneMapper", "OOHDR_TONEMAPPER_UNDEFINED");
	OO_CHECK_EVAL("(function () { oolite.sdrToneMapper = 'OOSDR_TONEMAPPER_REINHARD'; return oolite.sdrToneMapper; })()", "OOSDR_TONEMAPPER_REINHARD");
	OO_CHECK_EQ(sView->_sdrSets, 1);
	sLastWarning.clear();
	OO_CHECK_EVAL("(function () { oolite.hdrToneMapper = 'OOHDR_TONEMAPPER_REINHARD'; return oolite.hdrToneMapper; })()", "OOHDR_TONEMAPPER_UNDEFINED");
	OO_CHECK_EQ(sLastWarning, std::string("hdrToneMapper cannot be set if not running in HDR mode"));
	OO_CHECK_EQ(sView->_hdrSets, 0);
	OO_CHECK_EVAL("(function () { oolite.sdrToneMapper = 3; return 'set'; })()", "threw: bad property value");	// not a string
	OO_CHECK_EQ(sView->_sdrSets, 1);

	// HDR output: the other way round.
	sView->_hdrOutput = YES;
	OO_CHECK_EVAL("oolite.hdrToneMapper", "OOHDR_TONEMAPPER_DICE");
	OO_CHECK_EVAL("oolite.sdrToneMapper", "OOSDR_TONEMAPPER_UNDEFINED");
	OO_CHECK_EVAL("(function () { oolite.hdrToneMapper = 'OOHDR_TONEMAPPER_REINHARD'; return oolite.hdrToneMapper; })()", "OOHDR_TONEMAPPER_REINHARD");
	OO_CHECK_EQ(sView->_hdrSets, 1);
	sLastWarning.clear();
	OO_CHECK_EVAL("(function () { oolite.sdrToneMapper = 'OOSDR_TONEMAPPER_ACES'; return 'set'; })()", "set");
	OO_CHECK_EQ(sLastWarning, std::string("sdrToneMapper cannot be set if not running in SDR mode"));
	OO_CHECK_EQ(sView->_sdrSets, 1);
	OO_CHECK_EVAL("(function () { oolite.hdrToneMapper = null; return 'set'; })()", "threw: bad property value");
	sView->_hdrOutput = NO;
}


OO_TEST(nativeExceptions)
{
	SetUpContext();
	sUniverse->_raise = YES;
	OO_CHECK_EVAL("oolite.gameSettings", "threw: Native exception: settings boom");
	sUniverse->_raise = NO;
	sUniverse->_throwCxx = YES;
	OO_CHECK_EVAL("oolite.gameSettings", "threw: Native exception: cxx boom");
	sUniverse->_throwCxx = NO;
	OO_CHECK_EVAL("typeof oolite.gameSettings", "object");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
	OO_CHECK(ooscript::isInRequest(sContext));
}


OO_TEST_MAIN()
