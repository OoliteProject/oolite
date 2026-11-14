/*	test_OOWeakSet.mm
	Unit tests for cxx::OOWeakSet (src/Core/OOWeakSet.h) and its Objective-C facade
	(OOWeakSet+ObjCBridge.h): bead oo-cc8a, a Phase 3 conversion in the OOColor house style
	(proposed ADR-0056).

	Pins what the set did before the conversion, through the Objective-C API its callers
	(ShipEntity, StationEntity) use: nil is ignored; members are unique by identity and kept in
	insertion order; a member that is deallocated leaves the set silently; removing a non-member
	is fine; the snapshots and the perform-selector calls see the live members; enumerating adds;
	copies are new sets of the live members; -isEqual: compares membership; and the description.
	Those checks go through the facade the callers use; they were run first on the Objective-C
	class. After the conversion: the C++ set answers the same, and the facade's contract (one
	facade per set, whether made by +alloc/-init or crossing from C++; nil stays nil).
	Run: bash tools/check-core-tests.sh
*/

#import "OOWeakSet.h"
#import "OODescription.h"

#include "oo_test.hpp"
#include "oofnd/String.hpp"

#include <vector>


@interface TestMember: OOWeakRefObject
{
@public
	int		frobs;
	id		lastArgument;
	int		tag;
}
- (void) frob;
- (void) frobWith:(id)argument;
@end


@implementation TestMember

- (void) frob
{
	frobs++;
}


- (void) frobWith:(id)argument
{
	frobs++;
	lastArgument = argument;
}


- (std::optional<std::string>) cxx_shortDescriptionComponents
{
	return oo::str::format("member %d", tag);
}

@end


namespace {

TestMember *NewMember(int tag)
{
	TestMember *member = [[TestMember alloc] init];
	member->tag = tag;
	return member;
}


std::vector<id> Members(const std::vector<oo::ObjCRef<id>> &snapshot)
{
	std::vector<id> result;
	for (const oo::ObjCRef<id> &object : snapshot)  result.push_back(object.get());
	return result;
}

}	// namespace


OO_TEST(emptyAndNil)
{
	@autoreleasepool
	{
		OOWeakSet *set = [OOWeakSet set];
		OO_CHECK(set != nil);
		OO_CHECK_EQ([set count], 0u);
		[set addObject:nil];	// fails silently
		OO_CHECK_EQ([set count], 0u);
		OO_CHECK(![set containsObject:nil]);
		OO_CHECK([set cxx_allObjects].empty());
		OO_CHECK_EQ([[OOWeakSet setWithCapacity:10] count], 0u);
		OO_CHECK_EQ([[[[OOWeakSet alloc] initWithCapacity:3] autorelease] count], 0u);
	}
}


OO_TEST(uniqueByIdentityInInsertionOrder)
{
	TestMember *a = NewMember(1), *b = NewMember(2), *c = NewMember(3);
	@autoreleasepool
	{
		OOWeakSet *set = [[[OOWeakSet alloc] init] autorelease];
		[set addObject:b];
		[set addObject:a];
		[set addObject:b];
		[set addObject:c];
		OO_CHECK_EQ([set count], 3u);
		OO_CHECK([set containsObject:a] && [set containsObject:b] && [set containsObject:c]);
		OO_CHECK(Members([set cxx_allObjects]) == std::vector<id>({ b, a, c }));
		OO_CHECK(Members([set cxx_objectEnumerator]) == std::vector<id>({ b, a, c }));
		OO_CHECK_EQ([a retainCount], 1u);	// weakly held

		[set removeObject:a];
		[set removeObject:a];	// not a member: no complaint
		OO_CHECK_EQ([set count], 2u);
		OO_CHECK(![set containsObject:a]);
		OO_CHECK(Members([set cxx_allObjects]) == std::vector<id>({ b, c }));

		[set removeAllObjects];
		OO_CHECK_EQ([set count], 0u);
		OO_CHECK(![set containsObject:b]);
	}
	[a release];
	[b release];
	[c release];
}


OO_TEST(aDeallocatedMemberLeavesSilently)
{
	TestMember *a = NewMember(1), *b = NewMember(2);
	@autoreleasepool
	{
		OOWeakSet *set = [OOWeakSet set];
		[set addObject:a];
		[set addObject:b];
		OO_CHECK_EQ([set count], 2u);
		[a release];
		OO_CHECK_EQ([set count], 1u);
		OO_CHECK(Members([set cxx_allObjects]) == std::vector<id>({ b }));
		OO_CHECK([set containsObject:b]);
	}
	[b release];
}


OO_TEST(makeObjectsPerformSelector)
{
	TestMember *a = NewMember(1), *b = NewMember(2);
	id argument = [[OOObject alloc] init];
	@autoreleasepool
	{
		OOWeakSet *set = [OOWeakSet set];
		[set addObject:a];
		[set addObject:b];
		[set makeObjectsPerformSelector:@selector(frob)];
		OO_CHECK(a->frobs == 1 && b->frobs == 1);
		[set makeObjectsPerformSelector:@selector(frobWith:) withObject:argument];
		OO_CHECK(a->frobs == 2 && b->frobs == 2);
		OO_CHECK(a->lastArgument == argument && b->lastArgument == argument);
	}
	[a release];
	[b release];
	[argument release];
}


OO_TEST(copiesAndEquality)
{
	TestMember *a = NewMember(1), *b = NewMember(2), *c = NewMember(3);
	@autoreleasepool
	{
		OOWeakSet *set = [OOWeakSet set];
		[set addObject:a];
		[set addObject:b];
		OOWeakSet *copy = [[set copy] autorelease];
		OOWeakSet *mutableCopy = [[set mutableCopy] autorelease];
		OO_CHECK(copy != set && mutableCopy != set && copy != mutableCopy);	// new sets
		OO_CHECK(Members([copy cxx_allObjects]) == std::vector<id>({ a, b }));
		OO_CHECK([copy isEqual:set] && [set isEqual:copy] && [mutableCopy isEqual:set]);

		[copy addObject:c];	// independent of the original
		OO_CHECK_EQ([set count], 2u);
		OO_CHECK(![copy isEqual:set]);

		OOWeakSet *other = [OOWeakSet set];
		[other addObject:b];
		[other addObject:a];	// same members, another order
		OO_CHECK([other isEqual:set]);
		[other removeObject:a];
		[other addObject:c];	// same count, another member
		OO_CHECK(![other isEqual:set]);
		OO_CHECK(![set isEqual:[[[OOObject alloc] init] autorelease]]);
		OO_CHECK(![set isEqual:nil]);
	}
	[a release];
	[b release];
	[c release];
}


OO_TEST(description)
{
	TestMember *a = NewMember(1), *b = NewMember(2);
	@autoreleasepool
	{
		OOWeakSet *set = [OOWeakSet set];
		const std::string prefix = "<OOWeakSet " + oo::str::pointerDescription(set) + ">{";
		OO_CHECK_EQ(oo::DescriptionOf(set), prefix + "}");
		[set addObject:a];
		[set addObject:b];
		OO_CHECK_EQ(oo::DescriptionOf(set), prefix + oo::ShortDescriptionOf(a) + ", " + oo::ShortDescriptionOf(b) + "}");
	}
	[a release];
	[b release];
}


OO_TEST(theCxxSetAnswersTheSame)
{
	TestMember *a = NewMember(1), *b = NewMember(2);
	@autoreleasepool
	{
		oo::Ref<cxx::OOWeakSet> set = cxx::OOWeakSet::set();
		set->addObject(nil);
		set->addObject(b);
		set->addObject(a);
		set->addObject(b);
		OO_CHECK_EQ(set->count(), 2u);
		OO_CHECK(set->containsObject(a) && set->containsObject(b));
		OO_CHECK(Members(set->allObjects()) == std::vector<id>({ b, a }));
		OO_CHECK(Members(set->objectEnumerator()) == std::vector<id>({ b, a }));
		set->makeObjectsPerformSelector(@selector(frob));
		OO_CHECK(a->frobs == 1 && b->frobs == 1);

		oo::Ref<cxx::OOWeakSet> copy = set->copyWithZone(nullptr);
		OO_CHECK(copy != set && copy->isEqual(set.get()) && set->isEqual(copy.get()));
		OO_CHECK(!set->isEqual(nullptr));
		OO_CHECK(set->description() == [oo::ToObjC(set) cxx_description]);

		set->removeObject(b);
		OO_CHECK(Members(set->allObjects()) == std::vector<id>({ a }));
		OO_CHECK(!copy->isEqual(set.get()));
		set->removeAllObjects();
		OO_CHECK_EQ(set->count(), 0u);
		OO_CHECK_EQ(copy->count(), 2u);
	}
	[a release];
	OO_CHECK_EQ(cxx::OOWeakSet::setWithCapacity(4)->count(), 0u);
	[b release];
}


OO_TEST(facadeContract)
{
	OOWeakSet *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOWeakSet *>(nullptr)) == nil);
	OO_CHECK_EQ([none count], 0u);

	@autoreleasepool
	{
		// Made by +alloc/-init: that object is the set's facade.
		OOWeakSet *made = [[[OOWeakSet alloc] init] autorelease];
		OO_CHECK(oo::ToCxx(made) != nullptr);
		OO_CHECK(oo::ToObjC(oo::ToCxx(made)) == made);
		OOWeakSet *factory = [OOWeakSet setWithCapacity:2];
		OO_CHECK(oo::ToObjC(oo::ToCxx(factory)) == factory);

		// A C++ set crosses to one facade, and back to itself.
		oo::Ref<cxx::OOWeakSet> cxxSet = cxx::OOWeakSet::set();
		OOWeakSet *facade = oo::ToObjC(cxxSet);
		OO_CHECK(facade != nil && facade == oo::ToObjC(cxxSet.get()));
		OO_CHECK(oo::ToCxx(facade) == cxxSet.get());
		OO_CHECK([OOWeakSet set] != [OOWeakSet set]);	// distinct sets, as before
	}
}


OO_TEST_MAIN()
