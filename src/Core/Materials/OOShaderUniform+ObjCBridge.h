/*

OOShaderUniform+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056): the Objective-C OOShaderUniform, a facade over the C++
cxx::OOShaderUniform (OOShaderUniform.h), for the callers that make and message uniforms
(OOShaderMaterial, DustEntity). Its interface is the one OOShaderUniform.h declared before the
conversion, copied exactly (same selectors, same types), with one ivar, the C++ uniform. Imported as
the last line of OOShaderUniform.h; do not import it directly.

oo::ToObjC(oo::ToCxx(u)) == u (oo::ObjCPeers). Never add to this file; converted code does not
message the facade. Deleted by its deletion bead once every caller is C++.


Copyright (C) 2007-2013 Jens Ayton

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

#ifndef OOSHADERUNIFORM_OBJCBRIDGE_H
#define OOSHADERUNIFORM_OBJCBRIDGE_H

@interface OOShaderUniform : OOObject {
@private
    oo::Ref<cxx::OOShaderUniform> _cxxUniform;
}

- (id)initWithName:(const std::string&)uniformName shaderProgram:(OOShaderProgram*)shaderProgram intValue:(GLint)constValue;
- (id)initWithName:(const std::string&)uniformName shaderProgram:(OOShaderProgram*)shaderProgram floatValue:(GLfloat)constValue;
- (id)initWithName:(const std::string&)uniformName shaderProgram:(OOShaderProgram*)shaderProgram vectorValue:(GLfloat[4])constValue;
- (id)initWithName:(const std::string&)uniformName shaderProgram:(OOShaderProgram*)shaderProgram colorValue:(OOColor*)constValue; // Converted to vector
- (id)initWithName:(const std::string&)uniformName shaderProgram:(OOShaderProgram*)shaderProgram quaternionValue:(Quaternion)constValue asMatrix:(BOOL)asMatrix; // Converted to vector (in xyzw order, not wxyz!) or rotation matrix.
- (id)initWithName:(const std::string&)uniformName shaderProgram:(OOShaderProgram*)shaderProgram matrixValue:(OOMatrix)constValue;

/*	"Convert" has different meanings for different types.
        For float and int types, it clamps to the range [0, 1].
        For vector types, it normalizes.
        For quaternions, it converts to rotation matrix (instead of vec4).
*/
- (id)initWithName:(const std::string&)uniformName
     shaderProgram:(OOShaderProgram*)shaderProgram
     boundToObject:(id<OOWeakReferenceSupport>)target
          property:(SEL)selector
    convertOptions:(OOUniformConvertOptions)options;

- (void)apply;

- (void)setBindingTarget:(id<OOWeakReferenceSupport>)target;

@end

namespace oo {

// The uniform's live facade, or a new one; autoreleased. nil for null.
OOShaderUniform* ToObjC(cxx::OOShaderUniform* uniform);
inline OOShaderUniform* ToObjC(const Ref<cxx::OOShaderUniform>& uniform) { return ToObjC(uniform.get()); }

// The C++ uniform behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOShaderUniform* ToCxx(OOShaderUniform* uniform);

} // namespace oo

#endif // OOSHADERUNIFORM_OBJCBRIDGE_H
