/*
OOJSFlasher.m (QuickJS-ng)

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

#import "OOJSFlasher.h"
#import "EntityOOJavaScriptExtensions.h"
#import "OOColor.h"
#import "OOFlasherEntity.h"
#import "OOJSEntity.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import "OOVisualEffectEntity.h"
#import "ShipEntity.h"

/*
        C++20 since bead oo-ub2g, converted the way bead oo-ppc converted OOJSVector.mm (proposed
        ADR-0056 amendment oo-ppc). The JS class was already C++ on QuickJS-ng;
        OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
        (OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. The category on OOFlasherEntity
        became free functions, and its methods and interface moved to a bridge file of the binding
        (amendment oo-ykoy), then onto the OOFlasherEntity facade (bead oo-9ht.49, amendment oo-6ia4
        item 3), and with that facade's deletion into the C++ class's overrides of the root's JS
        members. OOColor, which is C++ since bead oo-11m, is reached as OOColor through
        oo::ToCxx/oo::ToObjC (amendment oo-ppc, item 4). The flasher is the C++ OOFlasherEntity, found
        through its entity's C++ part. Messages to classes that are still Objective-C (ShipEntity,
        OOVisualEffectEntity, Entity) stay as they are, which is why the file is still .mm until Phase 4.
*/

static JSClassID sFlasherClassID;

static bool JSFlasherGetFlasherEntity(JSContext* context, JSValueConst jsobj, OOFlasherEntity** outEntity);

static JSValue FlasherGetProperty(OOJS_GETTER_ARGS);
static JSValue FlasherSetProperty(OOJS_SETTER_ARGS);

static JSValue FlasherRemove(OOJS_NATIVE_ARGS);

namespace {

    // A colour's components as its -normalizedArray gave them to JavaScript: floats, null for no colour.
    oo::PList NormalizedColorComponents(OOColor* color)
    {
        if (color == nullptr)
            return oo::PList();
        oo::PList::Array components;
        for (float component : color->normalizedArray())
            components.push_back(oo::PList::singleReal(component));
        return oo::PList(std::move(components));
    }

} // namespace

static JSClassDef sFlasherClass = {
    .class_name = "Flasher",
    .finalizer = OOJSCxxObjectWrapperFinalize, // the slot holds an OOJSEntityHolder
};

enum {
    // Property IDs
    kFlasher_active,
    kFlasher_color,
    kFlasher_fraction,
    kFlasher_frequency,
    kFlasher_phase,
    kFlasher_size
};

static const JSCFunctionListEntry sFlasherProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RW("active", FlasherGetProperty, FlasherSetProperty, kFlasher_active),
    OOJS_PROPERTY_RW("color", FlasherGetProperty, FlasherSetProperty, kFlasher_color),
    OOJS_PROPERTY_RW("fraction", FlasherGetProperty, FlasherSetProperty, kFlasher_fraction),
    OOJS_PROPERTY_RW("frequency", FlasherGetProperty, FlasherSetProperty, kFlasher_frequency),
    OOJS_PROPERTY_RW("phase", FlasherGetProperty, FlasherSetProperty, kFlasher_phase),
    OOJS_PROPERTY_RW("size", FlasherGetProperty, FlasherSetProperty, kFlasher_size),
};

static const JSCFunctionListEntry sFlasherMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("remove", 0, FlasherRemove),
};

void InitOOJSFlasher(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sFlasherClassID, &sFlasherClass);

    JSValue parentPrototype = JS_GetClassProto(context, JSEntityClassID());
    OOCAssert(JS_IsObject(parentPrototype), "Entity must be initialized before Flasher.");
    OOJSInitClass(context, global, sFlasherClassID, parentPrototype, OOJSUnconstructableConstruct, 0,
        sFlasherProperties, OOJS_COUNT(sFlasherProperties), sFlasherMethods, OOJS_COUNT(sFlasherMethods), NULL, 0);
    JS_FreeValue(context, parentPrototype);

    OOJSRegisterObjectConverter(sFlasherClassID, OOJSEntityObjectConverter);
    OOJSRegisterSubclass(sFlasherClassID, JSEntityClassID());
}

JSClassID JSFlasherClassID(void)
{
    return sFlasherClassID;
}

static bool JSFlasherGetFlasherEntity(JSContext* context, JSValueConst jsobj, OOFlasherEntity** outEntity)
{
    OOJS_PROFILE_ENTER

    bool result;
    Entity* entity = nullptr; // the slot holds the C++ entity

    if (outEntity == NULL)
        return false;
    *outEntity = nullptr;

    result = OOJSEntityGetEntity(context, jsobj, &entity);
    if (!result)
        return false;

    // The object is the nearest facade left (OOLightParticleEntity's): a flasher is its C++ part.
    OOFlasherEntity* flasher = dynamic_cast<OOFlasherEntity*>(entity);
    if (flasher == nullptr)
        return false;

    *outEntity = flasher; // the natives no longer ask its object
    return true;

    OOJS_PROFILE_EXIT
}

// The bodies of OOFlasherEntity (OOJavaScriptExtensions), which the C++ class's overrides of the
// root's JS members call (proposed ADR-0056 amendments oo-ppc, oo-ykoy and oo-6ia4).
std::optional<std::string> OOJSFlasherJSClassName(void)
{
    return std::string("Flasher");
}

bool OOJSFlasherIsVisibleToScripts(void)
{
    return true;
}

static JSValue FlasherGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOFlasherEntity* entity = nullptr;
    oo::PList result; // null: nil

    if (!JSFlasherGetFlasherEntity(context, thisObj, &entity))
        return OOJSNativeFailure(context);
    if (entity == nullptr) {
        return JS_UNDEFINED;
    }

    switch (magic) {
    case kFlasher_active:
        return OOJSValueFromBOOL(entity->isActive());

    case kFlasher_color:
        result = NormalizedColorComponents(entity->color().get());
        break;

    case kFlasher_frequency:
        return JS_NewNumber(context, entity->frequency());

    case kFlasher_fraction:
        return JS_NewNumber(context, entity->fraction());

    case kFlasher_phase:
        return JS_NewNumber(context, entity->phase());

    case kFlasher_size:
        return JS_NewNumber(context, entity->diameter());

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sFlasherProperties, OOJS_COUNT(sFlasherProperties));
        return OOJSNativeFailure(context);
    }

    return OOJSValueFromPList(context, result);

    OOJS_NATIVE_EXIT
}

static JSValue FlasherSetProperty(OOJS_SETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOFlasherEntity* entity = nullptr;
    double fValue;
    int bValue;
    oo::Ref<OOColor> colorForScript;

    if (!JSFlasherGetFlasherEntity(context, thisObj, &entity))
        return OOJSNativeFailure(context);
    if (entity == nullptr)
        return JS_UNDEFINED;

    switch (magic) {
    case kFlasher_active:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            entity->setActive((bool)bValue);
            return JS_UNDEFINED;
        }
        break;

    case kFlasher_color:
        colorForScript = OOColor::colorWithDescription(cxx_OOJSPListFromJSValue(context, value));
        if (colorForScript != nullptr || JS_IsNull(value)) {
            entity->setColor(colorForScript.get());
            return JS_UNDEFINED;
        }
        break;

    case kFlasher_frequency:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (fValue >= 0.0) {
                entity->setFrequency(fValue);
                return JS_UNDEFINED;
            }
        }
        break;

    case kFlasher_fraction:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (fValue > 0.0 && fValue <= 1.0) {
                entity->setFraction(fValue);
                return JS_UNDEFINED;
            }
        }
        break;

    case kFlasher_phase:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            entity->setPhase(fValue);
            return JS_UNDEFINED;
        }
        break;

    case kFlasher_size:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (fValue > 0.0) {
                entity->setDiameter(fValue);
                return JS_UNDEFINED;
            }
        }
        break;

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sFlasherProperties, OOJS_COUNT(sFlasherProperties));
        return OOJSNativeFailure(context);
    }

    OOJSReportBadPropertyValue(context, thisObj, magic, sFlasherProperties, OOJS_COUNT(sFlasherProperties), value);
    return OOJSNativeFailure(context);

    OOJS_NATIVE_EXIT
}

// *** Methods ***

#define GET_THIS_FLASHER(THISENT)                                                   \
    do {                                                                            \
        if (EXPECT_NOT(!JSFlasherGetFlasherEntity(context, OOJS_THIS, &(THISENT)))) \
            return OOJSNativeFailure(context); /* Exception */                      \
        if (OOIsStaleEntity(THISENT))                                               \
            OOJS_RETURN_VOID; /* the C++ flasher's */                               \
    } while (0)

static JSValue FlasherRemove(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOFlasherEntity* thisEnt = nullptr;
    GET_THIS_FLASHER(thisEnt);

    Entity* parent = thisEnt->owner(); // the C++ member its object's -owner answered
    if (oo::EntityIsShip(parent)) {
        if (oo::ToShip(parent) != nullptr)
            oo::ToShip(parent)->removeFlasher(thisEnt);
    } else {
        if (OOVisualEffectEntity* effect = oo::ToEffect(parent))
            effect->removeSubEntity(thisEnt); // the C++ flasher
    }

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}
