/*

OOShaderProgram.h

Encapsulates a vertex + fragment shader combo. In general, this should only be
used though OOShaderMaterial. The point of this separation is that more than
one OOShaderMaterial can use the same OOShaderProgram.


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

#import "OOOpenGL.h"
#import "OOOpenGLExtensionManager.h"
#import "oofnd/objc/OOObject.h"
#import <Foundation/Foundation.h>

#if OO_SHADERS

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

/*	Foundation sweep (proposed ADR-0043, bead oo-vqvw): shader sources, names, prefix and cache key
        are nil-able strings (std::optional: a missing source means no shader of that kind, an empty
        prefix counts as none). Attribute bindings are a property-list dictionary of attribute name ->
        location (oo::PList, null for none).
*/
@interface OOShaderProgram : OOObject {
@private
    GLhandleARB program;
    std::optional<std::string> key;
    oo::PList standardMatrixUniformLocations;
}

+ (id)shaderProgramWithVertexShader:(const std::optional<std::string>&)vertexShaderSource
                     fragmentShader:(const std::optional<std::string>&)fragmentShaderSource
                   vertexShaderName:(const std::optional<std::string>&)vertexShaderName
                 fragmentShaderName:(const std::optional<std::string>&)fragmentShaderName
                             prefix:(const std::optional<std::string>&)prefixString // String prepended to program source (both vs and fs)
                  attributeBindings:(const oo::PList&)attributeBindings // Maps vertex attribute names to "locations".
                           cacheKey:(const std::optional<std::string>&)cacheKey;

// Loads a shader from a file, caching and sharing shader program instances.
+ (id)shaderProgramWithVertexShaderName:(const std::string&)vertexShaderName
                     fragmentShaderName:(const std::string&)fragmentShaderName
                                 prefix:(const std::optional<std::string>&)prefixString // String prepended to program source (both vs and fs)
                      attributeBindings:(const oo::PList&)attributeBindings; // Maps vertex attribute names to "locations".

- (void)apply;
+ (void)applyNone;

- (GLhandleARB)program;

@end

#endif // OO_SHADERS
