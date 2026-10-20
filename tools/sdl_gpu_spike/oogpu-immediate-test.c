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

#include "OOImmediateMode.h"

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

void OORendererBackendWarn(const char* message)
{
    fprintf(stderr, "renderer warning: %s\n", message);
    sWarnings++;
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
} Variant;

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
    kDrawOOAlternateDiagonal
} DrawMode;

static void Render(const TestShape* shape, const Variant* variant, DrawMode mode, uint8_t* pixels)
{
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    glShadeModel(variant->flat ? GL_FLAT : GL_SMOOTH);
    glLineWidth(variant->lineWidth);
    glPointSize(variant->lineWidth * 2.0f);
    if (variant->textured)
        glEnable(GL_TEXTURE_2D);
    else
        glDisable(GL_TEXTURE_2D);
    if (mode == kDrawOO)
        DrawOO(shape);
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
        { false, false, 1.0f },
        { true, false, 1.0f },
        { false, true, 1.0f },
        { true, true, 3.0f },
    };
    static const char* const kVariantNames[] = { "smooth", "flat", "textured", "flat_textured_wide" };

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
