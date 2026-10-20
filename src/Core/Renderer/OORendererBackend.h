/*

OORendererBackend.h

Functions each renderer backend implements for the shared renderer code.
Only the OpenGL backend (OORendererGL.c) exists for now; the SDL_GPU backend
follows in phase 3 of issue #579.


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

#ifndef OORENDERERBACKEND_H
#define OORENDERERBACKEND_H

#include "OOImmediateMode.h"

#ifdef __cplusplus
extern "C" {
#endif

// Draw expanded immediate-mode vertices with the current render state.
void OORendererBackendDrawImmediate(OONativePrimitive primitive, const OOImmediateVertex* vertices, size_t count);

#if OO_IMMEDIATE_GL_INTEROP
// Read and write GL's current colour, texture co-ordinate and normal.
void OORendererBackendGetGLAttributes(OOImmediateAttributes* outAttributes);
void OORendererBackendSetGLAttributes(const OOImmediateAttributes* attributes);
// Report legacy GL code that changed the current colour inside a batch.
void OORendererBackendCheckGLAttributes(const OOImmediateAttributes* expected);
#endif

#ifdef __cplusplus
}
#endif

#endif
