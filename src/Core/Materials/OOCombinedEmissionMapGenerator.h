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

#import "OOTextureGenerator.h"

@class OOColor;

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

@interface OOCombinedEmissionMapGenerator : OOTextureGenerator {
@private
    std::string _cacheKey;

    oo::PList _emissionSpec;
    oo::PList _illuminationSpec;
    OOTexture* _diffuseMap;

    OOPixMap _emissionPx;
    OOPixMap _diffusePx;
    OOPixMap _illuminationPx;
    OOColor* _emissionColor;
    OOColor* _illuminationColor;
    BOOL _isCombinedMap;

    uint32_t _textureOptions;
    GLfloat _anisotropy;
    GLfloat _lodBias;

#ifndef NDEBUG
    std::string _emissionDesc;
    std::string _illuminationDesc;
    std::string _diffuseDesc;
#endif
}

- (id)cxx_initWithEmissionMapSpec:(const oo::PList&)emissionMapSpec
                    emissionColor:(OOColor*)emissionColor
                       diffuseMap:(OOTexture*)diffuseMap
                     diffuseColor:(OOColor*)diffuseColor
              illuminationMapSpec:(const oo::PList&)illuminationMapSpec
                illuminationColor:(OOColor*)illuminationColor
                 optionsSpecifier:(const oo::PList&)spec OO_RETURNS_RETAINED;

- (id)cxx_initWithEmissionAndIlluminationMapSpec:(const oo::PList&)emissionAndIlluminationMapSpec
                                      diffuseMap:(OOTexture*)diffuseMap
                                    diffuseColor:(OOColor*)diffuseColor
                                   emissionColor:(OOColor*)emissionColor
                               illuminationColor:(OOColor*)illuminationColor
                                optionsSpecifier:(const oo::PList&)spec OO_RETURNS_RETAINED;

@end
