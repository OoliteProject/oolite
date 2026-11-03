/*

OOTextureGenerator.h

A texture "loader" which doesn't require an input file.


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

#ifndef OOTEXTUREGENERATOR_H
#define OOTEXTUREGENERATOR_H

#include "OOTextureLoader.h"

typedef struct
{
    float r, g, b;
} FloatRGB;

typedef struct
{
    float r, g, b, a;
} FloatRGBA;

/*	Phase 3 (bead oo-rr2x, proposed ADR-0056 amendments oo-zl36 and oo-vl43): an intermediate C++
        class of the texture loaders, which OOPixMapTextureLoader and the planet, atmosphere and
        emission-map generators derive from. Its Objective-C facade was deleted by bead oo-9ht.118
        (ADR-0056 amendment oo-9ht.114), which moved the class out of namespace cxx.
*/
class OOTextureGenerator : public OOTextureLoader {
public:
    // Generators, unlike normal loaders, get to specify their own flags and other settings.
    virtual uint32_t textureOptions(); // Default: kOOTextureDefaultOptions
    virtual GLfloat anisotropy(); // Default: kOOTextureDefaultAnisotropy
    virtual GLfloat lodBias(); // Default: kOOTextureDefaultLODBias

    // Key for in-memory cache; nullopt for no cache.
    std::optional<std::string> cacheKey() override;

    // For use by OOTexture: queues the generator on the work manager.
    virtual bool enqueue();
};

#endif // OOTEXTUREGENERATOR_H
