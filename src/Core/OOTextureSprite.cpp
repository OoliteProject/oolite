/*

OOTextureSprite.m

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

#include "OOTextureSprite.h"
#include "OOMacroOpenGL.h"
#include "OOMaths.h"
#include "OOTexture.h"

oo::Ref<OOTextureSprite> OOTextureSprite::initWithTexture(OOTexture* inTexture)
{
    return initWithTexture(inTexture, (inTexture != nullptr) ? inTexture->originalDimensions() : NSSize { }); // a message to nil answered a zero size
}

// -initWithTexture:size:'s failure test, then the object (amendment oo-novu item 1).
oo::Ref<OOTextureSprite> OOTextureSprite::initWithTexture(OOTexture* inTexture, NSSize spriteSize)
{
    if (inTexture == nil) {
        return nullptr;
    }

    return oo::adopt(new OOTextureSprite(inTexture, spriteSize));
}

OOTextureSprite::OOTextureSprite(OOTexture* inTexture, NSSize spriteSize)
{
    texture = oo::Ref<OOTexture>(inTexture);
    size = spriteSize;
}

NSSize OOTextureSprite::getSize()
{
    return size;
}

void OOTextureSprite::blitToX(float x, float y, float z, float a)
{
    OO_ENTER_OPENGL();
    OOSetOpenGLState(OPENGL_STATE_OVERLAY);

    a = OOClamp_0_1_f(a);
    OOGL(glEnable(GL_TEXTURE_2D));
    OOGL(glColor4f(1.0, 1.0, 1.0, a));

    // Note that the textured Quad is drawn ACW from the top left.

    if (texture != nullptr)
        texture->apply(); // a message to nil did nothing
    OOGLBEGIN(GL_QUADS);
    glTexCoord2f(0.0, 0.0);
    glVertex3f(x, y + size.height, z);

    glTexCoord2f(0.0, 1.0);
    glVertex3f(x, y, z);

    glTexCoord2f(1.0, 1.0);
    glVertex3f(x + size.width, y, z);

    glTexCoord2f(1.0, 0.0);
    glVertex3f(x + size.width, y + size.height, z);
    OOGLEND();

    OOGL(glDisable(GL_TEXTURE_2D));

    OOVerifyOpenGLState();
}

void OOTextureSprite::blitCentredToX(float x, float y, float z, float a)
{
    float xs = x - size.width / 2.0;
    float ys = y - size.height / 2.0;
    blitToX(xs, ys, z, a);
}

void OOTextureSprite::blitBackgroundCentredToX(float x, float y, float z, float a)
{
    // Without distance, coriolis stations would be rendered behind the background image.
    // Set an arbitrary value for distance, might not be sufficient for really huge ships.
    float distance = 512.0f;

    size.width *= distance;
    size.height *= distance;
    blitCentredToX(x, y, z * distance, a);
    size.width /= distance;
    size.height /= distance;
}
