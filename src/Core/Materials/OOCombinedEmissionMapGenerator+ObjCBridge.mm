/*

OOCombinedEmissionMapGenerator+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056): the Objective-C OOCombinedEmissionMapGenerator facade over
cxx::OOCombinedEmissionMapGenerator. Every method forwards in one line. Deleted, with
OOCombinedEmissionMapGenerator+ObjCBridge.h, by the bridge's deletion bead.


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

#import "OOCombinedEmissionMapGenerator.h"

@implementation OOCombinedEmissionMapGenerator

/*	The initialisers make the C++ generator and answer its facade (amendment oo-qa7c): the receiver
        alloc made is released, and nil answered where the C++ factory answers null.
*/
- (id)cxx_initWithEmissionMapSpec:(const oo::PList&)emissionMapSpec
                    emissionColor:(OOColor*)emissionColor
                       diffuseMap:(OOTexture*)diffuseMap
                     diffuseColor:(OOColor*)diffuseColor
              illuminationMapSpec:(const oo::PList&)illuminationMapSpec
                illuminationColor:(OOColor*)illuminationColor
                 optionsSpecifier:(const oo::PList&)spec
{
    oo::Ref<cxx::OOCombinedEmissionMapGenerator> generator = cxx::OOCombinedEmissionMapGenerator::generatorWithEmissionMapSpec(emissionMapSpec, oo::ToCxx(emissionColor), diffuseMap, oo::ToCxx(diffuseColor), illuminationMapSpec, oo::ToCxx(illuminationColor), spec);
    [self release];
    return [oo::ToObjC(generator.get()) retain];
}

- (id)cxx_initWithEmissionAndIlluminationMapSpec:(const oo::PList&)emissionAndIlluminationMapSpec
                                      diffuseMap:(OOTexture*)diffuseMap
                                    diffuseColor:(OOColor*)diffuseColor
                                   emissionColor:(OOColor*)emissionColor
                               illuminationColor:(OOColor*)illuminationColor
                                optionsSpecifier:(const oo::PList&)spec
{
    oo::Ref<cxx::OOCombinedEmissionMapGenerator> generator = cxx::OOCombinedEmissionMapGenerator::generatorWithEmissionAndIlluminationMapSpec(emissionAndIlluminationMapSpec, diffuseMap, oo::ToCxx(diffuseColor), oo::ToCxx(emissionColor), oo::ToCxx(illuminationColor), spec);
    [self release];
    return [oo::ToObjC(generator.get()) retain];
}

@end

// A C++ emission map generator's facade is an OOCombinedEmissionMapGenerator: the root's
// oo::ToObjC picks the Objective-C class named as the C++ class is (amendment oo-up4b item 3).
OOCombinedEmissionMapGenerator* oo::ToObjC(cxx::OOCombinedEmissionMapGenerator* generator)
{
    return static_cast<OOCombinedEmissionMapGenerator*>(oo::ToObjC(static_cast<cxx::OOTextureLoader*>(generator)));
}

cxx::OOCombinedEmissionMapGenerator* oo::ToCxx(OOCombinedEmissionMapGenerator* generator)
{
    return static_cast<cxx::OOCombinedEmissionMapGenerator*>(oo::ToCxx(static_cast<OOTextureLoader*>(generator)));
}
