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
	The waypoints are made as the universe makes them: by the C++ factory, handed to Objective-C
	with oo::NewEntityFacade, whose object is the root Entity's facade since bead oo-9ht.108
	deleted the class's facade (ADR-0056 amendment oo-9ht.106). The object still answers the
	beacon selectors (the root's category Entity (OOWaypointBeacon)), so the beacon checks send
	them as before; the class's own selectors are member calls; the last tests pin that the object
	is a C++ entity's, that only a waypoint's object (or a facade that implements them) answers the
	beacon selectors, and the JS answers.
	Run: bash tools/check-core-tests.sh
*/

#import "OOWaypointEntity.h"
#import "PlayerEntity.h"	// PLAYER is C++ (bead oo-9ht.177)
#import "EntityOOJavaScriptExtensions.h"
#import "OOJSEntity.h"
#import "OOJSWaypoint.h"
#import "Universe.h"

#include "oo_test.hpp"

#include <cmath>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

class PlayerEntity;
extern PlayerEntity *gOOPlayer;
extern Universe *gSharedUniverse;


class TestPlayer : public PlayerEntity	// C++ since bead oo-9ht.177 deleted the Objective-C player
{
public:
	HPVector viewpointPosition() override	{ return kZeroHPVector; }
};

// NewTestPlayer<TestPlayer>() (bead oo-9ht.177): a C++ player under the ship's facade, as
// PlayerEntity::sharedPlayer() makes the game's, retained (+1) as +alloc's object was.
template <class T>
T *NewTestPlayer()
{
	oo::Ref<T> player = oo::makeRef<T>();
	@autoreleasepool
	{
		[oo::NewEntityFacade(player) retain];
	}
	return player.get();
}


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
	if (universe == nil)
	{
		universe = (Universe *)class_createInstance([TestUniverse class], 0);	// never released
		universe->_cxxUniverse = oo::makeRef<cxx::Universe>(universe);	// what -initWithGameView: makes first (ADR-0056 amendment oo-riqmz)
	}
	gSharedUniverse = universe;
	static TestPlayer *player = nullptr;
	if (player == nullptr)  player = NewTestPlayer<TestPlayer>();
	gOOPlayer = player;
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


// +waypointWithDictionary: until bead oo-9ht.108: the waypoint's object, as the universe makes it.
OOBeaconEntityObject *WaypointObject(const oo::PList &info)
{
	return (OOBeaconEntityObject *)oo::NewEntityFacade(OOWaypointEntity::waypointWithDictionary(info));
}

OOWaypointEntity *Part(Entity *object)	{ return dynamic_cast<OOWaypointEntity *>(oo::ToCxx(object)); }


OOBeaconEntityObject *Waypoint(const std::string &code)
{
	return WaypointObject(Dict({ { "beaconCode", oo::PList(code) } }));
}

}	// namespace


OO_TEST(defaults)
{
	@autoreleasepool
	{
		SetUp();
		OOBeaconEntityObject *wp = WaypointObject(Dict({ { "unused", oo::PList(1) } }));
		OO_CHECK(wp != nil && Part(wp) != nullptr);
		OO_CHECK(HPvector_equal([wp position], kZeroHPVector));
		OO_CHECK(QuatIs([wp orientation], 1, 0, 0, 0) && Part(wp)->getOriented());
		OO_CHECK(Part(wp)->size() == 1000.0);
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
		OOBeaconEntityObject *wp = WaypointObject(Dict({
			{ "position", Vec(1, 2, 3) },
			{ "orientation", oo::PList(oo::PList::Array{ oo::PList(0.0), oo::PList(1.0), oo::PList(0.0), oo::PList(0.0) }) },
			{ "size", oo::PList(50.0) },
			{ "beaconCode", oo::PList("AB") },
			{ "beaconLabel", oo::PList("Somewhere") },
		}));
		OO_CHECK(HPvector_equal([wp position], make_HPvector(1, 2, 3)));
		OO_CHECK(QuatIs([wp orientation], 0, 1, 0, 0) && Part(wp)->getOriented());
		OO_CHECK(Part(wp)->size() == 50.0);
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
		OOBeaconEntityObject *wp = WaypointObject(oo::PList());
		OO_CHECK(HPvector_equal([wp position], kZeroHPVector));
		OO_CHECK(QuatIs([wp orientation], 1, 0, 0, 0) && !Part(wp)->getOriented());
		OO_CHECK(![wp beaconCode].has_value() && ![wp beaconLabel].has_value() && ![wp isBeacon]);
	}
}


OO_TEST(orientation)
{
	@autoreleasepool
	{
		SetUp();
		OOBeaconEntityObject *wp = Waypoint("W");
		[wp setOrientation:kZeroQuaternion];
		OO_CHECK(!Part(wp)->getOriented() && QuatIs([wp orientation], 1, 0, 0, 0));
		Quaternion q = { 0, 0, 1, 0 };
		[wp setOrientation:q];
		OO_CHECK(Part(wp)->getOriented() && QuatIs([wp orientation], 0, 0, 1, 0));
	}
}


OO_TEST(size)
{
	@autoreleasepool
	{
		SetUp();
		OOBeaconEntityObject *wp = Waypoint("W");
		Part(wp)->setSize(10.0);
		OO_CHECK(Part(wp)->size() == 10.0);
		OO_CHECK(NoDrawDistance(wp) == (GLfloat)(10.0 * 10.0 * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR * 2));
		Part(wp)->setSize(0.0);
		Part(wp)->setSize(-5.0);
		OO_CHECK(Part(wp)->size() == 10.0);
	}
}


OO_TEST(beaconStrings)
{
	@autoreleasepool
	{
		SetUp();
		OOBeaconEntityObject *wp = WaypointObject(Dict({ { "beaconCode", oo::PList("X") }, { "beaconLabel", oo::PList("Label") } }));
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
		OO_CHECK(Part(Waypoint("a"))->compareBeaconCodeWith(Waypoint("B")) == OOOrderedAscending);
		OO_CHECK(Part(Waypoint("b"))->compareBeaconCodeWith(Waypoint("A")) == OOOrderedDescending);
		OO_CHECK(Part(Waypoint("abc"))->compareBeaconCodeWith(Waypoint("ABC")) == OOOrderedSame);
	}
}


OO_TEST(beaconDrawable)
{
	@autoreleasepool
	{
		SetUp();
		OOBeaconEntityObject *wp = Waypoint("W");
		// A C++ OOHUDBeaconIcon since bead oo-7ae4p (the protocol type before), held as the
		// test retained it.
		oo::Ref<OOHUDBeaconIcon> icon(static_cast<OOHUDBeaconIcon *>([wp beaconDrawable]));
		OO_CHECK(icon != nullptr && [wp beaconDrawable] == icon.get());
		[wp setBeaconCode:std::string("V")];
		OO_CHECK([wp beaconDrawable] != nullptr && [wp beaconDrawable] != icon.get());
	}
}


OO_TEST(neighbours)
{
	@autoreleasepool
	{
		SetUp();
		OOBeaconEntityObject *wp = Waypoint("W");
		OO_CHECK([wp prevBeacon] == nil && [wp nextBeacon] == nil);
		OOBeaconEntityObject *other = nil;
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
		Entity *wp = Waypoint("W");	// the root's facade (the protocol type would pick a subclass's crossing)
		// A C++ entity (amendment oo-0mxi), not an Objective-C entity's adapter.
		OO_CHECK(dynamic_cast<OOWaypointEntity *>(oo::ToCxx(wp)) != nullptr);
		OO_CHECK(oo::AsObjCEntity(oo::ToCxx(wp)) == nullptr);
		OO_CHECK(oo::ToObjC(oo::ToCxx(wp)) == wp);
	}
}


// Registers Entity's JS class and the given class (a child of Entity) in the test's context, as the
// engine's start does; the context is made here if the test has none yet.
static void RegisterJSClasses(void (*initClass)(JSContext *, JSValueConst))
{
	extern JSContext *gOOJSMainThreadContext;
	if (gOOJSMainThreadContext == nullptr)  gOOJSMainThreadContext = JS_NewContext(JS_NewRuntime());
	JSContext *context = OOJSAcquireContext();
	JSValue global = JS_GetGlobalObject(context);
	InitOOJSEntity(context, global);
	initClass(context, global);
	JS_FreeValue(context, global);
}


// The beacon selectors on the root's facade: answered for a waypoint's part, and not for another
// entity's, whose object did not answer them before.
OO_TEST(beaconSelectorsForAWaypointOnly)
{
	@autoreleasepool
	{
		SetUp();
		OOBeaconEntityObject *wp = Waypoint("W");
		OO_CHECK([wp respondsToSelector:@selector(beaconCode)] && [wp respondsToSelector:@selector(setNextBeacon:)]);
		Entity *plain = [[[Entity alloc] init] autorelease];
		OO_CHECK(![plain respondsToSelector:@selector(beaconCode)] && ![plain respondsToSelector:@selector(isBeacon)]);
		OO_CHECK(![(OOBeaconEntityObject *)plain isBeacon] && ![(OOBeaconEntityObject *)plain beaconCode].has_value());
		OO_CHECK([(OOBeaconEntityObject *)plain nextBeacon] == nil);
	}
}


// The binding's category, which the facade carried and the C++ class's overrides answer now: what
// the engine asks a waypoint's object for by selector is what OOJSWaypoint.mm answers.
OO_TEST(jsExtensions)
{
	@autoreleasepool
	{
		SetUp();
		OOBeaconEntityObject *wp = Waypoint("W");
		RegisterJSClasses(InitOOJSWaypoint);
		const JSClassID jsClass = [wp oo_jsClassID];
		const JSClassID expectedClass = JSWaypointClassID();
		OO_CHECK(jsClass != 0 && jsClass == expectedClass);
		OO_CHECK([wp cxx_oo_jsClassName] == std::optional<std::string>("Waypoint"));
		OO_CHECK([wp isVisibleToScripts] == YES);
	}
}


OO_TEST_MAIN()
