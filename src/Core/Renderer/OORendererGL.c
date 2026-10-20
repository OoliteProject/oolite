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
