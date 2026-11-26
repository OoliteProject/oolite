/*

OOPixMapTextureLoader.h

Load a texture from a pixmap. The loader takes ownership of the pixmap.


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

#ifndef OOPIXMAPTEXTURELOADER_H
#define OOPIXMAPTEXTURELOADER_H

#include "OOPixMap.h"
#include "OOTexture.h"
#include "OOTextureGenerator.h"

/*	Phase 3 (bead oo-kvqq, proposed ADR-0056 amendments oo-bj8 item 12, oo-2c6g item 2, oo-rr2x
        and oo-z889): a converted leaf of the texture generators, global, over OOTextureGenerator,
        with no facade of its own. Its callers (the planets) make it with loaderWithPixMap and hand
        the texture the C++ loader (the generators' facade until bead oo-9ht.118 deleted it).
*/
class OOPixMapTextureLoader : public OOTextureGenerator {
public:
    ~OOPixMapTextureLoader() override; // was -dealloc

    /*	Was [[OOPixMapTextureLoader alloc] initWithPixMap:textureOptions:freeWhenDone:]: null where
            that answered nil (amendment oo-novu).
    */
    static oo::Ref<OOPixMapTextureLoader> loaderWithPixMap(OOPixMap pixMap, uint32_t options, bool freeWhenDone);

    // Was -initWithPixMap:textureOptions:freeWhenDone:; false where it answered nil.
    bool initWithPixMap(OOPixMap pixMap, uint32_t options, bool freeWhenDone);

    void loadTexture() override;
    uint32_t textureOptions() override;

private:
    OOPixMap _pixMap = { };
    uint32_t _texOptions = { };
};

#endif // OOPIXMAPTEXTURELOADER_H
