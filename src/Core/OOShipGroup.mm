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
#import "OOFoundationBridge.h"
#import "OOMaths.h"
#import "ShipEntity.h"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"
#include "oofnd/objc/OOException.h"

enum {
    kMinSize = 4,
    kMaxFreeSpace = 128
};

@interface OOShipGroup (Private)

- (BOOL)resizeTo:(NSUInteger)newCapacity;
- (void)cleanUp;

- (NSUInteger)updateCount;

@end

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
            , _updateCount([group updateCount])
        {
            Fill();
        }

        id operator*() const { return _buffer[_position]; }
        Iterator& operator++()
        {
            OOCAssert([_group updateCount] == _updateCount, "OOShipGroup was mutated while being enumerated.");
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
    // One batch of live members (defined in OOShipGroup's @implementation, for its ivars).
    static NSUInteger FillBatch(OOShipGroup* group, NSUInteger* ioIndex, id* buffer, NSUInteger length);

    OOShipGroup* _group;
};

@implementation OOShipGroup

- (id)init
{
    return [self initWithName:nil];
}

- (id)initWithName:(id)name
{
    if ((self = [super init])) {
        _capacity = kMinSize;
        _members = (OOWeakReference**)malloc(sizeof *_members * _capacity);
        if (_members == NULL) {
            [self release];
            return nil;
        }

        [self setName:name];
    }

    return self;
}

+ (instancetype)cxx_groupWithName:(const std::optional<std::string>&)name
{
    return [[[self alloc] initWithName:oo::NSStringOrNil(name)] autorelease];
}

+ (instancetype)cxx_groupWithName:(const std::optional<std::string>&)name leader:(ShipEntity*)leader
{
    OOShipGroup* result = [self cxx_groupWithName:name];
    [result setLeader:leader];
    return result;
}

- (void)dealloc
{
    NSUInteger i;

    for (i = 0; i < _count; i++) {
        [_members[i] release];
    }
    free(_members);
    _name.reset();

    [super dealloc];
}

- (id)descriptionComponents
{
    std::string desc = oo::str::format("%zu ships", _count);
    if (_name.has_value()) {
        desc = oo::str::format("\"%s\", %s", _name->c_str(), desc.c_str());
    }
    if ([self leader] != nil) {
        desc = oo::str::format("%s, leader: %s", desc.c_str(), oo::DescriptionOf([[self leader] shortDescription]).c_str());
    }
    return oo::NSStringFrom(desc);
}

- (id)name
{
    return oo::NSStringOrNil(_name);
}

- (void)setName:(id)name
{
    _updateCount++;

    _name = oo::OptionalString(name);
}

- (ShipEntity*)leader
{
    ShipEntity* result = [_leader weakRefUnderlyingObject];

    // If reference is stale, delete weakref object.
    if (result == nil && _leader != nil) {
        [_leader release];
        _leader = nil;
    }

    return result;
}

- (void)setLeader:(ShipEntity*)leader
{
    _updateCount++;

    if (leader != [self leader]) {
        [_leader release];
        [self addShip:leader];
        _leader = [leader weakRetain];
    }
}

- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_memberArray
{
    std::vector<oo::ObjCRef<ShipEntity*>> result;

    if (_count == 0)
        return result;

    result.reserve(_count);
    for (ShipEntity* ship : OOShipGroupMembers(self)) {
        result.emplace_back(ship);
    }

    return result;
}

- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_memberArrayExcludingLeader
{
    std::vector<oo::ObjCRef<ShipEntity*>> result;
    ShipEntity* leader = nil;

    if (_count == 0)
        return result;
    leader = self.leader;

    result.reserve(_count);
    for (ShipEntity* ship : OOShipGroupMembers(self)) {
        if (ship != leader) {
            result.emplace_back(ship);
        }
    }

    return result;
}

- (BOOL)containsShip:(ShipEntity*)ship
{
    for (ShipEntity* containedShip : OOShipGroupMembers(self)) {
        if ([ship isEqual:containedShip]) {
            return YES;
        }
    }

    return NO;
}

- (BOOL)addShip:(ShipEntity*)ship
{
    _updateCount++;

    if ([self containsShip:ship])
        return YES; // it's in the group already, result!

    // Ensure there's space.
    if (_count == _capacity) {
        if (![self resizeTo:(_capacity > kMaxFreeSpace) ? (_capacity + kMaxFreeSpace) : (_capacity * 2)]) {
            if (![self resizeTo:_capacity + 1]) {
                // Out of memory?
                return NO;
            }
        }
    }

    _members[_count++] = [ship weakRetain];
    return YES;
}

- (BOOL)removeShip:(ShipEntity*)ship
{
    ShipEntity* containedShip = nil;
    NSUInteger index;
    BOOL foundIt = NO;

    _updateCount++;

    if (ship == [self leader])
        [self setLeader:nil];

    OOShipGroupCursor shipEnum(self);
    shipEnum.setPerformCleanup(NO);
    while ((containedShip = shipEnum.next())) {
        if ([ship isEqual:containedShip]) {
            index = shipEnum.index() - 1;
            _members[index] = _members[--_count];
            foundIt = YES;

            // Clean up
            [ship setGroup:nil];
            [ship setOwner:ship];
            [self cleanUp];
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

- (NSUInteger)count
{
    NSUInteger result = 0;

    if (_count != 0) {
        OOShipGroupCursor memberEnum(self);
        while (memberEnum.next() != nil)
            result++;
    }

    assert(result == _count);

    return result;
}

- (BOOL)isEmpty
{
    if (_count == 0)
        return YES;

    return OOShipGroupCursor(self).next() == nil;
}

- (BOOL)resizeTo:(NSUInteger)newCapacity
{
    OOWeakReference** temp = NULL;

    if (newCapacity < _count)
        return NO;

    temp = (OOWeakReference**)realloc(_members, newCapacity * sizeof *_members);
    if (temp == NULL)
        return NO;

    _members = temp;
    _capacity = newCapacity;
    return YES;
}

- (void)cleanUp
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
        [self resizeTo:newCapacity];
}

- (NSUInteger)updateCount
{
    return _updateCount;
}

ShipEntity* OOShipGroupCursor::next()
{
    // The work is done here, in OOShipGroup's @implementation, so that we can have access to both OOShipGroup's and OOShipGroupCursor's ivars.

    OOShipGroupCursor* enumerator = this;
    OOShipGroup* group = enumerator->_group.get();
    ShipEntity* result = nil;
    BOOL cleanupNeeded = NO;

    if (enumerator->_updateCount != group->_updateCount) {
        [OOException raise:OOGenericException format:"Collection <OOShipGroup: %p> was mutated while being enumerated.", (void*)group];
    }

    while (enumerator->_index < group->_count) {
        result = [group->_members[enumerator->_index] weakRefUnderlyingObject];
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
            [group cleanUp];
        }
    }

    return result;
}

// One batch of live members for OOShipGroupMembers: the body of the former
// -countByEnumeratingWithState:objects:count:, unchanged.
NSUInteger OOShipGroupMembers::FillBatch(OOShipGroup* group, NSUInteger* ioIndex, id* buffer, NSUInteger length)
{
    NSUInteger srcIndex, dstIndex = 0;
    ShipEntity* item = nil;
    BOOL cleanupNeeded = NO;

    srcIndex = *ioIndex;
    while (srcIndex < group->_count && dstIndex < length) {
        item = [group->_members[srcIndex] weakRefUnderlyingObject];
        if (item != nil) {
            buffer[dstIndex++] = item;
            srcIndex++;
        } else {
            group->_members[srcIndex] = group->_members[--group->_count];
            cleanupNeeded = YES;
        }
    }

    if (cleanupNeeded)
        [group cleanUp];

    *ioIndex = srcIndex;

    return dstIndex;
}

/*	This method exists purely to suppress Clang static analyzer warnings that
        this ivar is unused (but may be used by categories, which they are).
        FIXME: there must be a feature macro we can use to avoid actually building
        this into the app, but I can't find it in docs.
*/
- (BOOL)suppressClangStuff
{
    return !JS_IsObject(_jsSelf);
}

@end

OOShipGroupCursor::OOShipGroupCursor(OOShipGroup* group)
{
    assert(group != nil);

    _group = oo::ObjCRef<OOShipGroup*>(group);
    _considerCleanup = YES;
    _updateCount = [group updateCount];
}
