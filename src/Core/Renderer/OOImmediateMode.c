/*

OOImmediateMode.c


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

#include "OOImmediateMode.h"
#include "OORendererBackend.h"

#include <assert.h>
#include <stdlib.h>
#include <string.h>

static OOImmediateAttributes sCurrent = {
    .color = { 1.0f, 1.0f, 1.0f, 1.0f },
    .normal = { 0.0f, 0.0f, 1.0f },
};

static OOPrimitive sPrimitive;
static bool sInBatch = false;

// Vertices of the current batch, and the expanded copy handed to the backend.
static OOImmediateVertex* sVertices = NULL;
static size_t sVertexCount = 0, sVertexCapacity = 0;
static OOImmediateVertex* sExpanded = NULL;
static size_t sExpandedCapacity = 0;

static bool Reserve(OOImmediateVertex** buffer, size_t* capacity, size_t needed)
{
    if (needed <= *capacity)
        return true;
    size_t newCapacity = *capacity ? *capacity : 256;
    while (newCapacity < needed)
        newCapacity *= 2;
    OOImmediateVertex* grown = realloc(*buffer, newCapacity * sizeof **buffer);
    if (grown == NULL)
        return false;
    *buffer = grown;
    *capacity = newCapacity;
    return true;
}

#pragma mark - Attributes

#if OO_IMMEDIATE_GL_INTEROP
/*  Keep GL's current values equal to ours between batches, so legacy code
    sees them. Inside a batch GL is left alone: OOImmediateEnd() syncs it,
    and checks it is unchanged to spot legacy glColor calls in the batch.
*/
static OOImmediateAttributes sGLAtBegin;
#define PUSH_TO_GL()                                     \
    do {                                                 \
        if (!sInBatch)                                   \
            OORendererBackendSetGLAttributes(&sCurrent); \
    } while (0)
#else
#define PUSH_TO_GL() \
    do {             \
    } while (0)
#endif

void OOImmediateColor3f(float r, float g, float b)
{
    OOImmediateColor4f(r, g, b, 1.0f);
}

void OOImmediateColor4f(float r, float g, float b, float a)
{
    sCurrent.color[0] = r;
    sCurrent.color[1] = g;
    sCurrent.color[2] = b;
    sCurrent.color[3] = a;
    PUSH_TO_GL();
}

void OOImmediateColor4fv(const float* rgba)
{
    OOImmediateColor4f(rgba[0], rgba[1], rgba[2], rgba[3]);
}

void OOImmediateTexCoord2f(float s, float t)
{
    sCurrent.texCoord[0] = s;
    sCurrent.texCoord[1] = t;
    PUSH_TO_GL();
}

void OOImmediateNormal3f(float x, float y, float z)
{
    sCurrent.normal[0] = x;
    sCurrent.normal[1] = y;
    sCurrent.normal[2] = z;
    PUSH_TO_GL();
}

OOImmediateAttributes OOImmediateGetAttributes(void)
{
    assert(!sInBatch);
#if OO_IMMEDIATE_GL_INTEROP
    OORendererBackendGetGLAttributes(&sCurrent);
#endif
    return sCurrent;
}

void OOImmediateSetAttributes(OOImmediateAttributes attributes)
{
    assert(!sInBatch);
    sCurrent = attributes;
    PUSH_TO_GL();
}

#pragma mark - Vertices

void OOImmediateBegin(OOPrimitive primitive)
{
    assert(!sInBatch && primitive < kOOPrimitiveCount);
#if OO_IMMEDIATE_GL_INTEROP
    // Pick up anything legacy code set through GL since the last draw.
    OORendererBackendGetGLAttributes(&sCurrent);
    sGLAtBegin = sCurrent;
#endif
    sPrimitive = primitive;
    sVertexCount = 0;
    sInBatch = true;
}

void OOImmediateVertex3f(float x, float y, float z)
{
    assert(sInBatch);
    if (!Reserve(&sVertices, &sVertexCapacity, sVertexCount + 1))
        return;
    OOImmediateVertex* v = &sVertices[sVertexCount++];
    v->position[0] = x;
    v->position[1] = y;
    v->position[2] = z;
    memcpy(v->color, sCurrent.color, sizeof v->color);
    memcpy(v->texCoord, sCurrent.texCoord, sizeof v->texCoord);
    memcpy(v->normal, sCurrent.normal, sizeof v->normal);
}

void OOImmediateVertex2f(float x, float y)
{
    OOImmediateVertex3f(x, y, 0.0f);
}

void OOImmediateVertex3fv(const float* v)
{
    OOImmediateVertex3f(v[0], v[1], v[2]);
}

void OOImmediateEnd(void)
{
    assert(sInBatch);
    sInBatch = false;
#if OO_IMMEDIATE_GL_INTEROP
    OORendererBackendCheckGLAttributes(&sGLAtBegin);
#endif
#ifndef NDEBUG
    const OODrawState* state = OORendererCurrentDrawState();
    if (state != NULL)
        OORendererBackendVerifyDrawState(state);
#endif

    size_t count = OOExpandedVertexCount(sPrimitive, sVertexCount);
    if (count > 0 && Reserve(&sExpanded, &sExpandedCapacity, count)) {
        OOExpandPrimitive(sPrimitive, sVertices, sVertexCount, sExpanded);
        OORendererBackendDrawImmediate(OONativePrimitiveFor(sPrimitive), sExpanded, count);
    }
#if OO_IMMEDIATE_GL_INTEROP
    // Vertex arrays leave GL's current attributes undefined.
    OORendererBackendSetGLAttributes(&sCurrent);
#endif
}

#pragma mark - Primitive expansion

OONativePrimitive OONativePrimitiveFor(OOPrimitive primitive)
{
    switch (primitive) {
    case kOOPrimitivePoints:
        return kOONativePrimitivePoints;
    case kOOPrimitiveLines:
        return kOONativePrimitiveLines;
    case kOOPrimitiveLineStrip:
    case kOOPrimitiveLineLoop:
        return kOONativePrimitiveLineStrip;
    case kOOPrimitiveTriangleStrip:
        return kOONativePrimitiveTriangleStrip;
    default:
        return kOONativePrimitiveTriangles;
    }
}

size_t OOExpandedVertexCount(OOPrimitive primitive, size_t count)
{
    switch (primitive) {
    case kOOPrimitivePoints:
        return count;
    case kOOPrimitiveLines:
        return count - count % 2;
    case kOOPrimitiveLineStrip:
        return count >= 2 ? count : 0;
    case kOOPrimitiveLineLoop:
        return count >= 2 ? count + 1 : 0;
    case kOOPrimitiveTriangles:
        return count - count % 3;
    case kOOPrimitiveTriangleStrip:
        return count >= 3 ? count : 0;
    case kOOPrimitiveTriangleFan:
    case kOOPrimitivePolygon:
        return count >= 3 ? 3 * (count - 2) : 0;
    case kOOPrimitiveQuads:
        return (count / 4) * 6;
    case kOOPrimitiveQuadStrip:
        return count >= 4 ? ((count - 2) / 2) * 6 : 0;
    case kOOPrimitiveCount:
        break;
    }
    return 0;
}

/*  Triangles are emitted so that each keeps the winding of the original
    primitive and ends with GL's provoking vertex for flat shading: the last
    vertex of each quad (quads and quad strips), the first vertex (polygons)
    and the last vertex of each triangle (fans).
*/
size_t OOExpandPrimitive(OOPrimitive primitive, const OOImmediateVertex* in, size_t count, OOImmediateVertex* out)
{
    size_t n = OOExpandedVertexCount(primitive, count);
    size_t o = 0;
#define EMIT(index) (out[o++] = in[(index)])

    switch (primitive) {
    case kOOPrimitivePoints:
    case kOOPrimitiveLines:
    case kOOPrimitiveLineStrip:
    case kOOPrimitiveTriangles:
    case kOOPrimitiveTriangleStrip:
        memcpy(out, in, n * sizeof *out);
        o = n;
        break;

    case kOOPrimitiveLineLoop:
        if (n > 0) {
            memcpy(out, in, count * sizeof *out);
            o = count;
            EMIT(0);
        }
        break;

    case kOOPrimitiveTriangleFan:
        for (size_t i = 1; i + 1 < count; i++) {
            EMIT(0);
            EMIT(i);
            EMIT(i + 1);
        }
        break;

    case kOOPrimitivePolygon:
        for (size_t i = 1; i + 1 < count; i++) {
            EMIT(i);
            EMIT(i + 1);
            EMIT(0);
        }
        break;

    case kOOPrimitiveQuads:
        for (size_t q = 0; q + 3 < count; q += 4) {
            EMIT(q);
            EMIT(q + 1);
            EMIT(q + 3);
            EMIT(q + 1);
            EMIT(q + 2);
            EMIT(q + 3);
        }
        break;

    case kOOPrimitiveQuadStrip:
        // Quad i is 2i, 2i+1, 2i+3, 2i+2 in winding order.
        for (size_t i = 0; 2 * i + 3 < count; i++) {
            EMIT(2 * i);
            EMIT(2 * i + 1);
            EMIT(2 * i + 3);
            EMIT(2 * i + 2);
            EMIT(2 * i);
            EMIT(2 * i + 3);
        }
        break;

    case kOOPrimitiveCount:
        break;
    }
#undef EMIT
    assert(o == n);
    return o;
}
