/*	test_OOWaypointEntity.mm
	Unit tests for OOWaypointEntity (src/Core/Entities/OOWaypointEntity.h), the scripted beacon
	waypoints: bead oo-zsid, a leaf of the Entities seam with a facade (proposed ADR-0056,
	amendments oo-bj8 item 12 and oo-0mxi).

	The entity reads Universe and PLAYER, so the test links the whole game but main (['*']) and
	uses a Universe that was never initialised and a plain entity as PLAYER. The expectations were
	written against the Objective-C API and run on the unconverted class first: a waypoint reads its
	position, orientation, size and beacon code and label from its dictionary (defaults: the
	origin, the identity, 1000, "W" and "Waypoint"; an empty dictionary reads zeros and no beacon);
	a zero orientation is the identity and marks it unoriented; its size sets its draw distance and
	ignores a size that is not positive; it is a no-draw effect and a waypoint; the beacon code and
	label setters (an empty string is none; a code gives a blank label its text) and the case-
	insensitive comparison; its beacon icon is kept until the code changes; and its neighbours in
	the beacon list are weak references. The draw distance is read through the one helper below.
	The waypoints are made by the class method the universe sends, which the conversion kept on the
	facade: the last test pins that their object is a C++ entity whose Objective-C object is the
	OOWaypointEntity facade.
	Run: bash tools/check-core-tests.sh
*/

#import "OOWaypointEntity.h"
#import "Universe.h"

#include "oo_test.hpp"

#include <cmath>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

@class PlayerEntity;
extern PlayerEntity *gOOPlayer;
extern Universe *gSharedUniverse;


@interface TestPlayer: Entity
@end


@implementation TestPlayer

- (HPVector) viewpointPosition	{ return kZeroHPVector; }

@end


// UNIVERSE: never initialised.
@interface TestUniverse: Universe
@end


@implementation TestUniverse

- (OOTimeAbsolute) getTime	{ return 0; }

@end


namespace {

void SetUp()
{
	static Universe *universe = nil;
	if (universe == nil)  universe = (Universe *)class_createInstance([TestUniverse class], 0);	// never released
	gSharedUniverse = universe;
	static TestPlayer *player = nil;
	if (player == nil)  player = [[TestPlayer alloc] init];
	gOOPlayer = (PlayerEntity *)player;
}


// --- Ivars the test reads, and nothing else ---------------------------------------------------------

GLfloat NoDrawDistance(Entity *e)	{ return e->_cxxEntity->no_draw_distance; }

// --------------------------------------------------------------------------------------------------


oo::PList Dict(oo::PList::Dict entries)
{
	return oo::PList(std::move(entries));
}


oo::PList Vec(double x, double y, double z)
{
	return oo::PList(oo::PList::Array{ oo::PList(x), oo::PList(y), oo::PList(z) });
}


bool QuatIs(Quaternion q, float w, float x, float y, float z)
{
	return q.w == w && q.x == x && q.y == y && q.z == z;
}


OOWaypointEntity *Waypoint(const std::string &code)
{
	return [OOWaypointEntity waypointWithDictionary:Dict({ { "beaconCode", oo::PList(code) } })];
}

}	// namespace


OO_TEST(defaults)
{
	@autoreleasepool
	{
		SetUp();
		OOWaypointEntity *wp = [OOWaypointEntity waypointWithDictionary:Dict({ { "unused", oo::PList(1) } })];
		OO_CHECK(wp != nil && [wp isKindOfClass:[OOWaypointEntity class]]);
		OO_CHECK(HPvector_equal([wp position], kZeroHPVector));
		OO_CHECK(QuatIs([wp orientation], 1, 0, 0, 0) && [wp oriented]);
		OO_CHECK([wp size] == 1000.0);
		OO_CHECK(NoDrawDistance(wp) == (GLfloat)(1000.0 * 1000.0 * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR * 2));
		OO_CHECK([wp beaconCode] == std::optional<std::string>("W"));
		OO_CHECK([wp beaconLabel] == std::optional<std::string>("Waypoint"));
		OO_CHECK([wp isBeacon] && ![wp isJammingScanning]);
		OO_CHECK([wp status] == STATUS_EFFECT && [wp scanClass] == CLASS_NO_DRAW);
		OO_CHECK([wp isEffect] && [wp isWaypoint]);
	}
}


OO_TEST(dictionary)
{
	@autoreleasepool
	{
		SetUp();
		OOWaypointEntity *wp = [OOWaypointEntity waypointWithDictionary:Dict({
			{ "position", Vec(1, 2, 3) },
			{ "orientation", oo::PList(oo::PList::Array{ oo::PList(0.0), oo::PList(1.0), oo::PList(0.0), oo::PList(0.0) }) },
			{ "size", oo::PList(50.0) },
			{ "beaconCode", oo::PList("AB") },
			{ "beaconLabel", oo::PList("Somewhere") },
		})];
		OO_CHECK(HPvector_equal([wp position], make_HPvector(1, 2, 3)));
		OO_CHECK(QuatIs([wp orientation], 0, 1, 0, 0) && [wp oriented]);
		OO_CHECK([wp size] == 50.0);
		OO_CHECK([wp beaconCode] == std::optional<std::string>("AB"));
		OO_CHECK([wp beaconLabel] == std::optional<std::string>("Somewhere"));
	}
}


OO_TEST(emptyDictionary)
{
	@autoreleasepool
	{
		SetUp();
		// A nil dictionary read zero-filled values and nil strings: the zero orientation is unoriented.
		OOWaypointEntity *wp = [OOWaypointEntity waypointWithDictionary:oo::PList()];
		OO_CHECK(HPvector_equal([wp position], kZeroHPVector));
		OO_CHECK(QuatIs([wp orientation], 1, 0, 0, 0) && ![wp oriented]);
		OO_CHECK(![wp beaconCode].has_value() && ![wp beaconLabel].has_value() && ![wp isBeacon]);
	}
}


OO_TEST(orientation)
{
	@autoreleasepool
	{
		SetUp();
		OOWaypointEntity *wp = Waypoint("W");
		[wp setOrientation:kZeroQuaternion];
		OO_CHECK(![wp oriented] && QuatIs([wp orientation], 1, 0, 0, 0));
		Quaternion q = { 0, 0, 1, 0 };
		[wp setOrientation:q];
		OO_CHECK([wp oriented] && QuatIs([wp orientation], 0, 0, 1, 0));
	}
}


OO_TEST(size)
{
	@autoreleasepool
	{
		SetUp();
		OOWaypointEntity *wp = Waypoint("W");
		[wp setSize:10.0];
		OO_CHECK([wp size] == 10.0);
		OO_CHECK(NoDrawDistance(wp) == (GLfloat)(10.0 * 10.0 * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR * 2));
		[wp setSize:0.0];
		[wp setSize:-5.0];
		OO_CHECK([wp size] == 10.0);
	}
}


OO_TEST(beaconStrings)
{
	@autoreleasepool
	{
		SetUp();
		OOWaypointEntity *wp = [OOWaypointEntity waypointWithDictionary:Dict({ { "beaconCode", oo::PList("X") }, { "beaconLabel", oo::PList("Label") } })];
		[wp setBeaconCode:std::string("")];
		OO_CHECK(![wp beaconCode].has_value() && ![wp isBeacon]);
		OO_CHECK([wp beaconLabel] == std::optional<std::string>("Label"));

		[wp setBeaconLabel:std::string("")];
		OO_CHECK(![wp beaconLabel].has_value());
		[wp setBeaconCode:std::string("Q")];
		OO_CHECK([wp beaconCode] == std::optional<std::string>("Q") && [wp beaconLabel] == std::optional<std::string>("Q"));
		[wp setBeaconCode:std::string("R")];
		OO_CHECK([wp beaconLabel] == std::optional<std::string>("Q"));	// a label is kept
	}
}


OO_TEST(compareBeaconCodes)
{
	@autoreleasepool
	{
		SetUp();
		OO_CHECK([Waypoint("a") compareBeaconCodeWith:Waypoint("B")] == OOOrderedAscending);
		OO_CHECK([Waypoint("b") compareBeaconCodeWith:Waypoint("A")] == OOOrderedDescending);
		OO_CHECK([Waypoint("abc") compareBeaconCodeWith:Waypoint("ABC")] == OOOrderedSame);
	}
}


OO_TEST(beaconDrawable)
{
	@autoreleasepool
	{
		SetUp();
		OOWaypointEntity *wp = Waypoint("W");
		id<OOHUDBeaconIcon> icon = [wp beaconDrawable];
		OO_CHECK(icon != nil && [wp beaconDrawable] == icon);
		[(id)icon retain];
		[wp setBeaconCode:std::string("V")];
		OO_CHECK([wp beaconDrawable] != nil && [wp beaconDrawable] != icon);
		[(id)icon release];
	}
}


OO_TEST(neighbours)
{
	@autoreleasepool
	{
		SetUp();
		OOWaypointEntity *wp = Waypoint("W");
		OO_CHECK([wp prevBeacon] == nil && [wp nextBeacon] == nil);
		OOWaypointEntity *other = nil;
		@autoreleasepool
		{
			other = [Waypoint("V") retain];
		}
		[wp setPrevBeacon:other];
		[wp setNextBeacon:other];
		OO_CHECK([wp prevBeacon] == other && [wp nextBeacon] == other);
		[other release];		// weak: they read nil once it is gone
		OO_CHECK([wp prevBeacon] == nil && [wp nextBeacon] == nil);
	}
}


OO_TEST(facade)
{
	@autoreleasepool
	{
		SetUp();
		OOWaypointEntity *wp = Waypoint("W");
		OO_CHECK([wp class] == [OOWaypointEntity class]);
		// A C++ entity (amendment oo-0mxi), not an Objective-C entity's adapter.
		OO_CHECK(dynamic_cast<cxx::OOWaypointEntity *>(oo::ToCxx(wp)) != nullptr);
		OO_CHECK(oo::AsObjCEntity(oo::ToCxx(wp)) == nullptr);
		OO_CHECK(oo::ToObjC(oo::ToCxx(wp)) == wp);
	}
}


OO_TEST_MAIN()
