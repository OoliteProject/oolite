/*

OOMaterialSpecifier.m


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

#include "OOMaterialSpecifier.h"

#include "OOColor.h"
#include "OOTexture.h"
#include "Universe.h"
#include "oofnd/Defaults.hpp"

namespace {

// The value for key; null if there is none.
oo::PList ValueFor(const oo::PList& configuration, const char* key) {
  const oo::PList* value = configuration.find(key);
  return value != nullptr ? *value : oo::PList();
}

oo::Ref<OOColor> ColorFor(const oo::PList& configuration, const char* key) {
  return OOColor::colorWithDescription(ValueFor(configuration, key));
}

// cxx_OOTextureSpecFromObject() applied to the value for key, as
// -oo_textureSpecifierForKey:defaultName: did.
oo::PList TextureSpecifierFor(const oo::PList& configuration, const char* key,
                              const std::optional<std::string>& defaultName) {
  return cxx_OOTextureSpecFromObject(ValueFor(configuration, key), defaultName);
}

// PList dict with extract_channel set (nil stays nil).
oo::PList AddingExtractChannelA(oo::PList specifier) {
  if (oo::PList::Dict* dict = specifier.getIf<oo::PList::Dict>())
    (*dict)["extract_channel"] = oo::PList("a");
  return specifier;
}

// Internal. Used to avoid mutual recusion between the specular exponent map
// specifier and the specular exponent.
int RawSpecularExponentValue(const oo::PList& configuration) {
  const oo::PList* value =
      configuration.find(cxx_kOOMaterialSpecularExponentName);
  if (value == nullptr)
    value = configuration.find(cxx_kOOMaterialSpecularExponentLegacyName);
  return oo::PListGet<int>::from(value, -1);
}

}  // namespace

oo::Ref<OOColor> cxx_OOMaterialDiffuseColor(const oo::PList& configuration) {
  oo::Ref<OOColor> result =
      ColorFor(configuration, cxx_kOOMaterialDiffuseColorName);
  if (result == nullptr)
    result = ColorFor(configuration, cxx_kOOMaterialDiffuseColorLegacyName);

  if (result != nullptr && result->isWhite())
    result = nullptr;  // -isWhite of nil was NO
  return result;
}

oo::Ref<OOColor> cxx_OOMaterialAmbientColor(const oo::PList& configuration) {
  oo::Ref<OOColor> result =
      ColorFor(configuration, cxx_kOOMaterialAmbientColorName);
  if (result == nullptr)
    result = ColorFor(configuration, cxx_kOOMaterialAmbientColorLegacyName);
  return result;
}

oo::Ref<OOColor> cxx_OOMaterialSpecularColor(const oo::PList& configuration) {
  oo::Ref<OOColor> result =
      ColorFor(configuration, cxx_kOOMaterialSpecularColorName);
  if (result == nullptr)
    result = ColorFor(configuration, cxx_kOOMaterialSpecularColorLegacyName);
  if (result == nullptr) {
    result = OOColor::colorWithWhite(0.2f, 1.0f);
  }
  return result;
}

oo::Ref<OOColor> cxx_OOMaterialSpecularModulateColor(
    const oo::PList& configuration) {
  oo::Ref<OOColor> result =
      ColorFor(configuration, cxx_kOOMaterialSpecularModulateColorName);
  if (result == nullptr) result = OOColor::whiteColor();

  return result;
}

oo::Ref<OOColor> cxx_OOMaterialEmissionColor(const oo::PList& configuration) {
  oo::Ref<OOColor> result =
      ColorFor(configuration, cxx_kOOMaterialEmissionColorName);
  if (result == nullptr)
    result = ColorFor(configuration, cxx_kOOMaterialEmissionColorLegacyName);

  if (result != nullptr && result->isBlack())
    result = nullptr;  // -isBlack of nil was NO
  return result;
}

oo::Ref<OOColor> cxx_OOMaterialEmissionModulateColor(
    const oo::PList& configuration) {
  oo::Ref<OOColor> result =
      ColorFor(configuration, cxx_kOOMaterialEmissionModulateColorName);

  if (result != nullptr && result->isWhite())
    result = nullptr;  // -isWhite of nil was NO
  return result;
}

oo::Ref<OOColor> cxx_OOMaterialIlluminationModulateColor(
    const oo::PList& configuration) {
  oo::Ref<OOColor> result =
      ColorFor(configuration, cxx_kOOMaterialIlluminationModulateColorName);

  if (result != nullptr && result->isWhite())
    result = nullptr;  // -isWhite of nil was NO
  return result;
}

oo::PList cxx_OOMaterialDiffuseMapSpecifier(
    const oo::PList& configuration,
    const std::optional<std::string>& defaultName) {
  return TextureSpecifierFor(configuration, cxx_kOOMaterialDiffuseMapName,
                             defaultName);
}

oo::PList cxx_OOMaterialCombinedSpecularMapSpecifier(
    const oo::PList& configuration) {
  if (RawSpecularExponentValue(configuration) == 0) return oo::PList();
  return TextureSpecifierFor(
      configuration, cxx_kOOMaterialCombinedSpecularMapName, std::nullopt);
}

oo::PList cxx_OOMaterialSpecularColorMapSpecifier(
    const oo::PList& configuration) {
  if (RawSpecularExponentValue(configuration) == 0) return oo::PList();
  oo::PList result = TextureSpecifierFor(
      configuration, cxx_kOOMaterialSpecularColorMapName, std::nullopt);
  if (result.isNull())
    result = cxx_OOMaterialCombinedSpecularMapSpecifier(configuration);
  return result;
}

oo::PList cxx_OOMaterialSpecularExponentMapSpecifier(
    const oo::PList& configuration) {
  if (RawSpecularExponentValue(configuration) == 0) return oo::PList();
  oo::PList result = TextureSpecifierFor(
      configuration, cxx_kOOMaterialSpecularExponentMapName, std::nullopt);
  if (result.isNull())
    result = AddingExtractChannelA(
        cxx_OOMaterialCombinedSpecularMapSpecifier(configuration));
  return result;
}

oo::PList cxx_OOMaterialNormalMapSpecifier(const oo::PList& configuration) {
  if (!cxx_OOMaterialNormalAndParallaxMapSpecifier(configuration).isNull())
    return oo::PList();
  return TextureSpecifierFor(configuration, cxx_kOOMaterialNormalMapName,
                             std::nullopt);
}

oo::PList cxx_OOMaterialParallaxMapSpecifier(const oo::PList& configuration) {
  oo::PList spec = TextureSpecifierFor(
      configuration, cxx_kOOMaterialParallaxMapName, std::nullopt);
  if (spec.isNull()) {
    // Default is alpha channel of normal_and_parallax_map.
    spec = AddingExtractChannelA(
        cxx_OOMaterialNormalAndParallaxMapSpecifier(configuration));
  }

  return spec;
}

oo::PList cxx_OOMaterialNormalAndParallaxMapSpecifier(
    const oo::PList& configuration) {
  return TextureSpecifierFor(
      configuration, cxx_kOOMaterialNormalAndParallaxMapName, std::nullopt);
}

oo::PList cxx_OOMaterialEmissionMapSpecifier(const oo::PList& configuration) {
  return TextureSpecifierFor(configuration, cxx_kOOMaterialEmissionMapName,
                             std::nullopt);
}

oo::PList cxx_OOMaterialIlluminationMapSpecifier(
    const oo::PList& configuration) {
  return TextureSpecifierFor(configuration, cxx_kOOMaterialIlluminationMapName,
                             std::nullopt);
}

oo::PList cxx_OOMaterialEmissionAndIlluminationMapSpecifier(
    const oo::PList& configuration) {
  if (!cxx_OOMaterialEmissionMapSpecifier(configuration).isNull() ||
      !cxx_OOMaterialIlluminationMapSpecifier(configuration).isNull())
    return oo::PList();
  return TextureSpecifierFor(configuration,
                             cxx_kOOMaterialEmissionAndIlluminationMapName,
                             std::nullopt);
}

float cxx_OOMaterialParallaxScale(const oo::PList& configuration) {
  return configuration.get<float>(cxx_kOOMaterialParallaxScaleName,
                                  kOOMaterialDefaultParallaxScale);
}

float cxx_OOMaterialParallaxBias(const oo::PList& configuration) {
  return configuration.get<float>(cxx_kOOMaterialParallaxBiasName);
}

bool cxx_OOMaterialGammaCorrect(const oo::PList& configuration) {
  return configuration.get<bool>(
      cxx_kOOMaterialGammaCorrectName,
      !oo::Defaults::standard().boolForKey("no-gamma-correct"));
}

float cxx_OOMaterialGloss(const oo::PList& configuration) {
  return OOClamp_0_1_f(
      configuration.get<float>(cxx_kOOMaterialGlossName, 0.375f));
}

int cxx_OOMaterialSpecularExponent(const oo::PList& configuration) {
  int result = RawSpecularExponentValue(configuration);
  if (result < 0) {
    if ((UNIVERSE != nullptr ? UNIVERSE->useShaders() : false) &&
        !cxx_OOMaterialSpecularExponentMapSpecifier(configuration).isNull()) {
      result = 128;
    } else {
      result = 10;
    }
  }

  return result;
}
