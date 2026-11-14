/*

OOSingleTextureMaterial+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-smy and oo-vl43): the Objective-C
OOSingleTextureMaterial, a facade over the C++ cxx::OOSingleTextureMaterial
(OOSingleTextureMaterial.h), for the callers that make it (OOPlanetDrawable, OOPlanetEntity,
OOMaterialConvenienceCreators). Its interface is the one OOSingleTextureMaterial.h declared before
the conversion, copied exactly (same selectors, same types), so they compile and behave unchanged.
Imported as the last line of OOSingleTextureMaterial.h; do not import it directly.

It has no ivars: the root facade's _cxxMaterial holds the C++ material (ADR-0056 amendment of bead
oo-up4b, item 3). Its initialisers make a new C++ material, whose facade it is from then on, or
answer nil where the Objective-C initialiser did. What it inherits (the basic material's selectors,
-doApply and the rest) reaches the C++ overrides through the facades above it. No Objective-C class
derives from it. Never add to this file; converted code does not message the facade. Deleted by its
deletion bead once every caller is C++.


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

#ifndef OOSINGLETEXTUREMATERIAL_OBJCBRIDGE_H
#define OOSINGLETEXTUREMATERIAL_OBJCBRIDGE_H

@interface OOSingleTextureMaterial : OOBasicMaterial

/*	In addition to OOBasicMateral configuration keys, an OOTexture
        configuration dictionary may be used. If there is a "texture" entry, it
        will be used; otherwise, if there is a "textures" array, its first member
        will be used.

        If the found OOTexture config dictionary contains a "name" key, it will be
        used in preference to the name parameter.
*/
- (id)initWithName:(const std::optional<std::string>&)name configuration:(const oo::PList&)configuration; // shared with OOBasicMaterial and OOMultiTextureMaterial

/*	Designated initializer. Foundation sweep (proposed ADR-0043, bead oo-ac2y): the name is
        nil-able (the initializer fails without one); the configuration is a material configuration
        dictionary (Object nodes for live objects such as colours; null for none) and goes to
        OOBasicMaterial unchanged.
*/
- (id)initWithName:(const std::optional<std::string>&)name texture:(OOTexture*)texture configuration:(const oo::PList&)configuration;

@end

namespace oo {

// The material's Objective-C object (see oo::ToObjC(cxx::OOMaterial *)); nil for null.
OOSingleTextureMaterial* ToObjC(cxx::OOSingleTextureMaterial* material);
inline OOSingleTextureMaterial* ToObjC(const Ref<cxx::OOSingleTextureMaterial>& material) { return ToObjC(material.get()); }

// The C++ material behind an Objective-C one, borrowed; null for nil.
cxx::OOSingleTextureMaterial* ToCxx(OOSingleTextureMaterial* material);

} // namespace oo

#endif // OOSINGLETEXTUREMATERIAL_OBJCBRIDGE_H
