/*	test_OOPlanetTextureGenerator.mm
	Unit tests for OOPlanetTextureGenerator (src/Core/Materials/OOPlanetTextureGenerator.h), the
	texture generator of a planet's surface, with the two helper generators private to its file
	that hand on the normal map and the atmosphere it makes at the same time: bead oo-kyje (Phase 3,
	house style of proposed ADR-0056; a leaf of the texture generators, amendments oo-zl36, oo-rr2x
	and oo-kvqq).

	It reads the planet's parameters (colours as PList::Object nodes holding OOColors), sizes its
	texture by the detail level (no universe here: the lowest, so 512 x 512, or 512 x 256 with 3D
	noise), keys it by its parameters and by which helpers it feeds, and fills it from the seed's
	noise; the class methods make the textures, the surface's last so that it is queued once the
	helpers are. It links the whole game but main (tests/unit/core/meson.build entry ['*']), on the
	hidden GL context of oo_gl_test_context.hpp. The expectations were written against the
	Objective-C API and run on the unconverted class first. Making a generator and the class methods
	go through the helpers below, the only lines the conversion ported (amendment oo-bj8 item 11):
	the class is now a global C++ class with no facade of its own (bead oo-9ht.118 deleted the
	generators' facade its generators crossed as; the crossing check went with it). The last test
	pins the C++ API.
	Run: bash tools/check-core-tests.sh test_OOPlanetTextureGenerator
*/

#include "OOPlanetTextureGenerator.h"
#include "OOConcreteTexture.h"
#include "OOColor.h"
#include "OODescription.h"
#include "OOObjCPList.h"

#include "oo_test.hpp"
#include "oo_gl_test_context.hpp"

#include <cstdlib>
#include <cstring>
#include <string>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif



// What an autoreleased Objective-C texture was (bead oo-9ht.99 deleted the facade): the C++
// texture, kept until the current autorelease scope drains (oo::autorelease; an Objective-C
// keeper object until bead oo-4aq6a.2).
static OOTexture *Autoreleased(const oo::Ref<OOTexture> &texture)
{
	if (texture == nullptr)  return nullptr;
	oo::autorelease(oo::Ref<OOTexture>(texture));
	return texture.get();
}


namespace {

// The loaders' sizes come from their one-time set-up, which a path with no known extension runs
// (and then answers nil, reading nothing).
void SetUp()
{
	OO_CHECK(OOTestGLContext());
	{
		oo::AutoreleaseScope pool;
		(void)OOTextureLoader::loaderWithPath(std::string("unknown.type"), 0);
	}
}


oo::PList PlanetInfo(bool perlin3d)
{
	return oo::PList(oo::PList::Dict{
		{ "land_fraction", oo::PList(0.25) },
		{ "polar_fraction", oo::PList(0.05) },
		{ "land_color", OOColorObjectNode(OOColor::colorWithRed(0.25f, 0.5f, 0.125f, 1.0f).get()) },
		{ "sea_color", OOColorObjectNode(OOColor::blueColor().get()) },
		{ "polar_land_color", OOColorObjectNode(OOColor::whiteColor().get()) },
		{ "polar_sea_color", OOColorObjectNode(OOColor::cyanColor().get()) },
		{ "cloud_alpha", oo::PList(1.0) },
		{ "cloud_fraction", oo::PList(0.5) },
		{ "cloud_color", OOColorObjectNode(OOColor::whiteColor().get()) },
		{ "polar_cloud_color", OOColorObjectNode(OOColor::lightGrayColor().get()) },
		{ "perlin_3d", oo::PList(perlin3d) },
	});
}


// --- The only lines a conversion ports ----------------------------------------------------------

// The generators made, kept for the test's life (each was autoreleased in its case's pool).
std::vector<oo::Ref<OOTextureGenerator>> gKeptGenerators;


OOTextureGenerator *Kept(oo::Ref<OOTextureGenerator> generator)
{
	if (generator != nullptr)  gKeptGenerators.push_back(generator);
	return generator.get();
}


// Was [[OOPlanetTextureGenerator alloc] initWithPlanetInfo:seed:], autoreleased, as a generator.
OOTextureGenerator *NewGenerator(const oo::PList &info, RANROTSeed seed)
{
	return Kept(OOPlanetTextureGenerator::generatorWithPlanetInfo(info, seed));
}


// Was +planetTextureWithInfo:seed: (autoreleased).
OOTexture *PlanetTexture(const oo::PList &info, RANROTSeed seed)
{
	return Autoreleased(OOPlanetTextureGenerator::planetTextureWithInfo(info, seed));
}




// The three +generatePlanetTexture:... methods: what they answered, and the textures they wrote.
struct Textures
{
	bool		ok = false;
	OOTexture	*texture = nil, *secondary = nil, *atmosphere = nil;
};


Textures GenerateWithAtmosphere(const oo::PList &info, RANROTSeed seed)
{
	Textures t;
	oo::Ref<OOTexture> texture, atmosphere;
	t.ok = OOPlanetTextureGenerator::generatePlanetTextureAndAtmosphere(&texture, &atmosphere, info, seed);
	t.texture = Autoreleased(texture);
	t.atmosphere = Autoreleased(atmosphere);
	return t;
}


Textures GenerateWithSecondary(const oo::PList &info, RANROTSeed seed, bool secondary)
{
	Textures t;
	oo::Ref<OOTexture> texture, secondaryTexture;
	t.ok = OOPlanetTextureGenerator::generatePlanetTexture(&texture, secondary ? &secondaryTexture : NULL, info, seed);
	t.texture = Autoreleased(texture);
	t.secondary = Autoreleased(secondaryTexture);
	return t;
}


Textures GenerateAll(const oo::PList &info, RANROTSeed seed, bool secondary)
{
	Textures t;
	oo::Ref<OOTexture> texture, secondaryTexture, atmosphere;
	t.ok = OOPlanetTextureGenerator::generatePlanetTexture(&texture, secondary ? &secondaryTexture : NULL, &atmosphere, info, seed);
	t.texture = Autoreleased(texture);
	t.secondary = Autoreleased(secondaryTexture);
	t.atmosphere = Autoreleased(atmosphere);
	return t;
}

// --------------------------------------------------------------------------------------------------


struct Generated
{
	bool				ok = false;
	OOPixMap			pixMap = kOONullPixMap;
	OOTextureDataFormat	format = kOOPixMapInvalidFormat;

	~Generated()	{ OOFreePixMap(&pixMap); }

	const uint8_t *bytes() const	{ return (const uint8_t *)pixMap.pixels; }
	size_t size() const				{ return (size_t)pixMap.rowBytes * pixMap.height; }
};


void Generate(OOTextureGenerator *generator, Generated &generated)
{
	OO_CHECK(generator->enqueue());
	generated.ok = generator->getResult(&generated.pixMap, &generated.format, NULL, NULL);
}


// A texture loaded: its key starts with the prefix, and it has the size.
bool Loaded(OOTexture *texture, const std::string &keyPrefix, unsigned width, unsigned height)
{
	if (!(dynamic_cast<OOConcreteTexture *>(texture) != nullptr))  return false;
	texture->ensureFinishedLoading();
	return texture->isFinishedLoading() && texture->cacheKey().value_or("").starts_with(keyPrefix)
		&& texture->dimensions().width == width && texture->dimensions().height == height;
}


void ClearCache()
{
	{
		oo::AutoreleaseScope scope;
		OOTexture::clearCache();
	}
}

}	// namespace


OO_TEST(settings)
{
	SetUp();
	{
		oo::AutoreleaseScope pool;
		OOTextureGenerator *generator = NewGenerator(PlanetInfo(false), (RANROTSeed){ 12345, 67890 });
		OO_CHECK(generator != nil && (dynamic_cast<OOTextureGenerator *>(generator) != nullptr));
		OO_CHECK(generator->textureOptions() == (kOOTextureMinFilterLinear | kOOTextureMagFilterLinear | kOOTextureRepeatS | kOOTextureNoShrink));
		OO_CHECK(generator->path().value_or("").starts_with("OOPlanetTexture@"));

		// Keyed by what it feeds (nothing yet: baked), the scale (512: 2), the size (not known until
		// it loads), the land fraction, the seed and the colours.
		const std::string key = generator->cacheKey().value_or("");
		OO_CHECK(key.starts_with("OOPlanetTextureGenerator-diffuse-baked@2\n0,0/0.25/12345,67890/"));
		OO_CHECK(generator->description().find("{seed: 12345,67890 land: 0.25}") != std::string::npos);
	}
}


OO_TEST(generatesTheSurface)
{
	SetUp();
	{
		oo::AutoreleaseScope pool;
		Generated a, b;
		Generate(NewGenerator(PlanetInfo(false), (RANROTSeed){ 1, 1 }), a);
		OO_CHECK(a.ok && a.format == kOOPixMapRGBA && a.pixMap.width == 512 && a.pixMap.height == 512 && a.pixMap.rowBytes == 2048);

		// The same seed and parameters give the same planet.
		Generate(NewGenerator(PlanetInfo(false), (RANROTSeed){ 1, 1 }), b);
		OO_CHECK(b.ok && b.size() == a.size() && std::memcmp(a.bytes(), b.bytes(), a.size()) == 0);

		// 3D noise: twice as wide as high.
		Generated wide;
		Generate(NewGenerator(PlanetInfo(true), (RANROTSeed){ 1, 1 }), wide);
		OO_CHECK(wide.ok && wide.pixMap.width == 512 && wide.pixMap.height == 256);
	}
}


OO_TEST(planetTexture)
{
	SetUp();
	{
		oo::AutoreleaseScope pool;
		OO_CHECK(Loaded(PlanetTexture(PlanetInfo(false), (RANROTSeed){ 2, 2 }), "OOPlanetTextureGenerator-diffuse-baked@2\n", 512, 512));
	}
	ClearCache();
}


OO_TEST(withSecondaryTexture)
{
	SetUp();
	{
		oo::AutoreleaseScope pool;
		// The normal map is filled when the surface is generated, so the surface is loaded first
		// (unlike the atmosphere's, the normal map's generator does not wait for the surface's).
		Textures t = GenerateWithSecondary(PlanetInfo(false), (RANROTSeed){ 3, 3 }, true);
		OO_CHECK(t.ok && t.atmosphere == nil);
		OO_CHECK(Loaded(t.texture, "OOPlanetTextureGenerator-diffuse-raw@2\n", 512, 512));
		OO_CHECK(Loaded(t.secondary, "OOPlanetTextureGenerator-normal@2\n", 512, 512));

		Textures alone = GenerateWithSecondary(PlanetInfo(false), (RANROTSeed){ 4, 4 }, false);
		OO_CHECK(alone.ok && alone.secondary == nil);
		OO_CHECK(Loaded(alone.texture, "OOPlanetTextureGenerator-diffuse-baked@2\n", 512, 512));
	}
	ClearCache();
}


OO_TEST(withAtmosphere)
{
	SetUp();
	{
		oo::AutoreleaseScope pool;
		Textures t = GenerateWithAtmosphere(PlanetInfo(false), (RANROTSeed){ 5, 5 });
		OO_CHECK(t.ok && t.secondary == nil);
		OO_CHECK(Loaded(t.texture, "OOPlanetTextureGenerator-diffuse-baked-atmo@2\n", 512, 512));
		OO_CHECK(Loaded(t.atmosphere, "OOPlanetTextureGenerator-atmo@2\n", 512, 512));

		Textures all = GenerateAll(PlanetInfo(false), (RANROTSeed){ 6, 6 }, true);
		OO_CHECK(all.ok);
		OO_CHECK(Loaded(all.texture, "OOPlanetTextureGenerator-diffuse-raw-atmo@2\n", 512, 512));
		OO_CHECK(Loaded(all.secondary, "OOPlanetTextureGenerator-normal@2\n", 512, 512));
		OO_CHECK(Loaded(all.atmosphere, "OOPlanetTextureGenerator-atmo@2\n", 512, 512));

		Textures noSecondary = GenerateAll(PlanetInfo(false), (RANROTSeed){ 7, 7 }, false);
		OO_CHECK(noSecondary.ok && noSecondary.secondary == nil);
		OO_CHECK(Loaded(noSecondary.atmosphere, "OOPlanetTextureGenerator-atmo@2\n", 512, 512));
		OO_CHECK(Loaded(noSecondary.texture, "OOPlanetTextureGenerator-diffuse-baked-atmo@2\n", 512, 512));
	}
	ClearCache();
}


// --- The C++ API (after the conversion) --------------------------------------------------------

OO_TEST(cxxApi)
{
	SetUp();
	{
		oo::AutoreleaseScope pool;
		const oo::Ref<OOPlanetTextureGenerator> generator = OOPlanetTextureGenerator::generatorWithPlanetInfo(PlanetInfo(false), (RANROTSeed){ 12345, 67890 });
		OO_CHECK(generator && generator->textureOptions() == (kOOTextureMinFilterLinear | kOOTextureMagFilterLinear | kOOTextureRepeatS | kOOTextureNoShrink));
		OO_CHECK(generator->descriptionComponents() == std::optional<std::string>("seed: 12345,67890 land: 0.25"));
		OO_CHECK(generator->cacheKey().value_or("").starts_with("OOPlanetTextureGenerator-diffuse-baked@2\n"));

		// Loading fills the root's state; the old -getResult:format:width:height: answers the result.
		generator->loadTexture();
		OO_CHECK(generator->_width == 512 && generator->_height == 512 && generator->_data != nullptr);
		OOPixMap pixMap = kOONullPixMap;
		OOTextureDataFormat format = kOOPixMapInvalidFormat;
		generator->completeAsyncTask();
		OO_CHECK(generator->getResultFormatWidthHeight(&pixMap, &format, nullptr, nullptr) && format == kOOPixMapRGBA && pixMap.width == 512);
		OOFreePixMap(&pixMap);

		// The helper generators cross as OOTextureGenerators, named in their descriptions.
		Textures all = GenerateAll(PlanetInfo(false), (RANROTSeed){ 8, 8 }, true);
		OO_CHECK(all.ok && Loaded(all.texture, "OOPlanetTextureGenerator-diffuse-raw-atmo@2\n", 512, 512));
		OO_CHECK(Loaded(all.secondary, "OOPlanetTextureGenerator-normal@2\n", 512, 512) && Loaded(all.atmosphere, "OOPlanetTextureGenerator-atmo@2\n", 512, 512));
	}
	ClearCache();
}


OO_TEST_MAIN()
