/*

OOVertexArray.c


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

#include "OOVertexArray.h"
#include "OORendererBackend.h"

#include <assert.h>
#include <stdbool.h>
#include <stdlib.h>

OORendererBuffer* OORendererCreateBuffer(const void* data, size_t size)
{
    OORendererBuffer* buffer = calloc(1, sizeof *buffer);
    if (buffer != NULL) {
        buffer->data = data;
        buffer->size = size;
    }
    return buffer;
}

void OORendererReleaseBuffer(OORendererBuffer* buffer)
{
    free(buffer);
}

void OOVertexLayoutAdd(OOVertexLayout* layout, OOVertexSemantic semantic, unsigned index, unsigned components,
    unsigned stride, const OORendererBuffer* buffer, size_t offset)
{
    assert(layout->count < kOOMaxVertexStreams);
    if (layout->count >= kOOMaxVertexStreams)
        return;
    layout->streams[layout->count++] = (OOVertexStream) {
        .semantic = semantic,
        .index = index,
        .components = components,
        .stride = stride,
        .buffer = buffer,
        .offset = offset,
    };
}

static void VerifyState(void)
{
#ifndef NDEBUG
    const OODrawState* state = OORendererCurrentDrawState();
    if (state != NULL)
        OORendererBackendVerifyDrawState(state);
#endif
}

enum {
    kTransientBuffers = 4096
};
static OORendererBuffer sTransient[kTransientBuffers];
static unsigned sNextTransient = 0;

const OORendererBuffer* OORendererTransientBuffer(const void* data, size_t size)
{
    // On OpenGL these are only borrowed pointers, so a ring is enough.
    OORendererBuffer* buffer = &sTransient[sNextTransient++ % kTransientBuffers];
    buffer->data = data;
    buffer->size = size;
    return buffer;
}

void OORendererDrawArrays(OONativePrimitive primitive, const OOVertexLayout* layout, size_t first, size_t count)
{
    VerifyState();
    if (count > 0)
        OORendererBackendDrawArrays(primitive, layout, first, count);
}

void OORendererDrawElements(OONativePrimitive primitive, const OOVertexLayout* layout,
    const OORendererBuffer* indexBuffer, size_t offset, OOIndexType indexType, size_t count)
{
    VerifyState();
    if (count > 0)
        OORendererBackendDrawElements(primitive, layout, (const char*)indexBuffer->data + offset, indexType, count);
}

static uint32_t* sExpanded = NULL;
static size_t sExpandedCapacity = 0;

static uint32_t* ExpandedScratch(size_t needed)
{
    if (needed > sExpandedCapacity) {
        size_t capacity = sExpandedCapacity ? sExpandedCapacity : 1024;
        while (capacity < needed)
            capacity *= 2;
        uint32_t* grown = realloc(sExpanded, capacity * sizeof *grown);
        if (grown == NULL)
            return NULL;
        sExpanded = grown;
        sExpandedCapacity = capacity;
    }
    return sExpanded;
}

static bool IsNative(OOPrimitive primitive)
{
    return primitive == kOOPrimitivePoints || primitive == kOOPrimitiveLines || primitive == kOOPrimitiveLineStrip
        || primitive == kOOPrimitiveTriangles || primitive == kOOPrimitiveTriangleStrip;
}

void OORendererDrawPrimitive(OOPrimitive primitive, const OOVertexLayout* layout, size_t first, size_t count)
{
    if (IsNative(primitive)) {
        OORendererDrawArrays(OONativePrimitiveFor(primitive), layout, first, count);
        return;
    }
    size_t n = OOExpandedVertexCount(primitive, count);
    uint32_t* indices = ExpandedScratch(n);
    if (n == 0 || indices == NULL)
        return;
    OOExpandPrimitiveIndices(primitive, NULL, first, count, indices);
    VerifyState();
    OORendererBackendDrawElements(OONativePrimitiveFor(primitive), layout, indices, kOOIndex32, n);
}

void OORendererDrawPrimitiveElements(OOPrimitive primitive, const OOVertexLayout* layout,
    const OORendererBuffer* indexBuffer, size_t offset, OOIndexType indexType, size_t count)
{
    if (IsNative(primitive)) {
        OORendererDrawElements(OONativePrimitiveFor(primitive), layout, indexBuffer, offset, indexType, count);
        return;
    }
    size_t n = OOExpandedVertexCount(primitive, count);
    uint32_t* expanded = ExpandedScratch(n + count);
    if (n == 0 || expanded == NULL)
        return;
    // Widen the caller's indices after the expanded ones, then expand.
    uint32_t* source = expanded + n;
    const char* raw = (const char*)indexBuffer->data + offset;
    for (size_t i = 0; i < count; i++)
        source[i] = indexType == kOOIndex16 ? ((const uint16_t*)raw)[i] : ((const uint32_t*)raw)[i];
    OOExpandPrimitiveIndices(primitive, source, 0, count, expanded);
    VerifyState();
    OORendererBackendDrawElements(OONativePrimitiveFor(primitive), layout, expanded, kOOIndex32, n);
}
