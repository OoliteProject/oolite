/*

oogpu-render.c

Renders one lit, textured sphere with an Oolite/OXP shader program twice:
through OpenGL with the original legacy GLSL (the reference, as the game does
today) and through SDL_GPU with the translated shaders. Both images are saved
and compared, to show that the translation preserves what the shader draws.

Usage:
    oogpu-render [options] <vertex|-> <fragment|-> <out prefix>
Options:
    -l <intensity>       sun colour scale; must come first. Ship shaders
                         saturate 8-bit output at 1 without tone mapping
    -p <file>            macro prefix, as OOShaderMaterial passes
    -t <name>=<png>      texture for a sampler uniform (others get white)
    -u <name>=<v,v,...>  value for a float uniform (others are zero, as in GL)
    -i <name>=<n>        value for an int uniform
    -U <v>               value for every other uniform (all components)
    -T <png>             texture for every other 2D sampler
Writes <out prefix>-gl.png and <out prefix>-gpu.png (.bmp with SDL older than
3.4, which also needs textures given as .bmp), and prints the mean and
maximum per-channel difference and the share of pixels that differ by more
than 2/255.


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

#include "OOGPUSpikeCommon.h"

#include <SDL3/SDL_opengl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
    kSize = 512,
    kRings = 48,
    kSegments = 96,
    kTangentAttributeIndex = 15, // As OOShaderMaterial.h
    kMaxValues = 64,
};

#pragma mark - Matrices (column-major, GL conventions)

typedef struct {
    float m[16];
} Mat4;

static Mat4 Identity(void)
{
    Mat4 r = { { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 } };
    return r;
}

static Mat4 Multiply(Mat4 a, Mat4 b)
{
    Mat4 r;
    for (int c = 0; c < 4; c++) {
        for (int row = 0; row < 4; row++) {
            float sum = 0;
            for (int k = 0; k < 4; k++)
                sum += a.m[k * 4 + row] * b.m[c * 4 + k];
            r.m[c * 4 + row] = sum;
        }
    }
    return r;
}

static Mat4 Transpose(Mat4 a)
{
    Mat4 r;
    for (int c = 0; c < 4; c++) {
        for (int row = 0; row < 4; row++)
            r.m[c * 4 + row] = a.m[row * 4 + c];
    }
    return r;
}

static Mat4 Inverse(Mat4 a)
{
    const float* m = a.m;
    float inv[16];
    inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] + m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10];
    inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] - m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10];
    inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] + m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9];
    inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] - m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9];
    inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] - m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10];
    inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] + m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10];
    inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] - m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9];
    inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] + m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9];
    inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] + m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6];
    inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] - m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6];
    inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] + m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5];
    inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] - m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5];
    inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] - m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6];
    inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] + m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6];
    inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] - m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5];
    inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] + m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5];
    float det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];
    Mat4 r;
    for (int i = 0; i < 16; i++)
        r.m[i] = inv[i] / det;
    return r;
}

static Mat4 Perspective(float fovyDegrees, float aspect, float zNear, float zFar)
{
    float f = 1.0f / tanf(fovyDegrees * SDL_PI_F / 360.0f);
    Mat4 r = { { 0 } };
    r.m[0] = f / aspect;
    r.m[5] = f;
    r.m[10] = (zFar + zNear) / (zNear - zFar);
    r.m[11] = -1;
    r.m[14] = 2 * zFar * zNear / (zNear - zFar);
    return r;
}

static Mat4 Rotation(float degrees, float x, float y, float z)
{
    float a = degrees * SDL_PI_F / 180.0f, c = cosf(a), s = sinf(a), t = 1 - c;
    Mat4 r = Identity();
    r.m[0] = t * x * x + c;
    r.m[1] = t * x * y + s * z;
    r.m[2] = t * x * z - s * y;
    r.m[4] = t * x * y - s * z;
    r.m[5] = t * y * y + c;
    r.m[6] = t * y * z + s * x;
    r.m[8] = t * x * z + s * y;
    r.m[9] = t * y * z - s * x;
    r.m[10] = t * z * z + c;
    return r;
}

#pragma mark - Scene

typedef struct {
    float* streams[kOOVertexStreamCount];
    uint32_t vertexCount;
    uint32_t* indices;
    uint32_t indexCount;
} Mesh;

static void BuildSphere(Mesh* mesh)
{
    uint32_t n = (kRings + 1) * (kSegments + 1);
    mesh->vertexCount = n;
    for (int s = 0; s < kOOVertexStreamCount; s++)
        mesh->streams[s] = calloc(n * OOVertexStreamComponents(s), sizeof(float));
    uint32_t v = 0;
    for (int ring = 0; ring <= kRings; ring++) {
        float theta = (float)ring / kRings * SDL_PI_F;
        for (int seg = 0; seg <= kSegments; seg++, v++) {
            float phi = (float)seg / kSegments * 2.0f * SDL_PI_F;
            float x = sinf(theta) * cosf(phi), y = cosf(theta), z = -sinf(theta) * sinf(phi);
            float* p = &mesh->streams[kOOVertexStreamPosition][v * 3];
            float* nrm = &mesh->streams[kOOVertexStreamNormal][v * 3];
            float* uv = &mesh->streams[kOOVertexStreamTexCoord][v * 2];
            float* tan = &mesh->streams[kOOVertexStreamTangent][v * 3];
            float* col = &mesh->streams[kOOVertexStreamColor][v * 4];
            p[0] = nrm[0] = x;
            p[1] = nrm[1] = y;
            p[2] = nrm[2] = z;
            uv[0] = (float)seg / kSegments;
            uv[1] = (float)ring / kRings;
            tan[0] = -sinf(phi);
            tan[1] = 0;
            tan[2] = -cosf(phi);
            col[0] = 1;
            col[1] = 0.8f;
            col[2] = 0.6f;
            col[3] = 1;
        }
    }
    mesh->indexCount = kRings * kSegments * 6;
    mesh->indices = malloc(mesh->indexCount * sizeof(uint32_t));
    uint32_t i = 0;
    for (int ring = 0; ring < kRings; ring++) {
        for (int seg = 0; seg < kSegments; seg++) {
            uint32_t a = ring * (kSegments + 1) + seg, b = a + kSegments + 1;
            // Counter-clockwise when seen from outside.
            mesh->indices[i++] = a;
            mesh->indices[i++] = b;
            mesh->indices[i++] = a + 1;
            mesh->indices[i++] = a + 1;
            mesh->indices[i++] = b;
            mesh->indices[i++] = b + 1;
        }
    }
}

typedef struct {
    char name[128];
    float values[16];
    int count;
    bool isInt;
} Value;

typedef struct {
    char name[128];
    SDL_Surface* image; // RGBA32
} TextureBinding;

typedef struct {
    Mesh mesh;
    Mat4 modelView, projection;
    Value values[kMaxValues];
    int valueCount;
    TextureBinding textures[16];
    int textureCount;
    OOGLSLLegacyStateBlock legacy;
    bool fixedFunctionVertex, fixedFunctionFragment;
    // Used for uniforms and samplers with no explicit value, if set.
    Value defaultValue;
    bool hasDefaultValue;
    SDL_Surface* defaultTexture;
} Scene;

static void AddValue(Scene* scene, const char* name, const float* values, int count, bool isInt)
{
    Value* v = &scene->values[scene->valueCount++];
    SDL_strlcpy(v->name, name, sizeof v->name);
    memcpy(v->values, values, count * sizeof(float));
    v->count = count;
    v->isInt = isInt;
}

static const Value* FindValue(const Scene* scene, const char* name)
{
    // GL reports arrays as "name[0]".
    char base[128];
    SDL_strlcpy(base, name, sizeof base);
    char* bracket = strchr(base, '[');
    if (bracket != NULL)
        *bracket = '\0';
    for (int i = 0; i < scene->valueCount; i++) {
        if (strcmp(scene->values[i].name, base) == 0)
            return &scene->values[i];
    }
    return scene->hasDefaultValue ? &scene->defaultValue : NULL;
}

static const SDL_Surface* FindTexture(const Scene* scene, const char* name)
{
    for (int i = 0; i < scene->textureCount; i++) {
        if (strcmp(scene->textures[i].name, name) == 0)
            return scene->textures[i].image;
    }
    return scene->defaultTexture;
}

static void Mat3Of(Mat4 m, float out[9])
{
    for (int c = 0; c < 3; c++) {
        for (int r = 0; r < 3; r++)
            out[c * 3 + r] = m.m[c * 4 + r];
    }
}

static void Copy4(float* dst, float a, float b, float c, float d)
{
    dst[0] = a;
    dst[1] = b;
    dst[2] = c;
    dst[3] = d;
}

static void SetUpScene(Scene* scene, float sunIntensity)
{
    BuildSphere(&scene->mesh);
    scene->projection = Perspective(40.0f, 1.0f, 0.5f, 10.0f);
    Mat4 translate = Identity();
    translate.m[14] = -3.2f;
    scene->modelView = Multiply(translate, Multiply(Rotation(25.0f, 1, 0, 0), Rotation(-35.0f, 0, 1, 0)));

    // Engine-supplied matrix uniforms (OOOpenGLMatrixManager).
    Mat4 mv = scene->modelView, p = scene->projection, mvp = Multiply(p, mv);
    struct {
        const char* name;
        Mat4 value;
    } matrices[] = {
        { "ooliteModelView", mv },
        { "ooliteProjection", p },
        { "ooliteModelViewProjection", mvp },
        { "ooliteModelViewInverse", Inverse(mv) },
        { "ooliteProjectionInverse", Inverse(p) },
        { "ooliteModelViewProjectionInverse", Inverse(mvp) },
        { "ooliteModelViewTranspose", Transpose(mv) },
        { "ooliteProjectionTranspose", Transpose(p) },
        { "ooliteModelViewProjectionTranspose", Transpose(mvp) },
        { "ooliteModelViewInverseTranspose", Transpose(Inverse(mv)) },
        { "ooliteProjectionInverseTranspose", Transpose(Inverse(p)) },
        { "ooliteModelViewProjectionInverseTranspose", Transpose(Inverse(mvp)) },
    };
    for (size_t i = 0; i < sizeof matrices / sizeof *matrices; i++)
        AddValue(scene, matrices[i].name, matrices[i].value.m, 16, false);
    float normal[9];
    Mat3Of(Transpose(Inverse(mv)), normal);
    AddValue(scene, "ooliteNormalMatrix", normal, 9, false);

    // Legacy state, matching what SetUpGLState() gives OpenGL.
    OOGLSLLegacyStateBlock* L = &scene->legacy;
    memcpy(L->modelViewMatrix, mv.m, sizeof mv.m);
    memcpy(L->projectionMatrix, p.m, sizeof p.m);
    memcpy(L->modelViewProjectionMatrix, mvp.m, sizeof mvp.m);
    memcpy(L->modelViewMatrixInverse, Inverse(mv).m, 64);
    memcpy(L->projectionMatrixInverse, Inverse(p).m, 64);
    memcpy(L->modelViewProjectionMatrixInverse, Inverse(mvp).m, 64);
    memcpy(L->modelViewMatrixTranspose, Transpose(mv).m, 64);
    memcpy(L->modelViewMatrixInverseTranspose, Transpose(Inverse(mv)).m, 64);
    for (int c = 0; c < 3; c++)
        memcpy(&L->normalMatrix[c * 4], &normal[c * 3], 3 * sizeof(float));
    for (int t = 0; t < kOOGLSLMaxTextureCoords; t++)
        memcpy(L->textureMatrix[t], Identity().m, 64);
    for (int i = 0; i < kOOGLSLMaxLights; i++) {
        OOGLSLLightSource* light = &L->lightSource[i];
        Copy4(light->position, 0, 0, 1, 0);
        Copy4(light->halfVector, 0, 0, 1, 0);
        light->spotDirection[2] = -1;
        light->spotCutoff = 180;
        light->spotCosCutoff = -1;
        light->constantAttenuation = 1;
    }
    // GL_LIGHT1 is the sun, as in Universe.m. GL_LIGHT0 is off.
    OOGLSLLightSource* sun = &L->lightSource[1];
    Copy4(sun->ambient, 0.05f, 0.05f, 0.05f, 1);
    Copy4(sun->diffuse, sunIntensity, 0.95f * sunIntensity, 0.85f * sunIntensity, 1);
    Copy4(sun->specular, sunIntensity, sunIntensity, sunIntensity, 1);
    float len = sqrtf(0.6f * 0.6f + 0.5f * 0.5f + 0.8f * 0.8f);
    Copy4(sun->position, -0.6f / len, 0.5f / len, 0.8f / len, 0);
    float h[3] = { sun->position[0], sun->position[1], sun->position[2] + 1 };
    float hl = sqrtf(h[0] * h[0] + h[1] * h[1] + h[2] * h[2]);
    Copy4(sun->halfVector, h[0] / hl, h[1] / hl, h[2] / hl, 0);
    Copy4(L->lightModelAmbient, 0.2f, 0.2f, 0.2f, 1);

    OOGLSLMaterial* mat = &L->frontMaterial;
    Copy4(mat->ambient, 0.8f, 0.8f, 0.8f, 1);
    Copy4(mat->diffuse, 0.8f, 0.8f, 0.8f, 1);
    Copy4(mat->specular, 0.5f, 0.5f, 0.5f, 1);
    Copy4(mat->emission, 0, 0, 0, 1);
    mat->shininess = 20;
    for (int k = 0; k < 4; k++) {
        L->frontLightModelProductSceneColor[k] = mat->emission[k] + mat->ambient[k] * L->lightModelAmbient[k];
        for (int i = 0; i < kOOGLSLMaxLights; i++) {
            L->frontLightProduct[i].ambient[k] = mat->ambient[k] * L->lightSource[i].ambient[k];
            L->frontLightProduct[i].diffuse[k] = mat->diffuse[k] * L->lightSource[i].diffuse[k];
            L->frontLightProduct[i].specular[k] = mat->specular[k] * L->lightSource[i].specular[k];
        }
    }
    // GL's fixed-function alpha is the material diffuse alpha; GL's
    // derived scene colour alpha is likewise the diffuse alpha.
    L->frontLightModelProductSceneColor[3] = mat->diffuse[3];
    Copy4(L->fogColor, 0, 0, 0, 0);
    L->fogDensity = 1;
    L->fogEnd = 1;
    L->fogScale = 1;
    L->viewportHeight = kSize;
    L->pointSize = 1;
}

#pragma mark - OpenGL reference

static GLuint CompileGL(GLenum type, const char* prefix, const char* source)
{
    const char* strings[3] = { prefix ? prefix : "", "#line 0\n", source };
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 3, strings, NULL);
    glCompileShader(shader);
    GLint ok = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[4096];
        glGetShaderInfoLog(shader, sizeof log, NULL, log);
        fprintf(stderr, "GL compile failed:\n%s\n", log);
        return 0;
    }
    return shader;
}

static GLuint UploadGLTexture(const SDL_Surface* image, bool cube)
{
    static const uint8_t white[4] = { 255, 255, 255, 255 };
    GLuint texture;
    glGenTextures(1, &texture);
    GLenum target = cube ? GL_TEXTURE_CUBE_MAP : GL_TEXTURE_2D;
    glBindTexture(target, texture);
    glTexParameteri(target, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(target, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(target, GL_TEXTURE_WRAP_S, cube ? GL_CLAMP_TO_EDGE : GL_REPEAT);
    glTexParameteri(target, GL_TEXTURE_WRAP_T, cube ? GL_CLAMP_TO_EDGE : GL_REPEAT);
    if (cube) {
        for (int face = 0; face < 6; face++)
            glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + face, 0, GL_RGBA8, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, white);
    } else if (image != NULL) {
        glPixelStorei(GL_UNPACK_ROW_LENGTH, image->pitch / 4);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, image->w, image->h, 0, GL_RGBA, GL_UNSIGNED_BYTE, image->pixels);
        glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
    } else {
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, white);
    }
    return texture;
}

static void SetUpGLState(const Scene* scene)
{
    const OOGLSLLegacyStateBlock* L = &scene->legacy;
    glMatrixMode(GL_PROJECTION);
    glLoadMatrixf(scene->projection.m);
    glMatrixMode(GL_MODELVIEW);
    // Light positions are given in eye space.
    glLoadIdentity();
    for (int i = 0; i < 2; i++) {
        const OOGLSLLightSource* light = &L->lightSource[i];
        glLightfv(GL_LIGHT0 + i, GL_AMBIENT, light->ambient);
        glLightfv(GL_LIGHT0 + i, GL_DIFFUSE, light->diffuse);
        glLightfv(GL_LIGHT0 + i, GL_SPECULAR, light->specular);
        glLightfv(GL_LIGHT0 + i, GL_POSITION, light->position);
        glEnable(GL_LIGHT0 + i);
    }
    glLightModelfv(GL_LIGHT_MODEL_AMBIENT, L->lightModelAmbient);
    glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT, L->frontMaterial.ambient);
    glMaterialfv(GL_FRONT_AND_BACK, GL_DIFFUSE, L->frontMaterial.diffuse);
    glMaterialfv(GL_FRONT_AND_BACK, GL_SPECULAR, L->frontMaterial.specular);
    glMaterialfv(GL_FRONT_AND_BACK, GL_EMISSION, L->frontMaterial.emission);
    glMaterialf(GL_FRONT_AND_BACK, GL_SHININESS, L->frontMaterial.shininess);
    glLoadMatrixf(scene->modelView.m);
}

static bool RenderGL(const Scene* scene, const char* vs, const char* fs, const char* prefix, uint8_t* outPixels)
{
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1);
    SDL_Window* window = SDL_CreateWindow("oogpu-render GL", 64, 64, SDL_WINDOW_OPENGL | SDL_WINDOW_HIDDEN);
    SDL_GLContext context = window ? SDL_GL_CreateContext(window) : NULL;
    if (context == NULL) {
        fprintf(stderr, "GL context: %s\n", SDL_GetError());
        return false;
    }

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

    GLuint program = glCreateProgram();
    if (vs != NULL) {
        GLuint shader = CompileGL(GL_VERTEX_SHADER, prefix, vs);
        if (shader == 0)
            return false;
        glAttachShader(program, shader);
    }
    if (fs != NULL) {
        GLuint shader = CompileGL(GL_FRAGMENT_SHADER, prefix, fs);
        if (shader == 0)
            return false;
        glAttachShader(program, shader);
    }
    glBindAttribLocation(program, kTangentAttributeIndex, "tangent");
    glLinkProgram(program);
    GLint linked = 0;
    glGetProgramiv(program, GL_LINK_STATUS, &linked);
    if (!linked) {
        char log[4096];
        glGetProgramInfoLog(program, sizeof log, NULL, log);
        fprintf(stderr, "GL link failed:\n%s\n", log);
        return false;
    }
    bool useProgram = vs != NULL || fs != NULL;

    glViewport(0, 0, kSize, kSize);
    glClearColor(0, 0, 0, 1);
    glClearDepth(1);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LEQUAL);
    glEnable(GL_CULL_FACE);
    glCullFace(GL_BACK);
    glFrontFace(GL_CCW);
    glEnable(GL_BLEND);
    glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    SetUpGLState(scene);
    if (scene->fixedFunctionVertex)
        glEnable(GL_LIGHTING);

    if (useProgram) {
        glUseProgram(program);
        GLint uniformCount = 0, unit = 0;
        glGetProgramiv(program, GL_ACTIVE_UNIFORMS, &uniformCount);
        for (GLint i = 0; i < uniformCount; i++) {
            char name[128];
            GLint size;
            GLenum type;
            glGetActiveUniform(program, i, sizeof name, NULL, &size, &type, name);
            GLint location = glGetUniformLocation(program, name);
            if (location < 0)
                continue;
            if (type == GL_SAMPLER_2D || type == GL_SAMPLER_CUBE) {
                glActiveTexture(GL_TEXTURE0 + unit);
                UploadGLTexture(FindTexture(scene, name), type == GL_SAMPLER_CUBE);
                glUniform1i(location, unit++);
                continue;
            }
            const Value* v = FindValue(scene, name);
            if (v == NULL)
                continue;
            switch (type) {
            case GL_FLOAT:
                glUniform1fv(location, 1, v->values);
                break;
            case GL_FLOAT_VEC2:
                glUniform2fv(location, 1, v->values);
                break;
            case GL_FLOAT_VEC3:
                glUniform3fv(location, 1, v->values);
                break;
            case GL_FLOAT_VEC4:
                glUniform4fv(location, 1, v->values);
                break;
            case GL_FLOAT_MAT3:
                glUniformMatrix3fv(location, 1, GL_FALSE, v->values);
                break;
            case GL_FLOAT_MAT4:
                glUniformMatrix4fv(location, 1, GL_FALSE, v->values);
                break;
            case GL_INT:
            case GL_BOOL:
                glUniform1i(location, (GLint)v->values[0]);
                break;
            default:
                fprintf(stderr, "GL: uniform %s has an unhandled type 0x%x\n", name, type);
                break;
            }
        }
        glActiveTexture(GL_TEXTURE0);
    }
    if (scene->fixedFunctionFragment) {
        glActiveTexture(GL_TEXTURE0);
        UploadGLTexture(FindTexture(scene, "oo_FixedFunctionTexture0"), false);
        glEnable(GL_TEXTURE_2D);
        glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
    }

    const Mesh* mesh = &scene->mesh;
    glEnableClientState(GL_VERTEX_ARRAY);
    glVertexPointer(3, GL_FLOAT, 0, mesh->streams[kOOVertexStreamPosition]);
    glEnableClientState(GL_NORMAL_ARRAY);
    glNormalPointer(GL_FLOAT, 0, mesh->streams[kOOVertexStreamNormal]);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    glTexCoordPointer(2, GL_FLOAT, 0, mesh->streams[kOOVertexStreamTexCoord]);
    glEnableClientState(GL_COLOR_ARRAY);
    glColorPointer(4, GL_FLOAT, 0, mesh->streams[kOOVertexStreamColor]);
    glEnableVertexAttribArray(kTangentAttributeIndex);
    glVertexAttribPointer(kTangentAttributeIndex, 3, GL_FLOAT, GL_FALSE, 0, mesh->streams[kOOVertexStreamTangent]);
    glDrawElements(GL_TRIANGLES, (GLsizei)mesh->indexCount, GL_UNSIGNED_INT, mesh->indices);
    glFinish();

    // GL rows run bottom to top.
    uint8_t* rows = malloc(kSize * kSize * 4);
    glReadPixels(0, 0, kSize, kSize, GL_RGBA, GL_UNSIGNED_BYTE, rows);
    for (int y = 0; y < kSize; y++)
        memcpy(outPixels + y * kSize * 4, rows + (kSize - 1 - y) * kSize * 4, kSize * 4);
    free(rows);

    GLenum error = glGetError();
    if (error != GL_NO_ERROR)
        fprintf(stderr, "GL error 0x%x\n", error);
    SDL_GL_DestroyContext(context);
    SDL_DestroyWindow(window);
    return true;
}

#pragma mark - SDL_GPU

static SDL_GPUBuffer* UploadBuffer(SDL_GPUDevice* device, SDL_GPUCopyPass* pass, SDL_GPUBufferUsageFlags usage, const void* data, uint32_t size)
{
    SDL_GPUBufferCreateInfo info = { .usage = usage, .size = size };
    SDL_GPUBuffer* buffer = SDL_CreateGPUBuffer(device, &info);
    SDL_GPUTransferBufferCreateInfo tinfo = { .usage = SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD, .size = size };
    SDL_GPUTransferBuffer* transfer = SDL_CreateGPUTransferBuffer(device, &tinfo);
    memcpy(SDL_MapGPUTransferBuffer(device, transfer, false), data, size);
    SDL_UnmapGPUTransferBuffer(device, transfer);
    SDL_GPUTransferBufferLocation src = { .transfer_buffer = transfer };
    SDL_GPUBufferRegion dst = { .buffer = buffer, .size = size };
    SDL_UploadToGPUBuffer(pass, &src, &dst, false);
    SDL_ReleaseGPUTransferBuffer(device, transfer);
    return buffer;
}

static SDL_GPUTexture* UploadTexture(SDL_GPUDevice* device, SDL_GPUCopyPass* pass, const SDL_Surface* image, bool cube)
{
    static const uint8_t white[4] = { 255, 255, 255, 255 };
    uint32_t w = image && !cube ? (uint32_t)image->w : 1, h = image && !cube ? (uint32_t)image->h : 1;
    uint32_t layers = cube ? 6 : 1;
    SDL_GPUTextureCreateInfo info = {
        .type = cube ? SDL_GPU_TEXTURETYPE_CUBE : SDL_GPU_TEXTURETYPE_2D,
        .format = SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .usage = SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = w,
        .height = h,
        .layer_count_or_depth = layers,
        .num_levels = 1,
    };
    SDL_GPUTexture* texture = SDL_CreateGPUTexture(device, &info);
    for (uint32_t layer = 0; layer < layers; layer++) {
        SDL_GPUTransferBufferCreateInfo tinfo = { .usage = SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD, .size = w * h * 4 };
        SDL_GPUTransferBuffer* transfer = SDL_CreateGPUTransferBuffer(device, &tinfo);
        uint8_t* dst = SDL_MapGPUTransferBuffer(device, transfer, false);
        for (uint32_t y = 0; y < h; y++)
            memcpy(dst + y * w * 4, image && !cube ? (const uint8_t*)image->pixels + y * image->pitch : white, w * 4);
        SDL_UnmapGPUTransferBuffer(device, transfer);
        SDL_GPUTextureTransferInfo src = { .transfer_buffer = transfer };
        SDL_GPUTextureRegion region = { .texture = texture, .layer = layer, .w = w, .h = h, .d = 1 };
        SDL_UploadToGPUTexture(pass, &src, &region, false);
        SDL_ReleaseGPUTransferBuffer(device, transfer);
    }
    return texture;
}

// Fill one stage's OOUniforms block from the scene values, by name.
static uint8_t* BuildUniformBlock(const Scene* scene, const OOGLSLStageResult* stage)
{
    uint8_t* block = calloc(1, stage->uniformBlockSize + 16);
    for (size_t i = 0; i < stage->uniformCount; i++) {
        const OOGLSLUniform* u = &stage->uniforms[i];
        const Value* v = FindValue(scene, u->name);
        if (v == NULL)
            continue;
        // A bool in a uniform block is a 32-bit uint in SPIR-V.
        if (u->baseType == kOOGLSLTypeInt || u->baseType == kOOGLSLTypeUInt || u->baseType == kOOGLSLTypeBool) {
            int32_t value = (int32_t)v->values[0];
            memcpy(block + u->offset, &value, sizeof value);
        } else if (u->baseType == kOOGLSLTypeFloat && u->columns > 1) {
            for (uint32_t c = 0; c < u->columns; c++)
                memcpy(block + u->offset + c * u->matrixStride, &v->values[c * u->vectorSize], u->vectorSize * sizeof(float));
        } else if (u->baseType == kOOGLSLTypeFloat) {
            int n = (int)u->vectorSize < v->count ? (int)u->vectorSize : v->count;
            memcpy(block + u->offset, v->values, n * sizeof(float));
        }
    }
    return block;
}

static bool RenderGPU(const Scene* scene, const OOGLSLProgram* program, uint8_t* outPixels)
{
    SDL_GPUDevice* device = SDL_CreateGPUDevice(SDL_GPU_SHADERFORMAT_MSL | SDL_GPU_SHADERFORMAT_SPIRV, true, NULL);
    if (device == NULL) {
        fprintf(stderr, "SDL_CreateGPUDevice: %s\n", SDL_GetError());
        return false;
    }
    OOGPUProgram gpu;
    if (!OOGPUProgramCreate(device, program, SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM, SDL_GPU_TEXTUREFORMAT_D32_FLOAT, &gpu)) {
        fprintf(stderr, "OOGPUProgramCreate: %s\n", SDL_GetError());
        return false;
    }

    SDL_GPUTextureCreateInfo colorInfo = {
        .type = SDL_GPU_TEXTURETYPE_2D,
        .format = SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .usage = SDL_GPU_TEXTUREUSAGE_COLOR_TARGET,
        .width = kSize,
        .height = kSize,
        .layer_count_or_depth = 1,
        .num_levels = 1,
    };
    SDL_GPUTexture* color = SDL_CreateGPUTexture(device, &colorInfo);
    SDL_GPUTextureCreateInfo depthInfo = colorInfo;
    depthInfo.format = SDL_GPU_TEXTUREFORMAT_D32_FLOAT;
    depthInfo.usage = SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET;
    SDL_GPUTexture* depth = SDL_CreateGPUTexture(device, &depthInfo);
    SDL_GPUSamplerCreateInfo samplerInfo = {
        .min_filter = SDL_GPU_FILTER_LINEAR,
        .mag_filter = SDL_GPU_FILTER_LINEAR,
        .mipmap_mode = SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
        .address_mode_u = SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
        .address_mode_v = SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
        .address_mode_w = SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
    };
    SDL_GPUSampler* repeatSampler = SDL_CreateGPUSampler(device, &samplerInfo);
    samplerInfo.address_mode_u = samplerInfo.address_mode_v = samplerInfo.address_mode_w = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE;
    SDL_GPUSampler* clampSampler = SDL_CreateGPUSampler(device, &samplerInfo);

    SDL_GPUCommandBuffer* commands = SDL_AcquireGPUCommandBuffer(device);
    SDL_GPUCopyPass* copy = SDL_BeginGPUCopyPass(commands);
    const Mesh* mesh = &scene->mesh;
    SDL_GPUBuffer* streams[kOOVertexStreamCount];
    for (int s = 0; s < kOOVertexStreamCount; s++)
        streams[s] = UploadBuffer(device, copy, SDL_GPU_BUFFERUSAGE_VERTEX, mesh->streams[s], mesh->vertexCount * OOVertexStreamComponents(s) * sizeof(float));
    SDL_GPUBuffer* indices = UploadBuffer(device, copy, SDL_GPU_BUFFERUSAGE_INDEX, mesh->indices, mesh->indexCount * sizeof(uint32_t));
    SDL_GPUTextureSamplerBinding bindings[kOOGLSLStageCount][16];
    SDL_GPUTexture* textures[32];
    int textureCount = 0;
    for (int stage = 0; stage < kOOGLSLStageCount; stage++) {
        const OOGLSLStageResult* result = &program->stages[stage];
        for (size_t i = 0; i < result->samplerCount; i++) {
            const OOGLSLSampler* s = &result->samplers[i];
            SDL_GPUTexture* texture = UploadTexture(device, copy, FindTexture(scene, s->name), s->isCube);
            textures[textureCount++] = texture;
            bindings[stage][s->slot] = (SDL_GPUTextureSamplerBinding) { .texture = texture, .sampler = s->isCube ? clampSampler : repeatSampler };
        }
    }
    SDL_EndGPUCopyPass(copy);

    SDL_GPUColorTargetInfo colorTarget = {
        .texture = color,
        .clear_color = { 0, 0, 0, 1 },
        .load_op = SDL_GPU_LOADOP_CLEAR,
        .store_op = SDL_GPU_STOREOP_STORE,
    };
    SDL_GPUDepthStencilTargetInfo depthTarget = {
        .texture = depth,
        .clear_depth = 1,
        .load_op = SDL_GPU_LOADOP_CLEAR,
        .store_op = SDL_GPU_STOREOP_DONT_CARE,
    };
    SDL_GPURenderPass* pass = SDL_BeginGPURenderPass(commands, &colorTarget, 1, &depthTarget);
    SDL_BindGPUGraphicsPipeline(pass, gpu.pipeline);
    for (uint32_t slot = 0; slot < gpu.slotCount; slot++) {
        SDL_GPUBufferBinding binding = { .buffer = streams[gpu.streamForSlot[slot]] };
        SDL_BindGPUVertexBuffers(pass, slot, &binding, 1);
    }
    SDL_GPUBufferBinding indexBinding = { .buffer = indices };
    SDL_BindGPUIndexBuffer(pass, &indexBinding, SDL_GPU_INDEXELEMENTSIZE_32BIT);

    OOGLSLLegacyStateBlock legacy = scene->legacy;
    legacy.lightingEnabled = scene->fixedFunctionVertex ? 1.0f : 0.0f;
    // The GL reference textures unit 0 with GL_MODULATE.
    legacy.textureEnabled[0] = scene->fixedFunctionFragment ? 1.0f : 0.0f;
    uint8_t* blocks[kOOGLSLStageCount];
    for (int stage = 0; stage < kOOGLSLStageCount; stage++) {
        const OOGLSLStageResult* result = &program->stages[stage];
        blocks[stage] = BuildUniformBlock(scene, result);
        if (stage == kOOGLSLStageVertex) {
            SDL_PushGPUVertexUniformData(commands, kOOGLSLLegacyStateSlot, &legacy, sizeof legacy);
            SDL_PushGPUVertexUniformData(commands, kOOGLSLUniformsSlot, blocks[stage], result->uniformBlockSize + 16);
            if (result->samplerCount > 0)
                SDL_BindGPUVertexSamplers(pass, 0, bindings[stage], (Uint32)result->samplerCount);
        } else {
            SDL_PushGPUFragmentUniformData(commands, kOOGLSLLegacyStateSlot, &legacy, sizeof legacy);
            SDL_PushGPUFragmentUniformData(commands, kOOGLSLUniformsSlot, blocks[stage], result->uniformBlockSize + 16);
            if (result->samplerCount > 0)
                SDL_BindGPUFragmentSamplers(pass, 0, bindings[stage], (Uint32)result->samplerCount);
        }
    }
    SDL_DrawGPUIndexedPrimitives(pass, mesh->indexCount, 1, 0, 0, 0);
    SDL_EndGPURenderPass(pass);

    SDL_GPUTransferBufferCreateInfo downloadInfo = { .usage = SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD, .size = kSize * kSize * 4 };
    SDL_GPUTransferBuffer* download = SDL_CreateGPUTransferBuffer(device, &downloadInfo);
    copy = SDL_BeginGPUCopyPass(commands);
    SDL_GPUTextureRegion region = { .texture = color, .w = kSize, .h = kSize, .d = 1 };
    SDL_GPUTextureTransferInfo dst = { .transfer_buffer = download };
    SDL_DownloadFromGPUTexture(copy, &region, &dst);
    SDL_EndGPUCopyPass(copy);
    SDL_GPUFence* fence = SDL_SubmitGPUCommandBufferAndAcquireFence(commands);
    SDL_WaitForGPUFences(device, true, &fence, 1);
    SDL_ReleaseGPUFence(device, fence);
    memcpy(outPixels, SDL_MapGPUTransferBuffer(device, download, false), kSize * kSize * 4);
    SDL_UnmapGPUTransferBuffer(device, download);

    for (int stage = 0; stage < kOOGLSLStageCount; stage++)
        free(blocks[stage]);
    for (int i = 0; i < textureCount; i++)
        SDL_ReleaseGPUTexture(device, textures[i]);
    for (int s = 0; s < kOOVertexStreamCount; s++)
        SDL_ReleaseGPUBuffer(device, streams[s]);
    SDL_ReleaseGPUBuffer(device, indices);
    SDL_ReleaseGPUTransferBuffer(device, download);
    SDL_ReleaseGPUSampler(device, repeatSampler);
    SDL_ReleaseGPUSampler(device, clampSampler);
    SDL_ReleaseGPUTexture(device, color);
    SDL_ReleaseGPUTexture(device, depth);
    OOGPUProgramRelease(device, &gpu);
    SDL_DestroyGPUDevice(device);
    return true;
}

#pragma mark - Main

// PNG support arrived in SDL 3.4; Debian and Ubuntu ship 3.2.
static SDL_Surface* LoadImage(const char* path)
{
    size_t length = strlen(path);
    if (length > 4 && SDL_strcasecmp(path + length - 4, ".bmp") == 0)
        return SDL_LoadBMP(path);
#if SDL_VERSION_ATLEAST(3, 4, 0)
    return SDL_LoadPNG(path);
#else
    SDL_SetError("PNG needs SDL 3.4; convert %s to BMP", path);
    return NULL;
#endif
}

static bool SaveImage(const uint8_t* pixels, const char* prefix, const char* suffix)
{
    char path[1024];
    SDL_Surface* surface = SDL_CreateSurfaceFrom(kSize, kSize, SDL_PIXELFORMAT_RGBA32, (void*)pixels, kSize * 4);
#if SDL_VERSION_ATLEAST(3, 4, 0)
    snprintf(path, sizeof path, "%s-%s.png", prefix, suffix);
    bool ok = surface != NULL && SDL_SavePNG(surface, path);
#else
    snprintf(path, sizeof path, "%s-%s.bmp", prefix, suffix);
    bool ok = surface != NULL && SDL_SaveBMP(surface, path);
#endif
    if (!ok)
        fprintf(stderr, "cannot save %s: %s\n", path, SDL_GetError());
    SDL_DestroySurface(surface);
    return ok;
}

static bool ParseAssignment(const char* arg, char* name, size_t nameSize, const char** value)
{
    const char* equals = strchr(arg, '=');
    if (equals == NULL || (size_t)(equals - arg) >= nameSize)
        return false;
    memcpy(name, arg, equals - arg);
    name[equals - arg] = '\0';
    *value = equals + 1;
    return true;
}

int main(int argc, char* argv[])
{
    static Scene scene;
    char* prefix = NULL;
    int arg = 1;
    if (!SDL_Init(SDL_INIT_VIDEO)) {
        fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
        return 1;
    }
    float sunIntensity = 1.0f;
    if (argc > 2 && strcmp(argv[1], "-l") == 0) {
        sunIntensity = strtof(argv[2], NULL);
        arg = 3;
    }
    SetUpScene(&scene, sunIntensity);

    for (; arg < argc && argv[arg][0] == '-' && argv[arg][1] != '\0'; arg += 2) {
        if (arg + 1 >= argc)
            break;
        char name[128];
        const char* value;
        if (strcmp(argv[arg], "-p") == 0) {
            prefix = OOReadTextFile(argv[arg + 1]);
        } else if (strcmp(argv[arg], "-U") == 0) {
            scene.hasDefaultValue = true;
            scene.defaultValue.count = 16;
            for (int i = 0; i < 16; i++)
                scene.defaultValue.values[i] = strtof(argv[arg + 1], NULL);
        } else if (strcmp(argv[arg], "-T") == 0) {
            SDL_Surface* loaded = LoadImage(argv[arg + 1]);
            if (loaded == NULL) {
                fprintf(stderr, "cannot load %s: %s\n", argv[arg + 1], SDL_GetError());
                return 2;
            }
            scene.defaultTexture = SDL_ConvertSurface(loaded, SDL_PIXELFORMAT_RGBA32);
            SDL_DestroySurface(loaded);
        } else if (strcmp(argv[arg], "-t") == 0 && ParseAssignment(argv[arg + 1], name, sizeof name, &value)) {
            SDL_Surface* loaded = LoadImage(value);
            if (loaded == NULL) {
                fprintf(stderr, "cannot load %s: %s\n", value, SDL_GetError());
                return 2;
            }
            TextureBinding* t = &scene.textures[scene.textureCount++];
            SDL_strlcpy(t->name, name, sizeof t->name);
            t->image = SDL_ConvertSurface(loaded, SDL_PIXELFORMAT_RGBA32);
            SDL_DestroySurface(loaded);
        } else if ((strcmp(argv[arg], "-u") == 0 || strcmp(argv[arg], "-i") == 0) && ParseAssignment(argv[arg + 1], name, sizeof name, &value)) {
            float values[16];
            int count = 0;
            for (char* end; count < 16 && *value != '\0'; value = *end == ',' ? end + 1 : end) {
                values[count++] = strtof(value, &end);
                if (end == value)
                    break;
            }
            AddValue(&scene, name, values, count, argv[arg][1] == 'i');
        } else {
            fprintf(stderr, "bad option %s\n", argv[arg]);
            return 2;
        }
    }
    if (argc - arg != 3) {
        fprintf(stderr, "usage: %s [-p prefix] [-t name=png] [-u name=v,...] [-i name=n] <vs|-> <fs|-> <out prefix>\n", argv[0]);
        return 2;
    }
    char* vs = strcmp(argv[arg], "-") ? OOReadTextFile(argv[arg]) : NULL;
    char* fs = strcmp(argv[arg + 1], "-") ? OOReadTextFile(argv[arg + 1]) : NULL;
    const char* out = argv[arg + 2];
    scene.fixedFunctionVertex = vs == NULL;
    scene.fixedFunctionFragment = fs == NULL;

    uint8_t* glPixels = calloc(kSize * kSize, 4);
    uint8_t* gpuPixels = calloc(kSize * kSize, 4);
    if (!RenderGL(&scene, vs, fs, prefix, glPixels))
        return 1;

    OOGLSLProgram program;
    SDL_GPUDevice* probe = SDL_CreateGPUDevice(SDL_GPU_SHADERFORMAT_MSL | SDL_GPU_SHADERFORMAT_SPIRV, false, NULL);
    OOGLSLOutputFormats formats = probe ? OOGPUFormatsForDevice(probe) : kOOGLSLOutputSPIRV;
    if (probe != NULL)
        SDL_DestroyGPUDevice(probe);
    if (!OOGLSLTranslateProgram(vs, fs, prefix, formats, &program)) {
        fprintf(stderr, "translation failed:\n%s\n", program.log);
        return 1;
    }
    if (!RenderGPU(&scene, &program, gpuPixels))
        return 1;
    OOGLSLProgramFree(&program);

    SaveImage(glPixels, out, "gl");
    SaveImage(gpuPixels, out, "gpu");

    double sum = 0;
    int maxDiff = 0;
    unsigned differing = 0;
    for (int i = 0; i < kSize * kSize; i++) {
        int pixelMax = 0;
        for (int c = 0; c < 3; c++) {
            int d = abs((int)glPixels[i * 4 + c] - (int)gpuPixels[i * 4 + c]);
            sum += d;
            if (d > pixelMax)
                pixelMax = d;
        }
        if (pixelMax > maxDiff)
            maxDiff = pixelMax;
        if (pixelMax > 2)
            differing++;
    }
    printf("mean %.3f  max %d  differing %.2f%%\n", sum / (kSize * kSize * 3.0), maxDiff, 100.0 * differing / (kSize * kSize));

    free(glPixels);
    free(gpuPixels);
    free(vs);
    free(fs);
    free(prefix);
    SDL_Quit();
    OOGLSLTranslatorShutdown();
    return 0;
}
