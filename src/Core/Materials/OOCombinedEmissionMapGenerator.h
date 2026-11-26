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

#ifndef OOCOMBINEDEMISSIONMAPGENERATOR_H
#define OOCOMBINEDEMISSIONMAPGENERATOR_H

#include "OOColor.h"
#include "OOTextureGenerator.h"

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

/*	Phase 3 (bead oo-e6xa, proposed ADR-0056 amendments oo-qa7c, oo-rmd7 item 3 and oo-rr2x): a
        converted leaf of the texture generators, over OOTextureGenerator. Bead oo-9ht.135
        deleted its Objective-C facade: its caller (OOMultiTextureMaterial) makes it with the factories
        below, and hands the C++ generator to the texture (the generators' facade it was seen as went
        with bead oo-9ht.118).
*/
class OOCombinedEmissionMapGenerator : public OOTextureGenerator {
public:
    ~OOCombinedEmissionMapGenerator() override; // was -dealloc

    /*	Were -cxx_initWithEmissionMapSpec:emissionColor:diffuseMap:diffuseColor:illuminationMapSpec:
            illuminationColor:optionsSpecifier: and -cxx_initWithEmissionAndIlluminationMapSpec:
            diffuseMap:diffuseColor:emissionColor:illuminationColor:optionsSpecifier:; null where they
            answered nil (amendment oo-novu).
    */
    static oo::Ref<OOCombinedEmissionMapGenerator> generatorWithEmissionMapSpec(const oo::PList& emissionMapSpec,
        OOColor* emissionColor,
        OOTexture* diffuseMap,
        OOColor* diffuseColor,
        const oo::PList& illuminationMapSpec,
        OOColor* illuminationColor,
        const oo::PList& spec);
    static oo::Ref<OOCombinedEmissionMapGenerator> generatorWithEmissionAndIlluminationMapSpec(const oo::PList& emissionAndIlluminationMapSpec,
        OOTexture* diffuseMap,
        OOColor* diffuseColor,
        OOColor* emissionColor,
        OOColor* illuminationColor,
        const oo::PList& spec);

#ifndef NDEBUG
    std::optional<std::string> descriptionComponents() const override;
#endif

    uint32_t textureOptions() override;
    GLfloat anisotropy() override;
    GLfloat lodBias() override;
    std::optional<std::string> cacheKey() override;

    void loadTexture() override;

private:
    bool initWithEmissionMapSpec(const oo::PList& emissionMapSpec,
        OOColor* emissionColor,
        OOTexture* diffuseMap,
        OOColor* diffuseColor,
        const oo::PList& illuminationMapSpec,
        OOColor* illuminationColor,
        bool isCombinedMap,
        const oo::PList& spec);

    std::string constructCacheKey();

    std::string _cacheKey;

    oo::PList _emissionSpec;
    oo::PList _illuminationSpec;
    oo::Ref<OOTexture> _diffuseMap;

    OOPixMap _emissionPx = { };
    OOPixMap _diffusePx = { };
    OOPixMap _illuminationPx = { };
    oo::Ref<OOColor> _emissionColor;
    oo::Ref<OOColor> _illuminationColor;
    bool _isCombinedMap = false;

    uint32_t _textureOptions = 0;
    GLfloat _anisotropy = 0;
    GLfloat _lodBias = 0;

#ifndef NDEBUG
    std::string _emissionDesc;
    std::string _illuminationDesc;
    std::string _diffuseDesc;
#endif
};

#endif // OOCOMBINEDEMISSIONMAPGENERATOR_H
