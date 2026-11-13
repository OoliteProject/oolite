/*	test_OOTextureGenerator.mm
        Unit tests for OOTextureGenerator
   (src/Core/Materials/OOTextureGenerator.h), a texture loader that needs no
   file.

        A generator chooses its own texture options, anisotropy, LOD bias and
   cache key, and queues itself on the game's work manager;
   OOPixMapTextureLoader and the planet, atmosphere and emission-map generators
   derive from it in their own files. The test's generators are C++ subclasses:
   a bare one that answers the class's defaults, and one that overrides
   them. It links the whole game but main (tests/unit/core/meson.build entry
   ['*']), on the hidden GL context of oo_gl_test_context.hpp. The last test
   pins the C++ API (OOTextureGenerator). Run: tests/run.sh unit
*/

#include <cstdlib>

#include "OOConcreteTexture.h"
#include "OOTextureGenerator.h"
#include "oo_gl_test_context.hpp"
#include "oo_test.hpp"
#include "oofnd/AutoreleaseScope.hpp"

// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

static int gLoads = 0;

// A generator of an 8 x 8 RGBA image whose bytes count up from 1. Its root
// state is written in one block.
class BareGenerator : public OOTextureGenerator {
 public:
  void loadTexture() override {
    gLoads++;
    OOPixelBuffer buffer = OOMakePixelBuffer(8 * 8 * 4);
    uint8_t* bytes = buffer->data();
    for (unsigned i = 0; i < 8 * 8 * 4; i++) bytes[i] = (uint8_t)(i + 1);
    _data = buffer;
    _width = 8;
    _height = 8;
    _format = kOOPixMapRGBA;
  }
};

// A generator that chooses its own settings and cache key.
class ChoosyGenerator : public BareGenerator {
 public:
  OOTextureFlags textureOptions() override {
    return OOTextureFlags::kMinFilterNearest | OOTextureFlags::kMagFilterNearest;
  }
  GLfloat anisotropy() override { return 0.25f; }
  GLfloat lodBias() override { return 0.5f; }
  std::optional<std::string> cacheKey() override {
    return std::string("test:choosy");
  }
};

// What an autoreleased texture is: the C++ texture, kept until the current
// autorelease scope drains (oo::autorelease).
static OOTexture* Autoreleased(const std::shared_ptr<OOTexture>& texture) {
  if (texture == nullptr) return nullptr;
  oo::autorelease(std::shared_ptr<OOTexture>(texture));
  return texture.get();
}

namespace {

// The loaders' sizes come from their one-time set-up, which a path with no
// known extension runs (and then answers nil, reading nothing).
void SetUpLoaders() {
  {
    oo::AutoreleaseScope pool;
    (void)OOTextureLoader::loaderWithPath(std::string("unknown.type"), OOTextureFlags::kNone);
  }
}

// The generators made, kept for the test's life (each was autoreleased in its
// case's pool).
std::vector<std::shared_ptr<OOTextureGenerator>> gKeptGenerators;

template <class G>
G* Generator(const char* path, OOTextureFlags options) {
  const std::shared_ptr<G> made = oo::makeShared<G>();
  if (!made->initWithPath(std::string(path), options)) return nullptr;
  gKeptGenerators.push_back(made);
  return made.get();
}

void ClearCache() {
  {
    oo::AutoreleaseScope scope;
    OOTexture::clearCache();
  }
}

}  // namespace

OO_TEST(defaults) {
  OO_CHECK(OOTestGLContext());
  SetUpLoaders();
  {
    oo::AutoreleaseScope pool;
    BareGenerator* generator =
        Generator<BareGenerator>("bare generator", OOTextureFlags::kMinFilterLinear);
    OO_CHECK(generator->textureOptions() == OOTextureFlags::kDefaultOptions);
    OO_CHECK(generator->anisotropy() == (GLfloat)kOOTextureDefaultAnisotropy &&
             generator->lodBias() == (GLfloat)kOOTextureDefaultLODBias);
    OO_CHECK(!generator->cacheKey()
                  .has_value());  // a generator is not cached unless it says so
    OO_CHECK(generator->path() == std::optional<std::string>("bare generator"));
    OO_CHECK(dynamic_cast<OOTextureLoader*>(generator) != nullptr);
    OO_CHECK(
        generator->description().ends_with(">{{bare generator -- loading}}"));
    OO_CHECK(!oo::makeShared<BareGenerator>()->initWithPath(std::nullopt, OOTextureFlags::kNone));
  }
}

OO_TEST(enqueueLoadsOnTheWorkManager) {
  OO_CHECK(OOTestGLContext());
  SetUpLoaders();
  {
    oo::AutoreleaseScope pool;
    const int loads = gLoads;
    BareGenerator* generator =
        Generator<BareGenerator>("queued generator", OOTextureFlags::kMinFilterLinear);
    OO_CHECK(generator->enqueue());
    OOPixMap pixMap = kOONullPixMap;
    OOTextureDataFormat format = kOOPixMapInvalidFormat;
    uint32_t width = 0, height = 0;
    OO_CHECK(generator->getResult(&pixMap, &format, &width, &height));
    OO_CHECK(gLoads == loads + 1 && generator->isReady());
    OO_CHECK(pixMap.width == 8 && pixMap.height == 8 && width == 8 &&
             format == kOOPixMapRGBA);
    OO_CHECK(((uint8_t*)pixMap.pixels)[0] == 1);
    OOFreePixMap(&pixMap);
  }
}

OO_TEST(aTextureTakesTheGeneratorsSettings) {
  OO_CHECK(OOTestGLContext());
  SetUpLoaders();
  {
    oo::AutoreleaseScope pool;
    ChoosyGenerator* generator =
        Generator<ChoosyGenerator>("choosy generator", OOTextureFlags::kNone);
    OO_CHECK(generator->textureOptions() ==
             (OOTextureFlags::kMinFilterNearest | OOTextureFlags::kMagFilterNearest));
    OO_CHECK(generator->anisotropy() == 0.25f && generator->lodBias() == 0.5f);

    OOTexture* texture =
        Autoreleased(OOTexture::textureWithGenerator(generator));
    OO_CHECK((dynamic_cast<OOConcreteTexture*>(texture) != nullptr));
    OO_CHECK(texture->cacheKey() == std::optional<std::string>("test:choosy"));
    OO_CHECK(OOTexture::textureWithGenerator(generator).get() ==
             texture);  // cached by the generator's key
    texture->ensureFinishedLoading();
    OO_CHECK(texture->dimensions().width == 8 &&
             !texture->isMipMapped());  // nearest: no mip-maps
#ifndef NDEBUG
    OO_CHECK(texture->name() ==
             std::optional<std::string>("<ChoosyGenerator>"));
#endif
  }
  ClearCache();
}

// --- The C++ API (after the conversion)
// --------------------------------------------------------

// A converted generator, as OOPixMapTextureLoader will be one: a global C++
// subclass.
class TestCxxGenerator final : public OOTextureGenerator {
 public:
  void loadTexture() override {
    loads++;
    OOPixelBuffer buffer = OOMakePixelBuffer(8 * 8 * 4);
    uint8_t* bytes = buffer->data();
    for (unsigned i = 0; i < 8 * 8 * 4; i++) bytes[i] = (uint8_t)(i + 1);
    _data = buffer;
    _width = 8;
    _height = 8;
    _format = kOOPixMapRGBA;
  }

  OOTextureFlags textureOptions() override {
    return OOTextureFlags::kMinFilterLinear | OOTextureFlags::kMagFilterLinear;
  }
  std::optional<std::string> cacheKey() override {
    return std::string("test:cxxgen");
  }

  int loads = 0;
};

OO_TEST(cxxApi) {
  OO_CHECK(OOTestGLContext());
  SetUpLoaders();
  {
    oo::AutoreleaseScope pool;
    const std::shared_ptr<TestCxxGenerator> generator = oo::makeShared<TestCxxGenerator>();
    OO_CHECK(generator->initWithPath(std::string("cxx generator"), OOTextureFlags::kNone));
    OO_CHECK(generator->anisotropy() == (GLfloat)kOOTextureDefaultAnisotropy &&
             generator->lodBias() == (GLfloat)kOOTextureDefaultLODBias);

    // A texture takes it.
    OO_CHECK(generator->textureOptions() ==
             (OOTextureFlags::kMinFilterLinear | OOTextureFlags::kMagFilterLinear));
    OO_CHECK(generator->cacheKey() ==
             std::optional<std::string>("test:cxxgen"));
    OOTexture* texture =
        Autoreleased(OOTexture::textureWithGenerator(generator.get()));
    OO_CHECK(texture->cacheKey() == std::optional<std::string>("test:cxxgen"));
    texture->ensureFinishedLoading();
    OO_CHECK(generator->loads == 1 && texture->dimensions().width == 8);

    // The bare class's own answers.
    const std::shared_ptr<OOTextureGenerator> bare = oo::makeShared<OOTextureGenerator>();
    OO_CHECK(bare->textureOptions() == OOTextureFlags::kDefaultOptions &&
             !bare->cacheKey().has_value());
  }
  ClearCache();
}

OO_TEST_MAIN()
