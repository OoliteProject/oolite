/*

OODefaultShaderSynthesizer.h

Function to automatically write a shader that implements a given material
specification.


Copyright © 2011–2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the “Software”), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish,0 distribute, sublicense, and/or sell
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

#import "OOFoundation.h"

#include "oofnd/PList.hpp"

#include <optional>
#include <string>

@class OOMesh;

/*	Foundation sweep (bead oo-3rb.150): the material configuration is an oo::PList dictionary, the
        material key and entity name are nil-able strings, and the outputs are the two shader sources, the
        texture list (a PList array) and the uniform specifications (a PList dictionary). On failure the
        strings are empty and the two PLists null, where all four used to be nil.
*/
BOOL OOSynthesizeMaterialShader(const oo::PList& materialConfiguration, const std::optional<std::string>& materialKey, const std::optional<std::string>& entityName, std::string* outVertexShader, std::string* outFragmentShader, oo::PList* outTextureSpecs, oo::PList* outUniformSpecs);
