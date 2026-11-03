/*	test_OOPixMapTextureLoader.mm
	Unit tests for OOPixMapTextureLoader (src/Core/Materials/OOPixMapTextureLoader.h), the texture
	generator whose pixels are a pixmap made in memory (the planets' generated surface and cloud
	textures): bead oo-kvqq (Phase 3, house style of proposed ADR-0056; a leaf of the texture
	generators, amendments oo-zl36, oo-rr2x and oo-bj8 item 12).

	It takes over the pixmap it is given, answers its texture options with the defaults applied, and
	hands the pixels to the texture as they are, after making room for and generating mip-maps when
	its options ask for them. It links the whole game but main (tests/unit/core/meson.build entry
	['*']), on the hidden GL context of oo_gl_test_context.hpp. The expectations were written against
	the Objective-C API and run on the unconverted class first (commit ab440895f). Making a loader
	goes through the helper below, the only lines the conversion ported (amendment oo-bj8 item 11):
	the class is now a global C++ class with no facade of its own, made by its factory (bead
	oo-9ht.118 deleted the generators' facade it crossed as; its crossing check went with it). The
	last test pins the C++ API.
	Run: bash tools/check-core-tests.sh
*/

#include "OOPixMapTextureLoader.h"
#include "OOConcreteTexture.h"

#include "oo_test.hpp"
#include "oo_gl_test_context.hpp"

#include <cstdlib>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif



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


// An 8 x 8 RGBA pixmap whose bytes count up from 1, allocated with malloc().
OOPixMap TestPixMap()
{
	OOPixMap pixMap = OOAllocatePixMap(8, 8, kOOPixMapRGBA, 0, 0);
	uint8_t *bytes = (uint8_t *)pixMap.pixels;
	for (unsigned i = 0; i < 8 * 8 * 4; i++)  bytes[i] = (uint8_t)(i + 1);
	return pixMap;
}


// The generators made, kept for the test's life (each was autoreleased in its case's pool).
std::vector<oo::Ref<OOTextureGenerator>> gKeptGenerators;


OOTextureGenerator *Kept(oo::Ref<OOTextureGenerator> generator)
{
	if (generator != nullptr)  gKeptGenerators.push_back(generator);
	return generator.get();
}


// Was [[OOPixMapTextureLoader alloc] initWithPixMap:...], autoreleased: the loader as a generator.
OOTextureGenerator *NewLoader(OOPixMap pixMap, uint32_t options, BOOL freeWhenDone)
{
	return Kept(OOPixMapTextureLoader::loaderWithPixMap(pixMap, options, freeWhenDone));
}


void ClearCache()
{
	{
		oo::AutoreleaseScope scope;
		OOTexture::clearCache();
	}
}

}	// namespace


OO_TEST(takesThePixMap)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	{
		oo::AutoreleaseScope pool;
		OOTextureGenerator *loader = NewLoader(TestPixMap(), kOOTextureMinFilterLinear | kOOTextureRepeatS, YES);
		OO_CHECK(loader != nullptr && dynamic_cast<OOTextureGenerator *>(loader) != nullptr);
		OO_CHECK(loader->textureOptions() == OOApplyTextureOptionDefaults(kOOTextureMinFilterLinear | kOOTextureRepeatS));
		OO_CHECK(loader->path().value_or("").starts_with("OOPixMap@"));
		OO_CHECK(!loader->cacheKey().has_value());	// a generator: not cached

		OO_CHECK(loader->enqueue());
		OOPixMap result = kOONullPixMap;
		OOTextureDataFormat format = kOOPixMapInvalidFormat;
		uint32_t width = 0, height = 0;
		OO_CHECK(loader->getResult(&result, &format, &width, &height));
		OO_CHECK(format == kOOPixMapRGBA && result.width == 8 && result.height == 8 && result.rowBytes == 32);
		OO_CHECK(width == 8 && height == 8);
		OO_CHECK(((const uint8_t *)result.pixels)[0] == 1 && ((const uint8_t *)result.pixels)[255] == 0);
		OOFreePixMap(&result);
	}
}


OO_TEST(refusals)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	{
		oo::AutoreleaseScope pool;
		// Not a pixmap.
		OO_CHECK(NewLoader(kOONullPixMap, kOOTextureMinFilterLinear, YES) == nullptr);

		// Not taken over: the initialiser duplicates its own (still empty) pixmap, not the one it was
		// given, so it answers nil and the caller keeps its pixels. (As it has since 2010; kept.)
		OOPixMap kept = TestPixMap();
		OO_CHECK(NewLoader(kept, kOOTextureMinFilterLinear, NO) == nullptr);
		OO_CHECK(OOIsValidPixMap(kept) && ((const uint8_t *)kept.pixels)[0] == 1);
		OOFreePixMap(&kept);
	}
}


OO_TEST(loadsWithMipMaps)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	{
		oo::AutoreleaseScope pool;
		OOTextureGenerator *loader = NewLoader(TestPixMap(), kOOTextureMinFilterMipMap, YES);
		OO_CHECK(loader->textureOptions() == OOApplyTextureOptionDefaults(kOOTextureMinFilterMipMap));
		OO_CHECK(loader->enqueue());
		OOPixMap result = kOONullPixMap;
		OOTextureDataFormat format = kOOPixMapInvalidFormat;
		OO_CHECK(loader->getResult(&result, &format, NULL, NULL));
		OO_CHECK(result.width == 8 && result.height == 8 && format == kOOPixMapRGBA);
		OO_CHECK(((const uint8_t *)result.pixels)[0] == 1);	// the base level as given
		OOFreePixMap(&result);
	}
}


OO_TEST(aTextureOfTheGenerator)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	{
		oo::AutoreleaseScope pool;
		OOTextureGenerator *loader = NewLoader(TestPixMap(), kOOTextureDefaultOptions | kOOTextureRepeatS, YES);
		OOTexture *texture = Autoreleased(OOTexture::textureWithGenerator(loader));
		OO_CHECK((dynamic_cast<OOConcreteTexture *>(texture) != nullptr));
		texture->ensureFinishedLoading();
		OO_CHECK(texture->dimensions().width == 8 && texture->dimensions().height == 8);
		OO_CHECK(texture->isFinishedLoading());
	}
	ClearCache();
}


// --- The C++ API (after the conversion) --------------------------------------------------------

OO_TEST(cxxApi)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	{
		oo::AutoreleaseScope pool;
		OO_CHECK(!OOPixMapTextureLoader::loaderWithPixMap(kOONullPixMap, 0, true));

		const oo::Ref<OOPixMapTextureLoader> loader = OOPixMapTextureLoader::loaderWithPixMap(TestPixMap(), kOOTextureMinFilterLinear, true);
		OO_CHECK(loader && loader->textureOptions() == OOApplyTextureOptionDefaults(kOOTextureMinFilterLinear));
		OO_CHECK(loader->path().value_or("").starts_with("OOPixMap@") && !loader->cacheKey().has_value());

		// Loading hands the pixels over as they are.
		loader->loadTexture();
		OO_CHECK(loader->_data != nullptr && loader->_width == 8 && loader->_height == 8 && loader->_rowBytes == 32);
		OO_CHECK(loader->_format == kOOPixMapRGBA && ((const uint8_t *)loader->_data)[0] == 1);
	}
}


OO_TEST_MAIN()
