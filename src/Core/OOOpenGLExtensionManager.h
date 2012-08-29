/*

OOOpenGLExtensionManager.h

Handles checking for and using OpenGL extensions and related information.

This is thread safe, except for initialization; that is, +sharedManager should
be called from the main thread at an early point. The OpenGL context must be
set up by then.


Copyright (C) 2007-2012 Jens Ayton and contributors

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
#import "OOTypes.h"


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
#define OO_USE_VBO				0
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
	
	BOOL					usePointSmoothing;
	BOOL					useLineSmoothing;
	BOOL					useDustShader;
	
#if OO_SHADERS
	BOOL					shadersAvailable;
	OOShaderSetting			defaultShaderSetting;
	OOShaderSetting			maximumShaderSetting;
	GLint					textureImageUnitCount;
#endif
#if OO_USE_VBO
	BOOL					vboSupported;
#endif
#if OO_USE_FBO
	BOOL					fboSupported;
#endif
#if OO_MULTITEXTURE
	BOOL					textureCombinersSupported;
	GLint					textureUnitCount;
#endif
}

+ (OOOpenGLExtensionManager *) sharedManager;

- (void) reset;

- (BOOL)haveExtension:(NSString *)extension;

- (BOOL)shadersSupported;
- (OOShaderSetting)defaultShaderSetting;
- (OOShaderSetting)maximumShaderSetting;
- (GLint)textureImageUnitCount;			// Fragment shader sampler count limit. Does not apply to fixed function multitexturing. (GL_MAX_TEXTURE_IMAGE_UNITS_ARB)

- (BOOL)vboSupported;					// Vertex buffer objects
- (BOOL)fboSupported;					// Frame buffer objects
- (BOOL)textureCombinersSupported;
- (GLint)textureUnitCount;				// Fixed function multitexture limit, does not apply to shaders. (GL_MAX_TEXTURE_UNITS_ARB)

- (NSUInteger)majorVersionNumber;
- (NSUInteger)minorVersionNumber;
- (NSUInteger)releaseVersionNumber;
- (void)getVersionMajor:(unsigned *)outMajor minor:(unsigned *)outMinor release:(unsigned *)outRelease;
- (BOOL) versionIsAtLeastMajor:(unsigned)maj minor:(unsigned)min;

- (NSString *) vendorString;
- (NSString *) rendererString;

//	GL_POINT_SMOOTH is slow or non-functional on some GPUs.
- (BOOL) usePointSmoothing;
- (BOOL) useLineSmoothing;

// Using vertex shader for dust transformation is counterproductive on systems which run vertex shaders on the CPU.
- (BOOL) useDustShader;

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

#if OO_USE_FBO
PFNGLGENFRAMEBUFFERSEXTPROC				glGenFramebuffersEXT;
PFNGLBINDFRAMEBUFFEREXTPROC				glBindFramebufferEXT;
PFNGLGENRENDERBUFFERSEXTPROC			glGenRenderbuffersEXT;
PFNGLBINDRENDERBUFFEREXTPROC			glBindRenderbufferEXT;
PFNGLRENDERBUFFERSTORAGEEXTPROC			glRenderbufferStorageEXT;
PFNGLFRAMEBUFFERRENDERBUFFEREXTPROC		glFramebufferRenderbufferEXT;
PFNGLFRAMEBUFFERTEXTURE2DEXTPROC		glFramebufferTexture2DEXT;
PFNGLCHECKFRAMEBUFFERSTATUSEXTPROC		glCheckFramebufferStatusEXT;
PFNGLDELETEFRAMEBUFFERSEXTPROC			glDeleteFramebuffersEXT;
PFNGLDELETERENDERBUFFERSEXTPROC			glDeleteRenderbuffersEXT;
#endif

#endif	// OOLITE_WINDOWS
