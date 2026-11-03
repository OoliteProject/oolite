/*

OOShipGroup.m


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

#import "OOJSShipGroup.h"
#import "EntityOOJavaScriptExtensions.h"
#import "OOJavaScriptEngine.h"
#import "OOObjCPList.h"
#import "OOShipGroup.h"
#import "ShipEntity.h"

#include "oofnd/objc/OOAssert.h"

/*
        C++20 since bead oo-n64m, converted the way bead oo-ppc converted OOJSVector.mm (proposed
        ADR-0056 amendment oo-ppc). The JS class was already C++ on QuickJS-ng;
        OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
        (OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. The category on the OOShipGroup
        façade became two free functions that take its _jsSelf ivar by reference, and its methods moved
        to OOJSShipGroup+ObjCBridge.mm (amendments oo-ykoy and oo-bwrq). OOShipGroup, which is C++ since
        bead oo-bwrq, is reached as cxx::OOShipGroup through oo::ToCxx/oo::ToObjC (amendment oo-ppc,
        item 4), null-guarded where a message to nil answered. Messages to classes that are still
        Objective-C (ShipEntity) stay as they are, which is why the file is still .mm until Phase 4.
*/

static JSClassID sShipGroupClassID;

static JSValue ShipGroupGetProperty(OOJS_GETTER_ARGS);
static JSValue ShipGroupSetProperty(OOJS_SETTER_ARGS);
static JSValue ShipGroupConstruct(OOJS_NATIVE_ARGS);

// Methods
static JSValue ShipGroupAddShip(OOJS_NATIVE_ARGS);
static JSValue ShipGroupRemoveShip(OOJS_NATIVE_ARGS);
static JSValue ShipGroupContainsShip(OOJS_NATIVE_ARGS);

static JSClassDef sShipGroupClass = {
    .class_name = "ShipGroup",
    .finalizer = OOJSObjectWrapperFinalize,
};

enum {
    // Property IDs
    kShipGroup_ships, // array of ships, double, read-only
    kShipGroup_leader, // leader, Ship, read/write
    kShipGroup_name, // name, string, read/write
    kShipGroup_count, // number of ships, integer, read-only
};

static const JSCFunctionListEntry sShipGroupProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RO("count", ShipGroupGetProperty, kShipGroup_count),
    OOJS_PROPERTY_RW("leader", ShipGroupGetProperty, ShipGroupSetProperty, kShipGroup_leader),
    OOJS_PROPERTY_RW("name", ShipGroupGetProperty, ShipGroupSetProperty, kShipGroup_name),
    OOJS_PROPERTY_RO("ships", ShipGroupGetProperty, kShipGroup_ships),
};

static const JSCFunctionListEntry sShipGroupMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("toString", 0, OOJSObjectWrapperToString),
    JS_CFUNC_DEF("addShip", 1, ShipGroupAddShip),
    JS_CFUNC_DEF("containsShip", 1, ShipGroupContainsShip),
    JS_CFUNC_DEF("removeShip", 1, ShipGroupRemoveShip),
};

DEFINE_JS_OBJECT_GETTER(JSShipGroupGetShipGroup, sShipGroupClassID, OOShipGroup)

void InitOOJSShipGroup(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sShipGroupClassID, &sShipGroupClass);
    OOJSInitClass(context, global, sShipGroupClassID, JS_UNDEFINED, ShipGroupConstruct, 0,
        sShipGroupProperties, OOJS_COUNT(sShipGroupProperties), sShipGroupMethods, OOJS_COUNT(sShipGroupMethods), NULL, 0);
    OOJSRegisterObjectConverter(sShipGroupClassID, OOJSBasicPrivateObjectConverter);
}

static JSValue ShipGroupGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOShipGroup* group = nil;
    oo::PList result; // null: nil

    if (EXPECT_NOT(!JSShipGroupGetShipGroup(context, thisObj, &group)))
        return OOJSNativeFailure(context);
    cxx::OOShipGroup* cxxGroup = oo::ToCxx(group); // null for the prototype: each use answers what a message to nil did

    switch (magic) {
    case kShipGroup_ships:
        result = oo::PListFromObjects((cxxGroup != nullptr) ? cxxGroup->memberArray() : std::vector<oo::ObjCRef<ShipEntity*>>()); // (no C++ value from a message to nil; an empty array)
        break;

    case kShipGroup_leader:
        result = oo::PListObject((cxxGroup != nullptr) ? cxxGroup->leader() : nil);
        break;

    case kShipGroup_name: {
        const std::optional<std::string> name = (cxxGroup != nullptr) ? cxxGroup->name() : std::nullopt;
        result = name.has_value() ? oo::PList(*name) : oo::PListObject([OONull null]);
        break;
    }

    case kShipGroup_count:
        return JS_NewNumber(context, (cxxGroup != nullptr) ? cxxGroup->count() : 0);

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sShipGroupProperties, OOJS_COUNT(sShipGroupProperties));
        return OOJSNativeFailure(context);
    }

    return OOJSValueFromPList(context, result);

    OOJS_NATIVE_EXIT
}

static JSValue ShipGroupSetProperty(OOJS_SETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOShipGroup* group = nil;
    ShipEntity* shipValue = nil;

    if (EXPECT_NOT(!JSShipGroupGetShipGroup(context, thisObj, &group)))
        return OOJSNativeFailure(context);
    cxx::OOShipGroup* cxxGroup = oo::ToCxx(group); // null for the prototype: the setters do nothing, as messages to nil

    switch (magic) {
    case kShipGroup_leader:
        shipValue = OOJSNativeObjectOfClassFromJSValue(context, value, [ShipEntity class]);
        if (shipValue != nil || JS_IsNull(value)) {
            if (cxxGroup != nullptr)
                cxxGroup->setLeader(shipValue);
            return JS_UNDEFINED;
        }
        break;

    case kShipGroup_name: {
        const std::optional<std::string> name = cxx_OOStringFromJSValueEvenIfNull(context, value);
        if (cxxGroup != nullptr)
            cxxGroup->setName(name);
    }
        return JS_UNDEFINED;
        break;

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sShipGroupProperties, OOJS_COUNT(sShipGroupProperties));
        return OOJSNativeFailure(context);
    }

    OOJSReportBadPropertyValue(context, thisObj, magic, sShipGroupProperties, OOJS_COUNT(sShipGroupProperties), value);
    return OOJSNativeFailure(context);

    OOJS_NATIVE_EXIT
}

// new ShipGroup([name : String [, leader : Ship]]) : ShipGroup
static JSValue ShipGroupConstruct(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    /*	QuickJS has no JS_IsConstructing(). When a constructor_or_func native is
            called with new, this is new.target (a constructor); when it is
            called as a function, this is the caller's this.
    */
    if (EXPECT_NOT(!OOJS_IS_CONSTRUCTING)) {
        cxx_OOJSReportError(context, "ShipGroup() cannot be called as a function, it must be used as a constructor (as in new ShipGroup(...)).");
        return JS_EXCEPTION;
    }

    std::optional<std::string> name;
    ShipEntity* leader = nil;

    if (argc >= 1) {
        if (!JS_IsString(OOJS_ARGV[0])) {
            cxx_OOJSReportBadArguments(context, std::nullopt, "ShipGroup()", 1, OOJS_ARGV, "Could not create ShipGroup", "group name");
            return OOJSNativeFailure(context);
        }
        name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    }

    if (argc >= 2) {
        leader = OOJSNativeObjectOfClassFromJSValue(context, OOJS_ARGV[1], [ShipEntity class]);
        if (leader == nil && !JS_IsNull(OOJS_ARGV[1])) {
            cxx_OOJSReportBadArguments(context, std::nullopt, "ShipGroup()", 1, OOJS_ARGV + 1, "Could not create ShipGroup", "ship");
            return OOJSNativeFailure(context);
        }
    }

    OOJS_RETURN_OBJECT(oo::ToObjC(cxx::OOShipGroup::groupWithName(name, leader))); // +cxx_groupWithName:leader:

    OOJS_NATIVE_EXIT
}

/*	The bodies of OOShipGroup (OOJavaScriptExtensions), whose methods are in
        OOJSShipGroup+ObjCBridge.mm until the façade goes (proposed ADR-0056 amendments oo-ppc and
        oo-ykoy). The group's JS object is the façade's ivar _jsSelf (amendment oo-bwrq, item 1), which
        the methods pass by reference: the JS object's private slot holds the façade, retained
        (amendment oo-ppc, item 5).

        As with SpiderMonkey, the JS object retains the group, and _jsSelf is a
        weak (uncounted) reference to the JS object, cleared by -oo_clearJSSelf:
        when the JS object is finalized.
*/
JSValue OOJSShipGroupJSValueInContext(OOShipGroup* group, JSValue& jsSelf, JSContext* context)
{
    if (!JS_IsObject(jsSelf)) {
        JSValue newSelf = JS_NewObjectClass(context, (int)sShipGroupClassID);
        if (JS_IsException(newSelf)) {
            JS_FreeValue(context, JS_GetException(context));
            return JS_NULL;
        }
        JS_SetOpaque(newSelf, [group retain]);

        // Weak: the caller gets the only reference.
        jsSelf = newSelf;
        return newSelf;
    }

    return JS_DupValue(context, jsSelf);
}

void OOJSShipGroupClearJSSelf(JSValue& jsSelf, JSValueConst selfVal)
{
    if (JS_IsObject(jsSelf) && JS_VALUE_GET_PTR(jsSelf) == JS_VALUE_GET_PTR(selfVal))
        jsSelf = JS_UNDEFINED;
}

// *** Methods ***

// addShip(ship : Ship)
static JSValue ShipGroupAddShip(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOShipGroup* thisGroup = nil;
    ShipEntity* ship = nil;
    bool OK = true;

    if (EXPECT_NOT(!JSShipGroupGetShipGroup(context, OOJS_THIS, &thisGroup)))
        return OOJSNativeFailure(context);

    if (argc > 0)
        ship = OOJSNativeObjectOfClassFromJSValue(context, OOJS_ARGV[0], [ShipEntity class]);
    if (ship == nil) {
        if (argc > 0 && JS_IsNull(OOJS_ARGV[0]))
            OOJS_RETURN_VOID; // OK, do nothing for null ship.

        cxx_OOJSReportBadArguments(context, "ShipGroup", "addShip", MIN(argc, 1), OOJS_ARGV, std::nullopt, "ship");
        return OOJSNativeFailure(context);
    }

    // The groups are C++; a null one (the prototype's, or a ship's that has none) answers what a
    // message to nil did. The façades still identify the groups the ships hold (one per group).
    cxx::OOShipGroup* cxxGroup = oo::ToCxx(thisGroup);

    if (cxxGroup != nullptr && cxxGroup->containsShip(ship)) {
        // nothing to do...
        OOJS_RETURN_VOID;
    } else {
        ShipEntity* thisGroupLeader = (cxxGroup != nullptr) ? cxxGroup->leader() : nil;

        if ([thisGroupLeader escortGroup] == thisGroup) // escort group!
        {
            if (((cxxGroup != nullptr) ? cxxGroup->count() : 0) > 1) // already with some escorts
            {
                OOShipGroup* thatGroup = [ship group];
                cxx::OOShipGroup* cxxThatGroup = oo::ToCxx(thatGroup);
                if (((cxxThatGroup != nullptr) ? cxxThatGroup->count() : 0) > 1 && [((cxxThatGroup != nullptr) ? cxxThatGroup->leader() : nil) escortGroup] == thatGroup) // new escort already escorting!
                {
                    cxx_OOJSReportWarningForCaller(context, "ShipGroup", "addShip", "Ship %s cannot be assigned to two escort groups, ignoring.", oo::DescriptionOf(ship).c_str());
                    OK = false;
                } else {
                    OK = [thisGroupLeader acceptAsEscort:ship];
                }
            } else // [thisGroup count] == 1, default unescorted ship?
            {
                if ([thisGroupLeader escortGroup] == [thisGroupLeader group]) {
                    // Default unescorted, unescortable, ship. Create new group and use that instead.
                    [thisGroupLeader setGroup:[oo::ToObjC(cxx::OOShipGroup::groupWithName(std::string("ship group"))) retain]]; // +1, as [[OOShipGroup alloc] cxx_initWithName:] was
                    thisGroup = [thisGroupLeader group];
                    cxxGroup = oo::ToCxx(thisGroup);
                } else {
                    // Unescorted ship with custom group. See if it accepts escorts.
                    OK = [thisGroupLeader acceptAsEscort:ship];
                }
            }
        }
        if (OK) {
            OOJS_RETURN_BOOL(cxxGroup != nullptr && cxxGroup->addShip(ship)); // if ship is there already, noop & YES
        } else
            OOJS_RETURN_BOOL(false);
    }

    OOJS_NATIVE_EXIT
}

// removeShip(ship : Ship)
static JSValue ShipGroupRemoveShip(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOShipGroup* thisGroup = nil;
    ShipEntity* ship = nil;

    if (EXPECT_NOT(!JSShipGroupGetShipGroup(context, OOJS_THIS, &thisGroup)))
        return OOJSNativeFailure(context);

    if (argc > 0)
        ship = OOJSNativeObjectOfClassFromJSValue(context, OOJS_ARGV[0], [ShipEntity class]);
    if (ship == nil) {
        if (argc > 0 && JS_IsNull(OOJS_ARGV[0]))
            OOJS_RETURN_VOID; // OK, do nothing for null ship.

        cxx_OOJSReportBadArguments(context, "ShipGroup", "removeShip", MIN(argc, 1), OOJS_ARGV, std::nullopt, "ship");
        return OOJSNativeFailure(context);
    }

    cxx::OOShipGroup* cxxGroup = oo::ToCxx(thisGroup); // null for the prototype: false, as a message to nil
    OOJS_RETURN_BOOL(cxxGroup != nullptr && cxxGroup->removeShip(ship));

    OOJS_NATIVE_EXIT
}

// containsShip(ship : Ship) : Boolean
static JSValue ShipGroupContainsShip(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOShipGroup* thisGroup = nil;
    ShipEntity* ship = nil;

    if (EXPECT_NOT(!JSShipGroupGetShipGroup(context, OOJS_THIS, &thisGroup)))
        return OOJSNativeFailure(context);

    if (argc > 0)
        ship = OOJSNativeObjectOfClassFromJSValue(context, OOJS_ARGV[0], [ShipEntity class]);
    if (ship == nil) {
        if (argc > 0 && JS_IsNull(OOJS_ARGV[0]))
            OOJS_RETURN_BOOL(false); // OK, return false for null ship.

        cxx_OOJSReportBadArguments(context, "ShipGroup", "containsShip", MIN(argc, 1), OOJS_ARGV, std::nullopt, "ship");
        return OOJSNativeFailure(context);
    }

    cxx::OOShipGroup* cxxGroup = oo::ToCxx(thisGroup); // null for the prototype: false, as a message to nil
    OOJS_RETURN_BOOL(cxxGroup != nullptr && cxxGroup->containsShip(ship));

    OOJS_NATIVE_EXIT
}
