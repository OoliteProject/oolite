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

#include <string_view>

#include "OOColor.h"
#include "OOTexture.h"
#include "Universe.h"
#include "oofnd/Defaults.hpp"

namespace {

// The value for key; null if there is none.
oo::PList ValueFor(const oo::PList& configuration, std::string_view key) {
  const oo::PList* value = configuration.find(key);
  return value != nullptr ? *value : oo::PList();
}

std::shared_ptr<OOColor> ColorFor(const oo::PList& configuration,
                                  std::string_view key) {
  return OOColor::colorWithDescription(ValueFor(configuration, key));
}

// OOTextureSpecFromObject() applied to the value for key, as
// -oo_textureSpecifierForKey:defaultName: did.
oo::PList TextureSpecifierFor(const oo::PList& configuration,
                              std::string_view key,
                              const std::optional<std::string>& defaultName) {
  return OOTextureSpecFromObject(ValueFor(configuration, key), defaultName);
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
  const oo::PList* value = configuration.find(kOOMaterialSpecularExponentName);
  if (value == nullptr)
    value = configuration.find(kOOMaterialSpecularExponentLegacyName);
  return oo::PListGet<int>::from(value, -1);
}

}  // namespace

std::shared_ptr<OOColor> OOMaterialDiffuseColor(
    const oo::PList& configuration) {
  std::shared_ptr<OOColor> result =
      ColorFor(configuration, kOOMaterialDiffuseColorName);
  if (result == nullptr)
    result = ColorFor(configuration, kOOMaterialDiffuseColorLegacyName);

  if (result != nullptr && result->isWhite())
    result = nullptr;  // -isWhite of nil was NO
  return result;
}

std::shared_ptr<OOColor> OOMaterialAmbientColor(
    const oo::PList& configuration) {
  std::shared_ptr<OOColor> result =
      ColorFor(configuration, kOOMaterialAmbientColorName);
  if (result == nullptr)
    result = ColorFor(configuration, kOOMaterialAmbientColorLegacyName);
  return result;
}

std::shared_ptr<OOColor> OOMaterialSpecularColor(
    const oo::PList& configuration) {
  std::shared_ptr<OOColor> result =
      ColorFor(configuration, kOOMaterialSpecularColorName);
  if (result == nullptr)
    result = ColorFor(configuration, kOOMaterialSpecularColorLegacyName);
  if (result == nullptr) {
    result = OOColor::colorWithWhite(0.2f, 1.0f);
  }
  return result;
}

std::shared_ptr<OOColor> OOMaterialSpecularModulateColor(
    const oo::PList& configuration) {
  std::shared_ptr<OOColor> result =
      ColorFor(configuration, kOOMaterialSpecularModulateColorName);
  if (result == nullptr) result = OOColor::whiteColor();

  return result;
}

std::shared_ptr<OOColor> OOMaterialEmissionColor(
    const oo::PList& configuration) {
  std::shared_ptr<OOColor> result =
      ColorFor(configuration, kOOMaterialEmissionColorName);
  if (result == nullptr)
    result = ColorFor(configuration, kOOMaterialEmissionColorLegacyName);

  if (result != nullptr && result->isBlack())
    result = nullptr;  // -isBlack of nil was NO
  return result;
}

std::shared_ptr<OOColor> OOMaterialEmissionModulateColor(
    const oo::PList& configuration) {
  std::shared_ptr<OOColor> result =
      ColorFor(configuration, kOOMaterialEmissionModulateColorName);

  if (result != nullptr && result->isWhite())
    result = nullptr;  // -isWhite of nil was NO
  return result;
}

std::shared_ptr<OOColor> OOMaterialIlluminationModulateColor(
    const oo::PList& configuration) {
  std::shared_ptr<OOColor> result =
      ColorFor(configuration, kOOMaterialIlluminationModulateColorName);

  if (result != nullptr && result->isWhite())
    result = nullptr;  // -isWhite of nil was NO
  return result;
}

oo::PList OOMaterialDiffuseMapSpecifier(
    const oo::PList& configuration,
    const std::optional<std::string>& defaultName) {
  return TextureSpecifierFor(configuration, kOOMaterialDiffuseMapName,
                             defaultName);
}

oo::PList OOMaterialCombinedSpecularMapSpecifier(
    const oo::PList& configuration) {
  if (RawSpecularExponentValue(configuration) == 0) return oo::PList();
  return TextureSpecifierFor(configuration, kOOMaterialCombinedSpecularMapName,
                             std::nullopt);
}

oo::PList OOMaterialSpecularColorMapSpecifier(const oo::PList& configuration) {
  if (RawSpecularExponentValue(configuration) == 0) return oo::PList();
  oo::PList result = TextureSpecifierFor(
      configuration, kOOMaterialSpecularColorMapName, std::nullopt);
  if (result.isNull())
    result = OOMaterialCombinedSpecularMapSpecifier(configuration);
  return result;
}

oo::PList OOMaterialSpecularExponentMapSpecifier(
    const oo::PList& configuration) {
  if (RawSpecularExponentValue(configuration) == 0) return oo::PList();
  oo::PList result = TextureSpecifierFor(
      configuration, kOOMaterialSpecularExponentMapName, std::nullopt);
  if (result.isNull())
    result = AddingExtractChannelA(
        OOMaterialCombinedSpecularMapSpecifier(configuration));
  return result;
}

oo::PList OOMaterialNormalMapSpecifier(const oo::PList& configuration) {
  if (!OOMaterialNormalAndParallaxMapSpecifier(configuration).isNull())
    return oo::PList();
  return TextureSpecifierFor(configuration, kOOMaterialNormalMapName,
                             std::nullopt);
}

oo::PList OOMaterialParallaxMapSpecifier(const oo::PList& configuration) {
  oo::PList spec = TextureSpecifierFor(
      configuration, kOOMaterialParallaxMapName, std::nullopt);
  if (spec.isNull()) {
    // Default is alpha channel of normal_and_parallax_map.
    spec = AddingExtractChannelA(
        OOMaterialNormalAndParallaxMapSpecifier(configuration));
  }

  return spec;
}

oo::PList OOMaterialNormalAndParallaxMapSpecifier(
    const oo::PList& configuration) {
  return TextureSpecifierFor(configuration, kOOMaterialNormalAndParallaxMapName,
                             std::nullopt);
}

oo::PList OOMaterialEmissionMapSpecifier(const oo::PList& configuration) {
  return TextureSpecifierFor(configuration, kOOMaterialEmissionMapName,
                             std::nullopt);
}

oo::PList OOMaterialIlluminationMapSpecifier(const oo::PList& configuration) {
  return TextureSpecifierFor(configuration, kOOMaterialIlluminationMapName,
                             std::nullopt);
}

oo::PList OOMaterialEmissionAndIlluminationMapSpecifier(
    const oo::PList& configuration) {
  if (!OOMaterialEmissionMapSpecifier(configuration).isNull() ||
      !OOMaterialIlluminationMapSpecifier(configuration).isNull())
    return oo::PList();
  return TextureSpecifierFor(
      configuration, kOOMaterialEmissionAndIlluminationMapName, std::nullopt);
}

float OOMaterialParallaxScale(const oo::PList& configuration) {
  return configuration.get<float>(kOOMaterialParallaxScaleName,
                                  kOOMaterialDefaultParallaxScale);
}

float OOMaterialParallaxBias(const oo::PList& configuration) {
  return configuration.get<float>(kOOMaterialParallaxBiasName);
}

bool OOMaterialGammaCorrect(const oo::PList& configuration) {
  return configuration.get<bool>(
      kOOMaterialGammaCorrectName,
      !oo::Defaults::standard().boolForKey("no-gamma-correct"));
}

float OOMaterialGloss(const oo::PList& configuration) {
  return OOClamp_0_1_f(configuration.get<float>(kOOMaterialGlossName, 0.375f));
}

int OOMaterialSpecularExponent(const oo::PList& configuration) {
  int result = RawSpecularExponentValue(configuration);
  if (result < 0) {
    if ((UNIVERSE != nullptr ? UNIVERSE->useShaders() : false) &&
        !OOMaterialSpecularExponentMapSpecifier(configuration).isNull()) {
      result = 128;
    } else {
      result = 10;
    }
  }

  return result;
}
