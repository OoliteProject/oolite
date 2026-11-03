/*	test_OOTexture.mm
        Unit tests for OOTexture (src/Core/Materials/OOTexture.h), the root of
   the textures.

        OOTexture is abstract. OOConcreteTexture and OONullTexture derive from
   it in their own files. The root keeps the
   texture caches (the live textures by cache key, unretained; the recent
   textures, retained; every live texture, for graphics resets) and is the
   factory that answers a cached texture or a new OOConcreteTexture. It links
   the whole game but main (tests/unit/core/meson.build entry ['*']), on the
   hidden GL context of oo_gl_test_context.hpp, because the factory checks the
   GL extensions on first use. Nothing here reaches the resource manager: the
   named texture is found in the cache by its key, and the generator's -enqueue
   is the test's, so no file is read and no worker thread runs.

        The cases call the C++ members. Two subclasses stand for the concrete
   textures: TestTexture overrides
   what OOConcreteTexture does and caches itself under a key, BareTexture
   overrides nothing, so it answers the root's defaults. An autoreleased texture
   is kept until its scope drains (oo::autorelease). After them comes the C++
   API. Run: tests/run.sh unit
*/

#include <algorithm>
#include <string>
#include <vector>

#include "OOConcreteTexture.h"
#include "OODescription.h"
#include "OONullTexture.h"
#include "OOTexture.h"
#include "OOTextureGenerator.h"
#include "OOTextureInternal.h"
#include "oo_gl_test_context.hpp"
#include "oo_test.hpp"

// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

static int gTestDeallocs = 0;

// A texture as OOConcreteTexture is one: it caches itself under its key, and
// uncaches itself.
class TestTexture final : public OOTexture {
 public:
  explicit TestTexture(std::optional<std::string> key) : _key(std::move(key)) {
    addToCaches();
  }
  ~TestTexture() override {
    gTestDeallocs++;
    removeFromCaches();
  }

  void apply() override { _applies++; }
  NSSize dimensions() override { return NSMakeSize(8, 4); }
  bool isMipMapped() override { return true; }
  void forceRebind() override { _rebinds++; }
  std::optional<std::string> cacheKey() override { return _key; }
  GLint glTextureName() override { return 7; }
  std::optional<std::string> descriptionComponents() const override {
    return std::string("test");
  }
#ifndef NDEBUG
  std::optional<std::string> name() override {
    return std::string("test texture");
  }
#endif

  std::optional<std::string> _key;
  int _rebinds = 0;
  int _applies = 0;
};

// A texture that overrides nothing: the root's own answers.
class BareTexture final : public OOTexture {};

// What an autoreleased texture is: the C++ texture, kept until the current
// autorelease scope drains (oo::autorelease).
static OOTexture* Autoreleased(const oo::Ref<OOTexture>& texture) {
  if (texture == nullptr) return nullptr;
  oo::autorelease(oo::Ref<OOTexture>(texture));
  return texture.get();
}

// A generator that is never queued: enqueue() answers what the test says, and
// counts.
class TestGenerator : public OOTextureGenerator {
 public:
  std::optional<std::string> cacheKey() override { return _key; }
  bool enqueue() override {
    _enqueues++;
    return _accept;
  }

  std::optional<std::string> _key;
  bool _accept = false;
  int _enqueues = 0;
};

namespace {

TestTexture* MakeTexture(const std::optional<std::string>& key) {
  return static_cast<TestTexture*>(Autoreleased(oo::makeRef<TestTexture>(key)));
}

// The generators made, kept for the test's life (each was autoreleased in its
// case's pool).
std::vector<oo::Ref<TestGenerator>> gKeptGenerators;

TestGenerator* MakeGenerator(const std::optional<std::string>& key,
                             bool accept) {
  const oo::Ref<TestGenerator> made = oo::makeRef<TestGenerator>();
  if (!made->initWithPath(std::string("test generator"), 0)) return nullptr;
  gKeptGenerators.push_back(made);
  TestGenerator* generator = made.get();
  generator->_key = key;
  generator->_accept = accept;
  return generator;
}

// -clearCache autoreleases the recent textures (a C++ cache), which needs a
// scope to be released.
void ClearCache() {
  {
    oo::AutoreleaseScope scope;
    OOTexture::clearCache();
  }
}

bool SameSize(NSSize size, double width, double height) {
  return size.width == width && size.height == height;
}

#ifndef NDEBUG
bool Contains(const std::vector<oo::Ref<OOTexture>>& textures,
              OOTexture* texture) {
  return std::find(textures.begin(), textures.end(), texture) != textures.end();
}
#endif

}  // namespace

OO_TEST(rootDefaults) {
  {
    oo::AutoreleaseScope pool;
    OOTexture* bare = Autoreleased(oo::makeRef<BareTexture>());
    OO_CHECK(bare->isFinishedLoading());
    OO_CHECK(!bare->cacheKey().has_value());
    OO_CHECK(!bare->isRectangleTexture() && !bare->isCubeMap());
    OO_CHECK(SameSize(bare->texCoordsScale(), 1, 1));
    OO_CHECK(OOIsNullPixMap(bare->copyPixMapRepresentation()));
    bare->ensureFinishedLoading();

    // The subclass responsibilities log and answer zero.
    OO_CHECK(SameSize(bare->dimensions(), 0, 0));
    OO_CHECK(SameSize(bare->originalDimensions(), 0, 0));
    OO_CHECK(!bare->isMipMapped());
    OO_CHECK(bare->glTextureName() == 0);
    bare->apply();
#ifndef NDEBUG
    OO_CHECK(!bare->name().has_value());
    OO_CHECK(bare->dataSize() == 0);
#endif
    OO_CHECK(bare->description().starts_with("<BareTexture 0x"));
  }
}

OO_TEST(subclassOverrides) {
  {
    oo::AutoreleaseScope pool;
    TestTexture* texture = MakeTexture(std::nullopt);
    OO_CHECK(SameSize(texture->originalDimensions(), 8,
                      4));  // the root's, from -dimensions
    OO_CHECK(SameSize(texture->texCoordsScale(), 1, 1));
    OO_CHECK(texture->glTextureName() == 7 && texture->isMipMapped());
    texture->apply();
    OO_CHECK(texture->_applies == 1);
#ifndef NDEBUG
    OO_CHECK(texture->dataSize() == 42);  // 8 * 4, mip-mapped: * 4 / 3
    OO_CHECK(texture->name() == std::optional<std::string>("test texture"));
    texture->setTrace(true);
    texture->setTrace(false);
#endif
    const std::string text = texture->description();
    OO_CHECK(text.starts_with("<TestTexture 0x") && text.ends_with(">{test}"));
  }
}

OO_TEST(cachesKeepAndForget) {
  ClearCache();
  const int deallocs = gTestDeallocs;
  TestTexture* texture = nullptr;
  OOTexture* bare = nullptr;
  {
    oo::AutoreleaseScope pool;
    texture = MakeTexture(std::string("test:cache"));
    bare = oo::makeRef<BareTexture>().leakRef();
    OO_CHECK(OOTexture::existingTextureForKey(std::string("test:cache")) ==
             texture);
    OO_CHECK(OOTexture::existingTextureForKey(std::nullopt) == nullptr);
    OO_CHECK(OOTexture::existingTextureForKey(std::string("test:none")) == nullptr);
  }

  // The recent textures keep it alive; the live textures find it.
  OO_CHECK(gTestDeallocs == deallocs);
  OO_CHECK(OOTexture::existingTextureForKey(std::string("test:cache")) ==
           texture);
#ifndef NDEBUG
  {
    oo::AutoreleaseScope pool;
    OO_CHECK(Contains(OOTexture::cachedTexturesByAge(), texture));
    OO_CHECK(!Contains(OOTexture::cachedTexturesByAge(),
                       bare));  // no key: not cached
    const std::vector<oo::Ref<OOTexture>> all = OOTexture::allTextures();
    OO_CHECK(Contains(all, texture) && Contains(all, bare));
  }
#endif

  // Clearing forgets both caches, and releases what only they kept.
  {
    oo::AutoreleaseScope scope;
    OOTexture::clearCache();
    OO_CHECK(OOTexture::existingTextureForKey(std::string("test:cache")) ==
             nullptr);
  }
  OO_CHECK(gTestDeallocs == deallocs + 1);
#ifndef NDEBUG
  {
    oo::AutoreleaseScope pool;
    OO_CHECK(OOTexture::cachedTexturesByAge().empty());
    const std::vector<oo::Ref<OOTexture>> all = OOTexture::allTextures();
    OO_CHECK(Contains(all, bare));
    OO_CHECK(
        std::none_of(all.begin(), all.end(), [](const oo::Ref<OOTexture>& t) {
          return dynamic_cast<TestTexture*>(t.get()) != nullptr;
        }));
  }
#endif
  oo::release(bare);
}

OO_TEST(rebindAllTextures) {
  const int deallocs = gTestDeallocs;
  {
    oo::AutoreleaseScope pool;
    TestTexture* cached = MakeTexture(std::string("test:rebind"));
    TestTexture* plain = MakeTexture(std::nullopt);
    OOTexture::rebindAllTextures();
    OO_CHECK(cached->_rebinds == 1 && plain->_rebinds == 1);

    // The recent textures are dropped; the live textures still find it while it
    // lives.
    OO_CHECK(OOTexture::existingTextureForKey(std::string("test:rebind")) ==
             cached);
#ifndef NDEBUG
    OO_CHECK(OOTexture::cachedTexturesByAge().empty());
#endif
  }
  OO_CHECK(gTestDeallocs == deallocs + 2);
  OO_CHECK(OOTexture::existingTextureForKey(std::string("test:rebind")) == nullptr);
}

OO_TEST(namedTextureFromTheCache) {
  OO_CHECK(OOTestGLContext());
  {
    oo::AutoreleaseScope pool;
    OO_CHECK(OOTexture::textureWithName(std::nullopt, std::string("Textures"))
                 .get() == nullptr);

    // Linear filtering: no anisotropy and no LOD bias in the key, whatever the
    // extensions.
    const std::string key = OOGenerateTextureCacheKey(
        std::string("Textures"), "test.png",
        kOOTextureMinFilterLinear | kOOTextureMagFilterLinear, 0.5f, -0.25f);
    OO_CHECK(key == "Textures/test.png:0x0006/0/0");
    TestTexture* texture = MakeTexture(key);

    OO_CHECK(OOTexture::textureWithName(
                 std::string("test.png"), std::string("Textures"),
                 kOOTextureMinFilterLinear | kOOTextureMagFilterLinear |
                     kOOTextureNoFNFMessage,
                 kOOTextureDefaultAnisotropy, kOOTextureDefaultLODBias)
                 .get() == texture);
    OO_CHECK(OOTexture::textureWithConfiguration(oo::PList(oo::PList::Dict{
                 {"name", oo::PList("test.png")},
                 {"min_filter", oo::PList("linear")}})) == texture);
    OO_CHECK(OOTexture::textureWithConfiguration(
                 oo::PList(oo::PList::Dict{{"name", oo::PList("test.png")}}),
                 kOOTextureMinFilterLinear) == texture);

    // A specifier that names no texture.
    OO_CHECK(OOTexture::textureWithConfiguration(oo::PList(
                 oo::PList::Dict{{"min_filter", oo::PList("linear")}})) == nullptr);
    OO_CHECK(OOTexture::textureWithConfiguration(oo::PList(3.0)).get() == nullptr);
    OO_CHECK(OOTexture::textureWithConfiguration(oo::PList()).get() == nullptr);
    ClearCache();
  }
}

OO_TEST(texturesFromGenerators) {
  {
    oo::AutoreleaseScope pool;
    ClearCache();
    OO_CHECK(OOTexture::textureWithGenerator(nullptr).get() == nullptr);
    TestGenerator* refusing = MakeGenerator(std::string("test:refused"), false);
    OO_CHECK(OOTexture::textureWithGenerator(refusing).get() == nullptr &&
             refusing->_enqueues == 1);

    TestGenerator* generator = MakeGenerator(std::string("test:gen"), true);
    OOTexture* first = Autoreleased(OOTexture::textureWithGenerator(generator));
    OO_CHECK((dynamic_cast<OOConcreteTexture*>(first) != nullptr) &&
             generator->_enqueues == 1);
    OO_CHECK(first->cacheKey() == std::optional<std::string>("test:gen"));
    OO_CHECK(OOTexture::existingTextureForKey(std::string("test:gen")) ==
             first);

    // Cached: the same texture, not queued again; unless the caller forces a
    // new one.
    OO_CHECK(OOTexture::textureWithGenerator(generator).get() == first &&
             generator->_enqueues == 1);
    OOTexture* second =
        Autoreleased(OOTexture::textureWithGenerator(generator, true));
    OO_CHECK(second != nullptr && second != first && generator->_enqueues == 2);
    OO_CHECK(OOTexture::existingTextureForKey(std::string("test:gen")) ==
             second);

    // No key: never cached.
    TestGenerator* uncached = MakeGenerator(std::nullopt, true);
    OOTexture* a = Autoreleased(OOTexture::textureWithGenerator(uncached));
    OOTexture* b = Autoreleased(OOTexture::textureWithGenerator(uncached));
    OO_CHECK(a != nullptr && b != nullptr && a != b && uncached->_enqueues == 2);
  }

  /*	The first texture's -dealloc (when the recent textures replaced it and
     the pool drained) uncached its key from the live textures, although the
     second texture had it by then.
  */
  OO_CHECK(OOTexture::existingTextureForKey(std::string("test:gen")) == nullptr);
  ClearCache();
}

OO_TEST(nullTexture) {
  OO_CHECK(OOTestGLContext());
  {
    oo::AutoreleaseScope pool;
    OOTexture* none = OOTexture::nullTexture().get();
    OO_CHECK(dynamic_cast<OONullTexture*>(none) != nullptr &&
             none == OOTexture::nullTexture());
    OO_CHECK(SameSize(none->dimensions(), 0, 0) && !none->isMipMapped());
#ifndef NDEBUG
    OO_CHECK(none->name() == std::optional<std::string>("<null texture>"));
#endif
    none->forceRebind();

    // Applying it is applying none.
    GLuint name = 0;
    glGenTextures(1, &name);
    glBindTexture(GL_TEXTURE_2D, name);
    none->apply();
    GLint bound = -1;
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &bound);
    OO_CHECK(bound == 0);
    glDeleteTextures(1, &name);
  }
}

OO_TEST(applyNone) {
  OO_CHECK(OOTestGLContext());
  GLuint name = 0;
  glGenTextures(1, &name);
  glBindTexture(GL_TEXTURE_2D, name);
  GLint bound = -1;
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &bound);
  OO_CHECK(bound == (GLint)name);
  OOTexture::applyNone();
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &bound);
  OO_CHECK(bound == 0);
  glDeleteTextures(1, &name);
}

// --- The C++ API (after the conversion)
// ---------------------------------------------------------

// A converted texture, as OOConcreteTexture is one: a C++ subclass, cached
// under its key. Global, so it prints its name as a global class's.
class TestCxxTexture final : public OOTexture {
 public:
  explicit TestCxxTexture(std::optional<std::string> key)
      : _key(std::move(key)) {
    addToCaches();
  }
  ~TestCxxTexture() override { removeFromCaches(); }

  void apply() override { applies++; }
  NSSize dimensions() override { return NSMakeSize(16, 2); }
  bool isMipMapped() override { return false; }
  void forceRebind() override { rebinds++; }
  std::optional<std::string> cacheKey() override { return _key; }
  GLint glTextureName() override { return 9; }
  std::optional<std::string> descriptionComponents() const override {
    return std::string("cxx");
  }

  int applies = 0;
  int rebinds = 0;

 private:
  std::optional<std::string> _key;
};

OO_TEST(cxxApi) {
  ClearCache();
  {
    oo::AutoreleaseScope pool;
    // The factories answer the C++ texture, retained.
    OO_CHECK(
        !OOTexture::textureWithName(std::nullopt, std::string("Textures")));
    const oo::Ref<OOTexture> none = OOTexture::nullTexture();
    OO_CHECK(dynamic_cast<OONullTexture*>(none.get()) != nullptr &&
             none.get() == OOTexture::nullTexture());
    TestGenerator* generator = MakeGenerator(std::string("test:cxxgen"), true);
    const oo::Ref<OOTexture> generated =
        OOTexture::textureWithGenerator(generator);
    OO_CHECK((dynamic_cast<OOConcreteTexture*>(generated.get()) != nullptr));
    OO_CHECK(OOTexture::existingTextureForKey(std::string("test:cxxgen")) ==
             generated.get());
    OO_CHECK(OOTexture::textureWithGenerator(generator, false).get() ==
                 generated &&
             generator->_enqueues == 1);
    OO_CHECK(!OOTexture::textureWithConfiguration(oo::PList(3.0)));
    OO_CHECK(OOTexture::existingTextureForKey(std::nullopt) == nullptr);
    ClearCache();
  }

  // The root's own answers.
  const oo::Ref<OOTexture> root = oo::makeRef<OOTexture>();
  OO_CHECK(root->isFinishedLoading() && !root->cacheKey().has_value());
  OO_CHECK(SameSize(root->dimensions(), 0, 0) &&
           SameSize(root->originalDimensions(), 0, 0));
  OO_CHECK(SameSize(root->texCoordsScale(), 1, 1) && !root->isMipMapped() &&
           root->glTextureName() == 0);
  OO_CHECK(!root->isRectangleTexture() && !root->isCubeMap() &&
           OOIsNullPixMap(root->copyPixMapRepresentation()));
  OO_CHECK(!root->descriptionComponents().has_value());
  root->apply();
  root->ensureFinishedLoading();
  root->forceRebind();
#ifndef NDEBUG
  OO_CHECK(!root->name().has_value() && root->dataSize() == 0);
#endif
}

OO_TEST(cxxTextureBehindTheFacade) {
  const int deallocs = gTestDeallocs;
  {
    oo::AutoreleaseScope pool;
    const oo::Ref<TestCxxTexture> texture =
        oo::makeRef<TestCxxTexture>(std::string("test:cxx"));
    OOTexture* facade = texture.get();  // what the callers hold

    // The callers' calls reach the C++ overrides, and the root's defaults.
    OO_CHECK(SameSize(facade->dimensions(), 16, 2) &&
             SameSize(facade->originalDimensions(), 16, 2));
    OO_CHECK(facade->glTextureName() == 9 && !facade->isMipMapped() &&
             facade->isFinishedLoading());
    OO_CHECK(facade->cacheKey() == std::optional<std::string>("test:cxx"));
    facade->apply();
    OO_CHECK(texture->applies == 1);
#ifndef NDEBUG
    OO_CHECK(facade->dataSize() == 32);
#endif
    const std::string text = facade->description();
    OO_CHECK(text.starts_with("<TestCxxTexture 0x") &&
             text.ends_with(">{cxx}"));

    // The caches hold it by key; a graphics reset reaches it.
    OO_CHECK(OOTexture::existingTextureForKey(std::string("test:cxx")) ==
             facade);
    OOTexture::rebindAllTextures();
    OO_CHECK(texture->rebinds == 1);
#ifndef NDEBUG
    {
      oo::AutoreleaseScope pool;
      OO_CHECK(Contains(OOTexture::allTextures(), facade));
    }
#endif
  }
  ClearCache();
  OO_CHECK(OOTexture::existingTextureForKey(std::string("test:cxx")) ==
           nullptr);  // destroyed: uncached
  OO_CHECK(gTestDeallocs == deallocs);
}

/*	clearCache() hands the old recent-texture cache to
   oo::autorelease, as upstream's [sRecentTextures autorelease] handed it to the
   enclosing pool. In the game that is the frame loop's or the start-up's
   oo::AutoreleaseScope. The cache, and the textures only it keeps,
   are released at the drain of the NEAREST open scope: not at the call, not at
   an outer scope's drain, and nothing is counted as autoreleased without a
   scope.
*/
OO_TEST(clearCacheReleasesAtTheNearestScopesDrain) {
  ClearCache();
  const int deallocs = gTestDeallocs;
  const std::size_t leaked = oo::AutoreleaseScope::leakedWithoutScope();
  {
    oo::AutoreleaseScope outer;  // stands for the frame loop's scope
    {
      oo::AutoreleaseScope made;
      MakeTexture(std::string("test:drain"));
    }
    OO_CHECK(gTestDeallocs == deallocs);  // only the recent textures keep it
    const std::size_t outerPending = outer.pendingCount();
    {
      oo::AutoreleaseScope nearest;
      OOTexture::clearCache();
      OO_CHECK(nearest.pendingCount() ==
               1);  // the old cache, waiting for the drain
      OO_CHECK(outer.pendingCount() == outerPending);
      OO_CHECK(gTestDeallocs == deallocs);  // no earlier than the drain
      OO_CHECK(OOTexture::existingTextureForKey(std::string("test:drain")) ==
               nullptr);  // forgotten at once

      // With no recent textures left, a second clear hands nothing over.
      OOTexture::clearCache();
      OO_CHECK(nearest.pendingCount() == 1);
    }
    OO_CHECK(gTestDeallocs ==
             deallocs + 1);  // released at the nearest scope's drain
    OO_CHECK(outer.pendingCount() == outerPending);
  }
  OO_CHECK(gTestDeallocs == deallocs + 1);
  OO_CHECK(oo::AutoreleaseScope::leakedWithoutScope() == leaked);
}

OO_TEST_MAIN()
