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

#import "OOMultiTextureMaterial.h"
#import "OOCombinedEmissionMapGenerator.h"
#import "OORegExpMatcher.h"
#import "OOOpenGLExtensionManager.h"
#import "OODescription.h"

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
@interface ResourceManager: OOObject
+ (std::vector<std::string>) cxx_paths;
+ (oo::PList) cxx_dictionaryFromFilesNamed:(const std::string &)fileName inFolder:(const std::string &)folderName andMerge:(BOOL)mergeFiles;
@end

@implementation ResourceManager
+ (std::vector<std::string>) cxx_paths  { return {}; }
+ (oo::PList) cxx_dictionaryFromFilesNamed:(const std::string &)fileName inFolder:(const std::string &)folderName andMerge:(BOOL)mergeFiles  { return oo::PList(oo::PList::Dict{}); }
@end


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
// kOOTextureExtraShrink: OOTexture.h is not imported, because the test defines OOTexture.
static const uint32_t kExtraShrink = 0x000020UL;

static int gTextureApplyNones = 0;
static int gTexturesDeallocated = 0;
static std::vector<std::pair<oo::PList, uint32_t>> gTextureConfigurations;	// (specifier, extra options)

@interface OOTexture: OOObject
{
@public
	oo::PList	_configuration;
	int			_applies;
	int			_ensures;
}
+ (void) applyNone;
+ (id) cxx_textureWithConfiguration:(const oo::PList &)configuration;
+ (id) cxx_textureWithConfiguration:(const oo::PList &)configuration extraOptions:(uint32_t)extraOptions;
+ (id) textureWithGenerator:(id)generator;
- (void) apply;
- (void) ensureFinishedLoading;
@end

@implementation OOTexture

+ (void) applyNone	{ gTextureApplyNones++; }

+ (id) cxx_textureWithConfiguration:(const oo::PList &)configuration
{
	return [self cxx_textureWithConfiguration:configuration extraOptions:0];
}

+ (id) cxx_textureWithConfiguration:(const oo::PList &)configuration extraOptions:(uint32_t)extraOptions
{
	gTextureConfigurations.emplace_back(configuration, extraOptions);
	if (configuration.isNull())  return nil;
	OOTexture *texture = [[[OOTexture alloc] init] autorelease];
	texture->_configuration = configuration;
	return texture;
}

+ (id) textureWithGenerator:(id)generator
{
	if (generator == nil)  return nil;
	OOTexture *texture = [[[OOTexture alloc] init] autorelease];
	texture->_configuration = oo::PList("generated");
	return texture;
}

- (void) dealloc						{ gTexturesDeallocated++; [super dealloc]; }
- (void) apply							{ _applies++; }
- (void) ensureFinishedLoading			{ _ensures++; }
- (std::optional<std::string>) cxx_shortDescription	{ return "tex:" + Str(_configuration); }

@end


/*	OOCombinedEmissionMapGenerator: records which factory was called and with what. It answers
	null when it would have nothing to bake (no emission map and no illumination map), as the
	material's callers never see a generated map for none. It is C++ since bead oo-9ht.135 deleted
	its Objective-C facade: the stand-in defines the factories, and its own and its bases' other
	members as no-ops (no texture loader is linked); its Objective-C object (the material hands it
	to the OOTexture stand-in, which only asks whether it is nil) is a plain object.
*/
static std::vector<std::string> gGenerators;

cxx::OOTextureLoader::OOTextureLoader()  {}
cxx::OOTextureLoader::~OOTextureLoader()  {}
bool cxx::OOTextureLoader::getResult(OOPixMap *, OOTextureDataFormat *, uint32_t *, uint32_t *)  { return false; }
std::optional<std::string> cxx::OOTextureLoader::cacheKey()  { return std::nullopt; }
std::optional<std::string> cxx::OOTextureLoader::descriptionComponents() const  { return std::nullopt; }
std::optional<std::string> cxx::OOTextureLoader::shortDescriptionComponents() const  { return std::nullopt; }
void cxx::OOTextureLoader::loadTexture()  {}
uint32_t cxx::OOTextureGenerator::textureOptions()  { return 0; }
GLfloat cxx::OOTextureGenerator::anisotropy()  { return 0; }
GLfloat cxx::OOTextureGenerator::lodBias()  { return 0; }
std::optional<std::string> cxx::OOTextureGenerator::cacheKey()  { return std::nullopt; }
bool cxx::OOTextureGenerator::enqueue()  { return false; }

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

OOTextureGenerator *oo::ToObjC(cxx::OOTextureGenerator *generator)
{
	if (generator == nullptr)  return nil;
	id object = [[[OOObject alloc] init] autorelease];	// not an OOTextureGenerator: nothing asks it anything
	return object;
}


// OOTexture.mm's specifier of a map value: the value itself, or the default name, or none.
oo::PList cxx_OOTextureSpecFromObject(const oo::PList &object, const std::optional<std::string> &defaultName)
{
	if (!object.isNull())  return object;
	return defaultName.has_value() ? oo::PList(*defaultName) : oo::PList();
}


// UNIVERSE is gSharedUniverse: nil, so not reduced detail and no shaders.
@class Universe;
Universe *gSharedUniverse = nil;


namespace {

bool CombinersSupported()
{
	return OOTestGLContext() && [[OOOpenGLExtensionManager sharedManager] textureCombinersSupported];
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
	@autoreleasepool
	{
		// On a GL without texture combiners the initialiser answers nil; this context has them.
		OO_CHECK(CombinersSupported());
		OO_CHECK(Make("Hull", {}) != nullptr);
	}
}


OO_TEST(mapsFromTheConfiguration)
{
	if (!CombinersSupported())  { OO_CHECK(false); return; }
	@autoreleasepool
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
	@autoreleasepool
	{
		m = Make("Hull", { { "diffuse_map", oo::PList("d.png") }, { "emission_map", oo::PList("e.png") } });
	}
	OO_CHECK(gTexturesDeallocated == deallocated);
	@autoreleasepool
	{
		m->ensureFinishedLoading();
#ifndef NDEBUG
		const std::vector<oo::ObjCRef<OOTexture *>> textures = m->allTextures();
		OO_CHECK(textures.size() == 2 && textures[0].get()->_ensures == 1 && textures[1].get()->_ensures == 1);
		OO_CHECK(textures[0].get()->_configuration == oo::PList("d.png") && textures[1].get()->_configuration == oo::PList("e.png"));
#endif
		const std::string text = oo::DescriptionOf(oo::ToObjC(static_cast<cxx::OOMaterial *>(m.get())));
		OO_CHECK(text.starts_with("<OOMultiTextureMaterial 0x"));
		OO_CHECK(text.ends_with(">{\"Hull\" - diffuse map: tex:d.png,emission map: tex:e.png}"));
	}
	m = nullptr;
	OO_CHECK(gTexturesDeallocated == deallocated + 2);

	@autoreleasepool
	{
		// No diffuse map (no name): only the emission map.
		gTextureConfigurations.clear();
		const oo::Ref<OOMultiTextureMaterial> emissive = OOMultiTextureMaterial::materialWithName(std::nullopt, oo::PList(oo::PList::Dict{ { "emission_map", oo::PList("e.png") } }));
		OO_CHECK(emissive->textureUnitCount() == 1);
#ifndef NDEBUG
		OO_CHECK(emissive->allTextures().size() == 1);
#endif
		OO_CHECK(oo::DescriptionOf(oo::ToObjC(static_cast<cxx::OOMaterial *>(emissive.get()))).ends_with(">{\"(null)\" - emission map: tex:e.png}"));
	}
}


OO_TEST(applyAndUnapply)
{
	if (!CombinersSupported())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		const oo::Ref<OOMultiTextureMaterial> two = Make("Two", { { "diffuse_map", oo::PList("d.png") }, { "emission_map", oo::PList("e.png") } });
		const oo::Ref<OOMultiTextureMaterial> one = Make("one.png", {});
#ifndef NDEBUG
		OOTexture *diffuse = two->allTextures()[0].get(), *emission = two->allTextures()[1].get();
#endif

		two->apply();
		OO_CHECK(cxx::OOMaterial::current().get() == two.get());
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
		cxx::OOMaterial::applyNone();
		OO_CHECK(gTextureApplyNones == applyNones + 3 && TexEnvMode(GL_TEXTURE0_ARB) == GL_MODULATE);
		OO_CHECK(cxx::OOMaterial::current() == nullptr);
		OO_CHECK(glGetError() == GL_NO_ERROR);
	}
}


// --- The C++ class and the facade (after the conversion) -----------------------------------------

OO_TEST(cxxAPI)
{
	if (!CombinersSupported())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		gTextureConfigurations.clear();
		const oo::Ref<OOMultiTextureMaterial> m = OOMultiTextureMaterial::materialWithName(std::string("Cxx"), oo::PList(oo::PList::Dict{
			{ "diffuse_map", oo::PList("d.png") }, { "emission_map", oo::PList("e.png") } }));
		OO_CHECK(m != nullptr && m->textureUnitCount() == 2 && m->countOfTextureUnitsWithBaseCoordinates() == 2);
		OO_CHECK(m->descriptionComponents() == std::optional<std::string>("\"Cxx\" - diffuse map: tex:d.png,emission map: tex:e.png"));
#ifndef NDEBUG
		OO_CHECK(m->allTextures().size() == 2);
#endif

		// apply() is virtual: through a root pointer, and through the root facade's -apply.
		cxx::OOMaterial *root = m.get();
		root->apply();
#ifndef NDEBUG
		OO_CHECK(m->allTextures()[0].get()->_applies == 1 && m->allTextures()[1].get()->_applies == 1);
#endif
		OO_CHECK(cxx::OOMaterial::current().get() == m.get());
		[oo::ToObjC(static_cast<cxx::OOMaterial *>(m.get())) apply];
#ifndef NDEBUG
		OO_CHECK(m->allTextures()[0].get()->_applies == 2);
#endif
		const int applyNones = gTextureApplyNones;
		cxx::OOMaterial::applyNone();
		OO_CHECK(gTextureApplyNones == applyNones + 3);
	}
}


// Objective-C sees a multi-texture material as an OOMaterial (beads oo-9ht.42, oo-9ht.33).
OO_TEST(crossesAsTheBasicMaterialFacade)
{
	if (!CombinersSupported())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		const oo::Ref<OOMultiTextureMaterial> m = OOMultiTextureMaterial::materialWithName(std::string("Cxx"), oo::PList());
		OOMaterial *facade = oo::ToObjC(static_cast<cxx::OOMaterial *>(m.get()));
		OO_CHECK([facade isMemberOfClass:[OOMaterial class]] && oo::ToObjC(static_cast<cxx::OOMaterial *>(m.get())) == facade);
		OO_CHECK(oo::ToCxx(facade) == m.get() && oo::AsObjCMaterial(m.get()) == nullptr);
		OO_CHECK(oo::DescriptionOf(facade).starts_with("<OOMultiTextureMaterial 0x"));
	}
}

OO_TEST_MAIN()
