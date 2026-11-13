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

#include "OOJSShipGroup.h"

#include <cstddef>
#include <format>
#include <optional>
#include <string>
#include <vector>

#include "EntityOOJavaScriptExtensions.h"
#include "OODescription.h"
#include "OOJSEntity.h"
#include "OOJavaScriptEngine.h"
#include "OOShipGroup.h"
#include "ShipEntity.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"

/*
        The group is C++ and is called directly, null-guarded where a message to
        nil answered.
*/

static JSClassID sShipGroupClassID;

static JSValue ShipGroupGetProperty(OOJS_GETTER_ARGS);
static JSValue ShipGroupSetProperty(OOJS_SETTER_ARGS);
static JSValue ShipGroupConstruct(OOJS_NATIVE_ARGS);

// Methods
static JSValue ShipGroupToString(OOJS_NATIVE_ARGS);
static JSValue ShipGroupAddShip(OOJS_NATIVE_ARGS);
static JSValue ShipGroupRemoveShip(OOJS_NATIVE_ARGS);
static JSValue ShipGroupContainsShip(OOJS_NATIVE_ARGS);

static JSClassDef sShipGroupClass = {
    .class_name = "ShipGroup",
    .finalizer = OOJSCxxObjectWrapperFinalize,  // the slot retains the group
};

namespace {

enum class ShipGroupProperty : std::int16_t {
  // Property IDs
  kShips,   // array of ships, double, read-only
  kLeader,  // leader, Ship, read/write
  kName,    // name, string, read/write
  kCount,   // number of ships, integer, read-only
};

}  // namespace

static const JSCFunctionListEntry sShipGroupProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RO("count", ShipGroupGetProperty, ShipGroupProperty::kCount),
    OOJS_PROPERTY_RW("leader", ShipGroupGetProperty, ShipGroupSetProperty,
                     ShipGroupProperty::kLeader),
    OOJS_PROPERTY_RW("name", ShipGroupGetProperty, ShipGroupSetProperty,
                     ShipGroupProperty::kName),
    OOJS_PROPERTY_RO("ships", ShipGroupGetProperty, ShipGroupProperty::kShips),
};

static const JSCFunctionListEntry sShipGroupMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("toString", 0, ShipGroupToString),
    JS_CFUNC_DEF("addShip", 1, ShipGroupAddShip),
    JS_CFUNC_DEF("containsShip", 1, ShipGroupContainsShip),
    JS_CFUNC_DEF("removeShip", 1, ShipGroupRemoveShip),
};

// The private object getter, DEFINE_JS_OBJECT_GETTER's equivalent for a slot
// that holds the C++ group (OOJSPrivateObject.h):
// OOJSGetCxxPrivate<OOShipGroup>(context, value, sShipGroupClassID, &group).

// OOJSBasicPrivateObjectConverter for the C++ group the slot holds: its node
// (null for the prototype).
static oo::PList ShipGroupConverter(JSContext* /*context*/,
                                    JSValueConst object) {
  OOShipGroup* group = static_cast<OOShipGroup*>(
      OOJSCxxPrivateFromOpaque(JS_GetOpaque(object, sShipGroupClassID)));
  if (group == nullptr) return oo::PList();
  return OOShipGroupObjectNode(group);
}

// *** Public ***

void InitOOJSShipGroup(JSContext* context, JSValueConst global) {
  OOJSRegisterClass(&sShipGroupClassID, &sShipGroupClass);
  OOJSInitClass(context, global, sShipGroupClassID, JS_UNDEFINED,
                ShipGroupConstruct, 0, sShipGroupProperties,
                OOJS_COUNT(sShipGroupProperties), sShipGroupMethods,
                OOJS_COUNT(sShipGroupMethods), nullptr, 0);
  OOJSRegisterObjectConverter(sShipGroupClassID, ShipGroupConverter);
}

static JSValue ShipGroupGetProperty(OOJS_GETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  oo::PList result;  // null: nil
  OOShipGroup* cxxGroup = nullptr;

  if (EXPECT_NOT(
          !OOJSGetCxxPrivate(context, thisObj, sShipGroupClassID, &cxxGroup)))
    return OOJSNativeFailure(context);
  // (null for the prototype: each use answers what a message to nil did

  switch (static_cast<ShipGroupProperty>(magic)) {
    using enum ShipGroupProperty;
    case kShips:
      result = oo::EntityNodesFrom(
          (cxxGroup != nullptr)
              ? cxxGroup->memberArray()
              : std::vector<oo::EntityHold>());  // (no C++ value from a message
                                                 // to nil; an empty array)
      break;

    case kLeader:
      result = oo::EntityObjectNode((cxxGroup != nullptr) ? cxxGroup->leader()
                                                          : nullptr);
      break;

    case kName: {
      const std::optional<std::string> name =
          (cxxGroup != nullptr) ? cxxGroup->name() : std::nullopt;
      result = name.has_value() ? oo::PList(*name) : OONullObjectNode();
      break;
    }

    case kCount:
      return JS_NewNumber(context,
                          (cxxGroup != nullptr) ? cxxGroup->count() : 0);

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic,
                                    sShipGroupProperties,
                                    OOJS_COUNT(sShipGroupProperties));
      return OOJSNativeFailure(context);
  }

  return OOJSValueFromPList(context, result);

  OOJS_NATIVE_EXIT
}

static JSValue ShipGroupSetProperty(OOJS_SETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* shipValue = nullptr;
  OOShipGroup* cxxGroup = nullptr;

  if (EXPECT_NOT(
          !OOJSGetCxxPrivate(context, thisObj, sShipGroupClassID, &cxxGroup)))
    return OOJSNativeFailure(context);
  // (null for the prototype: the setters do nothing, as messages to nil

  switch (static_cast<ShipGroupProperty>(magic)) {
    using enum ShipGroupProperty;
    case kLeader:
      shipValue = oo::ToShip(OOJSEntityFromJSValue(context, value));
      if (shipValue != nullptr || JS_IsNull(value)) {
        if (cxxGroup != nullptr) cxxGroup->setLeader(shipValue);
        return JS_UNDEFINED;
      }
      break;

    case kName: {
      const std::optional<std::string> name =
          cxx_OOStringFromJSValueEvenIfNull(context, value);
      if (cxxGroup != nullptr) cxxGroup->setName(name);
    }
      return JS_UNDEFINED;
      break;

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic,
                                    sShipGroupProperties,
                                    OOJS_COUNT(sShipGroupProperties));
      return OOJSNativeFailure(context);
  }

  OOJSReportBadPropertyValue(context, thisObj, magic, sShipGroupProperties,
                             OOJS_COUNT(sShipGroupProperties), value);
  return OOJSNativeFailure(context);

  OOJS_NATIVE_EXIT
}

// new ShipGroup([name : String [, leader : Ship]]) : ShipGroup
static JSValue ShipGroupConstruct(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  /*	QuickJS has no JS_IsConstructing(). When a constructor_or_func native is
          called with new, this is new.target (a constructor); when it is
          called as a function, this is the caller's this.
  */
  if (EXPECT_NOT(!OOJS_IS_CONSTRUCTING)) {
    cxx_OOJSReportError(context,
                        "ShipGroup() cannot be called as a function, it must "
                        "be used as a constructor (as in new ShipGroup(...)).");
    return JS_EXCEPTION;
  }

  std::optional<std::string> name;
  ShipEntity* leader = nullptr;

  if (argc >= 1) {
    if (!JS_IsString(OOJS_ARGV[0])) {
      cxx_OOJSReportBadArguments(context, std::nullopt, "ShipGroup()", 1,
                                 OOJS_ARGV, "Could not create ShipGroup",
                                 "group name");
      return OOJSNativeFailure(context);
    }
    name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  }

  if (argc >= 2) {
    leader = oo::ToShip(OOJSEntityFromJSValue(context, OOJS_ARGV[1]));
    if (leader == nullptr && !JS_IsNull(OOJS_ARGV[1])) {
      cxx_OOJSReportBadArguments(context, std::nullopt, "ShipGroup()", 1,
                                 OOJS_ARGV + 1, "Could not create ShipGroup",
                                 "ship");
      return OOJSNativeFailure(context);
    }
  }

  const std::shared_ptr<OOShipGroup> group = OOShipGroup::groupWithName(
      name, leader);  // kept until the JS object holds it
  OOJS_RETURN(OOJSValueFromCxxObject(context, group.get()));

  OOJS_NATIVE_EXIT
}

/*	The JS glue of the C++ group (OOJSPrivateObject). As with SpiderMonkey,
   the JS object retains the group (its private slot holds the group), and
   _jsSelf is a weak (uncounted) reference to the JS object, cleared by
   clearJSSelf() when the JS object is finalized.
*/
JSValue OOShipGroup::jsValueInContext(JSContext* context) {
  if (!JS_IsObject(_jsSelf)) {
    JSValue newSelf =
        JS_NewObjectClass(context, static_cast<int>(sShipGroupClassID));
    if (JS_IsException(newSelf)) {
      JS_FreeValue(context, JS_GetException(context));
      return JS_NULL;
    }
    if (!OOJSSetCxxPrivate(newSelf, oo::share(this))) {
      JS_FreeValue(context, newSelf);
      return JS_NULL;
    }

    // Weak: the caller gets the only reference.
    _jsSelf = newSelf;
    return newSelf;
  }

  return JS_DupValue(context, _jsSelf);
}

void OOShipGroup::clearJSSelf(JSValueConst selfVal) {
  if (JS_IsObject(_jsSelf) &&
      JS_VALUE_GET_PTR(_jsSelf) == JS_VALUE_GET_PTR(selfVal))
    _jsSelf = JS_UNDEFINED;
}

// What the façade's -cxx_oo_jsDescription answered (OOObject
// (OOJavaScriptConversion)): the class name (the façade had no jsClassName) and
// the components.
std::optional<std::string> OOShipGroup::jsDescription() {
  const std::optional<std::string> components = descriptionComponents();
  if (components.has_value())
    return std::format("[OOShipGroup {}]", *components);
  return std::string("[object OOShipGroup]");
}

// *** Methods ***

// toString() : String
static JSValue ShipGroupToString(OOJS_NATIVE_ARGS) {
  return OOJSCxxObjectWrapperToString(context, OOJS_THIS, sShipGroupClassID);
}

// addShip(ship : Ship)
static JSValue ShipGroupAddShip(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOShipGroup* cxxGroup = nullptr;
  ShipEntity* ship = nullptr;
  bool OK = true;

  if (EXPECT_NOT(
          !OOJSGetCxxPrivate(context, OOJS_THIS, sShipGroupClassID, &cxxGroup)))
    return OOJSNativeFailure(context);

  if (argc > 0) ship = oo::ToShip(OOJSEntityFromJSValue(context, OOJS_ARGV[0]));
  if (ship == nullptr) {
    if (argc > 0 && JS_IsNull(OOJS_ARGV[0]))
      OOJS_RETURN_VOID;  // OK, do nothing for null ship.

    cxx_OOJSReportBadArguments(context, "ShipGroup", "addShip", MIN(argc, 1),
                               OOJS_ARGV, std::nullopt, "ship");
    return OOJSNativeFailure(context);
  }

  // The groups are C++; a null one (the prototype's, or a ship's that has none)
  // answers what a message to nil did.
  OOShipGroup* thisGroup = cxxGroup;

  if (cxxGroup != nullptr && cxxGroup->containsShip(ship)) {
    // nothing to do...
    OOJS_RETURN_VOID;
  } else {
    ShipEntity* thisGroupLeader =
        (cxxGroup != nullptr) ? cxxGroup->leader() : nullptr;

    if ((thisGroupLeader != nullptr ? thisGroupLeader->escortGroup()
                                    : static_cast<OOShipGroup*>(nullptr)) ==
        thisGroup)  // escort group!
    {
      if (((cxxGroup != nullptr) ? cxxGroup->count() : 0) >
          1)  // already with some escorts
      {
        OOShipGroup* thatGroup =
            (ship != nullptr ? ship->group()
                             : static_cast<OOShipGroup*>(nullptr));
        OOShipGroup* cxxThatGroup = thatGroup;
        if (((cxxThatGroup != nullptr) ? cxxThatGroup->count() : 0) > 1 &&
            (((cxxThatGroup != nullptr) ? cxxThatGroup->leader() : nullptr) !=
                     nullptr
                 ? ((cxxThatGroup != nullptr) ? cxxThatGroup->leader()
                                              : nullptr)
                       ->escortGroup()
                 : static_cast<OOShipGroup*>(nullptr)) ==
                thatGroup)  // new escort already escorting!
        {
          cxx_OOJSReportWarningForCaller(
              context, "ShipGroup", "addShip",
              "Ship %s cannot be assigned to two escort groups, ignoring.",
              oo::EntityDescription(ship).c_str());
          OK = false;
        } else {
          OK = (thisGroupLeader != nullptr
                    ? thisGroupLeader->acceptAsEscort(ship)
                    : false);
        }
      } else  // [thisGroup count] == 1, default unescorted ship?
      {
        if ((thisGroupLeader != nullptr ? thisGroupLeader->escortGroup()
                                        : static_cast<OOShipGroup*>(nullptr)) ==
            (thisGroupLeader != nullptr ? thisGroupLeader->group()
                                        : static_cast<OOShipGroup*>(nullptr))) {
          // Default unescorted, unescortable, ship. Create new group and use
          // that instead.
          if (thisGroupLeader != nullptr)
            thisGroupLeader->setGroup(oo::leakRef(OOShipGroup::groupWithName(
                std::string("ship group"))));  // +1 kept, as [[OOShipGroup
                                               // alloc] cxx_initWithName:] was
          thisGroup =
              (thisGroupLeader != nullptr ? thisGroupLeader->group()
                                          : static_cast<OOShipGroup*>(nullptr));
          cxxGroup = thisGroup;
        } else {
          // Unescorted ship with custom group. See if it accepts escorts.
          OK = (thisGroupLeader != nullptr
                    ? thisGroupLeader->acceptAsEscort(ship)
                    : false);
        }
      }
    }
    if (OK) {
      OOJS_RETURN_BOOL(
          cxxGroup != nullptr &&
          cxxGroup->addShip(ship));  // if ship is there already, noop & YES
    } else
      OOJS_RETURN_BOOL(false);
  }

  OOJS_NATIVE_EXIT
}

// removeShip(ship : Ship)
static JSValue ShipGroupRemoveShip(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOShipGroup* cxxGroup = nullptr;
  ShipEntity* ship = nullptr;

  if (EXPECT_NOT(
          !OOJSGetCxxPrivate(context, OOJS_THIS, sShipGroupClassID, &cxxGroup)))
    return OOJSNativeFailure(context);

  if (argc > 0) ship = oo::ToShip(OOJSEntityFromJSValue(context, OOJS_ARGV[0]));
  if (ship == nullptr) {
    if (argc > 0 && JS_IsNull(OOJS_ARGV[0]))
      OOJS_RETURN_VOID;  // OK, do nothing for null ship.

    cxx_OOJSReportBadArguments(context, "ShipGroup", "removeShip", MIN(argc, 1),
                               OOJS_ARGV, std::nullopt, "ship");
    return OOJSNativeFailure(context);
  }

  // (null for the prototype: false, as a message to nil)
  OOJS_RETURN_BOOL(cxxGroup != nullptr && cxxGroup->removeShip(ship));

  OOJS_NATIVE_EXIT
}

// containsShip(ship : Ship) : Boolean
static JSValue ShipGroupContainsShip(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOShipGroup* cxxGroup = nullptr;
  ShipEntity* ship = nullptr;

  if (EXPECT_NOT(
          !OOJSGetCxxPrivate(context, OOJS_THIS, sShipGroupClassID, &cxxGroup)))
    return OOJSNativeFailure(context);

  if (argc > 0) ship = oo::ToShip(OOJSEntityFromJSValue(context, OOJS_ARGV[0]));
  if (ship == nullptr) {
    if (argc > 0 && JS_IsNull(OOJS_ARGV[0]))
      OOJS_RETURN_BOOL(false);  // OK, return false for null ship.

    cxx_OOJSReportBadArguments(context, "ShipGroup", "containsShip",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt, "ship");
    return OOJSNativeFailure(context);
  }

  // (null for the prototype: false, as a message to nil)
  OOJS_RETURN_BOOL(cxxGroup != nullptr && cxxGroup->containsShip(ship));

  OOJS_NATIVE_EXIT
}
