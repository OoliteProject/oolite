/*
OOJSVisualEffect.mm

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

#include "OOVisualEffectEntity.h"
#include "OOJSVisualEffect.h"
#include "OOJSEntity.h"
#include "OOJSVector.h"
#include "OOJavaScriptEngine.h"
#include "OOMesh.h"
#include "ResourceManager.h"
#include "EntityOOJavaScriptExtensions.h"

#include "ooscript/JSEngine.hpp"
#include <cstring>
#include <cstdint>
#include "OOObjCPList.h"
#include "OOScript.h"

// Retargeted onto the ooscript facade (JSEngine.hpp), the way OOJSVector.mm and
// OOJSFlasher.mm do it (bead oo-sdz exemplar): stub hooks become nullptr, InitClass
// becomes ooscript::initClass, numeric/boolean conversion becomes
// ooscript::newNumberValue/valueToNumber/valueToInt32, and `this` is renamed to `thisObj`
// (reserved word in Objective-C++, ADR-0001).
/*
	C++20 since bead oo-s1wq, converted the way bead oo-ppc converted OOJSVector.mm (proposed
	ADR-0056 amendment oo-ppc). The JS class was already C++ on the ooscript façade;
	OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
	(OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. The category on
	OOVisualEffectEntity became four free functions, and its methods and interface moved to a bridge
	file of the binding (amendment oo-ykoy), then onto the OOVisualEffectEntity facade in
	OOVisualEffectEntity+ObjCBridge.mm (bead oo-9ht.93, amendment oo-6ia4 item 3);
	restoreSubEntities() calls the function that holds -subEntitiesForScript's body. OOColor, which is C++ since bead oo-11m, is reached as
	OOColor through oo::ToCxx/oo::ToObjC (amendment oo-ppc, item 4). Messages to classes that
	are still Objective-C (OOVisualEffectEntity, ResourceManager, Universe, PlayerEntity; OOMesh is
	C++ since bead oo-9ht.132)
	stay as they are, which is why the file is still .mm until Phase 4.
*/

namespace ooscript { }
using ooscript::Context;
using ooscript::Object;
using ooscript::Value;
using ooscript::PropertyId;
using ooscript::ClassDef;
using ooscript::ClassFlag;
using ooscript::PropertyFlag;
using ooscript::PropertySpec;
using ooscript::FunctionSpec;
using ooscript::CallArgs;

// Byte-identical facade <-> jsapi views, local to this call site (see OOJSVector.mm).


namespace {
static ooscript::Object sVisualEffectPrototype;
} // namespace

namespace {
static bool JSVisualEffectGetVisualEffectEntity(ooscript::Context context, ooscript::Object visualEffectObj, OOVisualEffectEntity **outEntity);
} // namespace


namespace {

namespace {

// A colour's components as its -normalizedArray gave them to JavaScript: floats, null for no colour.
oo::PList NormalizedColorComponents(OOColor *color)
{
	if (color == nullptr)  return oo::PList();
	oo::PList::Array components;
	for (float component : color->normalizedArray())  components.push_back(oo::PList::singleReal(component));
	return oo::PList(std::move(components));
}

}	// namespace


static bool VisualEffectGetProperty(Context cx, Object obj, PropertyId propID, Value *value);
} // namespace
namespace {
static bool VisualEffectSetProperty(Context cx, Object obj, PropertyId propID, bool strict, Value *value);
} // namespace

namespace {
static bool VisualEffectRemove(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool VisualEffectGetShaders(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool VisualEffectSetShaders(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool VisualEffectGetMaterials(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool VisualEffectSetMaterials(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool VisualEffectScale(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool VisualEffectRestoreSubEntities(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace

namespace {
static bool VisualEffectSetMaterialsInternal(ooscript::Context context, ooscript::CallArgs &oojsArgs, OOVisualEffectEntity *thisEnt, bool fromShaders);
} // namespace


namespace {
static ClassDef sVisualEffectClass =
{
	"VisualEffect",
	ClassFlag::HasPrivate,
	
	nullptr,			// addProperty (engine default: PropertyStub)
	nullptr,			// delProperty (engine default: PropertyStub)
	VisualEffectGetProperty,		// getProperty
	VisualEffectSetProperty,		// setProperty
	nullptr,			// enumerate (engine default: EnumerateStub)
	nullptr,			// newEnumerate (ooscript::ClassFlag::NewEnumerate not used)
	nullptr,			// resolve (engine default: ResolveStub)
	nullptr,			// convert (engine default: ConvertStub)
	OOJSCxxObjectWrapperFinalize,// finalize
	nullptr,			// call
	nullptr,			// construct
	nullptr,			// backend: owned by the facade backend, must start null
};
} // namespace


enum : std::uint8_t
{
	// Property IDs
	kVisualEffect_beaconCode,
	kVisualEffect_beaconLabel,
	kVisualEffect_dataKey,
	kVisualEffect_hullHeatLevel,
	kVisualEffect_isBreakPattern,
	kVisualEffect_scaleX,
	kVisualEffect_scaleY,
	kVisualEffect_scaleZ,
	kVisualEffect_scannerDisplayColor1,
	kVisualEffect_scannerDisplayColor2,
	kVisualEffect_script,
	kVisualEffect_scriptInfo,
	kVisualEffect_shaderFloat1,
	kVisualEffect_shaderFloat2,
	kVisualEffect_shaderInt1,
	kVisualEffect_shaderInt2,
	kVisualEffect_shaderVector1,
	kVisualEffect_shaderVector2,
	kVisualEffect_subEntities,
	kVisualEffect_vectorForward,
	kVisualEffect_vectorRight,
	kVisualEffect_vectorUp
};


namespace {
static PropertySpec sVisualEffectProperties[] =
{
	// JS name						ID									flags																			getter		setter
	{ "beaconCode",	   kVisualEffect_beaconCode,	  PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "beaconLabel",   kVisualEffect_beaconLabel,	  PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "dataKey",	     kVisualEffect_dataKey,	      OOJS_PROP_READONLY_CB, nullptr, nullptr },
	{ "isBreakPattern",	kVisualEffect_isBreakPattern,	PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "scaleX", kVisualEffect_scaleX, PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "scaleY", kVisualEffect_scaleY, PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },	
	{ "scaleZ", kVisualEffect_scaleZ, PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "scannerDisplayColor1", kVisualEffect_scannerDisplayColor1, PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "scannerDisplayColor2", kVisualEffect_scannerDisplayColor2, PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "hullHeatLevel", kVisualEffect_hullHeatLevel, PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "script",				 kVisualEffect_script,				OOJS_PROP_READONLY_CB, nullptr, nullptr },
	{ "scriptInfo", 	 kVisualEffect_scriptInfo,		OOJS_PROP_READONLY_CB, nullptr, nullptr },
	{ "shaderFloat1",  kVisualEffect_shaderFloat1,  PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "shaderFloat2",  kVisualEffect_shaderFloat2,  PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "shaderInt1",    kVisualEffect_shaderInt1,    PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "shaderInt2",    kVisualEffect_shaderInt2,    PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "shaderVector1", kVisualEffect_shaderVector1, PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "shaderVector2", kVisualEffect_shaderVector2, PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "subEntities",			kVisualEffect_subEntities,			OOJS_PROP_READONLY_CB, nullptr, nullptr },
	{ "vectorForward", kVisualEffect_vectorForward,	OOJS_PROP_READONLY_CB, nullptr, nullptr },
	{ "vectorRight",	 kVisualEffect_vectorRight,		OOJS_PROP_READONLY_CB, nullptr, nullptr },
	{ "vectorUp",			 kVisualEffect_vectorUp,			OOJS_PROP_READONLY_CB, nullptr, nullptr },
	{ 0 }
};
} // namespace


// Raw jsapi mirror of sVisualEffectProperties for the shared error reporters that still take a
// ooscript::PropertySpec* (see OOJSVector.mm's sVectorPropertiesRaw).
namespace {
static ooscript::PropertySpec sVisualEffectPropertiesRaw[] =
{
	// JS name						ID									flags
	{ "beaconCode",	   kVisualEffect_beaconCode,	  OOJS_PROP_READWRITE_CB },
	{ "beaconLabel",   kVisualEffect_beaconLabel,	  OOJS_PROP_READWRITE_CB },
	{ "dataKey",	     kVisualEffect_dataKey,	      OOJS_PROP_READONLY_CB },
	{ "isBreakPattern",	kVisualEffect_isBreakPattern,	OOJS_PROP_READWRITE_CB },
	{ "scaleX", kVisualEffect_scaleX, OOJS_PROP_READWRITE_CB },
	{ "scaleY", kVisualEffect_scaleY, OOJS_PROP_READWRITE_CB },	
	{ "scaleZ", kVisualEffect_scaleZ, OOJS_PROP_READWRITE_CB },
	{ "scannerDisplayColor1", kVisualEffect_scannerDisplayColor1, OOJS_PROP_READWRITE_CB },
	{ "scannerDisplayColor2", kVisualEffect_scannerDisplayColor2, OOJS_PROP_READWRITE_CB },
	{ "hullHeatLevel", kVisualEffect_hullHeatLevel, OOJS_PROP_READWRITE_CB },
	{ "script",				 kVisualEffect_script,				OOJS_PROP_READONLY_CB },
	{ "scriptInfo", 	 kVisualEffect_scriptInfo,		OOJS_PROP_READONLY_CB },
	{ "shaderFloat1",  kVisualEffect_shaderFloat1,  OOJS_PROP_READWRITE_CB },
	{ "shaderFloat2",  kVisualEffect_shaderFloat2,  OOJS_PROP_READWRITE_CB },
	{ "shaderInt1",    kVisualEffect_shaderInt1,    OOJS_PROP_READWRITE_CB },
	{ "shaderInt2",    kVisualEffect_shaderInt2,    OOJS_PROP_READWRITE_CB },
	{ "shaderVector1", kVisualEffect_shaderVector1, OOJS_PROP_READWRITE_CB },
	{ "shaderVector2", kVisualEffect_shaderVector2, OOJS_PROP_READWRITE_CB },
	{ "subEntities",			kVisualEffect_subEntities,			OOJS_PROP_READONLY_CB },
	{ "vectorForward", kVisualEffect_vectorForward,	OOJS_PROP_READONLY_CB },
	{ "vectorRight",	 kVisualEffect_vectorRight,		OOJS_PROP_READONLY_CB },
	{ "vectorUp",			 kVisualEffect_vectorUp,			OOJS_PROP_READONLY_CB },
	{ 0 }
};
} // namespace


namespace {
static FunctionSpec sVisualEffectMethods[] =
{
	// JS name					Function						min args	flags
	{ "getMaterials",   VisualEffectGetMaterials,    0,	0 },
	{ "getShaders",     VisualEffectGetShaders,    0,	0 },
	{ "remove",         VisualEffectRemove,    0,	0 },
	{ "restoreSubEntities", VisualEffectRestoreSubEntities, 0,	0 },
	{ "scale",				  VisualEffectScale, 1,	0 },
	{ "setMaterials",   VisualEffectSetMaterials,    1,	0 },
	{ "setShaders",     VisualEffectSetShaders,    2,	0 },

	{ 0 }
};
} // namespace


void InitOOJSVisualEffect(ooscript::Context context, ooscript::Object global)
{
	Object proto = ooscript::initClass((context), (global), (JSEntityPrototype()), &sVisualEffectClass, OOJSUnconstructableConstruct, 0, sVisualEffectProperties, sVisualEffectMethods, nullptr, nullptr);
	sVisualEffectPrototype = (proto);
	OOJSRegisterObjectConverter(&sVisualEffectClass, OOJSEntityObjectConverter);
	OOJSRegisterSubclass(&sVisualEffectClass, JSEntityClass());
}


namespace {
static bool JSVisualEffectGetVisualEffectEntity(ooscript::Context context, ooscript::Object visualEffectObj, OOVisualEffectEntity **outEntity)
{
	OOJS_PROFILE_ENTER
	
	bool						result;
	Entity					*entity = nullptr;	// the slot holds the C++ entity (bead oo-9ht.39.3)
	
	if (outEntity == NULL)  return false;
	*outEntity = nil;
	
	result = OOJSEntityGetEntity(context, visualEffectObj, &entity);
	if (!result)  return false;
	
	OOVisualEffectEntity *effect = oo::ToEffect(entity);	// -isKindOfClass:[OOVisualEffectEntity class] until bead oo-9ht.165
	if (effect == nullptr)  return false;
	
	*outEntity = effect;
	return true;
	
	OOJS_PROFILE_EXIT
}
} // namespace


// The bodies of OOVisualEffectEntity (OOJavaScriptExtensions), whose methods are on the
// OOVisualEffectEntity facade, in OOVisualEffectEntity+ObjCBridge.mm (bead oo-9ht.93), until that
// facade goes (oo-9ht.165; proposed ADR-0056 amendments oo-ppc, oo-ykoy and oo-6ia4).
void OOJSVisualEffectGetJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)
{
	*outClass = &sVisualEffectClass;
	*outPrototype = sVisualEffectPrototype;
}

std::optional<std::string> OOJSVisualEffectJSClassName(void)
{
	return std::string("VisualEffect");
}

bool OOJSVisualEffectIsVisibleToScripts(void)
{
	return true;
}

std::vector<oo::EntityHold> OOJSVisualEffectSubEntitiesForScript(OOVisualEffectEntity *effect)
{
	const auto subs = effect->visualEffectSubEntityEnumerator();
	if (!subs.has_value())  return {};
	std::vector<oo::EntityHold> result;
	result.reserve(subs->size());
	for (const auto &sub : *subs)
	{
		result.emplace_back(sub.get());
	}
	return result;
}


namespace {
static bool VisualEffectGetProperty(Context cx, Object obj, PropertyId propID, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = reinterpret_cast<ooscript::Context >(cx);
	ooscript::Object thisObj = (obj);
	ooscript::Value *value_raw = reinterpret_cast<ooscript::Value*>(value);
	
	OOJS_NATIVE_ENTER(context)
	
	OOVisualEffectEntity				*entity = nil;
	oo::PList result;	// null maps to null
	
	if (!JSVisualEffectGetVisualEffectEntity(context, thisObj, &entity))  return false;
	if (entity == nil)  { *value_raw = ooscript::undefinedValue(); return true; }
	
	switch (ooscript::idToInt32(propID))
	{
		case kVisualEffect_beaconCode:
			if (const std::optional<std::string> text = (entity != nullptr ? entity->beaconCode() : std::optional<std::string>()))  result = oo::PList(*text);
			break;

		case kVisualEffect_beaconLabel:
			if (const std::optional<std::string> text = (entity != nullptr ? entity->beaconLabel() : std::optional<std::string>()))  result = oo::PList(*text);
			break;

		case kVisualEffect_dataKey:
			if (const std::optional<std::string> text = (entity != nullptr ? entity->effectKey() : std::optional<std::string>()))  result = oo::PList(*text);
			break;

		case kVisualEffect_isBreakPattern:
			*value_raw = OOJSValueFromBOOL((entity != nullptr ? entity->isBreakPattern() : false));

			return true;

		case kVisualEffect_vectorRight:
			return VectorToJSValue(context, (entity != nullptr ? entity->rightVector() : kZeroVector), value_raw);
			
		case kVisualEffect_vectorForward:
			return VectorToJSValue(context, (entity != nullptr ? entity->forwardVector() : kZeroVector), value_raw);
			
		case kVisualEffect_vectorUp:
			return VectorToJSValue(context, (entity != nullptr ? entity->upVector() : kZeroVector), value_raw);

		case kVisualEffect_scaleX:
			return ooscript::newNumberValue(cx, (entity != nullptr ? entity->scaleX() : 0.0f), value);

		case kVisualEffect_scaleY:
			return ooscript::newNumberValue(cx, (entity != nullptr ? entity->scaleY() : 0.0f), value);

		case kVisualEffect_scaleZ:
			return ooscript::newNumberValue(cx, (entity != nullptr ? entity->scaleZ() : 0.0f), value);

		case kVisualEffect_scannerDisplayColor1:
			result = NormalizedColorComponents((entity != nullptr ? entity->scannerDisplayColor1() : (OOColor *)nullptr));
			break;
			
		case kVisualEffect_scannerDisplayColor2:
			result = NormalizedColorComponents((entity != nullptr ? entity->scannerDisplayColor2() : (OOColor *)nullptr));
			break;

		case kVisualEffect_hullHeatLevel:
			return ooscript::newNumberValue(cx, (entity != nullptr ? entity->hullHeatLevel() : 0.0f), value);

		case kVisualEffect_shaderFloat1:
			return ooscript::newNumberValue(cx, (entity != nullptr ? entity->shaderFloat1() : 0.0f), value);

		case kVisualEffect_shaderFloat2:
			return ooscript::newNumberValue(cx, (entity != nullptr ? entity->shaderFloat2() : 0.0f), value);

		case kVisualEffect_shaderInt1:
			*value_raw = ooscript::int32Value((entity != nullptr ? entity->shaderInt1() : 0));
			return true;

		case kVisualEffect_shaderInt2:
			*value_raw = ooscript::int32Value((entity != nullptr ? entity->shaderInt2() : 0));
			return true;

		case kVisualEffect_shaderVector1:
			return VectorToJSValue(context, (entity != nullptr ? entity->shaderVector1() : kZeroVector), value_raw);

		case kVisualEffect_shaderVector2:
			return VectorToJSValue(context, (entity != nullptr ? entity->shaderVector2() : kZeroVector), value_raw);

		case kVisualEffect_subEntities:
			{
				// nil before the first subentity (was [subEntitiesForScript] == nil)
				const auto subs = (entity != nullptr ? entity->visualEffectSubEntityEnumerator() : std::optional<std::vector<oo::EntityHold>>());
				if (subs.has_value())  result = oo::EntityNodesFrom(*subs);
			}
			break;
			
			
		case kVisualEffect_script:
			result = OOScriptObjectNode((entity != nullptr ? entity->script() : (OOScript *)nullptr));
			break;

		case kVisualEffect_scriptInfo:
			result = (entity != nullptr ? entity->scriptInfo() : oo::PList());	// empty dict, never null
			break;

		default:
			OOJSReportBadPropertySelector(context, thisObj, (propID), sVisualEffectPropertiesRaw);
			return false;
	}

	*value_raw = OOJSValueFromPList(context, result);
	return true;
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool VisualEffectSetProperty(Context cx, Object obj, PropertyId propID, bool /*strict*/, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = reinterpret_cast<ooscript::Context >(cx);
	ooscript::Object thisObj = (obj);
	ooscript::Value *value_raw = reinterpret_cast<ooscript::Value*>(value);
	
	OOJS_NATIVE_ENTER(context)
	
	OOVisualEffectEntity				*entity = nil;
	bool						bValue;
	oo::Ref<OOColor>	colorForScript;
	std::int32_t						iValue;
	double        fValue;
	Vector          vValue;
	std::optional<std::string>	sValue;

	
	if (!JSVisualEffectGetVisualEffectEntity(context, thisObj, &entity)) return false;
	if (entity == nil)  return true;
	
	switch (ooscript::idToInt32(propID))
	{
		case kVisualEffect_beaconCode:
			sValue = cxx_OOStringFromJSValue(context,*value_raw);
			if (!sValue.has_value() || sValue->empty()) 
			{
				if ((entity != nullptr ? entity->isBeacon() : false)) 
				{
					if (UNIVERSE != nullptr)  UNIVERSE->clearBeacon(entity);	// the C++ entity (bead oo-9ht.39.8.10)
					if ((PLAYER != nullptr ? PLAYER->nextBeaconEntity() : nullptr) == entity)	// the C++ entities (bead oo-9ht.39.8.10; not virtual, so the binding test stands in for it)
					{
						if (PLAYER != nullptr)  PLAYER->PlayerEntity::setCompassMode(COMPASS_MODE_PLANET);	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
					}
				}
			}
			else 
			{
				if ((entity != nullptr ? entity->isBeacon() : false)) 
				{
					if (entity != nullptr)  entity->setBeaconCode(sValue);
				}
				else // Universe needs to update beacon lists in this case only
				{
					if (entity != nullptr)  entity->setBeaconCode(sValue);
					if (UNIVERSE != nullptr)  UNIVERSE->setNextBeacon(entity);	// the C++ entity (bead oo-9ht.39.8.10)
				}
			}
			return true;
			break;

		case kVisualEffect_beaconLabel:
			sValue = cxx_OOStringFromJSValue(context,*value_raw);
			if (sValue.has_value())
			{
				if (entity != nullptr)  entity->setBeaconLabel(sValue);
				return true;
			}
			break;

		case kVisualEffect_isBreakPattern:
			if (ooscript::valueToBoolean(cx, (*value_raw), &bValue))
			{
				if (entity != nullptr)  entity->setIsBreakPattern(bValue);
				return true;
			}
			break;

		case kVisualEffect_scannerDisplayColor1:
			colorForScript = OOColor::colorWithDescription(cxx_OOJSPListFromJSValue(context, *value_raw));
			if (colorForScript != nullptr || ooscript::isNull(*value_raw))
			{
				if (entity != nullptr)  entity->setScannerDisplayColor1(colorForScript.get());
				return true;
			}
			break;
			
		case kVisualEffect_scannerDisplayColor2:
			colorForScript = OOColor::colorWithDescription(cxx_OOJSPListFromJSValue(context, *value_raw));
			if (colorForScript != nullptr || ooscript::isNull(*value_raw))
			{
				if (entity != nullptr)  entity->setScannerDisplayColor2(colorForScript.get());
				return true;
			}
			break;

		case kVisualEffect_scaleX:
			if (ooscript::valueToNumber(cx, (*value_raw), &fValue))
			{
				if (fValue > 0.0)
				{
					if (entity != nullptr)  entity->setScaleX(fValue);
					return true;
				}
			}
			break;

		case kVisualEffect_scaleY:
			if (ooscript::valueToNumber(cx, (*value_raw), &fValue))
			{
				if (fValue > 0.0)
				{
					if (entity != nullptr)  entity->setScaleY(fValue);
					return true;
				}
			}
			break;

		case kVisualEffect_scaleZ:
			if (ooscript::valueToNumber(cx, (*value_raw), &fValue))
			{
				if (fValue > 0.0)
				{
					if (entity != nullptr)  entity->setScaleZ(fValue);
					return true;
				}
			}
			break;

		case kVisualEffect_hullHeatLevel:
			if (ooscript::valueToNumber(cx, (*value_raw), &fValue))
			{
				if (entity != nullptr)  entity->setHullHeatLevel(fValue);
				return true;
			}
			break;

		case kVisualEffect_shaderFloat1:
			if (ooscript::valueToNumber(cx, (*value_raw), &fValue))
			{
				if (entity != nullptr)  entity->setShaderFloat1(fValue);
				return true;
			}
			break;

		case kVisualEffect_shaderFloat2:
			if (ooscript::valueToNumber(cx, (*value_raw), &fValue))
			{
				if (entity != nullptr)  entity->setShaderFloat2(fValue);
				return true;
			}
			break;

		case kVisualEffect_shaderInt1:
			if (ooscript::valueToInt32(cx, (*value_raw), &iValue))
			{
				if (entity != nullptr)  entity->setShaderInt1(iValue);
				return true;
			}
			break;

		case kVisualEffect_shaderInt2:
			if (ooscript::valueToInt32(cx, (*value_raw), &iValue))
			{
				if (entity != nullptr)  entity->setShaderInt2(iValue);
				return true;
			}
			break;

		case kVisualEffect_shaderVector1:
			if (JSValueToVector(context, *value_raw, &vValue))
			{
				if (entity != nullptr)  entity->setShaderVector1(vValue);
				return true;
			}
			break;

		case kVisualEffect_shaderVector2:
			if (JSValueToVector(context, *value_raw, &vValue))
			{
				if (entity != nullptr)  entity->setShaderVector2(vValue);
				return true;
			}
			break;

		default:
			OOJSReportBadPropertySelector(context, thisObj, (propID), sVisualEffectPropertiesRaw);
			return false;
	}
	
	OOJSReportBadPropertyValue(context, thisObj, (propID), sVisualEffectPropertiesRaw, *value_raw);
	return false;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// *** Methods ***

// The effect's mesh's materials and shaders: C++ since bead oo-9ht.132 (the effect's -mesh answers
// the C++ mesh); null for no mesh, as a message to nil answered.
namespace {
oo::PList MeshMaterials(OOVisualEffectEntity *effect)
{
	OOMesh *mesh = (effect != nullptr ? effect->mesh() : (OOMesh *)nullptr);
	return (mesh != nullptr) ? mesh->getMaterials() : oo::PList();
}

oo::PList MeshShaders(OOVisualEffectEntity *effect)
{
	OOMesh *mesh = (effect != nullptr ? effect->mesh() : (OOMesh *)nullptr);
	return (mesh != nullptr) ? mesh->shaders() : oo::PList();
}
} // namespace


#define GET_THIS_EFFECT(THISENT) do { \
	if (EXPECT_NOT(!JSVisualEffectGetVisualEffectEntity(context, OOJS_THIS, &(THISENT))))  return false; /* Exception */ \
	if (OOIsStaleEntity(THISENT))  OOJS_RETURN_VOID;	/* the C++ effect's (bead oo-9ht.39.8.13) */ \
} while (0)


namespace {
static bool VisualEffectRemove(ooscript::Context cx, ooscript::CallArgs &oojsArgs)
{
	ooscript::Context context = reinterpret_cast<ooscript::Context >(cx);
	
	OOJS_NATIVE_ENTER(context)
	
	OOVisualEffectEntity				*thisEnt = nil;
	GET_THIS_EFFECT(thisEnt);
	
	if ((thisEnt != nullptr ? thisEnt->getIsSubEntity() : false))
	{
		OOVisualEffectEntity				*parent = oo::ToEffect(oo::LiveOwner(thisEnt));	// C++ since bead oo-9ht.165; the owner's C++ entity (bead oo-9ht.39.25)
		if (parent != nullptr)  parent->removeSubEntity(thisEnt);	// the C++ sub-entity (bead oo-9ht.39.8.13)
	}
	else
	{
		if (thisEnt != nullptr)  thisEnt->remove();
	}

	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace


//getMaterials()
namespace {
static bool VisualEffectGetMaterials(ooscript::Context cx, ooscript::CallArgs &oojsArgs)
{
	ooscript::Context context = reinterpret_cast<ooscript::Context >(cx);

	OOJS_PROFILE_ENTER

	oo::PList			result;
	OOVisualEffectEntity				*thisEnt = nil;

	GET_THIS_EFFECT(thisEnt);
	
	result = MeshMaterials(thisEnt);
	if (result.isNull())  result = oo::PList(oo::PList::Dict{});	// an empty dictionary
	OOJS_RETURN_PLIST(result);
	
	OOJS_PROFILE_EXIT
}
} // namespace

//getShaders()
namespace {
static bool VisualEffectGetShaders(ooscript::Context cx, ooscript::CallArgs &oojsArgs)
{
	ooscript::Context context = reinterpret_cast<ooscript::Context >(cx);
	
	OOJS_PROFILE_ENTER
	
	oo::PList			result;
	OOVisualEffectEntity				*thisEnt = nil;

	GET_THIS_EFFECT(thisEnt);
	
	result = MeshShaders(thisEnt);
	if (result.isNull())  result = oo::PList(oo::PList::Dict{});	// an empty dictionary
	OOJS_RETURN_PLIST(result);
	
	OOJS_PROFILE_EXIT
}
} // namespace


// setMaterials(params: dict, [shaders: dict])  // sets materials dictionary. Optional parameter sets the shaders dictionary too.
namespace {
static bool VisualEffectSetMaterials(ooscript::Context cx, ooscript::CallArgs &oojsArgs)
{
	ooscript::Context context = reinterpret_cast<ooscript::Context >(cx);
	
	OOJS_NATIVE_ENTER(context)
	
	OOVisualEffectEntity				*thisEnt = nil;
	
	if (oojsArgs.count() < 1)
	{
		cxx_OOJSReportBadArguments(context, "VisualEffect", "setMaterials", 0, OOJS_ARGV, std::nullopt, "parameter object");
		return false;
	}
	
	GET_THIS_EFFECT(thisEnt);
	
	return VisualEffectSetMaterialsInternal(context, oojsArgs, thisEnt, false);
	
	OOJS_NATIVE_EXIT
}
} // namespace


// setShaders(params: dict) 
namespace {
static bool VisualEffectSetShaders(ooscript::Context cx, ooscript::CallArgs &oojsArgs)
{
	ooscript::Context context = reinterpret_cast<ooscript::Context >(cx);
	
	OOJS_NATIVE_ENTER(context)
	
	OOVisualEffectEntity				*thisEnt = nil;
	
	GET_THIS_EFFECT(thisEnt);
	
	if (oojsArgs.count() < 1)
	{
		cxx_OOJSReportBadArguments(context, "VisualEffect", "setShaders", 0, OOJS_ARGV, std::nullopt, "parameter object");
		return false;
	}
	
	if (ooscript::isNull(OOJS_ARGV[0]) || (!ooscript::isNull(OOJS_ARGV[0]) && !ooscript::isObjectOrNull(OOJS_ARGV[0])))
	{
		// EMMSTRAN: valueToObject() and normal error handling here.
		cxx_OOJSReportWarning(context, "VisualEffect.%s: expected %s instead of '%s'.", "setShaders", "object", cxx_OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[0]).value_or("(null)").c_str());
		OOJS_RETURN_BOOL(false);
	}
	
	OOJS_ARGV[1] = OOJS_ARGV[0];
	return VisualEffectSetMaterialsInternal(context, oojsArgs, thisEnt, true);
	
	OOJS_NATIVE_EXIT
}
} // namespace




/* **  helper functions ** */

namespace {
static bool VisualEffectSetMaterialsInternal(ooscript::Context context, ooscript::CallArgs &oojsArgs, OOVisualEffectEntity *thisEnt, bool fromShaders)
{
	OOJS_PROFILE_ENTER
	
	ooscript::Object params = NULL;
	oo::PList				materials;
	oo::PList				shaders;
	bool					withShaders = false;
	bool					success = false;
	
	GET_THIS_EFFECT(thisEnt);
	
	if (ooscript::isNull(OOJS_ARGV[0]) || (!ooscript::isNull(OOJS_ARGV[0]) && !ooscript::isObjectOrNull(OOJS_ARGV[0])))
	{
		cxx_OOJSReportWarning(context, "VisualEffect.%s: expected %s instead of '%s'.", "setMaterials", "object", cxx_OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[0]).value_or("(null)").c_str());
		OOJS_RETURN_BOOL(false);
	}
	
	if (oojsArgs.count() > 1)
	{
		withShaders = true;
		if (ooscript::isNull(OOJS_ARGV[1]) || (!ooscript::isNull(OOJS_ARGV[1]) && !ooscript::isObjectOrNull(OOJS_ARGV[1])))
		{
			cxx_OOJSReportWarning(context, "VisualEffect.%s: expected %s instead of '%s'.",  "setMaterials", "object as second parameter", cxx_OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[1]).value_or("(null)").c_str());
			withShaders = false;
		}
	}
	
	if (fromShaders)
	{
		materials = MeshMaterials(thisEnt);
		params = ooscript::toObject(OOJS_ARGV[0]);
		shaders = cxx_OOJSPListFromJSObject(context, params);
	}
	else
	{
		params = ooscript::toObject(OOJS_ARGV[0]);
		materials = cxx_OOJSPListFromJSObject(context, params);
		if (withShaders)
		{
			params = ooscript::toObject(OOJS_ARGV[1]);
			shaders = cxx_OOJSPListFromJSObject(context, params);
		}
		else
		{
			shaders = MeshShaders(thisEnt);
		}
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	const oo::PList		effectDict = (thisEnt != nullptr ? thisEnt->effectInfoDictionary() : oo::PList());
	// -oo_stringForKey: / -oo_dictionaryForKey: as the mesh call read them: nil unless a string (or a
	// number's text) / a dictionary.
	const oo::PList		*model = effectDict.get<oo::PList>("model");
	std::optional<std::string>	modelName;
	if (model != nullptr && (model->isString() || model->isNumber()))  modelName = effectDict.get<std::string>("model");
	// The ship-prefix-macros default as the mesh call read it: a dictionary, else nothing.
	const oo::PList		materialDefaults = ResourceManager::materialDefaults();
	const oo::PList		*macros = materialDefaults.get<oo::PList::Dict>("ship-prefix-macros");
	const oo::PList		shaderMacros = (macros != nullptr) ? *macros : oo::PList();
	
	// First we test to see if we can create the mesh.
	const oo::Ref<OOMesh> mesh = OOMesh::meshWithName(modelName.value_or(std::string()),
							   std::nullopt,
					 materials,
					  shaders,
								 effectDict.get<bool>("smooth", false),
						   shaderMacros,
					thisEnt);	// the C++ effect (bead oo-9ht.39.6)
	
	if (mesh != nullptr)
	{
		if (thisEnt != nullptr)  thisEnt->setMesh(mesh.get());
		success = true;
	}
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_BOOL(success);
	
	OOJS_PROFILE_EXIT
}
} // namespace

namespace {
static bool VisualEffectScale(ooscript::Context cx, ooscript::CallArgs &oojsArgs)
{
	ooscript::Context context = reinterpret_cast<ooscript::Context >(cx);

	OOJS_NATIVE_ENTER(context)

	OOVisualEffectEntity *thisEnt = nil;
	GET_THIS_EFFECT(thisEnt);
	double scale;
	bool gotScale;
 
	if (oojsArgs.count() < 1)
	{
		cxx_OOJSReportBadArguments(context, "VisualEffect", "scale", oojsArgs.count(), OOJS_ARGV, std::nullopt, "scale factor needed");
		return false;
	}
 
	gotScale = ooscript::valueToNumber(cx, (OOJS_ARGV[0]), &scale);
	if (EXPECT_NOT(scale <= 0.0 || !gotScale))
	{
		cxx_OOJSReportBadArguments(context, "VisualEffect", "scale", oojsArgs.count(), OOJS_ARGV, std::nullopt, "scale factor must be positive");
		return false;
	}
 
	// set all three scales
	if (thisEnt != nullptr)  thisEnt->setScaleX(scale);
	if (thisEnt != nullptr)  thisEnt->setScaleY(scale);
	if (thisEnt != nullptr)  thisEnt->setScaleZ(scale);
 
	return true;
	OOJS_NATIVE_EXIT
		
}
} // namespace


// restoreSubEntities(): boolean
namespace {
static bool VisualEffectRestoreSubEntities(ooscript::Context cx, ooscript::CallArgs &oojsArgs)
{
	ooscript::Context context = reinterpret_cast<ooscript::Context >(cx);
	
	OOJS_NATIVE_ENTER(context)
	
	OOVisualEffectEntity				*thisEnt = nil;
	NSUInteger				numSubEntitiesRestored = 0U;
	
	GET_THIS_EFFECT(thisEnt);
	
	// -subEntitiesForScript, called as the function that holds its body (amendment oo-ykoy item 2;
	// the method is on the OOVisualEffectEntity facade since bead oo-9ht.93).
	NSUInteger subCount = OOJSVisualEffectSubEntitiesForScript(thisEnt).size();
	
	if (thisEnt != nullptr)  thisEnt->clearSubEntities();
	if (thisEnt != nullptr)  thisEnt->setUpSubEntities();
	
	if (OOJSVisualEffectSubEntitiesForScript(thisEnt).size() - subCount > 0)  numSubEntitiesRestored = OOJSVisualEffectSubEntitiesForScript(thisEnt).size() - subCount;
	
	OOJS_RETURN_BOOL(numSubEntitiesRestored > 0);
	
	OOJS_NATIVE_EXIT
}
} // namespace
