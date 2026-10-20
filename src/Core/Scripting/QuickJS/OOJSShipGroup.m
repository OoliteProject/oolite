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
#import "OOShipGroup.h"
#import "ShipEntity.h"

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
    id result = nil;

    if (EXPECT_NOT(!JSShipGroupGetShipGroup(context, this, &group)))
        return OOJSNativeFailure(context);

    switch (magic) {
    case kShipGroup_ships:
        result = [group memberArray];
        if (result == nil)
            result = [NSArray array];
        break;

    case kShipGroup_leader:
        result = [group leader];
        break;

    case kShipGroup_name:
        result = [group name];
        if (result == nil)
            result = [NSNull null];
        break;

    case kShipGroup_count:
        return JS_NewNumber(context, [group count]);

    default:
        OOJSReportBadPropertySelector(context, this, magic, sShipGroupProperties, OOJS_COUNT(sShipGroupProperties));
        return OOJSNativeFailure(context);
    }

    return OOJSValueFromNativeObject(context, result);

    OOJS_NATIVE_EXIT
}

static JSValue ShipGroupSetProperty(OOJS_SETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOShipGroup* group = nil;
    ShipEntity* shipValue = nil;

    if (EXPECT_NOT(!JSShipGroupGetShipGroup(context, this, &group)))
        return OOJSNativeFailure(context);

    switch (magic) {
    case kShipGroup_leader:
        shipValue = OOJSNativeObjectOfClassFromJSValue(context, value, [ShipEntity class]);
        if (shipValue != nil || JS_IsNull(value)) {
            [group setLeader:shipValue];
            return JS_UNDEFINED;
        }
        break;

    case kShipGroup_name:
        [group setName:OOStringFromJSValueEvenIfNull(context, value)];
        return JS_UNDEFINED;
        break;

    default:
        OOJSReportBadPropertySelector(context, this, magic, sShipGroupProperties, OOJS_COUNT(sShipGroupProperties));
        return OOJSNativeFailure(context);
    }

    OOJSReportBadPropertyValue(context, this, magic, sShipGroupProperties, OOJS_COUNT(sShipGroupProperties), value);
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
        OOJSReportError(context, @"ShipGroup() cannot be called as a function, it must be used as a constructor (as in new ShipGroup(...)).");
        return JS_EXCEPTION;
    }

    NSString* name = nil;
    ShipEntity* leader = nil;

    if (argc >= 1) {
        if (!JS_IsString(OOJS_ARGV[0])) {
            OOJSReportBadArguments(context, nil, @"ShipGroup()", 1, OOJS_ARGV, @"Could not create ShipGroup", @"group name");
            return OOJSNativeFailure(context);
        }
        name = OOStringFromJSValue(context, OOJS_ARGV[0]);
    }

    if (argc >= 2) {
        leader = OOJSNativeObjectOfClassFromJSValue(context, OOJS_ARGV[1], [ShipEntity class]);
        if (leader == nil && !JS_IsNull(OOJS_ARGV[1])) {
            OOJSReportBadArguments(context, nil, @"ShipGroup()", 1, OOJS_ARGV + 1, @"Could not create ShipGroup", @"ship");
            return OOJSNativeFailure(context);
        }
    }

    OOJS_RETURN_OBJECT([OOShipGroup groupWithName:name leader:leader]);

    OOJS_NATIVE_EXIT
}

@implementation OOShipGroup (OOJavaScriptExtensions)

/*	As with SpiderMonkey, the JS object retains the group, and _jsSelf is a
        weak (uncounted) reference to the JS object, cleared by -oo_clearJSSelf:
        when the JS object is finalized.
*/
- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    if (!JS_IsObject(_jsSelf)) {
        JSValue jsSelf = JS_NewObjectClass(context, (int)sShipGroupClassID);
        if (JS_IsException(jsSelf)) {
            JS_FreeValue(context, JS_GetException(context));
            return JS_NULL;
        }
        JS_SetOpaque(jsSelf, [self retain]);

        // Weak: the caller gets the only reference.
        _jsSelf = jsSelf;
        return jsSelf;
    }

    return JS_DupValue(context, _jsSelf);
}

- (void)oo_clearJSSelf:(JSValueConst)selfVal
{
    if (JS_IsObject(_jsSelf) && JS_VALUE_GET_PTR(_jsSelf) == JS_VALUE_GET_PTR(selfVal))
        _jsSelf = JS_UNDEFINED;
}

@end

// *** Methods ***

// addShip(ship : Ship)
static JSValue ShipGroupAddShip(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOShipGroup* thisGroup = nil;
    ShipEntity* ship = nil;
    BOOL OK = YES;

    if (EXPECT_NOT(!JSShipGroupGetShipGroup(context, OOJS_THIS, &thisGroup)))
        return OOJSNativeFailure(context);

    if (argc > 0)
        ship = OOJSNativeObjectOfClassFromJSValue(context, OOJS_ARGV[0], [ShipEntity class]);
    if (ship == nil) {
        if (argc > 0 && JS_IsNull(OOJS_ARGV[0]))
            OOJS_RETURN_VOID; // OK, do nothing for null ship.

        OOJSReportBadArguments(context, @"ShipGroup", @"addShip", MIN(argc, 1), OOJS_ARGV, nil, @"ship");
        return OOJSNativeFailure(context);
    }

    if ([thisGroup containsShip:ship]) {
        // nothing to do...
        OOJS_RETURN_VOID;
    } else {
        ShipEntity* thisGroupLeader = [thisGroup leader];

        if ([thisGroupLeader escortGroup] == thisGroup) // escort group!
        {
            if ([thisGroup count] > 1) // already with some escorts
            {
                OOShipGroup* thatGroup = [ship group];
                if ([thatGroup count] > 1 && [[thatGroup leader] escortGroup] == thatGroup) // new escort already escorting!
                {
                    OOJSReportWarningForCaller(context, @"ShipGroup", @"addShip", @"Ship %@ cannot be assigned to two escort groups, ignoring.", ship);
                    OK = NO;
                } else {
                    OK = [thisGroupLeader acceptAsEscort:ship];
                }
            } else // [thisGroup count] == 1, default unescorted ship?
            {
                if ([thisGroupLeader escortGroup] == [thisGroupLeader group]) {
                    // Default unescorted, unescortable, ship. Create new group and use that instead.
                    [thisGroupLeader setGroup:[[OOShipGroup alloc] initWithName:@"ship group"]];
                    thisGroup = [thisGroupLeader group];
                } else {
                    // Unescorted ship with custom group. See if it accepts escorts.
                    OK = [thisGroupLeader acceptAsEscort:ship];
                }
            }
        }
        if (OK) {
            OOJS_RETURN_BOOL([thisGroup addShip:ship]); // if ship is there already, noop & YES
        } else
            OOJS_RETURN_BOOL(NO);
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

        OOJSReportBadArguments(context, @"ShipGroup", @"removeShip", MIN(argc, 1), OOJS_ARGV, nil, @"ship");
        return OOJSNativeFailure(context);
    }

    OOJS_RETURN_BOOL([thisGroup removeShip:ship]);

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
            OOJS_RETURN_BOOL(NO); // OK, return false for null ship.

        OOJSReportBadArguments(context, @"ShipGroup", @"containsShip", MIN(argc, 1), OOJS_ARGV, nil, @"ship");
        return OOJSNativeFailure(context);
    }

    OOJS_RETURN_BOOL([thisGroup containsShip:ship]);

    OOJS_NATIVE_EXIT
}
