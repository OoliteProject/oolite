/*	test_OOJSSoundSource.mm
	Unit tests for the SoundSource JS binding (src/Core/Scripting/OOJSSoundSource.h/.mm) and the
	bodies of its OOSoundSource category (the Scripting bridge file until bead oo-9ht.88 deleted
	it with the source's facade): bead oo-cib0, converted the way bead oo-ppc converted OOJSVector
	(proposed ADR-0056 amendments oo-ppc and oo-ykoy).

	As test_OOJSWormhole.mm does (amendment oo-ykoy, item 4), it runs the JS class in a real
	context on the game's own façade backend (ooscript/JSEngine_quickjs.cpp), links the game's own
	objects for the binding and the engine's exception translator (OOJSEngineNativeWrappers.mm), and
	stands in for the classes the binding calls (the source and the sound answer only what the
	binding asks), for the Sound and Vector3D conversions (a vector is the array [x, y, z] here)
	and for the engine functions it links against, with the engine headers' linkage. The
	expectations were written against the Objective-C file and run on it first; they pin the
	JS-visible behaviour (construction, the seven properties and their clamps, play(), stop(),
	playOrRepeat(), a native's exception) and what the category answered the engine. Since beads
	oo-9ht.88 and oo-9ht.68 deleted the source's and the sound's facades the two are C++ stand-ins
	(their members over a record per object), the category's answers are the functions that held
	its bodies, and the engine's C++ private-slot glue (OOJSPrivateObject.h) is stood in for as its
	Objective-C getter, finalizer and toString() were (standing approval oo-9n5p9).
	Run: bash tools/check-core-tests.sh
*/

#include "OOCocoa.h"
#include "oofnd/objc/OOObject.h"
#include "OOMaths.h"
#include "ooscript/JSEngine.hpp"
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"


// MARK: The classes, as far as the binding sees them ----------------------------------------------

#include "OOSoundSource.h"
#include "OOJSPrivateObject.h"
#include "OOJSSoundSource.h"

#include "oo_test.hpp"

#include <cstdarg>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>


// The sound: an object the binding hands on (the root's members its vtable names; OOALSound.mm is
// not linked). A C++ stand-in since bead oo-9ht.68 deleted the facade this file stubbed.
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


/*	The source: a C++ stand-in since bead oo-9ht.88 deleted the facade this file stubbed. Its
	members answer from a record per source (its ivars were the stub's). A source whose gain is 0.99
	raises from gain(), one whose gain is 0.98 throws a C++ exception, so the test sees what an
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


namespace {
std::map<ooscript::ClassDef *, int> sConverters;
ooscript::ClassDef sFakeSoundClass = { "Sound", ooscript::ClassFlag::HasPrivate };
} // namespace


extern "C" {

void OOJSReportBadPropertySelector(ooscript::Context context, ooscript::Object, ooscript::PropertyId, ooscript::PropertySpec *)
{
	cxx_OOJSReportError(context, "bad property selector");
}


void OOJSReportBadPropertyValue(ooscript::Context context, ooscript::Object, ooscript::PropertyId, ooscript::PropertySpec *, ooscript::Value)
{
	cxx_OOJSReportError(context, "bad property value");
}


void OOJSRegisterObjectConverter(ooscript::ClassDef *theClass, oo::PList (*)(ooscript::Context, ooscript::Object))
{
	sConverters[theClass]++;
}


BOOL OOJSIsSubclass(ooscript::ClassDef *putativeSubclass, ooscript::ClassDef *superclass)
{
	return putativeSubclass == superclass;
}


// A vector is the array [x, y, z] here: enough to see what the binding hands over and takes.
bool VectorToJSValue(ooscript::Context context, Vector vector, ooscript::Value *outValue)
{
	ooscript::Value parts[3] = { ooscript::numberValue(vector.x), ooscript::numberValue(vector.y), ooscript::numberValue(vector.z) };
	ooscript::Object array = ooscript::newArrayObject(context, 3, parts);
	if (array == nullptr)  return false;
	*outValue = ooscript::objectValue(array);
	return true;
}


bool JSValueToVector(ooscript::Context context, ooscript::Value value, Vector *outVector)
{
	double v[3] = {};
	ooscript::Value element;
	if (!ooscript::isObject(value) || !ooscript::isArrayObject(context, ooscript::toObject(value)))  return false;
	for (int i = 0; i < 3; i++)
	{
		if (!ooscript::getElement(context, ooscript::toObject(value), i, &element) || !ooscript::valueToNumber(context, element, &v[i]))  return false;
	}
	*outVector = make_vector(v[0], v[1], v[2]);
	return true;
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


// A sound's JS value, as the Sound binding gives it: a JS Sound holding the sound (OOJSSound.mm is
// not linked); null for none.
ooscript::Value OOJSSoundJSValueInContext(OOSound *sound, ooscript::Context context)
{
	if (sound == nullptr)  return ooscript::nullValue();
	ooscript::Object object = ooscript::newObject(context, &sFakeSoundClass, nullptr, nullptr);
	if (object == nullptr || !ooscript::setPrivate(context, object, sound))  return ooscript::nullValue();
	return ooscript::objectValue(object);
}


// A JS Sound's sound, or null for anything else (a name is not looked up here). C linkage, as
// OOJSSound.h declares it.
extern "C" OOSound *SoundFromJSValue(ooscript::Context context, ooscript::Value value);
extern "C" OOSound *SoundFromJSValue(ooscript::Context context, ooscript::Value value)
{
	if (!ooscript::isObject(value) || ooscript::toObject(value) == nullptr)  return nullptr;
	if (ooscript::getObjectClass(context, ooscript::toObject(value)) != &sFakeSoundClass)  return nullptr;
	return static_cast<OOSound *>(ooscript::getPrivate(context, ooscript::toObject(value)));
}


/*	The engine's C++ private-slot glue (OOJSPrivateObject.cpp), stood in for as its Objective-C
	counterparts were: the slot holds the object retained; the getter checks the JS class and gives
	the slot's object; the finalizer does nothing (as the stub's did); toString() is the shared
	one's answer here.
*/
bool OOJSSetCxxPrivate(ooscript::Context context, ooscript::Object jsObject, oo::RefCounted *object)
{
	if (object != nullptr)  object->retain();
	if (ooscript::setPrivate(context, jsObject, object))  return true;
	if (object != nullptr)  object->release();
	return false;
}


bool OOJSGetCxxPrivateImpl(ooscript::Context context, ooscript::Object object, ooscript::ClassDef *requiredJSClass, oo::RefCounted **outObject)
{
	ooscript::ClassDef *actualClass = const_cast<ooscript::ClassDef *>(ooscript::getObjectClass(context, object));
	if (!OOJSIsSubclass(actualClass, requiredJSClass))
	{
		cxx_OOJSReportError(context, "Native method expected %s, got %s.", requiredJSClass->name, cxx_OOStringFromJSValue(context, ooscript::objectValue(object)).value_or("(null)").c_str());
		return false;
	}
	*outObject = static_cast<oo::RefCounted *>(ooscript::getPrivate(context, object));
	return true;
}


void OOJSCxxObjectWrapperFinalize(ooscript::Context, ooscript::Object)
{
}


bool OOJSCxxObjectWrapperToString(ooscript::Context context, ooscript::CallArgs &args, ooscript::ClassDef *)
{
	std::string text = "[SoundSource]";
	args.setRval(ooscript::stringValue(ooscript::newStringCopyN(context, text.data(), text.size())));
	return true;
}


// MARK: The context -------------------------------------------------------------------------------

namespace {

ooscript::Runtime sRuntime;
ooscript::Context sContext;
ooscript::Object sGlobal;
OOSoundSource *sSourceObject = nullptr;	// the source the tests ask through `source`
SourceRecord *sSource = nullptr;		// what it was asked
TestSound *sSound = nullptr;


void Define(const char *name, ooscript::Value value)
{
	ooscript::setProperty(sContext, sGlobal, name, &value);
}


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = ooscript::newRuntime(8u * 1024u * 1024u);
	sContext = ooscript::newContext(sRuntime, 8192);
	ooscript::beginRequest(sContext);
	sGlobal = ooscript::getGlobalObject(sContext);
	ooscript::initStandardClasses(sContext, sGlobal);
	ooscript::initClass(sContext, sGlobal, nullptr, &sFakeSoundClass, nullptr, 0, nullptr, nullptr, nullptr, nullptr);
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
	OO_CHECK_EVAL("typeof SoundSource", "function");
	OO_CHECK_EQ(sConverters.size(), 1u);
	OO_CHECK(OOJSSoundSourceJSClassName() == std::optional<std::string>("SoundSource"));
	// -oo_jsValueInContext: makes a new SoundSource object each time, holding the source retained.
	const std::uint32_t before = sSourceObject->retainCount();
	ooscript::Value a = OOJSSoundSourceJSValueInContext(sSourceObject, sContext);
	ooscript::Value b = OOJSSoundSourceJSValueInContext(sSourceObject, sContext);
	OO_CHECK(ooscript::isObject(a) && ooscript::isObject(b) && ooscript::toObject(a) != ooscript::toObject(b));
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
	OO_CHECK(ooscript::isInRequest(sContext));
}


OO_TEST_MAIN()
