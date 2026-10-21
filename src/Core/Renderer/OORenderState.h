/*

OORenderState.h

Explicit render state for the renderer layer (issue #579).

Under SDL_GPU nothing is inherited from earlier drawing: each draw needs a
pipeline (blend, depth, cull and topology, fixed when it is created), its
textures with their samplers, and dynamic state such as the scissor rect.
OODrawState collects what the converted code needs, so draws can carry it.

Migrated code brackets its drawing with OORendererPushDrawState() and
OORendererPopDrawState(). Immediate-mode batches inside the scope use that
state and nothing else.

On the OpenGL backend, a push saves the GL state the fields cover and
applies the new values; a pop restores what was there. Code that still sets
GL state directly is therefore unaffected by migrated code, and the reverse.
Debug builds check at every batch that GL still matches the pushed state,
which catches migrated draws that still depend on, or are changed by,
legacy GL calls.


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

#ifndef OORENDERSTATE_H
#define OORENDERSTATE_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    // SDL_GPUColorTargetBlendState: blending disabled.
    kOOBlendOff,
    // SRC_ALPHA, ONE_MINUS_SRC_ALPHA: Oolite's standard translucency.
    kOOBlendAlpha,
    // SRC_ALPHA, ONE: glows and other additive effects.
    kOOBlendAdditive,
} OOBlendMode;

typedef struct {
    // Pipeline state: part of the SDL_GPU graphics pipeline key.
    OOBlendMode blend;
    bool depthTest; // SDL_GPUDepthStencilState.enable_depth_test, compare LESS
    bool depthWrite; // SDL_GPUDepthStencilState.enable_depth_write
    bool cullBack; // SDL_GPURasterizerState.cull_mode, front face CCW

    /*  Fixed-function state. On SDL_GPU these select the fixed-function
        emulation shader and fill its uniforms (OOGLSLLegacyStateBlock).
    */
    bool lighting;
    bool texture2D;
    bool fog;

    /*  Texture unit 0: an OOTexture, or NULL for none. On SDL_GPU the
        texture's options also give its SDL_GPUSampler. The caller keeps the
        texture alive while the state is pushed.
    */
    const void* texture;

    // Dynamic state: SDL_SetGPUScissor. Window co-ordinates, origin bottom left.
    bool scissor;
    int scissorRect[4]; // x, y, width, height
} OODrawState;

// The four OOSetOpenGLState() presets as draw states, with no texture.
typedef enum {
    kOODrawStateOpaque,
    kOODrawStateTranslucent,
    kOODrawStateAdditive,
    kOODrawStateOverlay,
} OODrawStatePreset;

OODrawState OODrawStateForPreset(OODrawStatePreset preset);

void OORendererPushDrawState(const OODrawState* state);
void OORendererPopDrawState(void);

// The innermost pushed state, or NULL outside any scope.
const OODrawState* OORendererCurrentDrawState(void);

/*  The innermost pushed state, or the preset outside any scope. For code
    that refines the state it is drawn in, such as text inside a scissored
    chart.
*/
OODrawState OORendererInheritedDrawState(OODrawStatePreset fallback);

#ifdef __cplusplus
}
#endif

#endif
