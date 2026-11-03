/*

OOMultiTextureMaterial+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-smy and oo-vl43): the Objective-C
OOMultiTextureMaterial, a facade over the C++ cxx::OOMultiTextureMaterial
(OOMultiTextureMaterial.h), for the caller that makes it (OOMaterialConvenienceCreators). Its
interface is the one OOMultiTextureMaterial.h declared before the conversion, copied exactly, so it
compiles and behaves unchanged. Imported as the last line of OOMultiTextureMaterial.h; do not
import it directly.

It has no ivars: the root facade's _cxxMaterial holds the C++ material (ADR-0056 amendment of bead
oo-up4b, item 3). Its initialiser makes a new C++ material, whose facade it is from then on, or
answers nil where the Objective-C initialiser did. What it inherits reaches the C++ overrides
through the facades above it (-apply too: it is virtual since this bead). No Objective-C class
derives from it. Never add to this file. Deleted by its deletion bead once its caller is C++.


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

#ifndef OOMULTITEXTUREMATERIAL_OBJCBRIDGE_H
#define OOMULTITEXTUREMATERIAL_OBJCBRIDGE_H

@interface OOMultiTextureMaterial : OOBasicMaterial

- (id)initWithName:(const std::optional<std::string>&)name configuration:(const oo::PList&)configuration; // shared with OOBasicMaterial

- (NSUInteger)textureUnitCount;

@end

namespace oo {

// The material's Objective-C object (see oo::ToObjC(cxx::OOMaterial *)); nil for null.
OOMultiTextureMaterial* ToObjC(cxx::OOMultiTextureMaterial* material);
inline OOMultiTextureMaterial* ToObjC(const Ref<cxx::OOMultiTextureMaterial>& material) { return ToObjC(material.get()); }

// The C++ material behind an Objective-C one, borrowed; null for nil.
cxx::OOMultiTextureMaterial* ToCxx(OOMultiTextureMaterial* material);

} // namespace oo

#endif // OOMULTITEXTUREMATERIAL_OBJCBRIDGE_H
