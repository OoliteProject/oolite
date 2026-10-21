/*

OOFixedFunction.c


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

#include "OOFixedFunction.h"
#include "OORendererBackend.h"

#include <assert.h>
#include <string.h>

// GL's initial values.
#define OTHER_LIGHT { .ambient = { 0, 0, 0, 1 }, .diffuse = { 0, 0, 0, 1 }, .specular = { 0, 0, 0, 1 }, .position = { 0, 0, 1, 0 } }
static OOFixedFunctionValues sValues = {
    .lights = {
        { .ambient = { 0, 0, 0, 1 }, .diffuse = { 1, 1, 1, 1 }, .specular = { 1, 1, 1, 1 }, .position = { 0, 0, 1, 0 } },
        OTHER_LIGHT,
        OTHER_LIGHT,
        OTHER_LIGHT,
        OTHER_LIGHT,
        OTHER_LIGHT,
        OTHER_LIGHT,
        OTHER_LIGHT,
    },
    .lightModelAmbient = { 0.2f, 0.2f, 0.2f, 1 },
    .frontMaterial = { .ambient = { 0.2f, 0.2f, 0.2f, 1 }, .diffuse = { 0.8f, 0.8f, 0.8f, 1 }, .specular = { 0, 0, 0, 1 }, .emission = { 0, 0, 0, 1 } },
    .fog = { .mode = kOOFogExp, .start = 0, .end = 1, .density = 1 },
};
#undef OTHER_LIGHT

static void Copy4(float* dst, const float* src)
{
    memcpy(dst, src, 4 * sizeof(float));
}

void OORendererSetLightColor(unsigned light, OOLightColor which, const float rgba[4])
{
    assert(light < kOOFixedFunctionMaxLights);
    if (light >= kOOFixedFunctionMaxLights)
        return;
    OOLightValues* values = &sValues.lights[light];
    Copy4(which == kOOLightAmbient ? values->ambient : which == kOOLightDiffuse ? values->diffuse
                                                                                : values->specular,
        rgba);
    OORendererBackendSetLightColor(light, which, rgba);
}

void OORendererSetLightPosition(unsigned light, const float position[4], const float* modelView)
{
    assert(light < kOOFixedFunctionMaxLights);
    if (light >= kOOFixedFunctionMaxLights)
        return;
    float eye[4];
    if (modelView != NULL) {
        for (int row = 0; row < 4; row++) {
            eye[row] = modelView[row] * position[0] + modelView[4 + row] * position[1]
                + modelView[8 + row] * position[2] + modelView[12 + row] * position[3];
        }
    } else {
        Copy4(eye, position);
    }
    Copy4(sValues.lights[light].position, eye);
    OORendererBackendSetLightPosition(light, eye);
}

void OORendererSetFogHint(bool nicest)
{
    OORendererBackendSetFogHint(nicest);
}

void OORendererSetLightModelSeparateSpecular(bool separate)
{
    sValues.separateSpecular = separate;
    OORendererBackendSetLightModelSeparateSpecular(separate);
}

void OORendererSetLightModelAmbient(const float rgba[4])
{
    Copy4(sValues.lightModelAmbient, rgba);
    OORendererBackendSetLightModelAmbient(rgba);
}

void OORendererSetMaterialColor(OOMaterialFace face, OOMaterialColor which, const float rgba[4])
{
    if (face != kOOMaterialBack) {
        OOMaterialValues* m = &sValues.frontMaterial;
        switch (which) {
        case kOOMaterialAmbient:
            Copy4(m->ambient, rgba);
            break;
        case kOOMaterialDiffuse:
            Copy4(m->diffuse, rgba);
            break;
        case kOOMaterialSpecular:
            Copy4(m->specular, rgba);
            break;
        case kOOMaterialEmission:
            Copy4(m->emission, rgba);
            break;
        case kOOMaterialAmbientAndDiffuse:
            Copy4(m->ambient, rgba);
            Copy4(m->diffuse, rgba);
            break;
        }
    }
    OORendererBackendSetMaterialColor(face, which, rgba);
}

void OORendererSetMaterialShininess(OOMaterialFace face, float shininess)
{
    if (face != kOOMaterialBack)
        sValues.frontMaterial.shininess = shininess;
    OORendererBackendSetMaterialShininess(face, shininess);
}

void OORendererSetFogMode(OOFogMode mode)
{
    sValues.fog.mode = mode;
    OORendererBackendSetFog(&sValues.fog);
}

void OORendererSetFogColor(const float rgba[4])
{
    Copy4(sValues.fog.color, rgba);
    OORendererBackendSetFog(&sValues.fog);
}

void OORendererSetFogRange(float start, float end)
{
    sValues.fog.start = start;
    sValues.fog.end = end;
    OORendererBackendSetFog(&sValues.fog);
}

void OORendererSetFogDensity(float density)
{
    sValues.fog.density = density;
    OORendererBackendSetFog(&sValues.fog);
}

const OOFixedFunctionValues* OORendererGetFixedFunctionValues(void)
{
    return &sValues;
}
