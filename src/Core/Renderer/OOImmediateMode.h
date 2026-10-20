/*

OOImmediateMode.h

Replacement for OpenGL immediate mode (glBegin/glVertex/glEnd), as the first
part of the renderer layer for the move to SDL_GPU (issue #579).

Vertices are collected with the same "current attribute" semantics as GL
immediate mode: each vertex takes the current colour, texture co-ordinate and
normal. At OOImmediateEnd() the primitive is expanded into one SDL_GPU can
draw (points, lines, line strips, triangles or triangle strips) and handed to
the renderer backend. Quads, quad strips, polygons, triangle fans and line
loops are therefore expanded here, in shared code, so the expansion is
exercised by the OpenGL backend too. The expansion keeps GL's winding and
its flat-shading provoking vertex.

Transitional OpenGL interoperation: until every caller has moved over, code
that still uses raw GL runs between immediate-mode draws. The attribute
setters therefore also set the GL current values, and OOImmediateBegin()
picks up values set directly through GL since the last draw. This is
compiled in when OO_IMMEDIATE_GL_INTEROP is non-zero, and goes away when the
SDL_GPU backend arrives.


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

#ifndef OOIMMEDIATEMODE_H
#define OOIMMEDIATEMODE_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef OO_IMMEDIATE_GL_INTEROP
#define OO_IMMEDIATE_GL_INTEROP 1
#endif

// Primitive types accepted by OOImmediateBegin(), matching GL immediate mode.
typedef enum {
    kOOPrimitivePoints,
    kOOPrimitiveLines,
    kOOPrimitiveLineStrip,
    kOOPrimitiveLineLoop,
    kOOPrimitiveTriangles,
    kOOPrimitiveTriangleStrip,
    kOOPrimitiveTriangleFan,
    kOOPrimitiveQuads,
    kOOPrimitiveQuadStrip,
    kOOPrimitivePolygon,
    kOOPrimitiveCount
} OOPrimitive;

// Primitive types every backend can draw (SDL_GPUPrimitiveType's set).
typedef enum {
    kOONativePrimitivePoints,
    kOONativePrimitiveLines,
    kOONativePrimitiveLineStrip,
    kOONativePrimitiveTriangles,
    kOONativePrimitiveTriangleStrip,
} OONativePrimitive;

typedef struct {
    float color[4];
    float texCoord[2];
    float normal[3];
} OOImmediateAttributes;

typedef struct {
    float position[3];
    float color[4];
    float texCoord[2];
    float normal[3];
} OOImmediateVertex;

void OOImmediateBegin(OOPrimitive primitive);
void OOImmediateEnd(void);

void OOImmediateVertex2f(float x, float y);
void OOImmediateVertex3f(float x, float y, float z);
void OOImmediateVertex3fv(const float* v);

void OOImmediateColor3f(float r, float g, float b);
void OOImmediateColor4f(float r, float g, float b, float a);
void OOImmediateColor4fv(const float* rgba);
void OOImmediateTexCoord2f(float s, float t);
void OOImmediateNormal3f(float x, float y, float z);

/*  The current attributes, replacing glGetFloatv(GL_CURRENT_COLOR, ...) and
    glPushAttrib(GL_CURRENT_BIT)/glPopAttrib(). Not valid between Begin and
    End.
*/
OOImmediateAttributes OOImmediateGetAttributes(void);
void OOImmediateSetAttributes(OOImmediateAttributes attributes);

/*  Primitive expansion, exposed for the backends and for testing.
    OOExpandedVertexCount() returns the number of vertices OOExpandPrimitive()
    will write for count input vertices. Incomplete trailing primitives are
    dropped, as GL does.
*/
OONativePrimitive OONativePrimitiveFor(OOPrimitive primitive);
size_t OOExpandedVertexCount(OOPrimitive primitive, size_t count);
size_t OOExpandPrimitive(OOPrimitive primitive, const OOImmediateVertex* in, size_t count, OOImmediateVertex* out);

#ifdef __cplusplus
}
#endif

#endif
