/*

OOOpenGLExtensionManager.h

Handles checking for and using OpenGL extensions and related information.

This is thread safe, except for initialization; that is, +sharedManager should
be called from the main thread at an early point. The OpenGL context must be
set up by then.


Copyright (C) 2007-2010 Jens Ayton and contributors

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

#import "OOCocoa.h"
#import "OOOpenGL.h"
#import "OOFunctionAttributes.h"


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
#define OO_USE_VBO		0	// Disabled due to crashes on certain systems (and limited VBO use)
#else
#define OO_USE_VBO		0
#warning Building without vertex buffer object support, are your OpenGL headers up to date?
#endif


/*	Multitexturing requires GL_ARB_multitexture, but we only have use for it
	if GL_ARB_texture_env_combine is available, and GL_ARB_texture_env_combine
	requires GL_ARB_multitexture. Both GL_ARB_multitexture and
	GL_ARB_texture_env_combine were promoted to core in OpenGL 1.3.
*/
#if GL_ARB_texture_env_combine
#define OO_MULTITEXTURE	1
#else
#warning GL_ARB_texture_env_combine is not defined; if possible, use a newer version of glext.h.
#define OO_MULTITEXTURE	0
#endif



#define OOOPENGLEXTMGR_LOCK_SET_ACCESS		(!OOLITE_MAC_OS_X)


@interface OOOpenGLExtensionManager: NSObject
{
@private
#if OOOPENGLEXTMGR_LOCK_SET_ACCESS
	NSLock					*lock;
#endif
	NSSet					*extensions;
	
	NSString				*vendor;
	NSString				*renderer;
	
	unsigned				major, minor, release;

#if OO_SHADERS
	BOOL					shadersAvailable;
#endif
#if OO_USE_VBO
	BOOL					vboSupported;
#endif
#if OO_MULTITEXTURE
	BOOL					textureCombinersSupported;
	GLint					textureUnitCount;
#endif
}

+ (id)sharedManager;

- (BOOL)haveExtension:(NSString *)extension;

- (BOOL)shadersSupported;
- (BOOL)vboSupported;			// Vertex buffer objects
- (BOOL)textureCombinersSupported;
- (OOUInteger)textureUnitCount;	// Fixed function multitexture limit, does not apply to shaders. (GL_MAX_TEXTURE_UNITS_ARB)

- (OOUInteger)majorVersionNumber;
- (OOUInteger)minorVersionNumber;
- (OOUInteger)releaseVersionNumber;
- (void)getVersionMajor:(unsigned *)outMajor minor:(unsigned *)outMinor release:(unsigned *)outRelease;

- (NSString *) vendorString;
- (NSString *) rendererString;

@end


OOINLINE BOOL OOShadersSupported(void) INLINE_PURE_FUNC;
OOINLINE BOOL OOShadersSupported(void)
{
	return [[OOOpenGLExtensionManager sharedManager] shadersSupported];
}


#if OOLITE_WINDOWS
/*	Declare the function pointers for the OpenGL extensions used in the game
	(required for Windows only).
*/

#if OO_SHADERS
// Shader functions
PFNGLUSEPROGRAMOBJECTARBPROC			glUseProgramObjectARB;
PFNGLGETUNIFORMLOCATIONARBPROC			glGetUniformLocationARB;
PFNGLUNIFORM1IARBPROC					glUniform1iARB;
PFNGLUNIFORM1FARBPROC					glUniform1fARB;
PFNGLUNIFORMMATRIX4FVARBPROC			glUniformMatrix4fvARB;
PFNGLUNIFORM4FVARBPROC					glUniform4fvARB;
PFNGLGETOBJECTPARAMETERIVARBPROC		glGetObjectParameterivARB;
PFNGLCREATESHADEROBJECTARBPROC			glCreateShaderObjectARB;
PFNGLGETINFOLOGARBPROC					glGetInfoLogARB;
PFNGLCREATEPROGRAMOBJECTARBPROC			glCreateProgramObjectARB;
PFNGLATTACHOBJECTARBPROC				glAttachObjectARB;
PFNGLDELETEOBJECTARBPROC				glDeleteObjectARB;
PFNGLLINKPROGRAMARBPROC					glLinkProgramARB;
PFNGLCOMPILESHADERARBPROC				glCompileShaderARB;
PFNGLSHADERSOURCEARBPROC				glShaderSourceARB;
PFNGLUNIFORM2FVARBPROC					glUniform2fvARB;
PFNGLBINDATTRIBLOCATIONARBPROC			glBindAttribLocationARB;
PFNGLENABLEVERTEXATTRIBARRAYARBPROC		glEnableVertexAttribArrayARB;
PFNGLVERTEXATTRIBPOINTERARBPROC			glVertexAttribPointerARB;
PFNGLDISABLEVERTEXATTRIBARRAYARBPROC	glDisableVertexAttribArrayARB;
PFNGLVALIDATEPROGRAMARBPROC				glValidateProgramARB;
#endif	// OO_SHADERS


#if OO_SHADERS || OO_MULTITEXTURE
PFNGLACTIVETEXTUREARBPROC				glActiveTextureARB;
#endif

#if OO_MULTITEXTURE
PFNGLCLIENTACTIVETEXTUREARBPROC			glClientActiveTextureARB;
#endif

#if OO_USE_VBO
PFNGLGENBUFFERSARBPROC					glGenBuffersARB;
PFNGLDELETEBUFFERSARBPROC				glDeleteBuffersARB;
PFNGLBINDBUFFERARBPROC					glBindBufferARB;
PFNGLBUFFERDATAARBPROC					glBufferDataARB;
#endif

#endif	// OOLITE_WINDOWS
