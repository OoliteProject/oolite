/*	test_OOMeshToOctreeConverter.mm
	Unit tests for cxx::OOMeshToOctreeConverter (src/Core/OOMeshToOctreeConverter.h) and its
	Objective-C facade (OOMeshToOctreeConverter+ObjCBridge.h): bead oo-rsk8 (Phase 3, house style
	of proposed ADR-0056).

	It links the whole game but main (tests/unit/core/meson.build entry ['*']), because the octrees
	it builds are Octree objects (ADR-0056 amendments oo-44gg, oo-novu). The expectations were
	written against the Objective-C API and run on the unconverted class first: what octree a set
	of triangles gives (nodes, radius and volume) at several depths, that degenerate triangles are
	dropped, the description, and that the triangle store grows past its sixteen inline slots.
	The last tests pin the C++ class and the facade's contract.
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
void AddCube(OOMeshToOctreeConverter *converter, float h)
{
	Vector p[8];
	for (int i = 0; i < 8; i++)  p[i] = make_vector((i & 4) ? h : -h, (i & 2) ? h : -h, (i & 1) ? h : -h);
	const int faces[6][4] = { { 0, 1, 3, 2 }, { 4, 6, 7, 5 }, { 0, 4, 5, 1 }, { 2, 3, 7, 6 }, { 0, 2, 6, 4 }, { 1, 5, 7, 3 } };
	for (const auto &f : faces)
	{
		[converter addTriangle:Tri(p[f[0]], p[f[1]], p[f[2]])];
		[converter addTriangle:Tri(p[f[0]], p[f[2]], p[f[3]])];
	}
}


std::vector<int> Nodes(Octree *octree)
{
	oo::PList representation = [octree cxx_dictionaryRepresentation];
	const oo::Data *data = representation.find("octree")->getIf<oo::Data>();
	const int *ints = (const int *)data->bytes();
	return std::vector<int>(ints, ints + data->length() / sizeof (int));
}


float Radius(Octree *octree)
{
	return [octree cxx_dictionaryRepresentation].get<float>("radius");
}


bool Near(float a, float b)
{
	return std::fabs(a - b) < 1e-3f * std::fmax(1.0f, std::fabs(b));
}


OOMeshToOctreeConverter *OneTriangle()
{
	OOMeshToOctreeConverter *one = [OOMeshToOctreeConverter converterWithCapacity:1];
	[one addTriangle:Tri(make_vector(0, 0, 0), make_vector(4, 0, 0), make_vector(0, 4, 0))];
	[one addTriangle:Tri(make_vector(1, 1, 1), make_vector(1, 1, 1), make_vector(2, 2, 2))];	// degenerate: dropped
	return one;
}

}	// namespace


OO_TEST(emptyGivesAnEmptyOctree)
{
	@autoreleasepool
	{
		OOMeshToOctreeConverter *empty = [OOMeshToOctreeConverter converterWithCapacity:0];
		Octree *octree = [empty findOctreeToDepth:3];
		OO_CHECK(Nodes(octree) == std::vector<int>({ 0 }));
		OO_CHECK(Radius(octree) == 0.5f);	// the half-metre pad
		OO_CHECK([octree volume] == 0.0f);
		std::string text = oo::DescriptionOf(empty);
		OO_CHECK(text.starts_with("<OOMeshToOctreeConverter 0x") && text.ends_with(">{0 triangles}"));
	}
}


OO_TEST(oneTriangle)
{
	@autoreleasepool
	{
		OOMeshToOctreeConverter *one = OneTriangle();
		OO_CHECK(oo::DescriptionOf(one).ends_with(">{1 triangles}"));

		Octree *d0 = [one findOctreeToDepth:0];
		OO_CHECK(Nodes(d0) == std::vector<int>({ -1 }));
		OO_CHECK(Radius(d0) == 4.5f);
		OO_CHECK(Near([d0 volume], 91.125f));

		OO_CHECK(Nodes([one findOctreeToDepth:1]) == std::vector<int>({ 1, 0, 0, 0, 0, 0, 0, 0, -1 }));
		OO_CHECK(Near([[one findOctreeToDepth:1] volume], 11.3906f));
		OO_CHECK(Nodes([one findOctreeToDepth:2]) == std::vector<int>({ 1, 0, 0, 0, 0, 0, 0, 0, 1, -1, 0, -1, 0, -1, 0, 0, 0 }));
		OO_CHECK(Near([[one findOctreeToDepth:2] volume], 4.27148f));
		OO_CHECK(Nodes([one findOctreeToDepth:3]) == std::vector<int>({ 1, 0, 0, 0, 0, 0, 0, 0, 1, 8, 0, 14, 0, 20, 0, 0, 0, -1, 0, -1, 0, -1, 0, -1, 0, -1, 0, -1, 0, -1, 0, 0, 0, -1, 0, -1, 0, -1, 0, 0, 0 }));
		OO_CHECK(Near([[one findOctreeToDepth:3] volume], 1.77979f));
	}
}


OO_TEST(cubeGrowsPastInlineStorage)
{
	@autoreleasepool
	{
		OOMeshToOctreeConverter *cube = [[[OOMeshToOctreeConverter alloc] initWithCapacity:12] autorelease];
		AddCube(cube, 10);
		AddCube(cube, 5);	// 24 triangles: past the sixteen inline slots
		OO_CHECK(oo::DescriptionOf(cube).ends_with(">{24 triangles}"));

		for (unsigned d = 0; d <= 2; d++)
		{
			Octree *octree = [cube findOctreeToDepth:d];
			OO_CHECK(Nodes(octree) == std::vector<int>({ -1 }) && Radius(octree) == 10.5f);
		}
		Octree *d3 = [cube findOctreeToDepth:3];
		std::vector<int> nodes = Nodes(d3);
		OO_CHECK(nodes.size() == 585);
		OO_CHECK(std::vector<int>(nodes.begin(), nodes.begin() + 9) == std::vector<int>({ 1, 8, 79, 150, 221, 292, 363, 434, 505 }));
		OO_CHECK(Near([d3 volume], 795.867f));
		OO_CHECK(Nodes([cube findOctreeToDepth:4]).size() == 3401);
		OO_CHECK(Near([[cube findOctreeToDepth:4] volume], 465.763f));
	}
}


OO_TEST(cxxConverter)
{
	oo::Ref<cxx::OOMeshToOctreeConverter> one = cxx::OOMeshToOctreeConverter::converterWithCapacity(1);
	one->addTriangle(Tri(make_vector(0, 0, 0), make_vector(4, 0, 0), make_vector(0, 4, 0)));
	one->addTriangle(Tri(make_vector(1, 1, 1), make_vector(1, 1, 1), make_vector(2, 2, 2)));	// degenerate: dropped
	OO_CHECK(one->descriptionComponents() == std::optional<std::string>("1 triangles"));
	oo::Ref<cxx::Octree> octree = one->findOctreeToDepth(1);
	OO_CHECK(octree.get() != nullptr && Near(octree->volume(), 11.3906f));
	OO_CHECK(Nodes(oo::ToObjC(octree)) == std::vector<int>({ 1, 0, 0, 0, 0, 0, 0, 0, -1 }));

	oo::Ref<cxx::OOMeshToOctreeConverter> empty = oo::makeRef<cxx::OOMeshToOctreeConverter>(0);
	OO_CHECK(empty->findOctreeToDepth(2)->volume() == 0.0f);
}


OO_TEST(facadeNilStaysNil)
{
	OOMeshToOctreeConverter *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOMeshToOctreeConverter *>(nullptr)) == nil);
	OO_CHECK([none findOctreeToDepth:2] == nil);
}


OO_TEST(facadeIdentity)
{
	@autoreleasepool
	{
		OOMeshToOctreeConverter *made = [[[OOMeshToOctreeConverter alloc] initWithCapacity:4] autorelease];
		OO_CHECK(oo::ToObjC(oo::ToCxx(made)) == made);

		OOMeshToOctreeConverter *one = OneTriangle();
		OO_CHECK(oo::ToObjC(oo::ToCxx(one)) == one);
		OO_CHECK([one isKindOfClass:[OOMeshToOctreeConverter class]]);

		oo::Ref<cxx::OOMeshToOctreeConverter> cxxConverter = cxx::OOMeshToOctreeConverter::converterWithCapacity(2);
		OOMeshToOctreeConverter *facade = oo::ToObjC(cxxConverter);
		OO_CHECK(facade != nil && facade == oo::ToObjC(cxxConverter.get()));
		OO_CHECK(oo::ToCxx(facade) == cxxConverter.get());
		OO_CHECK([OOMeshToOctreeConverter converterWithCapacity:1] != [OOMeshToOctreeConverter converterWithCapacity:1]);
	}
}


OO_TEST_MAIN()
