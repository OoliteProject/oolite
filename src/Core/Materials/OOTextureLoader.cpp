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

// Kept first, in a block of its own: which header comes first decides whether
// MinGW's or the UCRT's printf/strtod family is used.
#include "OOTextureLoader.h"

#include <stdlib.h>

#include <cstring>
#include <format>
#include <typeinfo>

#include "OOConvertCubeMapToLatLong.h"
#include "OODebugStandards.h"
#include "OODemangle.h"
#include "OOFunctionAttributes.h"
#include "OOMaths.h"
#include "OOOpenGLExtensionManager.h"
#include "OOPNGTextureLoader.h"
#include "OOPixMapChannelOperations.h"
#include "OOTexture.h"
#include "OOTextureGenerator.h"
#include "OOTextureScaling.h"
#include "ResourceManager.h"
#include "Universe.h"
#include "oofnd/Defaults.hpp"
#include "oofnd/PListGet.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"
#include "oofnd/objc/OOException.h"

#define DUMP_CONVERTED_CUBE_MAPS 0

// Thresholds for reduced-detail texture shrinking in different circumstances.
constexpr unsigned kNeverShrinkThreshold = UINT32_MAX;
constexpr unsigned kDefaultShrinkThreshold = 512;
constexpr unsigned kExtraShrinkThreshold = 128;
constexpr unsigned kExtraShrinkMaxSize = 256;
constexpr unsigned kCubeShrinkThreshold = 256;

static unsigned sGLMaxSize;
static uint32_t sUserMaxSize;
static bool sReducedDetail;
static bool sHaveNPOTTextures =
    false;  // TODO: support "true" non-power-of-two textures.
static bool sHaveSetUp = false;

oo::Ref<OOTextureLoader> OOTextureLoader::loaderWithPath(
    const std::optional<std::string>& inPath, OOTextureFlags options) {
  std::string extension;
  oo::Ref<OOTextureLoader> result;

  if (EXPECT_NOT(!inPath.has_value())) return nullptr;
  if (EXPECT_NOT(!sHaveSetUp)) setUp();

  // Get reduced detail setting (every time, in case it changes; we don't want
  // to call through to Universe on the loading thread in case the
  // implementation becomes non-trivial).
  sReducedDetail = (UNIVERSE != nullptr ? UNIVERSE->reducedDetail() : false);

  // Get a suitable loader. FIXME -- this should sniff the data instead of
  // relying on extensions.
  extension = oo::str::lowercase(oo::str::pathExtension(*inPath));
  if (extension == "png") {
    // A C++ loader; the work manager retains it while it is queued.
    const oo::Ref<::OOPNGTextureLoader> loader =
        oo::makeRef<::OOPNGTextureLoader>();
    if (loader->initWithPath(inPath, options)) result = loader;
  } else {
    OO_LOG("texture.load.unknownType",
           "Can't use {} as a texture - extension \"{}\" does not identify a "
           "known type.",
           *inPath, extension);
  }

  if (result != nullptr) {
    if (!OOAsyncWorkManager::sharedAsyncWorkManager()->addTask(
            result.get(), OOAsyncWorkPriority::kMedium))
      result = nullptr;
  }

  return result;
}

oo::Ref<OOTextureLoader> OOTextureLoader::loaderWithTextureSpecifier(
    const oo::PList& specifier, OOTextureFlags extraOptions,
    const std::optional<std::string>& folder) {
  std::string name;
  std::optional<std::string> path;
  OOTextureFlags options = OOTextureFlags::kNone;

  if (!cxx_OOInterpretTextureSpecifier(specifier, &name, &options, nullptr,
                                       nullptr, false))
    return nullptr;
  options |= extraOptions;
  path = ResourceManager::pathForFileNamed(name, folder);
  if (!path.has_value()) {
    if (!oo::Any(options & OOTextureFlags::kNoFNFMessage)) {
      OO_LOG_WARN(cxx_kOOLogFileNotFound, "Could not find texture file \"{}\".",
                  name);
      cxx_OOStandardsError("Texture file not found");
    }
    return nullptr;
  }

  return loaderWithPath(path, options);
}

OOTextureLoader::OOTextureLoader() {}

/*	The part of -cxx_initWithPath:options: after [super init]; false where
   it released the receiver and answered nil.
*/
bool OOTextureLoader::initWithPath(const std::optional<std::string>& inPath,
                                   OOTextureFlags options) {
  if (EXPECT_NOT(!inPath.has_value())) {
    return false;
  }
  _path = *inPath;

  _options = options;

  _maxSize = MIN(sUserMaxSize, sGLMaxSize);

  _generateMipMaps = (options & OOTextureFlags::kMinFilterMask) ==
                     OOTextureFlags::kMinFilterMipMap;
  _avoidShrinking = oo::Any(options & OOTextureFlags::kNoShrink);
  _noScalingWhatsoever = oo::Any(options & OOTextureFlags::kNeverScale);
  if (_avoidShrinking || _noScalingWhatsoever) {
    _shrinkThreshold = kNeverShrinkThreshold;
  } else if (oo::Any(options & OOTextureFlags::kExtraShrink)) {
    _shrinkThreshold = kExtraShrinkThreshold;
    _maxSize = MIN(_maxSize, (uint32_t)kExtraShrinkMaxSize);
  } else {
    _shrinkThreshold = kDefaultShrinkThreshold;
  }
#if OO_TEXTURE_CUBE_MAP
  _allowCubeMap = oo::Any(options & OOTextureFlags::kAllowCubeMap);
#endif

  if (oo::Any(options & OOTextureFlags::kExtractChannelMask)) {
    _extractChannel = true;
    switch (options & OOTextureFlags::kExtractChannelMask) {
      case OOTextureFlags::kExtractChannelR:
        _extractChannelIndex = 0;
        break;

      case OOTextureFlags::kExtractChannelG:
        _extractChannelIndex = 1;
        break;

      case OOTextureFlags::kExtractChannelB:
        _extractChannelIndex = 2;
        break;

      case OOTextureFlags::kExtractChannelA:
        _extractChannelIndex = 3;
        break;

      default:
        OO_LOG_ERR(
            "texture.load.unknownExtractChannelMask",
            "Unknown texture extract channel mask (0x{:04X}). This is an "
            "internal error, please report it.",
            static_cast<unsigned>(options &
                                  OOTextureFlags::kExtractChannelMask));
        _extractChannel = false;
    }
  }

  return true;
}

OOTextureLoader::~OOTextureLoader() {
  free(_data);
  _data = nullptr;
}

std::optional<std::string> OOTextureLoader::descriptionComponents() const {
  const char* state = nullptr;

  if (_ready) {
    if (_data != nullptr)
      state = "ready";
    else
      state = "failed";
  } else {
    state = "loading";
#if INSTRUMENT_TEXTURE_LOADING
    if (debugHasLoaded) state = "loaded";
#endif
  }

  return std::format("{{{} -- {}}}", _path, state);
}

std::optional<std::string> OOTextureLoader::shortDescriptionComponents() const {
  return oo::str::lastPathComponent(_path);
}

namespace {

std::string DemangledName(const std::type_info& type) {
  std::string result = OODemangle(type.name());
  return result;
}

}  // namespace

std::string OOTextureLoader::className() const {
  return DemangledName(typeid(*this));
}

std::string OOTextureLoader::description() const {
  std::string result =
      std::format("<{} {}>", className(), oo::str::pointerDescription(this));
  if (const std::optional<std::string> components = descriptionComponents())
    result += "{" + *components + "}";
  return result;
}

std::string OOTextureLoader::shortDescription() const {
  const char* facadeClass =
      (dynamic_cast<const OOTextureGenerator*>(this) != nullptr)
          ? "OOTextureGenerator"
          : "OOTextureLoader";
  std::string result =
      std::format("<{} {}>", facadeClass, oo::str::pointerDescription(this));
  if (const std::optional<std::string> components =
          shortDescriptionComponents())
    result += "{" + *components + "}";
  return result;
}

std::optional<std::string> OOTextureLoader::path() { return _path; }

bool OOTextureLoader::isReady() { return _ready; }

bool OOTextureLoader::getResult(OOPixMap* result,
                                OOTextureDataFormat* outFormat,
                                uint32_t* outWidth, uint32_t* outHeight) {
  OOCParameterAssert(result != nullptr && outFormat != nullptr);

  bool OK = true;

  if (!_ready) {
    // The work manager knows the task as the C++ loader.
    OOAsyncWorkManager::sharedAsyncWorkManager()->waitForTaskToComplete(this);
  }
  if (_data == nullptr) OK = false;

  if (OK) {
    *result = OOMakePixMap(
        _data, _width, _height,
        static_cast<OOPixMapFormat>(OOTextureComponentsForFormat(_format)), 0,
        0);
    _data = nullptr;
    *outFormat = _format;
    OK = OOIsValidPixMap(*result);
    if (outWidth != nullptr) *outWidth = _originalWidth;
    if (outHeight != nullptr) *outHeight = _originalHeight;
  }

  if (!OK) {
    *result = kOONullPixMap;
    *outFormat = kOOTextureDataInvalid;
  }

  return OK;
}

std::optional<std::string> OOTextureLoader::cacheKey() {
  return std::format("{}:0x{:04X}", oo::str::lastPathComponent(*path()),
                     oo::ToUnderlying(_options));
}

void OOTextureLoader::loadTexture() { OOLogGenericSubclassResponsibility(); }

void OOTextureLoader::setUp() {
  // Load two maximum sizes - graphics hardware limit and user-specified limit.
  GLint maxSize;
  OOGL(glGetIntegerv(GL_MAX_TEXTURE_SIZE, &maxSize));
  sGLMaxSize = MAX(maxSize, 64);
  OO_LOG("texture.load.rescale.maxSize", "GL maximum texture size: {}",
         static_cast<unsigned>(sGLMaxSize));

  // Why 0x80000000? Because it's the biggest number OORoundUpToPowerOf2() can
  // handle.
  {
    const oo::PList maxTex =
        oo::Defaults::standard().object("max-texture-size");
    sUserMaxSize = oo::PListGet<unsigned int>::from(
        maxTex.isNull() ? nullptr : &maxTex, 0x80000000);
  }
  if (sUserMaxSize < 0x80000000)
    OO_LOG("texture.load.rescale.maxSize", "User maximum texture size: {}",
           static_cast<unsigned>(sUserMaxSize));
  sUserMaxSize = OORoundUpToPowerOf2_32(sUserMaxSize);
  sUserMaxSize = MAX(sUserMaxSize, 64U);

  sHaveSetUp = true;
}

/*** Methods performed on the loader thread. ***/

void OOTextureLoader::performAsyncTask() {
  try {
    OO_LOG("texture.load.asyncLoad", "Loading texture {}",
           oo::str::lastPathComponent(_path));

    loadTexture();

    // Catch an error I've seen but not diagnosed yet.
    if (_data != nullptr && OOTextureComponentsForFormat(_format) == 0) {
      OO_LOG("texture.load.failed.internalError",
             "Texture loader internal error for {}: data is non-null but data "
             "format is invalid ({}).",
             _path, static_cast<unsigned>(_format));
      free(_data);
      _data = nullptr;
    }

    if (_data != nullptr) applySettings();

    OO_LOG("texture.load.asyncLoad.done", "{}", "Loading complete.");
  } catch (...) {
    const auto exception = oo::CurrentOOException();
    if (!exception) throw;  // not an OOException: it goes on up, as before
    OO_LOG("texture.load.asyncLoad.exception",
           "***** Exception loading texture {}: {} ({}).", _path,
           exception->name(), exception->reason());

    // Be sure to signal load failure.
    free(_data);
    _data = nullptr;
  }
}

void OOTextureLoader::generateMipMapsForCubeMap() {
  // Generate mip maps for each cube face.
  OOCParameterAssert(_data != nullptr);

  uint8_t components = OOTextureComponentsForFormat(_format);
  size_t srcSideSize =
      _width * _width * components;  // Space for one side without mip-maps.
  size_t newSideSize =
      srcSideSize * 4 / 3;                 // Space for one side with mip-maps.
  newSideSize = (newSideSize + 15) & ~15;  // Round up to multiple of 16 bytes.
  size_t newSize = newSideSize * 6;        // Space for all six sides.

  void* newData = malloc(newSize);
  if (EXPECT_NOT(newData == nullptr)) {
    _generateMipMaps = false;
    _options = (_options & ~OOTextureFlags::kMinFilterMask) |
               OOTextureFlags::kMinFilterLinear;
    return;
  }

  unsigned i;
  for (i = 0; i < 6; i++) {
    void* srcBytes = (static_cast<uint8_t*>(_data)) + srcSideSize * i;
    void* dstBytes = (static_cast<uint8_t*>(newData)) + newSideSize * i;

    memcpy(dstBytes, srcBytes, srcSideSize);
    OOGenerateMipMaps(dstBytes, _width, _width, _format);
  }

  free(_data);
  _data = newData;
}

void OOTextureLoader::applySettings() {
  OOPixMapDimension desiredWidth, desiredHeight;
  bool rescale;
  size_t newSize;
  uint8_t components;
  OOPixMap pixMap;

  components = OOTextureComponentsForFormat(_format);

  // Apply defaults.
  if (_originalWidth == 0) _originalWidth = _width;
  if (_originalHeight == 0) _originalHeight = _height;
  if (_rowBytes == 0) _rowBytes = _width * components;

  pixMap = OOMakePixMap(_data, _width, _height,
                        static_cast<OOPixMapFormat>(components), _rowBytes, 0);

  if (_extractChannel) {
    if (OOExtractPixMapChannel(&pixMap, _extractChannelIndex, false)) {
      _format = kOOTextureDataGrayscale;
      components = 1;
    } else {
      OO_LOG_WARN("texture.load.extractChannel.invalid",
                  "Cannot extract channel from texture \"{}\"",
                  oo::str::lastPathComponent(_path));
    }
  }

  getDesiredWidth(&desiredWidth, &desiredHeight);

  if (_isCubeMap && !OOCubeMapsAvailable()) {
    OOPixMapToRGBA(&pixMap);
    desiredHeight = MIN(desiredWidth * 2, 512U);
    if (sReducedDetail && desiredHeight > kCubeShrinkThreshold)
      desiredHeight /= 2;
    desiredWidth = desiredHeight * 2;

    OOPixMap converted =
        OOConvertCubeMapToLatLong(pixMap, desiredHeight, _generateMipMaps);
    OOFreePixMap(&pixMap);
    pixMap = converted;
    _isCubeMap = false;

#if DUMP_CONVERTED_CUBE_MAPS
    // -stringByDeletingPathExtension of the last path component (probed): cut
    // at its last '.', unless that starts the name.
    std::string dumpName = oo::str::lastPathComponent(_path);
    const std::string::size_type dot = dumpName.rfind('.');
    if (dot != std::string::npos && dot != 0) dumpName.erase(dot);
    OODumpPixMap(pixMap, std::format("converted cube map {}", dumpName));
#endif
  }

  // Rescale if needed.
  rescale = (_width != desiredWidth || _height != desiredHeight);
  if (rescale) {
    bool leaveSpaceForMipMaps = _generateMipMaps;
#if OO_TEXTURE_CUBE_MAP
    if (_isCubeMap) leaveSpaceForMipMaps = false;
#endif

    OO_LOG("texture.load.rescale",
           "Rescaling texture \"{}\" from {} x {} to {} x {}.",
           oo::str::lastPathComponent(_path),
           static_cast<unsigned>(pixMap.width),
           static_cast<unsigned>(pixMap.height),
           static_cast<unsigned>(desiredWidth),
           static_cast<unsigned>(desiredHeight));

    pixMap = OOScalePixMap(pixMap, desiredWidth, desiredHeight,
                           leaveSpaceForMipMaps);
    if (EXPECT_NOT(!OOIsValidPixMap(pixMap))) return;

    _data = pixMap.pixels;
    _width = pixMap.width;
    _height = pixMap.height;
    _rowBytes = pixMap.rowBytes;
  }

#if OO_TEXTURE_CUBE_MAP
  if (_isCubeMap) {
    if (_generateMipMaps) {
      generateMipMapsForCubeMap();
    }
    return;
  }
#endif

  // Generate mip maps if needed.
  if (_generateMipMaps) {
    // Make space if needed.
    newSize = desiredWidth * components * desiredHeight;
    newSize = (newSize * 4) / 3;
    // +1 to fix overrun valgrind spotted - CIM
    _generateMipMaps = OOExpandPixMap(&pixMap, newSize + 1);

    _data = pixMap.pixels;
    _width = pixMap.width;
    _height = pixMap.height;
    _rowBytes = pixMap.rowBytes;
  }
  if (_generateMipMaps) {
    OOGenerateMipMaps(_data, _width, _height, _format);
  }

  // All done.
}

void OOTextureLoader::getDesiredWidth(OOPixMapDimension* outDesiredWidth,
                                      OOPixMapDimension* outDesiredHeight) {
  OOPixMapDimension desiredWidth, desiredHeight;

  // Work out appropriate final size for textures.
  if (!_noScalingWhatsoever) {
    // Cube maps are six times as high as they are wide, and we need to preserve
    // that.
    if (_allowCubeMap && _height == _width * 6) {
      _isCubeMap = true;

      desiredWidth = OORoundUpToPowerOf2_PixMap((2 * _width) / 3);
      desiredWidth = MIN(desiredWidth, sGLMaxSize / 8);
      if (sReducedDetail) {
        if (256 < desiredWidth) desiredWidth /= 2;
      }
      desiredWidth = MIN(desiredWidth, sUserMaxSize / 4);

      desiredHeight = desiredWidth * 6;
    } else {
      if (!sHaveNPOTTextures) {
        // Round to nearest power of two. NOTE: this is duplicated in
        // OOTextureVerifierStage.m.
        desiredWidth = OORoundUpToPowerOf2_PixMap((2 * _width) / 3);
        desiredHeight = OORoundUpToPowerOf2_PixMap((2 * _height) / 3);
      } else {
        desiredWidth = _width;
        desiredHeight = _height;
      }

      desiredWidth = MIN(desiredWidth, sGLMaxSize);
      desiredHeight = MIN(desiredHeight, sGLMaxSize);

      if (!_avoidShrinking) {
        if (sReducedDetail) {
          if (_shrinkThreshold < desiredWidth) desiredWidth /= 2;
          if (_shrinkThreshold < desiredHeight) desiredHeight /= 2;
        }

        desiredWidth = MIN(desiredWidth, _maxSize);
        desiredHeight = MIN(desiredHeight, _maxSize);
      }
    }
  } else {
    desiredWidth = _width;
    desiredHeight = _height;
  }

  if (outDesiredWidth != nullptr) *outDesiredWidth = desiredWidth;
  if (outDesiredHeight != nullptr) *outDesiredHeight = desiredHeight;
}

void OOTextureLoader::completeAsyncTask() { _ready = true; }
