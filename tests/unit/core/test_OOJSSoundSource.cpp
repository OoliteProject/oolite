/*	test_OOJSSoundSource.mm
	Unit tests for the SoundSource JS binding (src/Core/Scripting/OOJSSoundSource.h/.mm) and the
	bodies of its OOSoundSource category.

	As test_OOJSWormhole.mm does, it runs the JS class in a real QuickJS-ng context, links the
	game's own objects for the binding, the engine's class registry (OOJSClasses.mm) and its
	exception translator (OOJSEngineNativeWrappers.mm), and stands in for the classes the binding
	calls (the source and the sound answer only what the binding asks), for the Sound and Vector3D
	conversions (a vector is the array [x, y, z] here) and for the engine functions it links
	against, with the engine headers' linkage. The expectations were written against the Objective-C
	file and run on it first; they pin the JS-visible behaviour (construction, the seven properties
	and their clamps, play(), stop(), playOrRepeat(), a native's exception) and what the category
	answered the engine. The source and the sound are C++ stand-ins (their members over a record per
	object), the category's answers are the functions that held its bodies, and the engine's C++
	private-slot glue (OOJSPrivateObject.h) is stood in for as its Objective-C getter, finalizer and
	toString() were. Run: tests/run.sh unit
*/

#include "OOFoundation.h"
#include "oofnd/objc/OOObject.h"
#include "OOMaths.h"
#include "OOJSEngineCore.h"
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"


#include "OOSoundSource.h"
#include "OOJSPrivateObject.h"
#include "OOJSSoundSource.h"

#include "oo_test.hpp"

#include <cmath>
#include <cstdarg>
#include <cstdint>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>


// The sound: an object the binding hands on (the root's members its vtable names; OOALSound.mm is
// not linked). A C++ stand-in.
OOSound::OOSound()  {}
std::optional<std::string> OOSound::name()  { return std::nullopt; }
ALuint OOSound::soundBuffer()  { return 0; }
bool OOSound::soundIncomplete()  { return false; }
void OOSound::rewind()  {}
std::optional<std::string> OOSound::descriptionComponents() const  { return std::nullopt; }

class TestSound final : public OOSound
{
public:
	std::string _name;
};


/*	The source: a C++ stand-in. Its members answer from a record per source
   (its ivars were the stub's). A source whose gain is 0.99 raises from gain(),
   one whose gain is 0.98 throws a C++ exception, so the test sees what an
   exception under a native becomes.
*/
struct SourceRecord
{
	oo::Ref<OOSound> _sound;
	BOOL _loop = NO;
	uint8_t _repeatCount = 0;
	BOOL _playing = NO;
	BOOL _positional = NO;
	Vector _position = {};
	float _gain = 0.0f;
	int _plays = 0;
	int _playOrRepeats = 0;
	int _stops = 0;
};

namespace {
std::map<const OOSoundSource *, SourceRecord> sRecords;
} // namespace

OOSoundSource::OOSoundSource()  { sRecords[this]; }
OOSoundSource::~OOSoundSource()  { sRecords.erase(this); }
void OOSoundSource::channel(OOSoundChannel *, OOSound *)  {}
std::optional<std::string> OOSoundSource::descriptionComponents() const  { return std::nullopt; }

OOSound *OOSoundSource::sound()  { return sRecords[this]._sound.get(); }
void OOSoundSource::setSound(OOSound *inSound)  { sRecords[this]._sound = oo::Ref<OOSound>(inSound); }
bool OOSoundSource::loop()  { return sRecords[this]._loop; }
void OOSoundSource::setLoop(bool inLoop)  { sRecords[this]._loop = inLoop; }
uint8_t OOSoundSource::repeatCount()  { return sRecords[this]._repeatCount; }
void OOSoundSource::setRepeatCount(uint8_t inCount)  { sRecords[this]._repeatCount = inCount; }
bool OOSoundSource::isPlaying()  { return sRecords[this]._playing; }
void OOSoundSource::play()  { sRecords[this]._plays++; sRecords[this]._playing = YES; }
void OOSoundSource::playOrRepeat()  { sRecords[this]._playOrRepeats++; sRecords[this]._playing = YES; }
void OOSoundSource::stop()  { sRecords[this]._stops++; sRecords[this]._playing = NO; }
void OOSoundSource::setPositional(bool inPositional)  { sRecords[this]._positional = inPositional; }
bool OOSoundSource::positional()  { return sRecords[this]._positional; }
void OOSoundSource::setPosition(Vector inPosition)  { sRecords[this]._position = inPosition; }
Vector OOSoundSource::position()  { return sRecords[this]._position; }
void OOSoundSource::setGain(float gain)  { sRecords[this]._gain = gain; }

float OOSoundSource::gain()
{
	const float gain = sRecords[this]._gain;
	if (gain == 0.99f)  OORaiseException(OOInvalidArgumentException, "gain %s", "boom");
	if (gain == 0.98f)  throw std::runtime_error("cxx boom");
	return gain;
}


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


// As the engine's: a number rounded to the nearest integer; NaN or out of range is an error.
BOOL OOJSValueToInt32(JSContext *context, JSValueConst value, int32_t *outValue)
{
	double number;
	if (JS_ToFloat64(context, &number, value) < 0)  return NO;
	number = std::floor(number + 0.5);
	if (std::isnan(number) || number < INT32_MIN || number > INT32_MAX)
	{
		cxx_OOJSReportError(context, "can't convert to an integer");
		return NO;
	}
	*outValue = static_cast<int32_t>(number);
	return YES;
}


namespace {
std::map<JSClassID, int> sConverters;
JSClassID sFakeSoundClassID = 0;
JSClassDef sFakeSoundClass = {
	.class_name = "Sound",
};
} // namespace


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


// A vector is the array [x, y, z] here: enough to see what the binding hands over and takes.
bool VectorToJSValue(JSContext *context, Vector vector, JSValue *outValue)
{
	JSValue array = JS_NewArray(context);
	if (JS_IsException(array))  return false;
	JS_SetPropertyUint32(context, array, 0, JS_NewNumber(context, vector.x));
	JS_SetPropertyUint32(context, array, 1, JS_NewNumber(context, vector.y));
	JS_SetPropertyUint32(context, array, 2, JS_NewNumber(context, vector.z));
	*outValue = array;
	return true;
}


bool JSValueToVector(JSContext *context, JSValueConst value, Vector *outVector)
{
	double v[3] = {};
	if (!JS_IsArray(value))  return false;
	for (std::uint32_t i = 0; i < 3; i++)
	{
		JSValue element = JS_GetPropertyUint32(context, value, i);
		const bool ok = !JS_IsException(element) && JS_ToFloat64(context, &v[i], element) == 0;
		JS_FreeValue(context, element);
		if (!ok)  return false;
	}
	*outVector = make_vector(v[0], v[1], v[2]);
	return true;
}


int sLimiterPauses = 0;
int sProfileDepth = 0;

#if OOJS_PROFILE
void OOJSProfileEnter(OOJSProfileStackFrame *, const char *)  { sProfileDepth++; }
void OOJSProfileExit(OOJSProfileStackFrame *)  { sProfileDepth--; }
#endif
void OOJSPauseTimeLimiter(void)  { sLimiterPauses++; }
void OOJSResumeTimeLimiter(void)  { sLimiterPauses--; }


// A sound's JS value, as the Sound binding gives it (owned by the caller): a JS Sound holding the
// sound (OOJSSound.mm is not linked); null for none.
JSValue OOJSSoundJSValueInContext(OOSound *sound, JSContext *context)
{
	if (sound == nullptr)  return JS_NULL;
	JSValue object = JS_NewObjectClass(context, static_cast<int>(sFakeSoundClassID));
	if (JS_IsException(object))
	{
		JS_FreeValue(context, JS_GetException(context));
		return JS_NULL;
	}
	if (JS_SetOpaque(object, sound) != 0)
	{
		JS_FreeValue(context, object);
		return JS_NULL;
	}
	return object;
}


// A JS Sound's sound, or null for anything else (a name is not looked up here).
OOSound *SoundFromJSValue(JSContext *, JSValueConst value)
{
	if (!JS_IsObject(value) || JS_GetClassID(value) != sFakeSoundClassID)  return nullptr;
	return static_cast<OOSound *>(JS_GetOpaque(value, sFakeSoundClassID));
}


/*	The engine's C++ private-slot glue (OOJSPrivateObject.cpp), stood in for as its Objective-C
	counterparts were: the slot holds the object retained; the getter checks the JS class (the
	class registry's OOJSIsSubclass(), OOJSClasses.mm) and gives the slot's object; the finalizer
	does nothing (as the stub's did); toString() is the shared one's answer here.
*/
bool OOJSSetCxxPrivate(JSValueConst jsObject, oo::RefCounted *object)
{
	if (object != nullptr)  object->retain();
	if (JS_SetOpaque(jsObject, object) == 0)  return true;
	if (object != nullptr)  object->release();
	return false;
}


bool OOJSGetCxxPrivateImpl(JSContext *context, JSValueConst object, JSClassID requiredClassID, oo::RefCounted **outObject)
{
	if (!OOJSIsSubclass(JS_GetClassID(object), requiredClassID))
	{
		cxx_OOJSReportError(context, "Native method expected %s, got %s.", OOJSClassName(requiredClassID), cxx_OOStringFromJSValue(context, object).value_or("(null)").c_str());
		return false;
	}
	JSClassID ignored;
	*outObject = static_cast<oo::RefCounted *>(JS_GetAnyOpaque(object, &ignored));
	return true;
}


// The test's sources live for the whole test; nothing is released when their objects go.
void OOJSCxxObjectWrapperFinalize(JSRuntime *, JSValueConst)
{
}


JSValue OOJSCxxObjectWrapperToString(JSContext *context, JSValueConst, JSClassID)
{
	return JS_NewString(context, "[SoundSource]");
}


// MARK: The context -------------------------------------------------------------------------------

namespace {

JSRuntime *sRuntime;
JSContext *sContext;
JSValue sGlobal = JS_UNDEFINED;	// owned for the life of the test
OOSoundSource *sSourceObject = nullptr;	// the source the tests ask through `source`
SourceRecord *sSource = nullptr;		// what it was asked
TestSound *sSound = nullptr;


// Takes value.
void Define(const char *name, JSValue value)
{
	JS_SetPropertyStr(sContext, sGlobal, name, value);
}


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = JS_NewRuntime();
	JS_SetMemoryLimit(sRuntime, 8u * 1024u * 1024u);
	sContext = JS_NewContext(sRuntime);
	gOOJSMainThreadContext = sContext;
	sGlobal = JS_GetGlobalObject(sContext);
	OOJSRegisterClass(&sFakeSoundClassID, &sFakeSoundClass);
	OOJSInitClass(sContext, sGlobal, sFakeSoundClassID, JS_UNDEFINED, nullptr, 0, nullptr, 0, nullptr, 0, nullptr, 0);
	InitOOJSSoundSource(sContext, sGlobal);

	sSound = oo::makeRef<TestSound>().leakRef();	// kept for the life of the test
	sSound->_name = "ping";
	sSourceObject = oo::makeRef<OOSoundSource>().leakRef();	// kept for the life of the test
	sSource = &sRecords[sSourceObject];
	sSource->_sound = oo::Ref<OOSound>(sSound);
	sSource->_repeatCount = 1;
	sSource->_position = make_vector(1, 2, 3);
	sSource->_gain = 0.5f;
	Define("source", OOJSSoundSourceJSValueInContext(sSourceObject, sContext));
	Define("aSound", OOJSSoundJSValueInContext(sSound, sContext));
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

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

OO_TEST(registration)
{
	SetUpContext();
	OO_CHECK_EVAL("typeof SoundSource", "function");
	OO_CHECK_EQ(sConverters.size(), 1u);
	OO_CHECK(OOJSSoundSourceJSClassName() == std::optional<std::string>("SoundSource"));
	// -oo_jsValueInContext: makes a new SoundSource object each time, holding the source retained.
	const std::uint32_t before = sSourceObject->retainCount();
	JSValue a = OOJSSoundSourceJSValueInContext(sSourceObject, sContext);
	JSValue b = OOJSSoundSourceJSValueInContext(sSourceObject, sContext);
	OO_CHECK(JS_IsObject(a) && JS_IsObject(b) && JS_VALUE_GET_PTR(a) != JS_VALUE_GET_PTR(b));
	JS_FreeValue(sContext, b);	// the stand-in finalizer keeps its holder
	Define("sourceA", a);	// the slot's holder holds the source: the object answers its record
	OO_CHECK_EVAL("sourceA.volume", "0.5");
	OO_CHECK_EQ(sSourceObject->retainCount(), before + 2);
	OO_CHECK_EVAL("source instanceof SoundSource", "true");
	OO_CHECK_EVAL("String(source)", "[SoundSource]");
}


OO_TEST(construction)
{
	OO_CHECK_EVAL("new SoundSource() instanceof SoundSource", "true");
	OO_CHECK_EVAL("new SoundSource().volume", "0");
	OO_CHECK_EVAL("new SoundSource().sound", "null");
	OO_CHECK_EVAL("SoundSource()", "threw: SoundSource() cannot be called as a function, it must be used as a constructor (as in new SoundSource()).");
}


OO_TEST(properties)
{
	OO_CHECK_EVAL("source.isPlaying", "false");
	OO_CHECK_EVAL("source.loop", "false");
	OO_CHECK_EVAL("source.position", "1,2,3");
	OO_CHECK_EVAL("source.positional", "false");
	OO_CHECK_EVAL("source.repeatCount", "1");
	OO_CHECK_EVAL("source.volume", "0.5");
	OO_CHECK_EVAL("source.sound === undefined", "false");
	OO_CHECK_EVAL("Object.keys(SoundSource.prototype).join()", "isPlaying,loop,position,positional,repeatCount,sound,volume");
}


OO_TEST(setters)
{
	SetUpContext();
	OO_CHECK_EVAL("(function () { source.loop = 1; return source.loop; })()", "true");
	OO_CHECK_EVAL("(function () { source.positional = 'y'; return source.positional; })()", "true");
	OO_CHECK_EVAL("(function () { source.position = [4, 5, 6]; return source.position; })()", "4,5,6");
	OO_CHECK_EVAL("(function () { source.position = 'here'; return source.position; })()", "threw: bad property value");
	OO_CHECK_EVAL("(function () { source.repeatCount = 7; return source.repeatCount; })()", "7");
	OO_CHECK_EVAL("(function () { source.repeatCount = 500; return source.repeatCount; })()", "100");
	OO_CHECK_EVAL("(function () { source.volume = 0.25; return source.volume; })()", "0.25");
	OO_CHECK_EVAL("(function () { source.volume = 3; return source.volume; })()", "1");
	OO_CHECK_EVAL("(function () { source.volume = -3; return source.volume; })()", "0");
	OO_CHECK_EVAL("(function () { source.sound = null; return source.sound; })()", "null");
	OO_CHECK(sSource->_sound == nullptr);
	OO_CHECK_EVAL("(function () { source.sound = aSound; return source.sound === null; })()", "false");
	OO_CHECK(sSource->_sound.get() == sSound);
	sSource->_gain = 0.5f;
}


OO_TEST(methods)
{
	SetUpContext();
	sSource->_repeatCount = 1;
	int plays = sSource->_plays;
	OO_CHECK_EVAL("source.play()", "undefined");
	OO_CHECK_EQ(sSource->_plays, plays + 1);
	OO_CHECK_EQ(static_cast<int>(sSource->_repeatCount), 1);
	OO_CHECK_EVAL("source.play(3)", "undefined");
	OO_CHECK_EQ(static_cast<int>(sSource->_repeatCount), 3);
	OO_CHECK_EVAL("source.play(1000)", "undefined");
	OO_CHECK_EQ(static_cast<int>(sSource->_repeatCount), 100);
	OO_CHECK_EVAL("source.play(0)", "undefined");	// not positive: the count is left alone
	OO_CHECK_EQ(static_cast<int>(sSource->_repeatCount), 100);
	OO_CHECK_EVAL("source.play(undefined)", "undefined");
	OO_CHECK_EQ(sSource->_plays, plays + 5);
	OO_CHECK_EVAL("source.play({ valueOf: function () { throw new Error('no count'); } })", "threw: bad arguments: SoundSource.play (1): ; expected integer count or no argument");
	OO_CHECK_EVAL("source.isPlaying", "true");
	OO_CHECK_EVAL("source.stop()", "undefined");
	OO_CHECK_EVAL("source.isPlaying", "false");
	int repeats = sSource->_playOrRepeats;
	OO_CHECK_EVAL("source.playOrRepeat()", "undefined");
	OO_CHECK_EQ(sSource->_playOrRepeats, repeats + 1);
	OO_CHECK_EVAL("SoundSource.prototype.stop.call({})", "threw: Native method expected SoundSource, got [object Object].");
	OO_CHECK_EQ(sLimiterPauses, 0);
}


OO_TEST(nativeExceptions)
{
	SetUpContext();
	// The property getter is a native (OOJS_NATIVE_ENTER): a raise from the source is a JS error,
	// and so is a C++ exception.
	sSource->_gain = 0.99f;
	OO_CHECK_EVAL("source.volume", "threw: Native exception: gain boom");
	sSource->_gain = 0.98f;
	OO_CHECK_EVAL("source.volume", "threw: Native exception: cxx boom");
	sSource->_gain = 0.5f;
	OO_CHECK_EVAL("source.volume", "0.5");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
}


OO_TEST_MAIN()
