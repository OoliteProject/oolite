/*
OOShipGroup.h

A weak-referencing, mutable set of ships. Not thread safe.

A group is its own PList::Object payload
(oo::PListForeign) and its own JS glue (OOJSPrivateObject); ships hold it as
std::shared_ptr.


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

#pragma once

#include <quickjs.h>

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "OOEntityHold.h"  // memberArray()
#include "OOFoundation.h"
#include "OOJSPrivateObject.h"
#include "oofnd/Object.hpp"
#include "oofnd/PList.hpp"

class ShipEntity;
class Entity;  // the members are held as weak references to the ships' C++
               // parts

class OOShipGroupCursor;
class OOShipGroupMembers;  // OOShipGroup.cpp's range-for over the members

class OOShipGroup : public oo::PListForeign, public ::OOJSPrivateObject {
 public:
  // Null if the member array cannot be allocated (-initWithName: returned
  // nil).
  static std::shared_ptr<OOShipGroup> groupWithName(
      const std::optional<std::string>& name);
  static std::shared_ptr<OOShipGroup> groupWithName(
      const std::optional<std::string>& name, ::ShipEntity* leader);

  ~OOShipGroup() override;

  std::optional<std::string> name();  // nullopt: unnamed
  void setName(const std::optional<std::string>& name);

  ::ShipEntity* leader();
  void setLeader(::ShipEntity* leader);

  // The members at the time this is called, even if the group is mutated later.
  std::vector<oo::EntityHold> memberArray();                 // arbitrary order
  std::vector<oo::EntityHold> memberArrayExcludingLeader();  // arbitrary order

  bool containsShip(::ShipEntity* ship);
  bool addShip(::ShipEntity* ship);
  bool removeShip(::ShipEntity* ship);

  std::size_t count();  // NOTE: this is O(n).
  bool isEmpty();

  // What "%@" prints between the braces of <OOShipGroup 0x...>{...}
  // (OODescription.h).
  std::optional<std::string> descriptionComponents() const;

  // The JS glue (OOJSPrivateObject), defined in OOJSShipGroup.cpp: the
  // ShipGroup object, made on first use; forgetting it when it is finalized;
  // "[OOShipGroup <components>]".
  JSValue jsValueInContext(JSContext* context) override;  // owned
  void clearJSSelf(JSValueConst selfVal) override;
  std::optional<std::string> jsDescription() override;

  // oo::PListForeign: the class name, and "%@" as <OOShipGroup 0x...>{...}.
  std::string className() const override;
  std::string description() const override;

 private:
  // The cursor and the range-for read the members directly.
  friend class ::OOShipGroupCursor;
  friend class ::OOShipGroupMembers;

  // -initWithName:, which could fail.
  bool initWithName(const std::optional<std::string>& name);

  bool resizeTo(std::size_t newCapacity);
  void cleanUp();

  std::size_t updateCount();

  std::size_t _count = {}, _capacity = {};
  unsigned long _updateCount = {};
  // Weak references to the ships' C++ parts: each reads null exactly when the
  // object's reference did. _capacity slots, the first _count in use.
  std::vector<std::weak_ptr<Entity>> _members = {};
  std::weak_ptr<Entity> _leader = {};
  std::optional<std::string> _name = {};
  JSValue _jsSelf =
      JS_UNDEFINED;  // The JS ShipGroup object proxy for this group; not an
                     // object until created (test with JS_IsObject()).
};

/*	OOShipGroupCursor: steps through a group's live members in its internal
   order (the former OOShipGroupEnumerator). It raises if the group is mutated
   while it is in use, compacts dead references as it passes them, and unless
   told not to runs the group's clean-up at the end. It keeps the group alive.
*/
class OOShipGroupCursor {
 public:
  explicit OOShipGroupCursor(OOShipGroup* group);

  ::ShipEntity* next();  // nil at the end
  std::size_t index() const { return _index; }
  void setPerformCleanup(bool flag) { _considerCleanup = flag; }

  // Public so ShipGroupIterate() can peek at both these and OOShipGroup's
  // ivars. Naughty!
  std::shared_ptr<OOShipGroup> _group;
  std::size_t _index = 0, _updateCount = 0;
  bool _considerCleanup = true, _cleanupNeeded = false;
};

/*	A group carried through plist data as a PList::Object node: the group is
   the node's foreign object.
*/
inline oo::PList OOShipGroupObjectNode(
    OOShipGroup* group)  // null group -> null PList
{
  if (group == nullptr) return oo::PList();
  return oo::PList(oo::PList::Object(oo::share(group)));
}

inline OOShipGroup* OOShipGroupInObjectNode(
    const oo::PList& plist)  // null for any other node
{
  const oo::PList::Object* node = plist.getIf<oo::PList::Object>();
  return (node != nullptr) ? dynamic_cast<OOShipGroup*>(node->get()) : nullptr;
}
