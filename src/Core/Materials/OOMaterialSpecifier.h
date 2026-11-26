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

#include "OOFoundation.h"

#include "oofnd/PList.hpp"

#include "OOColor.h" // the colour readers answer oo::Ref<OOColor>

/*	Material configuration properties (Foundation sweep, proposed ADR-0043 Amendment 2, bead
        oo-hiis). A material configuration is an oo::PList dictionary: property-list data plus
        PList::Object nodes for the live objects callers put in it (colours, textures); a null PList is
        a nil configuration, and every function then answers as a message to nil did. Specifiers are
        oo::PList dictionaries (null = nil). The Foundation dictionary category these replace, and the
        Foundation-string key constants, live on in a transitional bridge (now removed) until their callers move.
*/
oo::Ref<OOColor> cxx_OOMaterialDiffuseColor(const oo::PList& configuration);
oo::Ref<OOColor> cxx_OOMaterialAmbientColor(const oo::PList& configuration);
oo::Ref<OOColor> cxx_OOMaterialSpecularColor(const oo::PList& configuration);
oo::Ref<OOColor> cxx_OOMaterialSpecularModulateColor(const oo::PList& configuration);
oo::Ref<OOColor> cxx_OOMaterialEmissionColor(const oo::PList& configuration);
oo::Ref<OOColor> cxx_OOMaterialEmissionModulateColor(const oo::PList& configuration);
oo::Ref<OOColor> cxx_OOMaterialIlluminationModulateColor(const oo::PList& configuration);

oo::PList cxx_OOMaterialDiffuseMapSpecifier(const oo::PList& configuration, const std::optional<std::string>& defaultName);
oo::PList cxx_OOMaterialCombinedSpecularMapSpecifier(const oo::PList& configuration);
oo::PList cxx_OOMaterialSpecularColorMapSpecifier(const oo::PList& configuration);
oo::PList cxx_OOMaterialSpecularExponentMapSpecifier(const oo::PList& configuration);
oo::PList cxx_OOMaterialNormalMapSpecifier(const oo::PList& configuration);
oo::PList cxx_OOMaterialParallaxMapSpecifier(const oo::PList& configuration);
oo::PList cxx_OOMaterialNormalAndParallaxMapSpecifier(const oo::PList& configuration);
oo::PList cxx_OOMaterialEmissionMapSpecifier(const oo::PList& configuration);
oo::PList cxx_OOMaterialIlluminationMapSpecifier(const oo::PList& configuration);
oo::PList cxx_OOMaterialEmissionAndIlluminationMapSpecifier(const oo::PList& configuration);

float cxx_OOMaterialParallaxScale(const oo::PList& configuration);
float cxx_OOMaterialParallaxBias(const oo::PList& configuration);
bool cxx_OOMaterialGammaCorrect(const oo::PList& configuration);
float cxx_OOMaterialGloss(const oo::PList& configuration);
int cxx_OOMaterialSpecularExponent(const oo::PList& configuration);

// Configuration keys.
inline constexpr const char* cxx_kOOMaterialDiffuseColorName = "diffuse_color";
inline constexpr const char* cxx_kOOMaterialDiffuseColorLegacyName = "diffuse";
inline constexpr const char* cxx_kOOMaterialAmbientColorName = "ambient_color";
inline constexpr const char* cxx_kOOMaterialAmbientColorLegacyName = "ambient";
inline constexpr const char* cxx_kOOMaterialSpecularColorName = "specular_color";
inline constexpr const char* cxx_kOOMaterialSpecularColorLegacyName = "specular";
inline constexpr const char* cxx_kOOMaterialSpecularModulateColorName = "specular_modulate_color";
inline constexpr const char* cxx_kOOMaterialEmissionColorName = "emission_color";
inline constexpr const char* cxx_kOOMaterialEmissionColorLegacyName = "emission";
inline constexpr const char* cxx_kOOMaterialEmissionModulateColorName = "emission_modulate_color";
inline constexpr const char* cxx_kOOMaterialIlluminationModulateColorName = "illumination_modulate_color";
inline constexpr const char* cxx_kOOMaterialDiffuseMapName = "diffuse_map";
inline constexpr const char* cxx_kOOMaterialSpecularColorMapName = "specular_color_map";
inline constexpr const char* cxx_kOOMaterialSpecularExponentMapName = "specular_exponent_map";
inline constexpr const char* cxx_kOOMaterialCombinedSpecularMapName = "specular_map"; // Combined specular_color_map and specular_exponent_map (unfortunate name required for backwards-compatibility).
inline constexpr const char* cxx_kOOMaterialNormalMapName = "normal_map";
inline constexpr const char* cxx_kOOMaterialParallaxMapName = "parallax_map";
inline constexpr const char* cxx_kOOMaterialNormalAndParallaxMapName = "normal_and_parallax_map";
inline constexpr const char* cxx_kOOMaterialEmissionMapName = "emission_map";
inline constexpr const char* cxx_kOOMaterialIlluminationMapName = "illumination_map";
inline constexpr const char* cxx_kOOMaterialEmissionAndIlluminationMapName = "emission_and_illumination_map";
inline constexpr const char* cxx_kOOMaterialParallaxScaleName = "parallax_scale";
inline constexpr const char* cxx_kOOMaterialParallaxBiasName = "parallax_bias";
inline constexpr const char* cxx_kOOMaterialGammaCorrectName = "gamma_correct";
inline constexpr const char* cxx_kOOMaterialGlossName = "gloss";
inline constexpr const char* cxx_kOOMaterialSpecularExponentName = "specular_exponent";
inline constexpr const char* cxx_kOOMaterialSpecularExponentLegacyName = "shininess";
inline constexpr const char* cxx_kOOMaterialLightMapsName = "light_map";

#define kOOMaterialDefaultParallaxScale (0.01f)
