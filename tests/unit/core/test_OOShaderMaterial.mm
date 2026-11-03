/*	test_OOShaderMaterial.mm
	Unit tests for OOShaderMaterial (src/Core/Materials/OOShaderMaterial.h): bead oo-ja7y,
	converted after its superclass OOBasicMaterial (bead oo-vl43; proposed ADR-0056, amendments
	oo-smy and oo-vl43).

	A basic material with a GLSL program, textures and uniforms. The program, the uniforms, the
	textures and the resource manager are stand-ins that record what the material asks of them
	(amendment oo-z1s4 item 4), so this pins, through the Objective-C API its callers use (the
	convenience creators, OOPlanetEntity), what it computed before the conversion: which
	configurations name a shader material; how the program is asked for (sources or file names
	and the extensions tried, the macro prefix, the attribute bindings, the cache key) and when
	the material fails; which uniform each entry of the uniforms dictionary becomes (every type,
	bindings and the whitelist, random values under the target's seed, gloss and gamma
	defaults); the textures loaded or passed in; and -doApply, -unapplyWithNext:, the loading
	questions, -setBindingTarget:, -permitSpecular and the description. Those checks ran on the
	Objective-C class first and now run through the facade. After them: the C++ API (null where the
	initialiser answered nil), and the facade's class and identity.
	Run: bash tools/check-core-tests.sh
*/

#import "OOShaderMaterial.h"
#import "OOOpenGLExtensionManager.h"
#import "OODescription.h"
#import "OOObjCPList.h"
#import "legacy_random.h"

#include "oo_gl_test_context.hpp"
#include "oo_test.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OORuntime.h"

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


namespace {

// A PList as short text: a string, a number, or "-" for null.
std::string Text(const oo::PList &plist)
{
	if (plist.isNull())  return "-";
	if (const std::string *string = plist.getIf<std::string>())  return *string;
	return oo::DescriptionOf(plist);
}


std::string Text(const std::optional<std::string> &string)
{
	return string.value_or("(nil)");
}

}	// namespace


// The resource manager: the extension manager's two class methods, and shader files from a table.
static std::map<std::string, std::string> gShaderFiles;
static std::vector<std::string> gShaderFileRequests;

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
	gShaderFileRequests.push_back(folderName + "/" + fileName);
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


// Link stubs (amendment oo-zffj item 2), never reached here: OOTexture.mm's specifier of a map
// value (OOMaterialSpecifier.mm links it), and OOStringParsing.mm's parsers of a vector or
// quaternion written as a string (OOPListGameTypes.mm links them; OOStringParsing.mm links the game).
oo::PList cxx_OOTextureSpecFromObject(const oo::PList &, const std::optional<std::string> &)	{ std::abort(); }
BOOL cxx_ScanVectorFromString(const std::optional<std::string> &, Vector *)				{ std::abort(); }
BOOL cxx_ScanHPVectorFromString(const std::optional<std::string> &, HPVector *)			{ std::abort(); }
BOOL cxx_ScanQuaternionFromString(const std::optional<std::string> &, Quaternion *)		{ std::abort(); }


// The shader program: one request recorded per +shaderProgramWith...; a vertex source "fail" fails.
static std::vector<std::string> gProgramRequests;
static int gProgramApplies = 0;
static int gProgramApplyNones = 0;
static int gProgramsDeallocated = 0;

@interface OOShaderProgram: OOObject
+ (id) shaderProgramWithVertexShader:(const std::optional<std::string> &)vertexShaderSource
					  fragmentShader:(const std::optional<std::string> &)fragmentShaderSource
					vertexShaderName:(const std::optional<std::string> &)vertexShaderName
				  fragmentShaderName:(const std::optional<std::string> &)fragmentShaderName
							  prefix:(const std::optional<std::string> &)prefixString
				   attributeBindings:(const oo::PList &)attributeBindings
							cacheKey:(const std::optional<std::string> &)cacheKey;
- (void) apply;
+ (void) applyNone;
@end

@implementation OOShaderProgram

+ (id) shaderProgramWithVertexShader:(const std::optional<std::string> &)vertexShaderSource
					  fragmentShader:(const std::optional<std::string> &)fragmentShaderSource
					vertexShaderName:(const std::optional<std::string> &)vertexShaderName
				  fragmentShaderName:(const std::optional<std::string> &)fragmentShaderName
							  prefix:(const std::optional<std::string> &)prefixString
				   attributeBindings:(const oo::PList &)attributeBindings
							cacheKey:(const std::optional<std::string> &)cacheKey
{
	gProgramRequests.push_back("vs=" + Text(vertexShaderSource) + " fs=" + Text(fragmentShaderSource)
							   + " vsName=" + Text(vertexShaderName) + " fsName=" + Text(fragmentShaderName)
							   + " prefix=" + Text(prefixString) + " bindings=" + oo::DescriptionOf(attributeBindings)
							   + " key=" + Text(cacheKey));
	if (vertexShaderSource == std::optional<std::string>("fail"))  return nil;
	return [[[self alloc] init] autorelease];
}

- (void) dealloc	{ gProgramsDeallocated++; [super dealloc]; }
- (void) apply		{ gProgramApplies++; }
+ (void) applyNone	{ gProgramApplyNones++; }

@end


// The uniforms: each initialiser recorded as "name kind value"; the name "bad" fails.
static std::vector<std::string> gUniforms;
static int gUniformApplies = 0;
static std::vector<std::string> gUniformTargets;

@interface OOShaderUniform: OOObject
{
@public
	std::string	_name;
}
@end

@implementation OOShaderUniform

- (id) made:(const std::string &)name what:(const std::string &)what
{
	gUniforms.push_back(name + " " + what);
	if (name == "bad")
	{
		[self release];
		return nil;
	}
	self = [super init];
	_name = name;
	return self;
}

- (id)initWithName:(const std::string &)uniformName shaderProgram:(OOShaderProgram *)shaderProgram intValue:(GLint)constValue
{
	return [self made:uniformName what:"int " + std::to_string(constValue) + (shaderProgram != nil ? "" : " (no program)")];
}

- (id)initWithName:(const std::string &)uniformName shaderProgram:(OOShaderProgram *)shaderProgram floatValue:(GLfloat)constValue
{
	return [self made:uniformName what:oo::str::format("float %g", constValue)];
}

- (id)initWithName:(const std::string &)uniformName shaderProgram:(OOShaderProgram *)shaderProgram vectorValue:(GLfloat[4])constValue
{
	return [self made:uniformName what:oo::str::format("vector %g %g %g %g", constValue[0], constValue[1], constValue[2], constValue[3])];
}

- (id)initWithName:(const std::string &)uniformName shaderProgram:(OOShaderProgram *)shaderProgram quaternionValue:(Quaternion)constValue asMatrix:(BOOL)asMatrix
{
	return [self made:uniformName what:oo::str::format("quaternion %g %g %g %g %s", constValue.w, constValue.x, constValue.y, constValue.z, asMatrix ? "matrix" : "vector")];
}

- (id)initWithName:(const std::string &)uniformName
	 shaderProgram:(OOShaderProgram *)shaderProgram
	 boundToObject:(id<OOWeakReferenceSupport>)target
		  property:(SEL)selector
	convertOptions:(OOUniformConvertOptions)options
{
	return [self made:uniformName what:oo::str::format("binding %s options %u", sel_getName(selector), (unsigned)options)];
}

- (void) apply											{ gUniformApplies++; }
- (void) setBindingTarget:(id<OOWeakReferenceSupport>)target	{ gUniformTargets.push_back(_name + (target != nil ? " target" : " nil")); }
- (std::optional<std::string>) cxx_descriptionComponents	{ return _name; }

@end


// The textures: "missing" fails to load, and then the null texture stands in.
static int gTextureApplyNones = 0;
static int gTexturesDeallocated = 0;

@interface OOTexture: OOObject
{
@public
	std::string	_name;
	int			_applies;
	int			_ensures;
	BOOL		_finished;
}
+ (void) applyNone;
+ (id) cxx_textureWithConfiguration:(const oo::PList &)configuration;
+ (id) nullTexture;
- (void) apply;
- (void) ensureFinishedLoading;
- (BOOL) isFinishedLoading;
@end

@implementation OOTexture

+ (void) applyNone	{ gTextureApplyNones++; }

+ (id) cxx_textureWithConfiguration:(const oo::PList &)configuration
{
	if (configuration == oo::PList("missing"))  return nil;
	OOTexture *texture = [[[OOTexture alloc] init] autorelease];
	texture->_name = Text(configuration);
	texture->_finished = YES;
	return texture;
}

+ (id) nullTexture
{
	static OOTexture *null = nil;
	if (null == nil)
	{
		null = [[OOTexture alloc] init];
		null->_name = "null";
		null->_finished = YES;
	}
	return null;
}

- (void) dealloc						{ gTexturesDeallocated++; [super dealloc]; }
- (void) apply							{ _applies++; }
- (void) ensureFinishedLoading			{ _ensures++; }
- (BOOL) isFinishedLoading				{ return _finished; }

@end


// The binding whitelist, which the game implements elsewhere: everything but "forbidden".
BOOL OOUniformBindingPermitted(const std::string &propertyName, id bindingTarget)
{
	return propertyName != "forbidden";
}


// A binding target, with a seed for random uniforms.
@interface TestTarget: OOWeakRefObject
@end

@implementation TestTarget
- (uint32_t) randomSeedForShaders	{ return 12345; }
- (float) someBinding				{ return 1.0f; }
@end


// UNIVERSE is gSharedUniverse: nil, so not reduced detail and no shaders.
@class Universe;
Universe *gSharedUniverse = nil;


namespace {

GLint TextureUnits()
{
	return [[OOOpenGLExtensionManager sharedManager] textureImageUnitCount];
}


oo::PList Config(oo::PList::Dict dict)
{
	return oo::PList(std::move(dict));
}


const oo::PList kSources = Config({ { "_oo_vertex_shader_source", oo::PList("VS") }, { "_oo_fragment_shader_source", oo::PList("FS") } });


OOShaderMaterial *Make(const oo::PList &configuration, const oo::PList &macros = oo::PList(), id<OOWeakReferenceSupport> target = nil)
{
	gProgramRequests.clear();
	gUniforms.clear();
	gShaderFileRequests.clear();
	return [[[OOShaderMaterial alloc] initWithName:std::string("Shader") configuration:configuration macros:macros bindingTarget:target] autorelease];
}


oo::PList With(const oo::PList &base, oo::PList::Dict more)
{
	oo::PList::Dict dict = *base.getIf<oo::PList::Dict>();
	for (auto &entry : more)  dict[entry.first] = entry.second;
	return oo::PList(std::move(dict));
}

}	// namespace


OO_TEST(specifiesShaderMaterial)
{
	OO_CHECK(![OOShaderMaterial configurationDictionarySpecifiesShaderMaterial:oo::PList()]);
	OO_CHECK(![OOShaderMaterial configurationDictionarySpecifiesShaderMaterial:Config({})]);
	OO_CHECK([OOShaderMaterial configurationDictionarySpecifiesShaderMaterial:Config({ { "vertex_shader", oo::PList("v") } })]);
	OO_CHECK([OOShaderMaterial configurationDictionarySpecifiesShaderMaterial:Config({ { "_oo_vertex_shader_source", oo::PList("v") } })]);
	OO_CHECK([OOShaderMaterial configurationDictionarySpecifiesShaderMaterial:Config({ { "_oo_fragment_shader_source", oo::PList("f") } })]);
	OO_CHECK([OOShaderMaterial configurationDictionarySpecifiesShaderMaterial:Config({ { "vertex_shader", oo::PList(std::int64_t(3)) } })]);	// a number's string value
	// Only the vertex shader's name is asked, twice: a fragment shader name alone does not count.
	OO_CHECK(![OOShaderMaterial configurationDictionarySpecifiesShaderMaterial:Config({ { "fragment_shader", oo::PList("f") } })]);
	OO_CHECK(![OOShaderMaterial configurationDictionarySpecifiesShaderMaterial:Config({ { "vertex_shader", oo::PList(oo::PList::Array{}) } })]);
}


OO_TEST(programFromSources)
{
	if (!OOTestGLContext())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		const std::string units = std::to_string(TextureUnits());
		OOShaderMaterial *m = Make(kSources, Config({ { "A", oo::PList(std::int64_t(1)) }, { "B", oo::PList("two") } }));
		OO_CHECK(m != nil && [m cxx_name] == std::optional<std::string>("Shader"));
		const std::string prefix = "#define A  1\n#define B  two\n#define OO_TEXTURE_UNIT_COUNT  " + units + "\n\n\n";
		OO_CHECK(gProgramRequests.size() == 1);
		OO_CHECK(gProgramRequests[0] == "vs=VS fs=FS vsName=<synthesized> fsName=<synthesized> prefix=" + prefix
				 + " bindings=" + oo::DescriptionOf(Config({ { "tangent", oo::PList::signedInteger(15) } }))
				 + " key=$VERTEX:\nVS\n\n$FRAGMENT:\nFS\n\n$MACROS:\n" + prefix + "\n");
		OO_CHECK(gShaderFileRequests.empty());

		// No macros: only the unit count.
		m = Make(Config({ { "_oo_vertex_shader_source", oo::PList("VS") } }));
		OO_CHECK(m != nil && gProgramRequests.size() == 1);
		OO_CHECK(gProgramRequests[0].starts_with("vs=VS fs=(nil) vsName=<synthesized> fsName=(nil) prefix=#define OO_TEXTURE_UNIT_COUNT  " + units + "\n\n\n"));
		OO_CHECK(gProgramRequests[0].ends_with(" key=$VERTEX:\nVS\n\n$FRAGMENT:\n(null)\n\n$MACROS:\n#define OO_TEXTURE_UNIT_COUNT  " + units + "\n\n\n\n"));
	}
}


OO_TEST(programFromFiles)
{
	if (!OOTestGLContext())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		gShaderFiles = { { "hull.vertex", "VSRC" }, { "hull.fs.frag", "FSRC" }, { "plain.fragment", "PLAIN" } };

		// A name with no extension tries it bare, then .vertex (found). One with an unknown
		// extension tries it bare, then .fragment and .frag (found).
		OOShaderMaterial *m = Make(Config({ { "vertex_shader", oo::PList("hull") }, { "fragment_shader", oo::PList("hull.fs") } }));
		OO_CHECK(m != nil);
		OO_CHECK(gShaderFileRequests == (std::vector<std::string>{ "Shaders/hull", "Shaders/hull.vertex", "Shaders/hull.fs", "Shaders/hull.fs.fragment", "Shaders/hull.fs.frag" }));
		OO_CHECK(gProgramRequests.size() == 1 && gProgramRequests[0].starts_with("vs=VSRC fs=FSRC vsName=hull fsName=hull.fs prefix="));
		OO_CHECK(gProgramRequests[0].find(" key=$VERTEX:\nhull\n\n$FRAGMENT:\nhull.fs\n\n$MACROS:\n") != std::string::npos);

		// A name that has one of the two extensions is not extended.
		m = Make(Config({ { "fragment_shader", oo::PList("plain.fragment") } }));
		OO_CHECK(m != nil && gShaderFileRequests == (std::vector<std::string>{ "Shaders/plain.fragment" }));

		// A file that is not there: no material, and no program asked for.
		m = Make(Config({ { "vertex_shader", oo::PList("gone.vert") } }));
		OO_CHECK(m == nil && gProgramRequests.empty());
		OO_CHECK(gShaderFileRequests == (std::vector<std::string>{ "Shaders/gone.vert" }));
		gShaderFiles.clear();
	}
}


OO_TEST(failures)
{
	if (!OOTestGLContext())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		OO_CHECK(Make(oo::PList()) == nil);	// no configuration
		OO_CHECK(Make(Config({ { "gloss", oo::PList(0.5) } })) == nil && gProgramRequests.empty());	// no shader
		OO_CHECK(Make(With(kSources, { { "_oo_vertex_shader_source", oo::PList("fail") } })) == nil);	// no program
		OO_CHECK(gProgramRequests.size() == 1 && gUniforms.empty());
		OO_CHECK([OOShaderMaterial shaderMaterialWithName:std::string("S") configuration:oo::PList() macros:oo::PList() bindingTarget:nil] == nil);
		OOShaderMaterial *made = [OOShaderMaterial shaderMaterialWithName:std::string("S") configuration:kSources macros:oo::PList() bindingTarget:nil];
		OO_CHECK(made != nil && [made cxx_name] == std::optional<std::string>("S"));
	}
}


OO_TEST(uniformsFromTheConfiguration)
{
	if (!OOTestGLContext())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		TestTarget *target = [[[TestTarget alloc] init] autorelease];
		const RANROTSeed before = RANROTGetFullSeed();
		OOShaderMaterial *m = Make(With(kSources, { { "uniforms", Config({
			{ "a", oo::PList(1.5) },
			{ "b", Config({ { "type", oo::PList("int") }, { "value", oo::PList(std::int64_t(3)) } }) },
			{ "c", oo::PList("2.5") },
			{ "d", Config({ { "type", oo::PList("texture") }, { "value", oo::PList("1") } }) },
			{ "e", Config({ { "type", oo::PList("vector") }, { "value", oo::PList(oo::PList::Array{ oo::PList(1.0), oo::PList(2.0), oo::PList(3.0), oo::PList(4.0) }) } }) },
			{ "f", Config({ { "type", oo::PList("quaternion") }, { "value", oo::PList(oo::PList::Array{ oo::PList(1.0), oo::PList(0.0), oo::PList(0.0), oo::PList(0.0) }) }, { "asMatrix", oo::PList(false) } }) },
			{ "g", oo::PList("someBinding") },
			{ "h", Config({ { "binding", oo::PList("forbidden") } }) },
			{ "i", Config({ { "binding", oo::PList("someBinding") }, { "clamped", oo::PList(true) }, { "normalised", oo::PList(true) }, { "asMatrix", oo::PList(false) }, { "bindToSubentity", oo::PList(true) } }) },
			{ "j", Config({ { "type", oo::PList("bogus") } }) },
			{ "k", Config({ { "type", oo::PList("randomFloat") }, { "scale", oo::PList(2.0) } }) },
			{ "uGloss", oo::PList(0.25) },
		}) } }), oo::PList(), target);
		OO_CHECK(m != nil);

		// The random value is the target's seed's first draw, scaled; the seed is put back after.
		RANROTSeed seeded = RANROTGetFullSeed();
		ranrot_srand(12345);
		const float random = randf() * 2;
		RANROTSetFullSeed(seeded);
		OO_CHECK(RANROTGetFullSeed().high == before.high && RANROTGetFullSeed().low == before.low);

		const std::vector<std::string> expected = {
			"a float 1.5",
			"b int 3",
			"c float 2.5",
			"d int 1",
			"e vector 1 2 3 4",
			"f quaternion 1 0 0 0 vector",
			oo::str::format("g binding someBinding options %u", (unsigned)kOOUniformConvertDefaults),
			// h: forbidden, not bound. i: every option.
			oo::str::format("i binding someBinding options %u", (unsigned)(kOOUniformConvertClamp | kOOUniformConvertNormalize)),
			// j: could not interpret.
			oo::str::format("k float %g", random),
			"uGloss float 0.25",
			// No uGammaCorrect in the configuration: the default preference (gamma correction on).
			"uGammaCorrect float 1",
		};
		OO_CHECK(gUniforms == expected);

		// Without a target a binding is not made, and gloss comes from the configuration.
		m = Make(With(kSources, { { "uniforms", Config({ { "g", oo::PList("someBinding") } }) }, { "gloss", oo::PList(2.0) }, { "gamma_correct", oo::PList(false) } }));
		OO_CHECK(gUniforms == (std::vector<std::string>{ "uGloss float 1", "uGammaCorrect float 0" }));
	}
}


OO_TEST(settingUniforms)
{
	if (!OOTestGLContext())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		TestTarget *target = [[[TestTarget alloc] init] autorelease];
		OOShaderMaterial *m = Make(kSources);
		gUniforms.clear();
		[m setUniform:"i" intValue:7];
		[m setUniform:"f" floatValue:0.5f];
		GLfloat v[4] = { 1, 2, 3, 4 };
		[m setUniform:"v" vectorValue:v];
		[m setUniform:"o" vectorObjectValue:oo::PList(oo::PList::Array{ oo::PList(5.0), oo::PList(6.0), oo::PList(7.0), oo::PList(8.0) })];
		[m setUniform:"p" vectorObjectValue:oo::PList(oo::PList::Array{ oo::PList(1.0), oo::PList(2.0), oo::PList(3.0) })];	// a vector: w is 1
		[m setUniform:"q" quaternionValue:kIdentityQuaternion asMatrix:YES];
		OO_CHECK([m bindUniform:"b" toObject:target property:OOSelectorFromName("someBinding") convertOptions:kOOUniformConvertClamp]);
		OO_CHECK([m bindSafeUniform:"s" toObject:target propertyNamed:std::string("someBinding") convertOptions:0]);
		OO_CHECK(![m bindSafeUniform:"n" toObject:target propertyNamed:std::nullopt convertOptions:0]);
		OO_CHECK(![m bindSafeUniform:"x" toObject:target propertyNamed:std::string("forbidden") convertOptions:0]);
		OO_CHECK(![m bindUniform:"bad" toObject:target property:OOSelectorFromName("someBinding") convertOptions:0]);
		const std::vector<std::string> expected = {
			"i int 7", "f float 0.5", "v vector 1 2 3 4", "o vector 5 6 7 8", "p vector 1 2 3 1",
			"q quaternion 1 0 0 0 matrix",
			oo::str::format("b binding someBinding options %u", (unsigned)kOOUniformConvertClamp),
			"s binding someBinding options 0",
			oo::str::format("bad binding someBinding options %u", 0u),
		};
		OO_CHECK(gUniforms == expected);

		// Every uniform is told the binding target; a failed one ("bad") replaced nothing.
		gUniformTargets.clear();
		[m setBindingTarget:target];
		OO_CHECK(gUniformTargets.size() == 10);	// b f i o p q s v, uGammaCorrect, uGloss
		OO_CHECK(gUniformTargets.front() == "b target" && gUniformTargets.back() == "v target");
		[m setUniform:"bad" intValue:1];
		gUniformTargets.clear();
		[m setBindingTarget:nil];
		OO_CHECK(gUniformTargets.size() == 10 && gUniformTargets.front() == "b nil");
	}
}


OO_TEST(texturesApplyAndUnapply)
{
	if (!OOTestGLContext())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		OOShaderMaterial *m = Make(With(kSources, { { "textures", oo::PList(oo::PList::Array{ oo::PList("a.png"), oo::PList("missing"), oo::PList("c.png") }) } }));
#ifndef NDEBUG
		const std::vector<oo::ObjCRef<OOTexture *>> textures = [m cxx_allTextures];
		OO_CHECK(textures.size() == 3);
		OO_CHECK(textures[0].get()->_name == "a.png" && textures[1].get() == [OOTexture nullTexture] && textures[2].get()->_name == "c.png");
		OO_CHECK([m isFinishedLoading]);
		textures[2].get()->_finished = NO;
		OO_CHECK(![m isFinishedLoading]);
		[m ensureFinishedLoading];
		OO_CHECK(textures[0].get()->_ensures == 1 && textures[2].get()->_ensures == 1);
#endif

		const int programApplies = gProgramApplies, uniformApplies = gUniformApplies, applyNones = gTextureApplyNones;
		OO_CHECK([m doApply]);
		OO_CHECK(gProgramApplies == programApplies + 1 && gUniformApplies == uniformApplies + 2);	// uGloss, uGammaCorrect
		OO_CHECK(gTextureApplyNones == applyNones);	// not exactly a basic material
#ifndef NDEBUG
		OO_CHECK(textures[0].get()->_applies == 1 && textures[2].get()->_applies == 1);
#endif
		GLint active = 0;
		glGetIntegerv(GL_ACTIVE_TEXTURE_ARB, &active);
		OO_CHECK(active == GL_TEXTURE0_ARB);

		// Another shader material comes next: nothing to undo.
		const int programApplyNones = gProgramApplyNones;
		[m unapplyWithNext:Make(kSources)];
		OO_CHECK(gProgramApplyNones == programApplyNones && gTextureApplyNones == applyNones);

		// Anything else: no program, and each texture unit cleared (the superclass is not asked).
		[m unapplyWithNext:nil];
		OO_CHECK(gProgramApplyNones == programApplyNones + 1 && gTextureApplyNones == applyNones + 3);
		[m unapplyWithNext:[[[OOBasicMaterial alloc] cxx_initWithName:std::string("Basic")] autorelease]];
		OO_CHECK(gProgramApplyNones == programApplyNones + 2 && gTextureApplyNones == applyNones + 6);

		// No textures: one unit is still cleared.
		[Make(kSources) unapplyWithNext:nil];
		OO_CHECK(gTextureApplyNones == applyNones + 7);

		// Texture objects passed in are used as they are, and win over specifiers.
		OOTexture *given = [OOTexture cxx_textureWithConfiguration:oo::PList("given.png")];
		OOShaderMaterial *withObjects = Make(With(kSources, {
			{ "_oo_texture_objects", oo::PList(oo::PList::Array{ oo::PListObject(given) }) },
			{ "textures", oo::PList(oo::PList::Array{ oo::PList("a.png") }) },
		}));
#ifndef NDEBUG
		OO_CHECK([withObjects cxx_allTextures].size() == 1 && [withObjects cxx_allTextures][0].get() == given);
#endif
		(void)withObjects;
	}
}


OO_TEST(lifetimeAndDescription)
{
	if (!OOTestGLContext())  { OO_CHECK(false); return; }
	const int programs = gProgramsDeallocated, textures = gTexturesDeallocated;
	OOShaderMaterial *m = nil;
	@autoreleasepool
	{
		m = [Make(With(kSources, { { "textures", oo::PList(oo::PList::Array{ oo::PList("a.png") }) } })) retain];
	}
	OO_CHECK(gProgramsDeallocated == programs && gTexturesDeallocated == textures);
	@autoreleasepool
	{
		const std::string text = oo::DescriptionOf(m);
		OO_CHECK(text.starts_with("<OOShaderMaterial 0x") && text.ends_with(">{\"Shader\"}"));
		OO_CHECK([m permitSpecular]);
		[m apply];
		OO_CHECK([OOMaterial current] == m);
		[OOMaterial applyNone];
	}
	[m release];
	OO_CHECK(gProgramsDeallocated == programs + 1 && gTexturesDeallocated == textures + 1);

	@autoreleasepool
	{
		// Specular is always permitted: the exponent applies.
		OOShaderMaterial *shiny = Make(With(kSources, { { "specular_exponent", oo::PList(std::int64_t(20)) } }));
		OO_CHECK([shiny shininess] == 20);
	}
}


// --- The C++ class and the facade (after the conversion) -----------------------------------------

OO_TEST(cxxAPI)
{
	if (!OOTestGLContext())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		OO_CHECK(cxx::OOShaderMaterial::configurationDictionarySpecifiesShaderMaterial(kSources));
		OO_CHECK(!cxx::OOShaderMaterial::configurationDictionarySpecifiesShaderMaterial(oo::PList()));
		OO_CHECK(cxx::OOShaderMaterial::shaderMaterialWithName(std::string("S"), oo::PList(), oo::PList(), nil) == nullptr);

		gUniforms.clear();
		const oo::Ref<cxx::OOShaderMaterial> m = cxx::OOShaderMaterial::shaderMaterialWithName(std::string("Cxx"), kSources, oo::PList(), nil);
		OO_CHECK(m != nullptr && m->name() == std::optional<std::string>("Cxx") && m->permitSpecular());
		OO_CHECK(gUniforms == (std::vector<std::string>{ "uGloss float 0.5", "uGammaCorrect float 1" }));

		// The overloads each make the uniform the selector of their second keyword made.
		gUniforms.clear();
		m->setUniform("i", 7);
		m->setUniform("f", 0.5f);
		GLfloat v[4] = { 1, 2, 3, 4 };
		m->setUniform("v", v);
		m->setUniform("o", oo::PList(oo::PList::Array{ oo::PList(5.0), oo::PList(6.0), oo::PList(7.0), oo::PList(8.0) }));
		m->setUniform("q", kIdentityQuaternion, false);
		OO_CHECK(gUniforms == (std::vector<std::string>{ "i int 7", "f float 0.5", "v vector 1 2 3 4", "o vector 5 6 7 8", "q quaternion 1 0 0 0 vector" }));

		const int programApplies = gProgramApplies;
		m->apply();
		OO_CHECK(gProgramApplies == programApplies + 1 && cxx::OOMaterial::current().get() == m.get());
		const int programApplyNones = gProgramApplyNones;
		cxx::OOMaterial::applyNone();
		OO_CHECK(gProgramApplyNones == programApplyNones + 1);
	}
}


OO_TEST(facade)
{
	if (!OOTestGLContext())  { OO_CHECK(false); return; }
	@autoreleasepool
	{
		OOShaderMaterial *made = Make(kSources);
		cxx::OOShaderMaterial *part = oo::ToCxx(made);
		OO_CHECK(part != nullptr && oo::AsObjCMaterial(part) == nullptr && oo::ToObjC(part) == made);
		OO_CHECK(oo::ToCxx(static_cast<OOBasicMaterial *>(made)) == part);

		OOShaderMaterial *factoryMade = [OOShaderMaterial shaderMaterialWithName:std::string("F") configuration:kSources macros:oo::PList() bindingTarget:nil];
		OO_CHECK([factoryMade isMemberOfClass:[OOShaderMaterial class]] && oo::ToObjC(oo::ToCxx(factoryMade)) == factoryMade);

		const oo::Ref<cxx::OOShaderMaterial> m = cxx::OOShaderMaterial::shaderMaterialWithName(std::string("Cxx"), kSources, oo::PList(), nil);
		OOMaterial *facade = oo::ToObjC(static_cast<cxx::OOMaterial *>(m.get()));
		OO_CHECK([facade isMemberOfClass:[OOShaderMaterial class]] && oo::ToObjC(m) == facade);
		OO_CHECK(oo::DescriptionOf(facade).starts_with("<OOShaderMaterial 0x"));

		OOShaderMaterial *plain = [[[OOShaderMaterial alloc] init] autorelease];
		OO_CHECK(plain != nil && [plain isFinishedLoading]);

		OOShaderMaterial *none = nil;
		OO_CHECK(oo::ToCxx(none) == nullptr && oo::ToObjC(static_cast<cxx::OOShaderMaterial *>(nullptr)) == nil);
	}
}

OO_TEST_MAIN()
