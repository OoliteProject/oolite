/*	test_OOMaterialConvenienceCreators.mm
	Unit tests for OOMaterialConvenienceCreators (src/Core/Materials/OOMaterialConvenienceCreators.h):
	bead oo-9fwb.

	The two class methods that pick and make a material for a mesh from its configuration: a
	shader material (named in the configuration, or synthesized from the configuration's maps when
	shaders are on and the configuration asks for more than fixed function), a multitexture
	material for emission and illumination maps, a single-texture material, or a basic one. This
	pins, through the Objective-C API its caller (OOMesh) uses, which material each configuration
	gets under each universe setting, and the synthesized configuration itself as it is written to
	the cache, against the real material classes and GLSL programs compiled in a hidden GL context.
	The universe, the resource manager (shader files), the cache manager, the textures and the
	emission-map generator are stand-ins (proposed ADR-0056 amendment oo-z1s4 item 4).
	Those checks ran on the Objective-C category first and now run through its forwarders; after
	them, the same choices through the C++ static members (ADR-0056 amendment oo-9fwb).
	Run: bash tools/check-core-tests.sh
*/

#import "OOMaterialConvenienceCreators.h"
#import "OOBasicMaterial.h"
#import "OOSingleTextureMaterial.h"
#import "OOMultiTextureMaterial.h"
#import "OOShaderMaterial.h"
#import "OOOpenGLExtensionManager.h"
#import "OODescription.h"

#include "oo_gl_test_context.hpp"
#include "oo_test.hpp"
#include "oofnd/String.hpp"

#include <cstdlib>
#include <map>
#include <string>
#include <vector>


// --- Stubs --------------------------------------------------------------------------------------

// OOLogging.mm's (it would bring the resource manager into the link).
void OOLogGenericSubclassResponsibilityForFunction(const char *inFunction)	{ (void)inFunction; }
void OOLogGenericParameterErrorForFunction(const char *inFunction)			{ (void)inFunction; }
void OOLogIndent(void)  {}
void OOLogOutdent(void)  {}
const char *const cxx_kOOLogFileNotFound = "files.notFound";
uint32_t gDebugFlags = 0;


// Link stubs (amendment oo-zffj item 2), never reached here: OOStringParsing.mm's parsers of a
// vector or quaternion written as a string (OOPListGameTypes.mm links them).
BOOL cxx_ScanVectorFromString(const std::optional<std::string> &, Vector *)				{ std::abort(); }
BOOL cxx_ScanHPVectorFromString(const std::optional<std::string> &, HPVector *)			{ std::abort(); }
BOOL cxx_ScanQuaternionFromString(const std::optional<std::string> &, Quaternion *)		{ std::abort(); }


// The binding whitelist, which the game implements elsewhere: everything.
BOOL OOUniformBindingPermitted(const std::string &propertyName, id bindingTarget)	{ return YES; }


// The resource manager: the extension manager's two class methods, and shader files from a table.
static std::map<std::string, std::string> gShaderFiles;

@interface ResourceManager: OOObject
+ (std::vector<std::string>) cxx_paths;
+ (oo::PList) cxx_dictionaryFromFilesNamed:(const std::string &)fileName inFolder:(const std::string &)folderName andMerge:(BOOL)mergeFiles;
+ (std::optional<std::string>) cxx_stringFromFilesNamed:(const std::string &)fileName inFolder:(const std::string &)folderName;
@end

@implementation ResourceManager
+ (std::vector<std::string>) cxx_paths  { return {}; }
+ (oo::PList) cxx_dictionaryFromFilesNamed:(const std::string &)fileName inFolder:(const std::string &)folderName andMerge:(BOOL)mergeFiles  { return oo::PList(oo::PList::Dict{}); }
+ (std::optional<std::string>) cxx_stringFromFilesNamed:(const std::string &)fileName inFolder:(const std::string &)folderName
{
	auto found = gShaderFiles.find(fileName);
	if (found == gShaderFiles.end())  return std::nullopt;
	return found->second;
}
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


// The cache manager: the synthesized configurations, by key, as they are written and read.
static std::map<std::string, oo::PList> gCache;
static std::vector<std::string> gCacheWrites;

@interface OOCacheManager: OOObject
+ (OOCacheManager *) sharedCache;
- (oo::PList)cxx_pListForKey:(const std::string &)key inCache:(const std::string &)cache;
- (void)cxx_setPList:(const oo::PList &)value forKey:(const std::string &)key inCache:(const std::string &)cache;
@end

@implementation OOCacheManager
+ (OOCacheManager *) sharedCache
{
	static OOCacheManager *shared = nil;
	if (shared == nil)  shared = [[OOCacheManager alloc] init];
	return shared;
}
- (oo::PList)cxx_pListForKey:(const std::string &)key inCache:(const std::string &)cache
{
	auto found = gCache.find(cache + "|" + key);
	return found != gCache.end() ? found->second : oo::PList();
}
- (void)cxx_setPList:(const oo::PList &)value forKey:(const std::string &)key inCache:(const std::string &)cache
{
	gCacheWrites.push_back(cache + "|" + key);
	gCache[cache + "|" + key] = value;
}
@end


// The textures: any configuration but "missing" loads; a name with no configuration loads unless "missing".
@interface OOTexture: OOObject
{
@public
	oo::PList	_configuration;
}
+ (void) applyNone;
+ (id) cxx_textureWithConfiguration:(const oo::PList &)configuration;
+ (id) cxx_textureWithConfiguration:(const oo::PList &)configuration extraOptions:(uint32_t)extraOptions;
+ (id) cxx_textureWithName:(const std::optional<std::string> &)name inFolder:(const std::optional<std::string> &)directory;
+ (id) textureWithGenerator:(id)generator;
+ (id) nullTexture;
- (void) apply;
- (void) ensureFinishedLoading;
- (BOOL) isFinishedLoading;
- (BOOL) isCubeMap;
@end

@implementation OOTexture
+ (void) applyNone	{}
+ (id) cxx_textureWithConfiguration:(const oo::PList &)configuration
{
	return [self cxx_textureWithConfiguration:configuration extraOptions:0];
}
+ (id) cxx_textureWithConfiguration:(const oo::PList &)configuration extraOptions:(uint32_t)extraOptions
{
	if (configuration.isNull() || configuration == oo::PList("missing"))  return nil;
	OOTexture *texture = [[[OOTexture alloc] init] autorelease];
	texture->_configuration = configuration;
	return texture;
}
+ (id) cxx_textureWithName:(const std::optional<std::string> &)name inFolder:(const std::optional<std::string> &)directory
{
	if (!name.has_value() || *name == "missing")  return nil;
	return [self cxx_textureWithConfiguration:oo::PList(*name)];
}
+ (id) textureWithGenerator:(id)generator	{ return generator != nil ? [self cxx_textureWithConfiguration:oo::PList("generated")] : nil; }
+ (id) nullTexture							{ return [self cxx_textureWithConfiguration:oo::PList("null")]; }
- (void) apply								{}
- (void) ensureFinishedLoading				{}
- (BOOL) isFinishedLoading					{ return YES; }
- (BOOL) isCubeMap							{ return NO; }
@end


@interface OOCombinedEmissionMapGenerator: OOObject
@end

@implementation OOCombinedEmissionMapGenerator
- (id) cxx_initWithEmissionMapSpec:(const oo::PList &)emissionMapSpec emissionColor:(OOColor *)emissionColor diffuseMap:(OOTexture *)diffuseMap diffuseColor:(OOColor *)diffuseColor illuminationMapSpec:(const oo::PList &)illuminationMapSpec illuminationColor:(OOColor *)illuminationColor optionsSpecifier:(const oo::PList &)spec
{
	if (emissionMapSpec.isNull() && illuminationMapSpec.isNull())
	{
		[self release];
		return nil;
	}
	return [super init];
}
- (id) cxx_initWithEmissionAndIlluminationMapSpec:(const oo::PList &)emissionAndIlluminationMapSpec diffuseMap:(OOTexture *)diffuseMap diffuseColor:(OOColor *)diffuseColor emissionColor:(OOColor *)emissionColor illuminationColor:(OOColor *)illuminationColor optionsSpecifier:(const oo::PList &)spec
{
	return [super init];
}
@end


// OOTexture.mm's specifier of a map value: the value itself, or the default name, or none.
oo::PList cxx_OOTextureSpecFromObject(const oo::PList &object, const std::optional<std::string> &defaultName)
{
	if (!object.isNull())  return object;
	return defaultName.has_value() ? oo::PList(*defaultName) : oo::PList();
}


// The universe: the three settings the creators and the materials ask about.
@class Universe;
Universe *gSharedUniverse = nil;

@interface TestUniverse: OOObject
{
@public
	BOOL				_useShaders;
	BOOL				_reducedDetail;
	OOGraphicsDetail	_detailLevel;
}
- (BOOL) useShaders;
- (BOOL) reducedDetail;
- (OOGraphicsDetail) detailLevel;
@end

@implementation TestUniverse
- (BOOL) useShaders					{ return _useShaders; }
- (BOOL) reducedDetail				{ return _reducedDetail; }
- (OOGraphicsDetail) detailLevel	{ return _detailLevel; }
@end


namespace {

TestUniverse *gUniverse = nil;

const char *kVertex = "void main() { gl_Position = gl_Vertex; }\n";
const char *kFragment = "uniform sampler2D uDiffuseMap;\nvoid main() { gl_FragColor = texture2D(uDiffuseMap, vec2(0.0)); }\n";


bool SetUp(BOOL useShaders, OOGraphicsDetail detail = DETAIL_LEVEL_MINIMUM)
{
	if (!OOTestGLContext())  return false;
	[OOOpenGLExtensionManager sharedManager];
	if (gUniverse == nil)  gUniverse = [[TestUniverse alloc] init];
	gUniverse->_useShaders = useShaders;
	gUniverse->_detailLevel = detail;
	gUniverse->_reducedDetail = NO;
	gSharedUniverse = (Universe *)gUniverse;
	gShaderFiles = {
		{ "oolite-tangent-space-vertex.vertex", kVertex },
		{ "oolite-default-shader.fragment", kFragment },
		{ "named.vertex", kVertex },
		{ "named.fragment", kFragment },
	};
	gCache.clear();
	gCacheWrites.clear();
	return true;
}


OOMaterial *Make(const char *name, oo::PList::Dict config, BOOL smooth = NO, const std::optional<std::string> &cacheKey = std::nullopt)
{
	return [OOMaterial materialWithName:(name != nullptr ? std::optional<std::string>(name) : std::nullopt)
							   cacheKey:cacheKey
						  configuration:oo::PList(std::move(config))
								 macros:oo::PList()
						  bindingTarget:nil
						forSmoothedMesh:smooth];
}


bool Is(OOMaterial *material, Class cls)
{
	return material != nil && [material isMemberOfClass:cls];
}

}	// namespace


OO_TEST(withoutShaders)
{
	if (!SetUp(NO))  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		// A diffuse map (named, or the material's own name): one texture.
		OO_CHECK(Is(Make("hull.png", {}), [OOSingleTextureMaterial class]));
		OO_CHECK(Is(Make("hull.png", { { "diffuse_map", oo::PList("d.png") } }), [OOSingleTextureMaterial class]));
		// With no name the single-texture initialiser fails (it needs one), so basic (observed on the
		// Objective-C category before its conversion).
		OO_CHECK(Is(Make(nullptr, { { "diffuse_map", oo::PList("d.png") } }), [OOBasicMaterial class]));
		// No diffuse map: basic; one that fails to load: basic too.
		OO_CHECK(Is(Make(nullptr, {}), [OOBasicMaterial class]));
		OO_CHECK(Is(Make("missing", {}), [OOBasicMaterial class]));
		// Emission or illumination maps: multitexture, when the combiners are there (they are).
		OO_CHECK(Is(Make("hull.png", { { "emission_map", oo::PList("e.png") } }), [OOMultiTextureMaterial class]));
		OO_CHECK(Is(Make("hull.png", { { "illumination_map", oo::PList("i.png") } }), [OOMultiTextureMaterial class]));
		OO_CHECK(Is(Make("hull.png", { { "emission_and_illumination_map", oo::PList("ei.png") } }), [OOMultiTextureMaterial class]));
		// A shader configuration without shaders: its fixed-function equivalent.
		OO_CHECK(Is(Make("hull.png", { { "vertex_shader", oo::PList("named") } }), [OOSingleTextureMaterial class]));
		OO_CHECK([Make("Named", {}) cxx_name] == std::optional<std::string>("Named"));
	}
}


OO_TEST(namedShaders)
{
	if (!SetUp(YES))  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		OOMaterial *m = Make("hull.png", { { "vertex_shader", oo::PList("named") }, { "fragment_shader", oo::PList("named") } });
		OO_CHECK(Is(m, [OOShaderMaterial class]));
		OO_CHECK(gCacheWrites.empty());

		// A shader that fails, at low detail and not smoothed: the fixed-function material.
		m = Make("hull.png", { { "vertex_shader", oo::PList("absent") } });
		OO_CHECK(Is(m, [OOSingleTextureMaterial class]));
	}
}


OO_TEST(synthesizedShaders)
{
	if (!SetUp(YES, DETAIL_LEVEL_SHADERS))  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		// Full shader detail: the configuration is synthesized into a shader material, and the
		// synthesized configuration is cached under the cache key, the name and the configuration.
		OOMaterial *m = Make("hull.png", { { "emission_map", oo::PList("e.png") } }, NO, std::string("ship"));
		OO_CHECK(Is(m, [OOShaderMaterial class]));
		OO_CHECK(gCacheWrites.size() == 1 && gCacheWrites[0].starts_with("synthesized shader materials|ship/hull.png/"));

		const oo::PList &config = gCache.begin()->second;
		OO_CHECK(config.get<std::string>("_oo_is_synthesized_config") == "true");
		OO_CHECK(config.get<std::string>("vertex_shader") == "oolite-tangent-space-vertex.vertex");
		OO_CHECK(config.get<std::string>("fragment_shader") == "oolite-default-shader.fragment");
		OO_CHECK(config.get<std::string>("diffuse_map") == "hull.png");
		const oo::PList *textures = config.find("textures");
		OO_CHECK(textures != nullptr && *textures == oo::PList(oo::PList::Array{ oo::PList("hull.png"), oo::PList("e.png") }));
		const oo::PList *uniforms = config.find("uniforms");
		OO_CHECK(uniforms != nullptr);
		OO_CHECK(uniforms->find("uDiffuseMap") != nullptr && *uniforms->find("uDiffuseMap") == oo::PList(oo::PList::Dict{ { "type", oo::PList("texture") }, { "value", oo::PList::unsignedInteger(0) } }));
		OO_CHECK(uniforms->find("uEmissionMap") != nullptr && *uniforms->find("uEmissionMap") == oo::PList(oo::PList::Dict{ { "type", oo::PList("texture") }, { "value", oo::PList::unsignedInteger(1) } }));
		OO_CHECK(uniforms->get<std::string>("uHullHeatLevel") == "hullHeatLevel" && uniforms->get<std::string>("uTime") == "timeElapsedSinceSpawn");
		OO_CHECK(uniforms->get<std::string>("uFogColor") == "fogUniform");
		const oo::PList *macros = config.find("_oo_synthesized_material_macros");
		OO_CHECK(macros != nullptr && macros->get<std::string>("OOSTD_DIFFUSE_MAP") == "1" && macros->get<std::string>("OOSTD_EMISSION_MAP") == "1");
		OO_CHECK(macros->get<std::string>("OOSTD_SPECULAR") == "1");	// the default exponent (10) and colour

		// Asked again: read from the cache, not written.
		gCacheWrites.clear();
		OO_CHECK(Is(Make("hull.png", { { "emission_map", oo::PList("e.png") } }, NO, std::string("ship")), [OOShaderMaterial class]));
		OO_CHECK(gCacheWrites.empty());

		// No cache key: synthesized, not cached.
		OO_CHECK(Is(Make("hull.png", {}), [OOShaderMaterial class]) && gCacheWrites.empty());
	}
}


OO_TEST(synthesisTriggersAndLoops)
{
	if (!SetUp(YES, DETAIL_LEVEL_MINIMUM))  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		// Low detail: fixed function, unless smoothed or a map needs the shader.
		OO_CHECK(Is(Make("hull.png", {}), [OOSingleTextureMaterial class]));
		OO_CHECK(Is(Make("hull.png", {}, YES), [OOShaderMaterial class]));
		OO_CHECK(Is(Make("hull.png", { { "normal_map", oo::PList("n.png") } }), [OOShaderMaterial class]));
		OO_CHECK(Is(Make("hull.png", { { "specular_map", oo::PList("s.png") } }), [OOShaderMaterial class]));

		/*	The synthesized shaders fail to build: no loop, and the fixed-function material of the
			synthesized configuration, which the inner call makes. That configuration keeps only the
			diffuse map outside its shader textures, so an emission map is dropped and the material
			is single-texture, not multitexture (observed on the Objective-C category before its
			conversion).
		*/
		gShaderFiles.erase("oolite-default-shader.fragment");
		OO_CHECK(Is(Make("hull.png", {}, YES), [OOSingleTextureMaterial class]));
		OO_CHECK(Is(Make("hull.png", { { "emission_map", oo::PList("e.png") } }, YES), [OOSingleTextureMaterial class]));
		// Without the smoothing that forces the shader, at low detail, the emission map still asks for
		// the shader, and the result is the same.
		OO_CHECK(Is(Make("hull.png", { { "emission_map", oo::PList("e.png") } }), [OOSingleTextureMaterial class]));
	}
}


OO_TEST(fromDictionaries)
{
	if (!SetUp(YES))  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		const oo::PList materials = oo::PList(oo::PList::Dict{ { "hull.png", oo::PList(oo::PList::Dict{ { "diffuse_map", oo::PList("m.png") } }) } });
		const oo::PList shaders = oo::PList(oo::PList::Dict{ { "hull.png", oo::PList(oo::PList::Dict{ { "vertex_shader", oo::PList("named") }, { "fragment_shader", oo::PList("named") } }) } });

		auto make = [&](const char *name, const oo::PList &m, const oo::PList &s)
		{
			return [OOMaterial materialWithName:std::string(name) cacheKey:std::nullopt materialDictionary:m shadersDictionary:s macros:oo::PList() bindingTarget:nil forSmoothedMesh:NO];
		};

		// With shaders, the shaders dictionary's entry; without, the materials dictionary's.
		OO_CHECK(Is(make("hull.png", materials, shaders), [OOShaderMaterial class]));
		gUniverse->_useShaders = NO;
		OOMaterial *m = make("hull.png", materials, shaders);
		OO_CHECK(Is(m, [OOSingleTextureMaterial class]));
		// Neither: an empty configuration if the texture of that name loads, else nothing.
		OO_CHECK(Is(make("other.png", materials, shaders), [OOSingleTextureMaterial class]));
		OO_CHECK(make("missing", materials, shaders) == nil);
		OO_CHECK(make("missing", oo::PList(), oo::PList()) == nil);
	}
}


// --- The C++ static members (after the conversion) -------------------------------------------------

namespace {

bool IsCxx(const oo::Ref<cxx::OOMaterial> &material, Class cls)
{
	return material != nullptr && [oo::ToObjC(material) isMemberOfClass:cls];
}

oo::Ref<cxx::OOMaterial> MakeCxx(const char *name, oo::PList::Dict config, bool smooth = false, const std::optional<std::string> &cacheKey = std::nullopt)
{
	return cxx::OOMaterial::materialWithName(name != nullptr ? std::optional<std::string>(name) : std::nullopt,
											 cacheKey, oo::PList(std::move(config)), oo::PList(), nil, smooth);
}

}	// namespace


OO_TEST(cxxStaticMembers)
{
	if (!SetUp(NO))  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		OO_CHECK(IsCxx(MakeCxx("hull.png", {}), [OOSingleTextureMaterial class]));
		OO_CHECK(IsCxx(MakeCxx(nullptr, {}), [OOBasicMaterial class]));
		OO_CHECK(IsCxx(MakeCxx("hull.png", { { "emission_map", oo::PList("e.png") } }), [OOMultiTextureMaterial class]));
		OO_CHECK(MakeCxx("Named", {})->name() == std::optional<std::string>("Named"));
	}

	if (!SetUp(YES, DETAIL_LEVEL_SHADERS))  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		OO_CHECK(IsCxx(MakeCxx("hull.png", { { "emission_map", oo::PList("e.png") } }, false, std::string("ship")), [OOShaderMaterial class]));
		OO_CHECK(gCacheWrites.size() == 1);

		const oo::PList materials = oo::PList(oo::PList::Dict{ { "hull.png", oo::PList(oo::PList::Dict{ { "diffuse_map", oo::PList("m.png") } }) } });
		const oo::PList shaders = oo::PList(oo::PList::Dict{ { "hull.png", oo::PList(oo::PList::Dict{ { "vertex_shader", oo::PList("named") }, { "fragment_shader", oo::PList("named") } }) } });
		OO_CHECK(IsCxx(cxx::OOMaterial::materialWithName(std::string("hull.png"), std::nullopt, materials, shaders, oo::PList(), nil, false), [OOShaderMaterial class]));
		OO_CHECK(cxx::OOMaterial::materialWithName(std::string("missing"), std::nullopt, oo::PList(), oo::PList(), oo::PList(), nil, false) == nullptr);

		// The facade's class method answers the same kind as the static member it forwards to.
		OO_CHECK(Is(Make("hull.png", {}, YES), [OOShaderMaterial class]) && IsCxx(MakeCxx("hull.png", {}, true), [OOShaderMaterial class]));
	}
}


OO_TEST_MAIN()
