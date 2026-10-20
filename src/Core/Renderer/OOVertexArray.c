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

void OORendererDrawArrays(OONativePrimitive primitive, const OOVertexLayout* layout, size_t first, size_t count)
{
#ifndef NDEBUG
    const OODrawState* state = OORendererCurrentDrawState();
    if (state != NULL)
        OORendererBackendVerifyDrawState(state);
#endif
    if (count > 0)
        OORendererBackendDrawArrays(primitive, layout, first, count);
}
