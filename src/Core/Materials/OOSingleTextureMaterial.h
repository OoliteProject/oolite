/*

OOSingleTextureMaterial.h

A material with a single texture (and no shaders).


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

#include "OOBasicMaterial.h"

class OOTexture;

class OOSingleTextureMaterial : public OOBasicMaterial {
 public:
  /*	A new material, initialised by the initialiser of the same arguments
     (below); null where the initialiser failed (it answered nil). They were
     [[OOSingleTextureMaterial alloc] initWith...].
  */
  static std::shared_ptr<OOSingleTextureMaterial> materialWithName(
      const std::optional<std::string>& name, const oo::PList& configuration);
  static std::shared_ptr<OOSingleTextureMaterial> materialWithName(
      const std::optional<std::string>& name, OOTexture* texture,
      const oo::PList& configuration);

  /*	In addition to OOBasicMateral configuration keys, an OOTexture
          configuration dictionary may be used. If there is a "texture" entry,
     it will be used; otherwise, if there is a "textures" array, its first
     member will be used.

          If the found OOTexture config dictionary contains a "name" key, it
     will be used in preference to the name parameter.

          The initialisers run once, right after construction, and answer false
     on failure.
  */
  bool initWithName(
      const std::optional<std::string>& name,
      const oo::PList& configuration);  // shared with OOBasicMaterial and
                                        // OOMultiTextureMaterial

  /*	Designated initializer. The name is nil-able (the initializer fails
     without one); the configuration is a material configuration dictionary
     (Object nodes for live objects such as colours; null for none) and goes to
     OOBasicMaterial unchanged.
  */
  bool initWithName(const std::optional<std::string>& name, OOTexture* texture,
                    const oo::PList& configuration);

  std::optional<std::string> descriptionComponents() const override;
  bool doApply() override;
  void unapplyWithNext(OOMaterial* next) override;
  size_t objectSize() const override { return sizeof *this; }
  void ensureFinishedLoading() override;
  bool isFinishedLoading() override;
  bool wantsNormalsAsTextureCoordinates() override;
#ifdef OO_DEBUG_MONITOR_ENABLED
  std::vector<std::shared_ptr<OOTexture>> allTextures() override;
#endif

 private:
  std::shared_ptr<OOTexture> _texture = {};
};
