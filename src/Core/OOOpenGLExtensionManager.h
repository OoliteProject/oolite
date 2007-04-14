/*

OOOpenGLExtensionManager.h

Handles checking for and using OpenGL extensions and related information.

This is thread safe, except for initialization; that is, +sharedManager should
be called from the main thread at an early point. The OpenGL context must be
set up by then.

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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

#import "OOCocoa.h"
#import "OOOpenGL.h"


#ifndef NO_SHADERS

// Certain extensions are required for shader support.
#ifndef GL_ARB_multitexture
#warning NO_SHADERS not defined and GL_ARB_multitexture not defined.
#endif

#ifndef GL_ARB_shader_objects
#warning NO_SHADERS not defined and GL_ARB_shader_objects not defined.
#endif

#ifndef GL_ARB_shading_language_100
#warning NO_SHADERS not defined and GL_ARB_shading_language_100 not defined.
#endif

#ifndef GL_ARB_fragment_shader
#warning NO_SHADERS not defined and GL_ARB_fragment_shader not defined.
#endif

#ifndef GL_ARB_vertex_shader
#warning NO_SHADERS not defined and GL_ARB_vertex_shader not defined.
#endif

// FIXME: are these last two relevant? Aren't they for the older "assembly-style" shaders?
#ifndef GL_ARB_fragment_program
#warning NO_SHADERS not defined and GL_ARB_fragment_program not defined.
#endif

#ifndef GL_ARB_vertex_program
#warning NO_SHADERS not defined and GL_ARB_vertex_program not defined.
#endif

#endif NO_SHADERS


@interface OOOpenGLExtensionManager: NSObject
{
	NSLock					*lock;
	NSSet					*extensions;
	
	NSString				*vendor;
	NSString				*renderer;
	
	unsigned				major, minor, release;
	
#ifndef NO_SHADERS
	BOOL					testedForShaders;
	BOOL					shadersAvailable;
#endif
}

+ (id)sharedManager;

- (BOOL)haveExtension:(NSString *)extension;

- (BOOL)shadersSupported;

- (unsigned)majorVersionNumber;
- (unsigned)minorVersionNumber;
- (unsigned)releaseVersionNumber;
- (void)getVersionMajor:(unsigned *)outMajor minor:(unsigned *)outMinor release:(unsigned *)outRelease;

@end


#if OOLITE_WINDOWS && !defined(NO_SHADERS)
/*	Define the function pointers for the OpenGL extensions used in the game
	(required for Windows only)
	These are set up by -[OOOpenGLExtensionManager shadersSupported]
*/
PFNGLUSEPROGRAMOBJECTARBPROC		glUseProgramObjectARB;
PFNGLACTIVETEXTUREARBPROC			glActiveTextureARB;
PFNGLGETUNIFORMLOCATIONARBPROC		glGetUniformLocationARB;
PFNGLUNIFORM1IARBPROC				glUniform1iARB;
PFNGLUNIFORM1FARBPROC				glUniform1fARB;
PFNGLGETOBJECTPARAMETERIVARBPROC	glGetObjectParameterivARB;
PFNGLCREATESHADEROBJECTARBPROC		glCreateShaderObjectARB;
PFNGLGETINFOLOGARBPROC				glGetInfoLogARB;
PFNGLCREATEPROGRAMOBJECTARBPROC		glCreateProgramObjectARB;
PFNGLATTACHOBJECTARBPROC			glAttachObjectARB;
PFNGLDELETEOBJECTARBPROC			glDeleteObjectARB;
PFNGLLINKPROGRAMARBPROC				glLinkProgramARB;
PFNGLCOMPILESHADERARBPROC			glCompileShaderARB;
PFNGLSHADERSOURCEARBPROC			glShaderSourceARB;
#endif	// OOLITE_WINDOWS
