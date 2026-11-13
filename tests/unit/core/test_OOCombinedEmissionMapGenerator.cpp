/*	test_OOCombinedEmissionMapGenerator.mm
	Unit tests for OOCombinedEmissionMapGenerator (src/Core/Materials/OOCombinedEmissionMapGenerator.h),
	the texture generator that bakes a material's emission map, illumination map, diffuse map and
	their modulating colours into one emission texture.

	It answers nil when there is nothing to bake, takes its texture options, anisotropy and LOD
	bias from the options specifier, keys its texture by what it combines, reads its source maps
	when it is made (unless a texture of its key exists), and bakes them on the work thread:
	emission tinted by its colour, plus illumination tinted by its colour and modulated by the
	diffuse map. Its source maps are PNGs the test writes under a scratch Resources/Textures, the
	current directory and HOMEPATH both pointed at the scratch folder first and the resource
	manager in strict mode (the built-in Resources alone), so no game resource and no add-on is
	read. It links the whole game but main (tests/unit/core/meson.build entry ['*']), on the
	hidden GL context of oo_gl_test_context.hpp. The generators are made by the C++ factories
	and asked directly. The last test pins the C++ API.
	Run: bash meson test -C build/meson_test test_OOCombinedEmissionMapGenerator
*/

#include <png.h>
#include <process.h>
#include <stdlib.h>

#include <cstdlib>
#include <filesystem>
#include <string>
#include <vector>

#include "OOColor.h"
#include "OOCombinedEmissionMapGenerator.h"
#include "OOConcreteTexture.h"
#include "OOTextureInternal.h"
#include "ResourceManager.h"
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

namespace stdfs = std::filesystem;

stdfs::path sRoot;

// A size x size PNG of the given libpng format, every byte `fill`, as
// Resources/Textures/name.
bool WritePNG(const char* name, uint32_t size, png_uint_32 format,
              uint8_t fill) {
  png_image image = {};
  image.version = PNG_IMAGE_VERSION;
  image.width = size;
  image.height = size;
  image.format = format;
  std::vector<uint8_t> bytes(PNG_IMAGE_SIZE(image), fill);
  const std::string path =
      (sRoot / "Resources" / "Textures" / name).generic_string();
  const bool written = png_image_write_to_file(&image, path.c_str(), 0,
                                               bytes.data(), 0, nullptr) != 0;
  png_image_free(&image);
  return written;
}

/*	The scratch folder (before the resource manager's first use), its maps,
   and the loaders' one-time set-up (a path with no known extension runs it, and
   answers nil). e.png: RGB 200; i.png: grey 100; d.png: RGB 128; c.png: RGBA
   200 (emission .rgb, illumination .a).
*/
void SetUp() {
  OO_CHECK(OOTestGLContext());
  if (sRoot.empty()) {
    sRoot = stdfs::temp_directory_path() /
            ("oo-test-emission-" +
             std::to_string(static_cast<unsigned long>(::_getpid())));
    stdfs::remove_all(sRoot);
    stdfs::create_directories(sRoot / "Resources" / "Textures");
    OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
    stdfs::current_path(sRoot);
    OO_CHECK(WritePNG("e.png", 8, PNG_FORMAT_RGB, 200));
    OO_CHECK(WritePNG("i.png", 8, PNG_FORMAT_GRAY, 100));
    OO_CHECK(WritePNG("d.png", 8, PNG_FORMAT_RGB, 128));
    OO_CHECK(WritePNG("c.png", 8, PNG_FORMAT_RGBA, 200));
    ResourceManager::setUseAddOns(std::string(
        SCENARIO_OXP_DEFINITION_NONE));  // strict: the built-in Resources alone
  }
  {
    oo::AutoreleaseScope pool;
    (void)OOTextureLoader::loaderWithPath(std::string("unknown.type"), OOTextureFlags::kNone);
  }
}

// The generators made, kept for the test's life (each was autoreleased in its
// case's pool).
std::vector<std::shared_ptr<OOTextureGenerator>> gKeptGenerators;

OOTextureGenerator* Kept(std::shared_ptr<OOTextureGenerator> generator) {
  if (generator != nullptr) gKeptGenerators.push_back(generator);
  return generator.get();
}

// OOCombinedEmissionMapGenerator::generatorWithEmissionMapSpec(), kept (it was
// autoreleased; null for null), as the facade initialiser
// initWithEmissionMapSpec:... answered it.
OOTextureGenerator* NewGenerator(const oo::PList& emission,
                                 OOColor* emissionColor, OOTexture* diffuseMap,
                                 OOColor* diffuseColor,
                                 const oo::PList& illumination,
                                 OOColor* illuminationColor,
                                 const oo::PList& options) {
  return Kept(OOCombinedEmissionMapGenerator::generatorWithEmissionMapSpec(
      emission, emissionColor, diffuseMap, diffuseColor, illumination,
      illuminationColor, options));
}

// OOCombinedEmissionMapGenerator::generatorWithEmissionAndIlluminationMapSpec(),
// likewise.
OOTextureGenerator* NewCombinedGenerator(const oo::PList& map,
                                         OOTexture* diffuseMap,
                                         OOColor* diffuseColor,
                                         OOColor* emissionColor,
                                         OOColor* illuminationColor) {
  return Kept(OOCombinedEmissionMapGenerator::
                  generatorWithEmissionAndIlluminationMapSpec(
                      map, diffuseMap, diffuseColor, emissionColor,
                      illuminationColor, map));
}

// A map named by a string spec, as the generator keys it (it sets extra_shrink
// only in a dictionary).
std::string KeyOf(const char* name) {
  return OOTextureCacheKeyForSpecifier(oo::PList(name));
}

struct Baked {
  bool ok = false;
  OOPixMap pixMap = kOONullPixMap;
  OOTextureDataFormat format = kOOPixMapInvalidFormat;

  ~Baked() { OOFreePixMap(&pixMap); }

  const uint8_t* pixel() const { return (const uint8_t*)pixMap.pixels; }
};

void Bake(OOTextureGenerator* generator, Baked& baked) {
  OO_CHECK(generator->enqueue());
  baked.ok = generator->getResult(&baked.pixMap, &baked.format, NULL, NULL);
}

// The diffuse map: d.png, loaded.
OOTexture* DiffuseMap() {
  OOTexture* texture = Autoreleased(OOTexture::textureWithName(
      std::string("d.png"), std::string("Textures")));
  texture->ensureFinishedLoading();
  return texture;
}

void ClearCache() {
  {
    oo::AutoreleaseScope scope;
    OOTexture::clearCache();
  }
}

}  // namespace

OO_TEST(nothingToBake) {
  SetUp();
  {
    oo::AutoreleaseScope pool;
    OO_CHECK(NewGenerator(oo::PList(), nullptr, nullptr, nullptr, oo::PList(),
                          OOColor::redColor().get(),
                          oo::PList("e.png")) == nullptr);
    OO_CHECK(NewCombinedGenerator(oo::PList(), nullptr, nullptr, nullptr, nullptr) == nullptr);
  }
}

OO_TEST(settingsFromTheOptionsSpecifier) {
  SetUp();
  {
    oo::AutoreleaseScope pool;
    const oo::PList options(
        oo::PList::Dict{{"name", oo::PList("e.png")},
                        {"min_filter", oo::PList("nearest")},
                        {"anisotropy", oo::PList(0.5)},
                        {"texture_LOD_bias", oo::PList(-0.25)}});
    OOTextureFlags expected = OOTextureFlags::kNone;
    float anisotropy = 0, lodBias = 0;
    OO_CHECK(OOInterpretTextureSpecifier(options, NULL, &expected,
                                             &anisotropy, &lodBias, true));
    OOTextureGenerator* generator = NewGenerator(
        oo::PList("e.png"), nullptr, nullptr, nullptr, oo::PList(), nullptr, options);
    OO_CHECK(generator != nullptr &&
             (dynamic_cast<OOTextureGenerator*>(generator) != nullptr));
    OO_CHECK(generator->textureOptions() ==
             OOApplyTextureOptionDefaults(expected));
    OO_CHECK(generator->anisotropy() == anisotropy &&
             generator->lodBias() == lodBias);
    OO_CHECK(generator->path() ==
             std::optional<std::string>("<generated emission map>"));
  }
}

OO_TEST(cacheKeys) {
  SetUp();
  {
    oo::AutoreleaseScope pool;
    std::shared_ptr<OOColor> red = OOColor::redColor();
    const std::string redRGBA = red->rgbaDescription().value_or("");

    OO_CHECK(NewGenerator(oo::PList("e.png"), red.get(), nullptr, nullptr, oo::PList(),
                          nullptr, oo::PList("e.png"))
                 ->cacheKey() ==
             std::optional<std::string>("emission map;emission:{" +
                                        KeyOf("e.png") + "}*" + redRGBA + ";"));
    // A white colour is no colour; the diffuse map is only used with
    // illumination. The generator before the expected key, the order Clang
    // evaluates the two sides of ==.
    const std::optional<std::string> whiteKey =
        NewGenerator(oo::PList("e.png"), OOColor::whiteColor().get(),
                     DiffuseMap(), nullptr, oo::PList(), nullptr, oo::PList("e.png"))
            ->cacheKey();
    OO_CHECK(whiteKey == std::optional<std::string>("emission map;emission:{" +
                                                    KeyOf("e.png") + "};"));

    OOTexture* diffuse = DiffuseMap();
    const std::string diffuseKey = diffuse->cacheKey().value_or("");
    OO_CHECK(!diffuseKey.empty());
    // The illumination colour is the diffuse colour times the illumination
    // colour.
    OO_CHECK(NewGenerator(oo::PList(), nullptr, diffuse, red.get(),
                          oo::PList("i.png"), OOColor::yellowColor().get(),
                          oo::PList("i.png"))
                 ->cacheKey() ==
             std::optional<std::string>("illumination map;illumination:{" +
                                        KeyOf("i.png") + "}*{" + diffuseKey +
                                        "}*" + redRGBA + ";"));
    OO_CHECK(NewGenerator(oo::PList("e.png"), nullptr, nullptr, nullptr, oo::PList("i.png"),
                          nullptr, oo::PList("e.png"))
                 ->cacheKey() ==
             std::optional<std::string>(
                 "merged emission and illumination map;emission:{" +
                 KeyOf("e.png") + "};illumination:{" + KeyOf("i.png") +
                 "}*{};"));
    OO_CHECK(NewCombinedGenerator(oo::PList("c.png"), diffuse, nullptr, nullptr, nullptr)
                 ->cacheKey() ==
             std::optional<std::string>(
                 "combined emission and illumination map;emission:{" +
                 KeyOf("c.png") + "};illumination:{" + KeyOf("c.png") +
                 ":a}*{" + diffuseKey + "};"));
  }
  ClearCache();
}

OO_TEST(bakesTheEmissionMap) {
  SetUp();
  {
    oo::AutoreleaseScope pool;
    // Emission alone, tinted (0.5, 1, 0.25).
    Baked baked;
    Bake(NewGenerator(oo::PList("e.png"),
                      OOColor::colorWithRed(0.5f, 1.0f, 0.25f, 1.0f).get(), nullptr,
                      nullptr, oo::PList(), nullptr, oo::PList("e.png")),
         baked);
    OO_CHECK(baked.ok && baked.format == kOOPixMapRGBA &&
             baked.pixMap.width > 0 &&
             baked.pixMap.width == baked.pixMap.height);
    OO_CHECK(baked.pixel()[0] == 100 && baked.pixel()[1] == 200 &&
             baked.pixel()[2] == 50);
  }
  ClearCache();
}

OO_TEST(bakesTheIlluminationMap) {
  SetUp();
  {
    oo::AutoreleaseScope pool;
    // Illumination alone: grey 100 x the diffuse map's 128 (x a white colour,
    // which is none).
    Baked illumination;
    Bake(NewGenerator(oo::PList(), nullptr, DiffuseMap(), nullptr, oo::PList("i.png"),
                      nullptr, oo::PList("i.png")),
         illumination);
    OO_CHECK(illumination.ok && illumination.pixMap.width > 0);
    const uint8_t lit = illumination.pixel()[0];
    OO_CHECK(lit == 50 || lit == 51);

    // Emission plus illumination: added.
    Baked merged;
    Bake(NewGenerator(oo::PList("e.png"), nullptr, DiffuseMap(), nullptr,
                      oo::PList("i.png"), nullptr, oo::PList("e.png")),
         merged);
    OO_CHECK(merged.ok && merged.format == kOOPixMapRGBA);
    OO_CHECK(merged.pixel()[0] == 200 + lit);

    // One map: its alpha (200) is the illumination, x the diffuse map; its
    // colour the emission.
    Baked combined;
    Bake(NewCombinedGenerator(oo::PList("c.png"), DiffuseMap(), nullptr, nullptr, nullptr),
         combined);
    OO_CHECK(combined.ok && combined.format == kOOPixMapRGBA);
    OO_CHECK(combined.pixel()[0] == 255);  // 200 + ~100, saturated
  }
  ClearCache();
}

OO_TEST(aMissingMap) {
  SetUp();
  {
    oo::AutoreleaseScope pool;
    // Made (the spec names a map), but there is nothing to bake.
    OOTextureGenerator* generator =
        NewGenerator(oo::PList("missing.png"), nullptr, nullptr, nullptr, oo::PList(), nullptr,
                     oo::PList("missing.png"));
    OO_CHECK(generator != nullptr);
    Baked baked;
    Bake(generator, baked);
    OO_CHECK(!baked.ok && baked.pixMap.pixels == NULL);
  }
}

OO_TEST(aTextureOfTheGenerator) {
  SetUp();
  {
    oo::AutoreleaseScope pool;
    OOTexture* texture = Autoreleased(OOTexture::textureWithGenerator(
        NewGenerator(oo::PList("e.png"), OOColor::redColor().get(), nullptr, nullptr,
                     oo::PList(), nullptr, oo::PList("e.png"))));
    OO_CHECK((dynamic_cast<OOConcreteTexture*>(texture) != nullptr));
    texture->ensureFinishedLoading();
    OO_CHECK(texture->isFinishedLoading() && texture->dimensions().width > 0);
    OO_CHECK(texture->cacheKey() ==
             NewGenerator(oo::PList("e.png"), OOColor::redColor().get(), nullptr,
                          nullptr, oo::PList(), nullptr, oo::PList("e.png"))
                 ->cacheKey());

    // While that texture is cached, a generator of its key reads no map, so it
    // bakes nothing.
    Baked baked;
    Bake(NewGenerator(oo::PList("e.png"), OOColor::redColor().get(), nullptr, nullptr,
                      oo::PList(), nullptr, oo::PList("e.png")),
         baked);
    OO_CHECK(!baked.ok);
  }
  ClearCache();
}

#ifndef NDEBUG
OO_TEST(description) {
  SetUp();
  {
    oo::AutoreleaseScope pool;
    const std::string description =
        NewGenerator(oo::PList("e.png"), OOColor::redColor().get(), nullptr, nullptr,
                     oo::PList(), nullptr, oo::PList("e.png"))
            ->description();
    OO_CHECK(description.starts_with("<OOCombinedEmissionMapGenerator 0x"));
    OO_CHECK(description.find("{emission map: ") != std::string::npos);
    OO_CHECK(description.find(
                 " * " + OOColor::redColor()->rgbaDescription().value_or("") +
                 "}") != std::string::npos);
  }
}
#endif

// --- The C++ API (after the conversion)
// --------------------------------------------------------

OO_TEST(cxxApi) {
  SetUp();
  {
    oo::AutoreleaseScope pool;
    OO_CHECK(!OOCombinedEmissionMapGenerator::generatorWithEmissionMapSpec(
        oo::PList(), nullptr, nullptr, nullptr, oo::PList(), nullptr, oo::PList()));
    OO_CHECK(!OOCombinedEmissionMapGenerator::
                 generatorWithEmissionAndIlluminationMapSpec(
                     oo::PList(), nullptr, nullptr, nullptr, nullptr, oo::PList()));

    const std::shared_ptr<OOColor> red = OOColor::colorWithRGBAComponents(
        (OORGBAComponents){1.0f, 0.0f, 0.0f, 1.0f});
    const std::shared_ptr<OOCombinedEmissionMapGenerator> generator =
        OOCombinedEmissionMapGenerator::generatorWithEmissionMapSpec(
            oo::PList("e.png"), red.get(), nullptr, nullptr, oo::PList(), nullptr,
            oo::PList("e.png"));
    OO_CHECK(generator &&
             generator->cacheKey() ==
                 std::optional<std::string>(
                     "emission map;emission:{" + KeyOf("e.png") + "}*" +
                     red->rgbaDescription().value_or("") + ";"));

    // A generator the factory made is one.
    OOTextureGenerator* made =
        NewGenerator(oo::PList("e.png"), nullptr, nullptr, nullptr, oo::PList(), nullptr,
                     oo::PList("e.png"));
    OO_CHECK(dynamic_cast<OOCombinedEmissionMapGenerator*>(made) != nullptr);

    // Baking through the C++ object.
    generator->loadTexture();
    OO_CHECK(generator->_data != nullptr &&
             generator->_format == kOOPixMapRGBA &&
             generator->_data->data()[0] == 200 &&
             generator->_data->data()[1] == 0);
  }
  ClearCache();
}

OO_TEST_MAIN()
