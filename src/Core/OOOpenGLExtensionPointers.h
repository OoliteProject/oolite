/*

OOOpenGLExtensionPointers.h

The OpenGL feature switches (OO_SHADERS, OO_USE_VBO, OO_USE_FBO, OO_MULTITEXTURE,
OO_TEXTURE_CUBE_MAP) and, on Windows, the function pointers for the OpenGL extensions used in the
game, moved verbatim out of OOOpenGLExtensionManager.h (bead oo-9ht.120), which includes this
header back where they were. This header is plain C/C++ (no Objective-C, no Foundation), so a C++
translation unit that only calls an extension through its pointer (OOMatrix, bead oo-s37k) can
include it without the extension manager's class.


Copyright (C) 2007-2013 Jens Ayton and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#ifndef OOOPENGLEXTENSIONPOINTERS_H
#define OOOPENGLEXTENSIONPOINTERS_H

/*	The platform switch below is set by the Foundation prefix header in an Objective-C translation
	unit; a plain one sets it the same way (WIN32 is only defined on the GNUstep build), as
	OOProfilingStopwatch.h does, so both kinds see the same declarations.
*/
#if defined(WIN32) && !defined(OOLITE_WINDOWS)
#define OOLITE_WINDOWS 1
#endif

#include "OOOpenGLOnly.h"



#ifndef OO_SHADERS
#ifdef NO_SHADERS
#define	OO_SHADERS		0
#else
#define	OO_SHADERS		1
#endif
#endif


#if OO_SHADERS

// Certain extensions are required for shader support.
#ifndef GL_ARB_multitexture
#warning NO_SHADERS not defined and GL_ARB_multitexture not defined; if possible, use a newer version of glext.h.
#endif

#ifndef GL_ARB_shader_objects
#warning NO_SHADERS not defined and GL_ARB_shader_objects not defined; if possible, use a newer version of glext.h.
#endif

#ifndef GL_ARB_shading_language_100
#warning NO_SHADERS not defined and GL_ARB_shading_language_100 not defined; if possible, use a newer version of glext.h.
#endif

#ifndef GL_ARB_fragment_shader
#warning NO_SHADERS not defined and GL_ARB_fragment_shader not defined; if possible, use a newer version of glext.h.
#endif

#ifndef GL_ARB_vertex_shader
#warning NO_SHADERS not defined and GL_ARB_vertex_shader not defined; if possible, use a newer version of glext.h.
#endif

#endif //OO_SHADERS


#if GL_ARB_vertex_buffer_object
#define OO_USE_VBO				0	// Disabled due to crashes on certain systems (and limited VBO use)
#else
#define OO_USE_VBO				0
#warning Building without vertex buffer object support, are your OpenGL headers up to date?
#endif


#if GL_EXT_framebuffer_object
#define OO_USE_FBO				1
#else
#define OO_USE_FBO				0
#warning Building without frame buffer object support, are your OpenGL headers up to date?
#endif


/*	Multitexturing requires GL_ARB_multitexture, but we only have use for it
	if GL_ARB_texture_env_combine is available, and GL_ARB_texture_env_combine
	requires GL_ARB_multitexture. Both GL_ARB_multitexture and
	GL_ARB_texture_env_combine were promoted to core in OpenGL 1.3.
*/
#if GL_ARB_texture_env_combine
#define OO_MULTITEXTURE			1
#else
#warning Building without texture combiner support, are your OpenGL headers up to date?
#define OO_MULTITEXTURE			0
#endif

#if defined(GL_ARB_texture_cube_map) || defined(GL_VERSION_1_3)
#define OO_TEXTURE_CUBE_MAP		1
#else
#warning Building without cube map support, are your OpenGL headers up to date?
#define OO_TEXTURE_CUBE_MAP		0
#endif


#if OOLITE_WINDOWS
/*	Declare the function pointers for the OpenGL extensions used in the game
	(required for Windows only).
*/

#if OO_SHADERS
// Shader functions
extern PFNGLUSEPROGRAMOBJECTARBPROC			glUseProgramObjectARB;
extern PFNGLGETUNIFORMLOCATIONARBPROC			glGetUniformLocationARB;
extern PFNGLUNIFORM1IARBPROC					glUniform1iARB;
extern PFNGLUNIFORM1FARBPROC					glUniform1fARB;
extern PFNGLUNIFORMMATRIX3FVARBPROC			glUniformMatrix3fvARB;
extern PFNGLUNIFORMMATRIX4FVARBPROC			glUniformMatrix4fvARB;
extern PFNGLUNIFORM4FVARBPROC					glUniform4fvARB;
extern PFNGLGETOBJECTPARAMETERIVARBPROC		glGetObjectParameterivARB;
extern PFNGLCREATESHADEROBJECTARBPROC			glCreateShaderObjectARB;
extern PFNGLGETINFOLOGARBPROC					glGetInfoLogARB;
extern PFNGLCREATEPROGRAMOBJECTARBPROC			glCreateProgramObjectARB;
extern PFNGLATTACHOBJECTARBPROC				glAttachObjectARB;
extern PFNGLDELETEOBJECTARBPROC				glDeleteObjectARB;
extern PFNGLLINKPROGRAMARBPROC					glLinkProgramARB;
extern PFNGLCOMPILESHADERARBPROC				glCompileShaderARB;
extern PFNGLSHADERSOURCEARBPROC				glShaderSourceARB;
extern PFNGLUNIFORM2FVARBPROC					glUniform2fvARB;
extern PFNGLBINDATTRIBLOCATIONARBPROC			glBindAttribLocationARB;
extern PFNGLENABLEVERTEXATTRIBARRAYARBPROC		glEnableVertexAttribArrayARB;
extern PFNGLVERTEXATTRIBPOINTERARBPROC			glVertexAttribPointerARB;
extern PFNGLDISABLEVERTEXATTRIBARRAYARBPROC	glDisableVertexAttribArrayARB;
extern PFNGLVALIDATEPROGRAMARBPROC				glValidateProgramARB;
#endif	// OO_SHADERS


#if OO_SHADERS || OO_MULTITEXTURE
// The SDL3/SDL_opengl.h header file declares glActiveTextureARB symbols as a function, not a function pointer, which means that if we
// try to declare or set glActiveTextureARB we get compiler errors. StackOverflow AI suggests we either use GLEW or we use a declare a different
// name for the symbol. As there are currently only three symbols with this problem, I've gone for the latter approach, creating a macro
// so we can stull use glActiveTexture in the code
// -- kanthoney 2026-05-04 
#define glActiveTextureARB glActiveTextureARBPtr
extern PFNGLACTIVETEXTUREARBPROC				glActiveTextureARB;
#endif

#if OO_MULTITEXTURE
// See note for glActiveTextureARB
#define glClientActiveTextureARB glClientActiveTextureARBPtr
extern PFNGLCLIENTACTIVETEXTUREARBPROC			glClientActiveTextureARB;
#endif

#if OO_USE_VBO
extern PFNGLGENBUFFERSARBPROC					glGenBuffersARB;
extern PFNGLDELETEBUFFERSARBPROC				glDeleteBuffersARB;
extern PFNGLBINDBUFFERARBPROC					glBindBufferARB;
extern PFNGLBUFFERDATAARBPROC					glBufferDataARB;
#endif

#if OO_USE_FBO
extern PFNGLGENFRAMEBUFFERSEXTPROC				glGenFramebuffersEXT;
extern PFNGLBINDFRAMEBUFFEREXTPROC				glBindFramebufferEXT;
extern PFNGLGENRENDERBUFFERSEXTPROC			glGenRenderbuffersEXT;
extern PFNGLBINDRENDERBUFFEREXTPROC			glBindRenderbufferEXT;
extern PFNGLRENDERBUFFERSTORAGEEXTPROC			glRenderbufferStorageEXT;
extern PFNGLFRAMEBUFFERRENDERBUFFEREXTPROC		glFramebufferRenderbufferEXT;
extern PFNGLFRAMEBUFFERTEXTURE2DEXTPROC		glFramebufferTexture2DEXT;
extern PFNGLCHECKFRAMEBUFFERSTATUSEXTPROC		glCheckFramebufferStatusEXT;
extern PFNGLDELETEFRAMEBUFFERSEXTPROC			glDeleteFramebuffersEXT;
extern PFNGLDELETERENDERBUFFERSEXTPROC			glDeleteRenderbuffersEXT;
extern PFNGLGENRENDERBUFFERSPROC				glGenRenderbuffers;
extern PFNGLBINDRENDERBUFFERPROC				glBindRenderbuffer;
extern PFNGLRENDERBUFFERSTORAGEPROC			glRenderbufferStorage;
extern PFNGLGENFRAMEBUFFERSPROC				glGenFramebuffers;
extern PFNGLBINDFRAMEBUFFERPROC				glBindFramebuffer;
extern PFNGLFRAMEBUFFERRENDERBUFFERPROC		glFramebufferRenderbuffer;
extern PFNGLFRAMEBUFFERTEXTURE2DPROC			glFramebufferTexture2D;
extern PFNGLGENVERTEXARRAYSPROC				glGenVertexArrays;
extern PFNGLGENBUFFERSPROC						glGenBuffers;
extern PFNGLBINDVERTEXARRAYPROC				glBindVertexArray;
extern PFNGLBINDBUFFERPROC						glBindBuffer;
extern PFNGLBUFFERDATAPROC						glBufferData;
extern PFNGLVERTEXATTRIBPOINTERPROC			glVertexAttribPointer;
extern PFNGLENABLEVERTEXATTRIBARRAYPROC		glEnableVertexAttribArray;
extern PFNGLUSEPROGRAMPROC						glUseProgram;
extern PFNGLGETUNIFORMLOCATIONPROC				glGetUniformLocation;
extern PFNGLUNIFORM1IPROC						glUniform1i;
// See note for glActiveTextureARB
#define glActiveTexture glActiveTexturePtr
extern PFNGLACTIVETEXTUREPROC					glActiveTexture;
extern PFNGLBLENDFUNCSEPARATEPROC				glBlendFuncSeparate;
extern PFNGLUNIFORM1FPROC						glUniform1f;
extern PFNGLUNIFORM2FVPROC						glUniform2fv;
extern PFNGLDELETERENDERBUFFERSPROC			glDeleteRenderbuffers;
extern PFNGLDELETEFRAMEBUFFERSPROC				glDeleteFramebuffers;
extern PFNGLDELETEVERTEXARRAYSPROC				glDeleteVertexArrays;
extern PFNGLDELETEBUFFERSPROC					glDeleteBuffers;
extern PFNGLDRAWBUFFERSPROC					glDrawBuffers;
extern PFNGLCHECKFRAMEBUFFERSTATUSPROC			glCheckFramebufferStatus;
extern PFNGLTEXIMAGE2DMULTISAMPLEPROC				glTexImage2DMultisample;
extern PFNGLRENDERBUFFERSTORAGEMULTISAMPLEPROC		glRenderbufferStorageMultisample;
extern PFNGLBLITFRAMEBUFFERPROC					glBlitFramebuffer;
extern PFNGLCLAMPCOLORPROC						glClampColor;
#endif

#endif	// OOLITE_WINDOWS


#endif	// OOOPENGLEXTENSIONPOINTERS_H
