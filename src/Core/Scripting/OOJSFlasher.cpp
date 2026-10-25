/*
OOJSFlasher.mm

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

#include "OOFlasherEntity.h"
#include "OOColor.h"
#include "OOJSFlasher.h"
#include "OOJSEntity.h"
#include "OOJSVector.h"
#include "OOJavaScriptEngine.h"
#include "EntityOOJavaScriptExtensions.h"
#include "ShipEntity.h"
#include "OOVisualEffectEntity.h"

#include "ooscript/JSEngine.hpp"
#include <cstring>
#include <cstdint>

// Retargeted onto the ooscript facade (JSEngine.hpp), the way OOJSVector.mm and
// OOJSWormhole.mm do it (bead oo-sdz exemplar): stub hooks become nullptr, InitClass
// becomes ooscript::initClass, numeric/boolean conversion becomes
// ooscript::newNumberValue/valueToNumber/valueToBoolean, and `this` is renamed to `thisObj`
// (reserved word in Objective-C++, ADR-0001).

/*
	C++20 since bead oo-ub2g, converted the way bead oo-ppc converted OOJSVector.mm (proposed
	ADR-0056 amendment oo-ppc). The JS class was already C++ on the ooscript façade;
	OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
	(OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. The category on OOFlasherEntity
	became three free functions, and its methods and interface moved to a bridge file of the binding
	(amendment oo-ykoy), then onto the OOFlasherEntity facade (bead oo-9ht.49, amendment oo-6ia4
	item 3), and with that facade's deletion (bead oo-9ht.107) into the C++ class's overrides of
	the root's JS members. OOColor, which is C++ since bead oo-11m, is reached as OOColor
	through oo::ToCxx/oo::ToObjC (amendment oo-ppc, item 4). The flasher is the C++ OOFlasherEntity,
	found through its entity's C++ part (amendment oo-9ht.12 item 6). Messages to classes that are
	still Objective-C (ShipEntity, OOVisualEffectEntity, Entity) stay as they are, which is why the
	file is still .mm until Phase 4.
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

namespace {
static ooscript::Object sFlasherPrototype;
} // namespace

namespace {
static bool JSFlasherGetFlasherEntity(ooscript::Context context, ooscript::Object jsobj, OOFlasherEntity **outEntity);
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


static bool FlasherGetProperty(Context cx, Object obj, PropertyId propID, Value *value);
} // namespace
namespace {
static bool FlasherSetProperty(Context cx, Object obj, PropertyId propID, bool /*strict*/, Value *value);
} // namespace

namespace {
static bool FlasherRemove(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace


namespace {
static ClassDef sFlasherClass =
{
	"Flasher",
	ClassFlag::HasPrivate,
	
	nullptr,		// addProperty
	nullptr,		// delProperty
	FlasherGetProperty,		// getProperty
	FlasherSetProperty,		// setProperty
	nullptr,		// enumerate
	nullptr,			// newEnumerate (ooscript::ClassFlag::NewEnumerate not used)
	nullptr,			// resolve
	nullptr,			// convert
	OOJSCxxObjectWrapperFinalize,// finalize
	nullptr,			// call
	nullptr,			// construct
	nullptr,			// backend: owned by the facade backend, must start null
};
} // namespace


enum : std::uint8_t
{
	// Property IDs
	kFlasher_active,
	kFlasher_color,
	kFlasher_fraction,
	kFlasher_frequency,
	kFlasher_phase,
	kFlasher_size
};


namespace {
static PropertySpec sFlasherProperties[] =
{
	// JS name							ID									flags
	{ "active",	   			kFlasher_active,  		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "color",	   			kFlasher_color,	  		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "fraction",  			kFlasher_fraction,		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "frequency", 			kFlasher_frequency,		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "phase",	   			kFlasher_phase,	  		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "size",	   			kFlasher_size,	  		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ 0 }
};
} // namespace


// Mirror of sFlasherProperties with the read-only/read-write flags the shared error reporters
// describe the properties by (see OOJSVector.mm's sVectorPropertiesRaw).
namespace {
static ooscript::PropertySpec sFlasherPropertiesRaw[] =
{
	// JS name							ID									flags
	{ "active",	   			kFlasher_active,  		OOJS_PROP_READWRITE_CB },
	{ "color",	   			kFlasher_color,	  		OOJS_PROP_READWRITE_CB },
	{ "fraction",  			kFlasher_fraction,		OOJS_PROP_READWRITE_CB },
	{ "frequency", 			kFlasher_frequency,		OOJS_PROP_READWRITE_CB },
	{ "phase",	   			kFlasher_phase,	  		OOJS_PROP_READWRITE_CB },
	{ "size",	   			kFlasher_size,	  		OOJS_PROP_READWRITE_CB },
	{ 0 }
};
} // namespace


namespace {
static FunctionSpec sFlasherMethods[] =
{
	// JS name					Function						min args	flags
	{ "remove",         FlasherRemove,    0,	0 },

	{ 0 }
};
} // namespace


void InitOOJSFlasher(ooscript::Context context, ooscript::Object global)
{
	Object proto = ooscript::initClass((context), (global), (JSEntityPrototype()), &sFlasherClass, OOJSUnconstructableConstruct, 0, sFlasherProperties, sFlasherMethods, NULL, NULL);
	sFlasherPrototype = (proto);
	OOJSRegisterObjectConverter(&sFlasherClass, OOJSEntityObjectConverter);
	OOJSRegisterSubclass(&sFlasherClass, JSEntityClass());
}


namespace {
static bool JSFlasherGetFlasherEntity(ooscript::Context context, ooscript::Object jsobj, OOFlasherEntity **outEntity)
{
	OOJS_PROFILE_ENTER

	bool						result;
	Entity					*entity = nullptr;	// the slot holds the C++ entity (bead oo-9ht.39.3)

	if (outEntity == NULL)  return false;
	*outEntity = nullptr;

	result = OOJSEntityGetEntity(context, jsobj, &entity);
	if (!result)  return false;

	// The object is the nearest façade left (OOLightParticleEntity's): a flasher is its C++ part.
	OOFlasherEntity *flasher = dynamic_cast<OOFlasherEntity *>(entity);
	if (flasher == nullptr)  return false;

	*outEntity = flasher;	// the natives no longer ask its object (bead oo-9ht.39.8.20)
	return true;
	
	OOJS_PROFILE_EXIT
}
} // namespace


// The bodies of OOFlasherEntity (OOJavaScriptExtensions), which the C++ class's overrides of the
// root's JS members call (bead oo-9ht.107; proposed ADR-0056 amendments oo-ppc, oo-ykoy, oo-6ia4
// and oo-9ht.107).
void OOJSFlasherGetJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)
{
	*outClass = &sFlasherClass;
	*outPrototype = sFlasherPrototype;
}

std::optional<std::string> OOJSFlasherJSClassName(void)
{
	return std::string("Flasher");
}

bool OOJSFlasherIsVisibleToScripts(void)
{
	return true;
}


namespace {
static bool FlasherGetProperty(Context cx, Object obj, PropertyId propID, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);
	ooscript::Value *value_raw = value;
	
	OOJS_NATIVE_ENTER(context)
	
	OOFlasherEntity				*entity = nullptr;
	oo::PList result;	// null: nil

	if (!JSFlasherGetFlasherEntity(context, thisObj, &entity))  return false;
	if (entity == nullptr)  { *value_raw = ooscript::undefinedValue(); return true; }
	
	switch (ooscript::idToInt32(propID))
	{
		case kFlasher_active:
			*value_raw = OOJSValueFromBOOL(entity->isActive());
			return true;

		case kFlasher_color:
			result = NormalizedColorComponents(entity->color().get());
			break;

		case kFlasher_frequency:
			return ooscript::newNumberValue(cx, entity->frequency(), value);

		case kFlasher_fraction:
			return ooscript::newNumberValue(cx, entity->fraction(), value);

		case kFlasher_phase:
			return ooscript::newNumberValue(cx, entity->phase(), value);

		case kFlasher_size:
			return ooscript::newNumberValue(cx, entity->diameter(), value);

		default:
			OOJSReportBadPropertySelector(context, thisObj, (propID), sFlasherPropertiesRaw);
			return false;
	}

	*value_raw = OOJSValueFromPList(context, result);
	return true;
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool FlasherSetProperty(Context cx, Object obj, PropertyId propID, bool /*strict*/, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);
	ooscript::Value *value_raw = value;
	
	OOJS_NATIVE_ENTER(context)
	
	OOFlasherEntity		*entity = nullptr;
	double          	fValue;
	bool				bValue;
	oo::Ref<OOColor>	colorForScript;
	
	if (!JSFlasherGetFlasherEntity(context, thisObj, &entity)) return false;
	if (entity == nullptr)  return true;
	
	switch (ooscript::idToInt32(propID))
	{
		case kFlasher_active:
			if (ooscript::valueToBoolean(cx, (*value_raw), &bValue))
			{
				entity->setActive((bool)bValue);
				return true;
			}
			break;

		case kFlasher_color:
			colorForScript = OOColor::colorWithDescription(cxx_OOJSPListFromJSValue(context, *value_raw));
			if (colorForScript != nullptr || ooscript::isNull(*value_raw))
			{
				entity->setColor(colorForScript.get());
				return true;
			}
			break;

		case kFlasher_frequency:
			if (ooscript::valueToNumber(cx, (*value_raw), &fValue))
			{
				if (fValue >= 0.0)
				{
					entity->setFrequency(fValue);
					return true;
				}
			}
			break;

		case kFlasher_fraction:
			if (ooscript::valueToNumber(cx, (*value_raw), &fValue))
			{
				if (fValue > 0.0 && fValue <= 1.0)
				{
					entity->setFraction(fValue);
					return true;
				}
			}
			break;

		case kFlasher_phase:
			if (ooscript::valueToNumber(cx, (*value_raw), &fValue))
			{
				entity->setPhase(fValue);
				return true;
			}
			break;

		case kFlasher_size:
			if (ooscript::valueToNumber(cx, (*value_raw), &fValue))
			{
				if (fValue > 0.0)
				{
					entity->setDiameter(fValue);
					return true;
				}
			}
			break;

		default:
			OOJSReportBadPropertySelector(context, thisObj, (propID), sFlasherPropertiesRaw);
			return false;
	}
	
	OOJSReportBadPropertyValue(context, thisObj, (propID), sFlasherPropertiesRaw, *value_raw);
	return false;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// *** Methods ***

#define GET_THIS_FLASHER(THISENT) do { \
	if (EXPECT_NOT(!JSFlasherGetFlasherEntity(context, OOJS_THIS, &(THISENT))))  return false; /* Exception */ \
	if (OOIsStaleEntity(THISENT))  OOJS_RETURN_VOID;	/* the C++ flasher's (bead oo-9ht.39.8.20) */ \
} while (0)


namespace {
static bool FlasherRemove(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	OOFlasherEntity				*thisEnt = nullptr;
	GET_THIS_FLASHER(thisEnt);

	Entity			*parent = thisEnt->owner();	// the C++ member its object's -owner answered (beads oo-9ht.39.8.20, oo-dpyk8)
	if (oo::EntityIsShip(parent))
	{
		if (oo::ToShip(parent) != nullptr)  oo::ToShip(parent)->removeFlasher(thisEnt);
	}
	else
	{
		if (OOVisualEffectEntity *effect = oo::ToEffect(parent))  effect->removeSubEntity(thisEnt);	// C++ since bead oo-9ht.165; the C++ flasher (bead oo-9ht.39.8.20)
	}

	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace
