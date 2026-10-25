/*

OOTextureLoader.m


Copyright (C) 2007-2014 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#include "OOPNGTextureLoader.h"
#include "OOTexture.h"
#include "OOTextureLoader.h"
#include "OOFunctionAttributes.h"
#include "OOMaths.h"
#include "Universe.h"
#include "OOTextureScaling.h"
#include "OOPixMapChannelOperations.h"
#include "OOConvertCubeMapToLatLong.h"
#include <stdlib.h>
#include "ResourceManager.h"
#include "OOOpenGLExtensionManager.h"
#include "OODebugStandards.h"
#include "oofnd/objc/OOException.h"
#include "oofnd/Defaults.hpp"
#include "oofnd/PListGet.hpp"

#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"
#include "OOTextureGenerator.h"

#include <cstdlib>
#include <cxxabi.h>
#include <typeinfo>


#define DUMP_CONVERTED_CUBE_MAPS	0

enum
{
	// Thresholds for reduced-detail texture shrinking in different circumstances.
	kNeverShrinkThreshold		= UINT32_MAX,
	kDefaultShrinkThreshold		= 512,
	kExtraShrinkThreshold		= 128,
	kExtraShrinkMaxSize			= 256,
	kCubeShrinkThreshold		= 256
};


static unsigned				sGLMaxSize;
static uint32_t				sUserMaxSize;
static BOOL					sReducedDetail;
static BOOL					sHaveNPOTTextures = NO;	// TODO: support "true" non-power-of-two textures.
static BOOL					sHaveSetUp = NO;


oo::Ref<OOTextureLoader> OOTextureLoader::loaderWithPath(const std::optional<std::string> &inPath, uint32_t options)
{
	std::string					extension;
	oo::Ref<OOTextureLoader>	result;

	if (EXPECT_NOT(!inPath.has_value())) return nullptr;
	if (EXPECT_NOT(!sHaveSetUp))  setUp();

	// Get reduced detail setting (every time, in case it changes; we don't want to call through to Universe on the loading thread in case the implementation becomes non-trivial).
	sReducedDetail = (UNIVERSE != nullptr ? UNIVERSE->reducedDetail() : false);

	// Get a suitable loader. FIXME -- this should sniff the data instead of relying on extensions.
	extension = oo::str::lowercase(oo::str::pathExtension(*inPath));
	if (extension == "png")
	{
		// A C++ loader (bead oo-z889); the work manager retains it while it is queued.
		const oo::Ref<::OOPNGTextureLoader> loader = oo::makeRef<::OOPNGTextureLoader>();
		if (loader->initWithPath(inPath, options))  result = loader;
	}
	else
	{
		OO_LOG("texture.load.unknownType", "Can't use {} as a texture - extension \"{}\" does not identify a known type.", *inPath, extension);
	}

	if (result != nullptr)
	{
		if (!OOAsyncWorkManager::sharedAsyncWorkManager()->addTask(result.get(), kOOAsyncPriorityMedium))  result = nullptr;
	}

	return result;
}


oo::Ref<OOTextureLoader> OOTextureLoader::loaderWithTextureSpecifier(const oo::PList &specifier, uint32_t extraOptions, const std::optional<std::string> &folder)
{
	std::string					name;
	std::optional<std::string>	path;
	uint32_t					options = 0;

	if (!cxx_OOInterpretTextureSpecifier(specifier, &name, &options, NULL, NULL, NO))  return nullptr;
	options |= extraOptions;
	path = ResourceManager::pathForFileNamed(name, folder);
	if (!path.has_value())
	{
		if (!(options & kOOTextureNoFNFMessage))
		{
			OO_LOG_WARN(cxx_kOOLogFileNotFound, "Could not find texture file \"{}\".", name);
			cxx_OOStandardsError("Texture file not found");
		}
		return nullptr;
	}

	return loaderWithPath(path, options);
}


OOTextureLoader::OOTextureLoader()
{
}


/*	The part of -cxx_initWithPath:options: after [super init]; false where it released the receiver
	and answered nil.
*/
bool OOTextureLoader::initWithPath(const std::optional<std::string> &inPath, uint32_t options)
{
	if (EXPECT_NOT(!inPath.has_value()))
	{
		return false;
	}
	_path = *inPath;

	_options = options;

	_maxSize = MIN(sUserMaxSize, sGLMaxSize);

	_generateMipMaps = (options & kOOTextureMinFilterMask) == kOOTextureMinFilterMipMap;
	_avoidShrinking = (options & kOOTextureNoShrink) != 0;
	_noScalingWhatsoever = (options & kOOTextureNeverScale) != 0;
	if (_avoidShrinking || _noScalingWhatsoever)
	{
		_shrinkThreshold = kNeverShrinkThreshold;
	}
	else if (options & kOOTextureExtraShrink)
	{
		_shrinkThreshold = kExtraShrinkThreshold;
		_maxSize = MIN(_maxSize, (uint32_t)kExtraShrinkMaxSize);
	}
	else {
		_shrinkThreshold = kDefaultShrinkThreshold;
	}
#if OO_TEXTURE_CUBE_MAP
	_allowCubeMap = (options & kOOTextureAllowCubeMap) != 0;
#endif

	if (options & kOOTextureExtractChannelMask)
	{
		_extractChannel = YES;
		switch (options & kOOTextureExtractChannelMask)
		{
			case kOOTextureExtractChannelR:
				_extractChannelIndex = 0;
				break;

			case kOOTextureExtractChannelG:
				_extractChannelIndex = 1;
				break;

			case kOOTextureExtractChannelB:
				_extractChannelIndex = 2;
				break;

			case kOOTextureExtractChannelA:
				_extractChannelIndex = 3;
				break;

			default:
				OO_LOG_ERR("texture.load.unknownExtractChannelMask", "Unknown texture extract channel mask (0x{:04X}). This is an internal error, please report it.", static_cast<unsigned>(options & kOOTextureExtractChannelMask));
				_extractChannel =  NO;
		}
	}

	return true;
}


OOTextureLoader::~OOTextureLoader()
{
	free(_data);
	_data = NULL;
}


std::optional<std::string> OOTextureLoader::descriptionComponents() const
{
	const char			*state = nullptr;

	if (_ready)
	{
		if (_data != NULL)  state = "ready";
		else  state = "failed";
	}
	else
	{
		state = "loading";
#if INSTRUMENT_TEXTURE_LOADING
		if (debugHasLoaded)  state = "loaded";
#endif
	}

	return oo::str::format("{%s -- %s}", _path.c_str(), state);
}


std::optional<std::string> OOTextureLoader::shortDescriptionComponents() const
{
	return oo::str::lastPathComponent(_path);
}


namespace {

std::string DemangledName(const std::type_info &type)
{
	int status = 0;
	char *demangled = abi::__cxa_demangle(type.name(), nullptr, nullptr, &status);
	std::string result = (status == 0 && demangled != nullptr) ? demangled : type.name();
	std::free(demangled);
	return result;
}

}	// namespace


std::string OOTextureLoader::className() const
{
	return DemangledName(typeid(*this));
}


std::string OOTextureLoader::description() const
{
	std::string result = oo::str::format("<%s %s>", className().c_str(), oo::str::pointerDescription(this).c_str());
	if (const std::optional<std::string> components = descriptionComponents())  result += "{" + *components + "}";
	return result;
}


std::string OOTextureLoader::shortDescription() const
{
	const char *facadeClass = (dynamic_cast<const OOTextureGenerator *>(this) != nullptr) ? "OOTextureGenerator" : "OOTextureLoader";
	std::string result = oo::str::format("<%s %s>", facadeClass, oo::str::pointerDescription(this).c_str());
	if (const std::optional<std::string> components = shortDescriptionComponents())  result += "{" + *components + "}";
	return result;
}


std::optional<std::string> OOTextureLoader::path()
{
	return _path;
}


bool OOTextureLoader::isReady()
{
	return _ready;
}


bool OOTextureLoader::getResult(OOPixMap *result,
								OOTextureDataFormat *outFormat,
								uint32_t *outWidth,
								uint32_t *outHeight)
{
	OOCParameterAssert(result != NULL && outFormat != NULL);

	BOOL		OK = YES;

	if (!_ready)
	{
		// The work manager knows the task as the C++ loader (bead oo-9ht.14).
		OOAsyncWorkManager::sharedAsyncWorkManager()->waitForTaskToComplete(this);
	}
	if (_data == NULL)  OK = NO;

	if (OK)
	{
		*result = OOMakePixMap(_data, _width, _height, (OOPixMapFormat)OOTextureComponentsForFormat(_format), 0, 0);
		_data = NULL;
		*outFormat = _format;
		OK = OOIsValidPixMap(*result);
		if (outWidth != NULL)  *outWidth = _originalWidth;
		if (outHeight != NULL)  *outHeight = _originalHeight;
	}

	if (!OK)
	{
		*result = kOONullPixMap;
		*outFormat = (OOTextureDataFormat)kOOTextureDataInvalid;
	}

	return OK;
}


std::optional<std::string> OOTextureLoader::cacheKey()
{
	return oo::str::format("%s:0x%.4X", oo::str::lastPathComponent(*path()).c_str(), _options);
}



void OOTextureLoader::loadTexture()
{
	OOLogGenericSubclassResponsibility();
}


void OOTextureLoader::setUp()
{
	// Load two maximum sizes - graphics hardware limit and user-specified limit.
	GLint maxSize;
	OOGL(glGetIntegerv(GL_MAX_TEXTURE_SIZE, &maxSize));
	sGLMaxSize = MAX(maxSize, 64);
	OO_LOG("texture.load.rescale.maxSize", "GL maximum texture size: {}", static_cast<unsigned>(sGLMaxSize));

	// Why 0x80000000? Because it's the biggest number OORoundUpToPowerOf2() can handle.
	{
		const oo::PList maxTex = oo::Defaults::standard().object("max-texture-size");
		sUserMaxSize = oo::PListGet<unsigned int>::from(maxTex.isNull() ? nullptr : &maxTex, 0x80000000);
	}
	if (sUserMaxSize < 0x80000000)  OO_LOG("texture.load.rescale.maxSize", "User maximum texture size: {}", static_cast<unsigned>(sUserMaxSize));
	sUserMaxSize = OORoundUpToPowerOf2_32(sUserMaxSize);
	sUserMaxSize = MAX(sUserMaxSize, 64U);


	sHaveSetUp = YES;
}


/*** Methods performed on the loader thread. ***/

void OOTextureLoader::performAsyncTask()
{
	try
	{
		OO_LOG("texture.load.asyncLoad", "Loading texture {}", oo::str::lastPathComponent(_path));

		loadTexture();

		// Catch an error I've seen but not diagnosed yet.
		if (_data != NULL && OOTextureComponentsForFormat(_format) == 0)
		{
			OO_LOG("texture.load.failed.internalError", "Texture loader internal error for {}: data is non-null but data format is invalid ({}).", _path, static_cast<unsigned>(_format));
			free(_data);
			_data = NULL;
		}

		if (_data != NULL)  applySettings();

		OO_LOG("texture.load.asyncLoad.done", "{}", "Loading complete.");
	}
	catch (...)
	{
		const auto exception = oo::CurrentOOException();
		if (!exception)  throw;	// not an OOException: it goes on up, as before
		OO_LOG("texture.load.asyncLoad.exception", "***** Exception loading texture {}: {} ({}).", _path, exception->name(), exception->reason());

		// Be sure to signal load failure.
		free(_data);
		_data = NULL;
	}
}


void OOTextureLoader::generateMipMapsForCubeMap()
{
	// Generate mip maps for each cube face.
	OOCParameterAssert(_data != NULL);
	
	uint8_t components = OOTextureComponentsForFormat(_format);
	size_t srcSideSize = _width * _width * components;	// Space for one side without mip-maps.
	size_t newSideSize = srcSideSize * 4 / 3;			// Space for one side with mip-maps.
	newSideSize = (newSideSize + 15) & ~15;				// Round up to multiple of 16 bytes.
	size_t newSize = newSideSize * 6;					// Space for all six sides.
	
	void *newData = malloc(newSize);
	if (EXPECT_NOT(newData == NULL))
	{
		_generateMipMaps = NO;
		_options = (_options & ~kOOTextureMinFilterMask) | kOOTextureMinFilterLinear;
		return;
	}
	
	unsigned i;
	for (i = 0; i < 6; i++)
	{
		void *srcBytes = ((uint8_t *)_data) + srcSideSize * i;
		void *dstBytes = ((uint8_t *)newData) + newSideSize * i;
		
		memcpy(dstBytes, srcBytes, srcSideSize);
		OOGenerateMipMaps(dstBytes, _width, _width, _format);
	}
	
	free(_data);
	_data = newData;
}


void OOTextureLoader::applySettings()
{
	OOPixMapDimension	desiredWidth, desiredHeight;
	BOOL				rescale;
	size_t				newSize;
	uint8_t				components;
	OOPixMap			pixMap;
	
	components = OOTextureComponentsForFormat(_format);
	
	// Apply defaults.
	if (_originalWidth == 0)  _originalWidth = _width;
	if (_originalHeight == 0)  _originalHeight = _height;
	if (_rowBytes == 0)  _rowBytes = _width * components;
	
	pixMap = OOMakePixMap(_data, _width, _height, (OOPixMapFormat)components, _rowBytes, 0);
	
	if (_extractChannel)
	{
		if (OOExtractPixMapChannel(&pixMap, _extractChannelIndex, NO))
		{
			_format = (OOTextureDataFormat)kOOTextureDataGrayscale;
			components = 1;
		}
		else
		{
			OO_LOG_WARN("texture.load.extractChannel.invalid", "Cannot extract channel from texture \"{}\"", oo::str::lastPathComponent(_path));
		}
	}
	
	getDesiredWidth(&desiredWidth, &desiredHeight);
	
	if (_isCubeMap && !OOCubeMapsAvailable())
	{
		OOPixMapToRGBA(&pixMap);
		desiredHeight = MIN(desiredWidth * 2, 512U);
		if (sReducedDetail && desiredHeight > kCubeShrinkThreshold)  desiredHeight /= 2;
		desiredWidth = desiredHeight * 2;
		
		OOPixMap converted = OOConvertCubeMapToLatLong(pixMap, desiredHeight, _generateMipMaps);
		OOFreePixMap(&pixMap);
		pixMap = converted;
		_isCubeMap = NO;
		
#if DUMP_CONVERTED_CUBE_MAPS
		// -stringByDeletingPathExtension of the last path component (probed): cut at its last '.',
		// unless that starts the name.
		std::string dumpName = oo::str::lastPathComponent(_path);
		const std::string::size_type dot = dumpName.rfind('.');
		if (dot != std::string::npos && dot != 0)  dumpName.erase(dot);
		OODumpPixMap(pixMap, oo::str::format("converted cube map %s", dumpName.c_str()));
#endif
	}
	
	// Rescale if needed.
	rescale = (_width != desiredWidth || _height != desiredHeight);
	if (rescale)
	{
		BOOL leaveSpaceForMipMaps = _generateMipMaps;
#if OO_TEXTURE_CUBE_MAP
		if (_isCubeMap)  leaveSpaceForMipMaps = NO;
#endif
		
		OO_LOG("texture.load.rescale", "Rescaling texture \"{}\" from {} x {} to {} x {}.", oo::str::lastPathComponent(_path), static_cast<unsigned>(pixMap.width), static_cast<unsigned>(pixMap.height), static_cast<unsigned>(desiredWidth), static_cast<unsigned>(desiredHeight));
		
		pixMap = OOScalePixMap(pixMap, desiredWidth, desiredHeight, leaveSpaceForMipMaps);
		if (EXPECT_NOT(!OOIsValidPixMap(pixMap)))  return;
		
		_data = pixMap.pixels;
		_width = pixMap.width;
		_height = pixMap.height;
		_rowBytes = pixMap.rowBytes;
	}
	
#if OO_TEXTURE_CUBE_MAP
	if (_isCubeMap)
	{
		if (_generateMipMaps)
		{
			generateMipMapsForCubeMap();
		}
		return;
	}
#endif
	
	// Generate mip maps if needed.
	if (_generateMipMaps)
	{
		// Make space if needed.
		newSize = desiredWidth * components * desiredHeight;
		newSize = (newSize * 4) / 3;
		// +1 to fix overrun valgrind spotted - CIM
		_generateMipMaps = OOExpandPixMap(&pixMap, newSize+1);
		
		_data = pixMap.pixels;
		_width = pixMap.width;
		_height = pixMap.height;
		_rowBytes = pixMap.rowBytes;
	}
	if (_generateMipMaps)
	{
		OOGenerateMipMaps(_data, _width, _height, _format);
	}
	
	// All done.
}


void OOTextureLoader::getDesiredWidth(OOPixMapDimension *outDesiredWidth, OOPixMapDimension *outDesiredHeight)
{
	OOPixMapDimension	desiredWidth, desiredHeight;
	
	// Work out appropriate final size for textures.
	if (!_noScalingWhatsoever)
	{
		// Cube maps are six times as high as they are wide, and we need to preserve that.
		if (_allowCubeMap && _height == _width * 6)
		{
			_isCubeMap = YES;
			
			desiredWidth = OORoundUpToPowerOf2_PixMap((2 * _width) / 3);
			desiredWidth = MIN(desiredWidth, sGLMaxSize / 8);
			if (sReducedDetail)
			{
				if (256 < desiredWidth)  desiredWidth /= 2;
			}
			desiredWidth = MIN(desiredWidth, sUserMaxSize / 4);
			
			desiredHeight = desiredWidth * 6;
		}
		else
		{
			if (!sHaveNPOTTextures)
			{
				// Round to nearest power of two. NOTE: this is duplicated in OOTextureVerifierStage.m.
				desiredWidth = OORoundUpToPowerOf2_PixMap((2 * _width) / 3);
				desiredHeight = OORoundUpToPowerOf2_PixMap((2 * _height) / 3);
			}
			else
			{
				desiredWidth = _width;
				desiredHeight = _height;
			}
			
			desiredWidth = MIN(desiredWidth, sGLMaxSize);
			desiredHeight = MIN(desiredHeight, sGLMaxSize);
			
			if (!_avoidShrinking)
			{
				if (sReducedDetail)
				{
					if (_shrinkThreshold < desiredWidth)  desiredWidth /= 2;
					if (_shrinkThreshold < desiredHeight)  desiredHeight /= 2;
				}
				
				desiredWidth = MIN(desiredWidth, _maxSize);
				desiredHeight = MIN(desiredHeight, _maxSize);
			}
		}
	}
	else
	{
		desiredWidth = _width;
		desiredHeight = _height;
	}
	
	if (outDesiredWidth != NULL)  *outDesiredWidth = desiredWidth;
	if (outDesiredHeight != NULL)  *outDesiredHeight = desiredHeight;
}


void OOTextureLoader::completeAsyncTask()
{
	_ready = YES;
}
