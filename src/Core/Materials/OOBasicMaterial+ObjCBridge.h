/*

OOBasicMaterial+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendment oo-vl43): the Objective-C OOBasicMaterial, a facade over
the C++ cxx::OOBasicMaterial (OOBasicMaterial.h), for the callers that make and message basic
materials (OOMesh, OOMaterialConvenienceCreators) and for the three materials not converted yet
(OOSingleTextureMaterial, OOMultiTextureMaterial, OOShaderMaterial), which derive from it. Its
interface is the one OOBasicMaterial.h declared before the conversion, copied exactly (same
selectors, same types), so they compile and behave unchanged. Imported as the last line of
OOBasicMaterial.h; do not import it directly.

It is an intermediate class's facade (ADR-0056 amendment of bead oo-up4b, items 2 and 3): it has
no ivars (the root facade's _cxxMaterial holds its C++ part), and

        the material is                      its C++ part is
        -----------------------------------  ---------------------------------------------------------
        [[OOBasicMaterial alloc] init...]    a new cxx::OOBasicMaterial, whose facade this is
        a C++ basic material                 itself; oo::ToObjC makes this facade (one live one)
        an Objective-C subclass              an adapter derived from cxx::OOBasicMaterial, so what the
          ([[X alloc] init...] of one)       subclass does not override (and [super ...]) answers as
                                             that class does, and permitSpecular() reaches its override

oo::ToObjC(oo::ToCxx(m)) == m for every kind. Never add to this file; converted code does not
message the facade. Deleted by its deletion bead once every caller and every subclass is C++.


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

#ifndef OOBASICMATERIAL_OBJCBRIDGE_H
#define OOBASICMATERIAL_OBJCBRIDGE_H

@interface OOBasicMaterial : OOMaterial

/*	Initialize with default values (historical Olite defaults, not GL defaults):
                diffuse		{ 1.0, 1.0, 1.0, 1.0 }
                specular	{ 0.0, 0.0, 0.0, 1.0 }
                ambient		{ 1.0, 1.0, 1.0, 1.0 }
                emission	{ 0.0, 0.0, 0.0, 1.0 }
                shininess	0
*/
- (id)cxx_initWithName:(const std::optional<std::string>&)name OO_RETURNS_RETAINED; // (bead oo-3rb.289.5)

/*	Initialize with dictionary. Accepted keys:
                diffuse		colour description
                specular	colour description
                ambient		colour description
                emission	colour description
                shininess	integer

        "Colour description" refers to anything +[OOColor colorWithDescription:]
        will accept.
*/
- (id)initWithName:(const std::optional<std::string>&)name configuration:(const oo::PList&)configuration; // a null configuration is an empty one. Shared by the material classes.

- (OOColor*)diffuseColor;
- (void)setDiffuseColor:(OOColor*)color;
- (void)setAmbientAndDiffuseColor:(OOColor*)color;
- (OOColor*)specularColor;
- (void)setSpecularColor:(OOColor*)color;
- (OOColor*)ambientColor;
- (void)setAmbientColor:(OOColor*)color;
- (OOColor*)emmisionColor;
- (void)setEmissionColor:(OOColor*)color;

- (void)getDiffuseComponents:(GLfloat[4])outComponents;
- (void)setDiffuseComponents:(const GLfloat[4])components;
- (void)setAmbientAndDiffuseComponents:(const GLfloat[4])components;
- (void)getSpecularComponents:(GLfloat[4])outComponents;
- (void)setSpecularComponents:(const GLfloat[4])components;
- (void)getAmbientComponents:(GLfloat[4])outComponents;
- (void)setAmbientComponents:(const GLfloat[4])components;
- (void)getEmissionComponents:(GLfloat[4])outComponents;
- (void)setEmissionComponents:(const GLfloat[4])components;

- (void)setDiffuseRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a;
- (void)setAmbientAndDiffuseRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a;
- (void)setSpecularRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a;
- (void)setAmbientRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a;
- (void)setEmissionRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a;

- (uint8_t)shininess;
- (void)setShininess:(uint8_t)value; // Clamped to [0, 128]

/*	For subclasses: return true to permit specular settings, false to deny
        them. By default, this is ![UNIVERSE reducedDetail].
*/
- (BOOL)permitSpecular;

@end

namespace oo {

// The material's Objective-C object (see oo::ToObjC(cxx::OOMaterial *)); nil for null.
OOBasicMaterial* ToObjC(cxx::OOBasicMaterial* material);
inline OOBasicMaterial* ToObjC(const Ref<cxx::OOBasicMaterial>& material) { return ToObjC(material.get()); }

// The C++ material behind an Objective-C one, borrowed; null for nil.
cxx::OOBasicMaterial* ToCxx(OOBasicMaterial* material);

} // namespace oo

#endif // OOBASICMATERIAL_OBJCBRIDGE_H
