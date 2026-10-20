/*

OORenderStateMachine.c


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

#include "OORenderStateMachine.h"

#include <assert.h>
#include <string.h>

// GL's attribute group bits, as glPushAttrib takes them.
enum {
    kCurrentBit = 0x00000001,
    kPointBit = 0x00000002,
    kLineBit = 0x00000004,
    kPolygonBit = 0x00000008,
    kLightingBit = 0x00000040,
    kFogBit = 0x00000080,
    kDepthBufferBit = 0x00000100,
    kEnableBit = 0x00002000,
    kColorBufferBit = 0x00004000,
    kTextureBit = 0x00040000,
    kScissorBit = 0x00080000,
};

static OORenderStateMachine sState;

enum {
    kMaxAttributeDepth = 16
};
static OORenderStateMachine sSaved[kMaxAttributeDepth];
static uint32_t sSavedMasks[kMaxAttributeDepth];
static int sDepth = 0;

void OORendererResetState(void)
{
    // GL's initial state.
    memset(&sState, 0, sizeof sState);
    sState.blendSrc = kOOBlendFactorOne;
    sState.blendDst = kOOBlendFactorZero;
    sState.depthMask = true;
    sState.depthFunc = kOOCompareLess;
    sState.cullFace = kOOCullBack;
    sState.frontFaceCCW = true;
    for (unsigned i = 0; i < kOOMaxTextureUnits; i++)
        sState.units[i].envMode = kOOTexEnvModulate;
    sDepth = 0;
}

static bool sInitialised = false;

static OORenderStateMachine* State(void)
{
    if (!sInitialised) {
        OORendererResetState();
        sInitialised = true;
    }
    return &sState;
}

const OORenderStateMachine* OORendererState(void)
{
    return State();
}

void OORendererSetCapability(OOCapability cap, bool enabled)
{
    if (cap < kOOCapCount)
        State()->caps[cap] = enabled;
}

void OORendererSetLightEnabled(unsigned light, bool enabled)
{
    if (light < kOOMaxStateLights)
        State()->lights[light] = enabled;
}

void OORendererSetBlendFunc(OOBlendFactor src, OOBlendFactor dst)
{
    State()->blendSrc = src;
    State()->blendDst = dst;
}

void OORendererSetDepthMask(bool enabled)
{
    State()->depthMask = enabled;
}

void OORendererSetDepthFunc(OOCompareOp op)
{
    State()->depthFunc = op;
}

void OORendererSetCullFace(OOCullFace face)
{
    State()->cullFace = face;
}

void OORendererSetFrontFaceCCW(bool ccw)
{
    State()->frontFaceCCW = ccw;
}

void OORendererSetFlatShading(bool flat)
{
    State()->flatShading = flat;
}

void OORendererSetWireframe(bool wireframe)
{
    State()->wireframe = wireframe;
}

void OORendererSetScissorRect(int x, int y, int width, int height)
{
    int* r = State()->scissor;
    r[0] = x;
    r[1] = y;
    r[2] = width;
    r[3] = height;
}

void OORendererSetActiveTexture(unsigned unit)
{
    if (unit < kOOMaxTextureUnits)
        State()->activeTexture = unit;
}

static OOTextureUnitState* ActiveUnit(void)
{
    return &State()->units[State()->activeTexture];
}

void OORendererSetTextureEnabled(bool cube, bool enabled)
{
    if (cube)
        ActiveUnit()->textureCube = enabled;
    else
        ActiveUnit()->texture2D = enabled;
}

void OORendererSetTextureBinding(bool cube, uint32_t texture)
{
    if (cube)
        ActiveUnit()->bindingCube = texture;
    else
        ActiveUnit()->binding2D = texture;
}

void OORendererSetTexEnvMode(OOTexEnvMode mode)
{
    ActiveUnit()->envMode = mode;
}

void OORendererSetTexEnvColor(const float rgba[4])
{
    memcpy(ActiveUnit()->envColor, rgba, sizeof ActiveUnit()->envColor);
}

void OORendererSetTextureLODBias(float bias)
{
    ActiveUnit()->lodBias = bias;
}

void OORendererSetProgram(uint32_t program)
{
    State()->program = program;
}

void OORendererForgetTexture(uint32_t texture)
{
    if (texture == 0)
        return;
    for (unsigned i = 0; i < kOOMaxTextureUnits; i++) {
        OOTextureUnitState* unit = &State()->units[i];
        if (unit->binding2D == texture)
            unit->binding2D = 0;
        if (unit->bindingCube == texture)
            unit->bindingCube = 0;
    }
}

void OORendererPushAttributes(uint32_t mask)
{
    assert(sDepth < kMaxAttributeDepth);
    if (sDepth >= kMaxAttributeDepth)
        return;
    sSaved[sDepth] = *State();
    sSavedMasks[sDepth] = mask;
    sDepth++;
}

static void RestoreCap(const OORenderStateMachine* saved, OOCapability cap)
{
    sState.caps[cap] = saved->caps[cap];
}

void OORendererPopAttributes(void)
{
    assert(sDepth > 0);
    if (sDepth <= 0)
        return;
    sDepth--;
    const OORenderStateMachine* saved = &sSaved[sDepth];
    uint32_t mask = sSavedMasks[sDepth];

    if (mask & kEnableBit) {
        memcpy(sState.caps, saved->caps, sizeof sState.caps);
        memcpy(sState.lights, saved->lights, sizeof sState.lights);
        for (unsigned i = 0; i < kOOMaxTextureUnits; i++) {
            sState.units[i].texture2D = saved->units[i].texture2D;
            sState.units[i].textureCube = saved->units[i].textureCube;
        }
    }
    if (mask & kColorBufferBit) {
        RestoreCap(saved, kOOCapBlend);
        sState.blendSrc = saved->blendSrc;
        sState.blendDst = saved->blendDst;
    }
    if (mask & kDepthBufferBit) {
        RestoreCap(saved, kOOCapDepthTest);
        sState.depthMask = saved->depthMask;
        sState.depthFunc = saved->depthFunc;
    }
    if (mask & kPolygonBit) {
        RestoreCap(saved, kOOCapCullFace);
        sState.cullFace = saved->cullFace;
        sState.frontFaceCCW = saved->frontFaceCCW;
        sState.wireframe = saved->wireframe;
    }
    if (mask & kLightingBit) {
        RestoreCap(saved, kOOCapLighting);
        RestoreCap(saved, kOOCapColorMaterial);
        memcpy(sState.lights, saved->lights, sizeof sState.lights);
        sState.flatShading = saved->flatShading;
    }
    if (mask & kFogBit)
        RestoreCap(saved, kOOCapFog);
    if (mask & kLineBit)
        RestoreCap(saved, kOOCapLineSmooth);
    if (mask & kPointBit) {
        RestoreCap(saved, kOOCapPointSmooth);
        RestoreCap(saved, kOOCapPointSprite);
    }
    if (mask & kScissorBit) {
        RestoreCap(saved, kOOCapScissorTest);
        memcpy(sState.scissor, saved->scissor, sizeof sState.scissor);
    }
    if (mask & kTextureBit) {
        sState.activeTexture = saved->activeTexture;
        memcpy(sState.units, saved->units, sizeof sState.units);
    }
    (void)kCurrentBit; // the current colour etc. are OOImmediate's
}
