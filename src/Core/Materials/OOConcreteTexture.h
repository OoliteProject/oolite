/*

OOConcreteTexture.h

Standard implementation of OOTexture. This is an implementation detail, use
OOTexture instead.


Copyright (C) 2007-2013 Jens Ayton and contributors

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

#include "OOOpenGLExtensionManager.h"  // OO_TEXTURE_CUBE_MAP, which the members below test (upstream #748)
#include "OOTexture.h"
#include "OOTextureLoader.h"
#include "oofnd/StdLib.hpp"

#define OOTEXTURE_RELOADABLE 1

/*	The path, cache key and debug name are nil-able strings (a generated
   texture has no path, and a generator may have no cache key).

        A leaf of OOTexture. Its loader is the C++ OOTextureLoader, held as
   oo::Ref. Callers hold it as an oo::Ref<OOTexture>.
*/
class OOConcreteTexture : public OOTexture {
 public:
  /*	Were -initWithLoader:key:options:anisotropy:lodBias: and
     -initWithPath:..., which answered nil for no loader: null here. The new
     texture is in the caches.
  */
  static oo::Ref<OOConcreteTexture> initWithLoader(
      OOTextureLoader* loader, const std::optional<std::string>& key,
      uint32_t options, GLfloat anisotropy, GLfloat lodBias);

  static oo::Ref<OOConcreteTexture> initWithPath(
      const std::string& path, const std::optional<std::string>& key,
      uint32_t options, float anisotropy, GLfloat lodBias);

  ~OOConcreteTexture() override;

  std::optional<std::string> descriptionComponents() const override;
  std::optional<std::string> shortDescriptionComponents() const override;

#ifdef OO_DEBUG_MONITOR_ENABLED
  std::optional<std::string> name() override;
#endif

  void apply() override;
  void ensureFinishedLoading() override;
  bool isFinishedLoading() override;
  std::optional<std::string> cacheKey() override;
  NSSize dimensions() override;
  NSSize originalDimensions() override;
  bool isMipMapped() override;
  OOPixMap copyPixMapRepresentation() override;
  bool isRectangleTexture() override;
  bool isCubeMap() override;
  NSSize texCoordsScale() override;
  GLint glTextureName() override;
  void forceRebind() override;

 private:
  // The part of -initWithLoader: that cannot fail; the factory adds the texture
  // to the caches.
  OOConcreteTexture(OOTextureLoader* loader,
                    const std::optional<std::string>& key, uint32_t options,
                    GLfloat anisotropy, GLfloat lodBias);

  void setUpTexture();
  void uploadTexture();
  void uploadTextureDataWithMipMap(bool mipMap, OOTextureDataFormat format);
#if OO_TEXTURE_CUBE_MAP
  void uploadTextureCubeMapDataWithMipMap(bool mipMap,
                                          OOTextureDataFormat format);
#endif

  GLenum glTextureTarget();

#if OOTEXTURE_RELOADABLE
  bool isReloadable();
#endif

#if OOTEXTURE_RELOADABLE
  std::optional<std::string> _path = {};
#endif
  std::optional<std::string> _key = {};
  uint8_t _loaded : 1 = 0, _uploaded : 1 = 0,
#if GL_EXT_texture_rectangle
                    _isRectTexture : 1 = 0,
#endif
#if OO_TEXTURE_CUBE_MAP
                    _isCubeMap : 1 = 0,
#endif
                    _valid : 1 = 0;
  uint8_t _mipLevels = {};

  oo::Ref<OOTextureLoader> _loader = {};

  void* _bytes = {};
  GLuint _textureName = {};
  uint32_t _width = {}, _height = {}, _originalWidth = {}, _originalHeight = {};

  OOTextureDataFormat _format = {};
  uint32_t _options = {};
#if GL_EXT_texture_lod_bias
  GLfloat _lodBias = {};
#endif
#if GL_EXT_texture_filter_anisotropic
  float _anisotropy = {};
#endif

#ifdef OO_DEBUG_MONITOR_ENABLED
  std::optional<std::string> _name = {};
#endif
};
