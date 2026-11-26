/*

OOTextureSprite.h

C++20 since bead oo-ljhc (Phase 3, proposed ADR-0056). The Objective-C facade was deleted by
bead oo-9ht.71, which moved the class out of namespace cxx.

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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

#ifndef OOTEXTURESPRITE_H
#define OOTEXTURESPRITE_H

#include "OOFoundation.h"
#include "OOOpenGL.h"
#include "oofnd/objc/OOObject.h"

#include "oofnd/Ref.hpp"

class OOTexture;

#define OPEN_GL_SPRITE_MIN_WIDTH 64.0
#define OPEN_GL_SPRITE_MIN_HEIGHT 64.0

class OOTextureSprite : public oo::RefCounted {
public:
    // Null for a nil texture (-initWithTexture:... answered nil). The first is the texture's
    // original dimensions.
    static oo::Ref<OOTextureSprite> initWithTexture(OOTexture* texture);
    static oo::Ref<OOTextureSprite> initWithTexture(OOTexture* texture, NSSize spriteSize);

    NSSize getSize(); // -size (the ivar keeps its name: amendment oo-862e item 1)

    void blitToX(float x, float y, float z, float a);
    void blitCentredToX(float x, float y, float z, float a);
    void blitBackgroundCentredToX(float x, float y, float z, float a);

private:
    OOTextureSprite(OOTexture* inTexture, NSSize spriteSize); // initWithTexture() checks the texture

    oo::Ref<OOTexture> texture;
    NSSize size = { };
};

#endif // OOTEXTURESPRITE_H
