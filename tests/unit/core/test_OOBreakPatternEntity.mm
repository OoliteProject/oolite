/*	test_OOBreakPatternEntity.mm
	Unit tests for OOBreakPatternEntity (src/Core/Entities/OOBreakPatternEntity.h), one ring of the
	hyperspace and docking tunnel: bead oo-a014, a leaf of the Entities pattern seam (amendment
	oo-bj8 item 12).

	Its object needs the game graph, so the test links the whole game but main (['*']) and uses a
	Universe that was never initialised, of a test subclass that records what is removed, and a plain
	entity as PLAYER. The expectations were written against the Objective-C API and run on the
	unconverted class first: the polygon (sides clamped to 3...128, the aspect ratio, the closing
	pair of vertices), the default and the set inner and outer colours, the status, scan class and
	break-pattern flags, and removal once its lifetime has run out at the ring speed. Its vertex
	arrays are private; the test reads them through the access struct below, the only lines the
	conversion ported (amendment oo-862e item 2).
	Run: bash tools/check-core-tests.sh
*/

#import "OOBreakPatternEntity.h"
#import "OOColor.h"
#import "OODescription.h"
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


static Entity *sRemoved = nil;


// UNIVERSE: never initialised; records what is removed.
@interface TestUniverse: Universe
@end


@implementation TestUniverse

- (OOTimeAbsolute) getTime				{ return 0; }
- (BOOL) removeEntity:(Entity *)entity	{ sRemoved = entity; return YES; }

@end


// --- The private vertex arrays, and nothing else ---------------------------------------------------

struct OOBreakPatternEntityTestAccess
{
	static NSUInteger VertexCount(OOBreakPatternEntity *e)				{ return oo::ToCxx(e)->_vertexCount; }
	static Vector VertexPosition(OOBreakPatternEntity *e, NSUInteger i)	{ return oo::ToCxx(e)->_vertexPosition[i]; }
	static const GLfloat *VertexColor(OOBreakPatternEntity *e, NSUInteger i)	{ return oo::ToCxx(e)->_vertexColor[i]; }
};

// --------------------------------------------------------------------------------------------------


namespace {

using Access = OOBreakPatternEntityTestAccess;


void SetUp()
{
	static Universe *universe = nil;
	if (universe == nil)
	{
		universe = (Universe *)class_createInstance([TestUniverse class], 0);	// never released
		universe->_cxxUniverse = oo::makeRef<cxx::Universe>(universe);	// what -initWithGameView: makes first (ADR-0056 amendment oo-riqmz)
	}
	gSharedUniverse = universe;
	static TestPlayer *player = nil;
	if (player == nil)  player = [[TestPlayer alloc] init];
	gOOPlayer = (PlayerEntity *)player;
	sRemoved = nil;
}


bool Near(float a, float b)  { return fabs(a - b) < 1e-4; }


bool ColorIs(OOBreakPatternEntity *e, NSUInteger i, GLfloat r, GLfloat g, GLfloat b, GLfloat a)
{
	const GLfloat *c = Access::VertexColor(e, i);
	return c[0] == r && c[1] == g && c[2] == b && c[3] == a;
}

}	// namespace


OO_TEST(polygon)
{
	@autoreleasepool
	{
		SetUp();
		OOBreakPatternEntity *ring = [OOBreakPatternEntity breakPatternWithPolygonSides:4 startAngle:0.0f aspectRatio:2.0f];
		OO_CHECK(ring != nil && [ring class] == [OOBreakPatternEntity class]);
		OO_CHECK(Access::VertexCount(ring) == 10);

		// The first side starts at the top; the aspect ratio narrows the other axis (here y).
		Vector v0 = Access::VertexPosition(ring, 0), v1 = Access::VertexPosition(ring, 1);
		OO_CHECK(Near(v0.x, 0) && Near(v0.y, 25) && v0.z == -40);
		OO_CHECK(Near(v1.x, 0) && Near(v1.y, 20) && v1.z == 0);
		Vector v2 = Access::VertexPosition(ring, 2);
		OO_CHECK(Near(v2.x, 50) && Near(v2.y, 0) && v2.z == -40);
		// The strip closes on the first pair.
		OO_CHECK(vector_equal(Access::VertexPosition(ring, 8), v0) && vector_equal(Access::VertexPosition(ring, 9), v1));

		// Sides are clamped to 3...128.
		OO_CHECK(Access::VertexCount([OOBreakPatternEntity breakPatternWithPolygonSides:1 startAngle:0.0f aspectRatio:1.0f]) == 8);
		OO_CHECK(Access::VertexCount([OOBreakPatternEntity breakPatternWithPolygonSides:1000 startAngle:0.0f aspectRatio:1.0f]) == kOOBreakPatternMaxVertices);
	}
}


OO_TEST(flagsAndColors)
{
	@autoreleasepool
	{
		SetUp();
		OOBreakPatternEntity *ring = [OOBreakPatternEntity breakPatternWithPolygonSides:3 startAngle:45.0f aspectRatio:1.0f];
		OO_CHECK([ring status] == STATUS_EFFECT && [ring scanClass] == CLASS_NO_DRAW);
		OO_CHECK([ring isImmuneToBreakPatternHide] && [ring isBreakPattern] && ![ring canCollide]);
		Entity *other = [[[Entity alloc] init] autorelease];
		OO_CHECK(![other isBreakPattern]);

		// Default: red inside, blue outside.
		OO_CHECK(ColorIs(ring, 0, 1.0f, 0.0f, 0.0f, 0.5f) && ColorIs(ring, 1, 0.0f, 0.0f, 1.0f, 0.25f));
		OO_CHECK(ColorIs(ring, 7, 0.0f, 0.0f, 1.0f, 0.25f));

		[ring setInnerColor:[OOColor colorWithRed:0.0f green:1.0f blue:0.0f alpha:1.0f] outerColor:[OOColor colorWithRed:1.0f green:1.0f blue:1.0f alpha:0.5f]];
		OO_CHECK(ColorIs(ring, 0, 0.0f, 1.0f, 0.0f, 1.0f) && ColorIs(ring, 1, 1.0f, 1.0f, 1.0f, 0.5f));
		OO_CHECK(ColorIs(ring, 6, 0.0f, 1.0f, 0.0f, 1.0f) && ColorIs(ring, 7, 1.0f, 1.0f, 1.0f, 0.5f));

		OO_CHECK(oo::DescriptionOf(ring).starts_with("<OOBreakPatternEntity 0x"));

		// Hidden (no longer immune): nothing is drawn.
		ring->_cxxEntity->isImmuneToBreakPatternHide = NO;
		[ring drawImmediate:false translucent:true];
	}
}


OO_TEST(lifetime)
{
	@autoreleasepool
	{
		SetUp();
		OOBreakPatternEntity *ring = [OOBreakPatternEntity breakPatternWithPolygonSides:4 startAngle:0.0f aspectRatio:1.0f];
		[ring setStatus:STATUS_EFFECT];
		[ring setVelocity:make_vector(0, 0, 10)];
		[ring setLifetime:100.0];

		// The lifetime runs down at the ring speed (200 a second); the ring moves meanwhile.
		[ring update:0.25];
		OO_CHECK(sRemoved == nil && HPvector_equal([ring position], make_HPvector(0, 0, 2.5)));
		[ring update:0.25];
		OO_CHECK(sRemoved == nil);
		[ring update:0.01];
		OO_CHECK(sRemoved == ring);
	}
}


OO_TEST_MAIN()
