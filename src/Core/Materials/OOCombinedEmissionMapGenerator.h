/*

OOCombinedEmissionMapGenerator.h

Generator which renders a single RGB emission map from some combination of
emission_map, emission, illumination_map, illumination_color and
emission_and_illumination_map parameters.


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

#pragma once

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "OOColor.h"
#include "OOTextureGenerator.h"
#include "oofnd/PList.hpp"

/*	A leaf of the texture generators, over OOTextureGenerator. Its caller
   (OOMultiTextureMaterial) makes it with the factories below, and hands the C++
   generator to the texture.
*/
class OOCombinedEmissionMapGenerator : public OOTextureGenerator {
 public:
  ~OOCombinedEmissionMapGenerator() override;  // was -dealloc

  /*	Were
     -initWithEmissionMapSpec:emissionColor:diffuseMap:diffuseColor:illuminationMapSpec:
          illuminationColor:optionsSpecifier: and
     -initWithEmissionAndIlluminationMapSpec:
          diffuseMap:diffuseColor:emissionColor:illuminationColor:optionsSpecifier:;
     null where they answered nil.
  */
  static std::shared_ptr<OOCombinedEmissionMapGenerator>
  generatorWithEmissionMapSpec(const oo::PList& emissionMapSpec,
                               OOColor* emissionColor, OOTexture* diffuseMap,
                               OOColor* diffuseColor,
                               const oo::PList& illuminationMapSpec,
                               OOColor* illuminationColor,
                               const oo::PList& spec);
  static std::shared_ptr<OOCombinedEmissionMapGenerator>
  generatorWithEmissionAndIlluminationMapSpec(
      const oo::PList& emissionAndIlluminationMapSpec, OOTexture* diffuseMap,
      OOColor* diffuseColor, OOColor* emissionColor, OOColor* illuminationColor,
      const oo::PList& spec);

#ifndef NDEBUG
  std::optional<std::string> descriptionComponents() const override;
#endif

  OOTextureFlags textureOptions() override;
  GLfloat anisotropy() override;
  GLfloat lodBias() override;
  std::optional<std::string> cacheKey() override;

  void loadTexture() override;

 private:
  bool initWithEmissionMapSpec(const oo::PList& emissionMapSpec,
                               OOColor* emissionColor, OOTexture* diffuseMap,
                               OOColor* diffuseColor,
                               const oo::PList& illuminationMapSpec,
                               OOColor* illuminationColor, bool isCombinedMap,
                               const oo::PList& spec);

  std::string constructCacheKey();

  std::string _cacheKey;

  oo::PList _emissionSpec;
  oo::PList _illuminationSpec;
  std::shared_ptr<OOTexture> _diffuseMap;

  OOPixMap _emissionPx = {};
  OOPixMap _diffusePx = {};
  OOPixMap _illuminationPx = {};
  std::shared_ptr<OOColor> _emissionColor;
  std::shared_ptr<OOColor> _illuminationColor;
  bool _isCombinedMap = false;

  OOTextureFlags _textureOptions = OOTextureFlags::kNone;
  GLfloat _anisotropy = 0;
  GLfloat _lodBias = 0;

#ifndef NDEBUG
  std::string _emissionDesc;
  std::string _illuminationDesc;
  std::string _diffuseDesc;
#endif
};
