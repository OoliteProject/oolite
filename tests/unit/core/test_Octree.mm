/*	test_Octree.mm
	Unit tests for cxx::Octree and OOOctreeBuilder (src/Core/Octree.h) and Octree's Objective-C
	facade (Octree+ObjCBridge.h): bead oo-novu (Phase 3, house style of proposed ADR-0056).

	The expectations were written against the Objective-C API and run on the unconverted classes
	first: what the builder builds (and folds), the cache representation and its round trip, the
	volume, the random point, line hits and octree-octree hits, and the facade's -init forms that
	answer nil. The last tests pin the C++ classes and the facade's contract.
	Run: bash tools/check-core-tests.sh
*/

#import "Octree.h"
#import "OODescription.h"

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


// An octree built by an OOOctreeBuilder (C++ since this bead, with no facade), handed to the
// Objective-C API through its facade.
#define BUILD(radius, ...) \
	([&]() { oo::Ref<OOOctreeBuilder> builder = oo::makeRef<OOOctreeBuilder>(); __VA_ARGS__; return oo::ToObjC(builder->buildOctreeWithRadius(radius)); }())


OO_TEST(builderAndRepresentation)
{
	@autoreleasepool
	{
		Octree *solid = BUILD(2.0f, builder->writeSolid());
		OO_CHECK(solid != nil);
		oo::PList representation = [solid cxx_dictionaryRepresentation];
		OO_CHECK(Nodes(representation) == std::vector<int>({ -1 }));
		OO_CHECK(representation.get<float>("radius") == 2.0f);

		Octree *empty = BUILD(2.0f, builder->writeEmpty());
		OO_CHECK(Nodes([empty cxx_dictionaryRepresentation]) == std::vector<int>({ 0 }));

		// One inner node with its first child solid: the root holds the offset to its children.
		Octree *corner = BUILD(2.0f, builder->beginInnerNode(); builder->writeSolid(); for (int i = 0; i < 7; i++)  builder->writeEmpty(); builder->endInnerNode());
		OO_CHECK(Nodes([corner cxx_dictionaryRepresentation]) == std::vector<int>({ 1, -1, 0, 0, 0, 0, 0, 0, 0 }));

		// Eight solid children fold into one solid node.
		Octree *folded = BUILD(2.0f, builder->beginInnerNode(); for (int i = 0; i < 8; i++)  builder->writeSolid(); builder->endInnerNode());
		OO_CHECK(Nodes([folded cxx_dictionaryRepresentation]) == std::vector<int>({ -1 }));

		// The representation comes back as an equal octree.
		Octree *copy = [[[Octree alloc] cxx_initWithDictionary:[corner cxx_dictionaryRepresentation]] autorelease];
		OO_CHECK(copy != nil && copy != corner);
		OO_CHECK(Nodes([copy cxx_dictionaryRepresentation]) == Nodes([corner cxx_dictionaryRepresentation]));
		OO_CHECK([copy volume] == [corner volume]);
	}
}


OO_TEST(invalidRepresentations)
{
	@autoreleasepool
	{
		OO_CHECK([[Octree alloc] cxx_initWithDictionary:oo::PList(oo::PList::Dict())] == nil);	// no octree

		oo::PList::Dict ragged;
		ragged["octree"] = oo::PList(oo::Data("abc", 3));	// not a whole number of nodes
		ragged["radius"] = oo::PList(1.0);
		OO_CHECK([[Octree alloc] cxx_initWithDictionary:oo::PList(std::move(ragged))] == nil);

		oo::PList::Dict empty;
		empty["octree"] = oo::PList(oo::Data());	// no nodes at all
		empty["radius"] = oo::PList(1.0);
		OO_CHECK([[Octree alloc] cxx_initWithDictionary:oo::PList(std::move(empty))] == nil);
	}
}


OO_TEST(volumeAndRandomPoint)
{
	@autoreleasepool
	{
		OO_CHECK([BUILD(2.0f, builder->writeSolid()) volume] == 8.0f);
		OO_CHECK([BUILD(2.0f, builder->writeEmpty()) volume] == 0.0f);

		Octree *corner = BUILD(2.0f, builder->beginInnerNode(); builder->writeSolid(); for (int i = 0; i < 7; i++)  builder->writeEmpty(); builder->endInnerNode());
		OO_CHECK([corner volume] == 1.0f);
		OO_CHECK(Same([corner randomPoint], make_vector(1, 1, 1)));	// the one full octant's centre
		OO_CHECK([[corner octreeScaledBy:2.0f] volume] == 8.0f);
		OO_CHECK(Same([[corner octreeScaledBy:2.0f] randomPoint], make_vector(2, 2, 2)));
		OO_CHECK(Same([BUILD(2.0f, builder->writeSolid()) randomPoint], kZeroVector));
	}
}


OO_TEST(lineHits)
{
	@autoreleasepool
	{
		Octree *solid = BUILD(2.0f, builder->writeSolid());
		OO_CHECK([solid isHitByLine:make_vector(-10, 0, 0) v1:make_vector(10, 0, 0)] == 10.0f);	// solid root: distance to v0

		Octree *empty = BUILD(2.0f, builder->writeEmpty());
		OO_CHECK([empty isHitByLine:make_vector(-10, 0, 0) v1:make_vector(10, 0, 0)] == 0.0f);

		Octree *corner = BUILD(2.0f, builder->beginInnerNode(); builder->writeSolid(); for (int i = 0; i < 7; i++)  builder->writeEmpty(); builder->endInnerNode());
		// (the values the Objective-C class gave: the line walk offsets octants with the opposite
		// sign to isHitByOctree(), so each of these lines finds the solid octant)
		OO_CHECK([corner isHitByLine:make_vector(-1, -1, 10) v1:make_vector(-1, -1, -10)] == 11.0f);
		OO_CHECK(Near([corner isHitByLine:make_vector(-1, 1, 10) v1:make_vector(-1, 1, -10)], 11.1803f));
		OO_CHECK(Near([corner isHitByLine:make_vector(1, 1, 10) v1:make_vector(1, 1, -10)], 11.3578f));
		OO_CHECK(Near([corner isHitByLine:make_vector(1, 1, 10) v1:make_vector(1, 1, -10)], 11.3578f));	// repeatable
		OO_CHECK([corner isHitByLine:make_vector(10, 10, 10) v1:make_vector(20, 20, 20)] == 0.0f);	// misses the cube
	}
}


OO_TEST(octreeHits)
{
	@autoreleasepool
	{
		Octree *a = BUILD(2.0f, builder->writeSolid());
		Octree *b = BUILD(1.0f, builder->writeSolid());
		Octree *empty = BUILD(1.0f, builder->writeEmpty());
		Octree *corner = BUILD(2.0f, builder->beginInnerNode(); builder->writeSolid(); for (int i = 0; i < 7; i++)  builder->writeEmpty(); builder->endInnerNode());

		OO_CHECK([a isHitByOctree:b withOrigin:make_vector(0, 0, 0) andIJK:kIdentityIJK]);
		OO_CHECK(![a isHitByOctree:b withOrigin:make_vector(10, 0, 0) andIJK:kIdentityIJK]);
		OO_CHECK(![a isHitByOctree:empty withOrigin:make_vector(0, 0, 0) andIJK:kIdentityIJK]);
		OO_CHECK(![a isHitByOctree:nil withOrigin:make_vector(0, 0, 0) andIJK:kIdentityIJK]);

		// Child 0 is the low-coordinate octant.
		OO_CHECK([corner isHitByOctree:b withOrigin:make_vector(-1.5f, -1.5f, -1.5f) andIJK:kIdentityIJK]);
		OO_CHECK(![corner isHitByOctree:b withOrigin:make_vector(1.5f, 1.5f, 1.5f) andIJK:kIdentityIJK]);
		OO_CHECK(![corner isHitByOctree:b withOrigin:make_vector(-1.5f, -1.5f, 1.5f) andIJK:kIdentityIJK]);

		// Scaled: b at 3 units misses unscaled, hits once b is scaled up.
		OO_CHECK(![a isHitByOctree:b withOrigin:make_vector(3.5f, 0, 0) andIJK:kIdentityIJK s1:1.0f s2:1.0f]);
		OO_CHECK([a isHitByOctree:b withOrigin:make_vector(3.5f, 0, 0) andIJK:kIdentityIJK s1:1.0f s2:2.0f]);
		OO_CHECK(![a isHitByOctree:nil withOrigin:make_vector(0, 0, 0) andIJK:kIdentityIJK s1:1.0f s2:1.0f]);
	}
}


OO_TEST(description)
{
	@autoreleasepool
	{
		std::string text = oo::DescriptionOf(BUILD(1.0f, builder->writeSolid()));
		OO_CHECK(text.starts_with("<Octree 0x") && text.ends_with(">"));
	}
}


OO_TEST(cxxOctree)
{
	oo::Ref<OOOctreeBuilder> builder = oo::makeRef<OOOctreeBuilder>();
	builder->beginInnerNode();
	builder->writeSolid();
	for (int i = 0; i < 7; i++)  builder->writeEmpty();
	builder->endInnerNode();
	oo::Ref<cxx::Octree> corner = builder->buildOctreeWithRadius(2.0f);
	OO_CHECK(corner.get() != nullptr);
	OO_CHECK(corner->volume() == 1.0f);
	OO_CHECK(Nodes(corner->dictionaryRepresentation()) == std::vector<int>({ 1, -1, 0, 0, 0, 0, 0, 0, 0 }));
	OO_CHECK(corner->octreeScaledBy(2.0f)->volume() == 8.0f);

	oo::Ref<cxx::Octree> copy = cxx::Octree::initWithDictionary(corner->dictionaryRepresentation());
	OO_CHECK(copy.get() != nullptr && copy.get() != corner.get() && copy->volume() == 1.0f);
	OO_CHECK(cxx::Octree::initWithDictionary(oo::PList(oo::PList::Dict())).get() == nullptr);

	oo::Ref<OOOctreeBuilder> small = oo::makeRef<OOOctreeBuilder>();
	small->writeSolid();
	oo::Ref<cxx::Octree> b = small->buildOctreeWithRadius(1.0f);
	OO_CHECK(corner->isHitByOctree(b.get(), make_vector(-1.5f, -1.5f, -1.5f), kIdentityIJK));
	OO_CHECK(!corner->isHitByOctree(b.get(), make_vector(1.5f, 1.5f, 1.5f), kIdentityIJK));
	OO_CHECK(!corner->isHitByOctree(nullptr, kZeroVector, kIdentityIJK));
	OO_CHECK(!corner->isHitByOctree(nullptr, kZeroVector, kIdentityIJK, 1.0f, 1.0f));
	OO_CHECK(corner->isHitByLine(make_vector(-1, -1, 10), make_vector(-1, -1, -10)) == 11.0f);
}


OO_TEST(facadeNilStaysNil)
{
	Octree *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::Octree *>(nullptr)) == nil);
	OO_CHECK([none volume] == 0.0f);
	OO_CHECK([none octreeScaledBy:2.0f] == nil);
}


OO_TEST(facadeIdentity)
{
	@autoreleasepool
	{
		// A facade made by -cxx_initWithDictionary: is its C++ octree's facade.
		Octree *corner = BUILD(2.0f, builder->beginInnerNode(); builder->writeSolid(); for (int i = 0; i < 7; i++)  builder->writeEmpty(); builder->endInnerNode());
		Octree *copy = [[[Octree alloc] cxx_initWithDictionary:[corner cxx_dictionaryRepresentation]] autorelease];
		OO_CHECK(oo::ToObjC(oo::ToCxx(copy)) == copy);
		OO_CHECK(oo::ToObjC(oo::ToCxx(corner)) == corner);

		// A C++ octree crosses to one facade, and back to itself.
		oo::Ref<cxx::Octree> scaled = oo::ToCxx(corner)->octreeScaledBy(3.0f);
		Octree *facade = oo::ToObjC(scaled);
		OO_CHECK(facade != nil && facade == oo::ToObjC(scaled.get()));
		OO_CHECK(oo::ToCxx(facade) == scaled.get());
		OO_CHECK([corner octreeScaledBy:3.0f] != facade);	// a new octree each time, as before
	}
}


OO_TEST_MAIN()
