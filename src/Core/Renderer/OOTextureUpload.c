/*

OOTextureUpload.c


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

#include "OORenderStateMachine.h"
#include "OORendererBackend.h"
#include "OORendererTexture.h"

unsigned OOTextureMipLevelCount(unsigned width, unsigned height)
{
    unsigned levels = 0;
    while (width > 0 && height > 0) {
        levels++;
        width >>= 1;
        height >>= 1;
    }
    return levels;
}

uint32_t OORendererCreateTexture(const OOTextureDescriptor* descriptor)
{
    if (descriptor == NULL || descriptor->width == 0 || descriptor->height == 0) {
        OORendererBackendWarn("OORendererCreateTexture: empty texture");
        return 0;
    }
    if (descriptor->cube && descriptor->width != descriptor->height) {
        OORendererBackendWarn("OORendererCreateTexture: cube map faces must be square");
        return 0;
    }
    if (descriptor->levels == 0 || descriptor->levels > OOTextureMipLevelCount(descriptor->width, descriptor->height)) {
        OORendererBackendWarn("OORendererCreateTexture: bad mipmap level count");
        return 0;
    }
    if (descriptor->srgb && descriptor->format != kOOTexelRGBA8) {
        OORendererBackendWarn("OORendererCreateTexture: sRGB needs RGBA8 texels");
        return 0;
    }
    return OORendererBackendCreateTexture(descriptor);
}

void OORendererUploadTexture(uint32_t texture, unsigned face, unsigned level, unsigned width, unsigned height, const void* texels)
{
    if (texture == 0 || face > 5)
        return;
    OORendererBackendUploadTexture(texture, face, level, width, height, texels);
}

void OORendererReadTexture(uint32_t texture, unsigned face, unsigned level, unsigned width, unsigned height, void* texels)
{
    if (texture == 0 || face > 5)
        return;
    OORendererBackendReadTexture(texture, face, level, width, height, texels);
}

void OORendererDeleteTexture(uint32_t texture)
{
    if (texture == 0)
        return;
    OORendererForgetTexture(texture);
    OORendererBackendDeleteTexture(texture);
}
