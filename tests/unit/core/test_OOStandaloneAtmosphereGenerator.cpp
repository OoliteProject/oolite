/*	test_OOStandaloneAtmosphereGenerator.mm
        Unit tests for OOStandaloneAtmosphereGenerator
   (src/Core/Materials/OOStandaloneAtmosphereGenerator.h), the texture generator
   of a planet's cloud layer when its surface is not generated.

        It reads the cloud parameters from the planet's material parameters
   (colours as PList::Object nodes holding OOColors), sizes its texture by the
   detail level (no universe here: the lowest, so 512 x 512, or 512 x 256 with
   3D noise), keys it by its parameters, and fills it with clouds from the
   seed's noise, their alpha scaled by cloud_alpha. It links the whole game but
   main (tests/unit/core/meson.build entry ['*']), on the hidden GL context of
   oo_gl_test_context.hpp. Making a generator and the class methods go through
   the helpers below. The class is a global C++ class. The last test pins the
   C++ API. Run: bash tools/check-core-tests.sh
   test_OOStandaloneAtmosphereGenerator
*/

#include <cstdlib>
#include <cstring>
#include <string>

#include "OOColor.h"
#include "OOConcreteTexture.h"
#include "OODescription.h"
#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#include "OOStandaloneAtmosphereGenerator.h"
#include "oo_gl_test_context.hpp"
#include "oo_test.hpp"

// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

// What an autoreleased texture is: the C++ texture, kept until the current
// autorelease scope drains (oo::autorelease).
static OOTexture* Autoreleased(const std::shared_ptr<OOTexture>& texture) {
  if (texture == nullptr) return nullptr;
  oo::autorelease(std::shared_ptr<OOTexture>(texture));
  return texture.get();
}

namespace {

const RANROTSeed kSeed = {12345, 67890};

// The loaders' sizes come from their one-time set-up, which a path with no
// known extension runs (and then answers nil, reading nothing).
void SetUp() {
  OO_CHECK(OOTestGLContext());
  {
    oo::AutoreleaseScope pool;
    (void)OOTextureLoader::loaderWithPath(std::string("unknown.type"), OOTextureFlags::kNone);
  }
}

oo::PList PlanetInfo(float cloudAlpha, bool perlin3d) {
  return oo::PList(oo::PList::Dict{
      {"cloud_alpha", oo::PList(cloudAlpha)},
      {"cloud_fraction", oo::PList(0.5)},
      {"cloud_color",
       OOColorObjectNode(OOColor::colorWithRed(1.0f, 0.5f, 0.25f, 1.0f).get())},
      {"polar_cloud_color", OOColorObjectNode(OOColor::whiteColor().get())},
      {"perlin_3d", oo::PList(perlin3d)},
  });
}

// --- The only lines a conversion ports
// ----------------------------------------------------------

// The generators made, kept for the test's life (each was autoreleased in its
// case's pool).
std::vector<std::shared_ptr<OOTextureGenerator>> gKeptGenerators;

OOTextureGenerator* Kept(std::shared_ptr<OOTextureGenerator> generator) {
  if (generator != nullptr) gKeptGenerators.push_back(generator);
  return generator.get();
}

// Was [[OOStandaloneAtmosphereGenerator alloc] initWithPlanetInfo:seed:],
// autoreleased, as a generator.
OOTextureGenerator* NewGenerator(const oo::PList& info, RANROTSeed seed) {
  return Kept(
      OOStandaloneAtmosphereGenerator::generatorWithPlanetInfo(info, seed));
}

// Was +generateAtmosphereTexture:withInfo:seed:; the texture (autoreleased), or
// nil where it answered NO.
OOTexture* GenerateAtmosphere(const oo::PList& info, RANROTSeed seed) {
  std::shared_ptr<OOTexture> texture;
  return OOStandaloneAtmosphereGenerator::generateAtmosphereTexture(&texture,
                                                                    info, seed)
             ? Autoreleased(texture)
             : nullptr;
}

// Was +planetTextureWithInfo:seed: (autoreleased).
OOTexture* PlanetTexture(const oo::PList& info, RANROTSeed seed) {
  return Autoreleased(
      OOStandaloneAtmosphereGenerator::planetTextureWithInfo(info, seed));
}

// --------------------------------------------------------------------------------------------------

struct Generated {
  bool ok = false;
  OOPixMap pixMap = kOONullPixMap;
  OOTextureDataFormat format = kOOPixMapInvalidFormat;

  ~Generated() { OOFreePixMap(&pixMap); }

  const uint8_t* bytes() const { return (const uint8_t*)pixMap.pixels; }
  size_t size() const { return (size_t)pixMap.rowBytes * pixMap.height; }
};

void Generate(OOTextureGenerator* generator, Generated& generated) {
  OO_CHECK(generator->enqueue());
  generated.ok =
      generator->getResult(&generated.pixMap, &generated.format, NULL, NULL);
}

void ClearCache() {
  {
    oo::AutoreleaseScope scope;
    OOTexture::clearCache();
  }
}

}  // namespace

OO_TEST(settings) {
  SetUp();
  {
    oo::AutoreleaseScope pool;
    OOTextureGenerator* generator =
        NewGenerator(PlanetInfo(0.75f, false), kSeed);
    OO_CHECK(generator != nullptr &&
             (dynamic_cast<OOTextureGenerator*>(generator) != nullptr));
    OO_CHECK(generator->textureOptions() ==
             (OOTextureFlags::kMinFilterLinear | OOTextureFlags::kMagFilterLinear |
              OOTextureFlags::kRepeatS | OOTextureFlags::kNoShrink));
    OO_CHECK(generator->path().value_or("").starts_with(
        "OOStandaloneAtmosphereTexture@"));

    // Keyed by the scale (512: 2), the size (not known until it loads), the
    // seed and the clouds; the air colour is never set.
    const std::string key = generator->cacheKey().value_or("");
    OO_CHECK(
        key.starts_with("OOStandaloneAtmosphereGenerator-@2\n0,0/12345,67890/"
                        "0.750000/0.500000/0.000000,0.000000,0.000000/"));
    OO_CHECK(NewGenerator(PlanetInfo(0.75f, false), kSeed)->cacheKey() ==
             std::optional<std::string>(key));
    OO_CHECK(NewGenerator(PlanetInfo(0.75f, false), (RANROTSeed){1, 2})
                 ->cacheKey() != std::optional<std::string>(key));

    OO_CHECK(generator->description().find("{seed: 12345,67890}") !=
             std::string::npos);
  }
}

OO_TEST(generatesClouds) {
  SetUp();
  {
    oo::AutoreleaseScope pool;
    Generated a, b;
    Generate(NewGenerator(PlanetInfo(1.0f, false), kSeed), a);
    OO_CHECK(a.ok && a.format == kOOPixMapRGBA && a.pixMap.width == 512 &&
             a.pixMap.height == 512 && a.pixMap.rowBytes == 2048);

    // The same seed and parameters give the same clouds.
    Generate(NewGenerator(PlanetInfo(1.0f, false), kSeed), b);
    OO_CHECK(b.ok && b.size() == a.size() &&
             std::memcmp(a.bytes(), b.bytes(), a.size()) == 0);

    // Some cloud, some clear sky.
    bool someCloud = false, someClear = false;
    for (size_t i = 3; i < a.size(); i += 4) {
      if (a.bytes()[i] > 128) someCloud = true;
      if (a.bytes()[i] < 128) someClear = true;
    }
    OO_CHECK(someCloud && someClear);

    // No cloud alpha: transparent everywhere.
    Generated clear;
    Generate(NewGenerator(PlanetInfo(0.0f, false), kSeed), clear);
    bool allClear = clear.ok;
    for (size_t i = 3; i < clear.size(); i += 4)
      allClear = allClear && clear.bytes()[i] == 0;
    OO_CHECK(allClear);

    // 3D noise: twice as wide as high.
    Generated wide;
    Generate(NewGenerator(PlanetInfo(1.0f, true), kSeed), wide);
    OO_CHECK(wide.ok && wide.pixMap.width == 512 && wide.pixMap.height == 256);
  }
}

OO_TEST(textures) {
  SetUp();
  {
    oo::AutoreleaseScope pool;
    OOTexture* atmosphere = GenerateAtmosphere(PlanetInfo(1.0f, false), kSeed);
    OO_CHECK((dynamic_cast<OOConcreteTexture*>(atmosphere) != nullptr));
    atmosphere->ensureFinishedLoading();
    OO_CHECK(atmosphere->isFinishedLoading() &&
             atmosphere->dimensions().width == 512 &&
             atmosphere->dimensions().height == 512);

    OOTexture* texture =
        PlanetTexture(PlanetInfo(1.0f, true), (RANROTSeed){3, 4});
    OO_CHECK((dynamic_cast<OOConcreteTexture*>(texture) != nullptr));
    texture->ensureFinishedLoading();
    OO_CHECK(texture->dimensions().width == 512 &&
             texture->dimensions().height == 256);
  }
  ClearCache();
}

// --- The C++ API (after the conversion)
// --------------------------------------------------------

OO_TEST(cxxApi) {
  SetUp();
  {
    oo::AutoreleaseScope pool;
    const std::shared_ptr<OOStandaloneAtmosphereGenerator> generator =
        OOStandaloneAtmosphereGenerator::generatorWithPlanetInfo(
            PlanetInfo(1.0f, false), kSeed);
    OO_CHECK(generator &&
             generator->textureOptions() ==
                 (OOTextureFlags::kMinFilterLinear | OOTextureFlags::kMagFilterLinear |
                  OOTextureFlags::kRepeatS | OOTextureFlags::kNoShrink));
    OO_CHECK(generator->descriptionComponents() ==
             std::optional<std::string>("seed: 12345,67890"));
    OO_CHECK(generator->cacheKey().value_or("").starts_with(
        "OOStandaloneAtmosphereGenerator-@2\n"));

    // Loading fills the root's state; the old -getResult:format:width:height:
    // answers the result.
    generator->loadTexture();
    OO_CHECK(generator->_width == 512 && generator->_height == 512 &&
             generator->_data != nullptr);
    OOPixMap pixMap = kOONullPixMap;
    OOTextureDataFormat format = kOOPixMapInvalidFormat;
    generator->completeAsyncTask();
    OO_CHECK(generator->getResultFormatWidthHeight(&pixMap, &format, nullptr,
                                                   nullptr) &&
             format == kOOPixMapRGBA && pixMap.width == 512);
    OOFreePixMap(&pixMap);

    std::shared_ptr<OOTexture> texture;
    OO_CHECK(OOStandaloneAtmosphereGenerator::generateAtmosphereTexture(
                 &texture, PlanetInfo(1.0f, false), (RANROTSeed){9, 9}) &&
             (dynamic_cast<OOConcreteTexture*>(texture.get()) != nullptr));
    OO_CHECK((dynamic_cast<OOConcreteTexture*>(
                  OOStandaloneAtmosphereGenerator::planetTextureWithInfo(
                      PlanetInfo(1.0f, false), (RANROTSeed){9, 10})
                      .get()) != nullptr));
  }
  ClearCache();
}

OO_TEST_MAIN()
