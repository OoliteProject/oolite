/*	test_objc_peer.mm
	Unit tests for oo::ObjCPeers (src/oofnd/objc/OOObjCPeer.h; proposed ADR-0056, bead oo-11m):
	one live Objective-C facade per C++ object, held weakly, forgotten when it dies.

	The facade here has the shape of a Phase 3 X+ObjCBridge.mm: an OOObject holding an oo::Ref to
	its C++ object, made only through the table, forgetting itself in -dealloc.

	Linked against libobjc2 alone, like the other test_*.mm (tools/check-oofnd-objc.sh).
*/

#include "oofnd/objc/OOObject.h"
#include "oofnd/objc/OOObjCPeer.h"
#include "oofnd/Ref.hpp"

#include "oo_test.hpp"

#include <objc/objc-arc.h>

#include <atomic>
#include <thread>
#include <vector>

namespace {

class Thing : public oo::RefCounted
{
public:
	static std::atomic<int> alive;
	Thing() { ++alive; }
	~Thing() override { --alive; }
};

std::atomic<int> Thing::alive{0};

int gFacadesMade = 0;
int gFacadesDeallocated = 0;

oo::ObjCPeers &Peers()
{
	static oo::ObjCPeers *peers = new oo::ObjCPeers;
	return *peers;
}

} // namespace


@interface OOPeerTestFacade : OOObject
{
@public
	oo::Ref<Thing>		_thing;
}
- (id) initWithThing:(Thing *)thing;
@end

@implementation OOPeerTestFacade

- (id) initWithThing:(Thing *)thing
{
	if ((self = [super init]))
	{
		_thing = oo::Ref<Thing>(thing);
		++gFacadesMade;
	}
	return self;
}


- (void) dealloc
{
	++gFacadesDeallocated;
	Peers().forget(_thing.get());
	[super dealloc];
}

@end


namespace {

OOPeerTestFacade *ToObjC(Thing *thing)
{
	return Peers().peerFor(thing, [thing] { return [[OOPeerTestFacade alloc] initWithThing:thing]; });
}

} // namespace


OO_TEST(nullHasNoPeer)
{
	OO_CHECK(ToObjC(nullptr) == nil);
	OO_CHECK_EQ(Peers().count(), 0u);
}


OO_TEST(sameObjectSamePeerWhileItLives)
{
	const int made = gFacadesMade;
	@autoreleasepool
	{
		oo::Ref<Thing> thing = oo::makeRef<Thing>();
		OOPeerTestFacade *first = ToObjC(thing.get());
		OOPeerTestFacade *second = ToObjC(thing.get());
		OO_CHECK(first != nil);
		OO_CHECK(first == second);
		OO_CHECK(first->_thing.get() == thing.get());
		OO_CHECK_EQ(gFacadesMade, made + 1);
		OO_CHECK_EQ(Peers().count(), 1u);

		oo::Ref<Thing> other = oo::makeRef<Thing>();
		OO_CHECK(ToObjC(other.get()) != first);
		OO_CHECK_EQ(Peers().count(), 2u);
	}
	// The pool released both facades: their entries are gone, and so are the C++ objects.
	OO_CHECK_EQ(Peers().count(), 0u);
	OO_CHECK_EQ(Thing::alive.load(), 0);
}


OO_TEST(facadeKeepsItsObjectAlive)
{
	OOPeerTestFacade *facade = nil;
	@autoreleasepool
	{
		oo::Ref<Thing> thing = oo::makeRef<Thing>();
		facade = [ToObjC(thing.get()) retain];
	}
	OO_CHECK_EQ(Thing::alive.load(), 1);	// only the facade holds it now
	OO_CHECK_EQ(Peers().count(), 1u);
	const int deallocated = gFacadesDeallocated;
	[facade release];
	OO_CHECK_EQ(gFacadesDeallocated, deallocated + 1);
	OO_CHECK_EQ(Thing::alive.load(), 0);
	OO_CHECK_EQ(Peers().count(), 0u);
}


OO_TEST(tableDoesNotKeepPeerAlive)
{
	oo::Ref<Thing> thing = oo::makeRef<Thing>();
	id firstAddress = nil;
	const int deallocated = gFacadesDeallocated;
	@autoreleasepool
	{
		firstAddress = ToObjC(thing.get());
	}
	OO_CHECK_EQ(gFacadesDeallocated, deallocated + 1);	// weak: the pool's release was the last
	OO_CHECK_EQ(Peers().count(), 0u);
	@autoreleasepool
	{
		OOPeerTestFacade *again = ToObjC(thing.get());
		OO_CHECK(again != nil);
		OO_CHECK(again->_thing.get() == thing.get());
		(void)firstAddress;
	}
	OO_CHECK_EQ(Peers().count(), 0u);
}


OO_TEST(forgetKeepsANewerLivePeer)
{
	// A peer made for the object while an older one is dying keeps its entry: forget() of the
	// old one only erases a dead entry.
	@autoreleasepool
	{
		oo::Ref<Thing> thing = oo::makeRef<Thing>();
		OOPeerTestFacade *peer = ToObjC(thing.get());
		Peers().forget(thing.get());	// as a dying older peer would
		OO_CHECK_EQ(Peers().count(), 1u);
		OO_CHECK(ToObjC(thing.get()) == peer);
	}
	OO_CHECK_EQ(Peers().count(), 0u);
}


OO_TEST(threadsAgreeOnOnePeer)
{
	oo::Ref<Thing> thing = oo::makeRef<Thing>();
	OOPeerTestFacade *keep = nil;
	@autoreleasepool
	{
		keep = [ToObjC(thing.get()) retain];
	}
	std::atomic<int> mismatches{0};
	std::vector<std::thread> threads;
	for (int t = 0; t < 4; t++)
	{
		threads.emplace_back([&]
		{
			for (int i = 0; i < 2000; i++)
			{
				@autoreleasepool
				{
					if (ToObjC(thing.get()) != keep)  ++mismatches;
					// A second object whose peer is made and dies on every iteration.
					oo::Ref<Thing> scratch = oo::makeRef<Thing>();
					(void)ToObjC(scratch.get());
				}
			}
		});
	}
	for (std::thread &thread : threads)  thread.join();
	OO_CHECK_EQ(mismatches.load(), 0);
	OO_CHECK_EQ(Peers().count(), 1u);
	[keep release];
	OO_CHECK_EQ(Peers().count(), 0u);
}


OO_TEST_MAIN()
