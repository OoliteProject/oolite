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

#import "OOShipGroup.h"
#import "OOMaths.h"
#import "ShipEntity.h"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"
#include "oofnd/objc/OOException.h"

enum {
    kMinSize = 4,
    kMaxFreeSpace = 128
};

/*	OOShipGroupMembers: range-for over a group's live members, in _members order, replacing the
        for-in fast-enumeration conformance (bead oo-3rb.20). It fetches batches of kBatchSize exactly
        as -countByEnumeratingWithState:objects:count: did under clang's for-in (whose buffer is 16
        objects): dead references are compacted, and -cleanUp runs, at the same points, so a loop that
        breaks early leaves the group as it did before.

                for (ShipEntity *ship : OOShipGroupMembers(group)) { ... }

        The group must not be mutated during the loop (for-in raised; this asserts).
*/
class OOShipGroupMembers {
public:
    enum { kBatchSize = 16 };

    explicit OOShipGroupMembers(OOShipGroup* group)
        : _group(group)
    {
    }

    struct End { };

    class Iterator {
    public:
        explicit Iterator(OOShipGroup* group)
            : _group(group)
            , _updateCount(group->updateCount())
        {
            Fill();
        }

        ::ShipEntity* operator*() const { return oo::ToShip(_buffer[_position]); } // the member's ship (the object until bead oo-9ht.144)
        Iterator& operator++()
        {
            OOCAssert(_group->updateCount() == _updateCount, "OOShipGroup was mutated while being enumerated.");
            if (++_position == _batchCount)
                Fill();
            return *this;
        }
        bool operator!=(End) const { return _batchCount != 0; }

    private:
        void Fill()
        {
            _batchCount = FillBatch(_group, &_index, _buffer, kBatchSize);
            _position = 0;
        }

        OOShipGroup* _group;
        NSUInteger _updateCount;
        NSUInteger _index = 0, _batchCount = 0, _position = 0;
        id _buffer[kBatchSize];
    };

    Iterator begin() const { return Iterator(_group); }
    End end() const { return End(); }

private:
    // One batch of live members (a friend of OOShipGroup, for its ivars).
    static NSUInteger FillBatch(OOShipGroup* group, NSUInteger* ioIndex, id* buffer, NSUInteger length);

    OOShipGroup* _group;
};

bool OOShipGroup::initWithName(const std::optional<std::string>& name)
{
    _capacity = kMinSize;
    _members = (OOWeakReference**)malloc(sizeof *_members * _capacity);
    if (_members == NULL) {
        return false;
    }

    setName(name);

    return true;
}

oo::Ref<OOShipGroup> OOShipGroup::groupWithName(const std::optional<std::string>& name)
{
    oo::Ref<OOShipGroup> result = oo::makeRef<OOShipGroup>();
    if (!result->initWithName(name))
        return nullptr;
    return result;
}

oo::Ref<OOShipGroup> OOShipGroup::groupWithName(const std::optional<std::string>& name, ::ShipEntity* leader)
{
    oo::Ref<OOShipGroup> result = groupWithName(name);
    if (result != nullptr)
        result->setLeader(leader);
    return result;
}

std::string OOShipGroup::className() const
{
    return "OOShipGroup";
}

std::string OOShipGroup::description() const
{
    std::string result = oo::str::format("<OOShipGroup %s>", oo::str::pointerDescription(this).c_str());
    const std::optional<std::string> components = descriptionComponents();
    if (components.has_value())
        result += "{" + *components + "}";
    return result;
}

OOShipGroup::~OOShipGroup()
{
    NSUInteger i;

    for (i = 0; i < _count; i++) {
        [_members[i] release];
    }
    free(_members);
    [_leader release]; // setLeader() weak-retained it (bead oo-9ht.24)
    _name.reset();
}

std::optional<std::string> OOShipGroup::descriptionComponents() const
{
    // leader() drops a stale weak reference, so it is not const (amendment oo-bhb9 item 5).
    OOShipGroup* mutableThis = const_cast<OOShipGroup*>(this);
    std::string desc = oo::str::format("%zu ships", _count);
    if (_name.has_value()) {
        desc = oo::str::format("\"%s\", %s", _name->c_str(), desc.c_str());
    }
    if (mutableThis->leader() != nil) {
        desc = oo::str::format("%s, leader: %s", desc.c_str(), oo::ShortDescriptionOf(oo::ToObjC(mutableThis->leader())).c_str());
    }
    return desc;
}

std::optional<std::string> OOShipGroup::name()
{
    return _name;
}

void OOShipGroup::setName(const std::optional<std::string>& name)
{
    _updateCount++;

    _name = name;
}

::ShipEntity* OOShipGroup::leader()
{
    ::ShipEntity* result = oo::ToShip([_leader weakRefUnderlyingObject]);

    // If reference is stale, delete weakref object.
    if (result == nil && _leader != nil) {
        [_leader release];
        _leader = nil;
    }

    return result;
}

void OOShipGroup::setLeader(::ShipEntity* leader)
{
    _updateCount++;

    if (leader != this->leader()) {
        [_leader release];
        addShip(leader);
        _leader = (leader != nullptr ? [oo::ToObjC(leader) weakRetain] : id { });
    }
}

std::vector<oo::ObjCRef<::Entity*>> OOShipGroup::memberArray()
{
    std::vector<oo::ObjCRef<::Entity*>> result;

    if (_count == 0)
        return result;

    result.reserve(_count);
    for (::ShipEntity* ship : OOShipGroupMembers(this)) {
        result.emplace_back(oo::ToObjC(ship));
    }

    return result;
}

std::vector<oo::ObjCRef<::Entity*>> OOShipGroup::memberArrayExcludingLeader()
{
    std::vector<oo::ObjCRef<::Entity*>> result;
    ::ShipEntity* leader = nil;

    if (_count == 0)
        return result;
    leader = this->leader();

    result.reserve(_count);
    for (::ShipEntity* ship : OOShipGroupMembers(this)) {
        if (ship != leader) {
            result.emplace_back(oo::ToObjC(ship));
        }
    }

    return result;
}

bool OOShipGroup::containsShip(::ShipEntity* ship)
{
    for (::ShipEntity* containedShip : OOShipGroupMembers(this)) {
        if ((ship != nullptr ? [oo::ToObjC(ship) isEqual:oo::ToObjC(containedShip)] : false)) {
            return true;
        }
    }

    return false;
}

bool OOShipGroup::addShip(::ShipEntity* ship)
{
    _updateCount++;

    if (containsShip(ship))
        return true; // it's in the group already, result!

    // Ensure there's space.
    if (_count == _capacity) {
        if (!resizeTo((_capacity > kMaxFreeSpace) ? (_capacity + kMaxFreeSpace) : (_capacity * 2))) {
            if (!resizeTo(_capacity + 1)) {
                // Out of memory?
                return false;
            }
        }
    }

    _members[_count++] = (ship != nullptr ? [oo::ToObjC(ship) weakRetain] : id { });
    return true;
}

bool OOShipGroup::removeShip(::ShipEntity* ship)
{
    ::ShipEntity* containedShip = nil;
    NSUInteger index;
    bool foundIt = false;

    _updateCount++;

    if (ship == leader())
        setLeader(nil);

    OOShipGroupCursor shipEnum(this);
    shipEnum.setPerformCleanup(NO);
    while ((containedShip = shipEnum.next())) {
        if ((ship != nullptr ? [oo::ToObjC(ship) isEqual:oo::ToObjC(containedShip)] : false)) {
            index = shipEnum.index() - 1;
            _members[index] = _members[--_count];
            foundIt = true;

            // Clean up
            if (ship != nullptr)
                ship->setGroup(nullptr);
            if (ship != nullptr)
                ship->ShipEntity::setOwner(ship); // qualified: the final overrider, so the group's test stands in for it
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

NSUInteger OOShipGroup::count()
{
    NSUInteger result = 0;

    if (_count != 0) {
        OOShipGroupCursor memberEnum(this);
        while (memberEnum.next() != nil)
            result++;
    }

    assert(result == _count);

    return result;
}

bool OOShipGroup::isEmpty()
{
    if (_count == 0)
        return true;

    return OOShipGroupCursor(this).next() == nil;
}

bool OOShipGroup::resizeTo(NSUInteger newCapacity)
{
    OOWeakReference** temp = NULL;

    if (newCapacity < _count)
        return false;

    temp = (OOWeakReference**)realloc(_members, newCapacity * sizeof *_members);
    if (temp == NULL)
        return false;

    _members = temp;
    _capacity = newCapacity;
    return true;
}

void OOShipGroup::cleanUp()
{
    NSUInteger newCapacity = _capacity;

    if (_count >= kMaxFreeSpace) {
        if (_capacity > _count + kMaxFreeSpace) {
            newCapacity = _count + 1; // +1 keeps us at powers of two + multiples of kMaxFreespace.
        }
    } else {
        if (_capacity > _count * 2) {
            newCapacity = OORoundUpToPowerOf2_NS(_count);
            if (newCapacity < kMinSize)
                newCapacity = kMinSize;
        }
    }

    if (newCapacity != _capacity)
        resizeTo(newCapacity);
}

NSUInteger OOShipGroup::updateCount()
{
    return _updateCount;
}

::ShipEntity* OOShipGroupCursor::next()
{
    // The cursor is a friend of OOShipGroup, so that we can have access to both OOShipGroup's and OOShipGroupCursor's ivars.

    OOShipGroupCursor* enumerator = this;
    OOShipGroup* group = enumerator->_group.get();
    ::ShipEntity* result = nil;
    BOOL cleanupNeeded = NO;

    if (enumerator->_updateCount != group->_updateCount) {
        [OOException raise:OOGenericException format:"Collection <OOShipGroup: %p> was mutated while being enumerated.", (void*)group];
    }

    while (enumerator->_index < group->_count) {
        result = oo::ToShip([group->_members[enumerator->_index] weakRefUnderlyingObject]);
        if (result != nil) {
            enumerator->_index++;
            break;
        }

        // If we got here, the group contains a stale reference to a dead ship.
        group->_members[enumerator->_index] = group->_members[--group->_count];
        cleanupNeeded = YES;
    }

    // Clean-up handling. Only perform actual clean-up at end of iteration.
    if (enumerator->_considerCleanup) {
        enumerator->_cleanupNeeded = enumerator->_cleanupNeeded && cleanupNeeded;
        if (enumerator->_cleanupNeeded && result == nil) {
            group->cleanUp();
        }
    }

    return result;
}

// One batch of live members for OOShipGroupMembers: the body of the former
// -countByEnumeratingWithState:objects:count:, unchanged.
NSUInteger OOShipGroupMembers::FillBatch(OOShipGroup* group, NSUInteger* ioIndex, id* buffer, NSUInteger length)
{
    NSUInteger srcIndex, dstIndex = 0;
    ::ShipEntity* item = nil;
    BOOL cleanupNeeded = NO;

    srcIndex = *ioIndex;
    while (srcIndex < group->_count && dstIndex < length) {
        item = oo::ToShip([group->_members[srcIndex] weakRefUnderlyingObject]);
        if (item != nil) {
            buffer[dstIndex++] = oo::ToObjC(item);
            srcIndex++;
        } else {
            group->_members[srcIndex] = group->_members[--group->_count];
            cleanupNeeded = YES;
        }
    }

    if (cleanupNeeded)
        group->cleanUp();

    *ioIndex = srcIndex;

    return dstIndex;
}

OOShipGroupCursor::OOShipGroupCursor(OOShipGroup* group)
{
    assert(group != nullptr);

    _group = oo::Ref<OOShipGroup>(group);
    _considerCleanup = YES;
    _updateCount = group->updateCount();
}
