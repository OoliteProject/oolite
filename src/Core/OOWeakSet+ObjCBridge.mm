/*

OOWeakSet+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-cc8a): the Objective-C OOWeakSet facade over
cxx::OOWeakSet. Every method forwards to its C++ member: a result that was OOWeakSet * (a copy)
comes back through oo::ToObjC, an argument that was one (-isEqual:) goes through oo::ToCxx.
Deleted with OOWeakSet+ObjCBridge.h.

Written by Jens Ayton in 2012 for Oolite.
This code is hereby placed in the public domain.

*/

#import "OODescription.h"
#import "OOWeakSet.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOWeakSet (OOObjCBridgePrivate)

- (id)initWithCxxWeakSet:(cxx::OOWeakSet*)set;

@end

@implementation OOWeakSet

// Inside the @implementation for the private ivar.
OOWeakSet* oo::ToObjC(cxx::OOWeakSet* set)
{
    return Peers().peerFor(set, [set] { return [[OOWeakSet alloc] initWithCxxWeakSet:set]; });
}

cxx::OOWeakSet* oo::ToCxx(OOWeakSet* set)
{
    if (set == nil)
        return nullptr;
    return set->_cxxWeakSet.get();
}

// oo::ToObjC's: runs under the peer table's lock, so it only stores the set.
- (id)initWithCxxWeakSet:(cxx::OOWeakSet*)set
{
    self = [super init];
    if (self != nil)
        _cxxWeakSet = oo::Ref<cxx::OOWeakSet>(set);
    return self;
}

- (id)init
{
    return [self initWithCapacity:0];
}

// A set made from Objective-C: its facade is this object, recorded as its peer at once.
- (id)initWithCapacity:(NSUInteger)capacity
{
    _cxxWeakSet = cxx::OOWeakSet::setWithCapacity(capacity);
    @autoreleasepool {
        Peers().peerFor(_cxxWeakSet.get(), [self] { return [self retain]; });
    }
    return [super init];
}

+ (instancetype)set
{
    return oo::ToObjC(cxx::OOWeakSet::set());
}
+ (instancetype)setWithCapacity:(NSUInteger)capacity
{
    return oo::ToObjC(cxx::OOWeakSet::setWithCapacity(capacity));
}

- (void)dealloc
{
    Peers().forget(_cxxWeakSet.get());
    [super dealloc];
}

- (std::optional<std::string>)cxx_description
{
    return _cxxWeakSet->description();
}

// MARK: Protocol conformance

- (id)copyWithZone:(OOZone*)zone
{
    return [oo::ToObjC(_cxxWeakSet->copyWithZone(zone)) retain];
}
- (id)mutableCopyWithZone:(OOZone*)zone
{
    return [oo::ToObjC(_cxxWeakSet->copyWithZone(zone)) retain];
}

- (BOOL)isEqual:(id)other
{
    if (![other isKindOfClass:[OOWeakSet class]])
        return NO;
    return _cxxWeakSet->isEqual(oo::ToCxx(static_cast<OOWeakSet*>(other)));
}

// MARK: Meat and potatoes

- (NSUInteger)count
{
    return _cxxWeakSet->count();
}
- (BOOL)containsObject:(id<OOWeakReferenceSupport>)object
{
    return _cxxWeakSet->containsObject(object);
}
- (std::vector<oo::ObjCRef<id>>)cxx_objectEnumerator
{
    return _cxxWeakSet->objectEnumerator();
}
- (void)addObject:(id<OOWeakReferenceSupport>)object
{
    _cxxWeakSet->addObject(object);
}
- (void)removeObject:(id<OOWeakReferenceSupport>)object
{
    _cxxWeakSet->removeObject(object);
}
- (void)makeObjectsPerformSelector:(SEL)selector
{
    _cxxWeakSet->makeObjectsPerformSelector(selector);
}

- (void)makeObjectsPerformSelector:(SEL)selector withObject:(id)argument
{
    _cxxWeakSet->makeObjectsPerformSelector(selector, argument);
}

- (std::vector<oo::ObjCRef<id>>)cxx_allObjects
{
    return _cxxWeakSet->allObjects();
}
- (void)removeAllObjects
{
    _cxxWeakSet->removeAllObjects();
}

@end
