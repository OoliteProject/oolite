/*

oogpu-backend-test.c

Draws the same scenes through the renderer layer with the OpenGL backend
(built as oogpu-backend-test-gl) or the SDL_GPU backend
(oogpu-backend-test-gpu), and saves each one as a BMP. The scenes use only
the renderer's API, so comparing the two sets of images checks the SDL_GPU
backend against GL. oogpu-backend-compare.py does the comparison.

    oogpu-backend-test-gl <dir>
    oogpu-backend-test-gpu <dir>      (OO_BACKEND_FAULT=<name> plants a fault)


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
#include "OOImmediateMode.h"
#include "OORenderPass.h"
#include "OORenderState.h"
#include "OORenderStateMachine.h"
#include "OORendererProgram.h"
#include "OORendererTexture.h"
#include "OOVertexArray.h"

#include <SDL3/SDL.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if OO_BACKEND_GPU
#include "OORendererSDLGPU.h"
#else
#if defined(__APPLE__)
#define GL_SILENCE_DEPRECATION 1
#include <OpenGL/gl.h>
#include <OpenGL/glext.h>
#else
#define GL_GLEXT_PROTOTYPES 1
#include <GL/gl.h>
#include <GL/glext.h>
#endif
#endif

enum {
    kSize = 256
};
static const float kPi = 3.14159265358979f;

static unsigned sWarnings = 0;

void OORendererBackendWarn(const char* message)
{
    fprintf(stderr, "renderer warning: %s\n", message);
    sWarnings++;
}

/*  Texture glue: the game passes OOTextures; here a "texture" is a renderer
    texture handle cast to a pointer.
*/
void OORendererBackendApplyTexture(const void* texture);
unsigned OORendererBackendTextureName(const void* texture);
void OORendererBackendSaveTexture(int depth);
void OORendererBackendRestoreTexture(int depth);

unsigned OORendererBackendTextureName(const void* texture)
{
    return (unsigned)(uintptr_t)texture;
}

#if OO_BACKEND_GPU
void OORendererBackendApplyTexture(const void* texture)
{
    (void)texture;
}

void OORendererBackendSaveTexture(int depth)
{
    (void)depth;
}

void OORendererBackendRestoreTexture(int depth)
{
    (void)depth;
}
#else
static GLint sSavedBinding[16];

void OORendererBackendApplyTexture(const void* texture)
{
    glBindTexture(GL_TEXTURE_2D, (GLuint)(uintptr_t)texture);
}

void OORendererBackendSaveTexture(int depth)
{
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &sSavedBinding[depth]);
}

void OORendererBackendRestoreTexture(int depth)
{
    glBindTexture(GL_TEXTURE_2D, (GLuint)sSavedBinding[depth]);
}

void OORendererBackendVerifyStateMachine(void)
{
}
#endif

#if !OO_BACKEND_GPU
void OORendererBackendNoteDrawOutsidePass(void)
{
    OORendererBackendWarn("a draw outside any pass");
}
#endif

#pragma mark - State the game sets through the OOGL* wrappers

/*  In the game these go through OOGLStateCompat.m, which records them in the
    state mirror and makes the GL call. The scenes do the same here.
*/
static void SetMatrices(const float modelView[16], const float projection[16])
{
    OORendererSetModelViewMatrix(modelView);
    OORendererSetProjectionMatrix(projection);
#if !OO_BACKEND_GPU
    glMatrixMode(GL_PROJECTION);
    glLoadMatrixf(projection);
    glMatrixMode(GL_MODELVIEW);
    glLoadMatrixf(modelView);
#endif
}

static void SetViewport(int x, int y, int width, int height)
{
    OORendererSetViewport(x, y, width, height);
#if !OO_BACKEND_GPU
    glViewport(x, y, width, height);
#endif
}

static void SetFlatShading(bool flat)
{
    OORendererSetFlatShading(flat);
#if !OO_BACKEND_GPU
    glShadeModel(flat ? GL_FLAT : GL_SMOOTH);
#endif
}

static void SetLightEnabled(unsigned light, bool enabled)
{
    OORendererSetLightEnabled(light, enabled);
#if !OO_BACKEND_GPU
    if (enabled)
        glEnable(GL_LIGHT0 + light);
    else
        glDisable(GL_LIGHT0 + light);
#endif
}

static void BindTextureUnit(unsigned unit, uint32_t texture)
{
    OORendererSetActiveTexture(unit);
    OORendererSetTextureBinding(false, texture);
#if !OO_BACKEND_GPU
    glActiveTexture(GL_TEXTURE0 + unit);
    glBindTexture(GL_TEXTURE_2D, texture);
#endif
    OORendererSetActiveTexture(0);
#if !OO_BACKEND_GPU
    glActiveTexture(GL_TEXTURE0);
#endif
}

static void SetDepthFunc(OOCompareOp op)
{
    OORendererSetDepthFunc(op);
#if !OO_BACKEND_GPU
    static const GLenum kOps[] = { GL_NEVER, GL_LESS, GL_EQUAL, GL_LEQUAL, GL_GREATER, GL_NOTEQUAL, GL_GEQUAL, GL_ALWAYS };
    glDepthFunc(kOps[op]);
#endif
}

#pragma mark - Matrices

static void Identity(float m[16])
{
    memset(m, 0, 16 * sizeof(float));
    m[0] = m[5] = m[10] = m[15] = 1.0f;
}

static void Ortho(float m[16], float l, float r, float b, float t, float n, float f)
{
    Identity(m);
    m[0] = 2.0f / (r - l);
    m[5] = 2.0f / (t - b);
    m[10] = -2.0f / (f - n);
    m[12] = -(r + l) / (r - l);
    m[13] = -(t + b) / (t - b);
    m[14] = -(f + n) / (f - n);
}

static void Perspective(float m[16], float fovyDegrees, float aspect, float n, float f)
{
    float t = 1.0f / tanf(fovyDegrees * kPi / 360.0f);
    memset(m, 0, 16 * sizeof(float));
    m[0] = t / aspect;
    m[5] = t;
    m[10] = (f + n) / (n - f);
    m[11] = -1.0f;
    m[14] = 2.0f * f * n / (n - f);
}

static void Translation(float m[16], float x, float y, float z)
{
    Identity(m);
    m[12] = x;
    m[13] = y;
    m[14] = z;
}

static void SetOrtho2D(void)
{
    float mv[16], p[16];
    Identity(mv);
    Ortho(p, 0, kSize, 0, kSize, -1, 1);
    SetMatrices(mv, p);
}

#pragma mark - Scenes

static OODrawState Plain(void)
{
    return (OODrawState) { .blend = kOOBlendOff };
}

static void Vertex(float x, float y, float r, float g, float b, float a)
{
    OOImmediateColor4f(r, g, b, a);
    OOImmediateVertex2f(x, y);
}

// Smooth-shaded triangles with per-vertex colours.
static void SceneSmooth(void)
{
    SetOrtho2D();
    OODrawState state = Plain();
    OORendererPushDrawState(&state);
    OOImmediateBegin(kOOPrimitiveTriangles);
    Vertex(20, 20, 1, 0, 0, 1);
    Vertex(230, 40, 0, 1, 0, 1);
    Vertex(110, 220, 0, 0, 1, 1);
    Vertex(150, 200, 1, 1, 0, 1);
    Vertex(240, 230, 0, 1, 1, 1);
    Vertex(200, 120, 1, 0, 1, 1);
    OOImmediateEnd();
    OORendererPopDrawState();
}

// Flat-shaded quads and a fan: each primitive takes GL's provoking (last) vertex colour.
static void SceneFlat(void)
{
    SetOrtho2D();
    SetFlatShading(true);
    OODrawState state = Plain();
    OORendererPushDrawState(&state);
    OOImmediateBegin(kOOPrimitiveQuads);
    Vertex(10, 10, 1, 0, 0, 1);
    Vertex(120, 20, 0, 1, 0, 1);
    Vertex(110, 120, 0, 0, 1, 1);
    Vertex(20, 110, 1, 1, 0, 1);
    OOImmediateEnd();
    OOImmediateBegin(kOOPrimitiveTriangleFan);
    Vertex(190, 190, 1, 1, 1, 1);
    Vertex(250, 190, 1, 0, 0, 1);
    Vertex(240, 240, 0, 1, 0, 1);
    Vertex(190, 250, 0, 0, 1, 1);
    Vertex(140, 240, 1, 0, 1, 1);
    OOImmediateEnd();
    OOImmediateBegin(kOOPrimitiveLines);
    Vertex(10, 200, 1, 0, 0, 1);
    Vertex(120, 240, 0, 1, 0, 1);
    OOImmediateEnd();
    OORendererPopDrawState();
    SetFlatShading(false);
}

// Alpha and additive blending over a background.
static void SceneBlend(void)
{
    SetOrtho2D();
    OODrawState state = Plain();
    OORendererPushDrawState(&state);
    OOImmediateBegin(kOOPrimitiveQuads);
    Vertex(0, 0, 0.2f, 0.3f, 0.6f, 1);
    Vertex(256, 0, 0.2f, 0.3f, 0.6f, 1);
    Vertex(256, 128, 0.6f, 0.2f, 0.2f, 1);
    Vertex(0, 128, 0.6f, 0.2f, 0.2f, 1);
    OOImmediateEnd();
    OORendererPopDrawState();

    state.blend = kOOBlendAlpha;
    OORendererPushDrawState(&state);
    OOImmediateBegin(kOOPrimitiveQuads);
    Vertex(30, 30, 1, 1, 0, 0.5f);
    Vertex(200, 30, 1, 1, 0, 0.5f);
    Vertex(200, 200, 1, 1, 0, 0.25f);
    Vertex(30, 200, 1, 1, 0, 0.75f);
    OOImmediateEnd();
    OORendererPopDrawState();

    state.blend = kOOBlendAdditive;
    OORendererPushDrawState(&state);
    OOImmediateBegin(kOOPrimitiveTriangles);
    Vertex(100, 100, 0.5f, 0, 0.5f, 0.8f);
    Vertex(250, 120, 0, 0.5f, 0.5f, 0.8f);
    Vertex(150, 250, 0.5f, 0.5f, 0, 0.8f);
    OOImmediateEnd();
    OORendererPopDrawState();
}

// Two triangles that pass through each other, in perspective: checks the depth remap.
static void SceneDepth(void)
{
    float mv[16], p[16];
    Translation(mv, 0, 0, -4);
    Perspective(p, 60, 1, 1, 10);
    SetMatrices(mv, p);
    OODrawState state = Plain();
    state.depthTest = true;
    state.depthWrite = true;
    OORendererPushDrawState(&state);
    SetDepthFunc(kOOCompareLessOrEqual);
    OOImmediateBegin(kOOPrimitiveTriangles);
    OOImmediateColor4f(1, 0.5f, 0, 1);
    OOImmediateVertex3f(-2, -1.5f, -1);
    OOImmediateVertex3f(2, -1.5f, 1);
    OOImmediateVertex3f(0, 2, 0);
    OOImmediateColor4f(0, 0.5f, 1, 1);
    OOImmediateVertex3f(-2, 1.5f, 1);
    OOImmediateVertex3f(0, -2, 0);
    OOImmediateVertex3f(2, 1.5f, -1);
    // Close to the near plane, where GL's clip-space depth is negative.
    OOImmediateColor4f(0.2f, 1, 0.2f, 1);
    OOImmediateVertex3f(-0.6f, -0.9f, 2.6f);
    OOImmediateVertex3f(0.2f, -0.9f, 2.6f);
    OOImmediateVertex3f(-0.2f, -0.3f, 2.6f);
    // Crossing the near plane (eye depth 1): GL clips the part in front of it.
    OOImmediateColor4f(1, 1, 1, 1);
    OOImmediateVertex3f(0.8f, 1.0f, 1.5f);
    OOImmediateVertex3f(-0.15f, 0.1f, 3.6f);
    OOImmediateVertex3f(0.15f, -0.1f, 3.6f);
    OOImmediateEnd();
    SetDepthFunc(kOOCompareLess);
    OORendererPopDrawState();
}

// Back-face culling: of each pair, only the counter-clockwise triangle shows.
static void SceneCull(void)
{
    SetOrtho2D();
    OODrawState state = Plain();
    state.cullBack = true;
    OORendererPushDrawState(&state);
    OOImmediateBegin(kOOPrimitiveTriangles);
    Vertex(20, 20, 1, 0, 0, 1);
    Vertex(120, 20, 1, 0, 0, 1);
    Vertex(70, 120, 1, 0, 0, 1);
    Vertex(140, 20, 0, 1, 0, 1);
    Vertex(190, 120, 0, 1, 0, 1);
    Vertex(240, 20, 0, 1, 0, 1);
    Vertex(20, 140, 0, 0, 1, 1);
    Vertex(120, 140, 0, 0, 1, 1);
    Vertex(70, 240, 0, 0, 1, 1);
    OOImmediateEnd();
    OORendererPopDrawState();
}

static uint32_t sChecker = 0;

// A nearest-filtered checkerboard, modulated by vertex colour.
static void SceneTexture(void)
{
    if (sChecker == 0) {
        uint8_t texels[8 * 8 * 4];
        for (int i = 0; i < 64; i++) {
            bool on = ((i % 8) + (i / 8)) % 2;
            uint8_t* t = &texels[i * 4];
            t[0] = on ? 255 : 40;
            t[1] = on ? 200 : 80;
            t[2] = on ? 60 : 160;
            t[3] = 255;
        }
        OOTextureDescriptor descriptor = { .width = 8, .height = 8, .levels = 1, .format = kOOTexelRGBA8, .repeatS = true, .repeatT = true, .minFilter = kOOFilterNearest, .magFilter = kOOFilterNearest };
        sChecker = OORendererCreateTexture(&descriptor);
        OORendererUploadTexture(sChecker, 0, 0, 8, 8, texels);
    }
    SetOrtho2D();
    OODrawState state = Plain();
    state.texture2D = true;
    state.texture = (const void*)(uintptr_t)sChecker;
    OORendererPushDrawState(&state);
    OOImmediateBegin(kOOPrimitiveQuads);
    OOImmediateColor4f(1, 1, 1, 1);
    OOImmediateTexCoord2f(0, 0);
    OOImmediateVertex2f(16, 16);
    OOImmediateColor4f(1, 0.5f, 0.5f, 1);
    OOImmediateTexCoord2f(2, 0);
    OOImmediateVertex2f(240, 16);
    OOImmediateColor4f(0.5f, 1, 0.5f, 1);
    OOImmediateTexCoord2f(2, 2);
    OOImmediateVertex2f(240, 240);
    OOImmediateColor4f(0.5f, 0.5f, 1, 1);
    OOImmediateTexCoord2f(0, 2);
    OOImmediateVertex2f(16, 240);
    OOImmediateEnd();
    OORendererPopDrawState();
}

// Indexed vertex arrays: a strip with 16-bit indices and colours.
static void SceneArrays(void)
{
    static const float positions[] = { 20, 30, 20, 220, 80, 60, 90, 200, 150, 40, 160, 230, 230, 30, 236, 210 };
    static const float colors[] = { 1, 0, 0, 1, 0, 1, 0, 1, 0, 0, 1, 1, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 0.5f, 0.5f, 0.5f, 1 };
    static const uint16_t indices[] = { 0, 1, 2, 3, 4, 5, 6, 7 };
    static OORendererBuffer *positionBuffer, *colorBuffer, *indexBuffer;
    if (positionBuffer == NULL) {
        positionBuffer = OORendererCreateBuffer(positions, sizeof positions);
        colorBuffer = OORendererCreateBuffer(colors, sizeof colors);
        indexBuffer = OORendererCreateBuffer(indices, sizeof indices);
    }
    SetOrtho2D();
    OODrawState state = Plain();
    OORendererPushDrawState(&state);
    OOVertexLayout layout = { 0 };
    OOVertexLayoutAdd(&layout, kOOVertexPosition, 0, 2, 0, positionBuffer, 0);
    OOVertexLayoutAdd(&layout, kOOVertexColor, 0, 4, 0, colorBuffer, 0);
    OORendererDrawElements(kOONativePrimitiveTriangleStrip, &layout, indexBuffer, 0, kOOIndex16, 8);
    OORendererPopDrawState();
}

// A lit sphere: light 1 as a directional sun, as Universe sets it, and a white material.
static void SceneLit(void)
{
    float mv[16], p[16];
    Translation(mv, 0, 0, -3);
    Perspective(p, 50, 1, 1, 10);
    // Light positions are given in eye space, with the identity modelview.
    float identity[16];
    Identity(identity);
    SetMatrices(identity, p);
    const float ambient[4] = { 0.1f, 0.1f, 0.1f, 1 }, diffuse[4] = { 1, 0.9f, 0.8f, 1 }, specular[4] = { 1, 1, 1, 1 };
    const float direction[4] = { -0.5f, 0.6f, 0.62f, 0 };
    OORendererSetLightColor(1, kOOLightAmbient, ambient);
    OORendererSetLightColor(1, kOOLightDiffuse, diffuse);
    OORendererSetLightColor(1, kOOLightSpecular, specular);
    OORendererSetLightPosition(1, direction, NULL);
    const float matAmbient[4] = { 0.6f, 0.6f, 0.6f, 1 }, matDiffuse[4] = { 0.7f, 0.6f, 0.5f, 1 }, matSpecular[4] = { 0.4f, 0.4f, 0.4f, 1 }, black[4] = { 0, 0, 0, 1 };
    OORendererSetMaterialColor(kOOMaterialFrontAndBack, kOOMaterialAmbient, matAmbient);
    OORendererSetMaterialColor(kOOMaterialFrontAndBack, kOOMaterialDiffuse, matDiffuse);
    OORendererSetMaterialColor(kOOMaterialFrontAndBack, kOOMaterialSpecular, matSpecular);
    OORendererSetMaterialColor(kOOMaterialFrontAndBack, kOOMaterialEmission, black);
    OORendererSetMaterialShininess(kOOMaterialFrontAndBack, 20);
    SetLightEnabled(0, false);
    SetLightEnabled(1, true);
    SetMatrices(mv, p);

    OODrawState state = Plain();
    state.depthTest = true;
    state.depthWrite = true;
    state.cullBack = true;
    state.lighting = true;
    OORendererPushDrawState(&state);
    enum {
        kStacks = 24,
        kSlices = 32
    };
    for (int i = 0; i < kStacks; i++) {
        OOImmediateBegin(kOOPrimitiveTriangleStrip);
        for (int j = 0; j <= kSlices; j++) {
            for (int k = 0; k <= 1; k++) {
                float phi = kPi * ((float)(i + k) / kStacks - 0.5f);
                float theta = 2.0f * kPi * j / kSlices;
                float n[3] = { cosf(phi) * cosf(theta), sinf(phi), cosf(phi) * sinf(theta) };
                OOImmediateNormal3f(n[0], n[1], n[2]);
                OOImmediateVertex3f(n[0], n[1], n[2]);
            }
        }
        OOImmediateEnd();
    }
    OORendererPopDrawState();
    SetLightEnabled(1, false);
}

// A scissored draw inside a smaller viewport, both off-centre vertically,
// so flipping between GL's bottom-left origin and SDL_GPU's shows.
static void SceneScissor(void)
{
    SetViewport(32, 40, 160, 128);
    SetOrtho2D();
    OODrawState state = Plain();
    state.scissor = true;
    state.scissorRect[0] = 60;
    state.scissorRect[1] = 20;
    state.scissorRect[2] = 100;
    state.scissorRect[3] = 120;
    OORendererPushDrawState(&state);
    OOImmediateBegin(kOOPrimitiveQuads);
    Vertex(0, 0, 1, 0, 0, 1);
    Vertex(256, 0, 0, 1, 0, 1);
    Vertex(256, 256, 0, 0, 1, 1);
    Vertex(0, 256, 1, 1, 1, 1);
    OOImmediateEnd();
    OORendererPopDrawState();
    SetViewport(0, 0, kSize, kSize);
}

// Render targets: drawn before the window pass, then sampled in it.
enum {
    kTargetSize = 128
};
static OORenderTarget sTarget, sMSAATarget, sResolved, sMRT;

static void DrawTargetContent(void)
{
    SetViewport(0, 0, kTargetSize, kTargetSize);
    float mv[16], p[16];
    Identity(mv);
    Ortho(p, 0, kTargetSize, 0, kTargetSize, -1, 1);
    SetMatrices(mv, p);
    OODrawState state = Plain();
    OORendererPushDrawState(&state);
    // An asymmetric picture, so a flipped target shows.
    OOImmediateBegin(kOOPrimitiveTriangles);
    Vertex(8, 8, 1, 0, 0, 1);
    Vertex(120, 16, 0, 1, 0, 1);
    Vertex(16, 100, 0, 0, 1, 1);
    Vertex(100, 120, 1, 1, 0, 1);
    Vertex(70, 90, 1, 1, 0, 1);
    Vertex(120, 70, 1, 1, 0, 1);
    OOImmediateEnd();
    OORendererPopDrawState();
    SetViewport(0, 0, kSize, kSize);
}

static void DrawTargetQuad(OORenderTarget target, unsigned attachment)
{
    SetOrtho2D();
    OODrawState state = Plain();
    state.texture2D = true;
    state.texture = (const void*)(uintptr_t)OORendererRenderTargetTexture(target, attachment);
    OORendererPushDrawState(&state);
    OOImmediateBegin(kOOPrimitiveQuads);
    OOImmediateColor4f(1, 1, 1, 1);
    OOImmediateTexCoord2f(0, 0);
    OOImmediateVertex2f(20, 30);
    OOImmediateTexCoord2f(1, 0);
    OOImmediateVertex2f(236, 30);
    OOImmediateTexCoord2f(1, 1);
    OOImmediateVertex2f(236, 230);
    OOImmediateTexCoord2f(0, 1);
    OOImmediateVertex2f(20, 230);
    OOImmediateEnd();
    OORendererPopDrawState();
}

static void PrepareTarget(void)
{
    if (sTarget == 0)
        sTarget = OORendererCreateRenderTarget(&(OORenderTargetDescriptor) { kTargetSize, kTargetSize, 1, true, 1 });
    OORendererSetClearColor(0.1f, 0.2f, 0.3f, 1);
    OORendererBeginPass(&(OORenderPassDescriptor) { .target = sTarget, .colorLoad = kOOLoadClear, .depthLoad = kOOLoadClear });
    DrawTargetContent();
    OORendererEndPass();
}

static void SceneTarget(void)
{
    DrawTargetQuad(sTarget, 0);
}

static void PrepareMSAA(void)
{
    if (sMSAATarget == 0) {
        sMSAATarget = OORendererCreateRenderTarget(&(OORenderTargetDescriptor) { kTargetSize, kTargetSize, 1, true, 4 });
        sResolved = OORendererCreateRenderTarget(&(OORenderTargetDescriptor) { kTargetSize, kTargetSize, 1, false, 1 });
    }
    OORendererSetClearColor(0, 0, 0, 1);
    OORendererBeginPass(&(OORenderPassDescriptor) { .target = sMSAATarget, .colorLoad = kOOLoadClear, .depthLoad = kOOLoadClear });
    DrawTargetContent();
    OORendererEndPass();
    OORendererResolveRenderTarget(sMSAATarget, sResolved);
}

static void SceneMSAA(void)
{
    DrawTargetQuad(sResolved, 0);
}

static void PrepareMRT(void)
{
    if (sMRT == 0)
        sMRT = OORendererCreateRenderTarget(&(OORenderTargetDescriptor) { 64, 32, 2, false, 1 });
    // A clear reaches every attachment.
    OORendererSetClearColor(0.75f, 0.5f, 0.25f, 1);
    OORendererBeginPass(&(OORenderPassDescriptor) { .target = sMRT, .colorLoad = kOOLoadClear, .depthLoad = kOOLoadDontCare });
    OORendererEndPass();
}

static void SceneMRT(void)
{
    DrawTargetQuad(sMRT, 1);
}

// A custom legacy GLSL program, as materials and OXPs supply: uniforms of
// several types, a sampler on texture unit 1, the normal matrix, a light,
// and a generic "tangent" attribute bound by name, from indexed arrays.
static const char* const kProgramVertex = "attribute vec3 tangent;\n"
                                          "uniform float uScale;\n"
                                          "varying vec3 vNormal;\n"
                                          "varying vec3 vTangent;\n"
                                          "varying vec2 vTexCoord;\n"
                                          "void main(void)\n"
                                          "{\n"
                                          "    vNormal = normalize(gl_NormalMatrix * gl_Normal);\n"
                                          "    vTangent = tangent;\n"
                                          "    vTexCoord = gl_MultiTexCoord0.st * uScale;\n"
                                          "    gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex;\n"
                                          "}\n";
static const char* const kProgramFragment = "uniform sampler2D uTexture;\n"
                                            "uniform vec4 uTint;\n"
                                            "uniform bool uShowTangent;\n"
                                            "varying vec3 vNormal;\n"
                                            "varying vec3 vTangent;\n"
                                            "varying vec2 vTexCoord;\n"
                                            "void main(void)\n"
                                            "{\n"
                                            "    vec3 l = normalize(gl_LightSource[1].position.xyz);\n"
                                            "    float d = max(dot(normalize(vNormal), l), 0.0);\n"
                                            "    vec3 c = texture2D(uTexture, vTexCoord).rgb * uTint.rgb * (0.15 + d * gl_LightSource[1].diffuse.rgb);\n"
                                            "    if (uShowTangent) c += 0.3 * abs(vTangent);\n"
                                            "    gl_FragColor = vec4(c, 1.0);\n"
                                            "}\n";

enum {
    kSphereStacks = 16,
    kSphereSlices = 24,
    kSphereVertices = (kSphereStacks + 1) * (kSphereSlices + 1),
    kSphereIndices = kSphereStacks * kSphereSlices * 6,
    kTangentLocation = 5
};

static void SceneProgram(void)
{
    static float positions[kSphereVertices * 3], normals[kSphereVertices * 3], texCoords[kSphereVertices * 2], tangents[kSphereVertices * 3];
    static uint16_t indices[kSphereIndices];
    static OORendererBuffer *positionBuffer, *normalBuffer, *texCoordBuffer, *tangentBuffer, *indexBuffer;
    static OORendererProgram* program;
    if (program == NULL) {
        size_t v = 0, n = 0;
        for (int i = 0; i <= kSphereStacks; i++) {
            for (int j = 0; j <= kSphereSlices; j++, v++) {
                float phi = kPi * ((float)i / kSphereStacks - 0.5f), theta = 2.0f * kPi * j / kSphereSlices;
                float p[3] = { cosf(phi) * cosf(theta), sinf(phi), cosf(phi) * sinf(theta) };
                memcpy(&positions[v * 3], p, sizeof p);
                memcpy(&normals[v * 3], p, sizeof p);
                texCoords[v * 2] = (float)j / kSphereSlices;
                texCoords[v * 2 + 1] = (float)i / kSphereStacks;
                tangents[v * 3] = -sinf(theta);
                tangents[v * 3 + 1] = 0;
                tangents[v * 3 + 2] = cosf(theta);
            }
        }
        for (int i = 0; i < kSphereStacks; i++) {
            for (int j = 0; j < kSphereSlices; j++) {
                uint16_t a = (uint16_t)(i * (kSphereSlices + 1) + j), b = (uint16_t)(a + kSphereSlices + 1);
                uint16_t quad[6] = { a, (uint16_t)(a + 1), b, b, (uint16_t)(a + 1), (uint16_t)(b + 1) };
                memcpy(&indices[n], quad, sizeof quad);
                n += 6;
            }
        }
        positionBuffer = OORendererCreateBuffer(positions, sizeof positions);
        normalBuffer = OORendererCreateBuffer(normals, sizeof normals);
        texCoordBuffer = OORendererCreateBuffer(texCoords, sizeof texCoords);
        tangentBuffer = OORendererCreateBuffer(tangents, sizeof tangents);
        indexBuffer = OORendererCreateBuffer(indices, sizeof indices);
        OOAttributeBinding binding = { "tangent", kTangentLocation };
        OOProgramError error;
        program = OORendererCreateProgram(kProgramVertex, kProgramFragment, NULL, &binding, 1, &error);
        if (program == NULL) {
            fprintf(stderr, "program: stage %d failed:\n%s\n", error.stage, error.log ? error.log : "");
            OORendererBackendWarn("program creation failed");
            return;
        }
    }
    if (sChecker == 0) {
        OORendererBackendWarn("the texture scene must run first, to create the checkerboard");
        return;
    }
    float mv[16], p[16], identity[16];
    Identity(identity);
    Translation(mv, 0, 0, -3);
    Perspective(p, 50, 1, 1, 10);
    SetMatrices(identity, p);
    const float diffuse[4] = { 1, 0.85f, 0.7f, 1 }, direction[4] = { -0.4f, 0.5f, 0.77f, 0 };
    OORendererSetLightColor(1, kOOLightDiffuse, diffuse);
    OORendererSetLightPosition(1, direction, NULL);
    SetMatrices(mv, p);
    BindTextureUnit(1, sChecker);

    OODrawState state = Plain();
    state.depthTest = true;
    state.depthWrite = true;
    state.cullBack = true;
    OORendererPushDrawState(&state);
    OORendererUseProgram(program);
    const float scale = 2.0f, tint[4] = { 1.0f, 0.8f, 0.9f, 1.0f };
    const int32_t unit = 1, show = 1;
    OORendererSetUniform(OORendererProgramUniform(program, "uScale"), kOOUniformFloat, &scale);
    OORendererSetUniform(OORendererProgramUniform(program, "uTint"), kOOUniformVec4, tint);
    OORendererSetUniform(OORendererProgramUniform(program, "uShowTangent"), kOOUniformInt, &show);
    OORendererSetUniform(OORendererProgramUniform(program, "uTexture"), kOOUniformInt, &unit);
    OOVertexLayout layout = { 0 };
    OOVertexLayoutAdd(&layout, kOOVertexPosition, 0, 3, 0, positionBuffer, 0);
    OOVertexLayoutAdd(&layout, kOOVertexNormal, 0, 3, 0, normalBuffer, 0);
    OOVertexLayoutAdd(&layout, kOOVertexTexCoord, 0, 2, 0, texCoordBuffer, 0);
    OOVertexLayoutAdd(&layout, kOOVertexAttribute, kTangentLocation, 3, 0, tangentBuffer, 0);
    OORendererDrawElements(kOONativePrimitiveTriangles, &layout, indexBuffer, 0, kOOIndex16, kSphereIndices);
    OORendererUseProgram(NULL);
    OORendererPopDrawState();
    BindTextureUnit(1, 0);
}

// Separate specular: highlights added after texturing, over a dark texture,
// where adding them before texturing would darken them.
static void SceneSpecular(void)
{
    static uint32_t dark;
    if (dark == 0) {
        uint8_t texels[4 * 4 * 4];
        for (int i = 0; i < 16; i++) {
            uint8_t* t = &texels[i * 4];
            t[0] = 50;
            t[1] = 60 + 8 * (i % 4);
            t[2] = 90;
            t[3] = 255;
        }
        OOTextureDescriptor descriptor = { .width = 4, .height = 4, .levels = 1, .format = kOOTexelRGBA8, .repeatS = true, .repeatT = true, .minFilter = kOOFilterNearest, .magFilter = kOOFilterNearest };
        dark = OORendererCreateTexture(&descriptor);
        OORendererUploadTexture(dark, 0, 0, 4, 4, texels);
    }
    float mv[16], p[16], identity[16];
    Identity(identity);
    Translation(mv, 0, 0, -3);
    Perspective(p, 50, 1, 1, 10);
    SetMatrices(identity, p);
    const float ambient[4] = { 0.05f, 0.05f, 0.05f, 1 }, diffuse[4] = { 0.6f, 0.6f, 0.6f, 1 }, specular[4] = { 1, 1, 1, 1 };
    const float direction[4] = { -0.3f, 0.4f, 0.87f, 0 };
    OORendererSetLightColor(1, kOOLightAmbient, ambient);
    OORendererSetLightColor(1, kOOLightDiffuse, diffuse);
    OORendererSetLightColor(1, kOOLightSpecular, specular);
    OORendererSetLightPosition(1, direction, NULL);
    const float matAmbient[4] = { 0.3f, 0.3f, 0.3f, 1 }, matDiffuse[4] = { 0.8f, 0.8f, 0.8f, 1 }, matSpecular[4] = { 0.9f, 0.9f, 0.9f, 1 }, black[4] = { 0, 0, 0, 1 };
    OORendererSetMaterialColor(kOOMaterialFrontAndBack, kOOMaterialAmbient, matAmbient);
    OORendererSetMaterialColor(kOOMaterialFrontAndBack, kOOMaterialDiffuse, matDiffuse);
    OORendererSetMaterialColor(kOOMaterialFrontAndBack, kOOMaterialSpecular, matSpecular);
    OORendererSetMaterialColor(kOOMaterialFrontAndBack, kOOMaterialEmission, black);
    OORendererSetMaterialShininess(kOOMaterialFrontAndBack, 3);
    OORendererSetLightModelSeparateSpecular(true);
    SetLightEnabled(1, true);
    SetMatrices(mv, p);

    OODrawState state = Plain();
    state.depthTest = true;
    state.depthWrite = true;
    state.cullBack = true;
    state.lighting = true;
    state.texture2D = true;
    state.texture = (const void*)(uintptr_t)dark;
    OORendererPushDrawState(&state);
    enum {
        kStacks = 24,
        kSlices = 32
    };
    for (int i = 0; i < kStacks; i++) {
        OOImmediateBegin(kOOPrimitiveTriangleStrip);
        for (int j = 0; j <= kSlices; j++) {
            for (int k = 0; k <= 1; k++) {
                float phi = kPi * ((float)(i + k) / kStacks - 0.5f);
                float theta = 2.0f * kPi * j / kSlices;
                float n[3] = { cosf(phi) * cosf(theta), sinf(phi), cosf(phi) * sinf(theta) };
                OOImmediateTexCoord2f(2.0f * j / kSlices, (float)(i + k) / kStacks);
                OOImmediateNormal3f(n[0], n[1], n[2]);
                OOImmediateVertex3f(n[0], n[1], n[2]);
            }
        }
        OOImmediateEnd();
    }
    OORendererPopDrawState();
    SetLightEnabled(1, false);
    OORendererSetLightModelSeparateSpecular(false);
}

// Linear fog over quads receding from the camera.
static void SceneFog(void)
{
    float mv[16], p[16];
    Identity(mv);
    Perspective(p, 60, 1, 1, 30);
    SetMatrices(mv, p);
    const float fogColor[4] = { 0.4f, 0.5f, 0.7f, 1 };
    OORendererSetFogMode(kOOFogLinear);
    OORendererSetFogColor(fogColor);
    OORendererSetFogRange(2.0f, 20.0f);
    OODrawState state = Plain();
    state.fog = true;
    state.depthTest = true;
    state.depthWrite = true;
    OORendererPushDrawState(&state);
    OOImmediateBegin(kOOPrimitiveQuads);
    for (int i = 0; i < 6; i++) {
        float z = -2.5f - 3.5f * i, x = -3.0f + 1.1f * i;
        OOImmediateColor4f(i % 2 ? 1.0f : 0.2f, 0.9f - 0.12f * i, i % 3 ? 0.3f : 1.0f, 1);
        OOImmediateVertex3f(x, -1.5f, z);
        OOImmediateVertex3f(x + 2.5f, -1.5f, z);
        OOImmediateVertex3f(x + 2.5f, 1.5f, z);
        OOImmediateVertex3f(x, 1.5f, z);
    }
    OOImmediateEnd();
    OORendererPopDrawState();
}

typedef struct {
    const char* name;
    void (*draw)(void);
    float clear[4];
    void (*prepare)(void); // passes into other targets, before the window pass
} Scene;

static const Scene kScenes[] = {
    { "smooth", SceneSmooth, { 0, 0, 0, 1 }, NULL },
    { "flat", SceneFlat, { 0.1f, 0.1f, 0.1f, 1 }, NULL },
    { "blend", SceneBlend, { 0, 0, 0, 1 }, NULL },
    { "depth", SceneDepth, { 0, 0, 0.1f, 1 }, NULL },
    { "cull", SceneCull, { 0, 0, 0, 1 }, NULL },
    { "texture", SceneTexture, { 0, 0, 0, 1 }, NULL },
    { "arrays", SceneArrays, { 0.2f, 0.2f, 0.2f, 1 }, NULL },
    { "lit", SceneLit, { 0, 0, 0, 1 }, NULL },
    { "scissor", SceneScissor, { 0.3f, 0, 0.3f, 1 }, NULL },
    { "target", SceneTarget, { 0, 0, 0, 1 }, PrepareTarget },
    { "msaa", SceneMSAA, { 0, 0, 0, 1 }, PrepareMSAA },
    { "mrt", SceneMRT, { 0, 0, 0, 1 }, PrepareMRT },
    { "program", SceneProgram, { 0, 0, 0, 1 }, NULL },
    { "specular", SceneSpecular, { 0, 0, 0, 1 }, NULL },
    { "fog", SceneFog, { 0, 0, 0, 1 }, NULL },
};

static bool Save(const char* dir, const char* name, const uint8_t* bgraBottomUp)
{
    SDL_Surface* surface = SDL_CreateSurface(kSize, kSize, SDL_PIXELFORMAT_BGRA32);
    for (int row = 0; row < kSize; row++)
        memcpy((uint8_t*)surface->pixels + row * surface->pitch, bgraBottomUp + (size_t)(kSize - 1 - row) * kSize * 4, kSize * 4);
    char path[1024];
    snprintf(path, sizeof path, "%s/%s.bmp", dir, name);
    bool ok = SDL_SaveBMP(surface, path);
    SDL_DestroySurface(surface);
    return ok;
}

int main(int argc, char* argv[])
{
    if (argc < 2) {
        fprintf(stderr, "usage: %s <output dir>\n", argv[0]);
        return 2;
    }
    if (!SDL_Init(SDL_INIT_VIDEO)) {
        fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
        return 2;
    }
#if OO_BACKEND_GPU
    SDL_GPUDevice* device = SDL_CreateGPUDevice(SDL_GPU_SHADERFORMAT_MSL | SDL_GPU_SHADERFORMAT_SPIRV, true, NULL);
    if (device == NULL || !OORendererSDLGPUInit(device, kSize, kSize)) {
        fprintf(stderr, "SDL_GPU: %s\n", SDL_GetError());
        return 2;
    }
    printf("SDL_GPU driver: %s\n", SDL_GetGPUDeviceDriver(device));
#else
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1);
    SDL_Window* window = SDL_CreateWindow("oogpu-backend-test", 64, 64, SDL_WINDOW_OPENGL | SDL_WINDOW_HIDDEN);
    SDL_GLContext context = window ? SDL_GL_CreateContext(window) : NULL;
    if (context == NULL) {
        fprintf(stderr, "GL context: %s\n", SDL_GetError());
        return 2;
    }
    printf("GL renderer: %s\n", (const char*)glGetString(GL_RENDERER));
    GLuint fbo, color, depth;
    glGenFramebuffersEXT(1, &fbo);
    glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, fbo);
    glGenRenderbuffersEXT(1, &color);
    glBindRenderbufferEXT(GL_RENDERBUFFER_EXT, color);
    glRenderbufferStorageEXT(GL_RENDERBUFFER_EXT, GL_RGBA8, kSize, kSize);
    glFramebufferRenderbufferEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_RENDERBUFFER_EXT, color);
    glGenRenderbuffersEXT(1, &depth);
    glBindRenderbufferEXT(GL_RENDERBUFFER_EXT, depth);
    glRenderbufferStorageEXT(GL_RENDERBUFFER_EXT, GL_DEPTH_COMPONENT24, kSize, kSize);
    glFramebufferRenderbufferEXT(GL_FRAMEBUFFER_EXT, GL_DEPTH_ATTACHMENT_EXT, GL_RENDERBUFFER_EXT, depth);
    OORendererSetWindowTarget(fbo);
    glDisable(GL_DITHER);
#endif
    SetViewport(0, 0, kSize, kSize);

    uint8_t* pixels = malloc(kSize * kSize * 4);
    int failures = 0;
    for (size_t i = 0; i < sizeof kScenes / sizeof *kScenes; i++) {
        const Scene* scene = &kScenes[i];
        if (scene->prepare != NULL)
            scene->prepare();
        OORendererSetClearColor(scene->clear[0], scene->clear[1], scene->clear[2], scene->clear[3]);
        OORendererSetClearDepth(1.0f);
        OORendererBeginPass(&(OORenderPassDescriptor) { .target = OORendererWindowTarget(), .colorLoad = kOOLoadClear, .depthLoad = kOOLoadClear });
        scene->draw();
        OORendererEndPass();
        OORendererReadPixels(0, 0, kSize, kSize, kOOPixelsBGRA8, pixels);
        if (!Save(argv[1], scene->name, pixels))
            failures++;
    }
    printf("%zu scenes drawn, %u renderer warnings\n", sizeof kScenes / sizeof *kScenes, sWarnings);
    free(pixels);
    return failures != 0 || sWarnings != 0;
}
