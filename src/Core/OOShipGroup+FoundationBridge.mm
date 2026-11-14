/*

OOShipGroup+FoundationBridge.mm

TRANSITIONAL: see OOShipGroup+FoundationBridge.h. Each method forwards to its cxx_ counterpart and
converts the result as the old method built it (immutable collections). -objectEnumerator hands
out the former OOShipGroupEnumerator, now a Foundation enumerator around an OOShipGroupCursor, so
it still raises if the group is mutated while it is in use.

*/

#import "OOFoundationBridge.h"
#import "OOShipGroup.h" // declares the bridge category at its end

@interface OOShipGroupEnumerator : NSEnumerator {
@private
    std::optional<OOShipGroupCursor> _cursor;
}

- (id)initWithShipGroup:(OOShipGroup*)group;

@end

@implementation OOShipGroup (OOFoundationBridge)

+ (instancetype)groupWithName:(NSString*)name
{
    return [self cxx_groupWithName:oo::OptionalString(name)];
}

+ (instancetype)groupWithName:(NSString*)name leader:(ShipEntity*)leader
{
    return [self cxx_groupWithName:oo::OptionalString(name) leader:leader];
}

- (NSEnumerator*)objectEnumerator
{
    return [[[OOShipGroupEnumerator alloc] initWithShipGroup:self] autorelease];
}

- (NSEnumerator*)mutationSafeEnumerator
{
    return [[self memberArray] objectEnumerator];
}

- (NSSet*)members
{
    return [NSSet setWithArray:[self memberArray]];
}

- (NSArray*)memberArray
{
    return oo::NSArrayFromObjects([self cxx_memberArray]);
}

- (NSSet*)membersExcludingLeader
{
    return [NSSet setWithArray:[self memberArrayExcludingLeader]];
}

- (NSArray*)memberArrayExcludingLeader
{
    return oo::NSArrayFromObjects([self cxx_memberArrayExcludingLeader]);
}

@end

@implementation OOShipGroupEnumerator

- (id)initWithShipGroup:(OOShipGroup*)group
{
    assert(group != nil);

    self = [super init];
    if (self != nil) {
        _cursor.emplace(group);
    }

    return self;
}

- (void)dealloc
{
    _cursor.reset();

    [super dealloc];
}

- (id)nextObject
{
    return _cursor->next();
}

@end
