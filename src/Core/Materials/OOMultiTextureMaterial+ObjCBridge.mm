/*

OOMultiTextureMaterial+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendments oo-smy and oo-vl43): the Objective-C
OOMultiTextureMaterial facade (see OOMultiTextureMaterial+ObjCBridge.h). Its initialiser runs the
C++ factory and adopts the result. Deleted with OOMultiTextureMaterial+ObjCBridge.h.


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

#import "OOMultiTextureMaterial.h"

#if OO_MULTITEXTURE

// A facade of this class is only ever made for a cxx::OOMultiTextureMaterial (oo::ToObjC names the
// facade class after the C++ class, and the initialisers below make one), so the casts are exact.
OOMultiTextureMaterial* oo::ToObjC(cxx::OOMultiTextureMaterial* material)
{
    return static_cast<OOMultiTextureMaterial*>(oo::ToObjC(static_cast<cxx::OOMaterial*>(material)));
}

cxx::OOMultiTextureMaterial* oo::ToCxx(OOMultiTextureMaterial* material)
{
    return static_cast<cxx::OOMultiTextureMaterial*>(oo::ToCxx(static_cast<OOMaterial*>(material)));
}

@interface OOMultiTextureMaterial (OOObjCBridgePrivate)

- (id)initWithNewCxxMultiTextureMaterial:(const oo::Ref<cxx::OOMultiTextureMaterial>&)material;

@end

@implementation OOMultiTextureMaterial

// The facade of material, a new C++ material; nil (self released) where the C++ initialiser failed.
- (id)initWithNewCxxMultiTextureMaterial:(const oo::Ref<cxx::OOMultiTextureMaterial>&)material
{
    if (material == nullptr) {
        [self release];
        return nil;
    }
    return [super initWithNewCxxMaterial:material];
}

// Every ivar zero, as before: -init did not run an initialiser of this class.
- (id)init
{
    return [self initWithNewCxxMultiTextureMaterial:oo::makeRef<cxx::OOMultiTextureMaterial>()];
}

- (id)initWithName:(const std::optional<std::string>&)name configuration:(const oo::PList&)configuration
{
    return [self initWithNewCxxMultiTextureMaterial:cxx::OOMultiTextureMaterial::materialWithName(name, configuration)];
}

- (NSUInteger)textureUnitCount
{
    return oo::ToCxx(self)->textureUnitCount();
}

@end

#endif /* OO_MULTITEXTURE */
