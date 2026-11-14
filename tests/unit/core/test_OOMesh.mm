/*	test_OOMesh.mm
	Unit tests for OOMesh (src/Core/OOMesh.h/.mm), the drawable of a static mesh from a DAT file:
	bead oo-dnbf, slice 1 of docs/phases/3-slices/OOMesh.md (Phase 3, house style of proposed
	ADR-0056; a converted subclass of the converted root OODrawable, amendments oo-smy and oo-pni4).

	The mesh loads its model through the resource manager, caches its data and octree in the cache
	manager, makes its materials and registers with the graphics reset manager, so the test links
	every game object but main's (tests/unit/core/meson.build entry ['*'], amendment oo-44gg) and
	runs on the hidden GL context of oo_gl_test_context.hpp. The models are DAT files the test
	writes to a scratch Resources/Models folder, which is the only resource root: the current
	directory, the home and the add-on folders all point into the scratch folder (amendment oo-rmd7
	item 4), so no add-on is ever scanned. The tetrahedron has no TEXTURES section, so its one
	material is the placeholder material and no texture is loaded.

	The expectations were written against the Objective-C API and run on the unconverted class
	first: loading (counts, name, radius, draw distance, bounding box, parts, the material and
	shader dictionaries, the description), scaling, a missing model, the mesh and octree caches,
	the placeholder material, -copy and -mutableCopy, -meshRescaledBy:, the subentity bounding box,
	the debug state and size, and a graphics reset after a mesh is gone (it unregistered itself)
	(commit 67fcb82ac). Slice 1 made the class shell C++ (cxx::OOMesh) with the Objective-C OOMesh
	as its facade, so they now run through the facade, which is its forwarding test; only the
	OOCacheManager (Octree) category became free functions, which OctreeForModel and
	SetOctreeForModel below now call. The facade's contract (identity, nil, the same answers from
	the C++ members and through the root's C++ pointer, the C++ factory) is checked last.
	Slice 3 (bead oo-9z7x) made the geometry C++ members; the pins of laterSlices and copies ran
	on it unchanged, and geometryMembers checks the members against the facade. Slice 4 (bead
	oo-zmix) made the rendering members: rendering was pinned first, and renderingMembers checks
	the members. Slice 2 (bead oo-rdwg) made loading and copying members and the mesh its own
	graphics reset client; loadingMembers checks them with no facade alive.
	Run: bash tools/check-core-tests.sh
*/

#import "OOMesh.h"
#import "OOCacheManager.h"
#import "OOGraphicsResetManager.h"
#import "OOBasicMaterial.h"
#import "Octree.h"
#import "Entity.h"
#import "OODescription.h"
#include "oofnd/FileSystem.hpp"
#include "oo_test.hpp"
#include "oo_gl_test_context.hpp"

#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <process.h>
#include <string>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


namespace {

namespace stdfs = std::filesystem;

stdfs::path sRoot;


void WriteText(const stdfs::path &path, const std::string &text)
{
	stdfs::create_directories(path.parent_path());
	OO_CHECK(oo::fs::writeFile(path, oo::Data(text.data(), text.size()), oo::fs::WriteMode::direct).has_value());
}


// A tetrahedron with its right angle at the origin and edges of 10 m, and no TEXTURES section.
const char *const kTetrahedron =
	"NVERTS 4\n"
	"NFACES 4\n"
	"VERTEX\n"
	"0 0 0\n"
	"10 0 0\n"
	"0 10 0\n"
	"0 0 10\n"
	"FACES\n"
	"0 0 0  0 0 -1  3 0 2 1\n"
	"0 0 0  0 -1 0  3 0 1 3\n"
	"0 0 0  -1 0 0  3 0 3 2\n"
	"0 0 0  1 1 1  3 1 2 3\n"
	"END\n";


// The same tetrahedron with explicit vertex normals.
const char *const kTetrahedronWithNormals =
	"NVERTS 4\n"
	"NFACES 4\n"
	"VERTEX\n"
	"0 0 0\n"
	"10 0 0\n"
	"0 10 0\n"
	"0 0 10\n"
	"FACES\n"
	"0 0 0  0 0 -1  3 0 2 1\n"
	"0 0 0  0 -1 0  3 0 1 3\n"
	"0 0 0  -1 0 0  3 0 3 2\n"
	"0 0 0  1 1 1  3 1 2 3\n"
	"NORMALS\n"
	"-1 -1 -1\n"
	"1 0 0\n"
	"0 1 0\n"
	"0 0 1\n"
	"END\n";


// The scratch game folder, made once, before the resource and cache managers exist.
void SetUp()
{
	if (!sRoot.empty())  return;
	sRoot = stdfs::temp_directory_path() / ("oo-test-mesh-" + std::to_string(static_cast<unsigned long>(::_getpid())));
	stdfs::remove_all(sRoot);
	stdfs::create_directories(sRoot / "game");
	OO_CHECK(::_putenv_s("HOMEPATH", (sRoot / "home").string().c_str()) == 0);
	OO_CHECK(::_putenv_s("OO_MANAGEDADDONSDIR", (sRoot / "managed").string().c_str()) == 0);
	OO_CHECK(::_putenv_s("OO_ADDONSEXTRACTDIR", (sRoot / "extract").string().c_str()) == 0);
	stdfs::current_path(sRoot / "game");
	WriteText(sRoot / "game" / "Resources" / "Info-gnustep.plist", "{ CFBundleVersion = \"9.9.9-test\"; }");
	WriteText(sRoot / "game" / "Resources" / "Models" / "tetra.dat", kTetrahedron);
	WriteText(sRoot / "game" / "Resources" / "Models" / "tetra2.dat", kTetrahedron);
	WriteText(sRoot / "game" / "Resources" / "Models" / "tetra3.dat", kTetrahedron);
	WriteText(sRoot / "game" / "Resources" / "Models" / "normals.dat", kTetrahedronWithNormals);
	OO_CHECK(OOTestGLContext());
}


OOMesh *Mesh(const std::string &name, float scale = 1.0f, BOOL cacheWriteable = YES, BOOL smooth = NO, const oo::PList &materials = oo::PList(), const oo::PList &shaders = oo::PList())
{
	return [OOMesh meshWithName:name cacheKey:std::nullopt materialDictionary:materials shadersDictionary:shaders smooth:smooth shaderMacros:oo::PList() shaderBindingTarget:nil scaleFactor:scale cacheWriteable:cacheWriteable];
}


oo::PList CachedPList(const std::string &key, const std::string &cache)
{
	return [[OOCacheManager sharedCache] cxx_pListForKey:key inCache:cache];
}


// The OOCacheManager (Octree) category: free functions on the C++ octree since bead oo-dnbf.
Octree *OctreeForModel(const std::string &key)
{
	return oo::ToObjC(OOCacheManagerOctreeForModel(key));
}


void SetOctreeForModel(Octree *octree, const std::string &key)
{
	OOCacheManagerSetOctree(oo::ToCxx(octree), key);
}


bool Near(double a, double b)
{
	return std::fabs(a - b) < 1e-4 * std::fmax(1.0, std::fabs(b));
}


bool SameVector(Vector a, Vector b)
{
	return Near(a.x, b.x) && Near(a.y, b.y) && Near(a.z, b.z);
}

}	// namespace


OO_TEST(loadsModel)
{
	SetUp();
	@autoreleasepool
	{
		OOMesh *mesh = Mesh("tetra.dat");
		OO_CHECK(mesh != nil);
		if (mesh == nil)  return;
		OO_CHECK([mesh isKindOfClass:[OOMesh class]]);
		OO_CHECK([mesh isKindOfClass:[OODrawable class]]);
		OO_CHECK_EQ([mesh modelName].value_or("<none>"), "tetra.dat");
		OO_CHECK_EQ([mesh vertexCount], 4u);
		OO_CHECK_EQ([mesh faceCount], 4u);
		OO_CHECK(Near([mesh collisionRadius], 10.0));
		// The average of the longest and shortest sides, squared, times the no-draw factor squared.
		OO_CHECK(Near([mesh maxDrawDistance], 100.0 * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR));
		const BoundingBox box = [mesh boundingBox];
		OO_CHECK(SameVector(box.min, make_vector(0, 0, 0)));
		OO_CHECK(SameVector(box.max, make_vector(10, 10, 10)));
		OO_CHECK([mesh hasOpaqueParts]);
		OO_CHECK(![mesh hasTranslucentParts]);
		OO_CHECK(![mesh materials]);
		OO_CHECK(![mesh shaders]);

		const std::string description = oo::DescriptionOf(mesh);
		OO_CHECK(description.starts_with("<OOMesh "));
		OO_CHECK(description.find("{\"tetra.dat\", 4 vertices, 4 faces, radius: 10 m normals: per-face}") != std::string::npos);

		// Binding targets go to the materials; dumping the state only logs.
		[mesh setBindingTarget:nil];
		[mesh dumpSelfState];

#ifndef NDEBUG
		// The placeholder material has no textures; the size counts the vertex and face buffers.
		OO_CHECK([mesh cxx_allTextures].empty());
		OO_CHECK([mesh totalSize] >= 4 * sizeof (Vector) + 4 * sizeof (OOMeshFace));
#endif
	}
}


OO_TEST(dictionariesAndSmoothing)
{
	SetUp();
	@autoreleasepool
	{
		oo::PList::Dict materials;
		materials["other.png"] = oo::PList(oo::PList::Dict{});
		oo::PList::Dict shaders;
		shaders["other.png"] = oo::PList(oo::PList::Dict{});
		OOMesh *mesh = Mesh("tetra2.dat", 1.0f, YES, YES, oo::PList(materials), oo::PList(shaders));
		OO_CHECK(mesh != nil);
		if (mesh == nil)  return;
		OO_CHECK([mesh materials] == oo::PList(materials));
		OO_CHECK([mesh shaders] == oo::PList(shaders));
		OO_CHECK(oo::DescriptionOf(mesh).find("normals: smooth}") != std::string::npos);
	}
}


OO_TEST(scaleAndMissingModel)
{
	SetUp();
	@autoreleasepool
	{
		OOMesh *mesh = Mesh("tetra3.dat", 2.0f, NO);
		OO_CHECK(mesh != nil);
		if (mesh == nil)  return;
		OO_CHECK(Near([mesh collisionRadius], 20.0));
		OO_CHECK(SameVector([mesh boundingBox].max, make_vector(20, 20, 20)));
		// Not cache-writeable: neither the mesh data nor its octree is cached.
		OO_CHECK(!CachedPList("tetra3.dat:0:2.000", "OOMesh"));
		OO_CHECK([mesh octree] != nil);
		OO_CHECK(!CachedPList("tetra3.dat-2.000", "octrees"));

		OO_CHECK(Mesh("no such model.dat") == nil);
	}
}


OO_TEST(caches)
{
	SetUp();
	@autoreleasepool
	{
		OOMesh *mesh = Mesh("tetra.dat");
		OO_CHECK(mesh != nil);
		if (mesh == nil)  return;

		// The OOCacheManager (OOMesh) category: the mesh data, under name:normal mode:scale.
		const oo::PList meshData = CachedPList("tetra.dat:0:1.000", "OOMesh");
		OO_CHECK(meshData.isDict());
		OO_CHECK_EQ(meshData.get<unsigned int>("vertex count"), 4u);
		OO_CHECK_EQ(meshData.get<unsigned int>("face count"), 4u);

		// The octree is made once, and cached under name-scale.
		Octree *octree = [mesh octree];
		OO_CHECK(octree != nil);
		OO_CHECK([mesh octree] == octree);
		const oo::PList octreeData = CachedPList("tetra.dat-1.000", "octrees");
		OO_CHECK(octreeData.isDict());
		OO_CHECK(octreeData == [octree cxx_dictionaryRepresentation]);

		// The OOCacheManager (Octree) category.
		Octree *cached = OctreeForModel("tetra.dat-1.000");
		OO_CHECK(cached != nil);
		OO_CHECK(cached != octree);
		OO_CHECK([cached cxx_dictionaryRepresentation] == octreeData);
		OO_CHECK(OctreeForModel("no such model-1.000") == nil);
		SetOctreeForModel(octree, "copied-1.000");
		OO_CHECK(CachedPList("copied-1.000", "octrees") == octreeData);
		SetOctreeForModel(nil, "nil-1.000");	// does nothing
		OO_CHECK(!CachedPList("nil-1.000", "octrees"));
	}
}


OO_TEST(placeholderMaterial)
{
	SetUp();
	@autoreleasepool
	{
		OOMaterial *placeholder = [OOMesh placeholderMaterial];
		OO_CHECK(placeholder != nil);
		OO_CHECK(dynamic_cast<OOBasicMaterial *>(oo::ToCxx(placeholder)) != nullptr);
		OO_CHECK_EQ([placeholder cxx_name].value_or("<none>"), "/placeholder/");
		OO_CHECK([OOMesh placeholderMaterial] == placeholder);
	}
	@autoreleasepool
	{
		OOMaterial *again = [OOMesh placeholderMaterial];
		OO_CHECK(again != nil);
		OO_CHECK_EQ([again cxx_name].value_or("<none>"), "/placeholder/");
	}
}


OO_TEST(copies)
{
	SetUp();
	@autoreleasepool
	{
		OOMesh *mesh = Mesh("tetra.dat");
		OO_CHECK(mesh != nil);
		if (mesh == nil)  return;

		// Immutable seen from outside: a copy is the mesh itself, retained.
		OOMesh *copy = [mesh copy];
		OO_CHECK(copy == mesh);
		[copy release];

		// A mutable copy is a new mesh with the same model, sharing nothing it can change.
		OOMesh *mutableCopy = [mesh mutableCopy];
		OO_CHECK(mutableCopy != nil);
		OO_CHECK(mutableCopy != mesh);
		OO_CHECK([mutableCopy isKindOfClass:[OOMesh class]]);
		OO_CHECK_EQ([mutableCopy modelName].value_or("<none>"), "tetra.dat");
		OO_CHECK_EQ([mutableCopy vertexCount], 4u);
		OO_CHECK_EQ([mutableCopy faceCount], 4u);
		OO_CHECK(Near([mutableCopy collisionRadius], 10.0));
		OO_CHECK([mutableCopy octree] != nil);
		[mutableCopy release];

		// The subentity bounding box: the vertices moved by the position and rotated.
		const BoundingBox moved = [mesh findSubentityBoundingBoxWithPosition:make_vector(1, 2, 3) rotMatrix:kIdentityMatrix];
		OO_CHECK(SameVector(moved.min, make_vector(1, 2, 3)));
		OO_CHECK(SameVector(moved.max, make_vector(11, 12, 13)));

		// Rescaled: a mutable copy, scaled, with no name (so its octree is not cached).
		OOMesh *rescaled = [mesh meshRescaledBy:3.0f];
		OO_CHECK(rescaled != nil && rescaled != mesh);
		OO_CHECK(Near([rescaled collisionRadius], 30.0));
		OO_CHECK(![rescaled modelName].has_value());
		OO_CHECK(SameVector([rescaled boundingBox].max, make_vector(30, 30, 30)));
		OO_CHECK(Near([mesh collisionRadius], 10.0));
		OO_CHECK(SameVector([mesh boundingBox].max, make_vector(10, 10, 10)));
		// The copy shares the original's vertex buffer, so the original's vertices were scaled too
		// (its radius and bounding box were not recalculated).
		const BoundingBox shared = [mesh findSubentityBoundingBoxWithPosition:make_vector(0, 0, 0) rotMatrix:kIdentityMatrix];
		OO_CHECK(SameVector(shared.max, make_vector(30, 30, 30)));
	}
}


OO_TEST(graphicsResetAfterRelease)
{
	SetUp();
	@autoreleasepool
	{
		OOMesh *mesh = Mesh("tetra.dat");
		OO_CHECK(mesh != nil);
		OOMesh *mutableCopy = [mesh mutableCopy];
		// Both are registered: the reset rebinds their materials.
		[[OOGraphicsResetManager sharedManager] resetGraphicsState];
		OO_CHECK_EQ([mesh vertexCount], 4u);
		OO_CHECK_EQ([mutableCopy vertexCount], 4u);
		[mutableCopy release];
	}
	// Both are gone and unregistered themselves, so the reset does not reach them.
	[[OOGraphicsResetManager sharedManager] resetGraphicsState];
	OO_CHECK(true);
}


// Pins for the later slices (loading, geometry, rendering), taken before they convert.
OO_TEST(laterSlices)
{
	SetUp();
	@autoreleasepool
	{
		// Loading (slice 2): a smooth mesh caches its normals and tangents with normal mode 1.
		OOMesh *smooth = Mesh("tetra2.dat", 1.0f, YES, YES);
		OO_CHECK(smooth != nil);
		const oo::PList smoothData = CachedPList("tetra2.dat:1:1.000", "OOMesh");
		OO_CHECK(smoothData.isDict());
		OO_CHECK_EQ(smoothData.get<unsigned int>("normal mode"), 1u);
		OO_CHECK(smoothData.find("normal data") != nullptr);
		OO_CHECK(smoothData.find("tangent data") != nullptr);
		const oo::PList *keys = smoothData.find("material keys");
		OO_CHECK(keys != nullptr && keys->isArray() && keys->getIf<oo::PList::Array>()->size() == 1);

		// Explicit normals: the normal mode is explicit, cached under the per-face key.
		OOMesh *normals = Mesh("normals.dat");
		OO_CHECK(normals != nil);
		if (normals == nil)  return;
		OO_CHECK(oo::DescriptionOf(normals).find("normals: explicit}") != std::string::npos);
		const oo::PList normalsData = CachedPList("normals.dat:0:1.000", "OOMesh");
		OO_CHECK_EQ(normalsData.get<unsigned int>("normal mode"), 2u);
		OO_CHECK(normalsData.find("normal data") != nullptr);
		// A per-face mesh caches no normals.
		OO_CHECK(CachedPList("tetra.dat:0:1.000", "OOMesh").find("normal data") == nullptr);

		// Geometry (slice 3): the bounding box relative to a position and basis.
		const Vector i = make_vector(1, 0, 0), j = make_vector(0, 1, 0), k = make_vector(0, 0, 1);
		const BoundingBox relative = [normals findBoundingBoxRelativeToPosition:make_vector(0, 0, 0) basis:i :j :k selfPosition:make_vector(1, 2, 3) selfBasis:i :j :k];
		OO_CHECK(SameVector(relative.min, make_vector(1, 2, 3)));
		OO_CHECK(SameVector(relative.max, make_vector(11, 12, 13)));
		// Seen along -x from (5, 0, 0): x is flipped and offset.
		const BoundingBox flipped = [normals findBoundingBoxRelativeToPosition:make_vector(5, 0, 0) basis:make_vector(-1, 0, 0) :j :k selfPosition:make_vector(0, 0, 0) selfBasis:i :j :k];
		OO_CHECK(SameVector(flipped.min, make_vector(-5, 0, 0)));
		OO_CHECK(SameVector(flipped.max, make_vector(5, 10, 10)));
		OO_CHECK([normals octree] != nil);

		// Rendering (slice 4): rebinding the materials keeps the placeholder.
		[normals rebindMaterials];
		OO_CHECK([normals hasOpaqueParts]);
#ifndef NDEBUG
		OO_CHECK([normals cxx_allTextures].empty());
#endif
	}
}


OO_TEST(facadeContract)
{
	SetUp();
	@autoreleasepool
	{
		OOMesh *mesh = Mesh("tetra.dat");
		cxx::OOMesh *cxxMesh = oo::ToCxx(mesh);
		OO_CHECK(cxxMesh != nullptr);
		if (cxxMesh == nullptr)  return;

		// Identity and nil.
		OO_CHECK(oo::ToObjC(cxxMesh) == mesh);
		OO_CHECK(oo::ToCxx(static_cast<OOMesh *>(nil)) == nullptr);
		OO_CHECK(oo::ToObjC(static_cast<cxx::OOMesh *>(nullptr)) == nil);

		// The C++ members answer what the facade does.
		OO_CHECK_EQ(cxxMesh->getVertexCount(), [mesh vertexCount]);
		OO_CHECK_EQ(cxxMesh->getFaceCount(), [mesh faceCount]);
		OO_CHECK(cxxMesh->modelName() == [mesh modelName]);
		OO_CHECK(cxxMesh->getMaterials() == [mesh materials]);
		OO_CHECK(cxxMesh->shaders() == [mesh shaders]);
		OO_CHECK(cxxMesh->hasOpaqueParts());
		OO_CHECK(cxxMesh->descriptionComponents() == std::optional<std::string>("\"tetra.dat\", 4 vertices, 4 faces, radius: 10 m normals: per-face"));
		OO_CHECK(cxxMesh->copyWithZone(nullptr).get() == cxxMesh);	// a copy is the mesh itself

		// Through the root's C++ pointer, the overrides answer (the bounding box is slice 3's,
		// reached through the facade), and the root's crossing gives this facade.
		cxx::OODrawable *drawable = cxxMesh;
		OO_CHECK(Near(drawable->collisionRadius(), 10.0));
		OO_CHECK(Near(drawable->maxDrawDistance(), [mesh maxDrawDistance]));
		OO_CHECK(SameVector(drawable->boundingBox().max, make_vector(10, 10, 10)));
		OO_CHECK(!drawable->hasTranslucentParts());
		OO_CHECK(oo::ToObjC(drawable) == mesh);

		// The C++ factory: a mesh whose facade is an OOMesh; null for a missing model.
		const oo::Ref<cxx::OOMesh> made = cxx::OOMesh::meshWithName("tetra.dat", std::nullopt, oo::PList(), oo::PList(), false, oo::PList(), nil, 2.0f, false);
		OO_CHECK(made.get() != nullptr);
		if (made.get() == nullptr)  return;
		OO_CHECK(Near(made->collisionRadius(), 20.0));
		OOMesh *madeFacade = oo::ToObjC(made);
		OO_CHECK([madeFacade isKindOfClass:[OOMesh class]]);
		OO_CHECK(oo::ToCxx(madeFacade) == made.get());
		OO_CHECK(oo::DescriptionOf(madeFacade).starts_with("<OOMesh "));
		OO_CHECK(cxx::OOMesh::meshWithName("no such model.dat", std::nullopt, oo::PList(), oo::PList(), false, oo::PList(), nil).get() == nullptr);

		// A C++ mesh made bare is the old -init's: no model yet; its facade is still an OOMesh.
		const oo::Ref<cxx::OOMesh> bare = oo::makeRef<cxx::OOMesh>();
		OO_CHECK_EQ(bare->modelName().value_or("<none>"), "No Model");
		OO_CHECK_EQ(bare->getVertexCount(), 0u);
		OOMesh *bareFacade = oo::ToObjC(bare);
		OO_CHECK([bareFacade isKindOfClass:[OOMesh class]]);
		OO_CHECK_EQ([bareFacade vertexCount], 0u);

		// The placeholder material's facade is the C++ material's.
		OO_CHECK(oo::ToCxx([OOMesh placeholderMaterial]) == cxx::OOMesh::placeholderMaterial().get());
	}
}


// Slice 3 (bead oo-9z7x): the geometry members answer what the facade does.
OO_TEST(geometryMembers)
{
	SetUp();
	@autoreleasepool
	{
		OOMesh *mesh = Mesh("tetra.dat");
		cxx::OOMesh *cxxMesh = oo::ToCxx(mesh);
		OO_CHECK(cxxMesh != nullptr);
		if (cxxMesh == nullptr)  return;

		const oo::Ref<cxx::Octree> octree = cxxMesh->getOctree();
		OO_CHECK(octree.get() != nullptr);
		OO_CHECK(cxxMesh->getOctree().get() == octree.get());	// made once
		OO_CHECK(oo::ToCxx([mesh octree]) == octree.get());

		OO_CHECK(SameVector(cxxMesh->boundingBox().max, make_vector(10, 10, 10)));
		const Vector i = make_vector(1, 0, 0), j = make_vector(0, 1, 0), k = make_vector(0, 0, 1);
		const BoundingBox relative = cxxMesh->findBoundingBoxRelativeToPosition(make_vector(0, 0, 0), i, j, k, make_vector(1, 2, 3), i, j, k);
		OO_CHECK(SameVector(relative.max, make_vector(11, 12, 13)));
		const BoundingBox moved = cxxMesh->findSubentityBoundingBoxWithPosition(make_vector(2, 2, 2), kIdentityMatrix);
		OO_CHECK(SameVector(moved.min, make_vector(2, 2, 2)));
		OO_CHECK(SameVector(moved.max, make_vector(12, 12, 12)));

		// Rescaled through the C++ member: a new mesh whose facade is an OOMesh, with no name.
		const oo::Ref<cxx::OOMesh> rescaled = cxxMesh->meshRescaledBy(0.5f);
		OO_CHECK(rescaled.get() != nullptr && rescaled.get() != cxxMesh);
		if (rescaled.get() == nullptr)  return;
		OO_CHECK(Near(rescaled->collisionRadius(), 5.0));
		OO_CHECK(!rescaled->modelName().has_value());
		OO_CHECK([oo::ToObjC(rescaled) isKindOfClass:[OOMesh class]]);
	}
}


// Slice 4 (bead oo-zmix), pinned before it converted: drawing on the hidden GL context, the
// display lists it makes, and a graphics reset between draws.
OO_TEST(rendering)
{
	SetUp();
	@autoreleasepool
	{
		OOMesh *mesh = Mesh("tetra.dat");
		OOMesh *smooth = Mesh("tetra2.dat", 1.0f, YES, YES);
		OO_CHECK(mesh != nil && smooth != nil);
		if (mesh == nil || smooth == nil)  return;
		while (glGetError() != GL_NO_ERROR)  {}

		[mesh renderOpaqueParts];	// makes the display lists
		[mesh renderOpaqueParts];
		[smooth renderOpaqueParts];
		OO_CHECK_EQ(glGetError(), static_cast<GLenum>(GL_NO_ERROR));

		// A reset deletes the display lists and rebinds the materials; the next draw remakes them.
		[[OOGraphicsResetManager sharedManager] resetGraphicsState];
		[mesh renderOpaqueParts];
		OO_CHECK_EQ(glGetError(), static_cast<GLenum>(GL_NO_ERROR));
		OO_CHECK_EQ([mesh vertexCount], 4u);
		OO_CHECK(Near([mesh collisionRadius], 10.0));

		// A mutable copy draws on its own lists.
		OOMesh *copy = [[mesh mutableCopy] autorelease];
		[copy renderOpaqueParts];
		OO_CHECK_EQ(glGetError(), static_cast<GLenum>(GL_NO_ERROR));
	}
}


// Slice 4 (bead oo-zmix): the rendering members, through the C++ mesh.
OO_TEST(renderingMembers)
{
	SetUp();
	@autoreleasepool
	{
		OOMesh *mesh = Mesh("tetra.dat");
		cxx::OOMesh *cxxMesh = oo::ToCxx(mesh);
		OO_CHECK(cxxMesh != nullptr);
		if (cxxMesh == nullptr)  return;
		while (glGetError() != GL_NO_ERROR)  {}

		// Through the root's C++ pointer, as the entities draw.
		cxx::OODrawable *drawable = cxxMesh;
		drawable->renderOpaqueParts();
		OO_CHECK(cxxMesh->listsReady);
		cxxMesh->deleteDisplayLists();
		OO_CHECK(!cxxMesh->listsReady);
		drawable->renderOpaqueParts();
		OO_CHECK_EQ(glGetError(), static_cast<GLenum>(GL_NO_ERROR));

		// The materials: the placeholder's facade, rebound; a reset through the facade.
		cxxMesh->rebindMaterials();
		OO_CHECK(cxxMesh->materials[0] == [OOMesh placeholderMaterial]);
		[mesh resetGraphicsState];
		OO_CHECK(!cxxMesh->listsReady);
		OO_CHECK(cxxMesh->materials[0] == [OOMesh placeholderMaterial]);

		// The buffers: a renamed key, and bytes kept by key.
		cxxMesh->renameTexturesFrom("_oo_placeholder_material", "_oo_placeholder_material");
		OO_CHECK_EQ(cxxMesh->materialKeys[0], "_oo_placeholder_material");
		void *bytes = cxxMesh->allocateBytesWithSize(4, 3, "test bytes");
		OO_CHECK(bytes != nullptr);
		OO_CHECK(cxxMesh->_retainedObjects.find("test bytes") != cxxMesh->_retainedObjects.end());
	}
}


// Slice 2 (bead oo-rdwg): loading and copying are C++ members, and the mesh itself is the
// graphics reset client.
OO_TEST(loadingMembers)
{
	SetUp();
	@autoreleasepool
	{
		const oo::Ref<cxx::OOMesh> mesh = cxx::OOMesh::meshWithName("tetra.dat", std::nullopt, oo::PList(), oo::PList(), false, oo::PList(), nil);
		OO_CHECK(mesh.get() != nullptr);
		if (mesh.get() == nullptr)  return;
		OO_CHECK_EQ(mesh->getVertexCount(), 4u);
		OO_CHECK_EQ(mesh->modelName().value_or("<none>"), "tetra.dat");

		// A mutable copy shares the buffers and is a new mesh.
		const oo::Ref<cxx::OOMesh> copy = mesh->mutableCopyWithZone(nullptr);
		OO_CHECK(copy.get() != nullptr && copy.get() != mesh.get());
		if (copy.get() == nullptr)  return;
		OO_CHECK(copy->_vertices == mesh->_vertices);
		OO_CHECK(copy->octree == mesh->octree);
		OO_CHECK(!copy->listsReady);

		// Both are registered with no facade alive for either: a reset deletes their display lists.
		while (glGetError() != GL_NO_ERROR)  {}
		mesh->renderOpaqueParts();
		copy->renderOpaqueParts();
		OO_CHECK(mesh->listsReady && copy->listsReady);
		cxx::OOGraphicsResetManager::sharedManager()->resetGraphicsState();
		OO_CHECK(!mesh->listsReady && !copy->listsReady);
		OO_CHECK_EQ(glGetError(), static_cast<GLenum>(GL_NO_ERROR));
	}
}


OO_TEST(cleanUp)
{
	stdfs::current_path(stdfs::temp_directory_path());
	std::error_code ignored;
	stdfs::remove_all(sRoot, ignored);
	OO_CHECK(true);
}


OO_TEST_MAIN()
