/*	test_OOTextureGenerator.mm
	Unit tests for OOTextureGenerator (src/Core/Materials/OOTextureGenerator.h), a texture loader
	that needs no file: bead oo-rr2x (Phase 3, house style of proposed ADR-0056; an intermediate
	class of the texture loaders, amendments oo-zl36 and oo-vl43).

	A generator chooses its own texture options, anisotropy, LOD bias and cache key, and queues
	itself on the game's work manager; OOPixMapTextureLoader and the planet, atmosphere and
	emission-map generators derive from it in their own files. The test's generators are
	Objective-C subclasses: a bare one that answers the class's defaults, and one that overrides
	them. It links the whole game but main (tests/unit/core/meson.build entry ['*']), on the hidden
	GL context of oo_gl_test_context.hpp. The expectations were written against the Objective-C API
	and run on the unconverted class first (commit 221196e7a); that API is now the facade, so they
	run through it, and the last tests pin the C++ API (cxx::OOTextureGenerator) and the crossing.
	Run: bash tools/check-core-tests.sh
*/

#import "OOTextureGenerator.h"
#import "OOConcreteTexture.h"
#import "OODescription.h"

#include "oo_test.hpp"
#include "oo_gl_test_context.hpp"

#include <cstdlib>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


static int gLoads = 0;


// A generator of an 8 x 8 RGBA image whose bytes count up from 1. Its root state is written in
// one block (the conversion of the loaders' root ported it; amendment oo-bj8 item 11).
@interface BareGenerator: OOTextureGenerator
@end

@implementation BareGenerator

- (void) loadTexture
{
	gLoads++;
	uint8_t *bytes = (uint8_t *)malloc(8 * 8 * 4);
	for (unsigned i = 0; i < 8 * 8 * 4; i++)  bytes[i] = (uint8_t)(i + 1);
	_cxxLoader->_data = bytes;
	_cxxLoader->_width = 8;
	_cxxLoader->_height = 8;
	_cxxLoader->_format = kOOPixMapRGBA;
}

@end


// A generator that chooses its own settings and cache key.
@interface ChoosyGenerator: BareGenerator
@end

@implementation ChoosyGenerator

- (uint32_t) textureOptions							{ return kOOTextureMinFilterNearest | kOOTextureMagFilterNearest; }
- (GLfloat) anisotropy								{ return 0.25f; }
- (GLfloat) lodBias									{ return 0.5f; }
- (std::optional<std::string>) cxx_cacheKey			{ return std::string("test:choosy"); }

@end


namespace {

// The loaders' sizes come from their one-time set-up, which a path with no known extension runs
// (and then answers nil, reading nothing).
void SetUpLoaders()
{
	@autoreleasepool
	{
		(void)[OOTextureLoader cxx_loaderWithPath:std::string("unknown.type") options:0];
	}
}


template <class G>
G *Generator(const char *path, uint32_t options)
{
	return [[[G alloc] cxx_initWithPath:std::string(path) options:options] autorelease];
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


OO_TEST(defaults)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	@autoreleasepool
	{
		BareGenerator *generator = Generator<BareGenerator>("bare generator", kOOTextureMinFilterLinear);
		OO_CHECK([generator textureOptions] == kOOTextureDefaultOptions);
		OO_CHECK([generator anisotropy] == (GLfloat)kOOTextureDefaultAnisotropy && [generator lodBias] == (GLfloat)kOOTextureDefaultLODBias);
		OO_CHECK(![generator cxx_cacheKey].has_value());	// a generator is not cached unless it says so
		OO_CHECK([generator cxx_path] == std::optional<std::string>("bare generator"));
		OO_CHECK([generator isKindOfClass:[OOTextureLoader class]]);
		OO_CHECK(oo::DescriptionOf(generator).ends_with(">{{bare generator -- loading}}"));
		OO_CHECK([[BareGenerator alloc] cxx_initWithPath:std::nullopt options:0] == nil);
	}
}


OO_TEST(enqueueLoadsOnTheWorkManager)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	@autoreleasepool
	{
		const int loads = gLoads;
		BareGenerator *generator = Generator<BareGenerator>("queued generator", kOOTextureMinFilterLinear);
		OO_CHECK([generator enqueue]);
		OOPixMap pixMap = kOONullPixMap;
		OOTextureDataFormat format = kOOPixMapInvalidFormat;
		uint32_t width = 0, height = 0;
		OO_CHECK([generator getResult:&pixMap format:&format originalWidth:&width originalHeight:&height]);
		OO_CHECK(gLoads == loads + 1 && [generator isReady]);
		OO_CHECK(pixMap.width == 8 && pixMap.height == 8 && width == 8 && format == kOOPixMapRGBA);
		OO_CHECK(((uint8_t *)pixMap.pixels)[0] == 1);
		OOFreePixMap(&pixMap);
	}
}


OO_TEST(aTextureTakesTheGeneratorsSettings)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	@autoreleasepool
	{
		ChoosyGenerator *generator = Generator<ChoosyGenerator>("choosy generator", 0);
		OO_CHECK([generator textureOptions] == (kOOTextureMinFilterNearest | kOOTextureMagFilterNearest));
		OO_CHECK([generator anisotropy] == 0.25f && [generator lodBias] == 0.5f);

		OOTexture *texture = [OOTexture textureWithGenerator:generator];
		OO_CHECK([texture isKindOfClass:[OOConcreteTexture class]]);
		OO_CHECK([texture cxx_cacheKey] == std::optional<std::string>("test:choosy"));
		OO_CHECK([OOTexture textureWithGenerator:generator] == texture);	// cached by the generator's key
		[texture ensureFinishedLoading];
		OO_CHECK([texture dimensions].width == 8 && ![texture isMipMapped]);	// nearest: no mip-maps
#ifndef NDEBUG
		OO_CHECK([texture cxx_name] == std::optional<std::string>("<ChoosyGenerator>"));
#endif
	}
	ClearCache();
}


// --- The C++ API and the crossing (after the conversion) -------------------------------------

// A converted generator, as OOPixMapTextureLoader will be one: a global C++ subclass.
class TestCxxGenerator final : public cxx::OOTextureGenerator
{
public:
	void loadTexture() override
	{
		loads++;
		uint8_t *bytes = (uint8_t *)malloc(8 * 8 * 4);
		for (unsigned i = 0; i < 8 * 8 * 4; i++)  bytes[i] = (uint8_t)(i + 1);
		_data = bytes;
		_width = 8;
		_height = 8;
		_format = kOOPixMapRGBA;
	}

	uint32_t textureOptions() override						{ return kOOTextureMinFilterLinear | kOOTextureMagFilterLinear; }
	std::optional<std::string> cacheKey() override			{ return std::string("test:cxxgen"); }

	int loads = 0;
};


OO_TEST(cxxApi)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	@autoreleasepool
	{
		const oo::Ref<TestCxxGenerator> generator = oo::makeRef<TestCxxGenerator>();
		OO_CHECK(generator->initWithPath(std::string("cxx generator"), 0));
		OO_CHECK(generator->anisotropy() == (GLfloat)kOOTextureDefaultAnisotropy && generator->lodBias() == (GLfloat)kOOTextureDefaultLODBias);

		// Its facade is an OOTextureGenerator (the nearest class with one), so a texture takes it.
		OOTextureGenerator *facade = oo::ToObjC(generator.get());
		OO_CHECK([facade isKindOfClass:[OOTextureGenerator class]] && oo::ToCxx(facade) == generator.get());
		OO_CHECK([facade textureOptions] == (kOOTextureMinFilterLinear | kOOTextureMagFilterLinear));
		OO_CHECK([facade cxx_cacheKey] == std::optional<std::string>("test:cxxgen"));
		OOTexture *texture = [OOTexture textureWithGenerator:facade];
		OO_CHECK([texture cxx_cacheKey] == std::optional<std::string>("test:cxxgen"));
		[texture ensureFinishedLoading];
		OO_CHECK(generator->loads == 1 && [texture dimensions].width == 8);

		// The bare class's own answers.
		const oo::Ref<cxx::OOTextureGenerator> bare = oo::makeRef<cxx::OOTextureGenerator>();
		OO_CHECK(bare->textureOptions() == kOOTextureDefaultOptions && !bare->cacheKey().has_value());
	}
	ClearCache();
}


OO_TEST(objCGeneratorBehindACxxPointer)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	@autoreleasepool
	{
		ChoosyGenerator *choosy = Generator<ChoosyGenerator>("choosy behind", 0);
		cxx::OOTextureGenerator *part = oo::ToCxx(choosy);
		OO_CHECK(part != nullptr && oo::ToObjC(part) == choosy);
		// The C++ part's virtual members reach the Objective-C overrides.
		OO_CHECK(part->textureOptions() == (kOOTextureMinFilterNearest | kOOTextureMagFilterNearest));
		OO_CHECK(part->anisotropy() == 0.25f && part->lodBias() == 0.5f);
		OO_CHECK(part->cacheKey() == std::optional<std::string>("test:choosy"));

		// A subclass that overrides none of them: the generator's own answers, not the loader's.
		BareGenerator *bare = Generator<BareGenerator>("bare behind", 0);
		cxx::OOTextureGenerator *barePart = oo::ToCxx(bare);
		OO_CHECK(barePart->textureOptions() == kOOTextureDefaultOptions && !barePart->cacheKey().has_value());
		const int loads = gLoads;
		OO_CHECK(barePart->enqueue());
		OOPixMap pixMap = kOONullPixMap;
		OOTextureDataFormat format = kOOPixMapInvalidFormat;
		OO_CHECK(barePart->getResult(&pixMap, &format, nullptr, nullptr) && gLoads == loads + 1);
		OOFreePixMap(&pixMap);
	}
}


OO_TEST(nilStaysNil)
{
	OOTextureGenerator *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOTextureGenerator *>(nullptr)) == nil);
	OO_CHECK([none textureOptions] == 0 && ![none enqueue]);
}


OO_TEST_MAIN()
