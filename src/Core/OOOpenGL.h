/*

OOOpenGL.h

Do whatever is appropriate to get gl.h, glu.h and glext.h included.

Also declares OpenGL-related utility functions.


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


#if OOLITE_MAC_OS_X

// Apple OpenGL includes...
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl.h>
#include <OpenGL/glu.h>
#include <OpenGL/glext.h>

typedef CGLContextObj OOOpenGLContext;
#define OOOpenGLGetCurrentContext CGLGetCurrentContext
#define OOOpenGLSetCurrentContext(ctx) (CGLSetCurrentContext(ctx) == kCGLNoError)

#elif OOLITE_SDL

// SDL OpenGL includes...

// prevent the including of SDL_opengl.h loading a previous version of glext.h
#define NO_SDL_GLEXT

// the standard SDL_opengl.h
#include <SDL_opengl.h>

// include an up-to-date version of glext.h
#include <GL/glext.h>


/*	FIXME: should probably use glXCopyContext() and glXMakeCurrent() on Linux;
	there should be an equivalent for Windows. This isn't very urgent since
	Oolite doesnt' use distinct contexts, though. I can't see an obvious SDL
	version, unfortunately.
*/

typedef uintptr_t OOOpenGLContext;	// Opaque context identifier
// OOOpenGLContext OOOpenGLGetCurrentContext(void)
#define OOOpenGLGetCurrentContext() ((OOOpenGLContextID)1UL)
// BOOL OOOpenGLSetCurrentContext(OOOpenGLContext context)
#define OOOpenGLSetCurrentContext(ctx) ((ctx) == 1UL)


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
