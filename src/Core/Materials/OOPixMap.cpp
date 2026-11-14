/*

OOPixMap.c


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

#include "OOPixMap.h"

#include <cstring>

#include "oofnd/String.hpp"

const OOPixMap kOONullPixMap = {.pixels = NULL,
                                .width = 0,
                                .height = 0,
                                .format = kOOPixMapInvalidFormat,
                                .rowBytes = 0,
                                .bufferSize = 0};

bool OOIsValidPixMap(OOPixMap pixMap) {
  return pixMap.pixels != NULL && pixMap.width > 0 && pixMap.height > 0 &&
         OOIsValidPixMapFormat(pixMap.format) &&
         pixMap.rowBytes >=
             pixMap.width * OOPixMapBytesPerPixelForFormat(pixMap.format) &&
         pixMap.bufferSize >= pixMap.rowBytes * pixMap.height;
}

OOPixMap OOMakePixMap(void* pixels, OOPixMapDimension width,
                      OOPixMapDimension height, OOPixMapFormat format,
                      size_t rowBytes, size_t bufferSize) {
  if (rowBytes == 0) rowBytes = width * OOPixMapBytesPerPixelForFormat(format);
  if (bufferSize == 0) bufferSize = rowBytes * height;

  OOPixMap result = {.pixels = pixels,
                     .width = width,
                     .height = height,
                     .format = format,
                     .rowBytes = rowBytes,
                     .bufferSize = bufferSize};

  if (OOIsValidPixMap(result))
    return result;
  else
    return kOONullPixMap;
}

OOPixMap OOAllocatePixMap(OOPixMapDimension width, OOPixMapDimension height,
                          OOPixMapFormat format, size_t rowBytes,
                          size_t bufferSize) {
  // Create pixmap struct with dummy pixel pointer to test validity.
  OOPixMap pixMap =
      OOMakePixMap((void*)-1, width, height, format, rowBytes, bufferSize);
  if (EXPECT_NOT(!OOIsValidPixMap(pixMap))) return kOONullPixMap;

  pixMap.pixels = malloc(pixMap.bufferSize);
  if (EXPECT_NOT(pixMap.pixels == NULL)) return kOONullPixMap;

  return pixMap;
}

void OOFreePixMap(OOPixMap* ioPixMap) {
  if (EXPECT_NOT(ioPixMap == NULL)) return;

  free(ioPixMap->pixels);
  *ioPixMap = kOONullPixMap;
}

OOPixMap OODuplicatePixMap(OOPixMap srcPixMap, size_t desiredSize) {
  if (EXPECT_NOT(!OOIsValidPixMap(srcPixMap))) return kOONullPixMap;

  size_t minSize = OOMinimumPixMapBufferSize(srcPixMap);
  if (desiredSize < minSize) desiredSize = minSize;

  OOPixMap result =
      OOAllocatePixMap(srcPixMap.width, srcPixMap.width, srcPixMap.format,
                       srcPixMap.rowBytes, desiredSize);
  if (EXPECT_NOT(!OOIsValidPixMap(result))) return kOONullPixMap;

  memcpy(result.pixels, srcPixMap.pixels, minSize);
  return result;
}

bool OOResizePixMap(OOPixMap* ioPixMap, size_t desiredSize) {
  if (EXPECT_NOT(ioPixMap == NULL || !OOIsValidPixMap(*ioPixMap))) return false;
  if (desiredSize == ioPixMap->bufferSize) return true;
  if (desiredSize < OOMinimumPixMapBufferSize(*ioPixMap)) return false;

  void* newPixels = realloc(ioPixMap->pixels, desiredSize);
  if (newPixels != NULL) {
    ioPixMap->pixels = newPixels;
    ioPixMap->bufferSize = desiredSize;
    return true;
  } else {
    return false;
  }
}

bool OOExpandPixMap(OOPixMap* ioPixMap, size_t desiredSize) {
  if (EXPECT_NOT(ioPixMap == NULL || !OOIsValidPixMap(*ioPixMap))) return false;
  if (desiredSize <= ioPixMap->bufferSize) return true;

  return OOResizePixMap(ioPixMap, desiredSize);
}

#ifndef NDEBUG

#include "MyOpenGLView.h"
#include "Universe.h"

void OODumpPixMap(OOPixMap pixMap, const std::string& name) {
  if (!OOIsValidPixMap(pixMap)) return;

  MyOpenGLView* gameView =
      (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);

  switch (pixMap.format) {
    case kOOPixMapInvalidFormat:
      break;

    case kOOPixMapGrayscale:
      if (gameView != nullptr)
        gameView->dumpGrayToFileNamed(name, (uint8_t*)pixMap.pixels,
                                      pixMap.width, pixMap.height,
                                      pixMap.rowBytes);
      break;

    case kOOPixMapGrayscaleAlpha:
      if (gameView != nullptr)
        gameView->dumpGrayAlphaToFileNamed(name, (uint8_t*)pixMap.pixels,
                                           pixMap.width, pixMap.height,
                                           pixMap.rowBytes);
      break;

    case kOOPixMapRGBA:
      if (gameView != nullptr)
        gameView->dumpRGBAToRGBFileNamed(name + " rgb", name + " alpha",
                                         (uint8_t*)pixMap.pixels, pixMap.width,
                                         pixMap.height, pixMap.rowBytes);
      break;
  }
}
#endif

bool OOIsValidPixMapFormat(OOPixMapFormat format) {
  switch (format) {
    case kOOPixMapInvalidFormat:
      return false;
    case kOOPixMapGrayscale:
    case kOOPixMapGrayscaleAlpha:
    case kOOPixMapRGBA:
      return true;
  }

  return false;
}

#ifndef NDEBUG
unsigned short OOPixMapBytesPerPixelForFormat(OOPixMapFormat format) {
  switch (format) {
    case kOOPixMapInvalidFormat:
      return 0;
    case kOOPixMapGrayscale:
      return 1;
    case kOOPixMapGrayscaleAlpha:
      return 2;
    case kOOPixMapRGBA:
      return 4;
  }

  return -1;
}
#endif

std::string OOPixMapFormatName(OOPixMapFormat format) {
  switch (format) {
    case kOOPixMapInvalidFormat:
      return "invalid";
    case kOOPixMapGrayscale:
      return "grayscale";
    case kOOPixMapGrayscaleAlpha:
      return "grayscale+alpha";
    case kOOPixMapRGBA:
      return "RGBA";
  }

  return oo::str::format("invalid<%i>", (int)format);
}

bool OOPixMapFormatHasAlpha(OOPixMapFormat format) {
  switch (format) {
    case kOOPixMapInvalidFormat:
      return false;
    case kOOPixMapGrayscale:
      return false;
    case kOOPixMapGrayscaleAlpha:
      return true;
    case kOOPixMapRGBA:
      return true;
  }

  return false;
}
