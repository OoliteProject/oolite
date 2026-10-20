/*

oogpu-immediate-test.c

Checks the renderer layer's immediate-mode replacement (src/Core/Renderer)
against real OpenGL immediate mode. Each case is drawn once with
glBegin()/glEnd() and once through OOImmediateBegin()/OOImmediateEnd() on
the OpenGL backend, which expands the primitive and draws from vertex
arrays, and the two images are compared.

Usage: oogpu-immediate-test [<image dir>]
       oogpu-immediate-test --bench
With an image directory, writes <case>-gl.png and <case>-oo.png for
failures. --bench times text-like batches (eight textured glyph quads, one
colour) drawn both ways.


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

#define GL_GLEXT_PROTOTYPES 1
#define GL_SILENCE_DEPRECATION 1

#include "OOFixedFunction.h"
#include "OOImmediateMode.h"
#include "OORenderPass.h"
#include "OORenderState.h"
#include "OORenderStateMachine.h"
#include "OORendererTexture.h"
#include "OOVertexArray.h"

#include <SDL3/SDL.h>
#include <SDL3/SDL_opengl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
    kSize = 256
};

void OORendererBackendWarn(const char* message);

static unsigned sWarnings = 0;
static bool sExpectWarnings = false;

void OORendererBackendWarn(const char* message)
{
    if (!sExpectWarnings)
        fprintf(stderr, "renderer warning: %s\n", message);
    sWarnings++;
}

/*  Texture glue: the game passes OOTextures; here a "texture" is a GL
    texture name cast to a pointer.
*/
void OORendererBackendVerifyStateMachine(void);
void OORendererBackendVerifyStateMachine(void)
{
    // The game checks this against GL; the harness drives GL directly.
}

void OORendererBackendApplyTexture(const void* texture);
unsigned OORendererBackendTextureName(const void* texture);
void OORendererBackendSaveTexture(int depth);
void OORendererBackendRestoreTexture(int depth);
static GLint sSavedBinding[16];

void OORendererBackendApplyTexture(const void* texture)
{
    glBindTexture(GL_TEXTURE_2D, (GLuint)(uintptr_t)texture);
}

unsigned OORendererBackendTextureName(const void* texture)
{
    return (unsigned)(uintptr_t)texture;
}

void OORendererBackendSaveTexture(int depth)
{
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &sSavedBinding[depth]);
}

void OORendererBackendRestoreTexture(int depth)
{
    glBindTexture(GL_TEXTURE_2D, (GLuint)sSavedBinding[depth]);
}

typedef struct {
    float x, y, s, t;
    float color[4];
} TestVertex;

typedef struct {
    const char* name;
    GLenum glMode;
    OOPrimitive ooPrimitive;
    TestVertex vertices[32];
    int count;
} TestShape;

// Distinct colour per vertex so the triangulation shows in smooth shading.
static void Color(int i, float out[4])
{
    out[0] = 0.5f + 0.5f * sinf(1.7f * i);
    out[1] = 0.5f + 0.5f * sinf(2.3f * i + 1.0f);
    out[2] = 0.5f + 0.5f * sinf(3.1f * i + 2.0f);
    out[3] = 1.0f;
}

static void AddVertex(TestShape* shape, float x, float y)
{
    TestVertex* v = &shape->vertices[shape->count];
    v->x = x;
    v->y = y;
    v->s = x / kSize * 3.0f;
    v->t = y / kSize * 3.0f;
    Color(shape->count, v->color);
    shape->count++;
}

static int BuildShapes(TestShape* shapes)
{
    int n = 0;
    TestShape* s;
    const float c = kSize / 2.0f;

    s = &shapes[n++];
    *s = (TestShape) { .name = "points", .glMode = GL_POINTS, .ooPrimitive = kOOPrimitivePoints };
    for (int i = 0; i < 12; i++)
        AddVertex(s, 20 + 18 * i, 30 + 15 * (i % 5));

    s = &shapes[n++];
    *s = (TestShape) { .name = "lines", .glMode = GL_LINES, .ooPrimitive = kOOPrimitiveLines };
    for (int i = 0; i < 11; i++) // odd count: last vertex dropped
        AddVertex(s, 20 + 20 * i, (i % 2) ? 220 : 30);

    s = &shapes[n++];
    *s = (TestShape) { .name = "line_strip", .glMode = GL_LINE_STRIP, .ooPrimitive = kOOPrimitiveLineStrip };
    for (int i = 0; i < 9; i++)
        AddVertex(s, 20 + 26 * i, (i % 2) ? 200 : 50);

    s = &shapes[n++];
    *s = (TestShape) { .name = "line_loop", .glMode = GL_LINE_LOOP, .ooPrimitive = kOOPrimitiveLineLoop };
    for (int i = 0; i < 7; i++)
        AddVertex(s, c + 100 * cosf(i * 0.9f), c + 90 * sinf(i * 0.9f));

    s = &shapes[n++];
    *s = (TestShape) { .name = "triangles", .glMode = GL_TRIANGLES, .ooPrimitive = kOOPrimitiveTriangles };
    for (int i = 0; i < 4; i++) {
        AddVertex(s, 20 + 55 * i, 30);
        AddVertex(s, 60 + 55 * i, 40);
        AddVertex(s, 35 + 55 * i, 200);
    }

    s = &shapes[n++];
    *s = (TestShape) { .name = "triangle_strip", .glMode = GL_TRIANGLE_STRIP, .ooPrimitive = kOOPrimitiveTriangleStrip };
    for (int i = 0; i < 10; i++)
        AddVertex(s, 20 + 24 * i, (i % 2) ? 210 : 40);

    s = &shapes[n++];
    *s = (TestShape) { .name = "triangle_fan", .glMode = GL_TRIANGLE_FAN, .ooPrimitive = kOOPrimitiveTriangleFan };
    AddVertex(s, c, c);
    for (int i = 0; i < 9; i++)
        AddVertex(s, c + 110 * cosf(i * 0.7f), c + 110 * sinf(i * 0.7f));

    s = &shapes[n++];
    *s = (TestShape) { .name = "quads", .glMode = GL_QUADS, .ooPrimitive = kOOPrimitiveQuads };
    for (int i = 0; i < 3; i++) {
        float x = 15 + 80 * i;
        // Not parallelograms, so the diagonal matters.
        AddVertex(s, x, 30);
        AddVertex(s, x + 70, 50);
        AddVertex(s, x + 60, 220);
        AddVertex(s, x + 5, 180);
    }

    s = &shapes[n++];
    *s = (TestShape) { .name = "quad_strip", .glMode = GL_QUAD_STRIP, .ooPrimitive = kOOPrimitiveQuadStrip };
    for (int i = 0; i < 6; i++) {
        AddVertex(s, 20 + 44 * i, 40 + 10 * (i % 3));
        AddVertex(s, 30 + 44 * i, 210 - 15 * (i % 2));
    }

    s = &shapes[n++];
    *s = (TestShape) { .name = "polygon", .glMode = GL_POLYGON, .ooPrimitive = kOOPrimitivePolygon };
    for (int i = 0; i < 8; i++)
        AddVertex(s, c + 110 * cosf(i * 0.785f), c + 100 * sinf(i * 0.785f));

    return n;
}

typedef struct {
    bool flat;
    bool textured;
    float lineWidth;
    bool smooth; // GL_LINE_SMOOTH and GL_POINT_SMOOTH with blending, as the game uses
} Variant;

static void SetCapability(GLenum capability, bool enabled)
{
    if (enabled)
        glEnable(capability);
    else
        glDisable(capability);
}

static void DrawGL(const TestShape* shape)
{
    glBegin(shape->glMode);
    for (int i = 0; i < shape->count; i++) {
        const TestVertex* v = &shape->vertices[i];
        glColor4fv(v->color);
        glTexCoord2f(v->s, v->t);
        glVertex3f(v->x, v->y, 0.0f);
    }
    glEnd();
}

static void DrawOO(const TestShape* shape)
{
    OOImmediateBegin(shape->ooPrimitive);
    for (int i = 0; i < shape->count; i++) {
        const TestVertex* v = &shape->vertices[i];
        OOImmediateColor4fv(v->color);
        OOImmediateTexCoord2f(v->s, v->t);
        OOImmediateVertex3f(v->x, v->y, 0.0f);
    }
    OOImmediateEnd();
}

/*  GL leaves the diagonal a smooth-shaded quad is split along up to the
    implementation; only winding and the flat-shading provoking vertex are
    defined. OOImmediate splits along 1-3 (as Apple's GL does); Mesa splits
    along 0-2. This draws the 0-2 split, to tell the two apart.
*/
static void DrawOOQuadsAlternateDiagonal(const TestShape* shape)
{
    static const int kOrder[6] = { 0, 1, 2, 0, 2, 3 };
    OOImmediateBegin(kOOPrimitiveTriangles);
    for (int q = 0; q + 3 < shape->count; q += 4) {
        for (int k = 0; k < 6; k++) {
            const TestVertex* v = &shape->vertices[q + kOrder[k]];
            OOImmediateColor4fv(v->color);
            OOImmediateTexCoord2f(v->s, v->t);
            OOImmediateVertex3f(v->x, v->y, 0.0f);
        }
    }
    OOImmediateEnd();
}

typedef enum {
    kDrawGL,
    kDrawOO,
    kDrawOOAlternateDiagonal,
    kDrawOOArrays, // OORendererDrawPrimitive from buffers
    kDrawOOElements, // OORendererDrawPrimitiveElements, 16-bit indices
} DrawMode;

static void DrawOOArrays(const TestShape* shape, bool indexed)
{
    float positions[32 * 3], colors[32 * 4], texCoords[32 * 2];
    uint16_t indices[32];
    for (int i = 0; i < shape->count; i++) {
        positions[i * 3] = shape->vertices[i].x;
        positions[i * 3 + 1] = shape->vertices[i].y;
        positions[i * 3 + 2] = 0;
        memcpy(&colors[i * 4], shape->vertices[i].color, 4 * sizeof(float));
        texCoords[i * 2] = shape->vertices[i].s;
        texCoords[i * 2 + 1] = shape->vertices[i].t;
        indices[i] = (uint16_t)i;
    }
    OOVertexLayout layout = { .count = 0 };
    OOVertexLayoutAdd(&layout, kOOVertexPosition, 0, 3, 0, OORendererTransientBuffer(positions, sizeof positions), 0);
    OOVertexLayoutAdd(&layout, kOOVertexColor, 0, 4, 0, OORendererTransientBuffer(colors, sizeof colors), 0);
    OOVertexLayoutAdd(&layout, kOOVertexTexCoord, 0, 2, 0, OORendererTransientBuffer(texCoords, sizeof texCoords), 0);
    if (indexed)
        OORendererDrawPrimitiveElements(shape->ooPrimitive, &layout, OORendererTransientBuffer(indices, sizeof indices), 0, kOOIndex16, (size_t)shape->count);
    else
        OORendererDrawPrimitive(shape->ooPrimitive, &layout, 0, (size_t)shape->count);
}

static void Render(const TestShape* shape, const Variant* variant, DrawMode mode, uint8_t* pixels)
{
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    glShadeModel(variant->flat ? GL_FLAT : GL_SMOOTH);
    glLineWidth(variant->lineWidth);
    glPointSize(variant->lineWidth * 2.0f);
    if (variant->smooth) {
        glEnable(GL_LINE_SMOOTH);
        glEnable(GL_POINT_SMOOTH);
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    } else {
        glDisable(GL_LINE_SMOOTH);
        glDisable(GL_POINT_SMOOTH);
        glDisable(GL_BLEND);
    }
    if (variant->textured)
        glEnable(GL_TEXTURE_2D);
    else
        glDisable(GL_TEXTURE_2D);
    if (mode == kDrawOO)
        DrawOO(shape);
    else if (mode == kDrawOOArrays || mode == kDrawOOElements)
        DrawOOArrays(shape, mode == kDrawOOElements);
    else if (mode == kDrawOOAlternateDiagonal)
        DrawOOQuadsAlternateDiagonal(shape);
    else
        DrawGL(shape);
    glFinish();
    glReadPixels(0, 0, kSize, kSize, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
}

static unsigned CountDifferences(const uint8_t* a, const uint8_t* b, int* outMax, unsigned* outLit)
{
    unsigned differing = 0, lit = 0;
    int maxDiff = 0;
    for (int i = 0; i < kSize * kSize; i++) {
        int pixelMax = 0;
        for (int ch = 0; ch < 3; ch++) {
            int d = abs((int)a[i * 4 + ch] - (int)b[i * 4 + ch]);
            if (d > pixelMax)
                pixelMax = d;
        }
        if (pixelMax > maxDiff)
            maxDiff = pixelMax;
        if (pixelMax > 2)
            differing++;
        if (a[i * 4] | a[i * 4 + 1] | a[i * 4 + 2])
            lit++;
    }
    *outMax = maxDiff;
    *outLit = lit;
    return differing;
}

static void Save(const uint8_t* pixels, const char* dir, const char* name, const char* suffix)
{
    char path[1024];
    snprintf(path, sizeof path, "%s/%s-%s.png", dir, name, suffix);
    SDL_Surface* surface = SDL_CreateSurfaceFrom(kSize, kSize, SDL_PIXELFORMAT_RGBA32, (void*)pixels, kSize * 4);
    SDL_FlipSurface(surface, SDL_FLIP_VERTICAL);
#if SDL_VERSION_ATLEAST(3, 4, 0)
    SDL_SavePNG(surface, path);
#else
    path[strlen(path) - 3] = '\0';
    strcat(path, "bmp");
    SDL_SaveBMP(surface, path);
#endif
    SDL_DestroySurface(surface);
}

static double Bench(bool useOO, int batches)
{
    glEnable(GL_TEXTURE_2D);
    glFinish();
    Uint64 start = SDL_GetTicksNS();
    for (int b = 0; b < batches; b++) {
        float x = (float)(b % 32) * 8.0f, y = (float)((b / 32) % 32) * 8.0f;
        if (useOO) {
            OOImmediateColor4f(1.0f, 0.8f, 0.2f, 1.0f);
            OOImmediateBegin(kOOPrimitiveQuads);
            for (int g = 0; g < 8; g++) {
                float gx = x + g;
                OOImmediateTexCoord2f(0.0f, 0.0f);
                OOImmediateVertex3f(gx, y, 0.0f);
                OOImmediateTexCoord2f(0.1f, 0.0f);
                OOImmediateVertex3f(gx + 1, y, 0.0f);
                OOImmediateTexCoord2f(0.1f, 0.1f);
                OOImmediateVertex3f(gx + 1, y + 1, 0.0f);
                OOImmediateTexCoord2f(0.0f, 0.1f);
                OOImmediateVertex3f(gx, y + 1, 0.0f);
            }
            OOImmediateEnd();
        } else {
            glColor4f(1.0f, 0.8f, 0.2f, 1.0f);
            glBegin(GL_QUADS);
            for (int g = 0; g < 8; g++) {
                float gx = x + g;
                glTexCoord2f(0.0f, 0.0f);
                glVertex3f(gx, y, 0.0f);
                glTexCoord2f(0.1f, 0.0f);
                glVertex3f(gx + 1, y, 0.0f);
                glTexCoord2f(0.1f, 0.1f);
                glVertex3f(gx + 1, y + 1, 0.0f);
                glTexCoord2f(0.0f, 0.1f);
                glVertex3f(gx, y + 1, 0.0f);
            }
            glEnd();
        }
    }
    glFinish();
    return (double)(SDL_GetTicksNS() - start) / 1e6;
}

int main(int argc, char* argv[])
{
    bool bench = argc > 1 && strcmp(argv[1], "--bench") == 0;
    const char* imageDir = argc > 1 && !bench ? argv[1] : NULL;
    if (!SDL_Init(SDL_INIT_VIDEO)) {
        fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
        return 2;
    }
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1);
    SDL_Window* window = SDL_CreateWindow("oogpu-immediate-test", 64, 64, SDL_WINDOW_OPENGL | SDL_WINDOW_HIDDEN);
    SDL_GLContext context = window ? SDL_GL_CreateContext(window) : NULL;
    if (context == NULL) {
        fprintf(stderr, "GL context: %s\n", SDL_GetError());
        return 2;
    }
    printf("GL renderer: %s\n", (const char*)glGetString(GL_RENDERER));

    GLuint fbo, color;
    glGenFramebuffersEXT(1, &fbo);
    glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, fbo);
    glGenRenderbuffersEXT(1, &color);
    glBindRenderbufferEXT(GL_RENDERBUFFER_EXT, color);
    glRenderbufferStorageEXT(GL_RENDERBUFFER_EXT, GL_RGBA8, kSize, kSize);
    glFramebufferRenderbufferEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_RENDERBUFFER_EXT, color);
    glViewport(0, 0, kSize, kSize);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrtho(0, kSize, 0, kSize, -1, 1);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    // A checkerboard texture, so texture co-ordinates show.
    uint8_t checker[16 * 16 * 4];
    for (int i = 0; i < 16 * 16; i++) {
        uint8_t v = ((i % 16) / 4 + (i / 16) / 4) % 2 ? 255 : 90;
        checker[i * 4] = checker[i * 4 + 1] = checker[i * 4 + 2] = v;
        checker[i * 4 + 3] = 255;
    }
    GLuint texture;
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 16, 16, 0, GL_RGBA, GL_UNSIGNED_BYTE, checker);
    glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);

    if (bench) {
        // A busy HUD frame has a few hundred batches; time many frames' worth.
        const int batches = 200000;
        Bench(false, 1000);
        Bench(true, 1000);
        double glTime = Bench(false, batches), ooTime = Bench(true, batches);
        printf("%d batches: GL immediate mode %.1f ms (%.2f us/batch), OOImmediate %.1f ms (%.2f us/batch)\n",
            batches, glTime, 1000.0 * glTime / batches, ooTime, 1000.0 * ooTime / batches);
        SDL_GL_DestroyContext(context);
        SDL_DestroyWindow(window);
        SDL_Quit();
        return 0;
    }

    static TestShape shapes[16];
    int shapeCount = BuildShapes(shapes);
    const Variant variants[] = {
        { false, false, 1.0f, false },
        { true, false, 1.0f, false },
        { false, true, 1.0f, false },
        { true, true, 3.0f, false },
        { false, false, 1.0f, true },
        { false, false, 2.0f, true },
    };
    static const char* const kVariantNames[] = { "smooth", "flat", "textured", "flat_textured_wide", "antialiased", "antialiased_wide" };

    uint8_t* glPixels = malloc(kSize * kSize * 4);
    uint8_t* ooPixels = malloc(kSize * kSize * 4);
    int failures = 0, total = 0;
    for (int v = 0; v < (int)(sizeof variants / sizeof *variants); v++) {
        for (int s = 0; s < shapeCount; s++) {
            Render(&shapes[s], &variants[v], kDrawGL, glPixels);
            Render(&shapes[s], &variants[v], kDrawOO, ooPixels);
            int maxDiff;
            unsigned lit;
            unsigned differing = CountDifferences(glPixels, ooPixels, &maxDiff, &lit);
            const char* status = "OK";
            if (differing > 0 && shapes[s].ooPrimitive == kOOPrimitiveQuads && !variants[v].flat) {
                // Implementation-defined; accept the other diagonal too.
                uint8_t* altPixels = malloc(kSize * kSize * 4);
                int altMax;
                unsigned altLit;
                Render(&shapes[s], &variants[v], kDrawOOAlternateDiagonal, altPixels);
                if (CountDifferences(glPixels, altPixels, &altMax, &altLit) == 0) {
                    status = "OK02";
                    differing = 0;
                    maxDiff = altMax;
                }
                free(altPixels);
            }
            // The same through the vertex-array paths.
            for (DrawMode arrayMode = kDrawOOArrays; arrayMode <= kDrawOOElements; arrayMode++) {
                Render(&shapes[s], &variants[v], arrayMode, ooPixels);
                int arrayMax;
                unsigned arrayLit, arrayDiffering = CountDifferences(glPixels, ooPixels, &arrayMax, &arrayLit);
                if (arrayDiffering > 0 && strcmp(status, "OK02") == 0)
                    arrayDiffering = 0; // the driver's other diagonal, as above
                if (arrayDiffering > 0) {
                    printf("DIFF %-16s %-20s through %s: differing %u\n", shapes[s].name, kVariantNames[v],
                        arrayMode == kDrawOOArrays ? "OORendererDrawPrimitive" : "OORendererDrawPrimitiveElements", arrayDiffering);
                    failures++;
                }
            }
            total++;
            // An empty reference image would make the comparison meaningless.
            bool ok = differing == 0 && lit > 0;
            if (!ok)
                status = "DIFF";
            if (!ok) {
                failures++;
                if (imageDir != NULL) {
                    char name[128];
                    snprintf(name, sizeof name, "%s_%s", shapes[s].name, kVariantNames[v]);
                    Save(glPixels, imageDir, name, "gl");
                    Save(ooPixels, imageDir, name, "oo");
                }
            }
            printf("%-4s %-16s %-20s lit %6u  max %3d  differing %u\n", status, shapes[s].name, kVariantNames[v], lit, maxDiff, differing);
        }
    }

    /*  Draw state: a pushed overlay state with a texture and a scissor draws
        what the equivalent raw GL state draws, and popping restores whatever
        was there before, however unusual.
    */
    {
        const TestShape* quads = &shapes[7];
        // Flat shading: smooth quads hit the driver's choice of diagonal.
        glShadeModel(GL_FLAT);
        glDisable(GL_LINE_SMOOTH);
        glDisable(GL_POINT_SMOOTH);
        glDisable(GL_BLEND);
        glDisable(GL_TEXTURE_2D);
        glDisable(GL_SCISSOR_TEST);
        glBindTexture(GL_TEXTURE_2D, 0);
        glClearColor(0, 0, 0, 1);
        glClear(GL_COLOR_BUFFER_BIT);
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glEnable(GL_TEXTURE_2D);
        glBindTexture(GL_TEXTURE_2D, texture);
        glEnable(GL_SCISSOR_TEST);
        glScissor(40, 30, 150, 170);
        DrawGL(quads);
        glFinish();
        glReadPixels(0, 0, kSize, kSize, GL_RGBA, GL_UNSIGNED_BYTE, glPixels);

        // Something unlike the overlay state, which the pop must restore.
        glDisable(GL_SCISSOR_TEST);
        glDisable(GL_TEXTURE_2D);
        glBindTexture(GL_TEXTURE_2D, 0);
        glEnable(GL_BLEND);
        glBlendFunc(GL_ONE, GL_ONE);
        glEnable(GL_DEPTH_TEST);
        glDepthMask(GL_FALSE);
        glEnable(GL_CULL_FACE);
        glCullFace(GL_FRONT);
        glScissor(1, 2, 3, 4);
        glClearColor(0, 0, 0, 1);
        glClear(GL_COLOR_BUFFER_BIT);
        OODrawState state = OODrawStateForPreset(kOODrawStateOverlay);
        state.texture2D = true;
        state.texture = (const void*)(uintptr_t)texture;
        state.scissor = true;
        state.scissorRect[0] = 40;
        state.scissorRect[1] = 30;
        state.scissorRect[2] = 150;
        state.scissorRect[3] = 170;
        OORendererPushDrawState(&state);
        OODrawState inner = OODrawStateForPreset(kOODrawStateOpaque); // nested, popped straight away
        OORendererPushDrawState(&inner);
        OORendererPopDrawState();
        DrawOO(quads);
        OORendererPopDrawState();
        glFinish();
        glReadPixels(0, 0, kSize, kSize, GL_RGBA, GL_UNSIGNED_BYTE, ooPixels);
        int maxDiff;
        unsigned lit, differing = CountDifferences(glPixels, ooPixels, &maxDiff, &lit);
        bool drawOK = differing == 0 && lit > 0;

        GLint src, dst, cullMode, box[4], binding;
        GLboolean depthMask;
        glGetIntegerv(GL_BLEND_SRC, &src);
        glGetIntegerv(GL_BLEND_DST, &dst);
        glGetIntegerv(GL_CULL_FACE_MODE, &cullMode);
        glGetIntegerv(GL_SCISSOR_BOX, box);
        glGetIntegerv(GL_TEXTURE_BINDING_2D, &binding);
        glGetBooleanv(GL_DEPTH_WRITEMASK, &depthMask);
        bool restored = glIsEnabled(GL_BLEND) && src == GL_ONE && dst == GL_ONE && glIsEnabled(GL_DEPTH_TEST)
            && !depthMask && glIsEnabled(GL_CULL_FACE) && cullMode == GL_FRONT && !glIsEnabled(GL_SCISSOR_TEST)
            && !glIsEnabled(GL_TEXTURE_2D) && binding == 0 && box[0] == 1 && box[3] == 4;
        glDisable(GL_DEPTH_TEST);
        glDisable(GL_CULL_FACE);
        glCullFace(GL_BACK);
        glDepthMask(GL_TRUE);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glDisable(GL_BLEND);

        // A raw GL change inside the scope must be reported.
        unsigned before = sWarnings;
        sExpectWarnings = true;
        OORendererPushDrawState(&state);
        glDisable(GL_BLEND);
        DrawOO(quads);
        OORendererPopDrawState();
        sExpectWarnings = false;
        bool reported = sWarnings > before;
        sWarnings = before;

        printf("%-4s pushed draw state draws like raw GL (lit %u, differing %u)\n", drawOK ? "OK" : "DIFF", lit, differing);
        printf("%-4s popping restores the previous GL state\n", restored ? "OK" : "FAIL");
        printf("%-4s raw GL change inside a pushed state is reported\n", reported ? "OK" : "FAIL");
        total += 3;
        failures += !drawOK + !restored + !reported;
    }

    /*  Vertex arrays: drawing from renderer buffers with a layout draws what
        immediate mode draws, and leaves client-array state as it found it.
    */
    {
        const TestShape* strip = &shapes[5];
        float positions[32 * 3], colors[32 * 4], texCoords[32 * 2];
        for (int i = 0; i < strip->count; i++) {
            positions[i * 3] = strip->vertices[i].x;
            positions[i * 3 + 1] = strip->vertices[i].y;
            positions[i * 3 + 2] = 0;
            memcpy(&colors[i * 4], strip->vertices[i].color, 4 * sizeof(float));
            texCoords[i * 2] = strip->vertices[i].s;
            texCoords[i * 2 + 1] = strip->vertices[i].t;
        }
        const Variant textured = { false, true, 1.0f, false };
        Render(strip, &textured, kDrawGL, glPixels);

        OORendererBuffer* posBuffer = OORendererCreateBuffer(positions, sizeof positions);
        OORendererBuffer* colorBuffer = OORendererCreateBuffer(colors, sizeof colors);
        OORendererBuffer* texBuffer = OORendererCreateBuffer(texCoords, sizeof texCoords);
        OOVertexLayout layout = { .count = 0 };
        OOVertexLayoutAdd(&layout, kOOVertexPosition, 0, 3, 0, posBuffer, 0);
        OOVertexLayoutAdd(&layout, kOOVertexColor, 0, 4, 0, colorBuffer, 0);
        OOVertexLayoutAdd(&layout, kOOVertexTexCoord, 0, 2, 0, texBuffer, 0);

        // Odd client state: normal array on, colour off, texture unit 1 active.
        glEnableClientState(GL_NORMAL_ARRAY);
        glNormalPointer(GL_FLOAT, 0, positions);
        glDisableClientState(GL_COLOR_ARRAY);
        glClientActiveTexture(GL_TEXTURE1);
        glClearColor(0, 0, 0, 1);
        glClear(GL_COLOR_BUFFER_BIT);
        glShadeModel(GL_SMOOTH);
        glEnable(GL_TEXTURE_2D);
        OORendererDrawArrays(kOONativePrimitiveTriangleStrip, &layout, 0, (size_t)strip->count);
        glFinish();
        glReadPixels(0, 0, kSize, kSize, GL_RGBA, GL_UNSIGNED_BYTE, ooPixels);
        GLint clientActive;
        glGetIntegerv(GL_CLIENT_ACTIVE_TEXTURE, &clientActive);
        bool stateKept = glIsEnabled(GL_NORMAL_ARRAY) && !glIsEnabled(GL_COLOR_ARRAY) && clientActive == GL_TEXTURE1;
        glClientActiveTexture(GL_TEXTURE0);
        stateKept = stateKept && !glIsEnabled(GL_TEXTURE_COORD_ARRAY) && !glIsEnabled(GL_VERTEX_ARRAY);
        glDisableClientState(GL_NORMAL_ARRAY);
        glDisable(GL_TEXTURE_2D);
        OORendererReleaseBuffer(posBuffer);
        OORendererReleaseBuffer(colorBuffer);
        OORendererReleaseBuffer(texBuffer);

        int maxDiff;
        unsigned lit, differing = CountDifferences(glPixels, ooPixels, &maxDiff, &lit);
        bool drawOK = differing == 0 && lit > 0;
        printf("%-4s vertex-array draw matches immediate mode (lit %u, differing %u)\n", drawOK ? "OK" : "DIFF", lit, differing);
        printf("%-4s vertex-array draw leaves client-array state as it was\n", stateKept ? "OK" : "FAIL");
        total += 2;
        failures += !drawOK + !stateKept;
    }

    /*  Wide lines and large points: GL draws them natively; for SDL_GPU they
        are expanded into triangles on the CPU. Without smoothing GL's shapes
        are specified closely enough to compare covered pixels; with
        smoothing GL's antialiased edges are only approximated. Report the
        overlap (intersection over union) of pixels at least half covered.
        Apple's GL and Mesa both give at least 0.999 without smoothing; a
        perpendicular offset instead of GL's minor-axis rule gives about
        0.98, so the threshold is 0.995.
    */
    {
        static const struct {
            const char* name;
            bool points, smooth, perspective;
            float size;
            double minimumOverlap;
        } kCases[] = {
            { "lines w3", false, false, false, 3.0f, 0.995 },
            { "lines w5", false, false, false, 5.0f, 0.995 },
            { "lines w5 perspective", false, false, true, 5.0f, 0.995 },
            { "lines w4 smooth", false, true, false, 4.0f, 0.75 },
            { "points s6", true, false, false, 6.0f, 0.995 },
            { "points s9 smooth", true, true, false, 9.0f, 0.75 },
        };
        const TestShape* strip = &shapes[2];
        const TestShape* points = &shapes[0];
        const float viewport[4] = { 0, 0, kSize, kSize };
        for (size_t c = 0; c < sizeof kCases / sizeof *kCases; c++) {
            const TestShape* shape = kCases[c].points ? points : strip;
            OOImmediateVertex in[32];
            for (int i = 0; i < shape->count; i++) {
                const TestVertex* v = &shape->vertices[i];
                in[i] = (OOImmediateVertex) { .position = { v->x, v->y, 0 }, .color = { 1, 1, 1, 1 } };
                if (kCases[c].perspective) {
                    // Into a frustum: x, y in [-1, 1] at depths 2 to 4.
                    in[i].position[0] = v->x / kSize * 2 - 1;
                    in[i].position[1] = v->y / kSize * 2 - 1;
                    in[i].position[2] = -2.0f - 2.0f * (float)i / shape->count;
                }
            }
            glMatrixMode(GL_PROJECTION);
            glLoadIdentity();
            if (kCases[c].perspective)
                glFrustum(-0.5, 0.5, -0.5, 0.5, 1.0, 10.0);
            else
                glOrtho(0, kSize, 0, kSize, -1, 1);
            glMatrixMode(GL_MODELVIEW);
            glLoadIdentity();
            float projection[16], mvp[16];
            glGetFloatv(GL_PROJECTION_MATRIX, projection);
            memcpy(mvp, projection, sizeof mvp); // modelview is the identity

            SetCapability(GL_LINE_SMOOTH, kCases[c].smooth);
            SetCapability(GL_POINT_SMOOTH, kCases[c].smooth);
            SetCapability(GL_BLEND, kCases[c].smooth);
            glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
            glLineWidth(kCases[c].size);
            glPointSize(kCases[c].size);
            glShadeModel(GL_SMOOTH);
            glDisable(GL_TEXTURE_2D);
            glClearColor(0, 0, 0, 1);
            glClear(GL_COLOR_BUFFER_BIT);
            glBegin(kCases[c].points ? GL_POINTS : GL_LINE_STRIP);
            glColor4f(1, 1, 1, 1);
            for (int i = 0; i < shape->count; i++)
                glVertex3fv(in[i].position);
            glEnd();
            glFinish();
            glReadPixels(0, 0, kSize, kSize, GL_RGBA, GL_UNSIGNED_BYTE, glPixels);

            static OOImmediateVertex out[32 * 48];
            size_t n = kCases[c].points
                ? OOExpandPointsToTriangles(in, (size_t)shape->count, kCases[c].size, kCases[c].smooth, mvp, viewport, out)
                : OOExpandLinesToTriangles(kOONativePrimitiveLineStrip, in, (size_t)shape->count, kCases[c].size, kCases[c].smooth, mvp, viewport, out);
            glDisable(GL_LINE_SMOOTH);
            glDisable(GL_POINT_SMOOTH);
            glDisable(GL_BLEND);
            glMatrixMode(GL_PROJECTION);
            glLoadIdentity();
            glMatrixMode(GL_MODELVIEW);
            glClear(GL_COLOR_BUFFER_BIT);
            OOImmediateBegin(kOOPrimitiveTriangles);
            for (size_t i = 0; i < n; i++) {
                OOImmediateColor4fv(out[i].color);
                OOImmediateVertex3fv(out[i].position);
            }
            OOImmediateEnd();
            glFinish();
            glReadPixels(0, 0, kSize, kSize, GL_RGBA, GL_UNSIGNED_BYTE, ooPixels);

            unsigned both = 0, either = 0;
            for (int i = 0; i < kSize * kSize; i++) {
                bool a = glPixels[i * 4 + 1] >= 128, b = ooPixels[i * 4 + 1] >= 128;
                both += a && b;
                either += a || b;
            }
            double overlap = either ? (double)both / either : 0;
            bool ok = either > 0 && overlap >= kCases[c].minimumOverlap;
            printf("%-4s CPU-expanded %-22s overlap with GL %.3f (%u px; need %.3f)\n", ok ? "OK" : "FAIL", kCases[c].name, overlap, either, kCases[c].minimumOverlap);
            total++;
            failures += !ok;
        }
        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        glOrtho(0, kSize, 0, kSize, -1, 1);
        glMatrixMode(GL_MODELVIEW);
        glLineWidth(1);
        glPointSize(1);
    }

    /*  Passes: a pass binds its target and clears with the current clear
        values, clearing depth even with depth writes off, which it puts back.
    */
    {
        GLuint depth;
        glGenRenderbuffersEXT(1, &depth);
        glBindRenderbufferEXT(GL_RENDERBUFFER_EXT, depth);
        glRenderbufferStorageEXT(GL_RENDERBUFFER_EXT, GL_DEPTH_COMPONENT24, kSize, kSize);
        glFramebufferRenderbufferEXT(GL_FRAMEBUFFER_EXT, GL_DEPTH_ATTACHMENT_EXT, GL_RENDERBUFFER_EXT, depth);
        glClearDepth(0.25);
        glClear(GL_DEPTH_BUFFER_BIT);
        glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0);
        glDepthMask(GL_FALSE);

        OORendererSetClearColor(0.0f, 0.5f, 1.0f, 1.0f);
        OORendererSetClearDepth(0.75f);
        OORendererBeginPass(&(OORenderPassDescriptor) { .target = fbo, .colorLoad = kOOLoadClear, .depthLoad = kOOLoadClear });
        GLint bound;
        glGetIntegerv(GL_FRAMEBUFFER_BINDING_EXT, &bound);
        OORendererEndPass();
        uint8_t pixel[4];
        float depthValue;
        glReadPixels(5, 5, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
        glReadPixels(5, 5, 1, 1, GL_DEPTH_COMPONENT, GL_FLOAT, &depthValue);
        GLboolean mask;
        glGetBooleanv(GL_DEPTH_WRITEMASK, &mask);

        // A keep-colour pass leaves the colour alone.
        OORendererSetClearColor(1.0f, 0.0f, 0.0f, 1.0f);
        OORendererBeginPass(&(OORenderPassDescriptor) { .target = kOORenderTargetCurrent, .colorLoad = kOOLoadKeep, .depthLoad = kOOLoadClear });
        OORendererEndPass();
        uint8_t kept[4];
        glReadPixels(5, 5, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, kept);
        glDepthMask(GL_TRUE);
        glFramebufferRenderbufferEXT(GL_FRAMEBUFFER_EXT, GL_DEPTH_ATTACHMENT_EXT, GL_RENDERBUFFER_EXT, 0);
        glDeleteRenderbuffersEXT(1, &depth);
        OORendererSetClearColor(0, 0, 0, 1);
        OORendererSetClearDepth(1.0f);

        bool passOK = (GLuint)bound == fbo && pixel[0] == 0 && pixel[1] >= 127 && pixel[1] <= 128 && pixel[2] == 255
            && fabsf(depthValue - 0.75f) < 1e-3f && !mask && kept[0] == 0 && kept[2] == 255;
        printf("%-4s pass binds its target, clears colour and depth, restores the depth mask, keeps colour on request (depth %.3f)\n",
            passOK ? "OK" : "FAIL", depthValue);
        total += 1;
        failures += !passOK;
    }

    /*  Fixed-function values: what GL stores must be the same whether set
        directly or through the renderer, including a light position set
        under a non-trivial modelview.
    */
    {
        float mv[16];
        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
        glTranslatef(3.0f, -2.0f, -7.5f);
        glRotatef(37.0f, 0.3f, 0.8f, 0.5f);
        glScalef(1.0f, 1.5f, 0.75f);
        glGetFloatv(GL_MODELVIEW_MATRIX, mv);
        const float position[4] = { 1.5f, -2.25f, 4.0f, 1.0f };
        const float direction[4] = { -0.6f, 0.5f, 0.8f, 0.0f };
        const float color[4] = { 0.9f, 0.7f, 0.3f, 1.0f };
        float legacy[4][4], viaRenderer[4][4];

        glLightfv(GL_LIGHT1, GL_POSITION, position);
        glLightfv(GL_LIGHT2, GL_POSITION, direction);
        glLightfv(GL_LIGHT1, GL_DIFFUSE, color);
        glGetLightfv(GL_LIGHT1, GL_POSITION, legacy[0]);
        glGetLightfv(GL_LIGHT2, GL_POSITION, legacy[1]);
        glGetLightfv(GL_LIGHT1, GL_DIFFUSE, legacy[2]);
        glLightfv(GL_LIGHT1, GL_POSITION, (const float[4]) { 0, 0, 0, 1 });
        glLightfv(GL_LIGHT2, GL_POSITION, (const float[4]) { 0, 0, 0, 1 });
        glLightfv(GL_LIGHT1, GL_DIFFUSE, (const float[4]) { 0, 0, 0, 1 });

        OORendererSetLightPosition(1, position, mv);
        OORendererSetLightPosition(2, direction, mv);
        OORendererSetLightColor(1, kOOLightDiffuse, color);
        glGetLightfv(GL_LIGHT1, GL_POSITION, viaRenderer[0]);
        glGetLightfv(GL_LIGHT2, GL_POSITION, viaRenderer[1]);
        glGetLightfv(GL_LIGHT1, GL_DIFFUSE, viaRenderer[2]);
        float modelviewAfter[16];
        glGetFloatv(GL_MODELVIEW_MATRIX, modelviewAfter);

        double worst = 0;
        for (int v = 0; v < 3; v++) {
            for (int k = 0; k < 4; k++) {
                double d = fabs((double)legacy[v][k] - viaRenderer[v][k]);
                if (d > worst)
                    worst = d;
            }
        }
        bool modelviewKept = memcmp(mv, modelviewAfter, sizeof mv) == 0;
        bool lightsOK = worst < 1e-5 && modelviewKept;

        const float shine = 12.0f, ambdiff[4] = { 0.4f, 0.5f, 0.6f, 1.0f }, emission[4] = { 0.1f, 0.0f, 0.2f, 1.0f };
        OORendererSetMaterialColor(kOOMaterialFrontAndBack, kOOMaterialAmbientAndDiffuse, ambdiff);
        OORendererSetMaterialColor(kOOMaterialFrontAndBack, kOOMaterialEmission, emission);
        OORendererSetMaterialShininess(kOOMaterialFrontAndBack, shine);
        float gotDiffuse[4], gotEmission[4], gotShine;
        glGetMaterialfv(GL_BACK, GL_DIFFUSE, gotDiffuse);
        glGetMaterialfv(GL_FRONT, GL_EMISSION, gotEmission);
        glGetMaterialfv(GL_FRONT, GL_SHININESS, &gotShine);
        const OOFixedFunctionValues* stored = OORendererGetFixedFunctionValues();
        bool materialOK = memcmp(gotDiffuse, ambdiff, sizeof ambdiff) == 0 && memcmp(gotEmission, emission, sizeof emission) == 0
            && gotShine == shine && memcmp(stored->frontMaterial.ambient, ambdiff, sizeof ambdiff) == 0
            && fabsf(stored->lights[1].position[0] - legacy[0][0]) < 1e-5f;

        const float fogColor[4] = { 0.1f, 0.2f, 0.3f, 1.0f };
        OORendererSetFogMode(kOOFogLinear);
        OORendererSetFogColor(fogColor);
        OORendererSetFogRange(5.0f, 50.0f);
        GLint fogMode;
        float gotFog[4], fogStart, fogEnd;
        glGetIntegerv(GL_FOG_MODE, &fogMode);
        glGetFloatv(GL_FOG_COLOR, gotFog);
        glGetFloatv(GL_FOG_START, &fogStart);
        glGetFloatv(GL_FOG_END, &fogEnd);
        bool fogOK = fogMode == GL_LINEAR && memcmp(gotFog, fogColor, sizeof fogColor) == 0 && fogStart == 5.0f && fogEnd == 50.0f;
        glLoadIdentity();

        printf("%-4s light positions and colours match glLightfv (worst difference %.2g), modelview untouched: %s\n",
            lightsOK ? "OK" : "FAIL", worst, modelviewKept ? "yes" : "no");
        printf("%-4s material values reach GL and the stored copy\n", materialOK ? "OK" : "FAIL");
        printf("%-4s fog values reach GL\n", fogOK ? "OK" : "FAIL");
        total += 3;
        failures += !lightsOK + !materialOK + !fogOK;
    }

    // Render targets: a 4x multisampled target resolves with partial coverage
    // on a triangle's edge; a clear reaches both attachments of an MRT target;
    // resizing keeps the attachment usable; the texture binding is left alone.
    {
        enum {
            kTargetSize = 32
        };
        GLuint bound = 0;
        glGenTextures(1, &bound);
        glBindTexture(GL_TEXTURE_2D, bound);
        OORendererSetTextureBinding(false, bound);

        OORenderTarget msaa = OORendererCreateRenderTarget(&(OORenderTargetDescriptor) { kTargetSize, kTargetSize, 1, true, 4 });
        OORenderTarget resolved = OORendererCreateRenderTarget(&(OORenderTargetDescriptor) { kTargetSize, kTargetSize, 1, true, 1 });
        OORenderTarget mrt = OORendererCreateRenderTarget(&(OORenderTargetDescriptor) { kTargetSize, kTargetSize, 2, false, 1 });
        bool created = msaa != 0 && resolved != 0 && mrt != 0 && OORendererRenderTargetTexture(msaa, 0) == 0
            && OORendererRenderTargetTexture(resolved, 0) != 0 && OORendererRenderTargetTexture(mrt, 1) != 0;

        glViewport(0, 0, kTargetSize, kTargetSize);
        glMatrixMode(GL_PROJECTION);
        glPushMatrix();
        glLoadIdentity();
        glOrtho(0, kTargetSize, 0, kTargetSize, -1, 1);
        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
        SetCapability(GL_TEXTURE_2D, false);
        SetCapability(GL_BLEND, false);
        SetCapability(GL_DEPTH_TEST, false);
        SetCapability(GL_LIGHTING, false);

        float pixels[kTargetSize * kTargetSize * 4];
        OORendererSetClearColor(0.0f, 0.0f, 1.0f, 1.0f);
        OORendererBeginPass(&(OORenderPassDescriptor) { msaa, kOOLoadClear, kOOLoadClear });
        OOImmediateBegin(kOOPrimitiveTriangles);
        OOImmediateColor4f(1.0f, 0.0f, 0.0f, 1.0f);
        OOImmediateVertex2f(0.0f, 0.0f);
        OOImmediateVertex2f(kTargetSize, 0.0f);
        OOImmediateVertex2f(0.0f, kTargetSize);
        OOImmediateEnd();
        OORendererEndPass();
        OORendererResolveRenderTarget(msaa, resolved);
        uint32_t resolvedTexture = OORendererRenderTargetTexture(resolved, 0);
        glBindTexture(GL_TEXTURE_2D, resolvedTexture);
        glGetTexImage(GL_TEXTURE_2D, 0, GL_RGBA, GL_FLOAT, pixels);
        const float* inside = &pixels[(5 * kTargetSize + 5) * 4];
        const float* outside = &pixels[(30 * kTargetSize + 30) * 4];
        float edgeRed = 0.0f;
        // Pixels whose centres lie on the diagonal are partly covered.
        for (int x = 0; x < kTargetSize; x++)
            edgeRed = fmaxf(edgeRed, fminf(pixels[((kTargetSize - 1 - x) * kTargetSize + x) * 4], 1.0f - pixels[((kTargetSize - 1 - x) * kTargetSize + x) * 4]));
        bool resolveOK = inside[0] == 1.0f && inside[2] == 0.0f && outside[0] == 0.0f && outside[2] == 1.0f && edgeRed >= 0.2f;

        OORendererSetClearColor(0.5f, 0.25f, 0.125f, 1.0f);
        OORendererBeginPass(&(OORenderPassDescriptor) { mrt, kOOLoadClear, kOOLoadDontCare });
        OORendererEndPass();
        bool mrtOK = true;
        for (unsigned a = 0; a < 2; a++) {
            glBindTexture(GL_TEXTURE_2D, OORendererRenderTargetTexture(mrt, a));
            glGetTexImage(GL_TEXTURE_2D, 0, GL_RGBA, GL_FLOAT, pixels);
            mrtOK = mrtOK && pixels[0] == 0.5f && pixels[1] == 0.25f && pixels[2] == 0.125f;
        }

        OORendererResizeRenderTarget(mrt, kTargetSize / 2, kTargetSize / 4);
        OORendererSetClearColor(0.75f, 0.0f, 0.0f, 1.0f);
        OORendererBeginPass(&(OORenderPassDescriptor) { mrt, kOOLoadClear, kOOLoadDontCare });
        OORendererEndPass();
        GLint width = 0, height = 0;
        glBindTexture(GL_TEXTURE_2D, OORendererRenderTargetTexture(mrt, 1));
        glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_WIDTH, &width);
        glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_HEIGHT, &height);
        glGetTexImage(GL_TEXTURE_2D, 0, GL_RGBA, GL_FLOAT, pixels);
        bool resizeOK = width == kTargetSize / 2 && height == kTargetSize / 4 && pixels[0] == 0.75f;

        glBindTexture(GL_TEXTURE_2D, bound);
        OORendererDeleteRenderTarget(msaa);
        OORendererDeleteRenderTarget(resolved);
        OORendererDeleteRenderTarget(mrt);
        GLint nowBound;
        glGetIntegerv(GL_TEXTURE_BINDING_2D, &nowBound);
        bool bindingKept = (GLuint)nowBound == bound && OORendererState()->units[0].binding2D == bound;

        glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, fbo);
        glViewport(0, 0, kSize, kSize);
        glMatrixMode(GL_PROJECTION);
        glPopMatrix();
        glMatrixMode(GL_MODELVIEW);
        glBindTexture(GL_TEXTURE_2D, 0);
        OORendererSetTextureBinding(false, 0);
        glDeleteTextures(1, &bound);
        OORendererSetClearColor(0.0f, 0.0f, 0.0f, 0.0f);

        printf("%-4s render targets created (multisampled colour not sampleable)\n", created ? "OK" : "FAIL");
        printf("%-4s 4x MSAA resolve: inside, outside and a partly covered edge (%.2f)\n", resolveOK ? "OK" : "FAIL", edgeRed);
        printf("%-4s a clear reaches both attachments of an MRT target\n", mrtOK ? "OK" : "FAIL");
        printf("%-4s resizing a target (%dx%d), binding kept: %s\n", resizeOK && bindingKept ? "OK" : "FAIL", width, height, bindingKept ? "yes" : "no");
        total += 4;
        failures += !created + !resolveOK + !mrtOK + !(resizeOK && bindingKept);
    }

    // Textures: every format, with mipmaps down to the odd narrow levels whose
    // rows aren't four-byte aligned, and a cube map. Each level reads back as
    // uploaded, and creating or uploading leaves the binding alone.
    {
        static const struct {
            const char* name;
            OOTexelFormat format;
            unsigned components, width, height;
            bool cube;
        } kTextures[] = {
            { "RGBA8 8x4", kOOTexelRGBA8, 4, 8, 4, false },
            { "Gray8 8x8", kOOTexelGray8, 1, 8, 8, false },
            { "Alpha8 4x8", kOOTexelAlpha8, 1, 4, 8, false },
            { "GrayAlpha8 8x8", kOOTexelGrayAlpha8, 2, 8, 8, false },
            { "Gray8 cube 4x4", kOOTexelGray8, 1, 4, 4, true },
            { "RGBA8 cube 4x4", kOOTexelRGBA8, 4, 4, 4, true },
        };
        GLuint bound = 0;
        glGenTextures(1, &bound);
        glBindTexture(GL_TEXTURE_2D, bound);
        OORendererSetTextureBinding(false, bound);
        for (size_t t = 0; t < sizeof kTextures / sizeof *kTextures; t++) {
            OOTextureDescriptor descriptor = { 0 };
            descriptor.cube = kTextures[t].cube;
            descriptor.width = kTextures[t].width;
            descriptor.height = kTextures[t].height;
            descriptor.format = kTextures[t].format;
            descriptor.levels = OOTextureMipLevelCount(descriptor.width, descriptor.height);
            descriptor.minFilter = kOOFilterLinearMipmapLinear;
            descriptor.magFilter = kOOFilterLinear;
            uint32_t texture = OORendererCreateTexture(&descriptor);
            bool ok = texture != 0;
            unsigned faces = descriptor.cube ? 6 : 1;
            uint8_t in[256], out[256 + 16];
            for (unsigned face = 0; face < faces && ok; face++) {
                unsigned w = descriptor.width, h = descriptor.height;
                for (unsigned level = 0; level < descriptor.levels; level++) {
                    size_t size = (size_t)w * h * kTextures[t].components;
                    for (size_t i = 0; i < size; i++)
                        in[i] = (uint8_t)(i * 37 + level * 11 + face * 101 + t);
                    OORendererUploadTexture(texture, face, level, w, h, in);
                    memset(out, 0xEE, sizeof out);
                    OORendererReadTexture(texture, face, level, w, h, out);
                    if (memcmp(in, out, size) != 0 || out[size] != 0xEE)
                        ok = false;
                    w >>= 1;
                    h >>= 1;
                }
            }
            GLint nowBound;
            glGetIntegerv(GL_TEXTURE_BINDING_2D, &nowBound);
            bool bindingKept = (GLuint)nowBound == bound;
            OORendererDeleteTexture(texture);
            printf("%-4s texture %-16s %u level(s) x %u face(s) read back as uploaded, binding kept: %s\n",
                ok && bindingKept ? "OK" : "FAIL", kTextures[t].name, descriptor.levels, faces, bindingKept ? "yes" : "no");
            total++;
            failures += !(ok && bindingKept);
        }
        glBindTexture(GL_TEXTURE_2D, 0);
        OORendererSetTextureBinding(false, 0);
        glDeleteTextures(1, &bound);
    }

    // Interoperation with legacy GL: a colour set through GL is picked up,
    // and OOImmediate's colour is visible to GL afterwards.
    glColor4f(0.25f, 0.5f, 0.75f, 1.0f);
    OOImmediateAttributes attributes = OOImmediateGetAttributes();
    bool interopIn = fabsf(attributes.color[2] - 0.75f) < 0.01f;
    OOImmediateColor4f(0.1f, 0.2f, 0.3f, 1.0f);
    float current[4];
    glGetFloatv(GL_CURRENT_COLOR, current);
    bool interopOut = fabsf(current[2] - 0.3f) < 0.01f;
    printf("%-4s legacy colour picked up\n%-4s colour visible to GL\n", interopIn ? "OK" : "FAIL", interopOut ? "OK" : "FAIL");
    total += 2;
    failures += !interopIn + !interopOut;

    printf("%d/%d cases match, %u renderer warnings\n", total - failures, total, sWarnings);
    printf("(OK02: the driver splits smooth quads along the 0-2 diagonal, not 1-3. GL leaves this to the implementation.)\n");
    SDL_GL_DestroyContext(context);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return failures == 0 && sWarnings == 0 ? 0 : 1;
}
