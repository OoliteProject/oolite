/*

OOSingleTextureMaterial+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendments oo-smy and oo-vl43): the Objective-C
OOSingleTextureMaterial facade (see OOSingleTextureMaterial+ObjCBridge.h). Its initialisers run the
C++ factories and adopt the result. Deleted with OOSingleTextureMaterial+ObjCBridge.h.


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

#import "OOSingleTextureMaterial.h"

// A facade of this class is only ever made for a cxx::OOSingleTextureMaterial (oo::ToObjC names
// the facade class after the C++ class, and the initialisers below make one), so the casts are exact.
OOSingleTextureMaterial* oo::ToObjC(cxx::OOSingleTextureMaterial* material)
{
    return static_cast<OOSingleTextureMaterial*>(oo::ToObjC(static_cast<cxx::OOMaterial*>(material)));
}

cxx::OOSingleTextureMaterial* oo::ToCxx(OOSingleTextureMaterial* material)
{
    return static_cast<cxx::OOSingleTextureMaterial*>(oo::ToCxx(static_cast<OOMaterial*>(material)));
}

@interface OOSingleTextureMaterial (OOObjCBridgePrivate)

- (id)initWithNewCxxSingleTextureMaterial:(const oo::Ref<cxx::OOSingleTextureMaterial>&)material;

@end

@implementation OOSingleTextureMaterial

// The facade of material, a new C++ material; nil (self released) where the C++ initialiser failed.
- (id)initWithNewCxxSingleTextureMaterial:(const oo::Ref<cxx::OOSingleTextureMaterial>&)material
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
    return [self initWithNewCxxSingleTextureMaterial:oo::makeRef<cxx::OOSingleTextureMaterial>()];
}

- (id)initWithName:(const std::optional<std::string>&)name configuration:(const oo::PList&)configuration
{
    return [self initWithNewCxxSingleTextureMaterial:cxx::OOSingleTextureMaterial::materialWithName(name, configuration)];
}

- (id)initWithName:(const std::optional<std::string>&)name texture:(OOTexture*)texture configuration:(const oo::PList&)configuration
{
    return [self initWithNewCxxSingleTextureMaterial:cxx::OOSingleTextureMaterial::materialWithName(name, texture, configuration)];
}

@end
