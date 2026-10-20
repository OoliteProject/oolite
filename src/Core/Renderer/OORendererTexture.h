/*

OORendererTexture.h

Texture creation and upload for the renderer layer (issue #579).

Texture-unit state (binding, LOD bias) stays in OORenderStateMachine.h.

A texture is identified by a uint32_t handle, the same value that
OOGLBindTexture and the state machine use for bindings: a GL texture name
on OpenGL, an index into the renderer's own table under SDL_GPU. The
descriptor also carries the sampler settings. GL keeps those in the
texture object; SDL_GPU needs a separate sampler, which its backend will
create from them.

SDL_GPU has no luminance or alpha-only formats and no channel swizzle, so
its backend will expand those to RGBA when uploading. OpenGL uploads them
as they are.


Copyright (C) 2026 Oolite contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#ifndef OORENDERERTEXTURE_H
#define OORENDERERTEXTURE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    kOOTexelRGBA8,
    kOOTexelGray8, // GL_LUMINANCE: (g, g, g, 1)
    kOOTexelAlpha8, // GL_ALPHA: (0, 0, 0, a)
    kOOTexelGrayAlpha8, // GL_LUMINANCE_ALPHA: (g, g, g, a)
} OOTexelFormat;

typedef enum {
    kOOFilterNearest,
    kOOFilterLinear,
    kOOFilterLinearMipmapLinear, // minification only
} OOTextureFilter;

typedef struct {
    bool cube; // six faces, width == height
    unsigned width, height;
    unsigned levels; // mipmap levels to be uploaded, at least 1
    OOTexelFormat format;
    bool srgb; // RGBA8 only
    // Sampler state.
    bool repeatS, repeatT; // otherwise clamped to the edge (cube maps always are)
    OOTextureFilter minFilter, magFilter;
    float anisotropy; // 1 or less for none; callers check support
} OOTextureDescriptor;

/*  The number of mipmap levels Oolite builds for a width x height image:
    halving until the smaller side reaches 1.
*/
unsigned OOTextureMipLevelCount(unsigned width, unsigned height);

// Returns 0 on failure.
uint32_t OORendererCreateTexture(const OOTextureDescriptor* descriptor);

/*  Upload one face (0 for 2D textures; 0-5 as +X, -X, +Y, -Y, +Z, -Z for cube
    maps) of one mipmap level, with rows tightly packed. Every level must be
    uploaded before the texture is drawn with. Neither creating nor
    uploading changes which texture is bound.
*/
void OORendererUploadTexture(uint32_t texture, unsigned face, unsigned level, unsigned width, unsigned height, const void* texels);

// Read one face of one level back, tightly packed. Slow; for debugging.
void OORendererReadTexture(uint32_t texture, unsigned face, unsigned level, unsigned width, unsigned height, void* texels);

void OORendererDeleteTexture(uint32_t texture);

#ifdef __cplusplus
}
#endif

#endif
