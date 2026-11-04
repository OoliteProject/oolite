/*

OOPixMapTextureLoader.mm


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

#include "OOPixMapTextureLoader.h"

#include "OOTextureScaling.h"
#include "oofnd/String.hpp"

oo::Ref<OOPixMapTextureLoader> OOPixMapTextureLoader::loaderWithPixMap(
    OOPixMap pixMap, uint32_t options, bool freeWhenDone) {
  oo::Ref<OOPixMapTextureLoader> result = oo::makeRef<OOPixMapTextureLoader>();
  if (!result->initWithPixMap(pixMap, options, freeWhenDone)) return {};
  return result;
}

bool OOPixMapTextureLoader::initWithPixMap(OOPixMap pixMap, uint32_t options,
                                           bool freeWhenDone) {
  if (!initWithPath(oo::str::format("OOPixMap@%s",
                                    oo::str::pointerDescription(this).c_str()),
                    options))
    return false;

  if (freeWhenDone)
    _pixMap = pixMap;
  else
    _pixMap = OODuplicatePixMap(_pixMap, 0);

  _texOptions = OOApplyTextureOptionDefaults(options);

  if (!OOIsValidPixMap(_pixMap))
    return false;  // was DESTROY(self): the destructor frees _pixMap

  return true;
}

OOPixMapTextureLoader::~OOPixMapTextureLoader() { OOFreePixMap(&_pixMap); }

void OOPixMapTextureLoader::loadTexture() {
  // Generate mip maps if needed.
  if ((_texOptions & kOOTextureMinFilterMask) == kOOTextureMinFilterMipMap) {
    size_t size = OOMinimumPixMapBufferSize(_pixMap) * 4 / 3;
    bool generateMipMaps = OOExpandPixMap(&_pixMap, size);
    if (generateMipMaps) {
      OOGenerateMipMaps(_pixMap.pixels, _pixMap.width, _pixMap.height,
                        _pixMap.format);
    } else {
      _texOptions =
          (_texOptions & ~kOOTextureMinFilterMask) | kOOTextureMinFilterMipMap;
    }
  }

  // Set up output ivars as per OOTextureLoader contract.
  _data = _pixMap.pixels;
  _width = _pixMap.width;
  _height = _pixMap.height;
  _rowBytes = _pixMap.rowBytes;
  _format = _pixMap.format;

  //	Explicitly do not free pixels - ownership passes to texture.
  _pixMap.pixels = NULL;
}

uint32_t OOPixMapTextureLoader::textureOptions() { return _texOptions; }
