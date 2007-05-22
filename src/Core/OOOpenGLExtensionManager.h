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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2007 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
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


#if OOLITE_WINDOWS
/*	Define the function pointers for the OpenGL extensions used in the game
	(required for Windows only).
*/
void OOBadOpenGLExtensionUsed(void) GCC_ATTR((noreturn));

#if GL_ARB_vertex_buffer_object
// Vertex Buffer Object functions
PFNGLBINDBUFFERARBPROC				glBindBufferARB;//				= (PFNGLBINDBUFFERARBPROC)OOBadOpenGLExtensionUsed;
PFNGLGENBUFFERSARBPROC				glGenBuffersARB;//				= (PFNGLGENBUFFERSARBPROC)OOBadOpenGLExtensionUsed;
PFNGLBUFFERDATAARBPROC				glBufferDataARB;//				= (PFNGLBUFFERDATAARBPROC)OOBadOpenGLExtensionUsed;
PFNGLUSEPROGRAMOBJECTARBPROC		glUseProgramObjectARB;//		
PFNGLACTIVETEXTUREARBPROC			glActiveTextureARB;//	
PFNGLGETUNIFORMLOCATIONARBPROC		glGetUniformLocationARB;//		
PFNGLUNIFORM1IARBPROC				glUniform1iARB;//		
PFNGLUNIFORM1FARBPROC				glUniform1fARB;//		
PFNGLGETOBJECTPARAMETERIVARBPROC	glGetObjectParameterivARB;//	
PFNGLCREATESHADEROBJECTARBPROC		glCreateShaderObjectARB;//		
PFNGLGETINFOLOGARBPROC				glGetInfoLogARB;//		
PFNGLCREATEPROGRAMOBJECTARBPROC		glCreateProgramObjectARB;//	
PFNGLATTACHOBJECTARBPROC			glAttachObjectARB;//	
PFNGLDELETEOBJECTARBPROC			glDeleteObjectARB;//	
PFNGLLINKPROGRAMARBPROC				glLinkProgramARB;//	
PFNGLCOMPILESHADERARBPROC			glCompileShaderARB;//	
PFNGLSHADERSOURCEARBPROC			glShaderSourceARB;//	
PFNGLUNIFORMMATRIX4FVARBPROC		glUniformMatrix4fvARB;
PFNGLUNIFORM4FVARBPROC			glUniform4fvARB;
#endif

#ifdef NO_SHADERS
// Shader functions
PFNGLUSEPROGRAMOBJECTARBPROC		glUseProgramObjectARB		= (PFNGLUSEPROGRAMOBJECTARBPROC)OOBadOpenGLExtensionUsed;
PFNGLACTIVETEXTUREARBPROC			glActiveTextureARB			= (PFNGLACTIVETEXTUREARBPROC)OOBadOpenGLExtensionUsed;
PFNGLGETUNIFORMLOCATIONARBPROC		glGetUniformLocationARB		= (PFNGLGETUNIFORMLOCATIONARBPROC)OOBadOpenGLExtensionUsed;
PFNGLUNIFORM1IARBPROC				glUniform1iARB				= (PFNGLUNIFORM1IARBPROC)OOBadOpenGLExtensionUsed;
PFNGLUNIFORM1FARBPROC				glUniform1fARB				= (PFNGLUNIFORM1FARBPROC)OOBadOpenGLExtensionUsed;
PFNGLGETOBJECTPARAMETERIVARBPROC	glGetObjectParameterivARB	= (PFNGLGETOBJECTPARAMETERIVARBPROC)OOBadOpenGLExtensionUsed;
PFNGLCREATESHADEROBJECTARBPROC		glCreateShaderObjectARB		= (PFNGLCREATESHADEROBJECTARBPROC)OOBadOpenGLExtensionUsed;
PFNGLGETINFOLOGARBPROC				glGetInfoLogARB				= (PFNGLGETINFOLOGARBPROC)OOBadOpenGLExtensionUsed;
PFNGLCREATEPROGRAMOBJECTARBPROC		glCreateProgramObjectARB	= (PFNGLCREATEPROGRAMOBJECTARBPROC)OOBadOpenGLExtensionUsed;
PFNGLATTACHOBJECTARBPROC			glAttachObjectARB			= (PFNGLATTACHOBJECTARBPROC)OOBadOpenGLExtensionUsed;
PFNGLDELETEOBJECTARBPROC			glDeleteObjectARB			= (PFNGLDELETEOBJECTARBPROC)OOBadOpenGLExtensionUsed;
PFNGLLINKPROGRAMARBPROC				glLinkProgramARB			= (PFNGLLINKPROGRAMARBPROC)OOBadOpenGLExtensionUsed;
PFNGLCOMPILESHADERARBPROC			glCompileShaderARB			= (PFNGLCOMPILESHADERARBPROC)OOBadOpenGLExtensionUsed;
PFNGLSHADERSOURCEARBPROC			glShaderSourceARB			= (PFNGLSHADERSOURCEARBPROC)OOBadOpenGLExtensionUsed;
#endif	// !defined(NO_SHADERS)

#endif	// OOLITE_WINDOWS
