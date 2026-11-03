/*

OODefaultShaderSynthesizer+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-bm1q): the Objective-C OODefaultShaderSynthesizer, a facade
over the C++ cxx::OODefaultShaderSynthesizer (OODefaultShaderSynthesizer.h), for the code that is not
converted yet: the shader stages of slice 2 of OODefaultShaderSynthesizer.mm
(docs/phases/3-slices/OODefaultShaderSynthesizer.md), which are methods of the Stages category below
and call back into the declaration helpers and texture bookkeeping through this interface. The
class was private to OODefaultShaderSynthesizer.mm; its interface is the one the .mm declared,
copied exactly (same selectors, same types), except that the stages are declared in the category
that implements them and -assignIDForTexture:, which the stages sent undeclared, is declared in
the OOPrivate category. Each method of the class forwards to its C++ member. Imported as the last
line of OODefaultShaderSynthesizer.h; do not import it directly.

        a caller that is                       holds / passes                       crosses with
        -------------------------------------  -----------------------------------  ------------------------
        still Objective-C (a shader stage)     OODefaultShaderSynthesizer * (self)    oo::ToCxx(self) for the state
        converted (C++)                        oo::Ref<cxx::OODefaultShaderSynthesizer>
          running a stage                                                           oo::ToObjC(this)

Never add to this file; converted code does not message the facade except to run a stage. Deleted
by its deletion bead once the stages are C++ (slice 2).

Copyright © 2011-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the “Software”), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#ifndef OODEFAULTSHADERSYNTHESIZER_OBJCBRIDGE_H
#define OODEFAULTSHADERSYNTHESIZER_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@interface OODefaultShaderSynthesizer : OOObject {
@private
    oo::Ref<cxx::OODefaultShaderSynthesizer> _cxxSynthesizer;
}

- (id)initWithMaterialConfiguration:(const oo::PList&)configuration
                        materialKey:(const std::optional<std::string>&)materialKey
                         entityName:(const std::optional<std::string>&)name;

- (BOOL)run;

- (std::string)vertexShader;
- (std::string)fragmentShader;
- (oo::PList)textureSpecifications; // an array
- (oo::PList)uniformSpecifications; // a dictionary

- (std::optional<std::string>)materialKey;
- (std::optional<std::string>)entityName;

- (void)composeVertexShader;
- (void)composeFragmentShader;

// Write various types of declarations.
- (void)appendVariable:(const std::string&)name ofType:(const std::string&)type withPrefix:(const std::string&)prefix to:(std::string&)buffer;
- (void)addAttribute:(const std::string&)name ofType:(const std::string&)type;
- (void)addVarying:(const std::string&)name ofType:(const std::string&)type;
- (void)addVertexUniform:(const std::string&)name ofType:(const std::string&)type;
- (void)addFragmentUniform:(const std::string&)name ofType:(const std::string&)type;

// Create or retrieve a uniform variable name for a given binding.
- (std::optional<std::string>)defineBindingUniform:(const oo::PList&)binding ofType:(const std::string&)type;

- (std::optional<std::string>)readRGBForTextureSpec:(const oo::PList&)textureSpec mapName:(const std::string&)mapName; // Generate a read for an RGB value, or a single channel splatted across RGB.
- (std::optional<std::string>)readOneChannelForTextureSpec:(const oo::PList&)textureSpec mapName:(const std::string&)mapName; // Generate a read for a single channel.

// Details of texture setup; generally use -read*ForTextureSpec:mapName: instead.
- (NSUInteger)textureIDForSpec:(const oo::PList&)textureSpec;
- (void)setUpOneTexture:(const oo::PList&)textureSpec;
- (void)getSampleName:(std::string*)outSampleName andSwizzleOp:(std::string*)outSwizzleOp forTextureSpec:(const oo::PList&)textureSpec; // swizzle "" = none

#ifndef NDEBUG
- (void)performStage:(SEL)stage;
#endif

@end

// Sent by the stages, which the .mm declared nowhere (it was defined above them).
@interface OODefaultShaderSynthesizer (OOPrivate)

- (NSUInteger)assignIDForTexture:(const oo::PList&)textureSpec;

@end

/*	Stages, implemented in OODefaultShaderSynthesizer.mm (slice 2, still Objective-C). These should
        only be called through the REQUIRE_STAGE macro to avoid duplicated code and ensure data
        depedencies are met. Their comments are in the .mm.
*/
@interface OODefaultShaderSynthesizer (Stages)

- (void)createTemporaries;
- (void)destroyTemporaries;

- (void)writeTextureCoordRead;
- (void)writeDiffuseColorTermIfNeeded;
- (void)writeDiffuseColorTerm;
- (void)writeDiffuseLighting;
- (void)writeLightVector;
- (void)writeEyeVector;
- (void)writeVertexTangentBasis;
- (void)writeNormalIfNeeded;
- (void)writeNormal;
- (void)writeSpecularLighting;
- (void)writeLightMaps;
- (void)writeVertexPosition;
- (void)writeTotalColor;
- (void)writeFinalColorComposite;

@end

namespace oo {

// The synthesizer's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OODefaultShaderSynthesizer* ToObjC(cxx::OODefaultShaderSynthesizer* synthesizer);
inline OODefaultShaderSynthesizer* ToObjC(const Ref<cxx::OODefaultShaderSynthesizer>& synthesizer) { return ToObjC(synthesizer.get()); }
// The C++ synthesizer behind a facade, borrowed (the facade retains it); null for nil.
cxx::OODefaultShaderSynthesizer* ToCxx(OODefaultShaderSynthesizer* synthesizer);

} // namespace oo

#endif // OODEFAULTSHADERSYNTHESIZER_OBJCBRIDGE_H
