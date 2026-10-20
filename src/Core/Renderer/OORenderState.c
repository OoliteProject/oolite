/*

OORenderState.c


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

#include "OORenderState.h"
#include "OORendererBackend.h"

#include <assert.h>

static OODrawState sStack[kOORendererMaxDrawStateDepth];
static int sDepth = 0;

OODrawState OODrawStateForPreset(OODrawStatePreset preset)
{
    // Values from kStandardStates in OOOpenGLStateManager.m.
    OODrawState state = { 0 };
    switch (preset) {
    case kOODrawStateOpaque:
        state.depthTest = state.depthWrite = state.cullBack = true;
        state.lighting = state.texture2D = true;
        break;
    case kOODrawStateTranslucent:
        state.depthTest = state.cullBack = true;
        break;
    case kOODrawStateAdditive:
        state.blend = kOOBlendAdditive;
        state.depthTest = true;
        break;
    case kOODrawStateOverlay:
        state.blend = kOOBlendAlpha;
        break;
    }
    return state;
}

void OORendererPushDrawState(const OODrawState* state)
{
    assert(sDepth < kOORendererMaxDrawStateDepth);
    if (sDepth >= kOORendererMaxDrawStateDepth)
        return;
    sStack[sDepth] = *state;
    OORendererBackendPushDrawState(state, sDepth);
    sDepth++;
}

void OORendererPopDrawState(void)
{
    assert(sDepth > 0);
    if (sDepth <= 0)
        return;
    sDepth--;
    OORendererBackendPopDrawState(sDepth);
}

const OODrawState* OORendererCurrentDrawState(void)
{
    return sDepth > 0 ? &sStack[sDepth - 1] : NULL;
}

OODrawState OORendererInheritedDrawState(OODrawStatePreset fallback)
{
    return sDepth > 0 ? sStack[sDepth - 1] : OODrawStateForPreset(fallback);
}
