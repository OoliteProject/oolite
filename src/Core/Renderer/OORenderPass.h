/*

OORenderPass.h

Render passes and readback for the renderer layer (issue #579).

SDL_GPU draws only inside render passes, and a pass fixes its targets.
Clearing is a load operation at the start of a pass, so a clear in the
middle of a frame (Oolite clears depth between its near and far passes)
ends one pass and begins the next. Reading pixels back is a download after
the pass. OORendererBeginPass()/OORendererEndPass() mark these boundaries.

The clear colour and depth are state, set with OORendererSetClearColor()
and OORendererSetClearDepth() as glClearColor() was. A pass that clears
uses whatever was set last.

On the OpenGL backend, a pass binds its framebuffer (unless the target is
kOORenderTargetCurrent) and clears what it is asked to. Depth writes are
enabled for the clear and then restored.


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

#ifndef OORENDERPASS_H
#define OORENDERPASS_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    kOOLoadKeep, // SDL_GPU_LOADOP_LOAD
    kOOLoadClear, // SDL_GPU_LOADOP_CLEAR, with the current clear value
    kOOLoadDontCare, // SDL_GPU_LOADOP_DONT_CARE
} OOLoadOp;

/*  A render target. On OpenGL, a framebuffer object name (0 for the
    window). Under SDL_GPU this becomes the colour and depth textures, plus
    a resolve texture for multisampled targets (resolving is a store op
    there, where GL uses glBlitFramebuffer).
*/
typedef uint32_t OORenderTarget;
#define kOORenderTargetCurrent ((OORenderTarget)0xFFFFFFFFu) // whatever GL has bound

typedef struct {
    OORenderTarget target;
    OOLoadOp colorLoad;
    OOLoadOp depthLoad;
} OORenderPassDescriptor;

/*  Offscreen render targets. Colour attachments are RGBA16F, filtered
    linearly and clamped to the edge; depth is 32-bit float. A multisampled
    target can't be sampled, only resolved into a single-sampled one. All of
    a target's attachments are cleared or loaded together.
*/
typedef struct {
    unsigned width, height;
    unsigned colorAttachments; // 0 to kOOMaxColorAttachments
    bool depth;
    unsigned samples; // 1, or 4 for MSAA
} OORenderTargetDescriptor;

enum {
    kOOMaxColorAttachments = 2
};

// Returns 0 on failure.
OORenderTarget OORendererCreateRenderTarget(const OORenderTargetDescriptor* descriptor);
// Keeps the contents undefined. Outside a pass.
void OORendererResizeRenderTarget(OORenderTarget target, unsigned width, unsigned height);
/*  A colour attachment as a texture for OOGLBindTexture, or 0 for a
    multisampled target. SDL_GPU replaces the texture on resize, so look it
    up each time rather than keeping it.
*/
uint32_t OORendererRenderTargetTexture(OORenderTarget target, unsigned attachment);
// Resolve (or copy) colour attachment 0 of source into destination, which has the same size. Outside a pass.
void OORendererResolveRenderTarget(OORenderTarget source, OORenderTarget destination);
void OORendererDeleteRenderTarget(OORenderTarget target);

/*  The window's own target. On OpenGL, the framebuffer bound when the
    window's context was set up, which isn't always 0.
*/
void OORendererSetWindowTarget(OORenderTarget target);
OORenderTarget OORendererWindowTarget(void);

void OORendererSetClearColor(float r, float g, float b, float a);
void OORendererSetClearDepth(float depth);

void OORendererBeginPass(const OORenderPassDescriptor* pass);
void OORendererEndPass(void);
// For exception paths: ends the pass if one is open.
void OORendererEndPassIfActive(void);
bool OORendererInPass(void);
// The target of the open pass, or kOORenderTargetCurrent.
OORenderTarget OORendererCurrentPassTarget(void);

typedef enum {
    kOOPixelsBGRA8, // 8 bits per channel, BGRA order
    kOOPixelsRGBFloat, // 32-bit float per channel
} OOPixelFormat;

/*  Read back a rectangle of the current read framebuffer, bottom-up rows
    as in GL. Outside a pass. Under SDL_GPU, a texture download.
*/
void OORendererReadPixels(int x, int y, int width, int height, OOPixelFormat format, void* pixels);

// Wait until the GPU has finished all submitted work (glFinish).
void OORendererFinish(void);
// Start submitted work without waiting for it (glFlush).
void OORendererFlush(void);

#ifdef __cplusplus
}
#endif

#endif
