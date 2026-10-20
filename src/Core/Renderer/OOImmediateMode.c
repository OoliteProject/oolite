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
#include <math.h>
#include <stdlib.h>
#include <string.h>

static OOImmediateAttributes sCurrent = {
    .color = { 1.0f, 1.0f, 1.0f, 1.0f },
    .normal = { 0.0f, 0.0f, 1.0f },
};

static OOPrimitive sPrimitive;
static bool sInBatch = false;
static float sLineWidth = 1.0f, sPointSize = 1.0f;
static float sBatchLineWidth = 1.0f, sBatchPointSize = 1.0f;

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
    sBatchLineWidth = sLineWidth;
    sBatchPointSize = sPointSize;
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

#pragma mark - Line width and point size

void OOImmediateSetLineWidth(float pixels)
{
    sLineWidth = pixels;
}

void OOImmediateSetPointSize(float pixels)
{
    sPointSize = pixels;
}

float OOImmediateLineWidth(void)
{
    return sLineWidth;
}

float OOImmediatePointSize(void)
{
    return sPointSize;
}

float OOImmediateBatchLineWidth(void)
{
    return sBatchLineWidth;
}

float OOImmediateBatchPointSize(void)
{
    return sBatchPointSize;
}

#pragma mark - Wide line and point expansion

enum {
    kSmoothPointSegments = 16
};

static void Transform(const float* m, const float* p, float* out)
{
    for (int row = 0; row < 4; row++)
        out[row] = m[row] * p[0] + m[4 + row] * p[1] + m[8 + row] * p[2] + m[12 + row];
}

static void Lerp(const float* a, const float* b, float t, float* out, int n)
{
    for (int i = 0; i < n; i++)
        out[i] = a[i] + (b[i] - a[i]) * t;
}

// A vertex at window position (x, y) and NDC depth z, with interpolated attributes.
static void Emit(OOImmediateVertex* out, const OOImmediateVertex* a, const OOImmediateVertex* b, float t,
    float x, float y, float z, const float* viewport)
{
    *out = *a;
    if (b != NULL && t != 0.0f) {
        Lerp(a->color, b->color, t, out->color, 4);
        Lerp(a->texCoord, b->texCoord, t, out->texCoord, 2);
        Lerp(a->normal, b->normal, t, out->normal, 3);
    }
    out->position[0] = (x - viewport[0]) / viewport[2] * 2.0f - 1.0f;
    out->position[1] = (y - viewport[1]) / viewport[3] * 2.0f - 1.0f;
    out->position[2] = z;
}

static void ToWindow(const float* clip, const float* viewport, float* x, float* y, float* z)
{
    *x = (clip[0] / clip[3] * 0.5f + 0.5f) * viewport[2] + viewport[0];
    *y = (clip[1] / clip[3] * 0.5f + 0.5f) * viewport[3] + viewport[1];
    *z = clip[2] / clip[3];
}

static size_t ExpandSegment(const OOImmediateVertex* va, const OOImmediateVertex* vb, float width, bool smooth,
    const float* mvp, const float* viewport, OOImmediateVertex* out)
{
    float ca[4], cb[4];
    Transform(mvp, va->position, ca);
    Transform(mvp, vb->position, cb);

    // Clip to the near plane, z >= -w.
    float da = ca[2] + ca[3], db = cb[2] + cb[3];
    if (da < 0 && db < 0)
        return 0;
    float ta = 0, tb = 1;
    if (da < 0)
        ta = da / (da - db);
    else if (db < 0)
        tb = da / (da - db);
    float pa[4], pb[4];
    Lerp(ca, cb, ta, pa, 4);
    Lerp(ca, cb, tb, pb, 4);

    float ax, ay, az, bx, by, bz;
    ToWindow(pa, viewport, &ax, &ay, &az);
    ToWindow(pb, viewport, &bx, &by, &bz);
    float dx = bx - ax, dy = by - ay;
    float ox, oy;
    if (smooth) {
        float length = sqrtf(dx * dx + dy * dy);
        if (length == 0)
            return 0;
        ox = -dy / length * width * 0.5f;
        oy = dx / length * width * 0.5f;
    } else if (fabsf(dx) >= fabsf(dy)) {
        // x-major: GL sweeps the line vertically.
        ox = 0;
        oy = width * 0.5f;
    } else {
        ox = width * 0.5f;
        oy = 0;
    }

    OOImmediateVertex corners[4];
    Emit(&corners[0], va, vb, ta, ax - ox, ay - oy, az, viewport);
    Emit(&corners[1], va, vb, tb, bx - ox, by - oy, bz, viewport);
    Emit(&corners[2], va, vb, tb, bx + ox, by + oy, bz, viewport);
    Emit(&corners[3], va, vb, ta, ax + ox, ay + oy, az, viewport);
    static const int kOrder[6] = { 0, 1, 2, 0, 2, 3 };
    for (int i = 0; i < 6; i++)
        out[i] = corners[kOrder[i]];
    return 6;
}

size_t OOExpandLinesCapacity(OONativePrimitive primitive, size_t count)
{
    size_t segments = primitive == kOONativePrimitiveLineStrip ? (count > 0 ? count - 1 : 0) : count / 2;
    return segments * 6;
}

size_t OOExpandLinesToTriangles(OONativePrimitive primitive, const OOImmediateVertex* in, size_t count, float width, bool smooth,
    const float* modelViewProjection, const float* viewport, OOImmediateVertex* out)
{
    size_t o = 0;
    size_t step = primitive == kOONativePrimitiveLineStrip ? 1 : 2;
    for (size_t i = 0; i + 1 < count; i += step)
        o += ExpandSegment(&in[i], &in[i + 1], width, smooth, modelViewProjection, viewport, out + o);
    return o;
}

size_t OOExpandPointsCapacity(size_t count, bool smooth)
{
    return count * (smooth ? 3 * kSmoothPointSegments : 6);
}

size_t OOExpandPointsToTriangles(const OOImmediateVertex* in, size_t count, float size, bool smooth,
    const float* modelViewProjection, const float* viewport, OOImmediateVertex* out)
{
    size_t o = 0;
    float r = size * 0.5f;
    for (size_t i = 0; i < count; i++) {
        float c[4], x, y, z;
        Transform(modelViewProjection, in[i].position, c);
        if (c[2] + c[3] < 0 || c[3] <= 0)
            continue;
        ToWindow(c, viewport, &x, &y, &z);
        if (smooth) {
            for (int k = 0; k < kSmoothPointSegments; k++) {
                float a0 = (float)k / kSmoothPointSegments * 6.2831853f;
                float a1 = (float)(k + 1) / kSmoothPointSegments * 6.2831853f;
                Emit(&out[o++], &in[i], NULL, 0, x, y, z, viewport);
                Emit(&out[o++], &in[i], NULL, 0, x + r * cosf(a0), y + r * sinf(a0), z, viewport);
                Emit(&out[o++], &in[i], NULL, 0, x + r * cosf(a1), y + r * sinf(a1), z, viewport);
            }
        } else {
            // GL's square point covers [x - r, x + r) on each axis.
            OOImmediateVertex corners[4];
            Emit(&corners[0], &in[i], NULL, 0, x - r, y - r, z, viewport);
            Emit(&corners[1], &in[i], NULL, 0, x + r, y - r, z, viewport);
            Emit(&corners[2], &in[i], NULL, 0, x + r, y + r, z, viewport);
            Emit(&corners[3], &in[i], NULL, 0, x - r, y + r, z, viewport);
            static const int kOrder[6] = { 0, 1, 2, 0, 2, 3 };
            for (int k = 0; k < 6; k++)
                out[o++] = corners[kOrder[k]];
        }
    }
    return o;
}
