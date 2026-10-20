/*

OORenderStateMachine.h

The renderer's copy of the OpenGL state machine, for the move to SDL_GPU
(issue #579).

Legacy code sets state as it always has, one call at a time, through the
OOGL* wrappers in OOGLStateCompat.h. Those record the state here as well as
passing it to GL. The SDL_GPU backend builds each draw's pipeline (blend,
depth, cull), fixed-function emulation and texture bindings from it. Debug
builds compare GL with this copy at every draw (OORendererVerifyStateMachine)
to catch GL calls that bypass the wrappers.

Pushed draw states (OORenderState.h) are applied through this state machine
too, so the two stay consistent.


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

#ifndef OORENDERSTATEMACHINE_H
#define OORENDERSTATEMACHINE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    kOOMaxTextureUnits = 8,
    kOOMaxStateLights = 8,
};

// Capabilities that apply to the whole context.
typedef enum {
    kOOCapBlend,
    kOOCapDepthTest,
    kOOCapCullFace,
    kOOCapLighting,
    kOOCapFog,
    kOOCapColorMaterial,
    kOOCapScissorTest,
    kOOCapPointSprite,
    kOOCapLineSmooth,
    kOOCapPointSmooth,
    kOOCapNormalize,
    kOOCapRescaleNormal,
    kOOCapCount
} OOCapability;

// Blend factors used by Oolite.
typedef enum {
    kOOBlendFactorZero,
    kOOBlendFactorOne,
    kOOBlendFactorSrcAlpha,
    kOOBlendFactorOneMinusSrcAlpha,
    kOOBlendFactorDstColor,
    kOOBlendFactorOneMinusSrcColor,
    kOOBlendFactorSrcColor,
    kOOBlendFactorOther,
} OOBlendFactor;

typedef enum {
    kOOCompareNever,
    kOOCompareLess,
    kOOCompareEqual,
    kOOCompareLessOrEqual,
    kOOCompareGreater,
    kOOCompareNotEqual,
    kOOCompareGreaterOrEqual,
    kOOCompareAlways,
} OOCompareOp;

typedef enum {
    kOOCullBack,
    kOOCullFront,
    kOOCullFrontAndBack,
} OOCullFace;

typedef enum {
    kOOTexEnvModulate,
    kOOTexEnvReplace,
    kOOTexEnvDecal,
    kOOTexEnvBlend,
    kOOTexEnvAdd,
    kOOTexEnvCombine,
} OOTexEnvMode;

typedef struct {
    bool texture2D, textureCube; // enables
    uint32_t binding2D, bindingCube; // texture names on OpenGL
    OOTexEnvMode envMode;
    float envColor[4];
} OOTextureUnitState;

typedef struct {
    bool caps[kOOCapCount];
    bool lights[kOOMaxStateLights];
    OOBlendFactor blendSrc, blendDst;
    bool depthMask;
    OOCompareOp depthFunc;
    OOCullFace cullFace;
    bool frontFaceCCW;
    bool flatShading;
    bool wireframe; // polygon mode
    int scissor[4];
    unsigned activeTexture;
    OOTextureUnitState units[kOOMaxTextureUnits];
    uint32_t program; // shader program name on OpenGL, 0 for none
} OORenderStateMachine;

// The current state. Read-only for backends.
const OORenderStateMachine* OORendererState(void);

// Writers, used by OOGLStateCompat.h and pushed draw states.
void OORendererSetCapability(OOCapability cap, bool enabled);
void OORendererSetLightEnabled(unsigned light, bool enabled);
void OORendererSetBlendFunc(OOBlendFactor src, OOBlendFactor dst);
void OORendererSetDepthMask(bool enabled);
void OORendererSetDepthFunc(OOCompareOp op);
void OORendererSetCullFace(OOCullFace face);
void OORendererSetFrontFaceCCW(bool ccw);
void OORendererSetFlatShading(bool flat);
void OORendererSetWireframe(bool wireframe);
void OORendererSetScissorRect(int x, int y, int width, int height);
void OORendererSetActiveTexture(unsigned unit);
void OORendererSetTextureEnabled(bool cube, bool enabled); // on the active unit
void OORendererSetTextureBinding(bool cube, uint32_t texture); // on the active unit
void OORendererSetTexEnvMode(OOTexEnvMode mode); // on the active unit
void OORendererSetTexEnvColor(const float rgba[4]); // on the active unit
void OORendererSetProgram(uint32_t program);
// A texture was deleted: GL unbinds it from every unit.
void OORendererForgetTexture(uint32_t texture);

/*  glPushAttrib/glPopAttrib for the state above. mask uses GL's
    GL_*_BIT values, so legacy callers can pass theirs straight through.
*/
void OORendererPushAttributes(uint32_t mask);
void OORendererPopAttributes(void);

// Replace the whole state, as after creating a context.
void OORendererResetState(void);

#ifdef __cplusplus
}
#endif

#endif
