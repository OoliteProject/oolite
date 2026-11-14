/*

OOCombinedEmissionMapGenerator.mm


Copyright (C) 2010-2013 Jens Ayton

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

#include "OOCombinedEmissionMapGenerator.h"

#include "OOColor.h"
#include "OOMaterialSpecifier.h"
#include "OOPixMapChannelOperations.h"
#include "OOTextureInternal.h"
#include "OOTextureLoader.h"
#include "OOTextureScaling.h"
#include "oofnd/Log.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"

#define DUMP_COMBINER 0

namespace {

oo::PList SpecWithExtraShrink(const oo::PList& spec) {
  if (spec.isNull()) return oo::PList();
  oo::PList copy = spec;
  if (oo::PList::Dict* dict = copy.getIf<oo::PList::Dict>()) {
    (*dict)[cxx_kOOTextureSpecifierExtraShrinkKey] = oo::PList(true);
  }
  return copy;
}

oo::Ref<OOColor> ModulateColor(OOColor* a, OOColor* b) {
  if (a == nullptr) return oo::Ref<OOColor>(b);
  if (b == nullptr) return oo::Ref<OOColor>(a);

  OORGBAComponents ac, bc;
  ac = a->rgbaComponents();
  bc = b->rgbaComponents();

  ac.r *= bc.r;
  ac.g *= bc.g;
  ac.b *= bc.b;
  ac.a *= bc.a;

  return OOColor::colorWithRGBAComponents(ac);
}

void ScaleToMatch(OOPixMap* pmA, OOPixMap* pmB) {
  OOCParameterAssert(pmA != NULL && pmB != NULL && OOIsValidPixMap(*pmA) &&
                     OOIsValidPixMap(*pmB));

  OOPixMapDimension minWidth = MIN(pmA->width, pmB->width);
  OOPixMapDimension minHeight = MIN(pmA->height, pmB->height);

  if (pmA->width != minWidth || pmA->height != minHeight) {
    *pmA = OOScalePixMap(*pmA, minWidth, minHeight, false);
  }
  if (pmB->width != minWidth || pmB->height != minHeight) {
    *pmB = OOScalePixMap(*pmB, minWidth, minHeight, false);
  }
}

}  // namespace

oo::Ref<OOCombinedEmissionMapGenerator>
OOCombinedEmissionMapGenerator::generatorWithEmissionMapSpec(
    const oo::PList& emissionMapSpec, OOColor* emissionColor,
    OOTexture* diffuseMap, OOColor* diffuseColor,
    const oo::PList& illuminationMapSpec, OOColor* illuminationColor,
    const oo::PList& spec) {
  oo::Ref<OOCombinedEmissionMapGenerator> result =
      oo::makeRef<OOCombinedEmissionMapGenerator>();
  if (!result->initWithEmissionMapSpec(
          emissionMapSpec, emissionColor, diffuseMap, diffuseColor,
          illuminationMapSpec, illuminationColor, false, spec))
    return {};
  return result;
}

oo::Ref<OOCombinedEmissionMapGenerator>
OOCombinedEmissionMapGenerator::generatorWithEmissionAndIlluminationMapSpec(
    const oo::PList& emissionAndIlluminationMapSpec, OOTexture* diffuseMap,
    OOColor* diffuseColor, OOColor* emissionColor, OOColor* illuminationColor,
    const oo::PList& spec) {
  oo::Ref<OOCombinedEmissionMapGenerator> result =
      oo::makeRef<OOCombinedEmissionMapGenerator>();
  if (!result->initWithEmissionMapSpec(
          emissionAndIlluminationMapSpec, emissionColor, diffuseMap,
          diffuseColor, oo::PList(), illuminationColor, true, spec))
    return {};
  return result;
}

// Was the private designated initialiser; false where it answered nil.
bool OOCombinedEmissionMapGenerator::initWithEmissionMapSpec(
    const oo::PList& emissionMapSpec, OOColor* emissionColor,
    OOTexture* diffuseMap, OOColor* diffuseColor,
    const oo::PList& illuminationMapSpec, OOColor* illuminationColor,
    bool isCombinedMap, const oo::PList& spec) {
  if (emissionMapSpec.isNull() && illuminationMapSpec.isNull()) {
    return false;
  }

  OOCParameterAssert(illuminationMapSpec.isNull() || !isCombinedMap);

  uint32_t options;
  GLfloat anisotropy;
  GLfloat lodBias;
  cxx_OOInterpretTextureSpecifier(spec, NULL, &options, &anisotropy, &lodBias,
                                  true);
  options = OOApplyTextureOptionDefaults(options);

  if (initWithPath(std::string("<generated emission map>"), options)) {
    /*	Illumination contribution is:
            illuminationMap * illuminationColor * diffuseMap * diffuseColor
            Since illuminationColor and diffuseColor aren't used otherwise,
            we may as well combine them up front.
    */
    const oo::Ref<OOColor> modulatedIlluminationColor =
        ModulateColor(diffuseColor, illuminationColor);
    illuminationColor = modulatedIlluminationColor.get();

    if (emissionColor != nullptr && emissionColor->isWhite())
      emissionColor = nullptr;
    if (illuminationColor != nullptr && illuminationColor->isWhite())
      illuminationColor = nullptr;
    if (!isCombinedMap && illuminationMapSpec.isNull())
      diffuseMap = nullptr;  // Diffuse map is only used with illumination

    // Insert extraShrink flag here instead of using extraOptions later because
    // we need it in cache key too.
    _emissionSpec = SpecWithExtraShrink(emissionMapSpec);
    _illuminationSpec = SpecWithExtraShrink(illuminationMapSpec);

    _diffuseMap = oo::Ref<OOTexture>(diffuseMap);

    _emissionColor = oo::Ref<OOColor>(emissionColor);
    _illuminationColor = oo::Ref<OOColor>(illuminationColor);
    _isCombinedMap = isCombinedMap;

    _textureOptions = options;
    _anisotropy = anisotropy;
    _lodBias = lodBias;

    _cacheKey = constructCacheKey();

    if (OOTexture::existingTextureForKey(_cacheKey) == nullptr) {
      /*	Extract pixmap from diffuse map. This must be done in the main
              thread even if scheduling is fixed, because it might involve
              reading back pixels from OpenGL.
      */
      if (diffuseMap != nullptr) {
        _diffusePx = diffuseMap->copyPixMapRepresentation();
#ifndef NDEBUG
        _diffuseDesc = diffuseMap->shortDescription();
#endif
      }

      /*	Extract emission and illumination pixmaps from loaders. Ideally,
              this would be done asynchronously, but that requires dependency
              management in OOAsyncWorkManager.
      */
      OOTextureDataFormat format;
      if (!_emissionSpec.isNull()) {
        const oo::Ref<OOTextureLoader> emissionMapLoader =
            OOTextureLoader::loaderWithTextureSpecifier(
                _emissionSpec, 0, std::string("Textures"));
        if (emissionMapLoader)
          emissionMapLoader->getResult(&_emissionPx, &format, NULL, NULL);
#ifndef NDEBUG
        _emissionDesc =
            (emissionMapLoader ? emissionMapLoader->shortDescription()
                               : std::string());
#endif
      }
      if (!_illuminationSpec.isNull()) {
        const oo::Ref<OOTextureLoader> illuminationMapLoader =
            OOTextureLoader::loaderWithTextureSpecifier(
                _illuminationSpec, 0, std::string("Textures"));
        if (illuminationMapLoader)
          illuminationMapLoader->getResult(&_illuminationPx, &format, NULL,
                                           NULL);
#ifndef NDEBUG
        _illuminationDesc =
            (illuminationMapLoader ? illuminationMapLoader->shortDescription()
                                   : std::string());
#endif
      }
    }
    return true;
  }

  return false;
}

std::string OOCombinedEmissionMapGenerator::constructCacheKey() {
  std::string cacheKey;

  if (_isCombinedMap)
    cacheKey += "combined emission and illumination map;";
  else if (_emissionSpec.isNull())
    cacheKey += "illumination map;";
  else if (_illuminationSpec.isNull())
    cacheKey += "emission map;";
  else
    cacheKey += "merged emission and illumination map;";

  std::string emissionDesc;
  if (!_emissionSpec.isNull()) {
    emissionDesc = cxx_OOTextureCacheKeyForSpecifier(_emissionSpec);
    cacheKey += oo::str::format("emission:{%s}", emissionDesc.c_str());
    if (_emissionColor) {
      const std::optional<std::string> rgba = _emissionColor->rgbaDescription();
      cacheKey += oo::str::format("*%s", rgba ? rgba->c_str() : "");
    }
    cacheKey += ";";
  }

  std::string illuminationDesc;
  if (_isCombinedMap) {
    illuminationDesc = emissionDesc + ":a";
  } else if (!_illuminationSpec.isNull()) {
    illuminationDesc = cxx_OOTextureCacheKeyForSpecifier(_illuminationSpec);
  }

  if (!illuminationDesc.empty()) {
    cacheKey +=
        oo::str::format("illumination:{%s}*{%s}", illuminationDesc.c_str(),
                        (_diffuseMap ? _diffuseMap->cacheKey() : std::nullopt)
                            .value_or("")
                            .c_str());
    if (_illuminationColor) {
      const std::optional<std::string> rgba =
          _illuminationColor->rgbaDescription();
      cacheKey += oo::str::format("*%s", rgba ? rgba->c_str() : "");
    }
    cacheKey += ";";
  }

  return cacheKey;
}

// Was -dealloc: the specs, the diffuse map and the colours are released with
// their members.
OOCombinedEmissionMapGenerator::~OOCombinedEmissionMapGenerator() {
  OOFreePixMap(&_emissionPx);
  OOFreePixMap(&_illuminationPx);
  OOFreePixMap(&_diffusePx);
}

#ifndef NDEBUG
std::optional<std::string>
OOCombinedEmissionMapGenerator::descriptionComponents() const {
  std::string result;
  bool haveIllumination = false;

  if (!_emissionDesc.empty()) {
    result += oo::str::format("emission map: %s", _emissionDesc.c_str());
    if (_isCombinedMap) {
      result += ".rgb";
    }
    if (_emissionColor) {
      const std::optional<std::string> rgba = _emissionColor->rgbaDescription();
      result += oo::str::format(" * %s", rgba ? rgba->c_str() : "");
    }

    if (_isCombinedMap) {
      result +=
          oo::str::format(", illumination map: %s.a", _emissionDesc.c_str());
      haveIllumination = true;
    }
  }

  if (!_illuminationDesc.empty()) {
    if (!_emissionDesc.empty()) result += ", ";
    result +=
        oo::str::format("illumination map: %s", _illuminationDesc.c_str());
    haveIllumination = true;
  }

  if (haveIllumination) {
    if (!_diffuseDesc.empty()) {
      result += oo::str::format(" * %s", _diffuseDesc.c_str());
    }
    if (_illuminationColor) {
      const std::optional<std::string> rgba =
          _illuminationColor->rgbaDescription();
      result += oo::str::format(" * %s", rgba ? rgba->c_str() : "");
    }
  }

  return result;
}
#endif

uint32_t OOCombinedEmissionMapGenerator::textureOptions() {
  return _textureOptions;
}

GLfloat OOCombinedEmissionMapGenerator::anisotropy() { return _anisotropy; }

GLfloat OOCombinedEmissionMapGenerator::lodBias() { return _lodBias; }

std::optional<std::string> OOCombinedEmissionMapGenerator::cacheKey() {
  return _cacheKey;
}

void OOCombinedEmissionMapGenerator::loadTexture() {
  OOPixMap illuminationPx = kOONullPixMap;
  bool haveEmission = false, haveIllumination = false, haveDiffuse = false;

#if DUMP_COMBINER
  static unsigned sTexID = 0;
  unsigned texID = ++sTexID, dumpCount = 0;

#define DUMP(pm, label) \
  OODumpPixMap(         \
      pm, oo::str::format("lightmap %u.%u - %s", texID, ++dumpCount, label));
#else
#define DUMP(pm, label) \
  do {                  \
  } while (0)
#endif

  haveEmission = !OOIsNullPixMap(_emissionPx);
  if (haveEmission) DUMP(_emissionPx, "source emission map");

  // Extract illumination component if emission_and_illumination_map.
  if (haveEmission && _isCombinedMap &&
      OOPixMapFormatHasAlpha(_emissionPx.format)) {
    OOPixMapToRGBA(&_emissionPx);
    illuminationPx = OODuplicatePixMap(_emissionPx, 0);
    OOExtractPixMapChannel(&illuminationPx, 3, true);
    haveIllumination = true;
    DUMP(illuminationPx, "extracted illumination map");
  }

  // Tint emission map if necessary.
  if (haveEmission && _emissionColor) {
    OOPixMapModulateUniform(&_emissionPx, _emissionColor->redComponent(),
                            _emissionColor->greenComponent(),
                            _emissionColor->blueComponent(), 1.0);
    DUMP(_emissionPx, "modulated emission map");
  }

  if (!OOIsNullPixMap(_illuminationPx)) {
    OOCAssert(!_isCombinedMap,
              "OOCombinedEmissionMapGenerator configured with both "
              "illumination map and combined emission/illumination map.");

    illuminationPx = _illuminationPx;
    _illuminationPx.pixels = NULL;
    haveIllumination = true;
    DUMP(illuminationPx, "source illumination map");
  }

  // Tint illumination map if necessary.
  if (haveIllumination && _illuminationColor) {
    OOPixMapModulateUniform(&illuminationPx, _illuminationColor->redComponent(),
                            _illuminationColor->greenComponent(),
                            _illuminationColor->blueComponent(), 1.0);
    DUMP(illuminationPx, "modulated illumination map");
  }

  // Load diffuse map and combine with illumination map.
  haveDiffuse = !OOIsNullPixMap(_diffusePx);
  if (haveDiffuse) DUMP(_diffusePx, "source diffuse map");

  if (haveIllumination && haveDiffuse) {
    // Modulate illumination with diffuse map.
    ScaleToMatch(&_diffusePx, &illuminationPx);
    OOPixMapToRGBA(&_diffusePx);
    OOPixMapModulatePixMap(&illuminationPx, _diffusePx);
    DUMP(illuminationPx, "combined diffuse and illumination map");
  }
  OOFreePixMap(&_diffusePx);

  if (haveIllumination) {
    if (haveEmission) {
      OOPixMapToRGBA(&illuminationPx);
      OOPixMapAddPixMap(&_emissionPx, illuminationPx);
      OOFreePixMap(&illuminationPx);
      DUMP(_emissionPx, "combined emission and illumination map");
    } else if (haveIllumination) {
      // No explicit emission map -> modulated illumination map is our only
      // emission map.
      _emissionPx = illuminationPx;
      haveEmission = true;
      illuminationPx.pixels = NULL;
    }
    haveIllumination =
        false;  // Either way, illumination is now baked into emission.
  }

  (void)haveEmission;
  (void)haveIllumination;

  // Done: emissionPx now contains combined emission map.
  OOCompactPixMap(&_emissionPx);
  if (OOIsValidPixMap(_emissionPx)) {
    _data = _emissionPx.pixels;
    _width = _emissionPx.width;
    _height = _emissionPx.height;
    _rowBytes = _emissionPx.rowBytes;
    _format = _emissionPx.format;

    _emissionPx.pixels = NULL;  // So it won't be freed by the destructor.
  }
  if (_data == NULL) {
    OO_LOG_ERR("texture.combinedEmissionMap.error", "Unknown error loading {}",
               description());
  }
}
