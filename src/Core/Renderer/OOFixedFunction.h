/*

OOFixedFunction.h

Fixed-function lighting, material and fog values as plain data, for the move
to SDL_GPU (issue #579).

SDL_GPU has no fixed-function pipeline. These values are what the
fixed-function emulation shaders and the translated OXP shaders read: the
OOLegacyState uniform block, see tools/sdl_gpu_spike/OOGLSLTranslator.h.
Callers set them here instead of through glLight/glMaterial/glFog. The
OpenGL backend passes them straight on to GL, and the renderer keeps a copy
for the SDL_GPU backend.

Light positions follow GL: they are transformed by the modelview current
when they are set, and stored in eye space. Pass that modelview explicitly.
Derived values (half vectors, light products) are left to GL now, and to
the SDL_GPU backend when it fills the uniform block.


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

#ifndef OOFIXEDFUNCTION_H
#define OOFIXEDFUNCTION_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    kOOFixedFunctionMaxLights = 8
};

typedef enum {
    kOOLightAmbient,
    kOOLightDiffuse,
    kOOLightSpecular,
} OOLightColor;

typedef enum {
    kOOMaterialAmbient,
    kOOMaterialDiffuse,
    kOOMaterialSpecular,
    kOOMaterialEmission,
    kOOMaterialAmbientAndDiffuse,
} OOMaterialColor;

typedef enum {
    kOOMaterialFront,
    kOOMaterialBack,
    kOOMaterialFrontAndBack,
} OOMaterialFace;

typedef enum {
    kOOFogLinear,
    kOOFogExp,
    kOOFogExp2,
} OOFogMode;

typedef struct {
    float ambient[4], diffuse[4], specular[4];
    float position[4]; // eye space
} OOLightValues;

typedef struct {
    float ambient[4], diffuse[4], specular[4], emission[4];
    float shininess;
} OOMaterialValues;

typedef struct {
    OOFogMode mode;
    float color[4];
    float start, end, density;
} OOFogValues;

typedef struct {
    OOLightValues lights[kOOFixedFunctionMaxLights];
    float lightModelAmbient[4];
    bool separateSpecular; // GL_SEPARATE_SPECULAR_COLOR: specular added after texturing
    OOMaterialValues frontMaterial; // GL_BACK values are only passed to GL
    OOFogValues fog;
} OOFixedFunctionValues;

void OORendererSetLightColor(unsigned light, OOLightColor which, const float rgba[4]);
/*  position is in object space; modelView (column-major, may be NULL for the
    identity) is the modelview it is in, as for glLightfv(GL_POSITION).
*/
void OORendererSetLightPosition(unsigned light, const float position[4], const float* modelView);
void OORendererSetLightModelAmbient(const float rgba[4]);
void OORendererSetLightModelSeparateSpecular(bool separate);
// GL_FOG_HINT: nicest (per-pixel) or fastest. SDL_GPU always fogs per pixel.
void OORendererSetFogHint(bool nicest);

void OORendererSetMaterialColor(OOMaterialFace face, OOMaterialColor which, const float rgba[4]);
void OORendererSetMaterialShininess(OOMaterialFace face, float shininess);

void OORendererSetFogMode(OOFogMode mode);
void OORendererSetFogColor(const float rgba[4]);
void OORendererSetFogRange(float start, float end);
void OORendererSetFogDensity(float density);

// The values last set, for backends that upload them as uniforms.
const OOFixedFunctionValues* OORendererGetFixedFunctionValues(void);

#ifdef __cplusplus
}
#endif

#endif
