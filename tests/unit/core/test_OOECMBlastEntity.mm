/*	test_OOECMBlastEntity.mm
	Unit tests for OOECMBlastEntity (src/Core/Entities/OOECMBlastEntity.h), the invisible entity
	that sends a ship's ECM pulses: bead oo-ryhi, a leaf of the Entities seam (proposed ADR-0056,
	amendment oo-bj8 item 12).

	The entity reads Universe, so the test links the whole game but main (['*']) and uses a Universe
	that was never initialised, subclassed to record -removeEntity: and the range searches the
	pulses make (it finds no ship, so no script event is sent). The firing ship is a plain entity
	(the blast messages it only as one: -position, -status, -weakRetain). The expectations were
	written against the Objective-C API and run on the unconverted class first (but for "no blast
	from nil", which crashed there in the Entity facade's -dealloc of an entity whose -init never
	ran, bead oo-s6ic6): no blast from nil; a blast is a no-draw effect at the ship's position; four
	pulses half a second apart, a quarter of the scanner range wider each, then it removes itself;
	a dead or deallocated ship ends it at once; -isECMBlast answers YES only for a blast. The
	blasts are made through the one helper below, the only line the conversion ported: the blast is
	now a C++ entity whose Objective-C object is the Entity facade oo::NewEntityFacade made.
	Run: bash tools/check-core-tests.sh
*/

#import "OOECMBlastEntity.h"
#import "Universe.h"

#include "oo_test.hpp"

#include <vector>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

@class PlayerEntity;
extern PlayerEntity *gOOPlayer;
extern Universe *gSharedUniverse;


// UNIVERSE: never initialised; records what is removed and what is searched for.
@interface TestUniverse: Universe
{
@public
	Entity					*_removed;
	std::vector<double>		*_ranges;
	Entity					*_searchedFrom;
}
@end


@implementation TestUniverse

- (BOOL) removeEntity:(Entity *)entity
{
	_removed = entity;
	return YES;
}


- (std::vector<oo::ObjCRef<Entity *>>) cxx_findEntitiesMatchingPredicate:(EntityFilterPredicate)predicate
										 parameter:(void *)parameter
										   inRange:(double)range
										  ofEntity:(Entity *)entity
{
	_ranges->push_back(range);
	_searchedFrom = entity;
	return {};
}

@end


namespace {

TestUniverse *sUniverse = nil;
std::vector<double> sRanges;


void SetUp()
{
	if (sUniverse == nil)  sUniverse = (TestUniverse *)class_createInstance([TestUniverse class], 0);	// never released
	sRanges.clear();
	sUniverse->_ranges = &sRanges;
	sUniverse->_removed = nil;
	sUniverse->_searchedFrom = nil;
	gSharedUniverse = sUniverse;
}


Entity *Ship()
{
	Entity *ship = [[[Entity alloc] init] autorelease];
	[ship setPosition:make_HPvector(10, 20, 30)];
	[ship setStatus:STATUS_IN_FLIGHT];
	return ship;
}


// --- How the test makes a blast (ported by the conversion), and nothing else ---------------------

Entity *Blast(Entity *ship)	{ return oo::NewEntityFacade(OOECMBlastEntity::initFromShip((ShipEntity *)ship)); }

// --------------------------------------------------------------------------------------------------

}	// namespace


OO_TEST(noShipNoBlast)
{
	@autoreleasepool
	{
		SetUp();
		OO_CHECK(Blast(nil) == nil);
	}
}


OO_TEST(blastAtTheShip)
{
	@autoreleasepool
	{
		SetUp();
		Entity *ship = Ship();
		Entity *blast = Blast(ship);
		OO_CHECK(blast != nil);
		OO_CHECK(HPvector_equal([blast position], make_HPvector(10, 20, 30)));
		OO_CHECK([blast status] == STATUS_EFFECT && [blast scanClass] == CLASS_NO_DRAW);
		OO_CHECK([blast owner] == nil);
		OO_CHECK([blast isECMBlast] && ![ship isECMBlast]);
	}
}


OO_TEST(fourPulsesThenGone)
{
	@autoreleasepool
	{
		SetUp();
		Entity *ship = Ship();
		Entity *blast = Blast(ship);

		[blast update:0.25];
		OO_CHECK(sRanges.empty() && sUniverse->_removed == nil);
		[blast update:0.25];
		OO_CHECK(sRanges.size() == 1 && sRanges[0] == SCANNER_MAX_RANGE * 0.25);
		OO_CHECK(sUniverse->_searchedFrom == blast);
		[blast update:0.5];
		[blast update:0.5];
		OO_CHECK(sRanges.size() == 3 && sRanges[1] == SCANNER_MAX_RANGE * 0.5 && sRanges[2] == SCANNER_MAX_RANGE * 0.75);
		OO_CHECK(sUniverse->_removed == nil);
		[blast update:0.5];
		OO_CHECK(sRanges.size() == 4 && sRanges[3] == SCANNER_MAX_RANGE);
		OO_CHECK(sUniverse->_removed == blast);
	}
}


OO_TEST(deadShipEndsIt)
{
	@autoreleasepool
	{
		SetUp();
		Entity *ship = Ship();
		Entity *blast = Blast(ship);
		[ship setStatus:STATUS_DEAD];
		[blast update:0.5];
		OO_CHECK(sRanges.empty() && sUniverse->_removed == blast);
	}

	Entity *blast = nil;
	@autoreleasepool
	{
		SetUp();
		Entity *ship = [[Entity alloc] init];
		blast = [Blast(ship) retain];
		[ship release];		// the blast holds it weakly
	}
	@autoreleasepool
	{
		[blast update:0.5];
		OO_CHECK(sRanges.empty() && sUniverse->_removed == blast);
		[blast release];
	}
}


OO_TEST_MAIN()
