/*	test_OOJSSound.mm
	Unit tests for the Sound JS binding (src/Core/Scripting/OOJSSound.h/.mm) and the bodies of its
	OOSound category.

	As test_OOJSWormhole.mm does, it runs the JS class in a real QuickJS-ng context, links the
	game's own objects for the binding, the engine's class registry (OOJSClasses.mm), its C++
	private-slot glue (OOJSPrivateObject.cpp) and its exception translator
	(OOJSEngineNativeWrappers.mm), and stands in for the classes the binding calls (the sound, the
	custom-sound look-up, ResourceManager, OOMusicController, the SoundSource binding and the player
	answer only what the binding asks) and for the engine functions it links against, with the
	engine headers' linkage. The expectations pin the JS-visible behaviour (name, toString(), the
	four static methods and their
	errors, SoundFromJSValue() for a Sound and for a name, a native's exception) and what the
	category answered the engine. The sound is a C++ stand-in, the category's answers are the
	functions that held its bodies, and a Sound object's slot holds the binding's holder of the
	sound, which SoundFromJSValue() answers. Run: tests/run.sh unit
*/

#include "OOFoundation.h"
#include "oofnd/objc/OOObject.h"
#include "OOTypes.h"
#include "OOJSEngineCore.h"
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"


// MARK: The classes, as far as the binding sees them ----------------------------------------------

class PlayerEntity;

// The player's status, as Entity.h defines it.
#include "OOEntityStatus.h"

/*	The sound: a C++ stand-in (the root's members its vtable names;
   OOALSound.mm is not linked). A sound named "raise" raises from name(), one
   named "throw" throws a C++ exception, so the test sees what an exception
   under a native becomes.
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

/*	The music controller: the members the binding calls, declared as
   OOMusicController.h declares them (that header would bring the real
   OOSoundSource into this file) and defined below over this file's record of
   what was asked.
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
	bool _loop = false;
	float _gain = 0.0f;
	int _stops = 0;
};

/*	PLAYER: The binding asks it its status, the root entity's member
   (declared as Entity.h declares it; the test imports no game header that
   defines the classes), answered from the test's value.
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
std::vector<std::shared_ptr<OOSound>> sLoaded;	// the sounds made, kept as the resource manager's cache keeps them
MusicRecord *sMusic = nullptr;
char sMusicSourceObject;	// the music's source: an object the binding hands on unopened
OOSoundSource *sMusicSource = reinterpret_cast<OOSoundSource *>(&sMusicSourceObject);


OOSound *MakeSound(const std::optional<std::string> &name)
{
	const std::shared_ptr<TestSound> sound = oo::makeRef<TestSound>();
	sound->_name = name;
	sLoaded.push_back(sound);
	return sound.get();
}
} // namespace


OOSound *OOSoundWithCustomSoundKey(const std::string &key)
{
	return MakeSound("custom:" + key);
}


// ResourceManager: C++ definitions of the statics the code under test calls,
// with the stand-in's answers.
OOSound * ResourceManager::ooSoundNamed(const std::string &fileName, const std::optional<std::string> &folderName)
{
	if (fileName == "missing.ogg")  return nullptr;
	return MakeSound((fileName == "raise" || fileName == "throw") ? fileName : folderName.value_or("") + "/" + fileName);
}



// The SoundSource binding's JS value for a source (owned by the caller): a string naming the
// class, as the engine's stand-in answered for any object but a sound (OOJSSoundSource.mm is not
// linked).
JSValue OOJSSoundSourceJSValueInContext(OOSoundSource *source, JSContext *context)
{
	if (source == nullptr)  return JS_NULL;
	const std::string name = "native OOSoundSource";
	return JS_NewStringLen(context, name.data(), name.size());
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

// The one context (OOJSAcquireContext(), which OOJSClasses.mm registers classes through).
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
	cxx_OOJSReportError(context, "bad arguments: %s.%s (%d): %s; expected %s", scriptClass.value_or("").c_str(), function.value_or("").c_str(), argc, message.value_or("").c_str(), expectedArgsDescription.value_or("").c_str());
}


// The engine's: the pending exception, else an uncatchable error, which ends the script.
JSValue OOJSNativeFailure(JSContext *context)
{
	if (JS_HasException(context))  return JS_EXCEPTION;
	JSValue error = JS_NewError(context);
	JS_SetUncatchableError(context, error);
	return JS_Throw(context, error);
}


// What the class registration (OOJSClasses.mm) asks of the engine: it reports what class set-up
// left pending (the test drops it), and records property IDs, interned for the life of the
// process, as the engine's.
void OOJSReportPendingException(JSContext *context)
{
	JS_FreeValue(context, JS_GetException(context));
}


JSAtom cxx_OOJSIDFromString(const std::string &string)
{
	return JS_NewAtomLen(OOJSAcquireContext(), string.data(), string.size());
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


JSValue OOJSValueFromPList(JSContext *context, const oo::PList &plist)
{
	const std::string *str = plist.getIf<std::string>();
	return str != nullptr ? JS_NewStringLen(context, str->data(), str->size()) : JS_NULL;
}


bool cxx_OOJSArgumentListGetNumber(JSContext *context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, int argc, JSValueConst *argv, double *outNumber, int *outConsumed)
{
	if (argc > 0 && JS_ToFloat64(context, outNumber, argv[0]) == 0 && !std::isnan(*outNumber))
	{
		if (outConsumed != NULL)  *outConsumed = 1;
		return true;
	}
	cxx_OOJSReportBadArguments(context, scriptClass, function, argc, argv, "Expected number, got", std::nullopt);
	return false;
}


namespace {
std::map<JSClassID, int> sConverters;
} // namespace

PlayerEntity *gOOPlayer = nullptr;


void OOJSReportBadPropertySelector(JSContext *context, JSValueConst, int, const JSCFunctionListEntry *, size_t)
{
	cxx_OOJSReportError(context, "bad property selector");
}


void OOJSRegisterObjectConverter(JSClassID classID, OOJSClassConverterCallback)
{
	sConverters[classID]++;
}


// The shared toString(), which OOJSCxxObjectWrapperToString() hands a `this` of another class.
JSValue OOJSObjectWrapperToString(JSContext *context, JSValueConst, int, JSValueConst *)
{
	const std::string text = "[object]";
	return JS_NewStringLen(context, text.data(), text.size());
}


JSValue OOJSUnconstructableConstruct(JSContext *context, JSValueConst, int, JSValueConst *)
{
	cxx_OOJSReportError(context, "unconstructable");
	return JS_EXCEPTION;
}


int sLimiterPauses = 0;
int sProfileDepth = 0;

#if OOJS_PROFILE
void OOJSProfileEnter(OOJSProfileStackFrame *, const char *)  { sProfileDepth++; }
void OOJSProfileExit(OOJSProfileStackFrame *)  { sProfileDepth--; }
#endif
void OOJSPauseTimeLimiter(void)  { sLimiterPauses++; }
void OOJSResumeTimeLimiter(void)  { sLimiterPauses--; }


// MARK: The context -------------------------------------------------------------------------------

namespace {

JSRuntime *sRuntime;
JSContext *sContext;
JSValue sGlobal = JS_UNDEFINED;	// owned for the life of the test
FakePlayer *sPlayer = nullptr;


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = JS_NewRuntime();
	JS_SetMemoryLimit(sRuntime, 8u * 1024u * 1024u);
	sContext = JS_NewContext(sRuntime);
	gOOJSMainThreadContext = sContext;
	sGlobal = JS_GetGlobalObject(sContext);
	InitOOJSSound(sContext, sGlobal);

	sPlayer = new FakePlayer;	// kept for the life of the test
	sPlayer->_status = OOEntityStatus::kInFlight;
	gOOPlayer = reinterpret_cast<PlayerEntity *>(sPlayer);	// the root part comes first in PlayerEntity: the binding's PLAYER->status() reaches it
	sMusic = new MusicRecord();
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
	const std::shared_ptr<TestSound> sound = oo::makeRef<TestSound>();
	sound->_name = "a.ogg";
	OO_CHECK(OOJSSoundJSClassName() == std::optional<std::string>("Sound"));
	OO_CHECK(OOJSSoundJSDescription(sound.get()) == std::optional<std::string>("[Sound \"a.ogg\"]"));
	sound->_name = std::nullopt;
	OO_CHECK(OOJSSoundJSDescription(sound.get()) == std::optional<std::string>("[Sound \"(null)\"]"));
	// -oo_jsValueInContext: makes a new Sound object each time, holding the sound retained.
	const std::uint32_t before = sound->retainCount();
	JSValue a = OOJSSoundJSValueInContext(sound.get(), sContext);
	JSValue b = OOJSSoundJSValueInContext(sound.get(), sContext);
	OO_CHECK(JS_IsObject(a) && JS_IsObject(b) && JS_VALUE_GET_PTR(a) != JS_VALUE_GET_PTR(b));
	OO_CHECK(SoundFromJSValue(sContext, a) == sound.get());	// the slot's holder holds the sound
	sLimiterPauses = 0;
	OO_CHECK_EQ(sound->retainCount(), before + 2);
	JS_FreeValue(sContext, a);
	JS_FreeValue(sContext, b);
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
	JSValue name = JS_NewString(sContext, "ping.ogg");
	OO_CHECK(NameOf(SoundFromJSValue(sContext, name)) == std::optional<std::string>("Sounds/ping.ogg"));
	OO_CHECK_EQ(sLimiterPauses, 0);	// a named sound pauses the time limiter and resumes it (upstream #768 balances the pause)
	sLimiterPauses = 0;
	const std::shared_ptr<TestSound> sound = oo::makeRef<TestSound>();
	sound->_name = "object.ogg";
	JSValue object = OOJSSoundJSValueInContext(sound.get(), sContext);
	OO_CHECK(SoundFromJSValue(sContext, object) == sound.get());
	JS_FreeValue(sContext, object);
	sLimiterPauses = 0;
	// At the start screen a name is not looked up: a string is not a Sound object.
	sPlayer->_status = OOEntityStatus::kStartGame;
	OO_CHECK(SoundFromJSValue(sContext, name) == nullptr);
	JS_FreeValue(sContext, name);
	sPlayer->_status = OOEntityStatus::kInFlight;
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
}


OO_TEST_MAIN()
