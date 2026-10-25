/*	test_OOMultiTextureMaterial.mm
	Unit tests for OOMultiTextureMaterial (src/Core/Materials/OOMultiTextureMaterial.h): bead
	oo-lh0x, converted after its superclass OOBasicMaterial (bead oo-vl43; proposed ADR-0056,
	amendments oo-smy and oo-vl43).

	A basic material with a diffuse map and an emission map on two texture units, combined by the
	fixed-function texture combiners. This pins, through the Objective-C API its caller (the
	convenience creators) uses, what it computed before the conversion: which maps each
	configuration asks for (a plain emission map, or one baked by OOCombinedEmissionMapGenerator
	from what else is configured), the emission colour kept from the basic material when a map
	replaces it, the units used, -apply (the maps, the combiner state, texture unit 0 active after),
	-unapplyWithNext: (the units the next material does not use are cleared), the loading question
	passed to the maps, and the description. The GL context is a hidden window's; the extension
	manager runs with its collaborators stubbed as in test_OOOpenGLExtensionManager. Those checks
	ran on the Objective-C class first and then through the facade. After them: the C++ API
	(apply() is virtual since this bead: the root facade's -apply and C++ callers reach the
	override), and the facade's class and identity.

	Bead oo-9ht.42 deleted the facade (ADR-0056 amendment "deleting a facade"). The cases that asked
	through its selectors ask the C++ class with the same expectations (alloc/init is
	materialWithName(), retain/release a held Ref); the facade's own case (facade) was retired with
	it (ADR-0049, standing approval oo-9n5p9), and crossesAsTheBasicMaterialFacade pins what
	Objective-C sees now: the nearest facade, OOBasicMaterial's.
	Run: bash tools/check-core-tests.sh
*/

#include "OOMultiTextureMaterial.h"
#include "OOCombinedEmissionMapGenerator.h"
#include "OORegExpMatcher.h"
#include "OOOpenGLExtensionManager.h"
#include "OODescription.h"
#include "OOTexture.h"
#include "oofnd/String.hpp"

#include "oo_gl_test_context.hpp"
#include "oo_test.hpp"

#include <cstdlib>
#include <string>
#include <vector>


// --- Stubs --------------------------------------------------------------------------------------

// OOLogging.mm's (it would bring the resource manager into the link).
void OOLogGenericSubclassResponsibilityForFunction(const char *inFunction)	{ (void)inFunction; }
void OOLogGenericParameterErrorForFunction(const char *inFunction)			{ (void)inFunction; }
void OOLogIndent(void)  {}
void OOLogOutdent(void)  {}


// The extension manager's collaborators, as test_OOOpenGLExtensionManager stubs them.
#include "ResourceManager.h"

// ResourceManager is C++ since bead oo-9ht.150 deleted its Objective-C facade: C++ definitions of the
// statics the code under test calls, with the Objective-C stand-in's answers.
std::vector<std::string> ResourceManager::paths()  { return {}; }
oo::PList ResourceManager::dictionaryFromFilesNamed(const std::string &/*fileName*/, const std::optional<std::string> &/*folderName*/, bool /*mergeFiles*/)  { return oo::PList(oo::PList::Dict{}); }



// OORegExpMatcher is C++ since its facade was deleted (bead oo-9ht.12): the stub answers no match.
oo::Ref<OORegExpMatcher> OORegExpMatcher::regExpMatcher()  { return oo::makeRef<OORegExpMatcher>(); }
bool OORegExpMatcher::string(const std::string &, const std::string &)  { return false; }
OORegExpMatcher::~OORegExpMatcher()  {}


OOShaderSetting cxx_OOShaderSettingFromString(const std::string &string)
{
	return string == "SHADERS_FULL" ? SHADERS_FULL : SHADERS_NOT_SUPPORTED;
}


// A specifier as text: its string, or "-".
static std::string Str(const oo::PList &plist)
{
	const std::string *string = plist.getIf<std::string>();
	return string != nullptr ? *string : "-";
}


/*	OOTexture: a stand-in recording what the material asks (proposed ADR-0056, amendment oo-z1s4
	item 4). A texture's configuration is the specifier it was made from, or "generated".
*/
// kOOTextureExtraShrink, spelled out as before.
static const uint32_t kExtraShrink = 0x000020UL;

static int gTextureApplyNones = 0;
static int gTexturesDeallocated = 0;
static std::vector<std::pair<oo::PList, uint32_t>> gTextureConfigurations;	// (specifier, extra options)

// Since bead oo-9ht.99 deleted the Objective-C facade, the stand-in is C++: the root's static
// members the material calls, TestTexture (what they answer), and the root's own members; the
// short description is every texture's here (they are all TestTextures).
class TestTexture final : public OOTexture
{
public:
	~TestTexture() override					{ gTexturesDeallocated++; }
	void apply() override					{ _applies++; }
	void ensureFinishedLoading() override	{ _ensures++; }

	oo::PList	_configuration;
	int			_applies = 0;
	int			_ensures = 0;
};

static TestTexture *AsTest(const oo::Ref<OOTexture> &texture)  { return static_cast<TestTexture *>(texture.get()); }

void OOTexture::applyNone()	{ gTextureApplyNones++; }

oo::Ref<OOTexture> OOTexture::textureWithConfiguration(const oo::PList &configuration)
{
	return textureWithConfiguration(configuration, 0);
}

oo::Ref<OOTexture> OOTexture::textureWithConfiguration(const oo::PList &configuration, OOTextureFlags extraOptions)
{
	gTextureConfigurations.emplace_back(configuration, extraOptions);
	if (configuration.isNull())  return nullptr;
	oo::Ref<TestTexture> texture = oo::makeRef<TestTexture>();
	texture->_configuration = configuration;
	return texture;
}

oo::Ref<OOTexture> OOTexture::textureWithGenerator(::OOTextureGenerator *generator)
{
	if (generator == nullptr)  return nullptr;
	oo::Ref<TestTexture> texture = oo::makeRef<TestTexture>();
	texture->_configuration = oo::PList("generated");
	return texture;
}

OOTexture::OOTexture()	{}
OOTexture::~OOTexture()	{}
void OOTexture::apply()	{}
void OOTexture::ensureFinishedLoading()	{}
bool OOTexture::isFinishedLoading()	{ return true; }
std::optional<std::string> OOTexture::cacheKey()	{ return std::nullopt; }
NSSize OOTexture::dimensions()	{ return NSSize{}; }
NSSize OOTexture::originalDimensions()	{ return dimensions(); }
bool OOTexture::isMipMapped()	{ return false; }
OOPixMap OOTexture::copyPixMapRepresentation()	{ return OOPixMap{}; }
bool OOTexture::isRectangleTexture()	{ return false; }
bool OOTexture::isCubeMap()	{ return false; }
NSSize OOTexture::texCoordsScale()	{ return NSSize{1.0, 1.0}; }
GLint OOTexture::glTextureName()	{ return 0; }
#ifndef NDEBUG
std::optional<std::string> OOTexture::name()	{ return std::nullopt; }
#endif
std::optional<std::string> OOTexture::descriptionComponents() const	{ return std::nullopt; }
std::optional<std::string> OOTexture::shortDescriptionComponents() const	{ return std::nullopt; }
std::string OOTexture::description() const	{ return oo::str::format("<OOTexture %s>", oo::str::pointerDescription(this).c_str()); }
std::string OOTexture::className() const	{ return "OOTexture"; }
void OOTexture::forceRebind()	{}
std::string OOTexture::shortDescription() const	{ return "tex:" + Str(static_cast<const TestTexture *>(this)->_configuration); }


/*	OOCombinedEmissionMapGenerator: records which factory was called and with what. It answers
	null when it would have nothing to bake (no emission map and no illumination map), as the
	material's callers never see a generated map for none. It is C++ since bead oo-9ht.135 deleted
	its Objective-C facade: the stand-in defines the factories, and its own and its bases' other
	members as no-ops (no texture loader is linked). The material hands the C++ generator to the
	OOTexture stand-in, which only asks whether it is nil (it handed the generator's Objective-C
	object, here a plain object, until bead oo-9ht.118 deleted the generators' facade).
*/
static std::vector<std::string> gGenerators;

OOTextureLoader::OOTextureLoader()  {}
OOTextureLoader::~OOTextureLoader()  {}
bool OOTextureLoader::getResult(OOPixMap *, OOTextureDataFormat *, uint32_t *, uint32_t *)  { return false; }
std::optional<std::string> OOTextureLoader::cacheKey()  { return std::nullopt; }
std::optional<std::string> OOTextureLoader::descriptionComponents() const  { return std::nullopt; }
std::optional<std::string> OOTextureLoader::shortDescriptionComponents() const  { return std::nullopt; }
void OOTextureLoader::loadTexture()  {}
// The loader is the work manager's task since bead oo-9ht.14 (its vtable): never reached.
void OOTextureLoader::performAsyncTask()  { std::abort(); }
void OOTextureLoader::completeAsyncTask()  { std::abort(); }
uint32_t OOTextureGenerator::textureOptions()  { return 0; }
GLfloat OOTextureGenerator::anisotropy()  { return 0; }
GLfloat OOTextureGenerator::lodBias()  { return 0; }
std::optional<std::string> OOTextureGenerator::cacheKey()  { return std::nullopt; }
bool OOTextureGenerator::enqueue()  { return false; }

oo::Ref<OOCombinedEmissionMapGenerator> OOCombinedEmissionMapGenerator::generatorWithEmissionMapSpec(const oo::PList &emissionMapSpec,
																									OOColor *emissionColor,
																									OOTexture *diffuseMap,
																									OOColor *diffuseColor,
																									const oo::PList &illuminationMapSpec,
																									OOColor *illuminationColor,
																									const oo::PList &spec)
{
	gGenerators.push_back("emission:" + Str(emissionMapSpec)
						  + " emissionColor:" + (emissionColor != nullptr ? "yes" : "no")
						  + " diffuseMap:" + (diffuseMap != nil ? "yes" : "no")
						  + " diffuseColor:" + (diffuseColor != nullptr ? "yes" : "no")
						  + " illumination:" + Str(illuminationMapSpec)
						  + " illuminationColor:" + (illuminationColor != nullptr ? "yes" : "no")
						  + " options:" + Str(spec));
	if (emissionMapSpec.isNull() && illuminationMapSpec.isNull())  return {};
	return oo::makeRef<OOCombinedEmissionMapGenerator>();
}

oo::Ref<OOCombinedEmissionMapGenerator> OOCombinedEmissionMapGenerator::generatorWithEmissionAndIlluminationMapSpec(const oo::PList &emissionAndIlluminationMapSpec,
																												  OOTexture *diffuseMap,
																												  OOColor *,
																												  OOColor *,
																												  OOColor *,
																												  const oo::PList &spec)
{
	gGenerators.push_back("emissionAndIllumination:" + Str(emissionAndIlluminationMapSpec)
						  + " diffuseMap:" + (diffuseMap != nil ? "yes" : "no")
						  + " options:" + Str(spec));
	return oo::makeRef<OOCombinedEmissionMapGenerator>();
}

OOCombinedEmissionMapGenerator::~OOCombinedEmissionMapGenerator()  {}
#ifndef NDEBUG
std::optional<std::string> OOCombinedEmissionMapGenerator::descriptionComponents() const  { return std::nullopt; }
#endif
uint32_t OOCombinedEmissionMapGenerator::textureOptions()  { return 0; }
GLfloat OOCombinedEmissionMapGenerator::anisotropy()  { return 0; }
GLfloat OOCombinedEmissionMapGenerator::lodBias()  { return 0; }
std::optional<std::string> OOCombinedEmissionMapGenerator::cacheKey()  { return std::nullopt; }
void OOCombinedEmissionMapGenerator::loadTexture()  {}

// OOTexture.mm's specifier of a map value: the value itself, or the default name, or none.
oo::PList cxx_OOTextureSpecFromObject(const oo::PList &object, const std::optional<std::string> &defaultName)
{
	if (!object.isNull())  return object;
	return defaultName.has_value() ? oo::PList(*defaultName) : oo::PList();
}


// UNIVERSE is gSharedUniverse: nil, so not reduced detail and no shaders.
// UNIVERSE stays nil here, so the code under test's guarded calls never reach it; the stand-in only
// links them (bead oo-ql9rn: they were messages to nil).
class Universe
{
public:
	bool useShaders();
};
bool Universe::useShaders()  { return false; }

Universe *gSharedUniverse = nil;


namespace {

bool CombinersSupported()
{
	return OOTestGLContext() && OOOpenGLExtensionManager::sharedManager()->textureCombinersSupported();
}


oo::Ref<OOMultiTextureMaterial> Make(const char *name, oo::PList::Dict config)
{
	gTextureConfigurations.clear();
	gGenerators.clear();
	return OOMultiTextureMaterial::materialWithName(std::string(name), oo::PList(std::move(config)));
}


GLint TexEnvMode(GLenum unit)
{
	GLint mode = 0;
	glActiveTextureARB(unit);
	glGetTexEnviv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, &mode);
	glActiveTextureARB(GL_TEXTURE0_ARB);
	return mode;
}

}	// namespace


OO_TEST(combinersRequired)
{
	if (!OOTestGLContext())  { OO_CHECK(false); return; }
	{
		// On a GL without texture combiners the initialiser answers nil; this context has them.
		OO_CHECK(CombinersSupported());
		OO_CHECK(Make("Hull", {}) != nullptr);
	}
}


OO_TEST(mapsFromTheConfiguration)
{
	if (!CombinersSupported())  { OO_CHECK(false); return; }
	{
		// Only a name: the diffuse map is named after it, and there is no emission map to bake.
		oo::Ref<OOMultiTextureMaterial> m = Make("hull.png", {});
		OO_CHECK(gTextureConfigurations.size() == 1 && gTextureConfigurations[0].first == oo::PList("hull.png") && gTextureConfigurations[0].second == 0);
		OO_CHECK(gGenerators == std::vector<std::string>{ "emission:- emissionColor:no diffuseMap:yes diffuseColor:no illumination:- illuminationColor:no options:-" });
		OO_CHECK(m->textureUnitCount() == 1 && m->countOfTextureUnitsWithBaseCoordinates() == 1);

		// A plain emission map: loaded shrunk, not baked.
		m = Make("Hull", { { "diffuse_map", oo::PList("d.png") }, { "emission_map", oo::PList("e.png") } });
		OO_CHECK(gTextureConfigurations.size() == 2);
		OO_CHECK(gTextureConfigurations[0].first == oo::PList("d.png") && gTextureConfigurations[0].second == 0);
		OO_CHECK(gTextureConfigurations[1].first == oo::PList("e.png") && gTextureConfigurations[1].second == kExtraShrink);
		OO_CHECK(gGenerators.empty() && m->textureUnitCount() == 2);

		// An emission map with a modulating colour: baked, and the basic material's emission colour
		// is dropped from what it is given.
		m = Make("Hull", {
			{ "diffuse_map", oo::PList("d.png") },
			{ "emission_map", oo::PList("e.png") },
			{ "emission_modulate_color", oo::PList("redColor") },
			{ "emission_color", oo::PList("greenColor") },
			{ "diffuse_color", oo::PList("blueColor") },
		});
		OO_CHECK(gGenerators == std::vector<std::string>{ "emission:e.png emissionColor:yes diffuseMap:yes diffuseColor:yes illumination:- illuminationColor:no options:e.png" });
		GLfloat c[4] = {};
		m->getEmissionComponents(c);
		OO_CHECK(c[0] == 0 && c[1] == 0 && c[2] == 0 && c[3] == 1);
		m->getDiffuseComponents(c);
		OO_CHECK(c[0] == 0 && c[2] == 1);
		OO_CHECK(m->textureUnitCount() == 2);

		// An illumination map alone: baked, with it as the options specifier; the emission colour stays.
		m = Make("Hull", { { "illumination_map", oo::PList("i.png") }, { "emission_color", oo::PList("greenColor") } });
		OO_CHECK(gGenerators == std::vector<std::string>{ "emission:- emissionColor:no diffuseMap:yes diffuseColor:no illumination:i.png illuminationColor:no options:i.png" });
		m->getEmissionComponents(c);
		OO_CHECK(c[1] == 1);

		// The combined map: the other generator.
		m = Make("Hull", { { "emission_and_illumination_map", oo::PList("ei.png") } });
		OO_CHECK(gGenerators == std::vector<std::string>{ "emissionAndIllumination:ei.png diffuseMap:yes options:ei.png" });
		OO_CHECK(m->textureUnitCount() == 2);
	}
}


OO_TEST(texturesKeptAndAsked)
{
	if (!CombinersSupported())  { OO_CHECK(false); return; }
	const int deallocated = gTexturesDeallocated;
	oo::Ref<OOMultiTextureMaterial> m;
	{
		m = Make("Hull", { { "diffuse_map", oo::PList("d.png") }, { "emission_map", oo::PList("e.png") } });
	}
	OO_CHECK(gTexturesDeallocated == deallocated);
	{
		m->ensureFinishedLoading();
#ifndef NDEBUG
		const std::vector<oo::Ref<OOTexture>> textures = m->allTextures();
		OO_CHECK(textures.size() == 2 && AsTest(textures[0])->_ensures == 1 && AsTest(textures[1])->_ensures == 1);
		OO_CHECK(AsTest(textures[0])->_configuration == oo::PList("d.png") && AsTest(textures[1])->_configuration == oo::PList("e.png"));
#endif
		const std::string text = m->description();
		OO_CHECK(text.starts_with("<OOMultiTextureMaterial 0x"));
		OO_CHECK(text.ends_with(">{\"Hull\" - diffuse map: tex:d.png,emission map: tex:e.png}"));
	}
	m = nullptr;
	OO_CHECK(gTexturesDeallocated == deallocated + 2);

	{
		// No diffuse map (no name): only the emission map.
		gTextureConfigurations.clear();
		const oo::Ref<OOMultiTextureMaterial> emissive = OOMultiTextureMaterial::materialWithName(std::nullopt, oo::PList(oo::PList::Dict{ { "emission_map", oo::PList("e.png") } }));
		OO_CHECK(emissive->textureUnitCount() == 1);
#ifndef NDEBUG
		OO_CHECK(emissive->allTextures().size() == 1);
#endif
		OO_CHECK(emissive->description().ends_with(">{\"(null)\" - emission map: tex:e.png}"));
	}
}


OO_TEST(applyAndUnapply)
{
	if (!CombinersSupported())  { OO_CHECK(false); return; }
	{
		const oo::Ref<OOMultiTextureMaterial> two = Make("Two", { { "diffuse_map", oo::PList("d.png") }, { "emission_map", oo::PList("e.png") } });
		const oo::Ref<OOMultiTextureMaterial> one = Make("one.png", {});
#ifndef NDEBUG
		TestTexture *diffuse = AsTest(two->allTextures()[0]), *emission = AsTest(two->allTextures()[1]);
#endif

		two->apply();
		OO_CHECK(OOMaterial::current().get() == two.get());
#ifndef NDEBUG
		OO_CHECK(diffuse->_applies == 1 && emission->_applies == 1);
#endif
		OO_CHECK(TexEnvMode(GL_TEXTURE0_ARB) == GL_COMBINE_ARB && TexEnvMode(GL_TEXTURE1_ARB) == GL_COMBINE_ARB);
		GLint active = 0;
		glGetIntegerv(GL_ACTIVE_TEXTURE_ARB, &active);
		OO_CHECK(active == GL_TEXTURE0_ARB);

		// The next material uses two units: nothing to clear, and it is a basic material.
		int applyNones = gTextureApplyNones;
		two->unapplyWithNext(Make("Other", { { "diffuse_map", oo::PList("x.png") }, { "emission_map", oo::PList("y.png") } }).get());
		OO_CHECK(gTextureApplyNones == applyNones);

		// One unit: the second is cleared, back to modulate.
		two->unapplyWithNext(one.get());
		OO_CHECK(gTextureApplyNones == applyNones + 1 && TexEnvMode(GL_TEXTURE1_ARB) == GL_MODULATE);

		// Nothing: the default material (no texture), then both units cleared.
		applyNones = gTextureApplyNones;
		OOMaterial::applyNone();
		OO_CHECK(gTextureApplyNones == applyNones + 3 && TexEnvMode(GL_TEXTURE0_ARB) == GL_MODULATE);
		OO_CHECK(OOMaterial::current() == nullptr);
		OO_CHECK(glGetError() == GL_NO_ERROR);
	}
}


// --- The C++ class and the facade (after the conversion) -----------------------------------------

OO_TEST(cxxAPI)
{
	if (!CombinersSupported())  { OO_CHECK(false); return; }
	{
		gTextureConfigurations.clear();
		const oo::Ref<OOMultiTextureMaterial> m = OOMultiTextureMaterial::materialWithName(std::string("Cxx"), oo::PList(oo::PList::Dict{
			{ "diffuse_map", oo::PList("d.png") }, { "emission_map", oo::PList("e.png") } }));
		OO_CHECK(m != nullptr && m->textureUnitCount() == 2 && m->countOfTextureUnitsWithBaseCoordinates() == 2);
		OO_CHECK(m->descriptionComponents() == std::optional<std::string>("\"Cxx\" - diffuse map: tex:d.png,emission map: tex:e.png"));
#ifndef NDEBUG
		OO_CHECK(m->allTextures().size() == 2);
#endif

		// apply() is virtual: through a root pointer, twice (the second was the root facade's -apply).
		OOMaterial *root = m.get();
		root->apply();
#ifndef NDEBUG
		OO_CHECK(AsTest(m->allTextures()[0])->_applies == 1 && AsTest(m->allTextures()[1])->_applies == 1);
#endif
		OO_CHECK(OOMaterial::current().get() == m.get());
		root->apply();
#ifndef NDEBUG
		OO_CHECK(AsTest(m->allTextures()[0])->_applies == 2);
#endif
		const int applyNones = gTextureApplyNones;
		OOMaterial::applyNone();
		OO_CHECK(gTextureApplyNones == applyNones + 3);
	}
}


// The description names the C++ class, as the facade's did (beads oo-9ht.42, oo-9ht.8).
OO_TEST(descriptionNamesTheClass)
{
	if (!CombinersSupported())  { OO_CHECK(false); return; }
	{
		const oo::Ref<OOMultiTextureMaterial> m = OOMultiTextureMaterial::materialWithName(std::string("Cxx"), oo::PList());
		OO_CHECK(m->description().starts_with("<OOMultiTextureMaterial 0x"));
	}
}

OO_TEST_MAIN()
