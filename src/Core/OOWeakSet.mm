/*

OOWeakSet.m

Written by Jens Ayton in 2012 for Oolite.
This code is hereby placed in the public domain.

*/

#import "OOWeakSet.h"

#import "OOFoundationBridge.h"

#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"

namespace {

// The objects behind the live references, in insertion order.
std::vector<oo::ObjCRef<id>> LiveObjects(const std::vector<oo::ObjCRef<OOWeakReference*>>& references)
{
    std::vector<oo::ObjCRef<id>> result;
    result.reserve(references.size());
    for (const auto& weakRef : references) {
        id object = [weakRef.get() weakRefUnderlyingObject];
        if (object != nil)
            result.emplace_back(object);
    }
    return result;
}

} // namespace

@interface OOWeakSet (OOPrivate)

- (void)compact; // Remove any zeroed entries.

@end

@implementation OOWeakSet

- (id)init
{
    return [self initWithCapacity:0];
}

- (id)initWithCapacity:(NSUInteger)capacity
{
    if ((self = [super init])) {
        _objects.reserve(capacity);
    }
    return self;
}

+ (instancetype)set
{
    return [[[self alloc] init] autorelease];
}

+ (instancetype)setWithCapacity:(NSUInteger)capacity
{
    return [[[self alloc] initWithCapacity:capacity] autorelease];
}

- (void)dealloc
{
    _objects.clear();

    [super dealloc];
}

- (id)description
{
    std::string result = oo::str::format("<%s %s>{", oo::DescriptionOf([self class]).c_str(), oo::str::pointerDescription(self).c_str());
    BOOL first = YES;
    for (const oo::ObjCRef<id>& object : LiveObjects(_objects)) {
        if (!first)
            result += ", ";
        else
            first = NO;

        if ([object.get() respondsToSelector:@selector(shortDescription)])
            result += oo::DescriptionOf([object.get() shortDescription]);
        else
            result += oo::DescriptionOf(object.get());
    }

    result += "}";
    return oo::NSStringFrom(result);
}

// MARK: Protocol conformance

- (id)copyWithZone:(OOZone*)zone
{
    [self compact];
    OOWeakSet* result = [[OOWeakSet allocWithZone:zone] init];
    [result addObjectsByEnumerating:[self objectEnumerator]];
    return result;
}

- (id)mutableCopyWithZone:(OOZone*)zone
{
    return [self copyWithZone:zone];
}

- (BOOL)isEqual:(id)other
{
    if (![other isKindOfClass:[OOWeakSet class]])
        return NO;
    if ([self count] != [other count])
        return NO;

    BOOL result = YES;
    @autoreleasepool {
        id selfEnum = [self objectEnumerator];
        id object = nil;
        while ((object = [selfEnum nextObject])) {
            if (![other containsObject:object]) {
                result = NO;
                break;
            }
        }
    }

    return result;
}

// MARK: Meat and potatoes

- (NSUInteger)count
{
    [self compact];
    return _objects.size();
}

- (BOOL)containsObject:(id<OOWeakReferenceSupport>)object
{
    [self compact];
    // (a live object has one weak reference, so membership is identity, as the set's was)
    OOWeakReference* weakObj = [object weakRetain];
    BOOL result = std::find_if(_objects.begin(), _objects.end(), [weakObj](const auto& ref) { return ref.get() == weakObj; }) != _objects.end();
    [weakObj release];
    return result;
}

- (id)objectEnumerator
{
    return [oo::NSArrayFromObjects(LiveObjects(_objects)) objectEnumerator];
}

- (void)addObject:(id<OOWeakReferenceSupport>)object
{
    if (object == nil)
        return;
    OOAssert([object conformsToProtocol:@protocol(OOWeakReferenceSupport)], "Attempt to add object to OOWeakSet which does not conform to OOWeakReferenceSupport.");

    OOWeakReference* weakObj = [object weakRetain];
    if (std::find_if(_objects.begin(), _objects.end(), [weakObj](const auto& ref) { return ref.get() == weakObj; }) == _objects.end()) {
        _objects.emplace_back(weakObj); // (a set holds each once)
    }
    [weakObj release];
}

- (void)removeObject:(id<OOWeakReferenceSupport>)object
{
    OOWeakReference* weakObj = [object weakRetain];
    std::erase_if(_objects, [weakObj](const auto& ref) { return ref.get() == weakObj; });
    [weakObj release];
}

- (void)addObjectsByEnumerating:(id)enumerator
{
    id object = nil;
    [self compact];
    while ((object = [enumerator nextObject])) {
        [self addObject:object];
    }
}

- (void)makeObjectsPerformSelector:(SEL)selector
{
    // (over a copy of the references: a selector may change the set)
    const std::vector<oo::ObjCRef<OOWeakReference*>> references = _objects;
    for (const auto& weakRef : references) {
        [[weakRef.get() weakRefUnderlyingObject] performSelector:selector];
    }
}

- (void)makeObjectsPerformSelector:(SEL)selector withObject:(id)argument
{
    const std::vector<oo::ObjCRef<OOWeakReference*>> references = _objects;
    for (const auto& weakRef : references) {
        [[weakRef.get() weakRefUnderlyingObject] performSelector:selector withObject:argument];
    }
}

- (id)allObjects
{
    return oo::NSArrayFromObjects(LiveObjects(_objects));
}

- (void)removeAllObjects
{
    _objects.clear();
}

- (void)compact
{
    std::erase_if(_objects, [](const auto& weakRef) { return [weakRef.get() weakRefUnderlyingObject] == nil; });
}

@end
