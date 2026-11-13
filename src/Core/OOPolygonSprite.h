/*

OOPolygonSprite.h
Oolite

Two-dimensional polygon object for UI things such as missile icons.

The class is its own graphics reset client, and it is an OOHUDBeaconIcon, the
C++ interface which the entities hold their beacon drawables by.

Copyright (C) 2009-2013 Jens Ayton

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

#include "OOFoundation.h"
#include "OOGraphicsResetManager.h"
#include "OOOpenGL.h"
#include "OOOpenGLExtensionManager.h"
#include "oofnd/Object.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/objc/OOObject.h"

/*	A HUD compass icon of a beacon: the interface OOHUDBeaconIcon. The
   polygon sprite and the beacon code icon (OOHUDBeaconCodeIcon,
   HeadUpDisplay.h) implement it; the ships, visual effects and waypoints hold
        their beacon drawables by it, as std::shared_ptr<OOHUDBeaconIcon>, and
   the HUD draws them.
*/
class OOHUDBeaconIcon : public oo::Object {
 public:
  virtual void drawHUDBeaconIconAt(
      NSPoint where, NSSize size, GLfloat alpha,
      GLfloat z) = 0;  // -oo_drawHUDBeaconIconAt:size:alpha:z:
};

class OOPolygonSprite : public OOHUDBeaconIcon, public OOGraphicsResetClient {
 public:
  /*	DataArray is either an array of pairs of numbers, or an array of such
          arrays (representing one or more contours), as property-list data.
          OutlineWidth is the width of the tesselated outline, in the same scale
     as the vertices. Name is used for debugging only. Null where the data
     cannot be tesselated (-initWithDataArray:... answered nil).
  */
  static std::shared_ptr<OOPolygonSprite> initWithDataArray(
      const oo::PList& dataArray, GLfloat outlineWidth,
      const std::string& name);

  void drawFilled();
  void drawOutline();

  // OOGraphicsResetClient: a sprite registers itself when made and unregisters
  // when destroyed, as -initWithDataArray:... and -dealloc did.
  void resetGraphicsState() override;

  // OOHUDBeaconIcon: the drawing of the sprite's OOHUDBeaconIcon category
  // (HeadUpDisplay.cpp).
  void drawHUDBeaconIconAt(NSPoint where, NSSize size, GLfloat alpha,
                           GLfloat z) override;

  // What "%@" prints: <OOPolygonSprite 0x...>, with
  // {components} in debug builds.
  std::string description() const;

#ifndef NDEBUG
  // What "%@" prints between the braces of <OOPolygonSprite 0x...>{...}
  // (OODescription.h).
  std::optional<std::string> descriptionComponents() const;
#endif

  ~OOPolygonSprite() override;

 private:
  OOPolygonSprite() =
      default;  // initWithDataArray() does -initWithDataArray:...'s work

  void drawWithData(GLfloat* data, size_t count, GLuint* vbo);
  bool loadPolygons(const oo::PList& dataArray, float outlineWidth);

  std::vector<GLfloat> _solidData;    // the fill's triangles, as x, y pairs
  std::vector<GLfloat> _outlineData;  // the outline's, likewise

#if OO_USE_VBO
  GLuint _solidVBO = {};
  GLuint _outlineVBO = {};
#endif

#ifndef NDEBUG
  std::string _name;  // for debugging
#endif
};
