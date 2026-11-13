/*	test_OOSingleTextureMaterial.mm
        Unit tests for OOSingleTextureMaterial
   (src/Core/Materials/OOSingleTextureMaterial.h).

        A basic material with one texture. This pins what it does: which
   texture specifier each initialiser asks for and when it fails (no name, no
   texture), the configuration reaching the basic material, the texture kept
   for the material's life, what -doApply / -unapplyWithNext: do to the texture
   and the GL material, the loading and cube-map questions it passes to the
   texture, and the description. The cases ask the C++ class (alloc/init is
   materialWithName(), nil is null, retain/release a held Ref);
   crossesAsTheBasicMaterialFacade pins what the root sees: the nearest
   base, OOBasicMaterial's. Run: bash tools/check-core-tests.sh
*/

#include <cstdlib>
#include <vector>

#include "OOSingleTextureMaterial.h"
#include "OOTexture.h"
#include "oo_gl_test_context.hpp"
#include "oo_test.hpp"
#include "oofnd/String.hpp"

/*	The game's OOLogging.mm reaches the resource manager, so it is not
   linked; what the material and the GL error check call of it is defined here.
*/
void OOLogGenericSubclassResponsibilityForFunction(const char* inFunction) {
  (void)inFunction;
}
void OOLogGenericParameterErrorForFunction(const char* inFunction) {
  (void)inFunction;
}
void OOLogIndent(void) {}
void OOLogOutdent(void) {}

/*	OOTexture (OOTexture.mm links the texture loaders and the game) is a
   stand-in that records what the material asks of it.
   +textureWithConfiguration: answers nil for a null specifier, or for the
   name "missing", as a texture that fails to load does.
*/
static int gTextureApplyNones = 0;
static int gTexturesDeallocated = 0;
static std::vector<oo::PList> gTextureConfigurations;

/*	The stand-in is C++: the root's static
	members the material calls, the root's own members (a texture needs them), and TestTexture, the
	texture the factory answers.
*/
class TestTexture final : public OOTexture {
 public:
  ~TestTexture() override { gTexturesDeallocated++; }
  void apply() override { _applies++; }
  void ensureFinishedLoading() override { _ensures++; }
  bool isFinishedLoading() override { return _finished; }
  bool isCubeMap() override { return _cubeMap; }
  std::string description() const override { return "<TestTexture>"; }

  oo::PList _configuration;
  int _applies = 0;
  int _ensures = 0;
  bool _finished = false;
  bool _cubeMap = false;
};

void OOTexture::applyNone() { gTextureApplyNones++; }

std::shared_ptr<OOTexture> OOTexture::textureWithConfiguration(
    const oo::PList& configuration) {
  gTextureConfigurations.push_back(configuration);
  if (configuration.isNull() || configuration == oo::PList("missing"))
    return nullptr;
  std::shared_ptr<TestTexture> texture = oo::makeShared<TestTexture>();
  texture->_configuration = configuration;
  return texture;
}

OOTexture::OOTexture() {}
OOTexture::~OOTexture() {}
void OOTexture::apply() {}
void OOTexture::ensureFinishedLoading() {}
bool OOTexture::isFinishedLoading() { return true; }
std::optional<std::string> OOTexture::cacheKey() { return std::nullopt; }
NSSize OOTexture::dimensions() { return NSSize{}; }
NSSize OOTexture::originalDimensions() { return dimensions(); }
bool OOTexture::isMipMapped() { return false; }
OOPixMap OOTexture::copyPixMapRepresentation() { return OOPixMap{}; }
bool OOTexture::isRectangleTexture() { return false; }
bool OOTexture::isCubeMap() { return false; }
NSSize OOTexture::texCoordsScale() { return NSSize{1.0, 1.0}; }
GLint OOTexture::glTextureName() { return 0; }
#ifndef NDEBUG
std::optional<std::string> OOTexture::name() { return std::nullopt; }
#endif
std::optional<std::string> OOTexture::descriptionComponents() const {
  return std::nullopt;
}
std::optional<std::string> OOTexture::shortDescriptionComponents() const {
  return std::nullopt;
}
std::string OOTexture::description() const {
  return oo::str::format("<OOTexture %s>",
                         oo::str::pointerDescription(this).c_str());
}
std::string OOTexture::shortDescription() const { return description(); }
std::string OOTexture::className() const { return "OOTexture"; }
void OOTexture::forceRebind() {}

/*	The texture specifier OOTexture.mm makes of a diffuse_map value,
   recorded: a dictionary naming what it was given (the game's own is pinned by
   the texture's tests).
*/
oo::PList OOTextureSpecFromObject(
    const oo::PList& object, const std::optional<std::string>& defaultName) {
  return oo::PList(oo::PList::Dict{
      {"object", object.isNull() ? oo::PList("(null)") : object},
      {"defaultName", oo::PList(defaultName.value_or("(nil)"))},
  });
}

// Link stubs, never reached here: OOOpenGL.mm's GL
// state dump.
OOOpenGLExtensionManager* OOOpenGLExtensionManager::sharedManager() {
  std::abort();
}
GLint OOOpenGLExtensionManager::textureUnitCount() { std::abort(); }
// OOOpenGLStateManager.mm's (linked for the debug build's
// OOGLNoteCurrentFunction) multitexture entry points live in
// OOOpenGLExtensionManager.mm, which this test stubs; never called here.
PFNGLACTIVETEXTUREARBPROC glActiveTextureARB = nullptr;
PFNGLCLIENTACTIVETEXTUREARBPROC glClientActiveTextureARB = nullptr;

// UNIVERSE is gSharedUniverse: nil, so not reduced detail and no shaders.
// UNIVERSE stays nil here, so the code under test's guarded calls never reach
// it; the stand-in only links them (they were messages to nil).
class Universe {
 public:
  bool useShaders();
};
bool Universe::useShaders() { return false; }

Universe* gSharedUniverse = nullptr;

namespace {

TestTexture* MakeTexture() {
  // The factory's autoreleased result: the texture, kept until the current
  // autorelease scope drains.
  return static_cast<TestTexture*>(oo::autorelease(
      OOTexture::textureWithConfiguration(oo::PList("hull.png"))));
}

std::shared_ptr<OOSingleTextureMaterial> Make(
    const std::optional<std::string>& name, OOTexture* texture,
    const oo::PList& configuration = oo::PList()) {
  return OOSingleTextureMaterial::materialWithName(name, texture,
                                                   configuration);
}

// The material's description ("(null)" for none).
std::string Description(OOMaterial* material) {
  return material != nullptr ? material->description() : "(null)";
}

bool Same(const GLfloat* a, std::initializer_list<GLfloat> b) {
  const GLfloat* e = b.begin();
  for (int i = 0; i < 4; i++) {
    if (a[i] != e[i]) return false;
  }
  return true;
}

}  // namespace

OO_TEST(initWithTexture) {
  {
    oo::AutoreleaseScope pool;
    TestTexture* texture = MakeTexture();
    const std::shared_ptr<OOSingleTextureMaterial> m = Make(
        std::string("Hull"), texture,
        oo::PList(oo::PList::Dict{{"diffuse_color", oo::PList("redColor")}}));
    OO_CHECK(m != nullptr && m->name() == std::optional<std::string>("Hull"));
    GLfloat c[4] = {};
    m->getDiffuseComponents(c);
    OO_CHECK(
        Same(c, {1, 0, 0, 1}));  // the configuration reached the basic material
    OO_CHECK(m->shininess() == 10);
#ifndef NDEBUG
    const std::vector<std::shared_ptr<OOTexture>> textures = m->allTextures();
    OO_CHECK(textures.size() == 1 && textures[0].get() == texture);
#endif

    // No name, or no texture: no material.
    OO_CHECK(Make(std::nullopt, texture) == nullptr);
    OO_CHECK(Make(std::string("Bare"), nullptr) == nullptr);
  }
}

OO_TEST(initWithConfiguration) {
  {
    oo::AutoreleaseScope pool;
    // A configuration: the texture is the diffuse_map's specifier, with the
    // name as its default.
    gTextureConfigurations.clear();
    std::shared_ptr<OOSingleTextureMaterial> m =
        OOSingleTextureMaterial::materialWithName(
            std::string("Hull"),
            oo::PList(oo::PList::Dict{
                {"diffuse_map", oo::PList("hull_diffuse.png")},
            }));
    OO_CHECK(m != nullptr);
    OO_CHECK(
        gTextureConfigurations.size() == 1 &&
        gTextureConfigurations[0] ==
            oo::PList(oo::PList::Dict{{"object", oo::PList("hull_diffuse.png")},
                                      {"defaultName", oo::PList("Hull")}}));

    // No diffuse_map: the specifier of nothing, still with the name as its
    // default.
    gTextureConfigurations.clear();
    m = OOSingleTextureMaterial::materialWithName(std::string("Plain"),
                                                  oo::PList(oo::PList::Dict{}));
    OO_CHECK(m != nullptr && gTextureConfigurations.size() == 1);
    OO_CHECK(gTextureConfigurations[0] ==
             oo::PList(oo::PList::Dict{{"object", oo::PList("(null)")},
                                       {"defaultName", oo::PList("Plain")}}));

    // No configuration: the name is the texture's specifier.
    gTextureConfigurations.clear();
    m = OOSingleTextureMaterial::materialWithName(std::string("named.png"),
                                                  oo::PList());
    OO_CHECK(m != nullptr && gTextureConfigurations.size() == 1 &&
             gTextureConfigurations[0] == oo::PList("named.png"));
    OO_CHECK(m->name() == std::optional<std::string>("named.png"));

    // Neither: a null specifier, no texture, no material. A texture that fails:
    // no material.
    gTextureConfigurations.clear();
    OO_CHECK(OOSingleTextureMaterial::materialWithName(std::nullopt,
                                                       oo::PList()) == nullptr);
    OO_CHECK(gTextureConfigurations.size() == 1 &&
             gTextureConfigurations[0].isNull());
    OO_CHECK(OOSingleTextureMaterial::materialWithName(std::string("missing"),
                                                       oo::PList()) == nullptr);
  }
}

OO_TEST(textureKeptForTheMaterialsLife) {
  const int deallocated = gTexturesDeallocated;
  std::shared_ptr<OOSingleTextureMaterial> m;
  {
    oo::AutoreleaseScope pool;
    m = Make(std::string("Kept"), MakeTexture());
  }
  OO_CHECK(gTexturesDeallocated == deallocated);
  m = nullptr;
  OO_CHECK(gTexturesDeallocated == deallocated + 1);
}

OO_TEST(texturesQuestions) {
  {
    oo::AutoreleaseScope pool;
    TestTexture* texture = MakeTexture();
    const std::shared_ptr<OOSingleTextureMaterial> m =
        Make(std::string("Asks"), texture);
    OO_CHECK(!m->isFinishedLoading() && !m->wantsNormalsAsTextureCoordinates());
    texture->_finished = true;
    texture->_cubeMap = true;
    OO_CHECK(m->isFinishedLoading() && m->wantsNormalsAsTextureCoordinates());
    m->ensureFinishedLoading();
    OO_CHECK(texture->_ensures == 1);
#if OO_MULTITEXTURE
    OO_CHECK(m->countOfTextureUnitsWithBaseCoordinates() == 1);
#endif
    m->setBindingTarget(nullptr);
    OO_CHECK(m->permitSpecular());
  }
}

OO_TEST(doApply) {
  if (!OOTestGLContext()) {
    OO_CHECK(false);
    return;
  }
  {
    oo::AutoreleaseScope pool;
    TestTexture* texture = MakeTexture();
    const std::shared_ptr<OOSingleTextureMaterial> m =
        Make(std::string("Applied"), texture);
    m->setDiffuseRed(0.5f, 0.25f, 0.125f, 1);
    const int applyNones = gTextureApplyNones;
    OO_CHECK(m->doApply());
    OO_CHECK(texture->_applies == 1);
    OO_CHECK(gTextureApplyNones == applyNones);  // not exactly a basic material
    GLfloat c[4] = {};
    glGetMaterialfv(GL_FRONT, GL_DIFFUSE, c);
    OO_CHECK(Same(c, {0.5f, 0.25f, 0.125f, 1}));

    m->apply();
    OO_CHECK(OOMaterial::current().get() == m.get() && texture->_applies == 2);
    OOMaterial::applyNone();
    OO_CHECK(OOMaterial::current() == nullptr);
  }
}

OO_TEST(unapplyWithNext) {
  if (!OOTestGLContext()) {
    OO_CHECK(false);
    return;
  }
  {
    oo::AutoreleaseScope pool;
    const std::shared_ptr<OOSingleTextureMaterial> m =
        Make(std::string("Current"), MakeTexture());
    m->setDiffuseRed(0.5f, 0.25f, 0.125f, 1);
    m->doApply();
    GLfloat c[4] = {};

    // Another textured material: the texture stays, and so does the GL
    // material.
    int applyNones = gTextureApplyNones;
    m->unapplyWithNext(Make(std::string("Next"), MakeTexture()).get());
    OO_CHECK(gTextureApplyNones == applyNones);
    glGetMaterialfv(GL_FRONT, GL_DIFFUSE, c);
    OO_CHECK(Same(c, {0.5f, 0.25f, 0.125f, 1}));

    // A basic material: no texture; it sets its own GL material.
    m->unapplyWithNext(
        OOBasicMaterial::materialWithName(std::string("Basic")).get());
    OO_CHECK(gTextureApplyNones == applyNones + 1);
    glGetMaterialfv(GL_FRONT, GL_DIFFUSE, c);
    OO_CHECK(Same(c, {0.5f, 0.25f, 0.125f, 1}));

    // Nothing: no texture, and the default material (which also has none).
    applyNones = gTextureApplyNones;
    m->unapplyWithNext(nullptr);
    OO_CHECK(gTextureApplyNones == applyNones + 2);
    glGetMaterialfv(GL_FRONT, GL_DIFFUSE, c);
    OO_CHECK(Same(c, {1, 1, 1, 1}));
  }
}

OO_TEST(description) {
  {
    oo::AutoreleaseScope pool;
    const std::string text =
        Description(Make(std::string("Hull"), MakeTexture()).get());
    OO_CHECK(text.starts_with("<OOSingleTextureMaterial 0x"));
    OO_CHECK(text.ends_with(">{<TestTexture>}"));
  }
}

// --- The C++ class and the root
// -----------------------------------------

OO_TEST(cxxAPI) {
  {
    oo::AutoreleaseScope pool;
    TestTexture* texture = MakeTexture();
    const std::shared_ptr<OOSingleTextureMaterial> m =
        OOSingleTextureMaterial::materialWithName(std::string("Cxx"), texture,
                                                  oo::PList());
    OO_CHECK(m != nullptr && m->name() == std::optional<std::string>("Cxx") &&
             m->shininess() == 10);
    OO_CHECK(m->descriptionComponents() ==
             std::optional<std::string>("<TestTexture>"));
    OO_CHECK(!m->isFinishedLoading() && !m->wantsNormalsAsTextureCoordinates());
    texture->_cubeMap = true;
    OO_CHECK(m->wantsNormalsAsTextureCoordinates());
#ifndef NDEBUG
    OO_CHECK(m->allTextures().size() == 1 &&
             m->allTextures()[0].get() == texture);
#endif

    OO_CHECK(OOSingleTextureMaterial::materialWithName(std::nullopt, texture,
                                                       oo::PList()) == nullptr);
    OO_CHECK(OOSingleTextureMaterial::materialWithName(std::string("Bare"), nullptr,
                                                       oo::PList()) == nullptr);
    OO_CHECK(OOSingleTextureMaterial::materialWithName(std::string("named.png"),
                                                       oo::PList()) != nullptr);
    OO_CHECK(OOSingleTextureMaterial::materialWithName(std::string("missing"),
                                                       oo::PList()) == nullptr);

    if (OOTestGLContext()) {
      const int applies = texture->_applies, applyNones = gTextureApplyNones;
      m->apply();
      OO_CHECK(texture->_applies == applies + 1 &&
               OOMaterial::current().get() == m.get());
      OOMaterial::applyNone();  // told nothing comes next: no texture, then the
                                // default material
      OO_CHECK(gTextureApplyNones == applyNones + 2);
    }
  }
}

// The name and description.
OO_TEST(nameAndDescription) {
  {
    oo::AutoreleaseScope pool;
    const std::shared_ptr<OOSingleTextureMaterial> m =
        OOSingleTextureMaterial::materialWithName(std::string("Cxx"),
                                                  MakeTexture(), oo::PList());
    OO_CHECK(m->name() == std::optional<std::string>("Cxx"));
    const std::string text = m->description();
    OO_CHECK(text.starts_with("<OOSingleTextureMaterial 0x") &&
             text.ends_with(">{<TestTexture>}"));
  }
}

OO_TEST_MAIN()
