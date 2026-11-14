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
	ran on the Objective-C class first and now run through the facade. After them: the C++ API
	(apply() is virtual since this bead: the root facade's -apply and C++ callers reach the
	override), and the facade's class and identity.
	Run: bash tools/check-core-tests.sh
*/

#import "OOMultiTextureMaterial.h"
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


@interface OORegExpMatcher: OOObject
+ (instancetype) regExpMatcher;
- (BOOL) string:(const std::string &)string matchesExpression:(const std::string &)regExp;
@end

@implementation OORegExpMatcher
+ (instancetype) regExpMatcher  { return [[[self alloc] init] autorelease]; }
- (BOOL) string:(const std::string &)string matchesExpression:(const std::string &)regExp  { return NO; }
@end


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


/*	OOCombinedEmissionMapGenerator: records which initialiser was sent and with what. It answers
	nil when it would have nothing to bake (no emission map and no illumination map), as the
	material's callers never see a generated map for none.
*/
static std::vector<std::string> gGenerators;

@interface OOCombinedEmissionMapGenerator: OOObject
@end

@implementation OOCombinedEmissionMapGenerator

- (id) cxx_initWithEmissionMapSpec:(const oo::PList &)emissionMapSpec
					 emissionColor:(OOColor *)emissionColor
						diffuseMap:(OOTexture *)diffuseMap
					  diffuseColor:(OOColor *)diffuseColor
			   illuminationMapSpec:(const oo::PList &)illuminationMapSpec
				 illuminationColor:(OOColor *)illuminationColor
				  optionsSpecifier:(const oo::PList &)spec
{
	gGenerators.push_back("emission:" + Str(emissionMapSpec)
						  + " emissionColor:" + (emissionColor != nil ? "yes" : "no")
						  + " diffuseMap:" + (diffuseMap != nil ? "yes" : "no")
						  + " diffuseColor:" + (diffuseColor != nil ? "yes" : "no")
						  + " illumination:" + Str(illuminationMapSpec)
						  + " illuminationColor:" + (illuminationColor != nil ? "yes" : "no")
						  + " options:" + Str(spec));
	if (emissionMapSpec.isNull() && illuminationMapSpec.isNull())
	{
		[self release];
		return nil;
	}
	return [super init];
}

- (id) cxx_initWithEmissionAndIlluminationMapSpec:(const oo::PList &)emissionAndIlluminationMapSpec
									   diffuseMap:(OOTexture *)diffuseMap
									 diffuseColor:(OOColor *)diffuseColor
									emissionColor:(OOColor *)emissionColor
								illuminationColor:(OOColor *)illuminationColor
								 optionsSpecifier:(const oo::PList &)spec
{
	gGenerators.push_back("emissionAndIllumination:" + Str(emissionAndIlluminationMapSpec)
						  + " diffuseMap:" + (diffuseMap != nil ? "yes" : "no")
						  + " options:" + Str(spec));
	return [super init];
}

@end


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


OOMultiTextureMaterial *Make(const char *name, oo::PList::Dict config)
{
	gTextureConfigurations.clear();
	gGenerators.clear();
	return [[[OOMultiTextureMaterial alloc] initWithName:std::string(name) configuration:oo::PList(std::move(config))] autorelease];
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
		OO_CHECK(Make("Hull", {}) != nil);
	}
}


OO_TEST(mapsFromTheConfiguration)
{
	if (!CombinersSupported())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		// Only a name: the diffuse map is named after it, and there is no emission map to bake.
		OOMultiTextureMaterial *m = Make("hull.png", {});
		OO_CHECK(gTextureConfigurations.size() == 1 && gTextureConfigurations[0].first == oo::PList("hull.png") && gTextureConfigurations[0].second == 0);
		OO_CHECK(gGenerators == std::vector<std::string>{ "emission:- emissionColor:no diffuseMap:yes diffuseColor:no illumination:- illuminationColor:no options:-" });
		OO_CHECK([m textureUnitCount] == 1 && [m countOfTextureUnitsWithBaseCoordinates] == 1);

		// A plain emission map: loaded shrunk, not baked.
		m = Make("Hull", { { "diffuse_map", oo::PList("d.png") }, { "emission_map", oo::PList("e.png") } });
		OO_CHECK(gTextureConfigurations.size() == 2);
		OO_CHECK(gTextureConfigurations[0].first == oo::PList("d.png") && gTextureConfigurations[0].second == 0);
		OO_CHECK(gTextureConfigurations[1].first == oo::PList("e.png") && gTextureConfigurations[1].second == kExtraShrink);
		OO_CHECK(gGenerators.empty() && [m textureUnitCount] == 2);

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
		[m getEmissionComponents:c];
		OO_CHECK(c[0] == 0 && c[1] == 0 && c[2] == 0 && c[3] == 1);
		[m getDiffuseComponents:c];
		OO_CHECK(c[0] == 0 && c[2] == 1);
		OO_CHECK([m textureUnitCount] == 2);

		// An illumination map alone: baked, with it as the options specifier; the emission colour stays.
		m = Make("Hull", { { "illumination_map", oo::PList("i.png") }, { "emission_color", oo::PList("greenColor") } });
		OO_CHECK(gGenerators == std::vector<std::string>{ "emission:- emissionColor:no diffuseMap:yes diffuseColor:no illumination:i.png illuminationColor:no options:i.png" });
		[m getEmissionComponents:c];
		OO_CHECK(c[1] == 1);

		// The combined map: the other generator.
		m = Make("Hull", { { "emission_and_illumination_map", oo::PList("ei.png") } });
		OO_CHECK(gGenerators == std::vector<std::string>{ "emissionAndIllumination:ei.png diffuseMap:yes options:ei.png" });
		OO_CHECK([m textureUnitCount] == 2);
	}
}


OO_TEST(texturesKeptAndAsked)
{
	if (!CombinersSupported())  { OO_CHECK(false); return; }
	const int deallocated = gTexturesDeallocated;
	OOMultiTextureMaterial *m = nil;
	@autoreleasepool
	{
		m = [Make("Hull", { { "diffuse_map", oo::PList("d.png") }, { "emission_map", oo::PList("e.png") } }) retain];
	}
	OO_CHECK(gTexturesDeallocated == deallocated);
	@autoreleasepool
	{
		[m ensureFinishedLoading];
#ifndef NDEBUG
		const std::vector<oo::ObjCRef<OOTexture *>> textures = [m cxx_allTextures];
		OO_CHECK(textures.size() == 2 && textures[0].get()->_ensures == 1 && textures[1].get()->_ensures == 1);
		OO_CHECK(textures[0].get()->_configuration == oo::PList("d.png") && textures[1].get()->_configuration == oo::PList("e.png"));
#endif
		const std::string text = oo::DescriptionOf(m);
		OO_CHECK(text.starts_with("<OOMultiTextureMaterial 0x"));
		OO_CHECK(text.ends_with(">{\"Hull\" - diffuse map: tex:d.png,emission map: tex:e.png}"));
	}
	[m release];
	OO_CHECK(gTexturesDeallocated == deallocated + 2);

	@autoreleasepool
	{
		// No diffuse map (no name): only the emission map.
		gTextureConfigurations.clear();
		OOMultiTextureMaterial *emissive = [[[OOMultiTextureMaterial alloc] initWithName:std::nullopt configuration:oo::PList(oo::PList::Dict{ { "emission_map", oo::PList("e.png") } })] autorelease];
		OO_CHECK([emissive textureUnitCount] == 1);
#ifndef NDEBUG
		OO_CHECK([emissive cxx_allTextures].size() == 1);
#endif
		OO_CHECK(oo::DescriptionOf(emissive).ends_with(">{\"(null)\" - emission map: tex:e.png}"));
	}
}


OO_TEST(applyAndUnapply)
{
	if (!CombinersSupported())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		OOMultiTextureMaterial *two = Make("Two", { { "diffuse_map", oo::PList("d.png") }, { "emission_map", oo::PList("e.png") } });
		OOMultiTextureMaterial *one = Make("one.png", {});
#ifndef NDEBUG
		OOTexture *diffuse = [two cxx_allTextures][0].get(), *emission = [two cxx_allTextures][1].get();
#endif

		[two apply];
		OO_CHECK([OOMaterial current] == two);
#ifndef NDEBUG
		OO_CHECK(diffuse->_applies == 1 && emission->_applies == 1);
#endif
		OO_CHECK(TexEnvMode(GL_TEXTURE0_ARB) == GL_COMBINE_ARB && TexEnvMode(GL_TEXTURE1_ARB) == GL_COMBINE_ARB);
		GLint active = 0;
		glGetIntegerv(GL_ACTIVE_TEXTURE_ARB, &active);
		OO_CHECK(active == GL_TEXTURE0_ARB);

		// The next material uses two units: nothing to clear, and it is a basic material.
		int applyNones = gTextureApplyNones;
		[two unapplyWithNext:Make("Other", { { "diffuse_map", oo::PList("x.png") }, { "emission_map", oo::PList("y.png") } })];
		OO_CHECK(gTextureApplyNones == applyNones);

		// One unit: the second is cleared, back to modulate.
		[two unapplyWithNext:one];
		OO_CHECK(gTextureApplyNones == applyNones + 1 && TexEnvMode(GL_TEXTURE1_ARB) == GL_MODULATE);

		// Nothing: the default material (no texture), then both units cleared.
		applyNones = gTextureApplyNones;
		[OOMaterial applyNone];
		OO_CHECK(gTextureApplyNones == applyNones + 3 && TexEnvMode(GL_TEXTURE0_ARB) == GL_MODULATE);
		OO_CHECK([OOMaterial current] == nil);
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
		const oo::Ref<cxx::OOMultiTextureMaterial> m = cxx::OOMultiTextureMaterial::materialWithName(std::string("Cxx"), oo::PList(oo::PList::Dict{
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
		[static_cast<OOMaterial *>(oo::ToObjC(m)) apply];
#ifndef NDEBUG
		OO_CHECK(m->allTextures()[0].get()->_applies == 2);
#endif
		const int applyNones = gTextureApplyNones;
		cxx::OOMaterial::applyNone();
		OO_CHECK(gTextureApplyNones == applyNones + 3);
	}
}


OO_TEST(facade)
{
	if (!CombinersSupported())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		OOMultiTextureMaterial *made = Make("Made", {});
		cxx::OOMultiTextureMaterial *part = oo::ToCxx(made);
		OO_CHECK(part != nullptr && oo::AsObjCMaterial(part) == nullptr && oo::ToObjC(part) == made);
		OO_CHECK(oo::ToCxx(static_cast<OOBasicMaterial *>(made)) == part);

		const oo::Ref<cxx::OOMultiTextureMaterial> m = cxx::OOMultiTextureMaterial::materialWithName(std::string("Cxx"), oo::PList());
		OOMaterial *facade = oo::ToObjC(static_cast<cxx::OOMaterial *>(m.get()));
		OO_CHECK([facade isMemberOfClass:[OOMultiTextureMaterial class]] && oo::ToObjC(m) == facade);
		OO_CHECK([oo::ToObjC(m) textureUnitCount] == m->textureUnitCount());
		OO_CHECK(oo::DescriptionOf(facade).starts_with("<OOMultiTextureMaterial 0x"));

		OOMultiTextureMaterial *plain = [[[OOMultiTextureMaterial alloc] init] autorelease];
		OO_CHECK(plain != nil && [plain textureUnitCount] == 0);

		OOMultiTextureMaterial *none = nil;
		OO_CHECK(oo::ToCxx(none) == nullptr && oo::ToObjC(static_cast<cxx::OOMultiTextureMaterial *>(nullptr)) == nil);
	}
}

OO_TEST_MAIN()
