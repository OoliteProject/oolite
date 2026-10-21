/*

OOGLStateCompat.h

Drop-in replacements for the OpenGL state calls Oolite makes. Each records
the change in the renderer's state machine (OORenderStateMachine.h), so the
SDL_GPU backend can build pipelines from it, and then makes the GL call.
Values the state machine doesn't track go to GL unchanged.

Use these instead of glEnable, glDisable, glBlendFunc and the rest in all
rendering code; debug builds report GL state that changed without them.


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

#import "OOOpenGL.h"
#import "OORenderStateMachine.h"

void OOGLEnable(GLenum cap);
void OOGLDisable(GLenum cap);
void OOGLBlendFunc(GLenum src, GLenum dst);
void OOGLDepthMask(GLboolean flag);
void OOGLDepthFunc(GLenum func);
void OOGLCullFace(GLenum mode);
void OOGLFrontFace(GLenum mode);
void OOGLShadeModel(GLenum mode);
void OOGLPolygonMode(GLenum face, GLenum mode);
void OOGLScissor(GLint x, GLint y, GLsizei width, GLsizei height);
void OOGLViewport(GLint x, GLint y, GLsizei width, GLsizei height);
// glLoadMatrixf on the modelview or projection stack, recorded for draws.
void OOGLLoadModelViewMatrix(const GLfloat matrix[16]);
void OOGLLoadProjectionMatrix(const GLfloat matrix[16]);
void OOGLActiveTexture(GLenum unit);
void OOGLBindTexture(GLenum target, GLuint texture);
void OOGLDeleteTextures(GLsizei count, const GLuint* textures);
void OOGLTexEnvi(GLenum target, GLenum name, GLint value);
void OOGLTexEnvf(GLenum target, GLenum name, GLfloat value);
void OOGLTexEnvfv(GLenum target, GLenum name, const GLfloat* values);
void OOGLUseProgramObject(GLhandleARB program);
void OOGLUseProgram(GLuint program); // core GL 2.0 program names
void OOGLPushAttrib(GLbitfield mask);
void OOGLPopAttrib(void);

#ifndef NDEBUG
/*  Report state where GL differs from the renderer's copy, once per field.
    Runs at every draw when OO_VERIFY_RENDER_STATE is set.
*/
void OOGLVerifyStateMachine(void);
#endif
