/*

OOJSSystemInfo.mm

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

#include "OOJSSystemInfo.h"
#include "OOJavaScriptEngine.h"
#include "PlayerEntityScriptMethods.h"
#include "Universe.h"
#include "OOJSVector.h"
#include "OOIsNumberLiteral.h"
#include "OOConstToString.h"
#include "OOSystemDescriptionManager.h"
#include "OOCommodities.h"
#include "OOTypes.h"	// OOCreditsQuantity (ADR-0063 item 5 samplePrice)
#include "OOJSScript.h"

#include "ooscript/JSEngine.hpp"
#include <cstring>
#include "oofnd/objc/OOAssert.h"
#include "OOObjCPList.h"
#include "oofnd/String.hpp"

/*
	Retargeted onto the ooscript façade (JSEngine.hpp) the way OOJSVector.mm does it (bead
	oo-sdz, the sweep exemplar): the class dispatch table becomes a static ooscript::ClassDef
	(the stub hooks are nullptr), the engine's own InitClass entry point becomes
	ooscript::initClass, native methods and class hooks take the façade's hook signature
	(Context/Object/PropertyId/Value pointer/CallArgs reference), and the directly spelled
	object-creation, numeric-conversion, property-id and function-call engine entry points
	become their ooscript:: façade equivalents. Natives take the
	façade signature directly (ooscript::Context and a CallArgs reference) and the OOJS_*
	argument-marshalling macros expand to the CallArgs accessors, so the rest of each function
	body is UNCHANGED. `this` is
	renamed to `thisObj` because it is a reserved word once this file compiles as Objective-C++
	(ADR-0001).

	SystemInfo is registered as an object converter with &sSystemInfoClass, the same
	ooscript::ClassDef that ooscript::getClass() reports for its instances.
*/
/*
	C++20 since bead oo-6ia4, converted the way bead oo-ppc converted OOJSVector.mm (proposed
	ADR-0056 amendment oo-ppc). The JS class was already C++ on the ooscript façade;
	OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
	(OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. OOSystemInfo, the class a
	SystemInfo wraps, is OOSystemInfo (OOJSSystemInfo.h), which the JS private slot holds; its
	-initWithGalaxy:system: is a factory that answers null (amendment oo-novu). The natives
	null-guard where a message to nil answered, and OOSystemDescriptionManager and
	OOCommodities, which are C++ since beads oo-0sr1 and oo-fqyw, are reached the same way
	(amendment oo-ppc, item 4). Messages to classes that are still Objective-C (Universe,
	PlayerEntity, OOJSScript) stay as they are, which is why the file is still .mm until Phase 4.
	Since bead oo-6symp.2 (proposed ADR-0056 amendment oo-6symp) the private slot holds the C++
	system info itself, which implements OOJSPrivateObject: the natives read it with
	OOJSGetCxxPrivate, the finalizer and toString() are the engine's OOJSCxxObjectWrapperFinalize
	and OOJSCxxObjectWrapperToString, and the converter answers the object itself, as a oo::PListForeign (bead oo-9ht.95 deleted the
	Objective-C facade).
*/


// The running script's manifest property (-cxx_propertyNamed: of the running OOJSScript, whose
// facades beads oo-9ht.137 and oo-9ht.133 deleted); null for no script, or once a script a timer or
// definition pushed weakly has gone, as the message to nil answered.
namespace {
oo::PList RunningScriptManifest()
{
	OOJSScript *running = OOJSScript::currentlyRunningScript();
	return running != nullptr ? running->propertyNamed(kLocalManifestProperty) : oo::PList();
}
}	// namespace

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
using ooscript::EnumerateOp;

// Byte-identical façade <-> jsapi views, local to this call site (see OOJSVector.mm).
namespace {
static inline Object    *OOJSFOBJP(ooscript::Object *o)  { return reinterpret_cast<Object*>(o); }
} // namespace


namespace {
static ooscript::Object sSystemInfoPrototype;
} // namespace
namespace {
static ooscript::Object sCachedSystemInfo;
} // namespace
namespace {
static OOGalaxyID sCachedGalaxy;
} // namespace
namespace {
static OOSystemID sCachedSystem;
} // namespace


namespace {
static bool SystemInfoDeleteProperty(Context cx, Object obj, PropertyId propID, Value *value);
} // namespace
namespace {
static bool SystemInfoGetProperty(Context cx, Object obj, PropertyId propID, Value *value);
} // namespace
namespace {
static bool SystemInfoSetProperty(Context cx, Object obj, PropertyId propID, bool strict, Value *value);
} // namespace
namespace {
static void SystemInfoFinalize(Context cx, Object obj);
} // namespace
namespace {
static bool SystemInfoToString(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
// The state of a SystemInfo enumeration, kept in the enumeration's private slot (was a retained
// Foundation enumerator over the keys).
struct SystemInfoEnumerationState
{
	std::vector<std::string>	keys;
	std::size_t					next = 0;
};
} // namespace


namespace {
static bool SystemInfoEnumerate(Context cx, Object obj, EnumerateOp enumOp, Value *state, PropertyId *idp);
} // namespace

namespace {
static bool SystemInfoDistanceToSystem(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool SystemInfoRouteToSystem(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool SystemInfoSamplePrice(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool SystemInfoSetPropertyMethod(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace

namespace {
static bool SystemInfoStaticSetInterstellarProperty(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool SystemInfoStaticFilteredSystems(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace

namespace {
static ClassDef sSystemInfoClass =
{
	"SystemInfo",
	ClassFlag::HasPrivate | ClassFlag::NewEnumerate,
	
	nullptr,						// addProperty (engine default: PropertyStub)
	SystemInfoDeleteProperty,		// delProperty
	SystemInfoGetProperty,			// getProperty
	SystemInfoSetProperty,			// setProperty
	nullptr,						// enumerate (ooscript::ClassFlag::NewEnumerate used instead)
	SystemInfoEnumerate,			// newEnumerate
	nullptr,						// resolve (engine default: ResolveStub)
	nullptr,						// convert (engine default: ConvertStub)
	SystemInfoFinalize,				// finalize
	nullptr,						// call
	nullptr,						// construct
	nullptr,						// backend: owned by the façade backend, must start null
};
} // namespace


enum : std::uint8_t
{
	// Property IDs
	kSystemInfo_coordinates,	// system coordinates (in LY), Vector3D (with z = 0), read-only
	kSystemInfo_internalCoordinates,	// system coordinates (unscaled), Vector3D (with z = 0), read-only
	kSystemInfo_galaxyID,		// galaxy number, integer, read-only
	kSystemInfo_systemID		// system number, integer, read-only
};


namespace {
static PropertySpec sSystemInfoProperties[] =
{
	// JS name					ID									flags								getter	setter
	{ "coordinates",			kSystemInfo_coordinates,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared,	nullptr, nullptr },
	{ "internalCoordinates",	kSystemInfo_internalCoordinates,	PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared,	nullptr, nullptr },
	{ "galaxyID",				kSystemInfo_galaxyID,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared,	nullptr, nullptr },
	{ "systemID",				kSystemInfo_systemID,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared,	nullptr, nullptr },
	{ 0 }
};
} // namespace


// A raw jsapi mirror of sSystemInfoProperties, used only for the bad-property error reporter
// in OOJavaScriptEngine.m (OOJSReportBadPropertySelector): that helper is outside this bead's
// scope (shared across every binding file) and still takes a ooscript::PropertySpec*, not
// ooscript::PropertySpec* (see OOJSVector.mm for the same pattern).
namespace {
static ooscript::PropertySpec sSystemInfoPropertiesRaw[] =
{
	// JS name					ID									flags
	{ "coordinates",			kSystemInfo_coordinates,			OOJS_PROP_READONLY_CB },
	{ "internalCoordinates",	kSystemInfo_internalCoordinates,	OOJS_PROP_READONLY_CB },
	{ "galaxyID",				kSystemInfo_galaxyID,				OOJS_PROP_READONLY_CB },
	{ "systemID",				kSystemInfo_systemID,				OOJS_PROP_READONLY_CB },
	{ 0 }
};
} // namespace


namespace {
static FunctionSpec sSystemInfoMethods[] =
{
	// JS name					Function					min args	flags
	{ "toString",				SystemInfoToString,				0,			0 },
	{ "distanceToSystem",		SystemInfoDistanceToSystem,		1,			0 },
	{ "routeToSystem",			SystemInfoRouteToSystem,		1,			0 },
	{ "samplePrice",			SystemInfoSamplePrice,			1,			0 },
	{ "setProperty",			SystemInfoSetPropertyMethod,	3,			0 },
	{ 0 }
};
} // namespace


namespace {
static FunctionSpec sSystemInfoStaticMethods[] =
{
	// JS name						Function									min args	flags
	{ "filteredSystems",			SystemInfoStaticFilteredSystems,			2,			0 },
	{ "setInterstellarProperty",	SystemInfoStaticSetInterstellarProperty,	4,			0 },
	{ 0 }
};
} // namespace


namespace {

// A string, or null for none.
oo::PList StringOrNull(const std::optional<std::string> &string)
{
	return string.has_value() ? oo::PList(*string) : oo::PList();
}

// A manifest identifier as the -fromManifest: arguments read it: a string, else none.
std::optional<std::string> ManifestString(const oo::PList &manifest)
{
	if (const std::string *text = manifest.getIf<std::string>())  return *text;
	return std::nullopt;
}

// What a message to a nil OOSystemInfo answered, for the natives that take one from a JS object
// (the prototype has none): 0, the zero point, null.
OOGalaxyID GalaxyOf(OOSystemInfo *info)  { return (info != nullptr) ? info->galaxy() : 0; }
OOSystemID SystemOf(OOSystemInfo *info)  { return (info != nullptr) ? info->system() : 0; }
NSPoint CoordinatesOf(OOSystemInfo *info)  { return (info != nullptr) ? info->coordinates() : NSMakePoint(0, 0); }
oo::PList ValueForKey(OOSystemInfo *info, const std::optional<std::string> &key)  { return (info != nullptr) ? info->valueForKey(key) : oo::PList(); }

// -intValue of a system property (an NSNumber or an NSString; 0 for nil).
int PropertyIntValue(const oo::PList &value)
{
	if (const std::string *text = value.getIf<std::string>())  return oo::plist_get::intValue(oo::utf8ToUtf16(*text));
	return static_cast<int>(value.int64Value());
}

}	// namespace


// DEFINE_JS_OBJECT_GETTER(JSSystemInfoGetSystemInfo, &sSystemInfoClass, sSystemInfoPrototype,
// OOSystemInfo) for the C++ system info the slot holds (bead oo-6symp.2).
namespace {
static bool JSSystemInfoGetSystemInfo(ooscript::Context context, ooscript::Object inObject, OOSystemInfo **outObject)
{
	return OOJSGetCxxPrivate(context, inObject, &sSystemInfoClass, outObject);
}


// The system info of a JS object of the SystemInfo class, else null (as the Objective-C class
// check of OOJSNativeObjectOfClassFromJSObject answered nil).
static OOSystemInfo *SystemInfoOfJSObject(ooscript::Context context, ooscript::Object object)
{
	if (object == nullptr || ooscript::getObjectClass(context, object) != &sSystemInfoClass)  return nullptr;
	return static_cast<OOSystemInfo *>(static_cast<oo::RefCounted *>(ooscript::getPrivate(context, object)));
}
} // namespace


// OOSystemInfo (OOJSSystemInfo.h), the helper class wrapped by JS SystemInfo objects.

OOSystemInfo::OOSystemInfo(OOGalaxyID galaxy, OOSystemID system)
	: _galaxy(galaxy), _system(system), _planetKey(oo::str::format("%u %i", galaxy, system))
{
}


oo::Ref<OOSystemInfo> OOSystemInfo::initWithGalaxy(OOGalaxyID galaxy, OOSystemID system)
{
	if (galaxy > kOOMaximumGalaxyID || system > kOOMaximumSystemID || system < kOOMinimumSystemID)
	{
		return nullptr;
	}

	return oo::adopt(new OOSystemInfo(galaxy, system));
}


std::optional<std::string> OOSystemInfo::descriptionComponents() const
{
	return oo::str::format("galaxy %u, system %i", _galaxy, _system);
}


std::optional<std::string> OOSystemInfo::shortDescriptionComponents() const
{
	return _planetKey;
}


std::optional<std::string> OOSystemInfo::oo_jsClassName() const
{
	return std::string("SystemInfo");
}


bool OOSystemInfo::isEqual(const OOSystemInfo *other) const
{
	return other == this ||
		   (other != nullptr &&
			other->galaxy() == _galaxy &&
			other->system() == _system);

}


NSUInteger OOSystemInfo::hash() const
{
	NSUInteger hash = _galaxy;
	hash <<= 16;
	hash |= (uint16_t)_system;
	return hash;
}


oo::PList OOSystemInfo::valueForKey(const std::optional<std::string> &key)
{
	if ((UNIVERSE != nullptr ? UNIVERSE->inInterstellarSpace() : false) && _system == -1)
	{
		// -objectForKey: (a nil key found nothing)
		const oo::PList systemData = (UNIVERSE != nullptr ? UNIVERSE->currentSystemData() : oo::PList());
		const oo::PList *value = key.has_value() ? systemData.find(*key) : nullptr;
		return (value != nullptr) ? *value : oo::PList();
	}
	return (UNIVERSE != nullptr ? UNIVERSE->systemDataForGalaxy(_galaxy, _system, key.value_or("")) : oo::PList());	// (a nil key as "")
}


void OOSystemInfo::setValue(const oo::PList &value, const std::string &key)
{
	// The running script's manifest identifier, handed on as it was read.
	const oo::PList manifest = RunningScriptManifest();

	if (UNIVERSE != nullptr)  UNIVERSE->setSystemDataForGalaxy(_galaxy, _system, key, value, ManifestString(manifest), OO_LAYER_OXP_DYNAMIC);
}


std::vector<std::string> OOSystemInfo::allKeys()
{
	if ((UNIVERSE != nullptr ? UNIVERSE->inInterstellarSpace() : false) && _system == -1)
	{
		// the dictionary's keys, in key order (-allKeys gave hash order)
		std::vector<std::string> keys;
		// -cxx_currentSystemData answers a copy: keep it alive while the loop reads it (bead oo-f4241).
		const oo::PList systemData = (UNIVERSE != nullptr ? UNIVERSE->currentSystemData() : oo::PList());
		if (const oo::PList::Dict *systemDict = systemData.getIf<oo::PList::Dict>())
		{
			for (const auto &entry : *systemDict)  keys.push_back(entry.first);
		}
		return keys;
	}
	return (UNIVERSE != nullptr ? UNIVERSE->systemDataKeysForGalaxy(_galaxy, _system) : std::vector<std::string>());
}


OOGalaxyID OOSystemInfo::galaxy() const
{
	return _galaxy;
}


OOSystemID OOSystemInfo::system() const
{
	return _system;
}


/*- (Random_Seed) systemSeed
{
	OOAssert([PLAYER currentGalaxyID] == _galaxy, "Attempt to use -[OOSystemInfo systemSeed] from a different galaxy.");
	return [UNIVERSE systemSeedForSystemNumber:_system];
	}*/


NSPoint OOSystemInfo::coordinates()
{
	if ((UNIVERSE != nullptr ? UNIVERSE->inInterstellarSpace() : false) && _system == -1)
	{
		return (PLAYER != nullptr ? PLAYER->PlayerEntity::getGalaxy_coordinates() : NSPoint{});	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
	}
	return (UNIVERSE != nullptr ? UNIVERSE->coordinatesForSystem(_system) : NSPoint{});
}


ooscript::Value OOSystemInfo::jsValueInContext(ooscript::Context context)
{
	ooscript::Object jsSelf = NULL;
	ooscript::Value						result = ooscript::nullValue();

	jsSelf = (ooscript::newObject((context), &sSystemInfoClass, (sSystemInfoPrototype), nullptr));
	if (jsSelf != NULL)
	{
		// The slot holds this, retained (OOJSCxxObjectWrapperFinalize releases it).
		if (!OOJSSetCxxPrivate(context, jsSelf, this))  jsSelf = NULL;
	}
	if (jsSelf != NULL)
	{
		_jsSelf = jsSelf;
		result = ooscript::objectValue(jsSelf);
	}

	return result;
}


void OOSystemInfo::clearJSSelf(ooscript::Object selfVal)
{
	if (_jsSelf == selfVal)  _jsSelf = NULL;
}


// What the facade's -cxx_oo_jsDescription answered (OOObject (OOJavaScriptConversion)): the JS
// class name and the components.
std::string OOSystemInfo::className() const
{
	return "OOSystemInfo";
}


std::string OOSystemInfo::description() const
{
	const std::optional<std::string> components = descriptionComponents();
	return oo::str::format("<OOSystemInfo>{%s}", components.value_or("").c_str());
}


std::optional<std::string> OOSystemInfo::jsDescription()
{
	const std::optional<std::string> components = descriptionComponents();
	const std::string name = oo_jsClassName().value_or("OOSystemInfo");
	if (components.has_value())  return oo::str::format("[%s %s]", name.c_str(), components->c_str());
	return oo::str::format("[object %s]", name.c_str());
}



// OOJSBasicPrivateObjectConverter for the C++ system info the slot holds: the object itself as a
// PList::Object node (null for the prototype).
namespace {
static oo::PList SystemInfoConverter(ooscript::Context context, ooscript::Object object)
{
	OOSystemInfo *info = static_cast<OOSystemInfo *>(static_cast<oo::RefCounted *>(ooscript::getPrivate(context, object)));
	if (info == nullptr)  return oo::PList();
	return oo::PList(oo::PList::Object(oo::Ref<oo::PListForeign>(info)));
}
} // namespace


void InitOOJSSystemInfo(ooscript::Context context, ooscript::Object global)
{
	Object proto = ooscript::initClass((context), (global), nullptr, &sSystemInfoClass, OOJSUnconstructableConstruct, 0, sSystemInfoProperties, sSystemInfoMethods, NULL, sSystemInfoStaticMethods);
	sSystemInfoPrototype = (proto);
	OOJSRegisterObjectConverter(&sSystemInfoClass, SystemInfoConverter);
}


ooscript::Value GetJSSystemInfoForSystem(ooscript::Context context, OOGalaxyID galaxy, OOSystemID system)
{
	OOJS_PROFILE_ENTER
	
	// Use cached object if possible.
	if (sCachedSystemInfo != NULL &&
		sCachedGalaxy == galaxy &&
		sCachedSystem == system)
	{
		return ooscript::objectValue(sCachedSystemInfo);
	}
	
	// If not, create a new one.
	oo::Ref<OOSystemInfo> info;
	ooscript::Value result;
	OOJS_BEGIN_FULL_NATIVE(context)
	info = OOSystemInfo::initWithGalaxy(galaxy, system);	// null for a galaxy or system out of range
	OOJS_END_FULL_NATIVE
	
	if (EXPECT_NOT(info == nullptr))
	{
		cxx_OOJSReportWarning(context, "Could not create system info object for galaxy %u, system %i.", galaxy, system);
	}
	
	result = OOJSValueFromCxxObject(context, info.get());
	
	// Cache is not a root; we clear it in finalize if necessary.
	sCachedSystemInfo = ooscript::toObject(result);
	sCachedGalaxy = galaxy;
	sCachedSystem = system;
	
	return result;
	
	OOJS_PROFILE_EXIT_JSVAL
}


namespace {
static bool SystemInfoToString(ooscript::Context cx, ooscript::CallArgs &oojsArgs)
{
	return OOJSCxxObjectWrapperToString(cx, oojsArgs, &sSystemInfoClass);
}
} // namespace


namespace {
static void SystemInfoFinalize(Context cx, Object obj)
{
	ooscript::Object thisObj = (obj);
	
	OOJS_PROFILE_ENTER
	
	OOJSCxxObjectWrapperFinalize(cx, obj);	// clearJSSelf(), the slot's release, the empty slot
	
	// Clear now-stale cache entry if appropriate.
	if (sCachedSystemInfo == thisObj)  sCachedSystemInfo = NULL;
	
	OOJS_PROFILE_EXIT_VOID
}
} // namespace


namespace {
static bool SystemInfoEnumerate(Context cx, Object obj, EnumerateOp enumOp, Value *state, PropertyId *idp)
{
	ooscript::Context context = (cx);
	
	OOJS_NATIVE_ENTER(context)
	
	SystemInfoEnumerationState *enumerator = nullptr;
	
	switch (enumOp)
	{
		case EnumerateOp::Init:
		case EnumerateOp::InitAll:	// For ES5 Object.getOwnPropertyNames(). Since we have no non-enumerable properties, this is the same as Init.
		{
			OOSystemInfo *info = static_cast<OOSystemInfo *>(static_cast<oo::RefCounted *>(ooscript::getPrivate(cx, obj)));
			enumerator = new SystemInfoEnumerationState{ (info != nullptr) ? info->allKeys() : std::vector<std::string>() };	// (none from a message to nil)
			*state = ooscript::privateValue(enumerator);
			
			NSUInteger count = enumerator->keys.size();
			assert(count <= INT32_MAX);
			if (idp != NULL)  *idp = ooscript::int32Id((int32_t)count);
			return true;
		}
		
		case EnumerateOp::Next:
		{
			enumerator = static_cast<SystemInfoEnumerationState *>(ooscript::toPrivate(*state));
			if (enumerator->next < enumerator->keys.size())
			{
				ooscript::Value val = OOJSValueFromPList(context, oo::PList(enumerator->keys[enumerator->next++]));
				return ooscript::valueToId(cx, (val), idp);
			}
			// else:
			*state = ooscript::nullValue();
			// Fall through.
		}
		
		case EnumerateOp::Destroy:
		{
			if (enumerator == nullptr && ooscript::isDouble(*(state)))
			{
				enumerator = static_cast<SystemInfoEnumerationState *>(ooscript::toPrivate(*state));
			}
			delete enumerator;
			
			if (idp != NULL)  *idp = ooscript::voidId();
			return true;
		}
	}
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool SystemInfoDeleteProperty(Context cx, Object obj, PropertyId propID, Value */*value*/)
{
	OOJS_PROFILE_ENTER	// Any exception will be converted in SystemInfoSetProperty()
	
	Value v = ooscript::undefinedValue();
	return SystemInfoSetProperty(cx, obj, propID, false, &v);
	
	OOJS_PROFILE_EXIT
}
} // namespace


namespace {
static bool SystemInfoGetProperty(Context cx, Object obj, PropertyId propID, Value *value)
{
	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);
	
	OOJS_NATIVE_ENTER(context)
	
	if (thisObj == sSystemInfoPrototype)
	{
		// Let SpiderMonkey handle access to the prototype object (where info will be nil).
		return true;
	}
	
	OOSystemInfo	*info = SystemInfoOfJSObject(context, thisObj);
	// What if we're trying to access a saved witchspace systemInfo object?
	bool savedInterstellarInfo = !(UNIVERSE != nullptr ? UNIVERSE->inInterstellarSpace() : false) && SystemOf(info) == -1;
	bool sameGalaxy = (PLAYER != nullptr ? PLAYER->PlayerEntity::currentGalaxyID() : OOGalaxyID{}) == GalaxyOf(info);	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
	
	
	if (ooscript::isInt32Id(propID))
	{
		switch (ooscript::idToInt32(propID))
		{
			case kSystemInfo_coordinates:
				if (sameGalaxy && !savedInterstellarInfo)
				{
					return VectorToJSValue(context, OOGalacticCoordinatesFromInternal(CoordinatesOf(info)), (value));
				}
				else
				{
					cxx_OOJSReportError(context, "Cannot read systemInfo values for %s.", (savedInterstellarInfo ? "invalid interstellar space reference" : "other galaxies"));
					return false;
				}
				break;
				
			case kSystemInfo_internalCoordinates:
				if (sameGalaxy && !savedInterstellarInfo)
				{
					return NSPointToVectorJSValue(context, CoordinatesOf(info), (value));
				}
				else
				{
					cxx_OOJSReportError(context, "Cannot read systemInfo values for %s.", (savedInterstellarInfo ? "invalid interstellar space reference" : "other galaxies"));
					return false;
				}
				break;
				
			case kSystemInfo_galaxyID:
				*value = (ooscript::int32Value(GalaxyOf(info)));
				return true;
				
			case kSystemInfo_systemID:
				*value = (ooscript::int32Value(SystemOf(info)));
				return true;
				
			default:
				OOJSReportBadPropertySelector(context, thisObj, (propID), sSystemInfoPropertiesRaw);
				return false;
		}
	}
	else if (ooscript::isStringId(propID))
	{
		std::optional<std::string> key = cxx_OOStringFromJSString(context, (ooscript::idToString(propID)));
		
		OOSystemDescriptionManager *systemManager = (UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr);
		oo::PList propValue;
		// interstellar space needs more work at this stage
		if (SystemOf(info) != -1)
		{
			propValue = (systemManager != nullptr) ? systemManager->getProperty(key.value_or(""), SystemOf(info), GalaxyOf(info)) : oo::PList();	// (null from a message to nil)
		} else {
			propValue = ValueForKey(info, key);
		}
		
		if (!propValue.isNull())
		{
			if (propValue.isNumber() || OOIsNumberLiteral(oo::DescriptionOf(propValue), true))
			{
				// -doubleValue: an NSNumber's, or an NSString's (a number literal)
				const std::string *text = propValue.getIf<std::string>();
				const double number = (text != nullptr) ? oo::plist_get::doubleValue(oo::utf8ToUtf16(*text)) : propValue.doubleValue();
				bool OK = ooscript::newNumberValue(cx, number, value);
				if (!OK)
				{
					*value = ooscript::undefinedValue();
					return false;
				}
			}
			else
			{
				*value = OOJSValueFromPList(context, propValue);	// non-null: as its own glue gave
			}
		}
	}
	return true;
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool SystemInfoSetProperty(Context cx, Object obj, PropertyId propID, bool /*strict*/, Value *value)
{
	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);
	
	if (EXPECT_NOT(thisObj == sSystemInfoPrototype))
	{
		// Let SpiderMonkey handle access to the prototype object (where info will be nil).
		return true;
	}
	
	OOJS_NATIVE_ENTER(context);
	
	if (ooscript::isStringId(propID))
	{
		std::optional<std::string>	key = cxx_OOStringFromJSString(context, (ooscript::idToString(propID)));
		OOSystemInfo	*info = SystemInfoOfJSObject(context, thisObj);
		
		const oo::PList newValue = StringOrNull(cxx_OOStringFromJSValue(context, *(value)));
		if (info != nullptr)  info->setValue(newValue, key.value_or(""));	// (a nil key as "")
	}
	return true;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// distanceToSystem(sys : SystemInfo) : Number
namespace {
static bool SystemInfoDistanceToSystem(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	OOSystemInfo		*thisInfo = nullptr;
	ooscript::Object otherObj = NULL;
	OOSystemInfo		*otherInfo = nullptr;

	if (!JSSystemInfoGetSystemInfo(context, OOJS_THIS, &thisInfo))  return false;
	if (oojsArgs.count() < 1 || !ooscript::valueToObject(context, (OOJS_ARGV[0]), OOJSFOBJP(&otherObj)) || !JSSystemInfoGetSystemInfo(context, otherObj, &otherInfo))
	{
		cxx_OOJSReportBadArguments(context, "SystemInfo", "distanceToSystem", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "system info");
		return false;
	}
	
	bool sameGalaxy = (GalaxyOf(thisInfo) == GalaxyOf(otherInfo));
	if (!sameGalaxy)
	{
		cxx_OOJSReportErrorForCaller(context, "SystemInfo", "distanceToSystem", "Cannot calculate distance for systems in other galaxies.");
		return false;
	}

	NSPoint thisCoord = CoordinatesOf(thisInfo);
	NSPoint otherCoord = CoordinatesOf(otherInfo);
	
	OOJS_RETURN_DOUBLE(distanceBetweenPlanetPositions(thisCoord.x, thisCoord.y, otherCoord.x, otherCoord.y));
	
	OOJS_NATIVE_EXIT
}
} // namespace


// routeToSystem(sys : SystemInfo [, optimizedBy : String]) : Object
namespace {
static bool SystemInfoRouteToSystem(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	OOSystemInfo		*thisInfo = nullptr;
	ooscript::Object otherObj = NULL;
	OOSystemInfo		*otherInfo = nullptr;
	oo::PList				result;
	OORouteType				routeType = OPTIMIZED_BY_JUMPS;

	if (!JSSystemInfoGetSystemInfo(context, OOJS_THIS, &thisInfo))  return false;
	if (oojsArgs.count() < 1 || !ooscript::valueToObject(context, (OOJS_ARGV[0]), OOJSFOBJP(&otherObj)) || !JSSystemInfoGetSystemInfo(context, otherObj, &otherInfo))
	{
		cxx_OOJSReportBadArguments(context, "SystemInfo", "routeToSystem", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "system info");
		return false;
	}
	
	bool sameGalaxy = (GalaxyOf(thisInfo) == GalaxyOf(otherInfo));
	if (!sameGalaxy)
	{
		cxx_OOJSReportErrorForCaller(context, "SystemInfo", "routeToSystem", "Cannot calculate route for destinations in other galaxies.");
		return false;
	}
	
	if (oojsArgs.count() >= 2)
	{
		routeType = cxx_StringToRouteType(cxx_OOStringFromJSValue(context, OOJS_ARGV[1]).value_or(""));
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	result = (UNIVERSE != nullptr ? UNIVERSE->routeFromSystem(SystemOf(thisInfo), SystemOf(otherInfo), routeType) : oo::PList());
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_PLIST(result);
	
	OOJS_NATIVE_EXIT
}
} // namespace


// samplePrice(commodity)
namespace {
static bool SystemInfoSamplePrice(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	OOSystemInfo		*thisInfo = nullptr;

	if (!JSSystemInfoGetSystemInfo(context, OOJS_THIS, &thisInfo))  return false;
	OOCommodities		*commodities = (UNIVERSE != nullptr ? UNIVERSE->getCommodities() : nullptr);	// null: no good is defined, as a message to nil
	std::optional<std::string> commodity = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(commodities == nullptr || !commodities->goodDefined(commodity.value_or(""))))
	{
		cxx_OOJSReportBadArguments(context, "SystemInfo", "samplePrice", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "Unrecognised commodity type");
		return false;
	}

	bool sameGalaxy = (GalaxyOf(thisInfo) == (PLAYER != nullptr ? PLAYER->PlayerEntity::galaxyNumber() : OOGalaxyID{}));	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
	if (!sameGalaxy)
	{
		cxx_OOJSReportErrorForCaller(context, "SystemInfo", "samplePrice", "Cannot calculate sample price for destinations in other galaxies.");
		return false;
	}

	int economy = PropertyIntValue(ValueForKey(thisInfo, std::string("economy")));	// one system-data read per local, in the order Clang evaluates the arguments: a description that is an array draws (ADR-0063 item 5)
	std::optional<std::string> commodityScript = ManifestString(ValueForKey(thisInfo, std::string("commodity_script")));
	OOCreditsQuantity price = commodities->samplePriceForCommodity(commodity.value_or(""), economy, commodityScript, SystemOf(thisInfo));

	return ooscript::newNumberValue(context, price, oojsArgs.rawVp());
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool SystemInfoSetPropertyMethod(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	OOSystemInfo		*thisInfo = nullptr;

	if (!JSSystemInfoGetSystemInfo(context, OOJS_THIS, &thisInfo))  return false;

	std::optional<std::string> property;
	oo::PList value;	// null for a JavaScript null
	oo::PList manifest;	// a string from JavaScript, or the running script's manifest identifier as read

	int32_t iValue;

	if (oojsArgs.count() < 3)
	{
		cxx_OOJSReportBadArguments(context, "SystemInfo", "setProperty", MIN(oojsArgs.count(), 3U), OOJS_ARGV, std::nullopt, "setProperty(layer, property, value [,manifest])");
		return false;
	}
	if (!ooscript::valueToInt32(context, (OOJS_ARGV[0]), &iValue))
	{
		cxx_OOJSReportBadArguments(context, "SystemInfo", "setProperty", MIN(oojsArgs.count(), 3U), OOJS_ARGV, std::nullopt, "setProperty(layer, property, value [,manifest])");
		return false;
	}
	if (iValue < 0 || iValue >= OO_SYSTEM_LAYERS)
	{
		cxx_OOJSReportBadArguments(context, "SystemInfo", "setProperty", MIN(oojsArgs.count(), 3U), OOJS_ARGV, std::nullopt, "layer must be 0, 1, 2 or 3");
		return false;
	}
	OOSystemLayer layer = (OOSystemLayer)iValue;

	property = cxx_OOStringFromJSValue(context, OOJS_ARGV[1]);
	if (!ooscript::isNull(OOJS_ARGV[2]))
	{
		value = cxx_OOJSPListFromJSValue(context, OOJS_ARGV[2]);
	}
	if (oojsArgs.count() >= 4)
	{
		manifest = StringOrNull(cxx_OOStringFromJSValue(context, OOJS_ARGV[3]));
	}
	else
	{
		manifest = RunningScriptManifest();
	}

	if (UNIVERSE != nullptr)  UNIVERSE->setSystemDataForGalaxy(GalaxyOf(thisInfo), SystemOf(thisInfo), property.value_or(""), value, ManifestString(manifest), layer);

	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// filteredSystems(this : Object, predicate : Function) : Array
namespace {
static bool SystemInfoStaticFilteredSystems(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	ooscript::Object jsThis = NULL;
	
	// Get this and predicate arguments
	if (oojsArgs.count() < 2 || !OOJSValueIsFunction(context, OOJS_ARGV[1]) || !ooscript::valueToObject(context, (OOJS_ARGV[0]), OOJSFOBJP(&jsThis)))
	{
		cxx_OOJSReportBadArguments(context, "SystemInfo", "filteredSystems", oojsArgs.count(), OOJS_ARGV, std::nullopt, "this and predicate function");
		return false;
	}
	ooscript::Value predicate = OOJS_ARGV[1];
	
	std::vector<oo::Ref<OOSystemInfo>> result;
	bool OK;
	{
		oo::AutoreleaseScope pool;	// was @autoreleasepool (oo-31u.8)
		result.reserve(256);
		
		// Not OOJS_BEGIN_FULL_NATIVE() - we use the engine while paused.
		OOJSPauseTimeLimiter();
		
		// Iterate over systems.
		OK = true;	// (the array was always made)
		OOGalaxyID galaxy = (PLAYER != nullptr ? PLAYER->PlayerEntity::currentGalaxyID() : OOGalaxyID{});	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
		OOSystemID system;
		for (system = 0; system <= kOOMaximumSystemID; system++)
		{
			// NOTE: this deliberately bypasses the cache, since iteration is inherently unfriendly to a single-item cache.
			oo::Ref<OOSystemInfo> info = OOSystemInfo::initWithGalaxy(galaxy, system);
			ooscript::Value args[1] = { OOJSValueFromCxxObject(context, info.get()) };
			
			ooscript::Value rval = ooscript::undefinedValue();
			OOJSResumeTimeLimiter();
			OK = ooscript::callFunctionValue(context, (jsThis), (predicate), 1, (args), (&rval));
			OOJSPauseTimeLimiter();
			
			if (OK)
			{
				if (ooscript::isExceptionPending(context))
				{
					ooscript::reportPendingException(context);
					OK = false;
				}
			}
			
			if (OK)
			{
				bool boolVal;
				if (ooscript::valueToBoolean(context, (rval), &boolVal) && boolVal)
				{
					result.emplace_back(info);
				}
			}
			
			if (!OK)  break;
		}
		
		if (OK)
		{
			oo::PList::Array infos;
			infos.reserve(result.size());
			for (const auto &info : result)  infos.push_back(oo::PList(oo::PList::Object(oo::Ref<oo::PListForeign>(info.get()))));
			OOJS_SET_RVAL(OOJSValueFromPList(context, oo::PList(std::move(infos))));
		}
		else
		{
			OOJS_SET_RVAL(ooscript::undefinedValue());
		}
	}
	
	OOJSResumeTimeLimiter();
	return OK;
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool SystemInfoStaticSetInterstellarProperty(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	std::optional<std::string> property;
	oo::PList value;	// null for a JavaScript null
	oo::PList manifest;	// a string from JavaScript, or the running script's manifest identifier as read

	int32_t iValue;
	OOGalaxyID g;
	OOSystemID s1,s2;

	if (oojsArgs.count() < 6)
	{
		cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty", MIN(oojsArgs.count(), 3U), OOJS_ARGV, std::nullopt, "setProperty(galaxy, fromsystem, tosystem, layer, property, value [,manifest])");
		return false;
	}
	if (!ooscript::valueToInt32(context, (OOJS_ARGV[0]), &iValue))
	{
		cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty", MIN(oojsArgs.count(), 3U), OOJS_ARGV, std::nullopt, "setProperty(galaxy, fromsystem, tosystem, layer, property, value [,manifest])");
		return false;
	}
	if (iValue < 0 || iValue > kOOMaximumGalaxyID)
	{
		cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty", MIN(oojsArgs.count(), 3U), OOJS_ARGV, std::nullopt, "galaxy out of range");
		return false;
	}
	else
	{
		g = (OOGalaxyID)iValue;
	}

	if (!ooscript::valueToInt32(context, (OOJS_ARGV[1]), &iValue))
	{
		cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty", MIN(oojsArgs.count(), 3U), OOJS_ARGV, std::nullopt, "setProperty(galaxy, fromsystem, tosystem, layer, property, value [,manifest])");
		return false;
	}
	if (iValue < 0 || iValue > kOOMaximumSystemID)
	{
		cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty", MIN(oojsArgs.count(), 3U), OOJS_ARGV, std::nullopt, "fromsystem out of range");
		return false;
	}
	else
	{
		s1 = (OOSystemID)iValue;
	}

	if (!ooscript::valueToInt32(context, (OOJS_ARGV[2]), &iValue))
	{
		cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty", MIN(oojsArgs.count(), 3U), OOJS_ARGV, std::nullopt, "setProperty(galaxy, fromsystem, tosystem, layer, property, value [,manifest])");
		return false;
	}
	if (iValue < 0 || iValue > kOOMaximumSystemID)
	{
		cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty", MIN(oojsArgs.count(), 3U), OOJS_ARGV, std::nullopt, "tosystem out of range");
		return false;
	}
	else
	{
		s2 = (OOSystemID)iValue;
	}

	if (!ooscript::valueToInt32(context, (OOJS_ARGV[3]), &iValue))
	{
		cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty", MIN(oojsArgs.count(), 3U), OOJS_ARGV, std::nullopt, "setProperty(galaxy, fromsystem, tosystem, layer, property, value [,manifest])");
		return false;
	}
	if (iValue < 0 || iValue >= OO_SYSTEM_LAYERS)
	{
		cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty", MIN(oojsArgs.count(), 3U), OOJS_ARGV, std::nullopt, "layer must be 0, 1, 2 or 3");
		return false;
	}
	OOSystemLayer layer = (OOSystemLayer)iValue;

	property = cxx_OOStringFromJSValue(context, OOJS_ARGV[4]);
	if (!ooscript::isNull(OOJS_ARGV[5]))
	{
		value = cxx_OOJSPListFromJSValue(context, OOJS_ARGV[5]);
	}
	if (oojsArgs.count() >= 7)
	{
		manifest = StringOrNull(cxx_OOStringFromJSValue(context, OOJS_ARGV[6]));
	}
	else
	{
		manifest = RunningScriptManifest();
	}

	std::string key = oo::str::format("interstellar: %u %u %u",g,s1,s2);
	
	OOSystemDescriptionManager *systemManager = (UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr);	// null: nothing set, as a message to nil
	if (systemManager != nullptr)  systemManager->setProperty(property.value_or(""), key, layer, value, ManifestString(manifest));

	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace
