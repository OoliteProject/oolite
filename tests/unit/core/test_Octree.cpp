/*	test_Octree.mm
	Unit tests for Octree and OOOctreeBuilder (src/Core/Octree.h): bead oo-novu (Phase 3, house style of proposed ADR-0056).

	The expectations were written against the Objective-C API and run on the unconverted classes
	first: what the builder builds (and folds), the cache representation and its round trip, the
	volume, the random point, line hits and octree-octree hits, and the facade's -init forms that
	answer nil. Ported to the C++ API by bead oo-9ht.20, which deleted the facade.
	Run: bash tools/check-core-tests.sh
*/

#import "Octree.h"

#include "oo_test.hpp"

#include <cmath>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


namespace {

bool Same(Vector a, Vector b)
{
	return a.x == b.x && a.y == b.y && a.z == b.z;
}


bool Near(float a, float b)
{
	return std::fabs(a - b) < 1e-4f;
}


const Triangle kIdentityIJK = { { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } } };


// The node values of an octree, from its cache representation.
std::vector<int> Nodes(const oo::PList &representation)
{
	const oo::Data *data = representation.find("octree")->getIf<oo::Data>();
	const int *ints = (const int *)data->bytes();
	return std::vector<int>(ints, ints + data->length() / sizeof (int));
}

}	// namespace


// An octree built by an OOOctreeBuilder.
#define BUILD(radius, ...) \
	([&]() { oo::Ref<OOOctreeBuilder> builder = oo::makeRef<OOOctreeBuilder>(); __VA_ARGS__; return builder->buildOctreeWithRadius(radius); }())


OO_TEST(builderAndRepresentation)
{
	{
		oo::Ref<Octree> solid = BUILD(2.0f, builder->writeSolid());
		OO_CHECK(solid);
		oo::PList representation = solid->dictionaryRepresentation();
		OO_CHECK(Nodes(representation) == std::vector<int>({ -1 }));
		OO_CHECK(representation.get<float>("radius") == 2.0f);

		oo::Ref<Octree> empty = BUILD(2.0f, builder->writeEmpty());
		OO_CHECK(Nodes(empty->dictionaryRepresentation()) == std::vector<int>({ 0 }));

		// One inner node with its first child solid: the root holds the offset to its children.
		oo::Ref<Octree> corner = BUILD(2.0f, builder->beginInnerNode(); builder->writeSolid(); for (int i = 0; i < 7; i++)  builder->writeEmpty(); builder->endInnerNode());
		OO_CHECK(Nodes(corner->dictionaryRepresentation()) == std::vector<int>({ 1, -1, 0, 0, 0, 0, 0, 0, 0 }));

		// Eight solid children fold into one solid node.
		oo::Ref<Octree> folded = BUILD(2.0f, builder->beginInnerNode(); for (int i = 0; i < 8; i++)  builder->writeSolid(); builder->endInnerNode());
		OO_CHECK(Nodes(folded->dictionaryRepresentation()) == std::vector<int>({ -1 }));

		// The representation comes back as an equal octree.
		oo::Ref<Octree> copy = Octree::initWithDictionary(corner->dictionaryRepresentation());
		OO_CHECK(copy && copy != corner);
		OO_CHECK(Nodes(copy->dictionaryRepresentation()) == Nodes(corner->dictionaryRepresentation()));
		OO_CHECK(copy->volume() == corner->volume());
	}
}


OO_TEST(invalidRepresentations)
{
	{
		OO_CHECK(Octree::initWithDictionary(oo::PList(oo::PList::Dict())).get() == nullptr);	// no octree

		oo::PList::Dict ragged;
		ragged["octree"] = oo::PList(oo::Data("abc", 3));	// not a whole number of nodes
		ragged["radius"] = oo::PList(1.0);
		OO_CHECK(Octree::initWithDictionary(oo::PList(std::move(ragged))).get() == nullptr);

		oo::PList::Dict empty;
		empty["octree"] = oo::PList(oo::Data());	// no nodes at all
		empty["radius"] = oo::PList(1.0);
		OO_CHECK(Octree::initWithDictionary(oo::PList(std::move(empty))).get() == nullptr);
	}
}


OO_TEST(volumeAndRandomPoint)
{
	{
		OO_CHECK(BUILD(2.0f, builder->writeSolid())->volume() == 8.0f);
		OO_CHECK(BUILD(2.0f, builder->writeEmpty())->volume() == 0.0f);

		oo::Ref<Octree> corner = BUILD(2.0f, builder->beginInnerNode(); builder->writeSolid(); for (int i = 0; i < 7; i++)  builder->writeEmpty(); builder->endInnerNode());
		OO_CHECK(corner->volume() == 1.0f);
		OO_CHECK(Same(corner->randomPoint(), make_vector(1, 1, 1)));	// the one full octant's centre
		OO_CHECK(corner->octreeScaledBy(2.0f)->volume() == 8.0f);
		OO_CHECK(Same(corner->octreeScaledBy(2.0f)->randomPoint(), make_vector(2, 2, 2)));
		OO_CHECK(Same(BUILD(2.0f, builder->writeSolid())->randomPoint(), kZeroVector));
	}
}


OO_TEST(lineHits)
{
	{
		oo::Ref<Octree> solid = BUILD(2.0f, builder->writeSolid());
		OO_CHECK(solid->isHitByLine(make_vector(-10, 0, 0), make_vector(10, 0, 0)) == 10.0f);	// solid root: distance to v0

		oo::Ref<Octree> empty = BUILD(2.0f, builder->writeEmpty());
		OO_CHECK(empty->isHitByLine(make_vector(-10, 0, 0), make_vector(10, 0, 0)) == 0.0f);

		oo::Ref<Octree> corner = BUILD(2.0f, builder->beginInnerNode(); builder->writeSolid(); for (int i = 0; i < 7; i++)  builder->writeEmpty(); builder->endInnerNode());
		// (the values the Objective-C class gave: the line walk offsets octants with the opposite
		// sign to isHitByOctree(), so each of these lines finds the solid octant)
		OO_CHECK(corner->isHitByLine(make_vector(-1, -1, 10), make_vector(-1, -1, -10)) == 11.0f);
		OO_CHECK(Near(corner->isHitByLine(make_vector(-1, 1, 10), make_vector(-1, 1, -10)), 11.1803f));
		OO_CHECK(Near(corner->isHitByLine(make_vector(1, 1, 10), make_vector(1, 1, -10)), 11.3578f));
		OO_CHECK(Near(corner->isHitByLine(make_vector(1, 1, 10), make_vector(1, 1, -10)), 11.3578f));	// repeatable
		OO_CHECK(corner->isHitByLine(make_vector(10, 10, 10), make_vector(20, 20, 20)) == 0.0f);	// misses the cube
	}
}


OO_TEST(octreeHits)
{
	{
		oo::Ref<Octree> a = BUILD(2.0f, builder->writeSolid());
		oo::Ref<Octree> b = BUILD(1.0f, builder->writeSolid());
		oo::Ref<Octree> empty = BUILD(1.0f, builder->writeEmpty());
		oo::Ref<Octree> corner = BUILD(2.0f, builder->beginInnerNode(); builder->writeSolid(); for (int i = 0; i < 7; i++)  builder->writeEmpty(); builder->endInnerNode());

		OO_CHECK(a->isHitByOctree(b.get(), make_vector(0, 0, 0), kIdentityIJK));
		OO_CHECK(!a->isHitByOctree(b.get(), make_vector(10, 0, 0), kIdentityIJK));
		OO_CHECK(!a->isHitByOctree(empty.get(), make_vector(0, 0, 0), kIdentityIJK));
		OO_CHECK(!a->isHitByOctree(nullptr, make_vector(0, 0, 0), kIdentityIJK));

		// Child 0 is the low-coordinate octant.
		OO_CHECK(corner->isHitByOctree(b.get(), make_vector(-1.5f, -1.5f, -1.5f), kIdentityIJK));
		OO_CHECK(!corner->isHitByOctree(b.get(), make_vector(1.5f, 1.5f, 1.5f), kIdentityIJK));
		OO_CHECK(!corner->isHitByOctree(b.get(), make_vector(-1.5f, -1.5f, 1.5f), kIdentityIJK));

		// Scaled: b at 3 units misses unscaled, hits once b is scaled up.
		OO_CHECK(!a->isHitByOctree(b.get(), make_vector(3.5f, 0, 0), kIdentityIJK, 1.0f, 1.0f));
		OO_CHECK(a->isHitByOctree(b.get(), make_vector(3.5f, 0, 0), kIdentityIJK, 1.0f, 2.0f));
		OO_CHECK(!a->isHitByOctree(nullptr, make_vector(0, 0, 0), kIdentityIJK, 1.0f, 1.0f));
	}
}


OO_TEST(cxxOctree)
{
	oo::Ref<OOOctreeBuilder> builder = oo::makeRef<OOOctreeBuilder>();
	builder->beginInnerNode();
	builder->writeSolid();
	for (int i = 0; i < 7; i++)  builder->writeEmpty();
	builder->endInnerNode();
	oo::Ref<Octree> corner = builder->buildOctreeWithRadius(2.0f);
	OO_CHECK(corner.get() != nullptr);
	OO_CHECK(corner->volume() == 1.0f);
	OO_CHECK(Nodes(corner->dictionaryRepresentation()) == std::vector<int>({ 1, -1, 0, 0, 0, 0, 0, 0, 0 }));
	OO_CHECK(corner->octreeScaledBy(2.0f)->volume() == 8.0f);

	oo::Ref<Octree> copy = Octree::initWithDictionary(corner->dictionaryRepresentation());
	OO_CHECK(copy.get() != nullptr && copy.get() != corner.get() && copy->volume() == 1.0f);
	OO_CHECK(Octree::initWithDictionary(oo::PList(oo::PList::Dict())).get() == nullptr);

	oo::Ref<OOOctreeBuilder> small = oo::makeRef<OOOctreeBuilder>();
	small->writeSolid();
	oo::Ref<Octree> b = small->buildOctreeWithRadius(1.0f);
	OO_CHECK(corner->isHitByOctree(b.get(), make_vector(-1.5f, -1.5f, -1.5f), kIdentityIJK));
	OO_CHECK(!corner->isHitByOctree(b.get(), make_vector(1.5f, 1.5f, 1.5f), kIdentityIJK));
	OO_CHECK(!corner->isHitByOctree(nullptr, kZeroVector, kIdentityIJK));
	OO_CHECK(!corner->isHitByOctree(nullptr, kZeroVector, kIdentityIJK, 1.0f, 1.0f));
	OO_CHECK(corner->isHitByLine(make_vector(-1, -1, 10), make_vector(-1, -1, -10)) == 11.0f);
}


OO_TEST_MAIN()
