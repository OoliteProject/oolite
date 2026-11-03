/*

OOCombinedEmissionMapGenerator+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-qa7c, oo-rmd7 item 3 and oo-e6xa): the Objective-C
OOCombinedEmissionMapGenerator, the facade of the C++ cxx::OOCombinedEmissionMapGenerator
(OOCombinedEmissionMapGenerator.h), a subclass of the OOTextureGenerator facade with no ivars. Its
interface is the one OOCombinedEmissionMapGenerator.h declared before the conversion, copied
exactly, for its caller (OOMultiTextureMaterial), whose test stubs the class by name.
Imported as the last line of OOCombinedEmissionMapGenerator.h; do not import it directly.
Deleted by its deletion bead, which turns the caller's messages into the C++ factories.


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

#ifndef OOCOMBINEDEMISSIONMAPGENERATOR_OBJCBRIDGE_H
#define OOCOMBINEDEMISSIONMAPGENERATOR_OBJCBRIDGE_H

@interface OOCombinedEmissionMapGenerator : OOTextureGenerator

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

namespace oo {

// The generator's facade, autoreleased; nil for null.
OOCombinedEmissionMapGenerator* ToObjC(cxx::OOCombinedEmissionMapGenerator* generator);

// The C++ generator behind the facade, borrowed; null for nil.
cxx::OOCombinedEmissionMapGenerator* ToCxx(OOCombinedEmissionMapGenerator* generator);

} // namespace oo

#endif // OOCOMBINEDEMISSIONMAPGENERATOR_OBJCBRIDGE_H
