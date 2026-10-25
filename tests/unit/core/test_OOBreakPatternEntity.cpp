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

#include "OOBreakPatternEntity.h"
#include "PlayerEntity.h"	// PLAYER is C++ (bead oo-9ht.177)
#include "OOColor.h"
#include "OODescription.h"
#include "Universe.h"

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
	{
		oo::RetainEntity(oo::MadeEntity(player));
	}
	return player.get();
}


static Entity *sRemoved = nil;


// UNIVERSE: never initialised; records what is removed.
class TestUniverse : public Universe
{
public:
	bool removeEntity(Entity *entity) override	{ sRemoved = entity; return YES; }	// the C++ entity since bead oo-9ht.39.26; the record is its object, as before
};


// --- The private vertex arrays, and nothing else ---------------------------------------------------

struct OOBreakPatternEntityTestAccess
{
	static NSUInteger VertexCount(const oo::Ref<OOBreakPatternEntity> &r)				{ OOBreakPatternEntity *e = r.get(); return e->_vertexCount; }
	static Vector VertexPosition(const oo::Ref<OOBreakPatternEntity> &r, NSUInteger i)	{ OOBreakPatternEntity *e = r.get(); return e->_vertexPosition[i]; }
	static const GLfloat *VertexColor(const oo::Ref<OOBreakPatternEntity> &r, NSUInteger i)	{ OOBreakPatternEntity *e = r.get(); return e->_vertexColor[i]; }
};

// --------------------------------------------------------------------------------------------------


namespace {

using Access = OOBreakPatternEntityTestAccess;


void SetUp()
{
	static Universe *universe = nil;
	if (universe == nil)
	{
		universe = new TestUniverse();	// never released
	}
	gSharedUniverse = universe;
	static TestPlayer *player = nullptr;
	if (player == nullptr)  player = NewTestPlayer<TestPlayer>();
	gOOPlayer = player;
	sRemoved = nil;
}


bool Near(float a, float b)  { return fabs(a - b) < 1e-4; }


bool ColorIs(const oo::Ref<OOBreakPatternEntity> &e, NSUInteger i, GLfloat r, GLfloat g, GLfloat b, GLfloat a)
{
	const GLfloat *c = Access::VertexColor(e, i);
	return c[0] == r && c[1] == g && c[2] == b && c[3] == a;
}

}	// namespace


OO_TEST(polygon)
{
	{
		SetUp();
		oo::Ref<OOBreakPatternEntity> ring = OOBreakPatternEntity::breakPatternWithPolygonSides(4, 0.0f, 2.0f);
		OO_CHECK(ring != nullptr);
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
		OO_CHECK(Access::VertexCount(OOBreakPatternEntity::breakPatternWithPolygonSides(1, 0.0f, 1.0f)) == 8);
		OO_CHECK(Access::VertexCount(OOBreakPatternEntity::breakPatternWithPolygonSides(1000, 0.0f, 1.0f)) == kOOBreakPatternMaxVertices);
	}
}


OO_TEST(flagsAndColors)
{
	{
		SetUp();
		oo::Ref<OOBreakPatternEntity> ring = OOBreakPatternEntity::breakPatternWithPolygonSides(3, 45.0f, 1.0f);
		OO_CHECK(ring->status() == STATUS_EFFECT && ring->scanClass == CLASS_NO_DRAW);
		OO_CHECK(ring->isImmuneToBreakPatternHide && !ring->canCollide());
		oo::Ref<Entity> other = oo::makeRef<Entity>();
		OO_CHECK(dynamic_cast<OOBreakPatternEntity *>(ring.get()) != nullptr && dynamic_cast<OOBreakPatternEntity *>(other.get()) == nullptr);

		// Default: red inside, blue outside.
		OO_CHECK(ColorIs(ring, 0, 1.0f, 0.0f, 0.0f, 0.5f) && ColorIs(ring, 1, 0.0f, 0.0f, 1.0f, 0.25f));
		OO_CHECK(ColorIs(ring, 7, 0.0f, 0.0f, 1.0f, 0.25f));

		ring->setInnerColor(OOColor::colorWithRed(0.0f, 1.0f, 0.0f, 1.0f).get(), OOColor::colorWithRed(1.0f, 1.0f, 1.0f, 0.5f).get());
		OO_CHECK(ColorIs(ring, 0, 0.0f, 1.0f, 0.0f, 1.0f) && ColorIs(ring, 1, 1.0f, 1.0f, 1.0f, 0.5f));
		OO_CHECK(ColorIs(ring, 6, 0.0f, 1.0f, 0.0f, 1.0f) && ColorIs(ring, 7, 1.0f, 1.0f, 1.0f, 0.5f));

		// Hidden (no longer immune): nothing is drawn.
		ring->isImmuneToBreakPatternHide = NO;
		ring->drawImmediate(false, true);
	}
}


OO_TEST(lifetime)
{
	{
		SetUp();
		oo::Ref<OOBreakPatternEntity> ring = OOBreakPatternEntity::breakPatternWithPolygonSides(4, 0.0f, 1.0f);
		Entity *facade = oo::MadeEntity(ring);	// what removeEntity: is sent
		ring->setStatus(STATUS_EFFECT);
		ring->setVelocity(make_vector(0, 0, 10));
		ring->setLifetime(100.0);

		// The lifetime runs down at the ring speed (200 a second); the ring moves meanwhile.
		ring->update(0.25);
		OO_CHECK(sRemoved == nil && HPvector_equal(ring->getPosition(), make_HPvector(0, 0, 2.5)));
		ring->update(0.25);
		OO_CHECK(sRemoved == nil);
		ring->update(0.01);
		OO_CHECK(sRemoved == facade);
	}
}


OO_TEST_MAIN()
