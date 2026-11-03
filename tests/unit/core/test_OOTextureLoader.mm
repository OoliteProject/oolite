/*	test_OOTextureLoader.mm
	Unit tests for OOTextureLoader (src/Core/Materials/OOTextureLoader.h), the root of the texture
	loaders: bead oo-zl36 (Phase 3, house style of proposed ADR-0056; the textures module,
	amendments oo-whzh and oo-bj8).

	A loader is a task on the game's work manager: its subclass's -loadTexture fills the pixels on
	a work thread, the root then applies the options (channel extraction, scaling to a power of
	two, mip-maps), and the texture takes the result on the main thread. OOPNGTextureLoader,
	OOPixMapTextureLoader and the generators derive from it in their own files. The test's loader
	is an Objective-C subclass that makes its pixels itself, so no file is read; the class factory
	is asked only for paths it refuses. It links the whole game but main (tests/unit/core/meson.build
	entry ['*']), on the hidden GL context of oo_gl_test_context.hpp (the loaders' one-time set-up
	reads the GL texture size limit). The expectations were written against the Objective-C API and
	run on the unconverted class first (commit c5a02306c); that API is now the facade, so they run
	through it. The test subclass reads the root's state in one block of helpers (amendment oo-bj8
	item 11), the only lines the conversion ported (to _cxxLoader->). The last tests pin the C++ API
	(cxx::OOTextureLoader) and the crossing both ways.
	Run: bash tools/check-core-tests.sh
*/

#import "OOTexture.h"
#import "OOTextureLoader.h"
#import "OOAsyncWorkManager.h"
#import "OODescription.h"

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
// 1, or none, or an exception.
@interface TestLoader: OOTextureLoader
{
@public
	uint32_t			_testWidth, _testHeight;
	OOTextureDataFormat	_testFormat;
	BOOL				_testEmpty, _testRaise;
}
@end

@implementation TestLoader

- (void) loadTexture
{
	gLoads++;
	if (_testRaise)  [OOException raise:"TestLoaderException" format:"test loader raised"];
	if (_testEmpty)  return;
	const size_t size = (size_t)_testWidth * _testHeight * OOTextureComponentsForFormat(_testFormat);
	uint8_t *bytes = (uint8_t *)malloc(size);
	for (size_t i = 0; i < size; i++)  bytes[i] = (uint8_t)(i + 1);
	_cxxLoader->_data = bytes;
	_cxxLoader->_width = _testWidth;
	_cxxLoader->_height = _testHeight;
	_cxxLoader->_format = _testFormat;
}


// The root's state, as the subclasses read it (the one block the conversion ports).
- (uint32_t) testOptions			{ return _cxxLoader->_options; }
- (uint32_t) testMaxSize			{ return _cxxLoader->_maxSize; }
- (uint32_t) testShrinkThreshold	{ return _cxxLoader->_shrinkThreshold; }
- (BOOL) testGenerateMipMaps		{ return _cxxLoader->_generateMipMaps; }
- (BOOL) testAvoidShrinking			{ return _cxxLoader->_avoidShrinking; }
- (BOOL) testNoScaling				{ return _cxxLoader->_noScalingWhatsoever; }
- (BOOL) testExtractChannel			{ return _cxxLoader->_extractChannel; }
- (uint8_t) testExtractChannelIndex	{ return _cxxLoader->_extractChannelIndex; }
- (BOOL) testAllowCubeMap			{ return _cxxLoader->_allowCubeMap; }
- (std::string) testPath			{ return _cxxLoader->_path; }

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


TestLoader *Loader(const char *path, uint32_t options, uint32_t width, uint32_t height, OOTextureDataFormat format)
{
	TestLoader *loader = [[[TestLoader alloc] cxx_initWithPath:std::string(path) options:options] autorelease];
	if (loader != nil)
	{
		loader->_testWidth = width;
		loader->_testHeight = height;
		loader->_testFormat = format;
	}
	return loader;
}


bool Queue(OOTextureLoader *loader)
{
	return [[OOAsyncWorkManager sharedAsyncWorkManager] addTask:loader priority:kOOAsyncPriorityMedium];
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
	result.ok = [loader getResult:&result.pixMap format:&result.format originalWidth:&result.originalWidth originalHeight:&result.originalHeight];
	return result;
}

}	// namespace


OO_TEST(factoryRefusals)
{
	OO_CHECK(OOTestGLContext());
	@autoreleasepool
	{
		OO_CHECK([OOTextureLoader cxx_loaderWithPath:std::nullopt options:0] == nil);
		OO_CHECK([OOTextureLoader cxx_loaderWithPath:std::string("textures/unknown.type") options:0] == nil);
		OO_CHECK([OOTextureLoader cxx_loaderWithTextureSpecifier:oo::PList(3.0) extraOptions:0 folder:std::string("Textures")] == nil);
		OO_CHECK([OOTextureLoader cxx_loaderWithTextureSpecifier:oo::PList() extraOptions:0 folder:std::string("Textures")] == nil);
		OO_CHECK([[TestLoader alloc] cxx_initWithPath:std::nullopt options:0] == nil);
	}
}


OO_TEST(optionsDecoded)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	@autoreleasepool
	{
		TestLoader *plain = Loader("dir/plain.png", kOOTextureMinFilterLinear, 4, 4, kOOPixMapRGBA);
		OO_CHECK([plain testOptions] == kOOTextureMinFilterLinear);
		OO_CHECK(![plain testGenerateMipMaps] && ![plain testAvoidShrinking] && ![plain testNoScaling]);
		OO_CHECK([plain testShrinkThreshold] == 512 && [plain testMaxSize] >= 64);
		OO_CHECK(![plain testExtractChannel] && ![plain testAllowCubeMap]);
		OO_CHECK([plain testPath] == "dir/plain.png" && [plain cxx_path] == std::optional<std::string>("dir/plain.png"));
		OO_CHECK([plain cxx_cacheKey] == std::optional<std::string>("plain.png:0x0002"));
		OO_CHECK(![plain isReady]);

		OO_CHECK([Loader("a", kOOTextureMinFilterMipMap, 1, 1, kOOPixMapRGBA) testGenerateMipMaps]);
		TestLoader *noShrink = Loader("b", kOOTextureNoShrink, 1, 1, kOOPixMapRGBA);
		OO_CHECK([noShrink testAvoidShrinking] && [noShrink testShrinkThreshold] == UINT32_MAX);
		TestLoader *never = Loader("c", kOOTextureNeverScale, 1, 1, kOOPixMapRGBA);
		OO_CHECK([never testNoScaling] && [never testShrinkThreshold] == UINT32_MAX);
		TestLoader *extra = Loader("d", kOOTextureExtraShrink, 1, 1, kOOPixMapRGBA);
		OO_CHECK([extra testShrinkThreshold] == 128 && [extra testMaxSize] <= 256);
		OO_CHECK([Loader("e", kOOTextureAllowCubeMap, 1, 1, kOOPixMapRGBA) testAllowCubeMap]);
		TestLoader *green = Loader("f", kOOTextureExtractChannelG, 1, 1, kOOPixMapRGBA);
		OO_CHECK([green testExtractChannel] && [green testExtractChannelIndex] == 1);
		TestLoader *alpha = Loader("g", kOOTextureExtractChannelA, 1, 1, kOOPixMapRGBA);
		OO_CHECK([alpha testExtractChannel] && [alpha testExtractChannelIndex] == 3);
	}
}


OO_TEST(descriptions)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	@autoreleasepool
	{
		TestLoader *loader = Loader("dir/desc.png", kOOTextureMinFilterLinear, 4, 4, kOOPixMapRGBA);
		OO_CHECK(oo::DescriptionOf(loader).starts_with("<TestLoader 0x"));
		OO_CHECK(oo::DescriptionOf(loader).ends_with(">{{dir/desc.png -- loading}}"));
		OO_CHECK(oo::ShortDescriptionOf(loader).ends_with(">{desc.png}"));
		OO_CHECK(Queue(loader));
		Result result = GetResult(loader);
		OO_CHECK(result.ok && [loader isReady]);
		OO_CHECK(oo::DescriptionOf(loader).ends_with(">{{dir/desc.png -- failed}}"));	// the pixels were handed over
		OOFreePixMap(&result.pixMap);
	}
}


OO_TEST(loadsScalesAndHandsOver)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	@autoreleasepool
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
	@autoreleasepool
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
	@autoreleasepool
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
	@autoreleasepool
	{
		TestLoader *empty = Loader("empty.png", kOOTextureMinFilterLinear, 4, 4, kOOPixMapRGBA);
		empty->_testEmpty = YES;
		OO_CHECK(Queue(empty));
		Result none = GetResult(empty);
		OO_CHECK(!none.ok && none.format == kOOPixMapInvalidFormat && [empty isReady]);
		OO_CHECK(oo::DescriptionOf(empty).ends_with(">{{empty.png -- failed}}"));

		TestLoader *raising = Loader("raise.png", kOOTextureMinFilterLinear, 4, 4, kOOPixMapRGBA);
		raising->_testRaise = YES;
		OO_CHECK(Queue(raising));
		Result raised = GetResult(raising);	// the exception is caught on the work thread
		OO_CHECK(!raised.ok && [raising isReady]);
	}
}


// --- The C++ API and the crossing (after the conversion) -------------------------------------

// A converted loader, as OOPNGTextureLoader will be one: a C++ subclass that fills the pixels.
class TestCxxLoader final : public cxx::OOTextureLoader
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
	@autoreleasepool
	{
		OO_CHECK(!cxx::OOTextureLoader::loaderWithPath(std::nullopt, 0));
		OO_CHECK(!cxx::OOTextureLoader::loaderWithPath(std::string("unknown.type"), 0));
		OO_CHECK(!cxx::OOTextureLoader::loaderWithTextureSpecifier(oo::PList(3.0), 0, std::string("Textures")));

		const oo::Ref<TestCxxLoader> loader = oo::makeRef<TestCxxLoader>();
		OO_CHECK(!loader->initWithPath(std::nullopt, 0));
		OO_CHECK(loader->initWithPath(std::string("dir/cxx.png"), kOOTextureMinFilterLinear));
		OO_CHECK(loader->path() == std::optional<std::string>("dir/cxx.png") && loader->_shrinkThreshold == 512);
		OO_CHECK(loader->cacheKey() == std::optional<std::string>("cxx.png:0x0002"));
		OO_CHECK(loader->shortDescriptionComponents() == std::optional<std::string>("cxx.png"));

		// Queued as its facade, loaded on a work thread, handed over on this one.
		OOTextureLoader *facade = oo::ToObjC(loader.get());
		OO_CHECK(facade != nil && facade == oo::ToObjC(loader.get()) && oo::ToCxx(facade) == loader.get());
		OO_CHECK(Queue(facade));
		OOPixMap pixMap = kOONullPixMap;
		OOTextureDataFormat format = kOOPixMapInvalidFormat;
		uint32_t width = 0, height = 0;
		OO_CHECK(loader->getResult(&pixMap, &format, &width, &height));
		OO_CHECK(loader->loads == 1 && loader->isReady() && format == kOOPixMapRGBA);
		OO_CHECK(pixMap.width == 8 && pixMap.height == 8 && width == 8 && height == 8);
		OO_CHECK(((uint8_t *)pixMap.pixels)[0] == 1);
		OOFreePixMap(&pixMap);

		// The facade answers the C++ loader's overrides and the root's defaults.
		OO_CHECK(oo::DescriptionOf(facade).starts_with("<TestCxxLoader 0x") && oo::DescriptionOf(facade).ends_with(">{cxx}"));
		OO_CHECK([facade cxx_cacheKey] == std::optional<std::string>("cxx.png:0x0002") && [facade isReady]);
	}
}


OO_TEST(objCLoaderBehindACxxPointer)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	@autoreleasepool
	{
		TestLoader *objCLoader = Loader("dir/objc.png", kOOTextureMinFilterLinear, 8, 8, kOOPixMapRGBA);
		cxx::OOTextureLoader *part = oo::ToCxx(objCLoader);
		OO_CHECK(part != nullptr && oo::ToObjC(part) == objCLoader);	// the object itself
		OO_CHECK(part->cacheKey() == std::optional<std::string>("objc.png:0x0002"));
		OO_CHECK(part->descriptionComponents() == std::optional<std::string>("{dir/objc.png -- loading}"));

		// The C++ part's virtual loadTexture reaches the Objective-C override.
		const int loads = gLoads;
		OO_CHECK(Queue(objCLoader));
		OOPixMap pixMap = kOONullPixMap;
		OOTextureDataFormat format = kOOPixMapInvalidFormat;
		OO_CHECK(part->getResult(&pixMap, &format, nullptr, nullptr) && gLoads == loads + 1);
		OO_CHECK(pixMap.width == 8 && ((uint8_t *)pixMap.pixels)[0] == 1);
		OOFreePixMap(&pixMap);
	}
}


OO_TEST(nilAndLifetime)
{
	OOTextureLoader *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOTextureLoader *>(nullptr)) == nil);
	OO_CHECK(![none isReady] && ![none cxx_cacheKey].has_value());

	// An Objective-C loader's C++ part outlives it, and then answers as nil did.
	oo::Ref<cxx::OOTextureLoader> part;
	@autoreleasepool
	{
		part = oo::Ref<cxx::OOTextureLoader>(oo::ToCxx(Loader("gone.png", 0, 8, 8, kOOPixMapRGBA)));
	}
	OO_CHECK(!part->cacheKey().has_value() && !part->descriptionComponents().has_value());
	OO_CHECK(oo::ToObjC(part) == nil);
	part->loadTexture();	// nothing: its object has gone
}


OO_TEST_MAIN()
