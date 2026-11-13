/*

OOMaterialSpecifier.h

Key declarations and convenience methods for material specifiers.


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

#include "OOColor.h"  // the colour readers answer std::shared_ptr<OOColor>
#include "OOFoundation.h"
#include "oofnd/PList.hpp"

/*	Material configuration properties. A material configuration is an
   oo::PList dictionary: property-list data plus PList::Object nodes for the
   live objects callers put in it (colours, textures); a null PList is a nil
   configuration, and every function then answers as a message to nil did.
   Specifiers are oo::PList dictionaries (null = nil).
*/
std::shared_ptr<OOColor> OOMaterialDiffuseColor(const oo::PList& configuration);
std::shared_ptr<OOColor> OOMaterialAmbientColor(const oo::PList& configuration);
std::shared_ptr<OOColor> OOMaterialSpecularColor(
    const oo::PList& configuration);
std::shared_ptr<OOColor> OOMaterialSpecularModulateColor(
    const oo::PList& configuration);
std::shared_ptr<OOColor> OOMaterialEmissionColor(
    const oo::PList& configuration);
std::shared_ptr<OOColor> OOMaterialEmissionModulateColor(
    const oo::PList& configuration);
std::shared_ptr<OOColor> OOMaterialIlluminationModulateColor(
    const oo::PList& configuration);

oo::PList OOMaterialDiffuseMapSpecifier(
    const oo::PList& configuration,
    const std::optional<std::string>& defaultName);
oo::PList OOMaterialCombinedSpecularMapSpecifier(
    const oo::PList& configuration);
oo::PList OOMaterialSpecularColorMapSpecifier(const oo::PList& configuration);
oo::PList OOMaterialSpecularExponentMapSpecifier(
    const oo::PList& configuration);
oo::PList OOMaterialNormalMapSpecifier(const oo::PList& configuration);
oo::PList OOMaterialParallaxMapSpecifier(const oo::PList& configuration);
oo::PList OOMaterialNormalAndParallaxMapSpecifier(
    const oo::PList& configuration);
oo::PList OOMaterialEmissionMapSpecifier(const oo::PList& configuration);
oo::PList OOMaterialIlluminationMapSpecifier(const oo::PList& configuration);
oo::PList OOMaterialEmissionAndIlluminationMapSpecifier(
    const oo::PList& configuration);

float OOMaterialParallaxScale(const oo::PList& configuration);
float OOMaterialParallaxBias(const oo::PList& configuration);
bool OOMaterialGammaCorrect(const oo::PList& configuration);
float OOMaterialGloss(const oo::PList& configuration);
int OOMaterialSpecularExponent(const oo::PList& configuration);

// Configuration keys.
inline constexpr const char* kOOMaterialDiffuseColorName = "diffuse_color";
inline constexpr const char* kOOMaterialDiffuseColorLegacyName = "diffuse";
inline constexpr const char* kOOMaterialAmbientColorName = "ambient_color";
inline constexpr const char* kOOMaterialAmbientColorLegacyName = "ambient";
inline constexpr const char* kOOMaterialSpecularColorName = "specular_color";
inline constexpr const char* kOOMaterialSpecularColorLegacyName = "specular";
inline constexpr const char* kOOMaterialSpecularModulateColorName =
    "specular_modulate_color";
inline constexpr const char* kOOMaterialEmissionColorName = "emission_color";
inline constexpr const char* kOOMaterialEmissionColorLegacyName = "emission";
inline constexpr const char* kOOMaterialEmissionModulateColorName =
    "emission_modulate_color";
inline constexpr const char* kOOMaterialIlluminationModulateColorName =
    "illumination_modulate_color";
inline constexpr const char* kOOMaterialDiffuseMapName = "diffuse_map";
inline constexpr const char* kOOMaterialSpecularColorMapName =
    "specular_color_map";
inline constexpr const char* kOOMaterialSpecularExponentMapName =
    "specular_exponent_map";
inline constexpr const char* kOOMaterialCombinedSpecularMapName =
    "specular_map";  // Combined specular_color_map and specular_exponent_map
                     // (unfortunate name required for backwards-compatibility).
inline constexpr const char* kOOMaterialNormalMapName = "normal_map";
inline constexpr const char* kOOMaterialParallaxMapName = "parallax_map";
inline constexpr const char* kOOMaterialNormalAndParallaxMapName =
    "normal_and_parallax_map";
inline constexpr const char* kOOMaterialEmissionMapName = "emission_map";
inline constexpr const char* kOOMaterialIlluminationMapName =
    "illumination_map";
inline constexpr const char* kOOMaterialEmissionAndIlluminationMapName =
    "emission_and_illumination_map";
inline constexpr const char* kOOMaterialParallaxScaleName = "parallax_scale";
inline constexpr const char* kOOMaterialParallaxBiasName = "parallax_bias";
inline constexpr const char* kOOMaterialGammaCorrectName = "gamma_correct";
inline constexpr const char* kOOMaterialGlossName = "gloss";
inline constexpr const char* kOOMaterialSpecularExponentName =
    "specular_exponent";
inline constexpr const char* kOOMaterialSpecularExponentLegacyName =
    "shininess";
inline constexpr const char* kOOMaterialLightMapsName = "light_map";

#define kOOMaterialDefaultParallaxScale (0.01f)
