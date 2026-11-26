/*

OOLightParticleEntity.h

Simple particle-type effect entity. Draws a billboard with additive blending.


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

#pragma once

#include "Entity.h"

class OOTexture;

// A particle is made in C++.
class OOLightParticleEntity : public Entity {
public:
    // -initWithDiameter:'s body, run once right after construction: it calls
    // members a subclass overrides. A converted subclass's initialiser calls it
    // first.
    void initWithDiameter(float diameter);

    float diameter();
    void setDiameter(float diameter);

    void setColor(OOColor* color);
    void setColor(OOColor* color, GLfloat alpha);

    /*	For subclasses that don't want the default blur texture.
            NOTE: such subclasses must deal with the OOGraphicsResetManager. Also,
            OOLightParticleEntity assumes the texture is twice as big as the nominal
            size of the particle (with a black border for anti-aliasing purposes).
    */
    virtual OOTexture* texture();

    static void setUpTexture();
    static OOTexture* defaultParticleTexture();
    // Called by the texture's file-local graphics reset client.
    static void resetGraphicsState();

    virtual void drawSubEntityImmediate(bool immediate, bool translucent);

    void drawImmediate(bool immediate, bool translucent) override;
    bool isEffect() override;
    bool canCollide() override;

#ifdef OO_DEBUG_MONITOR_ENABLED
    std::vector<oo::Ref<OOTexture>> allTextures() override;
#endif

    // Public, as the tests read them.
    GLfloat _colorComponents[4] = { };
    float _diameter = { };
};
