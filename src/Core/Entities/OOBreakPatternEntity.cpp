/*

OOBreakPatternEntity.m

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

#include "OOBreakPatternEntity.h"

#include <cstring>

#include "OOColor.h"
#include "OOMacroOpenGL.h"
#include "Universe.h"

void OOBreakPatternEntity::initWithPolygonSides(NSUInteger sides,
                                                float startAngleDegrees,
                                                float aspectRatio) {
  sides = MIN(MAX((NSUInteger)3, sides), (NSUInteger)kOOBreakPatternMaxSides);

  // [super init] could not fail: the constructor ran Entity's -init body.
  {
    _vertexCount = (sides + 1) * 2;
    float angle = startAngleDegrees * M_PI / 180.0f;
    float deltaAngle = M_PI * 2.0f / sides;
    float xAspect = fmin(1.0f, aspectRatio);
    float yAspect = fmin(1.0f, 1.0f / aspectRatio);

    NSUInteger vi = 0;
    for (NSUInteger i = 0; i < sides; i++) {
      float s = sin(angle) * xAspect;
      float c = cos(angle) * yAspect;

      _vertexPosition[vi++] = (Vector){s * 50, c * 50, -40};
      _vertexPosition[vi++] = (Vector){s * 40, c * 40, 0};

      angle += deltaAngle;
    }

    _vertexPosition[vi++] = _vertexPosition[0];
    _vertexPosition[vi++] = _vertexPosition[1];

    setInnerColorComponents((GLfloat[]){1.0f, 0.0f, 0.0f, 0.5f},
                            (GLfloat[]){0.0f, 0.0f, 1.0f, 0.25f});

    setStatus(STATUS_EFFECT);
    setScanClass(CLASS_NO_DRAW);

    isImmuneToBreakPatternHide = true;
  }
}

oo::Ref<OOBreakPatternEntity>
OOBreakPatternEntity::breakPatternWithPolygonSides(NSUInteger sides,
                                                   float startAngleDegrees,
                                                   float aspectRatio) {
  const oo::Ref<OOBreakPatternEntity> ring =
      oo::makeRef<OOBreakPatternEntity>();
  ring->initWithPolygonSides(sides, startAngleDegrees, aspectRatio);
  return ring;
}

void OOBreakPatternEntity::setInnerColor(OOColor* color1, OOColor* color2) {
  // Messages to a nil colour did nothing: those components stay uninitialised,
  // as they did.
  GLfloat inner[4], outer[4];
  if (color1 != nullptr)
    color1->getRed(&inner[0], &inner[1], &inner[2], &inner[3]);
  if (color2 != nullptr)
    color2->getRed(&outer[0], &outer[1], &outer[2], &outer[3]);
  setInnerColorComponents(inner, outer);
}

void OOBreakPatternEntity::setInnerColorComponents(GLfloat color1[4],
                                                   GLfloat color2[4]) {
  GLfloat* colors[2] = {color1, color2};

  for (NSUInteger i = 0; i < _vertexCount; i++) {
    GLfloat* color = colors[i & 1];
    memcpy(&_vertexColor[i], color, sizeof(GLfloat) * 4);
  }
}

void OOBreakPatternEntity::setLifetime(double lifetime) {
  _lifetime = lifetime;
}

void OOBreakPatternEntity::update(OOTimeDelta delta_t) {
  Entity::update(delta_t);

  _lifetime -= BREAK_PATTERN_RING_SPEED * delta_t;
  if (_lifetime < 0.0) {
    if (UNIVERSE != nullptr) UNIVERSE->removeEntity(this);
  }
}

void OOBreakPatternEntity::drawImmediate(bool immediate, bool translucent) {
  // check if has been hidden.
  if (!isImmuneToBreakPatternHide) return;

  if (translucent || immediate) {
    OO_ENTER_OPENGL();
    OOSetOpenGLState(OPENGL_STATE_OPAQUE);

    OOGL(glDisable(GL_LIGHTING));
    OOGL(glDisable(GL_TEXTURE_2D));
    OOGL(glEnable(GL_BLEND));
    OOGL(glDepthMask(GL_FALSE));
    OOGL(glDisableClientState(GL_NORMAL_ARRAY));

    OOGL(glVertexPointer(3, GL_FLOAT, 0, _vertexPosition));
    OOGL(glEnableClientState(GL_COLOR_ARRAY));
    OOGL(glColorPointer(4, GL_FLOAT, 0, _vertexColor));

    OOGL(glDrawArrays(GL_TRIANGLE_STRIP, 0, _vertexCount));

    OOGL(glEnable(GL_LIGHTING));
    OOGL(glEnable(GL_TEXTURE_2D));
    OOGL(glDisable(GL_BLEND));
    OOGL(glDepthMask(GL_TRUE));
    OOGL(glEnableClientState(GL_NORMAL_ARRAY));
    OOGL(glDisableClientState(GL_COLOR_ARRAY));

    OOVerifyOpenGLState();
    cxx_OOCheckOpenGLErrors([&]() -> std::string {
      return "OOBreakPatternEntity after drawing " +
             oo::EntityDescription(this);
    });
  }
}

bool OOBreakPatternEntity::canCollide() { return false; }
