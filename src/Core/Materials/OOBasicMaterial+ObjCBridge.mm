/*

OOBasicMaterial+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendment oo-vl43): the Objective-C OOBasicMaterial facade (see
OOBasicMaterial+ObjCBridge.h). Every method forwards to its C++ member through oo::ToCxx(self):
colours cross with oo::ToCxx / oo::ToObjC. The initialisers make the C++ part (a new
cxx::OOBasicMaterial, or an Objective-C subclass's adapter) and run the C++ initialiser on it.
Deleted with OOBasicMaterial+ObjCBridge.h.


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

#import "OOBasicMaterial.h"

namespace {

/*	The C++ part of an Objective-C subclass of OOBasicMaterial: the root's adapter over
        cxx::OOBasicMaterial, and the one virtual member this class adds, so a subclass's
        -permitSpecular is what the C++ initialiser asks.
*/
class ObjCBasicMaterial final : public oo::ObjCMaterial<cxx::OOBasicMaterial> {
public:
    explicit ObjCBasicMaterial(::OOBasicMaterial* owner)
        : oo::ObjCMaterial<cxx::OOBasicMaterial>(owner)
    {
    }

    bool permitSpecular() override { return [static_cast<::OOBasicMaterial*>(_owner) permitSpecular]; }
};

} // namespace

// A facade of this class is only ever made for a cxx::OOBasicMaterial (oo::ToObjC names the facade
// class after the C++ class, and the initialisers below make one), or it is an Objective-C
// subclass instance whose adapter derives from it, so the casts are exact.
OOBasicMaterial* oo::ToObjC(cxx::OOBasicMaterial* material)
{
    return static_cast<OOBasicMaterial*>(oo::ToObjC(static_cast<cxx::OOMaterial*>(material)));
}

cxx::OOBasicMaterial* oo::ToCxx(OOBasicMaterial* material)
{
    return static_cast<cxx::OOBasicMaterial*>(oo::ToCxx(static_cast<OOMaterial*>(material)));
}

@interface OOBasicMaterial (OOObjCBridgePrivate)

- (id)initBasicMaterial;

@end

@implementation OOBasicMaterial

// The C++ part, not yet initialised: [[OOBasicMaterial alloc] init...] makes a new C++ basic
// material and is its facade; an Objective-C subclass's is its adapter.
- (id)initBasicMaterial
{
    if ([self class] == [OOBasicMaterial class])
        return [super initWithNewCxxMaterial:oo::makeRef<cxx::OOBasicMaterial>()];
    return [super initWithCxxMaterial:oo::makeRef<ObjCBasicMaterial>(self).get()];
}

// Every ivar zero, as before: -init did not run an initialiser of this class.
- (id)init
{
    return [self initBasicMaterial];
}

- (id)cxx_initWithName:(const std::optional<std::string>&)name
{
    self = [self initBasicMaterial];
    if (self != nil)
        oo::ToCxx(self)->initWithName(name);
    return self;
}

- (id)initWithName:(const std::optional<std::string>&)name configuration:(const oo::PList&)configuration
{
    self = [self initBasicMaterial];
    if (self != nil)
        oo::ToCxx(self)->initWithName(name, configuration);
    return self;
}

- (OOColor*)diffuseColor
{
    return oo::ToObjC(oo::ToCxx(self)->diffuseColor());
}
- (void)setDiffuseColor:(OOColor*)color
{
    oo::ToCxx(self)->setDiffuseColor(oo::ToCxx(color));
}
- (void)setAmbientAndDiffuseColor:(OOColor*)color
{
    oo::ToCxx(self)->setAmbientAndDiffuseColor(oo::ToCxx(color));
}
- (OOColor*)specularColor
{
    return oo::ToObjC(oo::ToCxx(self)->specularColor());
}
- (void)setSpecularColor:(OOColor*)color
{
    oo::ToCxx(self)->setSpecularColor(oo::ToCxx(color));
}
- (OOColor*)ambientColor
{
    return oo::ToObjC(oo::ToCxx(self)->ambientColor());
}
- (void)setAmbientColor:(OOColor*)color
{
    oo::ToCxx(self)->setAmbientColor(oo::ToCxx(color));
}
- (OOColor*)emmisionColor
{
    return oo::ToObjC(oo::ToCxx(self)->emmisionColor());
}
- (void)setEmissionColor:(OOColor*)color
{
    oo::ToCxx(self)->setEmissionColor(oo::ToCxx(color));
}

- (void)getDiffuseComponents:(GLfloat[4])outComponents
{
    oo::ToCxx(self)->getDiffuseComponents(outComponents);
}
- (void)setDiffuseComponents:(const GLfloat[4])components
{
    oo::ToCxx(self)->setDiffuseComponents(components);
}
- (void)setAmbientAndDiffuseComponents:(const GLfloat[4])components
{
    oo::ToCxx(self)->setAmbientAndDiffuseComponents(components);
}
- (void)getSpecularComponents:(GLfloat[4])outComponents
{
    oo::ToCxx(self)->getSpecularComponents(outComponents);
}
- (void)setSpecularComponents:(const GLfloat[4])components
{
    oo::ToCxx(self)->setSpecularComponents(components);
}
- (void)getAmbientComponents:(GLfloat[4])outComponents
{
    oo::ToCxx(self)->getAmbientComponents(outComponents);
}
- (void)setAmbientComponents:(const GLfloat[4])components
{
    oo::ToCxx(self)->setAmbientComponents(components);
}
- (void)getEmissionComponents:(GLfloat[4])outComponents
{
    oo::ToCxx(self)->getEmissionComponents(outComponents);
}
- (void)setEmissionComponents:(const GLfloat[4])components
{
    oo::ToCxx(self)->setEmissionComponents(components);
}

- (void)setDiffuseRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a
{
    oo::ToCxx(self)->setDiffuseRed(r, g, b, a);
}
- (void)setAmbientAndDiffuseRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a
{
    oo::ToCxx(self)->setAmbientAndDiffuseRed(r, g, b, a);
}
- (void)setSpecularRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a
{
    oo::ToCxx(self)->setSpecularRed(r, g, b, a);
}
- (void)setAmbientRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a
{
    oo::ToCxx(self)->setAmbientRed(r, g, b, a);
}
- (void)setEmissionRed:(GLfloat)r green:(GLfloat)g blue:(GLfloat)b alpha:(GLfloat)a
{
    oo::ToCxx(self)->setEmissionRed(r, g, b, a);
}

- (uint8_t)shininess
{
    return oo::ToCxx(self)->shininess();
}
- (void)setShininess:(uint8_t)value
{
    oo::ToCxx(self)->setShininess(value);
}

// Overridable: on an Objective-C subclass (reached only when it does not override it, or by
// [super permitSpecular]) this class's own member answers; on a C++ material's facade, its override.
- (BOOL)permitSpecular
{
    cxx::OOBasicMaterial* material = oo::ToCxx(self);
    if (oo::AsObjCMaterial(material) != nullptr)
        return material->cxx::OOBasicMaterial::permitSpecular();
    return material->permitSpecular();
}

@end
