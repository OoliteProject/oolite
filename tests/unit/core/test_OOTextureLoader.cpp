/*	test_OOTextureLoader.mm
	Unit tests for OOTextureLoader (src/Core/Materials/OOTextureLoader.h), the root of the texture
	loaders: bead oo-zl36 (Phase 3, house style of proposed ADR-0056; the textures module,
	amendments oo-whzh and oo-bj8).

	A loader is a task on the game's work manager: its subclass's -loadTexture fills the pixels on
	a work thread, the root then applies the options (channel extraction, scaling to a power of
	two, mip-maps), and the texture takes the result on the main thread. OOPNGTextureLoader,
	OOPixMapTextureLoader and the generators derive from it in their own files. The test's loader
	is a subclass that makes its pixels itself, so no file is read; the class factory
	is asked only for paths it refuses. It links the whole game but main (tests/unit/core/meson.build
	entry ['*']), on the hidden GL context of oo_gl_test_context.hpp (the loaders' one-time set-up
	reads the GL texture size limit). The expectations were written against the Objective-C API and
	run on the unconverted class first (commit c5a02306c). Bead oo-9ht.114 deleted the Objective-C
	facade: its crossing cases went with it (standing approval oo-9n5p9), the Objective-C test loader
	is a C++ subclass of the same name with the same answers, and the other cases call the same
	members with every expectation kept. The last test pins the C++ API (OOTextureLoader).
	Run: bash tools/check-core-tests.sh
*/

#include "OOTexture.h"
#include "OOTextureLoader.h"
#include "OOAsyncWorkManager.h"
#include "OODescription.h"

#include "oo_test.hpp"
#include "oo_gl_test_context.hpp"
#include "oofnd/objc/OOException.h"

#include <cstdlib>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


static int gLoads = 0;


// A loader whose pixels are a width x height image of the given format whose bytes count up from
// 1, or none, or an exception. (An Objective-C subclass until bead oo-9ht.114; named as it was.)
class TestLoader : public OOTextureLoader
{
public:
	void loadTexture() override
	{
		gLoads++;
		if (_testRaise)  OORaiseException("TestLoaderException", "test loader raised");
		if (_testEmpty)  return;
		const size_t size = (size_t)_testWidth * _testHeight * OOTextureComponentsForFormat(_testFormat);
		uint8_t *bytes = (uint8_t *)malloc(size);
		for (size_t i = 0; i < size; i++)  bytes[i] = (uint8_t)(i + 1);
		_data = bytes;
		_width = _testWidth;
		_height = _testHeight;
		_format = _testFormat;
	}


	// The root's state, as the subclasses read it (the one block the conversion ports).
	uint32_t testOptions()				{ return _options; }
	uint32_t testMaxSize()				{ return _maxSize; }
	uint32_t testShrinkThreshold()		{ return _shrinkThreshold; }
	BOOL testGenerateMipMaps()			{ return _generateMipMaps; }
	BOOL testAvoidShrinking()			{ return _avoidShrinking; }
	BOOL testNoScaling()				{ return _noScalingWhatsoever; }
	BOOL testExtractChannel()			{ return _extractChannel; }
	uint8_t testExtractChannelIndex()	{ return _extractChannelIndex; }
	BOOL testAllowCubeMap()				{ return _allowCubeMap; }
	std::string testPath()				{ return _path; }

	uint32_t			_testWidth = 0, _testHeight = 0;
	OOTextureDataFormat	_testFormat = {};
	BOOL				_testEmpty = NO, _testRaise = NO;
};


namespace {

// The loaders' sizes come from their one-time set-up, which a path with no known extension runs
// (and then answers nil, reading nothing).
void SetUpLoaders()
{
	{
		(void)OOTextureLoader::loaderWithPath(std::string("unknown.type"), 0);
	}
}


// The loaders made, kept for the test's life (each was autoreleased in its case's pool).
std::vector<oo::Ref<TestLoader>> gKeptLoaders;


TestLoader *Loader(const char *path, uint32_t options, uint32_t width, uint32_t height, OOTextureDataFormat format)
{
	const oo::Ref<TestLoader> made = oo::makeRef<TestLoader>();
	TestLoader *loader = made->initWithPath(std::string(path), options) ? made.get() : nullptr;
	if (loader != nullptr)
	{
		gKeptLoaders.push_back(made);
		loader->_testWidth = width;
		loader->_testHeight = height;
		loader->_testFormat = format;
	}
	return loader;
}


bool Queue(OOTextureLoader *loader)
{
	// The work manager's task is the C++ loader since bead oo-9ht.14 (it was the Objective-C object).
	return OOAsyncWorkManager::sharedAsyncWorkManager()->addTask(loader, kOOAsyncPriorityMedium);
}


struct Result
{
	bool				ok = false;
	OOPixMap			pixMap = kOONullPixMap;
	OOTextureDataFormat	format = kOOPixMapInvalidFormat;
	uint32_t			originalWidth = 0, originalHeight = 0;
};


Result GetResult(OOTextureLoader *loader)
{
	Result result;
	result.ok = loader->getResult(&result.pixMap, &result.format, &result.originalWidth, &result.originalHeight);
	return result;
}

}	// namespace


OO_TEST(factoryRefusals)
{
	OO_CHECK(OOTestGLContext());
	{
		OO_CHECK(OOTextureLoader::loaderWithPath(std::nullopt, 0) == nullptr);
		OO_CHECK(OOTextureLoader::loaderWithPath(std::string("textures/unknown.type"), 0) == nullptr);
		OO_CHECK(OOTextureLoader::loaderWithTextureSpecifier(oo::PList(3.0), 0, std::string("Textures")) == nullptr);
		OO_CHECK(OOTextureLoader::loaderWithTextureSpecifier(oo::PList(), 0, std::string("Textures")) == nullptr);
		OO_CHECK(!oo::makeRef<TestLoader>()->initWithPath(std::nullopt, 0));
	}
}


OO_TEST(optionsDecoded)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	{
		TestLoader *plain = Loader("dir/plain.png", kOOTextureMinFilterLinear, 4, 4, kOOPixMapRGBA);
		OO_CHECK(plain->testOptions() == kOOTextureMinFilterLinear);
		OO_CHECK(!plain->testGenerateMipMaps() && !plain->testAvoidShrinking() && !plain->testNoScaling());
		OO_CHECK(plain->testShrinkThreshold() == 512 && plain->testMaxSize() >= 64);
		OO_CHECK(!plain->testExtractChannel() && !plain->testAllowCubeMap());
		OO_CHECK(plain->testPath() == "dir/plain.png" && plain->path() == std::optional<std::string>("dir/plain.png"));
		OO_CHECK(plain->cacheKey() == std::optional<std::string>("plain.png:0x0002"));
		OO_CHECK(!plain->isReady());

		OO_CHECK(Loader("a", kOOTextureMinFilterMipMap, 1, 1, kOOPixMapRGBA)->testGenerateMipMaps());
		TestLoader *noShrink = Loader("b", kOOTextureNoShrink, 1, 1, kOOPixMapRGBA);
		OO_CHECK(noShrink->testAvoidShrinking() && noShrink->testShrinkThreshold() == UINT32_MAX);
		TestLoader *never = Loader("c", kOOTextureNeverScale, 1, 1, kOOPixMapRGBA);
		OO_CHECK(never->testNoScaling() && never->testShrinkThreshold() == UINT32_MAX);
		TestLoader *extra = Loader("d", kOOTextureExtraShrink, 1, 1, kOOPixMapRGBA);
		OO_CHECK(extra->testShrinkThreshold() == 128 && extra->testMaxSize() <= 256);
		OO_CHECK(Loader("e", kOOTextureAllowCubeMap, 1, 1, kOOPixMapRGBA)->testAllowCubeMap());
		TestLoader *green = Loader("f", kOOTextureExtractChannelG, 1, 1, kOOPixMapRGBA);
		OO_CHECK(green->testExtractChannel() && green->testExtractChannelIndex() == 1);
		TestLoader *alpha = Loader("g", kOOTextureExtractChannelA, 1, 1, kOOPixMapRGBA);
		OO_CHECK(alpha->testExtractChannel() && alpha->testExtractChannelIndex() == 3);
	}
}


OO_TEST(descriptions)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	{
		TestLoader *loader = Loader("dir/desc.png", kOOTextureMinFilterLinear, 4, 4, kOOPixMapRGBA);
		OO_CHECK(loader->description().starts_with("<TestLoader 0x"));
		OO_CHECK(loader->description().ends_with(">{{dir/desc.png -- loading}}"));
		OO_CHECK(loader->shortDescription().ends_with(">{desc.png}"));
		OO_CHECK(Queue(loader));
		Result result = GetResult(loader);
		OO_CHECK(result.ok && loader->isReady());
		OO_CHECK(loader->description().ends_with(">{{dir/desc.png -- failed}}"));	// the pixels were handed over
		OOFreePixMap(&result.pixMap);
	}
}


OO_TEST(loadsScalesAndHandsOver)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	{
		const int loads = gLoads;
		TestLoader *loader = Loader("square.png", kOOTextureMinFilterLinear, 8, 8, kOOPixMapRGBA);
		OO_CHECK(Queue(loader));
		Result result = GetResult(loader);	// waits for the work thread
		OO_CHECK(gLoads == loads + 1);
		OO_CHECK(result.ok && result.format == kOOPixMapRGBA);
		OO_CHECK(result.originalWidth == 8 && result.originalHeight == 8);
		OO_CHECK(result.pixMap.width == 8 && result.pixMap.height == 8 && result.pixMap.rowBytes == 32);	// a power of two: as loaded
		OO_CHECK(result.pixMap.pixels != NULL && ((uint8_t *)result.pixMap.pixels)[0] == 1);
		OOFreePixMap(&result.pixMap);

		// The pixels were handed over: a second request has none.
		Result again = GetResult(loader);
		OO_CHECK(!again.ok && again.format == kOOPixMapInvalidFormat && OOIsNullPixMap(again.pixMap));

		// A 4 x 2 image is scaled to 2 x 2 (a power of two near two thirds of each side).
		TestLoader *wide = Loader("wide.png", kOOTextureMinFilterLinear, 4, 2, kOOPixMapRGBA);
		OO_CHECK(Queue(wide));
		Result scaled = GetResult(wide);
		OO_CHECK(scaled.ok && scaled.pixMap.width == 2 && scaled.pixMap.height == 2);
		OO_CHECK(scaled.originalWidth == 4 && scaled.originalHeight == 2);
		OO_CHECK(((uint8_t *)scaled.pixMap.pixels)[0] == 3);
		OOFreePixMap(&scaled.pixMap);

		// Never scaled: as loaded.
		TestLoader *never = Loader("never.png", kOOTextureNeverScale, 4, 2, kOOPixMapRGBA);
		OO_CHECK(Queue(never));
		Result asLoaded = GetResult(never);
		OO_CHECK(asLoaded.ok && asLoaded.pixMap.width == 4 && asLoaded.pixMap.height == 2);
		OOFreePixMap(&asLoaded.pixMap);
	}
}


OO_TEST(extractsAChannel)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	{
		TestLoader *loader = Loader("green.png", kOOTextureMinFilterLinear | kOOTextureExtractChannelG, 8, 8, kOOPixMapRGBA);
		OO_CHECK(Queue(loader));
		Result result = GetResult(loader);
		OO_CHECK(result.ok && result.format == kOOPixMapGrayscale);
		OO_CHECK(result.pixMap.width == 8 && result.pixMap.height == 8 && result.pixMap.rowBytes == 8);
		OO_CHECK(((uint8_t *)result.pixMap.pixels)[0] == 2);	// the first pixel's green byte
		OOFreePixMap(&result.pixMap);
	}
}


OO_TEST(mipMaps)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	{
		TestLoader *loader = Loader("mip.png", kOOTextureMinFilterMipMap, 8, 8, kOOPixMapRGBA);
		OO_CHECK(Queue(loader));
		Result result = GetResult(loader);
		OO_CHECK(result.ok && result.pixMap.width == 8 && result.pixMap.height == 8);
		OO_CHECK(((uint8_t *)result.pixMap.pixels)[0] == 1);	// the base level as loaded
		OOFreePixMap(&result.pixMap);
	}
}


OO_TEST(failures)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	{
		TestLoader *empty = Loader("empty.png", kOOTextureMinFilterLinear, 4, 4, kOOPixMapRGBA);
		empty->_testEmpty = YES;
		OO_CHECK(Queue(empty));
		Result none = GetResult(empty);
		OO_CHECK(!none.ok && none.format == kOOPixMapInvalidFormat && empty->isReady());
		OO_CHECK(empty->description().ends_with(">{{empty.png -- failed}}"));

		TestLoader *raising = Loader("raise.png", kOOTextureMinFilterLinear, 4, 4, kOOPixMapRGBA);
		raising->_testRaise = YES;
		OO_CHECK(Queue(raising));
		Result raised = GetResult(raising);	// the exception is caught on the work thread
		OO_CHECK(!raised.ok && raising->isReady());
	}
}


// --- The C++ API (after the conversion) --------------------------------------------------------

// A converted loader, as OOPNGTextureLoader will be one: a C++ subclass that fills the pixels.
class TestCxxLoader final : public OOTextureLoader
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

	std::optional<std::string> descriptionComponents() const override	{ return std::string("cxx"); }

	int loads = 0;
};


OO_TEST(cxxApi)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	{
		OO_CHECK(!OOTextureLoader::loaderWithPath(std::nullopt, 0));
		OO_CHECK(!OOTextureLoader::loaderWithPath(std::string("unknown.type"), 0));
		OO_CHECK(!OOTextureLoader::loaderWithTextureSpecifier(oo::PList(3.0), 0, std::string("Textures")));

		const oo::Ref<TestCxxLoader> loader = oo::makeRef<TestCxxLoader>();
		OO_CHECK(!loader->initWithPath(std::nullopt, 0));
		OO_CHECK(loader->initWithPath(std::string("dir/cxx.png"), kOOTextureMinFilterLinear));
		OO_CHECK(loader->path() == std::optional<std::string>("dir/cxx.png") && loader->_shrinkThreshold == 512);
		OO_CHECK(loader->cacheKey() == std::optional<std::string>("cxx.png:0x0002"));
		OO_CHECK(loader->shortDescriptionComponents() == std::optional<std::string>("cxx.png"));

		// Queued, loaded on a work thread, handed over on this one.
		OO_CHECK(Queue(loader.get()));
		OOPixMap pixMap = kOONullPixMap;
		OOTextureDataFormat format = kOOPixMapInvalidFormat;
		uint32_t width = 0, height = 0;
		OO_CHECK(loader->getResult(&pixMap, &format, &width, &height));
		OO_CHECK(loader->loads == 1 && loader->isReady() && format == kOOPixMapRGBA);
		OO_CHECK(pixMap.width == 8 && pixMap.height == 8 && width == 8 && height == 8);
		OO_CHECK(((uint8_t *)pixMap.pixels)[0] == 1);
		OOFreePixMap(&pixMap);

		// The C++ loader's overrides and the root's defaults, as the facade answered them.
		OO_CHECK(loader->description().starts_with("<TestCxxLoader 0x") && loader->description().ends_with(">{cxx}"));
		OO_CHECK(loader->cacheKey() == std::optional<std::string>("cxx.png:0x0002") && loader->isReady());
	}
}


OO_TEST_MAIN()
