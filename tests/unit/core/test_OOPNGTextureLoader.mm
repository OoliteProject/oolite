/*	test_OOPNGTextureLoader.mm
	Unit tests for OOPNGTextureLoader (src/Core/Materials/OOPNGTextureLoader.h), the texture loader
	that reads PNG files: bead oo-z889 (Phase 3, house style of proposed ADR-0056; a leaf of the
	texture loaders, amendments oo-zl36 and oo-vl43).

	The loaders' factory makes one for a path ending in .png and queues it on the game's work
	manager; on a work thread it reads the file with libpng, and the texture takes the pixels on the
	main thread. The test writes its PNG files with libpng's simplified API into a scratch directory
	under the working directory, so no game resource is read. It links the whole game but main
	(tests/unit/core/meson.build entry ['*']), on the hidden GL context of oo_gl_test_context.hpp
	(the loaders' one-time set-up reads the GL texture size limit). The expectations were written
	against the Objective-C API and run on the unconverted class first (commit a35e9c1a5); the
	loader is made by the factory, so they hold unchanged after it. The last test pins the C++ API
	of the converted class (a global C++ class with no facade of its own).
	Run: bash tools/check-core-tests.sh
*/

#import "OOPNGTextureLoader.h"
#import "OOAsyncWorkManager.h"
#import "OODescription.h"

#include "oo_test.hpp"
#include "oo_gl_test_context.hpp"

#include <png.h>

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <vector>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


namespace {

const std::filesystem::path &ScratchDirectory()
{
	static const std::filesystem::path directory = [] {
		std::filesystem::path result = std::filesystem::current_path() / "test_OOPNGTextureLoader.d";
		std::filesystem::remove_all(result);
		std::filesystem::create_directories(result);
		return result;
	}();
	return directory;
}


// A width x height PNG of the given libpng format whose bytes count up from 1; its path.
std::string WritePNG(const char *name, uint32_t width, uint32_t height, png_uint_32 format)
{
	png_image image = {};
	image.version = PNG_IMAGE_VERSION;
	image.width = width;
	image.height = height;
	image.format = format;
	std::vector<uint8_t> bytes(PNG_IMAGE_SIZE(image));
	for (size_t i = 0; i < bytes.size(); i++)  bytes[i] = (uint8_t)(i + 1);

	const std::string path = (ScratchDirectory() / name).generic_string();
	const bool written = png_image_write_to_file(&image, path.c_str(), 0, bytes.data(), 0, nullptr) != 0;
	png_image_free(&image);
	return written ? path : std::string();
}


void WriteBytes(const std::string &path, const std::vector<char> &bytes)
{
	std::ofstream file(path, std::ios::binary | std::ios::trunc);
	file.write(bytes.data(), (std::streamsize)bytes.size());
}


std::vector<char> ReadBytes(const std::string &path)
{
	std::ifstream file(path, std::ios::binary);
	return std::vector<char>(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
}


// The loaders' sizes come from their one-time set-up, which a path with no known extension runs
// (and then answers nil, reading nothing).
void SetUpLoaders()
{
	@autoreleasepool
	{
		(void)[OOTextureLoader cxx_loaderWithPath:std::string("unknown.type") options:0];
	}
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


// The factory's loader for a path, already queued.
OOTextureLoader *Load(const std::string &path)
{
	return [OOTextureLoader cxx_loaderWithPath:path options:kOOTextureMinFilterLinear];
}

}	// namespace


OO_TEST(theFactoryMakesOneForAPNG)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	@autoreleasepool
	{
		const std::string path = WritePNG("made.png", 8, 8, PNG_FORMAT_RGBA);
		OO_CHECK(!path.empty());
		OOTextureLoader *loader = Load(path);
		OO_CHECK(loader != nil);
		OO_CHECK(oo::DescriptionOf(loader).starts_with("<OOPNGTextureLoader 0x"));
		OO_CHECK([loader cxx_path] == std::optional<std::string>(path));
		OO_CHECK([loader cxx_cacheKey] == std::optional<std::string>("made.png:0x0002"));
		Result result = GetResult(loader);
		OO_CHECK(result.ok && [loader isReady]);
		OOFreePixMap(&result.pixMap);

		// The extension is matched without regard to case.
		const std::string upper = WritePNG("UPPER.PNG", 8, 8, PNG_FORMAT_RGBA);
		OOTextureLoader *upperLoader = Load(upper);
		OO_CHECK(upperLoader != nil && oo::DescriptionOf(upperLoader).starts_with("<OOPNGTextureLoader 0x"));
		Result upperResult = GetResult(upperLoader);
		OO_CHECK(upperResult.ok);
		OOFreePixMap(&upperResult.pixMap);
	}
}


OO_TEST(readsRGBA)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	@autoreleasepool
	{
		Result result = GetResult(Load(WritePNG("rgba.png", 8, 8, PNG_FORMAT_RGBA)));
		OO_CHECK(result.ok && result.format == kOOPixMapRGBA);
		OO_CHECK(result.pixMap.width == 8 && result.pixMap.height == 8 && result.pixMap.rowBytes == 32);
		OO_CHECK(result.originalWidth == 8 && result.originalHeight == 8);
		const uint8_t *pixels = (const uint8_t *)result.pixMap.pixels;
		OO_CHECK(pixels != NULL && pixels[0] == 1 && pixels[3] == 4 && pixels[255] == 0);	// byte 256 of the file's image
		OOFreePixMap(&result.pixMap);
	}
}


OO_TEST(readsRGBWithAnOpaqueAlpha)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	@autoreleasepool
	{
		Result result = GetResult(Load(WritePNG("rgb.png", 8, 8, PNG_FORMAT_RGB)));
		OO_CHECK(result.ok && result.format == kOOPixMapRGBA);
		OO_CHECK(result.pixMap.width == 8 && result.pixMap.rowBytes == 32);
		const uint8_t *pixels = (const uint8_t *)result.pixMap.pixels;
		OO_CHECK(pixels[0] == 1 && pixels[1] == 2 && pixels[2] == 3 && pixels[3] == 0xFF);
		OO_CHECK(pixels[4] == 4 && pixels[7] == 0xFF);
		OOFreePixMap(&result.pixMap);
	}
}


OO_TEST(readsGrayscale)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	@autoreleasepool
	{
		Result gray = GetResult(Load(WritePNG("gray.png", 8, 8, PNG_FORMAT_GRAY)));
		OO_CHECK(gray.ok && gray.format == kOOPixMapGrayscale);
		OO_CHECK(gray.pixMap.width == 8 && gray.pixMap.height == 8 && gray.pixMap.rowBytes == 8);
		OO_CHECK(((const uint8_t *)gray.pixMap.pixels)[0] == 1 && ((const uint8_t *)gray.pixMap.pixels)[63] == 64);
		OOFreePixMap(&gray.pixMap);

		Result grayAlpha = GetResult(Load(WritePNG("grayalpha.png", 8, 8, PNG_FORMAT_GA)));
		OO_CHECK(grayAlpha.ok && grayAlpha.format == kOOPixMapGrayscaleAlpha);
		OO_CHECK(grayAlpha.pixMap.width == 8 && grayAlpha.pixMap.rowBytes == 16);
		OO_CHECK(((const uint8_t *)grayAlpha.pixMap.pixels)[0] == 1 && ((const uint8_t *)grayAlpha.pixMap.pixels)[1] == 2);
		OOFreePixMap(&grayAlpha.pixMap);
	}
}


OO_TEST(sixteenBitsAreStrippedToEight)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	@autoreleasepool
	{
		Result result = GetResult(Load(WritePNG("deep.png", 8, 8, PNG_FORMAT_LINEAR_Y)));
		OO_CHECK(result.ok && result.format == kOOPixMapGrayscale);
		OO_CHECK(result.pixMap.width == 8 && result.pixMap.height == 8 && result.pixMap.rowBytes == 8);
		OOFreePixMap(&result.pixMap);
	}
}


OO_TEST(failures)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	@autoreleasepool
	{
		// No file.
		OOTextureLoader *missing = Load((ScratchDirectory() / "missing.png").generic_string());
		OO_CHECK(missing != nil);
		Result none = GetResult(missing);
		OO_CHECK(!none.ok && none.format == kOOPixMapInvalidFormat && [missing isReady]);

		// Not a PNG: libpng's error is caught, and nothing is answered.
		const std::string garbage = (ScratchDirectory() / "garbage.png").generic_string();
		WriteBytes(garbage, std::vector<char>(64, 'x'));
		OOTextureLoader *garbageLoader = Load(garbage);
		Result notPNG = GetResult(garbageLoader);
		OO_CHECK(!notPNG.ok && OOIsNullPixMap(notPNG.pixMap) && [garbageLoader isReady]);

		// A file cut short: the read beyond its end is an error, and the pixels read are freed.
		const std::vector<char> whole = ReadBytes(WritePNG("whole.png", 8, 8, PNG_FORMAT_RGBA));
		OO_CHECK(whole.size() > 64);
		const std::string truncated = (ScratchDirectory() / "truncated.png").generic_string();
		WriteBytes(truncated, std::vector<char>(whole.begin(), whole.begin() + (std::ptrdiff_t)(whole.size() / 2)));
		OOTextureLoader *truncatedLoader = Load(truncated);
		Result cutShort = GetResult(truncatedLoader);
		OO_CHECK(!cutShort.ok && OOIsNullPixMap(cutShort.pixMap) && [truncatedLoader isReady]);
		OO_CHECK(oo::DescriptionOf(truncatedLoader).ends_with(">{{" + truncated + " -- failed}}"));
	}
}


// --- The C++ API (after the conversion) --------------------------------------------------------

OO_TEST(cxxApi)
{
	OO_CHECK(OOTestGLContext());
	SetUpLoaders();
	@autoreleasepool
	{
		const std::string path = WritePNG("cxx.png", 8, 8, PNG_FORMAT_RGBA);
		const oo::Ref<OOPNGTextureLoader> loader = oo::makeRef<OOPNGTextureLoader>();
		OO_CHECK(!loader->initWithPath(std::nullopt, 0));
		OO_CHECK(loader->initWithPath(path, kOOTextureMinFilterLinear));
		OO_CHECK(loader->path() == std::optional<std::string>(path) && loader->cacheKey() == std::optional<std::string>("cxx.png:0x0002"));

		// Its facade is an OOTextureLoader (it has none of its own), and the work manager takes it.
		OOTextureLoader *facade = oo::ToObjC(loader.get());
		OO_CHECK([facade class] == [OOTextureLoader class] && oo::ToCxx(facade) == loader.get());
		OO_CHECK(oo::DescriptionOf(facade).starts_with("<OOPNGTextureLoader 0x"));
		OO_CHECK([[OOAsyncWorkManager sharedAsyncWorkManager] addTask:facade priority:kOOAsyncPriorityMedium]);
		OOPixMap pixMap = kOONullPixMap;
		OOTextureDataFormat format = kOOPixMapInvalidFormat;
		OO_CHECK(loader->getResult(&pixMap, &format, nullptr, nullptr) && loader->isReady());
		OO_CHECK(format == kOOPixMapRGBA && pixMap.width == 8 && ((const uint8_t *)pixMap.pixels)[0] == 1);
		OOFreePixMap(&pixMap);

		// The factory's loader is one.
		oo::ObjCRef<OOTextureLoader *> made = cxx::OOTextureLoader::loaderWithPath(path, kOOTextureMinFilterLinear);
		OO_CHECK(dynamic_cast<OOPNGTextureLoader *>(oo::ToCxx(made.get())) != nullptr);
		OO_CHECK(oo::ToCxx(made.get())->getResult(&pixMap, &format, nullptr, nullptr));
		OOFreePixMap(&pixMap);

		// Reading on its own (as libpng's read callback does): the loader reads its file first.
		const oo::Ref<OOPNGTextureLoader> direct = oo::makeRef<OOPNGTextureLoader>();
		OO_CHECK(direct->initWithPath(WritePNG("direct.png", 8, 8, PNG_FORMAT_GA), 0));
		direct->loadTexture();
		OO_CHECK(direct->_data != nullptr && direct->_format == kOOPixMapGrayscaleAlpha && direct->_width == 8 && direct->_rowBytes == 16);
	}
}


OO_TEST_MAIN()
