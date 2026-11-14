/*

OOConcreteTexture+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-up4b item 3 and oo-whzh): the Objective-C
OOConcreteTexture, the facade of the C++ cxx::OOConcreteTexture (OOConcreteTexture.h), a subclass
of the OOTexture facade with no ivars. Its interface is the one OOConcreteTexture.h declared
before the conversion; a C++ concrete texture crossing to Objective-C is one of these, so code
that tests a texture's class still finds it. Imported as the last line of OOConcreteTexture.h; do
not import it directly. Deleted, with OOTexture+ObjCBridge.h, once every caller is C++.


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

#ifndef OOCONCRETETEXTURE_OBJCBRIDGE_H
#define OOCONCRETETEXTURE_OBJCBRIDGE_H

@interface OOConcreteTexture : OOTexture

- (id)initWithLoader:(OOTextureLoader*)loader
                 key:(const std::optional<std::string>&)key
             options:(uint32_t)options
          anisotropy:(GLfloat)anisotropy
             lodBias:(GLfloat)lodBias;

- (id)initWithPath:(const std::string&)path
               key:(const std::optional<std::string>&)key
           options:(uint32_t)options
        anisotropy:(float)anisotropy
           lodBias:(GLfloat)lodBias;

@end

namespace oo {

// A concrete texture's facade, or nil for null.
OOConcreteTexture* ToObjC(cxx::OOConcreteTexture* texture);
inline OOConcreteTexture* ToObjC(const Ref<cxx::OOConcreteTexture>& texture) { return ToObjC(texture.get()); }

// The C++ texture behind the facade, borrowed; null for nil.
cxx::OOConcreteTexture* ToCxx(OOConcreteTexture* texture);

} // namespace oo

#endif // OOCONCRETETEXTURE_OBJCBRIDGE_H
