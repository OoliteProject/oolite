/*

OOVertexArray.h

Vertex-array drawing for the renderer layer (issue #579).

SDL_GPU draws from GPU buffers, described by a vertex layout that is part of
the pipeline. Code that draws arrays of vertices therefore creates its
buffers once, with OORendererCreateBuffer(), and describes each draw with an
OOVertexLayout of streams into them.

The OpenGL backend keeps buffers in client memory (vertex buffer objects are
off in Oolite, see OO_USE_VBO) and draws exactly as the code did before. It
saves and restores the vertex-array state it touches, so legacy code
around a draw is unaffected.


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

#ifndef OOVERTEXARRAY_H
#define OOVERTEXARRAY_H

#include "OOImmediateMode.h"

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*  A block of vertex data. Under SDL_GPU this is an SDL_GPUBuffer, uploaded
    when it is created; on OpenGL it refers to the caller's memory, which
    must stay valid and unchanged until the buffer is released.
*/
typedef struct OORendererBuffer OORendererBuffer;

OORendererBuffer* OORendererCreateBuffer(const void* data, size_t size);
void OORendererReleaseBuffer(OORendererBuffer* buffer);

typedef enum {
    kOOVertexPosition, // gl_Vertex
    kOOVertexNormal, // gl_Normal; always three components
    kOOVertexColor, // gl_Color
    kOOVertexTexCoord, // gl_MultiTexCoord<index>
    kOOVertexAttribute, // generic attribute at location index, such as "tangent"
} OOVertexSemantic;

typedef struct {
    OOVertexSemantic semantic;
    unsigned index; // texture unit or attribute location
    unsigned components; // 1-4 floats
    unsigned stride; // bytes between vertices; 0 for tightly packed
    const OORendererBuffer* buffer;
    size_t offset; // bytes into the buffer
} OOVertexStream;

enum {
    kOOMaxVertexStreams = 12
};

typedef struct {
    OOVertexStream streams[kOOMaxVertexStreams];
    unsigned count;
} OOVertexLayout;

void OOVertexLayoutAdd(OOVertexLayout* layout, OOVertexSemantic semantic, unsigned index, unsigned components,
    unsigned stride, const OORendererBuffer* buffer, size_t offset);

// Draw count vertices from first, with the current render state.
void OORendererDrawArrays(OONativePrimitive primitive, const OOVertexLayout* layout, size_t first, size_t count);

#ifdef __cplusplus
}
#endif

#endif
