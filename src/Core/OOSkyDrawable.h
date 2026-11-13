/*

OOSkyDrawable.h

Drawable for the sky (i.e., the surrounding space, not planetary atmosphere).


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

#include "OODrawable.h"
#include "OOGraphicsResetManager.h"
#include "OOOpenGL.h"
#include "oofnd/Ref.hpp"

class OOColor;
class OOSkyQuadSet;
struct OOSkyQuadDesc;

/*	A drawable. Its one caller, SkyEntity, makes it with oo::makeRef and
   hands it to the entity. It is a graphics reset client through the C++ client
        interface.
*/
class OOSkyDrawable : public OODrawable, public OOGraphicsResetClient {
 public:
  // -initWithColor1:Color2:Color3:Color4:starCount:nebulaCount:nebulaHueFix:clusterFactor:alpha:scale:
  OOSkyDrawable(OOColor* color1, OOColor* color2, OOColor* color3,
                OOColor* color4, unsigned starCount, unsigned nebulaCount,
                bool nebulaHueFix, float nebulaClusterFactor, float nebulaAlpha,
                float nebulaScale);
  ~OOSkyDrawable() override;

  void renderOpaqueParts() override;
  bool hasOpaqueParts() override;
  GLfloat maxDrawDistance() override;
#ifdef OO_DEBUG_MONITOR_ENABLED
  std::vector<std::shared_ptr<OOTexture>> allTextures() override;
  size_t totalSize() override;
  size_t objectSize() const override { return sizeof *this; }
#endif

  // OOGraphicsResetClient
  void resetGraphicsState() override;

 private:
  friend struct OOSkyDrawableTestAccess;

  void setUpStars(OOColor* color1, OOColor* color2);
  void setUpNebulae(OOColor* color1, OOColor* color2, float nebulaClusterFactor,
                    bool nebulaHueFix, float nebulaAlpha, float nebulaScale);

  void loadStarTextures();
  void loadNebulaTextures();

  void addQuads(OOSkyQuadDesc* quads, unsigned count);

  void ensureTexturesLoaded();

  // The unit test's stand-in for setUpStars(), which needs the game's star
  // textures; null in the game.
  static void (*sSetUpStarsStandIn)(OOSkyDrawable* sky, OOColor* color1,
                                    OOColor* color2);

  unsigned _starCount = {};
  unsigned _nebulaCount = {};

  std::vector<std::shared_ptr<OOSkyQuadSet>>
      _quadSets;  // no `= {}` (GCC, incomplete
                  // T);	// one per texture

  GLint _displayListName = {};
};
