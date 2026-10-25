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

#ifndef OOCONCRETETEXTURE_H
#define OOCONCRETETEXTURE_H

#include "OOTexture.h"
#include "OOTextureLoader.h"

#include "oofnd/StdLib.hpp"


#define OOTEXTURE_RELOADABLE		1


/*	Foundation sweep (proposed ADR-0043, bead oo-pa9j): the path, cache key and debug name are
	nil-able strings (a generated texture has no path, and a generator may have no cache key).

	Phase 3 (bead oo-qa7c, proposed ADR-0056 amendment oo-whzh): a C++ leaf of OOTexture. Its
	loader is the C++ OOTextureLoader, held as oo::Ref since bead oo-9ht.114. Its Objective-C facade was
	deleted by bead oo-9ht.105 (ADR-0056 amendment "deleting a facade"): the class is global; the
	root's facade went with bead oo-9ht.99, so callers hold it as an oo::Ref<OOTexture>.
*/
class OOConcreteTexture : public OOTexture
{
public:
	/*	Were -initWithLoader:key:options:anisotropy:lodBias: and -initWithPath:..., which answered
		nil for no loader (amendment oo-novu item 1): null here. The new texture is in the caches.
	*/
	static oo::Ref<OOConcreteTexture> initWithLoader(OOTextureLoader *loader,
													 const std::optional<std::string> &key,
													 uint32_t options,
													 GLfloat anisotropy,
													 GLfloat lodBias);

	static oo::Ref<OOConcreteTexture> initWithPath(const std::string &path,
												   const std::optional<std::string> &key,
												   uint32_t options,
												   float anisotropy,
												   GLfloat lodBias);

	~OOConcreteTexture() override;

	std::optional<std::string> descriptionComponents() const override;
	std::optional<std::string> shortDescriptionComponents() const override;

#ifndef NDEBUG
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
	// The part of -initWithLoader: that cannot fail; the factory adds the texture to the caches.
	OOConcreteTexture(OOTextureLoader *loader,
					  const std::optional<std::string> &key,
					  uint32_t options,
					  GLfloat anisotropy,
					  GLfloat lodBias);

	void setUpTexture();
	void uploadTexture();
	void uploadTextureDataWithMipMap(bool mipMap, OOTextureDataFormat format);
#if OO_TEXTURE_CUBE_MAP
	void uploadTextureCubeMapDataWithMipMap(bool mipMap, OOTextureDataFormat format);
#endif

	GLenum glTextureTarget();

#if OOTEXTURE_RELOADABLE
	bool isReloadable();
#endif

#if OOTEXTURE_RELOADABLE
	std::optional<std::string>	_path = {};
#endif
	std::optional<std::string>	_key = {};
	uint8_t					_loaded: 1 = 0,
							_uploaded: 1 = 0,
#if GL_EXT_texture_rectangle
							_isRectTexture: 1 = 0,
#endif
#if OO_TEXTURE_CUBE_MAP
							_isCubeMap: 1 = 0,
#endif
							_valid: 1 = 0;
	uint8_t					_mipLevels = {};

	oo::Ref<OOTextureLoader>			_loader = {};

	void					*_bytes = {};
	GLuint					_textureName = {};
	uint32_t				_width = {},
							_height = {},
							_originalWidth = {},
							_originalHeight = {};

	OOTextureDataFormat		_format = {};
	uint32_t				_options = {};
#if GL_EXT_texture_lod_bias
	GLfloat					_lodBias = {};
#endif
#if GL_EXT_texture_filter_anisotropic
	float					_anisotropy = {};
#endif

#ifndef NDEBUG
	std::optional<std::string>	_name = {};
#endif
};

#endif	// OOCONCRETETEXTURE_H
