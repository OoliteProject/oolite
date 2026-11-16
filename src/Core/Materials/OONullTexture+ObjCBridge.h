/*

OONullTexture+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-up4b item 3 and oo-whzh): the Objective-C
OONullTexture, the facade of the C++ cxx::OONullTexture (OONullTexture.h), a subclass of the
OOTexture facade with no ivars. Its interface is the one OONullTexture.h declared before the
conversion. OOTexture's +nullTexture answers it, and code that tests a texture's class still finds
it. Imported as the last line of OONullTexture.h; do not import it directly. Deleted, with
OOTexture+ObjCBridge.h, once every texture and caller is C++.


Copyright (C) 2008-2013 Jens Ayton

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

#ifndef OONULLTEXTURE_OBJCBRIDGE_H
#define OONULLTEXTURE_OBJCBRIDGE_H

@interface OONullTexture : OOTexture

+ (OONullTexture*)sharedNullTexture;

@end

namespace oo {

// The null texture's facade (the one +sharedNullTexture keeps), or nil for null.
OONullTexture* ToObjC(cxx::OONullTexture* texture);

// The C++ null texture behind the facade, borrowed; null for nil.
cxx::OONullTexture* ToCxx(OONullTexture* texture);

} // namespace oo

#endif // OONULLTEXTURE_OBJCBRIDGE_H
