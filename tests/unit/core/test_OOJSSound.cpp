/*	test_OOJSSound.mm
	Unit tests for the Sound JS binding (src/Core/Scripting/OOJSSound.h/.mm) and the bodies of its
	OOSound category (the Scripting bridge file until bead oo-9ht.68 deleted it with the sound's
	facade): bead oo-crq2, converted the way bead oo-ppc converted OOJSVector (proposed ADR-0056
	amendments oo-ppc and oo-ykoy).

	As test_OOJSWormhole.mm does (amendment oo-ykoy, item 4), it runs the JS class in a real
	context on the game's own façade backend (ooscript/JSEngine_quickjs.cpp), links the game's own
	objects for the binding, the engine's C++ private-slot glue (OOJSPrivateObject.cpp) and the
	engine's exception translator (OOJSEngineNativeWrappers.mm), and stands in for the classes the
	binding calls (the sound, the custom-sound look-up, ResourceManager, OOMusicController, the
	SoundSource binding and the player answer only what the binding asks) and for the engine
	functions it links against, with the engine headers' linkage. The expectations were written
	against the Objective-C file and run on it first; they pin the JS-visible behaviour (name,
	toString(), the four static methods and their errors, SoundFromJSValue() for a Sound and for a
	name, a native's exception) and what the category answered the engine. Since bead oo-9ht.68
	deleted the sound's facade the sound is a C++ stand-in, the category's answers are the
	functions that held its bodies, and a Sound object's slot holds the binding's holder of the
	sound, which SoundFromJSValue() answers (standing approval oo-9n5p9).
	Run: bash tools/check-core-tests.sh
*/

#include "OOCocoa.h"
#include "oofnd/objc/OOObject.h"
#include "OOTypes.h"
#include "ooscript/JSEngine.hpp"
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"


// MARK: The classes, as far as the binding sees them ----------------------------------------------

class PlayerEntity;

// The player's status, as Entity.h defines it.
#undef ENTRY
#define ENTRY(label, value) label = value,
typedef enum OOEntityStatus
{
	#include "OOEntityStatus.tbl"
} OOEntityStatus;
#undef ENTRY

/*	The sound: a C++ stand-in since bead oo-9ht.68 deleted the facade this file stubbed (the root's
	members its vtable names; OOALSound.mm is not linked). A sound named "raise" raises from name(),
	one named "throw" throws a C++ exception, so the test sees what an exception under a native
	becomes.
*/
#include "OOALSound.h"
#include <stdexcept>

OOSound::OOSound()  {}
ALuint OOSound::soundBuffer()  { return 0; }
bool OOSound::soundIncomplete()  { return false; }
void OOSound::rewind()  {}
std::optional<std::string> OOSound::descriptionComponents() const  { return std::nullopt; }
std::optional<std::string> OOSound::name()  { return std::nullopt; }

class TestSound final : public OOSound
{
public:
	std::optional<std::string> name() override
	{
		if (_name == "raise")  OORaiseException(OOInvalidArgumentException, "name %s", "boom");
		if (_name == "throw")  throw std::runtime_error("cxx boom");
		return _name;
	}

	std::optional<std::string> _name;
};

class OOSoundSource;	// only handed on (OOSoundSource.h)

#include "ResourceManager.h"

/*	The music controller is C++ (bead oo-9ht.90 deleted its Objective-C facade): the members the
	binding calls, declared as OOMusicController.h declares them (that header would bring the real
	OOSoundSource into this file) and defined below over this file's record of what was asked.
*/
#include "oofnd/Ref.hpp"
class OOMusicController : public oo::RefCounted
{
public:
	static OOMusicController *sharedController();
	void playMusicNamed(const std::string &name, bool loop, float gain);
	void stop();
	::OOSoundSource *soundSource();
	std::optional<std::string> playingMusic();
};

// What the controller was asked.
struct MusicRecord
{
	std::optional<std::string> _playing;
	BOOL _loop = NO;
	float _gain = 0.0f;
	int _stops = 0;
};

/*	PLAYER: C++ since bead oo-9ht.177 deleted the Objective-C player this stood in for. The binding
	asks it its status, the root entity's member (declared as Entity.h declares it; the test imports
	no game header that defines the classes), answered from the test's value.
*/
class Entity
{
public:
	OOEntityStatus status();
};

class FakePlayer : public Entity
{
public:
	OOEntityStatus _status = {};
};

#include "OOJSSound.h"
#include "OOJSSoundSource.h"

#include "oo_test.hpp"

#include <cmath>
#include <cstdarg>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>


namespace {
std::vector<oo::Ref<OOSound>> sLoaded;	// the sounds made, kept as the resource manager's cache keeps them
MusicRecord *sMusic = nullptr;
char sMusicSourceObject;	// the music's source: an object the binding hands on unopened
OOSoundSource *sMusicSource = reinterpret_cast<OOSoundSource *>(&sMusicSourceObject);


OOSound *MakeSound(const std::optional<std::string> &name)
{
	const oo::Ref<TestSound> sound = oo::makeRef<TestSound>();
	sound->_name = name;
	sLoaded.push_back(sound);
	return sound.get();
}
} // namespace


// Was +[OOSound cxx_soundWithCustomSoundKey:] (the category went with the facade, bead oo-9ht.68).
OOSound *OOSoundWithCustomSoundKey(const std::string &key)
{
	return MakeSound("custom:" + key);
}


// ResourceManager is C++ since bead oo-9ht.150 deleted its Objective-C facade: C++ definitions of the
// statics the code under test calls, with the Objective-C stand-in's answers.
OOSound * ResourceManager::ooSoundNamed(const std::string &fileName, const std::optional<std::string> &folderName)
{
	if (fileName == "missing.ogg")  return nullptr;
	return MakeSound((fileName == "raise" || fileName == "throw") ? fileName : folderName.value_or("") + "/" + fileName);
}



// The SoundSource binding's JS value for a source: a string naming the class, as the engine's
// stand-in answered for any object but a sound (OOJSSoundSource.mm is not linked).
ooscript::Value OOJSSoundSourceJSValueInContext(OOSoundSource *source, ooscript::Context context)
{
	if (source == nullptr)  return ooscript::nullValue();
	const std::string name = "native OOSoundSource";
	return ooscript::stringValue(ooscript::newStringCopyN(context, name.data(), name.size()));
}


OOMusicController *OOMusicController::sharedController()
{
	static OOMusicController *shared = new OOMusicController();	// never released, as the game's
	return shared;
}

::OOSoundSource *OOMusicController::soundSource()  { return sMusicSource; }
std::optional<std::string> OOMusicController::playingMusic()  { return sMusic->_playing; }
void OOMusicController::stop()  { sMusic->_playing = std::nullopt; sMusic->_stops++; }

void OOMusicController::playMusicNamed(const std::string &name, bool loop, float gain)
{
	sMusic->_playing = name;
	sMusic->_loop = loop;
	sMusic->_gain = gain;
}


OOEntityStatus Entity::status()  { return static_cast<FakePlayer *>(this)->_status; }


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


void cxx_OOJSReportBadArguments(ooscript::Context context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, unsigned argc, ooscript::Value *, const std::optional<std::string> &message, const std::optional<std::string> &expectedArgsDescription)
{
	cxx_OOJSReportError(context, "bad arguments: %s.%s (%u): %s; expected %s", scriptClass.value_or("").c_str(), function.value_or("").c_str(), argc, message.value_or("").c_str(), expectedArgsDescription.value_or("").c_str());
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


ooscript::Value OOJSValueFromPList(ooscript::Context context, const oo::PList &plist)
{
	const std::string *str = plist.getIf<std::string>();
	ooscript::String js = str != nullptr ? ooscript::newStringCopyN(context, str->data(), str->size()) : nullptr;
	return js != nullptr ? ooscript::stringValue(js) : ooscript::nullValue();
}


BOOL cxx_OOJSArgumentListGetNumber(ooscript::Context context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, unsigned argc, ooscript::Value *argv, double *outNumber, unsigned *outConsumed)
{
	if (argc > 0 && ooscript::valueToNumber(context, argv[0], outNumber) && !std::isnan(*outNumber))
	{
		if (outConsumed != NULL)  *outConsumed = 1;
		return YES;
	}
	cxx_OOJSReportBadArguments(context, scriptClass, function, argc, argv, "Expected number, got", std::nullopt);
	return NO;
}


namespace {
std::map<ooscript::ClassDef *, int> sConverters;
} // namespace

PlayerEntity *gOOPlayer = nullptr;


extern "C" {

void OOJSReportBadPropertySelector(ooscript::Context context, ooscript::Object, ooscript::PropertyId, ooscript::PropertySpec *)
{
	cxx_OOJSReportError(context, "bad property selector");
}


void OOJSRegisterObjectConverter(ooscript::ClassDef *theClass, oo::PList (*)(ooscript::Context, ooscript::Object))
{
	sConverters[theClass]++;
}


BOOL OOJSIsSubclass(ooscript::ClassDef *putativeSubclass, ooscript::ClassDef *superclass)
{
	return putativeSubclass == superclass;
}


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
FakePlayer *sPlayer = nullptr;


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = ooscript::newRuntime(8u * 1024u * 1024u);
	sContext = ooscript::newContext(sRuntime, 8192);
	ooscript::beginRequest(sContext);
	sGlobal = ooscript::getGlobalObject(sContext);
	ooscript::initStandardClasses(sContext, sGlobal);
	InitOOJSSound(sContext, sGlobal);

	sPlayer = new FakePlayer;	// kept for the life of the test
	sPlayer->_status = STATUS_IN_FLIGHT;
	gOOPlayer = reinterpret_cast<PlayerEntity *>(sPlayer);	// the root part comes first in PlayerEntity: the binding's PLAYER->status() reaches it
	sMusic = new MusicRecord();
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


std::optional<std::string> NameOf(OOSound *sound)
{
	return sound != nullptr ? static_cast<TestSound *>(sound)->_name : std::optional<std::string>("<nil>");
}

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

OO_TEST(registration)
{
	SetUpContext();
	OO_CHECK_EVAL("typeof Sound", "function");
	OO_CHECK_EVAL("new Sound()", "threw: unconstructable");
	OO_CHECK_EQ(sConverters.size(), 1u);
	const oo::Ref<TestSound> sound = oo::makeRef<TestSound>();
	sound->_name = "a.ogg";
	OO_CHECK(OOJSSoundJSClassName() == std::optional<std::string>("Sound"));
	OO_CHECK(OOJSSoundJSDescription(sound.get()) == std::optional<std::string>("[Sound \"a.ogg\"]"));
	sound->_name = std::nullopt;
	OO_CHECK(OOJSSoundJSDescription(sound.get()) == std::optional<std::string>("[Sound \"(null)\"]"));
	// -oo_jsValueInContext: makes a new Sound object each time, holding the sound retained.
	const std::uint32_t before = sound->retainCount();
	ooscript::Value a = OOJSSoundJSValueInContext(sound.get(), sContext);
	ooscript::Value b = OOJSSoundJSValueInContext(sound.get(), sContext);
	OO_CHECK(ooscript::isObject(a) && ooscript::isObject(b) && ooscript::toObject(a) != ooscript::toObject(b));
	OO_CHECK(SoundFromJSValue(sContext, a) == sound.get());	// the slot's holder holds the sound
	sLimiterPauses = 0;
	OO_CHECK_EQ(sound->retainCount(), before + 2);
}


OO_TEST(load)
{
	OO_CHECK_EVAL("Sound.load('bang.ogg').name", "Sounds/bang.ogg");
	OO_CHECK_EVAL("Sound.load('[custom-key]').name", "custom:[custom-key]");
	OO_CHECK_EVAL("Sound.load('bang.ogg') instanceof Sound", "true");
	OO_CHECK_EVAL("String(Sound.load('bang.ogg'))", "[Sound \"Sounds/bang.ogg\"]");
	OO_CHECK_EVAL("Sound.load('missing.ogg')", "null");
	OO_CHECK_EVAL("Sound.load()", "threw: bad arguments: Sound.load (0): ; expected string");
	OO_CHECK_EVAL("Sound.load(null)", "threw: bad arguments: Sound.load (1): ; expected string");
	OO_CHECK_EQ(sLimiterPauses, 0);
}


OO_TEST(music)
{
	SetUpContext();
	OO_CHECK_EVAL("Sound.musicSoundSource()", "native OOSoundSource");
	OO_CHECK_EVAL("Sound.playMusic('theme.ogg')", "undefined");
	OO_CHECK(sMusic->_playing == std::optional<std::string>("theme.ogg") && !sMusic->_loop && sMusic->_gain == 1.0f);
	OO_CHECK_EVAL("Sound.playMusic('loop.ogg', true, 0.5)", "undefined");
	OO_CHECK(sMusic->_playing == std::optional<std::string>("loop.ogg") && sMusic->_loop && sMusic->_gain == 0.5f);
	OO_CHECK_EVAL("Sound.playMusic('x.ogg', true, 'loud')", "threw: bad arguments: Sound.playMusic (1): ; expected float");
	OO_CHECK_EVAL("Sound.playMusic()", "threw: bad arguments: Sound.playMusic (0): ; expected string");
	int stops = sMusic->_stops;
	OO_CHECK_EVAL("Sound.stopMusic('other.ogg')", "undefined");	// not the one playing
	OO_CHECK_EQ(sMusic->_stops, stops);
	OO_CHECK_EVAL("Sound.stopMusic('loop.ogg')", "undefined");
	OO_CHECK_EQ(sMusic->_stops, stops + 1);
	OO_CHECK_EVAL("Sound.stopMusic()", "undefined");
	OO_CHECK_EQ(sMusic->_stops, stops + 2);
	OO_CHECK_EVAL("Sound.stopMusic(null)", "threw: bad arguments: Sound.stopMusic (1): ; expected string or no argument");
	OO_CHECK_EQ(sLimiterPauses, 0);
}


OO_TEST(soundFromJSValue)
{
	SetUpContext();
	ooscript::Value value = ooscript::undefinedValue();
	ooscript::String name = ooscript::newStringCopyN(sContext, "ping.ogg", 8);
	value = ooscript::stringValue(name);
	OO_CHECK(NameOf(SoundFromJSValue(sContext, value)) == std::optional<std::string>("Sounds/ping.ogg"));
	OO_CHECK_EQ(sLimiterPauses, 1);	// a named sound pauses the time limiter and returns without resuming it
	sLimiterPauses = 0;
	const oo::Ref<TestSound> sound = oo::makeRef<TestSound>();
	sound->_name = "object.ogg";
	value = OOJSSoundJSValueInContext(sound.get(), sContext);
	OO_CHECK(SoundFromJSValue(sContext, value) == sound.get());
	sLimiterPauses = 0;
	// At the start screen a name is not looked up: a string is not a Sound object.
	sPlayer->_status = STATUS_START_GAME;
	value = ooscript::stringValue(name);
	OO_CHECK(SoundFromJSValue(sContext, value) == nullptr);
	sPlayer->_status = STATUS_IN_FLIGHT;
	sLimiterPauses = 0;
}


OO_TEST(nativeExceptions)
{
	SetUpContext();
	// The property getter is a native (OOJS_NATIVE_ENTER): a raise from the sound is a JS error,
	// and so is a C++ exception.
	OO_CHECK_EVAL("Sound.load('raise').name", "threw: Native exception: name boom");
	OO_CHECK_EVAL("Sound.load('throw').name", "threw: Native exception: cxx boom");
	OO_CHECK_EVAL("Sound.load('fine').name", "Sounds/fine");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
	OO_CHECK(ooscript::isInRequest(sContext));
}


OO_TEST_MAIN()
