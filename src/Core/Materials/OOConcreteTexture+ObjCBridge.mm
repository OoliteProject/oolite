/*

OOConcreteTexture+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056): the Objective-C OOConcreteTexture facade over
cxx::OOConcreteTexture. Deleted, with OOConcreteTexture+ObjCBridge.h, by the bridge's deletion
bead.


Copyright (C) 2007-2013 Jens Ayton and contributors

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

#import "OOConcreteTexture.h"

@implementation OOConcreteTexture

/*	The initialisers release the receiver and answer the new C++ texture's facade, retained, or nil
        where the factory gives null (amendment oo-novu item 2). The factory has already cached the
        texture under its key, which made its facade (the peer oo::ToObjC answers); the receiver would
        be a second one.
*/
- (id)initWithLoader:(OOTextureLoader*)loader
                 key:(const std::optional<std::string>&)key
             options:(uint32_t)options
          anisotropy:(GLfloat)anisotropy
             lodBias:(GLfloat)lodBias
{
    oo::Ref<cxx::OOConcreteTexture> texture = cxx::OOConcreteTexture::initWithLoader(loader, key, options, anisotropy, lodBias);
    [self release];
    return [oo::ToObjC(texture) retain];
}

- (id)initWithPath:(const std::string&)path
               key:(const std::optional<std::string>&)key
           options:(uint32_t)options
        anisotropy:(float)anisotropy
           lodBias:(GLfloat)lodBias
{
    oo::Ref<cxx::OOConcreteTexture> texture = cxx::OOConcreteTexture::initWithPath(path, key, options, anisotropy, lodBias);
    [self release];
    return [oo::ToObjC(texture) retain];
}

@end

// A C++ concrete texture's facade is an OOConcreteTexture: the root's oo::ToObjC picks the
// Objective-C class named as the C++ class is (amendment oo-up4b item 3).
OOConcreteTexture* oo::ToObjC(cxx::OOConcreteTexture* texture)
{
    return static_cast<OOConcreteTexture*>(oo::ToObjC(static_cast<cxx::OOTexture*>(texture)));
}

cxx::OOConcreteTexture* oo::ToCxx(OOConcreteTexture* texture)
{
    return static_cast<cxx::OOConcreteTexture*>(oo::ToCxx(static_cast<OOTexture*>(texture)));
}
