/*	test_OOJSSound.mm
	Unit tests for the Sound JS binding (src/Core/Scripting/OOJSSound.h/.mm) and its OOSound
	category (OOJSSound+ObjCBridge.mm): bead oo-crq2, converted the way bead oo-ppc converted
	OOJSVector (proposed ADR-0056 amendments oo-ppc and oo-ykoy).

	As test_OOJSWormhole.mm does (amendment oo-ykoy, item 4), it runs the JS class in a real
	QuickJS-ng context, links the game's own objects for the binding, its bridge, the engine's
	class registry (OOJSClasses.mm) and its exception translator (OOJSEngineNativeWrappers.mm),
	and stands in for the classes the binding messages (OOSound,
	ResourceManager, OOMusicController, OOSoundSource and the player answer only the selectors the
	binding sends) and for the engine functions it links against, with the engine headers' linkage.
	The expectations were written against the Objective-C file and run on it first; they pin the
	JS-visible behaviour (name, toString(), the four static methods and their errors,
	SoundFromJSValue() for a Sound and for a name, a native's exception) and what the category
	answers the engine. Run: tests/run.sh unit
*/

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"
#include <objc/runtime.h>
#include "OOTypes.h"
#include "OOJSEngineCore.h"
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"


// MARK: The classes, as far as the binding sees them ----------------------------------------------

@class PlayerEntity;

// The player's status, as Entity.h defines it.
#undef ENTRY
#define ENTRY(label, value) label = value,
typedef enum OOEntityStatus
{
	#include "OOEntityStatus.tbl"
} OOEntityStatus;
#undef ENTRY

/*	A sound named "raise" raises from -cxx_name, one named "throw" throws a C++ exception, so the
	test sees what an exception under a native becomes.
*/
@interface OOSound: OOObject
{
@public
	std::optional<std::string> _name;
}
+ (id) cxx_soundWithCustomSoundKey:(const std::string &)key;
- (std::optional<std::string>) cxx_name;
@end

@interface OOSoundSource: OOObject
@end

@interface ResourceManager: OOObject
+ (OOSound *) cxx_ooSoundNamed:(const std::string &)fileName inFolder:(const std::optional<std::string> &)folderName;
@end

@interface OOMusicController: OOObject
{
@public
	std::optional<std::string> _playing;
	BOOL _loop;
	float _gain;
	int _stops;
}
+ (OOMusicController *) sharedController;
- (void) playMusicNamed:(const std::string &)name loop:(BOOL)loop gain:(float)gain;
- (void) stop;
- (OOSoundSource *) soundSource;
- (std::optional<std::string>) playingMusic;
@end

@interface FakePlayer: OOObject
{
@public
	OOEntityStatus _status;
}
- (OOEntityStatus) status;
@end

@interface OOSound (OOJavaScriptExtentions)
- (JSValue) oo_jsValueInContext:(JSContext *)context;
- (std::optional<std::string>) cxx_oo_jsDescription;
- (std::optional<std::string>) cxx_oo_jsClassName;
@end


#import "OOJSSound.h"

#include "oo_test.hpp"

#include <cmath>
#include <cstdarg>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>


namespace {
std::vector<OOSound *> sLoaded;
OOMusicController *sMusic = nil;
OOSoundSource *sMusicSource = nil;
} // namespace


@implementation OOSound

+ (id) cxx_soundWithCustomSoundKey:(const std::string &)key
{
	OOSound *sound = [[[OOSound alloc] init] autorelease];
	sound->_name = "custom:" + key;
	sLoaded.push_back([sound retain]);
	return sound;
}


- (std::optional<std::string>) cxx_name
{
	if (_name == "raise")  [OOException raise:OOInvalidArgumentException format:"name %s", "boom"];
	if (_name == "throw")  throw std::runtime_error("cxx boom");
	return _name;
}

@end


@implementation OOSoundSource
@end


@implementation ResourceManager

+ (OOSound *) cxx_ooSoundNamed:(const std::string &)fileName inFolder:(const std::optional<std::string> &)folderName
{
	if (fileName == "missing.ogg")  return nil;
	OOSound *sound = [[[OOSound alloc] init] autorelease];
	sound->_name = (fileName == "raise" || fileName == "throw") ? fileName : folderName.value_or("") + "/" + fileName;
	sLoaded.push_back([sound retain]);
	return sound;
}

@end


@implementation OOMusicController

+ (OOMusicController *) sharedController  { return sMusic; }
- (OOSoundSource *) soundSource  { return sMusicSource; }
- (std::optional<std::string>) playingMusic  { return _playing; }
- (void) stop  { _playing = std::nullopt; _stops++; }

- (void) playMusicNamed:(const std::string &)name loop:(BOOL)loop gain:(float)gain
{
	_playing = name;
	_loop = loop;
	_gain = gain;
}

@end


@implementation FakePlayer

- (OOEntityStatus) status  { return _status; }

@end


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


BOOL cxx_OOJSArgumentListGetNumber(JSContext *context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, int argc, JSValueConst *argv, double *outNumber, int *outConsumed)
{
	if (argc > 0 && JS_ToFloat64(context, outNumber, argv[0]) == 0 && !std::isnan(*outNumber))
	{
		if (outConsumed != NULL)  *outConsumed = 1;
		return YES;
	}
	cxx_OOJSReportBadArguments(context, scriptClass, function, argc, argv, "Expected number, got", std::nullopt);
	return NO;
}


namespace {
std::map<JSClassID, int> sConverters;
} // namespace

PlayerEntity *gOOPlayer = nil;


void OOJSReportBadPropertySelector(JSContext *context, JSValueConst, int, const JSCFunctionListEntry *, size_t)
{
	cxx_OOJSReportError(context, "bad property selector");
}


void OOJSRegisterObjectConverter(JSClassID classID, OOJSClassConverterCallback)
{
	sConverters[classID]++;
}


// The engine's object getter: the JS class must be the required one (the class registry's
// OOJSIsSubclass(), OOJSClasses.mm), and the private slot holds the object itself.
BOOL OOJSObjectGetterImplPRIVATE(JSContext *context, JSValueConst object, JSClassID requiredClassID, Class requiredObjCClass, const char *, id *outObject)
{
	if (!OOJSIsSubclass(JS_GetClassID(object), requiredClassID))
	{
		cxx_OOJSReportError(context, "Native method expected %s, got %s.", OOJSClassName(requiredClassID), cxx_OOStringFromJSValue(context, object).value_or("(null)").c_str());
		return NO;
	}
	JSClassID ignored;
	*outObject = (id)JS_GetAnyOpaque(object, &ignored);
	if (*outObject != nil && ![*outObject isKindOfClass:requiredObjCClass])
	{
		*outObject = nil;
		return NO;
	}
	return YES;
}


// An object's JS value, as the engine gives it (owned by the caller): its category's
// -oo_jsValueInContext: for a sound, a string naming the class for anything else here.
JSValue OOJSValueFromNativeObject(JSContext *context, id object)
{
	if (object == nil)  return JS_NULL;
	if ([object isKindOfClass:[OOSound class]])  return [(OOSound *)object oo_jsValueInContext:context];
	std::string name = std::string("native ") + class_getName([object class]);
	return JS_NewStringLen(context, name.data(), name.size());
}


id OOJSNativeObjectOfClassFromJSValue(JSContext *, JSValueConst value, Class requiredClass)
{
	if (!JS_IsObject(value))  return nil;
	JSClassID ignored;
	id object = (id)JS_GetAnyOpaque(value, &ignored);
	return [object isKindOfClass:requiredClass] ? object : nil;
}


JSValue OOJSObjectWrapperToString(JSContext *context, JSValueConst thisObj, int, JSValueConst *)
{
	JSClassID ignored;
	id object = (id)JS_GetAnyOpaque(thisObj, &ignored);
	std::optional<std::string> description;
	if ([object isKindOfClass:[OOSound class]])  description = [(OOSound *)object cxx_oo_jsDescription];
	std::string text = description.value_or("[object]");
	return JS_NewStringLen(context, text.data(), text.size());
}


JSValue OOJSUnconstructableConstruct(JSContext *context, JSValueConst, int, JSValueConst *)
{
	cxx_OOJSReportError(context, "unconstructable");
	return JS_EXCEPTION;
}


// The test's sounds live for the whole test; nothing is released when their objects go.
void OOJSObjectWrapperFinalize(JSRuntime *, JSValueConst)
{
}


int sLimiterPauses = 0;
int sProfileDepth = 0;

#if OOJS_PROFILE
void OOJSProfileEnter(OOJSProfileStackFrame *, const char *)  { sProfileDepth++; }
void OOJSProfileExit(OOJSProfileStackFrame *)  { sProfileDepth--; }
#endif
void OOJSPauseTimeLimiter(void)  { sLimiterPauses++; }
void OOJSResumeTimeLimiter(void)  { sLimiterPauses--; }


oo::PList OOJSBasicPrivateObjectConverter(JSContext *, JSValueConst)
{
	return oo::PList();
}


// MARK: The context -------------------------------------------------------------------------------

namespace {

JSRuntime *sRuntime;
JSContext *sContext;
JSValue sGlobal = JS_UNDEFINED;	// owned for the life of the test
FakePlayer *sPlayer = nil;


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = JS_NewRuntime();
	JS_SetMemoryLimit(sRuntime, 8u * 1024u * 1024u);
	sContext = JS_NewContext(sRuntime);
	gOOJSMainThreadContext = sContext;
	sGlobal = JS_GetGlobalObject(sContext);
	InitOOJSSound(sContext, sGlobal);

	sPlayer = [[FakePlayer alloc] init];	// kept for the life of the test
	sPlayer->_status = STATUS_IN_FLIGHT;
	gOOPlayer = (PlayerEntity *)sPlayer;
	sMusic = [[OOMusicController alloc] init];
	sMusicSource = [[OOSoundSource alloc] init];
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
	return sound != nil ? sound->_name : std::optional<std::string>("<nil>");
}

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

OO_TEST(registration)
{
	SetUpContext();
	OO_CHECK_EVAL("typeof Sound", "function");
	OO_CHECK_EVAL("new Sound()", "threw: unconstructable");
	OO_CHECK_EQ(sConverters.size(), 1u);
	OOSound *sound = [[[OOSound alloc] init] autorelease];
	sound->_name = "a.ogg";
	OO_CHECK([sound cxx_oo_jsClassName] == std::optional<std::string>("Sound"));
	OO_CHECK([sound cxx_oo_jsDescription] == std::optional<std::string>("[Sound \"a.ogg\"]"));
	sound->_name = std::nullopt;
	OO_CHECK([sound cxx_oo_jsDescription] == std::optional<std::string>("[Sound \"(null)\"]"));
	// -oo_jsValueInContext: makes a new Sound object each time, holding the sound retained.
	NSUInteger before = [sound retainCount];
	JSValue a = [sound oo_jsValueInContext:sContext];
	JSValue b = [sound oo_jsValueInContext:sContext];
	OO_CHECK(JS_IsObject(a) && JS_IsObject(b) && JS_VALUE_GET_PTR(a) != JS_VALUE_GET_PTR(b));
	JSClassID ignored;
	OO_CHECK(JS_GetAnyOpaque(a, &ignored) == sound);
	OO_CHECK_EQ([sound retainCount], before + 2);
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
	OOSound *sound = [[[OOSound alloc] init] autorelease];
	sound->_name = "object.ogg";
	JSValue object = [sound oo_jsValueInContext:sContext];
	OO_CHECK(SoundFromJSValue(sContext, object) == sound);
	JS_FreeValue(sContext, object);
	sLimiterPauses = 0;
	// At the start screen a name is not looked up: a string is not a Sound object.
	sPlayer->_status = STATUS_START_GAME;
	OO_CHECK(SoundFromJSValue(sContext, name) == nil);
	JS_FreeValue(sContext, name);
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
}


OO_TEST_MAIN()
