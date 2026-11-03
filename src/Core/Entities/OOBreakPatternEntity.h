/*

OOBreakPatternEntity.h

Entity implementing tunnel effect for hyperspace and stations.


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

enum {
    kOOBreakPatternMaxSides = 128,
    kOOBreakPatternMaxVertices = (kOOBreakPatternMaxSides + 1) * 2
};

#define BREAK_PATTERN_RING_SPACING 50.0
#define BREAK_PATTERN_RING_SPEED 200.0

struct OOBreakPatternEntityTestAccess;

class OOBreakPatternEntity : public Entity {
public:
    // +breakPatternWithPolygonSides:startAngle:aspectRatio:: a new ring, initialised.
    static oo::Ref<OOBreakPatternEntity> breakPatternWithPolygonSides(NSUInteger sides, float startAngleDegrees, float aspectRatio);

    void setInnerColor(OOColor* color1, OOColor* color2);

    void setLifetime(double lifetime);

    void update(OOTimeDelta delta_t) override;
    void drawImmediate(bool immediate, bool translucent) override;
    bool canCollide() override;

private:
    friend struct ::OOBreakPatternEntityTestAccess;

    // -initWithPolygonSides:startAngle:aspectRatio:'s body, run once right after construction
    // (amendment oo-vl43 item 2).
    void initWithPolygonSides(NSUInteger sides, float startAngleDegrees, float aspectRatio);

    void setInnerColorComponents(GLfloat color1[4], GLfloat color2[4]);

    Vector _vertexPosition[kOOBreakPatternMaxVertices] = { };
    GLfloat _vertexColor[kOOBreakPatternMaxVertices][4] = { };
    NSUInteger _vertexCount = { };
    double _lifetime = { };
};
