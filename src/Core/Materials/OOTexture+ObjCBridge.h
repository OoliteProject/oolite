/*

OOTexture+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-smy and oo-2en): the Objective-C OOTexture, a
facade over the C++ cxx::OOTexture (OOTexture.h), for the callers that message textures (the
materials, the HUD, the GUI, the planets, the debug support, the scripting bindings) and for the
textures not converted yet (OOConcreteTexture, OONullTexture). Its interface
is the one OOTexture.h declared before the conversion, copied exactly (same selectors, same types,
same superclass), so they compile and behave unchanged; OOTextureInternal.h's categories are its
categories. Imported as the last line of OOTexture.h; do not import it directly.

It is a hierarchy root's facade, as OOALSound+ObjCBridge.h is; the table there applies here:

        the texture is                       its facade is                      virtual calls on the
                                                                                  C++ side reach
        -----------------------------------  ---------------------------------  ---------------------
        an Objective-C subclass              the subclass instance itself, and  the subclass's
          (unconverted, [[X alloc] init])    an adapter is its C++ part         methods
        a C++ subclass (converted)           made by oo::ToObjC, one live one   the C++ overrides
                                             per texture (oo::ObjCPeers)

The factories answer the Objective-C texture (an OOConcreteTexture or the OONullTexture), which
cxx::OOTexture's static factories make. A converted caller that keeps a texture while any
subclass is Objective-C holds oo::ObjCRef<OOTexture *>: an Objective-C texture's C++ part does
not retain it. The debug retain tracing flag is cxx::OOTexture's (the subclasses read it); its
traced -retain/-release/-autorelease overrides are gone (amendment oo-whzh item 4).

A converted subclass that its callers message by its own selectors has a facade of its own, a
subclass of this one with no ivars (amendment oo-up4b item 3): oo::ToObjC picks the Objective-C
class named as the C++ class is, else OOTexture.

oo::ToObjC(oo::ToCxx(t)) == t for both kinds. Never add to this file; converted code does not
message the facade. Deleted by its deletion bead once every caller and every texture is C++.


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

#ifndef OOTEXTURE_OBJCBRIDGE_H
#define OOTEXTURE_OBJCBRIDGE_H

@interface OOTexture : OOWeakRefObject {
@private
    oo::Ref<cxx::OOTexture> _cxxTexture;
}

/*	Load a texture, looking in Textures directories.

        NOTE: anisotropy is normalized to the range [0, 1]. 1 means as high an
        anisotropy setting as the hardware supports.

        This method may change; +textureWithConfiguration is generally more
        appropriate.
*/
+ (id)cxx_textureWithName:(const std::optional<std::string>&)name
                 inFolder:(const std::optional<std::string>&)directory
                  options:(OOTextureFlags)options
               anisotropy:(GLfloat)anisotropy
                  lodBias:(GLfloat)lodBias;

/*	Equivalent to cxx_textureWithName:name
                                                         inFolder:directory
                                                          options:kOOTextureDefaultOptions
                                                   anisotropy:kOOTextureDefaultAnisotropy
                                                          lodBias:kOOTextureDefaultLODBias
*/
+ (id)cxx_textureWithName:(const std::optional<std::string>&)name
                 inFolder:(const std::optional<std::string>&)directory;

/*	Load a texure, looking in Textures directories, using configuration
        dictionary or name. (That is, configuration may be either a dictionary
        or a string.)

        Supported keys:
                name				(string, required)
                min_filter			(string, one of "default", "nearest", "linear", "mipmap")
                max_filter			(string, one of "default", "nearest", "linear")
                noShrink			(boolean)
                repeat_s			(boolean)
                repeat_t			(boolean)
                cube_map			(boolean)
                anisotropy			(real)
                texture_LOD_bias	(real)
                extract_channel		(string, one of "r", "g", "b", "a")
 */
+ (id)cxx_textureWithConfiguration:(const oo::PList&)configuration;
+ (id)cxx_textureWithConfiguration:(const oo::PList&)configuration extraOptions:(OOTextureFlags)extraOptions;

/*	Return the "null texture", a texture object representing an empty texture.
        Applying the null texture is equivalent to calling [OOTexture applyNone].
*/
+ (id)nullTexture;

/*	Load a texture from a generator.
 */
+ (id)textureWithGenerator:(OOTextureGenerator*)generator;

//	Load a texture from a generator with option to force an enqueue
+ (id)textureWithGenerator:(OOTextureGenerator*)generator enqueue:(BOOL)enqueue;

/*	Bind the texture to the current texture unit.
        This will block until loading is completed.
*/
- (void)apply;

+ (void)applyNone;

/*	Ensure texture is loaded. This is required because setting up textures
        inside display lists isn't allowed.
*/
- (void)ensureFinishedLoading;

/*	Check whether a texture has loaded. NOTE: this does not do the setup that
        -ensureFinishedLoading does, so -ensureFinishedLoading is still required
        before using the texture in a display list.
*/
- (BOOL)isFinishedLoading;

- (std::optional<std::string>)cxx_cacheKey; // nullopt: not cacheable

/*	Dimensions in pixels.
        This will block until loading is completed.
*/
- (NSSize)dimensions;

/*	Original file dimensions in pixels.
        This will block until loading is completed.
*/
- (NSSize)originalDimensions;

/*	Check whether texture is mip-mapped.
        This will block until loading is completed.
*/
- (BOOL)isMipMapped;

/*	Create a new pixmap with a copy of the texture data. The caller is
        responsible for free()ing the resulting buffer.
*/
- (OOPixMap)copyPixMapRepresentation;

/*	Identify special texture types.
 */
- (BOOL)isRectangleTexture;
- (BOOL)isCubeMap;

/*	Dimensions in texture coordinates.

        If kOOTextureAllowRectTexture is set, and GL_EXT_texture_rectangle is
        available, textures whose dimensions are not powers of two will be loaded
        as rectangle textures. Rectangle textures use unnormalized co-ordinates;
        that is, co-oridinates range from 0 to the actual size of the texture
        rather than 0 to 1. Thus, for rectangle textures, -texCoordsScale returns
        -dimensions (with the required wait for loading) for a rectangle texture.
        For non-rectangle textures, (1, 1) is returned without delay. If the
        texture has power-of-two dimensions, it will be loaded as a normal
        texture.

        Rectangle textures have additional limitations: kOOTextureMinFilterMipMap
        is not supported (kOOTextureMinFilterLinear will be used instead), and
        kOOTextureRepeatS/kOOTextureRepeatT will be ignored.

        Note that 'rectangle texture' is a misnomer; non-rectangle textures may
        be rectangular, as long as their sides are powers of two. Non-power-of-two
        textures would be more descriptive, but this phrase is used for the
        extension that allows 'normal' textures to have non-power-of-two sides
        without additional restrictions. It is intended that OOTexture should
        support this in future, but this shouldn’t affect the interface, only
        avoid the scaling-to-power-of-two stage.
*/
- (NSSize)texCoordsScale;

/*	OpenGL texture name.
        Not reccomended, but required for legacy TextureStore.
*/
- (GLint)glTextureName;

//	Forget all cached textures so new texture objects will reload.
+ (void)clearCache;

// Called by OOGraphicsResetManager as necessary.
+ (void)rebindAllTextures;

#ifdef OO_DEBUG_MONITOR_ENABLED
- (void)setTrace:(BOOL)trace;

+ (std::vector<oo::ObjCRef<OOTexture*>>)cxx_cachedTexturesByAge; // youngest first
+ (std::vector<oo::ObjCRef<OOTexture*>>)cxx_allTextures; // in no particular order

- (size_t)dataSize;

- (std::optional<std::string>)cxx_name; // nullopt: none (bead oo-3rb.289.4)
#endif

@end

@interface OOTexture (OOObjCBridge)

/*	For the facades of converted subclasses: the facade made by alloc and an initialiser of the
        subclass adopts its new C++ texture and is that texture's peer (the one oo::ToObjC answers), as
        amendment oo-vl43 item 2's -initWithNewCxxMaterial: is.
*/
- (id)initWithNewCxxTexture:(const oo::Ref<cxx::OOTexture>&)texture;

@end

namespace oo {

// The texture's Objective-C object: an Objective-C texture itself, else a C++ texture's live
// facade (or a new one); autoreleased. nil for null.
OOTexture* ToObjC(cxx::OOTexture* texture);
inline OOTexture* ToObjC(const Ref<cxx::OOTexture>& texture) { return ToObjC(texture.get()); }

// The C++ texture behind an Objective-C one, borrowed (the Objective-C object retains it); null for nil.
cxx::OOTexture* ToCxx(OOTexture* texture);

} // namespace oo

#endif // OOTEXTURE_OBJCBRIDGE_H
