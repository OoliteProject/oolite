/*
OOShipGroup.m

IMPLEMENTATION NOTE:
This is implemented as a dynamic array rather than a hash table for the
following reasons:
 *	Ship groups are generally quite small, not motivating a more complex
        implementation.
 *	The code ship groups replace was all array-based and not a significant
        bottleneck.
 *	Ship groups are compacted (i.e., dead weak references removed) as a side
        effect of iteration.
 *	Many uses of ship groups involve iterating over the whole group anyway.


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

#include "OOShipGroup.h"

#include "OOMaths.h"
#include "ShipEntity.h"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"
#include "oofnd/objc/OOException.h"

enum { kMinSize = 4, kMaxFreeSpace = 128 };

/*	OOShipGroupMembers: range-for over a group's live members, in _members
   order, replacing the for-in fast-enumeration conformance. It
   fetches batches of kBatchSize exactly as
   -countByEnumeratingWithState:objects:count: did under clang's for-in (whose
   buffer is 16 objects): dead references are compacted, and -cleanUp runs, at
   the same points, so a loop that breaks early leaves the group as it did
   before.

                for (ShipEntity *ship : OOShipGroupMembers(group)) { ... }

        The group must not be mutated during the loop (for-in raised; this
   asserts).
*/
class OOShipGroupMembers {
 public:
  enum { kBatchSize = 16 };

  explicit OOShipGroupMembers(OOShipGroup* group) : _group(group) {}

  struct End {};

  class Iterator {
   public:
    explicit Iterator(OOShipGroup* group)
        : _group(group), _updateCount(group->updateCount()) {
      Fill();
    }

    ::ShipEntity* operator*() const {
      return oo::ToShip(_buffer[_position].get());
    }  // the member's ship
    Iterator& operator++() {
      OOCAssert(_group->updateCount() == _updateCount,
                "OOShipGroup was mutated while being enumerated.");
      if (++_position == _batchCount) Fill();
      return *this;
    }
    bool operator!=(End) const { return _batchCount != 0; }

   private:
    void Fill() {
      _batchCount = FillBatch(_group, &_index, _buffer, kBatchSize);
      _position = 0;
    }

    OOShipGroup* _group;
    std::size_t _updateCount;
    std::size_t _index = 0, _batchCount = 0, _position = 0;
    oo::EntityHold _buffer[kBatchSize];  // held, as the autoreleased objects
                                         // were
  };

  Iterator begin() const { return Iterator(_group); }
  End end() const { return End(); }

 private:
  // One batch of live members (a friend of OOShipGroup, for its ivars).
  static std::size_t FillBatch(OOShipGroup* group, std::size_t* ioIndex,
                               oo::EntityHold* buffer, std::size_t length);

  OOShipGroup* _group;
};

bool OOShipGroup::initWithName(const std::optional<std::string>& name) {
  _capacity = kMinSize;
  _members.resize(_capacity);  // the malloc of _capacity weak references

  setName(name);

  return true;
}

oo::Ref<OOShipGroup> OOShipGroup::groupWithName(
    const std::optional<std::string>& name) {
  oo::Ref<OOShipGroup> result = oo::makeRef<OOShipGroup>();
  if (!result->initWithName(name)) return nullptr;
  return result;
}

oo::Ref<OOShipGroup> OOShipGroup::groupWithName(
    const std::optional<std::string>& name, ::ShipEntity* leader) {
  oo::Ref<OOShipGroup> result = groupWithName(name);
  if (result != nullptr) result->setLeader(leader);
  return result;
}

std::string OOShipGroup::className() const { return "OOShipGroup"; }

std::string OOShipGroup::description() const {
  std::string result = oo::str::format(
      "<OOShipGroup %s>", oo::str::pointerDescription(this).c_str());
  const std::optional<std::string> components = descriptionComponents();
  if (components.has_value()) result += "{" + *components + "}";
  return result;
}

OOShipGroup::~OOShipGroup() {
  // The members' and the leader's weak references go with the vector and the
  // member.
  _name.reset();
}

std::optional<std::string> OOShipGroup::descriptionComponents() const {
  // leader() drops a stale weak reference, so it is not const.
  OOShipGroup* mutableThis = const_cast<OOShipGroup*>(this);
  std::string desc = oo::str::format("%zu ships", _count);
  if (_name.has_value()) {
    desc = oo::str::format("\"%s\", %s", _name->c_str(), desc.c_str());
  }
  if (mutableThis->leader() != nullptr) {
    desc = oo::str::format(
        "%s, leader: %s", desc.c_str(),
        oo::EntityShortDescription(mutableThis->leader()).c_str());
  }
  return desc;
}

std::optional<std::string> OOShipGroup::name() { return _name; }

void OOShipGroup::setName(const std::optional<std::string>& name) {
  _updateCount++;

  _name = name;
}

::ShipEntity* OOShipGroup::leader() {
  ::ShipEntity* result = oo::ToShip(_leader.get());

  // If reference is stale, delete weakref object.
  if (result == nullptr) _leader.reset();

  return result;
}

void OOShipGroup::setLeader(::ShipEntity* leader) {
  _updateCount++;

  if (leader != this->leader()) {
    _leader.reset();
    addShip(leader);
    _leader = oo::WeakRef<Entity>(leader);  // empty for none
  }
}

std::vector<oo::EntityHold> OOShipGroup::memberArray() {
  std::vector<oo::EntityHold> result;

  if (_count == 0) return result;

  result.reserve(_count);
  for (::ShipEntity* ship : OOShipGroupMembers(this)) {
    result.emplace_back(ship);
  }

  return result;
}

std::vector<oo::EntityHold> OOShipGroup::memberArrayExcludingLeader() {
  std::vector<oo::EntityHold> result;
  ::ShipEntity* leader = nullptr;

  if (_count == 0) return result;
  leader = this->leader();

  result.reserve(_count);
  for (::ShipEntity* ship : OOShipGroupMembers(this)) {
    if (ship != leader) {
      result.emplace_back(ship);
    }
  }

  return result;
}

bool OOShipGroup::containsShip(::ShipEntity* ship) {
  for (::ShipEntity* containedShip : OOShipGroupMembers(this)) {
    if (ship != nullptr &&
        ship == containedShip)  // what -isEqual: of their objects answered
                                // (identity)
    {
      return true;
    }
  }

  return false;
}

bool OOShipGroup::addShip(::ShipEntity* ship) {
  _updateCount++;

  if (containsShip(ship)) return true;  // it's in the group already, result!

  // Ensure there's space.
  if (_count == _capacity) {
    if (!resizeTo((_capacity > kMaxFreeSpace) ? (_capacity + kMaxFreeSpace)
                                              : (_capacity * 2))) {
      if (!resizeTo(_capacity + 1)) {
        // Out of memory?
        return false;
      }
    }
  }

  _members[_count++] = oo::WeakRef<Entity>(ship);  // empty for none
  return true;
}

bool OOShipGroup::removeShip(::ShipEntity* ship) {
  ::ShipEntity* containedShip = nullptr;
  std::size_t index;
  bool foundIt = false;

  _updateCount++;

  if (ship == leader()) setLeader(nullptr);

  OOShipGroupCursor shipEnum(this);
  shipEnum.setPerformCleanup(false);
  while ((containedShip = shipEnum.next())) {
    if (ship != nullptr &&
        ship == containedShip)  // what -isEqual: of their objects answered
                                // (identity)
    {
      index = shipEnum.index() - 1;
      _members[index] = _members[--_count];
      foundIt = true;

      // Clean up
      if (ship != nullptr) ship->setGroup(nullptr);
      if (ship != nullptr)
        ship->ShipEntity::setOwner(ship);  // qualified: the final overrider, so
                                           // the group's test stands in for it
      cleanUp();
      break;
    }
  }
  return foundIt;
}

/* TODO post-1.78: profiling indicates this is a noticeable
 * contributor to ShipEntity::update time. Consider optimisation: may
 * be possible to return _count if invalidation of weakref and group
 * removal in ShipEntity::dealloc keeps the data consistent anyway -
 * CIM */

std::size_t OOShipGroup::count() {
  std::size_t result = 0;

  if (_count != 0) {
    OOShipGroupCursor memberEnum(this);
    while (memberEnum.next() != nullptr) result++;
  }

  assert(result == _count);

  return result;
}

bool OOShipGroup::isEmpty() {
  if (_count == 0) return true;

  return OOShipGroupCursor(this).next() == nullptr;
}

bool OOShipGroup::resizeTo(std::size_t newCapacity) {
  if (newCapacity < _count) return false;

  _members.resize(newCapacity);  // the realloc: the first _count kept
  _capacity = newCapacity;
  return true;
}

void OOShipGroup::cleanUp() {
  std::size_t newCapacity = _capacity;

  if (_count >= kMaxFreeSpace) {
    if (_capacity > _count + kMaxFreeSpace) {
      newCapacity =
          _count +
          1;  // +1 keeps us at powers of two + multiples of kMaxFreespace.
    }
  } else {
    if (_capacity > _count * 2) {
      newCapacity = OORoundUpToPowerOf2_NS(_count);
      if (newCapacity < kMinSize) newCapacity = kMinSize;
    }
  }

  if (newCapacity != _capacity) resizeTo(newCapacity);
}

std::size_t OOShipGroup::updateCount() { return _updateCount; }

::ShipEntity* OOShipGroupCursor::next() {
  // The cursor is a friend of OOShipGroup, so that we can have access to both
  // OOShipGroup's and OOShipGroupCursor's ivars.

  OOShipGroupCursor* enumerator = this;
  OOShipGroup* group = enumerator->_group.get();
  ::ShipEntity* result = nullptr;
  bool cleanupNeeded = false;

  if (enumerator->_updateCount != group->_updateCount) {
    OORaiseException(
        OOGenericException,
        "Collection <OOShipGroup: %p> was mutated while being enumerated.",
        (void*)group);
  }

  while (enumerator->_index < group->_count) {
    result = oo::ToShip(group->_members[enumerator->_index].get());
    if (result != nullptr) {
      enumerator->_index++;
      break;
    }

    // If we got here, the group contains a stale reference to a dead ship.
    group->_members[enumerator->_index] = group->_members[--group->_count];
    cleanupNeeded = true;
  }

  // Clean-up handling. Only perform actual clean-up at end of iteration.
  if (enumerator->_considerCleanup) {
    enumerator->_cleanupNeeded = enumerator->_cleanupNeeded && cleanupNeeded;
    if (enumerator->_cleanupNeeded && result == nullptr) {
      group->cleanUp();
    }
  }

  return result;
}

// One batch of live members for OOShipGroupMembers: the body of the former
// -countByEnumeratingWithState:objects:count:, unchanged.
std::size_t OOShipGroupMembers::FillBatch(OOShipGroup* group,
                                          std::size_t* ioIndex,
                                          oo::EntityHold* buffer,
                                          std::size_t length) {
  std::size_t srcIndex, dstIndex = 0;
  ::ShipEntity* item = nullptr;
  bool cleanupNeeded = false;

  srcIndex = *ioIndex;
  while (srcIndex < group->_count && dstIndex < length) {
    item = oo::ToShip(group->_members[srcIndex].get());
    if (item != nullptr) {
      buffer[dstIndex++] =
          oo::EntityHold(item);  // its object retained (and autoreleased by
                                 // oo::ToObjC), as before
      srcIndex++;
    } else {
      group->_members[srcIndex] = group->_members[--group->_count];
      cleanupNeeded = true;
    }
  }

  if (cleanupNeeded) group->cleanUp();

  *ioIndex = srcIndex;

  return dstIndex;
}

OOShipGroupCursor::OOShipGroupCursor(OOShipGroup* group) {
  assert(group != nullptr);

  _group = oo::Ref<OOShipGroup>(group);
  _considerCleanup = true;
  _updateCount = group->updateCount();
}
