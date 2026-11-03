/*

OOTextureGenerator+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-zl36, oo-vl43 and oo-up4b item 2): the Objective-C
OOTextureGenerator, the facade of the C++ cxx::OOTextureGenerator (OOTextureGenerator.h), a
subclass of the OOTextureLoader facade with no ivars (the root's _cxxLoader holds its C++ part).
Its interface is the one OOTextureGenerator.h declared before the conversion, copied exactly, so
OOPixMapTextureLoader and the planet, atmosphere and emission-map generators still subclass it,
and OOTexture still takes one. Imported as the last line of OOTextureGenerator.h; do not import
it directly. Deleted, with OOTextureLoader+ObjCBridge.h, once every generator is C++.


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

#ifndef OOTEXTUREGENERATOR_OBJCBRIDGE_H
#define OOTEXTUREGENERATOR_OBJCBRIDGE_H

@interface OOTextureGenerator : OOTextureLoader

// Generators, unlike normal loaders, get to specify their own flags and other settings.
- (uint32_t)textureOptions; // Default: kOOTextureDefaultOptions
- (GLfloat)anisotropy; // Default: kOOTextureDefaultAnisotropy
- (GLfloat)lodBias; // Default: kOOTextureDefaultLODBias

// Key for in-memory cache; nullopt for no cache.
- (std::optional<std::string>)cxx_cacheKey;

// For use by OOTexture.
- (BOOL)enqueue;

@end

namespace oo {

// The generator's Objective-C object (an Objective-C generator itself, else a C++ generator's
// facade), autoreleased; nil for null.
OOTextureGenerator* ToObjC(cxx::OOTextureGenerator* generator);

// The C++ generator behind an Objective-C one, borrowed; null for nil.
cxx::OOTextureGenerator* ToCxx(OOTextureGenerator* generator);

} // namespace oo

#endif // OOTEXTUREGENERATOR_OBJCBRIDGE_H
