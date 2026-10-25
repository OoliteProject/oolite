/*

OOJSSoundSource.mm

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#include "OOJSSoundSource.h"
#include "OOJSSound.h"
#include "OOJSVector.h"
#include "OOJavaScriptEngine.h"
#include "OOJSPrivateObject.h"
#include "OOSound.h"
#include "ResourceManager.h"

#include "ooscript/JSEngine.hpp"
#include "oofnd/String.hpp"
#include <cstring>

/*
	Retargeted onto the ooscript façade (JSEngine.hpp) the way OOJSVector.mm does it (bead
	oo-sdz, the sweep exemplar): the class dispatch table becomes a static ooscript::ClassDef
	(the stub hooks are nullptr), InitClass becomes ooscript::initClass, and the directly
	spelled construction-check, object-construction, private-storage and boolean/integer/
	numeric-conversion calls become ooscript::isConstructing (via CallArgs), ooscript::newObject,
	ooscript::setPrivate, ooscript::valueToBoolean, ooscript::valueToInt32 and
	ooscript::newNumberValue/valueToNumber. `this` is renamed to `thisObj` because it is a
	reserved word once this file compiles as Objective-C++ (ADR-0001).

	Natives and class hooks take the façade signature directly; the shared
	OOJSObjectWrapperToString and OOJSObjectWrapperFinalize natives are used as-is in the class
	and method tables.
*/

/*
	C++20 since bead oo-cib0, converted the way bead oo-ppc converted OOJSVector.mm (proposed
	ADR-0056 amendment oo-ppc). The JS class was already C++ on the ooscript façade;
	OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
	(OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. The category on OOSoundSource
	became two free functions, and its methods moved to the Scripting bridge file (amendment
	oo-ykoy). Beads oo-9ht.88 and oo-9ht.68 deleted the source's and the sound's facades and that
	file: both are C++, and a SoundSource object's private slot holds an OOJSSoundSourceHolder of the source
	(amendment oo-6symp; ADR-0056 amendment oo-9ht.68).
*/

namespace ooscript { }
using ooscript::Context;
using ooscript::Object;
using ooscript::Value;
using ooscript::PropertyId;
using ooscript::CallArgs;
using ooscript::ClassDef;
using ooscript::ClassFlag;
using ooscript::PropertyFlag;
using ooscript::PropertySpec;
using ooscript::FunctionSpec;


namespace {
static ooscript::Object sSoundSourcePrototype;
} // namespace


namespace {
static bool SoundSourceGetProperty(Context cx, Object obj, PropertyId propID, Value *value);
} // namespace
namespace {
static bool SoundSourceSetProperty(Context cx, Object obj, PropertyId propID, bool strict, Value *value);
} // namespace
namespace {
static bool SoundSourceConstruct(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace

// Methods
namespace {
static bool SoundSourceToString(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool SoundSourcePlay(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool SoundSourceStop(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool SoundSourcePlayOrRepeat(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace


namespace {
static ClassDef sSoundSourceClass =
{
	"SoundSource",
	ClassFlag::HasPrivate,

	nullptr,				// addProperty (engine default: PropertyStub)
	nullptr,				// delProperty (engine default: PropertyStub)
	SoundSourceGetProperty,	// getProperty
	SoundSourceSetProperty,	// setProperty
	nullptr,				// enumerate (engine default: EnumerateStub)
	nullptr,				// newEnumerate (ooscript::ClassFlag::NewEnumerate not used)
	nullptr,				// resolve (engine default: ResolveStub)
	nullptr,				// convert (engine default: ConvertStub)
	OOJSCxxObjectWrapperFinalize,	// finalize
	nullptr,				// call
	nullptr,				// construct
	nullptr,				// backend: owned by the façade backend, must start null
};
} // namespace


enum : std::uint8_t
{
	// Property IDs
	kSoundSource_sound,
	kSoundSource_isPlaying,
	kSoundSource_loop,
	kSoundSource_position,
	kSoundSource_positional,
	kSoundSource_repeatCount,
	kSoundSource_volume
};


namespace {
static PropertySpec sSoundSourceProperties[] =
{
	// JS name					ID							flags								getter	setter
	{ "isPlaying",				kSoundSource_isPlaying,		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "loop",					kSoundSource_loop,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared,	nullptr, nullptr },
	{ "position",				kSoundSource_position,		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared,	nullptr, nullptr },
	{ "positional",				kSoundSource_positional,	PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared,	nullptr, nullptr },
	{ "repeatCount",			kSoundSource_repeatCount,	PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared,	nullptr, nullptr },
	{ "sound",					kSoundSource_sound,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared,	nullptr, nullptr },
	{ "volume",					kSoundSource_volume,		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared,	nullptr, nullptr },
	{ 0 }
};
} // namespace


namespace {
static FunctionSpec sSoundSourceMethods[] =
{
	// JS name					Function					min args	flags
	{ "toString",				SoundSourceToString,		0,			0 },
	{ "play",					SoundSourcePlay,			0,			0 },
	{ "playOrRepeat",			SoundSourcePlayOrRepeat,	0,			0 },
	// playSound is defined in oolite-global-prefix.js.
	{ "stop",					SoundSourceStop,			0,			0 },
	{ 0 }
};
} // namespace


// OOJSSoundSourceHolder (OOJSSoundSource.h): the JS glue of a SoundSource object's slot.
OOJSSoundSourceHolder::OOJSSoundSourceHolder(OOSoundSource *inSource) : _source(inSource) {}
OOJSSoundSourceHolder::~OOJSSoundSourceHolder() = default;
OOSoundSource *OOJSSoundSourceHolder::source() const  { return _source.get(); }
ooscript::Value OOJSSoundSourceHolder::jsValueInContext(ooscript::Context context)  { return OOJSSoundSourceJSValueInContext(_source.get(), context); }
void OOJSSoundSourceHolder::clearJSSelf(ooscript::Object)  {}	// no wrapper is kept

std::optional<std::string> OOJSSoundSourceHolder::jsDescription()
{
	const std::optional<std::string> components = _source->descriptionComponents();
	if (components.has_value())  return oo::str::format("[SoundSource %s]", components->c_str());
	return std::string("[object SoundSource]");
}


namespace {
// DEFINE_JS_OBJECT_GETTER's equivalent for the slot's holder (OOJSPrivateObject.h): the source, or
// null for SoundSource.prototype, which has none.
static bool JSSoundSourceGetSoundSource(ooscript::Context context, ooscript::Object object, OOSoundSource **outSource)
{
	OOJSSoundSourceHolder *holder = nullptr;
	if (!OOJSGetCxxPrivate(context, object, &sSoundSourceClass, &holder))  return false;
	*outSource = (holder != nullptr) ? holder->source() : nullptr;
	return true;
}


// The class's converter: the slot held the source's facade, which OOJSBasicPrivateObjectConverter
// handed to Objective-C callers of OOJSNativeObjectFromJSValue. No Objective-C object is left to
// hand over (bead oo-9ht.88), and nothing asks for one.
static oo::PList SoundSourceConverter(ooscript::Context, ooscript::Object)
{
	return oo::PList();
}
} // namespace


// *** Public ***

void InitOOJSSoundSource(ooscript::Context context, ooscript::Object global)
{
	Object proto = ooscript::initClass((context), (global), nullptr, &sSoundSourceClass, SoundSourceConstruct, 0, sSoundSourceProperties, sSoundSourceMethods, nullptr, nullptr);
	sSoundSourcePrototype = (proto);
	OOJSRegisterObjectConverter(&sSoundSourceClass, SoundSourceConverter);
}


namespace {
static bool SoundSourceConstruct(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{

	OOJS_NATIVE_ENTER(context)

	if (EXPECT_NOT(!oojsArgs.isConstructing()))
	{
		cxx_OOJSReportError(context, "SoundSource() cannot be called as a function, it must be used as a constructor (as in new SoundSource()).");
		return false;
	}

	const oo::Ref<OOSoundSource> source = oo::makeRef<OOSoundSource>();	// [[[OOSoundSource alloc] init] autorelease]
	OOJS_RETURN(OOJSSoundSourceJSValueInContext(source.get(), context));

	OOJS_NATIVE_EXIT
}
} // namespace


// *** Implementation stuff ***

namespace {
static bool SoundSourceGetProperty(Context cx, Object obj, PropertyId propID, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;

	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);

	OOJS_NATIVE_ENTER(context)

	OOSoundSource				*soundSource = nullptr;	// null for SoundSource.prototype

	if (!JSSoundSourceGetSoundSource(context, thisObj, &soundSource))  return false;

	switch (ooscript::idToInt32(propID))
	{
		// (Each answers what a message to nil did for the prototype, which has no source.)
		case kSoundSource_sound:
			*value = OOJSSoundJSValueInContext((soundSource != nullptr) ? soundSource->sound() : nullptr, context);
			return true;

		case kSoundSource_isPlaying:
			*value = OOJSValueFromBOOL(soundSource != nullptr && soundSource->isPlaying());
			return true;

		case kSoundSource_loop:
			*value = OOJSValueFromBOOL(soundSource != nullptr && soundSource->loop());
			return true;

		case kSoundSource_repeatCount:
			*value = ooscript::int32Value((soundSource != nullptr) ? soundSource->repeatCount() : 0);
			return true;

		case kSoundSource_position:
			return VectorToJSValue(context, (soundSource != nullptr) ? soundSource->position() : Vector{}, value);	// a zeroed struct, as from nil

		case kSoundSource_positional:
			*value = OOJSValueFromBOOL(soundSource != nullptr && soundSource->positional());
			return true;

		case kSoundSource_volume:
			return ooscript::newNumberValue(cx, (soundSource != nullptr) ? soundSource->gain() : 0.0f, value);


		default:
			OOJSReportBadPropertySelector(context, thisObj, (propID), sSoundSourceProperties);
			return false;
	}

	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool SoundSourceSetProperty(Context cx, Object obj, PropertyId propID, bool /*strict*/, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;

	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);

	OOJS_NATIVE_ENTER(context)

	OOSoundSource				*soundSource = nullptr;	// null for SoundSource.prototype
	int32_t						iValue;
	bool						bValue;
	Vector						vValue;
	double						fValue;

	if (!JSSoundSourceGetSoundSource(context, thisObj, &soundSource)) return false;

	switch (ooscript::idToInt32(propID))
	{
		case kSoundSource_sound:
			if (soundSource != nullptr)  soundSource->setSound(SoundFromJSValue(context, *value));
			return true;
			break;

		case kSoundSource_loop:
			if (ooscript::valueToBoolean(cx, *value, &bValue))
			{
				if (soundSource != nullptr)  soundSource->setLoop(bValue);
				return true;
			}
			break;

		case kSoundSource_repeatCount:
			if (ooscript::valueToInt32(cx, *value, &iValue))
			{
				if (iValue > 100)  iValue = 100;
				if (100 < 1)  iValue = 1;
				if (soundSource != nullptr)  soundSource->setRepeatCount(iValue);
				return true;
			}
			break;


		case kSoundSource_position:
			if (JSValueToVector(context, *value, &vValue))
			{
				if (soundSource != nullptr)  soundSource->setPosition(vValue);
				return true;
			}
			break;

		case kSoundSource_positional:
			if (ooscript::valueToBoolean(cx, *value, &bValue))
			{
				if (soundSource != nullptr)  soundSource->setPositional(bValue);
				return true;
			}
			break;

		case kSoundSource_volume:
			if (ooscript::valueToNumber(cx, *value, &fValue))
			{
				fValue = OOClamp_0_max_d(fValue, 1);
				if (soundSource != nullptr)  soundSource->setGain(fValue);
				return true;
			}
			break;

		default:
			OOJSReportBadPropertySelector(context, thisObj, (propID), sSoundSourceProperties);
			return false;
	}

	OOJSReportBadPropertyValue(context, thisObj, (propID), sSoundSourceProperties, *value);
	return false;

	OOJS_NATIVE_EXIT
}
} // namespace


// *** Methods ***

// toString() : String
namespace {
static bool SoundSourceToString(ooscript::Context cx, ooscript::CallArgs &oojsArgs)
{
	return OOJSCxxObjectWrapperToString(cx, oojsArgs, &sSoundSourceClass);
}
} // namespace


// play([count : Number])
namespace {
static bool SoundSourcePlay(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)

	OOSoundSource			*thisv = nullptr;	// null for SoundSource.prototype
	int32_t					count = 0;

	if (EXPECT_NOT(!JSSoundSourceGetSoundSource(context, OOJS_THIS, &thisv)))  return false;
	if (oojsArgs.count() > 0 && !ooscript::isUndefined(OOJS_ARGV[0]) && !ooscript::valueToInt32(context, (OOJS_ARGV[0]), &count))
	{
		cxx_OOJSReportBadArguments(context, "SoundSource", "play", 1, OOJS_ARGV, std::nullopt, "integer count or no argument");
		return false;
	}

	if (count > 0)
	{
		if (count > 100)  count = 100;
		if (thisv != nullptr)  thisv->setRepeatCount(count);
	}

	OOJS_BEGIN_FULL_NATIVE(context)
	if (thisv != nullptr)  thisv->play();
	OOJS_END_FULL_NATIVE

	OOJS_RETURN_VOID;

	OOJS_NATIVE_EXIT
}
} // namespace


// stop()
namespace {
static bool SoundSourceStop(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{

	OOJS_NATIVE_ENTER(context)

	OOSoundSource			*thisv = nullptr;	// null for SoundSource.prototype

	if (EXPECT_NOT(!JSSoundSourceGetSoundSource(context, OOJS_THIS, &thisv)))  return false;

	OOJS_BEGIN_FULL_NATIVE(context)
	if (thisv != nullptr)  thisv->stop();
	OOJS_END_FULL_NATIVE

	OOJS_RETURN_VOID;

	OOJS_NATIVE_EXIT
}
} // namespace


// playOrRepeat()
namespace {
static bool SoundSourcePlayOrRepeat(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{

	OOJS_NATIVE_ENTER(context)

	OOSoundSource			*thisv = nullptr;	// null for SoundSource.prototype

	if (EXPECT_NOT(!JSSoundSourceGetSoundSource(context, OOJS_THIS, &thisv)))  return false;

	OOJS_BEGIN_FULL_NATIVE(context)
	if (thisv != nullptr)  thisv->playOrRepeat();
	OOJS_END_FULL_NATIVE

	OOJS_RETURN_VOID;

	OOJS_NATIVE_EXIT
}
} // namespace


// The bodies of OOSoundSource (OOJavaScriptExtentions), whose methods were in
// the Scripting bridge file until bead oo-9ht.88 deleted the source's facade (proposed ADR-0056
// amendments oo-ppc and oo-ykoy). A null source is JS null, as OOJSValueFromNativeObject() answered
// nil.
ooscript::Value OOJSSoundSourceJSValueInContext(OOSoundSource *source, ooscript::Context context)
{
	ooscript::Object jsSelf = NULL;
	ooscript::Value						result = ooscript::nullValue();

	if (source == nullptr)  return result;

	jsSelf = (ooscript::newObject((context), &sSoundSourceClass, (sSoundSourcePrototype), nullptr));
	if (jsSelf != NULL)
	{
		const oo::Ref<OOJSSoundSourceHolder> holder = oo::makeRef<OOJSSoundSourceHolder>(source);
		if (!OOJSSetCxxPrivate(context, jsSelf, holder.get()))  jsSelf = NULL;
	}
	if (jsSelf != NULL)  result = ooscript::objectValue(jsSelf);

	return result;
}

std::optional<std::string> OOJSSoundSourceJSClassName(void)
{
	return std::string("SoundSource");
}
