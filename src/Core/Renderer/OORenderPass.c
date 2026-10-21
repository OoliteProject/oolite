/*

OORenderPass.c


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

#include "OORenderPass.h"
#include "OORendererBackend.h"

#include <assert.h>

static float sClearColor[4] = { 0, 0, 0, 0 };
static float sClearDepth = 1.0f;
static bool sInPass = false;
static OORenderTarget sTarget = kOORenderTargetCurrent;

void OORendererSetClearColor(float r, float g, float b, float a)
{
    sClearColor[0] = r;
    sClearColor[1] = g;
    sClearColor[2] = b;
    sClearColor[3] = a;
    // Legacy glClear calls still rely on GL's clear colour.
    OORendererBackendSetClearValues(sClearColor, sClearDepth);
}

void OORendererSetClearDepth(float depth)
{
    sClearDepth = depth;
    OORendererBackendSetClearValues(sClearColor, sClearDepth);
}

void OORendererBeginPass(const OORenderPassDescriptor* pass)
{
    assert(!sInPass);
    sInPass = true;
    sTarget = pass->target;
    OORendererBackendBeginPass(pass, sClearColor, sClearDepth);
}

void OORendererEndPass(void)
{
    assert(sInPass);
    sInPass = false;
    sTarget = kOORenderTargetCurrent;
    OORendererBackendEndPass();
}

void OORendererEndPassIfActive(void)
{
    if (sInPass)
        OORendererEndPass();
}

bool OORendererInPass(void)
{
    return sInPass;
}

OORenderTarget OORendererCurrentPassTarget(void)
{
    return sTarget;
}

void OORendererFinish(void)
{
    OORendererBackendFinish();
}

void OORendererFlush(void)
{
    OORendererBackendFlush();
}

void OORendererReadPixels(int x, int y, int width, int height, OOPixelFormat format, void* pixels)
{
    assert(!sInPass);
    OORendererBackendReadPixels(x, y, width, height, format, pixels);
}

static OORenderTarget sWindowTarget = 0;

void OORendererSetWindowTarget(OORenderTarget target)
{
    sWindowTarget = target;
}

OORenderTarget OORendererWindowTarget(void)
{
    return sWindowTarget;
}

OORenderTarget OORendererCreateRenderTarget(const OORenderTargetDescriptor* descriptor)
{
    if (descriptor == NULL || descriptor->width == 0 || descriptor->height == 0
        || descriptor->colorAttachments > kOOMaxColorAttachments
        || (descriptor->colorAttachments == 0 && !descriptor->depth)
        || (descriptor->samples != 1 && descriptor->samples != 4)) {
        OORendererBackendWarn("OORendererCreateRenderTarget: bad descriptor");
        return 0;
    }
    return OORendererBackendCreateRenderTarget(descriptor);
}

void OORendererResizeRenderTarget(OORenderTarget target, unsigned width, unsigned height)
{
    assert(!sInPass);
    if (target == 0 || width == 0 || height == 0)
        return;
    OORendererBackendResizeRenderTarget(target, width, height);
}

uint32_t OORendererRenderTargetTexture(OORenderTarget target, unsigned attachment)
{
    if (target == 0 || attachment >= kOOMaxColorAttachments)
        return 0;
    return OORendererBackendRenderTargetTexture(target, attachment);
}

void OORendererResolveRenderTarget(OORenderTarget source, OORenderTarget destination)
{
    assert(!sInPass);
    if (source == 0 || destination == 0)
        return;
    OORendererBackendResolveRenderTarget(source, destination);
}

void OORendererDeleteRenderTarget(OORenderTarget target)
{
    assert(!sInPass);
    if (target == 0)
        return;
    OORendererBackendDeleteRenderTarget(target);
}
