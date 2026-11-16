/*	test_OOMeshToOctreeConverter.mm
	Unit tests for OOMeshToOctreeConverter (src/Core/OOMeshToOctreeConverter.h): bead oo-rsk8 (Phase 3, house style
	of proposed ADR-0056).

	It links the whole game but main (tests/unit/core/meson.build entry ['*']), because the octrees
	it builds are Octree objects (ADR-0056 amendments oo-44gg, oo-novu). The expectations were
	written against the Objective-C API and run on the unconverted class first: what octree a set
	of triangles gives (nodes, radius and volume) at several depths, that degenerate triangles are
	dropped, the description, and that the triangle store grows past its sixteen inline slots.
	They were moved onto the C++ class when its Objective-C facade was deleted (bead oo-9ht.26).
	Run: bash tools/check-core-tests.sh
*/

#import "OOMeshToOctreeConverter.h"
#import "Octree.h"
#import "OODescription.h"

#include "oo_test.hpp"

#include <cmath>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


namespace {

Triangle Tri(Vector a, Vector b, Vector c)
{
	Triangle t;
	t.v[0] = a;
	t.v[1] = b;
	t.v[2] = c;
	return t;
}


// The twelve triangles of a cube centred on the origin.
void AddCube(OOMeshToOctreeConverter &converter, float h)
{
	Vector p[8];
	for (int i = 0; i < 8; i++)  p[i] = make_vector((i & 4) ? h : -h, (i & 2) ? h : -h, (i & 1) ? h : -h);
	const int faces[6][4] = { { 0, 1, 3, 2 }, { 4, 6, 7, 5 }, { 0, 4, 5, 1 }, { 2, 3, 7, 6 }, { 0, 2, 6, 4 }, { 1, 5, 7, 3 } };
	for (const auto &f : faces)
	{
		converter.addTriangle(Tri(p[f[0]], p[f[1]], p[f[2]]));
		converter.addTriangle(Tri(p[f[0]], p[f[2]], p[f[3]]));
	}
}


std::vector<int> Nodes(const oo::Ref<Octree> &octree)
{
	oo::PList representation = octree->dictionaryRepresentation();
	const oo::Data *data = representation.find("octree")->getIf<oo::Data>();
	const int *ints = (const int *)data->bytes();
	return std::vector<int>(ints, ints + data->length() / sizeof (int));
}


float Radius(const oo::Ref<Octree> &octree)
{
	return octree->dictionaryRepresentation().get<float>("radius");
}


// The octree at a depth (Nodes and Radius read its representation).
oo::Ref<Octree> At(const oo::Ref<OOMeshToOctreeConverter> &converter, NSUInteger depth)
{
	return converter->findOctreeToDepth(depth);
}


std::optional<std::string> Description(const oo::Ref<OOMeshToOctreeConverter> &converter)
{
	return converter->descriptionComponents();
}


bool Near(float a, float b)
{
	return std::fabs(a - b) < 1e-3f * std::fmax(1.0f, std::fabs(b));
}


oo::Ref<OOMeshToOctreeConverter> OneTriangle()
{
	oo::Ref<OOMeshToOctreeConverter> one = OOMeshToOctreeConverter::converterWithCapacity(1);
	one->addTriangle(Tri(make_vector(0, 0, 0), make_vector(4, 0, 0), make_vector(0, 4, 0)));
	one->addTriangle(Tri(make_vector(1, 1, 1), make_vector(1, 1, 1), make_vector(2, 2, 2)));	// degenerate: dropped
	return one;
}

}	// namespace


OO_TEST(emptyGivesAnEmptyOctree)
{
	@autoreleasepool
	{
		oo::Ref<OOMeshToOctreeConverter> empty = OOMeshToOctreeConverter::converterWithCapacity(0);
		oo::Ref<Octree> octree = At(empty, 3);
		OO_CHECK(Nodes(octree) == std::vector<int>({ 0 }));
		OO_CHECK(Radius(octree) == 0.5f);	// the half-metre pad
		OO_CHECK(octree->volume() == 0.0f);
		OO_CHECK(Description(empty) == std::optional<std::string>("0 triangles"));
	}
}


OO_TEST(oneTriangle)
{
	@autoreleasepool
	{
		oo::Ref<OOMeshToOctreeConverter> one = OneTriangle();
		OO_CHECK(Description(one) == std::optional<std::string>("1 triangles"));

		oo::Ref<Octree> d0 = At(one, 0);
		OO_CHECK(Nodes(d0) == std::vector<int>({ -1 }));
		OO_CHECK(Radius(d0) == 4.5f);
		OO_CHECK(Near(d0->volume(), 91.125f));

		OO_CHECK(Nodes(At(one, 1)) == std::vector<int>({ 1, 0, 0, 0, 0, 0, 0, 0, -1 }));
		OO_CHECK(Near(At(one, 1)->volume(), 11.3906f));
		OO_CHECK(Nodes(At(one, 2)) == std::vector<int>({ 1, 0, 0, 0, 0, 0, 0, 0, 1, -1, 0, -1, 0, -1, 0, 0, 0 }));
		OO_CHECK(Near(At(one, 2)->volume(), 4.27148f));
		OO_CHECK(Nodes(At(one, 3)) == std::vector<int>({ 1, 0, 0, 0, 0, 0, 0, 0, 1, 8, 0, 14, 0, 20, 0, 0, 0, -1, 0, -1, 0, -1, 0, -1, 0, -1, 0, -1, 0, -1, 0, 0, 0, -1, 0, -1, 0, -1, 0, 0, 0 }));
		OO_CHECK(Near(At(one, 3)->volume(), 1.77979f));
	}
}


OO_TEST(cubeGrowsPastInlineStorage)
{
	@autoreleasepool
	{
		oo::Ref<OOMeshToOctreeConverter> cube = oo::makeRef<OOMeshToOctreeConverter>(12);
		AddCube(*cube, 10);
		AddCube(*cube, 5);	// 24 triangles: past the sixteen inline slots
		OO_CHECK(Description(cube) == std::optional<std::string>("24 triangles"));

		for (unsigned d = 0; d <= 2; d++)
		{
			oo::Ref<Octree> octree = At(cube, d);
			OO_CHECK(Nodes(octree) == std::vector<int>({ -1 }) && Radius(octree) == 10.5f);
		}
		oo::Ref<Octree> d3 = At(cube, 3);
		std::vector<int> nodes = Nodes(d3);
		OO_CHECK(nodes.size() == 585);
		OO_CHECK(std::vector<int>(nodes.begin(), nodes.begin() + 9) == std::vector<int>({ 1, 8, 79, 150, 221, 292, 363, 434, 505 }));
		OO_CHECK(Near(d3->volume(), 795.867f));
		OO_CHECK(Nodes(At(cube, 4)).size() == 3401);
		OO_CHECK(Near(At(cube, 4)->volume(), 465.763f));
	}
}


OO_TEST(cxxConverter)
{
	oo::Ref<OOMeshToOctreeConverter> one = OOMeshToOctreeConverter::converterWithCapacity(1);
	one->addTriangle(Tri(make_vector(0, 0, 0), make_vector(4, 0, 0), make_vector(0, 4, 0)));
	one->addTriangle(Tri(make_vector(1, 1, 1), make_vector(1, 1, 1), make_vector(2, 2, 2)));	// degenerate: dropped
	OO_CHECK(one->descriptionComponents() == std::optional<std::string>("1 triangles"));
	oo::Ref<Octree> octree = one->findOctreeToDepth(1);
	OO_CHECK(octree.get() != nullptr && Near(octree->volume(), 11.3906f));
	OO_CHECK(Nodes(octree) == std::vector<int>({ 1, 0, 0, 0, 0, 0, 0, 0, -1 }));

	oo::Ref<OOMeshToOctreeConverter> empty = oo::makeRef<OOMeshToOctreeConverter>(0);
	OO_CHECK(empty->findOctreeToDepth(2)->volume() == 0.0f);
}


OO_TEST_MAIN()
