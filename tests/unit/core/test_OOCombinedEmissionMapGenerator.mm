/*	test_OOCombinedEmissionMapGenerator.mm
	Unit tests for OOCombinedEmissionMapGenerator (src/Core/Materials/OOCombinedEmissionMapGenerator.h),
	the texture generator that bakes a material's emission map, illumination map, diffuse map and
	their modulating colours into one emission texture: bead oo-e6xa (Phase 3, house style of
	proposed ADR-0056; a leaf of the texture generators, amendments oo-zl36 and oo-rr2x).

	It answers nil when there is nothing to bake, takes its texture options, anisotropy and LOD
	bias from the options specifier, keys its texture by what it combines, reads its source maps
	when it is made (unless a texture of its key exists), and bakes them on the work thread:
	emission tinted by its colour, plus illumination tinted by its colour and modulated by the
	diffuse map. Its source maps are PNGs the test writes under a scratch Resources/Textures, the
	current directory and HOMEPATH both pointed at the scratch folder first and the resource
	manager in strict mode (the built-in Resources alone), so no game resource and no add-on is
	read. It links the whole game but main (tests/unit/core/meson.build entry ['*']), on the
	hidden GL context of oo_gl_test_context.hpp. The expectations were written against the
	Objective-C API and run on the unconverted class first (commit 49fa6013a); that API is now the
	facade of cxx::OOCombinedEmissionMapGenerator (its caller's test stubs the class by name), so
	they run through it unchanged. The last test pins the C++ API and the crossing.
	Run: bash tools/check-core-tests.sh test_OOCombinedEmissionMapGenerator
*/

#import "OOCombinedEmissionMapGenerator.h"
#import "OOConcreteTexture.h"
#import "OOColor.h"
#import "OODescription.h"
#import "OOTextureInternal.h"
#import "ResourceManager.h"

#include "oo_test.hpp"
#include "oo_gl_test_context.hpp"

#include <png.h>

#include <process.h>
#include <stdlib.h>

#include <cstdlib>
#include <filesystem>
#include <string>
#include <vector>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


namespace {

namespace stdfs = std::filesystem;

stdfs::path sRoot;


// A size x size PNG of the given libpng format, every byte `fill`, as Resources/Textures/name.
bool WritePNG(const char *name, uint32_t size, png_uint_32 format, uint8_t fill)
{
	png_image image = {};
	image.version = PNG_IMAGE_VERSION;
	image.width = size;
	image.height = size;
	image.format = format;
	std::vector<uint8_t> bytes(PNG_IMAGE_SIZE(image), fill);
	const std::string path = (sRoot / "Resources" / "Textures" / name).generic_string();
	const bool written = png_image_write_to_file(&image, path.c_str(), 0, bytes.data(), 0, nullptr) != 0;
	png_image_free(&image);
	return written;
}


/*	The scratch folder (before the resource manager's first use), its maps, and the loaders'
	one-time set-up (a path with no known extension runs it, and answers nil).
	e.png: RGB 200; i.png: grey 100; d.png: RGB 128; c.png: RGBA 200 (emission .rgb, illumination .a).
*/
void SetUp()
{
	OO_CHECK(OOTestGLContext());
	if (sRoot.empty())
	{
		sRoot = stdfs::temp_directory_path() / ("oo-test-emission-" + std::to_string(static_cast<unsigned long>(::_getpid())));
		stdfs::remove_all(sRoot);
		stdfs::create_directories(sRoot / "Resources" / "Textures");
		OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
		stdfs::current_path(sRoot);
		OO_CHECK(WritePNG("e.png", 8, PNG_FORMAT_RGB, 200));
		OO_CHECK(WritePNG("i.png", 8, PNG_FORMAT_GRAY, 100));
		OO_CHECK(WritePNG("d.png", 8, PNG_FORMAT_RGB, 128));
		OO_CHECK(WritePNG("c.png", 8, PNG_FORMAT_RGBA, 200));
		[ResourceManager cxx_setUseAddOns:std::string(SCENARIO_OXP_DEFINITION_NONE)];	// strict: the built-in Resources alone
	}
	@autoreleasepool
	{
		(void)[OOTextureLoader cxx_loaderWithPath:std::string("unknown.type") options:0];
	}
}


// [[OOCombinedEmissionMapGenerator alloc] cxx_initWithEmissionMapSpec:...], autoreleased.
OOCombinedEmissionMapGenerator *NewGenerator(const oo::PList &emission, OOColor *emissionColor, OOTexture *diffuseMap, OOColor *diffuseColor,
											 const oo::PList &illumination, OOColor *illuminationColor, const oo::PList &options)
{
	return [[[OOCombinedEmissionMapGenerator alloc] cxx_initWithEmissionMapSpec:emission
																   emissionColor:emissionColor
																	  diffuseMap:diffuseMap
																	diffuseColor:diffuseColor
															 illuminationMapSpec:illumination
															   illuminationColor:illuminationColor
																optionsSpecifier:options] autorelease];
}


// [[OOCombinedEmissionMapGenerator alloc] cxx_initWithEmissionAndIlluminationMapSpec:...], autoreleased.
OOCombinedEmissionMapGenerator *NewCombinedGenerator(const oo::PList &map, OOTexture *diffuseMap, OOColor *diffuseColor,
													 OOColor *emissionColor, OOColor *illuminationColor)
{
	return [[[OOCombinedEmissionMapGenerator alloc] cxx_initWithEmissionAndIlluminationMapSpec:map
																					diffuseMap:diffuseMap
																				  diffuseColor:diffuseColor
																				 emissionColor:emissionColor
																			 illuminationColor:illuminationColor
																			  optionsSpecifier:map] autorelease];
}


// A map named by a string spec, as the generator keys it (it sets extra_shrink only in a dictionary).
std::string KeyOf(const char *name)
{
	return cxx_OOTextureCacheKeyForSpecifier(oo::PList(name));
}


struct Baked
{
	bool				ok = false;
	OOPixMap			pixMap = kOONullPixMap;
	OOTextureDataFormat	format = kOOPixMapInvalidFormat;

	~Baked()	{ OOFreePixMap(&pixMap); }

	const uint8_t *pixel() const	{ return (const uint8_t *)pixMap.pixels; }
};


void Bake(OOCombinedEmissionMapGenerator *generator, Baked &baked)
{
	OO_CHECK([generator enqueue]);
	baked.ok = [generator getResult:&baked.pixMap format:&baked.format originalWidth:NULL originalHeight:NULL];
}


// The diffuse map: d.png, loaded.
OOTexture *DiffuseMap()
{
	OOTexture *texture = [OOTexture cxx_textureWithName:std::string("d.png") inFolder:std::string("Textures")];
	[texture ensureFinishedLoading];
	return texture;
}


void ClearCache()
{
	@autoreleasepool
	{
		oo::AutoreleaseScope scope;
		[OOTexture clearCache];
	}
}

}	// namespace


OO_TEST(nothingToBake)
{
	SetUp();
	@autoreleasepool
	{
		OO_CHECK(NewGenerator(oo::PList(), nil, nil, nil, oo::PList(), [OOColor redColor], oo::PList("e.png")) == nil);
		OO_CHECK(NewCombinedGenerator(oo::PList(), nil, nil, nil, nil) == nil);
	}
}


OO_TEST(settingsFromTheOptionsSpecifier)
{
	SetUp();
	@autoreleasepool
	{
		const oo::PList options(oo::PList::Dict{ { "name", oo::PList("e.png") }, { "min_filter", oo::PList("nearest") },
												 { "anisotropy", oo::PList(0.5) }, { "texture_LOD_bias", oo::PList(-0.25) } });
		uint32_t expected = 0;
		float anisotropy = 0, lodBias = 0;
		OO_CHECK(cxx_OOInterpretTextureSpecifier(options, NULL, &expected, &anisotropy, &lodBias, YES));
		OOCombinedEmissionMapGenerator *generator = NewGenerator(oo::PList("e.png"), nil, nil, nil, oo::PList(), nil, options);
		OO_CHECK(generator != nil && [generator isKindOfClass:[OOTextureGenerator class]]);
		OO_CHECK([generator textureOptions] == OOApplyTextureOptionDefaults(expected));
		OO_CHECK([generator anisotropy] == anisotropy && [generator lodBias] == lodBias);
		OO_CHECK([generator cxx_path] == std::optional<std::string>("<generated emission map>"));
	}
}


OO_TEST(cacheKeys)
{
	SetUp();
	@autoreleasepool
	{
		OOColor *red = [OOColor redColor];
		const std::string redRGBA = [red cxx_rgbaDescription].value_or("");

		OO_CHECK([NewGenerator(oo::PList("e.png"), red, nil, nil, oo::PList(), nil, oo::PList("e.png")) cxx_cacheKey]
				 == std::optional<std::string>("emission map;emission:{" + KeyOf("e.png") + "}*" + redRGBA + ";"));
		// A white colour is no colour; the diffuse map is only used with illumination.
		OO_CHECK([NewGenerator(oo::PList("e.png"), [OOColor whiteColor], DiffuseMap(), nil, oo::PList(), nil, oo::PList("e.png")) cxx_cacheKey]
				 == std::optional<std::string>("emission map;emission:{" + KeyOf("e.png") + "};"));

		OOTexture *diffuse = DiffuseMap();
		const std::string diffuseKey = [diffuse cxx_cacheKey].value_or("");
		OO_CHECK(!diffuseKey.empty());
		// The illumination colour is the diffuse colour times the illumination colour.
		OO_CHECK([NewGenerator(oo::PList(), nil, diffuse, red, oo::PList("i.png"), [OOColor yellowColor], oo::PList("i.png")) cxx_cacheKey]
				 == std::optional<std::string>("illumination map;illumination:{" + KeyOf("i.png") + "}*{" + diffuseKey + "}*" + redRGBA + ";"));
		OO_CHECK([NewGenerator(oo::PList("e.png"), nil, nil, nil, oo::PList("i.png"), nil, oo::PList("e.png")) cxx_cacheKey]
				 == std::optional<std::string>("merged emission and illumination map;emission:{" + KeyOf("e.png") + "};illumination:{" + KeyOf("i.png") + "}*{};"));
		OO_CHECK([NewCombinedGenerator(oo::PList("c.png"), diffuse, nil, nil, nil) cxx_cacheKey]
				 == std::optional<std::string>("combined emission and illumination map;emission:{" + KeyOf("c.png") + "};illumination:{" + KeyOf("c.png") + ":a}*{" + diffuseKey + "};"));
	}
	ClearCache();
}


OO_TEST(bakesTheEmissionMap)
{
	SetUp();
	@autoreleasepool
	{
		// Emission alone, tinted (0.5, 1, 0.25).
		Baked baked;
		Bake(NewGenerator(oo::PList("e.png"), [OOColor colorWithRed:0.5f green:1.0f blue:0.25f alpha:1.0f], nil, nil, oo::PList(), nil, oo::PList("e.png")), baked);
		OO_CHECK(baked.ok && baked.format == kOOPixMapRGBA && baked.pixMap.width > 0 && baked.pixMap.width == baked.pixMap.height);
		OO_CHECK(baked.pixel()[0] == 100 && baked.pixel()[1] == 200 && baked.pixel()[2] == 50);
	}
	ClearCache();
}


OO_TEST(bakesTheIlluminationMap)
{
	SetUp();
	@autoreleasepool
	{
		// Illumination alone: grey 100 x the diffuse map's 128 (x a white colour, which is none).
		Baked illumination;
		Bake(NewGenerator(oo::PList(), nil, DiffuseMap(), nil, oo::PList("i.png"), nil, oo::PList("i.png")), illumination);
		OO_CHECK(illumination.ok && illumination.pixMap.width > 0);
		const uint8_t lit = illumination.pixel()[0];
		OO_CHECK(lit == 50 || lit == 51);

		// Emission plus illumination: added.
		Baked merged;
		Bake(NewGenerator(oo::PList("e.png"), nil, DiffuseMap(), nil, oo::PList("i.png"), nil, oo::PList("e.png")), merged);
		OO_CHECK(merged.ok && merged.format == kOOPixMapRGBA);
		OO_CHECK(merged.pixel()[0] == 200 + lit);

		// One map: its alpha (200) is the illumination, x the diffuse map; its colour the emission.
		Baked combined;
		Bake(NewCombinedGenerator(oo::PList("c.png"), DiffuseMap(), nil, nil, nil), combined);
		OO_CHECK(combined.ok && combined.format == kOOPixMapRGBA);
		OO_CHECK(combined.pixel()[0] == 255);	// 200 + ~100, saturated
	}
	ClearCache();
}


OO_TEST(aMissingMap)
{
	SetUp();
	@autoreleasepool
	{
		// Made (the spec names a map), but there is nothing to bake.
		OOCombinedEmissionMapGenerator *generator = NewGenerator(oo::PList("missing.png"), nil, nil, nil, oo::PList(), nil, oo::PList("missing.png"));
		OO_CHECK(generator != nil);
		Baked baked;
		Bake(generator, baked);
		OO_CHECK(!baked.ok && baked.pixMap.pixels == NULL);
	}
}


OO_TEST(aTextureOfTheGenerator)
{
	SetUp();
	@autoreleasepool
	{
		OOTexture *texture = [OOTexture textureWithGenerator:NewGenerator(oo::PList("e.png"), [OOColor redColor], nil, nil, oo::PList(), nil, oo::PList("e.png"))];
		OO_CHECK([texture isKindOfClass:[OOConcreteTexture class]]);
		[texture ensureFinishedLoading];
		OO_CHECK([texture isFinishedLoading] && [texture dimensions].width > 0);
		OO_CHECK([texture cxx_cacheKey] == [NewGenerator(oo::PList("e.png"), [OOColor redColor], nil, nil, oo::PList(), nil, oo::PList("e.png")) cxx_cacheKey]);

		// While that texture is cached, a generator of its key reads no map, so it bakes nothing.
		Baked baked;
		Bake(NewGenerator(oo::PList("e.png"), [OOColor redColor], nil, nil, oo::PList(), nil, oo::PList("e.png")), baked);
		OO_CHECK(!baked.ok);
	}
	ClearCache();
}


#ifndef NDEBUG
OO_TEST(description)
{
	SetUp();
	@autoreleasepool
	{
		const std::string description = oo::DescriptionOf(NewGenerator(oo::PList("e.png"), [OOColor redColor], nil, nil, oo::PList(), nil, oo::PList("e.png")));
		OO_CHECK(description.starts_with("<OOCombinedEmissionMapGenerator 0x"));
		OO_CHECK(description.find("{emission map: ") != std::string::npos);
		OO_CHECK(description.find(" * " + [[OOColor redColor] cxx_rgbaDescription].value_or("") + "}") != std::string::npos);
	}
}
#endif


// --- The C++ API (after the conversion) --------------------------------------------------------

OO_TEST(cxxApi)
{
	SetUp();
	@autoreleasepool
	{
		OO_CHECK(!cxx::OOCombinedEmissionMapGenerator::generatorWithEmissionMapSpec(oo::PList(), nullptr, nil, nullptr, oo::PList(), nullptr, oo::PList()));
		OO_CHECK(!cxx::OOCombinedEmissionMapGenerator::generatorWithEmissionAndIlluminationMapSpec(oo::PList(), nil, nullptr, nullptr, nullptr, oo::PList()));

		const oo::Ref<cxx::OOColor> red = cxx::OOColor::colorWithRGBAComponents((OORGBAComponents){ 1.0f, 0.0f, 0.0f, 1.0f });
		const oo::Ref<cxx::OOCombinedEmissionMapGenerator> generator = cxx::OOCombinedEmissionMapGenerator::generatorWithEmissionMapSpec(oo::PList("e.png"), red.get(), nil, nullptr, oo::PList(), nullptr, oo::PList("e.png"));
		OO_CHECK(generator && generator->cacheKey() == std::optional<std::string>("emission map;emission:{" + KeyOf("e.png") + "}*" + red->rgbaDescription().value_or("") + ";"));

		// Its facade is an OOCombinedEmissionMapGenerator, the same one each time, and back.
		OOCombinedEmissionMapGenerator *facade = oo::ToObjC(generator.get());
		OO_CHECK([facade class] == [OOCombinedEmissionMapGenerator class] && [facade isKindOfClass:[OOTextureGenerator class]]);
		OO_CHECK(oo::ToCxx(facade) == generator.get() && oo::ToObjC(generator.get()) == facade);
		OO_CHECK([facade cxx_cacheKey] == generator->cacheKey() && [facade textureOptions] == generator->textureOptions());

		// The facade's initialiser answers a C++ generator's facade.
		OOCombinedEmissionMapGenerator *made = NewGenerator(oo::PList("e.png"), nil, nil, nil, oo::PList(), nil, oo::PList("e.png"));
		OO_CHECK([made class] == [OOCombinedEmissionMapGenerator class] && dynamic_cast<cxx::OOCombinedEmissionMapGenerator *>(oo::ToCxx(made)) != nullptr);

		// Baking through the C++ object.
		generator->loadTexture();
		OO_CHECK(generator->_data != nullptr && generator->_format == kOOPixMapRGBA && ((const uint8_t *)generator->_data)[0] == 200 && ((const uint8_t *)generator->_data)[1] == 0);
	}
	ClearCache();
}


OO_TEST_MAIN()
