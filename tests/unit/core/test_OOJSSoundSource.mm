/*	test_OOJSSoundSource.mm
	Unit tests for the SoundSource JS binding (src/Core/Scripting/OOJSSoundSource.h/.mm) and its
	OOSoundSource category (OOJSSoundSource+ObjCBridge.mm): bead oo-cib0, converted the way bead
	oo-ppc converted OOJSVector (proposed ADR-0056 amendments oo-ppc and oo-ykoy).

	As test_OOJSWormhole.mm does (amendment oo-ykoy, item 4), it runs the JS class in a real
	QuickJS-ng context, links the game's own objects for the binding, its bridge, the engine's
	class registry (OOJSClasses.mm) and its exception translator (OOJSEngineNativeWrappers.mm),
	and stands in for the classes the binding messages (OOSoundSource
	and OOSound answer only the selectors the binding sends), for the Sound and Vector3D
	conversions (a vector is the array [x, y, z] here) and for the engine functions it links
	against, with the engine headers' linkage. The expectations were written against the
	Objective-C file and run on it first; they pin the JS-visible behaviour (construction, the seven
	properties and their clamps, play(), stop(), playOrRepeat(), a native's exception) and what the
	category answers the engine. Run: tests/run.sh unit
*/

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"
#include <objc/runtime.h>
#include "OOMaths.h"
#include "OOJSEngineCore.h"
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"


// MARK: The classes, as far as the binding sees them ----------------------------------------------

@interface OOSound: OOObject
{
@public
	std::string _name;
}
@end

/*	A source whose gain is 0.99 raises from -gain, one whose gain is 0.98 throws a C++ exception,
	so the test sees what an exception under a native becomes.
*/
@interface OOSoundSource: OOObject
{
@public
	OOSound *_sound;
	BOOL _loop;
	uint8_t _repeatCount;
	BOOL _playing;
	BOOL _positional;
	Vector _position;
	float _gain;
	int _plays;
	int _playOrRepeats;
	int _stops;
}
- (OOSound *) sound;
- (void) setSound:(OOSound *)inSound;
- (BOOL) loop;
- (void) setLoop:(BOOL)inLoop;
- (uint8_t) repeatCount;
- (void) setRepeatCount:(uint8_t)inCount;
- (BOOL) isPlaying;
- (void) play;
- (void) playOrRepeat;
- (void) stop;
- (void) setPositional:(BOOL)inPositional;
- (BOOL) positional;
- (void) setPosition:(Vector)inPosition;
- (Vector) position;
- (void) setGain:(float)gain;
- (float) gain;
@end

@interface OOSoundSource (OOJavaScriptExtentions)
- (JSValue) oo_jsValueInContext:(JSContext *)context;
- (std::optional<std::string>) cxx_oo_jsClassName;
@end


#import "OOJSSoundSource.h"

#include "oo_test.hpp"

#include <cmath>
#include <cstdarg>
#include <cstdint>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>


@implementation OOSound
@end


@implementation OOSoundSource

- (OOSound *) sound  { return _sound; }
- (void) setSound:(OOSound *)inSound  { [_sound release]; _sound = [inSound retain]; }
- (BOOL) loop  { return _loop; }
- (void) setLoop:(BOOL)inLoop  { _loop = inLoop; }
- (uint8_t) repeatCount  { return _repeatCount; }
- (void) setRepeatCount:(uint8_t)inCount  { _repeatCount = inCount; }
- (BOOL) isPlaying  { return _playing; }
- (void) play  { _plays++; _playing = YES; }
- (void) playOrRepeat  { _playOrRepeats++; _playing = YES; }
- (void) stop  { _stops++; _playing = NO; }
- (void) setPositional:(BOOL)inPositional  { _positional = inPositional; }
- (BOOL) positional  { return _positional; }
- (void) setPosition:(Vector)inPosition  { _position = inPosition; }
- (Vector) position  { return _position; }
- (void) setGain:(float)gain  { _gain = gain; }

- (float) gain
{
	if (_gain == 0.99f)  [OOException raise:OOInvalidArgumentException format:"gain %s", "boom"];
	if (_gain == 0.98f)  throw std::runtime_error("cxx boom");
	return _gain;
}

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
// -oo_jsValueInContext: for a sound source, a JS Sound holding the sound for a sound.
JSValue OOJSValueFromNativeObject(JSContext *context, id object)
{
	if (object == nil)  return JS_NULL;
	if ([object isKindOfClass:[OOSoundSource class]])  return [(OOSoundSource *)object oo_jsValueInContext:context];
	JSValue sound = JS_NewObjectClass(context, static_cast<int>(sFakeSoundClassID));
	if (JS_IsException(sound))
	{
		JS_FreeValue(context, JS_GetException(context));
		return JS_NULL;
	}
	JS_SetOpaque(sound, [object retain]);
	return sound;
}


// A JS Sound's sound, or nil for anything else (a name is not looked up here).
OOSound *SoundFromJSValue(JSContext *, JSValueConst value)
{
	if (!JS_IsObject(value) || JS_GetClassID(value) != sFakeSoundClassID)  return nil;
	return (OOSound *)JS_GetOpaque(value, sFakeSoundClassID);
}


JSValue OOJSObjectWrapperToString(JSContext *context, JSValueConst, int, JSValueConst *)
{
	return JS_NewString(context, "[SoundSource]");
}


// The test's sources live for the whole test; nothing is released when their objects go.
void OOJSObjectWrapperFinalize(JSRuntime *, JSValueConst)
{
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


oo::PList OOJSBasicPrivateObjectConverter(JSContext *, JSValueConst)
{
	return oo::PList();
}


// MARK: The context -------------------------------------------------------------------------------

namespace {

JSRuntime *sRuntime;
JSContext *sContext;
JSValue sGlobal = JS_UNDEFINED;	// owned for the life of the test
OOSoundSource *sSource = nil;
OOSound *sSound = nil;


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

	sSound = [[OOSound alloc] init];	// kept for the life of the test
	sSound->_name = "ping";
	sSource = [[OOSoundSource alloc] init];
	sSource->_sound = [sSound retain];
	sSource->_repeatCount = 1;
	sSource->_position = make_vector(1, 2, 3);
	sSource->_gain = 0.5f;
	Define("source", [sSource oo_jsValueInContext:sContext]);
	Define("aSound", OOJSValueFromNativeObject(sContext, sSound));
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
	OO_CHECK([sSource cxx_oo_jsClassName] == std::optional<std::string>("SoundSource"));
	// -oo_jsValueInContext: makes a new SoundSource object each time, holding the source retained.
	NSUInteger before = [sSource retainCount];
	JSValue a = [sSource oo_jsValueInContext:sContext];
	JSValue b = [sSource oo_jsValueInContext:sContext];
	OO_CHECK(JS_IsObject(a) && JS_IsObject(b) && JS_VALUE_GET_PTR(a) != JS_VALUE_GET_PTR(b));
	JSClassID ignored;
	OO_CHECK(JS_GetAnyOpaque(a, &ignored) == sSource);
	OO_CHECK_EQ([sSource retainCount], before + 2);
	JS_FreeValue(sContext, a);
	JS_FreeValue(sContext, b);
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
	OO_CHECK(sSource->_sound == nil);
	OO_CHECK_EVAL("(function () { source.sound = aSound; return source.sound === null; })()", "false");
	OO_CHECK(sSource->_sound == sSound);
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
