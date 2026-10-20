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

#include "OOFixedFunction.h"
#include "OOImmediateMode.h"
#include "OORenderPass.h"
#include "OORenderState.h"
#include "OORendererTexture.h"
#include "OOVertexArray.h"

#ifdef __cplusplus
extern "C" {
#endif

enum {
    kOORendererMaxDrawStateDepth = 16
};

// What an OORendererBuffer is on the OpenGL backend: the caller's memory.
struct OORendererBuffer {
    const void* data;
    size_t size;
};

void OORendererBackendDrawArrays(OONativePrimitive primitive, const OOVertexLayout* layout, size_t first, size_t count);
// indices points at count indices of indexType.
void OORendererBackendDrawElements(OONativePrimitive primitive, const OOVertexLayout* layout,
    const void* indices, OOIndexType indexType, size_t count);

// Draw expanded immediate-mode vertices with the current render state.
void OORendererBackendDrawImmediate(OONativePrimitive primitive, const OOImmediateVertex* vertices, size_t count);

/*  Apply a pushed draw state, keeping what it replaces in slot depth, and
    restore it again on pop.
*/
void OORendererBackendPushDrawState(const OODrawState* state, int depth);
void OORendererBackendPopDrawState(int depth);

// Logs once per message through rendering.renderer.
void OORendererBackendWarn(const char* message);

// Render targets (OORenderPass.h); descriptors are already validated.
OORenderTarget OORendererBackendCreateRenderTarget(const OORenderTargetDescriptor* descriptor);
void OORendererBackendResizeRenderTarget(OORenderTarget target, unsigned width, unsigned height);
uint32_t OORendererBackendRenderTargetTexture(OORenderTarget target, unsigned attachment);
void OORendererBackendResolveRenderTarget(OORenderTarget source, OORenderTarget destination);
void OORendererBackendDeleteRenderTarget(OORenderTarget target);

// Textures (OORendererTexture.h); descriptors are already validated.
uint32_t OORendererBackendCreateTexture(const OOTextureDescriptor* descriptor);
void OORendererBackendUploadTexture(uint32_t texture, unsigned face, unsigned level, unsigned width, unsigned height, const void* texels);
void OORendererBackendReadTexture(uint32_t texture, unsigned face, unsigned level, unsigned width, unsigned height, void* texels);
void OORendererBackendDeleteTexture(uint32_t texture);

// Debug builds: report where the context no longer matches state.
void OORendererBackendVerifyDrawState(const OODrawState* state);
// Debug builds: report where the context no longer matches the state machine.
void OORendererBackendVerifyStateMachine(void);

// Fixed-function values. Light positions are already in eye space.
void OORendererBackendSetLightColor(unsigned light, OOLightColor which, const float rgba[4]);
void OORendererBackendSetLightPosition(unsigned light, const float eyePosition[4]);
void OORendererBackendSetLightModelAmbient(const float rgba[4]);
void OORendererBackendSetMaterialColor(OOMaterialFace face, OOMaterialColor which, const float rgba[4]);
void OORendererBackendSetMaterialShininess(OOMaterialFace face, float shininess);
void OORendererBackendSetFog(const OOFogValues* fog);

// Passes. clearColor and clearDepth are the current clear values.
void OORendererBackendSetClearValues(const float clearColor[4], float clearDepth);
void OORendererBackendBeginPass(const OORenderPassDescriptor* pass, const float clearColor[4], float clearDepth);
void OORendererBackendEndPass(void);
void OORendererBackendReadPixels(int x, int y, int width, int height, OOPixelFormat format, void* pixels);

/*  Texture glue, in Objective-C (OORendererTexture.m). texture is an
    OOTexture or NULL. The save and restore pair covers the 2D binding and
    the LOD bias that -[OOTexture apply] sets.
*/
void OORendererBackendApplyTexture(const void* texture);
unsigned OORendererBackendTextureName(const void* texture);
void OORendererBackendSaveTexture(int depth);
void OORendererBackendRestoreTexture(int depth);

#if OO_IMMEDIATE_GL_INTEROP
// Read and write GL's current colour, texture co-ordinate and normal.
void OORendererBackendGetGLAttributes(OOImmediateAttributes* outAttributes);
void OORendererBackendSetGLAttributes(const OOImmediateAttributes* attributes);
// Report legacy GL code that changed the current colour inside a batch;
// expected is GL's colour when the batch began.
void OORendererBackendCheckGLAttributes(const OOImmediateAttributes* expected);
#endif

#ifdef __cplusplus
}
#endif

#endif
