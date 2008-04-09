/*

OOOpenGL.h

Do whatever is appropriate to get gl.h, glu.h and glext.h included.

Also declares OpenGL-related utility functions.


Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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


#if OOLITE_MAC_OS_X

// Apple OpenGL includes...
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl.h>
#include <OpenGL/glu.h>
#include <OpenGL/glext.h>

#elif OOLITE_SDL

// SDL OpenGL includes...

// prevent the including of SDL_opengl.h loading a previous version of glext.h
#define NO_SDL_GLEXT

// GL_GLEXT_PROTOTYPES must be defined for the Linux build to use shaders.
// The preprocessor if statement below is required as is, because the LINUX
// symbol is defined for both Windows and Linux builds.
#if (OOLITE_LINUX && !OOLITE_WINDOWS)
#ifndef GL_GLEXT_PROTOTYPES
#define GL_GLEXT_PROTOTYPES
#define	__DEFINED_GL_GLEXT_PROTOTYPES
#endif	// GL_GLEXT_PROTOTYPES
#endif	// OOLITE_LINUX && !OOLITE_WINDOWS

// the standard SDL_opengl.h
#include <SDL_opengl.h>

// include an up-to-date version of glext.h
#include <GL/glext.h>

#ifdef __DEFINED_GL_GLEXT_PROTOTYPES
#undef GL_GLEXT_PROTOTYPES
#undef __DEFINED_GL_GLEXT_PROTOTYPES
#endif

#else	// Not OS X or SDL

#error OOOpenGL.h: unknown target!

#endif


#define NULL_SHADER ((GLhandleARB)0)


/*	CheckOpenGLErrors()
	Check for and log OpenGL errors, and returns YES if an error occurred.
	NOTE: this is controlled by the log message class rendering.opengl.error.
		  If logging is disabled, no error checking will occur. This is done
		  because glGetError() is quite expensive, requiring a full OpenGL
		  state sync.
*/
BOOL CheckOpenGLErrors(NSString *format, ...);

/*	LogOpenGLState()
	Write a bunch of OpenGL state information to the log.
*/
void LogOpenGLState(void);


/*	GLDebugWireframeModeOn()
	GLDebugWireframeModeOff()
	Enable/disable debug wireframe mode. In debug wireframe mode, the polygon
	mode is set to GL_LINE, textures are disabled and the line size is set to
	1 pixel.
*/
void GLDebugWireframeModeOn(void);
void GLDebugWireframeModeOff(void);

/*	GLDrawBallBillboard()
	Draws a circle corresponding to a sphere of given radius at given distance.
	Assumes Z buffering will be disabled.
*/
void GLDrawBallBillboard(GLfloat radius, GLfloat step, GLfloat z_distance);

/*	GLDrawOval(), GLDrawFilledOval()
	Draw axis-alligned ellipses, as outline and fill respectively.
*/
void GLDrawOval(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat step);
void GLDrawFilledOval(GLfloat x, GLfloat y, GLfloat z, NSSize siz, GLfloat step);


/*	Texture name cache.
	
	glGenTextures() and glDeleteTextures() are expensive operations -- each
	requres a complete flush of the rendering pipeline. We work around this by
	caching texture objects.
*/
GLuint GLAllocateTextureName(void);
void GLRecycleTextureName(GLuint name, GLuint mipLevels);
