/*	test_OOTextureGenerator.mm
	Unit tests for OOTextureGenerator (src/Core/Materials/OOTextureGenerator.h), a texture loader
	that needs no file: bead oo-rr2x (Phase 3, house style of proposed ADR-0056; an intermediate
	class of the texture loaders, amendments oo-zl36 and oo-vl43).

	A generator chooses its own texture options, anisotropy, LOD bias and cache key, and queues
	itself on the game's work manager; OOPixMapTextureLoader and the planet, atmosphere and
	emission-map generators derive from it in their own files. The test's generators are
	subclasses (Objective-C until bead oo-9ht.118 deleted the facade; C++ now, named as they were):
	a bare one that answers the class's defaults, and one that overrides them. It links the whole
	game but main (tests/unit/core/meson.build entry ['*']), on the hidden GL context of
	oo_gl_test_context.hpp. The expectations were written against the Objective-C API
	and run on the unconverted class first (commit 221196e7a). Bead oo-9ht.118 deleted the facade:
	its crossing cases went with it (standing approval oo-9n5p9), and the other cases call the same
	members with every expectation kept; the last test pins the C++ API (OOTextureGenerator).
	Run: bash tools/check-core-tests.sh
*/

#include "OOTextureGenerator.h"
#include "OOConcreteTexture.h"
#include "OODescription.h"

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
class BareGenerator : public OOTextureGenerator
{
public:
	void loadTexture() override
	{
		gLoads++;
		uint8_t *bytes = (uint8_t *)malloc(8 * 8 * 4);
		for (unsigned i = 0; i < 8 * 8 * 4; i++)  bytes[i] = (uint8_t)(i + 1);
		_data = bytes;
		_width = 8;
		_height = 8;
		_format = kOOPixMapRGBA;
	}
};


// A generator that chooses its own settings and cache key.
class ChoosyGenerator : public BareGenerator
{
public:
	uint32_t textureOptions() override					{ return kOOTextureMinFilterNearest | kOOTextureMagFilterNearest; }
	GLfloat anisotropy() override						{ return 0.25f; }
	GLfloat lodBias() override							{ return 0.5f; }
	std::optional<std::string> cacheKey() override		{ return std::string("test:choosy"); }
};



// What an autoreleased Objective-C texture was (bead oo-9ht.99 deleted the facade): the C++
// texture, kept until the current autorelease scope drains (oo::autorelease; an Objective-C
// keeper object until bead oo-4aq6a.2).
static OOTexture *Autoreleased(const oo::Ref<OOTexture> &texture)
{
	if (texture == nullptr)  return nullptr;
	oo::autorelease(oo::Ref<OOTexture>(texture));
	return texture.get();
}


namespace {

// The loaders' sizes come from their one-time set-up, which a path with no known extension runs
// (and then answers nil, reading nothing).
void SetUpLoaders()
{
	{
		oo::AutoreleaseScope pool;
		(void)OOTextureLoader::loaderWithPath(std::string("unknown.type"), 0);
	}
}


// The generators made, kept for the test's life (each was autoreleased in its case's pool).
std::vector<oo::Ref<OOTextureGenerator>> gKeptGenerators;


template <class G>
G *Generator(const char *path, uint32_t options)
{
	const oo::Ref<G> made = oo::makeRef<G>();
	if (!made->initWithPath(std::string(path), options))  return nullptr;
	gKeptGenerators.push_back(made);
	return made.get();
}


void ClearCache()
{
	{
		oo::AutoreleaseScope scope;
		OOTexture::clearCache();
	}
}

}	// namespace


OO_TEST(defaults)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	{
		oo::AutoreleaseScope pool;
		BareGenerator *generator = Generator<BareGenerator>("bare generator", kOOTextureMinFilterLinear);
		OO_CHECK(generator->textureOptions() == kOOTextureDefaultOptions);
		OO_CHECK(generator->anisotropy() == (GLfloat)kOOTextureDefaultAnisotropy && generator->lodBias() == (GLfloat)kOOTextureDefaultLODBias);
		OO_CHECK(!generator->cacheKey().has_value());	// a generator is not cached unless it says so
		OO_CHECK(generator->path() == std::optional<std::string>("bare generator"));
		OO_CHECK(dynamic_cast<OOTextureLoader *>(generator) != nullptr);
		OO_CHECK(generator->description().ends_with(">{{bare generator -- loading}}"));
		OO_CHECK(!oo::makeRef<BareGenerator>()->initWithPath(std::nullopt, 0));
	}
}


OO_TEST(enqueueLoadsOnTheWorkManager)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	{
		oo::AutoreleaseScope pool;
		const int loads = gLoads;
		BareGenerator *generator = Generator<BareGenerator>("queued generator", kOOTextureMinFilterLinear);
		OO_CHECK(generator->enqueue());
		OOPixMap pixMap = kOONullPixMap;
		OOTextureDataFormat format = kOOPixMapInvalidFormat;
		uint32_t width = 0, height = 0;
		OO_CHECK(generator->getResult(&pixMap, &format, &width, &height));
		OO_CHECK(gLoads == loads + 1 && generator->isReady());
		OO_CHECK(pixMap.width == 8 && pixMap.height == 8 && width == 8 && format == kOOPixMapRGBA);
		OO_CHECK(((uint8_t *)pixMap.pixels)[0] == 1);
		OOFreePixMap(&pixMap);
	}
}


OO_TEST(aTextureTakesTheGeneratorsSettings)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	{
		oo::AutoreleaseScope pool;
		ChoosyGenerator *generator = Generator<ChoosyGenerator>("choosy generator", 0);
		OO_CHECK(generator->textureOptions() == (kOOTextureMinFilterNearest | kOOTextureMagFilterNearest));
		OO_CHECK(generator->anisotropy() == 0.25f && generator->lodBias() == 0.5f);

		OOTexture *texture = Autoreleased(OOTexture::textureWithGenerator(generator));
		OO_CHECK((dynamic_cast<OOConcreteTexture *>(texture) != nullptr));
		OO_CHECK(texture->cacheKey() == std::optional<std::string>("test:choosy"));
		OO_CHECK(OOTexture::textureWithGenerator(generator).get() == texture);	// cached by the generator's key
		texture->ensureFinishedLoading();
		OO_CHECK(texture->dimensions().width == 8 && !texture->isMipMapped());	// nearest: no mip-maps
#ifndef NDEBUG
		OO_CHECK(texture->name() == std::optional<std::string>("<ChoosyGenerator>"));
#endif
	}
	ClearCache();
}


// --- The C++ API (after the conversion) --------------------------------------------------------

// A converted generator, as OOPixMapTextureLoader will be one: a global C++ subclass.
class TestCxxGenerator final : public OOTextureGenerator
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
	{
		oo::AutoreleaseScope pool;
		const oo::Ref<TestCxxGenerator> generator = oo::makeRef<TestCxxGenerator>();
		OO_CHECK(generator->initWithPath(std::string("cxx generator"), 0));
		OO_CHECK(generator->anisotropy() == (GLfloat)kOOTextureDefaultAnisotropy && generator->lodBias() == (GLfloat)kOOTextureDefaultLODBias);

		// A texture takes it (it took the generator's facade until bead oo-9ht.118).
		OO_CHECK(generator->textureOptions() == (kOOTextureMinFilterLinear | kOOTextureMagFilterLinear));
		OO_CHECK(generator->cacheKey() == std::optional<std::string>("test:cxxgen"));
		OOTexture *texture = Autoreleased(OOTexture::textureWithGenerator(generator.get()));
		OO_CHECK(texture->cacheKey() == std::optional<std::string>("test:cxxgen"));
		texture->ensureFinishedLoading();
		OO_CHECK(generator->loads == 1 && texture->dimensions().width == 8);

		// The bare class's own answers.
		const oo::Ref<OOTextureGenerator> bare = oo::makeRef<OOTextureGenerator>();
		OO_CHECK(bare->textureOptions() == kOOTextureDefaultOptions && !bare->cacheKey().has_value());
	}
	ClearCache();
}


OO_TEST_MAIN()
