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

#include "OORendererBackend.h"

// OOOpenGLOnly.h keys GL_GLEXT_PROTOTYPES on OOLITE_LINUX, which comes from
// Objective-C headers this C file doesn't use.
#if !defined(_WIN32) && !defined(GL_GLEXT_PROTOTYPES)
#define GL_GLEXT_PROTOTYPES 1
#endif
#include "OOOpenGLOnly.h"

#include <math.h>
#include <stdio.h>

#ifdef _WIN32
/*  On Windows, GL functions after 1.1 are pointers that
    OOOpenGLExtensionManager loads; OOOpenGLExtensionManager.h declares them
    for Objective-C under these names.
*/
extern PFNGLACTIVETEXTUREPROC glActiveTexturePtr;
extern PFNGLCLIENTACTIVETEXTUREARBPROC glClientActiveTextureARBPtr;
extern PFNGLBINDBUFFERPROC glBindBuffer;
#define glActiveTexture glActiveTexturePtr
#define glClientActiveTexture glClientActiveTextureARBPtr
#endif

void OORendererBackendWarn(const char* message);

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
