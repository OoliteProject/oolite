/*

OORendererGL.c

OpenGL backend for the renderer layer. Immediate-mode batches are drawn from
client-side vertex arrays, so they no longer need glBegin()/glEnd(). All
other render state still comes from the live GL context, which legacy code
sets directly until it moves to the renderer layer.


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
#include "OORendererBackend.h"

// OOOpenGLOnly.h keys GL_GLEXT_PROTOTYPES on OOLITE_LINUX, which comes from
// Objective-C headers this C file doesn't use.
#if !defined(_WIN32) && !defined(GL_GLEXT_PROTOTYPES)
#define GL_GLEXT_PROTOTYPES 1
#endif
#include "OOOpenGLOnly.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
/*  On Windows, GL functions after 1.1 are pointers that
    OOOpenGLExtensionManager loads; OOOpenGLExtensionManager.h declares them
    for Objective-C under these names.
*/
extern PFNGLACTIVETEXTUREPROC glActiveTexturePtr;
extern PFNGLCLIENTACTIVETEXTUREARBPROC glClientActiveTextureARBPtr;
extern PFNGLBINDBUFFERPROC glBindBuffer;
extern PFNGLBINDFRAMEBUFFERPROC glBindFramebuffer;
extern PFNGLENABLEVERTEXATTRIBARRAYARBPROC glEnableVertexAttribArrayARB;
extern PFNGLDISABLEVERTEXATTRIBARRAYARBPROC glDisableVertexAttribArrayARB;
extern PFNGLVERTEXATTRIBPOINTERARBPROC glVertexAttribPointerARB;
extern PFNGLGENFRAMEBUFFERSPROC glGenFramebuffers;
extern PFNGLDELETEFRAMEBUFFERSPROC glDeleteFramebuffers;
extern PFNGLFRAMEBUFFERTEXTURE2DPROC glFramebufferTexture2D;
extern PFNGLFRAMEBUFFERRENDERBUFFERPROC glFramebufferRenderbuffer;
extern PFNGLCHECKFRAMEBUFFERSTATUSPROC glCheckFramebufferStatus;
extern PFNGLGENRENDERBUFFERSPROC glGenRenderbuffers;
extern PFNGLDELETERENDERBUFFERSPROC glDeleteRenderbuffers;
extern PFNGLBINDRENDERBUFFERPROC glBindRenderbuffer;
extern PFNGLRENDERBUFFERSTORAGEPROC glRenderbufferStorage;
extern PFNGLRENDERBUFFERSTORAGEMULTISAMPLEPROC glRenderbufferStorageMultisample;
extern PFNGLTEXIMAGE2DMULTISAMPLEPROC glTexImage2DMultisample;
extern PFNGLDRAWBUFFERSPROC glDrawBuffers;
extern PFNGLBLITFRAMEBUFFERPROC glBlitFramebuffer;
#define glActiveTexture glActiveTexturePtr
#define glClientActiveTexture glClientActiveTextureARBPtr
#endif

static GLenum GLPrimitive(OONativePrimitive primitive)
{
    switch (primitive) {
    case kOONativePrimitivePoints:
        return GL_POINTS;
    case kOONativePrimitiveLines:
        return GL_LINES;
    case kOONativePrimitiveLineStrip:
        return GL_LINE_STRIP;
    case kOONativePrimitiveTriangleStrip:
        return GL_TRIANGLE_STRIP;
    case kOONativePrimitiveTriangles:
        break;
    }
    return GL_TRIANGLES;
}

void OORendererBackendDrawImmediate(OONativePrimitive primitive, const OOImmediateVertex* vertices, size_t count)
{
    // Legacy code may have left any of this set; draw from client memory
    // with exactly the four classic arrays, then put things back.
    GLint arrayBuffer = 0, clientActiveTexture = GL_TEXTURE0;
    glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &arrayBuffer);
    glGetIntegerv(GL_CLIENT_ACTIVE_TEXTURE, &clientActiveTexture);
    if (arrayBuffer != 0)
        glBindBuffer(GL_ARRAY_BUFFER, 0);
    if (clientActiveTexture != GL_TEXTURE0)
        glClientActiveTexture(GL_TEXTURE0);

    static const GLenum kArrays[4] = { GL_VERTEX_ARRAY, GL_COLOR_ARRAY, GL_TEXTURE_COORD_ARRAY, GL_NORMAL_ARRAY };
    GLboolean wasEnabled[4];
    for (int i = 0; i < 4; i++) {
        wasEnabled[i] = glIsEnabled(kArrays[i]);
        if (!wasEnabled[i])
            glEnableClientState(kArrays[i]);
    }

    const GLsizei stride = sizeof(OOImmediateVertex);
    glVertexPointer(3, GL_FLOAT, stride, vertices->position);
    glColorPointer(4, GL_FLOAT, stride, vertices->color);
    glTexCoordPointer(2, GL_FLOAT, stride, vertices->texCoord);
    glNormalPointer(GL_FLOAT, stride, vertices->normal);
    glDrawArrays(GLPrimitive(primitive), 0, (GLsizei)count);

    for (int i = 0; i < 4; i++) {
        if (!wasEnabled[i])
            glDisableClientState(kArrays[i]);
    }
    if (clientActiveTexture != GL_TEXTURE0)
        glClientActiveTexture((GLenum)clientActiveTexture);
    if (arrayBuffer != 0)
        glBindBuffer(GL_ARRAY_BUFFER, (GLuint)arrayBuffer);
}

#if OO_IMMEDIATE_GL_INTEROP

void OORendererBackendGetGLAttributes(OOImmediateAttributes* outAttributes)
{
    GLfloat texCoord[4];
    GLint activeTexture = GL_TEXTURE0;
    glGetFloatv(GL_CURRENT_COLOR, outAttributes->color);
    glGetFloatv(GL_CURRENT_NORMAL, outAttributes->normal);
    // GL_CURRENT_TEXTURE_COORDS belongs to the active texture unit.
    glGetIntegerv(GL_ACTIVE_TEXTURE, &activeTexture);
    if (activeTexture != GL_TEXTURE0)
        glActiveTexture(GL_TEXTURE0);
    glGetFloatv(GL_CURRENT_TEXTURE_COORDS, texCoord);
    if (activeTexture != GL_TEXTURE0)
        glActiveTexture((GLenum)activeTexture);
    outAttributes->texCoord[0] = texCoord[0];
    outAttributes->texCoord[1] = texCoord[1];
}

void OORendererBackendSetGLAttributes(const OOImmediateAttributes* attributes)
{
    glColor4fv(attributes->color);
    glNormal3fv(attributes->normal);
    // glTexCoord2f sets unit 0 regardless of the active texture unit.
    glTexCoord2fv(attributes->texCoord);
}

void OORendererBackendCheckGLAttributes(const OOImmediateAttributes* expected)
{
#ifndef NDEBUG
    static bool sWarned = false;
    GLfloat color[4];
    glGetFloatv(GL_CURRENT_COLOR, color);
    for (int i = 0; i < 4 && !sWarned; i++) {
        // GL may clamp what it stores; compare clamped values.
        float want = fminf(fmaxf(expected->color[i], 0.0f), 1.0f);
        float have = fminf(fmaxf(color[i], 0.0f), 1.0f);
        if (fabsf(have - want) > 1.0f / 512.0f) {
            OORendererBackendWarn("GL colour changed directly during an immediate-mode batch; a glColor call still needs to move to OOImmediateColor.");
            sWarned = true;
        }
    }
#else
    (void)expected;
#endif
}

#endif

#pragma mark - Draw state

typedef struct {
    GLboolean blend, depthTest, depthMask, cullFace, lighting, texture2D, fog, scissorTest;
    GLint blendSrc, blendDst, cullFaceMode, frontFace, activeTexture;
    GLint scissorBox[4];
} SavedGLState;

static SavedGLState sSaved[kOORendererMaxDrawStateDepth];

static void SetCapability(GLenum capability, bool enabled)
{
    if (enabled)
        glEnable(capability);
    else
        glDisable(capability);
}

static void SetClientState(GLenum array, bool enabled)
{
    if (enabled)
        glEnableClientState(array);
    else
        glDisableClientState(array);
}

static void ApplyBlend(OOBlendMode blend)
{
    SetCapability(GL_BLEND, blend != kOOBlendOff);
    // OOSetOpenGLState keeps the alpha blend function even with blending off.
    glBlendFunc(GL_SRC_ALPHA, blend == kOOBlendAdditive ? GL_ONE : GL_ONE_MINUS_SRC_ALPHA);
}

void OORendererBackendPushDrawState(const OODrawState* state, int depth)
{
    SavedGLState* saved = &sSaved[depth];
    saved->blend = glIsEnabled(GL_BLEND);
    saved->depthTest = glIsEnabled(GL_DEPTH_TEST);
    saved->cullFace = glIsEnabled(GL_CULL_FACE);
    saved->lighting = glIsEnabled(GL_LIGHTING);
    saved->fog = glIsEnabled(GL_FOG);
    saved->scissorTest = glIsEnabled(GL_SCISSOR_TEST);
    glGetBooleanv(GL_DEPTH_WRITEMASK, &saved->depthMask);
    glGetIntegerv(GL_BLEND_SRC, &saved->blendSrc);
    glGetIntegerv(GL_BLEND_DST, &saved->blendDst);
    glGetIntegerv(GL_CULL_FACE_MODE, &saved->cullFaceMode);
    glGetIntegerv(GL_FRONT_FACE, &saved->frontFace);
    glGetIntegerv(GL_SCISSOR_BOX, saved->scissorBox);
    // Texture enables and bindings belong to the active unit; use unit 0.
    glGetIntegerv(GL_ACTIVE_TEXTURE, &saved->activeTexture);
    if (saved->activeTexture != GL_TEXTURE0)
        glActiveTexture(GL_TEXTURE0);
    saved->texture2D = glIsEnabled(GL_TEXTURE_2D);
    OORendererBackendSaveTexture(depth);

    ApplyBlend(state->blend);
    SetCapability(GL_DEPTH_TEST, state->depthTest);
    glDepthMask(state->depthWrite ? GL_TRUE : GL_FALSE);
    SetCapability(GL_CULL_FACE, state->cullBack);
    glCullFace(GL_BACK);
    glFrontFace(GL_CCW);
    SetCapability(GL_LIGHTING, state->lighting);
    SetCapability(GL_FOG, state->fog);
    SetCapability(GL_TEXTURE_2D, state->texture2D);
    OORendererBackendApplyTexture(state->texture);
    SetCapability(GL_SCISSOR_TEST, state->scissor);
    if (state->scissor)
        glScissor(state->scissorRect[0], state->scissorRect[1], state->scissorRect[2], state->scissorRect[3]);
    // Stay on unit 0 for the scope, as OOSetOpenGLState's presets do.
}

void OORendererBackendPopDrawState(int depth)
{
    const SavedGLState* saved = &sSaved[depth];
    glActiveTexture(GL_TEXTURE0);
    OORendererBackendRestoreTexture(depth);
    SetCapability(GL_TEXTURE_2D, saved->texture2D);
    if (saved->activeTexture != GL_TEXTURE0)
        glActiveTexture((GLenum)saved->activeTexture);
    SetCapability(GL_BLEND, saved->blend);
    glBlendFunc((GLenum)saved->blendSrc, (GLenum)saved->blendDst);
    SetCapability(GL_DEPTH_TEST, saved->depthTest);
    glDepthMask(saved->depthMask);
    SetCapability(GL_CULL_FACE, saved->cullFace);
    glCullFace((GLenum)saved->cullFaceMode);
    glFrontFace((GLenum)saved->frontFace);
    SetCapability(GL_LIGHTING, saved->lighting);
    SetCapability(GL_FOG, saved->fog);
    SetCapability(GL_SCISSOR_TEST, saved->scissorTest);
    glScissor(saved->scissorBox[0], saved->scissorBox[1], saved->scissorBox[2], saved->scissorBox[3]);
}

void OORendererBackendVerifyDrawState(const OODrawState* state)
{
#ifndef NDEBUG
    static unsigned sReported = 0; // bit per field, so each is reported once
    unsigned bad = 0;
    GLint value = 0, activeTexture = GL_TEXTURE0;
    GLboolean flag;

    if (glIsEnabled(GL_BLEND) != (state->blend != kOOBlendOff))
        bad |= 1u << 0;
    if (state->blend != kOOBlendOff) {
        glGetIntegerv(GL_BLEND_DST, &value);
        if (value != (state->blend == kOOBlendAdditive ? GL_ONE : GL_ONE_MINUS_SRC_ALPHA))
            bad |= 1u << 1;
    }
    if (glIsEnabled(GL_DEPTH_TEST) != state->depthTest)
        bad |= 1u << 2;
    glGetBooleanv(GL_DEPTH_WRITEMASK, &flag);
    if (flag != state->depthWrite)
        bad |= 1u << 3;
    if (glIsEnabled(GL_CULL_FACE) != state->cullBack)
        bad |= 1u << 4;
    if (glIsEnabled(GL_LIGHTING) != state->lighting)
        bad |= 1u << 5;
    if (glIsEnabled(GL_FOG) != state->fog)
        bad |= 1u << 6;
    if (glIsEnabled(GL_SCISSOR_TEST) != state->scissor)
        bad |= 1u << 7;
    glGetIntegerv(GL_ACTIVE_TEXTURE, &activeTexture);
    if (activeTexture != GL_TEXTURE0)
        bad |= 1u << 8;
    else {
        if (glIsEnabled(GL_TEXTURE_2D) != state->texture2D)
            bad |= 1u << 9;
        if (state->texture2D) {
            glGetIntegerv(GL_TEXTURE_BINDING_2D, &value);
            if ((unsigned)value != OORendererBackendTextureName(state->texture))
                bad |= 1u << 10;
        }
    }

    static const char* const kNames[] = { "blend enable", "blend function", "depth test", "depth write",
        "culling", "lighting", "fog", "scissor", "active texture unit", "texturing", "bound texture" };
    unsigned fresh = bad & ~sReported;
    for (unsigned i = 0; i < sizeof kNames / sizeof *kNames; i++) {
        if (fresh & (1u << i)) {
            char message[160];
            snprintf(message, sizeof message, "GL %s changed directly inside a pushed draw state; that code still needs to move to the renderer.", kNames[i]);
            OORendererBackendWarn(message);
        }
    }
    sReported |= bad;
#else
    (void)state;
#endif
}

#pragma mark - Fixed-function values

void OORendererBackendSetLightColor(unsigned light, OOLightColor which, const float rgba[4])
{
    static const GLenum kParameters[] = { GL_AMBIENT, GL_DIFFUSE, GL_SPECULAR };
    glLightfv(GL_LIGHT0 + light, kParameters[which], rgba);
}

void OORendererBackendSetLightPosition(unsigned light, const float eyePosition[4])
{
    // GL transforms the position by the current modelview; it is already in
    // eye space, so give GL the identity. The matrix manager's copy of the
    // modelview is untouched.
    GLint matrixMode = GL_MODELVIEW;
    glGetIntegerv(GL_MATRIX_MODE, &matrixMode);
    if (matrixMode != GL_MODELVIEW)
        glMatrixMode(GL_MODELVIEW);
    glPushMatrix();
    glLoadIdentity();
    glLightfv(GL_LIGHT0 + light, GL_POSITION, eyePosition);
    glPopMatrix();
    if (matrixMode != GL_MODELVIEW)
        glMatrixMode((GLenum)matrixMode);
}

void OORendererBackendSetLightModelAmbient(const float rgba[4])
{
    glLightModelfv(GL_LIGHT_MODEL_AMBIENT, rgba);
}

static GLenum GLFace(OOMaterialFace face)
{
    return face == kOOMaterialFront ? GL_FRONT : face == kOOMaterialBack ? GL_BACK
                                                                         : GL_FRONT_AND_BACK;
}

void OORendererBackendSetMaterialColor(OOMaterialFace face, OOMaterialColor which, const float rgba[4])
{
    static const GLenum kParameters[] = { GL_AMBIENT, GL_DIFFUSE, GL_SPECULAR, GL_EMISSION, GL_AMBIENT_AND_DIFFUSE };
    glMaterialfv(GLFace(face), kParameters[which], rgba);
}

void OORendererBackendSetMaterialShininess(OOMaterialFace face, float shininess)
{
    glMaterialf(GLFace(face), GL_SHININESS, shininess);
}

void OORendererBackendSetFog(const OOFogValues* fog)
{
    static const GLint kModes[] = { GL_LINEAR, GL_EXP, GL_EXP2 };
    glFogi(GL_FOG_MODE, kModes[fog->mode]);
    glFogfv(GL_FOG_COLOR, fog->color);
    glFogf(GL_FOG_START, fog->start);
    glFogf(GL_FOG_END, fog->end);
    glFogf(GL_FOG_DENSITY, fog->density);
}

#pragma mark - Vertex arrays

static void DrawLayout(OONativePrimitive primitive, const OOVertexLayout* layout, size_t first, size_t count,
    const void* indices, OOIndexType indexType)
{
    // Classic arrays the layout doesn't use are disabled for the draw, as
    // the state presets do, and everything is put back afterwards. Generic
    // attribute arrays are assumed off outside draws, as Oolite keeps them
    // (and glGetVertexAttribiv isn't loaded on Windows).
    GLint arrayBuffer = 0, clientActiveTexture = GL_TEXTURE0;
    glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &arrayBuffer);
    glGetIntegerv(GL_CLIENT_ACTIVE_TEXTURE, &clientActiveTexture);
    if (arrayBuffer != 0)
        glBindBuffer(GL_ARRAY_BUFFER, 0);

    static const GLenum kClassic[3] = { GL_VERTEX_ARRAY, GL_NORMAL_ARRAY, GL_COLOR_ARRAY };
    GLboolean classicWas[3], classicUsed[3] = { false, false, false };
    for (int i = 0; i < 3; i++)
        classicWas[i] = glIsEnabled(kClassic[i]);

    enum { kMaxUnits = 8 };
    GLboolean texCoordWas[kMaxUnits], texCoordUsed[kMaxUnits] = { false };
    for (unsigned unit = 0; unit < kMaxUnits; unit++)
        texCoordWas[unit] = 2; // not looked at yet

    for (unsigned i = 0; i < layout->count; i++) {
        const OOVertexStream* stream = &layout->streams[i];
        const char* pointer = (const char*)stream->buffer->data + stream->offset;
        GLsizei stride = (GLsizei)stream->stride;
        switch (stream->semantic) {
        case kOOVertexPosition:
            classicUsed[0] = true;
            glVertexPointer((GLint)stream->components, GL_FLOAT, stride, pointer);
            break;
        case kOOVertexNormal:
            classicUsed[1] = true;
            glNormalPointer(GL_FLOAT, stride, pointer);
            break;
        case kOOVertexColor:
            classicUsed[2] = true;
            glColorPointer((GLint)stream->components, GL_FLOAT, stride, pointer);
            break;
        case kOOVertexTexCoord:
            if (stream->index < kMaxUnits) {
                glClientActiveTexture(GL_TEXTURE0 + stream->index);
                texCoordWas[stream->index] = glIsEnabled(GL_TEXTURE_COORD_ARRAY);
                texCoordUsed[stream->index] = true;
                glEnableClientState(GL_TEXTURE_COORD_ARRAY);
                glTexCoordPointer((GLint)stream->components, GL_FLOAT, stride, pointer);
            }
            break;
        case kOOVertexAttribute:
            glEnableVertexAttribArrayARB(stream->index);
            glVertexAttribPointerARB(stream->index, (GLint)stream->components, GL_FLOAT, GL_FALSE, stride, pointer);
            break;
        }
    }
    for (int i = 0; i < 3; i++)
        SetClientState(kClassic[i], classicUsed[i]);
    // Unit 0 texture co-ordinates off if the layout doesn't supply them.
    if (!texCoordUsed[0]) {
        glClientActiveTexture(GL_TEXTURE0);
        texCoordWas[0] = glIsEnabled(GL_TEXTURE_COORD_ARRAY);
        glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    }

    if (indices != NULL)
        glDrawElements(GLPrimitive(primitive), (GLsizei)count, indexType == kOOIndex16 ? GL_UNSIGNED_SHORT : GL_UNSIGNED_INT, indices);
    else
        glDrawArrays(GLPrimitive(primitive), (GLint)first, (GLsizei)count);

    for (unsigned i = 0; i < layout->count; i++) {
        if (layout->streams[i].semantic == kOOVertexAttribute)
            glDisableVertexAttribArrayARB(layout->streams[i].index);
    }
    for (unsigned unit = 0; unit < kMaxUnits; unit++) {
        if (texCoordWas[unit] != 2) {
            glClientActiveTexture(GL_TEXTURE0 + unit);
            SetClientState(GL_TEXTURE_COORD_ARRAY, texCoordWas[unit]);
        }
    }
    for (int i = 0; i < 3; i++)
        SetClientState(kClassic[i], classicWas[i]);
    glClientActiveTexture((GLenum)clientActiveTexture);
    if (arrayBuffer != 0)
        glBindBuffer(GL_ARRAY_BUFFER, (GLuint)arrayBuffer);
}

#pragma mark - Passes

void OORendererBackendSetClearValues(const float clearColor[4], float clearDepth)
{
    glClearColor(clearColor[0], clearColor[1], clearColor[2], clearColor[3]);
    glClearDepth(clearDepth);
}

void OORendererBackendBeginPass(const OORenderPassDescriptor* pass, const float clearColor[4], float clearDepth)
{
    if (pass->target != kOORenderTargetCurrent)
        glBindFramebuffer(GL_FRAMEBUFFER, pass->target);

    GLbitfield mask = 0;
    if (pass->colorLoad == kOOLoadClear)
        mask |= GL_COLOR_BUFFER_BIT;
    if (pass->depthLoad == kOOLoadClear)
        mask |= GL_DEPTH_BUFFER_BIT;
    if (mask == 0)
        return;

    GLboolean depthMask = GL_TRUE;
    if (mask & GL_DEPTH_BUFFER_BIT) {
        glGetBooleanv(GL_DEPTH_WRITEMASK, &depthMask);
        if (!depthMask)
            glDepthMask(GL_TRUE);
    }
    glClearColor(clearColor[0], clearColor[1], clearColor[2], clearColor[3]);
    glClearDepth(clearDepth);
    glClear(mask);
    if (!depthMask)
        glDepthMask(GL_FALSE);
}

void OORendererBackendEndPass(void)
{
    // GL has nothing to do; SDL_GPU ends the render pass here.
}

void OORendererBackendReadPixels(int x, int y, int width, int height, OOPixelFormat format, void* pixels)
{
    if (format == kOOPixelsRGBFloat)
        glReadPixels(x, y, width, height, GL_RGB, GL_FLOAT, pixels);
    else
        glReadPixels(x, y, width, height, GL_BGRA, GL_UNSIGNED_BYTE, pixels);
}

void OORendererBackendDrawArrays(OONativePrimitive primitive, const OOVertexLayout* layout, size_t first, size_t count)
{
    DrawLayout(primitive, layout, first, count, NULL, kOOIndex32);
}

void OORendererBackendDrawElements(OONativePrimitive primitive, const OOVertexLayout* layout,
    const void* indices, OOIndexType indexType, size_t count)
{
    DrawLayout(primitive, layout, 0, count, indices, indexType);
}

static GLenum TextureTarget(bool cube)
{
#ifdef GL_TEXTURE_CUBE_MAP
    if (cube)
        return GL_TEXTURE_CUBE_MAP;
#endif
    (void)cube;
    return GL_TEXTURE_2D;
}

// Bind texture on the active unit for creation or upload, returning what was bound.
static uint32_t BindForUpload(bool cube, uint32_t texture)
{
    const OOTextureUnitState* unit = &OORendererState()->units[OORendererState()->activeTexture];
    uint32_t previous = cube ? unit->bindingCube : unit->binding2D;
    glBindTexture(TextureTarget(cube), texture);
    return previous;
}

static GLint GLFilter(OOTextureFilter filter)
{
    switch (filter) {
    case kOOFilterNearest:
        return GL_NEAREST;
    case kOOFilterLinearMipmapLinear:
        return GL_LINEAR_MIPMAP_LINEAR;
    case kOOFilterLinear:
        break;
    }
    return GL_LINEAR;
}

/*  GL names are handed out by glGenTextures, so the backend has to remember
    whether each one is a cube map and what format it holds for uploads.
*/
typedef struct {
    uint8_t cube;
    uint8_t format;
    uint8_t srgb;
} TextureRecord;

static TextureRecord* sTextures = NULL;
static size_t sTextureCapacity = 0;

static TextureRecord* Record(uint32_t texture, bool grow)
{
    if (texture >= sTextureCapacity) {
        if (!grow)
            return NULL;
        size_t capacity = sTextureCapacity ? sTextureCapacity : 256;
        while (capacity <= texture)
            capacity *= 2;
        TextureRecord* records = realloc(sTextures, capacity * sizeof *records);
        if (records == NULL)
            return NULL;
        memset(records + sTextureCapacity, 0, (capacity - sTextureCapacity) * sizeof *records);
        sTextures = records;
        sTextureCapacity = capacity;
    }
    return &sTextures[texture];
}

static void GLFormat(const TextureRecord* record, GLenum* outFormat, GLenum* outInternalFormat, GLenum* outType)
{
    *outType = GL_UNSIGNED_BYTE;
    switch ((OOTexelFormat)record->format) {
    case kOOTexelGray8:
        *outFormat = GL_LUMINANCE;
        *outInternalFormat = GL_LUMINANCE8;
        return;
    case kOOTexelAlpha8:
        *outFormat = GL_ALPHA;
        *outInternalFormat = GL_ALPHA8;
        return;
    case kOOTexelGrayAlpha8:
        *outFormat = GL_LUMINANCE_ALPHA;
        *outInternalFormat = GL_LUMINANCE8_ALPHA8;
        return;
    case kOOTexelRGBA8:
        break;
    }
    *outFormat = GL_RGBA;
    *outInternalFormat = record->srgb ? GL_SRGB_ALPHA : GL_RGBA;
#ifdef __BIG_ENDIAN__
    *outType = GL_UNSIGNED_INT_8_8_8_8_REV;
#endif
}

static GLenum ImageTarget(const TextureRecord* record, unsigned face)
{
#ifdef GL_TEXTURE_CUBE_MAP
    if (record->cube)
        return GL_TEXTURE_CUBE_MAP_POSITIVE_X + face;
#endif
    (void)record;
    (void)face;
    return GL_TEXTURE_2D;
}

uint32_t OORendererBackendCreateTexture(const OOTextureDescriptor* descriptor)
{
    GLuint name = 0;
    glGenTextures(1, &name);
    TextureRecord* record = Record(name, true);
    if (name == 0 || record == NULL) {
        OORendererBackendWarn("OORendererCreateTexture: no texture name");
        return 0;
    }
    record->cube = descriptor->cube;
    record->format = (uint8_t)descriptor->format;
    record->srgb = descriptor->srgb;

    GLenum target = TextureTarget(descriptor->cube);
    uint32_t previous = BindForUpload(descriptor->cube, name);
    GLint wrapS = descriptor->repeatS && !descriptor->cube ? GL_REPEAT : GL_CLAMP_TO_EDGE;
    GLint wrapT = descriptor->repeatT && !descriptor->cube ? GL_REPEAT : GL_CLAMP_TO_EDGE;
#ifdef GL_TEXTURE_CUBE_MAP
    if (descriptor->cube)
        glTexParameteri(target, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);
#endif
    glTexParameteri(target, GL_TEXTURE_WRAP_S, wrapS);
    glTexParameteri(target, GL_TEXTURE_WRAP_T, wrapT);
    glTexParameteri(target, GL_TEXTURE_MIN_FILTER, GLFilter(descriptor->minFilter));
#ifdef GL_TEXTURE_MAX_ANISOTROPY_EXT
    if (descriptor->anisotropy > 1.0f)
        glTexParameterf(target, GL_TEXTURE_MAX_ANISOTROPY_EXT, descriptor->anisotropy);
#endif
    glTexParameteri(target, GL_TEXTURE_MAG_FILTER, descriptor->magFilter == kOOFilterNearest ? GL_NEAREST : GL_LINEAR);
    if (descriptor->levels > 1)
        glTexParameteri(target, GL_TEXTURE_MAX_LEVEL, (GLint)descriptor->levels - 1);
    glBindTexture(target, previous);
    return name;
}

void OORendererBackendUploadTexture(uint32_t texture, unsigned face, unsigned level, unsigned width, unsigned height, const void* texels)
{
    const TextureRecord* record = Record(texture, false);
    if (record == NULL)
        return;

    GLenum format, internalFormat, type;
    GLFormat(record, &format, &internalFormat, &type);

    GLenum imageTarget = ImageTarget(record, face);
    uint32_t previous = BindForUpload(record->cube, texture);
    // Rows are tightly packed; GL's default of 4-byte rows would misread
    // one- and two-channel levels narrower than four bytes.
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexImage2D(imageTarget, (GLint)level, (GLint)internalFormat, (GLsizei)width, (GLsizei)height, 0, format, type, texels);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
    glBindTexture(TextureTarget(record->cube), previous);
}

void OORendererBackendReadTexture(uint32_t texture, unsigned face, unsigned level, unsigned width, unsigned height, void* texels)
{
    const TextureRecord* record = Record(texture, false);
    if (record == NULL)
        return;
    (void)width;
    (void)height; // GL knows the level's size
    GLenum format, internalFormat, type;
    GLFormat(record, &format, &internalFormat, &type);
    uint32_t previous = BindForUpload(record->cube, texture);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glGetTexImage(ImageTarget(record, face), (GLint)level, format, type, texels);
    glPixelStorei(GL_PACK_ALIGNMENT, 4);
    glBindTexture(TextureTarget(record->cube), previous);
}

void OORendererBackendDeleteTexture(uint32_t texture)
{
    GLuint name = texture;
    glDeleteTextures(1, &name);
    TextureRecord* record = Record(texture, false);
    if (record != NULL)
        memset(record, 0, sizeof *record);
}

#pragma mark - Render targets

/*  A render target is a framebuffer object. Single-sampled colour attachments
    are textures, so they can be sampled; multisampled colour is a
    renderbuffer on the macOS legacy context (OO_MSAA_COLOR_RENDERBUFFER) and
    a multisample texture elsewhere. Depth is always a renderbuffer.
*/
typedef struct {
    bool used;
    OORenderTargetDescriptor descriptor;
    GLuint color[kOOMaxColorAttachments];
    GLuint depth;
} RenderTargetRecord;

static RenderTargetRecord* sTargets = NULL;
static size_t sTargetCapacity = 0;

static RenderTargetRecord* TargetRecord(OORenderTarget target, bool grow)
{
    if (target >= sTargetCapacity) {
        if (!grow)
            return NULL;
        size_t capacity = sTargetCapacity ? sTargetCapacity : 16;
        while (capacity <= target)
            capacity *= 2;
        RenderTargetRecord* records = realloc(sTargets, capacity * sizeof *records);
        if (records == NULL)
            return NULL;
        memset(records + sTargetCapacity, 0, (capacity - sTargetCapacity) * sizeof *records);
        sTargets = records;
        sTargetCapacity = capacity;
    }
    RenderTargetRecord* record = &sTargets[target];
    return grow || record->used ? record : NULL;
}

static bool MultisampleColorIsTexture(void)
{
#if OO_MSAA_COLOR_RENDERBUFFER
    return false;
#else
    return true;
#endif
}

// Size (or resize) every attachment's storage. The framebuffer is bound.
static void AllocateStorage(const RenderTargetRecord* record)
{
    const OORenderTargetDescriptor* d = &record->descriptor;
    GLsizei width = (GLsizei)d->width, height = (GLsizei)d->height;
    for (unsigned i = 0; i < d->colorAttachments; i++) {
        if (d->samples > 1 && !MultisampleColorIsTexture()) {
            glBindRenderbuffer(GL_RENDERBUFFER, record->color[i]);
            glRenderbufferStorageMultisample(GL_RENDERBUFFER, (GLsizei)d->samples, GL_RGBA16F, width, height);
            glBindRenderbuffer(GL_RENDERBUFFER, 0);
        } else if (d->samples > 1) {
#if !OO_MSAA_COLOR_RENDERBUFFER
            glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, record->color[i]);
            glTexImage2DMultisample(GL_TEXTURE_2D_MULTISAMPLE, (GLsizei)d->samples, GL_RGBA16F, width, height, GL_TRUE);
            glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, 0);
#endif
        } else {
            uint32_t previous = BindForUpload(false, record->color[i]);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, width, height, 0, GL_RGBA, GL_FLOAT, NULL);
            glBindTexture(GL_TEXTURE_2D, previous);
        }
    }
    if (d->depth) {
        glBindRenderbuffer(GL_RENDERBUFFER, record->depth);
        if (d->samples > 1)
            glRenderbufferStorageMultisample(GL_RENDERBUFFER, (GLsizei)d->samples, GL_DEPTH_COMPONENT32F, width, height);
        else
            glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT32F, width, height);
        glBindRenderbuffer(GL_RENDERBUFFER, 0);
    }
}

OORenderTarget OORendererBackendCreateRenderTarget(const OORenderTargetDescriptor* descriptor)
{
    GLint previousFramebuffer;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &previousFramebuffer);

    GLuint framebuffer = 0;
    glGenFramebuffers(1, &framebuffer);
    RenderTargetRecord* record = framebuffer != 0 ? TargetRecord(framebuffer, true) : NULL;
    if (record == NULL) {
        OORendererBackendWarn("OORendererCreateRenderTarget: no framebuffer name");
        return 0;
    }
    memset(record, 0, sizeof *record);
    record->used = true;
    record->descriptor = *descriptor;
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);

    bool multisample = descriptor->samples > 1;
    if (multisample && !MultisampleColorIsTexture())
        glGenRenderbuffers((GLsizei)descriptor->colorAttachments, record->color);
    else if (descriptor->colorAttachments > 0)
        glGenTextures((GLsizei)descriptor->colorAttachments, record->color);
    if (descriptor->depth)
        glGenRenderbuffers(1, &record->depth);

    for (unsigned i = 0; i < descriptor->colorAttachments && !multisample; i++) {
        uint32_t previous = BindForUpload(false, record->color[i]);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glBindTexture(GL_TEXTURE_2D, previous);
    }
    AllocateStorage(record);

    GLenum drawBuffers[kOOMaxColorAttachments];
    for (unsigned i = 0; i < descriptor->colorAttachments; i++) {
        GLenum attachment = GL_COLOR_ATTACHMENT0 + i;
        drawBuffers[i] = attachment;
        if (multisample && !MultisampleColorIsTexture())
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, attachment, GL_RENDERBUFFER, record->color[i]);
#if !OO_MSAA_COLOR_RENDERBUFFER
        else if (multisample)
            glFramebufferTexture2D(GL_FRAMEBUFFER, attachment, GL_TEXTURE_2D_MULTISAMPLE, record->color[i], 0);
#endif
        else
            glFramebufferTexture2D(GL_FRAMEBUFFER, attachment, GL_TEXTURE_2D, record->color[i], 0);
    }
    if (descriptor->depth)
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, record->depth);
    if (descriptor->colorAttachments > 0)
        glDrawBuffers((GLsizei)descriptor->colorAttachments, drawBuffers);

    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
        OORendererBackendWarn("OORendererCreateRenderTarget: framebuffer not complete");
    glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)previousFramebuffer);
    return framebuffer;
}

void OORendererBackendResizeRenderTarget(OORenderTarget target, unsigned width, unsigned height)
{
    RenderTargetRecord* record = TargetRecord(target, false);
    if (record == NULL)
        return;
    record->descriptor.width = width;
    record->descriptor.height = height;
    AllocateStorage(record);
}

uint32_t OORendererBackendRenderTargetTexture(OORenderTarget target, unsigned attachment)
{
    const RenderTargetRecord* record = TargetRecord(target, false);
    if (record == NULL || record->descriptor.samples > 1 || attachment >= record->descriptor.colorAttachments)
        return 0;
    return record->color[attachment];
}

void OORendererBackendResolveRenderTarget(OORenderTarget source, OORenderTarget destination)
{
    const RenderTargetRecord* from = TargetRecord(source, false);
    if (from == NULL)
        return;
    GLint previousRead, previousDraw;
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &previousRead);
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &previousDraw);
    GLint width = (GLint)from->descriptor.width, height = (GLint)from->descriptor.height;
    glBindFramebuffer(GL_READ_FRAMEBUFFER, source);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, destination);
    glBlitFramebuffer(0, 0, width, height, 0, 0, width, height, GL_COLOR_BUFFER_BIT, GL_NEAREST);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)previousRead);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, (GLuint)previousDraw);
}

void OORendererBackendDeleteRenderTarget(OORenderTarget target)
{
    RenderTargetRecord* record = TargetRecord(target, false);
    if (record == NULL)
        return;
    const OORenderTargetDescriptor* d = &record->descriptor;
    if (d->samples > 1 && !MultisampleColorIsTexture())
        glDeleteRenderbuffers((GLsizei)d->colorAttachments, record->color);
    else if (d->colorAttachments > 0) {
        for (unsigned i = 0; i < d->colorAttachments; i++)
            OORendererForgetTexture(record->color[i]);
        glDeleteTextures((GLsizei)d->colorAttachments, record->color);
    }
    if (d->depth)
        glDeleteRenderbuffers(1, &record->depth);
    GLuint framebuffer = target;
    glDeleteFramebuffers(1, &framebuffer);
    memset(record, 0, sizeof *record);
}
