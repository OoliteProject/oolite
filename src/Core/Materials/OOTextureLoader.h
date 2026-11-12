/*

OOTextureLoader.h

Abstract base class for asynchronous texture loaders, which are dispatched by
OOTextureLoadDispatcher. In general, this should be used through OOTexture.

Note: interface is likely to change in future to support other buffer types
(like S3TC/DXT#).


Copyright (C) 2007-2014 Jens Ayton

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

#pragma once

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "OOAsyncWorkManager.h"
#include "OOOpenGL.h"
#include "OOPixMap.h"
#include "OOTextureFlags.h"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"

class OOTexture;

/*	As OOTexture.h declares it. The loaders do not import OOTexture.h, so
   a test that stands in for OOTexture can still see a C++
   generator; a file that uses the textures imports OOTexture.h itself.
*/
typedef OOPixMapFormat OOTextureDataFormat;

/*	The path is a UTF-8 std::string (never empty once initialised: a nil
   path failed -init); paths passed in are std::optional where the old code
   accepted nil; a texture specifier is an oo::PList.

        The C++ root of the texture loaders, and a task on the work manager.
   The state below is public (the subclasses read it).
*/
class OOTextureLoader : public ::OOAsyncWorkTask {
 public:
  OOTextureLoader();
  ~OOTextureLoader()
      override;  // was -dealloc: frees the pixels not handed over

  /*	Were +cxx_loaderWithPath:options: and
     +cxx_loaderWithTextureSpecifier:extraOptions:folder:. The loader they make
     (the C++ OOPNGTextureLoader) is answered retained, already
          queued on the work manager; null where they answered nil.
  */
  static oo::Ref<OOTextureLoader> loaderWithPath(
      const std::optional<std::string>& path, OOTextureFlags options);

  /*	Convenience method to load images not destined for normal texture use.
          Specifier is a string or a dictionary as with textures. ExtraOptions
     is ored into the option flags interpreted from the specifier. Folder is the
          directory to look in, typically Textures or Images. Options in the
          specifier which are applied at the OOTexture level will be ignored.
  */
  static oo::Ref<OOTextureLoader> loaderWithTextureSpecifier(
      const oo::PList& specifier, OOTextureFlags extraOptions,
      const std::optional<std::string>& folder);

  bool isReady();

  /*	Return value indicates success. This may only be called once (subsequent
          attempts will return failure), and only on the main thread.
  */
  virtual bool getResult(OOPixMap* result, OOTextureDataFormat* outFormat,
                         uint32_t* outWidth, uint32_t* outHeight);

  /*	Hopefully-unique string for texture loader; analagous, but not
     identical, to corresponding texture cacheKey.
  */
  virtual std::optional<std::string> cacheKey();

  // What "%@" prints between the braces of <Class 0x...>{...}
  // (OODescription.h), and the short form's.
  virtual std::optional<std::string> descriptionComponents() const;
  virtual std::optional<std::string> shortDescriptionComponents() const;

  /*	The descriptions, with the
     loader's address: <CxxClass 0x...>{components} (the C++ class's
     name), and the short form names the class, OOTextureGenerator for
     a generator and OOTextureLoader for any other loader.
  */
  std::string description() const;
  std::string shortDescription() const;
  std::string className()
      const;  // the C++ class's name, as [self class] named it

  /*** Subclass interface; do not use on pain of pain. Unless you're
   * subclassing. ***/

  /*	Was -cxx_initWithPath:options:, after [super init] (subclasses shouldn't
     do much on init, because of the whole asynchronous thing): false where it
     answered nil, for no path.
  */
  bool initWithPath(const std::optional<std::string>& path,
                    OOTextureFlags options);

  std::optional<std::string> path();

  /*	Load data, setting up _data, _format, _width, and _height; also
     _rowBytes if it's not _width * OOTextureComponentsForFormat(_format), and
          _originalWidth/_originalHeight if _width and _height for some reason
     aren't the original pixel dimensions.

          Thread-safety concerns: this will be called in a worker thread, and
     there may be several worker threads. The caller takes responsibility for
          autorelease pools and exception safety.

          Superclass will handle scaling and mip-map generation. Data must be
          allocated with malloc() family.
  */
  virtual void loadTexture();

  // The work manager's task: on a work thread, then on the main thread. The
  // every loader has a completion.
  void performAsyncTask() override;
  bool hasCompleteAsyncTask() const override { return true; }
  void completeAsyncTask() override;

  // The state.
  std::string _path = {};

  OOTextureFlags _options = {};
  uint8_t _generateMipMaps : 1 = 0, _scaleAsNormalMap : 1 = 0,
                             _avoidShrinking : 1 = 0,
                             _noScalingWhatsoever : 1 = 0,
                             _extractChannel : 1 = 0, _allowCubeMap : 1 = 0,
                             _isCubeMap : 1 = 0, _ready : 1 = 0;
  uint8_t _extractChannelIndex = {};
  OOTextureDataFormat _format = {};

  void* _data = {};
  uint32_t _width = {}, _height = {}, _originalWidth = {}, _originalHeight = {},
           _shrinkThreshold = {}, _maxSize = {};
  size_t _rowBytes = {};

 private:
  static void setUp();

  void applySettings();
  void getDesiredWidth(OOPixMapDimension* outDesiredWidth,
                       OOPixMapDimension* outDesiredHeight);
  void generateMipMapsForCubeMap();
};
